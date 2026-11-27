local host={Analytics={},app={}}
_G.MerchantMasterLedgerDB={schema=1,stats={chars={}}}
local ns=host.Analytics
ns.Model={GetIndexes=function() return {RECIPE_BY_SCROLL={}} end,ItemName=function(id) return 'Item '..id end}
assert(loadfile((((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../Analytics/Store.lua")))("MerchantMaster",host)
assert(loadfile((((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../Analytics/Inventory.lua")))("MerchantMaster",host)
ns.Store.Init()
_G.CreateFrame=function() return {SetScript=function() end,RegisterEvent=function() end} end
_G.MerchantMasterAPI={API_VERSION=1}; _G.MerchantMasterDB={chars={["Alt-Realm"]={},["Normal-Horde-Alt"]={name="Alt"},["Legacy-Realm"]={bags={["Old Item"]=6}}},itemIDs={["Old Item"]=18}}
assert(loadfile((((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../Analytics/Capture.lua")) )("MerchantMaster",host)
local inv=assert(ns.Inventory)
ns.Capture._testReady=true
local assertions=0
local function check(cond,msg) assertions=assertions+1; if not cond then error("ASSERTION FAILED: "..tostring(msg),2) end end
local function eq(a,b,msg) check(a==b,(msg or "value")..": got "..tostring(a)..", expected "..tostring(b)) end
inv.RecordInTransitMail("Alt-Realm",{{itemID=17,qty=3}},0,ns.Store.Now())
local d=inv.GetItemBreakdown(17)
eq(d.inTransit,3,"pending mail count")
inv.ScanCurrentChar({char="Main-Realm",econ="Main-Realm",bags={[17]=4}})
d=inv.GetItemBreakdown(17)
eq(d.bags,4,"bag count")
eq(d.total,7,"combined count")
local rows=inv.GetAllItems()
eq(#rows,2,"flat item count includes offline alt inventory")
inv.ScanCurrentChar({char="Stale-Realm-Alt",econ="Stale-Realm",bags={},bank={[99]=2}})
local stale=ns.Store.db.inventory["Stale-Realm-Alt"]
stale.updatedAt=ns.Store.Now(); stale.bankAt=1
local staleBreakdown=inv.GetItemBreakdown(99,"Stale-Realm")
check(staleBreakdown.byChar[1].stale,"old bank snapshot stays stale after a fresh bag scan")
_G.MerchantMasterDB.chars["Stale-Realm-Alt"]={name="Alt"}
eq(inv.GetItemBreakdown(99,"Stale-Realm").byChar[1].shortName,"Alt","inventory character label uses display name")
_G.GetMoney=function() return 1000 end
local durability=50
local repairAction="none"
_G.GetInventoryItemDurability = function(slot) check(type(slot) == "number", "durability slot must be numeric"); return durability, 100 end
_G.GetRepairAllCost=function() return 200 end
_G.RepairAllItems=function(guild) if not guild and repairAction=="repair" then durability=70; _G.GetMoney=function() return 800 end end end
local composeMoney,composeCOD,composePostage=500,0,30
_G.GetSendMailMoney=nil
_G.GetSendMailCOD=nil
_G.SetSendMailMoney=function(value) composeMoney=value end
_G.SetSendMailCOD=function(value) composeCOD=value end
_G.GetSendMailPrice=function() return composePostage end
_G.SendMail=function() composeMoney,composeCOD,composePostage=0,0,0 end
_G.ATTACHMENTS_MAX_SEND=1
_G.GetSendMailItem=function() return "Item",nil,2 end
_G.GetSendMailItemLink=function() return "|Hitem:17|h" end
ns.Capture.InstallHooks()
_G.SetSendMailMoney(500); _G.SetSendMailCOD(0); _G.SendMail("Alt")
ns.Capture.OnEvent(nil,"MAIL_FAILED")
ns.Capture.OnEvent(nil,"MAIL_SEND_SUCCESS")
local failedDay=ns.Store.db.days[ns.Store.DayKey()]; local failedMailRows=failedDay and failedDay.r or {}
eq(#failedMailRows,0,"failed mail call records no accounting event")
composeMoney,composePostage=500,30
_G.SetSendMailMoney(500); _G.SetSendMailCOD(0); _G.SendMail("Alt")
ns.Capture.OnEvent(nil,"MAIL_SEND_SUCCESS")
local transit=ns.Inventory.GetItemBreakdown(17)
eq(transit.inTransit,5,"pending transfer combines across mails")
local rows=ns.Store.db.days[ns.Store.DayKey()].r
local sent,postage=false,false
for _,row in ipairs(rows) do if row.type=="MONEY_TRANSFER" and row.total==-500 then sent=true elseif row.type=="POSTAGE" and row.total==-30 then postage=true end end
check(sent and postage,"sent gold and postage only after completion")
_G.MerchantMasterDB.chars["Normal-Horde-Forever-Player"]={name="Main"}
host.app.charKey="Normal-Horde-Alt"
inv.RecordInTransitMail("Normal-Horde-Alt",{{itemID=17,qty=3}},0,ns.Store.Now(),"Another-Realm","Normal-Horde")
_G.GetInboxNumItems=function() return 1 end
_G.GetInboxItem=function(_,slot) if slot==1 then return "Item",17,nil,3 end end
_G.GetInboxItemLink=function(_,slot) if slot==1 then return "|Hitem:17|h" end end
local inbox,arrived=inv.ScanMailbox(); inv.ReceiveTransitMail("Normal-Horde-Alt",arrived)
eq(inv.GetItemBreakdown(17,"Normal-Horde").inTransit,2,"mailbox arrival decrements only received quantities")
inbox,arrived=inv.ScanMailbox(); inv.ReceiveTransitMail("Normal-Horde-Alt",arrived)
eq(inv.GetItemBreakdown(17,"Normal-Horde").inTransit,2,"repeated mailbox snapshots do not consume later mail")
_G.GetInboxHeaderInfo=function() return nil,nil,"Main","Gold transfer",500,0,30,0,false,false end
_G.GetInboxInvoiceInfo=function() return nil end
_G.GetInboxItem=function() return nil end
_G.GetMoney=function() return 1000 end
ns.Capture._preTakeMail(1)
_G.GetMoney=function() return 1500 end
ns.Capture.OnEvent(nil,"PLAYER_MONEY")
local sharedPair,incomingPair
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="MONEY_TRANSFER" and row.total==-500 then sharedPair=row.extra.pairKey elseif row.type=="MONEY_TRANSFER" and row.total==500 then incomingPair=row.extra.internal and row.extra.pairKey==sharedPair end end
check(sharedPair and incomingPair,"incoming transfer reuses outgoing pair")
host.app.charKey=nil
_G.GetMoney=function() return 1000 end
ns.Capture.OnEvent(nil,"PLAYER_MONEY")
_G.GetMoney=function() return 1000 end
ns.Capture.OnEvent(nil,"PLAYER_MONEY")
_G.GetMoney=function() return 1000 end
repairAction="none"
_G.RepairAllItems(true)
ns.Capture.OnEvent(nil,"PLAYER_MONEY")
local guildRepairs=0
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="REPAIR" then guildRepairs=guildRepairs+1 end end
check(guildRepairs==0,"guild bank repair is not charged to player")
repairAction="repair"
_G.GetMoney=function() return 1000 end
_G.RepairAllItems(false)
ns.Capture.OnEvent(nil,"PLAYER_MONEY")
repairAction="none"
local repair=false
for _,row in ipairs(rows) do if row.type=="REPAIR" and row.total==-200 then repair=true end end
check(repair,"repair records observed money decrease")
_G.GetInboxNumItems=function() return 1 end
local oldMaxAttachments=_G.ATTACHMENTS_MAX_RECEIVE
_G.ATTACHMENTS_MAX_RECEIVE=1
_G.GetInboxHeaderInfo=function() return nil,nil,"Seller-Realm","COD Item",0,250,30,1,false,false end
_G.GetInboxInvoiceInfo=function() return nil end
_G.GetInboxItem=function() return "COD Item",19,nil,2 end
_G.GetInboxItemLink=function() return "|Hitem:19|h" end
_G.GetMoney=function() return 1000 end
_G.GetItemCount=function(id) if id==19 then return 0 end return 0 end
ns.Capture._preTakeMail(1)
_G.GetMoney=function() return 750 end
_G.GetItemCount=function(id) if id==19 then return 2 end return 0 end
ns.Capture.OnEvent(nil,"PLAYER_MONEY")
local codBuy=false
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="COD_BUY" and row.itemID==19 and row.total==-250 then codBuy=true end end
check(codBuy,"COD buy confirms money and item changes")
_G.ATTACHMENTS_MAX_RECEIVE=oldMaxAttachments
_G.MerchantMasterDB.chars["Legacy-Realm"].bags={ ["Old Item"]=6 }
local old=inv.GetItemBreakdown(18)
eq(old.bags,6,"offline legacy alt quantities map to item ids")
_G.GetInboxHeaderInfo=function() return nil,nil,"Buyer-Realm","COD Payment: Item",150,0,30,0,false,false end
_G.GetInboxInvoiceInfo=function() return nil end
_G.GetInboxItem=function() return nil end
_G.GetMoney=function() return 750 end
ns.Capture._preTakeMail(1)
_G.GetMoney=function() return 900 end
ns.Capture.OnEvent(nil,"PLAYER_MONEY")
local codSell=false
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="COD_SELL" and row.total==150 then codSell=true end end
check(codSell,"COD proceeds confirm on gold receipt")
_G.GetNumTradeSlots=function() return 1 end
_G.GetTradePlayerItemInfo=function() return "Item",nil,1 end
_G.GetTradePlayerItemLink=function() return "|Hitem:21|h" end
_G.GetTradeTargetItemInfo=function() return "Item",nil,1 end
_G.GetTradeTargetItemLink=function() return "|Hitem:22|h" end
_G.GetPlayerTradeMoney=function() return 50 end
_G.GetTargetTradeMoney=function() return 0 end
_G.GetMoney=function() return 900 end
ns.Capture.OnEvent(nil,"TRADE_SHOW")
ns.Capture.OnEvent(nil,"TRADE_ACCEPT_UPDATE",1,1)
_G.GetMoney=function() return 850 end
ns.Capture.OnEvent(nil,"TRADE_CLOSED")
local tradeBuy=false
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="TRADE_BUY" and row.itemID==22 then tradeBuy=true end end
check(tradeBuy,"accepted gold-for-item trade records buy")
_G.GetPlayerTradeMoney=function() return 0 end
_G.GetTargetTradeMoney=function() return 200 end
_G.GetMoney=function() return 850 end
ns.Capture.OnEvent(nil,"TRADE_SHOW")
ns.Capture.OnEvent(nil,"TRADE_ACCEPT_UPDATE",1,1)
_G.GetMoney=function() return 1050 end
ns.Capture.OnEvent(nil,"TRADE_CLOSED")
local tradeSell=false
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="TRADE_SELL" and row.itemID==21 then tradeSell=true end end
check(tradeSell,"accepted item-for-gold trade records sale")
_G.GetPlayerTradeMoney=function() return 0 end; _G.GetTargetTradeMoney=function() return 0 end
_G.GetMoney=function() return 1000 end
ns.Capture._StageRepair(); ns.Capture.OnEvent(nil,"PLAYER_MONEY")
_G.GetMoney=function() return 1000 end
ns.Capture._StageRepair(); _G.GetMoney=function() return 900 end; ns.Capture.OnEvent(nil,"PLAYER_MONEY")
local destroyState={[31]=3,[32]=0,[33]=2,[34]=0,[35]=2,[36]=0,[23]=0,[25]=0}
_G.C_Container={GetContainerNumSlots=function(bag) if bag==0 then return 8 end return 0 end,GetContainerItemInfo=function(bag,slot) if bag~=0 then return nil end; local ids={31,32,33,34,35,36,23,25}; local id=ids[slot]; local n=destroyState[id] or 0; if n>0 then return {itemID=id,stackCount=n} end end}
_G.GetContainerNumSlots=nil
_G.GetItemCount=function(id) return destroyState[id] or 0 end
local char,econ=ns.Store.CurrentCharAndEcon()
ns.Store.AddBasis(econ,31,3,900)
ns.Capture.OnEvent(nil,"UNIT_SPELLCAST_SUCCEEDED","player","de",13262)
destroyState[31]=1; destroyState[32]=5
ns.Capture.OnEvent(nil,"BAG_UPDATE_DELAYED")
local deBrokenRow,deReceiveRow
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do
    if row.type=="DISENCHANT_BROKEN" then deBrokenRow=row
    elseif row.type=="DISENCHANT_RECEIVE" then deReceiveRow=row end
end
check(deBrokenRow and deBrokenRow.itemID==31 and deBrokenRow.qty==2 and deBrokenRow.cogs==600,
    "disenchant captures DISENCHANT_BROKEN on broken item with exact consumed basis")
check(deReceiveRow and deReceiveRow.itemID==32 and deReceiveRow.qty==5 and deReceiveRow.extra.srcItemID==31
    and deBrokenRow.extra.deGroup==deReceiveRow.extra.deGroup and select(2,ns.Store.Basis(econ,32))>0,
    "disenchant captures linked DISENCHANT_RECEIVE row with deGroup, srcItemID and mat basis")
_G.GetInboxHeaderInfo=function() return nil,nil,"Seller-Realm","Auction successful: Item",0,0,30,1,false,false end
_G.GetInboxInvoiceInfo=function() return "buyer","Item","Seller-Realm",100,100,0,0,0,0,0,1 end
_G.GetInboxItem=function() return "Item",23,nil,1 end
_G.GetInboxItemLink=function() return "|Hitem:23|h" end
_G.GetItemCount=function(id) return destroyState[id] or 0 end
_G.ATTACHMENTS_MAX_RECEIVE=1
_G.GetInboxNumItems=function() return 1 end
_G.GetMoney=function() return 1000 end
local liveBuyerRow=ns.Store.Append({type="AH_BUY",itemID=23,qty=1,unit=100,total=-100,time=ns.Store.Now(),where="Auction House",extra={}})
local recordedBeforeInvoice=ns.Store.db.stats.recon[liveBuyerRow.char].recorded
ns.Capture._preTakeMail(1)
destroyState[23]=1; ns.Capture.OnEvent(nil,"BAG_UPDATE_DELAYED")
local buyerOne=false
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="AH_BUY" and row.itemID==23 and row.extra.seller=="Seller-Realm" and row.total==-100 then buyerOne=true end end
check(buyerOne,"buyer invoice enriches matching live purchase with seller")
local item23Buys=0; for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="AH_BUY" and row.itemID==23 then item23Buys=item23Buys+1 end end
check(item23Buys==1 and ns.Store.db.stats.recon[liveBuyerRow.char].recorded==recordedBeforeInvoice,"buyer invoice does not double count live cash or basis")
_G.GetInboxInvoiceInfo=function() return "buyer","Item","Seller-Two",200,200,0,0,0,0,0,1 end
_G.GetInboxHeaderInfo=function() return nil,nil,"Seller-Two","Auction successful: Item",0,0,30,1,false,false end
ns.Capture._preTakeMail(1)
destroyState[23]=2; ns.Capture.OnEvent(nil,"BAG_UPDATE_DELAYED")
local sellerTwo=false
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="AH_BUY" and row.itemID==23 and row.extra.seller=="Seller-Two" and row.total==-200 then sellerTwo=true end end
check(sellerTwo,"separate invoice retains its seller and amount")
local char,econ=ns.Store.CurrentCharAndEcon()
ns.Store.PostLot(char,econ,24,1,50,0,ns.Store.Now(),"Item")
_G.GetInboxInvoiceInfo=function() return nil end
_G.GetInboxHeaderInfo=function() return nil,nil,"Auction House","Auction cancelled: Item",0,0,30,1,false,false end
_G.GetInboxItem=function() return "Item",24,nil,1 end
_G.GetInboxItemLink=function() return "|Hitem:24|h" end
ns.Capture._preTakeMail(1)
local cancelFallback=false
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="AH_CANCEL" and row.itemID==24 and row.extra.mailFallback then cancelFallback=true end end
check(cancelFallback,"cancelled AH return mail closes an open lot")
_G.GetMoney=function() return 1000 end
ns.Capture.OnEvent(nil,"PLAYER_MONEY")
_G.GetRepairAllCost=function() return 100 end
ns.Capture._StageRepair()
_G.GetMoney=function() return 900 end
ns.Capture.OnEvent(nil,"PLAYER_MONEY")
local repairCount=0
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="REPAIR" then repairCount=repairCount+1 end end
check(repairCount==1,"unrelated gold loss without durability change is not repair")
_G.GetMoney=function() return 1050 end
ns.Capture.OnEvent(nil,"PLAYER_MONEY")
destroyState[25]=0
_G.GetItemCount=function(id) return destroyState[id] or 0 end
_G.GetBuybackItemInfo=function() return "Buyback",nil,100,1 end
_G.GetBuybackItemLink=function() return "|Hitem:25|h" end
_G.BuybackItem=function() _G.GetMoney=function() return 950 end; destroyState[25]=1 end
ns.Capture.InstallHooks()
_G.BuybackItem(1)
ns.Capture.OnEvent(nil,"PLAYER_MONEY")
local buyback=false
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="VENDOR_BUYBACK" and row.itemID==25 and row.total==-100 then buyback=true end end
check(buyback,"buyback confirms gold drop and bag gain")
ns.Store.AddBasis(econ,33,2,600)
ns.Capture.OnEvent(nil,"UNIT_SPELLCAST_SUCCEEDED","player","mill",51005)
destroyState[33]=1; destroyState[34]=4
ns.Capture.OnEvent(nil,"BAG_UPDATE_DELAYED")
local mill=false
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="DESTROY" and row.extra.spellID==51005 and row.cogs==300 then mill=true end end
check(mill,"milling carries input basis to outputs")
ns.Store.AddBasis(econ,35,2,400)
ns.Capture.OnEvent(nil,"UNIT_SPELLCAST_SUCCEEDED","player","prospect",31252)
destroyState[35]=1; destroyState[36]=2
ns.Capture.OnEvent(nil,"BAG_UPDATE_DELAYED")
local prospect=false
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="DESTROY" and row.extra.spellID==31252 and row.cogs==200 then prospect=true end end
check(prospect,"prospecting carries input basis to outputs")
local tradesBefore=0
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="TRADE_BUY" or row.type=="TRADE_SELL" then tradesBefore=tradesBefore+1 end end
_G.ERR_TRADE_CANCELLED="trade cancelled"
_G.GetMoney=function() return 1000 end
ns.Capture.OnEvent(nil,"TRADE_SHOW")
ns.Capture.OnEvent(nil,"TRADE_ACCEPT_UPDATE",1,1)
ns.Capture.OnEvent(nil,"UI_INFO_MESSAGE",0,"trade cancelled")
_G.GetMoney=function() return 900 end
ns.Capture.OnEvent(nil,"TRADE_CLOSED")
local tradesAfter=0
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="TRADE_BUY" or row.type=="TRADE_SELL" then tradesAfter=tradesAfter+1 end end
check(tradesBefore==tradesAfter,"cancelled trade records no transactions")
local tradeStart=#ns.Store.db.days[ns.Store.DayKey()].r
_G.GetNumTradeSlots=function() return 2 end
_G.GetTradeTargetItemLink=function(slot) return slot==1 and "|Hitem:22|h" or "|Hitem:26|h" end
_G.GetTradeTargetItemInfo=function() return "Item",nil,1 end
_G.GetPlayerTradeMoney=function() return 101 end
_G.GetTargetTradeMoney=function() return 0 end
_G.GetMoney=function() return 900 end
ns.Capture.OnEvent(nil,"TRADE_SHOW")
ns.Capture.OnEvent(nil,"TRADE_ACCEPT_UPDATE",1,1)
_G.GetMoney=function() return 799 end
ns.Capture.OnEvent(nil,"TRADE_CLOSED")
local allocated=0
for i=tradeStart+1,#ns.Store.db.days[ns.Store.DayKey()].r do local row=ns.Store.db.days[ns.Store.DayKey()].r[i]; if row.type=="TRADE_BUY" then allocated=allocated-row.total end end
check(allocated==101,"multi-item trade allocation preserves every copper")
local secretTable={}
setmetatable(secretTable,{__index=function() error("secret table indexed") end})
_G.issecrettable=function(value) return value==secretTable end
_G.issecretvalue=nil
_G.C_CraftingOrders=secretTable
local safeCaps=ns.Capture.GetCapabilities()
check(not safeCaps.craftingOrders,"secret client tables are reported unavailable")
_G.BuyMerchantItem=function() end
_G.GetMerchantItemInfo=function() return 'Item',nil,0,1,nil,nil,nil,true end
_G.GetMerchantItemLink=function() return '|Hitem:25|h' end
_G.GetMerchantItemCostInfo=function() return 1 end
_G.GetMerchantItemCostItem=function() return nil,10,'|Hcurrency:3402|h','Favor',3402 end
_G.C_CurrencyInfo={GetCurrencyInfo=function() return secretTable end}
ns.Capture.InstallHooks()
local favorErrors=ns.Store.db.stats.errors.VENDOR_BUY or 0
BuyMerchantItem(1,1)
check((ns.Store.db.stats.errors.VENDOR_BUY or 0)==favorErrors,'secret currency table never indexed or counted as capture error')
_G.C_CurrencyInfo=nil
_G.issecrettable=nil; _G.C_CraftingOrders=nil
local guild=inv.CaptureGuildSnapshot("Guild", "Main-Realm", {{[17]=4}}, 1200)
local guildBreakdown=inv.GetItemBreakdown(17,"Main-Realm")
eq(guildBreakdown.guild,4,"guild bank quantities appear in breakdown")
eq(guildBreakdown.guildUpdatedAt,guild.updatedAt,"guild snapshot freshness is exposed")
ns.Store.readOnly=true
eq(inv.RecordInTransitMail("Other-Realm",{{itemID=17,qty=1}}),nil,"read-only mode blocks inventory writes")
ns.Store.readOnly=nil
local caps=ns.Capture.GetCapabilities()
check(type(caps.craftingOrders)=="boolean" and type(caps.guildBank)=="boolean")
-- Review regressions run independently so every missing behavior is visible on red.
local regressionFailures={}
local function regression(name,fn)
    local ok,err=pcall(fn)
    if not ok then regressionFailures[#regressionFailures+1]=name..": "..tostring(err); print("RED "..name..": "..tostring(err)) end
end
regression("durability takes one numeric slot",function()
    local original=_G.GetInventoryItemDurability
    _G.GetInventoryItemDurability=function(slot,...)
        assert(type(slot)=="number" and select("#",...)==0,"durability API expects one numeric slot")
        return 70,100
    end
    local ok,err=pcall(ns.Capture.OnEvent,nil,"PLAYER_LOGIN")
    _G.GetInventoryItemDurability=original
    check(ok,"strict durability login: "..tostring(err))
end)
regression("bank containers and bound counts",function()
    _G.Enum={BagIndex={Bank=-5}}
    _G.NUM_BAG_SLOTS=4; _G.NUM_BANKBAGSLOTS=2
    local visited={}
    _G.C_Container={GetContainerNumSlots=function(bag) visited[bag]=(visited[bag] or 0)+1; return 1 end,
        GetContainerItemInfo=function(bag) if bag==-1 then return {itemID=71,stackCount=2} elseif bag==-5 then return {itemID=72,stackCount=3} elseif bag==5 then return {itemID=71,stackCount=4} elseif bag==6 then return {itemID=73,stackCount=1} end end}
    _G.C_Item={ItemLocation={CreateFromBagAndSlot=function(bag,slot) return {bag=bag,slot=slot} end},IsBound=function(loc) return loc.bag==-1 or loc.bag==5 end}
    local bank=inv.ScanBank()
    eq(bank.bank[71],6,"main bank and bag quantities merged")
    eq(bank.bank[72],3,"distinct enum bank included")
    eq(bank.bank[73],1,"last supported bank bag included")
    eq(bank.boundBank[71],6,"bound main bank and bag counts merged")
    check(not visited[7],"unsupported extra bank bag not scanned")
    _G.Enum.BagIndex.Bank=-1
    bank=inv.ScanBank(); eq(bank.bank[71],6,"duplicate enum bank is scanned once")
    _G.C_Item=nil; _G.Enum=nil
end)
regression("external COD attachment allocation",function()
    local seller,economy=ns.Store.CurrentCharAndEcon()
    _G.GetMoney=function() return 2000 end
    _G.ATTACHMENTS_MAX_SEND=2
    _G.GetSendMailItem=function(slot) return "Item",nil,slot==1 and 2 or 1 end
    _G.GetSendMailItemLink=function(slot) return slot==1 and "|Hitem:81|h" or "|Hitem:82|h" end
    _G.GetSendMailPrice=function() return 0 end
    ns.Store.AddBasis(economy,81,2,200); ns.Store.AddBasis(economy,82,1,300)
    _G.SetSendMailMoney(0); _G.SetSendMailCOD(101); _G.SendMail("OutsideBuyer-Realm")
    ns.Capture.OnEvent(nil,"MAIL_SEND_SUCCESS")
    local expectation=ns.Store.db.stats.codExpectations[#ns.Store.db.stats.codExpectations]
    eq(expectation.sellerChar,seller,"COD owned by current seller")
    eq(expectation.recipient,"outsidebuyer-realm","external COD recipient normalized")
    local start=#ns.Store.db.days[ns.Store.DayKey()].r
    _G.GetInboxNumItems=function() return 1 end
    _G.GetInboxHeaderInfo=function() return nil,nil,"OutsideBuyer-Realm","COD Payment: Items",101,0,30,0,false,false end
    _G.GetInboxInvoiceInfo=function() return nil end; _G.GetInboxItem=function() return nil end
    _G.GetInboxItemLink=function() return nil end
    ns.Capture._preTakeMail(1)
    _G.GetMoney=function() return 2101 end; ns.Capture.OnEvent(nil,"PLAYER_MONEY")
    local total,count,cogs=0,0,0
    local proceeds={}
    for i=start+1,#ns.Store.db.days[ns.Store.DayKey()].r do local row=ns.Store.db.days[ns.Store.DayKey()].r[i]; if row.type=="COD_SELL" then total=total+row.total; count=count+1; cogs=cogs+row.cogs; proceeds[row.itemID]=row.total end end
    eq(total,101,"COD allocations preserve every copper"); eq(count,2,"both COD attachments retain identity"); eq(cogs,500,"both COD attachment bases consumed")
    eq(proceeds[81],67,"COD first attachment quantity share"); eq(proceeds[82],34,"COD final attachment gets copper residual")
    eq(ns.Store.Basis(economy,81),0,"first attachment basis exhausted"); eq(ns.Store.Basis(economy,82),0,"second attachment basis exhausted")
    ns.Capture.OnEvent(nil,"PLAYER_MONEY")
    eq(#ns.Store.db.days[ns.Store.DayKey()].r,start+2,"COD payment confirmed once")
end)
regression("failed cash collection and retry",function()
    local mailCash=95
    _G.GetMoney=function() return 3000 end
    _G.GetInboxNumItems=function() return 1 end
    _G.GetInboxHeaderInfo=function() return nil,nil,"Auction House","Auction successful: Item",mailCash,0,30,0,false,false end
    _G.GetInboxInvoiceInfo=function() return "seller","Item 91","CashBuyer",100,100,0,5,0,0,0,1 end
    _G.GetInboxItem=function() return nil end; _G.GetInboxItemLink=function() return nil end
    _G.TakeInboxMoney=function() end
    ns.Capture.InstallHooks(); ns.Capture.OnEvent(nil,"MAIL_SHOW")
    local char=ns.Store.CurrentCharAndEcon(); ns.Store.ReconcileGold(char,3000,"Regression baseline")
    local start=#ns.Store.db.days[ns.Store.DayKey()].r
    _G.TakeInboxMoney(1); ns.Capture.OnEvent(nil,"MAIL_INBOX_UPDATE")
    ns.Capture.OnEvent(nil,"PLAYER_MONEY")
    ns.Store.ReconcileGold(char,3000,"Failed collection")
    eq(#ns.Store.db.days[ns.Store.DayKey()].r,start,"failed take posts no cash or reconciliation adjustment")
    _G.TakeInboxMoney(1); mailCash=0; _G.GetMoney=function() return 3095 end
    ns.Capture.OnEvent(nil,"PLAYER_MONEY"); ns.Capture.OnEvent(nil,"MAIL_INBOX_UPDATE")
    ns.Store.ReconcileGold(char,3095,"Successful retry")
    eq(#ns.Store.db.days[ns.Store.DayKey()].r,start+1,"retry posts cash once without reconciliation adjustment")
    eq(ns.Store.db.days[ns.Store.DayKey()].r[start+1].total,95,"retry cash amount")
    _G.GetMoney=function() return 3190 end; ns.Capture.OnEvent(nil,"PLAYER_MONEY")
    eq(#ns.Store.db.days[ns.Store.DayKey()].r,start+1,"failed retry attempt leaves no duplicate pending cash")
end)
regression("buyback caches disappearing inputs",function()
    local char=ns.Store.CurrentCharAndEcon()
    _G.GetMoney=function() return 4000 end; ns.Capture.OnEvent(nil,"PLAYER_MONEY")
    local count=0
    _G.GetItemCount=function(id) return id==92 and count or 0 end
    _G.C_Container={GetContainerNumSlots=function() return 0 end}; ns.Inventory.ScanCurrentChar()
    _G.GetNumBuybackItems=function() return 1 end
    _G.GetBuybackItemInfo=function() if count==0 then return "Buyback",nil,101,1 end end
    _G.GetBuybackItemLink=function() if count==0 then return "|Hitem:92|h" end end
    _G.BuybackItem=function() count=1; _G.GetMoney=function() return 3899 end end
    ns.Capture.InstallHooks(); ns.Capture.OnEvent(nil,"MERCHANT_SHOW")
    local start=#ns.Store.db.days[ns.Store.DayKey()].r
    _G.BuybackItem(1); ns.Capture.OnEvent(nil,"PLAYER_MONEY")
    eq(#ns.Store.db.days[ns.Store.DayKey()].r,start+1,"buyback confirms cached item after slot disappears")
    eq(ns.Store.db.days[ns.Store.DayKey()].r[start+1].itemID,92,"buyback preserves pre-call item")
end)
regression("secure repair and buyback hooks",function()
    local registered={}
    _G.hooksecurefunc=function(owner,key,callback) registered[type(owner)=="string" and owner or key]=true end
    _G.RepairAllItems=function() end; _G.BuybackItem=function() end; _G.PickupInventoryItem=function() end
    local repair,buyback,pickup=_G.RepairAllItems,_G.BuybackItem,_G.PickupInventoryItem
    ns.Capture.InstallHooks()
    check(registered.RepairAllItems and registered.BuybackItem and registered.PickupInventoryItem,"repair and buyback use secure hooks")
    check(_G.RepairAllItems==repair and _G.BuybackItem==buyback and _G.PickupInventoryItem==pickup,"secure hook installation does not assign API globals")
    _G.hooksecurefunc=nil
end)
regression("failed invoice cannot consume another receipt",function()
    local cash=5000
    local inboxCash={100,200}
    _G.GetMoney=function() return cash end
    _G.GetInboxNumItems=function() return 2 end
    _G.GetInboxHeaderInfo=function(i) return nil,nil,"Auction House","Auction successful: Review"..i,inboxCash[i],0,30,0,false,false end
    _G.GetInboxInvoiceInfo=function(i) return "seller","Review item "..i,"ReviewBuyer",i==1 and 100 or 200,i==1 and 100 or 200,0,0,0,0,0,1 end
    _G.GetInboxItem=function() return nil end; _G.GetInboxItemLink=function() return nil end
    ns.Capture.OnEvent(nil,"MAIL_SHOW")
    local start=#ns.Store.db.days[ns.Store.DayKey()].r
    ns.Capture._preTakeMail(1); ns.Capture.OnEvent(nil,"MAIL_INBOX_UPDATE")
    cash=5100; ns.Capture.OnEvent(nil,"PLAYER_MONEY")
    eq(#ns.Store.db.days[ns.Store.DayKey()].r,start,"unrelated gold cannot confirm unchanged failed invoice")
    ns.Capture._preTakeMail(2); inboxCash[2]=0; cash=5300
    ns.Capture.OnEvent(nil,"PLAYER_MONEY")
    eq(#ns.Store.db.days[ns.Store.DayKey()].r,start+1,"distinct successful invoice bypasses failed invoice")
    local row=ns.Store.db.days[ns.Store.DayKey()].r[start+1]
    eq(row.total,200,"correct successful invoice cash")
    eq(row.extra.name,"Review item 2","correct successful invoice identity")
end)
if #regressionFailures>0 then error(table.concat(regressionFailures,"\n")) end
local transferRowsBefore=0
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="MONEY_TRANSFER" and row.total==-500 then transferRowsBefore=transferRowsBefore+1 end end
host.app.charKey="Normal-Horde-Forever-Player"
_G.SetSendMailMoney(500); _G.SetSendMailCOD(0); _G.SendMail("Alt")
assert(loadfile((((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../Analytics/Capture.lua")))("MerchantMaster",host)
local freshCapture=ns.Capture; freshCapture._testReady=true; freshCapture.InstallHooks()
freshCapture.OnEvent(nil,"MAIL_SEND_SUCCESS")
local afterOldSuccess=0
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="MONEY_TRANSFER" and row.total==-500 then afterOldSuccess=afterOldSuccess+1 end end
check(afterOldSuccess==transferRowsBefore,"module reload clears staged send and updates hook callback")
_G.SetSendMailMoney(500); _G.SetSendMailCOD(0); _G.SendMail("Alt")
freshCapture.OnEvent(nil,"MAIL_SEND_SUCCESS")
local afterFreshSuccess=0
for _,row in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do if row.type=="MONEY_TRANSFER" and row.total==-500 then afterFreshSuccess=afterFreshSuccess+1 end end
check(afterFreshSuccess==transferRowsBefore+1,"reloaded capture records a new completed send once")
print(string.format("Accounting capture suite: %d assertions, 0 failures",assertions))










































-- Quantity equality cannot suppress a freshness change, and exact repeats stay cheap.
do
    local oldTime=_G.time; local clock=1794484800; _G.time=function() return clock end
    local snapshot={items={[901001]=2}}
    inv.AcceptMailboxSnapshot(snapshot); local before=inv.version
    inv.AcceptMailboxSnapshot(snapshot)
    eq(inv.version,before,"same quantities and freshness preserve inventory generation")
    clock=clock+1; inv.AcceptMailboxSnapshot(snapshot)
    check(inv.version>before,"equal quantities with fresh observation advance inventory generation")
    _G.time=oldTime
end
-- Every declared attachment must load before an ownership snapshot can replace totals.
do
    local attachments={[2]={"Second",902002,nil,4},[3]={"Third",902003,nil,5}}
    _G.GetInboxNumItems=function() return 1,1 end
    _G.GetInboxHeaderInfo=function() return nil,nil,"Sender","Sparse attachments",0,0,30,2,false,false end
    _G.GetInboxInvoiceInfo=function() end
    _G.ATTACHMENTS_MAX_RECEIVE=3
    _G.GetInboxItem=function(_,slot) local a=attachments[slot]; if a then return unpack(a) end end
    _G.GetInboxItemLink=function(_,slot) local a=attachments[slot]; return a and ("|Hitem:"..a[2].."|h") end
    local sparse=ns.Capture.ScanMailboxSnapshot()
    check(sparse and sparse.items[902002]==4 and sparse.items[902003]==5,"sparse attachment slots are all scanned")
    attachments={[1]={"First",902001,nil,2},[2]={"Second",902002,nil,4}}
    _G.GetInboxHeaderInfo=function() return nil,nil,"Sender","Boolean attachment flag",0,0,30,true,false,false end
    local booleanFlag=ns.Capture.ScanMailboxSnapshot()
    check(booleanFlag and booleanFlag.items[902001]==2 and booleanFlag.items[902002]==4,"boolean has-item flag permits multiple loaded attachments")
    attachments={[1]={"First",902001,nil,2}}
    _G.GetInboxHeaderInfo=function() return nil,nil,"Sender","Incomplete attachments",0,0,30,2,false,false end
    _G.GetInboxItem=function(_,slot) local a=attachments[slot]; if a then return unpack(a) end end
    _G.GetInboxItemLink=function(_,slot) local a=attachments[slot]; return a and ("|Hitem:"..a[2].."|h") end
    local incomplete=ns.Capture.ScanMailboxSnapshot()
    check(incomplete==nil,"missing declared attachment rejects entire snapshot")
end
-- Random-enchant queuePost + OWNED_AUCTIONS_UPDATED + mail sale without TSM, plus exact base item with "of".
do
    local oldTSM=_G.TradeSkillMasterDB; _G.TradeSkillMasterDB=nil
    local oldAH=_G.C_AuctionHouse
    local oldContainer=_G.C_Container
    local oldGetItemInfo=_G.GetItemInfo
    local oldCItem=_G.C_Item
    local oldItemIDsByName=host.ITEM_IDS_BY_NAME
    local oldModelItemName=ns.Model.ItemName
    local oldCharKey=host.app.charKey
    local oldMoney=_G.GetMoney
    local oldInboxNum=_G.GetInboxNumItems
    local oldInboxHeader=_G.GetInboxHeaderInfo
    local oldInboxInvoice=_G.GetInboxInvoiceInfo
    local oldInboxItem=_G.GetInboxItem
    local oldInboxLink=_G.GetInboxItemLink

    host.app.charKey="Normal-Horde-Forever-Player"
    host.ITEM_IDS_BY_NAME={ ["Green Lens"]=10504, ["Flask of Supreme Power"]=13512, ["Flask"]=99999 }
    ns.Model.ItemName=function(id)
        if id==10504 then return "Green Lens" end
        if id==13512 then return "Flask of Supreme Power" end
        if id==77777 then return "Wand of Eventide" end
        return "Item "..tostring(id)
    end

    local eagleLink="|cff1eff00|Hitem:10504::::::::60:::::::|h[Green Lens of the Eagle]|h|r"
    local owlLink="|cff1eff00|Hitem:10504::::::::60:::::::|h[Green Lens of the Owl]|h|r"
    local wandLink="|cff1eff00|Hitem:77777::::::::60:::::::|h[Wand of Eventide of the Eagle]|h|r"
    _G.C_Item=nil
    _G.C_Container={
        GetContainerItemInfo=function(b,s)
            if b==0 and s==1 then return {itemID=10504,stackCount=1,hyperlink=eagleLink} end
            if b==0 and s==2 then return {itemID=77777,stackCount=1,hyperlink=wandLink} end
        end,
        GetContainerItemLink=function(b,s)
            if b==0 and s==1 then return eagleLink end
            if b==0 and s==2 then return wandLink end
        end,
    }
    -- Intentionally return base name from GetItemInfo to verify linkName prefers exact bracketed hyperlink name first!
    _G.GetItemInfo=function(q)
        if q==eagleLink then return "Green Lens" end
        if q==owlLink then return "Green Lens" end
        if q==wandLink then return "Wand of Eventide" end
    end

    local cash=100000
    _G.GetMoney=function() return cash end
    local owned={
        { auctionID=8801, itemID=10504, itemLink=owlLink, quantity=1, status=0 },
    }
    _G.C_AuctionHouse={
        PostItem=function() end,
        PostCommodity=function() end,
        ConfirmPostItem=function() end,
        ConfirmPostCommodity=function() end,
        CancelAuction=function() end,
        CalculateItemDeposit=function() return 150 end,
        GetNumOwnedAuctions=function() return #owned end,
        GetOwnedAuctionInfo=function(i) return owned[i] end,
    }

    local cap=ns.Capture
    cap._testReady=true
    cap.InstallHooks()

    -- 1. Post "Green Lens of the Eagle" via queuePost (PostItem hook) and confirm creation
    local startRows=#ns.Store.db.days[ns.Store.DayKey()].r
    _G.C_AuctionHouse.PostItem({bagID=0,slotIndex=1},2,1,17000,17000)
    cash=cash-150
    cap.OnEvent(nil,"AUCTION_HOUSE_AUCTION_CREATED",8802)
    local postRow=ns.Store.db.days[ns.Store.DayKey()].r[startRows+1]
    check(postRow and postRow.type=="AH_POST" and postRow.itemID==10504,"Green Lens of the Eagle post stores base itemID 10504")
    eq(postRow.extra.name,"Green Lens of the Eagle","AH_POST preserves suffixed full name")
    eq(postRow.extra.variant,"Green Lens of the Eagle","AH_POST records variant full name")
    local lots=ns.Store.Lots("Normal-Horde-Forever-Player",10504)
    check(lots and #lots>=1 and lots[#lots].name=="Green Lens of the Eagle","open lot keeps full suffixed name")

    -- 2. OWNED_AUCTIONS_UPDATED indexes suffixed owned auction name into fast lookup map
    cap.OnEvent(nil,"OWNED_AUCTIONS_UPDATED")
    eq(ns.Store.ResolveItemIDByName("Normal-Horde-Forever-Player","Green Lens of the Owl"),10504,"OWNED_AUCTIONS_UPDATED indexes suffixed name -> 10504")

    -- 3. Sell "Green Lens of the Eagle" via GetInboxInvoiceInfo with TSM completely unloaded
    local inboxCash={16300, 650000}
    _G.GetInboxNumItems=function() return 2 end
    _G.GetInboxHeaderInfo=function(i)
        if i==1 then return nil,nil,"Auction House","Auction successful: Green Lens of the Eagle",inboxCash[1],0,30,0,false,false end
        return nil,nil,"Auction House","Auction successful: Flask of Supreme Power",inboxCash[2],0,30,0,false,false
    end
    _G.GetInboxInvoiceInfo=function(i)
        if i==1 then return "seller","Green Lens of the Eagle","LensBuyer",17000,17000,150,850,0,0,0,1 end
        return "seller","Flask of Supreme Power","RaidBuyer",680000,680000,0,30000,0,0,0,1
    end
    _G.GetInboxItem=function() return nil end
    _G.GetInboxItemLink=function() return nil end

    cap.OnEvent(nil,"MAIL_SHOW")
    local beforeSell=#ns.Store.db.days[ns.Store.DayKey()].r
    cap._preTakeMail(1); inboxCash[1]=0; cash=cash+16300
    cap.OnEvent(nil,"PLAYER_MONEY")
    local sellLens=ns.Store.db.days[ns.Store.DayKey()].r[beforeSell+1]
    check(sellLens and sellLens.type=="AH_SELL","Green Lens of the Eagle mail invoice recorded as AH_SELL")
    eq(sellLens.itemID,10504,"Green Lens of the Eagle resolves to itemID 10504 without TSM")
    eq(sellLens.extra.name,"Green Lens of the Eagle","AH_SELL keeps full suffixed name")
    eq(sellLens.extra.variant,"Green Lens of the Eagle","AH_SELL records random-enchant variant")

    -- 4. Sell "Flask of Supreme Power" (contains "of" in base name) -> resolves to 13512 via exact match
    cap._preTakeMail(2); inboxCash[2]=0; cash=cash+650000
    cap.OnEvent(nil,"PLAYER_MONEY")
    local sellFlask=ns.Store.db.days[ns.Store.DayKey()].r[beforeSell+2]
    check(sellFlask and sellFlask.type=="AH_SELL","Flask of Supreme Power mail invoice recorded as AH_SELL")
    eq(sellFlask.itemID,13512,"Flask of Supreme Power resolves to exact itemID 13512 without false suffix stripping")

    -- 5. Non-recipe multi-"of" BoE: post "Wand of Eventide of the Eagle" -> baseName persisted on lot -> sibling "Wand of Eventide of the Owl" resolves even after /reload!
    _G.C_AuctionHouse.PostItem({bagID=0,slotIndex=2},2,1,25000,25000)
    cash=cash-150
    cap.OnEvent(nil,"AUCTION_HOUSE_AUCTION_CREATED",8803)
    local wandLots=ns.Store.Lots("Normal-Horde-Forever-Player",77777)
    check(wandLots and #wandLots>=1 and wandLots[#wandLots].baseName=="Wand of Eventide","variant AH_POST persists baseName on open lot")
    eq(ns.Store.ResolveItemIDByName("Normal-Horde-Forever-Player","Wand of Eventide of the Owl"),77777,"queuePost indexes baseName so sibling multi-of BoE suffix resolves without TSM")
    ns.Store.Init()
    eq(ns.Store.ResolveItemIDByName("Normal-Horde-Forever-Player","Wand of Eventide of the Owl"),77777,"sibling multi-of BoE resolves from persisted lot.baseName after reload")

    -- 6. Secret numeric itemID passed to Capture.ResolveItemID must return nil (never bypass hasSecret)
    local oldIsSecret=_G.issecretvalue
    _G.issecretvalue=function(v) return v==10504 end
    eq(cap.ResolveItemID(host,_G.MerchantMasterDB,10504),nil,"Capture.ResolveItemID blocks secret numeric itemID before type(name)==number")
    _G.issecretvalue=oldIsSecret

    _G.TradeSkillMasterDB=oldTSM
    _G.C_AuctionHouse=oldAH
    _G.C_Container=oldContainer
    _G.GetItemInfo=oldGetItemInfo
    _G.C_Item=oldCItem
    host.ITEM_IDS_BY_NAME=oldItemIDsByName
    ns.Model.ItemName=oldModelItemName
    host.app.charKey=oldCharKey
    _G.GetMoney=oldMoney
    _G.GetInboxNumItems=oldInboxNum
    _G.GetInboxHeaderInfo=oldInboxHeader
    _G.GetInboxInvoiceInfo=oldInboxInvoice
    _G.GetInboxItem=oldInboxItem
    _G.GetInboxItemLink=oldInboxLink
end
-- Live WoW player-to-player trade capture regressions (single-side accept, >30s open, close before UI_INFO_MESSAGE, multi-slot/multi-item, mixed tip, cancel)
do
    local oldLedger=_G.MerchantMasterLedgerDB
    local oldTime=_G.time
    local oldMoney=_G.GetMoney
    local oldItemCount=_G.GetItemCount
    local oldNumTrade=_G.GetNumTradeSlots
    local oldPInfo=_G.GetTradePlayerItemInfo
    local oldPLink=_G.GetTradePlayerItemLink
    local oldTInfo=_G.GetTradeTargetItemInfo
    local oldTLink=_G.GetTradeTargetItemLink
    local oldPMoney=_G.GetPlayerTradeMoney
    local oldTMoney=_G.GetTargetTradeMoney
    local oldUnitName=_G.UnitName
    local oldLeComplete=_G.LE_GAME_ERR_TRADE_COMPLETE
    local oldErrComplete=_G.ERR_TRADE_COMPLETE
    local oldLeCancel=_G.LE_GAME_ERR_TRADE_CANCELLED
    local oldErrCancel=_G.ERR_TRADE_CANCELLED
    local oldCharKey=host.app.charKey
    local oldModel=ns.Model

    assert(loadfile((((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../Analytics/Model.lua")))("MerchantMaster",host)
    _G.MerchantMasterLedgerDB={}
    ns.Store.Init()
    ns.Capture._testReady=true
    host.app.charKey="Normal-Horde-Forever-Crafter"
    local char,econ=ns.Store.CurrentCharAndEcon()
    local clock=1795390000
    _G.time=function() return clock end
    local cash=500000
    _G.GetMoney=function() return cash end
    local bagCounts={[12360]=0,[7068]=1,[7077]=1,[21]=0,[22]=0,[26]=0,[7078]=0}
    _G.GetItemCount=function(id) return bagCounts[id] or 0 end
    ns.Store.InitRecon(char,cash)

    local pSlots,tSlots,pGold,tGold,partnerName={},{},0,0,"BuyerBuddy"
    _G.GetNumTradeSlots=function() return 6 end
    _G.GetTradePlayerItemInfo=function(i) local s=pSlots[i]; if s then return s.name,nil,s.qty end end
    _G.GetTradePlayerItemLink=function(i) local s=pSlots[i]; return s and ("|Hitem:"..s.id.."|h["..s.name.."]|h") or nil end
    _G.GetTradeTargetItemInfo=function(i) local s=tSlots[i]; if s then return s.name,nil,s.qty end end
    _G.GetTradeTargetItemLink=function(i) local s=tSlots[i]; return s and ("|Hitem:"..s.id.."|h["..s.name.."]|h") or nil end
    _G.GetPlayerTradeMoney=function() return pGold end
    _G.GetTargetTradeMoney=function() return tGold end
    _G.UnitName=function(u) if u=="NPC" then return partnerName end return "Crafter" end
    _G.LE_GAME_ERR_TRADE_COMPLETE=245
    _G.ERR_TRADE_COMPLETE="Trade complete."
    _G.LE_GAME_ERR_TRADE_CANCELLED=246
    _G.ERR_TRADE_CANCELLED="Trade cancelled."

    -- 1. Craft Arcanite Bar (12360) with 10g cost, open trade > 30s, partner accepts (0,1), TRADE_CLOSED + close-time clear, then UI_INFO_MESSAGE(LE_GAME_ERR_TRADE_COMPLETE)
    ns.Store.Append({type="CRAFT",char=char,econ=econ,itemID=12360,qty=1,unit=0,total=0,where="Alchemy",time=clock,cogs=100000,extra={reagentCost=100000,name="Arcanite Bar"}})
    bagCounts[12360]=1
    clock=clock+60
    pSlots,tSlots,pGold,tGold={},{},0,0
    ns.Capture.OnEvent(nil,"TRADE_SHOW")
    pSlots[1]={id=12360,name="Arcanite Bar",qty=1}
    ns.Capture.OnEvent(nil,"TRADE_PLAYER_ITEM_CHANGED")
    tGold=260000
    ns.Capture.OnEvent(nil,"TRADE_MONEY_CHANGED")
    clock=clock+60 -- >30s open trade window must not drop pendingTrade
    ns.Capture.OnEvent(nil,"TRADE_ACCEPT_UPDATE",0,1)
    ns.Capture.OnEvent(nil,"TRADE_CLOSED")
    -- Simulate close-time trade slot clearing before UI_INFO_MESSAGE arrives
    pSlots,tSlots,pGold,tGold={},{},0,0
    ns.Capture.OnEvent(nil,"TRADE_PLAYER_ITEM_CHANGED")
    ns.Capture.OnEvent(nil,"TRADE_MONEY_CHANGED")
    cash=cash+260000
    bagCounts[12360]=0
    ns.Capture.OnEvent(nil,"UI_INFO_MESSAGE",245,"Trade complete.")

    local dayRows=ns.Store.db.days[ns.Store.DayKey(clock)].r
    local sellRow
    for _,r in ipairs(dayRows) do if r.type=="TRADE_SELL" and r.itemID==12360 then sellRow=r end end
    check(sellRow~=nil,"Arcanite Bar trade recorded after single-side accept, >30s open, TRADE_CLOSED clear, and LE_GAME_ERR_TRADE_COMPLETE")
    eq(sellRow.qty,1,"Arcanite Bar trade qty == 1")
    eq(sellRow.total,260000,"Arcanite Bar trade total == 26g (260000c)")
    eq(sellRow.where,"Trade","Arcanite Bar trade where == Trade")
    eq(sellRow.cogs,100000,"Arcanite Bar trade consumes 10g craft COGS")
    eq(sellRow.extra.buyer,"BuyerBuddy","Arcanite Bar trade records partner")
    local ov=ns.Model.Compute("overview",{char=char,period="today",knownCostOnly=false})
    eq(ov.kpis.sales,260000,"Overview Sales KPI reflects 26g Arcanite Bar trade")
    eq(ov.kpis.profit,160000,"Overview Profit KPI reflects 16g net profit (26g - 10g COGS)")
    local adj=ns.Store.ReconcileGold(char,cash,"Logout Reconciliation")
    check(adj==nil,"Logout Reconciliation produces zero unexplained delta after trade capture")

    -- 2. TRADE_BUY where player enters gold without TRADE_MONEY_CHANGED and clicks Accept (1,0), TRADE_CLOSED, then UI_INFO_MESSAGE
    clock=clock+120
    local beforeBuyCount=#dayRows
    pSlots,tSlots,pGold,tGold={},{},0,0
    partnerName="MatSeller"
    ns.Capture.OnEvent(nil,"TRADE_SHOW")
    tSlots[1]={id=7078,name="Essence of Fire",qty=2}
    ns.Capture.OnEvent(nil,"TRADE_TARGET_ITEM_CHANGED")
    pGold=50000
    ns.Capture.OnEvent(nil,"TRADE_ACCEPT_UPDATE",1,0)
    ns.Capture.OnEvent(nil,"TRADE_CLOSED")
    cash=cash-50000
    bagCounts[7078]=2
    ns.Capture.OnEvent(nil,"UI_INFO_MESSAGE",245,"Trade complete.")
    local buyRow=dayRows[beforeBuyCount+1]
    check(buyRow and buyRow.type=="TRADE_BUY" and buyRow.itemID==7078,"TRADE_BUY recorded when local player gold entered without TRADE_MONEY_CHANGED")
    eq(buyRow.total,-50000,"TRADE_BUY records -5g total")

    -- 3. Same item split across 2 slots aggregates to 1 row; 2 distinct items get distinct eids
    clock=clock+120
    local beforeMulti=#dayRows
    pSlots,tSlots,pGold,tGold={},{},0,0
    partnerName="BulkBuyer"
    ns.Capture.OnEvent(nil,"TRADE_SHOW")
    pSlots[1]={id=21,name="Item 21",qty=2}
    pSlots[2]={id=21,name="Item 21",qty=3}
    pSlots[3]={id=26,name="Item 26",qty=1}
    tGold=12000
    ns.Capture.OnEvent(nil,"TRADE_ACCEPT_UPDATE",1,1)
    cash=cash+12000
    ns.Capture.OnEvent(nil,"UI_INFO_MESSAGE",245,"Trade complete.")
    eq(#dayRows,beforeMulti+2,"same item across 2 slots aggregates into 1 row while distinct items emit 2 rows")
    eq(dayRows[beforeMulti+1].qty,5,"aggregated item sums qty across trade slots")
    check(dayRows[beforeMulti+1].extra.eid~=dayRows[beforeMulti+2].extra.eid,"multi-item trade rows keep distinct event IDs")

    -- 4. Mixed trade: mats received + gold tip received logs both TRADE_BUY (0g) and MONEY_TRANSFER (+tip, Trade)
    clock=clock+120
    local beforeMixed=#dayRows
    pSlots,tSlots,pGold,tGold={},{},0,0
    partnerName="TipClient"
    ns.Capture.OnEvent(nil,"TRADE_SHOW")
    tSlots[1]={id=22,name="Mat 22",qty=1}
    tGold=30000
    ns.Capture.OnEvent(nil,"TRADE_ACCEPT_UPDATE",1,1)
    cash=cash+30000
    bagCounts[22]=1
    ns.Capture.OnEvent(nil,"UI_INFO_MESSAGE",245,"Trade complete.")
    eq(#dayRows,beforeMixed+2,"mixed mats + tip trade logs both TRADE_BUY and MONEY_TRANSFER")
    check(dayRows[beforeMixed+1].type=="TRADE_BUY" and dayRows[beforeMixed+1].total==0,"mixed mats + tip logs 0g TRADE_BUY for mats")
    check(dayRows[beforeMixed+2].type=="MONEY_TRANSFER" and dayRows[beforeMixed+2].total==30000 and dayRows[beforeMixed+2].where=="Trade","mixed mats + tip logs +3g MONEY_TRANSFER at Trade")

    -- 5. Cancelled trade after (1,0) accept and TRADE_CLOSED records nothing
    clock=clock+120
    local beforeCancel=#dayRows
    pSlots,tSlots,pGold,tGold={},{},0,0
    ns.Capture.OnEvent(nil,"TRADE_SHOW")
    pSlots[1]={id=12360,name="Arcanite Bar",qty=1}
    tGold=260000
    ns.Capture.OnEvent(nil,"TRADE_ACCEPT_UPDATE",1,0)
    ns.Capture.OnEvent(nil,"TRADE_CLOSED")
    ns.Capture.OnEvent(nil,"UI_INFO_MESSAGE",246,"Trade cancelled.")
    eq(#dayRows,beforeCancel,"cancelled trade after single accept logs no transactions")

    _G.MerchantMasterLedgerDB=oldLedger
    ns.Store.Init()
    _G.time=oldTime
    _G.GetMoney=oldMoney
    _G.GetItemCount=oldItemCount
    _G.GetNumTradeSlots=oldNumTrade
    _G.GetTradePlayerItemInfo=oldPInfo
    _G.GetTradePlayerItemLink=oldPLink
    _G.GetTradeTargetItemInfo=oldTInfo
    _G.GetTradeTargetItemLink=oldTLink
    _G.GetPlayerTradeMoney=oldPMoney
    _G.GetTargetTradeMoney=oldTMoney
    _G.UnitName=oldUnitName
    _G.LE_GAME_ERR_TRADE_COMPLETE=oldLeComplete
    _G.ERR_TRADE_COMPLETE=oldErrComplete
    _G.LE_GAME_ERR_TRADE_CANCELLED=oldLeCancel
    _G.ERR_TRADE_CANCELLED=oldErrCancel
    host.app.charKey=oldCharKey
    ns.Model=oldModel
end
-- Portfolio container boundaries, bank open/close snapshot lifecycle, legacy preservation, and Audit & Sync tool
do
    local inv = ns.Inventory
    local oldLedger = _G.MerchantMasterLedgerDB
    local oldHostDB = _G.MerchantMasterDB
    local oldContainer = _G.C_Container
    local oldEnum = _G.Enum
    local oldNumBag = _G.NUM_BAG_SLOTS
    local oldTotalBag = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS
    local oldNumBank = _G.NUM_BANKBAGSLOTS
    local oldBankFrame = _G.BankFrame
    local oldTime = _G.time
    local oldGetMoney = _G.GetMoney
    local clock = 1794500000
    _G.time = function() return clock end
    _G.GetMoney = function() return 12345 end

    _G.MerchantMasterLedgerDB = {}
    ns.Store.Init()
    local char, econ = ns.Store.CurrentCharAndEcon()
    _G.MerchantMasterDB = {
        itemIDs = { ["Peacebloom"] = 2447, ["Silverleaf"] = 765, ["Silk Cloth"] = 4306 },
        chars = {
            [char] = {
                name = "Tester",
                economy = econ,
                bags = { ["Peacebloom"] = 2 },
                bank = { ["Silk Cloth"] = 10 },
                mail = { ["Silverleaf"] = 4 },
            },
        },
    }

    -- 1. Container boundary: ReagentBag == 5 with NUM_BAG_SLOTS == 4 must NOT include bag 5 in bags
    _G.NUM_BAG_SLOTS = 4
    _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
    _G.NUM_BANKBAGSLOTS = 6
    _G.Enum = { BagIndex = { Bank = -1, ReagentBag = 5, BankBag_1 = 5 } }
    local bagIDs, bagSet = inv.GetBagContainerIDs()
    local bankIDs = inv.GetBankContainerIDs()
    check(not bagSet[5], "ReagentBag=5 with 4 normal bags must NOT be scanned as a player bag")
    local bankHas5 = false
    for _, b in ipairs(bankIDs) do if b == 5 then bankHas5 = true end end
    check(bankHas5, "Bank bag 5 remains exclusively in bank container list")

    -- 2. First BAG_UPDATE_DELAYED preserves legacy MerchantMasterDB.chars[char].bank and mail
    local liveState = {
        bags = { [0] = { { id = 2447, qty = 2, link = "|Hitem:2447|h[Peacebloom]|h" } } },
        bank = { [5] = { { id = 4306, qty = 10, link = "|Hitem:4306|h[Silk Cloth]|h" } } },
        bankShown = false,
    }
    _G.BankFrame = { IsShown = function() return liveState.bankShown end }
    _G.C_Container = {
        GetContainerNumSlots = function(bag)
            if bag >= 0 and bag <= 4 then return 4 end
            if liveState.bankShown and (bag == -1 or (bag >= 5 and bag <= 10)) then return 4 end
            return 0
        end,
        GetContainerItemInfo = function(bag, slot)
            local src = (bag >= 0 and bag <= 4) and liveState.bags[bag] or (liveState.bankShown and liveState.bank[bag] or nil)
            local entry = src and src[slot]
            if not entry then return nil end
            return { itemID = entry.id, stackCount = entry.qty, hyperlink = entry.link, isBound = entry.bound == true }
        end,
    }
    ns.Capture.OnEvent(nil, "BAG_UPDATE_DELAYED")
    local snap1 = ns.Store.db.inventory[char]
    check(snap1 and snap1.bags[2447] == 2, "first BAG_UPDATE_DELAYED captures live bags")
    check(snap1 and snap1.bank[4306] == 10 and snap1.mail[765] == 4, "first BAG_UPDATE_DELAYED preserves legacy bank and mail instead of wiping")

    -- 3. Bank-bag withdraw + BANKFRAME_CLOSED: zero double-count and closed-bank never wipes bank
    liveState.bankShown = true
    ns.Capture.OnEvent(nil, "BANKFRAME_OPENED")
    eq(ns.Store.db.inventory[char].bank[4306], 10, "BANKFRAME_OPENED scans live bank bag 5")
    -- Withdraw 4 Silk Cloth from bank bag 5 to player bag 0 (triggers BAG_UPDATE_DELAYED, NOT PLAYERBANKSLOTS_CHANGED)
    liveState.bank[5] = { { id = 4306, qty = 6, link = "|Hitem:4306|h[Silk Cloth]|h" } }
    liveState.bags[0] = {
        { id = 2447, qty = 2, link = "|Hitem:2447|h[Peacebloom]|h" },
        { id = 4306, qty = 4, link = "|Hitem:4306|h[Silk Cloth]|h" },
    }
    ns.Capture.OnEvent(nil, "BAG_UPDATE_DELAYED")
    eq(ns.Store.db.inventory[char].bags[4306], 4, "withdrawn Silk Cloth appears in bags")
    eq(ns.Store.db.inventory[char].bank[4306], 6, "BAG_UPDATE_DELAYED while bank open updates bank bag 5 without double-counting")
    -- Final withdraw right at BANKFRAME_CLOSED
    liveState.bank[5] = { { id = 4306, qty = 5, link = "|Hitem:4306|h[Silk Cloth]|h" } }
    liveState.bags[0][2].qty = 5
    ns.Capture.OnEvent(nil, "BANKFRAME_CLOSED")
    liveState.bankShown = false
    eq(ns.Store.db.inventory[char].bags[4306], 5, "BANKFRAME_CLOSED captures final bag qty")
    eq(ns.Store.db.inventory[char].bank[4306], 5, "BANKFRAME_CLOSED captures final bank qty before closing")
    -- Closed-bank events with 0 bank slots MUST NEVER wipe stored bank
    ns.Capture.OnEvent(nil, "PLAYERBANKSLOTS_CHANGED")
    ns.Capture.OnEvent(nil, "BAG_UPDATE_DELAYED")
    eq(ns.Store.db.inventory[char].bank[4306], 5, "closed-bank PLAYERBANKSLOTS_CHANGED and BAG_UPDATE_DELAYED never wipe bank")

    -- 4. AnalyzePortfolio (bank closed vs open) + SyncPortfolio (dedup, stale lot, transit, basis avg preservation)
    ns.Store.db.wealth[char] = {
        at = clock, econ = econ,
        cats = {
            bags = {
                { id = 2447, name = "Peacebloom", qty = 1, unit = 100, total = 100, basis = "Live AH" },
                { id = 2447, name = "Peacebloom", qty = 1, unit = 100, total = 100, basis = "Live AH" },
                { id = 4306, name = "Silk Cloth", qty = 1, unit = 200, total = 200, basis = "Live AH" },
            },
            bank = {
                { id = 4306, name = "Silk Cloth", qty = 5, unit = 200, total = 1000, basis = "Live AH" },
            },
            mail = {}, gear = {}, listed = {},
        },
    }
    ns.Store.PostLot(char, econ, 2447, 3, 500, 10, clock - 60 * 3600, "Peacebloom", 7701)
    ns.Store.db.inTransitMail = {
        { id = "tr1", fromChar = "Alt", toChar = char, econ = econ, sentAt = clock - 90 * 86400, expiresAt = clock - 10, items = { [4306] = 2 }, money = 0 },
    }
    ns.Store.AddBasis(econ, 4306, 20, 20 * 250) -- 20 units @ 250c avg vs 10 physical units (5 bags + 5 bank)
    local closedRep = inv.AnalyzePortfolio({ char = char, econ = econ, bankOpen = false, now = clock })
    check(not closedRep.bankOpen and closedRep.bankStatus:find("CLOSED", 1, true) ~= nil, "AnalyzePortfolio marks closed bank clearly")
    local hasDup, hasBagDrift, hasStaleLot, hasStaleTransit, hasBasisExcess, hasFalseBankMiss = false, false, false, false, false, false
    for _, f in ipairs(closedRep.findings) do
        if f.code == "DUP" and f.itemID == 2447 then hasDup = true end
        if f.code == "BAG_DRIFT" and f.itemID == 4306 then hasBagDrift = true end
        if f.code == "STALE_LOT" and f.itemID == 2447 then hasStaleLot = true end
        if f.code == "STALE_TRANSIT" and f.itemID == 4306 then hasStaleTransit = true end
        if f.code == "BASIS_EXCESS" and f.itemID == 4306 then hasBasisExcess = true end
        if f.code == "BANK_DRIFT" and f.liveQty == 0 then hasFalseBankMiss = true end
    end
    check(hasDup, "AnalyzePortfolio detects duplicate Wealth Breakdown bag rows")
    check(hasBagDrift, "AnalyzePortfolio detects bag snapshot drift against live bags")
    check(hasStaleLot, "AnalyzePortfolio detects stale open AH lot older than 48h")
    check(hasStaleTransit, "AnalyzePortfolio detects expired in-transit mail")
    check(hasBasisExcess, "AnalyzePortfolio detects ledger basis qty excess vs tracked inventory")
    check(not hasFalseBankMiss, "AnalyzePortfolio never falsely flags closed-bank items as missing")

    -- Sync without basis alignment preserves bank & basis while fixing duplicates, bags, stale lots, and transit
    local sync1 = inv.SyncPortfolio({ char = char, econ = econ, bankOpen = false, now = clock, reconcileBasis = false })
    check(sync1 and sync1.ok, "SyncPortfolio completes cleanly")
    check(#ns.Store.db.wealth[char].cats.bags == 2, "SyncPortfolio merges duplicate Wealth Breakdown bag rows")
    eq(ns.Store.db.inventory[char].bank[4306], 5, "SyncPortfolio preserves closed bank snapshot")
    eq(#(ns.Store.Lots(char, 2447)), 0, "SyncPortfolio prunes >52h stale open AH lot")
    eq(#(ns.Store.db.inTransitMail or {}), 0, "SyncPortfolio prunes expired in-transit mail")
    local bQty1, bAvg1 = ns.Store.Basis(econ, 4306)
    eq(bQty1, 20, "SyncPortfolio(reconcileBasis=false) preserves ledger basis qty untouched")
    eq(bAvg1, 250, "SyncPortfolio(reconcileBasis=false) preserves unit avg cost")
    check(ns.Store.db.stats.portfolioAuditLog and #ns.Store.db.stats.portfolioAuditLog >= 1, "SyncPortfolio records persistent audit receipt")

    -- Sync WITH basis alignment caps basis qty to physical stock while preserving avg unit cost
    local sync2 = inv.SyncPortfolio({ char = char, econ = econ, bankOpen = false, now = clock, reconcileBasis = true })
    check(sync2 and sync2.ok and sync2.auditEntry.basisAdjusted == 1, "SyncPortfolio(reconcileBasis=true) aligns excess basis item")
    local bQty2, bAvg2 = ns.Store.Basis(econ, 4306)
    eq(bQty2, 10, "Aligned basis qty matches tracked physical stock (5 bags + 5 bank = 10)")
    eq(bAvg2, 250, "Aligned basis strictly preserves original unit avg cost (250c)")

    _G.MerchantMasterLedgerDB = oldLedger
    _G.MerchantMasterDB = oldHostDB
    _G.C_Container = oldContainer
    _G.Enum = oldEnum
    _G.NUM_BAG_SLOTS = oldNumBag
    _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = oldTotalBag
    _G.NUM_BANKBAGSLOTS = oldNumBank
    _G.BankFrame = oldBankFrame
    _G.time = oldTime
    _G.GetMoney = oldGetMoney
    ns.Capture._bankOpen = nil
    ns.Store.Init()
end

-- Regression: PLAYER_EQUIPMENT_CHANGED updates DB.inventory.gear, AnalyzePortfolio reports GEAR_DRIFT, and SyncPortfolio cleans alias/placeholder keys + syncs gear
do
    local oldLedger = _G.MerchantMasterLedgerDB
    local oldHostDB = _G.MerchantMasterDB
    local oldContainer = _G.C_Container
    local oldGetInvID = _G.GetInventoryItemID
    local oldTime = _G.time
    local oldGetMoney = _G.GetMoney
    local oldCharKey = host.app and host.app.charKey
    local clock = 1794600000
    _G.time = function() return clock end
    _G.GetMoney = function() return 10000 end
    _G.MerchantMasterLedgerDB = { schema = 1, stats = { chars = {} } }
    ns.Store.Init()
    local char = "Normal-Horde-ExampleRealm PvE-GearHero"
    local alias = "Normal-Horde-Forever-GearHero"
    local ghost = "Normal-Horde-Forever-Player"
    local econ = "Normal-Horde"
    local bagItems, equippedItem = { [7001] = 0 }, 7001
    host.app.charKey = char
    _G.MerchantMasterDB = {
        itemIDs = { ["Explorer Tunic"] = 7001 },
        chars = {
            [char] = { name = "GearHero", economy = econ, bags = {}, bank = {}, mail = {}, gear = { ["Explorer Tunic"] = 1 } },
            [alias] = { name = "GearHero", economy = econ, bags = {}, bank = {}, mail = {}, gear = { ["Explorer Tunic"] = 1 } },
            [ghost] = { name = "Player", economy = econ, bags = {}, bank = {}, mail = {}, gear = {} },
        },
    }
    _G.C_Container = {
        GetContainerNumSlots = function(b) return b == 0 and 1 or 0 end,
        GetContainerItemInfo = function(b, s)
            if b == 0 and s == 1 and (bagItems[7001] or 0) > 0 then
                return { itemID = 7001, stackCount = bagItems[7001], hyperlink = "|Hitem:7001|h[Explorer Tunic]|h", isBound = true }
            end
            return nil
        end,
    }
    _G.GetInventoryItemID = function(_, slot)
        if slot == 5 then return equippedItem end
        return nil
    end

    inv.ScanCurrentChar({ char = char, econ = econ })
    eq(inv.GetItemBreakdown(7001, econ).gear, 1, "Initial scan sees Explorer Tunic equipped once (alias collapsed)")
    eq(inv.GetItemBreakdown(7001, econ).bags, 0, "Initial bags have 0 Explorer Tunic")

    -- Unequip into bag: PLAYER_EQUIPMENT_CHANGED + BAG_UPDATE_DELAYED must move count from Gear -> Bags (Total = 1, never 2)
    equippedItem = nil
    bagItems[7001] = 1
    ns.Capture.OnEvent(nil, "PLAYER_EQUIPMENT_CHANGED")
    ns.Capture.OnEvent(nil, "BAG_UPDATE_DELAYED")
    local bdAfter = inv.GetItemBreakdown(7001, econ)
    eq(bdAfter.bags, 1, "Unequipped item counts 1 in bags")
    eq(bdAfter.gear, 0, "PLAYER_EQUIPMENT_CHANGED clears unequipped item from DB.inventory.gear")
    eq(bdAfter.total, 1, "Total equipment count remains 1 (not 2x Bags+Gear)")

    -- Re-equip item while stored DB.inventory still had old state -> AnalyzePortfolio detects GEAR_DRIFT + ALIAS
    equippedItem = 7001
    bagItems[7001] = 0
    ns.Store.SaveSnapshot(alias, "2026-11-20", { gold = 500, items = 420, listed = 0, econ = econ })
    ns.Store.db.wealth[alias] = { at = clock - 100, econ = econ, cats = { bags = {}, bank = {}, mail = {}, gear = { { id = 7001, name = "Explorer Tunic", qty = 1, unit = 420, total = 420 } }, listed = {} } }
    local repBefore = inv.AnalyzePortfolio({ char = char, econ = econ, bankOpen = false, now = clock })
    local sawGearDrift, sawAlias = false, false
    for _, f in ipairs(repBefore.findings) do
        if f.code == "GEAR_DRIFT" and f.itemID == 7001 then sawGearDrift = true end
        if f.code == "ALIAS" then sawAlias = true end
    end
    check(sawGearDrift, "AnalyzePortfolio detects GEAR_DRIFT when live equipped gear differs from stored snapshot")
    check(sawAlias, "AnalyzePortfolio detects alias and placeholder character keys")

    local syncRes = inv.SyncPortfolio({ char = char, econ = econ, bankOpen = false, now = clock })
    check(syncRes and syncRes.ok, "SyncPortfolio completes alias cleanup and live gear sync")
    eq(ns.Store.db.inventory[char].gear[7001], 1, "SyncPortfolio syncs live equipped gear into DB.inventory")
    check(ns.Store.db.snaps[alias] == nil and ns.Store.db.wealth[alias] == nil and _G.MerchantMasterDB.chars[alias] == nil,
        "SyncPortfolio removes duplicate alias character key")
    check(ns.Store.db.snaps[char] and ns.Store.db.snaps[char]["2026-11-20"] ~= nil,
        "SyncPortfolio preserves historical snap day from merged alias key")
    check(_G.MerchantMasterDB.chars[ghost] == nil, "SyncPortfolio removes placeholder Normal-Horde-Forever-Player")

    if host.app then
        host.app.charKey = oldCharKey
    end
    _G.MerchantMasterLedgerDB = oldLedger
    _G.MerchantMasterDB = oldHostDB
    _G.C_Container = oldContainer
    _G.GetInventoryItemID = oldGetInvID
    _G.time = oldTime
    _G.GetMoney = oldGetMoney
    ns.Store.Init()
end

-- Disenchant capture: proportional cost carryover, remainder copper split, and 0-cost looted BoE
do
    local oldLedger = _G.MerchantMasterLedgerDB
    local oldContainer = _G.C_Container
    local oldGetItemCount = _G.GetItemCount
    local oldMarketPrice = host.GetItemMarketPrice
    local oldItemName = ns.Model.ItemName
    _G.MerchantMasterLedgerDB = { schema = 1, stats = { chars = {} } }
    ns.Store.Init()
    local char, econ = ns.Store.CurrentCharAndEcon()
    local bagState = { [8101] = 1, [8102] = 0, [8103] = 1, [8104] = 0, [8105] = 0, [8106] = 0, [8107] = 1, [8108] = 0 }
    local slotOrder = { 8101, 8102, 8103, 8104, 8105, 8106, 8107, 8108 }
    local prices = { [8102] = 20000, [8104] = 1000, [8105] = 1000, [8106] = 1000, [8108] = 20000 }
    local names = { [8101] = "Green Lens", [8102] = "Large Radiant Shard", [8103] = "Arcane Robe", [8107] = "Looted Belt" }
    host.GetItemMarketPrice = function(id) return prices[id] or 0 end
    ns.Model.ItemName = function(id) return names[id] or ("Item " .. tostring(id)) end
    _G.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and #slotOrder or 0 end,
        GetContainerItemInfo = function(bag, slot)
            if bag ~= 0 then return nil end
            local id = slotOrder[slot]
            local n = id and bagState[id] or 0
            if n > 0 then return { itemID = id, stackCount = n } end
        end,
    }
    _G.GetItemCount = function(id) return bagState[id] or 0 end

    -- Case 1: 1g Green Lens -> 2g Large Radiant Shard carries over exact 1g basis (NOT 2g marketValue)
    ns.Store.AddBasis(econ, 8101, 1, 10000)
    ns.Capture.OnEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "de1", 13262)
    bagState[8101] = 0; bagState[8102] = 1
    ns.Capture.OnEvent(nil, "BAG_UPDATE_DELAYED")
    local rows = ns.Store.db.days[ns.Store.DayKey()].r
    local b1, r1
    for _, r in ipairs(rows) do
        if r.type == "DISENCHANT_BROKEN" and r.itemID == 8101 then b1 = r
        elseif r.type == "DISENCHANT_RECEIVE" and r.itemID == 8102 then r1 = r end
    end
    check(b1 and b1.cogs == 10000 and b1.profit == 0, "DE capture books 0 profit on Green Lens DISENCHANT_BROKEN")
    check(r1 and r1.extra.costCarryover == true and r1.extra.allocBasis == 10000 and r1.extra.marketValue == 20000 and r1.extra.srcName == "Green Lens",
        "DE capture stamps costCarryover=true and carries 10000c basis instead of 20000c marketValue")
    eq(select(2, ns.Store.Basis(econ, 8102)), 10000, "Large Radiant Shard basis equals 10000c source cost")

    -- Case 2: Multi-output exact integer copper split (100c across 3 equal-value outputs -> 33 + 33 + 34 = 100)
    ns.Store.AddBasis(econ, 8103, 1, 100)
    ns.Capture.OnEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "de2", 13262)
    bagState[8103] = 0; bagState[8104] = 1; bagState[8105] = 1; bagState[8106] = 1
    ns.Capture.OnEvent(nil, "BAG_UPDATE_DELAYED")
    local splitRows, splitSum = {}, 0
    for _, r in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do
        if r.type == "DISENCHANT_RECEIVE" and r.extra.srcItemID == 8103 then
            splitRows[#splitRows + 1] = r
            splitSum = splitSum + (tonumber(r.extra.allocBasis) or 0)
        end
    end
    eq(#splitRows, 3, "multi-output DE emits 3 DISENCHANT_RECEIVE rows")
    eq(splitSum, 100, "multi-output DE conserves exact 100c copper total")
    eq(splitRows[1].extra.allocBasis, 33, "first multi-output share is 33c")
    eq(splitRows[2].extra.allocBasis, 33, "second multi-output share is 33c")
    eq(splitRows[3].extra.allocBasis, 34, "final multi-output share receives 34c remainder")

    -- Case 3: 0-cost looted BoE DE -> allocBasis == 0, costCarryover == true, basis == 0
    ns.Capture.OnEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "de3", 13262)
    bagState[8107] = 0; bagState[8108] = 1
    ns.Capture.OnEvent(nil, "BAG_UPDATE_DELAYED")
    local r3
    for _, r in ipairs(ns.Store.db.days[ns.Store.DayKey()].r) do
        if r.type == "DISENCHANT_RECEIVE" and r.itemID == 8108 then r3 = r end
    end
    check(r3 and r3.extra.costCarryover == true and r3.extra.allocBasis == 0 and r3.extra.marketValue == 20000,
        "0-cost looted BoE DE sets allocBasis=0 with costCarryover=true even when marketValue=20000")
    eq(select(2, ns.Store.Basis(econ, 8108)), 0, "0-cost looted BoE output has 0 basis")

    host.GetItemMarketPrice = oldMarketPrice
    ns.Model.ItemName = oldItemName
    _G.C_Container = oldContainer
    _G.GetItemCount = oldGetItemCount
    _G.MerchantMasterLedgerDB = oldLedger
    ns.Store.Init()
end
print(string.format("PASS: Random-enchant ledger capture (%d total assertions)",assertions))
print("PASS: Inventory freshness generation")
