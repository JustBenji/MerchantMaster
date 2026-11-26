-- Standalone accounting persistence contracts; all identities and money are synthetic.
local root = (((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local now, char, econ = 1794484800, "Normal-Horde-Forever-Tester", "Normal-Horde"
time = function() return now end; date = os.date
local host = {app={charKey=char}, DetectActiveEconomy=function() return econ end,
    GetItemMarketPrice=function() return 25 end, ItemName=function(id) return id==1 and 'Herb,"Rare"\nleaf' or ('Item '..id) end}
MerchantMasterAPI={ns=host}; MerchantMasterDB={chars={[char]={}},itemIDs={}}
assert(loadfile(root.."Analytics/Store.lua"))("MerchantMaster",host)
local S=host.Analytics.Store
local assertions, cases = 0, 0
local function check(v,msg) assertions=assertions+1; assert(v,msg) end
local function fresh() MerchantMasterLedgerDB={}; TradeSkillMasterDB=nil; S.Init(); return S.db end
local function rows() local out={}; S.IterDays(nil,nil,function(_,r) for _,v in ipairs(r) do out[#out+1]=v end end); return out end
local function add(typ,id,qty,total,t,extra) return S.Append({type=typ,itemID=id,qty=qty,total=total,time=t or now,unit=qty>0 and math.abs(total)/qty or 0,extra=extra}) end
local function test(name,fn) fresh(); fn(); cases=cases+1; print('PASS '..name) end

test('legacy TSM importer/reconciler removed while passive historical tsm rows load and replay',function()
    check(S.SeedTSM==nil and S.ReconcileTSMSales==nil,'SeedTSM and ReconcileTSMSales removed in pure standalone mode')
    MerchantMasterLedgerDB={schema=1,seed={tsm={at=now-86400,imported=2}},basis={[econ]={[1]={qty=2,avg=10}}},days={[S.DayKey(now-86400)]={r={
        {time=now-86400,char=char,econ=econ,type='AH_BUY',itemID=1,qty=4,unit=10,total=-40,where='Auction House',extra={tsm=1,seller='Seller'}},
        {time=now-86300,char=char,econ=econ,type='AH_SELL',itemID=1,qty=2,unit=100,total=190,cogs=20,where='Auction House',extra={tsm=1,gross=200,fee=10,buyer='Buyer'}},
    }}}}
    S.Init()
    local list=rows()
    check(#list==2 and list[1].extra.tsm==1 and list[2].extra.tsm==1,'passive historical extra.tsm rows load cleanly')
    check(list[2].total==190 and list[2].extra.buyer=='Buyer' and list[1].extra.seller=='Seller','historical counterparties and totals preserved')
    check(S.db.schema==1,'schema remains rollback compatible')
end)

test('normalized buys and sales feed basis, cash and item metadata',function()
    for _,typ in ipairs({'COD_BUY','TRADE_BUY','VENDOR_BUYBACK'}) do add(typ,1,2,-100,now-100) end
    local sold=add('COD_SELL',1,2,160,now,{fee=10,buyer='Buyer',variant='suffix:7'})
    check(sold.cogs==100,'COD consumes known basis')
    check(S.Basis(econ,1)==4,'new buy types build shared basis')
    local roll=S.db.roll[S.DayKey()][char][1]
    check(roll.bought==6 and roll.spent==300 and roll.sold==2 and roll.gross==170 and roll.fee==10,'rollups cover normalized trade types')
    local meta=S.db.itemStats[econ][1]
    check(meta.minBuy==50 and meta.maxBuy==50 and meta.lastBuyTs==now-100,'buy price bounds')
    check(meta.lastSoldTo=='Buyer' and meta.lastSoldTs==now,'last-sale metadata')
    check(meta.variants['suffix:7'].lastSoldTo=='Buyer','variant stats alongside base item')
    add('REPAIR',0,0,-30); add('POSTAGE',0,0,-5); add('MONEY_TRANSFER',0,0,100); add('OTHER_INCOME',0,0,7); add('OTHER_EXPENSE',0,0,-2)
    check(S.db.stats.recon[char].recorded==-70,'all cash changes reconcile')
    local log=add('AUCTION_LOG',0,0,900,nil,{nonCash=true}); check(log.total==0 and S.db.stats.recon[char].recorded==-70,'operational log never adds ledger cash')
end)

test('expiry counters reset on chronological sale and ignore older returns',function()
    add('AH_EXPIRE',1,2,0,now-10); add('AH_CANCEL',1,1,0,now-9)
    local m=S.db.itemStats[econ][1]; check(m.expSinceSale==2 and m.canSinceSale==1,'returns tracked')
    add('TRADE_SELL',1,1,50,now); check(m.expSinceSale==0 and m.canSinceSale==0,'trade sale resets counts')
    add('AH_EXPIRE',1,3,0,now-8); check(m.expSinceSale==0,'out of order return does not resurrect counter')
end)

test('stable IDs survive packed format, legacy data and CSV escaping',function()
    local a=add('TRADE_BUY',1,2,-100,now-86400,{seller='A,"B"',mixed=false,[7]=true,time='extra'})
    local b=add('ADJUST',0,0,0,now-86400,{mixed=0}); b.ref=''
    local id=a.extra.eid; check(type(id)=='string' and id~=b.extra.eid,'stable unique identity')
    local packed=S.PackDay(S.DayKey(now-86400)); local decoded=S.UnpackDayString(packed)
    check(decoded[1].extra.eid==id and decoded[1].extra[7] and decoded[2].ref=='','MM1 metadata preserves types')
    check(S.UnpackDayString('123,C,Normal-Horde,ADJUST,W,0,1,0,-1,,,x=n:1')[1].extra.x==1,'legacy CSV remains readable')
    local csv=S.Export({type='buys',itemID=1,search='rare'})
    check(csv:sub(1,14)=='time,date,char','CSV header')
    check(csv:find('"Herb,""Rare""\nleaf"',1,true) and csv:find('"A,""B"""',1,true),'CSV escaped names and counterparties')
    check(S.Export({type='sells'}):find('\n')==nil,'empty selection is header only')
end)

test('packed edit replays later sales, lots, cash and metadata',function()
    local buy=add('AH_BUY',1,10,-1000,now-172800)
    add('AH_POST',1,4,-20,now-86400,{auctionID=77,name='Herb'})
    local sale=add('AH_SELL',1,4,760,now,{gross=800,fee=40,buyer='Old'})
    check(sale.cogs==400 and S.Basis(econ,1)==6,'initial basis')
    local day=S.DayKey(buy.time); S.PackDay(day)
    local result=S.Correct(buy.extra.eid,{action='edit',total=-2000,unit=200})
    check(result.ok and S.db.days[day].s~=nil,'packed day edited and repacked')
    local r=rows(); check(r[#r].cogs==800,'later sale COGS replayed')
    local qty,avg=S.Basis(econ,1); check(qty==6 and avg==200,'remaining weighted basis replayed')
    check(#S.Lots(char,1)==0 and S.db.roll[S.DayKey()][char][1].cogs==800,'lots and rollups replayed')
    check(S.db.stats.recon[char].recorded==-1260,'cash reconciliation rebuilt')
    check(S.Correct(sale.extra.eid,{action='delete'}).ok,'sale deleted')
    check(S.Basis(econ,1)==10 and S.Lots(char,1)[1].qty==4,'deletion restores basis and open lot')
    check(S.db.itemStats[econ][1].lastSoldTs==nil,'deleted sale metadata removed')
    check(not S.Correct('missing',{action='delete'}).ok,'unknown ID rejected')
    check(not S.Correct(buy.extra.eid,{action='edit',qty=-1}).ok,'invalid edit rejected before mutation')
end)

test('prune preview and repeated prune preserve aggregate and basis continuity',function()
    add('AH_BUY',1,10,-1000,now-172800); add('TRADE_SELL',1,2,400,now-86400)
    S.AddLoot(2,'Mob','Test',3,{time=now-172800})
    S.SaveSnapshot(char,S.DayKey(now-172800),{gold=123,econ=econ})
    local cutoff=S.DayKey(now); local version=S.version; local p=S.PreviewPrune(cutoff)
    check(p.daysToPrune==2 and p.rowsToPrune==2 and p.rollDaysToFold==2,'preview exact counts')
    check(p.estBytesBefore>p.estBytesAfter and S.version==version,'preview estimates without mutation')
    local qty,avg=S.Basis(econ,1); local result=S.PruneBefore(cutoff)
    check(result.ok and next(S.db.days)==nil and S.db.loot[S.DayKey(now-172800)]==nil,'raw days and loot removed')
    check(S.db.archivedRoll[char][1].bought==10 and S.db.archivedRoll[char][1].sold==2,'archive preserves all-time aggregates')
    check(S.Basis(econ,1)==qty and select(2,S.Basis(econ,1))==avg,'pruning retains basis')
    check(S.db.snaps[char][S.DayKey(now-172800)].gold==123,'snapshots survive')
    check(S.db.archivedLoot[char]['2|Mob|Test']==3,'all-time loot aggregate survives')
    S.PruneBefore(cutoff); check(S.db.archivedRoll[char][1].sold==2,'repeated prune does not refold')
    local later=add('TRADE_SELL',1,1,300,now)
    check(S.Correct(later.extra.eid,{action='edit',qty=2,total=600}).ok,'correction after prune uses checkpoint')
    check(S.Basis(econ,1)==6,'archived basis checkpoint survives correction')
end)

test('grouped presentation conserves raw identities and exact cash',function()
    local a=add('TRADE_BUY',1,2,-100,now-200,{seller='Seller',fee=1})
    local b=add('TRADE_BUY',1,3,-150,now-100,{seller='Seller',fee=2})
    add('TRADE_BUY',1,1,-50,now+301,{seller='Seller'})
    local grouped=S.CoalesceRows(rows())
    check(#grouped==2 and grouped[1].qty==5 and grouped[1].total==-250 and grouped[1].fee==3,'grouped totals')
    check(#grouped[1].rawEventIDs==2 and grouped[1].rawEventIDs[1]==a.extra.eid and grouped[1].rawEventIDs[2]==b.extra.eid,'raw event identities retained')
    check(#rows()==3 and a.qty==2,'raw ledger unchanged')
end)

test('portable transfer deterministic, duplicate safe and validates before mutation',function()
    assert(loadfile(root..'Analytics/Transfer.lua'))('MerchantMaster',host)
    local T=host.Analytics.Transfer
    add('TRADE_BUY',1,3,-150,now-1,{seller='Seller'}); add('TRADE_SELL',1,1,90,now,{buyer='Buyer'})
    local payload=T.ExportBundle({}); check(payload:sub(1,5)=='MMX1:' and payload==T.ExportBundle({}),'deterministic export')
    fresh(); local r=T.Import(payload); check(r.ok and r.imported==2 and r.skipped==0,'new account import')
    local second=T.Import(payload); check(second.ok and second.imported==0 and second.skipped==2 and #rows()==2,'duplicate origins skipped')
    for _,bad in ipairs({'',payload:sub(1,-2),payload..'x',payload:gsub('MMX1:','MMX2:',1),'MMX1:1:0:x'}) do
        local call,result=pcall(T.Import,bad); check(call and not result.ok and #rows()==2,'malformed transfer rejected atomically')
    end
end)

test('pre-retention transfers are rejected before database mutation',function()
    assert(loadfile(root..'Analytics/Transfer.lua'))('MerchantMaster',host); local T=host.Analytics.Transfer
    add('AH_BUY',1,10,-1000,now-120*86400); add('AH_SELL',1,2,400,now-120*86400)
    add('AH_BUY',1,1,-300,now)
    local payload=T.ExportBundle({}); local current=T.ExportBundle({period='today'})
    fresh(); add('AH_BUY',1,10,-1000,now-120*86400); add('AH_SELL',1,2,400,now-120*86400)
    local cutoff=S.DayKey(now-90*86400); check(S.PruneBefore(cutoff).ok,'historical rows pruned')
    S.db.stats.importedOrigins=nil; S.db.stats.originID=nil
    local database,stats,version=S.db,S.db.stats,S.version
    local function copy(value)
        if type(value)~='table' then return value end
        local out={}; for key,child in pairs(value) do out[key]=copy(child) end; return out
    end
    local function same(a,b)
        if type(a)~='table' or type(b)~='table' then return a==b end
        for key,value in pairs(a) do if not same(value,b[key]) then return false end end
        for key in pairs(b) do if a[key]==nil then return false end end
        return true
    end
    local snapshot=copy(database)
    local qty,avg=S.Basis(econ,1)
    local rejected=T.Import(payload)
    check(not rejected.ok and rejected.err=='bundle contains transactions before pruned retention cutoff ('..cutoff..')'
        and rejected.imported==0 and rejected.skipped==0,'pre-retention import rejected with exact cutoff')
    check(S.db==database and S.db.stats==stats and S.version==version and next(S.db.days)==nil,'rejection leaves database identity, version and raw rows unchanged')
    check(stats.importedOrigins==nil and stats.originID==nil,'rejection does not initialize origin or dedupe metadata')
    check(same(database,snapshot),'rejection preserves the complete database value')
    check(S.Basis(econ,1)==qty and select(2,S.Basis(econ,1))==avg,'rejection leaves basis unchanged')
    for i=1,2 do
        check(S.Rebuild().ok,'rebuild after rejected import succeeds')
        local roll=S.db.roll[S.DayKey(now-120*86400)][char][1]
        check(roll.bought==10 and roll.spent==1000 and roll.sold==2,'rebuild cannot inflate archived totals')
    end
    check(T.Import(current).imported==1,'retained-day transactions may still import')
    local mixed=T.Import(payload)
    check(not mixed.ok and mixed.imported==0 and mixed.skipped==1 and #rows()==1,'rejection reports duplicates while appending no pending rows')
end)

test('future schemas remain read only',function()
    MerchantMasterLedgerDB={schema=2}; S.Init(); check(S.readOnly and S.Append({type='REPAIR',total=-1})==nil,'unknown future schema protected')
end)
test('replay preserves quest inputs, crafted inputs, loot cash and external basis ordering',function()
    add('AH_BUY',1,4,-400,now-2)
    add('WRIT_TURNIN',1,1,0,now-1,{reqItemID=0,reqQty=0})
    add('CRATE_TURNIN',1,1,0,now,{bundles={{itemID=1,qty=1}}})
    S.AddBasis(econ,2,2,80)
    add('CRAFT',3,1,0,now,{reagents={{itemID=2,qty=1}}})
    S.AddLoot(0,'Money','Test',7)
    local fix=add('ADJUST',0,0,1,now)
    S.AddBasis(econ,3,1,60)
    check(S.Correct(fix.extra.eid,{action='delete'}).ok,'correction succeeds')
    check(S.Basis(econ,1)==1 and S.Basis(econ,2)==1 and S.Basis(econ,3)==2,'writ/crate/craft inputs consumed exactly once')
    check(select(2,S.Basis(econ,3))==50,'external basis after same-time craft retains order')
    check(S.db.stats.recon[char].recorded==-393,'loot cash retained in reconciliation')
end)
test('same-second reconciliation checkpoint excludes already settled cash',function()
    S.InitRecon(char,1000); add('REPAIR',0,0,-10); S.ReconcileGold(char,990)
    local row=add('REPAIR',0,0,-20)
    check(S.Correct(row.extra.eid,{action='edit',total=-30}).ok,'repair corrected')
    check(S.db.stats.recon[char].recorded==-30,'cash before checkpoint not counted again')
end)
test('auction reconciliation remains closed through later correction',function()
    add('AH_POST',1,1,-10,now-100,{auctionID=77}); S.PruneMissingLots(char,{}, {},now)
    local repair=add('REPAIR',0,0,-20)
    check(S.Correct(repair.extra.eid,{action='edit',total=-30}).ok,'repair corrected after AH reconciliation')
    check(#S.Lots(char,1)==0,'missing auction stays closed')
end)
test('historical corrections recompute downstream COGS on pre-existing tsm-flagged rows',function()
    MerchantMasterLedgerDB={schema=1,seed={tsm={at=now}},basis={[econ]={[1]={qty=1,avg=100}}},days={[S.DayKey(now-100)]={r={
        {time=now-100,char=char,econ=econ,type='AH_BUY',itemID=1,qty=2,unit=100,total=-200,where='Auction House',extra={tsm=1,seller='Seller'}},
        {time=now-90,char=char,econ=econ,type='AH_SELL',itemID=1,qty=1,unit=300,total=285,cogs=100,where='Auction House',extra={tsm=1,gross=300,fee=15,buyer='Buyer'}},
    }}}}
    S.Init()
    local list=rows(); check(list[2].cogs==100,'initial historical cost')
    check(S.Correct(S.DayKey(now-100)..':1',{action='edit',total=-400,unit=200}).ok,'historical buy corrected')
    check(rows()[2].cogs==200,'historical downstream cost recalculated')
    check(select(2,S.Basis(econ,1))==200,'remaining basis recalculated')
end)
test('legacy upgrade preserves unjournaled loot basis during corrections',function()
    MerchantMasterLedgerDB={schema=1,days={[S.DayKey()]={r={{time=now,char=char,econ=econ,type='REPAIR',itemID=0,qty=0,unit=0,total=-10,where='Vendor',extra={}}}}},
        basis={[econ]={[2]={qty=3,avg=0}}},loot={[S.DayKey()]={[char]={['2|Mob|Test']=3}}}}
    S.Init(); check(S.Correct(S.DayKey()..':1',{action='edit',total=-20}).ok,'legacy correction succeeds')
    check(S.Basis(econ,2)==3,'legacy unjournaled loot retained')
end)
test('transfer origins are distinct from local identities and preserve equal-time order',function()
    assert(loadfile(root..'Analytics/Transfer.lua'))('MerchantMaster',host); local T=host.Analytics.Transfer
    for i=1,8 do add('ADJUST',0,0,i) end
    add('AH_BUY',1,2,-200); local sale=add('AH_SELL',1,1,300)
    local payload=T.ExportBundle({itemID=1})
    local own=T.Import(payload); check(own.ok and own.imported==0 and own.skipped==2,'self-import skipped')
    fresh(); check(T.Import(payload).imported==2,'new account accepts bundle')
    local list=rows(); check(list[2].type=='AH_SELL' and list[2].cogs==100 and S.Basis(econ,1)==1,'same-time ordering survives e9/e10')
    local localRow=add('REPAIR',0,0,-5); check(localRow.extra.eid~=list[1].extra.eid,'imported and local event IDs distinct')
    check(S.Correct(localRow.extra.eid,{action='delete'}).ok and #rows()==2,'local correction targets correct event')
end)
test('separate older transfer bundle recomputes an already imported sale',function()
    assert(loadfile(root..'Analytics/Transfer.lua'))('MerchantMaster',host); local T=host.Analytics.Transfer
    add('AH_BUY',1,2,-200,now-100); add('AH_SELL',1,1,300,now)
    local buy=T.ExportBundle({type='buys'}); local sell=T.ExportBundle({type='sells'})
    fresh(); check(T.Import(sell).imported==1 and rows()[1].cogs==25,'sale starts estimated')
    check(T.Import(buy).imported==1,'older buy imported')
    local list=rows(); check(list[2].cogs==100 and S.Basis(econ,1)==1,'cross-bundle replay repairs sale basis')
end)
test('transfer append failure restores database and notifications atomically',function()
    assert(loadfile(root..'Analytics/Transfer.lua'))('MerchantMaster',host); local T=host.Analytics.Transfer
    add('AH_BUY',1,2,-200,now-100); add('AH_SELL',1,1,300,now)
    local payload=T.ExportBundle({}); fresh(); local original=S.Append; local calls=0; local originalRoot=S.db; local v=S.version
    S.Append=function(row) calls=calls+1; if calls==2 then error('synthetic append failure') end; return original(row) end
    local ok,result=pcall(T.Import,payload); S.Append=original
    check(ok and not result.ok and result.imported==0,'import errors returned as failed result')
    check(S.db==originalRoot and MerchantMasterLedgerDB==originalRoot and #rows()==0 and next(S.db.basis)==nil,'rollback preserves root identity and all data')
    check(S.version==v and not S._appending and next(S.db.stats.importedOrigins)==nil,'rollback restores flags and dedupe')
end)
test('destroyed basis conserves copper and retains allocation weights through corrections',function()
    local buy=add('AH_BUY',1,1,-1,now-2)
    local destroyed=add('DESTROY',1,1,0,now-1,{spellID=13262,outputs='2:1:1;3:1:1',nonCash=true})
    check(destroyed.cogs==1 and S.Basis(econ,1)==0,'known source basis consumed')
    check(select(2,S.Basis(econ,2))==0 and select(2,S.Basis(econ,3))==1,'last output receives exact copper remainder')
    check(S.Correct(buy.extra.eid,{action='edit',total=-100,unit=100}).ok,'source buy corrected')
    check(select(2,S.Basis(econ,2))==50 and select(2,S.Basis(econ,3))==50,'original weights retained rather than rounded allocation')
    local sum=select(2,S.Basis(econ,2))+select(2,S.Basis(econ,3)); check(sum==100,'output basis conserves corrected cost')
end)
test('unmodified Model all-time totals survive raw retention',function()
    assert(loadfile(root..'Analytics/Model.lua'))('MerchantMaster',host); local M=host.Analytics.Model
    add('AH_BUY',1,4,-400,now-86400); add('AH_SELL',1,2,600,now-86400,{gross=600,fee=0})
    S.AddLoot(2,'Mob','Test',3,{time=now-86400}); S.AddLoot(0,'Money','Test',7,{time=now-86400})
    local before=M.Compute('overview',{period='all',knownCostOnly=false})
    check(S.PruneBefore(S.DayKey()).ok,'raw retention succeeds')
    M.Invalidate(); local after=M.Compute('overview',{period='all',knownCostOnly=false})
    check(after.kpis.profit==before.kpis.profit and after.kpis.salesGross==before.kpis.salesGross,'existing Model profit and revenue continuous')
    check(after.kpis.lootValue==before.kpis.lootValue,'existing Model all-time loot value continuous')
    M.Invalidate(); local recent=M.Compute('overview',{period='today',knownCostOnly=false})
    check(recent.kpis.lootValue==0,'archive does not enter recent periods')
    check(M.Compute('ledger',{period='all',knownCostOnly=false}).rows~=nil,'legacy ledger safely reads aggregate projection')
end)
test('same-time accounts have distinct portable origins without client random API',function()
    assert(loadfile(root..'Analytics/Transfer.lua'))('MerchantMaster',host); local T=host.Analytics.Transfer
    add('REPAIR',0,0,-10); local a=T.ExportBundle({})
    fresh(); add('REPAIR',0,0,-20); local b=T.ExportBundle({})
    fresh(); check(T.Import(a).imported==1 and T.Import(b).imported==1,'different accounts do not collide at same second')
    check(#rows()==2,'both distinct histories imported')
end)
test('legacy opening inference reverses surviving external basis journal',function()
    MerchantMasterLedgerDB={schema=1,basis={[econ]={[3]={qty=3,avg=260/3}}},
        days={[S.DayKey()]={r={
            {time=now-2,char=char,econ=econ,type='CRAFT',itemID=3,qty=1,unit=0,total=0,cogs=100,where='Craft',extra={}},
            {time=now,char=char,econ=econ,type='ADJUST',itemID=0,qty=0,unit=0,total=1,where='Test',extra={}},
        }}},basisEvents={{time=now-1,econ=econ,itemID=3,qty=2,paid=160,order=1}}}
    S.Init(); check(S.Correct(S.DayKey()..':2',{action='delete'}).ok,'legacy correction with surviving journal succeeds')
    check(S.Basis(econ,3)==3 and math.abs(select(2,S.Basis(econ,3))-260/3)<0.00001,'external journal not counted twice')
end)
test('legacy historical seed residual follows corrected purchase price',function()
    MerchantMasterLedgerDB={schema=1,seed={tsm={at=now}},basis={[econ]={[1]={qty=1,avg=100}}},days={[S.DayKey()]={r={
        {time=now-2,char=char,econ=econ,type='AH_BUY',itemID=1,qty=2,unit=100,total=-200,where='AH',extra={tsm=1}},
        {time=now-1,char=char,econ=econ,type='AH_SELL',itemID=1,qty=1,unit=300,total=285,cogs=100,where='AH',extra={tsm=1,gross=300,fee=15}},
    }}}}
    S.Init(); check(S.Correct(S.DayKey()..':1',{action='edit',total=-400,unit=200}).ok,'legacy TSM buy corrected')
    check(rows()[2].cogs==200 and select(2,S.Basis(econ,1))==200,'legacy seeded residual follows historical price edit')
end)
test('legacy quest turn-ins consume inputs again after purchase correction',function()
    for _,typ in ipairs({'WRIT_TURNIN','CRATE_TURNIN'}) do
        MerchantMasterLedgerDB={schema=1,basis={[econ]={[1]={qty=1,avg=100}}},days={[S.DayKey()]={r={
            {time=now-2,char=char,econ=econ,type='AH_BUY',itemID=1,qty=2,unit=100,total=-200,where='AH',extra={}},
            {time=now-1,char=char,econ=econ,type=typ,itemID=1,qty=1,unit=0,total=0,cogs=100,where='Quest',extra={reqItemID=0,reqQty=0}},
        }}}}
        S.Init(); check(S.Correct(S.DayKey()..':1',{action='edit',total=-400,unit=200}).ok,'legacy quest purchase corrected')
        check(S.Basis(econ,1)==1 and rows()[2].cogs==200,'legacy quest consumes corrected input basis')
    end
end)
test('accounting generations distinguish wealth from every accounting mutation',function()
    local notify=S.onChange; local kinds={}
    S.onChange=function(_,kind) kinds[#kinds+1]=kind end
    local function mutation(fn,label)
        local before=S.accountingVersion; fn(); check(S.accountingVersion>before,label..' advances accounting generation')
    end
    mutation(function() add('AH_BUY',1,5,-500) end,'transactions and coverage')
    local before,legacy=S.accountingVersion,S.version
    S.SaveSnapshot(char,S.DayKey(),{gold=100,items=20,listed=0})
    check(S.accountingVersion==before and S.version>legacy,'wealth advances only compatibility version')
    check(kinds[#kinds]=='snapshot','wealth subscribers receive snapshot kind')
    mutation(function() S.AddBasis(econ,1,1,100) end,'external basis additions')
    mutation(function() S.ConsumeBasis(econ,1,1) end,'external basis consumption')
    mutation(function() S.PostLot(char,econ,1,1,200,5,now-120,'Item',42) end,'external lots')
    mutation(function() S.PruneMissingLots(char,{},{}) end,'lot pruning')
    mutation(function() S.Rebuild() end,'replay')
    mutation(function() S.RecordError('AH_BUY','synthetic') end,'capture error state')
    mutation(function() S.ResetErrors() end,'disabled-state reset')
    check(kinds[#kinds]=='accounting','accounting subscribers receive accounting kind')
    S.onChange=notify
end)
test('random-enchant suffix fallback resolves without TSM while exact base items with of stay intact',function()
    local oldMap=host.ITEM_IDS_BY_NAME
    local oldInstant=_G.GetItemInfoInstant
    local oldCItem=_G.C_Item
    TradeSkillMasterDB=nil
    host.ITEM_IDS_BY_NAME={
        ['Green Lens']=10504,
        ['Flask of Supreme Power']=13512,
        ['Flask']=99999,
        ['Ring of Protection']=99123,
    }
    _G.GetItemInfoInstant=nil; _G.C_Item=nil
    check(S.ResolveItemIDByName(char,'Flask of Supreme Power')==13512,'exact match resolves Flask of Supreme Power without suffix stripping')
    check(S.ResolveItemIDByName(char,'Green Lens of the Eagle')==10504,'of the ... suffix strips cleanly to Green Lens 10504 without TSM')
    check(S.ResolveItemIDByName(char,'Green Lens of Stamina')==10504,'of ... suffix strips cleanly to Green Lens 10504 without TSM')
    check(S.ResolveItemIDByName(char,'Ring of Protection of the Owl')==99123,'multi-of base item strips only trailing random-enchant suffix')
    host.ITEM_IDS_BY_NAME={}
    _G.GetItemInfoInstant=function(nm) if nm=='Green Lens' then return 10504 end end
    S.Init()
    check(S.ResolveItemIDByName(char,'Green Lens of the Bear')==10504,'suffix fallback resolves through GetItemInfoInstant when catalog misses')
    _G.GetItemInfoInstant=nil
    S.IndexItemName('Green Lens of the Whale',10504)
    check(S.ResolveItemIDByName(char,'Green Lens of the Whale')==10504,'fast suffixed name index resolves immediately')
    -- Non-recipe multi-"of" BoE sibling suffix resolves via persisted variant lot.baseName after /reload (empty suffixedNameIndex, no catalog, no TSM)
    S.PostLot(char,econ,77777,1,25000,150,now-3600,'Wand of Eventide of the Eagle',9901,'Wand of Eventide')
    -- Normal non-variant "X of Y" lot MUST NOT hijack unrelated "X of Z" items or poison suffixedNameIndex!
    S.PostLot(char,econ,13452,1,45000,150,now-3600,'Elixir of Mongoose',9902)
    S.Init() -- simulates /reload wiping in-memory suffixedNameIndex while keeping DB.lots
    check(S.ResolveItemIDByName(char,'Wand of Eventide of the Owl')==77777,'non-recipe BoE sibling suffix resolves from persisted variant lot.baseName after reload without TSM')
    check(S.ResolveItemIDByName(char,'Elixir of Forever Power')==0,'unrelated Elixir of Mongoose lot cannot hijack Elixir of Forever Power')
    check(S.suffixedNameIndex['Elixir of Forever Power']==nil,'failed unrelated lookup does not poison suffixedNameIndex')
    check(S.ResolveItemIDByName(char,'Elixir of Mongoose')==13452,'exact match on Elixir of Mongoose lot still resolves to 13452')
    host.ITEM_IDS_BY_NAME=oldMap
    _G.GetItemInfoInstant=oldInstant
    _G.C_Item=oldCItem
end)
test('CloseUnits matches suffixed AH_SELL by lot.name before FIFO',function()
    add('AH_POST',10504,1,-150,now-5400,{name='Green Lens of the Whale',variant='Green Lens of the Whale',auctionID=901})
    -- Set posted unit prices equal (17000c) at distinct timestamps: Whale @ T-5400, Eagle @ T-1800
    S.Lots(char,10504)[1].unit=17000
    S.PostLot(char,econ,10504,1,17000,150,now-1800,'Green Lens of the Eagle',902)
    add('AH_SELL',10504,1,16300,now,{gross=17000,fee=850,depositReturned=150,saleAt=now,name='Green Lens of the Eagle',variant='Green Lens of the Eagle'})
    local remaining=S.Lots(char,10504)
    check(#remaining==1 and remaining[1].name=='Green Lens of the Whale','selling Eagle closes Eagle lot and keeps Whale lot open')
    local r=S.db.roll[S.DayKey()][char][10504]
    check(r.dtUnits==1 and r.dtSum==1800,'dt uses matched Eagle lot postedAt (1800s) instead of older Whale lot (5400s)')
end)
test('Store.Init DB swap advances all versions and invalidates cached Model queries',function()
    assert(loadfile(root..'Analytics/Model.lua'))('MerchantMaster',host)
    local M=host.Analytics.Model
    add('AH_SELL',10504,7,119000,now,{gross=125000,fee=6000})
    local beforeItems=M.Compute('items',{period='7d',knownCostOnly=false})
    check(beforeItems.rows and #beforeItems.rows==1 and beforeItems.rows[1].sold==7,'initial DB populates cached 7d items query')
    local v,av,sv,gen=S.version,S.accountingVersion,S.ahSalesVersion,M.generation
    MerchantMasterLedgerDB={}
    S.Init()
    check(S.version>v and S.accountingVersion>av and S._trackedAccountingVersion==S.accountingVersion and S.ahSalesVersion>sv,'DB swap advances version, accountingVersion, and ahSalesVersion')
    check((M.generation or 0)>(gen or 0),'DB swap invalidates Analytics.Model cache generation')
    local afterItems=M.Compute('items',{period='7d',knownCostOnly=false})
    check(afterItems.rows and #afterItems.rows==0,'Model.Compute reflects swapped empty DB without stale cached sales')
end)
test('native Trade and COD ledger rows preserve zero AH fee and counterparties',function()
    add('TRADE_BUY',12360,2,-200000,now-86400,{seller='SellerA'})
    add('COD_BUY',12360,1,-110000,now-86400,{seller='SellerB'})
    add('TRADE_SELL',12360,1,260000,now-43200,{gross=260000,fee=0,buyer='BuyerA'})
    add('COD_SELL',12360,1,270000,now-43200,{gross=270000,fee=0,buyer='BuyerB'})
    local tradeBuy,codBuy,tradeSell,codSell
    for _,r in ipairs(rows()) do
        if r.type=='TRADE_BUY' then tradeBuy=r
        elseif r.type=='COD_BUY' then codBuy=r
        elseif r.type=='TRADE_SELL' then tradeSell=r
        elseif r.type=='COD_SELL' then codSell=r end
    end
    check(tradeBuy and tradeBuy.total==-200000 and tradeBuy.extra.seller=='SellerA','native Trade buy preserved')
    check(codBuy and codBuy.total==-110000 and codBuy.extra.seller=='SellerB','native COD buy preserved')
    check(tradeSell and tradeSell.total==260000 and (tradeSell.extra.fee or 0)==0 and tradeSell.extra.buyer=='BuyerA','native Trade sale has zero AH cut')
    check(codSell and codSell.total==270000 and (codSell.extra.fee or 0)==0 and codSell.extra.buyer=='BuyerB','native COD sale has zero AH cut')
end)
test('Store.craftYieldVersion advances only on RecordCraftYield and DB swap',function()
    local y0,s0,a0=S.craftYieldVersion,S.ahSalesVersion,S.accountingVersion
    add('AH_BUY',10504,2,-2000)
    check(S.craftYieldVersion==y0,'AH_BUY does not advance craftYieldVersion')
    add('AH_SELL',10504,1,1500,now,{gross=1500,fee=75})
    check(S.craftYieldVersion==y0 and S.ahSalesVersion>s0,'AH_SELL advances ahSalesVersion without advancing craftYieldVersion')
    S.AddLoot(10504,'Mob','Zone',2)
    check(S.craftYieldVersion==y0,'AddLoot does not advance craftYieldVersion')
    S.SaveSnapshot(char,S.DayKey(),{gold=500,items=100,listed=0})
    check(S.craftYieldVersion==y0,'SaveSnapshot does not advance craftYieldVersion')
    local sBefore=S.ahSalesVersion
    local rec=S.RecordCraftYield(3946,4378,5,1,{5})
    check(rec~=nil and S.craftYieldVersion==y0+1,'RecordCraftYield advances craftYieldVersion by 1')
    check(S.ahSalesVersion==sBefore and S.accountingVersion>a0,'RecordCraftYield leaves ahSalesVersion unchanged while advancing accountingVersion')
    local yBeforeRebuild=S.craftYieldVersion
    S.Rebuild()
    check(S.craftYieldVersion==yBeforeRebuild,'Store.Rebuild preserves craftYieldVersion')
    MerchantMasterLedgerDB={}
    S.Init()
    check(S.craftYieldVersion>yBeforeRebuild,'Store.Init DB swap advances craftYieldVersion')
end)
test('DISENCHANT_BROKEN attributes profit to broken item without double-counting on shard sale',function()
    local buy=add('AH_BUY',101,1,-10000,now-3)
    local broken=add('DISENCHANT_BROKEN',101,1,0,now-2,{spellID=13262,deGroup='de:test:101',estValue=18992,outputs='102:1:18992',nonCash=true})
    local recv=add('DISENCHANT_RECEIVE',102,1,18992,now-2,{spellID=13262,deGroup='de:test:101',srcItemID=101,srcQty=1,allocBasis=18992,marketValue=18992,nonCash=true})
    check(broken.cogs==10000 and broken.profit==8992,'DISENCHANT_BROKEN records 8992c profit on broken item')
    check(S.Basis(econ,101)==0 and S.Basis(econ,102)==1 and select(2,S.Basis(econ,102))==18992,'broken item basis cleared and shard basis set to estValue')
    local sale=add('AH_SELL',102,1,18992,now-1,{gross=20000,fee=1008})
    check(sale.cogs==18992,'selling shard at estValue yields zero duplicate profit on shard')
    local packDay=S.DayKey(now)
    local dayTbl=S.db.days[packDay]
    dayTbl.s=S.PackRows(dayTbl.r); dayTbl.r=nil
    S.Rebuild()
    check(S.Basis(econ,101)==0 and S.Basis(econ,102)==0,'Store.Rebuild replays packed DISENCHANT_BROKEN and DISENCHANT_RECEIVE cleanly')
end)
print(string.format('Accounting store: %d cases, %d assertions, 0 failures',cases,assertions))
