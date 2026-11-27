local addonName, host = ...
host.Analytics = host.Analytics or {}
local ns = host.Analytics
_G.MerchantMasterAnalytics = ns
local unpack = unpack or table.unpack
local function H()
    return host
end

local UI = { controls = {}, views = {}, tables = {}, auxTables = {}, _styledTables = {}, _actionButtons = {} }
ns.UI = UI
local function readable(value)
    if type(_G.issecretvalue) == "function" then
        local ok, secret = pcall(_G.issecretvalue, value)
        if not ok or secret then return false end
    end
    if type(value) == "table" and type(_G.issecrettable) == "function" then
        local ok, secret = pcall(_G.issecrettable, value)
        if not ok or secret then return false end
    end
    return true
end
local dateFn = _G.date or (os and os.date)
local APPLE_ASSET = "Interface\\AddOns\\" .. tostring(addonName or "MerchantMaster") .. "\\Assets\\apple\\"

local FALLBACK_PALETTES = {
    dark = {
        mode = "dark",
        winBg = { 0.110, 0.110, 0.118, 1.0 },
        cardBg = { 0.173, 0.173, 0.180, 1.0 },
        cardAltBg = { 0.133, 0.133, 0.141, 1.0 },
        cardHover = { 1.0, 1.0, 1.0, 0.06 },
        pillTrack = { 1.0, 1.0, 1.0, 0.08 },
        pillThumb = { 1.0, 1.0, 1.0, 0.17 },
        navActiveBg = { 1.0, 1.0, 1.0, 0.13 },
        border = { 1.0, 1.0, 1.0, 0.14 },
        borderStrong = { 1.0, 1.0, 1.0, 0.24 },
        specular = { 1.0, 1.0, 1.0, 0.24 },
        separator = { 0.329, 0.329, 0.345, 0.55 },
        text = { 1.0, 1.0, 1.0, 1.0 },
        textSecondary = { 0.922, 0.922, 0.961, 0.62 },
        textMuted = { 0.596, 0.596, 0.616, 1.0 },
        accentBlue = { 0.000, 0.569, 1.000, 1.0 },
        accentGreen = { 0.188, 0.820, 0.345, 1.0 },
        accentOrange = { 1.000, 0.573, 0.188, 1.0 },
        accentRed = { 1.000, 0.271, 0.227, 1.0 },
        accentPurple = { 0.749, 0.353, 0.949, 1.0 },
        hexText = "ffffff",
        hexMuted = "98989d",
        hexGreen = "30d158",
        hexRed = "ff453a",
        hexOrange = "ff9230",
        hexBlue = "0091ff",
    },
    light = {
        mode = "light",
        winBg = { 0.949, 0.949, 0.969, 1.0 },
        cardBg = { 1.0, 1.0, 1.0, 1.0 },
        cardAltBg = { 0.949, 0.949, 0.969, 1.0 },
        cardHover = { 0.0, 0.0, 0.0, 0.04 },
        pillTrack = { 0.0, 0.0, 0.0, 0.06 },
        pillThumb = { 1.0, 1.0, 1.0, 1.0 },
        navActiveBg = { 0.0, 0.0, 0.0, 0.10 },
        border = { 0.0, 0.0, 0.0, 0.12 },
        borderStrong = { 0.0, 0.0, 0.0, 0.22 },
        specular = { 1.0, 1.0, 1.0, 0.80 },
        separator = { 0.235, 0.235, 0.263, 0.26 },
        text = { 0.0, 0.0, 0.0, 1.0 },
        textSecondary = { 0.235, 0.235, 0.263, 0.76 },
        textMuted = { 0.431, 0.431, 0.451, 1.0 },
        accentBlue = { 0.000, 0.533, 1.000, 1.0 },
        accentGreen = { 0.000, 0.478, 0.169, 1.0 },
        accentOrange = { 0.702, 0.290, 0.000, 1.0 },
        accentRed = { 0.839, 0.141, 0.161, 1.0 },
        accentPurple = { 0.686, 0.322, 0.871, 1.0 },
        hexText = "000000",
        hexMuted = "6e6e73",
        hexGreen = "007a2b",
        hexRed = "d62429",
        hexOrange = "b34a00",
        hexBlue = "0088ff",
    },
}

local function getPalette()
    local h = H()
    local theme = h and h.Theme
    local mode = (theme and theme.GetMode and theme.GetMode()) or "dark"
    if mode ~= "light" then mode = "dark" end
    local pal = (theme and theme.GetActivePalette and theme.GetActivePalette()) or (theme and theme.PALETTES and theme.PALETTES[mode])
    local fb = FALLBACK_PALETTES[mode]
    if not pal then return fb, mode end
    local out = {}
    for k, v in pairs(fb) do out[k] = pal[k] or v end
    out.mode = mode
    return out, mode
end

local function assetPath(name)
    local h = H()
    local assets = h and h.Theme and h.Theme.ASSETS
    if assets and assets[name] then return assets[name] end
    return APPLE_ASSET .. name
end

local function applyFont(fs, size, weight, flags)
    if type(fs) ~= "table" then return end
    local h = H()
    local theme = h and h.Theme
    if theme and theme.ApplyFont then
        theme.ApplyFont(fs, size, weight, flags)
        return
    end
    if fs.SetFont then
        local fonts = theme and theme.FONTS
        local isSemi = (weight == "semibold" or weight == "bold" or weight == "heavy")
        local fallbackFont = (fonts and fonts.fallback) or _G.STANDARD_TEXT_FONT or "Fonts\\ARIALN.TTF"
        local target = (fonts and (isSemi and fonts.semibold or fonts.regular)) or fallbackFont
        local sz = tonumber(size) or 12
        local fl = flags or ""
        local ok = fs:SetFont(target, sz, fl)
        local loaded = fs.GetFont and select(1, fs:GetFont())
        if ok == false or (ok == nil and loaded ~= target) then
            fs:SetFont(fallbackFont, sz, fl)
        end
    end
    if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
end

local function setFontSize(fs, size, weight)
    applyFont(fs, size, weight or "regular")
end

local function setTextColor(fs, col, fallbackA)
    if fs and fs.SetTextColor and col then
        fs:SetTextColor(col[1], col[2], col[3], col[4] or fallbackA or 1)
    end
end

local function applySurface(frame, kind, fillCol, strokeCol)
    local h = H()
    local theme = h and h.Theme
    local sc = (type(strokeCol) == "table") and strokeCol or false
    if not frame._appleSurf then
        if theme and theme.NineApple then
            frame._appleSurf = theme.NineApple(frame, kind or "glass_r10", fillCol, sc, { noSpecular = true })
        elseif theme and theme.Card then
            local radius = kind == "glass_r16" and 16 or (kind == "glass_r12" and 12 or (kind == "glass_r8" and 8 or 10))
            frame._appleSurf = theme.Card(frame, frame, radius, sc or { 0, 0, 0, 0 }, fillCol)
        end
    end
    local surf = frame._appleSurf
    if surf then
        if surf.SetFill and fillCol then surf:SetFill(fillCol[1], fillCol[2], fillCol[3], fillCol[4] or 1) end
        if sc then
            if surf.SetBorder then surf:SetBorder(sc[1], sc[2], sc[3], sc[4] or 1) end
            if surf.SetColors then surf:SetColors(fillCol, sc) end
        else
            if surf.stroke and surf.stroke.SetShown then surf.stroke:SetShown(false) end
            if surf.border and surf.border.SetShown then surf.border:SetShown(false) end
        end
    end
end

local function groupThousands(n)
    local s = tostring(n)
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if formatted:sub(1, 1) == "," then formatted = formatted:sub(2) end
    return formatted
end

local function formatMoneyApple(v, signed)
    local pal = getPalette()
    if not readable(v) then return "-" end
    local copper = tonumber(v) or 0
    local h = H()
    if h and h.Theme and h.Theme.FormatMoneyFable then
        return h.Theme.FormatMoneyFable(copper, signed)
    elseif h and h.Theme and h.Theme.FormatMoneyParts then
        local parts = h.Theme.FormatMoneyParts(copper, signed, true)
        if type(parts) == "table" and parts.text then return parts.text end
    end
    local n = math.floor(copper + 0.5)
    local absN = math.abs(n)
    local digitHex = pal.hexText
    local prefix = ""
    if signed then
        if n > 0 then
            digitHex = pal.hexGreen
            prefix = "|cff" .. digitHex .. "+|r"
        elseif n < 0 then
            digitHex = pal.hexRed
            prefix = "|cff" .. digitHex .. "-|r"
        else
            digitHex = pal.hexMuted
        end
    elseif n < 0 then
        digitHex = pal.hexRed
        prefix = "|cff" .. digitHex .. "-|r"
    end
    local unitHex = pal.hexMuted
    local g = math.floor(absN / 10000)
    local s = math.floor((absN % 10000) / 100)
    local c = absN % 100
    local chunks = {}
    if g > 0 then
        chunks[#chunks + 1] = "|cff" .. digitHex .. groupThousands(g) .. "|r|cff" .. unitHex .. "g|r"
        if s > 0 or c > 0 then
            chunks[#chunks + 1] = "|cff" .. digitHex .. string.format("%02d", s) .. "|r|cff" .. unitHex .. "s|r"
        end
    elseif s > 0 then
        chunks[#chunks + 1] = "|cff" .. digitHex .. tostring(s) .. "|r|cff" .. unitHex .. "s|r"
        if c > 0 then
            chunks[#chunks + 1] = "|cff" .. digitHex .. string.format("%02d", c) .. "|r|cff" .. unitHex .. "c|r"
        end
    else
        chunks[#chunks + 1] = "|cff" .. digitHex .. tostring(c) .. "|r|cff" .. unitHex .. "c|r"
    end
    return prefix .. table.concat(chunks, " ")
end

local PERIODS = { { key = "today", label = "Today" }, { key = "3d", label = "3 Days" }, { key = "7d", label = "7 Days" }, { key = "14d", label = "14 Days" },
    { key = "30d", label = "30 Days" }, { key = "60d", label = "60 Days" }, { key = "90d", label = "90 Days" }, { key = "all", label = "All Time" } }
local TYPES = { { key = "all", label = "All Types" }, { key = "buys", label = "Buys" },
    { key = "sells", label = "Sells" }, { key = "auctions", label = "Auctions" },
    { key = "vendor", label = "Vendor" }, { key = "trade", label = "Trade" }, { key = "loot", label = "Loot & Gather" },
    { key = "craft", label = "Crafting" }, { key = "quests", label = "Quests & Writs" }, { key = "favor", label = "Favor" },
    { key = "TRAINER_FEE", label = "Trainer Fee" }, { key = "GUILD_DEPOSIT", label = "Guild Deposit" },
    { key = "GUILD_WITHDRAW", label = "Guild Withdraw" }, { key = "AH_BID", label = "AH Bid" },
    { key = "AH_OUTBID", label = "AH Outbid" } }
local MODES = { { key = "profit", label = "View: Best Profit", col = "profit" },
    { key = "turnaround", label = "View: High Turnaround", col = "daysToSell", asc = true },
    { key = "slowing", label = "View: Slowing Sales", col = "slowRatio", asc = true },
    { key = "relists", label = "View: Constant Relists", col = "relists" } }
local PORTFOLIO_VIEWS = { { key = "breakdown", label = "View: Wealth Breakdown" },
    { key = "chars", label = "View: By Character" }, { key = "inventory", label = "View: Item Inventory" } }

local function db() return _G.MerchantMasterDB or {} end
local function ledger() return _G.MerchantMasterLedgerDB or {} end
local function app() return H() and H().app end
local function money(v, signed) return formatMoneyApple(v, signed) end
local function num(v) return groupThousands(math.floor((tonumber(v) or 0) + 0.5)) end
local function decimal(v) return v ~= nil and string.format("%.2f", v) or "-" end
local function percent(v) return v ~= nil and string.format("%.1f%%", v * 100) or "-" end
local function when(t) return t and dateFn and dateFn("%m/%d %H:%M", t) or "-" end

local function formatRelativeTime(t)
    t = tonumber(t)
    if not t or t <= 0 then return "-" end
    local now = (_G.time and _G.time()) or (os and os.time and os.time()) or t
    local diff = math.max(0, math.floor(now - t))
    if diff < 60 then
        return tostring(diff) .. " Sec"
    elseif diff < 3600 then
        local m = math.floor(diff / 60)
        local s = diff % 60
        return tostring(m) .. " Min " .. tostring(s) .. " Sec"
    elseif diff < 86400 then
        local h = math.floor(diff / 3600)
        local m = math.floor((diff % 3600) / 60)
        return tostring(h) .. " Hr " .. tostring(m) .. " Min"
    else
        local d = math.floor(diff / 86400)
        local h = math.floor((diff % 86400) / 3600)
        return tostring(d) .. (d == 1 and " Day " or " Days ") .. tostring(h) .. " Hr"
    end
end

local QUALITY_HEX_DARK = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
    [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff",
}
local QUALITY_HEX_LIGHT = {
    [0] = "6e6e73", [1] = "000000", [2] = "007a2b", [3] = "005bb5",
    [4] = "7c22b8", [5] = "b34a00", [6] = "8a6d3b", [7] = "007799",
}

local function itemQualityHex(itemID, quality)
    local pal = getPalette()
    local q = readable(quality) and tonumber(quality) or nil
    local id = readable(itemID) and tonumber(itemID) or nil
    if q == nil and id and id > 0 then
        if _G.C_Item and _G.C_Item.GetItemQualityByID then
            local ok, v = pcall(_G.C_Item.GetItemQualityByID, id)
            if ok and readable(v) then q = tonumber(v) end
        end
        if q == nil and _G.GetItemInfo then
            local ok, _, _, iq = pcall(_G.GetItemInfo, id)
            if ok and readable(iq) then q = tonumber(iq) end
        end
    end
    if q == nil then return nil end
    local tbl = (pal.mode == "light") and QUALITY_HEX_LIGHT or QUALITY_HEX_DARK
    return tbl[q]
end

local function formatItemDisplay(itemID, name, icon, quality)
    local text = name or (itemID and ("Item " .. tostring(itemID))) or "-"
    local qHex = itemQualityHex(itemID, quality)
    if qHex and text ~= "-" and not tostring(text):find("|cff", 1, true) then
        text = "|cff" .. qHex .. tostring(text) .. "|r"
    end
    if icon then
        return "|T" .. tostring(icon) .. ":15:15:0:0:64:64:4:60:4:60|t " .. tostring(text)
    end
    return tostring(text)
end

local function item(row, field)
    local text = row[field or "name"] or row.itemName or (row.itemID and ("Item " .. row.itemID)) or "-"
    return formatItemDisplay(row.itemID, text, row.icon or row.itemIcon, row.quality)
end
local function mfield(key, signed)
    return function(row) return money(row[key], signed) end
end
local function pricefield(key, signed)
    return function(row) return row[key] ~= nil and money(row[key], signed) or "-" end
end
local function column(key, title, width, align, render)
    local coin={profit=true,unit=true,total=true,avgBuy=true,avgSell=true,avgCost=true,gold=true,bags=true,bank=true,mail=true,gear=true,listed=true,
        unitValue=true,totalValue=true,grossCost=true,refunds=true,pendingRefund=true,netCost=true,costPerRep=true,investCost=true,realizedProfit=true,netPayback=true,perRep=true,
        curBasis=true,avgProfit=true,market=true,craftCost=true}
    return { key = key, label = title, width = width, minWidth = coin[key] and math.max(90,width) or width, align = coin[key] and "RIGHT" or (align or "RIGHT"), defaultAsc = false, render = render }
end
local function slowing(r)
    local pal = getPalette()
    return r.isSlowing and ("|cff" .. pal.hexOrange .. "Slow " .. decimal(r.slowRatio) .. "x|r")
        or ("|cff" .. pal.hexGreen .. "OK|r")
end

local function ledgerTypeBadge(r)
    local pal = getPalette()
    local lbl = r.typeLabel or (ns.Model and ns.Model.TYPE_LABELS and ns.Model.TYPE_LABELS[r.type]) or r.type or "-"
    if r.type == "DISENCHANT_BROKEN" then
        local purple = pal.hexPurple or (pal.mode == "light" and "7c22b8" or "b07cff")
        return "|cff" .. purple .. lbl .. "|r"
    elseif r.type == "DISENCHANT_RECEIVE" then
        return "|cff" .. pal.hexGreen .. "+ " .. lbl .. "|r"
    end
    local t = r.total
    local isPos = (type(t) == "number" and t > 0) or r.type == "AH_SELL" or r.type == "VENDOR_SELL" or r.type == "COD_SELL" or r.type == "TRADE_SELL" or r.type == "LOOT" or r.type == "QUEST_MONEY" or r.type == "POUCH_MONEY" or r.type == "GUILD_WITHDRAW" or r.type == "AH_OUTBID"
    local isNeg = (type(t) == "number" and t < 0) or r.type == "AH_BUY" or r.type == "VENDOR_BUY" or r.type == "COD_BUY" or r.type == "TRADE_BUY" or r.type == "VENDOR_BUYBACK" or r.type == "AH_EXPIRE" or r.type == "AH_CANCEL" or r.type == "REPAIR" or r.type == "POSTAGE" or r.type == "TRAINER_FEE" or r.type == "GUILD_DEPOSIT" or r.type == "AH_BID"
    if isPos and (t == nil or t >= 0) then
        return "|cff" .. pal.hexGreen .. "+ " .. lbl .. "|r"
    elseif isNeg and (t == nil or t <= 0) then
        return "|cff" .. pal.hexRed .. "- " .. lbl .. "|r"
    end
    return "|cff" .. pal.hexMuted .. lbl .. "|r"
end

local function formatDeQty(q)
    local n = tonumber(q) or 0
    local r = math.floor(n + 0.5)
    if math.abs(n - r) < 1e-6 then return num(r) end
    return string.format("%.1f", n)
end

local function renderLedgerTotal(r)
    local pal = getPalette()
    if r.type == "DISENCHANT_BROKEN" then
        local cost = tonumber(r.cogs) or tonumber(r.extra and r.extra.deSrcCost) or 0
        return "|cff" .. pal.hexMuted .. "Cost|r " .. money(cost, false)
    elseif r.type == "DISENCHANT_RECEIVE" then
        local basis = (r.extra and r.extra.allocBasis ~= nil) and tonumber(r.extra.allocBasis) or 0
        return "|cff" .. pal.hexMuted .. "Cost|r " .. money(basis, false)
    end
    return money(r.total, true)
end

local function renderLedgerWhere(r)
    local w = r.where or ""
    local deOrigin = r.extra and r.extra.deOrigin
    if type(deOrigin) == "table" and type(deOrigin.srcName) == "string" and deOrigin.srcName ~= "" then
        local pal = getPalette()
        local tag = "|cff" .. pal.hexMuted .. "via DE: " .. deOrigin.srcName .. "|r"
        return (w ~= "" and (w .. " ") or "") .. tag
    end
    return w ~= "" and w or "-"
end

local TOP_COLS = {
    column("name", "Item", 250, "LEFT", item),
    column("profit", "Profit", 115, nil, mfield("profit", true)),
}
local LEDGER_COLS = {
    column("time", "Time Frame", 98, "LEFT", function(r) return formatRelativeTime(r.time) end),
    column("char", "Character", 96, "LEFT", function(r) return r.charShort or r.char or "-" end),
    column("type", "Type", 94, "LEFT", ledgerTypeBadge),
    column("where", "Where", 100, "LEFT", renderLedgerWhere),
    column("itemName", "Item", 184, "LEFT", function(r) return item(r, "itemName") end),
    column("qty", "Qty", 46),
    column("unit", "Per Item", 80, nil, mfield("unit")),
    column("total", "Total", 88, nil, renderLedgerTotal),
    column("counterparty", "Player", 108, "LEFT"),
}
local ITEM_COLS = {
    column("name", "Item", 180, "LEFT", item), column("profit", "Profit", 76, nil, mfield("profit", true)),
    column("bought", "Bought", 50), column("sold", "Sold", 45),
    column("avgBuy", "Avg Buy", 65, nil, pricefield("avgBuy")), column("avgSell", "Avg Sell", 65, nil, pricefield("avgSell")),
    column("profitPct", "Profit %", 60, nil, function(r) return percent(r.profitPct) end),
    column("saleRate", "Sale Rate", 66, nil, function(r) return percent(r.saleRate) end),
    column("expSinceSale", "Exp/Sale", 60), column("avgCost", "Avg Cost", 75, nil, function(r)
        local pal = getPalette()
        return money(r.avgCost or ((r.sold or 0) > 0 and (r.cogs or 0) / r.sold or 0)) .. (r.est and (" |cff" .. pal.hexOrange .. "(est.)|r") or "")
    end),
    column("slowRatio", "Slowing", 72, "CENTER", slowing), column("relists", "Relists", 55),
}
local function renderWealthLabel(r)
    local pal = getPalette()
    if r.isCategory then
        local mark = r.expanded and ("|cff" .. pal.hexBlue .. "[-]|r ") or ("|cff" .. pal.hexBlue .. "[+]|r ")
        local cnt = (r.itemCount or 0) > 0 and (" |cff" .. pal.hexMuted .. "(" .. r.itemCount .. ")|r") or (" |cff" .. pal.hexMuted .. "(empty)|r")
        return mark .. "|cff" .. pal.hexText .. (r.title or r.label or "-") .. "|r" .. cnt
    end
    local iconTxt = (r.icon or r.itemIcon) and ("|T" .. (r.icon or r.itemIcon) .. ":15:15|t ") or ""
    return "    " .. iconTxt .. (r.label or r.name or "-")
end
local WEALTH_COLS = {
    column("label", "Category / Item", 320, "LEFT", renderWealthLabel),
    column("owner", "Character", 150, "LEFT", function(r)
        local pal = getPalette()
        return r.owner or (r.isCategory and ("|cff" .. pal.hexMuted .. "Click to expand|r") or "-")
    end),
    column("basis", "Source / Basis", 156, "LEFT", function(r) return r.basis or "-" end),
    column("qty", "Qty", 74, "RIGHT", function(r) return r.qty ~= nil and num(r.qty) or "-" end),
    column("unit", "Unit Value", 140, "RIGHT", function(r) return r.unit ~= nil and money(r.unit) or "-" end),
    column("total", "Total Value", 168, "RIGHT", mfield("total")),
}
local PORTFOLIO_COLS = {
    column("char", "Character", 142, "LEFT", function(r) return r.charShort or r.char end),
    column("gold", "Gold", 98, nil, mfield("gold")), column("bags", "Bags", 86, nil, mfield("bags")),
    column("bank", "Bank", 86, nil, mfield("bank")), column("mail", "Mail", 86, nil, mfield("mail")),
    column("gear", "Gear", 86, nil, mfield("gear")), column("listed", "Listed on AH", 102, nil, mfield("listed")),
    column("total", "Total Wealth", 118, nil, mfield("total")), column("lastDay", "Last Seen", 76, nil, function(r) return r.lastDay or "-" end),
}
local INVENTORY_COLS = {
    column("name", "Item", 220, "LEFT", item), column("bags", "Bags", 62), column("bank", "Bank", 62),
    column("mail", "Mail", 62), column("inTransit", "Transit", 62), column("ah", "AH", 62),
    column("gear", "Gear", 62), column("guild", "Guild", 62), column("totalQty", "Total", 70),
    column("unitValue", "Unit Value", 110, nil, mfield("unitValue")), column("totalValue", "Value", 120, nil, mfield("totalValue")),
}
local DETAIL_TX_COLS = {
    column("time", "Time", 98, "LEFT", function(r) return when(r.time) end),
    column("type", "Type", 82, "LEFT", ledgerTypeBadge),
    column("counterparty", "Buyer / Seller", 118, "LEFT"),
    column("qty", "Qty", 48), column("unit", "Unit", 80, nil, mfield("unit")),
    column("total", "Total", 88, nil, renderLedgerTotal), column("profit", "Profit", 82, nil, mfield("profit", true)),
}
local PUSH_COLS = {
    column("char", "Character", 136, "LEFT", function(r) return r.charShort or r.char end),
    column("startedAt", "Standing Push", 168, "LEFT", function(r)
        return tostring(r.fromStanding or "-") .. " -> " .. tostring(r.toStanding or "-") .. (r.active and " (active)" or "")
    end), column("writsDone", "Writs", 58), column("grossCost", "Gross Cost", 104, nil, mfield("grossCost")),
    column("refunds", "Quest + Pouch", 116, nil, function(r) return money((r.questCash or 0) + (r.pouchRefund or 0)) end),
    column("pendingRefund", "Pending Pouch", 104, nil, mfield("pendingRefund")), column("netCost", "Net Cost", 104, nil, mfield("netCost")),
    column("repGained", "Rep Gained", 84), column("costPerRep", "Net / Rep", 96, nil, mfield("costPerRep")),
}
local RECIPE_COLS = {
    column("recipeName", "Recipe", 214, "LEFT", function(r) return item(r, "recipeName") end),
    column("source", "Source", 96, "LEFT"), column("investCost", "Invest Cost", 108, nil, function(r)
        if (r.favorSpent or 0)>0 then return tostring(r.favorSpent).." Favor"..((r.copperSpent or 0)>0 and (" + "..money(r.copperSpent)) or "") end
        return money(r.investCost)
    end),
    column("outputName", "Crafted Output", 190, "LEFT"), column("unitsSold", "Sold", 60),
    column("realizedProfit", "Realized Profit", 112, nil, mfield("realizedProfit", true)),
    column("netPayback", "Net Payback", 112, nil, mfield("netPayback", true)),
    column("paidBackPct", "Status", 92, nil, function(r)
        local pal = getPalette()
        return r.isPaidBack and ("|cff" .. pal.hexGreen .. "Paid Back|r") or percent(r.paidBackPct)
    end),
}
local WRIT_COLS = {
    column("tierOrder", "Tier", 160, "LEFT", function(r) return r.tier end), column("writs", "Turn-Ins", 90),
    column("rep", "Total Rep / Favor", 140), column("grossCost", "Gross Spend", 140, nil, mfield("grossCost")),
    column("refunds", "Cash + Pouch Refunds", 160, nil, mfield("refunds")), column("netCost", "Net Cost", 140, nil, mfield("netCost")),
    column("perRep", "Avg Cost / Unit", 140, nil, mfield("perRep")),
}
UI.Columns = { an_overview = TOP_COLS, an_ledger = LEDGER_COLS, an_items = ITEM_COLS,
    an_portfolio = PORTFOLIO_COLS, an_wealth = WEALTH_COLS, an_pushes = PUSH_COLS, an_recipes = RECIPE_COLS, an_writs = WRIT_COLS }

function UI.Filters()
    local d, a = db(), app()
    local ledgerRoute = a and a.activeTab == "an_ledger"
    local itemsRoute = a and a.activeTab == "an_items"
    local routeProf = d.anProf
    local routeRarities = d.anRarities
    local routeRarity = d.anRarity
    local routeMinRarity = d.anMinRarity
    local routeGroup = d.anGroup
    if ledgerRoute then
        routeProf = nil
        routeRarities, routeRarity = nil, d.anLedgerMinRarity
        routeMinRarity, routeGroup = d.anLedgerMinRarity, d.anLedgerGroup
    end
    local preset = d.anLedgerPreset or "all"
    local types
    if preset == "sales" then types = { AH_SELL=true, VENDOR_SELL=true, COD_SELL=true, TRADE_SELL=true }
    elseif preset == "purchases" then types = { AH_BUY=true, VENDOR_BUY=true, VENDOR_BUYBACK=true, COD_BUY=true, TRADE_BUY=true }
    elseif preset == "craft" then types = { CRAFT=true, DESTROY=true, DISENCHANT_BROKEN=true, DISENCHANT_RECEIVE=true }
    elseif preset == "trade" then types = { TRADE_BUY=true, TRADE_SELL=true }
    elseif preset == "loot" then types = { LOOT=true, GATHER=true, MONEY_LOOT=true }
    elseif preset == "expired" then types = { AH_EXPIRE=true }
    elseif preset == "cancelled" then types = { AH_CANCEL=true }
    elseif preset == "expiredCancelled" then types = { AH_EXPIRE=true, AH_CANCEL=true }
    elseif preset == "other" then types = { OTHER_INCOME=true, OTHER_EXPENSE=true, REPAIR=true, POSTAGE=true,
        MONEY_TRANSFER=true, QUEST_MONEY=true, POUCH_MONEY=true, MONEY_LOOT=true,
        TRAINER_FEE=true, GUILD_DEPOSIT=true, GUILD_WITHDRAW=true, AH_OUTBID=true } end
    return { char = d.anChar or "all", period = d.anPeriod or "30d", type = d.anType or "all",
        zone = d.anZone or "all", search = a and a.ui.searchBox and a.ui.searchBox:GetText() or "",
        knownCostOnly = d.anKnownCostOnly == true, chars = d.anChars and next(d.anChars) and d.anChars or nil, faction = itemsRoute and d.anFaction or "all",
        source = itemsRoute and d.anSource or nil, groupBy = d.anGroupBy or "base", prof = routeProf, rarities = routeRarities,
        rarity = routeRarity, minRarity = routeMinRarity, group = routeGroup, page = d.anLedgerOffset or 0,
        limit = d.anLedgerLimit or 500, coalesce = d.anCoalesce == true, types=types, ledgerPreset=preset }
end

local function refresh()
    if app() and app().refresh then app().refresh() end
end

local function distinct(list, seen, value, display)
    if value and value ~= "" and not seen[value] then
        seen[value] = true; list[#list + 1] = { key = value, label = display or value }
    end
end

local function shortChar(c)
    return (ns.Model and ns.Model.CharShort and ns.Model.CharShort(c)) or c
end

local function charOptions()
    local list, seen = { { key = "all", label = "Char: All" } }, { all = true }
    local l = ledger(); local stats = l.stats or {}
    for char, info in pairs(db().chars or {}) do
        distinct(list, seen, char, "Char: " .. (type(info) == "table" and info.name or shortChar(char)))
    end
    for char in pairs(stats.chars or {}) do distinct(list, seen, char, "Char: " .. shortChar(char)) end
    for char in pairs(stats.firstLive or {}) do distinct(list, seen, char, "Char: " .. shortChar(char)) end
    for char in pairs(l.snaps or {}) do
        if type(char) == "string" and not char:match("^%d%d%d%d%-%d%d%-%d%d$") then distinct(list, seen, char, "Char: " .. shortChar(char)) end
    end
    table.sort(list, function(a, b) if a.key == "all" then return true elseif b.key == "all" then return false end return a.label < b.label end)
    return list
end

local function zoneOptions()
    local list, seen = { { key = "all", label = "All Zones" } }, { all = true }
    local l = ledger(); local stats = l.stats or {}
    for z in pairs(stats.zones or {}) do distinct(list, seen, z) end
    table.sort(list, function(a, b) if a.key == "all" then return true elseif b.key == "all" then return false end return a.label < b.label end)
    return list
end

local function selectedLabel(options, key, fallback)
    for _, option in ipairs(options) do if option.key == key then return option.label end end
    return fallback or key
end

function UI.ResetFilters()
    local d, a = db(), app()
    local tab = a and a.activeTab
    d.anChar, d.anPeriod, d.anChars = "all", "30d", nil
    if tab ~= "an_ledger" then d.anProf = nil end
    if a then
        a.resetSearchBox(a.ui.searchBox)
    end

    if tab == "an_overview" then
        d.anShowActivity, d.anKnownCostOnly = false, false
        d.anWealthSeries = { total = true, gold = true, items = true, listed = true }
        if UI.seriesMenu then UI.seriesMenu:Hide() end
    elseif tab == "an_ledger" then
        d.anType, d.anZone = "all", "all"
        d.anLedgerOffset, d.anLedgerLimit, d.anCoalesce, d.anLedgerPreset = 0, 500, false, "all"
        d.anLedgerGroup, d.anLedgerMinRarity = nil, nil
        UI._ledgerScope = nil
        local view = UI.views.an_ledger
        if view then
            if view.preset then view.preset:SetText("Preset: All") end
            if view.prof then view.prof:SetText("Prof") end
            if view.rarity then view.rarity:SetText("Rarity") end
        end
    elseif tab == "an_items" then
        for _, key in ipairs({ "anSource", "anRarities", "anRarity", "anMinRarity", "anGroup" }) do d[key] = nil end
        d.anFaction, d.anGroupBy, d.anKnownCostOnly, d.anItemMode = "all", "base", false, "profit"
        if UI.detailKey then UI.detailKey = nil end
        local view = UI.views.an_items
        if view and view.detail then view.detail:Hide() end
        if a then
            a.sortState.an_items = { col = "profit", asc = false }
            d.sort = d.sort or {}
            d.sort.an_items = { col = "profit", asc = false }
        end
        if view then
            if view.group then view.group:SetText("Group: base") end
            if view.source then view.source:SetText("Source: All") end
            if view.faction then view.faction:SetText("Faction: All") end
        end
    elseif tab == "an_portfolio" then
        d.anPortfolioView, d.anInvPriceSource, d.anInvIncludeGuild = "breakdown", "market", false
        local view = UI.views.an_portfolio
        if view then
            if view.inventorySearch then a.resetSearchBox(view.inventorySearch) end
            if view.inventoryPrice then view.inventoryPrice:SetText("Price: market") end
            if view.inventoryGuild then view.inventoryGuild:SetText("Guild: Off") end
        end
    end

    if UI.choiceMenu then UI.choiceMenu:Hide() end
    if UI.charBtn then UI.GetSidebarControls(a and a.activeTab) end
    return refresh()
end

local function createControls()
    local hostUI = app().ui
    local function drop(name, options, field, initial, tip, onSet)
        local button = hostUI.makeSidebarDrop(options, function() return db()[field] or initial end,
            function(k) db()[field] = k; if onSet then onSet(k) end end, function() db()[field] = initial end, tip, "Right-click to reset.")
        UI[name] = button; UI.controls[#UI.controls + 1] = button
    end
    drop("charBtn", charOptions, "anChar", "all", "Character")
    drop("periodBtn", PERIODS, "anPeriod", "30d", "Period")
    drop("typeBtn", TYPES, "anType", "all", "Transaction Type", function(k)
        if k ~= "all" then db().anLedgerPreset = "all"; db().anLedgerOffset = 0 end
    end)
    drop("zoneBtn", zoneOptions, "anZone", "all", "Zone")
    drop("portfolioViewBtn", PORTFOLIO_VIEWS, "anPortfolioView", "breakdown", "Portfolio View")
    UI.itemModeBtn = hostUI.makeSidebarDrop(MODES, function() return db().anItemMode or "profit" end, function(k)
        db().anItemMode = k
        for _, mode in ipairs(MODES) do
            if mode.key == k then
                app().sortState.an_items = { col = mode.col, asc = mode.asc == true }
                db().sort = db().sort or {}; db().sort.an_items = { col = mode.col, asc = mode.asc == true }
            end
        end
    end, function() db().anItemMode = "profit"; app().sortState.an_items = { col = "profit", asc = false } end,
        "Item View", "Choose a ranking or show slowing sales and repeated relists.")
    UI.knownCostCheck = hostUI.makeSidebarCheck("Known Cost Only", function(self)
        db().anKnownCostOnly = self:GetChecked() == true; refresh()
    end, "Known Cost Only", "Exclude estimated or missing cost basis from performance totals.")
    UI.controls[#UI.controls + 1] = UI.itemModeBtn
    UI.controls[#UI.controls + 1] = UI.knownCostCheck
    UI.resetFiltersBtn = hostUI.makeSidebarBtn("Reset Filters", false, UI.ResetFilters)
    UI.controls[#UI.controls + 1] = UI.resetFiltersBtn
end

function UI.GetSidebarControls(tab)
    if not UI.charBtn then return {} end
    UI.charBtn:SetText(db().anChar and db().anChar ~= "all" and ("Char: " .. shortChar(db().anChar)) or "Char: All")
    UI.periodBtn:SetText(selectedLabel(PERIODS, db().anPeriod or "30d"))
    UI.typeBtn:SetText(selectedLabel(TYPES, db().anType or "all"))
    UI.zoneBtn:SetText(db().anZone and db().anZone ~= "all" and db().anZone or "All Zones")
    UI.itemModeBtn:SetText(selectedLabel(MODES, db().anItemMode or "profit"))
    if UI.portfolioViewBtn then UI.portfolioViewBtn:SetText(selectedLabel(PORTFOLIO_VIEWS, db().anPortfolioView or "breakdown")) end
    UI.knownCostCheck:SetChecked(db().anKnownCostOnly == true)
    local controls = { UI.charBtn, UI.periodBtn }
    if tab == "an_ledger" then
        controls[#controls + 1] = UI.typeBtn; controls[#controls + 1] = UI.zoneBtn
    elseif tab == "an_items" then
        controls[#controls + 1] = UI.itemModeBtn; controls[#controls + 1] = UI.knownCostCheck
    elseif tab == "an_portfolio" and UI.portfolioViewBtn then
        controls[#controls + 1] = UI.portfolioViewBtn
    elseif tab == "an_overview" then controls[#controls + 1] = UI.knownCostCheck end
    controls[#controls + 1] = UI.resetFiltersBtn
    return controls
end

function UI.SendToShopping(row)
    local h = H(); local a = h and h.app
    if not row or not a or not a.setActiveShoppingList then return false end
    local qty = math.max(1, tonumber(row.bought) or 1)
    if a.addUnifiedShoppingItem then
        a.addUnifiedShoppingItem({
            key = "acct:" .. tostring(row.itemID or row.id or row.name or 1),
            itemID = row.itemID or row.id,
            name = row.name or row.itemName,
            qty = qty,
            sourceLabel = "Accounting Restock",
        }, true)
    end
    a.setActiveShoppingList({ { itemID = row.itemID or row.id, name = row.name or row.itemName,
        qty = qty, buyQty = qty, lineCost = row.avgBuy or 0, role = "Accounting Restock", isVendor = false } },
        "Accounting restock suggestion", "MM Accounting")
    if a.toggleShoppingWindow then a.toggleShoppingWindow(true) end
    return true
end

local function tooltip(owner, row)
    if not GameTooltip or not row then return end
    local title = row.title or row.itemName or row.name or row.recipeName or row.label
    if not title or title == "" or title == "-" then return end
    local pal = getPalette()
    local extra = row.extra or {}
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, pal.accentBlue[1], pal.accentBlue[2], pal.accentBlue[3])
    if row.isCategory then
        GameTooltip:AddDoubleLine("Category Total", money(row.total or 0))
        GameTooltip:AddDoubleLine("Entries", num(row.itemCount or 0))
        if row.sharePct ~= nil then GameTooltip:AddDoubleLine("Portfolio Share", percent(row.sharePct)) end
        GameTooltip:AddLine(row.expanded and "Click to collapse this category." or "Click to expand individual items.", 0.72, 0.86, 1)
        GameTooltip:Show()
        return
    end
    if row.catKey or row.isGoldRow or row.basis then
        if row.owner then GameTooltip:AddDoubleLine("Character", row.owner) end
        if row.basis then GameTooltip:AddDoubleLine("Valuation Basis", row.basis) end
        if row.qty ~= nil then GameTooltip:AddDoubleLine("Quantity", num(row.qty)) end
        if row.unit ~= nil then GameTooltip:AddDoubleLine("Unit Value", money(row.unit)) end
        GameTooltip:AddDoubleLine("Total Value", money(row.total or 0))
        if row.bound then GameTooltip:AddLine("Soulbound item: strictly valued at vendor sell price.", 1, 0.80, 0.33) end
        if row.itemID then GameTooltip:AddLine("Click to search on Auction House.", 0.72, 0.86, 1) end
        GameTooltip:Show()
        return
    end
    if row.time then GameTooltip:AddLine(when(row.time) .. "  " .. (row.typeLabel or row.type or "")) end
    if row.type == "DISENCHANT_BROKEN" then
        GameTooltip:AddDoubleLine("Transferred Cost", money(row.cogs or extra.deSrcCost or 0, false))
        GameTooltip:AddDoubleLine("Realized Profit", money(0, true))
    elseif row.type == "DISENCHANT_RECEIVE" then
        GameTooltip:AddDoubleLine("Carried-Over Cost", money(extra.allocBasis or 0, false))
        if extra.srcName and extra.srcName ~= "" then
            GameTooltip:AddDoubleLine("Disenchanted From", tostring(extra.srcName))
        end
        GameTooltip:AddDoubleLine("Realized Profit", money(0, true))
    else
        for _, field in ipairs({ { "total", "Cash Flow" }, { "gross", "Gross" }, { "fee", "AH Fee" },
            { "deposit", "Deposit" }, { "depositReturned", "Returned Deposit" }, { "cogs", "COGS" }, { "depLost", "Deposits Lost" }, { "profit", "Realized Profit" } }) do
            local v = row[field[1]]
            if v == nil then v = extra[field[1]] end
            if v ~= nil then GameTooltip:AddDoubleLine(field[2], money(v, true)) end
        end
    end
    if type(extra.deOrigin) == "table" and extra.deOrigin.srcName and extra.deOrigin.srcName ~= "" then
        GameTooltip:AddDoubleLine("Origin", "via DE: " .. tostring(extra.deOrigin.srcName))
        if type(extra.deOrigins) == "table" and #extra.deOrigins > 1 then
            for i, orig in ipairs(extra.deOrigins) do
                if i > 4 then break end
                GameTooltip:AddDoubleLine("  " .. tostring(orig.srcName or ("Item #" .. tostring(orig.srcItemID or 0))) .. " x" .. formatDeQty(orig.qty),
                    "Cost " .. money(orig.srcCost or 0, false))
            end
        end
    end
    if (tonumber(row.deBrokenQty) or 0) > 0 or (tonumber(row.deIndirectProfit) or 0) ~= 0 then
        GameTooltip:AddDoubleLine("Indirect via DE", money(row.deIndirectProfit or 0, true))
        GameTooltip:AddDoubleLine("DE'd / Sold Mats", num(row.deBrokenQty or 0) .. "x / " .. formatDeQty(row.deSoldMatsQty or 0) .. "x")
        if type(row.deSoldOutputs) == "table" then
            for i, out in ipairs(row.deSoldOutputs) do
                if i > 3 then break end
                GameTooltip:AddDoubleLine("  " .. tostring(out.name or ("Item #" .. tostring(out.itemID or 0))) .. " x" .. formatDeQty(out.qty),
                    money(out.profit or 0, true))
            end
        end
        GameTooltip:AddLine("Already counted on sold mat (not double-counted).", 0.70, 0.70, 0.70)
    end
    if row.reprices ~= nil then GameTooltip:AddDoubleLine("Repriced Units", num(row.reprices)) end
    if row.relists ~= nil then GameTooltip:AddDoubleLine("Relisted Units", num(row.relists)) end
    if row.est or extra.est then GameTooltip:AddLine("(est.) Estimated COGS", 1, 0.80, 0.33) end
    if row.unconfirmed or extra.unconfirmed then GameTooltip:AddLine("Unconfirmed money change", 1, 0.60, 0.33) end
    if row.tsm or extra.tsm or extra.source == "tsm" then GameTooltip:AddLine("TSM history import", 0.70, 0.70, 0.70) end
    if row.where then GameTooltip:AddLine(row.where) end
    GameTooltip:Show()
end

function UI.OpenItemRow(r, tabKey, button)
    if not r or not r.itemID then return false end
    if tabKey=="an_items" then UI.selectedItem=r end
    if button=="RightButton" and tabKey=="an_ledger" and IsShiftKeyDown and IsShiftKeyDown() then
        UI.pendingCorrection=r; UI.ShowCorrection(r); return true
    end
    if tabKey=="an_ledger" and _G.MerchantMasterAPI and _G.MerchantMasterAPI.SetTab then
        _G.MerchantMasterAPI.SetTab("an_items")
    end
    local extra=r.extra or {}
    local variant=r.variant or extra.variant or r.itemString or extra.itemString
    local level=r.itemLevel or extra.itemLevel or extra.level
    local detailKey=(variant or level) and {itemID=r.itemID,variant=variant,itemLevel=level,itemString=r.itemString or extra.itemString} or r.itemID
    UI.ShowItemDetail(detailKey)
    return true
end

local function hideInsetTemplates(inset)
    if not inset or inset._appleHidden then return end
    inset._appleHidden = true
    for _, r in ipairs(inset.GetRegions and { inset:GetRegions() } or {}) do
        if r.GetObjectType and r:GetObjectType() == "Texture" and r.SetAlpha then r:SetAlpha(0) end
    end
    for _, k in ipairs({ "NineSlice", "Bg", "TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner",
        "TopBorder", "BottomBorder", "LeftBorder", "RightBorder", "InsetBorderTop", "InsetBorderBottom",
        "InsetBorderLeft", "InsetBorderRight", "InsetBorderTopLeft", "InsetBorderTopRight",
        "InsetBorderBottomLeft", "InsetBorderBottomRight" }) do
        if type(inset[k]) == "table" and inset[k].SetAlpha then inset[k]:SetAlpha(0) end
    end
end

local function styleTableChrome(tbl, pal)
    if tbl.headerBar then
        if not tbl._transparentChrome then
            applySurface(tbl.headerBar, "glass_r8", pal.cardBg, false)
        end
        if not tbl.headerBar._appleLine then
            local line = tbl.headerBar:CreateTexture(nil, "BORDER")
            line:SetPoint("BOTTOMLEFT", 0, 0)
            line:SetPoint("BOTTOMRIGHT", 0, 0)
            line:SetHeight(1)
            tbl.headerBar._appleLine = line
        end
        tbl.headerBar._appleLine:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.65)
    end
    if tbl.inset then
        local inset = tbl.inset
        hideInsetTemplates(inset)
        if not tbl._transparentChrome then
            applySurface(inset, "glass_r10", pal.cardBg, false)
        end
    end
end

local function resolveOverviewIcon(data)
    if data.icon or data.itemIcon then return data.icon or data.itemIcon end
    local h = H()
    if h and h.ItemIcon and data.itemID then
        local ok, ic = pcall(h.ItemIcon, data.itemID)
        if ok and ic then return ic end
    end
    return assetPath("icon_flask")
end

local function styleRow(row, data, tableUI, pal)
    local isOverview = (tableUI and tableUI.tabKey == "an_overview")
    if not row._appleRowInit then
        row._appleRowInit = true
        local div = row:CreateTexture(nil, "BORDER")
        if isOverview then
            div:SetPoint("BOTTOMLEFT", 54, 0)
            div:SetPoint("BOTTOMRIGHT", 0, 0)
        else
            div:SetPoint("BOTTOMLEFT", 16, 0)
            div:SetPoint("BOTTOMRIGHT", -16, 0)
        end
        div:SetHeight(1)
        row.divider = div
        local pill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        pill:SetHeight(18)
        pill:SetTexture(assetPath("pill_fill"))
        pill:Hide()
        row.semanticPill = pill
        if isOverview then
            local gbg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
            gbg:SetSize(20, 20)
            gbg:SetPoint("LEFT", row, "LEFT", 14, 0)
            gbg:SetTexture(assetPath("circle_fill"))
            row.glyphBg = gbg
            local gic = row:CreateTexture(nil, "ARTWORK")
            gic:SetSize(15, 15)
            gic:SetPoint("CENTER", gbg, "CENTER", 0, 0)
            if gic.SetTexCoord then gic:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            row.glyphIcon = gic
        end
    end
    row.divider:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.4) * 0.55)
    if row.glyphBg and row.glyphIcon then
        local alpha = (pal.mode == "light") and 0.12 or 0.24
        row.glyphBg:SetVertexColor(0.463, 0.463, 0.502, alpha)
        row.glyphIcon:SetTexture(resolveOverviewIcon(data))
    end
    if row.stripe then
        if data.isCategory then
            row.stripe:SetColorTexture(pal.accentBlue[1], pal.accentBlue[2], pal.accentBlue[3], 0.10)
        else
            row.stripe:SetColorTexture(0, 0, 0, 0)
        end
    end
    for _, cell in ipairs(row.cells or {}) do
        setTextColor(cell, pal.text)
    end
    -- Keep ledger rows ultra-clean like TSM (colored semantic text without heavy pill background blobs)
    if row.semanticPill then
        row.semanticPill:Hide()
    end
end

local TOOLTIP_COLUMNS = {
    an_overview = "name",
    an_ledger = "itemName",
    an_items = "name",
    an_wealth = "label",
    an_inventory_matrix = "name",
    an_recipes = "recipeName",
}

local function createTable(parent, y, key, cols, bottom, auxiliary, transparentChrome)
    -- Layout mutates widths; keep the catalog's default widths for future rebuilds.
    local copies={}; for i,col in ipairs(cols) do local c={}; for k,v in pairs(col) do c[k]=v end; copies[i]=c end; cols=copies
    local tooltipColumn = TOOLTIP_COLUMNS[key]
    local isHistory = key == "an_item_history"
    app().sortState[key] = app().sortState[key] or { col = key == "an_wealth" and "total" or cols[1].key, asc = key ~= "an_wealth" }
    local tbl = app().ui.createSortableTable(parent, y, key, cols, function(row, data, tableUI)
        local pal = getPalette()
        if not row.cells then
            app().ui.applyRowHighlight(row)
            row.cells = {}
            for i, col in ipairs(cols) do
                local hasTooltip = col.key == tooltipColumn
                if hasTooltip or (isHistory and i == 1) then
                    local cell = CreateFrame("Button", nil, row)
                    cell:SetPoint("LEFT", tableUI.colX[i], 0)
                    cell:SetSize(col.width, app().ui.ROW_H or 22)
                    local fs = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    local textInset = (key == "an_overview" and i == 1) and 40 or 0
                    fs:SetPoint("LEFT", cell, "LEFT", textInset, 0)
                    fs:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
                    fs:SetHeight(app().ui.ROW_H or 22)
                    fs:SetJustifyH(col.align); fs:SetWordWrap(false)
                    applyFont(fs, 12, "regular")
                    cell.fs = fs
                    function cell:SetText(t) self.fs:SetText(t) end
                    function cell:GetText() return self.fs:GetText() end
                    function cell:SetTextColor(...) return self.fs:SetTextColor(...) end
                    function cell:SetFont(...) return self.fs:SetFont(...) end
                    function cell:GetFont() return self.fs:GetFont() end
                    function cell:SetJustifyH(...) return self.fs:SetJustifyH(...) end
                    function cell:SetWordWrap(...) return self.fs:SetWordWrap(...) end
                    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    if hasTooltip then
                        cell:SetScript("OnEnter", function(self)
                            tooltip(self, self:GetParent().data)
                        end)
                        cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                    end
                    cell:SetScript("OnClick", function(self, button)
                        local parent = self:GetParent()
                        local onClick = parent and parent:GetScript("OnClick")
                        if onClick then onClick(parent, button) end
                    end)
                    row.cells[i] = cell
                else
                    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    fs:SetPoint("LEFT", tableUI.colX[i], 0)
                    fs:SetSize(col.width, app().ui.ROW_H or 22)
                    fs:SetJustifyH(col.align); fs:SetWordWrap(false)
                    applyFont(fs, 12, "regular")
                    row.cells[i] = fs
                end
            end
            row:SetScript("OnClick", function(self, button)
                local r = self.data
                if r and r.isCategory and r.catKey then
                    UI.expandedWealth = UI.expandedWealth or { bags = true }
                    UI.expandedWealth[r.catKey] = not UI.expandedWealth[r.catKey]
                    refresh()
                elseif r and isHistory then
                    if button == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then UI.ShowCorrection(r) end
                elseif r and r.itemID and (tableUI.tabKey == "an_items" or tableUI.tabKey == "an_ledger") then
                    UI.OpenItemRow(r,tableUI.tabKey,button)
                elseif r and r.itemID then
                    _G.MerchantMasterAPI.SearchAH(r.itemName or r.name or r.recipeName or ("Item " .. r.itemID), 1, r.itemID)
                end
            end)
        end
        row.data = data
        for i, col in ipairs(cols) do
            if key == "an_overview" and i == 1 then
                local nm = data.name or data.itemName or (data.itemID and ("Item " .. data.itemID)) or "-"
                local qHex = itemQualityHex(data.itemID, data.quality)
                row.cells[i]:SetText((qHex and nm ~= "-") and ("|cff" .. qHex .. tostring(nm) .. "|r") or nm)
            else
                row.cells[i]:SetText(col.render and col.render(data) or data[col.key] or "-")
            end
        end
        styleRow(row, data, tableUI, pal)
    end, bottom, transparentChrome and { transparentInset = true } or nil)
    tbl._transparentChrome = transparentChrome == true

    local origUpdateHeaders = tbl.updateHeaders
    tbl.updateHeaders = function()
        if origUpdateHeaders then origUpdateHeaders() end
        local pal = getPalette()
        local st = key and app().sortState[key] or nil
        for i, col in ipairs(tbl.columns or cols) do
            local btn = tbl.headerBtns and tbl.headerBtns[i]
            if btn then
                local active = st and col.key == st.col
                if type(btn.sep) == "table" and btn.sep.Hide then
                    btn.sep:Hide()
                end
                if btn.bg then
                    btn.bg:SetColorTexture(0, 0, 0, 0)
                end
                if btn.fs then
                    applyFont(btn.fs, 11, active and "semibold" or "regular")
                    local chev = assetPath("icon_chevron_down")
                    local tint = (pal.mode == "light") and ":110:110:115" or ":174:174:178"
                    local arrow = active and (st.asc
                        and (" |T" .. chev .. ":9:9:1:0:16:16:0:16:16:0" .. tint .. "|t")
                        or (" |T" .. chev .. ":9:9:1:0:16:16:0:16:0:16" .. tint .. "|t")) or ""
                    local hex = active and pal.hexText or pal.hexMuted
                    btn.fs:SetText("|cff" .. hex .. col.label .. "|r" .. arrow)
                    setTextColor(btn.fs, active and pal.text or pal.textMuted)
                end
            end
        end
    end
    styleTableChrome(tbl, getPalette())
    tbl.updateHeaders()
    UI._styledTables[#UI._styledTables + 1] = tbl

    if auxiliary then UI.auxTables[key] = tbl else UI.tables[key] = tbl end
    cols = tbl.columns or cols; tbl.columns = cols
    tbl.proportional = true
    tbl.analyticsParent = parent; tbl.analyticsY = y; tbl.analyticsBottom = bottom or 0
    if key == "an_items" then
        for _, header in ipairs(tbl.headerBtns or {}) do
            if header.RegisterForClicks then header:RegisterForClicks("LeftButtonUp") end
            if header.HookScript then
                header:HookScript("OnMouseUp", function(_, button) if button == "RightButton" then UI.ShowColumnPicker() end end)
            else
                header:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then UI.ShowColumnPicker() end end)
            end
        end
    end
    return tbl
end

local function setRows(tbl, rows, predicate, limit)
    local sorted = {}
    for _, row in ipairs(rows or {}) do
        if not predicate or predicate(row) then
            local copy = {}; for k, v in pairs(row) do copy[k] = v end
            if copy.avgCost == nil and copy.sold and copy.sold > 0 then copy.avgCost = (copy.cogs or 0) / copy.sold end
            copy.refunds = copy.refunds or ((copy.questCash or 0) + (copy.pouchRefund or 0))
            copy._order = #sorted + 1; sorted[#sorted + 1] = copy
        end
    end
    local st = app().sortState[tbl.tabKey]
    if st then table.sort(sorted, function(a, b)
        local av, bv = a[st.col], b[st.col]
        if av == bv then return a._order < b._order end
        if av == nil then return false elseif bv == nil then return true end
        if type(av) ~= type(bv) then av, bv = tostring(av), tostring(bv) end
        if st.asc then return av < bv end
        return av > bv
    end) end
    if limit then for i = #sorted, limit + 1, -1 do sorted[i] = nil end end
    tbl.setRows(sorted); tbl.updateHeaders()
    return sorted
end

local function text(parent, title, y, size, muted)
    local pal = getPalette()
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", 12, y); fs:SetText(title)
    local sz = size or 13
    setFontSize(fs, sz, sz >= 14 and "semibold" or "regular")
    setTextColor(fs, muted and pal.textSecondary or pal.text)
    fs._isMutedLabel = muted == true
    UI._textLabels = UI._textLabels or {}
    UI._textLabels[#UI._textLabels + 1] = fs
    return fs
end

local function styleKpiCard(card, pal)
    applySurface(card, "glass_r10", pal.cardBg, false)
    setTextColor(card.title, pal.textSecondary)
    setTextColor(card.value, pal.text)
    if card.sub then setTextColor(card.sub, pal.textMuted or pal.textSecondary) end
    if card.badge and card.badge.SetVariant and card._badgeVariant then
        card.badge.SetVariant(card._badgeVariant, card._badgeText)
    end
end

local function kpis(parent, specs, height, valueSize)
    local pal = getPalette()
    local h = H()
    local theme = h and h.Theme
    local cards, gap = {}, #specs > 4 and 10 or 12
    local cardH = height or 72
    local padX = #specs > 4 and 10 or 14
    local width = (1068 - (#specs - 1) * gap) / #specs
    for i, spec in ipairs(specs) do
        local title = type(spec) == "table" and spec.title or spec
        local card = CreateFrame("Button", nil, parent)
        card:SetSize(width, cardH)
        card:SetPoint("TOPLEFT", (i - 1) * (width + gap), -4)
        card._padX = padX
        card._valueSize = valueSize or (#specs > 4 and 12 or 18)
        applySurface(card, "glass_r10", pal.cardBg, false)

        card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.title:SetPoint("TOPLEFT", padX, -10)
        card.title:SetWidth(math.max(1, width - padX * 2))
        card.title:SetJustifyH("LEFT")
        card.title:SetWordWrap(false)
        setFontSize(card.title, #specs > 4 and 11 or 12, "regular")
        card.title:SetText(tostring(title))

        card.value = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        card.value:SetPoint("TOPLEFT", padX, -28)
        card.value:SetWidth(math.max(1, width - padX * 2))
        if #specs > 4 then card.value:SetHeight(40) end
        card.value:SetJustifyH("LEFT")
        card.value:SetWordWrap(#specs > 4)
        setFontSize(card.value, card._valueSize, "semibold")
        card.value:SetText("-")

        card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.sub:SetPoint("BOTTOMLEFT", padX, 10)
        card.sub:SetWidth(math.max(1, width - padX * 2))
        card.sub:SetJustifyH("LEFT")
        card.sub:SetWordWrap(false)
        setFontSize(card.sub, 11, "regular")
        card.sub:SetText("")

        if theme and theme.CreateBadgePill then
            card.badge = theme.CreateBadgePill(card, "", "neutral")
            card.badge.frame:ClearAllPoints()
            card.badge.frame:SetPoint("TOPRIGHT", -12, -10)
            card.badge.frame:Hide()
        end

        styleKpiCard(card, pal)
        card:SetScript("OnEnter", function(self)
            local p = getPalette()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(title, p.accentBlue[1], p.accentBlue[2], p.accentBlue[3])
            if self.tip then GameTooltip:AddLine(self.tip, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        card:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cards[i] = card
    end
    return cards
end

local function line(parent, width, height, title, y)
    local c = ns.Chart.CreateLineChart(parent, width, height, { title = title })
    c:SetPoint("TOPLEFT", 0, y); return c
end

local function styleActionButton(btn, pal)
    local h = H()
    local theme = h and h.Theme
    if not btn._appleBtnInit then
        btn._appleBtnInit = true
        for _, k in ipairs({ "Left", "Middle", "Right" }) do
            if type(btn[k]) == "table" and btn[k].SetAlpha then btn[k]:SetAlpha(0) end
        end
        for _, fn in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
            local t = btn[fn] and btn[fn](btn)
            if t and t.SetAlpha then t:SetAlpha(0) end
        end
        if theme and theme.RoundRect and theme.ASSETS and theme.ASSETS.pill_fill then
            btn._appleBgPill = theme.RoundRect(btn, btn, "BACKGROUND", 0, 12, 0, pal.pillTrack[1], pal.pillTrack[2], pal.pillTrack[3], pal.pillTrack[4] or 0.12, theme.ASSETS.pill_fill)
        else
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture(assetPath("pill_fill"))
            btn._appleBg = bg
        end
        if not (theme and theme.RoundRect) then
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetTexture(assetPath("pill_fill"))
            btn._appleHl = hl
        end
        local fs = (btn.GetFontString and btn:GetFontString()) or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if btn.SetFontString then btn:SetFontString(fs) end
        fs:ClearAllPoints(); fs:SetPoint("CENTER", 0, 0)
        setFontSize(fs, 11, "semibold")
        fs:SetWordWrap(false)
        btn._appleFs = fs
        if btn.SetEnabled then
            local origEnable = btn.SetEnabled
            btn.SetEnabled = function(self, on)
                origEnable(self, on)
                local p = getPalette()
                setTextColor(self._appleFs, on and p.text or p.textMuted)
                if self._appleBg and self._appleBg.SetAlpha then self._appleBg:SetAlpha(on and 1 or 0.45) end
            end
        end
    end
    if btn._appleBgPill and btn._appleBgPill.SetColor then
        btn._appleBgPill:SetColor(pal.pillTrack[1], pal.pillTrack[2], pal.pillTrack[3], pal.pillTrack[4] or 0.12)
    elseif btn._appleBg then
        btn._appleBg:SetVertexColor(pal.pillTrack[1], pal.pillTrack[2], pal.pillTrack[3], pal.pillTrack[4] or 0.08)
    end
    if btn._appleHl then
        btn._appleHl:SetVertexColor(pal.cardHover[1], pal.cardHover[2], pal.cardHover[3], pal.cardHover[4] or 0.08)
    end
    local enabled = not btn.IsEnabled or btn:IsEnabled()
    setTextColor(btn._appleFs, enabled and pal.text or pal.textMuted)
end

local function action(parent, label, x, y, callback, width)
    parent._actionPool = parent._actionPool or {}
    parent._actionUsed = (parent._actionUsed or 0) + 1
    local index = parent._actionUsed
    local b = parent._actionPool[index]
    if not b then
        b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        parent._actionPool[index] = b
        UI._actionButtons[#UI._actionButtons + 1] = b
    end
    b:ClearAllPoints(); b:SetSize(width or math.max(58, #label * 6 + 16), 24); b:SetPoint("TOPLEFT", x, y)
    b:SetText(label); b:SetScript("OnClick", callback)
    styleActionButton(b, getPalette())
    b:Show()
    return b
end

local function editModal(title, value)
    local pal = getPalette()
    local box = UI.modal
    if not box then box = CreateFrame("Frame", nil, UI.content, "BackdropTemplate"); UI.modal = box end
    box._actionUsed = 0
    for _, b in ipairs(box._actionPool or {}) do b:Hide() end
    box:SetFrameStrata("DIALOG"); box:SetSize(600, 236); box:ClearAllPoints(); box:SetPoint("CENTER")
    applySurface(box, "glass_r16", pal.cardBg, pal.borderStrong)
    if not box.title then box.title = text(box, "", -14, 14) end
    box.title:SetText(title)
    setTextColor(box.title, pal.text)
    local edit = box.edit
    if not edit then
        edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
        box.edit = edit
        if H() and H().Theme and H().Theme.StyleEditBox then H().Theme.StyleEditBox(edit) end
    end
    edit:SetAutoFocus(false); if edit.SetMultiLine then edit:SetMultiLine(true) end
    edit:ClearAllPoints(); edit:SetSize(560, 126); edit:SetPoint("TOPLEFT", 18, -42)
    edit:SetText(value or ""); if edit.HighlightText then edit:HighlightText() end
    action(box, "Close", 512, -12, function() box:Hide() end, 72)
    box:Show()
    return box, edit
end

local function copyCsv(kind)
    local filters = UI.Filters()
    local rows, cols, body
    if kind == "ledger" then
        cols = LEDGER_COLS
        -- QueryLedger is the canonical filtered source: Store.Export does not
        -- include every synthetic row or all UI filters (notably zone).
        local result = ns.Model.QueryLedger(filters, 0, math.huge)
        rows = result.rows or {}
    else
        cols = UI.tables.an_items and UI.tables.an_items.columns or ITEM_COLS
        local mode = db().anItemMode or "profit"
        local result = ns.Model.Compute("items", filters)
        rows = {}
        for _, row in ipairs(result.rows or {}) do
            if (mode ~= "slowing" or row.isSlowing) and (mode ~= "relists" or (row.expired or 0) + (row.cancelled or 0) > 0)
                and (mode ~= "sales" or (row.sold or 0) > 0) and (mode ~= "purchases" or (row.bought or 0) > 0) then rows[#rows + 1] = row end
        end
    end
    if body then
        local box, edit = editModal("Copy CSV", body)
        if edit.HighlightText then edit:HighlightText() end
        if edit.SetFocus then edit:SetFocus() end
        UI.lastModalEdit = edit
        return box
    end
    local lines = {}
    for i, col in ipairs(cols) do lines[i] = '"' .. tostring(col.label):gsub('"', '""') .. '"' end
    local out = { table.concat(lines, ",") }
    for _, row in ipairs(rows) do
        local cells = {}
        for i, col in ipairs(cols) do
            local val = row[col.key]
            if col.key == "counterparty" then val = row.counterparty or (row.extra and (row.extra.buyer or row.extra.seller or row.extra.counterparty)) end
            cells[i] = '"' .. tostring(val or ""):gsub('"', '""') .. '"'
        end
        out[#out + 1] = table.concat(cells, ",")
    end
    local box, edit = editModal("Copy CSV", table.concat(out, "\n"))
    if edit.HighlightText then edit:HighlightText() end
    if edit.SetFocus then edit:SetFocus() end
    UI.lastModalEdit = edit
    return box
end

local QUICK_PERIODS = {
    { key = "today", label = "1D" },
    { key = "7d", label = "1W" },
    { key = "30d", label = "1M" },
    { key = "90d", label = "3M" },
    { key = "all", label = "All" },
}

local LEDGER_PRESETS = {
    { key = "all", label = "All" },
    { key = "sales", label = "Sales" },
    { key = "purchases", label = "Purchases" },
    { key = "craft", label = "Craft" },
    { key = "trade", label = "Trade" },
    { key = "loot", label = "Loot" },
    { key = "other", label = "Other" },
    { key = "expired", label = "Expired" },
    { key = "cancelled", label = "Cancelled" },
}

local LEDGER_PRESET_NAMES = {
    all = "All",
    sales = "Sales",
    purchases = "Purchases",
    craft = "Craft",
    trade = "Trade",
    loot = "Loot & Gather",
    other = "Other Income / Expense",
    expired = "Expired",
    cancelled = "Cancelled",
    expiredCancelled = "Expired / Cancelled",
}

local function stylePillToggle(btn, active, pal)
    styleActionButton(btn, pal)
    local fill = active and pal.accentOrange or pal.pillTrack
    if btn._appleBgPill and btn._appleBgPill.SetColor then
        btn._appleBgPill:SetColor(fill[1], fill[2], fill[3], active and 0.92 or (fill[4] or 0.10))
    elseif btn._appleBg then
        btn._appleBg:SetVertexColor(fill[1], fill[2], fill[3], active and 0.92 or (fill[4] or 0.08))
    end
    if btn._appleFs then
        if active then
            btn._appleFs:SetTextColor(0.08, 0.08, 0.09, 1)
        else
            setTextColor(btn._appleFs, pal.textSecondary)
        end
    end
end

local function createCenteredFooterBar(parent)
    local pal = getPalette()
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(26)
    bar:SetPoint("BOTTOMLEFT", 0, 2)
    bar:SetPoint("BOTTOMRIGHT", 0, 2)
    applySurface(bar, "glass_r8", pal.cardAltBg or pal.cardBg, pal.border)
    local fs = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", bar, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    applyFont(fs, 12, "semibold")
    setTextColor(fs, pal.text)
    bar.text = fs
    function bar:ApplyTheme(p)
        p = p or getPalette()
        applySurface(self, "glass_r8", p.cardAltBg or p.cardBg, p.border)
        setTextColor(self.text, p.text)
    end
    return bar
end

local function createTsmOverviewSummary(parent)
    local pal = getPalette()
    local panel = CreateFrame("Frame", nil, parent)
    panel._stats = {}
    panel._rows = {}
    panel._headers = {}

    local statSpecs = {
        { key = "high52w", label = "52W HIGH", col = 1, row = 1 },
        { key = "low52w", label = "52W LOW", col = 1, row = 2 },
        { key = "avgDailySalesQty", label = "AVG DAILY SALES", col = 2, row = 1 },
        { key = "dailyChange", label = "DAILY CHANGE", col = 2, row = 2 },
        { key = "topSale", label = "TOP SALE", col = 3, row = 1 },
        { key = "topBuy", label = "TOP PURCHASE", col = 3, row = 2 },
    }
    for _, spec in ipairs(statSpecs) do
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        applyFont(lbl, 10, "semibold")
        setTextColor(lbl, pal.textMuted)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(spec.label)

        local val = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        applyFont(val, 11, "semibold")
        setTextColor(val, pal.accentOrange)
        val:SetJustifyH("RIGHT")
        val:SetWordWrap(false)
        val:SetText("-")

        panel._stats[spec.key] = { spec = spec, label = lbl, value = val }
    end

    local sep = panel:CreateTexture(nil, "BORDER")
    sep:SetHeight(1)
    sep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.60)
    panel._sep = sep

    local sections = {
        { id = "sales", heading = "SALES", totalLabel = "Total Gold Earned:", avgLabel = "Average Earned per Day:", hasTop = true },
        { id = "expenses", heading = "EXPENSES", totalLabel = "Total Gold Spent:", avgLabel = "Average Spent per Day:", hasTop = true },
        { id = "profit", heading = "PROFIT", totalLabel = "Total Profit:", avgLabel = "Average Profit per Day:", hasTop = false },
    }
    for _, sec in ipairs(sections) do
        local hdr = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        applyFont(hdr, 10, "semibold")
        setTextColor(hdr, pal.textMuted)
        hdr:SetJustifyH("LEFT")
        hdr:SetText(sec.heading)
        panel._headers[sec.id] = hdr

        local function makeLine(lblText)
            local l = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            applyFont(l, 11, "regular")
            setTextColor(l, pal.textSecondary)
            l:SetJustifyH("LEFT")
            l:SetWordWrap(false)
            l:SetText(lblText)
            local v = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            applyFont(v, 11, "semibold")
            setTextColor(v, pal.text)
            v:SetJustifyH("RIGHT")
            v:SetWordWrap(false)
            v:SetText("-")
            return { label = l, value = v }
        end

        panel._rows[sec.id] = {
            total = makeLine(sec.totalLabel),
            avg = makeLine(sec.avgLabel),
            top = sec.hasTop and makeLine("Top Item:") or nil,
        }
    end

    function panel:Layout(w, h)
        w = math.max(260, tonumber(w) or 500)
        local pad = 16
        local innerW = w - pad * 2
        local colGap = 14
        local colW = (innerW - colGap * 2) / 3
        for _, entry in pairs(self._stats) do
            local col = entry.spec.col
            local row = entry.spec.row
            local x = pad + (col - 1) * (colW + colGap)
            local y = -12 - (row - 1) * 18
            entry.label:ClearAllPoints()
            entry.label:SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
            entry.label:SetWidth(colW * 0.52)
            entry.value:ClearAllPoints()
            entry.value:SetPoint("TOPRIGHT", self, "TOPLEFT", x + colW, y)
            entry.value:SetWidth(colW * 0.46)
        end

        self._sep:ClearAllPoints()
        self._sep:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -54)
        self._sep:SetPoint("TOPRIGHT", self, "TOPRIGHT", -pad, -54)

        local y = -64
        for _, sec in ipairs(sections) do
            local hdr = self._headers[sec.id]
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", self, "TOPLEFT", pad, y)
            y = y - 16
            local grp = self._rows[sec.id]
            for _, ln in ipairs({ grp.total, grp.avg, grp.top }) do
                if ln then
                    ln.label:ClearAllPoints()
                    ln.label:SetPoint("TOPLEFT", self, "TOPLEFT", pad, y)
                    ln.label:SetWidth(innerW * 0.48)
                    ln.value:ClearAllPoints()
                    ln.value:SetPoint("TOPRIGHT", self, "TOPRIGHT", -pad, y)
                    ln.value:SetWidth(innerW * 0.52)
                    y = y - 17
                end
            end
            y = y - 6
        end
    end

    function panel:ApplyTheme(p)
        p = p or getPalette()
        self._sep:SetColorTexture(p.separator[1], p.separator[2], p.separator[3], (p.separator[4] or 0.45) * 0.60)
        for _, entry in pairs(self._stats) do
            setTextColor(entry.label, p.textMuted)
            setTextColor(entry.value, p.accentOrange)
        end
        for _, hdr in pairs(self._headers) do setTextColor(hdr, p.textMuted) end
        for _, grp in pairs(self._rows) do
            for _, ln in ipairs({ grp.total, grp.avg, grp.top }) do
                if ln then
                    setTextColor(ln.label, p.textSecondary)
                    setTextColor(ln.value, p.text)
                end
            end
        end
    end

    function panel:Update(data, p)
        p = p or getPalette()
        local m = (data and data.kpis) or data or {}
        local sale, buy = (data and data.topSingleSale) or {}, (data and data.topSingleBuy) or {}
        local topSaleItem = data and data.topSaleItem
        local topBuyItem = data and data.topBuyItem

        self._stats.high52w.value:SetText(money(m.high52w or 0))
        self._stats.low52w.value:SetText(money(m.low52w or 0))
        local dailySalesQty = tonumber(m.avgDailySalesQty)
        self._stats.avgDailySalesQty.value:SetText(dailySalesQty ~= nil and string.format("%.1f", dailySalesQty) or "-")
        self._stats.dailyChange.value:SetText(money(m.dailyChange or 0, true))
        self._stats.topSale.value:SetText((sale.total or 0) > 0 and money(sale.total) or "-")
        self._stats.topBuy.value:SetText((buy.total or 0) > 0 and money(buy.total) or "-")

        local function trendTag(deltaPct, invert)
            if deltaPct == nil or deltaPct == 0 then return "" end
            local good = invert and (deltaPct < 0) or (deltaPct > 0)
            local hex = good and p.hexGreen or p.hexRed
            local arrow = deltaPct > 0 and "+" or ""
            return "|cff" .. hex .. "(" .. arrow .. string.format("%.0f%%", deltaPct) .. ")|r  "
        end

        self._rows.sales.total.value:SetText(trendTag(m.salesDeltaPct, false) .. money(m.sales or 0))
        self._rows.sales.avg.value:SetText(money(m.avgDailySales or 0))
        self._rows.sales.top.value:SetText(topSaleItem and formatItemDisplay(topSaleItem.itemID, topSaleItem.name, topSaleItem.icon, topSaleItem.quality) or "-")

        self._rows.expenses.total.value:SetText(trendTag(m.purchasesDeltaPct, true) .. money(m.purchases or 0))
        self._rows.expenses.avg.value:SetText(money(m.avgDailyPurchases or 0))
        self._rows.expenses.top.value:SetText(topBuyItem and formatItemDisplay(topBuyItem.itemID, topBuyItem.name, topBuyItem.icon, topBuyItem.quality) or "-")

        self._rows.profit.total.value:SetText(trendTag(m.profitDeltaPct, false) .. money(m.profit or 0, true))
        self._rows.profit.avg.value:SetText(money(m.avgDailyProfit or 0, true))
    end

    return panel
end

local function ensureView(tab)
    if UI.views[tab] then return UI.views[tab] end
    local pal = getPalette()
    local view = CreateFrame("Frame", nil, UI.content); view:SetAllPoints(UI.content)
    UI.views[tab] = view
    if tab == "an_overview" then
        view.kpis = kpis(view, { "Realized Profit", "Sales", "Purchases", "Deposits Lost", "Loot Value", "Wealth Change", "Unexplained Gold" }, 76, 11)
        view.kpis[5].tip = "Loot valued at today's price; this is not realized profit."
        view.kpis[7].tip = "Flights, quest rewards or other uncaptured cash changes land here. This is the cash change not explained by captured transactions."
        view.profit = ns.Chart.CreateBarChart(view, 528, 174, { title = "Daily Realized Profit" })
        view.profit:SetPoint("TOPLEFT", 0, -90)
        view.wealth = line(view, 528, 174, "Total Wealth", -90)
        view.wealth:ClearAllPoints(); view.wealth:SetPoint("TOPLEFT", 540, -90)

        -- TSM-style quick time-range buttons (1D, 1W, 1M, 3M, All) right in the Wealth chart header
        if view.wealth.summary then view.wealth.summary:Hide() end
        view.periodBtns = {}
        local rx = -14
        for i = #QUICK_PERIODS, 1, -1 do
            local spec = QUICK_PERIODS[i]
            local key = spec.key
            local b = action(view.wealth, spec.label, 0, -13, function()
                db().anPeriod = key
                refresh()
            end, 30)
            b:SetHeight(20)
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", view.wealth, "TOPRIGHT", rx, -13)
            rx = rx - 34
            b._periodKey = key
            view.periodBtns[i] = b
        end

        view.topCard = CreateFrame("Frame", nil, view)
        view.topCard:SetPoint("TOPLEFT", 0, -276)
        view.topCard:SetPoint("BOTTOMRIGHT", 0, 0)
        if view.GetFrameLevel and view.topCard.SetFrameLevel then
            view.topCard:SetFrameLevel(view:GetFrameLevel())
        end
        applySurface(view.topCard, "glass_r10", pal.cardBg, false)

        view.tsmSummary = createTsmOverviewSummary(view.topCard)
        view.tsmSummary:SetPoint("TOPLEFT", view.topCard, "TOPLEFT", 0, 0)
        view.tsmSummary:SetPoint("BOTTOMLEFT", view.topCard, "BOTTOMLEFT", 0, 0)
        view.tsmSummary:SetWidth(520)

        view.cardDivider = view.topCard:CreateTexture(nil, "BORDER")
        view.cardDivider:SetWidth(1)
        view.cardDivider:SetPoint("TOPLEFT", view.tsmSummary, "TOPRIGHT", 0, -12)
        view.cardDivider:SetPoint("BOTTOMLEFT", view.tsmSummary, "BOTTOMRIGHT", 0, 12)
        view.cardDivider:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.55)

        view.topTablePane = CreateFrame("Frame", nil, view.topCard)
        view.topTablePane:SetPoint("TOPLEFT", view.tsmSummary, "TOPRIGHT", 6, 0)
        view.topTablePane:SetPoint("BOTTOMRIGHT", view.topCard, "BOTTOMRIGHT", 0, 0)

        view.seriesButton = action(view.topTablePane, "Series", 420, -12, function() UI.ShowWealthSeriesMenu() end, 76)
        view.secHdr = text(view.topTablePane, "Top 5 Running Items", -15, 14)
        view.secHdr:SetPoint("TOPLEFT", 14, -15)
        view.table = createTable(view.topTablePane, -44, tab, TOP_COLS, 0, false, true)
        if view.topCard.GetFrameLevel then
            local lvl = view.topCard:GetFrameLevel() + 2
            if view.table.headerBar and view.table.headerBar.SetFrameLevel then view.table.headerBar:SetFrameLevel(lvl) end
            if view.table.inset and view.table.inset.SetFrameLevel then view.table.inset:SetFrameLevel(lvl) end
        end
    elseif tab == "an_ledger" then
        view.kpis = kpis(view, { "Total Revenue", "Realized Profit", "Expenses & Mats", "Net Margin / ROI" }, 78)
        view.kpis[1].tip = "Gross positive inflow across matched transactions in the active period."
        view.kpis[2].tip = "Net realized profit (or net cashflow where COGS is unallocated)."
        view.kpis[3].tip = "Total purchases, deposits, repairs and fees across matched transactions."
        view.kpis[4].tip = "Net return percentage relative to total expenses & materials."
        view.toolbar = CreateFrame("Frame", nil, view)
        view.toolbar:SetPoint("TOPLEFT", 0, -90); view.toolbar:SetPoint("TOPRIGHT", 0, -90); view.toolbar:SetHeight(58)
        applySurface(view.toolbar, "glass_r8", pal.cardBg, false)

        -- Row 1: TSM-style quick Ledger section pills (All | Sales | Purchases | Craft | Trade | Loot | Other | Expired | Cancelled)
        view.presetBtns = {}
        local px = 8
        for i, spec in ipairs(LEDGER_PRESETS) do
            local pKey = spec.key
            local bw = math.max(52, #spec.label * 7 + 18)
            local b = action(view.toolbar, spec.label, px, -4, function()
                db().anLedgerPreset = pKey
                db().anType = "all"
                db().anLedgerOffset = 0
                refresh()
            end, bw)
            b._presetKey = pKey
            view.presetBtns[i] = b
            px = px + bw + 6
        end
        view.pageLabel = text(view.toolbar, "Page 1", -9, 11, true)
        view.pageLabel:ClearAllPoints()
        view.pageLabel:SetPoint("TOPRIGHT", view.toolbar, "TOPRIGHT", -12, -9)
        view.pageLabel:SetJustifyH("RIGHT")

        view.table = createTable(view, -154, tab, LEDGER_COLS, 32)
        view.footerBar = createCenteredFooterBar(view)
        view.footer = view.footerBar.text
        -- Row 2: Pagination & Filter actions
        view.prev = action(view.toolbar, "Prev Page", 8, -31, function() db().anLedgerOffset = math.max(0, (db().anLedgerOffset or 0) - (db().anLedgerLimit or 500)); refresh() end, 72)
        view.next = action(view.toolbar, "Next Page", 84, -31, function() db().anLedgerOffset = (db().anLedgerOffset or 0) + (db().anLedgerLimit or 500); refresh() end, 74)
        view.group = action(view.toolbar, "5m Group", 162, -31, function() db().anCoalesce = not db().anCoalesce; refresh() end, 72)
        view.csv = action(view.toolbar, "Copy CSV", 238, -31, function() copyCsv("ledger") end, 70)
        view.settings = action(view.toolbar, "Settings", 312, -31, function() UI.ShowSettings() end, 68)
        view.prof = action(view.toolbar, "Prof", 384, -31, function() UI.ShowGroupPicker() end, 50)
        view.rarity = action(view.toolbar, "Rarity", 438, -31, function() UI.ShowRarityPicker() end, 56)
        view.chars = action(view.toolbar, "Characters", 498, -31, function() UI.ShowCharPicker() end, 82)
        view.preset = action(view.toolbar, "Preset: All", 584, -31, function()
            local modes={"all","sales","purchases","craft","trade","loot","other","expired","cancelled","expiredCancelled"}; local current=db().anLedgerPreset or "all"
            for i,key in ipairs(modes) do if key==current then db().anLedgerPreset=modes[i%#modes+1]; break end end
            db().anType="all"; db().anLedgerOffset=0; refresh()
        end, 130)
        view.preset:SetText("Preset: " .. (LEDGER_PRESET_NAMES[db().anLedgerPreset or "all"] or "All"))
    elseif tab == "an_items" then
        view.toolbar = CreateFrame("Frame", nil, view)
        view.toolbar:SetPoint("TOPLEFT", 0, -2); view.toolbar:SetPoint("TOPRIGHT", 0, -2); view.toolbar:SetHeight(58)
        applySurface(view.toolbar, "glass_r8", pal.cardBg, false)
        view.table = createTable(view, -66, tab, ITEM_COLS, 32)
        view.footerBar = createCenteredFooterBar(view)
        view.footer = view.footerBar.text
        view.emptyText = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        view.emptyText:SetPoint("CENTER", view, "CENTER", 0, -20)
        view.emptyText:SetWidth(520)
        view.emptyText:SetJustifyH("CENTER")
        view.emptyText:SetWordWrap(true)
        applyFont(view.emptyText, 12, "regular")
        setTextColor(view.emptyText, pal.textMuted)
        view.emptyText:Hide()
        view.preset = action(view.toolbar, "Resale / All", 6, -4, function() db().anItemMode = "profit"; refresh() end, 82)
        view.sales = action(view.toolbar, "Sales", 92, -4, function() db().anItemMode = "sales"; refresh() end, 54)
        view.purchases = action(view.toolbar, "Purchases", 150, -4, function() db().anItemMode = "purchases"; refresh() end, 72)
        view.expired = action(view.toolbar, "Expired / Cancelled", 226, -4, function() db().anItemMode = "relists"; refresh() end, 114)
        view.slow = action(view.toolbar, "Slowing", 344, -4, function() db().anItemMode = "slowing"; refresh() end, 64)
        view.group = action(view.toolbar, "Group: Base", 412, -4, function() local g=db().anGroupBy or "base"; db().anGroupBy=g=="base" and "level" or (g=="level" and "specific" or "base"); refresh() end, 90)
        view.csv = action(view.toolbar, "Copy CSV", 506, -4, function() copyCsv("items") end, 70)
        view.filters = action(view.toolbar, "Category / Prof", 580, -4, function() UI.ShowGroupPicker() end, 98)
        view.rarity = action(view.toolbar, "Rarity", 682, -4, function() UI.ShowRarityPicker() end, 56)
        view.columns = action(view.toolbar, "Columns", 742, -4, function() UI.ToggleItemColumns() end, 64)
        view.shop = action(view.toolbar, "Send Top", 810, -4, function()
            UI.SendToShopping(UI.lastItemRows and UI.lastItemRows[1])
        end, 72)
        view.shopSelected = action(view.toolbar, "Send Selected", 886, -4, function() UI.SendToShopping(UI.selectedItem) end, 94)
        view.source = action(view.toolbar, "Source: All", 6, -31, function() UI.ShowSourcePicker() end, 92)
        view.faction = action(view.toolbar, "Faction: All", 102, -31, function()
            local f=db().anFaction or "all"; db().anFaction=f=="all" and "Alliance" or (f=="Alliance" and "Horde" or "all"); refresh()
        end, 92)
        view.chars = action(view.toolbar, "Characters", 198, -31, function() UI.ShowCharPicker() end, 84)
        view.detail = CreateFrame("Frame", nil, view, "BackdropTemplate"); view.detail:SetPoint("TOPLEFT", 150, -42); view.detail:SetPoint("BOTTOMRIGHT", -20, 24)
        view.detail:SetFrameStrata("DIALOG"); applySurface(view.detail, "glass_r16", pal.cardBg, pal.borderStrong); view.detail:Hide()
        view.detail.title = text(view.detail, "Item Detail", -12, 14)
        view.detail.body = text(view.detail, "", -36, 12, true); view.detail.body:SetSize(900, 164); view.detail.body:SetJustifyH("LEFT")
        view.detail.body:SetWordWrap(true)
        action(view.detail, "Search AH", 12, -208, function() if UI.detailItem then _G.MerchantMasterAPI.SearchAH(UI.detailItem.name, 1, UI.detailItem.itemID) end end, 84)
        view.detail.deepAnalysisBtn = action(view.detail, "Deep Analysis >", 102, -208, function()
            if UI.detailItem and UI.detailItem.itemID and _G.MerchantMasterAPI and _G.MerchantMasterAPI.OpenDeepAnalysis then
                _G.MerchantMasterAPI.OpenDeepAnalysis(
                    { kind = "item", itemID = UI.detailItem.itemID, name = UI.detailItem.name, icon = UI.detailItem.icon },
                    { tab = "an_items", wasQuickLookOpen = false, analyticsDetailKey = UI.detailKey }
                )
            end
        end, 122)
        action(view.detail, "Close", 230, -208, function() view.detail:Hide() end, 64)
        view.detail.history = createTable(view.detail, -238, "an_item_history", DETAIL_TX_COLS, 8, true, true)
    elseif tab == "an_portfolio" then
        view.kpis = kpis(view, { "Total Portfolio Wealth", "Liquid Gold", "Inventory Value", "Listed AH Value" }, 64)
        view.kpis[3].tip = "Combined value of Bags, Bank, Mail, and Equipped Gear (soulbound and equipped items are strictly valued at vendor sell price)."
        view.wealth = line(view, 1056, 175, "Personal Portfolio & Wealth", -74)
        view.breakdownPane = CreateFrame("Frame", nil, view)
        view.breakdownPane:SetPoint("TOPLEFT", 0, 0); view.breakdownPane:SetPoint("BOTTOMRIGHT", 0, 0)
        view.charsPane = CreateFrame("Frame", nil, view)
        view.charsPane:SetPoint("TOPLEFT", 0, 0); view.charsPane:SetPoint("BOTTOMRIGHT", 0, 0)
        view.breakdownTable = createTable(view.breakdownPane, -256, "an_wealth", WEALTH_COLS, 12)
        view.table = createTable(view.charsPane, -256, tab, PORTFOLIO_COLS, 12)
        view.inventoryPane = CreateFrame("Frame", nil, view); view.inventoryPane:SetPoint("TOPLEFT", 0, 0); view.inventoryPane:SetPoint("BOTTOMRIGHT", 0, 0)
        view.inventoryTable = createTable(view.inventoryPane, -34, "an_inventory_matrix", INVENTORY_COLS, 32, true)
        view.inventoryFooterBar = createCenteredFooterBar(view.inventoryPane)
        view.inventorySearch = CreateFrame("EditBox", nil, view.inventoryPane, "InputBoxTemplate")
        view.inventorySearch:SetAutoFocus(false); view.inventorySearch:SetSize(188, 24); view.inventorySearch:SetPoint("TOPLEFT", 4, -3)
        if H() and H().Theme and H().Theme.StyleEditBox then H().Theme.StyleEditBox(view.inventorySearch) end
        view.inventorySearch:SetScript("OnTextChanged", function() refresh() end)
        view.inventoryPrice = action(view.inventoryPane, "Price: Market", 200, -3, function() local p=db().anInvPriceSource or "market"; db().anInvPriceSource=p=="market" and "vendor" or (p=="vendor" and "basis" or (p=="basis" and "avgSell" or "market")); refresh() end, 112)
        view.inventoryGuild = action(view.inventoryPane, "Include Guild Bank", 316, -3, function() db().anInvIncludeGuild=not db().anInvIncludeGuild; refresh() end, 134)
    elseif tab == "an_invest" then
        local top = CreateFrame("Frame", nil, view); top:SetPoint("TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", 0, 0); top:SetHeight(216)
        view.topPane = top
        view.pushHdr = text(top, "Reputation Push Tracker", -4, 13)
        view.pushes = createTable(top, -24, "an_pushes", PUSH_COLS)
        view.recipeHdr = text(view, "Recipe Investment & Payback Tracker", -224, 13)
        view.recipes = createTable(view, -244, "an_recipes", RECIPE_COLS, 12)
    elseif tab == "an_writs" then
        view.kpis = kpis(view, { "Actual Avg Writ Cost / Rep", "Actual Avg Favor Cost / Token", "Total Writs Logged", "Pending Coin Pouches" }, 68)
        view.trend = line(view, 1056, 172, "Writ Cost/Rep & Favor Cost/Token - 30 Days", -78)
        view.table = createTable(view, -258, tab, WRIT_COLS, 12)
    end
    return view
end

function UI.ShowItemDetail(itemKey)
    local view = UI.views.an_items or ensureView("an_items")
    local detail = ns.Model.GetItemDetail and ns.Model.GetItemDetail(itemKey, UI.Filters())
    if not detail then return end
    if type(itemKey)=="table" then
        UI.detailKey={itemID=itemKey.itemID,variant=itemKey.variant,itemLevel=itemKey.itemLevel,itemString=itemKey.itemString}
    else UI.detailKey=itemKey end
    UI.detailItem = detail
    view.detail.title:SetText(detail.name or ("Item " .. tostring(detail.itemID)))
    local function windowLine(name, w)
        w = w or {}
        return name .. ": Sold " .. num(w.sold) .. " @ " .. money(w.avgSell) .. " (" .. money(w.totalSales) ..
            ") | Bought " .. num(w.bought) .. " @ " .. money(w.avgBuy) .. " (" .. money(w.totalSpent) ..
            ") | Profit " .. money(w.profit, true) .. " / unit " .. money(w.avgProfit, true)
    end
    local lines = { windowLine("7 Days", detail.windows and detail.windows.d7),
        windowLine("30 Days", detail.windows and detail.windows.d30),
        windowLine("All Time", detail.windows and detail.windows.all),
        "Cur Basis " .. money(detail.curBasis or 0) .. " | Smart Avg Buy " .. money(detail.smartAvgBuy or 0),
        "Buy " .. money(detail.minBuy or 0) .. " - " .. money(detail.maxBuy or 0) ..
        " | Sell " .. money(detail.minSell or 0) .. " - " .. money(detail.maxSell or 0),
        "180d Sale Rate " .. percent(detail.saleRate) .. " | Expires " .. num(detail.expSinceSale) .. " | Cancels " .. num(detail.canSinceSale) }
    if (tonumber(detail.deBrokenQty) or 0) > 0 or (tonumber(detail.deIndirectProfit) or 0) ~= 0 then
        lines[#lines + 1] = "Indirect via DE: " .. money(detail.deIndirectProfit or 0, true)
            .. " (DE'd " .. num(detail.deBrokenQty or 0) .. "x -> Sold mats: " .. formatDeQty(detail.deSoldMatsQty or 0)
            .. "x; already counted on sold mat, not double-counted)"
        if type(detail.deSoldOutputs) == "table" and #detail.deSoldOutputs > 0 then
            local outs = {}
            for i, out in ipairs(detail.deSoldOutputs) do
                if i > 3 then break end
                outs[#outs + 1] = tostring(out.name or ("Item #" .. tostring(out.itemID or 0)))
                    .. " x" .. formatDeQty(out.qty) .. ": " .. money(out.profit or 0, true)
            end
            lines[#lines + 1] = "DE Sold Outputs: " .. table.concat(outs, ", ")
        end
    end
    local inv = detail.inventory or {}
    lines[#lines + 1] = "Cross-Alt Inventory: Bags " .. num(inv.bags) .. " | Bank " .. num(inv.bank) .. " | Mail " ..
        num(inv.mail) .. " | In-Transit " .. num(inv.inTransit) .. " | AH " .. num(inv.ah) .. " | Total " .. num(inv.total)
    for _, alt in ipairs(inv.byChar or {}) do
        lines[#lines + 1] = tostring(alt.shortName or alt.char) .. ": Bags " .. num(alt.bags) .. " | Bank " .. num(alt.bank) ..
            " | Mail " .. num(alt.mail) .. " | Transit " .. num(alt.inTransit) .. " | AH " .. num(alt.ah) .. (alt.stale and " (stale)" or "")
    end
    for _, old in ipairs(view.detail.txButtons or {}) do old:Hide() end
    view.detail.txButtons = view.detail.txButtons or {}
    view.detail.history.setRows(detail.transactions or {}); view.detail.history.updateHeaders()
    if detail.topBuyers and #detail.topBuyers > 0 then
        local names = {}; for i, r in ipairs(detail.topBuyers) do if i > 3 then break end; names[#names + 1] = tostring(r.name) .. " x" .. num(r.qty) end
        lines[#lines + 1] = "Top Buyers: " .. table.concat(names, ", ")
    end
    if detail.topSellers and #detail.topSellers > 0 then
        local names = {}; for i, r in ipairs(detail.topSellers) do if i > 3 then break end; names[#names + 1] = tostring(r.name) .. " x" .. num(r.qty) end
        lines[#lines + 1] = "Top Sellers: " .. table.concat(names, ", ")
    end
    view.detail.body:SetText(table.concat(lines, "\n")); view.detail:Show()
end

function UI.ShowCorrection(row)
    local label = "Delete transaction #" .. tostring(row.eid or (row.extra and row.extra.eid) or "?") .. " and rebuild basis/rollups?"
    local grouped = type(row.rawEventIDs)=="table" and #row.rawEventIDs>1
    local box = editModal(grouped and "Grouped transactions" or label,
        grouped and "Expand the 5-minute group in an ungrouped ledger view before correcting individual events."
            or "Review the transaction above, then confirm deletion.")
    UI.correctionConfirm = action(box, "Confirm", 300, -200, function()
        local eid = row.eid or (row.extra and row.extra.eid)
        if not grouped and eid and ns.Store.Correct then
            local result = ns.Store.Correct(eid, { action = "delete" })
            if result and result.ok ~= false then box:Hide(); refresh()
            else box.edit:SetText(tostring(result and result.err or "Correction failed")) end
        end
    end, 72)
    UI.correctionConfirm:SetEnabled(not grouped)
    UI.correctionCancel = action(box, "Cancel", 380, -200, function() box:Hide() end, 60)
end

function UI.ShowColumnPicker()
    if UI.choiceMenu then UI.choiceMenu:Hide() end
    local pal = getPalette()
    local opts = {}
    for _, col in ipairs(ITEM_COLS) do
        if col.key ~= "name" then opts[#opts + 1] = { col.label, col.key, col.width, col.render, true } end
    end
    local extras = {
        { "Cur Basis", "curBasis", 72, pricefield("curBasis") }, { "Avg Profit", "avgProfit", 72, pricefield("avgProfit") },
        { "Last Sold", "lastSoldTs", 90, function(r) return when(r.lastSoldTs) end },
        { "Market", "market", 76, mfield("market") }, { "Craft Cost", "craftCost", 76, mfield("craftCost") },
        { "Last Buy", "lastBuyTs", 90, function(r) return when(r.lastBuyTs) end },
    }
    local box = CreateFrame("Frame", nil, UI.views.an_items, "BackdropTemplate"); UI.choiceMenu = box
    box._actionUsed = 0
    for _, entry in ipairs(extras) do opts[#opts + 1] = entry end
    box:SetFrameStrata("DIALOG"); box:SetSize(226, 396); box:SetPoint("TOPRIGHT", UI.views.an_items, "TOPRIGHT", -20, -42)
    applySurface(box, "glass_r12", pal.cardBg, pal.borderStrong)
    text(box, "Item Columns", -10, 12)
    UI.columnChoices = {}
    for i, opt in ipairs(opts) do
        local choice = opt
        local active = choice[5] and (db().anItemHidden and not db().anItemHidden[choice[2]]) or (db().anItemOptional and db().anItemOptional[choice[2]])
        local b = action(box, (active and "[x] " or "[ ] ") .. choice[1], 10, -28 - (i - 1) * 24, function()
            if choice[5] then
                local hidden = db().anItemHidden or {}; db().anItemHidden = hidden; hidden[choice[2]] = not hidden[choice[2]]
            else local set = db().anItemOptional or {}; db().anItemOptional = set; set[choice[2]] = not set[choice[2]] end
            box:Hide(); UI.RebuildItemColumns()
        end, 204)
        UI.columnChoices[choice[2]] = b
    end
    UI.widthModeButton = action(box,"Width: " .. tostring(db().anItemWidthMode or "Normal"),10,-334,function(self)
        local m=db().anItemWidthMode or "Normal"; db().anItemWidthMode=m=="Normal" and "Wide" or (m=="Wide" and "Narrow" or "Normal")
        self:SetText("Width: " .. db().anItemWidthMode); UI.RebuildItemColumns()
    end,98)
    UI.resetColumnButton=action(box, "Reset Columns", 114, -334, function() db().anItemOptional=nil; db().anItemHidden=nil; db().anItemWidthMode=nil; box:Hide(); UI.RebuildItemColumns() end, 100)
end

function UI.RebuildItemColumns(silent)
    local view = UI.views.an_items; if not view then return end
    local targetWidth=math.max(1048,view._layoutWidth or (view.GetWidth and view:GetWidth()) or 0)
    local old = UI.tables.an_items
    if old then
        old.headerBar:Hide(); old.inset:Hide()
        if old.wellBgFrame and old.wellBgFrame.Hide then old.wellBgFrame:Hide() end
        if old.skinFrame and old.skinFrame.Hide then old.skinFrame:Hide() end
        local registered = app().ui.resizeTables or {}
        for i = #registered, 1, -1 do if registered[i] == old then table.remove(registered, i) end end
        for i = #UI._styledTables, 1, -1 do if UI._styledTables[i] == old then table.remove(UI._styledTables, i) end end
    end
    local cols, hidden = {}, db().anItemHidden or {}
    for _, col in ipairs(ITEM_COLS) do
        if col.key=="name" or not hidden[col.key] then local copy={}; for k,v in pairs(col) do copy[k]=v end; cols[#cols + 1]=copy end
    end
    local extras = {
        curBasis=column("curBasis", "Cur Basis", 72, nil, pricefield("curBasis")),
        avgProfit=column("avgProfit", "Avg Profit", 72, nil, pricefield("avgProfit")),
        lastSoldTs=column("lastSoldTs", "Last Sold", 90, "LEFT", function(r) return when(r.lastSoldTs) end),
        market=column("market", "MM Market", 76, nil, mfield("market")),
        craftCost=column("craftCost", "Craft Cost", 76, nil, mfield("craftCost")),
        lastBuyTs=column("lastBuyTs", "Last Buy", 90, "LEFT", function(r) return when(r.lastBuyTs) end),
    }
    local selected = db().anItemOptional or {}
    for key, col in pairs(extras) do
        local width = 4 + (#cols - 1) * 5; for _, c in ipairs(cols) do width = width + c.width end
        if selected[key] and width + col.width + 5 <= targetWidth then cols[#cols + 1] = col end
    end
    local factor=({Narrow=0.85,Normal=1,Wide=1.12})[db().anItemWidthMode or "Normal"] or 1
    local totalWidth=0; for _, col in ipairs(cols) do totalWidth=totalWidth+col.width+5 end
    factor=math.min(factor,targetWidth/math.max(totalWidth,1))
    if factor~=1 then for _, col in ipairs(cols) do col.width=math.max(36,math.floor(col.width*factor)) end end
    view.table = createTable(view, -66, "an_items", cols, 32)
    if silent then setRows(view.table,UI.lastItemRows or {}) else refresh() end
end

function UI.Layout(width,height)
    width=tonumber(width) or 0; height=tonumber(height) or (UI.content and UI.content:GetHeight()) or 0
    if width<=0 then return end
    local window=H() and H().Window
    local function visible(frame)
        return frame and ((frame.IsVisible and frame:IsVisible()) or (not frame.IsVisible and frame:IsShown()))
    end
    for key,view in pairs(UI.views) do if visible(view) then
        local changed=view._layoutWidth~=width
        local viewHeight=height>0 and height or view:GetHeight()
        view._layoutWidth=width; view:SetSize(width,viewHeight)
        if key=="an_items" and changed then UI.RebuildItemColumns(true) end
        for _,pane in ipairs({view.breakdownPane,view.charsPane,view.inventoryPane}) do pane:SetSize(width,viewHeight) end
        if view.toolbar then view.toolbar:SetWidth(width) end
        if view.feed then view.feed:SetWidth(math.max(1,width-16)) end
        if view.detail then
            view.detail:SetSize(math.max(1,width-170),math.max(1,viewHeight-66))
            view.detail.body:SetWidth(math.max(1,width-202))
        end
        local chartTop = (key == "an_overview") and 90 or 78
        for _,name in ipairs({"profit","wealth","trend"}) do
            local chart=view[name]
            if chart then
                local chartWidth=view.profit and (width-12)/2 or width
                local targetH = (key == "an_overview" or key == "an_writs") and math.max(168, math.min(220, math.floor((viewHeight > 0 and viewHeight or 560) * 0.30))) or chart:GetHeight()
                if chart.SetHeight and (key == "an_overview" or key == "an_writs") then chart:SetHeight(targetH) end
                if chart.Layout then chart:Layout(chartWidth,targetH) else chart:SetWidth(chartWidth) end
                chart:ClearAllPoints()
                if view.profit and name=="wealth" then
                    chart:SetPoint("TOPLEFT",chartWidth+12,-chartTop)
                else
                    chart:SetPoint("TOPLEFT",0,-chartTop)
                end
            end
        end
        if key == "an_overview" and view.seriesButton then
            local chartH = view.profit and view.profit:GetHeight() or 174
            local secY = -(chartTop + chartH + 12)
            local topCardH = math.max(120, viewHeight + secY)
            if view.periodBtns and view.wealth then
                local rx = -14
                for i = #view.periodBtns, 1, -1 do
                    local b = view.periodBtns[i]
                    b:ClearAllPoints()
                    b:SetPoint("TOPRIGHT", view.wealth, "TOPRIGHT", rx, -13)
                    rx = rx - (b:GetWidth() or 30) - 4
                end
                if view.wealth.summary then
                    view.wealth.summary:Hide()
                end
            end
            if view.topCard then
                view.topCard:ClearAllPoints()
                view.topCard:SetPoint("TOPLEFT", view, "TOPLEFT", 0, secY)
                view.topCard:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
            end
            local leftW = math.floor(width * 0.52)
            local rightW = math.max(200, width - leftW - 6)
            if view.tsmSummary then
                view.tsmSummary:SetSize(leftW, topCardH)
                view.tsmSummary:Layout(leftW, topCardH)
            end
            if view.topTablePane then
                view.topTablePane:ClearAllPoints()
                view.topTablePane:SetPoint("TOPLEFT", view.topCard, "TOPLEFT", leftW + 6, 0)
                view.topTablePane:SetPoint("BOTTOMRIGHT", view.topCard, "BOTTOMRIGHT", 0, 0)
                view.topTablePane:SetSize(rightW, topCardH)
            end
            view.seriesButton:ClearAllPoints()
            view.seriesButton:SetPoint("TOPRIGHT", view.topTablePane or view.topCard or view, "TOPRIGHT", -14, -12)
            if view.activityBtn then
                view.activityBtn:ClearAllPoints()
                view.activityBtn:SetPoint("RIGHT", view.seriesButton, "LEFT", -8, 0)
            end
            if view.secHdr then
                view.secHdr:ClearAllPoints()
                view.secHdr:SetPoint("TOPLEFT", view.topTablePane or view.topCard or view, "TOPLEFT", 14, -15)
            end
            if view.feed then
                view.feed:ClearAllPoints()
                view.feed:SetPoint("TOPLEFT", view.topTablePane or view.topCard or view, "TOPLEFT", 14, -48)
                view.feed:SetWidth(math.max(1, rightW - 28))
            end
            if view.table then view.table.analyticsY = -44 end
        elseif key == "an_writs" and view.trend and view.table then
            view.table.analyticsY = -(78 + view.trend:GetHeight() + 12)
        end
        local cards=view.kpis or {}; local gap = #cards > 4 and 10 or 12
        local cardWidth=#cards>0 and (width-(#cards-1)*gap)/#cards or 0
        for i,card in ipairs(cards) do
            local padX = card._padX or 14
            card:SetWidth(cardWidth); card:ClearAllPoints(); card:SetPoint("TOPLEFT",(i-1)*(cardWidth+gap),-4)
            card.title:SetWidth(math.max(1,cardWidth-padX*2)); card.value:SetWidth(math.max(1,cardWidth-padX*2))
            if card.sub then card.sub:SetWidth(math.max(1,cardWidth-padX*2)) end
        end
    end end
    local function layoutTables(tables)
        for _,tbl in pairs(tables) do if visible(tbl.analyticsParent) and visible(tbl.headerBar) then
            local parent=tbl.analyticsParent; local tblWidth=parent:GetWidth()
            if not tblWidth or tblWidth<=0 then tblWidth=width end
            local padL = tbl._transparentChrome and 0 or 6
            local padR = tbl._transparentChrome and 0 or 24
            tbl.headerBar:ClearAllPoints(); tbl.headerBar:SetPoint("TOPLEFT",parent,"TOPLEFT",padL,tbl.analyticsY or 0); tbl.headerBar:SetWidth(math.max(1,tblWidth-padR))
            local insetHeight=math.max(1,parent:GetHeight()+(tbl.analyticsY or 0)-26-(tbl.analyticsBottom or 0))
            if tbl.inset then
                tbl.inset:ClearAllPoints(); tbl.inset:SetPoint("TOPLEFT",parent,"TOPLEFT",0,(tbl.analyticsY or 0)-26); tbl.inset:SetSize(tblWidth,insetHeight)
            end
            if tbl.scrollBox then
                tbl.scrollBox:ClearAllPoints(); tbl.scrollBox:SetPoint("TOPLEFT",tbl.inset,"TOPLEFT",6,-5); tbl.scrollBox:SetSize(math.max(1,tblWidth-22),math.max(1,insetHeight-10))
            end
            if window and window.LayoutTable then window.LayoutTable(tbl,tblWidth,1) end
        end end
    end
    layoutTables(UI.tables); layoutTables(UI.auxTables)
end

UI.ToggleItemColumns = UI.ShowColumnPicker

function UI.ShowGroupPicker()
    if UI.choiceMenu then UI.choiceMenu:Hide() end
    local pal = getPalette()
    local vals, seen = { { key="", label="All Categories" } }, { [""]=true }
    local h = H()
    for _, r in pairs(h and h.RECIPES or {}) do
        local val = r.prof or r.profession or r.category
        if type(val)=="string" and val~="" and not seen[val] then seen[val]=true; vals[#vals+1]={key=val,label=val} end
    end
    for _, wr in pairs((ns.Model.GetIndexes and ns.Model.GetIndexes().WRIT_BY_ITEM) or {}) do
        local val = wr.prof or wr.category or "Writ Items"
        if not seen[val] then seen[val]=true; vals[#vals+1]={key=val,label=val} end
    end
    local box=CreateFrame("Frame",nil,UI.views[app().activeTab] or UI.views.an_items,"BackdropTemplate"); UI.choiceMenu=box
    box:SetFrameStrata("DIALOG"); box:SetSize(196,math.min(320,38+#vals*26)); box:SetPoint("TOPLEFT",560,-30)
    applySurface(box, "glass_r12", pal.cardBg, pal.borderStrong)
    text(box,"Category / Profession",-10, 12)
    for i,opt in ipairs(vals) do local choice=opt; action(box,choice.label,8,-26-i*25,function()
        local d, a = db(), app()
        if a and a.activeTab == "an_ledger" then
            d.anLedgerGroup = choice.key ~= "" and choice.key or nil
        else
            d.anProf = choice.key ~= "" and choice.key or nil
            d.anGroup = d.anProf
        end
        box:Hide(); refresh()
    end,180) end
end

function UI.ShowRarityPicker()
    if UI.choiceMenu then UI.choiceMenu:Hide() end
    local pal = getPalette()
    local box=CreateFrame("Frame",nil,UI.views[app().activeTab] or UI.views.an_items,"BackdropTemplate"); UI.choiceMenu=box
    box:SetFrameStrata("DIALOG"); box:SetSize(196,226); box:SetPoint("TOPLEFT",660,-30)
    applySurface(box, "glass_r12", pal.cardBg, pal.borderStrong)
    text(box,"Minimum Rarity",-10, 12)
    local names={"Any Rarity","Common+","Uncommon+","Rare+","Epic+","Legendary+","Artifact+"}
    for quality=0,6 do local selectedQuality=quality; action(box,names[selectedQuality+1],8,-28-selectedQuality*26,function()
        local d, a = db(), app()
        local value = selectedQuality > 0 and selectedQuality or nil
        if a and a.activeTab == "an_ledger" then
            d.anLedgerMinRarity = value
        else
            d.anMinRarity, d.anRarity = value, value
        end
        box:Hide(); refresh()
    end,180) end
end

function UI.ShowCharPicker()
    if UI.choiceMenu then UI.choiceMenu:Hide() end
    local pal = getPalette()
    local parent=UI.views[app().activeTab] or UI.views.an_items
    local opts=charOptions(); local box=CreateFrame("Frame",nil,parent,"BackdropTemplate"); UI.choiceMenu=box
    box:SetFrameStrata("DIALOG"); box:SetSize(226,math.min(360,40+#opts*26)); box:SetPoint("TOPLEFT",190,-54)
    applySurface(box, "glass_r12", pal.cardBg, pal.borderStrong)
    text(box,"Characters (multi-select)",-10, 12)
    local selected=db().anChars or {}; if not next(selected) then selected={} end
    for i,opt in ipairs(opts) do
        local choice=opt
        local checked=choice.key=="all" and not next(selected) or selected[choice.key]==true
        action(box,(checked and "[x] " or "[ ] ")..choice.label,8,-24-i*26,function()
            if choice.key=="all" then db().anChars=nil
            else selected[choice.key]=not selected[choice.key] or nil; if not next(selected) then db().anChars=nil else db().anChars=selected end end
            box:Hide(); refresh()
        end,210)
    end
end

function UI.ShowSourcePicker()
    if UI.choiceMenu then UI.choiceMenu:Hide() end
    local pal = getPalette()
    local vals={"all","AH","Vendor","Guild","Craft","COD","Trade","Mail","Quest/Loot"}
    local box=CreateFrame("Frame",nil,UI.views[app().activeTab] or UI.views.an_items,"BackdropTemplate"); UI.choiceMenu=box
    box:SetFrameStrata("DIALOG"); box:SetSize(176,268); box:SetPoint("TOPLEFT",0,-54)
    applySurface(box, "glass_r12", pal.cardBg, pal.borderStrong)
    text(box,"Source Type",-10, 12)
    for i,value in ipairs(vals) do local selectedSource=value; action(box,selectedSource,8,-24-i*26,function() db().anSource=selectedSource~="all" and selectedSource or nil; box:Hide(); refresh() end,160) end
end

function UI.ShowSettings()
    local box = editModal("Accounting Settings", "Tooltip accounting: " .. (db().anTooltips == false and "Off" or "On") ..
        " | Alt inventory: " .. (db().anTooltipInventory == false and "Off" or "On") ..
        " | Trade tracking: " .. (db().anTrackTrades == "off" and "Off" or "Auto") ..
        " | Retention: " .. tostring(db().anRetentionDays or 180) .. " days")
    UI.settingsActions = { box = box }
    UI.settingsActions.tooltips = action(box, "Toggle Tooltips", 12, -174, function() db().anTooltips = db().anTooltips == false; box:Hide() end, 100)
    UI.settingsActions.inventory = action(box, "Toggle Alt Inventory", 118, -174, function() db().anTooltipInventory = db().anTooltipInventory == false; box:Hide() end, 116)
    UI.settingsActions.trades = action(box, "Toggle Trades", 240, -174, function()
        db().anTrackTrades = db().anTrackTrades == "off" and "auto" or "off"; box:Hide()
    end, 82)
    local retention = tonumber(db().anRetentionDays) or 180
    UI.settingsActions.retention = action(box, "Retention: " .. tostring(retention) .. "d", 12, -204, function(self)
        local current = tonumber(db().anRetentionDays) or 180
        db().anRetentionDays = current == 90 and 180 or (current == 180 and 365 or 90)
        self:SetText("Retention: " .. tostring(db().anRetentionDays) .. "d")
    end, 116)
    UI.settingsActions.prune = action(box, "Prune Preview", 330, -174, function()
        local days = tonumber(db().anRetentionDays) or 180
        local cutoff = dateFn and dateFn("%Y-%m-%d", (time and time() or os.time()) - days * 86400)
        local preview = cutoff and ns.Store.PreviewPrune and ns.Store.PreviewPrune(cutoff)
        local summary = preview and preview.ok ~= false and ("Cutoff: " .. cutoff .. " | Rows: " .. num(preview.rowsToPrune) ..
            " | Days: " .. num(preview.daysToPrune) .. " | Estimated bytes after: " .. num(preview.estBytesAfter)) or "Preview unavailable"
        if preview and preview.ok == false then summary = tostring(preview.err or "Prune preview failed") end
        local confirm = editModal("Prune Preview", summary)
        UI.prunePreview = preview
        UI.pruneConfirm = action(confirm, "Confirm Prune", 300, -200, function()
            if not cutoff or not preview or preview.ok==false or not ns.Store.PruneBefore then return end
            local result=ns.Store.PruneBefore(cutoff)
            if result and result.ok~=false then confirm:Hide(); refresh()
            else confirm.edit:SetText(tostring(result and result.err or "Prune failed")) end
        end, 104)
        UI.pruneConfirm:SetEnabled(cutoff~=nil and preview~=nil and preview.ok~=false)
        UI.pruneCancel = action(confirm, "Cancel", 410, -200, function() confirm:Hide() end, 60)
    end, 100)
    UI.settingsActions.export = action(box, "Export Bundle", 134, -204, function()
        local bundle = ns.Transfer and ns.Transfer.ExportBundle and ns.Transfer.ExportBundle()
        editModal("Cross-Account Export", tostring(bundle or "Export unavailable"))
    end, 104)
    UI.settingsActions.import = action(box, "Import Bundle", 244, -204, function()
        local modal, edit = editModal("Cross-Account Import", "Paste a MerchantMaster MMX1 bundle here")
        edit:SetText(""); if edit.SetFocus then edit:SetFocus() end; UI.lastModalEdit = edit
        UI.importConfirm = action(modal, "Validate and Import", 270, -200, function()
            local result = ns.Transfer and ns.Transfer.Import and ns.Transfer.Import(edit:GetText())
            edit:SetText(result and result.ok and ("Imported " .. num(result.imported) .. "; skipped " .. num(result.skipped)) or (result and result.err or "Import unavailable"))
        end, 150)
    end, 96)
    UI.settingsActions.csv = action(box, "Store CSV", 346, -204, function() editModal("Copy Ledger CSV", ns.Store.Export(UI.Filters())) end, 84)
end

function UI.ToggleColumn(tab, key)
    local visible = db().anOptionalColumns or {}; db().anOptionalColumns = visible
    visible[tab .. ":" .. key] = not visible[tab .. ":" .. key]; refresh()
end

local function series(rows, field, name, colorKey)
    local points = {}
    for _, row in ipairs(rows or {}) do
        if row[field] ~= nil then points[#points + 1] = { day = row.day, label = row.label, value = row[field] } end
    end
    local colors = ns.Chart and ns.Chart.SeriesColors and ns.Chart.SeriesColors() or {}
    return { name = name, colorKey = colorKey, color = colors[colorKey], points = points }
end

local WEALTH_SERIES = {
    { key = "total", field = "total", name = "Total", colorKey = "blue" },
    { key = "gold", field = "gold", name = "Gold", colorKey = "green" },
    { key = "items", field = "items", name = "Inventory", colorKey = "orange" },
    { key = "listed", field = "listed", name = "Listed", colorKey = "purple" },
}

local function wealthData(chart, rows, title)
    local enabled = db().anWealthSeries or { total = true, gold = true, items = true, listed = true }
    local data = {}
    for _, spec in ipairs(WEALTH_SERIES) do
        if enabled[spec.key] then data[#data + 1] = series(rows, spec.field, spec.name, spec.colorKey) end
    end
    title = title or "Total Wealth"
    chart:SetTitle(title)
    chart:SetData(data, { title = title })
end

local function intradayRows(points)
    if type(points)~="table" then return nil end
    if type(points.points)=="table" then points=points.points end
    local rows={}
    for _, point in pairs(points) do
        if type(point)=="table" then
            local stamp=tonumber(point.timestamp or point.ts or point.time)
            local label=type(point.label)=="string" and point.label or (stamp and dateFn and dateFn("%H:%M",stamp))
            if not label and stamp then label=string.format("%02d:%02d",math.floor(stamp/3600)%24,math.floor(stamp/60)%60) end
            if not label and type(point.time)=="string" then label=point.time end
            if label then
                local inv=tonumber(point.items or point.inventory or point.itemValue) or 0
                local gold=tonumber(point.gold or point.money) or 0
                local listed=tonumber(point.listed or point.ah or point.listedValue) or 0
                rows[#rows+1]={day=label,label=label,total=tonumber(point.total or point.wealth) or (gold+inv+listed),gold=gold,items=inv,listed=listed,_stamp=stamp}
            end
        end
    end
    table.sort(rows,function(a,b) if a._stamp and b._stamp then return a._stamp<b._stamp end return a.label<b.label end)
    for _,row in ipairs(rows) do row._stamp=nil end
    return #rows>0 and rows or nil
end

function UI.ShowWealthSeriesMenu()
    if UI.seriesMenu then UI.seriesMenu:Hide() end
    local pal = getPalette()
    local parent = UI.views.an_overview
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate"); UI.seriesMenu = box
    box:SetFrameStrata("DIALOG"); box:SetSize(160, 140)
    if parent and parent.seriesButton then
        box:SetPoint("TOPRIGHT", parent.seriesButton, "BOTTOMRIGHT", 0, -4)
    else
        box:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -300)
    end
    applySurface(box, "glass_r12", pal.cardBg, pal.borderStrong)
    text(box, "Wealth Series", -10, 12)
    for i, spec in ipairs(WEALTH_SERIES) do
        local s = spec
        UI.seriesChoices = UI.seriesChoices or {}
        UI.seriesChoices[s.key] = action(box, (db().anWealthSeries or { total = true, gold = true, items = true, listed = true })[s.key] and "[x] " .. s.name or "[ ] " .. s.name,
            8, -28 - (i - 1) * 25, function()
                local selected = db().anWealthSeries or { total = true, gold = true, items = true, listed = true }; db().anWealthSeries = selected
                selected[s.key] = not selected[s.key]; box:Hide(); refresh()
            end, 144)
    end
end

local function styleSubBar(pal)
    local a = app()
    local bar = a and a.ui and a.ui.analyticsSubBar
    if not bar then return end
    if bar.UpdateTheme then
        bar.UpdateTheme(pal.mode, pal)
    else
        for _, btn in pairs(bar.buttons or {}) do
            if btn and btn._mmLabel then setTextColor(btn._mmLabel, pal.text) end
        end
    end
end

function UI.ApplyTheme()
    local pal = getPalette()
    if UI.banner then
        applySurface(UI.banner, "glass_r8", { pal.accentOrange[1], pal.accentOrange[2], pal.accentOrange[3], 0.16 }, false)
        setTextColor(UI.banner.label, pal.text)
    end
    for _, fs in ipairs(UI._textLabels or {}) do
        setTextColor(fs, fs._isMutedLabel and pal.textSecondary or pal.text)
    end
    for _, view in pairs(UI.views) do
        for _, card in ipairs(view.kpis or {}) do styleKpiCard(card, pal) end
        if view.topCard then applySurface(view.topCard, "glass_r10", pal.cardBg, false) end
        if view.tsmSummary and view.tsmSummary.ApplyTheme then view.tsmSummary:ApplyTheme(pal) end
        if view.cardDivider then
            view.cardDivider:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.55)
        end
        if view.footerBar and view.footerBar.ApplyTheme then view.footerBar:ApplyTheme(pal) end
        if view.inventoryFooterBar and view.inventoryFooterBar.ApplyTheme then view.inventoryFooterBar:ApplyTheme(pal) end
        if view.toolbar then applySurface(view.toolbar, "glass_r8", pal.cardBg, false) end
        if view.pageLabel then setTextColor(view.pageLabel, pal.textSecondary) end
        if view.footer then setTextColor(view.footer, pal.textSecondary) end
        if view.feed then setTextColor(view.feed, pal.textSecondary) end
        if view.secHdr then setTextColor(view.secHdr, pal.text) end
        if view.pushHdr then setTextColor(view.pushHdr, pal.text) end
        if view.recipeHdr then setTextColor(view.recipeHdr, pal.text) end
        if view.detail then
            applySurface(view.detail, "glass_r16", pal.cardBg, pal.borderStrong)
            setTextColor(view.detail.title, pal.text)
            setTextColor(view.detail.body, pal.textSecondary)
        end
    end
    for _, tbl in ipairs(UI._styledTables) do
        styleTableChrome(tbl, pal)
        if tbl.updateHeaders then tbl.updateHeaders() end
        if tbl.scrollBox and tbl.scrollBox.ForEachFrame then
            tbl.scrollBox:ForEachFrame(function(r)
                if r.data then styleRow(r, r.data, tbl, pal) end
            end)
        end
    end
    for _, btn in ipairs(UI._actionButtons) do styleActionButton(btn, pal) end
    if UI.modal then
        applySurface(UI.modal, "glass_r16", pal.cardBg, pal.borderStrong)
        setTextColor(UI.modal.title, pal.text)
    end
    if UI.ApplyPortfolioAuditTheme then UI.ApplyPortfolioAuditTheme(pal) end
    if UI.choiceMenu then applySurface(UI.choiceMenu, "glass_r12", pal.cardBg, pal.borderStrong) end
    if UI.seriesMenu then applySurface(UI.seriesMenu, "glass_r12", pal.cardBg, pal.borderStrong) end
    styleSubBar(pal)
    local a = app()
    if a and a.panel and a.panel:IsShown() and type(a.activeTab) == "string" and a.activeTab:sub(1, 3) == "an_" then
        UI.Refresh(a.activeTab, UI.content, a.ui and a.ui.statusText)
    end
end

local function ensureThemeHook()
    if UI._themeHooked then return end
    local h = H()
    if h and h.Theme and h.Theme.OnModeChanged then
        UI._themeHooked = true
        h.Theme.OnModeChanged(function() UI.ApplyTheme() end)
    end
end

local function notice()
    local disabled = {}
    for kind, paused in pairs(ledger().stats and ledger().stats.disabled or {}) do if paused then disabled[#disabled + 1] = kind end end
    table.sort(disabled)
    local warning
    if #disabled > 0 then warning = "Capture paused: " .. table.concat(disabled, ", ") .. " (click to reset)"
    elseif ns.Store.EstimateBytes() >= 3 * 1024 * 1024 then warning = "Ledger size > 3 MB" end
    UI.banner:SetShown(warning ~= nil); UI.banner.label:SetText(warning or "")
    UI.resetBar:ClearAllPoints()
    UI.resetBar:SetPoint("TOPLEFT", 0, warning and -26 or 0)
    UI.resetBar:SetPoint("TOPRIGHT", 0, warning and -26 or 0)
    UI.content:ClearAllPoints(); UI.content:SetPoint("TOPLEFT", 0, warning and -56 or -30); UI.content:SetPoint("BOTTOMRIGHT", 0, 0)
    return warning
end

function UI.Refresh(tab, container, status)
    local pal = getPalette()
    if not UI.content then
        UI.content = CreateFrame("Frame", nil, container)
        UI.resetBar = CreateFrame("Frame", nil, container)
        UI.resetBar:SetHeight(30)
        UI.resetButton = H().Theme.CreatePlateButton(UI.resetBar, "Reset Filters", 106, 24,
            { variant = "secondary", pill = true, fontSize = 11 })
        UI.resetButton:SetPoint("RIGHT", -6, 0)
        UI.resetButton:SetScript("OnClick", UI.ResetFilters)
        UI.filtersButton = H().Theme.CreatePlateButton(UI.resetBar, "Filters", 78, 24, {
            variant = "secondary",
            pill = true,
            fontSize = 11,
            icon = H().Theme.ASSETS and H().Theme.ASSETS.icon_bars,
            iconSize = 11,
        })
        UI.filtersButton:SetPoint("RIGHT", UI.resetButton, "LEFT", -6, 0)
        UI.filtersButton:SetScript("OnClick", function(self)
            local a = H() and H().app
            if a and a.toggleScreenFilters then a.toggleScreenFilters(self) end
        end)
        if H() and H().Theme and H().Theme.CreatePlateButton then
            UI.portfolioAuditBtn = H().Theme.CreatePlateButton(UI.resetBar, "Audit & Sync", 98, 24,
                { variant = "secondary", pill = true, fontSize = 11 })
            UI.portfolioAuditBtn:SetPoint("RIGHT", UI.filtersButton, "LEFT", -6, 0)
            UI.portfolioAuditBtn:SetScript("OnClick", function()
                if UI.ShowPortfolioAudit then UI.ShowPortfolioAudit() end
            end)
            UI.portfolioAuditBtn:Hide()
        end
        UI.banner = CreateFrame("Button", nil, container)
        UI.banner:SetPoint("TOPLEFT", 0, 0); UI.banner:SetPoint("TOPRIGHT", 0, 0); UI.banner:SetHeight(22)
        applySurface(UI.banner, "glass_r8", { pal.accentOrange[1], pal.accentOrange[2], pal.accentOrange[3], 0.16 }, false)
        UI.banner.label = text(UI.banner, "", -5, 11)
        UI.banner:SetScript("OnClick", function() ns.Store.ResetErrors(); refresh() end)
        ensureThemeHook()
    end
    styleSubBar(pal)
    local warning = notice()
    if UI.portfolioAuditBtn then UI.portfolioAuditBtn:SetShown(tab == "an_portfolio") end
    for key, view in pairs(UI.views) do view:SetShown(key == tab) end
    if not ({ an_overview = true, an_ledger = true, an_items = true, an_portfolio = true, an_invest = true, an_writs = true })[tab] then return end
    local wasNew = (UI.views[tab] == nil)
    local view, filters = ensureView(tab), UI.Filters()
    view:Show()
    -- Transaction type and zone controls apply to the ledger only.
    if tab ~= "an_ledger" then filters.type, filters.zone = "all", "all" end
    if tab ~= "an_overview" and tab ~= "an_items" then filters.knownCostOnly = false end
    local data
    if tab == "an_ledger" and ns.Model.QueryLedger then
        local selectedChars = {}
        for char, selected in pairs(filters.chars or {}) do if selected == true then selectedChars[#selectedChars + 1] = char end end
        table.sort(selectedChars)
        local scope = table.concat({ tostring(filters.char), table.concat(selectedChars, ","), tostring(filters.period), tostring(filters.type), tostring(filters.zone),
            tostring(filters.search), tostring(filters.source), tostring(filters.faction), tostring(filters.prof), tostring(filters.group),
            tostring(filters.minRarity), tostring(filters.coalesce), tostring(filters.ledgerPreset) }, "|")
        if UI._ledgerScope ~= scope then db().anLedgerOffset = 0; filters.page = 0; UI._ledgerScope = scope end
        data = ns.Model.QueryLedger(filters, filters.page, filters.limit)
        data.rows = data.rows or {}
    else data = ns.Model.Compute(tab:sub(4), filters) end

    if tab == "an_overview" then
        local metrics = data.kpis or data
        for i, key in ipairs({ "profit", "sales", "purchases", "depLost", "lootValue", "wealthChange", "unexplained" }) do
            local signed = (key == "profit" or key == "wealthChange" or key == "unexplained")
            local val = tonumber(metrics[key]) or 0
            view.kpis[i].value:SetJustifyH("RIGHT")
            view.kpis[i].value:SetText(money(val, signed))
            local dailyKey = ({ profit="avgDailyProfit", sales="avgDailySales", purchases="avgDailyPurchases" })[key]
            if dailyKey then
                local dv = tonumber(metrics[dailyKey]) or 0
                view.kpis[i].value:SetText(view.kpis[i].value:GetText() .. "|n|cff" .. pal.hexMuted .. "Avg/Day|r " .. money(dv))
                if view.kpis[i].sub then view.kpis[i].sub:SetText("") end
            elseif view.kpis[i].sub then
                view.kpis[i].sub:SetText(selectedLabel(PERIODS, filters.period))
            end
        end
        local sale, buy = data.topSingleSale or {}, data.topSingleBuy or {}
        local function delta(val) return val == nil and "n/a" or string.format("%+.1f%%", val) end
        view.kpis[1].tip = "Previous period: " .. money(metrics.prevProfit or 0) .. " | Change: " .. delta(metrics.profitDeltaPct) ..
            " | Top Sale: " .. tostring(sale.name or "-") .. " " .. money(sale.total or 0)
        view.kpis[2].tip = "Previous period: " .. money(metrics.prevSales or 0) .. " | Change: " .. delta(metrics.salesDeltaPct) ..
            " | Top Sale: " .. tostring(sale.name or "-") .. " to " .. tostring(sale.buyer or "-")
        view.kpis[3].tip = "Previous period: " .. money(metrics.prevPurchases or 0) .. " | Change: " .. delta(metrics.purchasesDeltaPct) ..
            " | Top Buy: " .. tostring(buy.name or "-") .. " from " .. tostring(buy.seller or "-")
        view.kpis[6].tip = "52-week high: " .. money(metrics.high52w or 0) .. " | low: " .. money(metrics.low52w or 0)
        view.profit:SetData(data.profitByDay)
        local todayPoints = filters.period == "today" and intradayRows(data.intradayWealth) or nil
        wealthData(view.wealth, todayPoints or data.wealth, todayPoints and "Today's Wealth (Intraday)" or "Total Wealth")
        if view.periodBtns then
            local activeP = filters.period or "30d"
            for _, b in ipairs(view.periodBtns) do
                stylePillToggle(b, b._periodKey == activeP, pal)
            end
        end
        if view.tsmSummary and view.tsmSummary.Update then
            view.tsmSummary:Update(data, pal)
        end
        setRows(view.table, data.top, nil, 5)
        local feedHost = view.topTablePane or view.topCard or view
        local feedW = math.max(200, ((feedHost.GetWidth and feedHost:GetWidth()) or 508) - 28)
        view.feed = view.feed or text(feedHost, "", -48, 12); view.feed:ClearAllPoints(); view.feed:SetPoint("TOPLEFT", feedHost, "TOPLEFT", 14, -48)
        view.feed:SetSize(feedW, 220); view.feed:SetJustifyH("LEFT")
        local feedLines = {}
        local showingFeed = db().anShowActivity == true
        if showingFeed then
            for i, entry in ipairs(data.activityFeed or {}) do
                if i > 7 then break end
                feedLines[#feedLines + 1] = tostring(entry.day) .. " " .. tostring(entry.charShort or entry.char) ..
                    " sold " .. num(entry.soldQty) .. " / bought " .. num(entry.boughtQty) .. " / net " ..
                    (entry.netGold ~= nil and money(entry.netGold, true) or "-")
            end
            feedLines[#feedLines+1]="Sale Hints:"
            for i,row in ipairs(data.top or {}) do
                if i>3 then break end
                if row.itemID and ns.Model.GetSaleHint then
                    local ok,hint=pcall(ns.Model.GetSaleHint,row.itemID)
                    if ok and hint then feedLines[#feedLines+1]=tostring(row.name or row.itemName or row.itemID)..": "..
                        tostring(hint.action or "hold").." - "..tostring(hint.reason or "").." (expires "..num(hint.expSinceSale)..
                        (hint.isSlowing and ", slowing" or "")..")" end
                end
            end
            feedLines[#feedLines+1]="Recent Auctioning Activity:"
            if ns.Model.QueryLedger then
                local logFilters={}; for k,v in pairs(filters) do logFilters[k]=v end
                logFilters.types={AUCTION_LOG=true}; logFilters.coalesce=false
                local ok,result=pcall(ns.Model.QueryLedger,logFilters,0,5)
                for i,row in ipairs(ok and result and result.rows or {}) do
                    if i>5 then break end
                    local extra=row.extra or {}; local actionText=extra.action or extra.operation or row.type or "Auction"
                    local reason=extra.reason or extra.message or ""
                    feedLines[#feedLines+1]=tostring(row.charShort or row.char or "").." "..tostring(actionText)..
                        (reason~="" and (": "..tostring(reason)) or "")
                end
            end
        end
        view.feed:SetText(showingFeed and ("Session Activity\n" .. table.concat(feedLines, "\n")) or "")
        if view.feed.Show and view.feed.Hide then
            if showingFeed then view.feed:Show() else view.feed:Hide() end
        end
        if view.table.SetShown then view.table:SetShown(not showingFeed)
        else
            for _, part in ipairs({ view.table.headerBar, view.table.inset }) do
                if part then if showingFeed then part:Hide() else part:Show() end end
            end
        end
        if not view.activityBtn then
            view.activityBtn = action(view.topTablePane or view.topCard or view, "Session Activity", 300, -12, function() db().anShowActivity = not db().anShowActivity; refresh() end, 112)
            view.activityBtn:ClearAllPoints()
            view.activityBtn:SetPoint("RIGHT", view.seriesButton, "LEFT", -8, 0)
        end
    elseif tab == "an_ledger" then
        UI.lastLedgerRows = data.rows
        setRows(view.table, data.rows)
        local totals = data.totals or {}
        local inflow = tonumber(totals.inflow) or 0
        local outflow = tonumber(totals.outflow) or 0
        local realized = totals.profit ~= nil and tonumber(totals.profit) or (tonumber(totals.net) or 0)
        local netFlow = tonumber(totals.net) or 0
        local fee = tonumber(totals.fee) or 0
        view.kpis[1].value:SetJustifyH("RIGHT")
        view.kpis[1].value:SetText(money(inflow))
        view.kpis[1].sub:SetText(num(data.totalMatched) .. " matched entries")
        view.kpis[2].value:SetJustifyH("RIGHT")
        view.kpis[2].value:SetText(money(realized, true))
        view.kpis[2].sub:SetJustifyH("RIGHT")
        view.kpis[2].sub:SetText("Net cashflow " .. money(netFlow, true))
        view.kpis[3].value:SetJustifyH("RIGHT")
        view.kpis[3].value:SetText(money(outflow))
        view.kpis[3].sub:SetJustifyH("RIGHT")
        view.kpis[3].sub:SetText("AH fees " .. money(fee))
        local base = outflow > 0 and outflow or (inflow > 0 and inflow or 0)
        if base > 0 then
            local roi = realized / base * 100
            local hex = roi >= 0 and pal.hexGreen or pal.hexRed
            view.kpis[4].value:SetText("|cff" .. hex .. string.format("%+.1f%%", roi) .. "|r")
            view.kpis[4].sub:SetText(outflow > 0 and "Return on spend" or "Net margin")
            if view.kpis[4].badge and view.kpis[4].badge.SetVariant then
                view.kpis[4]._badgeVariant = roi >= 0 and "pos" or "hot"
                view.kpis[4]._badgeText = roi >= 0 and "+ROI" or "-ROI"
                view.kpis[4].badge.SetVariant(view.kpis[4]._badgeVariant, view.kpis[4]._badgeText)
                view.kpis[4].badge.frame:Show()
            end
        else
            view.kpis[4].value:SetText("|cff" .. pal.hexMuted .. "-|r")
            view.kpis[4].sub:SetText("No cashflow in period")
            if view.kpis[4].badge then view.kpis[4].badge.frame:Hide() end
        end

        local offset, limit = tonumber(data.cursor) or (filters.page or 0), tonumber(data.limit) or filters.limit or 500
        local pageNum=math.floor(offset/math.max(1,limit))+1
        local pageTotal=math.max(1,math.ceil((tonumber(data.totalMatched) or 0)/math.max(1,limit)))
        view.pageLabel:SetText("Page " .. tostring(pageNum) .. " of " .. tostring(pageTotal) .. " · Total " .. num(data.totalMatched))
        view.prev:SetEnabled(offset > 0); view.next:SetEnabled(data.hasMore == true)
        local presetKey = filters.ledgerPreset or "all"
        if view.presetBtns then
            for _, b in ipairs(view.presetBtns) do
                stylePillToggle(b, b._presetKey == presetKey, pal)
            end
        end
        local goldHex = (pal.mode == "light") and "9a6700" or "ffd100"
        if presetKey == "sales" then
            view.footer:SetText("|cff" .. goldHex .. num(totals.qty) .. "|r Items Sold:  " .. money(inflow))
        elseif presetKey == "purchases" then
            view.footer:SetText("|cff" .. goldHex .. num(totals.qty) .. "|r Items Bought:  " .. money(outflow))
        elseif presetKey == "craft" then
            view.footer:SetText("|cff" .. goldHex .. num(totals.qty) .. "|r Items Crafted  ·  Craft Cost: " .. money(totals.cogs or 0))
        elseif presetKey == "trade" then
            view.footer:SetText("Trades: |cff" .. goldHex .. num(data.totalMatched) .. "|r  ·  Qty: " .. num(totals.qty) ..
                "  ·  Inflow: " .. money(inflow, true) .. "  ·  Outflow: " .. money(-outflow, true) .. "  ·  Net: " .. money(netFlow, true))
        elseif presetKey == "loot" then
            view.footer:SetText("|cff" .. goldHex .. num(totals.qty) .. "|r Items Looted / Gathered")
        elseif presetKey == "expired" then
            view.footer:SetText("|cff" .. goldHex .. num(totals.qty) .. "|r Items Expired")
        elseif presetKey == "cancelled" then
            view.footer:SetText("|cff" .. goldHex .. num(totals.qty) .. "|r Items Cancelled")
        else
            view.footer:SetText("Matched: |cff" .. goldHex .. num(data.totalMatched) .. "|r  ·  Qty: " .. num(totals.qty) ..
                "  ·  Inflow: " .. money(inflow, true) .. "  ·  Outflow: " .. money(-outflow, true) .. "  ·  Net: " .. money(netFlow, true))
        end
        view.preset:SetText("Preset: " .. (LEDGER_PRESET_NAMES[presetKey] or "All"))
    elseif tab == "an_items" then
        local mode = db().anItemMode or "profit"
        local visible, totals = {}, {qtySold=0,qtyBought=0,gross=0,spent=0,fee=0,cogs=0,depLost=0,profit=0}
        for _, r in ipairs(data.rows or {}) do
            if (mode ~= "slowing" or r.isSlowing) and (mode ~= "relists" or (r.expired or 0) + (r.cancelled or 0) > 0)
                and (mode ~= "sales" or (r.sold or 0) > 0) and (mode ~= "purchases" or (r.bought or 0) > 0) then
                local display={}; for k,v in pairs(r) do display[k]=v end
                visible[#visible+1]=display
                totals.qtySold=totals.qtySold+(r.sold or 0); totals.qtyBought=totals.qtyBought+(r.bought or 0)
                for _,k in ipairs({"gross","spent","fee","cogs","depLost","profit"}) do totals[k]=totals[k]+(r[k] or 0) end
            end
        end
        local optional=db().anItemOptional or {}; local hostApi=H()
        for _, r in ipairs(visible) do
            if optional.market and hostApi and hostApi.GetItemMarketPrice then
                local ok,value=pcall(hostApi.GetItemMarketPrice,r.itemID); if ok then r.market=value end
            end
            if optional.craftCost and ns.Model.GetItemStats then
                local stats=ns.Model.GetItemStats(r.itemID,filters); r.craftCost=stats and stats.craftCost
                if not r.craftCost and hostApi and hostApi.RECIPES_BY_OUTPUT and hostApi.ComputeCraftCost then
                    local list=hostApi.RECIPES_BY_OUTPUT[r.itemID]; local recipe=list and (list.reagents and list or list[1])
                    if recipe then local ok,value=pcall(hostApi.ComputeCraftCost,recipe.reagents,recipe.numMade,r.itemID); if ok then r.craftCost=value end end
                end
            end
        end
        UI.lastItemRows=setRows(view.table, visible)
        if view.preset then stylePillToggle(view.preset, mode == "profit", pal) end
        if view.sales then stylePillToggle(view.sales, mode == "sales", pal) end
        if view.purchases then stylePillToggle(view.purchases, mode == "purchases", pal) end
        if view.expired then stylePillToggle(view.expired, mode == "relists", pal) end
        if view.slow then stylePillToggle(view.slow, mode == "slowing", pal) end
        if view.emptyText then
            setTextColor(view.emptyText, pal.textMuted)
            if #visible == 0 then
                if filters.knownCostOnly then
                    view.emptyText:SetText("No items with known cost basis in this period.\nUncheck 'Known Cost Only' in Filters or click 'Reset Filters' to show all items.")
                else
                    view.emptyText:SetText("No items match the current filters for " .. selectedLabel(PERIODS, filters.period) .. ".")
                end
                view.emptyText:Show()
            else
                view.emptyText:Hide()
            end
        end
        local goldHex = (pal.mode == "light") and "9a6700" or "ffd100"
        view.footer:SetText("Sold: |cff" .. goldHex .. num(totals.qtySold) .. "|r  ·  Bought: |cff" .. goldHex .. num(totals.qtyBought) .. "|r  ·  Gross: " ..
            money(totals.gross) .. "  ·  Spent: " .. money(totals.spent) .. "  ·  Profit: " .. money(totals.profit, true))
        view.group:SetText("Group: " .. tostring(db().anGroupBy or "base"))
        view.source:SetText("Source: " .. tostring(db().anSource or "All"))
        view.faction:SetText("Faction: " .. tostring(db().anFaction or "All"))
        if UI.detailKey and view.detail and view.detail:IsShown() then UI.ShowItemDetail(UI.detailKey) end
    elseif tab == "an_portfolio" then
        for i, key in ipairs({ "latestTotal", "latestGold", "latestItems", "latestListed" }) do
            view.kpis[i].value:SetJustifyH("RIGHT")
            view.kpis[i].value:SetText(money(data[key]))
            if view.kpis[i].sub then view.kpis[i].sub:SetText(selectedLabel(PORTFOLIO_VIEWS, db().anPortfolioView or "breakdown")) end
        end
        view.kpis[3].tip = string.format("Bags: %s | Bank: %s | Mail: %s | Gear: %s\nSoulbound and equipped items are valued at vendor sell price.",
            money(data.latestBags or 0), money(data.latestBank or 0), money(data.latestMail or 0), money(data.latestGear or 0))
        wealthData(view.wealth, data.series)
        local pMode = db().anPortfolioView or "breakdown"
        local showSummaryTop = (pMode ~= "inventory")
        for _, card in ipairs(view.kpis or {}) do card:SetShown(showSummaryTop) end
        if view.wealth then view.wealth:SetShown(showSummaryTop) end
        view.breakdownPane:SetShown(pMode == "breakdown")
        view.charsPane:SetShown(pMode == "chars")
        view.inventoryPane:SetShown(pMode == "inventory")
        if pMode == "breakdown" then
            UI.expandedWealth = UI.expandedWealth or { bags = true }
            local st = app().sortState.an_wealth or { col = "total", asc = false }
            local flat = {}
            local grand = math.max(1, data.latestTotal or 0)
            for _, cat in ipairs(data.categories or {}) do
                local exp = UI.expandedWealth[cat.catKey] == true
                local basisSummary = (data.latestTotal or 0) > 0 and (percent((cat.total or 0) / grand) .. " of wealth") or "-"
                flat[#flat + 1] = {
                    isCategory = true, catKey = cat.catKey, title = cat.title, label = cat.title,
                    expanded = exp, itemCount = cat.itemCount or 0,
                    qty = cat.catKey ~= "gold" and (cat.unitCount or 0) or nil,
                    basis = basisSummary, total = cat.total or 0,
                    sharePct = (data.latestTotal or 0) > 0 and ((cat.total or 0) / grand) or nil,
                    rowIndex = #flat + 1,
                }
                if exp and #(cat.items or {}) > 0 then
                    local children = {}
                    for idx, child in ipairs(cat.items) do
                        local copy = {}; for k, v in pairs(child) do copy[k] = v end
                        copy._order = idx; children[#children + 1] = copy
                    end
                    table.sort(children, function(a, b)
                        local av, bv = a[st.col], b[st.col]
                        if av == bv then return a._order < b._order end
                        if av == nil then return false elseif bv == nil then return true end
                        if type(av) ~= type(bv) then av, bv = tostring(av), tostring(bv) end
                        if st.asc then return av < bv end
                        return av > bv
                    end)
                    for _, child in ipairs(children) do
                        child.rowIndex = #flat + 1
                        flat[#flat + 1] = child
                    end
                end
            end
            view.breakdownTable.setRows(flat); view.breakdownTable.updateHeaders()
        elseif pMode == "chars" then
            setRows(view.table, data.byChar)
        else
            local matrix = ns.Model.GetInventoryMatrix and ns.Model.GetInventoryMatrix({ char = filters.char, chars = filters.chars,
                faction = filters.faction, econ = filters.econ, valSource = db().anInvPriceSource or "market",
                includeGuild = db().anInvIncludeGuild == true, search = view.inventorySearch:GetText() }) or { rows = {}, totals = {} }
            setRows(view.inventoryTable, matrix.rows)
            if view.inventoryFooterBar and view.inventoryFooterBar.text then
                local invVal = (matrix.totals and matrix.totals.value) or 0
                local invUnits = (matrix.totals and matrix.totals.units) or 0
                view.inventoryFooterBar.text:SetText("Total Value:  " .. money(invVal) .. "   |cff" .. pal.hexMuted .. "(" .. num(invUnits) .. " items)|r")
            end
            view.inventoryPrice:SetText("Price: " .. tostring(db().anInvPriceSource or "market"))
            view.inventoryGuild:SetText(db().anInvIncludeGuild and "Guild: On" or "Guild: Off")
        end
    elseif tab == "an_invest" then setRows(view.pushes, data.pushes); setRows(view.recipes, data.recipes)
    elseif tab == "an_writs" then
        view.kpis[1].value:SetJustifyH("RIGHT")
        view.kpis[1].value:SetText(data.perRep and money(data.perRep) or "No turn-ins logged")
        view.kpis[2].value:SetJustifyH("RIGHT")
        view.kpis[2].value:SetText((data.favorPrice and data.favorPrice > 0) and money(data.favorPrice) or "No crates logged")
        view.kpis[3].value:SetText(num(data.totalWrits)); view.kpis[4].value:SetText(num(data.pendingPouches))
        view.kpis[4].tip = "Estimated pending refunds: " .. money(data.pendingRefundEst)
        local trendFilters = {}; for k, v in pairs(filters) do trendFilters[k] = v end; trendFilters.period = "30d"
        local trend = ns.Model.Compute("writs", trendFilters).trend
        view.trend:SetData({ series(trend, "perRep", "Cost / Rep", "blue"), series(trend, "favorPrice", "Cost / Favor", "green") })
        local tiers = {}; for _, row in ipairs(data.perRepByTier or {}) do tiers[#tiers + 1] = row end
        if (data.totalCrates or 0) > 0 then tiers[#tiers + 1] = { tier = "Waylaid Crates", tierOrder = 999,
            writs = data.totalCrates, rep = data.totalFavor, grossCost = data.totalFavorNetCost,
            refunds = 0, netCost = data.totalFavorNetCost, perRep = data.favorPrice } end
        setRows(view.table, tiers)
    end
    if UI.content and UI.content.GetWidth then
        local cw = tonumber(UI.content:GetWidth()) or 0
        local ch = tonumber(UI.content:GetHeight()) or 0
        if cw > 0 and (wasNew or view._layoutWidth ~= cw) then
            UI.Layout(cw, ch)
        end
    end
    if status then status:SetText(warning or ("Analytics | " .. selectedLabel(PERIODS, filters.period) ..
        (data.totalMatched and (" | " .. data.totalMatched .. " matched (latest 500)") or ""))) end
end

function UI.ScheduleRefresh()
    UI.refreshGeneration = (UI.refreshGeneration or 0) + 1
    local generation = UI.refreshGeneration
    local function run()
        if generation ~= UI.refreshGeneration then return end
        local a = app()
        if a and a.panel and a.panel:IsShown() and type(a.activeTab) == "string" and a.activeTab:sub(1, 3) == "an_" then refresh() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, run) end
end

function UI.Register()
    if UI.registered or not H() or not app() or not app().ui.makeSidebarDrop then return false end
    createControls()
    ensureThemeHook()
    styleSubBar(getPalette())
    UI.provider = { controls = UI.controls, sidebarControls = UI.GetSidebarControls, refresh = UI.Refresh, resetFilters = UI.ResetFilters,
        getAverages = function() return ns.Model.Compute("averages", { char = "all", period = "all" }) end,
        GetPriceSource = function(source, itemID, filters) return ns.Model.GetPriceSource(source, itemID, filters) end,
        GetItemStats = function(itemID, filters) return ns.Model.GetItemStats(itemID, filters) end }
    UI.registered = _G.MerchantMasterAPI.RegisterAnalytics(UI.provider)
    ns.Store.onChange = function(row,kind) ns.Model.Invalidate(kind); UI.ScheduleRefresh() end
    return UI.registered
end

local function say(message)
    print("|cffffcc55MerchantMaster Analytics:|r " .. message)
end

function UI.Slash(message)
    local command = (message or ""):lower():match("^%s*(%S+)") or ""
    if command == "probe" then
        local d = ledger(); d.probe = d.probe or { log = {} }; d.probe.enabled = not d.probe.enabled
        say("Probe " .. (d.probe.enabled and "on" or "off") .. "; " .. #(d.probe.log or {}) .. " entries")
    elseif command == "snapshot" then ns.Capture.QueueWealthSnapshot()
    elseif command == "audit" then if UI.ShowPortfolioAudit then UI.ShowPortfolioAudit() end
    elseif command == "reseterrors" then ns.Store.ResetErrors(); refresh()
    elseif command == "status" then
        local rows, days = 0, 0
        for _ in pairs(ledger().days or {}) do days = days + 1 end
        local result = ns.Model.Compute("ledger", { char = "all", type = "all", zone = "all", period = "all" })
        rows = result.totalMatched or #(result.rows or {})
        local avg = ns.Model.Compute("averages", { char = "all", period = "all" })
        say(string.format("%d rows / %d days; %.1f KB; writ / rep %s; favor / token %s", rows, days,
            ns.Store.EstimateBytes() / 1024, avg.perRep and money(avg.perRep) or "-", avg.favorPrice and money(avg.favorPrice) or "-"))
    elseif _G.MerchantMasterAPI then _G.MerchantMasterAPI.TogglePanel(command == "ledger" and "an_ledger" or "analytics") end
end

_G.SLASH_MERCHANTMASTERANALYTICS1 = "/mma"
SlashCmdList.MERCHANTMASTERANALYTICS = UI.Slash
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED"); events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then UI.Register() end
end)

-- Portfolio Audit & Sync Modal (scoped to consume 0 top-level locals)
do
    local function paintAuditModal(box, pal)
        if not box then return end
        pal = pal or getPalette()
        applySurface(box, "glass_r16", pal.cardBg, pal.borderStrong)
        if box.title then setTextColor(box.title, pal.text) end
        if box.statusFs then setTextColor(box.statusFs, pal.textSecondary) end
        if box.summaryFs then setTextColor(box.summaryFs, pal.text) end
        if box.reportCard then applySurface(box.reportCard, "glass_r10", pal.cardAltBg or pal.cardBg, pal.border) end
        if box.edit and box.edit.SetTextColor then setTextColor(box.edit, pal.text) end
    end

    local function renderAuditResult(box, report, syncResult)
        local pal = getPalette()
        local active = (syncResult and syncResult.after) or report
        if not active then
            box.statusFs:SetText("|cff" .. pal.hexOrange .. "Inventory analyzer unavailable.|r")
            box.summaryFs:SetText("")
            box.edit:SetText("Portfolio Audit & Sync requires Analytics.Inventory.")
            return
        end
        local bankColor = active.bankOpen and pal.hexGreen or pal.hexOrange
        box.statusFs:SetText("|cff" .. bankColor .. "Bank: " .. tostring(active.bankStatus or "-") .. "|r")
        local s = active.summary or {}
        if syncResult and syncResult.before then
            local b = syncResult.before.summary or {}
            local deltaHex = (s.totalIssues or 0) <= (b.totalIssues or 0) and pal.hexGreen or pal.hexOrange
            box.summaryFs:SetText(string.format(
                "|cff%sSynced: %d -> %d issues|r  |  Duplicates: %d  |  Drift: %d  |  Stale: %d  |  Basis/Ledger: %d",
                deltaHex, b.totalIssues or 0, s.totalIssues or 0,
                s.duplicates or 0, s.drift or 0, s.stale or 0, s.ledger or 0))
            box.edit:SetText(syncResult.summaryText or active.text or "")
        else
            local countHex = (s.totalIssues or 0) == 0 and pal.hexGreen or pal.hexOrange
            box.summaryFs:SetText(string.format(
                "|cff%sIssues: %d|r  |  Duplicates: %d  |  Bag/Bank Drift: %d  |  Stale AH/Transit: %d  |  Basis/Ledger: %d",
                countHex, s.totalIssues or 0,
                s.duplicates or 0, s.drift or 0, s.stale or 0, s.ledger or 0))
            box.edit:SetText(active.text or "")
        end
        if box.edit.SetCursorPosition then pcall(box.edit.SetCursorPosition, box.edit, 0) end
        box._lastReport = active
        box._lastSync = syncResult
    end

    function UI.ApplyPortfolioAuditTheme(pal)
        paintAuditModal(UI.portfolioAuditModal, pal)
        if UI.portfolioAuditModal and UI.portfolioAuditModal:IsShown() and UI.portfolioAuditModal._lastReport then
            renderAuditResult(UI.portfolioAuditModal, UI.portfolioAuditModal._lastReport, UI.portfolioAuditModal._lastSync)
        end
    end

    function UI.ShowPortfolioAudit(opts)
        local pal = getPalette()
        local box = UI.portfolioAuditModal
        if not box then
            box = CreateFrame("Frame", nil, UI.content or _G.UIParent, "BackdropTemplate")
            UI.portfolioAuditModal = box
            box:SetFrameStrata("DIALOG")
            box:SetSize(680, 440)
            box:SetPoint("CENTER")
            box.title = text(box, "Portfolio Audit & Sync", -14, 14)
            box.statusFs = text(box, "", -36, 11, true)
            box.statusFs:SetWidth(648); box.statusFs:SetJustifyH("LEFT")
            box.summaryFs = text(box, "", -54, 11, false)
            box.summaryFs:SetWidth(648); box.summaryFs:SetJustifyH("LEFT")

            local card = CreateFrame("Frame", nil, box)
            card:SetPoint("TOPLEFT", 14, -76)
            card:SetPoint("BOTTOMRIGHT", -14, 48)
            box.reportCard = card

            local scroll = CreateFrame("ScrollFrame", nil, card, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", 8, -8)
            scroll:SetPoint("BOTTOMRIGHT", -24, 8)
            box.scroll = scroll

            local edit = CreateFrame("EditBox", nil, scroll)
            edit:SetAutoFocus(false)
            if edit.SetMultiLine then edit:SetMultiLine(true) end
            edit:SetSize(610, 300)
            applyFont(edit, 11, "regular")
            if edit.SetScript then
                edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            end
            if scroll.SetScrollChild then scroll:SetScrollChild(edit) end
            box.edit = edit

            box.analyzeBtn = action(box, "Analyze", 14, -404, function()
                local rep = ns.Inventory and ns.Inventory.AnalyzePortfolio and ns.Inventory.AnalyzePortfolio(box._opts)
                renderAuditResult(box, rep, nil)
            end, 92)
            box.syncBtn = action(box, "Sync Snapshots", 114, -404, function()
                if not (ns.Inventory and ns.Inventory.SyncPortfolio) then return end
                local syncOpts = { reconcileBasis = false }
                if type(box._opts) == "table" then
                    for k, v in pairs(box._opts) do syncOpts[k] = v end
                    syncOpts.reconcileBasis = false
                end
                local res = ns.Inventory.SyncPortfolio(syncOpts)
                renderAuditResult(box, res and res.after, res)
                refresh()
            end, 126)
            box.alignBasisBtn = action(box, "Sync + Align Basis", 248, -404, function()
                if not (ns.Inventory and ns.Inventory.SyncPortfolio) then return end
                local syncOpts = { reconcileBasis = true }
                if type(box._opts) == "table" then
                    for k, v in pairs(box._opts) do syncOpts[k] = v end
                    syncOpts.reconcileBasis = true
                end
                local res = ns.Inventory.SyncPortfolio(syncOpts)
                renderAuditResult(box, res and res.after, res)
                refresh()
            end, 146)
            box.closeBtn = action(box, "Close", 594, -404, function() box:Hide() end, 72)
        end
        box._opts = opts
        paintAuditModal(box, pal)
        local report = ns.Inventory and ns.Inventory.AnalyzePortfolio and ns.Inventory.AnalyzePortfolio(opts)
        renderAuditResult(box, report, nil)
        box:Show()
        return box, report
    end
end

---------------------------------------------------------------------------------------------------
-- Unified Deep Analysis Screen (host.DeepAnalysis)
-- Lazy-built on first open; supports recipe, writ, crate, forged, and market item drill-downs.
---------------------------------------------------------------------------------------------------
do
    local DeepAnalysis = {}
    host.DeepAnalysis = DeepAnalysis
    ns.DeepAnalysis = DeepAnalysis

    local TAB_RETURN_LABELS = {
        dashboard = "Dashboard",
        recipes = "Super List",
        vendor_crafter = "Vendor Crafter",
        disenchant_crafter = "Disenchantment Crafter",
        profit_spread = "Profit Spread",
        outliers = "Outliers",
        writs = "Writs",
        crates = "Crates",
        forged = "Forged",
        rep = "Reputation",
        calc = "Calculator",
        calc_favor = "Favor Calc",
        calc_rep = "Rep Calc",
        an_overview = "Ledger",
        an_ledger = "Ledger",
        an_items = "Item Ledger",
        an_portfolio = "Portfolio",
        an_invest = "Investments",
        an_writs = "Writ Ledger",
        prof_path = "Leveling",
        prof_shop = "Leveling",
        prof_browse = "Leveling",
    }

    local state = {
        built = false,
        root = nil,
        target = nil,
        data = nil,
        window = "7d",
        scrollOffset = 0,
        viewportW = 1060,
        viewportH = 620,
        contentH = 920,
        reagentRows = {},
        reagentUsedCount = 0,
        vcRow = nil,
        vcCapRows = {},
        vcCapUsed = 0,
        vcHistBuckets = {},
        vcHistMaxCount = 0,
        deRow = nil,
        deOutcomeRows = {},
        deOutcomeUsed = 0,
        allAhCard = nil,
        allAhFilter = "faction8",
        allAhSortCol = "min",
        allAhSortAsc = true,
        allAhData = nil,
        allAhRows = {},
        allAhUsedCount = 0,
        dirtyThemeRender = false,
        qlDualCache = nil,
        chartsRow = nil,
        chart24h = nil,
        chart7d = nil,
        baselineCard = nil,
        chartsCollapsed = true,
        charts24Pts = 0,
        charts7dPts = 0,
    }

    local function daTheme()
        local h = H() or host
        return h and h.Theme or nil
    end

    local function hasSnapshotUI()
        local h = H() or host
        if not h then return false end
        if h.HasSnapshots and h.HasSnapshots() then return true end
        if h.app and h.app.snapshotExtension ~= nil then return true end
        return false
    end

    local function daPal()
        local T = daTheme()
        if T and T.GetActivePalette then
            local p = T.GetActivePalette()
            if type(p) == "table" then return p end
        end
        return getPalette()
    end

    local function daHex(pal, key, fallbackKey)
        local v = pal and (pal[key] or (fallbackKey and pal[fallbackKey]) or pal.hexText)
        return "|cff" .. tostring(v or "ffffff")
    end

    local function daMoney(copper, signed)
        if not readable(copper) or copper == nil then return "-" end
        local n = tonumber(copper)
        if not n then return "-" end
        local T = daTheme()
        if T and T.FormatMoneyParts then
            local parts = T.FormatMoneyParts(n, signed, true)
            if type(parts) == "table" and parts.text then return parts.text end
        end
        local h = H() or host
        if h and h.FormatMoneyCompact then
            local s = h.FormatMoneyCompact(math.abs(n))
            if signed then
                local pal = daPal()
                if n > 0 then return daHex(pal, "hexGreen") .. "+|r" .. s
                elseif n < 0 then return daHex(pal, "hexRed") .. "-|r" .. s end
            elseif n < 0 then
                local pal = daPal()
                return daHex(pal, "hexRed") .. "-|r" .. s
            end
            return s
        end
        return formatMoneyApple(n, signed)
    end

    local function daNum(v)
        local n = tonumber(v)
        if not n then return "-" end
        return groupThousands(math.floor(n + 0.5))
    end

    local function daRate(v)
        local n = tonumber(v)
        if not n then return "-" end
        local T = daTheme()
        if T and T.FormatSalesPerDay then return T.FormatSalesPerDay(n) end
        if n >= 10 then return string.format("%.0f/d", n) end
        if n >= 1 then return string.format("%.1f/d", n) end
        return string.format("%.2f/d", n)
    end

    local function daPct(v, showPlus)
        local n = tonumber(v)
        if not n then return "-" end
        if showPlus then return string.format("%+.1f%%", n) end
        return string.format("%.1f%%", n)
    end

    local function stripCodes(str)
        if type(str) ~= "string" then return "" end
        local s = str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
        return s
    end

    local function truncateText(str, maxLen)
        local s = stripCodes(tostring(str or ""))
        if #s <= maxLen then return s end
        return s:sub(1, math.max(1, maxLen - 3)) .. "..."
    end

    local function makeCard(parent, kind, fillKey, strokeKey)
        local f = CreateFrame("Frame", nil, parent)
        local T = daTheme()
        if T and T.NineApple then
            f._daSurf = T.NineApple(f, kind or "glass_r10", fillKey or "cardBg", strokeKey or "border", { noSpecular = true })
        else
            local pal = daPal()
            applySurface(f, kind or "glass_r10", pal[fillKey or "cardBg"] or pal.cardBg, pal[strokeKey or "border"] or pal.border)
        end
        return f
    end

    local function makeFs(parent, size, weight, justify, colorKey)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        applyFont(fs, size or 11, weight or "regular")
        fs:SetJustifyH(justify or "LEFT")
        if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
        local pal = daPal()
        setTextColor(fs, pal[colorKey or "text"] or pal.text)
        fs._daColorKey = colorKey or "text"
        fs._daFontSize = size or 11
        fs._daFontWeight = weight or "regular"
        return fs
    end

    local function showItemTooltip(owner, itemID)
        local id = tonumber(itemID)
        if not id or id <= 0 or not _G.GameTooltip then return end
        local tip = _G.GameTooltip
        tip:SetOwner(owner, "ANCHOR_RIGHT")
        if tip.SetItemByID then
            tip:SetItemByID(id)
        elseif tip.SetHyperlink then
            tip:SetHyperlink("item:" .. tostring(id))
        end
        local h = H() or host
        if h and h.AppendCrateTooltip then h.AppendCrateTooltip(tip, id) end
        local T = daTheme()
        if T and T.LiftTooltip then T.LiftTooltip(tip) end
        tip:Show()
    end

    local function hideTooltip()
        if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
    end

    local function getActiveEcon()
        local h = H() or host
        if h and h.CurrentEconomyInfo then
            local info = h.CurrentEconomyInfo()
            if type(info) == "table" then return info.effectiveKey, info end
        end
        return nil, nil
    end

    local function getOwnedTotal(itemID)
        local id = tonumber(itemID)
        if not id or id <= 0 then return 0 end
        if _G.MerchantMasterAPI and _G.MerchantMasterAPI.GetOwnedCountByID then
            return tonumber(_G.MerchantMasterAPI.GetOwnedCountByID(id)) or 0
        end
        return 0
    end

    local function getTargetItemID(target)
        if type(target) ~= "table" then return nil end
        local r = target.row
        local rec = target.recipe or (r and r.recipe)
        return tonumber(target.itemID
            or (r and (r.outputItemID or r.writID or r.crateID or r.itemID))
            or (rec and rec.outputItemID))
    end

    local function getTargetTitle(target, data)
        local h = H() or host
        local id = getTargetItemID(target)
        local r = target and target.row
        if data and data.title and data.title ~= "" then return data.title end
        if r and (r.name or r.writFullName or r.crateFullName or r.crateName) then
            return r.name or r.writFullName or r.crateFullName or r.crateName
        end
        if target and target.name and target.name ~= "" then return target.name end
        if id and h and h.ItemName then return h.ItemName(id) end
        return id and ("Item " .. tostring(id)) or "Deep Analysis"
    end

    local function getTargetIcon(target, data)
        local h = H() or host
        local id = getTargetItemID(target)
        local r = target and target.row
        local ic = (data and data.icon) or (r and (r.icon or r.crateIcon)) or (target and target.icon)
        if not ic and id and h and h.ItemIcon then ic = h.ItemIcon(id) end
        return ic or (h and h.QUESTION_ICON) or 134400
    end

    local function resolveDemandRate(md)
        if type(md) ~= "table" then return nil end
        if md.effectiveDailySold ~= nil then return tonumber(md.effectiveDailySold) end
        if md.dailySold ~= nil then return tonumber(md.dailySold) end
        return tonumber(md.snapDailySold or md.localClearsPerDay or md.personalDailySold)
    end

    local function resolveDemandSource(md)
        if type(md) ~= "table" then return nil end
        return md.demandSource or md.source or nil
    end

    local function buildItemDeepData(target, itemID, econKey)
        local h = H() or host
        local win = (db().quickLookWindow == "24h") and "24h" or "7d"
        local livePrice = (h and h.GetItemMarketPrice and h.GetItemMarketPrice(itemID)) or nil
        local snapPrice, snapRec = nil, nil
        if h and h.QueryLocalSnapshot then
            snapPrice, snapRec = h.QueryLocalSnapshot(itemID, econKey)
        end
        if not livePrice then livePrice = snapPrice end
        local vendorSell = (h and h.GetVendorSellPrice and h.GetVendorSellPrice(itemID)) or nil
        local dep24 = (h and h.GetAHListingDeposit and h.GetAHListingDeposit(itemID, 2, 1)) or nil
        local listed = (h and h.GetNumListed and h.GetNumListed(itemID))
            or (snapRec and (snapRec.numAuctions or snapRec.quantity or snapRec.qty)) or nil
        local md = (h and h.GetMultiSourceDemand and h.GetMultiSourceDemand(itemID, econKey)) or nil
        local salesPerDay = resolveDemandRate(md)
        local demandSrc = resolveDemandSource(md)
        local demandInfo = (h and h.EvaluateMarketDemand and h.EvaluateMarketDemand(listed, salesPerDay, true)) or nil
        local hm = (h and h.Pricing and h.Pricing.GetItemHeatmap and h.Pricing.GetItemHeatmap(itemID, econKey)) or nil
        local overall = hm and hm.overall or nil
        local name = (target and target.name) or (h and h.ItemName and h.ItemName(itemID)) or ("Item " .. tostring(itemID))
        local icon = (target and target.icon) or (h and h.ItemIcon and h.ItemIcon(itemID)) or (h and h.QUESTION_ICON) or 134400

        -- Build fallback output series from heatmap hourly averages if present so fallback chart has points
        local seriesVals, seriesCount = {}, 0
        if hm and hm.hourly then
            for hr = 0, 23 do
                local hv = hm.hourly[hr]
                if hv and hv.avgPrice and hv.avgPrice > 0 then
                    seriesVals[hr + 1] = hv.avgPrice
                    seriesCount = seriesCount + 1
                end
            end
        elseif livePrice and livePrice > 0 then
            seriesVals[1] = livePrice
            seriesCount = 1
        end
        local outputSeries = {
            values = seriesVals,
            count = seriesCount,
            last = livePrice or (overall and overall.avgPrice) or nil,
            pct = nil,
            days = seriesCount,
        }

        local wowheadURL, wowheadCA = nil, nil
        if h and h.GetRecipeWowheadURL then
            local url, label, kind = h.GetRecipeWowheadURL({ itemID = itemID, name = name })
            if url then
                wowheadURL = url
                wowheadCA = { wowheadURL = url, wowheadLabel = label or name, wowheadKind = kind or "item", recipeName = name }
            end
        end

        local hasSnaps = hasSnapshotUI()
        local overviewRows = {
            { key = "sellPrice", label = "Market price", qtyText = "1x", liveValue = livePrice, valueKind = "money", series = outputSeries, lowerIsBetter = false },
            hasSnaps
                and { key = "snapValue", label = "Snapshot market value", qtyText = "Snap", liveValue = (snapRec and snapRec.marketValue) or (overall and overall.avgPrice) or snapPrice, valueKind = "money", fixed = true }
                or  { key = "liveAvg", label = "Live AH history", qtyText = win, liveValue = outputSeries.last, valueKind = "money", series = outputSeries, lowerIsBetter = false },
            { key = "vendorFloor", label = "Vendor sell floor", qtyText = "Vendor", liveValue = vendorSell, valueKind = "money", fixed = true },
            { key = "deposit24", label = "24h AH deposit", qtyText = "24h", liveValue = dep24, valueKind = "money", fixed = true },
            { key = "salesPerDay", label = "Sales per day", qtyText = "1d", liveValue = salesPerDay, valueKind = "rate", salesSource = demandSrc },
            { key = "ahListed", label = "AH listed", qtyText = "AH", liveValue = listed, valueKind = "int", lowerIsBetter = true },
        }

        -- Find recipes crafting or consuming this item
        local linkedRecipes = {}
        local seenRec = {}
        for _, rec in ipairs((h and h.RECIPES) or {}) do
            if not seenRec[rec] then
                if rec.outputItemID == itemID then
                    seenRec[rec] = true
                    linkedRecipes[#linkedRecipes + 1] = { recipe = rec, role = "Crafts", qty = rec.numMade or 1 }
                else
                    for _, rg in ipairs(rec.reagents or {}) do
                        local rid = rg.itemID or rg.id or rg[1]
                        if rid == itemID then
                            seenRec[rec] = true
                            linkedRecipes[#linkedRecipes + 1] = { recipe = rec, role = "Used in", qty = rg.qty or rg[2] or 1 }
                            break
                        end
                    end
                end
                if #linkedRecipes >= 12 then break end
            end
        end

        return {
            kind = "item",
            itemID = itemID,
            title = name,
            icon = icon,
            window = win,
            output = outputSeries,
            liveListed = listed,
            liveSalesPerDay = salesPerDay,
            salesSource = demandSrc,
            demandInfo = demandInfo,
            marketDemand = md,
            snapPrice = snapPrice,
            snapRec = snapRec,
            vendorSell = vendorSell,
            dep24 = dep24,
            overviewRows = overviewRows,
            movers = {},
            linkedRecipes = linkedRecipes,
            sourceInfo = { wowheadURL = wowheadURL, wowheadCA = wowheadCA },
        }
    end

    local function updateScrollMetrics()
        if not state.built or not state.scrollFrame or not state.scrollChild then return end
        local vpH = math.max(120, state.viewportH - 64)
        local maxScroll = math.max(0, state.contentH - vpH)
        state.scrollOffset = math.max(0, math.min(state.scrollOffset or 0, maxScroll))
        state.scrollChild:SetHeight(math.max(state.contentH, vpH))
        if state.scrollFrame.SetVerticalScroll then
            state.scrollFrame:SetVerticalScroll(state.scrollOffset)
        end
        if state.scrollFrame.UpdateScrollChildRect then
            state.scrollFrame:UpdateScrollChildRect()
        end
        local bar = state.scrollBar
        if bar then
            if maxScroll > 1 then
                if bar.SetMinMaxValues then bar:SetMinMaxValues(0, maxScroll) end
                if bar.SetValue then bar:SetValue(state.scrollOffset) end
                bar:Show()
            else
                if bar.SetMinMaxValues then bar:SetMinMaxValues(0, 0) end
                if bar.SetValue then bar:SetValue(0) end
                bar:Hide()
            end
        end
    end

    local function setScrollOffset(v)
        local vpH = math.max(120, state.viewportH - 64)
        local maxScroll = math.max(0, state.contentH - vpH)
        state.scrollOffset = math.max(0, math.min(tonumber(v) or 0, maxScroll))
        if state.scrollFrame and state.scrollFrame.SetVerticalScroll then
            state.scrollFrame:SetVerticalScroll(state.scrollOffset)
        end
        if state.scrollBar and state.scrollBar.SetValue then
            state.scrollBar:SetValue(state.scrollOffset)
        end
    end

    local function ensureReagentRow(index)
        if state.reagentRows[index] then return state.reagentRows[index] end
        local parent = state.leftCard
        local btn = CreateFrame("Button", nil, parent)
        btn:SetHeight(26)
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp")
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints(btn)
        btn.bg:Hide()
        btn.sep = btn:CreateTexture(nil, "BORDER")
        btn.sep:SetPoint("TOPLEFT", 4, 0)
        btn.sep:SetPoint("TOPRIGHT", -4, 0)
        btn.sep:SetHeight(1)
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(18, 18)
        btn.icon:SetPoint("LEFT", 6, 0)
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.nameFs = makeFs(btn, 11, "semibold", "LEFT", "text")
        if btn.nameFs.SetWordWrap then btn.nameFs:SetWordWrap(false) end
        btn.qtyFs = makeFs(btn, 11, "regular", "RIGHT", "textSecondary")
        btn.unitFs = makeFs(btn, 11, "regular", "RIGHT", "text")
        btn.extFs = makeFs(btn, 11, "semibold", "RIGHT", "text")
        btn.tagFs = makeFs(btn, 10, "semibold", "RIGHT", "textMuted")
        btn.stockFs = makeFs(btn, 10, "regular", "RIGHT", "textSecondary")
        btn.shareTrack = btn:CreateTexture(nil, "BORDER")
        btn.shareTrack:SetHeight(3)
        btn.shareTrack:Hide()
        btn.shareFill = btn:CreateTexture(nil, "ARTWORK")
        btn.shareFill:SetHeight(3)
        btn.shareFill:Hide()
        btn._hasShareBar = false
        btn._shareRatio = nil
        btn._shareColorKey = "accentBlue"

        btn:SetScript("OnEnter", function(self)
            local pal = daPal()
            if self.clickable and self.bg then
                local hc = pal.cardHover or { 1, 1, 1, 0.06 }
                self.bg:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 0.08)
                self.bg:Show()
            end
            if self.itemID and self.itemID > 0 then
                showItemTooltip(self, self.itemID)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self.bg then self.bg:Hide() end
            hideTooltip()
        end)
        btn:SetScript("OnClick", function(self)
            local a = app()
            if not (a and a.openDeepAnalysis) then return end
            if self.drillRecipe then
                a.openDeepAnalysis({ kind = "recipe", recipe = self.drillRecipe })
            elseif self.clickable and self.itemID and self.itemID > 0 then
                a.openDeepAnalysis({ kind = "item", itemID = self.itemID, name = self.itemName, icon = self.itemIcon })
            end
        end)
        btn:Hide()
        state.reagentRows[index] = btn
        return btn
    end

    local function ensureVcCapRow(index)
        if state.vcCapRows[index] then return state.vcCapRows[index] end
        local parent = state.vcCard
        local btn = CreateFrame("Button", nil, parent)
        btn:SetHeight(24)
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp")
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints(btn)
        btn.bg:Hide()
        btn.sep = btn:CreateTexture(nil, "BORDER")
        btn.sep:SetPoint("TOPLEFT", 2, 0)
        btn.sep:SetPoint("TOPRIGHT", -2, 0)
        btn.sep:SetHeight(1)
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(16, 16)
        btn.icon:SetPoint("LEFT", 4, 0)
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.nameFs = makeFs(btn, 10, "semibold", "LEFT", "text")
        if btn.nameFs.SetWordWrap then btn.nameFs:SetWordWrap(false) end
        btn.capFs = makeFs(btn, 10, "regular", "RIGHT", "text")
        if btn.capFs.SetWordWrap then btn.capFs:SetWordWrap(false) end
        btn.statusFs = makeFs(btn, 10, "semibold", "RIGHT", "accentGreen")
        if btn.statusFs.SetWordWrap then btn.statusFs:SetWordWrap(false) end

        btn:SetScript("OnEnter", function(self)
            local pal = daPal()
            if self.clickable and self.bg then
                local hc = pal.cardHover or { 1, 1, 1, 0.06 }
                self.bg:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 0.08)
                self.bg:Show()
            end
            if self.itemID and self.itemID > 0 then
                showItemTooltip(self, self.itemID)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self.bg then self.bg:Hide() end
            hideTooltip()
        end)
        btn:SetScript("OnClick", function(self)
            local a = app()
            if a and a.openDeepAnalysis and self.clickable and self.itemID and self.itemID > 0 then
                a.openDeepAnalysis({ kind = "item", itemID = self.itemID, name = self.itemName, icon = self.itemIcon })
            end
        end)
        btn:Hide()
        state.vcCapRows[index] = btn
        return btn
    end

    local function ensureDeOutcomeRow(index)
        if state.deOutcomeRows[index] then return state.deOutcomeRows[index] end
        local parent = state.deCard
        local btn = CreateFrame("Button", nil, parent)
        btn:SetHeight(24)
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp")
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints(btn)
        btn.bg:Hide()
        btn.sep = btn:CreateTexture(nil, "BORDER")
        btn.sep:SetPoint("TOPLEFT", 2, 0)
        btn.sep:SetPoint("TOPRIGHT", -2, 0)
        btn.sep:SetHeight(1)
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(16, 16)
        btn.icon:SetPoint("LEFT", 4, 0)
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.nameFs = makeFs(btn, 10, "semibold", "LEFT", "textBlue")
        if btn.nameFs.SetWordWrap then btn.nameFs:SetWordWrap(false) end
        btn.chanceFs = makeFs(btn, 10, "regular", "RIGHT", "textSecondary")
        if btn.chanceFs.SetWordWrap then btn.chanceFs:SetWordWrap(false) end
        btn.unitFs = makeFs(btn, 10, "regular", "RIGHT", "text")
        if btn.unitFs.SetWordWrap then btn.unitFs:SetWordWrap(false) end
        btn.evFs = makeFs(btn, 10, "semibold", "RIGHT", "text")
        if btn.evFs.SetWordWrap then btn.evFs:SetWordWrap(false) end

        btn:SetScript("OnEnter", function(self)
            local pal = daPal()
            if self.clickable and self.bg then
                local hc = pal.cardHover or { 1, 1, 1, 0.06 }
                self.bg:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 0.08)
                self.bg:Show()
            end
            if self.itemID and self.itemID > 0 then
                showItemTooltip(self, self.itemID)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self.bg then self.bg:Hide() end
            hideTooltip()
        end)
        btn:SetScript("OnClick", function(self)
            local a = app()
            if a and a.openDeepAnalysis and self.clickable and self.itemID and self.itemID > 0 then
                a.openDeepAnalysis({ kind = "item", itemID = self.itemID, name = self.itemName, icon = self.itemIcon })
            end
        end)
        btn:Hide()
        state.deOutcomeRows[index] = btn
        return btn
    end

    local ALL_AH_FILTERS = {
        { key = "faction8", label = "Faction", width = 62 },
        { key = "all", label = "All", width = 42 },
        { key = "Horde", label = "Horde", width = 54 },
        { key = "Alliance", label = "Alliance", width = 64 },
        { key = "Blackwater", label = "Blackwater", width = 78 },
    }

    local ALL_AH_COLS = {
        { key = "label", label = "AUCTION HOUSE", align = "LEFT" },
        { key = "min", label = "MIN BUYOUT", align = "RIGHT" },
        { key = "mkt", label = "MARKET", align = "RIGHT" },
        { key = "diff", label = "VS HOME", align = "RIGHT" },
        { key = "qty", label = "QTY", align = "RIGHT" },
    }

    local function ensureAllAhRow(index)
        if state.allAhRows[index] then return state.allAhRows[index] end
        local parent = state.allAhCard
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(24)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:Hide()
        row.sep = row:CreateTexture(nil, "BORDER")
        row.sep:SetPoint("TOPLEFT", 0, 0)
        row.sep:SetPoint("TOPRIGHT", 0, 0)
        row.sep:SetHeight(1)
        row.nameFs = makeFs(row, 11, "semibold", "LEFT", "text")
        if row.nameFs.SetWordWrap then row.nameFs:SetWordWrap(false) end
        row.minFs = makeFs(row, 11, "semibold", "RIGHT", "text")
        if row.minFs.SetWordWrap then row.minFs:SetWordWrap(false) end
        row.mktFs = makeFs(row, 11, "regular", "RIGHT", "textSecondary")
        if row.mktFs.SetWordWrap then row.mktFs:SetWordWrap(false) end
        row.diffFs = makeFs(row, 11, "semibold", "RIGHT", "textMuted")
        if row.diffFs.SetWordWrap then row.diffFs:SetWordWrap(false) end
        row.barTrack = row:CreateTexture(nil, "BORDER")
        row.barTrack:SetSize(64, 5)
        row.barFill = row:CreateTexture(nil, "ARTWORK")
        row.barFill:SetSize(4, 5)
        row.qtyFs = makeFs(row, 11, "semibold", "RIGHT", "text")
        if row.qtyFs.SetWordWrap then row.qtyFs:SetWordWrap(false) end
        row:Hide()
        state.allAhRows[index] = row
        return row
    end

    local function paintAllAhRows()
        local allAh = state.allAhCard
        local ahData = state.allAhData
        if not allAh or not ahData then
            state.allAhUsedCount = 0
            return
        end
        local pal = daPal()
        local sep = pal.separator or pal.border or { 1, 1, 1, 0.14 }
        local barCol = pal.accentBlue or { 0.0, 0.57, 1.0, 1.0 }
        local trackCol = { sep[1], sep[2], sep[3], (sep[4] or 0.4) * 0.55 }
        local homeBgCol = pal.cardHover or { barCol[1], barCol[2], barCol[3], 0.12 }

        for _, spec in ipairs(ALL_AH_FILTERS) do
            local btn = allAh.filterBtns and allAh.filterBtns[spec.key]
            if btn and btn.SetActive then
                btn:SetActive(state.allAhFilter == spec.key)
            end
        end

        for i, cs in ipairs(ALL_AH_COLS) do
            local cbtn = allAh.colBtns and allAh.colBtns[i]
            if cbtn and cbtn.fs then
                local ind = ""
                if state.allAhSortCol == cs.key then
                    ind = state.allAhSortAsc and " ^" or " v"
                end
                cbtn.fs:SetText(cs.label .. ind)
                setTextColor(cbtn.fs, (state.allAhSortCol == cs.key) and pal.text or pal.textMuted)
            end
        end

        local filtered = {}
        local fKey = state.allAhFilter or "faction8"
        for _, r in ipairs(ahData.rows or {}) do
            if fKey == "all" then
                filtered[#filtered + 1] = r
            elseif fKey == "faction8" then
                if r.faction ~= "Blackwater" then
                    filtered[#filtered + 1] = r
                end
            elseif r.faction == fKey then
                filtered[#filtered + 1] = r
            end
        end

        local sCol = state.allAhSortCol or "min"
        local sAsc = (state.allAhSortAsc ~= false)
        table.sort(filtered, function(a, b)
            if sCol == "label" then
                if sAsc then return a.economy < b.economy end
                return a.economy > b.economy
            end
            if sCol == "qty" then
                if a.qty ~= b.qty then
                    if sAsc then return a.qty < b.qty end
                    return a.qty > b.qty
                end
                return a.economy < b.economy
            end
            local va = (sCol == "min" and a.minBuyout) or (sCol == "mkt" and a.marketValue) or (sCol == "diff" and a.diffPct) or nil
            local vb = (sCol == "min" and b.minBuyout) or (sCol == "mkt" and b.marketValue) or (sCol == "diff" and b.diffPct) or nil
            local aMissing = (va == nil)
            local bMissing = (vb == nil)
            if aMissing ~= bMissing then return not aMissing end
            if not aMissing and va ~= vb then
                if sAsc then return va < vb end
                return va > vb
            end
            return a.economy < b.economy
        end)

        local maxQty = 1
        for _, r in ipairs(filtered) do
            if (r.qty or 0) > maxQty then maxQty = r.qty end
        end

        local used = 0
        for _, r in ipairs(filtered) do
            used = used + 1
            local row = ensureAllAhRow(used)
            row._isHome = r.isHome == true
            row._qtyRatio = (r.listed and r.qty > 0) and math.max(0.04, math.min(1, r.qty / maxQty)) or 0
            row.nameFs:SetText(r.economy .. (r.isHome and "  [HOME]" or ""))
            row.minFs:SetText(r.listed and daMoney(r.minBuyout, false) or "-")
            row.mktFs:SetText((r.listed and r.marketValue) and daMoney(r.marketValue, false) or "-")
            local diffTxt, diffColKey = "-", "textMuted"
            if r.isHome and r.listed then
                diffTxt = "Home"
                diffColKey = "textMuted"
            elseif r.diffPct ~= nil then
                diffTxt = (math.abs(r.diffPct) < 0.05) and "0.0%" or string.format("%+.1f%%", r.diffPct)
                if r.diffPct < -0.05 then
                    diffColKey = "accentGreen"
                elseif r.diffPct > 0.05 then
                    diffColKey = "accentRed"
                end
            end
            row._diffColKey = diffColKey
            row.diffFs:SetText(diffTxt)
            row.qtyFs:SetText(r.listed and daNum(r.qty) or "0")

            setTextColor(row.nameFs, pal.text)
            setTextColor(row.minFs, r.listed and pal.text or pal.textMuted)
            setTextColor(row.mktFs, (r.listed and r.marketValue) and pal.textSecondary or pal.textMuted)
            setTextColor(row.diffFs, pal[diffColKey] or pal.textMuted)
            setTextColor(row.qtyFs, r.listed and pal.text or pal.textMuted)
            row.sep:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.4) * 0.55)
            row.barTrack:SetColorTexture(trackCol[1], trackCol[2], trackCol[3], trackCol[4])
            row.barFill:SetColorTexture(barCol[1], barCol[2], barCol[3], barCol[4] or 0.85)
            if r.isHome then
                row.bg:SetColorTexture(homeBgCol[1], homeBgCol[2], homeBgCol[3], math.min(0.28, homeBgCol[4] or 0.14))
                row.bg:Show()
            else
                row.bg:Hide()
            end
            row:Show()
        end
        state.allAhUsedCount = used
        for i = used + 1, #state.allAhRows do
            state.allAhRows[i]:Hide()
        end
        if allAh.emptyFs then
            allAh.emptyFs:SetShown(used == 0)
        end
    end

    local function renderAllAhCard(itemID, econKey)
        local allAh = state.allAhCard
        if not allAh then return end
        if not hasSnapshotUI() then
            state.allAhData = nil
            state.allAhUsedCount = 0
            allAh:Hide()
            return
        end
        local h = H() or host
        local fn = h and h.Pricing and h.Pricing.GetAllAuctionHousesForItem
        local ahData = (itemID and itemID > 0 and fn) and fn(itemID, econKey) or nil
        if not ahData or (ahData.totalHouses or 0) == 0 then
            state.allAhData = nil
            state.allAhUsedCount = 0
            allAh:Hide()
            return
        end
        state.allAhData = ahData
        local parts = {
            string.format("Listed %d/%d", ahData.listedHouses or 0, ahData.totalHouses or 0),
        }
        if ahData.lowest then
            parts[#parts + 1] = "Low " .. daMoney(ahData.lowest.minBuyout, false) .. " (" .. tostring(ahData.lowest.economy) .. ")"
        end
        if ahData.highest then
            parts[#parts + 1] = "High " .. daMoney(ahData.highest.minBuyout, false) .. " (" .. tostring(ahData.highest.economy) .. ")"
        end
        parts[#parts + 1] = "Total " .. daNum(ahData.totalQty or 0) .. " units"
        allAh.summaryFs:SetText(table.concat(parts, "  ·  "))
        paintAllAhRows()
        allAh:Show()
    end

    local function isTargetWatchlisted(target)
        local h = H() or host
        local wl = h and h.Watchlist
        if not wl or not target then return false end
        if type(wl.IsFavorite) == "function" then
            local ok, res = pcall(wl.IsFavorite, target)
            if ok then return res and true or false end
        elseif type(wl.IsWatched) == "function" then
            local ok, res = pcall(wl.IsWatched, target)
            if ok then return res and true or false end
        elseif type(wl.Has) == "function" then
            local ok, res = pcall(wl.Has, target)
            if ok then return res and true or false end
        elseif type(wl.Contains) == "function" then
            local ok, res = pcall(wl.Contains, target)
            if ok then return res and true or false end
        end
        return false
    end

    local function syncFavButton()
        local btn = state.header and state.header.favBtn
        if not btn then return end
        local h = H() or host
        local wl = h and h.Watchlist
        if wl and type(wl.RegisterListener) == "function" and not state._wlListenerBound then
            state._wlListenerBound = true
            pcall(wl.RegisterListener, function()
                if state.built and state.header and state.header.favBtn then
                    syncFavButton()
                end
            end)
        end
        local pal = daPal()
        local watched = isTargetWatchlisted(state.target)
        btn._watched = watched
        local ic = btn._mmIcon
        if ic and ic.SetVertexColor then
            if watched then
                ic:SetVertexColor(1.0, 0.82, 0.18, 1.0)
            else
                local mc = pal.textMuted or { 0.6, 0.6, 0.62, 1.0 }
                ic:SetVertexColor(mc[1], mc[2], mc[3], mc[4] or 1.0)
            end
        end
    end

    local function countMaxPoints(seriesList)
        local best = 0
        for _, s in ipairs(seriesList or {}) do
            local pts = s and (s.points or s.data)
            if type(pts) == "table" and #pts > best then
                best = #pts
            end
        end
        return best
    end

    local function extractDualChartSeries(ql)
        local Chart = ns.Chart
        if type(ql) ~= "table" or not (Chart and Chart.BuildQuickLookSeries) then return nil end
        local all = Chart.BuildQuickLookSeries(ql)
        if type(all) ~= "table" or #all == 0 then return nil end
        local out = {}
        for _, s in ipairs(all) do
            if s.name == "Sell Price" or s.name == "Craft Cost" then
                out[#out + 1] = s
            end
        end
        if #out == 0 then
            out[#out + 1] = all[1]
        end
        return out
    end

    local function buildItemChartSeries(itemID, econKey)
        local h = H() or host
        local ms = h and h.MarketScan
        local dateFn = _G.date or (os and os.date)
        local pts24, pct24 = {}, nil
        local pts7d, pct7d = {}, nil

        if itemID and itemID > 0 then
            -- 24h series: prefer MarketScan.GetItemTrend24h, fallback to Pricing hourly / ReadHistory
            if ms and type(ms.GetItemTrend24h) == "function" then
                local ok, t24 = pcall(ms.GetItemTrend24h, itemID, econKey)
                if ok and type(t24) == "table" and type(t24.points) == "table" then
                    pct24 = tonumber(t24.trendPct)
                    for _, pt in ipairs(t24.points) do
                        local p = tonumber(pt.price)
                        if p and p > 0 then
                            local ts = tonumber(pt.at) or ((tonumber(pt.h) or 0) * 3600)
                            local dayKey = dateFn and dateFn("!%Y-%m-%d %H:00", ts) or string.format("H%d", #pts24 + 1)
                            local lbl = dateFn and dateFn("!%H:00", ts) or dayKey
                            pts24[#pts24 + 1] = { day = dayKey, label = lbl, value = p, sortKey = ts }
                        end
                    end
                end
            end
            if #pts24 < 2 and h and h.Pricing then
                local strip = type(h.Pricing.GetItemHeatStrip24h) == "function" and h.Pricing.GetItemHeatStrip24h(itemID, econKey) or nil
                local hm = (not strip or not strip.hourly) and type(h.Pricing.GetItemHeatmap) == "function" and h.Pricing.GetItemHeatmap(itemID, econKey) or nil
                local hourly = (strip and strip.hourly) or (hm and hm.hourly)
                if type(hourly) == "table" then
                    pts24 = {}
                    for hr = 0, 23 do
                        local rec = hourly[hr]
                        local p = type(rec) == "table" and tonumber(rec.avgPrice) or tonumber(rec)
                        if p and p > 0 then
                            local lbl = string.format("%02d:00", hr)
                            pts24[#pts24 + 1] = { day = lbl, label = lbl, value = p, sortKey = hr }
                        end
                    end
                end
            end
            if #pts24 < 2 and ms and type(ms.ReadHistory) == "function" then
                local raw = db().ahHistory and db().ahHistory[econKey] and db().ahHistory[econKey][itemID]
                local ring = raw and ms.ReadHistory(raw) or nil
                if type(ring) == "table" then
                    local now = (time and time()) or 0
                    local cutoff = now - 86400
                    pts24 = {}
                    for _, e in ipairs(ring) do
                        local ts = type(e) == "table" and tonumber(e.t)
                        local p = type(e) == "table" and tonumber(e.p)
                        if ts and p and p > 0 and (now == 0 or ts >= cutoff) then
                            local dayKey = dateFn and dateFn("!%Y-%m-%d %H:00", ts) or string.format("H%d", #pts24 + 1)
                            local lbl = dateFn and dateFn("!%H:00", ts) or dayKey
                            pts24[#pts24 + 1] = { day = dayKey, label = lbl, value = p, sortKey = ts }
                        end
                    end
                end
            end

            -- 7d series: prefer MarketScan.GetItemTrend7d, fallback to ReadDaily
            if ms and type(ms.GetItemTrend7d) == "function" then
                local ok, t7 = pcall(ms.GetItemTrend7d, itemID, econKey)
                if ok and type(t7) == "table" and type(t7.points) == "table" then
                    pct7d = tonumber(t7.trendPct)
                    for _, pt in ipairs(t7.points) do
                        local p = tonumber(pt.price)
                        local d = tonumber(pt.d)
                        if p and p > 0 and d then
                            local ts = d * 86400
                            local dayKey = dateFn and dateFn("!%Y-%m-%d", ts) or ("D" .. tostring(d))
                            pts7d[#pts7d + 1] = { day = dayKey, label = dayKey, value = p, sortKey = d }
                        end
                    end
                end
            end
            if #pts7d < 2 and ms and type(ms.ReadDaily) == "function" then
                local raw = db().ahDaily and db().ahDaily[econKey] and db().ahDaily[econKey][itemID]
                local buckets = raw and ms.ReadDaily(raw) or nil
                if type(buckets) == "table" then
                    pts7d = {}
                    for _, b in ipairs(buckets) do
                        local d = type(b) == "table" and tonumber(b.d)
                        local p = type(b) == "table" and (tonumber(b.lastP) or tonumber(b.obsP))
                        if d and p and p > 0 then
                            local ts = d * 86400
                            local dayKey = dateFn and dateFn("!%Y-%m-%d", ts) or ("D" .. tostring(d))
                            pts7d[#pts7d + 1] = { day = dayKey, label = dayKey, value = p, sortKey = d }
                        end
                    end
                end
            end
        end

        local s24 = (#pts24 >= 2) and { { name = "Market Price", colorKey = "blue", points = pts24 } } or {}
        local s7d = (#pts7d >= 2) and { { name = "Market Price", colorKey = "blue", points = pts7d } } or {}
        return s24, pct24, s7d, pct7d
    end

    local HEAT_TIERS = {
        { label = "Cold",     colorKey = "accentBlue" },
        { label = "Steady",   colorKey = "accentGreen" },
        { label = "Hot",      colorKey = "accentOrange" },
        { label = "Monopoly", colorKey = "accentPurple" },
    }

    local function resolveHeatTier(heatLabel, demandInfo, liveSales)
        local raw = tostring(heatLabel or ""):lower()
        if demandInfo and demandInfo.tier then
            local t = tostring(demandInfo.tier):lower()
            raw = raw .. " " .. t
        end
        if raw:find("monopoly", 1, true) or raw:find("dominat", 1, true) or raw:find("corner", 1, true) then
            return 4
        elseif raw:find("hot", 1, true) or raw:find("fast", 1, true) or raw:find("high", 1, true) or raw:find("strong", 1, true) or raw:find("booming", 1, true) then
            return 3
        elseif raw:find("steady", 1, true) or raw:find("moderate", 1, true) or raw:find("fair", 1, true) or raw:find("normal", 1, true) or raw:find("med", 1, true) then
            return 2
        elseif raw:find("cold", 1, true) or raw:find("slow", 1, true) or raw:find("dead", 1, true) or raw:find("low", 1, true) then
            return 1
        end
        local s = tonumber(liveSales) or 0
        if s >= 15 then return 3
        elseif s >= 2 then return 2 end
        return 1
    end

    local function paintVisualCards(pal)
        local sep = pal.separator or pal.border or { 1, 1, 1, 0.14 }
        local isLight = (pal.mode == "light")
        local trackAlpha = isLight and 0.14 or 0.16
        local trackCol = { sep[1], sep[2], sep[3], math.max(trackAlpha, (sep[4] or 0.4) * 0.55) }

        local function paintFsLocal(fs, overrideCol)
            if not fs then return end
            applyFont(fs, fs._daFontSize or 11, fs._daFontWeight or "regular")
            local col = overrideCol or pal[fs._daColorKey or "text"] or pal.text
            setTextColor(fs, col)
        end

        if state.baselineCard then
            paintFsLocal(state.baselineCard.titleFs, pal.textMuted)
            paintFsLocal(state.baselineCard.stripFs, pal.text)
            paintFsLocal(state.baselineCard.hintFs, pal.textSecondary)
        end

        local ec = state.leftCard and state.leftCard.econBarCard
        if ec then
            for _, slot in ipairs(ec.craftBars or {}) do
                paintFsLocal(slot.lblFs, pal.textSecondary)
                local col = (slot._colorKey and pal[slot._colorKey]) or pal.accentBlue
                paintFsLocal(slot.valFs, slot._valColorKey and pal[slot._valColorKey] or pal.text)
                if slot.trackTex then
                    slot.trackTex:SetColorTexture(trackCol[1], trackCol[2], trackCol[3], trackCol[4])
                end
                if slot.fillTex and col then
                    slot.fillTex:SetColorTexture(col[1], col[2], col[3], col[4] or 0.90)
                end
            end
            if ec.rangeTrack then
                ec.rangeTrack:SetColorTexture(trackCol[1], trackCol[2], trackCol[3], trackCol[4])
            end
            if ec.rangeSpan then
                local scCol = pal.accentBlue or { 0.0, 0.57, 1.0, 1.0 }
                ec.rangeSpan:SetColorTexture(scCol[1], scCol[2], scCol[3], isLight and 0.25 or 0.30)
            end
            for i, lbl in ipairs(ec.rangeLabels or {}) do
                paintFsLocal(lbl, i == 2 and pal.text or pal.textSecondary)
            end
            local mkKeys = ec._markerColorKeys or { "textMuted", "accentBlue", "accentOrange" }
            for i, mk in ipairs(ec.rangeMarkers or {}) do
                local col = pal[mkKeys[i]] or pal.accentBlue
                mk:SetColorTexture(col[1], col[2], col[3], 1.0)
            end
        end

        for _, r in ipairs(state.reagentRows or {}) do
            if r.shareTrack then
                r.shareTrack:SetColorTexture(trackCol[1], trackCol[2], trackCol[3], trackCol[4])
            end
            if r.shareFill then
                local col = pal[r._shareColorKey or "accentBlue"] or pal.accentBlue
                r.shareFill:SetColorTexture(col[1], col[2], col[3], col[4] or 0.85)
            end
        end

        local cc = state.compCard
        if cc and cc.heatTiers then
            local activeIdx = cc._activeTier or 1
            for i, tier in ipairs(cc.heatTiers) do
                local spec = HEAT_TIERS[i]
                local col = pal[spec.colorKey] or pal.accentBlue
                if i == activeIdx then
                    tier.bgTex:SetColorTexture(col[1], col[2], col[3], isLight and 0.20 or 0.26)
                    paintFsLocal(tier.lblFs, col)
                else
                    tier.bgTex:SetColorTexture(trackCol[1], trackCol[2], trackCol[3], isLight and 0.10 or 0.12)
                    paintFsLocal(tier.lblFs, pal.textMuted)
                end
            end
        end
        if cc and cc.heatStripFrame then
            local hsf = cc.heatStripFrame
            paintFsLocal(hsf.captionFs, pal.textSecondary)
            if hsf._mode == "snapshot" and hsf.strip24h and hsf._stripData then
                hsf.strip24h:Bind(hsf._stripData, pal, hsf._nowHour)
            elseif hsf.spectrumSegs then
                local stops = isLight and {
                    { 0.10, 0.45, 0.88 }, { 0.08, 0.56, 0.88 }, { 0.06, 0.65, 0.82 }, { 0.08, 0.68, 0.64 },
                    { 0.12, 0.68, 0.42 }, { 0.28, 0.70, 0.28 }, { 0.56, 0.70, 0.16 }, { 0.78, 0.64, 0.10 },
                    { 0.88, 0.54, 0.08 }, { 0.90, 0.40, 0.10 }, { 0.86, 0.26, 0.14 }, { 0.80, 0.16, 0.18 },
                } or {
                    { 0.18, 0.56, 0.96 }, { 0.14, 0.68, 0.94 }, { 0.14, 0.78, 0.88 }, { 0.16, 0.80, 0.70 },
                    { 0.20, 0.82, 0.48 }, { 0.40, 0.84, 0.32 }, { 0.68, 0.84, 0.22 }, { 0.90, 0.76, 0.16 },
                    { 0.96, 0.64, 0.16 }, { 0.98, 0.48, 0.14 }, { 0.96, 0.34, 0.18 }, { 0.94, 0.22, 0.24 },
                }
                local frac = math.max(0, math.min(1, tonumber(hsf._heatFrac) or 0.12))
                local activeSeg = math.max(1, math.min(#stops, math.floor(frac * #stops) + 1))
                for i, seg in ipairs(hsf.spectrumSegs) do
                    local c = stops[i] or stops[#stops]
                    local a = (i == activeSeg) and 1.0 or (isLight and 0.82 or 0.78)
                    seg:SetColorTexture(c[1], c[2], c[3], a)
                end
                if hsf.spectrumMarker then
                    if isLight then
                        hsf.spectrumMarker:SetColorTexture(0.08, 0.10, 0.14, 1.0)
                    else
                        hsf.spectrumMarker:SetColorTexture(1.0, 1.0, 1.0, 0.98)
                    end
                end
            end
        end

        local lc = state.ledgerCard
        if lc then
            paintFsLocal(lc.emptyTradesFs, pal.textMuted)
            for _, colFrame in ipairs(lc.horizonCols or {}) do
                local col = pal[colFrame._colorKey or "accentGreen"] or pal.accentGreen
                paintFsLocal(colFrame.valFs, colFrame._valColorKey and pal[colFrame._valColorKey] or pal.text)
                paintFsLocal(colFrame.lblFs, pal.textMuted)
                if colFrame.barTrack then
                    colFrame.barTrack:SetColorTexture(trackCol[1], trackCol[2], trackCol[3], trackCol[4])
                end
                if colFrame.barFill then
                    colFrame.barFill:SetColorTexture(col[1], col[2], col[3], col[4] or 0.88)
                end
            end
            if lc.saleRateRow then
                paintFsLocal(lc.saleRateRow.lblFs, pal.textSecondary)
                if lc.saleRateRow.fallbackTrack then
                    lc.saleRateRow.fallbackTrack:SetColorTexture(trackCol[1], trackCol[2], trackCol[3], trackCol[4])
                end
                if lc.saleRateRow.fallbackFill then
                    local fc = pal[lc.saleRateRow._colorKey or "accentGreen"] or pal.accentGreen
                    lc.saleRateRow.fallbackFill:SetColorTexture(fc[1], fc[2], fc[3], fc[4] or 0.90)
                end
                if lc.saleRateRow.bar and lc.saleRateRow.bar.SetColor then
                    local fc = pal[lc.saleRateRow._colorKey or "accentGreen"] or pal.accentGreen
                    lc.saleRateRow.bar:SetColor(fc)
                end
            end
            for _, chip in ipairs(lc.stockChips or {}) do
                local hasQty = (chip._qty or 0) > 0
                if hasQty then
                    local ac = pal.accentBlue or { 0.0, 0.57, 1.0, 1.0 }
                    chip.bgTex:SetColorTexture(ac[1], ac[2], ac[3], isLight and 0.14 or 0.20)
                    paintFsLocal(chip.lblFs, pal.text)
                else
                    chip.bgTex:SetColorTexture(trackCol[1], trackCol[2], trackCol[3], isLight and 0.10 or 0.12)
                    paintFsLocal(chip.lblFs, pal.textMuted)
                end
            end
        end
    end

    local function isRootVisible()
        if not state.root then return false end
        if state.root.IsShown and not state.root:IsShown() then return false end
        local p = state.root.GetParent and state.root:GetParent() or nil
        if p and p.IsShown and not p:IsShown() then return false end
        return true
    end

    local function applyTheme()
        if not state.built or not state.root then return end
        local pal = daPal()
        local sep = pal.separator or pal.border or { 1, 1, 1, 0.14 }

        local function paintFs(fs, overrideCol)
            if not fs then return end
            applyFont(fs, fs._daFontSize or 11, fs._daFontWeight or "regular")
            local col = overrideCol or pal[fs._daColorKey or "text"] or pal.text
            setTextColor(fs, col)
        end

        if state.header then
            paintFs(state.header.titleFs, pal.text)
            paintFs(state.header.subtitleFs, pal.textSecondary)
            syncFavButton()
        end
        for _, card in ipairs(state.kpiCards or {}) do
            paintFs(card.titleFs, pal.textMuted)
            paintFs(card.valueFs, card._valColorKey and pal[card._valColorKey] or pal.text)
            paintFs(card.subFs, pal.textSecondary)
        end
        if state.chart24h and state.chart24h.ApplyTheme then
            state.chart24h:ApplyTheme()
        end
        if state.chart7d and state.chart7d.ApplyTheme then
            state.chart7d:ApplyTheme()
        end
        if state.timingDrawer and state.timingDrawer.ApplyTheme then
            state.timingDrawer:ApplyTheme()
        end
        if state.timingPlaceholder then
            paintFs(state.timingPlaceholder.textFs, pal.textSecondary)
        end
        if state.vcCard then
            local vc = state.vcCard
            paintFs(vc.titleFs, pal.textMuted)
            paintFs(vc.badgeFs, vc._badgeColKey and pal[vc._badgeColKey] or pal.accentGreen or pal.text)
            paintFs(vc.spreadFs, pal.text)
            paintFs(vc.capHdrFs, pal.textMuted)
            paintFs(vc.capEmptyFs, pal.textMuted)
            paintFs(vc.histHdrFs, pal.textMuted)
            paintFs(vc.histMetaFs, pal.textSecondary)
            paintFs(vc.histEmptyFs, pal.textMuted)
            if vc.div then vc.div:SetColorTexture(sep[1], sep[2], sep[3], sep[4] or 0.4) end
            if vc.vDiv then vc.vDiv:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.4) * 0.7) end
            for _, r in ipairs(state.vcCapRows or {}) do
                paintFs(r.nameFs, r.clickable and (pal.textBlue or pal.accentBlue or pal.text) or pal.text)
                paintFs(r.capFs, pal.text)
                paintFs(r.statusFs, r._statusColKey and pal[r._statusColKey] or pal.accentGreen or pal.text)
                if r.sep then r.sep:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.4) * 0.55) end
            end
            local peakCol = pal.accentGreen or pal.positive or { 0.18, 0.85, 0.45, 1 }
            local baseBarCol = pal.mode == "light"
                and { peakCol[1], peakCol[2], peakCol[3], 0.55 }
                or { peakCol[1], peakCol[2], peakCol[3], 0.48 }
            for i, b in ipairs(vc.histBars or {}) do
                paintFs(b.countFs, b._isPeak and peakCol or pal.textSecondary)
                paintFs(b.lblFs, pal.textMuted)
                if b.barTex then
                    local col = b._isPeak and peakCol or baseBarCol
                    b.barTex:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
                end
            end
        end
        if state.deCard then
            local de = state.deCard
            paintFs(de.titleFs, pal.textMuted)
            paintFs(de.badgeFs, de._badgeColKey and pal[de._badgeColKey] or pal.textBlue or pal.text)
            paintFs(de.summaryFs, pal.text)
            paintFs(de.exitFs, de._exitColKey and pal[de._exitColKey] or pal.textSecondary)
            paintFs(de.matHdrFs, pal.textMuted)
            paintFs(de.matEmptyFs, pal.textMuted)
            if de.div then de.div:SetColorTexture(sep[1], sep[2], sep[3], sep[4] or 0.4) end
            for _, r in ipairs(state.deOutcomeRows or {}) do
                paintFs(r.nameFs, r.clickable and (pal.textBlue or pal.accentBlue or pal.text) or pal.text)
                paintFs(r.chanceFs, pal.textSecondary)
                paintFs(r.unitFs, pal.text)
                paintFs(r.evFs, pal.text)
                if r.sep then r.sep:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.4) * 0.55) end
            end
        end
        if state.leftCard then
            paintFs(state.leftCard.hdrTitle, pal.textMuted)
            paintFs(state.leftCard.reagTitle, pal.textMuted)
            paintFs(state.leftCard.reagEmptyFs, pal.textMuted)
            for _, hfs in ipairs(state.leftCard.colHeaders or {}) do paintFs(hfs, pal.textMuted) end
            if state.leftCard.divider then
                state.leftCard.divider:SetColorTexture(sep[1], sep[2], sep[3], sep[4] or 0.4)
            end
            for _, r in ipairs(state.leftCard.overviewRows or {}) do
                paintFs(r.labelFs, pal.text)
                paintFs(r.qtyFs, pal.textMuted)
                paintFs(r.valueFs, pal.text)
                paintFs(r.deltaFs, r._deltaColKey and pal[r._deltaColKey] or pal.textMuted)
                paintFs(r.covFs, pal.textMuted)
                if r.sep then r.sep:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.4) * 0.55) end
            end
            for _, r in ipairs(state.reagentRows or {}) do
                paintFs(r.nameFs, r.clickable and (pal.textBlue or pal.accentBlue or pal.text) or pal.text)
                paintFs(r.qtyFs, pal.textSecondary)
                paintFs(r.unitFs, pal.text)
                paintFs(r.extFs, pal.text)
                paintFs(r.tagFs, r._tagColKey and pal[r._tagColKey] or pal.textMuted)
                paintFs(r.stockFs, pal.textSecondary)
                if r.sep then r.sep:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.4) * 0.55) end
            end
        end
        for _, card in ipairs({ state.compCard, state.ledgerCard, state.acqCard }) do
            if card then
                paintFs(card.titleFs, pal.textMuted)
                paintFs(card.bodyFs, pal.text)
            end
        end
        paintVisualCards(pal)
        if state.allAhCard then
            local allAh = state.allAhCard
            paintFs(allAh.titleFs, pal.textMuted)
            paintFs(allAh.summaryFs, pal.textSecondary)
            paintFs(allAh.emptyFs, pal.textMuted)
            if allAh.div then allAh.div:SetColorTexture(sep[1], sep[2], sep[3], sep[4] or 0.4) end
            if state.allAhData then
                paintAllAhRows()
            end
        end
        if state.target then
            if isRootVisible() then
                state.dirtyThemeRender = false
                DeepAnalysis.Render(state.target, true)
            else
                state.dirtyThemeRender = true
            end
        end
    end

    local function ensureBuilt()
        if state.built then return state.root end
        local a = app()
        local parent = a and a.ui and a.ui.deepAnalysisView
        if not parent then return nil end
        local T = daTheme()
        local pal = daPal()

        local root = CreateFrame("Frame", nil, parent)
        root:SetPoint("TOPLEFT", 0, 0)
        root:SetPoint("BOTTOMRIGHT", 0, 0)
        state.root = root
        DeepAnalysis.frame = root

        -- 1. Sticky Top Header (54px, glass_r12)
        local hdr = makeCard(root, "glass_r12", "cardBg", "border")
        hdr:SetPoint("TOPLEFT", 0, 0)
        hdr:SetPoint("TOPRIGHT", 0, 0)
        hdr:SetHeight(54)
        state.header = hdr
        DeepAnalysis.header = hdr

        local mkBtn = (T and T.CreatePlateButton) or function(p, lbl, w, h)
            local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
            b:SetSize(w, h)
            b:SetText(lbl)
            return b
        end

        hdr.returnBtn = mkBtn(hdr, "< Return", 136, 28, { variant = "secondary", pill = true, border = true, fontSize = 11, weight = "semibold" })
        hdr.returnBtn:SetPoint("LEFT", hdr, "LEFT", 10, 0)
        hdr.returnBtn:SetScript("OnClick", function()
            local cur = app()
            if cur and cur.returnFromDeepAnalysis then cur.returnFromDeepAnalysis() end
        end)

        hdr.icon = hdr:CreateTexture(nil, "ARTWORK")
        hdr.icon:SetSize(34, 34)
        hdr.icon:SetPoint("LEFT", hdr.returnBtn, "RIGHT", 10, 0)
        hdr.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        hdr.wowheadBtn = mkBtn(hdr, "Wowhead", 86, 28, { variant = "secondary", pill = true, border = true, fontSize = 11, icon = T and T.ASSETS and T.ASSETS.icon_send, iconSize = 11 })
        hdr.wowheadBtn:SetPoint("RIGHT", hdr, "RIGHT", -10, 0)
        hdr.wowheadBtn:SetScript("OnClick", function()
            local cur = app()
            if cur and cur.openWowheadPopup and state.wowheadCA then
                cur.openWowheadPopup(state.wowheadCA, state.titleText or "Item", hdr.icon and hdr.icon:GetTexture())
            end
        end)
        hdr.wowheadBtn:Hide()

        hdr.searchBtn = mkBtn(hdr, "Search AH", 92, 28, { variant = "secondary", pill = true, border = true, fontSize = 11, icon = T and T.ASSETS and T.ASSETS.icon_search, iconSize = 11 })
        hdr.searchBtn:SetPoint("RIGHT", hdr.wowheadBtn, "LEFT", -6, 0)
        hdr.searchBtn:SetScript("OnClick", function()
            local cur = app()
            local id = getTargetItemID(state.target)
            if cur and cur.searchAH and id then
                cur.searchAH(state.titleText or "", 1, id)
            end
        end)

        hdr.addBtn = mkBtn(hdr, "+ Add to Cart", 118, 28, { variant = "primary", fontSize = 11, weight = "semibold" })
        hdr.addBtn:SetPoint("RIGHT", hdr.searchBtn, "LEFT", -6, 0)
        hdr.addBtn:SetScript("OnClick", function(self)
            local cur = app()
            local tgt = state.target
            if not (cur and tgt) then return end
            local kind = tgt.kind or "recipe"
            if kind == "recipe" and tgt.row and cur.adjustRecipeShoppingQty then
                local before = cur.getRecipeShoppingQty and cur.getRecipeShoppingQty(tgt.row) or 0
                local caps = (state.vcRow and state.vcRow.reagentBuyCaps) or tgt.row.reagentBuyCaps
                local after = cur.adjustRecipeShoppingQty(tgt.row, 1, caps and { buyCaps = caps } or nil) or 0
                if after > before then self:SetText("Added (" .. tostring(after) .. ")") end
            elseif (kind == "writ" or kind == "crate" or kind == "forged") and tgt.row and cur.addQuickLookItem then
                if cur.addQuickLookItem(kind, tgt.row) then
                    self:SetText(kind == "writ" and "Queued" or "Added")
                end
            elseif kind == "item" and cur.addUnifiedShoppingItem then
                local id = getTargetItemID(tgt)
                if id and id > 0 then
                    cur.addUnifiedShoppingItem({
                        key = "item:" .. tostring(id),
                        name = state.titleText or ("Item " .. tostring(id)),
                        itemID = id,
                        qty = 1,
                        demandList = { { itemID = id, qty = 1, role = "Market Item" } },
                        sourceLabel = "Deep Analysis",
                    })
                    self:SetText("Added")
                end
            end
        end)

        hdr.favBtn = mkBtn(hdr, "", 28, 28, {
            icon = (T and T.ASSETS and T.ASSETS.icon_star) or "star",
            iconSize = 13,
            variant = "secondary",
            pill = true,
            border = true,
        })
        hdr.favBtn:SetPoint("RIGHT", hdr.addBtn, "LEFT", -6, 0)
        hdr.favBtn:SetScript("OnClick", function()
            local h = H() or host
            local wl = h and h.Watchlist
            if wl and type(wl.Toggle) == "function" and state.target then
                pcall(wl.Toggle, state.target)
            end
            syncFavButton()
        end)
        hdr.favBtn:SetScript("OnEnter", function(self)
            if not _G.GameTooltip then return end
            local tip = _G.GameTooltip
            tip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            tip:SetText(self._watched and "Remove from Watchlist" or "Add to Watchlist", 1, 1, 1)
            local TT = daTheme()
            if TT and TT.LiftTooltip then TT.LiftTooltip(tip) end
            tip:Show()
        end)
        hdr.favBtn:SetScript("OnLeave", hideTooltip)

        hdr.titleFs = makeFs(hdr, 16, "semibold", "LEFT", "text")
        if hdr.titleFs.SetWordWrap then hdr.titleFs:SetWordWrap(false) end
        hdr.titleFs:SetPoint("TOPLEFT", hdr.icon, "TOPRIGHT", 10, 0)
        hdr.titleFs:SetPoint("RIGHT", hdr.favBtn, "LEFT", -10, 0)
        hdr.titleFs:SetHeight(20)

        hdr.subtitleFs = makeFs(hdr, 11, "regular", "LEFT", "textSecondary")
        if hdr.subtitleFs.SetWordWrap then hdr.subtitleFs:SetWordWrap(false) end
        hdr.subtitleFs:SetPoint("TOPLEFT", hdr.titleFs, "BOTTOMLEFT", 0, -1)
        hdr.subtitleFs:SetPoint("RIGHT", hdr.favBtn, "LEFT", -10, 0)
        hdr.subtitleFs:SetHeight(15)

        hdr.titleHover = CreateFrame("Frame", nil, hdr)
        hdr.titleHover:SetPoint("TOPLEFT", hdr.icon, "TOPLEFT", 0, 2)
        hdr.titleHover:SetPoint("BOTTOMRIGHT", hdr.subtitleFs, "BOTTOMRIGHT", 0, -2)
        hdr.titleHover:EnableMouse(true)
        hdr.titleHover:SetScript("OnEnter", function(self)
            showItemTooltip(self, getTargetItemID(state.target))
        end)
        hdr.titleHover:SetScript("OnLeave", hideTooltip)

        -- 2. Scrollable Body (ScrollFrame + Theme.SlimScrollBar)
        local sf = CreateFrame("ScrollFrame", nil, root)
        sf:SetPoint("TOPLEFT", 0, -60)
        sf:SetPoint("BOTTOMRIGHT", -12, 0)
        if sf.SetClipsChildren then sf:SetClipsChildren(true) end
        if sf.EnableMouseWheel then sf:EnableMouseWheel(true) end
        sf:SetScript("OnMouseWheel", function(_, delta)
            setScrollOffset((state.scrollOffset or 0) - (tonumber(delta) or 0) * 48)
        end)
        state.scrollFrame = sf
        DeepAnalysis.scrollFrame = sf

        local sc = CreateFrame("Frame", nil, sf)
        sc:SetSize(1040, 920)
        if sf.SetScrollChild then sf:SetScrollChild(sc) end
        state.scrollChild = sc
        DeepAnalysis.scrollChild = sc

        local sb = CreateFrame("Slider", nil, root)
        sb:SetPoint("TOPRIGHT", -2, -62)
        sb:SetPoint("BOTTOMRIGHT", -2, 4)
        sb:SetWidth(8)
        if sb.SetOrientation then sb:SetOrientation("VERTICAL") end
        if sb.SetMinMaxValues then sb:SetMinMaxValues(0, 0) end
        if sb.SetValueStep then sb:SetValueStep(1) end
        if sb.SetObeyStepOnDrag then sb:SetObeyStepOnDrag(false) end
        if sb.SetValue then sb:SetValue(0) end
        if T and T.SlimScrollBar then T.SlimScrollBar(sb) end
        sb:SetScript("OnValueChanged", function(_, value)
            if math.abs((state.scrollOffset or 0) - (tonumber(value) or 0)) >= 0.5 then
                state.scrollOffset = tonumber(value) or 0
                if sf.SetVerticalScroll then sf:SetVerticalScroll(state.scrollOffset) end
            end
        end)
        sb:Hide()
        state.scrollBar = sb
        DeepAnalysis.scrollBar = sb

        -- Row 1: 5 KPI Cards (68px, glass_r10)
        state.kpiCards = {}
        for i = 1, 5 do
            local card = makeCard(sc, "glass_r10", "cardBg", "border")
            card:SetHeight(68)
            card.titleFs = makeFs(card, 10, "semibold", "LEFT", "textMuted")
            card.titleFs:SetPoint("TOPLEFT", 12, -9)
            card.titleFs:SetPoint("TOPRIGHT", -10, -9)
            card.titleFs:SetHeight(13)
            card.valueFs = makeFs(card, 15, "semibold", "LEFT", "text")
            if card.valueFs.SetWordWrap then card.valueFs:SetWordWrap(false) end
            card.valueFs:SetPoint("TOPLEFT", 12, -25)
            card.valueFs:SetPoint("TOPRIGHT", -10, -25)
            card.valueFs:SetHeight(20)
            card.subFs = makeFs(card, 10, "regular", "LEFT", "textSecondary")
            if card.subFs.SetWordWrap then card.subFs:SetWordWrap(false) end
            card.subFs:SetPoint("BOTTOMLEFT", 12, 8)
            card.subFs:SetPoint("BOTTOMRIGHT", -10, 8)
            card.subFs:SetHeight(13)
            state.kpiCards[i] = card
        end
        DeepAnalysis.kpiCards = state.kpiCards

        -- Row 1.5: Dual Side-by-Side 24h & 7d Charts Strip (DA.chartsRow) + 44px Baseline Fallback
        local chartsFrame = CreateFrame("Frame", nil, sc)
        chartsFrame:SetHeight(152)
        local Chart = ns.Chart
        local chart24h = Chart and Chart.CreateLineChart and Chart.CreateLineChart(chartsFrame, 480, 152, {
            title = "24h Price Trend",
            preserveColor = true,
            preserveOrder = true,
            compact = true,
            borderKey = "border",
            emptyText = "Need 2+ AH scans for 24h trend",
        }) or nil
        local chart7d = Chart and Chart.CreateLineChart and Chart.CreateLineChart(chartsFrame, 480, 152, {
            title = "7d Price Trend",
            preserveColor = true,
            preserveOrder = true,
            compact = true,
            borderKey = "border",
            emptyText = "Need 2+ daily scans for 7d trend",
        }) or nil

        local baselineCard = makeCard(chartsFrame, "glass_r10", "cardBg", "border")
        baselineCard:SetHeight(44)
        baselineCard.titleFs = makeFs(baselineCard, 9, "semibold", "LEFT", "textMuted")
        baselineCard.titleFs:SetPoint("TOPLEFT", 12, -6)
        baselineCard.titleFs:SetText("PRICE BASELINE")
        baselineCard.stripFs = makeFs(baselineCard, 11, "semibold", "LEFT", "text")
        if baselineCard.stripFs.SetWordWrap then baselineCard.stripFs:SetWordWrap(false) end
        baselineCard.stripFs:SetPoint("BOTTOMLEFT", 12, 7)
        baselineCard.hintFs = makeFs(baselineCard, 10, "regular", "RIGHT", "textSecondary")
        if baselineCard.hintFs.SetWordWrap then baselineCard.hintFs:SetWordWrap(false) end
        baselineCard.hintFs:SetPoint("RIGHT", -12, 0)
        baselineCard.hintFs:SetText("Run 2+ AH scans over time to plot 24h & 7d trends")
        baselineCard:Hide()

        state.chart24h = chart24h
        state.chart7d = chart7d
        state.baselineCard = baselineCard
        state.chartsRow = {
            frame = chartsFrame,
            chart24h = chart24h,
            chart7d = chart7d,
            baselineCard = baselineCard,
        }
        DeepAnalysis.chart24h = chart24h
        DeepAnalysis.chart7d = chart7d
        DeepAnalysis.baselineCard = baselineCard
        DeepAnalysis.chartsRow = state.chartsRow

        -- Row 2: Concept B Split Timing Drawer (415px, mounted only when Snapshots / Snapshot Extension active)
        state.ensureTimingDrawer = function()
            if not hasSnapshotUI() then return nil end
            if state.timingDrawer then return state.timingDrawer end
            local h = H() or host
            local ext = h and h.app and h.app.snapshotExtension
            local Chart = ns.Chart
            local factory = (ext and type(ext.CreateHeatmapDrawer) == "function" and ext.CreateHeatmapDrawer)
                or (Chart and Chart.CreateHeatmapTimingDrawer)
            if factory then
                local drawer = factory(sc, 1020, 415, { compact = false, showCurve = true, skipInitialRedraw = true })
                state.timingDrawer = drawer
                DeepAnalysis.timingDrawer = drawer
                local df = drawer and (drawer.frame or drawer)
                if df and df.SetPoint then
                    df:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -78)
                end
                return drawer
            end
            return nil
        end
        if hasSnapshotUI() then
            state.ensureTimingDrawer()
        end

        -- Vendor Yield & Material Buy Caps Card (Proposal A, shown for recipes with buy caps / variable or measured yield)
        local vc = makeCard(sc, "glass_r10", "cardBg", "border")
        vc.titleFs = makeFs(vc, 10, "semibold", "LEFT", "textMuted")
        vc.titleFs:SetPoint("TOPLEFT", 12, -10)
        vc.titleFs:SetText("VENDOR YIELD & MATERIAL BUY CAPS")

        vc.badgeFs = makeFs(vc, 10, "semibold", "RIGHT", "accentGreen")
        vc.badgeFs:SetPoint("TOPRIGHT", -12, -10)
        vc.badgeFs:SetText("")

        vc.spreadFs = makeFs(vc, 11, "regular", "LEFT", "text")
        if vc.spreadFs.SetWordWrap then vc.spreadFs:SetWordWrap(false) end
        vc.spreadFs:SetPoint("TOPLEFT", 12, -28)
        vc.spreadFs:SetPoint("TOPRIGHT", -12, -28)
        vc.spreadFs:SetHeight(16)

        vc.div = vc:CreateTexture(nil, "BORDER")
        vc.div:SetHeight(1)
        vc.div:SetPoint("TOPLEFT", 12, -50)
        vc.div:SetPoint("TOPRIGHT", -12, -50)
        vc.div:SetColorTexture(1, 1, 1, 0.14)

        vc.vDiv = vc:CreateTexture(nil, "BORDER")
        vc.vDiv:SetWidth(1)
        vc.vDiv:SetColorTexture(1, 1, 1, 0.12)

        vc.capHdrFs = makeFs(vc, 9, "semibold", "LEFT", "textMuted")
        vc.capHdrFs:SetText("MATERIAL BUY CAPS (AH LIMITS)")

        vc.capEmptyFs = makeFs(vc, 10, "regular", "LEFT", "textMuted")
        vc.capEmptyFs:SetText("No AH material buy caps for this recipe.")
        vc.capEmptyFs:Hide()

        vc.histHdrFs = makeFs(vc, 9, "semibold", "LEFT", "textMuted")
        vc.histHdrFs:SetText("LEDGER ROLL DISTRIBUTION")

        vc.histMetaFs = makeFs(vc, 10, "semibold", "RIGHT", "textSecondary")
        vc.histMetaFs:SetText("")

        vc.histEmptyFs = makeFs(vc, 10, "regular", "CENTER", "textMuted")
        if vc.histEmptyFs.SetWordWrap then vc.histEmptyFs:SetWordWrap(true) end
        vc.histEmptyFs:SetText("Craft this recipe to measure real rolls (auto-switches at 10 casts).")
        vc.histEmptyFs:Hide()

        vc.histBars = {}
        for i = 1, 12 do
            local slot = CreateFrame("Frame", nil, vc)
            slot:SetSize(24, 68)
            slot.countFs = makeFs(slot, 9, "semibold", "CENTER", "textSecondary")
            slot.countFs:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 0, 14)
            slot.countFs:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 14)
            slot.countFs:SetHeight(12)
            slot.barTex = slot:CreateTexture(nil, "ARTWORK")
            slot.barTex:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 2, 14)
            slot.barTex:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 14)
            slot.barTex:SetHeight(8)
            slot.barTex:SetColorTexture(0.18, 0.85, 0.45, 0.72)
            slot.lblFs = makeFs(slot, 9, "semibold", "CENTER", "textMuted")
            slot.lblFs:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 0, 0)
            slot.lblFs:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
            slot.lblFs:SetHeight(12)
            slot:Hide()
            vc.histBars[i] = slot
        end

        vc:Hide()
        state.vcCard = vc
        DeepAnalysis.vcCard = vc

        -- Disenchanting Analysis Card (shown for disenchantable items and crafted gear)
        local de = makeCard(sc, "glass_r10", "cardBg", "border")
        de.titleFs = makeFs(de, 10, "semibold", "LEFT", "textMuted")
        de.titleFs:SetPoint("TOPLEFT", 12, -10)
        de.titleFs:SetText("DISENCHANTING ANALYSIS")

        de.badgeFs = makeFs(de, 10, "semibold", "RIGHT", "textBlue")
        de.badgeFs:SetPoint("TOPRIGHT", -12, -10)
        de.badgeFs:SetText("")

        de.summaryFs = makeFs(de, 11, "regular", "LEFT", "text")
        if de.summaryFs.SetWordWrap then de.summaryFs:SetWordWrap(false) end
        de.summaryFs:SetPoint("TOPLEFT", 12, -28)
        de.summaryFs:SetPoint("TOPRIGHT", -12, -28)
        de.summaryFs:SetHeight(16)

        de.exitFs = makeFs(de, 10, "semibold", "LEFT", "textSecondary")
        if de.exitFs.SetWordWrap then de.exitFs:SetWordWrap(false) end
        de.exitFs:SetPoint("TOPLEFT", 12, -46)
        de.exitFs:SetPoint("TOPRIGHT", -12, -46)
        de.exitFs:SetHeight(15)

        de.div = de:CreateTexture(nil, "BORDER")
        de.div:SetHeight(1)
        de.div:SetPoint("TOPLEFT", 12, -66)
        de.div:SetPoint("TOPRIGHT", -12, -66)
        de.div:SetColorTexture(1, 1, 1, 0.14)

        de.matHdrFs = makeFs(de, 9, "semibold", "LEFT", "textMuted")
        de.matHdrFs:SetText("DISENCHANT MATERIAL OUTCOMES (CLICK TO INSPECT)")

        de.matEmptyFs = makeFs(de, 10, "regular", "LEFT", "textMuted")
        de.matEmptyFs:SetText("No priced disenchant outcomes available.")
        de.matEmptyFs:Hide()

        de:Hide()
        state.deCard = de
        DeepAnalysis.deCard = de

        -- Row 3 Left Card: Overview + Full Reagents & Movers Breakdown
        local left = makeCard(sc, "glass_r10", "cardBg", "border")
        state.leftCard = left
        DeepAnalysis.leftCard = left

        left.hdrTitle = makeFs(left, 10, "semibold", "LEFT", "textMuted")
        left.hdrTitle:SetPoint("TOPLEFT", 12, -11)
        left.hdrTitle:SetText("CRAFT & MARKET OVERVIEW")

        local pillOpts = { variant = "secondary", pill = true, border = true, fontSize = 10, weight = "semibold" }
        left.win7dBtn = mkBtn(left, "7d", 42, 22, pillOpts)
        left.win7dBtn:SetPoint("TOPRIGHT", left, "TOPRIGHT", -10, -7)
        left.win24Btn = mkBtn(left, "24h", 44, 22, pillOpts)
        left.win24Btn:SetPoint("RIGHT", left.win7dBtn, "LEFT", -4, 0)
        local function switchWindow(win)
            _G.MerchantMasterDB = _G.MerchantMasterDB or {}
            _G.MerchantMasterDB.quickLookWindow = win
            state.window = win
            if state.target then
                state.target.window = win
                if state.target.context then state.target.context.window = win end
                DeepAnalysis.Render(state.target, true)
            end
        end
        left.win24Btn:SetScript("OnClick", function() switchWindow("24h") end)
        left.win7dBtn:SetScript("OnClick", function() switchWindow("7d") end)

        -- Visual Economy Bar Card (54px at y=-36 inside leftCard)
        local econCard = makeCard(left, "glass_r10", "cardAltBg", "border")
        econCard:SetHeight(54)
        econCard.craftFrame = CreateFrame("Frame", nil, econCard)
        econCard.craftFrame:SetAllPoints(econCard)
        econCard.craftBars = {}
        local craftDefs = {
            { label = "Craft Cost",  colorKey = "accentOrange" },
            { label = "Net AH Sale", colorKey = "accentBlue" },
            { label = "Net Profit",  colorKey = "accentGreen" },
        }
        for i, cd in ipairs(craftDefs) do
            local slot = CreateFrame("Frame", nil, econCard.craftFrame)
            slot:SetHeight(14)
            slot.lblFs = makeFs(slot, 9, "semibold", "LEFT", "textSecondary")
            if slot.lblFs.SetWordWrap then slot.lblFs:SetWordWrap(false) end
            slot.lblFs:SetText(cd.label)
            slot.trackTex = slot:CreateTexture(nil, "BORDER")
            slot.trackTex:SetHeight(5)
            slot.fillTex = slot:CreateTexture(nil, "ARTWORK")
            slot.fillTex:SetHeight(5)
            slot.valFs = makeFs(slot, 10, "semibold", "RIGHT", "text")
            if slot.valFs.SetWordWrap then slot.valFs:SetWordWrap(false) end
            slot._ratio = 0
            slot._colorKey = cd.colorKey
            slot._valColorKey = "text"
            econCard.craftBars[i] = slot
        end

        econCard.rangeFrame = CreateFrame("Frame", nil, econCard)
        econCard.rangeFrame:SetAllPoints(econCard)
        econCard.rangeLabels = {
            makeFs(econCard.rangeFrame, 10, "regular", "LEFT", "textSecondary"),
            makeFs(econCard.rangeFrame, 10, "semibold", "CENTER", "text"),
            makeFs(econCard.rangeFrame, 10, "regular", "RIGHT", "textSecondary"),
        }
        for _, rlbl in ipairs(econCard.rangeLabels) do
            if rlbl.SetWordWrap then rlbl:SetWordWrap(false) end
        end
        econCard.rangeTrack = econCard.rangeFrame:CreateTexture(nil, "BORDER")
        econCard.rangeTrack:SetHeight(6)
        econCard.rangeSpan = econCard.rangeFrame:CreateTexture(nil, "ARTWORK", nil, 0)
        econCard.rangeSpan:SetHeight(6)
        econCard.rangeMarkers = {}
        econCard._markerFracs = { 0, 0.5, 1 }
        econCard._markerColorKeys = { "textMuted", "accentBlue", "accentOrange" }
        for i = 1, 3 do
            local mk = econCard.rangeFrame:CreateTexture(nil, "OVERLAY")
            mk:SetSize(8, 10)
            econCard.rangeMarkers[i] = mk
        end
        econCard.rangeFrame:Hide()
        left.econBarCard = econCard

        left.overviewRows = {}
        local sep = pal.separator or pal.border or { 1, 1, 1, 0.14 }
        for i = 1, 6 do
            local r = CreateFrame("Frame", nil, left)
            r:SetHeight(21)
            r.sep = r:CreateTexture(nil, "BORDER")
            r.sep:SetPoint("TOPLEFT", 0, 0)
            r.sep:SetPoint("TOPRIGHT", 0, 0)
            r.sep:SetHeight(1)
            r.sep:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.4) * 0.55)
            r.labelFs = makeFs(r, 11, "semibold", "LEFT", "text")
            r.qtyFs = makeFs(r, 10, "regular", "RIGHT", "textMuted")
            r.valueFs = makeFs(r, 11, "semibold", "RIGHT", "text")
            r.deltaFs = makeFs(r, 10, "semibold", "RIGHT", "textMuted")
            r.covFs = makeFs(r, 10, "regular", "RIGHT", "textMuted")
            left.overviewRows[i] = r
        end

        left.divider = left:CreateTexture(nil, "BORDER")
        left.divider:SetHeight(1)
        left.divider:SetColorTexture(sep[1], sep[2], sep[3], sep[4] or 0.4)

        left.reagTitle = makeFs(left, 10, "semibold", "LEFT", "textMuted")
        left.reagTitle:SetText("REAGENTS & MOVERS BREAKDOWN")

        left.colHeaders = {}
        local hdrSpecs = {
            { "ITEM", "LEFT" },
            { "QTY", "RIGHT" },
            { "UNIT", "RIGHT" },
            { "EXTENDED", "RIGHT" },
            { "TREND / SRC", "RIGHT" },
            { "OWN / AH", "RIGHT" },
        }
        for i, hs in ipairs(hdrSpecs) do
            local fs = makeFs(left, 9, "semibold", hs[2], "textMuted")
            fs:SetText(hs[1])
            left.colHeaders[i] = fs
        end

        left.reagEmptyFs = makeFs(left, 11, "regular", "CENTER", "textMuted")
        left.reagEmptyFs:SetText("No reagents listed.")
        left.reagEmptyFs:Hide()

        -- Row 3 Right Column: 3 Stacked Cards
        local function makeInfoCard(title)
            local c = makeCard(sc, "glass_r10", "cardBg", "border")
            c.titleFs = makeFs(c, 10, "semibold", "LEFT", "textMuted")
            c.titleFs:SetPoint("TOPLEFT", 12, -10)
            c.titleFs:SetPoint("TOPRIGHT", -12, -10)
            c.titleFs:SetHeight(14)
            c.titleFs:SetText(title)
            c.bodyFs = makeFs(c, 11, "regular", "LEFT", "text")
            if c.bodyFs.SetJustifyV then c.bodyFs:SetJustifyV("TOP") end
            if c.bodyFs.SetWordWrap then c.bodyFs:SetWordWrap(true) end
            if c.bodyFs.SetSpacing then c.bodyFs:SetSpacing(3) end
            c.bodyFs:SetPoint("TOPLEFT", 12, -28)
            c.bodyFs:SetPoint("TOPRIGHT", -12, -28)
            return c
        end

        state.compCard = makeInfoCard("COMPETITION, VELOCITY & QUALITY")
        state.compCard.heatBar = CreateFrame("Frame", nil, state.compCard)
        state.compCard.heatBar:SetHeight(24)
        state.compCard.heatTiers = {}
        state.compCard._activeTier = 1
        for i, spec in ipairs(HEAT_TIERS) do
            local tf = CreateFrame("Frame", nil, state.compCard.heatBar)
            tf:SetHeight(22)
            tf.bgTex = tf:CreateTexture(nil, "BACKGROUND")
            tf.bgTex:SetAllPoints(tf)
            tf.lblFs = makeFs(tf, 10, "semibold", "CENTER", "textMuted")
            tf.lblFs:SetAllPoints(tf)
            tf.lblFs:SetText(spec.label)
            state.compCard.heatTiers[i] = tf
        end
        local hsf = CreateFrame("Frame", nil, state.compCard)
        hsf:SetHeight(26)
        hsf.captionFs = makeFs(hsf, 9, "semibold", "LEFT", "textSecondary")
        if hsf.captionFs.SetWordWrap then hsf.captionFs:SetWordWrap(false) end
        hsf.captionFs:SetHeight(12)
        hsf.captionFs:SetText("Sales Heat")
        hsf.strip24h = (ns.Chart and ns.Chart.CreateHeatStrip24h)
            and ns.Chart.CreateHeatStrip24h(hsf, { height = 8, showNowTick = true })
            or nil
        hsf.spectrumBar = CreateFrame("Frame", nil, hsf)
        hsf.spectrumBar:SetHeight(8)
        hsf.spectrumSegs = {}
        for i = 1, 12 do
            local seg = hsf.spectrumBar:CreateTexture(nil, "ARTWORK", nil, 0)
            seg:SetHeight(8)
            hsf.spectrumSegs[i] = seg
        end
        hsf.spectrumMarker = hsf.spectrumBar:CreateTexture(nil, "OVERLAY", nil, 2)
        hsf.spectrumMarker:SetSize(4, 12)
        hsf._mode = "spectrum"
        hsf._heatFrac = 0.12
        state.compCard.heatStripFrame = hsf

        state.ledgerCard = makeInfoCard("PERSONAL LEDGER & CROSS-ALT INVENTORY")
        local lc = state.ledgerCard
        lc.horizonFrame = CreateFrame("Frame", nil, lc)
        lc.horizonFrame:SetHeight(56)
        lc.horizonCols = {}
        for i, hLbl in ipairs({ "7d", "30d", "All-Time" }) do
            local cf = CreateFrame("Frame", nil, lc.horizonFrame)
            cf:SetHeight(56)
            cf.valFs = makeFs(cf, 10, "semibold", "CENTER", "text")
            if cf.valFs.SetWordWrap then cf.valFs:SetWordWrap(false) end
            cf.barTrack = cf:CreateTexture(nil, "BORDER")
            cf.barTrack:SetHeight(20)
            cf.barFill = cf:CreateTexture(nil, "ARTWORK")
            cf.barFill:SetHeight(6)
            cf.lblFs = makeFs(cf, 9, "semibold", "CENTER", "textMuted")
            cf.lblFs:SetText(hLbl)
            cf._ratio = 0
            cf._colorKey = "accentGreen"
            cf._valColorKey = "text"
            lc.horizonCols[i] = cf
        end
        lc.emptyTradesFs = makeFs(lc, 10, "regular", "LEFT", "textMuted")
        lc.emptyTradesFs:SetText("No personal AH trades recorded yet")
        lc.emptyTradesFs:Hide()

        lc.saleRateRow = CreateFrame("Frame", nil, lc)
        lc.saleRateRow:SetHeight(24)
        lc.saleRateRow.lblFs = makeFs(lc.saleRateRow, 10, "semibold", "LEFT", "textSecondary")
        if lc.saleRateRow.lblFs.SetWordWrap then lc.saleRateRow.lblFs:SetWordWrap(false) end
        if T and T.CreateProgressBar then
            lc.saleRateRow.bar = T.CreateProgressBar(lc.saleRateRow, 6, { width = 200 })
        else
            lc.saleRateRow.fallbackTrack = lc.saleRateRow:CreateTexture(nil, "BORDER")
            lc.saleRateRow.fallbackTrack:SetHeight(6)
            lc.saleRateRow.fallbackFill = lc.saleRateRow:CreateTexture(nil, "ARTWORK")
            lc.saleRateRow.fallbackFill:SetHeight(6)
        end
        lc.saleRateRow._frac = 0
        lc.saleRateRow._colorKey = "accentGreen"
        lc.saleRateRow:Hide()

        lc.stockRow = CreateFrame("Frame", nil, lc)
        lc.stockRow:SetHeight(22)
        lc.stockChips = {}
        for i, sLbl in ipairs({ "Bags", "Bank", "Mail", "AH" }) do
            local ch = CreateFrame("Frame", nil, lc.stockRow)
            ch:SetHeight(20)
            ch.bgTex = ch:CreateTexture(nil, "BACKGROUND")
            ch.bgTex:SetAllPoints(ch)
            ch.lblFs = makeFs(ch, 10, "semibold", "CENTER", "textMuted")
            if ch.lblFs.SetWordWrap then ch.lblFs:SetWordWrap(false) end
            ch.lblFs:SetAllPoints(ch)
            ch.lblFs:SetText(sLbl .. " 0")
            ch._qty = 0
            lc.stockChips[i] = ch
        end

        state.acqCard = makeInfoCard("ACQUISITION, SCROLL, SKILL & COOLDOWN")
        local ac = state.acqCard
        ac.pillRow = CreateFrame("Frame", nil, ac)
        ac.pillRow:SetHeight(22)
        ac.pills = {}
        for i = 1, 4 do
            local p
            if T and T.CreateBadgePill then
                p = T.CreateBadgePill(ac.pillRow, "", "neutral", { height = 20, fontSize = 10, padX = 12 })
                p.frame:Hide()
            else
                local pf = CreateFrame("Frame", nil, ac.pillRow)
                pf:SetSize(72, 20)
                local bg = pf:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints(pf)
                bg:SetColorTexture(0.3, 0.3, 0.35, 0.25)
                local lbl = makeFs(pf, 10, "semibold", "CENTER", "text")
                lbl:SetAllPoints(pf)
                p = {
                    frame = pf,
                    label = lbl,
                    SetVariant = function(self, _, txt)
                        self.label:SetText(tostring(txt or ""))
                        self.frame:SetWidth(math.max(44, #tostring(txt or "") * 6 + 14))
                    end,
                }
                pf:Hide()
            end
            ac.pills[i] = p
        end

        DeepAnalysis.compCard = state.compCard
        DeepAnalysis.ledgerCard = state.ledgerCard
        DeepAnalysis.acqCard = state.acqCard
        DeepAnalysis.rightCol = { state.compCard, state.ledgerCard, state.acqCard }

        -- Row 4 Full Width: All Auction Houses (Latest-Only Price & Qty Comparison)
        local allAh = makeCard(sc, "glass_r10", "cardBg", "border")
        allAh.titleFs = makeFs(allAh, 10, "semibold", "LEFT", "textMuted")
        allAh.titleFs:SetText("ALL AUCTION HOUSES (LATEST)")
        allAh.summaryFs = makeFs(allAh, 11, "regular", "LEFT", "textSecondary")
        if allAh.summaryFs.SetWordWrap then allAh.summaryFs:SetWordWrap(false) end
        allAh.div = allAh:CreateTexture(nil, "BORDER")
        allAh.div:SetHeight(1)
        allAh.div:SetColorTexture(sep[1], sep[2], sep[3], sep[4] or 0.4)

        allAh.filterBtns = {}
        local ahPillOpts = { variant = "secondary", pill = true, border = true, fontSize = 10, weight = "semibold" }
        for _, spec in ipairs(ALL_AH_FILTERS) do
            local fKey = spec.key
            local fBtn = mkBtn(allAh, spec.label, spec.width, 22, ahPillOpts)
            fBtn:SetScript("OnClick", function()
                state.allAhFilter = fKey
                paintAllAhRows()
                DeepAnalysis.Layout(state.viewportW, state.viewportH, true)
            end)
            allAh.filterBtns[fKey] = fBtn
        end

        allAh.colBtns = {}
        for i, cs in ipairs(ALL_AH_COLS) do
            local cKey = cs.key
            local cBtn = CreateFrame("Button", nil, allAh)
            cBtn:EnableMouse(true)
            cBtn:RegisterForClicks("LeftButtonUp")
            cBtn.fs = makeFs(cBtn, 9, "semibold", cs.align, "textMuted")
            cBtn.fs:SetAllPoints(cBtn)
            cBtn.fs:SetText(cs.label)
            cBtn:SetScript("OnClick", function()
                if state.allAhSortCol == cKey then
                    state.allAhSortAsc = not state.allAhSortAsc
                else
                    state.allAhSortCol = cKey
                    state.allAhSortAsc = (cKey ~= "qty")
                end
                paintAllAhRows()
            end)
            allAh.colBtns[i] = cBtn
        end

        allAh.emptyFs = makeFs(allAh, 11, "regular", "CENTER", "textMuted")
        allAh.emptyFs:SetText("No houses match the selected faction filter.")
        allAh.emptyFs:Hide()
        allAh:Hide()
        state.allAhCard = allAh
        DeepAnalysis.allAhCard = allAh

        if T and T.RegisterWidget then T.RegisterWidget(root, applyTheme) end
        local function flushDirtyTheme()
            if state.dirtyThemeRender and state.target and isRootVisible() then
                state.dirtyThemeRender = false
                DeepAnalysis.Render(state.target, true)
            end
        end
        root:SetScript("OnShow", flushDirtyTheme)
        if parent and parent.HookScript then
            parent:HookScript("OnShow", flushDirtyTheme)
        end

        state.built = true
        return root
    end

    local function estimateWrappedHeight(str, widthPx, lineHeight)
        local w = math.max(180, tonumber(widthPx) or 360)
        local charsPerLine = math.max(24, math.floor(w / 6.3))
        local totalLines = 0
        local clean = stripCodes(tostring(str or ""))
        for line in (clean .. "\n"):gmatch("([^\n]*)\n") do
            local n = #line
            totalLines = totalLines + math.max(1, math.ceil(n / charsPerLine))
        end
        return math.max(40, totalLines * (lineHeight or 16))
    end

    function DeepAnalysis.Layout(width, height, skipDrawerRedraw)
        if not state.built or not state.root then return end
        local a = app()
        local mainW = tonumber(width) or (a and a.ui and a.ui.deepAnalysisView and a.ui.deepAnalysisView:GetWidth()) or state.viewportW or 1060
        local mainH = tonumber(height) or (a and a.ui and a.ui.deepAnalysisView and a.ui.deepAnalysisView:GetHeight()) or state.viewportH or 620
        if mainW <= 100 then mainW = 1060 end
        if mainH <= 100 then mainH = 620 end
        state.viewportW, state.viewportH = mainW, mainH
        if a and a._openingDeepAnalysis then return end

        local W = math.max(480, math.floor(mainW - 18))
        state.scrollChild:SetWidth(W)

        -- Row 1: 5 KPI Cards
        local kpiGap = 8
        local kpiW = math.floor((W - kpiGap * 4) / 5)
        for i = 1, 5 do
            local card = state.kpiCards[i]
            local x = (i - 1) * (kpiW + kpiGap)
            local cw = (i == 5) and (W - x) or kpiW
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", x, 0)
            card:SetSize(cw, 68)
        end

        -- Row 1.5: Dual Side-by-Side 24h & 7d Charts Strip (or 44px Baseline Fallback)
        local nextY = -78
        if state.chartsRow and state.chartsRow.frame then
            local cf = state.chartsRow.frame
            local c24 = state.chart24h
            local c7 = state.chart7d
            local bc = state.baselineCard
            local chartsRowH = 0
            if state.chartsCollapsed then
                chartsRowH = 44
                if c24 then c24:Hide() end
                if c7 then c7:Hide() end
                if bc then
                    bc:ClearAllPoints()
                    bc:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
                    bc:SetSize(W, 44)
                    bc.titleFs:ClearAllPoints()
                    bc.titleFs:SetPoint("TOPLEFT", bc, "TOPLEFT", 12, -6)
                    bc.titleFs:SetSize(120, 12)
                    bc.stripFs:ClearAllPoints()
                    bc.stripFs:SetPoint("BOTTOMLEFT", bc, "BOTTOMLEFT", 12, 7)
                    if W >= 740 then
                        local hintW = math.min(310, math.floor(W * 0.42))
                        bc.hintFs:ClearAllPoints()
                        bc.hintFs:SetPoint("RIGHT", bc, "RIGHT", -12, 0)
                        bc.hintFs:SetSize(hintW, 16)
                        bc.hintFs:Show()
                        bc.stripFs:SetSize(math.max(180, W - hintW - 36), 16)
                    else
                        bc.hintFs:ClearAllPoints()
                        bc.hintFs:SetPoint("TOPRIGHT", bc, "TOPRIGHT", -12, -6)
                        bc.hintFs:SetSize(math.max(160, W - 144), 12)
                        bc.hintFs:Show()
                        bc.stripFs:SetSize(math.max(200, W - 24), 16)
                    end
                    bc:Show()
                end
            else
                if bc then bc:Hide() end
                local sideBySide = (W >= 860)
                local chartGap = 10
                if sideBySide then
                    chartsRowH = 152
                    local halfW = math.floor((W - chartGap) / 2)
                    if c24 then
                        c24:ClearAllPoints()
                        c24:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
                        c24:Show()
                        c24:Layout(halfW, 152, skipDrawerRedraw)
                    end
                    if c7 then
                        c7:ClearAllPoints()
                        c7:SetPoint("TOPLEFT", cf, "TOPLEFT", halfW + chartGap, 0)
                        c7:Show()
                        c7:Layout(W - halfW - chartGap, 152, skipDrawerRedraw)
                    end
                else
                    chartsRowH = 314
                    if c24 then
                        c24:ClearAllPoints()
                        c24:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
                        c24:Show()
                        c24:Layout(W, 152, skipDrawerRedraw)
                    end
                    if c7 then
                        c7:ClearAllPoints()
                        c7:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, -162)
                        c7:Show()
                        c7:Layout(W, 152, skipDrawerRedraw)
                    end
                end
            end
            cf:ClearAllPoints()
            cf:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", 0, nextY)
            cf:SetSize(W, chartsRowH)
            cf:Show()
            nextY = nextY - chartsRowH - 10
        end

        -- Row 2 (optional, above Timing Drawer so Proposal A shows above the fold): Vendor Yield & Material Buy Caps Card
        local vc = state.vcCard
        if vc and vc.IsShown and vc:IsShown() then
            local twoColVC = (W >= 820)
            local innerW = W - 24
            local capW = twoColVC and math.floor((innerW - 18) * 0.58) or innerW
            local histW = twoColVC and (innerW - 18 - capW) or innerW
            local capRowsH = math.max(1, state.vcCapUsed or 0) * 24 + 22
            local histH = 92
            local bodyTopY = -58

            vc.capHdrFs:ClearAllPoints()
            vc.capHdrFs:SetPoint("TOPLEFT", vc, "TOPLEFT", 12, bodyTopY)
            vc.capHdrFs:SetSize(capW, 13)

            local capTopY = bodyTopY - 18
            local capUsed = state.vcCapUsed or 0
            for i = 1, capUsed do
                local cr = state.vcCapRows[i]
                if cr then
                    cr:ClearAllPoints()
                    cr:SetPoint("TOPLEFT", vc, "TOPLEFT", 12, capTopY - (i - 1) * 24)
                    cr:SetSize(capW, 24)
                    cr.nameFs:ClearAllPoints(); cr.nameFs:SetPoint("LEFT", 24, 0); cr.nameFs:SetWidth(math.max(96, capW - 306))
                    cr.statusFs:ClearAllPoints(); cr.statusFs:SetPoint("RIGHT", cr, "RIGHT", -2, 0); cr.statusFs:SetWidth(40)
                    cr.capFs:ClearAllPoints(); cr.capFs:SetPoint("RIGHT", cr.statusFs, "LEFT", -6, 0); cr.capFs:SetWidth(234)
                end
            end
            if capUsed == 0 and vc.capEmptyFs then
                vc.capEmptyFs:ClearAllPoints()
                vc.capEmptyFs:SetPoint("TOPLEFT", vc, "TOPLEFT", 12, capTopY - 2)
                vc.capEmptyFs:SetSize(capW, 20)
            end

            local histX = twoColVC and (12 + capW + 18) or 12
            local histTopY = twoColVC and bodyTopY or (bodyTopY - capRowsH - 12)
            if vc.vDiv then
                if twoColVC then
                    vc.vDiv:ClearAllPoints()
                    vc.vDiv:SetPoint("TOPLEFT", vc, "TOPLEFT", 12 + capW + 9, bodyTopY + 2)
                    vc.vDiv:SetSize(1, math.max(capRowsH, histH) - 4)
                    vc.vDiv:Show()
                else
                    vc.vDiv:Hide()
                end
            end
            vc.histHdrFs:ClearAllPoints()
            vc.histHdrFs:SetPoint("TOPLEFT", vc, "TOPLEFT", histX, histTopY)
            vc.histHdrFs:SetWidth(math.floor(histW * 0.48))
            vc.histHdrFs:SetHeight(13)
            vc.histMetaFs:ClearAllPoints()
            vc.histMetaFs:SetPoint("TOPRIGHT", vc, "TOPLEFT", histX + histW, histTopY)
            vc.histMetaFs:SetWidth(math.ceil(histW * 0.52))
            vc.histMetaFs:SetHeight(13)

            local barsTopY = histTopY - 18
            local nBars = #(state.vcHistBuckets or {})
            local maxCnt = math.max(1, tonumber(state.vcHistMaxCount) or 1)
            if nBars > 0 then
                vc.histEmptyFs:Hide()
                local gap = math.max(4, math.min(10, math.floor(histW / (nBars * 6))))
                local barW = math.max(18, math.floor((histW - gap * (nBars - 1)) / nBars))
                for i = 1, 12 do
                    local b = vc.histBars[i]
                    local spec = (i <= nBars) and state.vcHistBuckets[i] or nil
                    if b and spec then
                        local bx = histX + (i - 1) * (barW + gap)
                        local barH = (spec.count > 0) and math.max(6, math.floor((spec.count / maxCnt) * 44 + 0.5)) or 3
                        b:ClearAllPoints()
                        b:SetPoint("TOPLEFT", vc, "TOPLEFT", bx, barsTopY)
                        b:SetSize(barW, 72)
                        b.barTex:ClearAllPoints()
                        b.barTex:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 14)
                        b.barTex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 14)
                        b.barTex:SetHeight(barH)
                        b.countFs:ClearAllPoints()
                        b.countFs:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 15 + barH)
                        b.countFs:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 15 + barH)
                        b.countFs:SetHeight(12)
                        b:Show()
                    elseif b then
                        b:Hide()
                    end
                end
            else
                for i = 1, 12 do
                    if vc.histBars[i] then vc.histBars[i]:Hide() end
                end
                vc.histEmptyFs:ClearAllPoints()
                vc.histEmptyFs:SetPoint("TOPLEFT", vc, "TOPLEFT", histX, barsTopY - 10)
                vc.histEmptyFs:SetSize(histW, 44)
                vc.histEmptyFs:Show()
            end

            local bodyH = twoColVC and math.max(capRowsH, histH) or (capRowsH + 12 + histH)
            local vcH = math.abs(bodyTopY) + bodyH + 12
            vc:ClearAllPoints()
            vc:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", 0, nextY)
            vc:SetSize(W, vcH)
            nextY = nextY - vcH - 10
        end

        local de = state.deCard
        if de and de.IsShown and de:IsShown() then
            local innerW = W - 24
            local deUsed = state.deOutcomeUsed or 0
            local matTopY = -74
            de.matHdrFs:ClearAllPoints()
            de.matHdrFs:SetPoint("TOPLEFT", de, "TOPLEFT", 12, matTopY)
            de.matHdrFs:SetSize(innerW, 13)

            local rowsTopY = matTopY - 18
            local chanceW = 148
            local unitW = 108
            local evW = 108
            local nameW = math.max(120, innerW - chanceW - unitW - evW - 44)
            for i = 1, deUsed do
                local dr = state.deOutcomeRows[i]
                if dr then
                    dr:ClearAllPoints()
                    dr:SetPoint("TOPLEFT", de, "TOPLEFT", 12, rowsTopY - (i - 1) * 24)
                    dr:SetSize(innerW, 24)
                    dr.nameFs:ClearAllPoints(); dr.nameFs:SetPoint("LEFT", 24, 0); dr.nameFs:SetWidth(nameW)
                    dr.evFs:ClearAllPoints(); dr.evFs:SetPoint("RIGHT", dr, "RIGHT", -4, 0); dr.evFs:SetWidth(evW)
                    dr.unitFs:ClearAllPoints(); dr.unitFs:SetPoint("RIGHT", dr.evFs, "LEFT", -8, 0); dr.unitFs:SetWidth(unitW)
                    dr.chanceFs:ClearAllPoints(); dr.chanceFs:SetPoint("RIGHT", dr.unitFs, "LEFT", -8, 0); dr.chanceFs:SetWidth(chanceW)
                end
            end
            if deUsed == 0 and de.matEmptyFs then
                de.matEmptyFs:ClearAllPoints()
                de.matEmptyFs:SetPoint("TOPLEFT", de, "TOPLEFT", 12, rowsTopY - 2)
                de.matEmptyFs:SetSize(innerW, 20)
            end

            local deH = math.abs(rowsTopY) + math.max(1, deUsed) * 24 + 12
            de:ClearAllPoints()
            de:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", 0, nextY)
            de:SetSize(W, deH)
            nextY = nextY - deH - 10
        end

        -- Row 2.5 / Row 2: Concept B Timing Drawer (hidden in standalone Live AH mode)
        local showTiming = hasSnapshotUI()
        local row3Y = nextY
        if showTiming and state.timingDrawer then
            local drawerH = 415
            local df = state.timingDrawer.frame or state.timingDrawer
            if df and df.Show then df:Show() end
            if df and df.ClearAllPoints and df.SetPoint then
                df:ClearAllPoints()
                df:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", 0, nextY)
            end
            if state.timingDrawer.Layout then
                state.timingDrawer:Layout(W, drawerH, skipDrawerRedraw)
            elseif df and df.SetSize then
                df:SetSize(W, drawerH)
            end
            row3Y = nextY - drawerH - 10
        elseif showTiming and state.timingPlaceholder then
            local drawerH = 140
            state.timingPlaceholder:Show()
            state.timingPlaceholder:ClearAllPoints()
            state.timingPlaceholder:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", 0, nextY)
            state.timingPlaceholder:SetSize(W, drawerH)
            row3Y = nextY - drawerH - 10
        else
            if state.timingDrawer then
                local df = state.timingDrawer.frame or state.timingDrawer
                if df and df.Hide then df:Hide() end
            end
            if state.timingPlaceholder then
                state.timingPlaceholder:Hide()
            end
        end

        -- Row 3: 2-Column at W >= 960, stacked below
        local twoCol = (W >= 960)
        local colGap = 10
        local leftW = twoCol and math.floor((W - colGap) * 0.56) or W
        local rightW = twoCol and (W - colGap - leftW) or W

        -- Left Card internal layout
        local left = state.leftCard
        local rw = leftW - 24
        if left.econBarCard then
            local ec = left.econBarCard
            ec:ClearAllPoints()
            ec:SetPoint("TOPLEFT", left, "TOPLEFT", 12, -36)
            ec:SetSize(rw, 54)
            local innerW = math.max(180, rw - 20)
            if ec.craftFrame and ec.craftFrame:IsShown() then
                local lblW = 72
                local valW = math.min(148, math.max(96, math.floor(innerW * 0.34)))
                local barW = math.max(40, innerW - lblW - valW - 16)
                for i, slot in ipairs(ec.craftBars or {}) do
                    slot:ClearAllPoints()
                    slot:SetPoint("TOPLEFT", ec, "TOPLEFT", 10, -4 - (i - 1) * 16)
                    slot:SetSize(innerW, 14)
                    slot.lblFs:ClearAllPoints()
                    slot.lblFs:SetPoint("LEFT", slot, "LEFT", 0, 0)
                    slot.lblFs:SetSize(lblW, 14)
                    slot.valFs:ClearAllPoints()
                    slot.valFs:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
                    slot.valFs:SetSize(valW, 14)
                    slot.trackTex:ClearAllPoints()
                    slot.trackTex:SetPoint("LEFT", slot, "LEFT", lblW + 8, 0)
                    slot.trackTex:SetSize(barW, 5)
                    local ratio = math.max(0, math.min(1, tonumber(slot._ratio) or 0))
                    slot.fillTex:ClearAllPoints()
                    slot.fillTex:SetPoint("LEFT", slot.trackTex, "LEFT", 0, 0)
                    if ratio > 0 then
                        slot.fillTex:SetSize(math.max(3, math.floor(barW * ratio + 0.5)), 5)
                        slot.fillTex:Show()
                    else
                        slot.fillTex:Hide()
                    end
                end
            elseif ec.rangeFrame and ec.rangeFrame:IsShown() then
                local thirdW = math.floor(innerW / 3)
                for i, rlbl in ipairs(ec.rangeLabels or {}) do
                    rlbl:ClearAllPoints()
                    rlbl:SetPoint("TOPLEFT", ec, "TOPLEFT", 10 + (i - 1) * thirdW, -8)
                    rlbl:SetSize(i == 3 and (innerW - 2 * thirdW) or thirdW, 14)
                end
                ec.rangeTrack:ClearAllPoints()
                ec.rangeTrack:SetPoint("TOPLEFT", ec, "TOPLEFT", 10, -34)
                ec.rangeTrack:SetSize(innerW, 6)
                local fracs = ec._markerFracs or { 0, 0.5, 1 }
                local minF, maxF = 1, 0
                local anyShown = false
                for i, mk in ipairs(ec.rangeMarkers or {}) do
                    local f = fracs[i]
                    if f ~= nil then
                        anyShown = true
                        local cf = math.max(0, math.min(1, f))
                        if cf < minF then minF = cf end
                        if cf > maxF then maxF = cf end
                        local mx = math.floor(cf * math.max(1, innerW - 8) + 0.5)
                        mk:ClearAllPoints()
                        mk:SetPoint("LEFT", ec.rangeTrack, "LEFT", mx, 0)
                        mk:SetSize(8, 10)
                        mk:Show()
                    else
                        mk:Hide()
                    end
                end
                if anyShown and maxF > minF then
                    local sx = math.floor(minF * innerW + 0.5)
                    local sw = math.max(4, math.floor((maxF - minF) * innerW + 0.5))
                    ec.rangeSpan:ClearAllPoints()
                    ec.rangeSpan:SetPoint("LEFT", ec.rangeTrack, "LEFT", sx, 0)
                    ec.rangeSpan:SetSize(sw, 6)
                    ec.rangeSpan:Show()
                else
                    ec.rangeSpan:Hide()
                end
            end
        end

        local ovY = -98
        for i = 1, 6 do
            local r = left.overviewRows[i]
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", left, "TOPLEFT", 12, ovY - (i - 1) * 21)
            r:SetSize(rw, 21)
            r.labelFs:ClearAllPoints(); r.labelFs:SetPoint("LEFT", 2, 0); r.labelFs:SetWidth(math.max(96, rw - 270))
            r.qtyFs:ClearAllPoints(); r.qtyFs:SetPoint("RIGHT", r, "RIGHT", -212, 0); r.qtyFs:SetWidth(52)
            r.valueFs:ClearAllPoints(); r.valueFs:SetPoint("RIGHT", r, "RIGHT", -104, 0); r.valueFs:SetWidth(104)
            r.deltaFs:ClearAllPoints(); r.deltaFs:SetPoint("RIGHT", r, "RIGHT", -44, 0); r.deltaFs:SetWidth(56)
            r.covFs:ClearAllPoints(); r.covFs:SetPoint("RIGHT", r, "RIGHT", -2, 0); r.covFs:SetWidth(40)
        end

        local divY = ovY - 6 * 21 - 8
        left.divider:ClearAllPoints()
        left.divider:SetPoint("TOPLEFT", left, "TOPLEFT", 12, divY)
        left.divider:SetPoint("TOPRIGHT", left, "TOPRIGHT", -12, divY)

        local reagTitleY = divY - 10
        left.reagTitle:ClearAllPoints()
        left.reagTitle:SetPoint("TOPLEFT", left, "TOPLEFT", 12, reagTitleY)

        local hdrY = reagTitleY - 16
        local colDefs = {
            { x = 28, w = math.max(96, rw - 368) },
            { r = -320, w = 36 },
            { r = -238, w = 78 },
            { r = -124, w = 110 },
            { r = -62, w = 58 },
            { r = -2, w = 56 },
        }
        for i, fs in ipairs(left.colHeaders) do
            local cd = colDefs[i]
            fs:ClearAllPoints()
            if cd.x then
                fs:SetPoint("TOPLEFT", left, "TOPLEFT", 12 + cd.x, hdrY)
            else
                fs:SetPoint("TOPRIGHT", left, "TOPRIGHT", -12 + cd.r, hdrY)
            end
            fs:SetSize(cd.w, 13)
        end

        local rowsTopY = hdrY - 18
        local used = state.reagentUsedCount or 0
        for i = 1, used do
            local row = state.reagentRows[i]
            if row then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", left, "TOPLEFT", 12, rowsTopY - (i - 1) * 26)
                row:SetSize(rw, 26)
                row.nameFs:ClearAllPoints()
                if row._hasShareBar and row._shareRatio then
                    row.nameFs:SetPoint("LEFT", 28, 3)
                    row.nameFs:SetWidth(colDefs[1].w)
                    local trackW = math.max(32, colDefs[1].w - 6)
                    row.shareTrack:ClearAllPoints()
                    row.shareTrack:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 28, 3)
                    row.shareTrack:SetSize(trackW, 3)
                    row.shareTrack:Show()
                    row.shareFill:ClearAllPoints()
                    row.shareFill:SetPoint("LEFT", row.shareTrack, "LEFT", 0, 0)
                    row.shareFill:SetSize(math.max(3, math.floor(trackW * row._shareRatio + 0.5)), 3)
                    row.shareFill:Show()
                else
                    row.nameFs:SetPoint("LEFT", 28, 0)
                    row.nameFs:SetWidth(colDefs[1].w)
                    if row.shareTrack then row.shareTrack:Hide() end
                    if row.shareFill then row.shareFill:Hide() end
                end
                row.qtyFs:ClearAllPoints(); row.qtyFs:SetPoint("RIGHT", row, "RIGHT", colDefs[2].r, 0); row.qtyFs:SetWidth(colDefs[2].w)
                row.unitFs:ClearAllPoints(); row.unitFs:SetPoint("RIGHT", row, "RIGHT", colDefs[3].r, 0); row.unitFs:SetWidth(colDefs[3].w)
                row.extFs:ClearAllPoints(); row.extFs:SetPoint("RIGHT", row, "RIGHT", colDefs[4].r, 0); row.extFs:SetWidth(colDefs[4].w)
                row.tagFs:ClearAllPoints(); row.tagFs:SetPoint("RIGHT", row, "RIGHT", colDefs[5].r, 0); row.tagFs:SetWidth(colDefs[5].w)
                row.stockFs:ClearAllPoints(); row.stockFs:SetPoint("RIGHT", row, "RIGHT", colDefs[6].r, 0); row.stockFs:SetWidth(colDefs[6].w)
            end
        end
        if used == 0 then
            left.reagEmptyFs:ClearAllPoints()
            left.reagEmptyFs:SetPoint("TOPLEFT", left, "TOPLEFT", 12, rowsTopY - 6)
            left.reagEmptyFs:SetSize(rw, 28)
        end

        local leftH = math.max(340, math.abs(rowsTopY) + math.max(1, used) * 26 + 16)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", 0, row3Y)
        left:SetSize(leftW, leftH)

        -- Right Column: 3 Stacked Visual Cards
        local rightX = twoCol and (leftW + colGap) or 0
        local curY = twoCol and row3Y or (row3Y - leftH - colGap)
        local rightTotalH = 0
        local bodyW = math.max(180, rightW - 24)
        local cards = { state.compCard, state.ledgerCard, state.acqCard }
        for idx, card in ipairs(cards) do
            local visualH = 28
            if card == state.compCard and card.heatBar then
                card.heatBar:ClearAllPoints()
                card.heatBar:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -28)
                card.heatBar:SetSize(bodyW, 24)
                local tGap = 4
                local tW = math.floor((bodyW - tGap * 3) / 4)
                for i, tf in ipairs(card.heatTiers or {}) do
                    local tx = (i - 1) * (tW + tGap)
                    local w = (i == 4) and (bodyW - tx) or tW
                    tf:ClearAllPoints()
                    tf:SetPoint("TOPLEFT", card.heatBar, "TOPLEFT", tx, 0)
                    tf:SetSize(math.max(24, w), 22)
                end
                if card.heatStripFrame then
                    local hsf = card.heatStripFrame
                    hsf:ClearAllPoints()
                    hsf:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -56)
                    hsf:SetSize(bodyW, 26)
                    if hsf.captionFs then
                        hsf.captionFs:ClearAllPoints()
                        hsf.captionFs:SetPoint("TOPLEFT", hsf, "TOPLEFT", 0, 0)
                        hsf.captionFs:SetSize(bodyW, 12)
                    end
                    if hsf.strip24h and hsf.strip24h.frame then
                        hsf.strip24h.frame:ClearAllPoints()
                        hsf.strip24h.frame:SetPoint("TOPLEFT", hsf, "TOPLEFT", 0, -15)
                        hsf.strip24h:Layout(bodyW)
                    end
                    if hsf.spectrumBar then
                        hsf.spectrumBar:ClearAllPoints()
                        hsf.spectrumBar:SetPoint("TOPLEFT", hsf, "TOPLEFT", 0, -15)
                        hsf.spectrumBar:SetSize(bodyW, 8)
                        local nSeg = #(hsf.spectrumSegs or {})
                        for i, seg in ipairs(hsf.spectrumSegs or {}) do
                            local x0 = math.floor((i - 1) * bodyW / nSeg)
                            local x1 = math.floor(i * bodyW / nSeg)
                            seg:ClearAllPoints()
                            seg:SetPoint("TOPLEFT", hsf.spectrumBar, "TOPLEFT", x0, 0)
                            seg:SetSize(math.max(1, x1 - x0), 8)
                        end
                        if hsf.spectrumMarker then
                            local frac = math.max(0.02, math.min(0.98, tonumber(hsf._heatFrac) or 0.12))
                            local mx = math.max(0, math.min(bodyW - 4, math.floor(bodyW * frac - 2 + 0.5)))
                            hsf.spectrumMarker:ClearAllPoints()
                            hsf.spectrumMarker:SetPoint("TOPLEFT", hsf.spectrumBar, "TOPLEFT", mx, 2)
                            hsf.spectrumMarker:SetSize(4, 12)
                        end
                    end
                    visualH = 86
                else
                    visualH = 58
                end
            elseif card == state.ledgerCard then
                local yOff = 28
                if card._hasTrades and card.horizonFrame then
                    card.horizonFrame:ClearAllPoints()
                    card.horizonFrame:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -yOff)
                    card.horizonFrame:SetSize(bodyW, 56)
                    local cGap = 8
                    local cW = math.floor((bodyW - cGap * 2) / 3)
                    for i, cf in ipairs(card.horizonCols or {}) do
                        local cx = (i - 1) * (cW + cGap)
                        local w = (i == 3) and (bodyW - cx) or cW
                        cf:ClearAllPoints()
                        cf:SetPoint("TOPLEFT", card.horizonFrame, "TOPLEFT", cx, 0)
                        cf:SetSize(math.max(40, w), 56)
                        cf.valFs:ClearAllPoints()
                        cf.valFs:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
                        cf.valFs:SetSize(math.max(40, w), 14)
                        cf.lblFs:ClearAllPoints()
                        cf.lblFs:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 0, 0)
                        cf.lblFs:SetSize(math.max(40, w), 12)
                        cf.barTrack:ClearAllPoints()
                        cf.barTrack:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", 4, 15)
                        cf.barTrack:SetSize(math.max(24, w - 8), 22)
                        local ratio = math.max(0.08, math.min(1, tonumber(cf._ratio) or 0))
                        local fillH = math.max(4, math.floor(22 * ratio + 0.5))
                        cf.barFill:ClearAllPoints()
                        cf.barFill:SetPoint("BOTTOMLEFT", cf.barTrack, "BOTTOMLEFT", 0, 0)
                        cf.barFill:SetSize(math.max(24, w - 8), fillH)
                    end
                    yOff = yOff + 60
                    if card.saleRateRow and card.saleRateRow:IsShown() then
                        card.saleRateRow:ClearAllPoints()
                        card.saleRateRow:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -yOff)
                        card.saleRateRow:SetSize(bodyW, 24)
                        card.saleRateRow.lblFs:ClearAllPoints()
                        card.saleRateRow.lblFs:SetPoint("TOPLEFT", card.saleRateRow, "TOPLEFT", 0, 0)
                        card.saleRateRow.lblFs:SetSize(bodyW, 13)
                        if card.saleRateRow.bar and card.saleRateRow.bar.frame then
                            local bf = card.saleRateRow.bar.frame
                            bf:ClearAllPoints()
                            bf:SetPoint("TOPLEFT", card.saleRateRow, "TOPLEFT", 0, -16)
                            bf:SetSize(bodyW, 6)
                            card.saleRateRow.bar:SetValue(card.saleRateRow._frac or 0)
                        elseif card.saleRateRow.fallbackTrack then
                            card.saleRateRow.fallbackTrack:ClearAllPoints()
                            card.saleRateRow.fallbackTrack:SetPoint("TOPLEFT", card.saleRateRow, "TOPLEFT", 0, -16)
                            card.saleRateRow.fallbackTrack:SetSize(bodyW, 6)
                            local fw = math.max(2, math.floor(bodyW * (card.saleRateRow._frac or 0) + 0.5))
                            card.saleRateRow.fallbackFill:ClearAllPoints()
                            card.saleRateRow.fallbackFill:SetPoint("LEFT", card.saleRateRow.fallbackTrack, "LEFT", 0, 0)
                            card.saleRateRow.fallbackFill:SetSize(fw, 6)
                        end
                        yOff = yOff + 28
                    end
                elseif card.emptyTradesFs then
                    card.emptyTradesFs:ClearAllPoints()
                    card.emptyTradesFs:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -yOff)
                    card.emptyTradesFs:SetSize(bodyW, 16)
                    yOff = yOff + 20
                end
                if card.stockRow then
                    card.stockRow:ClearAllPoints()
                    card.stockRow:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -yOff)
                    card.stockRow:SetSize(bodyW, 22)
                    local sGap = 6
                    local sW = math.floor((bodyW - sGap * 3) / 4)
                    for i, ch in ipairs(card.stockChips or {}) do
                        local sx = (i - 1) * (sW + sGap)
                        local w = (i == 4) and (bodyW - sx) or sW
                        ch:ClearAllPoints()
                        ch:SetPoint("TOPLEFT", card.stockRow, "TOPLEFT", sx, 0)
                        ch:SetSize(math.max(36, w), 20)
                    end
                    yOff = yOff + 26
                end
                visualH = yOff + 2
            elseif card == state.acqCard and card.pillRow then
                local px, py, rowCount, shownPills = 0, 0, 1, 0
                for _, p in ipairs(card.pills or {}) do
                    if p and p.frame and p.frame:IsShown() then
                        shownPills = shownPills + 1
                        local pw = math.max(32, p.frame:GetWidth() or 60)
                        if px > 0 and (px + pw) > bodyW then
                            px = 0
                            py = py - 24
                            rowCount = rowCount + 1
                        end
                        p.frame:ClearAllPoints()
                        p.frame:SetPoint("TOPLEFT", card.pillRow, "TOPLEFT", px, py)
                        px = px + pw + 6
                    end
                end
                if shownPills > 0 then
                    local prH = rowCount * 20 + (rowCount - 1) * 4
                    card.pillRow:ClearAllPoints()
                    card.pillRow:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -28)
                    card.pillRow:SetSize(bodyW, prH)
                    card.pillRow:Show()
                    visualH = 28 + prH + 8
                else
                    card.pillRow:Hide()
                    visualH = 28
                end
            end

            card.bodyFs:ClearAllPoints()
            card.bodyFs:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -visualH)
            card.bodyFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -visualH)
            card.bodyFs:SetWidth(bodyW)
            local textH = estimateWrappedHeight(card.bodyFs:GetText(), bodyW, 16)
            local cardH = math.max(visualH + 30, visualH + textH + 12)
            card.bodyFs:SetHeight(math.max(22, cardH - visualH - 8))
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", rightX, curY)
            card:SetSize(rightW, cardH)
            curY = curY - cardH - colGap
            rightTotalH = rightTotalH + cardH + (idx < #cards and colGap or 0)
        end

        local row3H = twoCol and math.max(leftH, rightTotalH) or (leftH + colGap + rightTotalH)
        local nextBottomY = row3Y - row3H

        -- Row 4: Full-Width All Auction Houses Comparison Card
        local allAh = state.allAhCard
        if allAh and allAh.IsShown and allAh:IsShown() then
            local row4Y = nextBottomY - colGap
            local ahUsed = state.allAhUsedCount or 0
            local aw = W - 24

            allAh.titleFs:ClearAllPoints()
            allAh.titleFs:SetPoint("TOPLEFT", allAh, "TOPLEFT", 12, -10)
            allAh.titleFs:SetSize(220, 14)

            local fx = -10
            local filterOrder = { "Blackwater", "Alliance", "Horde", "all", "faction8" }
            for _, fKey in ipairs(filterOrder) do
                local btn = allAh.filterBtns and allAh.filterBtns[fKey]
                if btn then
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPRIGHT", allAh, "TOPRIGHT", fx, -7)
                    fx = fx - (btn:GetWidth() or 60) - 4
                end
            end

            allAh.summaryFs:ClearAllPoints()
            allAh.summaryFs:SetPoint("TOPLEFT", allAh, "TOPLEFT", 12, -31)
            allAh.summaryFs:SetPoint("TOPRIGHT", allAh, "TOPRIGHT", -12, -31)
            allAh.summaryFs:SetHeight(14)

            if allAh.div then
                allAh.div:ClearAllPoints()
                allAh.div:SetPoint("TOPLEFT", allAh, "TOPLEFT", 12, -50)
                allAh.div:SetPoint("TOPRIGHT", allAh, "TOPRIGHT", -12, -50)
            end

            local hdrY = -57
            local ahColDefs = {
                { x = 8,    w = math.max(150, aw - 446) },
                { r = -326, w = 110 },
                { r = -212, w = 110 },
                { r = -146, w = 62 },
                { r = -4,   w = 136 },
            }
            for i, cbtn in ipairs(allAh.colBtns or {}) do
                local cd = ahColDefs[i]
                cbtn:ClearAllPoints()
                if cd.x then
                    cbtn:SetPoint("TOPLEFT", allAh, "TOPLEFT", 12 + cd.x, hdrY)
                else
                    cbtn:SetPoint("TOPRIGHT", allAh, "TOPRIGHT", -12 + cd.r, hdrY)
                end
                cbtn:SetSize(cd.w, 15)
            end

            local rowsTopY = hdrY - 19
            for i = 1, ahUsed do
                local row = state.allAhRows[i]
                if row then
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", allAh, "TOPLEFT", 12, rowsTopY - (i - 1) * 24)
                    row:SetSize(aw, 24)
                    row.nameFs:ClearAllPoints(); row.nameFs:SetPoint("LEFT", 8, 0); row.nameFs:SetWidth(ahColDefs[1].w)
                    row.minFs:ClearAllPoints(); row.minFs:SetPoint("RIGHT", row, "RIGHT", ahColDefs[2].r, 0); row.minFs:SetWidth(ahColDefs[2].w)
                    row.mktFs:ClearAllPoints(); row.mktFs:SetPoint("RIGHT", row, "RIGHT", ahColDefs[3].r, 0); row.mktFs:SetWidth(ahColDefs[3].w)
                    row.diffFs:ClearAllPoints(); row.diffFs:SetPoint("RIGHT", row, "RIGHT", ahColDefs[4].r, 0); row.diffFs:SetWidth(ahColDefs[4].w)
                    row.qtyFs:ClearAllPoints(); row.qtyFs:SetPoint("RIGHT", row, "RIGHT", ahColDefs[5].r, 0); row.qtyFs:SetWidth(58)
                    row.barTrack:ClearAllPoints()
                    row.barTrack:SetPoint("RIGHT", row.qtyFs, "LEFT", -8, 0)
                    row.barTrack:SetSize(64, 5)
                    local ratio = tonumber(row._qtyRatio) or 0
                    if ratio > 0 then
                        row.barTrack:Show()
                        row.barFill:ClearAllPoints()
                        row.barFill:SetPoint("LEFT", row.barTrack, "LEFT", 0, 0)
                        row.barFill:SetSize(math.max(3, math.floor(64 * ratio + 0.5)), 5)
                        row.barFill:Show()
                    else
                        row.barTrack:Hide()
                        row.barFill:Hide()
                    end
                end
            end
            if ahUsed == 0 and allAh.emptyFs then
                allAh.emptyFs:ClearAllPoints()
                allAh.emptyFs:SetPoint("TOPLEFT", allAh, "TOPLEFT", 12, rowsTopY - 4)
                allAh.emptyFs:SetSize(aw, 24)
            end

            local ahH = math.abs(rowsTopY) + math.max(1, ahUsed) * 24 + 12
            allAh:ClearAllPoints()
            allAh:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", 0, row4Y)
            allAh:SetSize(W, ahH)
            nextBottomY = row4Y - ahH
        end

        state.contentH = math.abs(nextBottomY) + 20
        updateScrollMetrics()
    end

    local function paintReturnButton()
        local a = app()
        local btn = state.header and state.header.returnBtn
        if not btn then return end
        local stack = a and a._deepAnalysisStack
        local lbl
        if stack and #stack > 0 then
            local parentTarget = stack[#stack]
            local pTitle = truncateText(getTargetTitle(parentTarget, nil), 18)
            lbl = "< Back to " .. pTitle
        else
            local ret = a and a._deepAnalysisReturn
            local tabName = ret and ret.tab and TAB_RETURN_LABELS[ret.tab]
            lbl = tabName and ("< Back to " .. tabName) or "< Return"
        end
        btn:SetText(lbl)
        local w = math.max(96, math.min(196, #lbl * 7 + 26))
        btn:SetWidth(w)
    end

    local function paintWindowButtons(win)
        local left = state.leftCard
        if not left then return end
        local is24 = (win == "24h")
        if left.win24Btn and left.win24Btn.SetActive then left.win24Btn:SetActive(is24) end
        if left.win7dBtn and left.win7dBtn.SetActive then left.win7dBtn:SetActive(not is24) end
    end

    local function formatProfLabel(profKey)
        if not profKey or profKey == "" then return nil end
        local key = tostring(profKey)
        local h = H() or host
        if h and h.PROF_LABELS and h.PROF_LABELS[key] then
            return tostring(h.PROF_LABELS[key])
        end
        if h and h.PROF_META and h.PROF_META[key] and h.PROF_META[key].label then
            return tostring(h.PROF_META[key].label)
        end
        local formatted = key:gsub("_", " "):gsub("(%a)([%w']*)", function(a, b)
            return a:upper() .. b:lower()
        end)
        return formatted
    end

    local function formatRepLabel(r, rec)
        local lbl = r and (r.repLabel or r.repText)
        if type(lbl) == "string" then
            lbl = stripCodes(lbl):match("^%s*(.-)%s*$")
            if lbl ~= "" and lbl ~= "-" and lbl ~= "0" then
                local fac = r and type(r.repFactionName) == "string" and stripCodes(r.repFactionName) or nil
                if fac and fac ~= "" and not lbl:find(fac, 1, true) then
                    return fac .. " (" .. lbl .. ")"
                end
                return lbl
            end
        end
        local repVal = rec and rec.rep
        if type(repVal) == "number" and repVal > 0 then
            local h = H() or host
            local standing = (h and h.REP_LABELS and h.REP_LABELS[repVal])
                or (h and h.STANDING_NAMES and h.STANDING_NAMES[repVal])
            return standing and tostring(standing) or tostring(repVal)
        elseif type(repVal) == "string" and repVal ~= "" and repVal ~= "0" and repVal ~= "-" then
            return stripCodes(repVal)
        end
        return nil
    end

    local function buildSubtitle(target, data)
        local kind = target.kind or "recipe"
        local r = target.row or {}
        local rec = target.recipe or r.recipe
        local parts = {}
        if kind == "recipe" and rec then
            local prof = formatProfLabel(r.prof or rec.prof)
            if prof and prof ~= "" then
                local sk = tonumber(r.skill or rec.skill)
                parts[#parts + 1] = sk and (prof .. " (" .. tostring(sk) .. ")") or prof
            end
            local sy, sg, sgr = tonumber(r.skillYellow or rec.yellow), tonumber(r.skillGreen or rec.green), tonumber(r.skillGray or rec.gray)
            if sy or sg or sgr then
                parts[#parts + 1] = "Y/G/Gr " .. tostring(sy or "-") .. "/" .. tostring(sg or "-") .. "/" .. tostring(sgr or "-")
            end
            local h = H() or host
            local lo, hi
            if h and h.ResolveRecipeYieldRange then
                lo, hi = h.ResolveRecipeYieldRange(rec)
            end
            local made = tonumber(r.numMade or rec.numMade) or 1
            local ys = (rec.spellID and ns.Store and ns.Store.GetCraftYieldStats) and ns.Store.GetCraftYieldStats(rec.spellID) or nil
            if lo and hi and hi > lo then
                local rng = string.format("Makes %d-%dx", lo, hi)
                if ys and (tonumber(ys.casts) or 0) > 0 then
                    rng = rng .. string.format(" · Measured %.2fx (%d)", ys.avg or 0, ys.casts or 0)
                end
                parts[#parts + 1] = rng
            elseif ys and (tonumber(ys.casts) or 0) > 0 then
                parts[#parts + 1] = string.format("Makes %dx · Measured %.2fx (%d)", made, ys.avg or 0, ys.casts or 0)
            else
                parts[#parts + 1] = "Makes " .. tostring(made) .. "x"
            end
            local ab = r.craftAbility
            if ab then
                if ab.known then parts[#parts + 1] = "Known"
                elseif ab.knownAltName then parts[#parts + 1] = "Alt: " .. tostring(ab.knownAltName)
                elseif ab.knownOnAlt then parts[#parts + 1] = "Known on Alt"
                else parts[#parts + 1] = "Unlearned" end
            elseif r.known then
                parts[#parts + 1] = "Known"
            end
            if r.cdText and r.cdText ~= "" and r.cdText ~= "-" then
                parts[#parts + 1] = "CD: " .. stripCodes(r.cdText)
            end
            local repDisplay = formatRepLabel(r, rec)
            if repDisplay then
                parts[#parts + 1] = "Rep: " .. repDisplay
            end
        elseif data and data.subtitle and data.subtitle ~= "" then
            parts[#parts + 1] = stripCodes(data.subtitle)
            if data.badge and data.badge ~= "" then
                table.insert(parts, 1, stripCodes(data.badge))
            end
        else
            local id = getTargetItemID(target)
            parts[#parts + 1] = "Market Item"
            if id then parts[#parts + 1] = "Item #" .. tostring(id) end
            local own = getOwnedTotal(id)
            parts[#parts + 1] = "Owned " .. daNum(own)
        end
        return table.concat(parts, " · ")
    end

    local function formatOverviewValue(row)
        local kind = row.valueKind
        if kind == "signed_money" then return daMoney(row.liveValue, true)
        elseif kind == "money" or kind == "cost_money" then
            local suffix = row.valueSuffix or ""
            return daMoney(row.liveValue, false) .. suffix
        elseif kind == "rate" then return daRate(row.liveValue)
        elseif kind == "int" then return row.liveValue ~= nil and daNum(row.liveValue) or "-"
        elseif kind == "demand" then
            return stripCodes(row.badgeText or row.stateLabel or (row.liveValue and string.format("%.2fx", row.liveValue) or "-"))
        end
        return row.liveValue ~= nil and tostring(row.liveValue) or "-"
    end

    function DeepAnalysis.Render(target, preserveScroll)
        if not ensureBuilt() then return false end
        if not target then return false end
        local h = H() or host
        local a = app()
        local pal = daPal()
        local econKey, econInfo = getActiveEcon()

        state.dirtyThemeRender = false
        local win = (db().quickLookWindow == "24h") and "24h" or "7d"
        state.window = win
        state.target = target
        local kind = target.kind or "recipe"
        local itemID = getTargetItemID(target)

        local r = target.row or {}
        local rec = target.recipe or r.recipe
        local applyAHCut = not _G.MerchantMasterDB or _G.MerchantMasterDB.applyAHCut ~= false
        local priceVer = (h and h.priceCacheEpoch) or 0
        local dualCacheKey = tostring(kind) .. "|" .. tostring(itemID or 0) .. "|"
            .. tostring(rec and rec.spellID or 0) .. "|" .. tostring(econKey or "") .. "|"
            .. tostring(priceVer) .. "|" .. tostring(applyAHCut)

        local qlData, ql24, ql7d
        if kind == "item" then
            qlData = buildItemDeepData(target, itemID, econKey)
        elseif h and h.RecipeStats and h.RecipeStats.BuildQuickLook and target.row then
            local function buildForWin(w)
                local ctx = {}
                for k, v in pairs(target.context or {}) do ctx[k] = v end
                ctx.kind = kind
                ctx.window = w
                return h.RecipeStats.BuildQuickLook(target.row, ctx)
            end
            if state.qlDualCache and state.qlDualCache.key == dualCacheKey then
                ql24 = state.qlDualCache.ql24
                ql7d = state.qlDualCache.ql7d
                if win == "24h" then
                    if not ql24 then ql24 = buildForWin("24h"); state.qlDualCache.ql24 = ql24 end
                    qlData = ql24
                else
                    if not ql7d then ql7d = buildForWin("7d"); state.qlDualCache.ql7d = ql7d end
                    qlData = ql7d
                end
            else
                ql24 = buildForWin("24h")
                ql7d = buildForWin("7d")
                state.qlDualCache = { key = dualCacheKey, ql24 = ql24, ql7d = ql7d }
                qlData = (win == "24h") and ql24 or ql7d
            end
        end
        if not qlData and itemID then
            qlData = buildItemDeepData(target, itemID, econKey)
        end
        state.data = qlData

        local title = getTargetTitle(target, qlData)
        local icon = getTargetIcon(target, qlData)
        state.titleText = title

        -- Header
        local hdr = state.header
        paintReturnButton()
        hdr.icon:SetTexture(icon)
        hdr.titleFs:SetText(title)
        hdr.subtitleFs:SetText(buildSubtitle(target, qlData))
        syncFavButton()

        -- Right action buttons
        if kind == "writ" then
            hdr.addBtn:SetText("+ Queue Writ")
        elseif kind == "forged" then
            hdr.addBtn:SetText("+ Queue Forged")
        else
            local curQty = (kind == "recipe" and target.row and a and a.getRecipeShoppingQty and a.getRecipeShoppingQty(target.row)) or 0
            hdr.addBtn:SetText(curQty > 0 and ("+ Add (" .. tostring(curQty) .. ")") or "+ Add to Cart")
        end

        local srcInfo = qlData and (qlData.scrollInfo or qlData.sourceInfo)
        state.wowheadCA = srcInfo and srcInfo.wowheadCA or nil
        local hasWowhead = (srcInfo and srcInfo.wowheadURL and srcInfo.wowheadURL ~= "") and true or false
        hdr.wowheadBtn:SetShown(hasWowhead)
        hdr.searchBtn:ClearAllPoints()
        if hasWowhead then
            hdr.searchBtn:SetPoint("RIGHT", hdr.wowheadBtn, "LEFT", -6, 0)
        else
            hdr.searchBtn:SetPoint("RIGHT", hdr, "RIGHT", -10, 0)
        end

        -- Gather shared market metrics for KPIs + right cards
        local dep24 = (itemID and h and h.GetAHListingDeposit) and h.GetAHListingDeposit(itemID, 2, 1) or (qlData and qlData.dep24)
        local vendorFloor = (itemID and h and h.GetVendorSellPrice) and h.GetVendorSellPrice(itemID) or (qlData and qlData.vendorSell)
        local snapPrice, snapRec = nil, nil
        if itemID and h and h.QueryLocalSnapshot then
            snapPrice, snapRec = h.QueryLocalSnapshot(itemID, econKey)
        end
        local sellerInfo = (itemID and h and h.SellerStats and h.SellerStats.Get)
            and h.SellerStats.Get(itemID, econKey)
            or { status = "unavailable", display = "n/a", reason = "No seller search recorded." }
        local ownedOut = getOwnedTotal(itemID)
        local scrollID = (qlData and qlData.scrollID) or (rec and rec.recipeItemID)
        local ownedScroll = (kind == "recipe" and scrollID and scrollID > 0) and getOwnedTotal(scrollID) or 0
        local md = r.marketDemand or (qlData and qlData.marketDemand)
            or (itemID and h and h.GetMultiSourceDemand and h.GetMultiSourceDemand(itemID, econKey))
        local mdPrimary = md and (md.effectiveDailySold ~= nil and tonumber(md.effectiveDailySold)
            or (md.dailySold ~= nil and tonumber(md.dailySold) or nil)) or nil
        local liveListed = (qlData and qlData.liveListed) or r.listed
        local liveSales = mdPrimary
        if liveSales == nil then liveSales = (qlData and qlData.liveSalesPerDay) or r.salesPerDay or resolveDemandRate(md) end
        local demandInfo = (qlData and qlData.demandInfo) or r.demand
        local heatLabel = demandInfo and stripCodes(demandInfo.heatShort or demandInfo.heatBadge or demandInfo.stateLabel or "") or "No signal"
        local salesSrc = resolveDemandSource(md) or (qlData and qlData.salesSource) or r.demandSource or r.salesScope or r.salesSource or "Market"

        -- Row 1: 5 KPI Cards
        local hasSnaps = hasSnapshotUI()
        local k1, k2, k3, k4, k5 = state.kpiCards[1], state.kpiCards[2], state.kpiCards[3], state.kpiCards[4], state.kpiCards[5]
        if kind == "recipe" then
            local made = math.max(1, tonumber(qlData and qlData.made or r.numMade or (rec and rec.numMade)) or 1)
            local profitVal = (tonumber(r.profit) and tonumber(r.profit) * made) or (qlData and qlData.net and qlData.net.last)
            local costVal = (tonumber(r.craftCost) and tonumber(r.craftCost) * made) or (qlData and qlData.cost and qlData.cost.last)
            local sellVal = tonumber(r.unitAH or r.ahPrice or r.targetPrice) or (qlData and qlData.output and qlData.output.last)
            local marginPct = (profitVal and costVal and costVal > 0) and (profitVal / costVal * 100) or tonumber(r.marginPct)
            k1.titleFs:SetText("NET PROFIT / CRAFT")
            k1.valueFs:SetText(daMoney(profitVal, true))
            k1._valColorKey = (profitVal and profitVal > 0) and "accentGreen" or ((profitVal and profitVal < 0) and "accentRed" or "text")
            setTextColor(k1.valueFs, pal[k1._valColorKey] or pal.text)
            k1.subFs:SetText("Margin " .. (marginPct and daPct(marginPct, false) or "-")
                .. " · AH " .. (applyAHCut and "5%" or "Off")
                .. " · Dep " .. (dep24 and daMoney(dep24) or "-"))

            k2.titleFs:SetText("SELL PRICE")
            k2.valueFs:SetText(daMoney(sellVal, false))
            k2._valColorKey = "text"
            setTextColor(k2.valueFs, pal.text)
            if hasSnaps then
                local snapVal = (snapRec and snapRec.marketValue) or snapPrice
                k2.subFs:SetText("Vendor " .. (vendorFloor and daMoney(vendorFloor) or "-")
                    .. " · Snap " .. (snapVal and daMoney(snapVal) or "-"))
            else
                k2.subFs:SetText("Vendor " .. (vendorFloor and daMoney(vendorFloor) or "-")
                    .. " · Live AH")
            end

            k3.titleFs:SetText("CRAFT COST")
            k3.valueFs:SetText(daMoney(costVal, false))
            k3._valColorKey = "text"
            setTextColor(k3.valueFs, pal.text)
            local costPct = qlData and qlData.cost and qlData.cost.pct
            local reagCount = qlData and qlData.movers and #qlData.movers or (rec and rec.reagents and #rec.reagents or 0)
            k3.subFs:SetText(win .. " " .. (costPct and daPct(costPct, true) or "-")
                .. " · " .. tostring(reagCount) .. (reagCount == 1 and " reagent" or " reagents"))
        elseif kind == "writ" or kind == "crate" or kind == "forged" then
            local kpis = (qlData and qlData.kpis) or {}
            local netVal = (kpis[1] and kpis[1].value) or (qlData and qlData.net and qlData.net.last)
            local refundVal = (kpis[2] and kpis[2].value) or 0
            local scrollVal = qlData and qlData.scrollCost
            k1.titleFs:SetText((kpis[1] and kpis[1].label or "NET COST"):upper())
            k1.valueFs:SetText(daMoney(netVal, false))
            k1._valColorKey = "text"
            setTextColor(k1.valueFs, pal.text)
            k1.subFs:SetText(stripCodes((kpis[1] and kpis[1].sub) or ("Mode: " .. tostring(qlData and qlData.meta and qlData.meta.mode or "-"))))

            k2.titleFs:SetText(kind == "writ" and "WRIT SCROLL" or "EMPTY CRATE")
            k2.valueFs:SetText(daMoney(scrollVal, false))
            k2._valColorKey = "text"
            setTextColor(k2.valueFs, pal.text)
            k2.subFs:SetText("Refund +" .. daMoney(refundVal, false))

            k3.titleFs:SetText("COMPONENT COST")
            local compVal = qlData and qlData.cost and qlData.cost.last
            k3.valueFs:SetText(daMoney(compVal, false))
            k3._valColorKey = "text"
            setTextColor(k3.valueFs, pal.text)
            local moverCount = qlData and qlData.movers and #qlData.movers or 0
            k3.subFs:SetText((kpis[3] and stripCodes(kpis[3].sub) or win) .. " · " .. tostring(moverCount) .. " parts")
        else
            local livePrice = qlData and qlData.output and qlData.output.last
            k1.titleFs:SetText("MARKET PRICE")
            k1.valueFs:SetText(daMoney(livePrice, false))
            k1._valColorKey = "text"
            setTextColor(k1.valueFs, pal.text)
            k1.subFs:SetText("Dep 24h " .. (dep24 and daMoney(dep24) or "-") .. " · " .. (econInfo and econInfo.label or "Active AH"))

            if hasSnaps then
                local snapVal = (snapRec and snapRec.marketValue) or snapPrice
                local snapMin = snapRec and snapRec.minBuyout
                k2.titleFs:SetText("SNAPSHOT & VENDOR")
                k2.valueFs:SetText(daMoney(snapVal, false))
                k2._valColorKey = "text"
                setTextColor(k2.valueFs, pal.text)
                k2.subFs:SetText("Vendor " .. (vendorFloor and daMoney(vendorFloor) or "-")
                    .. " · Min " .. (snapMin and daMoney(snapMin) or "-"))

                local hmLocal = (itemID and h and h.Pricing and h.Pricing.GetItemHeatmap) and h.Pricing.GetItemHeatmap(itemID, econKey) or nil
                local ov = hmLocal and hmLocal.overall
                k3.titleFs:SetText("WEEKLY AVERAGE")
                k3.valueFs:SetText(daMoney(ov and ov.avgPrice or livePrice, false))
                k3._valColorKey = "text"
                setTextColor(k3.valueFs, pal.text)
                k3.subFs:SetText(ov and ("CV " .. daPct(ov.cvPct, false) .. " · " .. daNum(ov.totalSamples) .. " samples")
                    or "No 7x24 snapshot range yet")
            else
                k2.titleFs:SetText("VENDOR & DEPOSIT")
                k2.valueFs:SetText(daMoney(vendorFloor, false))
                k2._valColorKey = "text"
                setTextColor(k2.valueFs, pal.text)
                k2.subFs:SetText("24h Dep " .. (dep24 and daMoney(dep24) or "-") .. " · Live AH")

                local obsCount = qlData and qlData.output and qlData.output.count or 0
                k3.titleFs:SetText("LIVE AH HISTORY")
                k3.valueFs:SetText(daMoney(livePrice, false))
                k3._valColorKey = "text"
                setTextColor(k3.valueFs, pal.text)
                k3.subFs:SetText(obsCount > 0 and (daNum(obsCount) .. " scan points · Live AH")
                    or "Scan AH to build history")
            end
        end

        k4.titleFs:SetText("SALES / DAY")
        k4.valueFs:SetText(daRate(liveSales))
        k4._valColorKey = (liveSales and liveSales > 0) and "textBlue" or "text"
        setTextColor(k4.valueFs, pal[k4._valColorKey] or pal.text)
        k4.subFs:SetText(heatLabel .. " · " .. salesSrc)

        k5.titleFs:SetText("COMPETITION")
        k5.valueFs:SetText(liveListed ~= nil and (daNum(liveListed) .. " listed") or "No AH count")
        k5._valColorKey = "text"
        setTextColor(k5.valueFs, pal.text)
        local ownSub = "Own " .. daNum(ownedOut) .. (ownedScroll > 0 and (" · Scrolls " .. daNum(ownedScroll)) or "")
        k5.subFs:SetText("Sellers " .. tostring(sellerInfo.display or "n/a") .. " · " .. ownSub)

        -- Row 1.5: Dual Side-by-Side 24h & 7d Charts Strip (DA.chartsRow)
        local series24, series7d = {}, {}
        local pct24, pct7d = nil, nil
        local title24, title7d = "24h Price Trend", "7d Price Trend"
        if kind == "item" then
            series24, pct24, series7d, pct7d = buildItemChartSeries(itemID, econKey)
            title24 = "24h Market Price"
            title7d = "7d Market Price"
        else
            series24 = extractDualChartSeries(ql24 or qlData) or {}
            series7d = extractDualChartSeries(ql7d or qlData) or {}
            pct24 = (ql24 and ((ql24.output and ql24.output.pct) or (ql24.cost and ql24.cost.pct))) or nil
            pct7d = (ql7d and ((ql7d.output and ql7d.output.pct) or (ql7d.cost and ql7d.cost.pct))) or nil
            local hasDual24 = (#series24 >= 2)
            local hasDual7d = (#series7d >= 2)
            title24 = hasDual24 and "24h Price vs Cost" or "24h Trend"
            title7d = hasDual7d and "7d Price vs Cost" or "7d Trend"
        end
        local pts24 = countMaxPoints(series24)
        local pts7d = countMaxPoints(series7d)
        state.charts24Pts = pts24
        state.charts7dPts = pts7d

        local liveRefPrice = (kind == "recipe" and tonumber(r.unitAH or r.ahPrice or r.targetPrice))
            or (qlData and qlData.output and tonumber(qlData.output.last))
            or (itemID and h and h.GetItemMarketPrice and h.GetItemMarketPrice(itemID))
            or snapPrice
        if pts24 >= 2 or pts7d >= 2 then
            state.chartsCollapsed = false
            if state.chart24h then
                if pts24 >= 2 then
                    local sum24 = (pct24 ~= nil and daPct(pct24, true) or (tostring(pts24) .. " pts"))
                    if #series24 >= 2 then sum24 = "Sell / Cost  " .. sum24 end
                    state.chart24h:SetData(series24, {
                        title = title24,
                        summary = sum24,
                        preserveColor = true,
                        preserveOrder = true,
                    })
                else
                    state.chart24h:SetData({}, {
                        title = title24,
                        emptyText = "Need 2+ AH scans for 24h trend",
                    })
                end
            end
            if state.chart7d then
                if pts7d >= 2 then
                    local sum7d = (pct7d ~= nil and daPct(pct7d, true) or (tostring(pts7d) .. " pts"))
                    if #series7d >= 2 then sum7d = "Sell / Cost  " .. sum7d end
                    state.chart7d:SetData(series7d, {
                        title = title7d,
                        summary = sum7d,
                        preserveColor = true,
                        preserveOrder = true,
                    })
                else
                    state.chart7d:SetData({}, {
                        title = title7d,
                        emptyText = "Need 2+ daily scans for 7d trend",
                    })
                end
            end
        else
            state.chartsCollapsed = true
            if state.chart24h then state.chart24h:Clear() end
            if state.chart7d then state.chart7d:Clear() end
            if state.baselineCard then
                state.baselineCard.stripFs:SetText(
                    "Vendor Floor " .. daMoney(vendorFloor, false)
                    .. " -> Live AH " .. daMoney(liveRefPrice, false)
                    .. " -> 24h Deposit " .. daMoney(dep24, false)
                )
                state.baselineCard.hintFs:SetText("Run 2+ AH scans over time to plot 24h & 7d trends")
            end
        end

        -- Row 2: Concept B Split Timing Drawer (only when snapshots / snapshot extension active)
        if hasSnaps then
            if state.ensureTimingDrawer then state.ensureTimingDrawer() end
            if state.timingDrawer and state.timingDrawer.SetItem then
                local df = state.timingDrawer.frame or state.timingDrawer
                if df and df.Show then df:Show() end
                if state.timingDrawer.Layout then
                    local mainW = state.viewportW or (a and a.ui and a.ui.deepAnalysisView and a.ui.deepAnalysisView:GetWidth()) or 1060
                    if mainW <= 100 then mainW = 1060 end
                    local drawerW = math.max(480, math.floor(mainW - 18))
                    state.timingDrawer:Layout(drawerW, 415, true)
                end
                local hm = (itemID and h and h.Pricing and h.Pricing.GetItemHeatmap) and h.Pricing.GetItemHeatmap(itemID, econKey) or nil
                state.timingDrawer:SetItem(itemID, hm, qlData, econKey)
            end
        else
            if state.timingDrawer then
                local df = state.timingDrawer.frame or state.timingDrawer
                if df and df.Hide then df:Hide() end
            end
            if state.timingPlaceholder then
                state.timingPlaceholder:Hide()
            end
        end

        -- Row 2.5 (optional): Proposal A Vendor Yield & Material Buy Caps Card
        local vc = state.vcCard
        state.vcRow = nil
        state.vcCapUsed = 0
        state.vcHistBuckets = {}
        state.vcHistMaxCount = 0
        local loMade = tonumber(r.minMade or (rec and rec.numMade) or 1) or 1
        local hiMade = tonumber(r.maxMade or (rec and rec.numMade) or 1) or 1
        local ys = (rec and rec.spellID and ns.Store and ns.Store.GetCraftYieldStats)
            and ns.Store.GetCraftYieldStats(rec.spellID) or nil
        if kind == "recipe" and rec then
            if h and h.ResolveRecipeYieldRange then
                local rLo, rHi = h.ResolveRecipeYieldRange(rec)
                if rLo and rHi then loMade, hiMade = rLo, rHi end
            end
            if type(ys) == "table" and tonumber(ys.minSeen) and ys.minSeen > 0 and rec.prof ~= "cooking" then
                loMade = math.min(loMade, math.floor(ys.minSeen + 0.5))
            end
            if type(ys) == "table" and tonumber(ys.maxSeen) and ys.maxSeen > 0 and rec.prof ~= "cooking" then
                hiMade = math.max(hiMade, math.floor(ys.maxSeen + 0.5))
            end
            local vcRow = (r and (r.moat ~= nil or r.reagentBuyCaps ~= nil or r.yieldSource ~= nil)) and r or nil
            if not vcRow and h and h.VendorCrafterModel and h.VendorCrafterModel.EvaluateRecipe then
                vcRow = h.VendorCrafterModel.EvaluateRecipe(rec, {
                    economy = econKey,
                    subCraftMode = db().subCraftMode or "smart",
                    subCraftOverrides = db().subCraftOverrides,
                    yieldMode = db().vendorCrafterYieldMode or "auto",
                    masterChefMode = db().vendorCrafterMasterChef,
                    barteringMode = db().vendorCrafterBartering,
                    honoredDiscount = db().vendorCrafterHonored,
                    profMap = target.context and target.context.profMap,
                    ownedCounts = target.context and target.context.ownedCounts,
                }, nil, {})
            end
            local hasHist = (type(ys) == "table" and (tonumber(ys.casts) or 0) > 0)
            local isVar = (hiMade > loMade) or (vcRow and vcRow.isVariableYield == true)
            if vc and (vcRow ~= nil or isVar or hasHist) then
                state.vcRow = vcRow
                local src = (vcRow and vcRow.yieldSource) or (hasHist and "measured" or (isVar and "uniform" or "fixed"))
                local badgeTxt, badgeKey
                if hasHist and src == "measured" then
                    badgeTxt = string.format("Measured Ledger Avg (%.2fx, %d casts)", ys.avg or 0, ys.casts or 0)
                    badgeKey = "accentGreen"
                elseif isVar then
                    badgeTxt = (src == "min")
                        and string.format("Conservative Min (%d-%dx range)", loMade, hiMade)
                        or string.format("Uniform Midpoint (%d-%dx%s)", loMade, hiMade, hasHist and string.format(" · %d/10 casts", ys.casts or 0) or "")
                    badgeKey = "textBlue"
                else
                    badgeTxt = hasHist and string.format("Ledger Measured (%d casts)", ys.casts or 0) or "Vendor Arbitrage Active"
                    badgeKey = "accentGreen"
                end
                vc._badgeColKey = badgeKey
                vc.badgeFs:SetText(badgeTxt)
                setTextColor(vc.badgeFs, pal[badgeKey] or pal.accentGreen or pal.text)

                if vcRow then
                    local costTxt = daMoney(vcRow.craftCost, false)
                    local minTxt = daMoney(vcRow.minVendor, false) .. " (" .. daMoney(vcRow.minProfit, true) .. ")"
                    local avgTxt = daMoney(vcRow.avgVendor, false) .. " (" .. daMoney(vcRow.avgProfit, true) .. ")"
                    local maxTxt = daMoney(vcRow.maxVendor, false) .. " (" .. daMoney(vcRow.maxProfit, true) .. ")"
                    local capCrafts = (vcRow.profitableCrafts == math.huge) and "Inf"
                        or (vcRow.profitableCrafts and (daNum(vcRow.profitableCrafts) .. "x") or "-")
                    local capProf = (vcRow.totalProfitCap == math.huge) and "Unlimited" or daMoney(vcRow.totalProfitCap, true)
                    vc.spreadFs:SetText(string.format("Craft %s  ·  Min %s  ·  Avg %s  ·  Max %s  ·  Optimal %s (%s)",
                        costTxt, minTxt, avgTxt, maxTxt, capCrafts, capProf))
                else
                    local vSell = vendorFloor or (h and h.GetVendorSellPrice and h.GetVendorSellPrice(itemID)) or 0
                    vc.spreadFs:SetText(string.format("Output %d-%dx  ·  Vendor %s ea (%s .. %s/craft)  ·  Vendor sell below AH cost",
                        loMade, hiMade, daMoney(vSell, false), daMoney(loMade * vSell, false), daMoney(hiMade * vSell, false)))
                end

                local capEntries = {}
                if vcRow and type(vcRow.moat) == "table" and type(vcRow.moat.reagents) == "table" then
                    for _, rg in ipairs(vcRow.moat.reagents) do
                        if type(rg) == "table" and not rg.isVendor and tonumber(rg.itemID) and rg.itemID > 0 then
                            capEntries[#capEntries + 1] = {
                                itemID = rg.itemID,
                                name = rg.name,
                                qty = rg.qty or 1,
                                maxBuy = rg.maxProfitableUnitPrice or rg.unitCost,
                                breakEven = rg.breakEvenPrice,
                                wall = rg.wallUnitPrice,
                            }
                        end
                    end
                elseif vcRow and type(vcRow.reagentBuyCaps) == "table" then
                    for rid, cp in pairs(vcRow.reagentBuyCaps) do
                        if tonumber(rid) and rid > 0 and type(cp) == "table" then
                            capEntries[#capEntries + 1] = {
                                itemID = rid,
                                name = h and h.ItemName and h.ItemName(rid) or ("Item #" .. tostring(rid)),
                                qty = cp.qty or 1,
                                maxBuy = cp.maxBuyUnit,
                                breakEven = cp.breakEvenUnit,
                                wall = cp.wallUnit,
                            }
                        end
                    end
                    table.sort(capEntries, function(x, y) return tostring(x.name or "") < tostring(y.name or "") end)
                end

                local capUsed = 0
                for _, ce in ipairs(capEntries) do
                    capUsed = capUsed + 1
                    local crow = ensureVcCapRow(capUsed)
                    local mid = tonumber(ce.itemID)
                    local mIcon = (mid and h and h.ItemIcon and h.ItemIcon(mid)) or (h and h.QUESTION_ICON) or 134400
                    local mName = ce.name or (mid and h and h.ItemName and h.ItemName(mid)) or "Reagent"
                    crow.itemID = mid
                    crow.itemName = mName
                    crow.itemIcon = mIcon
                    crow.clickable = (mid and mid > 0) and true or false
                    crow.icon:SetTexture(mIcon)
                    crow.nameFs:SetText(string.format("%s (%gx)", mName, tonumber(ce.qty) or 1))
                    setTextColor(crow.nameFs, crow.clickable and (pal.textBlue or pal.accentBlue or pal.text) or pal.text)
                    local wallStr = (ce.wall and ce.wall > 0) and (" · Wall " .. daMoney(ce.wall, false)) or ""
                    local beStr = (ce.breakEven and ce.breakEven > 0) and (" · BE " .. daMoney(ce.breakEven, false)) or ""
                    crow.capFs:SetText("Max <= " .. daMoney(ce.maxBuy, false) .. beStr .. wallStr)
                    local liveP = mid and h and h.GetItemMarketPrice and h.GetItemMarketPrice(mid) or nil
                    if liveP and ce.maxBuy and ce.maxBuy > 0 and liveP > ce.maxBuy then
                        crow._statusColKey = "accentRed"
                        crow.statusFs:SetText("OVER")
                    else
                        crow._statusColKey = "accentGreen"
                        crow.statusFs:SetText("OK")
                    end
                    setTextColor(crow.statusFs, pal[crow._statusColKey] or pal.accentGreen or pal.text)
                    crow:Show()
                end
                state.vcCapUsed = capUsed
                for i = capUsed + 1, #(state.vcCapRows or {}) do
                    state.vcCapRows[i]:Hide()
                end
                if capUsed == 0 then
                    vc.capEmptyFs:SetText((vcRow and vcRow.isAllVendor)
                        and "Vendor-only craft (unlimited NPC supply with Bartering/Honored discounts)."
                        or "No profitable vendor buy caps (vendor sell below current craft cost).")
                    vc.capEmptyFs:Show()
                else
                    vc.capEmptyFs:Hide()
                end

                local histTbl = (hasHist and type(ys.hist) == "table") and ys.hist
                    or (vcRow and type(vcRow.yieldHist) == "table" and vcRow.yieldHist) or nil
                local uAvg = (vcRow and vcRow.yieldUniformAvg) or ((loMade + hiMade) / 2)
                if hasHist and histTbl then
                    local bMin, bMax = loMade, hiMade
                    for k, cnt in pairs(histTbl) do
                        local kn = tonumber(k)
                        if kn and (tonumber(cnt) or 0) > 0 then
                            bMin = math.min(bMin, math.floor(kn + 0.5))
                            bMax = math.max(bMax, math.floor(kn + 0.5))
                        end
                    end
                    local buckets, maxCnt = {}, 0
                    if (bMax - bMin + 1) <= 12 then
                        for b = bMin, bMax do
                            local c = tonumber(histTbl[b]) or 0
                            if c > maxCnt then maxCnt = c end
                            buckets[#buckets + 1] = { val = b, count = c }
                        end
                    else
                        local keys = {}
                        for k, cnt in pairs(histTbl) do
                            local kn = tonumber(k)
                            if kn and (tonumber(cnt) or 0) > 0 then keys[#keys + 1] = math.floor(kn + 0.5) end
                        end
                        table.sort(keys)
                        for idx = 1, math.min(12, #keys) do
                            local b = keys[idx]
                            local c = tonumber(histTbl[b]) or 0
                            if c > maxCnt then maxCnt = c end
                            buckets[#buckets + 1] = { val = b, count = c }
                        end
                    end
                    state.vcHistBuckets = buckets
                    state.vcHistMaxCount = maxCnt
                    local peakCol = pal.accentGreen or pal.positive or { 0.18, 0.85, 0.45, 1 }
                    local baseBarCol = pal.mode == "light"
                        and { peakCol[1], peakCol[2], peakCol[3], 0.55 }
                        or { peakCol[1], peakCol[2], peakCol[3], 0.48 }
                    for i = 1, 12 do
                        local barSlot = vc.histBars[i]
                        local bSpec = buckets[i]
                        if barSlot and bSpec then
                            local isPeak = (maxCnt > 0 and bSpec.count == maxCnt)
                            barSlot._isPeak = isPeak
                            barSlot.countFs:SetText(tostring(bSpec.count))
                            barSlot.lblFs:SetText(tostring(bSpec.val) .. "x")
                            setTextColor(barSlot.countFs, isPeak and peakCol or pal.textSecondary)
                            setTextColor(barSlot.lblFs, pal.textMuted)
                            local col = isPeak and peakCol or baseBarCol
                            barSlot.barTex:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
                        end
                    end
                    vc.histMetaFs:SetText(string.format("Avg %.2fx (%d) vs %.2fx uniform", ys.avg or 0, ys.casts or 0, uAvg))
                else
                    state.vcHistBuckets = {}
                    state.vcHistMaxCount = 0
                    vc.histMetaFs:SetText(string.format("Uniform %.2fx (0 casts)", uAvg))
                end

                vc:Show()
            elseif vc then
                vc:Hide()
            end
        elseif vc then
            vc:Hide()
        end

        -- Disenchanting Analysis Card (disenchantable gear + crafted items)
        local de = state.deCard
        local deTargetLink = target.link or r.outputLink or (rec and rec.outputLink)
        local deBD = (de and itemID and itemID > 0 and h and h.GetItemDEBreakdown)
            and h.GetItemDEBreakdown(itemID, deTargetLink, applyAHCut) or nil
        if de and deBD and type(deBD.outcomes) == "table" and #deBD.outcomes > 0 then
            local deRow = nil
            local hasNet = (deBD.netCopper ~= nil and deBD.netCopper > 0)
            if kind == "recipe" and hasNet then
                if r.avgDE ~= nil and type(r.deOutcomes) == "table" then
                    deRow = r
                elseif rec and h and h.DisenchantCrafterModel and h.DisenchantCrafterModel.EvaluateRecipe then
                    deRow = h.DisenchantCrafterModel.EvaluateRecipe(rec, {
                        economy = econKey,
                        applyAHCut = applyAHCut,
                        arcaneSalvager = (db().disenchantCrafterArcaneSalvager == true),
                        subCraftMode = db().subCraftMode or "smart",
                        subCraftOverrides = db().subCraftOverrides,
                        barteringMode = db().disenchantCrafterBartering,
                        honoredDiscount = db().disenchantCrafterHonored,
                        profMap = target.context and target.context.profMap,
                        ownedCounts = target.context and target.context.ownedCounts,
                    }, nil, {})
                end
            end
            state.deRow = deRow

            local asActive = (db().disenchantCrafterArcaneSalvager == true)
            local baseNetDE = hasNet and (deBD.netCopper or deBD.grossCopper or (deRow and deRow.avgDE)) or nil
            local asDE = hasNet and (deBD.asNetCopper or (baseNetDE and math.floor(baseNetDE * 1.20 + 0.5))) or nil
            local netDE = (asActive and asDE) or baseNetDE
            local baseMinDE = hasNet and (deBD.minNetCopper or deBD.minGrossCopper or (deRow and deRow.minDE) or baseNetDE) or nil
            local baseMaxDE = hasNet and (deBD.maxNetCopper or deBD.maxGrossCopper or (deRow and deRow.maxDE) or baseNetDE) or nil
            local minDE = (asActive and baseMinDE) and math.floor(baseMinDE * 1.20 + 0.5) or baseMinDE
            local maxDE = (asActive and baseMaxDE) and math.floor(baseMaxDE * 1.20 + 0.5) or baseMaxDE
            local craftC = (deRow and tonumber(deRow.craftCost)) or (kind == "recipe" and tonumber(r.craftCost)) or (kind == "recipe" and qlData and qlData.cost and tonumber(qlData.cost.last)) or nil
            local deProfit = (craftC and netDE) and (netDE - craftC) or (deRow and tonumber(deRow.avgProfit)) or nil
            local deMargin = (deProfit and craftC and craftC > 0) and (deProfit / craftC * 100) or (deRow and tonumber(deRow.marginPct)) or nil

            local qualPrefix = tostring(deBD.qualityName or "Uncommon")
            local ilvlStr = (deBD.ilvl and deBD.ilvl > 0) and ("iLvl " .. tostring(deBD.ilvl) .. " ") or ""
            local classStr = tostring(deBD.className or "Gear")
            if deProfit ~= nil then
                de._badgeColKey = (deProfit > 0) and "accentGreen" or "accentRed"
                de.badgeFs:SetText(qualPrefix .. " · " .. ilvlStr .. classStr .. " · " .. (deProfit > 0 and "Profitable DE" or "DE Loss"))
            elseif not hasNet then
                de._badgeColKey = "textMuted"
                de.badgeFs:SetText(qualPrefix .. " · " .. ilvlStr .. classStr .. " · Unpriced")
            else
                de._badgeColKey = "textBlue"
                de.badgeFs:SetText(qualPrefix .. " · " .. ilvlStr .. classStr)
            end
            setTextColor(de.badgeFs, pal[de._badgeColKey] or pal.textBlue or pal.text)

            local learnedSuffix = (deBD.learnedCasts and deBD.learnedCasts > 0)
                and ("  ·  Learned: " .. tostring(deBD.learnedCasts) .. " casts")
                or ""
            if not hasNet then
                de.summaryFs:SetText("DE EV Unpriced  ·  Outcomes shown below (awaiting tracked material prices)" .. learnedSuffix)
            elseif craftC ~= nil and deProfit ~= nil then
                local capSuffix = ""
                if deRow and deRow.profitableCrafts and deRow.profitableCrafts > 0 and deRow.totalProfitCap then
                    local capCrafts = (deRow.profitableCrafts == math.huge) and "Inf" or (daNum(deRow.profitableCrafts) .. "x")
                    capSuffix = string.format("  ·  Optimal %s (%s)", capCrafts, daMoney(deRow.totalProfitCap, true))
                end
                local asSuffix = asActive
                    and (baseNetDE and ("  ·  AS (+20% Active; Base " .. daMoney(baseNetDE, false) .. ")") or "  ·  AS (+20% Active)")
                    or (asDE and ("  ·  AS (+20%) " .. daMoney(asDE, false)) or "")
                de.summaryFs:SetText(string.format("Craft %s  ·  DE EV %s (%s%s)%s  ·  Roll %s .. %s%s%s",
                    daMoney(craftC, false), daMoney(netDE, false), daMoney(deProfit, true),
                    deMargin and (" · " .. daPct(deMargin, false)) or "",
                    asSuffix, daMoney(minDE, false), daMoney(maxDE, false), capSuffix, learnedSuffix))
            else
                local asSuffix = asActive
                    and (baseNetDE and ("  ·  AS (+20% Active; Base " .. daMoney(baseNetDE, false) .. ")") or "  ·  AS (+20% Active)")
                    or (asDE and ("  ·  AS (+20%) " .. daMoney(asDE, false)) or "")
                de.summaryFs:SetText(string.format("DE EV %s (%s)%s  ·  Min Roll %s  ·  Max Roll %s%s",
                    daMoney(netDE, false), applyAHCut and "net 5% AH" or "gross",
                    asSuffix, daMoney(minDE, false), daMoney(maxDE, false), learnedSuffix))
            end

            local isBoP = (rec and rec.bop) or (deRow and deRow.isBoP)
                or (h and h.IsItemSoulbound and h.IsItemSoulbound(itemID))
                or (h and h.RECIPE_BOP and h.RECIPE_BOP[itemID])
                or false
            local rawAH = (not isBoP) and ((kind == "recipe" and tonumber(r.unitAH or r.ahPrice or r.targetPrice)) or (qlData and qlData.output and tonumber(qlData.output.last))) or nil
            local ahNet = (rawAH and rawAH > 0) and (applyAHCut and math.floor(rawAH * 0.95 + 0.5) or rawAH) or nil
            local vSell = (vendorFloor and vendorFloor > 0) and vendorFloor or nil
            local bestLabel, bestVal = netDE and "DE" or "None", netDE or -1
            if ahNet and ahNet > bestVal then
                bestLabel, bestVal = "AH", ahNet
            end
            if vSell and vSell > bestVal then
                bestLabel, bestVal = "Vendor", vSell
            end
            de._exitColKey = (bestLabel == "DE") and "accentGreen" or "textSecondary"
            setTextColor(de.exitFs, pal[de._exitColKey] or pal.textSecondary)
            de.exitFs:SetText(string.format("Best Exit: %s (%s)  ·  AH Net %s  ·  DE EV %s  ·  Vendor %s",
                bestLabel, (bestVal >= 0) and daMoney(bestVal, false) or "-",
                ahNet and daMoney(ahNet, false) or (isBoP and "BoP" or "-"),
                netDE and daMoney(netDE, false) or "Unpriced",
                vSell and daMoney(vSell, false) or "-"))

            local deUsed = 0
            for _, oc in ipairs(deBD.outcomes) do
                deUsed = deUsed + 1
                local drow = ensureDeOutcomeRow(deUsed)
                local mid = tonumber(oc.matID)
                local mIcon = (mid and h and h.ItemIcon and h.ItemIcon(mid)) or (h and h.QUESTION_ICON) or 134400
                local mName = oc.name or (mid and h and h.ItemName and h.ItemName(mid)) or "Material"
                drow.itemID = mid
                drow.itemName = mName
                drow.itemIcon = mIcon
                drow.clickable = (mid ~= nil and mid > 0) and true or false
                drow.icon:SetTexture(mIcon)
                drow.nameFs:SetText(drow.clickable and (mName .. " >") or mName)
                setTextColor(drow.nameFs, drow.clickable and (pal.textBlue or pal.accentBlue or pal.text) or pal.text)
                local minA = tonumber(oc.minAmount) or 1
                local maxA = tonumber(oc.maxAmount) or minA
                local amtSpan = (minA == maxA) and (tostring(minA) .. "x") or (tostring(minA) .. "-" .. tostring(maxA) .. "x")
                local pctStr = (h and h.FormatDEChancePct) and h.FormatDEChancePct(oc.matRate) or string.format("%.1f", (tonumber(oc.matRate) or 0) * 100)
                drow.chanceFs:SetText(string.format("%s%%  ·  %s (%.2f)", pctStr, amtSpan, tonumber(oc.amountOfMats) or minA))
                setTextColor(drow.chanceFs, pal.textSecondary)
                drow.unitFs:SetText("@ " .. daMoney(oc.unitPrice, false))
                setTextColor(drow.unitFs, pal.text)
                local evVal = oc.evNet or oc.evGross
                drow.evFs:SetText(evVal and ("EV " .. daMoney(evVal, false)) or "-")
                setTextColor(drow.evFs, pal.text)
                if drow.sep then
                    local sep = pal.separator or pal.border or { 1, 1, 1, 0.14 }
                    drow.sep:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.4) * 0.55)
                end
                drow:Show()
            end
            state.deOutcomeUsed = deUsed
            for i = deUsed + 1, #(state.deOutcomeRows or {}) do
                state.deOutcomeRows[i]:Hide()
            end
            if de.matEmptyFs then
                de.matEmptyFs:SetShown(deUsed == 0)
            end
            de:Show()
        elseif de then
            state.deRow = nil
            state.deOutcomeUsed = 0
            de:Hide()
        end

        -- Row 3 Left Card: Economy Bar Card + Overview + Full Reagents / Linked Recipes
        paintWindowButtons(win)
        local left = state.leftCard
        left.hdrTitle:SetText(kind == "item" and "MARKET OVERVIEW" or "CRAFT & MARKET OVERVIEW")

        if left.econBarCard then
            local ec = left.econBarCard
            if kind == "recipe" then
                local made = math.max(1, tonumber(qlData and qlData.made or r.numMade or (rec and rec.numMade)) or 1)
                local costVal = (tonumber(r.craftCost) and tonumber(r.craftCost) * made) or (qlData and qlData.cost and qlData.cost.last) or 0
                local sellUnit = tonumber(r.unitAH or r.ahPrice or r.targetPrice) or (qlData and qlData.output and qlData.output.last) or 0
                local grossSale = sellUnit * made
                local netSale = applyAHCut and math.floor(grossSale * 0.95 + 0.5) or grossSale
                local profitVal = (tonumber(r.profit) and tonumber(r.profit) * made) or (qlData and qlData.net and qlData.net.last) or (netSale - costVal)
                local marginPct = (costVal and costVal > 0 and profitVal) and (profitVal / costVal * 100) or tonumber(r.marginPct)
                local maxBar = math.max(1, costVal or 0, netSale or 0, math.abs(profitVal or 0))

                local b1, b2, b3 = ec.craftBars[1], ec.craftBars[2], ec.craftBars[3]
                b1._ratio = (costVal and costVal > 0) and (costVal / maxBar) or 0
                b1._colorKey = "accentOrange"
                b1._valColorKey = "text"
                b1.valFs:SetText(daMoney(costVal, false))

                b2._ratio = (netSale and netSale > 0) and (netSale / maxBar) or 0
                b2._colorKey = "accentBlue"
                b2._valColorKey = "text"
                b2.valFs:SetText(daMoney(netSale, false))

                b3._ratio = (profitVal and profitVal ~= 0) and (math.abs(profitVal) / maxBar) or 0
                b3._colorKey = (profitVal and profitVal < 0) and "accentRed" or "accentGreen"
                b3._valColorKey = b3._colorKey
                b3.valFs:SetText(daMoney(profitVal, true) .. (marginPct and (" (" .. daPct(marginPct, false) .. ")") or ""))

                ec.craftFrame:Show()
                ec.rangeFrame:Hide()
            else
                local avg7d = nil
                if series7d and series7d[1] and series7d[1].points and #series7d[1].points > 0 then
                    local sum, cnt = 0, 0
                    for _, pt in ipairs(series7d[1].points) do
                        local pv = tonumber(pt.value)
                        if pv and pv > 0 then sum = sum + pv; cnt = cnt + 1 end
                    end
                    if cnt > 0 then avg7d = math.floor(sum / cnt + 0.5) end
                end
                if not avg7d then
                    avg7d = (snapRec and snapRec.marketValue) or snapPrice or liveRefPrice
                end
                local vFloor = (vendorFloor and vendorFloor > 0) and vendorFloor or nil
                local vLive = (liveRefPrice and liveRefPrice > 0) and liveRefPrice or nil
                local vAvg = (avg7d and avg7d > 0) and avg7d or nil
                ec.rangeLabels[1]:SetText("Vendor " .. (vFloor and daMoney(vFloor, false) or "-"))
                ec.rangeLabels[2]:SetText("Live AH " .. (vLive and daMoney(vLive, false) or "-"))
                ec.rangeLabels[3]:SetText("7d Avg " .. (vAvg and daMoney(vAvg, false) or "-"))

                local minV, maxV = nil, nil
                for _, v in ipairs({ vFloor, vLive, vAvg }) do
                    if v then
                        minV = minV and math.min(minV, v) or v
                        maxV = maxV and math.max(maxV, v) or v
                    end
                end
                local span = (minV and maxV and maxV > minV) and (maxV - minV) or nil
                local function norm(v, fallbackFrac)
                    if not v then return nil end
                    if not span then return fallbackFrac end
                    return (v - minV) / span
                end
                ec._markerFracs = { norm(vFloor, 0.1), norm(vLive, 0.5), norm(vAvg, 0.9) }
                ec._markerColorKeys = { "textMuted", "accentBlue", "accentOrange" }

                ec.craftFrame:Hide()
                ec.rangeFrame:Show()
            end
        end

        local ovList = (qlData and qlData.overviewRows) or {}
        for i = 1, 6 do
            local rowFrame = left.overviewRows[i]
            local spec = ovList[i]
            if spec then
                rowFrame.labelFs:SetText(tostring(spec.label or "-"))
                rowFrame.qtyFs:SetText(tostring(spec.qtyText or ""))
                rowFrame.valueFs:SetText(formatOverviewValue(spec))
                local pct = spec.series and spec.series.pct
                if spec.fixed then
                    rowFrame.deltaFs:SetText(spec.tag or "FIXED")
                    rowFrame._deltaColKey = "textMuted"
                elseif pct ~= nil then
                    rowFrame.deltaFs:SetText(daPct(pct, true))
                    local good = spec.lowerIsBetter and (pct < 0) or (not spec.lowerIsBetter and pct > 0)
                    local bad = spec.lowerIsBetter and (pct > 0) or (not spec.lowerIsBetter and pct < 0)
                    rowFrame._deltaColKey = good and "accentGreen" or (bad and "accentRed" or "textMuted")
                else
                    rowFrame.deltaFs:SetText("-")
                    rowFrame._deltaColKey = "textMuted"
                end
                setTextColor(rowFrame.deltaFs, pal[rowFrame._deltaColKey] or pal.textMuted)
                local days = spec.series and (spec.series.days or spec.series.count)
                rowFrame.covFs:SetText((days and days > 0) and (tostring(days) .. (win == "24h" and "h" or "d")) or "-")
                rowFrame:Show()
            else
                rowFrame:Hide()
            end
        end

        local movers = (qlData and qlData.movers) or {}
        local linked = (kind == "item" and qlData and qlData.linkedRecipes) or nil
        local used = 0
        if kind ~= "item" then
            left.reagTitle:SetText("REAGENTS & MOVERS BREAKDOWN (" .. tostring(#movers) .. " | click market item to inspect)")
            local totalExt = 0
            if kind == "recipe" then
                for _, m in ipairs(movers) do
                    local mQty = tonumber(m.qty) or 1
                    local mUnit = tonumber(m.unitPrice) or (m.series and m.series.last)
                    if mUnit and mUnit > 0 and mQty > 0 then
                        totalExt = totalExt + (mUnit * mQty)
                    end
                end
            end
            for idx, m in ipairs(movers) do
                used = used + 1
                local row = ensureReagentRow(used)
                local mid = tonumber(m.itemID or (m.item and m.item.itemID))
                local mQty = tonumber(m.qty) or 1
                local mUnit = tonumber(m.unitPrice) or (m.series and m.series.last)
                local mExt = (mUnit and mQty) and (mUnit * mQty) or nil
                local isVendor = (m.pureVendor == true) or (m.fixed == true)
                local mName = m.name or (mid and h and h.ItemName and h.ItemName(mid)) or "Reagent"
                local mIcon = m.icon or (mid and h and h.ItemIcon and h.ItemIcon(mid)) or (h and h.QUESTION_ICON) or 134400
                local mOwn = mid and getOwnedTotal(mid) or 0
                local mListed = mid and h and h.GetNumListed and h.GetNumListed(mid)

                row.itemID = mid
                row.itemName = mName
                row.itemIcon = mIcon
                row.drillRecipe = nil
                row.clickable = (mid ~= nil and mid > 0 and not m.pureVendor) and true or false
                row.icon:SetTexture(mIcon)
                row.nameFs:SetText(row.clickable and (mName .. " >") or mName)
                setTextColor(row.nameFs, row.clickable and (pal.textBlue or pal.accentBlue or pal.text) or pal.text)
                row.qtyFs:SetText(tostring(mQty) .. "x")
                row.unitFs:SetText(daMoney(mUnit, false))

                if kind == "recipe" and mExt and mExt > 0 and totalExt > 0 then
                    local sharePct = math.max(0, math.min(100, math.floor((mExt / totalExt) * 100 + 0.5)))
                    row._hasShareBar = true
                    row._shareRatio = math.max(0.03, math.min(1, mExt / totalExt))
                    row._shareColorKey = isVendor and "textMuted" or (sharePct >= 45 and "accentOrange" or "accentBlue")
                    row.extFs:SetText(daMoney(mExt, false) .. " (" .. tostring(sharePct) .. "%)")
                else
                    row._hasShareBar = false
                    row._shareRatio = nil
                    if row.shareTrack then row.shareTrack:Hide() end
                    if row.shareFill then row.shareFill:Hide() end
                    row.extFs:SetText(daMoney(mExt, false))
                end

                if isVendor then
                    row.tagFs:SetText("VENDOR")
                    row._tagColKey = "textMuted"
                elseif m.deltaPct ~= nil then
                    row.tagFs:SetText(daPct(m.deltaPct, true))
                    row._tagColKey = (m.deltaPct < 0) and "accentGreen" or ((m.deltaPct > 0) and "accentRed" or "textMuted")
                else
                    row.tagFs:SetText(m.role or "-")
                    row._tagColKey = "textMuted"
                end
                setTextColor(row.tagFs, pal[row._tagColKey] or pal.textMuted)
                row.stockFs:SetText(daNum(mOwn) .. " / " .. (mListed ~= nil and daNum(mListed) or "-"))
                row:Show()
            end
        else
            left.reagTitle:SetText("RELATED CATALOG RECIPES (" .. tostring(linked and #linked or 0) .. " | click to inspect craft)")
            for _, entry in ipairs(linked or {}) do
                used = used + 1
                local row = ensureReagentRow(used)
                local lrec = entry.recipe
                local oid = lrec.outputItemID
                local rName = lrec.name or (oid and h and h.ItemName and h.ItemName(oid)) or "Recipe"
                local rIcon = (oid and h and h.ItemIcon and h.ItemIcon(oid)) or (h and h.QUESTION_ICON) or 134400
                local rPrice = oid and h and h.GetItemMarketPrice and h.GetItemMarketPrice(oid)
                row.itemID = oid
                row.itemName = rName
                row.itemIcon = rIcon
                row.drillRecipe = lrec
                row.clickable = true
                row._hasShareBar = false
                row._shareRatio = nil
                if row.shareTrack then row.shareTrack:Hide() end
                if row.shareFill then row.shareFill:Hide() end
                row.icon:SetTexture(rIcon)
                row.nameFs:SetText(rName .. " >")
                setTextColor(row.nameFs, pal.textBlue or pal.accentBlue or pal.text)
                row.qtyFs:SetText(tostring(entry.qty or 1) .. "x")
                row.unitFs:SetText(daMoney(rPrice, false))
                row.extFs:SetText(formatProfLabel(lrec.prof) or "-")
                row.tagFs:SetText(tostring(entry.role or "Recipe"))
                row._tagColKey = "textMuted"
                setTextColor(row.tagFs, pal.textMuted)
                row.stockFs:SetText(oid and daNum(getOwnedTotal(oid)) or "-")
                row:Show()
            end
        end
        state.reagentUsedCount = used
        for i = used + 1, #state.reagentRows do
            state.reagentRows[i]:Hide()
        end
        left.reagEmptyFs:SetShown(used == 0)
        if used == 0 then
            left.reagEmptyFs:SetText(kind == "item" and "Standalone market item - no linked catalog recipes." or "No reagents listed.")
        end

        -- Row 3 Right Column Card 1: Competition, Velocity & Quality
        state.compCard._activeTier = resolveHeatTier(heatLabel, demandInfo, liveSales)
        if state.compCard.heatStripFrame then
            local hsf = state.compCard.heatStripFrame
            local strip24h = (itemID and h and h.Pricing and type(h.Pricing.GetItemHeatStrip24h) == "function")
                and h.Pricing.GetItemHeatStrip24h(itemID, econKey) or nil
            if (not strip24h or type(strip24h.hourly) ~= "table")
                and itemID and h and h.Pricing and type(h.Pricing.GetItemHeatmap) == "function" then
                local hmObj = h.Pricing.GetItemHeatmap(itemID, econKey)
                if type(hmObj) == "table" and type(hmObj.hourly) == "table" then
                    strip24h = {
                        hourly = hmObj.hourly,
                        avgPrice = hmObj.avgPrice,
                        medianPrice = hmObj.medianPrice,
                        updatedAt = hmObj.updatedAt,
                        hasLiveOverlay = hmObj.hasLiveOverlay,
                    }
                end
            end
            local hasHourlyData = false
            if type(strip24h) == "table" and type(strip24h.hourly) == "table" then
                for hr = 0, 23 do
                    local raw = strip24h.hourly[hr]
                    local v = (type(raw) == "table") and tonumber(raw.avgPrice) or tonumber(raw)
                    if v and v > 0 then hasHourlyData = true; break end
                end
            end
            if hasHourlyData and hsf.strip24h then
                local nowHr = tonumber(dateFn and dateFn("!%H")) or 12
                hsf._mode = "snapshot"
                hsf._stripData = strip24h
                hsf._nowHour = nowHr
                hsf.strip24h:Bind(strip24h, pal, nowHr)
                hsf.spectrumBar:Hide()
                local srcLbl = (salesSrc and salesSrc ~= "") and tostring(salesSrc) or "Snapshot"
                hsf.captionFs:SetText("24h Heatmap | Cold (Buy) -> Hot (Sell) | " .. srcLbl)
            else
                hsf._mode = "spectrum"
                hsf._stripData = nil
                if hsf.strip24h then hsf.strip24h:Clear() end
                hsf.spectrumBar:Show()
                local tierIdx = state.compCard._activeTier or 1
                local sRate = tonumber(liveSales)
                local frac
                if tierIdx >= 4 then
                    frac = 0.88
                elseif tierIdx == 3 then
                    frac = (sRate and sRate > 0) and (0.62 + math.min(0.20, math.log(1 + sRate / 15) * 0.14)) or 0.72
                elseif tierIdx == 2 then
                    frac = (sRate and sRate > 0) and (0.34 + math.min(0.22, (sRate / 15) * 0.22)) or 0.45
                else
                    frac = (sRate and sRate > 0) and (0.10 + math.min(0.18, (sRate / 2) * 0.18)) or 0.10
                end
                hsf._heatFrac = frac
                local tierSpec = HEAT_TIERS[tierIdx] or HEAT_TIERS[1]
                local rateTxt = (sRate ~= nil) and (daRate(sRate) .. "/day") or "Unscanned"
                hsf.captionFs:SetText("Sales Heat | " .. tierSpec.label .. " (" .. rateTxt .. ")")
            end
            hsf:Show()
        end
        local compLines = {}
        local mutedHex = daHex(pal, "hexMuted")
        local textHex = daHex(pal, "hexText")
        local blueHex = daHex(pal, "hexBlue")
        local greenHex = daHex(pal, "hexGreen")
        local orangeHex = daHex(pal, "hexOrange", "hexWarning")

        local whyText = stripCodes(r.goodFull or r.goodPlain or (rec and (rec.goodFull or rec.good)) or "")
        if whyText ~= "" then
            compLines[#compLines + 1] = mutedHex .. "Why It Sells:|r " .. textHex .. whyText .. "|r"
        end
        local bisText = stripCodes(r.bisInfo or (rec and rec.bis) or "")
        if bisText ~= "" then
            compLines[#compLines + 1] = mutedHex .. "BiS / Rank:|r " .. blueHex .. bisText .. "|r"
        end
        local effText = stripCodes(r.effectText or (rec and rec.effect) or "")
        if effText ~= "" then
            compLines[#compLines + 1] = mutedHex .. "Forever Effect:|r " .. textHex .. effText .. "|r"
        end
        local velParts = {}
        velParts[#velParts + 1] = "Sales/Day " .. daRate(liveSales) .. (salesSrc and salesSrc ~= "" and (" (" .. tostring(salesSrc) .. ")") or "")
        if md then
            local personalRate = tonumber(md.personalDailySold)
            if personalRate and personalRate > 0 then
                velParts[#velParts + 1] = "Personal " .. daRate(personalRate)
            end
            local snapRate = tonumber(md.snapDailySold)
            if snapRate ~= nil then
                local obsH = tonumber(md.snapObsHours) or tonumber(md.velocityObsHours)
                velParts[#velParts + 1] = "Realm " .. daRate(snapRate) .. ((obsH and obsH > 0) and (" (" .. daNum(obsH) .. "h)") or "")
            end
        end
        compLines[#compLines + 1] = mutedHex .. "Velocity:|r " .. textHex .. table.concat(velParts, " | ") .. "|r"
        local sellerDisplay = tostring(sellerInfo.display or "")
        if sellerDisplay == "" or sellerDisplay:lower() == "n/a" then
            sellerDisplay = "Unscanned"
        end
        local sellerStatus = tostring(sellerInfo.status or "unscanned")
        if sellerStatus == "unavailable" then sellerStatus = "unscanned" end
        compLines[#compLines + 1] = mutedHex .. "Seller Stats:|r " .. textHex .. sellerDisplay
            .. " (" .. sellerStatus .. ")"
            .. (liveListed ~= nil and (" | " .. daNum(liveListed) .. " listed on AH") or "") .. "|r"
        state.compCard.bodyFs:SetText(table.concat(compLines, "\n"))

        -- Row 3 Right Column Card 2: Personal Ledger & Cross-Alt Inventory
        local lc = state.ledgerCard
        local detail = (itemID and ns.Model and ns.Model.GetItemDetail)
            and ns.Model.GetItemDetail(itemID, { char = "all", period = "all", faction = "all", source = "all" })
            or nil
        local w7 = (detail and detail.windows and detail.windows.d7) or {}
        local w30 = (detail and detail.windows and detail.windows.d30) or {}
        local wAll = (detail and detail.windows and detail.windows.all) or {}
        local allSold = tonumber(wAll.sold) or 0
        local allBought = tonumber(wAll.bought) or 0
        local hasTrades = (detail ~= nil) and (allSold > 0 or allBought > 0)
        lc._hasTrades = hasTrades

        if hasTrades then
            local p7 = tonumber(w7.profit) or 0
            local p30 = tonumber(w30.profit) or 0
            local pAll = tonumber(wAll.profit) or 0
            local maxAbs = math.max(1, math.abs(p7), math.abs(p30), math.abs(pAll))
            local horizons = {
                { profit = p7,   sold = tonumber(w7.sold) or 0 },
                { profit = p30,  sold = tonumber(w30.sold) or 0 },
                { profit = pAll, sold = allSold },
            }
            for i, hz in ipairs(horizons) do
                local cf = lc.horizonCols[i]
                if cf then
                    cf._ratio = math.abs(hz.profit) / maxAbs
                    cf._colorKey = (hz.profit < 0) and "accentRed" or "accentGreen"
                    cf._valColorKey = (hz.profit ~= 0) and cf._colorKey or "textSecondary"
                    cf.valFs:SetText(daMoney(hz.profit, true))
                end
            end
            lc.horizonFrame:Show()
            lc.emptyTradesFs:Hide()

            local sr = tonumber(detail.saleRate) or 0
            local srClamped = math.max(0, math.min(1, sr))
            local isSlowing = (detail.isSlowing == true)
            local slowStr = isSlowing and ("Slowing (" .. decimal(detail.slowRatio or 0) .. "x)") or "Healthy"
            lc.saleRateRow._frac = srClamped
            lc.saleRateRow._colorKey = isSlowing and "accentOrange" or "accentGreen"
            lc.saleRateRow.lblFs:SetText("180d Sale Rate: " .. percent(sr)
                .. " | Exp " .. daNum(detail.expSinceSale or 0)
                .. " | Can " .. daNum(detail.canSinceSale or 0)
                .. " | " .. slowStr)
            if lc.saleRateRow.bar then
                lc.saleRateRow.bar:SetValue(srClamped, pal[lc.saleRateRow._colorKey] or pal.accentGreen)
            end
            lc.saleRateRow:Show()
        else
            lc.horizonFrame:Hide()
            lc.saleRateRow:Hide()
            lc.emptyTradesFs:SetText("No personal AH trades recorded yet")
            lc.emptyTradesFs:Show()
        end

        local inv = (detail and type(detail.inventory) == "table") and detail.inventory or nil
        local qBags = inv and (tonumber(inv.bags) or 0) or (tonumber(ownedOut) or 0)
        local qBank = inv and (tonumber(inv.bank) or 0) or 0
        local qMail = inv and (tonumber(inv.mail) or 0) or 0
        local qAH = inv and (tonumber(inv.ah) or 0) or 0
        local qTotal = inv and (tonumber(inv.total) or (qBags + qBank + qMail + qAH)) or (qBags + qBank + qMail + qAH)
        local stockSpecs = {
            { "Bags", qBags },
            { "Bank", qBank },
            { "Mail", qMail },
            { "AH",   qAH },
        }
        for i, sp in ipairs(stockSpecs) do
            local ch = lc.stockChips[i]
            if ch then
                ch._qty = sp[2]
                ch.lblFs:SetText(sp[1] .. " " .. daNum(sp[2]))
            end
        end
        local ledgerLines = {
            mutedHex .. "Owned:|r " .. textHex
                .. "Bags " .. daNum(qBags) .. " | Bank " .. daNum(qBank)
                .. " | Mail " .. daNum(qMail) .. " | AH " .. daNum(qAH)
                .. " (Total " .. daNum(qTotal) .. ")"
                .. (hasTrades and (" | Sold 7d " .. daNum(w7.sold or 0) .. " / All " .. daNum(allSold)) or "")
                .. (ownedScroll > 0 and (" | Scrolls " .. daNum(ownedScroll)) or "") .. "|r"
        }
        local deBrokenQty = detail and (tonumber(detail.deBrokenQty) or 0) or 0
        local deSoldMatsQty = detail and (tonumber(detail.deSoldMatsQty) or 0) or 0
        local deIndirectProfit = detail and (tonumber(detail.deIndirectProfit) or 0) or 0
        if deBrokenQty > 0 or deIndirectProfit ~= 0 then
            local deLine = mutedHex .. "Indirect via Disenchant:|r " .. textHex
                .. "DE'd " .. daNum(deBrokenQty) .. "x -> Sold mats"
                .. (deSoldMatsQty > 0 and (" (" .. formatDeQty(deSoldMatsQty) .. "x)") or "")
                .. ":|r " .. daMoney(deIndirectProfit, true)
                .. mutedHex .. " (counted on sold mat)|r"
            ledgerLines[#ledgerLines + 1] = deLine
        end
        lc.bodyFs:SetText(table.concat(ledgerLines, "\n"))

        -- Row 3 Right Column Card 3: Acquisition, Scroll, Skill & Cooldown
        local ac = state.acqCard
        local pillSpecs = {}
        local acqLines = {}
        if kind == "recipe" then
            ac.titleFs:SetText("ACQUISITION, SCROLL, SKILL & COOLDOWN")
            local whereStr = stripCodes((qlData and qlData.scrollInfo and qlData.scrollInfo.whereToBuy) or r.sourceLabel or "Trainer / AH")
            local srcShort = truncateText(r.sourceLabel or whereStr, 18)
            pillSpecs[#pillSpecs + 1] = { "neutral", srcShort }

            local ab = r.craftAbility or {}
            if ab.known then
                pillSpecs[#pillSpecs + 1] = { "positive", "Known" }
            elseif ab.knownAltName then
                pillSpecs[#pillSpecs + 1] = { "blue", "Alt: " .. truncateText(ab.knownAltName, 14) }
            elseif ab.knownOnAlt then
                pillSpecs[#pillSpecs + 1] = { "blue", "Alt Known" }
            else
                pillSpecs[#pillSpecs + 1] = { "warning", "Unlearned" }
            end
            local repDisplay = formatRepLabel(r, rec)
            if repDisplay then
                pillSpecs[#pillSpecs + 1] = { "purple", "Rep: " .. truncateText(repDisplay, 18) }
            end
            if r.cdText and r.cdText ~= "" and r.cdText ~= "-" then
                pillSpecs[#pillSpecs + 1] = { "warning", "CD: " .. truncateText(stripCodes(r.cdText), 14) }
            end

            acqLines[#acqLines + 1] = mutedHex .. "Source:|r " .. textHex .. whereStr .. "|r"
            local sCost = qlData and qlData.scrollCost
            local sListed = qlData and qlData.scrollLiveListed
            local sFixed = qlData and qlData.scrollFixed
            local sBreak = qlData and qlData.scrollInfo and qlData.scrollInfo.breakEvenText
            acqLines[#acqLines + 1] = mutedHex .. "Recipe Scroll:|r " .. textHex
                .. (sCost and daMoney(sCost) or "Not tradeable")
                .. (sFixed and " (VENDOR)" or "")
                .. (sListed ~= nil and (" | " .. daNum(sListed) .. " AH") or "")
                .. (sBreak and (" | " .. sBreak) or "") .. "|r"
        elseif kind == "writ" or kind == "crate" or kind == "forged" then
            ac.titleFs:SetText("TURN-IN & MECHANICS")
            local meta = qlData and qlData.meta
            if meta then
                if meta.rep then pillSpecs[#pillSpecs + 1] = { "purple", "+" .. tostring(meta.rep) .. " Rep" } end
                if meta.tokens then pillSpecs[#pillSpecs + 1] = { "positive", "+" .. tostring(meta.tokens) .. " Favor" } end
                if meta.cdText then pillSpecs[#pillSpecs + 1] = { "warning", "CD " .. tostring(meta.cdText) } end
                if meta.mode then pillSpecs[#pillSpecs + 1] = { "neutral", tostring(meta.mode) } end
            end
            local whereStr = stripCodes((qlData and qlData.sourceInfo and qlData.sourceInfo.whereToBuy) or "")
            if whereStr ~= "" then
                acqLines[#acqLines + 1] = mutedHex .. "Mechanics:|r " .. textHex .. whereStr .. "|r"
            end
            if qlData and qlData.breakdown and qlData.breakdown ~= "" then
                acqLines[#acqLines + 1] = mutedHex .. "Breakdown:|r " .. textHex .. stripCodes(qlData.breakdown) .. "|r"
            end
            if #acqLines == 0 then
                acqLines[#acqLines + 1] = mutedHex .. "Source:|r " .. textHex .. "Turn-in objective|r"
            end
        else
            ac.titleFs:SetText(hasSnaps and "ITEM & SNAPSHOT METADATA" or "ITEM & MARKET METADATA")
            pillSpecs[#pillSpecs + 1] = { "neutral", "ID #" .. tostring(itemID or "-") }
            pillSpecs[#pillSpecs + 1] = { "neutral", "Vendor " .. (vendorFloor and stripCodes(daMoney(vendorFloor, false)) or "-") }
            pillSpecs[#pillSpecs + 1] = { "neutral", "Dep " .. (dep24 and stripCodes(daMoney(dep24, false)) or "-") }
            pillSpecs[#pillSpecs + 1] = { "blue", hasSnaps and "Snapshot" or "Live AH" }
            if hasSnaps then
                local sm = (h and h.Pricing and h.Pricing.GetSnapshotMeta) and h.Pricing.GetSnapshotMeta(econKey) or nil
                if sm then
                    acqLines[#acqLines + 1] = mutedHex .. "Source:|r " .. textHex .. tostring(sm.source or "local")
                        .. " | " .. tostring(sm.windowDays or "-") .. "d window | "
                        .. daNum(sm.itemCount) .. " items (" .. daNum(sm.heatmapCount) .. " heatmaps)|r"
                else
                    acqLines[#acqLines + 1] = mutedHex .. "Source:|r " .. mutedHex .. "No snapshot pack loaded for this economy yet.|r"
                end
            else
                acqLines[#acqLines + 1] = mutedHex .. "Source:|r " .. textHex .. "Live AH Scans (scan at an Auctioneer to build local history)|r"
            end
        end
        for i = 1, 4 do
            local p = ac.pills and ac.pills[i]
            local sp = pillSpecs[i]
            if p then
                if sp then
                    p:SetVariant(sp[1], sp[2])
                    p.frame:Show()
                else
                    p.frame:Hide()
                end
            end
        end
        ac.bodyFs:SetText(table.concat(acqLines, "\n"))

        paintVisualCards(pal)
        renderAllAhCard(itemID, econKey)

        if not preserveScroll then
            state.scrollOffset = 0
        end
        DeepAnalysis.Layout(state.viewportW, state.viewportH, true)
        if not preserveScroll then
            setScrollOffset(0)
        end

        if a and a.ui and a.ui.statusText then
            a.ui.statusText:SetText("Deep Analysis | " .. stripCodes(title)
                .. (econInfo and econInfo.label and (" | " .. econInfo.label) or ""))
        end
        return true
    end

    function DeepAnalysis.ShowTarget(target)
        return DeepAnalysis.Render(target, false)
    end

    function DeepAnalysis.Refresh()
        local a = app()
        if a and a._openingDeepAnalysis then return false end
        local tgt = (a and a._deepAnalysisTarget) or state.target
        if not tgt then return false end
        if state.built and not isRootVisible() then
            state.dirtyThemeRender = true
            return false
        end
        return DeepAnalysis.Render(tgt, true)
    end

    function DeepAnalysis.GetState()
        local a = app()
        return {
            built = state.built,
            target = state.target,
            data = state.data,
            window = state.window,
            scrollOffset = state.scrollOffset,
            dirtyThemeRender = state.dirtyThemeRender == true,
            favWatched = (state.header and state.header.favBtn and state.header.favBtn._watched) and true or false,
            chartsCollapsed = state.chartsCollapsed == true,
            charts24Pts = state.charts24Pts or 0,
            charts7dPts = state.charts7dPts or 0,
            vcShown = (state.vcCard and state.vcCard:IsShown()) and true or false,
            vcCapUsed = state.vcCapUsed or 0,
            vcHistBuckets = state.vcHistBuckets,
            deShown = (state.deCard and state.deCard:IsShown()) and true or false,
            deOutcomeCount = state.deOutcomeUsed or 0,
            allAhShown = (state.allAhCard and state.allAhCard:IsShown()) and true or false,
            allAhUsed = state.allAhUsedCount or 0,
            allAhFilter = state.allAhFilter,
            allAhSortCol = state.allAhSortCol,
            allAhSortAsc = state.allAhSortAsc,
            allAhRows = state.allAhRows,
            stackDepth = (a and a._deepAnalysisStack) and #a._deepAnalysisStack or 0,
        }
    end
end
