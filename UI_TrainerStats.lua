-- Selected profession recipe economics, using the same evaluator as the Super List.
local _, ns = ...
local UI = {}; ns.TrainerStats = UI
local open, pending, getContext, invalidatePending
local defaultContext = {}
local WIDTH, HEIGHT, GAP = 268, 312, 8
local function readable(v)
    return not (issecretvalue and issecretvalue(v)) and not (type(v)=="table" and issecrettable and issecrettable(v))
end
local function text(v) if readable(v) and type(v)=="string" then return v end end
local function tableValue(v) if readable(v) and type(v)=="table" then return v end end
local function number(v)
    if readable(v) and type(v)=="number" and v==v and v>-math.huge and v<math.huge then return v end
end
local function read(fn,...)
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...); if ok then return value end
end
local function money(v,signed)
    v=number(v); if not v then return "n/a" end
    if type(ns.FormatMoneyCompact)=='function' then return ns.FormatMoneyCompact(v,signed) end
    local amount=math.floor(math.abs(v)+0.5)
    return string.format("%s%dg %ds %dc",v<0 and "-" or "",math.floor(amount/10000),math.floor(amount/100)%100,amount%100)
end
local function getPalette()
    local T = ns.Theme
    local active = T and T.GetActivePalette and T.GetActivePalette()
    if active then return active end
    if T and T.PALETTES and T.GetMode then
        return T.PALETTES[T.GetMode()] or T.PALETTES.dark
    end
    return nil
end

local function resolveFallbackFont(weight)
    local T = ns.Theme
    if type(T) == "table" then
        if type(T.ResolveFontPath) == "function" then
            return T.ResolveFontPath(weight)
        end
        if type(T.FONTS) == "table" then
            local wantBold = (weight == "semibold" or weight == "bold" or weight == "heavy")
            return (wantBold and T.FONTS.semibold) or T.FONTS.regular or T.FONTS.fallback
        end
    end
    return STANDARD_TEXT_FONT or "Fonts\\ARIALN.TTF"
end

local function applyFont(fs, size, weight, flags)
    if type(fs) ~= "table" then return end
    local T = ns.Theme
    if T and T.ApplyFont then
        T.ApplyFont(fs, size, weight, flags)
        return
    end
    if fs.SetFont then
        local target = resolveFallbackFont(weight)
        local sz = tonumber(size) or 12
        local fl = flags or ""
        local ok = fs:SetFont(target, sz, fl)
        local loaded = fs.GetFont and select(1, fs:GetFont())
        if ok == false or (ok == nil and loaded ~= target) then
            fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\ARIALN.TTF", sz, fl)
        end
    end
    if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
end

local function applyTheme()
    local frame = UI.frame
    if not frame then return end
    local pal = getPalette()
    if not pal then
        if frame._mmFallbackFill and frame._mmFallbackFill.SetColorTexture then
            frame._mmFallbackFill:SetColorTexture(0.173, 0.173, 0.180, 0.98)
        end
        return
    end
    if frame._mmGlass then
        local bg = pal.cardBg or pal.winBg or { 0.173, 0.173, 0.180, 0.98 }
        if frame._mmGlass.SetFill then
            frame._mmGlass:SetFill(bg)
        elseif frame._mmGlass.fill and frame._mmGlass.fill.SetColor then
            frame._mmGlass.fill:SetColor(bg[1], bg[2], bg[3], bg[4] or 0.98)
        end
    end
    if UI.hdrSep and UI.hdrSep.SetColorTexture and pal.separator then
        UI.hdrSep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.65)
    end
    if UI.title and UI.title.SetTextColor and pal.text then
        UI.title:SetTextColor(pal.text[1], pal.text[2], pal.text[3], 1)
    end
    if UI.body and UI.body.SetTextColor and pal.textSecondary then
        UI.body:SetTextColor(pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1)
    end
    if UI.subTitle and UI.subTitle.SetTextColor and pal.textMuted then
        UI.subTitle:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1)
    end
end

