local addonName, host = ...
host.Analytics = host.Analytics or {}
local ns = host.Analytics

local Tooltips = {}
ns.Tooltips = Tooltips
local seen = setmetatable({}, { __mode = "k" })
local clearHooked = setmetatable({}, { __mode = "k" })
local origHostFormatMoney = host and host.FormatMoneyCompact or nil

local function secret(value)
    if _G.issecretvalue then
        local ok, result = pcall(_G.issecretvalue, value)
        return not ok or result == true
    end
    return false
end

local function secretTable(value)
    if _G.issecrettable then
        local ok, result = pcall(_G.issecrettable, value)
        return not ok or result == true
    end
    return false
end

local function number(value)
    if secret(value) then return nil end
    local n = tonumber(value)
    return n and n == n and n or nil
end

local function field(tbl, name)
    if type(tbl) ~= "table" or secretTable(tbl) then return nil end
    local ok, value = pcall(function() return tbl[name] end)
    if ok and not secret(value) then return value end
end

local TooltipPrefs = {}
host.TooltipPrefs = TooltipPrefs
ns.TooltipPrefs = TooltipPrefs

local DEFAULTS = {
    -- Global
    ttEnabled = true,
    ttPriceFormat = "colored",
    ttModifier = "none",
    -- Market & Pricing
    ttMarketEnabled = true,
    ttMinBuyout = true,
    ttMarketValue = true,
    ttListedCount = true,
    ttVendorSell = false,
    -- Crafting & Disenchant
    tooltipCraftCost = false,
    ttCraftProfit = true,
    tooltipDEValue = true,
    ttDEArcaneSalvager = true,
    tooltipDEBreakdown = true,
    crateTooltips = true,
    -- Accounting
    anTooltips = true,
    ttAccSell = true,
    ttAccBasis = true,
    ttAccProfit = true,
    ttAccLastSold = true,
    ttAccSaleRate = true,
    ttAccSlowing = true,
    ttHideEmpty = true,
    -- Inventory
    anTooltipInventory = true,
    ttInvByChar = true,
    ttInvHideZero = true,
    ttInvCompact = true,
}
TooltipPrefs.DEFAULTS = DEFAULTS

local VALID_MODIFIERS = {
    none = true,
    shift = true,
    alt = true,
    ctrl = true,
}

local COLORS = {
    header      = { 1.00, 0.82, 0.00 },
    headerRight = { 0.62, 0.66, 0.72 },
    label       = { 0.90, 0.92, 0.95 },
    value       = { 0.96, 0.97, 0.99 },
    alt         = { 0.86, 0.72, 0.54 },
    breakdown   = { 0.84, 0.86, 0.90 },
    positive    = { 0.28, 0.88, 0.45 },
    negative    = { 1.00, 0.38, 0.36 },
    arcane      = { 0.78, 0.64, 1.00 },
    slowing     = { 1.00, 0.68, 0.18 },
    muted       = { 0.62, 0.66, 0.72 },
    dimmed      = { 0.42, 0.45, 0.50 },
}
TooltipPrefs.COLORS = COLORS

local ICON_GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local ICON_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local ICON_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"

local LETTER_GOLD   = "|cffffd100g|r"
local LETTER_SILVER = "|cffc7c7ccs|r"
local LETTER_COPPER = "|cffeda55fc|r"

local DIM_HEX = "|cff6b7380"

function TooltipPrefs.Get(key)
    local db = _G.MerchantMasterDB
    local raw = nil
    if type(db) == "table" and not secretTable(db) then
        raw = db[key]
    end
    if key == "ttPriceFormat" then
        if raw == "icons" then return "icons" end
        return "colored"
    elseif key == "ttModifier" then
        if type(raw) == "string" then
            local low = raw:lower()
            if VALID_MODIFIERS[low] then return low end
        end
        return "none"
    end
    if raw ~= nil then
        return raw
    end
    return DEFAULTS[key]
end

local function normalizePrefValue(key, val)
    if key == "ttPriceFormat" then
        return (val == "icons") and "icons" or "colored"
    elseif key == "ttModifier" then
        if type(val) == "string" then
            local low = val:lower()
            if VALID_MODIFIERS[low] then return low end
        end
        return "none"
    elseif type(DEFAULTS[key]) == "boolean" then
        return val and true or false
    end
    return val
end

local function syncExternalControls(key, val)
    local app = host and host.app
    local ui = app and app.ui
    if key == "crateTooltips" and ui then
        if ui.optCrateTooltipCheck and ui.optCrateTooltipCheck.SetChecked then
            pcall(ui.optCrateTooltipCheck.SetChecked, ui.optCrateTooltipCheck, val and true or false)
        end
        if ui.crateTooltipCheck and ui.crateTooltipCheck.SetChecked then
            pcall(ui.crateTooltipCheck.SetChecked, ui.crateTooltipCheck, val and true or false)
        end
    end
end

function TooltipPrefs.Set(key, val)
    if type(_G.MerchantMasterDB) ~= "table" then
        _G.MerchantMasterDB = {}
    end
    local normalized = normalizePrefValue(key, val)
    _G.MerchantMasterDB[key] = normalized
    syncExternalControls(key, normalized)
    TooltipPrefs.InvalidateAll()
    return normalized
end

