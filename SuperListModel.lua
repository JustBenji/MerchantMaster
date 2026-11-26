-- Local source selection intentionally does not change the legacy source filter.
local _, ns = ...
local Model={}; ns.SuperListModel=Model
local states=setmetatable({}, {__mode='kv'})
local function readable(v) return not (issecretvalue and issecretvalue(v)) end
local function numeric(v)
    return readable(v) and type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end
local function text(v) return readable(v) and type(v)=="string" and v or "" end
local function clockMS()
    if debugprofilestop then return debugprofilestop() end
    if GetTime then return GetTime()*1000 end
    return 0
end
local function sourcesActive(sources)
    if type(sources)~="table" or sources.all==true then return false end
    for _, enabled in pairs(sources) do if enabled==true then return true end end
    return false
end
local function sourceMatchesValues(sourceBucket, isWrit, sources)
    if not sourcesActive(sources) then return true end
    return sources[sourceBucket]==true or (sources.writ==true and isWrit==true)
end
local function normalizeProfFilter(v)
    if not readable(v) or type(v)~="string" then return "all" end
    local s=v:match("^%s*(.-)%s*$"):lower()
    return s~="" and s or "all"
end
local function isMineUnlockFilter(priority)
    if type(priority)~="table" then return false end
    if priority.knownRecipesOnly==true then return true end
    local u=priority.unlockFilter
    return u=="mine_profs" or u=="applies" or u=="known" or u=="unlocked"
end
local function hasAnyProf(profMap)
    if type(profMap)~="table" then return false end
    for _,v in pairs(profMap) do
        if v~=nil and v~=false then return true end
    end
    return false
end
local function entryMatchesStatic(entry, priority, lo, hi, hasSources, effProfFilter)
    local recipe=entry and entry.recipe
    if not recipe then return false end
    if hasSources then
        local bucket=entry.sourceBucket or (ns.GetRecipeSourceBucket and ns.GetRecipeSourceBucket(recipe))
        if not sourceMatchesValues(bucket,entry.isWrit,priority.sources) then return false end
    end
    if lo or hi then
        local skill=recipe.skill
        if not numeric(skill) or (lo and skill<lo) or (hi and skill>hi) then return false end
    end
    local profFilter=effProfFilter or normalizeProfFilter(priority.profFilter or priority.prof)
    if profFilter=="mine_profs" then
        if not (recipe.anyChar or (priority.profMap and priority.profMap[recipe.prof])) then return false end
    elseif profFilter=="others" then
        if not (recipe.prof=="others" or (ns.IsOtherExceptionRecipe and ns.IsOtherExceptionRecipe(recipe))) then return false end
    elseif profFilter~="all" and recipe.prof~=profFilter then
        return false
    end
    return true
