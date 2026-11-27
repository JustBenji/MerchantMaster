-- End-to-End UI Suite for Unified Deep Analysis + Concept B/C Time-of-Day Heatmaps
-- Covers Super List inline 24h heat strip + compact 7x24 popover, Quick Look "Deep Analysis >"
-- across recipe/dashboard/writs/crates/forged, full Deep Analysis sections, reagent drill-down
-- stack + < Return restoration, non-persistence of activeTab, and Dark/Light + 5 Warcraft skins.
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local ns, createdFrames, hostEnv = dofile(testsDir .. "host_fixture.lua")

local assertions = 0
local function check(ok, msg)
    assertions = assertions + 1
    if not ok then
        error("DEEP ANALYSIS E2E FAIL [" .. assertions .. "]: " .. tostring(msg), 2)
    end
end

local function plain(s)
    return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end
local function btnText(btn)
    if not btn then return "" end
    local direct = btn.GetText and btn:GetText() or ""
    if direct ~= "" then return plain(direct) end
    local fs = btn.fs or btn.text
    if fs and fs.GetText then
        local t = fs:GetText()
        if t and t ~= "" then return plain(t) end
    end
    return ""
end

local app = assert(ns.app, "ns.app must exist")
local provider = assert(ns.SuperList, "ns.SuperList must exist")
local Theme = assert(ns.Theme, "ns.Theme must exist")
local DA = assert(ns.DeepAnalysis, "ns.DeepAnalysis must exist")
local db = assert(MerchantMasterDB, "MerchantMasterDB must exist")

-- 0. Startup lazy-build & public API invariants
check(DA.GetState and DA.GetState().built == false, "Deep Analysis screen must be lazy-built (0ms startup)")
check(type(app.openDeepAnalysis) == "function", "app.openDeepAnalysis must be defined")
check(type(app.returnFromDeepAnalysis) == "function", "app.returnFromDeepAnalysis must be defined")
check(type(MerchantMasterAPI.OpenDeepAnalysis) == "function", "MerchantMasterAPI.OpenDeepAnalysis must be exported")
check(type(MerchantMasterAPI.ReturnFromDeepAnalysis) == "function", "MerchantMasterAPI.ReturnFromDeepAnalysis must be exported")
check(type(provider.CloseHeatPopover) == "function" and type(ns.CloseSuperListHeatPopover) == "function",
    "Super List must expose CloseHeatPopover and ns.CloseSuperListHeatPopover")

-- Seed realistic market, daily history, ledger, and 7x24 snapshot data for Flask of Supreme Power (13512) + Black Lotus (13468)
local nowTs = 1795300000
local origTime = _G.time
_G.time = function() return nowTs end

local econ = ns.CurrentEconomyInfo().effectiveKey
local day = math.floor(nowTs / 86400)
db.ahPrices = db.ahPrices or {}
db.ahPrices[econ] = db.ahPrices[econ] or {}
db.ahDaily = db.ahDaily or {}
db.ahDaily[econ] = db.ahDaily[econ] or {}

local seedPrices = {
    [13512] = { 610000, 622000, 618000, 640000, 652000, 672000, 685000 }, -- Flask of Supreme Power
    [13468] = { 320000, 326000, 330000, 344000, 355000, 370000, 382000 }, -- Black Lotus
    [13463] = { 4600, 4550, 4500, 4420, 4380, 4280, 4200 },               -- Dreamfoil
    [13465] = { 7300, 7400, 7450, 7550, 7600, 7700, 7800 },               -- Mountain Silversage
    [13521] = { 1450000, 1410000, 1380000, 1340000, 1300000, 1260000, 1220000 }, -- Recipe: Flask of Supreme Power
    [8925]  = { 500, 500, 500, 500, 500, 500, 500 },                      -- Crystal Vial
}
for id, series in pairs(seedPrices) do
    local buckets = {}
    for i = 1, 7 do
        buckets[i] = { d = day - 7 + i, lastP = series[i], lastQ = 24 - i, at = nowTs - (7 - i) * 86400 }
    end
    db.ahDaily[econ][id] = buckets
    db.ahPrices[econ][id] = { price = series[7], qty = 17, at = nowTs - 120 }
end

local B32 = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
local function encB32(num)
    num = math.floor(tonumber(num) or 0)
    if num <= 0 then return "0" end
    local d = {}
    while num > 0 do
        local rem = num % 32
        d[#d + 1] = string.sub(B32, rem + 1, rem + 1)
        num = math.floor(num / 32)
    end
    local out = {}
    for i = #d, 1, -1 do out[#out + 1] = d[i] end
    return table.concat(out)
end

local function makeHeatPayloads(itemID, basePrice)
    local h24 = {}
    local cells = {}
    for dow = 1, 7 do
        for hr = 0, 23 do
            local mult = (hr <= 5 and 0.78) or (hr <= 11 and 0.92) or (hr <= 16 and 1.00) or (hr <= 20 and 1.18) or 1.35
            if dow >= 6 then mult = mult * 1.04 end
            local avgP = math.floor(basePrice * mult + 0.5)
            local minP = math.floor(avgP * 0.91 + 0.5)
            local qty = (hr <= 5) and 42 or ((hr >= 18) and 8 or 22)
            local slot = (dow - 1) * 24 + hr
            cells[#cells + 1] = tostring(slot) .. "=" .. encB32(avgP) .. "," .. encB32(minP) .. "," .. encB32(qty) .. ",4"
            if dow == 1 then h24[hr + 1] = encB32(avgP) end
        end
    end
    local bbSlot = 3 -- Mon 03:00
    local bsSlot = 6 * 24 + 21 -- Sun 21:00
    local bbP = math.floor(basePrice * 0.78 + 0.5)
    local bsP = math.floor(basePrice * 1.35 * 1.04 + 0.5)
    local latest = string.format("%d:%s,%s,%s,%s,%s,%s",
        itemID, encB32(math.floor(basePrice * 0.93 + 0.5)), encB32(basePrice), encB32(basePrice),
        encB32(17), encB32(nowTs - 600), encB32(basePrice))
    local heat24 = string.format("%d:%s,%s,%s,%s,%s,%d,%s,%d,%s|%s",
        itemID, encB32(basePrice), encB32(basePrice), encB32(22), encB32(15), encB32(672),
        bbSlot, encB32(bbP), bsSlot, encB32(bsP), table.concat(h24, ","))
    local heat7x24 = tostring(itemID) .. ":" .. table.concat(cells, "|")
    return latest, heat24, heat7x24
end

ns.snapshotRaw = {}
ns.snapshotParsed = {}
ns.snapshotHeatmapCache = {}
local l1, h1, m1 = makeHeatPayloads(13512, 685000)
local l2, h2, m2 = makeHeatPayloads(13468, 382000)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", econ,
    string.format([[return {v=1,updatedAt=%d,source="tsm_csv",windowDays=30,itemCount=2,heatmapCount=2,velocityCount=1,regSaleCount=1,velocityObsHours=24}]], nowTs - 600))
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", econ, l1 .. ";" .. l2)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT24", econ, h1 .. ";" .. h2)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT7X24", econ, m1 .. ";" .. m2)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("VELOCITY", econ,
    "13512:" .. encB32(3500) .. "," .. encB32(24) .. "," .. encB32(3) .. "," .. encB32(25))
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("REGSALE", econ,
    "13512:" .. encB32(685000) .. "," .. encB32(12000) .. "," .. encB32(450))
ns.InvalidatePriceCache()

check(ns.Pricing.GetItemHeatStrip24h(13512) ~= nil, "Flask 24h heat strip must load from snapshot")
check(ns.Pricing.GetItemHeatmap(13512) ~= nil, "Flask 7x24 heatmap must load from snapshot")
check(ns.Pricing.GetItemHeatStrip24h(13468) ~= nil, "Black Lotus 24h heat strip must load from snapshot")

