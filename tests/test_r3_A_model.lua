local addon=(((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local ns={}
assert(loadfile(addon..'SuperListModel.lua'))('MerchantMaster',ns)
local rows={
 {key='a',name='a',prof='alchemy',requiredSkill=1,sourceBucket='merchant',bisSort=100,bisInfo={isBiS=true}},
 {key='b',name='b',prof='alchemy',requiredSkill=75,sourceBucket='vendor',bisSort=2,bisInfo={isBiS=true}},
 {key='c',name='c',prof='alchemy',requiredSkill=76,sourceBucket='merchant',bisSort=9},
 {key='d',name='d',prof='smithing',sourceBucket='merchant'},
}
local n=0
local function count(f,want)
 n=n+1; assert(#ns.SuperListModel.FilterSort(rows,f)==want,'skill filter case '..n)
end
count({skillMin=1,skillMax=75},2)
count({skillMin=75},2)
count({skillMax=75},2)
count({skillMin=75,skillMax=75},1)
count({skillMin=76,skillMax=1},0)
count({},4)
count({skillMin='',skillMax=''},4)
count({skillMin=-1,skillMax=0/0},4)
count({skillMin=1.5,skillMax=math.huge},4)
count({skillMin=1,skillMax=75,sources={merchant=true,vendor=true},profFilter='alchemy',bisOnly=true},2)
count({skillMin=1,skillMax=75,sources={merchant=true},profFilter='alchemy',bisOnly=true},1)
local sorted=ns.SuperListModel.FilterSort(rows,{}, {key='bisSort',ascending=false})
assert(sorted[1].key=='a' and sorted[2].key=='c' and sorted[3].key=='b','Best sorts numerically; unknown last')
print('PASS: R3 A model inclusive/one-sided/invalid/combined bounds and Best ordering')
