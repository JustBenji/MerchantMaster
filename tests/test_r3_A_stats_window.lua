local S=((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local F=dofile(S..'wp5_fixture.lua')
local ns={RECIPES={},WRITS={},FAVOR_CURRENCY_ID=3402}
local r={name='Favor',prof='alchemy',source='camp',spellID=1,outputItemID=10,skill=75,favorCost=150,recipeVendorPrice=99999}
ns.RECIPES={r}
ns.GetRecipeSourceBucket=function(recipe) return recipe.source=='camp' and 'merchant' or 'vendor' end
ns.BeginEval=function(bank) return bank or {} end
ns.EndEval=function() end
ns.GetRecipeWowheadURL=function() end
ns.BuildRecipeRow=function(recipe) return {name=recipe.name,craftAbility={vendorFavorCost=recipe.favorCost,vendorCopperCost=recipe.recipeVendorPrice},profit=345,sellable=true} end
assert(loadfile(F.addon..'RecipeStats.lua'))('MerchantMaster',ns)
local row=ns.RecipeStats.Get(r,{favorCopper=10})
assert(row.sourceCost.copper==nil and row.sourceCost.currencies[3402]==150,'camp actual cost contains Favor only')
assert(row.buyCostCopper==1500 and row.buyCostEstimated and row.profit==345,'Favor equivalent excludes generic copper; operating profit unchanged')
for _,v in ipairs({0,-1,0/0,math.huge,'bad'}) do
 local got=ns.RecipeStats.Get(r,{favorCopper=v})
 assert(got.buyCostCopper==(v==0 and 0 or nil),'known zero / invalid Favor conversion')
end
assert(ns.RecipeStats.Get(r,{}).buyCostCopper==nil,'missing conversion stays unknown')
local c={favorCopper=5}; assert(ns.RecipeStats.Get(r,c).buyCostCopper==750)
c.favorCopper=20; assert(ns.RecipeStats.Get(r,c).buyCostCopper==3000,'changing conversion invalidates cache')
r={name='Vendor',prof='alchemy',source='vendor',spellID=2,recipeVendorPrice=123}
assert(ns.RecipeStats.Get(r,{}).buyCostCopper==123,'copper-only vendor preserved')
r={name='Synthetic mixed shop',prof='alchemy',source='vendor',spellID=3,recipeVendorPrice=123,favorCost=10}
local mixed=ns.RecipeStats.Get(r,{favorCopper=5})
assert(mixed.sourceCost.copper==123 and mixed.sourceCost.currencies[3402]==10 and mixed.buyCostCopper==173,'explicit non-camp mixed components preserved')
assert(loadfile(F.addon..'UI_Window.lua'))('MerchantMaster',ns)
local tbl={proportional=true,columns={{width=100,minWidth=120},{width=50,minWidth=80}},colX={},headerBar=F.widget(),headerBtns={F.widget(),F.widget()},pool={}}
ns.Window.LayoutTable(tbl,364,1)
assert(tbl.columns[1].width==220 and tbl.columns[2].width==130,'surplus follows stable column weights')
ns.Window.LayoutTable(tbl,214,1)
assert(tbl.columns[1].width==120 and tbl.columns[2].width==80,'shrink restores measured minima')
ns.Window.LayoutTable(tbl,364,1)
assert(tbl.columns[1].width==220 and tbl.columns[2].width==130,'expand/shrink is idempotent')
assert(tbl.colX[2]+tbl.columns[2].width<=364,'last column fits viewport')
local recycled={cells={F.widget(),F.widget()}}; tbl.layoutRow(recycled)
assert(recycled.cells[2].width==130,'recycled geometry matches header')
local db={}; local p=F.widget(UIParent)
local control=ns.Window.Attach(p,nil,nil,{getWindowDB=function() return db end})
control:SetMinimumWidth(1600); control:ApplyFull()
assert(p.width==1600 and db.width==1600,'measured full-window minimum applied')
control:SetCompact(true); p:SetSize(440,520); control:SetMinimumWidth(1700)
assert(p.width==440,'minimum change preserves compact mode')
control:SetCompact(false); control:ApplyFull(); assert(p.width==1700,'minimum retained after compact mode')
print('PASS: R3 A Favor acquisition, conversion, proportional layout and window minimum')