end
local function applyPriority(state, catalog, priority)
    local total=#catalog
    local startIdx=state.index or 1
    local order=state.order
    if not order or #order~=total then
        order={}
        for i=1,total do order[i]=i end
        state.order=order
    end
    local key=priority and priority.key
    if state.priorityApplied and key~=nil and state.priorityKey==key then return order end
    state.priorityApplied=true
    state.priorityKey=key
    if not priority then
        state.tier1Target=total
        state.tier1Authoritative=false
        state.tier1Notified=false
        return order
    end
    local hasSources=sourcesActive(priority.sources)
    local lo,hi=Model.SkillBound(priority.skillMin),Model.SkillBound(priority.skillMax)
    local rawProfFilter=normalizeProfFilter(priority.profFilter or priority.prof)
    local profMap=priority.profMap
    local hasProfs=hasAnyProf(profMap)
    local isFallback=priority.profMapFallback==true
    local mineNarrow=(rawProfFilter=="all") and isMineUnlockFilter(priority) and hasProfs and (not isFallback)
    local effProfFilter=mineNarrow and "mine_profs" or rawProfFilter
    local hasNarrowing=(effProfFilter~="all") or lo~=nil or hi~=nil or hasSources
    local t1Mine,t1Other,t2Mine,t3Rest={},{},{},{}
    for pos=startIdx,total do
        local idx=order[pos]
        local entry=catalog[idx]
        local recipe=entry and entry.recipe
        local isMine=recipe and profMap and profMap[recipe.prof]~=nil and profMap[recipe.prof]~=false
        if entryMatchesStatic(entry,priority,lo,hi,hasSources,effProfFilter) then
            if isMine then t1Mine[#t1Mine+1]=idx else t1Other[#t1Other+1]=idx end
        elseif isMine then
            t2Mine[#t2Mine+1]=idx
        else
            t3Rest[#t3Rest+1]=idx
        end
    end
    local pos=startIdx-1
    for _,idx in ipairs(t1Mine) do pos=pos+1; order[pos]=idx end
    for _,idx in ipairs(t1Other) do pos=pos+1; order[pos]=idx end
    local tier1Target=pos
    for _,idx in ipairs(t2Mine) do pos=pos+1; order[pos]=idx end
    for _,idx in ipairs(t3Rest) do pos=pos+1; order[pos]=idx end
    state.tier1Target=tier1Target
    state.tier1Authoritative=hasNarrowing and (not isFallback or rawProfFilter~="mine_profs") and (#t2Mine+#t3Rest>0)
    state.tier1Notified=false
    return order
end
function Model.BuildPriorityOrder(catalog, priority)
    local state={index=1}
    return applyPriority(state,catalog or {},priority)
end
function Model.Reprioritize(state, priority)
    if not state or state.completed then return state and state.order end
    local catalog=state.catalog or ns.RecipeStats.GetCatalog()
    return applyPriority(state,catalog,priority)
end
function Model.Attach(state, background, priority, onProgress, onComplete, onTierReady)
    if not state or state.completed then return state end
    local prevOnTierReady=state.onTierReady
    state.background=background==true
    if onProgress~=nil or background then state.onProgress=onProgress end
    if onComplete~=nil then state.onComplete=onComplete end
    if onTierReady~=nil or background then state.onTierReady=onTierReady end
    local catalog=state.catalog or ns.RecipeStats.GetCatalog()
    applyPriority(state,catalog,priority)
    if not state.background and state.onTierReady and not prevOnTierReady and state.tier1Authoritative and state.index>state.tier1Target then
        state.tier1Notified=false
    end
    return state
end
function Model.Start(context, onProgress, onComplete, resumeState, onTierReady)
    context=context or {}
    local catalog=ns.RecipeStats.GetCatalog()
    local identity=context.dataset or context
    local state=resumeState or states[context]
    if not state or state.dataset~=identity or state.catalog~=catalog then
        if state and state.cancel then state.cancel() end
        state={dataset=identity,catalog=catalog,rows={},index=1,favorWarmed=false,warmed=false,generation=0}
    end
    states[context]=state
    local prevOnTierReady=state.onTierReady
    state.onProgress=onProgress
    state.onComplete=onComplete
    state.onTierReady=onTierReady
    state.background=context.background==true
    applyPriority(state,catalog,context.priority)
    if not state.background and state.onTierReady and not prevOnTierReady and state.tier1Authoritative and state.index>state.tier1Target then
        state.tier1Notified=false
    end
    if state.running or state.completed then return state.cancel or function() end,state end
    state.generation=state.generation+1
    local token=state.generation
    state.running=true
    state.warmed=false
    local function current() return state.running and state.generation==token end
    local function cancel()
        if state.generation==token then
            state.running=false; state.cancel=nil; state.generation=token+1
        end
    end
    state.cancel=cancel
    local defer=context.defer or (C_Timer and C_Timer.After and function(fn) C_Timer.After(0,fn) end)
    local stats=ns.RecipeStats
    local function runBatch(started)
        local count=0
        local maxBatch=state.background and 16 or 20
        local budgetMS=state.background and 1.2 or 1.8
        repeat
            if state.index>#state.order then break end
            local entry=catalog[state.order[state.index]]
            local isFirstFavor=not state.favorWarmed and (entry.recipe.favorCost or 0)>0
            local recipeStarted=isFirstFavor and clockMS()
            state.rows[#state.rows+1]=stats.Get(entry.recipe,context)
            if isFirstFavor then state.favorWarmed=true; state.favorWarmMS=clockMS()-recipeStarted end
            state.index=state.index+1; count=count+1
            if isFirstFavor then break end
            if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index>state.tier1Target then break end
        until count>=maxBatch or clockMS()-started>=budgetMS
    end
    local step
    local batchOpen=false
    local stepping,stepAgain=false,false
    local function runStep()
        if not current() then return end
        if not state.warmed then
            local warmSlice=state.background and 1.2 or 1.8
            if defer then
                if ns.RecipeStats.WarmStep and ns.RecipeStats.WarmStep(context,warmSlice) then
                    if not current() then return end
                    defer(step)
                    return
                end
                state.warmed=true
            else
                while ns.RecipeStats.WarmStep and ns.RecipeStats.WarmStep(context,warmSlice) do end
                state.warmed=true
            end
        end
        if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index>state.tier1Target then
            state.tier1Notified=true
            state.onTierReady(state.rows,#state.rows,#state.order)
            if not current() then return end
        end
        if state.index<=#state.order then
            local started=clockMS()
            if stats.BeginBatch then batchOpen=true; stats.BeginBatch(context) end
            runBatch(started)
            if stats.EndBatch then stats.EndBatch() end
            batchOpen=false
            if not current() then return end
            if state.onProgress then state.onProgress(state.rows,#state.rows,#state.order) end
            if not current() then return end
        end
        if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index>state.tier1Target then
            state.tier1Notified=true
            if state.index<=#state.order then
                state.onTierReady(state.rows,#state.rows,#state.order)
                if not current() then return end
            end
        end
        if state.index>#state.order then
            state.running=false; state.cancel=nil; state.completed=true
            if state.onComplete then state.onComplete(state.rows) end
        elseif defer then defer(step) end
    end
    step=function()
        if stepping then stepAgain=true; return end
        stepping=true
        repeat
            stepAgain=false
            local ok,err=pcall(runStep)
            if not ok then
                stepping=false
                if state.generation==token then
                    state.running=false; state.cancel=nil; state.completed=false
                    state.tier1Notified=false
                end
                if batchOpen and stats.EndBatch then pcall(stats.EndBatch) end
                if ns.ResetEval then ns.ResetEval() end
                error(err,0)
            end
        until not stepAgain
        stepping=false
    end
    if defer then defer(step) else repeat step() until not current() end
    return cancel,state
end

local numericKeys={ownedOutputQty=true,ownedScrollQty=true,buyCostCopper=true,craftCost=true,unitAH=true,
    salesPerDay=true,turnoverPerDay=true,profit=true,requiredSkill=true,skillupSort=true,bisSort=true,numMade=true,
    demandSort=true,canCraftSort=true,listed=true,marginPct=true,
    knownSort=true,goodScore=true,repSort=true,cdSort=true}
local function sourceMatches(row, sources)
    return sourceMatchesValues(row.sourceBucket, row.isWrit, sources)
end
local function matches(row, f, needle, lo, hi)
    if not sourceMatches(row,f.sources or f.recipeSources) then return false end
    if lo or hi then
        local skill=row.requiredSkill
        if not numeric(skill) or (lo and skill<lo) or (hi and skill>hi) then return false end
    end
    local prof=normalizeProfFilter(f.profFilter or f.prof)
    if prof=="mine_profs" then
        local rec=row.recipe
        if not ((rec and rec.anyChar) or (f.profMap and f.profMap[row.prof])) then return false end
    elseif prof=="others" then
        local rec=row.recipe
        if not (row.prof=="others" or (rec and ns.IsOtherExceptionRecipe and ns.IsOtherExceptionRecipe(rec))) then return false end
    elseif prof~="all" and row.prof~=prof then return false end
    local known=f.known
    if known==nil and f.knownRecipesOnly then known="known" end
    if (known=="known" or known==true) and not row.known then return false end
    if (known=="unknown" or known==false) and row.known then return false end
    if f.sellableFilter=="yes" and not row.sellable or f.sellableFilter=="no" and row.sellable then return false end
    if f.bisOnly and not (row.bisInfo and row.bisInfo.isBiS) then return false end
    if f.craftableFilter and f.craftableFilter~="all" and not ns.MatchesCraftableFilter(row.craftAbility,f.craftableFilter) then return false end
    if f.demandFilter and f.demandFilter~="all" and not ns.MatchesDemandFilter(row.demand,f.demandFilter) then return false end
    if f.unlockFilter and f.unlockFilter~="all" and not ns.MatchesGlobalFilters(row.prof,row.unlock,"all",f.unlockFilter) then return false end
    if needle~="" then
        local blob=row._searchBlob
        if not blob or row._searchBlobName~=row.name then
            local recipe=row.recipe or {}
            local ability=row.craftAbility
            blob=table.concat({
                text(row.name),
                (row.outputItemID and ns.ItemName and text(ns.ItemName(row.outputItemID))) or "",
                text(row.prof),
                text(row.sourceLabel),
                text(row.repLabel),
                text(row.repFactionName),
                text(row.goodPlain),
                text(recipe.name),
                text(recipe.recipeName),
                text(recipe.effectText),
                text(ability and ability.howDetail),
            }, "\n"):lower()
            row._searchBlob=blob
            row._searchBlobName=row.name
        end
        if not blob:find(needle,1,true) then return false end
    end
    return true
end
-- Saved bounds are optional nonnegative integers; malformed legacy settings mean no bound.
function Model.SkillBound(value)
    if not readable(value) then return nil end
    if type(value)=='string' and value:match('^%s*%d+%s*$') then value=tonumber(value) end
    if numeric(value) and value>=0 and value==math.floor(value) then return value end
end
function Model.FilterSort(rows, filters, sort, workspace)
    filters=filters or {}
    sort=sort or {}
    workspace=workspace or {values={},profs={},names={},keys={}}
    local values,profs,names,keys=workspace.values,workspace.profs,workspace.names,workspace.keys
    if not workspace.keepEntries then
        for row in pairs(values) do values[row]=nil; profs[row]=nil; names[row]=nil; keys[row]=nil end
    end
    local key=sort.key or "profit"
    local isNumeric=numericKeys[key]
    local needle=text(filters.search):lower():match("^%s*(.-)%s*$")
    local lo,hi=Model.SkillBound(filters.skillMin),Model.SkillBound(filters.skillMax)
    local result={}
    for _, row in ipairs(rows or {}) do
        if matches(row,filters,needle,lo,hi) then
            result[#result+1]=row
            local value=row[key]
            if isNumeric then
                if not numeric(value) then value=false end
            else value=text(value) end
            values[row]=value
            profs[row]=text(row.prof); names[row]=text(row.name); keys[row]=text(row.key)
        end
    end
    local ascending=sort.ascending==true or sort.direction=="asc"
    table.sort(result,function(a,b)
        local av,bv=values[a],values[b]
        if isNumeric then
            if av==false and bv~=false then return false end
            if av~=false and bv==false then return true end
            if av~=false and av~=bv then if ascending then return av<bv else return av>bv end end
        else
            if av~=bv then if ascending then return av<bv else return av>bv end end
        end
        local ap,bp=profs[a],profs[b]
        if ap~=bp then return ap<bp end
        local an,bn=names[a],names[b]
        if an~=bn then return an<bn end
        return keys[a]<keys[b]
    end)
    return result
end

---------------------------------------------------------------------------------------------------
-- Vendor Crafter Model: Pricing, Legacy Perks, Buy Moat Order-Book Depth & Incremental Scanner
---------------------------------------------------------------------------------------------------
do
    local VC = {}
    ns.VendorCrafterModel = VC

    local C = {
        MAX_SUB_DEPTH = 4,
        MAX_SIM_CRAFTS = 10000,
        DEFAULT_VENDOR_LOOP_CAP = 500,
        MAX_PORTFOLIO_STEPS = 20000,
        MIN_MEASURED_SAMPLES = 10,
        MAX_BATCH = 24,
        BUDGET_MS = 1.8,
        EPS = 1e-9,
        DEFAULT_DATASET = {},
        COPY_FIELDS = {
            "key", "recipe", "spellID", "outputItemID", "name", "icon", "prof",
            "requiredSkill", "known", "knownSort", "cdInfo", "cdSort",
            "sourceBucket", "sourceLabel", "sourceCost", "buyCostCopper", "buyCostEstimated",
            "craftAbility", "unlock", "repSort", "repLabel", "repFactionName", "repMet", "reqRep",
            "wowheadURL", "ownedOutputQty", "ownedScrollQty", "isWrit",
            "skillYellow", "skillGreen", "skillGray",
        },
        NUMERIC_KEYS = {
            craftCost = true,
            minVendor = true,
            avgVendor = true,
            maxVendor = true,
            avgProfit = true,
            minProfit = true,
            maxProfit = true,
            marginPct = true,
            moatScore = true,
            profitableCrafts = true,
            totalProfitCap = true,
            totalSpendCap = true,
            buyCeiling = true,
            safeProfitCrafts = true,
            planCrafts = true,
            planProfit = true,
            planRank = true,
            requiredSkill = true,
            knownSort = true,
            cdSort = true,
            buyCostCopper = true,
            numMade = true,
            repSort = true,
            ownedOutputQty = true,
            ownedScrollQty = true,
        },
        HUGE_KEYS = {
            profitableCrafts = true,
            totalProfitCap = true,
            totalSpendCap = true,
            safeProfitCrafts = true,
            planCrafts = true,
            planProfit = true,
        },
        DEPTH_RANK = {
            live_lots = 3,
            snapshot_depth = 2,
            vendor_backstop = 2,
            listed = 1,
            none = 0,
        },
    }

    local H = {}
    local buildCache = setmetatable({}, { __mode = "k" })

    function H.sortableNum(v, allowHuge)
        if not readable(v) or type(v) ~= "number" or v ~= v then return false end
        if not allowHuge and (v == math.huge or v == -math.huge) then return false end
        return true
    end

    function H.serializeMap(tbl)
        if type(tbl) ~= "table" or not readable(tbl) or next(tbl) == nil then return "" end
        local ks = {}
        for k in pairs(tbl) do
            if readable(k) then ks[#ks + 1] = tostring(k) end
        end
        table.sort(ks)
        local parts = {}
        for i = 1, #ks do
            local k = ks[i]
            local v = tbl[k]
            if v == nil then
                local kn = tonumber(k)
                if kn ~= nil then v = tbl[kn] end
            end
            parts[i] = k .. "=" .. tostring(readable(v) and v or "")
        end
        return table.concat(parts, ",")
    end

    function H.resolveEconKey(context)
        local econ = context and text(context.economy)
        if econ and econ ~= "" then return econ end
        if ns.CurrentEconomyInfo then
            local info = ns.CurrentEconomyInfo()
            if type(info) == "table" and readable(info) and type(info.effectiveKey) == "string" and info.effectiveKey ~= "" then
                return info.effectiveKey
            end
        end
        if ns.DetectActiveEconomy then
            local e = ns.DetectActiveEconomy()
            if readable(e) and type(e) == "string" and e ~= "" then return e end
        end
        return nil
    end

    function H.itemName(id)
        if ns.ItemName then
            local nm = ns.ItemName(id)
            if readable(nm) and type(nm) == "string" and nm ~= "" then return nm end
        end
        return tostring(id)
    end

    function H.sanitizeLots(rawLots)
        if type(rawLots) ~= "table" or not readable(rawLots) or #rawLots == 0 then return nil end
        local out = {}
        local needsSort = false
        local prevP = 0
        for i = 1, #rawLots do
            local l = rawLots[i]
            if type(l) == "table" and readable(l) then
                local p, q = l.price, l.qty
                if numeric(p) and p > 0 and numeric(q) and q > 0 then
                    if p < prevP then needsSort = true end
                    prevP = p
                    out[#out + 1] = { price = p, qty = q }
                end
            end
        end
        if #out == 0 then return nil end
        if needsSort then
            table.sort(out, function(a, b) return a.price < b.price end)
        end
        return out
    end

    function H.medianPositive(vals)
        local n = #vals
        if n == 0 then return nil end
        table.sort(vals)
        if n % 2 == 1 then
            return vals[(n + 1) / 2]
        end
        local mid = n / 2
        return (vals[mid] + vals[mid + 1]) / 2
    end

    function H.getDirectCost(rid, legacy, evalScratch)
        local dKey = tostring(legacy.bartering) .. "|" .. (legacy.honored and "1" or "0")
        local dMap = evalScratch.directCache
        if not dMap then
            dMap = {}
            evalScratch.directCache = dMap
        end
        local bucket = dMap[dKey]
        if not bucket then
            bucket = {}
            dMap[dKey] = bucket
        end
        local hit = bucket[rid]
        if hit ~= nil then return hit end

        local staticV = ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[rid] or nil
        local vBuy = ns.GetVendorBuyPrice and ns.GetVendorBuyPrice(rid, staticV, false, legacy.bartering, legacy.honored) or nil
        if not numeric(vBuy) or vBuy <= 0 then vBuy = nil end

        local ahUnit, ahSrc = nil, nil
        if ns.GetItemMarketPrice then
            ahUnit, ahSrc = ns.GetItemMarketPrice(rid)
        end
        if not numeric(ahUnit) or ahUnit <= 0 then ahUnit = nil end

        local res
        if vBuy and (not ahUnit or vBuy <= ahUnit) then
            res = { unit = vBuy, isVendor = true, src = "Vendor", vendorUnit = vBuy }
        else
            res = { unit = ahUnit, isVendor = false, src = ahSrc, vendorUnit = vBuy }
        end
        bucket[rid] = res
        return res
    end

    function H.shouldAutoSub(craftOpt, subCraftMode)
        if not craftOpt then return false end
        local rec = craftOpt.recipe
        if (tonumber(rec and rec.cd) or 0) >= 60 then return false end
        return subCraftMode == "all_sub" or subCraftMode == "always"
            or (subCraftMode == "smart" and (craftOpt.sameProf or craftOpt.playerCanCraft))
    end

    function H.addLeaf(leafMap, id, name, qty, unitCost, isVendor, source, vendorUnit)
        local vUnit = (numeric(vendorUnit) and vendorUnit > 0) and vendorUnit or (isVendor and unitCost or nil)
        local existing = leafMap[id]
        if existing then
            existing.qty = existing.qty + qty
            if vUnit and not existing.vendorUnit then existing.vendorUnit = vUnit end
        else
            leafMap[id] = {
                itemID = id,
                name = name,
                qty = qty,
                unitCost = unitCost,
                isVendor = isVendor == true,
                source = source,
                vendorUnit = vUnit,
            }
        end
    end

    function H.applyVendorBackstop(lots, vendorUnit)
        local out = {}
        if type(lots) == "table" then
            for i = 1, #lots do
                local lt = lots[i]
                if lt and numeric(lt.price) and lt.price > 0 and lt.price < vendorUnit and lt.qty and lt.qty > 0 then
                    out[#out + 1] = { price = lt.price, qty = lt.qty, isVendor = lt.isVendor == true }
                end
            end
        end
        out[#out + 1] = { price = vendorUnit, qty = math.huge, isVendor = true }
        return out
    end

    function H.evalSubRecipe(rid, parentProf, profMap, legacy, subCraftMode, overrides, subBucket, visited, depth, evalScratch)
        if depth >= C.MAX_SUB_DEPTH then return nil, false, 0, nil, true end
        if visited[rid] then return nil, true, 0, nil, false end

        local list = ns.RECIPES_BY_OUTPUT and ns.RECIPES_BY_OUTPUT[rid]
        if type(list) ~= "table" or #list == 0 then return nil, false, 0, nil, false end

        local cacheKey = tostring(parentProf or "") .. ":" .. tostring(rid)
        local cached = subBucket[cacheKey]
        if cached == false then
            return nil, false, 0, nil, false
        elseif cached then
            if depth + cached.maxSubDepth <= C.MAX_SUB_DEPTH then
                local usable = true
                local cDeps = cached.deps
                if cDeps then
                    for i = 1, #cDeps do
                        if visited[cDeps[i]] then
                            usable = false
                            break
                        end
                    end
                end
                if usable then
                    return cached.opt, false, cached.maxSubDepth, cDeps, false
                end
            end
        end

        local subRec = (ns.SelectBestRecipeForItem and ns.SelectBestRecipeForItem(rid, parentProf, profMap, nil)) or list[1]
        if not subRec then
            subBucket[cacheKey] = false
            return nil, false, 0, nil, false
        end
        local subReagents = (ns.ResolveRecipeReagents and ns.ResolveRecipeReagents(subRec)) or subRec.reagents
        if type(subReagents) ~= "table" or #subReagents == 0 then
            subBucket[cacheKey] = false
            return nil, false, 0, nil, false
        end

        local sameProf, playerCanCraft = false, false
        if ns.GetRecipeCraftEligibility then
            sameProf, playerCanCraft = ns.GetRecipeCraftEligibility(subRec, profMap, parentProf, nil)
        else
            sameProf = (subRec.anyChar == true) or (subRec.prof == parentProf)
            local sk = profMap and profMap[subRec.prof]
            playerCanCraft = (subRec.anyChar == true) or (numeric(sk) and sk >= (subRec.skill or 1))
                or (ns.IsRecipeKnown and ns.IsRecipeKnown(subRec)) or false
        end

        local pObj = ns.PROF_BY_KEY and ns.PROF_BY_KEY[subRec.prof]
        local profLabel = ((pObj and pObj.label) or tostring(subRec.prof or "")) .. " " .. tostring(subRec.skill or 1)
        local optStub = {
            recipe = subRec,
            prof = subRec.prof,
            profLabel = profLabel,
            sameProf = sameProf,
            playerCanCraft = playerCanCraft,
        }
        local override = overrides and overrides[rid]
        if override == "buy" or (override ~= "craft" and not H.shouldAutoSub(optStub, subCraftMode)) then
            subBucket[cacheKey] = false
            return nil, false, 0, nil, false
        end

        visited[rid] = true
        local totalCost, _, subLeaves, hitCycle, childMaxDepth, childDeps, hitDepthLimit =
            H.evalReagentList(subReagents, subRec.prof, profMap, legacy, subCraftMode, overrides, subBucket, visited, depth + 1, evalScratch)
        visited[rid] = nil

        if not totalCost then
            if not hitCycle and not hitDepthLimit then
                subBucket[cacheKey] = false
            end
            return nil, hitCycle, 1 + (childMaxDepth or 0), childDeps, hitDepthLimit
        end

        local subNumMade = (numeric(subRec.numMade) and subRec.numMade > 0) and subRec.numMade or 1
        local subProc = (subRec.prof == "cooking") and (0.10 * legacy.masterChef) or 0
        local subEffYield = subNumMade * (1 + subProc)
        local subUnit = totalCost / subEffYield

        optStub.numMade = subNumMade
        optStub.effYield = subEffYield
        optStub.unitCraftCost = subUnit
        optStub.leaves = subLeaves

        local maxSubDepth = 1 + (childMaxDepth or 0)
        if not hitCycle and not hitDepthLimit then
            subBucket[cacheKey] = {
                opt = optStub,
                maxSubDepth = maxSubDepth,
                deps = childDeps,
            }
        end
        return optStub, hitCycle, maxSubDepth, childDeps, hitDepthLimit
    end

    function H.evalReagentList(reagents, parentProf, profMap, legacy, subCraftMode, overrides, subBucket, visited, depth, evalScratch)
        local totalCost = 0
        local breakdown = {}
        local leafReagents = {}
        local hitCycle = false
        local hitDepthLimit = false
        local maxSubDepth = 0
        local deps, depsSeen = nil, nil

        for i = 1, #reagents do
            local pair = reagents[i]
            if type(pair) ~= "table" then return nil, nil, nil, hitCycle, maxSubDepth, deps, hitDepthLimit end
            local rid = pair[1] or pair.itemID or pair.id
            local rqty = pair[2] or pair.qty or pair.count
            if not numeric(rid) or rid <= 0 or not numeric(rqty) or rqty <= 0 then
                return nil, nil, nil, hitCycle, maxSubDepth, deps, hitDepthLimit
            end

            local direct = H.getDirectCost(rid, legacy, evalScratch)
            local override = overrides and overrides[rid]
            local allowSub = (not direct.isVendor)
                and ((subCraftMode ~= "buy" and subCraftMode ~= "buy_only") or override == "craft")
                and override ~= "buy"

            local craftOpt = nil
            if allowSub and ns.RECIPES_BY_OUTPUT and ns.RECIPES_BY_OUTPUT[rid] then
                local rCycle, rMaxDepth, rDeps, rDepthLimit
                craftOpt, rCycle, rMaxDepth, rDeps, rDepthLimit = H.evalSubRecipe(
                    rid, parentProf, profMap, legacy, subCraftMode, overrides, subBucket, visited, depth, evalScratch
                )
                if rCycle then hitCycle = true end
                if rDepthLimit then hitDepthLimit = true end
                if craftOpt then
                    if rMaxDepth > maxSubDepth then maxSubDepth = rMaxDepth end
                    if not deps then
                        deps = { rid }
                        depsSeen = { [rid] = true }
                    elseif not depsSeen[rid] then
                        depsSeen[rid] = true
                        deps[#deps + 1] = rid
                    end
                    if rDeps then
                        for j = 1, #rDeps do
                            local d = rDeps[j]
                            if not depsSeen[d] then
                                depsSeen[d] = true
                                deps[#deps + 1] = d
                            end
                        end
                    end
                end
            end

            local subUnit = craftOpt and craftOpt.unitCraftCost or nil
            local useSub = false
            if craftOpt and subUnit ~= nil then
                if ns.ShouldSubCraft then
                    useSub = ns.ShouldSubCraft(craftOpt, subCraftMode, override, direct.unit, subUnit) == true
                else
                    useSub = (override == "craft") or (H.shouldAutoSub(craftOpt, subCraftMode) and (direct.unit == nil or subUnit < direct.unit))
                end
            end

            local chosenUnit, chosenSrc, chosenIsVendor
            if useSub then
                chosenUnit = subUnit
                chosenSrc = "Craft (" .. craftOpt.profLabel .. ")"
                chosenIsVendor = false
                local scale = rqty / craftOpt.effYield
                for lid, leaf in pairs(craftOpt.leaves) do
                    H.addLeaf(leafReagents, lid, leaf.name, leaf.qty * scale, leaf.unitCost, leaf.isVendor, leaf.source, leaf.vendorUnit)
                end
            else
                if direct.unit == nil then
                    return nil, nil, nil, hitCycle, maxSubDepth, deps, hitDepthLimit
                end
                chosenUnit = direct.unit
                chosenIsVendor = direct.isVendor == true
                chosenSrc = direct.src or (chosenIsVendor and "Vendor" or "AH")
                H.addLeaf(leafReagents, rid, H.itemName(rid), rqty, chosenUnit, chosenIsVendor, chosenSrc, direct.vendorUnit)
            end

            local lineCost = chosenUnit * rqty
            totalCost = totalCost + lineCost
            breakdown[#breakdown + 1] = {
                itemID = rid,
                name = H.itemName(rid),
                qty = rqty,
                unitCost = chosenUnit,
                lineCost = lineCost,
                source = chosenSrc,
                isVendor = chosenIsVendor,
                makeMyself = useSub,
                directUnitCost = direct.unit,
                craftUnitCost = subUnit,
            }
        end

        return totalCost, breakdown, leafReagents, hitCycle, maxSubDepth, deps, hitDepthLimit
    end

    function H.getMoatItemMarket(itemID, econKey, evalScratch)
        local eKey = econKey or "_default"
        local cache = evalScratch.moatItemCache
        if not cache then
            cache = {}
            evalScratch.moatItemCache = cache
        end
        local byEcon = cache[eKey]
        if not byEcon then
            byEcon = {}
            cache[eKey] = byEcon
        end
        local hit = byEcon[itemID]
        if hit then return hit end

        local lots, depthSource = nil, "none"
        if ns.GetSavedItemLots then
            local saved = ns.GetSavedItemLots(itemID, econKey)
            local clean = H.sanitizeLots(saved)
            if clean then
                lots = clean
                depthSource = "live_lots"
            end
        end
        if not lots and ns.Pricing and type(ns.Pricing.GetItemSnapshotDepth) == "function" then
            local snap = ns.Pricing.GetItemSnapshotDepth(itemID, econKey)
            local clean = H.sanitizeLots(snap)
            if clean then
                lots = clean
                depthSource = "snapshot_depth"
            end
        end
        local listed = nil
        if not lots and ns.GetNumListed then
            local nListed = ns.GetNumListed(itemID)
            if numeric(nListed) and nListed > 0 then
                listed = nListed
            end
        end

        local heat = nil
        if ns.Pricing and type(ns.Pricing.GetItemHeatStrip24h) == "function" then
            local ok, h = pcall(ns.Pricing.GetItemHeatStrip24h, itemID, econKey)
            if ok and type(h) == "table" and readable(h) then heat = h end
        end

        local trend7dMedian = nil
        if ns.MarketScan and type(ns.MarketScan.GetItemTrend7d) == "function" then
            local ok, t7 = pcall(ns.MarketScan.GetItemTrend7d, itemID, econKey)
            if ok and type(t7) == "table" and type(t7.points) == "table" then
                local vals = {}
                for i = 1, #t7.points do
                    local pt = t7.points[i]
                    if type(pt) == "table" then
                        local p = numeric(pt.price) and pt.price > 0 and pt.price
                            or (numeric(pt.observedPrice) and pt.observedPrice > 0 and pt.observedPrice)
                            or nil
                        if p then vals[#vals + 1] = p end
                    end
                end
                trend7dMedian = H.medianPositive(vals)
            end
        end

        local baselineUnit = (heat and numeric(heat.medianPrice) and heat.medianPrice > 0 and heat.medianPrice)
            or trend7dMedian
            or nil

        local rec = {
            lots = lots,
            depthSource = depthSource,
            listed = listed,
            heat = heat,
            baselineUnit = baselineUnit,
        }
        byEcon[itemID] = rec
        return rec
    end

    function H.pickPriceWallBottleneck(leaves, leafCosts, details)
        local bestIdx = 1
        local bestDelta = -math.huge
        local bestCost = -math.huge
        for i = 1, #leaves do
            local r = leaves[i]
            local curC = leafCosts[i] or 0
            local delta = curC - (r.unitCost * r.qty)
            if delta > bestDelta + C.EPS or (math.abs(delta - bestDelta) <= C.EPS and curC > bestCost) then
                bestDelta = delta
                bestCost = curC
                bestIdx = i
            end
        end
        return details[bestIdx]
    end

    function VC.ResolveLegacy(opts)
        opts = (type(opts) == "table") and opts or {}
        local livePerks = ns.MP and type(ns.MP.DetectLegacyPerks) == "function" and ns.MP.DetectLegacyPerks() or nil

        local liveMasterChef = 0
        if type(livePerks) == "table" and numeric(livePerks.masterChef) then
            liveMasterChef = livePerks.masterChef
        end
        liveMasterChef = math.max(0, math.min(5, math.floor(liveMasterChef)))

        local liveBartering = 0
        if type(livePerks) == "table" and numeric(livePerks.bartering) and (livePerks.detected == true or livePerks.bartering > 0) then
            liveBartering = livePerks.bartering
        elseif ns.GetBarteringRank then
            local b = ns.GetBarteringRank()
            if numeric(b) then liveBartering = b end
        elseif type(livePerks) == "table" and numeric(livePerks.bartering) then
            liveBartering = livePerks.bartering
        end
        liveBartering = math.max(0, math.min(2, math.floor(liveBartering)))

        local mcMode = opts.masterChefMode
        local masterChefAuto = (mcMode == nil or mcMode == "auto")
        local masterChef = liveMasterChef
        if not masterChefAuto then
            local n = tonumber(mcMode)
            if numeric(n) then
                masterChef = n
            else
                masterChefAuto = true
            end
        end
        masterChef = math.max(0, math.min(5, math.floor(masterChef)))

        local bMode = opts.barteringMode
        local barteringAuto = (bMode == nil or bMode == "auto")
        local bartering = liveBartering
        if not barteringAuto then
            local n = tonumber(bMode)
            if numeric(n) then
                bartering = n
            else
                barteringAuto = true
            end
        end
        bartering = math.max(0, math.min(2, math.floor(bartering)))

        local honored = (opts.honoredDiscount == true)
        local vendorMult = (1 - 0.05 * bartering) * (honored and 0.90 or 1.0)
        local cookingProcChance = 0.10 * masterChef

        return {
            masterChef = masterChef,
            liveMasterChef = liveMasterChef,
            masterChefAuto = masterChefAuto,
            bartering = bartering,
            liveBartering = liveBartering,
            barteringAuto = barteringAuto,
            honored = honored,
            vendorMult = vendorMult,
            cookingProcChance = cookingProcChance,
        }
    end

    function H.countProfitableCrafts(ahLeaves, leafLots, fixedVendorCost, targetPayout, maxCrafts)
        if not numeric(targetPayout) or targetPayout <= fixedVendorCost then return 0 end
        local nLeaves = #ahLeaves
        local lotIdx = {}
        local rem = {}
        for i = 1, nLeaves do
            lotIdx[i] = 1
            rem[i] = leafLots[i][1] and leafLots[i][1].qty or 0
        end

        local crafts = 0
        local nextIdx = {}
        local nextRem = {}
        while crafts < maxCrafts do
            local kFull = maxCrafts - crafts
            for i = 1, nLeaves do
                local lots = leafLots[i]
                if lotIdx[i] > #lots or rem[i] <= C.EPS then
                    return crafts
                end
                local canDo = (rem[i] == math.huge) and (maxCrafts - crafts) or math.floor((rem[i] + C.EPS) / ahLeaves[i].qty)
                if canDo < kFull then kFull = canDo end
            end

            if kFull >= 1 then
                local marginalCost = fixedVendorCost
                for i = 1, nLeaves do
                    marginalCost = marginalCost + (leafLots[i][lotIdx[i]].price * ahLeaves[i].qty)
                end
                if targetPayout - marginalCost <= 0 then
                    return crafts
                end
                crafts = crafts + kFull
                for i = 1, nLeaves do
                    if rem[i] ~= math.huge then
                        local lots = leafLots[i]
                        local left = rem[i] - (kFull * ahLeaves[i].qty)
                        local idx = lotIdx[i]
                        while left <= C.EPS and idx <= #lots do
                            idx = idx + 1
                            left = (idx <= #lots) and lots[idx].qty or 0
                        end
                        lotIdx[i] = idx
                        rem[i] = left
                    end
                end
            else
                local singleCost = fixedVendorCost
                for i = 1, nLeaves do
                    local lots = leafLots[i]
                    local need = ahLeaves[i].qty
                    local idx = lotIdx[i]
                    local avail = rem[i]
                    local lc = 0
                    while need > C.EPS do
                        if idx > #lots or avail <= C.EPS then
                            return crafts
                        end
                        local take = (avail == math.huge or need < avail) and need or avail
                        lc = lc + (take * lots[idx].price)
                        need = need - take
                        if avail ~= math.huge then
                            avail = avail - take
                            if avail <= C.EPS then
                                idx = idx + 1
                                avail = (idx <= #lots) and lots[idx].qty or 0
                            end
                        end
                    end
                    nextIdx[i] = idx
                    nextRem[i] = avail
                    singleCost = singleCost + lc
                end
                if targetPayout - singleCost <= 0 then
                    return crafts
                end
                crafts = crafts + 1
                for i = 1, nLeaves do
                    lotIdx[i] = nextIdx[i]
                    rem[i] = nextRem[i]
                end
            end
        end
        return crafts
    end

    function VC.EvaluateBuyMoat(leafReagents, craftCost, avgVendor, econKey, evalScratch, minVendor)
        evalScratch = evalScratch or {}
        if econKey == nil then
            econKey = H.resolveEconKey(nil)
        end
        if not numeric(craftCost) or not numeric(avgVendor) or avgVendor <= 0 then
            return {
                tier = "unknown",
                label = "n/a",
                short = "n/a",
                badgeKind = "neutral",
                score = -1,
                profitableCrafts = nil,
                atCurrentPriceCrafts = nil,
                totalProfitCap = nil,
                totalSpendCap = nil,
                avgSpendPerCraft = numeric(craftCost) and craftCost or nil,
                lastProfitableCraftCost = nil,
                stopWallCraftCost = nil,
                safeProfitCrafts = nil,
                isAllVendor = false,
                stability = "unknown",
                depthSource = "none",
                reason = not numeric(craftCost) and "Craft cost unavailable" or "Output value unavailable",
                reagents = {},
            }
        end

        local fixedVendorCost = 0
        local pureVendorCost = 0
        local allVendorBacked = true
        local ahLeaves = {}
        for k, entry in pairs(leafReagents or {}) do
            if type(entry) == "table" and numeric(entry.qty) and entry.qty > 0 and numeric(entry.unitCost) then
                if entry.isVendor then
                    fixedVendorCost = fixedVendorCost + (entry.unitCost * entry.qty)
                    pureVendorCost = pureVendorCost + (entry.unitCost * entry.qty)
                else
                    local id = numeric(entry.itemID) and entry.itemID or (numeric(k) and k or nil)
                    if id then
                        local vUnit = (numeric(entry.vendorUnit) and entry.vendorUnit > 0) and entry.vendorUnit or nil
                        if vUnit then
                            pureVendorCost = pureVendorCost + (vUnit * entry.qty)
                        else
                            allVendorBacked = false
                        end
                        ahLeaves[#ahLeaves + 1] = {
                            itemID = id,
                            name = entry.name or H.itemName(id),
                            qty = entry.qty,
                            unitCost = entry.unitCost,
                            source = entry.source,
                            vendorUnit = vUnit,
                        }
                    end
                end
            end
        end

        if #ahLeaves == 0 and craftCost >= avgVendor then
            return {
                tier = "unknown",
                label = "0x (Loss)",
                short = "0x",
                badgeKind = "neutral",
                score = 0,
                profitableCrafts = 0,
                atCurrentPriceCrafts = 0,
                totalProfitCap = 0,
                totalSpendCap = 0,
                avgSpendPerCraft = craftCost,
                lastProfitableCraftCost = nil,
                stopWallCraftCost = craftCost,
                safeProfitCrafts = 0,
                isAllVendor = true,
                stability = "unknown",
                depthSource = "vendor",
                reason = "NPC vendor reagent cost exceeds payout",
                reagents = {},
            }
        end

        if #ahLeaves == 0 or (allVendorBacked and pureVendorCost < avgVendor) then
            local effVendorCost = (#ahLeaves == 0) and craftCost or pureVendorCost
            local safeCrafts = math.huge
            if numeric(minVendor) and minVendor < avgVendor then
                safeCrafts = (minVendor > effVendorCost) and math.huge or 0
            end
            local infReagents = {}
            if #ahLeaves > 0 then
                table.sort(ahLeaves, function(a, b) return a.itemID < b.itemID end)
                for i = 1, #ahLeaves do
                    local r = ahLeaves[i]
                    infReagents[i] = {
                        itemID = r.itemID,
                        name = r.name,
                        qty = r.qty,
                        unitCost = r.unitCost,
                        vendorUnit = r.vendorUnit,
                        hasVendorBackstop = true,
                        breakEvenPrice = math.floor((avgVendor - (craftCost - r.unitCost * r.qty)) / r.qty),
                        totalAvailableQty = math.huge,
                        atCurrentPriceCrafts = math.huge,
                        depthSource = "vendor_backstop",
                        minLotPrice = r.unitCost,
                        maxBuyQty = math.huge,
                        maxProfitableUnitPrice = r.vendorUnit,
                        wallUnitPrice = nil,
                        avgBuyUnitPrice = r.vendorUnit,
                    }
                end
            end
            return {
                tier = "infinite",
                label = "Infinite",
                short = "Infinite",
                badgeKind = "pos",
                score = 1000000000,
                profitableCrafts = math.huge,
                atCurrentPriceCrafts = math.huge,
                totalProfitCap = math.huge,
                totalSpendCap = math.huge,
                avgSpendPerCraft = effVendorCost,
                lastProfitableCraftCost = effVendorCost,
                stopWallCraftCost = nil,
                safeProfitCrafts = safeCrafts,
                isAllVendor = true,
                stability = "infinite",
                depthSource = (#ahLeaves == 0) and "vendor" or "vendor_backstop",
                reason = (#ahLeaves == 0) and "All reagents sold by unlimited NPC vendors"
                    or "All reagents have unlimited NPC vendor backstop below payout",
                reagents = infReagents,
            }
        end

        table.sort(ahLeaves, function(a, b) return a.itemID < b.itemID end)

        local reagentDetails = {}
        local leafLots = {}
        local leafHeats = {}
        local allHaveDepth = true
        local allHaveHourly = true
        local hasBaseline = true
        local baselineCraftCost = fixedVendorCost
        local minAtCurrent = math.huge
        local aggDepthSource = "live_lots"

        for i = 1, #ahLeaves do
            local r = ahLeaves[i]
            local mkt = H.getMoatItemMarket(r.itemID, econKey, evalScratch)

            local lots = mkt.lots
            local depthSource = mkt.depthSource
            local hasDepth = (lots ~= nil and #lots > 0)
            if not hasDepth and mkt.listed and mkt.listed > 0 and r.unitCost > 0 then
                lots = { { price = r.unitCost, qty = mkt.listed } }
                depthSource = "listed"
                hasDepth = true
            end
            if r.vendorUnit then
                lots = H.applyVendorBackstop(lots, r.vendorUnit)
                hasDepth = true
                if depthSource == "none" then
                    depthSource = "vendor_backstop"
                end
            end
            if not hasDepth then
                allHaveDepth = false
                depthSource = "none"
            elseif C.DEPTH_RANK[depthSource] < C.DEPTH_RANK[aggDepthSource] then
                aggDepthSource = depthSource
            end

            local breakEvenPrice = math.floor((avgVendor - (craftCost - r.unitCost * r.qty)) / r.qty)
            local totalAvail = 0
            local atCurCrafts = nil
            if hasDepth then
                local curThresh = math.max(r.unitCost + 1, math.floor(r.unitCost * 1.05 + 0.5))
                local sumCur = 0
                for j = 1, #lots do
                    local lt = lots[j]
                    if lt.qty == math.huge then
                        totalAvail = math.huge
                    elseif totalAvail ~= math.huge then
                        totalAvail = totalAvail + lt.qty
                    end
                    if lt.price <= curThresh then
                        if lt.qty == math.huge then
                            sumCur = math.huge
                        elseif sumCur ~= math.huge then
                            sumCur = sumCur + lt.qty
                        end
                    end
                end
                atCurCrafts = (sumCur == math.huge) and math.huge or math.floor(sumCur / r.qty)
                if atCurCrafts < minAtCurrent then minAtCurrent = atCurCrafts end
            end

            if mkt.baselineUnit and mkt.baselineUnit > 0 then
                local effBase = r.vendorUnit and math.min(mkt.baselineUnit, r.vendorUnit) or mkt.baselineUnit
                baselineCraftCost = baselineCraftCost + (effBase * r.qty)
            elseif r.vendorUnit then
                baselineCraftCost = baselineCraftCost + (r.vendorUnit * r.qty)
            else
                hasBaseline = false
            end

            if mkt.heat and type(mkt.heat.hourly) == "table" then
                leafHeats[i] = mkt.heat.hourly
            else
                allHaveHourly = false
            end

            leafLots[i] = lots
            reagentDetails[i] = {
                itemID = r.itemID,
                name = r.name,
                qty = r.qty,
                unitCost = r.unitCost,
                vendorUnit = r.vendorUnit,
                hasVendorBackstop = (r.vendorUnit ~= nil),
                breakEvenPrice = breakEvenPrice,
                totalAvailableQty = hasDepth and totalAvail or nil,
                atCurrentPriceCrafts = atCurCrafts,
                baselineUnit = mkt.baselineUnit or r.vendorUnit,
                depthSource = depthSource,
                minLotPrice = (hasDepth and lots[1]) and lots[1].price or nil,
                maxBuyQty = nil,
                maxProfitableUnitPrice = nil,
                wallUnitPrice = nil,
                avgBuyUnitPrice = nil,
            }
        end

        if not hasBaseline then baselineCraftCost = nil end
        local isFlashDip = (hasBaseline and baselineCraftCost >= avgVendor and craftCost < baselineCraftCost * 0.88) and true or false

        local observedHours24h, profitableHours24h = nil, nil
        if allHaveHourly then
            observedHours24h, profitableHours24h = 0, 0
            for hr = 0, 23 do
                local okHour = true
                local hrCost = fixedVendorCost
                for i = 1, #ahLeaves do
                    local p = leafHeats[i][hr]
                    if numeric(p) and p > 0 then
                        hrCost = hrCost + p * ahLeaves[i].qty
                    else
                        okHour = false
                        break
                    end
                end
                if okHour then
                    observedHours24h = observedHours24h + 1
                    if hrCost < avgVendor then
                        profitableHours24h = profitableHours24h + 1
                    end
                end
            end
        end

        local isSustained = false
        if not isFlashDip then
            if observedHours24h and observedHours24h >= 4 then
                isSustained = (profitableHours24h / observedHours24h) >= 0.75
            elseif hasBaseline and baselineCraftCost < avgVendor then
                isSustained = true
            end
        end

        if not allHaveDepth then
            return {
                tier = "unknown",
                label = "n/a",
                short = "n/a",
                badgeKind = "neutral",
                score = -1,
                profitableCrafts = nil,
                atCurrentPriceCrafts = nil,
                totalProfitCap = nil,
                totalSpendCap = nil,
                avgSpendPerCraft = craftCost,
                lastProfitableCraftCost = nil,
                stopWallCraftCost = nil,
                safeProfitCrafts = nil,
                isAllVendor = false,
                isFlashDip = isFlashDip,
                isSustained = isSustained,
                profitableHours24h = profitableHours24h,
                observedHours24h = observedHours24h,
                baselineCraftCost = baselineCraftCost,
                stability = isFlashDip and "flash_dip" or "unknown",
                depthSource = "none",
                reason = "AH lot depth unavailable",
                reagents = reagentDetails,
            }
        end

        -- O(lots) multi-reagent profitable depth walk capped at MAX_SIM_CRAFTS
        local nLeaves = #ahLeaves
        local lotIdx = {}
        local rem = {}
        local reagentSpend = {}
        local reagentMaxUnit = {}
        local reagentWallUnit = {}
        for i = 1, nLeaves do
            lotIdx[i] = 1
            rem[i] = leafLots[i][1] and leafLots[i][1].qty or 0
            reagentSpend[i] = 0
        end

        local profitableCrafts = 0
        local totalProfitCap = 0
        local totalSpendCap = 0
        local lastProfitableCraftCost = nil
        local stopWallCraftCost = nil
        local bottleneck = nil
        local bottleneckReason = nil
        local stepCosts = {}
        local stepMaxUnit = {}
        local nextIdx = {}
        local nextRem = {}

        while profitableCrafts < C.MAX_SIM_CRAFTS do
            local kFull = C.MAX_SIM_CRAFTS - profitableCrafts
            local supplyOutIdx = nil
            for i = 1, nLeaves do
                local lots = leafLots[i]
                if lotIdx[i] > #lots or rem[i] <= C.EPS then
                    supplyOutIdx = i
                    break
                end
                local canDo = (rem[i] == math.huge) and (C.MAX_SIM_CRAFTS - profitableCrafts) or math.floor((rem[i] + C.EPS) / ahLeaves[i].qty)
                if canDo < kFull then kFull = canDo end
            end

            if supplyOutIdx then
                bottleneck = reagentDetails[supplyOutIdx]
                bottleneckReason = "supply"
                break
            end

            if kFull >= 1 then
                local marginalCost = fixedVendorCost
                for i = 1, nLeaves do
                    local p = leafLots[i][lotIdx[i]].price
                    local c = p * ahLeaves[i].qty
                    stepCosts[i] = c
                    stepMaxUnit[i] = p
                    marginalCost = marginalCost + c
                end
                local marginalProfit = avgVendor - marginalCost
                if marginalProfit <= 0 then
                    stopWallCraftCost = marginalCost
                    for i = 1, nLeaves do reagentWallUnit[i] = stepMaxUnit[i] end
                    bottleneck = H.pickPriceWallBottleneck(ahLeaves, stepCosts, reagentDetails)
                    bottleneckReason = "price_wall"
                    break
                end
                profitableCrafts = profitableCrafts + kFull
                totalProfitCap = totalProfitCap + (kFull * marginalProfit)
                totalSpendCap = totalSpendCap + (kFull * marginalCost)
                lastProfitableCraftCost = marginalCost
                for i = 1, nLeaves do
                    local lots = leafLots[i]
                    local p = stepMaxUnit[i]
                    reagentSpend[i] = reagentSpend[i] + (kFull * stepCosts[i])
                    if reagentMaxUnit[i] == nil or p > reagentMaxUnit[i] then
                        reagentMaxUnit[i] = p
                    end
                    if rem[i] ~= math.huge then
                        local left = rem[i] - (kFull * ahLeaves[i].qty)
                        local idx = lotIdx[i]
                        while left <= C.EPS and idx <= #lots do
                            idx = idx + 1
                            left = (idx <= #lots) and lots[idx].qty or 0
                        end
                        lotIdx[i] = idx
                        rem[i] = left
                    end
                end
            else
                -- Straddling lot boundary: simulate exactly 1 craft across lots
                local singleCost = fixedVendorCost
                local outOfSupply = nil
                for i = 1, nLeaves do
                    local lots = leafLots[i]
                    local need = ahLeaves[i].qty
                    local idx = lotIdx[i]
                    local avail = rem[i]
                    local lc = 0
                    local maxP = nil
                    while need > C.EPS do
                        if idx > #lots or avail <= C.EPS then
                            outOfSupply = i
                            break
                        end
                        local p = lots[idx].price
                        local take = (avail == math.huge or need < avail) and need or avail
                        lc = lc + (take * p)
                        if maxP == nil or p > maxP then maxP = p end
                        need = need - take
                        if avail ~= math.huge then
                            avail = avail - take
                            if avail <= C.EPS then
                                idx = idx + 1
                                avail = (idx <= #lots) and lots[idx].qty or 0
                            end
                        end
                    end
                    if outOfSupply then break end
                    stepCosts[i] = lc
                    stepMaxUnit[i] = maxP
                    nextIdx[i] = idx
                    nextRem[i] = avail
                    singleCost = singleCost + lc
                end
                if outOfSupply then
                    bottleneck = reagentDetails[outOfSupply]
                    bottleneckReason = "supply"
                    break
                end
                local singleProfit = avgVendor - singleCost
                if singleProfit <= 0 then
                    stopWallCraftCost = singleCost
                    for i = 1, nLeaves do reagentWallUnit[i] = stepMaxUnit[i] end
                    bottleneck = H.pickPriceWallBottleneck(ahLeaves, stepCosts, reagentDetails)
                    bottleneckReason = "price_wall"
                    break
                end
                profitableCrafts = profitableCrafts + 1
                totalProfitCap = totalProfitCap + singleProfit
                totalSpendCap = totalSpendCap + singleCost
                lastProfitableCraftCost = singleCost
                for i = 1, nLeaves do
                    reagentSpend[i] = reagentSpend[i] + stepCosts[i]
                    local p = stepMaxUnit[i]
                    if p and (reagentMaxUnit[i] == nil or p > reagentMaxUnit[i]) then
                        reagentMaxUnit[i] = p
                    end
                    lotIdx[i] = nextIdx[i]
                    rem[i] = nextRem[i]
                end
            end
        end

        local avgSpendPerCraft = (profitableCrafts > 0) and (totalSpendCap / profitableCrafts) or craftCost
        for i = 1, nLeaves do
            local rd = reagentDetails[i]
            local maxBuyQty = profitableCrafts * ahLeaves[i].qty
            rd.maxBuyQty = maxBuyQty
            rd.maxProfitableUnitPrice = reagentMaxUnit[i]
            rd.wallUnitPrice = (bottleneckReason == "price_wall") and reagentWallUnit[i] or nil
            rd.avgBuyUnitPrice = (maxBuyQty > 0) and (reagentSpend[i] / maxBuyQty) or nil
        end

        local safeProfitCrafts
        if numeric(minVendor) and minVendor < avgVendor then
            safeProfitCrafts = H.countProfitableCrafts(ahLeaves, leafLots, fixedVendorCost, minVendor, C.MAX_SIM_CRAFTS)
        else
            safeProfitCrafts = profitableCrafts
        end

        if minAtCurrent == math.huge then minAtCurrent = 0 end
        local capped = (profitableCrafts >= C.MAX_SIM_CRAFTS)
        local cappedSuffix = capped and "+" or ""
        local countTag = tostring(profitableCrafts) .. cappedSuffix .. "x"

        local tier, short, badgeKind, score, label
        if profitableCrafts < 5 or (isFlashDip and profitableCrafts < 25) then
            tier = "moment"
            short = "Moment (" .. countTag .. ")"
            label = isFlashDip and ("Moment (Flash Dip, " .. countTag .. ")") or short
            badgeKind = "hot"
            score = 10000 + profitableCrafts
        elseif (profitableCrafts >= 50 and minAtCurrent >= 25 and not isFlashDip) or (profitableCrafts >= 100 and isSustained) then
            tier = "deep"
            short = "Deep (" .. countTag .. ")"
            label = short
            badgeKind = "pos"
            score = 400000 + profitableCrafts
        elseif (profitableCrafts >= 15 and not isFlashDip) or profitableCrafts >= 50 then
            tier = "steady"
            short = "Steady (" .. countTag .. ")"
            label = short
            badgeKind = "blue"
            score = 200000 + profitableCrafts
        else
            tier = "thin"
            short = "Thin (" .. countTag .. ")"
            label = short
            badgeKind = "warn"
            score = 50000 + profitableCrafts
        end

        local stability
        if isFlashDip then
            stability = "flash_dip"
        elseif isSustained then
            stability = "sustained"
        elseif observedHours24h and observedHours24h > 0 then
            stability = "mixed"
        else
            stability = "unknown"
        end

        local reason
        if isFlashDip then
            reason = "Flash dip below baseline cost; " .. countTag .. " profitable crafts"
        elseif bottleneckReason == "price_wall" and bottleneck then
            reason = "Up to " .. countTag .. " crafts before " .. bottleneck.name .. " hits break-even price wall"
        elseif bottleneckReason == "supply" and bottleneck then
            reason = "Up to " .. countTag .. " crafts limited by AH supply of " .. bottleneck.name
        elseif capped then
            reason = "Over " .. tostring(C.MAX_SIM_CRAFTS) .. " profitable crafts available in AH depth"
        else
            reason = "Up to " .. countTag .. " profitable crafts available"
        end

        return {
            tier = tier,
            label = label,
            short = short,
            badgeKind = badgeKind,
            score = score,
            profitableCrafts = profitableCrafts,
            atCurrentPriceCrafts = minAtCurrent,
            totalProfitCap = totalProfitCap,
            totalSpendCap = totalSpendCap,
            avgSpendPerCraft = avgSpendPerCraft,
            lastProfitableCraftCost = lastProfitableCraftCost,
            stopWallCraftCost = stopWallCraftCost,
            safeProfitCrafts = safeProfitCrafts,
            capped = capped,
            isAllVendor = false,
            bottleneck = bottleneck,
            bottleneckReason = bottleneckReason,
            isFlashDip = isFlashDip,
            isSustained = isSustained,
            profitableHours24h = profitableHours24h,
            observedHours24h = observedHours24h,
            baselineCraftCost = baselineCraftCost,
            stability = stability,
            depthSource = aggDepthSource,
            reason = reason,
            reagents = reagentDetails,
        }
    end

    function H.resolveYield(recipe, context, legacy)
        local lo, hi
        if ns.ResolveRecipeYieldRange then
            lo, hi = ns.ResolveRecipeYieldRange(recipe)
        else
            local nm = (numeric(recipe.numMade) and recipe.numMade > 0) and recipe.numMade or 1
            lo, hi = nm, nm
        end
        local spellID = recipe.spellID
        local isCooking = (recipe.prof == "cooking")
        local store = ns.Analytics and ns.Analytics.Store
        local stats = (store and type(store.GetCraftYieldStats) == "function" and numeric(spellID) and spellID > 0)
            and store.GetCraftYieldStats(spellID) or nil
        if not isCooking and type(stats) == "table" then
            if numeric(stats.minSeen) and stats.minSeen > 0 then
                lo = math.min(lo, math.floor(stats.minSeen + 0.5))
            end
            if numeric(stats.maxSeen) and stats.maxSeen > 0 then
                hi = math.max(hi, math.floor(stats.maxSeen + 0.5))
            end
        end
        local isVariable = (hi > lo)
        local uniformAvg = (lo + hi) / 2
        local samples = (type(stats) == "table" and numeric(stats.casts)) and math.floor(stats.casts + 0.5) or 0
        local measuredAvg = (type(stats) == "table" and numeric(stats.avg) and stats.avg > 0) and stats.avg or nil

        local mode = (context and text(context.yieldMode)) or "auto"
        if mode ~= "uniform" and mode ~= "min" and mode ~= "measured" then
            mode = "auto"
        end
        local baseAvg, source
        if mode == "min" then
            baseAvg = lo
            source = "min"
        elseif mode == "uniform" then
            baseAvg = uniformAvg
            source = isVariable and "uniform" or "fixed"
        elseif mode == "measured" then
            if measuredAvg then
                baseAvg = measuredAvg
                source = "measured"
            else
                baseAvg = uniformAvg
                source = isVariable and "uniform" or "fixed"
            end
        else
            if measuredAvg and samples >= C.MIN_MEASURED_SAMPLES then
                baseAvg = measuredAvg
                source = "measured"
            else
                baseAvg = uniformAvg
                source = isVariable and "uniform" or "fixed"
            end
        end

        local procChance = isCooking and (0.10 * (legacy and legacy.masterChef or 0)) or 0
        local effAvg, minY, maxY
        if source == "measured" and isCooking then
            effAvg = baseAvg
            minY = lo
            maxY = math.max(hi, (procChance > 0) and (2 * hi) or hi)
        else
            effAvg = baseAvg * (1 + procChance)
            minY = lo
            maxY = (procChance > 0) and (2 * hi) or hi
        end

        return {
            min = minY,
            avg = effAvg,
            max = maxY,
            baseMin = lo,
            baseMax = hi,
            uniformAvg = uniformAvg,
            measuredAvg = measuredAvg,
            samples = samples,
            hist = (type(stats) == "table" and type(stats.hist) == "table") and stats.hist or nil,
            source = source,
            isVariable = isVariable,
        }
    end

    function VC.EvaluateRecipe(recipe, context, legacy, evalScratch)
        if type(recipe) ~= "table" or recipe.isEnchant then return nil end
        local outID = recipe.outputItemID
        if not numeric(outID) or outID <= 0 then return nil end

        local unitVendorSell = ns.GetVendorSellPrice and ns.GetVendorSellPrice(outID) or nil
        if not numeric(unitVendorSell) or unitVendorSell <= 0 then return nil end

        local reagents = (ns.ResolveRecipeReagents and ns.ResolveRecipeReagents(recipe)) or recipe.reagents
        if type(reagents) ~= "table" or #reagents == 0 then return nil end

        context = (type(context) == "table") and context or {}
        legacy = legacy or VC.ResolveLegacy(context)
        evalScratch = evalScratch or {}

        local numMade = (numeric(recipe.numMade) and recipe.numMade > 0) and recipe.numMade or 1
        local isCooking = (recipe.prof == "cooking")
        local procChance = isCooking and (0.10 * legacy.masterChef) or 0
        local y = H.resolveYield(recipe, context, legacy)
        local minVendor = y.min * unitVendorSell
        local avgVendor = y.avg * unitVendorSell
        local maxVendor = y.max * unitVendorSell

        local subCraftMode = context.subCraftMode or "smart"
        local overrides = context.subCraftOverrides
        local profMap = context.profMap or (ns.GetPlayerProfessions and ns.GetPlayerProfessions()) or nil

        local subKey = table.concat({
            tostring(legacy.bartering),
            legacy.honored and "1" or "0",
            tostring(legacy.masterChef),
            tostring(subCraftMode),
            H.serializeMap(overrides),
            H.serializeMap(profMap),
        }, "|")
        local subRoot = evalScratch.subCache
        if not subRoot then
            subRoot = {}
            evalScratch.subCache = subRoot
        end
        local subBucket = subRoot[subKey]
        if not subBucket then
            subBucket = {}
            subRoot[subKey] = subBucket
        end

        local visited = { [outID] = true }
        local craftCost, craftBreakdown, leafReagents = H.evalReagentList(
            reagents, recipe.prof, profMap, legacy, subCraftMode, overrides, subBucket, visited, 0, evalScratch
        )
        if not numeric(craftCost) then return nil end

        local minProfit = minVendor - craftCost
        local avgProfit = avgVendor - craftCost
        local maxProfit = maxVendor - craftCost
        if not numeric(avgProfit) or avgProfit <= 0 then return nil end

        local marginPct = (craftCost > 0) and ((avgProfit / craftCost) * 100) or 999

        local base = ns.RecipeStats and ns.RecipeStats.Get and ns.RecipeStats.Get(recipe, context) or {}
        local row = {}
        for i = 1, #C.COPY_FIELDS do
            local k = C.COPY_FIELDS[i]
            row[k] = base[k]
        end
        if row.recipe == nil then row.recipe = recipe end
        if row.spellID == nil then row.spellID = recipe.spellID end
        if row.outputItemID == nil then row.outputItemID = outID end
        if row.prof == nil then row.prof = recipe.prof end
        if row.requiredSkill == nil then row.requiredSkill = recipe.skill end
        if row.name == nil or row.name == "" then row.name = recipe.name or H.itemName(outID) end

        local econKey = H.resolveEconKey(context)
        local moat = VC.EvaluateBuyMoat(leafReagents, craftCost, avgVendor, econKey, evalScratch, minVendor)

        row.numMade = numMade
        row.minMade = y.baseMin
        row.maxMade = y.baseMax
        row.isCooking = isCooking
        row.procChance = procChance
        row.yieldMin = y.min
        row.yieldAvg = y.avg
        row.yieldMax = y.max
        row.yieldUniformAvg = y.uniformAvg
        row.yieldMeasuredAvg = y.measuredAvg
        row.yieldSamples = y.samples
        row.yieldHist = y.hist
        row.yieldSource = y.source
        row.isVariableYield = y.isVariable
        row.effYield = y.avg
        row.unitVendorSell = unitVendorSell
        row.minVendor = minVendor
        row.avgVendor = avgVendor
        row.maxVendor = maxVendor
        row.craftCost = craftCost
        row.minProfit = minProfit
        row.avgProfit = avgProfit
        row.maxProfit = maxProfit
        row.marginPct = marginPct
        row.craftBreakdown = craftBreakdown
        row.leafReagents = leafReagents
        row.legacy = legacy
        row.moat = moat
        row.moatScore = moat.score
        row.moatTier = moat.tier
        row.profitableCrafts = moat.profitableCrafts
        row.totalProfitCap = moat.totalProfitCap
        row.totalSpendCap = moat.totalSpendCap
        row.avgSpendPerCraft = moat.avgSpendPerCraft
        row.buyCeiling = moat.lastProfitableCraftCost
        row.stopWallCost = moat.stopWallCraftCost
        row.safeProfitCrafts = moat.safeProfitCrafts
        row.isAllVendor = moat.isAllVendor == true

        local buyCaps = {}
        for i = 1, #(moat.reagents or {}) do
            local rd = moat.reagents[i]
            if type(rd) == "table" and numeric(rd.itemID) and rd.itemID > 0 then
                buyCaps[rd.itemID] = {
                    maxBuyUnit = numeric(rd.maxProfitableUnitPrice) and rd.maxProfitableUnitPrice or rd.unitCost,
                    breakEvenUnit = numeric(rd.breakEvenPrice) and rd.breakEvenPrice or nil,
                    wallUnit = numeric(rd.wallUnitPrice) and rd.wallUnitPrice or nil,
                    avgBuyUnit = numeric(rd.avgBuyUnitPrice) and rd.avgBuyUnitPrice or nil,
                    minLotUnit = numeric(rd.minLotPrice) and rd.minLotPrice or nil,
                    maxBuyQty = rd.maxBuyQty,
                    source = "vendor_crafter",
                }
            end
        end
        row.reagentBuyCaps = next(buyCaps) ~= nil and buyCaps or nil

        return row
    end

    function H.effectiveCraftYieldVersion(store)
        if not store then return 0 end
        if store.craftYieldVersion ~= nil and (store._trackedAccountingVersion == nil or store.accountingVersion == store._trackedAccountingVersion) then
            return store.craftYieldVersion
        end
        return store.accountingVersion or store.version or 0
    end

    function H.serializeProfKeys(profMap)
        if type(profMap) ~= "table" or not readable(profMap) or next(profMap) == nil then return "" end
        local ks = {}
        for k, v in pairs(profMap) do
            if readable(k) and readable(v) and v ~= false then
                ks[#ks + 1] = tostring(k)
            end
        end
        table.sort(ks)
        return table.concat(ks, ",")
    end

    function H.buildSignature(context, legacy)
        local priceVer = (ns.GetEffectivePriceVersion and ns.GetEffectivePriceVersion()) or ns.priceCacheEpoch or 0
        local econ = H.resolveEconKey(context) or ""
        local profMap = context.profMap or (ns.GetPlayerProfessions and ns.GetPlayerProfessions()) or nil
        local store = ns.Analytics and ns.Analytics.Store
        local yieldVer = H.effectiveCraftYieldVersion(store)
        return table.concat({
            tostring(priceVer),
            econ,
            tostring(legacy.masterChef),
            tostring(legacy.bartering),
            legacy.honored and "1" or "0",
            tostring(context.yieldMode or "auto"),
            tostring(yieldVer),
            tostring(context.subCraftMode or "smart"),
            H.serializeMap(context.subCraftOverrides),
            (context.craftableAllChars == true) and "1" or "0",
            H.serializeProfKeys(profMap),
        }, "|")
    end

    function VC.ClearCache()
        buildCache = setmetatable({}, { __mode = "k" })
    end

    function VC.BuildPriorityOrder(catalog, priority)
        local state = { index = 1 }
        return applyPriority(state, catalog or {}, priority)
    end

    function VC.Reprioritize(state, priority)
        if not state or state.completed then return state and state.order end
        local catalog = state.catalog or (ns.RecipeStats and ns.RecipeStats.GetCatalog and ns.RecipeStats.GetCatalog()) or {}
        return applyPriority(state, catalog, priority)
    end

    function VC.Attach(state, background, priority, onProgress, onComplete, onTierReady)
        if not state or state.completed then return state end
        local prevOnTierReady = state.onTierReady
        state.background = background == true
        if onProgress ~= nil or background then state.onProgress = onProgress end
        if onComplete ~= nil then state.onComplete = onComplete end
        if onTierReady ~= nil or background then state.onTierReady = onTierReady end
        local catalog = state.catalog or (ns.RecipeStats and ns.RecipeStats.GetCatalog and ns.RecipeStats.GetCatalog()) or {}
        applyPriority(state, catalog, priority)
        if not state.background and state.onTierReady and not prevOnTierReady and state.tier1Authoritative and state.index > state.tier1Target then
            state.tier1Notified = false
        end
        return state
    end

    function VC.RepairItems(rows, context, legacy, evalScratch, itemIDs)
        if type(rows) ~= "table" or type(itemIDs) ~= "table" then return 0 end
        local expanded, queue = {}, {}
        local function enqueue(id)
            if numeric(id) and id > 0 and not expanded[id] then
                expanded[id] = true
                queue[#queue + 1] = id
            end
        end
        for k, v in pairs(itemIDs) do
            if type(v) == "number" then
                enqueue(v)
            elseif v ~= false and v ~= nil and type(k) == "number" then
                enqueue(k)
            end
        end
        if #queue == 0 then return 0 end

        context = (type(context) == "table") and context or {}
        legacy = legacy or VC.ResolveLegacy(context)
        evalScratch = (type(evalScratch) == "table") and evalScratch or {}
        local catalog = (ns.RecipeStats and ns.RecipeStats.GetCatalog and ns.RecipeStats.GetCatalog()) or {}

        local outputsByReagent = {}
        local function indexRecipeReagents(rec)
            if type(rec) ~= "table" then return end
            local outID = rec.outputItemID
            if not numeric(outID) or outID <= 0 then return end
            local reags = (ns.ResolveRecipeReagents and ns.ResolveRecipeReagents(rec)) or rec.reagents
            if type(reags) ~= "table" then return end
            for i = 1, #reags do
                local rg = reags[i]
                local rid = type(rg) == "table" and (rg[1] or rg.itemID or rg.id) or nil
                if numeric(rid) and rid > 0 then
                    local list = outputsByReagent[rid]
                    if not list then
                        list = {}
                        outputsByReagent[rid] = list
                    end
                    list[#list + 1] = outID
                end
            end
        end
        for i = 1, #catalog do
            indexRecipeReagents(catalog[i] and catalog[i].recipe)
        end
        if type(ns.RECIPES_BY_OUTPUT) == "table" then
            for _, list in pairs(ns.RECIPES_BY_OUTPUT) do
                if type(list) == "table" then
                    for i = 1, #list do indexRecipeReagents(list[i]) end
                end
            end
        end

        local head = 1
        while head <= #queue do
            local outs = outputsByReagent[queue[head]]
            if outs then
                for i = 1, #outs do enqueue(outs[i]) end
            end
            head = head + 1
        end

        if type(evalScratch.directCache) == "table" then
            for _, bucket in pairs(evalScratch.directCache) do
                if type(bucket) == "table" then
                    for id in pairs(expanded) do bucket[id] = nil end
                end
            end
        end
        if type(evalScratch.moatItemCache) == "table" then
            for _, byEcon in pairs(evalScratch.moatItemCache) do
                if type(byEcon) == "table" then
                    for id in pairs(expanded) do byEcon[id] = nil end
                end
            end
        end
        if type(evalScratch.subCache) == "table" then
            for _, subBucket in pairs(evalScratch.subCache) do
                if type(subBucket) == "table" then
                    for cacheKey, cached in pairs(subBucket) do
                        local rid = type(cacheKey) == "string" and tonumber(cacheKey:match(":(%d+)$")) or nil
                        local hit = (rid ~= nil and expanded[rid] == true)
                        if not hit and type(cached) == "table" and type(cached.deps) == "table" then
                            for j = 1, #cached.deps do
                                if expanded[cached.deps[j]] then
                                    hit = true
                                    break
                                end
                            end
                        end
                        if hit then subBucket[cacheKey] = nil end
                    end
                end
            end
        end

        local affectedEntries, affectedStubs = {}, {}
        for i = 1, #catalog do
            local entry = catalog[i]
            local rec = entry and entry.recipe
            if type(rec) == "table" then
                local hit = (rec.outputItemID and expanded[rec.outputItemID]) or (rec.recipeItemID and expanded[rec.recipeItemID])
                if not hit then
                    local reags = (ns.ResolveRecipeReagents and ns.ResolveRecipeReagents(rec)) or rec.reagents
                    if type(reags) == "table" then
                        for j = 1, #reags do
                            local rg = reags[j]
                            local rid = type(rg) == "table" and (rg[1] or rg.itemID or rg.id) or nil
                            if rid and expanded[rid] then
                                hit = true
                                break
                            end
                        end
                    end
                end
                if hit then
                    affectedEntries[#affectedEntries + 1] = entry
                    affectedStubs[#affectedStubs + 1] = { recipe = rec }
                end
            end
        end
        if #affectedEntries == 0 then return 0 end

        local stats = ns.RecipeStats
        if stats and stats.RepairItemsInPlace then
            pcall(stats.RepairItemsInPlace, affectedStubs, context, expanded)
        end

        local posByKey, posByRecipe = {}, {}
        for i = 1, #rows do
            local r = rows[i]
            if type(r) == "table" then
                if r.key ~= nil then posByKey[r.key] = i end
                if r.recipe ~= nil then posByRecipe[r.recipe] = i end
            end
        end

        local changedCount = 0
        local removed = {}
        local batchOpen = false
        if stats and stats.BeginBatch then
            batchOpen = true
            stats.BeginBatch(context)
        end
        local ok, err = pcall(function()
            for i = 1, #affectedEntries do
                local entry = affectedEntries[i]
                local rec = entry.recipe
                local newRow = VC.EvaluateRecipe(rec, context, legacy, evalScratch)
                local existingPos = (entry.key ~= nil and posByKey[entry.key])
                    or (newRow and newRow.key ~= nil and posByKey[newRow.key])
                    or posByRecipe[rec]
                if newRow then
                    if existingPos then
                        rows[existingPos] = newRow
                        removed[existingPos] = nil
                    else
                        local nextPos = #rows + 1
                        rows[nextPos] = newRow
                        if newRow.key ~= nil then posByKey[newRow.key] = nextPos end
                        if entry.key ~= nil then posByKey[entry.key] = nextPos end
                        posByRecipe[rec] = nextPos
                    end
                    changedCount = changedCount + 1
                elseif existingPos then
                    removed[existingPos] = true
                    changedCount = changedCount + 1
                end
            end
        end)
        if batchOpen and stats and stats.EndBatch then
            pcall(stats.EndBatch)
        end
        if not ok then
            if ns.ResetEval then ns.ResetEval() end
            error(err, 0)
        end

        if next(removed) ~= nil then
            local writeIdx = 0
            for readIdx = 1, #rows do
                if not removed[readIdx] then
                    writeIdx = writeIdx + 1
                    if writeIdx ~= readIdx then rows[writeIdx] = rows[readIdx] end
                end
            end
            for clearIdx = writeIdx + 1, #rows do rows[clearIdx] = nil end
        end

        return changedCount
    end

    function VC.Start(context, onProgress, onComplete, resumeState, onTierReady)
        context = (type(context) == "table") and context or {}
        local catalog = ns.RecipeStats and ns.RecipeStats.GetCatalog and ns.RecipeStats.GetCatalog() or {}
        local legacy = VC.ResolveLegacy(context)
        local sig = H.buildSignature(context, legacy)
        local datasetKey = (context.dataset ~= nil) and context.dataset or C.DEFAULT_DATASET

        local dsBucket = buildCache[datasetKey]
        if not dsBucket then
            dsBucket = {}
            buildCache[datasetKey] = dsBucket
        end

        local state = nil
        if type(resumeState) == "table" and resumeState.signature == sig and resumeState.catalog == catalog and resumeState.dataset == datasetKey then
            state = resumeState
        elseif dsBucket[sig] and dsBucket[sig].catalog == catalog then
            state = dsBucket[sig]
        end

        if not state then
            if type(resumeState) == "table" and resumeState.cancel then
                resumeState.cancel()
            end
            state = {
                dataset = datasetKey,
                signature = sig,
                catalog = catalog,
                legacy = legacy,
                rows = {},
                evalScratch = {},
                index = 1,
                scanned = 0,
                total = #catalog,
                generation = 0,
                running = false,
                completed = false,
            }
            dsBucket[sig] = state
        end

        local prevOnTierReady = state.onTierReady
        state.onProgress = onProgress
        state.onComplete = onComplete
        state.onTierReady = onTierReady
        state.background = context.background == true
        applyPriority(state, catalog, context.priority)
        if not state.background and state.onTierReady and not prevOnTierReady and state.tier1Authoritative and state.index > state.tier1Target then
            state.tier1Notified = false
        end

        if state.completed then
            if onComplete then onComplete(state.rows) end
            return function() end, state
        end
        if state.running then
            return state.cancel or function() end, state
        end

        state.generation = state.generation + 1
        local token = state.generation
        state.running = true

        local function isCurrent()
            return state.running and state.generation == token
        end
        local function cancel()
            if state.generation == token then
                state.running = false
                state.cancel = nil
                state.generation = token + 1
            end
        end
        state.cancel = cancel

        local defer = context.defer == false and nil or (context.defer or (C_Timer and C_Timer.After and function(fn) C_Timer.After(0, fn) end))
        local stats = ns.RecipeStats
        local total = #catalog
        state.total = total

        local step
        local batchOpen = false
        local stepping, stepAgain = false, false

        local function runStep()
            if not isCurrent() then return end
            if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index > state.tier1Target then
                state.tier1Notified = true
                state.onTierReady(state.rows, state.scanned, total)
                if not isCurrent() then return end
            end
            if state.index <= total then
                local started = clockMS()
                local maxBatch = state.background and 16 or C.MAX_BATCH
                local budgetMS = state.background and 1.2 or C.BUDGET_MS
                if stats and stats.BeginBatch then
                    batchOpen = true
                    stats.BeginBatch(context)
                end
                local count = 0
                repeat
                    if state.index > total then break end
                    local entry = catalog[state.order[state.index]]
                    local rec = entry and entry.recipe
                    if rec then
                        local row = VC.EvaluateRecipe(rec, context, state.legacy, state.evalScratch)
                        if row then
                            state.rows[#state.rows + 1] = row
                        end
                    end
                    state.index = state.index + 1
                    state.scanned = state.index - 1
                    count = count + 1
                    if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index > state.tier1Target then break end
                until count >= maxBatch or (clockMS() - started) >= budgetMS

                if batchOpen and stats and stats.EndBatch then
                    stats.EndBatch()
                end
                batchOpen = false
                if not isCurrent() then return end
                if state.onProgress then
                    state.onProgress(state.rows, state.scanned, total)
                end
                if not isCurrent() then return end
            end

            if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index > state.tier1Target then
                state.tier1Notified = true
                if state.index <= total then
                    state.onTierReady(state.rows, state.scanned, total)
                    if not isCurrent() then return end
                end
            end

            if state.index > total then
                state.running = false
                state.cancel = nil
                state.completed = true
                if state.onComplete then
                    state.onComplete(state.rows)
                end
            elseif defer then
                defer(step)
            end
        end

        step = function()
            if stepping then
                stepAgain = true
                return
            end
            stepping = true
            repeat
                stepAgain = false
                local ok, err = pcall(runStep)
                if not ok then
                    stepping = false
                    if state.generation == token then
                        state.running = false
                        state.cancel = nil
                        state.completed = false
                        state.tier1Notified = false
                    end
                    if batchOpen and stats and stats.EndBatch then
                        pcall(stats.EndBatch)
                    end
                    batchOpen = false
                    if ns.ResetEval then ns.ResetEval() end
                    error(err, 0)
                end
            until not stepAgain
            stepping = false
        end

        if defer then
            defer(step)
        else
            repeat step() until not isCurrent()
        end
        return cancel, state
    end

    function H.moatMatches(row, moatFilter)
        if not moatFilter or moatFilter == "all" then return true end
        local tier = row.moatTier or (row.moat and row.moat.tier) or "unknown"
        if moatFilter == "deep" then
            return tier == "infinite" or tier == "deep"
        elseif moatFilter == "steady" then
            return tier == "infinite" or tier == "deep" or tier == "steady"
        elseif moatFilter == "moment" then
            return tier == "moment"
        elseif moatFilter == "vendor_loop" then
            return tier == "infinite"
        elseif moatFilter == "ah_only" then
            return tier ~= "infinite"
        end
        return tier == moatFilter
    end

    function H.rowMatches(row, f, needle, lo, hi)
        if type(row) ~= "table" then return false end
        if not numeric(row.avgProfit) or row.avgProfit <= 0 then return false end
        if not sourceMatchesValues(row.sourceBucket, row.isWrit, f.sources or f.recipeSources) then return false end
        if lo or hi then
            local skill = row.requiredSkill
            if not numeric(skill) or (lo and skill < lo) or (hi and skill > hi) then return false end
        end
        local prof = normalizeProfFilter(f.profFilter or f.prof)
        if prof == "mine_profs" then
            local rec = row.recipe
            if not ((rec and rec.anyChar) or (f.profMap and f.profMap[row.prof])) then return false end
        elseif prof == "others" then
            local rec = row.recipe
            if not (row.prof == "others" or (rec and ns.IsOtherExceptionRecipe and ns.IsOtherExceptionRecipe(rec))) then return false end
        elseif prof ~= "all" and row.prof ~= prof then
            return false
        end
        local known = f.known
        if known == nil and f.knownRecipesOnly then known = "known" end
        if (known == "known" or known == true) and not row.known then return false end
        if (known == "unknown" or known == false) and row.known then return false end
        if f.craftableFilter and f.craftableFilter ~= "all" and ns.MatchesCraftableFilter
            and not ns.MatchesCraftableFilter(row.craftAbility, f.craftableFilter) then
            return false
        end
        if f.unlockFilter and f.unlockFilter ~= "all" and ns.MatchesGlobalFilters
            and not ns.MatchesGlobalFilters(row.prof, row.unlock, "all", f.unlockFilter) then
            return false
        end
        if not H.moatMatches(row, f.moatFilter) then return false end
        if needle ~= "" then
            local blob = row._vcSearchBlob
            if not blob or row._vcSearchBlobName ~= row.name then
                local rec = row.recipe or {}
                local ability = row.craftAbility
                local moat = row.moat
                local parts = {
                    text(row.name),
                    (row.outputItemID and ns.ItemName and text(ns.ItemName(row.outputItemID))) or "",
                    text(row.prof),
                    text(row.sourceLabel),
                    text(row.repLabel),
                    text(row.repFactionName),
                    text(moat and moat.label),
                    text(moat and moat.short),
                    text(rec.name),
                    text(rec.recipeName),
                    text(ability and ability.howDetail),
                }
                if type(row.craftBreakdown) == "table" then
                    for i = 1, #row.craftBreakdown do
                        local rg = row.craftBreakdown[i]
                        if type(rg) == "table" then
                            parts[#parts + 1] = text(rg.name)
                        end
                    end
                end
                blob = table.concat(parts, "\n"):lower()
                row._vcSearchBlob = blob
                row._vcSearchBlobName = row.name
            end
            if not blob:find(needle, 1, true) then return false end
        end
        return true
    end

    function VC.FilterSort(rows, filters, sort, workspace)
        filters = filters or {}
        sort = sort or {}
        workspace = workspace or { values = {}, profs = {}, names = {}, keys = {} }
        local values, profs, names, keys = workspace.values, workspace.profs, workspace.names, workspace.keys
        if not workspace.keepEntries then
            for row in pairs(values) do
                values[row] = nil
                profs[row] = nil
                names[row] = nil
                keys[row] = nil
            end
        end

        local key = sort.key or "avgProfit"
        local isNumeric = C.NUMERIC_KEYS[key] == true
        local allowHuge = C.HUGE_KEYS[key] == true
        local needle = text(filters.search):lower():match("^%s*(.-)%s*$")
        local lo, hi = Model.SkillBound(filters.skillMin), Model.SkillBound(filters.skillMax)

        local result = {}
        for _, row in ipairs(rows or {}) do
            if H.rowMatches(row, filters, needle, lo, hi) then
                result[#result + 1] = row
                local value = row[key]
                if isNumeric then
                    if not H.sortableNum(value, allowHuge) then value = false end
                else
                    value = text(value)
                end
                values[row] = value
                profs[row] = text(row.prof)
                names[row] = text(row.name)
                keys[row] = text(row.key)
            end
        end

        local ascending = (sort.ascending == true) or (sort.direction == "asc")
        table.sort(result, function(a, b)
            local av, bv = values[a], values[b]
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
            local ap, bp = profs[a], profs[b]
            if ap ~= bp then return ap < bp end
            local an, bn = names[a], names[b]
            if an ~= bn then return an < bn end
            return keys[a] < keys[b]
        end)
        return result
    end

    function H.recordBought(map, itemID, name, qty, spend, minUnit, maxUnit, isVendor)
        local rec = map[itemID]
        if not rec then
            map[itemID] = {
                itemID = itemID,
                name = name,
                qty = qty,
                spend = spend,
                minUnit = minUnit,
                maxUnit = maxUnit,
                isVendor = isVendor == true,
            }
        else
            rec.qty = rec.qty + qty
            rec.spend = rec.spend + spend
            if minUnit and (rec.minUnit == nil or minUnit < rec.minUnit) then rec.minUnit = minUnit end
            if maxUnit and (rec.maxUnit == nil or maxUnit > rec.maxUnit) then rec.maxUnit = maxUnit end
        end
    end

    function H.runSharedAllocation(candidates, craftCap, budgetCopper, econKey, evalScratch, avgField, minField, maxField)
        avgField = avgField or "avgVendor"
        minField = minField or "minVendor"
        maxField = maxField or "maxVendor"
        local sharedPool = {}
        local states = {}

        for idx = 1, #candidates do
            local row = candidates[idx]
            local fixedVendorCost = 0
            local ahLeaves = {}
            local vendorLeaves = {}
            local hasLeafMap = (type(row.leafReagents) == "table" and next(row.leafReagents) ~= nil)
            if hasLeafMap then
                for k, entry in pairs(row.leafReagents) do
                    if type(entry) == "table" and numeric(entry.qty) and entry.qty > 0 and numeric(entry.unitCost) then
                        local id = numeric(entry.itemID) and entry.itemID or (numeric(k) and k or nil)
                        if entry.isVendor then
                            fixedVendorCost = fixedVendorCost + (entry.unitCost * entry.qty)
                            if id then
                                vendorLeaves[#vendorLeaves + 1] = {
                                    itemID = id,
                                    name = entry.name or H.itemName(id),
                                    qty = entry.qty,
                                    unitCost = entry.unitCost,
                                }
                            end
                        elseif id then
                            local vUnit = (numeric(entry.vendorUnit) and entry.vendorUnit > 0) and entry.vendorUnit or nil
                            ahLeaves[#ahLeaves + 1] = {
                                itemID = id,
                                name = entry.name or H.itemName(id),
                                qty = entry.qty,
                                unitCost = entry.unitCost,
                                vendorUnit = vUnit,
                            }
                        end
                    end
                end
                table.sort(ahLeaves, function(a, b) return a.itemID < b.itemID end)
                table.sort(vendorLeaves, function(a, b) return a.itemID < b.itemID end)
            elseif (row.isAllVendor == true or (row.moat and row.moat.isAllVendor == true)) and numeric(row.craftCost) then
                fixedVendorCost = row.craftCost
            end

            local poolReady = true
            for i = 1, #ahLeaves do
                local r = ahLeaves[i]
                local pRec = sharedPool[r.itemID]
                if pRec == nil then
                    local mkt = H.getMoatItemMarket(r.itemID, econKey, evalScratch)
                    local srcLots = mkt.lots
                    if (not srcLots or #srcLots == 0) and mkt.listed and mkt.listed > 0 and r.unitCost > 0 then
                        srcLots = { { price = r.unitCost, qty = mkt.listed } }
                    end
                    if r.vendorUnit then
                        srcLots = H.applyVendorBackstop(srcLots, r.vendorUnit)
                    end
                    if srcLots and #srcLots > 0 then
                        local cloned = {}
                        for j = 1, #srcLots do
                            cloned[j] = { price = srcLots[j].price, qty = srcLots[j].qty, isVendor = srcLots[j].isVendor == true }
                        end
                        pRec = {
                            itemID = r.itemID,
                            name = r.name,
                            lots = cloned,
                            idx = 1,
                            rem = cloned[1].qty,
                        }
                        sharedPool[r.itemID] = pRec
                    else
                        sharedPool[r.itemID] = false
                        pRec = false
                    end
                end
                if pRec == false then
                    poolReady = false
                    break
                end
            end

            if poolReady then
                local isAllVendor = (row.isAllVendor == true) or (row.moat and row.moat.isAllVendor == true) or (#ahLeaves == 0)
                local effCap
                if isAllVendor then
                    effCap = (craftCap and craftCap > 0) and craftCap or C.DEFAULT_VENDOR_LOOP_CAP
                else
                    effCap = (craftCap and craftCap > 0) and craftCap or C.MAX_SIM_CRAFTS
                end
                local rKey = text(row.key)
                if rKey == "" then rKey = tostring(row.spellID or row.name or idx) end
                states[#states + 1] = {
                    row = row,
                    key = rKey,
                    isAllVendor = isAllVendor,
                    fixedVendorCost = fixedVendorCost,
                    ahLeaves = ahLeaves,
                    vendorLeaves = vendorLeaves,
                    avgVendor = row[avgField],
                    minVendor = numeric(row[minField]) and row[minField] or row[avgField],
                    maxVendor = numeric(row[maxField]) and row[maxField] or row[avgField],
                    effectiveCap = effCap,
                    crafts = 0,
                    spend = 0,
                    revenue = 0,
                    profit = 0,
                    firstCost = nil,
                    lastCost = nil,
                    stopReason = nil,
                    stopWallCost = nil,
                    reagentBought = {},
                    active = true,
                }
            end
        end

        local buyList = {}
        local remBudget = (numeric(budgetCopper) and budgetCopper > 0) and budgetCopper or nil
        local steps = 0

        while steps < C.MAX_PORTFOLIO_STEPS do
            steps = steps + 1
            local best = nil

            for i = 1, #states do
                local c = states[i]
                if c.active then
                    local remCap = c.effectiveCap - c.crafts
                    if remCap <= 0 then
                        c.stopReason = c.isAllVendor and "vendor_loop" or "craft_cap"
                        c.active = false
                    elseif #c.ahLeaves == 0 then
                        local marginalCost = c.fixedVendorCost
                        local marginalProfit = c.avgVendor - marginalCost
                        if marginalProfit <= 0 then
                            c.stopWallCost = marginalCost
                            c.stopReason = "price_wall"
                            c.active = false
                        else
                            local batch = remCap
                            if remBudget ~= nil then
                                local maxByB = (marginalCost > 0) and math.floor((remBudget + C.EPS) / marginalCost) or batch
                                if maxByB < 1 then
                                    c.stopReason = "budget"
                                    c.active = false
                                elseif maxByB < batch then
                                    batch = maxByB
                                end
                            end
                            if c.active then
                                local eff = marginalProfit / math.max(1, marginalCost)
                                if not best
                                    or eff > best.eff + 1e-12
                                    or (math.abs(eff - best.eff) <= 1e-12 and marginalProfit > best.marginalProfit + C.EPS)
                                    or (math.abs(eff - best.eff) <= 1e-12 and math.abs(marginalProfit - best.marginalProfit) <= C.EPS and c.key < best.c.key) then
                                    best = {
                                        c = c,
                                        batch = batch,
                                        isFull = true,
                                        marginalCost = marginalCost,
                                        marginalProfit = marginalProfit,
                                        ahSpend = 0,
                                        eff = eff,
                                    }
                                end
                            end
                        end
                    else
                        local ahLeaves = c.ahLeaves
                        local nL = #ahLeaves
                        local kFull = remCap
                        local outSupply = false
                        for j = 1, nL do
                            local leaf = ahLeaves[j]
                            local p = sharedPool[leaf.itemID]
                            if p.idx > #p.lots or p.rem <= C.EPS then
                                outSupply = true
                                break
                            end
                            local canDo = (p.rem == math.huge) and remCap or math.floor((p.rem + C.EPS) / leaf.qty)
                            if canDo < kFull then kFull = canDo end
                        end

                        if outSupply then
                            c.stopReason = "supply"
                            c.active = false
                        elseif kFull >= 1 then
                            local ahSpend = 0
                            local poolSpend = 0
                            for j = 1, nL do
                                local leaf = ahLeaves[j]
                                local p = sharedPool[leaf.itemID]
                                local lot = p.lots[p.idx]
                                local lc = lot.price * leaf.qty
                                poolSpend = poolSpend + lc
                                if not lot.isVendor then
                                    ahSpend = ahSpend + lc
                                end
                            end
                            local marginalCost = c.fixedVendorCost + poolSpend
                            local marginalProfit = c.avgVendor - marginalCost
                            if marginalProfit <= 0 then
                                c.stopWallCost = marginalCost
                                c.stopReason = "price_wall"
                                c.active = false
                            else
                                local batch = kFull
                                if remBudget ~= nil then
                                    local maxByB = (marginalCost > 0) and math.floor((remBudget + C.EPS) / marginalCost) or batch
                                    if maxByB < 1 then
                                        c.stopReason = "budget"
                                        c.active = false
                                    elseif maxByB < batch then
                                        batch = maxByB
                                    end
                                end
                                if c.active then
                                    local eff = (ahSpend > 0) and (marginalProfit / ahSpend) or (marginalProfit / math.max(1, marginalCost))
                                    if not best
                                        or eff > best.eff + 1e-12
                                        or (math.abs(eff - best.eff) <= 1e-12 and marginalProfit > best.marginalProfit + C.EPS)
                                        or (math.abs(eff - best.eff) <= 1e-12 and math.abs(marginalProfit - best.marginalProfit) <= C.EPS and c.key < best.c.key) then
                                        best = {
                                            c = c,
                                            batch = batch,
                                            isFull = true,
                                            marginalCost = marginalCost,
                                            marginalProfit = marginalProfit,
                                            ahSpend = ahSpend,
                                            eff = eff,
                                        }
                                    end
                                end
                            end
                        else
                            -- Straddling 1 craft peek across lots without mutating sharedPool
                            local ahSpend = 0
                            local poolSpend = 0
                            local straddleSupplyOut = false
                            for j = 1, nL do
                                local leaf = ahLeaves[j]
                                local p = sharedPool[leaf.itemID]
                                local lots = p.lots
                                local need = leaf.qty
                                local lIdx = p.idx
                                local avail = p.rem
                                while need > C.EPS do
                                    if lIdx > #lots or avail <= C.EPS then
                                        straddleSupplyOut = true
                                        break
                                    end
                                    local lot = lots[lIdx]
                                    local take = (avail == math.huge or need < avail) and need or avail
                                    local tc = take * lot.price
                                    poolSpend = poolSpend + tc
                                    if not lot.isVendor then
                                        ahSpend = ahSpend + tc
                                    end
                                    need = need - take
                                    if avail ~= math.huge then
                                        avail = avail - take
                                        if avail <= C.EPS then
                                            lIdx = lIdx + 1
                                            avail = (lIdx <= #lots) and lots[lIdx].qty or 0
                                        end
                                    end
                                end
                                if straddleSupplyOut then break end
                            end

                            if straddleSupplyOut then
                                c.stopReason = "supply"
                                c.active = false
                            else
                                local marginalCost = c.fixedVendorCost + poolSpend
                                local marginalProfit = c.avgVendor - marginalCost
                                if marginalProfit <= 0 then
                                    c.stopWallCost = marginalCost
                                    c.stopReason = "price_wall"
                                    c.active = false
                                elseif remBudget ~= nil and marginalCost > remBudget + C.EPS then
                                    c.stopReason = "budget"
                                    c.active = false
                                else
                                    local eff = (ahSpend > 0) and (marginalProfit / ahSpend) or (marginalProfit / math.max(1, marginalCost))
                                    if not best
                                        or eff > best.eff + 1e-12
                                        or (math.abs(eff - best.eff) <= 1e-12 and marginalProfit > best.marginalProfit + C.EPS)
                                        or (math.abs(eff - best.eff) <= 1e-12 and math.abs(marginalProfit - best.marginalProfit) <= C.EPS and c.key < best.c.key) then
                                        best = {
                                            c = c,
                                            batch = 1,
                                            isFull = false,
                                            marginalCost = marginalCost,
                                            marginalProfit = marginalProfit,
                                            ahSpend = ahSpend,
                                            eff = eff,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if not best then break end

            local bc = best.c
            local batch = best.batch
            local batchSpend = batch * best.marginalCost
            local batchRev = batch * bc.avgVendor
            local batchProf = batch * best.marginalProfit

            bc.crafts = bc.crafts + batch
            bc.spend = bc.spend + batchSpend
            bc.revenue = bc.revenue + batchRev
            bc.profit = bc.profit + batchProf
            if bc.firstCost == nil then bc.firstCost = best.marginalCost end
            bc.lastCost = best.marginalCost

            if remBudget ~= nil then
                remBudget = math.max(0, remBudget - batchSpend)
            end

            for j = 1, #bc.vendorLeaves do
                local vl = bc.vendorLeaves[j]
                local q = batch * vl.qty
                local sp = q * vl.unitCost
                H.recordBought(bc.reagentBought, vl.itemID, vl.name, q, sp, vl.unitCost, vl.unitCost, true)
                H.recordBought(buyList, vl.itemID, vl.name, q, sp, vl.unitCost, vl.unitCost, true)
            end

            if #bc.ahLeaves > 0 then
                for j = 1, #bc.ahLeaves do
                    local leaf = bc.ahLeaves[j]
                    local p = sharedPool[leaf.itemID]
                    local lots = p.lots
                    if best.isFull then
                        local lot = lots[p.idx]
                        local unitP = lot.price
                        local q = batch * leaf.qty
                        local sp = q * unitP
                        local lotIsVendor = lot.isVendor == true
                        H.recordBought(bc.reagentBought, leaf.itemID, leaf.name, q, sp, unitP, unitP, lotIsVendor)
                        H.recordBought(buyList, leaf.itemID, leaf.name, q, sp, unitP, unitP, lotIsVendor)
                        if p.rem ~= math.huge then
                            local left = p.rem - q
                            local lIdx = p.idx
                            while left <= C.EPS and lIdx <= #lots do
                                lIdx = lIdx + 1
                                left = (lIdx <= #lots) and lots[lIdx].qty or 0
                            end
                            p.idx = lIdx
                            p.rem = left
                        end
                    else
                        local need = leaf.qty
                        local lIdx = p.idx
                        local avail = p.rem
                        local qTaken = 0
                        local spTaken = 0
                        local minP, maxP = nil, nil
                        local anyAH = false
                        while need > C.EPS and lIdx <= #lots do
                            local lot = lots[lIdx]
                            local unitP = lot.price
                            local take = (avail == math.huge or need < avail) and need or avail
                            qTaken = qTaken + take
                            spTaken = spTaken + (take * unitP)
                            if not lot.isVendor then anyAH = true end
                            if minP == nil or unitP < minP then minP = unitP end
                            if maxP == nil or unitP > maxP then maxP = unitP end
                            need = need - take
                            if avail ~= math.huge then
                                avail = avail - take
                                if avail <= C.EPS then
                                    lIdx = lIdx + 1
                                    avail = (lIdx <= #lots) and lots[lIdx].qty or 0
                                end
                            end
                        end
                        p.idx = lIdx
                        p.rem = avail
                        H.recordBought(bc.reagentBought, leaf.itemID, leaf.name, qTaken, spTaken, minP, maxP, not anyAH)
                        H.recordBought(buyList, leaf.itemID, leaf.name, qTaken, spTaken, minP, maxP, not anyAH)
                    end
                end
            end

            if bc.crafts >= bc.effectiveCap then
                bc.stopReason = bc.isAllVendor and "vendor_loop" or "craft_cap"
                bc.active = false
            end
        end

        for _, rec in pairs(buyList) do
            rec.avgUnit = (rec.qty > 0) and (rec.spend / rec.qty) or 0
        end

        local entries = {}
        local totalProfit = 0
        local totalSpend = 0
        local totalRevenue = 0
        local totalCrafts = 0

        for i = 1, #states do
            local c = states[i]
            if c.crafts > 0 then
                for _, rb in pairs(c.reagentBought) do
                    rb.avgUnit = (rb.qty > 0) and (rb.spend / rb.qty) or 0
                end
                local roiPct = (c.spend > 0) and ((c.profit / c.spend) * 100) or 999
                entries[#entries + 1] = {
                    row = c.row,
                    key = c.key,
                    crafts = c.crafts,
                    spend = c.spend,
                    revenue = c.revenue,
                    profit = c.profit,
                    minProfitTotal = (c.crafts * c.minVendor) - c.spend,
                    maxProfitTotal = (c.crafts * c.maxVendor) - c.spend,
                    roiPct = roiPct,
                    firstCost = c.firstCost,
                    lastCost = c.lastCost,
                    avgCost = c.spend / c.crafts,
                    stopReason = c.stopReason or (c.isAllVendor and "vendor_loop" or "craft_cap"),
                    stopWallCost = c.stopWallCost,
                    isAllVendor = c.isAllVendor,
                    reagentBought = c.reagentBought,
                }
                totalProfit = totalProfit + c.profit
                totalSpend = totalSpend + c.spend
                totalRevenue = totalRevenue + c.revenue
                totalCrafts = totalCrafts + c.crafts
            end
        end

        table.sort(entries, function(a, b)
            if math.abs(a.profit - b.profit) > C.EPS then
                return a.profit > b.profit
            end
            return a.key < b.key
        end)

        local byKey = {}
        for i = 1, #entries do
            entries[i].rank = i
            byKey[entries[i].key] = entries[i]
        end

        return {
            entries = entries,
            byKey = byKey,
            buyList = buyList,
            totalProfit = totalProfit,
            totalSpend = totalSpend,
            totalRevenue = totalRevenue,
            totalCrafts = totalCrafts,
            roiPct = (totalSpend > 0) and ((totalProfit / totalSpend) * 100) or 0,
        }
    end

    function H.optimizePortfolio(rows, opts, avgField, minField, maxField, sourceTag)
        opts = (type(opts) == "table") and opts or {}
        avgField = avgField or "avgVendor"
        minField = minField or "minVendor"
        maxField = maxField or "maxVendor"
        sourceTag = sourceTag or "vendor_crafter_plan"
        local topN = (numeric(opts.topN) and opts.topN > 0) and math.floor(opts.topN) or nil
        local maxCraftsPerRecipe = (numeric(opts.maxCraftsPerRecipe) and opts.maxCraftsPerRecipe > 0) and math.floor(opts.maxCraftsPerRecipe) or 0
        local budgetCopper = (numeric(opts.budgetCopper) and opts.budgetCopper > 0) and opts.budgetCopper or 0
        local econKey = (text(opts.econKey) ~= "" and opts.econKey) or H.resolveEconKey(opts)
        local includeVendorLoops = (opts.includeVendorLoops ~= false)

        local vendorLoopRows = {}
        local ahRows = {}
        for i = 1, #(rows or {}) do
            local row = rows[i]
            if type(row) == "table" and numeric(row.avgProfit) and row.avgProfit > 0 and numeric(row[avgField]) and row[avgField] > 0 then
                local moat = row.moat
                local isAllVendor = (moat and moat.isAllVendor == true) or (row.isAllVendor == true) or (row.moatTier == "infinite")
                local isUnknown = (moat and moat.tier == "unknown") or (row.moatTier == "unknown")
                if isAllVendor then
                    vendorLoopRows[#vendorLoopRows + 1] = row
                elseif not isUnknown then
                    ahRows[#ahRows + 1] = row
                end
            end
        end

        local vendorLoopCount = #vendorLoopRows
        local candidates = {}
        for i = 1, #ahRows do candidates[#candidates + 1] = ahRows[i] end
        if includeVendorLoops then
            for i = 1, #vendorLoopRows do candidates[#candidates + 1] = vendorLoopRows[i] end
        end

        local evalScratch = {}
        local pass1 = H.runSharedAllocation(candidates, maxCraftsPerRecipe, budgetCopper, econKey, evalScratch, avgField, minField, maxField)
        local final = pass1
        if topN and topN > 0 and #pass1.entries > topN then
            local topCandidates = {}
            for i = 1, topN do
                topCandidates[i] = pass1.entries[i].row
            end
            final = H.runSharedAllocation(topCandidates, maxCraftsPerRecipe, budgetCopper, econKey, evalScratch, avgField, minField, maxField)
        end

        local buyCapsByItemID = {}
        for i = 1, #final.entries do
            local e = final.entries[i]
            local rCaps = e.row and e.row.reagentBuyCaps or nil
            local eCaps = {}
            for itemID, rb in pairs(e.reagentBought or {}) do
                if type(rb) == "table" and numeric(itemID) and itemID > 0 and not rb.isVendor then
                    local baseCap = rCaps and rCaps[itemID] or nil
                    local maxU = numeric(rb.maxUnit) and rb.maxUnit or (baseCap and baseCap.maxBuyUnit)
                    local beU = baseCap and baseCap.breakEvenUnit or nil
                    local wallU = baseCap and baseCap.wallUnit or nil
                    local capRec = {
                        maxBuyUnit = maxU,
                        breakEvenUnit = beU,
                        wallUnit = wallU,
                        avgBuyUnit = numeric(rb.avgUnit) and rb.avgUnit or (baseCap and baseCap.avgBuyUnit or nil),
                        minLotUnit = numeric(rb.minUnit) and rb.minUnit or (baseCap and baseCap.minLotUnit or nil),
                        maxBuyQty = rb.qty,
                        source = sourceTag,
                    }
                    eCaps[itemID] = capRec
                    local agg = buyCapsByItemID[itemID]
                    if not agg then
                        agg = {
                            maxBuyUnit = maxU,
                            breakEvenUnit = beU,
                            maxBreakEvenUnit = beU,
                            wallUnit = wallU,
                            totalQty = rb.qty or 0,
                            recipes = {},
                        }
                        buyCapsByItemID[itemID] = agg
                    else
                        if maxU and (not agg.maxBuyUnit or maxU > agg.maxBuyUnit) then agg.maxBuyUnit = maxU end
                        if beU and (not agg.breakEvenUnit or beU < agg.breakEvenUnit) then agg.breakEvenUnit = beU end
                        if beU and (not agg.maxBreakEvenUnit or beU > agg.maxBreakEvenUnit) then agg.maxBreakEvenUnit = beU end
                        if wallU and (not agg.wallUnit or wallU > agg.wallUnit) then agg.wallUnit = wallU end
                        agg.totalQty = agg.totalQty + (rb.qty or 0)
                    end
                    agg.recipes[#agg.recipes + 1] = {
                        key = e.key,
                        name = e.row and e.row.name or e.key,
                        crafts = e.crafts,
                        maxBuyUnit = maxU,
                        breakEvenUnit = beU,
                    }
                end
            end
            e.reagentBuyCaps = next(eCaps) ~= nil and eCaps or rCaps
        end

        return {
            entries = final.entries,
            byKey = final.byKey,
            buyList = final.buyList,
            buyCapsByItemID = buyCapsByItemID,
            totalProfit = final.totalProfit,
            totalSpend = final.totalSpend,
            totalRevenue = final.totalRevenue,
            totalCrafts = final.totalCrafts,
            recipeCount = #final.entries,
            roiPct = final.roiPct,
            vendorLoopCount = vendorLoopCount,
            topN = topN,
            maxCraftsPerRecipe = maxCraftsPerRecipe,
            budgetCopper = budgetCopper,
        }
    end

    function VC.OptimizePortfolio(rows, opts)
        return H.optimizePortfolio(rows, opts, "avgVendor", "minVendor", "maxVendor", "vendor_crafter_plan")
    end

    VC._shared = {
        C = C,
        sortableNum = H.sortableNum,
        serializeMap = H.serializeMap,
        resolveEconKey = H.resolveEconKey,
        itemName = H.itemName,
        evalReagentList = H.evalReagentList,
        resolveYield = H.resolveYield,
        buildSignature = H.buildSignature,
        moatMatches = H.moatMatches,
        optimizePortfolio = H.optimizePortfolio,
    }
end

---------------------------------------------------------------------------------------------------
-- All Items Model: Full Catalog & Gathering Goods Valuation, Filtering & Incremental Builder
---------------------------------------------------------------------------------------------------
do
    local AI = {}
    ns.AllItemsModel = AI
    local C, H = {}, {}
    local states = setmetatable({}, { __mode = "kv" })
    local catalogCache = nil

    C.EXTRA_GATHER_META = {
        -- Mining Stones (5)
        [2835]  = { prof = "mining", skill = 1,   note = "Copper Vein (Stone)" },
        [2836]  = { prof = "mining", skill = 65,  note = "Tin Vein (Stone)" },
        [2838]  = { prof = "mining", skill = 125, note = "Iron Deposit (Stone)" },
        [7912]  = { prof = "mining", skill = 175, note = "Mithril Deposit (Stone)" },
        [12365] = { prof = "mining", skill = 245, note = "Thorium Vein (Stone)" },
        -- Extra & Forever Mining Ores (6)
        [18562]  = { prof = "mining", skill = 300, note = "Blackwing Lair (Ore)" },
        [248815] = { prof = "mining", skill = 275, note = "WoW Forever Ore" },
        [249391] = { prof = "mining", skill = 300, note = "WoW Forever Ore" },
        [249425] = { prof = "mining", skill = 300, note = "WoW Forever Ore" },
        [249426] = { prof = "mining", skill = 300, note = "WoW Forever Ore" },
        [248820] = { prof = "mining", skill = 300, note = "WoW Forever Ore" },
        -- Mining Gems & Crystals (20)
        [774]    = { prof = "mining", skill = 1,   note = "Copper / Tin Vein (Gem)" },
        [818]    = { prof = "mining", skill = 1,   note = "Copper / Tin Vein (Gem)" },
        [1210]   = { prof = "mining", skill = 1,   note = "Copper / Tin / Silver Vein (Gem)" },
        [1206]   = { prof = "mining", skill = 65,  note = "Tin / Silver Vein (Gem)" },
        [1705]   = { prof = "mining", skill = 125, note = "Iron / Gold Deposit (Gem)" },
        [1529]   = { prof = "mining", skill = 125, note = "Iron / Gold Deposit (Gem)" },
        [3864]   = { prof = "mining", skill = 125, note = "Iron / Mithril Deposit (Gem)" },
        [7909]   = { prof = "mining", skill = 175, note = "Mithril / Truesilver Deposit (Gem)" },
        [7910]   = { prof = "mining", skill = 175, note = "Mithril / Truesilver Deposit (Gem)" },
        [11382]  = { prof = "mining", skill = 230, note = "Dark Iron Deposit (Gem)" },
        [11754]  = { prof = "mining", skill = 230, note = "Dark Iron Deposit (Gem)" },
        [12361]  = { prof = "mining", skill = 245, note = "Thorium Vein (Gem)" },
        [12363]  = { prof = "mining", skill = 245, note = "Thorium Vein (Rare Crystal)" },
        [12364]  = { prof = "mining", skill = 245, note = "Thorium Vein (Gem)" },
        [12799]  = { prof = "mining", skill = 245, note = "Thorium Vein (Gem)" },
        [12800]  = { prof = "mining", skill = 245, note = "Thorium Vein (Gem)" },
        [19774]  = { prof = "mining", skill = 275, note = "Hakkari Thorium Vein (Gem)" },
        [22202]  = { prof = "mining", skill = 305, note = "Ahn'Qiraj Obsidian Chunk" },
        [22203]  = { prof = "mining", skill = 305, note = "Ahn'Qiraj Large Obsidian Chunk" },
        [248819] = { prof = "mining", skill = 300, note = "WoW Forever Crystal" },
        -- Extra & Forever Herbalism Goods (11)
        [2452]   = { prof = "herbalism", skill = 50,  note = "Mageroyal / Briarthorn bonus" },
        [8153]   = { prof = "herbalism", skill = 115, note = "Purple Lotus / Trolls" },
        [11040]  = { prof = "herbalism", skill = 200, note = "Un'Goro Soil" },
        [19726]  = { prof = "herbalism", skill = 300, note = "Zul'Gurub" },
        [248821] = { prof = "herbalism", skill = 300, note = "WoW Forever Herb" },
        [248822] = { prof = "herbalism", skill = 300, note = "WoW Forever Herb" },
        [248823] = { prof = "herbalism", skill = 300, note = "WoW Forever Herb" },
        [249274] = { prof = "herbalism", skill = 300, note = "WoW Forever Herb" },
        [249399] = { prof = "herbalism", skill = 300, note = "WoW Forever Herb" },
        [249424] = { prof = "herbalism", skill = 300, note = "WoW Forever Herb" },
        [249796] = { prof = "herbalism", skill = 300, note = "WoW Forever Herb" },
        -- Extra & Forever Skinning Goods (36)
        [8171]   = { prof = "skinning", skill = 255, note = "Level 51-60 beasts (Hide)" },
        [4461]   = { prof = "skinning", skill = 100, note = "Raptors (Hide)" },
        [5082]   = { prof = "skinning", skill = 50,  note = "Kodos (Leather)" },
        [7428]   = { prof = "skinning", skill = 175, note = "Panthers / Cats (Hide)" },
        [8368]   = { prof = "skinning", skill = 205, note = "Wolves (Hide)" },
        [6470]   = { prof = "skinning", skill = 75,  note = "Wailing Caverns Deviates" },
        [6471]   = { prof = "skinning", skill = 75,  note = "Wailing Caverns Deviates" },
        [7286]   = { prof = "skinning", skill = 100, note = "Black Whelps (Scale)" },
        [7287]   = { prof = "skinning", skill = 100, note = "Red Whelps (Scale)" },
        [7392]   = { prof = "skinning", skill = 150, note = "Green Whelps (Scale)" },
        [8154]   = { prof = "skinning", skill = 200, note = "Scorpids (Scale)" },
        [8165]   = { prof = "skinning", skill = 205, note = "Dragonkin (Scale)" },
        [8167]   = { prof = "skinning", skill = 200, note = "Turtles (Scale)" },
        [12607]  = { prof = "skinning", skill = 300, note = "Chromatic Dragonkin" },
        [15408]  = { prof = "skinning", skill = 250, note = "High-level Scorpids" },
        [15410]  = { prof = "skinning", skill = 315, note = "Onyxia's Lair" },
        [15412]  = { prof = "skinning", skill = 275, note = "Green Dragonkin" },
        [15414]  = { prof = "skinning", skill = 275, note = "Red Dragonkin" },
        [15415]  = { prof = "skinning", skill = 275, note = "Blue Dragonkin" },
        [15416]  = { prof = "skinning", skill = 275, note = "Black Dragonkin" },
        [15417]  = { prof = "skinning", skill = 275, note = "Un'Goro Devilsaurs" },
        [15419]  = { prof = "skinning", skill = 275, note = "Winterspring Bears" },
        [15422]  = { prof = "skinning", skill = 285, note = "Winterspring Frostsabers" },
        [15423]  = { prof = "skinning", skill = 285, note = "Winterspring Chimeras" },
        [17012]  = { prof = "skinning", skill = 310, note = "Molten Core Core Hounds" },
        [19767]  = { prof = "skinning", skill = 300, note = "Zul'Gurub Bats" },
        [19768]  = { prof = "skinning", skill = 300, note = "Zul'Gurub Tigers" },
        [20381]  = { prof = "skinning", skill = 315, note = "Ahn'Qiraj / Emerald Dragons" },
        [20498]  = { prof = "skinning", skill = 285, note = "Silithid Beasts" },
        [20500]  = { prof = "skinning", skill = 285, note = "Silithid Beasts" },
        [20501]  = { prof = "skinning", skill = 285, note = "Silithid Beasts" },
        [248824] = { prof = "skinning", skill = 300, note = "WoW Forever Hide" },
        [248825] = { prof = "skinning", skill = 300, note = "WoW Forever Leather" },
        [249427] = { prof = "skinning", skill = 300, note = "WoW Forever Leather" },
        [249428] = { prof = "skinning", skill = 300, note = "WoW Forever Hide" },
        [249429] = { prof = "skinning", skill = 300, note = "WoW Forever Scale" },
    }

    C.TAILOR_MATS = {
        [2589] = true, [2592] = true, [4306] = true, [4338] = true, [14047] = true, [14256] = true,
        [3182] = true, [4337] = true, [10285] = true, [14227] = true,
    }

    C.ENCHANT_MATS = {
        [10940] = true, [10938] = true, [10939] = true, [10978] = true, [10998] = true,
        [11082] = true, [11083] = true, [11084] = true, [11134] = true, [11135] = true,
        [11137] = true, [11138] = true, [11139] = true, [11174] = true, [11175] = true,
        [11176] = true, [11177] = true, [11178] = true, [14343] = true, [14344] = true,
        [16202] = true, [16203] = true, [16204] = true, [20725] = true,
    }

    C.GATHER_CAT_LABELS = {
        mining = "Mining",
        herbalism = "Herbalism",
        skinning = "Skinning",
    }

    C.NUMERIC_KEYS = {
        itemID = true,
        ownedQty = true,
        ownedOutputQty = true,
        listed = true,
        goodScore = true,
        unitAH = true,
        marketValue = true,
        vendorSell = true,
        craftCost = true,
        profit = true,
        salesPerDay = true,
        turnoverPerDay = true,
        demandSort = true,
        usedInCount = true,
        requiredSkill = true,
    }

    function H.nonnegative(v)
        if numeric(v) and v >= 0 then return v end
        return nil
    end

    function H.tableVal(v)
        if readable(v) and type(v) == "table" then return v end
        return nil
    end

    function H.isPlaceholderName(name)
        if type(name) ~= "string" or name == "" then return false end
        return name:find("^Monster %- ") ~= nil
            or name:find("^Level %d+ Test Gear") ~= nil
            or name:find("^%[PH%]") ~= nil
    end

    function H.isScrollName(name)
        if type(name) ~= "string" then return false end
        return name:find("^Recipe: ") ~= nil
            or name:find("^Pattern: ") ~= nil
            or name:find("^Plans: ") ~= nil
            or name:find("^Schematic: ") ~= nil
            or name:find("^Formula: ") ~= nil
            or name:find("^Manual: ") ~= nil
    end

    function H.chooseBestRecipe(list)
        if type(list) ~= "table" or #list == 0 then return nil end
        local best = list[1]
        for i = 2, #list do
            local r = list[i]
            local bestCD = (tonumber(best.cd) or 0) > 0
            local rCD = (tonumber(r.cd) or 0) > 0
            if bestCD ~= rCD then
                if not rCD then best = r end
            else
                local bs = tonumber(best.skill) or 9999
                local rs = tonumber(r.skill) or 9999
                if rs ~= bs then
                    if rs < bs then best = r end
                elseif (tonumber(r.idx) or 999999) < (tonumber(best.idx) or 999999) then
                    best = r
                end
            end
        end
        return best
    end

    function H.resolveEconKey(context)
        local econ = text(context and context.economy)
        if econ ~= "" then return econ end
        if context and context.econInfo and readable(context.econInfo) and text(context.econInfo.effectiveKey) ~= "" then
            return context.econInfo.effectiveKey
        end
        if ns.CurrentEconomyInfo then
            local info = ns.CurrentEconomyInfo()
            if type(info) == "table" and readable(info) and text(info.effectiveKey) ~= "" then
                return info.effectiveKey
            end
        end
        if ns.DetectActiveEconomy then
            local e = ns.DetectActiveEconomy()
            if readable(e) and type(e) == "string" and e ~= "" then return e end
        end
        return nil
    end

    function H.ownedQty(context, id, name)
        local ids = H.tableVal(context and context.ownedCountsByID)
        local counts = H.tableVal(context and context.ownedCounts)
        local qty = (ids and H.nonnegative(ids[id])) or (counts and H.nonnegative(counts[id]))
        if not qty and name and counts then qty = H.nonnegative(counts[name]) end
        if not qty and id and ns.ItemName and counts then
            local liveNm = ns.ItemName(id)
            if liveNm then qty = H.nonnegative(counts[liveNm]) end
        end
        return qty or 0
    end

    function H.coverageStart(first, char, econ, store)
        if not H.tableVal(first) or not econ or not store or type(store.DeriveEcon) ~= "function" then return nil end
        if char and char ~= "all" and store.DeriveEcon(char) ~= econ then return nil end
        local start
        for ck, value in pairs(first) do
            local stamp = H.nonnegative(value)
            if text(ck) ~= "" and stamp and store.DeriveEcon(ck) == econ then
                start = not start and stamp or math.min(start, stamp)
            end
        end
        return start
    end

    function H.loadPersonalSales(state, context)
        if state.personalLoaded then return end
        state.personalLoaded = true
        local analytics = ns.Analytics
        local store = analytics and analytics.Store
        local db = store and store.db
        local first = db and db.stats and db.stats.firstLive
        local char = text(context and context.charKey) ~= "" and context.charKey or (ns.app and text(ns.app.charKey))
        local econ = state.econ
        local now = state.now or (time and time()) or 0
        local start = H.coverageStart(first, char, econ, store)
        state.coverageStart = start
        local disabled = db and db.stats and db.stats.disabled
        local saleDisabled = disabled and (disabled.MAIL == true or disabled.AH_SELL == true or disabled.VENDOR_SELL == true) or false
        if (store and store.readOnly) or saleDisabled or not start or start > now - 7 * 86400 then return end
        if not analytics.Model or type(analytics.Model.Compute) ~= "function" then return end
        local ok, result = pcall(analytics.Model.Compute, "items", { char = "all", econ = econ, period = "7d", source = "AH", knownCostOnly = false })
        if not ok or not H.tableVal(result) or not H.tableVal(result.rows) then return end
        state.personal = {}
        for _, row in ipairs(result.rows) do
            if H.tableVal(row) then
                local id = H.nonnegative(row.itemID)
                if id then state.personal[id] = row end
            end
        end
    end

    function H.typeActive(itemTypes)
        if type(itemTypes) ~= "table" or itemTypes.all == true then return false end
        for _, enabled in pairs(itemTypes) do
            if enabled == true then return true end
        end
        return false
    end

    function H.entryMatchesPriority(entry, priority, lo, hi, hasTypes)
        if not entry then return false end
        if hasTypes and not (priority.itemTypes and priority.itemTypes[entry.itemType] == true) then
            return false
        end
        if lo or hi then
            local sk = entry.requiredSkill
            if not numeric(sk) or (lo and sk < lo) or (hi and sk > hi) then return false end
        end
        local pf = normalizeProfFilter(priority.profFilter or priority.prof)
        if pf == "others" then
            if not (entry.prof == "others" or (entry.profSet and entry.profSet.others == true)) then return false end
        elseif pf ~= "all" then
            if not (entry.prof == pf or (entry.profSet and entry.profSet[pf] == true)) then return false end
        end
        return true
    end

    function H.applyPriority(state, catalog, priority)
        local total = #catalog
        local startIdx = state.index or 1
        local order = state.order
        if not order or #order ~= total then
            order = {}
            for i = 1, total do order[i] = i end
            state.order = order
        end
        local key = priority and priority.key
        if state.priorityApplied and key ~= nil and state.priorityKey == key then return order end
        state.priorityApplied = true
        state.priorityKey = key
        if not priority then
            state.tier1Target = total
            state.tier1Authoritative = false
            state.tier1Notified = false
            return order
        end
        local hasTypes = H.typeActive(priority.itemTypes)
        local lo, hi = Model.SkillBound(priority.skillMin), Model.SkillBound(priority.skillMax)
        local pf = normalizeProfFilter(priority.profFilter or priority.prof)
        local hasNarrowing = (pf ~= "all") or lo ~= nil or hi ~= nil or hasTypes
        if not hasNarrowing then
            state.tier1Target = total
            state.tier1Authoritative = false
            state.tier1Notified = false
            return order
        end
        local t1, t2 = {}, {}
        for pos = startIdx, total do
            local idx = order[pos]
            local entry = catalog[idx]
            if H.entryMatchesPriority(entry, priority, lo, hi, hasTypes) then
                t1[#t1 + 1] = idx
            else
                t2[#t2 + 1] = idx
            end
        end
        local pos = startIdx - 1
        for _, idx in ipairs(t1) do pos = pos + 1; order[pos] = idx end
        local tier1Target = pos
        for _, idx in ipairs(t2) do pos = pos + 1; order[pos] = idx end
        state.tier1Target = tier1Target
        state.tier1Authoritative = (#t2 > 0)
        state.tier1Notified = false
        return order
    end

    function H.matchesRow(row, f, needle, lo, hi, hasTypes)
        if hasTypes and not (f.itemTypes and f.itemTypes[row.itemType] == true) then
            return false
        end
        local pf = normalizeProfFilter(f.profFilter or f.prof)
        if pf == "others" then
            if not (row.prof == "others" or (row.profSet and row.profSet.others == true)) then return false end
        elseif pf ~= "all" then
            if not (row.prof == pf or (row.profSet and row.profSet[pf] == true)) then return false end
        end
        local role = f.roleFilter
        if role and role ~= "all" then
            if role == "priced" then
                if not (numeric(row.unitAH) and row.unitAH > 0) then return false end
            elseif role == "gather" then
                if row.itemType ~= "gather" then return false end
            elseif role == "reagent" then
                if (row.usedInCount or 0) <= 0 then return false end
            elseif role == "crate_writ" then
                if not (row.isCrateMat == true or row.isWritReq == true or row.itemType == "turnin") then return false end
            elseif role == "craftable" then
                if row.recipe == nil then return false end
            end
        end
        if f.sellableFilter == "yes" and not row.sellable then return false end
        if f.sellableFilter == "no" and row.sellable then return false end
        if f.demandFilter and f.demandFilter ~= "all" and ns.MatchesDemandFilter then
            if not ns.MatchesDemandFilter(row.demand, f.demandFilter) then return false end
        end
        if lo or hi then
            local sk = row.requiredSkill
            if not numeric(sk) or (lo and sk < lo) or (hi and sk > hi) then return false end
        end
        if needle ~= "" then
            local blob = row._searchBlob
            if not blob or row._searchBlobName ~= row.name then
                local parts = {
                    text(row.name),
                    tostring(row.itemID or ""),
                    text(row.prof),
                    text(row.categoryLabel),
                    text(row.sourceLabel),
                    text(row.gatherNote),
                    text(row.goodPlain),
                }
                local used = row.usedInRecipes
                if type(used) == "table" then
                    local cap = math.min(8, #used)
                    for i = 1, cap do
                        if used[i] and used[i].name then
                            parts[#parts + 1] = text(used[i].name)
                        end
                    end
                end
                blob = table.concat(parts, "\n"):lower()
                row._searchBlob = blob
                row._searchBlobName = row.name
            end
            if not blob:find(needle, 1, true) then return false end
        end
        return true
    end

    function AI.ClearCache()
        catalogCache = nil
    end

    function AI.Invalidate(reason)
        if reason == "catalog" then
            catalogCache = nil
        end
    end

    function AI.GetCatalog()
        if catalogCache then return catalogCache end
        local recipesByOutput = {}
        local scrollRecipeByID = {}
        local usedInByItem = {}
        local usedInSeen = {}
        local usedInProfs = {}
        for _, rec in ipairs(ns.RECIPES or {}) do
            if type(rec) == "table" then
                local oid = tonumber(rec.outputItemID)
                if oid and oid > 0 and not rec.isEnchant then
                    local list = recipesByOutput[oid]
                    if not list then list = {}; recipesByOutput[oid] = list end
                    list[#list + 1] = rec
                end
                local rid = tonumber(rec.recipeItemID)
                if rid and rid > 0 and not scrollRecipeByID[rid] then
                    scrollRecipeByID[rid] = rec
                end
                local recDispName = rec.name or (oid and ns.ITEM_NAMES_BY_ID and ns.ITEM_NAMES_BY_ID[oid])
                local dedupKey = rec.spellID or recDispName or rec.idx
                for _, rg in ipairs(rec.reagents or {}) do
                    local rgID = tonumber(rg[1] or rg.itemID or rg.id)
                    if rgID and rgID > 0 then
                        local uSeen = usedInSeen[rgID]
                        if not uSeen then uSeen = {}; usedInSeen[rgID] = uSeen end
                        if not uSeen[dedupKey] then
                            uSeen[dedupKey] = true
                            local uList = usedInByItem[rgID]
                            if not uList then uList = {}; usedInByItem[rgID] = uList end
                            uList[#uList + 1] = {
                                spellID = rec.spellID,
                                name = recDispName or ("Recipe #" .. tostring(rec.spellID or rec.idx or 0)),
                                prof = rec.prof,
                                outputItemID = oid,
                            }
                        end
                        if type(rec.prof) == "string" and rec.prof ~= "" then
                            local ps = usedInProfs[rgID]
                            if not ps then ps = {}; usedInProfs[rgID] = ps end
                            ps[rec.prof] = true
                        end
                    end
                end
            end
        end

        local crateByID = {}
        for _, c in ipairs(ns.CRATES or {}) do
            if c and c.itemID then crateByID[c.itemID] = c end
        end
        local writByID = {}
        for _, w in ipairs(ns.WRITS or {}) do
            if w and w.itemID and not writByID[w.itemID] then writByID[w.itemID] = w end
        end
        local specialByID = {}
        for _, s in ipairs(ns.SPECIAL_REP_UNLOCKS or {}) do
            if s and s.itemID and not specialByID[s.itemID] then specialByID[s.itemID] = s end
        end

        local ids = {}
        for id, item in pairs(ns.ITEMS or {}) do
            if type(id) == "number" and id > 0 and id == math.floor(id) and type(item) == "table" then
                if not H.isPlaceholderName(item.name) then
                    ids[#ids + 1] = id
                end
            end
        end
        table.sort(ids)

        local entries = {}
        local gatherByItem = ns.GATHER_BY_ITEM or {}
        local vendorReagents = ns.VENDOR_REAGENTS or {}
        local crateBundle = ns.CRATE_BY_BUNDLE_ITEM or {}
        local writReq = ns.WRIT_BY_REQ_ITEM or {}
        local profByKey = ns.PROF_BY_KEY or {}

        for i = 1, #ids do
            local id = ids[i]
            local item = ns.ITEMS[id]
            local gatherInfo = gatherByItem[id] or C.EXTRA_GATHER_META[id]
            local outRecipes = recipesByOutput[id]
            local bestRecipe = outRecipes and H.chooseBestRecipe(outRecipes) or nil
            local scrollRec = scrollRecipeByID[id]
            local usedProfs = usedInProfs[id]

            local itemType, prof, profSet, categoryLabel, sourceLabel, requiredSkill, gatherNote
            if gatherInfo then
                itemType = "gather"
                prof = gatherInfo.prof
                profSet = { [prof] = true }
                requiredSkill = gatherInfo.skill
                gatherNote = gatherInfo.note
                categoryLabel = C.GATHER_CAT_LABELS[prof] or "Gathering"
                sourceLabel = categoryLabel
            elseif bestRecipe then
                itemType = "crafted"
                prof = bestRecipe.prof or "others"
                profSet = {}
                for _, r in ipairs(outRecipes) do
                    if r.prof then profSet[r.prof] = true end
                end
                if not next(profSet) then profSet[prof] = true end
                requiredSkill = bestRecipe.skill
                categoryLabel = "Crafted"
                local pObj = profByKey[prof]
                sourceLabel = (pObj and pObj.full) or "Crafted"
            elseif scrollRec or H.isScrollName(item.name) then
                itemType = "scroll"
                prof = (scrollRec and scrollRec.prof) or "others"
                profSet = { [prof] = true }
                requiredSkill = scrollRec and scrollRec.skill or nil
                categoryLabel = "Scroll"
                sourceLabel = "Recipe Scroll"
            elseif crateByID[id] then
                itemType = "turnin"
                prof = "others"
                profSet = { others = true }
                categoryLabel = "Crate"
                sourceLabel = "Waylaid Crate"
            elseif writByID[id] then
                local w = writByID[id]
                itemType = "turnin"
                prof = w.prof or "others"
                profSet = { [prof] = true, others = true }
                categoryLabel = "Writ"
                sourceLabel = "Craftsman's Writ"
            elseif specialByID[id] then
                itemType = "turnin"
                prof = "others"
                profSet = { others = true }
                categoryLabel = "Unlock"
                sourceLabel = "Merchant Favor"
            elseif vendorReagents[id] then
                itemType = "vendor"
                local onlyProf
                if usedProfs then
                    for pk in pairs(usedProfs) do
                        if not onlyProf then onlyProf = pk else onlyProf = false; break end
                    end
                end
                prof = (onlyProf and onlyProf ~= false) and onlyProf or "others"
                profSet = { [prof] = true }
                categoryLabel = "Vendor"
                sourceLabel = "Vendor"
            elseif C.TAILOR_MATS[id] then
                itemType = "material"
                prof = "tailoring"
                profSet = { tailoring = true }
                categoryLabel = "Cloth"
                sourceLabel = "Drop / Cloth"
            elseif C.ENCHANT_MATS[id] then
                itemType = "material"
                prof = "enchanting"
                profSet = { enchanting = true }
                categoryLabel = "Disenchant"
                sourceLabel = "Disenchant"
            else
                itemType = "material"
                local onlyCooking = usedProfs and usedProfs.cooking == true
                if onlyCooking then
                    for pk in pairs(usedProfs) do
                        if pk ~= "cooking" then onlyCooking = false; break end
                    end
                end
                if onlyCooking then
                    prof = "cooking"
                else
                    local cb = crateBundle[id]
                    if type(cb) == "table" and type(cb.prof) == "string" and cb.prof ~= "" and cb.prof ~= "other" then
                        prof = cb.prof
                    else
                        prof = "others"
                    end
                end
                profSet = { [prof] = true }
                categoryLabel = "Material"
                sourceLabel = (prof == "cooking") and "Cooking Mat" or "Drop / World"
            end

            local usedList = usedInByItem[id] or {}
            entries[#entries + 1] = {
                itemID = id,
                name = item.name or ("Item #" .. tostring(id)),
                sell = item.sell,
                buy = item.buy,
                vendorPrice = item.vendorPrice,
                bop = item.bop == true,
                itemType = itemType,
                prof = prof,
                profSet = profSet,
                categoryLabel = categoryLabel,
                sourceLabel = sourceLabel,
                gatherNote = gatherNote,
                requiredSkill = requiredSkill,
                bestRecipe = bestRecipe,
                usedInRecipes = usedList,
                usedInCount = #usedList,
                isCrateMat = crateBundle[id] ~= nil,
                isWritReq = writReq[id] ~= nil,
                wowheadURL = "https://www.wowhead.com/classic/item=" .. tostring(id),
            }
        end

        catalogCache = entries
        return catalogCache
    end

    function AI.EvaluateItem(entry, context, state)
        context = context or {}
        state = state or {}
        local id = entry.itemID
        local name = (ns.ItemName and ns.ItemName(id, entry.name)) or entry.name or ("Item #" .. tostring(id))
        local icon = (ns.ItemIcon and ns.ItemIcon(id, ns.QUESTION_ICON)) or ns.QUESTION_ICON
        local sellable = (ns.IsItemSellable and ns.IsItemSellable(id, not entry.bop, false)) or (not entry.bop)
        local vendorSell = (ns.GetVendorSellPrice and H.nonnegative(ns.GetVendorSellPrice(id))) or H.nonnegative(entry.sell)
        local vendorBuy = (ns.VENDOR_REAGENTS and H.nonnegative(ns.VENDOR_REAGENTS[id])) or nil
        local ownedQty = H.ownedQty(context, id, name)
        local econ = state.econ or H.resolveEconKey(context)

        local unitAH, ahSource, listed, marketValue, marketDemand
        local salesPerDay, salesScope, salesWindowDays
        local personalSold7d, personalExpired7d, personalSellThrough, personalCancelChurn, isSlowing
        local fallbackDailySold, marketSalesPerDay, snapDailySold, demandSource

        if sellable then
            if ns.GetItemMarketPrice then
                local rawAH, rawSrc = ns.GetItemMarketPrice(id)
                unitAH = H.nonnegative(rawAH)
                if unitAH then ahSource = rawSrc end
            end
            if ns.GetNumListed then
                listed = H.nonnegative(ns.GetNumListed(id))
            end
            if ns.Pricing and ns.Pricing.GetItemSnapshotLatest then
                local snap = ns.Pricing.GetItemSnapshotLatest(id, econ)
                marketValue = snap and (H.nonnegative(snap.marketValue) or H.nonnegative(snap.historical)) or nil
            end
            if marketValue == nil then marketValue = unitAH end

            if ns.GetMultiSourceDemand then
                marketDemand = ns.GetMultiSourceDemand(id, econ)
            end
            local md = marketDemand
            fallbackDailySold = (ns.GetDailySold and H.nonnegative(ns.GetDailySold(id))) or nil
            local personal = state.personal and state.personal[id]
            local pSold = personal and (H.nonnegative(personal.ahSold) or H.nonnegative(personal.sold)) or 0
            local pExp = personal and H.nonnegative(personal.expired) or 0
            if state.personal then
                personalSold7d = pSold
                personalExpired7d = pExp
                personalSellThrough = personal and (H.nonnegative(personal.ahSellThrough) or H.nonnegative(personal.saleRate)) or nil
                personalCancelChurn = personal and H.nonnegative(personal.cancelChurn) or nil
            end
            local snapDaily = md and H.nonnegative(md.snapDailySold) or nil
            marketSalesPerDay = md and H.nonnegative(md.effectiveDailySold) or nil
            snapDailySold = snapDaily
            demandSource = md and text(md.demandSource) ~= "" and md.demandSource or nil
            if personal and pSold > 0 then
                salesPerDay = H.nonnegative(personal.ahVelocity) or H.nonnegative(personal.velocity) or 0
                isSlowing = (readable(personal.ahIsSlowing) and personal.ahIsSlowing == true)
                    or (readable(personal.isSlowing) and personal.isSlowing == true) or false
                salesScope = "Personal"
                salesWindowDays = 7
            elseif snapDaily and snapDaily > 0 then
                salesPerDay = snapDaily
                salesScope = "Blizzard"
                salesWindowDays = 7
            elseif md and H.nonnegative(md.localClearsPerDay) then
                salesPerDay = H.nonnegative(md.localClearsPerDay)
                salesScope = "Local Scan"
                salesWindowDays = 3
            elseif fallbackDailySold ~= nil then
                salesPerDay = fallbackDailySold
                salesScope = "Blizzard"
                salesWindowDays = 7
            elseif personal and pExp > 0 then
                salesPerDay = 0
                isSlowing = (readable(personal.ahIsSlowing) and personal.ahIsSlowing == true)
                    or (readable(personal.isSlowing) and personal.isSlowing == true) or false
                salesScope = "Personal"
                salesWindowDays = 7
            end
        end

        local turnoverPerDay = (salesPerDay and unitAH) and (salesPerDay * unitAH) or nil
        local demand = ns.EvaluateMarketDemand and ns.EvaluateMarketDemand(listed, salesPerDay, sellable) or nil
        local demandSort = demand and demand.demandScore or nil

        local craftCost, profit
        local rec = entry.bestRecipe
        if rec then
            local reagents = (ns.ResolveRecipeReagents and ns.ResolveRecipeReagents(rec)) or rec.reagents
            if type(reagents) == "table" and #reagents > 0 and ns.ComputeSmartCraftCost then
                local cc = ns.ComputeSmartCraftCost(reagents, rec.numMade or 1, id, {
                    parentProf = rec.prof,
                    profMap = context.profMap,
                    subCraftMode = context.subCraftMode or "smart",
                    subCraftOverrides = context.subCraftOverrides,
                })
                craftCost = H.nonnegative(cc)
                if craftCost and unitAH and sellable then
                    local netSale = (context.applyAHCut ~= false) and math.floor(unitAH * 0.95 + 0.5) or unitAH
                    profit = netSale - craftCost
                end
            end
        end

        local goodScore, goodShort, goodFull, goodPlain
        if type(ns.EvaluateProductQuality) == "function" then
            local effDaily = numeric(salesPerDay) and salesPerDay or fallbackDailySold
            local saleRate = numeric(personalSellThrough) and personalSellThrough or nil
            local _, gs, gShort, gFull = ns.EvaluateProductQuality(id, rec, nil, effDaily, saleRate)
            goodScore, goodShort, goodFull = gs, gShort, gFull
        end
        if entry.usedInCount > 0 then
            local usedTag = "|cff66ccffUsed in " .. tostring(entry.usedInCount)
                .. (entry.usedInCount == 1 and " recipe|r" or " recipes|r")
            goodScore = (tonumber(goodScore) or 0) + (entry.usedInCount >= 3 and 14 or 6)
            if type(goodShort) ~= "string" or goodShort == "" or goodShort:find("Niche / Low Vol", 1, true) then
                goodShort = usedTag
            end
            if type(goodFull) ~= "string" or goodFull == "" or goodFull:find("Low Regional Demand", 1, true) then
                goodFull = usedTag
            elseif not goodFull:find("Used in ", 1, true) then
                goodFull = goodFull .. " · " .. usedTag
            end
        end
        if not sellable and (not goodScore or goodScore <= 0) then
            goodScore, goodShort, goodFull, goodPlain = nil, nil, nil, nil
        elseif goodScore or goodShort or goodFull then
            local plainParts
            if type(goodShort) == "string" and type(goodFull) == "string" and goodFull ~= goodShort and not goodFull:find(goodShort, 1, true) then
                plainParts = goodShort .. " " .. goodFull
            else
                plainParts = (type(goodFull) == "string" and goodFull ~= "") and goodFull or goodShort
            end
            goodPlain = type(plainParts) == "string" and (plainParts:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or nil
        end

        return {
            key = "item:" .. tostring(id),
            itemID = id,
            outputItemID = id,
            name = name,
            icon = icon,
            prof = entry.prof,
            profSet = entry.profSet,
            itemType = entry.itemType,
            categoryLabel = entry.categoryLabel,
            sourceLabel = entry.sourceLabel,
            gatherNote = entry.gatherNote,
            requiredSkill = entry.requiredSkill,
            sellable = sellable == true,
            bop = entry.bop == true,
            ownedQty = ownedQty,
            ownedOutputQty = ownedQty,
            listed = listed,
            unitAH = unitAH,
            ahSource = ahSource,
            marketValue = marketValue,
            vendorSell = vendorSell,
            vendorBuy = vendorBuy,
            craftCost = craftCost,
            profit = profit,
            salesPerDay = salesPerDay,
            salesScope = salesScope,
            salesWindowDays = salesWindowDays,
            turnoverPerDay = turnoverPerDay,
            demand = demand,
            demandSort = demandSort,
            marketDemand = marketDemand,
            marketSalesPerDay = marketSalesPerDay,
            snapDailySold = snapDailySold,
            demandSource = demandSource,
            personalSold7d = personalSold7d,
            personalExpired7d = personalExpired7d,
            personalSellThrough = personalSellThrough,
            personalCancelChurn = personalCancelChurn,
            isSlowing = isSlowing,
            goodScore = goodScore,
            goodShort = goodShort,
            goodFull = goodFull,
            goodPlain = goodPlain,
            usedInCount = entry.usedInCount,
            usedInRecipes = entry.usedInRecipes,
            isCrateMat = entry.isCrateMat,
            isWritReq = entry.isWritReq,
            recipe = rec,
            numMade = (rec and rec.numMade) or 1,
            wowheadURL = entry.wowheadURL,
            coverageStart = state.coverageStart,
        }
    end

    function AI.Reprioritize(state, priority)
        if not state or state.completed then return state and state.order end
        local catalog = state.catalog or AI.GetCatalog()
        return H.applyPriority(state, catalog, priority)
    end

    function AI.Attach(state, background, priority, onProgress, onComplete, onTierReady)
        if not state or state.completed then return state end
        local prevOnTierReady = state.onTierReady
        state.background = background == true
        if onProgress ~= nil or background then state.onProgress = onProgress end
        if onComplete ~= nil then state.onComplete = onComplete end
        if onTierReady ~= nil or background then state.onTierReady = onTierReady end
        local catalog = state.catalog or AI.GetCatalog()
        H.applyPriority(state, catalog, priority)
        if not state.background and state.onTierReady and not prevOnTierReady and state.tier1Authoritative and state.index > state.tier1Target then
            state.tier1Notified = false
        end
        return state
    end

    function AI.Start(context, onProgress, onComplete, resumeState, onTierReady)
        context = context or {}
        local catalog = AI.GetCatalog()
        local identity = context.dataset or context
        local state = resumeState or states[context]
        if not state or state.dataset ~= identity or state.catalog ~= catalog then
            if state and state.cancel then state.cancel() end
            state = {
                dataset = identity,
                catalog = catalog,
                rows = {},
                index = 1,
                generation = 0,
                econ = H.resolveEconKey(context),
                now = numeric(context.now) and context.now or (time and time()) or 0,
            }
        end
        states[context] = state
        local prevOnTierReady = state.onTierReady
        state.onProgress = onProgress
        state.onComplete = onComplete
        state.onTierReady = onTierReady
        state.background = context.background == true
        H.applyPriority(state, catalog, context.priority)
        if not state.background and state.onTierReady and not prevOnTierReady and state.tier1Authoritative and state.index > state.tier1Target then
            state.tier1Notified = false
        end
        if state.running or state.completed then return state.cancel or function() end, state end
        state.generation = state.generation + 1
        local token = state.generation
        state.running = true
        local function current() return state.running and state.generation == token end
        local function cancel()
            if state.generation == token then
                state.running = false
                state.cancel = nil
                state.generation = token + 1
            end
        end
        state.cancel = cancel
        local defer = context.defer == false and nil or (context.defer or (C_Timer and C_Timer.After and function(fn) C_Timer.After(0, fn) end))

        local function runBatch(started)
            local count = 0
            local maxBatch = state.background and 40 or 60
            local budgetMS = state.background and 1.2 or 1.8
            repeat
                if state.index > #state.order then break end
                local entry = catalog[state.order[state.index]]
                state.rows[#state.rows + 1] = AI.EvaluateItem(entry, context, state)
                state.index = state.index + 1
                count = count + 1
                if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index > state.tier1Target then break end
            until count >= maxBatch or clockMS() - started >= budgetMS
        end

        local step
        local batchOpen = false
        local stepping, stepAgain = false, false
        local function runStep()
            if not current() then return end
            if not state.personalLoaded then
                H.loadPersonalSales(state, context)
                if defer and #state.order > 0 then
                    defer(step)
                    return
                end
            end
            if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index > state.tier1Target then
                state.tier1Notified = true
                state.onTierReady(state.rows, #state.rows, #state.order)
                if not current() then return end
            end
            local ranBatch = false
            if state.index <= #state.order then
                ranBatch = true
                local started = clockMS()
                if ns.BeginEval then batchOpen = true; state.bank = ns.BeginEval(state.bank) end
                runBatch(started)
                if ns.EndEval then ns.EndEval() end
                batchOpen = false
                if not current() then return end
                if state.onProgress then state.onProgress(state.rows, #state.rows, #state.order) end
                if not current() then return end
            end
            if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index > state.tier1Target then
                state.tier1Notified = true
                if state.index <= #state.order then
                    state.onTierReady(state.rows, #state.rows, #state.order)
                    if not current() then return end
                end
            end
            if state.index > #state.order then
                if defer and ranBatch then
                    defer(step)
                    return
                end
                state.running = false
                state.cancel = nil
                state.completed = true
                if state.onComplete then state.onComplete(state.rows) end
            elseif defer then
                defer(step)
            end
        end

        step = function()
            if stepping then stepAgain = true; return end
            stepping = true
            repeat
                stepAgain = false
                local ok, err = pcall(runStep)
                if not ok then
                    stepping = false
                    if state.generation == token then
                        state.running = false
                        state.cancel = nil
                        state.completed = false
                        state.tier1Notified = false
                    end
                    if batchOpen and ns.EndEval then pcall(ns.EndEval) end
                    if ns.ResetEval then ns.ResetEval() end
                    error(err, 0)
                end
            until not stepAgain
            stepping = false
        end
        if defer then defer(step) else repeat step() until not current() end
        return cancel, state
    end

    function AI.PatchMeta(rows, context)
        context = context or {}
        for _, row in ipairs(rows or {}) do
            if type(row) == "table" and row.itemID then
                local qty = H.ownedQty(context, row.itemID, row.name)
                row.ownedQty = qty
                row.ownedOutputQty = qty
            end
        end
    end

    function AI.PatchMetaTargeted(rows, context, targets)
        if type(rows) ~= "table" or #rows == 0 or type(targets) ~= "table" then return 0 end
        local ids = H.tableVal(targets.ids)
        local names = H.tableVal(targets.names)
        if not ((ids and next(ids)) or (names and next(names))) then return 0 end
        context = context or {}
        local patched = 0
        for i = 1, #rows do
            local row = rows[i]
            if type(row) == "table" and row.itemID then
                if (ids and ids[row.itemID]) or (names and row.name and names[row.name]) then
                    local qty = H.ownedQty(context, row.itemID, row.name)
                    row.ownedQty = qty
                    row.ownedOutputQty = qty
                    patched = patched + 1
                end
            end
        end
        return patched
    end

    function AI.RepairItems(rows, context, itemIDs)
        if type(rows) ~= "table" or type(itemIDs) ~= "table" or not next(itemIDs) then return false end
        context = context or {}
        local catalog = AI.GetCatalog()
        local byID = {}
        for i = 1, #catalog do
            byID[catalog[i].itemID] = catalog[i]
        end
        local state = states[context] or { econ = H.resolveEconKey(context), now = numeric(context.now) and context.now or (time and time()) or 0 }
        local changed = false
        if ns.BeginEval then state.bank = ns.BeginEval(state.bank) end
        local ok, err = pcall(function()
            for i = 1, #rows do
                local row = rows[i]
                local hit = itemIDs[row.itemID] == true
                if not hit and type(row.recipe) == "table" then
                    for _, rg in ipairs(row.recipe.reagents or {}) do
                        local rid = rg[1] or rg.itemID or rg.id
                        if rid and itemIDs[rid] then hit = true; break end
                    end
                end
                if hit then
                    local entry = byID[row.itemID]
                    if entry then
                        rows[i] = AI.EvaluateItem(entry, context, state)
                        changed = true
                    end
                end
            end
        end)
        if ns.EndEval then ns.EndEval() end
        if not ok then
            if ns.ResetEval then ns.ResetEval() end
            error(err, 0)
        end
        return changed
    end

    function AI.FilterSort(rows, filters, sort, workspace)
        filters = filters or {}
        sort = sort or {}
        workspace = workspace or {}
        workspace.values = workspace.values or {}
        workspace.names = workspace.names or {}
        workspace.keys = workspace.keys or {}
        local values, names, keys = workspace.values, workspace.names, workspace.keys
        if not workspace.keepEntries then
            for row in pairs(values) do
                values[row] = nil
                names[row] = nil
                keys[row] = nil
            end
        end
        local key = sort.key or "turnoverPerDay"
        local isNumeric = C.NUMERIC_KEYS[key] == true
        local needle = text(filters.search):lower():match("^%s*(.-)%s*$")
        local lo, hi = Model.SkillBound(filters.skillMin), Model.SkillBound(filters.skillMax)
        local hasTypes = H.typeActive(filters.itemTypes)
        local result = {}
        for _, row in ipairs(rows or {}) do
            if H.matchesRow(row, filters, needle, lo, hi, hasTypes) then
                result[#result + 1] = row
                local val = row[key]
                if isNumeric then
                    if not numeric(val) then val = false end
                else
                    val = text(val)
                end
                values[row] = val
                names[row] = text(row.name)
                keys[row] = row.itemID or 0
            end
        end
        local ascending = sort.ascending == true or sort.direction == "asc"
        table.sort(result, function(a, b)
            local av, bv = values[a], values[b]
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
            local an, bn = names[a], names[b]
            if an ~= bn then return an < bn end
            return (keys[a] or 0) < (keys[b] or 0)
        end)
        return result
    end
end

---------------------------------------------------------------------------------------------------
-- Disenchantment Crafter Model: Craft-to-Disenchant Expected Value, Buy Moat & Portfolio Planner
---------------------------------------------------------------------------------------------------
do
    local DC = {}
    ns.DisenchantCrafterModel = DC

    local VC = ns.VendorCrafterModel
    local S = VC._shared
    local C = S.C

    local DC_NUMERIC_KEYS = {
        craftCost = true,
        minDE = true,
        avgDE = true,
        avgDEAS = true,
        maxDE = true,
        avgProfit = true,
        minProfit = true,
        maxProfit = true,
        marginPct = true,
        moatScore = true,
        profitableCrafts = true,
        totalProfitCap = true,
        totalSpendCap = true,
        buyCeiling = true,
        safeProfitCrafts = true,
        planCrafts = true,
        planProfit = true,
        planRank = true,
        requiredSkill = true,
        knownSort = true,
        cdSort = true,
        buyCostCopper = true,
        numMade = true,
        repSort = true,
        ownedOutputQty = true,
        ownedScrollQty = true,
        deIlvl = true,
        deQuality = true,
    }

    local buildCache = setmetatable({}, { __mode = "k" })

    local function resolveApplyCut(context)
        if type(context) == "table" and context.applyAHCut ~= nil then
            return context.applyAHCut == true
        end
        return not _G.MerchantMasterDB or _G.MerchantMasterDB.applyAHCut ~= false
    end

    local function buildSignature(context, legacy)
        local base = S.buildSignature(context, legacy)
        local asFlag = (type(context) == "table" and context.arcaneSalvager == true) and "1" or "0"
        local opFlag = (type(context) == "table" and context.onlyProfitable == true) and "1" or "0"
        local nonDEFlag = (type(context) == "table" and context.showNonDE == true) and "1" or "0"
        local obsVer = (type(context) == "table" and context.deObsVersion)
            or (ns.GetDEObservationVersion and ns.GetDEObservationVersion())
            or 0
        return base .. "|" .. (resolveApplyCut(context) and "1" or "0") .. "|" .. asFlag .. "|" .. opFlag .. "|" .. nonDEFlag .. "|" .. tostring(obsVer)
    end

    function DC.ResolveLegacy(opts)
        return VC.ResolveLegacy(opts)
    end

    function DC.ClearCache()
        buildCache = setmetatable({}, { __mode = "k" })
    end

    function DC.BuildPriorityOrder(catalog, priority)
        local state = { index = 1 }
        return applyPriority(state, catalog or {}, priority)
    end

    function DC.Reprioritize(state, priority)
        if not state or state.completed then return state and state.order end
        local catalog = state.catalog or (ns.RecipeStats and ns.RecipeStats.GetCatalog and ns.RecipeStats.GetCatalog()) or {}
        return applyPriority(state, catalog, priority)
    end

    function DC.Attach(state, background, priority, onProgress, onComplete, onTierReady)
        if not state or state.completed then return state end
        local prevOnTierReady = state.onTierReady
        state.background = background == true
        if onProgress ~= nil or background then state.onProgress = onProgress end
        if onComplete ~= nil then state.onComplete = onComplete end
        if onTierReady ~= nil or background then state.onTierReady = onTierReady end
        local catalog = state.catalog or (ns.RecipeStats and ns.RecipeStats.GetCatalog and ns.RecipeStats.GetCatalog()) or {}
        applyPriority(state, catalog, priority)
        if not state.background and state.onTierReady and not prevOnTierReady and state.tier1Authoritative and state.index > state.tier1Target then
            state.tier1Notified = false
        end
        return state
    end

    function DC.EvaluateRecipe(recipe, context, legacy, evalScratch)
        if type(recipe) ~= "table" then return nil end
        context = (type(context) == "table") and context or {}
        local showNonDE = (context.showNonDE == true)
        local outID = recipe.outputItemID
        local isEnchant = (recipe.isEnchant == true)

        if isEnchant and not showNonDE then
            return nil
        end

        local applyCut = resolveApplyCut(context)
        local bd, err = nil, nil
        local deEligible = false
        local deReason = nil

        if isEnchant then
            deEligible = false
            deReason = "Enchant"
        elseif not numeric(outID) or outID <= 0 then
            if not showNonDE then return nil end
            deEligible = false
            deReason = "Not Disenchantable"
        else
            if not ns.GetItemDEBreakdown then return nil end
            bd, err = ns.GetItemDEBreakdown(outID, nil, applyCut)
            if err == "uncached" then
                if type(evalScratch) == "table" then
                    evalScratch.uncachedIDs = evalScratch.uncachedIDs or {}
                    evalScratch.uncachedIDs[outID] = true
                end
                return nil, "uncached"
            end
            if type(evalScratch) == "table" and evalScratch.uncachedIDs then
                evalScratch.uncachedIDs[outID] = nil
            end
            if bd and type(bd.outcomes) == "table" and #bd.outcomes > 0 then
                deEligible = true
            else
                if not showNonDE then return nil end
                deEligible = false
                deReason = err or "Not Disenchantable"
                bd = nil
            end
        end

        local reagents = (ns.ResolveRecipeReagents and ns.ResolveRecipeReagents(recipe)) or recipe.reagents
        legacy = legacy or VC.ResolveLegacy(context)
        evalScratch = evalScratch or {}

        local numMade = (numeric(recipe.numMade) and recipe.numMade > 0) and recipe.numMade or 1
        local y = S.resolveYield(recipe, context, legacy)
        local asActive = (context.arcaneSalvager == true)

        local minDE, baseAvgDE, asAvgDE, avgDE, maxDE = nil, nil, nil, nil, nil
        if deEligible and bd and numeric(bd.netCopper) then
            minDE = y.min * (bd.minNetCopper or bd.netCopper)
            baseAvgDE = y.avg * bd.netCopper
            asAvgDE = y.avg * (bd.asNetCopper or math.floor(bd.netCopper * (1 + (ns.DE_ARCANE_SALVAGER_BONUS or 0.20)) + 0.5))
            avgDE = asActive and asAvgDE or baseAvgDE
            local maxBaseDE = y.max * (bd.maxNetCopper or bd.netCopper)
            maxDE = asActive and math.floor(maxBaseDE * (1 + (ns.DE_ARCANE_SALVAGER_BONUS or 0.20)) + 0.5) or maxBaseDE
        end

        local subCraftMode = context.subCraftMode or "smart"
        local overrides = context.subCraftOverrides
        local profMap = context.profMap or (ns.GetPlayerProfessions and ns.GetPlayerProfessions()) or nil

        local craftCost, craftBreakdown, leafReagents = nil, nil, nil
        if type(reagents) == "table" and #reagents > 0 then
            local subKey = table.concat({
                tostring(legacy.bartering),
                legacy.honored and "1" or "0",
                tostring(legacy.masterChef),
                tostring(subCraftMode),
                S.serializeMap(overrides),
                S.serializeMap(profMap),
            }, "|")
            local subRoot = evalScratch.subCache
            if not subRoot then
                subRoot = {}
                evalScratch.subCache = subRoot
            end
            local subBucket = subRoot[subKey]
            if not subBucket then
                subBucket = {}
                subRoot[subKey] = subBucket
            end

            local visited = (numeric(outID) and outID > 0) and { [outID] = true } or {}
            local cCost, cBreak, cLeaves = S.evalReagentList(
                reagents, recipe.prof, profMap, legacy, subCraftMode, overrides, subBucket, visited, 0, evalScratch
            )
            if numeric(cCost) then
                craftCost = cCost
                craftBreakdown = cBreak
                leafReagents = cLeaves
            end
        end

        local minProfit, avgProfit, maxProfit, marginPct = nil, nil, nil, nil
        if deEligible and numeric(craftCost) and numeric(avgDE) then
            minProfit = numeric(minDE) and (minDE - craftCost) or nil
            avgProfit = avgDE - craftCost
            maxProfit = numeric(maxDE) and (maxDE - craftCost) or nil
            if craftCost > 0 then
                marginPct = (avgProfit / craftCost) * 100
            elseif avgProfit > 0 then
                marginPct = 999
            elseif avgProfit < 0 then
                marginPct = -999
            else
                marginPct = 0
            end
        end

        local base = ns.RecipeStats and ns.RecipeStats.Get and ns.RecipeStats.Get(recipe, context) or {}
        local row = {}
        for i = 1, #C.COPY_FIELDS do
            local k = C.COPY_FIELDS[i]
            row[k] = base[k]
        end
        if row.recipe == nil then row.recipe = recipe end
        if row.spellID == nil then row.spellID = recipe.spellID end
        if row.outputItemID == nil then row.outputItemID = outID end
        if row.prof == nil then row.prof = recipe.prof end
        if row.requiredSkill == nil then row.requiredSkill = recipe.skill end
        if row.name == nil or row.name == "" then row.name = recipe.name or (numeric(outID) and S.itemName(outID)) or "" end

        local moat = nil
        local buyCaps = nil
        if deEligible and numeric(craftCost) and numeric(avgDE) and avgDE > 0 and type(leafReagents) == "table" then
            local econKey = S.resolveEconKey(context)
            moat = VC.EvaluateBuyMoat(leafReagents, craftCost, avgDE, econKey, evalScratch, minDE)
            if type(moat) == "table" and type(moat.reagents) == "table" then
                buyCaps = {}
                for i = 1, #moat.reagents do
                    local rd = moat.reagents[i]
                    if type(rd) == "table" and numeric(rd.itemID) and rd.itemID > 0 then
                        buyCaps[rd.itemID] = {
                            maxBuyUnit = numeric(rd.maxProfitableUnitPrice) and rd.maxProfitableUnitPrice or rd.unitCost,
                            breakEvenUnit = numeric(rd.breakEvenPrice) and rd.breakEvenPrice or nil,
                            wallUnit = numeric(rd.wallUnitPrice) and rd.wallUnitPrice or nil,
                            avgBuyUnit = numeric(rd.avgBuyUnitPrice) and rd.avgBuyUnitPrice or nil,
                            minLotUnit = numeric(rd.minLotPrice) and rd.minLotPrice or nil,
                            maxBuyQty = rd.maxBuyQty,
                            source = "disenchant_crafter",
                        }
                    end
                end
                if next(buyCaps) == nil then buyCaps = nil end
            end
        end

        row.numMade = numMade
        row.minMade = y.baseMin
        row.maxMade = y.baseMax
        row.yieldMin = y.min
        row.yieldAvg = y.avg
        row.yieldMax = y.max
        row.yieldUniformAvg = y.uniformAvg
        row.yieldMeasuredAvg = y.measuredAvg
        row.yieldSamples = y.samples
        row.yieldHist = y.hist
        row.yieldSource = y.source
        row.isVariableYield = y.isVariable
        row.effYield = y.avg
        row.deEligible = deEligible
        row.deReason = deReason
        row.deLearnedCasts = (deEligible and bd and bd.learnedCasts) or 0
        row.dePartialPrice = (deEligible and bd and (bd.missingPriceCount or 0) > 0) and true or false
        row.minDE = minDE
        row.avgDE = avgDE
        row.avgDEBase = baseAvgDE
        row.avgDEAS = asAvgDE
        row.arcaneSalvager = asActive
        row.maxDE = maxDE
        row.deBreakdown = bd
        row.deOutcomes = bd and bd.outcomes or nil
        row.deSummary = (bd and bd.primarySummary) or ""
        row.deIlvl = bd and bd.ilvl or nil
        row.deQuality = bd and bd.quality or nil
        row.isBoP = (recipe.bop == true) or (numeric(outID) and ns.ITEM_BOP and ns.ITEM_BOP[outID] == true) or false
        row.craftCost = craftCost
        row.minProfit = minProfit
        row.avgProfit = avgProfit
        row.maxProfit = maxProfit
        row.marginPct = marginPct
        row.craftBreakdown = craftBreakdown
        row.leafReagents = leafReagents
        row.legacy = legacy
        row.moat = moat
        row.moatScore = moat and moat.score or nil
        row.moatTier = moat and moat.tier or nil
        row.profitableCrafts = moat and moat.profitableCrafts or nil
        row.totalProfitCap = moat and moat.totalProfitCap or nil
        row.totalSpendCap = moat and moat.totalSpendCap or nil
        row.avgSpendPerCraft = moat and moat.avgSpendPerCraft or nil
        row.buyCeiling = moat and moat.lastProfitableCraftCost or nil
        row.stopWallCost = moat and moat.stopWallCraftCost or nil
        row.safeProfitCrafts = moat and moat.safeProfitCrafts or nil
        row.isAllVendor = (moat and moat.isAllVendor == true) or false
        row.reagentBuyCaps = buyCaps

        return row
    end

    function DC.RepairItems(rows, context, legacy, evalScratch, itemIDs)
        if type(rows) ~= "table" or type(itemIDs) ~= "table" then return 0 end
        local expanded, queue = {}, {}
        local anyDEMat = false
        local function enqueue(id)
            if numeric(id) and id > 0 and not expanded[id] then
                expanded[id] = true
                queue[#queue + 1] = id
                if ns.DE_MAT_INFO and ns.DE_MAT_INFO[id] then
                    anyDEMat = true
                end
            end
        end
        for k, v in pairs(itemIDs) do
            if type(v) == "number" then
                enqueue(v)
            elseif v ~= false and v ~= nil and type(k) == "number" then
                enqueue(k)
            end
        end
        if #queue == 0 then return 0 end

        if ns.ClearDECache then ns.ClearDECache() end

        context = (type(context) == "table") and context or {}
        legacy = legacy or VC.ResolveLegacy(context)
        evalScratch = (type(evalScratch) == "table") and evalScratch or {}
        local catalog = (ns.RecipeStats and ns.RecipeStats.GetCatalog and ns.RecipeStats.GetCatalog()) or {}

        local outputsByReagent = {}
        local function indexRecipeReagents(rec)
            if type(rec) ~= "table" then return end
            local outID = rec.outputItemID
            if not numeric(outID) or outID <= 0 then return end
            local reags = (ns.ResolveRecipeReagents and ns.ResolveRecipeReagents(rec)) or rec.reagents
            if type(reags) ~= "table" then return end
            for i = 1, #reags do
                local rg = reags[i]
                local rid = type(rg) == "table" and (rg[1] or rg.itemID or rg.id) or nil
                if numeric(rid) and rid > 0 then
                    local list = outputsByReagent[rid]
                    if not list then
                        list = {}
                        outputsByReagent[rid] = list
                    end
                    list[#list + 1] = outID
                end
            end
        end
        for i = 1, #catalog do
            indexRecipeReagents(catalog[i] and catalog[i].recipe)
        end
        if type(ns.RECIPES_BY_OUTPUT) == "table" then
            for _, list in pairs(ns.RECIPES_BY_OUTPUT) do
                if type(list) == "table" then
                    for i = 1, #list do indexRecipeReagents(list[i]) end
                end
            end
        end

        local head = 1
        while head <= #queue do
            local outs = outputsByReagent[queue[head]]
            if outs then
                for i = 1, #outs do enqueue(outs[i]) end
            end
            head = head + 1
        end

        if type(evalScratch.directCache) == "table" then
            for _, bucket in pairs(evalScratch.directCache) do
                if type(bucket) == "table" then
                    for id in pairs(expanded) do bucket[id] = nil end
                end
            end
        end
        if type(evalScratch.moatItemCache) == "table" then
            for _, byEcon in pairs(evalScratch.moatItemCache) do
                if type(byEcon) == "table" then
                    for id in pairs(expanded) do byEcon[id] = nil end
                end
            end
        end
        if type(evalScratch.subCache) == "table" then
            for _, subBucket in pairs(evalScratch.subCache) do
                if type(subBucket) == "table" then
                    for cacheKey, cached in pairs(subBucket) do
                        local rid = type(cacheKey) == "string" and tonumber(cacheKey:match(":(%d+)$")) or nil
                        local hit = (rid ~= nil and expanded[rid] == true)
                        if not hit and type(cached) == "table" and type(cached.deps) == "table" then
                            for j = 1, #cached.deps do
                                if expanded[cached.deps[j]] then
                                    hit = true
                                    break
                                end
                            end
                        end
                        if hit then subBucket[cacheKey] = nil end
                    end
                end
            end
        end

        local affectedEntries, affectedStubs = {}, {}
        for i = 1, #catalog do
            local entry = catalog[i]
            local rec = entry and entry.recipe
            if type(rec) == "table" and (context.showNonDE == true or not rec.isEnchant) then
                local hit = (rec.outputItemID and expanded[rec.outputItemID]) or (rec.recipeItemID and expanded[rec.recipeItemID])
                if not hit then
                    local reags = (ns.ResolveRecipeReagents and ns.ResolveRecipeReagents(rec)) or rec.reagents
                    if type(reags) == "table" then
                        for j = 1, #reags do
                            local rg = reags[j]
                            local rid = type(rg) == "table" and (rg[1] or rg.itemID or rg.id) or nil
                            if rid and expanded[rid] then
                                hit = true
                                break
                            end
                        end
                    end
                end
                if not hit and anyDEMat and rec.outputItemID and ns.GetItemDEProfile then
                    local mats = ns.GetItemDEProfile(rec.outputItemID)
                    if type(mats) == "table" then
                        for j = 1, #mats do
                            if expanded[mats[j].matID] then
                                hit = true
                                break
                            end
                        end
                    end
                end
                if hit then
                    affectedEntries[#affectedEntries + 1] = entry
                    affectedStubs[#affectedStubs + 1] = { recipe = rec }
                end
            end
        end
        if #affectedEntries == 0 then return 0 end

        local stats = ns.RecipeStats
        if stats and stats.RepairItemsInPlace then
            pcall(stats.RepairItemsInPlace, affectedStubs, context, expanded)
        end

        local posByKey, posByRecipe = {}, {}
        for i = 1, #rows do
            local r = rows[i]
            if type(r) == "table" then
                if r.key ~= nil then posByKey[r.key] = i end
                if r.recipe ~= nil then posByRecipe[r.recipe] = i end
            end
        end

        local changedCount = 0
        local removed = {}
        local batchOpen = false
        if stats and stats.BeginBatch then
            batchOpen = true
            stats.BeginBatch(context)
        end
        local ok, err = pcall(function()
            for i = 1, #affectedEntries do
                local entry = affectedEntries[i]
                local rec = entry.recipe
                local newRow = DC.EvaluateRecipe(rec, context, legacy, evalScratch)
                local keepRow = newRow and (context.onlyProfitable ~= true or (newRow.deEligible ~= false and numeric(newRow.avgProfit) and newRow.avgProfit > 0))
                local existingPos = (entry.key ~= nil and posByKey[entry.key])
                    or (newRow and newRow.key ~= nil and posByKey[newRow.key])
                    or posByRecipe[rec]
                if keepRow then
                    if existingPos then
                        rows[existingPos] = newRow
                        removed[existingPos] = nil
                    else
                        local nextPos = #rows + 1
                        rows[nextPos] = newRow
                        if newRow.key ~= nil then posByKey[newRow.key] = nextPos end
                        if entry.key ~= nil then posByKey[entry.key] = nextPos end
                        posByRecipe[rec] = nextPos
                    end
                    changedCount = changedCount + 1
                elseif existingPos then
                    removed[existingPos] = true
                    changedCount = changedCount + 1
                end
            end
        end)
        if batchOpen and stats and stats.EndBatch then
            pcall(stats.EndBatch)
        end
        if not ok then
            if ns.ResetEval then ns.ResetEval() end
            error(err, 0)
        end

        if next(removed) ~= nil then
            local writeIdx = 0
            for readIdx = 1, #rows do
                if not removed[readIdx] then
                    writeIdx = writeIdx + 1
                    if writeIdx ~= readIdx then rows[writeIdx] = rows[readIdx] end
                end
            end
            for clearIdx = writeIdx + 1, #rows do rows[clearIdx] = nil end
        end

        return changedCount
    end

    function DC.Start(context, onProgress, onComplete, resumeState, onTierReady)
        context = (type(context) == "table") and context or {}
        local catalog = ns.RecipeStats and ns.RecipeStats.GetCatalog and ns.RecipeStats.GetCatalog() or {}
        local legacy = VC.ResolveLegacy(context)
        local sig = buildSignature(context, legacy)
        local datasetKey = (context.dataset ~= nil) and context.dataset or C.DEFAULT_DATASET

        local dsBucket = buildCache[datasetKey]
        if not dsBucket then
            dsBucket = {}
            buildCache[datasetKey] = dsBucket
        end

        local state = nil
        if type(resumeState) == "table" and resumeState.signature == sig and resumeState.catalog == catalog and resumeState.dataset == datasetKey then
            state = resumeState
        elseif dsBucket[sig] and dsBucket[sig].catalog == catalog then
            state = dsBucket[sig]
        end

        if not state then
            if type(resumeState) == "table" and resumeState.cancel then
                resumeState.cancel()
            end
            state = {
                dataset = datasetKey,
                signature = sig,
                catalog = catalog,
                legacy = legacy,
                rows = {},
                evalScratch = {},
                index = 1,
                scanned = 0,
                total = #catalog,
                generation = 0,
                running = false,
                completed = false,
            }
            dsBucket[sig] = state
        end

        local prevOnTierReady = state.onTierReady
        state.onProgress = onProgress
        state.onComplete = onComplete
        state.onTierReady = onTierReady
        state.background = context.background == true
        applyPriority(state, catalog, context.priority)
        if not state.background and state.onTierReady and not prevOnTierReady and state.tier1Authoritative and state.index > state.tier1Target then
            state.tier1Notified = false
        end

        if state.completed then
            if onComplete then onComplete(state.rows) end
            return function() end, state
        end
        if state.running then
            return state.cancel or function() end, state
        end

        state.generation = state.generation + 1
        local token = state.generation
        state.running = true

        local function isCurrent()
            return state.running and state.generation == token
        end
        local function cancel()
            if state.generation == token then
                state.running = false
                state.cancel = nil
                state.generation = token + 1
            end
        end
        state.cancel = cancel

        local defer = context.defer == false and nil or (context.defer or (C_Timer and C_Timer.After and function(fn) C_Timer.After(0, fn) end))
        local stats = ns.RecipeStats
        local total = #catalog
        state.total = total

        local step
        local batchOpen = false
        local stepping, stepAgain = false, false

        local function runStep()
            if not isCurrent() then return end
            if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index > state.tier1Target then
                state.tier1Notified = true
                state.onTierReady(state.rows, state.scanned, total)
                if not isCurrent() then return end
            end
            if state.index <= total then
                local started = clockMS()
                local maxBatch = state.background and 16 or C.MAX_BATCH
                local budgetMS = state.background and 1.2 or C.BUDGET_MS
                if stats and stats.BeginBatch then
                    batchOpen = true
                    stats.BeginBatch(context)
                end
                local count = 0
                repeat
                    if state.index > total then break end
                    local entry = catalog[state.order[state.index]]
                    local rec = entry and entry.recipe
                    if rec then
                        local row = DC.EvaluateRecipe(rec, context, state.legacy, state.evalScratch)
                        if row and (context.onlyProfitable ~= true or (row.deEligible ~= false and numeric(row.avgProfit) and row.avgProfit > 0)) then
                            state.rows[#state.rows + 1] = row
                        end
                    end
                    state.index = state.index + 1
                    state.scanned = state.index - 1
                    count = count + 1
                    if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index > state.tier1Target then break end
                until count >= maxBatch or (clockMS() - started) >= budgetMS

                if batchOpen and stats and stats.EndBatch then
                    stats.EndBatch()
                end
                batchOpen = false
                if not isCurrent() then return end
                if state.onProgress then
                    state.onProgress(state.rows, state.scanned, total)
                end
                if not isCurrent() then return end
            end

            if state.tier1Authoritative and not state.tier1Notified and state.onTierReady and state.index > state.tier1Target then
                state.tier1Notified = true
                if state.index <= total then
                    state.onTierReady(state.rows, state.scanned, total)
                    if not isCurrent() then return end
                end
            end

            if state.index > total then
                state.running = false
                state.cancel = nil
                state.completed = true
                if state.onComplete then
                    state.onComplete(state.rows)
                end
            elseif defer then
                defer(step)
            end
        end

        step = function()
            if stepping then
                stepAgain = true
                return
            end
            stepping = true
            repeat
                stepAgain = false
                local ok, err = pcall(runStep)
                if not ok then
                    stepping = false
                    if state.generation == token then
                        state.running = false
                        state.cancel = nil
                        state.completed = false
                        state.tier1Notified = false
                    end
                    if batchOpen and stats and stats.EndBatch then
                        pcall(stats.EndBatch)
                    end
                    batchOpen = false
                    if ns.ResetEval then ns.ResetEval() end
                    error(err, 0)
                end
            until not stepAgain
            stepping = false
        end

        if defer then
            defer(step)
        else
            repeat step() until not isCurrent()
        end
        return cancel, state
    end

    local function dcRowMatches(row, f, needle, lo, hi)
        if type(row) ~= "table" then return false end
        if f.onlyProfitable == true then
            if row.deEligible == false or not numeric(row.avgProfit) or row.avgProfit <= 0 then
                return false
            end
        end
        if f.showNonDE == false and row.deEligible == false then
            return false
        end
        if not sourceMatchesValues(row.sourceBucket, row.isWrit, f.sources or f.recipeSources) then return false end
        if lo or hi then
            local skill = row.requiredSkill
            if not numeric(skill) or (lo and skill < lo) or (hi and skill > hi) then return false end
        end
        local prof = normalizeProfFilter(f.profFilter or f.prof)
        if prof == "mine_profs" then
            local rec = row.recipe
            if not ((rec and rec.anyChar) or (f.profMap and f.profMap[row.prof])) then return false end
        elseif prof == "others" then
            local rec = row.recipe
            if not (row.prof == "others" or (rec and ns.IsOtherExceptionRecipe and ns.IsOtherExceptionRecipe(rec))) then return false end
        elseif prof ~= "all" and row.prof ~= prof then
            return false
        end
        local known = f.known
        if known == nil and f.knownRecipesOnly then known = "known" end
        if (known == "known" or known == true) and not row.known then return false end
        if (known == "unknown" or known == false) and row.known then return false end
        if f.craftableFilter and f.craftableFilter ~= "all" and ns.MatchesCraftableFilter
            and not ns.MatchesCraftableFilter(row.craftAbility, f.craftableFilter) then
            return false
        end
        if f.unlockFilter and f.unlockFilter ~= "all" and ns.MatchesGlobalFilters
            and not ns.MatchesGlobalFilters(row.prof, row.unlock, "all", f.unlockFilter) then
            return false
        end
        if not S.moatMatches(row, f.moatFilter) then return false end
        if needle ~= "" then
            local blob = row._dcSearchBlob
            if not blob or row._dcSearchBlobName ~= row.name then
                local rec = row.recipe or {}
                local ability = row.craftAbility
                local moat = row.moat
                local parts = {
                    text(row.name),
                    (row.outputItemID and ns.ItemName and text(ns.ItemName(row.outputItemID))) or "",
                    text(row.prof),
                    text(row.sourceLabel),
                    text(row.repLabel),
                    text(row.repFactionName),
                    text(row.deSummary),
                    text(moat and moat.label),
                    text(moat and moat.short),
                    text(rec.name),
                    text(rec.recipeName),
                    text(ability and ability.howDetail),
                }
                if type(row.craftBreakdown) == "table" then
                    for i = 1, #row.craftBreakdown do
                        local rg = row.craftBreakdown[i]
                        if type(rg) == "table" then parts[#parts + 1] = text(rg.name) end
                    end
                end
                if type(row.deOutcomes) == "table" then
                    for i = 1, #row.deOutcomes do
                        local o = row.deOutcomes[i]
                        if type(o) == "table" then parts[#parts + 1] = text(o.name) end
                    end
                end
                blob = table.concat(parts, "\n"):lower()
                row._dcSearchBlob = blob
                row._dcSearchBlobName = row.name
            end
            if not blob:find(needle, 1, true) then return false end
        end
        return true
    end

    function DC.FilterSort(rows, filters, sort, workspace)
        filters = filters or {}
        sort = sort or {}
        workspace = workspace or { values = {}, profs = {}, names = {}, keys = {} }
        local values, profs, names, keys = workspace.values, workspace.profs, workspace.names, workspace.keys
        if not workspace.keepEntries then
            for row in pairs(values) do
                values[row] = nil
                profs[row] = nil
                names[row] = nil
                keys[row] = nil
            end
        end

        local key = sort.key or "avgProfit"
        local isNumeric = DC_NUMERIC_KEYS[key] == true
        local allowHuge = C.HUGE_KEYS[key] == true
        local needle = text(filters.search):lower():match("^%s*(.-)%s*$")
        local lo, hi = Model.SkillBound(filters.skillMin), Model.SkillBound(filters.skillMax)

        local result = {}
        for _, row in ipairs(rows or {}) do
            if dcRowMatches(row, filters, needle, lo, hi) then
                result[#result + 1] = row
                local value = row[key]
                if isNumeric then
                    if not S.sortableNum(value, allowHuge) then value = false end
                else
                    value = text(value)
                end
                values[row] = value
                profs[row] = text(row.prof)
                names[row] = text(row.name)
                keys[row] = text(row.key)
            end
        end

        local ascending = (sort.ascending == true) or (sort.direction == "asc")
        table.sort(result, function(a, b)
            local av, bv = values[a], values[b]
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
            local ap, bp = profs[a], profs[b]
            if ap ~= bp then return ap < bp end
            local an, bn = names[a], names[b]
            if an ~= bn then return an < bn end
            return keys[a] < keys[b]
        end)
        return result
    end

    function DC.OptimizePortfolio(rows, opts)
        return S.optimizePortfolio(rows, opts, "avgDE", "minDE", "maxDE", "disenchant_crafter_plan")
    end
end
