local S=((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
MerchantMasterDB={superListColumns={hidden={wowheadURL=true},order={'name','cdSort','knownSort'}}}
local ns, frames, hostEnv = dofile(S .. 'host_fixture.lua')
local TOTAL_RECIPES = #ns.RecipeStats.GetCatalog()
local n=0
local function check(ok,msg) n=n+1; assert(ok,msg) end
local function plain(value) return (value:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')) end
local app, provider=ns.app,ns.SuperList
local tbl=app.ui.recipesTable
check(#tbl.columns==19 and tbl.columns[2].key=='cdSort','startup uses the saved hidden column and order')
check(provider.ResetColumns(),'reset restores a column hidden at startup')
check(tbl.headerBtns[20] and tbl.headerBtns[20]:IsShown(),'reset shows the startup-hidden Wowhead header')
check(#tbl.columns==20,'Super List has the twenty unified columns')
local keys={'name','knownSort','cdSort','ownedOutputQty','listed','goodScore','buyCostCopper','craftCost','unitAH','salesPerDay','turnoverPerDay','demandSort','profit','requiredSkill','skillupSort','sourceLabel','sourceCost','repSort','bisSort','wowheadURL'}
local widths={128,48,34,34,40,104,62,62,62,58,66,48,64,54,74,48,66,46,40,28}
for i,key in ipairs(keys) do
    check(tbl.columns[i].key==key,'column identity '..key)
    check((tbl.baseWidths and tbl.baseWidths[i] or tbl.columns[i].width)==widths[i],'base width '..key)
end
check(type(provider.Cancel)=='function','pending evaluation is cancellable on hide')
check(type(provider.Invalidate)=='function','host invalidation reaches cached list')
check(app.ui.recipesView.sourceButton~=app.ui.recipeSourcesBtn,'source selection is local to Super List')
app.activeTab='recipes'; app.panel:Show(); provider.Invalidate()
-- Model the native scrollbox's bounded pool; invoke the real factory initializer.
local box=tbl.scrollBox
local pool,offset,capacity={},1,16
box._frames=pool
box.GetHeight=function() return capacity*app.ui.ROW_H end
local function render()
    if not box._dp then return end
    local items=box._dp:GetCollection()
    for i=1,math.min(capacity,#items) do
        local r=pool[i]
        if not r then r=CreateFrame('Button',nil,box); pool[i]=r end
        r:Show(); box._view._initFn(r,items[offset+i-1])
    end
    for i=math.min(capacity,#items)+1,#pool do pool[i]:Hide() end
    box._frames=pool
end
function box:SetDataProvider(dp) self._dp=dp; offset=math.min(offset,math.max(1,#dp:GetCollection()-capacity+1)); render() end
function box:FullUpdate() render() end
local queued={}
local oldAfter=C_Timer.After
C_Timer.After=function(_,fn) queued[#queued+1]=fn end
local ciScale=(os and os.getenv and (os.getenv('CI')=='true' or os.getenv('GITHUB_ACTIONS')=='true')) and 2.5 or 1.0
local oldProfile=debugprofilestop
debugprofilestop=function() return os.clock()*1000 end
local maxCallback=0
local function runCallback(fn)
    local before=os.clock()
    fn()
    local elapsed=(os.clock()-before)*1000
    if elapsed>maxCallback then
        maxCallback=elapsed
        if elapsed>4.001 then
            local info=debug.getinfo(fn,'Su')
            for i=1,info.nups do
                local name,value=debug.getupvalue(fn,i)
                if name=='fn' and type(value)=='function' then info=debug.getinfo(value,'S'); break end
            end
            print('WP6 CALLBACK '..info.short_src..':'..info.linedefined..' ms='..elapsed)
        end
    end
end
local function drain()
    local count=0
    while #queued>0 do
        runCallback(table.remove(queued,1))
        count=count+1; assert(count<10000,'no runaway jobs')
    end
    return count
end
local starts,gets,sorts,searches=0,0,0,0
local oldStart,oldGet,oldSort,oldSearch=ns.SuperListModel.Start,ns.RecipeStats.Get,ns.SuperListModel.FilterSort,app.searchAH
ns.SuperListModel.Start=function(...) starts=starts+1; return oldStart(...) end
ns.RecipeStats.Get=function(...)
    gets=gets+1; local at=os.clock(); local row=oldGet(...)
    if (os.clock()-at)*1000>3 then print('WP6 SLOW GET '..row.name..' ms='..(os.clock()-at)*1000) end
    return row
end
ns.SuperListModel.FilterSort=function(...) sorts=sorts+1; return oldSort(...) end
app.searchAH=function() searches=searches+1 end
local context={db={superListSources={},applyAHCut=true},search='',profFilter='all',unlockFilter='all',knownRecipesOnly=false,
    subCraftMode='smart',counts={},profMap={},repState={standing=4},econInfo=ns.CurrentEconomyInfo(),revision=1,charKey=app.charKey}
collectgarbage('collect')
local before=os.clock()
for i=1,40 do provider.Refresh(context) end
check(#queued==1,'event storms coalesce to one build kickoff')
drain()
local cold=(os.clock()-before)*1000
local all=box._dp:GetCollection()
check(#all== TOTAL_RECIPES,'all non-gather recipes shown without learned professions')
check(starts==1 and gets== TOTAL_RECIPES,'one incremental catalog build for event storm')
check(searches==0,'opening, evaluating and filtering issue no AH searches')
check(#pool<=capacity+4,'visible row pool bounded by capacity plus four')
do
    local savedMode = MerchantMasterDB.priceDisplayMode
    local row = pool[1]
    local data = row.data
    local profitColumn
    for index, column in ipairs(tbl.columns) do
        if column.key == 'profit' then profitColumn = index; break end
    end
    MerchantMasterDB.priceDisplayMode = 'no_copper'
    for _, value in ipairs({-49, 49}) do
        data.profit = value
        box._view._initFn(row, data)
        check(plain(row.cells[profitColumn].fs:GetText()) == '0s',
            'All Recipes signed profit rounds '..tostring(value)..'c to neutral 0s')
        local cells = row.cellGroup.cellsByKey
        check(row:GetScript('OnEnter') == nil and row.cells[profitColumn]:GetScript('OnEnter') == nil
            and cells.craftCost:GetScript('OnEnter') == nil, 'only the name cell owns the recipe tooltip')
        cells.name:GetScript('OnEnter')(cells.name)
        local tooltipProfit
        for _, line in ipairs(GameTooltip._lines or {}) do
            if line:find('Profit per output | ', 1, true) then
                tooltipProfit = line:match('Profit per output | (.*)')
            end
        end
        check(tooltipProfit and plain(tooltipProfit) == '0s',
            'All Recipes profit tooltip rounds '..tostring(value)..'c to neutral 0s')
        cells.name:GetScript('OnLeave')(cells.name)
    end
    MerchantMasterDB.priceDisplayMode = savedMode
    box._view._initFn(row, data)
end
local allIDs={}; for _,row in ipairs(all) do check(not allIDs[row.key],'duplicate recipe identity absent'); allIDs[row.key]=true end
check(cold<=1000*ciScale,'cold completion under one second in synthetic harness')
-- The entire scheduled pipeline is checked, including the final sort callback.
check(maxCallback<=4.001,'maximum scheduled callback under four milliseconds: '..maxCallback)
-- Record the native layout options missing from the lightweight host fixture.
local originalCreateFrame=CreateFrame
CreateFrame=function(...)
    local frame=originalCreateFrame(...)
    frame.EnableMouseWheel=function(self,value) self.mouseWheel=value end
    local createFontString=frame.CreateFontString
    frame.CreateFontString=function(self,...)
        local fs=createFontString(self,...)
        local setTextColor=fs.SetTextColor
        function fs:SetTextColor(r,g,b,a)
            self._lastColor={r,g,b,a}
            return setTextColor(self,r,g,b,a)
        end
        fs.SetWordWrap=function(self,value) self.wordWrap=value end
        fs.SetNonSpaceWrap=function(self,value) self.nonSpaceWrap=value end
        fs.SetMaxLines=function(self,value) self.maxLines=value end
        fs.SetJustifyH=function(self,value) self.justifyH=value end
        return fs
    end
    return frame
end
local first=pool[1]; first:Click('LeftButton')
CreateFrame=originalCreateFrame
local selected=app.selectedRecipeItemID
local framesBefore=#frames; local getsBefore=gets
offset=#all-capacity+1; render()
check(pool[capacity].data.key==all[#all].key,'last row reachable')
check(gets==getsBefore and searches==1,'scrolling does not value recipes or search the AH')
offset=1; render()
for i=1,10 do
    app.sortState.recipes.asc=i%2==0
    provider.Refresh(context); drain()
end
check(#frames==framesBefore,'repeated sorting reuses row widgets')
check(gets==getsBefore and starts==1,'warm sorting never evaluates economics')
check(app.selectedRecipeItemID==selected,'selection survives refresh and sorting')
local warmBefore=os.clock(); provider.Refresh(context); drain()
local warm=(os.clock()-warmBefore)*1000
check(warm<=50*ciScale,'warm presentation within fifty milliseconds')
context.db.superListSources={vendor=true,writ=true}; provider.Refresh(context); drain()
local filtered=box._dp:GetCollection(); local seenWrit=false
for _,row in ipairs(filtered) do check(row.sourceBucket=='vendor' or row.isWrit,'Writ and vendor combine with OR'); seenWrit=seenWrit or row.isWrit end
check(seenWrit,'Writ filter includes catalog Writ recipes')
check(gets==getsBefore,'source changes reuse evaluated catalog')
context.search='zzzz-not-a-recipe'; provider.Refresh(context); drain()
check(#box._dp:GetCollection()==0,'search composes with selected sources using AND')
check(pool[1].data==nil,'hidden recycled row clears click and tooltip identity')
local searchBefore=searches; pool[1]:Click('LeftButton'); check(searches==searchBefore,'hidden row cannot search previous recipe')
context.search=''; context.db.superListSources={}; provider.Refresh(context); drain()
context.db.merchantVendorOnly=true; context.db.superListSources=nil
provider.Refresh(context); drain()
check(context.db.superListSources.merchant==true and context.db.merchantVendorOnly==false,'legacy merchant selection migrates into visible sources')
for _,row in ipairs(box._dp:GetCollection()) do check(row.sourceBucket=='merchant','migrated source applies merchant filter') end
context.db.merchantVendorOnly=true; context.db.superListSources={vendor=true}
provider.Refresh(context); drain()
check(context.db.superListSources.vendor and not context.db.superListSources.merchant and context.db.merchantVendorOnly==false,'explicit source selection survives legacy flag')
context.db.superListSources={}; provider.Refresh(context); drain()
local skillView=app.ui.recipesView
local originalRefresh=app.refresh
app.refresh=function() provider.Refresh(context) end
check(skillView.skillControl and skillView.skillMin and skillView.skillMax,'skill controls exposed')
local function enter(edit,value)
    edit:SetText(value); edit:GetScript('OnEnterPressed')(edit); drain()
end
enter(skillView.skillMin,'1'); enter(skillView.skillMax,'75')
check(context.db.superListSkillMin==1 and context.db.superListSkillMax==75,'skill bounds persisted as integers')
check(#box._dp:GetCollection()>0,'valid skill range has matches')
for _,row in ipairs(box._dp:GetCollection()) do check(row.requiredSkill>=1 and row.requiredSkill<=75,'inclusive recipe skill range') end
context.db.superListSources={merchant=true,vendor=true}; context.db.bisOnly=true
provider.Refresh(context); drain()
for _,row in ipairs(box._dp:GetCollection()) do
    check(row.requiredSkill>=1 and row.requiredSkill<=75 and row.bisInfo.isBiS and (row.sourceBucket=='merchant' or row.sourceBucket=='vendor'),'skill/source/Best combine with AND')
end
enter(skillView.skillMin,'76')
check(#box._dp:GetCollection()==0 and skillView.skillError:GetText()=='Min exceeds max','inverted range reports error without swapping')
enter(skillView.skillMin,'bad'); check(context.db.superListSkillMin==76 and skillView.skillMin:GetText()=='76','invalid edit restores previous value')
enter(skillView.skillMin,'1.5'); check(context.db.superListSkillMin==76,'fraction rejected')
skillView.skillMin:SetText('99'); skillView.skillMin:GetScript('OnEscapePressed')(skillView.skillMin)
check(context.db.superListSkillMin==76 and skillView.skillMin:GetText()=='76','Escape restores previous bound')
skillView.skillMin:SetText('0'); skillView.skillMin:GetScript('OnEditFocusLost')(skillView.skillMin); drain()
check(context.db.superListSkillMin==0,'focus loss commits known zero skill')
enter(skillView.skillMin,''); enter(skillView.skillMax,'')
check(context.db.superListSkillMin==nil and context.db.superListSkillMax==nil and skillView.skillError:GetText()=='','empty removes both bounds')
check(gets==getsBefore,'skill/source/Best presentation does not revalue recipes')
context.db.superListSkillMin='2'; context.db.superListSkillMax='75'; provider.Refresh(context); drain()
check(skillView.skillMin:GetText()=='2' and skillView.skillMax:GetText()=='75' and context.db.superListSkillMin==2,'restored saved range normalized without recursive refresh')
context.db.superListSkillMin=nil; context.db.superListSkillMax=nil
context.db.superListSources={}; context.db.bisOnly=false
app.sortState.recipes.col='uniqueSellers'; app.sortState.recipes.asc=true
provider.Refresh(context); drain()
check(app.sortState.recipes.col=='profit' and not app.sortState.recipes.asc,'obsolete Sellers sort migrates to Profit descending')
app.sortState.recipes.col='bisSort'; app.sortState.recipes.asc=false; provider.Refresh(context); drain()
local sortedBest=box._dp:GetCollection()
for i=2,#sortedBest do check((sortedBest[i-1].bisSort or -math.huge)>=(sortedBest[i].bisSort or -math.huge),'Best numeric order across merged runs') end
app.sortState.recipes.col='knownSort'; app.sortState.recipes.asc=false; provider.Refresh(context); drain()
local sortedKnown=box._dp:GetCollection()
for i=2,#sortedKnown do check((sortedKnown[i-1].knownSort or -math.huge)>=(sortedKnown[i].knownSort or -math.huge),'Known numeric order across merged runs') end
app.sortState.recipes.col='listed'; app.sortState.recipes.asc=true; provider.Refresh(context); drain()
local sortedListed=box._dp:GetCollection()
for i=2,#sortedListed do
    local a,b=sortedListed[i-1].listed,sortedListed[i].listed
    if a==nil then check(b==nil,'Listed nil sorted last')
    elseif b~=nil then check(a<=b,'Listed ascending order') end
end
app.sortState.recipes.col='goodScore'; app.sortState.recipes.asc=false; provider.Refresh(context); drain()
local sortedGood=box._dp:GetCollection()
for i=2,#sortedGood do
    local a,b=sortedGood[i-1].goodScore,sortedGood[i].goodScore
    if a==nil then check(b==nil,'Why It Sells nil sorted last')
    elseif b~=nil then check(a>=b,'Why It Sells descending order') end
end
app.sortState.recipes.col='repSort'; app.sortState.recipes.asc=true; provider.Refresh(context); drain()
local sortedRep=box._dp:GetCollection()
for i=2,#sortedRep do
    local a,b=sortedRep[i-1].repSort,sortedRep[i].repSort
    if a==nil then check(b==nil,'Rep nil sorted last')
    elseif b~=nil then check(a<=b,'Rep ascending order') end
end
app.sortState.recipes.col='profit'; app.sortState.recipes.asc=false; provider.Refresh(context); drain()
app.refresh=originalRefresh
-- Verify clean Source labels across evaluated catalog rows and live rep invalidation.
local seenSource={}
local repTarget
for _,r in ipairs(box._dp:GetCollection()) do
    seenSource[r.sourceLabel]=true
    check(not tostring(r.sourceLabel or ''):find('Favor',1,true) and not tostring(r.sourceLabel or ''):find('Vendor (',1,true),
        'clean Source label has no coin/Favor text: '..tostring(r.sourceLabel))
    if r.sourceBucket=='merchant' and (r.reqRep or 0)>=6 and not repTarget then repTarget=r end
end
check(seenSource['Merchant'] and seenSource['Vendor'] and seenSource['Trainer'],'clean Source labels include Merchant, Vendor, Trainer')
check(repTarget~=nil and repTarget.repMet==false and repTarget.repLabel==ns.STANDING_NAMES[repTarget.reqRep],'rep requirement unmet at Neutral')
local getsBeforeRep=gets
context.repState={standing=8}
provider.Invalidate('rep'); provider.Refresh(context); drain()
check(gets==getsBeforeRep,'live rep invalidation patches metadata without full rebuild')
check(repTarget.repMet==true,'live rep invalidation updates repMet when standing increases')
context.repState={standing=4}
provider.Invalidate('rep'); provider.Refresh(context); drain()
-- Spy cell text colors on pool[1] without editing shared host_fixture.lua.
for _,cell in ipairs(pool[1].cells) do
    local fs=cell.fs
    if fs and not fs._wp6ColorSpy then
        fs._wp6ColorSpy=true
        local orig=fs.SetTextColor
        fs.SetTextColor=function(self,r,g,b,a)
            self._lastColor={r,g,b,a}
            return orig(self,r,g,b,a)
        end
    end
end
-- Bind a row with every optional metric, then one without them, onto the same widget.
local rich={key='rich',name='Favor recipe',prof='alchemy',requiredSkill=75,skillYellow=100,skillGreen=125,skillGray=150,skillupSort=150,ownedOutputQty=12,ownedScrollQty=2,
    known=true,knownSort=1,cdInfo={hasCooldown=false},listed=0,goodScore=45,goodShort='|cffffd200Best: Tank|r',goodFull='|cffffd200Best: Tank|r',goodPlain='Best: Tank',
    reqRep=6,repSort=6,repLabel='Honored',repMet=false,
    buyCostCopper=10000,buyCostEstimated=true,craftCost=250,unitAH=500,profit=225,salesPerDay=0,turnoverPerDay=0,
    sourceCost={known=true,currencies={[3402]=150}},sourceLabel='Merchant',sellerStatus='partial',uniqueSellers=3,
    bisInfo={hasEval=true,isBiS=true,cellText='Best'},bisSort=10001,
    salesScope='Personal',salesWindowDays=7,sellerAt=123,sellerScope='named items',sellable=true,isSlowing=true,
    wowheadURL='https://www.wowhead.com/forever/spell=123',craftAbility={},demand={heatBadge='Hot'},icon=123,rowIndex=1}
box._view._initFn(pool[1],rich)
check(pool[1].cells[2].fs:GetText()=='Yes','Known displays Yes when learned')
check(pool[1].cellGroup.cellsByKey.cdSort.fs:GetText()=='-','CD displays a hyphen when the recipe has no cooldown')
check(pool[1].cells[4].fs:GetText()=='12','Owned displays output quantity rather than scrolls')
check(pool[1].cells[5].fs:GetText()=='0','Listed displays active listing count')
check((pool[1].cells[6].fs:GetText() or ''):find('Best: Tank',1,true)~=nil,'Why It Sells displays goodShort without asterisk')
check(pool[1].cells[10].fs:GetText()==ns.Theme.FormatSalesPerDay(0),'known zero sales distinct from unknown using house formatting')
check(plain(pool[1].cells[15].fs:GetText())=='100/125/150','Y/G/Gr displays yellow/green/gray skill-up thresholds')
check(pool[1].cells[16].fs:GetText()=='Merchant','Source displays clean Merchant label')
check(pool[1].cells[17].fs:GetText()=='150 Favor','actual Favor currency shown without copper or abbreviation')
check(pool[1].cells[18].fs:GetText()=='Honored','Rep displays standing name')
check(pool[1].cells[19].fs:GetText()=='Best','Best displays existing effect-class evaluation without asterisk')
ns.Theme.SetMode('light')
box._view._initFn(pool[1],rich)
local lightWhy=pool[1].cells[6].fs:GetText() or ''
check(lightWhy:find('|cff9e4b00',1,true)~=nil and not lightWhy:find('|cffffd200',1,true),'Why It Sells re-themes for light mode')
local repColLight=pool[1].cells[18].fs._lastColor
check(repColLight and math.abs(repColLight[1]-0.722)<0.01 and repColLight[2]<0.1,'unmet Rep uses accessible #B8141A in light mode')
local cdColLight=pool[1].cellGroup.cellsByKey.cdSort.fs._lastColor
check(cdColLight and cdColLight[1]==0 and cdColLight[2]==0 and cdColLight[3]==0 and cdColLight[4]==1,'CD hyphen uses primary black text in light mode')
rich.known=false; rich.repMet=true
box._view._initFn(pool[1],rich)
check(pool[1].cells[2].fs:GetText()=='No','Known displays No when unlearned')
local knownColLight=pool[1].cells[2].fs._lastColor
check(knownColLight and math.abs(knownColLight[1]-0.722)<0.01 and knownColLight[2]<0.1,'unlearned Known uses accessible #B8141A in light mode')
local repMetCol=pool[1].cells[18].fs._lastColor
check(repMetCol and repMetCol[2]>repMetCol[1],'met Rep uses accentGreen')
ns.Theme.SetMode('dark')
rich.known=true; rich.repMet=false
box._view._initFn(pool[1],rich)
local cdColDark=pool[1].cellGroup.cellsByKey.cdSort.fs._lastColor
check(cdColDark and cdColDark[1]==1 and cdColDark[2]==1 and cdColDark[3]==1 and cdColDark[4]==1,'CD hyphen uses primary white text in dark mode')
check((pool[1].cells[6].fs:GetText() or ''):find('|cff',1,true)~=nil and not (pool[1].cells[6].fs:GetText() or ''):find('|cff9e4b00',1,true),'Why It Sells restores dark theme')
rich.sourceCost.copper=100
box._view._initFn(pool[1],rich)
check(pool[1].cells[17].fs:GetText()==ns.FormatMoneyCompact(100)..' + 150 Favor','explicit mixed cost remains visible for auditing')
rich.sourceCost.copper=nil; box._view._initFn(pool[1],rich)
check(pool[1].cells[10]:GetScript('OnEnter') == nil, 'the Sales per day cell has no tooltip script')
local richNameCell = pool[1].cellGroup.cellsByKey.name
richNameCell:GetScript('OnEnter')(richNameCell)
local tip=table.concat(GameTooltip._lines,' ')
check(tip:find('Personal',1,true) and tip:find('7 days',1,true),'sales tooltip identifies scope and window')
check(tip:find('not realized ledger revenue',1,true),'turnover tooltip states gross estimate')
check(tip:find('Why Buyers Need It',1,true) and tip:find('Reputation required',1,true) and tip:find('Hold Shift:',1,true),'tooltip includes Why Buyers Need It, Reputation required, and Shift hint')
check(not tip:find('Sellers:',1,true) and not tip:find('Seller observation:',1,true),'seller statistics absent from Super List tooltip')
check(not tip:find('Sales/day: Personal seven-day',1,true),'column header hint is not injected into row item tooltip')
pool[1].cells[20]:Click('LeftButton')
check(app.ui.wowheadModal.currentURL==rich.wowheadURL,'Wowhead button uses row spell URL in existing copy popup')
local bare={key='bare',name='No output',prof='enchanting',craftAbility={},sourceCost={known=false},sellerStatus='unavailable'}
box._view._initFn(pool[1],bare)
check(pool[1].cells[2].fs:GetText()=='No','recycling resets Known to No')
check(pool[1].cells[18].fs:GetText()=='—','recycling clears Rep to dash')
check(pool[1].cellGroup.cellsByKey.cdSort.fs:GetText()=='-','recycling clears the cooldown to a hyphen')
for _,i in ipairs({5,6,7,8,9,10,11,13,15,17,19,20}) do check(pool[1].cells[i].fs:GetText()=='n/a','recycling clears missing metric '..i) end
pool[1].cells[20]:Click('LeftButton'); check(app.ui.wowheadModal.currentURL==rich.wowheadURL,'recycled unavailable URL cannot open previous URL')
pool[1].cells[1]:GetScript('OnEnter')(pool[1].cells[1]); check(not table.concat(GameTooltip._lines,' '):find('Favor recipe',1,true),'recycled tooltip uses new identity')
-- Host hide and tab transitions stop jobs before another row is evaluated.
provider.Invalidate(); provider.Refresh(context); table.remove(queued,1)()
local interrupted=gets; app.panel:Hide(); drain()
check(gets==interrupted,'hidden window cancels incremental jobs')
check(searches==searchBefore,'no background AH searches')
collectgarbage('collect')
app.activeTab='recipes'; app.panel:Show(); provider.Invalidate(); provider.Refresh(context)
context.revision=2; context.econInfo={effectiveKey='Hardcore-Horde',label='Hardcore'}; provider.Refresh(context); drain()
check(#box._dp:GetCollection()== TOTAL_RECIPES,'replacement economy completes its own build')
local minimum=4; for _,col in ipairs(tbl.columns) do minimum=minimum+col.minWidth+5 end
check(minimum<=1430,'minimum width invariant <= 1430: '..minimum)
local available=minimum
box.GetWidth=function() return available end; tbl.headerBar.GetWidth=function() return available end
provider.Layout(available+24,600)
local right=tbl.colX[20]+tbl.columns[20].width
check(right<=available,'all columns fit measured minimum viewport with scrollbar reserved')
local getsBeforeLayout=gets
local narrow={}; for i,col in ipairs(tbl.columns) do narrow[i]=col.width end
available=minimum+600; provider.Layout(available+24,900)
check(tbl.columns[1].width>170,'Name expands first')
for i=2,20 do check(tbl.columns[i].width>narrow[i],'all columns expand proportionally '..i) end
local expanded=tbl.columns[1].width; provider.Layout(available+24,900); check(tbl.columns[1].width==expanded,'resizing is idempotent')
check(gets==getsBeforeLayout,'geometry only uses retained row data')
local expandedWidths={}; for i,col in ipairs(tbl.columns) do expandedWidths[i]=col.width end
available=minimum; provider.Layout(available+24,600)
for i,col in ipairs(tbl.columns) do
    check(col.width==col.minWidth,'minimum widths restored after shrink '..i)
    check(pool[1].cells[i]:GetWidth()==col.width and tbl.headerBtns[i]:GetWidth()==col.width,'header and visible cell widths align '..i)
end
local measure=skillView.measure
for _,index in ipairs({7,8,9,11,13,17}) do
    measure:SetText(ns.Theme.FormatMoneyText(99999999,index==13,false,'full_fixed')..(index==7 and '*' or ''))
    check(tbl.columns[index].align=='RIGHT' and tbl.columns[index].minWidth>=math.max(90,math.ceil(measure:GetStringWidth()+4)),
        'right-aligned full coin price and estimate marker fit '..index)
end
measure:SetText(ns.Theme.FormatMoneyText(-99999999,true,false,'full_fixed'))
check(tbl.columns[13].minWidth>=math.ceil(measure:GetStringWidth()+4),'negative full coin Profit fits')
available=minimum+600; provider.Layout(available+24,900)
for i,col in ipairs(tbl.columns) do check(col.width==expandedWidths[i],'shrink/expand preserves stable proportions '..i) end
-- Actual notification storms must preserve partial work and the last displayed table.
collectgarbage('collect')
context.db.superListSources={}; context.search=''; context.revision=3
local visible=box._dp:GetCollection()
provider.Refresh(context)
check(box._dp:GetCollection()==visible,'refresh keeps old rows visible while new economics load')
while gets==getsBeforeLayout and #queued>0 do table.remove(queued,1)() end
local partialGets=gets
check(partialGets>getsBeforeLayout,'new version made partial progress')
local jobStarts=starts
for i=1,20 do
    provider.Invalidate('ownership'); provider.Invalidate('snapshot'); provider.Invalidate('trainer')
    provider.Invalidate('items',{[987654321]=true}); provider.Refresh(context)
end
check(gets==partialGets and starts==jobStarts,'notifications never restart the active job')
provider.Cancel(); drain()
check(gets==partialGets,'pause cancels queued evaluation')
provider.Refresh(context); drain()
check(gets-partialGets== TOTAL_RECIPES-(partialGets-getsBeforeLayout),'reopen evaluates only unfinished recipes')
local completeGets=gets
provider.Cancel(); provider.Refresh(context); drain()
check(gets==completeGets,'completed dataset persists between opens')
collectgarbage('collect')
local store=ns.Analytics and ns.Analytics.Store
if store then
    local oldVersion,oldAccounting=store.version,store.accountingVersion
    store.accountingVersion=oldAccounting or 700
    provider.Refresh(context); drain()
    local baseGets=gets
    store.version=(oldVersion or 0)+1
    provider.Invalidate('snapshot'); provider.Refresh(context); drain()
    check(gets==baseGets,'snapshot-only ledger version cannot restart recipes')
    store.accountingVersion=store.accountingVersion+1
    provider.Refresh(context); drain()
    check(gets==baseGets+TOTAL_RECIPES,'accounting version builds replacement exactly once')
    store.version,store.accountingVersion=oldVersion,oldAccounting
    provider.Refresh(context); drain()
end
local beforeSkillGets=gets
context.profMap={alchemy=310}; provider.Invalidate('skills'); drain()
check(gets==beforeSkillGets,'sliced skill patch updates metadata without rebuilding')
local patchedAlch=false
for _,r in ipairs(box._dp:GetCollection()) do
    if r.prof=='alchemy' and r.unlock and r.unlock.playerSkill==310 then patchedAlch=true break end
end
check(patchedAlch,'sliced skill patch updates alchemy unlock playerSkill')

-- Best only moved to SEARCH & VIEW; Reset Filters / Reset All Filters buttons reset all filters in 1 refresh.
local function listContains(list, target)
    for _, item in ipairs(list or {}) do
        if item == target then return true end
    end
    return false
end
check(app.ui.bisOnlyCheck ~= nil, 'bisOnlyCheck exists in UI')
check(skillView.resetButton ~= nil and skillView.resetFiltersButton ~= nil, 'Super List Reset Filters and Reset All Filters buttons exist')
skillView.resetFiltersButton:GetScript('OnEnter')(skillView.resetFiltersButton)
check(GameTooltip._lines[1]=='Reset All Recipe Filters','sidebar reset tooltip uses the Recipe Filters label')
skillView.resetFiltersButton:GetScript('OnLeave')(skillView.resetFiltersButton)
local slControls = provider.GetSidebarControls()
check(not listContains(slControls, app.ui.bisOnlyCheck), 'GetSidebarControls excludes bisOnlyCheck after moving it to SEARCH & VIEW')
check(listContains(slControls, skillView.resetFiltersButton), 'GetSidebarControls includes resetFiltersButton')
check(not listContains(app.allDynamicSidebarControls, app.ui.bisOnlyCheck), 'allDynamicSidebarControls excludes global bisOnlyCheck')
check(listContains(app.allDynamicSidebarControls, skillView.resetFiltersButton), 'allDynamicSidebarControls registers resetFiltersButton for tab toggling')

app.setTab('dashboard'); app.refresh(); drain()
check(not skillView.resetFiltersButton:IsShown(), 'resetFiltersButton hides on dashboard tab')
check(app.ui.bisOnlyCheck:IsShown(), 'bisOnlyCheck stays visible in SEARCH & VIEW on other tabs')

app.setTab('recipes'); app.resetSuperListFilters(); drain()
check(not skillView.resetFiltersButton:IsShown() and skillView.resetButton:IsShown() and skillView.filtersButton:IsShown(),
    'inline Reset Filters and Filters buttons show on recipes tab while legacy sidebar reset stays hidden in tools mode')
check(#box._dp:GetCollection() == TOTAL_RECIPES, 'all 2057 recipes shown before Reset Filters checks')

local function applyAllNonDefaultFilters()
    MerchantMasterDB.profFilter = 'alchemy'
    MerchantMasterDB.unlockFilter = 'unlocked'
    MerchantMasterDB.knownRecipesOnly = true
    MerchantMasterDB.bisOnly = true
    MerchantMasterDB.craftableFilter = 'craftable'
    MerchantMasterDB.demandFilter = 'fast'
    MerchantMasterDB.sellableFilter = 'profitable'
    MerchantMasterDB.superListSources = { vendor = true }
    MerchantMasterDB.superListSkillMin = 50
    MerchantMasterDB.superListSkillMax = 200
    app.ui.searchBox:SetText('viridian')
    app.refresh(); drain()
    check(#box._dp:GetCollection() < TOTAL_RECIPES, 'active filters + search narrow Super List before reset')
end

local function assertAllFiltersReset(label)
    check(MerchantMasterDB.profFilter == 'all', label .. ': profFilter reset')
    check(MerchantMasterDB.unlockFilter == 'all', label .. ': unlockFilter reset')
    check(MerchantMasterDB.knownRecipesOnly == false, label .. ': knownRecipesOnly reset')
    check(MerchantMasterDB.bisOnly == false, label .. ': bisOnly reset')
    check(MerchantMasterDB.craftableFilter == 'all', label .. ': craftableFilter reset')
    check(MerchantMasterDB.demandFilter == 'all', label .. ': demandFilter reset')
    check(MerchantMasterDB.sellableFilter == 'all', label .. ': sellableFilter reset')
    check(next(MerchantMasterDB.superListSources or {}) == nil, label .. ': superListSources cleared')
    check(MerchantMasterDB.superListSkillMin == nil and MerchantMasterDB.superListSkillMax == nil, label .. ': skill range cleared')
    check(app.ui.searchBox:GetText() == '', label .. ': searchBox cleared')
    check(skillView.skillMin:GetText() == '' and skillView.skillMax:GetText() == '' and skillView.skillError:GetText() == '',
        label .. ': skill edit boxes and error cleared')
    check(#box._dp:GetCollection() == TOTAL_RECIPES, label .. ': all 2057 recipes restored')
end

applyAllNonDefaultFilters()
local getsBeforeReset1 = gets
skillView.resetButton:Click('LeftButton'); drain()
check(gets == getsBeforeReset1, 'top bar Reset Filters button triggers zero recipe re-evaluation')
assertAllFiltersReset('top bar Reset Filters')

applyAllNonDefaultFilters()
local getsBeforeReset2 = gets
skillView.resetFiltersButton:Click('LeftButton'); drain()
check(gets == getsBeforeReset2, 'sidebar Reset All Filters button triggers zero recipe re-evaluation')
assertAllFiltersReset('sidebar Reset All Filters')

-- Sidebar min-height clearance (MIN_H=730 -> sidebar=604px -> shopCard top at -546)
local resetPt = skillView.resetFiltersButton._points and skillView.resetFiltersButton._points[1]
local resetBottom = (resetPt and resetPt[5] or 0) - skillView.resetFiltersButton:GetHeight()
check(resetBottom >= -540, 'resetFiltersButton clears shopCard at MIN_H=730: bottom=' .. tostring(resetBottom))

-- Focus-loss commit during Reset Filters should not fire a duplicate refresh
local sortsBeforeBaseline = sorts
MerchantMasterDB.superListSkillMin = 50
app.refresh(); drain()
local sortsPerPresent = sorts - sortsBeforeBaseline
check(sortsPerPresent > 0, 'baseline skill filter triggers one chunked FilterSort presentation')
local origClearFocus = skillView.skillMin.ClearFocus
local focusedMin = true
skillView.skillMin.ClearFocus = function(self)
    if focusedMin then
        focusedMin = false
        local onLost = self:GetScript('OnEditFocusLost')
        if onLost then onLost(self) end
    end
end
skillView.skillMin:SetText('120')
local refreshCount, providerRefreshCount = 0, 0
local origAppRefresh = app.refresh
local origProviderRefresh = provider.Refresh
app.refresh = function(...)
    refreshCount = refreshCount + 1
    return origAppRefresh(...)
end
provider.Refresh = function(...)
    providerRefreshCount = providerRefreshCount + 1
    return origProviderRefresh(...)
end
local sortsBeforeFocusReset = sorts
skillView.resetButton:Click('LeftButton'); drain()
app.refresh = origAppRefresh
provider.Refresh = origProviderRefresh
skillView.skillMin.ClearFocus = origClearFocus
check(refreshCount == 1, 'Reset Filters with uncommitted focused skill input calls app.refresh only once: ' .. refreshCount)
check(providerRefreshCount == 1, 'Reset Filters with uncommitted focused skill input calls provider.Refresh only once: ' .. providerRefreshCount)
check(sorts == sortsBeforeFocusReset, 'Reset Filters with uncommitted focused skill input hits LRU cache with 0 FilterSort re-runs')
check(skillView.skillMin:GetText() == '' and MerchantMasterDB.superListSkillMin == nil, 'uncommitted skill input cleared cleanly')

-- Shift-hold quick-add mode: stepper -/qty/+, Shift-Left/Right-Click, 0 AH searches, header badge, [Nx] prefix
app.clearCraftingOrderQueue(); drain()
render()
local shopLbl = (skillView.shopButton._mmLabel and skillView.shopButton._mmLabel:GetText()) or skillView.shopButton:GetText()
check(shopLbl == 'Shopping List', 'shopButton text stays strictly Shopping List: ' .. tostring(shopLbl))
check(skillView.shiftBadge ~= nil and not skillView.shiftBadge:IsShown(), 'shiftBadge hidden when Shift not active')
local firstRowData = pool[1].data
check(firstRowData ~= nil, 'first row bound before Shift mode test')
local searchesBeforeShift = searches
local oldShiftFn = _G.IsShiftKeyDown
_G.IsShiftKeyDown = function() return true end
provider.SetShiftMode(true)
check(skillView.shiftBadge:IsShown(), 'shiftBadge visible in Shift quick-add mode')
check(pool[1].shiftStepper ~= nil and pool[1].shiftStepper:IsShown(), 'row stepper visible in Shift mode')
check(not pool[1].cells[19]:IsShown() and not pool[1].cells[20]:IsShown(), 'Best and WH cells hidden behind stepper in Shift mode')
check(pool[1].shiftStepper.qtyFs:GetText() == '0', 'stepper qty starts at 0')
check(pool[1].stripe._colorTexture and pool[1].stripe._colorTexture[3] > 0.5, 'unqueued row has subtle blue stripe in Shift mode')
pool[1].shiftStepper.plusBtn:Click('LeftButton')
check(app.getRecipeShoppingQty(firstRowData) == 1 and pool[1].shiftStepper.qtyFs:GetText() == '1', 'stepper + LeftClick adds 1')
check(pool[1].stripe._colorTexture and pool[1].stripe._colorTexture[2] > pool[1].stripe._colorTexture[1], 'queued row turns green stripe in Shift mode')
pool[1].shiftStepper.plusBtn:Click('RightButton')
check(app.getRecipeShoppingQty(firstRowData) == 6 and pool[1].shiftStepper.qtyFs:GetText() == '6', 'stepper + RightClick adds 5')
pool[1].shiftStepper.minusBtn:Click('LeftButton')
check(app.getRecipeShoppingQty(firstRowData) == 5 and pool[1].shiftStepper.qtyFs:GetText() == '5', 'stepper - LeftClick subtracts 1')
pool[1].shiftStepper.minusBtn:Click('RightButton')
check(app.getRecipeShoppingQty(firstRowData) == 0 and pool[1].shiftStepper.qtyFs:GetText() == '0', 'stepper - RightClick removes all')
pool[1].cells[1]:Click('LeftButton')
check(app.activeTab == 'recipes' and app.getRecipeShoppingQty(firstRowData) == 1, 'Shift-Left-Click on cell stays on All Recipes and adds 1')
pool[1].cells[1]:Click('RightButton')
check(app.activeTab == 'recipes' and app.getRecipeShoppingQty(firstRowData) == 0, 'Shift-Right-Click on cell subtracts 1 back to 0')
check(searches == searchesBeforeShift, 'Shift quick-add issues 0 AH searches')
pool[1].shiftStepper.plusBtn:Click('LeftButton')
pool[1].shiftStepper.plusBtn:Click('LeftButton')
_G.IsShiftKeyDown = oldShiftFn
provider.SetShiftMode(false)
check(not skillView.shiftBadge:IsShown() and not pool[1].shiftStepper:IsShown(), 'Shift release hides shiftBadge and row stepper')
check(pool[1].cells[19]:IsShown() and pool[1].cells[20]:IsShown(), 'Shift release restores Best and WH cells')
check((pool[1].cells[1].fs:GetText() or ''):find('[2x]', 1, true) ~= nil, 'Queued recipe displays green [2x] prefix on Name when Shift released')
app.clearCraftingOrderQueue(); drain()
check((pool[1].cells[1].fs:GetText() or ''):find('[2x]', 1, true) == nil, 'Clearing queue repaints Name without [2x] prefix')

C_Timer.After=oldAfter; debugprofilestop=oldProfile
check(maxCallback<=4.001,'full pipeline retains callback budget after filters and economy replacement')
ns.SuperListModel.Start=oldStart; ns.RecipeStats.Get=oldGet; ns.SuperListModel.FilterSort=oldSort; app.searchAH=oldSearch

do
    local name, itemID
    app.searchAH=function(term,_,id) name,itemID=term,id end
    local frame=CreateFrame('Button',nil,box)
    box._view._initFn(frame,{key='transmute-output',name='Transmute: Arcanite',outputItemID=12360})
    frame:Click('LeftButton')
    check(name=='Arcanite Bar' and itemID==12360,'an uncached transmute searches by its catalog output name')
    name,itemID=nil,nil
    box._view._initFn(frame,{key='unknown-output',name='Spell Name',outputItemID=99004403})
    frame:Click('LeftButton')
    check(not name and itemID==99004403 and ns.pendingItemLoads[99004403],
        'an unresolved output requests item data and forwards its ID so searchAH can cancel the previous search')
    app.searchAH=oldSearch
end

-- Phase 2 + Phase 3: Recipe cooldowns, shared Alchemy Transmute cooldowns, Salt Shaker, and Shift stepper guards
do
    local entryBySpell = {}
    for _, entry in ipairs(ns.RecipeStats.GetCatalog()) do
        if entry.recipe and entry.recipe.spellID then entryBySpell[entry.recipe.spellID] = entry end
    end
    local arcEntry = entryBySpell[17187]
    local eleEntry = entryBySpell[25146]
    local arcanite = arcEntry and arcEntry.recipe
    local undeath = entryBySpell[17563] and entryBySpell[17563].recipe
    local legionite = entryBySpell[1317279] and entryBySpell[1317279].recipe
    local ironToGold = entryBySpell[11479] and entryBySpell[11479].recipe
    local mithrilToTruesilver = entryBySpell[11480] and entryBySpell[11480].recipe
    local airToFire = entryBySpell[17559] and entryBySpell[17559].recipe
    local elemFire = eleEntry and eleEntry.recipe
    local mooncloth = entryBySpell[18560] and entryBySpell[18560].recipe
    local ruggedHide = entryBySpell[19047] and entryBySpell[19047].recipe
    local refinedSalt = entryBySpell[19566] and entryBySpell[19566].recipe
    check(arcanite and undeath and legionite and ironToGold and mithrilToTruesilver and airToFire and elemFire and mooncloth and ruggedHide and refinedSalt,
        'all expected cooldown recipes present in catalog')
    check(refinedSalt.outputItemID == 15409 and refinedSalt.toolItemID == 15846 and refinedSalt.recipeItemID == 15846
        and refinedSalt.prof == 'leatherworking' and refinedSalt.skill == 250,
        'Refined Deeprock Salt uses Salt Shaker (15846) under Leatherworking (250)')
    check(ns.GetRecipeBaseCooldown(ruggedHide) == nil and ns.GetRecipeCooldownInfo(ruggedHide) == nil,
        'Cured Rugged Hide (19047) has no cooldown')

    local ch = ns.activeChar or app.char
    local savedKnown = {}
    local cooldownSpells = {17187, 17563, 1317279, 11479, 11480, 17559, 25146, 18560, 19566}
    for _, sid in ipairs(cooldownSpells) do
        savedKnown[sid] = ch.knownSpells and ch.knownSpells[sid]
    end
    local savedCD = ch.cooldowns
    local savedCDGroups = ch.cooldownGroups
    local oldGetSpellCooldown = _G.GetSpellCooldown
    local oldGetItemCooldown = _G.GetItemCooldown
    local oldGetItemInfo = C_Item.GetItemInfo
    local oldGetRecipeCooldown = _G.C_TradeSkillUI and _G.C_TradeSkillUI.GetRecipeCooldown
    local oldCSpellGet = _G.C_Spell and _G.C_Spell.GetSpellCooldown
    local oldGetProfs = _G.GetProfessions
    local oldGetProfInfo = _G.GetProfessionInfo

    _G.GetProfessions = function() return 1, 2, nil, nil, 3, nil end
    _G.GetProfessionInfo = function(idx)
        if idx == 1 then return "Alchemy", 136240, 300, 300, 0, 0, 171 end
        if idx == 2 then return "Tailoring", 136249, 250, 300, 0, 0, 197 end
        if idx == 3 then return "Leatherworking", 133611, 250, 300, 0, 0, 165 end
    end
    if ns.ResetEval then ns.ResetEval() end

    ch.knownSpells = ch.knownSpells or {}
    ch.knownSpells[17187] = true
    ch.knownSpells[25146] = true
    ch.knownSpells[18560] = true
    ch.knownSpells[19047] = true
    ch.knownSpells[17563] = nil
    ch.knownSpells[1317279] = nil
    ch.knownSpells[11479] = true
    ch.knownSpells[11480] = true
    ch.cooldowns = {}
    ch.cooldownGroups = {}

    local activeSpells = {}
    local activeItems = {}
    _G.GetSpellCooldown = function(sid)
        local rem = activeSpells[sid]
        if rem then return (GetTime() - 10), rem + 10 end
        return 0, 0
    end
    _G.GetItemCooldown = function(iid)
        local rem = activeItems[iid]
        if rem then return (GetTime() - 5), rem + 5 end
        return 0, 0
    end
    if _G.C_TradeSkillUI then _G.C_TradeSkillUI.GetRecipeCooldown = nil end
    if _G.C_Spell then _G.C_Spell.GetSpellCooldown = nil end

    local readyInfo = ns.GetRecipeCooldownInfo(arcanite)
    check(readyInfo and readyInfo.hasCooldown and readyInfo.baseSeconds == 169200
        and readyInfo.nominalSeconds == 172800 and readyInfo.windowLabel == '48h'
        and math.abs(readyInfo.maxPerDay - 0.5) < 0.001
        and readyInfo.sharedGroup == 'alchemy_transmute' and readyInfo.isShared == true
        and readyInfo.available == true and readyInfo.availableLabel == 'Yes',
        'Transmute: Arcanite reports 48h shared cooldown and ready state')

    local elemReady = ns.GetRecipeCooldownInfo(elemFire)
    check(elemReady and elemReady.windowLabel == '10m' and elemReady.sharedGroup == nil and elemReady.isShared == false,
        'Transmute: Elemental Fire (10m) is independent with no sharedGroup')
    local moonReady = ns.GetRecipeCooldownInfo(mooncloth)
    check(moonReady and moonReady.windowLabel == '4d' and moonReady.sharedGroup == nil and moonReady.available == true,
        'Mooncloth (4d) is independent with no sharedGroup')

    -- Arcanite locks only shared transmutes.
    activeSpells[17187] = 36000
    local arcCD = ns.GetRecipeCooldownInfo(arcanite)
    local undCD = ns.GetRecipeCooldownInfo(undeath)
    local legCD = ns.GetRecipeCooldownInfo(legionite)
    local irnCD = ns.GetRecipeCooldownInfo(ironToGold)
    local mitCD = ns.GetRecipeCooldownInfo(mithrilToTruesilver)
    local eleCD = ns.GetRecipeCooldownInfo(elemFire)
    local mooCD = ns.GetRecipeCooldownInfo(mooncloth)
    check(arcCD.onCooldown == true and arcCD.available == false and arcCD.availableLabel == 'No',
        'Active Arcanite timer marks 17187 onCooldown')
    check(undCD.onCooldown and legCD.onCooldown and undCD.sharedGroup == 'alchemy_transmute'
        and legCD.sharedGroup == 'alchemy_transmute', 'Arcanite cooldown locks Undeath to Water and Legionite')
    for _, info in ipairs({irnCD, mitCD}) do
        check(info.baseSeconds == 3600 and info.sharedGroup == nil and info.isShared == false and info.available,
            'One-hour transmute stays ready during Arcanite cooldown')
    end
    activeSpells[11479] = 1800
    check(ns.GetRecipeCooldownInfo(ironToGold).onCooldown and ns.GetRecipeCooldownInfo(mithrilToTruesilver).available,
        'Iron to Gold does not lock Mithril to Truesilver')
    activeSpells[11479], activeSpells[11480] = nil, 1800
    check(ns.GetRecipeCooldownInfo(mithrilToTruesilver).onCooldown and ns.GetRecipeCooldownInfo(ironToGold).available,
        'Mithril to Truesilver does not lock Iron to Gold')
    activeSpells[11480] = nil
    check(eleCD.onCooldown == false and eleCD.available == true and mooCD.onCooldown == false and mooCD.available == true,
        'Independent recipes 25146 (10m) and 18560 (4d) remain CD: Yes')
    check(tonumber(ch.cooldowns[17187]) ~= nil and tonumber(ch.cooldownGroups.alchemy_transmute) ~= nil,
        'Active shared cooldown persists in char.cooldowns and char.cooldownGroups')

    -- Salt Shaker 15846 item ownership + cooldown maps onto Refined Deeprock Salt 19566 (not Cured Rugged Hide 19047)
    local savedSaltShakerBag = ch.bags and ch.bags['Salt Shaker']
    ch.bags = ch.bags or {}
    ch.bags['Salt Shaker'] = nil
    ch.knownSpells[19566] = nil
    if ns.ResetEval then ns.ResetEval() end
    check(ns.IsRecipeKnown(refinedSalt) == false, 'Refined Deeprock Salt requires owning Salt Shaker')
    ch.bags['Salt Shaker'] = 1
    if ns.ResetEval then ns.ResetEval() end
    local saltReady = ns.GetRecipeCooldownInfo(refinedSalt)
    check(ns.IsRecipeKnown(refinedSalt) == true and saltReady and saltReady.available == true and saltReady.windowLabel == '72h',
        'Owning Salt Shaker at LW 250 marks Refined Deeprock Salt known and ready (72h)')
    activeItems[15846] = 7200
    local saltCD = ns.GetRecipeCooldownInfo(refinedSalt)
    local hideCD = ns.GetRecipeCooldownInfo(ruggedHide)
    check(saltCD.onCooldown == true and saltCD.sharedGroup == nil and saltCD.windowLabel == '72h',
        'Salt Shaker 15846 cooldown marks Refined Deeprock Salt 19566 onCooldown')
    check(hideCD == nil,
        'Salt Shaker 15846 cooldown leaves Cured Rugged Hide 19047 without a cooldown')
    activeItems[15846] = nil
    ch.bags['Salt Shaker'] = savedSaltShakerBag

    -- Row binding & tooltip assertions for cooldown recipes
    local cdCtx = { db = context.db, search = '', profFilter = 'all', unlockFilter = 'all', knownRecipesOnly = false,
        subCraftMode = 'smart', ownedCounts = {}, profMap = { alchemy = 300 }, repState = { standing = 4 }, econInfo = context.econInfo, revision = 99 }
    C_Item.GetItemInfo = function(id)
        if id == 3577 then return 'Gold Bar' end
        if id == 6037 then return 'Truesilver Bar' end
        return oldGetItemInfo(id)
    end
    cdCtx.ownedCounts['Gold Bar'] = 3
    local ironRow = ns.RecipeStats.Get(ironToGold, cdCtx)
    local mithrilRow = ns.RecipeStats.Get(mithrilToTruesilver, cdCtx)
    check(ironRow.name == 'Transmute: Iron to Gold' and mithrilRow.name == 'Transmute: Mithril to Truesilver',
        'Transmutes display their recipe names when the native item API returns bar names')
    check(ironRow.ownedOutputQty == 3, 'Iron to Gold counts Gold Bar inventory by item name')
    local goldRows = ns.SuperListModel.FilterSort({ironRow, mithrilRow}, {search='Gold Bar'}, {})
    check(#goldRows == 1 and goldRows[1] == ironRow, 'Searching Gold Bar finds Transmute: Iron to Gold')
    C_Item.GetItemInfo = oldGetItemInfo
    local arcRow = ns.RecipeStats.Get(arcanite, cdCtx)
    local elemRow = ns.RecipeStats.Get(elemFire, cdCtx)
    check(arcRow.cdSort > 1 and elemRow.cdSort == 0, 'cdSort ranks ready (0) before active cooldown (>1)')
    box._view._initFn(pool[1], arcRow)
    check(not (pool[1].cells[1].fs:GetText() or ''):find('CD:', 1, true),
        'Name cell omits inline CD badge after moving to dedicated CD column')
    check((pool[1].cells[3].fs:GetText() or '') == '10h',
        'On-cooldown recipe displays remaining hours in CD cell, got ' .. tostring(pool[1].cells[3].fs:GetText()))
    local arcCdCol = pool[1].cells[3].fs._lastColor
    check(arcCdCol and arcCdCol[1] > arcCdCol[2], 'On-cooldown CD cell uses red text')
    pool[1].cells[1]:GetScript('OnEnter')(pool[1].cells[1])
    local cdTipOn = table.concat(GameTooltip._lines, ' ')
    check(cdTipOn:find('Item:' .. tostring(arcanite.outputItemID), 1, true) ~= nil,
        'Row hover triggers native GameTooltip:SetItemByID for output item')
    check(cdTipOn:find('(Shared Alchemy Transmute CD)', 1, true) ~= nil and cdTipOn:find('Cooldown Available', 1, true) ~= nil,
        'Shared Transmute tooltip displays Shared Alchemy Transmute CD and Cooldown Available')

    -- Shift quick-add catalog caps cooldown recipe at 1 and blocks conflicting shared transmute
    local oldShiftFn2 = _G.IsShiftKeyDown
    _G.IsShiftKeyDown = function() return true end
    provider.SetShiftMode(true)
    app.clearCraftingOrderQueue()
    box._view._initFn(pool[1], arcRow)
    pool[1].shiftStepper.plusBtn:Click('LeftButton')
    pool[1].shiftStepper.plusBtn:Click('LeftButton')
    check(app.getRecipeShoppingQty(arcanite) == 1, 'Shift stepper caps cooldown craft at 1')
    local blockedShared = app.adjustRecipeShoppingQty(airToFire, 1)
    check(blockedShared == 0 and app.getRecipeShoppingQty(airToFire) == 0,
        'All Recipes Shift catalog blocks queueing conflicting shared Transmute Air to Fire')
    local allowedIndep = app.adjustRecipeShoppingQty(elemFire, 1)
    check(allowedIndep == 1 and app.getRecipeShoppingQty(elemFire) == 1,
        'All Recipes Shift catalog allows independent Transmute Elemental Fire alongside Arcanite')
    for _, recipe in ipairs({ironToGold, mithrilToTruesilver, elemFire}) do
        app.adjustRecipeShoppingQty(recipe, 1)
        app.adjustRecipeShoppingQty(recipe, 1)
        check(app.getRecipeShoppingQty(recipe) > 1, recipe.name .. ' can queue more than one batch')
    end
    app.clearCraftingOrderQueue()
    _G.IsShiftKeyDown = oldShiftFn2
    provider.SetShiftMode(false)

    -- Clearing live cooldown marks shared group ready again
    activeSpells[17187] = nil
    local arcCleared = ns.GetRecipeCooldownInfo(arcanite)
    check(arcCleared.onCooldown == false and arcCleared.available == true and ch.cooldownGroups.alchemy_transmute == nil,
        'Expired live cooldown clears char.cooldownGroups and restores ready state')
    ns.RecipeStats.PatchMeta({ arcRow, elemRow }, cdCtx)
    check(arcRow.cdSort == 0, 'PatchMeta updates cdSort to 0 when cooldown clears')
    box._view._initFn(pool[1], arcRow)
    check((pool[1].cells[3].fs:GetText() or '') == 'R',
        'Ready cooldown recipe displays R in dedicated CD cell, got ' .. tostring(pool[1].cells[3].fs:GetText()))
    local readyCdCol = pool[1].cells[3].fs._lastColor
    check(readyCdCol and readyCdCol[2] > readyCdCol[1], 'Ready CD cell uses green text')

    -- Enchanting recipe without outputItemID falls back to SetSpellByID / spell: hyperlink
    local enchSpellRec
    for _, entry in ipairs(ns.RecipeStats.GetCatalog()) do
        if entry.recipe and not entry.recipe.outputItemID and entry.recipe.spellID then
            enchSpellRec = entry.recipe
            break
        end
    end
    if enchSpellRec then
        local enchRow = ns.RecipeStats.Get(enchSpellRec, cdCtx)
        box._view._initFn(pool[1], enchRow)
        pool[1].cells[1]:GetScript('OnEnter')(pool[1].cells[1])
        local enchTip = table.concat(GameTooltip._lines, ' ')
        check(enchTip:find('spell:' .. tostring(enchSpellRec.spellID), 1, true) ~= nil,
            'Recipe without outputItemID uses spell: tooltip hyperlink')
    end

    box._view._initFn(pool[1], elemRow)
    pool[1].cells[1]:GetScript('OnEnter')(pool[1].cells[1])
    check(table.concat(GameTooltip._lines, ' '):find('(Independent CD)', 1, true) ~= nil,
        'Independent cooldown tooltip displays (Independent CD)')

    _G.GetProfessions = oldGetProfs
    _G.GetProfessionInfo = oldGetProfInfo
    _G.GetSpellCooldown = oldGetSpellCooldown
    _G.GetItemCooldown = oldGetItemCooldown
    if _G.C_TradeSkillUI then _G.C_TradeSkillUI.GetRecipeCooldown = oldGetRecipeCooldown end
    if _G.C_Spell then _G.C_Spell.GetSpellCooldown = oldCSpellGet end
    for _, sid in ipairs(cooldownSpells) do ch.knownSpells[sid] = savedKnown[sid] end
    ch.cooldowns = savedCD
    ch.cooldownGroups = savedCDGroups
    if ns.ResetEval then ns.ResetEval() end
end

-- Phase 5: Column Customizer hide, reorder, persistence, popover toggle, and zero recipe re-evals
do
    local getsBeforeCol = 0
    local origGetCol = ns.RecipeStats.Get
    ns.RecipeStats.Get = function(...) getsBeforeCol = getsBeforeCol + 1; return origGetCol(...) end

    check(skillView.colSettingsBtn ~= nil and skillView.colSettingsPopover ~= nil, 'Column Customizer button and popover exist')
    check(not skillView.colSettingsPopover:IsShown(), 'Column Customizer popover starts hidden')
    skillView.colSettingsBtn:Click('LeftButton')
    check(skillView.colSettingsPopover:IsShown(), 'Clicking colSettingsBtn opens Column Customizer popover')
    check(#skillView.colSettingsPopover.rows == 20, 'Customizer popover has 20 column rows')

    check(provider.SetColumnVisible('name', false) == false, 'Name column cannot be hidden')
    check(provider.SetColumnVisible('wowheadURL', false) == true, 'Can hide wowheadURL column')
    check(#tbl.columns == 19, 'Hiding 1 column updates active table to 19 columns')
    check(provider.MoveColumn('cdSort', -1) == true, 'Can move cdSort column before knownSort')
    check(tbl.columns[2].key == 'cdSort' and tbl.columns[3].key == 'knownSort', 'Column reorder updates active column order')
    local cfg = provider.GetColumnConfig()
    check(cfg.hidden.wowheadURL == true and cfg.order[2] == 'cdSort', 'Column customizations persist in MerchantMasterDB.superListColumns')
    check(getsBeforeCol == 0, 'Column customizations trigger zero recipe re-evaluations')

    check(provider.ResetColumns() == true, 'ResetColumns restores defaults')
    check(#tbl.columns == 20 and tbl.columns[2].key == 'knownSort' and tbl.columns[3].key == 'cdSort', 'ResetColumns restores 20 columns and original order')
    skillView.colSettingsPopover.closeBtn:Click('LeftButton')
    check(not skillView.colSettingsPopover:IsShown(), 'Popover close button hides Customizer')

    ns.RecipeStats.Get = origGetCol
end

-- Phase 6: World faction reputation tooltip, live invalidation & search filtering
do
    local getsRep, origGetRep = 0, ns.RecipeStats.Get
    ns.RecipeStats.Get = function(...) getsRep = getsRep + 1; return origGetRep(...) end

    local savedRep = context.repState
    context.repState = { standing = 8, playerFaction = 'Horde' }
    provider.Invalidate('rep'); provider.Refresh(context); drain()

    local allRows = box._dp:GetCollection()
    local waterRow
    for _, r in ipairs(allRows) do
        if r.recipe and r.recipe.recipeItemID == 13484 then waterRow = r; break end
    end
    check(waterRow ~= nil, 'Transmute: Earth to Water appears in All Recipes')
    check(waterRow.reqRep == 5 and waterRow.repLabel == 'Friendly' and waterRow.repFactionName == 'Timbermaw Hold' and waterRow.repMet == false,
        'Timbermaw Hold Friendly stays unmet even when Camp is Exalted')

    box._view._initFn(pool[1], waterRow)
    local onEnter = pool[1].cells[1]:GetScript('OnEnter')
    GameTooltip._lines = {}
    onEnter(pool[1].cells[1])
    local tipRequired = table.concat(GameTooltip._lines or {}, ' ')
    check(tipRequired:find('Timbermaw Hold - Friendly (Required)', 1, true) ~= nil, 'Tooltip surfaces Timbermaw Hold - Friendly (Required)')

    local getsBeforeFaction = getsRep
    context.repState = { standing = 8, playerFaction = 'Horde', factions = { [576] = 5 } }
    provider.Invalidate('rep'); provider.Refresh(context); drain()
    check(getsRep == getsBeforeFaction, 'Live per-faction rep invalidation patches metadata without full rebuild')
    check(waterRow.repMet == true, 'Setting Timbermaw Hold standing 5 updates repMet to true')

    box._view._initFn(pool[1], waterRow)
    GameTooltip._lines = {}
    onEnter(pool[1].cells[1])
    local tipMet = table.concat(GameTooltip._lines or {}, ' ')
    check(tipMet:find('Timbermaw Hold - Friendly (Met)', 1, true) ~= nil, 'Tooltip updates to Timbermaw Hold - Friendly (Met)')

    local matchesTimber = ns.SuperListModel.FilterSort(allRows, { search = 'timbermaw' }, { key = 'profit', ascending = false })
    local foundWater = false
    for _, mr in ipairs(matchesTimber) do
        if mr == waterRow then foundWater = true end
    end
    check(#matchesTimber >= 11 and foundWater, 'Searching "timbermaw" matches all Timbermaw Hold recipes')

    context.repState = savedRep
    provider.Invalidate('rep'); provider.Refresh(context); drain()
    ns.RecipeStats.Get = origGetRep
end

-- Sustained All Recipes interaction and recovery checks.
do
    local stressOldProfile=debugprofilestop
    debugprofilestop=function() return os.clock()*1000 end
    local stressOldStart=ns.SuperListModel.Start
    ns.SuperListModel.Start=function(...)
        starts=starts+1
        return stressOldStart(...)
    end
    local stressRows=box._dp:GetCollection()
    local stressStarts=starts
    check(#stressRows==TOTAL_RECIPES,'stress catalog includes every recipe')
    local registeredWidgets
    for index=1,12 do
        local name,value=debug.getupvalue(ns.Theme.RegisterWidget,index)
        if not name then break end
        if name=='registeredWidgets' then registeredWidgets=value; break end
    end
    local registeredAtStart=registeredWidgets and #registeredWidgets or 0
    local originalGetTime=GetTime
    local virtualSeconds=0
    GetTime=function() return originalGetTime()+virtualSeconds end
    for i=1,600 do
        virtualSeconds=i/10
        offset=i==600 and (#stressRows-capacity+1) or (((i*17-1)%(#stressRows-capacity+1))+1)
        render()
    end
    GetTime=originalGetTime
    check(virtualSeconds==60 and offset==#stressRows-capacity+1,'600 scroll steps cover 60 virtual seconds and reach the last row')
    check(#pool<=capacity+4,'600 scroll steps keep the row pool bounded')
    check(starts==stressStarts,'scrolling the complete catalog does not restart its build')
    local cellLayoutCalls=0
    for _,widget in ipairs(pool) do
        for _,cell in ipairs(widget.cells or {}) do
            local clear=cell.ClearAllPoints
            cell.ClearAllPoints=function(self,...)
                cellLayoutCalls=cellLayoutCalls+1
                return clear(self,...)
            end
        end
    end
    local layoutBaseline=cellLayoutCalls
    for i=1,10 do offset=1; render() end
    check(cellLayoutCalls==layoutBaseline,'recycled rows skip unchanged cell layout work')

    local hoverCell=pool[1].cells[1]
    local onEnter=hoverCell:GetScript('OnEnter')
    local onLeave=hoverCell:GetScript('OnLeave')
    for i=1,200 do
        onEnter(hoverCell)
        onLeave(hoverCell)
    end
    check(not GameTooltip:IsShown(),'200 hover sweeps leave no tooltip open')
    local oldSetTooltipOwner=GameTooltip.SetOwner
    local ownerCalls=0
    GameTooltip.SetOwner=function(self,...)
        ownerCalls=ownerCalls+1
        return oldSetTooltipOwner(self,...)
    end
    onEnter(hoverCell); onEnter(hoverCell)
    check(ownerCalls==1,'repeated hover on the same row reuses its tooltip')
    onLeave(hoverCell); onEnter(hoverCell)
    check(ownerCalls==2,'leaving and re-entering refreshes the tooltip')
    onLeave(hoverCell)
    GameTooltip.SetOwner=oldSetTooltipOwner

    local oldPrint=print
    local chatLines={}
    print=function(line) chatLines[#chatLines+1]=tostring(line) end
    local oldAH=AuctionHouseFrame
    local immediateSearches,raises=0,0
    local ah={SearchBar={
        FilterButton={},
        SearchBox={SetText=function() end},
        SetSearchText=function() end,
        StartSearch=function() immediateSearches=immediateSearches+1 end,
    },IsShown=function() return true end,Raise=function() raises=raises+1 end,
        SetDisplayMode=function() end}
    AuctionHouseFrame=ah
    local searchTimers={}
    local maxClick=0
    local function timedClick(widget,button)
        local before=os.clock()
        widget:Click(button)
        maxClick=math.max(maxClick,(os.clock()-before)*1000)
    end
    C_Timer.After=function(delay,fn)
        if delay==0.18 then searchTimers[#searchTimers+1]=fn else queued[#queued+1]=fn end
    end
    local searchRowIndex
    for i,row in ipairs(stressRows) do
        if row.outputItemID then searchRowIndex=i; break end
    end
    check(searchRowIndex~=nil,'stress catalog has an AH-searchable output row')
    offset=searchRowIndex
    render()
    provider.CloseQuickLook()
    for i=1,60 do
        timedClick(pool[1],'LeftButton')
        timedClick(pool[1],'RightButton')
    end
    check(raises==0,'recipe row clicks never raise the Auction House over the recipes panel')
    check(immediateSearches==0,'rapid recipe clicks defer coalesced AH searches')
    check(#searchTimers==30 and not provider.GetQuickLookFrame():IsShown(),
        'only the left clicks that open Quick Look schedule Auction House searches')
    for _,fn in ipairs(searchTimers) do runCallback(fn) end
    check(immediateSearches==1,'rapid AH searches coalesce to the final request')

    ah.IsShown=function() return false end
    searchTimers={}
    for i=1,120 do
        offset=((i-1)%math.max(1,#stressRows-capacity+1))+1
        render()
        timedClick(pool[1],i%2==0 and 'RightButton' or 'LeftButton')
    end
    local openAHMessages=0
    for _,line in ipairs(chatLines) do
        if line:find('Open the Auction House',1,true) then openAHMessages=openAHMessages+1 end
    end
    check(openAHMessages==0,'recipe clicks with AH closed do not print open-AH messages')
    drain()
    check(maxClick<=5.001*ciScale,'synchronous row clicks stay within five milliseconds: '..maxClick)
    check(maxCallback<=4.001,'row-click callbacks stay under four milliseconds: '..maxCallback)
    local rowClickMax=maxClick
    AuctionHouseFrame=oldAH
    C_Timer.After=function(_,fn) queued[#queued+1]=fn end
    print=oldPrint

    local modal,shopPanel=app.ui.shopModal,app.ui.shopPanel
    modal:Hide()
    local originalSetRows,shopBinds=shopPanel.table.setRows,0
    shopPanel.table.setRows=function(displayRows)
        shopBinds=shopBinds+1
        originalSetRows(displayRows)
    end
    local preview={{itemID=2447,name='Peacebloom',qty=1,lineCost=15,role='Reagent'}}
    app.setActiveShoppingList(preview)
    check(shopBinds==0 and shopPanel.rawRows==preview and shopPanel.currentRows==app.activeShoppingRows
        and #app.activeShoppingRows==1,'hidden shopping modal keeps preview data without rebinding')
    modal:Show()
    check(shopBinds==1,'showing the shopping modal binds the latest preview once')
    modal:Hide()
    drain()
    shopPanel.table.setRows=originalSetRows

    local oldShiftStress=IsShiftKeyDown
    IsShiftKeyDown=function() return true end
    provider.SetShiftMode(true)
    offset=1
    render()
    local stepper=pool[1].shiftStepper
    check(stepper~=nil,'Shift mode exposes recipe quantity steppers')
    local quickRow=pool[1].data
    check(#(MerchantMasterDB.craftOrderQueue or {})==0,'stress quick-add starts with an empty queue')
    local originalForEachFrame,paints=box.ForEachFrame,0
    box.ForEachFrame=function(self,fn)
        paints=paints+1
        return originalForEachFrame(self,fn)
    end
    maxClick=0
    for i=1,60 do
        timedClick(pool[1],'LeftButton')
        check(stepper.qtyFs:GetText()=='1','Shift-click updates the stepper immediately')
        timedClick(pool[1],'RightButton')
    end
    for i=1,60 do
        timedClick(stepper.plusBtn,'LeftButton')
        check(stepper.qtyFs:GetText()=='1','plus button updates the stepper immediately')
        timedClick(stepper.minusBtn,'LeftButton')
    end
    box.ForEachFrame=originalForEachFrame
    check(paints==240,'each Shift-click or stepper change repaints visible rows once: '..paints)
    check(app.getRecipeShoppingQty(quickRow)==0,'60 Shift click and stepper pairs preserve zero queued quantity')
    check(stepper.qtyFs:GetText()=='0','decrement clears the displayed quantity')
    timedClick(stepper.plusBtn,'LeftButton')
    check(drain()==1,'a burst of quantity changes schedules one basket rebuild')
    check(app.rawUnifiedShoppingRows[1] and app.rawUnifiedShoppingRows[1].isMainRow,
        'the deferred refresh publishes the current nonempty basket')
    timedClick(stepper.minusBtn,'LeftButton')
    drain()
    check(maxClick<=4.001*ciScale,'synchronous Shift and stepper clicks stay within four milliseconds: '..maxClick)
    check(maxCallback<=4.001,'Shift and stepper callbacks stay under four milliseconds: '..maxCallback)
    print(string.format('WP6 MEASURE row_click_max_ms=%.3f shift_and_stepper_max_ms=%.3f',rowClickMax,maxClick))
    provider.SetShiftMode(false)
    IsShiftKeyDown=oldShiftStress

    local repairRows=box._dp:GetCollection()
    local repairTargets,repairTargetCount={},0
    for _,row in ipairs(repairRows) do
        if row.outputItemID and row.vendorSell~=nil and not repairTargets[row.outputItemID] then
            repairTargets[row.outputItemID]=row
            repairTargetCount=repairTargetCount+1
            if repairTargetCount>=25 then break end
        end
    end
    local oldGetVendorSell=ns.GetVendorSellPrice
    local oldRepairSlice=ns.RecipeStats.RepairSlice
    local changedPrices={}
    local repairElapsed=0
    ns.GetVendorSellPrice=function(id)
        if changedPrices[id] then return changedPrices[id] end
        return oldGetVendorSell and oldGetVendorSell(id)
    end
    ns.RecipeStats.RepairSlice=function(...)
        local before=os.clock()
        local done,repaired,needFull=oldRepairSlice(...)
        repairElapsed=math.max(repairElapsed,(os.clock()-before)*1000)
        return done,repaired,needFull
    end
    local repairIds={}
    for id in pairs(repairTargets) do repairIds[#repairIds+1]=id end
    table.sort(repairIds)
    local startsBeforeRepair=starts
    check(repairTargetCount>=25,'stress catalog has 25 distinct repair targets')
    local id=repairIds[1]
    local sourceRow=repairTargets[id]
    collectgarbage('collect')
    for i=1,25 do
        changedPrices[id]=(sourceRow.vendorSell or 0)+i+1
        ns.pendingItemLoads[id]=true
        hostEnv.eventFrame._scripts.OnEvent(hostEnv.eventFrame,'GET_ITEM_INFO_RECEIVED',id,true)
        drain()
        local repairedRow
        for _,current in ipairs(box._dp:GetCollection()) do
            if current.outputItemID==id then repairedRow=current; break end
        end
        check(repairedRow and repairedRow.vendorSell==changedPrices[id],
            'streamed item repair updates the matching result row '..i)
        check(starts==startsBeforeRepair,'streamed item repair avoids a full catalog rebuild '..i)
        check(repairElapsed<=4.001*ciScale,'in-place repair evaluation stays under four milliseconds '..i..': '..repairElapsed)
        check(maxCallback<=4.001,'item repair callback stays under four milliseconds after batch '..i..': '..maxCallback)
    end
    ns.GetVendorSellPrice=oldGetVendorSell
    ns.RecipeStats.RepairSlice=oldRepairSlice

    local threadID=14341
    local threadPrice=ns.VENDOR_REAGENTS[threadID]
    local threadRows={}
    local threadCount=0
    for _,row in ipairs(box._dp:GetCollection()) do
        for _,reagent in ipairs(row.recipe.reagents or {}) do
            if reagent[1]==threadID then
                threadRows[row.key]=row
                threadCount=threadCount+1
                break
            end
        end
    end
    check(threadCount>=268,'common reagent fixture covers at least 268 recipes')
    ns.VENDOR_REAGENTS[threadID]=12000
    offset=math.floor(#repairRows/2)
    render()
    ns.pendingItemLoads[threadID]=true
    hostEnv.eventFrame._scripts.OnEvent(hostEnv.eventFrame,'GET_ITEM_INFO_RECEIVED',threadID,true)
    drain()
    local refreshed=0
    for _,row in ipairs(box._dp:GetCollection()) do
        if threadRows[row.key] and threadRows[row.key]~=row then refreshed=refreshed+1 end
    end
    check(refreshed==threadCount and starts==startsBeforeRepair,'mid-scroll repair updates every Rune Thread consumer in place')
    check(maxCallback<=4.001,'common reagent repair callback stays under four milliseconds: '..maxCallback)
    ns.VENDOR_REAGENTS[threadID]=threadPrice
    app.sortState.recipes.col='profit'; app.sortState.recipes.asc=false
    provider.Refresh(context); drain()
    context.search='zzzz-stress-no-match'; provider.Refresh(context); drain()
    check(#box._dp:GetCollection()==0,'search remains responsive after item repair batches')
    context.search=''; provider.Refresh(context); drain()
    check(#box._dp:GetCollection()==TOTAL_RECIPES,'all rows return after clearing stress search')
    skillView.profPills[2]:Click('LeftButton'); drain()
    check(context.profFilter=='alchemy' or (context.db and context.db.profFilter=='alchemy'),
        'profession pill remains responsive after item repair')
    skillView.profPills[2]:Click('LeftButton'); drain()
    local othersPill = skillView.profPills[#skillView.profPills]
    check(othersPill and othersPill.key == 'others', 'All Recipes header bar includes Others filter pill')
    othersPill:Click('LeftButton'); drain()
    check(#box._dp:GetCollection()==15, 'Others pill filters All Recipes to all 15 Darkmoon Deck and item-combine/tool exceptions')
    othersPill:Click('LeftButton'); drain()
    check(#box._dp:GetCollection()==TOTAL_RECIPES, 'Clicking Others pill again restores all recipes')
    check(provider.SetColumnVisible('wowheadURL',false),'column controls remain responsive after repairs')
    check(provider.ResetColumns(),'column reset remains responsive after repairs')
    context.profFilter='all'
    context.db.profFilter='all'
    provider.Refresh(context); drain()

    local oldGetStress=ns.RecipeStats.Get
    local previousRows=box._dp:GetCollection()
    previousRows[1].known=true
    ns.RecipeStats.Get=function(...)
        local row=oldGetStress(...)
        row.known=false
        return row
    end
    context.revision=(context.revision or 1)+1
    provider.Refresh(context)
    table.remove(queued,1)() -- Kick off the replacement build before asking to filter the previous rows.
    context.knownRecipesOnly=true
    provider.Refresh(context)
    local stalePresentation=table.remove(queued)
    drain()
    check(#box._dp:GetCollection()==0,'completed replacement has no known recipes')
    stalePresentation()
    drain()
    check(#box._dp:GetCollection()==0,'late presentation of previous rows cannot overwrite the empty replacement')
    ns.RecipeStats.Get=oldGetStress
    context.knownRecipesOnly=false
    provider.Refresh(context); drain()

    local beforeFault=pool[1].data
    local newRows={}
    local failedOnce=false
    ns.RecipeStats.Get=function(...)
        if not failedOnce then failedOnce=true; error('one-shot stress evaluation failure') end
        local row=oldGetStress(...)
        gets=gets+1
        newRows[row]=true
        return row
    end
    context.revision=(context.revision or 1)+1000
    provider.Refresh(context)
    local injectedFailureSeen=false
    local function drainWithRecovery()
        local count=0
        while #queued>0 do
            local fn=table.remove(queued,1)
            local before=os.clock()
            local ok,err=pcall(fn)
            local elapsed=(os.clock()-before)*1000
            if elapsed>maxCallback then maxCallback=elapsed end
            if not ok then
                local message=tostring(err)
                check(not injectedFailureSeen and message:find('one-shot stress evaluation failure',1,true)~=nil,
                    'only the injected one-shot callback failure is swallowed')
                injectedFailureSeen=true
            end
            count=count+1
            assert(count<10000,'fault recovery leaves no runaway callbacks')
        end
    end
    drainWithRecovery()
    local function getRefreshUpvalue(name)
        local i=1
        while true do
            local key,value=debug.getupvalue(provider.Refresh,i)
            if not key then break end
            if key==name then return value end
            i=i+1
        end
    end
    local recoveredBuild=getRefreshUpvalue('buildState')
    check(failedOnce and injectedFailureSeen and recoveredBuild and recoveredBuild.running==false,
        'one-shot evaluation failure clears the running build state')
    check(getRefreshUpvalue('cancelBuild')==nil,'one-shot evaluation failure clears its cancellation handle')
    check(getRefreshUpvalue('pending')==false,'one-shot evaluation failure clears pending state')
    local getsBeforeRetry=gets
    provider.Refresh(context); drainWithRecovery()
    local afterFault=pool[1].data
    check(gets==getsBeforeRetry+TOTAL_RECIPES and getRefreshUpvalue('buildState').completed
        and #box._dp:GetCollection()==TOTAL_RECIPES,'retry evaluates and completes the new catalog')
    check(afterFault~=beforeFault and newRows[afterFault],'visible slot binds a row evaluated by the retry')
    ns.RecipeStats.Get=oldGetStress
    pool[1]:Click('RightButton')
    provider.Refresh(context); drainWithRecovery()
    check(maxCallback<=4.001,'stress callbacks stay under four milliseconds: '..maxCallback)
    check(not registeredWidgets or #registeredWidgets<=registeredAtStart+capacity+4,
        'theme widget registrations stay bounded by the visible row pool')
    ns.SuperListModel.Start=stressOldStart
    debugprofilestop=stressOldProfile
    C_Timer.After=oldAfter
end

local function checkQuickLookWindow(hud, window)
    local hourly = window == '24h'
    check(hud.window == window and hud.data.window == window and hud.slotCount == (hourly and 24 or 7)
        and hud.heading:GetText() == hud.kind:upper()..' QUICK LOOK | '..(hourly and '24 HOURS' or '7 DAYS'),
        hud.kind..' shows the '..window..' history window in its heading')
    check(hud.win24Btn:IsShown() and hud.win24Btn.fs:GetText() == '24h' and hud.win24Btn._mmPlate.active == hourly
        and hud.win7dBtn:IsShown() and hud.win7dBtn.fs:GetText() == '7d' and hud.win7dBtn._mmPlate.active == not hourly
        and hud.win24Btn:GetParent() == hud.win7dBtn:GetParent(), 'the header pills show the selected history window')
    local offsets, widths = {10,202,254,364,430,522,572}, {188,48,104,62,88,48,36}
    local trend, impact, coverage = window:upper()..' TREND', window:upper()..' IMPACT', hourly and 'HRS' or 'DAYS'
    for _, section in ipairs({{hud.overviewHeaders, 'OVERVIEW', 'VALUE'}, {hud.moverHeaders, 'REAGENT', 'PRICE'},
            {hud.scrollHeaders, 'RECIPE SCROLL', 'PRICE'}}) do
        local headers, title = section[1], section[2]
        local labels = {title, 'QTY', section[3], trend, impact, '%', coverage}
        check(#headers == 7, title..' has seven columns')
        for i, label in ipairs(labels) do
            local header = headers[i]
            local alignment = i == 1 and 'LEFT' or (i == 4 and 'CENTER' or 'RIGHT')
            check(header:GetText() == label and header._points[1][4] == offsets[i] and header._points[1][5] == -4
                and header:GetWidth() == widths[i] and header:GetHeight() == 15 and header.justifyH == alignment
                and select(2, header:GetFont()) == 10, title..' column header '..label)
        end
        check(headers[4]:GetStringWidth() <= headers[4]:GetWidth() and headers[4].wordWrap == false,
            title..' fits '..trend..' on one line')
    end
end

local function checkMetricColumns(widgets, label)
    local columns = {{widgets.name,24,164}, {widgets.qty,192,48}, {widgets.price,244,104},
        {widgets.spark,354,62}, {widgets.impact,420,88}, {widgets.pct,512,48}, {widgets.coverage,562,36}}
    check(widgets:GetWidth() == 598 and widgets.name.wordWrap == false and widgets.name.nonSpaceWrap == false
        and widgets.name.maxLines == 1, label..' keeps its name on one line')
    check(widgets.rule._points[1][4] == 24 and widgets.rule:GetWidth() == widgets:GetWidth() - 24
        and widgets.rule:GetHeight() == 1, label..' insets the separator to the name column')
    for i, column in ipairs(columns) do
        local widget = column[1]
        check(widget._points[1][4] == column[2] and widget:GetWidth() == column[3], label..' column '..i)
        if i ~= 1 and i ~= 4 then check(widget.justifyH == 'RIGHT', label..' right aligns column '..i) end
    end
end

local function checkOverview(hud, labels)
    check(#hud.overviewRows == #labels, hud.kind..' displays six overview rows')
    for i, label in ipairs(labels) do
        local widgets = hud.overviewRows[i]
        check(widgets:IsShown() and widgets.name:GetText() == label and widgets:GetHeight() == 24
            and widgets._points[1][5] == -(22+(i-1)*24), hud.kind..' overview row '..i..' is '..label)
        checkMetricColumns(widgets, label)
    end
end

local function checkBelow(hud, lower, upper, label)
    local point, upperPoint = lower._points[1], upper._points[1]
    check(point[1] == 'TOPLEFT' and point[2] == hud and point[3] == 'TOPLEFT'
        and point[4] == upperPoint[4] and point[5] == upperPoint[5] - upper:GetHeight() - 6, label)
end

local function sameColor(actual, expected)
    return actual and actual[1] == expected[1] and actual[2] == expected[2] and actual[3] == expected[3]
        and actual[4] == expected[4]
end

local function quickLookInk(hud, role)
    return (hud.inks and hud.inks[role]) or hud.palette[role]
end

local function checkTraceGap(trace, values, first, last, label)
    check(values[first] ~= nil and values[last] ~= nil and trace.dots[first]:IsShown() and trace.dots[last]:IsShown(),
        label..' draws both observed dots')
    for slot = first+1, last-1 do
        check(values[slot] == nil and not trace.dots[slot]:IsShown() and not trace.lines[slot]:IsShown(),
            label..' leaves slot '..slot..' unobserved')
    end
    local line = trace.lines[last]
    local from, to = trace.dots[first]._points[1], trace.dots[last]._points[1]
    check(line:IsShown() and line._startPoint[1] == 'BOTTOMLEFT' and line._endPoint[1] == 'BOTTOMLEFT'
        and line._startPoint[2] == from[4] and line._startPoint[3] == from[5]
        and line._endPoint[2] == to[4] and line._endPoint[3] == to[5],
        label..' draws a straight segment between the observed dots across the gap')
end

local function checkUnavailableScroll(hud, source)
    local data, listings = hud.data, hud.scrollListedRow
    check(not data.canTradeScroll and not data.scrollInfo.canTrade
        and data.scrollLiveListed == nil and data.scrollInfo.liveListed == nil
        and (not data.scrollListed or data.scrollListed.count == 0), source..' has no AH quantity or listing history')
    check(hud.scrollRow.fixed:IsShown() and hud.scrollRow.fixed:GetText() == source
        and listings:IsShown() and listings.fixed:IsShown() and listings.fixed:GetText() == source
        and listings.coverage:GetText() == 'N/A' and not listings.spark:IsShown(),
        source..' displays its source tag and N/A listing coverage')
end

local function checkQuickLookWowhead(hud, url)
    local modal = app.ui.wowheadModal
    modal:Hide()
    check(hud.wowheadButton:IsShown() and type(url) == 'string', hud.kind..' has a Wowhead source link')
    local mouseDown = hud:GetScript('OnEvent')
    hud.mouseOver = true
    mouseDown(hud, 'GLOBAL_MOUSE_DOWN', 'LeftButton')
    hud.wowheadButton:Click('LeftButton')
    hud.mouseOver = false
    check(hud:IsShown() and modal:IsShown() and modal.currentURL == url and modal.urlBox:GetText() == url,
        hud.kind..' opens the Wowhead copy modal with its source URL')
    for _, target in ipairs({modal, modal.urlBox}) do
        target.mouseOver = true
        mouseDown(hud, 'GLOBAL_MOUSE_DOWN', 'LeftButton')
        target.mouseOver = false
        check(hud:IsShown() and modal:IsShown(), hud.kind..' keeps Quick Look open while using the Wowhead modal')
    end
    modal:Hide()
end

local function checkRecipeQuickLook()
    local initialQuickLook=provider.GetQuickLookFrame()
    check(initialQuickLook and initialQuickLook:IsShown() and initialQuickLook.pinned,
        'the initial normal row click opens a pinned Quick Look')
    provider.CloseQuickLook()
    check(not initialQuickLook:IsShown(),'CloseQuickLook closes the HUD')
    check(provider.OpenQuickLook('missing recipe',true)==nil,'unknown Quick Look keys return nil')
    local econ,day=ns.CurrentEconomyInfo().effectiveKey,math.floor(time()/86400)
    local oldDaily,oldHistory=MerchantMasterDB.ahDaily,MerchantMasterDB.ahHistory
    local oldSnapshots,oldWindow,oldMode=MerchantMasterDB.ahSnapshots,MerchantMasterDB.quickLookWindow,MerchantMasterDB.priceDisplayMode
    local livePrices=MerchantMasterDB.ahPrices[econ]
    local oldScrollQuote=livePrices[13521]
    local daily,snapshots={},{}
    MerchantMasterDB.ahDaily={[econ]=daily}
    MerchantMasterDB.ahHistory={}
    MerchantMasterDB.ahSnapshots={[econ]=snapshots}
    MerchantMasterDB.quickLookWindow='7d'
    MerchantMasterDB.priceDisplayMode='compact'
    local function seed(id,values,quantities)
        local buckets={}
        for i=1,7 do
            if values[i] then
                local point={d=day-7+i,lastP=values[i],lastQ=quantities and quantities[i] or 21-i,at=time()-(7-i)*86400-240}
                if id==13512 and i~=2 then
                    point.scanSeconds,point.scanPairs,point.scanUnits=7200,2,(10+i)/4
                end
                buckets[#buckets+1]=point
            end
        end
        daily[id]=buckets
    end
    seed(13512,{600000,610000,606000,636000,644000,670000,685000})
    seed(13468,{320000,323500,321800,346000,356000,372000,382000})
    seed(13463,{4800,4590,4690,4500,4470,4320,4200})
    seed(13465,{7300,nil,7480,nil,nil,7610,7800})
    seed(13521,{1480000,1450000,1410000,1415000,1340000,1290000,1220000},{8,7,6,5,4,3,2})
    livePrices[13521]={price=1220000,qty=2,at=time()-60,itemWide=true}

    local recipe,recipeKey
    for _,entry in ipairs(ns.RecipeStats.GetCatalog()) do
        if entry.recipe.outputItemID==13512 then recipe,recipeKey=entry.recipe,entry.key; break end
    end
    local options={economy=econ,applyAHCut=true,charKey=app.charKey}
    local realRow=ns.RecipeStats.Get(recipe,options)
    local row={}; for k,v in pairs(realRow) do row[k]=v end
    row.profit,row.listed,row.salesPerDay,row.demand=64250,14,7,nil
    local vendor=ns.GetRecipeVendorBuyPrice(8925,ns.VENDOR_REAGENTS[8925])
    check(vendor and vendor>0,'Crystal Vial has a real vendor price')
    local priorVialMarket = ns.GetItemMarketPrice
    ns.GetItemMarketPrice = function(id, ...)
        if id == 8925 then return vendor + 1, 'AH' end
        return priorVialMarket(id, ...)
    end
    local data=ns.RecipeStats.BuildQuickLook(row,options,time())
    local movers=data.movers
    check(data.startDay==day-6 and data.output.days==7 and data.output.values[7]==685000
        and math.abs(data.output.pct-14.1666667)<0.0001,'output uses the seven daily slots and computes the sell delta')
    check(data.cost.days==4 and data.cost.values[1]==537000+vendor and data.cost.values[7]==586000+vendor
        and data.cost.values[2]==nil and data.cost.values[4]==nil and data.cost.values[5]==nil,
        'craft cost is per craft and only exists when all required prices are recorded')
    check(data.net.values[7]==64750-vendor and data.net.change==31750 and data.net.values[2]==nil,
        'net profit deducts the configured AH cut and inherits cost gaps')
    check(ns.RecipeStats.BuildQuickLook(row,{economy=econ,applyAHCut=false},time()).net.values[7]==99000-vendor,
        'net profit honors a disabled auction cut')
    check(data.sales.days==6 and data.sales.values[2]==nil and data.sales.values[7]==17
        and data.salesSource=='Local scan estimate','sales use recorded scan velocity and preserve missing days')
    check(data.scroll.days==7 and data.scroll.first==1480000 and data.scrollCost==1220000
        and data.breakEvenCrafts==19,'scroll history and positive per-output profit drive break-even')
    check(data.canTradeScroll and data.scrollLiveListed==2 and data.scrollListed.count==7
        and data.scrollListed.first==8 and data.scrollListed.last==2 and data.scrollListed.change==-6
        and data.scrollListed.pct==-75,'tradeable scroll exposes its live count and weekly listing history')
    check(data.scrollInfo.canTrade and data.scrollInfo.listed==data.scrollListed and data.scrollInfo.liveListed==2,
        'scroll source info carries the same market listing metrics')
    local multiOutputRow={}
    for key,value in pairs(row) do multiOutputRow[key]=value end
    multiOutputRow.numMade,multiOutputRow.profit=3,100
    local multiScrollID=multiOutputRow.recipe.recipeItemID
    local originalMultiScroll=daily[multiScrollID]
    local originalMultiQuote=livePrices[multiScrollID]
    livePrices[multiScrollID]=nil
    seed(multiScrollID,{1130,1140,1150,1160,1170,1180,1200})
    local multiOutputLook=ns.RecipeStats.BuildQuickLook(multiOutputRow,options,time())
    check(multiOutputLook.scrollCost==1200 and multiOutputLook.breakEvenCrafts==4,
        'Break-even craft count divides scroll cost across all output units')
    daily[multiScrollID]=originalMultiScroll
    livePrices[multiScrollID]=originalMultiQuote
    row.profit=0
    check(ns.RecipeStats.BuildQuickLook(row,options).breakEvenCrafts==nil,'nonpositive current profit has no break-even')
    row.profit=64250
    check(movers[1].itemID==13468 and movers[1].impact==62000 and movers[2].itemID==13463
        and movers[2].impact==-18000 and movers[3].impact==5000,'movers rank by absolute price impact times reagent quantity')
    check(data.bottleneck==movers[3] and movers[3].series.days==4 and movers[3].series.values[2]==nil
        and movers[4].fixed and movers[4].impact==0 and movers[4].series.values[2]==vendor,'partial and vendor fixed prices remain distinct')

    local dailyOutput=daily[13512]
    local lastScan=day*86400-86400+43200
    MerchantMasterDB.ahHistory[econ]={[13512]={
        {t=lastScan-1800,p=650000,q=20}, {t=lastScan-900,p=660000,q=19}, {t=lastScan,p=670000,q=17},
    }}
    daily[13512]=nil
    local legacy=ns.RecipeStats.BuildQuickLook(row,options,time())
    check(legacy.output.values[6]==670000 and legacy.output.pct==nil and legacy.output.values[7]==nil
        and legacy.sales.values[6]==12 and legacy.sales.days==1,'legacy scan history gives observed prices and daily velocity only')
    MerchantMasterDB.ahHistory[econ]=nil
    local store=ns.Analytics.Store
    local oldIter=store.IterDays
    store.IterDays=function(_,_,visit)
        visit(nil,{
            {type='AH_SELL',itemID=13512,econ=econ,char=app.charKey,time=lastScan,qty=3},
            {type='AH_SELL',itemID=13512,econ=econ,char=app.charKey,time=time(),qty=9,extra={saleAt=lastScan}},
            {type='AH_SELL',itemID=13512,econ=econ,char='Other character',time=time(),qty=11},
        })
    end
    local personal=ns.RecipeStats.BuildQuickLook(row,options,time())
    store.IterDays=oldIter
    check(personal.salesSource=='Personal sales' and personal.sales.values[6]==12 and personal.sales.values[7]==nil,
        'personal history uses actual sale time and the selected character without filling empty days')
    daily[13512]=dailyOutput

    local oldAlt,oldShift=_G.IsAltKeyDown,_G.IsShiftKeyDown
    local oldModified,oldChatInsert=_G.IsModifiedClick,_G.ChatEdit_InsertLink
    local oldItemInfo=C_Item.GetItemInfo
    local oldAH,ahCalls=app.searchAH,0
    local oldWowhead,wowheadCalls=app.openWowheadPopup,0
    local searchRow=row
    app.searchAH=function(name,qty,id)
        check(name==searchRow.name and qty==1 and id==searchRow.outputItemID,
            'AH uses the selected recipe output')
        ahCalls=ahCalls+1
    end
    app.openWowheadPopup=function() wowheadCalls=wowheadCalls+1 end
    app.clearCraftingOrderQueue()
    box._view._initFn(pool[1],row)
    local nameCell=pool[1].cellGroup.cellsByKey.name
    _G.IsAltKeyDown=function() return false end
    _G.IsShiftKeyDown=function() return true end
    _G.IsModifiedClick=function(key) return key=='CHATLINK' end
    C_Item.GetItemInfo=function(id) return 'Test item','|Hitem:'..tostring(id)..'|h[Test item]|h' end
    _G.ChatEdit_InsertLink=function() return 'chat-result' end
    nameCell:Click('LeftButton')
    check(not provider.GetQuickLookFrame():IsShown() and app.getRecipeShoppingQty(row)==1,
        'truthy non-boolean chat result falls through to Shift quick-add')
    local beforeAcceptedLink=app.getRecipeShoppingQty(row)
    _G.ChatEdit_InsertLink=function(link)
        check(link:find('item:13512',1,true)~=nil,'C_Item.GetItemInfo supplies the chat item link')
        return true
    end
    nameCell:Click('LeftButton')
    check(app.getRecipeShoppingQty(row)==beforeAcceptedLink and not provider.GetQuickLookFrame():IsShown(),
        'accepted Shift chat link inserts without queueing a craft')
    nameCell:Click('RightButton')
    check(not provider.GetQuickLookFrame():IsShown() and app.getRecipeShoppingQty(row)==0,
        'Shift-right-click removes one craft and leaves Quick Look closed (qty='..tostring(app.getRecipeShoppingQty(row))..')')
    app.clearCraftingOrderQueue()
    do
        local searchBox=app.ui.searchBox
        local oldHasFocus,oldSearchText=searchBox.HasFocus,searchBox:GetText()
        _G.IsModifiedClick=function() return false end
        searchBox.HasFocus=function() return true end
        check(app.tryQuickLookChatLink(row.outputItemID)==true and searchBox:GetText()=='Test item',
            'focused search box accepts a C_Item link when chat-link modifier is inactive')
        searchBox.HasFocus=oldHasFocus
        searchBox:SetText(oldSearchText)
    end
    box._view._initFn(pool[1],row)
    _G.IsShiftKeyDown=function() return false end
    provider.SetShiftMode(false)
    _G.IsModifiedClick,_G.ChatEdit_InsertLink=oldModified,oldChatInsert
    C_Item.GetItemInfo=oldItemInfo
    nameCell:Click('RightButton')
    check(not provider.GetQuickLookFrame():IsShown() and ahCalls==0
        and app.selectedRecipeItemID==13512,'right-click selects without Quick Look or AH search')
    local whCell=pool[1].cellGroup.cellsByKey.wowheadURL
    whCell:Click('LeftButton')
    check(wowheadCalls==1 and not provider.GetQuickLookFrame():IsShown() and ahCalls==0,
        'Wowhead left-click opens its popup without Quick Look or AH search')
    whCell:Click('RightButton')
    check(wowheadCalls==1 and not provider.GetQuickLookFrame():IsShown() and ahCalls==0
        and app.selectedRecipeItemID==13512,
        'Wowhead right-click follows recipe selection without opening the popup or Quick Look')
    nameCell:Click('LeftButton')
    local frame=provider.GetQuickLookFrame()
    check(frame and frame.pinned and frame:IsShown() and frame.keyboard and frame._events.GLOBAL_MOUSE_DOWN
        and frame.row==row and frame:GetWidth()==654 and frame.chart==nil and not frame.expandChart:IsShown() and ahCalls==1,
        'plain left-click opens the 654 px Quick Look with its inline chart collapsed and searches AH')
    GameTooltip:Hide()
    nameCell:GetScript('OnEnter')(nameCell)
    check(GameTooltip:IsShown() and #GameTooltip._lines>0,
        'hovering the selected recipe name still shows its tooltip while Quick Look is open')
    nameCell:GetScript('OnLeave')(nameCell)
    pool[1].mouseOver=true
    frame:GetScript('OnEvent')(frame,'GLOBAL_MOUSE_DOWN','LeftButton')
    pool[1].mouseOver=false
    check(frame:IsShown(),'mouse-down over the selected recipe leaves the toggle to its name cell')
    nameCell:Click('LeftButton')
    check(not frame:IsShown() and ahCalls==1,'clicking the same name cell closes Quick Look without a second AH search')
    nameCell:Click('LeftButton')
    check(frame:IsShown() and frame.row==row and ahCalls==2,'the same name cell reopens Quick Look')
    local secondRow
    for _,candidate in ipairs(all) do
        if candidate.outputItemID and candidate.outputItemID~=row.outputItemID and candidate.recipe then
            secondRow=candidate
            break
        end
    end
    check(secondRow~=nil,'catalog has another recipe for click switching')
    box._view._initFn(pool[2],secondRow)
    pool[2].mouseOver=true
    frame:GetScript('OnEvent')(frame,'GLOBAL_MOUSE_DOWN','LeftButton')
    check(frame:IsShown(),'clicking another visible recipe does not dismiss Quick Look on mouse-down')
    searchRow=secondRow
    pool[2].cellGroup.cellsByKey.name:Click('LeftButton')
    check(frame:IsShown() and frame.row==secondRow and frame.pinned and ahCalls==3,
        'plain left-click on another recipe switches the pinned Quick Look and searches AH')
    pool[2].mouseOver=false
    searchRow=row
    provider.OpenQuickLook(row,true)
    check(pool[1].cellGroup.cellsByKey.cdSort.fs:GetText()=='-','opening Quick Look preserves the non-cooldown hyphen')
    checkQuickLookWindow(frame, '7d')
    checkOverview(frame, {'Profit', 'Sell price', 'Craft cost', 'Sales per day', 'AH listed', 'Demand'})
    local overview, chart = frame.overviewRows, frame.expandChart
    local weeklyPercent = {string.format('%+.1f%%',31750/(33000-vendor)*100), '+14.2%',
        string.format('%+.1f%%',49000/(537000+vendor)*100), '+54.5%', '-30.0%', '+120.8%'}
    for i, expected in ipairs(weeklyPercent) do
        check(overview[i].pct:GetText()==expected, overview[i].name:GetText()..' shows its weekly percentage change')
    end
    checkTraceGap(overview[3].trace,frame.data.cost.values,1,3,'weekly Craft cost sparkline')
    check(overview[4].price:GetText()=='7.0/d' and overview[5].price:GetText()=='14'
        and overview[6].qty:GetText()=='Hot/Cold' and plain(overview[6].price:GetText())=='Hot'
        and frame.data.overviewRows[6].liveValue==7/14, 'Demand shows Hot at seven daily sales for fourteen listings')
    check(overview[6].qty:GetWidth()==48 and overview[6].qty:GetStringWidth()<=overview[6].qty:GetWidth()
        and overview[6].qty.wordWrap==false, 'the full Hot/Cold label fits the Quantity cell on one line')
    row.salesPerDay=0.5
    provider.RefreshQuickLook()
    check(overview[4].price:GetText()=='0.5/d' and overview[5].price:GetText()=='14'
        and plain(overview[6].price:GetText())=='Cold' and frame.data.overviewRows[6].liveValue==0.5/14,
        'Demand repaints as Cold when sales drop against the same listing count')
    row.salesPerDay=7
    provider.RefreshQuickLook()

    local vial=frame.movers[4]
    check(#frame.movers==4 and frame.movers[3].coverage:GetText()=='4/7d' and vial.name:GetText()=='Crystal Vial'
        and vial.fixed:IsShown() and vial.fixed:GetText()=='VENDOR' and not vial.spark:IsShown()
        and vial.pct:GetText()=='0.0%' and vial.coverage:GetText()=='N/A' and frame.data.movers[4].pureVendor,
        'Crystal Vial displays VENDOR, zero percent, and N/A coverage')
    check(frame.craftButton==nil and frame.more==nil,'Quick Look has no full crafting action or hidden-reagent summary')
    check(frame.overviewPanel._points[1][4]==15 and frame.overviewPanel:GetWidth()==624 and frame.overviewPanel:GetHeight()==172,
        'the overview card is inset evenly inside the HUD')
    checkBelow(frame,frame.moverPanel,frame.overviewPanel,'the reagent panel follows the overview')
    check(frame.moverPanel:GetWidth()==624 and frame.moverPanel:GetHeight()==132 and not frame.moverScrollTrack:IsShown(),
        'four reagents fit the fixed panel with the scrollbar hidden')
    for i,mover in ipairs(frame.movers) do
        check(mover:IsShown() and mover._points[1][4]==10 and mover._points[1][5]==-(22+(i-1)*26)
            and mover:GetHeight()==26 and mover.qty:GetText()==frame.data.movers[i].qty..'x'
            and mover.qty.wordWrap==false and mover.price.wordWrap==false and mover.mouseWheel, 'visible reagent slot '..i)
        checkMetricColumns(mover, mover.name:GetText())
    end
    check(frame.movers[1].pct:GetText()=='+19.4%' and frame.movers[2].pct:GetText()=='-12.5%',
        'market reagents have percentage changes in their own column')

    local scroll, listings=frame.scrollRow, frame.scrollListedRow
    checkMetricColumns(scroll, 'Recipe scroll')
    checkMetricColumns(listings, 'Scroll AH listed')
    checkBelow(frame,frame.scrollPanel,frame.moverPanel,'the scroll panel follows the reagent panel')
    check(frame.scrollPanel:GetWidth()==624 and frame.scrollPanel:GetHeight()==96 and scroll._points[1][5]==-22
        and listings._points[1][5]==-46, 'the recipe scroll panel reserves two metric rows')
    check(scroll:IsShown() and scroll.name:GetText()=='Recipe scroll' and scroll.qty:GetText()=='1x'
        and plain(scroll.price:GetText())=='122g' and scroll.pct:GetText()=='-17.6%' and scroll.coverage:GetText()=='7/7d'
        and frame.scrollHeaders[1]:IsShown(), 'the recipe scroll has its own seven-column metric row')
    check(listings:IsShown() and listings.name:GetText()=='Scroll AH listed' and listings.qty:GetText()=='AH'
        and listings.price:GetText()=='2' and listings.impact:GetText()=='-6' and listings.pct:GetText()=='-75.0%'
        and listings.coverage:GetText()=='7/7d' and sameColor(listings.impact._lastColor,quickLookInk(frame,'accentRed'))
        and sameColor(listings.pct._lastColor,quickLookInk(frame,'accentRed')), 'the weekly scroll listing row paints the live count and red decline')
    check(listings.spark:IsShown() and listings.trace.dots[1]:IsShown() and listings.trace.dots[7]:IsShown()
        and listings.trace.lines[7]:IsShown(), 'the weekly listing sparkline connects its observed counts')
    check(frame.whereToBuy:GetText()=='Where to buy: '..row.craftAbility.howDetail
        and frame.breakEven:IsShown() and frame.breakEven:GetText()=='Break-even: 19 crafts',
        'the recipe scroll shows its acquisition source and break-even crafts')
    local wowheadPoint=frame.wowheadButton._points[1]
    check(frame.whereToBuy._points[1][5]==-72 and frame.breakEven._points[1][5]==-84
        and wowheadPoint[4]==512 and wowheadPoint[5]==-71 and frame.wowheadButton:GetWidth()==100
        and frame.wowheadButton:GetHeight()==22, 'source, break-even and Wowhead fit below both recipe scroll rows')
    app.openWowheadPopup=oldWowhead
    checkQuickLookWowhead(frame, 'https://www.wowhead.com/forever/item=13521')

    do
        local vendorRow, favorRow = {}, {}
        for k,v in pairs(row) do vendorRow[k],favorRow[k]=v,v end
        vendorRow.key,vendorRow.sourceLabel='quick-look-vendor-scroll','Vendor'
        vendorRow.craftAbility={howCategory='vendor',vendorCopperCost=250000,howDetail='Test vendor'}
        provider.OpenQuickLook(vendorRow,true)
        local look=frame.data
        check(look.scrollFixed and look.scrollCost==250000 and look.scroll.first==250000 and look.scroll.last==250000,
            'a copper vendor fixes the scroll price even when AH prices exist')
        check(look.canTradeScroll and look.scrollLiveListed==2 and look.scrollListed.count==7 and look.scrollListed.change==-6
            and look.scrollInfo.canTrade and look.scrollInfo.liveListed==2 and look.scrollInfo.listed==look.scrollListed,
            'a copper vendor leaves the same scroll tradeable with independently tracked AH quantities')
        check(scroll.fixed:IsShown() and scroll.fixed:GetText()=='VENDOR' and plain(scroll.price:GetText())=='25g'
            and listings.price:GetText()=='2' and listings.coverage:GetText()=='7/7d',
            'vendor scroll price and observed AH listings appear together on separate rows')
        local scrollQuote=livePrices[13521]
        livePrices[13521]={qty=0,at=time()-300,itemWide=true,absent=true}
        provider.RefreshQuickLook()
        check(frame.data.scrollLiveListed==0 and frame.data.scrollInfo.liveListed==0 and frame.data.scrollListed.last==2
            and listings.price:GetText()=='0' and listings.impact:GetText()=='-6',
            'zero live listings stay distinct from a nonzero trend endpoint')
        livePrices[13521]=scrollQuote

        favorRow.key,favorRow.sourceLabel='quick-look-favor-scroll','Merchant'
        favorRow.craftAbility={vendorFavorCost=5,vendorCostText='5 Favor'}
        provider.OpenQuickLook(favorRow,true)
        checkUnavailableScroll(frame,'FAVOR')
        provider.OpenQuickLook(row,true)
    end

    do
        local hour=math.floor(time()/3600)*3600
        local function snapshot(id, slot, price, qty, seconds)
            local points=snapshots[id] or {}
            points[#points+1]=hour+(slot-24)*3600+(seconds or 0)
            points[#points+1]=price
            points[#points+1]=qty
            snapshots[id]=points
        end
        snapshot(13512,2,605000,22)
        snapshot(13512,2,610000,20,300)
        snapshot(13512,2,615000,19,900)
        snapshot(13512,7,630000,17)
        snapshot(13512,7,640000,15,900)
        snapshot(13512,18,650000,16,900)
        snapshot(13512,24,670000,15)
        snapshot(13512,24,680000,14,900)
        for id, prices in pairs({[13468]={300000,310000,320000,360000}, [13463]={5000,4800,4600,4300},
                [13465]={7000,7200,7500,7700}}) do
            for i, slot in ipairs({2,7,18,24}) do snapshot(id,slot,prices[i],20-i) end
        end
        local scrollPrices,scrollCounts={1400000,1350000,1290000,1220000},{6,5,4,2}
        for i, slot in ipairs({2,7,18,24}) do snapshot(13521,slot,scrollPrices[i],scrollCounts[i]) end

        frame.win24Btn:Click('LeftButton')
        check(MerchantMasterDB.quickLookWindow=='24h','the 24h pill saves the hourly window')
        checkQuickLookWindow(frame,'24h')
        check(overview[2].coverage:GetText()=='4/24h' and overview[4].coverage:GetText()=='3/24h'
            and frame.movers[1].coverage:GetText()=='4/24h' and scroll.coverage:GetText()=='4/24h',
            'hourly coverage counts observed hours for the overview, reagents, and recipe scroll')
        check(frame.data.output.values[2]==615000 and frame.data.output.values[7]==640000
            and overview[2].pct:GetText()=='+10.6%', 'hourly sell price uses the latest snapshot in each observed hour')
        checkTraceGap(overview[2].trace,frame.data.output.values,2,7,'Sell price sparkline')
        checkTraceGap(overview[4].trace,frame.data.sales.values,2,7,'Sales per day sparkline')
        checkTraceGap(frame.movers[1].trace,frame.data.movers[1].series.values,2,7,'Black Lotus sparkline')

        local closedHeight=frame:GetHeight()
        check(listings.price:GetText()=='2' and listings.impact:GetText()=='-4' and listings.pct:GetText()=='-66.7%'
            and listings.coverage:GetText()=='4/24h', 'the listing row uses observed hours and an exact signed count')
        checkTraceGap(listings.trace,frame.data.scrollListed.values,2,7,'hourly scroll listing sparkline')
        listings:Click('LeftButton')
        check(chart:IsShown() and chart.title:GetText()=='Scroll AH listed — 24h' and listings.active:IsShown()
            and chart.value:GetText()=='2' and chart.impact:GetText()=='-4' and chart.pct:GetText()=='-66.7%'
            and chart.axis[1]:GetText()=='6' and chart.axis[3]:GetText()=='2'
            and frame:GetHeight()==closedHeight+chart:GetHeight()+6, 'the listing row expands its own integer chart')
        checkBelow(frame,chart,frame.scrollPanel,'the listing chart opens directly below the scroll panel')
        checkBelow(frame,frame.footer,chart,'the footer follows the expanded listing chart')
        checkTraceGap(chart.trace,frame.data.scrollListed.values,2,7,'expanded scroll listing chart')
        listings:Click('LeftButton')
        check(not chart:IsShown() and not listings.active:IsShown() and frame:GetHeight()==closedHeight,
            'clicking the listing row again collapses its chart and restores the HUD height')
        checkBelow(frame,frame.footer,frame.scrollPanel,'the footer returns below the scroll panel')

        local firstCount=3 -- AH snapshots are stored as timestamp, price, quantity triples.
        snapshots[13521][firstCount]=1
        provider.RefreshQuickLook()
        check(listings.price:GetText()=='2' and listings.impact:GetText()=='+1' and listings.pct:GetText()=='+100.0%'
            and sameColor(listings.impact._lastColor,quickLookInk(frame,'accentGreen'))
            and sameColor(listings.pct._lastColor,quickLookInk(frame,'accentGreen')), 'a rising listing count is signed and green')
        snapshots[13521][firstCount]=scrollCounts[1]
        provider.RefreshQuickLook()

        overview[4]:Click('LeftButton')
        check(chart:IsShown() and chart.title:GetText()=='Sales per day — 24h' and overview[4].active:IsShown()
            and frame:GetHeight()==closedHeight+chart:GetHeight()+6, 'Sales per day expands the hourly chart')
        checkBelow(frame,chart,frame.overviewPanel,'the chart opens directly below the overview')
        checkBelow(frame,frame.moverPanel,chart,'the reagent panel moves below the expanded overview chart')
        checkTraceGap(chart.trace,frame.data.sales.values,2,7,'expanded Sales per day chart')
        check(chart.hits[24]:IsShown() and chart.ticks[1]:GetText()=='-24h' and chart.ticks[5]:GetText()=='Now'
            and not chart.ticks[6]:IsShown() and chart.axis[1]:GetText()=='16.0/d' and chart.axis[3]:GetText()=='8.0/d',
            'the hourly Sales per day chart shows the hourly ticks and rate axis')
        local hit=chart.hits[7]
        hit:GetScript('OnEnter')(hit)
        local stamp=os.date('!%a %d %b %H:%M UTC',hour-17*3600)
        check(frame.readout:IsShown() and frame.dayReadout:GetText()==stamp..'  |  16.0/d',
            'hover displays the observed UTC hour and sales rate')
        hit:GetScript('OnLeave')(hit)
        check(not frame.readout:IsShown(),'leaving the chart point hides the readout')
        overview[4]:Click('LeftButton')
        check(not chart:IsShown() and not overview[4].active:IsShown() and frame:GetHeight()==closedHeight,
            'clicking Sales per day again collapses the chart and restores the height')
        checkBelow(frame,frame.moverPanel,frame.overviewPanel,'collapsing the chart restores the reagent panel position')

        overview[1]:Click('LeftButton')
        check(chart:IsShown() and chart.title:GetText()=='Profit — 24h','Profit opens its own hourly series')
        checkBelow(frame,chart,frame.overviewPanel,'the Profit chart follows the overview')
        local expandedHeight=frame:GetHeight()
        frame.movers[1]:Click('LeftButton')
        check(chart:IsShown() and chart.title:GetText()=='Black Lotus — 24h' and frame.movers[1].active:IsShown()
            and not overview[1].active:IsShown() and frame:GetHeight()==expandedHeight,
            'selecting the first reagent moves the one expanded chart without stacking a second chart')
        checkBelow(frame,frame.moverPanel,frame.overviewPanel,'the overview reclaims the space under it')
        checkBelow(frame,chart,frame.moverPanel,'the reagent chart opens directly below the reagent panel')
        checkBelow(frame,frame.scrollPanel,chart,'the recipe scroll stays below the reagent chart')
        checkTraceGap(chart.trace,frame.data.movers[1].series.values,2,7,'expanded Black Lotus chart')
        check(plain(chart.axis[1]:GetText())=='36g 00s' and plain(chart.axis[3]:GetText())=='30g 00s',
            'the hourly Black Lotus axis uses hourly prices')

        frame.win7dBtn:Click('LeftButton')
        check(MerchantMasterDB.quickLookWindow=='7d','the 7d pill saves the weekly window')
        checkQuickLookWindow(frame,'7d')
        check(chart:IsShown() and chart.title:GetText()=='Black Lotus — 7d' and frame.movers[1].active:IsShown()
            and frame:GetHeight()==expandedHeight and chart.trace.dots[1]:IsShown() and not chart.trace.dots[24]:IsShown()
            and chart.hits[7]:IsShown() and not chart.hits[8]:IsShown() and chart.ticks[7]:IsShown()
            and chart.ticks[7]:GetText()==os.date('!%a',day*86400)
            and plain(chart.axis[1]:GetText())=='38g 20s' and plain(chart.axis[3]:GetText())=='32g 00s',
            'switching windows preserves the selected reagent chart and replaces the series, axis, and hover slots')
        checkBelow(frame,chart,frame.moverPanel,'the weekly chart keeps its inline placement')
    end
    do
        local theme = ns.Theme
        local cases = {
            compact = {{0, '0c'}, {500, '5s 00c'}, {123456, '12g 34s 56c'}},
            no_copper = {{12349, '1g 23s'}, {12350, '1g 24s'}, {49, '0s'}, {50, '1s'}, {123456, '12g 35s'}, {9950, '1g 00s'}},
            full_fixed = {{0, '00g 00s 00c'}, {500, '00g 05s 00c'}, {50000, '05g 00s 00c'},
                {123456, '12g 34s 56c'}, {-990000, '-99g 00s 00c'}},
        }
        for mode, values in pairs(cases) do
            MerchantMasterDB.priceDisplayMode = mode
            for _, case in ipairs(values) do
                local copper, expected = case[1], case[2]
                check(plain(theme.FormatMoneyText(copper)) == expected and plain(theme.FormatMoneyParts(copper).text) == expected,
                    mode .. ' formats ' .. tostring(copper) .. ' as ' .. expected)
            end
        end
        MerchantMasterDB.priceDisplayMode='no_copper'
        for _, case in ipairs({{-49,'0s'},{49,'0s'},{-50,'-1s'}}) do
            local copper,expected=case[1],case[2]
            check(plain(theme.FormatMoneyText(copper,true))==expected,
                'signed no-copper formatting '..tostring(copper)..' as '..expected)
        end
        check(plain(theme.FormatMoneyText(9950))=='1g 00s',
            'no-copper rounding preserves the 1g boundary')
        check(plain(theme.FormatMoneyFable(123456, false, {priceDisplayMode='full_fixed'})) == '12g 34s 56c'
            and plain(theme.FormatMoneyFable(123456, false, {priceDisplayMode='compact'})) == '12g 34s',
            'Fable formatter honors the override and its compact gold/silver behavior')
        MerchantMasterDB.priceDisplayMode = 'compact'

        local oldOpen, oldInvalidate, oldRefresh = theme.OpenDropDown, provider.Invalidate, app.refresh
        local refreshes, invalidations = 0, 0
        local selection = 'full_fixed'
        theme.OpenDropDown = function(_, modes, current, choose)
            check(modes == ns.PRICE_DISPLAY_MODES and current == theme.GetPriceDisplayMode(),
                'Price Format dropdown offers the shared modes and selected value')
            choose(selection)
        end
        provider.Invalidate = function(reason)
            check(reason == 'prices', 'Changing price mode invalidates Super List prices')
            invalidations = invalidations + 1
        end
        app.refresh = function() refreshes = refreshes + 1 end
        local gear, canvas = app.ui.priceFmtBtn, app.ui.optPriceFmtBtn
        local firstProfession = app.ui.profBtns.all
        check(gear._points[1][3] - gear:GetHeight() > firstProfession._points[1][3]
            and gear:GetParent():GetHeight() == 292 and not firstProfession:IsShown(),
            'Gear Price Format sits in the compact Settings & Tools popover with profession filters moved out')
        local moverPrice = frame.movers[1].price
        gear:Click('LeftButton')
        check(theme.GetPriceDisplayMode() == 'full_fixed' and gear:GetText():find('00g 00s 00c', 1, true),
            'Gear Settings saves Full Fixed and displays its label')
        check(frame:IsShown() and plain(moverPrice:GetText()):match('%d+g %d%ds %d%dc$') and moverPrice.justifyH == 'RIGHT',
            'Changing price mode refreshes the open Quick Look with right-aligned fixed money values')
        local axis = frame.expandChart.axis[1]
        check(frame.expandChart:IsShown() and axis:GetWidth() == 90 and axis.justifyH == 'RIGHT'
            and plain(axis:GetText()) == '38g 20s 00c' and axis:GetStringWidth() <= axis:GetWidth(),
            'The open chart repaints its right-aligned money axis in Full Fixed')
        local chart = ns.Analytics.Chart.CreateBarChart(app.panel, 400, 180)
        local bars = {{day='Today', value=-990000}}
        chart:SetData(bars)
        check(chart.yLabels[1]:GetWidth() == 90 and plain(chart.yLabels[1]:GetText()):find('00s 00c', 1, true),
            'Analytics chart reserves space for fixed money axis labels')
        local options = canvas:GetParent()
        options:GetScript('OnShow')(options)
        check(canvas:GetText():find('00g 00s 00c', 1, true), 'Blizzard Settings reflects the saved price mode on show')
        selection = 'no_copper'
        canvas:Click('LeftButton')
        check(theme.GetPriceDisplayMode() == 'no_copper' and not plain(moverPrice:GetText()):find('c', 1, true),
            'Blizzard Settings changes the mode and refreshes Quick Look without copper')
        canvas:Click('RightButton')
        chart:SetData(bars)
        check(chart.yLabels[1]:GetWidth() == 64, 'Analytics chart restores its Standard axis spacing after reset')
        chart:Hide()
        check(theme.GetPriceDisplayMode() == 'compact' and refreshes == 3 and invalidations == 3,
            'Right-click restores Standard and each setting change refreshes the UI')
        theme.OpenDropDown, provider.Invalidate, app.refresh = oldOpen, oldInvalidate, oldRefresh
    end
    check(frame.addButton._points[1][4]==0 and frame.addButton:GetWidth()==132
        and frame.searchButton._points[1][4]==535 and frame.searchButton:GetWidth()==89,
        'Quick Look exposes the cart and search actions at opposite footer edges')
    do
        local function blend(foreground, background)
            local alpha=foreground[4] or 1
            return {foreground[1]*alpha+background[1]*(1-alpha), foreground[2]*alpha+background[2]*(1-alpha),
                foreground[3]*alpha+background[3]*(1-alpha)}
        end
        local function luminance(rgb)
            local function linear(channel)
                return channel <= 0.04045 and channel/12.92 or ((channel+0.055)/1.055)^2.4
            end
            return 0.2126*linear(rgb[1])+0.7152*linear(rgb[2])+0.0722*linear(rgb[3])
        end
        local function assertContrast(ink, background, label)
            check(ink ~= nil, label..' has painted ink')
            local foreground, backdrop=luminance(blend(ink, background)), luminance(background)
            local ratio=(math.max(foreground,backdrop)+0.05)/(math.min(foreground,backdrop)+0.05)
            check(ratio>=3, string.format('%s contrast is %.2f:1', label, ratio))
        end
        local function assertColor(actual, expected, label)
            check(sameColor(actual,expected), label..' repaints with the current palette')
        end
        local function assertTextContrast(fs, background, label)
            assertContrast(fs._lastColor, background, label)
            for a,r,g,b in fs:GetText():gmatch('|c(%x%x)(%x%x)(%x%x)(%x%x)') do
                assertContrast({tonumber(r,16)/255,tonumber(g,16)/255,tonumber(b,16)/255,tonumber(a,16)/255},
                    background, label..' embedded color')
            end
        end
        local function surfaceBackground(widget, asset, expected, base, label, radius)
            for _, texture in ipairs({widget:GetRegions()}) do
                if texture._layer=='BACKGROUND' and texture:GetTexture()==asset then
                    if radius then
                        check(texture:GetWidth()==radius and texture:GetHeight()==radius, label..' has concentric corner slices')
                    end
                    assertColor(texture._vertexColor,expected,label)
                    return blend(texture._vertexColor,base)
                end
            end
            error(label..' is missing its background texture')
        end
        local function checkMetricTheme(widgets, background, pal)
            local label=widgets.name:GetText()
            assertColor(widgets.name._lastColor,pal.text,label..' name')
            assertColor(widgets.qty._lastColor,pal.textSecondary,label..' quantity')
            assertColor(widgets.price._lastColor,pal.text,label..' value')
            assertColor(widgets.rule._colorTexture,{pal.textMuted[1],pal.textMuted[2],pal.textMuted[3],0.78},label..' rule')
            assertColor(widgets.active._colorTexture,pal.glassHover,label..' selection')
            if widgets.active:IsShown() then background=blend(widgets.active._colorTexture,background) end
            for _, key in ipairs({'name','qty','price','impact','pct','coverage','fixed'}) do
                if widgets[key]:IsShown() then assertTextContrast(widgets[key],background,label..' '..key) end
            end
        end

        local line=chart.trace.lines[7]
        for _, mode in ipairs({'light','dark'}) do
            ns.Theme.SetMode(mode)
            local pal,assets=ns.Theme.PALETTES[mode],ns.Theme.ASSETS
            local muted,red=quickLookInk(frame,'textMuted'),quickLookInk(frame,'accentRed')
            local hudCorner=frame.surface.fill.pieces[1]
            local hudFill=hudCorner._vertexColor
            check(frame.surface.kind=='glass_r22' and frame.surface.specular==nil and hudCorner:GetWidth()==22,
                'Quick Look uses the curved outer glass surface')
            assertColor(hudFill,mode=='dark' and pal.toolbarBg or pal.winBg,'Quick Look surface')
            local hudBackground=blend(hudFill,pal.winBg)
            check(frame:IsShown() and frame.palette==pal and chart:IsShown() and chart.trace.lines[7]==line and line:IsShown(),
                mode..' theme preserves the pinned HUD and its expanded chart')
            local scrollBackground
            for _, section in ipairs({{frame.overviewPanel,frame.overviewHeaders,overview,pal.cardBg},
                    {frame.moverPanel,frame.moverHeaders,frame.movers,pal.cardBg},
                    {frame.scrollPanel,frame.scrollHeaders,{scroll,listings},pal.cardBg}}) do
                local title=section[2][1]:GetText()
                local background=surfaceBackground(section[1],assets.glass_r12_fill,section[4],hudBackground,title,12)
                if section[1]==frame.scrollPanel then scrollBackground=background end
                for _, header in ipairs(section[2]) do
                    assertColor(header._lastColor,muted,header:GetText())
                    assertTextContrast(header,background,header:GetText())
                end
                for _, widgets in ipairs(section[3]) do checkMetricTheme(widgets,background,pal) end
            end
            for _, fs in ipairs({frame.whereToBuy,frame.breakEven}) do
                assertColor(fs._lastColor,pal.textSecondary,fs:GetText())
                assertTextContrast(fs,scrollBackground,fs:GetText())
            end
            assertColor(listings.trace.lines[7]._colorTexture,red,'scroll listing sparkline')
            assertContrast(listings.trace.lines[7]._colorTexture,scrollBackground,'scroll listing sparkline')
            local pills=surfaceBackground(frame.win24Btn:GetParent(),assets.pill_fill,pal.glassFill,hudBackground,'history control')
            for _, button in ipairs({frame.win24Btn,frame.win7dBtn}) do
                local label=button.fs:GetText()
                local fill=button._mmPlate.active and pal.pillThumb or pal.pillTrack
                local background=surfaceBackground(button,assets.pill_fill,fill,pills,label..' pill')
                assertColor(button.fs._lastColor,pal.text,label..' label')
                assertTextContrast(button.fs,background,label..' label')
            end
            local chartBackground=surfaceBackground(chart,assets.glass_r12_fill,pal.cardBg,hudBackground,'expanded chart',12)
            assertColor(chart.title._lastColor,pal.text,'expanded chart title')
            assertColor(chart.value._lastColor,pal.text,'expanded chart value')
            assertColor(chart.pct._lastColor,red,'rising reagent chart percentage')
            for _, key in ipairs({'title','value','impact','pct'}) do
                assertTextContrast(chart[key],chartBackground,'expanded chart '..key)
            end
            for _, axis in ipairs(chart.axis) do
                assertColor(axis._lastColor,muted,'chart axis')
                assertTextContrast(axis,chartBackground,'chart axis')
            end
            for _, tick in ipairs(chart.ticks) do
                assertColor(tick._lastColor,pal.textSecondary,'chart tick')
                assertTextContrast(tick,chartBackground,'chart tick')
            end
            assertColor(line._colorTexture,red,'chart line')
            assertColor(chart.trace.dots[7]._vertexColor,red,'chart dot')
            assertContrast(line._colorTexture,chartBackground,'chart line')
            local hit=chart.hits[7]
            hit:GetScript('OnEnter')(hit)
            local readoutBackground=surfaceBackground(frame.readout,assets.glass_r8_fill,pal.cardAltBg,chartBackground,'chart readout')
            assertColor(frame.dayReadout._lastColor,pal.textSecondary,'chart readout text')
            assertTextContrast(frame.dayReadout,readoutBackground,'chart readout text')
            hit:GetScript('OnLeave')(hit)
        end
    end
    scroll:Click('LeftButton')
    check(chart:IsShown() and chart.title:GetText()=='Recipe scroll — 7d' and chart.trace.dots[7]:IsShown(),
        'the recipe scroll expands its own weekly price chart')
    checkBelow(frame,chart,frame.scrollPanel,'the recipe scroll chart opens directly below the source panel')
    checkBelow(frame,frame.footer,chart,'the footer moves below the recipe scroll chart')
    frame.mouseOver=true
    frame:GetScript('OnEvent')(frame,'GLOBAL_MOUSE_DOWN','LeftButton')
    check(frame:IsShown(),'inside clicks leave Quick Look open')
    frame.mouseOver=false
    frame:GetScript('OnEvent')(frame,'GLOBAL_MOUSE_DOWN','LeftButton')
    check(not frame:IsShown() and not frame.keyboard and not frame._events.GLOBAL_MOUSE_DOWN,'outside clicks close and release listeners')
    check(provider.OpenQuickLook(recipeKey,true)==frame,'recipe key opens the same frame')
    frame:GetScript('OnKeyDown')(frame,'A')
    check(frame:IsShown() and frame.propagate,'ordinary keys still propagate')
    frame:GetScript('OnKeyDown')(frame,'ESCAPE')
    check(not frame:IsShown() and not frame.propagate,'Escape dismisses Quick Look')
    check(provider.OpenQuickLook(13512,true)==frame,'item ID opens the same frame')
    frame.closeButton:Click()
    check(not frame:IsShown(),'circular close button dismisses Quick Look')
    provider.OpenQuickLook(row,false)
    frame:GetScript('OnUpdate')(frame,0.25)
    check(not frame:IsShown(),'unpinned Quick Look closes after the pointer leaves')

    local extraRow={}
    for k,v in pairs(row) do extraRow[k]=v end
    extraRow.key='quick-look-five-reagents'
    extraRow.recipe={outputItemID=13512,reagents={{13468,1},{13463,30},{13465,10},{8925,1},{3371,2}}}
    extraRow.sourceLabel,extraRow.craftAbility='Trainer',nil
    provider.OpenQuickLook(extraRow,true)
    local track,thumb=frame.moverScrollTrack,frame.moverScrollThumb
    check(track:IsShown() and frame.moverOffset==0 and #frame.movers==4 and frame.moverPanel:GetHeight()==132
        and frame.whereToBuy:GetText()=='Where to buy: Trainer' and frame.scrollRow.fixed:GetText()=='TRAINER',
        'five reagents show four visible slots and the trainer source in the fixed layout')
    checkUnavailableScroll(frame,'TRAINER')
    check(track:GetHeight()==102 and thumb:GetHeight()==82 and track._points[1][4]==612 and track._points[1][5]==-23,
        'five reagents have a proportional scrollbar thumb')
    frame.SetMoverScroll(99)
    check(frame.moverOffset==1,'the reagent scroll setter clamps at the final row')
    frame.SetMoverScroll(-99)
    check(frame.moverOffset==0,'the reagent scroll setter clamps at the first row')
    frame.moverPanel:GetScript('OnMouseWheel')(frame.moverPanel,-1)
    check(frame.moverOffset==1 and frame.movers[4].name:GetText()==frame.data.movers[5].name
        and frame.movers[1].pct:GetText()=='-12.5%' and thumb._points[1][5]==-20,
        'wheel down reveals the fifth reagent and repaints its percentage in the recycled slot')
    track:GetScript('OnMouseWheel')(track,-1)
    check(frame.moverOffset==1,'wheel scrolling clamps at the final reagent')
    frame.movers[1]:GetScript('OnMouseWheel')(frame.movers[1],1)
    check(frame.moverOffset==0,'wheel up over a reagent returns to the first row')
    local oldCursor=GetCursorPosition
    GetCursorPosition=function() return 0,track:GetTop()-100 end
    track:GetScript('OnMouseDown')(track,'LeftButton')
    check(frame.moverOffset==1,'clicking below the scrollbar thumb scrolls down')
    GetCursorPosition=function() return 0,track:GetTop() end
    track:GetScript('OnMouseDown')(track,'LeftButton')
    check(frame.moverOffset==0,'clicking above the scrollbar thumb scrolls up')
    local oldTrackScale=track:GetScale()
    track:SetScale(1.25)
    GetCursorPosition=function() return 0,(track:GetTop()-100)*track:GetEffectiveScale() end
    track:GetScript('OnMouseDown')(track,'LeftButton')
    check(frame.moverOffset==1,'scrollbar track clicks account for the effective UI scale')
    track:SetScale(oldTrackScale)
    GetCursorPosition=oldCursor
    provider.OpenQuickLook(row,true)
    check(frame.moverOffset==0 and not frame.moverScrollTrack:IsShown(),'opening another recipe resets reagent scrolling')
    local emptyRow={}
    for k,v in pairs(row) do emptyRow[k]=v end
    emptyRow.key='quick-look-no-reagents'
    emptyRow.recipe={outputItemID=13512,reagents={}}
    provider.OpenQuickLook(emptyRow,true)
    check(frame.moverEmpty:IsShown() and frame.moverEmpty:GetText()=='No reagents listed'
        and frame.moverEmpty.justifyH=='CENTER' and not frame.movers[1]:IsShown()
        and not frame.moverScrollTrack:IsShown(),'recipes without reagents show the centered empty state')
    provider.OpenQuickLook(row,true)
    frame.addButton:Click()
    check(frame.addButton:GetText()=='Added' and app.getRecipeShoppingQty(row)==1,'cart action queues one craft and confirms the addition')
    AuctionHouseFrame:Hide()
    local beforeClosedSearch=ahCalls
    frame.searchButton:Click()
    check(frame.banner:IsShown() and ahCalls==beforeClosedSearch and frame.bannerText:GetText():find('14 listed',1,true)
        and frame.bannerText:GetText():find('4m ago',1,true),'closed AH shows the local scan price, listing count and age')
    frame.searchButton:Click()
    check(not frame.banner:IsShown(),'closed AH button toggles the inline result')
    local previousQuote = livePrices[13512]
    local quotedAt, scannedAt = time()-3600, time()-120
    livePrices[13512] = { lastPrice = 1, lastAt = quotedAt, qty = 3, at = scannedAt }
    local function checkBidOnlyBanner(source)
        provider.RefreshQuickLook()
        for _, mode in ipairs({ 'dark', 'light' }) do
            ns.Theme.SetMode(mode)
            frame.searchButton:Click()
            local bannerText = frame.bannerText:GetText()
            check(frame.banner:IsShown() and bannerText:find('No buyout',1,true) and bannerText:find('3 listed',1,true)
                and bannerText:find('2m ago',1,true) and not bannerText:find('Lowest',1,true),
                mode .. ' bid-only ' .. source .. ' banner displays current quantity and age without a stale buyout')
            frame.searchButton:Click()
        end
    end
    checkBidOnlyBanner('Browse')
    local oldAHAPI, oldTime, oldOutputDaily = C_AuctionHouse, time, daily[13512]
    local oldLots = MerchantMasterDB.ahLots
    daily[13512], MerchantMasterDB.ahLots = nil, nil
    _G.time = function() return scannedAt end
    _G.C_AuctionHouse = setmetatable({
        HasFullItemSearchResults = function() return true end,
        GetNumItemSearchResults = function() return 3 end,
        GetItemSearchResultInfo = function() return { quantity = 1, buyoutAmount = 0 } end,
    }, { __index = oldAHAPI })
    ns.MarketScan.HandleEvent('ITEM_SEARCH_RESULTS_UPDATED', { itemID = 13512 })
    _G.C_AuctionHouse, _G.time = oldAHAPI, oldTime
    check(livePrices[13512].qty == 0 and livePrices[13512].absent and livePrices[13512].lastAt == quotedAt,
        'Complete ItemSearch leaves zero purchasable units and preserves the last positive quote timestamp')
    checkBidOnlyBanner('ItemSearch')
    daily[13512], MerchantMasterDB.ahLots = oldOutputDaily, oldLots
    ns.Theme.SetMode('dark')
    livePrices[13512] = previousQuote
    AuctionHouseFrame:Show()
    frame.searchButton:Click()
    check(ahCalls==beforeClosedSearch+1 and not frame.banner:IsShown(),'open AH dispatches the existing search')
    AuctionHouseFrame:Hide()
    provider.CloseQuickLook()
    app.searchAH=oldAH
    _G.IsAltKeyDown,_G.IsShiftKeyDown=oldAlt,oldShift
    ns.GetItemMarketPrice = priorVialMarket
    livePrices[13521]=oldScrollQuote
    MerchantMasterDB.ahDaily,MerchantMasterDB.ahHistory=oldDaily,oldHistory
    MerchantMasterDB.ahSnapshots,MerchantMasterDB.quickLookWindow,MerchantMasterDB.priceDisplayMode=oldSnapshots,oldWindow,oldMode
end
checkRecipeQuickLook()

do
    local db, scanner = MerchantMasterDB, ns.MarketScan
    local oldAH, oldTime, oldTheme = C_AuctionHouse, time, ns.Theme.GetMode()
    local oldMode, oldRefreshAt = db.priceDisplayMode, db.lastRefreshAt
    local oldAppPrices, oldNSPrices = app.ahPrices, ns.ahPrices
    local saved, economy = {}, ns.DetectActiveEconomy()
    local fields = { 'ahPrices', 'ahDaily', 'ahHistory', 'ahSnapshots', 'ahLots', 'ahVariants', 'sellerStats', 'econSnapshots', 'regionSalesCache' }
    for _, field in ipairs(fields) do
        saved[field], db[field] = db[field], {}
    end
    local hood, vial = 7048, 8925
    local latest = math.floor(time() / 86400) * 86400 + 3600
    local browseAt = latest - 600
    local day = math.floor(browseAt / 86400)
    local hoodRow = { recipe = ns.RECIPES_BY_OUTPUT[hood][1], name = ns.ItemName(hood), outputItemID = hood }
    local vialRow = { recipe = { outputItemID = 13512, reagents = {{vial, 2}} }, name = ns.ItemName(13512) }
    local vendor = assert(ns.GetRecipeVendorBuyPrice(vial, ns.VENDOR_REAGENTS[vial]))
    db.priceDisplayMode = 'no_copper'
    _G.time = function() return browseAt end
    _G.C_AuctionHouse = setmetatable({
        GetBrowseResults = function() return {
            { itemKey = { itemID = hood }, totalQuantity = 3, minPrice = 300 },
            { itemKey = { itemID = hood, itemSuffix = 9 }, totalQuantity = 9, minPrice = 100 },
        } end,
        HasFullItemSearchResults = function() return true end,
        GetNumItemSearchResults = function() return 1 end,
        GetItemSearchResultInfo = function() return { quantity = 3, buyoutAmount = 900 } end,
    }, { __index = oldAH })
    AuctionHouseFrame:Show()
    check(app.refreshAllMarketValues(), 'Full Browse starts for the Quick Look fixtures')
    scanner.HandleEvent('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
    local prices, daily, history = db.ahPrices[economy], db.ahDaily[economy], db.ahHistory[economy]
    check(daily[vial][1].at == browseAt and daily[vial][1].lastQ == 0 and daily[vial][1].obsP == 0,
        'Full Browse records the Crystal Vial empty-market snapshot')
    _G.time = function() return latest end
    scanner.HandleEvent('ITEM_SEARCH_RESULTS_UPDATED', { itemID = hood })
    check(prices[hood].at == latest and prices[hood].qty == 3 and daily[hood][1].lastQ == 12,
        'Newer base Search updates the Hood price cache while Browse retains all 12 listings')
    AuctionHouseFrame:Hide()
    local function banner(row)
        local frame = provider.OpenQuickLook(row, true)
        frame.searchButton:Click()
        local text = frame.bannerText:GetText():gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
        provider.CloseQuickLook()
        return text
    end
    local browseBucket, browseRing, searchPrice = daily[hood][1], history[hood], prices[hood]
    for _, theme in ipairs({ 'dark', 'light' }) do
        ns.Theme.SetMode(theme)
        local text = banner(hoodRow)
        check(text:find('Lowest 1s', 1, true) and text:find('12 listed', 1, true) and text:find('10m ago', 1, true),
            theme .. ' Quick Look uses the Azure Silk Hood Browse price, quantity and age after a base-only Search')

        local legacyAt = browseAt - 86400
        local legacyBucket = { d = day - 1, at = legacyAt, lastP = 100, lastQ = 12 }
        daily[hood][1], prices[hood] = legacyBucket, nil
        history[hood] = { { t = legacyAt, p = 100, q = 12 }, { t = legacyAt + 600, p = 300, q = 3 } }
        check(banner(hoodRow):find('Lowest 1s', 1, true), theme .. ' legacy daily bucket recovers its exact history buyout')
        history[hood] = nil
        check(banner(hoodRow):find('No buyout', 1, true), theme .. ' legacy daily bucket needs confirmation for its last price')
        prices[hood] = { at = legacyAt, price = 100, qty = 12 }
        db.ahVariants[economy][hood] = nil
        local sellerCoverage = db.sellerStats[economy].coverage
        local coveredHoodKeys = sellerCoverage[hood]
        sellerCoverage[hood] = nil
        check(banner(hoodRow):find('Lowest 1s', 1, true), theme .. ' legacy daily bucket recovers its exact cached buyout')
        sellerCoverage[hood] = coveredHoodKeys
        legacyBucket.obsP = 0
        history[hood] = { { t = legacyAt, p = 100, q = 12 } }
        check(banner(hoodRow):find('No buyout', 1, true), theme .. ' explicit zero stays No buyout with matching positive quotes')
        daily[hood][1], history[hood], prices[hood] = browseBucket, browseRing, searchPrice
        db.ahVariants[economy][hood] = true

        local frame = provider.OpenQuickLook(vialRow, true)
        local mover = frame.movers[1]
        check(frame.data.movers[1].pureVendor and mover.fixed:IsShown() and mover.fixed:GetText() == 'VENDOR'
            and mover.pct:GetText() == '0.0%' and mover.coverage:GetText() == 'N/A',
            theme .. ' empty Browse market keeps Crystal Vial VENDOR, 0.0%, N/A')
        check(frame.data.cost.days == 7, theme .. ' Crystal Vial craft cost uses all seven days')
        for i = 1, 7 do
            check(frame.data.cost.values[i] == 2 * vendor, theme .. ' Crystal Vial keeps the vendor cost on day ' .. i)
        end
        provider.CloseQuickLook()

        db.priceDisplayMode = 'compact'
        local thread, today = 2321, math.floor(latest / 86400)
        prices[thread] = { at = latest, price = 100, qty = 12 }
        daily[thread] = { { d = today - 1, at = today * 86400 - 1, lastP = 1, obsP = 1, lastQ = 1 } }
        local function checkThreadQuote(label)
            local threadFrame = provider.OpenQuickLook(hoodRow, true)
            local threadData, threadWidgets
            for i, reagent in ipairs(threadFrame.data.movers) do
                if reagent.itemID == thread then
                    threadData, threadWidgets = reagent, threadFrame.movers[i]
                    break
                end
            end
            check(threadData and not threadData.pureVendor and threadWidgets.fixed:IsShown()
                and threadWidgets.fixed:GetText() == 'VENDOR' and threadWidgets.coverage:GetText() == '2/7d'
                and threadWidgets.impact:GetText():gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '') == '+99c',
                theme .. ' Fine Thread ' .. label .. ' renders VENDOR, 2/7d, and +99c')
            provider.CloseQuickLook()
        end
        checkThreadQuote('legacy quote with a yesterday observation')
        daily[thread][2] = { d = today, at = latest - 300, lastP = 1, obsP = 1, lastQ = 1 }
        prices[thread].itemWide = true
        checkThreadQuote('newer item-wide quote after an earlier observation today')
        db.priceDisplayMode = 'no_copper'
    end
    for _, field in ipairs(fields) do db[field] = saved[field] end
    app.ahPrices, ns.ahPrices = oldAppPrices, oldNSPrices
    db.priceDisplayMode, db.lastRefreshAt = oldMode, oldRefreshAt
    _G.C_AuctionHouse, _G.time = oldAH, oldTime
    ns.Theme.SetMode(oldTheme)
end

do
    local db, ui, stats = MerchantMasterDB, app.ui, ns.RecipeStats
    local oldDaily, oldHistory, oldShopping, oldQueue = db.ahDaily, db.ahHistory, db.shoppingList, db.writTurnInQueue
    local oldShift, oldMode = _G.IsShiftKeyDown, db.priceDisplayMode
    local oldSnapshots, oldWindow, oldWritMode, oldCrateMode = db.ahSnapshots, db.quickLookWindow, db.writMode, db.crateMode
    local oldQuickLookRows = app.quickLookRows
    local economy, now = ns.CurrentEconomyInfo().effectiveKey, time()
    local today, hour = math.floor(now / 86400), math.floor(now / 3600) * 3600
    local daily, snapshots = {}, {}
    db.ahDaily, db.ahHistory, db.shoppingList, db.writTurnInQueue = { [economy] = daily }, {}, {}, {}
    db.ahSnapshots, db.quickLookWindow, db.writMode, db.crateMode = { [economy] = snapshots }, '7d', 'buy', 'buy'
    app.quickLookRows = {}
    _G.IsShiftKeyDown = function() return false end
    local function seed(id, price)
        daily[id] = {}
        for day = 1, 7 do
            daily[id][day] = { d = today - 7 + day, lastP = price + day * 10, lastQ = 19 - day,
                at = now - (7 - day) * 86400 }
        end
        snapshots[id] = { hour - 17 * 3600, price + 15, 18, now, price + 90, 12 }
    end
    for id, price in pairs({ [264066] = 1234, [8949] = 3400, [3821] = 180, [3820] = 231,
        [248704] = 2219, [4359] = 860, [2840] = 118, [4361] = 1800, [4363] = 2500 }) do seed(id, price) end

    local function find(rows, match)
        for _, row in ipairs(rows) do if match(row) then return row end end
    end
    local writRows = ns.BuildWritRows({ search = 'Elixir of Agility' })
    local writ = assert(find(writRows, function(row) return row.writID == 264066 end))
    local crateRows = ns.BuildCrateRows({ search = 'Apprentice Parts' })
    local crate = assert(find(crateRows, function(row) return row.crateID == 248704 and row.reagentID == 4359 end))
    writ.totalPrice, writ.writPrice, writ.pouchRefund, writ.pricePerRep = 4321, 1304, 7480, 4321 / writ.rep
    writ.cdInfo, writ.cdAvailable, writ.cdText = { available = false, shortText = '35m' }, false, '35m'
    writ.zone, writ.npc = 'The Hinterlands', 'Juo'
    writ.listed, writ.salesPerDay, writ.demand = 12, 6, nil
    crate.totalPrice, crate.cratePrice, crate.reward, crate.pricePerToken = 5432, 2289, 1000, 5432 / crate.tokens
    crate.listed, crate.salesPerDay, crate.demand = 12, 0.48, nil
    local options = { economy = economy, writMode = 'buy', crateMode = 'buy', ownedCounts = { [264066] = 2 } }
    local writLook = stats.BuildWritQuickLook(writ, options, now)
    local crateLook = stats.BuildCrateQuickLook(crate, options, now)
    local function checkModel(data, rowID, targetID, tag, targetTag, chartKey, refundKey)
        check(#data.days == 7 and data.chartSeries.netCost.days == 7 and data.chartSeries[chartKey].days == 7,
            data.kind .. ' uses seven aligned observations')
        local last = data.days[7]
        local primaryPrice = last.writPrice or last.cratePrice
        check(last.d == today and last.netCost == primaryPrice + last[chartKey] - last[refundKey],
            data.kind .. ' subtracts its cashback from the combined acquisition cost')
        check(data.movers[1].itemID == rowID and data.movers[1].qty == 1 and data.movers[1].tag == tag
            and data.movers[2].itemID == targetID and data.movers[2].tag == targetTag,
            data.kind .. ' pins the two acquisition items in order')
        check(data.movers[1].days == 7 and data.movers[1].impact == 60 and data.movers[1].deltaPct > 0
            and #data.movers >= 4 and data.movers[3].indent > 0 and data.movers[3].tag == 'Reagent',
            data.kind .. ' carries history trends and an indented recipe breakdown')
        local overview = data.overviewRows
        check(#overview == 6 and overview[4].fixed and overview[4].liveValue == last[refundKey]
            and overview[1].series == data.chartSeries.netCost and overview[1].series.pct > 0,
            data.kind .. ' supplies a fixed cashback row and a percentage change for net cost')
    end
    checkModel(writLook, 264066, 8949, 'Writ', 'Turn-In', 'turnInCost', 'pouchRefund')
    checkModel(crateLook, 248704, 4359, 'Crate', 'Bundle', 'bundleCost', 'reward')
    local craftCrate={}
    for key,value in pairs(crate) do craftCrate[key]=value end
    craftCrate.mode='Craft'
    local craftCrateLook=stats.BuildCrateQuickLook(craftCrate,options,now)
    local selectedBundle
    for _,mover in ipairs(craftCrateLook.movers) do
        if mover.itemID==craftCrate.reagentID and mover.tag=='Bundle' then selectedBundle=mover; break end
    end
    check(selectedBundle and craftCrateLook.chartSeries.bundleCost.values[7]
        == selectedBundle.series.values[7]*selectedBundle.qty,
        'Crate Craft override keeps selected bundle chart and mover series aligned')
    local unavailableWrit={}
    for key,value in pairs(writ) do unavailableWrit[key]=value end
    unavailableWrit.mode,unavailableWrit.craftCost,unavailableWrit.buyCost=nil,nil,nil
    local unavailableWritLook = stats.BuildWritQuickLook(unavailableWrit,options,now)
    check(unavailableWritLook.subtitle:find('Price unavailable',1,true)
        and unavailableWritLook.meta.mode == 'Price unavailable',
        'Unpriced Writ shows unavailable pricing instead of Buy AH')
    local unavailableCrate={}
    for key,value in pairs(crate) do unavailableCrate[key]=value end
    unavailableCrate.mode,unavailableCrate.craftTotal,unavailableCrate.buyTotal=nil,nil,nil
    check(stats.BuildCrateQuickLook(unavailableCrate,options,now).subtitle:find('Price unavailable',1,true),
        'Unpriced Crate shows unavailable pricing instead of Buy AH')
    check(writLook.movers[1].owned == 2 and writLook.meta.canQueue and writLook.meta.cdText == '35m'
        and writLook.subtitle:find('The Hinterlands', 1, true) and writLook.subtitle:find('Juo', 1, true),
        'Writ HUD includes ownership, turn-in area, NPC, and remaining cooldown')
    check(crateLook.meta.canAddToList and crateLook.badge:find('Favor', 1, true) and crateLook.subtitle:find('Cashback', 1, true),
        'Crate HUD includes Favor, cashback, and cart action')
    check(stats.BuildQuickLook(writ, options, now).kind == 'writ' and stats.BuildQuickLook(crate, options, now).kind == 'crate',
        'The shared Quick Look builder recognizes both turn-in row types')
    local ammo = find(ns.BuildWritRows({ search = 'Crafted Solid Shot' }), function(row) return row.writID == 264037 end)
    local ammoLook = stats.BuildWritQuickLook(ammo, options, now)
    check(ammoLook.movers[2].qty == 200 and ammoLook.movers[3].qty == 1 and ammoLook.movers[4].qty == 1,
        'A Writ requiring 200 bullets shows the materials for one 200-bullet craft')

    local function openFromRow(tab, row, tableWidget, second)
        app.setTab(tab)
        local rows = { row, second }
        tableWidget.setRows(rows)
        app.quickLookRows[row.writID and 'writ' or 'crate'] = rows
        local first = tableWidget.scrollBox._frames[1]
        first.cells[1]:Click('LeftButton')
        local frame = provider.GetQuickLookFrame()
        check(frame:IsShown() and frame.row == row and frame.pinned, tab .. ' row left-click opens the shared HUD')
        return frame, first
    end
    local function checkNameCellToggle(tab, row, tableWidget, expectedID)
        local oldSearch, ahShown = app.searchAH, AuctionHouseFrame:IsShown()
        local searches = 0
        AuctionHouseFrame:Show()
        app.searchAH = function(_, qty, itemID)
            check(qty == 1 and itemID == expectedID, tab .. ' name searches for one of the selected item')
            searches = searches + 1
        end
        local hud, rowFrame = openFromRow(tab, row, tableWidget)
        check(searches == 1, tab .. ' name searches the AH when it opens Quick Look')
        rowFrame.cells[1]:Click('LeftButton')
        check(not hud:IsShown() and searches == 1, tab .. ' name closes Quick Look without another AH search')
        app.searchAH = oldSearch
        AuctionHouseFrame:SetShown(ahShown)
    end
    local function checkModes(frame)
        local oldOpen = ns.Theme.OpenDropDown
        for _, mode in ipairs({ 'compact', 'no_copper', 'full_fixed' }) do
            ns.Theme.OpenDropDown = function(_, _, _, choose) choose(mode) end
            ui.priceFmtBtn:Click('LeftButton')
            local price, reward = frame.movers[1].price, frame.overviewRows[4].price
            check(frame:IsShown() and price.justifyH == 'RIGHT' and reward.justifyH == 'RIGHT'
                and plain(price:GetText()) == plain(ns.Theme.FormatMoneyText(frame.data.movers[1].unitPrice))
                and plain(reward:GetText()) == plain(ns.Theme.FormatMoneyText(frame.data.overviewRows[4].liveValue)),
                frame.data.kind .. ' live Options repaint aligns and formats prices in ' .. mode)
        end
        ns.Theme.OpenDropDown = oldOpen
        local oldMode, optionsShown = db.priceDisplayMode, ui.optionsFrame:IsShown()
        ui.optionsFrame:Show()
        ui.optPriceFmtBtn:Click('LeftButton')
        local menu = ns.Theme.GetDropDownMenu()
        check(menu and menu:IsShown(), 'Options Price Format opens its theme dropdown')
        ui.optionsFrame.mouseOver = true
        frame:GetScript('OnEvent')(frame, 'GLOBAL_MOUSE_DOWN', 'LeftButton')
        check(frame:IsShown(), 'GLOBAL_MOUSE_DOWN over Options preserves Quick Look')
        ui.optionsFrame.mouseOver = false
        ui.priceFmtBtn.mouseOver = true
        frame:GetScript('OnEvent')(frame, 'GLOBAL_MOUSE_DOWN', 'LeftButton')
        check(frame:IsShown(), 'GLOBAL_MOUSE_DOWN over the sidebar Price Format control preserves Quick Look')
        ui.priceFmtBtn.mouseOver = false
        ui.optPriceFmtBtn.mouseOver = true
        frame:GetScript('OnEvent')(frame, 'GLOBAL_MOUSE_DOWN', 'LeftButton')
        check(frame:IsShown(), 'GLOBAL_MOUSE_DOWN over the Options Price Format control preserves Quick Look')
        ui.optPriceFmtBtn.mouseOver = false
        menu.mouseOver = true
        frame:GetScript('OnEvent')(frame, 'GLOBAL_MOUSE_DOWN', 'LeftButton')
        check(frame:IsShown(), 'GLOBAL_MOUSE_DOWN over a visible theme dropdown preserves Quick Look')
        menu.mouseOver = false
        local oldBlizzardDropdown = _G.DropDownList1
        _G.DropDownList1 = CreateFrame('Frame')
        _G.DropDownList1.mouseOver = true
        frame:GetScript('OnEvent')(frame, 'GLOBAL_MOUSE_DOWN', 'LeftButton')
        check(frame:IsShown(), 'GLOBAL_MOUSE_DOWN over a visible Blizzard dropdown preserves Quick Look')
        _G.DropDownList1 = oldBlizzardDropdown
        local option = menu.rows[2]
        option.mouseOver = true
        frame:GetScript('OnEvent')(frame, 'GLOBAL_MOUSE_DOWN', 'LeftButton')
        option:Click('LeftButton')
        option.mouseOver = false
        check(frame:IsShown() and db.priceDisplayMode == 'no_copper' and not menu:IsShown()
            and plain(frame.overviewRows[4].price:GetText()) == plain(ns.Theme.FormatMoneyText(frame.data.overviewRows[4].liveValue)),
            'Selecting the visible Price Format option keeps Quick Look open and repaints the values')
        ui.optionsFrame:SetShown(optionsShown)
        db.priceDisplayMode = oldMode
    end

    local function checkBannerLayout(frame)
        local kind = frame.kind
        local height, footerY = frame:GetHeight(), frame.footer._points[1][5]
        local chartY = frame.expandChart._points[1][5]
        frame.searchButton:Click()
        check(frame.banner:IsShown() and frame.bannerText:GetText():find('12 listed', 1, true)
            and frame:GetHeight() == height + frame.banner:GetHeight() + 6
            and frame.expandChart:IsShown() and frame.expandChart._points[1][5] == chartY,
            kind .. ' adds the closed-AH banner without moving the expanded chart')
        checkBelow(frame, frame.banner, frame.scrollPanel, kind .. ' banner follows the turn-in source')
        checkBelow(frame, frame.footer, frame.banner, kind .. ' footer moves below the banner')
        frame.searchButton:Click()
        check(not frame.banner:IsShown() and frame:GetHeight() == height and frame.footer._points[1][5] == footerY,
            kind .. ' hiding the banner restores the standard footer and HUD height')
    end

    local function checkTurnInHUD(frame, expect)
        local overview, chart, kind = frame.overviewRows, frame.expandChart, frame.kind
        check(frame:GetWidth() == 654 and frame.chart == nil and not chart:IsShown(), kind .. ' shares the collapsed Quick Look layout')
        checkQuickLookWindow(frame, '7d')
        checkOverview(frame, expect.labels)
        check(overview[2].pct:GetText() == expect.pricePct and overview[4].pct:GetText() == '0.0%'
            and overview[4].coverage:GetText() == 'Fixed' and overview[4].fixed:GetText() == 'FIXED',
            kind .. ' shows the acquisition price change and fixed reward')
        check(overview[5].price:GetText() == '12' and overview[5].pct:GetText() == '-33.3%'
            and plain(overview[6].price:GetText()) == expect.demand and overview[6].pct:GetText() == '+50.0%'
            and frame.data.overviewRows[6].liveValue == expect.ratio,
            kind .. ' derives Demand from listings and daily sales and shows both percentage changes')
        local dailyPct = overview[1].pct:GetText()
        check(dailyPct:match('^%+%d+%.%d%%$') and sameColor(overview[1].pct._lastColor, quickLookInk(frame, 'accentRed'))
            and sameColor(overview[1].price._lastColor, frame.palette.text),
            kind .. ' uses red ink for rising net cost and normal ink for its live value')
        check(frame.movers[4]:IsShown() and frame.movers[1].pct:GetText() == expect.pricePct,
            kind .. ' displays four material rows with its acquisition price trend')
        check(frame.scrollPanel:GetHeight() == 36 and not frame.scrollRow:IsShown() and not frame.scrollListedRow:IsShown()
            and not frame.scrollHeaders[1]:IsShown() and not frame.breakEven:IsShown()
            and frame.whereToBuy:GetText() == expect.source, kind .. ' shows only the turn-in source in the compact source panel')
        check(frame.data.sourceInfo.whereToBuy == expect.source:sub(#'Turn-in source: ' + 1),
            kind .. ' model supplies the source detail for the caption')
        checkQuickLookWowhead(frame, expect.url)

        local collapsedHeight, label = frame:GetHeight(), expect.labels[1]
        overview[1]:Click('LeftButton')
        check(chart:IsShown() and chart.title:GetText() == label .. ' — 7d' and chart.pct:GetText() == dailyPct
            and chart.trace.dots[1]:IsShown() and chart.trace.dots[7]:IsShown()
            and frame:GetHeight() == collapsedHeight + chart:GetHeight() + 6, kind .. ' expands the weekly net cost chart')
        checkBelow(frame, chart, frame.overviewPanel, kind .. ' chart follows the overview panel')
        checkBannerLayout(frame)
        frame.win24Btn:Click('LeftButton')
        check(db.quickLookWindow == '24h', kind .. ' saves the hourly window')
        checkQuickLookWindow(frame, '24h')
        check(chart:IsShown() and chart.title:GetText() == label .. ' — 24h' and chart.trace.dots[24]:IsShown()
            and not chart.trace.dots[1]:IsShown() and overview[1].coverage:GetText() == '2/24h'
            and overview[5].coverage:GetText() == '2/24h' and overview[6].coverage:GetText() == '2/24h',
            kind .. ' keeps the chart open and paints observed hours for net cost, listings, and demand')
        frame.win7dBtn:Click('LeftButton')
        check(db.quickLookWindow == '7d' and chart:IsShown() and chart.title:GetText() == label .. ' — 7d'
            and overview[1].coverage:GetText() == '7/7d' and not chart.hits[24]:IsShown(),
            kind .. ' restores the weekly chart and coverage')
        overview[1]:Click('LeftButton')
        check(not chart:IsShown() and frame:GetHeight() == collapsedHeight, kind .. ' collapses the inline chart on a second click')
    end

    local frame = openFromRow('writs', writ, ui.writsTable)
    check(frame.data.kind == 'writ' and frame.addButton:GetText() == '+ Queue Writ', 'Writ row selects Writ HUD labels and CTA')
    checkTurnInHUD(frame, {
        labels = {'Net turn-in cost', 'Writ scroll', 'Turn-in item', 'Coin pouch', 'AH listed', 'Demand'},
        pricePct = '+4.8%', demand = 'Hot', ratio = 6 / 12,
        source = 'Turn-in source: The Hinterlands — Juo (35m)', url = 'https://www.wowhead.com/forever/item=264066',
    })
    checkModes(frame)
    frame.addButton:Click('LeftButton')
    check(db.writTurnInQueue[writ.writID] == 1 and frame:IsShown(), 'Writ CTA queues one turn-in and keeps its HUD open')
    frame.addButton:Click('LeftButton')
    check(db.writTurnInQueue[writ.writID] == 2, 'Writ CTA increments a previously queued turn-in')
    app.setTab('crates')
    check(not frame:IsShown(), 'Changing tabs closes the Writ HUD')
    check(openFromRow('crates', crate, ui.cratesTable) == frame and frame.data.kind == 'crate', 'Crates reuse the same HUD')
    checkTurnInHUD(frame, {
        labels = {'Net crate cost', 'Empty crate', 'Bundle cost', 'Turn-in reward', 'AH listed', 'Demand'},
        pricePct = '+2.7%', demand = 'Cold', ratio = 0.48 / 12,
        source = 'Turn-in source: Waylaid Crate: Apprentice Parts (+' .. crate.tokens .. ' Favor, Mode ' .. crateLook.meta.mode .. ')',
        url = 'https://www.wowhead.com/forever/item=248704',
    })
    checkModes(frame)
    frame.addButton:Click('LeftButton')
    local demands = {}
    for _, entry in ipairs(db.shoppingList) do
        if entry.itemID then demands[entry.itemID] = entry.qty end
        for _, demand in ipairs(entry.demandList or {}) do demands[demand.itemID] = demand.qty end
    end
    check(demands[crate.crateID] == 1 and demands[crate.reagentID] == crate.reagentQty and frame:IsShown(),
        'Crate CTA adds the empty crate and the selected bundle to the unified cart')
    frame:GetScript('OnEvent')(frame, 'GLOBAL_MOUSE_DOWN', 'LeftButton')
    check(not frame:IsShown(), 'Outside click closes the Crate HUD')
    local otherCrate = assert(find(crateRows, function(row) return row.reagentID ~= crate.reagentID end))
    local _, first = openFromRow('crates', crate, ui.cratesTable, otherCrate)
    local second = ui.cratesTable.scrollBox._frames[2]
    second.mouseOver = true
    frame:GetScript('OnEvent')(frame, 'GLOBAL_MOUSE_DOWN', 'LeftButton')
    check(frame:IsShown(), 'Mouse down over another crate keeps the HUD open for in-place switching')
    second:Click('LeftButton')
    check(frame:IsShown() and frame.row == otherCrate, 'Clicking another crate updates the same HUD in place')
    second.mouseOver = false
    first:Click('LeftButton')
    check(frame:IsShown() and frame.row == crate, 'Clicking back restores the original crate')
    first:Click('LeftButton')
    check(not frame:IsShown(), 'Clicking the selected crate row toggles the HUD closed')
    checkNameCellToggle('writs', writ, ui.writsTable, writ.writID)
    checkNameCellToggle('crates', crate, ui.cratesTable, crate.crateID)
    openFromRow('crates', crate, ui.cratesTable)
    app.setTab('recipes')
    provider.OpenQuickLook(13512,true)
    provider.RefreshQuickLook()
    local sales=frame.overviewRows[4]
    check(frame.data.kind=='recipe' and sales.name:GetText()=='Sales per day' and not sales.fixed:IsShown()
        and sameColor(sales.price._lastColor,frame.palette.text) and frame.scrollRow:IsShown()
        and frame.scrollListedRow:IsShown() and frame.scrollPanel:GetHeight()==96,
        'reusing the HUD restores the recipe sales row and scroll section')
    frame = openFromRow('writs', writ, ui.writsTable)
    frame:GetScript('OnKeyDown')(frame, 'ESCAPE')
    check(not frame:IsShown(), 'Escape closes the Writ HUD')
    db.ahDaily, db.ahHistory, db.shoppingList, db.writTurnInQueue = oldDaily, oldHistory, oldShopping, oldQueue
    db.ahSnapshots, db.quickLookWindow, db.writMode, db.crateMode = oldSnapshots, oldWindow, oldWritMode, oldCrateMode
    app.quickLookRows = oldQuickLookRows
    _G.IsShiftKeyDown, db.priceDisplayMode = oldShift, oldMode
end

-- Real Azure Silk Hood inputs keep All Recipes and Writ acquisition decisions aligned.
do
    local oldMarket, oldTrend = ns.GetItemMarketPrice, ns.MarketScan.GetItemTrend7d
    local oldTheme = ns.Theme.GetMode()
    local now, economy = time(), ns.CurrentEconomyInfo().effectiveKey
    local today = math.floor(now / 86400)
    local prices = { [264049] = 100, [7048] = 900, [2321] = 1, [6260] = 50, [4305] = 100 }
    local threadHistory, threadToday, interiorThread
    ns.GetItemMarketPrice = function(id) return prices[id], 'AH' end
    ns.MarketScan.GetItemTrend7d = function(id)
        local points = {}
        for day = 1, 7 do
            local price = prices[id]
            if id == 2321 then
                if interiorThread then price = interiorThread[day]
                else price = (day == 7 and threadToday) or threadHistory or (day == 1 and 200) or (day == 2 and 1) or price end
            end
            if price then points[#points + 1] = { d = today - 7 + day, price = price } end
        end
        return { points = points }
    end
    local recipe = assert(ns.RECIPES_BY_OUTPUT[7048][1])
    local function findMover(data, id)
        for _, mover in ipairs(data.movers) do if mover.itemID == id then return mover end end
    end
    for _, theme in ipairs({ 'dark', 'light' }) do
        ns.Theme.SetMode(theme, true)
        local opts = { economy = economy, profMap = { tailoring = 300 }, subCraftMode = 'never', writMode = 'craft' }
        local row = { recipe = recipe, outputItemID = 7048 }
        local recipeLook = ns.RecipeStats.BuildQuickLook(row, opts, now)
        local writ = assert((function()
            for _, candidate in ipairs(ns.BuildWritRows(opts)) do
                if candidate.writID == 264049 then return candidate end
            end
        end)())
        local writLook = ns.RecipeStats.BuildWritQuickLook(writ, opts, now)
        check(recipeLook.cost.values[7] == 301 and writLook.cost.values[7] == 301,
            theme .. ' All Recipes and Writ use 1c AH Fine Thread in the 301c craft')
        check(findMover(recipeLook, 2321).series.values[1] == 100
            and not findMover(recipeLook, 2321).fixed and not findMover(writLook, 2321).fixed,
            theme .. ' per-day Fine Thread quote selects vendor or AH and current AH removes VENDOR badge')
        threadHistory = 200
        recipeLook = findMover(ns.RecipeStats.BuildQuickLook(row, opts, now), 2321)
        writLook = findMover(ns.RecipeStats.BuildWritQuickLook(writ, opts, now), 2321)
        check(not recipeLook.fixed and recipeLook.unitPrice == 1 and not writLook.fixed and writLook.unitPrice == 1,
            theme .. ' live AH undercut removes VENDOR badges even with vendor-only history')
        prices[2321], threadHistory = 200, 1
        recipeLook = findMover(ns.RecipeStats.BuildQuickLook(row, opts, now), 2321)
        writLook = findMover(ns.RecipeStats.BuildWritQuickLook(writ, opts, now), 2321)
        check(recipeLook.fixed and recipeLook.unitPrice == 100 and writLook.fixed and writLook.unitPrice == 100,
            theme .. ' current vendor selection restores VENDOR badges despite past AH undercuts')
        threadToday = 200
        local frame = provider.OpenQuickLook(writ, true, nil, { kind = 'writ' })
        local threadWidgets
        for i, mover in ipairs(frame.data.movers) do
            if mover.itemID == 2321 then
                if i > #frame.movers and frame.SetMoverScroll then
                    frame.SetMoverScroll(i - #frame.movers)
                end
                threadWidgets = frame.movers[i - (frame.moverOffset or 0)]
                break
            end
        end
        check(threadWidgets and threadWidgets.fixed:IsShown()
            and threadWidgets.impact:GetText():gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '') == '+99c'
            and threadWidgets.coverage:GetText() == '7/7d',
            theme .. ' Fine Thread keeps VENDOR and displays its 99c weekly impact and coverage')
        provider.CloseQuickLook()
        interiorThread = { [2] = 1, [5] = 100 }
        local interiorRecipe = ns.RecipeStats.BuildQuickLook(row, opts, now)
        local interiorWrit = ns.RecipeStats.BuildWritQuickLook(writ, opts, now)
        check(interiorRecipe.cost.days == 7 and interiorRecipe.cost.values[1] == 400
            and interiorWrit.cost.days == 7 and interiorWrit.cost.values[7] == 400,
            theme .. ' missing Fine Thread observations still use the 100c vendor quote in both cost curves')
        check(findMover(interiorRecipe, 2321).impact == 99 and findMover(interiorWrit, 2321).impact == 99,
            theme .. ' both Fine Thread movers measure 99c from the two interior observations')
        frame = provider.OpenQuickLook(writ, true, nil, { kind = 'writ' })
        threadWidgets = nil
        for i, mover in ipairs(frame.data.movers) do
            if mover.itemID == 2321 then
                if i > #frame.movers and frame.SetMoverScroll then
                    frame.SetMoverScroll(i - #frame.movers)
                end
                threadWidgets = frame.movers[i - (frame.moverOffset or 0)]
                break
            end
        end
        check(threadWidgets and threadWidgets.fixed:IsShown()
            and threadWidgets.impact:GetText():gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '') == '+99c'
            and threadWidgets.coverage:GetText() == '2/7d',
            theme .. ' Fine Thread keeps VENDOR with 2/7d coverage and +99c impact')
        provider.CloseQuickLook()
        interiorThread = nil
        threadToday = nil
        threadHistory = nil
        prices[2321], prices[4305], prices[7048] = 200, 150, 1
        opts.writMode, opts.subCraftOverrides = 'cheapest', { [7048] = 'craft' }
        local function checkChoice(expectedMode, expectedCost, label)
            local live
            for _, candidate in ipairs(ns.BuildWritRows(opts)) do
                if candidate.writID == 264049 then live = candidate; break end
            end
            local look = ns.RecipeStats.BuildWritQuickLook(assert(live), opts, now)
            check(live.mode == expectedMode and look.meta.mode == (expectedMode == 'Buy' and 'Buy AH' or 'Craft')
                and look.cost.values[7] == expectedCost
                and live.grossTotal == live.writPrice + expectedCost,
                theme .. ' Writ 264049 live row, caption and chart agree: ' .. label)
        end
        checkChoice('Craft', 500, 'Craft override beats cheaper 1c AH')
        opts.writMode = 'buy'
        checkChoice('Buy', 1, 'explicit Buy mode precedes Craft override')
        opts.writMode, opts.subCraftOverrides[7048] = 'craft', 'buy'
        checkChoice('Craft', 500, 'explicit Craft mode precedes Buy override')
        opts.writMode, opts.subCraftOverrides[7048], prices[7048] = 'cheapest', 'buy', 900
        checkChoice('Buy', 900, 'Buy override beats cheaper Craft')
        prices[7048] = nil
        checkChoice('Craft', 500, 'missing override buy price falls back to Craft')
        opts.subCraftOverrides[7048], prices[7048], prices[4305] = 'craft', 1, nil
        checkChoice('Buy', 1, 'missing override craft inputs fall back to Buy')
        prices[2321], prices[4305], prices[7048] = 1, 100, 900
    end
    ns.GetItemMarketPrice, ns.MarketScan.GetItemTrend7d = oldMarket, oldTrend
    ns.Theme.SetMode(oldTheme, true)
end

-- Forged Delivery uses the same Quick Look and cart interactions as the other turn-ins.
do
    local db, ui, stats = MerchantMasterDB, app.ui, ns.RecipeStats
    local saved = {}
    for key, value in pairs(db) do saved[key] = value end
    local priorTab, priorShown, priorSearch = app.activeTab, app.panel:IsShown(), ui.searchBox:GetText()
    local priorRows, addItem = app.quickLookRows, app.addQuickLookItem
    local priorRepTab, solveRep = app.lastSubTab.reputation, ns.SolveRepShoppingList
    local economy, now, crateID = 'Normal-Horde', time(), 248683
    local day = math.floor(now / 86400)
    local prices, daily, snapshots = { _scannedAt = now }, {}, {}
    for id, price in pairs({ [crateID] = 400, [248682] = 250, [2447] = 10 }) do
        prices[id], daily[id] = { price = price, qty = 15, at = now }, {}
        for i = 1, 7 do
            daily[id][i] = { d = day - 7 + i, lastP = price + i - 7, lastQ = 22 - i, at = now - (7 - i) * 86400 }
        end
        snapshots[id] = { now - 3600, price - 1, 16, now, price, 15 }
    end
    local labels = { 'COST / REP (SELF-FUNDED)', 'EMPTY CRATE (AH)', '15X FAVOR SOURCING', 'QUEST REFUNDS', 'AH LISTED', 'DEMAND' }
    local view, initRow, priorInlineSearch
    local ok, failure = pcall(function()
        db.economy, db.priceSource, db.crateMode = economy, 'live_ah', 'buy'
        db.ahPrices, db.ahDaily, db.ahSnapshots = { [economy] = prices }, { [economy] = daily }, { [economy] = snapshots }
        db.forgedTurnInQueue, db.shoppingList, db.rewards = {}, {}, {}
        db.forgedMode, db.forgedTierFilter, db.forgedHumanDiplomacy = 'self_funded', 'all', false
        db.quickLookWindow, db.priceDisplayMode = '7d', 'compact'
        app.quickLookRows = {}
        ns.InvalidatePriceCache()

        local function metricValue(metric)
            return metric.liveValue or metric.value
        end
        check(type(stats.BuildForgedQuickLook) == 'function' and type(stats.BuildQuickLook) == 'function',
            'Forged Quick Look has direct and shared builders')
        for _, mode in ipairs({ 'self_funded', 'banked' }) do
            local opts = { economy = economy, forgedMode = mode, humanDiplomacy = false, crateMode = 'buy', window = '7d' }
            local result, row = ns.BuildForgedDeliveryRows(opts), nil
            for _, candidate in ipairs(result.rows) do
                if candidate.crateID == crateID then row = candidate; break end
            end
            check(row and row.available, 'Forged Quick Look uses a priced empty crate')
            local banked = mode == 'banked'
            for _, build in ipairs({ stats.BuildForgedQuickLook, stats.BuildQuickLook }) do
                local model = build(row, opts, now)
                check(model and model.kind == 'forged' and #model.days == 7 and #model.movers > 0
                    and type(model.chartSeries) == 'table' and type(model.sourceInfo) == 'table' and type(model.meta) == 'table'
                    and model.title and model.badge and model.subtitle, mode .. ' has a Quick Look v2 model')
                local metrics = model.overviewRows
                check(model.meta.forgedMode == mode and metricValue(metrics[1]) == (banked and 6 or 18)
                    and metricValue(metrics[2]) == 400 and metricValue(metrics[3]) == (banked and 0 or 600)
                    and metricValue(metrics[4]) == (banked and 100 or 850), mode .. ' shows its cost per rep, crate quote, Favor cost, and refunds')
            end
        end

        ui.searchBox:SetText('')
        priorInlineSearch = ui.forgedSearchBox:GetText()
        ui.forgedSearchBox:SetText('')
        local tableWidget = ui.forgedTable
        view, initRow = tableWidget.scrollBox._view, tableWidget.scrollBox._view._initFn
        -- Hook row FontString creation before app.setTab('forged') renders forgedTable.
        view._initFn = function(frame, data)
            local createFontString = frame.CreateFontString
            frame.CreateFontString = function(self, ...)
                local fs = createFontString(self, ...)
                function fs:SetJustifyH(value) self.justifyH = value end
                return fs
            end
            initRow(frame, data)
            frame.CreateFontString = createFontString
        end
        app.panel:Show()
        app.setTab('forged')
        check(ui.forgedView and ui.forgedView:IsShown() and ui.forgedTable, 'Forged Delivery tab shows its table')
        local function visibleRow()
            for _, frame in ipairs(tableWidget.scrollBox._frames) do
                if frame.data and frame.data.crateID == crateID then return frame end
            end
            error('Forged Delivery table must render the priced Apprentice Ore crate', 2)
        end
        app.refresh()
        local row = visibleRow()
        local nameCell = row.cells[1]
        check(row.data.forged and row:GetScript('OnEnter') == nil, 'Forged rows leave tooltips to the empty crate name')
        for i = 2, #row.cells do
            check(row.cells[i]:GetScript('OnEnter') == nil, 'Forged non-name cell ' .. i .. ' has no tooltip')
        end
        GameTooltip:Hide()
        nameCell:GetScript('OnEnter')(nameCell)
        local forgedTip = plain(table.concat(GameTooltip._lines or {}, '\n'))
        check(GameTooltip:IsShown() and GameTooltip._lines[1] == 'Item:' .. crateID
            and forgedTip:find('Fill Cost', 1, true) ~= nil
            and forgedTip:find('Reputation', 1, true) ~= nil
            and forgedTip:find('Cost / Rep (inc. crate)', 1, true) ~= nil
            and forgedTip:find('Cost / Rep (ex. crate)', 1, true) ~= nil,
            'The empty crate name shows the matching item tooltip and compact crate breakdown on hover')
        nameCell:GetScript('OnLeave')(nameCell)
        check(not GameTooltip:IsShown(), 'Leaving the empty crate name hides its tooltip')

        db.crateTooltips = false
        GameTooltip:Hide()
        nameCell:GetScript('OnEnter')(nameCell)
        check(GameTooltip:IsShown() and #GameTooltip._lines == 1 and GameTooltip._lines[1] == 'Item:' .. crateID,
            'Disabling crateTooltips suppresses crate breakdown on forgedTable name hover')
        nameCell:GetScript('OnLeave')(nameCell)
        check(not GameTooltip:IsShown(), 'Leaving forgedTable name hides tooltip when crateTooltips is false')
        db.crateTooltips = true

        row:Click('LeftButton')
        local hud = provider.GetQuickLookFrame()
        check(hud and hud:IsShown() and hud.data.kind == 'forged' and hud.row.crateID == crateID,
            'Clicking a Forged row opens Quick Look for that empty crate')
        local feederMoverWidget
        for _, mw in ipairs(hud.movers or {}) do
            if mw:IsShown() and mw.spec and mw.spec.itemID == 248682 then
                feederMoverWidget = mw
                break
            end
        end
        check(feederMoverWidget ~= nil, 'Forged Quick Look mover row carries feeder crate itemID 248682')
        GameTooltip:Hide()
        feederMoverWidget:GetScript('OnEnter')(feederMoverWidget)
        local moverCrateTip = plain(table.concat(GameTooltip._lines or {}, '\n'))
        check(GameTooltip:IsShown() and GameTooltip._lines[1] == 'Item:248682'
            and moverCrateTip:find('Fill Cost', 1, true) ~= nil
            and moverCrateTip:find('Cost / Rep', 1, true) ~= nil,
            'Hovering a Quick Look crate mover row shows item tooltip and compact crate breakdown')
        feederMoverWidget:GetScript('OnLeave')(feederMoverWidget)
        check(not GameTooltip:IsShown(), 'Leaving Quick Look mover row hides tooltip cleanly')
        feederMoverWidget:Click('LeftButton')
        check(hud.expandChart:IsShown(), 'Clicking a Quick Look mover row still expands its chart')
        feederMoverWidget:Click('LeftButton')
        check(not hud.expandChart:IsShown(), 'Clicking the Quick Look mover row again collapses its chart')
        for i, label in ipairs(labels) do
            check(hud.overviewRows[i]:IsShown() and plain(hud.overviewRows[i].name:GetText()):upper() == label,
                'Forged Quick Look displays ' .. label)
        end
        local crateMetric = hud.overviewRows[2]
        check(not hud.expandChart:IsShown(), 'Forged Quick Look opens with its chart collapsed')
        crateMetric:Click('LeftButton')
        check(hud.expandChart:IsShown(), 'Clicking the crate price expands its inline chart')
        for _, window in ipairs({ { '24h', hud.win24Btn }, { '7d', hud.win7dBtn } }) do
            window[2]:Click('LeftButton')
            check(db.quickLookWindow == window[1] and hud.data.window == window[1] and hud.expandChart:IsShown(),
                'Forged inline chart switches to ' .. window[1])
        end
        crateMetric:Click('LeftButton')
        check(not hud.expandChart:IsShown(), 'Clicking the same metric collapses the chart')

        local priceKeys = { emptyPrice = true, costPerRep = true, netCost = true, favorCost = true, totalRefund = true }
        for mode, expected in pairs({ compact = '4s 00c', no_copper = '4s', full_fixed = '00g 04s 00c' }) do
            db.priceDisplayMode = mode
            app.refresh()
            provider.RefreshQuickLook()
            row = visibleRow()
            local emptyPriceCell, priceCount = nil, 0
            for i, column in ipairs(tableWidget.columns) do
                if priceKeys[column.key] then
                    local fs = row.cells[i].fs or row.cells[i]
                    check(fs.justifyH == 'RIGHT', 'Forged ' .. column.key .. ' is right aligned in ' .. mode)
                    priceCount = priceCount + 1
                    if column.key == 'emptyPrice' then emptyPriceCell = fs end
                end
            end
            check(priceCount == 5 and emptyPriceCell and plain(emptyPriceCell:GetText()) == expected
                and plain(crateMetric.price:GetText()) == expected,
                'The Forged table and Quick Look format the same crate price in ' .. mode)
            for i = 1, 4 do
                check(hud.overviewRows[i].price.justifyH == 'RIGHT', labels[i] .. ' is right aligned in ' .. mode)
            end
        end
        local function clickAgain(target)
            target.mouseOver = true
            hud:GetScript('OnEvent')(hud, 'GLOBAL_MOUSE_DOWN', 'LeftButton')
            target.mouseOver = nil
            check(hud:IsShown(), 'Mouse-down over the selected crate leaves Quick Look open for its click handler')
            target:Click('LeftButton')
        end
        clickAgain(row)
        check(not hud:IsShown(), 'Clicking the same Forged row again closes Quick Look')
        nameCell = row.cells[1]
        nameCell:Click('LeftButton')
        check(hud:IsShown() and hud.data.kind == 'forged', 'Clicking the empty crate name opens Forged Quick Look')
        clickAgain(nameCell)
        check(not hud:IsShown(), 'Clicking the same empty crate name again closes Quick Look')

        local queuedKind, queuedID
        app.addQuickLookItem = function(kind, selected)
            queuedKind, queuedID = kind, selected.crateID
            return addItem(kind, selected)
        end
        nameCell:Click('LeftButton')
        check(hud.addButton:IsShown() and hud.addButton:GetText() == '+ Add to Cart', 'Forged Quick Look offers Add to Cart')
        hud.addButton:Click('LeftButton')
        local queue = db.forgedTurnInQueue
        check(queuedKind == 'forged' and queuedID == crateID and #queue == 1
            and queue[1].crateID == crateID and queue[1].count == 1,
            'Add to Cart passes the Forged row and queues one turn-in')

        db.forgedMode, db.forgedTierFilter = 'banked', 'Journeyman'
        ui.searchBox:SetText('Apprentice Ore')
        ui.forgedSearchBox:SetText('Apprentice Ore')
        app.refresh()
        ui.forgedResetBtn:Click('LeftButton')
        check(db.forgedMode == 'self_funded' and db.forgedTierFilter == 'all'
            and ui.searchBox:GetText() == '' and ui.forgedSearchBox:GetText() == '',
            'Reset Filters restores Self-Funded mode, all tiers, and an empty search')

        local solvedMode
        ns.SolveRepShoppingList = function(opts)
            solvedMode = opts.repSourceMode
            return solveRep(opts)
        end
        db.calcRepTarget = 5
        app.setTab('calc_rep')
        local source = ui.repSourceSeg
        check(source.frame:IsShown(), 'The Rep Calculator shows its Source Mode control')
        for _, mode in ipairs({ 'forged_only', 'writs_only', 'hybrid' }) do
            source.buttons[mode]:Click('LeftButton')
            check(db.repSourceMode == mode and solvedMode == mode, 'Source Mode passes ' .. mode .. ' to the reputation solver')
        end
    end)
    if view then view._initFn = initRow end
    app.addQuickLookItem, app.quickLookRows = addItem, priorRows
    ns.SolveRepShoppingList = solveRep
    provider.CloseQuickLook()
    GameTooltip:Hide()
    for key in pairs(db) do db[key] = saved[key] end
    for key, value in pairs(saved) do db[key] = value end
    ns.InvalidatePriceCache()
    ui.searchBox:SetText(priorSearch)
    if priorInlineSearch then ui.forgedSearchBox:SetText(priorInlineSearch) end
    app.setTab(priorTab)
    app.lastSubTab.reputation = priorRepTab
    db.activeTab = saved.activeTab
    if app.panel:IsShown() ~= priorShown then app.panel:SetShown(priorShown) end
    if not ok then error(failure, 0) end
end

do
    local ui, db = app.ui, MerchantMasterDB
    local savedChars, savedActive = db.chars, ns.activeChar
    local savedKnown, savedUnlock, savedAll = db.knownRecipesOnly, db.unlockFilter, db.craftableAllChars
    local savedTab = app.activeTab
    local ok, err = pcall(function()
        local bankChar = { name='BankerUI', realm='Forever', faction='Horde', economy=ns.CurrentEconomyInfo().effectiveKey,
            knownSpells={}, knownOutputs={}, knownNames={}, scannedProfs={}, cooldowns={}, cooldownGroups={}, writCooldowns={} }
        local alchChar = { name='AlchUI', realm='Forever', faction='Horde', economy=ns.CurrentEconomyInfo().effectiveKey,
            profs={ alchemy=300 }, knownSpells={ [11449]=true }, knownOutputs={}, knownNames={}, scannedProfs={ alchemy=true },
            cooldowns={}, cooldownGroups={}, writCooldowns={} }
        db.chars = { ['Normal-Horde-Forever-BankerUI']=bankChar, ['Normal-Horde-Forever-AlchUI']=alchChar }
        ns.activeChar = bankChar
        app.setTab('recipes')
        db.knownRecipesOnly, db.unlockFilter, db.craftableAllChars = false, 'all', false
        app.refresh()
        check(ui.charScopeSeg and not ui.charScopeSeg.frame:IsShown(), 'charScopeSeg hides outside Craftable Now')
        ui.scopeSeg:SetActive('known', false)
        check(db.knownRecipesOnly == true and ui.charScopeSeg.frame:IsShown() and not db.craftableAllChars,
            'Selecting Craftable Now shows charScopeSeg defaulting to This Char')
        ui.charScopeSeg:SetActive('all_chars', false)
        check(db.craftableAllChars == true and ui.knownAllCharsCheck:GetChecked(),
            'Selecting All Chars updates SavedVariables and syncs sidebar All Chars checkbox')
        local allCtx = app.buildSuperListContext()
        check(allCtx.craftableAllChars == true and allCtx.statsContext.craftableAllChars == true,
            'SuperList and RecipeStats contexts propagate craftableAllChars=true')
        local countAll, altRow = 0, nil
        for _, entry in ipairs(ns.RecipeStats.GetCatalog()) do
            local r = ns.RecipeStats.Get(entry.recipe, allCtx.statsContext)
            if r.known then
                countAll = countAll + 1
                if not altRow and r.craftAbility and r.craftAbility.knownOnActive == false then
                    altRow = r
                end
            end
        end
        check(altRow ~= nil, 'Found an alt-learned recipe row for cell and tooltip attribution check')
        box._view._initFn(pool[1], altRow)
        check(pool[1].cells[2].fs:GetText() == 'Alt', 'Alt-known recipe displays Alt in SuperList Known cell')
        local altNameCell = pool[1].cellGroup.cellsByKey.name
        altNameCell:GetScript('OnEnter')(altNameCell)
        local altTip = table.concat(GameTooltip._lines or {}, ' ')
        check(altTip:find('Yes (AlchUI)', 1, true) ~= nil, 'Alt-known row tooltip identifies AlchUI in Recipe learned')
        GameTooltip:Hide()
        ui.charScopeSeg:SetActive('current', false)
        local selfCtx = app.buildSuperListContext()
        local countSelf, countProfSelf = 0, 0
        for _, entry in ipairs(ns.RecipeStats.GetCatalog()) do
            local r = ns.RecipeStats.Get(entry.recipe, selfCtx.statsContext)
            if r.known then
                countSelf = countSelf + 1
                if not entry.recipe.anyChar then countProfSelf = countProfSelf + 1 end
            end
        end
        check(countAll > countSelf and countSelf == 14 and countProfSelf == 0,
            string.format('Switching This Char -> All Chars changes SuperList known count (%d -> %d)', countSelf, countAll))
        ui.scopeSeg:SetActive('all', false)
        check(not ui.charScopeSeg.frame:IsShown(), 'Returning to All hides charScopeSeg cleanly')
    end)
    db.chars, ns.activeChar = savedChars, savedActive
    db.knownRecipesOnly, db.unlockFilter, db.craftableAllChars = savedKnown, savedUnlock, savedAll
    if app.invalidateCraftableScope then app.invalidateCraftableScope() end
    app.setTab(savedTab)
    if not ok then error(err, 0) end
end

-- QuickLook non-crate reagent mover hover & OnHide cleanup.
do
    local savedTab, savedShown = app.activeTab, app.panel:IsShown()
    local ok, err = pcall(function()
        app.panel:Show()
        app.setTab('recipes')
        provider.Refresh(context); drain()
        local firstRow = pool[1]
        check(firstRow and firstRow.data, 'Recipes table renders first row for QuickLook mover hover check')
        firstRow:Click('LeftButton')
        local hud = provider.GetQuickLookFrame()
        check(hud and hud:IsShown(), 'Clicking recipe row opens QuickLook')
        local reagentMover
        for _, mw in ipairs(hud.movers or {}) do
            if mw:IsShown() and mw.spec and tonumber(mw.spec.itemID) and mw.spec.itemID > 0
                and not ns.CRATE_BY_ID[mw.spec.itemID] and not ns.SEALED_CRATE_BY_ID[mw.spec.itemID] then
                reagentMover = mw
                break
            end
        end
        check(reagentMover ~= nil, 'Recipe QuickLook exposes a non-crate mover row with itemID')
        GameTooltip:Hide()
        reagentMover:GetScript('OnEnter')(reagentMover)
        local expectedID = tonumber(reagentMover.spec.itemID)
        check(GameTooltip:IsShown() and #GameTooltip._lines == 1 and GameTooltip._lines[1] == 'Item:' .. expectedID,
            'Hovering non-crate QuickLook mover shows item tooltip without crate lines')
        hud:Hide()
        check(not GameTooltip:IsShown(), 'Hiding QuickLook cleans up active mover tooltip')
    end)
    provider.CloseQuickLook()
    GameTooltip:Hide()
    app.setTab(savedTab)
    if app.panel:IsShown() ~= savedShown then app.panel:SetShown(savedShown) end
    if not ok then error(err, 0) end
end

-- Ancestor view hide/show must not leave visible ScrollBox rows with nil data (dead hover/click/stepper).
do
    local savedTab, savedShown = app.activeTab, app.panel:IsShown()
    local savedFullUpdate = box.FullUpdate
    local ok, err = pcall(function()
        app.panel:Show()
        app.setTab('recipes')
        provider.Refresh(context); drain()
        check(pool[1] and pool[1].data and pool[5] and pool[5].data,
            'SuperList renders rows 1 and 5 before ancestor hide')
        -- Simulate real WoW: hiding recipesView fires OnHide on visible child rows while r:IsShown() stays true.
        local recipesView = app.ui.recipesView
        recipesView:Hide()
        for i = 1, #pool do
            if pool[i]:IsShown() then
                local onHide = pool[i]:GetScript('OnHide')
                if onHide then onHide(pool[i]) end
            end
        end
        check(pool[5].data ~= nil and pool[5].cellGroup.data ~= nil,
            'Ancestor view hide keeps active row data intact when row itself remains shown')
        -- Simulate real WoW ScrollBox where FullUpdate() does NOT re-invoke ElementInitializer on acquired frames.
        box.FullUpdate = function() end
        recipesView:Show()
        -- Even before any async refresh completes, row 5 must immediately support hover, click QuickLook, and Shift stepper.
        GameTooltip:Hide()
        local nameCell = pool[5].cellGroup.cellsByKey.name
        nameCell:GetScript('OnEnter')(nameCell)
        check(GameTooltip:IsShown(), 'Row 5 hover tooltip works immediately after view re-show')
        GameTooltip:Hide()
        pool[5]:Click('LeftButton')
        local hud = provider.GetQuickLookFrame()
        check(hud and hud:IsShown(), 'Row 5 left-click opens QuickLook immediately after view re-show')
        provider.CloseQuickLook()
        provider.SetShiftMode(true)
        check(pool[5].shiftStepper and pool[5].shiftStepper:IsShown(),
            'Row 5 Shift Quick-Add stepper shows immediately after view re-show')
        provider.SetShiftMode(false)
        -- Belt-and-suspenders: if a shown row somehow loses r.data, OnShow rebinds via GetElementData even when FullUpdate is a no-op.
        local expectedRow5 = pool[5].data
        pool[5].GetElementData = function() return expectedRow5 end
        pool[5].data = nil
        pool[5].cellGroup.data = nil
        recipesView:Hide()
        recipesView:Show()
        check(pool[5].data == expectedRow5 and pool[5].cellGroup.data == expectedRow5,
            'OnShow rebinds stale shown row via GetElementData even when FullUpdate is a no-op')
        pool[5].GetElementData = nil
    end)
    box.FullUpdate = savedFullUpdate
    provider.SetShiftMode(false)
    provider.CloseQuickLook()
    GameTooltip:Hide()
    app.setTab(savedTab)
    if app.panel:IsShown() ~= savedShown then app.panel:SetShown(savedShown) end
    if not ok then error(err, 0) end
end

-- Regression: 20-col tail reorder (float colSum collision) aligns All Recipes headers & cells without adding/removing a column.
do
    local savedTab, savedShown = app.activeTab, app.panel:IsShown()
    local savedCols = context.db.superListColumns
    local origBoxW = box.GetWidth
    local origHdrW = tbl.headerBar.GetWidth
    local origParentW = app.ui.mainArea and app.ui.mainArea.GetWidth
    local ok, err = pcall(function()
        box.GetWidth = function() return 1800 end
        tbl.headerBar.GetWidth = function() return 1800 end
        if app.ui.mainArea then app.ui.mainArea.GetWidth = function() return 1824 end end
        app.panel:Show()
        app.setTab('recipes')
        provider.ResetColumns()
        provider.Refresh(context); drain()
        context.db.superListColumns = {
            order = {
                'name','knownSort','cdSort','ownedOutputQty','listed','goodScore','buyCostCopper','craftCost',
                'unitAH','salesPerDay','turnoverPerDay','demandSort','profit','requiredSkill',
                'sourceLabel','sourceCost','repSort','bisSort','wowheadURL','skillupSort',
            },
            hidden = {},
        }
        provider.Refresh(context); drain()
        check(#tbl.columns == 20 and tbl.columns[20].key == 'skillupSort',
            'Saved 20-col reorder moves skillupSort to column 20 cleanly')
        check(tbl.columns[1].width > 128,
            'Reordered 20-col SuperList expands Name column rather than stalling on colSum collision')
        for i = 1, #tbl.columns do
            local hb = tbl.headerBtns[i]
            local _, _, _, hx = hb:GetPoint(1)
            check(hx == tbl.colX[i] and hb:GetWidth() == tbl.columns[i].width,
                'SuperList header ' .. i .. ' aligns with colX and width after reorder')
        end
        local checkedRow = false
        for _, r in ipairs(pool) do
            if r:IsShown() and r.cells then
                checkedRow = true
                for i = 1, #tbl.columns do
                    local cell = r.cells[i]
                    local _, _, _, cx = cell:GetPoint(1)
                    check(cx == tbl.colX[i] and cell:GetWidth() == tbl.columns[i].width,
                        'SuperList cell ' .. i .. ' aligns with header without toggling columns')
                end
            end
        end
        check(checkedRow, 'At least one visible SuperList row checked for header/cell alignment')
    end)
    box.GetWidth = origBoxW
    tbl.headerBar.GetWidth = origHdrW
    if app.ui.mainArea then app.ui.mainArea.GetWidth = origParentW end
    context.db.superListColumns = savedCols
    provider.ResetColumns()
    provider.Refresh(context); drain()
    app.setTab(savedTab)
    if app.panel:IsShown() ~= savedShown then app.panel:SetShown(savedShown) end
    if not ok then error(err, 0) end
end

-- Regression (Bug 1): redundant Refresh mid-present does not abort FilterSort, warm filter miss updates summary immediately, and away-tab changes refresh cleanly on return.
do
    local savedTab, savedShown = app.activeTab, app.panel:IsShown()
    local savedProf = MerchantMasterDB.profFilter
    local savedKnown = MerchantMasterDB.knownRecipesOnly
    local savedUnlock = MerchantMasterDB.unlockFilter
    local savedSearch = app.ui.searchBox and app.ui.searchBox:GetText() or ''
    local savedAfter = C_Timer.After
    local savedProfile = debugprofilestop
    local savedFilterSort = ns.SuperListModel.FilterSort
    local regSorts, fakeClock = 0, 0
    local function drainReg()
        local count = 0
        while #queued > 0 do
            table.remove(queued, 1)()
            count = count + 1
            assert(count < 10000, 'no runaway jobs in Bug 1 regression')
        end
        return count
    end
    C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
    debugprofilestop = function() return fakeClock end
    ns.SuperListModel.FilterSort = function(...)
        regSorts = regSorts + 1
        fakeClock = fakeClock + 0.6
        return savedFilterSort(...)
    end
    local ok, err = pcall(function()
        MerchantMasterDB.profFilter = 'all'
        MerchantMasterDB.knownRecipesOnly = false
        MerchantMasterDB.unlockFilter = 'all'
        app.panel:Show()
        app.setTab('recipes')
        if app.ui.searchBox then app.ui.searchBox:SetText('') end
        drainReg()
        check(box._dp and #box._dp:GetCollection() == TOTAL_RECIPES, 'All Recipes baseline starts with full catalog')

        -- Search 'green lens' -> switch to dashboard -> clear search -> return to recipes:
        -- warm filter cache miss updates summary immediately and redundant app.refresh() mid-present does not abort FilterSort.
        app.ui.searchBox._text = 'green lens'
        app.ui.searchBox:GetScript('OnTextChanged')(app.ui.searchBox, false)
        drainReg()
        check(box._dp and #box._dp:GetCollection() == 1, 'Search narrows All Recipes to 1 row before navigation')

        app.setTab('dashboard')
        drainReg()
        app.ui.searchBox._mmClearBtn:GetScript('OnClick')(app.ui.searchBox._mmClearBtn)
        drainReg()
        local sortsBefore = regSorts
        app.setTab('recipes')
        check(regSorts == sortsBefore and box._dp and #box._dp:GetCollection() == TOTAL_RECIPES,
            'Returning to previously-visited empty search hits 8-entry LRU cache synchronously with 0 FilterSort calls')

        -- Switch to dashboard and apply a never-visited filter (true LRU miss) to test immediate feedback + redundant Refresh mid-present.
        app.setTab('dashboard')
        drainReg()
        app.ui.searchBox._text = 'potion'
        app.ui.searchBox:GetScript('OnTextChanged')(app.ui.searchBox, false)
        drainReg()
        local sortsMissBefore = regSorts
        app.setTab('recipes')
        check(app.ui.recipesView.summary:GetText() == 'Filtering recipes...',
            'Warm filter cache miss on return sets immediate Filtering recipes... feedback: got=' .. tostring(app.ui.recipesView.summary:GetText()))

        -- Run kickoff until FilterSort starts (while still mid-present), then fire a redundant app.refresh()
        local stepGuard = 0
        while #queued > 0 and regSorts == sortsMissBefore and stepGuard < 200 do
            stepGuard = stepGuard + 1
            table.remove(queued, 1)()
        end
        local sortsMid = regSorts
        local expectedBlocks = math.ceil(TOTAL_RECIPES / 96)
        check(sortsMid > sortsMissBefore and sortsMid < sortsMissBefore + expectedBlocks and #queued > 0,
            'present() FilterSort is actively mid-flight before redundant Refresh (mid=' .. tostring(sortsMid - sortsMissBefore) .. ', q=' .. tostring(#queued) .. ')')
        app.refresh()
        drainReg()
        local sortsUsed = regSorts - sortsMissBefore
        check(sortsUsed <= expectedBlocks + 2,
            'Redundant Refresh mid-present does not abort/restart FilterSort (blocks=' .. tostring(sortsUsed) .. ', expected<=' .. tostring(expectedBlocks + 2) .. ')')
        check(box._dp and #box._dp:GetCollection() > 0 and #box._dp:GetCollection() < TOTAL_RECIPES, 'All Recipes finishes with filtered potion rows after redundant Refresh')
        app.ui.searchBox._mmClearBtn:GetScript('OnClick')(app.ui.searchBox._mmClearBtn)
        drainReg()
        check(box._dp and #box._dp:GetCollection() == TOTAL_RECIPES, 'All Recipes restores full catalog cleanly after clearing search')

        -- Away-tab sibling triggers: ownership (metaDirty), profFilter, knownRecipesOnly
        app.setTab('dashboard'); drainReg()
        app.invalidateRecipeStats('ownership')
        MerchantMasterDB.profFilter = 'alchemy'
        app.setTab('recipes'); drainReg()
        local alchRows = box._dp and box._dp:GetCollection() or {}
        check(#alchRows > 0 and #alchRows < TOTAL_RECIPES, 'Away-tab ownership + profFilter change updates All Recipes cleanly on return')
        for _, r in ipairs(alchRows) do
            check(r.prof == 'alchemy', 'Returned rows reflect away-tab profFilter=alchemy')
        end

        app.setTab('dashboard'); drainReg()
        MerchantMasterDB.profFilter = 'all'
        app.invalidateRecipeStats('items', { [10504] = true })
        app.setTab('recipes'); drainReg()
        check(box._dp and #box._dp:GetCollection() == TOTAL_RECIPES, 'Away-tab items invalidation + filter clear updates All Recipes cleanly on return')
    end)
    MerchantMasterDB.profFilter = savedProf
    MerchantMasterDB.knownRecipesOnly = savedKnown
    MerchantMasterDB.unlockFilter = savedUnlock
    if app.ui.searchBox then app.ui.searchBox:SetText(savedSearch) end
    app.setTab(savedTab)
    if app.panel:IsShown() ~= savedShown then app.panel:SetShown(savedShown) end
    drainReg()
    ns.SuperListModel.FilterSort = savedFilterSort
    debugprofilestop = savedProfile
    C_Timer.After = savedAfter
    if not ok then error(err, 0) end
end

-- Regression: All Recipes Y/G/Gr skill-up column renders numeric thresholds (not n/a) and tooltip exposes Skill-Up (Y / G / Gr).
do
    local savedTab, savedShown = app.activeTab, app.panel:IsShown()
    local savedProf = MerchantMasterDB.profFilter
    local savedSearch = app.ui.searchBox and app.ui.searchBox:GetText() or ''
    local savedCols = context.db.superListColumns
    local skillupColIdx
    for idx, col in ipairs(tbl.columns or {}) do
        if col.key == 'skillupSort' then skillupColIdx = idx; break end
    end
    check(skillupColIdx ~= nil, 'skillupSort (Y/G/Gr) column exists in All Recipes')
    MerchantMasterDB.profFilter = 'engineering'
    if app.ui.searchBox then app.ui.searchBox:SetText('Green Lens') end
    app.panel:Show(); app.setTab('recipes'); drain()
    local foundTarget, formattedCell, foundTip
    for _, r in ipairs(pool) do
        if r:IsShown() and r.data and r.data.name == 'Green Lens' then
            foundTarget = r
            local sc = (r.cellGroup and r.cellGroup.cellsByKey and r.cellGroup.cellsByKey.skillupSort) or (r.cells and r.cells[skillupColIdx])
            formattedCell = sc and ((sc.fs and sc.fs:GetText()) or (sc.GetText and sc:GetText()))
            local nc = (r.cellGroup and r.cellGroup.cellsByKey and r.cellGroup.cellsByKey.name) or (r.cells and r.cells[1])
            if nc and nc.GetScript and nc:GetScript('OnEnter') then
                nc:GetScript('OnEnter')(nc)
                for _, line in ipairs(GameTooltip._lines or {}) do
                    local txt = type(line) == 'table' and line.left or line
                    if tostring(txt or ''):find('Skill%-Up %(Y / G / Gr%)') then
                        foundTip = type(line) == 'table' and line.right or txt
                    end
                end
            end
            break
        end
    end
    check(foundTarget ~= nil, 'Green Lens row rendered in All Recipes')
    check(type(foundTarget.data.skillYellow) == 'number' and type(foundTarget.data.skillGreen) == 'number' and type(foundTarget.data.skillGray) == 'number',
        'Green Lens row carries numeric skillYellow/skillGreen/skillGray')
    local plainCell = tostring(formattedCell or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
    check(plainCell ~= '' and plainCell ~= 'n/a' and plainCell:match('^%d+/%d+/%d+$') ~= nil,
        'Y/G/Gr cell renders numeric Y/G/Gr instead of n/a (got=' .. tostring(plainCell) .. ')')
    check(type(foundTip) == 'string' and foundTip:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):match('%d+%s*/%s*%d+%s*/%s*%d+') ~= nil,
        'Row tooltip displays Skill-Up (Y / G / Gr) thresholds')
    MerchantMasterDB.profFilter = savedProf
    if app.ui.searchBox then app.ui.searchBox:SetText(savedSearch) end
    context.db.superListColumns = savedCols
    app.setTab(savedTab)
    if app.panel:IsShown() ~= savedShown then app.panel:SetShown(savedShown) end
    drain()
end

print(string.format('WP6 MEASURE cold_ms=%.3f callback_max_ms=%.3f warm_ms=%.3f pool=%d rows=%d',cold,maxCallback,warm,#pool,#all))
print('WP6 UI: '..n..' assertions, 0 failures')
