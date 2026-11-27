-- Merchant's single all-profession recipe list. Scrolling never evaluates economics.
local ADDON, ns = ...
if ns.SuperList then return end
local provider = {}; ns.SuperList = provider
local host, view, tbl, latest, evaluation, signature, rows, cancelBuild
local generation, pending, selectedKey = 0, false, nil
local buildState, reconcilePending, forceVersion = nil, false, 0
local metaDirty, metaPatch = false, nil
local repairPatch
local shiftActive = false
local uiCache = {
    metaEpoch = 0,
    prewarmSeq = 0,
    metaTargets = nil,
    builtPriceRev = nil,
    appleRoot = 'Interface\\AddOns\\' .. tostring(ADDON or 'MerchantMaster') .. '\\Assets\\apple\\',
}
function uiCache.curPriceRev()
    return (ns.GetPriceDataRevision and ns.GetPriceDataRevision())
        or (ns.GetEffectivePriceVersion and ns.GetEffectivePriceVersion())
        or ns.priceCacheEpoch or 0
end
function uiCache.snapshotsAvailable()
    if type(ns.HasSnapshots) == 'function' then
        return ns.HasSnapshots() == true
    end
    return (ns.app and ns.app.snapshotExtension ~= nil) and true or false
end
function uiCache.createFilterLRU(cap)
    local maxEntries = cap or 8
    local byKey = {}
    local tagsByKey = {}
    local order = {}
    return {
        get = function(_, key)
            local entry = byKey[key]
            if entry == nil then return nil end
            for i = #order, 1, -1 do
                if order[i] == key then
                    if i ~= #order then
                        table.remove(order, i)
                        order[#order + 1] = key
                    end
                    break
                end
            end
            return entry
        end,
        put = function(_, key, value, tags)
            if not key or value == nil then return end
            if byKey[key] ~= nil then
                byKey[key] = value
                tagsByKey[key] = tags
                for i = #order, 1, -1 do
                    if order[i] == key then
                        if i ~= #order then
                            table.remove(order, i)
                            order[#order + 1] = key
                        end
                        break
                    end
                end
                return
            end
            if #order >= maxEntries then
                local oldest = table.remove(order, 1)
                if oldest ~= nil then
                    byKey[oldest] = nil
                    tagsByKey[oldest] = nil
                end
            end
            byKey[key] = value
            tagsByKey[key] = tags
            order[#order + 1] = key
        end,
        evictWhere = function(_, pred)
            if type(pred) ~= 'function' then return end
            for i = #order, 1, -1 do
                local k = order[i]
                if pred(tagsByKey[k]) then
                    table.remove(order, i)
                    byKey[k] = nil
                    tagsByKey[k] = nil
                end
            end
        end,
        clear = function()
            for k in pairs(byKey) do byKey[k] = nil end
            for k in pairs(tagsByKey) do tagsByKey[k] = nil end
            for i = #order, 1, -1 do order[i] = nil end
        end,
    }
end
function uiCache.metaSensitivityTags(cf, col)
    cf = cf or 'all'
    return {
        ownSens = (cf ~= 'all' or col == 'ownedOutputQty' or col == 'ownedScrollQty' or col == 'canCraftSort' or col == 'canCraft'),
        cdSens = (cf == 'craftable_now' or col == 'cdSort' or col == 'cooldown'),
    }
end
function uiCache.makeLRUKey(sig, metaEpoch, fKey)
    return tostring(sig or '')..'|'..tostring(metaEpoch or 0)..'|'..tostring(fKey or '')
end
uiCache.filterLRU = uiCache.createFilterLRU(8)
local changes, itemChanges = {}, {}
local prepared={}
local presentSeq=0
local function later(fn) if C_Timer and C_Timer.After then C_Timer.After(0,fn) else fn() end end
local function clockMS()
    if debugprofilestop then return debugprofilestop() end
    return (GetTimePreciseSec and GetTimePreciseSec() or os and os.clock and os.clock() or GetTime and GetTime() or 0)*1000
end
local sources = {
    {key='all',label='All Sources'}, {key='merchant',label='Merchant'},
    {key='vendor',label='Vendor'}, {key='writ',label='Writ'}, {key='trainer',label='Trainer'},
    {key='ah',label='AH / World'}, {key='quest_drop',label='Quest / BoP'},
}
local MASTER_COLUMNS = {
    {key='name',label='Name',width=128,minWidth=128,grow=450,align='LEFT',hint='Name: click to search AH and preview shopping. Shift-click to quick-add. Click to pin the 7-day Quick Look.'},
    {key='knownSort',label='Known',width=48,minWidth=46,grow=28,align='CENTER',defaultAsc=false,hint='Known: whether you (or an alt in All Chars mode) have learned the recipe.'},
    {key='cdSort',label='CD',width=34,minWidth=29,grow=10,align='CENTER',defaultAsc=true,hint='CD: craft cooldown status. R = Ready, <H>h or <M>m = cooldown duration, - = no cooldown.'},
    {key='ownedOutputQty',label='Own',width=34,minWidth=32,grow=10,align='RIGHT',hint='Own: output quantity currently owned. Recipe scroll quantity and learned status are separate.'},
    {key='listed',label='Listed',width=40,minWidth=36,grow=12,align='RIGHT',defaultAsc=true,hint='Listed: active Auction House listings for the output item.'},
    {key='goodScore',label='Why It Sells',width=104,minWidth=104,grow=360,align='LEFT',defaultAsc=false,hint='Why It Sells: Best in Class, Writ Turn-In, Crate Mat, or regional buyer velocity.'},
    {key='buyCostCopper',label='Buy',width=62,minWidth=90,grow=12,align='RIGHT',hint='Buy Cost: one-time recipe acquisition. * marks an estimated Favor equivalent.'},
    {key='craftCost',label='Craft',width=62,minWidth=90,grow=12,align='RIGHT',hint='Craft Cost: per output unit, using existing reagent and subcraft valuation.'},
    {key='unitAH',label='AH',width=62,minWidth=90,grow=12,align='RIGHT',hint='AH Price: per output unit in the selected economy. Listed quantity is in the Listed column.'},
    {key='salesPerDay',label='Sales/d',width=58,minWidth=54,grow=14,align='RIGHT',hint='Sales/day: Personal seven-day velocity when covered; otherwise live AH scan velocity. Row tooltip shows scope and window.'},
    {key='turnoverPerDay',label='Turnover/d',width=66,minWidth=90,grow=12,align='RIGHT',hint='Turnover/day: estimated gross output revenue (Sales/day x AH Price), not realized ledger revenue.'},
    {key='demandSort',label='Heat',width=48,minWidth=48,grow=80,align='LEFT',hint='Heat: existing market demand classification. Personal slowing is a separate signal.'},
    {key='profit',label='Profit',width=64,minWidth=90,grow=14,align='RIGHT',defaultAsc=false,hint='Profit: per output unit, with the configured AH cut. Acquisition cost is not deducted per craft.'},
    {key='requiredSkill',label='Level',width=54,minWidth=62,grow=14,align='LEFT',hint='Level: profession abbreviation and required profession skill, not character level.'},
    {key='skillupSort',label='Y/G/Gr',width=74,minWidth=72,grow=18,align='CENTER',hint='Skill-Up Levels: Yellow / Green / Gray profession skill thresholds from 1-300 Leveling.'},
    {key='sourceLabel',label='Source',width=48,minWidth=46,grow=14,align='LEFT',hint='Source: recipe acquisition (Merchant, Vendor, Trainer, AH, Quest, Drop, Starter). Writ overlaps sources without duplicating recipes.'},
    {key='sourceCost',label='Src Cost',width=66,minWidth=90,grow=14,align='RIGHT',hint='Src Cost: actual copper or currency fee. Favor is Merchant Favor. Sorted by copper equivalent; unknown last.'},
    {key='repSort',label='Rep',width=46,minWidth=46,grow=52,align='LEFT',defaultAsc=true,hint='Rep: required faction reputation standing, if any.'},
    {key='bisSort',label='Best',width=40,minWidth=40,grow=12,align='RIGHT',defaultAsc=false,hint='Best: strongest within the catalog effect class, not highest profit or character equipment. n/a means no comparison.'},
    {key='wowheadURL',label='WH',width=28,minWidth=26,grow=8,align='CENTER',hint='Wowhead: copy the recipe item or spell URL with the existing Ctrl+C window.'},
}
local MASTER_BY_KEY={}
for _,col in ipairs(MASTER_COLUMNS) do MASTER_BY_KEY[col.key]=col end
local colEpoch=0
local appliedColSig=nil
local fallbackColConfig={order={},hidden={}}
for i,col in ipairs(MASTER_COLUMNS) do fallbackColConfig.order[i]=col.key end
local function getColumnDB()
    return (latest and latest.db) or _G.MerchantMasterDB
end
local function normalizeColumnConfig(db)
    local cfg
    if type(db)=='table' then
        if type(db.superListColumns)~='table' then db.superListColumns={} end
        cfg=db.superListColumns
    else
        cfg=fallbackColConfig
    end
    local seen={}
    local nextOrder={}
    if type(cfg.order)=='table' then
        for _,key in ipairs(cfg.order) do
            if type(key)=='string' and MASTER_BY_KEY[key] and not seen[key] then
                seen[key]=true
                nextOrder[#nextOrder+1]=key
            end
        end
    end
    for _,col in ipairs(MASTER_COLUMNS) do
        if not seen[col.key] then
            seen[col.key]=true
            nextOrder[#nextOrder+1]=col.key
        end
    end
    -- Keep Name pinned as the first column.
    if nextOrder[1]~='name' then
        local filtered={'name'}
        for _,k in ipairs(nextOrder) do if k~='name' then filtered[#filtered+1]=k end end
        nextOrder=filtered
    end
    cfg.order=nextOrder
    if type(cfg.hidden)~='table' then cfg.hidden={} end
    cfg.hidden.name=nil
    for k,v in pairs(cfg.hidden) do
        if not MASTER_BY_KEY[k] or v~=true then cfg.hidden[k]=nil end
    end
    return cfg
end
local function copyColumn(col)
    local copy={}
    for k,v in pairs(col) do copy[k]=v end
    return copy
end
local function getActiveColumnDefs(db)
    local cfg=normalizeColumnConfig(db)
    local active={}
    for _,key in ipairs(cfg.order) do
        if not cfg.hidden[key] then
            active[#active+1]=copyColumn(MASTER_BY_KEY[key])
        end
    end
    return active,cfg
end
local function colorHex(col,fallback)
    if type(col)~='table' then return fallback or 'ffffff' end
    local r=math.max(0,math.min(255,math.floor((col[1] or 1)*255+0.5)))
    local g=math.max(0,math.min(255,math.floor((col[2] or 1)*255+0.5)))
    local b=math.max(0,math.min(255,math.floor((col[3] or 1)*255+0.5)))
    return string.format('%02x%02x%02x',r,g,b)
end
local cachedMode, cachedPal, cachedGreenHex
local function getThemePalette()
    local T=ns.Theme
    if T and T.PALETTES and T.GetMode then
        local m=T.GetMode()
        local active=T.GetActivePalette and T.GetActivePalette()
        local key=active or m
        if key~=cachedMode then
            cachedMode=key
            cachedPal=active or T.PALETTES[m] or T.PALETTES.dark
            cachedGreenHex=colorHex(cachedPal and cachedPal.accentGreen,'30d158')
        end
        return cachedPal
    end
    return nil
end
local function applyFont(fs, size, weight, flags)
    if type(fs) ~= 'table' then return end
    local T = ns.Theme
    if type(T) == 'table' and type(T.ApplyFont) == 'function' then
        T.ApplyFont(fs, size, weight, flags)
        return
    end
    if type(fs.SetFont) == 'function' then
        local target
        if type(T) == 'table' then
            if type(T.ResolveFontPath) == 'function' then
                target = T.ResolveFontPath(weight)
            elseif type(T.FONTS) == 'table' then
                local wantBold = (weight == 'semibold' or weight == 'bold' or weight == 'heavy')
                target = (wantBold and T.FONTS.semibold) or T.FONTS.regular or T.FONTS.fallback
            end
        end
        target = target or STANDARD_TEXT_FONT or 'Fonts\\ARIALN.TTF'
        local sz = tonumber(size) or 12
        local fl = flags or ''
        local ok = fs:SetFont(target, sz, fl)
        local loaded = type(fs.GetFont) == 'function' and select(1, fs:GetFont())
        if ok == false or (ok == nil and loaded ~= target) then
            fs:SetFont(STANDARD_TEXT_FONT or 'Fonts\\ARIALN.TTF', sz, fl)
        end
    end
    if type(fs.SetShadowOffset) == 'function' then fs:SetShadowOffset(0, 0) end
    if type(fs.SetShadowColor) == 'function' then fs:SetShadowColor(0, 0, 0, 0) end
end
local function readable(v) return not (issecretvalue and issecretvalue(v)) and not (type(v)=='table' and issecrettable and issecrettable(v)) end
local function shown(frame)
    if (type(frame)~='table' and type(frame)~='userdata') or type(frame.IsShown)~='function' then return false end
    local ok,value=pcall(frame.IsShown,frame)
    return ok and readable(value) and value==true
end
local function isMouseOverFrame(frame)
    if (type(frame)~='table' and type(frame)~='userdata') or type(frame.IsMouseOver)~='function' then return false end
    local ok,value=pcall(frame.IsMouseOver,frame)
    return ok and readable(value) and value==true
end
function uiCache.enableEscape(self)
    if self.EnableKeyboard and self.SetPropagateKeyboardInput then
        self:SetPropagateKeyboardInput(true)
        self:EnableKeyboard(true)
    end
end
function uiCache.frameBounds(frame,scale)
    if not frame or type(frame.GetLeft)~='function' or type(frame.GetTop)~='function' then return end
    local factor=(frame.GetEffectiveScale and frame:GetEffectiveScale() or scale)/scale
    local left,top=frame:GetLeft(),frame:GetTop()
    if not left or not top then return end
    return left*factor,top*factor,(left+(frame:GetWidth() or 0))*factor,(top-(frame:GetHeight() or 0))*factor
end
local function combatLocked()
    if type(InCombatLockdown)~='function' then return false end
    local ok,value=pcall(InCombatLockdown)
    return not ok or not readable(value) or value==true
end
local function shiftKeyDown()
    if type(IsShiftKeyDown)~='function' then return false end
    local ok,value=pcall(IsShiftKeyDown)
    if not ok or not readable(value) then return nil end
    return value==true
end
local function number(v) return readable(v) and type(v)=='number' and v==v and v~=math.huge and v~=-math.huge and v end
local function text(v) return readable(v) and type(v)=='string' and v or '' end
local function money(v,signed)
    if not number(v) then return 'n/a' end
    local T=ns.Theme
    if T and T.FormatMoneyText then
        return T.FormatMoneyText(v,signed)
    elseif T and T.FormatMoneyParts then
        local parts=T.FormatMoneyParts(v,signed)
        if parts and parts.text then return parts.text end
    end
    return ns.FormatMoneyCompact(v,signed)
end
local function moneyCompact(v,signed) return number(v) and ns.FormatMoneyCompact(v,signed) or 'n/a' end
local function quantity(v) return number(v) and string.format('%.2f',v) or 'n/a' end
local function actualCost(row)
    local cost=row.sourceCost
    if type(cost)~='table' or not cost.known then return 'n/a' end
    local parts,currencies={},{}
    if number(cost.copper) then parts[#parts+1]=moneyCompact(cost.copper) end
    for id,amount in pairs(cost.currencies or {}) do
        if number(id) and number(amount) then currencies[#currencies+1]={id,amount} end
    end
    table.sort(currencies,function(a,b) return a[1]<b[1] end)
    for _,c in ipairs(currencies) do parts[#parts+1]=tostring(c[2])..(c[1]==(ns.FAVOR_CURRENCY_ID or 3402) and ' Favor' or (' C'..c[1])) end
    return #parts>0 and table.concat(parts,' + ') or 'n/a'
end
local tooltipOwner,tooltipRow
local function clearTooltipCache() tooltipOwner,tooltipRow=nil,nil end
local function getTooltipOwner()
    if GameTooltip and type(GameTooltip.GetOwner)=='function' then
        local ok,owner=pcall(GameTooltip.GetOwner,GameTooltip)
        if ok and readable(owner) then return owner end
        return nil
    end
    return readable(tooltipOwner) and tooltipOwner or nil
end
local function leaveTooltip(owner)
    if GameTooltip and shown(GameTooltip) and getTooltipOwner()==owner then GameTooltip:Hide() end
    if tooltipOwner==owner then clearTooltipCache() end
end
local function hideRowTooltip(owner)
    if not owner or not GameTooltip or not shown(GameTooltip) then return end
    local target=getTooltipOwner()
    local parent
    if target and type(target.GetParent)=='function' then
        local ok,value=pcall(target.GetParent,target)
        if ok and readable(value) then parent=value end
    end
    if target==owner or (parent and (parent==owner or parent==owner.cellGroup)) then
        clearTooltipCache()
        GameTooltip:Hide()
    end
end
local function sameQuickLookTarget(a,b,kind)
    if a==b then return true end
    if type(a)~='table' or type(b)~='table' then return false end
    if kind=='forged' then
        local id=a.crateID or a.itemID
        return id~=nil and id==(b.crateID or b.itemID)
    end
    if kind=='writ' then return a.writID~=nil and a.writID==b.writID end
    if kind=='crate' then
        return a.crateID~=nil and a.reagentID~=nil and a.crateID==b.crateID and a.reagentID==b.reagentID
    end
    if kind=='item' then
        return a.itemID~=nil and a.itemID==b.itemID
    end
    if a.key~=nil and b.key~=nil then return a.key==b.key end
    if a.recipe~=nil and a.recipe==b.recipe then return true end
    local itemID=a.outputItemID or a.itemID
    return itemID~=nil and itemID==(b.outputItemID or b.itemID)
end
if GameTooltip and GameTooltip.HookScript then GameTooltip:HookScript('OnHide',clearTooltipCache) end
local function tooltip(owner,row)
    if not row then return end
    if tooltipOwner==owner and tooltipRow==row and shown(GameTooltip) and getTooltipOwner()==owner then return end
    GameTooltip:SetOwner(owner,'ANCHOR_RIGHT')
    local usedNative=false
    if number(row.outputItemID) and row.outputItemID>0 then
        if GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(row.outputItemID)
            usedNative=true
        elseif GameTooltip.SetHyperlink then
            GameTooltip:SetHyperlink('item:'..tostring(row.outputItemID))
            usedNative=true
        end
    elseif number(row.spellID) and row.spellID>0 then
        if GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(row.spellID)
            usedNative=true
        elseif GameTooltip.SetHyperlink then
            GameTooltip:SetHyperlink('spell:'..tostring(row.spellID))
            usedNative=true
        end
    end
    if not usedNative then
        GameTooltip:AddLine(text(row.name),1,0.82,0,true)
    else
        GameTooltip:AddLine(' ')
    end
    if row.recipe and text(row.recipe.effectText)~='' then GameTooltip:AddLine('Forever Effect: '..row.recipe.effectText,0.5,1,0.7,true) end
    local bis=row.bisInfo
    if bis and bis.hasEval then
        GameTooltip:AddLine('Best in Class Evaluation',1,0.82,0)
        GameTooltip:AddDoubleLine(bis.classLabel or 'Effect class',string.format('#%d / %d - %s',bis.rank or 0,bis.total or 0,bis.valText or ''))
        if bis.bestName then GameTooltip:AddLine('Strongest: '..bis.bestName,0.6,1,0.7,true) end
    end
    if text(row.goodFull)~='' or text(row.goodShort)~='' then
        GameTooltip:AddDoubleLine('Why Buyers Need It',text(row.goodFull)~='' and row.goodFull or row.goodShort,0.85,0.85,0.85,1,1,1)
    end
    local prof=(ns.PROF_BY_KEY or {})[row.prof]
    GameTooltip:AddDoubleLine('Profession / required skill',(prof and prof.full or text(row.prof))..' '..tostring(number(row.requiredSkill) or 'n/a'))
    local sy,sg,sgr=number(row.skillYellow),number(row.skillGreen),number(row.skillGray)
    if not (sy and sg and sgr) then
        local MP=ns.MP or _G.MerchantProfessorNS or _G.MerchantProfessor or ns.Professor
        local bySpell=MP and (MP.RECIPE_BY_SPELL or MP.RECIPES_BY_SPELL)
        local profRec=bySpell and row.spellID and bySpell[row.spellID]
        if profRec and MP.GetEffectiveThresholds then
            local _,ty,tg,tgr=MP.GetEffectiveThresholds(profRec)
            sy,sg,sgr=number(ty),number(tg),number(tgr)
        end
    end
    if sy and sg and sgr then
        GameTooltip:AddDoubleLine('Skill-Up (Y / G / Gr)',string.format('|cffffd100%d|r / |cff30d158%d|r / |cff98989d%d|r',sy,sg,sgr),0.85,0.85,0.85,1,1,1)
    end
    GameTooltip:AddLine('Source: '..text(row.sourceLabel),0.8,0.9,1,true)
    if number(row.reqRep) and row.reqRep>0 then
        local repName=text(row.repLabel)~='' and text(row.repLabel) or ('Rep '..tostring(row.reqRep))
        local fac=text(row.repFactionName)
        local repTxt=((fac~='' and (fac..' - ')) or '')..repName..(row.repMet~=false and ' (Met)' or ' (Required)')
        GameTooltip:AddDoubleLine('Reputation required',repTxt,0.85,0.85,0.85,row.repMet~=false and 0.25 or 1.0,row.repMet~=false and 0.95 or 0.35,row.repMet~=false and 0.45 or 0.35)
    else
        GameTooltip:AddDoubleLine('Reputation required','None',0.85,0.85,0.85,0.65,0.65,0.68)
    end
    if type(row.cdInfo)=='table' and row.cdInfo.hasCooldown then
        local cdInfo=row.cdInfo
        local cdRate=text(cdInfo.rateLabel)~='' and text(cdInfo.rateLabel) or ('1 / '..tostring(cdInfo.windowLabel or 'CD'))
        local cdScope=cdInfo.isShared and '(Shared Alchemy Transmute CD)' or '(Independent CD)'
        GameTooltip:AddDoubleLine('Craft Cooldown',cdRate..' '..cdScope,0.85,0.85,0.85,0.95,0.75,0.28)
        if cdInfo.onCooldown then
            local remTxt=text(cdInfo.remainingLabel)~='' and text(cdInfo.remainingLabel) or 'Active'
            GameTooltip:AddDoubleLine('Cooldown Available','No ('..remTxt..' left)',0.85,0.85,0.85,1.0,0.35,0.35)
        elseif cdInfo.available==true then
            GameTooltip:AddDoubleLine('Cooldown Available','Yes (Ready)',0.85,0.85,0.85,0.25,0.95,0.45)
        else
            GameTooltip:AddDoubleLine('Cooldown Available','Unknown (Recipe not learned)',0.85,0.85,0.85,0.65,0.65,0.68)
        end
    end
    local ability=row.craftAbility or {}
    if text(ability.howDetail)~='' then GameTooltip:AddLine(ability.howDetail,0.8,0.9,1,true) end
    if number(ability.vendorFavorCost) then GameTooltip:AddLine(tostring(ability.vendorFavorCost).." Merchant's Favor Tokens",0.5,1,0.7,true) end
    GameTooltip:AddDoubleLine('Owned output / scrolls',tostring(number(row.ownedOutputQty) or 0)..' / '..tostring(number(row.ownedScrollQty) or 0))
    local knownTipText='No'
    if row.known then
        if ability.knownOnActive==false and type(ability.knownAltNames)=='table' and #ability.knownAltNames>0 then
            knownTipText='Yes ('..table.concat(ability.knownAltNames,', ')..')'
        else
            knownTipText='Yes'
        end
    end
    GameTooltip:AddDoubleLine('Recipe learned',knownTipText)
    GameTooltip:AddDoubleLine('Buy Cost'..(row.buyCostEstimated and ' (estimated Favor equivalent)' or ''),money(row.buyCostCopper))
    GameTooltip:AddLine('Actual Source Cost: '..actualCost(row),1,1,1,true)
    GameTooltip:AddDoubleLine('Craft / AH Price',money(row.craftCost)..' / '..money(row.unitAH))
    GameTooltip:AddDoubleLine('Listed AH quantity',tostring(number(row.listed) or 'n/a'))
    GameTooltip:AddDoubleLine('Sales/day',quantity(row.salesPerDay)..' - '..(text(row.salesScope)~='' and row.salesScope or 'Unknown scope'))
    GameTooltip:AddLine('Sales window: '..(number(row.salesWindowDays) and tostring(row.salesWindowDays)..' days' or 'provider window unknown'),0.8,0.9,1,true)
    local market=readable(row.marketDemand) and type(row.marketDemand)=='table' and row.marketDemand
    if market or number(row.personalSold7d) then
        if number(row.personalSold7d) or number(row.personalExpired7d) then
            local personal=tostring(number(row.personalSold7d) or 0)..' sold / '..tostring(number(row.personalExpired7d) or 0)..' expired'
            if number(row.personalSellThrough) then personal=personal..string.format(', %.1f%% sell-through',row.personalSellThrough*100) end
            if number(row.personalCancelChurn) then personal=personal..string.format(', %.1f%% cancel churn',row.personalCancelChurn*100) end
            GameTooltip:AddLine('My AH (7d, econ): '..personal,0.8,0.9,1,true)
        end
        if market then
            if number(market.effectiveDailySold) and text(market.demandSource)~='' then
                GameTooltip:AddLine('Realm Est ('..market.demandSource..'): '..quantity(market.effectiveDailySold)..'/d',0.5,1,0.7,true)
            end
            if uiCache.snapshotsAvailable() and number(market.snapDailySold) then
                local obsH=number(market.snapObsHours) or 0
                GameTooltip:AddLine('Blizzard Realm: '..quantity(market.snapDailySold)..'/d ('..tostring(obsH)..'h obs)',0.8,0.9,1,true)
            end
            if number(market.localClearsPerDay) then
                GameTooltip:AddLine('Local Scans: '..quantity(market.localClearsPerDay)..' clears/day ('..
                    (text(market.localConfidence)~='' and market.localConfidence or 'Unknown')..', '..
                    tostring(number(market.localScanPairs) or 0)..' pairs)',0.8,0.9,1,true)
            end
        end
    end
    if number(row.coverageStart) then GameTooltip:AddLine('Personal coverage start: '..tostring(row.coverageStart),0.8,0.9,1,true) end
    GameTooltip:AddLine('Turnover/day: '..money(row.turnoverPerDay)..' estimated gross output revenue; not realized ledger revenue.',1,1,1,true)
    GameTooltip:AddDoubleLine('Heat',text(row.demand and (row.demand.stateLabel or row.demand.heatBadge)))
    if row.isSlowing then GameTooltip:AddLine('Personal sales are slowing.',1,0.7,0.3,true) end
    GameTooltip:AddDoubleLine('Profit per output',money(row.profit,true))
    if not row.sellable then GameTooltip:AddLine('Output is not tradeable; market metrics are unavailable.',1,0.7,0.3,true) end
    if row.wowheadURL then GameTooltip:AddLine(row.wowheadURL,0.6,0.9,1,true) end
    GameTooltip:AddLine('Click a recipe to pin its 7-day Quick Look.',0.6,0.9,1,true)
    GameTooltip:AddLine('Hold Shift: quick-add mode (+1 Left-Click, -1 Right-Click, or use -/+ stepper).',0.4,1,0.6,true)
    GameTooltip:Show()
    tooltipOwner,tooltipRow=owner,row
end
local function themeText(str)
    if type(str)~='string' or str=='' then return nil end
    local T=ns.Theme
    return (T and type(T.ThemeText)=='function') and T.ThemeText(str) or str
end
local function queuedQtyFor(data)
    if not data or not host or type(host.getRecipeShoppingQty)~='function' then return 0 end
    return tonumber(host.getRecipeShoppingQty(data)) or 0
end
local function updateShiftHeader()
    if not view then return end
    if view.shiftBadge and view.shiftBadge.SetShown then
        view.shiftBadge:SetShown(shiftActive)
    end
    if view.summary and view.summary.ClearAllPoints and view.summary.SetPoint then
        view.summary:ClearAllPoints()
        if view.summaryLeftAnchor then
            view.summary:SetPoint('LEFT',view.summaryLeftAnchor,'RIGHT',10,0)
        end
        if shiftActive and view.shiftBadge then
            view.summary:SetPoint('RIGHT',view.shiftBadge,'LEFT',-8,0)
        elseif view.filtersButton then
            view.summary:SetPoint('RIGHT',view.filtersButton,'LEFT',-10,0)
        elseif view.resetButton then
            view.summary:SetPoint('RIGHT',view.resetButton,'LEFT',-10,0)
        end
    end
end
local function styleRowStepper(stepper, qty, pal)
    if not stepper then return end
    local isLight=(pal and pal.mode=='light')
    local bgCol=(pal and pal.cardAltBg) or (isLight and {0.949,0.949,0.969,1} or {0.204,0.204,0.220,1})
    local stCol=(pal and pal.borderStrong) or (isLight and {0,0,0,0.14} or {1,1,1,0.22})
    local textCol=(pal and pal.text) or (isLight and {0,0,0,1} or {1,1,1,1})
    local mutedCol=(pal and pal.textMuted) or (isLight and {0.369,0.384,0.416,1} or {0.596,0.596,0.616,0.88})
    local greenCol=(pal and pal.accentGreen) or (isLight and {0,0.478,0.169,1} or {0.188,0.820,0.345,1})
    if stepper.bg then
        if stepper.bg.SetColor then stepper.bg:SetColor(bgCol[1],bgCol[2],bgCol[3],1)
        elseif stepper.bg.SetColorTexture then stepper.bg:SetColorTexture(bgCol[1],bgCol[2],bgCol[3],1) end
    end
    if stepper.stroke and stepper.stroke.SetColor then
        stepper.stroke:SetColor(stCol[1],stCol[2],stCol[3],stCol[4] or 0.22)
    end
    if stepper.minusBtn and stepper.minusBtn.fs and stepper.minusBtn.fs.SetTextColor then
        stepper.minusBtn.fs:SetTextColor(textCol[1],textCol[2],textCol[3],1)
    end
    if stepper.plusBtn and stepper.plusBtn.fs and stepper.plusBtn.fs.SetTextColor then
        stepper.plusBtn.fs:SetTextColor(textCol[1],textCol[2],textCol[3],1)
    end
    if stepper.qtyFs then
        stepper.qtyFs:SetText(tostring(qty))
        if stepper.qtyFs.SetTextColor then
            local qc=(qty>0) and greenCol or mutedCol
            stepper.qtyFs:SetTextColor(qc[1],qc[2],qc[3],qc[4] or 1)
        end
    end
end
local function ensureRowStepper(r)
    if r.shiftStepper then return r.shiftStepper end
    local T=ns.Theme
    local stepper=CreateFrame('Frame',nil,r)
    stepper:SetSize(76,20)
    stepper:SetPoint('RIGHT',r,'RIGHT',-2,0)
    if r.GetFrameLevel and stepper.SetFrameLevel then
        stepper:SetFrameLevel((r:GetFrameLevel() or 1)+4)
    end
    if stepper.EnableMouse then stepper:EnableMouse(true) end
    if type(T)=='table' and type(T.RoundRect)=='function' and type(T.ASSETS)=='table' and T.ASSETS.pill_fill then
        stepper.bg=T.RoundRect(stepper,stepper,'BACKGROUND',0,10,0,0.204,0.204,0.220,1,T.ASSETS.pill_fill)
        if T.ASSETS.pill_stroke then
            stepper.stroke=T.RoundRect(stepper,stepper,'BORDER',1,10,0,1,1,1,0.22,T.ASSETS.pill_stroke)
        end
    else
        stepper.bg=stepper:CreateTexture(nil,'BACKGROUND')
        stepper.bg:SetAllPoints()
        stepper.bg:SetColorTexture(0.204,0.204,0.220,1)
    end
    local minusBtn=CreateFrame('Button',nil,stepper)
    minusBtn:SetSize(22,18)
    minusBtn:SetPoint('LEFT',stepper,'LEFT',1,0)
    minusBtn:RegisterForClicks('LeftButtonUp','RightButtonUp')
    minusBtn.hl=minusBtn:CreateTexture(nil,'HIGHLIGHT')
    minusBtn.hl:SetAllPoints()
    minusBtn.hl:SetColorTexture(1,1,1,0.08)
    minusBtn.fs=minusBtn:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    minusBtn.fs:SetAllPoints()
    minusBtn.fs:SetJustifyH('CENTER')
    applyFont(minusBtn.fs,12,'semibold')
    minusBtn.fs:SetText('-')
    minusBtn:SetScript('OnClick',function(_,button)
        local row=r.data
        if not row or not host or type(host.adjustRecipeShoppingQty)~='function' then return end
        local cur=queuedQtyFor(row)
        local delta=(button=='RightButton') and -math.max(1,cur) or -1
        host.adjustRecipeShoppingQty(row,delta)
    end)

    local plusBtn=CreateFrame('Button',nil,stepper)
    plusBtn:SetSize(22,18)
    plusBtn:SetPoint('RIGHT',stepper,'RIGHT',-1,0)
    plusBtn:RegisterForClicks('LeftButtonUp','RightButtonUp')
    plusBtn.hl=plusBtn:CreateTexture(nil,'HIGHLIGHT')
    plusBtn.hl:SetAllPoints()
    plusBtn.hl:SetColorTexture(1,1,1,0.08)
    plusBtn.fs=plusBtn:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    plusBtn.fs:SetAllPoints()
    plusBtn.fs:SetJustifyH('CENTER')
    applyFont(plusBtn.fs,12,'semibold')
    plusBtn.fs:SetText('+')
    plusBtn:SetScript('OnClick',function(_,button)
        local row=r.data
        if not row or not host or type(host.adjustRecipeShoppingQty)~='function' then return end
        local delta=(button=='RightButton') and 5 or 1
        host.adjustRecipeShoppingQty(row,delta)
    end)

    local qtyFs=stepper:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    qtyFs:SetPoint('LEFT',minusBtn,'RIGHT',0,0)
    qtyFs:SetPoint('RIGHT',plusBtn,'LEFT',0,0)
    qtyFs:SetJustifyH('CENTER')
    qtyFs:SetWordWrap(false)
    applyFont(qtyFs,11,'semibold')
    qtyFs:SetText('0')

    stepper.minusBtn=minusBtn
    stepper.plusBtn=plusBtn
    stepper.qtyFs=qtyFs
    stepper:Hide()
    r.shiftStepper=stepper
    return stepper
end
local function paintSelection(r)
    local pal=getThemePalette()
    local isLight=(pal and pal.mode=='light')
    local hasRow=(r.data~=nil)
    local isSel=hasRow and r.data.key==selectedKey
    if shiftActive and hasRow then
        local qty=queuedQtyFor(r.data)
        local stepper=ensureRowStepper(r)
        styleRowStepper(stepper,qty,pal)
        stepper:Show()
        local n=r.cells and #r.cells or 0
        if n>0 then
            r._shiftHidden=true
            local activeCols=tbl and tbl.columns
            local colX=tbl and tbl.colX
            local lastCol=activeCols and activeCols[n]
            local lastX=colX and colX[n]
            local tblRight=(lastCol and lastX) and (lastX+(lastCol.width or 0)) or 0
            local rawRowW=(r.GetWidth and r:GetWidth()) or 0
            local rowW=(rawRowW>=math.max(200,tblRight*0.5)) and rawRowW or tblRight
            local hidAny=false
            if rowW>80 and activeCols and colX then
                local cutoff=rowW-80
                for i=1,n do
                    local c=r.cells[i]
                    local cx=colX[i] or 0
                    local cw=(activeCols[i] and activeCols[i].width) or 0
                    local overlap=(cx+cw>cutoff)
                    if c and c.SetShown then c:SetShown(not overlap) end
                    if overlap then hidAny=true end
                end
            end
            if not hidAny then
                for i=math.max(1,n-1),n do
                    local c=r.cells[i]
                    if c and c.SetShown then c:SetShown(false) end
                end
            end
        end
        if pal then
            if qty>0 and pal.accentGreen then
                r.stripe:SetColorTexture(pal.accentGreen[1],pal.accentGreen[2],pal.accentGreen[3],isLight and 0.10 or 0.14)
            elseif pal.accentBlue then
                r.stripe:SetColorTexture(pal.accentBlue[1],pal.accentBlue[2],pal.accentBlue[3],isLight and 0.05 or 0.07)
            end
        else
            if qty>0 then r.stripe:SetColorTexture(0.188,0.820,0.345,0.14)
            else r.stripe:SetColorTexture(0.00,0.569,1.0,0.07) end
        end
    else
        if r.shiftStepper and r.shiftStepper.Hide then r.shiftStepper:Hide() end
        if r._shiftHidden and r.cells then
            r._shiftHidden=false
            for _,c in ipairs(r.cells) do
                if c and c.SetShown then c:SetShown(true) end
            end
        end
        if pal then
            if isSel and pal.accentBlue then
                r.stripe:SetColorTexture(pal.accentBlue[1],pal.accentBlue[2],pal.accentBlue[3],0.16)
            else
                r.stripe:SetColorTexture(0,0,0,0)
            end
        else
            r.stripe:SetColorTexture(0.00,0.569,1.0,isSel and 0.16 or 0)
        end
    end
    if type(r.sep)=='table' then
        if not r._sepAnchored and type(r.sep.ClearAllPoints)=='function' and type(r.sep.SetPoint)=='function' then
            r._sepAnchored=true
            r.sep:ClearAllPoints()
            r.sep:SetPoint('BOTTOMLEFT',r,'BOTTOMLEFT',16,0)
            r.sep:SetPoint('BOTTOMRIGHT',r,'BOTTOMRIGHT',-16,0)
        end
        if pal and type(r.sep.SetColorTexture)=='function' and pal.separator then
            r.sep:SetColorTexture(pal.separator[1],pal.separator[2],pal.separator[3],(pal.separator[4] or 0.45)*0.45)
        end
    end
end
local function selectRow(row, button)
    if not row then return end
    if button~=nil and (not readable(button) or type(button)~='string') then return end
    local shiftValue=shiftKeyDown()
    if shiftValue==nil then return end
    local shiftHeld=shiftValue or shiftActive
    if shiftHeld and host and type(host.adjustRecipeShoppingQty)=='function' then
        if button=='LeftButton' and row.outputItemID and type(host.tryQuickLookChatLink)=='function'
            and host.tryQuickLookChatLink(row.outputItemID)==true then
            return
        end
        selectedKey=row.key; host.selectRecipe(row.outputItemID)
        local delta=(button=='RightButton') and -1 or 1
        host.adjustRecipeShoppingQty(row,delta)
        return
    end
    local leftClick=button==nil or button=='LeftButton'
    if leftClick then
        local hud=provider.GetQuickLookFrame()
        if shown(hud) and hud.pinned and (not hud.data or hud.data.kind=='recipe')
            and sameQuickLookTarget(hud.row,row,'recipe') then
            provider.CloseQuickLook()
            return
        end
    end
    selectedKey=row.key; host.selectRecipe(row.outputItemID); tbl.scrollBox:ForEachFrame(paintSelection)
    if row.craftBreakdown and #row.craftBreakdown>0 and not (host.hasUnifiedShoppingItems and host.hasUnifiedShoppingItems()) then
        local modalShown = ns.app and ns.app.ui and ns.app.ui.shopModal and shown(ns.app.ui.shopModal)
        if modalShown then
            host.showSingleCraftShoppingPreview(row,row.numMade or 1,latest.counts,latest.profMap,latest.subCraftMode,latest.subCraftOverrides)
        else
            uiCache.previewSeq=(uiCache.previewSeq or 0)+1
            local myPrevSeq=uiCache.previewSeq
            local snapRow,snapLatest=row,latest
            later(function()
                if myPrevSeq~=uiCache.previewSeq or not snapLatest then return end
                if host.hasUnifiedShoppingItems and host.hasUnifiedShoppingItems() then return end
                host.showSingleCraftShoppingPreview(snapRow,snapRow.numMade or 1,snapLatest.counts,snapLatest.profMap,snapLatest.subCraftMode,snapLatest.subCraftOverrides)
            end)
        end
    end
    if button~='RightButton' and row.outputItemID then
        local name=ns.ItemName(row.outputItemID)
        if name=='Item #'..row.outputItemID then name=nil end
        host.searchAH(name,1,row.outputItemID,{silentNoAH=true,coalesce=true})
    end
    if leftClick and row.recipe then
        provider.OpenQuickLook(row,true)
    end
end
local function styleCellPill(cell,kind,pal)
    local pill=cell.pillBg
    if not pill then return end
    if not kind then
        if cell._pillKind then pill:SetShown(false) end
        cell._pillKind=nil
        return
    end
    if cell._pillKind==kind and cell._pillPalette==pal then return end
    cell._pillKind,cell._pillPalette=kind,pal
    local bgCol
    local isLight=(pal and pal.mode=='light')
    if pal then
        if kind=='hot' and pal.accentOrange then bgCol={pal.accentOrange[1],pal.accentOrange[2],pal.accentOrange[3],isLight and 0.11 or 0.12}
        elseif kind=='pos' and pal.accentGreen then bgCol={pal.accentGreen[1],pal.accentGreen[2],pal.accentGreen[3],isLight and 0.11 or 0.14}
        elseif kind=='blue' and pal.accentBlue then bgCol={pal.accentBlue[1],pal.accentBlue[2],pal.accentBlue[3],isLight and 0.11 or 0.14}
        elseif pal and pal.pillTrack then bgCol={pal.pillTrack[1],pal.pillTrack[2],pal.pillTrack[3],0.12}
        end
    else
        if kind=='hot' then bgCol={1,0.55,0.16,0.12}
        elseif kind=='pos' then bgCol={0.20,0.78,0.35,0.14}
        elseif kind=='blue' then bgCol={0.04,0.52,1.0,0.14}
        else bgCol={0.47,0.47,0.50,0.12} end
    end
    if bgCol and cell.pillBg.SetColor then
        cell.pillBg:SetColor(bgCol[1],bgCol[2],bgCol[3],bgCol[4] or 0.16)
    end
    if cell.pillBg.SetShown then cell.pillBg:SetShown(true) end
end
local function syncCellGroup(group)
    local cells,byKey=group.cells,group.cellsByKey
    local active={}
    for i=#cells,#tbl.columns+1,-1 do cells[i]=nil end
    for i,col in ipairs(tbl.columns) do
        local cell=byKey[col.key]
        cells[i]=cell
        active[col.key]=true
        cell:Show()
    end
    for key,cell in pairs(byKey) do
        if not active[key] then cell:Hide() end
    end
    group._colEpoch=colEpoch
    group._layoutEpoch=nil
end
local function syncRowCells(r)
    syncCellGroup(r.cellGroup)
    r._colEpoch=colEpoch
    r._layoutEpoch=nil
end
local HEAT_DOW_NAMES={'Mon','Tue','Wed','Thu','Fri','Sat','Sun'}
local HEAT_POPOVER_W,HEAT_POPOVER_H=580,246
local function currentLocalHour()
    local now=(type(time)=='function' and time()) or (os and os.time and os.time()) or nil
    if uiCache.localHour~=nil and now~=nil and uiCache.localHourAt~=nil and now>=uiCache.localHourAt and (now-uiCache.localHourAt)<60 then
        return uiCache.localHour
    end
    local fn=date or (os and os.date)
    if type(fn)~='function' then return 12 end
    local t=fn('*t')
    local hour=(type(t)=='table' and type(t.hour)=='number') and t.hour or 12
    uiCache.localHour,uiCache.localHourAt=hour,now
    return hour
end
local function getSuperListScrollPct()
    if tbl and tbl.scrollBox and type(tbl.scrollBox.GetScrollPercentage)=='function' then
        local ok,pct=pcall(tbl.scrollBox.GetScrollPercentage,tbl.scrollBox)
        if ok and number(pct) then return pct end
    end
    return nil
end
local function getHeatStripForRow(data)
    if not uiCache.snapshotsAvailable() then return nil end
    if not data or not number(data.outputItemID) or data.outputItemID<=0 then return nil end
    local P=ns.Pricing
    if not (P and type(P.GetItemHeatStrip24h)=='function') then return nil end
    local econ=latest and latest.econInfo and latest.econInfo.effectiveKey or nil
    return P.GetItemHeatStrip24h(data.outputItemID,econ)
end
local function showHeatCellTooltip(owner,row)
    if not uiCache.snapshotsAvailable() then return end
    if not row or not GameTooltip then return end
    local shiftValue=shiftKeyDown()
    if shiftValue==nil or shiftValue or shiftActive then return end
    local strip=getHeatStripForRow(row)
    if not strip then return end
    GameTooltip:SetOwner(owner,'ANCHOR_RIGHT')
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    local title=(text(row.name)~='' and row.name or 'Item')..' — 24h Price Heat'
    GameTooltip:AddLine(title,1,0.82,0)
    local nowHour=currentLocalHour()
    local curPrice=strip.hourly and number(strip.hourly[nowHour])
    local avgPrice=(number(strip.avgPrice) and strip.avgPrice>0 and strip.avgPrice)
        or (number(strip.medianPrice) and strip.medianPrice>0 and strip.medianPrice) or nil
    if curPrice and avgPrice then
        local pct=((curPrice-avgPrice)/avgPrice)*100
        GameTooltip:AddDoubleLine(string.format('Now %02d:00',nowHour),
            string.format('%s (%+.1f%% vs avg)',money(curPrice),pct),0.72,0.78,0.86,1,1,1)
    elseif avgPrice then
        GameTooltip:AddDoubleLine('Weekly avg',money(avgPrice),0.72,0.78,0.86,1,1,1)
    end
    local bb=strip.bestBuy
    if type(bb)=='table' and number(bb.dow) and number(bb.hour) and number(bb.price) then
        local bbDay=HEAT_DOW_NAMES[bb.dow] or ('D'..tostring(bb.dow))
        local bbPct=(avgPrice and avgPrice>0) and string.format(' (%+.1f%%)',((bb.price-avgPrice)/avgPrice)*100) or ''
        GameTooltip:AddDoubleLine('Best Buy',string.format('%s %02d:00  %s%s',bbDay,bb.hour,money(bb.price),bbPct),
            0.72,0.78,0.86,0.30,0.85,0.45)
    end
    local bs=strip.bestSell
    if type(bs)=='table' and number(bs.dow) and number(bs.hour) and number(bs.price) then
        local bsDay=HEAT_DOW_NAMES[bs.dow] or ('D'..tostring(bs.dow))
        local bsPct=(avgPrice and avgPrice>0) and string.format(' (%+.1f%%)',((bs.price-avgPrice)/avgPrice)*100) or ''
        GameTooltip:AddDoubleLine('Best Sell',string.format('%s %02d:00  %s%s',bsDay,bs.hour,money(bs.price),bsPct),
            0.72,0.78,0.86,1.00,0.62,0.22)
    end
    GameTooltip:AddLine('Click: 7x24 heatmap | Right-Click: Deep Analysis',0.65,0.72,0.80,true)
    local T=ns.Theme
    if T and T.LiftTooltip then T.LiftTooltip(GameTooltip) end
    GameTooltip:Show()
    tooltipOwner,tooltipRow=owner,row
end
local function closeHeatPopover(onlyForRow)
    local pop=type(view)=='table' and rawget(view,'heatPopover') or nil
    if (type(pop)~='table' and type(pop)~='userdata') or not shown(pop) then return end
    if onlyForRow then
        local demandCell=onlyForRow.cellGroup and onlyForRow.cellGroup.cellsByKey and onlyForRow.cellGroup.cellsByKey.demandSort
        if not demandCell or pop.ownerCell~=demandCell then return end
    end
    pop:Hide()
end
local function repositionHeatPopover(pop,ownerCell)
    if not pop then return end
    local parent=pop:GetParent() or (host and host.parent) or view
    if not parent then return end
    local scale=parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
    local pLeft,pTop,pRight,pBottom=uiCache.frameBounds(parent,scale)
    if not pLeft then
        pop:ClearAllPoints()
        if ownerCell then
            pop:SetPoint('TOPLEFT',ownerCell,'BOTTOMLEFT',0,-4)
        else
            pop:SetPoint('CENTER',parent,'CENTER',0,0)
        end
        return
    end
    local sLeft,sTop,sRight,sBottom=uiCache.frameBounds(UIParent,scale)
    local minX,maxX=math.max(pLeft,sLeft or pLeft)+8,math.min(pRight,sRight or pRight)-8
    local minY,maxY=math.max(pBottom,sBottom or pBottom)+8,math.min(pTop,sTop or pTop)-8
    if maxX<=minX or maxY<=minY then return end
    local w,h=HEAT_POPOVER_W,HEAT_POPOVER_H
    local oLeft,oTop,oRight,oBottom=uiCache.frameBounds(ownerCell,scale)
    local x=(oRight and (oRight-w)) or (maxX-w)
    if oLeft and x<minX then x=oLeft end
    x=math.max(minX,math.min(maxX-w,x))
    local y=(oBottom and (oBottom-6)) or (maxY-60)
    if y-h<minY and oTop and oTop+6+h<=maxY then y=oTop+6+h end
    y=math.max(minY+h,math.min(maxY,y))
    pop:ClearAllPoints()
    pop:SetPoint('TOPLEFT',parent,'TOPLEFT',x-pLeft,y-pTop)
end
local function ensureHeatPopover()
    if not view then return nil end
    local existing=type(view)=='table' and rawget(view,'heatPopover') or nil
    if type(existing)=='table' or type(existing)=='userdata' then return existing end
    local Chart=ns.Analytics and ns.Analytics.Chart
    if not (Chart and type(Chart.CreateHeatmapTimingDrawer)=='function') then return nil end
    local T=ns.Theme
    local parent=(host and host.parent) or view
    local pop=CreateFrame('Frame','MerchantMasterHeatPopover',parent)
    if UISpecialFrames then table.insert(UISpecialFrames,pop:GetName()) end
    pop:SetSize(HEAT_POPOVER_W,HEAT_POPOVER_H)
    if pop.SetFrameStrata then pop:SetFrameStrata('DIALOG') end
    if parent.GetFrameLevel and pop.SetFrameLevel then pop:SetFrameLevel((parent:GetFrameLevel() or 1)+65) end
    if pop.SetClampedToScreen then pop:SetClampedToScreen(true) end
    if pop.EnableMouse then pop:EnableMouse(true) end
    pop:Hide()
    if type(T)=='table' and type(T.Nine)=='function' and type(T.ASSETS)=='table' and T.ASSETS.shadow_r22 then
        T.Nine(pop,pop,T.ASSETS.shadow_r22,18,10,'BACKGROUND',-3):SetColor(0,0,0,0.45)
    end
    local drawer=Chart.CreateHeatmapTimingDrawer(pop,HEAT_POPOVER_W,HEAT_POPOVER_H,{
        compact=true,
        showCurve=false,
        skipInitialRedraw=true,
        onClose=closeHeatPopover,
        onDeepAnalysis=function()
            local targetRow=pop.row
            local targetItemID=pop.itemID
            closeHeatPopover()
            local openFn=(host and host.openDeepAnalysis) or (ns.app and ns.app.openDeepAnalysis)
            if type(openFn)=='function' then
                local spec=targetRow and {kind='recipe',row=targetRow} or {kind='item',itemID=targetItemID}
                openFn(spec,{
                    tab=(host and host.getActiveTab and host.getActiveTab()) or 'recipes',
                    wasQuickLookOpen=false,
                    superListScrollPct=getSuperListScrollPct(),
                })
            end
        end,
    })
    drawer:SetAllPoints(pop)
    pop.drawer=drawer
    pop:SetScript('OnEvent',function(self,event)
        if event=='PLAYER_REGEN_ENABLED' then
            if not combatLocked() then uiCache.enableEscape(self) end
        elseif event=='GLOBAL_MOUSE_DOWN' then
            if not isMouseOverFrame(self) and not isMouseOverFrame(self.ownerCell) then
                closeHeatPopover()
            end
        end
    end)
    pop:SetScript('OnKeyDown',function(self,key)
        if not readable(key) or type(key)~='string' then return end
        if self.SetPropagateKeyboardInput and not combatLocked() then
            self:SetPropagateKeyboardInput(key~='ESCAPE')
        end
        if key=='ESCAPE' then closeHeatPopover() end
    end)
    pop:SetScript('OnShow',function(self)
        self:RegisterEvent('GLOBAL_MOUSE_DOWN')
        self:RegisterEvent('PLAYER_REGEN_ENABLED')
        if not combatLocked() then uiCache.enableEscape(self) end
    end)
    pop:SetScript('OnHide',function(self)
        self:UnregisterEvent('GLOBAL_MOUSE_DOWN')
        self:UnregisterEvent('PLAYER_REGEN_ENABLED')
        if self.EnableKeyboard then self:EnableKeyboard(false) end
        if self.drawer and self.drawer.SimulateHover then self.drawer:SimulateHover(nil,nil) end
        self.row,self.ownerCell,self.itemID=nil,nil,nil
    end)
    view.heatPopover=pop
    return pop
end
local function toggleHeatPopover(ownerCell,row)
    if not uiCache.snapshotsAvailable() then closeHeatPopover(); return end
    if not row or not number(row.outputItemID) or row.outputItemID<=0 then return end
    local pop=type(view)=='table' and rawget(view,'heatPopover') or nil
    if type(pop)~='table' and type(pop)~='userdata' then pop=nil end
    if pop and shown(pop) and (pop.row==row or (pop.itemID==row.outputItemID and pop.ownerCell==ownerCell)) then
        closeHeatPopover()
        return
    end
    if provider.CloseQuickLook then provider.CloseQuickLook() end
    leaveTooltip(ownerCell)
    pop=ensureHeatPopover()
    if not pop or not pop.drawer then return end
    local econ=latest and latest.econInfo and latest.econInfo.effectiveKey or nil
    local heatmap=ns.Pricing and ns.Pricing.GetItemHeatmap and ns.Pricing.GetItemHeatmap(row.outputItemID,econ) or nil
    local fallbackQL=nil
    if not heatmap and ns.RecipeStats and ns.RecipeStats.BuildQuickLook then
        local ctx=evaluation or {applyAHCut=not MerchantMasterDB or MerchantMasterDB.applyAHCut~=false}
        fallbackQL=ns.RecipeStats.BuildQuickLook(row,ctx)
    end
    pop.row=row
    pop.ownerCell=ownerCell
    pop.itemID=row.outputItemID
    pop.drawer:Layout(HEAT_POPOVER_W,HEAT_POPOVER_H,true)
    pop.drawer:SetItem(row.outputItemID,heatmap,fallbackQL,econ)
    repositionHeatPopover(pop,ownerCell)
    pop:Show()
end
local function heatCellOnEnter(self)
    showHeatCellTooltip(self,self:GetParent().data)
end
local function prepareCells()
    local group=CreateFrame('Frame',nil,view)
    group.cells={}; group.cellsByKey={}; group:Hide()
    local T=ns.Theme
    local pal=getThemePalette()
    for _,col in ipairs(MASTER_COLUMNS) do
            local cell=CreateFrame('Button',nil,group)
            cell:SetHeight(host.rowHeight)
            cell.fs=cell:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            cell.fs:SetPoint('LEFT',2,0); cell.fs:SetPoint('RIGHT',-2,0)
            cell.fs:SetJustifyH(col.align); cell.fs:SetWordWrap(false)
            applyFont(cell.fs,11,'regular')
            if T and T.AutoThemeText then T.AutoThemeText(cell.fs) end
            if pal and pal.text then
                local color=pal.text
                if col.key=='requiredSkill' or col.key=='sourceLabel' then
                    color=pal.textSecondary or color
                end
                cell._textColor=color
                cell.fs:SetTextColor(color[1],color[2],color[3],1)
            end
            if (col.key=='demandSort' or col.key=='bisSort' or col.key=='wowheadURL') and type(T)=='table' and type(T.RoundRect)=='function' and type(T.ASSETS)=='table' and T.ASSETS.pill_fill then
                cell.pillBg=T.RoundRect(cell,cell,'BACKGROUND',0,6,2,0.5,0.5,0.5,0.16,T.ASSETS.pill_fill)
                cell.pillBg:SetShown(false)
            end
            if col.key=='demandSort' then
                local Chart=ns.Analytics and ns.Analytics.Chart
                if Chart and type(Chart.CreateHeatStrip24h)=='function' then
                    local hs=Chart.CreateHeatStrip24h(cell,{height=4,showNowTick=true})
                    if hs and hs.frame then
                        hs.frame:ClearAllPoints()
                        hs.frame:SetPoint('BOTTOMLEFT',cell,'BOTTOMLEFT',2,1)
                        hs.frame:SetPoint('BOTTOMRIGHT',cell,'BOTTOMRIGHT',-2,1)
                        hs:Clear()
                        cell.heatStrip=hs
                        cell._heatStripBound=false
                        cell._heatTipBound=false
                    end
                end
            end
            cell:RegisterForClicks('LeftButtonUp','RightButtonUp')
            cell:SetScript('OnClick',function(self,button)
                if not readable(button) or type(button)~='string' then return end
                local row=self:GetParent().data
                local shiftValue=shiftKeyDown()
                if shiftValue==nil then return end
                local shiftHeld=shiftValue or shiftActive
                if col.key=='wowheadURL' and button=='LeftButton' and not shiftHeld then
                    if row and row.wowheadURL then
                        local ca={}; for k,v in pairs(row.craftAbility or {}) do ca[k]=v end
                        ca.wowheadURL=row.wowheadURL; host.openWowheadPopup(ca,row.name,row.icon)
                    end
                elseif col.key=='demandSort' and not shiftHeld and row then
                    local strip=getHeatStripForRow(row)
                    if strip then
                        if button=='LeftButton' then
                            toggleHeatPopover(self,row)
                            return
                        elseif button=='RightButton' then
                            closeHeatPopover()
                            local openFn=(host and host.openDeepAnalysis) or (ns.app and ns.app.openDeepAnalysis)
                            if type(openFn)=='function' then
                                openFn({kind='recipe',row=row},{
                                    tab=(host and host.getActiveTab and host.getActiveTab()) or 'recipes',
                                    wasQuickLookOpen=false,
                                    superListScrollPct=getSuperListScrollPct(),
                                })
                                return
                            end
                        end
                    end
                    selectRow(row,button)
                else selectRow(row,button) end
            end)
            if col.key=='name' then
                cell:SetScript('OnEnter',function(self) tooltip(self,self:GetParent().data) end)
                cell:SetScript('OnLeave',leaveTooltip)
                local circleTex=type(T)=='table' and type(T.ASSETS)=='table' and T.ASSETS.circle_fill
                if circleTex and type(cell.CreateTexture)=='function' then
                    cell.glyphBg=cell:CreateTexture(nil,'BACKGROUND',nil,1)
                    if type(cell.glyphBg)=='table' then
                        cell.glyphBg:SetSize(20,20); cell.glyphBg:SetPoint('LEFT',0,0)
                        cell.glyphBg:SetTexture(circleTex)
                        if type(cell.glyphBg.SetVertexColor)=='function' then cell.glyphBg:SetVertexColor(0.463,0.463,0.502,0.24) end
                    end
                end
                cell.icon=cell:CreateTexture(nil,'ARTWORK'); cell.icon:SetSize(16,16)
                if type(cell.glyphBg)=='table' then
                    cell.icon:SetPoint('CENTER',cell.glyphBg,'CENTER',0,0)
                else
                    cell.icon:SetPoint('LEFT',0,0)
                end
                if cell.icon.SetTexCoord then cell.icon:SetTexCoord(0.08,0.92,0.08,0.92) end
                cell.fs:SetPoint('LEFT',cell.glyphBg or cell.icon,'RIGHT',5,0)
            end
            group.cellsByKey[col.key]=cell
    end
    syncCellGroup(group)
    if tbl.layoutRow then tbl.layoutRow(group) end
    prepared[#prepared+1]=group
end
local function formatSalesCell(val, pal)
    if not number(val) then return 'n/a' end
    local T=ns.Theme
    local raw=(type(T)=='table' and type(T.FormatSalesPerDay)=='function') and T.FormatSalesPerDay(val) or tostring(val)
    pal=pal or getThemePalette()
    if pal and pal.mode=='light' and type(raw)=='string' then
        raw=raw:gsub('|cff7fd4ff','|cff0066cc'):gsub('|cff6e6b64','|cff6e6e73'):gsub('|cff7a766e','|cff6e6e73')
    end
    return themeText(raw) or raw
end
local function formatCooldownCell(cdInfo)
    if type(cdInfo)~='table' or not cdInfo.hasCooldown then return '-' end
    if cdInfo.available==true then return 'R' end
    local sec=(cdInfo.onCooldown and number(cdInfo.remainingSeconds)) or number(cdInfo.nominalSeconds) or 0
    if sec>=3600 then
        return string.format('%dh',math.max(1,math.floor(sec/3600+0.5)))
    end
    return string.format('%dm',math.min(59,math.max(1,math.ceil(sec/60))))
end
local function formatBisCell(bisInfo)
    if type(bisInfo)~='table' or not bisInfo.hasEval then return 'n/a' end
    local raw=tostring(bisInfo.cellText or '')
    if bisInfo.isBiS then return themeText(raw) or raw end
    return raw:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
end
local function formatSkillupCell(data, pal)
    local y, g, gr = number(data.skillYellow), number(data.skillGreen), number(data.skillGray)
    if not (y and g and gr) then
        local MP = ns.MP or _G.MerchantProfessorNS or _G.MerchantProfessor or ns.Professor
        local bySpell = MP and (MP.RECIPE_BY_SPELL or MP.RECIPES_BY_SPELL)
        local profRec = bySpell and data.spellID and bySpell[data.spellID]
        if profRec and MP.GetEffectiveThresholds then
            local _, sy, sg, sgr = MP.GetEffectiveThresholds(profRec)
            y, g, gr = number(sy), number(sg), number(sgr)
        end
    end
    if not (y and g and gr) then return 'n/a' end
    local isLight = pal and pal.mode == 'light'
    local yHex = isLight and '9a6700' or 'ffd100'
    local gHex = (pal and pal.hexPositive) or (isLight and '007a2b' or '30d158')
    local grHex = (pal and pal.hexMuted) or (isLight and '6e6e73' or '98989d')
    local sepHex = (pal and pal.hexMuted) or (isLight and '6e6e73' or '8e8e93')
    local raw = '|cff'..yHex..tostring(y)..'|r|cff'..sepHex..'/|r|cff'..gHex..tostring(g)..'|r|cff'..sepHex..'/|r|cff'..grHex..tostring(gr)..'|r'
    return themeText(raw) or raw
end
local cellValueCache = setmetatable({}, { __mode = 'k' })
local cellCacheEpoch = 0
local function cellValues(data)
    local pal = getThemePalette()
    local palMode = pal and pal.mode
    local palSkin = pal and pal.skin
    local T = ns.Theme
    local priceMode = (T and T.GetPriceDisplayMode and T.GetPriceDisplayMode()) or 'compact'
    local qty = queuedQtyFor(data)
    local cd = data.cdInfo
    local cdAvail = cd and cd.available
    local cdOn = cd and cd.onCooldown
    local cdRem = cd and cd.remainingSeconds
    local sc = type(data.sourceCost) == 'table' and data.sourceCost or nil
    local scKnown = sc and sc.known
    local scCopper = sc and sc.copper
    local dm = type(data.demand) == 'table' and data.demand or nil
    local dmText = dm and (dm.heatBadge or dm.stateLabel)
    local bi = type(data.bisInfo) == 'table' and data.bisInfo or nil
    local biText = bi and bi.cellText
    local biFlag = bi and bi.isBiS
    local ca = type(data.craftAbility) == 'table' and data.craftAbility or nil
    local caActive = ca and ca.knownOnActive
    local entry = cellValueCache[data]
    if entry
        and entry.pal == pal
        and entry.palMode == palMode
        and entry.palSkin == palSkin
        and entry.priceMode == priceMode
        and entry.epoch == cellCacheEpoch
        and entry.ver == data._ver
        and entry.profit == data.profit
        and entry.unitAH == data.unitAH
        and entry.craftCost == data.craftCost
        and entry.buyCost == data.buyCostCopper
        and entry.buyEst == data.buyCostEstimated
        and entry.turnover == data.turnoverPerDay
        and entry.sales == data.salesPerDay
        and entry.listed == data.listed
        and entry.owned == data.ownedOutputQty
        and entry.known == data.known
        and entry.cdInfo == cd
        and entry.cdAvail == cdAvail
        and entry.cdOn == cdOn
        and entry.cdRem == cdRem
        and entry.demand == dm
        and entry.dmText == dmText
        and entry.bisInfo == bi
        and entry.biText == biText
        and entry.biFlag == biFlag
        and entry.goodShort == data.goodShort
        and entry.nameRaw == data.name
        and entry.craftAbility == ca
        and entry.caActive == caActive
        and entry.sourceCost == sc
        and entry.scKnown == scKnown
        and entry.scCopper == scCopper
        and entry.reqRep == data.reqRep
        and entry.repLabel == data.repLabel then
        if entry.shift ~= shiftActive or entry.qty ~= qty then
            local greenHex = (pal and pal.hexPositive) or cachedGreenHex or '30d158'
            local nameTxt = text(data.name)
            if not shiftActive and qty > 0 then
                nameTxt = '|cff'..greenHex..'['..tostring(qty)..'x]|r '..nameTxt
            end
            entry.values.name = nameTxt
            entry.shift = shiftActive
            entry.qty = qty
        end
        return entry.values
    end
    local prof = (ns.PROF_BY_KEY or {})[data.prof]
    local level = (prof and (prof.short or prof.label) or text(data.prof):sub(1,3))..' '..tostring(number(data.requiredSkill) or 'n/a')
    local greenHex = (pal and pal.hexPositive) or cachedGreenHex or '30d158'
    local nameTxt = text(data.name)
    if not shiftActive and qty > 0 then
        nameTxt = '|cff'..greenHex..'['..tostring(qty)..'x]|r '..nameTxt
    end
    local repTxt = (number(data.reqRep) and data.reqRep>0) and (text(data.repLabel)~='' and text(data.repLabel) or ('Rep '..tostring(data.reqRep))) or '—'
    local knownText = 'No'
    if data.known then
        if ca and ca.knownOnActive==false and type(ca.knownAltNames)=='table' and #ca.knownAltNames>0 then
            knownText = 'Alt'
        else
            knownText = 'Yes'
        end
    end
    local v = (entry and entry.values) or {}
    v.name = nameTxt
    v.knownSort = knownText
    v.cdSort = formatCooldownCell(cd)
    v.ownedOutputQty = tostring(number(data.ownedOutputQty) or 0)
    v.listed = number(data.listed) and tostring(data.listed) or 'n/a'
    v.goodScore = themeText(data.goodShort) or 'n/a'
    v.buyCostCopper = money(data.buyCostCopper)..(data.buyCostEstimated and '*' or '')
    v.craftCost = money(data.craftCost)
    v.unitAH = money(data.unitAH)
    v.salesPerDay = formatSalesCell(data.salesPerDay, pal)
    v.turnoverPerDay = money(data.turnoverPerDay)
    v.demandSort = themeText(dmText) or ''
    v.profit = money(data.profit, true)
    v.requiredSkill = level
    v.skillupSort = formatSkillupCell(data, pal)
    v.sourceLabel = text(data.sourceLabel)
    v.sourceCost = themeText(actualCost(data)) or 'n/a'
    v.repSort = repTxt
    v.bisSort = formatBisCell(bi)
    v.wowheadURL = data.wowheadURL and 'WH' or 'n/a'
    if not entry then
        entry = { values = v }
        cellValueCache[data] = entry
    end
    entry.pal = pal
    entry.palMode = palMode
    entry.palSkin = palSkin
    entry.priceMode = priceMode
    entry.epoch = cellCacheEpoch
    entry.ver = data._ver
    entry.profit = data.profit
    entry.unitAH = data.unitAH
    entry.craftCost = data.craftCost
    entry.buyCost = data.buyCostCopper
    entry.buyEst = data.buyCostEstimated
    entry.turnover = data.turnoverPerDay
    entry.sales = data.salesPerDay
    entry.listed = data.listed
    entry.owned = data.ownedOutputQty
    entry.known = data.known
    entry.cdInfo = cd
    entry.cdAvail = cdAvail
    entry.cdOn = cdOn
    entry.cdRem = cdRem
    entry.demand = dm
    entry.dmText = dmText
    entry.bisInfo = bi
    entry.biText = biText
    entry.biFlag = biFlag
    entry.goodShort = data.goodShort
    entry.nameRaw = data.name
    entry.craftAbility = ca
    entry.caActive = caActive
    entry.sourceCost = sc
    entry.scKnown = scKnown
    entry.scCopper = scCopper
    entry.reqRep = data.reqRep
    entry.repLabel = data.repLabel
    entry.shift = shiftActive
    entry.qty = qty
    return v
end
local function measureCell(key,value,header)
    local str=tostring(value or '')
    local cacheName=header and 'measuredHeaders' or 'measuredStrings'
    local cache=tbl[cacheName]
    if not cache then cache={}; tbl[cacheName]=cache end
    local column=cache[key]
    if not column then column={}; cache[key]=column end
    if column[str] then return end
    local fs=view.measure
    local hdrBtn=tbl.headerBtnsByKey and tbl.headerBtnsByKey[key]
    local reference=header and (hdrBtn and hdrBtn.fs or view.cellFont) or view.cellFont
    fs:SetFont(reference:GetFont())
    local icons=0
    local stripped=str
    if str:find('|',1,true) then
        local s,n=str:gsub('|T.-|t','')
        icons=n
        stripped=s:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
    end
    fs:SetText(str)
    local rawW=fs:GetStringWidth() or 0
    local w=rawW
    if rawW==0 and (#stripped>0 or icons>0) then w=math.max(w,icons*11+#stripped*6.2) end
    local padding=header and 4 or (key=='name' and 23 or 4)
    local need=math.ceil(w+padding)
    local masterCol=MASTER_BY_KEY[key]
    if masterCol then masterCol.minWidth=math.max(masterCol.minWidth or masterCol.width,need) end
    local minChanged=false
    for _,col in ipairs(tbl.columns or {}) do
        if col.key==key then
            local prevMin=col.minWidth or col.width
            if need>prevMin then
                col.minWidth=need
                minChanged=true
            end
            break
        end
    end
    if minChanged then tbl._layoutDirty=true end
    if rawW>0 then column[str]=true end
end
local function measureRowsOnce(dataRows,yieldSlice)
    local visible=shown(view) or (view.measure:GetStringWidth() or 0)>0
    local mark=visible and 'vis' or 'est'
    local prior=tbl.measuredDataset[dataRows]
    local total=#dataRows
    if type(prior)=='table' then
        if (prior.mark=='vis' or (prior.mark=='est' and not visible)) and prior.count==total then return end
    elseif prior=='vis' or (prior=='est' and not visible) then
        return
    end
    local ms
    if type(prior)=='table' and (prior.mark==mark or not visible) then
        ms=prior
    else
        ms={count=0,done=0,mark=mark,maxSkillByProf={}}
        tbl.measuredDataset[dataRows]=ms
    end
    local startIdx=(ms.done or 0)+1
    local prevDone=ms.done or 0
    local maxSkillByProf=ms.maxSkillByProf
    for i=startIdx,total do
        local row=dataRows[i]
        local value=row.ownedOutputQty
        if type(value)=='number' and value==value and (not ms.maxOwned or value>ms.maxOwned) then ms.maxOwned=value end
        value=row.buyCostCopper
        if type(value)=='number' and value==value then
            if row.buyCostEstimated then if not ms.maxBuyEst or value>ms.maxBuyEst then ms.maxBuyEst=value end
            elseif not ms.maxBuy or value>ms.maxBuy then ms.maxBuy=value end
        end
        value=row.craftCost
        if type(value)=='number' and value==value and (not ms.maxCraft or value>ms.maxCraft) then ms.maxCraft=value end
        value=row.unitAH
        if type(value)=='number' and value==value and (not ms.maxAH or value>ms.maxAH) then ms.maxAH=value end
        value=row.salesPerDay
        if type(value)=='number' and value==value and (not ms.maxSales or value>ms.maxSales) then ms.maxSales=value end
        value=row.turnoverPerDay
        if type(value)=='number' and value==value and (not ms.maxTurn or value>ms.maxTurn) then ms.maxTurn=value end
        value=row.profit
        if type(value)=='number' and value==value then
            if value>=0 then if not ms.maxProfit or value>ms.maxProfit then ms.maxProfit=value end
            elseif not ms.minProfit or value<ms.minProfit then ms.minProfit=value end
        end
        value=row.requiredSkill
        if type(value)=='number' and value==value then
            local skill=maxSkillByProf[row.prof]
            if not skill or value>skill then maxSkillByProf[row.prof]=value end
        end
        local cost=row.sourceCost
        if cost then
            local copper=type(cost.copper)=='number' and cost.copper==cost.copper and cost.copper or 0
            local favor=cost.currencies and cost.currencies[ns.FAVOR_CURRENCY_ID or 3402]
            if type(favor)~='number' or favor~=favor then favor=0 end
            if favor>0 and copper>0 then
                if not ms.maxSrcMixC or copper>ms.maxSrcMixC then ms.maxSrcMixC=copper end
                if not ms.maxSrcMixF or favor>ms.maxSrcMixF then ms.maxSrcMixF=favor end
            elseif favor>0 and (not ms.maxSrcFavor or favor>ms.maxSrcFavor) then ms.maxSrcFavor=favor
            elseif copper>0 and (not ms.maxSrcCopper or copper>ms.maxSrcCopper) then ms.maxSrcCopper=copper
            end
        end
        local best=row.bisInfo and row.bisInfo.cellText
        if type(best)=='string' and (not ms.longestBest or #best>#ms.longestBest) then ms.longestBest=best end
        ms.done=i
        if i%256==0 then yieldSlice() end
    end
    if prevDone<total or ms.mark~=mark then
        if ms.maxOwned then measureCell('ownedOutputQty',tostring(ms.maxOwned)) end
        if ms.maxBuy then measureCell('buyCostCopper',moneyCompact(ms.maxBuy)) end
        if ms.maxBuyEst then measureCell('buyCostCopper',moneyCompact(ms.maxBuyEst)..'*') end
        if ms.maxCraft then measureCell('craftCost',moneyCompact(ms.maxCraft)) end
        if ms.maxAH then measureCell('unitAH',moneyCompact(ms.maxAH)) end
        if ms.maxSales then measureCell('salesPerDay',formatSalesCell(ms.maxSales)) end
        if ms.maxTurn then measureCell('turnoverPerDay',moneyCompact(ms.maxTurn)) end
        if ms.maxProfit then measureCell('profit',moneyCompact(ms.maxProfit,true)) end
        if ms.minProfit then measureCell('profit',moneyCompact(ms.minProfit,true)) end
        if ms.maxSrcCopper then measureCell('sourceCost',moneyCompact(ms.maxSrcCopper)) end
        if ms.maxSrcFavor then measureCell('sourceCost',tostring(ms.maxSrcFavor)..' Favor') end
        if ms.maxSrcMixC and ms.maxSrcMixF then measureCell('sourceCost',moneyCompact(ms.maxSrcMixC)..' + '..tostring(ms.maxSrcMixF)..' Favor') end
        for profKey,skill in pairs(maxSkillByProf) do
            local prof=(ns.PROF_BY_KEY or {})[profKey]
            measureCell('requiredSkill',(prof and (prof.short or prof.label) or text(profKey):sub(1,3))..' '..tostring(skill))
        end
        if ms.longestBest then measureCell('bisSort',ms.longestBest) end
    end
    ms.count=total
    ms.mark=mark
end
local transientCells
local function runGuarded(fn)
    local ok,err=pcall(fn)
    if ok then return end
    local cancel=cancelBuild or (buildState and buildState.cancel)
    pending,cancelBuild,reconcilePending,transientCells=false,nil,false,nil
    if cancel then pcall(cancel) end
    generation=generation+1; presentSeq=presentSeq+1; uiCache.prewarmSeq=(uiCache.prewarmSeq or 0)+1
    uiCache.reconcileSeq=(uiCache.reconcileSeq or 0)+1
    uiCache.inFlightPresent=nil
    uiCache.boundResult=nil; uiCache.boundFilterKey=nil; uiCache.earlyPresentedFilterKey=nil; uiCache.earlyBoundResult=nil; uiCache.earlyCountShown=nil
    if ns.ResetEval then ns.ResetEval() end
    error(err,0)
end
local function laterGuarded(fn) later(function() runGuarded(fn) end) end
local fallbackText={1,1,1}
local fallbackMuted={0.6,0.6,0.6}
local fallbackSecondary={0.82,0.82,0.85}
local fallbackPillText={0.88,0.88,0.90}
local fallbackGreen={0.20,0.78,0.35}
local fallbackOrange={1,0.55,0.16}
local fallbackRed={1,0.26,0.27}
local lightRed={0.722,0.078,0.102}
local function paintRowCells(r,values,pal)
    local textCol=(pal and pal.text) or fallbackText
    local mutedCol=(pal and pal.textMuted) or fallbackMuted
    local secCol=(pal and pal.textSecondary) or fallbackSecondary
    local pillMutedCol=(pal and pal.text) or fallbackPillText
    local greenCol=(pal and pal.accentGreen) or fallbackGreen
    local orangeCol=(pal and pal.accentOrange) or fallbackOrange
    local data=r.data
    local isLight=(pal and pal.mode=='light')
    local redCol=isLight and lightRed or ((pal and pal.accentRed) or fallbackRed)
    for i,cell in ipairs(r.cells) do
        local key=tbl.columns[i].key
        local txt=values[key]
        if cell._lastText~=txt or cell._textPalette~=pal then
            cell._lastText,cell._textPalette=txt,pal
            if cell.fs._mmThemedText then
                cell.fs:SetText(txt,true)
            else
                cell.fs:SetText(txt)
            end
        end
        local color,kind=textCol,nil
        if key=='name' then
            if txt=='n/a' then color=mutedCol end
            if cell._icon~=data.icon then
                cell._icon=data.icon
                cell.icon:SetTexture(data.icon)
            end
            local glyphAlpha=isLight and 0.12 or 0.24
            if cell.glyphBg and cell._glyphAlpha~=glyphAlpha then
                cell._glyphAlpha=glyphAlpha
                cell.glyphBg:SetVertexColor(0.463,0.463,0.502,glyphAlpha)
            end
        elseif key=='knownSort' then
            color=data.known and greenCol or redCol
        elseif key=='cdSort' then
            if txt=='R' then color=greenCol
            elseif txt~='-' then
                color=(data.cdInfo and data.cdInfo.onCooldown) and redCol or secCol
            end
        elseif key=='listed' then
            if txt=='0' then color=orangeCol
            elseif txt=='n/a' then color=mutedCol end
        elseif key=='repSort' then
            if number(data.reqRep) and data.reqRep>0 then
                color=(data.repMet~=false) and greenCol or redCol
            else
                color=mutedCol
            end
        elseif txt=='n/a' then
            color=mutedCol
        elseif key=='demandSort' then
            color,kind=pillMutedCol,'neutral'
            local low=txt:lower()
            if low:find('hot',1,true) or low:find('monop',1,true) or low:find('surge',1,true) then
                color,kind=orangeCol,'hot'
            elseif low:find('fav',1,true) or low:find('warm',1,true) or low:find('fast',1,true) then
                color,kind=greenCol,'pos'
            end
            if cell.heatStrip then
                local strip=getHeatStripForRow(data)
                if strip then
                    local colW=(tbl and tbl.columns and tbl.columns[i] and tbl.columns[i].width) or 48
                    cell.heatStrip:Bind(strip,pal,currentLocalHour())
                    cell.heatStrip:Layout(math.max(24,colW-4))
                    if cell._fsOffsetY~=2 then
                        cell._fsOffsetY=2
                        cell.fs:ClearAllPoints()
                        cell.fs:SetPoint('LEFT',2,2)
                        cell.fs:SetPoint('RIGHT',-2,2)
                    end
                    cell._heatStripBound=true
                    if not cell._heatTipBound then
                        cell:SetScript('OnEnter',heatCellOnEnter)
                        cell:SetScript('OnLeave',leaveTooltip)
                        cell._heatTipBound=true
                    end
                else
                    if cell._heatStripBound then
                        cell.heatStrip:Clear()
                        cell._heatStripBound=false
                    end
                    if cell._heatTipBound then
                        leaveTooltip(cell)
                        cell:SetScript('OnEnter',nil)
                        cell:SetScript('OnLeave',nil)
                        cell._heatTipBound=false
                    end
                    if cell._fsOffsetY~=0 and cell._fsOffsetY~=nil then
                        cell._fsOffsetY=0
                        cell.fs:ClearAllPoints()
                        cell.fs:SetPoint('LEFT',2,0)
                        cell.fs:SetPoint('RIGHT',-2,0)
                    end
                end
            end
        elseif key=='bisSort' then
            if data.bisInfo and data.bisInfo.isBiS then color,kind=greenCol,'pos'
            else color,kind=pillMutedCol,'neutral' end
        elseif key=='wowheadURL' then
            color,kind=secCol,'neutral'
        elseif key=='requiredSkill' or key=='sourceLabel' then
            color=secCol
        end
        if cell._textColor~=color then
            cell._textColor=color
            cell.fs:SetTextColor(color[1],color[2],color[3],1)
        end
        if cell.pillBg then styleCellPill(cell,kind,pal) end
    end
end
local function bindRow(r,data,t)
    if not r.cells then
        host.applyRowHighlight(r)
        if #prepared==0 then prepareCells() end
        r.cellGroup=table.remove(prepared)
        r.cellGroup:SetParent(r); r.cellGroup:SetAllPoints(r); r.cellGroup:Show()
        r.cells=r.cellGroup.cells
        r._colEpoch=r.cellGroup._colEpoch
        r._layoutEpoch=r.cellGroup._layoutEpoch
        r:RegisterForClicks('LeftButtonUp','RightButtonUp')
        r:SetScript('OnHide',function(self)
            hideRowTooltip(self)
            if self.shiftStepper and self.shiftStepper.Hide then self.shiftStepper:Hide() end
            if not shown(self) then
                closeHeatPopover(self)
                self.data=nil; self.cellGroup.data=nil
            end
        end)
        r:SetScript('OnClick',function(self,button) selectRow(self.data,button) end)
    end
    if r._colEpoch~=colEpoch then syncRowCells(r) end
    if tbl and tbl.layoutRow and r._layoutEpoch~=tbl._layoutEpoch then tbl.layoutRow(r) end
    -- Every click and tooltip reads r.data, so no closure retains a previous recipe.
    hideRowTooltip(r)
    if r.data~=data then
        closeHeatPopover(r)
        if tooltipRow==r.data then clearTooltipCache() end
    end
    r.data=data; r.cellGroup.data=data
    local values=(transientCells and transientCells[data]) or cellValues(data)
    paintRowCells(r,values,getThemePalette())
    paintSelection(r)
end
local function rebindStaleRows()
    if not tbl or not tbl.scrollBox or not tbl.scrollBox.ForEachFrame then return end
    local needsRebind=false
    tbl.scrollBox:ForEachFrame(function(r)
        if r.cells and r.data==nil and shown(r) then
            local elData=type(r.GetElementData)=='function' and r:GetElementData() or nil
            if elData then
                bindRow(r,elData,tbl)
            else
                needsRebind=true
            end
        end
    end)
    if needsRebind then
        if tbl.scrollBox.ReinitializeFrames then
            tbl.scrollBox:ReinitializeFrames()
        elseif uiCache.boundResult then
            tbl.setRows(uiCache.boundResult)
        elseif tbl.scrollBox.FullUpdate then
            tbl.scrollBox:FullUpdate()
        end
    end
end
local function active() return not host.isActive or host.isActive() end
local function migrateSources(db)
    if type(db.superListSources)~='table' then db.superListSources={} end
    if db.merchantVendorOnly==true and not next(db.superListSources) then db.superListSources={merchant=true} end
    db.merchantVendorOnly=false
end
local function sourceLabel(db)
    local labels={}
    for _,s in ipairs(sources) do if s.key~='all' and db.superListSources[s.key] then labels[#labels+1]=s.key=='merchant' and 'Merchant' or s.label end end
    if #labels==0 then return 'Sources: All' end
    if #labels==1 then return 'Sources: '..labels[1] end
    if #labels==2 then return 'Src: '..table.concat(labels,' + ') end
    return 'Sources: '..#labels..' selected'
end
local function syncSkills(db)
    local lo=ns.SuperListModel.SkillBound(db.superListSkillMin)
    local hi=ns.SuperListModel.SkillBound(db.superListSkillMax)
    db.superListSkillMin,db.superListSkillMax=lo,hi
    view.skillMin:SetText(lo and tostring(lo) or '')
    view.skillMax:SetText(hi and tostring(hi) or '')
    view.skillError:SetText(lo and hi and lo>hi and 'Min exceeds max' or '')
end
local fingerprint
local function resolveSort(db)
    local st=host.getSort()
    if st.col=='uniqueSellers' then
        st.col,st.asc='profit',false
        if db and db.sort then db.sort.recipes={col='profit',asc=false} end
    end
    return st.col,st.asc==true
end
local function buildFilterKey(context, col, asc)
    local db=context.db or {}
    return fingerprint({col=col,asc=asc,search=text(context.search),profFilter=context.profFilter or 'all',
        profMap=context.profMap,unlockFilter=context.unlockFilter or 'all',
        knownRecipesOnly=context.knownRecipesOnly==true,allChars=context.craftableAllChars==true,sellableFilter=db.sellableFilter or 'all',
        craftableFilter=db.craftableFilter or 'all',demandFilter=db.demandFilter or 'all',
        bisOnly=db.bisOnly==true,skillMin=db.superListSkillMin,skillMax=db.superListSkillMax,
        sources=db.superListSources})
end
local function present(sourceRows, warmTotal)
    local dataRows=sourceRows or rows
    if not latest or not dataRows or not active() then return end
    presentSeq=presentSeq+1
    uiCache.prewarmSeq=(uiCache.prewarmSeq or 0)+1
    local mySeq=presentSeq
    local token=generation
    local function current()
        return mySeq==presentSeq and token==generation and active()
            and not (buildState and buildState.completed and rows and dataRows~=rows)
    end
    local c,db=latest,latest.db
    migrateSources(db)
    local col,asc=resolveSort(db)
    local fKey=buildFilterKey(c,col,asc)
    local presentSig,presentMetaEpoch=signature,uiCache.metaEpoch
    local function clearInFlight()
        if uiCache.inFlightPresent and uiCache.inFlightPresent.seq==mySeq then
            uiCache.inFlightPresent=nil
        end
    end
    uiCache.inFlightPresent={
        seq=mySeq, sig=presentSig, metaEpoch=presentMetaEpoch, fKey=fKey,
        dataRows=dataRows, warmTotal=warmTotal,
        hasRepair=repairPatch~=nil, hasMeta=metaPatch~=nil,
    }
    local aliases={ahValue='unitAH',dailySold='salesPerDay',profLabel='requiredSkill',listedSort='listed',canCraftSort='sourceLabel',sourceCost='buyCostCopper',wowheadURL='name'}
    local filters={sources=db.superListSources,search=c.search,profFilter=c.profFilter,
        profMap=c.profMap,unlockFilter=c.unlockFilter,knownRecipesOnly=c.knownRecipesOnly,sellableFilter=db.sellableFilter,
        craftableFilter=db.craftableFilter,demandFilter=db.demandFilter,bisOnly=db.bisOnly,
        skillMin=db.superListSkillMin,skillMax=db.superListSkillMax}
    local sort={key=aliases[col] or col,ascending=asc}
    local numeric={ownedOutputQty=true,buyCostCopper=true,craftCost=true,unitAH=true,salesPerDay=true,
        turnoverPerDay=true,demandSort=true,profit=true,requiredSkill=true,bisSort=true,listed=true,
        canCraftSort=true,marginPct=true,ownedScrollQty=true,numMade=true,
        knownSort=true,goodScore=true,repSort=true,cdSort=true}
    local sortWorkspace={values={},profs={},names={},keys={},keepEntries=true}
    -- Merge already filtered/sorted blocks with the model's unknown-last and identity ordering.
    local function before(a,b)
        local av,bv=sortWorkspace.values[a],sortWorkspace.values[b]
        if numeric[sort.key] then
            if av==false and bv~=false then return false end
            if av~=false and bv==false then return true end
            if av~=false and av~=bv then if sort.ascending then return av<bv else return av>bv end end
        else
            if av~=bv then if sort.ascending then return av<bv else return av>bv end end
        end
        local ap,bp=sortWorkspace.profs[a],sortWorkspace.profs[b]
        if ap~=bp then return ap<bp end
        local an,bn=sortWorkspace.names[a],sortWorkspace.names[b]
        if an~=bn then return an<bn end
        return sortWorkspace.keys[a]<sortWorkspace.keys[b]
    end
    local deadline
    local function yieldBudget() if clockMS()>=deadline then coroutine.yield() end end
    local job=coroutine.create(function()
        local runs={}
        while repairPatch do
            yieldBudget()
            local done,_,needFull=ns.RecipeStats.RepairSlice(repairPatch,evaluation,8,math.max(0.1,deadline-clockMS()))
            cellCacheEpoch=cellCacheEpoch+1
            if done then
                repairPatch=nil
                if needFull then forceVersion=forceVersion+1 end
                if needFull or next(itemChanges) then
                    laterGuarded(function() if current() then provider.Refresh(latest) end end)
                    return
                end
            end
        end
        yieldBudget()
        while metaPatch and type(ns.RecipeStats.PatchMetaSlice)=='function' do
            local patch=metaPatch
            local target=patch.target
            local cap=patch.cap or (target and #target) or 0
            if not target or patch.index>cap then
                metaPatch=nil
                break
            end
            yieldBudget()
            if metaPatch~=patch then break end
            local nextIdx,done=ns.RecipeStats.PatchMetaSlice(target,evaluation,patch.index,64,math.max(0.5,deadline-clockMS()),cap)
            cellCacheEpoch=cellCacheEpoch+1
            patch.index=nextIdx
            if done or nextIdx>cap then
                metaPatch=nil
                yieldBudget()
                break
            end
            yieldBudget()
        end
        measureRowsOnce(dataRows,yieldBudget)
        for first=1,#dataRows,96 do
            local block={}
            for i=first,math.min(first+95,#dataRows) do
                if i>first and (i-first)%24==0 then yieldBudget() end
                block[#block+1]=dataRows[i]
            end
            yieldBudget()
            runs[#runs+1]=ns.SuperListModel.FilterSort(block,filters,sort,sortWorkspace)
            yieldBudget()
        end
        while #runs>1 do
            local nextRuns={}
            for i=1,#runs,2 do
                local a,b=runs[i],runs[i+1]
                if not b then nextRuns[#nextRuns+1]=a else
                    local merged,ai,bi={},1,1
                    while ai<=#a or bi<=#b do
                        if bi>#b or (ai<=#a and before(a[ai],b[bi])) then merged[#merged+1]=a[ai]; ai=ai+1
                        else merged[#merged+1]=b[bi]; bi=bi+1 end
                        if (#merged)%24==0 then yieldBudget() end
                    end
                    nextRuns[#nextRuns+1]=merged
                end
                yieldBudget()
            end
            runs=nextRuns
        end
        return runs[1] or {}
    end)
    local function step()
        if not current() then clearInFlight(); return end
        deadline=clockMS()+1.8
        local ok,result=coroutine.resume(job)
        if not ok then clearInFlight(); error(result) end
        if coroutine.status(job)~='dead' then laterGuarded(step); return end
        if not result then clearInFlight(); return end
        -- Row widget binding gets its own callback rather than extending the sorting slice.
        local laidOut, preformatted, preformattedIdx = false, {}, 0
        local function commit()
            if not current() then clearInFlight(); return end
            -- Prepare cell widgets in bounded slices before native rows are bound together.
            local needed=math.ceil(math.max(1,tbl.scrollBox:GetHeight())/host.rowHeight)+4
            local existing=0
            tbl.scrollBox:ForEachFrame(function(r) if r.cells then existing=existing+1 end end)
            local target=math.max(0,math.min(#result,needed)-existing)
            if not laidOut then
                laidOut=true
                local width=host.parent and host.parent:GetWidth() or view:GetWidth()
                uiCache.boundWidth=width
                -- The data-provider swap will refresh the ScrollBox after cells are ready.
                provider.Layout(width,nil,true)
                tbl.updateHeaders()
                laterGuarded(commit); return
            end
            if #prepared<target then
                local started=clockMS()
                for _=1,2 do
                    prepareCells()
                    if #prepared>=target or clockMS()-started>=0.8 then break end
                end
                laterGuarded(commit); return
            end
            local preTarget=math.min(#result,needed)
            if preformattedIdx<preTarget then
                local started=clockMS()
                for i=1,8 do
                    preformattedIdx=preformattedIdx+1
                    local row=result[preformattedIdx]
                    preformatted[row]=cellValues(row)
                    if preformattedIdx>=preTarget or clockMS()-started>=0.9 then break end
                end
                laterGuarded(commit); return
            end
            if not current() then clearInFlight(); return end
            clearInFlight()
            transientCells=preformatted
            uiCache.viewWasHidden=false
            tbl.setRows(result)
            transientCells=nil
            if sourceRows and warmTotal then
                uiCache.earlyBoundResult=result
                uiCache.earlyCountShown=#result
                uiCache.earlyTier1Done=#dataRows
                uiCache.earlyWarmTotal=warmTotal
                uiCache.earlyPresentedFilterKey=fKey
                local doneNow=buildState and #(buildState.rows or {}) or #dataRows
                view.summary:SetText(string.format('%d / %d recipes (warming %d/%d)',#result,#dataRows,doneNow,warmTotal))
            else
                uiCache.retainedResult=result
                uiCache.retainedDatasetSig=presentSig
                uiCache.retainedFilterKey=fKey
                uiCache.retainedMetaEpoch=presentMetaEpoch
                uiCache.filterLRU:put(uiCache.makeLRUKey(presentSig,presentMetaEpoch,fKey),result,uiCache.metaSensitivityTags(db and db.craftableFilter,col))
                uiCache.boundResult=result
                uiCache.boundDatasetSig=presentSig
                uiCache.boundFilterKey=fKey
                uiCache.boundMetaEpoch=presentMetaEpoch
                uiCache.earlyPresentedFilterKey=nil
                uiCache.earlyBoundResult=nil
                uiCache.earlyCountShown=nil
                view.summary:SetText(string.format('%d / %d recipes',#result,#dataRows))
            end
            host.statusText:SetText(c.scanBanner or string.format('%d recipes - %s',#result,c.econInfo and c.econInfo.label or 'selected economy'))
            local top=result[1]; provider.bestProfit=top and top.profit
        end
        laterGuarded(commit)
    end
    laterGuarded(step)
end
function uiCache.notifyWarmComplete()
    if ns.app and type(ns.app.onSuperListWarmComplete)=='function' then
        ns.app.onSuperListWarmComplete()
    end
end
function uiCache.prewarmPresentation(context)
    local dataRows=rows
    if not context or not dataRows or not view or not tbl or not host or active() then
        if not active() and buildState and buildState.completed then uiCache.notifyWarmComplete() end
        return
    end
    uiCache.prewarmSeq=(uiCache.prewarmSeq or 0)+1
    local myPreSeq=uiCache.prewarmSeq
    local token=generation
    local preSig,preMetaEpoch=signature,uiCache.metaEpoch
    local function preCurrent()
        return myPreSeq==uiCache.prewarmSeq and token==generation and not active()
            and buildState and buildState.completed and rows==dataRows
            and signature==preSig and uiCache.metaEpoch==preMetaEpoch
    end
    local db=context.db or _G.MerchantMasterDB or {}
    migrateSources(db)
    local col,asc=resolveSort(db)
    local fKey=buildFilterKey(context,col,asc)
    local lruKey=uiCache.makeLRUKey(preSig,preMetaEpoch,fKey)
    local function prewarmWidgets(result)
        if not preCurrent() then return end
        local inCombat=_G.InCombatLockdown and _G.InCombatLockdown()
        if not inCombat and tbl and tbl.scrollBox then
            local rowH=(host and host.rowHeight) or 22
            local boxH=(tbl.scrollBox.GetHeight and tbl.scrollBox:GetHeight()) or 520
            local needed=math.max(24,math.min(30,math.ceil(math.max(1,boxH)/rowH)+4))
            local existing=0
            if tbl.scrollBox.ForEachFrame then
                tbl.scrollBox:ForEachFrame(function(r) if r.cells then existing=existing+1 end end)
            end
            local target=math.max(0,math.min(#result,needed)-existing)
            if #prepared<target then
                local started=clockMS()
                for _=1,4 do
                    prepareCells()
                    if #prepared>=target or clockMS()-started>=0.9 then break end
                end
                if #prepared<target then
                    laterGuarded(function() prewarmWidgets(result) end)
                    return
                end
            end
        end
        if preCurrent() then uiCache.notifyWarmComplete() end
    end
    local cached=uiCache.retainedResult and uiCache.retainedDatasetSig==preSig
        and uiCache.retainedFilterKey==fKey and uiCache.retainedMetaEpoch==preMetaEpoch and uiCache.retainedResult
        or uiCache.filterLRU:get(lruKey)
    if cached then
        uiCache.retainedResult=cached
        uiCache.retainedDatasetSig=preSig
        uiCache.retainedFilterKey=fKey
        uiCache.retainedMetaEpoch=preMetaEpoch
        laterGuarded(function() prewarmWidgets(cached) end)
        return
    end
    local aliases={ahValue='unitAH',dailySold='salesPerDay',profLabel='requiredSkill',listedSort='listed',canCraftSort='sourceLabel',sourceCost='buyCostCopper',wowheadURL='name'}
    local filters={sources=db.superListSources,search=context.search,profFilter=context.profFilter,
        profMap=context.profMap,unlockFilter=context.unlockFilter,knownRecipesOnly=context.knownRecipesOnly,sellableFilter=db.sellableFilter,
        craftableFilter=db.craftableFilter,demandFilter=db.demandFilter,bisOnly=db.bisOnly,
        skillMin=db.superListSkillMin,skillMax=db.superListSkillMax}
    local sort={key=aliases[col] or col,ascending=asc}
    local numeric={ownedOutputQty=true,buyCostCopper=true,craftCost=true,unitAH=true,salesPerDay=true,
        turnoverPerDay=true,demandSort=true,profit=true,requiredSkill=true,bisSort=true,listed=true,
        canCraftSort=true,marginPct=true,ownedScrollQty=true,numMade=true,
        knownSort=true,goodScore=true,repSort=true,cdSort=true}
    local sortWorkspace={values={},profs={},names={},keys={},keepEntries=true}
    local function before(a,b)
        local av,bv=sortWorkspace.values[a],sortWorkspace.values[b]
        if numeric[sort.key] then
            if av==false and bv~=false then return false end
            if av~=false and bv==false then return true end
            if av~=false and av~=bv then if sort.ascending then return av<bv else return av>bv end end
        else
            if av~=bv then if sort.ascending then return av<bv else return av>bv end end
        end
        local ap,bp=sortWorkspace.profs[a],sortWorkspace.profs[b]
        if ap~=bp then return ap<bp end
        local an,bn=sortWorkspace.names[a],sortWorkspace.names[b]
        if an~=bn then return an<bn end
        return sortWorkspace.keys[a]<sortWorkspace.keys[b]
    end
    local deadline
    local function yieldBudget() if clockMS()>=deadline then coroutine.yield() end end
    local job=coroutine.create(function()
        local runs={}
        measureRowsOnce(dataRows,yieldBudget)
        for first=1,#dataRows,96 do
            local block={}
            for i=first,math.min(first+95,#dataRows) do
                if i>first and (i-first)%24==0 then yieldBudget() end
                block[#block+1]=dataRows[i]
            end
            yieldBudget()
            runs[#runs+1]=ns.SuperListModel.FilterSort(block,filters,sort,sortWorkspace)
            yieldBudget()
        end
        while #runs>1 do
            local nextRuns={}
            for i=1,#runs,2 do
                local a,b=runs[i],runs[i+1]
                if not b then nextRuns[#nextRuns+1]=a else
                    local merged,ai,bi={},1,1
                    while ai<=#a or bi<=#b do
                        if bi>#b or (ai<=#a and before(a[ai],b[bi])) then merged[#merged+1]=a[ai]; ai=ai+1
                        else merged[#merged+1]=b[bi]; bi=bi+1 end
                        if (#merged)%24==0 then yieldBudget() end
                    end
                    nextRuns[#nextRuns+1]=merged
                end
                yieldBudget()
            end
            runs=nextRuns
        end
        return runs[1] or {}
    end)
    local function step()
        if not preCurrent() then return end
        deadline=clockMS()+1.2
        local ok,result=coroutine.resume(job)
        if not ok then error(result) end
        if coroutine.status(job)~='dead' then laterGuarded(step); return end
        if not result or not preCurrent() then return end
        uiCache.retainedResult=result
        uiCache.retainedDatasetSig=preSig
        uiCache.retainedFilterKey=fKey
        uiCache.retainedMetaEpoch=preMetaEpoch
        uiCache.filterLRU:put(lruKey,result,uiCache.metaSensitivityTags(db and db.craftableFilter,col))
        laterGuarded(function() prewarmWidgets(result) end)
    end
    laterGuarded(step)
end
fingerprint=function(value)
    if not readable(value) then return '?' end
    if type(value)~='table' then return tostring(value) end
    local parts={}
    for k,v in pairs(value) do
        if readable(k) and readable(v) and type(v)~='function' then parts[#parts+1]=tostring(k)..'='..fingerprint(v) end
    end
    table.sort(parts); return '{'..table.concat(parts,',')..'}'
end
function provider.CancelPresentation()
    presentSeq=presentSeq+1; pending=false; uiCache.viewWasHidden=true; uiCache.inFlightPresent=nil
    if buildState and buildState.running then
        buildState.background=true
        buildState.onProgress=nil
        buildState.onTierReady=nil
        if evaluation then evaluation.background=true end
    end
end
function uiCache.applyPendingChanges()
    local itemsOnly=changes.items==true
    for chReason in pairs(changes) do
        if chReason~='items' then itemsOnly=false end
        if chReason~='ownership' and chReason~='snapshot' and chReason~='trainer' and chReason~='items' and
            chReason~='skills' and chReason~='known' and chReason~='rep' and chReason~='cooldown' then
            forceVersion=forceVersion+1; break
        end
    end
    changes={}
    return itemsOnly
end
function provider.Cancel()
    generation=generation+1; presentSeq=presentSeq+1; uiCache.prewarmSeq=(uiCache.prewarmSeq or 0)+1; pending=false; uiCache.inFlightPresent=nil
    if reconcilePending then
        reconcilePending=false
        uiCache.reconcileSeq=(uiCache.reconcileSeq or 0)+1
        uiCache.applyPendingChanges()
    end
    if cancelBuild then cancelBuild(); cancelBuild=nil end
end
function provider.Invalidate(reason, itemIDs)
    if not reason then
        provider.Cancel(); signature=nil; uiCache.builtPriceRev=nil; buildState=nil; rows=nil; metaPatch=nil; uiCache.metaTargets=nil; repairPatch=nil; changes={}; itemChanges={}
        uiCache.retainedResult=nil; uiCache.boundResult=nil; uiCache.boundFilterKey=nil
        uiCache.earlyPresentedFilterKey=nil; uiCache.earlyBoundResult=nil; uiCache.earlyCountShown=nil
        uiCache.filterLRU:clear()
        uiCache.metaEpoch=uiCache.metaEpoch+1; forceVersion=forceVersion+1; cellCacheEpoch=cellCacheEpoch+1
    else
        changes[reason]=true
        if reason=='ownership' then
            if type(itemIDs)=='table' and (itemIDs.ids~=nil or itemIDs.names~=nil) then
                local hasAny=(type(itemIDs.ids)=='table' and next(itemIDs.ids)~=nil)
                    or (type(itemIDs.names)=='table' and next(itemIDs.names)~=nil)
                if hasAny then
                    uiCache.metaTargets=uiCache.metaTargets or {ids={},names={},spells={}}
                    uiCache.metaTargets.hasOwnership=true
                    if type(itemIDs.ids)=='table' then
                        for k,v in pairs(itemIDs.ids) do
                            local id=type(v)=='number' and v or (type(k)=='number' and k)
                            if id and v~=false then uiCache.metaTargets.ids[id]=true end
                        end
                    end
                    if type(itemIDs.names)=='table' then
                        for k,v in pairs(itemIDs.names) do
                            local nm=type(v)=='string' and v or (type(k)=='string' and k)
                            if nm and v~=false then uiCache.metaTargets.names[nm]=true end
                        end
                    end
                end
            else
                metaDirty=true
            end
        elseif reason=='cooldown' then
            if type(itemIDs)=='table' and next(itemIDs)~=nil then
                uiCache.metaTargets=uiCache.metaTargets or {ids={},names={},spells={}}
                uiCache.metaTargets.hasCooldown=true
                for k,v in pairs(itemIDs) do
                    local sid=type(v)=='number' and v or (type(k)=='number' and k)
                    if sid and v~=false then uiCache.metaTargets.spells[sid]=true end
                end
            elseif itemIDs==nil then
                metaDirty=true
            end
        elseif reason=='trainer' or reason=='skills' or reason=='known' or reason=='rep' then
            metaDirty=true
        end
        if reason=='items' then
            for key,value in pairs(itemIDs or {}) do
                local id=type(value)=='number' and value or key
                if number(id) then itemChanges[id]=true end
            end
        end
    end
    if reconcilePending then return end
    reconcilePending=true
    uiCache.reconcileSeq=(uiCache.reconcileSeq or 0)+1
    local myRecSeq=uiCache.reconcileSeq
    laterGuarded(function()
        if myRecSeq~=uiCache.reconcileSeq then return end
        reconcilePending=false
        local itemsOnly=uiCache.applyPendingChanges()
        if latest and active() then
            if not itemsOnly and latest.hostManaged and host.refresh then host.refresh() else provider.Refresh(latest) end
        end
    end)
end
local PROF_PILLS={
    {key='all',label='All'},
    {key='alchemy',label='Alch'},
    {key='blacksmithing',label='BS'},
    {key='enchanting',label='Ench'},
    {key='engineering',label='Eng'},
    {key='leatherworking',label='LW'},
    {key='tailoring',label='Tailor'},
    {key='cooking',label='Cook'},
    {key='firstaid',label='FA'},
    {key='poisons',label='Pois'},
    {key='others',label='Others'},
}
local function updateProfPills(activeProf)
    if not view or not view.profPills then return end
    local pal=getThemePalette()
    local isLight=(pal and pal.mode=='light')
    local cur=activeProf or 'all'
    for _,pill in ipairs(view.profPills) do
        local on=(pill.key==cur)
        pill._active=on
        if type(pill.bg)=='table' and pill.bg.SetColor then
            if on and pal and pal.accentBlue then
                pill.bg:SetColor(pal.accentBlue[1],pal.accentBlue[2],pal.accentBlue[3],isLight and 0.14 or 0.18)
            elseif on then
                pill.bg:SetColor(0.00,0.569,1.0,0.18)
            elseif pal and pal.pillTrack then
                pill.bg:SetColor(pal.pillTrack[1],pal.pillTrack[2],pal.pillTrack[3],isLight and 0.06 or 0.08)
            else
                pill.bg:SetColor(0.47,0.47,0.50,0.12)
            end
        end
        if type(pill.fs)=='table' and pill.fs.SetTextColor then
            local tc=on and ((pal and (pal.textBlue or pal.accentBlue)) or {0.0,0.569,1.0}) or ((pal and pal.textSecondary) or {0.75,0.75,0.78})
            pill.fs:SetTextColor(tc[1],tc[2],tc[3],1)
        end
    end
end
function provider.RepaintShoppingQty()
    if tbl and tbl.scrollBox and tbl.scrollBox.ForEachFrame then
        tbl.scrollBox:ForEachFrame(paintSelection)
    end
end
function provider.RepaintVisible()
    if not view or not tbl or not tbl.scrollBox or not tbl.scrollBox.ForEachFrame then return end
    local pal=getThemePalette()
    tbl.scrollBox:ForEachFrame(function(r)
        if r.data and r.cells then
            if r._colEpoch~=colEpoch then syncRowCells(r) end
            if tbl.layoutRow and r._layoutEpoch~=tbl._layoutEpoch then tbl.layoutRow(r) end
            paintRowCells(r,cellValues(r.data),pal)
            paintSelection(r)
        elseif r.shiftStepper and r.shiftStepper.Hide then
            r.shiftStepper:Hide()
        end
    end)
end
function provider.SetShiftMode(on)
    shiftActive=(on==true)
    updateShiftHeader()
    provider.RepaintVisible()
    return shiftActive
end
local lastShiftDown=false
local function syncShiftFromModifier()
    local state=shiftKeyDown()
    if state==nil then return end
    local down=state and true or false
    if down~=lastShiftDown then
        lastShiftDown=down
        provider.SetShiftMode(down)
    end
end
function provider.Create(parent,context)
    if view then return view end
    host=context
    local T=ns.Theme
    view=CreateFrame('Frame',nil,parent); view:SetPoint('TOPLEFT',0,0); view:SetPoint('BOTTOMRIGHT',0,0); view:Hide()
    view:RegisterEvent('MODIFIER_STATE_CHANGED')
    view:SetScript('OnEvent',function(self,event)
        if event=='MODIFIER_STATE_CHANGED' and shown(self) then
            syncShiftFromModifier()
        end
    end)
    local function onShiftUpdate(self)
        if not shown(self) then return end
        syncShiftFromModifier()
    end
    view:HookScript('OnShow',function(self)
        self:SetScript('OnUpdate',onShiftUpdate)
        rebindStaleRows()
        local state=shiftKeyDown()
        if state==nil then return end
        local down=state and true or false
        lastShiftDown=down
        if down~=shiftActive then provider.SetShiftMode(down) end
    end)
    view:HookScript('OnHide',function(self)
        self:SetScript('OnUpdate',nil)
        closeHeatPopover()
        local quickLook=provider.GetQuickLookFrame and provider.GetQuickLookFrame()
        if quickLook and quickLook.data and quickLook.data.kind=='recipe' then provider.CloseQuickLook() end
        lastShiftDown=false
        if shiftActive then provider.SetShiftMode(false) end
        if self.colSettingsPopover and self.colSettingsPopover.Hide then self.colSettingsPopover:Hide() end
        provider.CancelPresentation()
    end)
    view.CloseHeatPopover=closeHeatPopover
    if type(T)=='table' and type(T.NineApple)=='function' then
        view._mmCard=T.NineApple(view,'glass_r10','cardBg',false,{noSpecular=true})
    end
    local bar=CreateFrame('Frame',nil,view); bar:SetPoint('TOPLEFT',0,0); bar:SetPoint('TOPRIGHT',0,0); bar:SetHeight(40)
    view.headerBar=bar
    local barSep=bar:CreateTexture(nil,'BORDER')
    barSep:SetPoint('BOTTOMLEFT',0,0); barSep:SetPoint('BOTTOMRIGHT',0,0); barSep:SetHeight(1)
    view.barSep=barSep

    local hdrTitle=bar:CreateFontString(nil,'OVERLAY','GameFontNormal')
    hdrTitle:SetPoint('LEFT',16,0)
    applyFont(hdrTitle,15,'semibold')
    hdrTitle:SetText('All Recipes')
    hdrTitle:SetWordWrap(false)
    view.hdrTitle=hdrTitle

    view.profPills={}
    local prevPill=nil
    for _,pd in ipairs(PROF_PILLS) do
        local pw=math.max(28,#pd.label*7+14)
        local pb=CreateFrame('Button',nil,bar)
        pb:SetSize(pw,22)
        if not prevPill then
            pb:SetPoint('LEFT',hdrTitle,'RIGHT',12,0)
        else
            pb:SetPoint('LEFT',prevPill,'RIGHT',4,0)
        end
        pb.key=pd.key
        if type(T)=='table' and type(T.RoundRect)=='function' and type(T.ASSETS)=='table' and T.ASSETS.pill_fill then
            pb.bg=T.RoundRect(pb,pb,'BACKGROUND',0,11,0,0.47,0.47,0.50,0.12,T.ASSETS.pill_fill)
        else
            local track=(getThemePalette() or {}).pillTrack or {0.47,0.47,0.50,0.12}
            local tbg=pb:CreateTexture(nil,'BACKGROUND'); tbg:SetAllPoints(); tbg:SetColorTexture(track[1],track[2],track[3],track[4] or 0.12)
        end
        pb.fs=pb:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        pb.fs:SetAllPoints(); pb.fs:SetJustifyH('CENTER'); pb.fs:SetWordWrap(false)
        applyFont(pb.fs,11,'regular')
        pb.fs:SetText(pd.label)
        pb:SetScript('OnClick',function()
            local db=(latest and latest.db) or _G.MerchantMasterDB
            if db then
                if db.profFilter==pd.key and pd.key~='all' then db.profFilter='all' else db.profFilter=pd.key end
            end
            if latest then latest.profFilter=(db and db.profFilter) or pd.key end
            updateProfPills(db and db.profFilter or pd.key)
            if host and host.refresh then host.refresh() elseif latest then provider.Refresh(latest) end
        end)
        view.profPills[#view.profPills+1]=pb
        prevPill=pb
    end

    local function resetFilters()
        if latest and latest.db then
            latest.db.superListSkillMin,latest.db.superListSkillMax=nil,nil
            syncSkills(latest.db)
        end
        if view.skillMin and view.skillMin.ClearFocus then view.skillMin:ClearFocus() end
        if view.skillMax and view.skillMax.ClearFocus then view.skillMax:ClearFocus() end
        if host and host.resetSuperListFilters then
            host.resetSuperListFilters()
            return
        end
        if not latest then return end
        local db=latest.db or {}
        db.profFilter='all'; db.unlockFilter='all'; db.prevUnlockFilter='all'; db.knownRecipesOnly=false
        db.bisOnly=false; db.sellableFilter='all'; db.merchantVendorOnly=false; db.sourceFilter='all'
        db.craftableFilter='all'; db.demandFilter='all'
        db.subCraftMode='smart'; latest.subCraftMode='smart'
        if host.sidebar and host.sidebar.subCraftBtn then
            host.sidebar.subCraftBtn:SetText(ns.SUBCRAFT_MODES[1].label)
        end
        db.superListSkillMin=nil; db.superListSkillMax=nil; db.superListSources={}
        if type(db.recipeSources)=='table' then wipe(db.recipeSources) end
        latest.profFilter='all'; latest.unlockFilter='all'; latest.knownRecipesOnly=false; latest.search=''
        syncSkills(db)
        updateProfPills('all')
        if view.sourceButton then view.sourceButton:SetText(sourceLabel(db)) end
        if host and host.refresh then host.refresh() end
    end
    view.colSettingsBtn=T.CreatePlateButton(bar,'',28,26,{variant='secondary',pill=true,icon=(T and T.ASSETS and T.ASSETS.icon_gear) or 'gear',iconSize=13})
    view.colSettingsBtn:SetPoint('RIGHT',bar,'RIGHT',-12,0)
    view.colSettingsBtn:SetScript('OnClick',function() provider.ToggleColumnSettings() end)
    view.colSettingsBtn:SetScript('OnEnter',function(self)
        GameTooltip:SetOwner(self,'ANCHOR_BOTTOMLEFT')
        GameTooltip:AddLine('Customize Columns',1,0.82,0)
        GameTooltip:AddLine('Show, hide, and reorder All Recipes columns.',1,1,1,true)
        GameTooltip:Show()
    end)
    view.colSettingsBtn:SetScript('OnLeave',function() GameTooltip:Hide() end)
    view.shopButton=T.CreatePlateButton(bar,'Shopping List',116,26,{variant='secondary',pill=true})
    view.shopButton:SetPoint('RIGHT',view.colSettingsBtn,'LEFT',-6,0); view.shopButton:SetScript('OnClick',function() host.toggleShoppingWindow(true) end)
    view.resetButton=T.CreatePlateButton(bar,'Reset Filters',92,26,{variant='secondary',pill=true})
    view.resetButton:SetPoint('RIGHT',view.shopButton,'LEFT',-6,0)
    view.resetButton:SetScript('OnClick',resetFilters)
    view.filtersButton=T.CreatePlateButton(bar,'Filters',78,26,{variant='secondary',pill=true,icon=T.ASSETS and T.ASSETS.icon_bars,iconSize=11})
    view.filtersButton:SetPoint('RIGHT',view.resetButton,'LEFT',-6,0)
    view.filtersButton:SetScript('OnClick',function(self)
        if host and host.toggleScreenFilters then host.toggleScreenFilters(self) end
    end)
    local badgePill=(type(T)=='table' and type(T.CreateBadgePill)=='function')
        and T.CreateBadgePill(bar,'Quick-Add Mode','blue',{height=22,fontSize=11,padX=14})
        or nil
    local shiftBadge=badgePill and badgePill.frame or CreateFrame('Frame',nil,bar)
    shiftBadge._pill=badgePill
    if not badgePill then
        shiftBadge:SetSize(102,22)
        shiftBadge.label=shiftBadge:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        shiftBadge.label:SetAllPoints()
        shiftBadge.label:SetText('Quick-Add Mode')
    end
    shiftBadge:SetPoint('RIGHT',view.filtersButton,'LEFT',-8,0)
    shiftBadge:Hide()
    view.shiftBadge=shiftBadge
    view.summaryLeftAnchor=prevPill
    view.summary=bar:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    applyFont(view.summary,11,'regular')
    view.summary:SetJustifyH('RIGHT'); view.summary:SetWordWrap(false)
    updateShiftHeader()
    local columns={}
    for i,col in ipairs(MASTER_COLUMNS) do columns[i]=copyColumn(col) end
    tbl=host.createSortableTable(view,-41,'recipes',columns,bindRow,nil,
        {preserveCellColors=true,preparedCells=true}); view.table=tbl
    tbl.headerBtnsByKey={}
    for i,col in ipairs(tbl.columns) do
        tbl.headerBtnsByKey[col.key]=tbl.headerBtns[i]
    end
    tbl.growWeights={}
    for i,col in ipairs(tbl.columns) do
        tbl.growWeights[i]=col.grow
    end
    if tbl.headerBar and tbl.headerBar.SetHeight then tbl.headerBar:SetHeight(28) end
    local function clearInsetChrome()
        if type(tbl.inset)~='table' then return end
        if type(tbl.inset._mmCard)=='table' then
            for _,k in ipairs({'fill','border','stroke'}) do
                local obj=tbl.inset._mmCard[k]
                if type(obj)=='table' then
                    if type(obj.SetColor)=='function' then obj:SetColor(0,0,0,0) end
                    if type(obj.SetAlpha)=='function' then obj:SetAlpha(0) end
                    if type(obj.SetShown)=='function' then obj:SetShown(false) end
                end
            end
        end
        if type(tbl.inset.GetRegions)=='function' then
            for _,r in ipairs({tbl.inset:GetRegions()}) do
                if type(r)=='table' and r.GetObjectType and r:GetObjectType()=='Texture' and type(r.SetAlpha)=='function' then
                    r:SetAlpha(0)
                end
            end
        end
        for _,k in ipairs({'NineSlice','Bg','TopLeftCorner','TopRightCorner','BotLeftCorner','BotRightCorner','TopBorder','BottomBorder','LeftBorder','RightBorder'}) do
            if type(tbl.inset[k])=='table' and type(tbl.inset[k].SetAlpha)=='function' then tbl.inset[k]:SetAlpha(0) end
        end
    end
    clearInsetChrome()
    if type(tbl.inset)=='table' then
        tbl.inset:ClearAllPoints()
        tbl.inset:SetPoint('TOPLEFT',0,-68)
        tbl.inset:SetPoint('BOTTOMRIGHT',0,0)
    end
    local chevPath=(T and T.ASSETS and T.ASSETS.icon_chevron_down) or (uiCache.appleRoot .. 'icon_chevron_down')
    local function styleHeaders()
        local pal=getThemePalette()
        local st=host.getSort and host.getSort() or nil
        local tStyle=(T and T.IsCustomSkin and T.IsCustomSkin() and T.GetTableStyle and T.GetTableStyle()) or 'standard'
        local styled=(tStyle=='t5_ruled' or tStyle=='t5_well' or tStyle=='t3_strips')
        local activeHex=colorHex(pal and (pal.textBlue or pal.accentBlue),'0091ff')
        local mutedCol=styled and (pal and (pal.gold or pal.text)) or (pal and pal.textMuted) or {0.60,0.60,0.65}
        local activeCol=(pal and (pal.textBlue or pal.accentBlue)) or {0.00,0.569,1.0}
        if type(tbl.headerBar)=='table' and type(tbl.headerBar.GetRegions)=='function' then
            for _,r in ipairs({tbl.headerBar:GetRegions()}) do
                if type(r)=='table' and r.GetObjectType and r:GetObjectType()=='Texture' and r.SetColorTexture then
                    if styled then
                        r:SetColorTexture(0,0,0,0)
                    elseif pal and pal.separator then
                        r:SetColorTexture(pal.separator[1],pal.separator[2],pal.separator[3],(pal.separator[4] or 0.45)*0.65)
                    end
                end
            end
        end
        for i,col in ipairs(tbl.columns) do
            local btn=tbl.headerBtns and tbl.headerBtns[i]
            if type(btn)=='table' then
                if btn.SetHeight then btn:SetHeight(26) end
                if type(btn.sep)=='table' and type(btn.sep.Hide)=='function' then
                    btn.sep:Hide()
                end
                if type(btn.bg)=='table' and btn.bg.SetColorTexture then
                    btn.bg:SetColorTexture(0,0,0,0)
                end
                applyFont(btn.fs,styled and 10 or 11,styled and 'semibold' or 'regular')
                local lbl=col.label or ''
                local dispLbl=styled and string.upper(lbl) or lbl
                if st and col.key==st.col then
                    local arrow=st.asc
                        and (' |T'..chevPath..':9:9:0:0:16:16:0:16:16:0|t')
                        or (' |T'..chevPath..':9:9:0:0:16:16:0:16:0:16|t')
                    btn.fs:SetText('|cff'..activeHex..dispLbl..'|r'..arrow)
                    if btn.fs.SetTextColor then btn.fs:SetTextColor(activeCol[1],activeCol[2],activeCol[3],1) end
                else
                    btn.fs:SetText(dispLbl)
                    if btn.fs.SetTextColor then btn.fs:SetTextColor(mutedCol[1],mutedCol[2],mutedCol[3],1) end
                end
            end
        end
        if tbl.paintTableChrome then tbl.paintTableChrome() end
    end
    tbl.updateHeaders=styleHeaders
    tbl.proportional=true; tbl.measuredDataset=setmetatable({}, {__mode='k'}); tbl.measuredStrings={}; tbl.measuredHeaders={}
    view.measure=view:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    applyFont(view.measure,12,'regular')
    view.measure:SetWordWrap(false); view.measure:Hide()
    view.cellFont=view:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    applyFont(view.cellFont,12,'regular')
    view.cellFont:Hide()
    local formatMoney=ns.Theme.FormatMoneyText or ns.FormatMoneyCompact
    local sample=formatMoney(99999999,false,false,'full_fixed')
    local floorMin={buyCostCopper=90,craftCost=90,unitAH=90,turnoverPerDay=90,profit=90,sourceCost=90}
    for _,col in ipairs(MASTER_COLUMNS) do
        col.minWidth=math.max(col.minWidth or col.width,floorMin[col.key] or 0)
        measureCell(col.key,col.label,true)
        if col.key=='buyCostCopper' then measureCell(col.key,sample..'*')
        elseif col.key=='profit' then
            measureCell(col.key,formatMoney(99999999,true,false,'full_fixed'))
            measureCell(col.key,formatMoney(-99999999,true,false,'full_fixed'))
        elseif col.key=='craftCost' or col.key=='unitAH' or col.key=='turnoverPerDay' or col.key=='sourceCost' then measureCell(col.key,sample) end
    end
    for _,col in ipairs(tbl.columns) do
        local m=MASTER_BY_KEY[col.key]
        if m then col.minWidth=m.minWidth end
    end

    local pop=CreateFrame('Frame',nil,view)
    pop:SetSize(264,38+20+#MASTER_COLUMNS*24)
    pop:SetPoint('TOPRIGHT',view.colSettingsBtn,'BOTTOMRIGHT',0,-6)
    if pop.SetFrameStrata then pop:SetFrameStrata('DIALOG') end
    if view.GetFrameLevel and pop.SetFrameLevel then pop:SetFrameLevel((view:GetFrameLevel() or 1)+40) end
    if pop.EnableMouse then pop:EnableMouse(true) end
    pop:Hide()
    pop.rows={}
    pop._built=false
    local function ensureColumnPopoverBuilt()
        if not pop or pop._built then return end
        pop._built=true
        if type(T)=='table' and type(T.NineApple)=='function' then
            pop.surface=T.NineApple(pop,'glass_r12','cardBg','borderStrong',{layer='BACKGROUND',sub=-1,noSpecular=true})
        end
        pop.title=pop:CreateFontString(nil,'OVERLAY','GameFontNormal')
        pop.title:SetPoint('TOPLEFT',pop,'TOPLEFT',14,-12)
        applyFont(pop.title,13,'semibold')
        pop.title:SetText('Customize Columns')
        pop.title:SetWordWrap(false)
        pop.closeBtn=T.CreatePlateButton(pop,'',22,22,{variant='ghost',pill=true,icon=(T and T.ASSETS and T.ASSETS.icon_close) or 'close',iconSize=11})
        pop.closeBtn:SetPoint('TOPRIGHT',pop,'TOPRIGHT',-10,-8)
        pop.closeBtn:SetScript('OnClick',function() provider.ToggleColumnSettings(false) end)
        pop.resetBtn=T.CreatePlateButton(pop,'Reset',50,22,{variant='secondary',pill=true,fontSize=11})
        pop.resetBtn:SetPoint('RIGHT',pop.closeBtn,'LEFT',-6,0)
        pop.resetBtn:SetScript('OnClick',function() provider.ResetColumns() end)
        pop.sep=pop:CreateTexture(nil,'BORDER')
        pop.sep:SetPoint('TOPLEFT',pop,'TOPLEFT',10,-38)
        pop.sep:SetPoint('TOPRIGHT',pop,'TOPRIGHT',-10,-38)
        pop.sep:SetHeight(1)
        local checkIconPath=(T and T.ASSETS and T.ASSETS.icon_check) or (uiCache.appleRoot .. 'icon_check')
        local pillTexPath=T and T.ASSETS and T.ASSETS.pill_fill
        for idx=1,#MASTER_COLUMNS do
            local row=CreateFrame('Frame',nil,pop)
            row:SetHeight(24)
            row:SetPoint('TOPLEFT',pop,'TOPLEFT',10,-48-(idx-1)*24)
            row:SetPoint('TOPRIGHT',pop,'TOPRIGHT',-10,-48-(idx-1)*24)

            local chk=CreateFrame('Button',nil,row)
            chk:SetSize(16,16)
            chk:SetPoint('LEFT',row,'LEFT',4,0)
            if type(T)=='table' and type(T.RoundRect)=='function' and pillTexPath then
                chk.bg=T.RoundRect(chk,chk,'BACKGROUND',0,5,0,0.47,0.47,0.50,0.16,pillTexPath)
            else
                chk.bg=chk:CreateTexture(nil,'BACKGROUND')
                chk.bg:SetAllPoints()
                chk.bg:SetColorTexture(0.47,0.47,0.50,0.16)
            end
            chk.tick=chk:CreateTexture(nil,'OVERLAY',nil,1)
            chk.tick:SetSize(10,10)
            chk.tick:SetPoint('CENTER',0,0)
            chk.tick:SetTexture(checkIconPath)
            chk:SetScript('OnClick',function()
                local k=row._colKey
                if not k or k=='name' then return end
                local cfg=normalizeColumnConfig(getColumnDB())
                provider.SetColumnVisible(k,cfg.hidden[k]==true)
            end)

            local downBtn=CreateFrame('Button',nil,row)
            downBtn:SetSize(20,20)
            downBtn:SetPoint('RIGHT',row,'RIGHT',-2,0)
            downBtn.icon=downBtn:CreateTexture(nil,'ARTWORK')
            downBtn.icon:SetSize(10,10)
            downBtn.icon:SetPoint('CENTER',0,0)
            downBtn.icon:SetTexture(chevPath)
            if downBtn.icon.SetTexCoord then downBtn.icon:SetTexCoord(0,1,0,1) end
            downBtn:SetScript('OnClick',function()
                if row._colKey then provider.MoveColumn(row._colKey,1) end
            end)

            local upBtn=CreateFrame('Button',nil,row)
            upBtn:SetSize(20,20)
            upBtn:SetPoint('RIGHT',downBtn,'LEFT',-2,0)
            upBtn.icon=upBtn:CreateTexture(nil,'ARTWORK')
            upBtn.icon:SetSize(10,10)
            upBtn.icon:SetPoint('CENTER',0,0)
            upBtn.icon:SetTexture(chevPath)
            if upBtn.icon.SetTexCoord then upBtn.icon:SetTexCoord(0,1,1,0) end
            upBtn:SetScript('OnClick',function()
                if row._colKey then provider.MoveColumn(row._colKey,-1) end
            end)

            local lbl=row:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            lbl:SetPoint('LEFT',chk,'RIGHT',8,0)
            lbl:SetPoint('RIGHT',upBtn,'LEFT',-6,0)
            lbl:SetJustifyH('LEFT')
            lbl:SetWordWrap(false)
            applyFont(lbl,12,'regular')

            row.checkBtn=chk
            row.upBtn=upBtn
            row.downBtn=downBtn
            row.label=lbl
            pop.rows[idx]=row
        end
    end
    view._ensureColumnPopoverBuilt=ensureColumnPopoverBuilt
    view.colSettingsPopover=pop
    view.skillControl=CreateFrame('Frame',nil,context.sidebarParent)
    view.skillControl:SetSize(194,34); view.skillControl:Hide()
    view.skillControl._sidebarHeight=35
    local label=view.skillControl:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    applyFont(label,11,'regular')
    label:SetPoint('TOPLEFT',2,-1); label:SetText('Skill')
    local dash=view.skillControl:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    applyFont(dash,11,'regular')
    dash:SetPoint('TOPLEFT',105,-1); dash:SetText('-')
    view.skillError=view.skillControl:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    applyFont(view.skillError,11,'regular')
    view.skillError:SetPoint('BOTTOMLEFT',2,0); view.skillError:SetTextColor(1,0.4,0.3)
    for _,spec in ipairs({{name='skillMin',key='superListSkillMin',x=43},{name='skillMax',key='superListSkillMax',x=119}}) do
        local edit=CreateFrame('EditBox',nil,view.skillControl,'InputBoxTemplate')
        edit:SetSize(52,20); edit:SetPoint('TOPLEFT',spec.x,-1)
        edit:SetAutoFocus(false); edit:SetNumeric(true)
        if T and T.StyleEditBox then T.StyleEditBox(edit) end
        view[spec.name]=edit
        local function commit(self)
            if not latest then return end
            local input=self:GetText() or ''
            local value=ns.SuperListModel.SkillBound(input)
            local empty=input:match('^%s*$')~=nil
            if not empty and value==nil then syncSkills(latest.db); return end
            local changed=latest.db[spec.key]~=value
            latest.db[spec.key]=value; syncSkills(latest.db)
            if changed then host.refresh() end
        end
        edit:SetScript('OnEnterPressed',function(self) commit(self); self:ClearFocus() end)
        edit:SetScript('OnEditFocusLost',commit)
        edit:SetScript('OnEscapePressed',function(self) if latest then syncSkills(latest.db) end; self:ClearFocus() end)
    end
    local function clearSkills()
        if not latest then return end
        latest.db.superListSkillMin,latest.db.superListSkillMax=nil,nil
        syncSkills(latest.db); host.refresh()
    end
    view.skillClear=CreateFrame('Button',nil,view.skillControl,'UIPanelButtonTemplate')
    view.skillClear:SetSize(16,18); view.skillClear:SetPoint('TOPLEFT',178,-1); view.skillClear:SetText('x')
    if T and T.SkinButton then
        local closeIc=(T.ASSETS and T.ASSETS.icon_close) or (uiCache.appleRoot .. 'icon_close')
        T.SkinButton(view.skillClear,{icon=closeIc,iconSize=9})
    end
    view.skillClear:SetScript('OnClick',clearSkills)
    view.skillControl:EnableMouse(true)
    view.skillControl:SetScript('OnMouseUp',function(_,button) if button=='RightButton' then clearSkills() end end)
    view.sourceButton=CreateFrame('Button',nil,context.sidebarParent,'UIPanelButtonTemplate')
    view.sourceButton:SetSize(194,21); view.sourceButton:RegisterForClicks('LeftButtonUp','RightButtonUp'); ns.Theme.SkinButton(view.sourceButton,{dropdown=true}); view.sourceButton:Hide()
    view.sourceButton:SetScript('OnClick',function(self,button)
        if not latest then return end
        local db=latest.db
        if button=='RightButton' then db.merchantVendorOnly=false; db.superListSources={}; self:SetText(sourceLabel(db)); host.refresh(); return end
        ns.Theme.OpenDropDown(self,sources,nil,function(key)
            if key=='all' then db.merchantVendorOnly=false; db.superListSources={} else db.superListSources[key]=not db.superListSources[key] or nil end
            self:SetText(sourceLabel(db)); host.refresh()
        end,214,{multiSelect=true,isSelected=function(key)
            if key=='all' then return next(db.superListSources)==nil end
            return db.superListSources[key]==true
        end})
    end)
    view.sourceButton:SetScript('OnEnter',function(self)
        GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:AddLine('Recipe Sources (Multi-Select)',1,0.82,0)
        GameTooltip:AddLine('Merchant Favor, Vendor, Writ, Trainer, AH / World, Quest / BoP. Selected sources combine with OR; other filters combine with AND.',1,1,1,true)
        GameTooltip:AddLine('Right-click: All Sources',0.7,0.9,1); GameTooltip:Show()
    end)
    view.sourceButton:SetScript('OnLeave',function() GameTooltip:Hide() end)
    view.resetFiltersButton=CreateFrame('Button',nil,context.sidebarParent,'UIPanelButtonTemplate')
    view.resetFiltersButton:SetSize(194,21); view.resetFiltersButton:SetText('Reset All Filters')
    ns.Theme.SkinButton(view.resetFiltersButton,{primary=false})
    view.resetFiltersButton._isCheck=false; view.resetFiltersButton:Hide()
    view.resetFiltersButton:SetScript('OnClick',resetFilters)
    view.resetFiltersButton:SetScript('OnEnter',function(self)
        GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:AddLine('Reset All Recipe Filters',1,0.82,0)
        GameTooltip:AddLine('Resets Search, Profession, Known/Potential, Best only, Sellable, Sources, Skill range, Able/Craft, and Demand filters.',1,1,1,true)
        GameTooltip:Show()
    end)
    view.resetFiltersButton:SetScript('OnLeave',function() GameTooltip:Hide() end)

    local function refreshColumnPopover()
        local pop=view and view.colSettingsPopover
        if not pop or not pop._built then return end
        local pal=getThemePalette()
        local cfg=normalizeColumnConfig(getColumnDB())
        local textCol=(pal and pal.text) or {1,1,1,1}
        local mutedCol=(pal and pal.textMuted) or {0.6,0.6,0.6,1}
        local secCol=(pal and pal.textSecondary) or {0.82,0.82,0.85,1}
        local blueCol=(pal and pal.accentBlue) or {0,0.569,1,1}
        local trackCol=(pal and pal.pillTrack) or {0.47,0.47,0.50,0.16}
        local total=#cfg.order
        for i,key in ipairs(cfg.order) do
            local row=pop.rows[i]
            local def=MASTER_BY_KEY[key]
            if row and def then
                row._colKey=key
                local isName=(key=='name')
                local vis=isName or (cfg.hidden[key]~=true)
                row.label:SetText(isName and (def.label..' (Always Shown)') or def.label)
                local lc=vis and textCol or mutedCol
                if row.label.SetTextColor then row.label:SetTextColor(lc[1],lc[2],lc[3],lc[4] or 1) end
                local bgCol=vis and blueCol or trackCol
                local bgAlpha=isName and 0.55 or (bgCol[4] or 1)
                if type(row.checkBtn.bg)=='table' then
                    if row.checkBtn.bg.SetColor then row.checkBtn.bg:SetColor(bgCol[1],bgCol[2],bgCol[3],bgAlpha)
                    elseif row.checkBtn.bg.SetColorTexture then row.checkBtn.bg:SetColorTexture(bgCol[1],bgCol[2],bgCol[3],bgAlpha) end
                end
                if type(row.checkBtn.tick)=='table' then
                    if row.checkBtn.tick.SetShown then row.checkBtn.tick:SetShown(vis) end
                    if row.checkBtn.tick.SetVertexColor then row.checkBtn.tick:SetVertexColor(1,1,1,isName and 0.85 or 1) end
                end
                local canUp=(not isName and i>2)
                local canDown=(not isName and i<total)
                if row.upBtn.SetEnabled then row.upBtn:SetEnabled(canUp) end
                if row.downBtn.SetEnabled then row.downBtn:SetEnabled(canDown) end
                if type(row.upBtn.icon)=='table' and row.upBtn.icon.SetVertexColor then
                    local uc=canUp and secCol or mutedCol
                    row.upBtn.icon:SetVertexColor(uc[1],uc[2],uc[3],canUp and (uc[4] or 1) or 0.35)
                end
                if type(row.downBtn.icon)=='table' and row.downBtn.icon.SetVertexColor then
                    local dc=canDown and secCol or mutedCol
                    row.downBtn.icon:SetVertexColor(dc[1],dc[2],dc[3],canDown and (dc[4] or 1) or 0.35)
                end
            end
        end
    end
    local function themeColumnSettingsPopover()
        local pop=view and view.colSettingsPopover
        if not pop or not pop._built then return end
        local pal=getThemePalette()
        if type(pop.surface)=='table' and pop.surface.UpdateTheme then
            pop.surface:UpdateTheme(pal and pal.cardBg or 'cardBg',pal and (pal.borderStrong or pal.border) or 'borderStrong')
        end
        if type(pop.title)=='table' and pop.title.SetTextColor and pal and pal.text then
            pop.title:SetTextColor(pal.text[1],pal.text[2],pal.text[3],1)
        end
        if type(pop.sep)=='table' and pop.sep.SetColorTexture and pal and pal.separator then
            pop.sep:SetColorTexture(pal.separator[1],pal.separator[2],pal.separator[3],(pal.separator[4] or 0.45)*0.7)
        end
        refreshColumnPopover()
    end
    local function applyColumnConfig(db)
        local active,cfg=getActiveColumnDefs(db or getColumnDB())
        appliedColSig=fingerprint(cfg)
        if not tbl then return end
        tbl.columns=tbl.columns or {}
        for k in pairs(tbl.columns) do tbl.columns[k]=nil end
        tbl.baseWidths=tbl.baseWidths or {}
        for k in pairs(tbl.baseWidths) do tbl.baseWidths[k]=nil end
        tbl.growWeights=tbl.growWeights or {}
        for k in pairs(tbl.growWeights) do tbl.growWeights[k]=nil end
        tbl.colX=tbl.colX or {}
        for k in pairs(tbl.colX) do tbl.colX[k]=nil end
        tbl.headerBtns=tbl.headerBtns or {}
        for k in pairs(tbl.headerBtns) do tbl.headerBtns[k]=nil end
        local activeBtns={}
        local x=4
        for i,col in ipairs(active) do
            tbl.columns[i]=col
            tbl.baseWidths[i]=col.width
            tbl.growWeights[i]=col.grow
            tbl.colX[i]=x
            x=x+col.width+5
            local btn=tbl.headerBtnsByKey and tbl.headerBtnsByKey[col.key]
            tbl.headerBtns[i]=btn
            if btn then
                activeBtns[btn]=true
                if btn.Show then btn:Show() end
            end
        end
        for _,btn in pairs(tbl.headerBtnsByKey or {}) do
            if not activeBtns[btn] and btn.Hide then btn:Hide() end
        end
        tbl._layoutDirty=true
        colEpoch=colEpoch+1
        for _,group in ipairs(prepared) do
            syncCellGroup(group)
        end
        if tbl.scrollBox and tbl.scrollBox.ForEachFrame then
            tbl.scrollBox:ForEachFrame(function(r)
                if r.cellGroup then
                    syncRowCells(r)
                end
            end)
        end
        local w=(host and host.parent and host.parent.GetWidth and host.parent:GetWidth()) or 0
        if w<=0 and view and view.GetWidth then w=view:GetWidth() or 0 end
        if w<=0 then w=1840 end
        provider.Layout(w)
        local pal=getThemePalette()
        if tbl.scrollBox and tbl.scrollBox.ForEachFrame then
            tbl.scrollBox:ForEachFrame(function(r)
                if r.cellGroup then
                    if tbl.layoutRow and r._layoutEpoch~=tbl._layoutEpoch then tbl.layoutRow(r) end
                    if r.data then
                        paintRowCells(r,cellValues(r.data),pal)
                    end
                    paintSelection(r)
                end
            end)
        end
        styleHeaders()
        refreshColumnPopover()
    end
    view._applyColumnConfig=applyColumnConfig
    view._refreshColumnPopover=refreshColumnPopover
    view._themeColumnSettingsPopover=themeColumnSettingsPopover
    view._applyColumnConfig(getColumnDB())

    local function applySuperListTheme()
        local pal=getThemePalette()
        clearInsetChrome()
        if type(view._mmCard)=='table' then
            if view._mmCard.UpdateTheme then
                view._mmCard:UpdateTheme()
            else
                local bg=(pal and pal.cardBg) or {0.173,0.173,0.180,1}
                if view._mmCard.SetFill then view._mmCard:SetFill(bg) end
            end
        end
        if view.barSep and view.barSep.SetColorTexture and pal and pal.separator then
            view.barSep:SetColorTexture(pal.separator[1],pal.separator[2],pal.separator[3],(pal.separator[4] or 0.45)*0.65)
        end
        if view.hdrTitle and view.hdrTitle.SetTextColor and pal and pal.text then
            view.hdrTitle:SetTextColor(pal.text[1],pal.text[2],pal.text[3],1)
        end
        if view.summary and view.summary.SetTextColor and pal and pal.textSecondary then
            view.summary:SetTextColor(pal.textSecondary[1],pal.textSecondary[2],pal.textSecondary[3],1)
        end
        if label and label.SetTextColor and pal and pal.textSecondary then
            label:SetTextColor(pal.textSecondary[1],pal.textSecondary[2],pal.textSecondary[3],1)
        end
        if dash and dash.SetTextColor and pal and pal.textMuted then
            dash:SetTextColor(pal.textMuted[1],pal.textMuted[2],pal.textMuted[3],1)
        end
        if type(view.skillError)=='table' and view.skillError.SetTextColor and pal and pal.accentRed then
            view.skillError:SetTextColor(pal.accentRed[1],pal.accentRed[2],pal.accentRed[3],1)
        end
        for _,eb in ipairs({view.skillMin,view.skillMax}) do
            if type(eb)=='table' and eb.SetTextColor and pal and pal.text then
                eb:SetTextColor(pal.text[1],pal.text[2],pal.text[3],1)
            end
        end
        updateProfPills((latest and latest.profFilter) or (_G.MerchantMasterDB and _G.MerchantMasterDB.profFilter) or 'all')
        styleHeaders()
        updateShiftHeader()
        themeColumnSettingsPopover()
        if tbl and tbl.scrollBox and tbl.scrollBox.ForEachFrame then
            tbl.scrollBox:ForEachFrame(function(r)
                if r.data then
                    if r._colEpoch~=colEpoch then syncRowCells(r) end
                    if tbl.layoutRow and r._layoutEpoch~=tbl._layoutEpoch then tbl.layoutRow(r) end
                    paintRowCells(r,cellValues(r.data),pal)
                end
                paintSelection(r)
            end)
        end
    end
    if T and T.OnModeChanged then
        T.OnModeChanged(applySuperListTheme)
    end
    applySuperListTheme()
    return view
end
local function effectiveLedgerVersion(store)
    return ns.RecipeStats and ns.RecipeStats.EffectiveLedgerVersion and ns.RecipeStats.EffectiveLedgerVersion(store)
        or (store and (store.accountingVersion or store.version))
end
local function computeDatasetSig(context)
    local db=context.db or {}
    local store=ns.Analytics and ns.Analytics.Store
    local statsContext=context.statsContext
    return fingerprint({economy=context.econInfo and context.econInfo.effectiveKey,
        price=(ns.GetEffectivePriceVersion and ns.GetEffectivePriceVersion()) or ns.priceCacheEpoch or 0,
        source=db.priceSource,cut=db.applyAHCut,mode=context.subCraftMode,overrides=context.subCraftOverrides,
        prices=db.outlierPrices,
        revision=not statsContext and context.revision or nil,forced=forceVersion,
        favor=statsContext and statsContext.favorCopper,char=context.charKey,allChars=context.craftableAllChars==true,
        catalog=tostring(ns.RecipeStats.GetCatalog()),
        ledger=effectiveLedgerVersion(store),ledgerDB=store and tostring(store.db),
        day=time and math.floor(time()/86400)})
end
local function snapshotValue(value)
    if type(value)~='table' then return value end
    local copy={}; for k,v in pairs(value) do copy[k]=snapshotValue(v) end; return copy
end
local function syncEvaluationState(context, sig)
    local db=context.db or {}
    local statsContext=context.statsContext
    local professor=(ns.GetProfessorDB and ns.GetProfessorDB()) or _G.MerchantProfessorDB
    if sig==signature and metaDirty then
        metaDirty=false; uiCache.metaTargets=nil
        evaluation.ownedCounts=context.counts
        evaluation.ownedCountsByID=statsContext and statsContext.ownedCountsByID
        evaluation.profMap=snapshotValue(context.profMap)
        evaluation.repState=snapshotValue(context.repState)
        evaluation.trainerCosts=statsContext and statsContext.trainerCosts or (professor and professor.trainerCosts)
        local currentRows=(buildState and buildState.rows) or rows
        if currentRows and #currentRows>0 and type(ns.RecipeStats.PatchMetaSlice)=='function' then
            metaPatch={target=currentRows,index=1,cap=#currentRows}
            uiCache.metaEpoch=uiCache.metaEpoch+1
            uiCache.retainedResult=nil; uiCache.boundResult=nil; uiCache.boundFilterKey=nil
            uiCache.earlyPresentedFilterKey=nil; uiCache.earlyBoundResult=nil; uiCache.earlyCountShown=nil
            uiCache.filterLRU:clear()
        elseif currentRows and #currentRows>0 and type(ns.RecipeStats.PatchMeta)=='function' then
            metaPatch=nil
            ns.RecipeStats.PatchMeta(currentRows,evaluation)
            uiCache.metaEpoch=uiCache.metaEpoch+1
            uiCache.retainedResult=nil; uiCache.boundResult=nil; uiCache.boundFilterKey=nil
            uiCache.earlyPresentedFilterKey=nil; uiCache.earlyBoundResult=nil; uiCache.earlyCountShown=nil
            uiCache.filterLRU:clear()
        else
            metaPatch=nil
        end
    elseif sig==signature and uiCache.metaTargets then
        local mt=uiCache.metaTargets
        uiCache.metaTargets=nil
        if evaluation then
            evaluation.ownedCounts=context.counts
            evaluation.ownedCountsByID=statsContext and statsContext.ownedCountsByID
            evaluation.profMap=snapshotValue(context.profMap)
            evaluation.repState=snapshotValue(context.repState)
            evaluation.trainerCosts=statsContext and statsContext.trainerCosts or (professor and professor.trainerCosts)
            evaluation.now=context.now or (statsContext and statsContext.now)
        end
        local currentRows=(buildState and buildState.rows) or rows
        if currentRows and #currentRows>0 and ns.RecipeStats and type(ns.RecipeStats.PatchMetaTargeted)=='function' then
            local patched=ns.RecipeStats.PatchMetaTargeted(currentRows,evaluation,mt)
            if patched>0 then
                cellCacheEpoch=cellCacheEpoch+1
                local col=resolveSort(db)
                local cf=db.craftableFilter or 'all'
                local ownSens=mt.hasOwnership and (cf~='all' or col=='ownedOutputQty' or col=='ownedScrollQty' or col=='canCraftSort' or col=='canCraft')
                local cdSens=mt.hasCooldown and (cf=='craftable_now' or col=='cdSort' or col=='cooldown')
                if ownSens or cdSens then
                    uiCache.metaEpoch=uiCache.metaEpoch+1
                    uiCache.retainedResult=nil; uiCache.boundResult=nil; uiCache.boundFilterKey=nil
                    uiCache.earlyPresentedFilterKey=nil; uiCache.earlyBoundResult=nil; uiCache.earlyCountShown=nil
                    uiCache.filterLRU:clear()
                else
                    uiCache.filterLRU:evictWhere(function(tag)
                        return tag and ((mt.hasOwnership and tag.ownSens) or (mt.hasCooldown and tag.cdSens))
                    end)
                    if active() and provider.RepaintVisible then
                        provider.RepaintVisible()
                    end
                end
            end
        end
    elseif sig~=signature then
        metaDirty=false; metaPatch=nil; uiCache.metaTargets=nil; repairPatch=nil; itemChanges={}
        provider.Cancel(); buildState=nil; signature=sig; uiCache.builtPriceRev=uiCache.curPriceRev()
        uiCache.retainedResult=nil; uiCache.boundResult=nil; uiCache.boundFilterKey=nil
        uiCache.earlyPresentedFilterKey=nil; uiCache.earlyBoundResult=nil; uiCache.earlyCountShown=nil
        uiCache.filterLRU:clear()
        uiCache.metaEpoch=uiCache.metaEpoch+1
        local inputs=statsContext or {ownedCounts=context.counts,profMap=context.profMap,repState=context.repState,economy=context.econInfo and context.econInfo.effectiveKey,
            charKey=context.charKey,applyAHCut=db.applyAHCut~=false,subCraftMode=context.subCraftMode,subCraftOverrides=context.subCraftOverrides,
            outlierPrices=db.outlierPrices,revision=context.revision}
        evaluation=snapshotValue(inputs)
        evaluation.revision=nil; evaluation.hostRevision=nil; evaluation.dataset=sig
        evaluation.defer=C_Timer and C_Timer.After and laterGuarded or nil
        -- A new dataset must not inherit a price bank from the preceding economy/version.
        evaluation.priceBank=nil
    end
end
local function buildPriority(context)
    local db=(context and context.db) or {}
    local rawProf=text((context and context.profFilter) or db.profFilter):lower():match('^%s*(.-)%s*$')
    local profFilter=(rawProf and rawProf~='') and rawProf or 'all'
    local unlockFilter=(context and context.unlockFilter) or db.unlockFilter or 'all'
    local knownRecipesOnly=(context and context.knownRecipesOnly==true) or (db.knownRecipesOnly==true) or (unlockFilter=='known')
    local profMap=context and context.profMap
    local profMapFallback=false
    if type(profMap)~='table' or next(profMap)==nil then
        local saved=ns.activeChar and ns.activeChar.profs
        if type(saved)=='table' and next(saved)~=nil then
            profMap=saved
            profMapFallback=true
        end
    end
    local skillMin=db.superListSkillMin
    local skillMax=db.superListSkillMax
    local sources=db.superListSources
    local key=fingerprint({profFilter=profFilter,profMap=profMap,profMapFallback=profMapFallback,
        unlockFilter=unlockFilter,knownRecipesOnly=knownRecipesOnly,allChars=(context and context.craftableAllChars==true),
        skillMin=skillMin,skillMax=skillMax,sources=sources})
    return {profFilter=profFilter,profMap=profMap,profMapFallback=profMapFallback,
        unlockFilter=unlockFilter,knownRecipesOnly=knownRecipesOnly,allChars=(context and context.craftableAllChars==true),
        skillMin=skillMin,skillMax=skillMax,sources=sources,key=key}
end
local function shallowCopyRows(list)
    local copy={}; for i=1,#list do copy[i]=list[i] end; return copy
end
local function makeForegroundHandlers(token)
    local function onProgress(_, done, total)
        if token~=generation or not active() then return end
        if uiCache.earlyPresentedFilterKey and uiCache.earlyCountShown~=nil then
            view.summary:SetText(string.format('%d / %d recipes (warming %d/%d)',uiCache.earlyCountShown,uiCache.earlyTier1Done or done,done,total))
        else
            view.summary:SetText(string.format(rows and 'Updating recipes: %d / %d' or 'Loading recipes: %d / %d',done,total))
        end
    end
    local function onTierReady(partialRows, done, total)
        if token~=generation or not active() or not latest then return end
        uiCache.earlyPresentedFilterKey=nil
        uiCache.earlyBoundResult=nil
        uiCache.earlyCountShown=nil
        uiCache.earlyTier1Done=done
        uiCache.earlyWarmTotal=total
        uiCache.earlyAuthoritative=buildState and buildState.tier1Authoritative==true
        present(shallowCopyRows(partialRows),total)
    end
    local function onComplete(result)
        if token~=generation then return end
        presentSeq=presentSeq+1; uiCache.inFlightPresent=nil
        cancelBuild=nil; rows=result
        uiCache.metaEpoch=uiCache.metaEpoch+1
        local earlyKey=uiCache.earlyPresentedFilterKey
        local earlyResult=uiCache.earlyBoundResult
        local earlyAuth=uiCache.earlyAuthoritative
        uiCache.retainedResult=nil; uiCache.boundResult=nil; uiCache.boundFilterKey=nil
        uiCache.filterLRU:clear()
        if not metaPatch and earlyKey and earlyAuth and earlyResult and not next(itemChanges) then
            uiCache.retainedResult=earlyResult
            uiCache.retainedDatasetSig=signature
            uiCache.retainedFilterKey=earlyKey
            uiCache.retainedMetaEpoch=uiCache.metaEpoch
            local eDb=(latest and latest.db) or _G.MerchantMasterDB or {}
            local eCol=resolveSort(eDb)
            uiCache.filterLRU:put(uiCache.makeLRUKey(signature,uiCache.metaEpoch,earlyKey),earlyResult,uiCache.metaSensitivityTags(eDb.craftableFilter,eCol))
            uiCache.boundResult=earlyResult
            uiCache.boundDatasetSig=signature
            uiCache.boundFilterKey=earlyKey
            uiCache.boundMetaEpoch=uiCache.metaEpoch
        end
        if not active() then
            if not metaPatch and not metaDirty and not uiCache.metaTargets and not next(itemChanges) and (uiCache.warmContext or latest) then
                uiCache.prewarmPresentation(uiCache.warmContext or latest)
            else
                uiCache.notifyWarmComplete()
            end
            return
        end
        if not latest then return end
        if next(itemChanges) or metaDirty or uiCache.metaTargets then
            uiCache.retainedResult=nil; uiCache.boundResult=nil; uiCache.boundFilterKey=nil
            uiCache.earlyPresentedFilterKey=nil; uiCache.earlyBoundResult=nil; uiCache.earlyCountShown=nil
            laterGuarded(function()
                if token==generation and active() then
                    provider.Refresh(latest)
                    if provider.RefreshQuickLook then provider.RefreshQuickLook() end
                end
            end)
            return
        end
        local col,asc=resolveSort(latest.db)
        local activeFilterKey=buildFilterKey(latest,col,asc)
        if not metaPatch and earlyKey and earlyKey==activeFilterKey and earlyAuth and earlyResult then
            uiCache.earlyPresentedFilterKey=nil; uiCache.earlyBoundResult=nil; uiCache.earlyCountShown=nil
            view.summary:SetText(string.format('%d / %d recipes',#earlyResult,#rows))
            if provider.RefreshQuickLook then provider.RefreshQuickLook() end
            return
        end
        uiCache.retainedResult=nil; uiCache.boundResult=nil; uiCache.boundFilterKey=nil
        uiCache.earlyPresentedFilterKey=nil; uiCache.earlyBoundResult=nil; uiCache.earlyCountShown=nil
        present()
        if provider.RefreshQuickLook then provider.RefreshQuickLook() end
    end
    return onProgress, onComplete, onTierReady
end
function provider.HasWarmData()
    return buildState~=nil and (buildState.running==true or buildState.completed==true)
end
function provider.IsWarming()
    return buildState~=nil and buildState.running==true
end
function provider.WarmInBackground(context)
    if not context then return false end
    uiCache.warmContext=context
    local db=context.db or {}
    migrateSources(db)
    local sig=computeDatasetSig(context)
    syncEvaluationState(context,sig)
    local priority=buildPriority(context,true)
    if buildState and buildState.completed then
        rows=rows or buildState.rows
        if not active() then
            local col,asc=resolveSort(db)
            local fKey=buildFilterKey(context,col,asc)
            local hasRetained=uiCache.retainedResult and uiCache.retainedDatasetSig==sig
                and uiCache.retainedFilterKey==fKey and uiCache.retainedMetaEpoch==uiCache.metaEpoch
            if not hasRetained then
                uiCache.prewarmPresentation(context)
            else
                uiCache.notifyWarmComplete()
            end
        end
        return true
    end
    if buildState and buildState.running then
        if buildState.priorityKey~=priority.key then
            evaluation.priority=priority
            if ns.SuperListModel.Reprioritize then
                ns.SuperListModel.Reprioritize(buildState,priority)
            end
        end
        return true
    end
    evaluation.background=true
    evaluation.priority=priority
    local token=generation
    local finished=false
    local cancel,state=ns.SuperListModel.Start(evaluation,nil,function(result)
        if token~=generation then return end
        presentSeq=presentSeq+1; uiCache.inFlightPresent=nil
        finished=true; cancelBuild=nil; rows=result
        uiCache.metaEpoch=uiCache.metaEpoch+1
        uiCache.retainedResult=nil; uiCache.boundResult=nil; uiCache.boundFilterKey=nil
        uiCache.filterLRU:clear()
        if active() and latest and not pending then
            provider.Refresh(latest)
        else
            uiCache.prewarmPresentation(uiCache.warmContext or context)
        end
    end,buildState,nil)
    buildState=state
    if not finished and token==generation then cancelBuild=cancel end
    return true
end
function provider.Refresh(context)
    latest=context
    local db=context.db
    migrateSources(db)
    if type(db)=='table' then
        local cfg=normalizeColumnConfig(db)
        local sigCol=fingerprint(cfg)
        if sigCol~=appliedColSig and view and view._applyColumnConfig then
            view._applyColumnConfig(db)
        end
    end
    syncSkills(db)
    updateProfPills(context.profFilter or (db and db.profFilter) or 'all')
    view.sourceButton:SetText(sourceLabel(db))
    local sidebar=host.sidebar
    sidebar.sellBtn:SetText(host.findLabel(host.sellableFilters,db.sellableFilter or 'all'))
    sidebar.recCraftFilterBtn:SetText(host.findLabel(ns.CRAFTABLE_FILTERS,db.craftableFilter or 'all'))
    sidebar.recDemandFilterBtn:SetText(host.findLabel(ns.DEMAND_FILTERS,db.demandFilter or 'all'))
    sidebar.bisOnlyCheck:SetChecked(db.bisOnly==true)
    if not active() then provider.CancelPresentation(); return provider.bestProfit end
    -- Accept dependency changes together after their notification burst has settled.
    if reconcilePending and next(changes) then return provider.bestProfit end
    -- Filter/sort state is excluded: warm presentation never revalues recipes.
    local sig=computeDatasetSig(context)
    syncEvaluationState(context,sig)
    if not repairPatch and next(itemChanges) and buildState and buildState.completed then
        local ids=itemChanges; itemChanges={}
        if rows and ns.RecipeStats.PrepareRepair then
            repairPatch=ns.RecipeStats.PrepareRepair(rows,evaluation,ids)
            uiCache.metaEpoch=uiCache.metaEpoch+1
            uiCache.retainedResult=nil; uiCache.boundResult=nil; uiCache.boundFilterKey=nil
            uiCache.earlyPresentedFilterKey=nil; uiCache.earlyBoundResult=nil; uiCache.earlyCountShown=nil
            uiCache.filterLRU:clear()
        elseif rows and ns.RecipeStats.RepairItems and ns.RecipeStats.RepairItems(rows,evaluation or {},ids) then
            forceVersion=forceVersion+1
            sig=computeDatasetSig(context)
            syncEvaluationState(context,sig)
        end
    end
    local col,asc=resolveSort(db)
    local fKey=buildFilterKey(context,col,asc)
    if not repairPatch and not metaPatch and buildState and buildState.completed and rows
        and not (uiCache.retainedResult and uiCache.retainedDatasetSig==sig
            and uiCache.retainedFilterKey==fKey and uiCache.retainedMetaEpoch==uiCache.metaEpoch) then
        local lruHit=uiCache.filterLRU:get(uiCache.makeLRUKey(sig,uiCache.metaEpoch,fKey))
        if lruHit then
            uiCache.retainedResult=lruHit
            uiCache.retainedDatasetSig=sig
            uiCache.retainedFilterKey=fKey
            uiCache.retainedMetaEpoch=uiCache.metaEpoch
        end
    end
    if not repairPatch and not metaPatch and buildState and buildState.completed and rows
        and uiCache.retainedResult and uiCache.retainedDatasetSig==sig
        and uiCache.retainedFilterKey==fKey and uiCache.retainedMetaEpoch==uiCache.metaEpoch then
        presentSeq=presentSeq+1; uiCache.prewarmSeq=(uiCache.prewarmSeq or 0)+1; uiCache.inFlightPresent=nil
        local currentWidth=host.parent and host.parent:GetWidth() or view:GetWidth()
        if uiCache.boundWidth~=currentWidth then
            uiCache.boundWidth=currentWidth
            provider.Layout(currentWidth)
            tbl.updateHeaders()
        end
        if uiCache.boundResult~=uiCache.retainedResult or uiCache.boundDatasetSig~=sig
            or uiCache.boundFilterKey~=fKey or uiCache.boundMetaEpoch~=uiCache.metaEpoch then
            uiCache.viewWasHidden=false
            tbl.setRows(uiCache.retainedResult)
            uiCache.boundResult=uiCache.retainedResult
            uiCache.boundDatasetSig=sig
            uiCache.boundFilterKey=fKey
            uiCache.boundMetaEpoch=uiCache.metaEpoch
        elseif uiCache.viewWasHidden then
            uiCache.viewWasHidden=false
            rebindStaleRows()
        end
        view.summary:SetText(string.format('%d / %d recipes',#uiCache.retainedResult,#rows))
        host.statusText:SetText(context.scanBanner or string.format('%d recipes - %s',#uiCache.retainedResult,context.econInfo and context.econInfo.label or 'selected economy'))
        local top=uiCache.retainedResult[1]; provider.bestProfit=top and top.profit
        return provider.bestProfit
    end
    if buildState and buildState.running then
        local wasBackground=buildState.background==true
        evaluation.background=false
        local priority=buildPriority(context,false)
        local prioChanged=buildState.priorityKey~=priority.key
        evaluation.priority=priority
        if wasBackground or not buildState.onProgress or not buildState.onTierReady then
            local onProgress,onComplete,onTierReady=makeForegroundHandlers(generation)
            if ns.SuperListModel.Attach then
                ns.SuperListModel.Attach(buildState,false,priority,onProgress,onComplete,onTierReady)
            else
                ns.SuperListModel.Reprioritize(buildState,priority)
            end
        elseif ns.SuperListModel.Attach then
            ns.SuperListModel.Attach(buildState,false,priority)
        else
            ns.SuperListModel.Reprioritize(buildState,priority)
        end
        local earlyStale=(uiCache.earlyPresentedFilterKey~=nil and uiCache.earlyPresentedFilterKey~=fKey)
        if earlyStale then
            uiCache.earlyPresentedFilterKey=nil
            uiCache.earlyBoundResult=nil
            uiCache.earlyCountShown=nil
        end
        local inflight=uiCache.inFlightPresent
        if uiCache.earlyPresentedFilterKey==fKey and uiCache.earlyBoundResult then
            presentSeq=presentSeq+1; uiCache.inFlightPresent=nil
            local currentWidth=host.parent and host.parent:GetWidth() or view:GetWidth()
            if uiCache.boundWidth~=currentWidth then
                uiCache.boundWidth=currentWidth
                provider.Layout(currentWidth)
                tbl.updateHeaders()
            end
            if uiCache.viewWasHidden then
                uiCache.viewWasHidden=false
                rebindStaleRows()
            end
            local doneNow=#(buildState.rows or {})
            local totalNow=#(buildState.order or {})
            view.summary:SetText(string.format('%d / %d recipes (warming %d/%d)',#uiCache.earlyBoundResult,uiCache.earlyTier1Done or doneNow,doneNow,totalNow))
        elseif buildState.tier1Authoritative and buildState.index>buildState.tier1Target then
            if not (inflight and inflight.warmTotal~=nil and inflight.sig==sig and inflight.metaEpoch==uiCache.metaEpoch
                and inflight.fKey==fKey and inflight.hasRepair==(repairPatch~=nil) and inflight.hasMeta==(metaPatch~=nil)) then
                buildState.tier1Notified=true
                if buildState.onTierReady then
                    buildState.onTierReady(buildState.rows,#buildState.rows,#(buildState.order or {}))
                end
            end
        elseif rows and #rows>0 and fKey~=uiCache.boundFilterKey then
            if not (inflight and inflight.dataRows==rows and inflight.sig==sig and inflight.metaEpoch==uiCache.metaEpoch
                and inflight.fKey==fKey and inflight.hasRepair==(repairPatch~=nil) and inflight.hasMeta==(metaPatch~=nil)) then
                view.summary:SetText('Filtering recipes...')
                present(rows)
            end
        elseif wasBackground or prioChanged or earlyStale or (buildState.tier1Notified and not uiCache.earlyBoundResult) then
            presentSeq=presentSeq+1; uiCache.inFlightPresent=nil
            uiCache.earlyPresentedFilterKey=nil; uiCache.earlyBoundResult=nil; uiCache.earlyCountShown=nil
            view.summary:SetText(string.format(rows and 'Updating recipes: %d / %d' or 'Loading recipes: %d / %d',#(buildState.rows or {}),#(buildState.order or {})))
        end
        return provider.bestProfit
    end
    local inflight=uiCache.inFlightPresent
    if buildState and buildState.completed and rows and inflight
        and inflight.sig==sig and inflight.metaEpoch==uiCache.metaEpoch
        and inflight.fKey==fKey and inflight.dataRows==rows
        and inflight.hasRepair==(repairPatch~=nil) and inflight.hasMeta==(metaPatch~=nil) then
        return provider.bestProfit
    end
    presentSeq=presentSeq+1; uiCache.inFlightPresent=nil
    if buildState and buildState.completed and rows and fKey~=uiCache.boundFilterKey then
        view.summary:SetText('Filtering recipes...')
    end
    if pending or cancelBuild then return provider.bestProfit end
    pending=true
    -- One kickoff per frame coalesces refresh bursts before constructing or sorting.
    local scheduledGeneration=generation
    local function kickoff()
        if scheduledGeneration~=generation then return end
        pending=false
        if not active() then return end
        if buildState and buildState.completed then rows=rows or buildState.rows; present(); return end
        local token=generation
        evaluation.background=false
        evaluation.priority=buildPriority(latest,false)
        if buildState and not buildState.completed then
            local kCol,kAsc=resolveSort(latest.db)
            local kFKey=buildFilterKey(latest,kCol,kAsc)
            if not (uiCache.earlyPresentedFilterKey==kFKey and uiCache.earlyBoundResult) then
                buildState.tier1Notified=false
            end
        end
        view.summary:SetText(rows and 'Updating recipes...' or 'Loading recipes...')
        local onProgress,rawOnComplete,onTierReady=makeForegroundHandlers(token)
        local finished=false
        local function onComplete(result) finished=true; rawOnComplete(result) end
        local cancel,state=ns.SuperListModel.Start(evaluation,onProgress,onComplete,buildState,onTierReady)
        buildState=state
        if not finished and token==generation then cancelBuild=cancel end
    end
    laterGuarded(kickoff)
    return provider.bestProfit
end
do
    local hud
    local WIDTH, INSET, CARD_WIDTH, ROW_WIDTH = 654, 15, 624, 598
    local DAY_COUNT, MAX_SLOTS, CHART_HEIGHT = 7, 24, 118
    local PLOT_X, PLOT_WIDTH, PLOT_TOP, PLOT_HEIGHT = 106, 494, 30, 54
    local WEEKDAYS = {'Sun','Mon','Tue','Wed','Thu','Fri','Sat'}
    local HOUR_TICKS = {{1,'-24h'},{7,'-18h'},{13,'-12h'},{19,'-6h'},{24,'Now'}}
    local EMPTY_SERIES = {values={},days=0}

    local function activeWindow()
        return MerchantMasterDB and MerchantMasterDB.quickLookWindow=='24h' and '24h' or '7d'
    end

    local function place(widget, parent, x, y, width, height)
        widget:ClearAllPoints()
        widget:SetPoint('TOPLEFT',parent,'TOPLEFT',x,-y)
        widget:SetSize(width,height)
        return widget
    end

    local function label(parent, x, y, width, height, size, ink, value, align, weight)
        local fs=place(parent:CreateFontString(nil,'OVERLAY'),parent,x,y,width,height)
        fs:SetJustifyH(align or 'LEFT')
        fs:SetJustifyV('MIDDLE')
        fs:SetWordWrap(false)
        applyFont(fs,size,weight or 'regular')
        fs:SetText(value or '')
        hud.labels[#hud.labels+1]={fs,ink}
        return fs
    end

    local function inset(parent, x, y, width, height, kind, fill)
        local frame=place(CreateFrame('Frame',nil,parent),parent,x,y,width,height)
        local surface=ns.Theme.NineApple(frame,kind or 'glass_r12',fill or 'cardBg','border',{noSpecular=true})
        hud.surfaces[#hud.surfaces+1]=surface
        return frame
    end

    local function icon(parent, x, y, size)
        local texture=place(parent:CreateTexture(nil,'ARTWORK'),parent,x,y,size,size)
        texture:SetTexCoord(0.07,0.93,0.07,0.93)
        return texture
    end

    local function quickLookInk(role)
        return hud.inks[role] or hud.palette[role]
    end

    local function quickLookText(value)
        local themed=ns.Theme.ThemeText(value)
        if hud.inlineInks and type(themed)=='string' and themed:find('|cff',1,true) then
            themed=themed:gsub('|cff(%x%x%x%x%x%x)',hud.inlineInks)
        end
        return themed
    end

    local function colorText(fs, value, ink)
        fs:SetText(quickLookText(value))
        fs:SetTextColor(unpack(quickLookInk(ink)))
    end

    local function coins(value, signed)
        if not number(value) then return '-' end
        local mode=(ns.Theme.GetPriceDisplayMode and ns.Theme.GetPriceDisplayMode()) or 'compact'
        if mode~='compact' or (hud and hud.data and hud.data.kind~='recipe') then
            return ns.Theme.FormatMoneyText(value,signed,false,mode)
        end
        if math.abs(value)>=10000 then
            value=math.floor(math.abs(value)/100+0.5)*(value<0 and -100 or 100)
        end
        local parts=ns.Theme.FormatMoneyParts(value,signed,true)
        if (parts.g>0 and parts.s==0) or (parts.g==0 and parts.s>0 and parts.c==0) then
            return parts.text:match('^(.*) ')
        end
        return parts.text
    end

    local function impactCoins(value, ink)
        return (coins(value,'neutral'):gsub('|cff'..hud.palette.hexText,'|cff'..colorHex(quickLookInk(ink))))
    end

    local function formatValue(value, kind, badgeText)
        if kind=='demand' and badgeText then return badgeText end
        if not number(value) then return '-' end
        if kind=='rate' then return string.format('%.1f/d',value) end
        if kind=='int' then return tostring(math.floor(value+0.5)) end
        if kind=='demand' then return string.format('%.2fx',value) end
        if kind=='cost_money' then return coins(value,'cost') end
        return coins(value,kind=='signed_money')
    end

    local function metricValueText(spec, value, kind)
        return (spec.valueText or formatValue(value,kind,spec.badgeText))..(spec.valueSuffix or '')
    end

    local function formatImpact(delta, kind, ink)
        if not number(delta) then return '-' end
        if kind=='rate' then return string.format('%+.1f/d',delta) end
        if kind=='int' then
            local count=delta<0 and math.ceil(delta-0.5) or math.floor(delta+0.5)
            return string.format('%+d',count)
        end
        if kind=='demand' then return string.format('%+.2fx',delta) end
        return impactCoins(delta,ink)
    end

    local function formatAxisValue(value, kind)
        if not number(value) then return '-' end
        if kind=='money' or kind=='signed_money' or kind=='cost_money' then
            return ns.Theme.FormatMoneyText(value,false,false)
        end
        return formatValue(value,kind)
    end

    local function percent(pct, pureVendor)
        if pureVendor then return '0.0%' end
        return pct and string.format('%+.1f%%',pct) or '-'
    end

    local function changeInk(value, lowerIsBetter)
        if not value or value==0 then return 'textMuted' end
        if (value<0)==lowerIsBetter then return 'accentGreen' end
        return 'accentRed'
    end

    local function makeTrace(parent, thickness, withGlow)
        local trace={lines={},glowLines={},dots={},thickness=thickness,withGlow=withGlow==true}
        local lineTex=ns.Theme and ns.Theme.ASSETS and ns.Theme.ASSETS.line_soft
        for slot=1,MAX_SLOTS do
            if parent.CreateLine then
                if withGlow then
                    local glow=parent:CreateLine(nil,'ARTWORK',nil,0)
                    glow:SetThickness(thickness*2.2)
                    if lineTex and glow.SetTexture then glow:SetTexture(lineTex) end
                    glow:Hide()
                    trace.glowLines[slot]=glow
                end
                local line=parent:CreateLine(nil,'ARTWORK',nil,1)
                line:SetThickness(thickness)
                if lineTex and line.SetTexture then line:SetTexture(lineTex) end
                line:Hide()
                trace.lines[slot]=line
            end
            local dot=parent:CreateTexture(nil,'OVERLAY')
            dot:SetTexture(ns.Theme.ASSETS.circle_fill)
            local dotSz=withGlow and math.max(3, math.floor(thickness + 0.5)) or 2
            dot:SetSize(dotSz, dotSz)
            dot:Hide()
            trace.dots[slot]=dot
        end
        return trace
    end

    local function extent(values, slotCount)
        local low,high
        for slot=1,slotCount do
            local value=number(values[slot])
            if value then
                low=math.min(low or value,value)
                high=math.max(high or value,value)
            end
        end
        return low,high
    end

    local function paintTrace(parent, trace, values, slotCount, x, y, width, height, low, high, color)
        local lineTex=ns.Theme and ns.Theme.ASSETS and ns.Theme.ASSETS.line_soft
        local isLight=(ns.Theme and ns.Theme.GetMode and ns.Theme.GetMode()=='light')
        local glowAlpha=isLight and 0.10 or 0.16
        local r,g,b,a=color[1],color[2],color[3],color[4] or 1
        trace._coords=trace._coords or {}
        for slot=1,MAX_SLOTS do
            trace.dots[slot]:Hide()
            trace._coords[slot]=nil
            local line=trace.lines[slot]
            if line then line:Hide() end
            local glow=trace.glowLines and trace.glowLines[slot]
            if glow then glow:Hide() end
        end
        local step=slotCount>1 and width/(slotCount-1) or 0
        local lastX,lastY
        for slot=1,slotCount do
            local value=number(values[slot])
            if value then
                local dot,line=trace.dots[slot],trace.lines[slot]
                local glow=trace.glowLines and trace.glowLines[slot]
                local px=x+(slot-1)*step
                local py=y+(high==low and height/2 or height*(value-low)/(high-low))
                trace._coords[slot]={px,py}
                dot:ClearAllPoints()
                dot:SetPoint('CENTER',parent,'BOTTOMLEFT',px,py)
                dot:SetVertexColor(r,g,b,a)
                dot:Show()
                if lastX~=nil and lastY~=nil and line then
                    if glow then
                        glow:SetStartPoint('BOTTOMLEFT',lastX,lastY)
                        glow:SetEndPoint('BOTTOMLEFT',px,py)
                        if lineTex and glow.SetTexture and glow.SetVertexColor then
                            glow:SetTexture(lineTex)
                            glow:SetVertexColor(r,g,b,glowAlpha)
                        else
                            glow:SetColorTexture(r,g,b,glowAlpha)
                        end
                        glow:Show()
                    end
                    line:SetStartPoint('BOTTOMLEFT',lastX,lastY)
                    line:SetEndPoint('BOTTOMLEFT',px,py)
                    line:SetColorTexture(r,g,b,a)
                    if lineTex and line.SetTexture and line.SetVertexColor then
                        line:SetTexture(lineTex)
                        line:SetVertexColor(r,g,b,a)
                    end
                    line:Show()
                end
                lastX,lastY=px,py
            end
        end
    end

    local function paintSpark(widgets, series, ink)
        local spark=widgets.spark
        local values=series.values or EMPTY_SERIES.values
        local low,high=extent(values,hud.slotCount)
        paintTrace(spark,widgets.trace,values,hud.slotCount,3,4,spark:GetWidth()-6,spark:GetHeight()-8,
            low,high,quickLookInk(ink))
    end

    local function since(stamp, now)
        if not stamp then return 'time unavailable' end
        local minutes=math.floor(math.max(0,now-stamp)/60)
        if minutes<1 then return 'just now' end
        if minutes<60 then return minutes..'m ago' end
        local hours=math.floor(minutes/60)
        return hours<24 and hours..'h ago' or math.floor(hours/24)..'d ago'
    end

    local function paintBanner()
        local scan,now=hud.data.scan,time and time() or hud.data.now
        local message='Auction House closed  |  No recent local scan for this item'
        if scan then
            local quote=''
            if (scan.qty or 0)>0 then
                quote=(scan.price or 0)>0 and ('  |  Lowest '..coins(scan.price)) or '  |  No buyout'
            end
            message='Offline AH sample  |  '..(scan.qty or '-')..' listed'..quote..'  |  Last scan '..since(scan.at,now)
        end
        hud.bannerText:SetText(message)
        hud.bannerDot:SetVertexColor(unpack(hud.palette[scan and 'accentGreen' or 'textMuted']))
    end

    local function overviewMetric(key, name, value, kind, series, lowerIsBetter, badgeText)
        return {key=key,name=name,value=value,valueKind=kind,series=series,lowerIsBetter=lowerIsBetter,badgeText=badgeText}
    end

    local function legacyOverview(data, row)
        if hud.kind=='recipe' then
            local demand=row.demand or {}
            return {
                overviewMetric('profit','Profit',row.profit,'signed_money',data.net),
                overviewMetric('sell','Sell price',row.unitAH,'money',data.output),
                overviewMetric('cost','Craft cost',row.craftCost,'money',data.cost,true),
                overviewMetric('sales','Sales per day',row.salesPerDay,'rate',data.sales),
                overviewMetric('listed','AH listed',row.listed or (data.scan and data.scan.qty),'int',nil,true),
                overviewMetric('demand','Demand',demand.salesRatio,'demand',nil,false,demand.heatBadge),
            }
        end
        local meta,writ=data.meta or {},hud.kind=='writ'
        return {
            overviewMetric('net','Net cost',meta.totalPrice,'money',data.net,true),
            overviewMetric('item',writ and 'Writ price' or 'Crate price',data.scrollCost,'money',data.scroll,true),
            overviewMetric('materials',writ and 'Turn-in cost' or 'Bundle cost',nil,'money',data.cost,true),
            overviewMetric('refund',writ and 'Coin pouch' or 'Crate reward',meta.pouchRefund or meta.reward,'money'),
            overviewMetric('unitCost',writ and 'Cost per rep' or 'Cost per favor',meta.pricePerRep or meta.pricePerToken,'money',nil,true),
            overviewMetric('reward',writ and 'Reputation' or 'Favor',meta.rep or meta.tokens,'int'),
        }
    end

    local function recipeScrollMetric(data, row, info)
        local ability=row.craftAbility or {}
        local scrollID=info.itemID or data.scrollID
        local tag=text(info.tag or info.sourceTag):upper()
        if tag~='VENDOR' and tag~='FAVOR' and tag~='TRAINER' then
            tag=nil
            if ability.vendorFavorCost or row.sourceLabel=='Merchant' then tag='FAVOR'
            elseif data.scrollFixed or ability.howCategory=='vendor' or row.sourceLabel=='Vendor' then tag='VENDOR'
            elseif ability.howCategory=='trainer' or row.sourceLabel=='Trainer' then tag='TRAINER' end
        end
        local pureVendor=info.pureVendor
        if pureVendor==nil then pureVendor=tag=='VENDOR' and data.scrollFixed end
        return {key=info.key or 'recipeScroll',name='Recipe scroll',itemID=scrollID,icon=scrollID and ns.ItemIcon(scrollID) or ns.Theme.ASSETS.icon_book,
            qty=info.qty or (scrollID and 1),value=info.value or info.price or data.scrollCost,valueKind='money',
            valueText=info.priceText or (tag=='FAVOR' and ability.vendorCostText or nil),series=info.series or data.scroll,
            lowerIsBetter=true,pureVendor=pureVendor,tag=tag}
    end

    local function recipeScrollListedMetric(data, row, info)
        local ability=row.craftAbility or {}
        local scrollID=info.itemID or data.scrollID
        local nonTradeTag
        if not data.canTradeScroll then
            if ability.vendorFavorCost or row.sourceLabel=='Merchant' then nonTradeTag='FAVOR'
            elseif not scrollID and (ability.howCategory=='trainer' or row.sourceLabel=='Trainer') then nonTradeTag='TRAINER'
            else nonTradeTag='BOP' end
        end
        return {key='recipeScrollListed',name='Scroll AH listed',icon=scrollID and ns.ItemIcon(scrollID) or ns.Theme.ASSETS.icon_book,
            qtyText='AH',value=data.scrollLiveListed,valueKind='int',series=data.scrollListed,
            lowerIsBetter=false,pureVendor=not data.canTradeScroll,tag=nonTradeTag}
    end

    local function buildMetricRows(data, row)
        local overview=data.overviewRows or legacyOverview(data,row)
        local movers,occurrences={},{}
        for i,mover in ipairs(data.movers or {}) do
            local id=mover.key or table.concat({mover.itemID or mover.name,mover.tag or '',mover.indent or 0,mover.qty or ''},':')
            local count=(occurrences[id] or 0)+1
            occurrences[id]=count
            local prefix=mover.tag and ('['..mover.tag..'] ') or ''
            local indent=mover.indent and string.rep('  ',mover.indent) or ''
            local craftable=mover.craftable and mover.tag~='Reagent' and mover.tag~='Bundle' and ' (Craft)' or ''
            local itemID=mover.itemID or (mover.item and mover.item.itemID)
            movers[i]={
                key=count==1 and id or (id..':'..count),name=indent..prefix..mover.name..craftable,
                itemID=itemID,
                icon=ns.ItemIcon(itemID),qty=mover.qty,
                value=mover.unitPrice or (mover.series and mover.series.last),valueKind='money',
                series=mover.observedSeries or mover.series,impact=mover.impact,pct=mover.deltaPct,
                lowerIsBetter=true,pureVendor=mover.pureVendor,tag=(mover.fixed or mover.pureVendor) and 'VENDOR' or nil,
            }
        end
        local scroll={}
        if hud.kind=='recipe' then
            local info=data.scrollInfo or {}
            scroll={recipeScrollMetric(data,row,info),recipeScrollListedMetric(data,row,info)}
        end
        return {overview=overview,mover=movers,scroll=scroll}
    end

    local function metricKey(spec)
        return spec.key or spec.name or spec.label
    end

    local function metricValues(spec)
        local series=(not hud.weekOnly and spec.series) or EMPTY_SERIES
        local value=number(spec.value) or number(spec.liveValue) or series.last or (series.values and series.values[hud.slotCount])
        local delta=(not hud.weekOnly and spec.impact) or series.change
        local pct=(not hud.weekOnly and spec.pct) or series.pct
        return series,value,delta,pct,spec.valueKind or 'money'
    end

    local function paintRowState(widgets)
        local selected=hud.expandedKey~=nil and hud.expandedKey==widgets.metricKey
            and hud.expandedSection==widgets.section
        widgets.active:SetShown(selected)
        widgets.hover:SetShown(not selected)
    end

    local function paintMetric(widgets, spec)
        if widgets.spec~=spec then leaveTooltip(widgets) end
        widgets.spec=spec
        widgets.metricKey=spec and metricKey(spec)
        widgets:SetShown(spec~=nil)
        paintRowState(widgets)
        if not spec then return end
        local series,value,delta,pct,kind=metricValues(spec)
        local lowerIsBetter=spec.lowerIsBetter==true
        local ink=changeInk(delta,lowerIsBetter)
        local days=series.days or 0
        local coverageInk=days==hud.slotCount and 'accentGreen' or (days>0 and 'accentOrange' or 'textMuted')
        local fixedTag=spec.tag or (spec.fixed and 'FIXED' or nil)
        local isFixed=spec.pureVendor==true or spec.fixed==true
        widgets.icon:SetTexture(spec.icon)
        widgets.name:SetText(spec.name or spec.label or '')
        widgets.qty:SetText(spec.qtyText or (spec.qty and (spec.qty..'x')) or '-')
        if widgets.priceSuffix~=spec.valueSuffix then
            widgets.priceSuffix=spec.valueSuffix
            applyFont(widgets.price,spec.valueSuffix and 10 or 11,'semibold')
        end
        colorText(widgets.price,metricValueText(spec,value,kind),'text')
        widgets.spark:SetShown(not fixedTag)
        widgets.fixed:SetShown(fixedTag~=nil)
        widgets.fixed:SetText(fixedTag or '')
        paintSpark(widgets,series,ink)
        colorText(widgets.impact,formatImpact(delta,kind,ink),ink)
        colorText(widgets.pct,percent(pct,isFixed),changeInk(pct,lowerIsBetter))
        local covText=spec.pureVendor and 'N/A' or (spec.fixed and 'Fixed' or (days..'/'..hud.window))
        local covInk=isFixed and 'textMuted' or coverageInk
        colorText(widgets.coverage,covText,covInk)
    end

    local function layoutPanel(panel, y, height, section)
        place(panel,hud,INSET,y,CARD_WIDTH,height)
        y=y+height+6
        if section==hud.expandedSection and shown(hud.expandChart) then
            place(hud.expandChart,hud,INSET,y,CARD_WIDTH,CHART_HEIGHT)
            y=y+CHART_HEIGHT+6
        end
        return y
    end

    local function layoutSections()
        local y=layoutPanel(hud.overviewPanel,66,22+#hud.metrics.overview*24+6,'overview')
        y=layoutPanel(hud.moverPanel,y,22+#hud.movers*26+6,'mover')
        local scrollHeight=hud.kind=='recipe' and 96 or (hud.kind=='forged' and 56 or 36)
        y=layoutPanel(hud.scrollPanel,y,scrollHeight,'scroll')
        if shown(hud.banner) then
            place(hud.banner,hud,INSET,y,CARD_WIDTH,34)
            y=y+34+6
        end
        place(hud.footer,hud,INSET,y,CARD_WIDTH,30)
        hud:SetHeight(y+30+12)
    end

    local function paintMovers()
        local movers=hud.metrics.mover
        local total=#movers
        local maxOffset=math.max(0,total-#hud.movers)
        hud.moverOffset=math.max(0,math.min(hud.moverOffset,maxOffset))
        for i,widgets in ipairs(hud.movers) do paintMetric(widgets,movers[i+hud.moverOffset]) end
        hud.moverEmpty:SetShown(total==0)
        local track=hud.moverScrollTrack
        track:SetShown(maxOffset>0)
        if maxOffset>0 then
            local thumbHeight=math.max(20,math.floor(102*#hud.movers/total+0.5))
            hud.moverThumbY=(102-thumbHeight)*hud.moverOffset/maxOffset
            place(hud.moverScrollThumb,track,0,hud.moverThumbY,4,thumbHeight)
        end
    end

    local function scrollMovers(_,delta)
        if not hud.data or not delta or delta==0 then return end
        hud.SetMoverScroll(hud.moverOffset+(delta<0 and 1 or -1))
    end

    local function enableMoverWheel(frame)
        if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
        frame:SetScript('OnMouseWheel',scrollMovers)
    end

    local function pointStamp(slot)
        local data=hud.data
        local now=data.now or (time and time()) or 0
        if hud.window=='24h' then
            local startHour=data.startHour or (data.window=='24h' and data.startSlot) or (math.floor(now/3600)-MAX_SLOTS+1)
            return (startHour+slot-1)*3600
        end
        return ((data.startDay or math.floor(now/86400)-DAY_COUNT+1)+slot-1)*86400
    end

    local function showChartPoint(slot)
        hud.hoverSlot=slot
        local chart=hud.expandChart
        local spec=chart.metric
        hud.readout:SetShown(slot~=nil and spec~=nil)
        if not slot or not spec then
            if chart.hoverLine then chart.hoverLine:Hide() end
            if chart.hoverDot then chart.hoverDot:Hide() end
            return
        end
        local series,_,_,_,kind=metricValues(spec)
        local stamp=pointStamp(slot)
        local timestamp=(date or os.date)(hud.window=='24h' and '!%a %d %b %H:%M UTC' or '!%a %d %b',stamp)
        local value=series.values and series.values[slot]
        hud.dayReadout:SetText(quickLookText(timestamp..'  |  '..formatAxisValue(value,kind)))
        local coord=chart.trace and chart.trace._coords and chart.trace._coords[slot]
        local accent=hud.palette and hud.palette.accentOrange or {1,0.57,0.19,1}
        if chart.hoverLine then
            local step=hud.slotCount>1 and PLOT_WIDTH/(hud.slotCount-1) or 0
            local hx=coord and coord[1] or (PLOT_X+(slot-1)*step)
            chart.hoverLine:ClearAllPoints()
            chart.hoverLine:SetPoint('BOTTOMLEFT',chart,'BOTTOMLEFT',hx,CHART_HEIGHT-PLOT_TOP-PLOT_HEIGHT)
            chart.hoverLine:SetSize(1,PLOT_HEIGHT)
            chart.hoverLine:SetColorTexture(accent[1],accent[2],accent[3],0.75)
            chart.hoverLine:Show()
        end
        if chart.hoverDot then
            if coord then
                chart.hoverDot:ClearAllPoints()
                chart.hoverDot:SetPoint('CENTER',chart,'BOTTOMLEFT',coord[1],coord[2])
                chart.hoverDot:SetVertexColor(accent[1],accent[2],accent[3],1)
                chart.hoverDot:Show()
            else
                chart.hoverDot:Hide()
            end
        end
    end

    local function paintExpandChart()
        local chart=hud.expandChart
        local spec
        if hud.expandedKey~=nil and hud.expandedSection then
            for _,candidate in ipairs(hud.metrics[hud.expandedSection]) do
                if metricKey(candidate)==hud.expandedKey then spec=candidate; break end
            end
        end
        chart.metric=spec
        chart:SetShown(spec~=nil)
        if not spec then
            hud.expandedKey,hud.expandedSection=nil,nil
            showChartPoint(nil)
            return
        end

        local series,value,delta,pct,kind=metricValues(spec)
        local lowerIsBetter=spec.lowerIsBetter==true
        local ink=changeInk(delta,lowerIsBetter)
        chart.title:SetText((spec.name or spec.label)..' — '..hud.window)
        colorText(chart.value,metricValueText(spec,value,kind),'text')
        colorText(chart.impact,formatImpact(delta,kind,ink),ink)
        colorText(chart.pct,percent(pct,spec.pureVendor),changeInk(pct,lowerIsBetter))

        local values,slots=series.values or EMPTY_SERIES.values,hud.slotCount
        local low,high=extent(values,slots)
        for i,axis in ipairs(chart.axis) do
            axis:SetText(quickLookText(low and formatAxisValue(low+(high-low)*(3-i)/2,kind) or '-'))
        end
        chart.empty:SetShown(low==nil)
        paintTrace(chart,chart.trace,values,slots,PLOT_X,CHART_HEIGHT-PLOT_TOP-PLOT_HEIGHT,PLOT_WIDTH,
            PLOT_HEIGHT,low,high,quickLookInk(delta and delta~=0 and ink or 'textBlue'))

        local step=PLOT_WIDTH/(slots-1)
        for i,fs in ipairs(chart.ticks) do
            local tick=HOUR_TICKS[i]
            fs:SetShown(hud.window=='7d' or tick~=nil)
            if hud.window=='7d' then
                fs:SetText(WEEKDAYS[(math.floor(pointStamp(i)/86400)+4)%DAY_COUNT+1])
                place(fs,chart,PLOT_X+(i-1)*step-19,87,38,13)
            elseif tick then
                fs:SetText(tick[2])
                place(fs,chart,PLOT_X+(tick[1]-1)*step-19,87,38,13)
            end
        end
        for slot,hit in ipairs(chart.hits) do
            hit:SetShown(slot<=slots)
            if slot<=slots then
                local x=PLOT_X+(slot-1)*step
                local left=math.max(PLOT_X,x-step/2)
                local right=math.min(PLOT_X+PLOT_WIDTH,x+step/2)
                place(hit,chart,left,PLOT_TOP-3,right-left,PLOT_HEIGHT+6)
            end
        end
        if hud.hoverSlot then showChartPoint(hud.hoverSlot<=slots and hud.hoverSlot or nil) end
    end

    local function wowheadTarget(info, row, detail)
        if info.wowheadCA and text(info.wowheadCA.wowheadURL)~='' then return info.wowheadCA end
        local ability=row.craftAbility or {}
        local url=info.wowheadURL or row.wowheadURL or ability.wowheadURL
        local name,kind=ability.wowheadLabel,ability.wowheadKind
        if not url and ns.GetRecipeWowheadURL then
            local target=hud.kind=='recipe' and row.recipe or {itemID=row.writID or row.crateID or row.itemID,name=hud.data.title}
            url,name,kind=ns.GetRecipeWowheadURL(target)
        end
        if text(url)=='' then return end
        local ca={}
        for k,v in pairs(ability) do ca[k]=v end
        ca.wowheadURL,ca.wowheadLabel,ca.wowheadKind=url,name,kind
        ca.howDetail=ca.howDetail or detail
        return ca
    end

    local function paintScroll()
        local data,row=hud.data,hud.row
        local info=data.scrollInfo or data.sourceInfo or {}
        local recipe=hud.kind=='recipe'
        for _,fs in ipairs(hud.scrollHeaders) do fs:SetShown(recipe) end
        for i,widgets in ipairs(hud.scrollMetricRows) do paintMetric(widgets,hud.metrics.scroll[i]) end

        local detail=text(info.whereToBuy)
        if detail=='' then
            if recipe then
                local ability=row.craftAbility or {}
                detail=ability.howDetail or ability.howShort or row.sourceLabel or 'Source unavailable'
            else
                local meta=data.meta or {}
                local parts={}
                for _,field in ipairs({'npc','zone','cdText','mode'}) do
                    local value=meta[field] or row[field]
                    if text(value)~='' then
                        local prefix=field=='mode' and 'Mode ' or (field=='cdText' and 'CD ' or '')
                        parts[#parts+1]=prefix..value
                    end
                end
                detail=#parts>0 and table.concat(parts,'  |  ') or 'Source unavailable'
            end
        end
        hud.wowheadCA=wowheadTarget(info,row,detail)
        hud.wowheadButton:SetShown(hud.wowheadCA~=nil)
        place(hud.wowheadButton,hud.scrollPanel,512,recipe and 71 or 7,100,22)
        local width=hud.wowheadCA and 496 or 604
        local forged=hud.kind=='forged'
        hud.whereToBuy:SetWordWrap(forged)
        hud.whereToBuy:SetJustifyV(forged and 'TOP' or 'MIDDLE')
        local sourceSize=forged and 9 or 10
        applyFont(hud.whereToBuy,sourceSize)
        applyFont(hud.breakEven,sourceSize)
        if forged then
            local breakdown=ns.RecipeStats.FormatForgedBreakdown(data.forgedSummary,coins,true) or data.breakdown
            place(hud.whereToBuy,hud.scrollPanel,10,6,width,28)
            colorText(hud.whereToBuy,'Turn-in mechanics: '..detail,'textSecondary')
            place(hud.breakEven,hud.scrollPanel,10,38,604,13)
            colorText(hud.breakEven,breakdown or '','textSecondary')
            hud.breakEven:SetShown(breakdown~=nil)
            return
        end
        local crafts=recipe and number(info.breakEvenCrafts or data.breakEvenCrafts) or nil
        hud.breakEven:SetShown(crafts~=nil)
        if crafts then hud.breakEven:SetText('Break-even: '..crafts..(crafts==1 and ' craft' or ' crafts')) end
        place(hud.whereToBuy,hud.scrollPanel,10,recipe and 72 or 1,width,crafts and 11 or (recipe and 20 or 34))
        if crafts then place(hud.breakEven,hud.scrollPanel,10,84,width,11) end
        local sourcePrefix=recipe and 'Where to buy: ' or (hud.kind=='item' and 'Source: ' or 'Turn-in source: ')
        colorText(hud.whereToBuy,sourcePrefix..detail,'textSecondary')
    end

    local function paintWindowButtons()
        local hourly=(hud.window or activeWindow())=='24h'
        hud.win24Btn:SetActive(hourly)
        hud.win7dBtn:SetActive(not hourly)
        hud.win24Btn.selection:SetShown(hourly)
        hud.win7dBtn.selection:SetShown(not hourly)
    end

    local function paintHeaders(headers)
        local timeLabel=hud.window:upper()
        headers[4]:SetText(timeLabel..' TREND')
        headers[5]:SetText(timeLabel..' IMPACT')
        headers[7]:SetText(hud.window=='24h' and 'HRS' or 'DAYS')
    end

    local function quickLookWatchTarget()
        local row=hud and hud.row
        if not row then return nil end
        local kind=hud.kind or (hud.data and hud.data.kind) or 'recipe'
        local recipe=row.recipe
        local spellID=row.spellID or (recipe and (recipe.spellID or recipe.recipeID or recipe.id))
        local itemID=row.outputItemID or row.writID or row.crateID or row.itemID or (recipe and recipe.outputItemID)
        return {
            kind=kind,
            row=row,
            key=row.key,
            itemID=itemID,
            spellID=spellID,
            name=(hud.data and hud.data.title) or row.name,
        }
    end

    local function syncFavButton()
        if not (hud and hud.favButton) then return false end
        local W=ns.Watchlist
        local target=quickLookWatchTarget()
        local fav=false
        if W and target then
            if type(W.IsFavorite)=='function' then fav=W.IsFavorite(target)==true
            elseif type(W.IsWatched)=='function' then fav=W.IsWatched(target)==true end
        end
        hud.favButton._isFavorite=fav
        local pal=hud.palette or getThemePalette()
        local ic=hud.favButton._mmIcon
        if ic and ic.SetVertexColor then
            if fav then
                ic:SetVertexColor(1,0.82,0.18,1)
            else
                local mc=(pal and pal.textMuted) or {0.60,0.60,0.65,1}
                ic:SetVertexColor(mc[1],mc[2],mc[3],mc[4] or 1)
            end
        end
        return fav
    end

    local function paintData()
        local data,row=hud.data,hud.row
        hud.window=hud.context.window
        hud.kind=data.kind or 'recipe'
        hud.slotCount=hud.window=='24h' and MAX_SLOTS or DAY_COUNT
        -- Weekly-only models still supply live values, but their daily samples are not hourly history.
        hud.weekOnly=hud.window=='24h' and not (data.overviewRows or data.window=='24h' or data.startHour or data.slotCount==MAX_SLOTS)
        hud.metrics=buildMetricRows(data,row)
        hud.heading:SetText(hud.kind:upper()..' QUICK LOOK | '..(hud.window=='24h' and '24 HOURS' or '7 DAYS'))
        paintWindowButtons()
        syncFavButton()
        paintHeaders(hud.overviewHeaders)
        if hud.moverHeaders and hud.moverHeaders[1] then
            hud.moverHeaders[1]:SetText(hud.kind=='item' and 'ITEM / USED IN' or 'REAGENT')
        end
        if hud.moverEmpty then
            hud.moverEmpty:SetText(hud.kind=='item' and 'Not used in catalog recipes' or 'No reagents listed')
        end
        paintHeaders(hud.moverHeaders)
        paintHeaders(hud.scrollHeaders)

        local actionText=hud.kind=='writ' and '+ Queue Writ' or '+ Add to Cart'
        hud.addButton:SetText(actionText)
        hud.addButton.fs:SetText(actionText)
        if hud.kind=='recipe' then
            local prof=(ns.PROF_BY_KEY or {})[row.prof]
            local listed=number(row.listed) or (data.scan and data.scan.qty)
            local listedText=listed and (listed..' listed') or 'Listings unavailable'
            if listed and data.firstQty and listed~=data.firstQty then
                listedText=listedText..'  |  From '..data.firstQty
            end
            hud.title:SetText(row.name)
            hud.subtitle:SetText((prof and prof.full or row.profLabel or row.prof or '-')..' '..(row.requiredSkill or row.skill or '-')..
                '  |  Makes '..(data.made or row.numMade or 1)..'  |  '..listedText)
            hud.outputIcon:SetTexture(row.icon or ns.QUESTION_ICON)
        else
            hud.title:SetText(data.title or row.writName or row.crateName or row.name or '')
            hud.subtitle:SetText(quickLookText((data.badge or '')..' | '..(data.subtitle or '')))
            hud.outputIcon:SetTexture(data.icon or row.icon or row.writIcon or row.crateIcon or ns.QUESTION_ICON)
        end

        for i,widgets in ipairs(hud.overviewRows) do paintMetric(widgets,hud.metrics.overview[i]) end
        paintMovers()
        paintScroll()
        paintBanner()
        paintExpandChart()
        layoutSections()
    end

    local function brightenInk(ink, textInk, amount)
        return {ink[1]+(textInk[1]-ink[1])*amount,ink[2]+(textInk[2]-ink[2])*amount,
            ink[3]+(textInk[3]-ink[3])*amount,1}
    end

    local function applyQuickLookTheme(_,pal)
        hud._appliedPalette=pal
        hud.palette=pal
        hud.inks,hud.inlineInks={},nil
        if pal.mode=='dark' then
            hud.inks.textMuted=brightenInk(pal.textMuted,pal.text,0.10)
            hud.inks.accentRed=brightenInk(pal.accentRed,pal.text,0.32)
            hud.inlineInks={
                [pal.hexMuted]='|cff'..colorHex(hud.inks.textMuted),
                [pal.hexDanger]='|cff'..colorHex(hud.inks.accentRed),
            }
        end
        hud.surface:UpdateTheme(pal.mode=='dark' and pal.toolbarBg or pal.winBg,
            pal.mode=='dark' and pal.glassBorder or pal.borderStrong)
        for _,surface in ipairs(hud.surfaces) do surface:UpdateTheme() end
        for _,entry in ipairs(hud.labels) do entry[1]:SetTextColor(unpack(quickLookInk(entry[2]))) end
        local muted=pal.textMuted
        local rule={muted[1],muted[2],muted[3],0.78}
        for _,widgets in ipairs(hud.metricWidgets) do
            widgets.rule:SetColorTexture(unpack(rule))
            widgets.hover:SetColorTexture(unpack(pal.glassHover))
            widgets.active:SetColorTexture(unpack(pal.glassHover))
        end
        for _,grid in ipairs(hud.expandChart.grid) do grid:SetColorTexture(rule[1],rule[2],rule[3],(rule[4] or 0.4)*0.45) end
        if hud.expandChart.plotBg then
            if ns.Theme and ns.Theme.GetMode and ns.Theme.GetMode()=='light' then
                hud.expandChart.plotBg:SetColorTexture(0.955,0.955,0.968,0.85)
            else
                hud.expandChart.plotBg:SetColorTexture(0.055,0.059,0.067,0.78)
            end
        end
        hud.moverScrollTrack.track:SetColorTexture(unpack(rule))
        hud.moverScrollThumb:SetColorTexture(unpack(pal.text))
        hud.win24Btn.selection:SetColorTexture(unpack(pal.text))
        hud.win7dBtn.selection:SetColorTexture(unpack(pal.text))
        hud.addButton.fs:SetTextColor(unpack(pal.mode=='dark' and pal.winBg or pal.text))
        if hud.data then
            paintData()
            if shown(hud) then hud.Reposition() end
        else
            paintWindowButtons()
            syncFavButton()
        end
    end

    local function reposition()
        local parent=hud:GetParent()
        local scale=parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
        local left,top,right,bottom=uiCache.frameBounds(parent,scale)
        if not left then return end
        local screenLeft,screenTop,screenRight,screenBottom=uiCache.frameBounds(UIParent,scale)
        local minX,maxX=math.max(left,screenLeft or left)+8,math.min(right,screenRight or right)-8
        local minY,maxY=math.max(bottom,screenBottom or bottom)+8,math.min(top,screenTop or top)-8
        if maxX<=minX or maxY<=minY then return end
        local height=hud:GetHeight()
        local fit=math.min(1,(maxX-minX)/WIDTH,(maxY-minY)/height)
        hud:SetScale(fit)
        local owner=hud.owner
        local ownerRow=owner and owner.data
        local _,ownerTop,ownerRight,ownerBottom
        if ownerRow and (ownerRow==hud.row or ownerRow._orig==hud.row) then
            _,ownerTop,ownerRight,ownerBottom=uiCache.frameBounds(owner,scale)
        end
        local w,h=WIDTH*fit,height*fit
        local x=math.max(minX,math.min(maxX-w,(ownerRight or maxX)-w))
        local y=ownerBottom and ownerBottom-6 or maxY-63
        if y-h<minY and ownerTop and ownerTop+6+h<=maxY then y=ownerTop+6+h end
        y=math.max(minY+h,math.min(maxY,y))
        hud:ClearAllPoints()
        hud:SetPoint('TOPLEFT',parent,'TOPLEFT',(x-left)/fit,(y-top)/fit)
    end

    local function toggleExpanded(widgets)
        local key,section=widgets.metricKey,widgets.section
        if key==nil or not hud.data then return end
        if hud.expandedKey==key and hud.expandedSection==section then
            hud.expandedKey,hud.expandedSection=nil,nil
        else
            hud.expandedKey,hud.expandedSection=key,section
        end
        showChartPoint(nil)
        paintExpandChart()
        for _,row in ipairs(hud.metricWidgets) do paintRowState(row) end
        layoutSections()
        reposition()
    end

    local function makeHeaders(panel, name, value)
        local columns={
            {name,10,188,'LEFT'},{'QTY',202,48,'RIGHT'},{value,254,104,'RIGHT'},
            {'',364,62,'CENTER'},{'',430,88,'RIGHT'},{'%',522,48,'RIGHT'},{'',572,36,'RIGHT'},
        }
        local headers={}
        for i,col in ipairs(columns) do
            headers[i]=label(panel,col[2],4,col[3],15,10,'textMuted',col[1],col[4],'semibold')
        end
        return headers
    end

    local function makeMetricRow(panel, section, index, height)
        local row=place(CreateFrame('Button',nil,panel),panel,10,22+(index-1)*height,ROW_WIDTH,height)
        row.section=section
        row:EnableMouse(true)
        row:RegisterForClicks('LeftButtonUp')
        row:SetScript('OnClick',toggleExpanded)
        row:SetScript('OnEnter',function(self)
            local spec=self.spec
            local itemID=spec and tonumber(spec.itemID or (spec.item and spec.item.itemID))
            if itemID and itemID>0 and GameTooltip then
                GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
                if GameTooltip.SetItemByID then GameTooltip:SetItemByID(itemID)
                elseif GameTooltip.SetHyperlink then GameTooltip:SetHyperlink('item:'..tostring(itemID)) end
                if ns.AppendCrateTooltip then ns.AppendCrateTooltip(GameTooltip,itemID) end
                local T=ns.Theme
                if T and T.LiftTooltip then T.LiftTooltip(GameTooltip) end
                GameTooltip:Show()
                tooltipOwner,tooltipRow=self,nil
            end
        end)
        row:SetScript('OnLeave',leaveTooltip)
        row.rule=place(row:CreateTexture(nil,'BORDER'),row,24,0,ROW_WIDTH-24,1)
        row.hover=row:CreateTexture(nil,'HIGHLIGHT')
        row.hover:SetAllPoints(row)
        row.active=row:CreateTexture(nil,'BACKGROUND')
        row.active:SetAllPoints(row)
        row.active:Hide()
        row.icon=icon(row,0,(height-18)/2,18)
        row.name=label(row,24,0,164,height,11,'text',nil,'LEFT','semibold')
        if row.name.SetNonSpaceWrap then row.name:SetNonSpaceWrap(false) end
        if row.name.SetMaxLines then row.name:SetMaxLines(1) end
        row.qty=label(row,192,0,48,height,11,'textSecondary',nil,'RIGHT','semibold')
        row.price=label(row,244,0,104,height,11,'text',nil,'RIGHT','semibold')
        row.spark=place(CreateFrame('Frame',nil,row),row,354,(height-18)/2,62,18)
        row.trace=makeTrace(row.spark,2.2)
        row.fixed=label(row,354,0,62,height,10,'textMuted',nil,'CENTER','semibold')
        row.impact=label(row,420,0,88,height,11,'textMuted',nil,'RIGHT','semibold')
        row.pct=label(row,512,0,48,height,11,'textMuted',nil,'RIGHT','semibold')
        row.coverage=label(row,562,0,36,height,11,'textMuted',nil,'RIGHT','semibold')
        hud.metricWidgets[#hud.metricWidgets+1]=row
        return row
    end

    local function createExpandChart()
        local chart=inset(hud,INSET,0,CARD_WIDTH,CHART_HEIGHT)
        hud.expandChart=chart
        chart.title=label(chart,10,5,264,16,12,'text',nil,'LEFT','semibold')
        chart.value=label(chart,280,5,142,16,11,'text',nil,'RIGHT','semibold')
        chart.impact=label(chart,428,5,118,16,11,'textMuted',nil,'RIGHT','semibold')
        chart.pct=label(chart,552,5,62,16,11,'textMuted',nil,'RIGHT','semibold')
        chart.plotBg=place(chart:CreateTexture(nil,'BACKGROUND',nil,0),chart,PLOT_X,PLOT_TOP,PLOT_WIDTH,PLOT_HEIGHT)
        if ns.Theme and ns.Theme.GetMode and ns.Theme.GetMode()=='light' then
            chart.plotBg:SetColorTexture(0.955,0.955,0.968,0.85)
        else
            chart.plotBg:SetColorTexture(0.055,0.059,0.067,0.78)
        end
        chart.grid,chart.axis,chart.ticks,chart.hits={},{},{},{}
        for i=1,3 do
            local y=PLOT_TOP+(i-1)*PLOT_HEIGHT/2
            chart.grid[i]=place(chart:CreateTexture(nil,'BORDER'),chart,PLOT_X,y,PLOT_WIDTH,1)
            chart.axis[i]=label(chart,7,y-6,90,12,10,'textMuted',nil,'RIGHT')
        end
        for i=1,DAY_COUNT do chart.ticks[i]=label(chart,0,87,38,13,10,'textSecondary',nil,'CENTER') end
        chart.trace=makeTrace(chart,3.4,true)
        chart.hoverLine=chart:CreateTexture(nil,'OVERLAY')
        chart.hoverLine:Hide()
        chart.hoverDot=chart:CreateTexture(nil,'OVERLAY')
        chart.hoverDot:SetTexture(ns.Theme.ASSETS.circle_fill)
        chart.hoverDot:SetSize(7,7)
        chart.hoverDot:Hide()
        chart.empty=label(chart,PLOT_X,PLOT_TOP,PLOT_WIDTH,PLOT_HEIGHT,11,'textSecondary','No history in this window','CENTER')
        for slot=1,MAX_SLOTS do
            local hit=CreateFrame('Frame',nil,chart)
            hit:EnableMouse(true)
            if hit.SetMouseClickEnabled then hit:SetMouseClickEnabled(false) end
            hit:SetScript('OnEnter',function() showChartPoint(slot) end)
            hit:SetScript('OnLeave',function() if hud.hoverSlot==slot then showChartPoint(nil) end end)
            hit:Hide()
            chart.hits[slot]=hit
        end
        hud.readout=inset(chart,PLOT_X,102,PLOT_WIDTH,15,'glass_r8','cardAltBg')
        hud.readout:SetFrameLevel(chart:GetFrameLevel()+4)
        hud.dayReadout=label(hud.readout,6,0,PLOT_WIDTH-12,15,10,'textSecondary',nil,'RIGHT')
        hud.readout:Hide()
        chart:Hide()
    end

    local function setWindow(window)
        if hud.window==window and activeWindow()==window then return end
        MerchantMasterDB=MerchantMasterDB or {}
        MerchantMasterDB.quickLookWindow=window
        provider.RefreshQuickLook()
    end

    local function createQuickLook()
        local T=ns.Theme
        local parent=host.parent or view
        hud=CreateFrame('Frame','MerchantMasterQuickLookHUD',parent)
        if UISpecialFrames then table.insert(UISpecialFrames,hud:GetName()) end
        hud:Hide()
        hud:SetSize(WIDTH,66)
        hud:SetFrameStrata('DIALOG')
        hud:SetFrameLevel(parent:GetFrameLevel()+60)
        hud:SetClampedToScreen(true)
        hud:EnableMouse(true)
        hud.labels,hud.surfaces,hud.metricWidgets={},{},{}
        hud.moverOffset=0
        hud.SetMoverScroll=function(offset)
            if not hud.data then return end
            hud.moverOffset=offset
            paintMovers()
        end
        T.Nine(hud,hud,T.ASSETS.shadow_r22,24,12,'BACKGROUND',-3):SetColor(0,0,0,0.45)
        local hudShellFill=T.GetMode()=='dark' and 'toolbarBg' or 'winBg'
        hud.surface=T.NineApple(hud,'glass_r22',hudShellFill,'glassBorder',{cornerSize=22,sub=-1,noSpecular=true})
        hud.Reposition=reposition
        hud.outputIcon=icon(hud,INSET,20,34)
        hud.heading=label(hud,58,12,418,13,10,'textMuted',nil,nil,'semibold')
        hud.title=label(hud,58,25,418,22,18,'text',nil,nil,'semibold')
        hud.subtitle=label(hud,58,47,580,13,11,'textSecondary')
        local titleHover=place(CreateFrame('Frame',nil,hud),hud,INSET,14,461,44)
        titleHover:EnableMouse(true)
        titleHover:SetFrameLevel(hud:GetFrameLevel()+2)
        titleHover:SetScript('OnEnter',function(self)
            local row=hud.row
            if not row then return end
            local kind=hud.data and hud.data.kind or 'recipe'
            if kind=='recipe' then
                tooltip(self,row)
                return
            end
            local itemID=number(row.outputItemID or row.writID or row.crateID or row.itemID)
            if itemID and itemID>0 and GameTooltip then
                GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
                if GameTooltip.SetItemByID then
                    GameTooltip:SetItemByID(itemID)
                elseif GameTooltip.SetHyperlink then
                    GameTooltip:SetHyperlink('item:'..tostring(itemID))
                end
                GameTooltip:Show()
            end
        end)
        titleHover:SetScript('OnLeave',function(self) leaveTooltip(self) end)
        hud.titleHover=titleHover
        hud.favButton=place(T.CreatePlateButton(hud,'',25,25,{icon=(T and T.ASSETS and T.ASSETS.icon_star) or 'star',iconSize=13,
            variant='secondary',pill=true,border=true}),hud,484,20,25,25)
        if hud.favButton.SetFrameLevel then hud.favButton:SetFrameLevel(hud:GetFrameLevel()+4) end
        hud.favButton:SetScript('OnClick',function(self)
            local W=ns.Watchlist
            local target=quickLookWatchTarget()
            if W and type(W.Toggle)=='function' and target then
                W.Toggle(target)
            end
            local fav=syncFavButton()
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then
                GameTooltip:SetOwner(self,'ANCHOR_TOP')
                GameTooltip:AddLine(fav and 'Remove from Watchlist' or 'Add to Watchlist',1,0.85,0.25)
                if T and T.LiftTooltip then T.LiftTooltip(GameTooltip) end
                GameTooltip:Show()
            end
        end)
        hud.favButton:SetScript('OnEnter',function(self)
            if not GameTooltip then return end
            local fav=syncFavButton()
            GameTooltip:SetOwner(self,'ANCHOR_TOP')
            GameTooltip:AddLine(fav and 'Remove from Watchlist' or 'Add to Watchlist',1,0.85,0.25)
            if T and T.LiftTooltip then T.LiftTooltip(GameTooltip) end
            GameTooltip:Show()
        end)
        hud.favButton:SetScript('OnLeave',function(self) leaveTooltip(self) end)
        local windowControl=inset(hud,516,20,90,25,'pill','glassFill')
        local pillOpts={variant='secondary',pill=true,fontSize=10,weight='semibold'}
        hud.win24Btn=place(T.CreatePlateButton(windowControl,'24h',44,23,pillOpts),windowControl,1,1,44,23)
        hud.win7dBtn=place(T.CreatePlateButton(windowControl,'7d',44,23,pillOpts),windowControl,45,1,44,23)
        for _,button in ipairs({hud.win24Btn,hud.win7dBtn}) do
            button.selection=place(button:CreateTexture(nil,'OVERLAY'),button,17,19,10,1)
        end
        hud.win24Btn:SetScript('OnClick',function() setWindow('24h') end)
        hud.win7dBtn:SetScript('OnClick',function() setWindow('7d') end)
        hud.closeButton=place(T.CreatePlateButton(hud,'',25,25,{icon=T.ASSETS.icon_close,iconSize=13,
            variant='secondary',pill=true,border=true}),hud,614,20,25,25)
        hud.closeButton:SetScript('OnClick',provider.CloseQuickLook)

        local overview=inset(hud,INSET,66,CARD_WIDTH,172)
        hud.overviewPanel=overview
        hud.overviewHeaders=makeHeaders(overview,'OVERVIEW','VALUE')
        hud.overviewRows={}
        for i=1,6 do hud.overviewRows[i]=makeMetricRow(overview,'overview',i,24) end

        local moverPanel=inset(hud,INSET,0,CARD_WIDTH,132)
        hud.moverPanel=moverPanel
        hud.moverHeaders=makeHeaders(moverPanel,'REAGENT','PRICE')
        hud.movers={}
        enableMoverWheel(moverPanel)
        for i=1,4 do
            local mover=makeMetricRow(moverPanel,'mover',i,26)
            enableMoverWheel(mover)
            hud.movers[i]=mover
        end
        hud.moverEmpty=label(moverPanel,10,22,ROW_WIDTH,104,11,'textMuted','No reagents listed','CENTER')
        local track=place(CreateFrame('Frame',nil,moverPanel),moverPanel,612,23,4,102)
        hud.moverScrollTrack=track
        track.track=place(track:CreateTexture(nil,'BACKGROUND'),track,0,0,4,102)
        hud.moverScrollThumb=place(track:CreateTexture(nil,'ARTWORK'),track,0,0,4,102)
        track:EnableMouse(true)
        enableMoverWheel(track)
        track:SetScript('OnMouseDown',function(self,button)
            if button~='LeftButton' then return end
            local _,cursorY=GetCursorPosition()
            local y=self:GetTop()-cursorY/self:GetEffectiveScale()
            if y<hud.moverThumbY then hud.SetMoverScroll(hud.moverOffset-1)
            elseif y>hud.moverThumbY+hud.moverScrollThumb:GetHeight() then hud.SetMoverScroll(hud.moverOffset+1) end
        end)

        local scroll=inset(hud,INSET,0,CARD_WIDTH,96)
        hud.scrollPanel=scroll
        hud.scrollHeaders=makeHeaders(scroll,'RECIPE SCROLL','PRICE')
        hud.scrollRow=makeMetricRow(scroll,'scroll',1,24)
        hud.scrollListedRow=makeMetricRow(scroll,'scroll',2,24)
        hud.scrollMetricRows={hud.scrollRow,hud.scrollListedRow}
        hud.whereToBuy=label(scroll,10,72,496,20,10,'textSecondary')
        hud.breakEven=label(scroll,10,84,496,11,10,'textSecondary')
        hud.wowheadButton=place(T.CreatePlateButton(scroll,'Wowhead',100,22,
            {variant='secondary',pill=true,border=true,fontSize=11,icon=T.ASSETS.icon_send,iconSize=11}),scroll,512,71,100,22)
        hud.wowheadButton:SetScript('OnClick',function()
            if hud.wowheadCA and hud.data and host.openWowheadPopup then
                host.openWowheadPopup(hud.wowheadCA,hud.data.title or hud.row.name,hud.outputIcon:GetTexture())
            end
        end)

        createExpandChart()
        local footer=place(CreateFrame('Frame',nil,hud),hud,INSET,0,CARD_WIDTH,30)
        hud.footer=footer
        hud.addButton=place(T.CreatePlateButton(footer,'+ Add to Cart',132,29,
            {variant='primary',fontSize=11}),footer,0,0,132,29)
        hud.deepAnalysisButton=place(T.CreatePlateButton(footer,'Deep Analysis >',138,29,
            {variant='secondary',pill=true,border=true,fontSize=11,icon=T.ASSETS.icon_trend,iconSize=11}),footer,389,0,138,29)
        hud.searchButton=place(T.CreatePlateButton(footer,'Search AH',89,29,
            {variant='secondary',pill=true,border=true,fontSize=11,icon=T.ASSETS.icon_search,iconSize=11}),footer,535,0,89,29)
        hud.addButton:SetScript('OnClick',function(self)
            local row=hud.row
            if hud.data.kind=='item' then
                local added=host.addQuickLookItem and host.addQuickLookItem('item',row)
                provider.RefreshQuickLook()
                if added then
                    self:SetText('Added')
                    if self.fs then self.fs:SetText('Added') end
                end
                return
            end
            if hud.data.kind and hud.data.kind~='recipe' then
                if host.addQuickLookItem then host.addQuickLookItem(hud.data.kind,row) end
                provider.RefreshQuickLook()
                return
            end
            local before=host.getRecipeShoppingQty(row)
            if (host.adjustRecipeShoppingQty(row,1) or 0)>before then self:SetText('Added') end
        end)
        hud.deepAnalysisButton:SetScript('OnClick',function()
            if not hud.row then return end
            local openFn=(host and host.openDeepAnalysis) or (ns.app and ns.app.openDeepAnalysis)
            if type(openFn)~='function' then return end
            local kind=hud.kind or (hud.data and hud.data.kind) or 'recipe'
            local returnCtx={
                tab=hud.openedTab or (host and host.getActiveTab and host.getActiveTab()) or 'recipes',
                wasQuickLookOpen=true,
                quickLookKind=kind,
                quickLookRow=hud.row,
                quickLookWindow=hud.window or activeWindow(),
                superListScrollPct=getSuperListScrollPct(),
            }
            openFn({
                kind=kind,
                row=hud.row,
                context=hud.context,
                window=hud.window or activeWindow(),
            },returnCtx)
        end)
        hud.searchButton:SetScript('OnClick',function()
            local id=hud.row.outputItemID or hud.row.writID or hud.row.crateID or hud.row.itemID
                or (hud.row.recipe and hud.row.recipe.outputItemID)
            if host.atAH() and id then
                hud.banner:Hide()
                host.searchAH(hud.data.title or hud.row.name,1,id)
            else
                paintBanner()
                hud.banner:SetShown(not shown(hud.banner))
            end
        end)
        hud.banner=inset(hud,INSET,0,CARD_WIDTH,34)
        hud.banner:SetFrameLevel(hud:GetFrameLevel()+40)
        hud.banner:EnableMouse(true)
        hud.bannerText=label(hud.banner,24,0,564,34,11,'textSecondary')
        hud.bannerDot=place(hud.banner:CreateTexture(nil,'ARTWORK'),hud.banner,10,14,6,6)
        hud.bannerDot:SetTexture(T.ASSETS.circle_fill)
        local bannerClose=place(T.CreatePlateButton(hud.banner,'',24,24,{icon=T.ASSETS.icon_close,
            iconSize=10,variant='ghost',pill=true}),hud.banner,594,5,24,24)
        bannerClose:SetScript('OnClick',function() hud.banner:Hide() end)
        hud.banner:Hide()
        local function bannerVisibilityChanged()
            if not hud.data or not shown(hud) then return end
            layoutSections()
            reposition()
        end
        hud.banner:SetScript('OnShow',bannerVisibilityChanged)
        hud.banner:SetScript('OnHide',bannerVisibilityChanged)

        hud:SetScript('OnEvent',function(self,event,button)
            if event=='PLAYER_REGEN_ENABLED' then
                if not combatLocked() then uiCache.enableEscape(self) end
            else
                local shiftValue=shiftKeyDown()
                if shiftValue==nil then return end
                local shiftHeld=shiftValue or shiftActive
                if event=='GLOBAL_MOUSE_DOWN' and readable(button) and button=='LeftButton' and not shiftHeld then
                    local overRecipe=false
                    tbl.scrollBox:ForEachFrame(function(frame)
                        if not overRecipe and frame.data~=nil and isMouseOverFrame(frame) then
                            local cells=frame.cellGroup and frame.cellGroup.cellsByKey
                            local whCell=cells and cells.wowheadURL
                            if not (shown(whCell) and isMouseOverFrame(whCell)) then overRecipe=true end
                        end
                    end)
                    if overRecipe then return end
                    if host.isQuickLookRowHovered and host.isQuickLookRowHovered() then return end
                end
                local appearanceHovered=false
                if type(host.isAppearanceHovered)=='function' then
                    local ok,value=pcall(host.isAppearanceHovered)
                    appearanceHovered=ok and readable(value) and value==true
                end
                if not isMouseOverFrame(self) and not appearanceHovered then
                    provider.CloseQuickLook()
                end
            end
        end)
        hud:SetScript('OnKeyDown',function(self,key)
            if not readable(key) or type(key)~='string' then return end
            if self.SetPropagateKeyboardInput and not combatLocked() then
                self:SetPropagateKeyboardInput(key~='ESCAPE')
            end
            if key=='ESCAPE' then provider.CloseQuickLook() end
        end)
        hud:SetScript('OnShow',function(self)
            self:RegisterEvent('GLOBAL_MOUSE_DOWN')
            self:RegisterEvent('PLAYER_REGEN_ENABLED')
            if not combatLocked() then uiCache.enableEscape(self) end
        end)
        hud:SetScript('OnHide',function(self)
            if self.titleHover then leaveTooltip(self.titleHover) end
            if self.favButton then leaveTooltip(self.favButton) end
            for _,w in ipairs(self.metricWidgets or {}) do leaveTooltip(w) end
            self:UnregisterEvent('GLOBAL_MOUSE_DOWN')
            self:UnregisterEvent('PLAYER_REGEN_ENABLED')
            if self.EnableKeyboard then self:EnableKeyboard(false) end
            self:SetScript('OnUpdate',nil)
            self.expandChart.metric=nil
            showChartPoint(nil)
            self.expandChart:Hide()
            self.banner:Hide()
            self.expandedKey,self.expandedSection,self.metrics=nil,nil,nil
            self.owner,self.row,self.data,self.pinned,self.context,self.openedTab=nil,nil,nil,nil,nil,nil
            self.window,self.wowheadCA=nil,nil
        end)
        hud.SyncFavButton=syncFavButton
        if ns.Watchlist and type(ns.Watchlist.RegisterListener)=='function' then
            ns.Watchlist.RegisterListener(function() if hud and shown(hud) then syncFavButton() end end)
        end
        T.RegisterWidget(hud,applyQuickLookTheme)
    end

    local function resolveQuickLook(target,context,recipe)
        local function matches(row)
            if not row then return false end
            if recipe then return row.recipe==recipe end
            return row==target or row.key==target or row.outputItemID==target
        end
        local owner
        tbl.scrollBox:ForEachFrame(function(frame)
            if not owner and matches(frame.data) then owner=frame end
        end)
        if owner then return owner.data,owner end
        if not recipe and type(target)=='table' then return target end
        for _,row in ipairs((buildState and buildState.rows) or rows or {}) do
            if matches(row) then return row end
        end
        if recipe then return ns.RecipeStats.Get(recipe,context) end
        for _,entry in ipairs(ns.RecipeStats.GetCatalog()) do
            if entry.key==target or entry.recipe.outputItemID==target then
                return ns.RecipeStats.Get(entry.recipe,context)
            end
        end
    end

    local function quickLookContext(context, kind)
        local result={}
        for k,v in pairs(context or {}) do result[k]=v end
        result.kind=kind
        result.window=activeWindow()
        return result
    end

    function provider.OpenQuickLook(rowOrKeyOrItemID,keepPinned,recipe,opts)
        opts=opts or {}
        local kind=opts.kind or (type(rowOrKeyOrItemID)=='table' and rowOrKeyOrItemID.forged and 'forged') or 'recipe'
        local acquisition=kind=='writ' or kind=='crate' or kind=='forged'
        local catalogItem=kind=='item'
        local simpleRecipe=opts.kind=='recipe' and (opts.owner~=nil or (type(rowOrKeyOrItemID)=='table' and rowOrKeyOrItemID.recipe~=nil))
        if not view or (not acquisition and not simpleRecipe and not catalogItem and not active()) or rowOrKeyOrItemID==nil then return end
        local context=evaluation or {applyAHCut=not MerchantMasterDB or MerchantMasterDB.applyAHCut~=false}
        if acquisition or simpleRecipe or catalogItem then
            context=host.getQuickLookContext and host.getQuickLookContext() or {}
        end
        context=quickLookContext(context,kind)
        local row,owner
        if acquisition or simpleRecipe or catalogItem then
            if catalogItem and type(rowOrKeyOrItemID)~='table' and host.resolveQuickLookRow then
                local id=tonumber(tostring(rowOrKeyOrItemID):match('(%d+)'))
                row=id and host.resolveQuickLookRow('item',{itemID=id}) or nil
            else
                row=rowOrKeyOrItemID
            end
            owner=opts.owner
        else
            row,owner=resolveQuickLook(rowOrKeyOrItemID,context,recipe)
        end
        if not row or (not acquisition and not catalogItem and not row.recipe) then return end
        local pal=getThemePalette()
        local priceVer=(ns.GetEffectivePriceVersion and ns.GetEffectivePriceVersion()) or ns.priceCacheEpoch
        local openedTab=host.getActiveTab and host.getActiveTab() or 'recipes'
        if shown(hud) and hud.pinned==(keepPinned==true) and hud.row==row and hud.kind==kind
            and hud.window==context.window and hud.openedTab==openedTab
            and hud._evalPriceVer==priceVer and hud._evalCtx==evaluation then
            hud.owner=owner
            if owner then hideRowTooltip(owner) end
            reposition()
            return hud
        end
        local data=ns.RecipeStats.BuildQuickLook(row,context)
        if not data then return end
        if not hud then createQuickLook() end
        closeHeatPopover()
        if hud.kind~=kind or not sameQuickLookTarget(hud.row,row,kind) then
            hud.moverOffset=0
            hud.expandedKey,hud.expandedSection=nil,nil
        end
        hud.row,hud.data,hud.owner,hud.pinned=row,data,owner,keepPinned==true
        hud.context=context
        hud.openedTab=openedTab
        hud._evalPriceVer,hud._evalCtx=priceVer,evaluation
        if owner then
            hideRowTooltip(owner)
            if hud.pinned and not acquisition and not simpleRecipe and not catalogItem then
                selectedKey=row.key
                tbl.scrollBox:ForEachFrame(paintSelection)
            end
        end
        hud.addButton:SetText('+ Add to Cart')
        hud.banner:Hide()
        showChartPoint(nil)
        if hud._appliedPalette~=pal then applyQuickLookTheme(nil,pal) else paintData() end
        reposition()
        hud:Show()
        local outside=0
        hud:SetScript('OnUpdate',not hud.pinned and function(self,elapsed)
            if isMouseOverFrame(self) or (self.owner and self.owner.data==self.row and isMouseOverFrame(self.owner)) then
                outside=0
            else
                outside=outside+elapsed
                if outside>=0.24 then provider.CloseQuickLook() end
            end
        end or nil)
        return hud
    end

    function provider.CloseQuickLook()
        if shown(hud) then hud:Hide() end
    end

    function provider.GetQuickLookFrame() return hud end
    function provider.RefreshQuickLook()
        if not shown(hud) or not hud.data then return false end
        local kind,row=hud.kind,hud.row
        if kind~='recipe' and host.resolveQuickLookRow then
            row=host.resolveQuickLookRow(kind,row) or row
        end
        local context=hud.context
        if host.getQuickLookContext then
            context=host.getQuickLookContext()
        end
        context=quickLookContext(context,kind)
        local data=ns.RecipeStats.BuildQuickLook(row,context)
        if not data then
            provider.CloseQuickLook()
            return false
        end
        if not sameQuickLookTarget(hud.row,row,kind) then
            hud.moverOffset=0
            hud.expandedKey,hud.expandedSection=nil,nil
        end
        hud.row,hud.context,hud.data=row,context,data
        paintData()
        reposition()
        return true
    end
end

function provider.Layout(width,height,deferScrollRefresh)
    if not view then return end
    local minimum=4
    for _,col in ipairs(tbl.columns) do minimum=minimum+(col.minWidth or col.width)+5 end
    if active() and host.setMinimumWidth then
        host.setMinimumWidth(minimum+(host.windowPadding or 0))
    end
    local w=tonumber(width) or 0
    if w<=0 then
        w=(host and host.parent and host.parent.GetWidth and host.parent:GetWidth()) or 0
        if w<=0 and view and view.GetWidth then w=view:GetWidth() or 0 end
    end
    local hdrW=(tbl.headerBar and tbl.headerBar.GetWidth and tbl.headerBar:GetWidth()) or 0
    ns.Window.LayoutTable(tbl,math.max(hdrW,w-24),1,deferScrollRefresh)
    if tbl and tbl.scrollBox and tbl.scrollBox.ForEachFrame then
        local demandW
        for _,col in ipairs(tbl.columns or {}) do
            if col.key=='demandSort' then demandW=col.width; break end
        end
        if demandW then
            local stripW=math.max(24,demandW-4)
            tbl.scrollBox:ForEachFrame(function(r)
                local cell=r.cellGroup and r.cellGroup.cellsByKey and r.cellGroup.cellsByKey.demandSort
                if cell and cell._heatStripBound and cell.heatStrip then
                    cell.heatStrip:Layout(stripW)
                end
            end)
        end
    end
    local quickLook=provider.GetQuickLookFrame()
    if shown(quickLook) then quickLook.Reposition() end
    local pop=type(view)=='table' and rawget(view,'heatPopover') or nil
    if (type(pop)=='table' or type(pop)=='userdata') and shown(pop) then
        repositionHeatPopover(pop,pop.ownerCell)
    end
end
function provider.CloseHeatPopover()
    closeHeatPopover()
end
function provider.GetHeatPopover()
    local pop=type(view)=='table' and rawget(view,'heatPopover') or nil
    return (type(pop)=='table' or type(pop)=='userdata') and pop or nil
end
ns.CloseSuperListHeatPopover=closeHeatPopover
function provider.GetColumnConfig()
    local cfg=normalizeColumnConfig(getColumnDB())
    local orderCopy,hiddenCopy={},{}
    for i,k in ipairs(cfg.order) do orderCopy[i]=k end
    for k,v in pairs(cfg.hidden) do if v then hiddenCopy[k]=true end end
    return {order=orderCopy,hidden=hiddenCopy}
end
function provider.SetColumnVisible(key,visible)
    if key=='name' or not MASTER_BY_KEY[key] then return false end
    local db=getColumnDB()
    local cfg=normalizeColumnConfig(db)
    cfg.hidden[key]=(visible==false) and true or nil
    if view and view._applyColumnConfig then view._applyColumnConfig(db) end
    return true
end
function provider.MoveColumn(key,delta)
    if key=='name' or not MASTER_BY_KEY[key] then return false end
    local step=tonumber(delta)
    if not step or step==0 then return false end
    local db=getColumnDB()
    local cfg=normalizeColumnConfig(db)
    local pos
    for i,k in ipairs(cfg.order) do if k==key then pos=i; break end end
    if not pos then return false end
    local target=math.max(2,math.min(#cfg.order,pos+step))
    if target==pos then return false end
    table.remove(cfg.order,pos)
    table.insert(cfg.order,target,key)
    if view and view._applyColumnConfig then view._applyColumnConfig(db) end
    return true
end
function provider.ResetColumns()
    local db=getColumnDB()
    local cfg=normalizeColumnConfig(db)
    cfg.order={}
    for i,col in ipairs(MASTER_COLUMNS) do cfg.order[i]=col.key end
    cfg.hidden={}
    if view and view._applyColumnConfig then view._applyColumnConfig(db) end
    return true
end
function provider.ToggleColumnSettings(force)
    local pop=view and view.colSettingsPopover
    if not pop then return false end
    local show
    if force~=nil then show=(force==true) else show=not shown(pop) end
    if show then
        if view._ensureColumnPopoverBuilt then view._ensureColumnPopoverBuilt() end
        if view._themeColumnSettingsPopover then view._themeColumnSettingsPopover()
        elseif view._refreshColumnPopover then view._refreshColumnPopover() end
    end
    pop:SetShown(show)
    return show
end
function provider.GetSidebarControls()
    local s=host.sidebar
    return {s.sellBtn,view.sourceButton,view.skillControl,s.recCraftFilterBtn,s.recDemandFilterBtn,s.subCraftBtn,view.resetFiltersButton}
end
MerchantMasterAPI.RegisterSuperList(provider)

---------------------------------------------------------------------------------------------------
-- Vendor Crafter & Disenchantment Crafter UI — parameterized factory for Lua 5.1 local safety
---------------------------------------------------------------------------------------------------
do
    local function createCrafterProvider(spec)
    local vcProvider = {}
    local S, H, C = {}, {}, {}
    local dbPrefix = spec.dbPrefix

    C.VENDOR_COLUMNS = spec.columns
    C.VENDOR_BY_KEY = {}
    for _, col in ipairs(C.VENDOR_COLUMNS) do C.VENDOR_BY_KEY[col.key] = col end

    C.MOAT_FILTERS = {
        {key='all', label='All Moats'},
        {key='vendor_loop', label='Vendor Loop (Inf)'},
        {key='ah_only', label='AH Crafts Only'},
        {key='deep', label='Infinite & Deep'},
        {key='steady', label='Steady+'},
        {key='moment', label='Moment Only'},
    }
    C.MOAT_PILL_LABELS = {
        all = 'All Moats',
        vendor_loop = 'Vendor Loop',
        ah_only = 'AH Only',
        deep = 'Inf & Deep',
        steady = 'Steady+',
        moment = 'Moment',
    }
    C.YIELD_MODES = {
        {key='auto', label='Yield: Auto (Ledger)'},
        {key='uniform', label='Yield: Uniform'},
        {key='min', label='Yield: Min (Safe)'},
        {key='measured', label='Yield: Measured'},
    }
    C.YIELD_PILL_LABELS = {
        auto = 'Yield: Auto',
        uniform = 'Yield: Uniform',
        min = 'Yield: Min',
        measured = 'Yield: Measured',
    }
    C.TOP_N_OPTIONS = {
        {key=5, label='Plan: Top 5'},
        {key=10, label='Plan: Top 10'},
        {key=20, label='Plan: Top 20'},
        {key='all', label='Plan: All'},
    }
    C.MAX_CRAFTS_OPTIONS = {
        {key=0, label='Cap: Max'},
        {key=100, label='Cap: 100x'},
        {key=250, label='Cap: 250x'},
        {key=500, label='Cap: 500x'},
        {key=1000, label='Cap: 1000x'},
    }
    C.BUDGET_OPTIONS = {
        {key=0, label='Budget: Unlim'},
        {key=500000, label='Budget: 50g'},
        {key=1000000, label='Budget: 100g'},
        {key=2500000, label='Budget: 250g'},
        {key=5000000, label='Budget: 500g'},
    }
    C.DEPTH_LABELS = {
        vendor = 'Unlimited NPC Vendors',
        live_lots = 'Live AH Lots',
        snapshot_depth = 'AH Market Depth',
        listed = 'AH Listed Count',
        none = 'Unavailable',
    }
    C.STABILITY_LABELS = {
        infinite = 'Infinite (Vendor-Only)',
        sustained = 'Sustained',
        flash_dip = 'Flash Dip (Temporary)',
        mixed = 'Mixed',
        unknown = 'Unknown',
    }
    C.FALLBACK = {
        text = {1, 1, 1},
        muted = {0.6, 0.6, 0.6},
        secondary = {0.82, 0.82, 0.85},
        pillText = {0.88, 0.88, 0.90},
        green = {0.20, 0.78, 0.35},
        blue = {0.36, 0.72, 1.00},
        orange = {1.00, 0.57, 0.19},
        red = {1.00, 0.26, 0.27},
        lightRed = {0.722, 0.078, 0.102},
    }

    C.VC_NUMERIC_KEYS = spec.numericKeys or {
        craftCost = true, minVendor = true, avgVendor = true, maxVendor = true,
        avgProfit = true, minProfit = true, maxProfit = true, marginPct = true,
        moatScore = true, profitableCrafts = true, totalProfitCap = true, totalSpendCap = true,
        buyCeiling = true, safeProfitCrafts = true, planCrafts = true, planProfit = true,
        planRank = true, requiredSkill = true, knownSort = true, cdSort = true,
        buyCostCopper = true, numMade = true, repSort = true, ownedOutputQty = true, ownedScrollQty = true,
    }

    S.generation = 0
    S.presentSeq = 0
    S.prewarmSeq = 0
    S.reconcileSeq = 0
    S.pending = false
    S.reconcilePending = false
    S.forceVersion = 0
    S.metaDirty = false
    S.metaTargets = nil
    S.seenCraftYieldVersion = nil
    S.itemChanges = {}
    S.inFlightPresent = nil
    S.filterLRU = uiCache.createFilterLRU(8)
    S.warmContext = nil
    S.earlyPresentedFilterKey = nil
    S.earlyBoundResult = nil
    S.earlyCountShown = nil
    S.earlyTier1Done = nil
    S.earlyWarmTotal = nil
    S.earlyAuthoritative = nil
    S.shiftActive = false
    S.lastShiftDown = false
    S.colEpoch = 0
    S.cellCacheEpoch = 0
    S.metaEpoch = 0
    S.prepared = {}
    S.changes = {}
    S.cellValueCache = setmetatable({}, { __mode = 'k' })
    S.fallbackColConfig = { order = {}, hidden = {} }
    for i, col in ipairs(C.VENDOR_COLUMNS) do S.fallbackColConfig.order[i] = col.key end

    function H.active()
        return not S.host or not S.host.isActive or S.host.isActive()
    end

    function H.getColumnDB()
        return (S.latest and S.latest.db) or _G.MerchantMasterDB
    end

    function H.setBtnText(btn, txt)
        if not btn then return end
        if btn.SetText then btn:SetText(txt) end
        if btn.fs and btn.fs.SetText then btn.fs:SetText(txt) end
    end

    function H.liftAndShowTooltip()
        if not GameTooltip then return end
        local T = ns.Theme
        if T and T.LiftTooltip then T.LiftTooltip(GameTooltip) end
        GameTooltip:Show()
    end

    function H.copyColumn(col)
        local copy = {}
        for k, v in pairs(col) do copy[k] = v end
        return copy
    end

    function H.normalizeColumnConfig(db)
        local cfg
        local colKey = dbPrefix .. 'Columns'
        if type(db) == 'table' then
            if type(db[colKey]) ~= 'table' then db[colKey] = {} end
            cfg = db[colKey]
        else
            cfg = S.fallbackColConfig
        end
        local seen = {}
        local nextOrder = {}
        if type(cfg.order) == 'table' then
            for _, key in ipairs(cfg.order) do
                if type(key) == 'string' and C.VENDOR_BY_KEY[key] and not seen[key] then
                    seen[key] = true
                    nextOrder[#nextOrder + 1] = key
                end
            end
        end
        for _, col in ipairs(C.VENDOR_COLUMNS) do
            if not seen[col.key] then
                seen[col.key] = true
                nextOrder[#nextOrder + 1] = col.key
            end
        end
        if nextOrder[1] ~= 'name' then
            local filtered = {'name'}
            for _, k in ipairs(nextOrder) do
                if k ~= 'name' then filtered[#filtered + 1] = k end
            end
            nextOrder = filtered
        end
        cfg.order = nextOrder
        if type(cfg.hidden) ~= 'table' then cfg.hidden = {} end
        cfg.hidden.name = nil
        for k, v in pairs(cfg.hidden) do
            if not C.VENDOR_BY_KEY[k] or v ~= true then cfg.hidden[k] = nil end
        end
        return cfg
    end

    function H.getActiveColumnDefs(db)
        local cfg = H.normalizeColumnConfig(db)
        local activeCols = {}
        for _, key in ipairs(cfg.order) do
            if not cfg.hidden[key] then
                activeCols[#activeCols + 1] = H.copyColumn(C.VENDOR_BY_KEY[key])
            end
        end
        return activeCols, cfg
    end

    function H.runGuarded(fn)
        local ok, err = pcall(fn)
        if ok then return end
        local cancel = S.cancelBuild or (S.buildState and S.buildState.cancel)
        S.pending, S.cancelBuild, S.reconcilePending, S.transientCells = false, nil, false, nil
        if cancel then pcall(cancel) end
        S.generation = S.generation + 1
        S.presentSeq = S.presentSeq + 1
        S.prewarmSeq = S.prewarmSeq + 1
        S.reconcileSeq = (S.reconcileSeq or 0) + 1
        S.inFlightPresent = nil
        S.boundResult = nil
        S.boundFilterKey = nil
        S.earlyPresentedFilterKey = nil
        S.earlyBoundResult = nil
        S.earlyCountShown = nil
        if ns.ResetEval then ns.ResetEval() end
        error(err, 0)
    end

    function H.laterGuarded(fn)
        later(function() H.runGuarded(fn) end)
    end

    function H.queuedQtyFor(data)
        if not data or not S.host or type(S.host.getRecipeShoppingQty) ~= 'function' then return 0 end
        return tonumber(S.host.getRecipeShoppingQty(data)) or 0
    end

    local nilFallback = (spec.mode == 'disenchant') and '-' or 'n/a'

    function H.formatRoundedMoney(v, signed)
        if not number(v) then return nilFallback end
        return money(math.floor(v + 0.5), signed)
    end

    function H.formatExactCopperNote(v)
        if not number(v) then return '' end
        local rounded = math.floor(v + 0.5)
        if math.abs(v - rounded) >= 0.05 then
            return string.format(' (%.1fc)', v)
        end
        return ''
    end

    function H.formatAvgProfitCell(val, pal)
        if not number(val) then return nilFallback end
        local greenHex = (pal and pal.hexPositive) or colorHex(pal and pal.accentGreen, '30d158')
        if val > 0 and val < 0.5 then
            return '|cff' .. greenHex .. '+<1c|r'
        end
        if val < 0 and val > -0.5 then
            local redHex = (pal and pal.hexNegative) or colorHex(pal and pal.accentRed, 'ff453a')
            return '|cff' .. redHex .. '-<1c|r'
        end
        return money(math.floor(val + 0.5), true)
    end

    function H.formatMarginCell(val)
        if not number(val) then return nilFallback end
        if val >= 999 then return '+999%+' end
        if val <= -999 then return '-999%+' end
        if val < 0 then return string.format('%.1f%%', val) end
        if val == 0 then return '0.0%' end
        return string.format('+%.1f%%', val)
    end

    function H.formatProfitCapCell(val)
        if val == math.huge then return 'Inf' end
        if not number(val) then return nilFallback end
        return money(math.floor(val + 0.5), true)
    end

    function H.formatCooldown(cdInfo)
        if type(cdInfo) ~= 'table' or not cdInfo.hasCooldown then return '-' end
        if cdInfo.available == true then return 'R' end
        local sec = (cdInfo.onCooldown and number(cdInfo.remainingSeconds)) or number(cdInfo.nominalSeconds) or 0
        if sec >= 3600 then
            return string.format('%dh', math.max(1, math.floor(sec / 3600 + 0.5)))
        end
        return string.format('%dm', math.min(59, math.max(1, math.ceil(sec / 60))))
    end

    function H.isOnlyProfitable(context)
        if spec.mode ~= 'disenchant' then return true end
        if context and context.onlyProfitable ~= nil then
            return context.onlyProfitable == true
        end
        if S.latest and S.latest.onlyProfitable ~= nil then
            return S.latest.onlyProfitable == true
        end
        local db = _G.MerchantMasterDB
        return (type(db) == 'table' and db[dbPrefix .. 'OnlyProfitable'] == true) and true or false
    end

    function H.isShowNonDE(context)
        if spec.mode ~= 'disenchant' then return false end
        if context and context.showNonDE ~= nil then
            return context.showNonDE == true
        end
        if S.latest and S.latest.showNonDE ~= nil then
            return S.latest.showNonDE == true
        end
        local db = _G.MerchantMasterDB
        return (type(db) == 'table' and db[dbPrefix .. 'ShowNonDE'] == true) and true or false
    end

    function H.isArcaneSalvager(context)
        if spec.mode ~= 'disenchant' then return false end
        if context and context.arcaneSalvager ~= nil then
            return context.arcaneSalvager == true
        end
        if S.latest and S.latest.arcaneSalvager ~= nil then
            return S.latest.arcaneSalvager == true
        end
        local db = _G.MerchantMasterDB
        return (type(db) == 'table' and db[dbPrefix .. 'ArcaneSalvager'] == true) and true or false
    end

    function H.craftCountNoun(context)
        if H.isOnlyProfitable(context) then
            return 'profitable ' .. spec.craftWordPlural
        end
        if spec.mode == 'disenchant' and H.isShowNonDE(context) then
            return 'all crafts'
        end
        return spec.craftWordPlural
    end

    function H.formatSummary(result)
        local count = #(result or {})
        local onlyProf = H.isOnlyProfitable()
        if count == 0 then
            return onlyProf and '0 profitable crafts' or '0 crafts'
        end
        local hasInf, hasFinite, sumCap, profCount = false, false, 0, 0
        for i = 1, count do
            local r = result[i]
            if r and number(r.avgProfit) and r.avgProfit > 0 then
                profCount = profCount + 1
            end
            local cap = r and r.totalProfitCap
            if cap == math.huge then
                hasInf = true
            elseif number(cap) then
                hasFinite = true
                sumCap = sumCap + cap
            end
        end
        local craftWord = (count == 1) and 'craft' or 'crafts'
        local capTxt
        if hasInf then
            capTxt = 'Inf'
        elseif hasFinite then
            capTxt = money(math.floor(sumCap + 0.5), true)
        else
            capTxt = nilFallback
        end
        if onlyProf then
            return string.format('%d profitable %s · Cap %s', count, craftWord, capTxt)
        end
        return string.format('%d %s (%d profitable) · Cap %s', count, craftWord, profCount, capTxt)
    end

    function H.sourceLabel(db)
        local map = (type(db) == 'table' and type(db[dbPrefix .. 'Sources']) == 'table') and db[dbPrefix .. 'Sources'] or {}
        local labels = {}
        for _, s in ipairs(sources) do
            if s.key ~= 'all' and map[s.key] then
                labels[#labels + 1] = (s.key == 'merchant') and 'Merchant' or s.label
            end
        end
        if #labels == 0 then return 'Sources: All' end
        if #labels == 1 then return 'Sources: ' .. labels[1] end
        if #labels == 2 then return 'Src: ' .. table.concat(labels, ' + ') end
        return 'Sources: ' .. #labels .. ' selected'
    end

    function H.syncSkills(db)
        if not S.view or type(db) ~= 'table' then return end
        local lo = ns.SuperListModel and ns.SuperListModel.SkillBound and ns.SuperListModel.SkillBound(db[dbPrefix .. 'SkillMin']) or nil
        local hi = ns.SuperListModel and ns.SuperListModel.SkillBound and ns.SuperListModel.SkillBound(db[dbPrefix .. 'SkillMax']) or nil
        db[dbPrefix .. 'SkillMin'], db[dbPrefix .. 'SkillMax'] = lo, hi
        if S.view.skillMin then S.view.skillMin:SetText(lo and tostring(lo) or '') end
        if S.view.skillMax then S.view.skillMax:SetText(hi and tostring(hi) or '') end
        if S.view.skillError then S.view.skillError:SetText(lo and hi and lo > hi and 'Min exceeds max' or '') end
    end

    function H.resolveLegacy(context)
        local db = (context and context.db) or _G.MerchantMasterDB or {}
        local opts = {
            masterChefMode = (context and context.masterChefMode ~= nil) and context.masterChefMode
                or ((db[dbPrefix .. 'MasterChef'] ~= nil) and db[dbPrefix .. 'MasterChef'] or 'auto'),
            barteringMode = (context and context.barteringMode ~= nil) and context.barteringMode
                or ((db[dbPrefix .. 'Bartering'] ~= nil) and db[dbPrefix .. 'Bartering'] or 'auto'),
            honoredDiscount = (context and context.honoredDiscount ~= nil) and (context.honoredDiscount == true)
                or (db[dbPrefix .. 'Honored'] == true),
        }
        local model = ns[spec.modelName]
        if model and model.ResolveLegacy then
            return model.ResolveLegacy(opts)
        end
        local mc = (opts.masterChefMode == 'auto') and 0 or (tonumber(opts.masterChefMode) or 0)
        local br = (opts.barteringMode == 'auto') and 0 or (tonumber(opts.barteringMode) or 0)
        return {
            masterChef = mc, liveMasterChef = 0, masterChefAuto = (opts.masterChefMode == 'auto'),
            bartering = br, liveBartering = 0, barteringAuto = (opts.barteringMode == 'auto'),
            honored = opts.honoredDiscount == true,
            vendorMult = (1 - 0.05 * br) * (opts.honoredDiscount and 0.90 or 1.0),
            cookingProcChance = 0.10 * mc,
        }
    end

    function H.findOptionLabel(options, key, fallback)
        for _, opt in ipairs(options) do
            if opt.key == key then return opt.label end
        end
        return fallback or ''
    end

    function H.findMoatLabel(key)
        return C.MOAT_PILL_LABELS[key] or H.findOptionLabel(C.MOAT_FILTERS, key, 'All Moats')
    end

    function H.findYieldModeLabel(key)
        return C.YIELD_PILL_LABELS[key] or H.findOptionLabel(C.YIELD_MODES, key, 'Yield: Auto')
    end

    function H.formatIntComma(v)
        local s = tostring(math.floor(tonumber(v) or 0))
        return (s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', ''))
    end

    function H.formatPlanSummary(plan)
        if type(plan) ~= 'table' or type(plan.entries) ~= 'table' or #plan.entries == 0 then
            return 'No active plan'
        end
        local cnt = plan.recipeCount or #plan.entries
        local prefix = (plan.topN == 'all' or not number(plan.topN))
            and ('All ' .. tostring(cnt))
            or ('Top ' .. tostring(cnt))
        local profTxt = H.formatRoundedMoney(plan.totalProfit, true)
        local spendTxt = H.formatRoundedMoney(plan.totalSpend)
        local roi = number(plan.roiPct) and math.floor(plan.roiPct + 0.5) or 0
        local craftsTxt = H.formatIntComma(plan.totalCrafts or 0) .. 'x'
        local vLoops = tonumber(plan.vendorLoopCount) or 0
        local loopPart = (vLoops > 0)
            and string.format(' · %d Vendor %s', vLoops, (vLoops == 1) and 'Loop' or 'Loops')
            or ''
        return string.format('%s: %s (Spend %s · +%d%% ROI · %s%s)', prefix, profTxt, spendTxt, roi, craftsTxt, loopPart)
    end

    function H.resolvePlanOpts(context)
        local db = (context and context.db) or _G.MerchantMasterDB or {}
        local topN = (context and context.topN ~= nil) and context.topN
            or ((db[dbPrefix .. 'TopN'] ~= nil) and db[dbPrefix .. 'TopN'] or 10)
        local maxCrafts = tonumber((context and context.maxCraftsPerRecipe ~= nil) and context.maxCraftsPerRecipe or db[dbPrefix .. 'MaxCrafts']) or 0
        local budget = tonumber((context and context.budgetCopper ~= nil) and context.budgetCopper or db[dbPrefix .. 'Budget']) or 0
        local topOnly = (context and context.topOnly ~= nil) and (context.topOnly == true) or (db[dbPrefix .. 'TopOnly'] == true)
        return topN, maxCrafts, budget, topOnly
    end

    function H.syncPlanControls(context)
        local v = S.view
        if not v then return end
        local topN, maxCrafts, budget, topOnly = H.resolvePlanOpts(context)
        if v.topNBtn then
            H.setBtnText(v.topNBtn, H.findOptionLabel(C.TOP_N_OPTIONS, topN, 'Plan: Top 10'))
        end
        if v.maxCraftsBtn then
            H.setBtnText(v.maxCraftsBtn, H.findOptionLabel(C.MAX_CRAFTS_OPTIONS, maxCrafts, 'Cap: Max'))
        end
        if v.budgetBtn then
            H.setBtnText(v.budgetBtn, H.findOptionLabel(C.BUDGET_OPTIONS, budget, 'Budget: Unlim'))
        end
        if v.topOnlyBtn then
            local lbl = (topN == 'all' or not number(topN)) and 'Plan Only' or ('Top ' .. tostring(topN) .. ' Only')
            H.setBtnText(v.topOnlyBtn, lbl)
            if v.topOnlyBtn.SetVariant then
                v.topOnlyBtn:SetVariant(topOnly and 'primary' or 'secondary')
            end
            if v.topOnlyBtn.SetActive then
                v.topOnlyBtn:SetActive(topOnly)
            end
        end
        local hasEntries = type(S.activePlan) == 'table' and type(S.activePlan.entries) == 'table' and #S.activePlan.entries > 0
        if v.queuePlanBtn and v.queuePlanBtn.SetEnabled then
            v.queuePlanBtn:SetEnabled(hasEntries)
        end
        if v.planSummaryFs then
            v.planSummaryFs:SetText(H.formatPlanSummary(S.activePlan))
        end
    end

    function H.syncLegacyControls(context)
        local v = S.view
        if not v then return end
        local db = (context and context.db) or _G.MerchantMasterDB or {}
        local leg = H.resolveLegacy(context)
        if v.masterChefBtn then
            local mcTxt = leg.masterChefAuto
                and string.format('Master Chef: Auto (%d/5)', leg.liveMasterChef)
                or string.format('Master Chef: %d/5 (+%d%%)', leg.masterChef, leg.masterChef * 10)
            H.setBtnText(v.masterChefBtn, mcTxt)
        end
        if v.arcaneSalvagerBtn then
            local asOn = H.isArcaneSalvager(context)
            H.setBtnText(v.arcaneSalvagerBtn, asOn and 'Salvager: +20%' or 'Salvager: Off')
            if v.arcaneSalvagerBtn.SetVariant then
                v.arcaneSalvagerBtn:SetVariant(asOn and 'primary' or 'secondary')
            end
            if v.arcaneSalvagerBtn.SetActive then
                v.arcaneSalvagerBtn:SetActive(asOn)
            end
        end
        if v.barteringBtn then
            local brTxt = leg.barteringAuto
                and string.format('Barter: Auto (%d/2)', leg.liveBartering)
                or string.format('Barter: %d/2 (-%d%%)', leg.bartering, leg.bartering * 5)
            H.setBtnText(v.barteringBtn, brTxt)
        end
        if v.honoredBtn then
            local on = (leg.honored == true)
            if v.honoredBtn.SetVariant then
                v.honoredBtn:SetVariant(on and 'primary' or 'secondary')
            end
            if v.honoredBtn.SetActive then
                v.honoredBtn:SetActive(on)
            end
        end
        if v.moatFilterBtn then
            local mf = (context and context.moatFilter) or db[dbPrefix .. 'MoatFilter'] or 'all'
            H.setBtnText(v.moatFilterBtn, H.findMoatLabel(mf))
        end
        if v.yieldModeBtn then
            local ym = (context and context.yieldMode) or db[dbPrefix .. 'YieldMode'] or 'auto'
            H.setBtnText(v.yieldModeBtn, H.findYieldModeLabel(ym))
        end
        if v.onlyProfitableBtn then
            local opOn = H.isOnlyProfitable(context)
            if v.onlyProfitableBtn.SetVariant then
                v.onlyProfitableBtn:SetVariant(opOn and 'primary' or 'secondary')
            end
            if v.onlyProfitableBtn.SetActive then
                v.onlyProfitableBtn:SetActive(opOn)
            end
        end
        if v.showNonDEBtn then
            local nonDEOn = H.isShowNonDE(context)
            if v.showNonDEBtn.SetVariant then
                v.showNonDEBtn:SetVariant(nonDEOn and 'primary' or 'secondary')
            end
            if v.showNonDEBtn.SetActive then
                v.showNonDEBtn:SetActive(nonDEOn)
            end
        end
    end

    function H.triggerRefresh()
        if S.host and S.host.refresh then
            S.host.refresh()
        elseif S.latest then
            vcProvider.Refresh(S.latest)
        end
    end

    function H.updateProfPills(activeProf)
        local v = S.view
        if not v or not v.profPills then return end
        local pal = getThemePalette()
        local isLight = (pal and pal.mode == 'light')
        local cur = activeProf or 'all'
        for _, pill in ipairs(v.profPills) do
            local on = (pill.key == cur)
            pill._active = on
            if type(pill.bg) == 'table' and pill.bg.SetColor then
                if on and pal and pal.accentBlue then
                    pill.bg:SetColor(pal.accentBlue[1], pal.accentBlue[2], pal.accentBlue[3], isLight and 0.14 or 0.18)
                elseif on then
                    pill.bg:SetColor(0.00, 0.569, 1.0, 0.18)
                elseif pal and pal.pillTrack then
                    pill.bg:SetColor(pal.pillTrack[1], pal.pillTrack[2], pal.pillTrack[3], isLight and 0.06 or 0.08)
                else
                    pill.bg:SetColor(0.47, 0.47, 0.50, 0.12)
                end
            end
            if type(pill.fs) == 'table' and pill.fs.SetTextColor then
                local tc = on and ((pal and (pal.textBlue or pal.accentBlue)) or C.FALLBACK.blue)
                    or ((pal and pal.textSecondary) or C.FALLBACK.secondary)
                pill.fs:SetTextColor(tc[1], tc[2], tc[3], 1)
            end
        end
    end

    function H.updateShiftHeader()
        local v = S.view
        if not v then return end
        if v.shiftBadge and v.shiftBadge.SetShown then
            v.shiftBadge:SetShown(S.shiftActive)
        end
        if v.summary and v.summary.ClearAllPoints and v.summary.SetPoint then
            v.summary:ClearAllPoints()
            if v.summaryLeftAnchor then
                v.summary:SetPoint('LEFT', v.summaryLeftAnchor, 'RIGHT', 10, 0)
            end
            if S.shiftActive and v.shiftBadge then
                v.summary:SetPoint('RIGHT', v.shiftBadge, 'LEFT', -8, 0)
            elseif v.filtersButton then
                v.summary:SetPoint('RIGHT', v.filtersButton, 'LEFT', -10, 0)
            elseif v.resetButton then
                v.summary:SetPoint('RIGHT', v.resetButton, 'LEFT', -10, 0)
            end
        end
    end

    function H.styleRowStepper(stepper, qty, pal)
        if not stepper then return end
        local isLight = (pal and pal.mode == 'light')
        local bgCol = (pal and pal.cardAltBg) or (isLight and {0.949, 0.949, 0.969, 1} or {0.204, 0.204, 0.220, 1})
        local stCol = (pal and pal.borderStrong) or (isLight and {0, 0, 0, 0.14} or {1, 1, 1, 0.22})
        local textCol = (pal and pal.text) or (isLight and {0, 0, 0, 1} or {1, 1, 1, 1})
        local mutedCol = (pal and pal.textMuted) or (isLight and {0.369, 0.384, 0.416, 1} or {0.596, 0.596, 0.616, 0.88})
        local greenCol = (pal and pal.accentGreen) or (isLight and {0, 0.478, 0.169, 1} or {0.188, 0.820, 0.345, 1})
        if stepper.bg then
            if stepper.bg.SetColor then stepper.bg:SetColor(bgCol[1], bgCol[2], bgCol[3], 1)
            elseif stepper.bg.SetColorTexture then stepper.bg:SetColorTexture(bgCol[1], bgCol[2], bgCol[3], 1) end
        end
        if stepper.stroke and stepper.stroke.SetColor then
            stepper.stroke:SetColor(stCol[1], stCol[2], stCol[3], stCol[4] or 0.22)
        end
        if stepper.minusBtn and stepper.minusBtn.fs and stepper.minusBtn.fs.SetTextColor then
            stepper.minusBtn.fs:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
        end
        if stepper.plusBtn and stepper.plusBtn.fs and stepper.plusBtn.fs.SetTextColor then
            stepper.plusBtn.fs:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
        end
        if stepper.qtyFs then
            stepper.qtyFs:SetText(tostring(qty))
            if stepper.qtyFs.SetTextColor then
                local qc = (qty > 0) and greenCol or mutedCol
                stepper.qtyFs:SetTextColor(qc[1], qc[2], qc[3], qc[4] or 1)
            end
        end
    end

    function H.ensureRowStepper(r)
        if r.shiftStepper then return r.shiftStepper end
        local T = ns.Theme
        local stepper = CreateFrame('Frame', nil, r)
        stepper:SetSize(76, 20)
        stepper:SetPoint('RIGHT', r, 'RIGHT', -2, 0)
        if r.GetFrameLevel and stepper.SetFrameLevel then
            stepper:SetFrameLevel((r:GetFrameLevel() or 1) + 4)
        end
        if stepper.EnableMouse then stepper:EnableMouse(true) end
        if type(T) == 'table' and type(T.RoundRect) == 'function' and type(T.ASSETS) == 'table' and T.ASSETS.pill_fill then
            stepper.bg = T.RoundRect(stepper, stepper, 'BACKGROUND', 0, 10, 0, 0.204, 0.204, 0.220, 1, T.ASSETS.pill_fill)
            if T.ASSETS.pill_stroke then
                stepper.stroke = T.RoundRect(stepper, stepper, 'BORDER', 1, 10, 0, 1, 1, 1, 0.22, T.ASSETS.pill_stroke)
            end
        else
            stepper.bg = stepper:CreateTexture(nil, 'BACKGROUND')
            stepper.bg:SetAllPoints()
            stepper.bg:SetColorTexture(0.204, 0.204, 0.220, 1)
        end

        local minusBtn = CreateFrame('Button', nil, stepper)
        minusBtn:SetSize(22, 18)
        minusBtn:SetPoint('LEFT', stepper, 'LEFT', 1, 0)
        minusBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        minusBtn.hl = minusBtn:CreateTexture(nil, 'HIGHLIGHT')
        minusBtn.hl:SetAllPoints()
        minusBtn.hl:SetColorTexture(1, 1, 1, 0.08)
        minusBtn.fs = minusBtn:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        minusBtn.fs:SetAllPoints()
        minusBtn.fs:SetJustifyH('CENTER')
        applyFont(minusBtn.fs, 12, 'semibold')
        minusBtn.fs:SetText('-')
        minusBtn:SetScript('OnClick', function(_, button)
            local row = r.data
            if not row or not S.host or type(S.host.adjustRecipeShoppingQty) ~= 'function' then return end
            local cur = H.queuedQtyFor(row)
            local delta = (button == 'RightButton') and -math.max(1, cur) or -1
            S.host.adjustRecipeShoppingQty(row, delta, row.reagentBuyCaps and { buyCaps = row.reagentBuyCaps } or nil)
        end)

        local plusBtn = CreateFrame('Button', nil, stepper)
        plusBtn:SetSize(22, 18)
        plusBtn:SetPoint('RIGHT', stepper, 'RIGHT', -1, 0)
        plusBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        plusBtn.hl = plusBtn:CreateTexture(nil, 'HIGHLIGHT')
        plusBtn.hl:SetAllPoints()
        plusBtn.hl:SetColorTexture(1, 1, 1, 0.08)
        plusBtn.fs = plusBtn:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        plusBtn.fs:SetAllPoints()
        plusBtn.fs:SetJustifyH('CENTER')
        applyFont(plusBtn.fs, 12, 'semibold')
        plusBtn.fs:SetText('+')
        plusBtn:SetScript('OnClick', function(_, button)
            local row = r.data
            if not row or not S.host or type(S.host.adjustRecipeShoppingQty) ~= 'function' then return end
            local delta = (button == 'RightButton') and 5 or 1
            S.host.adjustRecipeShoppingQty(row, delta, row.reagentBuyCaps and { buyCaps = row.reagentBuyCaps } or nil)
        end)

        local qtyFs = stepper:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        qtyFs:SetPoint('LEFT', minusBtn, 'RIGHT', 0, 0)
        qtyFs:SetPoint('RIGHT', plusBtn, 'LEFT', 0, 0)
        qtyFs:SetJustifyH('CENTER')
        qtyFs:SetWordWrap(false)
        applyFont(qtyFs, 11, 'semibold')
        qtyFs:SetText('0')

        stepper.minusBtn = minusBtn
        stepper.plusBtn = plusBtn
        stepper.qtyFs = qtyFs
        stepper:Hide()
        r.shiftStepper = stepper
        return stepper
    end

    function H.paintSelection(r)
        local pal = getThemePalette()
        local isLight = (pal and pal.mode == 'light')
        local hasRow = (r.data ~= nil)
        local isSel = hasRow and r.data.key == S.selectedKey
        if S.shiftActive and hasRow then
            local qty = H.queuedQtyFor(r.data)
            local stepper = H.ensureRowStepper(r)
            H.styleRowStepper(stepper, qty, pal)
            stepper:Show()
            local n = r.cells and #r.cells or 0
            if n > 0 then
                r._shiftHidden = true
                local activeCols = S.tbl and S.tbl.columns
                local colX = S.tbl and S.tbl.colX
                local lastCol = activeCols and activeCols[n]
                local lastX = colX and colX[n]
                local tblRight = (lastCol and lastX) and (lastX + (lastCol.width or 0)) or 0
                local rawRowW = (r.GetWidth and r:GetWidth()) or 0
                local rowW = (rawRowW >= math.max(200, tblRight * 0.5)) and rawRowW or tblRight
                local hidAny = false
                if rowW > 80 and activeCols and colX then
                    local cutoff = rowW - 80
                    for i = 1, n do
                        local c = r.cells[i]
                        local cx = colX[i] or 0
                        local cw = (activeCols[i] and activeCols[i].width) or 0
                        local overlap = (cx + cw > cutoff)
                        if c and c.SetShown then c:SetShown(not overlap) end
                        if overlap then hidAny = true end
                    end
                end
                if not hidAny then
                    for i = math.max(1, n - 1), n do
                        local c = r.cells[i]
                        if c and c.SetShown then c:SetShown(false) end
                    end
                end
            end
            if pal then
                if qty > 0 and pal.accentGreen then
                    r.stripe:SetColorTexture(pal.accentGreen[1], pal.accentGreen[2], pal.accentGreen[3], isLight and 0.10 or 0.14)
                elseif pal.accentBlue then
                    r.stripe:SetColorTexture(pal.accentBlue[1], pal.accentBlue[2], pal.accentBlue[3], isLight and 0.05 or 0.07)
                end
            else
                if qty > 0 then r.stripe:SetColorTexture(0.188, 0.820, 0.345, 0.14)
                else r.stripe:SetColorTexture(0.00, 0.569, 1.0, 0.07) end
            end
        else
            if r.shiftStepper and r.shiftStepper.Hide then r.shiftStepper:Hide() end
            if r._shiftHidden and r.cells then
                r._shiftHidden = false
                for _, c in ipairs(r.cells) do
                    if c and c.SetShown then c:SetShown(true) end
                end
            end
            if pal then
                if isSel and pal.accentBlue then
                    r.stripe:SetColorTexture(pal.accentBlue[1], pal.accentBlue[2], pal.accentBlue[3], 0.16)
                else
                    r.stripe:SetColorTexture(0, 0, 0, 0)
                end
            else
                r.stripe:SetColorTexture(0.00, 0.569, 1.0, isSel and 0.16 or 0)
            end
        end
        if type(r.sep) == 'table' then
            if not r._sepAnchored and type(r.sep.ClearAllPoints) == 'function' and type(r.sep.SetPoint) == 'function' then
                r._sepAnchored = true
                r.sep:ClearAllPoints()
                r.sep:SetPoint('BOTTOMLEFT', r, 'BOTTOMLEFT', 16, 0)
                r.sep:SetPoint('BOTTOMRIGHT', r, 'BOTTOMRIGHT', -16, 0)
            end
            if pal and type(r.sep.SetColorTexture) == 'function' and pal.separator then
                r.sep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.45)
            end
        end
    end

    function H.selectRow(row, button, rowFrame)
        if not row then return end
        if button ~= nil and (not readable(button) or type(button) ~= 'string') then return end
        local shiftValue = shiftKeyDown()
        if shiftValue == nil then return end
        local shiftHeld = shiftValue or S.shiftActive
        if shiftHeld and S.host and type(S.host.adjustRecipeShoppingQty) == 'function' then
            if button == 'LeftButton' and row.outputItemID and type(S.host.tryQuickLookChatLink) == 'function'
                and S.host.tryQuickLookChatLink(row.outputItemID) == true then
                return
            end
            S.selectedKey = row.key
            if S.host.selectRecipe then S.host.selectRecipe(row.outputItemID) end
            local delta = (button == 'RightButton') and -1 or 1
            S.host.adjustRecipeShoppingQty(row, delta, row.reagentBuyCaps and { buyCaps = row.reagentBuyCaps } or nil)
            return
        end
        local leftClick = (button == nil or button == 'LeftButton')
        local openFn = (S.host and S.host.openDeepAnalysis) or (ns.app and ns.app.openDeepAnalysis)
        if button == 'RightButton' and row.recipe and type(openFn) == 'function' then
            openFn({ kind = 'recipe', row = row, recipe = row.recipe }, { tab = spec.tabKey, wasQuickLookOpen = false })
            return
        end
        if leftClick and ns.SuperList and ns.SuperList.GetQuickLookFrame then
            local hud = ns.SuperList.GetQuickLookFrame()
            if shown(hud) and hud.pinned and (not hud.data or hud.data.kind == 'recipe')
                and sameQuickLookTarget(hud.row, row, 'recipe') then
                if ns.SuperList.CloseQuickLook then ns.SuperList.CloseQuickLook() end
                return
            end
        end
        S.selectedKey = row.key
        if S.host and S.host.selectRecipe then S.host.selectRecipe(row.outputItemID) end
        if S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame then
            S.tbl.scrollBox:ForEachFrame(H.paintSelection)
        end
        if S.host and row.craftBreakdown and #row.craftBreakdown > 0
            and not (S.host.hasUnifiedShoppingItems and S.host.hasUnifiedShoppingItems())
            and S.host.showSingleCraftShoppingPreview and S.latest then
            S.host.showSingleCraftShoppingPreview(row, row.numMade or 1, S.latest.counts, S.latest.profMap, S.latest.subCraftMode, S.latest.subCraftOverrides)
        end
        if button ~= 'RightButton' and row.outputItemID and S.host and S.host.searchAH then
            local nm = ns.ItemName and ns.ItemName(row.outputItemID) or nil
            if nm == 'Item #' .. tostring(row.outputItemID) then nm = nil end
            S.host.searchAH(nm, 1, row.outputItemID, { silentNoAH = true, coalesce = true })
        end
        if leftClick and row.recipe and S.host and S.host.openQuickLook then
            S.host.openQuickLook(row, true, rowFrame)
        end
    end

    function H.appendPlanAndWallLines(row)
        local moat = row and row.moat
        if type(moat) == 'table' then
            local safeVal = (row.safeProfitCrafts ~= nil) and row.safeProfitCrafts or moat.safeProfitCrafts
            local safeTxt = (safeVal == math.huge) and 'Inf'
                or (number(safeVal) and (tostring(math.floor(safeVal)) .. 'x') or 'n/a')
            local optTxt = (moat.profitableCrafts == math.huge) and 'Inf'
                or (number(moat.profitableCrafts) and (tostring(math.floor(moat.profitableCrafts)) .. (moat.capped and '+x' or 'x')) or 'n/a')
            local spendVal = (row.totalSpendCap ~= nil) and row.totalSpendCap or moat.totalSpendCap
            local spendTxt = (spendVal == math.huge) and 'Inf'
                or (number(spendVal) and H.formatRoundedMoney(spendVal) or 'n/a')
            GameTooltip:AddLine('Craft Limits', 1, 0.82, 0)
            GameTooltip:AddLine(
                string.format('Safe (0-proc): %s | Optimal (Avg): %s | Max Buy Spend: %s', safeTxt, optTxt, spendTxt),
                0.85, 0.92, 1, true
            )
            if number(row.buyCeiling) then
                local wallPart = number(row.stopWallCost) and (' | Wall: ' .. H.formatRoundedMoney(row.stopWallCost)) or ''
                GameTooltip:AddLine('Buy Up To (Last Profitable Craft): ' .. H.formatRoundedMoney(row.buyCeiling) .. wallPart, 0.85, 0.92, 1, true)
            elseif row.isAllVendor then
                GameTooltip:AddLine('Buy Up To: Unlimited NPC Vendors (Fixed Cost)', 0.30, 0.90, 0.45, true)
            end
            if type(moat.reagents) == 'table' and #moat.reagents > 0 then
                GameTooltip:AddLine(' ')
                GameTooltip:AddLine('Per-Reagent Buy Plan & Price Wall', 1, 0.82, 0)
                for i = 1, #moat.reagents do
                    local rg = moat.reagents[i]
                    if type(rg) == 'table' then
                        local maxQty = number(rg.maxBuyQty) and tostring(math.floor(rg.maxBuyQty + 0.5)) or '0'
                        local minP = H.formatRoundedMoney(rg.minLotPrice or rg.unitCost)
                        local maxP = H.formatRoundedMoney(rg.maxProfitableUnitPrice or rg.unitCost)
                        local avgP = H.formatRoundedMoney(rg.avgBuyUnitPrice or rg.unitCost)
                        local wallPart = number(rg.wallUnitPrice) and (' | wall ' .. H.formatRoundedMoney(rg.wallUnitPrice)) or ''
                        local bePart = number(rg.breakEvenPrice) and (' | break-even <= ' .. H.formatRoundedMoney(rg.breakEvenPrice)) or ''
                        GameTooltip:AddLine(
                            string.format('%s: up to %sx (%s -> %s, avg %s%s%s)', text(rg.name), maxQty, minP, maxP, avgP, wallPart, bePart),
                            0.82, 0.88, 0.94, true
                        )
                    end
                end
            end
        end
        local plan = S.activePlan
        local pe = plan and plan.byKey and row and plan.byKey[row.key] or nil
        if type(pe) == 'table' then
            GameTooltip:AddLine(' ')
            local planLbl = (plan.topN == 'all' or not number(plan.topN))
                and 'All Plan'
                or ('Top ' .. tostring(plan.topN) .. ' Plan')
            GameTooltip:AddLine(
                string.format('Rank #%d in %s: queue %dx -> %s (Spend %s, %s)',
                    tonumber(pe.rank) or 0, planLbl, tonumber(pe.crafts) or 0,
                    H.formatRoundedMoney(pe.profit, true), H.formatRoundedMoney(pe.spend), text(pe.stopReason)),
                0.30, 0.90, 0.45, true
            )
        end
    end

    function H.showRowTooltip(owner, row)
        if not row or not GameTooltip then return end
        GameTooltip:SetOwner(owner, 'ANCHOR_RIGHT')
        local usedNative = false
        if number(row.outputItemID) and row.outputItemID > 0 then
            if GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(row.outputItemID)
                usedNative = true
            elseif GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink('item:' .. tostring(row.outputItemID))
                usedNative = true
            end
        elseif number(row.spellID) and row.spellID > 0 then
            if GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(row.spellID)
                usedNative = true
            elseif GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink('spell:' .. tostring(row.spellID))
                usedNative = true
            end
        end
        if not usedNative then
            GameTooltip:AddLine(text(row.name), 1, 0.82, 0, true)
        else
            GameTooltip:AddLine(' ')
        end

        GameTooltip:AddLine(spec.econHeader, 1, 0.82, 0)
        local leg = row.legacy or {}
        local discParts = {}
        if spec.showMasterChef ~= false and number(leg.bartering) and leg.bartering > 0 then
            discParts[#discParts + 1] = string.format('Bartering %d/2 (-%d%%)', leg.bartering, leg.bartering * 5)
        elseif spec.showMasterChef == false and number(leg.bartering) and leg.bartering > 0 then
            discParts[#discParts + 1] = string.format('Bartering %d/2 (-%d%%)', leg.bartering, leg.bartering * 5)
        end
        if leg.honored then
            discParts[#discParts + 1] = 'Honored (-10%)'
        end
        local costLabel = 'Craft Cost'
        if #discParts > 0 then
            costLabel = costLabel .. ' (' .. table.concat(discParts, ' + ') .. ')'
        end
        GameTooltip:AddDoubleLine(costLabel, H.formatRoundedMoney(row.craftCost) .. H.formatExactCopperNote(row.craftCost), 0.85, 0.85, 0.85, 1, 1, 1)

        local made = number(row.numMade) or 1
        local sellNote = row.isVariableYield
            and string.format('Makes %d-%dx', number(row.minMade) or made, number(row.maxMade) or made)
            or string.format('Makes %d', made)
        if row.yieldSource == 'measured' and number(row.yieldSamples) and row.yieldSamples > 0 then
            sellNote = sellNote .. string.format(', Measured %.2fx (%d casts)', number(row.yieldAvg) or made, row.yieldSamples)
        elseif row.yieldSource == 'min' then
            sellNote = sellNote .. ', Min 1x safe'
        elseif row.isVariableYield then
            sellNote = sellNote .. string.format(', Uniform %.2fx', number(row.yieldUniformAvg) or made)
        end
        if spec.showMasterChef ~= false and row.isCooking and number(row.procChance) and row.procChance > 0 and row.yieldSource ~= 'measured' then
            sellNote = sellNote .. string.format(', Master Chef +%d%%', math.floor(row.procChance * 100 + 0.5))
        end
        local minRev = (spec.mode == 'disenchant') and row.minDE or row.minVendor
        local avgRev = (spec.mode == 'disenchant') and row.avgDE or row.avgVendor
        local maxRev = (spec.mode == 'disenchant') and row.maxDE or row.maxVendor
        local revLabel = (spec.mode == 'disenchant') and 'Disenchant EV (' .. sellNote .. ')' or 'Vendor Sell (' .. sellNote .. ')'
        GameTooltip:AddDoubleLine(revLabel,
            H.formatRoundedMoney(minRev) .. ' / ' .. H.formatRoundedMoney(avgRev) .. H.formatExactCopperNote(avgRev) .. ' / ' .. H.formatRoundedMoney(maxRev),
            0.85, 0.85, 0.85, 1, 1, 1)
        if spec.mode == 'disenchant' and number(row.avgDEAS) then
            GameTooltip:AddDoubleLine('Arcane Salvager EV (+20%)',
                H.formatRoundedMoney(row.avgDEAS) .. H.formatExactCopperNote(row.avgDEAS)
                    .. (row.arcaneSalvager and ' (Active)' or ''),
                0.78, 0.62, 1.0, 1, 1, 1)
        end

        local avgProfitTxt = (number(row.avgProfit) and row.avgProfit > 0 and row.avgProfit < 0.5)
            and '+<1c' or (H.formatRoundedMoney(row.avgProfit, true) .. H.formatExactCopperNote(row.avgProfit))
        local profR, profG, profB = 0.60, 0.60, 0.64
        if number(row.avgProfit) then
            if row.avgProfit > 0 then profR, profG, profB = 0.30, 0.90, 0.45
            elseif row.avgProfit < 0 then profR, profG, profB = 1.00, 0.32, 0.32
            else profR, profG, profB = 0.85, 0.85, 0.85 end
        end
        GameTooltip:AddDoubleLine('Min / Avg / Max Profit',
            H.formatRoundedMoney(row.minProfit, true) .. ' / ' .. avgProfitTxt .. ' / ' .. H.formatRoundedMoney(row.maxProfit, true),
            0.85, 0.85, 0.85, profR, profG, profB)
        GameTooltip:AddDoubleLine('Margin', H.formatMarginCell(row.marginPct), 0.85, 0.85, 0.85, profR, profG, profB)
        if spec.mode == 'disenchant' then
            if row.deEligible == false then
                local reasonTxt = text(row.deReason) ~= '' and text(row.deReason) or 'Not Disenchantable'
                GameTooltip:AddDoubleLine('Disenchant Eligible', 'No (' .. reasonTxt .. ')', 0.85, 0.85, 0.85, 1.00, 0.45, 0.45)
            else
                local learned = number(row.deLearnedCasts) or (row.deBreakdown and number(row.deBreakdown.learnedCasts)) or 0
                if learned > 0 then
                    GameTooltip:AddDoubleLine('DE Learning', string.format('Learned: %d casts', learned), 0.72, 0.86, 0.72, 0.30, 0.90, 0.45)
                end
            end
        end

        if spec.mode == 'disenchant' and type(row.deOutcomes) == 'table' and #row.deOutcomes > 0 then
            GameTooltip:AddLine(' ')
            GameTooltip:AddLine('Disenchant Outcomes (per craft)', 1, 0.82, 0)
            for i = 1, #row.deOutcomes do
                local o = row.deOutcomes[i]
                local pctStr = ns.FormatDEChancePct and ns.FormatDEChancePct(o.matRate) or tostring(math.floor((o.matRate or 0) * 100 + 0.5))
                local qtyStr = ns.FormatDEAmount and ns.FormatDEAmount(o.amountOfMats) or tostring(o.amountOfMats or 1)
                local rangeStr = (o.minAmount == o.maxAmount) and ('[' .. tostring(o.minAmount) .. ']') or ('[' .. tostring(o.minAmount) .. '-' .. tostring(o.maxAmount) .. ']')
                local left = string.format('%s%% %s%s|r x%s |cffffd100%s|r', pctStr, o.colorHex or '|cffffffff', text(o.name), qtyStr, rangeStr)
                local right = H.formatRoundedMoney(o.evNetRounded or o.evNet)
                GameTooltip:AddDoubleLine(left, right, 0.85, 0.85, 0.85, 1, 1, 1)
            end
        end

        local moat = row.moat
        if type(moat) == 'table' then
            GameTooltip:AddLine(' ')
            GameTooltip:AddLine('Buy Moat: ' .. text(moat.label ~= '' and moat.label or moat.short), 1, 0.82, 0)
            if text(moat.reason) ~= '' then
                GameTooltip:AddLine(moat.reason, 0.80, 0.90, 1, true)
            end
            local curTxt = (moat.atCurrentPriceCrafts == math.huge) and 'Inf' or tostring(moat.atCurrentPriceCrafts or 'n/a')
            local totTxt = (moat.profitableCrafts == math.huge) and 'Inf'
                or (moat.profitableCrafts and (tostring(moat.profitableCrafts) .. (moat.capped and '+' or '')) or 'n/a')
            GameTooltip:AddDoubleLine('Crafts (at price / total)', curTxt .. ' / ' .. totTxt, 0.85, 0.85, 0.85, 1, 1, 1)
            GameTooltip:AddDoubleLine('Total Profit Cap', H.formatProfitCapCell(moat.totalProfitCap), 0.85, 0.85, 0.85, 0.30, 0.90, 0.45)
            if type(moat.bottleneck) == 'table' then
                local bn = moat.bottleneck
                GameTooltip:AddDoubleLine('Bottleneck (' .. text(bn.name) .. ')',
                    'Break-even ' .. H.formatRoundedMoney(bn.breakEvenPrice), 0.85, 0.85, 0.85, 1, 0.72, 0.30)
            end
        end

        GameTooltip:AddLine(' ')
        H.appendPlanAndWallLines(row)

        if type(row.craftBreakdown) == 'table' and #row.craftBreakdown > 0 then
            GameTooltip:AddLine(' ')
            GameTooltip:AddLine('Reagent Breakdown', 1, 0.82, 0)
            for i = 1, #row.craftBreakdown do
                local rg = row.craftBreakdown[i]
                if type(rg) == 'table' then
                    local left = string.format('%sx %s (%s)', tostring(rg.qty or 1), text(rg.name), text(rg.source))
                    local right = H.formatRoundedMoney(rg.lineCost)
                    GameTooltip:AddDoubleLine(left, right, 0.82, 0.88, 0.94, 1, 1, 1)
                end
            end
        end

        local prof = (ns.PROF_BY_KEY or {})[row.prof]
        GameTooltip:AddLine(' ')
        GameTooltip:AddDoubleLine('Profession / Skill', (prof and prof.full or text(row.prof)) .. ' ' .. tostring(number(row.requiredSkill) or 'n/a'), 0.85, 0.85, 0.85, 1, 1, 1)
        GameTooltip:AddDoubleLine('Source', text(row.sourceLabel), 0.85, 0.85, 0.85, 0.80, 0.90, 1)
        if number(row.buyCostCopper) then
            GameTooltip:AddDoubleLine('Buy Recipe' .. (row.buyCostEstimated and ' (est. Favor)' or ''), money(row.buyCostCopper), 0.85, 0.85, 0.85, 1, 1, 1)
        end
        if row.wowheadURL then
            GameTooltip:AddLine(row.wowheadURL, 0.6, 0.9, 1, true)
        end
        GameTooltip:AddLine('Click a recipe to pin its 7-day Quick Look. Right-click: Deep Analysis (Buy Caps & Roll Histogram).', 0.6, 0.9, 1, true)
        GameTooltip:AddLine('Hold Shift: quick-add mode (+1 Left-Click, -1 Right-Click, or use -/+ stepper).', 0.4, 1, 0.6, true)
        H.liftAndShowTooltip()
    end

    function H.showMoatTooltip(owner, row)
        if not row or not GameTooltip then return end
        local moat = row.moat
        GameTooltip:SetOwner(owner, 'ANCHOR_RIGHT')
        if GameTooltip.ClearLines then GameTooltip:ClearLines() end
        local title = (text(row.name) ~= '' and row.name or 'Recipe') .. ' — Buy Moat'
        GameTooltip:AddLine(title, 1, 0.82, 0)
        if type(moat) ~= 'table' then
            GameTooltip:AddLine('Buy Moat data unavailable.', 0.8, 0.8, 0.8, true)
            H.liftAndShowTooltip()
            return
        end
        local tierText = text(moat.label) ~= '' and moat.label or text(moat.short)
        GameTooltip:AddDoubleLine('Tier', tierText ~= '' and tierText or 'n/a', 0.85, 0.85, 0.85, 1, 1, 1)
        if text(moat.reason) ~= '' then
            GameTooltip:AddLine(moat.reason, 0.80, 0.90, 1, true)
        end
        GameTooltip:AddLine(' ')
        local atCurTxt = (moat.atCurrentPriceCrafts == math.huge) and 'Inf'
            or (number(moat.atCurrentPriceCrafts) and tostring(moat.atCurrentPriceCrafts) or 'n/a')
        local totTxt = (moat.profitableCrafts == math.huge) and 'Inf'
            or (number(moat.profitableCrafts) and (tostring(moat.profitableCrafts) .. (moat.capped and '+' or '')) or 'n/a')
        GameTooltip:AddDoubleLine('Crafts at current price', atCurTxt, 0.85, 0.85, 0.85, 1, 1, 1)
        GameTooltip:AddDoubleLine('Total profitable crafts', totTxt, 0.85, 0.85, 0.85, 1, 1, 1)
        GameTooltip:AddDoubleLine('Total profit cap', H.formatProfitCapCell(moat.totalProfitCap), 0.85, 0.85, 0.85, 0.30, 0.90, 0.45)
        GameTooltip:AddDoubleLine('Depth source', C.DEPTH_LABELS[moat.depthSource] or text(moat.depthSource), 0.85, 0.85, 0.85, 0.82, 0.88, 0.94)

        if type(moat.bottleneck) == 'table' then
            local bn = moat.bottleneck
            local bnWhy = (moat.bottleneckReason == 'price_wall') and 'Price wall' or 'AH supply'
            GameTooltip:AddLine(' ')
            GameTooltip:AddDoubleLine('Bottleneck reagent', text(bn.name) .. ' (' .. bnWhy .. ')', 0.85, 0.85, 0.85, 1, 0.72, 0.30)
            GameTooltip:AddDoubleLine('Break-even ceiling',
                H.formatRoundedMoney(bn.breakEvenPrice) .. ' (now ' .. H.formatRoundedMoney(bn.unitCost) .. ')',
                0.85, 0.85, 0.85, 1, 1, 1)
        end

        GameTooltip:AddLine(' ')
        GameTooltip:AddDoubleLine('24h / 7d Stability', C.STABILITY_LABELS[moat.stability] or text(moat.stability), 0.85, 0.85, 0.85, 1, 1, 1)
        if number(moat.observedHours24h) and moat.observedHours24h > 0 then
            GameTooltip:AddDoubleLine('24h profitable hours',
                string.format('%d / %d hours', number(moat.profitableHours24h) or 0, moat.observedHours24h),
                0.85, 0.85, 0.85, 0.82, 0.88, 0.94)
        end
        if number(moat.baselineCraftCost) then
            GameTooltip:AddDoubleLine('Baseline craft cost', H.formatRoundedMoney(moat.baselineCraftCost), 0.85, 0.85, 0.85, 0.82, 0.88, 0.94)
        end

        GameTooltip:AddLine(' ')
        H.appendPlanAndWallLines(row)
        H.liftAndShowTooltip()
    end

    function H.styleCellPill(cell, kind, pal)
        local pill = cell.pillBg
        if not pill then return end
        if not kind then
            if cell._pillKind then pill:SetShown(false) end
            cell._pillKind = nil
            return
        end
        if cell._pillKind == kind and cell._pillPalette == pal then return end
        cell._pillKind, cell._pillPalette = kind, pal
        local bgCol
        local isLight = (pal and pal.mode == 'light')
        if pal then
            if kind == 'pos' and pal.accentGreen then
                bgCol = {pal.accentGreen[1], pal.accentGreen[2], pal.accentGreen[3], isLight and 0.11 or 0.14}
            elseif kind == 'blue' and pal.accentBlue then
                bgCol = {pal.accentBlue[1], pal.accentBlue[2], pal.accentBlue[3], isLight and 0.11 or 0.14}
            elseif kind == 'hot' and pal.accentOrange then
                bgCol = {pal.accentOrange[1], pal.accentOrange[2], pal.accentOrange[3], isLight and 0.11 or 0.12}
            elseif kind == 'warn' and pal.accentOrange then
                bgCol = {pal.accentOrange[1], pal.accentOrange[2], pal.accentOrange[3], isLight and 0.10 or 0.12}
            elseif pal.pillTrack then
                bgCol = {pal.pillTrack[1], pal.pillTrack[2], pal.pillTrack[3], 0.12}
            end
        else
            if kind == 'pos' then bgCol = {0.20, 0.78, 0.35, 0.14}
            elseif kind == 'blue' then bgCol = {0.04, 0.52, 1.0, 0.14}
            elseif kind == 'hot' then bgCol = {1.0, 0.55, 0.16, 0.12}
            elseif kind == 'warn' then bgCol = {1.0, 0.65, 0.16, 0.12}
            else bgCol = {0.47, 0.47, 0.50, 0.12} end
        end
        if bgCol and cell.pillBg.SetColor then
            cell.pillBg:SetColor(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.16)
        end
        if cell.pillBg.SetShown then cell.pillBg:SetShown(true) end
    end

    function H.syncCellGroup(group)
        local cells, byKey = group.cells, group.cellsByKey
        local active = {}
        for i = #cells, #S.tbl.columns + 1, -1 do cells[i] = nil end
        for i, col in ipairs(S.tbl.columns) do
            local cell = byKey[col.key]
            cells[i] = cell
            active[col.key] = true
            cell:Show()
        end
        for key, cell in pairs(byKey) do
            if not active[key] then cell:Hide() end
        end
        group._colEpoch = S.colEpoch
        group._layoutEpoch = nil
    end

    function H.syncRowCells(r)
        H.syncCellGroup(r.cellGroup)
        r._colEpoch = S.colEpoch
        r._layoutEpoch = nil
    end

    function H.prepareCells()
        local group = CreateFrame('Frame', nil, S.view)
        group.cells = {}
        group.cellsByKey = {}
        group:Hide()
        local T = ns.Theme
        local pal = getThemePalette()
        for _, col in ipairs(C.VENDOR_COLUMNS) do
            local cell = CreateFrame('Button', nil, group)
            cell:SetHeight((S.host and S.host.rowHeight) or 22)
            cell.fs = cell:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
            cell.fs:SetPoint('LEFT', 2, 0)
            cell.fs:SetPoint('RIGHT', -2, 0)
            cell.fs:SetJustifyH(col.align)
            cell.fs:SetWordWrap(false)
            applyFont(cell.fs, 11, 'regular')
            if T and T.AutoThemeText then T.AutoThemeText(cell.fs) end
            if pal and pal.text then
                local color = (col.key == 'requiredSkill' or col.key == 'sourceLabel') and (pal.textSecondary or pal.text) or pal.text
                cell._textColor = color
                cell.fs:SetTextColor(color[1], color[2], color[3], 1)
            end
            if (col.key == 'moatScore' or col.key == 'wowheadURL') and type(T) == 'table'
                and type(T.RoundRect) == 'function' and type(T.ASSETS) == 'table' and T.ASSETS.pill_fill then
                cell.pillBg = T.RoundRect(cell, cell, 'BACKGROUND', 0, 6, 2, 0.5, 0.5, 0.5, 0.16, T.ASSETS.pill_fill)
                cell.pillBg:SetShown(false)
            end
            cell:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
            cell:SetScript('OnClick', function(self, button)
                if not readable(button) or type(button) ~= 'string' then return end
                local grp = self:GetParent()
                local row = grp and grp.data
                local rowFrame = grp and grp.GetParent and grp:GetParent() or grp
                local shiftValue = shiftKeyDown()
                if shiftValue == nil then return end
                local shiftHeld = shiftValue or S.shiftActive
                if col.key == 'wowheadURL' and button == 'LeftButton' and not shiftHeld then
                    if row and row.wowheadURL and S.host and S.host.openWowheadPopup then
                        local ca = {}
                        for k, v in pairs(row.craftAbility or {}) do ca[k] = v end
                        ca.wowheadURL = row.wowheadURL
                        S.host.openWowheadPopup(ca, row.name, row.icon)
                    end
                else
                    H.selectRow(row, button, rowFrame)
                end
            end)
            if col.key == 'name' then
                cell:SetScript('OnEnter', function(self) H.showRowTooltip(self, self:GetParent().data) end)
                cell:SetScript('OnLeave', leaveTooltip)
                local circleTex = type(T) == 'table' and type(T.ASSETS) == 'table' and T.ASSETS.circle_fill
                if circleTex and type(cell.CreateTexture) == 'function' then
                    cell.glyphBg = cell:CreateTexture(nil, 'BACKGROUND', nil, 1)
                    if type(cell.glyphBg) == 'table' then
                        cell.glyphBg:SetSize(20, 20)
                        cell.glyphBg:SetPoint('LEFT', 0, 0)
                        cell.glyphBg:SetTexture(circleTex)
                        if type(cell.glyphBg.SetVertexColor) == 'function' then
                            cell.glyphBg:SetVertexColor(0.463, 0.463, 0.502, 0.24)
                        end
                    end
                end
                cell.icon = cell:CreateTexture(nil, 'ARTWORK')
                cell.icon:SetSize(16, 16)
                if type(cell.glyphBg) == 'table' then
                    cell.icon:SetPoint('CENTER', cell.glyphBg, 'CENTER', 0, 0)
                else
                    cell.icon:SetPoint('LEFT', 0, 0)
                end
                if cell.icon.SetTexCoord then cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
                cell.fs:SetPoint('LEFT', cell.glyphBg or cell.icon, 'RIGHT', 5, 0)
            elseif col.key == 'moatScore' or col.key == 'buyCeiling' or col.key == 'profitableCrafts' then
                cell:SetScript('OnEnter', function(self) H.showMoatTooltip(self, self:GetParent().data) end)
                cell:SetScript('OnLeave', leaveTooltip)
            end
            group.cellsByKey[col.key] = cell
        end
        H.syncCellGroup(group)
        if S.tbl and S.tbl.layoutRow then S.tbl.layoutRow(group) end
        S.prepared[#S.prepared + 1] = group
    end

    function H.cellValues(data)
        local pal = getThemePalette()
        local palMode = pal and pal.mode
        local palSkin = pal and pal.skin
        local T = ns.Theme
        local priceMode = (T and T.GetPriceDisplayMode and T.GetPriceDisplayMode()) or 'compact'
        local qty = H.queuedQtyFor(data)
        local cd = data.cdInfo
        local ca = type(data.craftAbility) == 'table' and data.craftAbility or nil
        local moat = type(data.moat) == 'table' and data.moat or nil
        local moatShort = moat and moat.short
        local planEntry = S.activePlan and S.activePlan.byKey and S.activePlan.byKey[data.key] or nil
        local planCrafts = planEntry and planEntry.crafts or nil
        local planProfit = planEntry and planEntry.profit or nil
        local greenHex = (pal and pal.hexPositive) or colorHex(pal and pal.accentGreen, '30d158')
        local yieldBadge = ''
        if data.isVariableYield and number(data.minMade) and number(data.maxMade) and data.maxMade > data.minMade then
            local mutedHex = (pal and pal.hexMuted) or colorHex(pal and pal.textMuted, '98989d')
            if data.yieldSource == 'measured' then
                local mAvg = data.yieldAvg or data.yieldMeasuredAvg or 0
                yieldBadge = string.format(' |cff%s[%d-%dx %.2fx (%d)]|r', greenHex, data.minMade, data.maxMade, mAvg, tonumber(data.yieldSamples) or 0)
            else
                yieldBadge = string.format(' |cff%s[%d-%dx]|r', mutedHex, data.minMade, data.maxMade)
            end
        end
        local entry = S.cellValueCache[data]
        if entry
            and entry.pal == pal
            and entry.palMode == palMode
            and entry.palSkin == palSkin
            and entry.priceMode == priceMode
            and entry.epoch == S.cellCacheEpoch
            and entry.craftCost == data.craftCost
            and entry.minVendor == data.minVendor
            and entry.avgVendor == data.avgVendor
            and entry.maxVendor == data.maxVendor
            and entry.minDE == data.minDE
            and entry.avgDE == data.avgDE
            and entry.avgDEAS == data.avgDEAS
            and entry.maxDE == data.maxDE
            and entry.deSummary == data.deSummary
            and entry.avgProfit == data.avgProfit
            and entry.minProfit == data.minProfit
            and entry.yieldSource == data.yieldSource
            and entry.yieldSamples == data.yieldSamples
            and entry.yieldAvg == data.yieldAvg
            and entry.minMade == data.minMade
            and entry.maxMade == data.maxMade
            and entry.marginPct == data.marginPct
            and entry.moatShort == moatShort
            and entry.profitableCrafts == data.profitableCrafts
            and entry.buyCeiling == data.buyCeiling
            and entry.isAllVendor == data.isAllVendor
            and entry.totalProfitCap == data.totalProfitCap
            and entry.planCrafts == planCrafts
            and entry.planProfit == planProfit
            and entry.buyCost == data.buyCostCopper
            and entry.known == data.known
            and entry.deEligible == data.deEligible
            and entry.deReason == data.deReason
            and entry.dePartialPrice == data.dePartialPrice then
            if entry.shift ~= S.shiftActive or entry.qty ~= qty then
                local nameTxt = text(data.name) .. yieldBadge
                if not S.shiftActive and qty > 0 then
                    nameTxt = '|cff' .. greenHex .. '[' .. tostring(qty) .. 'x]|r ' .. nameTxt
                end
                entry.values.name = nameTxt
                entry.shift = S.shiftActive
                entry.qty = qty
            end
            return entry.values
        end

        local prof = (ns.PROF_BY_KEY or {})[data.prof]
        local level = (prof and (prof.short or prof.label) or text(data.prof):sub(1, 3)) .. ' ' .. tostring(number(data.requiredSkill) or 'n/a')
        local nameTxt = text(data.name) .. yieldBadge
        if not S.shiftActive and qty > 0 then
            nameTxt = '|cff' .. greenHex .. '[' .. tostring(qty) .. 'x]|r ' .. nameTxt
        end
        local knownText = 'No'
        if data.known then
            if ca and ca.knownOnActive == false and type(ca.knownAltNames) == 'table' and #ca.knownAltNames > 0 then
                knownText = 'Alt'
            else
                knownText = 'Yes'
            end
        end

        local maxCraftsTxt = nilFallback
        if data.profitableCrafts == math.huge then
            maxCraftsTxt = 'Inf'
        elseif number(data.profitableCrafts) then
            maxCraftsTxt = tostring(math.floor(data.profitableCrafts)) .. ((moat and moat.capped) and '+x' or 'x')
        end
        local buyCeilTxt = nilFallback
        if data.isAllVendor then
            buyCeilTxt = 'Vendor'
        elseif number(data.buyCeiling) then
            buyCeilTxt = H.formatRoundedMoney(data.buyCeiling)
        end
        local capVal = (planEntry and number(planEntry.profit)) and planEntry.profit or data.totalProfitCap
        local isNonDE = (spec.mode == 'disenchant' and data.deEligible == false)

        local v = (entry and entry.values) or {}
        v.name = nameTxt
        v.knownSort = knownText
        v.cdSort = H.formatCooldown(cd)
        v.craftCost = H.formatRoundedMoney(data.craftCost)
        v.minVendor = H.formatRoundedMoney(data.minVendor)
        v.avgVendor = H.formatRoundedMoney(data.avgVendor)
        v.maxVendor = H.formatRoundedMoney(data.maxVendor)
        v.deSummary = isNonDE and 'Non-DE' or ((type(data.deSummary) == 'string' and data.deSummary ~= '') and data.deSummary or nilFallback)
        v.minDE = isNonDE and '-' or H.formatRoundedMoney(data.minDE)
        v.avgDE = isNonDE and '-' or H.formatRoundedMoney(data.avgDE)
        v.avgDEAS = isNonDE and '-' or H.formatRoundedMoney(data.avgDEAS)
        v.maxDE = isNonDE and '-' or H.formatRoundedMoney(data.maxDE)
        v.avgProfit = isNonDE and '-' or H.formatAvgProfitCell(data.avgProfit, pal)
        v.marginPct = isNonDE and '-' or H.formatMarginCell(data.marginPct)
        v.moatScore = (not isNonDE and type(moatShort) == 'string' and moatShort ~= '') and moatShort or nilFallback
        v.profitableCrafts = isNonDE and '-' or maxCraftsTxt
        v.buyCeiling = isNonDE and '-' or buyCeilTxt
        v.totalProfitCap = isNonDE and '-' or H.formatProfitCapCell(capVal)
        v.requiredSkill = level
        v.sourceLabel = text(data.sourceLabel)
        v.buyCostCopper = money(data.buyCostCopper) .. (data.buyCostEstimated and '*' or '')
        v.wowheadURL = data.wowheadURL and 'WH' or nilFallback

        if not entry then
            entry = { values = v }
            S.cellValueCache[data] = entry
        end
        entry.pal = pal
        entry.palMode = palMode
        entry.palSkin = palSkin
        entry.priceMode = priceMode
        entry.epoch = S.cellCacheEpoch
        entry.craftCost = data.craftCost
        entry.minVendor = data.minVendor
        entry.avgVendor = data.avgVendor
        entry.maxVendor = data.maxVendor
        entry.minDE = data.minDE
        entry.avgDE = data.avgDE
        entry.avgDEAS = data.avgDEAS
        entry.maxDE = data.maxDE
        entry.deSummary = data.deSummary
        entry.avgProfit = data.avgProfit
        entry.minProfit = data.minProfit
        entry.yieldSource = data.yieldSource
        entry.yieldSamples = data.yieldSamples
        entry.yieldAvg = data.yieldAvg
        entry.minMade = data.minMade
        entry.maxMade = data.maxMade
        entry.marginPct = data.marginPct
        entry.moatShort = moatShort
        entry.profitableCrafts = data.profitableCrafts
        entry.buyCeiling = data.buyCeiling
        entry.isAllVendor = data.isAllVendor
        entry.totalProfitCap = data.totalProfitCap
        entry.planCrafts = planCrafts
        entry.planProfit = planProfit
        entry.buyCost = data.buyCostCopper
        entry.known = data.known
        entry.deEligible = data.deEligible
        entry.deReason = data.deReason
        entry.dePartialPrice = data.dePartialPrice
        entry.shift = S.shiftActive
        entry.qty = qty
        return v
    end

    function H.paintRowCells(r, values, pal)
        local textCol = (pal and pal.text) or C.FALLBACK.text
        local mutedCol = (pal and pal.textMuted) or C.FALLBACK.muted
        local secCol = (pal and pal.textSecondary) or C.FALLBACK.secondary
        local greenCol = (pal and pal.accentGreen) or C.FALLBACK.green
        local blueCol = (pal and (pal.textBlue or pal.accentBlue)) or C.FALLBACK.blue
        local orangeCol = (pal and pal.accentOrange) or C.FALLBACK.orange
        local isLight = (pal and pal.mode == 'light')
        local redCol = isLight and C.FALLBACK.lightRed or ((pal and pal.accentRed) or C.FALLBACK.red)
        local data = r.data
        for i, cell in ipairs(r.cells) do
            local key = S.tbl.columns[i].key
            local txt = values[key]
            if cell._lastText ~= txt or cell._textPalette ~= pal then
                cell._lastText, cell._textPalette = txt, pal
                if cell.fs._mmThemedText then
                    cell.fs:SetText(txt, true)
                else
                    cell.fs:SetText(txt)
                end
            end
            local color, kind = textCol, nil
            if key == 'name' then
                if txt == 'n/a' then color = mutedCol end
                if cell._icon ~= data.icon then
                    cell._icon = data.icon
                    cell.icon:SetTexture(data.icon)
                end
                local glyphAlpha = isLight and 0.12 or 0.24
                if cell.glyphBg and cell._glyphAlpha ~= glyphAlpha then
                    cell._glyphAlpha = glyphAlpha
                    cell.glyphBg:SetVertexColor(0.463, 0.463, 0.502, glyphAlpha)
                end
            elseif key == 'knownSort' then
                color = data.known and greenCol or redCol
            elseif key == 'cdSort' then
                if txt == 'R' then color = greenCol
                elseif txt ~= '-' then
                    color = (data.cdInfo and data.cdInfo.onCooldown) and redCol or secCol
                end
            elseif key == 'minVendor' or key == 'minDE' then
                if txt == 'n/a' or txt == '-' then
                    color = mutedCol
                elseif number(data.minProfit) and data.minProfit < 0 then
                    color = redCol
                end
            elseif key == 'deSummary' then
                color = (txt == 'n/a' or txt == '-' or txt == 'Non-DE' or data.deEligible == false) and mutedCol or secCol
            elseif key == 'avgProfit' or key == 'marginPct' then
                local val = (key == 'avgProfit') and data.avgProfit or data.marginPct
                if txt == 'n/a' or txt == '-' or not number(val) then
                    color = mutedCol
                elseif val > 0 then
                    color = greenCol
                elseif val < 0 then
                    color = redCol
                else
                    color = secCol
                end
            elseif key == 'profitableCrafts' then
                local pe = S.activePlan and S.activePlan.byKey and S.activePlan.byKey[data.key] or nil
                if txt == 'n/a' or txt == '-' then
                    color = mutedCol
                elseif data.profitableCrafts == math.huge then
                    color = greenCol
                elseif pe and number(pe.crafts) and number(data.profitableCrafts) and pe.crafts ~= data.profitableCrafts then
                    color = blueCol
                else
                    color = textCol
                end
            elseif key == 'buyCeiling' then
                if txt == 'n/a' or txt == '-' then
                    color = mutedCol
                elseif data.isAllVendor then
                    color = greenCol
                else
                    color = textCol
                end
            elseif key == 'totalProfitCap' then
                if txt == 'n/a' or txt == '-' then color = mutedCol
                else color = greenCol end
            elseif key == 'moatScore' then
                local bKind = (data.moat and data.moat.badgeKind) or 'neutral'
                if txt == 'n/a' or txt == '-' or bKind == 'neutral' then
                    color, kind = mutedCol, 'neutral'
                elseif bKind == 'pos' then
                    color, kind = greenCol, 'pos'
                elseif bKind == 'blue' then
                    color, kind = blueCol, 'blue'
                elseif bKind == 'hot' then
                    color, kind = orangeCol, 'hot'
                elseif bKind == 'warn' then
                    color, kind = orangeCol, 'warn'
                else
                    color, kind = mutedCol, 'neutral'
                end
            elseif key == 'wowheadURL' then
                color, kind = (txt == 'n/a' or txt == '-') and mutedCol or secCol, 'neutral'
            elseif key == 'requiredSkill' or key == 'sourceLabel' then
                color = secCol
            elseif txt == 'n/a' or txt == '-' then
                color = mutedCol
            end
            if cell._textColor ~= color then
                cell._textColor = color
                cell.fs:SetTextColor(color[1], color[2], color[3], 1)
            end
            if cell.pillBg then H.styleCellPill(cell, kind, pal) end
        end
    end

    function H.bindRow(r, data)
        if not r.cells then
            if S.host and S.host.applyRowHighlight then S.host.applyRowHighlight(r) end
            if #S.prepared == 0 then H.prepareCells() end
            r.cellGroup = table.remove(S.prepared)
            r.cellGroup:SetParent(r)
            r.cellGroup:SetAllPoints(r)
            r.cellGroup:Show()
            r.cells = r.cellGroup.cells
            r._colEpoch = r.cellGroup._colEpoch
            r._layoutEpoch = r.cellGroup._layoutEpoch
            r:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
            r:SetScript('OnHide', function(self)
                hideRowTooltip(self)
                if self.shiftStepper and self.shiftStepper.Hide then self.shiftStepper:Hide() end
                if not shown(self) then
                    self.data = nil
                    if self.cellGroup then self.cellGroup.data = nil end
                end
            end)
            r:SetScript('OnClick', function(self, button) H.selectRow(self.data, button, self) end)
        end
        if r._colEpoch ~= S.colEpoch then H.syncRowCells(r) end
        if S.tbl and S.tbl.layoutRow and r._layoutEpoch ~= S.tbl._layoutEpoch then S.tbl.layoutRow(r) end
        hideRowTooltip(r)
        r.data = data
        r.cellGroup.data = data
        local values = (S.transientCells and S.transientCells[data]) or H.cellValues(data)
        H.paintRowCells(r, values, getThemePalette())
        H.paintSelection(r)
    end

    function H.rebindStaleRows()
        if not S.tbl or not S.tbl.scrollBox or not S.tbl.scrollBox.ForEachFrame then return end
        local needsRebind = false
        S.tbl.scrollBox:ForEachFrame(function(r)
            if r.cells and r.data == nil and shown(r) then
                local elData = type(r.GetElementData) == 'function' and r:GetElementData() or nil
                if elData then
                    H.bindRow(r, elData)
                else
                    needsRebind = true
                end
            end
        end)
        if needsRebind then
            if S.tbl.scrollBox.ReinitializeFrames then
                S.tbl.scrollBox:ReinitializeFrames()
            elseif S.boundResult then
                S.tbl.setRows(S.boundResult)
            elseif S.tbl.scrollBox.FullUpdate then
                S.tbl.scrollBox:FullUpdate()
            end
        end
    end

    function H.clearInsetChrome()
        local t = S.tbl
        if not t or type(t.inset) ~= 'table' then return end
        if type(t.inset._mmCard) == 'table' then
            for _, k in ipairs({'fill', 'border', 'stroke'}) do
                local obj = t.inset._mmCard[k]
                if type(obj) == 'table' then
                    if type(obj.SetColor) == 'function' then obj:SetColor(0, 0, 0, 0) end
                    if type(obj.SetAlpha) == 'function' then obj:SetAlpha(0) end
                    if type(obj.SetShown) == 'function' then obj:SetShown(false) end
                end
            end
        end
        if type(t.inset.GetRegions) == 'function' then
            for _, r in ipairs({t.inset:GetRegions()}) do
                if type(r) == 'table' and r.GetObjectType and r:GetObjectType() == 'Texture' and type(r.SetAlpha) == 'function' then
                    r:SetAlpha(0)
                end
            end
        end
        for _, k in ipairs({'NineSlice', 'Bg', 'TopLeftCorner', 'TopRightCorner', 'BotLeftCorner', 'BotRightCorner', 'TopBorder', 'BottomBorder', 'LeftBorder', 'RightBorder'}) do
            if type(t.inset[k]) == 'table' and type(t.inset[k].SetAlpha) == 'function' then
                t.inset[k]:SetAlpha(0)
            end
        end
    end

    function H.styleHeaders()
        local t = S.tbl
        if not t then return end
        local T = ns.Theme
        local pal = getThemePalette()
        local st = S.host and S.host.getSort and S.host.getSort() or nil
        local tStyle = (T and T.IsCustomSkin and T.IsCustomSkin() and T.GetTableStyle and T.GetTableStyle()) or 'standard'
        local styled = (tStyle == 't5_ruled' or tStyle == 't5_well' or tStyle == 't3_strips')
        local activeHex = colorHex(pal and (pal.textBlue or pal.accentBlue), '0091ff')
        local mutedCol = styled and (pal and (pal.gold or pal.text)) or (pal and pal.textMuted) or {0.60, 0.60, 0.65}
        local activeCol = (pal and (pal.textBlue or pal.accentBlue)) or C.FALLBACK.blue
        local chevPath = (T and T.ASSETS and T.ASSETS.icon_chevron_down) or (uiCache.appleRoot .. 'icon_chevron_down')
        if type(t.headerBar) == 'table' and type(t.headerBar.GetRegions) == 'function' then
            for _, r in ipairs({t.headerBar:GetRegions()}) do
                if type(r) == 'table' and r.GetObjectType and r:GetObjectType() == 'Texture' and r.SetColorTexture then
                    if styled then
                        r:SetColorTexture(0, 0, 0, 0)
                    elseif pal and pal.separator then
                        r:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.65)
                    end
                end
            end
        end
        for i, col in ipairs(t.columns or {}) do
            local btn = t.headerBtns and t.headerBtns[i]
            if type(btn) == 'table' then
                if btn.SetHeight then btn:SetHeight(26) end
                if type(btn.sep) == 'table' and type(btn.sep.Hide) == 'function' then btn.sep:Hide() end
                if type(btn.bg) == 'table' and btn.bg.SetColorTexture then btn.bg:SetColorTexture(0, 0, 0, 0) end
                applyFont(btn.fs, styled and 10 or 11, styled and 'semibold' or 'regular')
                local lbl = col.label or ''
                local dispLbl = styled and string.upper(lbl) or lbl
                if st and col.key == st.col then
                    local arrow = st.asc
                        and (' |T' .. chevPath .. ':9:9:0:0:16:16:0:16:16:0|t')
                        or (' |T' .. chevPath .. ':9:9:0:0:16:16:0:16:0:16|t')
                    btn.fs:SetText('|cff' .. activeHex .. dispLbl .. '|r' .. arrow)
                    if btn.fs.SetTextColor then btn.fs:SetTextColor(activeCol[1], activeCol[2], activeCol[3], 1) end
                else
                    btn.fs:SetText(dispLbl)
                    if btn.fs.SetTextColor then btn.fs:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1) end
                end
            end
        end
        if t.paintTableChrome then t.paintTableChrome() end
    end

    function H.refreshColumnPopover()
        local pop = S.view and S.view.colSettingsPopover
        if not pop or not pop._built then return end
        local pal = getThemePalette()
        local cfg = H.normalizeColumnConfig(H.getColumnDB())
        local textCol = (pal and pal.text) or {1, 1, 1, 1}
        local mutedCol = (pal and pal.textMuted) or {0.6, 0.6, 0.6, 1}
        local secCol = (pal and pal.textSecondary) or {0.82, 0.82, 0.85, 1}
        local blueCol = (pal and pal.accentBlue) or {0, 0.569, 1, 1}
        local trackCol = (pal and pal.pillTrack) or {0.47, 0.47, 0.50, 0.16}
        local total = #cfg.order
        for i, key in ipairs(cfg.order) do
            local row = pop.rows[i]
            local def = C.VENDOR_BY_KEY[key]
            if row and def then
                row._colKey = key
                local isName = (key == 'name')
                local vis = isName or (cfg.hidden[key] ~= true)
                row.label:SetText(isName and (def.label .. ' (Always Shown)') or def.label)
                local lc = vis and textCol or mutedCol
                if row.label.SetTextColor then row.label:SetTextColor(lc[1], lc[2], lc[3], lc[4] or 1) end
                local bgCol = vis and blueCol or trackCol
                local bgAlpha = isName and 0.55 or (bgCol[4] or 1)
                if type(row.checkBtn.bg) == 'table' then
                    if row.checkBtn.bg.SetColor then row.checkBtn.bg:SetColor(bgCol[1], bgCol[2], bgCol[3], bgAlpha)
                    elseif row.checkBtn.bg.SetColorTexture then row.checkBtn.bg:SetColorTexture(bgCol[1], bgCol[2], bgCol[3], bgAlpha) end
                end
                if type(row.checkBtn.tick) == 'table' then
                    if row.checkBtn.tick.SetShown then row.checkBtn.tick:SetShown(vis) end
                    if row.checkBtn.tick.SetVertexColor then row.checkBtn.tick:SetVertexColor(1, 1, 1, isName and 0.85 or 1) end
                end
                local canUp = (not isName and i > 2)
                local canDown = (not isName and i < total)
                if row.upBtn.SetEnabled then row.upBtn:SetEnabled(canUp) end
                if row.downBtn.SetEnabled then row.downBtn:SetEnabled(canDown) end
                if type(row.upBtn.icon) == 'table' and row.upBtn.icon.SetVertexColor then
                    local uc = canUp and secCol or mutedCol
                    row.upBtn.icon:SetVertexColor(uc[1], uc[2], uc[3], canUp and (uc[4] or 1) or 0.35)
                end
                if type(row.downBtn.icon) == 'table' and row.downBtn.icon.SetVertexColor then
                    local dc = canDown and secCol or mutedCol
                    row.downBtn.icon:SetVertexColor(dc[1], dc[2], dc[3], canDown and (dc[4] or 1) or 0.35)
                end
            end
        end
    end

    function H.themeColumnSettingsPopover()
        local pop = S.view and S.view.colSettingsPopover
        if not pop or not pop._built then return end
        local pal = getThemePalette()
        if type(pop.surface) == 'table' and pop.surface.UpdateTheme then
            pop.surface:UpdateTheme(pal and pal.cardBg or 'cardBg', pal and (pal.borderStrong or pal.border) or 'borderStrong')
        end
        if type(pop.title) == 'table' and pop.title.SetTextColor and pal and pal.text then
            pop.title:SetTextColor(pal.text[1], pal.text[2], pal.text[3], 1)
        end
        if type(pop.sep) == 'table' and pop.sep.SetColorTexture and pal and pal.separator then
            pop.sep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.7)
        end
        H.refreshColumnPopover()
    end

    function H.applyColumnConfig(db)
        local activeCols, cfg = H.getActiveColumnDefs(db or H.getColumnDB())
        S.appliedColSig = fingerprint(cfg)
        local t = S.tbl
        if not t then return end
        t.columns = t.columns or {}
        for k in pairs(t.columns) do t.columns[k] = nil end
        t.baseWidths = t.baseWidths or {}
        for k in pairs(t.baseWidths) do t.baseWidths[k] = nil end
        t.growWeights = t.growWeights or {}
        for k in pairs(t.growWeights) do t.growWeights[k] = nil end
        t.colX = t.colX or {}
        for k in pairs(t.colX) do t.colX[k] = nil end
        t.headerBtns = t.headerBtns or {}
        for k in pairs(t.headerBtns) do t.headerBtns[k] = nil end
        local activeBtns = {}
        local x = 4
        for i, col in ipairs(activeCols) do
            t.columns[i] = col
            t.baseWidths[i] = col.width
            t.growWeights[i] = col.grow
            t.colX[i] = x
            x = x + col.width + 5
            local btn = t.headerBtnsByKey and t.headerBtnsByKey[col.key]
            t.headerBtns[i] = btn
            if btn then
                activeBtns[btn] = true
                if btn.Show then btn:Show() end
            end
        end
        for _, btn in pairs(t.headerBtnsByKey or {}) do
            if not activeBtns[btn] and btn.Hide then btn:Hide() end
        end
        t._layoutDirty = true
        S.colEpoch = S.colEpoch + 1
        for _, group in ipairs(S.prepared) do
            H.syncCellGroup(group)
        end
        if t.scrollBox and t.scrollBox.ForEachFrame then
            t.scrollBox:ForEachFrame(function(r)
                if r.cellGroup then
                    H.syncRowCells(r)
                end
            end)
        end
        local w = (S.host and S.host.parent and S.host.parent.GetWidth and S.host.parent:GetWidth()) or 0
        if w <= 0 and S.view and S.view.GetWidth then w = S.view:GetWidth() or 0 end
        if w <= 0 then w = 1320 end
        vcProvider.Layout(w)
        local pal = getThemePalette()
        if t.scrollBox and t.scrollBox.ForEachFrame then
            t.scrollBox:ForEachFrame(function(r)
                if r.cellGroup then
                    if t.layoutRow and r._layoutEpoch ~= t._layoutEpoch then t.layoutRow(r) end
                    if r.data then
                        H.paintRowCells(r, H.cellValues(r.data), pal)
                    end
                    H.paintSelection(r)
                end
            end)
        end
        H.styleHeaders()
        H.refreshColumnPopover()
    end

    function H.applyTheme()
        local v = S.view
        if not v then return end
        local pal = getThemePalette()
        H.clearInsetChrome()
        if type(v._mmCard) == 'table' then
            if v._mmCard.UpdateTheme then
                v._mmCard:UpdateTheme()
            else
                local bg = (pal and pal.cardBg) or {0.173, 0.173, 0.180, 1}
                if v._mmCard.SetFill then v._mmCard:SetFill(bg) end
            end
        end
        if pal and pal.separator then
            local a = (pal.separator[4] or 0.45) * 0.65
            if v.barSep and v.barSep.SetColorTexture then
                v.barSep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], a)
            end
            if v.row2Sep and v.row2Sep.SetColorTexture then
                v.row2Sep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], a)
            end
            if v.row3Sep and v.row3Sep.SetColorTexture then
                v.row3Sep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], a)
            end
        end
        if v.hdrTitle and v.hdrTitle.SetTextColor and pal and pal.text then
            v.hdrTitle:SetTextColor(pal.text[1], pal.text[2], pal.text[3], 1)
        end
        if v.summary and v.summary.SetTextColor and pal and pal.textSecondary then
            v.summary:SetTextColor(pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1)
        end
        if v.planSummaryFs and v.planSummaryFs.SetTextColor and pal and pal.textSecondary then
            v.planSummaryFs:SetTextColor(pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1)
        end
        if v.emptyText and v.emptyText.SetTextColor and pal and pal.textSecondary then
            v.emptyText:SetTextColor(pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1)
        end
        if v._skillLabel and v._skillLabel.SetTextColor and pal and pal.textSecondary then
            v._skillLabel:SetTextColor(pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1)
        end
        if v._skillDash and v._skillDash.SetTextColor and pal and pal.textMuted then
            v._skillDash:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1)
        end
        if type(v.skillError) == 'table' and v.skillError.SetTextColor and pal and pal.accentRed then
            v.skillError:SetTextColor(pal.accentRed[1], pal.accentRed[2], pal.accentRed[3], 1)
        end
        for _, eb in ipairs({v.skillMin, v.skillMax}) do
            if type(eb) == 'table' and eb.SetTextColor and pal and pal.text then
                eb:SetTextColor(pal.text[1], pal.text[2], pal.text[3], 1)
            end
        end
        H.updateProfPills((S.latest and S.latest.profFilter) or (_G.MerchantMasterDB and _G.MerchantMasterDB.profFilter) or 'all')
        H.syncLegacyControls(S.latest)
        H.syncPlanControls(S.latest)
        H.styleHeaders()
        H.updateShiftHeader()
        H.themeColumnSettingsPopover()
        if S.boundResult and S.buildState and S.buildState.completed and v.summary then
            v.summary:SetText(H.formatSummary(S.boundResult))
        end
        if S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame then
            S.tbl.scrollBox:ForEachFrame(function(r)
                if r.data then
                    if r._colEpoch ~= S.colEpoch then H.syncRowCells(r) end
                    if S.tbl.layoutRow and r._layoutEpoch ~= S.tbl._layoutEpoch then S.tbl.layoutRow(r) end
                    H.paintRowCells(r, H.cellValues(r.data), pal)
                end
                H.paintSelection(r)
            end)
        end
    end

    function H.resetFilters()
        local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
        if type(db) == 'table' then
            db[dbPrefix .. 'SkillMin'], db[dbPrefix .. 'SkillMax'] = nil, nil
            H.syncSkills(db)
        end
        if S.view and S.view.skillMin and S.view.skillMin.ClearFocus then S.view.skillMin:ClearFocus() end
        if S.view and S.view.skillMax and S.view.skillMax.ClearFocus then S.view.skillMax:ClearFocus() end
        if S.host and S.host[spec.hostResetFn] then
            S.host[spec.hostResetFn]()
            return
        end
        if type(db) == 'table' then
            db.profFilter = 'all'
            db.unlockFilter = 'all'
            db.knownRecipesOnly = false
            db.craftableFilter = 'all'
            db.subCraftMode = 'smart'
            db[dbPrefix .. 'MasterChef'] = 'auto'
            db[dbPrefix .. 'ArcaneSalvager'] = false
            db[dbPrefix .. 'Bartering'] = 'auto'
            db[dbPrefix .. 'Honored'] = false
            db[dbPrefix .. 'MoatFilter'] = 'all'
            db[dbPrefix .. 'YieldMode'] = 'auto'
            db[dbPrefix .. 'OnlyProfitable'] = false
            db[dbPrefix .. 'ShowNonDE'] = false
            db[dbPrefix .. 'TopN'] = 10
            db[dbPrefix .. 'MaxCrafts'] = 0
            db[dbPrefix .. 'Budget'] = 0
            db[dbPrefix .. 'TopOnly'] = false
            db[dbPrefix .. 'SkillMin'] = nil
            db[dbPrefix .. 'SkillMax'] = nil
            db[dbPrefix .. 'Sources'] = {}
        end
        if S.latest then
            S.latest.profFilter = 'all'
            S.latest.unlockFilter = 'all'
            S.latest.knownRecipesOnly = false
            S.latest.search = ''
            S.latest.subCraftMode = 'smart'
            S.latest.masterChefMode = 'auto'
            S.latest.arcaneSalvager = false
            S.latest.barteringMode = 'auto'
            S.latest.honoredDiscount = false
            S.latest.moatFilter = 'all'
            S.latest.yieldMode = 'auto'
            S.latest.onlyProfitable = false
            S.latest.showNonDE = false
            S.latest.topN = 10
            S.latest.maxCraftsPerRecipe = 0
            S.latest.budgetCopper = 0
            S.latest.topOnly = false
        end
        if S.host and S.host.sidebar and S.host.sidebar.subCraftBtn and ns.SUBCRAFT_MODES and ns.SUBCRAFT_MODES[1] then
            H.setBtnText(S.host.sidebar.subCraftBtn, ns.SUBCRAFT_MODES[1].label)
        end
        H.syncSkills(db)
        H.updateProfPills('all')
        H.syncLegacyControls(S.latest)
        H.syncPlanControls(S.latest)
        if S.view and S.view.sourceButton then H.setBtnText(S.view.sourceButton, H.sourceLabel(db)) end
        H.triggerRefresh()
    end

    function H.resolveSort()
        local st = S.host and S.host.getSort and S.host.getSort() or nil
        if type(st) ~= 'table' or not st.col then
            return 'avgProfit', false
        end
        return st.col, st.asc == true
    end

    function H.buildFilterKey(context, col, asc)
        local db = (context and context.db) or {}
        local topN, maxCrafts, budget, topOnly = H.resolvePlanOpts(context)
        return fingerprint({
            col = col,
            asc = asc,
            search = text(context and context.search),
            profFilter = (context and context.profFilter) or 'all',
            profMap = context and context.profMap,
            unlockFilter = (context and context.unlockFilter) or 'all',
            knownRecipesOnly = (context and context.knownRecipesOnly == true),
            allChars = (context and context.craftableAllChars == true),
            craftableFilter = db.craftableFilter or 'all',
            moatFilter = (context and context.moatFilter) or db[dbPrefix .. 'MoatFilter'] or 'all',
            onlyProfitable = (spec.mode == 'disenchant') and H.isOnlyProfitable(context) or nil,
            showNonDE = (spec.mode == 'disenchant') and H.isShowNonDE(context) or nil,
            topN = topN,
            maxCrafts = maxCrafts,
            budget = budget,
            topOnly = topOnly,
            skillMin = db[dbPrefix .. 'SkillMin'],
            skillMax = db[dbPrefix .. 'SkillMax'],
            sources = db[dbPrefix .. 'Sources'],
        })
    end

    function H.effectiveCraftYieldVersion(store)
        if type(store) ~= 'table' then return 0 end
        if type(store.craftYieldVersion) == 'number' then
            if store._trackedAccountingVersion == nil or store._trackedAccountingVersion == store.accountingVersion then
                return store.craftYieldVersion
            end
        end
        local stats = store.db and store.db.craftYieldStats
        if type(stats) == 'table' then
            local parts = {}
            for k, v in pairs(stats) do
                if type(v) == 'table' then
                    parts[#parts + 1] = tostring(k) .. ':' .. tostring(v.casts or 0) .. ':' .. tostring(v.totalOutput or 0)
                end
            end
            table.sort(parts)
            return table.concat(parts, ',')
        end
        return store.accountingVersion or store.version or 0
    end

    function H.serializeProfKeys(profMap)
        if type(profMap) ~= 'table' or not readable(profMap) then return '' end
        local keys = {}
        for k, v in pairs(profMap) do
            if readable(k) and readable(v) and v ~= false and v ~= nil then
                keys[#keys + 1] = tostring(k)
            end
        end
        table.sort(keys)
        return table.concat(keys, ',')
    end

    function H.buildVCPriority(context)
        local db = (context and context.db) or _G.MerchantMasterDB or {}
        local rawProf = text((context and context.profFilter) or db.profFilter):lower():match('^%s*(.-)%s*$')
        local profFilter = (rawProf and rawProf ~= '') and rawProf or 'all'
        local unlockFilter = (context and context.unlockFilter) or db.unlockFilter or 'all'
        local knownRecipesOnly = (context and context.knownRecipesOnly == true) or (db.knownRecipesOnly == true) or (unlockFilter == 'known')
        local profMap = context and context.profMap
        local profMapFallback = false
        if type(profMap) ~= 'table' or next(profMap) == nil then
            local saved = ns.activeChar and ns.activeChar.profs
            if type(saved) == 'table' and next(saved) ~= nil then
                profMap = saved
                profMapFallback = true
            end
        end
        local skillMin = db[dbPrefix .. 'SkillMin']
        local skillMax = db[dbPrefix .. 'SkillMax']
        local sources = db[dbPrefix .. 'Sources']
        local key = fingerprint({
            profFilter = profFilter,
            profMap = profMap,
            profMapFallback = profMapFallback,
            unlockFilter = unlockFilter,
            knownRecipesOnly = knownRecipesOnly,
            allChars = (context and context.craftableAllChars == true),
            skillMin = skillMin,
            skillMax = skillMax,
            sources = sources,
        })
        return {
            profFilter = profFilter,
            profMap = profMap,
            profMapFallback = profMapFallback,
            unlockFilter = unlockFilter,
            knownRecipesOnly = knownRecipesOnly,
            allChars = (context and context.craftableAllChars == true),
            skillMin = skillMin,
            skillMax = skillMax,
            sources = sources,
            key = key,
        }
    end

    function H.effectiveCraftYieldReset(store)
        if type(store) ~= 'table' then return 0 end
        if type(store.craftYieldResetVersion) == 'number' then
            return store.craftYieldResetVersion
        end
        return H.effectiveCraftYieldVersion(store)
    end

    function H.computeDatasetSig(context, legacy)
        local db = (context and context.db) or {}
        local statsContext = context and context.statsContext
        local leg = legacy or H.resolveLegacy(context)
        return fingerprint({
            economy = context and context.econInfo and context.econInfo.effectiveKey,
            price = (ns.GetEffectivePriceVersion and ns.GetEffectivePriceVersion()) or ns.priceCacheEpoch or 0,
            source = db.priceSource,
            mode = context and context.subCraftMode,
            overrides = context and context.subCraftOverrides,
            prices = db.outlierPrices,
            masterChef = leg.masterChef,
            bartering = leg.bartering,
            honored = leg.honored == true,
            applyAHCut = (spec.mode == 'disenchant') and (db.applyAHCut ~= false) or nil,
            arcaneSalvager = (spec.mode == 'disenchant') and H.isArcaneSalvager(context) or nil,
            showNonDE = (spec.mode == 'disenchant') and H.isShowNonDE(context) or nil,
            deObsVersion = (spec.mode == 'disenchant') and ((context and context.deObsVersion) or (ns.GetDEObservationVersion and ns.GetDEObservationVersion()) or 0) or nil,
            yieldMode = (context and context.yieldMode) or db[dbPrefix .. 'YieldMode'] or 'auto',
            yieldReset = H.effectiveCraftYieldReset(ns.Analytics and ns.Analytics.Store),
            revision = not statsContext and context and context.revision or nil,
            forced = S.forceVersion,
            favor = statsContext and statsContext.favorCopper,
            char = context and context.charKey,
            allChars = context and context.craftableAllChars == true,
            profKeys = H.serializeProfKeys(context and context.profMap),
            catalog = tostring(ns.RecipeStats and ns.RecipeStats.GetCatalog and ns.RecipeStats.GetCatalog() or ''),
        })
    end

    function H.snapshotValue(value)
        if type(value) ~= 'table' then return value end
        local copy = {}
        for k, v in pairs(value) do copy[k] = H.snapshotValue(v) end
        return copy
    end

    function H.buildEvalContext(context, sig)
        local db = (context and context.db) or {}
        local statsContext = context and context.statsContext
        local base = statsContext and H.snapshotValue(statsContext) or {
            ownedCounts = context and context.counts,
            profMap = H.snapshotValue(context and context.profMap),
            repState = H.snapshotValue(context and context.repState),
            economy = context and context.econInfo and context.econInfo.effectiveKey,
            charKey = context and context.charKey,
            applyAHCut = db.applyAHCut ~= false,
            subCraftMode = context and context.subCraftMode,
            subCraftOverrides = H.snapshotValue(context and context.subCraftOverrides),
            outlierPrices = H.snapshotValue(db.outlierPrices),
        }
        base.economy = base.economy or (context and context.econInfo and context.econInfo.effectiveKey)
        base.profMap = base.profMap or H.snapshotValue(context and context.profMap)
        base.counts = context and context.counts
        base.ownedCounts = base.ownedCounts or (context and context.counts)
        base.subCraftMode = (context and context.subCraftMode) or base.subCraftMode or 'smart'
        base.subCraftOverrides = (context and context.subCraftOverrides) or base.subCraftOverrides
        base.craftableAllChars = (context and context.craftableAllChars == true)
        base.knownRecipesOnly = (context and context.knownRecipesOnly == true)
        base.masterChefMode = (context and context.masterChefMode ~= nil) and context.masterChefMode
            or ((db[dbPrefix .. 'MasterChef'] ~= nil) and db[dbPrefix .. 'MasterChef'] or 'auto')
        base.barteringMode = (context and context.barteringMode ~= nil) and context.barteringMode
            or ((db[dbPrefix .. 'Bartering'] ~= nil) and db[dbPrefix .. 'Bartering'] or 'auto')
        base.honoredDiscount = (context and context.honoredDiscount ~= nil) and (context.honoredDiscount == true)
            or (db[dbPrefix .. 'Honored'] == true)
        base.yieldMode = (context and context.yieldMode) or db[dbPrefix .. 'YieldMode'] or 'auto'
        if spec.mode == 'disenchant' then
            base.arcaneSalvager = H.isArcaneSalvager(context)
            base.showNonDE = H.isShowNonDE(context)
            base.deObsVersion = (context and context.deObsVersion) or (ns.GetDEObservationVersion and ns.GetDEObservationVersion()) or 0
        end
        base.revision = nil
        base.hostRevision = nil
        base.dataset = sig
        base.defer = C_Timer and C_Timer.After and H.laterGuarded or nil
        base.priceBank = nil
        return base
    end

    function H.syncEvaluationState(context, sig)
        local statsContext = context and context.statsContext
        local professor = (ns.GetProfessorDB and ns.GetProfessorDB()) or _G.MerchantProfessorDB
        local store = ns.Analytics and ns.Analytics.Store
        if sig == S.signature then
            if store and type(store.craftYieldVersion) == 'number' and S.seenCraftYieldVersion ~= nil then
                if store.craftYieldVersion > S.seenCraftYieldVersion then
                    local prevV, curV = S.seenCraftYieldVersion, store.craftYieldVersion
                    S.seenCraftYieldVersion = curV
                    local delta = curV - prevV
                    local log = store.craftYieldLog
                    local needForce = false
                    if delta <= 64 and type(log) == 'table' then
                        local catalog = ns.RecipeStats and ns.RecipeStats.GetCatalog and ns.RecipeStats.GetCatalog() or nil
                        for v = prevV + 1, curV do
                            local entry = log[v]
                            if entry == nil then
                                needForce = true
                                break
                            end
                            local id = tonumber(entry.itemID) or 0
                            if id <= 0 and entry.spellID and catalog then
                                for j = 1, #catalog do
                                    local r = catalog[j] and catalog[j].recipe
                                    if r and r.spellID == entry.spellID and r.outputItemID and r.outputItemID > 0 then
                                        id = r.outputItemID
                                        break
                                    end
                                end
                            end
                            if id and id > 0 then
                                S.itemChanges[id] = true
                            elseif not (entry.spellID and entry.spellID > 0) then
                                needForce = true
                                break
                            end
                        end
                    else
                        needForce = true
                    end
                    if needForce then
                        S.forceVersion = S.forceVersion + 1
                        return true
                    end
                elseif store.craftYieldVersion < S.seenCraftYieldVersion then
                    S.seenCraftYieldVersion = store.craftYieldVersion
                end
            end
        end
        if sig == S.signature and S.metaDirty then
            S.metaDirty = false
            S.metaTargets = nil
            if S.evaluation then
                S.evaluation.counts = context and context.counts
                S.evaluation.ownedCounts = context and context.counts
                S.evaluation.ownedCountsByID = statsContext and statsContext.ownedCountsByID
                S.evaluation.profMap = H.snapshotValue(context and context.profMap)
                S.evaluation.repState = H.snapshotValue(context and context.repState)
                S.evaluation.trainerCosts = (statsContext and statsContext.trainerCosts) or (professor and professor.trainerCosts)
            end
            local currentRows = (S.buildState and S.buildState.rows) or S.rows
            if currentRows and #currentRows > 0 and ns.RecipeStats and type(ns.RecipeStats.PatchMeta) == 'function' then
                ns.RecipeStats.PatchMeta(currentRows, S.evaluation)
                S.metaEpoch = S.metaEpoch + 1
                S.cellCacheEpoch = S.cellCacheEpoch + 1
                S.retainedResult = nil
                S.retainedPlan = nil
                S.boundResult = nil
                S.boundFilterKey = nil
                S.earlyPresentedFilterKey = nil
                S.earlyBoundResult = nil
                S.earlyCountShown = nil
                S.filterLRU:clear()
            end
        elseif sig == S.signature and S.metaTargets then
            local mt = S.metaTargets
            S.metaTargets = nil
            if S.evaluation then
                S.evaluation.counts = context and context.counts
                S.evaluation.ownedCounts = context and context.counts
                S.evaluation.ownedCountsByID = statsContext and statsContext.ownedCountsByID
                S.evaluation.profMap = H.snapshotValue(context and context.profMap)
                S.evaluation.repState = H.snapshotValue(context and context.repState)
                S.evaluation.trainerCosts = (statsContext and statsContext.trainerCosts) or (professor and professor.trainerCosts)
                S.evaluation.now = (context and context.now) or (statsContext and statsContext.now)
            end
            local currentRows = (S.buildState and S.buildState.rows) or S.rows
            if currentRows and #currentRows > 0 and ns.RecipeStats and type(ns.RecipeStats.PatchMetaTargeted) == 'function' then
                local patched = ns.RecipeStats.PatchMetaTargeted(currentRows, S.evaluation, mt)
                if patched > 0 then
                    S.cellCacheEpoch = S.cellCacheEpoch + 1
                    local db = (context and context.db) or _G.MerchantMasterDB or {}
                    local col = H.resolveSort()
                    local cf = db.craftableFilter or 'all'
                    local ownSens = mt.hasOwnership and (cf ~= 'all' or col == 'ownedOutputQty' or col == 'ownedScrollQty' or col == 'canCraftSort' or col == 'canCraft')
                    local cdSens = mt.hasCooldown and (cf == 'craftable_now' or col == 'cdSort' or col == 'cooldown')
                    if ownSens or cdSens then
                        S.metaEpoch = S.metaEpoch + 1
                        S.retainedResult = nil
                        S.retainedPlan = nil
                        S.boundResult = nil
                        S.boundFilterKey = nil
                        S.earlyPresentedFilterKey = nil
                        S.earlyBoundResult = nil
                        S.earlyCountShown = nil
                        S.filterLRU:clear()
                    else
                        S.filterLRU:evictWhere(function(tag)
                            return tag and ((mt.hasOwnership and tag.ownSens) or (mt.hasCooldown and tag.cdSens))
                        end)
                        if H.active() and vcProvider.RepaintVisible then
                            vcProvider.RepaintVisible()
                        end
                    end
                end
            end
        elseif sig ~= S.signature then
            S.metaDirty = false
            S.metaTargets = nil
            S.itemChanges = {}
            vcProvider.Cancel()
            S.buildState = nil
            S.rows = nil
            S.signature = sig
            S.builtPriceRev = uiCache.curPriceRev()
            S.seenCraftYieldVersion = (store and type(store.craftYieldVersion) == 'number') and store.craftYieldVersion or 0
            S.retainedResult = nil
            S.retainedPlan = nil
            S.boundResult = nil
            S.boundFilterKey = nil
            S.earlyPresentedFilterKey = nil
            S.earlyBoundResult = nil
            S.earlyCountShown = nil
            S.filterLRU:clear()
            S.activePlan = nil
            if S.view then S.view.activePlan = nil end
            S.metaEpoch = S.metaEpoch + 1
            S.evaluation = H.buildEvalContext(context, sig)
        end
        return false
    end

    function H.reapplyPlanFields(rowsList, plan)
        if type(rowsList) ~= 'table' then return end
        local byKey = plan and plan.byKey or nil
        for i = 1, #rowsList do
            local row = rowsList[i]
            local pe = byKey and byKey[row.key] or nil
            if pe then
                row.planCrafts = pe.crafts
                row.planProfit = pe.profit
                row.planRank = pe.rank
            else
                row.planCrafts = nil
                row.planProfit = nil
                row.planRank = nil
            end
        end
    end

    function H.buildPlanAndResult(filtered, topN, maxCrafts, budget, econKey, topOnly, col, asc)
        local activePlan = nil
        local model = ns[spec.modelName]
        if model and model.OptimizePortfolio then
            activePlan = model.OptimizePortfolio(filtered, {
                topN = topN,
                maxCraftsPerRecipe = maxCrafts,
                budgetCopper = budget,
                econKey = econKey,
                includeVendorLoops = true,
            })
        end
        H.reapplyPlanFields(filtered, activePlan)
        local byKey = activePlan and activePlan.byKey or nil
        local result = filtered
        if topOnly then
            result = {}
            if byKey then
                for i = 1, #filtered do
                    if byKey[filtered[i].key] then
                        result[#result + 1] = filtered[i]
                    end
                end
                if col == 'avgProfit' and not asc then
                    table.sort(result, function(a, b)
                        local ar = tonumber(a.planRank) or 999999
                        local br = tonumber(b.planRank) or 999999
                        if ar ~= br then return ar < br end
                        return text(a.key) < text(b.key)
                    end)
                end
            end
        end
        return result, activePlan
    end

    function H.createFilterSortJob(dataRows, filters, sort, yieldBudget)
        local sortWorkspace = { values = {}, profs = {}, names = {}, keys = {}, keepEntries = true }
        local isNumeric = C.VC_NUMERIC_KEYS[sort.key or 'avgProfit'] == true
        local ascending = sort.ascending == true
        local function before(a, b)
            local av, bv = sortWorkspace.values[a], sortWorkspace.values[b]
            if isNumeric then
                if av == false and bv ~= false then return false end
                if av ~= false and bv == false then return true end
                if av ~= false and av ~= bv then
                    if ascending then return av < bv else return av > bv end
                end
            else
                if av ~= bv then
                    if ascending then return av < bv else return av > bv end
                end
            end
            local ap, bp = sortWorkspace.profs[a], sortWorkspace.profs[b]
            if ap ~= bp then return ap < bp end
            local an, bn = sortWorkspace.names[a], sortWorkspace.names[b]
            if an ~= bn then return an < bn end
            return sortWorkspace.keys[a] < sortWorkspace.keys[b]
        end
        return coroutine.create(function()
            local runs = {}
            local vcModel = ns[spec.modelName]
            if not (vcModel and vcModel.FilterSort) then return {} end
            for first = 1, #dataRows, 96 do
                local block = {}
                for i = first, math.min(first + 95, #dataRows) do
                    if i > first and (i - first) % 24 == 0 then yieldBudget() end
                    block[#block + 1] = dataRows[i]
                end
                yieldBudget()
                runs[#runs + 1] = vcModel.FilterSort(block, filters, sort, sortWorkspace)
                yieldBudget()
            end
            while #runs > 1 do
                local nextRuns = {}
                for i = 1, #runs, 2 do
                    local a, b = runs[i], runs[i + 1]
                    if not b then
                        nextRuns[#nextRuns + 1] = a
                    else
                        local merged, ai, bi = {}, 1, 1
                        while ai <= #a or bi <= #b do
                            if bi > #b or (ai <= #a and before(a[ai], b[bi])) then
                                merged[#merged + 1] = a[ai]; ai = ai + 1
                            else
                                merged[#merged + 1] = b[bi]; bi = bi + 1
                            end
                            if (#merged) % 24 == 0 then yieldBudget() end
                        end
                        nextRuns[#nextRuns + 1] = merged
                    end
                    yieldBudget()
                end
                runs = nextRuns
            end
            return runs[1] or {}
        end)
    end

    function H.present(sourceRows, warmTotal)
        local dataRows = sourceRows or S.rows
        if not S.latest or not dataRows or not H.active() then return end
        S.presentSeq = S.presentSeq + 1
        S.prewarmSeq = S.prewarmSeq + 1
        local mySeq = S.presentSeq
        local token = S.generation
        local function isCurrent()
            return mySeq == S.presentSeq and token == S.generation and H.active()
                and not (S.buildState and S.buildState.completed and S.rows and dataRows ~= S.rows)
        end
        local function clearInFlight()
            if S.inFlightPresent and S.inFlightPresent.seq == mySeq then
                S.inFlightPresent = nil
            end
        end
        local c = S.latest
        local db = c.db or {}
        if type(db[dbPrefix .. 'Sources']) ~= 'table' then db[dbPrefix .. 'Sources'] = {} end
        local col, asc = H.resolveSort()
        local fKey = H.buildFilterKey(c, col, asc)
        local presentSig, presentMetaEpoch = S.signature, S.metaEpoch
        S.inFlightPresent = {
            seq = mySeq, sig = presentSig, metaEpoch = presentMetaEpoch,
            fKey = fKey, dataRows = dataRows, warmTotal = warmTotal,
        }
        local aliases = { wowheadURL = 'name' }
        local filters = {
            sources = db[dbPrefix .. 'Sources'],
            search = c.search,
            profFilter = c.profFilter,
            profMap = c.profMap,
            unlockFilter = c.unlockFilter,
            knownRecipesOnly = c.knownRecipesOnly,
            craftableFilter = db.craftableFilter,
            moatFilter = c.moatFilter or db[dbPrefix .. 'MoatFilter'] or 'all',
            onlyProfitable = (spec.mode == 'disenchant') and (((c.onlyProfitable == true) or (db[dbPrefix .. 'OnlyProfitable'] == true)) and true or false) or nil,
            showNonDE = (spec.mode == 'disenchant') and (((c.showNonDE == true) or (db[dbPrefix .. 'ShowNonDE'] == true)) and true or false) or nil,
            skillMin = db[dbPrefix .. 'SkillMin'],
            skillMax = db[dbPrefix .. 'SkillMax'],
        }
        local sort = { key = aliases[col] or col, ascending = asc }
        local topN, maxCrafts, budget, topOnly = H.resolvePlanOpts(c)
        local econKey = (c.econInfo and c.econInfo.effectiveKey) or (S.evaluation and S.evaluation.economy) or nil
        local deadline
        local function yieldBudget() if clockMS() >= deadline then coroutine.yield() end end
        local job = H.createFilterSortJob(dataRows, filters, sort, yieldBudget)
        local function runStep()
            if not isCurrent() then clearInFlight(); return end
            deadline = clockMS() + 1.8
            local ok, filtered = coroutine.resume(job)
            if not ok then clearInFlight(); error(filtered) end
            if coroutine.status(job) ~= 'dead' then
                H.laterGuarded(runStep)
                return
            end
            if not filtered then clearInFlight(); return end
            local result, activePlan = H.buildPlanAndResult(filtered, topN, maxCrafts, budget, econKey, topOnly, col, asc)
            S.activePlan = activePlan
            if S.view then S.view.activePlan = activePlan end
            local laidOut, preformatted, preIdx = false, {}, 0
            local function commit()
                if not isCurrent() then clearInFlight(); return end
                local rowH = (S.host and S.host.rowHeight) or 22
                local boxH = (S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.GetHeight and S.tbl.scrollBox:GetHeight()) or 400
                local needed = math.ceil(math.max(1, boxH) / rowH) + 4
                local existing = 0
                if S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame then
                    S.tbl.scrollBox:ForEachFrame(function(r) if r.cells then existing = existing + 1 end end)
                end
                local target = math.max(0, math.min(#result, needed) - existing)
                if not laidOut then
                    laidOut = true
                    local width = (S.host and S.host.parent and S.host.parent:GetWidth()) or S.view:GetWidth()
                    S.boundWidth = width
                    vcProvider.Layout(width, nil, true)
                    S.tbl.updateHeaders()
                    H.laterGuarded(commit)
                    return
                end
                if #S.prepared < target then
                    local started = clockMS()
                    for _ = 1, 4 do
                        H.prepareCells()
                        if #S.prepared >= target or (clockMS() - started) >= 0.9 then break end
                    end
                    H.laterGuarded(commit)
                    return
                end
                local preTarget = math.min(#result, needed)
                if preIdx < preTarget then
                    local started = clockMS()
                    for _ = 1, 12 do
                        preIdx = preIdx + 1
                        local row = result[preIdx]
                        preformatted[row] = H.cellValues(row)
                        if preIdx >= preTarget or (clockMS() - started) >= 1.2 then break end
                    end
                    H.laterGuarded(commit)
                    return
                end
                if not isCurrent() then clearInFlight(); return end
                clearInFlight()
                S.transientCells = preformatted
                S.viewWasHidden = false
                S.tbl.setRows(result)
                S.transientCells = nil
                if sourceRows and warmTotal then
                    S.earlyBoundResult = result
                    S.earlyCountShown = #result
                    S.earlyTier1Done = (S.buildState and S.buildState.scanned) or #dataRows
                    S.earlyWarmTotal = warmTotal
                    S.earlyPresentedFilterKey = fKey
                    local doneNow = (S.buildState and S.buildState.scanned) or #dataRows
                    if S.view.summary then
                        local warmLabel = H.isOnlyProfitable(c) and 'profitable' or 'crafts'
                        S.view.summary:SetText(string.format('%d %s (warming %d/%d)', #result, warmLabel, doneNow, warmTotal))
                    end
                else
                    S.retainedResult = result
                    S.retainedPlan = activePlan
                    S.retainedDatasetSig = presentSig
                    S.retainedFilterKey = fKey
                    S.retainedMetaEpoch = presentMetaEpoch
                    S.filterLRU:put(uiCache.makeLRUKey(presentSig, presentMetaEpoch, fKey), { result = result, plan = activePlan }, uiCache.metaSensitivityTags(db and db.craftableFilter, col))
                    S.boundResult = result
                    S.boundDatasetSig = presentSig
                    S.boundFilterKey = fKey
                    S.boundMetaEpoch = presentMetaEpoch
                    S.earlyPresentedFilterKey = nil
                    S.earlyBoundResult = nil
                    S.earlyCountShown = nil
                    if S.view.summary then
                        S.view.summary:SetText(H.formatSummary(result))
                    end
                end
                H.syncPlanControls(c)
                if S.view.emptyText and S.view.emptyText.SetShown then
                    S.view.emptyText:SetShown(#result == 0)
                end
                if S.host and S.host.statusText then
                    S.host.statusText:SetText(c.scanBanner or string.format('%d %s - %s', #result, H.craftCountNoun(c), c.econInfo and c.econInfo.label or 'selected economy'))
                end
                local top = result[1]
                vcProvider.bestProfit = top and top.avgProfit
            end
            H.laterGuarded(commit)
        end
        H.laterGuarded(runStep)
    end

    function H.prewarmPresentation(context)
        local dataRows = S.rows
        if not context or not dataRows or not S.view or not S.tbl or not S.host or H.active() then return end
        S.prewarmSeq = S.prewarmSeq + 1
        local myPreSeq = S.prewarmSeq
        local token = S.generation
        local preSig, preMetaEpoch = S.signature, S.metaEpoch
        local function preCurrent()
            return myPreSeq == S.prewarmSeq and token == S.generation and not H.active()
                and S.buildState and S.buildState.completed and S.rows == dataRows
                and S.signature == preSig and S.metaEpoch == preMetaEpoch
        end
        local db = context.db or _G.MerchantMasterDB or {}
        if type(db[dbPrefix .. 'Sources']) ~= 'table' then db[dbPrefix .. 'Sources'] = {} end
        local col, asc = H.resolveSort()
        local fKey = H.buildFilterKey(context, col, asc)
        local lruKey = uiCache.makeLRUKey(preSig, preMetaEpoch, fKey)
        local function prewarmWidgets(result)
            if not preCurrent() then return end
            local inCombat = _G.InCombatLockdown and _G.InCombatLockdown()
            if not inCombat and S.tbl and S.tbl.scrollBox then
                local rowH = (S.host and S.host.rowHeight) or 22
                local boxH = (S.tbl.scrollBox.GetHeight and S.tbl.scrollBox:GetHeight()) or 520
                local needed = math.max(24, math.min(30, math.ceil(math.max(1, boxH) / rowH) + 4))
                local existing = 0
                if S.tbl.scrollBox.ForEachFrame then
                    S.tbl.scrollBox:ForEachFrame(function(r) if r.cells then existing = existing + 1 end end)
                end
                local target = math.max(0, math.min(#result, needed) - existing)
                if #S.prepared < target then
                    local started = clockMS()
                    for _ = 1, 4 do
                        H.prepareCells()
                        if #S.prepared >= target or (clockMS() - started) >= 0.9 then break end
                    end
                    if #S.prepared < target then
                        H.laterGuarded(function() prewarmWidgets(result) end)
                        return
                    end
                end
            end
        end
        local lruHit = S.filterLRU:get(lruKey)
        if S.retainedResult and S.retainedDatasetSig == preSig
            and S.retainedFilterKey == fKey and S.retainedMetaEpoch == preMetaEpoch then
            H.laterGuarded(function() prewarmWidgets(S.retainedResult) end)
            return
        elseif lruHit then
            S.retainedResult = lruHit.result
            S.retainedPlan = lruHit.plan
            S.retainedDatasetSig = preSig
            S.retainedFilterKey = fKey
            S.retainedMetaEpoch = preMetaEpoch
            H.reapplyPlanFields(lruHit.result, lruHit.plan)
            H.laterGuarded(function() prewarmWidgets(lruHit.result) end)
            return
        end
        local aliases = { wowheadURL = 'name' }
        local filters = {
            sources = db[dbPrefix .. 'Sources'],
            search = context.search,
            profFilter = context.profFilter,
            profMap = context.profMap,
            unlockFilter = context.unlockFilter,
            knownRecipesOnly = context.knownRecipesOnly,
            craftableFilter = db.craftableFilter,
            moatFilter = context.moatFilter or db[dbPrefix .. 'MoatFilter'] or 'all',
            onlyProfitable = (spec.mode == 'disenchant') and H.isOnlyProfitable(context) or nil,
            showNonDE = (spec.mode == 'disenchant') and H.isShowNonDE(context) or nil,
            skillMin = db[dbPrefix .. 'SkillMin'],
            skillMax = db[dbPrefix .. 'SkillMax'],
        }
        local sort = { key = aliases[col] or col, ascending = asc }
        local topN, maxCrafts, budget, topOnly = H.resolvePlanOpts(context)
        local econKey = (context.econInfo and context.econInfo.effectiveKey) or (S.evaluation and S.evaluation.economy) or nil
        local deadline
        local function yieldBudget() if clockMS() >= deadline then coroutine.yield() end end
        local job = H.createFilterSortJob(dataRows, filters, sort, yieldBudget)
        local function runStep()
            if not preCurrent() then return end
            deadline = clockMS() + 1.2
            local ok, filtered = coroutine.resume(job)
            if not ok then error(filtered) end
            if coroutine.status(job) ~= 'dead' then
                H.laterGuarded(runStep)
                return
            end
            if not filtered or not preCurrent() then return end
            local result, activePlan = H.buildPlanAndResult(filtered, topN, maxCrafts, budget, econKey, topOnly, col, asc)
            S.activePlan = activePlan
            if S.view then S.view.activePlan = activePlan end
            S.retainedResult = result
            S.retainedPlan = activePlan
            S.retainedDatasetSig = preSig
            S.retainedFilterKey = fKey
            S.retainedMetaEpoch = preMetaEpoch
            S.filterLRU:put(lruKey, { result = result, plan = activePlan }, uiCache.metaSensitivityTags(db and db.craftableFilter, col))
            H.laterGuarded(function() prewarmWidgets(result) end)
        end
        H.laterGuarded(runStep)
    end

    function H.makeForegroundHandlers(token)
        local function onProgress(partialRows, done, total)
            if token ~= S.generation or not H.active() then return end
            if S.view and S.view.summary then
                if S.earlyPresentedFilterKey and S.earlyCountShown ~= nil then
                    local warmLabel = H.isOnlyProfitable() and 'profitable' or 'crafts'
                    S.view.summary:SetText(string.format('%d %s (warming %d/%d)', S.earlyCountShown, warmLabel, done or 0, total or 0))
                else
                    local scanLabel = H.isOnlyProfitable() and 'profitable' or 'matched'
                    S.view.summary:SetText(string.format('Scanning %s: %d / %d (%d %s)', spec.craftWordPlural, done or 0, total or 0, #(partialRows or {}), scanLabel))
                end
            end
        end
        local function onTierReady(partialRows, done, total)
            if token ~= S.generation or not H.active() or not S.latest then return end
            S.earlyPresentedFilterKey = nil
            S.earlyBoundResult = nil
            S.earlyCountShown = nil
            S.earlyTier1Done = done
            S.earlyWarmTotal = total
            S.earlyAuthoritative = S.buildState and S.buildState.tier1Authoritative == true
            local copy = {}
            for i = 1, #(partialRows or {}) do copy[i] = partialRows[i] end
            H.present(copy, total)
        end
        local function onComplete(result)
            if token ~= S.generation then return end
            S.presentSeq = S.presentSeq + 1
            S.inFlightPresent = nil
            S.cancelBuild = nil
            S.rows = result
            S.metaEpoch = S.metaEpoch + 1
            local earlyKey = S.earlyPresentedFilterKey
            local earlyResult = S.earlyBoundResult
            local earlyAuth = S.earlyAuthoritative
            S.retainedResult = nil
            S.retainedPlan = nil
            S.boundResult = nil
            S.boundFilterKey = nil
            S.filterLRU:clear()
            if not S.metaDirty and earlyKey and earlyAuth and earlyResult and not next(S.itemChanges) then
                S.retainedResult = earlyResult
                S.retainedPlan = S.activePlan
                S.retainedDatasetSig = S.signature
                S.retainedFilterKey = earlyKey
                S.retainedMetaEpoch = S.metaEpoch
                local eDb = (S.latest and S.latest.db) or _G.MerchantMasterDB or {}
                local eCol = H.resolveSort()
                S.filterLRU:put(uiCache.makeLRUKey(S.signature, S.metaEpoch, earlyKey), { result = earlyResult, plan = S.activePlan }, uiCache.metaSensitivityTags(eDb.craftableFilter, eCol))
                S.boundResult = earlyResult
                S.boundDatasetSig = S.signature
                S.boundFilterKey = earlyKey
                S.boundMetaEpoch = S.metaEpoch
            end
            if not H.active() then
                if not S.metaDirty and not S.metaTargets and not next(S.itemChanges) and (S.warmContext or S.latest) then
                    H.prewarmPresentation(S.warmContext or S.latest)
                end
                return
            end
            if not S.latest then return end
            if next(S.itemChanges) or S.metaDirty or S.metaTargets then
                S.retainedResult = nil
                S.retainedPlan = nil
                S.boundResult = nil
                S.boundFilterKey = nil
                S.earlyPresentedFilterKey = nil
                S.earlyBoundResult = nil
                S.earlyCountShown = nil
                H.laterGuarded(function()
                    if token == S.generation and H.active() then vcProvider.Refresh(S.latest) end
                end)
                return
            end
            local col, asc = H.resolveSort()
            local activeFilterKey = H.buildFilterKey(S.latest, col, asc)
            if earlyKey and earlyKey == activeFilterKey and earlyAuth and earlyResult then
                S.earlyPresentedFilterKey = nil
                S.earlyBoundResult = nil
                S.earlyCountShown = nil
                if S.view and S.view.summary then
                    S.view.summary:SetText(H.formatSummary(earlyResult))
                end
                return
            end
            S.retainedResult = nil
            S.retainedPlan = nil
            S.boundResult = nil
            S.boundFilterKey = nil
            S.earlyPresentedFilterKey = nil
            S.earlyBoundResult = nil
            S.earlyCountShown = nil
            H.present()
        end
        return onProgress, onComplete, onTierReady
    end

    function H.syncShiftFromModifier()
        local state = shiftKeyDown()
        if state == nil then return end
        local down = state and true or false
        if down ~= S.lastShiftDown then
            S.lastShiftDown = down
            vcProvider.SetShiftMode(down)
        end
    end

    function vcProvider.SetShiftMode(on)
        S.shiftActive = (on == true)
        H.updateShiftHeader()
        vcProvider.RepaintVisible()
        return S.shiftActive
    end

    function vcProvider.RepaintShoppingQty()
        if S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame then
            S.tbl.scrollBox:ForEachFrame(H.paintSelection)
        end
    end

    function vcProvider.RepaintVisible()
        if not S.view or not S.tbl or not S.tbl.scrollBox or not S.tbl.scrollBox.ForEachFrame then return end
        local pal = getThemePalette()
        S.tbl.scrollBox:ForEachFrame(function(r)
            if r.data and r.cells then
                if r._colEpoch ~= S.colEpoch then H.syncRowCells(r) end
                if S.tbl.layoutRow and r._layoutEpoch ~= S.tbl._layoutEpoch then S.tbl.layoutRow(r) end
                H.paintRowCells(r, H.cellValues(r.data), pal)
                H.paintSelection(r)
            elseif r.shiftStepper and r.shiftStepper.Hide then
                r.shiftStepper:Hide()
            end
        end)
    end

    function vcProvider.CancelPresentation()
        S.presentSeq = S.presentSeq + 1
        S.pending = false
        S.viewWasHidden = true
        S.inFlightPresent = nil
        if S.buildState and S.buildState.running then
            S.buildState.background = true
            S.buildState.onProgress = nil
            S.buildState.onTierReady = nil
            if S.evaluation then S.evaluation.background = true end
        end
    end

    function H.applyPendingChanges()
        local itemsOnly = (S.changes.items == true)
        local needFull = false
        for chReason in pairs(S.changes) do
            if chReason ~= 'items' then itemsOnly = false end
            if chReason ~= 'ownership' and chReason ~= 'snapshot' and chReason ~= 'trainer' and chReason ~= 'items'
                and chReason ~= 'skills' and chReason ~= 'known' and chReason ~= 'rep' and chReason ~= 'cooldown' then
                needFull = true
            end
        end
        if needFull then
            local model = ns[spec.modelName]
            if model and model.ClearCache then
                model.ClearCache()
            end
            S.forceVersion = S.forceVersion + 1
            S.cellCacheEpoch = S.cellCacheEpoch + 1
            S.retainedResult = nil
            S.retainedPlan = nil
            S.boundResult = nil
            S.boundFilterKey = nil
            S.earlyPresentedFilterKey = nil
            S.earlyBoundResult = nil
            S.earlyCountShown = nil
            S.filterLRU:clear()
        end
        S.changes = {}
        return itemsOnly
    end

    function vcProvider.Cancel()
        S.generation = S.generation + 1
        S.presentSeq = S.presentSeq + 1
        S.prewarmSeq = S.prewarmSeq + 1
        S.pending = false
        S.inFlightPresent = nil
        if S.reconcilePending then
            S.reconcilePending = false
            S.reconcileSeq = (S.reconcileSeq or 0) + 1
            H.applyPendingChanges()
        end
        if S.cancelBuild then
            S.cancelBuild()
            S.cancelBuild = nil
        end
    end

    function vcProvider.Invalidate(reason, itemIDs)
        if not reason then
            local model = ns[spec.modelName]
            if model and model.ClearCache then
                model.ClearCache()
            end
            vcProvider.Cancel()
            S.signature = nil
            S.builtPriceRev = nil
            S.buildState = nil
            S.rows = nil
            S.metaDirty = false
            S.metaTargets = nil
            S.seenCraftYieldVersion = nil
            S.itemChanges = {}
            S.retainedResult = nil
            S.retainedPlan = nil
            S.boundResult = nil
            S.boundFilterKey = nil
            S.earlyPresentedFilterKey = nil
            S.earlyBoundResult = nil
            S.earlyCountShown = nil
            S.filterLRU:clear()
            S.activePlan = nil
            if S.view then S.view.activePlan = nil end
            S.metaEpoch = S.metaEpoch + 1
            S.forceVersion = S.forceVersion + 1
            S.cellCacheEpoch = S.cellCacheEpoch + 1
        else
            S.changes[reason] = true
            if reason == 'ownership' then
                if type(itemIDs) == 'table' and (itemIDs.ids ~= nil or itemIDs.names ~= nil) then
                    local hasAny = (type(itemIDs.ids) == 'table' and next(itemIDs.ids) ~= nil)
                        or (type(itemIDs.names) == 'table' and next(itemIDs.names) ~= nil)
                    if hasAny then
                        S.metaTargets = S.metaTargets or { ids = {}, names = {}, spells = {} }
                        S.metaTargets.hasOwnership = true
                        if type(itemIDs.ids) == 'table' then
                            for k, v in pairs(itemIDs.ids) do
                                local id = type(v) == 'number' and v or (type(k) == 'number' and k)
                                if id and v ~= false then S.metaTargets.ids[id] = true end
                            end
                        end
                        if type(itemIDs.names) == 'table' then
                            for k, v in pairs(itemIDs.names) do
                                local nm = type(v) == 'string' and v or (type(k) == 'string' and k)
                                if nm and v ~= false then S.metaTargets.names[nm] = true end
                            end
                        end
                    end
                else
                    S.metaDirty = true
                end
            elseif reason == 'cooldown' then
                if type(itemIDs) == 'table' and next(itemIDs) ~= nil then
                    S.metaTargets = S.metaTargets or { ids = {}, names = {}, spells = {} }
                    S.metaTargets.hasCooldown = true
                    for k, v in pairs(itemIDs) do
                        local sid = type(v) == 'number' and v or (type(k) == 'number' and k)
                        if sid and v ~= false then S.metaTargets.spells[sid] = true end
                    end
                elseif itemIDs == nil then
                    S.metaDirty = true
                end
            elseif reason == 'trainer' or reason == 'skills' or reason == 'known' or reason == 'rep' then
                S.metaDirty = true
            end
            if reason == 'items' then
                for key, value in pairs(itemIDs or {}) do
                    local id = type(value) == 'number' and value or key
                    if number(id) then S.itemChanges[id] = true end
                end
            end
        end
        if S.reconcilePending then return end
        S.reconcilePending = true
        S.reconcileSeq = (S.reconcileSeq or 0) + 1
        local myRecSeq = S.reconcileSeq
        H.laterGuarded(function()
            if myRecSeq ~= S.reconcileSeq then return end
            S.reconcilePending = false
            local itemsOnly = H.applyPendingChanges()
            if S.latest and H.active() then
                if not itemsOnly and S.latest.hostManaged and S.host and S.host.refresh then
                    S.host.refresh()
                else
                    vcProvider.Refresh(S.latest)
                end
            end
        end)
    end

    function vcProvider.HasWarmData()
        return S.buildState ~= nil and (S.buildState.running == true or S.buildState.completed == true)
    end

    function vcProvider.IsWarming()
        return S.buildState ~= nil and S.buildState.running == true
    end

    function vcProvider.GetActivePlan()
        return S.activePlan
    end

    function vcProvider.WarmInBackground(context)
        if not context then return vcProvider.HasWarmData() end
        S.warmContext = context
        local db = context.db or _G.MerchantMasterDB or {}
        if type(db[dbPrefix .. 'Sources']) ~= 'table' then db[dbPrefix .. 'Sources'] = {} end
        local leg = H.resolveLegacy(context)
        local sig = H.computeDatasetSig(context, leg)
        if H.syncEvaluationState(context, sig) then
            sig = H.computeDatasetSig(context, leg)
            H.syncEvaluationState(context, sig)
        end
        local priority = H.buildVCPriority(context)
        if S.buildState and S.buildState.completed then
            S.rows = S.rows or S.buildState.rows
            if not H.active() then
                local col, asc = H.resolveSort()
                local fKey = H.buildFilterKey(context, col, asc)
                local hasRetained = S.retainedResult and S.retainedDatasetSig == sig
                    and S.retainedFilterKey == fKey and S.retainedMetaEpoch == S.metaEpoch
                if not hasRetained then
                    H.prewarmPresentation(context)
                end
            end
            return true
        end
        local model = ns[spec.modelName]
        if S.buildState and S.buildState.running then
            if S.buildState.priorityKey ~= priority.key then
                if S.evaluation then S.evaluation.priority = priority end
                if model and model.Reprioritize then
                    model.Reprioritize(S.buildState, priority)
                end
            end
            return true
        end
        if S.evaluation then
            S.evaluation.background = true
            S.evaluation.priority = priority
        end
        local token = S.generation
        local finished = false
        local function onBgComplete(result)
            if token ~= S.generation then return end
            S.presentSeq = S.presentSeq + 1
            S.inFlightPresent = nil
            finished = true
            S.cancelBuild = nil
            S.rows = result
            S.metaEpoch = S.metaEpoch + 1
            S.retainedResult = nil
            S.retainedPlan = nil
            S.boundResult = nil
            S.boundFilterKey = nil
            S.filterLRU:clear()
            if H.active() and S.latest and not S.pending then
                vcProvider.Refresh(S.latest)
                if provider and provider.RefreshQuickLook then provider.RefreshQuickLook() end
            elseif not H.active() then
                H.prewarmPresentation(S.warmContext or context)
            end
            if ns.app and type(ns.app[spec.hostWarmCompleteFn]) == 'function' then
                ns.app[spec.hostWarmCompleteFn]()
            end
        end
        if model and model.Start then
            local cancel, state = model.Start(S.evaluation, nil, onBgComplete, S.buildState, nil)
            S.buildState = state
            if not finished and token == S.generation then S.cancelBuild = cancel end
        else
            onBgComplete({})
        end
        return true
    end

    function vcProvider.CloseHeatPopover()
        -- Vendor Crafter has no heat popover; safe no-op for host tab-switch contract.
    end

    function H.layoutRow2(rowWidth)
        local v = S.view
        if not v or not v.legacyBar or not v.row2LeftBtns then return end
        local w = tonumber(rowWidth) or (v.legacyBar.GetWidth and v.legacyBar:GetWidth()) or 0
        if w < 400 then return end
        local row2 = v.legacyBar
        local infoBtn = v.legacyInfoBtn
        local infoW = (infoBtn and infoBtn._pillW) or 82
        if infoBtn then
            infoBtn:ClearAllPoints()
            infoBtn:SetPoint('TOPRIGHT', row2, 'TOPRIGHT', -12, -6)
            infoBtn._layoutBox = { row = 1, left = w - 12 - infoW, right = w - 12, top = -46, bottom = -70 }
        end
        local sub1MaxRight = infoBtn and (w - 12 - infoW - 8) or (w - 12)
        local subrow = 1
        local x = 16
        local gap = 6
        for _, btn in ipairs(v.row2LeftBtns) do
            local bw = btn._pillW or (btn.GetWidth and btn:GetWidth()) or 100
            local maxRight = (subrow == 1) and sub1MaxRight or (w - 12)
            if x > 16 and (x + bw) > maxRight then
                subrow = subrow + 1
                x = 16
            end
            local y = -6 - (subrow - 1) * 28
            btn:ClearAllPoints()
            btn:SetPoint('TOPLEFT', row2, 'TOPLEFT', x, y)
            btn._layoutBox = { row = subrow, left = x, right = x + bw, top = -40 + y, bottom = -40 + y - 24 }
            x = x + bw + gap
        end
        local row2H = (subrow == 1) and 36 or (12 + subrow * 24 + (subrow - 1) * 4)
        v._row2Subrows = subrow
        if v._row2Height ~= row2H then
            v._row2Height = row2H
            row2:SetHeight(row2H)
            local planTop = -40 - row2H
            if v.planBar then
                v.planBar:ClearAllPoints()
                v.planBar:SetPoint('TOPLEFT', 0, planTop)
                v.planBar:SetPoint('TOPRIGHT', 0, planTop)
            end
            local hdrTop = planTop - 35
            if S.tbl and S.tbl.headerBar then
                S.tbl.headerBar:ClearAllPoints()
                S.tbl.headerBar:SetPoint('TOPLEFT', 6, hdrTop)
                S.tbl.headerBar:SetPoint('TOPRIGHT', -18, hdrTop)
            end
            local insetTop = hdrTop - 28
            if S.tbl and type(S.tbl.inset) == 'table' then
                S.tbl.inset:ClearAllPoints()
                S.tbl.inset:SetPoint('TOPLEFT', 0, insetTop)
                S.tbl.inset:SetPoint('BOTTOMRIGHT', 0, 0)
            end
        end
    end

    function vcProvider.Layout(width, _, deferScrollRefresh)
        if not S.view or not S.tbl then return end
        local minimum = 4
        for _, col in ipairs(S.tbl.columns or {}) do
            minimum = minimum + (col.minWidth or col.width) + 5
        end
        if H.active() and S.host and S.host.setMinimumWidth then
            S.host.setMinimumWidth(minimum + (S.host.windowPadding or 0))
        end
        local w = tonumber(width) or 0
        if w <= 0 then
            w = (S.host and S.host.parent and S.host.parent.GetWidth and S.host.parent:GetWidth()) or 0
            if w <= 0 and S.view and S.view.GetWidth then w = S.view:GetWidth() or 0 end
        end
        if w > 0 then
            H.layoutRow2(w)
        end
        local hdrW = (S.tbl.headerBar and S.tbl.headerBar.GetWidth and S.tbl.headerBar:GetWidth()) or 0
        ns.Window.LayoutTable(S.tbl, math.max(hdrW, w - 24), 1, deferScrollRefresh)
        local quickLook = ns.SuperList and ns.SuperList.GetQuickLookFrame and ns.SuperList.GetQuickLookFrame()
        if shown(quickLook) and quickLook.Reposition then quickLook.Reposition() end
    end

    function vcProvider.GetColumnConfig()
        local cfg = H.normalizeColumnConfig(H.getColumnDB())
        local orderCopy, hiddenCopy = {}, {}
        for i, k in ipairs(cfg.order) do orderCopy[i] = k end
        for k, v in pairs(cfg.hidden) do if v then hiddenCopy[k] = true end end
        return { order = orderCopy, hidden = hiddenCopy }
    end

    function vcProvider.SetColumnVisible(key, visible)
        if key == 'name' or not C.VENDOR_BY_KEY[key] then return false end
        local db = H.getColumnDB()
        local cfg = H.normalizeColumnConfig(db)
        cfg.hidden[key] = (visible == false) and true or nil
        if S.view and S.view._applyColumnConfig then S.view._applyColumnConfig(db) end
        return true
    end

    function vcProvider.MoveColumn(key, delta)
        if key == 'name' or not C.VENDOR_BY_KEY[key] then return false end
        local step = tonumber(delta)
        if not step or step == 0 then return false end
        local db = H.getColumnDB()
        local cfg = H.normalizeColumnConfig(db)
        local pos
        for i, k in ipairs(cfg.order) do
            if k == key then pos = i break end
        end
        if not pos then return false end
        local target = math.max(2, math.min(#cfg.order, pos + step))
        if target == pos then return false end
        table.remove(cfg.order, pos)
        table.insert(cfg.order, target, key)
        if S.view and S.view._applyColumnConfig then S.view._applyColumnConfig(db) end
        return true
    end

    function vcProvider.ResetColumns()
        local db = H.getColumnDB()
        local cfg = H.normalizeColumnConfig(db)
        cfg.order = {}
        for i, col in ipairs(C.VENDOR_COLUMNS) do cfg.order[i] = col.key end
        cfg.hidden = {}
        if S.view and S.view._applyColumnConfig then S.view._applyColumnConfig(db) end
        return true
    end

    function vcProvider.ToggleColumnSettings(force)
        local pop = S.view and S.view.colSettingsPopover
        if not pop then return false end
        local show
        if force ~= nil then show = (force == true) else show = not shown(pop) end
        if show then
            if S.view._ensureColumnPopoverBuilt then S.view._ensureColumnPopoverBuilt() end
            if S.view._themeColumnSettingsPopover then S.view._themeColumnSettingsPopover()
            elseif S.view._refreshColumnPopover then S.view._refreshColumnPopover() end
        end
        pop:SetShown(show)
        return show
    end

    function vcProvider.GetSidebarControls()
        local s = (S.host and S.host.sidebar) or {}
        local v = S.view or {}
        return { s.recCraftFilterBtn, v.sourceButton, v.skillControl, s.subCraftBtn, v.resetFiltersButton }
    end

    function vcProvider.Refresh(context)
        S.latest = context
        local db = (context and context.db) or _G.MerchantMasterDB or {}
        if type(db[dbPrefix .. 'Sources']) ~= 'table' then db[dbPrefix .. 'Sources'] = {} end
        if type(db) == 'table' then
            local cfg = H.normalizeColumnConfig(db)
            local sigCol = fingerprint(cfg)
            if sigCol ~= S.appliedColSig and S.view and S.view._applyColumnConfig then
                S.view._applyColumnConfig(db)
            end
        end
        H.syncSkills(db)
        H.updateProfPills((context and context.profFilter) or db.profFilter or 'all')
        if S.view and S.view.sourceButton then
            H.setBtnText(S.view.sourceButton, H.sourceLabel(db))
        end
        H.syncLegacyControls(context)
        H.syncPlanControls(context)
        local sidebar = S.host and S.host.sidebar
        if sidebar and sidebar.recCraftFilterBtn and S.host.findLabel and ns.CRAFTABLE_FILTERS then
            H.setBtnText(sidebar.recCraftFilterBtn, S.host.findLabel(ns.CRAFTABLE_FILTERS, db.craftableFilter or 'all'))
        end
        if not H.active() then
            vcProvider.CancelPresentation()
            return vcProvider.bestProfit
        end
        if S.reconcilePending and next(S.changes) then return vcProvider.bestProfit end

        local leg = H.resolveLegacy(context)
        local sig = H.computeDatasetSig(context, leg)
        if H.syncEvaluationState(context, sig) then
            sig = H.computeDatasetSig(context, leg)
            H.syncEvaluationState(context, sig)
        end

        if S.buildState and S.buildState.completed and next(S.itemChanges) then
            local ids = S.itemChanges
            S.itemChanges = {}
            local model = ns[spec.modelName]
            if S.rows and model and type(model.RepairItems) == 'function' then
                model.RepairItems(S.rows, S.evaluation, S.buildState.legacy, S.buildState.evalScratch, ids)
                S.metaEpoch = S.metaEpoch + 1
                S.cellCacheEpoch = S.cellCacheEpoch + 1
                S.retainedResult = nil
                S.retainedPlan = nil
                S.boundResult = nil
                S.boundFilterKey = nil
                S.earlyPresentedFilterKey = nil
                S.earlyBoundResult = nil
                S.earlyCountShown = nil
                S.filterLRU:clear()
            end
        end

        local col, asc = H.resolveSort()
        local fKey = H.buildFilterKey(context, col, asc)
        if S.buildState and S.buildState.completed and S.rows
            and not (S.retainedResult and S.retainedDatasetSig == sig
                and S.retainedFilterKey == fKey and S.retainedMetaEpoch == S.metaEpoch) then
            local lruHit = S.filterLRU:get(uiCache.makeLRUKey(sig, S.metaEpoch, fKey))
            if lruHit then
                S.retainedResult = lruHit.result
                S.retainedPlan = lruHit.plan
                S.retainedDatasetSig = sig
                S.retainedFilterKey = fKey
                S.retainedMetaEpoch = S.metaEpoch
                H.reapplyPlanFields(lruHit.result, lruHit.plan)
            end
        end
        if S.buildState and S.buildState.completed and S.rows
            and S.retainedResult and S.retainedDatasetSig == sig
            and S.retainedFilterKey == fKey and S.retainedMetaEpoch == S.metaEpoch then
            S.presentSeq = S.presentSeq + 1
            S.prewarmSeq = S.prewarmSeq + 1
            S.inFlightPresent = nil
            S.activePlan = S.retainedPlan
            if S.view then S.view.activePlan = S.activePlan end
            H.syncPlanControls(context)
            local currentWidth = (S.host and S.host.parent and S.host.parent:GetWidth()) or S.view:GetWidth()
            if S.boundWidth ~= currentWidth then
                S.boundWidth = currentWidth
                vcProvider.Layout(currentWidth)
                S.tbl.updateHeaders()
            end
            if S.boundResult ~= S.retainedResult or S.boundDatasetSig ~= sig
                or S.boundFilterKey ~= fKey or S.boundMetaEpoch ~= S.metaEpoch then
                S.viewWasHidden = false
                S.tbl.setRows(S.retainedResult)
                S.boundResult = S.retainedResult
                S.boundDatasetSig = sig
                S.boundFilterKey = fKey
                S.boundMetaEpoch = S.metaEpoch
            elseif S.viewWasHidden then
                S.viewWasHidden = false
                H.rebindStaleRows()
            end
            if S.view.emptyText and S.view.emptyText.SetShown then
                S.view.emptyText:SetShown(#S.retainedResult == 0)
            end
            if S.view.summary then S.view.summary:SetText(H.formatSummary(S.retainedResult)) end
            if S.host and S.host.statusText then
                S.host.statusText:SetText(context.scanBanner or string.format('%d %s - %s', #S.retainedResult, H.craftCountNoun(context), context.econInfo and context.econInfo.label or 'selected economy'))
            end
            local top = S.retainedResult[1]
            vcProvider.bestProfit = top and top.avgProfit
            return vcProvider.bestProfit
        end

        if S.buildState and S.buildState.running then
            local wasBackground = S.buildState.background == true
            local priority = H.buildVCPriority(context)
            local prioChanged = S.buildState.priorityKey ~= priority.key
            if S.evaluation then
                S.evaluation.background = false
                S.evaluation.priority = priority
            end
            local VC = ns[spec.modelName]
            if wasBackground or not S.buildState.onProgress or not S.buildState.onTierReady then
                local onProgress, onComplete, onTierReady = H.makeForegroundHandlers(S.generation)
                if VC and type(VC.Attach) == 'function' then
                    VC.Attach(S.buildState, false, priority, onProgress, onComplete, onTierReady)
                else
                    S.buildState.background = false
                    S.buildState.onProgress = onProgress
                    S.buildState.onComplete = onComplete
                    S.buildState.onTierReady = onTierReady
                    if VC and type(VC.Reprioritize) == 'function' then
                        VC.Reprioritize(S.buildState, priority)
                    end
                end
            elseif VC and type(VC.Attach) == 'function' then
                VC.Attach(S.buildState, false, priority)
            elseif VC and type(VC.Reprioritize) == 'function' then
                VC.Reprioritize(S.buildState, priority)
            end
            local earlyStale = (S.earlyPresentedFilterKey ~= nil and S.earlyPresentedFilterKey ~= fKey)
            if earlyStale then
                S.earlyPresentedFilterKey = nil
                S.earlyBoundResult = nil
                S.earlyCountShown = nil
            end
            local inflight = S.inFlightPresent
            if S.earlyPresentedFilterKey == fKey and S.earlyBoundResult then
                S.presentSeq = S.presentSeq + 1
                S.inFlightPresent = nil
                local currentWidth = (S.host and S.host.parent and S.host.parent:GetWidth()) or S.view:GetWidth()
                if S.boundWidth ~= currentWidth then
                    S.boundWidth = currentWidth
                    vcProvider.Layout(currentWidth)
                    S.tbl.updateHeaders()
                end
                if S.viewWasHidden then
                    S.viewWasHidden = false
                    H.rebindStaleRows()
                end
                local doneNow = S.buildState.scanned or #(S.buildState.rows or {})
                local totalNow = #(S.buildState.order or {})
                if S.view and S.view.summary then
                    local warmLabel = H.isOnlyProfitable(context) and 'profitable' or 'crafts'
                    S.view.summary:SetText(string.format('%d %s (warming %d/%d)', #S.earlyBoundResult, warmLabel, doneNow, totalNow))
                end
            elseif S.buildState.tier1Authoritative and S.buildState.index and S.buildState.tier1Target
                and S.buildState.index > S.buildState.tier1Target then
                if not (inflight and inflight.warmTotal ~= nil and inflight.sig == sig
                    and inflight.metaEpoch == S.metaEpoch and inflight.fKey == fKey) then
                    S.buildState.tier1Notified = true
                    if S.buildState.onTierReady then
                        S.buildState.onTierReady(S.buildState.rows, S.buildState.scanned or #(S.buildState.rows or {}), #(S.buildState.order or {}))
                    end
                end
            elseif wasBackground or prioChanged or earlyStale or (S.buildState.tier1Notified and not S.earlyBoundResult) then
                S.presentSeq = S.presentSeq + 1
                S.inFlightPresent = nil
                if S.view and S.view.summary then
                    local doneNow = S.buildState.scanned or 0
                    local totalNow = #(S.buildState.order or {})
                    local scanLabel = H.isOnlyProfitable(context) and 'profitable' or 'matched'
                    S.view.summary:SetText(string.format('Scanning %s: %d / %d (%d %s)', spec.craftWordPlural, doneNow, totalNow, #(S.buildState.rows or {}), scanLabel))
                end
            end
            return vcProvider.bestProfit
        end

        local inflight = S.inFlightPresent
        if S.buildState and S.buildState.completed and S.rows and inflight
            and inflight.sig == sig and inflight.metaEpoch == S.metaEpoch
            and inflight.fKey == fKey and inflight.dataRows == S.rows then
            return vcProvider.bestProfit
        end
        S.presentSeq = S.presentSeq + 1
        S.inFlightPresent = nil
        if S.buildState and S.buildState.completed and S.rows and fKey ~= S.boundFilterKey and S.view and S.view.summary then
            S.view.summary:SetText('Filtering ' .. spec.craftWordPlural .. '...')
        end

        if S.pending or S.cancelBuild then return vcProvider.bestProfit end
        S.pending = true
        local scheduledGen = S.generation
        local function kickoff()
            if scheduledGen ~= S.generation then return end
            S.pending = false
            if not H.active() then return end
            if S.buildState and S.buildState.completed then
                S.rows = S.rows or S.buildState.rows
                H.present()
                return
            end
            local token = S.generation
            if S.evaluation then
                S.evaluation.background = false
                S.evaluation.priority = H.buildVCPriority(S.latest)
            end
            if S.buildState and not S.buildState.completed then
                local kCol, kAsc = H.resolveSort()
                local kFKey = H.buildFilterKey(S.latest, kCol, kAsc)
                if not (S.earlyPresentedFilterKey == kFKey and S.earlyBoundResult) then
                    S.buildState.tier1Notified = false
                end
            end
            if S.view.emptyText and S.view.emptyText.Hide then S.view.emptyText:Hide() end
            if S.view.summary then S.view.summary:SetText('Scanning ' .. spec.craftWordPlural .. '...') end
            local onProgress, rawOnComplete, onTierReady = H.makeForegroundHandlers(token)
            local finished = false
            local function onComplete(result)
                finished = true
                rawOnComplete(result)
            end
            local model = ns[spec.modelName]
            if model and model.Start then
                local cancel, state = model.Start(S.evaluation, onProgress, onComplete, S.buildState, onTierReady)
                S.buildState = state
                if not finished and token == S.generation then S.cancelBuild = cancel end
            else
                onComplete({})
            end
        end
        H.laterGuarded(kickoff)
        return vcProvider.bestProfit
    end

    function H.buildRow1(v, T)
        local bar = CreateFrame('Frame', nil, v)
        bar:SetPoint('TOPLEFT', 0, 0)
        bar:SetPoint('TOPRIGHT', 0, 0)
        bar:SetHeight(40)
        v.headerBar = bar
        local barSep = bar:CreateTexture(nil, 'BORDER')
        barSep:SetPoint('BOTTOMLEFT', 0, 0)
        barSep:SetPoint('BOTTOMRIGHT', 0, 0)
        barSep:SetHeight(1)
        v.barSep = barSep

        local hdrTitle = bar:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        hdrTitle:SetPoint('LEFT', 16, 0)
        applyFont(hdrTitle, 15, 'semibold')
        hdrTitle:SetText(spec.title)
        hdrTitle:SetWordWrap(false)
        v.hdrTitle = hdrTitle

        v.profPills = {}
        local prevPill = nil
        for _, pd in ipairs(PROF_PILLS) do
            local pw = math.max(28, #pd.label * 7 + 14)
            local pb = CreateFrame('Button', nil, bar)
            pb:SetSize(pw, 22)
            if not prevPill then
                pb:SetPoint('LEFT', hdrTitle, 'RIGHT', 12, 0)
            else
                pb:SetPoint('LEFT', prevPill, 'RIGHT', 4, 0)
            end
            pb.key = pd.key
            if type(T) == 'table' and type(T.RoundRect) == 'function' and type(T.ASSETS) == 'table' and T.ASSETS.pill_fill then
                pb.bg = T.RoundRect(pb, pb, 'BACKGROUND', 0, 11, 0, 0.47, 0.47, 0.50, 0.12, T.ASSETS.pill_fill)
            else
                local track = (getThemePalette() or {}).pillTrack or {0.47, 0.47, 0.50, 0.12}
                local tbg = pb:CreateTexture(nil, 'BACKGROUND')
                tbg:SetAllPoints()
                tbg:SetColorTexture(track[1], track[2], track[3], track[4] or 0.12)
            end
            pb.fs = pb:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
            pb.fs:SetAllPoints()
            pb.fs:SetJustifyH('CENTER')
            pb.fs:SetWordWrap(false)
            applyFont(pb.fs, 11, 'regular')
            pb.fs:SetText(pd.label)
            pb:SetScript('OnClick', function()
                local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
                if db then
                    if db.profFilter == pd.key and pd.key ~= 'all' then db.profFilter = 'all' else db.profFilter = pd.key end
                end
                if S.latest then S.latest.profFilter = (db and db.profFilter) or pd.key end
                H.updateProfPills(db and db.profFilter or pd.key)
                H.triggerRefresh()
            end)
            v.profPills[#v.profPills + 1] = pb
            prevPill = pb
        end

        v.colSettingsBtn = T.CreatePlateButton(bar, '', 28, 26, {variant='secondary', pill=true, icon=(T and T.ASSETS and T.ASSETS.icon_gear) or 'gear', iconSize=13})
        v.colSettingsBtn:SetPoint('RIGHT', bar, 'RIGHT', -12, 0)
        v.colSettingsBtn:SetScript('OnClick', function() vcProvider.ToggleColumnSettings() end)
        v.colSettingsBtn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMLEFT')
            GameTooltip:AddLine('Customize Columns', 1, 0.82, 0)
            GameTooltip:AddLine('Show, hide, and reorder ' .. spec.title .. ' columns.', 1, 1, 1, true)
            H.liftAndShowTooltip()
        end)
        v.colSettingsBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

        v.shopButton = T.CreatePlateButton(bar, 'Shopping List', 116, 26, {variant='secondary', pill=true})
        v.shopButton:SetPoint('RIGHT', v.colSettingsBtn, 'LEFT', -6, 0)
        v.shopButton:SetScript('OnClick', function() if S.host and S.host.toggleShoppingWindow then S.host.toggleShoppingWindow(true) end end)

        v.resetButton = T.CreatePlateButton(bar, 'Reset Filters', 92, 26, {variant='secondary', pill=true})
        v.resetButton:SetPoint('RIGHT', v.shopButton, 'LEFT', -6, 0)
        v.resetButton:SetScript('OnClick', H.resetFilters)

        v.filtersButton = T.CreatePlateButton(bar, 'Filters', 78, 26, {variant='secondary', pill=true, icon=T.ASSETS and T.ASSETS.icon_bars, iconSize=11})
        v.filtersButton:SetPoint('RIGHT', v.resetButton, 'LEFT', -6, 0)
        v.filtersButton:SetScript('OnClick', function(self)
            if S.host and S.host.toggleScreenFilters then S.host.toggleScreenFilters(self) end
        end)

        local badgePill = (type(T) == 'table' and type(T.CreateBadgePill) == 'function')
            and T.CreateBadgePill(bar, 'Quick-Add Mode', 'blue', {height=22, fontSize=11, padX=14}) or nil
        local shiftBadge = badgePill and badgePill.frame or CreateFrame('Frame', nil, bar)
        shiftBadge._pill = badgePill
        if not badgePill then
            shiftBadge:SetSize(102, 22)
            shiftBadge.label = shiftBadge:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
            shiftBadge.label:SetAllPoints()
            shiftBadge.label:SetText('Quick-Add Mode')
        end
        shiftBadge:SetPoint('RIGHT', v.filtersButton, 'LEFT', -8, 0)
        shiftBadge:Hide()
        v.shiftBadge = shiftBadge

        v.summaryLeftAnchor = prevPill
        v.summary = bar:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
        applyFont(v.summary, 11, 'regular')
        if T and T.AutoThemeText then T.AutoThemeText(v.summary) end
        v.summary:SetJustifyH('RIGHT')
        v.summary:SetWordWrap(false)
        H.updateShiftHeader()
    end

    function H.buildRow2(v, T)
        local row2 = CreateFrame('Frame', nil, v)
        row2:SetPoint('TOPLEFT', 0, -40)
        row2:SetPoint('TOPRIGHT', 0, -40)
        row2:SetHeight(36)
        v.legacyBar = row2
        v._row2Height = 36
        v._row2Subrows = 1
        v.row2LeftBtns = {}

        local row2Sep = row2:CreateTexture(nil, 'BORDER')
        row2Sep:SetPoint('BOTTOMLEFT', 0, 0)
        row2Sep:SetPoint('BOTTOMRIGHT', 0, 0)
        row2Sep:SetHeight(1)
        v.row2Sep = row2Sep

        local function addLeftBtn(btn, w)
            btn._pillW = w
            local n = #v.row2LeftBtns
            if n == 0 then
                btn:SetPoint('TOPLEFT', row2, 'TOPLEFT', 16, -6)
            else
                btn:SetPoint('LEFT', v.row2LeftBtns[n], 'RIGHT', 6, 0)
            end
            v.row2LeftBtns[n + 1] = btn
        end

        if spec.showMasterChef ~= false then
            v.masterChefBtn = T.CreatePlateButton(row2, 'Master Chef: Auto (0/5)', 146, 24, {variant='secondary', pill=true, dropdown=true, fontSize=11})
            addLeftBtn(v.masterChefBtn, 146)
            v.masterChefBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
            v.masterChefBtn:SetScript('OnClick', function(self, button)
                local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
                if not db then return end
                if button == 'RightButton' then
                    db[dbPrefix .. 'MasterChef'] = 'auto'
                    if S.latest then S.latest.masterChefMode = 'auto' end
                    H.syncLegacyControls(S.latest)
                    H.triggerRefresh()
                    return
                end
                local leg = H.resolveLegacy(S.latest)
                local opts = {
                    {key='auto', label=string.format('Auto (Live %d/5)', leg.liveMasterChef)},
                    {key=0, label='0/5 (0%)'},
                    {key=1, label='1/5 (+10%)'},
                    {key=2, label='2/5 (+20%)'},
                    {key=3, label='3/5 (+30%)'},
                    {key=4, label='4/5 (+40%)'},
                    {key=5, label='5/5 (+50%)'},
                }
                local cur = leg.masterChefAuto and 'auto' or leg.masterChef
                ns.Theme.OpenDropDown(self, opts, cur, function(key)
                    db[dbPrefix .. 'MasterChef'] = key
                    if S.latest then S.latest.masterChefMode = key end
                    H.syncLegacyControls(S.latest)
                    H.triggerRefresh()
                end, 168)
            end)
            v.masterChefBtn:SetScript('OnEnter', function(self)
                GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
                GameTooltip:AddLine('Master Chef Legacy Perk (Cooking)', 1, 0.82, 0)
                GameTooltip:AddLine('+10% chance per rank (0-5) to double Cooking craft output, up to +50% expected vendor revenue at 5/5.', 1, 1, 1, true)
                GameTooltip:AddLine('Right-click: reset to Auto (live character rank).', 0.7, 0.9, 1)
                H.liftAndShowTooltip()
            end)
            v.masterChefBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
        elseif spec.showArcaneSalvager then
            v.arcaneSalvagerBtn = T.CreatePlateButton(row2, 'Salvager: Off', 116, 24, {variant='secondary', pill=true, fontSize=11})
            addLeftBtn(v.arcaneSalvagerBtn, 116)
            v.arcaneSalvagerBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
            v.arcaneSalvagerBtn:SetScript('OnClick', function(self, button)
                local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
                if not db then return end
                local nextVal = (button ~= 'RightButton') and (not (db[dbPrefix .. 'ArcaneSalvager'] == true)) or false
                db[dbPrefix .. 'ArcaneSalvager'] = nextVal
                if S.latest then S.latest.arcaneSalvager = nextVal end
                H.syncLegacyControls(S.latest)
                H.triggerRefresh()
            end)
            v.arcaneSalvagerBtn:SetScript('OnEnter', function(self)
                GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
                GameTooltip:AddLine('Arcane Salvager (+20% Bonus Loot)', 1, 0.82, 0)
                GameTooltip:AddLine('Applies the ~20% expected extra disenchant loot from a deployed Arcane Salvager.', 1, 1, 1, true)
                GameTooltip:AddLine('Right-click: turn Off.', 0.7, 0.9, 1)
                H.liftAndShowTooltip()
            end)
            v.arcaneSalvagerBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
        end

        v.barteringBtn = T.CreatePlateButton(row2, 'Barter: Auto (0/2)', 126, 24, {variant='secondary', pill=true, dropdown=true, fontSize=11})
        addLeftBtn(v.barteringBtn, 126)
        v.barteringBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        v.barteringBtn:SetScript('OnClick', function(self, button)
            local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
            if not db then return end
            if button == 'RightButton' then
                db[dbPrefix .. 'Bartering'] = 'auto'
                if S.latest then S.latest.barteringMode = 'auto' end
                H.syncLegacyControls(S.latest)
                H.triggerRefresh()
                return
            end
            local leg = H.resolveLegacy(S.latest)
            local opts = {
                {key='auto', label=string.format('Auto (Live %d/2)', leg.liveBartering)},
                {key=0, label='0/2 (0%)'},
                {key=1, label='1/2 (-5%)'},
                {key=2, label='2/2 (-10%)'},
            }
            local cur = leg.barteringAuto and 'auto' or leg.bartering
            ns.Theme.OpenDropDown(self, opts, cur, function(key)
                db[dbPrefix .. 'Bartering'] = key
                if S.latest then S.latest.barteringMode = key end
                H.syncLegacyControls(S.latest)
                H.triggerRefresh()
            end, 156)
        end)
        v.barteringBtn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
            GameTooltip:AddLine('Bartering Legacy Perk (NPC Vendors)', 1, 0.82, 0)
            GameTooltip:AddLine('-5% per rank (0-2) on NPC vendor reagent buy prices, up to -10% at 2/2.', 1, 1, 1, true)
            GameTooltip:AddLine('Stacks multiplicatively with Honored -10% for up to -19% total vendor savings.', 0.8, 0.9, 1, true)
            GameTooltip:AddLine('Right-click: reset to Auto (live character rank).', 0.7, 0.9, 1)
            H.liftAndShowTooltip()
        end)
        v.barteringBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

        v.honoredBtn = T.CreatePlateButton(row2, 'Honored -10%', 96, 24, {variant='secondary', pill=true, fontSize=11})
        addLeftBtn(v.honoredBtn, 96)
        v.honoredBtn:SetScript('OnClick', function()
            local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
            if not db then return end
            local nextVal = not (db[dbPrefix .. 'Honored'] == true)
            db[dbPrefix .. 'Honored'] = nextVal
            if S.latest then S.latest.honoredDiscount = nextVal end
            H.syncLegacyControls(S.latest)
            H.triggerRefresh()
        end)
        v.honoredBtn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
            GameTooltip:AddLine('Honored Reputation Discount (-10%)', 1, 0.82, 0)
            GameTooltip:AddLine('Applies the 10% Honored faction reputation discount to NPC vendor reagents.', 1, 1, 1, true)
            GameTooltip:AddLine('Stacks multiplicatively with Bartering: 0.90 x 0.90 = 0.81 (-19% total discount at 2/2 Bartering + Honored).', 0.8, 0.9, 1, true)
            GameTooltip:AddLine('Note: The old PvP Rank 3 vendor discount was removed in WoW: Forever.', 1, 0.78, 0.35, true)
            H.liftAndShowTooltip()
        end)
        v.honoredBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

        v.moatFilterBtn = T.CreatePlateButton(row2, 'All Moats', 116, 24, {variant='secondary', pill=true, dropdown=true, fontSize=11})
        addLeftBtn(v.moatFilterBtn, 116)
        v.moatFilterBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        v.moatFilterBtn:SetScript('OnClick', function(self, button)
            local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
            if not db then return end
            if button == 'RightButton' then
                db[dbPrefix .. 'MoatFilter'] = 'all'
                if S.latest then S.latest.moatFilter = 'all' end
                H.syncLegacyControls(S.latest)
                H.triggerRefresh()
                return
            end
            local cur = db[dbPrefix .. 'MoatFilter'] or 'all'
            ns.Theme.OpenDropDown(self, C.MOAT_FILTERS, cur, function(key)
                db[dbPrefix .. 'MoatFilter'] = key
                if S.latest then S.latest.moatFilter = key end
                H.syncLegacyControls(S.latest)
                H.triggerRefresh()
            end, 168)
        end)
        v.moatFilterBtn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
            GameTooltip:AddLine('Buy Moat Depth Filter', 1, 0.82, 0)
            GameTooltip:AddLine('Filter recipes by reagent depth: Infinite (all vendor), Deep (50+ crafts), Steady (15+ crafts), Thin, or Moment (flash dips / <5 crafts).', 1, 1, 1, true)
            GameTooltip:AddLine('Right-click: All Moats.', 0.7, 0.9, 1)
            H.liftAndShowTooltip()
        end)
        v.moatFilterBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

        v.yieldModeBtn = T.CreatePlateButton(row2, 'Yield: Auto', 114, 24, {variant='secondary', pill=true, dropdown=true, fontSize=11})
        addLeftBtn(v.yieldModeBtn, 114)
        v.yieldModeBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        v.yieldModeBtn:SetScript('OnClick', function(self, button)
            local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
            if not db then return end
            if button == 'RightButton' then
                db[dbPrefix .. 'YieldMode'] = 'auto'
                if S.latest then S.latest.yieldMode = 'auto' end
                H.syncLegacyControls(S.latest)
                H.triggerRefresh()
                return
            end
            local cur = db[dbPrefix .. 'YieldMode'] or 'auto'
            ns.Theme.OpenDropDown(self, C.YIELD_MODES, cur, function(key)
                db[dbPrefix .. 'YieldMode'] = key
                if S.latest then S.latest.yieldMode = key end
                H.syncLegacyControls(S.latest)
                H.triggerRefresh()
            end, 176)
        end)
        v.yieldModeBtn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
            GameTooltip:AddLine('Variable Craft Yield Mode', 1, 0.82, 0)
            GameTooltip:AddLine('Auto (Ledger): Uses measured Ledger roll average once >=10 casts are logged, else midpoint of min..max.', 1, 1, 1, true)
            GameTooltip:AddLine('Uniform: Always uses midpoint (min+max)/2. Min (Safe): Worst-case minimum output. Measured: Prefers Ledger avg immediately.', 0.8, 0.9, 1, true)
            GameTooltip:AddLine('Right-click: reset to Auto (Ledger).', 0.7, 0.9, 1)
            H.liftAndShowTooltip()
        end)
        v.yieldModeBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

        if spec.mode == 'disenchant' then
            v.onlyProfitableBtn = T.CreatePlateButton(row2, 'Profitable Only', 98, 24, {variant='secondary', pill=true, fontSize=11})
            addLeftBtn(v.onlyProfitableBtn, 98)
            v.onlyProfitableBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
            v.onlyProfitableBtn:SetScript('OnClick', function(_, button)
                local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
                if not db then return end
                local nextVal = (button ~= 'RightButton') and (not (db[dbPrefix .. 'OnlyProfitable'] == true)) or false
                db[dbPrefix .. 'OnlyProfitable'] = nextVal
                if S.latest then S.latest.onlyProfitable = nextVal end
                H.syncLegacyControls(S.latest)
                H.triggerRefresh()
            end)
            v.onlyProfitableBtn:SetScript('OnEnter', function(self)
                GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
                GameTooltip:AddLine('Profitable Only Filter', 1, 0.82, 0)
                GameTooltip:AddLine('When active, shows only disenchantable crafts with positive expected profit (Avg Profit > 0).', 1, 1, 1, true)
                GameTooltip:AddLine('Right-click: turn Off.', 0.7, 0.9, 1)
                H.liftAndShowTooltip()
            end)
            v.onlyProfitableBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

            v.showNonDEBtn = T.CreatePlateButton(row2, 'All Craftable', 88, 24, {variant='secondary', pill=true, fontSize=11})
            addLeftBtn(v.showNonDEBtn, 88)
            v.showNonDEBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
            v.showNonDEBtn:SetScript('OnClick', function(_, button)
                local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
                if not db then return end
                local nextVal = (button ~= 'RightButton') and (not (db[dbPrefix .. 'ShowNonDE'] == true)) or false
                db[dbPrefix .. 'ShowNonDE'] = nextVal
                if S.latest then S.latest.showNonDE = nextVal end
                H.syncLegacyControls(S.latest)
                H.triggerRefresh()
            end)
            v.showNonDEBtn:SetScript('OnEnter', function(self)
                GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
                GameTooltip:AddLine('Include All Craftable Recipes', 1, 0.82, 0)
                GameTooltip:AddLine('Includes non-disenchantable items and enchants alongside disenchantable gear (labeled Non-DE).', 1, 1, 1, true)
                GameTooltip:AddLine('Right-click: turn Off.', 0.7, 0.9, 1)
                H.liftAndShowTooltip()
            end)
            v.showNonDEBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
        end

        v.legacyInfoBtn = T.CreatePlateButton(row2, 'Legacy Info', 82, 24, {variant='secondary', pill=true, fontSize=11})
        v.legacyInfoBtn._pillW = 82
        v.legacyInfoBtn:SetPoint('TOPRIGHT', row2, 'TOPRIGHT', -12, -6)
        v.legacyInfoBtn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMLEFT')
            GameTooltip:AddLine('WoW: Forever Legacy Perk Audit (21 Perks)', 1, 0.82, 0)
            if spec.showMasterChef ~= false then
                GameTooltip:AddLine('Active in Vendor Crafter (2 of 21):', 0.30, 0.90, 0.45)
                GameTooltip:AddLine('- Master Chef (0-5): +10%/rank chance to double Cooking yield (+50% EV at 5/5).', 1, 1, 1, true)
                GameTooltip:AddLine('- Bartering (0-2): -5%/rank NPC vendor buy cost (-10% at 2/2; -19% with Honored -10%).', 1, 1, 1, true)
            else
                GameTooltip:AddLine('Active in Disenchantment Crafter (1 of 21):', 0.30, 0.90, 0.45)
                GameTooltip:AddLine('- Bartering (0-2): -5%/rank NPC vendor buy cost (-10% at 2/2; -19% with Honored -10%).', 1, 1, 1, true)
            end
            GameTooltip:AddLine(' ')
            GameTooltip:AddLine('No Effect on Craft Gold (Remaining Perks):', 0.85, 0.85, 0.85)
            GameTooltip:AddLine('Working Overtime, Bountiful Harvest, Luremaster, Performance Bonus, Dedicated Study, Reagent Economy, Diplomat, Frequent Flier, and the remaining Legacy perks do not alter disenchant/vendor reagent buy costs or output values.', 0.78, 0.84, 0.90, true)
            H.liftAndShowTooltip()
        end)
        v.legacyInfoBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    end

    function H.buildRow3(v, T)
        local planBar = CreateFrame('Frame', nil, v)
        planBar:SetPoint('TOPLEFT', 0, -76)
        planBar:SetPoint('TOPRIGHT', 0, -76)
        planBar:SetHeight(34)
        v.planBar = planBar

        local row3Sep = planBar:CreateTexture(nil, 'BORDER')
        row3Sep:SetPoint('BOTTOMLEFT', 0, 0)
        row3Sep:SetPoint('BOTTOMRIGHT', 0, 0)
        row3Sep:SetHeight(1)
        v.row3Sep = row3Sep

        v.topNBtn = T.CreatePlateButton(planBar, 'Plan: Top 10', 96, 24, {variant='secondary', pill=true, dropdown=true, fontSize=11})
        v.topNBtn:SetPoint('LEFT', planBar, 'LEFT', 16, 0)
        v.topNBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        v.topNBtn:SetScript('OnClick', function(self, button)
            local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
            if not db then return end
            if button == 'RightButton' then
                db[dbPrefix .. 'TopN'] = 10
                if S.latest then S.latest.topN = 10 end
                H.syncPlanControls(S.latest)
                H.triggerRefresh()
                return
            end
            local cur = (db[dbPrefix .. 'TopN'] ~= nil) and db[dbPrefix .. 'TopN'] or 10
            ns.Theme.OpenDropDown(self, C.TOP_N_OPTIONS, cur, function(key)
                db[dbPrefix .. 'TopN'] = key
                if S.latest then S.latest.topN = key end
                H.syncPlanControls(S.latest)
                H.triggerRefresh()
            end, 132)
        end)
        v.topNBtn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
            GameTooltip:AddLine('Profit Maximizer Portfolio Size', 1, 0.82, 0)
            GameTooltip:AddLine('Allocates shared AH reagent lots across the Top N recipes in two passes, reclaiming shared lots from lower-ranked recipes.', 1, 1, 1, true)
            GameTooltip:AddLine('Right-click: reset to Top 10.', 0.7, 0.9, 1)
            H.liftAndShowTooltip()
        end)
        v.topNBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

        v.maxCraftsBtn = T.CreatePlateButton(planBar, 'Cap: Max', 116, 24, {variant='secondary', pill=true, dropdown=true, fontSize=11})
        v.maxCraftsBtn:SetPoint('LEFT', v.topNBtn, 'RIGHT', 8, 0)
        v.maxCraftsBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        v.maxCraftsBtn:SetScript('OnClick', function(self, button)
            local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
            if not db then return end
            if button == 'RightButton' then
                db[dbPrefix .. 'MaxCrafts'] = 0
                if S.latest then S.latest.maxCraftsPerRecipe = 0 end
                H.syncPlanControls(S.latest)
                H.triggerRefresh()
                return
            end
            local cur = tonumber(db[dbPrefix .. 'MaxCrafts']) or 0
            ns.Theme.OpenDropDown(self, C.MAX_CRAFTS_OPTIONS, cur, function(key)
                db[dbPrefix .. 'MaxCrafts'] = key
                if S.latest then S.latest.maxCraftsPerRecipe = key end
                H.syncPlanControls(S.latest)
                H.triggerRefresh()
            end, 136)
        end)
        v.maxCraftsBtn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
            GameTooltip:AddLine('Max Crafts Per Recipe Cap', 1, 0.82, 0)
            GameTooltip:AddLine('Limits how many crafts the Profit Maximizer queues per recipe (Vendor Loops default to 500x when set to Max).', 1, 1, 1, true)
            GameTooltip:AddLine('Right-click: reset to Cap: Max.', 0.7, 0.9, 1)
            H.liftAndShowTooltip()
        end)
        v.maxCraftsBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

        v.budgetBtn = T.CreatePlateButton(planBar, 'Budget: Unlim', 112, 24, {variant='secondary', pill=true, dropdown=true, fontSize=11})
        v.budgetBtn:SetPoint('LEFT', v.maxCraftsBtn, 'RIGHT', 8, 0)
        v.budgetBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        v.budgetBtn:SetScript('OnClick', function(self, button)
            local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
            if not db then return end
            if button == 'RightButton' then
                db[dbPrefix .. 'Budget'] = 0
                if S.latest then S.latest.budgetCopper = 0 end
                H.syncPlanControls(S.latest)
                H.triggerRefresh()
                return
            end
            local cur = tonumber(db[dbPrefix .. 'Budget']) or 0
            ns.Theme.OpenDropDown(self, C.BUDGET_OPTIONS, cur, function(key)
                db[dbPrefix .. 'Budget'] = key
                if S.latest then S.latest.budgetCopper = key end
                H.syncPlanControls(S.latest)
                H.triggerRefresh()
            end, 140)
        end)
        v.budgetBtn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
            GameTooltip:AddLine('Portfolio Spend Budget', 1, 0.82, 0)
            GameTooltip:AddLine('Caps total copper spent on AH and NPC reagents across the active Profit Maximizer plan.', 1, 1, 1, true)
            GameTooltip:AddLine('Right-click: reset to Unlimited.', 0.7, 0.9, 1)
            H.liftAndShowTooltip()
        end)
        v.budgetBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

        v.topOnlyBtn = T.CreatePlateButton(planBar, 'Top 10 Only', 88, 24, {variant='secondary', pill=true, fontSize=11})
        v.topOnlyBtn:SetPoint('LEFT', v.budgetBtn, 'RIGHT', 8, 0)
        v.topOnlyBtn:SetScript('OnClick', function()
            local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
            if not db then return end
            local nextVal = not (db[dbPrefix .. 'TopOnly'] == true)
            db[dbPrefix .. 'TopOnly'] = nextVal
            if S.latest then S.latest.topOnly = nextVal end
            H.syncPlanControls(S.latest)
            H.triggerRefresh()
        end)
        v.topOnlyBtn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMRIGHT')
            GameTooltip:AddLine('Filter to Top-N Plan Only', 1, 0.82, 0)
            GameTooltip:AddLine('Shows only the recipes selected in the active Profit Maximizer plan, ranked by realizable profit.', 1, 1, 1, true)
            H.liftAndShowTooltip()
        end)
        v.topOnlyBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

        v.queuePlanBtn = T.CreatePlateButton(planBar, '+ Queue Plan', 118, 24, {variant='primary', pill=true, fontSize=11, readableDisabled=true})
        v.queuePlanBtn:SetPoint('RIGHT', planBar, 'RIGHT', -12, 0)
        if v.queuePlanBtn.SetEnabled then v.queuePlanBtn:SetEnabled(false) end
        v.queuePlanBtn:SetScript('OnClick', function()
            local plan = S.activePlan
            if not plan or type(plan.entries) ~= 'table' or #plan.entries == 0 then return end
            if S.host and type(S.host[spec.hostQueueFn]) == 'function' then
                S.host[spec.hostQueueFn](plan.entries)
                vcProvider.RepaintVisible()
            end
        end)
        v.queuePlanBtn:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOMLEFT')
            GameTooltip:AddLine('Queue Active Profit Plan', 1, 0.82, 0)
            local plan = S.activePlan
            if type(plan) == 'table' and type(plan.entries) == 'table' and #plan.entries > 0 then
                GameTooltip:AddLine('Adds all optimal craft counts from the active plan into the shared Shopping List.', 1, 1, 1, true)
                GameTooltip:AddLine(H.formatPlanSummary(plan), 0.30, 0.90, 0.45, true)
            else
                GameTooltip:AddLine('No profitable plan entries are currently available to queue.', 0.8, 0.8, 0.8, true)
            end
            H.liftAndShowTooltip()
        end)
        v.queuePlanBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

        local planSummaryFs = planBar:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
        planSummaryFs:SetPoint('LEFT', v.topOnlyBtn, 'RIGHT', 10, 0)
        planSummaryFs:SetPoint('RIGHT', v.queuePlanBtn, 'LEFT', -10, 0)
        planSummaryFs:SetJustifyH('LEFT')
        planSummaryFs:SetWordWrap(false)
        applyFont(planSummaryFs, 11, 'regular')
        if T and T.AutoThemeText then T.AutoThemeText(planSummaryFs) end
        planSummaryFs:SetText('No active plan')
        v.planSummaryFs = planSummaryFs
    end

    function H.buildColumnPopover(v, T)
        local chevPath = (T and T.ASSETS and T.ASSETS.icon_chevron_down) or (uiCache.appleRoot .. 'icon_chevron_down')
        local checkIconPath = (T and T.ASSETS and T.ASSETS.icon_check) or (uiCache.appleRoot .. 'icon_check')
        local pillTexPath = T and T.ASSETS and T.ASSETS.pill_fill
        local pop = CreateFrame('Frame', nil, v)
        pop:SetSize(264, 38 + 20 + #C.VENDOR_COLUMNS * 24)
        pop:SetPoint('TOPRIGHT', v.colSettingsBtn, 'BOTTOMRIGHT', 0, -6)
        if pop.SetFrameStrata then pop:SetFrameStrata('DIALOG') end
        if v.GetFrameLevel and pop.SetFrameLevel then pop:SetFrameLevel((v:GetFrameLevel() or 1) + 40) end
        if pop.EnableMouse then pop:EnableMouse(true) end
        pop:Hide()
        pop.rows = {}
        pop._built = false
        v._ensureColumnPopoverBuilt = function()
            if not pop or pop._built then return end
            pop._built = true
            if type(T) == 'table' and type(T.NineApple) == 'function' then
                pop.surface = T.NineApple(pop, 'glass_r12', 'cardBg', 'borderStrong', {layer='BACKGROUND', sub=-1, noSpecular=true})
            end
            pop.title = pop:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
            pop.title:SetPoint('TOPLEFT', pop, 'TOPLEFT', 14, -12)
            applyFont(pop.title, 13, 'semibold')
            pop.title:SetText('Customize Columns')
            pop.title:SetWordWrap(false)
            pop.closeBtn = T.CreatePlateButton(pop, '', 22, 22, {variant='ghost', pill=true, icon=(T and T.ASSETS and T.ASSETS.icon_close) or 'close', iconSize=11})
            pop.closeBtn:SetPoint('TOPRIGHT', pop, 'TOPRIGHT', -10, -8)
            pop.closeBtn:SetScript('OnClick', function() vcProvider.ToggleColumnSettings(false) end)
            pop.resetBtn = T.CreatePlateButton(pop, 'Reset', 50, 22, {variant='secondary', pill=true, fontSize=11})
            pop.resetBtn:SetPoint('RIGHT', pop.closeBtn, 'LEFT', -6, 0)
            pop.resetBtn:SetScript('OnClick', function() vcProvider.ResetColumns() end)
            pop.sep = pop:CreateTexture(nil, 'BORDER')
            pop.sep:SetPoint('TOPLEFT', pop, 'TOPLEFT', 10, -38)
            pop.sep:SetPoint('TOPRIGHT', pop, 'TOPRIGHT', -10, -38)
            pop.sep:SetHeight(1)
            for idx = 1, #C.VENDOR_COLUMNS do
                local row = CreateFrame('Frame', nil, pop)
                row:SetHeight(24)
                row:SetPoint('TOPLEFT', pop, 'TOPLEFT', 10, -48 - (idx - 1) * 24)
                row:SetPoint('TOPRIGHT', pop, 'TOPRIGHT', -10, -48 - (idx - 1) * 24)

                local chk = CreateFrame('Button', nil, row)
                chk:SetSize(16, 16)
                chk:SetPoint('LEFT', row, 'LEFT', 4, 0)
                if type(T) == 'table' and type(T.RoundRect) == 'function' and pillTexPath then
                    chk.bg = T.RoundRect(chk, chk, 'BACKGROUND', 0, 5, 0, 0.47, 0.47, 0.50, 0.16, pillTexPath)
                else
                    chk.bg = chk:CreateTexture(nil, 'BACKGROUND')
                    chk.bg:SetAllPoints()
                    chk.bg:SetColorTexture(0.47, 0.47, 0.50, 0.16)
                end
                chk.tick = chk:CreateTexture(nil, 'OVERLAY', nil, 1)
                chk.tick:SetSize(10, 10)
                chk.tick:SetPoint('CENTER', 0, 0)
                chk.tick:SetTexture(checkIconPath)
                chk:SetScript('OnClick', function()
                    local k = row._colKey
                    if not k or k == 'name' then return end
                    local cfg = H.normalizeColumnConfig(H.getColumnDB())
                    vcProvider.SetColumnVisible(k, cfg.hidden[k] == true)
                end)

                local downBtn = CreateFrame('Button', nil, row)
                downBtn:SetSize(20, 20)
                downBtn:SetPoint('RIGHT', row, 'RIGHT', -2, 0)
                downBtn.icon = downBtn:CreateTexture(nil, 'ARTWORK')
                downBtn.icon:SetSize(10, 10)
                downBtn.icon:SetPoint('CENTER', 0, 0)
                downBtn.icon:SetTexture(chevPath)
                if downBtn.icon.SetTexCoord then downBtn.icon:SetTexCoord(0, 1, 0, 1) end
                downBtn:SetScript('OnClick', function()
                    if row._colKey then vcProvider.MoveColumn(row._colKey, 1) end
                end)

                local upBtn = CreateFrame('Button', nil, row)
                upBtn:SetSize(20, 20)
                upBtn:SetPoint('RIGHT', downBtn, 'LEFT', -2, 0)
                upBtn.icon = upBtn:CreateTexture(nil, 'ARTWORK')
                upBtn.icon:SetSize(10, 10)
                upBtn.icon:SetPoint('CENTER', 0, 0)
                upBtn.icon:SetTexture(chevPath)
                if upBtn.icon.SetTexCoord then upBtn.icon:SetTexCoord(0, 1, 1, 0) end
                upBtn:SetScript('OnClick', function()
                    if row._colKey then vcProvider.MoveColumn(row._colKey, -1) end
                end)

                local lbl = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
                lbl:SetPoint('LEFT', chk, 'RIGHT', 8, 0)
                lbl:SetPoint('RIGHT', upBtn, 'LEFT', -6, 0)
                lbl:SetJustifyH('LEFT')
                lbl:SetWordWrap(false)
                applyFont(lbl, 12, 'regular')

                row.checkBtn = chk
                row.upBtn = upBtn
                row.downBtn = downBtn
                row.label = lbl
                pop.rows[idx] = row
            end
        end
        v.colSettingsPopover = pop
    end

    function H.buildSidebarControls(v, context, T)
        local sbParent = (context and context.sidebarParent) or v
        v.skillControl = CreateFrame('Frame', nil, sbParent)
        v.skillControl:SetSize(194, 34)
        v.skillControl:Hide()
        v.skillControl._sidebarHeight = 35
        local label = v.skillControl:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
        applyFont(label, 11, 'regular')
        label:SetPoint('TOPLEFT', 2, -1)
        label:SetText('Skill')
        v._skillLabel = label
        local dash = v.skillControl:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        applyFont(dash, 11, 'regular')
        dash:SetPoint('TOPLEFT', 105, -1)
        dash:SetText('-')
        v._skillDash = dash
        v.skillError = v.skillControl:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
        applyFont(v.skillError, 11, 'regular')
        v.skillError:SetPoint('BOTTOMLEFT', 2, 0)
        v.skillError:SetTextColor(1, 0.4, 0.3)

        for _, skSpec in ipairs({{name='skillMin', key=dbPrefix .. 'SkillMin', x=43}, {name='skillMax', key=dbPrefix .. 'SkillMax', x=119}}) do
            local edit = CreateFrame('EditBox', nil, v.skillControl, 'InputBoxTemplate')
            edit:SetSize(52, 20)
            edit:SetPoint('TOPLEFT', skSpec.x, -1)
            edit:SetAutoFocus(false)
            edit:SetNumeric(true)
            if T and T.StyleEditBox then T.StyleEditBox(edit) end
            v[skSpec.name] = edit
            local function commit(self)
                local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
                if not db then return end
                local input = self:GetText() or ''
                local value = ns.SuperListModel and ns.SuperListModel.SkillBound and ns.SuperListModel.SkillBound(input) or nil
                local empty = input:match('^%s*$') ~= nil
                if not empty and value == nil then H.syncSkills(db) return end
                local changed = db[skSpec.key] ~= value
                db[skSpec.key] = value
                H.syncSkills(db)
                if changed then H.triggerRefresh() end
            end
            edit:SetScript('OnEnterPressed', function(self) commit(self) self:ClearFocus() end)
            edit:SetScript('OnEditFocusLost', commit)
            edit:SetScript('OnEscapePressed', function(self)
                local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
                if db then H.syncSkills(db) end
                self:ClearFocus()
            end)
        end

        local function clearSkills()
            local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
            if not db then return end
            db[dbPrefix .. 'SkillMin'], db[dbPrefix .. 'SkillMax'] = nil, nil
            H.syncSkills(db)
            H.triggerRefresh()
        end
        v.skillClear = CreateFrame('Button', nil, v.skillControl, 'UIPanelButtonTemplate')
        v.skillClear:SetSize(16, 18)
        v.skillClear:SetPoint('TOPLEFT', 178, -1)
        v.skillClear:SetText('x')
        if T and T.SkinButton then
            local closeIc = (T.ASSETS and T.ASSETS.icon_close) or (uiCache.appleRoot .. 'icon_close')
            T.SkinButton(v.skillClear, {icon=closeIc, iconSize=9})
        end
        v.skillClear:SetScript('OnClick', clearSkills)
        v.skillControl:EnableMouse(true)
        v.skillControl:SetScript('OnMouseUp', function(_, button) if button == 'RightButton' then clearSkills() end end)

        v.sourceButton = CreateFrame('Button', nil, sbParent, 'UIPanelButtonTemplate')
        v.sourceButton:SetSize(194, 21)
        v.sourceButton:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        if T and T.SkinButton then T.SkinButton(v.sourceButton, {dropdown=true}) end
        v.sourceButton:Hide()
        v.sourceButton:SetScript('OnClick', function(self, button)
            local db = (S.latest and S.latest.db) or _G.MerchantMasterDB
            if not db then return end
            local srcKey = dbPrefix .. 'Sources'
            if type(db[srcKey]) ~= 'table' then db[srcKey] = {} end
            if button == 'RightButton' then
                db[srcKey] = {}
                H.setBtnText(self, H.sourceLabel(db))
                H.triggerRefresh()
                return
            end
            ns.Theme.OpenDropDown(self, sources, nil, function(key)
                if key == 'all' then
                    db[srcKey] = {}
                else
                    db[srcKey][key] = not db[srcKey][key] or nil
                end
                H.setBtnText(self, H.sourceLabel(db))
                H.triggerRefresh()
            end, 214, {multiSelect=true, isSelected=function(key)
                if key == 'all' then return next(db[srcKey]) == nil end
                return db[srcKey][key] == true
            end})
        end)
        v.sourceButton:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:AddLine('Recipe Sources (Multi-Select)', 1, 0.82, 0)
            GameTooltip:AddLine('Merchant Favor, Vendor, Writ, Trainer, AH / World, Quest / BoP. Selected sources combine with OR; other filters combine with AND.', 1, 1, 1, true)
            GameTooltip:AddLine('Right-click: All Sources', 0.7, 0.9, 1)
            H.liftAndShowTooltip()
        end)
        v.sourceButton:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

        v.resetFiltersButton = CreateFrame('Button', nil, sbParent, 'UIPanelButtonTemplate')
        v.resetFiltersButton:SetSize(194, 21)
        v.resetFiltersButton:SetText('Reset All Filters')
        if T and T.SkinButton then T.SkinButton(v.resetFiltersButton, {primary=false}) end
        v.resetFiltersButton._isCheck = false
        v.resetFiltersButton:Hide()
        v.resetFiltersButton:SetScript('OnClick', H.resetFilters)
        v.resetFiltersButton:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:AddLine('Reset ' .. spec.title .. ' Filters', 1, 0.82, 0)
            GameTooltip:AddLine('Resets Search, Profession, Sources, Skill range, Legacy overrides, Buy Moat, and Sub-Craft mode.', 1, 1, 1, true)
            H.liftAndShowTooltip()
        end)
        v.resetFiltersButton:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    end

    function vcProvider.Create(parent, context)
        if S.view then return S.view end
        S.host = context
        local T = ns.Theme
        local v = CreateFrame('Frame', nil, parent)
        v:SetPoint('TOPLEFT', 0, 0)
        v:SetPoint('BOTTOMRIGHT', 0, 0)
        v:Hide()
        S.view = v

        v:RegisterEvent('MODIFIER_STATE_CHANGED')
        v:SetScript('OnEvent', function(self, event)
            if event == 'MODIFIER_STATE_CHANGED' and shown(self) then
                H.syncShiftFromModifier()
            end
        end)
        local function onShiftUpdate(self)
            if not shown(self) then return end
            H.syncShiftFromModifier()
        end
        v:HookScript('OnShow', function(self)
            self:SetScript('OnUpdate', onShiftUpdate)
            H.rebindStaleRows()
            local state = shiftKeyDown()
            if state == nil then return end
            local down = state and true or false
            S.lastShiftDown = down
            if down ~= S.shiftActive then vcProvider.SetShiftMode(down) end
        end)
        v:HookScript('OnHide', function(self)
            self:SetScript('OnUpdate', nil)
            local quickLook = ns.SuperList and ns.SuperList.GetQuickLookFrame and ns.SuperList.GetQuickLookFrame()
            if quickLook and quickLook.data and quickLook.data.kind == 'recipe' and ns.SuperList.CloseQuickLook then
                ns.SuperList.CloseQuickLook()
            end
            S.lastShiftDown = false
            if S.shiftActive then vcProvider.SetShiftMode(false) end
            if self.colSettingsPopover and self.colSettingsPopover.Hide then self.colSettingsPopover:Hide() end
            vcProvider.CancelPresentation()
        end)
        v.CloseHeatPopover = vcProvider.CloseHeatPopover

        if type(T) == 'table' and type(T.NineApple) == 'function' then
            v._mmCard = T.NineApple(v, 'glass_r10', 'cardBg', false, {noSpecular=true})
        end

        H.buildRow1(v, T)
        H.buildRow2(v, T)
        H.buildRow3(v, T)

        local columns = {}
        for i, col in ipairs(C.VENDOR_COLUMNS) do columns[i] = H.copyColumn(col) end
        S.tbl = S.host.createSortableTable(v, -111, spec.tabKey, columns, H.bindRow, nil,
            {preserveCellColors=true, preparedCells=true})
        v.table = S.tbl
        S.tbl.headerBtnsByKey = {}
        for i, col in ipairs(S.tbl.columns) do
            S.tbl.headerBtnsByKey[col.key] = S.tbl.headerBtns[i]
        end
        S.tbl.growWeights = {}
        for i, col in ipairs(S.tbl.columns) do
            S.tbl.growWeights[i] = col.grow
        end
        if S.tbl.headerBar and S.tbl.headerBar.SetHeight then S.tbl.headerBar:SetHeight(28) end
        H.clearInsetChrome()
        if type(S.tbl.inset) == 'table' then
            S.tbl.inset:ClearAllPoints()
            S.tbl.inset:SetPoint('TOPLEFT', 0, -139)
            S.tbl.inset:SetPoint('BOTTOMRIGHT', 0, 0)
        end
        S.tbl.updateHeaders = H.styleHeaders
        S.tbl.proportional = true

        local emptyParent = S.tbl.inset or v
        local emptyText = emptyParent:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        emptyText:SetPoint('CENTER', emptyParent, 'CENTER', 0, 0)
        emptyText:SetWidth(520)
        emptyText:SetJustifyH('CENTER')
        emptyText:SetWordWrap(true)
        applyFont(emptyText, 12, 'regular')
        emptyText:SetText(spec.emptyMsg)
        emptyText:Hide()
        v.emptyText = emptyText

        H.buildColumnPopover(v, T)
        H.buildSidebarControls(v, context, T)

        v._applyColumnConfig = H.applyColumnConfig
        v._refreshColumnPopover = H.refreshColumnPopover
        v._themeColumnSettingsPopover = H.themeColumnSettingsPopover
        v._applyColumnConfig(H.getColumnDB())

        local initW = (context and context.parent and context.parent.GetWidth and context.parent:GetWidth())
            or (parent and parent.GetWidth and parent:GetWidth()) or 0
        if initW >= 400 then
            H.layoutRow2(initW)
        end

        if T and T.RegisterWidget then
            T.RegisterWidget(v, H.applyTheme)
        elseif T and T.OnModeChanged then
            T.OnModeChanged(H.applyTheme)
        end
        H.applyTheme()
        return v
    end

    return vcProvider
    end

    if not ns.VendorCrafter then
        local vc = createCrafterProvider({
            mode = 'vendor',
            tabKey = 'vendor_crafter',
            title = 'Vendor Crafter',
            dbPrefix = 'vendorCrafter',
            modelName = 'VendorCrafterModel',
            hostResetFn = 'resetVendorCrafterFilters',
            hostQueueFn = 'queueVendorCrafterPlan',
            hostWarmCompleteFn = 'onVendorCrafterWarmComplete',
            craftWordPlural = 'vendor crafts',
            econHeader = 'Vendor Craft Economics',
            emptyMsg = 'No vendor-profitable crafts (Avg Profit > 0) match the active filters and Legacy settings.',
            showMasterChef = true,
            columns = {
                {key='name',label='Name',width=128,minWidth=104,grow=450,align='LEFT',hint='Name: click to search AH, preview shopping, and pin Quick Look. Shift-click to quick-add.'},
                {key='knownSort',label='Known',width=48,minWidth=46,grow=20,align='CENTER',defaultAsc=false,hint='Known: whether you (or an alt in All Chars mode) have learned the recipe.'},
                {key='cdSort',label='CD',width=32,minWidth=26,grow=10,align='CENTER',defaultAsc=true,hint='CD: craft cooldown status. R = Ready, <H>h or <M>m = cooldown duration, - = no cooldown.'},
                {key='craftCost',label='Craft Cost',width=66,minWidth=60,grow=14,align='RIGHT',hint='Craft Cost: total reagent cost per craft, applying Bartering, Honored, and sub-craft settings.'},
                {key='minVendor',label='Min Vendor',width=66,minWidth=60,grow=14,align='RIGHT',hint='Min Vendor: guaranteed NPC vendor sell revenue per craft without Master Chef double-proc.'},
                {key='avgVendor',label='Avg Vendor',width=68,minWidth=62,grow=14,align='RIGHT',hint='Avg Vendor: expected NPC vendor sell revenue per craft including Master Chef Cooking double-proc EV.'},
                {key='maxVendor',label='Max Vendor',width=66,minWidth=60,grow=14,align='RIGHT',hint='Max Vendor: maximum NPC vendor sell revenue per craft on a Master Chef double-proc.'},
                {key='avgProfit',label='Avg Profit',width=70,minWidth=64,grow=18,align='RIGHT',defaultAsc=false,hint='Avg Profit: expected net vendor profit per craft (Avg Vendor - Craft Cost). Only Avg Profit > 0 rows are shown.'},
                {key='marginPct',label='Margin',width=50,minWidth=46,grow=14,align='RIGHT',defaultAsc=false,hint='Margin: expected return on craft cost (Avg Profit / Craft Cost).'},
                {key='moatScore',label='Buy Moat',width=82,minWidth=74,grow=45,align='CENTER',defaultAsc=false,hint='Buy Moat: how many profitable crafts exist in AH reagent depth before hitting supply or break-even walls.'},
                {key='profitableCrafts',label='Max Crafts',width=60,minWidth=56,grow=16,align='RIGHT',defaultAsc=false,hint='Max Crafts: maximum profitable crafts supported by AH depth (Inf for unlimited vendor loops). Hover for safe/plan limits.'},
                {key='buyCeiling',label='Buy Up To',width=70,minWidth=62,grow=14,align='RIGHT',defaultAsc=false,hint='Buy Up To: marginal craft cost of the last profitable craft before hitting the break-even price wall (Vendor if all-vendor).'},
                {key='totalProfitCap',label='Profit Cap',width=70,minWidth=62,grow=14,align='RIGHT',defaultAsc=false,hint='Profit Cap: realizable profit in the active Top-N Plan (or standalone total profit cap across profitable reagent lots).'},
                {key='requiredSkill',label='Level',width=54,minWidth=48,grow=14,align='LEFT',hint='Level: profession abbreviation and required profession skill.'},
                {key='sourceLabel',label='Source',width=48,minWidth=44,grow=14,align='LEFT',hint='Source: recipe acquisition (Merchant, Vendor, Trainer, AH, Quest, Drop, Starter).'},
                {key='buyCostCopper',label='Buy Recipe',width=64,minWidth=60,grow=12,align='RIGHT',hint='Buy Recipe: one-time recipe acquisition cost. * marks an estimated Favor equivalent.'},
                {key='wowheadURL',label='WH',width=28,minWidth=26,grow=8,align='CENTER',hint='Wowhead: copy the recipe item or spell URL with the Ctrl+C window.'},
            },
        })
        ns.VendorCrafter = vc
        if MerchantMasterAPI and MerchantMasterAPI.RegisterVendorCrafter then
            MerchantMasterAPI.RegisterVendorCrafter(vc)
        end
    end

    if not ns.DisenchantCrafter then
        local dc = createCrafterProvider({
            mode = 'disenchant',
            tabKey = 'disenchant_crafter',
            title = 'Disenchantment Crafter',
            dbPrefix = 'disenchantCrafter',
            modelName = 'DisenchantCrafterModel',
            hostResetFn = 'resetDisenchantCrafterFilters',
            hostQueueFn = 'queueDisenchantCrafterPlan',
            hostWarmCompleteFn = 'onDisenchantCrafterWarmComplete',
            craftWordPlural = 'disenchant crafts',
            econHeader = 'Disenchant Craft Economics',
            emptyMsg = 'No disenchantable or craftable recipes match the active filters.',
            showMasterChef = false,
            showArcaneSalvager = true,
            columns = {
                {key='name',label='Name',width=128,minWidth=104,grow=420,align='LEFT',hint='Name: click to search AH, preview shopping, and pin Quick Look. Shift-click to quick-add.'},
                {key='knownSort',label='Known',width=48,minWidth=46,grow=20,align='CENTER',defaultAsc=false,hint='Known: whether you (or an alt in All Chars mode) have learned the recipe.'},
                {key='cdSort',label='CD',width=32,minWidth=26,grow=10,align='CENTER',defaultAsc=true,hint='CD: craft cooldown status. R = Ready, <H>h or <M>m = cooldown duration, - = no cooldown.'},
                {key='craftCost',label='Craft Cost',width=66,minWidth=60,grow=14,align='RIGHT',hint='Craft Cost: total reagent cost per craft, applying Bartering, Honored, and sub-craft settings.'},
                {key='deSummary',label='Primary DE',width=112,minWidth=92,grow=160,align='LEFT',hint='Primary DE: highest-chance enchanting material received when disenchanting the crafted item.'},
                {key='minDE',label='Min DE',width=66,minWidth=60,grow=14,align='RIGHT',hint='Min DE: worst-case net AH disenchant roll per craft after AH cut.'},
                {key='avgDE',label='Avg DE',width=68,minWidth=62,grow=14,align='RIGHT',hint='Avg DE: expected net AH disenchant value per craft using built-in Forever disenchant probabilities and tracked prices.'},
                {key='avgDEAS',label='Avg DE (AS)',width=72,minWidth=64,grow=14,align='RIGHT',hint='Avg DE (AS): expected net disenchant value per craft with Arcane Salvager (+20% bonus loot).'},
                {key='maxDE',label='Max DE',width=66,minWidth=60,grow=14,align='RIGHT',hint='Max DE: best-case net AH disenchant roll per craft after AH cut.'},
                {key='avgProfit',label='Avg Profit',width=70,minWidth=64,grow=18,align='RIGHT',defaultAsc=false,hint='Avg Profit: expected net disenchant profit per craft (Avg DE - Craft Cost).'},
                {key='marginPct',label='Margin',width=50,minWidth=46,grow=14,align='RIGHT',defaultAsc=false,hint='Margin: expected return on craft cost (Avg Profit / Craft Cost).'},
                {key='moatScore',label='Buy Moat',width=82,minWidth=74,grow=45,align='CENTER',defaultAsc=false,hint='Buy Moat: how many profitable crafts exist in AH reagent depth before hitting supply or break-even walls.'},
                {key='profitableCrafts',label='Max Crafts',width=60,minWidth=56,grow=16,align='RIGHT',defaultAsc=false,hint='Max Crafts: maximum profitable crafts supported by AH depth (Inf for unlimited vendor loops).'},
                {key='buyCeiling',label='Buy Up To',width=70,minWidth=62,grow=14,align='RIGHT',defaultAsc=false,hint='Buy Up To: marginal craft cost of the last profitable craft before hitting the break-even price wall.'},
                {key='totalProfitCap',label='Profit Cap',width=70,minWidth=62,grow=14,align='RIGHT',defaultAsc=false,hint='Profit Cap: realizable profit in the active Top-N Plan (or standalone total profit cap across profitable reagent lots).'},
                {key='requiredSkill',label='Level',width=54,minWidth=48,grow=14,align='LEFT',hint='Level: profession abbreviation and required profession skill.'},
                {key='sourceLabel',label='Source',width=48,minWidth=44,grow=14,align='LEFT',hint='Source: recipe acquisition (Merchant, Vendor, Trainer, AH, Quest, Drop, Starter).'},
                {key='buyCostCopper',label='Buy Recipe',width=64,minWidth=60,grow=12,align='RIGHT',hint='Buy Recipe: one-time recipe acquisition cost. * marks an estimated Favor equivalent.'},
                {key='wowheadURL',label='WH',width=28,minWidth=26,grow=8,align='CENTER',hint='Wowhead: copy the recipe item or spell URL with the Ctrl+C window.'},
            },
            numericKeys = {
                craftCost = true, minDE = true, avgDE = true, avgDEAS = true, maxDE = true,
                avgProfit = true, minProfit = true, maxProfit = true, marginPct = true,
                moatScore = true, profitableCrafts = true, totalProfitCap = true, totalSpendCap = true,
                buyCeiling = true, safeProfitCrafts = true, planCrafts = true, planProfit = true,
                planRank = true, requiredSkill = true, knownSort = true, cdSort = true,
                buyCostCopper = true, numMade = true, repSort = true, ownedOutputQty = true, ownedScrollQty = true,
                deIlvl = true, deQuality = true,
            },
        })
        ns.DisenchantCrafter = dc
        if MerchantMasterAPI and MerchantMasterAPI.RegisterDisenchantCrafter then
            MerchantMasterAPI.RegisterDisenchantCrafter(dc)
        end
    end
end

do
    local aiProvider, C, H, S = {}, {}, {}, {}
    ns.AllItems = aiProvider

    C.PROF_PILLS = {
        { key = 'all',            label = 'All',    tip = 'Show catalog items across all professions and sources.' },
        { key = 'mining',         label = 'Mine',   tip = 'Mining goods: ores, Solid Stone and other stones, gems, and smelted bars.' },
        { key = 'herbalism',      label = 'Herb',   tip = 'Herbalism goods: gathered herbs and lotus.' },
        { key = 'skinning',       label = 'Skin',   tip = 'Skinning goods: leathers, hides, and scales.' },
        { key = 'alchemy',        label = 'Alch',   tip = 'Alchemy crafted items and reagents.' },
        { key = 'blacksmithing',  label = 'BS',     tip = 'Blacksmithing crafted items and reagents.' },
        { key = 'enchanting',     label = 'Ench',   tip = 'Enchanting dust, shards, essences, rods, and oils.' },
        { key = 'engineering',    label = 'Eng',    tip = 'Engineering crafted parts, bombs, and reagents.' },
        { key = 'leatherworking', label = 'LW',     tip = 'Leatherworking armor, kits, hides, and reagents.' },
        { key = 'tailoring',      label = 'Tailor', tip = 'Tailoring cloth, bolts, bags, and crafted gear.' },
        { key = 'cooking',        label = 'Cook',   tip = 'Cooking ingredients, spices, fish, meat, and food.' },
        { key = 'firstaid',       label = 'FA',     tip = 'First Aid bandages and anti-venoms.' },
        { key = 'poisons',        label = 'Pois',   tip = 'Rogue Poisons and poison reagents.' },
        { key = 'others',         label = 'Others', tip = 'Crates, Writs, Recipe Scrolls, and general trade goods.' },
    }

    C.ITEM_TYPES = {
        { key = 'gather',   label = 'Gathering' },
        { key = 'crafted',  label = 'Crafted' },
        { key = 'material', label = 'Materials & Cloth' },
        { key = 'scroll',   label = 'Recipe Scrolls' },
        { key = 'turnin',   label = 'Crates / Writs' },
        { key = 'vendor',   label = 'Vendor Supplies' },
    }

    C.ROLE_FILTERS = {
        { key = 'all',        label = 'Role: All' },
        { key = 'gather',     label = 'Role: Gathering' },
        { key = 'reagent',    label = 'Role: Reagent' },
        { key = 'craftable',  label = 'Role: Craftable' },
        { key = 'crate_writ', label = 'Role: Crate / Writ' },
        { key = 'priced',     label = 'Role: Has AH Price' },
    }

    C.SELLABLE_FILTERS = {
        { key = 'all', label = 'Trade: All' },
        { key = 'yes', label = 'Trade: AH Sellable' },
        { key = 'no',  label = 'Trade: Soulbound' },
    }

    C.DEMAND_FILTERS_FALLBACK = {
        { key = 'all',       label = 'Demand: All' },
        { key = 'monopoly',  label = 'Demand: Monopoly' },
        { key = 'high_turn', label = 'Demand: High Turn (>=1x)' },
        { key = 'hot',       label = 'Demand: Hot/Fav (>=0.15x)' },
        { key = 'unlisted',  label = 'Demand: Unlisted (0)' },
        { key = 'listed',    label = 'Demand: Listed (Yes)' },
        { key = 'cold',      label = 'Demand: Cold (<0.05x)' },
    }

    C.ITEM_COLUMNS = {
        { key = 'name',           label = 'Item',         width = 186, minWidth = 136, grow = 1.60, align = 'LEFT',   defaultAsc = true,  icon = true, locked = true,
          hint = 'Item name and icon. Click for Quick Look, Shift+Click or Stepper to add to Shopping List.' },
        { key = 'categoryLabel',  label = 'Category',     width = 92,  minWidth = 70,  grow = 0.60, align = 'LEFT',   defaultAsc = true,
          hint = 'Item subtype or gathering category (Ore/Stone, Herb, Leather, Cloth, etc.).' },
        { key = 'ownedQty',       label = 'Owned',        width = 54,  minWidth = 42,  grow = 0.25, align = 'RIGHT',  defaultAsc = false,
          hint = 'Count owned across bags, bank, and tracked alts.' },
        { key = 'listed',         label = 'Listed',       width = 50,  minWidth = 38,  grow = 0.20, align = 'RIGHT',  defaultAsc = false,
          hint = 'Current live Auction House listing quantity.' },
        { key = 'goodScore',      label = 'Rating',       width = 60,  minWidth = 48,  grow = 0.25, align = 'LEFT',   defaultAsc = false,
          hint = 'Market demand rating and turn-in utility.' },
        { key = 'unitAH',         label = 'AH Price',     width = 78,  minWidth = 62,  grow = 0.45, align = 'RIGHT',  defaultAsc = false,
          hint = 'Live Auction House unit buyout price.' },
        { key = 'vendorSell',     label = 'Vendor Sell',  width = 74,  minWidth = 58,  grow = 0.40, align = 'RIGHT',  defaultAsc = false,
          hint = 'NPC vendor sell price.' },
        { key = 'salesPerDay',    label = 'Sales/d',      width = 78,  minWidth = 58,  grow = 0.45, align = 'RIGHT',  defaultAsc = false,
          hint = 'Estimated daily AH sales rate (scope tag appended).' },
        { key = 'turnoverPerDay', label = 'Gold/d',       width = 76,  minWidth = 58,  grow = 0.45, align = 'RIGHT',  defaultAsc = false,
          hint = 'Estimated daily AH gold turnover (AH Price x Sales/d).' },
        { key = 'demandSort',     label = 'Demand',       width = 102, minWidth = 78,  grow = 0.65, align = 'LEFT',   defaultAsc = false, heatStrip = true,
          hint = 'Market demand tier based on active listings and estimated sales velocity.' },
        { key = 'usedInCount',    label = 'Used In',      width = 56,  minWidth = 44,  grow = 0.25, align = 'RIGHT',  defaultAsc = false,
          hint = 'Count of catalog crafting recipes that require this item.' },
        { key = 'sourceLabel',    label = 'Source',       width = 84,  minWidth = 64,  grow = 0.55, align = 'LEFT',   defaultAsc = true,
          hint = 'Acquisition source (Gathering, Crafted, Vendor, Waylaid Crate, Writ).' },
        { key = 'marketValue',    label = 'Market Val',   width = 78,  minWidth = 60,  grow = 0.45, align = 'RIGHT',  defaultAsc = false, defaultHidden = true,
          hint = 'Historical reference market value.' },
        { key = 'craftCost',      label = 'Craft Cost',   width = 76,  minWidth = 58,  grow = 0.45, align = 'RIGHT',  defaultAsc = true,  defaultHidden = true,
          hint = 'Estimated reagent craft cost if craftable.' },
        { key = 'profit',         label = 'Craft Profit', width = 80,  minWidth = 60,  grow = 0.45, align = 'RIGHT',  defaultAsc = false, defaultHidden = true,
          hint = 'Estimated net crafting profit after AH cut (if craftable).' },
        { key = 'requiredSkill',  label = 'Skill',        width = 46,  minWidth = 36,  grow = 0.20, align = 'RIGHT',  defaultAsc = true,  defaultHidden = true,
          hint = 'Minimum profession skill level for gathering or crafting.' },
        { key = 'wowheadURL',     label = 'Wowhead',      width = 62,  minWidth = 48,  grow = 0.30, align = 'CENTER', defaultAsc = true,  defaultHidden = true,
          hint = 'Click to open the Wowhead item link popup.' },
    }

    C.NUMERIC_KEYS = {
        ownedQty = true, listed = true, goodScore = true, unitAH = true,
        vendorSell = true, salesPerDay = true, turnoverPerDay = true, demandSort = true,
        usedInCount = true, marketValue = true, craftCost = true, profit = true,
        requiredSkill = true,
    }

    C.FALLBACK = {
        text = { 1, 1, 1 },
        muted = { 0.6, 0.6, 0.6 },
        secondary = { 0.82, 0.82, 0.85 },
        pillText = { 0.88, 0.88, 0.90 },
        green = { 0.20, 0.78, 0.35 },
        blue = { 0.36, 0.72, 1.00 },
        orange = { 1.00, 0.57, 0.19 },
        red = { 1.00, 0.26, 0.27 },
        lightRed = { 0.722, 0.078, 0.102 },
    }

    S.generation = 0
    S.presentSeq = 0
    S.prewarmSeq = 0
    S.reconcileSeq = 0
    S.pending = false
    S.reconcilePending = false
    S.forceVersion = 0
    S.metaDirty = false
    S.metaTargets = nil
    S.itemChanges = {}
    S.inFlightPresent = nil
    S.retainedResult = nil
    S.retainedDatasetSig = nil
    S.retainedFilterKey = nil
    S.retainedMetaEpoch = nil
    S.boundResult = nil
    S.boundDatasetSig = nil
    S.boundFilterKey = nil
    S.boundMetaEpoch = nil
    S.boundWidth = nil
    S.viewWasHidden = false
    S.earlyPresentedFilterKey = nil
    S.earlyBoundResult = nil
    S.earlyCountShown = nil
    S.earlyTier1Done = nil
    S.earlyWarmTotal = nil
    S.earlyAuthoritative = nil
    S.warmContext = nil
    S.filterLRU = uiCache.createFilterLRU(8)
    S.shiftActive = false
    S.lastShiftDown = false
    S.colEpoch = 0
    S.cellCacheEpoch = 0
    S.metaEpoch = 0
    S.prepared = {}
    S.changes = {}
    S.cellValueCache = setmetatable({}, { __mode = 'k' })
    S.sortWorkspace = { values = {}, names = {}, keys = {} }
    S.fallbackColConfig = { order = {}, hidden = {} }
    for i, col in ipairs(C.ITEM_COLUMNS) do
        S.fallbackColConfig.order[i] = col.key
        if col.defaultHidden then S.fallbackColConfig.hidden[col.key] = true end
    end

    function H.active()
        return not S.host or not S.host.isActive or S.host.isActive()
    end

    function H.getDB(ctx)
        local c = ctx or S.latest
        return (c and c.db) or _G.MerchantMasterDB
    end

    function H.setBtnText(btn, txt)
        if not btn then return end
        if btn.SetText then btn:SetText(txt) end
        if btn.fs and btn.fs.SetText then btn.fs:SetText(txt) end
    end

    function H.liftAndShowTooltip()
        if not GameTooltip then return end
        local T = ns.Theme
        if T and T.LiftTooltip then T.LiftTooltip(GameTooltip) end
        GameTooltip:Show()
    end

    function H.copyColumn(col)
        local copy = {}
        for k, v in pairs(col) do copy[k] = v end
        return copy
    end

    function H.demandFilters()
        return (type(ns.DEMAND_FILTERS) == 'table' and #ns.DEMAND_FILTERS > 0) and ns.DEMAND_FILTERS or C.DEMAND_FILTERS_FALLBACK
    end

    function H.findLabel(list, key, fallback)
        for _, it in ipairs(list or {}) do
            if it.key == key then return it.label end
        end
        return fallback or tostring(key or 'All')
    end

    function H.formatTypesLabel(typesMap)
        if type(typesMap) ~= 'table' then return 'Types: All' end
        local labels = {}
        for _, spec in ipairs(C.ITEM_TYPES) do
            if typesMap[spec.key] == true then labels[#labels + 1] = spec.label end
        end
        if #labels == 0 or #labels == #C.ITEM_TYPES then return 'Types: All' end
        if #labels == 1 then return 'Type: ' .. labels[1] end
        return 'Types (' .. #labels .. ')'
    end

    function H.updateFilterControls(db)
        db = db or H.getDB()
        local v = S.view
        if not v then return end
        local pf = (type(db) == 'table' and db.allItemsProfFilter) or 'all'
        for key, btn in pairs(v.profBtns or {}) do
            local active = (key == pf)
            btn.active = active
            if btn.SetActive then btn:SetActive(active) end
        end
        if v.typeButton then H.setBtnText(v.typeButton, H.formatTypesLabel(type(db) == 'table' and db.allItemsTypes)) end
        if v.roleButton then H.setBtnText(v.roleButton, H.findLabel(C.ROLE_FILTERS, (type(db) == 'table' and db.allItemsRoleFilter) or 'all', 'Role: All')) end
        if v.sellableButton then H.setBtnText(v.sellableButton, H.findLabel(C.SELLABLE_FILTERS, (type(db) == 'table' and db.allItemsSellableFilter) or 'all', 'Trade: All')) end
        if v.demandButton then H.setBtnText(v.demandButton, H.findLabel(H.demandFilters(), (type(db) == 'table' and db.allItemsDemandFilter) or 'all', 'Demand: All')) end
        if v.skillControl and not v.skillControl._editing and ns.AllItemsModel and ns.SuperListModel then
            local lo = ns.SuperListModel.SkillBound(type(db) == 'table' and db.allItemsSkillMin or nil)
            local hi = ns.SuperListModel.SkillBound(type(db) == 'table' and db.allItemsSkillMax or nil)
            local loText = lo and tostring(lo) or ''
            local hiText = hi and tostring(hi) or ''
            if v.skillControl.minBox and v.skillControl.minBox.GetText and v.skillControl.minBox:GetText() ~= loText then
                v.skillControl.minBox:SetText(loText)
            end
            if v.skillControl.maxBox and v.skillControl.maxBox.GetText and v.skillControl.maxBox:GetText() ~= hiText then
                v.skillControl.maxBox:SetText(hiText)
            end
        end
    end

    function H.normalizeColumnConfig(db)
        local cfg
        if type(db) == 'table' then
            if type(db.allItemsColumns) ~= 'table' then db.allItemsColumns = {} end
            cfg = db.allItemsColumns
        else
            cfg = S.fallbackColConfig
        end
        if type(cfg.order) ~= 'table' then cfg.order = {} end
        if type(cfg.hidden) ~= 'table' then cfg.hidden = {} end
        local byKey, defaultPos = {}, {}
        for i, col in ipairs(C.ITEM_COLUMNS) do
            byKey[col.key] = col
            defaultPos[col.key] = i
        end
        local hadOrder = #cfg.order > 0
        local seen, cleanOrder = {}, {}
        for _, key in ipairs(cfg.order) do
            if byKey[key] and not seen[key] then
                seen[key] = true
                cleanOrder[#cleanOrder + 1] = key
            end
        end
        if not hadOrder then
            for _, col in ipairs(C.ITEM_COLUMNS) do
                if col.defaultHidden and cfg.hidden[col.key] == nil then
                    cfg.hidden[col.key] = true
                end
            end
        end
        for _, col in ipairs(C.ITEM_COLUMNS) do
            if not seen[col.key] then
                seen[col.key] = true
                if col.locked then
                    table.insert(cleanOrder, 1, col.key)
                else
                    cleanOrder[#cleanOrder + 1] = col.key
                end
                if col.defaultHidden and cfg.hidden[col.key] == nil then
                    cfg.hidden[col.key] = true
                end
            end
        end
        for i = 1, #cleanOrder do
            if byKey[cleanOrder[i]] and byKey[cleanOrder[i]].locked and i ~= 1 then
                local lk = table.remove(cleanOrder, i)
                table.insert(cleanOrder, 1, lk)
                break
            end
        end
        cfg.order = cleanOrder
        for k in pairs(cfg.hidden) do
            if not byKey[k] or byKey[k].locked or cfg.hidden[k] ~= true then
                cfg.hidden[k] = nil
            end
        end
        return cfg, byKey, defaultPos
    end

    function H.getActiveColumnDefs(db)
        local cfg, byKey = H.normalizeColumnConfig(db)
        local out = {}
        for _, key in ipairs(cfg.order) do
            local col = byKey[key]
            if col and (col.locked or cfg.hidden[key] ~= true) then
                out[#out + 1] = H.copyColumn(col)
            end
        end
        return out, cfg
    end

    function H.clearInsetChrome()
        local t = S.tbl
        if not t or type(t.inset) ~= 'table' then return end
        if type(t.inset._mmCard) == 'table' then
            for _, k in ipairs({ 'fill', 'border', 'stroke' }) do
                local obj = t.inset._mmCard[k]
                if type(obj) == 'table' then
                    if type(obj.SetColor) == 'function' then obj:SetColor(0, 0, 0, 0) end
                    if type(obj.SetAlpha) == 'function' then obj:SetAlpha(0) end
                    if type(obj.SetShown) == 'function' then obj:SetShown(false) end
                end
            end
        end
        if type(t.inset.GetRegions) == 'function' then
            for _, r in ipairs({ t.inset:GetRegions() }) do
                if type(r) == 'table' and r.GetObjectType and r:GetObjectType() == 'Texture' and type(r.SetAlpha) == 'function' then
                    r:SetAlpha(0)
                end
            end
        end
        for _, k in ipairs({ 'NineSlice', 'Bg', 'TopLeftCorner', 'TopRightCorner', 'BotLeftCorner', 'BotRightCorner', 'TopBorder', 'BottomBorder', 'LeftBorder', 'RightBorder' }) do
            local reg = t.inset[k]
            if type(reg) == 'table' and type(reg.Hide) == 'function' then reg:Hide() end
        end
    end

    function H.getHeatStripForRow(data)
        if not uiCache.snapshotsAvailable() then return nil end
        local id = type(data) == 'table' and (data.outputItemID or data.itemID) or nil
        if not id or id <= 0 then return nil end
        local P = ns.Pricing
        if not (P and type(P.GetItemHeatStrip24h) == 'function') then return nil end
        local econ = S.latest and S.latest.econInfo and S.latest.econInfo.effectiveKey or nil
        return P.GetItemHeatStrip24h(id, econ)
    end

    function H.closeHeatPopover(onlyForRow)
        local pop = type(S.view) == 'table' and rawget(S.view, 'heatPopover') or nil
        if not (type(pop) == 'table' or type(pop) == 'userdata') then return end
        if onlyForRow and pop.ownerCell and pop.ownerCell._ownerRow ~= onlyForRow then return end
        if shown(pop) then pop:Hide() end
        pop.ownerCell = nil
        pop.itemID = nil
    end

    function H.repositionHeatPopover(pop, ownerCell)
        if not pop or not ownerCell then return end
        local parent = pop:GetParent() or S.view
        local scale = parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
        local pL, pT, pR, pB = uiCache.frameBounds(parent, scale)
        local cL, cT, cR, cB = uiCache.frameBounds(ownerCell, scale)
        if not (pL and cL) then return end
        local x = cR - pL + 8
        if x + HEAT_POPOVER_W > (pR - pL - 6) then
            x = cL - pL - HEAT_POPOVER_W - 8
        end
        x = math.max(6, math.min(x, (pR - pL) - HEAT_POPOVER_W - 6))
        local yTop = pT - cT - 4
        local maxTop = (pT - pB) - HEAT_POPOVER_H - 6
        yTop = math.max(6, math.min(yTop, maxTop))
        pop:ClearAllPoints()
        pop:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, -yTop)
    end

    function H.ensureHeatPopover()
        local existing = type(S.view) == 'table' and rawget(S.view, 'heatPopover') or nil
        if existing then return existing end
        local Chart = ns.Analytics and ns.Analytics.Chart
        if not (Chart and type(Chart.CreateHeatmapTimingDrawer) == 'function') then return nil end
        local T = ns.Theme
        local parent = S.view
        local pop = CreateFrame('Frame', nil, parent)
        pop:SetSize(HEAT_POPOVER_W, HEAT_POPOVER_H)
        if pop.SetFrameStrata then pop:SetFrameStrata('DIALOG') end
        if parent and parent.GetFrameLevel and pop.SetFrameLevel then
            pop:SetFrameLevel((parent:GetFrameLevel() or 2) + 80)
        end
        pop:EnableMouse(true)
        pop:Hide()
        pop.drawer = Chart.CreateHeatmapTimingDrawer(pop, HEAT_POPOVER_W, HEAT_POPOVER_H, {
            compact = true,
            showCurve = true,
            onClose = function() H.closeHeatPopover() end,
        })
        if pop.drawer then
            pop.drawer:ClearAllPoints()
            pop.drawer:SetPoint('TOPLEFT', pop, 'TOPLEFT', 0, 0)
            pop.drawer:Show()
        end
        pop:SetScript('OnHide', function(self)
            self.ownerCell = nil
            self.itemID = nil
            if self.drawer and self.drawer.SimulateHover then self.drawer:SimulateHover(nil, nil) end
        end)
        if T and T.RegisterWidget then
            T.RegisterWidget(pop, function()
                if pop.drawer and pop.drawer.UpdateTheme then pop.drawer:UpdateTheme() end
            end)
        end
        if type(S.view) == 'table' then S.view.heatPopover = pop end
        return pop
    end

    function H.toggleHeatPopover(ownerCell, row)
        if not uiCache.snapshotsAvailable() then H.closeHeatPopover(); return end
        local itemID = type(row) == 'table' and (row.outputItemID or row.itemID) or nil
        if not ownerCell or not itemID then return end
        local pop = type(S.view) == 'table' and rawget(S.view, 'heatPopover') or nil
        if pop and shown(pop) and pop.ownerCell == ownerCell and pop.itemID == itemID then
            H.closeHeatPopover()
            return
        end
        H.closeHeatPopover()
        pop = H.ensureHeatPopover()
        if not pop or not pop.drawer then return end
        local econ = S.latest and S.latest.econInfo and S.latest.econInfo.effectiveKey or nil
        local heatmap = ns.Pricing and ns.Pricing.GetItemHeatmap and ns.Pricing.GetItemHeatmap(itemID, econ) or nil
        local fallbackQL = nil
        if not heatmap and ns.RecipeStats and ns.RecipeStats.BuildQuickLook then
            local ctx = {
                kind = 'item',
                econInfo = S.latest and S.latest.econInfo,
                applyAHCut = not MerchantMasterDB or MerchantMasterDB.applyAHCut ~= false,
                window = (MerchantMasterDB and MerchantMasterDB.quickLookWindow) or '7d',
            }
            fallbackQL = ns.RecipeStats.BuildQuickLook(row, ctx)
        end
        pop.ownerCell = ownerCell
        pop.itemID = itemID
        pop.drawer:Layout(HEAT_POPOVER_W, HEAT_POPOVER_H, true)
        pop.drawer:SetItem(itemID, heatmap, fallbackQL, econ)
        H.repositionHeatPopover(pop, ownerCell)
        pop:Show()
    end

    function H.styleHeaders()
        local t = S.tbl
        if not t then return end
        local T = ns.Theme
        local pal = getThemePalette()
        local sort = S.host and S.host.getSort and S.host.getSort() or {}
        local tStyle = (T and T.IsCustomSkin and T.IsCustomSkin() and T.GetTableStyle and T.GetTableStyle()) or 'standard'
        local styled = (tStyle == 't5_ruled' or tStyle == 't5_well' or tStyle == 't3_strips')
        local chevPath = (T and T.ASSETS and T.ASSETS.icon_chevron_down) or (uiCache.appleRoot .. 'icon_chevron_down')
        local activeHex = colorHex(pal and (pal.textBlue or pal.accentBlue), '0091ff')
        local mutedCol = styled and (pal and (pal.gold or pal.text)) or (pal and pal.textMuted) or C.FALLBACK.muted
        local activeCol = (pal and (pal.textBlue or pal.accentBlue)) or C.FALLBACK.blue
        if type(t.headerBar) == 'table' and type(t.headerBar.GetRegions) == 'function' then
            for _, reg in ipairs({ t.headerBar:GetRegions() }) do
                if type(reg) == 'table' and reg.GetObjectType and reg:GetObjectType() == 'Texture' and reg.SetColorTexture then
                    if styled then
                        reg:SetColorTexture(0, 0, 0, 0)
                    elseif pal and pal.separator then
                        reg:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.65)
                    end
                end
            end
        end
        for i, col in ipairs(t.columns or {}) do
            local btn = t.headerBtns and t.headerBtns[i]
            if type(btn) == 'table' then
                if btn.SetHeight then btn:SetHeight(26) end
                if type(btn.sep) == 'table' and type(btn.sep.Hide) == 'function' then
                    btn.sep:Hide()
                end
                if type(btn.bg) == 'table' and btn.bg.SetColorTexture then
                    btn.bg:SetColorTexture(0, 0, 0, 0)
                end
                if btn.fs then
                    applyFont(btn.fs, styled and 10 or 11, styled and 'semibold' or 'regular')
                    if btn.fs.SetJustifyH then btn.fs:SetJustifyH(col.align or 'LEFT') end
                    if btn.fs.SetJustifyV then btn.fs:SetJustifyV('MIDDLE') end
                    local lbl = col.label or ''
                    local dispLbl = styled and string.upper(lbl) or lbl
                    if sort.col == col.key then
                        local arrow = sort.asc
                            and (' |T' .. chevPath .. ':9:9:0:0:16:16:0:16:16:0|t')
                            or (' |T' .. chevPath .. ':9:9:0:0:16:16:0:16:0:16|t')
                        btn.fs:SetText('|cff' .. activeHex .. dispLbl .. '|r' .. arrow)
                        if btn.fs.SetTextColor then btn.fs:SetTextColor(activeCol[1], activeCol[2], activeCol[3], 1) end
                    else
                        btn.fs:SetText(dispLbl)
                        if btn.fs.SetTextColor then btn.fs:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1) end
                    end
                end
            end
        end
        if t.paintTableChrome then t.paintTableChrome() end
    end

    function H.formatCellValues(data, pal)
        local cached = S.cellValueCache[data]
        if cached and cached.epoch == S.cellCacheEpoch and cached.pal == pal and cached.metaEpoch == S.metaEpoch
            and cached.priceVer == ((ns.GetEffectivePriceVersion and ns.GetEffectivePriceVersion()) or ns.priceCacheEpoch) then
            return cached.values
        end
        local values = {}
        values.name = data.name or ''
        values.categoryLabel = text(data.categoryLabel) ~= '' and data.categoryLabel or 'Item'
        values.ownedQty = (number(data.ownedQty) and data.ownedQty > 0) and tostring(math.floor(data.ownedQty + 0.5)) or '-'
        values.listed = (number(data.listed) and data.listed > 0) and tostring(math.floor(data.listed + 0.5)) or '0'
        local gs = text(data.goodShort)
        values.goodScore = gs ~= '' and (themeText(gs) or gs) or '-'
        values.unitAH = number(data.unitAH) and money(data.unitAH) or '|cff888888n/a|r'
        values.vendorSell = number(data.vendorSell) and money(data.vendorSell) or '|cff888888n/a|r'
        values.salesPerDay = formatSalesCell(data.salesPerDay, pal)
        values.turnoverPerDay = number(data.turnoverPerDay) and moneyCompact(data.turnoverPerDay) or '|cff888888n/a|r'
        local dm = type(data.demand) == 'table' and data.demand or nil
        local dmBadge = dm and (dm.shortBadge or dm.badge or dm.label) or ''
        values.demandSort = dmBadge ~= '' and (themeText(dmBadge) or dmBadge) or '-'
        local uc = number(data.usedInCount) or 0
        values.usedInCount = uc > 0 and tostring(uc) or '-'
        values.sourceLabel = text(data.sourceLabel) ~= '' and data.sourceLabel or '-'
        values.marketValue = number(data.marketValue) and money(data.marketValue) or '|cff888888n/a|r'
        values.craftCost = number(data.craftCost) and money(data.craftCost) or '-'
        if number(data.profit) then
            local p = data.profit
            local col = (p > 0 and (pal and pal.hexSuccess or '34c759')) or (p < 0 and (pal and pal.hexDanger or 'ff453a')) or (pal and pal.hexMuted or '8e8e93')
            values.profit = '|cff' .. col .. money(p, true) .. '|r'
        else
            values.profit = '-'
        end
        values.requiredSkill = number(data.requiredSkill) and tostring(data.requiredSkill) or '-'
        values.wowheadURL = text(data.wowheadURL) ~= '' and 'Link' or '-'
        S.cellValueCache[data] = {
            epoch = S.cellCacheEpoch,
            pal = pal,
            metaEpoch = S.metaEpoch,
            priceVer = (ns.GetEffectivePriceVersion and ns.GetEffectivePriceVersion()) or ns.priceCacheEpoch,
            values = values,
        }
        return values
    end

    function H.styleRowStepper(stepper, qty, pal)
        if not stepper then return end
        local T = ns.Theme
        local dark = not (T and T.GetMode and T.GetMode() == 'light')
        local bgCol = dark and { 0.16, 0.17, 0.19 } or { 0.92, 0.93, 0.95 }
        local stCol = dark and { 1, 1, 1, 0.22 } or { 0, 0, 0, 0.18 }
        local textCol = (pal and pal.text) or C.FALLBACK.text
        local activeCol = (pal and pal.accentGreen) or C.FALLBACK.green
        local qc = (qty and qty > 0) and activeCol or ((pal and pal.textSecondary) or C.FALLBACK.secondary)
        if stepper.bg then
            if stepper.bg.SetColor then stepper.bg:SetColor(bgCol[1], bgCol[2], bgCol[3], 1)
            elseif stepper.bg.SetColorTexture then stepper.bg:SetColorTexture(bgCol[1], bgCol[2], bgCol[3], 1) end
        end
        if stepper.stroke and stepper.stroke.SetColor then
            stepper.stroke:SetColor(stCol[1], stCol[2], stCol[3], stCol[4] or 0.22)
        end
        if stepper.minusBtn and stepper.minusBtn.fs then
            stepper.minusBtn.fs:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
        end
        if stepper.plusBtn and stepper.plusBtn.fs then
            stepper.plusBtn.fs:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
        end
        if stepper.qtyFs then
            stepper.qtyFs:SetText(tostring(qty or 0))
            stepper.qtyFs:SetTextColor(qc[1], qc[2], qc[3], qc[4] or 1)
        end
    end

    function H.ensureRowStepper(r)
        if r.shiftStepper then return r.shiftStepper end
        local T = ns.Theme
        local stepper = CreateFrame('Frame', nil, r)
        stepper:SetSize(74, 20)
        stepper:SetPoint('RIGHT', r, 'RIGHT', -2, 0)
        if r.GetFrameLevel and stepper.SetFrameLevel then
            stepper:SetFrameLevel((r:GetFrameLevel() or 1) + 4)
        end
        if stepper.EnableMouse then stepper:EnableMouse(true) end
        if T and T.RoundRect and T.ASSETS and T.ASSETS.pill_fill then
            stepper.bg = T.RoundRect(stepper, stepper, 'BACKGROUND', 0, 10, 0, 0.204, 0.204, 0.220, 1, T.ASSETS.pill_fill)
            stepper.stroke = T.RoundRect(stepper, stepper, 'BORDER', 1, 10, 0, 1, 1, 1, 0.22, T.ASSETS.pill_stroke)
        else
            stepper.bg = stepper:CreateTexture(nil, 'BACKGROUND')
            stepper.bg:SetAllPoints()
            stepper.bg:SetColorTexture(0.204, 0.204, 0.220, 1)
        end
        local minusBtn = CreateFrame('Button', nil, stepper)
        minusBtn:SetSize(22, 20)
        minusBtn:SetPoint('LEFT', stepper, 'LEFT', 0, 0)
        minusBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        minusBtn.fs = minusBtn:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        minusBtn.fs:SetAllPoints()
        minusBtn.fs:SetJustifyH('CENTER')
        minusBtn.fs:SetText('-')
        applyFont(minusBtn.fs, 12, 'semibold')
        minusBtn:SetScript('OnClick', function(_, button)
            if r.data and S.host and S.host.adjustItemShoppingQty then
                local cur = (S.host.getItemShoppingQty and S.host.getItemShoppingQty(r.data)) or 0
                local delta = (button == 'RightButton') and -math.max(1, cur) or -1
                S.host.adjustItemShoppingQty(r.data, delta)
            end
        end)
        local plusBtn = CreateFrame('Button', nil, stepper)
        plusBtn:SetSize(22, 20)
        plusBtn:SetPoint('RIGHT', stepper, 'RIGHT', 0, 0)
        plusBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        plusBtn.fs = plusBtn:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        plusBtn.fs:SetAllPoints()
        plusBtn.fs:SetJustifyH('CENTER')
        plusBtn.fs:SetText('+')
        applyFont(plusBtn.fs, 12, 'semibold')
        plusBtn:SetScript('OnClick', function(_, button)
            if r.data and S.host and S.host.adjustItemShoppingQty then
                local delta = (button == 'RightButton') and 5 or 1
                S.host.adjustItemShoppingQty(r.data, delta)
            end
        end)
        local qtyFs = stepper:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        qtyFs:SetPoint('LEFT', minusBtn, 'RIGHT', 0, 0)
        qtyFs:SetPoint('RIGHT', plusBtn, 'LEFT', 0, 0)
        qtyFs:SetJustifyH('CENTER')
        applyFont(qtyFs, 11, 'semibold')
        stepper.minusBtn, stepper.plusBtn, stepper.qtyFs = minusBtn, plusBtn, qtyFs
        stepper:Hide()
        r.shiftStepper = stepper
        return stepper
    end

    function H.paintRowShiftUI(r, pal)
        if not (r and r.data) then return end
        local hovered = isMouseOverFrame(r) or (r.shiftStepper and isMouseOverFrame(r.shiftStepper))
        local qty = S.host and S.host.getItemShoppingQty and S.host.getItemShoppingQty(r.data) or 0
        local showStep = (S.shiftActive == true) or (qty > 0 and hovered)
        local activeCols = S.tbl and S.tbl.columns
        local colX = S.tbl and S.tbl.colX
        local cellsByKey = r.cellGroup and r.cellGroup.cellsByKey
        if showStep then
            local stepper = H.ensureRowStepper(r)
            H.styleRowStepper(stepper, qty, pal)
            stepper:Show()
            local n = activeCols and #activeCols or 0
            local hidAny = false
            if n > 0 and cellsByKey and colX then
                r._shiftHidden = true
                local lastCol = activeCols[n]
                local lastX = colX[n]
                local tblRight = (lastCol and lastX) and (lastX + (lastCol.width or 0)) or 0
                local rawRowW = (r.GetWidth and r:GetWidth()) or 0
                local rowW = (rawRowW >= math.max(200, tblRight * 0.5)) and rawRowW or tblRight
                if rowW > 80 then
                    local cutoff = rowW - 80
                    for i = 1, n do
                        local col = activeCols[i]
                        local c = col and cellsByKey[col.key]
                        local cx = colX[i] or 0
                        local cw = (col and col.width) or 0
                        local overlap = (cx + cw > cutoff)
                        if c and c.SetShown then c:SetShown(not overlap) end
                        if overlap then hidAny = true end
                    end
                end
            end
            local nameCell = cellsByKey and cellsByKey.name
            if nameCell and nameCell.fs then
                nameCell.fs:ClearAllPoints()
                nameCell.fs:SetPoint('LEFT', nameCell.icon and 22 or 0, 0)
                if not hidAny then
                    nameCell.fs:SetPoint('RIGHT', stepper, 'LEFT', -4, 0)
                else
                    nameCell.fs:SetPoint('RIGHT', 0, 0)
                end
            end
        else
            if r.shiftStepper then r.shiftStepper:Hide() end
            if r._shiftHidden then
                r._shiftHidden = false
                if activeCols and cellsByKey then
                    for i = 1, #activeCols do
                        local c = cellsByKey[activeCols[i].key]
                        if c and c.Show then c:Show() end
                    end
                end
            end
            local nameCell = cellsByKey and cellsByKey.name
            if nameCell and nameCell.fs then
                nameCell.fs:ClearAllPoints()
                nameCell.fs:SetPoint('LEFT', nameCell.icon and 22 or 0, 0)
                nameCell.fs:SetPoint('RIGHT', 0, 0)
            end
        end
    end

    function H.paintRowSep(r)
        if not r then return end
        local pal = getThemePalette()
        if r.sep then
            if not r._sepAnchored and type(r.sep.ClearAllPoints) == 'function' and type(r.sep.SetPoint) == 'function' then
                r._sepAnchored = true
                r.sep:ClearAllPoints()
                r.sep:SetPoint('BOTTOMLEFT', r, 'BOTTOMLEFT', 16, 0)
                r.sep:SetPoint('BOTTOMRIGHT', r, 'BOTTOMRIGHT', -16, 0)
                if r.sep.SetHeight then r.sep:SetHeight(1) end
            end
            if type(r.sep.SetColorTexture) == 'function' then
                local sep = pal and pal.separator
                if sep then
                    r.sep:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.45) * 0.45)
                else
                    r.sep:SetColorTexture(0.5, 0.5, 0.54, 0.18)
                end
            end
        end
    end

    function H.paintRowSelection(r)
        if not r then return end
        local sel = r.data and S.selectedKey ~= nil and r.data.key == S.selectedKey
        if r.selectTex then
            if sel then
                local pal = getThemePalette()
                local c = (pal and pal.rowSelect) or { 0.25, 0.55, 1, 0.18 }
                r.selectTex:SetColorTexture(c[1], c[2], c[3], c[4] or 0.18)
                r.selectTex:Show()
            else
                r.selectTex:Hide()
            end
        end
        H.paintRowSep(r)
    end

    function H.showRowTooltip(owner, data)
        if not (GameTooltip and data) then return end
        GameTooltip:SetOwner(owner, 'ANCHOR_RIGHT')
        local itemName = data.name or ('Item #' .. tostring(data.itemID))
        GameTooltip:SetText(itemName, 1, 0.85, 0.25)
        GameTooltip:AddDoubleLine('Category', text(data.categoryLabel) ~= '' and data.categoryLabel or 'Item', 0.72, 0.72, 0.76, 1, 1, 1)
        GameTooltip:AddDoubleLine('Source', text(data.sourceLabel) ~= '' and data.sourceLabel or '-', 0.72, 0.72, 0.76, 1, 1, 1)
        if text(data.gatherNote) ~= '' then
            GameTooltip:AddDoubleLine('Gather / Note', data.gatherNote, 0.72, 0.72, 0.76, 0.85, 0.95, 1)
        end
        if number(data.requiredSkill) then
            GameTooltip:AddDoubleLine('Skill Req', tostring(data.requiredSkill), 0.72, 0.72, 0.76, 1, 1, 1)
        end
        GameTooltip:AddLine(' ', 1, 1, 1)
        GameTooltip:AddDoubleLine('AH Price', number(data.unitAH) and money(data.unitAH) or 'n/a', 0.72, 0.72, 0.76, 1, 1, 1)
        GameTooltip:AddDoubleLine('Vendor Sell', number(data.vendorSell) and money(data.vendorSell) or 'n/a', 0.72, 0.72, 0.76, 1, 1, 1)
        if number(data.craftCost) then
            GameTooltip:AddDoubleLine('Craft Cost', money(data.craftCost), 0.72, 0.72, 0.76, 1, 1, 1)
        end
        if number(data.profit) then
            GameTooltip:AddDoubleLine('Craft Profit', money(data.profit, true), 0.72, 0.72, 0.76, data.profit >= 0 and 0.25 or 1, data.profit >= 0 and 0.9 or 0.35, 0.35)
        end
        GameTooltip:AddDoubleLine('Listed / Owned', string.format('%d / %d', math.floor(tonumber(data.listed) or 0), math.floor(tonumber(data.ownedQty) or 0)), 0.72, 0.72, 0.76, 1, 1, 1)
        local used = type(data.usedInRecipes) == 'table' and data.usedInRecipes or {}
        if #used > 0 then
            GameTooltip:AddLine(' ', 1, 1, 1)
            GameTooltip:AddLine(string.format('Used in %d recipe%s:', #used, #used == 1 and '' or 's'), 0.45, 0.82, 1)
            local limit = math.min(#used, 6)
            for i = 1, limit do
                local u = used[i]
                local pf = u.prof and ((ns.PROF_BY_KEY and ns.PROF_BY_KEY[u.prof] and ns.PROF_BY_KEY[u.prof].short) or u.prof) or ''
                GameTooltip:AddDoubleLine('  ' .. tostring(u.name or u.outputItemID), pf, 0.9, 0.9, 0.92, 0.7, 0.7, 0.75)
            end
            if #used > limit then
                GameTooltip:AddLine(string.format('  ...and %d more', #used - limit), 0.65, 0.65, 0.7)
            end
        end
        GameTooltip:AddLine(' ', 1, 1, 1)
        GameTooltip:AddLine('Click for Item Quick Look | Hold Shift + Click to add to Shopping List', 0.4, 1, 0.6, true)
        H.liftAndShowTooltip()
    end

    function H.prepareCells()
        local t = S.tbl
        local parent = (t and t.scrollBox) or S.view
        local T = ns.Theme
        local Chart = ns.Analytics and ns.Analytics.Chart
        local rowH = (t and t.rowHeight) or (S.host and S.host.rowHeight) or 22
        local cells, byKey = {}, {}
        for i, col in ipairs(C.ITEM_COLUMNS) do
            local cell = CreateFrame('Button', nil, parent)
            cell:SetHeight(rowH)
            cell:EnableMouse(true)
            cell:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
            if col.icon then
                local icon = cell:CreateTexture(nil, 'ARTWORK')
                icon:SetSize(16, 16)
                icon:SetPoint('LEFT', 2, 0)
                cell.icon = icon
            end
            local fs = cell:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
            fs:SetPoint('LEFT', col.icon and 22 or 0, 0)
            fs:SetPoint('RIGHT', 0, 0)
            fs:SetJustifyH(col.align or 'LEFT')
            if fs.SetJustifyV then fs:SetJustifyV('MIDDLE') end
            fs:SetWordWrap(false)
            applyFont(fs, 11, col.key == 'name' and 'semibold' or 'regular')
            cell.fs = fs
            if col.heatStrip and Chart and type(Chart.CreateHeatStrip24h) == 'function' then
                local hs = Chart.CreateHeatStrip24h(cell, { height = 4, showNowTick = true })
                if hs then
                    local frameObj = hs.frame or hs
                    if frameObj and frameObj.SetPoint then
                        frameObj:ClearAllPoints()
                        frameObj:SetPoint('BOTTOMLEFT', cell, 'BOTTOMLEFT', 2, 2)
                        frameObj:SetPoint('BOTTOMRIGHT', cell, 'BOTTOMRIGHT', -2, 2)
                    end
                    cell.heatStrip = hs
                    cell._heatStripBound = false
                end
            end
            cell._colKey = col.key
            cell:SetScript('OnClick', function(self, button)
                local row = self._ownerRow
                if not (row and row.data) then return end
                local data = row.data
                if shiftKeyDown() and button == 'LeftButton' then
                    if S.host and S.host.adjustItemShoppingQty then
                        S.host.adjustItemShoppingQty(data, 1)
                    end
                    return
                end
                if shiftKeyDown() and button == 'RightButton' then
                    local cur = (S.host and S.host.getItemShoppingQty and S.host.getItemShoppingQty(data)) or 0
                    if cur > 0 and S.host and S.host.adjustItemShoppingQty then
                        S.host.adjustItemShoppingQty(data, -1)
                    end
                    return
                end
                if self._colKey == 'demandSort' and button == 'LeftButton' and uiCache.snapshotsAvailable() and H.getHeatStripForRow(data) then
                    H.toggleHeatPopover(self, data)
                    return
                end
                if self._colKey == 'wowheadURL' and button == 'LeftButton' then
                    if S.host and S.host.openWowheadPopup and text(data.wowheadURL) ~= '' then
                        S.host.openWowheadPopup({
                            wowheadURL = data.wowheadURL,
                            wowheadLabel = data.name,
                            wowheadKind = 'item',
                            recipeName = data.name,
                        }, data.name, data.icon)
                    end
                    return
                end
                if button == 'LeftButton' then
                    S.selectedKey = data.key
                    if S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame then
                        S.tbl.scrollBox:ForEachFrame(H.paintRowSelection)
                    end
                    if S.host and S.host.openQuickLook then
                        S.host.openQuickLook('item', data, { owner = row, toggle = true })
                    end
                end
            end)
            cell:SetScript('OnEnter', function(self)
                local row = self._ownerRow
                if row and row.data then
                    H.showRowTooltip(row, row.data)
                    H.paintRowShiftUI(row, getThemePalette())
                end
            end)
            cell:SetScript('OnLeave', function(self)
                if GameTooltip then GameTooltip:Hide() end
                local row = self._ownerRow
                if row and row.data then H.paintRowShiftUI(row, getThemePalette()) end
            end)
            cells[i] = cell
            byKey[col.key] = cell
        end
        return { cells = cells, cellsByKey = byKey }
    end

    function H.bindRow(r, data)
        if not r then return end
        if not r.cellGroup then
            if S.host and S.host.applyRowHighlight then S.host.applyRowHighlight(r) end
            if r.sep and type(r.sep.ClearAllPoints) == 'function' and type(r.sep.SetPoint) == 'function' then
                r._sepAnchored = true
                r.sep:ClearAllPoints()
                r.sep:SetPoint('BOTTOMLEFT', r, 'BOTTOMLEFT', 16, 0)
                r.sep:SetPoint('BOTTOMRIGHT', r, 'BOTTOMRIGHT', -16, 0)
                if r.sep.SetHeight then r.sep:SetHeight(1) end
            end
            if ns.Theme and ns.Theme.RegisterWidget then
                ns.Theme.RegisterWidget(r, function() H.paintRowSep(r) end)
            end
            H.paintRowSep(r)
            if #S.prepared == 0 then
                S.prepared[#S.prepared + 1] = H.prepareCells()
            end
            r.cellGroup = table.remove(S.prepared)
            r.cells = r.cellGroup.cells
        end
        if r.stripe and r.stripe.SetColorTexture then
            r.stripe:SetColorTexture(0, 0, 0, 0)
        end
        if not r.selectTex then
            r.selectTex = r:CreateTexture(nil, 'BACKGROUND', nil, 2)
            r.selectTex:SetAllPoints()
            r.selectTex:Hide()
        end
        if r.data ~= data then
            H.closeHeatPopover(r)
        end
        r.data = data
        local t = S.tbl
        local pal = getThemePalette()
        local rowH = (t and t.rowHeight) or (S.host and S.host.rowHeight) or 22
        local active = {}
        local activeCells = r._activeCells
        if not activeCells then activeCells = {}; r._activeCells = activeCells end
        for k in pairs(activeCells) do activeCells[k] = nil end
        local vals = data and H.formatCellValues(data, pal) or nil
        if t then
            for i, col in ipairs(t.columns or {}) do
                local cell = r.cellGroup.cellsByKey[col.key]
                if cell then
                    active[cell] = true
                    activeCells[i] = cell
                    cell:SetParent(r)
                    cell._ownerRow = r
                    cell:ClearAllPoints()
                    cell:SetPoint('LEFT', r, 'LEFT', t.colX[i] or 4, 0)
                    cell:SetSize(col.width, rowH)
                    cell:Show()
                    if data and vals then
                        if cell.fs then
                            if cell.fs.SetJustifyV then cell.fs:SetJustifyV('MIDDLE') end
                            if col.key == 'name' then
                                local c = (pal and pal.text) or C.FALLBACK.text
                                cell.fs:SetTextColor(c[1], c[2], c[3], 1)
                            elseif col.key == 'categoryLabel' or col.key == 'sourceLabel' then
                                local c = (pal and pal.textSecondary) or C.FALLBACK.secondary
                                cell.fs:SetTextColor(c[1], c[2], c[3], 1)
                            else
                                local c = (pal and pal.text) or C.FALLBACK.text
                                cell.fs:SetTextColor(c[1], c[2], c[3], 1)
                            end
                            cell.fs:SetText(vals[col.key] or '-')
                        end
                        if cell.icon then
                            cell.icon:SetTexture(data.icon or ns.QUESTION_ICON)
                            cell.icon:Show()
                        end
                        if cell.heatStrip then
                            local strip = H.getHeatStripForRow(data)
                            if strip then
                                cell.heatStrip:Bind(strip, pal, currentLocalHour())
                                cell.heatStrip:Layout(math.max(24, (col.width or 80) - 4))
                                cell._heatStripBound = true
                            elseif cell._heatStripBound then
                                cell.heatStrip:Clear()
                                cell._heatStripBound = false
                            end
                        end
                    end
                end
            end
        end
        r.cells = activeCells
        for _, cell in ipairs(r.cellGroup.cells) do
            if not active[cell] then
                cell._ownerRow = nil
                cell:Hide()
                if cell.icon then cell.icon:Hide() end
                if cell._heatStripBound and cell.heatStrip then
                    cell.heatStrip:Clear()
                    cell._heatStripBound = false
                end
            end
        end
        H.paintRowSelection(r)
        H.paintRowShiftUI(r, pal)
        if not r._aiHooked then
            r._aiHooked = true
            r:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
            r:SetScript('OnClick', function(self, button)
                if not self.data then return end
                if shiftKeyDown() and button == 'LeftButton' then
                    if S.host and S.host.adjustItemShoppingQty then
                        S.host.adjustItemShoppingQty(self.data, 1)
                    end
                    return
                end
                if shiftKeyDown() and button == 'RightButton' then
                    local cur = (S.host and S.host.getItemShoppingQty and S.host.getItemShoppingQty(self.data)) or 0
                    if cur > 0 and S.host and S.host.adjustItemShoppingQty then
                        S.host.adjustItemShoppingQty(self.data, -1)
                    end
                    return
                end
                if button == 'LeftButton' then
                    S.selectedKey = self.data.key
                    if S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame then
                        S.tbl.scrollBox:ForEachFrame(H.paintRowSelection)
                    end
                    if S.host and S.host.openQuickLook then
                        S.host.openQuickLook('item', self.data, { owner = self, toggle = true })
                    end
                end
            end)
            r:SetScript('OnEnter', function(self)
                if self.data then
                    H.showRowTooltip(self, self.data)
                    H.paintRowShiftUI(self, getThemePalette())
                end
            end)
            r:SetScript('OnLeave', function(self)
                if GameTooltip then GameTooltip:Hide() end
                H.paintRowShiftUI(self, getThemePalette())
            end)
        end
    end

    function H.applyColumnConfig(db)
        local activeCols, cfg = H.getActiveColumnDefs(db or H.getDB())
        S.appliedColSig = fingerprint(cfg)
        local t = S.tbl
        if not t then return end
        t.columns = t.columns or {}
        for k in pairs(t.columns) do t.columns[k] = nil end
        t.baseWidths = t.baseWidths or {}
        for k in pairs(t.baseWidths) do t.baseWidths[k] = nil end
        t.growWeights = t.growWeights or {}
        for k in pairs(t.growWeights) do t.growWeights[k] = nil end
        t.colX = t.colX or {}
        for k in pairs(t.colX) do t.colX[k] = nil end
        t.headerBtns = t.headerBtns or {}
        for k in pairs(t.headerBtns) do t.headerBtns[k] = nil end
        local activeBtns = {}
        local x = 4
        for i, col in ipairs(activeCols) do
            t.columns[i] = col
            t.baseWidths[i] = col.width
            t.growWeights[i] = col.grow
            t.colX[i] = x
            x = x + col.width + 5
            local btn = t.headerBtnsByKey and t.headerBtnsByKey[col.key]
            t.headerBtns[i] = btn
            if btn then
                activeBtns[btn] = true
                if btn.Show then btn:Show() end
            end
        end
        for _, btn in pairs(t.headerBtnsByKey or {}) do
            if not activeBtns[btn] and btn.Hide then btn:Hide() end
        end
        S.colEpoch = S.colEpoch + 1
        S.cellCacheEpoch = S.cellCacheEpoch + 1
        local w = S.view and S.view.GetWidth and S.view:GetWidth() or 0
        if w > 0 then
            aiProvider.Layout(w, S.view:GetHeight(), true)
        else
            for i, col in ipairs(t.columns) do
                local btn = t.headerBtns[i]
                if btn and t.headerBar then
                    btn:ClearAllPoints()
                    btn:SetPoint('LEFT', t.headerBar, 'LEFT', t.colX[i], 1)
                    btn:SetWidth(col.width)
                end
            end
            H.styleHeaders()
        end
        if t.scrollBox and t.scrollBox.ForEachFrame then
            t.scrollBox:ForEachFrame(function(r)
                if r.data then H.bindRow(r, r.data) end
            end)
        end
    end

    function H.buildColumnPopover(v, T)
        local pop = CreateFrame('Frame', nil, v)
        pop:SetSize(288, 396)
        pop:SetPoint('TOPRIGHT', v.colSettingsBtn, 'BOTTOMRIGHT', 0, -6)
        if pop.SetFrameStrata then pop:SetFrameStrata('DIALOG') end
        if v.GetFrameLevel and pop.SetFrameLevel then pop:SetFrameLevel((v:GetFrameLevel() or 2) + 80) end
        pop:EnableMouse(true)
        pop:Hide()
        if T and T.NineApple then
            pop.surface = T.NineApple(pop, 'glass_r16', T.COLORS and T.COLORS.toolbarBg, T.COLORS and T.COLORS.borderStrong, { noSpecular = true })
        else
            pop.bg = pop:CreateTexture(nil, 'BACKGROUND')
            pop.bg:SetAllPoints()
            pop.bg:SetColorTexture(0.11, 0.12, 0.14, 0.97)
        end
        pop.titleFs = pop:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        pop.titleFs:SetPoint('TOPLEFT', 12, -12)
        pop.titleFs:SetText('All Items Columns')
        applyFont(pop.titleFs, 12, 'semibold')
        pop.closeBtn = T and T.CreatePlateButton and T.CreatePlateButton(pop, '', 22, 22, { variant = 'ghost', pill = true, icon = T.ASSETS and T.ASSETS.icon_close, iconSize = 11 }) or CreateFrame('Button', nil, pop)
        pop.closeBtn:SetPoint('TOPRIGHT', pop, 'TOPRIGHT', -10, -8)
        pop.closeBtn:SetScript('OnClick', function() aiProvider.ToggleColumnSettings(false) end)
        pop.resetBtn = T and T.CreatePlateButton and T.CreatePlateButton(pop, 'Reset', 50, 22, { variant = 'secondary', pill = true, fontSize = 11 }) or CreateFrame('Button', nil, pop)
        pop.resetBtn:SetPoint('RIGHT', pop.closeBtn, 'LEFT', -6, 0)
        pop.resetBtn:SetScript('OnClick', function() aiProvider.ResetColumns() end)

        pop.rows = {}
        local byKey = {}
        for _, c in ipairs(C.ITEM_COLUMNS) do byKey[c.key] = c end
        for idx = 1, #C.ITEM_COLUMNS do
            local r = CreateFrame('Frame', nil, pop)
            r:SetSize(264, 19)
            r:SetPoint('TOPLEFT', pop, 'TOPLEFT', 12, -38 - (idx - 1) * 20)
            local cb = CreateFrame('CheckButton', nil, r, 'UICheckButtonTemplate')
            cb:SetSize(18, 18)
            cb:SetPoint('LEFT', r, 'LEFT', 0, 0)
            cb:SetScript('OnClick', function(self)
                if r.colKey then
                    aiProvider.SetColumnVisible(r.colKey, self:GetChecked() == true)
                end
            end)
            local lbl = r:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
            lbl:SetPoint('LEFT', cb, 'RIGHT', 6, 0)
            lbl:SetPoint('RIGHT', r, 'RIGHT', -48, 0)
            lbl:SetJustifyH('LEFT')
            lbl:SetWordWrap(false)
            applyFont(lbl, 11, 'regular')
            local up = CreateFrame('Button', nil, r)
            up:SetSize(18, 18)
            up:SetPoint('RIGHT', r, 'RIGHT', -22, 0)
            up.fs = up:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
            up.fs:SetAllPoints()
            up.fs:SetJustifyH('CENTER')
            up.fs:SetText('^')
            applyFont(up.fs, 11, 'semibold')
            up:SetScript('OnClick', function()
                if r.colKey then aiProvider.MoveColumn(r.colKey, -1) end
            end)
            local dn = CreateFrame('Button', nil, r)
            dn:SetSize(18, 18)
            dn:SetPoint('RIGHT', r, 'RIGHT', -2, 0)
            dn.fs = dn:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
            dn.fs:SetAllPoints()
            dn.fs:SetJustifyH('CENTER')
            dn.fs:SetText('v')
            applyFont(dn.fs, 11, 'semibold')
            dn:SetScript('OnClick', function()
                if r.colKey then aiProvider.MoveColumn(r.colKey, 1) end
            end)
            r.cb, r.lbl, r.up, r.dn, r._byKey = cb, lbl, up, dn, byKey
            pop.rows[idx] = r
        end
        v.colSettingsPopover = pop
    end

    function H.refreshColumnPopover()
        local pop = S.view and S.view.colSettingsPopover
        if not pop then return end
        local cfg, byKey = H.normalizeColumnConfig(H.getDB())
        local pal = getThemePalette()
        local tc = (pal and pal.text) or C.FALLBACK.text
        local mc = (pal and pal.textMuted) or C.FALLBACK.muted
        for idx, r in ipairs(pop.rows or {}) do
            local key = cfg.order[idx]
            local col = key and byKey[key]
            if col then
                r.colKey = key
                r:Show()
                r.lbl:SetText(col.label)
                local vis = col.locked or cfg.hidden[key] ~= true
                r.cb:SetChecked(vis)
                if r.cb.Enable and r.cb.Disable then
                    if col.locked then r.cb:Disable() else r.cb:Enable() end
                end
                r.lbl:SetTextColor(vis and tc[1] or mc[1], vis and tc[2] or mc[2], vis and tc[3] or mc[3], 1)
                if r.up.SetEnabled then r.up:SetEnabled(not col.locked and idx > 2) end
                if r.dn.SetEnabled then r.dn:SetEnabled(not col.locked and idx < #cfg.order) end
            else
                r.colKey = nil
                r:Hide()
            end
        end
    end

    function H.themeColumnSettingsPopover()
        local pop = S.view and S.view.colSettingsPopover
        if not pop then return end
        local pal = getThemePalette()
        if pop.surface and pop.surface.UpdateTheme and pal then
            pop.surface:UpdateTheme(pal.toolbarBg, pal.borderStrong)
        end
        if pop.titleFs and pal and pal.text then
            pop.titleFs:SetTextColor(pal.text[1], pal.text[2], pal.text[3], 1)
        end
        H.refreshColumnPopover()
    end

    function H.laterGuarded(fn)
        later(function()
            if type(fn) ~= 'function' then return end
            fn()
        end)
    end

    function H.filtersFromDB(ctx)
        local c = ctx or S.latest or {}
        local db = H.getDB(c) or {}
        local pf = (type(db) == 'table' and db.allItemsProfFilter) or c.profFilter or 'all'
        local search = c.search
        if search == nil then search = db.allItemsSearch or '' end
        return {
            profFilter = pf,
            itemTypes = db.allItemsTypes,
            roleFilter = db.allItemsRoleFilter or 'all',
            sellableFilter = db.allItemsSellableFilter or 'all',
            demandFilter = db.allItemsDemandFilter or 'all',
            skillMin = db.allItemsSkillMin,
            skillMax = db.allItemsSkillMax,
            search = search,
        }
    end

    function H.resolveSort()
        local s = S.host and S.host.getSort and S.host.getSort() or {}
        return s.col or 'turnoverPerDay', s.asc == true
    end

    function H.sortFromHost()
        local col, asc = H.resolveSort()
        return {
            key = col,
            ascending = asc,
        }
    end

    function H.buildFilterKey(context, col, asc)
        local f = H.filtersFromDB(context)
        return fingerprint({
            prof = f.profFilter,
            types = f.itemTypes,
            role = f.roleFilter,
            sell = f.sellableFilter,
            demand = f.demandFilter,
            smin = f.skillMin,
            smax = f.skillMax,
            search = f.search,
            col = col,
            asc = asc == true,
        })
    end

    function H.buildPriority(context, col)
        local c = context or S.latest or {}
        local db = H.getDB(c) or {}
        local sortCol = col or H.resolveSort()
        return {
            profFilter = (type(db) == 'table' and db.allItemsProfFilter) or c.profFilter or 'all',
            itemTypes = db.allItemsTypes,
            skillMin = db.allItemsSkillMin,
            skillMax = db.allItemsSkillMax,
            key = sortCol,
        }
    end

    function H.applyPendingChanges()
        local itemsOnly = (S.changes.items == true)
        for chReason in pairs(S.changes) do
            if chReason ~= 'items' then itemsOnly = false end
            if chReason ~= 'ownership' and chReason ~= 'snapshot' and chReason ~= 'items' then
                S.forceVersion = S.forceVersion + 1
                break
            end
        end
        S.changes = {}
        return itemsOnly
    end

    function H.computeDatasetSig(context)
        local db = (context and context.db) or _G.MerchantMasterDB or {}
        local statsContext = context and context.statsContext
        return fingerprint({
            economy = context and context.econInfo and context.econInfo.effectiveKey,
            price = (ns.GetEffectivePriceVersion and ns.GetEffectivePriceVersion()) or ns.priceCacheEpoch or 0,
            source = db.priceSource,
            cut = db.applyAHCut ~= false,
            char = context and context.charKey,
            revision = not statsContext and (context and context.revision) or nil,
            forced = S.forceVersion,
            catalog = tostring(ns.AllItemsModel and ns.AllItemsModel.GetCatalog()),
            day = time and math.floor(time() / 86400),
        })
    end

    function H.rebindStaleRows()
        if not (S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame) then return end
        S.tbl.scrollBox:ForEachFrame(function(r)
            if r.data then H.bindRow(r, r.data) end
        end)
    end

    function H.clearRetained()
        S.retainedResult = nil
        S.retainedDatasetSig = nil
        S.retainedFilterKey = nil
        S.retainedMetaEpoch = nil
        S.boundResult = nil
        S.boundDatasetSig = nil
        S.boundFilterKey = nil
        S.boundMetaEpoch = nil
        S.earlyPresentedFilterKey = nil
        S.earlyBoundResult = nil
        S.earlyCountShown = nil
        S.filterLRU:clear()
    end

    function H.syncEvaluationState(context, sig)
        local c = context or S.latest or {}
        local db = c.db or _G.MerchantMasterDB or {}
        local sc = c.statsContext
        if sig == S.signature and S.metaDirty then
            S.metaDirty = false
            S.metaTargets = nil
            if S.evaluation then
                S.evaluation.ownedCounts = c.counts
                S.evaluation.ownedCountsByID = sc and sc.ownedCountsByID
            end
            local currentRows = (S.buildState and S.buildState.rows) or S.rows
            if currentRows and #currentRows > 0 and ns.AllItemsModel and ns.AllItemsModel.PatchMeta then
                ns.AllItemsModel.PatchMeta(currentRows, S.evaluation)
                S.cellCacheEpoch = S.cellCacheEpoch + 1
                local col = H.resolveSort()
                if col == 'ownedQty' then
                    S.metaEpoch = S.metaEpoch + 1
                    H.clearRetained()
                else
                    S.filterLRU:evictWhere(function(tag)
                        return tag and tag.ownSens == true
                    end)
                    if H.active() then aiProvider.RepaintVisible() end
                end
            end
        elseif sig == S.signature and S.metaTargets then
            local mt = S.metaTargets
            S.metaTargets = nil
            if S.evaluation then
                S.evaluation.ownedCounts = c.counts
                S.evaluation.ownedCountsByID = sc and sc.ownedCountsByID
            end
            local currentRows = (S.buildState and S.buildState.rows) or S.rows
            if currentRows and #currentRows > 0 and ns.AllItemsModel and ns.AllItemsModel.PatchMetaTargeted then
                local patched = ns.AllItemsModel.PatchMetaTargeted(currentRows, S.evaluation, mt)
                if patched > 0 then
                    S.cellCacheEpoch = S.cellCacheEpoch + 1
                    local col = H.resolveSort()
                    local ownSens = mt.hasOwnership and (col == 'ownedQty')
                    if ownSens then
                        S.metaEpoch = S.metaEpoch + 1
                        H.clearRetained()
                    else
                        S.filterLRU:evictWhere(function(tag)
                            return tag and mt.hasOwnership and tag.ownSens == true
                        end)
                        if H.active() then aiProvider.RepaintVisible() end
                    end
                end
            end
        elseif sig ~= S.signature then
            S.metaDirty = false
            S.metaTargets = nil
            S.itemChanges = {}
            aiProvider.Cancel()
            S.buildState = nil
            S.rows = nil
            S.filteredRows = nil
            S.signature = sig
            S.builtPriceRev = uiCache.curPriceRev()
            S.metaEpoch = S.metaEpoch + 1
            H.clearRetained()
            S.evaluation = {
                dataset = sig,
                db = db,
                econInfo = c.econInfo,
                ownedCounts = c.counts,
                ownedCountsByID = sc and sc.ownedCountsByID,
                profMap = c.profMap or (sc and sc.profMap),
                repState = c.repState or (sc and sc.repState),
                revision = c.revision or (sc and sc.revision),
                charKey = c.charKey or (sc and sc.charKey),
                applyAHCut = (sc and sc.applyAHCut ~= nil) and sc.applyAHCut or (db.applyAHCut ~= false),
                defer = c.defer,
                background = c.background == true,
                priority = H.buildPriority(c),
            }
        else
            if S.evaluation then
                S.evaluation.ownedCounts = c.counts
                S.evaluation.ownedCountsByID = sc and sc.ownedCountsByID
                if c.defer ~= nil then S.evaluation.defer = c.defer end
            end
        end
    end

    function H.bindFilteredRows(filtered, totalCount, sig, fKey)
        local t = S.tbl
        local v = S.view
        if not (t and v) then return end
        S.filteredRows = filtered
        local currentWidth = (S.host and S.host.parent and S.host.parent:GetWidth()) or (v.GetWidth and v:GetWidth()) or 0
        if currentWidth > 0 and S.boundWidth ~= currentWidth then
            S.boundWidth = currentWidth
            aiProvider.Layout(currentWidth)
            H.styleHeaders()
        end
        if S.boundResult ~= filtered or S.boundDatasetSig ~= sig or S.boundFilterKey ~= fKey or S.boundMetaEpoch ~= S.metaEpoch then
            S.viewWasHidden = false
            if type(t.setRows) == 'function' then
                t.setRows(filtered)
            elseif t.scrollBox and t.scrollBox.SetDataProvider and CreateDataProvider then
                t.scrollBox:SetDataProvider(CreateDataProvider(filtered))
            end
            S.boundResult = filtered
            S.boundDatasetSig = sig
            S.boundFilterKey = fKey
            S.boundMetaEpoch = S.metaEpoch
        elseif S.viewWasHidden then
            S.viewWasHidden = false
            H.rebindStaleRows()
        end
        if v.summary then
            v.summary:SetText(string.format('%d / %d items', #filtered, tonumber(totalCount or #filtered) or 0))
        end
        if v.emptyText then
            v.emptyText:SetShown(#filtered == 0)
        end
    end

    function H.createFilterSortJob(dataRows, filters, sort, yieldBudget)
        local sortWorkspace = { values = {}, names = {}, keys = {}, keepEntries = true }
        local isNumeric = C.NUMERIC_KEYS[sort.key or 'turnoverPerDay'] == true
        local ascending = sort.ascending == true
        local function before(a, b)
            local av, bv = sortWorkspace.values[a], sortWorkspace.values[b]
            if isNumeric then
                if av == false and bv ~= false then return false end
                if av ~= false and bv == false then return true end
                if av ~= false and av ~= bv then
                    if ascending then return av < bv else return av > bv end
                end
            else
                if av ~= bv then
                    if ascending then return av < bv else return av > bv end
                end
            end
            local an, bn = sortWorkspace.names[a], sortWorkspace.names[b]
            if an ~= bn then return an < bn end
            return (sortWorkspace.keys[a] or 0) < (sortWorkspace.keys[b] or 0)
        end
        return coroutine.create(function()
            local aiModel = ns.AllItemsModel
            if not (aiModel and aiModel.FilterSort) then return {} end
            local runs = {}
            for first = 1, #dataRows, 96 do
                local block = {}
                for i = first, math.min(first + 95, #dataRows) do
                    if i > first and (i - first) % 24 == 0 then yieldBudget() end
                    block[#block + 1] = dataRows[i]
                end
                yieldBudget()
                runs[#runs + 1] = aiModel.FilterSort(block, filters, sort, sortWorkspace)
                yieldBudget()
            end
            while #runs > 1 do
                local nextRuns = {}
                for i = 1, #runs, 2 do
                    local a, b = runs[i], runs[i + 1]
                    if not b then
                        nextRuns[#nextRuns + 1] = a
                    else
                        local merged, ai, bi = {}, 1, 1
                        while ai <= #a or bi <= #b do
                            if bi > #b or (ai <= #a and before(a[ai], b[bi])) then
                                merged[#merged + 1] = a[ai]; ai = ai + 1
                            else
                                merged[#merged + 1] = b[bi]; bi = bi + 1
                            end
                            if (#merged) % 24 == 0 then yieldBudget() end
                        end
                        nextRuns[#nextRuns + 1] = merged
                    end
                    yieldBudget()
                end
                runs = nextRuns
            end
            return runs[1] or {}
        end)
    end

    function H.present(rows, totalCount, sig, fKey, col)
        local t = S.tbl
        local v = S.view
        if not (t and v) then return end
        local dataRows = rows or {}
        sig = sig or S.signature
        local resolvedCol, asc = H.resolveSort()
        col = col or resolvedCol
        fKey = fKey or H.buildFilterKey(S.latest, col, asc)
        local filters = H.filtersFromDB()
        local sort = { key = col, ascending = asc }
        S.presentSeq = S.presentSeq + 1
        local mySeq = S.presentSeq
        local token = S.generation
        local presentMetaEpoch = S.metaEpoch
        local useSync = (#dataRows <= 250) or not (C_Timer and C_Timer.After) or (S.evaluation and S.evaluation.defer == false)
        if useSync then
            S.inFlightPresent = nil
            local filtered = ns.AllItemsModel.FilterSort(dataRows, filters, sort, S.sortWorkspace)
            S.retainedResult = filtered
            S.retainedDatasetSig = sig
            S.retainedFilterKey = fKey
            S.retainedMetaEpoch = presentMetaEpoch
            S.filterLRU:put(uiCache.makeLRUKey(sig, presentMetaEpoch, fKey), filtered, { ownSens = (col == 'ownedQty') })
            H.bindFilteredRows(filtered, totalCount or #dataRows, sig, fKey)
            H.styleHeaders()
            return
        end
        S.inFlightPresent = {
            seq = mySeq, sig = sig, metaEpoch = presentMetaEpoch,
            fKey = fKey, dataRows = dataRows,
        }
        local function isCurrent()
            return mySeq == S.presentSeq and token == S.generation and H.active() and S.signature == sig
        end
        local function clearInFlight()
            if S.inFlightPresent and S.inFlightPresent.seq == mySeq then
                S.inFlightPresent = nil
            end
        end
        local deadline
        local function yieldBudget()
            if clockMS() >= deadline then coroutine.yield() end
        end
        local job = H.createFilterSortJob(dataRows, filters, sort, yieldBudget)
        local function startCommit(filtered)
            local preIdx = 0
            local pal = getThemePalette()
            local function commit()
                if not isCurrent() then clearInFlight(); return end
                local rowH = (S.host and S.host.rowHeight) or 22
                local boxH = (t.scrollBox and t.scrollBox.GetHeight and t.scrollBox:GetHeight()) or 400
                local needed = math.ceil(math.max(1, boxH) / rowH) + 4
                local existing = 0
                if t.scrollBox and t.scrollBox.ForEachFrame then
                    t.scrollBox:ForEachFrame(function(r) if r.cellGroup then existing = existing + 1 end end)
                end
                local target = math.max(0, math.min(#filtered, needed) - existing)
                if #S.prepared < target then
                    local started = clockMS()
                    for _ = 1, 4 do
                        S.prepared[#S.prepared + 1] = H.prepareCells()
                        if #S.prepared >= target or (clockMS() - started) >= 0.9 then break end
                    end
                    H.laterGuarded(commit)
                    return
                end
                local preTarget = math.min(#filtered, needed)
                if preIdx < preTarget then
                    local started = clockMS()
                    for _ = 1, 12 do
                        preIdx = preIdx + 1
                        H.formatCellValues(filtered[preIdx], pal)
                        if preIdx >= preTarget or (clockMS() - started) >= 1.2 then break end
                    end
                    H.laterGuarded(commit)
                    return
                end
                if not isCurrent() then clearInFlight(); return end
                clearInFlight()
                S.retainedResult = filtered
                S.retainedDatasetSig = sig
                S.retainedFilterKey = fKey
                S.retainedMetaEpoch = presentMetaEpoch
                S.filterLRU:put(uiCache.makeLRUKey(sig, presentMetaEpoch, fKey), filtered, { ownSens = (col == 'ownedQty') })
                H.bindFilteredRows(filtered, totalCount or #dataRows, sig, fKey)
                H.styleHeaders()
            end
            H.laterGuarded(commit)
        end
        local function runStep()
            if not isCurrent() then clearInFlight(); return end
            deadline = clockMS() + 1.6
            local ok, filtered = coroutine.resume(job)
            if not ok then clearInFlight(); error(filtered) end
            if coroutine.status(job) ~= 'dead' then
                H.laterGuarded(runStep)
                return
            end
            if not filtered then clearInFlight(); return end
            startCommit(filtered)
        end
        H.laterGuarded(runStep)
    end

    function H.makeForegroundHandlers(token, seq, sig, fKey, col)
        local function isCurr()
            return S.presentSeq == seq and token == S.generation
        end
        local function onProgress(partialRows, done, total)
            if not isCurr() then return end
            S.rows = partialRows
            if S.view and S.view.summary and H.active() then
                if S.earlyPresentedFilterKey == fKey and S.earlyCountShown ~= nil then
                    S.view.summary:SetText(string.format('%d / %d items (warming %d/%d)', S.earlyCountShown, total or 0, done or 0, total or 0))
                else
                    S.view.summary:SetText(string.format('Loading items: %d / %d', done or #(partialRows or {}), total or 0))
                end
            end
        end
        local function onTierReady(partialRows, done, total)
            if not isCurr() or not H.active() then return end
            local copy = {}
            for i = 1, #(partialRows or {}) do copy[i] = partialRows[i] end
            S.rows = copy
            local curCol, curAsc = H.resolveSort()
            local curFKey = H.buildFilterKey(S.latest, curCol, curAsc)
            local filters = H.filtersFromDB()
            local filtered = ns.AllItemsModel.FilterSort(copy, filters, { key = curCol, ascending = curAsc }, S.sortWorkspace)
            S.earlyPresentedFilterKey = curFKey
            S.earlyBoundResult = filtered
            S.earlyCountShown = #filtered
            S.earlyTier1Done = done
            S.earlyWarmTotal = total
            S.earlyAuthoritative = S.buildState and S.buildState.tier1Authoritative == true
            H.bindFilteredRows(filtered, total or #copy, sig, curFKey)
            if S.view and S.view.summary then
                S.view.summary:SetText(string.format('%d / %d items (warming %d/%d)', #filtered, total or 0, done or #copy, total or 0))
            end
            H.styleHeaders()
        end
        local function onComplete(rows)
            if token ~= S.generation then return end
            S.cancelBuild = nil
            S.rows = rows
            if S.presentSeq ~= seq then
                return
            end
            S.inFlightPresent = nil
            S.cellCacheEpoch = S.cellCacheEpoch + 1
            local curCol, curAsc = H.resolveSort()
            local curFKey = H.buildFilterKey(S.latest, curCol, curAsc)
            if not S.metaDirty and not S.metaTargets and not next(S.itemChanges)
                and S.earlyPresentedFilterKey == curFKey and S.earlyAuthoritative and S.earlyBoundResult then
                local earlyResult = S.earlyBoundResult
                S.earlyPresentedFilterKey = nil
                S.earlyBoundResult = nil
                S.retainedResult = earlyResult
                S.retainedDatasetSig = S.signature
                S.retainedFilterKey = curFKey
                S.retainedMetaEpoch = S.metaEpoch
                S.filterLRU:put(uiCache.makeLRUKey(S.signature, S.metaEpoch, curFKey), earlyResult, { ownSens = (curCol == 'ownedQty') })
                S.boundResult = earlyResult
                S.boundDatasetSig = S.signature
                S.boundFilterKey = curFKey
                S.boundMetaEpoch = S.metaEpoch
                if S.view and S.view.summary then
                    S.view.summary:SetText(string.format('%d / %d items', #earlyResult, #rows))
                end
                aiProvider.RepaintVisible()
                H.styleHeaders()
                return
            end
            S.earlyPresentedFilterKey = nil
            S.earlyBoundResult = nil
            H.present(rows, #rows, S.signature, curFKey, curCol)
        end
        return onProgress, onComplete, onTierReady
    end

    function H.resetFilters()
        if S.host and S.host.resetAllItemsFilters then
            S.host.resetAllItemsFilters()
            return
        end
        local db = H.getDB()
        if type(db) == 'table' then
            db.allItemsProfFilter = 'all'
            db.allItemsTypes = nil
            db.allItemsRoleFilter = 'all'
            db.allItemsSellableFilter = 'all'
            db.allItemsDemandFilter = 'all'
            db.allItemsSkillMin = nil
            db.allItemsSkillMax = nil
        end
        if S.latest then
            S.latest.profFilter = 'all'
            S.latest.search = ''
        end
        H.updateFilterControls(db)
        aiProvider.Refresh()
    end

    function H.applyTheme()
        local pal = getThemePalette()
        local v = S.view
        if not v then return end
        if v._mmCard and v._mmCard.UpdateTheme then v._mmCard:UpdateTheme() end
        if v.barSep and v.barSep.SetColorTexture then
            if pal and pal.separator then
                v.barSep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.65)
            else
                v.barSep:SetColorTexture(0.5, 0.5, 0.54, 0.25)
            end
        end
        if v.summary and pal and pal.textSecondary then
            v.summary:SetTextColor(pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1)
        end
        if v.emptyText and pal and pal.textMuted then
            v.emptyText:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1)
        end
        if v.skillControl and pal and pal.textMuted then
            if v.skillControl.lbl then v.skillControl.lbl:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1) end
            if v.skillControl.dash then v.skillControl.dash:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1) end
        end
        H.clearInsetChrome()
        H.styleHeaders()
        H.themeColumnSettingsPopover()
        aiProvider.RepaintVisible()
        if S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame then
            S.tbl.scrollBox:ForEachFrame(H.paintRowSep)
        end
    end

    function H.updateShiftHeader()
        local v = S.view
        if not v then return end
        if v.shiftBadge and v.shiftBadge.SetShown then
            v.shiftBadge:SetShown(S.shiftActive == true)
        end
        if v.summary and v.summary.ClearAllPoints and v.summary.SetPoint then
            v.summary:ClearAllPoints()
            if v.summaryLeftAnchor then
                v.summary:SetPoint('LEFT', v.summaryLeftAnchor, 'RIGHT', 8, 0)
            end
            if S.shiftActive and v.shiftBadge then
                v.summary:SetPoint('RIGHT', v.shiftBadge, 'LEFT', -8, 0)
            elseif v.filtersButton then
                v.summary:SetPoint('RIGHT', v.filtersButton, 'LEFT', -8, 0)
            elseif v.resetButton then
                v.summary:SetPoint('RIGHT', v.resetButton, 'LEFT', -8, 0)
            end
        end
    end

    function H.buildHeader(v, T)
        local bar = CreateFrame('Frame', nil, v)
        bar:SetPoint('TOPLEFT', 0, 0)
        bar:SetPoint('TOPRIGHT', 0, 0)
        bar:SetHeight(40)
        v.headerBar = bar
        local barSep = bar:CreateTexture(nil, 'BORDER')
        barSep:SetPoint('BOTTOMLEFT', 0, 0)
        barSep:SetPoint('BOTTOMRIGHT', 0, 0)
        barSep:SetHeight(1)
        v.barSep = barSep

        v.profBtns = {}
        v.profOrder = {}
        local prevPill
        for idx, spec in ipairs(C.PROF_PILLS) do
            local pw = math.max(28, #spec.label * 6 + 12)
            local btn = T and T.CreatePlateButton and T.CreatePlateButton(bar, spec.label, pw, 22, { variant = 'secondary', pill = true, fontSize = 10, weight = 'semibold' })
                or CreateFrame('Button', nil, bar)
            btn:SetSize(pw, 22)
            local pfs = (btn.GetFontString and btn:GetFontString()) or btn.fs
            if pfs and pfs.SetJustifyV then pfs:SetJustifyV('MIDDLE') end
            if idx == 1 then
                btn:SetPoint('LEFT', bar, 'LEFT', 8, 0)
            else
                btn:SetPoint('LEFT', prevPill, 'RIGHT', 3, 0)
            end
            btn.profKey = spec.key
            btn:SetScript('OnClick', function()
                local db = H.getDB()
                if type(db) == 'table' then db.allItemsProfFilter = spec.key end
                if S.latest then S.latest.profFilter = spec.key end
                H.updateFilterControls(db)
                aiProvider.Refresh()
            end)
            btn:SetScript('OnEnter', function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, 'ANCHOR_BOTTOM')
                GameTooltip:SetText(spec.label, 1, 0.85, 0.25)
                GameTooltip:AddLine(spec.tip, 1, 1, 1, true)
                H.liftAndShowTooltip()
            end)
            btn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
            v.profBtns[spec.key] = btn
            v.profOrder[idx] = btn
            prevPill = btn
        end

        local function attachHeaderTooltip(btn, title, body, anchor)
            btn:SetScript('OnEnter', function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, anchor or 'ANCHOR_BOTTOMLEFT')
                GameTooltip:AddLine(title, 1, 0.85, 0.25)
                GameTooltip:AddLine(body, 1, 1, 1, true)
                H.liftAndShowTooltip()
            end)
            btn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
        end

        v.colSettingsBtn = T and T.CreatePlateButton and T.CreatePlateButton(bar, 'Cols', 54, 26, { variant = 'secondary', pill = true, fontSize = 11 })
            or CreateFrame('Button', nil, bar)
        v.colSettingsBtn:SetSize(54, 26)
        v.colSettingsBtn:SetPoint('RIGHT', bar, 'RIGHT', -8, 0)
        if v.colSettingsBtn.fs and v.colSettingsBtn.fs.SetJustifyV then v.colSettingsBtn.fs:SetJustifyV('MIDDLE') end
        v.colSettingsBtn:SetScript('OnClick', function() aiProvider.ToggleColumnSettings() end)
        attachHeaderTooltip(v.colSettingsBtn, 'Customize Columns', 'Show, hide, and reorder All Items table columns.', 'ANCHOR_BOTTOMLEFT')

        v.shopButton = T and T.CreatePlateButton and T.CreatePlateButton(bar, 'Shop', 62, 26, { variant = 'secondary', pill = true, fontSize = 11 })
            or CreateFrame('Button', nil, bar)
        v.shopButton:SetSize(62, 26)
        v.shopButton:SetPoint('RIGHT', v.colSettingsBtn, 'LEFT', -6, 0)
        if v.shopButton.fs and v.shopButton.fs.SetJustifyV then v.shopButton.fs:SetJustifyV('MIDDLE') end
        v.shopButton:SetScript('OnClick', function()
            if S.host and S.host.toggleShoppingWindow then
                S.host.toggleShoppingWindow(true)
            elseif S.host and S.host.openShoppingWindow then
                S.host.openShoppingWindow(true)
            end
        end)
        attachHeaderTooltip(v.shopButton, 'Shopping List', 'Open or close the Shopping List window.', 'ANCHOR_BOTTOMLEFT')

        v.resetButton = T and T.CreatePlateButton and T.CreatePlateButton(bar, 'Reset', 58, 26, { variant = 'secondary', pill = true, fontSize = 11 })
            or CreateFrame('Button', nil, bar)
        v.resetButton:SetSize(58, 26)
        v.resetButton:SetPoint('RIGHT', v.shopButton, 'LEFT', -6, 0)
        if v.resetButton.fs and v.resetButton.fs.SetJustifyV then v.resetButton.fs:SetJustifyV('MIDDLE') end
        v.resetButton:SetScript('OnClick', H.resetFilters)
        attachHeaderTooltip(v.resetButton, 'Reset Filters', 'Clear active profession, type, role, skill, and search filters.', 'ANCHOR_BOTTOMLEFT')

        v.filtersButton = T and T.CreatePlateButton and T.CreatePlateButton(bar, 'Filters', 66, 26, { variant = 'secondary', pill = true, fontSize = 11, icon = T and T.ASSETS and T.ASSETS.icon_bars, iconSize = 11 })
            or CreateFrame('Button', nil, bar)
        v.filtersButton:SetSize(66, 26)
        v.filtersButton:SetPoint('RIGHT', v.resetButton, 'LEFT', -6, 0)
        if v.filtersButton.fs and v.filtersButton.fs.SetJustifyV then v.filtersButton.fs:SetJustifyV('MIDDLE') end
        v.filtersButton:SetScript('OnClick', function(self)
            if S.host and S.host.toggleScreenFilters then
                S.host.toggleScreenFilters(self)
            elseif S.host and S.host.toggleFiltersPopover then
                S.host.toggleFiltersPopover(self)
            end
        end)
        attachHeaderTooltip(v.filtersButton, 'All Items Filters', 'Filter items by type, role, tradeability, demand, and skill range.', 'ANCHOR_BOTTOMLEFT')

        local badgePill = (type(T) == 'table' and type(T.CreateBadgePill) == 'function')
            and T.CreateBadgePill(bar, 'Quick-Add Mode', 'blue', { height = 22, fontSize = 11, padX = 12 })
            or nil
        local shiftBadge = badgePill and badgePill.frame or CreateFrame('Frame', nil, bar)
        shiftBadge._pill = badgePill
        if not badgePill then
            shiftBadge:SetSize(102, 22)
            shiftBadge.label = shiftBadge:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
            shiftBadge.label:SetAllPoints()
            shiftBadge.label:SetJustifyH('CENTER')
            if shiftBadge.label.SetJustifyV then shiftBadge.label:SetJustifyV('MIDDLE') end
            shiftBadge.label:SetText('Quick-Add Mode')
            applyFont(shiftBadge.label, 11, 'semibold')
        elseif badgePill.label and badgePill.label.SetJustifyV then
            badgePill.label:SetJustifyV('MIDDLE')
        end
        shiftBadge:SetPoint('RIGHT', v.filtersButton, 'LEFT', -8, 0)
        shiftBadge:EnableMouse(true)
        attachHeaderTooltip(shiftBadge, 'Quick-Add Mode', 'Hold Shift and left-click a row to add +1 to Shopping List, or right-click to remove -1.', 'ANCHOR_BOTTOM')
        shiftBadge:Hide()
        v.shiftBadge = shiftBadge

        v.summaryLeftAnchor = prevPill
        v.summary = bar:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        v.summary:SetJustifyH('RIGHT')
        if v.summary.SetJustifyV then v.summary:SetJustifyV('MIDDLE') end
        v.summary:SetWordWrap(false)
        applyFont(v.summary, 11, 'regular')
        v.summary:SetText('0 / 0 items')
        H.updateShiftHeader()
    end

    function H.buildSidebarControls(v, context, T)
        local sbParent = (context and context.sidebarParent) or v

        local function makeSidebarBtn(txt, onClick, isDrop)
            local btn = CreateFrame('Button', nil, sbParent, 'UIPanelButtonTemplate')
            btn:SetSize(194, 21)
            btn:SetText(txt)
            if T and T.SkinButton then T.SkinButton(btn, isDrop and { dropdown = true } or { primary = false }) end
            btn._isCheck = false
            btn:Hide()
            btn:SetScript('OnClick', onClick)
            return btn
        end

        v.typeButton = makeSidebarBtn('Types: All', function(self)
            local db = H.getDB()
            if type(db) ~= 'table' then return end
            db.allItemsTypes = type(db.allItemsTypes) == 'table' and db.allItemsTypes or {}
            local opts = { { key = 'all', label = 'All Types', checked = (next(db.allItemsTypes) == nil) } }
            for _, spec in ipairs(C.ITEM_TYPES) do
                opts[#opts + 1] = { key = spec.key, label = spec.label, checked = db.allItemsTypes[spec.key] == true }
            end
            if T and T.OpenDropDown then
                T.OpenDropDown(self, opts, nil, function(key)
                    if key == 'all' then
                        wipe(db.allItemsTypes)
                    else
                        db.allItemsTypes[key] = not db.allItemsTypes[key]
                        if db.allItemsTypes[key] == false then db.allItemsTypes[key] = nil end
                    end
                    H.updateFilterControls(db)
                    aiProvider.Refresh()
                end)
            end
        end, true)

        v.roleButton = makeSidebarBtn('Role: All', function(self)
            local db = H.getDB()
            local cur = (type(db) == 'table' and db.allItemsRoleFilter) or 'all'
            if T and T.OpenDropDown then
                T.OpenDropDown(self, C.ROLE_FILTERS, cur, function(key)
                    if type(db) == 'table' then db.allItemsRoleFilter = key end
                    H.updateFilterControls(db)
                    aiProvider.Refresh()
                end)
            end
        end, true)

        v.sellableButton = makeSidebarBtn('Trade: All', function(self)
            local db = H.getDB()
            local cur = (type(db) == 'table' and db.allItemsSellableFilter) or 'all'
            if T and T.OpenDropDown then
                T.OpenDropDown(self, C.SELLABLE_FILTERS, cur, function(key)
                    if type(db) == 'table' then db.allItemsSellableFilter = key end
                    H.updateFilterControls(db)
                    aiProvider.Refresh()
                end)
            end
        end, true)

        v.demandButton = makeSidebarBtn('Demand: All', function(self)
            local db = H.getDB()
            local cur = (type(db) == 'table' and db.allItemsDemandFilter) or 'all'
            if T and T.OpenDropDown then
                T.OpenDropDown(self, H.demandFilters(), cur, function(key)
                    if type(db) == 'table' then db.allItemsDemandFilter = key end
                    H.updateFilterControls(db)
                    aiProvider.Refresh()
                end)
            end
        end, true)

        local skillWrap = CreateFrame('Frame', nil, sbParent)
        skillWrap:SetSize(194, 22)
        skillWrap._sidebarHeight = 24
        skillWrap:Hide()
        local lbl = skillWrap:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        lbl:SetPoint('LEFT', skillWrap, 'LEFT', 2, 0)
        lbl:SetText('Skill')
        applyFont(lbl, 11, 'regular')
        local minBox = CreateFrame('EditBox', nil, skillWrap, 'InputBoxTemplate')
        minBox:SetSize(56, 20)
        minBox:SetPoint('LEFT', lbl, 'RIGHT', 8, 0)
        minBox:SetAutoFocus(false)
        local dash = skillWrap:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        dash:SetPoint('LEFT', minBox, 'RIGHT', 4, 0)
        dash:SetText('-')
        applyFont(dash, 11, 'regular')
        local maxBox = CreateFrame('EditBox', nil, skillWrap, 'InputBoxTemplate')
        maxBox:SetSize(56, 20)
        maxBox:SetPoint('LEFT', dash, 'RIGHT', 4, 0)
        maxBox:SetAutoFocus(false)
        local function commitSkill()
            skillWrap._editing = false
            local db = H.getDB()
            if type(db) == 'table' then
                local lo = ns.SuperListModel and ns.SuperListModel.SkillBound(minBox:GetText())
                local hi = ns.SuperListModel and ns.SuperListModel.SkillBound(maxBox:GetText())
                db.allItemsSkillMin = lo
                db.allItemsSkillMax = hi
            end
            H.updateFilterControls(db)
            aiProvider.Refresh()
        end
        for _, box in ipairs({ minBox, maxBox }) do
            if T and T.SkinEditBox then T.SkinEditBox(box) end
            box:SetScript('OnEditFocusGained', function() skillWrap._editing = true end)
            box:SetScript('OnEnterPressed', function(self) if self.ClearFocus then self:ClearFocus() end; commitSkill() end)
            box:SetScript('OnEditFocusLost', commitSkill)
            box:SetScript('OnEscapePressed', function(self) if self.ClearFocus then self:ClearFocus() end; H.updateFilterControls() end)
        end
        skillWrap.lbl, skillWrap.minBox, skillWrap.dash, skillWrap.maxBox = lbl, minBox, dash, maxBox
        v.skillControl = skillWrap

        v.resetFiltersButton = makeSidebarBtn('Reset Filters', H.resetFilters, false)
    end

    function aiProvider.GetSidebarControls()
        local v = S.view
        if not v then return {} end
        return { v.typeButton, v.roleButton, v.sellableButton, v.demandButton, v.skillControl, v.resetFiltersButton }
    end

    function aiProvider.GetColumnConfig()
        return H.normalizeColumnConfig(H.getDB())
    end

    function aiProvider.SetColumnVisible(key, visible)
        local db = H.getDB()
        local cfg, byKey = H.normalizeColumnConfig(db)
        if not byKey[key] or byKey[key].locked then return end
        cfg.hidden[key] = (not visible) and true or nil
        H.applyColumnConfig(db)
        H.refreshColumnPopover()
    end

    function aiProvider.MoveColumn(key, delta)
        local db = H.getDB()
        local cfg, byKey = H.normalizeColumnConfig(db)
        if not byKey[key] or byKey[key].locked then return end
        local idx
        for i, k in ipairs(cfg.order) do
            if k == key then idx = i; break end
        end
        if not idx then return end
        local dst = idx + (delta or 0)
        if dst < 2 or dst > #cfg.order then return end
        cfg.order[idx], cfg.order[dst] = cfg.order[dst], cfg.order[idx]
        H.applyColumnConfig(db)
        H.refreshColumnPopover()
    end

    function aiProvider.ResetColumns()
        local db = H.getDB()
        if type(db) == 'table' then
            db.allItemsColumns = nil
        else
            S.fallbackColConfig = { order = {}, hidden = {} }
            for i, col in ipairs(C.ITEM_COLUMNS) do
                S.fallbackColConfig.order[i] = col.key
                if col.defaultHidden then S.fallbackColConfig.hidden[col.key] = true end
            end
        end
        H.applyColumnConfig(db)
        H.refreshColumnPopover()
    end

    function aiProvider.ToggleColumnSettings(force)
        local pop = S.view and S.view.colSettingsPopover
        if not pop then return false end
        local want = force
        if want == nil then want = not shown(pop) end
        if want then
            H.refreshColumnPopover()
            H.themeColumnSettingsPopover()
            pop:Show()
        else
            pop:Hide()
        end
        return shown(pop)
    end

    function aiProvider.CloseHeatPopover()
        H.closeHeatPopover()
    end

    function aiProvider.GetHeatPopover()
        local pop = type(S.view) == 'table' and rawget(S.view, 'heatPopover') or nil
        return (type(pop) == 'table' or type(pop) == 'userdata') and pop or nil
    end

    function aiProvider.SetShiftMode(on)
        local want = on == true
        if S.shiftActive == want then return end
        S.shiftActive = want
        H.updateShiftHeader()
        aiProvider.RepaintShoppingQty()
    end

    function aiProvider.RepaintShoppingQty()
        if not (S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame) then return end
        local pal = getThemePalette()
        S.tbl.scrollBox:ForEachFrame(function(r)
            if r.data then H.paintRowShiftUI(r, pal) end
        end)
    end

    function aiProvider.RepaintVisible()
        if not (S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame) then return end
        local db = H.getDB()
        local _, cfg = H.getActiveColumnDefs(db)
        if S.appliedColSig ~= fingerprint(cfg) then
            H.applyColumnConfig(db)
            return
        end
        S.tbl.scrollBox:ForEachFrame(function(r)
            if r.data then H.bindRow(r, r.data) end
        end)
    end

    function aiProvider.CancelPresentation()
        S.presentSeq = S.presentSeq + 1
        S.pending = false
        S.viewWasHidden = true
        S.inFlightPresent = nil
        if S.buildState and S.buildState.running then
            S.buildState.background = true
            S.buildState.onProgress = nil
            S.buildState.onTierReady = nil
            if S.evaluation then S.evaluation.background = true end
        end
    end

    function aiProvider.Cancel()
        S.generation = S.generation + 1
        S.presentSeq = S.presentSeq + 1
        S.prewarmSeq = S.prewarmSeq + 1
        S.pending = false
        S.reconcilePending = false
        S.reconcileSeq = (S.reconcileSeq or 0) + 1
        S.inFlightPresent = nil
        if S.cancelBuild then S.cancelBuild(); S.cancelBuild = nil end
    end

    function aiProvider.HasWarmData()
        return S.buildState ~= nil and type(S.rows) == 'table' and S.buildState.completed == true
    end

    function aiProvider.IsWarming()
        return S.buildState ~= nil and S.buildState.running == true and S.buildState.background == true
    end

    function aiProvider.Invalidate(reason, itemIDs)
        if not reason then
            aiProvider.Cancel()
            S.signature = nil
            S.builtPriceRev = nil
            S.buildState = nil
            S.rows = nil
            S.filteredRows = nil
            S.metaDirty = false
            S.metaTargets = nil
            S.itemChanges = {}
            H.clearRetained()
            S.metaEpoch = S.metaEpoch + 1
            S.forceVersion = S.forceVersion + 1
            S.cellCacheEpoch = S.cellCacheEpoch + 1
            if ns.AllItemsModel and ns.AllItemsModel.ClearCache then ns.AllItemsModel.ClearCache() end
            return
        end
        if reason == 'sellers' or reason == 'cooldown' or reason == 'skills' or reason == 'known' or reason == 'trainer' or reason == 'rep' then
            return
        end
        S.changes[reason] = true
        if reason == 'ownership' then
            if type(itemIDs) == 'table' and (itemIDs.ids ~= nil or itemIDs.names ~= nil) then
                local hasAny = (type(itemIDs.ids) == 'table' and next(itemIDs.ids) ~= nil)
                    or (type(itemIDs.names) == 'table' and next(itemIDs.names) ~= nil)
                if hasAny then
                    S.metaTargets = S.metaTargets or { ids = {}, names = {} }
                    S.metaTargets.hasOwnership = true
                    if type(itemIDs.ids) == 'table' then
                        for k, v in pairs(itemIDs.ids) do
                            local id = type(v) == 'number' and v or (type(k) == 'number' and k)
                            if id and v ~= false then S.metaTargets.ids[id] = true end
                        end
                    end
                    if type(itemIDs.names) == 'table' then
                        for k, v in pairs(itemIDs.names) do
                            local nm = type(v) == 'string' and v or (type(k) == 'string' and k)
                            if nm and v ~= false then S.metaTargets.names[nm] = true end
                        end
                    end
                end
            else
                S.metaDirty = true
            end
        elseif reason == 'items' and type(itemIDs) == 'table' then
            for k, v in pairs(itemIDs) do
                local id = type(v) == 'number' and v or (type(k) == 'number' and k)
                if id and v ~= false then S.itemChanges[id] = true end
            end
        end
        if S.reconcilePending then return end
        S.reconcilePending = true
        S.reconcileSeq = (S.reconcileSeq or 0) + 1
        local myRecSeq = S.reconcileSeq
        H.laterGuarded(function()
            if myRecSeq ~= S.reconcileSeq then return end
            S.reconcilePending = false
            local itemsOnly = H.applyPendingChanges()
            if S.latest and H.active() then
                if not itemsOnly and S.latest.hostManaged and S.host and S.host.refresh then
                    S.host.refresh()
                else
                    aiProvider.Refresh(S.latest)
                end
            end
        end)
    end

    function aiProvider.PatchMeta(context, targets)
        local currentRows = (S.buildState and S.buildState.rows) or S.rows
        if not (type(currentRows) == 'table' and ns.AllItemsModel) then return 0 end
        local patched = 0
        if targets and (targets.ids or targets.names) and ns.AllItemsModel.PatchMetaTargeted then
            patched = ns.AllItemsModel.PatchMetaTargeted(currentRows, context or S.evaluation or S.latest, targets)
        elseif ns.AllItemsModel.PatchMeta then
            ns.AllItemsModel.PatchMeta(currentRows, context or S.evaluation or S.latest)
            patched = #currentRows
        end
        if patched > 0 then
            S.cellCacheEpoch = S.cellCacheEpoch + 1
            local col = H.resolveSort()
            if col == 'ownedQty' then
                S.metaEpoch = S.metaEpoch + 1
                H.clearRetained()
            else
                S.filterLRU:evictWhere(function(tag)
                    return tag and tag.ownSens == true
                end)
                aiProvider.RepaintVisible()
            end
        end
        return patched
    end

    function aiProvider.WarmInBackground(context)
        if not (ns.AllItemsModel and ns.AllItemsModel.Start) then return false end
        if context then S.warmContext = context; S.latest = context end
        local ctx = context or S.warmContext or S.latest
        if not ctx then return false end
        local sig = H.computeDatasetSig(ctx)
        H.syncEvaluationState(ctx, sig)
        local priority = H.buildPriority(ctx)
        if S.buildState and S.buildState.completed then
            S.rows = S.rows or S.buildState.rows
            return true
        end
        if S.buildState and S.buildState.running then
            if S.buildState.priorityKey ~= priority.key then
                if S.evaluation then S.evaluation.priority = priority end
                if ns.AllItemsModel.Reprioritize then
                    ns.AllItemsModel.Reprioritize(S.buildState, priority)
                end
            end
            return true
        end
        if S.evaluation then
            S.evaluation.background = true
            S.evaluation.priority = priority
        end
        local token = S.generation
        local finished = false
        local function onBgComplete(rows)
            if token ~= S.generation then return end
            finished = true
            S.cancelBuild = nil
            S.rows = rows
            if H.active() and S.latest and not S.pending then
                aiProvider.Refresh(S.latest)
            end
        end
        local cancel, state = ns.AllItemsModel.Start(S.evaluation, nil, onBgComplete, S.buildState, nil)
        S.buildState = state
        if not finished and token == S.generation then S.cancelBuild = cancel end
        return true
    end

    function aiProvider.Layout(width, _, deferScrollRefresh)
        local t = S.tbl
        local v = S.view
        if not (t and v) then return end
        local w = tonumber(width) or (v.GetWidth and v:GetWidth()) or 0
        if w <= 0 then return end
        if ns.Window and ns.Window.LayoutTable then
            local hdrW = (t.headerBar and t.headerBar.GetWidth and t.headerBar:GetWidth()) or 0
            ns.Window.LayoutTable(t, math.max(hdrW, w - 24), 1, deferScrollRefresh)
        end
        if t.scrollBox and t.scrollBox.ForEachFrame then
            local demandW
            for _, col in ipairs(t.columns or {}) do
                if col.key == 'demandSort' then demandW = col.width; break end
            end
            if demandW then
                local stripW = math.max(24, demandW - 4)
                t.scrollBox:ForEachFrame(function(r)
                    local cell = r.cellGroup and r.cellGroup.cellsByKey and r.cellGroup.cellsByKey.demandSort
                    if cell and cell._heatStripBound and cell.heatStrip then
                        cell.heatStrip:Layout(stripW)
                    end
                end)
            end
        end
        local pop = aiProvider.GetHeatPopover()
        if pop and shown(pop) and pop.ownerCell then
            H.repositionHeatPopover(pop, pop.ownerCell)
        end
        H.styleHeaders()
    end

    function aiProvider.Refresh(context)
        if not (S.view and S.tbl and ns.AllItemsModel) then return end
        if context then S.latest = context end
        local ctx = S.latest or {}
        local db = H.getDB(ctx) or {}
        H.updateFilterControls(db)

        if S.appliedColSig ~= fingerprint(H.normalizeColumnConfig(db)) then
            H.applyColumnConfig(db)
        end

        if not H.active() then
            aiProvider.CancelPresentation()
            return
        end
        if S.reconcilePending and next(S.changes) then return end

        local sig = H.computeDatasetSig(ctx)
        H.syncEvaluationState(ctx, sig)

        if S.buildState and S.buildState.completed and next(S.itemChanges) then
            local ids = S.itemChanges
            S.itemChanges = {}
            if S.rows and ns.AllItemsModel.RepairItems then
                local repaired = ns.AllItemsModel.RepairItems(S.rows, S.evaluation, ids)
                if repaired then
                    S.metaEpoch = S.metaEpoch + 1
                    S.cellCacheEpoch = S.cellCacheEpoch + 1
                    H.clearRetained()
                end
            end
        end

        local col, asc = H.resolveSort()
        local fKey = H.buildFilterKey(ctx, col, asc)

        if S.buildState and S.buildState.completed and S.rows then
            if not (S.retainedResult and S.retainedDatasetSig == sig
                and S.retainedFilterKey == fKey and S.retainedMetaEpoch == S.metaEpoch) then
                local lruHit = S.filterLRU:get(uiCache.makeLRUKey(sig, S.metaEpoch, fKey))
                if lruHit then
                    S.retainedResult = lruHit
                    S.retainedDatasetSig = sig
                    S.retainedFilterKey = fKey
                    S.retainedMetaEpoch = S.metaEpoch
                end
            end
            if S.retainedResult and S.retainedDatasetSig == sig
                and S.retainedFilterKey == fKey and S.retainedMetaEpoch == S.metaEpoch then
                S.presentSeq = S.presentSeq + 1
                S.inFlightPresent = nil
                H.bindFilteredRows(S.retainedResult, #S.rows, sig, fKey)
                H.styleHeaders()
                return
            end
            if S.inFlightPresent and S.inFlightPresent.sig == sig
                and S.inFlightPresent.metaEpoch == S.metaEpoch
                and S.inFlightPresent.fKey == fKey
                and S.inFlightPresent.dataRows == S.rows then
                return
            end
            S.inFlightPresent = nil
            H.present(S.rows, #S.rows, sig, fKey, col)
            return
        end

        if S.buildState and S.buildState.running then
            local wasBackground = S.buildState.background == true
            if S.evaluation then S.evaluation.background = false end
            local priority = H.buildPriority(ctx, col)
            local prioChanged = S.buildState.priorityKey ~= priority.key
            if S.evaluation then S.evaluation.priority = priority end
            local onProgress, onComplete, onTierReady = H.makeForegroundHandlers(S.generation, S.presentSeq, sig, fKey, col)
            if wasBackground or not S.buildState.onProgress or not S.buildState.onTierReady then
                if ns.AllItemsModel.Attach then
                    ns.AllItemsModel.Attach(S.buildState, false, priority, onProgress, onComplete, onTierReady)
                elseif ns.AllItemsModel.Reprioritize then
                    ns.AllItemsModel.Reprioritize(S.buildState, priority)
                end
            elseif ns.AllItemsModel.Attach then
                ns.AllItemsModel.Attach(S.buildState, false, priority)
            elseif ns.AllItemsModel.Reprioritize then
                ns.AllItemsModel.Reprioritize(S.buildState, priority)
            end
            local earlyStale = (S.earlyPresentedFilterKey ~= nil and S.earlyPresentedFilterKey ~= fKey)
            if earlyStale then
                S.earlyPresentedFilterKey = nil
                S.earlyBoundResult = nil
                S.earlyCountShown = nil
            end
            if S.earlyPresentedFilterKey == fKey and S.earlyBoundResult then
                H.bindFilteredRows(S.earlyBoundResult, #(S.buildState.order or {}), sig, fKey)
                if S.view.summary then
                    S.view.summary:SetText(string.format('%d / %d items (warming %d/%d)',
                        S.earlyCountShown or #S.earlyBoundResult,
                        S.earlyWarmTotal or #(S.buildState.order or {}),
                        #(S.buildState.rows or {}),
                        #(S.buildState.order or {})))
                end
            elseif S.buildState.tier1Authoritative and S.buildState.index > S.buildState.tier1Target then
                S.buildState.tier1Notified = true
                if S.buildState.onTierReady then
                    S.buildState.onTierReady(S.buildState.rows, #S.buildState.rows, #(S.buildState.order or {}))
                end
            elseif wasBackground or prioChanged or earlyStale or S.viewWasHidden then
                S.viewWasHidden = false
                if S.view.summary then
                    S.view.summary:SetText(string.format('Loading items: %d / %d', #(S.buildState.rows or {}), #(S.buildState.order or {})))
                end
            end
            return
        end

        S.presentSeq = S.presentSeq + 1
        local seq = S.presentSeq
        local priority = H.buildPriority(ctx, col)
        if S.evaluation then
            S.evaluation.background = false
            S.evaluation.priority = priority
        end
        local onProgress, onComplete, onTierReady = H.makeForegroundHandlers(S.generation, seq, sig, fKey, col)
        local cancel, state = ns.AllItemsModel.Start(S.evaluation, onProgress, onComplete, S.buildState, onTierReady)
        S.cancelBuild, S.buildState = cancel, state
        if state and state.completed and state.rows then
            S.rows = state.rows
            H.present(state.rows, #state.rows, sig, fKey, col)
            H.styleHeaders()
        end
    end

    function aiProvider.GetRows()
        return S.rows or {}
    end

    function aiProvider.GetFilteredRows()
        return S.filteredRows or {}
    end

    function aiProvider.Create(parent, context)
        if S.view then return S.view end
        S.host = context
        S.latest = context
        local T = context and context.theme or ns.Theme
        local v = CreateFrame('Frame', nil, parent)
        v:SetAllPoints()
        v:Hide()
        S.view = v

        v:SetScript('OnUpdate', function()
            if not H.active() then return end
            local down = shiftKeyDown()
            if down ~= S.lastShiftDown then
                S.lastShiftDown = down
                aiProvider.SetShiftMode(down)
            end
        end)
        v:SetScript('OnHide', function(self)
            S.lastShiftDown = false
            if S.shiftActive then aiProvider.SetShiftMode(false) end
            if self.colSettingsPopover and self.colSettingsPopover.Hide then self.colSettingsPopover:Hide() end
            H.closeHeatPopover()
            aiProvider.CancelPresentation()
        end)
        v.CloseHeatPopover = aiProvider.CloseHeatPopover
        if type(T) == 'table' and type(T.NineApple) == 'function' then
            v._mmCard = T.NineApple(v, 'glass_r10', 'cardBg', false, { noSpecular = true })
        end

        H.buildHeader(v, T)

        local columns = {}
        for i, col in ipairs(C.ITEM_COLUMNS) do columns[i] = H.copyColumn(col) end
        S.tbl = S.host.createSortableTable(v, -41, 'all_items', columns, H.bindRow, nil, {
            preserveCellColors = true,
            preparedCells = true,
        })
        v.table = S.tbl
        S.tbl.headerBtnsByKey = {}
        for i, col in ipairs(S.tbl.columns) do
            S.tbl.headerBtnsByKey[col.key] = S.tbl.headerBtns[i]
        end
        S.tbl.growWeights = {}
        for i, col in ipairs(S.tbl.columns) do
            S.tbl.growWeights[i] = col.grow
        end
        if S.tbl.headerBar and S.tbl.headerBar.SetHeight then S.tbl.headerBar:SetHeight(28) end
        H.clearInsetChrome()
        if type(S.tbl.inset) == 'table' then
            S.tbl.inset:ClearAllPoints()
            S.tbl.inset:SetPoint('TOPLEFT', 0, -68)
            S.tbl.inset:SetPoint('BOTTOMRIGHT', 0, 0)
        end
        S.tbl.updateHeaders = H.styleHeaders
        S.tbl.proportional = true

        local emptyParent = S.tbl.inset or v
        local emptyText = emptyParent:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        emptyText:SetPoint('CENTER', emptyParent, 'CENTER', 0, 0)
        emptyText:SetWidth(520)
        emptyText:SetJustifyH('CENTER')
        emptyText:SetWordWrap(true)
        applyFont(emptyText, 12, 'regular')
        emptyText:SetText('No catalog items match the active profession, type, or search filters.')
        emptyText:Hide()
        v.emptyText = emptyText

        H.buildColumnPopover(v, T)
        H.buildSidebarControls(v, context, T)

        v._applyColumnConfig = H.applyColumnConfig
        v._refreshColumnPopover = H.refreshColumnPopover
        v._themeColumnSettingsPopover = H.themeColumnSettingsPopover
        v._applyTheme = H.applyTheme
        v._applyColumnConfig(H.getDB())

        if T and T.RegisterWidget then
            T.RegisterWidget(v, H.applyTheme)
        elseif T and T.OnModeChanged then
            T.OnModeChanged(H.applyTheme)
        end
        H.applyTheme()
        return v
    end

    if MerchantMasterAPI and MerchantMasterAPI.RegisterAllItems then
        MerchantMasterAPI.RegisterAllItems(aiProvider)
    end
end
