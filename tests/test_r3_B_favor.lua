-- Regression: generic camp metadata and invalid modeled exchange rates cannot inflate acquisition cost.
local addon=(((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local scratch=((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns={}
for _,name in ipairs({'Data_CratesAndWrits.lua','Data_Recipes.lua'}) do
    assert(loadfile(addon..name))('MerchantMaster',ns)
end
local audit=assert(io.open(scratch..'logs/r3_favor_audit.tsv','w'))
audit:write('kind\tprofession\tname\tspellID\trecipeItemID\tfavorCost\tgenericCopper\tclassification\n')
local counts={camp=0,overlap=0,buckets=0,special=0,raw=0}
local campBySpell={}
for _,r in ipairs(ns.RECIPES) do
    if r.source=='camp' or r.acqType=='camp' then
        counts.camp=counts.camp+1; campBySpell[r.spellID]=r
        assert(r.favorCost>0,'every catalog camp recipe has Favor cost')
        if r.recipeVendorPrice and r.recipeVendorPrice>0 then counts.overlap=counts.overlap+1 end
        audit:write(table.concat({'normalized recipe',r.prof,r.name,r.spellID or '',r.recipeItemID or '',r.favorCost,r.recipeVendorPrice or '', 'generic item metadata; not verified shop fee'},'\t')..'\n')
    end
end
for _,bucket in pairs(ns.CAMP_RECIPES_BY_REP) do
    for _,r in ipairs(bucket) do
        counts.buckets=counts.buckets+1
        assert(campBySpell[r.spellID]==r,'reputation bucket points to the catalog recipe')
    end
end
for _,r in ipairs(ns.SPECIAL_REP_UNLOCKS) do
    counts.special=counts.special+1
    assert(r.favorCost>=0 and not r.copper and not r.recipeVendorPrice,'special camp purchase or free quest bonus has no copper fee')
    audit:write(table.concat({'special purchase',r.category,r.name,'',r.itemID,r.favorCost,'','Favor only'},'\t')..'\n')
end
local mp=ns.MP
assert(mp and mp.RECIPES,'Professor raw metadata available')
for prof,recipes in pairs(mp.RECIPES) do
    for _,r in ipairs(recipes) do
        if r.src=='camp' then
            counts.raw=counts.raw+1
            assert(campBySpell[r.s],'raw camp recipe maps to normalized catalog')
            assert(r.fav==campBySpell[r.s].favorCost,'raw and camp Favor charges agree')
        end
    end
end
assert(counts.camp==314 and counts.buckets==314 and counts.raw==314,'complete camp catalog audited')
audit:close()

-- Stub only the upstream row boundary to exercise contradictory actual components too.
ns.GetRecipeSourceBucket=function(r) return r.source=='camp' and 'merchant' or r.source end
ns.BeginEval=function(bank) return bank or {} end
ns.EndEval=function() end
ns.GetRecipeWowheadURL=function() end
ns.ItemName=function(id,fallback) return ns.ITEM_NAMES_BY_ID[id] or fallback end
ns.BuildRecipeRow=function(r)
    return {recipe=r,craftAbility={vendorFavorCost=r.favorCost,vendorCopperCost=r.recipeVendorPrice,
        howCategory=r.source,recipeAHPrice=r.ahPrice},craftCost=300,profit=650,sellable=true}
end
assert(loadfile(addon..'RecipeStats.lua'))('MerchantMaster',ns)
for _,r in pairs(campBySpell) do
    local row=ns.RecipeStats.Get(r,{favorCopper=10})
    assert(row.sourceCost.copper==nil and row.sourceCost.currencies[3402]==r.favorCost,'every catalog camp acquisition is Favor only')
    assert(row.buyCostCopper==r.favorCost*10 and row.buyCostEstimated,'every catalog Buy uses Favor alone')
    assert(row.profit==(r.outputItemID and 650 or nil),'acquisition never changes output profit or makes non-output enchants sellable')
end
local r={name='Camp boundary',source='camp',favorCost=150,recipeVendorPrice=123456,spellID=999001}
local ctx={favorCopper=10}
assert(ns.RecipeStats.Get(r,ctx).buyCostCopper==1500,'generic recipe price excluded')
ctx.favorCopper=20
assert(ns.RecipeStats.Get(r,ctx).buyCostCopper==3000,'changed conversion invalidates cached Buy')
for _,v in ipairs({0,-1,0/0,math.huge,-math.huge,'25',false,1e308}) do
    local row=ns.RecipeStats.Get(r,{favorCopper=v})
    assert(row.buyCostCopper==(v==0 and 0 or nil),'invalid or overflowing conversion stays unknown: '..tostring(v))
    assert(row.buyCostEstimated==(v==0),'estimate marker only when converted amount exists')
end
local routeCalls=0
ns.BuildCrateRows=function() routeCalls=routeCalls+1; return {},{pricePerToken=12} end
assert(ns.RecipeStats.Get(r,{}).buyCostCopper==1800,'missing override uses the evaluated crate route')
for _,v in ipairs({-5,math.huge,1e308}) do
    ns.BuildCrateRows=function() return {},{pricePerToken=v} end
    assert(ns.RecipeStats.Get(r,{}).buyCostCopper==nil,'invalid crate basis is unknown')
end
ns.BuildCrateRows=function() return {} end
assert(ns.RecipeStats.Get(r,{}).buyCostCopper==nil,'absent route remains unknown')
local vendor={name='Copper vendor',source='vendor',recipeVendorPrice=125,spellID=999002}
assert(ns.RecipeStats.Get(vendor,{}).buyCostCopper==125,'copper vendor cost retained')
local mixed={name='Synthetic mixed shop',source='vendor',favorCost=3,recipeVendorPrice=125,spellID=999003}
local row=ns.RecipeStats.Get(mixed,{favorCopper=10})
assert(row.sourceCost.copper==125 and row.buyCostCopper==155,'explicit non-camp mixed source retained')
local ah={name='AH scroll',source='ah',ahPrice=450,spellID=999004}
assert(ns.RecipeStats.Get(ah,{}).buyCostCopper==450,'AH acquisition retained')
print(string.format('PASS: R3 B Favor audit camp=%d metadata_overlap=%d rep_bucket=%d special=%d raw=%d; cost, Profit and conversion boundaries',counts.camp,counts.overlap,counts.buckets,counts.special,counts.raw))
