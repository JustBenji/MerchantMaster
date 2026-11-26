-- Shared trainer identity and Professor cost scanning. No auction queries.
local _, ns = ...
local TrainerServices = {}
ns.TrainerServices = TrainerServices
local scanning = false
local function readable(v)
    return not (issecretvalue and issecretvalue(v)) and not (type(v)=="table" and issecrettable and issecrettable(v))
end
local function text(v) if readable(v) and type(v)=="string" then return v end end
local function number(v)
    if readable(v) and type(v)=="number" and v==v and v>=0 and v<math.huge then return v end
end
local function index(v) local n=number(v); if n and n>0 and n==math.floor(n) then return n end end
local function read(fn, ...)
    if type(fn)~="function" then return nil end
    local ok,a,b,c=pcall(fn,...)
    if ok then return a,b,c end
end
function TrainerServices.IsScanning() return scanning end

function TrainerServices.Initialize(getProfDB)
    if TrainerServices.initialized then return end
    TrainerServices.initialized = true
    local MP=ns.MP or {}
    local byName, bySpell, statsBySpell = {}, {}, {}
    local function add(t,k,r)
        if t[k]==nil then t[k]=r elseif t[k]~=r then t[k]=false end
    end
    for pk,list in pairs(MP.RECIPES or {}) do
        for _,r in ipairs(list) do
            add(byName,pk .. "|" .. r.n,r)
            if r.s then add(bySpell,r.s,r) end
        end
    end
    for _,r in ipairs(ns.RECIPES or {}) do
        if r.spellID then add(statsBySpell,r.spellID,r) end
    end
    local trainerScanTip
    local function spellID(i)
        if C_TooltipInfo and type(C_TooltipInfo.GetTrainerService)=="function" then
            local data=read(C_TooltipInfo.GetTrainerService,i)
            if not readable(data) then return nil,true end
            if type(data)=="table" then
                if not readable(data.id) or not readable(data.type) then return nil,true end
                local spellKind=Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell
                if spellKind and data.type and data.type~=spellKind then return nil,true end
                local id=index(data.id)
                if id then return id end
            end
        end
        if not CreateFrame then return nil end
        if not trainerScanTip then
            trainerScanTip=CreateFrame("GameTooltip","MerchantProfessorTrainerScanTip",nil,"GameTooltipTemplate")
        end
        local id
        pcall(function()
            if trainerScanTip.SetOwner then trainerScanTip:SetOwner(UIParent,"ANCHOR_NONE") end
            if trainerScanTip.SetTrainerService then trainerScanTip:SetTrainerService(i) end
            if trainerScanTip.GetSpell then id=select(2,trainerScanTip:GetSpell()) end
        end)
        if trainerScanTip.Hide then pcall(trainerScanTip.Hide,trainerScanTip) end
        if not readable(id) then return nil,true end
        return index(id)
    end
    local function identity(i)
        i=index(i); if not i then return nil end
        local name,sub,category=read(GetTrainerServiceInfo,i)
        if not text(name) or not readable(sub) or not readable(category) then return nil end
        if sub~=nil and not text(sub) then return nil end
        if category~=nil and not text(category) then return nil end
        local id,blocked=spellID(i)
        if blocked then return nil end
        return {name=name,sub=sub,category=category,spellID=id}
    end
    local function normalize(name,sub)
        local rank=sub and sub:match("^Rank (%d+)$")
        if not rank or rank=="1" then return name end
        local roman={["2"]="II",["3"]="III",["4"]="IV",["5"]="V",["6"]="VI"}
        return name .. " " .. (roman[rank] or rank)
    end
    local function resolve(i)
        local id=identity(i)
        if not id or id.category=="header" then return nil end
        local skillName,skillRank=read(GetTrainerServiceSkillReq,i)
        local pk=text(skillName) and (MP.NAME_TO_PROF_KEY or {})[skillName:lower()]
        local name=normalize(id.name,id.sub)
        local rec,statsRecipe
        if id.spellID then
            statsRecipe=statsBySpell[id.spellID] or nil
            rec=bySpell[id.spellID] or statsRecipe
        else
            if pk then rec=byName[pk .. "|" .. name] or nil
            else rec=byName["poisons|" .. name] or nil end
            if rec then statsRecipe=statsBySpell[rec.s] or nil end
        end
        if rec then pk=rec.prof or pk end
        return {spellID=id.spellID or (rec and (rec.s or rec.spellID)),recipe=rec,statsRecipe=statsRecipe,
            cost=number(read(GetTrainerServiceCost,i)),skill=number(skillRank),
            level=number(read(GetTrainerServiceLevelReq,i)),profession=pk,
            name=id.name,normalizedName=name,category=id.category}
    end
    function TrainerServices.Resolve(i)
        if scanning then return nil end
        local service=resolve(i)
        if service and service.recipe then return service end
    end
    local function same(a,b)
        if a.spellID and b.spellID then return a.spellID==b.spellID end
        return a.name==b.name and a.sub==b.sub and a.category==b.category
    end
    function TrainerServices.Scan(isInitialShow)
        if scanning or not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
        scanning=true
        local savedFilters,selected={},nil
        local canRestore=isInitialShow and type(GetTrainerSelectionIndex)=="function" and type(SelectTrainerService)=="function"
        local allowFilterExpand=isInitialShow and (canRestore or type(GetTrainerSelectionIndex)~="function")
        local ok,err=pcall(function()
            if canRestore then
                selected=identity(read(GetTrainerSelectionIndex))
            end
            local trade=read(IsTradeskillTrainer)
            if allowFilterExpand and readable(trade) and (trade==true or trade==1)
                and GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
                for _,kind in ipairs({"available","unavailable","used"}) do
                    local got,v=pcall(GetTrainerServiceTypeFilter,kind)
                    if got and readable(v) and not (v==true or v==1) then
                        savedFilters[#savedFilters+1]={kind=kind,value=v}
                        pcall(SetTrainerServiceTypeFilter,kind,true)
                    end
                end
            end
            local db=getProfDB()
            db.trainerCosts=db.trainerCosts or {};db.trainerReqs=db.trainerReqs or {};db.trainerReqsByName=db.trainerReqsByName or {}
            local count=index(read(GetNumTrainerServices)) or 0
            for i=1,count do
                local service=resolve(i)
                if service then
                    local rec,pk=service.recipe,service.profession
                    local cost,req,level=service.cost,service.skill,service.level
                    if cost then
                        db.trainerCosts[service.name]=cost
                        if rec then
                            db.trainerCosts[rec.n or rec.name]=cost
                            db.trainerCosts[rec.s or rec.spellID]=cost
                        end
                    end
                    if pk and ((req and req>0) or (level and level>0)) then
                        local cleanReq=(req and req>0) and math.floor(req) or nil
                        local cleanLevel=(level and level>0) and math.floor(level) or nil
                        if rec then
                            local sid=rec.s or rec.spellID
                            db.trainerReqs[pk]=db.trainerReqs[pk] or {}
                            local prev=db.trainerReqs[pk][sid] or {}
                            db.trainerReqs[pk][sid]={req=cleanReq or prev.req,rlv=cleanLevel or prev.rlv}
                        end
                        local key=pk .. "|" .. ((rec and (rec.n or rec.name)) or service.normalizedName)
                        local prev=db.trainerReqsByName[key] or {}
                        db.trainerReqsByName[key]={req=cleanReq or prev.req,rlv=cleanLevel or prev.rlv}
                    end
                end
            end
        end)
        -- Filter callbacks may change the selected index. Restore by identity in the final list.
        for _,entry in ipairs(savedFilters) do pcall(SetTrainerServiceTypeFilter,entry.kind,entry.value) end
        if canRestore and #savedFilters>0 then
            local matched,count=nil,index(read(GetNumTrainerServices)) or 0
            for i=1,count do
                local candidate=identity(i)
                if selected and candidate and same(selected,candidate) then
                    if matched then matched=nil;break end
                    matched=i
                end
            end
            local restored=false
            if matched and type(ClassTrainer_SetSelection)=="function" then
                restored=pcall(ClassTrainer_SetSelection,matched)
            end
            if not restored then pcall(SelectTrainerService,matched or 0) end
        end
        scanning=false
        return ok,err
    end
end
