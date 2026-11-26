local S=((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns, frames = dofile(S .. 'host_fixture.lua')
local n=0; local function check(ok,msg) n=n+1; assert(ok,msg) end
local app=ns.app; local panel=app.panel; local chrome=app.ui.winChrome
MerchantMasterDB.window=true
panel:Show(); app.setTab('dashboard')
check(type(MerchantMasterDB.window)=='table','malformed saved window container repaired')
check(chrome.ahRefresh.button:GetScript('OnUpdate')~=nil,'theme freshness show hook survives host show handler')
check(chrome.ahRefresh.button:GetWidth()==78 and chrome.ahRefresh.button:GetHeight()==24,'first-run Scan AH button expands before first scan')
MerchantMasterDB.ahPrices = MerchantMasterDB.ahPrices or {}
MerchantMasterDB.ahPrices[ns.DetectActiveEconomy()] = { _scannedAt = time() }
chrome.ahRefresh:Update()
check(chrome.ahRefresh.button:GetWidth()==24 and chrome.ahRefresh.button:GetHeight()==24,'refresh square after live AH scan')
MerchantMasterDB.window.width=1700; MerchantMasterDB.window.height=900; MerchantMasterDB.window.scale=1
app.refresh(); check(panel:GetWidth()==1700 and panel:GetHeight()==900,'host saved size')
for _,tab in ipairs({'profit_spread','outliers','recipes','crates','writs','rep','calc_favor','an_overview','an_ledger','an_items','an_portfolio','an_invest','an_writs','prof_path','prof_shop','prof_browse'}) do
    app.setTab(tab); check(panel:GetWidth()==1700 and panel:GetHeight()==900,'full size survives '..tab)
end
app.setTab('bags'); check(panel:GetWidth()==440,'compact bags'); check(MerchantMasterDB.window.width==1700,'bags preserve full size')
app.setTab('recipes'); check(panel:GetWidth()==1700 and panel:GetHeight()==900,'full size after bags')
local evaluations=0; local oldBegin=ns.BeginEval
ns.BeginEval=function(...) evaluations=evaluations+1; return oldBegin(...) end
panel.GetTop=function() return 1000 end
chrome.window:SetSize(1705,950); local pulse=chrome.window.pulse; pulse:GetScript('OnUpdate')(pulse,.1)
check(evaluations==0,'resize does not start recipe evaluation')
check(panel:GetWidth()==1705 and panel:GetHeight()==950,'host real dimensions')
ns.BeginEval=oldBegin
local tbl=app.ui.recipesTable; local h=tbl.headerBar; local oldWidth=h.GetWidth
local oldScrollWidth=tbl.scrollBox.GetWidth; tbl.scrollBox.GetWidth=function() return 1802 end
h.GetWidth=function() return 1800 end; app.layoutWindow()
check(tbl.columns[1].width>170,'name column expands with content')
local newWidth=tbl.columns[1].width; app.layoutWindow(); check(tbl.columns[1].width==newWidth,'repeat layout cannot accumulate column growth')
h.GetWidth=oldWidth
tbl.scrollBox.GetWidth=oldScrollWidth
local shared={{width=100,label='Name',align='LEFT'},{width=50,label='Cost',align='RIGHT'}}
local first=app.ui.createSortableTable(panel,0,nil,shared,function() end)
local second=app.ui.createSortableTable(panel,0,nil,shared,function() end)
first.scrollBox.GetWidth=function() return 400 end
ns.Window.LayoutTable(first,400,1)
check(first.columns[1].width>100,'shared columns regression exercises expansion')
check(second.columns[1].width==100 and shared[1].width==100,'resizing one table cannot mutate another table column definition')
check(ns.MapPins == nil,'core addon has no bundled MapPins module standalone')
local mapEvents=0
local prevMapPinsProvider = app.mapPinsProvider
MerchantMasterAPI.RegisterMapPins({
    apiVersion = 1,
    version = '1.0.0-test',
    Init = function() end,
    OnEvent = function(reason) if reason=='HOST_CONTEXT_CHANGED' then mapEvents=mapEvents+1 end end,
    InvalidateOwnership = function() end,
    GetPinCount = function() return 0 end,
})
app.cycleEconomy('RightButton'); check(mapEvents==1,'cycle/reset invalidates registered map pins context')
local originalDropDown=ns.Theme.OpenDropDown
ns.Theme.OpenDropDown=function(_,_,_,callback) callback('Normal-Horde') end
app.cycleEconomy('LeftButton',{}); check(mapEvents==2,'dropdown invalidates registered map pins context')
ns.Theme.OpenDropDown=originalDropDown; app.mapPinsProvider = prevMapPinsProvider
local reasons={}; local originalInvalidate=ns.RecipeStats.Invalidate
ns.RecipeStats.Invalidate=function(reason) reasons[reason]=true; return originalInvalidate(reason) end
-- Give the event an actual ownership change; unchanged notifications must be cheap.
app.char.bags['Synthetic removed bag item']=1
for _,f in ipairs(frames) do if f._events.BAG_UPDATE_DELAYED and f._scripts.OnEvent then f._scripts.OnEvent(f,'BAG_UPDATE_DELAYED') end end
check(reasons.ownership,'bag event invalidates shared recipe ownership cache')
reasons={}
for _,f in ipairs(frames) do if f._events.BAG_UPDATE_DELAYED and f._scripts.OnEvent then f._scripts.OnEvent(f,'BAG_UPDATE_DELAYED') end end
check(not reasons.ownership,'unchanged bag notification preserves shared recipe ownership cache')
ns.RecipeStats.Invalidate=originalInvalidate
panel:Hide(); check(chrome.ahRefresh.button:GetScript('OnUpdate')==nil,'host hide cancels freshness timer')
check(chrome.window.pulse:GetScript('OnUpdate')==nil,'host hide cancels layout work')
print('WP5 integration: '..n..' assertions, 0 failures')
