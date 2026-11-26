local F = { count = 0 }
function F.check(ok, message) F.count = F.count + 1; assert(ok, message) end
function F.widget(parent)
    local w = { parent = parent, scripts = {}, width = 1320, height = 730, scale = 1, left = 40, top = 1000, shown = true }
    function w:SetScript(k, fn) self.scripts[k] = fn end
    function w:HookScript(k, fn) local old = self.scripts[k]; self.scripts[k] = function(...) if old then old(...) end; fn(...) end end
    function w:Fire(k, ...) if self.scripts[k] then self.scripts[k](self, ...) end end
    function w:SetSize(x,y) local changed = self.width ~= x or self.height ~= y; self.width,self.height=x,y; if changed then self:Fire('OnSizeChanged',x,y) end end
    function w:SetWidth(x) self:SetSize(x,self.height) end
    function w:SetHeight(y) self:SetSize(self.width,y) end
    function w:GetWidth() return self.width end
    function w:GetHeight() return self.height end
    function w:GetScale() return self.scale end
    function w:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
    function w:SetScale(s) self.scale=s end
    function w:GetLeft() return self.left end
    function w:GetTop() return self.top end
    function w:ClearAllPoints() end
    function w:SetPoint(point, relative, relativePoint, x, y) if point == 'TOPLEFT' and relativePoint == 'BOTTOMLEFT' then self.left,self.top=x,y end end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function w:Show() self.shown=true; self:Fire('OnShow') end
    function w:Hide() self.shown=false; self:Fire('OnHide') end
    function w:RegisterForClicks(...) end
    function w:SetText(t) self.text=t end
    function w:SetTextColor(...) self.color={...} end
    function w:SetColorTexture(...) self.color={...} end
    function w:SetAllPoints() end
    function w:GetFrameLevel() return 1 end
    function w:SetFrameLevel() end
    function w:CreateTexture() return F.widget(self) end
    return w
end
UIParent=F.widget(); UIParent.width=2560; UIParent.height=1440
CreateFrame=function(_,_,p) return F.widget(p) end
GameTooltip=F.widget(); GameTooltip.lines={}
function GameTooltip:SetOwner() self.lines={} end
function GameTooltip:AddLine(t) self.lines[#self.lines+1]=t end
function GameTooltip:SetText(t) self.lines={t} end
GameTooltip_Hide=function() GameTooltip:Hide() end
local x,y=0,0
GetCursorPosition=function() return x,y end
function F.cursor(a,b) x,y=a,b end
F.addon=(((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
return F