function UI.Clear()
    UI.service,UI.stats=nil,nil
    if UI.frame then
        UI.title:SetText("")
        UI.body:SetText("")
        if UI.learnPill and UI.learnPill.frame and UI.learnPill.frame.Hide then UI.learnPill.frame:Hide() end
        if UI.costPill and UI.costPill.frame and UI.costPill.frame.Hide then UI.costPill.frame:Hide() end
        UI.frame:Hide()
    end
end
local function closed()
    open=false;pending=nil;invalidatePending=nil;UI.Clear()
end
local function bounds(frame)
    if not frame or not frame.GetLeft or not frame.GetEffectiveScale then return end
    local left,right=number(read(frame.GetLeft,frame)),number(read(frame.GetRight,frame))
    local top,bottom=number(read(frame.GetTop,frame)),number(read(frame.GetBottom,frame))
    local scale=number(read(frame.GetEffectiveScale,frame))
    if left and right and top and bottom and scale and scale>0 then return left*scale,right*scale,top*scale,bottom*scale end
end
local function anchor()
    local frame,parent=UI.frame,ClassTrainerFrame
    local left,right,top,_=bounds(parent)
    local screenLeft,screenRight=bounds(UIParent)
    local scale=number(read(frame.GetEffectiveScale,frame)) or 1
    local width,gap=WIDTH*scale,GAP*scale
    local function occupied(x1,x2)
        for _,root in ipairs({UIParent,parent}) do
            if root.GetChildren then
                for _,other in ipairs({root:GetChildren()}) do
                    if other~=parent and other~=frame and other.IsShown and other:IsShown() then
                        local l,r,t,b=bounds(other)
                        -- UIParent has full-screen layout containers, not just visible docks.
                        if l and not (l<=left and r>=right) and l<x2 and r>x1 and b<top and t>top-HEIGHT*scale then return true end
                    end
                end
            end
        end
        return false
    end
    frame:ClearAllPoints()
    if left and screenLeft then
        if right+gap+width<=screenRight and not occupied(right+gap,right+gap+width) then
            frame:SetPoint("TOPLEFT",parent,"TOPRIGHT",GAP,-24)
        elseif left-gap-width>=screenLeft and not occupied(left-gap-width,left-gap) then
            frame:SetPoint("TOPRIGHT",parent,"TOPLEFT",-GAP,-24)
        else frame:SetPoint("TOPLEFT",parent,"BOTTOMLEFT",0,-GAP) end
    else frame:SetPoint("TOPLEFT",parent,"TOPRIGHT",GAP,-24) end
