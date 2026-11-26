-- Focused lifecycle contracts; synthetic globals only.
local dir = (((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../Analytics/")
local checks = 0
local function check(ok, message) checks = checks + 1; assert(ok, message) end
local function boot()
    local lines, hooks, frames = 0, 0, {}
    _G.C_AddOns = { IsAddOnLoaded = function() return false end }
    _G.print = function() lines = lines + 1 end
    _G.SlashCmdList = {}
    _G.MerchantMasterAnalytics = nil
    _G.MerchantMasterLedgerDB = nil
    _G.MerchantMasterAPI = { API_VERSION = 1 }
    _G.CreateFrame = function()
        local f = { events = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:SetScript(_, fn) self.fn = fn end
        frames[#frames + 1] = f; return f
    end
    _G.hooksecurefunc = function() hooks = hooks + 1 end
    _G.GetMoney = function() return 0 end
    _G.C_AuctionHouse = { StartCommoditiesPurchase = function() end }
    local host = { app = { ui = {} } }
    for _, file in ipairs({"Store", "Model", "Chart", "Capture", "UI"}) do
        assert(loadfile(dir .. file .. ".lua"))("MerchantMaster", host)
    end
    local function fire(event, name) for _, f in ipairs(frames) do if f.events[event] then f.fn(f, event, name) end end end
    check(host.Store == nil and host.Model == nil and host.UI == nil, "host namespace remains separate")
    check(host.Analytics == _G.MerchantMasterAnalytics, "legacy alias equals nested namespace")
    check(host.Analytics.Store and host.Analytics.Model and host.Analytics.Chart and host.Analytics.Capture and host.Analytics.UI,
        "all modules stay in the nested namespace")
    fire("ADDON_LOADED", "MerchantMaster")
    check(hooks == 0, "hooks wait for dependencies to finish loading")
    fire("PLAYER_LOGIN"); fire("PLAYER_LOGIN")
    check(hooks == 1, "repeated initialization installs each available hook once")
    check(lines == 0, "fresh merged load has no spurious warnings")
    local future = { schema = 99, opaque = "preserve" }
    _G.MerchantMasterLedgerDB = future
    host.Analytics.Store.Init()
    check(host.Analytics.Store.readOnly and _G.MerchantMasterLedgerDB == future and next(future) ~= nil,
        "future schema keeps its original table and becomes read-only")
    check(not host.Analytics.UI or not host.Analytics.UI.registered, "unmounted provider stays inert until host mounts")
end
local realPrint = print
boot()
realPrint("WP1 lifecycle: " .. checks .. " assertions, 0 failures")