-- Timer drain helper for Super List async presentation
local queued = {}
local origAfter = C_Timer.After
C_Timer.After = function(_, fn)
    if type(fn) == "function" then queued[#queued + 1] = fn end
end
local function drain()
    local n = 0
    while #queued > 0 do
        local fn = table.remove(queued, 1)
        fn()
        n = n + 1
        assert(n < 15000, "timer drain exceeded limit")
    end
end

-- Set up bounded scrollbox pool for Super List
local tbl = assert(app.ui.recipesTable, "recipesTable must exist")
local box = tbl.scrollBox
local pool, capacity = {}, 18
box._frames = pool
box.GetHeight = function() return capacity * app.ui.ROW_H end
local scrollPctValue = 0.25
function box:GetScrollPercentage() return scrollPctValue end
function box:SetScrollPercentage(v) scrollPctValue = v end
local function renderBox()
    if not box._dp then return end
    local items = box._dp:GetCollection()
    for i = 1, math.min(capacity, #items) do
        local r = pool[i]
        if not r then
            r = CreateFrame("Button", nil, box)
            pool[i] = r
        end
        r:Show()
        box._view._initFn(r, items[i])
    end
    for i = math.min(capacity, #items) + 1, #pool do pool[i]:Hide() end
    box._frames = pool
end
function box:SetDataProvider(dp) self._dp = dp; renderBox() end
function box:FullUpdate() renderBox() end

-- 1. Super List Concept C: inline 24h heat strip, hover tooltip, Left-Click compact popover, Right-Click Deep Analysis
app.panel:Show()
app.setTab("recipes")
app.ui.searchBox:SetText("Flask of Supreme Power")
app.refresh()
drain()

local flaskFrame, flaskRow
for _, rf in ipairs(pool) do
    if rf:IsShown() and rf.data and rf.data.outputItemID == 13512 then
        flaskFrame = rf
        flaskRow = rf.data
        break
    end
end
check(flaskFrame ~= nil and flaskRow ~= nil, "Flask of Supreme Power must render in Super List")

local heatCell = flaskFrame.cellGroup and flaskFrame.cellGroup.cellsByKey and flaskFrame.cellGroup.cellsByKey.demandSort
check(heatCell ~= nil, "Heat (demandSort) cell must exist")
check(heatCell.heatStrip ~= nil and heatCell._heatStripBound == true, "Flask Heat cell must bind inline 24h heatStrip")
check(heatCell.heatStrip.frame:IsShown(), "Flask inline 24h heatStrip frame must be shown")
local segsShown = 0
for h = 0, 23 do
    if heatCell.heatStrip.segments[h] and heatCell.heatStrip.segments[h]:IsShown() then
        segsShown = segsShown + 1
    end
end
check(segsShown == 24, "Inline 24h heat strip must display all 24 pooled segments, got " .. segsShown)
check(heatCell.heatStrip.nowTick:IsShown(), "Inline 24h heat strip must display nowTick")
check(heatCell._fsOffsetY == 2, "Heat cell label must shift +2px upward when strip is bound")

-- Verify a non-snapshot recipe leaves heat strip hidden (baseline preserved)
app.ui.searchBox:SetText("Minor Healing Potion")
app.refresh()
drain()
local plainFrame
for _, rf in ipairs(pool) do
    if rf:IsShown() and rf.data and rf.data.outputItemID ~= 13512 and rf.data.outputItemID ~= 13468 then
        plainFrame = rf
        break
    end
end
check(plainFrame ~= nil, "Non-snapshot recipe row must render")
local plainHeatCell = plainFrame.cellGroup.cellsByKey.demandSort
check(plainHeatCell._heatStripBound == false and not plainHeatCell.heatStrip.frame:IsShown(),
    "Row without snapshot data must keep heatStrip cleared and hidden")
check(plainHeatCell:GetScript("OnEnter") == nil,
    "Row without snapshot heat strip must detach demandSort OnEnter tooltip handler (host_suite:934 contract)")

-- Switch back to Flask row for hover + popover + Right-Click tests
app.ui.searchBox:SetText("Flask of Supreme Power")
app.refresh()
drain()
flaskFrame, flaskRow = nil, nil
for _, rf in ipairs(pool) do
    if rf:IsShown() and rf.data and rf.data.outputItemID == 13512 then
        flaskFrame, flaskRow = rf, rf.data
        break
    end
end
check(flaskFrame ~= nil, "Flask row must re-appear")
heatCell = flaskFrame.cellGroup.cellsByKey.demandSort

-- Hover on Heat cell: dark GameTooltip, zero GetItemHeatmap decode
local heatmapDecodes = 0
local origGetHeatmap = ns.Pricing.GetItemHeatmap
ns.Pricing.GetItemHeatmap = function(...)
    heatmapDecodes = heatmapDecodes + 1
    return origGetHeatmap(...)
end
local onEnter = heatCell:GetScript("OnEnter")
check(type(onEnter) == "function", "Heat cell must have OnEnter script")
onEnter(heatCell)
check(heatmapDecodes == 0, "Heat cell OnEnter must use O(1) strip without decoding GetItemHeatmap")
check(GameTooltip:IsShown(), "Heat cell OnEnter must show GameTooltip")
local tipJoined = table.concat(GameTooltip._lines or {}, "\n")
check(tipJoined:find("Best Buy", 1, true) ~= nil, "Heat cell tooltip must show Best Buy")
check(tipJoined:find("Best Sell", 1, true) ~= nil, "Heat cell tooltip must show Best Sell")
check(tipJoined:find("Click: 7x24 heatmap | Right-Click: Deep Analysis", 1, true) ~= nil,
    "Heat cell tooltip must show click/right-click hint")
local onLeave = heatCell:GetScript("OnLeave")
if onLeave then onLeave(heatCell) end
check(not GameTooltip:IsShown(), "Heat cell OnLeave must hide GameTooltip")
ns.Pricing.GetItemHeatmap = origGetHeatmap

-- Left-Click on Heat cell opens single shared compact 7x24 popover
heatCell:Click("LeftButton")
local pop = provider.GetHeatPopover()
check(pop ~= nil and pop:IsShown(), "Left-Click on Heat cell must open view.heatPopover")
check(pop == app.ui.recipesView.heatPopover, "provider.GetHeatPopover must match view.heatPopover")
check(pop.drawer ~= nil and pop.drawer._compact == true and pop.drawer._showCurve == false,
    "Super List heatPopover drawer must be compact without 24h curve")
check(pop.drawer.deepAnalysisBtn ~= nil and pop.drawer.deepAnalysisBtn:IsShown(),
    "Compact heatPopover must expose 'Deep Analysis >' button")
check(pop.drawer.closeBtn ~= nil and pop.drawer.closeBtn:IsShown(),
    "Compact heatPopover must expose Close button")
check(pop.drawer.cells[1][0] ~= nil and pop.drawer.cells[7][23] ~= nil,
    "Compact heatPopover must contain 168 pooled cells")

-- Clicking same Heat cell toggles popover closed
heatCell:Click("LeftButton")
check(not pop:IsShown(), "Second Left-Click on same Heat cell must toggle heatPopover closed")

-- Re-open and press ESCAPE to dismiss
heatCell:Click("LeftButton")
check(pop:IsShown(), "Heat popover must re-open cleanly")
local popKeyDown = pop:GetScript("OnKeyDown")
check(type(popKeyDown) == "function", "Heat popover must support Escape OnKeyDown")
popKeyDown(pop, "ESCAPE")
check(not pop:IsShown(), "Pressing ESCAPE must close heatPopover")

-- Round 2 regression: hiding or recycling the owning row must close heatPopover so it never orphans
heatCell:Click("LeftButton")
check(pop:IsShown(), "Heat popover must open before row-hide test")
flaskFrame:Hide()
check(not pop:IsShown(), "Hiding the owning Super List row must close heatPopover")
flaskFrame:Show()
app.refresh()
drain()
flaskFrame = nil
for _, rf in ipairs(pool) do
    if rf:IsShown() and rf.data and rf.data.outputItemID == 13512 then
        flaskFrame = rf
        break
    end
end
check(flaskFrame ~= nil, "Flask row must rebind after refresh")
heatCell = flaskFrame.cellGroup.cellsByKey.demandSort
heatCell:Click("LeftButton")
check(pop:IsShown(), "Heat popover must open before row-recycle test")
-- Filter to another recipe so the pooled row frame rebinds to different data
app.ui.searchBox:SetText("Minor Healing Potion")
app.refresh()
drain()
check(not pop:IsShown(), "Recycling the owning Super List row onto different data must close heatPopover")
-- Restore Flask row for subsequent tests
app.ui.searchBox:SetText("Flask of Supreme Power")
app.refresh()
drain()
flaskFrame, flaskRow = nil, nil
for _, rf in ipairs(pool) do
    if rf:IsShown() and rf.data and rf.data.outputItemID == 13512 then
        flaskFrame, flaskRow = rf, rf.data
        break
    end
end
check(flaskFrame ~= nil, "Flask row must return after recycle test")
heatCell = flaskFrame.cellGroup.cellsByKey.demandSort

-- Re-open and click popover's "Deep Analysis >" button
heatCell:Click("LeftButton")
check(pop:IsShown(), "Heat popover must open before Deep Analysis jump")
pop.drawer.deepAnalysisBtn:Click("LeftButton")
drain()
check(not pop:IsShown(), "Jumping to Deep Analysis from popover must close heatPopover")
check(app.activeTab == "deep_analysis", "Popover 'Deep Analysis >' must navigate to deep_analysis tab")
check(DA.GetState().built == true, "Deep Analysis must be lazily built on first open")
check(app.ui.deepAnalysisView:IsShown(), "deepAnalysisView must be shown")
check(db.activeTab ~= "deep_analysis", "MerchantMasterDB.activeTab must NEVER persist 'deep_analysis'")

-- Return from Deep Analysis back to Super List
DA.header.returnBtn:Click("LeftButton")
drain()
check(app.activeTab == "recipes", "< Return from popover jump must restore recipes tab")
check(not app.ui.deepAnalysisView:IsShown(), "deepAnalysisView must hide on return")

-- Right-Click on Heat cell jumps directly to Deep Analysis
heatCell:Click("RightButton")
drain()
check(app.activeTab == "deep_analysis", "Right-Click on Heat cell must open Deep Analysis directly")
check(DA.GetState().target and DA.GetState().target.itemID == 13512, "Right-Click Deep Analysis target must be Flask 13512")
app.returnFromDeepAnalysis()
drain()
check(app.activeTab == "recipes", "Return after Right-Click must restore recipes tab")

-- 2. Quick Look "Deep Analysis >" button from Super List + Full Screen Sections + Reagent Drill-Down Stack
local nameCell = flaskFrame.cellGroup.cellsByKey.name
-- Verify Super List row tooltip surfaces unified Realm Est + Blizzard Realm velocity
GameTooltip:ClearLines()
local nameOnEnter = nameCell:GetScript("OnEnter")
check(type(nameOnEnter) == "function", "Name cell must have OnEnter tooltip handler")
nameOnEnter(nameCell)
local nameTipJoined = table.concat(GameTooltip._lines or {}, "\n")
check(nameTipJoined:find("Realm Est (", 1, true) ~= nil, "Super List row tooltip must display unified Realm Est")
check(nameTipJoined:find("Blizzard Realm:", 1, true) ~= nil, "Super List row tooltip must display Blizzard Realm velocity")
GameTooltip:Hide()
nameCell:Click("LeftButton")
drain()
local hud = assert(provider.GetQuickLookFrame(), "Quick Look HUD must exist")
check(hud:IsShown(), "Clicking Flask name cell must open Quick Look")
check(hud.addButton._points[1][4] == 0 and hud.addButton:GetWidth() == 132,
    "Quick Look addButton must stay at x=0, w=132")
check(hud.searchButton._points[1][4] == 535 and hud.searchButton:GetWidth() == 89,
    "Quick Look searchButton must stay at x=535, w=89")
check(hud.deepAnalysisButton ~= nil, "Quick Look must expose hud.deepAnalysisButton")
check(hud.deepAnalysisButton._points[1][4] == 389 and hud.deepAnalysisButton:GetWidth() == 138
    and hud.deepAnalysisButton:GetHeight() == 29,
    "Quick Look deepAnalysisButton must sit at x=389, w=138, h=29")
check(btnText(hud.deepAnalysisButton) == "Deep Analysis >",
    "Quick Look deepAnalysisButton label must be ASCII 'Deep Analysis >', got: " .. btnText(hud.deepAnalysisButton))

scrollPctValue = 0.42
hud.deepAnalysisButton:Click("LeftButton")
drain()
check(not hud:IsShown(), "Opening Deep Analysis from Quick Look must close Quick Look HUD")
check(app.activeTab == "deep_analysis", "Quick Look 'Deep Analysis >' must switch to deep_analysis")
check(db.activeTab ~= "deep_analysis", "db.activeTab must never be 'deep_analysis'")

-- Verify ALL Deep Analysis sections
check(DA.header ~= nil and DA.header:IsShown(), "Sticky header must be shown")
check(btnText(DA.header.returnBtn):find("< Back to Super List", 1, true) ~= nil,
    "Header return button must show '< Back to Super List', got: " .. btnText(DA.header.returnBtn))
check(plain(DA.header.titleFs:GetText()):find("Flask of Supreme Power", 1, true) ~= nil,
    "Header title must display Flask of Supreme Power")
check(plain(DA.header.subtitleFs:GetText()) ~= "", "Header subtitle must be populated")
check(DA.header.addBtn:IsShown() and DA.header.searchBtn:IsShown(), "Header Add and Search AH buttons must be shown")

-- Row 1: 5 KPI Cards
check(DA.kpiCards ~= nil and #DA.kpiCards == 5, "Deep Analysis must render 5 KPI cards")
for i = 1, 5 do
    local c = DA.kpiCards[i]
    check(c:IsShown() and plain(c.titleFs:GetText()) ~= "" and plain(c.valueFs:GetText()) ~= ""
        and plain(c.subFs:GetText()) ~= "", "KPI card " .. i .. " must show title, value, and subtitle")
end

-- Row 2: Concept B Timing Drawer (Matrix + 24h Curve)
local td = assert(DA.timingDrawer, "Deep Analysis must mount Concept B timingDrawer")
check(td:IsShown() and td._showCurve == true, "Deep Analysis timingDrawer must show 24h curve")
check(td.matrixFrame:IsShown() and td.curveFrame:IsShown(), "TimingDrawer matrix and curve must both be shown for Flask")
td:SetMetric("min")
td:SetMetric("supply")
td:SetMetric("avg")
td:SetResolution("12x2h")
td:SetResolution("24h")
td:SimulateHover(3, 19)
check(td.curveHoverLine:IsShown(), "Matrix hover must sync curve crosshair")
td:SimulateCurveHover(4)
check(td.colHighlight:IsShown(), "Curve hover must sync matrix column highlight")
td:SimulateHover(nil, nil)
td:SimulateCurveHover(nil)

-- Row 3 Left Card: 24h | 7d toggle + 6 Overview rows + Uncapped Reagents
local left = assert(DA.leftCard, "Deep Analysis leftCard must exist")
check(left.win24Btn ~= nil and left.win7dBtn ~= nil, "Left card must expose 24h and 7d buttons")
left.win24Btn:Click("LeftButton")
check(DA.GetState().window == "24h", "Clicking 24h toggle must switch Deep Analysis window to 24h")
left.win7dBtn:Click("LeftButton")
check(DA.GetState().window == "7d", "Clicking 7d toggle must switch Deep Analysis window back to 7d")
local shownOverview = 0
for i = 1, 6 do
    if left.overviewRows[i] and left.overviewRows[i]:IsShown() then shownOverview = shownOverview + 1 end
end
check(shownOverview >= 4, "Left card must render Quick Look Overview rows, got " .. shownOverview)

-- Row 3 Right Column: Competition, Personal Ledger, Acquisition
check(DA.compCard and plain(DA.compCard.bodyFs:GetText()):find("Seller Stats:", 1, true) ~= nil,
    "Competition card must include Seller Stats")
check(DA.ledgerCard and plain(DA.ledgerCard.bodyFs:GetText()) ~= "",
    "Personal Ledger & Cross-Alt Inventory card must be populated")
check(DA.acqCard and plain(DA.acqCard.bodyFs:GetText()):find("Source:", 1, true) ~= nil,
    "Acquisition card must include Source details")

-- Reagent Drill-Down: click Black Lotus (13468) row inside Left Card
local lotusReagentBtn
for _, f in ipairs(createdFrames) do
    if f._parent == left and f.itemID == 13468 and f.clickable == true then
        lotusReagentBtn = f
        break
    end
end
check(lotusReagentBtn ~= nil and lotusReagentBtn:IsShown(),
    "Clickable Black Lotus (13468) reagent row must exist in Deep Analysis breakdown")
lotusReagentBtn:Click("LeftButton")
drain()
check(DA.GetState().stackDepth == 1, "Clicking reagent must push parent craft onto drill-down stack")
check(DA.GetState().target and DA.GetState().target.kind == "item" and DA.GetState().target.itemID == 13468,
    "Reagent drill-down must inspect Black Lotus (13468) as kind='item'")
check(btnText(DA.header.returnBtn):find("< Back to ", 1, true) ~= nil,
    "Drill-down return button must display parent craft name, got: " .. btnText(DA.header.returnBtn))
check(td.matrixFrame:IsShown(), "Drilled-down Black Lotus must render its own 7x24 heatmap")

-- First < Return pops stack back to Flask of Supreme Power
DA.header.returnBtn:Click("LeftButton")
drain()
check(app.activeTab == "deep_analysis", "First < Return from reagent drill-down must stay on deep_analysis")
check(DA.GetState().stackDepth == 0, "First < Return must pop drill-down stack to 0")
check(DA.GetState().target and DA.GetState().target.itemID == 13512,
    "First < Return must restore parent craft Flask (13512)")

-- Second < Return restores originating tab ('recipes'), scrollPct, AND re-opens Quick Look!
DA.header.returnBtn:Click("LeftButton")
drain()
check(app.activeTab == "recipes", "Second < Return must restore originating recipes tab")
check(math.abs(scrollPctValue - 0.42) < 0.001, "Return must restore superListScrollPct")
check(hud:IsShown() and hud.row and hud.row.outputItemID == 13512,
    "Second < Return must re-open Quick Look for Flask of Supreme Power")
provider.CloseQuickLook()

-- 3. Quick Look -> Deep Analysis -> < Return across Dashboard, Writs, Crates, and Forged
app.ui.searchBox:SetText("")
for _, w in ipairs(ns.WRITS or {}) do
    local wid = w.writID or w.itemID
    if wid then db.ahPrices[econ][wid] = db.ahPrices[econ][wid] or { price = 12500, qty = 8, at = nowTs - 120 } end
    for _, req in ipairs(w.reagents or {}) do
        local rid = req.itemID or req[1]
        if rid then db.ahPrices[econ][rid] = db.ahPrices[econ][rid] or { price = 1800, qty = 30, at = nowTs - 120 } end
    end
end
for _, c in ipairs(ns.CRATES or {}) do
    if c.itemID then db.ahPrices[econ][c.itemID] = db.ahPrices[econ][c.itemID] or { price = 7500, qty = 12, at = nowTs - 120 } end
    for _, b in ipairs(c.bundles or {}) do
        if b.itemID then db.ahPrices[econ][b.itemID] = db.ahPrices[econ][b.itemID] or { price = 950, qty = 40, at = nowTs - 120 } end
    end
end
ns.InvalidatePriceCache()

-- 3a. Dashboard (recipe Quick Look)
app.setTab("dashboard")
drain()
check(app.openQuickLook("recipe", flaskRow, { owner = app.panel, toggle = false }), "Dashboard must open recipe Quick Look")
check(hud:IsShown(), "Dashboard Quick Look must be shown")
hud.deepAnalysisButton:Click("LeftButton")
drain()
check(app.activeTab == "deep_analysis", "Dashboard Quick Look button must open Deep Analysis")
check(btnText(DA.header.returnBtn):find("Dashboard", 1, true) ~= nil,
    "Return label must name Dashboard, got: " .. btnText(DA.header.returnBtn))
DA.header.returnBtn:Click("LeftButton")
drain()
check(app.activeTab == "dashboard" and hud:IsShown(), "Return must restore Dashboard and re-open Quick Look")
provider.CloseQuickLook()

-- 3b. Writs
app.setTab("writs")
drain()
local writRow = (app.quickLookRows and app.quickLookRows.writ and app.quickLookRows.writ[1])
    or (app.ui.writsTable and app.ui.writsTable.scrollBox and app.ui.writsTable.scrollBox._dp and app.ui.writsTable.scrollBox._dp:GetCollection()[1])
check(writRow ~= nil, "A writ row must be available for E2E test")
app.openQuickLook("writ", writRow, { toggle = false })
check(hud:IsShown() and hud.kind == "writ", "Writ Quick Look must open")
hud.deepAnalysisButton:Click("LeftButton")
drain()
check(app.activeTab == "deep_analysis" and DA.GetState().target.kind == "writ",
    "Writ Quick Look button must open Deep Analysis with kind='writ'")
check(plain(DA.acqCard.titleFs:GetText()) == "TURN-IN & MECHANICS",
    "Writ Deep Analysis must display Turn-In & Mechanics card")
DA.header.returnBtn:Click("LeftButton")
drain()
check(app.activeTab == "writs" and hud:IsShown(), "Return must restore Writs tab and Quick Look")
provider.CloseQuickLook()

-- 3c. Crates
app.setTab("crates")
drain()
local crateRow = (app.quickLookRows and app.quickLookRows.crate and app.quickLookRows.crate[1])
    or (app.ui.cratesTable and app.ui.cratesTable.scrollBox and app.ui.cratesTable.scrollBox._dp and app.ui.cratesTable.scrollBox._dp:GetCollection()[1])
check(crateRow ~= nil, "A crate row must be available for E2E test")
app.openQuickLook("crate", crateRow, { toggle = false })
check(hud:IsShown() and hud.kind == "crate", "Crate Quick Look must open")
hud.deepAnalysisButton:Click("LeftButton")
drain()
check(app.activeTab == "deep_analysis" and DA.GetState().target.kind == "crate",
    "Crate Quick Look button must open Deep Analysis with kind='crate'")
DA.header.returnBtn:Click("LeftButton")
drain()
check(app.activeTab == "crates" and hud:IsShown(), "Return must restore Crates tab and Quick Look")
provider.CloseQuickLook()

-- 3d. Forged Delivery
app.setTab("forged")
drain()
local forgedRow = (app.quickLookRows and app.quickLookRows.forged and app.quickLookRows.forged[1])
    or (app.ui.forgedTable and app.ui.forgedTable.scrollBox and app.ui.forgedTable.scrollBox._dp and app.ui.forgedTable.scrollBox._dp:GetCollection()[1])
check(forgedRow ~= nil, "A forged row must be available for E2E test")
app.openQuickLook("forged", forgedRow, { toggle = false })
check(hud:IsShown() and hud.kind == "forged", "Forged Quick Look must open")
hud.deepAnalysisButton:Click("LeftButton")
drain()
check(app.activeTab == "deep_analysis" and DA.GetState().target.kind == "forged",
    "Forged Quick Look button must open Deep Analysis with kind='forged'")
DA.header.returnBtn:Click("LeftButton")
drain()
check(app.activeTab == "forged" and hud:IsShown(), "Return must restore Forged tab and Quick Look")
provider.CloseQuickLook()

-- 3e. Analytics an_items detail popup button + sidebar escape clears stack
if ns.Analytics and ns.Analytics.UI and ns.Analytics.UI.Register then
    ns.Analytics.UI.Register()
end
app.setTab("an_items")
drain()
local anUI = ns.Analytics and ns.Analytics.UI
local anItemsView = anUI and anUI.views and anUI.views.an_items
check(anItemsView and anItemsView.detail and anItemsView.detail.deepAnalysisBtn ~= nil,
    "an_items detail popup must expose deepAnalysisBtn")
anUI.detailItem = { itemID = 13512, name = "Flask of Supreme Power", icon = ns.ItemIcon(13512) }
anUI.detailKey = 13512
anItemsView.detail:Show()
anItemsView.detail.deepAnalysisBtn:Click("LeftButton")
drain()
check(app.activeTab == "deep_analysis" and DA.GetState().target and DA.GetState().target.itemID == 13512,
    "an_items detail 'Deep Analysis >' button must open Deep Analysis for detailItem")
DA.header.returnBtn:Click("LeftButton")
drain()
check(app.activeTab == "an_items", "Return from an_items Deep Analysis must restore an_items tab")

-- Non-persistence + sidebar escape clears stack
app.openDeepAnalysis({ kind = "recipe", itemID = 13512 }, { tab = "recipes", wasQuickLookOpen = false })
app.openDeepAnalysis(13468)
check(DA.GetState().stackDepth == 1 and db.activeTab ~= "deep_analysis",
    "Nested Deep Analysis must track stackDepth=1 without persisting activeTab")
app.setTab("dashboard")
drain()
check(app._deepAnalysisStack == nil and not app.ui.deepAnalysisView:IsShown(),
    "Switching away via sidebar must clear drill-down stack and hide deepAnalysisView")
check(db.activeTab == "dashboard", "Normal tab switch must persist activeTab")

-- 4. Responsive Layouts (1320x730, 900x700 stacked, 1920x1080 wide) + Dark/Light + 5 Warcraft Skins
app.openDeepAnalysis({ kind = "recipe", itemID = 13512 }, { tab = "recipes", wasQuickLookOpen = false })
drain()
for _, sz in ipairs({ { 1320, 730 }, { 900, 700 }, { 1920, 1080 } }) do
    DA.Layout(sz[1], sz[2])
    check(DA.leftCard:GetWidth() > 0 and DA.compCard:GetWidth() > 0,
        "Deep Analysis layout must remain valid at " .. sz[1] .. "x" .. sz[2])
end

local origSkin = Theme.GetSkin and Theme.GetSkin() or "standard"
local origMode = Theme.GetMode and Theme.GetMode() or "dark"
for _, mode in ipairs({ "dark", "light" }) do
    if Theme.SetSkin then Theme.SetSkin("standard") end
    Theme.SetMode(mode)
    DA.Refresh()
    check(DA.frame:IsShown() and td.matrixFrame:IsShown(), "Deep Analysis must repaint cleanly in standard/" .. mode)
end
for _, skin in ipairs({ "human", "night_elf", "orc", "undead", "goblin" }) do
    if Theme.SetSkin then Theme.SetSkin(skin) end
    DA.Refresh()
    check(DA.frame:IsShown() and td.matrixFrame:IsShown(), "Deep Analysis must repaint cleanly in skin=" .. skin)
end

-- Also repaint Super List inline heat strip + compact popover under Light & Goblin skin
app.returnFromDeepAnalysis()
drain()
if Theme.SetSkin then Theme.SetSkin("standard") end
Theme.SetMode("light")
app.refresh()
drain()
if Theme.SetSkin then Theme.SetSkin("goblin") end
app.refresh()
drain()
if Theme.SetSkin then Theme.SetSkin(origSkin) end
Theme.SetMode(origMode)

-- 5. Proposal A in Deep Analysis: Vendor Yield Spread, Material Buy Caps & 5-bar Ledger Roll Histogram
do
    local Store = ns.Analytics and ns.Analytics.Store
    check(Store and type(Store.RecordCraftYield) == "function", "Analytics Store.RecordCraftYield exposed in DeepAnalysis")
    local oldLedger = _G.MerchantMasterLedgerDB
    _G.MerchantMasterLedgerDB = {}
    Store.Init()

    local hdRec
    for _, rec in ipairs(ns.RECIPES or {}) do
        if rec.spellID == 3946 then hdRec = rec; break end
    end
    check(hdRec and hdRec.outputItemID == 4378, "Heavy Dynamite (3946 -> 4378) recipe available")
    ns.RecordRecipeYieldRange(3946, 1, 5)
    db.ahPrices[econ][4377] = { price = 310, qty = 40, at = nowTs - 60 }
    db.ahPrices[econ][2592] = { price = 108, qty = 20, at = nowTs - 60 }
    db.ahLots = db.ahLots or {}
    db.ahLots[econ] = db.ahLots[econ] or {}
    db.ahLots[econ][4377] = { at = nowTs - 60, lots = { { price = 310, qty = 40 }, { price = 450, qty = 20 } } }
    db.ahLots[econ][2592] = { at = nowTs - 60, lots = { { price = 108, qty = 20 }, { price = 150, qty = 20 } } }
    ns.InvalidatePriceCache()
    if ns.VendorCrafterModel and ns.VendorCrafterModel.ClearCache then ns.VendorCrafterModel.ClearCache() end

    -- Record 15 casts summing to 42 (2.80x measured avg): 1x=2, 2x=4, 3x=5, 4x=3, 5x=1
    Store.RecordCraftYield(3946, 4378, 42, 15, { 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 5 })

    app.openDeepAnalysis({ kind = "recipe", recipe = hdRec }, { tab = "vendor_crafter", wasQuickLookOpen = false })
    drain()
    local stVC = DA.GetState()
    check(app.activeTab == "deep_analysis" and stVC.vcShown == true and DA.vcCard:IsShown(),
        "Deep Analysis shows Proposal A VC card for variable/measured Heavy Dynamite")
    check(btnText(DA.header.returnBtn) == "< Back to Vendor Crafter",
        "Return button shows '< Back to Vendor Crafter', got: " .. btnText(DA.header.returnBtn))
    local subTxt = plain(DA.header.subtitleFs:GetText())
    check(subTxt:find("1-5x", 1, true) ~= nil and subTxt:find("2.80x (15)", 1, true) ~= nil,
        "Deep Analysis subtitle displays '1-5x' range and '2.80x (15)' measured yield: " .. subTxt)
    local spreadTxt = plain(DA.vcCard.spreadFs:GetText())
    check(spreadTxt:find("Min", 1, true) ~= nil and spreadTxt:find("Avg", 1, true) ~= nil and spreadTxt:find("Max", 1, true) ~= nil,
        "VC card spread strip displays Min/Avg/Max vendor summary")
    check(stVC.vcCapUsed >= 2, "VC card shows at least 2 AH material buy-cap rows, got: " .. tostring(stVC.vcCapUsed))
    check(type(stVC.vcHistBuckets) == "table" and #stVC.vcHistBuckets == 5,
        "VC card renders 5 roll histogram bars (1x..5x), got: " .. tostring(stVC.vcHistBuckets and #stVC.vcHistBuckets))
    check(stVC.vcHistBuckets[3].val == 3 and stVC.vcHistBuckets[3].count == 5
        and DA.vcCard.histBars[3]:IsShown() and DA.vcCard.histBars[3].countFs:GetText() == "5",
        "Histogram peak bar 3x shows exact count=5")

    -- Theme & skin sweep with VC card visible
    for _, mode in ipairs({ "dark", "light" }) do
        if Theme.SetSkin then Theme.SetSkin("standard") end
        Theme.SetMode(mode)
        DA.Refresh()
        check(DA.vcCard:IsShown(), "VC card stays visible and repaints in standard/" .. mode)
    end
    for _, skin in ipairs({ "human", "night_elf", "orc", "undead", "goblin" }) do
        if Theme.SetSkin then Theme.SetSkin(skin) end
        DA.Refresh()
        check(DA.vcCard:IsShown(), "VC card repaints cleanly in skin=" .. skin)
    end

    -- Opening an item target or writ target hides VC card cleanly
    app.openDeepAnalysis({ kind = "item", itemID = 13468 })
    drain()
    check(not DA.vcCard:IsShown(), "Item target hides Recipe Vendor Yield & Buy Caps card")
    app.openDeepAnalysis({ kind = "writ", row = writRow }, { tab = "writs", wasQuickLookOpen = false })
    drain()
    check(not DA.vcCard:IsShown(), "Writ target hides Recipe Vendor Yield & Buy Caps card")

    app.setTab("dashboard")
    drain()
    if Theme.SetSkin then Theme.SetSkin(origSkin) end
    Theme.SetMode(origMode)
    _G.MerchantMasterLedgerDB = oldLedger
    Store.Init()
    db.ahPrices[econ][4377] = nil
    db.ahPrices[econ][2592] = nil
    db.ahLots[econ][4377] = nil
    db.ahLots[econ][2592] = nil
    ns.InvalidatePriceCache()
    if ns.VendorCrafterModel and ns.VendorCrafterModel.ClearCache then ns.VendorCrafterModel.ClearCache() end
end

-- 11. All Auction Houses (Latest-Only) Cross-House Comparison Card
do
    local origSkin = Theme.GetSkin and Theme.GetSkin() or "standard"
    local origMode = Theme.GetMode and Theme.GetMode() or "dark"
    local savedRaw = ns.snapshotRaw
    local savedParsed = ns.snapshotParsed
    local savedHeat = ns.snapshotHeatmapCache

    ns.snapshotRaw = {}
    ns.snapshotParsed = {}
    ns.snapshotHeatmapCache = {}

    local function seedHouse(ek, minB, mktV, qty, numA)
        _G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", ek,
            string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=1,heatmapCount=0}]], nowTs - 60))
        local entry = string.format("13468:%s,%s,%s,%s,%s,%s",
            encB32(minB), encB32(mktV), encB32(0), encB32(qty), encB32(numA), encB32(0))
        _G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", ek, entry)
    end

    seedHouse("Normal-Horde",    70085, 77503, 284, 61)
    seedHouse("Normal-Alliance", 60000, 62000, 232, 95)
    seedHouse("PvP-Horde",       92000, 92424, 410, 72)
    seedHouse("PvP-Blackwater",  94999, 94999,  24, 15)
    ns.InvalidatePriceCache()

    local ahSummary = ns.Pricing.GetAllAuctionHousesForItem(13468, "Normal-Horde")
    check(type(ahSummary) == "table" and ahSummary.totalHouses == 4 and ahSummary.listedHouses == 4,
        "GetAllAuctionHousesForItem returns all 4 seeded houses")
    check(ahSummary.totalQty == (284 + 232 + 410 + 24),
        "GetAllAuctionHousesForItem sums totalQty across all houses")
    check(ahSummary.lowest and ahSummary.lowest.economy == "Normal-Alliance" and ahSummary.lowest.minBuyout == 60000,
        "GetAllAuctionHousesForItem identifies Normal-Alliance as lowest")
    check(ahSummary.highest and ahSummary.highest.economy == "PvP-Blackwater" and ahSummary.highest.minBuyout == 94999,
        "GetAllAuctionHousesForItem identifies PvP-Blackwater as highest")

    app.openDeepAnalysis({ kind = "item", itemID = 13468, name = "Black Lotus" })
    drain()
    local stAH = DA.GetState()
    check(DA.allAhCard ~= nil and DA.allAhCard:IsShown() and stAH.allAhShown == true,
        "Deep Analysis displays All Auction Houses card when multi-house data is loaded")
    check(stAH.allAhFilter == "faction8" and stAH.allAhUsed == 3,
        "Default Faction filter excludes Blackwater and renders 3 faction houses, got: " .. tostring(stAH.allAhUsed))
    check(plain(stAH.allAhRows[1].nameFs:GetText()):find("Normal-Alliance", 1, true) ~= nil,
        "Default min-price sort puts cheapest Normal-Alliance first")

    local allBtn = DA.allAhCard.filterBtns and DA.allAhCard.filterBtns.all
    check(allBtn ~= nil and type(allBtn:GetScript("OnClick")) == "function", "All filter pill exists")
    allBtn:GetScript("OnClick")(allBtn)
    stAH = DA.GetState()
    check(stAH.allAhFilter == "all" and stAH.allAhUsed == 4,
        "Clicking All filter reveals PvP-Blackwater (4 rows), got: " .. tostring(stAH.allAhUsed))

    local qtyHdrBtn = DA.allAhCard.colBtns and DA.allAhCard.colBtns[5]
    check(qtyHdrBtn ~= nil and type(qtyHdrBtn:GetScript("OnClick")) == "function", "QTY column header exists")
    qtyHdrBtn:GetScript("OnClick")(qtyHdrBtn)
    stAH = DA.GetState()
    check(stAH.allAhSortCol == "qty" and plain(stAH.allAhRows[1].nameFs:GetText()):find("PvP-Horde", 1, true) ~= nil,
        "Clicking QTY column sorts descending with PvP-Horde (410) first")

    local minHdrBtn = DA.allAhCard.colBtns and DA.allAhCard.colBtns[2]
    minHdrBtn:GetScript("OnClick")(minHdrBtn)
    stAH = DA.GetState()
    check(stAH.allAhSortCol == "min" and plain(stAH.allAhRows[1].nameFs:GetText()):find("Normal-Alliance", 1, true) ~= nil,
        "Clicking MIN BUYOUT restores cheapest Normal-Alliance first")

    for _, mode in ipairs({ "dark", "light" }) do
        if Theme.SetSkin then Theme.SetSkin("standard") end
        Theme.SetMode(mode)
        DA.Refresh()
        check(DA.allAhCard:IsShown(), "All Auction Houses card repaints cleanly in " .. mode)
    end
    if Theme.SetSkin then Theme.SetSkin("goblin") end
    DA.Refresh()
    check(DA.allAhCard:IsShown(), "All Auction Houses card repaints cleanly in goblin skin")

    app.setTab("dashboard")
    drain()
    if Theme.SetSkin then Theme.SetSkin(origSkin) end
    Theme.SetMode(origMode)
    ns.snapshotRaw = savedRaw
    ns.snapshotParsed = savedParsed
    ns.snapshotHeatmapCache = savedHeat
    ns.InvalidatePriceCache()
end

-- 12. Feature B Visual-First Deep Analysis + Chart.lua Fixes + Header Star Button
do
    local Chart = assert(ns.Analytics and ns.Analytics.Chart, "ns.Analytics.Chart must exist")
    local origSkin = Theme.GetSkin and Theme.GetSkin() or "standard"
    local origMode = Theme.GetMode and Theme.GetMode() or "dark"

    -- 12a. Chart.lua exports, midnight-crossing chronological order, preserveColor, compact resetZoom, empty state
    check(type(Chart.BuildQuickLookSeries) == "function", "Chart.BuildQuickLookSeries must be exported")
    local testChart = Chart.CreateLineChart(UIParent, 440, 152, {
        title = "24h Test",
        preserveColor = true,
        preserveOrder = true,
        compact = true,
        emptyText = "Custom empty msg",
    })
    local midnightPts = {
        { day = "2026-11-25 22:00", label = "22:00", value = 120000, sortKey = 1795557600 },
        { day = "2026-11-25 23:00", label = "23:00", value = 115000, sortKey = 1795561200 },
        { day = "2026-11-26 00:00", label = "00:00", value = 105000, sortKey = 1795564800 },
        { day = "2026-11-26 01:00", label = "01:00", value = 98000,  sortKey = 1795568400 },
    }
    testChart:SetData({ { name = "Sell Price", colorKey = "blue", points = midnightPts } })
    check(testChart._rawCategories[1] == "2026-11-25 22:00" and testChart._rawCategories[4] == "2026-11-26 01:00",
        "Midnight-crossing 24h series must remain strictly chronological")
    check(testChart.xLabels[1]:GetText() == "22:00" and testChart.xLabels[3]:GetText() == "01:00",
        "formatAxisX must render YYYY-MM-DD HH:00 cleanly as HH:00, got " .. tostring(testChart.xLabels[1]:GetText()) .. " .. " .. tostring(testChart.xLabels[3]:GetText()))
    local palNow = Theme.GetActivePalette()
    local c1 = testChart._lastSeries[1] and testChart._lastSeries[1].color
    check(c1 ~= nil and math.abs(c1[1] - palNow.accentBlue[1]) < 0.001 and math.abs(c1[3] - palNow.accentBlue[3]) < 0.001,
        "preserveColor=true must keep semantic blue color even on a falling single series")
    local rzPt = testChart.resetZoom._points and testChart.resetZoom._points[1]
    check(rzPt ~= nil and rzPt[2] == testChart.plot,
        "Compact chart resetZoom must anchor inside chart.plot to never overlap summary")
    testChart:SetData({}, { emptyText = "Need 2+ AH scans" })
    check(testChart.empty:IsShown() and testChart.empty:GetText() == "Need 2+ AH scans",
        "Empty chart must show custom emptyText cleanly")
    -- Theme / skin repaint via Theme.RegisterWidget
    Theme.SetMode("light")
    if Theme.SetSkin then Theme.SetSkin("goblin") end
    if Theme.SetSkin then Theme.SetSkin(origSkin) end
    Theme.SetMode(origMode)
    testChart:Hide()

    -- 12b. Header favBtn star toggle with safe Watchlist guard + gold tint sync
    app.openDeepAnalysis({ kind = "recipe", row = flaskRow, recipe = flaskRow.recipe, itemID = 13512 }, { tab = "recipes", wasQuickLookOpen = false })
    drain()
    check(DA.header.favBtn ~= nil and DA.header.favBtn:IsShown(), "DA.header.favBtn must exist and be shown")
    check(DA.header.favBtn:GetWidth() == 28 and DA.header.favBtn:GetHeight() == 28, "DA.header.favBtn must be 28x28")
    -- Safe click when ns.Watchlist is absent
    local origWatchlist = ns.Watchlist
    ns.Watchlist = nil
    DA.header.favBtn:Click("LeftButton")
    check(DA.GetState().favWatched == false, "favBtn must not error when ns.Watchlist is nil")
    -- Mock Watchlist locally (matching UI_Watchlist.lua IsFavorite/Toggle/RegisterListener contract) and verify toggle + theme sync
    local watchedMap = {}
    local wlListeners = {}
    ns.Watchlist = {
        Toggle = function(tgt)
            local id = tgt and (tgt.itemID or (tgt.row and tgt.row.outputItemID)) or 0
            watchedMap[id] = not watchedMap[id]
            for _, fn in ipairs(wlListeners) do fn() end
            return watchedMap[id]
        end,
        IsFavorite = function(tgt)
            local id = tgt and (tgt.itemID or (tgt.row and tgt.row.outputItemID)) or 0
            return watchedMap[id] == true
        end,
        RegisterListener = function(fn)
            if type(fn) == "function" then wlListeners[#wlListeners + 1] = fn end
        end,
    }
    DA.header.favBtn:Click("LeftButton")
    check(DA.GetState().favWatched == true and DA.header.favBtn._watched == true,
        "Clicking favBtn with ns.Watchlist must toggle watched=true")
    if Theme.SetSkin then Theme.SetSkin("human") end
    check(DA.header.favBtn._watched == true, "favBtn must preserve watched state across skin switch")
    DA.header.favBtn:Click("LeftButton")
    check(DA.GetState().favWatched == false, "Second favBtn click must toggle watched=false")
    ns.Watchlist = origWatchlist
    if Theme.SetSkin then Theme.SetSkin(origSkin) end
    Theme.SetMode(origMode)

    -- 12c. DA.chartsRow dual 24h & 7d charts for recipe, item, and 44px fallback collapse
    check(DA.chartsRow ~= nil and DA.chartsRow.frame ~= nil, "DA.chartsRow must be exposed")
    check(DA.chartsRow.chart24h == DA.chart24h and DA.chartsRow.chart7d == DA.chart7d and DA.chartsRow.baselineCard == DA.baselineCard,
        "DA.chartsRow must expose { frame, chart24h, chart7d, baselineCard }")
    DA.Render({ kind = "recipe", row = flaskRow, recipe = flaskRow.recipe, itemID = 13512 }, false)
    local stRec = DA.GetState()
    check(stRec.chartsCollapsed == false and DA.chart7d:IsShown() and not DA.baselineCard:IsShown(),
        "Seeded recipe must show chartsRow instead of collapsed baselineCard")
    check(stRec.charts7dPts >= 2, "Flask 7d chart must have >= 2 points, got " .. tostring(stRec.charts7dPts))
    check(DA.chart7d._lastSeries and #DA.chart7d._lastSeries >= 2,
        "Recipe 7d chart must plot dual Sell Price + Craft Cost series")

    -- Side-by-side at 1320x730 & 900x700 (W=882 >= 860), stacked at 720x700 (W=702 < 860)
    DA.Layout(1320, 730)
    check(DA.chartsRow.frame:GetHeight() == 152, "chartsRow must be 152px side-by-side at 1320x730")
    DA.Layout(900, 700)
    check(DA.chartsRow.frame:GetHeight() == 152 and DA.leftCard:GetWidth() <= 882,
        "900x700 must never clip horizontally (leftCard W=" .. tostring(DA.leftCard:GetWidth()) .. ")")
    DA.Layout(720, 700)
    check(DA.chartsRow.frame:GetHeight() == 314, "chartsRow must stack cleanly (314px) below W=860, got " .. tostring(DA.chartsRow.frame:GetHeight()))
    DA.Layout(1320, 730)

    -- 12d. Left Card econBarCard (recipe 3-bar vs item range track) + Reagent Cost Share Bars vs hidden on Item
    local left = DA.leftCard
    check(left.econBarCard ~= nil and left.econBarCard:IsShown(), "left.econBarCard must be shown")
    check(left.econBarCard.craftFrame:IsShown() and not left.econBarCard.rangeFrame:IsShown(),
        "Recipe econBarCard must display 3-bar craft waterfall")
    check(#left.econBarCard.craftBars == 3, "econBarCard must have 3 craft bars (Craft Cost, Net AH Sale, Net Profit)")

    local foundShareBar, foundPctExt = false, false
    for _, f in ipairs(createdFrames) do
        if f._parent == left and f:IsShown() and f._hasShareBar == true then
            foundShareBar = true
            if f.shareTrack and f.shareTrack:IsShown() and f.shareFill and f.shareFill:IsShown() then
                local extTxt = plain(f.extFs and f.extFs:GetText() or "")
                if extTxt:find("(%d+%%)") then foundPctExt = true end
            end
        end
    end
    check(foundShareBar and foundPctExt, "Recipe priced reagent rows must show Cost Share bar and (XX%) share on extFs")

    -- 12e. Item view: dual item charts, econBarCard range track, and Cost Share bars explicitly HIDDEN on Used In rows
    app.openDeepAnalysis({ kind = "item", itemID = 13468, name = "Black Lotus" })
    drain()
    local stItem = DA.GetState()
    check(stItem.chartsCollapsed == false and stItem.charts24Pts >= 2 and stItem.charts7dPts >= 2,
        "Seeded item Black Lotus must plot both 24h (" .. tostring(stItem.charts24Pts) .. ") and 7d (" .. tostring(stItem.charts7dPts) .. ") trends")
    check(left.econBarCard.rangeFrame:IsShown() and not left.econBarCard.craftFrame:IsShown(),
        "Item econBarCard must display Price Range Track")
    local anyItemShareShown = false
    for _, f in ipairs(createdFrames) do
        if f._parent == left and f:IsShown() and f.shareTrack and f.shareTrack:IsShown() then
            anyItemShareShown = true
            break
        end
    end
    check(not anyItemShareShown, "Item 'Used in' rows must explicitly hide Cost Share bars")

    -- 12f. Fallback 44px Baseline Card when BOTH 24h and 7d have < 2 points
    app.openDeepAnalysis({ kind = "item", itemID = 999991, name = "Unscanned Relic" })
    drain()
    local stEmpty = DA.GetState()
    check(stEmpty.chartsCollapsed == true and DA.baselineCard:IsShown() and DA.chartsRow.frame:GetHeight() == 44,
        "Item with < 2 scan points must collapse chartsRow to 44px baselineCard")
    check(not DA.chart24h:IsShown() and not DA.chart7d:IsShown(),
        "Collapsed chartsRow must hide both line charts cleanly")
    local baseStrip = plain(DA.baselineCard.stripFs:GetText())
    local baseHint = plain(DA.baselineCard.hintFs:GetText())
    check(baseStrip:find("Vendor Floor", 1, true) ~= nil and baseStrip:find("Live AH", 1, true) ~= nil and baseStrip:find("24h Deposit", 1, true) ~= nil,
        "Baseline card must display Vendor Floor -> Live AH -> 24h Deposit, got: " .. baseStrip)
    check(baseHint:find("Run 2+ AH scans over time", 1, true) ~= nil,
        "Baseline card must show clean AH scan hint without snapshot nag, got: " .. baseHint)

    -- 12g. Right Column: compCard heat bar + Unscanned, ledgerCard zero-trade vs seeded trades + nil guards, acqCard pills
    check(DA.compCard.heatBar ~= nil and #DA.compCard.heatTiers == 4, "compCard must have 4-tier Demand Heat Bar")
    local compTxt = plain(DA.compCard.bodyFs:GetText())
    check(compTxt:find("Seller Stats:", 1, true) ~= nil and compTxt:find("Unscanned", 1, true) ~= nil and not compTxt:find("n/a", 1, true),
        "compCard must show 'Unscanned' instead of 'n/a' and keep 'Seller Stats:', got: " .. compTxt)

    -- Ledger card with zero trades
    check(not DA.ledgerCard.horizonFrame:IsShown() and DA.ledgerCard.emptyTradesFs:IsShown(),
        "ledgerCard with 0 personal trades must hide Profit Horizon bars and show emptyTradesFs")
    check(DA.ledgerCard.stockRow:IsShown() and #DA.ledgerCard.stockChips == 4,
        "ledgerCard must always render 4 Cross-Alt Stock chips (Bags, Bank, Mail, AH)")
    check(plain(DA.ledgerCard.bodyFs:GetText()) ~= "", "ledgerCard.bodyFs must stay populated even with 0 trades")

    -- Ledger card with seeded personal trades + nil inventory/isSlowing guard
    local origGetItemDetail = ns.Analytics and ns.Analytics.Model and ns.Analytics.Model.GetItemDetail
    if ns.Analytics and ns.Analytics.Model then
        ns.Analytics.Model.GetItemDetail = function()
            return {
                windows = {
                    d7  = { sold = 5, bought = 2, avgSell = 685000, profit = 420000 },
                    d30 = { sold = 18, bought = 6, avgSell = 660000, profit = 1350000 },
                    all = { sold = 44, bought = 12, avgSell = 650000, profit = 3100000 },
                },
                saleRate = 0.72,
                expSinceSale = 1,
                canSinceSale = 2,
                isSlowing = false,
                inventory = { bags = 3, bank = 8, mail = 1, ah = 4, total = 16 },
            }
        end
        DA.Render({ kind = "recipe", row = flaskRow, recipe = flaskRow.recipe, itemID = 13512 }, false)
        check(DA.ledgerCard.horizonFrame:IsShown() and not DA.ledgerCard.emptyTradesFs:IsShown(),
            "ledgerCard with trades must show 3-column Profit Horizon bars")
        check(DA.ledgerCard.saleRateRow:IsShown(), "ledgerCard with trades must show 180d Sale-Rate ProgressBar")
        check(plain(DA.ledgerCard.stockChips[1].lblFs:GetText()) == "Bags 3"
            and plain(DA.ledgerCard.stockChips[2].lblFs:GetText()) == "Bank 8"
            and plain(DA.ledgerCard.stockChips[3].lblFs:GetText()) == "Mail 1"
            and plain(DA.ledgerCard.stockChips[4].lblFs:GetText()) == "AH 4",
            "ledgerCard stock chips must reflect cross-alt Bags/Bank/Mail/AH counts")

        -- Guard nil inventory & nil isSlowing
        ns.Analytics.Model.GetItemDetail = function()
            return {
                windows = { d7 = {}, d30 = {}, all = { sold = 1, bought = 0, profit = 5000 } },
                saleRate = nil,
                isSlowing = nil,
                inventory = nil,
            }
        end
        DA.Render({ kind = "recipe", row = flaskRow, recipe = flaskRow.recipe, itemID = 13512 }, false)
        check(DA.ledgerCard.horizonFrame:IsShown() and plain(DA.ledgerCard.bodyFs:GetText()) ~= "",
            "ledgerCard must gracefully guard nil inventory, nil saleRate, and nil isSlowing")

        -- Indirect via Disenchant summary line on Personal Ledger card
        ns.Analytics.Model.GetItemDetail = function()
            return {
                windows = { d7 = {}, d30 = {}, all = { sold = 0, bought = 12, profit = 0 } },
                saleRate = 0,
                isSlowing = false,
                deBrokenQty = 12,
                deSoldMatsQty = 11,
                deIndirectProfit = 104000,
                deSoldOutputs = { { itemID = 11178, name = "Large Radiant Shard", qty = 11, profit = 104000 } },
                inventory = { bags = 0, bank = 0, mail = 0, ah = 0, total = 0 },
            }
        end
        DA.Render({ kind = "item", itemID = 10504, name = "Green Lens" }, false)
        local deLedgerTxt = plain(DA.ledgerCard.bodyFs:GetText())
        check(deLedgerTxt:find("Indirect via Disenchant:", 1, true) ~= nil
            and deLedgerTxt:find("DE'd 12x -> Sold mats", 1, true) ~= nil
            and deLedgerTxt:find("10g 40s", 1, true) ~= nil,
            "Personal Ledger card must render Indirect via Disenchant summary when deBrokenQty > 0 (got: " .. deLedgerTxt .. ")")
        ns.Analytics.Model.GetItemDetail = origGetItemDetail
    end

    -- 12g-2. compCard colored heatmap line in Standalone (spectrum) AND Snapshot (24h strip) modes, zero vertical overlap
    do
        local cc = DA.compCard
        local hsf = cc and cc.heatStripFrame
        check(hsf ~= nil and hsf:IsShown() and hsf.captionFs ~= nil,
            "compCard must mount and show heatStripFrame above bodyFs")
        local origGetHeatStrip = ns.Pricing and ns.Pricing.GetItemHeatStrip24h
        local origGetHeatmap = ns.Pricing and ns.Pricing.GetItemHeatmap

        -- Mode A: Standalone (no 24h snapshot curve) -> 12-segment colored spectrum bar + active heat marker
        if ns.Pricing then
            ns.Pricing.GetItemHeatStrip24h = function() return nil end
            ns.Pricing.GetItemHeatmap = function() return nil end
        end
        DA.Render({ kind = "item", itemID = 10504, name = "Green Lens" }, false)
        DA.Layout(1320, 730)
        check(hsf._mode == "spectrum" and hsf.spectrumBar:IsShown() and #(hsf.spectrumSegs or {}) == 12
            and hsf.spectrumMarker ~= nil and hsf.spectrumMarker:IsShown(),
            "Standalone mode must render 12-segment colored Hot/Cold spectrum bar with active marker")
        check(plain(hsf.captionFs:GetText()):find("Sales Heat", 1, true) ~= nil,
            "Standalone mode caption must label Sales Heat (got: " .. plain(hsf.captionFs:GetText()) .. ")")
        check(not (hsf.strip24h and hsf.strip24h.frame and hsf.strip24h.frame:IsShown()),
            "Standalone mode must hide 24h snapshot strip")
        local function pointY(f)
            local pt = f and f._points and f._points[1]
            return tonumber(pt and (pt[5] or pt.y)) or 0
        end
        local hsfY = pointY(hsf)
        local bodyY = pointY(cc.bodyFs)
        check(hsfY < 0 and math.abs(bodyY) >= math.abs(hsfY) + hsf:GetHeight(),
            "compCard.bodyFs must sit cleanly below heatStripFrame with zero vertical overlap (hsfY=" .. tostring(hsfY) .. ", hsfH=" .. tostring(hsf:GetHeight()) .. ", bodyY=" .. tostring(bodyY) .. ")")
        local compTop = pointY(cc)
        local ledTop = pointY(DA.ledgerCard)
        check(math.abs(ledTop) >= math.abs(compTop) + cc:GetHeight(),
            "ledgerCard must sit cleanly below compCard after adding heatStripFrame (zero overlap)")

        -- Mode B: Snapshot mode (24h hourly curve present) -> real 24h colored CreateHeatStrip24h bar
        if ns.Pricing then
            local hourly = {}
            for hr = 0, 23 do hourly[hr] = { avgPrice = 10000 + hr * 400 } end
            ns.Pricing.GetItemHeatStrip24h = function()
                return { hourly = hourly, avgPrice = 14600, medianPrice = 14600, updatedAt = _G.time() }
            end
        end
        DA.Render({ kind = "item", itemID = 10504, name = "Green Lens" }, false)
        DA.Layout(1320, 730)
        check(hsf._mode == "snapshot" and hsf.strip24h ~= nil and hsf.strip24h.frame:IsShown()
            and not hsf.spectrumBar:IsShown(),
            "Snapshot mode must render real 24h colored CreateHeatStrip24h bar and hide standalone spectrum")
        check(plain(hsf.captionFs:GetText()):find("24h Heatmap", 1, true) ~= nil,
            "Snapshot mode caption must label 24h Heatmap (got: " .. plain(hsf.captionFs:GetText()) .. ")")

        if ns.Pricing then
            ns.Pricing.GetItemHeatStrip24h = origGetHeatStrip
            ns.Pricing.GetItemHeatmap = origGetHeatmap
        end
    end

    -- acqCard pills shown for recipe
    check(DA.acqCard.pillRow ~= nil and DA.acqCard.pillRow:IsShown() and DA.acqCard.pills[1].frame:IsShown(),
        "acqCard must render structured status pills for recipes")
    check(plain(DA.acqCard.bodyFs:GetText()):find("Source:", 1, true) ~= nil,
        "acqCard must preserve 'Source:' line for recipes")

    -- 12h. Hidden theme switch sets dirtyThemeRender instead of eagerly rendering; OnShow clears it
    DA.frame:Hide()
    Theme.SetMode("light")
    check(DA.GetState().dirtyThemeRender == true,
        "Theme switch while DeepAnalysis hidden must defer render via dirtyThemeRender=true")
    DA.frame:Show()
    check(DA.GetState().dirtyThemeRender == false,
        "Showing DeepAnalysis frame must flush dirtyThemeRender cleanly")

    -- Full viewport x skin sweep on new visual panels
    for _, sz in ipairs({ { 900, 700 }, { 1320, 730 }, { 1920, 1080 } }) do
        DA.Layout(sz[1], sz[2])
        check(DA.chartsRow.frame:GetWidth() <= sz[1] - 18 and DA.leftCard:GetWidth() <= sz[1] - 18,
            "All visual cards must fit within viewport at " .. sz[1] .. "x" .. sz[2])
    end
    for _, mode in ipairs({ "dark", "light" }) do
        if Theme.SetSkin then Theme.SetSkin("standard") end
        Theme.SetMode(mode)
        check(DA.chartsRow.frame:IsShown() and DA.leftCard.econBarCard:IsShown() and DA.compCard.heatBar:IsShown(),
            "All Feature B visual panels must repaint cleanly in standard/" .. mode)
    end
    for _, skin in ipairs({ "human", "night_elf", "orc", "undead", "goblin" }) do
        if Theme.SetSkin then Theme.SetSkin(skin) end
        check(DA.chartsRow.frame:IsShown() and DA.leftCard.econBarCard:IsShown() and DA.compCard.heatBar:IsShown(),
            "All Feature B visual panels must repaint cleanly in skin=" .. skin)
    end

    app.setTab("dashboard")
    drain()
    if Theme.SetSkin then Theme.SetSkin(origSkin) end
    Theme.SetMode(origMode)
end

-- 13. Permanent CRAFTING BREAKDOWN + USED IN Sections (Shadow Oil, Vendor, Drop, Unused)
do
    local origSkin = Theme.GetSkin and Theme.GetSkin() or "standard"
    local origMode = Theme.GetMode and Theme.GetMode() or "dark"
    local left = assert(DA.leftCard, "DA.leftCard must exist for Crafting Breakdown tests")

    local extraSeed = {
        [3824]  = { 11000, 11400, 11800, 12200, 12600, 13000, 13500 }, -- Shadow Oil
        [3818]  = { 1500,  1550,  1600,  1680,  1720,  1780,  1850  }, -- Fadeleaf
        [3369]  = { 900,   920,   950,   980,   1000,  1050,  1100  }, -- Grave Moss
        [3372]  = { 40,    40,    40,    40,    40,    40,    40    }, -- Leaded Vial
        [13459] = { 82000, 84000, 86000, 89000, 91000, 93000, 95000 }, -- Greater Shadow Protection Potion
        [4304]  = { 1100,  1150,  1200,  1250,  1300,  1350,  1400  }, -- Thick Leather
    }
    local savedPrices, savedDaily = {}, {}
    for id, series in pairs(extraSeed) do
        savedPrices[id] = db.ahPrices[econ][id]
        savedDaily[id] = db.ahDaily[econ][id]
        local buckets = {}
        for i = 1, 7 do
            buckets[i] = { d = day - 7 + i, lastP = series[i], lastQ = 18 - i, at = nowTs - (7 - i) * 86400 }
        end
        db.ahDaily[econ][id] = buckets
        db.ahPrices[econ][id] = { price = series[7], qty = 14, at = nowTs - 90 }
    end
    ns.InvalidatePriceCache()

    -- 13a. Shadow Oil (itemID=3824) opened as kind="item" from Watchlist shows full Crafting Breakdown + Used In
    app.openDeepAnalysis({ kind = "item", itemID = 3824, name = "Shadow Oil" }, { tab = "watchlist", wasQuickLookOpen = false })
    drain()
    local stSO = DA.GetState()
    check(btnText(DA.header.returnBtn) == "< Back to Watchlist",
        "Watchlist return button displays '< Back to Watchlist', got: " .. btnText(DA.header.returnBtn))
    check(stSO.target and stSO.target.kind == "item" and stSO.target.itemID == 3824,
        "Shadow Oil retains kind='item' target identity while showing crafting breakdown")
    check(stSO.hasCraftBreakdown == true and stSO.craftSourceKind == "crafted" and stSO.reagentUsedCount == 3,
        string.format("Shadow Oil displays Crafting Breakdown with 3 reagents (hasCraft=%s, src=%s, reagents=%s)",
            tostring(stSO.hasCraftBreakdown), tostring(stSO.craftSourceKind), tostring(stSO.reagentUsedCount)))
    check(left.econBarCard.craftFrame:IsShown() and not left.econBarCard.rangeFrame:IsShown(),
        "Craftable item Shadow Oil switches econBarCard to 3-bar Craft Cost / Net Sale / Net Profit")
    check(plain(left.reagTitle:GetText()):find("CRAFTING BREAKDOWN", 1, true) ~= nil
        and plain(left.reagTitle:GetText()):find("Alchemy", 1, true) ~= nil,
        "Shadow Oil Crafting Breakdown title names Alchemy: " .. plain(left.reagTitle:GetText()))
    check(DA.chart7d._lastSeries and #DA.chart7d._lastSeries >= 2,
        "Shadow Oil 7d chart plots both Sell Price and Craft Cost series")
    check(left.colHeaders[1]:IsShown() and select(4, left.reagTitle:GetTextColor()) >= 0.9,
        "Active Crafting Breakdown keeps full column headers and un-muted title opacity")

    local soShareCount = 0
    for _, f in ipairs(createdFrames) do
        if f._parent == left and f:IsShown() and f._hasShareBar == true then
            soShareCount = soShareCount + 1
        end
    end
    check(soShareCount >= 2, "Shadow Oil market reagents render Cost Share bars, got: " .. tostring(soShareCount))

    check(stSO.usedInTotalCount >= 6 and stSO.usedInShownCount >= 6,
        "Shadow Oil shows downstream Used In recipes, total=" .. tostring(stSO.usedInTotalCount))
    check(left.usedInTitle:IsShown() and plain(left.usedInTitle:GetText()):find("USED IN", 1, true) ~= nil,
        "Used In section header renders directly below Crafting Breakdown")
    check(DA.usedInRows[1] and DA.usedInRows[1]:IsShown() and DA.usedInRows[1].itemID == 13459,
        "Used In sorts highest-priced downstream product (Greater Shadow Protection Potion 13459) first, got: "
        .. tostring(DA.usedInRows[1] and DA.usedInRows[1].itemID))

    local function pointYLocal(f)
        local pt = f and f._points and f._points[1]
        return tonumber(pt and (pt[5] or pt.y)) or 0
    end
    local lastReagBtn
    for _, f in ipairs(createdFrames) do
        if f._parent == left and f:IsShown() and f._hasShareBar ~= nil and f.qtyFs and f.itemID == 3372 then
            lastReagBtn = f
        end
    end
    check(lastReagBtn ~= nil, "Shadow Oil Leaded Vial (3372) reagent row must be visible")
    local divY = pointYLocal(left.usedInDivider)
    local lrY = pointYLocal(lastReagBtn)
    check(math.abs(divY) >= math.abs(lrY) + 26,
        "Used In divider sits cleanly below last Shadow Oil reagent row without overlap")

    -- Clicking Used In row drills into Greater Shadow Protection Potion and Back returns to Shadow Oil
    DA.usedInRows[1]:Click("LeftButton")
    drain()
    check(DA.GetState().stackDepth == 1 and DA.GetState().target and DA.GetState().target.itemID == 13459,
        "Clicking Shadow Oil Used In row drills into Greater Shadow Protection Potion (13459)")
    check(btnText(DA.header.returnBtn):find("< Back to Shadow Oil", 1, true) ~= nil,
        "Return button after Used In drill-down names Shadow Oil, got: " .. btnText(DA.header.returnBtn))
    DA.header.returnBtn:Click("LeftButton")
    drain()
    check(DA.GetState().stackDepth == 0 and DA.GetState().target and DA.GetState().target.itemID == 3824,
        "< Return restores Shadow Oil (3824)")

    -- 13b. Non-craftable Vendor item Crystal Vial (8925) shows muted 'Not craftable | Vendor' + active Used In
    app.openDeepAnalysis({ kind = "item", itemID = 8925, name = "Crystal Vial" })
    drain()
    local stVial = DA.GetState()
    check(stVial.hasCraftBreakdown == false and stVial.craftSourceKind == "vendor",
        "Crystal Vial classifies as non-craftable Vendor, got: " .. tostring(stVial.craftSourceKind))
    local vialTxt = plain(left.reagEmptyFs:GetText())
    check(left.reagEmptyFs:IsShown() and vialTxt:find("Not craftable", 1, true) ~= nil and vialTxt:find("Vendor", 1, true) ~= nil,
        "Crystal Vial shows 'Not craftable | Vendor', got: " .. vialTxt)
    check(select(4, left.reagTitle:GetTextColor()) < 0.8 and select(4, left.reagEmptyFs:GetTextColor()) < 0.8,
        "Non-craftable Vendor Crafting Breakdown renders grayed-out muted text")
    check(not left.colHeaders[1]:IsShown(), "Non-craftable Crafting Breakdown hides reagent column headers")
    check(stVial.usedInTotalCount > 0 and DA.usedInRows[1]:IsShown(),
        "Vendor item Crystal Vial still renders downstream Used In recipes")

    -- 13c. Thick Leather (4304): craftable from Heavy Leather AND >10 Used In recipes + Show All toggle
    app.openDeepAnalysis({ kind = "item", itemID = 4304, name = "Thick Leather" })
    drain()
    local stTL = DA.GetState()
    check(stTL.hasCraftBreakdown == true and stTL.craftSourceKind == "crafted" and stTL.reagentUsedCount >= 1,
        "Thick Leather shows Leatherworking craft breakdown from Heavy Leather")
    check(stTL.usedInTotalCount > 10 and stTL.usedInShownCount == 10 and left.usedInToggleBtn:IsShown(),
        string.format("Thick Leather caps initial Used In to top 10 of %s with Show all toggle", tostring(stTL.usedInTotalCount)))
    left.usedInToggleBtn:Click("LeftButton")
    drain()
    local stTLExp = DA.GetState()
    check(stTLExp.usedInExpanded == true and stTLExp.usedInShownCount == stTLExp.usedInTotalCount,
        "Clicking Show all expands all Used In recipes for Thick Leather")

    -- 13c2. Genuine Non-craftable Drop items: Runecloth (14047) & Black Lotus (13468) show muted Drop + active Used In
    app.openDeepAnalysis({ kind = "item", itemID = 14047, name = "Runecloth" })
    drain()
    local stRC = DA.GetState()
    local rcTxt = plain(left.reagEmptyFs:GetText())
    check(stRC.hasCraftBreakdown == false and stRC.craftSourceKind == "drop"
        and rcTxt:find("Not craftable", 1, true) ~= nil and rcTxt:find("Drop", 1, true) ~= nil,
        "Runecloth shows 'Not craftable | Drop', got: " .. rcTxt)
    check(select(4, left.reagTitle:GetTextColor()) < 0.8 and select(4, left.reagEmptyFs:GetTextColor()) < 0.8,
        "Non-craftable Drop Runecloth renders grayed-out muted text")
    check(stRC.usedInTotalCount > 10 and stRC.usedInShownCount == 10,
        "Runecloth shows Used In recipes downstream, total=" .. tostring(stRC.usedInTotalCount))

    app.openDeepAnalysis({ kind = "item", itemID = 13468, name = "Black Lotus" })
    drain()
    local stBL = DA.GetState()
    local blTxt = plain(left.reagEmptyFs:GetText())
    check(stBL.hasCraftBreakdown == false and stBL.craftSourceKind == "drop"
        and blTxt:find("Drop (Herbalism 300)", 1, true) ~= nil,
        "Black Lotus shows 'Drop (Herbalism 300)', got: " .. blTxt)
    check(stBL.usedInTotalCount > 0 and DA.usedInRows[1]:IsShown(),
        "Black Lotus displays downstream Flask Used In recipes")

    -- 13d. Non-craftable and Unused item Unscanned Relic (999991) shows both muted grayed-out states
    app.openDeepAnalysis({ kind = "item", itemID = 999991, name = "Unscanned Relic" })
    drain()
    local stNone = DA.GetState()
    check(stNone.craftSourceKind == "not_craftable" and plain(left.reagEmptyFs:GetText()) == "Not craftable",
        "Unknown/unused item displays exact 'Not craftable', got: " .. plain(left.reagEmptyFs:GetText()))
    check(stNone.usedInTotalCount == 0 and stNone.usedInShownCount == 0 and left.usedInEmptyFs:IsShown()
        and plain(left.usedInEmptyFs:GetText()):find("Not used in any", 1, true) ~= nil,
        "Unused item displays muted 'Not used in any crafting recipes.', got: " .. plain(left.usedInEmptyFs:GetText()))
    check(select(4, left.usedInTitle:GetTextColor()) < 0.8 and select(4, left.usedInEmptyFs:GetTextColor()) < 0.8,
        "Empty Used In section renders grayed-out muted title and message")

    -- 13e. Craftable end-game weapon Sageblade (22383): active Crafting Breakdown + muted empty Used In
    app.openDeepAnalysis({ kind = "item", itemID = 22383, name = "Sageblade" })
    drain()
    local stSage = DA.GetState()
    check(stSage.hasCraftBreakdown == true and stSage.reagentUsedCount >= 4
        and stSage.usedInTotalCount == 0 and left.usedInEmptyFs:IsShown()
        and select(4, left.usedInEmptyFs:GetTextColor()) < 0.8,
        "Craftable end-game gear Sageblade shows active Crafting Breakdown and grayed-out empty Used In underneath")

    -- 14. Back-button restores parent scroll offset, Crafting Breakdown section, and Used In expanded state
    local function findClickableReagentRow(minItemID)
        for _, f in ipairs(createdFrames) do
            if f._parent == left and f:IsShown() and f._hasShareBar ~= nil and f.qtyFs and f.clickable == true then
                if not minItemID or f.itemID == minItemID then return f end
            end
        end
        return nil
    end
    app.setTab("recipes")
    drain()
    app.openDeepAnalysis({ kind = "recipe", itemID = 13512, name = "Flask of Supreme Power" })
    drain()
    local mw = DA.scrollFrame and DA.scrollFrame:GetScript("OnMouseWheel")
    check(type(mw) == "function", "DA.scrollFrame exposes OnMouseWheel for scroll restoration check")
    mw(DA.scrollFrame, -4)
    local scrolledBefore = DA.GetState().scrollOffset or 0
    check(scrolledBefore > 0, "Mouse wheel scrolls Flask Deep Analysis down (offset=" .. tostring(scrolledBefore) .. ")")
    local flaskReagBtn = findClickableReagentRow()
    check(flaskReagBtn ~= nil, "Flask clickable Crafting Breakdown reagent row is visible")
    flaskReagBtn:Click("LeftButton")
    drain()
    check(DA.GetState().stackDepth == 1 and DA.GetState().target and DA.GetState().target.itemID == flaskReagBtn.itemID,
        "Clicking reagent drilled into child item " .. tostring(flaskReagBtn.itemID))
    DA.header.returnBtn:Click("LeftButton")
    drain()
    local restoredOff = DA.GetState().scrollOffset or 0
    check(DA.GetState().stackDepth == 0 and DA.GetState().target and DA.GetState().target.itemID == 13512
        and math.abs(restoredOff - scrolledBefore) <= 2,
        "Back button restores parent Flask item at prior scroll offset (" .. tostring(restoredOff) .. " vs " .. tostring(scrolledBefore) .. ")")

    -- 14b. Drilling from Crafting Breakdown at scroll=0 jumps back straight to Crafting Breakdown section
    app.setTab("recipes")
    drain()
    app.openDeepAnalysis({ kind = "recipe", itemID = 13512, name = "Flask of Supreme Power" })
    drain()
    check((DA.GetState().scrollOffset or 0) == 0, "Fresh Deep Analysis starts at scrollOffset=0")
    local topReagBtn = findClickableReagentRow()
    check(topReagBtn ~= nil, "Reagent row visible for un-scrolled drill check")
    topReagBtn:Click("LeftButton")
    drain()
    DA.header.returnBtn:Click("LeftButton")
    drain()
    check((DA.GetState().scrollOffset or 0) > 0,
        "Back after un-scrolled Crafting Breakdown click jumps straight to Crafting Breakdown (offset=" .. tostring(DA.GetState().scrollOffset) .. ")")

    -- 14c. Used In Show All expansion and Used In scroll section restore cleanly on Back
    app.setTab("recipes")
    drain()
    app.openDeepAnalysis({ kind = "item", itemID = 4304, name = "Thick Leather" })
    drain()
    if left.usedInToggleBtn and left.usedInToggleBtn:IsShown() then
        left.usedInToggleBtn:Click("LeftButton")
        drain()
    end
    check(DA.GetState().usedInExpanded == true, "Thick Leather Used In expanded before drill-down")
    check(DA.usedInRows[1] and DA.usedInRows[1]:IsShown(), "Thick Leather Used In row[1] visible")
    DA.usedInRows[1]:Click("LeftButton")
    drain()
    DA.header.returnBtn:Click("LeftButton")
    drain()
    check(DA.GetState().target and DA.GetState().target.itemID == 4304
        and DA.GetState().usedInExpanded == true
        and (DA.GetState().scrollOffset or 0) > 0,
        "Back from Thick Leather Used In drill-down restores usedInExpanded and scrolls to Used In section")

    -- Restore seeded prices & dashboard state
    app.setTab("dashboard")
    drain()
    for id in pairs(extraSeed) do
        db.ahPrices[econ][id] = savedPrices[id]
        db.ahDaily[econ][id] = savedDaily[id]
    end
    ns.InvalidatePriceCache()
    if Theme.SetSkin then Theme.SetSkin(origSkin) end
    Theme.SetMode(origMode)
end

-- Restore globals
C_Timer.After = origAfter
_G.time = origTime

print(string.format("PASS: deep_analysis_ui suite (%d assertions, 0 failures)", assertions))
