local S=((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local F=dofile(S..'wp5_fixture.lua'); local check=F.check
local ns={}; assert(loadfile(F.addon..'UI_Window.lua'))('MerchantMaster',ns)
local db={scale=1.1}; local p=F.widget(UIParent); local grip=F.widget(p); local hgrip=F.widget(p); local layouts=0
local c=ns.Window.Attach(p,grip,hgrip,{getWindowDB=function() return db end,onLayout=function() layouts=layouts+1 end})
c:ApplyFull(); check(p.width==1320 and p.height==730,'default size'); check(p.scale==1.1 and db.scale==1.1,'separate saved scale')
local left,top=p.left,p.top; F.cursor(100,100); grip:Fire('OnMouseDown','LeftButton'); F.cursor(320,-10); grip:Fire('OnUpdate',.01)
check(p.width==1520 and p.height==830,'two dimensional drag uses effective scale'); check(p.left==left and p.top==top,'top left stable')
check(db.width==1520 and db.height==830 and db.scale==1.1,'persist dimensions without changing scale')
grip:Fire('OnMouseUp','LeftButton'); check(not grip.scripts.OnUpdate,'drag stopped'); check(layouts==1,'stop flushes one layout')
c:ApplyFull(); check(p.width==1520 and p.height==830,'tab restore')
c:SetCompact(true); p:SetSize(440,520); check(db.width==1520 and db.height==830,'bags not persisted')
c:SetCompact(false); c:ApplyFull(); check(p.width==1520 and p.height==830,'leaving bags restores')
c:SetSize(1,1); check(p.width==1320 and p.height==730,'minimum bounds')
UIParent.width=5000; UIParent.height=3000; p.top=2900; c:SetSize(10000,10000); check(p.width==3840 and p.height==2160,'maximum bounds')
UIParent.width=2560; UIParent.height=1440
local oldLeft,oldTop=p.left,p.top; p.left=800; p.top=1100
c:SetSize(1920,1200)
check(p.width*p.scale+800*p.scale<=UIParent.width and p.height<=p.top,'resize respects remaining screen from top left')
p.left,p.top=oldLeft,oldTop
c:SetSize(1500,800); check(not c:IsZoomed(),'initially unzoomed')
c:ToggleZoom(); check(c:IsZoomed() and p.width==math.floor((UIParent.width-24)/p.scale+0.5) and p.height==math.floor((UIParent.height-24)/p.scale+0.5),'ToggleZoom expands to screen bounds')
c:ToggleZoom(); check(not c:IsZoomed() and p.width==1500 and p.height==800,'ToggleZoom restores pre-zoom size')
c:ToggleZoom(); check(c:IsZoomed(),'re-zoomed'); grip:Fire('OnMouseDown','RightButton'); check(not c:IsZoomed(),'right-click grip clears zoomed state')
db.width='bad'; db.height=0/0; db.scale=math.huge; c:ApplyFull(); check(p.width==1320 and p.height==730 and p.scale==1,'malformed values')
db.width=1800; db.height=1000; db.scale=1; UIParent.width=1024; UIParent.height=768; c:ApplyFull()
check(p.width==1800 and p.height==1000 and p.scale<1,'small screen keeps logical size and fits')
check(p.width*p.scale<=1000 and p.height*p.scale<=744,'both screen bounds')
check(db.scale==1,'fit does not overwrite preferred scale')
UIParent.width=2560; UIParent.height=1440; c:ApplyFull(); check(p.scale==1,'larger screen restores preference')
local before=layouts; p:SetSize(1700,950); p:SetSize(1750,960); check(layouts==before,'size events deferred')
c.pulse:Fire('OnUpdate',.02); check(layouts==before,'debounce waits'); c.pulse:Fire('OnUpdate',.04); check(layouts==before+1,'coalesced layout')
p:SetSize(1760,970); p:Hide(); check(not c.pulse.scripts.OnUpdate,'hidden layout cancelled'); check(layouts==before+1,'hidden no layout')
p:Show(); c:ApplyFull(); F.cursor(10,10); hgrip:Fire('OnMouseDown','LeftButton'); F.cursor(200,-20); hgrip:Fire('OnUpdate',.1); hgrip:Fire('OnMouseUp')
check(p.width==1760 and p.height==1000,'height grip keeps width')
UIParent.scale=.8; c:ApplyFull(); local w,h=p.width,p.height; F.cursor(0,0); grip:Fire('OnMouseDown','LeftButton'); F.cursor(80,-80); grip:Fire('OnUpdate',.1); grip:Fire('OnMouseUp')
check(p.width==w+100 and p.height==h+100,'parent scale conversion')
local p2=F.widget(UIParent); local c2=ns.Window.Attach(p2,F.widget(p2),nil,{getWindowDB=function() return db end}); c2:ApplyFull()
check(p2.width==db.width and p2.height==db.height,'reload persistence')
issecretvalue=function(v) return type(v)=='table' end; db.width={}; db.height={}; c2:ApplyFull(); check(p2.width==1320 and p2.height==730,'secret dimensions ignored')
local cell1,cell2=F.widget(),F.widget(); local row={cells={cell1,cell2}}
local tbl={columns={{width=100},{width=50}},colX={},headerBar=F.widget(),headerBtns={F.widget(),F.widget()},pool={}}
tbl.scrollBox={FullUpdate=function() end,ForEachFrame=function(_,fn) fn(row) end}
ns.Window.LayoutTable(tbl,264,1)
check(tbl.columns[1].width==200 and tbl.colX[2]==209,'headers expand name column')
check(cell1.width==200 and cell2.width==50,'visible cell geometry')
ns.Window.LayoutTable(tbl,164,1); check(tbl.columns[1].width==100 and cell1.width==100,'shrink restores original widths')
local recycled={cells={F.widget(),F.widget()}}; tbl.layoutRow(recycled); check(recycled.cells[1].width==100,'recycled cells receive current geometry')
tbl.professor=true; tbl.scrollBox.GetWidth=function() return 378 end
ns.Window.LayoutTable(tbl,400,0)
check(tbl.colX[2]+tbl.columns[2].width<=378,'Professor last cell fits narrower scroll viewport')
local retained={{points={{value=7}}}}; local chart=F.widget(); chart.plot=F.widget(); chart.title=F.widget(); chart.summary=F.widget(); chart.yLabels={F.widget(),F.widget(),F.widget()}; chart.xLabels={F.widget(),F.widget(),F.widget()}; chart._lastBars={}; chart._lastSeries=retained
function chart:SetData(data) self.drawn=data end
local view=F.widget(); view.wealth=chart
ns.Window.LayoutAnalytics({UI={views={view}}},1500)
check(chart.drawn==retained,'line chart redraw uses retained series, never bars')
check(chart.width==1500 and chart.plotWidth==1406,'chart plot follows window width')
local hiddenParent=F.widget(); hiddenParent:Hide(); view.parent=hiddenParent; chart.drawn=nil
ns.Window.LayoutAnalytics({UI={views={view}}},1600)
check(chart.drawn==nil,'hidden analytics chart does not redraw on other tabs')
do
    local function trackWidget(parent)
        local w=F.widget(parent)
        w._pts={}
        local origSet=w.SetPoint
        function w:SetPoint(point,rel,relPt,x,y)
            self._pts[point]={rel=rel,relPt=relPt,x=x or 0,y=y or 0}
            return origSet(self,point,rel,relPt,x,y)
        end
        return w
    end
    local function assertAligned(tbl,row,label)
        for i,col in ipairs(tbl.columns) do
            local hb=tbl.headerBtns[i]
            local cell=row.cells[i]
            local hx=hb._pts.LEFT and hb._pts.LEFT.x or nil
            local cx=cell._pts.LEFT and cell._pts.LEFT.x or nil
            check(hx==tbl.colX[i] and cx==tbl.colX[i],label..' col '..i..' x aligned ('..tostring(hx)..','..tostring(cx)..','..tostring(tbl.colX[i])..')')
            check(hb:GetWidth()==col.width and cell:GetWidth()==col.width,label..' col '..i..' width aligned')
        end
    end
    local vcDefs={
        {key='name',width=128,grow=450},{key='knownSort',width=36,grow=20},{key='cdSort',width=32,grow=10},
        {key='craftCost',width=66,grow=14},{key='minVendor',width=66,grow=14},{key='avgVendor',width=68,grow=14},
        {key='maxVendor',width=66,grow=14},{key='avgProfit',width=70,grow=18},{key='marginPct',width=50,grow=14},
        {key='moatScore',width=82,grow=45},{key='profitableCrafts',width=60,grow=16},{key='buyCeiling',width=70,grow=14},
        {key='totalProfitCap',width=70,grow=14},{key='requiredSkill',width=54,grow=14},{key='sourceLabel',width=48,grow=14},
        {key='buyCostCopper',width=64,grow=12},{key='wowheadURL',width=28,grow=8},
    }
    local byKey={}
    local btnsByKey,cellsByKey={},{}
    for _,d in ipairs(vcDefs) do
        byKey[d.key]=d
        btnsByKey[d.key]=trackWidget()
        cellsByKey[d.key]=trackWidget()
    end
    local vrow={cells={}}
    local chromeCount=0
    local vtbl={columns={},baseWidths={},growWeights={},colX={},headerBar=trackWidget(),headerBtns={},proportional=true,
        paintTableChrome=function() chromeCount=chromeCount+1 end}
    vtbl.scrollBox={FullUpdate=function() end,ForEachFrame=function(_,fn) fn(vrow) end,GetWidth=function() return 1400 end}
    local function applyOrder(order)
        vtbl.columns,vtbl.baseWidths,vtbl.growWeights,vtbl.colX,vtbl.headerBtns,vrow.cells={},{},{},{},{},{}
        local x=4
        for i,k in ipairs(order) do
            local d=byKey[k]
            vtbl.columns[i]={key=d.key,width=d.width,minWidth=d.width,grow=d.grow}
            vtbl.baseWidths[i]=d.width; vtbl.growWeights[i]=d.grow
            vtbl.colX[i]=x; x=x+d.width+5
            vtbl.headerBtns[i]=btnsByKey[k]
            vrow.cells[i]=cellsByKey[k]
        end
        vrow._layoutEpoch=nil
    end
    local defOrder={'name','knownSort','cdSort','craftCost','minVendor','avgVendor','maxVendor','avgProfit','marginPct','moatScore',
        'profitableCrafts','buyCeiling','totalProfitCap','requiredSkill','sourceLabel','buyCostCopper','wowheadURL'}
    local savedOrder={'name','knownSort','cdSort','craftCost','minVendor','avgVendor','maxVendor','avgProfit','marginPct','moatScore',
        'totalProfitCap','requiredSkill','sourceLabel','buyCostCopper','wowheadURL','profitableCrafts','buyCeiling'}
    applyOrder(defOrder)
    ns.Window.LayoutTable(vtbl,1400,1)
    assertAligned(vtbl,vrow,'default 17-col')
    applyOrder(savedOrder) -- IEEE-754 colSum collides with defOrder without changing #columns
    ns.Window.LayoutTable(vtbl,1400,1)
    check(vtbl.columns[1].width>128 and vtbl.columns[16].key=='profitableCrafts','17-col tail reorder bypasses colSum collision')
    assertAligned(vtbl,vrow,'saved 17-col reorder')
    local swappedOrder={}
    for i,k in ipairs(savedOrder) do swappedOrder[i]=k end
    swappedOrder[4],swappedOrder[7]=swappedOrder[7],swappedOrder[4]
    local beforeChrome=chromeCount
    applyOrder(swappedOrder)
    ns.Window.LayoutTable(vtbl,1400,1)
    check(vtbl.columns[4].key=='maxVendor' and chromeCount==beforeChrome+1,'equal-width key swap invalidates cache and repaints chrome')
    assertAligned(vtbl,vrow,'equal-width swap')
    vtbl.columns[11].minWidth=120
    ns.Window.LayoutTable(vtbl,1400,1)
    check(vtbl.columns[11].width>=120,'minWidth growth at same viewport width triggers relayout')
    assertAligned(vtbl,vrow,'minWidth growth')
    vtbl.scrollBox.GetWidth=function() return 0 end
    vtbl.columns[1].minWidth=140
    ns.Window.LayoutTable(vtbl,1400,1)
    check(vtbl.columns[1].width>140,'zero scrollBox width does not collapse table width to 0')
    assertAligned(vtbl,vrow,'zero scrollBox guard')
end
do
    _G.MerchantMasterDB = {}
    UIParent.width = 1920; UIParent.height = 1080
    local helper = F.widget(UIParent)
    helper:SetSize(496, 584)
    helper.scale = 1
    helper.left = 312.5
    helper.top = 740.25
    local savedRec = ns.Window.SavePosition(helper, 'disenchant_helper')
    check(savedRec ~= nil and ns.Window.HasSavedPosition('disenchant_helper'), 'SavePosition stores per-window position')
    local f2 = F.widget(UIParent); f2:SetSize(496, 584); f2.scale = 1.2
    check(ns.Window.RestorePosition(f2, 'disenchant_helper') == true, 'RestorePosition applies saved position cleanly')
    check(math.abs((f2.left * f2.scale) - 312.5) < 1 and math.abs((f2.top * f2.scale) - 740.2) < 1, 'RestorePosition normalizes UIParent coords across UI scale')
    UIParent.width = 1024; UIParent.height = 768
    f2.left = 900; f2.top = 900; f2.scale = 1
    ns.Window.ClampToScreen(f2)
    check(f2.left <= (1024 - 496) and f2.top <= 768, 'ClampToScreen keeps resized/restored window inside viewport bounds')
    UIParent.width = 1920; UIParent.height = 1080
    local anchor = F.widget(UIParent); anchor:SetSize(600, 600); anchor:Show(); anchor.left = 200; anchor.top = 800
    anchor.GetRight = function() return 800 end
    anchor.GetLeft = function() return 200 end
    local lastPts = nil
    f2.ClearAllPoints = function() lastPts = nil end
    f2.SetPoint = function(self, pt, rel, relPt, x, y) lastPts = { pt, rel, relPt, x, y } end
    check(ns.Window.PlaceBeside(f2, anchor, 'CENTER', 0, 0, 12) == true and lastPts[1] == 'TOPLEFT' and lastPts[2] == anchor and lastPts[3] == 'TOPRIGHT',
        'PlaceBeside anchors beside open Blizzard window on right when room fits')
    anchor.GetRight = function() return 1700 end; anchor.GetLeft = function() return 1100 end
    check(ns.Window.PlaceBeside(f2, anchor, 'CENTER', 0, 0, 12) == true and lastPts[1] == 'TOPRIGHT' and lastPts[2] == anchor and lastPts[3] == 'TOPLEFT',
        'PlaceBeside flips to left of Blizzard window near right screen edge')
    anchor:Hide()
    check(ns.Window.PlaceBeside(f2, anchor, 'CENTER', 0, 20, 12) == false and lastPts[1] == 'CENTER' and lastPts[5] == 20,
        'PlaceBeside falls back to CENTER when Blizzard window is hidden')
    -- Zero-hop cursor-delta dragging when GetCursorPosition + GetLeft/GetTop are available
    local fDrag = F.widget(UIParent)
    fDrag:SetSize(400, 300)
    local dragStopped = false
    local hdr = F.widget(fDrag)
    fDrag.left, fDrag.top = 150, 720
    fDrag.scale = 1
    UIParent.scale = 1
    F.cursor(300, 700)
    ns.Window.MakeDragHandle(hdr, fDrag, function(t)
        dragStopped = true
        ns.Window.SavePosition(t, 'drag_key')
    end)
    hdr:Fire('OnDragStart')
    check(ns.Window.IsDragging(fDrag) and fDrag.left == 150 and fDrag.top == 720,
        'MakeDragHandle starts cursor-delta drag with zero hop (left=150, top=720)')
    F.cursor(420, 640)
    fDrag._mmDragDriver:Fire('OnUpdate', 0.016)
    check(math.abs(fDrag.left - 270) < 0.01 and math.abs(fDrag.top - 660) < 0.01,
        'Cursor-delta drag moves target smoothly by exact cursor delta')
    hdr:Fire('OnDragStop')
    check(dragStopped and not ns.Window.IsDragging(fDrag) and ns.Window.HasSavedPosition('drag_key')
        and math.abs(MerchantMasterDB.windowPositions.drag_key.x - 270) < 0.2,
        'MakeDragHandle stops cleanly and saves final dragged coordinates')

    -- OnHide mid-drag cleans up without firing onStop
    dragStopped = false
    F.cursor(100, 500)
    hdr:Fire('OnDragStart')
    check(ns.Window.IsDragging(fDrag), 'Second drag started')
    fDrag:Hide()
    check(not ns.Window.IsDragging(fDrag) and not dragStopped and not fDrag._mmDragDriver.scripts.OnUpdate,
        'Hiding target mid-drag cancels OnUpdate cleanly')
    fDrag:Show()

    -- Per-window Snap / Lock / Free mode persistence & Lock drag blocking
    check(ns.Window.GetMode('drag_key', 'snap') == 'snap', 'Default mode is snap')
    check(ns.Window.CycleMode('drag_key') == 'lock', 'CycleMode snap -> lock')
    local lockDragStopped = false
    local hdrLock = F.widget(fDrag)
    fDrag.left, fDrag.top = 200, 600
    ns.Window.MakeDragHandle(hdrLock, fDrag, function() lockDragStopped = true end, {
        canDrag = function() return ns.Window.GetMode('drag_key', 'snap') ~= 'lock' end,
    })
    F.cursor(200, 600)
    hdrLock:Fire('OnDragStart')
    check(not ns.Window.IsDragging(fDrag), 'Lock mode blocks drag start')
    F.cursor(400, 400)
    hdrLock:Fire('OnDragStop')
    check(fDrag.left == 200 and fDrag.top == 600 and not lockDragStopped, 'Locked target stays at anchored coords')
    check(ns.Window.CycleMode('drag_key') == 'free', 'CycleMode lock -> free')
    check(ns.Window.CycleMode('drag_key') == 'snap', 'CycleMode free -> snap')

    -- Native StartMoving fallback when GetCursorPosition is absent
    local origCursorFn = _G.GetCursorPosition
    _G.GetCursorPosition = nil
    local nativeMoved, nativeStopped = false, false
    local f3 = F.widget(UIParent)
    local hdr3 = F.widget(f3)
    f3.StartMoving = function() nativeMoved = true end
    f3.StopMovingOrSizing = function() nativeStopped = true end
    ns.Window.MakeDragHandle(hdr3, f3, function(t) ns.Window.SavePosition(t, 'drag_native') end)
    hdr3:Fire('OnDragStart'); hdr3:Fire('OnDragStop')
    check(nativeMoved and nativeStopped and ns.Window.HasSavedPosition('drag_native'),
        'MakeDragHandle falls back to StartMoving when GetCursorPosition is unavailable')
    _G.GetCursorPosition = origCursorFn

    ns.Window.ClearSavedPosition(nil)
    check(not ns.Window.HasSavedPosition('disenchant_helper')
        and not ns.Window.HasSavedPosition('drag_key')
        and ns.Window.GetMode('drag_key', 'snap') == 'snap',
        'ClearSavedPosition(nil) resets saved positions and window modes back to snap')
    _G.MerchantMasterDB = nil
end
print('WP5 window: '..F.count..' assertions, 0 failures')
