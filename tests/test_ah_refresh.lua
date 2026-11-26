local S=((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local F=dofile(S..'wp5_fixture.lua'); local check=F.check; local now=10000; time=function() return now end
GameTooltip.owner=nil; GameTooltip.hidden=true
function GameTooltip:SetOwner(owner) self.owner=owner; self.lines={} end
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:Show() self.hidden=false end
function GameTooltip:Hide() self.hidden=true end
local econ='A'; local scans={A={_scannedAt=9401},B={_scannedAt=8000}}
MerchantMasterDB={ahPrices=scans}; local clicks=0; MerchantMasterAPI={RefreshMarket=function() clicks=clicks+1; return false end}
local ns={CurrentEconomyInfo=function() return {effectiveKey=econ} end,Theme={ASSETS={icon_close='close',icon_refresh='refresh'},CreatePlateButton=function(p)
	local button=F.widget(p)
	function button:CreateTexture()
		local texture=F.widget(self)
		function texture:SetTexture(value) self.texture=value end
		function texture:GetTexture() return self.texture end
		function texture:SetVertexColor(...) self.color={...} end
		function texture:SetRotation(value) self.rotation=value end
		return texture
	end
	return button
end}}
assert(loadfile(F.addon..'UI_AHRefresh.lua'))('MerchantMaster',ns)
local state=ns.AHRefresh.GetFreshness(9401,now); check(state.status=='green' and state.age==599,'599 green')
check(ns.AHRefresh.GetFreshness(9400,now).status=='orange','600 orange'); check(ns.AHRefresh.GetFreshness(8200,now).status=='orange','1800 orange')
check(ns.AHRefresh.GetFreshness(8199,now).status=='red','1801 red')
for _,v in ipairs({false,0,-1,'bad',math.huge,0/0}) do check(ns.AHRefresh.GetFreshness(v,now).status=='red','invalid never red') end
check(ns.AHRefresh.GetFreshness(nil,now).status=='red','missing red'); check(ns.AHRefresh.GetFreshness(now+1,now).status=='red','future timestamp invalid')
local p=F.widget(UIParent); p:Hide(); local c=ns.AHRefresh.Create(p,F.widget(p))
AuctionHouseFrame=F.widget(UIParent); AuctionHouseFrame:Hide()
check(c.button.width==24 and c.button.height==24 and c.button.accessibilityLabel=='Refresh AH','square named button')
check(not c.button.scripts.OnUpdate and clicks==0,'hidden no timer or automatic scan'); p:Show()
check(c.state.status=='green' and c.button.scripts.OnUpdate,'immediate show update')
now=10001; c.button:Fire('OnUpdate',1); check(c.state.status=='orange','visible second boundary')
econ='B'; c:Update(); check(c.state.status=='red','selected economy')
local stamp=scans.B._scannedAt; c.button:Fire('OnClick'); check(clicks==1 and scans.B._scannedAt==stamp and c.state.status=='red','failed click cannot freshen')
check(c.ahNotOpen and c.button.ahNotOpen and c.icon:GetTexture()==ns.Theme.ASSETS.icon_close,'closed AH marks button and uses close icon')
check(c.icon.color[1]==1 and c.icon.color[2]==0.259 and c.icon.width==14,'closed AH cross is red and 14px')
check(GameTooltip.lines[1]=='AH not open' and GameTooltip:GetOwner()==c.button and not GameTooltip.hidden,'closed AH click immediately shows owned tooltip')
scans.B.partial=true; c:Update(); check(c.state.status=='red','partial metadata cannot freshen')
scans.B._scannedAt=now; c:Update(); check(c.state.status=='green' and not c.ahNotOpen and c.icon:GetTexture()==ns.Theme.ASSETS.icon_refresh,'completed full timestamp clears closed AH state')
check(GameTooltip.hidden,'scan timestamp change hides the owned error tooltip')
scans.B._scannedAt=0/0; c:Update(); c.button:Fire('OnClick'); check(c.ahNotOpen and c.icon:GetTexture()==ns.Theme.ASSETS.icon_close,'invalid scanned timestamp does not clear the closed AH cross')
AuctionHouseFrame:Show(); c:Update(); check(not c.ahNotOpen and GameTooltip.hidden,'AH opening clears cross and owned tooltip with invalid scan timestamp')
c.button:Fire('OnEnter'); check(GameTooltip.lines[1]=='Refresh AH','tooltip title'); check(#GameTooltip.lines>=3,'status and timestamp in tooltip')
AuctionHouseFrame:Hide(); c.button:Fire('OnLeave'); c.button:Fire('OnClick')
check(not GameTooltip.hidden and GameTooltip:GetOwner()==c.button,'unhovered closed-AH click owns visible error tooltip')
p:Hide(); check(not c.button.scripts.OnUpdate and GameTooltip.hidden,'panel hide clears timer and owned error tooltip')
now=now+2000; p:Show(); check(c.state.status=='red','show rechecks age')
AuctionHouseFrame:Hide(); c.button:Fire('OnClick'); local otherOwner=F.widget(UIParent)
GameTooltip:SetOwner(otherOwner); GameTooltip:Show(); AuctionHouseFrame:Show(); c:Update()
check(not GameTooltip.hidden and GameTooltip:GetOwner()==otherOwner,'clearing error leaves another owner tooltip visible')
local callsBeforeMissingApi=clicks; MerchantMasterAPI=nil; c.button:Fire('OnClick'); check(clicks==callsBeforeMissingApi,'optional refresh API absent')
issecretvalue=function(v) return type(v)=='table' end; scans.B._scannedAt={}; c:Update(); check(c.state.status=='red','secret scan time ignored')
econ={}; c:Update(); check(c.state.status=='red','secret economy ignored')
local secretInfo=setmetatable({},{__index=function() error('indexed secret info') end})
ns.CurrentEconomyInfo=function() return secretInfo end
c:Update(); check(c.state.status=='red','secret economy info is guarded before indexing')
print('WP5 freshness: '..F.count..' assertions, 0 failures')
