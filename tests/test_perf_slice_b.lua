local addon=(((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local checks=0
local function check(ok,msg) checks=checks+1; assert(ok,msg) end
local function load(name,ns) assert(loadfile(addon..name))('MerchantMaster',ns) end
local ns,queue,calls={},{},{}
local catalog={}
for i=1,55 do catalog[i]={recipe={id=i}} end
ns.RecipeStats={GetCatalog=function() return catalog end,Get=function(r)
    calls[r.id]=(calls[r.id] or 0)+1; return {id=r.id}
end}
load('SuperListModel.lua',ns)
local ctx={dataset='one',defer=function(fn) queue[#queue+1]=fn end}
local completed,progress=0,0
local function onProgress(_,done) check(done>=progress,'progress never resets');progress=done end
local function onComplete() completed=completed+1 end
local cancel,state=ns.SuperListModel.Start(ctx,onProgress,onComplete)
table.remove(queue,1)()
check(state and state.index>1 and state.index<=#catalog,'partial model state is returned')
local firstRow=state.rows[1]
local duplicate,same=ns.SuperListModel.Start(ctx,onProgress,onComplete,state)
check(same==state and #queue==1,'duplicate running start does not enqueue a second pass')
local _,implicit=ns.SuperListModel.Start(ctx,onProgress,onComplete)
check(implicit==state and #queue==1,'same-context duplicate start is idempotent without explicit resume state')
cancel()
local paused=progress
cancel,state=ns.SuperListModel.Start(ctx,onProgress,onComplete,state)
while #queue>0 do table.remove(queue,1)() end
check(state.rows[1]==firstRow and progress>paused,'resume preserves row objects and moves forward')
for i=1,#catalog do check(calls[i]==1,'recipe evaluated once after resume: '..i) end
check(completed==1,'completion publishes once')
ns.SuperListModel.Start(ctx,onProgress,onComplete,state)
check(completed==1 and #queue==0,'completed version never republishes')
local oldState=state
ctx={dataset='two',defer=ctx.defer}
cancel,state=ns.SuperListModel.Start(ctx,nil,onComplete,state)
check(state~=oldState,'different dataset cannot reuse economics')
while #queue>0 do table.remove(queue,1)() end
check(completed==2,'new dataset publishes once')
catalog={}
ns.SuperListModel.Start({defer=ctx.defer},nil,onComplete)
while #queue>0 do table.remove(queue,1)() end
check(completed==3,'empty dataset completes once')
catalog={{recipe={id=1}},{recipe={id=2}}}
cancel=ns.SuperListModel.Start({defer=ctx.defer},function() cancel() end,onComplete)
while #queue>0 do table.remove(queue,1)() end
check(completed==3,'cancelling inside progress prevents completion')
print('PASS: Slice B resumable model '..checks..' assertions')

-- Real recipe-cache domains and cleanup, without the host invalidation wrapper.
local statsNS={RECIPES={},WRITS={},Analytics={Store={version=1,accountingVersion=1}},priceCacheEpoch=1}
local builds,depth,banks=0,0,{}
statsNS.GetRecipeSourceBucket=function() return 'vendor' end
statsNS.BeginEval=function(bank) depth=depth+1; local b=bank or {};banks[#banks+1]=b;return b end
statsNS.EndEval=function() depth=depth-1 end
statsNS.BuildRecipeRow=function(r)
    builds=builds+1
    if r.fail then error('recipe failure') end
    return {recipe=r,name=r.name,craftAbility={known=false,howShort='Vendor',vendorCopperCost=0},sellable=true}
end
statsNS.ItemName=function(_,fallback) return fallback end
statsNS.GetRecipeWowheadURL=function() return 'url' end
load('RecipeStats.lua',statsNS)
local stats,sc=statsNS.RecipeStats,{economy='one'}
local recipe={name='Example',outputItemID=1}
local row=stats.Get(recipe,sc)
stats.Invalidate('ownership')
check(stats.Get(recipe,sc)==row,'unchanged ownership notifications retain cache')
statsNS.Analytics.Store.version=2
stats.Invalidate('snapshot')
check(stats.Get(recipe,sc)==row,'wealth snapshots preserve recipe rows')
local previousBank=banks[#banks]
statsNS.priceCacheEpoch=2
check(stats.Get(recipe,sc)~=row and banks[#banks]~=previousBank,'price version replaces economics and bank')
row=stats.Get(recipe,sc)
statsNS.Analytics.Store.accountingVersion=2
check(stats.Get(recipe,sc)~=row,'accounting change replaces economics')
local callerBank={}
local explicitContext={economy='one',priceBank=callerBank}
stats.Get(recipe,explicitContext)
statsNS.priceCacheEpoch=3
stats.Get(recipe,explicitContext)
check(banks[#banks]~=callerBank,'caller-supplied bank is not reused across a changed price version')
local ok=pcall(stats.Get,{name='broken',fail=true},sc)
check(not ok and depth==0,'failed recipe closes its evaluation')
local metadataRow={recipe={outputItemID=1,name='Old'},name='Old',ownedOutputQty=0,sellable=true,vendorSell=0}
statsNS.ItemName=function() return 'Resolved' end
statsNS.ItemIcon=function() return 123 end
statsNS.IsItemSellable=function() return true end
statsNS.GetVendorSellPrice=function() return nil end
check(not stats.RepairItems({metadataRow},sc,{[1]=true}),'metadata-only resolution preserves economic version')
check(metadataRow.name=='Resolved' and metadataRow.icon==123,'metadata repair updates same row object')
statsNS.IsItemSellable=function() return false end
check(stats.RepairItems({metadataRow},sc,{[1]=true}),'resolved binding creates economic update')
check(stats.RepairItems({{recipe={reagents={{itemID=2}}}}},sc,{[2]=true}),'reagent metadata can require revaluation')
local favorCalls=0
statsNS.BuildCrateRows=function() favorCalls=favorCalls+1;return {},{pricePerToken=5} end
local normalBuild=statsNS.BuildRecipeRow
statsNS.BuildRecipeRow=function(r) local result=normalBuild(r);result.craftAbility.vendorFavorCost=2;return result end
stats.Invalidate('prices')
local favorContext={economy='one'}
stats.Get({name='Favor one'},favorContext);stats.Get({name='Favor two'},favorContext)
check(favorCalls==1,'Favor warm-up reused for accepted context')
print('PASS: Slice B recipe cache '..checks..' assertions')

-- Exercise the real UI provider with queued timers, independent of legacy host setup.
local function widget()
    local w={scripts={},shown=true}
    local noop=function() end
    setmetatable(w,{__index=function(_,key) return noop end})
    function w:SetText(value) self.text=value end
    function w:GetText() return self.text end
    function w:GetWidth() return 100 end
    function w:GetFont() return 'Fonts\\FRIZQT__.TTF',12,'' end
    function w:GetStringWidth() return #(self.text or '')*6 end
    function w:SetScript(key,fn) self.scripts[key]=fn end
    function w:HookScript(key,fn) self.scripts[key]=fn end
    function w:Hide() self.shown=false;if self.scripts.OnHide then self.scripts.OnHide(self) end end
    function w:CreateFontString() return widget() end
    function w:CreateTexture() return widget() end
    return w
end
queue={};calls={};catalog={}
for i=1,55 do catalog[i]={recipe={id=i}} end
local u={RecipeStats={GetCatalog=function() return catalog end,Get=function(r)
    calls[r.id]=(calls[r.id] or 0)+1
    return {recipe=r,key=tostring(r.id),name='Recipe '..r.id,craftAbility={},sourceCost={},profit=1}
end,RepairItems=function() return false end},Analytics={Store={version=1,accountingVersion=1}},
    Theme={CreatePlateButton=widget,SkinButton=function() end},Window={LayoutTable=function() end},FormatMoneyCompact=tostring}
CreateFrame=widget
C_Timer={After=function(_,fn) queue[#queue+1]=fn end}
MerchantMasterAPI={RegisterSuperList=function() end}
load('SuperListModel.lua',u);load('UI_SuperList.lua',u)
local displayed,visible={},true
local box={GetHeight=function() return 1 end,ForEachFrame=function() end}
local tableUI={scrollBox=box,columns={},colX={},headerBtns={},headerBar=widget(),updateHeaders=function() end,setRows=function(r) displayed=r end}
local host={rowHeight=20,sidebar={sellBtn=widget(),recCraftFilterBtn=widget(),recDemandFilterBtn=widget(),bisOnlyCheck=widget()},
    isActive=function() return visible end,findLabel=function() return '' end,
    createSortableTable=function(_,_,_,columns)
        for i,col in ipairs(columns) do
            tableUI.columns[i]={}; for k,v in pairs(col) do tableUI.columns[i][k]=v end
            tableUI.colX[i]=i*100; tableUI.headerBtns[i]={fs=widget()}
        end
        return tableUI
    end,getSort=function() return {col='profit'} end,statusText=widget()}
local p=u.SuperList
p.Create(widget(),host)
local c={db={},counts={},profMap={},repState={},econInfo={effectiveKey='one'}}
local function drain() local n=0;while #queue>0 do n=n+1;assert(n<1000,'bounded UI work');table.remove(queue,1)() end end
p.Refresh(c);table.remove(queue,1)();table.remove(queue,1)()
local partial=calls[1];check(partial==1,'UI starts actual bounded evaluation')
for i=1,15 do p.Invalidate('snapshot');p.Invalidate('ownership');p.Invalidate('trainer');p.Invalidate('items',{[99999]=true});p.Refresh(c) end
p.Cancel();drain()
check(calls[21]==nil,'cancel also suppresses a queued reconciliation while host remains active')
p.Refresh(c);drain()
check(#displayed==55,'paused UI finishes the same version')
for i=1,55 do check(calls[i]==1,'UI evaluates each recipe once despite invalidation storm: '..i) end
local oldRows=displayed
p.Cancel();p.Refresh(c);drain()
check(displayed[1]==oldRows[1],'completed rows survive reopen')
u.Analytics.Store.version=2;p.Invalidate('snapshot');p.Refresh(c);drain()
check(calls[1]==1,'wealth snapshot does not replace completed UI data')
u.Analytics.Store.accountingVersion=2;p.Refresh(c)
check(displayed==oldRows or displayed[1]==oldRows[1],'old rows stay displayed during replacement')
drain();check(calls[1]==2,'accounting change computes one replacement')
check(displayed[1]~=oldRows[1],'replacement publishes fresh row objects')
c.statsContext={ownedCounts=c.counts,profMap=c.profMap,repState=c.repState,economy='one',revision=1,hostRevision=1}
p.Refresh(c);drain()
local hostBefore=calls[1]
for i=1,10 do c.statsContext.revision=i;c.statsContext.hostRevision=i;p.Invalidate('ownership');p.Refresh(c) end
drain();check(calls[1]==hostBefore,'host notification counters excluded from dataset identity')
for i=1,10 do p.Invalidate('sellers') end
drain();check(calls[1]==hostBefore+1,'seller updates coalesce into one new dataset')
c.db.superListSources={};c.search='not-found';p.Refresh(c);drain()
check(#displayed==0 and calls[1]==hostBefore+1,'search changes presentation only')
print('PASS: Slice B provider '..checks..' assertions')

-- Reuse only the shared host boot fixture; legacy stock-pricing tests run separately.
local scratch=((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local live = dofile(scratch .. 'host_fixture.lua')
debugprofilestop=function() return os.clock()*1000 end
local app,provider=live.app,live.SuperList
queue={};C_Timer.After=function(_,fn) queue[#queue+1]=fn end
local nativeBox=app.ui.recipesTable.scrollBox
nativeBox.SetDataProvider=function(self,dp) self._dp=dp end
nativeBox.ForEachFrame=function() end
app.activeTab='recipes';app.panel:Show()
provider.Invalidate()
local context={db=MerchantMasterDB,counts={},profMap={},repState={standing=4},econInfo=live.CurrentEconomyInfo(),charKey=app.charKey}
context.statsContext=app.getRecipeStatsContext(context)
local rowBuilds,realBuild={},live.BuildRecipeRow
local realStart,acceptedState=live.SuperListModel.Start
live.SuperListModel.Start=function(...)
    local cancel,state=realStart(...);acceptedState=state;return cancel,state
end
live.BuildRecipeRow=function(recipe,...)
    rowBuilds[recipe]=(rowBuilds[recipe] or 0)+1;return realBuild(recipe,...)
end
provider.Refresh(context)
while #queue>0 and not next(rowBuilds) do table.remove(queue,1)() end
check(next(rowBuilds)~=nil,'real host begins partial evaluation')
local forwarded,forwardReason,forwardIDs=0
local realInvalidate=provider.Invalidate
provider.Invalidate=function(reason,ids)
    forwarded=forwarded+1;forwardReason=reason;forwardIDs=ids;return realInvalidate(reason,ids)
end
app.scheduleRecipeRefresh=function() end
local ids={[99999999]=true}
app.invalidateRecipeStats('items',ids)
check(forwarded==1 and forwardReason=='items' and forwardIDs==ids,'host forwards reason/items exactly once')
for i=1,15 do app.invalidateRecipeStats('ownership');app.invalidateRecipeStats('trainer');provider.Refresh(context) end
provider.Cancel();drain()
provider.Refresh(context);drain()
local recipes=live.RecipeStats.GetCatalog()
for _,entry in ipairs(recipes) do check(rowBuilds[entry.recipe]==1,'real recipe computed once through host pause/storm') end
local shown=nativeBox._dp:GetCollection()
check(#shown==#recipes,'real host commits complete catalog')
check(acceptedState.favorWarmed and type(acceptedState.favorWarmMS)=='number','first Favor cost measured separately on accepted dataset')
print(string.format('MEASURE SUPERLIST_FIRST_FAVOR_MS=%.3f',acceptedState.favorWarmMS))
provider.Cancel();provider.Refresh(context);drain()
for _,entry in ipairs(recipes) do check(rowBuilds[entry.recipe]==1,'real completed version reused on reopen') end
local sample=shown[1]
context.search='zzzz-no-recipe';provider.Refresh(context);drain()
check(#nativeBox._dp:GetCollection()==0,'real host search only filters retained rows')
local pinNotifications=0
local prevMapPins = app.mapPinsProvider
MerchantMasterAPI.RegisterMapPins({
    apiVersion=1,
    version='1.0.0-test',
    Init=function() end,
    OnEvent=function() end,
    InvalidateOwnership=function() pinNotifications=pinNotifications+1 end,
    GetPinCount=function() return 0 end,
})
if app.CommitMailboxSnapshot then
    app.CommitMailboxSnapshot({names={['Recipe: Synthetic']=1},itemIDs={['Recipe: Synthetic']=99999999},items={[99999999]=1}})
    local firstNotifications=pinNotifications
    app.CommitMailboxSnapshot({names={['Recipe: Synthetic']=1},itemIDs={['Recipe: Synthetic']=99999999},items={[99999999]=1}})
    check(firstNotifications==1 and pinNotifications==1,'committed ownership reaches map once; identical snapshot is inert')
end
app.mapPinsProvider=prevMapPins
live.BuildRecipeRow=realBuild
print('PASS: Slice B real host '..checks..' assertions')