local PRESETS = {
    all = {
        ttEnabled = true,
        ttMarketEnabled = true,
        ttMinBuyout = true,
        ttMarketValue = true,
        ttListedCount = true,
        ttVendorSell = true,
        tooltipCraftCost = true,
        ttCraftProfit = true,
        tooltipDEValue = true,
        ttDEArcaneSalvager = true,
        tooltipDEBreakdown = true,
        crateTooltips = true,
        anTooltips = true,
        ttAccSell = true,
        ttAccBasis = true,
        ttAccProfit = true,
        ttAccLastSold = true,
        ttAccSaleRate = true,
        ttAccSlowing = true,
        ttHideEmpty = false,
        anTooltipInventory = true,
        ttInvByChar = true,
        ttInvHideZero = false,
        ttInvCompact = true,
    },
    compact = {
        ttEnabled = true,
        ttMarketEnabled = true,
        ttMinBuyout = true,
        ttMarketValue = true,
        ttListedCount = false,
        ttVendorSell = false,
        tooltipCraftCost = false,
        ttCraftProfit = false,
        tooltipDEValue = true,
        ttDEArcaneSalvager = false,
        tooltipDEBreakdown = false,
        crateTooltips = true,
        anTooltips = true,
        ttAccSell = true,
        ttAccBasis = false,
        ttAccProfit = true,
        ttAccLastSold = false,
        ttAccSaleRate = false,
        ttAccSlowing = true,
        ttHideEmpty = true,
        anTooltipInventory = true,
        ttInvByChar = false,
        ttInvHideZero = true,
        ttInvCompact = true,
    },
}

function TooltipPrefs.ApplyPreset(name)
    if type(name) ~= "string" then return false end
    local presetKey = name:lower()
    local source
    if presetKey == "reset" then
        source = DEFAULTS
    else
        source = PRESETS[presetKey]
    end
    if not source then return false end
    if type(_G.MerchantMasterDB) ~= "table" then
        _G.MerchantMasterDB = {}
    end
    local db = _G.MerchantMasterDB
    for k, v in pairs(source) do
        db[k] = v
        syncExternalControls(k, v)
    end
    TooltipPrefs.InvalidateAll()
    return true
end

function TooltipPrefs.IsModifierSatisfied()
    local mod = TooltipPrefs.Get("ttModifier")
    if mod == "shift" then
        if _G.IsShiftKeyDown then
            local ok, v = pcall(_G.IsShiftKeyDown)
            return ok and not secret(v) and v == true
        end
        return false
    elseif mod == "alt" then
        if _G.IsAltKeyDown then
            local ok, v = pcall(_G.IsAltKeyDown)
            return ok and not secret(v) and v == true
        end
        return false
    elseif mod == "ctrl" then
        if _G.IsControlKeyDown then
            local ok, v = pcall(_G.IsControlKeyDown)
            return ok and not secret(v) and v == true
        end
        return false
    end
    return true
end

