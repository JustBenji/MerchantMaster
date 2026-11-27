-- Stage B chart and tooltip contract checks; UI view checks are appended by the UI owner.
local root = (((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local scratch = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local harness = assert(io.open(scratch .. "test_analytics.lua", "rb"))
local harnessSource = harness:read("*a")
harness:close()
-- Keep all original assertions visible and carry their failure count through this suite.
harnessSource = harnessSource:gsub("if #failures > 0 then error%(table%.concat%(failures,.*", "return #failures")
local priorFailures = assert(loadstring(harnessSource, "@" .. scratch .. "test_analytics.lua"))()
local ns = assert(_G.MerchantMasterAnalytics)
local hostNS = assert(_G._MM_TEST_HOST)
assert(loadfile(root .. "Analytics/Tooltips.lua"))("MerchantMaster", hostNS)
local assertions = 0
local function check(value, message)
    assertions = assertions + 1
    assert(value, "accounting ui assertion " .. assertions .. ": " .. message)
end

do
    local chart = ns.Chart.CreateLineChart(UIParent, 528, 195, { formatY = tostring })
    local points = {}
    for i = 1, 12 do points[i] = { day = "D" .. i, value = i } end
    chart:SetData({ { name = "Gold", points = points } })
    check(#chart._grids == 48, "grid dash textures are retained for all three rows")
    local beforeWidth = chart._grids[1]:GetWidth()
    chart:Layout(900, 500)
    check(chart.plotWidth == 806 and chart.plotHeight == 434, "Layout updates plot dimensions")
    check(chart._grids[1]:GetWidth() > beforeWidth, "Layout resizes retained grid textures")
    local cursor = 200
    _G.GetCursorPosition = function() return cursor, 0 end
    chart.plot:GetScript("OnMouseDown")(chart.plot)
    cursor = 200 + chart.plotWidth * 0.7
    chart.plot:GetScript("OnMouseUp")(chart.plot)
    check(chart._zoomRange and chart._zoomRange[2] - chart._zoomRange[1] >= 2, "drag selects a range spanning at least two points")
    check(chart.resetZoom:IsShown(), "zoom reveals Reset Zoom control")
    local rawPoints = {}
    for i = 1, 100 do rawPoints[i] = { day = "P" .. i, value = i } end
    local lineChart = ns.Chart.CreateLineChart(UIParent, 528, 195, { formatY = tostring })
    lineChart:SetData({ { name="Long", points=rawPoints } })
    local left = lineChart.plot:GetLeft() or 0
    cursor = left + lineChart.plotWidth * 0.1; lineChart.plot:GetScript("OnMouseDown")(lineChart.plot, "LeftButton")
    cursor = left + lineChart.plotWidth * 0.8; lineChart.plot:GetScript("OnMouseUp")(lineChart.plot, "LeftButton")
    check(lineChart._zoomRange and lineChart._zoomRange[2] - lineChart._zoomRange[1] >= 2, "100-point line chart supports range zoom")
    local rawBars = {}; for i=1,60 do rawBars[i]={day="B"..i,value=i} end
    local barChart = ns.Chart.CreateBarChart(UIParent, 528, 195, { formatY=tostring })
    barChart:SetData(rawBars)
    left = barChart.plot:GetLeft() or 0
    cursor = left + barChart.plotWidth * 0.1; barChart.plot:GetScript("OnMouseDown")(barChart.plot,"LeftButton")
    cursor = left + barChart.plotWidth * 0.8; barChart.plot:GetScript("OnMouseUp")(barChart.plot,"LeftButton")
    check(barChart._zoomRange and barChart._rawPointCount==60, "60-bar chart zoom retains the unsampled raw input")
    local beforeZoomCount = barChart._rawPointCount
    barChart:Layout(900,500)
    check(barChart._rawPointCount==beforeZoomCount and barChart._zoomRange~=nil, "chart layout resize preserves zoom and every raw bar")
    barChart.resetZoom:GetScript("OnClick")(barChart.resetZoom)
    check(barChart._rawPointCount==60 and barChart._zoomRange==nil, "Reset Zoom restores all 60 unsampled bars")
    local noZoom = ns.Chart.CreateLineChart(UIParent,528,195,{formatY=tostring})
    noZoom:SetData({{name="x",points=rawPoints}})
    cursor=0; noZoom.plot:GetScript("OnMouseDown")(noZoom.plot,"RightButton"); cursor=200
    noZoom.plot:GetScript("OnMouseUp")(noZoom.plot,"RightButton")
    check(noZoom._zoomRange==nil, "right-button drag does not zoom")
    noZoom:Clear(); noZoom:Layout(900,500)
    check(noZoom.empty:IsShown() and noZoom._rawPointCount==0, "empty chart stays empty after layout")
    chart.resetZoom:GetScript("OnClick")(chart.resetZoom)
    check(chart._zoomRange == nil and not chart.resetZoom:IsShown() and chart._rawPointCount == 12, "reset restores the full series")
end

do
    local tooltip = CreateFrame("GameTooltip", nil, UIParent)
    -- This formatting fixture executes deferred work immediately; the real timer/host
    -- contract (including cold misses) is exercised by bench_mm_perf.lua.
    local oldTooltipTimer=_G.C_Timer
    _G.C_Timer={After=function(_,fn) fn() end}
    local model, inventory = ns.Model, ns.Inventory
    local apiNS = hostNS
    local oldFormat = apiNS.FormatMoneyCompact
    apiNS.FormatMoneyCompact = function(value) return tostring(value) end
    local oldDB, oldShift = _G.MerchantMasterDB, _G.IsShiftKeyDown
    _G.MerchantMasterDB = { anTooltips = true, anTooltipInventory = true }
    _G.IsShiftKeyDown = function() return false end
    tooltip.GetItem = function() return "Sample Item", "|Hitem:12345::::::::|h[Sample Item]|h" end
    tooltip.GetTooltipData = function() return { stackCount = 4 } end
    ns.Model = {
        GetPriceSource = function(key)
            return ({ AvgSell = 300, AvgBuy = 100, CurBasis = 80, AvgProfit = 150, SaleRate = 1, NumExpires = 5 })[key]
        end,
        GetItemStats = function() return { minSell = 250, maxSell = 350, lastSoldUnit = 275 } end,
        GetSaleHint = function() return { isSlowing = true, expSinceSale = 5 } end,
    }
    ns.Inventory = { GetItemBreakdown = function()
        return { total = 9, byChar = { { char = "Mage-Realm", shortName = "Mage", bags = 2, bank = 3, mail = 1,
            inTransit = 1, ah = 2, updatedAt = time() - 1, stale = true } } }
    end }
    local function clearTooltip()
        tooltip:ClearLines()
        local onCleared = tooltip:GetScript("OnTooltipCleared")
        if onCleared then onCleared(tooltip) end
    end
    check(ns.Tooltips.OnTooltipItem(tooltip), "accounting tooltip resolves item ID from GetItem hyperlink")
    local function lines()
        return table.concat(tooltip._lines or {}, "\n")
    end
    local once = lines()
    local onceCount = tooltip:NumLines()
    check(once:find("Avg Sell", 1, true) and once:find("Slowing", 1, true), "tooltip shows sell price and slowing hint")
    check(once:find("Mage (stale)", 1, true) and once:find("Total Inventory", 1, true), "tooltip shows stale per-character inventory and total")
    check(once:find("1%", 1, true), "sale rate uses the 0-to-100 export convention")
    ns.Tooltips.OnTooltipItem(tooltip)
    check(tooltip:NumLines() == onceCount, "repeated callback for the same item does not duplicate accounting lines")
    _G.IsShiftKeyDown = function() return true end
    clearTooltip()
    ns.Tooltips.OnTooltipItem(tooltip)
    local stacked = lines()
    check(stacked:find("x4", 1, true) and stacked:find("1200", 1, true), "shift tooltip multiplies unit prices by stack size")
    check(stacked:find("1000 / 1400", 1, true) and stacked:find("Last Sold", 1, true), "min, max, and last sold unit prices use the stack multiplier")
    clearTooltip()
    ns.Tooltips.OnTooltipItem(tooltip)
    check(tooltip:NumLines() == onceCount, "recycled tooltip adds the same number of lines")
    clearTooltip()
    tooltip.GetItem = function() return nil, nil end
    tooltip.GetTooltipData = function() return {} end
    check(not ns.Tooltips.OnTooltipItem(tooltip, nil, 1) and tooltip:NumLines() == 0, "unresolved IDs add no lines")
    local secret = {}
    local oldSecret = _G.issecretvalue
    _G.issecretvalue = function(value) return value == secret end
    check(not ns.Tooltips.OnTooltipItem(tooltip, secret, 1) and tooltip:NumLines() == 0, "secret IDs are ignored without coercion")
    check(not ns.Tooltips.OnTooltipItem(tooltip, "unrecognized") and not ns.Tooltips.OnTooltipItem(tooltip, {})
        and not ns.Tooltips.OnTooltipItem(tooltip, false), "invalid item ID types are ignored safely")
    clearTooltip()
    check(ns.Tooltips.OnTooltipItem(tooltip, "item:12345") and tooltip:NumLines()>0, "item hyperlink argument resolves to its numeric ID")
    clearTooltip()
    _G.issecretvalue = oldSecret
    local oldSecretTable, oldContainer = _G.issecrettable, _G.C_Container
    local bagOwner = { GetBagID=function() return 0 end, GetID=function() return 2 end }
    tooltip.GetOwner=function() return bagOwner end
    tooltip.GetItem=function() return nil,nil end
    tooltip.GetTooltipData=function() return {} end
    _G.C_Container={GetContainerItemInfo=function(bag,slot)
        check(bag==0 and slot==2, "tooltip stack fallback queries owner bag and slot")
        return {itemID=12345,stackCount=7}
    end}
    _G.IsShiftKeyDown=function() return true end
    clearTooltip()
    check(ns.Tooltips.OnTooltipItem(tooltip) and lines():find("x7",1,true), "owner lookup resolves item and uses bag stack count")
    local poisonedOwner=setmetatable({}, {__index=function() error("secret owner access") end})
    tooltip.GetOwner=function() return poisonedOwner end
    _G.issecrettable=function(value) return value==poisonedOwner end
    clearTooltip()
    check(not ns.Tooltips.OnTooltipItem(tooltip) and tooltip:NumLines()==0, "secret owner parent is ignored safely")
    local oldBreakdown=ns.Inventory.GetItemBreakdown
    local poisonedInventory=setmetatable({}, {__index=function() error("secret inventory access") end})
    ns.Inventory.GetItemBreakdown=function() return {byChar=poisonedInventory,total=4} end
    _G.issecrettable=function(value) return value==poisonedInventory end
    tooltip.GetOwner=function() return nil end
    clearTooltip()
    local ok = pcall(ns.Tooltips.OnTooltipItem,tooltip,12345,1)
    check(ok, "secret inventory character table does not raise")
    ns.Inventory.GetItemBreakdown=oldBreakdown
    _G.issecrettable, _G.C_Container = oldSecretTable, oldContainer
    _G.MerchantMasterDB = { anTooltips = false }
    check(not ns.Tooltips.OnTooltipItem(tooltip, 12345, 1), "tooltip master toggle disables accounting lines")
    ns.Model, ns.Inventory = model, inventory
    _G.C_Timer=oldTooltipTimer
    apiNS.FormatMoneyCompact = oldFormat
    _G.MerchantMasterDB, _G.IsShiftKeyDown = oldDB, oldShift
end

do
    local captured = {}
    local tooltip = {
        GetItem = function() return "Rich Item", "|Hitem:54321::::::::|h[Rich Item]|h" end,
        GetTooltipData = function() return { stackCount = 1 } end,
        AddDoubleLine = function(_, l, r, rL, gL, bL, rR, gR, bR)
            captured[#captured + 1] = { l, r, rL, gL, bL, rR, gR, bR }
        end,
        ClearLines = function() captured = {} end,
        NumLines = function() return #captured end,
        HookScript = function(self, ev, fn)
            self._hooks = self._hooks or {}
            self._hooks[ev] = fn
        end,
    }
    local function resetTip()
        tooltip:ClearLines()
        if tooltip._hooks and tooltip._hooks.OnTooltipCleared then
            tooltip._hooks.OnTooltipCleared(tooltip)
        end
    end
    local function nearRGB(a, b)
        return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.02
    end
    local function findRow(prefix)
        for _, row in ipairs(captured) do
            if type(row[1]) == "string" and row[1]:find(prefix, 1, true) then
                return row
            end
        end
        return nil
    end

    local oldTimer = _G.C_Timer
    local oldDB = _G.MerchantMasterDB
    local oldShift = _G.IsShiftKeyDown
    local oldAlt = _G.IsAltKeyDown
    local oldModel = ns.Model
    local oldInv = ns.Inventory
    local oldFormat = hostNS.FormatMoneyCompact

    _G.C_Timer = { After = function(_, fn) fn() end }
    _G.IsShiftKeyDown = function() return false end
    _G.IsAltKeyDown = function() return false end
    hostNS.FormatMoneyCompact = function(v) return tostring(v) end

    local mockPrices = { AvgSell = 25000, AvgBuy = 12000, CurBasis = 0, AvgProfit = 10000, SaleRate = nil, NumExpires = 0 }
    ns.Model = {
        GetPriceSource = function(key) return mockPrices[key] end,
        GetItemStats = function() return { minSell = 20000, maxSell = 30000, lastSoldUnit = 24000 } end,
        GetSaleHint = function() return nil end,
    }
    ns.Inventory = {
        GetItemBreakdown = function()
            return {
                total = 8,
                byChar = {
                    { char = "Main-Realm", shortName = "Main", bags = 7, bank = 1, mail = 0, inTransit = 0, ah = 0, updatedAt = time() - 5, stale = false },
                    { char = "ZeroAlt-Realm", shortName = "ZeroAlt", bags = 0, bank = 0, mail = 0, inTransit = 0, ah = 0, updatedAt = time() - 5, stale = false },
                },
            }
        end,
    }

    -- 1. Default prefs: RGB colors, ttInvHideZero=true, ttHideEmpty=true, ttInvCompact=true
    _G.MerchantMasterDB = { anTooltips = true, anTooltipInventory = true }
    ns.Tooltips.Invalidate()
    resetTip()
    check(ns.Tooltips.OnTooltipItem(tooltip, 54321, 1) == true, "tooltip renders with default TooltipPrefs")

    local hdr = captured[1]
    check(hdr and hdr[1] == "MerchantMaster Accounting"
        and nearRGB(hdr[3], 1.00) and nearRGB(hdr[4], 0.82) and nearRGB(hdr[5], 0.00),
        "accounting tooltip line 1 uses Gold header 'MerchantMaster Accounting'")

    local avgSellRow = findRow("  Avg Sell")
    check(avgSellRow ~= nil
        and nearRGB(avgSellRow[3], 0.90) and nearRGB(avgSellRow[4], 0.92) and nearRGB(avgSellRow[5], 0.95)
        and nearRGB(avgSellRow[6], 0.96) and nearRGB(avgSellRow[7], 0.97) and nearRGB(avgSellRow[8], 0.99),
        "2-space indented accounting label uses off-white RGB")

    local mainAltRow = findRow("    Main")
    check(mainAltRow ~= nil
        and nearRGB(mainAltRow[3], 0.86) and nearRGB(mainAltRow[4], 0.72) and nearRGB(mainAltRow[5], 0.54)
        and mainAltRow[2] == "8 (7 bags, 1 bank, 0 mail, 0 AH)",
        "4-space indented alt row uses warm tan RGB and compact format '8 (7 bags, 1 bank, 0 mail, 0 AH)'")

    check(findRow("ZeroAlt") == nil, "ttInvHideZero=true hides 0-count characters by default")
    check(findRow("Current Basis") == nil and findRow("Sale Rate / Expires") == nil,
        "ttHideEmpty=true hides CurBasis=0 and nil SaleRate with 0 expires")

    -- 2. ttInvHideZero=false, ttHideEmpty=false, ttInvCompact=false
    _G.MerchantMasterDB.ttInvHideZero = false
    _G.MerchantMasterDB.ttHideEmpty = false
    _G.MerchantMasterDB.ttInvCompact = false
    resetTip()
    check(ns.Tooltips.OnTooltipItem(tooltip, 54321, 1) == true, "tooltip renders with verbose/non-hidden options")
    local zeroAltRow = findRow("    ZeroAlt")
    local mainVerbose = findRow("    Main")
    local basisRow = findRow("  Current Basis")
    local rateRow = findRow("  Sale Rate / Expires")
    check(zeroAltRow ~= nil, "ttInvHideZero=false shows 0-count alt rows")
    check(mainVerbose and mainVerbose[2] == "Bags 7, Bank 1, Mail 0, In-Transit 0, AH 0",
        "ttInvCompact=false uses verbose inventory format")
    check(basisRow ~= nil and rateRow ~= nil and rateRow[2] == "- / 0",
        "ttHideEmpty=false shows Current Basis=0 and Sale Rate / Expires='- / 0'")

    -- 3. ttPriceFormat = "icons" uses coin icon texture markup
    _G.MerchantMasterDB.ttPriceFormat = "icons"
    resetTip()
    ns.Tooltips.OnTooltipItem(tooltip, 54321, 1)
    local iconSellRow = findRow("  Avg Sell")
    check(iconSellRow ~= nil and iconSellRow[2]:find("|TInterface\\MoneyFrame\\UI-", 1, true) ~= nil,
        "ttPriceFormat='icons' renders WoW coin icon texture markup")

    -- 4. ttModifier = "alt" suppresses when Alt is not held and shows when Alt is held
    _G.MerchantMasterDB.ttModifier = "alt"
    _G.IsAltKeyDown = function() return false end
    resetTip()
    check(ns.Tooltips.OnTooltipItem(tooltip, 54321, 1) == false and #captured == 0,
        "ttModifier='alt' suppresses tooltip when Alt is not held")
    _G.IsAltKeyDown = function() return true end
    resetTip()
    check(ns.Tooltips.OnTooltipItem(tooltip, 54321, 1) == true and #captured > 0,
        "ttModifier='alt' displays tooltip when Alt is held")

    -- 5. ttEnabled = false disables all lines
    _G.MerchantMasterDB.ttEnabled = false
    resetTip()
    check(ns.Tooltips.OnTooltipItem(tooltip, 54321, 1) == false and #captured == 0,
        "ttEnabled=false disables all tooltip lines")

    ns.Model, ns.Inventory = oldModel, oldInv
    _G.C_Timer = oldTimer
    hostNS.FormatMoneyCompact = oldFormat
    _G.MerchantMasterDB = oldDB
    _G.IsShiftKeyDown = oldShift
    _G.IsAltKeyDown = oldAlt
    ns.Tooltips.Invalidate()
end

do
    local source = assert(io.open(root .. "Analytics/Chart.lua", "rb")):read("*a")
    check(not source:match('SetScript%s*%(%s*["\']On' .. "Update[" .. "']"), "Chart.lua contains no OnUpdate script")
    check(not source:find("C_Timer." .. "NewTicker", 1, true), "Chart.lua contains no repeating ticker")
    source = assert(io.open(root .. "Analytics/Tooltips.lua", "rb")):read("*a")
    check(not source:match('SetScript%s*%(%s*["\']On' .. "Update[" .. "']"), "Tooltips.lua contains no OnUpdate script")
    check(not source:find("C_Timer." .. "NewTicker", 1, true), "Tooltips.lua contains no repeating ticker")
end

do
    local ui = assert(ns.UI)
    local core = 0
    for _ in pairs(ui.tables or {}) do core = core + 1 end
    check(core == 8, "analytics keeps exactly eight core sortable tables")
    check(type(ui.auxTables) == "table", "auxiliary item tables have a separate registry")
    check(#ui.GetSidebarControls("an_ledger") == 5 or #ui.GetSidebarControls("an_ledger") == 6,
        "ledger toolbar additions preserve sidebar control contract")
    check(ui.Columns.an_items[2].key == "profit", "Profit remains second in default item columns")
    local avgBuyColumn; for _,col in ipairs(ui.Columns.an_items) do if col.key=="avgBuy" then avgBuyColumn=col end end
    check(avgBuyColumn and avgBuyColumn.render({avgBuy=nil})=="-", "missing average buy prices render as unavailable instead of zero")
    local total = 0
    for _, col in ipairs(ui.Columns.an_ledger) do total = total + col.width + 5 end
    check(total <= 1048, "ledger columns fit the default width")
    total = 0
    for _, col in ipairs(ui.Columns.an_items) do total = total + col.width + 5 end
    check(total <= 1048, "item columns fit the default width")
    local window = hostNS.Window
    check(window and ui.content, "window layout integration is registered with the analytics content")
    if window and ui.content then
        local overview = ui.views.an_overview
        if overview and overview.profit then
            overview:Show()
            window.LayoutAnalytics(ns, 1320)
            check(overview.profit.plotWidth == 560, "minimum window width produces the expected chart plot width")
            window.LayoutAnalytics(ns, 1920)
            check(overview.profit.plotWidth == 860, "maximum window width produces the expected chart plot width")
        end
        for _, tab in ipairs({"an_overview","an_ledger","an_items","an_portfolio","an_invest","an_writs"}) do
            local v=ui.views[tab]
            if v then v:Show(); window.LayoutAnalytics(ns,1320); window.LayoutAnalytics(ns,1920) end
        end
        window.LayoutAnalytics(ns, 1320)
        window.LayoutAnalytics(ns, 1920)
        local hostApp=hostNS.app
        check(hostApp and hostApp.layoutWindow and hostApp.panel, "host panel exposes the live analytics resize path")
        if hostApp and hostApp.layoutWindow and hostApp.panel then
            local oldActive, oldW, oldH = hostApp.activeTab, hostApp.panel:GetWidth(), hostApp.panel:GetHeight()
            hostApp.panel:Show()
            for _, size in ipairs({{1320,730},{1920,1200}}) do
                hostApp.panel:SetSize(size[1],size[2])
                for _, tab in ipairs({"an_overview","an_ledger","an_items","an_portfolio","an_invest","an_writs"}) do
                    hostApp.activeTab=tab
                    local v=ui.views[tab]; if v then v:Show() end
                    hostApp.layoutWindow()
                end
            end
            hostApp.activeTab=oldActive
            if oldW and oldH then hostApp.panel:SetSize(oldW,oldH) end
        end
        local tbl = ui.tables.an_items
        if tbl and window.LayoutTable then
            window.LayoutTable(tbl, 1320, 0)
            local minRight = tbl.colX[#tbl.columns] + tbl.columns[#tbl.columns].width
            window.LayoutTable(tbl, 1920, 0)
            local maxRight = tbl.colX[#tbl.columns] + tbl.columns[#tbl.columns].width
            check(minRight <= 1320 and maxRight <= 1920, "sortable columns stay inside both supported window widths")
        end
    end
    local items = ui.views.an_items
    if items then
        check(items.preset and items.sales and items.purchases and items.expired and items.slow,
            "item presets expose resale, sales, purchases, expired, and slowing views")
        check(items.source and items.faction and items.chars and items.group and items.rarity,
            "item toolbar exposes source, faction, character, grouping, and rarity filters")
        local oldOptional = MerchantMasterDB.anItemOptional
        ui.ShowColumnPicker()
        check(ui.columnChoices and ui.columnChoices.avgProfit and ui.choiceMenu:IsShown(), "optional column picker opens")
        ui.columnChoices.avgProfit:GetScript("OnClick")(ui.columnChoices.avgProfit)
        check(#ui.tables.an_items.columns > #ui.Columns.an_items, "optional column selection rebuilds the item table")
        MerchantMasterDB.anItemOptional = oldOptional; ui.RebuildItemColumns()
        ui.ShowColumnPicker()
        ui.columnChoices.bought:GetScript("OnClick")(ui.columnChoices.bought)
        local hasBought=false; for _,col in ipairs(ui.tables.an_items.columns) do if col.key=="bought" then hasBought=true end end
        check(not hasBought, "column picker can hide a default core metric")
        ui.ShowColumnPicker(); ui.widthModeButton:GetScript("OnClick")(ui.widthModeButton)
        check(MerchantMasterDB.anItemWidthMode=="Wide", "column picker exposes a width preset")
        ui.ShowColumnPicker(); ui.resetColumnButton:GetScript("OnClick")(ui.resetColumnButton)
        local resetBought=false; for _,col in ipairs(ui.tables.an_items.columns) do if col.key=="bought" then resetBought=true end end
        check(resetBought and MerchantMasterDB.anItemWidthMode==nil, "Reset Columns restores default visibility and widths")
        local width=0; for _,col in ipairs(ui.tables.an_items.columns) do width=width+col.width+5 end
        check(width<=1048, "item column width presets preserve the core table width budget")
        local oldDetail, requestedDetailKey = ns.Model.GetItemDetail, nil
        ns.Model.GetItemDetail = function(id)
            requestedDetailKey=id
            return { itemID=type(id)=="table" and id.itemID or id, name="Detail Item", windows={ d7={sold=2, totalSales=200}, d30={}, all={} },
                inventory={total=4,bags=1,bank=2,mail=1,byChar={{char="Alt",shortName="Alt",bags=1,bank=2,mail=1,stale=true}}},
                transactions={{eid="e1",itemID=id,time=1,type="AH_SELL",qty=1,unit=100,total=100,counterparty="Buyer"}} }
        end
        ui.ShowItemDetail(123)
        check(items.detail:IsShown() and items.detail.history, "item detail opens with its auxiliary transaction history table")
        check(items.detail.body:GetText():find("Cross%-Alt Inventory"), "detail includes cross-character inventory")
        ui.OpenItemRow({itemID=321,name="Variant Item",variant="suffix:42",itemLevel=23},"an_items","LeftButton")
        check(type(requestedDetailKey)=="table" and requestedDetailKey.itemID==321 and requestedDetailKey.variant=="suffix:42"
            and ui.detailKey.variant=="suffix:42", "clicking a specific-group row opens that exact item variant")
        check(#items.detail.history.scrollBox._dp:GetCollection()==1, "variant detail displays its transaction history")
        ns.Model.GetItemDetail = oldDetail
        ui.ShowCorrection({eid="e1"})
        check(ui.modal:IsShown(), "transaction correction opens a confirmation modal")
        local oldCorrect, corrected = ns.Store.Correct, nil
        ns.Store.Correct = function(eid, request) corrected = eid .. ":" .. request.action; return {ok=true} end
        ui.correctionConfirm:GetScript("OnClick")(ui.correctionConfirm)
        check(corrected == "e1:delete", "transaction delete confirmation calls Store.Correct")
        do
            local hostApp=hostNS.app
            local oldRefresh,oldCompute,oldDetailFn=hostApp.refresh,ns.Model.Compute,ns.Model.GetItemDetail
            local removed,detailKeySeen=false,nil
            ns.Model.Compute=function() return {rows={}} end
            ns.Model.GetItemDetail=function(key)
                detailKeySeen=key
                return {itemID=321,name="Variant Item",windows={d7={},d30={},all={}},transactions=removed and {} or
                    {{eid="remove-me",itemID=321,time=2,type="AH_SELL",qty=1,unit=10,total=10}}}
            end
            hostApp.refresh=function() ui.Refresh("an_items",ui.content) end
            ui.ShowItemDetail({itemID=321,variant="suffix:42"})
            ns.Store.Correct=function() removed=true; return {ok=true} end
            ui.ShowCorrection({eid="remove-me"}); ui.correctionConfirm:GetScript("OnClick")(ui.correctionConfirm)
            check(type(detailKeySeen)=="table" and detailKeySeen.variant=="suffix:42", "successful correction refreshes detail with the same variant key")
            check(#items.detail.history.scrollBox._dp:GetCollection()==0, "deleted transaction disappears from refreshed detail history")
            hostApp.refresh,ns.Model.Compute,ns.Model.GetItemDetail=oldRefresh,oldCompute,oldDetailFn
        end
        ns.Store.Correct=function() return {ok=false,err="blocked"} end
        ui.ShowCorrection({eid="e2"}); ui.correctionConfirm:GetScript("OnClick")(ui.correctionConfirm)
        check(ui.modal:IsShown() and ui.modal.edit:GetText():find("blocked",1,true), "failed correction remains visible with its error")
        ui.correctionCancel:GetScript("OnClick")(ui.correctionCancel)
        ui.ShowCorrection({eid="group",rawEventIDs={"e1","e2"}})
        check(not ui.correctionConfirm:IsEnabled(), "grouped ledger rows cannot delete a single event")
        ui.correctionCancel:GetScript("OnClick")(ui.correctionCancel)
        ns.Store.Correct = oldCorrect
    end
    local oldPortfolioView = MerchantMasterDB.anPortfolioView
    MerchantMasterDB.anPortfolioView = "inventory"
    if ui.content and hostNS and hostNS.app then
        ui.Refresh("an_portfolio", ui.content)
        local portfolio = ui.views.an_portfolio
        check(portfolio.inventoryPane:IsShown() and portfolio.inventoryTable, "portfolio item inventory view opens")
        check(ui.auxTables.an_inventory_matrix ~= nil, "inventory matrix table is auxiliary")
    end
    MerchantMasterDB.anPortfolioView = oldPortfolioView
    local oldCompute,oldQuery,oldHint=ns.Model.Compute,ns.Model.QueryLedger,ns.Model.GetSaleHint
    local oldIntradayPeriod=MerchantMasterDB.anPeriod; MerchantMasterDB.anPeriod="today"
    local hintCalls,logCalls=0,0
    ns.Model.Compute=function() return {kpis={profit=100,sales=200,purchases=50,depLost=0,lootValue=0,wealthChange=10,unexplained=0,
        avgDailyProfit=10,avgDailySales=20,avgDailyPurchases=5,prevProfit=80,profitDeltaPct=25,prevSales=100,salesDeltaPct=100,
        prevPurchases=25,purchasesDeltaPct=100,high52w=1000,low52w=100},top={{itemID=77,name="Hint Item"}},wealth={},profitByDay={},activityFeed={},
        intradayWealth={{label="12:34",time=time(),gold=100,items=40,listed=20,total=160}}} end
    ns.Model.GetSaleHint=function() hintCalls=hintCalls+1; return {action="reprice",reason="Test reason",expSinceSale=3,isSlowing=false} end
    ns.Model.QueryLedger=function(filters,cursor,limit)
        logCalls=logCalls+1
        check(filters.types and filters.types.AUCTION_LOG and cursor==0 and limit==5,"activity drawer queries a bounded auction-log slice")
        return {rows={{charShort="Main",type="AUCTION_LOG",extra={action="Reprice",reason="Undercut"}}}}
    end
    ui.Refresh("an_overview",ui.content)
    check(ui.views.an_overview.kpis[1].value:GetText():find("Avg/Day",1,true), "overview displays pace from nested KPI metrics")
    check(ui.views.an_overview.kpis[1].tip:find("+25.0%",1,true), "overview renders the model percentage delta without multiplying it")
    local wealthChart=ui.views.an_overview.wealth
    check(wealthChart.title:GetText():find("Intraday",1,true) and #wealthChart._inputSeries==4,
        "today wealth chart uses intraday points and the four selectable storage series")
    check(wealthChart._rawCategories[1]:match("^%d%d:%d%d$"),"intraday wealth labels use readable hour and minute times")
    MerchantMasterDB.anPeriod="30d"; ui.Refresh("an_overview",ui.content)
    check(not wealthChart.title:GetText():find("Intraday",1,true),"a historical period keeps the daily wealth graph even when today's intraday points exist")
    MerchantMasterDB.anPeriod="today"
    check(hintCalls==0 and logCalls==0,"sale diagnostics do no extra model work while the activity drawer is closed")
    local hostApp=hostNS.app; local oldRefresh=hostApp.refresh; hostApp.refresh=function() end
    ui.views.an_overview.seriesButton:GetScript("OnClick")(ui.views.an_overview.seriesButton)
    ui.seriesChoices.total:GetScript("OnClick")(ui.seriesChoices.total)
    ui.Refresh("an_overview",ui.content)
    local hasTotal=false; for _,serie in ipairs(wealthChart._inputSeries) do if serie.name=="Total" then hasTotal=true end end
    check(not hasTotal,"wealth series menu toggles displayed graph series")
    MerchantMasterDB.anWealthSeries=nil
    MerchantMasterDB.anShowActivity=true; ui.Refresh("an_overview",ui.content)
    check(hintCalls>0 and logCalls>0 and ui.views.an_overview.feed:GetText():find("Reprice: Undercut",1,true),
        "open activity drawer shows bounded sale hints and recent auction action/reason diagnostics")
    MerchantMasterDB.anShowActivity=nil; hostApp.refresh=oldRefresh
    ns.Model.Compute,ns.Model.QueryLedger,ns.Model.GetSaleHint=oldCompute,oldQuery,oldHint
    MerchantMasterDB.anPeriod=oldIntradayPeriod
    ui.ShowSettings()
    check(ui.settingsActions and ui.settingsActions.prune and ui.settingsActions.import and ui.settingsActions.export and ui.settingsActions.csv,
        "accounting settings expose prune, import, export, and CSV actions")
    check(ui.settingsActions.retention~=nil, "accounting settings expose a retention selector")
    MerchantMasterDB.anRetentionDays=90; ui.settingsActions.retention:GetScript("OnClick")(ui.settingsActions.retention)
    check(MerchantMasterDB.anRetentionDays==180, "retention selector chooses 180 days")
    ui.settingsActions.retention:GetScript("OnClick")(ui.settingsActions.retention)
    check(MerchantMasterDB.anRetentionDays==365, "retention selector chooses 365 days")
    ui.settingsActions.retention:GetScript("OnClick")(ui.settingsActions.retention)
    check(MerchantMasterDB.anRetentionDays==90, "retention selector cycles back to 90 days")
    ui.settingsActions.prune:GetScript("OnClick")(ui.settingsActions.prune)
    check(ui.prunePreview and ui.pruneConfirm and ui.pruneCancel, "prune displays preview and confirm/cancel controls")
    local oldPrune, oldPreview, pruned, previewCutoff = ns.Store.PruneBefore, ns.Store.PreviewPrune, nil, nil
    ns.Store.PreviewPrune=function(day) previewCutoff=day; return {ok=true,rowsToPrune=3,daysToPrune=2,estBytesAfter=10} end
    ui.settingsActions.prune:GetScript("OnClick")(ui.settingsActions.prune)
    check(type(previewCutoff)=="string" and previewCutoff:match("^%d%d%d%d%-%d%d%-%d%d$"), "prune preview receives a concrete ISO date cutoff")
    ns.Store.PruneBefore = function(day) pruned=day; return {ok=true} end
    ui.pruneConfirm:GetScript("OnClick")(ui.pruneConfirm)
    check(pruned ~= nil, "prune confirmation calls Store.PruneBefore")
    ns.Store.PreviewPrune=function() return {ok=false,err="preview blocked"} end
    ui.settingsActions.prune:GetScript("OnClick")(ui.settingsActions.prune)
    check(not ui.pruneConfirm:IsEnabled(), "failed prune preview disables the destructive confirmation")
    check(ui.modal.edit:GetText():find("preview blocked",1,true), "failed prune preview reports its error")
    ui.settingsActions.prune:GetScript("OnClick")(ui.settingsActions.prune)
    ui.pruneCancel:GetScript("OnClick")(ui.pruneCancel)
    check(not ui.modal:IsShown(), "prune cancel closes the preview without pruning")
    ns.Store.PruneBefore, ns.Store.PreviewPrune = oldPrune, oldPreview
    local oldExport, oldCsv, oldImport = ns.Transfer.ExportBundle, ns.Store.Export, ns.Transfer.Import
    ns.Transfer.ExportBundle = function() return "MMX1:test" end
    ns.Store.Export = function() return "header\nrow" end
    ns.Transfer.Import = function(payload) return {ok=payload=="MMX1:input",imported=1,skipped=0} end
    ui.settingsActions.export:GetScript("OnClick")(ui.settingsActions.export)
    check(ui.modal.edit:GetText()=="MMX1:test", "transfer export opens a copyable bundle modal")
    ui.settingsActions.csv:GetScript("OnClick")(ui.settingsActions.csv)
    check(ui.modal.edit:GetText():find("header",1,true), "CSV action opens a copyable ledger modal")
    ui.settingsActions.import:GetScript("OnClick")(ui.settingsActions.import)
    ui.lastModalEdit:SetText("MMX1:input")
    ui.importConfirm:GetScript("OnClick")(ui.importConfirm)
    check(ui.lastModalEdit:GetText():find("Imported 1",1,true), "transfer import validates and reports imported rows")
    ns.Transfer.ExportBundle, ns.Store.Export, ns.Transfer.Import = oldExport, oldCsv, oldImport
    do
        local oldQuery=ns.Model.QueryLedger
        local oldZone,oldOffset=MerchantMasterDB.anZone,MerchantMasterDB.anLedgerOffset
        local queryArgs
        ns.Model.QueryLedger=function(filters,cursor,limit)
            queryArgs={zone=filters.zone,cursor=cursor,limit=limit}
            return {rows={{itemName="Zone Sale",type="AH_SELL",qty=1,total=50},
                {itemName="Aggregate Loot",type="LOOT",qty=2,total=20}},totalMatched=2}
        end
        MerchantMasterDB.anZone="Elwynn"; MerchantMasterDB.anLedgerOffset=500
        ui.views.an_ledger.csv:GetScript("OnClick")(ui.views.an_ledger.csv)
        local exported=ui.modal.edit:GetText()
        check(queryArgs and queryArgs.zone=="Elwynn" and queryArgs.cursor==0 and queryArgs.limit==math.huge,
            "ledger CSV requests the full filtered query regardless of current page")
        check(exported:find("Zone Sale",1,true) and exported:find("Aggregate Loot",1,true),
            "ledger CSV includes zone-matched transactions and synthetic aggregate loot")
        ns.Model.QueryLedger=oldQuery; MerchantMasterDB.anZone,MerchantMasterDB.anLedgerOffset=oldZone,oldOffset
    end
    local hostApp=hostNS.app; local oldSet,oldToggle=hostApp.setActiveShoppingList,hostApp.toggleShoppingWindow
    local sent,opened=nil,false
    hostApp.setActiveShoppingList=function(rows) sent=rows end; hostApp.toggleShoppingWindow=function(show) opened=show==true end
    local oldCompute,oldMode,oldSort=ns.Model.Compute,MerchantMasterDB.anItemMode,hostApp.sortState.an_items
    MerchantMasterDB.anItemMode="profit"
    ns.Model.Compute=function() return {rows={{itemID=111,name="Lower Profit",profit=10,bought=1,avgBuy=20},
        {itemID=222,name="Higher Profit",profit=90,bought=2,avgBuy=30}}} end
    hostApp.sortState.an_items={col="profit",asc=false}
    ui.Refresh("an_items",ui.content)
    check(ui.lastItemRows[1].itemID==222,"Send Top source rows follow the table's descending profit order")
    items.shop:GetScript("OnClick")(items.shop)
    check(sent and sent[1].itemID==222 and opened, "Send Top adds the displayed top item to the shopping list")
    hostApp.sortState.an_items={col="profit",asc=true}; ui.Refresh("an_items",ui.content); sent=nil
    items.shop:GetScript("OnClick")(items.shop)
    check(sent and sent[1].itemID==111,"Send Top respects ascending header sort as well")
    sent=nil; ui.selectedItem={itemID=456,name="Selected Item",bought=1,avgBuy=10}
    items.shopSelected:GetScript("OnClick")(items.shopSelected)
    check(sent and sent[1].itemID==456, "Send Selected adds the selected item to the shopping list")
    ns.Model.Compute,MerchantMasterDB.anItemMode,hostApp.sortState.an_items=oldCompute,oldMode,oldSort
    hostApp.setActiveShoppingList,hostApp.toggleShoppingWindow=oldSet,oldToggle
end

do
    local model, host = ns.Model, hostNS
    local oldGet = host.Pricing.GetAccountingPrice
    host.Pricing.GetAccountingPrice=function(key,id) return key=="AvgSell" and id==54321 and 1234 or nil end
    check(MerchantMasterAPI.GetAccountingPrice("AvgSell",54321)==1234, "host pricing bridge forwards supported accounting price keys")
    check(MerchantMasterAPI.GetAccountingPrice({},54321)==nil and MerchantMasterAPI.GetAccountingPrice("AvgSell",{})==nil,
        "host pricing bridge rejects invalid source and item arguments")
    local secretValue={}; local oldSecret=_G.issecretvalue
    _G.issecretvalue=function(value) return value==secretValue end
    check(MerchantMasterAPI.GetAccountingPrice("AvgSell",secretValue)==nil, "host pricing bridge rejects secret item IDs")
    _G.issecretvalue=oldSecret; host.Pricing.GetAccountingPrice=oldGet
    local app=host.app; local box=app and app.ui and app.ui.searchBox
    if box and app.panel and MerchantMasterAPI.AllowItemInsert then
        local oldShown, oldFocus, oldShift=app.panel:IsShown(), box.HasFocus, _G.IsShiftKeyDown
        local oldText=box:GetText()
        app.panel:Show(); box.HasFocus=function() return true end; _G.IsShiftKeyDown=function() return true end
        check(MerchantMasterAPI.AllowItemInsert("|Hitem:54321::::::::|h[Linked Item]|h"), "focused search accepts a shifted item link")
        check(box:GetText()=="Linked Item", "shifted link inserts its plain item name")
        box.HasFocus=function() return false end
        check(not MerchantMasterAPI.AllowItemInsert("|Hitem:54321::::::::|h[Linked Item]|h"), "unfocused search ignores item links")
        box.HasFocus=function() return true end; _G.IsShiftKeyDown=function() return false end
        check(not MerchantMasterAPI.AllowItemInsert("|Hitem:54321::::::::|h[Linked Item]|h"), "unshifted item link is ignored")
        _G.IsShiftKeyDown=function() return true end; app.panel:Hide()
        check(not MerchantMasterAPI.AllowItemInsert("|Hitem:54321::::::::|h[Linked Item]|h"), "hidden analytics panel ignores item links")
        if oldShown then app.panel:Show() end; box.HasFocus=oldFocus; _G.IsShiftKeyDown=oldShift; box:SetText(oldText or "")
    else check(false, "host search exposes AllowItemInsert integration") end
    local tooltip=GameTooltip
    if tooltip and tooltip.GetScript then
        local callback=tooltip:GetScript("OnTooltipSetItem")
        if callback then
            local analyticTooltips=ns.Tooltips; local received=0
            ns.Tooltips={OnTooltipItem=function() received=received+1 end}
            tooltip.GetItem=function() return "Plain Item", "|Hitem:54321::::::::|h[Plain Item]|h" end
            callback(tooltip)
            check(received==1, "host item tooltip callback reaches accounting lines without crate bundles")
            ns.Tooltips=analyticTooltips
        else check(false, "host item tooltip hook is installed") end
    end
    ns.Model=model
end

do
    local ui,hostApp=ns.UI,hostNS.app
    local oldCreate,oldRefresh,oldActive=CreateFrame,hostApp.refresh,hostApp.activeTab
    local oldChars,oldSelected,oldOffset,oldScope=MerchantMasterDB.chars,MerchantMasterDB.anChars,MerchantMasterDB.anLedgerOffset,ui._ledgerScope
    MerchantMasterDB.chars={['Regression-A']={name='Selection Regression'}}
    MerchantMasterDB.anChars={['Regression-A']=true}; hostApp.activeTab='an_ledger'; hostApp.refresh=function() end
    local made={}
    CreateFrame=function(...) local widget=oldCreate(...); made[#made+1]=widget; return widget end
    ui.ShowCharPicker(); CreateFrame=oldCreate
    local deselect
    for _,widget in ipairs(made) do if widget.GetText and widget:GetText()=='[x] Char: Selection Regression' then deselect=widget end end
    check(deselect~=nil,'selected character is available in the picker')
    deselect:GetScript('OnClick')(deselect)
    check(MerchantMasterDB.anChars==nil,'deselecting final character deletes its key and returns to All')
    local oldQuery=ns.Model.QueryLedger; local cursor
    ns.Model.QueryLedger=function(filters,page) cursor=page; return {rows={},totalMatched=2000} end
    MerchantMasterDB.anChars={['Regression-A']=true}; ui.Refresh('an_ledger',ui.content)
    MerchantMasterDB.anLedgerOffset=500; ui.Refresh('an_ledger',ui.content)
    check(cursor==500,'same character scope retains ledger page')
    MerchantMasterDB.anChars={['Regression-B']=true}; ui.Refresh('an_ledger',ui.content)
    check(cursor==0 and MerchantMasterDB.anLedgerOffset==0,'changing selected characters resets ledger page')
    MerchantMasterDB.anChars={['Regression-B']=true,['Regression-A']=true}; ui.Refresh('an_ledger',ui.content)
    MerchantMasterDB.anLedgerOffset=500
    MerchantMasterDB.anChars={['Regression-A']=true,['Regression-B']=true,ignored=false}; ui.Refresh('an_ledger',ui.content)
    check(cursor==500,'character scope is sorted and excludes deselected keys')
    ns.Model.QueryLedger=oldQuery; hostApp.refresh,hostApp.activeTab=oldRefresh,oldActive
    MerchantMasterDB.chars,MerchantMasterDB.anChars,MerchantMasterDB.anLedgerOffset,ui._ledgerScope=oldChars,oldSelected,oldOffset,oldScope
end

do
    local ui, hostApp = ns.UI, hostNS.app
    local oldTab, oldRefresh = hostApp.activeTab, hostApp.refresh
    local oldSeries = MerchantMasterDB.anWealthSeries
    hostApp.activeTab = "an_overview"
    hostApp.refresh = function() end
    MerchantMasterDB.anWealthSeries = { total = false, gold = false, items = false, listed = false }
    ui.ShowWealthSeriesMenu()
    ui.ResetFilters()
    local enabled = MerchantMasterDB.anWealthSeries
    check(ui.seriesMenu and not ui.seriesMenu:IsShown(), "overview reset dismisses the wealth series menu")
    check(enabled.total and enabled.gold and enabled.items and enabled.listed, "overview reset enables all chart series")
    hostApp.activeTab, hostApp.refresh = oldTab, oldRefresh
    MerchantMasterDB.anWealthSeries = oldSeries
end

do
    local chart = ns.Chart.CreateLineChart(UIParent, 528, 195)
    local pts = {}
    for i = 1, 15 do pts[i] = { day = string.format("2026-11-%02d", i + 5), value = i * 25000 } end
    chart:SetData({ { name = "Gold", points = pts } })
    check(#chart._yAxisLabels >= 3 and chart._yAxisLabels[1]:GetText():find("g", 1, true), "money chart renders nice-step Y ticks with compact gold units")
    check(#chart._xAxisLabels >= 3 and chart._xAxisLabels[1]:GetText() == "Nov 06", "ISO dates format as readable month-day labels on X axis")
    chart._hits[5]:GetScript("OnEnter")(chart._hits[5])
    check(chart._hoverLine:IsShown() and chart._hoverDot:IsShown() and chart._hoverText:IsShown(), "hovering a chart slice shows crosshair, dot, and floating readout")
    chart._hits[5]:GetScript("OnLeave")(chart._hits[5])
    check(not chart._hoverLine:IsShown() and not chart._hoverDot:IsShown(), "leaving a chart slice hides crosshair and dot")

    local ui = ns.UI
    local ov = ui.views.an_overview
    check(ov and ov.tsmSummary and ov.periodBtns and #ov.periodBtns == 5, "overview includes TSM summary panel and 5 quick period buttons")
    local led = ui.views.an_ledger
    check(led and led.presetBtns and #led.presetBtns == 9 and led.footerBar, "ledger includes 9 quick preset pills and centered footer bar")
    local oldPreset = MerchantMasterDB.anLedgerPreset
    MerchantMasterDB.anLedgerPreset = "sales"
    local f = ui.Filters()
    check(f.types and f.types.AH_SELL and not f.types.AH_BUY, "sales preset filters to sale transaction types")
    MerchantMasterDB.anLedgerPreset = "craft"
    f = ui.Filters()
    check(f.types and f.types.CRAFT and f.types.DESTROY and f.types.DISENCHANT_BROKEN and f.types.DISENCHANT_RECEIVE and not f.types.AH_SELL, "craft preset filters to craft, destroy, and disenchant types")
    MerchantMasterDB.anLedgerPreset = "trade"
    f = ui.Filters()
    check(f.types and f.types.TRADE_BUY and f.types.TRADE_SELL and not f.types.AH_SELL, "trade preset filters to trade buy and trade sell types")
    MerchantMasterDB.anLedgerPreset = "loot"
    f = ui.Filters()
    check(f.types and f.types.LOOT and f.types.GATHER and f.types.MONEY_LOOT and not f.types.AH_SELL, "loot preset filters to loot and gather types")
    MerchantMasterDB.anLedgerPreset = "expired"
    f = ui.Filters()
    check(f.types and f.types.AH_EXPIRE and not f.types.AH_CANCEL, "expired preset filters to expired auctions")

    -- Verify trade preset & craft preset query filtering (including Trade gold transfer vs Mail gold transfer)
    local oldTab = hostNS.app.activeTab
    local oldLedgerDB = _G.MerchantMasterLedgerDB
    hostNS.app.activeTab = "an_ledger"
    _G.MerchantMasterLedgerDB = {}
    ns.Store.Init()
    local char, econ = ns.Store.CurrentCharAndEcon()
    local now = ns.Store.Now()
    ns.Store.Append({ type = "CRAFT", char = char, econ = econ, itemID = 12360, qty = 1, unit = 0, total = 0, where = "Alchemy", time = now, cogs = 100000, extra = { reagentCost = 100000 } })
    ns.Store.Append({ type = "TRADE_SELL", char = char, econ = econ, itemID = 12360, qty = 1, unit = 260000, total = 260000, where = "Trade", time = now + 1, extra = { gross = 260000, fee = 0, buyer = "Buyer" } })
    ns.Store.Append({ type = "MONEY_TRANSFER", char = char, econ = econ, itemID = 0, qty = 0, unit = 0, total = 50000, where = "Trade", time = now + 2, extra = { counterparty = "Tipper" } })
    ns.Store.Append({ type = "MONEY_TRANSFER", char = char, econ = econ, itemID = 0, qty = 0, unit = 0, total = 90000, where = "Mail", time = now + 3, extra = { counterparty = "Alt" } })
    MerchantMasterDB.anLedgerPreset = "craft"
    local craftRes = ns.Model.QueryLedger(ui.Filters(), 0, 500)
    check(craftRes.totalMatched == 1 and craftRes.rows[1].type == "CRAFT" and craftRes.totals.cogs == 100000, "craft preset matches CRAFT rows and aggregates craft cost")
    MerchantMasterDB.anLedgerPreset = "trade"
    local tradeRes = ns.Model.QueryLedger(ui.Filters(), 0, 500)
    check(tradeRes.totalMatched == 2, "trade preset matches TRADE_SELL and Trade MONEY_TRANSFER while excluding Mail transfer")
    local sawMail = false
    for _, r in ipairs(tradeRes.rows) do if r.where == "Mail" then sawMail = true end end
    check(not sawMail, "trade preset excludes Mail MONEY_TRANSFER rows")
    -- Verify Transaction Type dropdown includes Trade & Crafting and clears conflicting quick preset
    local savedDrop, dropOpts, dropPick = hostNS.Theme.OpenDropDown
    hostNS.Theme.OpenDropDown = function(_, list, _, cb) dropOpts, dropPick = list, cb end
    local oldType = MerchantMasterDB.anType
    ui.typeBtn:Click()
    local hasTradeOpt, hasCraftOpt = false, false
    for _, opt in ipairs(dropOpts or {}) do
        if opt.key == "trade" then hasTradeOpt = true end
        if opt.key == "craft" then hasCraftOpt = true end
    end
    check(hasTradeOpt and hasCraftOpt, "Transaction Type dropdown exposes both trade and craft options")
    MerchantMasterDB.anLedgerPreset = "sales"
    dropPick("trade")
    check(MerchantMasterDB.anType == "trade" and MerchantMasterDB.anLedgerPreset == "all", "selecting Trade type clears active quick preset")
    MerchantMasterDB.anType = oldType
    hostNS.Theme.OpenDropDown = savedDrop
    _G.MerchantMasterLedgerDB = oldLedgerDB
    ns.Store.Init()
    hostNS.app.activeTab = oldTab
    MerchantMasterDB.anLedgerPreset = oldPreset
    local negBars = ns.Chart.CreateBarChart(UIParent, 528, 195)
    negBars:SetData({ { day = "2026-11-18", value = -150000 } })
    check(negBars._bars[1]:GetWidth() <= 36, "single bar width is capped instead of stretching across the plot")
    check(negBars._yAxisLabels[#negBars._yAxisLabels]:GetText():find("0", 1, true), "negative-only bar chart anchors 0g cleanly at top")
    negBars._hits[1]:GetScript("OnEnter")(negBars._hits[1])
    check(negBars._hoverBar:IsShown() and negBars._hoverText:IsShown() and not negBars._hoverLine:IsShown(), "bar hover shows column wash and floating readout")
    negBars._hits[1]:GetScript("OnLeave")(negBars._hits[1])
    check(not negBars._hoverBar:IsShown(), "leaving a bar hides column wash")
end

do
    local barChart = ns.Chart.CreateBarChart(UIParent, 528, 195, { title = "Daily Realized Profit" })
    check(barChart._barCaps == nil, "bar chart does not allocate a rounded top cap texture pool")
    local origCreateTex = barChart.plot.CreateTexture
    local createdArtwork, usedPillCap = {}, false
    barChart.plot.CreateTexture = function(self, name, layer, ...)
        local tex = origCreateTex(self, name, layer, ...)
        if layer == "ARTWORK" then
            createdArtwork[#createdArtwork + 1] = tex
            local origSetTex = tex.SetTexture
            tex.SetTexture = function(t, path, ...)
                if type(path) == "string" and path:find("pill_fill", 1, true) then usedPillCap = true end
                return origSetTex(t, path, ...)
            end
        end
        return tex
    end
    local function countShown(tbl)
        local n = 0
        for _, w in pairs(tbl) do if w:IsShown() then n = n + 1 end end
        return n
    end
    local function makeBars(days)
        local out = {}
        for i = 1, days do
            local v = (i <= 2 and days > 1) and 0 or ((i % 3 == 0) and -45000 or (i * 25000))
            out[i] = { day = string.format("2026-11-%02d", i), value = v }
        end
        return out
    end
    -- Switch 1D -> 1W -> 1M -> 1W -> 1D -> empty, including leading zero-profit days
    local seq = { 1, 7, 30, 7, 1, 0 }
    for _, count in ipairs(seq) do
        barChart:SetData(makeBars(count))
        check(barChart._barCount == count, "bar count matches timeframe slice (" .. count .. ")")
        check(countShown(barChart._bars) == count, "visible bar textures match active count (" .. count .. ")")
        check(countShown(barChart._hits) == count, "visible bar hit strips match active count (" .. count .. ")")
        check(countShown(createdArtwork) == count, "no orphaned bar cap or extra artwork textures remain visible (" .. count .. ")")
        check(barChart.baseline:IsShown() == (count > 0), "baseline visibility matches non-empty bar state (" .. count .. ")")
    end
    check(not usedPillCap, "bar chart never assigns pill_fill rounded cap textures")
    check(barChart.empty:IsShown(), "empty timeframe shows empty state with zero lingering bar textures")

    -- Exercise the Overview Daily Realized Profit chart across 1D -> 1W -> 1M -> 1D switches
    local ui = ns.UI
    local oldCompute, oldPeriod = ns.Model.Compute, MerchantMasterDB.anPeriod
    local byPeriod = { today = makeBars(1), ["7d"] = makeBars(7), ["30d"] = makeBars(30) }
    ns.Model.Compute = function(_, filters)
        return {
            kpis = { profit = 0, sales = 0, purchases = 0, depLost = 0, lootValue = 0, wealthChange = 0, unexplained = 0 },
            top = {}, wealth = {}, activityFeed = {},
            profitByDay = byPeriod[filters.period] or {},
        }
    end
    for _, step in ipairs({ { "today", 1 }, { "7d", 7 }, { "30d", 30 }, { "7d", 7 }, { "today", 1 } }) do
        MerchantMasterDB.anPeriod = step[1]
        ui.Refresh("an_overview", ui.content)
        local profitChart = ui.views.an_overview.profit
        check(profitChart._barCaps == nil, "overview Daily Realized Profit chart has no rounded cap pool")
        check(countShown(profitChart._bars) == step[2], "overview profit bars cleanly resize on period " .. step[1])
    end
    ns.Model.Compute, MerchantMasterDB.anPeriod = oldCompute, oldPeriod
end

-- Portfolio Audit & Sync button visibility, modal rendering, /mma audit, and Sync action
do
    local ui = ns.UI
    ui.Refresh("an_overview", ui.content)
    check(ui.portfolioAuditBtn == nil or not ui.portfolioAuditBtn:IsShown(), "Audit & Sync button is hidden on Overview")
    ui.Refresh("an_portfolio", ui.content)
    if ui.portfolioAuditBtn then
        check(ui.portfolioAuditBtn:IsShown(), "Audit & Sync button is visible on Portfolio")
    end
    local box, report = ui.ShowPortfolioAudit({ bankOpen = false })
    check(box ~= nil and box:IsShown() and report ~= nil, "ShowPortfolioAudit opens modal with live analysis report")
    check(box.statusFs and box.statusFs:GetText():find("CLOSED", 1, true) ~= nil, "Audit modal shows Bank CLOSED badge")
    check(box.edit and box.edit:GetText():find("Portfolio Audit Report", 1, true) ~= nil, "Audit modal populates plain-English report text")
    box:Hide()
    ui.Slash("audit")
    check(ui.portfolioAuditModal and ui.portfolioAuditModal:IsShown(), "/mma audit opens Portfolio Audit & Sync modal")
    local syncClick = box.syncBtn and box.syncBtn:GetScript("OnClick")
    check(type(syncClick) == "function", "Audit modal exposes Sync Snapshots button")
    syncClick(box.syncBtn)
    check(box.summaryFs:GetText():find("Synced:", 1, true) ~= nil, "Sync Snapshots updates modal with before -> after summary")
    ui.ApplyTheme()
    box:Hide()
end

-- Disenchant ledger rendering, via DE origin tags, Item Detail indirect DE summary, and Items tooltip
do
    local ui = ns.UI
    local function strip(s) return tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "") end
    local ledgerCols = ui.Columns and ui.Columns.an_ledger or {}
    local totalCol, whereCol
    for _, col in ipairs(ledgerCols) do
        if col.key == "total" then totalCol = col
        elseif col.key == "where" then whereCol = col end
    end
    check(totalCol and type(totalCol.render) == "function", "an_ledger total column exposes renderer")
    check(whereCol and type(whereCol.render) == "function", "an_ledger where column exposes renderer")

    local brokenTxt = strip(totalCol.render({ type = "DISENCHANT_BROKEN", cogs = 10000, profit = 0, extra = { deSrcCost = 10000, estValue = 20000 } }))
    local recvTxt = strip(totalCol.render({ type = "DISENCHANT_RECEIVE", extra = { allocBasis = 10000, marketValue = 20000, costCarryover = true } }))
    check(brokenTxt:find("Cost", 1, true) ~= nil and brokenTxt:find("1g", 1, true) ~= nil,
        "DISENCHANT_BROKEN renders muted transferred Cost 1g (got: " .. brokenTxt .. ")")
    check(recvTxt:find("Cost", 1, true) ~= nil and recvTxt:find("1g", 1, true) ~= nil,
        "DISENCHANT_RECEIVE renders carried-over Cost 1g (got: " .. recvTxt .. ")")

    local whereTxt = strip(whereCol.render({ type = "AH_SELL", where = "Auction House", extra = { deOrigin = { srcItemID = 10504, srcName = "Green Lens", qty = 1, srcCost = 10000, share = 1 } } }))
    check(whereTxt:find("via DE: Green Lens", 1, true) ~= nil,
        "AH_SELL carrying extra.deOrigin renders 'via DE: Green Lens' in Where column (got: " .. whereTxt .. ")")

    -- ShowItemDetail renders Indirect via DE + top sold outputs without double-counting
    local oldGetDetail = ns.Model.GetItemDetail
    ns.Model.GetItemDetail = function()
        return {
            itemID = 10504, name = "Green Lens", curBasis = 10000, smartAvgBuy = 10000,
            minBuy = 10000, maxBuy = 10000, minSell = 0, maxSell = 0, saleRate = 0,
            expSinceSale = 0, canSinceSale = 0,
            deBrokenQty = 12, deBrokenCost = 120000, deSoldMatsQty = 11, deIndirectProfit = 99000,
            deSoldOutputs = { { itemID = 11178, name = "Large Radiant Shard", qty = 11, profit = 99000 } },
            windows = { d7 = { profit = 0 }, d30 = { profit = 0 }, all = { bought = 12, sold = 0, profit = 0 } },
            inventory = { bags = 0, bank = 0, mail = 0, inTransit = 0, ah = 0, total = 0, byChar = {} },
            transactions = {},
        }
    end
    ui.ShowItemDetail(10504)
    local detailBody = strip(ui.views.an_items.detail.body:GetText())
    check(detailBody:find("Indirect via DE:", 1, true) ~= nil and detailBody:find("not double-counted", 1, true) ~= nil,
        "Item Detail body shows Indirect via DE summary with non-double-counting note")
    check(detailBody:find("Large Radiant Shard x11", 1, true) ~= nil,
        "Item Detail body lists top sold DE output Large Radiant Shard x11")
    ui.views.an_items.detail:Hide()
    ns.Model.GetItemDetail = oldGetDetail

    -- Items row hover tooltip displays Indirect via DE + top sold output
    local oldCompute = ns.Model.Compute
    ns.Model.Compute = function(view)
        if view == "items" then
            return {
                rows = { {
                    itemID = 10504, name = "Green Lens", profit = 0, bought = 12, sold = 0,
                    deBrokenQty = 12, deSoldMatsQty = 11, deIndirectProfit = 99000,
                    deSoldOutputs = { { itemID = 11178, name = "Large Radiant Shard", qty = 11, profit = 99000 } },
                } },
                totals = { qtySold = 0, qtyBought = 12, gross = 0, spent = 120000, fee = 0, cogs = 0, depLost = 0, profit = 0 },
            }
        end
        return oldCompute(view)
    end
    ui.Refresh("an_items", ui.content)
    local itemRow = ui.views.an_items.table and ui.views.an_items.table.rows and ui.views.an_items.table.rows[1]
    local nameCell = itemRow and itemRow.cells and itemRow.cells[1]
    local onEnter = nameCell and nameCell.GetScript and nameCell:GetScript("OnEnter")
    if onEnter and GameTooltip then
        GameTooltip:ClearLines()
        onEnter(nameCell)
        local tipText = strip(table.concat(GameTooltip._lines or {}, "\n"))
        check(tipText:find("Indirect via DE", 1, true) ~= nil and tipText:find("Large Radiant Shard x11", 1, true) ~= nil,
            "Items row tooltip shows Indirect via DE and top sold output")
    end
    ns.Model.Compute = oldCompute
end

print("Accounting UI suite: " .. assertions .. " chart, tooltip, and UI assertions")
if priorFailures > 0 then error("Existing analytics suite failures: " .. priorFailures) end