end
local function render(service,stats)
    local velocity=number(stats.salesPerDay)
    local scope=text(stats.salesScope)
    local window=number(stats.salesWindowDays)
    local sales="n/a (unknown)"
    if velocity and velocity>=0 then
        sales=string.format("%.2f",velocity) .. " (" .. (scope or "Unknown")
        if window and window>0 then sales=sales .. string.format(", %dd",window) end
        sales=sales .. ")"
    end
    local demand=tableValue(stats.demand)
    local heat=demand and (text(demand.heatShort) or text(demand.label) or text(demand.tierKey)) or "n/a"
    local lines={"Profit / output: " .. money(stats.profit),"Craft cost / output: " .. money(stats.craftCost),
        "AH / output: " .. money(stats.unitAH),"Sales/day: " .. sales,"Heat: " .. heat}
    if number(stats.turnoverPerDay) then lines[#lines+1]="Turnover/day: " .. money(stats.turnoverPerDay) end
    local bis=tableValue(stats.bisInfo)
    if bis and readable(bis.hasEval) and bis.hasEval and text(bis.cellText) and bis.cellText~="" then
        lines[#lines+1]="Best in class: " .. bis.cellText
    end
    if number(stats.ownedOutputQty) then lines[#lines+1]="Owned output: " .. tostring(stats.ownedOutputQty) end
    local cost,profit=number(service.cost),number(stats.profit)
    if cost and cost>0 and profit and profit>0 then
        lines[#lines+1]="Payback: " .. math.ceil(cost/profit) .. " crafts"
    end
    lines[#lines+1]="";lines[#lines+1]="Learning cost: " .. money(service.cost)
    local note
    if not number(stats.outputItemID) then note="No sellable item output"
    elseif readable(stats.sellable) and stats.sellable==false then note="Output is not tradeable"
    elseif not number(stats.unitAH) then note="Market data unavailable"
    elseif not number(stats.craftCost) then note="Reagent prices unavailable" end
    if note then lines[#lines+1]="";lines[#lines+1]=note end
    UI.title:SetText(text(service.statsRecipe.name) or text(service.name) or "Recipe economics")
    UI.body:SetText(table.concat(lines,"\n"))
    if UI.learnPill and UI.learnPill.SetVariant then
        local st = text(service.status)
        if not st then
            local idx = number(read(GetTrainerSelectionIndex))
            if idx then
                local _, _, sType = read(GetTrainerServiceInfo, idx)
                st = text(sType)
            end
        end
        if st == "used" then
            UI.learnPill.SetVariant("info", "Learned")
        elseif st == "unavailable" then
            UI.learnPill.SetVariant("danger", "Locked")
        else
            UI.learnPill.SetVariant("positive", "Learnable")
        end
        if UI.learnPill.frame and UI.learnPill.frame.Show then UI.learnPill.frame:Show() end
    end
    if UI.costPill and UI.costPill.SetVariant then
        local c = number(service.cost)
        local costLbl = (c and c > 0) and ("Gold Needed: " .. money(c)) or "Gold Needed: Free"
        local cVar = (c and c > 0) and "warning" or "neutral"
        UI.costPill.SetVariant(cVar, costLbl)
        if UI.costPill.frame and UI.costPill.frame.Show then UI.costPill.frame:Show() end
    end
end
function UI.Refresh()
    UI.Clear()
    if not UI.frame or not open or not ClassTrainerFrame:IsShown() then return end
    local services,stats=ns.TrainerServices,ns.RecipeStats
    if not services or not services.Resolve or not stats or not stats.Get then return end
    if services.IsScanning and services.IsScanning() then return end
    local trade=read(IsTradeskillTrainer)
    if not readable(trade) or not (trade==true or trade==1) then return end
    local selected=number(read(GetTrainerSelectionIndex))
    if not selected or selected<1 or selected~=math.floor(selected) then return end
    local service=tableValue(read(services.Resolve,selected))
    if not service or not tableValue(service.statsRecipe) then return end
    local context=defaultContext
    if getContext then
        context=tableValue(read(getContext))
        if not context then return end
    end
    local row=tableValue(read(stats.Get,service.statsRecipe,context))
    if not row then return end
    render(service,row)
    UI.service,UI.stats=service,row
    anchor();UI.frame:Show()
end
local function queue()
    UI.Clear()
    if pending or not open then return end
    local token={};pending=token
    local function finish()
        if pending~=token then return end
        pending=nil
        if invalidatePending and ns.RecipeStats and ns.RecipeStats.Invalidate then ns.RecipeStats.Invalidate('skills') end
        invalidatePending=nil;UI.Refresh()
    end
    if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(0,finish) else finish() end
end
local function attach()
    if UI.frame or not ClassTrainerFrame then return end
    local frame=CreateFrame("Frame",nil,ClassTrainerFrame)
    UI.frame=frame;frame:SetSize(WIDTH,HEIGHT);frame:SetClampedToScreen(true)
    local T=ns.Theme
    local pal=getPalette()
    if T and T.NineApple and pal then
        local bg=pal.cardBg or pal.winBg or {0.173,0.173,0.180,0.98}
        frame._mmGlass=T.NineApple(frame,"glass_r12",bg,false,{noSpecular=true})
    else
        local fill=frame:CreateTexture(nil,"BACKGROUND");fill:SetAllPoints()
        fill:SetColorTexture(0.173,0.173,0.180,0.98)
        frame._mmFallbackFill=fill
    end
    local subTitle=frame:CreateFontString(nil,"OVERLAY")
    applyFont(subTitle,11,"regular")
    if subTitle.SetPoint then subTitle:SetPoint("TOPLEFT",14,-12) end
    if subTitle.SetWidth then subTitle:SetWidth(WIDTH-28) end
    if subTitle.SetJustifyH then subTitle:SetJustifyH("LEFT") end
    if subTitle.SetText then subTitle:SetText("Recipe Economics") end
    UI.subTitle=subTitle

    local title=frame:CreateFontString(nil,"OVERLAY")
    applyFont(title,14,"semibold")
    title:SetPoint("TOPLEFT",14,-27);title:SetWidth(WIDTH-28);title:SetJustifyH("LEFT")
    if title.SetMaxLines then title:SetMaxLines(2) end
    local colors=T and T.COLORS
    local gold=(pal and pal.text) or (colors and colors.titleCream) or {1,1,1};title:SetTextColor(unpack(gold))

    if T and T.CreateBadgePill then
        local learnPill=T.CreateBadgePill(frame,"Learnable","positive")
        if learnPill and learnPill.frame then
            learnPill.frame:SetPoint("TOPLEFT",frame,"TOPLEFT",14,-56)
            learnPill.frame:Hide()
        end
        UI.learnPill=learnPill

        local costPill=T.CreateBadgePill(frame,"Gold Needed","warning")
        if costPill and costPill.frame then
            if learnPill and learnPill.frame then
                costPill.frame:SetPoint("LEFT",learnPill.frame,"RIGHT",6,0)
            else
                costPill.frame:SetPoint("TOPLEFT",frame,"TOPLEFT",14,-56)
            end
            costPill.frame:Hide()
        end
        UI.costPill=costPill
    end

    if pal and frame.CreateTexture then
        local sep=frame:CreateTexture(nil,"BORDER")
        if sep.SetPoint then sep:SetPoint("TOPLEFT",14,-82); sep:SetPoint("TOPRIGHT",-14,-82) end
        if sep.SetHeight then sep:SetHeight(1) end
        if sep.SetColorTexture and pal.separator then
            sep:SetColorTexture(pal.separator[1],pal.separator[2],pal.separator[3],(pal.separator[4] or 0.45)*0.65)
        end
        UI.hdrSep=sep
    end

    local body=frame:CreateFontString(nil,"OVERLAY")
    applyFont(body,12,"regular")
    body:SetPoint("TOPLEFT",14,pal and -92 or -48);body:SetWidth(WIDTH-28);body:SetJustifyH("LEFT")
    body:SetTextColor(0.922,0.922,0.961)
    UI.title,UI.body=title,body
    if T and T.OnModeChanged then
        T.OnModeChanged(applyTheme)
    end
    applyTheme()
    if ClassTrainerFrame.HookScript then
        ClassTrainerFrame:HookScript("OnHide",closed)
        ClassTrainerFrame:HookScript("OnShow",function() open=true;queue() end)
    end
    if hooksecurefunc then
        for _,name in ipairs({"ClassTrainerFrame_Update","SelectTrainerService","ClassTrainer_SetSelection"}) do
            if type(_G[name])=="function" then hooksecurefunc(name,UI.Refresh) end
        end
    end
    if open==nil then open=ClassTrainerFrame:IsShown() end
    queue()
end
function UI.Initialize(contextProvider)
    if UI.initialized then return end
    UI.initialized=true;getContext=contextProvider
    local events=CreateFrame("Frame");UI.events=events
    for _,event in ipairs({"ADDON_LOADED","TRAINER_SHOW","TRAINER_UPDATE","TRAINER_CLOSED",
        "NEW_RECIPE_LEARNED","SKILL_LINES_CHANGED","SPELLS_CHANGED","TRADE_SKILL_UPDATE","TRAINER_SERVICE_INFO_NAME_UPDATE"}) do
        pcall(events.RegisterEvent,events,event)
    end
    events:SetScript("OnEvent",function(_,event,name)
        if event=="ADDON_LOADED" then
            if text(name)=="Blizzard_TrainerUI" then attach() end
        elseif event=="TRAINER_CLOSED" then closed()
        else
            if event=="TRAINER_SHOW" then open=true;attach() end
            -- The host already accepts skill/cost changes; display notifications add no version.
            if not (ns.app and ns.app.invalidateRecipeStats) and
                (event=='NEW_RECIPE_LEARNED' or event=='SKILL_LINES_CHANGED' or event=='SPELLS_CHANGED' or event=='TRADE_SKILL_UPDATE') then
                invalidatePending=true
            end
            queue()
        end
    end)
    attach()
end