function TooltipPrefs.FormatMoney(copper, dimmed, signed)
    if type(copper) ~= "number" or copper ~= copper then
        return dimmed and (DIM_HEX .. "-|r") or "|cff9ea8b8-|r"
    end
    local fmt = TooltipPrefs.Get("ttPriceFormat")
    if not dimmed and fmt ~= "icons" and host and type(host.FormatMoneyCompact) == "function"
        and host.FormatMoneyCompact ~= origHostFormatMoney then
        local ok, result = pcall(host.FormatMoneyCompact, copper)
        if ok and not secret(result) and result ~= nil then
            return tostring(result)
        end
    end
    local neg = copper < 0
    local val = math.floor(math.abs(copper) + 0.5)
    local gold = math.floor(val / 10000)
    local silver = math.floor((val % 10000) / 100)
    local cop = val % 100
    local sign = neg and "-" or ((signed and val > 0) and "+" or "")

    local gUnit, sUnit, cUnit
    if fmt == "icons" then
        gUnit, sUnit, cUnit = ICON_GOLD, ICON_SILVER, ICON_COPPER
    elseif dimmed then
        gUnit, sUnit, cUnit = "g", "s", "c"
    else
        gUnit, sUnit, cUnit = LETTER_GOLD, LETTER_SILVER, LETTER_COPPER
    end

    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = string.format("%d%s", gold, gUnit)
        if silver > 0 or cop > 0 then
            parts[#parts + 1] = string.format("%02d%s", silver, sUnit)
        end
        if cop > 0 then
            parts[#parts + 1] = string.format("%02d%s", cop, cUnit)
        end
    elseif silver > 0 then
        parts[#parts + 1] = string.format("%d%s", silver, sUnit)
        if cop > 0 then
            parts[#parts + 1] = string.format("%02d%s", cop, cUnit)
        end
    else
        parts[#parts + 1] = string.format("%d%s", cop, cUnit)
    end

    local out = sign .. table.concat(parts, " ")
    if dimmed then
        return DIM_HEX .. out .. "|r"
    end
    return out
end

local function money(value, signed)
    return TooltipPrefs.FormatMoney(value, false, signed)
end

local function makePreviewRow(left, right, colL, colR, enabled, isHeader)
    local d = COLORS.dimmed
    local cL = enabled and (colL or COLORS.label) or d
    local cR = enabled and (colR or COLORS.value) or d
    return {
        left = left or "",
        right = right or "",
        rL = cL[1], gL = cL[2], bL = cL[3],
        rR = cR[1], gR = cR[2], bR = cR[3],
        enabled = enabled and true or false,
        isHeader = isHeader and true or false,
    }
end

local function formatInvCounts(bags, bank, mail, inTransit, ah, compact)
    local charTotal = bags + bank + mail + inTransit + ah
    if compact then
        local extra = inTransit > 0 and (", " .. tostring(inTransit) .. " transit") or ""
        return string.format("%d (%d bags, %d bank, %d mail, %d AH%s)", charTotal, bags, bank, mail, ah, extra)
    end
    return string.format("Bags %d, Bank %d, Mail %d, In-Transit %d, AH %d", bags, bank, mail, inTransit, ah)
end

function TooltipPrefs.BuildPreviewLines(sampleKey)
    local key = (sampleKey == "silk_cloth" or sampleKey == "waylaid_crate") and sampleKey or "green_lens"
    local master = TooltipPrefs.Get("ttEnabled") ~= false
    local mktOn = master and TooltipPrefs.Get("ttMarketEnabled") ~= false
    local showMin = mktOn and TooltipPrefs.Get("ttMinBuyout") ~= false
    local showMktVal = mktOn and TooltipPrefs.Get("ttMarketValue") ~= false
    local showListed = mktOn and TooltipPrefs.Get("ttListedCount") ~= false
    local showVendor = mktOn and TooltipPrefs.Get("ttVendorSell") == true

    local showCraft = master and TooltipPrefs.Get("tooltipCraftCost") == true
    local showCraftProfit = showCraft and TooltipPrefs.Get("ttCraftProfit") ~= false
    local showDE = master and TooltipPrefs.Get("tooltipDEValue") ~= false
    local showDEAS = showDE and TooltipPrefs.Get("ttDEArcaneSalvager") ~= false
    local showDEBD = showDE and TooltipPrefs.Get("tooltipDEBreakdown") ~= false
    local showCrate = master and TooltipPrefs.Get("crateTooltips") ~= false

    local accOn = master and TooltipPrefs.Get("anTooltips") ~= false
    local showAccSell = accOn and TooltipPrefs.Get("ttAccSell") ~= false
    local showAccBasis = accOn and TooltipPrefs.Get("ttAccBasis") ~= false
    local showAccProfit = accOn and TooltipPrefs.Get("ttAccProfit") ~= false
    local showAccLast = accOn and TooltipPrefs.Get("ttAccLastSold") ~= false
    local showAccRate = accOn and TooltipPrefs.Get("ttAccSaleRate") ~= false
    local showAccSlow = accOn and TooltipPrefs.Get("ttAccSlowing") ~= false
    local hideEmpty = TooltipPrefs.Get("ttHideEmpty") ~= false

    local invOn = accOn and TooltipPrefs.Get("anTooltipInventory") ~= false
    local invByChar = invOn and TooltipPrefs.Get("ttInvByChar") ~= false
    local invHideZero = TooltipPrefs.Get("ttInvHideZero") ~= false
    local invCompact = TooltipPrefs.Get("ttInvCompact") ~= false

    local fmt = TooltipPrefs.FormatMoney
    local rows = {}
    local function push(left, right, colL, colR, enabled, isHeader)
        rows[#rows + 1] = makePreviewRow(left, right, colL, colR, enabled, isHeader)
    end

    if key == "waylaid_crate" then
        local header = {
            name = "Waylaid Crate: Journeyman Ore",
            qualityRGB = { 0.12, 1.00, 0.00 },
            subtitle = "Quest Item  Waylaid Supplies",
            sellPrice = "",
        }
        -- Waylaid Crate section
        push("MerchantMaster Waylaid Crate", "+40 Favor", COLORS.header, COLORS.positive, showCrate, true)
        push("  * 20x Iron Ore (Ready)", fmt(42000, not showCrate) .. " (" .. fmt(2100, not showCrate) .. " ea)", COLORS.label, COLORS.value, showCrate, false)
        push("    20x Mithril Ore", fmt(64000, not showCrate) .. " (" .. fmt(3200, not showCrate) .. " ea)", COLORS.alt, COLORS.headerRight, showCrate, false)
        push("  Fill Cost", fmt(42000, not showCrate), COLORS.label, COLORS.value, showCrate, false)
        push("  Net Cost", fmt(27000, not showCrate), COLORS.label, COLORS.value, showCrate, false)
        push("  Price / Favor", fmt(675, not showCrate), COLORS.header, COLORS.value, showCrate, false)
        push("  Reputation", "+50 Rep", COLORS.label, COLORS.headerRight, showCrate, false)
        push("  Cost / Rep (inc. crate)", fmt(540, not showCrate), COLORS.label, COLORS.value, showCrate, false)

        -- Market section
        push("MerchantMaster Market", "5m ago", COLORS.header, COLORS.headerRight, mktOn, true)
        push("  Min Buyout", fmt(18500, not showMin), COLORS.label, COLORS.value, showMin, false)
        local trendStr = showMktVal and " |cffff615c(-3.6%)|r" or (" " .. DIM_HEX .. "(-3.6%)|r")
        push("  Market Value (7d)", fmt(19200, not showMktVal) .. trendStr, COLORS.label, COLORS.value, showMktVal, false)
        push("  Listed Supply", "6 auctions", COLORS.label, COLORS.value, showListed, false)

        -- Inventory section
        push("MerchantMaster Accounting", "(per 1)", COLORS.header, COLORS.headerRight, accOn, true)
        push("  Total Inventory", "2 total", COLORS.label, COLORS.value, invOn, false)
        push("    Mainbank", formatInvCounts(2, 0, 0, 0, 0, invCompact), COLORS.alt, COLORS.headerRight, invByChar, false)
        push("    Bankalt", formatInvCounts(0, 0, 0, 0, 0, invCompact), COLORS.alt, COLORS.headerRight, invByChar and not invHideZero, false)

        return { header = header, rows = rows }
    elseif key == "silk_cloth" then
        local header = {
            name = "Silk Cloth",
            qualityRGB = { 1.00, 1.00, 1.00 },
            subtitle = "Trade Goods  Cloth (Stack of 20)",
            sellPrice = "Sell Price: " .. fmt(150, false),
        }
        -- Market section
        push("MerchantMaster Market", "3m ago", COLORS.header, COLORS.headerRight, mktOn, true)
        push("  Min Buyout", fmt(450, not showMin), COLORS.label, COLORS.value, showMin, false)
        local trendStr = showMktVal and " |cffff615c(-8.2%)|r" or (" " .. DIM_HEX .. "(-8.2%)|r")
        push("  Market Value (7d)", fmt(490, not showMktVal) .. trendStr, COLORS.label, COLORS.value, showMktVal, false)
        push("  Listed Supply", "1840 auctions", COLORS.label, COLORS.value, showListed, false)
        push("  Vendor Sell Price", fmt(150, not showVendor), COLORS.label, COLORS.value, showVendor, false)

        -- Accounting section
        push("MerchantMaster Accounting", "(per 1)", COLORS.header, COLORS.headerRight, accOn, true)
        push("  Avg Sell", fmt(480, not showAccSell), COLORS.label, COLORS.value, showAccSell, false)
        push("  Avg Buy", fmt(390, not showAccBasis), COLORS.label, COLORS.value, showAccBasis, false)
        local showZeroBasis = showAccBasis and not hideEmpty
        push("  Current Basis", fmt(0, not showZeroBasis), COLORS.label, COLORS.value, showZeroBasis, false)
        push("  Avg Profit", fmt(66, not showAccProfit, true), COLORS.label, COLORS.positive, showAccProfit, false)
        push("  Last Sold", fmt(475, not showAccLast), COLORS.label, COLORS.value, showAccLast, false)
        push("  Sale Rate / Expires", "84% / 1", COLORS.label, COLORS.value, showAccRate, false)

        -- Inventory section
        push("  Total Inventory", "120 total", COLORS.label, COLORS.value, invOn, false)
        push("    Mainbank", formatInvCounts(40, 40, 0, 0, 0, invCompact), COLORS.alt, COLORS.headerRight, invByChar, false)
        push("    Tailor", formatInvCounts(20, 0, 0, 0, 20, invCompact), COLORS.alt, COLORS.headerRight, invByChar, false)
        push("    Herbalt", formatInvCounts(0, 0, 0, 0, 0, invCompact), COLORS.alt, COLORS.headerRight, invByChar and not invHideZero, false)

        return { header = header, rows = rows }
    end

    -- Default: "green_lens"
    local header = {
        name = "Green Lens",
        qualityRGB = { 0.00, 0.44, 0.87 },
        subtitle = "Item Level 48  Head (Cloth)",
        sellPrice = "Sell Price: " .. fmt(8425, false),
    }

    -- 1. Market & Pricing
    push("MerchantMaster Market", "12m ago", COLORS.header, COLORS.headerRight, mktOn, true)
    push("  Min Buyout", fmt(485000, not showMin), COLORS.label, COLORS.value, showMin, false)
    local trendStr = showMktVal and " |cff47e073(+6.2%)|r" or (" " .. DIM_HEX .. "(+6.2%)|r")
    push("  Market Value (7d)", fmt(520000, not showMktVal) .. trendStr, COLORS.label, COLORS.value, showMktVal, false)
    push("  Listed Supply", "14 auctions", COLORS.label, COLORS.value, showListed, false)
    push("  Vendor Sell Price", fmt(8425, not showVendor), COLORS.label, COLORS.value, showVendor, false)

    -- 2. Crafting & Disenchant
    local econOn = showCraft or showDE
    push("MerchantMaster Crafting & DE", "", COLORS.header, COLORS.headerRight, econOn, true)
    push("  Craft Cost (est.)", fmt(342000, not showCraft), COLORS.label, COLORS.value, showCraft, false)
    push("  Craft Profit (est.)", fmt(118750, not showCraftProfit, true), COLORS.label, COLORS.positive, showCraftProfit, false)
    push("  DE Value (est.)", fmt(195000, not showDE), COLORS.label, COLORS.value, showDE, false)
    push("  DE Value (AS +20%)", fmt(234000, not showDEAS), COLORS.arcane, COLORS.arcane, showDEAS, false)
    push("  DE Learning", "Learned: 12 casts", COLORS.label, COLORS.positive, showDE, false)
    local shardLbl = showDEBD and "    75% |cff0070ddSmall Radiant Shard|r x1.0 |cffffd100[1]|r"
        or "    75% Small Radiant Shard x1.0 [1]"
    local dustLbl = showDEBD and "    25% |cffffffffVision Dust|r x2.5 |cffffd100[2-3]|r"
        or "    25% Vision Dust x2.5 [2-3]"
    push(shardLbl, fmt(165000, not showDEBD), COLORS.breakdown, COLORS.value, showDEBD, false)
    push(dustLbl, fmt(30000, not showDEBD), COLORS.breakdown, COLORS.value, showDEBD, false)

    -- 3. Accounting
    push("MerchantMaster Accounting", "(per 1)", COLORS.header, COLORS.headerRight, accOn, true)
    push("  Avg Sell", fmt(510000, not showAccSell), COLORS.label, COLORS.value, showAccSell, false)
    push("  Min / Max Sell", fmt(475000, not showAccSell) .. " / " .. fmt(560000, not showAccSell), COLORS.label, COLORS.value, showAccSell, false)
    push("  Current Basis", fmt(342000, not showAccBasis), COLORS.label, COLORS.value, showAccBasis, false)
    push("  Avg Profit", fmt(142500, not showAccProfit, true), COLORS.label, COLORS.positive, showAccProfit, false)
    push("  Last Sold", fmt(495000, not showAccLast), COLORS.label, COLORS.value, showAccLast, false)
    push("  Sale Rate / Expires", "68% / 2", COLORS.label, COLORS.value, showAccRate, false)
    push("  Slowing", "Review price or listing", COLORS.slowing, COLORS.slowing, showAccSlow, false)

    -- 4. Inventory (includes zero-count alt row so ttInvHideZero visibly dims/shows it)
    push("  Total Inventory", "3 total", COLORS.label, COLORS.value, invOn, false)
    push("    Mainbank", formatInvCounts(1, 1, 0, 0, 0, invCompact), COLORS.alt, COLORS.headerRight, invByChar, false)
    push("    Crafter", formatInvCounts(0, 0, 0, 0, 1, invCompact), COLORS.alt, COLORS.headerRight, invByChar, false)
    push("    Bankalt", formatInvCounts(0, 0, 0, 0, 0, invCompact), COLORS.alt, COLORS.headerRight, invByChar and not invHideZero, false)

    return { header = header, rows = rows }
end

local function add(tooltip, left, right, rL, gL, bL, rR, gR, bR)
    if right ~= nil and type(tooltip.AddDoubleLine) == "function" then
        if rL ~= nil then
            pcall(tooltip.AddDoubleLine, tooltip, left, right, rL, gL, bL, rR, gR, bR)
        else
            pcall(tooltip.AddDoubleLine, tooltip, left, right)
        end
    elseif type(tooltip.AddLine) == "function" then
        local txt = right ~= nil and (left .. "  " .. right) or left
        if rL ~= nil then
            pcall(tooltip.AddLine, tooltip, txt, rL, gL, bL)
        else
            pcall(tooltip.AddLine, tooltip, txt)
        end
    end
end

local function discoverItem(tooltip, itemID, stackCount)
    local link, count
    if secret(itemID) then return nil end
    local explicitID = number(itemID)
    if not explicitID and type(itemID) == "string" then explicitID = tonumber(itemID:match("item:(%d+)")) end
    itemID = explicitID
    local data
    if tooltip.GetTooltipData then
        local ok, result = pcall(tooltip.GetTooltipData, tooltip)
        if ok and type(result) == "table" and not secretTable(result) and not secret(result) then data = result end
    end
    if data then
        if not itemID then
            local raw = not secret(data.itemID) and data.itemID or (not secret(data.id) and data.id)
            itemID = number(raw)
            link = not secret(data.hyperlink) and data.hyperlink or (not secret(data.link) and data.link)
        end
        count = number(data.stackCount) or number(data.quantity) or number(data.count)
        if not count and type(data.args) == "table" and not secretTable(data.args) then
            for _, value in pairs(data.args) do
                if type(value) == "string" and not secret(value) then
                    link = link or value:match("item:%d+[^|]*") and value
                    if link then break end
                end
            end
        end
    end
    if tooltip.GetItem then
        local ok, _, gotLink = pcall(tooltip.GetItem, tooltip)
        if ok and not secret(gotLink) then link = link or gotLink end
    end
    if not itemID and type(link) == "string" then itemID = tonumber(link:match("item:(%d+)")) end
    count = number(stackCount) or count
    if not count or not itemID then
        local owner
        if tooltip.GetOwner then
            local ok, result = pcall(tooltip.GetOwner, tooltip)
            if ok and not secret(result) and not secretTable(result) then owner = result end
        end
        if owner then
            local bag, slot
            if owner.GetBagID then local ok, value = pcall(owner.GetBagID, owner); if ok then bag = number(value) end end
            if owner.GetSlotID then local ok, value = pcall(owner.GetSlotID, owner); if ok then slot = number(value) end end
            if not slot and owner.GetID then local ok, value = pcall(owner.GetID, owner); if ok then slot = number(value) end end
            if not bag and owner.GetParent then
                local ok, parent = pcall(owner.GetParent, owner)
                if ok and parent and not secret(parent) and not secretTable(parent) and parent.GetID then
                    local got, value = pcall(parent.GetID, parent); if got then bag = number(value) end
                end
            end
            local container = _G.C_Container
            if bag and slot and container and container.GetContainerItemInfo then
                local ok, info = pcall(container.GetContainerItemInfo, bag, slot)
                if ok and type(info) == "table" and not secretTable(info) and not secret(info) then
                    count = count or number(field(info, "stackCount")) or number(field(info, "quantity")) or 1
                    itemID = itemID or number(field(info, "itemID"))
                end
            elseif slot and _G.GetInventoryItemID then
                local ok, equipped = pcall(_G.GetInventoryItemID, "player", slot)
                if ok and not secret(equipped) then itemID = itemID or number(equipped); count = itemID and 1 end
            end
        end
    end
    return itemID, count or 1
end

local function onCleared(tooltip)
    seen[tooltip] = nil
end

local function installClearHook(tooltip)
    if clearHooked[tooltip] or not tooltip.HookScript then return end
    local ok = pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", onCleared)
    if ok then clearHooked[tooltip] = true end
end

local prepared, pending, waiters, preparedOrder = {}, {}, {}, {}
local generation, entryCount = nil, 0
local formatJobs, formatQueued = {}, false

local function signature()
    local store = ns.Store or {}
    local inv = ns.Inventory or {}
    local options = _G.MerchantMasterDB or {}
    local app = host.app
    local econ = app and app.char and app.char.economy
    if not econ and app and app.charKey and store.DeriveEcon then econ = store.DeriveEcon(app.charKey) end
    if not econ and store.CurrentCharAndEcon then local _; _, econ = store.CurrentCharAndEcon() end
    return table.concat({
        tostring(ns.Model),
        tostring(ns.Model and ns.Model.generation),
        tostring((host.GetPriceDataRevision and host.GetPriceDataRevision()) or host.priceCacheEpoch or 0),
        tostring(host.GetBackgroundPriceMode and host.GetBackgroundPriceMode() or ""),
        tostring(inv),
        tostring(store.accountingVersion or store.version or 0),
        tostring(inv.version or 0),
        tostring(econ),
        tostring(options.economy),
        tostring(TooltipPrefs.Get("ttEnabled")),
        tostring(TooltipPrefs.Get("ttPriceFormat")),
        tostring(TooltipPrefs.Get("ttModifier")),
        tostring(TooltipPrefs.Get("anTooltips")),
        tostring(TooltipPrefs.Get("ttAccSell")),
        tostring(TooltipPrefs.Get("ttAccBasis")),
        tostring(TooltipPrefs.Get("ttAccProfit")),
        tostring(TooltipPrefs.Get("ttAccLastSold")),
        tostring(TooltipPrefs.Get("ttAccSaleRate")),
        tostring(TooltipPrefs.Get("ttAccSlowing")),
        tostring(TooltipPrefs.Get("ttHideEmpty")),
        tostring(TooltipPrefs.Get("anTooltipInventory")),
        tostring(TooltipPrefs.Get("ttInvByChar")),
        tostring(TooltipPrefs.Get("ttInvHideZero")),
        tostring(TooltipPrefs.Get("ttInvCompact")),
        tostring(math.floor((_G.time and _G.time() or 0) / 86400)),
    }, "|")
end

function Tooltips.Invalidate()
    generation = nil
    prepared = {}
    pending = {}
    waiters = {}
    preparedOrder = {}
    formatJobs = {}
    entryCount = 0
    seen = setmetatable({}, { __mode = "k" })
end

function Tooltips.InvalidateAll()
    Tooltips.Invalidate()
    if host then
        if type(host.InvalidateMarketTooltipCache) == "function" then
            pcall(host.InvalidateMarketTooltipCache)
        end
        if type(host.InvalidateEconTooltipCache) == "function" then
            pcall(host.InvalidateEconTooltipCache)
        end
        if type(host.InvalidateCrateTooltipCache) == "function" then
            pcall(host.InvalidateCrateTooltipCache)
        end
    end
end
TooltipPrefs.InvalidateAll = Tooltips.InvalidateAll

local function currentGeneration()
    local sig = signature()
    if sig ~= generation then
        Tooltips.Invalidate()
        generation = sig
    end
    return sig
end

local function presentation(id, qty, shift)
    return id .. ":" .. (shift and math.max(1, qty) or 1) .. ":" .. tostring(shift)
end

local function prepare(id, qty, shift)
    local lines = {}
    local tooltip = {
        AddDoubleLine = function(_, left, right, rL, gL, bL, rR, gR, bR)
            lines[#lines + 1] = { left, right, rL, gL, bL, rR, gR, bR }
        end,
        AddLine = function(_, left, rL, gL, bL)
            lines[#lines + 1] = { left, nil, rL, gL, bL }
        end,
    }
    local analytics = ns.Model
    if not analytics then return false end
    local indexedStats, indexedHint, indexed
    if analytics.GetPreparedTooltipStats then
        indexedStats, indexedHint, indexed = analytics.GetPreparedTooltipStats(id)
    end
    local get = analytics.GetPriceSource
    local function price(key)
        if indexed then
            local value = number(field(indexedStats, ({
                AvgSell = "avgSell",
                AvgBuy = "avgBuy",
                CurBasis = "curBasis",
                SaleRate = "saleRate",
                NumExpires = "expSinceSale",
            })[key]))
            if key == "SaleRate" and value then value = math.floor(value * 100 + 0.5) end
            return value
        end
        if not get then return nil end
        local ok, value = pcall(get, key, id)
        if ok then return number(value) end
    end

    local avgSell, avgBuy = price("AvgSell"), price("AvgBuy")
    local curBasis, avgProfit = price("CurBasis"), price("AvgProfit")
    local saleRate, expired = price("SaleRate"), price("NumExpires")
    local stats = indexedStats
    if not indexed and analytics.GetItemStats then
        local ok, value = pcall(analytics.GetItemStats, id)
        if ok and type(value) == "table" and not secretTable(value) and not secret(value) then stats = value end
    end
    local hint = indexedHint
    if not indexed and analytics.GetSaleHint then
        local ok, value = pcall(analytics.GetSaleHint, id)
        if ok and type(value) == "table" and not secretTable(value) and not secret(value) then hint = value end
    end

    local cH = COLORS.header
    local cHR = COLORS.headerRight
    local cL = COLORS.label
    local cV = COLORS.value
    local cAlt = COLORS.alt
    local cPos = COLORS.positive
    local cNeg = COLORS.negative
    local cSlow = COLORS.slowing

    local showSell = TooltipPrefs.Get("ttAccSell") ~= false
    local showBasis = TooltipPrefs.Get("ttAccBasis") ~= false
    local showProfit = TooltipPrefs.Get("ttAccProfit") ~= false
    local showLastSold = TooltipPrefs.Get("ttAccLastSold") ~= false
    local showSaleRate = TooltipPrefs.Get("ttAccSaleRate") ~= false
    local showSlowing = TooltipPrefs.Get("ttAccSlowing") ~= false
    local hideEmpty = TooltipPrefs.Get("ttHideEmpty") ~= false

    local multiplier = shift and math.max(1, qty) or 1
    add(tooltip, "MerchantMaster Accounting", shift and ("(x" .. tostring(multiplier) .. ")") or "(per 1)",
        cH[1], cH[2], cH[3], cHR[1], cHR[2], cHR[3])

    if showSell then
        if avgSell then
            add(tooltip, "  Avg Sell", money(avgSell * multiplier),
                cL[1], cL[2], cL[3], cV[1], cV[2], cV[3])
        end
        local minSell, maxSell = number(field(stats, "minSell")), number(field(stats, "maxSell"))
        if minSell and maxSell then
            add(tooltip, "  Min / Max Sell", money(minSell * multiplier) .. " / " .. money(maxSell * multiplier),
                cL[1], cL[2], cL[3], cV[1], cV[2], cV[3])
        end
    end

    if showBasis then
        if avgBuy then
            add(tooltip, "  Avg Buy", money(avgBuy * multiplier),
                cL[1], cL[2], cL[3], cV[1], cV[2], cV[3])
        end
        if curBasis and (not hideEmpty or curBasis ~= 0) then
            add(tooltip, "  Current Basis", money(curBasis * multiplier),
                cL[1], cL[2], cL[3], cV[1], cV[2], cV[3])
        end
    end

    if showProfit then
        avgProfit = avgProfit or number(field(stats, "avgProfit"))
        if avgProfit then
            local pc = avgProfit >= 0 and cPos or cNeg
            add(tooltip, "  Avg Profit", money(avgProfit * multiplier, false),
                cL[1], cL[2], cL[3], pc[1], pc[2], pc[3])
        end
    end

    if showLastSold then
        local lastSoldUnit = number(field(stats, "lastSoldUnit"))
        if lastSoldUnit then
            add(tooltip, "  Last Sold", money(lastSoldUnit * multiplier),
                cL[1], cL[2], cL[3], cV[1], cV[2], cV[3])
        end
    end

    if showSaleRate and (saleRate ~= nil or expired ~= nil) then
        if not hideEmpty or saleRate ~= nil or (expired or 0) ~= 0 then
            local rate = saleRate and (tostring(math.floor(saleRate + 0.5)) .. "%") or "-"
            add(tooltip, "  Sale Rate / Expires", rate .. " / " .. tostring(expired or 0),
                cL[1], cL[2], cL[3], cV[1], cV[2], cV[3])
        end
    end

    if showSlowing and hint and (field(hint, "isSlowing") == true or (number(field(hint, "expSinceSale")) or 0) >= 5) then
        add(tooltip, "  Slowing", "Review price or listing",
            cSlow[1], cSlow[2], cSlow[3], cSlow[1], cSlow[2], cSlow[3])
    end

    if TooltipPrefs.Get("anTooltipInventory") ~= false and ns.Inventory and ns.Inventory.GetItemBreakdown then
        local ok, breakdown = pcall(ns.Inventory.GetItemBreakdown, id)
        local byChar = field(breakdown, "byChar")
        if ok and type(byChar) == "table" and not secretTable(byChar) then
            local total = number(field(breakdown, "total")) or 0
            add(tooltip, "  Total Inventory", tostring(total) .. " total",
                cL[1], cL[2], cL[3], cV[1], cV[2], cV[3])

            if TooltipPrefs.Get("ttInvByChar") ~= false then
                local invHideZero = TooltipPrefs.Get("ttInvHideZero") ~= false
                local invCompact = TooltipPrefs.Get("ttInvCompact") ~= false
                local now = _G.time and _G.time() or 0
                for _, entry in ipairs(byChar) do
                    if type(entry) == "table" and not secret(entry) and not secretTable(entry) then
                        local shortName, fullName = field(entry, "shortName"), field(entry, "char")
                        local char = type(shortName) == "string" and shortName or fullName
                        if type(char) == "string" and not secret(char) then
                            local bags = number(field(entry, "bags")) or 0
                            local bank = number(field(entry, "bank")) or 0
                            local mail = number(field(entry, "mail")) or 0
                            local inTransit = number(field(entry, "inTransit")) or 0
                            local ah = number(field(entry, "ah")) or 0
                            local charTotal = bags + bank + mail + inTransit + ah
                            if not invHideZero or charTotal > 0 then
                                local counts = formatInvCounts(bags, bank, mail, inTransit, ah, invCompact)
                                local stamp = number(field(entry, "updatedAt"))
                                local staleFlag = field(entry, "stale") == true
                                local stale = staleFlag or (stamp and (now - stamp) > 7 * 86400)
                                add(tooltip, "    " .. char .. (stale and " (stale)" or ""), counts,
                                    cAlt[1], cAlt[2], cAlt[3], cHR[1], cHR[2], cHR[3])
                            end
                        end
                    end
                end
            end
        end
    end

    return lines
end

local function appendPrepared(tooltip, key, lines)
    if seen[tooltip] == key then return end
    for _, line in ipairs(lines) do
        add(tooltip, line[1], line[2], line[3], line[4], line[5], line[6], line[7], line[8])
    end
    seen[tooltip] = key
end

local function ownerOf(tooltip)
    if tooltip.GetOwner then
        local ok, value = pcall(tooltip.GetOwner, tooltip)
        if ok and not secret(value) then return value end
    end
end

local function enqueueFormatting(job)
    formatJobs[#formatJobs + 1] = job
    if formatQueued then return end
    formatQueued = true
    local function drain()
        local jobs = {}
        for i = 1, math.min(4, #formatJobs) do
            jobs[i] = table.remove(formatJobs, 1)
        end
        for _, run in ipairs(jobs) do run() end
        if #formatJobs > 0 and _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0.01, drain)
        else
            formatQueued = false
        end
    end
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0.01, drain)
    else
        drain()
    end
end

local function isStackShiftActive()
    if TooltipPrefs.Get("ttModifier") == "shift" then return false end
    if _G.IsShiftKeyDown then
        local ok, value = pcall(_G.IsShiftKeyDown)
        return ok and not secret(value) and value == true
    end
    return false
end

local function queue(id, qty, shift)
    local gen = currentGeneration()
    local key = presentation(id, qty, shift)
    if prepared[key] or pending[key] then return key end
    pending[key] = true
    local function ready(success)
        if currentGeneration() ~= gen then return end
        if success == false then
            pending[key] = nil
            waiters[key] = nil
            return
        end
        -- Bound formatting/inventory work as well as the aggregate scan.
        local function build()
            if currentGeneration() ~= gen then return end
            local lines = prepare(id, qty, shift)
            if entryCount >= 512 then
                prepared[table.remove(preparedOrder, 1)] = nil
                entryCount = entryCount - 1
            end
            prepared[key] = lines or {}
            preparedOrder[#preparedOrder + 1] = key
            entryCount = entryCount + 1
            pending[key] = nil
            local waiting = waiters[key]
            waiters[key] = nil
            for tooltip, request in pairs(waiting or {}) do
                if request.gen == generation and ownerOf(tooltip) == request.owner and seen[tooltip] == request.marker then
                    if TooltipPrefs.Get("ttEnabled") ~= false and TooltipPrefs.IsModifierSatisfied() then
                        local actual, quantity = discoverItem(tooltip)
                        local isShift = isStackShiftActive()
                        if actual == id and presentation(id, quantity, isShift) == key then
                            appendPrepared(tooltip, key, prepared[key])
                            if tooltip.Show then tooltip:Show() end
                        end
                    end
                end
            end
        end
        enqueueFormatting(build)
    end
    if ns.Model and ns.Model.PrepareTooltipIndexes then
        ns.Model.PrepareTooltipIndexes(ready)
    else
        ready()
    end
    return key
end

function Tooltips.PrimeItems(itemIDs, isCurrent)
    currentGeneration()
    local ids = {}
    for _, id in ipairs(itemIDs or {}) do
        id = number(id)
        if id and id > 0 then ids[id] = true end
    end
    local list = {}
    for id in pairs(ids) do list[#list + 1] = id end
    local index = 1
    local gen = generation
    local function step()
        if (isCurrent and not isCurrent()) or currentGeneration() ~= gen then return end
        local stop = math.min(#list, index + 7)
        while index <= stop do
            queue(list[index], 1, false)
            index = index + 1
        end
        if index <= #list and _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0.01, step)
        end
    end
    step()
end

function Tooltips.OnTooltipItem(tooltip, itemID, stackCount)
    if not tooltip or secret(tooltip) or secretTable(tooltip) then return false end
    if TooltipPrefs.Get("ttEnabled") == false then return false end
    if not TooltipPrefs.IsModifierSatisfied() then return false end
    if TooltipPrefs.Get("anTooltips") == false then return false end
    installClearHook(tooltip)
    local id, qty = discoverItem(tooltip, itemID, stackCount)
    if not id or id <= 0 or not ns.Model then return false end
    local shift = isStackShiftActive()
    currentGeneration()
    local key = queue(id, qty, shift)
    local lines = prepared[key]
    if lines then
        appendPrepared(tooltip, key, lines)
    else
        local marker = "pending:" .. key
        seen[tooltip] = marker
        waiters[key] = waiters[key] or setmetatable({}, { __mode = "k" })
        waiters[key][tooltip] = { gen = generation, owner = ownerOf(tooltip), marker = marker }
    end
    return true
end

return Tooltips
