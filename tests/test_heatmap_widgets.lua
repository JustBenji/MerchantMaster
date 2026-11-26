-- Standalone Lua 5.1 Unit Suite for Concept B & Concept C Time-of-Day Heatmap Widgets
-- Covers Chart.HeatmapCellColor, Chart.CreateHeatmapTimingDrawer, Chart.CreateHeatStrip24h.
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local ns, createdFrames, host = dofile(testsDir .. "host_fixture.lua")
local Theme = ns.Theme
local Chart = ns.Analytics and ns.Analytics.Chart

local assertions = 0
local function check(ok, msg)
    assertions = assertions + 1
    if not ok then
        error("HEATMAP WIDGETS FAIL [" .. assertions .. "]: " .. tostring(msg), 2)
    end
end

local function srgbLin(v)
    if v <= 0.03928 then return v / 12.92 end
    return ((v + 0.055) / 1.055) ^ 2.4
end

local function relLum(r, g, b)
    return 0.2126 * srgbLin(r) + 0.7152 * srgbLin(g) + 0.0722 * srgbLin(b)
end

local function blendOver(bg, fg)
    local a = fg[4] or 1
    return {
        bg[1] + (fg[1] - bg[1]) * a,
        bg[2] + (fg[2] - bg[2]) * a,
        bg[3] + (fg[3] - bg[3]) * a,
        1,
    }
end

local function contrastRatio(c1, c2)
    local l1 = relLum(c1[1], c1[2], c1[3])
    local l2 = relLum(c2[1], c2[2], c2[3])
    if l1 < l2 then l1, l2 = l2, l1 end
    return (l1 + 0.05) / (l2 + 0.05)
end

local function buildSyntheticHeatmap(opts)
    opts = opts or {}
    local baseAvg = opts.baseAvg or 100000 -- 10g
    local cells = { {}, {}, {}, {}, {}, {}, {} }
    local daily = {}
    local hourly = {}
    local totalSamples = 0

    for dow = 1, 7 do
        local daySum, dayMin, dayQty, dayN = 0, nil, 0, 0
        for hour = 0, 23 do
            if not (opts.sparse and (hour % 3 ~= 0)) then
                -- Cheap early morning (0..5), fair midday (6..16), expensive prime time (17..23)
                local mult = 1.0
                if hour <= 5 then mult = 0.78
                elseif hour <= 10 then mult = 0.92
                elseif hour <= 16 then mult = 1.00
                elseif hour <= 20 then mult = 1.18
                else mult = 1.36 end
                if dow >= 6 then mult = mult * 1.04 end
                local avgP = math.floor(baseAvg * mult + 0.5)
                local minP = math.floor(avgP * 0.90 + 0.5)
                local qty = (hour <= 5) and 48 or ((hour >= 18) and 8 or 24)
                local samp = opts.cellSamples or 3
                local pct = math.floor((((avgP - baseAvg) / baseAvg) * 100) * 10 + 0.5) / 10
                cells[dow][hour] = {
                    avgPrice = avgP,
                    minPrice = minP,
                    avgQty = qty,
                    samples = samp,
                    pctVsAvg = pct,
                }
                daySum = daySum + avgP
                dayMin = dayMin and math.min(dayMin, minP) or minP
                dayQty = dayQty + qty
                dayN = dayN + 1
                totalSamples = totalSamples + samp
            end
        end
        if dayN > 0 then
            daily[dow] = {
                avgPrice = math.floor(daySum / dayN + 0.5),
                minPrice = dayMin,
                avgQty = math.floor(dayQty / dayN + 0.5),
                samples = dayN * (opts.cellSamples or 3),
            }
        end
    end

    for hour = 0, 23 do
        local hSum, hMin, hQty, hN, hSamp = 0, nil, 0, 0, 0
        for dow = 1, 7 do
            local c = cells[dow][hour]
            if c then
                hSum = hSum + c.avgPrice
                hMin = hMin and math.min(hMin, c.minPrice) or c.minPrice
                hQty = hQty + c.avgQty
                hSamp = hSamp + c.samples
                hN = hN + 1
            end
        end
        if hN > 0 then
            hourly[hour] = {
                avgPrice = math.floor(hSum / hN + 0.5),
                minPrice = hMin,
                avgQty = math.floor(hQty / hN + 0.5),
                samples = hSamp,
            }
        end
    end

    return {
        itemID = opts.itemID or 13457,
        economy = "Realm:Horde",
        updatedAt = 1794360000,
        source = opts.source or "tsm_csv",
        windowDays = opts.windowDays or 30,
        cells = cells,
        daily = daily,
        hourly = hourly,
        overall = {
            avgPrice = baseAvg,
            medianPrice = baseAvg,
            minPrice = math.floor(baseAvg * 0.70),
            maxPrice = math.floor(baseAvg * 1.42),
            avgQty = 24,
            totalSamples = opts.totalSamplesOverride or totalSamples,
            cvPct = opts.cvPct ~= nil and opts.cvPct or 18,
        },
        bestBuy = { dow = 1, hour = 3, avgPrice = 78000, minPrice = 70200, pctVsAvg = -22.0 },
        bestSell = { dow = 7, hour = 22, avgPrice = 141440, minPrice = 127296, pctVsAvg = 41.4 },
    }
