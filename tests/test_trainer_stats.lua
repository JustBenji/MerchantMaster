local addon = (((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local checks = 0
local function check(ok, message) checks=checks+1; assert(ok, message) end
local function eq(a,b,message) check(a==b,message .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end
local secret = setmetatable({}, {__index=function() error('secret indexed') end,
    __tostring=function() error('secret formatted') end, __lt=function() error('secret compared') end})
issecretvalue=function(v) return rawequal(v,secret) end
issecrettable=issecretvalue
local a={s=101,n='Potion',prof='alchemy'}
local b={s=102,n='Potion II',prof='alchemy'}
local duplicate={s=103,n='Duplicate',prof='alchemy'}
local duplicate2={s=104,n='Duplicate',prof='alchemy'}
local ra={spellID=101,name='Potion',prof='alchemy',outputItemID=501}
local rb={spellID=102,name='Potion II',prof='alchemy',outputItemID=502}
local ns={MP={RECIPES={alchemy={a,b,duplicate,duplicate2}},
    RECIPES_BY_SPELL={[101]=a,[102]=b,[103]=duplicate,[104]=duplicate2},
    NAME_TO_PROF_KEY={alchemy='alchemy'}},RECIPES={ra,rb}}
local db={trainerCosts={},trainerReqs={},trainerReqsByName={}}
local filters={available=true,unavailable=false,used=false}
local services={{'Potion','Rank 1','available',101,250},{'Potion','Rank 2','unavailable',102,500},
    {'Duplicate','','available',nil,100},{'Heading','','header'}}
local selection,trade,full=1,true,false
local function rows()
    if full then return services end
    local out={}; for _,r in ipairs(services) do if filters[r[3]] or r[3]=='header' then out[#out+1]=r end end
    return out
end
GetTrainerServiceInfo=function(i) local r=rows()[i]; if r then return r[1],r[2],r[3] end end
GetTrainerServiceCost=function(i) return rows()[i][5] end
GetTrainerServiceSkillReq=function() return 'Alchemy',75 end
GetTrainerServiceLevelReq=function() return 20 end
GetNumTrainerServices=function() return #rows() end
GetTrainerSelectionIndex=function() return selection end
SelectTrainerService=function(i) selection=i end
GetTrainerServiceTypeFilter=function(k) return filters[k] end
SetTrainerServiceTypeFilter=function(k,v) filters[k]=v; selection=1 end
IsTradeskillTrainer=function() return trade end
C_TooltipInfo={GetTrainerService=function(i) return {id=rows()[i][4]} end}
assert(loadfile(addon .. 'TrainerServices.lua'))('MerchantMaster',ns)
ns.TrainerServices.Initialize(function() return db end)
local svc=ns.TrainerServices.Resolve(1)
check(svc and svc.recipe==a and svc.statsRecipe==ra,'tooltip spell identity maps to the shared catalog recipe')
full=true
eq(ns.TrainerServices.Resolve(2).recipe,b,'spell identifies same-name rank')
check(ns.TrainerServices.Resolve(3)==nil,'ambiguous name is rejected')
check(ns.TrainerServices.Resolve(4)==nil,'header rejected')
local getTip=C_TooltipInfo.GetTrainerService
C_TooltipInfo.GetTrainerService=function() return nil end
eq(ns.TrainerServices.Resolve(2).recipe,b,'rank fallback without tooltip')
services[2][2]='Rank 9'
check(ns.TrainerServices.Resolve(2)==nil,'unknown rank never falls back to rank one')
services[2][2]='Rank 2'
C_TooltipInfo.GetTrainerService=function() return {id=99999} end
check(ns.TrainerServices.Resolve(1)==nil,'unknown explicit spell never borrows name match')
C_TooltipInfo.GetTrainerService=getTip
for _,field in ipairs({1,2,3,4,5}) do
    local old=services[1][field]; services[1][field]=secret
    local ok,value=pcall(ns.TrainerServices.Resolve,1)
    check(ok,'secret service field guarded: ' .. field)
    if field<=4 then check(value==nil,'secret identity clears selection')
    else check(value and value.cost==nil,'secret cost remains unknown') end
    services[1][field]=old
end
check(ns.TrainerServices.Resolve(secret)==nil,'secret selection rejected')
check(ns.TrainerServices.Resolve(0)==nil and ns.TrainerServices.Resolve(1.5)==nil,'invalid selection rejected')
C_TooltipInfo.GetTrainerService=function() return secret end
check(ns.TrainerServices.Resolve(1)==nil,'secret tooltip table cannot fall back to a guessed recipe')
C_TooltipInfo.GetTrainerService=getTip
local skillReq=GetTrainerServiceSkillReq
local levelReq=GetTrainerServiceLevelReq
GetTrainerServiceSkillReq=function() return secret,secret end
GetTrainerServiceLevelReq=function() return secret end
svc=ns.TrainerServices.Resolve(1)
check(svc and svc.skill==nil and svc.level==nil,'secret requirements remain unknown with a readable spell identity')
GetTrainerServiceSkillReq=skillReq;GetTrainerServiceLevelReq=levelReq
local tooltipCreates,fallbackSpell=0,102
CreateFrame=function()
    tooltipCreates=tooltipCreates+1
    return {SetTrainerService=function() end,GetSpell=function() return 'Potion',fallbackSpell end,Hide=function() end}
end
C_TooltipInfo=nil
eq(ns.TrainerServices.Resolve(1).recipe,b,'hidden tooltip spell ID fallback has priority over names')
ns.TrainerServices.Resolve(1)
eq(tooltipCreates,1,'hidden scan tooltip is reused')
fallbackSpell=nil;CreateFrame=nil;C_TooltipInfo={GetTrainerService=getTip}
full=false; selection=2 -- Duplicate is second while unavailable rows are filtered out.
ns.TrainerServices.Scan(true)
eq(selection,2,'full scan restores selection after restoring filters')
check(filters.available and filters.unavailable==false and filters.used==false,'filters restored exactly')
eq(db.trainerCosts[102],500,'live learning fee cached by spell ID')
eq(db.trainerCosts['Potion II'],500,'ranked learning fee retained')
eq(db.trainerReqs.alchemy[102].req,75,'trainer requirement retained')
local visualSelection
ClassTrainer_SetSelection=function(i) visualSelection=i;SelectTrainerService(i) end
ns.TrainerServices.Scan(true)
eq(visualSelection,2,'scan restores the Blizzard visual selection through its selection callback')
ClassTrainer_SetSelection=nil
local getDBError={MP=ns.MP,RECIPES=ns.RECIPES}
assert(loadfile(addon .. 'TrainerServices.lua'))('MerchantMaster',getDBError)
getDBError.TrainerServices.Initialize(function() error('synthetic DB unavailable') end)
local ok=getDBError.TrainerServices.Scan(true)
check(ok==false,'scan reports a failed persistence callback')
check(filters.unavailable==false and filters.used==false and selection==2,'scan error still restores filters and selected service')
check(not getDBError.TrainerServices.IsScanning(),'scan error clears reentrancy guard')
selection=0;ns.TrainerServices.Scan(true)
eq(selection,0,'full scan preserves empty selection')
selection=2
local oldInfo=GetTrainerServiceInfo
local nested=0
GetTrainerServiceInfo=function(i)
    nested=nested+1
    ns.TrainerServices.Scan(false)
    return oldInfo(i)
end
ns.TrainerServices.Scan(true)
check(nested>0 and not ns.TrainerServices.IsScanning(),'nested trainer events cannot start another full scan')
GetTrainerServiceInfo=oldInfo
local countServices=GetNumTrainerServices
GetNumTrainerServices=function() return secret end
check(pcall(ns.TrainerServices.Scan,true),'secret trainer count does not enter arithmetic or a loop')
check(filters.used==false and filters.unavailable==false,'secret count still restores filters')
GetNumTrainerServices=countServices

-- Minimal Blizzard widget/event mocks; all state below is produced by the actual UI module.
local frames,hooks,timers={},{},{}
local function widget()
    local w={scripts={},events={},shown=true,text=''}
    function w:SetSize(x,y) self.width=x;self.height=y end
    function w:SetPoint(...) self.point={...} end
    function w:ClearAllPoints() self.point=nil end
    function w:SetClampedToScreen(v) self.clamped=v end
    function w:SetScript(k,f) self.scripts[k]=f end
    function w:HookScript(k,f) local old=self.scripts[k];self.scripts[k]=function(...) if old then old(...) end;f(...) end end
    function w:RegisterEvent(e) self.events[e]=true end
    function w:Show() self.shown=true end
    function w:Hide() self.shown=false end
    function w:IsShown() return self.shown end
    function w:SetText(v) self.text=v end
    function w:SetFont(...) self.font={...} end
    function w:SetTextColor(...) end
    function w:SetJustifyH(...) end
    function w:SetWidth(v) self.width=v end
    function w:CreateFontString() return widget() end
    function w:CreateTexture() local t=widget();function t:SetAllPoints() end;function t:SetColorTexture(...) end;return t end
    function w:GetLeft() return self.left or 0 end
    function w:GetRight() return self.right or 350 end
    function w:GetTop() return 600 end
    function w:GetBottom() return 0 end
    function w:GetEffectiveScale() return 1 end
    return w
end
CreateFrame=function(kind,name,parent) local f=widget();f.parent=parent;frames[#frames+1]=f;return f end
UIParent=widget();UIParent.right=1200
hooksecurefunc=function(name,fn) hooks[name]=hooks[name] or {};table.insert(hooks[name],fn) end
local function call(name,...) if _G[name] then _G[name](...) end;for _,fn in ipairs(hooks[name] or {}) do fn(...) end end
local function fire(event,arg) for _,f in ipairs(frames) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event,arg) end end end
C_Timer={After=function(_,f) timers[#timers+1]=f end}
local function drain() local n=0;while #timers>0 do n=n+1;assert(n<100,'timer loop');table.remove(timers,1)() end end
local context={economy='test',revision=1}
C_AuctionHouse=setmetatable({}, {__index=function() error('trainer attempted AH access') end})
local statsA={profit=100,craftCost=200,unitAH=320,salesPerDay=2.5,salesScope='Regional',sellable=true,outputItemID=501,demand={label='Hot'}}
local statsB={craftCost=500,sellable=true,outputItemID=502,demand={label='Unknown'}}
local gets,invalidations=0,0
ns.RecipeStats={Get=function(recipe,ctx) eq(ctx,context,'overlay uses host economics context');gets=gets+1;return recipe==ra and statsA or statsB end,
    Invalidate=function() invalidations=invalidations+1 end}
assert(loadfile(addon .. 'UI_TrainerStats.lua'))('MerchantMaster',ns)
local ui=ns.TrainerStats
check(ui and type(ui.Initialize)=='function','trainer overlay API exists')
ui.Initialize(function() return context end)
ui.Initialize(function() error('duplicate initialization') end)
check(ui.frame==nil,'UI waits for late trainer addon')
ClassTrainerFrame=widget();ClassTrainerFrame.left=100;ClassTrainerFrame.right=450
ClassTrainerFrame_Update=function() end
fire('ADDON_LOADED','Blizzard_TrainerUI');drain()
local panel=ui.frame
check(panel and panel.parent==ClassTrainerFrame,'overlay attaches to trainer frame')
fire('ADDON_LOADED','Blizzard_TrainerUI');drain()
eq(ui.frame,panel,'late loading attaches once')
eq(#hooks.ClassTrainerFrame_Update,1,'one frame update hook')
eq(#hooks.SelectTrainerService,1,'one selection hook')
selection=1;fire('TRAINER_SHOW');drain()
eq(ui.stats,statsA,'overlay consumes shared stats unchanged')
check(panel:IsShown(),'selected profession recipe shows overlay')
check(ui.body.text:find('Profit / output: 0g 1s 0c',1,true),'profit displayed per output')
check(ui.body.text:find('Craft cost / output: 0g 2s 0c',1,true),'shared craft cost displayed')
check(ui.body.text:find('AH / output: 0g 3s 20c',1,true),'shared AH price displayed')
check(ui.body.text:find('Learning cost: 0g 2s 50c',1,true),'learning fee separate from craft profit')
check(ui.body.text:find('Sales/day: 2.50 (Regional)',1,true),'velocity scope visible')
check(ui.body.text:find('Heat: Hot',1,true),'shared heat displayed')
full=true;call('SelectTrainerService',2)
eq(ui.stats,statsB,'selection change without trainer update refreshes current recipe')
check(ui.body.text:find('Profit / output: n/a',1,true),'missing profit never fabricated')
check(ui.body.text:find('Market data unavailable',1,true),'missing price explained')
services[1],services[2]=services[2],services[1]
call('ClassTrainerFrame_Update')
eq(ui.stats,statsA,'reordered index resolves current identity again')
call('SelectTrainerService',3)
check(not panel:IsShown() and ui.stats==nil and ui.body.text=='','ambiguous selection clears stale stats')
call('SelectTrainerService',4)
check(not panel:IsShown(),'header hides overlay')
call('SelectTrainerService',1);trade=false;call('ClassTrainerFrame_Update')
check(not panel:IsShown(),'class trainer hidden')
trade=secret;call('ClassTrainerFrame_Update')
check(not panel:IsShown(),'secret trade trainer flag hidden')
trade=true;selection=secret;call('ClassTrainerFrame_Update')
check(not panel:IsShown(),'secret selected index hidden')
selection=1
local tradeAPI=IsTradeskillTrainer;IsTradeskillTrainer=nil;call('ClassTrainerFrame_Update')
check(not panel:IsShown(),'missing tradeskill capability hides safely')
IsTradeskillTrainer=tradeAPI
selection=1;fire('NEW_RECIPE_LEARNED');drain()
check(invalidations>0 and ui.stats==statsB,'learned recipe invalidates and resolves fresh selection')
services[1][3]='used';call('ClassTrainerFrame_Update')
check(panel:IsShown() and ui.stats==statsB,'learned recipe remains tied to current selected identity')
services[1][3]='unavailable'
local before=gets
fire('TRAINER_UPDATE');fire('TRAINER_UPDATE');fire('TRAINER_UPDATE');drain()
eq(gets,before+1,'event refreshes coalesced')
fire('TRAINER_UPDATE');fire('TRAINER_CLOSED');drain()
check(not panel:IsShown() and ui.stats==nil,'close cancels pending refresh')
call('ClassTrainerFrame_Update')
check(not panel:IsShown(),'late callback cannot reopen closed trainer stats')
fire('TRAINER_SHOW');drain()
check(panel:IsShown() and ui.stats==statsB,'rapid reopen refreshes current selection')
local getter=GetTrainerSelectionIndex;GetTrainerSelectionIndex=nil
call('ClassTrainerFrame_Update');check(not panel:IsShown(),'missing selection API hides safely')
GetTrainerSelectionIndex=getter
local previousContext,previousGetter=context,ns.RecipeStats.Get;context=secret
ns.RecipeStats.Get=function() return statsB end
call('ClassTrainerFrame_Update')
check(not panel:IsShown(),'secret host context cannot silently switch valuation settings')
context=previousContext;ns.RecipeStats.Get=previousGetter
local statsGetter=ns.RecipeStats.Get
ns.RecipeStats.Get=function() return secret end
call('ClassTrainerFrame_Update');check(not panel:IsShown(),'secret stats table hidden')
ns.RecipeStats.Get=function() return {profit=secret,craftCost=secret,unitAH=secret,salesPerDay=secret,salesScope=secret,demand=secret,sellable=true,outputItemID=501} end
call('ClassTrainerFrame_Update')
check(panel:IsShown() and ui.body.text:find('Profit / output: n/a',1,true),'secret metric fields shown as unknown')
ns.RecipeStats.Get=function() return {craftCost=10,sellable=false,outputItemID=501} end
call('ClassTrainerFrame_Update')
check(ui.body.text:find('Output is not tradeable',1,true),'nontradeable output explained')
ns.RecipeStats.Get=function() return {craftCost=10,sellable=false} end
call('ClassTrainerFrame_Update')
check(ui.body.text:find('No sellable item output',1,true),'missing output explained')
ns.RecipeStats.Get=statsGetter
statsB.salesPerDay=0;statsB.salesScope='Personal';statsB.salesWindowDays=7
statsB.demand={heatShort='Cached heat'}
call('ClassTrainerFrame_Update')
check(ui.body.text:find('Sales/day: 0.00 (Personal, 7d)',1,true),'observed zero distinct from unknown sales')
check(ui.body.text:find('Heat: Cached heat',1,true),'production heatShort contract displayed unchanged')
ClassTrainerFrame.left=700;ClassTrainerFrame.right=1050
call('ClassTrainerFrame_Update')
eq(panel.point[1],'TOPRIGHT','overlay chooses left edge when screen right is full')
local occupied=widget();occupied.left=460;occupied.right=740
UIParent.GetChildren=function() return occupied end
ClassTrainerFrame.left=300;ClassTrainerFrame.right=450
call('ClassTrainerFrame_Update')
eq(panel.point[1],'TOPRIGHT','overlay avoids another visible right-side dock')
ClassTrainerFrame.left=100
call('ClassTrainerFrame_Update')
eq(panel.point[3],'BOTTOMLEFT','crowded edges use below-frame fallback')
local container=widget();container.left=0;container.right=1200
UIParent.GetChildren=function() return container end
call('ClassTrainerFrame_Update')
eq(panel.point[1],'TOPLEFT','full-screen layout containers do not occupy the docking edge')
eq(panel.point[3],'TOPRIGHT','free right edge preferred despite full-screen containers')
local serviceInfo=GetTrainerServiceInfo
GetTrainerServiceInfo=function() error('trainer gone') end
call('ClassTrainerFrame_Update')
check(not panel:IsShown(),'disappearing trainer API cannot leave stale overlay')
GetTrainerServiceInfo=serviceInfo
-- Initialization with an already loaded trainer UI needs no ADDON_LOADED event.
local beforeTrainerNotifications=invalidations
for i=1,15 do fire('TRAINER_UPDATE');fire('TRAINER_SERVICE_INFO_NAME_UPDATE') end
drain()
eq(invalidations,beforeTrainerNotifications,'unchanged trainer display storms preserve shared recipe cache')
local previousApp=ns.app
ns.app={invalidateRecipeStats=function() end}
fire('NEW_RECIPE_LEARNED');fire('SKILL_LINES_CHANGED');drain()
eq(invalidations,beforeTrainerNotifications,'host-owned skill changes are not invalidated twice by overlay')
ns.app=previousApp
local formerCost=services[1][5];services[1][5]=formerCost+1
selection=1;fire('TRAINER_UPDATE');drain()
eq(ui.service.cost,formerCost+1,'changed trainer fee is displayed after notification')
services[1][5]=formerCost
local ns2={TrainerServices=ns.TrainerServices,RecipeStats=ns.RecipeStats}
assert(loadfile(addon .. 'UI_TrainerStats.lua'))('MerchantMaster',ns2)
ns2.TrainerStats.Initialize(function() return context end)
check(ns2.TrainerStats.frame~=nil,'already loaded trainer UI attached immediately')
if arg and arg[1]=='--real' then
    local scratch=((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
    C_AuctionHouse=nil
    local live=dofile(scratch .. 'host_fixture.lua')
    local recipe
    for _,r in ipairs(live.RECIPES) do
        if r.prof=='alchemy' and r.spellID and r.outputItemID and live.GetRecipeSourceBucket(r)=='trainer' then recipe=r;break end
    end
    check(recipe~=nil,'real catalog trainer recipe available')
    GetTrainerServiceInfo=function() return recipe.name,'','available' end
    GetTrainerServiceSkillReq=function() return 'Alchemy',recipe.skill end
    GetTrainerServiceCost=function() return 456 end
    GetTrainerServiceLevelReq=function() return 5 end
    GetTrainerSelectionIndex=function() return 1 end
    IsTradeskillTrainer=function() return true end
    C_TooltipInfo={GetTrainerService=function() return {id=recipe.spellID} end}
    -- Use the real pricing/economy fixture, including the AH-cut setting.
    local actualContext={profMap={},repState={standing=4},ownedCounts={},applyAHCut=true,
        economy=live.DetectActiveEconomy(),charKey=live.app.charKey}
    local expected=live.RecipeStats.Get(recipe,actualContext)
    ClassTrainerFrame=widget();ClassTrainerFrame.left=100;ClassTrainerFrame.right=450
    assert(loadfile(addon .. 'UI_TrainerStats.lua'))('MerchantMaster',live)
    live.TrainerStats.Initialize(function() return actualContext end)
    live.TrainerStats.Refresh()
    eq(live.TrainerStats.service.statsRecipe,recipe,'real trainer spell resolves exact Super List recipe object')
    eq(live.TrainerStats.stats,expected,'real trainer and Super List share identical cached statistics')
    eq(live.TrainerStats.stats.craftCost,expected.craftCost,'real craft cost agrees')
    eq(live.TrainerStats.stats.unitAH,expected.unitAH,'real AH price agrees')
    eq(live.TrainerStats.stats.profit,expected.profit,'real AH-cut profit agrees')
    eq(live.TrainerStats.stats.salesPerDay,expected.salesPerDay,'real velocity agrees')
    eq(live.TrainerStats.stats.demand,expected.demand,'real heat agrees')
    eq(live.TrainerStats.service.cost,456,'live learning fee independent of craft economics')
end
print('WP7 trainer: ' .. checks .. ' assertions, 0 failures')
