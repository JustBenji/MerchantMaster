local addonName, host = ...
host.Analytics = host.Analytics or {}
local ns = host.Analytics

local Tooltips = {}
ns.Tooltips = Tooltips
local seen = setmetatable({}, { __mode = "k" })
local clearHooked = setmetatable({}, { __mode = "k" })

local function secret(value)
    if _G.issecretvalue then
        local ok, result = pcall(_G.issecretvalue, value)
        return not ok or result == true
    end
    return false
end

local function secretTable(value)
    if _G.issecrettable then
        local ok, result = pcall(_G.issecrettable, value)
        return not ok or result == true
    end
    return false
end

local function number(value)
    if secret(value) then return nil end
    local n = tonumber(value)
    return n and n == n and n or nil
end

local function field(tbl, name)
    if type(tbl) ~= "table" or secretTable(tbl) then return nil end
    local ok, value = pcall(function() return tbl[name] end)
    if ok and not secret(value) then return value end
end

local function money(value)
    local h = host
    if h and h.FormatMoneyCompact then
        local ok, result = pcall(h.FormatMoneyCompact, value)
        if ok and not secret(result) then return result end
    end
    return tostring(value)
end

local function add(tooltip, left, right)
    if right ~= nil and type(tooltip.AddDoubleLine) == "function" then
        pcall(tooltip.AddDoubleLine, tooltip, left, right)
    elseif type(tooltip.AddLine) == "function" then
        pcall(tooltip.AddLine, tooltip, right ~= nil and (left .. "  " .. right) or left)
    end
end

local function discoverItem(tooltip, itemID, stackCount)
    local link, count
    if secret(itemID) then return nil end
    local explicitID = number(itemID)
    if not explicitID and type(itemID) == "string" then explicitID = tonumber(itemID:match("item:(%d+)")) end
    itemID = explicitID
    local data
    if tooltip.GetTooltipData then
        local ok, result = pcall(tooltip.GetTooltipData, tooltip)
        if ok and type(result) == "table" and not secretTable(result) and not secret(result) then data = result end
    end
    if data then
        if not itemID then
            local raw = not secret(data.itemID) and data.itemID or (not secret(data.id) and data.id)
            itemID = number(raw)
            link = not secret(data.hyperlink) and data.hyperlink or (not secret(data.link) and data.link)
        end
        count = number(data.stackCount) or number(data.quantity) or number(data.count)
        if not count and type(data.args) == "table" and not secretTable(data.args) then
            for _, value in pairs(data.args) do
                if type(value) == "string" and not secret(value) then
                    link = link or value:match("item:%d+[^|]*") and value
                    if link then break end
                end
            end
        end
    end
    if tooltip.GetItem then
        local ok, _, gotLink = pcall(tooltip.GetItem, tooltip)
        if ok and not secret(gotLink) then link = link or gotLink end
    end
    if not itemID and type(link) == "string" then itemID = tonumber(link:match("item:(%d+)")) end
    count = number(stackCount) or count
    if not count or not itemID then
        local owner
        if tooltip.GetOwner then
            local ok, result = pcall(tooltip.GetOwner, tooltip)
            if ok and not secret(result) and not secretTable(result) then owner = result end
        end
        if owner then
            local bag, slot
            if owner.GetBagID then local ok, value = pcall(owner.GetBagID, owner); if ok then bag = number(value) end end
            if owner.GetSlotID then local ok, value = pcall(owner.GetSlotID, owner); if ok then slot = number(value) end end
            if not slot and owner.GetID then local ok, value = pcall(owner.GetID, owner); if ok then slot = number(value) end end
            if not bag and owner.GetParent then
                local ok, parent = pcall(owner.GetParent, owner)
                if ok and parent and not secret(parent) and not secretTable(parent) and parent.GetID then
                    local got, value = pcall(parent.GetID, parent); if got then bag = number(value) end
                end
            end
            local container = _G.C_Container
            if bag and slot and container and container.GetContainerItemInfo then
                local ok, info = pcall(container.GetContainerItemInfo, bag, slot)
                if ok and type(info) == "table" and not secretTable(info) and not secret(info) then
                    count = count or number(field(info, "stackCount")) or number(field(info, "quantity")) or 1
                    itemID = itemID or number(field(info, "itemID"))
                end
            elseif slot and _G.GetInventoryItemID then
                local ok, equipped = pcall(_G.GetInventoryItemID, "player", slot)
                if ok and not secret(equipped) then itemID = itemID or number(equipped); count = itemID and 1 end
            end
        end
    end
    return itemID, count or 1
end

local function onCleared(tooltip)
    seen[tooltip] = nil
end

local function installClearHook(tooltip)
    if clearHooked[tooltip] or not tooltip.HookScript then return end
    local ok = pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", onCleared)
    if ok then clearHooked[tooltip] = true end
end