end

---------------------------------------------------------------------------------------------------
-- 1. Exports & Static Hygiene
---------------------------------------------------------------------------------------------------
check(type(Chart) == "table", "ns.Analytics.Chart is loaded")
check(type(Chart.HeatmapCellColor) == "function", "Chart.HeatmapCellColor exported")
check(type(Chart.CreateHeatmapTimingDrawer) == "function", "Chart.CreateHeatmapTimingDrawer exported")
check(type(Chart.CreateHeatStrip24h) == "function", "Chart.CreateHeatStrip24h exported")
check(type(Chart.IsoDowFromWday) == "function", "Chart.IsoDowFromWday exported")

do
    local fh = assert(io.open(testsDir .. "../Analytics/Chart.lua", "rb"))
    local src = fh:read("*a")
    fh:close()
    check(not src:match('SetScript%s*%(%s*["\']OnUpdate["\']'), "Chart.lua has no OnUpdate script")
    check(not src:find("C_Timer.NewTicker", 1, true), "Chart.lua has no C_Timer.NewTicker")
    check(not src:find("\226\134\146", 1, true), "Chart.lua has no forbidden right arrow glyph")
    check(not src:find("\226\134\144", 1, true), "Chart.lua has no forbidden left arrow glyph")
end

---------------------------------------------------------------------------------------------------
-- 2. ISO dow Conversion (Lua date('*t').wday 1=Sun..7=Sat -> ISO 1=Mon..7=Sun)
---------------------------------------------------------------------------------------------------
do
    local expected = { [1] = 7, [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [7] = 6 }
    for wday = 1, 7 do
        check(Chart.IsoDowFromWday(wday) == expected[wday],
            string.format("IsoDowFromWday(%d) == %d", wday, expected[wday]))
    end
end

---------------------------------------------------------------------------------------------------
-- 3. HeatmapCellColor Across Dark, Light & All 5 Warcraft Skins
---------------------------------------------------------------------------------------------------
do
    local modes = {
        { skin = "standard", mode = "dark", label = "Dark" },
        { skin = "standard", mode = "light", label = "Light" },
        { skin = "human", mode = "dark", label = "Human" },
        { skin = "night_elf", mode = "dark", label = "NightElf" },
        { skin = "orc", mode = "dark", label = "Orc" },
        { skin = "undead", mode = "dark", label = "Undead" },
        { skin = "goblin", mode = "dark", label = "Goblin" },
    }
    local stops = { -25, -15, -10, 0, 10, 22, 36 }
    for _, cfg in ipairs(modes) do
        Theme.SetSkin(cfg.skin, true)
        Theme.SetMode(cfg.mode, true)
        local pal = Theme.GetActivePalette()

        for _, pct in ipairs(stops) do
            local r, g, b, a = Chart.HeatmapCellColor(pct, "avg", pal, false, nil)
            check(r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1 and a > 0 and a <= 1,
                cfg.label .. " pct=" .. pct .. " returns valid RGBA")
        end

        -- Cold buy stop is blue-dominant; hot sell stop is red-dominant
        local br, bg, bb = Chart.HeatmapCellColor(-20, "avg", pal, false, nil)
        local hr, hg, hb = Chart.HeatmapCellColor(35, "avg", pal, false, nil)
        check(bb > br, cfg.label .. " <=-15% is blue-dominant")
        check(hr > hb, cfg.label .. " >+30% is red-dominant")

        -- Supply mode: scarce (0.1) is warm red/orange, abundant (1.7) is cool blue
        local sr, sg, sb = Chart.HeatmapCellColor(nil, "supply", pal, false, 0.1)
        local ar, ag, ab = Chart.HeatmapCellColor(nil, "supply", pal, false, 1.7)
        check(sr > sb, cfg.label .. " supply scarce (0.1) is warm")
        check(ab > ar, cfg.label .. " supply abundant (1.7) is cool")

        -- Missing cell returns muted recessed slot
        local mr, mg, mb, ma = Chart.HeatmapCellColor(nil, "avg", pal, false, nil)
        check(mr >= 0 and mg >= 0 and mb >= 0 and ma > 0 and ma <= 1, cfg.label .. " missing cell returns valid muted slot")

        -- Weekend tint is distinct from weekday
        local wr1, wg1, wb1, wa1 = Chart.HeatmapCellColor(0, "avg", pal, false, nil)
        local wr2, wg2, wb2, wa2 = Chart.HeatmapCellColor(0, "avg", pal, true, nil)
        check(math.abs(wr1 - wr2) + math.abs(wg1 - wg2) + math.abs(wb1 - wb2) + math.abs(wa1 - wa2) > 0.005,
            cfg.label .. " weekend tint shifts color measurably")
    end

    -- Light mode neutral differs clearly from Dark mode neutral
    Theme.SetSkin("standard", true)
    Theme.SetMode("dark", true)
    local dr, dg, db = Chart.HeatmapCellColor(0, "avg", Theme.GetActivePalette(), false, nil)
    Theme.SetMode("light", true)
    local lr, lg, lb = Chart.HeatmapCellColor(0, "avg", Theme.GetActivePalette(), false, nil)
    check(lr > dr + 0.3 and lg > dg + 0.3 and lb > db + 0.3, "Light neutral cell is lighter than Dark neutral cell")
    Theme.SetMode("dark", true)
end

---------------------------------------------------------------------------------------------------
-- 4. CreateHeatmapTimingDrawer: Pooling, ISO Now Ring, Verdict Banner, Toggles, Hover Sync
---------------------------------------------------------------------------------------------------
do
    local origDate = _G.date
    -- Mock Sunday (wday=1 -> ISO dow=7) at hour=3 (cheap buy window)
    local mockWday, mockHour = 1, 3
    _G.date = function(fmt, ts)
        if fmt == "*t" then
            return { wday = mockWday, hour = mockHour, min = 0, sec = 0 }
        end
        return origDate and origDate(fmt, ts) or "2026-11-21"
    end

    Theme.SetSkin("standard", true)
    Theme.SetMode("dark", true)

    local framesBefore = #createdFrames
    local drawer = Chart.CreateHeatmapTimingDrawer(UIParent, 860, 415, { showCurve = true })
    local framesAfterCreate = #createdFrames
    -- Verify zero per-cell CreateFrame (168 cells must be Textures, not Frames!)
    check((framesAfterCreate - framesBefore) < 50,
        "drawer creates < 50 frames total (zero per-cell CreateFrame), created " .. (framesAfterCreate - framesBefore))

    local quadCount = 0
    for dow = 1, 7 do
        for hour = 0, 23 do
            local q = drawer.cells[dow] and drawer.cells[dow][hour]
            check(q and q:GetObjectType() == "Texture", "cell[" .. dow .. "][" .. hour .. "] is pooled Texture")
            quadCount = quadCount + 1
        end
    end
    check(quadCount == 168, "exactly 168 pooled cell quads")
    check(drawer.nowRing and drawer.nowRing.top and drawer.nowRing.bottom and drawer.nowRing.left and drawer.nowRing.right,
        "4-edge Now ring exists")
    check(#drawer.curveLines == 23 and #drawer.curveGlowLines == 23, "23 pooled curve + glow lines exist")

    -- Bind synthetic heatmap (Sunday 03:00 -> BUY WINDOW, Volatile since cvPct=18)
    local hm = buildSyntheticHeatmap({ cvPct = 18 })
    drawer:SetItem(13457, hm, nil, "Realm:Horde")
    local framesAfterBind = #createdFrames
    check(framesAfterBind == framesAfterCreate, "SetItem allocates zero new frames")

    check(drawer.verdictPill.text:GetText() == "BUY WINDOW",
        "Sunday 03:00 cheap slot shows BUY WINDOW, got " .. tostring(drawer.verdictPill.text:GetText()))
    check(drawer.stabilityPill.text:GetText() == "Volatile",
        "cvPct=18 shows Volatile stability pill, got " .. tostring(drawer.stabilityPill.text:GetText()))
    check(drawer.freshnessText:GetText() == "tsm_csv · 30d",
        "freshness meta shows source and windowDays, got " .. tostring(drawer.freshnessText:GetText()))
    local hl = drawer.verdictHeadline:GetText()
    check(hl:find("Now Sun 03:00", 1, true) ~= nil, "headline shows ISO Sun 03:00: " .. hl)
    check(hl:find("Best Buy Mon 03:00", 1, true) ~= nil, "headline shows Best Buy: " .. hl)
    check(hl:find("Best Sell Sun 22:00", 1, true) ~= nil, "headline shows Best Sell: " .. hl)
    check(drawer.nowHourPill.text:GetText() == "03", "green Now hour pill shows 03")
    check(drawer.nowRing.top:IsShown(), "Now ring is visible")

    -- Verify Now ring vertical position matches dow=7 (Sunday, bottom row)
    local _, _, _, _, nowTopY = drawer.nowRing.top:GetPoint(1)
    local rowH = drawer._gridH / 7
    check(math.abs(nowTopY - (-(6 * rowH))) < 1.5,
        string.format("Sunday wday=1 places Now ring on row 7 (y=%.1f vs expected %.1f)", nowTopY, -(6 * rowH)))

    -- Switch clock to Monday (wday=2 -> ISO dow=1) hour=22 (expensive -> SELL WINDOW) and Steady (cvPct=8)
    mockWday, mockHour = 2, 22
    local hmSteady = buildSyntheticHeatmap({ cvPct = 8 })
    drawer:SetItem(13457, hmSteady)
    check(drawer.verdictPill.text:GetText() == "SELL WINDOW", "Monday 22:00 expensive slot shows SELL WINDOW")
    check(drawer.stabilityPill.text:GetText() == "Steady", "cvPct=8 shows Steady stability pill")
    local _, _, _, _, monTopY = drawer.nowRing.top:GetPoint(1)
    check(math.abs(monTopY) < 1.5, "Monday wday=2 places Now ring on row 1 (y=0)")

    -- Switch clock to midday hour=12 (fair price) and Recent (totalSamples=8)
    mockWday, mockHour = 4, 12
    local hmRecent = buildSyntheticHeatmap({ totalSamplesOverride = 8, cvPct = 5 })
    drawer:SetItem(13457, hmRecent)
    check(drawer.verdictPill.text:GetText() == "FAIR PRICE", "midday 0% slot shows FAIR PRICE")
    check(drawer.stabilityPill.text:GetText() == "Recent", "totalSamples < 12 shows Recent stability pill")

    -- Limited data when totalSamples < 4
    local hmLimited = buildSyntheticHeatmap({ totalSamplesOverride = 2 })
    drawer:SetItem(13457, hmLimited)
    check(drawer.verdictPill.text:GetText() == "LIMITED DATA", "totalSamples < 4 shows LIMITED DATA")

    -- Restore rich heatmap for controls, alignment, hover tests
    mockWday, mockHour = 2, 14
    drawer:SetItem(13457, hm)

    -- Sat/Sun weekend row tints visible
    check(drawer.weekendBgs[6]:IsShown() and drawer.weekendBgs[7]:IsShown(), "Sat/Sun weekend row tints are shown")
    check(drawer.dayLabels[6]:GetText() == "Sat" and drawer.dayLabels[7]:GetText() == "Sun", "Sat/Sun labels on rows 6 and 7")

    -- Column-aligned 24h curve matches matrix gridArea 1:1
    local _, _, _, gridX = drawer.gridArea:GetPoint(1)
    local _, _, _, curveX = drawer.curvePlot:GetPoint(1)
    check(gridX == curveX, string.format("curvePlot X (%s) matches gridArea X (%s)", tostring(curveX), tostring(gridX)))
    check(drawer.curvePlot:GetWidth() == drawer.gridArea:GetWidth(),
        "curvePlot width matches gridArea width 1:1")
    check(drawer.curveAvgLine:IsShown(), "24h curve weekly average reference line is shown")
    check(drawer.curveLines[1]:IsShown() and drawer.curveLines[1]:GetTexture():find("line_soft.tga", 1, true) ~= nil,
        "24h curve reuses LINE_SOFT_TEX")

    -- Metric toggle buttons: Avg -> Min -> Supply
    check(drawer.dayAvgHeader:GetText() == "Day Avg", "default right-hand header is Day Avg")
    local avgDay1 = drawer.dayAvgLabels[1]:GetText()
    check(avgDay1:find("g", 1, true) ~= nil, "Day Avg uses Theme.FormatMoneyParts formatting: " .. avgDay1)
    local avgColorBefore = { drawer.cells[1][2]._colorTexture[1], drawer.cells[1][2]._colorTexture[2], drawer.cells[1][2]._colorTexture[3] }

    drawer.metricBtns.min:Click()
    check(drawer._metric == "min" and drawer.dayAvgHeader:GetText() == "Day Min", "Min button toggles metric to min")
    local minDay1 = drawer.dayAvgLabels[1]:GetText()
    check(minDay1 ~= avgDay1, "Day Min column updates values vs Day Avg")

    drawer.metricBtns.supply:Click()
    check(drawer._metric == "supply" and drawer.dayAvgHeader:GetText() == "Avg Qty", "Supply button toggles metric to supply")
    local qtyDay1 = drawer.dayAvgLabels[1]:GetText()
    check(tonumber(qtyDay1) ~= nil, "Supply mode Day column shows numeric qty, got " .. tostring(qtyDay1))
    local supColor = drawer.cells[1][2]._colorTexture
    check(math.abs(supColor[1] - avgColorBefore[1]) + math.abs(supColor[2] - avgColorBefore[2]) + math.abs(supColor[3] - avgColorBefore[3]) >= 0,
        "Supply mode repaints cells")

    drawer.metricBtns.avg:Click()
    check(drawer._metric == "avg", "Avg button returns to avg mode")

    -- Resolution toggle: 24h -> 12x2h -> 24h
    drawer.resBtns["12x2h"]:Click()
    check(drawer._resolution == "12x2h", "12x2h button toggles resolution")
    check(drawer.cells[1][0]:IsShown() and not drawer.cells[1][1]:IsShown(), "12x2h hides odd-hour quads and shows even buckets")
    check(drawer.cells[1][0]:GetWidth() > (drawer._gridW / 24), "12x2h widens even bucket quads")

    -- Hover in 12x2h mode shows 2-hour range
    check(drawer:SimulateHover(3, 15) == true, "SimulateHover works in 12x2h mode")
    local tip12 = table.concat(GameTooltip._lines or {}, "\n")
    check(tip12:find("Wed 14:00 - 16:00", 1, true) ~= nil, "12x2h hover tooltip shows 2h span: " .. tip12)

    drawer.resBtns["24h"]:Click()
    check(drawer._resolution == "24h" and drawer.cells[1][1]:IsShown(), "24h restores all 168 visible cell quads")
    check(#createdFrames == framesAfterCreate, "toggles allocate zero new frames")

    -- SimulateHover (Matrix -> Tooltip + Synced 24h Curve highlight)
    check(drawer:SimulateHover(3, 14) == true, "SimulateHover(3, 14) succeeds")
    check(drawer.colHighlight:IsShown() and drawer.hoverRing.top:IsShown(), "SimulateHover highlights column and cell ring")
    check(drawer.curveHoverLine:IsShown() and drawer.curveHoverDot:IsShown() and drawer.curveHoverReadout:IsShown(),
        "SimulateHover syncs 24h curve crosshair, dot, and readout")
    local readout = drawer.curveHoverReadout:GetText()
    check(readout:find("14:00", 1, true) ~= nil, "curve hover readout reflects hovered hour 14:00: " .. readout)
    local tip24 = table.concat(GameTooltip._lines or {}, "\n")
    check(tip24:find("Wed 14:00 - 15:00", 1, true) ~= nil, "tooltip header shows Wed 14:00 - 15:00")
    check(tip24:find("Avg Price", 1, true) ~= nil and tip24:find("Min Price", 1, true) ~= nil, "tooltip shows Avg and Min Price")
    check(tip24:find("vs Weekly Avg", 1, true) ~= nil and tip24:find("Avg Supply", 1, true) ~= nil and tip24:find("Samples", 1, true) ~= nil,
        "tooltip shows vs Weekly Avg, Avg Supply, Samples")

    -- Verify LiftTooltip is called during SimulateHover
    local liftCount = 0
    local origLift = Theme.LiftTooltip
    Theme.LiftTooltip = function(tip)
        liftCount = liftCount + 1
        return origLift(tip)
    end
    drawer:SimulateHover(5, 20)
    Theme.LiftTooltip = origLift
    check(liftCount == 1, "SimulateHover calls Theme.LiftTooltip once")

    -- Clear hover
    check(drawer:SimulateHover(nil, nil) == false, "SimulateHover(nil, nil) clears hover")
    check(not drawer.colHighlight:IsShown() and not drawer.curveHoverLine:IsShown() and not drawer.curveHoverDot:IsShown(),
        "clearing hover hides matrix highlight and synced curve indicators")

    -- Reverse sync: Curve hover -> Matrix column highlight
    check(drawer:SimulateCurveHover(20) == true, "SimulateCurveHover(20) succeeds")
    check(drawer.colHighlight:IsShown() and drawer.curveHoverLine:IsShown() and drawer.curveHoverDot:IsShown(),
        "curve hover highlights matrix column and curve crosshair")
    local curveTip = table.concat(GameTooltip._lines or {}, "\n")
    check(curveTip:find("All Days 20:00 - 21:00", 1, true) ~= nil, "curve hover tooltip shows All Days 20:00 - 21:00")
    drawer:SimulateCurveHover(nil)
    check(not drawer.colHighlight:IsShown() and not drawer.curveHoverLine:IsShown(), "clearing curve hover clears matrix highlight")

    -- Regression: rapid OnEnter -> OnLeave -> OnEnter border crossings keep strictly 1 active poll chain
    do
        local origTimer = _G.C_Timer
        local queue = {}
        _G.C_Timer = {
            After = function(_, fn)
                queue[#queue + 1] = fn
            end,
        }
        local onEnter = drawer.hitOverlay:GetScript("OnEnter")
        local onLeave = drawer.hitOverlay:GetScript("OnLeave")
        local onHide = drawer.hitOverlay:GetScript("OnHide")
        onEnter(drawer.hitOverlay)
        onLeave(drawer.hitOverlay)
        onEnter(drawer.hitOverlay)
        onLeave(drawer.hitOverlay)
        onEnter(drawer.hitOverlay)
        check(#queue == 3, "three rapid OnEnter calls queued 3 initial callbacks")
        -- Drain wave 1: only the latest generation (3rd) should reschedule itself
        local wave1 = queue
        queue = {}
        for _, fn in ipairs(wave1) do fn() end
        check(#queue == 1, "rapid OnEnter/OnLeave/OnEnter leaves strictly 1 active poll chain, got " .. #queue)
        -- Drain wave 2 while still hovering: still strictly 1 active chain
        local wave2 = queue
        queue = {}
        for _, fn in ipairs(wave2) do fn() end
        check(#queue == 1, "active poll chain stays strictly 1 on subsequent tick, got " .. #queue)
        -- OnHide cancels the active chain completely
        onHide(drawer.hitOverlay)
        local wave3 = queue
        queue = {}
        for _, fn in ipairs(wave3) do fn() end
        check(#queue == 0, "OnHide terminates active poll chain cleanly, got " .. #queue)
        _G.C_Timer = origTimer
    end

    -- Theme & skin switching + WCAG >= 3.0 contrast checks across Dark, Light, and 5 Warcraft skins
    local themeCases = {
        { skin = "standard", mode = "dark" },
        { skin = "standard", mode = "light" },
        { skin = "human", mode = "dark" },
        { skin = "night_elf", mode = "dark" },
        { skin = "orc", mode = "dark" },
        { skin = "undead", mode = "dark" },
        { skin = "goblin", mode = "dark" },
    }
    for _, tc in ipairs(themeCases) do
        Theme.SetSkin(tc.skin, true)
        Theme.SetMode(tc.mode, true)
        drawer:ApplyTheme()
        local pal = Theme.GetActivePalette()
        local bg = pal.cardBg
        local bannerBgCol = drawer.bannerBg._colorTexture or pal.cardAltBg
        local bannerComp = blendOver(bg, bannerBgCol)

        local txt = { drawer.verdictHeadline:GetTextColor() }
        local muted = { drawer.dayAvgHeader:GetTextColor() }
        local crText = contrastRatio(bannerComp, blendOver(bannerComp, txt))
        local crMuted = contrastRatio(bg, blendOver(bg, muted))
        check(crText >= 4.5, string.format("%s/%s headline contrast %.2f >= 4.5", tc.skin, tc.mode, crText))
        check(crMuted >= 3.0, string.format("%s/%s muted header contrast %.2f >= 3.0", tc.skin, tc.mode, crMuted))

        -- Check all badge variants (verdictPill, stabilityPill, nowHourPill) >= 3.0
        for _, vName in ipairs({ "positive", "hot", "warning", "danger", "blue", "neutral" }) do
            drawer.verdictPill:Set(vName, "TEST", pal, 14, 60)
            local fill = (drawer.verdictPill.surface and drawer.verdictPill.surface.fill and drawer.verdictPill.surface.fill[1] and drawer.verdictPill.surface.fill[1]._vertexColor)
                or (drawer.verdictPill.bgTex and drawer.verdictPill.bgTex._colorTexture)
                or { 0.5, 0.5, 0.5, 0.16 }
            local pillBg = blendOver(bannerComp, fill)
            local ink = { drawer.verdictPill.text:GetTextColor() }
            local crPill = contrastRatio(pillBg, blendOver(pillBg, ink))
            check(crPill >= 3.0, string.format("%s/%s badge '%s' contrast %.2f >= 3.0", tc.skin, tc.mode, vName, crPill))
        end

        -- Check active/inactive segmented button contrast >= 3.0
        local trackComp = blendOver(bg, drawer.metricTrackBg._colorTexture or pal.pillTrack)
        local activeComp = blendOver(trackComp, drawer.metricBtns.avg._activeBg._colorTexture or pal.pillThumb)
        local activeInk = { drawer.metricBtns.avg.text:GetTextColor() }
        local inactiveInk = { drawer.metricBtns.min.text:GetTextColor() }
        local crActive = contrastRatio(activeComp, blendOver(activeComp, activeInk))
        local crInactive = contrastRatio(trackComp, blendOver(trackComp, inactiveInk))
        check(crActive >= 3.0, string.format("%s/%s active toggle contrast %.2f >= 3.0", tc.skin, tc.mode, crActive))
        check(crInactive >= 3.0, string.format("%s/%s inactive toggle contrast %.2f >= 3.0", tc.skin, tc.mode, crInactive))
    end
    Theme.SetSkin("standard", true)
    Theme.SetMode("dark", true)
    drawer:ApplyTheme()

    -----------------------------------------------------------------------------------------------
    -- 5. Compact Popover Mode (compact = true, showCurve = false, onDeepAnalysis, onClose)
    -----------------------------------------------------------------------------------------------
    local daClickedItem, closeClicked = nil, false
    local popover = Chart.CreateHeatmapTimingDrawer(UIParent, 460, 232, {
        compact = true,
        showCurve = false,
        onDeepAnalysis = function(id) daClickedItem = id end,
        onClose = function() closeClicked = true end,
    })
    popover:SetItem(13457, hm)
    check(not popover.curveFrame:IsShown(), "compact popover hides 24h curve when showCurve=false")
    check(popover.deepAnalysisBtn and popover.deepAnalysisBtn.text:GetText() == "Deep Analysis >",
        "compact popover Deep Analysis button uses ASCII '>'")
    check(not popover.legend:IsShown(), "narrow 460px popover hides legend to prevent overlap with controls")
    popover.deepAnalysisBtn:Click()
    check(daClickedItem == 13457, "clicking Deep Analysis > invokes onDeepAnalysis(itemID)")
    popover.closeBtn:Click()
    check(closeClicked == true, "clicking close button invokes onClose()")

    -----------------------------------------------------------------------------------------------
    -- 6. Graceful Empty State + Fallback Line Chart
    -----------------------------------------------------------------------------------------------
    local origGetMeta = ns.Pricing and ns.Pricing.GetSnapshotMeta
    if ns.Pricing then
        ns.Pricing.GetSnapshotMeta = function() return nil end
    end
    local fallbackQL = {
        window = "7d",
        now = 1794360000,
        output = { values = { 95000, 98000, 102000, 100000, 104000, 108000, 110000 } },
        cost   = { values = { 60000, 61000, 62000, 60500, 61500, 63000, 62500 } },
        net    = { values = { 30250, 32100, 34900, 34500, 37300, 39600, 42000 } },
    }
    drawer:SetItem(99999, nil, fallbackQL)
    check(drawer.emptyFrame:IsShown() and not drawer.matrixFrame:IsShown() and not drawer.curveFrame:IsShown(),
        "heatmap == nil shows emptyFrame and hides matrix/curve")
    check(drawer.emptyText:GetText():find("Live AH mode", 1, true) ~= nil
        and drawer.emptyText:GetText():find("snapshot_builder", 1, true) == nil,
        "GetSnapshotMeta() == nil shows Live AH guidance without snapshot_builder CLI text")
    check(drawer.fallbackChart and drawer.fallbackChart:IsShown(),
        "empty state renders fallback Chart.CreateLineChart when fallbackQuickLook has points")
    check(#(drawer.fallbackChart._lastSeries or {}) == 3,
        "fallback chart plots output, cost, and net series")

    if ns.Pricing then
        ns.Pricing.GetSnapshotMeta = function() return { updatedAt = 1794360000, source = "tsm_csv", windowDays = 30 } end
    end
    drawer:SetItem(99999, nil, nil)
    check(drawer.emptyText:GetText() == "No hourly history recorded for this item yet",
        "GetSnapshotMeta() ~= nil shows item-specific empty message")
    check(not drawer.fallbackChart:IsShown(), "without fallbackQuickLook, fallbackChart stays hidden")

    if ns.Pricing then ns.Pricing.GetSnapshotMeta = origGetMeta end

    drawer:Clear()
    check(drawer._heatmap == nil and drawer._itemID == nil and drawer.emptyFrame:IsShown(),
        "Clear() resets drawer cleanly")

    _G.date = origDate
end

---------------------------------------------------------------------------------------------------
-- 7. CreateHeatStrip24h (Concept C Inline 24-Segment Heat Strip)
---------------------------------------------------------------------------------------------------
do
    local framesBefore = #createdFrames
    local strip = Chart.CreateHeatStrip24h(UIParent, { height = 4, showNowTick = true })
    check((#createdFrames - framesBefore) == 1, "CreateHeatStrip24h creates exactly 1 container frame")
    check(not strip.frame:IsShown(), "strip starts hidden until Bind")
    for h = 0, 23 do
        check(strip.segments[h] and strip.segments[h]:GetObjectType() == "Texture",
            "strip segment[" .. h .. "] is pooled Texture")
    end
    check(strip.nowTick and strip.nowTick:GetObjectType() == "Texture", "strip nowTick is pooled Texture")

    local fullStrip = {
        hourly = {},
        avgPrice = 100000,
        medianPrice = 100000,
    }
    for h = 0, 23 do
        fullStrip.hourly[h] = (h <= 6) and 80000 or ((h >= 18) and 130000 or 100000)
    end

    Theme.SetSkin("standard", true)
    Theme.SetMode("dark", true)
    local pal = Theme.GetActivePalette()
    strip:Bind(fullStrip, pal, 14)
    strip:Layout(96)
    check(strip.frame:IsShown() and strip.nowTick:IsShown(), "Bind shows frame and nowTick")
    check(strip.frame:GetWidth() == 96 and strip.frame:GetHeight() == 4, "Layout sizes strip frame to 96x4")

    local totalSegW = 0
    for h = 0, 23 do
        check(strip.segments[h]:IsShown(), "segment " .. h .. " shown after Bind")
        totalSegW = totalSegW + strip.segments[h]:GetWidth()
    end
    check(totalSegW == 96, "24 segments tile exact width 96, got " .. totalSegW)

    -- Sparse hours (only 3, 12, 20 populated)
    local sparseStrip = {
        hourly = { [3] = 75000, [12] = 100000, [20] = 140000 },
        avgPrice = 100000,
    }
    local framesBeforeSparse = #createdFrames
    strip:Bind(sparseStrip, pal, 20)
    check(#createdFrames == framesBeforeSparse, "re-binding strip allocates zero frames")
    local c3 = strip.segments[3]._colorTexture
    local c20 = strip.segments[20]._colorTexture
    check(c3[3] > c3[1], "sparse hour 3 (cheap) is blue-dominant")
    check(c20[1] > c20[3], "sparse hour 20 (expensive) is red-dominant")

    -- Bind across Light & all 5 Warcraft skins
    for _, skinKey in ipairs({ "standard", "human", "night_elf", "orc", "undead", "goblin" }) do
        Theme.SetSkin(skinKey, true)
        Theme.SetMode(skinKey == "standard" and "light" or "dark", true)
        strip:Bind(fullStrip, Theme.GetActivePalette(), 10)
        check(strip.frame:IsShown(), "strip binds cleanly under skin " .. skinKey)
    end
    Theme.SetSkin("standard", true)
    Theme.SetMode("dark", true)

    -- Clear hides everything
    strip:Clear()
    check(not strip.frame:IsShown() and not strip.nowTick:IsShown(), "Clear hides strip frame and nowTick")
    for h = 0, 23 do
        check(not strip.segments[h]:IsShown(), "Clear hides segment " .. h)
    end
end

print("PASS: heatmap_widgets suite (" .. assertions .. " assertions, 0 failures)")
