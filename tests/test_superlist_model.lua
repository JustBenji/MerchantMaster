local scratch = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local addon = (((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local COUNTS = dofile(scratch .. "catalog_counts.lua")
local toc=assert(io.open(addon .. "MerchantMaster.toc","r")); local tocEntries, tocCount = {}, 0
for line in toc:lines() do
    local entry=line:gsub("\r",""):match("^%s*([^#%s].-)%s*$")
    if entry then tocEntries[entry]=true; tocCount = tocCount + 1 end
end
toc:close()
assert(tocCount == COUNTS.tocFiles, "TOC entry count matches catalog_counts: " .. tostring(tocCount))
assert(tocEntries["RecipeStats.lua"] and tocEntries["SuperListModel.lua"], "SuperList TOC entries present")
local ns = dofile(scratch .. "host_fixture.lua")
local TOTAL_RECIPES = #ns.RecipeStats.GetCatalog()
local checks = 0
local function check(ok, message) checks = checks + 1; assert(ok, message) end
local function eq(a, b, message) check(a == b, message .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
check(type(ns.BuildRecipeRow) == "function", "shared single-recipe evaluator exists")
assert(loadfile(addon .. "RecipeStats.lua"))("MerchantMaster", ns)
assert(loadfile(addon .. "SuperListModel.lua"))("MerchantMaster", ns)

-- Verify ns.BuildRecipeRows handles all filter options cleanly and returns 5 values.
for _, opts in ipairs({{}, {profFilter="alchemy"}, {merchantVendorOnly=true},
    {recipeSources={vendor=true, trainer=true}, knownRecipesOnly=true},
    {search="potion", applyAHCut=false}, {sourceFilter="gather"},
    {demandFilter="hot", craftableFilter="yes"}, {sellableFilter="no", bisOnly=true}}) do
    local rows, bestProfitRow, profitableCount, totalMatched, summary = ns.BuildRecipeRows(opts)
    check(type(rows) == "table", "BuildRecipeRows returns rows table")
    check(bestProfitRow == nil or type(bestProfitRow) == "table", "BuildRecipeRows returns optional bestProfitRow")
    check(type(profitableCount) == "number", "BuildRecipeRows returns numeric profitableCount")
    check(type(totalMatched) == "number", "BuildRecipeRows returns numeric totalMatched")
    check(type(summary) == "table", "BuildRecipeRows returns summary table")
end

local complete, progress = nil, 0
local timers = {}
local context = {profMap={}, repState={standing=4}, defer=function(fn) timers[#timers+1]=fn end}
local cancel = ns.SuperListModel.Start(context, function(rows, done, total)
    progress = progress + 1; eq(#rows, done, "progress count"); eq(total, TOTAL_RECIPES, "progress total")
end, function(rows) complete = rows end)
check(type(cancel)=="function", "build returns cancellation")
check(complete == nil, "build yields before completion")
while #timers > 0 do table.remove(timers, 1)() end
eq(#complete, TOTAL_RECIPES, "all recipes without learned professions")
check(progress > 1, "background construction is incremental")
local identities, outputs, duplicate = {}, {}, false
for _, row in ipairs(complete) do
    if row.sourceBucket=='merchant' and row.sourceCost.currencies[ns.FAVOR_CURRENCY_ID] then
        eq(row.sourceCost.copper,nil,'catalog camp Favor has no copper acquisition component')
    end
    check(not identities[row.key], "unique recipe key"); identities[row.key]=true
    eq(row.recipe.spellID, row.spellID, "spell identity")
    eq(row.outputItemID, row.recipe.outputItemID, "output identity")
    eq(row.requiredSkill, row.recipe.skill, "skill identity")
    if row.outputItemID then
        if outputs[row.outputItemID] then duplicate=true end
        outputs[row.outputItemID]=true
    end
end
check(duplicate, "duplicate outputs retained")
local called = false
local stop = ns.SuperListModel.Start(context, function() called=true end, function() called=true end)
stop(); while #timers > 0 do table.remove(timers, 1)() end
check(not called, "cancelled build cannot publish rows")
local ciScale=(os and os.getenv and (os.getenv("CI")=="true" or os.getenv("GITHUB_ACTIONS")=="true")) and 2.5 or 1.0
local originalProfiler=debugprofilestop
debugprofilestop=function() return os.clock()*1000 end
local coldContext={profMap={},repState={standing=4},defer=context.defer}
ns.RecipeStats.Invalidate("catalog")
collectgarbage("collect")
local began=os.clock(); local callbackMax=0
ns.SuperListModel.Start(coldContext,nil,function(rows) complete=rows end)
while #timers>0 do
    local callback=table.remove(timers,1); local before=os.clock(); callback()
    callbackMax=math.max(callbackMax,(os.clock()-before)*1000)
end
local coldMS=(os.clock()-began)*1000
began=os.clock(); ns.SuperListModel.FilterSort(complete); local sortMS=(os.clock()-began)*1000
print(string.format("WP3 MEASURE cold_ms=%.3f callback_max_ms=%.3f filter_sort_ms=%.3f",coldMS,callbackMax,sortMS))
check(callbackMax<=4.000001*ciScale,"build callback budget")
debugprofilestop=originalProfiler

-- Synthetic IDs isolate edge cases while keeping the real shared pricing evaluator.
local save = {}; for _, key in ipairs({"GetDailySold", "GetNumListed", "ComputeSmartCraftCost", "ResolveOutputSaleValuation"}) do save[key]=ns[key] end
ns.GetDailySold = function(id) if id == 80001 then return 14 elseif id == 80002 then return 0 end end
ns.GetNumListed = function() return 10 end
ns.ComputeSmartCraftCost = function(reagents, count) return 600/count, {}, "test premats" end
ns.ResolveOutputSaleValuation = function(id, listed, sellable, cost, cut)
    if not sellable then return {} end
    local price = id == 80001 and 1000 or (id == 80002 and 0 or nil)
    local value = price and price*(cut and .95 or 1)
    return {unitAH=price, ahValue=value, profit=value and value-cost}
end
local rec = {idx=90001, spellID=90001, name="WP3 synthetic", prof="alchemy", skill=20,
    outputItemID=80001, recipeItemID=81001, acqType="camp", source="camp", favorCost=3,
    sellable=true, numMade=2, reagents={},recipeVendorPrice=123456}
local ctx = {profMap={}, repState={standing=4}, ownedCounts={[80001]=8,[81001]=2}, favorCopper=25,
    trainerCosts={}, economy="Normal-Horde", charKey="Normal-Horde-Forever-Test", now=2000000}
local stats = ns.RecipeStats.Get(rec, ctx)
eq(stats.craftCost, 300, "craft cost per output")
eq(stats.profit, 650, "profit per output retains cut and excludes acquisition cost")
eq(stats.ownedOutputQty, 8, "Owned is output count")
eq(stats.ownedScrollQty, 2, "scroll ownership separate")
eq(stats.sourceCost.currencies[ns.FAVOR_CURRENCY_ID], 3, "actual Favor cost")
eq(stats.sourceCost.copper,nil,'generic recipe buy metadata cannot become a camp fee')
eq(stats.buyCostCopper, 75, "Favor copper equivalent")
eq(stats.buyCostEstimated, true, "Favor conversion labelled estimate")
eq(stats.salesPerDay, 14, "Blizzard snapshot fallback")
eq(stats.salesScope, "Blizzard", "Blizzard snapshot scope")
eq(stats.turnoverPerDay, 14000, "estimated gross turnover")
eq(stats.sellerStatus, "unavailable", "unknown sellers distinct from zero")
eq(stats.wowheadURL, ns.GetRecipeWowheadURL(rec), "Wowhead scroll URL")
eq(ns.RecipeStats.Get(rec, ctx), stats, "same context cached")
ns.RecipeStats.Invalidate("prices")
check(ns.RecipeStats.Get(rec,ctx) ~= stats, "explicit invalidation rebuilds")
ctx.favorCopper=nil
local oldCrate=ns.BuildCrateRows
ns.BuildCrateRows=function() return {} end
eq(ns.RecipeStats.Get(rec,ctx).buyCostCopper, nil, "unknown Favor conversion never zero")
ns.BuildCrateRows=function() return {}, {pricePerToken=40} end
ns.RecipeStats.Invalidate("Favor")
eq(ns.RecipeStats.Get(rec,ctx).buyCostCopper,120,"existing crate Favor valuation reused")
ns.BuildCrateRows=oldCrate
rec = {idx=90002, spellID=90002, name="WP3 trainer", prof="alchemy", skill=30, outputItemID=80002,
    acqType="trainer", sellable=true, numMade=1, reagents={}}
ctx.trainerCosts[rec.name]=0
stats=ns.RecipeStats.Get(rec,ctx)
eq(stats.buyCostCopper,0,"known free trainer fee")
eq(stats.unitAH,0,"zero price is not unknown")
eq(stats.salesPerDay,0,"zero regional velocity preserved")
eq(stats.turnoverPerDay,0,"zero revenue known")
ctx.trainerCosts[rec.name]=123; ns.RecipeStats.Invalidate("trainer")
eq(ns.RecipeStats.Get(rec,ctx).buyCostCopper,123,"cached live trainer fee")
rec.outputItemID=80003; ns.RecipeStats.Invalidate("item")
stats=ns.RecipeStats.Get(rec,ctx)
eq(stats.unitAH,nil,"missing price unknown"); eq(stats.salesPerDay,nil,"missing sales unknown")
eq(stats.turnoverPerDay,nil,"unknown turnover")
rec.sellable=false; ns.RecipeStats.Invalidate("binding")
stats=ns.RecipeStats.Get(rec,ctx)
eq(stats.unitAH,nil,"BoP has no market price"); eq(stats.salesPerDay,nil,"BoP has no sales rate")
rec.outputItemID=nil; rec.isEnchant=true; ns.RecipeStats.Invalidate("enchant")
eq(ns.RecipeStats.Get(rec,ctx).sellable,false,"enchant retained but not tradeable")

-- Analytics is queried once per covered economy, using AH outcomes only.
rec.outputItemID=80001; rec.isEnchant=nil; rec.sellable=true
local originalAnalytics=ns.Analytics
local modelCalls=0
local ledger={stats={firstLive={[ctx.charKey]=ctx.now-8*86400}}}
ns.Analytics={Store={db=ledger, DayKey=function(t) return math.floor(t/86400) end,
    DeriveEcon=function(c) return c:match("^([^%-]+%-[^%-]+)") end}, Model={Compute=function(view,filters)
        modelCalls=modelCalls+1; eq(view,"items","Analytics items consumer")
        eq(filters.char,"all","all characters"); eq(filters.econ,ctx.economy,"economy scope"); eq(filters.source,"AH","AH-only channel purity")
        return {rows={{itemID=80001,sold=14,velocity=2,isSlowing=true},{itemID=80002,sold=0,expired=0,velocity=0},{itemID=80004,expired=2,sold=0,velocity=0}}}
    end}}
ns.RecipeStats.Invalidate("ledger")
stats=ns.RecipeStats.Get(rec,ctx)
eq(stats.salesPerDay,2,"covered personal seven-day velocity")
eq(stats.salesScope,"Personal","personal scope")
eq(stats.salesWindowDays,7,"personal window")
eq(stats.coverageStart,ledger.stats.firstLive[ctx.charKey],"tracking coverage")
eq(stats.isSlowing,true,"slowing independent of heat")
eq(stats.turnoverPerDay,2000,"turnover uses selected velocity")
local emptyRec={idx=90003,spellID=90003,name="No observed sales",prof="alchemy",skill=1,outputItemID=80002,sellable=true,reagents={}}
stats=ns.RecipeStats.Get(emptyRec,ctx)
eq(stats.salesPerDay,0,"untested item preserves snapshot zero")
eq(stats.salesScope,"Blizzard","untested item retains Blizzard scope"); local expiredRec={idx=90004,spellID=90004,name="Expired AH test",prof="alchemy",outputItemID=80004,sellable=true,reagents={}}; stats=ns.RecipeStats.Get(expiredRec,ctx); eq(stats.salesPerDay,0,"real expirations retain zero"); eq(stats.salesScope,"Personal","real expirations use personal scope")
eq(modelCalls,1,"one ledger computation for multiple recipes")
ns.Analytics.Store.readOnly=true; ns.RecipeStats.Invalidate("future schema")
eq(ns.RecipeStats.Get(rec,ctx).salesScope,"Blizzard","read-only future schema cannot assert coverage")
ns.Analytics.Store.readOnly=false
ledger.stats.disabled={MAIL=true}; ns.RecipeStats.Invalidate("disabled capture")
eq(ns.RecipeStats.Get(rec,ctx).salesScope,"Blizzard","disabled sale capture cannot assert coverage")
ledger.stats.disabled={}
ctx.charKey="Normal-Horde-Forever-Other"
eq(ns.RecipeStats.Get(rec,ctx).salesScope,"Personal","same economy shares covered AH outcomes")
ctx.charKey="Normal-Horde-Forever-Test"
ledger.stats.firstLive[ctx.charKey]=ctx.now-7*86400+1
ns.RecipeStats.Invalidate("coverage boundary")
eq(ns.RecipeStats.Get(rec,ctx).salesScope,"Blizzard","one second short of covered week")
ctx.now=ctx.now+1
eq(ns.RecipeStats.Get(rec,ctx).salesScope,"Personal","coverage threshold invalidates cached snapshot rows")
ledger.stats.firstLive[ctx.charKey]=ctx.now-86400; ns.RecipeStats.Invalidate("coverage")
eq(ns.RecipeStats.Get(rec,ctx).salesScope,"Blizzard","short coverage falls back")
ctx.economy="Hardcore-Horde"
eq(ns.RecipeStats.Get(rec,ctx).salesScope,"Blizzard","another economy cannot reuse personal sales")
ns.Analytics=originalAnalytics
for k,v in pairs(save) do ns[k]=v end

-- Spell-first Writ membership; output fallback records its evidence and profession.
local catalogRecipes,catalogWrits=ns.RECIPES,ns.WRITS
local r1={idx=1,spellID=1,outputItemID=100,prof="alchemy"}
local r2={idx=2,spellID=2,outputItemID=100,prof="alchemy"}
local r3={idx=3,spellID=3,outputItemID=200,prof="alchemy"}
local r4={idx=4,spellID=4,outputItemID=200,prof="cooking"}
ns.RECIPES={r1,r2,r3,r4}
ns.WRITS={{spellID=1,requiredItemID=100,prof="alchemy"},{spellID=999,requiredItemID=200,prof="alchemy"}}
ns.RecipeStats.Invalidate("catalog")
local catalog=ns.RecipeStats.GetCatalog()
eq(catalog[1].isWrit,true,"exact Writ spell")
eq(catalog[2].isWrit,false,"same output does not override exact Writ spell")
eq(catalog[3].isWrit,true,"documented Writ output fallback")
eq(catalog[3].writMatch,"requiredItemID (no catalog spell match)","fallback provenance")
eq(catalog[4].isWrit,false,"fallback respects profession")
ns.RECIPES=catalogRecipes; ns.WRITS=catalogWrits; ns.RecipeStats.Invalidate("catalog")

local rows={
 {key="a",prof="alchemy",name="Same",profit=10,sourceBucket="vendor",isWrit=true,known=true},
 {key="b",prof="alchemy",name="Same",profit=10,sourceBucket="trainer",known=false},
 {key="c",prof="cooking",name="Cold",profit=nil,sourceBucket="ah",known=false},
 {key="d",prof="alchemy",name="Free",profit=0,sourceBucket="vendor",known=false}}
local model=ns.SuperListModel
local ordered=model.FilterSort(rows)
eq(ordered[1].key,"a","stable profit tie"); eq(ordered[2].key,"b","second stable tie")
eq(ordered[4].key,"c","unknown last descending")
ordered=model.FilterSort(rows,{}, {key="profit",ascending=true})
eq(ordered[1].key,"d","ascending numeric"); eq(ordered[4].key,"c","unknown last ascending")
eq(rows[1].key,"a","sort preserves input")
eq(#model.FilterSort(rows,{sources={vendor=true,writ=true}}),2,"Writ/vendor OR union without duplicates")
eq(#model.FilterSort(rows,{sources={trainer=true,writ=true},known="unknown",search="same"}),1,"source OR combines with known/search AND")
eq(#model.FilterSort(rows,{sources={writ=true}}),1,"Writ only filter")
eq(#model.FilterSort(rows,{sources={writ=true},profFilter="cooking"}),0,"profession AND source")
eq(#model.FilterSort(rows,{sources={all=true}}),4,"all sources")
eq(#model.FilterSort(rows,{sources={},merchantVendorOnly=true}),4,"legacy hidden filter cannot restrict model rows")
eq(#model.FilterSort(rows,{known=false}),3,"boolean unknown status excludes learned recipes")
local secret={}; local originalSecret=issecretvalue
issecretvalue=function(v) return rawequal(v,secret) end
rows[3].profit=secret
eq(model.FilterSort(rows)[4].key,"c","secret numeric sort unknown")
ctx.favorCopper=secret
ns.RecipeStats.Invalidate("secret")
check(pcall(ns.RecipeStats.Get,rec,ctx),"secret optional value guarded")
issecretvalue=originalSecret

-- Priority queue, unlockFilter mine_profs parity, background Tier-1 latch, and VendorCrafterModel contracts.
do
    local catalog = ns.RecipeStats.GetCatalog()
    local mockProfs = { alchemy = 300, enchanting = 300 }
    local alchCount, enchCount, tailCount, anyCharNonMine = 0, 0, 0, 0
    for _, entry in ipairs(catalog) do
        local r = entry.recipe
        if r.prof == "alchemy" then alchCount = alchCount + 1
        elseif r.prof == "enchanting" then enchCount = enchCount + 1
        elseif r.prof == "tailoring" then tailCount = tailCount + 1 end
        if r.anyChar and not mockProfs[r.prof] then anyCharNonMine = anyCharNonMine + 1 end
    end

    -- Normalized profFilter casing & whitespace
    local normOrder = model.BuildPriorityOrder(catalog, { profFilter = "  Tailoring ", profMap = mockProfs, key = "norm_tail" })
    for i = 1, tailCount do
        eq(catalog[normOrder[i]].recipe.prof, "tailoring", "normalized profFilter puts tailoring first at " .. i)
    end
    for i = tailCount + 1, tailCount + alchCount + enchCount do
        local p = catalog[normOrder[i]].recipe.prof
        check(p == "alchemy" or p == "enchanting", "Tier 2 after normalized tailoring is my profs at " .. i)
    end
    eq(#model.FilterSort(rows, { profFilter = "  ALCHEMY " }), 3, "FilterSort normalizes mixed-case profFilter")

    -- Pricing.MatchesGlobalFilters treats unlockFilter == "mine_profs" identically to "applies"
    check(ns.MatchesGlobalFilters("tailoring", { anyProfLearned = true, hasProf = false }, "all", "mine_profs") == false,
        "MatchesGlobalFilters excludes unlearned prof under unlockFilter=mine_profs")
    check(ns.MatchesGlobalFilters("alchemy", { anyProfLearned = true, hasProf = true }, "all", "mine_profs") == true,
        "MatchesGlobalFilters includes learned prof under unlockFilter=mine_profs")
    check(ns.MatchesGlobalFilters("tailoring", { anyProfLearned = false, hasProf = false }, "all", "mine_profs") == true,
        "MatchesGlobalFilters allows all when no profs learned under unlockFilter=mine_profs")

    -- unlockFilter mine_profs / knownRecipesOnly narrows Tier 1 to my profs when profFilter == "all"
    for _, pSpec in ipairs({
        { profFilter = "all", unlockFilter = "mine_profs", profMap = mockProfs, key = "u_mine" },
        { profFilter = "all", unlockFilter = "applies", profMap = mockProfs, key = "u_applies" },
        { profFilter = "all", unlockFilter = "known", knownRecipesOnly = true, profMap = mockProfs, key = "u_known" },
        { profFilter = "all", unlockFilter = "unlocked", profMap = mockProfs, key = "u_unlocked" },
    }) do
        local tQ, readyDone, readyCount = {}, 0, 0
        local _, st = model.Start(
            { dataset = pSpec.key, priority = pSpec, defer = function(fn) tQ[#tQ + 1] = fn end },
            nil, nil, nil,
            function(_, done) readyCount = readyCount + 1; readyDone = done end
        )
        while #tQ > 0 do table.remove(tQ, 1)() end
        eq(readyCount, 1, pSpec.key .. " fires onTierReady once")
        eq(readyDone, alchCount + enchCount + anyCharNonMine, pSpec.key .. " fires onTierReady right after my profs + anyChar")
        check(st.tier1Authoritative == true, pSpec.key .. " marks tier1Authoritative true")
    end

    -- Fallback profMap orders Tier 2 my profs first without marking mine_profs authoritative
    do
        local fbQ, fbReady = {}, 0
        local _, fbState = model.Start(
            {
                dataset = "fb_mine",
                priority = { profFilter = "all", unlockFilter = "mine_profs", profMap = mockProfs, profMapFallback = true, key = "fb_mine" },
                defer = function(fn) fbQ[#fbQ + 1] = fn end,
            },
            nil, nil, nil,
            function() fbReady = fbReady + 1 end
        )
        while #fbQ > 0 do table.remove(fbQ, 1)() end
        eq(fbReady, 0, "fallback profMap does not prematurely declare mine_profs tier1Authoritative")
        for i = 1, alchCount + enchCount do
            local p = catalog[fbState.order[i]].recipe.prof
            check(p == "alchemy" or p == "enchanting", "fallback profMap still evaluates my profs first at " .. i)
        end
    end

    -- Background Tier-1 completion (onTierReady == nil) must NOT swallow tier1Notified when attaching foreground
    do
        local bgQ = {}
        local bgCtx = {
            dataset = "bg_tier1_latch",
            background = true,
            priority = { profFilter = "tailoring", profMap = mockProfs, key = "bg_tail" },
            defer = function(fn) bgQ[#bgQ + 1] = fn end,
        }
        local _, bgState = model.Start(bgCtx, nil, nil, nil, nil)
        while #bgQ > 0 and bgState.index <= bgState.tier1Target + 10 do
            table.remove(bgQ, 1)()
        end
        check(bgState.index > bgState.tier1Target and not bgState.completed, "background progressed past Tier-1 boundary")
        check(bgState.tier1Notified == false, "background run without onTierReady does not latch tier1Notified")
        local fgTierReady = 0
        model.Attach(bgState, false, bgCtx.priority, nil, nil, function() fgTierReady = fgTierReady + 1 end)
        while #bgQ > 0 do table.remove(bgQ, 1)() end
        eq(fgTierReady, 1, "attaching foreground onTierReady after background Tier-1 fires immediately once")
    end

    -- VendorCrafterModel: priority queue, mid-scan reprioritization, signature stability, and RepairItems
    do
        local VC = ns.VendorCrafterModel
        check(type(VC.BuildPriorityOrder) == "function" and type(VC.Reprioritize) == "function"
            and type(VC.Attach) == "function" and type(VC.RepairItems) == "function",
            "VendorCrafterModel exposes priority and RepairItems APIs")

        local vcOrder = VC.BuildPriorityOrder(catalog, { profFilter = "tailoring", profMap = mockProfs, key = "vc_tail" })
        eq(#vcOrder, #catalog, "VC.BuildPriorityOrder covers full catalog")
        for i = 1, tailCount do
            eq(catalog[vcOrder[i]].recipe.prof, "tailoring", "VC Tier 1 is tailoring at " .. i)
        end
        for i = tailCount + 1, tailCount + alchCount + enchCount do
            local p = catalog[vcOrder[i]].recipe.prof
            check(p == "alchemy" or p == "enchanting", "VC Tier 2 is my profs at " .. i)
        end

        -- VC.Start respects priority, fires onTierReady, and reprioritizes mid-scan with 0 duplicates
        local vcSeen, vcEvalOrder = {}, {}
        local origVCEval = VC.EvaluateRecipe
        VC.EvaluateRecipe = function(r, ...)
            vcSeen[r] = (vcSeen[r] or 0) + 1
            vcEvalOrder[#vcEvalOrder + 1] = r.prof
            return origVCEval(r, ...)
        end
        local vcQ, vcTierCount, vcTierScanned, vcDone = {}, 0, 0, nil
        local vcCtx = {
            dataset = "vc_prio_test",
            profMap = { alchemy = 280, enchanting = 300 },
            priority = { profFilter = "alchemy", profMap = { alchemy = 280, enchanting = 300 }, key = "vc_alch" },
            defer = function(fn) vcQ[#vcQ + 1] = fn end,
        }
        local _, vcState = VC.Start(vcCtx, nil, function(r) vcDone = r end, nil, function(_, scanned)
            vcTierCount = vcTierCount + 1
            vcTierScanned = scanned
        end)
        -- Step partially then reprioritize to tailoring
        table.remove(vcQ, 1)()
        check(vcState.scanned > 0 and vcState.scanned < #catalog, "VC partial scan before mid-scan reprioritize")
        for i = 1, #vcEvalOrder do eq(vcEvalOrder[i], "alchemy", "VC initial slice evaluated alchemy first") end
        VC.Reprioritize(vcState, { profFilter = "tailoring", profMap = { alchemy = 280, enchanting = 300 }, key = "vc_tail2" })
        while #vcQ > 0 do table.remove(vcQ, 1)() end
        eq(vcTierCount, 1, "VC fired onTierReady once after reprioritized Tier 1 finished")
        check(vcTierScanned > 0 and vcTierScanned < #catalog, "VC onTierReady fired before full catalog finished")
        check(vcDone ~= nil and vcState.completed == true, "VC completed after reprioritization")
        for _, entry in ipairs(catalog) do
            eq(vcSeen[entry.recipe], 1, "VC evaluated every recipe exactly once after mid-scan reprioritization")
        end

        -- Signature stability: rank bump & knownRecipesOnly & non-yield accountingVersion do NOT reset buildState
        local origStore = ns.Analytics and ns.Analytics.Store
        local mockStore = { accountingVersion = 10, _trackedAccountingVersion = 10, craftYieldVersion = 1 }
        if ns.Analytics then ns.Analytics.Store = mockStore end
        VC.ClearCache()
        local baseCtx = { dataset = "vc_sig", profMap = { alchemy = 280 }, knownRecipesOnly = false, defer = function(fn) vcQ[#vcQ + 1] = fn end }
        local _, st1 = VC.Start(baseCtx)
        table.remove(vcQ, 1)()
        local scanned1 = st1.scanned
        -- Rank bump + knownRecipesOnly flip + non-yield accountingVersion (craftYieldVersion unchanged, _trackedAccountingVersion updated)
        mockStore.accountingVersion = 15
        mockStore._trackedAccountingVersion = 15
        local sameCtx = { dataset = "vc_sig", profMap = { alchemy = 310 }, knownRecipesOnly = true, defer = function(fn) vcQ[#vcQ + 1] = fn end }
        local _, st2 = VC.Start(sameCtx, nil, nil, st1)
        check(st2 == st1 and st2.scanned == scanned1, "VC signature ignores rank bump, knownRecipesOnly, and non-yield accountingVersion")
        -- Adding a new profession key DOES create a new state
        local newProfCtx = { dataset = "vc_sig", profMap = { alchemy = 310, tailoring = 1 }, defer = function(fn) vcQ[#vcQ + 1] = fn end }
        local _, st3 = VC.Start(newProfCtx, nil, nil, st1)
        check(st3 ~= st1, "VC signature invalidates when a new profession key is learned")
        if st3.cancel then st3.cancel() end
        -- Incrementing craftYieldVersion DOES create a new state
        mockStore.craftYieldVersion = 2
        local _, st4 = VC.Start(sameCtx, nil, nil, st1)
        check(st4 ~= st1, "VC signature invalidates when craftYieldVersion increments")
        if st4.cancel then st4.cancel() end
        vcQ = {}
        if ns.Analytics then ns.Analytics.Store = origStore end
        VC.EvaluateRecipe = origVCEval

        -- VC.RepairItems updates/inserts/removes affected rows in place without full rebuild
        local targetEntry
        for _, entry in ipairs(catalog) do
            local r = entry.recipe
            if r and not r.isEnchant and r.outputItemID and r.outputItemID > 0 and r.reagents and #r.reagents > 0 then
                targetEntry = entry
                break
            end
        end
        check(targetEntry ~= nil, "found real catalog recipe for VC.RepairItems test")
        local outID = targetEntry.recipe.outputItemID
        local origSellFn, origMktFn = ns.GetVendorSellPrice, ns.GetItemMarketPrice
        local mockSell = 500000
        ns.GetVendorSellPrice = function(id) if id == outID then return mockSell end return origSellFn(id) end
        ns.GetItemMarketPrice = function(id) return 10, "mock" end
        local repScratch = {}
        local repCtx = { profMap = mockProfs, economy = "Normal-Horde" }
        local repRows = {}
        local c1 = VC.RepairItems(repRows, repCtx, nil, repScratch, { [outID] = true })
        check(c1 >= 1 and #repRows >= 1, "VC.RepairItems inserts newly profitable row")
        local foundRow
        for _, r in ipairs(repRows) do if r.key == targetEntry.key then foundRow = r; break end end
        check(foundRow ~= nil and foundRow.unitVendorSell == 500000, "VC.RepairItems inserted row with fresh vendorSell")
        mockSell = 1
        local c2 = VC.RepairItems(repRows, repCtx, nil, repScratch, { [outID] = true })
        check(c2 >= 1, "VC.RepairItems detects unprofitable row change")
        local stillThere = false
        for _, r in ipairs(repRows) do if r.key == targetEntry.key then stillThere = true; break end end
        check(not stillThere, "VC.RepairItems removes row that became unprofitable")
        ns.GetVendorSellPrice, ns.GetItemMarketPrice = origSellFn, origMktFn
    end

    -- RecipeStats Y/G/Gr threshold coverage from ns.MP (RECIPE_BY_SPELL / RECIPES_BY_SPELL)
    do
        local statsCtx = {
            economy = "Normal-Horde",
            profMap = { alchemy = 300, engineering = 300 },
            ownedCounts = {},
            ownedCountsByID = {},
            knownSpells = {},
            knownOutputs = {},
            knownNames = {},
            scannedProfs = {},
            repState = {},
            trainerCosts = {},
        }
        local withThresholds, validOrder = 0, 0
        for _, entry in ipairs(catalog) do
            local r = ns.RecipeStats.Get(entry.recipe, statsCtx)
            if type(r.skillYellow) == "number" and type(r.skillGreen) == "number" and type(r.skillGray) == "number" then
                withThresholds = withThresholds + 1
                if r.skillYellow <= r.skillGreen and r.skillGreen <= r.skillGray and r.skillupSort == r.skillGray then
                    validOrder = validOrder + 1
                end
            end
        end
        check(withThresholds >= 2100, "RecipeStats populates Y/G/Gr thresholds across catalog (got " .. tostring(withThresholds) .. ")")
        check(validOrder == withThresholds, "RecipeStats Y <= G <= Gr and skillupSort==Gr holds for all thresholded recipes")
    end
end
print("WP3 model: " .. checks .. " assertions, 0 failures")
