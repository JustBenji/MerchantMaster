-- Shared economics for the Super List and a selected trainer recipe. No AH queries.
local _, ns = ...
local Stats = {}; ns.RecipeStats = Stats
local caches = setmetatable({}, {__mode="k"})
local itemEconomics = setmetatable({}, {__mode="k"})
local catalog, byRecipe, outputsByReagent, indexedReagents, favorInputs
local defaultContext = {}
local activeBatchContext, activeBatchState

local function clockMS()
    return debugprofilestop and debugprofilestop() or (os and os.clock and os.clock()*1000 or 0)
end

local function readable(v) return not (issecretvalue and issecretvalue(v)) and not (type(v)=="table" and issecrettable and issecrettable(v)) end
local function number(v)
    if not readable(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end
local function nonnegative(v) local n=number(v); if n and n>=0 then return n end end
local function text(v) if readable(v) and type(v)=="string" then return v end end
local function tableValue(v) if readable(v) and type(v)=="table" then return v end end
local function baseKey(r)
    return table.concat({r.prof or "", r.spellID or 0, r.recipeItemID or 0, r.outputItemID or 0, r.idx or 0}, ":")
end

local function indexReagents(recipe)
    local reagents,output=recipe.reagents,recipe.outputItemID
    if not output or not reagents or indexedReagents[recipe]==reagents then return end
    indexedReagents[recipe]=reagents
    for _,rg in ipairs(reagents) do
        local id=rg.itemID or rg.id or rg[1]
        if id then
            local outputs=outputsByReagent[id] or {}
            outputs[#outputs+1]=output
            outputsByReagent[id]=outputs
        end
    end
end

function Stats.GetCatalog()
    if catalog then return catalog end
    catalog, byRecipe, outputsByReagent, indexedReagents = {}, {}, {}, {}
    favorInputs={}
    for _,crate in ipairs(ns.CRATES or {}) do
        favorInputs[crate.itemID]=true
        for _,bundle in ipairs(crate.bundles) do favorInputs[bundle.itemID]=true end
    end
    local spells, outputs, keys = {}, {}, {}
    for _, recipe in ipairs(ns.RECIPES or {}) do
        indexReagents(recipe)
        if ns.GetRecipeSourceBucket(recipe) ~= "gather" then
            local key=baseKey(recipe); keys[key]=(keys[key] or 0)+1
            local entry={recipe=recipe, key=key .. ":" .. keys[key], isWrit=false}
            catalog[#catalog+1]=entry; byRecipe[recipe]=entry
            if recipe.spellID and recipe.spellID>0 then
                spells[recipe.spellID]=spells[recipe.spellID] or {}
                table.insert(spells[recipe.spellID],entry)
            end
            if recipe.outputItemID then
                outputs[recipe.outputItemID]=outputs[recipe.outputItemID] or {}
                table.insert(outputs[recipe.outputItemID],entry)
            end
        end
    end
    for _, writ in ipairs(ns.WRITS or {}) do
        local matches=spells[writ.spellID]
        -- Output fallback is only for writs without a catalog spell match; never match the writ scroll.
        local reason="spellID"
        if not matches then matches=outputs[writ.requiredItemID]; reason="requiredItemID (no catalog spell match)" end
        for _, entry in ipairs(matches or {}) do
            if not writ.prof or writ.prof==entry.recipe.prof then entry.isWrit=true; entry.writMatch=reason end
        end
    end
    return catalog
end

function Stats.Invalidate(reason, itemIDs)
    -- These domains are accepted through immutable context snapshots, not notifications.
    if reason=="ownership" or reason=="snapshot" or reason=="trainer" or reason=="items"
        or reason=="skills" or reason=="known" or reason=="rep" or reason=="sellers" or reason=="cooldown" then return end
    caches=setmetatable({}, {__mode="k"})
    if reason=="catalog" then catalog,byRecipe,outputsByReagent,indexedReagents,favorInputs=nil,nil,nil,nil,nil end
end

local function coverageStart(first, char, econ, store)
    if not tableValue(first) or not econ or not store or type(store.DeriveEcon)~="function" then return nil end
    if char and char~="all" and store.DeriveEcon(char)~=econ then return nil end
    local start
    for ck, value in pairs(first) do
        local stamp=nonnegative(value)
        if text(ck) and stamp and store.DeriveEcon(ck)==econ then start=not start and stamp or math.min(start,stamp) end
    end
    return start
end

local signatureFields={"ownedCounts", "ownedCountsByID", "profMap", "repState", "trainerCosts", "favorCopper",
    "applyAHCut", "subCraftMode", "subCraftOverrides", "outlierPrices", "priceBank", "revision", "sourceKey", "dataset", "craftableAllChars"}
local function effectiveLedgerVersion(store)
    if not store then return nil end
    if store.ahSalesVersion~=nil and (store._trackedAccountingVersion==nil or store.accountingVersion==store._trackedAccountingVersion) then
        return store.ahSalesVersion
    end
    return store.accountingVersion or store.version
end
Stats.EffectiveLedgerVersion=effectiveLedgerVersion
local function getState(context)
    local analytics=ns.Analytics
    local store=analytics and analytics.Store
    local char=text(context.charKey) or (ns.app and text(ns.app.charKey))
    local econ=text(context.economy)
    if not econ and ns.CurrentEconomyInfo then
        local info=ns.CurrentEconomyInfo(); econ=tableValue(info) and text(info.effectiveKey)
    end
    if not econ and ns.DetectActiveEconomy then econ=text(ns.DetectActiveEconomy()) end
    local now=number(context.now) or (time and number(time())) or 0
    local first=store and store.db and store.db.stats and store.db.stats.firstLive
    local coverage=coverageStart(first,char,econ,store)
    local disabled=store and store.db and store.db.stats and store.db.stats.disabled
    local saleDisabled=disabled and (disabled.MAIL==true or disabled.AH_SELL==true or disabled.VENDOR_SELL==true) or false
    local day=math.floor(now/86400)
    local price=ns.GetEffectivePriceVersion and ns.GetEffectivePriceVersion() or ns.priceCacheEpoch
    local version=effectiveLedgerVersion(store)
    local db=store and store.db
    local covered=coverage and coverage<=now-7*86400
    local readOnly=store and store.readOnly
    local state=caches[context]
    if state then
        local sig=state.signature
        if not (rawequal(sig.char,char) and rawequal(sig.econ,econ) and rawequal(sig.day,day)
            and rawequal(sig.price,price) and rawequal(sig.analytics,analytics)
            and rawequal(sig.version,version) and rawequal(sig.db,db)
            and rawequal(sig.coverage,coverage) and rawequal(sig.covered,covered)
            and rawequal(sig.readOnly,readOnly) and rawequal(sig.saleDisabled,saleDisabled)) then
            state=nil
        else
            for i=1,#signatureFields do
                local k=signatureFields[i]
                local v=context[k]
                if not readable(v) then v=nil end
                if not rawequal(sig[k],v) then state=nil; break end
            end
        end
    end
    if not state then
        local signature={char=char,econ=econ,day=day,price=price,
            analytics=analytics,version=version,db=db,
            coverage=coverage,covered=covered,
            readOnly=readOnly,saleDisabled=saleDisabled}
        for i=1,#signatureFields do
            local k=signatureFields[i]
            local v=context[k]; if readable(v) then signature[k]=v end
        end
        state={signature=signature,rows={},favorRows={},char=char,econ=econ}; caches[context]=state
    end
    state.now=now
    return state
end

function Stats.BeginBatch(context)
    context=tableValue(context) or defaultContext
    Stats.GetCatalog()
    local state=getState(context)
    state.bank=ns.BeginEval(state.bank)
    activeBatchContext,activeBatchState=context,state
    return state
end

function Stats.EndBatch()
    activeBatchContext,activeBatchState=nil,nil
    ns.EndEval()
end

local function personalSales(state)
    if state.personalLoaded then return end
    state.personalLoaded=true
    local analytics=ns.Analytics
    local store=analytics and analytics.Store
    local db=store and store.db
    local first=db and db.stats and db.stats.firstLive
    local start=coverageStart(first,state.char,state.econ,store)
    state.coverageStart=start
    if state.signature.readOnly or state.signature.saleDisabled
        or not start or start>state.now-7*86400 then return end
    if not analytics.Model or type(analytics.Model.Compute)~="function" then return end
    local ok,result=pcall(analytics.Model.Compute,"items",{char="all",econ=state.econ,period="7d",source="AH",knownCostOnly=false})
    if not ok or not tableValue(result) or not tableValue(result.rows) then return end
    state.personal={}
    for _, row in ipairs(result.rows) do
        if tableValue(row) then
            local id=nonnegative(row.itemID)
            if id then state.personal[id]=row end
        end
    end
end

function Stats.WarmStep(context, budgetMS)
    context=tableValue(context) or defaultContext
    Stats.GetCatalog()
    local state=getState(context)
    if not state.personalLoaded then personalSales(state); return true end
    if not state.favorLoaded and not nonnegative(context.favorCopper)
        and readable(context.favorCopper) and context.favorCopper==nil and ns.BuildCrateRows then
        state.crateScanIdx=state.crateScanIdx or 1
        local sliceMS=math.min(1.0,math.max(0.5,tonumber(budgetMS) or 1.0))
        local deadline=clockMS()+sliceMS
        local opts={profMap=context.profMap,repState=context.repState,
            ownedCounts=context.ownedCounts,subCraftMode=context.subCraftMode,
            subCraftOverrides=context.subCraftOverrides,bestOnly=true,minimalBest=true,
            startIndex=state.crateScanIdx,endIndex=state.crateScanIdx+10,
            bestPricePerToken=state.bestFavorToken,
            yieldBudget=function() return clockMS()>=deadline end}
        state.bank=ns.BeginEval(state.bank)
        local ok,_,best=pcall(ns.BuildCrateRows,opts)
        ns.EndEval()
        if not ok then
            if ns.ResetEval then ns.ResetEval() end
            state.bank=nil
            state.favorLoaded=true
            state.favorCopper=nil
            return true
        end
        state.bestFavorToken=tableValue(best) and nonnegative(best.pricePerToken) or state.bestFavorToken
        if type(opts.outNextIndex)=="number" and opts.outNextIndex<=#(ns.CRATES or {}) then
            state.crateScanIdx=opts.outNextIndex
            return true
        end
        state.favorLoaded=true
        state.favorCopper=tableValue(best) and nonnegative(best.pricePerToken) or nil
        return true
    end
    return false
end

local function dependencyPrices(id, recipe)
    local vendor
    local isScroll = recipe and id == recipe.recipeItemID
    if ns.GetVendorBuyPrice then vendor=nonnegative(ns.GetVendorBuyPrice(id, isScroll and recipe.recipeVendorPrice or nil, isScroll))
    elseif recipe and ns.GetRecipeVendorBuyPrice then vendor=nonnegative(ns.GetRecipeVendorBuyPrice(id,recipe.recipeVendorPrice))
    else
        vendor=ns.VENDOR_REAGENTS and nonnegative(ns.VENDOR_REAGENTS[id])
    end
    return {vendor=vendor,market=ns.GetItemMarketPrice and nonnegative(ns.GetItemMarketPrice(id))}
end
local function repairDependency(row, id, recipe, current)
    local prices=itemEconomics[row]
    if not prices and row.craftCost==nil then return true end
    current=current or dependencyPrices(id,recipe)
    local previous=prices and prices[id]
    if previous and (previous.vendor~=current.vendor or previous.market~=current.market) then return true end
    if not prices then prices={}; itemEconomics[row]=prices end
    if not previous then prices[id]=current end
    return false
end
local function rememberItemEconomics(row, recipe, state)
    state.itemPrices=state.itemPrices or {}
    local prices=state.itemPrices; itemEconomics[row]=prices
    if recipe.recipeItemID and not prices[recipe.recipeItemID] then prices[recipe.recipeItemID]=dependencyPrices(recipe.recipeItemID,recipe) end
    for _,rg in ipairs(recipe.reagents or {}) do
        local id=rg.itemID or rg.id or rg[1]
        if id and not prices[id] then prices[id]=dependencyPrices(id) end
    end
end

local function owned(context, id, name)
    local ids=tableValue(context.ownedCountsByID)
    local counts=tableValue(context.ownedCounts)
    local qty=id and ((ids and nonnegative(ids[id])) or (counts and nonnegative(counts[id])))
    if not qty and id and ns.ItemName then qty=counts and nonnegative(counts[ns.ItemName(id)]) end
    return qty or (counts and name and nonnegative(counts[name])) or 0
end

local function usesCrateFavor(row,context)
    return readable(context.favorCopper) and context.favorCopper==nil and row.craftAbility
        and nonnegative(row.craftAbility.vendorFavorCost)~=nil
end

local function acquisition(row, recipe, context, state)
    local ability=row.craftAbility
    local cost={currencies={},known=false}
    local copper=nonnegative(ability.vendorCopperCost)
    if row.sourceBucket=="trainer" then
        local professor=(ns.GetProfessorDB and ns.GetProfessorDB()) or _G.MerchantProfessorDB
        local fees=tableValue(context.trainerCosts) or (professor and tableValue(professor.trainerCosts))
        copper=fees and (nonnegative(fees[recipe.spellID]) or nonnegative(fees[recipe.name]))
    elseif ability.howCategory=="ah" then copper=nonnegative(ability.recipeAHPrice) end
    local favor=nonnegative(ability.vendorFavorCost)
    -- Camp Favor is the actual fee; generic item buy metadata is not a shop charge.
    if favor and favor>0 and (row.sourceBucket=="merchant" or recipe.source=="camp" or recipe.acqType=="camp") then copper=nil end
    if copper then cost.copper=copper; cost.known=true end
    if favor then
        cost.currencies[ns.FAVOR_CURRENCY_ID or 3402]=favor; cost.known=true
        local equivalent=nonnegative(context.favorCopper)
        if not equivalent and readable(context.favorCopper) and context.favorCopper==nil and ns.BuildCrateRows then
            if not state.favorLoaded then
                state.favorLoaded=true
                local _, best=ns.BuildCrateRows({profMap=context.profMap,repState=context.repState,
                    ownedCounts=context.ownedCounts,subCraftMode=context.subCraftMode,subCraftOverrides=context.subCraftOverrides,bestOnly=true})
                state.favorCopper=tableValue(best) and nonnegative(best.pricePerToken)
            end
            equivalent=state.favorCopper
        end
        if equivalent then
            local converted=nonnegative((cost.copper or 0)+math.floor(favor*equivalent+0.5))
            if converted then row.buyCostCopper=converted; row.buyCostEstimated=true end
        end
    else row.buyCostCopper=copper end
    row.sourceCost=cost
    row.buyCostEstimated=row.buyCostEstimated or false
end

local function cleanSourceLabel(recipe, ability, bucket)
    local acq=(recipe and (recipe.acqType or (recipe.source=="camp" and "camp" or recipe.source))) or (ability and ability.acqType)
    if bucket=="merchant" or (recipe and (recipe.source=="camp" or recipe.acqType=="camp")) or acq=="camp" then
        return "Merchant"
    end
    if bucket=="vendor" or acq=="vendor" or acq=="vendor_ah" then
        return (ability and ability.howCategory=="ah") and "AH" or "Vendor"
    end
    if bucket=="ah" or acq=="ah" or (ability and ability.howCategory=="ah") then
        return "AH"
    end
    if acq=="quest" then return "Quest" end
    if acq=="drop_bop" then return "Drop" end
    if acq=="start" then return "Starter" end
    return "Trainer"
end

local function applyRepFields(row, recipe, context)
    if ns.BuildRecipeRepFields then
        row.reqRep,row.repSort,row.repLabel,row.repFactionName,row.repMet=ns.BuildRecipeRepFields(recipe,context and context.repState,row.unlock)
    else
        row.reqRep,row.repSort,row.repLabel,row.repFactionName,row.repMet=0,nil,nil,nil,true
    end
end

local function applyCooldownFields(row, recipe, now)
    local cdInfo=ns.GetRecipeCooldownInfo and ns.GetRecipeCooldownInfo(recipe,now) or nil
    row.cdInfo=cdInfo
    if type(cdInfo)~="table" or not cdInfo.hasCooldown then
        row.cdSort=nil
    elseif cdInfo.available==true then
        row.cdSort=0
    elseif cdInfo.onCooldown==true then
        row.cdSort=math.max(1,tonumber(cdInfo.remainingSeconds) or tonumber(cdInfo.nominalSeconds) or 1)
    else
        row.cdSort=math.max(1,tonumber(cdInfo.nominalSeconds) or 1)+0.5
    end
end

local function evaluate(recipe, context, state)
    local row=ns.BuildRecipeRow(recipe,context)
    indexReagents(recipe)
    local entry=byRecipe[recipe]
    row.key=entry and entry.key or (baseKey(recipe) .. ":1")
    row.spellID=recipe.spellID; row.outputItemID=recipe.outputItemID; row.requiredSkill=recipe.skill
    local MP=ns.MP or _G.MerchantProfessorNS or _G.MerchantProfessor or ns.Professor
    local bySpell=MP and (MP.RECIPE_BY_SPELL or MP.RECIPES_BY_SPELL)
    local profRec=bySpell and recipe.spellID and bySpell[recipe.spellID]
    if profRec and MP.GetEffectiveThresholds then
        local _,sy,sg,sgr=MP.GetEffectiveThresholds(profRec)
        row.skillYellow,row.skillGreen,row.skillGray=sy,sg,sgr
        row.skillupSort=sgr
    end
    row.ownedOutputQty=owned(context,recipe.outputItemID,row.name)
    local scrollName=recipe.recipeItemID and ns.ItemName(recipe.recipeItemID,recipe.recipeName)
    row.ownedScrollQty=owned(context,recipe.recipeItemID,scrollName)
    row.known=row.craftAbility.known==true; row.knownSort=row.known and 1 or 0
    row.sourceBucket=ns.GetRecipeSourceBucket(recipe)
    row.isWrit=entry and entry.isWrit or false; row.writMatch=entry and entry.writMatch
    row.sourceLabel=cleanSourceLabel(recipe,row.craftAbility,row.sourceBucket)
    applyRepFields(row,recipe,context)
    -- Only an explicit clock override belongs in the live cooldown query.
    local evalTok=ns.PushEvalOpts and ns.PushEvalOpts(context)
    applyCooldownFields(row,recipe,number(context.now))
    if ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
    row.wowheadURL=ns.GetRecipeWowheadURL(recipe)
    row.craftCost=nonnegative(row.craftCost); row.unitAH=nonnegative(row.unitAH); row.profit=number(row.profit)
    acquisition(row,recipe,context,state)
    personalSales(state)
    row.coverageStart=state.coverageStart
    if row.sellable and row.outputItemID then
        row.marketDemand=ns.GetMultiSourceDemand and ns.GetMultiSourceDemand(row.outputItemID,state.econ) or nil
        local fallbackDaily = nonnegative(row.dailySold)
        local personal=state.personal and state.personal[row.outputItemID]
        local pSold=personal and (nonnegative(personal.ahSold) or nonnegative(personal.sold)) or 0
        local pExp=personal and nonnegative(personal.expired) or 0
        if state.personal then
            row.personalSalesPerDay=personal and (nonnegative(personal.ahVelocity) or nonnegative(personal.velocity)) or nil
            row.personalSold7d=pSold; row.personalExpired7d=pExp
            row.personalSellThrough=personal and (nonnegative(personal.ahSellThrough) or nonnegative(personal.saleRate)) or nil
            row.personalCancelChurn=personal and nonnegative(personal.cancelChurn) or nil
        end
        local md = row.marketDemand
        local snapDaily = md and nonnegative(md.snapDailySold) or nil
        row.marketSalesPerDay = md and nonnegative(md.effectiveDailySold) or nil
        row.snapDailySold = snapDaily
        row.demandSource = md and text(md.demandSource) or nil
        if personal and pSold > 0 then
            row.salesPerDay = nonnegative(personal.ahVelocity) or nonnegative(personal.velocity) or 0
            row.isSlowing = (readable(personal.ahIsSlowing) and personal.ahIsSlowing == true)
                or (readable(personal.isSlowing) and personal.isSlowing == true) or false
            row.salesScope = "Personal"; row.salesWindowDays = 7
        elseif snapDaily and snapDaily > 0 then
            row.salesPerDay = snapDaily
            row.salesScope = "Blizzard"; row.salesWindowDays = 7
        elseif md and nonnegative(md.localClearsPerDay) then
            row.salesPerDay = nonnegative(md.localClearsPerDay)
            row.salesScope = "Local Scan"; row.salesWindowDays = 3
        elseif fallbackDaily ~= nil then
            row.salesPerDay = fallbackDaily
            row.salesScope = "Blizzard"; row.salesWindowDays = 7
        elseif personal and pExp > 0 then
            row.salesPerDay = 0
            row.isSlowing = (readable(personal.ahIsSlowing) and personal.ahIsSlowing == true)
                or (readable(personal.isSlowing) and personal.isSlowing == true) or false
            row.salesScope = "Personal"; row.salesWindowDays = 7
        else
            row.salesPerDay = nil
        end
        if row.salesPerDay and row.unitAH then row.turnoverPerDay=row.salesPerDay*row.unitAH else row.turnoverPerDay=nil end
    else
        row.unitAH=nil; row.profit=nil; row.ahValue=nil
    end
    if type(ns.EvaluateProductQuality)=="function" then
        local effDaily=number(row.salesPerDay)
        if effDaily==nil then effDaily=number(row.dailySold) end
        local saleRate=number(row.personalSellThrough) or nil
        local _,goodScore,goodShort,goodFull=ns.EvaluateProductQuality(row.outputItemID,recipe,row.bisInfo,effDaily,saleRate)
        if not row.sellable and (not goodScore or goodScore<=0) then
            row.goodScore=nil; row.goodShort=nil; row.goodFull=nil; row.goodPlain=nil
        else
            row.goodScore=goodScore; row.goodShort=goodShort; row.goodFull=goodFull
            local plainParts
            if type(goodShort)=="string" and type(goodFull)=="string" and goodFull~=goodShort and not goodFull:find(goodShort,1,true) then
                plainParts=goodShort.." "..goodFull
            else
                plainParts=(type(goodFull)=="string" and goodFull~="") and goodFull or goodShort
            end
            row.goodPlain=type(plainParts)=="string" and (plainParts:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")) or nil
        end
    end
    row.sellerStatus="unavailable"
    rememberItemEconomics(row,recipe,state)
    return row
end

function Stats.Get(recipe, context)
    context=tableValue(context) or defaultContext
    Stats.GetCatalog()
    local batched=activeBatchState and rawequal(context,activeBatchContext)
    local state=batched and activeBatchState or getState(context)
    local cached=state.rows[recipe] or state.favorRows[recipe]
    if cached then
        local row=cached
        if row.sourceBucket~="trainer" then return row end
        local professor=(ns.GetProfessorDB and ns.GetProfessorDB()) or _G.MerchantProfessorDB
        local fees=tableValue(context.trainerCosts) or (professor and tableValue(professor.trainerCosts))
        local fee=fees and (nonnegative(fees[recipe.spellID]) or nonnegative(fees[recipe.name]))
        if fee==row.buyCostCopper then return row end
    end
    -- Own the bank with the accepted dependencies; callers may retain an older bank.
    if not batched then state.bank=ns.BeginEval(state.bank) end
    local ok,row=pcall(evaluate,recipe,context,state)
    if not batched then ns.EndEval() end
    if not ok then
        -- A nested pricing helper may have failed before closing its own evaluation.
        if ns.ResetEval then ns.ResetEval() end
        activeBatchContext,activeBatchState=nil,nil
        state.bank=nil; state.favorLoaded=nil; state.personalLoaded=nil
        error(row,0)
    end
    local rows=usesCrateFavor(row,context) and state.favorRows or state.rows
    rows[recipe]=row
    return row
end

local function spanSeries(values, slotCount, allowPartialEndpoints)
    slotCount = slotCount or 7
    local first, last, count = nil, nil, 0
    for slot = 1, slotCount do
        local value = values[slot]
        if value ~= nil then
            first, last, count = first or value, value, count + 1
        end
    end
    local change = count >= 2 and (allowPartialEndpoints or (values[1] ~= nil and values[slotCount] ~= nil))
        and (last - first) or nil
    local pct = change and first and math.abs(first) > 0 and (change / math.abs(first) * 100) or nil
    return { values = values, days = count, count = count, slotCount = slotCount,
        first = first, last = last, change = change, pct = pct }
end

local function historyPriceAt(db, economy, itemID, stamp)
    local history = db and tableValue(db.ahHistory)
    local econHistory = history and tableValue(history[economy])
    local rawRing = econHistory and econHistory[itemID]
    local ring = (ns.MarketScan and ns.MarketScan.ReadHistory and ns.MarketScan.ReadHistory(rawRing))
        or tableValue(rawRing)
    for i = ring and #ring or 0, 1, -1 do
        local entry = tableValue(ring[i])
        if entry and nonnegative(entry.t) == stamp then
            local price = nonnegative(entry.p)
            if price ~= nil then return price end
        end
    end
end

local function itemSpan(itemID, economy, now, startSlot, slotCount, fixedPrice, allowPartialEndpoints)
    local prices, sales, qtys = {}, {}, {}
    if fixedPrice then
        for slot = 1, slotCount do prices[slot] = fixedPrice end
        return spanSeries(prices, slotCount, false), sales, nil, nil, 0, spanSeries(qtys, slotCount, false), nil
    end

    local scan, firstQty, liveQty
    local hourly = slotCount == 24
    local slotSeconds = hourly and 3600 or 86400
    local market = ns.MarketScan
    local getTrend = market and market[hourly and "GetItemTrend24h" or "GetItemTrend7d"]
    local trend = itemID and getTrend and getTrend(itemID, economy, now)
    for _, point in ipairs(trend and trend.points or {}) do
        local slot = (hourly and point.h or point.d) - startSlot + 1
        if slot >= 1 and slot <= slotCount then
            if point.price and point.price > 0 then prices[slot] = point.price end
            qtys[slot], sales[slot] = point.qty, point.salesPerDay
            firstQty = firstQty or point.qty
            if point.at and point.at <= now
                and (not scan or point.at >= scan.at) then scan = point end
        end
    end

    local db = tableValue(MerchantMasterDB)
    local pricesByEconomy = db and tableValue(db.ahPrices)
    local livePrices = pricesByEconomy and tableValue(pricesByEconomy[economy])
    local ah = livePrices and tableValue(livePrices[itemID])
    local itemWide = ah and ah.itemWide
    if ah and itemWide == nil then
        itemWide = not (market and market.HasKnownVariants and market.HasKnownVariants(itemID, economy))
    end
    local stamp = itemWide == true and nonnegative(ah.at)
    -- Complete searches stamp both records, but only history includes bids and owned lots.
    if stamp and stamp >= startSlot * slotSeconds and stamp <= now and (not scan or stamp > scan.at) then
        local ahPrice = nonnegative(ah.price)
        liveQty = nonnegative(ah.qty)
        scan = { price = ahPrice, qty = liveQty, at = stamp }
        local slot = math.floor(stamp / slotSeconds) - startSlot + 1
        if ahPrice and ahPrice > 0 then prices[slot] = ahPrice end
        qtys[slot] = liveQty
        firstQty = firstQty or liveQty
    elseif scan then
        local price = scan.observedPrice
        if price == nil then
            price = historyPriceAt(db, economy, itemID, scan.at)
            if price == nil and stamp == scan.at then price = nonnegative(ah.price) end
        end
        scan = { price = price, qty = scan.qty, at = scan.at }
    end

    local observedDays = 0
    for slot = 1, slotCount do
        if prices[slot] ~= nil or (qtys[slot] and qtys[slot] > 0) then
            observedDays = observedDays + 1
        end
    end
    return spanSeries(prices, slotCount, allowPartialEndpoints), sales, scan, firstQty, observedDays,
        spanSeries(qtys, slotCount, allowPartialEndpoints), liveQty
end

local function quickLookState(context, nowOverride)
    context = context or defaultContext
    local now = number(nowOverride) or number(context.now) or (time and time()) or 0
    local economy = context.economy
    if not economy and ns.CurrentEconomyInfo then economy = ns.CurrentEconomyInfo().effectiveKey end
    local window = context.window == "24h" and "24h" or "7d"
    local slotCount = window == "24h" and 24 or 7
    local startDay = math.floor(now / 86400) - 6
    local startSlot = window == "24h" and (math.floor(now / 3600) - 23) or startDay
    return { context = context, now = now, window = window, slotCount = slotCount, startSlot = startSlot, startDay = startDay,
        economy = economy, quotes = {}, profMap = context.profMap or (ns.GetPlayerProfessions and ns.GetPlayerProfessions()),
        subCraftMode = context.subCraftMode or "smart" }
end

local function quickLookQty(value)
    local qty = number(tonumber(value))
    if not qty or qty <= 0 then return 1 end
    return qty
end

local function scaleSpan(series, qty)
    local values = {}
    for slot = 1, series.slotCount do
        local value = series.values[slot]
        if value ~= nil then values[slot] = value * qty end
    end
    return spanSeries(values, series.slotCount, true)
end

local function chooseSpan(buy, craft, mode, override)
    local values = {}
    for slot = 1, buy.slotCount do
        local ah, made = buy.values[slot], craft.values[slot]
        if mode == "buy" then values[slot] = ah
        elseif mode == "craft" then values[slot] = made
        elseif override == "craft" and made ~= nil then values[slot] = made
        elseif override == "buy" and ah ~= nil then values[slot] = ah
        elseif ah ~= nil and made ~= nil then values[slot] = math.min(ah, made)
        else values[slot] = ah or made end
    end
    return spanSeries(values, buy.slotCount, true)
end

local function quickLookRecipe(itemID, state, parentProf)
    if ns.SelectBestRecipeForItem then
        return ns.SelectBestRecipeForItem(itemID, parentProf, state.profMap)
    end
    local recipes = ns.RECIPES_BY_OUTPUT and ns.RECIPES_BY_OUTPUT[itemID]
    return recipes and recipes[1]
end

local function acquisitionQuote(itemID, state)
    local quote = state.quotes[itemID]
    if quote then return quote end
    local vendor = ns.GetRecipeVendorBuyPrice(itemID, ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[itemID])
    local slotCount = state.slotCount
    local market, sales, scan, firstQty, observedDays, listed, liveQty =
        itemSpan(itemID, state.economy, state.now, state.startSlot, slotCount, nil, true)
    local prices, vendorSelected, observedPrices = {}, {}, {}
    for slot = 1, slotCount do
        local observed = market.values[slot]
        vendorSelected[slot] = vendor ~= nil and (observed == nil or observed >= vendor)
        prices[slot] = vendorSelected[slot] and vendor or observed
        if vendor and observed then observedPrices[slot] = prices[slot] end
    end
    local ah = spanSeries(prices, slotCount, true)
    local currentAH = ns.GetItemMarketPrice and number(ns.GetItemMarketPrice(itemID)) or market.values[slotCount]
    local fixed = vendor ~= nil and (currentAH == nil or currentAH >= vendor)
    quote = { ah = ah, vendorSelected = vendorSelected, fixed = fixed, pureVendor = fixed and observedDays == 0,
        unitPrice = fixed and vendor or currentAH, scan = scan, firstQty = firstQty, sales = sales, listed = listed, liveQty = liveQty,
        observedSeries = vendor and observedDays > 0 and spanSeries(observedPrices, slotCount, true) or nil }
    state.quotes[itemID] = quote
    return quote
end

-- The same material can be eligible under one parent profession and ineligible under another.
local function acquisitionSpan(itemID, state, recipe, visited, depth, parentProf)
    local quote = acquisitionQuote(itemID, state)
    local ah = quote.ah
    local item = { itemID = itemID, ah = ah, vendorSelected = quote.vendorSelected,
        fixed = quote.fixed, pureVendor = quote.pureVendor, unitPrice = quote.unitPrice,
        scan = quote.scan, firstQty = quote.firstQty, observedSeries = quote.observedSeries,
        sales = quote.sales, listed = quote.listed, liveQty = quote.liveQty,
        craft = spanSeries({}, state.slotCount), selected = ah, children = {}, useCraft = {} }
    visited, depth = visited or {}, depth or 0
    if visited[itemID] or depth >= 4 then return item end
    recipe = recipe or quickLookRecipe(itemID, state, parentProf)
    item.recipe = recipe
    local reagents = recipe and (ns.ResolveRecipeReagents(recipe) or recipe.reagents)
    if not reagents or #reagents == 0 then return item end

    visited[itemID] = true
    for _, reagent in ipairs(reagents) do
        local id, qty = reagent.itemID or reagent.id or reagent[1], reagent.qty or reagent[2]
        if id and qty and qty > 0 then
            local child = acquisitionSpan(id, state, nil, visited, depth + 1, recipe.prof)
            item.children[#item.children + 1] = { item = child, qty = qty }
        end
    end
    visited[itemID] = nil

    local values, selected = {}, {}
    local made = math.max(1, tonumber(recipe.numMade) or 1)
    local sameProf, playerCanCraft = ns.GetRecipeCraftEligibility(recipe, state.profMap, parentProf)
    local craftOpt = { recipe = recipe, sameProf = sameProf, playerCanCraft = playerCanCraft }
    local overrides = state.context.subCraftOverrides
    local override = overrides and overrides[itemID]
    for slot = 1, state.slotCount do
        local total = #item.children > 0 and 0 or nil
        for _, child in ipairs(item.children) do
            local price = child.item.selected.values[slot]
            if price == nil then total = nil; break end
            total = total + price * child.qty
        end
        local craftPrice = total and math.floor(total / made + 0.5)
        local buyPrice = ah.values[slot]
        local useCraft = not item.vendorSelected[slot]
            and ns.ShouldSubCraft(craftOpt, state.subCraftMode, override, buyPrice, craftPrice)
        values[slot] = craftPrice
        item.useCraft[slot] = useCraft
        selected[slot] = useCraft and craftPrice or buyPrice
    end
    item.craft = spanSeries(values, state.slotCount, true)
    item.selected = spanSeries(selected, state.slotCount, true)
    return item
end

local function acquisitionModeLabel(mode, buyCost, craftCost)
    if buyCost == nil and craftCost == nil then return "Price unavailable" end
    if mode == "Buy" then return "Buy AH" end
    if mode == "Craft" then return "Craft" end
    return "Price unavailable"
end

local function addQuickLookMover(movers, item, qty, name, tag, state, series, indent, livePrice)
    series = series or item.selected
    local observedSeries = tag == "Reagent" and item.observedSeries or nil
    local trend = observedSeries or series
    local id = item.itemID
    name = name or (ns.ItemName and ns.ItemName(id)) or tostring(id)
    local price = number(livePrice) or (series == item.ah and item.unitPrice) or series.values[state.slotCount]
    if price == nil and ns.GetItemMarketPrice then price = number(ns.GetItemMarketPrice(id)) end
    local listed = ns.GetNumListed and nonnegative(ns.GetNumListed(id)) or (item.scan and item.scan.qty)
    local mover = { itemID = id, name = name, qty = qty, tag = tag, indent = indent or 0,
        series = series, observedSeries = observedSeries, fixed = item.fixed, pureVendor = item.pureVendor,
        unitPrice = price, extPrice = price and price * qty, deltaPct = trend.pct, impact = trend.change and trend.change * qty,
        days = trend.days, listed = listed, owned = owned(state.context, id, name),
        craftable = item.recipe ~= nil }
    movers[#movers + 1] = mover
    return mover
end

local function addCraftMovers(movers, item, qty, state, depth, visited)
    depth, visited = depth or 1, visited or {}
    if depth > 4 or visited[item.itemID] then return end
    visited[item.itemID] = true
    for _, child in ipairs(item.children) do
        local amount = child.qty * qty
        addQuickLookMover(movers, child.item, amount, nil, "Reagent", state, nil, depth)
        if child.item.useCraft[state.slotCount] then
            addCraftMovers(movers, child.item, amount / math.max(1, tonumber(child.item.recipe.numMade) or 1), state, depth + 1, visited)
        end
    end
    visited[item.itemID] = nil
end

local function moneyText(value)
    if value == nil then return "-" end
    if ns.Theme and ns.Theme.FormatMoneyText then return ns.Theme.FormatMoneyText(value) end
    return ns.FormatMoneyCompact and ns.FormatMoneyCompact(value) or tostring(value)
end

local function personalSalesSpan(itemID, state)
    local analytics = ns.Analytics
    local store = analytics and analytics.Store
    local char = state.context.charKey or (ns.app and ns.app.charKey)
    local economy, now = state.economy, state.now
    local sales = {}
    if not (itemID and char and economy and store and store.IterDays) then return sales end
    local hourly = state.window == "24h"
    local slotSeconds, rateScale = hourly and 3600 or 86400, hourly and 24 or 1
    local firstStamp = state.startSlot * slotSeconds
    store.IterDays(store.DayKey(firstStamp), store.DayKey(now + 86400), function(_, entries)
        for _, entry in ipairs(entries) do
            if entry.type == "AH_SELL" and entry.itemID == itemID and entry.econ == economy and entry.char == char then
                local stamp = nonnegative(entry.extra and entry.extra.saleAt) or nonnegative(entry.time)
                local qty = nonnegative(entry.qty)
                if stamp and qty and stamp >= firstStamp and stamp <= now then
                    local slot = math.floor(stamp / slotSeconds) - state.startSlot + 1
                    sales[slot] = (sales[slot] or 0) + qty * rateScale
                end
            end
        end
    end)
    return sales
end

local function setQuickLookMarket(data, row, state, itemID, slotSales, listed, liveQty)
    local slotCount = state.slotCount
    local sales, salesSource = spanSeries(slotSales, slotCount, true), "Local scan estimate"
    if sales.count == 0 then
        sales = spanSeries(personalSalesSpan(itemID, state), slotCount, true)
        salesSource = sales.count > 0 and "Personal sales" or nil
    end

    local liveListed
    if data.kind == "forged" then
        liveListed = nonnegative(row.emptyAhQty) or nonnegative(row.ahListed) or nonnegative(row.listed)
            or (ns.GetNumListed and nonnegative(ns.GetNumListed(itemID)))
    else
        liveListed = number(row.listed)
    end
    liveListed = liveListed or liveQty or (data.scan and data.scan.qty) or listed.last
    local liveSalesPerDay = nonnegative(row.salesPerDay) or nonnegative(row.dailySold)
        or nonnegative(row.writDailySold) or nonnegative(row.reqDailySold) or sales.last
    local demandValues = {}
    for slot = 1, slotCount do
        local qty, rate = listed.values[slot], sales.values[slot] or liveSalesPerDay
        if qty ~= nil and rate ~= nil then demandValues[slot] = rate / math.max(1, qty) end
    end

    data.window, data.slotCount, data.startSlot, data.startDay = state.window, slotCount, state.startSlot, state.startDay
    data.sales, data.salesSource, data.liveSalesPerDay = sales, salesSource, liveSalesPerDay
    data.listed, data.liveListed = listed, liveListed
    data.demand = spanSeries(demandValues, slotCount, true)
    data.demandInfo = row.demand
        or (ns.EvaluateMarketDemand and ns.EvaluateMarketDemand(liveListed, liveSalesPerDay, row.sellable ~= false))
end

local function addMarketOverviewRows(data)
    local rows, demandInfo = data.overviewRows, data.demandInfo
    rows[#rows + 1] = { key = "ahListed", label = "AH listed", qtyText = "AH", liveValue = data.liveListed,
        valueKind = "int", series = data.listed, lowerIsBetter = true }
    rows[#rows + 1] = { key = "demand", label = "Demand", qtyText = "Hot/Cold",
        liveValue = (demandInfo and demandInfo.salesRatio) or data.demand.last,
        badgeText = demandInfo and (demandInfo.heatShort or demandInfo.heatBadge),
        stateLabel = demandInfo and demandInfo.stateLabel, valueKind = "demand", series = data.demand, lowerIsBetter = false }
end

local function quickLookSource(obj, row, ability, whereToBuy, recipeName)
    local url, label, kind
    if ns.GetRecipeWowheadURL then url, label, kind = ns.GetRecipeWowheadURL(obj) end
    local ca = {}
    for key, value in pairs(ability or {}) do ca[key] = value end
    ca.wowheadURL = url or row.wowheadURL or ca.wowheadURL
    ca.wowheadLabel = label or row.wowheadLabel or ca.wowheadLabel
    ca.wowheadKind = kind or row.wowheadKind or ca.wowheadKind
    ca.howDetail, ca.recipeName = whereToBuy, ca.recipeName or recipeName
    return { whereToBuy = whereToBuy, wowheadURL = ca.wowheadURL, wowheadCA = ca }
end

local function acquisitionCost(price, cost, refund)
    if price == nil or cost == nil then return end
    local gross = price + cost
    return gross - refund, gross
end

local function acquisitionQuickLook(kind, row, state, primary, materials, refund, materialCashback)
    local netValues, grossValues, days = {}, {}, {}
    local slotCount = state.slotCount
    local hourly = state.window == "24h"
    for slot = 1, slotCount do
        local price = primary.ah.values[slot]
        local cost = not materials and 0 or materials.values[slot]
        local net, gross = acquisitionCost(price, cost, refund)
        netValues[slot], grossValues[slot] = net, gross and gross + (materialCashback or 0)
        local bucket = state.startSlot + slot - 1
        local point = { d = hourly and math.floor(bucket / 24) or bucket, h = hourly and bucket or nil, netCost = net }
        days[slot] = point
        if kind == "writ" then
            point.writPrice, point.turnInCost, point.pouchRefund = price, cost, refund
        elseif kind == "forged" then
            point.cratePrice, point.favorCost, point.forgedRefund = price, cost, refund
        else
            point.cratePrice, point.bundleCost, point.reward = price, cost, refund
        end
    end
    local net = spanSeries(netValues, slotCount, true)
    local data = { kind = kind, now = state.now, days = days, chartSeries = { netCost = net },
        output = net, cost = materials, net = net, gross = spanSeries(grossValues, slotCount, true),
        scroll = primary.ah, scrollID = primary.itemID,
        scrollCost = number(row.writPrice or row.cratePrice) or primary.ah.values[slotCount],
        scrollFixed = primary.fixed, scan = primary.scan, firstQty = primary.firstQty, made = 1, movers = {} }
    local costKey = kind == "writ" and "turnInCost" or (kind == "forged" and "favorCost" or "bundleCost")
    data.chartSeries[costKey] = materials
    setQuickLookMarket(data, row, state, primary.itemID, primary.sales, primary.listed, primary.liveQty)
    return data
end

function Stats.BuildWritQuickLook(row, context, nowOverride)
    if type(row) ~= "table" then return nil end
    local state = quickLookState(context, nowOverride)
    local writ = row.writ or {}
    local writID, reqID = nonnegative(tonumber(row.writID or writ.itemID)), nonnegative(tonumber(row.reqItemID or writ.requiredItemID))
    if not writID or writID <= 0 or not reqID or reqID <= 0 then return nil end
    local qty = quickLookQty(row.reqQty or writ.qty)
    local scroll = acquisitionSpan(writID, state)
    local parentProf = writ.prof or row.prof
    local recipe = writ.reagents and writ or quickLookRecipe(reqID, state, parentProf)
    local turnIn = acquisitionSpan(reqID, state, recipe, nil, nil, parentProf)
    local buy = scaleSpan(turnIn.ah, qty)
    local made = math.max(1, tonumber(recipe and recipe.numMade) or 1)
    local batches = math.ceil(qty / made)
    local craft = scaleSpan(turnIn.craft, made * batches)
    local writMode = state.context.writMode or "cheapest"
    local writOverrides = state.context.subCraftOverrides
    local cost = chooseSpan(buy, craft, writMode, writOverrides and writOverrides[reqID])
    local refund = number(row.pouchRefund) or 0
    local data = acquisitionQuickLook("writ", row, state, scroll, cost, refund)
    local rep, tier = row.rep or writ.rep or 0, writ.tier or row.pouchTier or "Writ"
    local cd = row.cdInfo
    if not cd and ns.GetWritCooldownInfo then cd = ns.GetWritCooldownInfo(writ, { now = state.now }) end
    local cdText = (cd and cd.available or row.cdAvailable or row.cdText == "R") and "Ready (Daily)"
        or (cd and cd.shortText) or row.cdText or "-"
    local zone, npc = row.zone or writ.zone, row.npc or writ.npc
    if ns.GetWritZoneInfo and (not zone or not npc) then
        local infoZone, _, infoNpc = ns.GetWritZoneInfo(writ)
        zone, npc = zone or infoZone, npc or infoNpc
    end
    local mode = acquisitionModeLabel(row.mode, row.buyCost, row.craftCost)
    data.title = row.writFullName or row.writName or writ.name or "Writ"
    data.badge = "+" .. tostring(rep) .. " Rep · " .. tostring(tier)
    data.subtitle = "Turn-in " .. (zone or "Unknown turn-in") .. " | " .. (npc or "Unknown turn-in") .. " | " .. cdText .. " | Mode " .. mode
    local source = (zone or "Unknown turn-in") .. " — " .. (npc or "Unknown turn-in") .. " (" .. cdText .. ")"
    -- A full Writ record also describes the recipe for its turn-in item.
    data.sourceInfo = quickLookSource({ itemID = writID, name = data.title }, row, row.craftAbility, source, data.title)
    local turnInCost = (row.mode == "Craft" and number(row.craftCost)) or (row.mode == "Buy" and number(row.buyCost))
    data.overviewRows = {
        { key = "netCost", label = "Net turn-in cost", qtyText = "1x", liveValue = number(row.totalPrice) or data.net.last,
            valueKind = "signed_money", series = data.net, lowerIsBetter = true },
        { key = "writScroll", label = "Writ scroll", qtyText = "1x", liveValue = nonnegative(row.writPrice) or scroll.ah.last,
            valueKind = "money", series = scroll.ah, lowerIsBetter = true },
        { key = "turnInItem", label = "Turn-in item", qtyText = tostring(qty) .. "x", liveValue = turnInCost or cost.last,
            valueKind = "money", series = cost, lowerIsBetter = true },
        { key = "coinPouch", label = "Coin pouch", qtyText = "1x", liveValue = refund, valueKind = "money", fixed = true, positive = true },
    }
    addMarketOverviewRows(data)
    local pct = data.gross.pct
    data.kpis = {
        { label = "Net Turn-In Cost", value = row.totalPrice, money = true, sub = "Cost/Rep: " .. moneyText(row.pricePerRep) },
        { label = "Coin Pouch", value = refund, money = true, positive = true, sub = tostring(rep) .. " Rep tier" },
        { label = state.window:upper() .. " Trend", value = pct and string.format("%+.1f%%", pct) or "-", deltaPct = pct, sub = mode == "Price unavailable" and mode or "Craft vs Buy AH | " .. mode },
    }
    addQuickLookMover(data.movers, scroll, 1, data.title, "Writ", state, scroll.ah, 0, row.writPrice)
    local chosen = scaleSpan(cost, 1 / qty)
    local liveUnit = row.mode == "Craft" and number(row.craftCost) and row.craftCost / qty
        or (row.mode == "Buy" and row.buyUnit or nil)
    addQuickLookMover(data.movers, turnIn, qty, row.reqItemName or writ.requiredItemName, "Turn-In", state, chosen, 0, liveUnit)
    addCraftMovers(data.movers, turnIn, batches, state)
    data.meta = { writID = writID, reqItemID = reqID, questID = row.questID or writ.questID,
        zone = zone, npc = npc, cdText = cdText, pouchRefund = refund, rep = rep, totalPrice = row.totalPrice,
        pricePerRep = row.pricePerRep, buyCost = row.buyCost, craftCost = row.craftCost, mode = mode, canQueue = true }
    return data
end

local function selectedBundleTotal(row)
    if row.mode == "Craft" then return number(row.craftTotal) or number(row.reagentTotal) or number(row.matCost) end
    if row.mode == "Buy" then return number(row.buyTotal) or number(row.reagentTotal) or number(row.matCost) end
end

local function crateBundle(row, state, itemID, bundle, selected)
    local qty = quickLookQty((selected and row.reagentQty) or bundle.qty)
    local prof = (selected and row.prof) or bundle.prof
    local craftOpt = selected and tableValue(row.craftOpt)
    local item = acquisitionSpan(itemID, state, craftOpt and craftOpt.recipe, nil, nil, prof)
    local overrides = state.context.crateOverrides or row.crateOverrides
    local subCraftOverrides = state.context.subCraftOverrides
    local override = (overrides and overrides[itemID]) or (subCraftOverrides and subCraftOverrides[itemID])
    local series = chooseSpan(item.ah, item.craft, state.context.crateMode or "cheapest", override)
    local total = selected and selectedBundleTotal(row)
    local livePrice = (total and total / qty) or (selected and number(row.reagentEach)) or nil
    return { item = item, qty = qty, name = bundle.name or row.reagentName, series = series,
        cost = selected and scaleSpan(series, qty), livePrice = livePrice }
end

local function selectedCrateBundle(row, state, bundles)
    local first = bundles and bundles[1]
    local itemID = nonnegative(tonumber(row.reagentID or (first and first.itemID)))
    if not itemID or itemID <= 0 then return end
    for _, bundle in ipairs(bundles or {}) do
        if bundle.itemID == itemID then return crateBundle(row, state, itemID, bundle, true) end
    end
    return crateBundle(row, state, itemID, {}, true)
end

local function addBundleMovers(movers, bundle, state, indent)
    local item, qty = bundle.item, bundle.qty
    addQuickLookMover(movers, item, qty, bundle.name, "Bundle", state, bundle.series, indent, bundle.livePrice)
    if item.recipe then
        addCraftMovers(movers, item, qty / math.max(1, tonumber(item.recipe.numMade) or 1), state, indent + 1)
    end
end

function Stats.BuildCrateQuickLook(row, context, nowOverride)
    if type(row) ~= "table" then return nil end
    local state = quickLookState(context, nowOverride)
    local crate = row.crate or {}
    local crateID = nonnegative(tonumber(row.crateID or crate.itemID))
    if not crateID or crateID <= 0 then return nil end
    local selected = selectedCrateBundle(row, state, crate.bundles)
    if not selected then return nil end
    local empty = acquisitionSpan(crateID, state)
    local cost = selected.cost
    local reward = number(row.reward) or 0
    local data = acquisitionQuickLook("crate", row, state, empty, cost, reward)
    local tokens = row.tokens or 0
    local mode = acquisitionModeLabel(row.mode, row.buyTotal, row.craftTotal)
    data.title = row.crateFullName or row.crateName or crate.name or "Crate"
    data.badge = "+" .. tostring(tokens) .. " Favor · " .. tostring(crate.tier or "Crate")
    data.subtitle = "Reward Cashback " .. moneyText(reward) .. " | Mode " .. mode .. " | Owned " .. tostring(owned(state.context, crateID, data.title))
    local source = data.title .. " (+" .. tostring(tokens) .. " Favor, Mode " .. mode .. ")"
    data.sourceInfo = quickLookSource(row.crate or { itemID = crateID, name = data.title }, row, row.craftAbility, source, data.title)
    data.overviewRows = {
        { key = "netCost", label = "Net crate cost", qtyText = "1x", liveValue = number(row.totalPrice) or data.net.last,
            valueKind = "signed_money", series = data.net, lowerIsBetter = true },
        { key = "emptyCrate", label = "Empty crate", qtyText = "1x", liveValue = nonnegative(row.cratePrice) or empty.ah.last,
            valueKind = "money", series = empty.ah, lowerIsBetter = true },
        { key = "bundleCost", label = "Bundle cost", qtyText = tostring(selected.qty) .. "x",
            liveValue = number(row.reagentTotal) or cost.last, valueKind = "money", series = cost, lowerIsBetter = true },
        { key = "turnInReward", label = "Turn-in reward", qtyText = "1x", liveValue = reward, valueKind = "money", fixed = true, positive = true },
    }
    addMarketOverviewRows(data)
    local pct = data.gross.pct
    data.kpis = {
        { label = "Net Crate Cost", value = row.totalPrice, money = true, sub = "Cost/Token: " .. moneyText(row.pricePerToken) },
        { label = "Crate Reward", value = reward, money = true, positive = true, sub = "+" .. tostring(tokens) .. " Favor" },
        { label = state.window:upper() .. " Trend", value = pct and string.format("%+.1f%%", pct) or "-", deltaPct = pct, sub = "Empty Crate + Bundle | " .. mode },
    }
    addQuickLookMover(data.movers, empty, 1, data.title, "Crate", state, empty.ah, 0, row.cratePrice)
    if crate.bundles then
        for _, bundle in ipairs(crate.bundles) do
            local details = bundle.itemID == selected.item.itemID and selected or crateBundle(row, state, bundle.itemID, bundle)
            addBundleMovers(data.movers, details, state, 0)
        end
    else
        addBundleMovers(data.movers, selected, state, 0)
    end
    data.meta = { crateID = crateID, tokens = tokens, reward = reward, totalPrice = row.totalPrice,
        pricePerToken = row.pricePerToken, cratePrice = row.cratePrice, buyTotal = row.buyTotal,
        craftTotal = row.craftTotal, mode = mode, canAddToList = true }
    return data
end

function Stats.FormatForgedBreakdown(summary, formatMoney, short)
    if not summary then return end
    formatMoney = formatMoney or moneyText
    local favor = tostring(summary.favorRequired) .. (short and not summary.isBanked and "F: " or "x Favor: ")
    local refunds = " | Refunds: +" .. formatMoney(summary.totalRefund)
    if summary.isBanked then
        return favor .. formatMoney(0) .. " (Banked Favor)" .. refunds
            .. " (Quest " .. tostring(summary.questID) .. " " .. summary.questName .. ")"
    end

    local source = summary.feederName or "Feeder unavailable"
    if short then source = source:gsub("^Waylaid Crate:%s*", "") end
    if summary.costPerFavor ~= nil then source = source .. " @ " .. formatMoney(summary.costPerFavor) .. "/F" end
    if summary.favorCost == nil then
        return favor .. source .. (summary.feederName and " (price unavailable)" or "") .. refunds
    end
    local net = formatMoney(summary.favorCost) .. " net"
    if summary.favorGrossCost == nil or summary.favorCashback == nil then
        return favor .. source .. " | " .. net .. refunds
    end
    local cashback = formatMoney(summary.favorCashback)
    local gross = formatMoney(summary.favorGrossCost)
    if short then
        refunds = refunds .. " (" .. cashback .. " + " .. formatMoney(summary.forgedRefund) .. ")"
    else
        refunds = refunds .. " (" .. cashback .. " Favor Crate + " .. formatMoney(summary.forgedRefund) .. " " .. summary.questName .. ")"
    end
    return favor .. source .. (short and " | " or " (") .. gross .. " gross - " .. cashback .. " cashback = "
        .. net .. (short and "" or ")") .. refunds
end

local function forgedFavorSpan(empty, bundle, ratio, reward, slotCount)
    local values = {}
    if empty and bundle and ratio then
        for slot = 1, slotCount do
            local net = acquisitionCost(empty.ah.values[slot], bundle.cost.values[slot], reward)
            if net then values[slot] = net * ratio end
        end
    end
    return spanSeries(values, slotCount, true)
end

function Stats.BuildForgedQuickLook(row, context, nowOverride)
    if type(row) ~= "table" then return nil end
    local crate = tableValue(row.crate)
    local crateID = nonnegative(tonumber(row.crateID or row.itemID or (crate and crate.itemID)))
    if not crateID or crateID <= 0 then return nil end
    local state = quickLookState(context, nowOverride)
    local isBanked = row.forgedMode == "banked" or state.context.forgedMode == "banked"
    local mode = isBanked and "banked" or "self_funded"
    local receipt = tableValue(ns.FORGED_RECEIPT) or {}
    local receiptID, receiptName = nonnegative(receipt.receiptItemID) or 262902, text(receipt.receiptName) or "Forged Delivery Receipt"
    local containerID = nonnegative(receipt.containerItemID) or 262917
    local containerName = text(receipt.containerName) or "Notarized Shipping Container"
    local questID, questName = nonnegative(receipt.questID) or 93862, text(receipt.questName) or "Crate Return"
    local favorRequired = nonnegative(row.favorRequired) or nonnegative(receipt.favorCost) or 15
    local baseRep = nonnegative(row.baseRep) or nonnegative(receipt.baseRep) or 50
    local forgedRefund = nonnegative(row.forgedRefund) or nonnegative(receipt.refundCopper) or 100
    local dailyCap = nonnegative(receipt.dailyCap) or 0
    local repMult = number(row.repMult) or (ns.GetRacialRepMultiplier and ns.GetRacialRepMultiplier(state.context.humanDiplomacy)) or 1.0
    local effectiveRep = nonnegative(row.rep) or math.floor(baseRep * repMult + 0.5)
    local humanRep = math.floor(baseRep * 1.1 + 0.5)
    local empty = acquisitionSpan(crateID, state)
    local emptyPrice = number(row.emptyPrice) or empty.unitPrice or empty.ah.last

    local feeder = not isBanked and tableValue(row.bestFavorCrate) or nil
    local feederCrate = feeder and tableValue(feeder.crate)
    local feederID = feeder and nonnegative(tonumber(feeder.crateID or feeder.itemID or (feederCrate and feederCrate.itemID)))
    local feederEmpty, feederBundle, feederPrice
    if feederID and feederID > 0 then
        feederEmpty = acquisitionSpan(feederID, state)
        feederBundle = selectedCrateBundle(feeder, state, feederCrate and feederCrate.bundles)
        feederPrice = number(feeder.cratePrice) or number(feeder.emptyPrice) or feederEmpty.unitPrice
    end
    local tokens = feeder and (nonnegative(feeder.tokens) or nonnegative(feeder.favor))
    local ratio = tokens and tokens > 0 and favorRequired / tokens or nil
    local feederReward = feeder and (number(feeder.reward) or number(feeder.rewardCopper) or number(feeder.cashback)) or 0
    local historicalCashback = ratio and feederReward * ratio
    local favorSeries = forgedFavorSpan(feederEmpty, feederBundle, ratio, feederReward, state.slotCount)
    local sourcingSeries = not isBanked and favorSeries or nil
    local data = acquisitionQuickLook("forged", row, state, empty, sourcingSeries, forgedRefund, historicalCashback)
    data.cost, data.scrollCost = favorSeries, emptyPrice
    data.chartSeries.emptyCrate, data.chartSeries.favorCost = empty.ah, favorSeries

    local feederName, costPerFavor
    local favorGrossCost, favorCashback, liveFavorCost = 0, 0, 0
    if not isBanked then
        feederName = row.favorCrateName or (feeder and (feeder.crateFullName or feeder.crateName or feeder.name)) or (feederCrate and feederCrate.name)
        costPerFavor = number(row.favorCostPerFavor) or (feeder and (number(feeder.pricePerToken) or number(feeder.costPerFavor)))
        local bundleTotal = feeder and (number(feeder.reagentTotal) or number(feeder.matCost) or selectedBundleTotal(feeder))
        local feederGross = feeder and (number(feeder.grossTotal) or number(feeder.grossCost)) or (feederPrice and bundleTotal and feederPrice + bundleTotal)
        local feederNet = feeder and (number(feeder.totalPrice) or number(feeder.netCost))
        favorCashback = number(row.favorCashback) or historicalCashback
        favorGrossCost = number(row.favorGrossCost) or (ratio and feederGross and feederGross * ratio)
        liveFavorCost = number(row.favorCost) or (costPerFavor and costPerFavor * favorRequired) or (ratio and feederNet and feederNet * ratio)
            or (favorGrossCost and favorCashback and favorGrossCost - favorCashback) or favorSeries.last
        costPerFavor = costPerFavor or (liveFavorCost and favorRequired > 0 and liveFavorCost / favorRequired) or nil
        favorGrossCost = favorGrossCost or (liveFavorCost and favorCashback and liveFavorCost + favorCashback)
    end
    local totalRefund = isBanked and forgedRefund or number(row.totalRefund) or (forgedRefund + (favorCashback or 0))
    local rowModeMatches = row.forgedMode == nil or row.forgedMode == mode
    local netCost = number(row[isBanked and "bankedNetCost" or "selfFundedNetCost"])
        or (rowModeMatches and number(row.netCost)) or acquisitionCost(emptyPrice, liveFavorCost, forgedRefund) or data.net.last
    local liveCostPerRep = number(row[isBanked and "bankedCostPerRep" or "selfFundedCostPerRep"])
        or (rowModeMatches and number(row.costPerRep)) or (effectiveRep > 0 and netCost and netCost / effectiveRep) or nil
    local costPerRepValues = {}
    if effectiveRep > 0 then
        for slot, point in ipairs(data.days) do
            local value = point.netCost and point.netCost / effectiveRep
            point.costPerRep, costPerRepValues[slot] = value, value
        end
    end
    local costPerRepSeries = spanSeries(costPerRepValues, state.slotCount, true)
    data.chartSeries.costPerRep = costPerRepSeries

    local emptyAhQty = data.liveListed
    local listedText = emptyAhQty and (tostring(math.floor(emptyAhQty + 0.5)) .. " listed") or "Listings unavailable"
    local tier = row.tier or (crate and crate.tier) or "-"
    data.icon = row.icon or row.crateIcon or (ns.ItemIcon and ns.ItemIcon(crateID)) or ns.QUESTION_ICON
    data.title = row.name or row.crateFullName or row.crateName or (ns.ItemName and ns.ItemName(crateID)) or "Forged Crate"
    data.badge = "Tier " .. tostring(tier) .. " | Forged Delivery (+" .. tostring(baseRep) .. " Rep / +" .. tostring(humanRep) .. " Human)"
    data.subtitle = "Empty Crate + " .. tostring(favorRequired) .. " Favor | " .. listedText
    data.overviewRows = {
        { key = "costPerRep", label = isBanked and "Cost / Rep (Banked)" or "Cost / Rep (Self-Funded)",
            qtyText = tostring(effectiveRep) .. " Rep", liveValue = liveCostPerRep, valueKind = "cost_money", series = costPerRepSeries, lowerIsBetter = true },
        { key = "emptyCrate", label = "Empty crate (AH)", qtyText = "1x", liveValue = emptyPrice,
            valueKind = "money", series = empty.ah, lowerIsBetter = true },
        { key = "favorSourcing", label = tostring(favorRequired) .. "x Favor sourcing", qtyText = tostring(favorRequired) .. "F",
            liveValue = liveFavorCost, valueKind = "money", valueSuffix = isBanked and " (Banked)" or nil,
            series = sourcingSeries, lowerIsBetter = true, fixed = isBanked, tag = isBanked and "BANKED" or nil },
        { key = "questRefunds", label = "Quest refunds", qtyText = isBanked and "1x" or "2x", liveValue = totalRefund,
            valueKind = "signed_money", fixed = true, positive = true },
    }
    addMarketOverviewRows(data)
    local crateShort = row.shortName or row.crateName or data.title:gsub("^Waylaid Crate:%s*", "")
    addQuickLookMover(data.movers, empty, 1, crateShort, "Crate", state, empty.ah, 0, emptyPrice)
    if feederEmpty then
        addQuickLookMover(data.movers, feederEmpty, 1, feederName, "Feeder", state, feederEmpty.ah, 0, feederPrice)
        if feederBundle then addBundleMovers(data.movers, feederBundle, state, 1) end
    end

    local allianceNPC, hordeNPC = tableValue(receipt.turnInAlliance), tableValue(receipt.turnInHorde)
    local mechanicsText = string.format("%d %s (%d Favor, Friendly) -> Empty Crate -> %d %s -> Quest %d %s at %s / %s (+%d Rep, +%s, %d daily cap)",
        receiptID, receiptName, favorRequired, containerID, containerName, questID, questName,
        (allianceNPC and text(allianceNPC.name)) or "Marcy Baker", (hordeNPC and text(hordeNPC.name)) or "Dokimi",
        baseRep, moneyText(forgedRefund), dailyCap)
    data.sourceInfo = quickLookSource({ itemID = receiptID, name = receiptName }, row, row.craftAbility, mechanicsText, data.title)
    data.forgedSummary = { isBanked = isBanked, favorRequired = favorRequired, feederName = feederName, costPerFavor = costPerFavor,
        favorGrossCost = favorGrossCost, favorCashback = favorCashback, favorCost = liveFavorCost, forgedRefund = forgedRefund,
        totalRefund = totalRefund, questID = questID, questName = questName }
    data.breakdown = Stats.FormatForgedBreakdown(data.forgedSummary)
    data.sourceInfo.breakdown = data.breakdown
    local pct = data.gross.pct
    data.kpis = {
        { label = "Net Delivery Cost", value = netCost, money = true, sub = "Cost/Rep: " .. moneyText(liveCostPerRep) },
        { label = "Quest Refunds", value = totalRefund, money = true, positive = true, sub = tostring(effectiveRep) .. " Rep" },
        { label = state.window:upper() .. " Trend", value = pct and string.format("%+.1f%%", pct) or "-", deltaPct = pct,
            sub = isBanked and "Banked Favor" or "Self-Funded" },
    }
    data.meta = { crateID = crateID, receiptItemID = receiptID, containerItemID = containerID, questID = questID, forgedMode = mode,
        emptyPrice = emptyPrice, emptyAhQty = emptyAhQty, favorRequired = favorRequired, favorCrateID = feederID, favorCrateName = feederName,
        favorCostPerFavor = costPerFavor, favorGrossCost = favorGrossCost, favorCashback = favorCashback, favorCost = liveFavorCost,
        forgedRefund = forgedRefund, totalRefund = totalRefund, netCost = netCost, baseRep = baseRep, repMult = repMult,
        rep = effectiveRep, costPerRep = liveCostPerRep, dailyCap = dailyCap, canAddToList = true }
    return data
end

local function recipePin(recipe)
    local pins = ns.NPC_PINS
    if type(pins) ~= "table" then return end
    local key = (ns.MapPins and ns.MapPins.RecipeKey and ns.MapPins.RecipeKey(recipe))
        or ("s:" .. tostring(recipe.spellID or 0) .. ":i:" .. tostring(recipe.recipeItemID or 0))
    local choices = pins[key] or (recipe.spellID and pins["spell:" .. tostring(recipe.spellID)])
        or (recipe.outputItemID and pins["item:" .. tostring(recipe.outputItemID)])
    if choices and choices.name then return choices end

    local faction = UnitFactionGroup and text(UnitFactionGroup("player"))
    local shortFaction = faction and faction:sub(1, 1)
    local best, bestID, bestRank
    local function consider(id, pin)
        local rank = 0
        local available = pin.recipeFactions and pin.recipeFactions[key]
        if faction and (not available or available == "AH" or available == faction or available == shortFaction) then
            if pin.faction == faction or pin.faction == shortFaction then rank = 2
            elseif not pin.faction or pin.faction == "AH" then rank = 1 end
        end
        if not best or rank > bestRank or (rank == bestRank and id < bestID) then
            best, bestID, bestRank = pin, id, rank
        end
    end
    if choices then
        for i, pin in ipairs(choices) do consider(i, pin) end
    else
        for id, pin in pairs(pins) do
            if type(id) == "number" then
                for _, recipeKey in ipairs(pin.recipeKeys or {}) do
                    if recipeKey == key then
                        consider(id, pin)
                        break
                    end
                end
            end
        end
    end
    return best
end

local pinKindLabels = { vendor = "Vendor", trainer = "Trainer", camp = "Favor vendor" }

local function recipeSource(recipe, row, ability)
    local pin = recipePin(recipe)
    if pin and pin.name then
        local spawn = pin.spawns and pin.spawns[1] or pin
        local map = C_Map and C_Map.GetMapInfo and spawn.uiMapID and tableValue(C_Map.GetMapInfo(spawn.uiMapID))
        local zone = (map and text(map.name)) or recipe.zone
        local x, y = number(spawn.x), number(spawn.y)
        local coords = ""
        if x and y then
            local scale = x <= 1 and y <= 1 and 100 or 1
            coords = string.format(" (%.1f, %.1f)", x * scale, y * scale)
        end
        local kind = pinKindLabels[pin.kind] or row.sourceLabel or "Recipe source"
        return kind .. ": " .. pin.name .. (zone and (" — " .. zone) or "") .. coords
    end
    local detail = ability.howDetail
    return (detail and detail ~= "" and detail) or row.sourceLabel or "Trainer / AH"
end

-- Historical costs use observed reagent purchase prices per craft. Live rows can value subcrafts differently.
function Stats.BuildItemQuickLook(row, context, nowOverride)
    if type(row) ~= "table" then return nil end
    local itemID = nonnegative(tonumber(row.itemID or row.outputItemID))
    if not itemID or itemID <= 0 then return nil end

    local state = quickLookState(context, nowOverride)
    local slotCount = state.slotCount
    local output, localSales, scan, firstQty, _, listed, liveQty =
        itemSpan(itemID, state.economy, state.now, state.startSlot, slotCount, nil, true)

    local liveAH = nonnegative(row.unitAH)
        or (ns.GetItemMarketPrice and nonnegative(ns.GetItemMarketPrice(itemID)))
        or output.last
    local liveMarket = nonnegative(row.marketValue)
    if liveMarket == nil and ns.Pricing and ns.Pricing.GetItemSnapshotLatest then
        local snap = ns.Pricing.GetItemSnapshotLatest(itemID, state.economy)
        liveMarket = snap and (nonnegative(snap.marketValue) or nonnegative(snap.historical)) or nil
    end
    local liveVendor = nonnegative(row.vendorSell)
        or (ns.GetVendorSellPrice and nonnegative(ns.GetVendorSellPrice(itemID)))

    local movers = {}
    if type(row.recipe) == "table" and type(row.recipe.reagents) == "table" then
        local recReagents = (ns.ResolveRecipeReagents and ns.ResolveRecipeReagents(row.recipe)) or row.recipe.reagents
        for _, reagent in ipairs(recReagents or {}) do
            local rid, rqty = reagent.itemID or reagent.id or reagent[1], reagent.qty or reagent[2]
            if rid and rqty and rqty > 0 then
                local quote = acquisitionQuote(rid, state)
                local series = quote.ah
                local trend = quote.observedSeries or series
                movers[#movers + 1] = {
                    itemID = rid,
                    name = (ns.ItemName and ns.ItemName(rid)) or tostring(rid),
                    qty = rqty,
                    tag = "Reagent",
                    series = series,
                    observedSeries = quote.observedSeries,
                    fixed = quote.fixed,
                    pureVendor = quote.pureVendor,
                    unitPrice = quote.unitPrice,
                    days = trend.days,
                    deltaPct = trend.pct,
                    impact = trend.change and trend.change * rqty,
                }
            end
        end
    end
    local usedSeen = {}
    local usedAdded = 0
    for _, u in ipairs(row.usedInRecipes or {}) do
        if usedAdded >= 12 then break end
        local outID = type(u) == "table" and nonnegative(tonumber(u.outputItemID)) or nil
        if outID and outID > 0 and not usedSeen[outID] then
            usedSeen[outID] = true
            usedAdded = usedAdded + 1
            local quote = acquisitionQuote(outID, state)
            local series = quote.ah
            local trend = quote.observedSeries or series
            movers[#movers + 1] = {
                itemID = outID,
                name = text(u.name) or (ns.ItemName and ns.ItemName(outID)) or tostring(outID),
                qty = 1,
                tag = "Used In",
                series = series,
                observedSeries = quote.observedSeries,
                fixed = quote.fixed,
                pureVendor = quote.pureVendor,
                unitPrice = quote.unitPrice,
                days = trend.days,
                deltaPct = trend.pct,
                impact = trend.change,
            }
        end
    end

    local title = text(row.name) or (ns.ItemName and ns.ItemName(itemID)) or ("Item #" .. tostring(itemID))
    local icon = row.icon or (ns.ItemIcon and ns.ItemIcon(itemID, ns.QUESTION_ICON)) or ns.QUESTION_ICON
    local catLabel = text(row.categoryLabel) or text(row.sourceLabel) or "Item"
    local reqSkill = number(row.requiredSkill)
    local badge = catLabel .. (reqSkill and (" · Skill " .. tostring(reqSkill)) or "")

    local data = {
        kind = "item",
        output = output,
        cost = spanSeries({}, slotCount, true),
        net = output,
        scroll = spanSeries({}, slotCount, true),
        movers = movers,
        firstQty = firstQty,
        scan = scan,
        now = state.now,
        made = 1,
        title = title,
        icon = icon,
        badge = badge,
    }
    setQuickLookMarket(data, row, state, itemID, localSales, listed, liveQty)

    local subParts = {}
    if text(row.gatherNote) and row.gatherNote ~= "" then
        subParts[#subParts + 1] = row.gatherNote
    end
    local usedInCount = number(row.usedInCount) or (type(row.usedInRecipes) == "table" and #row.usedInRecipes or 0)
    if usedInCount > 0 then
        subParts[#subParts + 1] = "Used in " .. tostring(usedInCount) .. (usedInCount == 1 and " recipe" or " recipes")
    end
    local curListed = data.liveListed
    subParts[#subParts + 1] = curListed and (tostring(curListed) .. " listed") or "Listings unavailable"
    data.subtitle = table.concat(subParts, "  |  ")

    data.overviewRows = {
        { key = "ahPrice", label = "AH price", qtyText = "1x", liveValue = liveAH,
            valueKind = "money", series = data.output, lowerIsBetter = false },
        { key = "marketValue", label = "Market value", qtyText = "1x", liveValue = liveMarket,
            valueKind = "money", series = spanSeries({}, slotCount, true), lowerIsBetter = false },
        { key = "vendorSell", label = "Vendor sell", qtyText = "1x", liveValue = liveVendor,
            valueKind = "money", series = spanSeries({}, slotCount, true), lowerIsBetter = false },
        { key = "salesPerDay", label = "Sales per day", qtyText = "1d", liveValue = data.liveSalesPerDay,
            valueKind = "rate", series = data.sales, lowerIsBetter = false, salesSource = data.salesSource },
    }
    addMarketOverviewRows(data)

    local profObj = (ns.PROF_BY_KEY or {})[row.prof]
    local profFull = (profObj and profObj.full) or text(row.prof) or "Profession"
    local whereToBuy
    if row.itemType == "gather" then
        whereToBuy = profFull .. (reqSkill and (" (Skill " .. tostring(reqSkill) .. ")") or "")
            .. ((text(row.gatherNote) and row.gatherNote ~= "") and (" - " .. row.gatherNote) or "")
    elseif nonnegative(row.vendorBuy) and row.vendorBuy > 0 then
        whereToBuy = "NPC Vendor (" .. moneyText(row.vendorBuy) .. ")"
    elseif row.itemType == "crafted" or type(row.recipe) == "table" then
        whereToBuy = "Crafted (" .. profFull .. (reqSkill and (" " .. tostring(reqSkill)) or "") .. ")"
    else
        whereToBuy = text(row.sourceLabel) or "Catalog Item"
    end
    local wowheadURL = text(row.wowheadURL) or ("https://www.wowhead.com/classic/item=" .. tostring(itemID))
    data.sourceInfo = {
        whereToBuy = whereToBuy,
        wowheadURL = wowheadURL,
        wowheadCA = {
            wowheadURL = wowheadURL,
            wowheadLabel = title,
            wowheadKind = "item",
            howDetail = whereToBuy,
            recipeName = title,
        },
    }
    return data
end

function Stats.BuildQuickLook(row, context, nowOverride)
    if row.forged or (context and context.kind == "forged") then return Stats.BuildForgedQuickLook(row, context, nowOverride) end
    if row.writ or (context and context.kind == "writ") then return Stats.BuildWritQuickLook(row, context, nowOverride) end
    if row.crate or (context and context.kind == "crate") then return Stats.BuildCrateQuickLook(row, context, nowOverride) end
    if (context and context.kind == "item") or (row.recipe == nil and (row.itemID or row.outputItemID)) then
        return Stats.BuildItemQuickLook(row, context, nowOverride)
    end
    if not row.recipe then return nil end
    local recipe = row.recipe
    local state = quickLookState(context, nowOverride)
    local slotCount = state.slotCount
    local outputID = row.outputItemID or recipe.outputItemID
    local output, localSales, scan, firstQty, _, listed, liveQty =
        itemSpan(outputID, state.economy, state.now, state.startSlot, slotCount, nil, true)

    local movers, bottleneck = {}, nil
    for _, reagent in ipairs(recipe.reagents or {}) do
        local id, qty = reagent.itemID or reagent.id or reagent[1], reagent.qty or reagent[2]
        if id and qty and qty > 0 then
            local quote = acquisitionQuote(id, state)
            local series = quote.ah
            local trend = quote.observedSeries or series
            local mover = { itemID = id, name = ns.ItemName(id), qty = qty, series = series,
                observedSeries = quote.observedSeries, fixed = quote.fixed, pureVendor = quote.pureVendor,
                unitPrice = quote.unitPrice, days = trend.days, deltaPct = trend.pct, impact = trend.change and trend.change * qty }
            movers[#movers + 1] = mover
            if not mover.fixed and (not bottleneck or mover.days < bottleneck.days
                or (mover.days == bottleneck.days and id < bottleneck.itemID)) then
                bottleneck = mover
            end
        end
    end
    table.sort(movers, function(a, b)
        local impactA, impactB = a.impact and math.abs(a.impact) or -1, b.impact and math.abs(b.impact) or -1
        if impactA ~= impactB then return impactA > impactB end
        return a.itemID < b.itemID
    end)

    local costs, profits = {}, {}
    local made = row.numMade or recipe.numMade or 1
    for slot = 1, slotCount do
        local total = #movers > 0 and 0 or nil
        for _, mover in ipairs(movers) do
            local price = mover.series.values[slot]
            if not price then total = nil; break end
            total = total + price * mover.qty
        end
        costs[slot] = total
        if total and output.values[slot] then
            local sale = output.values[slot]
            if state.context.applyAHCut ~= false then sale = math.floor(sale * 0.95 + 0.5) end
            profits[slot] = sale * made - total
        end
    end

    local scrollID = recipe.recipeItemID and recipe.recipeItemID > 0 and recipe.recipeItemID or nil
    local ability = row.craftAbility or {}
    local vendorPrice = scrollID and row.sourceLabel ~= "Merchant" and not ability.vendorFavorCost
        and (ability.howCategory == "vendor" or row.sourceLabel == "Vendor")
        and (nonnegative(ability.vendorCopperCost) or ns.GetRecipeVendorBuyPrice(scrollID, recipe.recipeVendorPrice)) or nil
    local canTradeScroll = scrollID and not ability.vendorFavorCost and row.sourceLabel ~= "Merchant"
        and (not ns.IsItemSellable or ns.IsItemSellable(scrollID))
    local scrollMarket, _, scrollScan, _, _, scrollListed, scrollLiveQty =
        itemSpan(canTradeScroll and scrollID, state.economy, state.now, state.startSlot, slotCount, nil, true)
    local scroll = vendorPrice and itemSpan(scrollID, state.economy, state.now, state.startSlot, slotCount, vendorPrice, true)
        or scrollMarket
    local scrollLiveListed = canTradeScroll and (nonnegative(ns.GetNumListed and ns.GetNumListed(scrollID))
        or scrollLiveQty or (scrollScan and scrollScan.qty) or scrollListed.last) or nil
    local scrollCost = vendorPrice or scroll.values[slotCount] or (canTradeScroll and nonnegative(ability.recipeAHPrice)) or nil
    local profit, craftCost = number(row.profit), nonnegative(row.craftCost)
    local data = { kind = "recipe", output = output, cost = spanSeries(costs, slotCount, true),
        net = spanSeries(profits, slotCount, true), scroll = scroll, movers = movers, bottleneck = bottleneck,
        scrollID = scrollID, scrollCost = scrollCost, scrollFixed = vendorPrice ~= nil,
        scrollListed = scrollListed, scrollLiveListed = scrollLiveListed, canTradeScroll = canTradeScroll == true,
        breakEvenCrafts = scrollCost and scrollCost > 0 and profit and profit > 0
            and math.ceil(scrollCost / (profit * math.max(1, number(made) or 1))) or nil,
        firstQty = firstQty, scan = scan, now = state.now, made = made }
    setQuickLookMarket(data, row, state, outputID, localSales, listed, liveQty)

    local craftQty = tostring(made) .. "x"
    data.overviewRows = {
        { key = "profit", label = "Profit", qtyText = craftQty, liveValue = profit and profit * made or data.net.last,
            valueKind = "signed_money", series = data.net, lowerIsBetter = false },
        { key = "sellPrice", label = "Sell price", qtyText = "1x",
            liveValue = nonnegative(row.unitAH) or nonnegative(row.ahPrice) or nonnegative(row.targetPrice) or data.output.last,
            valueKind = "money", series = data.output, lowerIsBetter = false },
        { key = "craftCost", label = "Craft cost", qtyText = craftQty, liveValue = craftCost and craftCost * made or data.cost.last,
            valueKind = "money", series = data.cost, lowerIsBetter = true },
        { key = "salesPerDay", label = "Sales per day", qtyText = "1d", liveValue = data.liveSalesPerDay,
            valueKind = "rate", series = data.sales, lowerIsBetter = false, salesSource = data.salesSource },
    }
    addMarketOverviewRows(data)

    local scrollName = ability.recipeName or (scrollID and ns.ItemName(scrollID)) or row.name
    data.scrollInfo = quickLookSource(recipe, row, ability, recipeSource(recipe, row, ability), scrollName)
    data.scrollInfo.listed, data.scrollInfo.liveListed, data.scrollInfo.canTrade = scrollListed, scrollLiveListed, data.canTradeScroll
    local breakEven = data.breakEvenCrafts
    data.scrollInfo.breakEvenText = breakEven and ("Break-even: " .. tostring(breakEven) .. (breakEven == 1 and " craft" or " crafts"))
    data.scrollInfo.fixedLabel = data.scrollFixed and "VENDOR" or nil
    return data
end

local function resolveTrainerFees(context)
    local professor=(ns.GetProfessorDB and ns.GetProfessorDB()) or _G.MerchantProfessorDB
    return tableValue(context.trainerCosts) or (professor and tableValue(professor.trainerCosts))
end

local function patchRowMeta(row,context,fees)
    local r=row.recipe or {}
    row.ownedOutputQty=owned(context,r.outputItemID,row.name)
    row.ownedScrollQty=owned(context,r.recipeItemID,r.recipeItemID and ns.ItemName(r.recipeItemID,r.recipeName))
    if ns.EvaluateUnlock then row.unlock=ns.EvaluateUnlock(r.prof,r.skill,r.rep,r.favorCost,r,context.profMap,context.repState) end
    local evaluateAbility=ns.EvaluateRecipeCraftAbility or ns.EvaluateCraftAbility
    if evaluateAbility then row.craftAbility=evaluateAbility(r,context.profMap,context.repState,context.ownedCounts) end
    local ability=tableValue(row.craftAbility)
    if ability then
        row.known=ability.known==true; row.canCraft=ability.ableToCraft==true or ability.canCraft==true
        row.canCraftSort=ability.sortScore
    end
    row.knownSort=row.known and 1 or 0
    row.sourceLabel=cleanSourceLabel(r,ability,row.sourceBucket)
    applyRepFields(row,r,context)
    applyCooldownFields(row,r,context and context.now)
    if row.sourceBucket=="trainer" then
        local fee=fees and (nonnegative(fees[r.spellID]) or nonnegative(fees[r.name]))
        row.buyCostCopper=fee; row.buyCostEstimated=false
        row.sourceCost={currencies={},copper=fee,known=fee~=nil}
    end
end

function Stats.PatchMeta(rows, context)
    context=tableValue(context) or defaultContext
    local fees=resolveTrainerFees(context)
    local evalTok=ns.PushEvalOpts and ns.PushEvalOpts(context)
    for _,row in ipairs(rows or {}) do
        patchRowMeta(row,context,fees)
    end
    if ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
end

function Stats.PatchMetaSlice(rows, context, startIdx, maxBatch, budgetMS, maxIndex)
    context=tableValue(context) or defaultContext
    rows=rows or {}
    local cap=#rows
    if type(maxIndex)=="number" and maxIndex<cap then cap=maxIndex end
    local idx=math.max(1,tonumber(startIdx) or 1)
    if idx>cap then return idx,true end
    local limit=math.max(1,tonumber(maxBatch) or 24)
    local deadline=budgetMS and (clockMS()+math.max(0.05,budgetMS)) or nil
    local fees=resolveTrainerFees(context)
    local processed=0
    local evalTok=ns.PushEvalOpts and ns.PushEvalOpts(context)
    while idx<=cap and processed<limit do
        patchRowMeta(rows[idx],context,fees)
        idx=idx+1
        processed=processed+1
        if deadline and clockMS()>=deadline then break end
    end
    if ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
    return idx,idx>cap
end

function Stats.PatchMetaTargeted(rows, context, targets)
    if type(rows)~="table" or #rows==0 or type(targets)~="table" then return 0 end
    local spells=tableValue(targets.spells)
    local ids=tableValue(targets.ids)
    local names=tableValue(targets.names)
    local hasSpells=spells~=nil and next(spells)~=nil
    local hasIDs=ids~=nil and next(ids)~=nil
    local hasNames=names~=nil and next(names)~=nil
    if not (hasSpells or hasIDs or hasNames) then return 0 end
    context=tableValue(context) or defaultContext
    local fees=resolveTrainerFees(context)
    local itemNameFn=ns.ItemName
    local patchedCount=0
    local evalTok=ns.PushEvalOpts and ns.PushEvalOpts(context)
    for i=1,#rows do
        local row=rows[i]
        local r=row and row.recipe or nil
        if r then
            local hit=false
            if hasSpells and r.spellID and spells[r.spellID] then
                hit=true
            elseif hasIDs and ((r.outputItemID and ids[r.outputItemID]) or (r.recipeItemID and ids[r.recipeItemID])) then
                hit=true
            elseif hasNames and ((row.name and names[row.name]) or (r.name and names[r.name]) or (r.recipeName and names[r.recipeName])) then
                hit=true
            elseif (hasIDs or hasNames) and type(r.reagents)=="table" then
                for j=1,#r.reagents do
                    local rg=r.reagents[j]
                    if type(rg)=="table" then
                        local rid=rg.itemID or rg.id or rg[1]
                        if hasIDs and rid and ids[rid] then
                            hit=true; break
                        end
                        if hasNames then
                            local rName=rg.name or (rid and itemNameFn and itemNameFn(rid))
                            if rName and names[rName] then
                                hit=true; break
                            end
                        end
                    end
                end
            end
            if hit then
                patchRowMeta(row,context,fees)
                patchedCount=patchedCount+1
            end
        end
    end
    if ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
    return patchedCount
end

-- Names/icons are presentation changes; unresolved economic dependencies need one new version.
function Stats.RepairItems(rows, context, itemIDs)
    context=tableValue(context) or defaultContext
    itemIDs=itemIDs or {}
    local economic=false
    for _,row in ipairs(rows or {}) do
        local r=row.recipe or {}
        local output=itemIDs[r.outputItemID]
        if output then
            row.name=ns.GetRecipeDisplayName and ns.GetRecipeDisplayName(r) or ns.ItemName(r.outputItemID,r.name)
            if ns.ItemIcon then row.icon=ns.ItemIcon(r.outputItemID,row.icon) end
            local qty=owned(context,r.outputItemID,row.name)
            row.ownedOutputQty=qty
            if ns.IsItemSellable and ns.IsItemSellable(r.outputItemID,r.sellable,r.isEnchant)~=row.sellable then economic=true end
            if ns.GetVendorSellPrice and (nonnegative(ns.GetVendorSellPrice(r.outputItemID)) or 0)~=(nonnegative(row.vendorSell) or 0) then economic=true end
        end
        if itemIDs[r.recipeItemID] then
            row.ownedScrollQty=owned(context,r.recipeItemID,ns.ItemName(r.recipeItemID,r.recipeName))
            if repairDependency(row,r.recipeItemID,r) then economic=true end
        end
        for _,rg in ipairs(r.reagents or {}) do
            local id=rg.itemID or rg.id or rg[1]
            if id and itemIDs[id] and repairDependency(row,id) then economic=true end
        end
    end
    return economic
end

function Stats.PrepareRepair(rows, context, itemIDs)
    Stats.GetCatalog()
    return {rows=rows or {}, context=tableValue(context) or defaultContext, itemIDs=itemIDs or {},
        outputsByReagent=outputsByReagent, favorInputs=favorInputs,
        ids={}, expanded={}, head=1, edge=1, invalidate=1, index=1, repaired=0}
end

local function addRepairID(job,id)
    if not job.expanded[id] then
        job.expanded[id]=true
        job.ids[#job.ids+1]=id
    end
end

local function prepareRepairSlice(job,context,deadline)
    while not job.seeded and clockMS()<deadline do
        local id=next(job.itemIDs,job.seed)
        job.seed=id
        if id then addRepairID(job,id) else job.seeded=true end
    end
    if not job.seeded then return false end
    while job.head<=#job.ids and clockMS()<deadline do
        local outputs=job.outputsByReagent[job.ids[job.head]]
        local output=outputs and outputs[job.edge]
        if output then
            addRepairID(job,output)
            job.edge=job.edge+1
        else
            job.head,job.edge=job.head+1,1
        end
    end
    if job.head<=#job.ids then return false end
    local state=caches[context]
    local bank=state and state.bank
    if job.invalidate==1 and #job.ids>0 then ns.InvalidateEvalCrafts(bank) end
    while job.invalidate<=#job.ids and clockMS()<deadline do
        local id=job.ids[job.invalidate]
        ns.InvalidateEvalItem(bank,id)
        if state and state.itemPrices then state.itemPrices[id]=nil end
        if job.favorInputs[id] then job.repairFavor=true end
        job.invalidate=job.invalidate+1
    end
    if job.invalidate<=#job.ids then return false end
    if state and job.repairFavor then
        state.favorLoaded,state.favorCopper,state.bestFavorToken,state.crateScanIdx=nil,nil,nil,nil
        state.favorRows={}
    end
    return true
end

local function matchesRepair(recipe,ids)
    if ids[recipe.outputItemID] or ids[recipe.recipeItemID] then return true end
    for _,rg in ipairs(recipe.reagents or {}) do
        if ids[rg.itemID or rg.id or rg[1]] then return true end
    end
    return false
end

local function runRepairSlice(job,context,limit,deadline)
    if not job.prepared then
        job.prepared=prepareRepairSlice(job,context,deadline)
        if not job.prepared then return false end
        if #job.ids==0 then return true end
    end
    local batch,processed
    while job.index<=#job.rows and clockMS()<deadline do
        local row=job.rows[job.index]
        local recipe=row.recipe
        if recipe and (matchesRepair(recipe,job.expanded) or (job.repairFavor and usesCrateFavor(row,context))) then
            if not batch then
                if Stats.WarmStep(context,deadline-clockMS()) then return false end
                batch=Stats.BeginBatch(context)
                processed=0
            end
            batch.rows[recipe],batch.favorRows[recipe]=nil,nil
            job.rows[job.index]=Stats.Get(recipe,context)
            job.repaired=job.repaired+1
            processed=processed+1
        end
        job.index=job.index+1
        if processed==limit then break end
    end
    if batch then Stats.EndBatch() end
    return job.index>#job.rows
end

function Stats.RepairSlice(job, context, maxBatch, budgetMS)
    context=tableValue(context) or job.context
    local deadline=budgetMS and (clockMS()+budgetMS) or math.huge
    local ok,done=pcall(runRepairSlice,job,context,maxBatch or math.huge,deadline)
    if not ok then
        activeBatchContext,activeBatchState=nil,nil
        if ns.ResetEval then ns.ResetEval() else Stats.EndBatch() end
        return true,0,true
    end
    return done,job.repaired,false
end

function Stats.RepairItemsInPlace(rows, context, itemIDs)
    local job=Stats.PrepareRepair(rows,context,itemIDs)
    while true do
        local done,repaired,needFull=Stats.RepairSlice(job,context)
        if done then return repaired,needFull end
    end
end