local prepared,pending,waiters,preparedOrder={},{},{},{}
local generation,entryCount=nil,0
local formatJobs,formatQueued={},false
local function signature()
    local store=ns.Store or {}; local inv=ns.Inventory or {}; local options=_G.MerchantMasterDB or {}
    local app=host.app
    local econ=app and app.char and app.char.economy
    if not econ and app and app.charKey and store.DeriveEcon then econ=store.DeriveEcon(app.charKey) end
    if not econ and store.CurrentCharAndEcon then local _; _,econ=store.CurrentCharAndEcon() end
    return table.concat({tostring(ns.Model),tostring(ns.Model and ns.Model.generation),tostring(inv),tostring(store.accountingVersion or store.version or 0),tostring(inv.version or 0),
        tostring(econ),tostring(options.economy),tostring(options.anTooltipInventory),tostring(options.anTooltips),tostring(math.floor((_G.time and _G.time() or 0)/86400))},"|")
end
function Tooltips.Invalidate()
    generation=nil; prepared={}; pending={}; waiters={}; preparedOrder={}; formatJobs={}; entryCount=0
end
local function currentGeneration()
    local sig=signature()
    if sig~=generation then Tooltips.Invalidate(); generation=sig end
    return sig
end
local function presentation(id,qty,shift) return id..":"..(shift and math.max(1,qty) or 1)..":"..tostring(shift) end
local function prepare(id,qty,shift)
    local options=_G.MerchantMasterDB or {}
    local lines={}
    local tooltip={AddDoubleLine=function(_,left,right) lines[#lines+1]={left,right} end,AddLine=function(_,left) lines[#lines+1]={left} end}
    local analytics = ns.Model
    if not analytics then return false end
    local indexedStats,indexedHint,indexed
    if analytics.GetPreparedTooltipStats then indexedStats,indexedHint,indexed=analytics.GetPreparedTooltipStats(id) end
    local get = analytics.GetPriceSource
    local function price(key)
        if indexed then
            local value=number(field(indexedStats,({AvgSell="avgSell",AvgBuy="avgBuy",CurBasis="curBasis",SaleRate="saleRate",NumExpires="expSinceSale"})[key]))
            if key=="SaleRate" and value then value=math.floor(value*100+0.5) end
            return value
        end
        if not get then return nil end
        local ok, value = pcall(get, key, id)
        if ok then return number(value) end
    end
    local avgSell, avgBuy = price("AvgSell"), price("AvgBuy")
    local curBasis, avgProfit = price("CurBasis"), price("AvgProfit")
    local saleRate, expired = price("SaleRate"), price("NumExpires")
    local stats=indexedStats
    if not indexed and analytics.GetItemStats then
        local ok, value = pcall(analytics.GetItemStats, id)
        if ok and type(value) == "table" and not secretTable(value) and not secret(value) then stats = value end
    end
    local hint=indexedHint
    if not indexed and analytics.GetSaleHint then
        local ok, value = pcall(analytics.GetSaleHint, id)
        if ok and type(value) == "table" and not secretTable(value) and not secret(value) then hint = value end
    end
    local multiplier = shift and math.max(1, qty) or 1
    add(tooltip, "MerchantMaster Accounting", shift and ("(x" .. tostring(multiplier) .. ")") or "(per 1)")
    if avgSell then add(tooltip, "Avg Sell", money(avgSell * multiplier)) end
    local minSell, maxSell = number(field(stats, "minSell")), number(field(stats, "maxSell"))
    if minSell and maxSell then add(tooltip, "Min / Max Sell", money(minSell * multiplier) .. " / " .. money(maxSell * multiplier))
    elseif number(field(stats, "lastSoldUnit")) then add(tooltip, "Last Sold", money(number(field(stats, "lastSoldUnit")) * multiplier)) end
    if avgBuy then add(tooltip, "Avg Buy", money(avgBuy * multiplier)) end
    if curBasis then add(tooltip, "Current Basis", money(curBasis * multiplier)) end
    avgProfit = avgProfit or number(field(stats, "avgProfit"))
    if avgProfit then add(tooltip, "Avg Profit", money(avgProfit * multiplier)) end
    local lastSoldUnit = number(field(stats, "lastSoldUnit"))
    if lastSoldUnit and minSell and maxSell then
        add(tooltip, "Last Sold", money(lastSoldUnit * multiplier))
    end
    if saleRate ~= nil or expired ~= nil then
        local rate = saleRate and (tostring(math.floor(saleRate + 0.5)) .. "%") or "-"
        add(tooltip, "Sale Rate / Expires", rate .. " / " .. tostring(expired or 0))
    end
    if hint and (field(hint, "isSlowing") == true or (number(field(hint, "expSinceSale")) or 0) >= 5) then
        add(tooltip, "Slowing", "Review price or listing")
    end

    if options.anTooltipInventory ~= false and ns.Inventory and ns.Inventory.GetItemBreakdown then
        local ok, breakdown = pcall(ns.Inventory.GetItemBreakdown, id)
        local byChar = field(breakdown, "byChar")
        if ok and type(byChar) == "table" and not secretTable(byChar) then
            for _, entry in ipairs(byChar) do
                if type(entry) == "table" and not secret(entry) and not secretTable(entry) then
                    local shortName, fullName = field(entry, "shortName"), field(entry, "char")
                    local char = type(shortName) == "string" and shortName or fullName
                    if type(char) == "string" and not secret(char) then
                        local counts = string.format("Bags %d, Bank %d, Mail %d, In-Transit %d, AH %d",
                            number(field(entry, "bags")) or 0, number(field(entry, "bank")) or 0, number(field(entry, "mail")) or 0,
                            number(field(entry, "inTransit")) or 0, number(field(entry, "ah")) or 0)
                        local stamp = number(field(entry, "updatedAt"))
                        local staleValue = field(entry, "stale")
                        local staleFlag = staleValue == true
                        local stale = staleFlag or (stamp and (_G.time and _G.time() or 0) - stamp > 7 * 86400)
                        add(tooltip, char .. (stale and " (stale)" or ""), counts)
                    end
                end
            end
            add(tooltip, "Total Inventory", tostring(number(field(breakdown, "total")) or 0))
        end
    end
    return lines
end
local function appendPrepared(tooltip,key,lines)
    if seen[tooltip]==key then return end
    for _,line in ipairs(lines) do add(tooltip,line[1],line[2]) end
    seen[tooltip]=key
end
local function ownerOf(tooltip)
    if tooltip.GetOwner then local ok,value=pcall(tooltip.GetOwner,tooltip); if ok and not secret(value) then return value end end
end
local function enqueueFormatting(job)
    formatJobs[#formatJobs+1]=job
    if formatQueued then return end
    formatQueued=true
    local function drain()
        local jobs={}
        for i=1,math.min(4,#formatJobs) do jobs[i]=table.remove(formatJobs,1) end
        for _,run in ipairs(jobs) do run() end
        if #formatJobs>0 and _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.01,drain)
        else formatQueued=false end
    end
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.01,drain) else drain() end
end
local function queue(id,qty,shift)
    local gen=currentGeneration(); local key=presentation(id,qty,shift)
    if prepared[key] or pending[key] then return key end
    pending[key]=true
    local function ready(success)
        if currentGeneration()~=gen then return end
        if success==false then pending[key]=nil; waiters[key]=nil; return end
        -- Bound formatting/inventory work as well as the aggregate scan.
        local function build()
            if currentGeneration()~=gen then return end
            local lines=prepare(id,qty,shift)
            if entryCount>=512 then prepared[table.remove(preparedOrder,1)]=nil; entryCount=entryCount-1 end
            prepared[key]=lines or {}; preparedOrder[#preparedOrder+1]=key; entryCount=entryCount+1; pending[key]=nil
            local waiting=waiters[key]; waiters[key]=nil
            for tooltip,request in pairs(waiting or {}) do
                if request.gen==generation and ownerOf(tooltip)==request.owner and seen[tooltip]==request.marker then
                    local actual,quantity=discoverItem(tooltip)
                    local isShift=_G.IsShiftKeyDown and _G.IsShiftKeyDown()==true or false
                    if actual==id and presentation(id,quantity,isShift)==key then
                        appendPrepared(tooltip,key,prepared[key])
                        if tooltip.Show then tooltip:Show() end
                    end
                end
            end
        end
        enqueueFormatting(build)
    end
    if ns.Model and ns.Model.PrepareTooltipIndexes then ns.Model.PrepareTooltipIndexes(ready)
    else ready() end
    return key
end
function Tooltips.PrimeItems(itemIDs,isCurrent)
    currentGeneration()
    local ids={}; for _,id in ipairs(itemIDs or {}) do id=number(id); if id and id>0 then ids[id]=true end end
    local list={}; for id in pairs(ids) do list[#list+1]=id end
    local index=1; local gen=generation
    local function step()
        if (isCurrent and not isCurrent()) or currentGeneration()~=gen then return end
        local stop=math.min(#list,index+7)
        while index<=stop do queue(list[index],1,false); index=index+1 end
        if index<=#list and _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.01,step) end
    end
    step()
end
function Tooltips.OnTooltipItem(tooltip,itemID,stackCount)
    if not tooltip or secret(tooltip) or secretTable(tooltip) then return false end
    local options=_G.MerchantMasterDB or {}
    if options.anTooltips==false then return false end
    installClearHook(tooltip)
    local id,qty=discoverItem(tooltip,itemID,stackCount)
    if not id or id<=0 or not ns.Model then return false end
    local shift=false
    if _G.IsShiftKeyDown then local ok,value=pcall(_G.IsShiftKeyDown); shift=ok and not secret(value) and value==true end
    currentGeneration()
    local key=queue(id,qty,shift)
    local lines=prepared[key]
    if lines then appendPrepared(tooltip,key,lines)
    else
        local marker="pending:"..key
        seen[tooltip]=marker
        waiters[key]=waiters[key] or setmetatable({},{__mode="k"})
        waiters[key][tooltip]={gen=generation,owner=ownerOf(tooltip),marker=marker}
    end
    return true
end

return Tooltips
