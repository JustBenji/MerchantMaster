-- Synthetic WP11 model contracts.
local root=(((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local now=1794484800; time=function() return now end; date=os.date
local char="Normal-Horde-Tester"; local host={app={charKey=char},DetectActiveEconomy=function()return "Normal-Horde"end,
 GetItemMarketPrice=function()return 100 end,GetVendorSellPrice=function()return 5 end,ItemName=function(id)return "Item "..id end}
MerchantMasterAPI={ns=host}; MerchantMasterDB={chars={[char]={}}}
assert(loadfile(root.."Analytics/Store.lua"))("MerchantMaster",host)
assert(loadfile(root.."Analytics/Inventory.lua"))("MerchantMaster",host)
assert(loadfile(root.."Analytics/Model.lua"))("MerchantMaster",host)
local S,M=host.Analytics.Store,host.Analytics.Model; S.Init()
local assertions=0; local function check(v,m) assertions=assertions+1; assert(v,m) end
local function add(t,q,total,at,extra) return S.Append({type=t,itemID=101,qty=q,total=total,time=at or now,unit=q>0 and math.abs(total)/q or 0,extra=extra or {}}) end
add("AH_BUY",10,-1000,now-86400,{seller="Seller"})
add("AH_SELL",4,760,now,{gross=800,fee=40,buyer="Buyer"})
add("AH_EXPIRE",2,0,now,{})
local r=M.GetItemStats(101,{period="all"})
check(r and r.bought==10 and r.avgBuy==100,"historical average buy")
check(r.curBasis==100 and r.smartAvgBuy==100,"remaining and smart basis")
check(r.avgSell==200 and r.netAvgSell==190 and r.avgProfit~=nil,"sale metrics")
check(r.saleRate==2/3 and r.sellThrough==nil,"180 day sale rate is separate")
check(r.lastSoldTo=="Buyer" and r.lastBuyFrom=="Seller","counterparties available")
check(M.GetPriceSource("AvgSell",101,{period="all"})==200,"named source exported")
local q=M.QueryLedger({period="all"},0,1); check(q.totalMatched==3 and #q.rows==1 and q.hasMore,"ledger pagination")
local q2=M.QueryLedger({period="all"},0,math.huge); check(q2.totals.qty==16 and #q2.rows==3,"ledger complete totals")
check(M.GetItemDetail(101,{period="all"}).windows.all.sold==4,"item detail windows")
check(M.GetItemStats(999,{period="all"})==nil,"missing item returns nil")
add("AH_BUY",2,-400,now,{seller="Seller B"})
add("AH_SELL",1,190,now,{gross=200,fee=10,buyer="Buyer B"})
add("AH_SELL",1,290,now,{gross=300,fee=10,buyer="Buyer C"})
add("AH_EXPIRE",1,0,now,{})
add("AH_CANCEL",1,0,now,{})
r=M.GetItemStats(101,{period="all"})
check(r.minBuy==100 and r.maxBuy==200 and r.minSell==200 and r.maxSell==300,"buy and sell extrema")
check(r.lastBuyFrom=="Seller B" and r.lastSoldTo=="Buyer C" and r.avgProfit~=nil and r.profitPct~=nil,"last transaction and margin fields")
check(r.saleRate==2/3,"sale rate counts sales and expires, excluding cancels")
check(r.expSinceSale==1 and r.canSinceSale==1,"since sale expiry and cancel counters")
check(#M.GetItemDetail(101,{period="all"}).topBuyers<=3 and #M.GetItemDetail(101,{period="all"}).topSellers<=3,"top counterparties capped at three")
add("VENDOR_SELL",1,25,now,{source="Vendor",variant="quality:2"})
local vendor=M.Compute("items",{period="all",source="Vendor",knownCostOnly=false})
check(#vendor.rows==1 and vendor.rows[1].sold==1 and vendor.rows[1].gross==25,"source filter recomputes row totals")
local grouped=M.Compute("items",{period="all",groupBy="specific"})
check(#grouped.rows>=2,"variant grouping splits item variants")
add("AH_BUY",1,-80,now,{itemLevel=10,seller="Level Seller"})
add("AH_SELL",1,150,now,{gross=160,fee=10,itemLevel=10,buyer="Level Buyer"})
add("AH_BUY",1,-120,now,{itemLevel=20,seller="Level Seller"})
add("AH_SELL",1,230,now,{gross=240,fee=10,itemLevel=20,buyer="Level Buyer"})
local levels=M.Compute("items",{period="all",groupBy="level",knownCostOnly=false})
local levelRows={}; for _,v in ipairs(levels.rows) do if v.itemID==101 then levelRows[v.itemLevel]=v end end
check(levelRows[10] and levelRows[20],"level grouping creates independent item-level rows")
check(levelRows[10].avgSell==160 and levelRows[20].avgSell==240,"level-specific averages use group totals")
check(levelRows[10].avgProfit==nil or levelRows[10].avgProfit~=levelRows[20].avgProfit,"level-specific ratios are recomputed")
local vendorArray=M.Compute("items",{period="all",sources={"Vendor"},knownCostOnly=false})
local ahArray=M.Compute("items",{period="all",sources={"AH"},knownCostOnly=false})
check(vendorArray.rows[1].gross==25 and ahArray.rows[1].gross>25,"array source values produce distinct cached results")
local vendorDetail=M.GetItemDetail(101,{period="all",source="Vendor"})
check(vendorDetail.windows.all.sold==1 and #vendorDetail.transactions==1,"item detail preserves source filter across windows and history")
local previousQuality=_G.C_Item
_G.C_Item={GetItemQualityByID=function() return 2 end}
local rare=M.Compute("items",{period="all",rarities={[2]=true},knownCostOnly=false})
local common=M.Compute("items",{period="all",rarities={[1]=true},knownCostOnly=false})
check(#rare.rows>0 and #common.rows==0,"rarity sets filter items and invalidate cached results")
_G.C_Item=previousQuality
local allPages=M.QueryLedger({period="all"},0,math.huge)
for i=1,501 do add("ADJUST",0,0,now,{source="Synthetic"}) end
local p1=M.QueryLedger({period="all"},0,250); local p2=M.QueryLedger({period="all"},250,250); local all=M.QueryLedger({period="all"},0,math.huge)
check(all.totalMatched>=500 and #p1.rows==250 and #p2.rows==250,"ledger supports histories over 500 rows")
check(p1.totals.net==p2.totals.net and all.totals.net==p1.totals.net,"ledger totals independent of page size")
check(p1.rows[1].eid~=p2.rows[1].eid,"ledger pages have no duplicate boundary row")
local noData=M.GetPriceSource("AvgSell",999,{period="all"}); check(noData==nil,"unknown item source returns nil")
check(M.GetPriceSource("SaleRate",101,{period="all"})==75,"named unfiltered sale rate includes vendor sales and uses 0..100 scale")
S.db.inventory={[char]={econ="Normal-Horde",updatedAt=now-8*86400,bags={[101]=5},bank={[101]=2},mail={},gear={[101]=1}}}
local matrix=M.GetInventoryMatrix({wealthMode=true,valSource="market"}); local invRow
for _,v in ipairs(matrix.rows) do if v.itemID==101 then invRow=v end end
check(invRow and invRow.totalQty==8 and invRow.totalValue==705,"inventory valuation separates gear vendor cap")
check(invRow.stale==true,"inventory matrix marks stale snapshots")

-- Every named transaction source maps to the intended type family.
local sourceCases={
 {"AH","AH_SELL"},{"Vendor","VENDOR_SELL"},{"Craft","CRAFT"},{"COD","COD_SELL"},
 {"Trade","TRADE_SELL"},{"Mail","POSTAGE"},{"Quest/Loot","QUEST_MONEY"},
}
for i,case in ipairs(sourceCases) do
 local id=500+i; S.Append({char=char,type=case[2],itemID=id,qty=1,total=20,time=now,extra={source=case[1]}})
 local got=M.Compute("items",{period="all",source=case[1],knownCostOnly=false})
 local found=false; for _,item in ipairs(got.rows) do if tonumber(item.itemID)==id then found=true end end
 check(found,"source family included: "..case[1])
end

-- Character selection and faction filters compose instead of overriding each other.
local alt="Normal-Horde-Alt"; MerchantMasterDB.chars[alt]={faction="Horde",name="Alt"}
S.Append({char=alt,type="AH_SELL",itemID=777,qty=1,total=99,time=now,extra={gross=100,buyer="Alt Buyer"}})
local horde=M.Compute("items",{period="all",chars={[char]=true,[alt]=true},faction="Horde",knownCostOnly=false})
local alliance=M.Compute("items",{period="all",chars={[char]=true,[alt]=true},faction="Alliance",knownCostOnly=false})
local function hasID(result,id) for _,item in ipairs(result.rows) do if tonumber(item.itemID)==id then return true end end return false end
check(hasID(horde,777),"multi-character faction composition keeps matching alt")
check(not hasID(alliance,777),"multi-character faction composition excludes other faction")
check(not hasID(M.Compute("items",{period="all",char=char,chars={[alt]=true},knownCostOnly=false}),777),"single char composes with chars set")

-- Specific-variant drilldown, counterparty filters, and query caching.
local variantDetail=M.GetItemDetail("101|quality:2",{period="all"})
check(variantDetail.itemID==101 and #variantDetail.transactions>0,"detail accepts item variant key")
local buyerSearch=M.Compute("items",{period="all",search="Buyer C",knownCostOnly=false})
check(#buyerSearch.rows==1 and buyerSearch.rows[1].itemID==101,"buyer names participate in item keyword search")
local vendorAgain=M.QueryLedger({period="all",source="Vendor"},0,20)
local ahAgain=M.QueryLedger({period="all",source="AH"},0,20)
check(vendorAgain.totalMatched~=ahAgain.totalMatched,"ledger cache separates source filters")

-- Explicit ledger type maps, counterparty search, and grouped auction counts.
local expired=M.QueryLedger({period="all",types={AH_EXPIRE=true,AH_CANCEL=true}},0,math.huge)
check(expired.totalMatched==3,"ledger type sets select expires and cancels")
local byBuyer=M.QueryLedger({period="all",search="Buyer"},0,math.huge)
check(byBuyer.totalMatched>=4,"ledger search matches counterparties")
local groupedAuctions=M.QueryLedger({period="all",type="all",coalesce=true},0,math.huge)
local auctionTotal=0; for _,row in ipairs(groupedAuctions.rows) do auctionTotal=auctionTotal+(row.auctionsCount or 0) end
check(auctionTotal>=7,"coalesced ledger preserves auction event counts")
check(groupedAuctions.totals.profit~=groupedAuctions.totals.net,"ledger profit excludes fees and cost basis correctly")

-- Price-source defaults use active economy and lifetime metrics.
check(M.GetPriceSource("avgBuy",101)==M.GetItemStats(101,{char=char,econ="Normal-Horde",period="all"}).avgBuy,"default price source scopes active economy")
check(M.GetPriceSource("unknown",101)==nil,"unknown named price source returns nil")
check(M.GetSaleHint(101).expSinceSale==M.GetItemStats(101,{char=char,econ="Normal-Horde",period="180d"}).expSinceSale,"sale hint uses active economy")

-- Overview retains KPI compatibility and produces pace, prior period, wealth and activity fields.
S.Append({char=char,type="AH_SELL",itemID=888,qty=1,total=500,time=now,extra={gross=500,buyer="Single"}})
S.Append({char=char,type="AH_SELL",itemID=889,qty=10,total=2000,time=now,extra={gross=2000,buyer="Bulk"}})
local overview=M.Compute("overview",{period="all",knownCostOnly=false})
check(overview.kpis.profit~=nil and overview.kpis.sales~=nil and overview.kpis.purchases~=nil,"overview keeps legacy KPI fields")
check(overview.kpis.daysInPeriod>=1 and overview.kpis.avgDailySales~=nil,"overview calculates days and daily pace")
check(overview.kpis.prevProfit~=nil and (overview.kpis.profitDeltaPct~=nil or overview.kpis.prevProfit==0),"overview calculates previous period delta safely")
check(overview.kpis.high52w~=nil and overview.kpis.low52w~=nil,"overview reports 52 week wealth bounds")
check(#overview.activityFeed>0 and overview.activityFeed[1].soldQty>0,"overview activity contains transaction quantities")
check(overview.topSingleSale.itemID==888 and overview.topSingleSale.unit==500,"overview top sale ranks unit price over stack total")
check(overview.topSingleBuy~=nil and overview.topSingleBuy.unit>0,"overview reports highest unit price buy")

-- Inventory matrix applies character/faction selectors and includes guild only on request.
S.db.inventory[alt]={econ="Normal-Horde",updatedAt=now,bags={[902]=4},bank={},mail={},gear={},boundBags={},boundBank={}}
local byAlt=M.GetInventoryMatrix({char="all",chars={[alt]=true},valSource="vendor"})
local altInventory; for _,row in ipairs(byAlt.rows) do if row.itemID==902 then altInventory=row end end
check(altInventory and altInventory.totalQty==4,"inventory matrix handles char all with chars set")
local byAlliance=M.GetInventoryMatrix({faction="Alliance",valSource="vendor"})
local excludedAlt; for _,row in ipairs(byAlliance.rows) do if row.itemID==902 then excludedAlt=row end end
check(excludedAlt==nil,"inventory matrix filters characters by faction")
S.db.guildInventory={Guild={econ="Normal-Horde",updatedAt=now,tabItems={[903]=3}}}
local noGuild=M.GetInventoryMatrix({valSource="vendor"}); local withGuild=M.GetInventoryMatrix({valSource="vendor",includeGuild=true})
local function findMatrix(result,id) for _,row in ipairs(result.rows) do if row.itemID==id then return row end end end
check(findMatrix(noGuild,903)==nil,"guild-only items stay hidden when guild inclusion is off")
check(findMatrix(withGuild,903) and findMatrix(withGuild,903).totalQty==3,"guild-only items appear when guild inclusion is on")

-- Complete item-detail windows and top counterparties remain populated.
local drill=M.GetItemDetail(101,{period="all"})
check(drill.windows.d7~=nil and drill.windows.d30~=nil and drill.windows.all~=nil,"detail exposes all requested windows")
check(drill.windows.all.sold>=drill.windows.d7.sold,"all-time window includes recent sales")
check(#drill.topBuyers<=3 and #drill.topSellers<=3,"detail counterparties stay capped at three")
check(drill.curBasis~=nil and drill.smartAvgBuy~=nil,"detail exposes current and smart basis")
check(drill.minBuy==80 and drill.maxBuy==200,"detail reports lifetime purchase range")
check(drill.minSell~=nil and drill.maxSell~=nil,"detail reports lifetime sale range")

-- Filtered summary totals match the rows exposed to the caller.
local filtered=M.Compute("items",{period="all",source="Vendor",knownCostOnly=false})
local sumQty,sumGross,sumProfit=0,0,0; for _,item in ipairs(filtered.rows) do sumQty=sumQty+item.sold; sumGross=sumGross+item.gross; sumProfit=sumProfit+item.profit end
check(filtered.totals.qtySold==sumQty,"filtered totals quantity is from returned matching scope")
check(filtered.totals.gross==sumGross,"filtered totals gross is complete")
check(filtered.totals.profit==sumProfit,"filtered totals profit matches item rows")
check(M.QueryLedger({period="all",types={AH_EXPIRE=true}},0,1).totals.qty==3,"ledger page totals include all matching expires")
check(M.QueryLedger({period="all",types={AH_EXPIRE=true}},1,1).totals.qty==3,"ledger totals do not change with cursor")
check(M.QueryLedger({period="all",types={AH_EXPIRE=true}},0,1).totalMatched==2,"ledger type filters return complete match count")
check(M.GetPriceSource("NumExpires",101,{period="all"})==M.GetItemStats(101,{period="all"}).expSinceSale,"named expiration source returns expiration count")
check(M.GetPriceSource("CurBasis",101,{period="all"})==M.GetItemStats(101,{period="all"}).curBasis,"named basis source returns copper per unit")
check(M.GetPriceSource("SmartAvgBuy",101,{period="all"})==M.GetItemStats(101,{period="all"}).smartAvgBuy,"named smart average source returns copper per unit")
check(M.PeriodBounds("3d",now)==S.DayKey(now-2*86400),"extended three day period bounds are supported")
check(M.PeriodBounds("60d",now)==S.DayKey(now-59*86400),"extended sixty day period bounds are supported")
check(M.GetPriceSource("MinBuy",101,{period="all"})==M.GetItemStats(101,{period="all"}).minBuy,"min buy named source returns transaction copper")
check(M.GetPriceSource("MaxSell",101,{period="all"})==M.GetItemStats(101,{period="all"}).maxSell,"max sell named source returns transaction copper")
host.RECIPES_BY_OUTPUT={[101]={{profession="Alchemy"}}}
local alchemyItems=M.Compute("items",{period="all",prof="alchemy",knownCostOnly=false})
check(hasID(alchemyItems,101),"profession filter matches recipe output index")
check(not hasID(M.Compute("items",{period="all",prof="Blacksmithing",knownCostOnly=false}),101),"profession filter excludes unmatched output")
local alchemyLedger=M.QueryLedger({period="all",prof="Alchemy"},0,math.huge)
check(alchemyLedger.totalMatched>0,"ledger profession filter uses output index")
local coalescedExpired=M.QueryLedger({period="all",types={AH_EXPIRE=true},coalesce=true},0,math.huge)
check(coalescedExpired.totalMatched>=1 and coalescedExpired.totals.qty==3,"coalescing keeps matched records and quantity totals")
local inventoryVendor=M.GetInventoryMatrix({valSource="vendor"}); local inventoryMarket=M.GetInventoryMatrix({valSource="market"})
local debugVendor=findMatrix(inventoryVendor,902); check(debugVendor and debugVendor.totalValue==20,"vendor valuation uses vendor unit price")
local debugMarket=findMatrix(inventoryMarket,902); check(debugMarket and debugMarket.totalValue==400,"market valuation uses market unit price")
local inventoryBasis=M.GetInventoryMatrix({valSource="basis"})
local debugBasis=findMatrix(inventoryBasis,902); check(debugBasis and debugBasis.unitValue==0,"basis valuation returns zero when no item basis exists")
S.db.intradaySnaps=S.db.intradaySnaps or {}; S.db.intradaySnaps[S.DayKey()]={{time=now,gold=123}}
check(M.Compute("overview",{period="today",knownCostOnly=false}).intradayWealth~=nil,"overview exposes intraday wealth snapshots")
local ratioStats=M.GetItemStats(101,{period="all"})
check(ratioStats.profitPct==ratioStats.profit/ratioStats.cogs,"profit percentage is recomputed from profit and cogs")
check(ratioStats.avgProfit==ratioStats.profit/ratioStats.sold,"average profit is per sold unit")
check(ratioStats.netAvgSell==(ratioStats.gross-ratioStats.fee)/ratioStats.sold,"net average sell subtracts auction fees")
check(M.GetPriceSource("SaleRate",999,{period="all"})==nil,"sale rate is nil for unknown item")
local today=S.DayKey(now); S.db.roll[today]=S.db.roll[today] or {}; S.db.roll[today][char]=S.db.roll[today][char] or {}
S.db.roll[today][char][990]={gross=100,sold=1,estUnits=1}; M.Invalidate()
check(M.GetItemStats(990,{period="all",knownCostOnly=false})~=nil,"item stats include estimated item when requested")
check(M.GetItemStats(990,{period="all",knownCostOnly=true})==nil,"item stats honor estimated cost exclusion")
S.Append({char=char,type="AH_SELL",itemID=915,qty=1,total=190,time=now,unit=200,extra={gross=200,fee=10,auctionsCount=2,buyer="Lot Buyer"}})
S.Append({char=char,type="AH_SELL",itemID=915,qty=1,total=190,time=now,unit=200,extra={gross=200,fee=10,auctionsCount=3,buyer="Lot Buyer"}})
local groupedLot=M.QueryLedger({period="all",coalesce=true,search="Lot Buyer"},0,math.huge)
check(groupedLot.totalMatched==2 and #groupedLot.rows==1,"coalesced ledger combines compatible sale events")
check(groupedLot.rows[1].auctionsCount==5,"coalesced auction count sums source event counts")
check(groupedLot.totals.fee==20 and groupedLot.totals.net==380,"coalesced fee and net totals preserve source values")
S.Append({char=char,type="AH_EXPIRE",itemID=916,qty=1,total=0,time=now,extra={depLost=15,tsm=true}})
local depositLoss=M.QueryLedger({period="all",types={AH_EXPIRE=true}},0,math.huge)
check(depositLoss.totals.profit==-15,"ledger expiration profit includes lost deposit "..tostring(depositLoss.totals.profit))
-- Legacy roll-only and summary-backed days merge the same item's profit numerically.
local overviewBeforeMixed=M.Compute("overview",{period="all",knownCostOnly=false}).kpis.profit
local mixedLegacyDay=S.DayKey(now-500*86400); local mixedSummaryDay=S.DayKey(now-499*86400); local mixedItem=12001
S.db.roll[mixedLegacyDay]=S.db.roll[mixedLegacyDay] or {}; S.db.roll[mixedLegacyDay][char]=S.db.roll[mixedLegacyDay][char] or {}
S.db.roll[mixedLegacyDay][char][mixedItem]={gross=40000,fee=5,cogs=5,depLost=0,sold=1,bought=0,spent=0}
S.db.roll[mixedSummaryDay]=S.db.roll[mixedSummaryDay] or {}; S.db.roll[mixedSummaryDay][char]=S.db.roll[mixedSummaryDay][char] or {}
S.db.roll[mixedSummaryDay][char][mixedItem]={gross=60020,fee=10,cogs=10,depLost=0,sold=1,bought=0,spent=0}
S.db.dayStats=S.db.dayStats or {}; S.db.dayStats[mixedLegacyDay]=nil
S.db.dayStats[mixedSummaryDay]={[char]={profitDelta=60000,salesGross=60020,buySpent=0,depLost=0,adjustTotal=0}}
M.Invalidate()
local mixedOverview=M.Compute("overview",{period="all",knownCostOnly=false})
check(mixedOverview.kpis.profit-overviewBeforeMixed==99990,"overview sums KPI profit across roll-only and summary-backed days")
local mixedTop
for _,item in ipairs(mixedOverview.top) do if item.itemID==mixedItem then mixedTop=item end end
check(mixedTop and mixedTop.profit==99990,"overview sums same-item profit across both day schemas")
-- Profession filters accept the recipe.prof schema for arrays and singleton output entries.
local recipeArrayItem,recipeSingleItem=12002,12003
host.RECIPES_BY_OUTPUT[recipeArrayItem]={{prof="Alchemy"}}
host.RECIPES_BY_OUTPUT[recipeSingleItem]={prof="Alchemy"}
S.Append({char=char,type="AH_SELL",itemID=recipeArrayItem,qty=1,total=40,time=now,extra={gross=40}})
S.Append({char=char,type="AH_SELL",itemID=recipeSingleItem,qty=1,total=60,time=now,extra={gross=60}})
local profItems=M.Compute("items",{period="all",prof="Alchemy",knownCostOnly=false})
check(hasID(profItems,recipeArrayItem) and hasID(profItems,recipeSingleItem),"profession item filter accepts recipe.prof array and singleton entries")
local profLedger=M.QueryLedger({period="all",prof="Alchemy"},0,math.huge)
local profArraySeen,profSingleSeen=false,false
for _,row in ipairs(profLedger.rows) do
 if row.itemID==recipeArrayItem then profArraySeen=true elseif row.itemID==recipeSingleItem then profSingleSeen=true end
end
check(profArraySeen and profSingleSeen,"profession ledger filter accepts recipe.prof array and singleton entries")
-- Same item sales stay scoped by economy while defaults aggregate only active-economy characters.
local scopeHordeAlt="Normal-Horde-ScopeAlt"; local scopeAlliance="Normal-Alliance-ScopeAlt"; local scopeItem=12004
MerchantMasterDB.chars[scopeHordeAlt]={name="Horde Scope",faction="Horde"}
MerchantMasterDB.chars[scopeAlliance]={name="Alliance Scope",faction="Alliance"}
S.Append({char=char,econ="Normal-Horde",type="AH_SELL",itemID=scopeItem,qty=1,total=100,time=now,extra={gross=100}})
S.Append({char=scopeHordeAlt,econ="Normal-Horde",type="AH_SELL",itemID=scopeItem,qty=1,total=300,time=now,extra={gross=300}})
S.Append({char=scopeAlliance,econ="Normal-Alliance",type="AH_SELL",itemID=scopeItem,qty=1,total=900,time=now,extra={gross=900}})
check(M.GetPriceSource("AvgSell",scopeItem)==200,"default price source averages same-item sales across active-economy alts only")
local allianceScope=M.Compute("items",{period="all",econ="Normal-Alliance",knownCostOnly=false})
local allianceRow
for _,item in ipairs(allianceScope.rows) do if item.itemID==scopeItem then allianceRow=item end end
check(allianceRow and allianceRow.sold==1 and allianceRow.gross==900 and allianceRow.avgSell==900,
    "explicit economy filter keeps same-item sale metrics within Alliance")
-- Overview activity uses the latest seven active days per real character, independent of KPI period.
local activityChar="Normal-Horde-ActivityTester"; local peerChar="Normal-Horde-ActivityPeer"; local activityItem=12030
MerchantMasterDB.chars[activityChar]={name="Activity",faction="Horde"}
MerchantMasterDB.chars[peerChar]={name="Activity Peer",faction="Horde"}
for _,offset in ipairs({0,2,4,6,8,10,12,14}) do
 S.Append({char=activityChar,econ="Normal-Horde",type="AH_SELL",itemID=activityItem,qty=1,total=10,time=now-offset*86400,extra={gross=10}})
end
S.Append({char=peerChar,econ="Normal-Horde",type="AH_SELL",itemID=activityItem,qty=1,total=20,time=now,extra={gross=20}})
M.Invalidate()
local activityToday=M.Compute("overview",{period="today",char=activityChar,knownCostOnly=false})
check(#activityToday.activityFeed==7,"activity feed keeps seven active days across gaps beyond seven calendar days")
check(activityToday.activityFeed[1].day==S.DayKey(now) and activityToday.activityFeed[7].day==S.DayKey(now-12*86400),
    "activity feed sorts recent active days and omits the eighth older day")
check(activityToday.kpis.sales==10,"today KPI totals exclude older days shown in the activity feed")
local allToday=M.Compute("overview",{period="today",knownCostOnly=false})
local todayChars,hasAllActivity={},false
for _,entry in ipairs(allToday.activityFeed) do
 if entry.day==S.DayKey(now) then todayChars[entry.char]=true end
 if entry.char=="all" then hasAllActivity=true end
end
check(todayChars[activityChar] and todayChars[peerChar] and not hasAllActivity,
    "unrestricted overview emits separate real-character activity rows")

-- Day summaries without item rolls still appear; unknown gold delta stays unknown.
local cashOnlyChar="Normal-Horde-CashOnly"; local cashOnlyDay=S.DayKey(now-86400)
S.db.dayStats[cashOnlyDay]=S.db.dayStats[cashOnlyDay] or {}
S.db.dayStats[cashOnlyDay][cashOnlyChar]={adjustTotal=-25}
M.Invalidate()
local cashOnlyOverview=M.Compute("overview",{period="all",char=cashOnlyChar,knownCostOnly=false})
check(not (S.db.roll[cashOnlyDay] and S.db.roll[cashOnlyDay][cashOnlyChar]),"cash-only fixture has no item roll")
check(#cashOnlyOverview.activityFeed==1 and cashOnlyOverview.activityFeed[1].char==cashOnlyChar
    and cashOnlyOverview.activityFeed[1].day==cashOnlyDay,"cash-only dayStats entry appears in activity")
check(cashOnlyOverview.activityFeed[1].netGold==nil and cashOnlyOverview.kpis.unexplained==-25,
    "unknown activity gold stays nil while cash adjustment remains accounted")

local snapshotChar="Normal-Horde-SnapshotDelta"; local snapshotPrev=S.DayKey(now-2*86400); local snapshotDay=S.DayKey(now-86400)
S.db.dayStats[snapshotDay]=S.db.dayStats[snapshotDay] or {}
S.db.dayStats[snapshotDay][snapshotChar]={adjustTotal=0}
S.db.snaps[snapshotChar]={
 [snapshotPrev]={gold=500,econ="Normal-Horde"},
 [snapshotDay]={gold=730,econ="Normal-Horde"},
}
M.Invalidate()
local oldClock=_G.time
_G.time=function(value) if type(value)=="table" then return os.time(value) end return now end
local snapshotOverview=M.Compute("overview",{period="all",char=snapshotChar,knownCostOnly=false})
_G.time=oldClock
check(#snapshotOverview.activityFeed==1 and snapshotOverview.activityFeed[1].netGold==230,
    "activity net gold uses adjacent character snapshot delta when dayStats lacks goldDelta")
-- Wealth inventory prices gear and bound units at vendor value, with active faction/character selectors.
local boundItem=12040
MerchantMasterDB.chars[char]={name="Tester",faction="Horde"}
local mainInventory=S.db.inventory[char]
mainInventory.bags[boundItem]=5; mainInventory.bank[boundItem]=2; mainInventory.mail[boundItem]=1; mainInventory.gear[boundItem]=2
mainInventory.boundBags={[boundItem]=2}; mainInventory.boundBank={[boundItem]=1}
local altInventory=S.db.inventory[alt]
altInventory.bags[boundItem]=1; altInventory.gear[boundItem]=1
altInventory.boundBags={[boundItem]=1}; altInventory.boundBank={}
S.db.guildInventory.Guild.tabItems[boundItem]=3
M.Invalidate()
local hordeWealth=M.GetInventoryMatrix({char="all",faction="Horde",wealthMode=true,valSource="market"})
local hordeBound=findMatrix(hordeWealth,boundItem)
check(hordeBound and hordeBound.totalQty==12 and hordeBound.totalValue==535,
    "Horde wealth values seven bound/gear units at vendor and five unbound units at market")
local mainWealth=M.GetInventoryMatrix({char="all",chars={[char]=true},faction="Horde",wealthMode=true,valSource="market"})
local mainBound=findMatrix(mainWealth,boundItem)
check(mainBound and mainBound.totalQty==10 and mainBound.totalValue==525,
    "char all plus character/faction selectors scopes bound inventory to the selected character")
local guildWealth=M.GetInventoryMatrix({char="all",includeGuild=true,wealthMode=true,valSource="market"})
local guildBound=findMatrix(guildWealth,boundItem)
check(guildBound and guildBound.totalQty==15 and guildBound.totalValue==835,
    "optional guild units add market value without changing character-bound valuation")
-- Item detail honors row-level specific variant and item-level selection keys.
local explicitVariant=M.GetItemDetail({itemID=101,variant="quality:2"},{period="all"})
check(explicitVariant.windows.all.sold==1 and explicitVariant.windows.all.totalSales==25,
    "table-key specific variant detail has only its own sales")
check(#explicitVariant.transactions==1 and explicitVariant.transactions[1].type=="VENDOR_SELL",
    "specific variant transaction history excludes other variants")
local explicitLevel=M.GetItemDetail({itemID=101,itemLevel=10},{period="all"})
check(explicitLevel.windows.all.sold==1 and explicitLevel.windows.all.totalSales==160
    and explicitLevel.windows.all.bought==1 and explicitLevel.windows.all.totalSpent==80,
    "item-level detail windows use only the selected item's level")
check(#explicitLevel.transactions==2,"item-level detail history excludes other item levels and base transactions")
-- Same-second buys honor replay order when valuing the one unit still in inventory.
local replayItem=12050
S.Append({char=char,econ="Normal-Horde",type="AH_BUY",itemID=replayItem,qty=1,unit=100,total=-100,time=now,extra={seller="First Seller"}})
S.Append({char=char,econ="Normal-Horde",type="AH_BUY",itemID=replayItem,qty=1,unit=300,total=-300,time=now,extra={seller="Later Seller"}})
S.Append({char=char,econ="Normal-Horde",type="AH_SELL",itemID=replayItem,qty=1,unit=500,total=500,time=now,extra={gross=500}})
S.db.inventory[char].bags[replayItem]=1
local replayStats=M.GetItemStats(replayItem,{char=char,econ="Normal-Horde",period="all"})
check(replayStats.avgBuy==200 and replayStats.curBasis==200 and replayStats.curBasisQty==1 and replayStats.smartAvgBuy==300,
    "same-second smart average selects the higher replay-order buy while historical average and current basis stay weighted")
-- AH source filtering and variant grouping preserve losses from posts and returns.
local lossItem=12060
local function loss(typ,qty,total,extra)
 return S.Append({char=char,econ="Normal-Horde",type=typ,itemID=lossItem,qty=qty,total=total,time=now,extra=extra})
end
loss("AH_BUY",4,-400,{variant="loss",itemLevel=30})
loss("AH_SELL",1,300,{gross=300,variant="loss",itemLevel=30})
loss("VENDOR_SELL",1,700,{gross=700,variant="vendor",itemLevel=40})
loss("AH_POST",1,-15,{auctionID=12060,variant="loss",itemLevel=30})
local expired=loss("AH_EXPIRE",1,0,{auctionID=12060,variant="loss",itemLevel=30})
loss("AH_POST",1,-20,{auctionID=12061,variant="loss",itemLevel=30})
local cancelled=loss("AH_CANCEL",1,-5,{auctionID=12061,variant="loss",itemLevel=30})
check(expired.extra.depLost==15 and cancelled.extra.depLost==25,"loss fixture closes exact deposits and cancellation fee")
-- Legacy raw rows may carry an already-recorded loss on the row or in metadata.
local legacyPost=loss("AH_POST",0,0,{variant="loss",itemLevel=30,depLost=99}); legacyPost.depLost=7
loss("AH_POST",0,0,{variant="loss",itemLevel=30,depLost=9})
for _,groupBy in ipairs({"item","specific","level"}) do
 local result=M.Compute("items",{period="all",source="AH",groupBy=groupBy,knownCostOnly=false})
 local row; for _,entry in ipairs(result.rows) do if entry.itemID==lossItem then row=entry end end
 check(row and row.depLost==56 and row.profit==144,"AH "..groupBy.." profit includes post, expired and cancelled deposits without double counting row metadata")
 check(row.gross==300 and row.sold==1,"AH "..groupBy.." excludes vendor sales")
end

-- Daily rolls retain complete purchase averages and the rolling sale-rate window.
local retentionItem=12062; local oldTime=now-120*86400
local function retain(owner,economy,typ,qty,total,at)
 S.Append({char=owner,econ=economy,type=typ,itemID=retentionItem,qty=qty,total=total,time=at,extra={gross=total>0 and total or nil}})
end
retain(char,"Normal-Horde","AH_BUY",10,-1000,oldTime)
retain(char,"Normal-Horde","AH_SELL",2,400,oldTime)
retain(char,"Normal-Horde","AH_EXPIRE",2,0,oldTime)
retain(char,"Normal-Horde","AH_BUY",2,-600,now)
retain(char,"Normal-Horde","VENDOR_SELL",1,300,now)
retain(char,"Normal-Horde","AH_EXPIRE",1,0,now)
retain(char,"Normal-Horde","AH_SELL",7,1400,now-181*86400)
retain(alt,"Normal-Horde","AH_SELL",9,1800,now)
retain(scopeAlliance,"Normal-Alliance","AH_EXPIRE",9,0,now)
local retentionFilters={period="all",char="all",chars={[char]=true},econ="Normal-Horde",knownCostOnly=false}
local beforeRetention=M.GetItemStats(retentionItem,retentionFilters)
check(beforeRetention.bought==12 and beforeRetention.spent==1600 and beforeRetention.avgBuy==1600/12,"complete purchase average before pruning")
check(beforeRetention.saleRate==1/2,"unfiltered rate includes vendor sale, excludes other characters and sales before the window")
check(M.GetItemStats(retentionItem,{period="all",char=char,source="AH",knownCostOnly=false}).saleRate==2/5,"AH-filtered rate counts only auction sales and expirations")
check(S.PruneBefore(S.DayKey(now-90*86400)).ok,"retention fixture prunes historical raw transactions")
M.Invalidate()
local afterRetention=M.GetItemStats(retentionItem,retentionFilters)
check(afterRetention.bought==beforeRetention.bought and afterRetention.spent==beforeRetention.spent
 and afterRetention.avgBuy==beforeRetention.avgBuy,"pruned purchases keep historical quantities, spending and average")
check(afterRetention.saleRate==beforeRetention.saleRate,"pruned sale and expiry counters keep rolling sale rate")
local allSource=M.GetItemStats(retentionItem,{period="all",char=char,source="all",knownCostOnly=false})
check(allSource.avgBuy==beforeRetention.avgBuy and allSource.saleRate==beforeRetention.saleRate,"all source selector uses complete unfiltered rolls")
check(M.GetItemStats(retentionItem,{period="all",char=char,source="AH",knownCostOnly=false}).saleRate==0,"AH source path continues using surviving source-filtered raw records")
print("PASS accounting model "..assertions.." assertions; ledger rows "..all.totalMatched)

-- Performance regression: simultaneous query signatures must survive alternating callers.
local retained=M.Compute("items",{char="all",econ="Normal-Horde",period="all",knownCostOnly=false})
for i=1,20 do M.GetSaleHint(101); M.GetItemStats(101) end
check(M.Compute("items",{char="all",econ="Normal-Horde",period="all",knownCostOnly=false})==retained,"all-time cache survives recent tooltip queries")
local accountingBefore=S.accountingVersion
S.SaveSnapshot(char,S.DayKey(),{gold=1,items=0,listed=0})
check(S.accountingVersion==accountingBefore,"wealth snapshots preserve accounting generation")
check(M.Compute("items",{char="all",econ="Normal-Horde",period="all",knownCostOnly=false})==retained,"wealth snapshots preserve item aggregates")
print("PASS: Accounting performance cache domains")

-- Deferred index calculations must exactly match synchronous calculations and yield.
local expectedAll=M.GetItemStats(101)
local expectedRecent=M.GetItemStats(101,{char="all",econ="Normal-Horde",period="180d"})
M.Invalidate()
local deferred,steps={},0
local oldTimer=_G.C_Timer
_G.C_Timer={After=function(_,fn) deferred[#deferred+1]=fn end}
local prepared=false
M.PrepareTooltipIndexes(function() prepared=true end)
check(not prepared,"cold aggregate preparation starts asynchronously")
while #deferred>0 do local fn=table.remove(deferred,1); steps=steps+1; fn() end
check(prepared and steps>2,"aggregate worker yields across bounded callbacks")
for _,pair in ipairs({{expectedAll,M.GetItemStats(101)},{expectedRecent,M.GetItemStats(101,{char="all",econ="Normal-Horde",period="180d"})}}) do
    for key,value in pairs(pair[1]) do if type(value)=="number" then check(pair[2][key]==value,"deferred/synchronous parity: "..key) end end
end
_G.C_Timer=oldTimer
print("PASS: Accounting deferred aggregate parity and work slices")

local indexed=M.Compute("items",{char="all",econ="Normal-Horde",period="all",knownCostOnly=false})
local originalRows=indexed.rows; indexed.rows={}
check(M.GetItemStats(101)==indexed.byItemID[101],"item lookup uses its index without traversing result rows")
indexed.rows=originalRows
print("PASS: Accounting item lookup is indexed")

local pinned=M.GetPreparedTooltipStats(101)
for i=1,35 do M.Compute("items",{period="all",search="cache-pressure-"..i}) end
local oldIter=S.IterDays; local indexedTraversals=0
S.IterDays=function(...) indexedTraversals=indexedTraversals+1; return oldIter(...) end
local stillReady=false; M.PrepareTooltipIndexes(function() stillReady=true end)
check(stillReady and M.GetPreparedTooltipStats(101)==pinned and indexedTraversals==0,"tooltip aggregate indexes survive bounded query-cache eviction")
S.IterDays=oldIter
print("PASS: Pinned tooltip indexes survive query cache pressure")

-- Portfolio deduplication on read + seriesOnly listed valuation regression (Model.lua:478)
do
    local dupChar = "Normal-Horde-Forever-DupTest"
    S.SaveSnapshot(dupChar, S.DayKey(), { gold = 1000, items = 900, bags = 600, bank = 300, listed = 0, econ = "Normal-Horde" }, {
        at = now, econ = "Normal-Horde",
        cats = {
            bags = {
                { id = 2447, name = "Peacebloom", qty = 3, unit = 100, total = 300, basis = "Live AH" },
                { id = 2447, name = "Peacebloom", qty = 3, unit = 100, total = 300, basis = "Live AH" },
            },
            bank = {
                { id = 765, name = "Silverleaf", qty = 2, unit = 150, total = 300, basis = "Live AH" },
                { id = 765, name = "Silverleaf", qty = 1, unit = 150, total = 150, basis = "Live AH" },
            },
            mail = {}, gear = {}, listed = {},
        },
    })
    S.PostLot(dupChar, "Normal-Horde", 2447, 4, 500, 10, now - 60, "Peacebloom", 8801)
    M.Invalidate()
    local pf = M.Compute("portfolio", { char = dupChar, period = "30d" })
    local byCat = {}
    for _, c in ipairs(pf.categories or {}) do byCat[c.catKey] = c end
    check(byCat.bags and #byCat.bags.items == 1 and byCat.bags.items[1].qty == 6 and byCat.bags.items[1].total == 600,
        "buildCharWealthDetail deduplicates legacy duplicate bag entries on read")
    check(byCat.bank and #byCat.bank.items == 1 and byCat.bank.items[1].qty == 3 and byCat.bank.items[1].total == 450,
        "buildCharWealthDetail deduplicates legacy duplicate bank entries on read")
    local ov = M.Compute("overview", { char = dupChar, period = "30d", knownCostOnly = false })
    local lastWealth = ov.wealth and ov.wealth[#ov.wealth]
    check(lastWealth and lastWealth.total == 1000 + 900 + 2000,
        "overview seriesOnly portfolio accurately includes live Store.Lots listed value (got " .. tostring(lastWealth and lastWealth.total) .. ")")
    print("PASS: Portfolio wealth deduplication and seriesOnly listed valuation")
end

-- Regression: Portfolio collapses alias charKeys + placeholder key, preserves snap history, and dedupes split gear rows
do
    local heroCanon = "Normal-Horde-ExampleRealm PvE-Hero"
    local heroAlias = "Normal-Horde-Forever-Hero"
    local ghostKey = "Normal-Horde-Forever-Player"
    local prevHostDB = _G.MerchantMasterDB
    local prevHostApp = host.app
    _G.MerchantMasterDB = {
        itemIDs = { ["Serrated Raptor Claw"] = 280805 },
        chars = {
            [heroCanon] = { name = "Hero", economy = "Normal-Horde" },
            [heroAlias] = { name = "Hero", economy = "Normal-Horde" },
        },
    }
    host.app = { charKey = heroCanon }
    local yest = S.DayKey(now - 86400)
    S.SaveSnapshot(heroAlias, yest, { gold = 2500, items = 6199, bags = 0, bank = 0, mail = 0, gear = 6199, listed = 0, econ = "Normal-Horde" }, {
        at = now - 86400, econ = "Normal-Horde",
        cats = { bags = {}, bank = {}, mail = {}, gear = { { id = 280805, name = "Serrated Raptor Claw", qty = 1, unit = 6199, total = 6199, basis = "Vendor (Gear)" } }, listed = {} },
    })
    S.SaveSnapshot(heroCanon, S.DayKey(), { gold = 3000, items = 6199, bags = 0, bank = 0, mail = 0, gear = 6199, listed = 0, econ = "Normal-Horde" }, {
        at = now, econ = "Normal-Horde",
        cats = {
            bags = {}, bank = {}, mail = {},
            gear = {
                { id = 280805, name = "Serrated Raptor Claw", qty = 1, unit = 6199, total = 6199, basis = "Vendor (Gear)", bound = true },
                { id = nil, name = "Serrated Raptor Claw", qty = 1, unit = 6199, total = 6199, basis = "Vendor (Gear)", bound = false },
            },
            listed = {},
        },
    })
    S.SaveSnapshot(ghostKey, S.DayKey(), { gold = 999, items = 500, bags = 500, bank = 0, mail = 0, gear = 0, listed = 0, econ = "Normal-Horde" })
    M.Invalidate()

    local pf = M.Compute("portfolio", { char = "all", econ = "Normal-Horde", period = "30d" })
    local byCat = {}
    for _, c in ipairs(pf.categories or {}) do byCat[c.catKey] = c end
    local heroCount = 0
    for _, bc in ipairs(pf.byChar or {}) do
        if bc.char == heroCanon then heroCount = heroCount + 1 end
        check(bc.char ~= heroAlias and bc.char ~= ghostKey, "Portfolio excludes alias and placeholder keys from byChar")
    end
    check(heroCount == 1, "Portfolio lists canonical Hero character exactly once")
    check(byCat.gear and #byCat.gear.items == 1 and byCat.gear.items[1].itemID == 280805,
        "Equipped Gear is not duplicated across alias charKeys or bound/id splits")
    local pfHero = M.Compute("portfolio", { chars = { [heroCanon] = true, [heroAlias] = true }, econ = "Normal-Horde", period = "30d" })
    check(pfHero.series and #pfHero.series == 2 and pfHero.series[1].day == yest and pfHero.series[1].gold == 2500 and pfHero.series[2].gold == 3000,
        "Portfolio preserves historical snap day from alias charKey on chart series")
    _G.MerchantMasterDB = prevHostDB
    host.app = prevHostApp
    print("PASS: Portfolio canonical char alias collapse and gear dedup")
end

do
    local brokenID, shardID = 12901, 12902
    local prevItemName = host.ItemName
    host.ItemName = function(id)
        if id == brokenID then return "Green Lens" end
        if id == shardID then return "Large Radiant Shard" end
        if id == 12903 then return "Blue Staff" end
        return prevItemName and prevItemName(id) or ("Item #" .. tostring(id))
    end
    local prevOverview = M.Compute("overview", { period = "all", char = char, knownCostOnly = false })
    local baseProfit = prevOverview.kpis.profit or 0

    S.Append({char=char,econ="Normal-Horde",type="AH_BUY",itemID=brokenID,qty=1,unit=10000,total=-10000,time=now})
    S.Append({char=char,econ="Normal-Horde",type="DISENCHANT_BROKEN",itemID=brokenID,qty=1,unit=0,total=0,time=now,
        where="Disenchanting",extra={spellID=13262,deGroup="de:m:1",estValue=20000,outputs="12902:1:20000",nonCash=true}})
    S.Append({char=char,econ="Normal-Horde",type="DISENCHANT_RECEIVE",itemID=shardID,qty=1,unit=10000,total=0,time=now,
        where="From: Green Lens",extra={spellID=13262,deGroup="de:m:1",srcItemID=brokenID,srcName="Green Lens",srcQty=1,allocBasis=10000,marketValue=20000,costCarryover=true,nonCash=true}})
    S.Append({char=char,econ="Normal-Horde",type="AH_SELL",itemID=shardID,qty=1,unit=20000,total=19000,time=now,
        extra={gross=20000,fee=1000}})
    M.Invalidate()

    local items = M.Compute("items", {period="all",char=char,knownCostOnly=false})
    local brokenRow, shardRow
    for _, r in ipairs(items.rows or {}) do
        if r.itemID == brokenID then brokenRow = r elseif r.itemID == shardID then shardRow = r end
    end
    check(brokenRow and brokenRow.profit == 0 and brokenRow.sold == 0,
        "Model Items view keeps 0 direct profit and 0 sold on broken Green Lens (got profit=" .. tostring(brokenRow and brokenRow.profit) .. ")")
    check(brokenRow and brokenRow.deBrokenQty == 1 and brokenRow.deSoldMatsQty == 1 and brokenRow.deIndirectProfit == 9000,
        "Model Items view exposes deBrokenQty=1, deSoldMatsQty=1, deIndirectProfit=+9000c on Green Lens")
    check(brokenRow and brokenRow.deSoldOutputs and #brokenRow.deSoldOutputs == 1 and brokenRow.deSoldOutputs[1].itemID == shardID and brokenRow.deSoldOutputs[1].profit == 9000,
        "Model Items view exposes top sold DE output Large Radiant Shard (+9000c) on Green Lens")
    check(shardRow and shardRow.profit == 9000 and shardRow.deIndirectProfit == 0,
        "Model Items view records real +9000c profit on sold Large Radiant Shard")

    local afterOverview = M.Compute("overview", { period = "all", char = char, knownCostOnly = false })
    check((afterOverview.kpis.profit - baseProfit) == 9000,
        "Total Account Profit increases by exact +9000c with ZERO double-counting (got " .. tostring(afterOverview.kpis.profit - baseProfit) .. ")")

    local detail = M.GetItemDetail(brokenID, { period = "all", char = char })
    check(detail and detail.deBrokenQty == 1 and detail.deSoldMatsQty == 1 and detail.deIndirectProfit == 9000 and #detail.deSoldOutputs == 1,
        "GetItemDetail exposes indirect DE summary for Green Lens")

    local led = M.QueryLedger({char=char,period="all",ledgerPreset="craft",types={CRAFT=true,DESTROY=true,DISENCHANT_BROKEN=true,DISENCHANT_RECEIVE=true}})
    local foundBroken, foundRecv = false, false
    for _, r in ipairs(led.rows or {}) do
        if r.type == "DISENCHANT_BROKEN" and r.itemID == brokenID then
            foundBroken = true
            check(r.profit == 0 and r.typeLabel == "DE Broken", "Ledger DE Broken carries profit=0 (no fake paper profit)")
        elseif r.type == "DISENCHANT_RECEIVE" and r.itemID == shardID then
            foundRecv = true
            check(r.profit == 0 and r.typeLabel == "DE Receive" and r.extra and r.extra.srcItemID == brokenID and r.extra.allocBasis == 10000,
                "Ledger DE Receive carries profit=0, srcItemID, and carried-over allocBasis")
        end
    end
    check(foundBroken and foundRecv and led.totals and led.totals.profit == 0,
        "Ledger craft preset books 0 total profit for DE Broken + DE Receive")

    local allLed = M.QueryLedger({char=char,period="all",search="Green Lens"})
    local foundShardViaDE = false
    for _, r in ipairs(allLed.rows or {}) do
        if r.type == "AH_SELL" and r.itemID == shardID and r.extra and r.extra.deOrigin and r.extra.deOrigin.srcItemID == brokenID then
            foundShardViaDE = true
            check(r.profit == 9000, "Ledger AH_SELL for shard reports real +9000c profit and links via DE: Green Lens")
        end
    end
    check(foundShardViaDE, "Ledger search for Green Lens surfaces linked shard AH_SELL via deOrigin")

    -- Multi-source DE sale prorates indirect profit cleanly across both source items without double-counting
    local staffID = 12903
    S.Append({char=char,econ="Normal-Horde",type="AH_BUY",itemID=brokenID,qty=1,unit=10000,total=-10000,time=now+1})
    S.Append({char=char,econ="Normal-Horde",type="DISENCHANT_BROKEN",itemID=brokenID,qty=1,unit=0,total=0,time=now+1,
        where="Disenchanting",extra={spellID=13262,deGroup="de:m:2",estValue=20000,outputs="12902:1:20000",nonCash=true}})
    S.Append({char=char,econ="Normal-Horde",type="DISENCHANT_RECEIVE",itemID=shardID,qty=1,unit=10000,total=0,time=now+1,
        where="From: Green Lens",extra={spellID=13262,deGroup="de:m:2",srcItemID=brokenID,srcName="Green Lens",srcQty=1,allocBasis=10000,marketValue=20000,costCarryover=true,nonCash=true}})
    S.Append({char=char,econ="Normal-Horde",type="AH_BUY",itemID=staffID,qty=1,unit=14000,total=-14000,time=now+1})
    S.Append({char=char,econ="Normal-Horde",type="DISENCHANT_BROKEN",itemID=staffID,qty=1,unit=0,total=0,time=now+1,
        where="Disenchanting",extra={spellID=13262,deGroup="de:m:3",estValue=20000,outputs="12902:1:20000",nonCash=true}})
    S.Append({char=char,econ="Normal-Horde",type="DISENCHANT_RECEIVE",itemID=shardID,qty=1,unit=14000,total=0,time=now+1,
        where="From: Blue Staff",extra={spellID=13262,deGroup="de:m:3",srcItemID=staffID,srcName="Blue Staff",srcQty=1,allocBasis=14000,marketValue=20000,costCarryover=true,nonCash=true}})
    S.Append({char=char,econ="Normal-Horde",type="AH_SELL",itemID=shardID,qty=2,unit=20000,total=38000,time=now+2,
        extra={gross=40000,fee=2000}})
    M.Invalidate()

    local items2 = M.Compute("items", {period="all",char=char,knownCostOnly=false})
    local lens2, staff2, shard2 = items2.byItemID[brokenID], items2.byItemID[staffID], items2.byItemID[shardID]
    check(lens2 and lens2.deBrokenQty == 2 and lens2.deSoldMatsQty == 2 and lens2.deIndirectProfit == 18000 and lens2.profit == 0,
        "Multi-source DE prorates +9000c second shard to Green Lens (total indirect +18000c, direct profit 0)")
    check(staff2 and staff2.deBrokenQty == 1 and staff2.deSoldMatsQty == 1 and staff2.deIndirectProfit == 5000 and staff2.profit == 0,
        "Multi-source DE prorates +5000c (19000-14000) to Blue Staff (direct profit 0)")
    check(shard2 and shard2.profit == 23000,
        "Shard direct profit equals exact sum of indirect DE profits (9000+9000+5000=23000c)")
    local ov2 = M.Compute("overview", { period = "all", char = char, knownCostOnly = false })
    check((ov2.kpis.profit - baseProfit) == 23000,
        "Total Account Profit matches exact 23000c with zero double-counting across multiple DE sources")

    host.ItemName = prevItemName
end
