local S=((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns, frames = dofile(S .. 'host_fixture.lua')
local n=0; local function check(ok,msg) n=n+1; assert(ok,msg) end
local app=ns.app
check(type(app.getRecipeStatsContext)=='function','host provides shared unfiltered evaluator context')
app.panel:Hide(); app.activeTab='dashboard'
local a=app.getRecipeStatsContext(); local b=app.getRecipeStatsContext()
check(a==b,'unchanged inputs reuse one stable context before list opens')
check(a.search==nil and a.sources==nil and a.knownRecipesOnly==nil,'list filters never leak into trainer valuation')
check(type(a.ownedCounts)=='table' and type(a.profMap)=='table' and type(a.repState)=='table','shared inventory/profession/reputation inputs')
check(a.economy==ns.CurrentEconomyInfo().effectiveKey and a.charKey==app.charKey,'selected economy and character shared')
local oldCut=MerchantMasterDB.applyAHCut; MerchantMasterDB.applyAHCut=oldCut==false
local c=app.getRecipeStatsContext()
check(c~=a and c.applyAHCut~=a.applyAHCut,'settings changes replace context without mutating an in-flight evaluation')
MerchantMasterDB.applyAHCut=oldCut
local oldPrices=MerchantMasterDB.outlierPrices
MerchantMasterDB.outlierPrices={[123]=100}; local first=app.getRecipeStatsContext()
MerchantMasterDB.outlierPrices[123]=200; local second=app.getRecipeStatsContext()
check(second~=first and first.outlierPrices[123]==100 and second.outlierPrices[123]==200,'in-place price edits preserve old snapshot and invalidate next context')
MerchantMasterDB.outlierPrices=oldPrices
local invalidations,forwardedReason=0; local original=ns.SuperList.Invalidate
ns.SuperList.Invalidate=function(reason,...) invalidations=invalidations+1;forwardedReason=reason;return original(reason,...) end
ns.RecipeStats.Invalidate('sellers')
check(forwardedReason=='sellers' and invalidations==1,'seller module invalidation forwards its change domain to retained Super List exactly once')
ns.SuperList.Invalidate=original
check(ns.SellerStats and type(ns.SellerStats.Get)=='function','WP4 seller module integrated in TOC')
check(ns.TrainerStats and ns.TrainerStats.initialized,'WP7 selected-trainer listener initialized at login')
local f=assert(io.open((((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../MerchantMaster.toc"),'r'))
local toc=f:read('*a'); f:close()
check(toc:find('SellerStats.lua',1,true)<toc:find('MarketScan.lua',1,true),'seller state loads before AH queue')
check(toc:find('RecipeStats.lua',1,true)<toc:find('UI_TrainerStats.lua',1,true),'shared stats load before trainer UI')
local queued={}; local after=C_Timer.After
C_Timer.After=function(_,fn) queued[#queued+1]=fn end
local starts=0; local start=ns.SuperListModel.Start
ns.SuperListModel.Start=function(...) starts=starts+1; return start(...) end
local function drain()
    local limit=0
    while #queued>0 do table.remove(queued,1)(); limit=limit+1; assert(limit<10000,'bounded refresh queue') end
end
local function fire(event)
    for _,frame in ipairs(frames) do
        if frame._events[event] and frame._scripts.OnEvent then frame._scripts.OnEvent(frame,event) end
    end
end
ns.SuperList.Invalidate(); app.activeTab='recipes'; app.panel:Show()
while starts==0 and #queued>0 do table.remove(queued,1)() end
check(starts==1,'visible Super List started an incremental build')
for i=1,40 do fire('TRAINER_UPDATE') end
drain()
check(starts==1,'unchanged trainer event storm preserves the visible list without restarting')
check(#app.ui.recipesTable.scrollBox._dp:GetCollection()>0,'trainer invalidation cannot leave list stuck loading')
local beforeSkills=starts
local origGetProfs=ns.GetPlayerProfessions
local mockProfs={}; for k,v in pairs(origGetProfs and origGetProfs() or {}) do mockProfs[k]=v end
ns.GetPlayerProfessions=function()
    local copy={}; for k,v in pairs(mockProfs) do copy[k]=v end; return copy
end
fire('SKILL_LINES_CHANGED'); drain()
check(starts==beforeSkills,'SKILL_LINES_CHANGED noise does not rebuild visible Super List')
local firstKey=next(mockProfs) or 'alchemy'
mockProfs[firstKey]=(tonumber(mockProfs[firstKey]) or 300)+5
fire('SKILL_LINES_CHANGED'); drain()
check(starts==beforeSkills,'skill rank bump patches metadata without rebuilding visible Super List')
mockProfs.jewelcrafting=300
fire('SKILL_LINES_CHANGED'); drain()
check(starts==beforeSkills+1,'learned profession refreshes visible Super List')
ns.GetPlayerProfessions=origGetProfs
app.panel:Hide(); local hiddenStarts=starts
fire('TRAINER_UPDATE'); drain()
check(starts==hiddenStarts,'trainer events do not rebuild a hidden list')
ns.SuperListModel.Start=start; C_Timer.After=after
print('WP6 integration: '..n..' assertions, 0 failures')
