-- MerchantMaster ConsoleEngine.lua
-- Diagnostics, storage/schema inspector, persistent AH refresh counters, zero-overhead
-- opt-in runtime profiler, optional snapshot extension bridge, debug bundle exporter,
-- and data maintenance actions. Pure ASCII only (BAD_GLYPHS=0).

local ADDON, ns = ...
ns = ns or {}

if ns.ConsoleEngine then
	return
end

local CE = {}
ns.ConsoleEngine = CE

local floor, max, min = math.floor, math.max, math.min
local format, tostring, tonumber, type, pairs, ipairs = string.format, tostring, tonumber, type, pairs, ipairs

---------------------------------------------------------------------------------------------------
-- Defensive Helpers & Formatting
---------------------------------------------------------------------------------------------------

local function readable(v)
	if type(_G.issecretvalue) == "function" then
		local ok, sec = pcall(_G.issecretvalue, v)
		if not ok or sec then return false end
	end
	if type(v) == "table" and type(_G.issecrettable) == "function" then
		local ok, sec = pcall(_G.issecrettable, v)
		if not ok or sec then return false end
	end
	return true
end

local function safeNum(v, fallback)
	if not readable(v) then return fallback end
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return n
end

local function safeStr(v, fallback)
	if not readable(v) then return fallback or "" end
	if type(v) == "string" then return v end
	return fallback or ""
end

local function asciiSafe(text)
	local s = safeStr(text, "")
	if s == "" then return "" end
	return (s:gsub("[^\32-\126]", "?"))
end

function CE.FormatInt(n)
	local v = floor(tonumber(n) or 0)
	local sign = v < 0 and "-" or ""
	local s = tostring(math.abs(v))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return sign .. out
end

function CE.FormatBytes(bytes)
	local b = max(0, tonumber(bytes) or 0)
	if b >= 1024 * 1024 then
		return format("%.2f MB", b / (1024 * 1024))
	elseif b >= 1024 then
		return format("%.1f KB", b / 1024)
	end
	return format("%d B", floor(b + 0.5))
end

function CE.FormatAge(ts, now)
	local t = safeNum(ts, 0)
	local cur = safeNum(now, (_G.time and _G.time()) or 0)
	if not t or t <= 0 or not cur or cur <= 0 then
		return "never"
	end
	local d = max(0, cur - t)
	if d < 60 then
		return format("%ds ago", floor(d))
	elseif d < 3600 then
		return format("%dm ago", floor(d / 60))
	elseif d < 86400 then
		return format("%dh %dm ago", floor(d / 3600), floor((d % 3600) / 60))
	end
	return format("%dd %dh ago", floor(d / 86400), floor((d % 86400) / 3600))
end

function CE.FormatTimestamp(ts)
	local t = safeNum(ts, 0)
	if not t or t <= 0 then return "never" end
	if type(_G.date) == "function" then
		local ok, txt = pcall(_G.date, "%Y-%m-%d %H:%M:%S", t)
		if ok and readable(txt) and type(txt) == "string" then
			return txt
		end
	end
	return tostring(t)
end

---------------------------------------------------------------------------------------------------
-- Opt-In Runtime & Transaction Profiler (Zero-Overhead OFF Default)
---------------------------------------------------------------------------------------------------

local MAX_RECENT_TX = 40
local perfState = {
	txTotal = 0,
	txSumMs = 0,
	txMaxMs = 0,
	txByKind = {},
	txRecent = {},
	uiByTab = {},
	bootPhases = {},
}

function CE.SyncPerfFlag()
	local db = type(_G.MerchantMasterDB) == "table" and _G.MerchantMasterDB or nil
	local on = (db and db.consolePerfEnabled == true) and true or false
	ns._consolePerfOn = on
	return on
end

function CE.IsPerfEnabled()
	if ns._consolePerfOn == nil then
		return CE.SyncPerfFlag()
	end
	return ns._consolePerfOn == true
end

function CE.SetPerfEnabled(on)
	local flag = (on == true)
	if type(_G.MerchantMasterDB) == "table" then
		_G.MerchantMasterDB.consolePerfEnabled = flag
	end
	ns._consolePerfOn = flag
	return flag
end

function CE.ResetPerfMetrics()
	perfState.txTotal = 0
	perfState.txSumMs = 0
	perfState.txMaxMs = 0
	perfState.txByKind = {}
	perfState.txRecent = {}
	perfState.uiByTab = {}
	perfState.bootPhases = {}
end

function CE.RecordTxTiming(kind, ms)
	if ns._consolePerfOn ~= true then return end
	local k = safeStr(kind, "UNKNOWN")
	local dt = max(0, tonumber(ms) or 0)
	perfState.txTotal = perfState.txTotal + 1
	perfState.txSumMs = perfState.txSumMs + dt
	if dt > perfState.txMaxMs then perfState.txMaxMs = dt end
	local bucket = perfState.txByKind[k]
	if not bucket then
		bucket = { count = 0, sumMs = 0, maxMs = 0, lastMs = 0 }
		perfState.txByKind[k] = bucket
	end
	bucket.count = bucket.count + 1
	bucket.sumMs = bucket.sumMs + dt
	bucket.lastMs = dt
	if dt > bucket.maxMs then bucket.maxMs = dt end

	local at = (_G.time and _G.time()) or 0
	perfState.txRecent[#perfState.txRecent + 1] = {
		kind = k,
		ms = dt,
		at = at,
	}
	if #perfState.txRecent > MAX_RECENT_TX then
		table.remove(perfState.txRecent, 1)
	end
end

function CE.RecordUITiming(tab, ms)
	if ns._consolePerfOn ~= true then return end
	local k = safeStr(tab, "unknown")
	local dt = max(0, tonumber(ms) or 0)
	local bucket = perfState.uiByTab[k]
	if not bucket then
		bucket = { count = 0, sumMs = 0, maxMs = 0, lastMs = 0, lastAt = 0 }
		perfState.uiByTab[k] = bucket
	end
	bucket.count = bucket.count + 1
	bucket.sumMs = bucket.sumMs + dt
	bucket.lastMs = dt
	bucket.lastAt = (_G.time and _G.time()) or 0
	if dt > bucket.maxMs then bucket.maxMs = dt end
end

function CE.RecordBootPhase(phase, ms)
	if ns._consolePerfOn ~= true then return end
	local p = safeStr(phase, "PHASE")
	local dt = max(0, tonumber(ms) or 0)
	perfState.bootPhases[#perfState.bootPhases + 1] = {
		phase = p,
		ms = dt,
		at = (_G.time and _G.time()) or 0,
	}
end

function CE.GetPerfSnapshot()
	local enabled = CE.IsPerfEnabled()
	local txKinds = {}
	for k, b in pairs(perfState.txByKind) do
		txKinds[#txKinds + 1] = {
			kind = k,
			count = b.count,
			avgMs = b.count > 0 and (b.sumMs / b.count) or 0,
			maxMs = b.maxMs,
			lastMs = b.lastMs,
		}
	end
	table.sort(txKinds, function(a, b)
		if a.maxMs ~= b.maxMs then return a.maxMs > b.maxMs end
		return a.kind < b.kind
	end)

	local uiTabs = {}
	for tab, b in pairs(perfState.uiByTab) do
		uiTabs[#uiTabs + 1] = {
			tab = tab,
			count = b.count,
			avgMs = b.count > 0 and (b.sumMs / b.count) or 0,
			maxMs = b.maxMs,
			lastMs = b.lastMs,
			lastAt = b.lastAt,
		}
	end
	table.sort(uiTabs, function(a, b)
		if a.lastMs ~= b.lastMs then return a.lastMs > b.lastMs end
		return a.tab < b.tab
	end)

	local recent = {}
	for i = #perfState.txRecent, 1, -1 do
		recent[#recent + 1] = perfState.txRecent[i]
	end

	local boots = {}
	for i, bp in ipairs(perfState.bootPhases) do
		boots[i] = bp
	end

	return {
		enabled = enabled,
		txTotal = perfState.txTotal,
		txAvgMs = perfState.txTotal > 0 and (perfState.txSumMs / perfState.txTotal) or 0,
		txMaxMs = perfState.txMaxMs,
		txByKind = txKinds,
		txRecent = recent,
		uiByTab = uiTabs,
		bootPhases = boots,
	}
end

---------------------------------------------------------------------------------------------------
-- Persistent Manual AH Refresh Counters (MerchantMasterDB.consoleStats)
---------------------------------------------------------------------------------------------------

local function ensureStatsDB()
	if type(_G.MerchantMasterDB) ~= "table" then
		return nil
	end
	if type(_G.MerchantMasterDB.consoleStats) ~= "table" then
		_G.MerchantMasterDB.consoleStats = {}
	end
	local s = _G.MerchantMasterDB.consoleStats
	if type(s.fullScans) ~= "number" then s.fullScans = 0 end
	if type(s.partialScans) ~= "number" then s.partialScans = 0 end
	if type(s.singleRefreshes) ~= "number" then s.singleRefreshes = 0 end
	if type(s.deepLotScans) ~= "number" then s.deepLotScans = 0 end
	return s
end

function CE.RecordAHScan(kind, info)
	local s = ensureStatsDB()
	if not s then return end
	local now = (_G.time and _G.time()) or 0
	info = type(info) == "table" and info or {}
	local at = safeNum(info.at, now) or now
	if kind == "full" then
		s.fullScans = (s.fullScans or 0) + 1
		s.lastFullScanAt = at
		s.lastFullScanItems = safeNum(info.items, 0) or 0
		s.lastFullScanSec = safeNum(info.elapsed, 0) or 0
		s.lastFullScanEcon = safeStr(info.economy, "")
	elseif kind == "partial" then
		s.partialScans = (s.partialScans or 0) + 1
		s.lastPartialAt = at
	elseif kind == "single" then
		s.singleRefreshes = (s.singleRefreshes or 0) + 1
		s.lastSingleAt = at
		s.lastSingleItemID = safeNum(info.itemID, 0) or 0
	elseif kind == "deep_lot" then
		s.deepLotScans = (s.deepLotScans or 0) + 1
		s.lastDeepLotAt = at
		s.lastDeepLotItems = safeNum(info.items, 0) or 0
	end
end

function CE.GetRefreshSummary()
	local stats = ensureStatsDB() or {}
	local econInfo = ns.CurrentEconomyInfo and ns.CurrentEconomyInfo() or {}
	local activeEcon = safeStr(econInfo.effectiveKey, "Normal-Horde")
	local db = type(_G.MerchantMasterDB) == "table" and _G.MerchantMasterDB or nil
	local ahEcon = db and type(db.ahPrices) == "table" and db.ahPrices[activeEcon] or nil
	local manualAt = type(ahEcon) == "table" and safeNum(ahEcon._scannedAt, nil) or nil
	if not manualAt and db then
		manualAt = safeNum(db.lastRefreshAt, nil)
	end

	local hasSnap = CE.HasSnapshotExtension() or (type(ns.HasSnapshots) == "function" and ns.HasSnapshots() == true)
	local snapMeta = hasSnap and ns.Pricing and type(ns.Pricing.GetSnapshotMeta) == "function"
		and ns.Pricing.GetSnapshotMeta(activeEcon) or nil
	local sysMeta = hasSnap and ns.Pricing and type(ns.Pricing.GetSnapshotSystemMeta) == "function"
		and ns.Pricing.GetSnapshotSystemMeta() or nil

	return {
		activeEcon = activeEcon,
		manualFullScans = stats.fullScans or 0,
		manualPartialScans = stats.partialScans or 0,
		manualSingleRefreshes = stats.singleRefreshes or 0,
		manualDeepLotScans = stats.deepLotScans or 0,
		lastFullScanAt = stats.lastFullScanAt or manualAt or 0,
		lastFullScanItems = stats.lastFullScanItems or 0,
		lastFullScanSec = stats.lastFullScanSec or 0,
		lastPartialAt = stats.lastPartialAt or 0,
		lastSingleAt = stats.lastSingleAt or 0,
		lastDeepLotAt = stats.lastDeepLotAt or 0,
		snapMeta = snapMeta,
		sysMeta = sysMeta,
	}
end

---------------------------------------------------------------------------------------------------
-- On-Demand Storage, Tables, Fields & Memory Inspector
---------------------------------------------------------------------------------------------------

function CE.EstimateTable(tbl, maxDepth, seen)
	if type(tbl) ~= "table" or not readable(tbl) then
		return 0, 0
	end
	seen = seen or {}
	if seen[tbl] then
		return 0, 0
	end
	seen[tbl] = true
	local depthLimit = maxDepth or 4
	local entries = 0
	local bytes = 32
	for k, v in pairs(tbl) do
		if readable(k) and readable(v) then
			entries = entries + 1
			local kt = type(k)
			if kt == "string" then
				bytes = bytes + #k + 8
			else
				bytes = bytes + 8
			end
			local vt = type(v)
			if vt == "string" then
				bytes = bytes + #v + 8
			elseif vt == "number" or vt == "boolean" then
				bytes = bytes + 8
			elseif vt == "table" then
				if depthLimit > 1 then
					local _, subBytes = CE.EstimateTable(v, depthLimit - 1, seen)
					bytes = bytes + subBytes
				else
					bytes = bytes + 48
				end
			end
		end
	end
	return entries, bytes
end

local function countMapItems(tbl)
	if type(tbl) ~= "table" or not readable(tbl) then return 0 end
	local n = 0
	for k in pairs(tbl) do
		if readable(k) then n = n + 1 end
	end
	return n
end

local function countNestedEconomyItems(root)
	if type(root) ~= "table" or not readable(root) then return 0 end
	local total = 0
	for _, econTbl in pairs(root) do
		if type(econTbl) == "table" and readable(econTbl) then
			for k in pairs(econTbl) do
				if readable(k) and type(k) == "number" then
					total = total + 1
				end
			end
		end
	end
	return total
end

local function queryAddonMemoryKB(addonName)
	local fn = (_G.C_AddOns and _G.C_AddOns.GetAddOnMemoryUsage) or _G.GetAddOnMemoryUsage
	if type(fn) ~= "function" then return nil end
	local ok, kb = pcall(fn, addonName)
	if ok and readable(kb) and type(kb) == "number" then
		return kb
	end
	return nil
end

local function isAddonLoadedSafe(addonName)
	local fn = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if type(fn) ~= "function" then return false end
	local ok, loaded = pcall(fn, addonName)
	return ok and readable(loaded) and loaded == true
end

local function findAddonExists(targetName)
	local numFn = (_G.C_AddOns and _G.C_AddOns.GetNumAddOns) or _G.GetNumAddOns
	local infoFn = (_G.C_AddOns and _G.C_AddOns.GetAddOnInfo) or _G.GetAddOnInfo
	if type(infoFn) == "function" then
		local ok, name = pcall(infoFn, targetName)
		if ok and readable(name) and name == targetName then
			return true
		end
	end
	if type(numFn) == "function" and type(infoFn) == "function" then
		local n = safeNum(numFn(), 0) or 0
		for i = 1, n do
			local ok, name = pcall(infoFn, i)
			if ok and readable(name) and name == targetName then
				return true
			end
		end
	end
	return false
end

local function getCompanionStatus(addonName, provider)
	if provider ~= nil or isAddonLoadedSafe(addonName) then
		return "loaded"
	end
	if findAddonExists(addonName) then
		return "disabled"
	end
	return "absent"
end

function CE.GetAddonState(addonName)
	local app = ns.app
	local provider = nil
	if addonName == "MerchantMaster_Snapshots" then
		provider = app and app.snapshotExtension or nil
	elseif addonName == "MerchantMaster_MapPins" then
		provider = app and app.mapPinsProvider or nil
	end
	return getCompanionStatus(addonName, provider)
end

function CE.HasSnapshotExtension()
	return (ns.app and ns.app.snapshotExtension ~= nil) and true or false
end

function CE.HasMapPinsExtension()
	return (ns.app and ns.app.mapPinsProvider ~= nil) and true or false
end

function CE.GetSnapshotExtension()
	return (ns.app and type(ns.app.snapshotExtension) == "table") and ns.app.snapshotExtension or nil
end

local DEFAULT_SERVER_PRESETS = {
	{ key = "Normal-Horde", label = "Normal-Horde (2:114)", rid = 2, hid = 114 },
	{ key = "Normal-Alliance", label = "Normal-Alliance (2:111)", rid = 2, hid = 111 },
	{ key = "Normal-Blackwater", label = "Normal-Blackwater (2:117)", rid = 2, hid = 117 },
	{ key = "PvP-Horde", label = "PvP-Horde (1:113)", rid = 1, hid = 113 },
	{ key = "PvP-Alliance", label = "PvP-Alliance (1:110)", rid = 1, hid = 110 },
	{ key = "PvP-Blackwater", label = "PvP-Blackwater (1:116)", rid = 1, hid = 116 },
	{ key = "RP-Horde", label = "RP-Horde (3:120)", rid = 3, hid = 120 },
	{ key = "RP-Alliance", label = "RP-Alliance (3:119)", rid = 3, hid = 119 },
	{ key = "RP-Blackwater", label = "RP-Blackwater (3:121)", rid = 3, hid = 121 },
	{ key = "RPPvP-Horde", label = "RPPvP-Horde (15:124)", rid = 15, hid = 124 },
	{ key = "RPPvP-Alliance", label = "RPPvP-Alliance (15:123)", rid = 15, hid = 123 },
	{ key = "RPPvP-Blackwater", label = "RPPvP-Blackwater (15:125)", rid = 15, hid = 125 },
	{ key = "custom", label = "Custom (ruleset:house=Economy)" },
}

CE.INSTALL_COMMANDS = {
	windows = "py -m pip install --upgrade https://github.com/JustBenji/MerchantMaster-Snapshots/archive/refs/heads/main.zip; py -m snapshot_builder setup-gui",
	windowsAlt = "python -m pip install --upgrade https://github.com/JustBenji/MerchantMaster-Snapshots/archive/refs/heads/main.zip; python -m snapshot_builder setup-gui",
	linux = "curl -fsSL https://raw.githubusercontent.com/JustBenji/MerchantMaster-Snapshots/main/install_linux.py -o install_linux.py && python3 install_linux.py",
	macos = "python3 -m pip install --upgrade https://github.com/JustBenji/MerchantMaster-Snapshots/archive/refs/heads/main.zip && python3 -m snapshot_builder setup-gui",
	guideUrl = "https://github.com/JustBenji/MerchantMaster-Snapshots",
	linuxScriptUrl = "https://raw.githubusercontent.com/JustBenji/MerchantMaster-Snapshots/main/install_linux.py",
}

local function quoteShellArg(s)
	return '"' .. tostring(s or ""):gsub('"', '\\"') .. '"'
end

local function normalizeOsMode(v)
	local m = safeStr(v, "windows"):lower()
	if m == "linux" or m == "macos" then
		return m
	end
	return "windows"
end

function CE.GetServerPresets()
	local ext = CE.GetSnapshotExtension()
	if ext and type(ext.serverPresets) == "table" and #ext.serverPresets > 0 then
		return ext.serverPresets
	end
	return DEFAULT_SERVER_PRESETS
end

local function buildFallbackSetupCommands(cfg)
	local opts = type(cfg) == "table" and cfg or {}
	local osMode = normalizeOsMode(opts.osMode)
	local snapDir = safeStr(opts.snapDir, "")
	if snapDir == "" then snapDir = safeStr(opts.mmDir, "") end
	if snapDir == "" then snapDir = safeStr(opts.dir, "") end

	local region = safeStr(opts.region, "eu"):lower()
	if region ~= "eu" and region ~= "us" and region ~= "kr" and region ~= "tw" then
		region = "eu"
	end

	local presetKey = safeStr(opts.presetKey, "Normal-Horde")
	local houseArg = "2:114=Normal-Horde"
	if presetKey == "custom" then
		local cust = safeStr(opts.customHouse, ""):match("^%s*(.-)%s*$")
		houseArg = cust ~= "" and cust or "2:114=Normal-Horde"
	else
		local presets = CE.GetServerPresets()
		for _, p in ipairs(presets) do
			if p.key == presetKey and p.rid and p.hid then
				houseArg = format("%d:%d=%s", p.rid, p.hid, p.key)
				break
			end
		end
	end

	local intervalMin = max(1, min(1439, floor(tonumber(opts.intervalMin) or 15)))
	local retentionDays = max(7, min(365, floor(tonumber(opts.retentionDays) or 30)))
	local maxExportMB = max(2, min(64, floor(tonumber(opts.maxExportMB) or 8)))
	local dbPath = safeStr(opts.dbPath, ""):match("^%s*(.-)%s*$")
	local outDir = safeStr(opts.outDir, ""):match("^%s*(.-)%s*$")

	local cmdPrefix
	if osMode == "linux" then
		if snapDir ~= "" then
			cmdPrefix = format("cd %s && ~/.local/bin/mm-snapshots ", quoteShellArg(snapDir))
		else
			cmdPrefix = "~/.local/bin/mm-snapshots "
		end
	elseif osMode == "macos" then
		local py = safeStr(opts.pythonExe, "")
		if py == "" then py = "python3" end
		if snapDir ~= "" then
			cmdPrefix = format("cd %s && %s -m snapshot_builder ", quoteShellArg(snapDir), quoteShellArg(py))
		elseif py ~= "python3" then
			cmdPrefix = format("%s -m snapshot_builder ", quoteShellArg(py))
		else
			cmdPrefix = "python3 -m snapshot_builder "
		end
	else
		local py = safeStr(opts.pythonExe, "")
		if py == "" then py = "python" end
		if snapDir ~= "" then
			cmdPrefix = format("cd %s; & %s -m snapshot_builder ", quoteShellArg(snapDir), quoteShellArg(py))
		elseif py ~= "python" then
			cmdPrefix = format("& %s -m snapshot_builder ", quoteShellArg(py))
		else
			cmdPrefix = "python -m snapshot_builder "
		end
	end

	local guiCmd = cmdPrefix .. "setup-gui"

	local cfgParts = { "configure" }
	if osMode ~= "windows" then
		cfgParts[#cfgParts + 1] = "--prompt-creds"
	end
	cfgParts[#cfgParts + 1] = "--region"
	cfgParts[#cfgParts + 1] = region
	cfgParts[#cfgParts + 1] = "--clear-houses"
	cfgParts[#cfgParts + 1] = "--house"
	cfgParts[#cfgParts + 1] = quoteShellArg(houseArg)
	cfgParts[#cfgParts + 1] = "--every-minutes"
	cfgParts[#cfgParts + 1] = tostring(intervalMin)
	cfgParts[#cfgParts + 1] = "--retention-days"
	cfgParts[#cfgParts + 1] = tostring(retentionDays)
	cfgParts[#cfgParts + 1] = "--max-export-mb"
	cfgParts[#cfgParts + 1] = tostring(maxExportMB)
	if dbPath ~= "" then
		cfgParts[#cfgParts + 1] = "--db-path"
		cfgParts[#cfgParts + 1] = quoteShellArg(dbPath)
	end
	if outDir ~= "" then
		cfgParts[#cfgParts + 1] = "--out-dir"
		cfgParts[#cfgParts + 1] = quoteShellArg(outDir)
	end
	cfgParts[#cfgParts + 1] = "--apply-task"
	cfgParts[#cfgParts + 1] = "--sync-now"
	local configureCmd = cmdPrefix .. table.concat(cfgParts, " ")

	local apiKeyCmd
	if osMode == "windows" then
		apiKeyCmd = table.concat({
			'setx BLIZZARD_CLIENT_ID "<YOUR_CLIENT_ID>";',
			'setx BLIZZARD_CLIENT_SECRET "<YOUR_CLIENT_SECRET>";',
			format("setx BLIZZARD_REGION %s;", region),
			format("%sdiscover --region %s --save-house %s", cmdPrefix, region, quoteShellArg(houseArg)),
		}, "\n")
	else
		apiKeyCmd = table.concat({
			format("%sconfigure --region %s --clear-houses --house %s --prompt-creds", cmdPrefix, region, quoteShellArg(houseArg)),
			format("%sdiscover --region %s --save-house %s", cmdPrefix, region, quoteShellArg(houseArg)),
		}, "\n")
	end

	local discoverCmd = format("%sdiscover --region %s", cmdPrefix, region)

	return {
		guiCmd = guiCmd,
		configureCmd = configureCmd,
		apiKeyCmd = apiKeyCmd,
		discoverCmd = discoverCmd,
		houseSpec = houseArg,
		region = region,
		osMode = osMode,
	}
end

function CE.BuildSetupCommands(cfg)
	local opts = type(cfg) == "table" and cfg or {}
	local osMode = normalizeOsMode(opts.osMode)
	local ext = CE.GetSnapshotExtension()
	if ext and type(ext.buildSetupCommands) == "function"
		and (ext.supportsOsMode or osMode == "windows") then
		return ext.buildSetupCommands(opts)
	end
	return buildFallbackSetupCommands(opts)
end

function CE.CollectStorageSnapshot()
	local updateMem = (_G.C_AddOns and _G.C_AddOns.UpdateAddOnMemoryUsage) or _G.UpdateAddOnMemoryUsage
	if type(updateMem) == "function" then
		pcall(updateMem)
	end

	local mmMemKB = queryAddonMemoryKB(ADDON or "MerchantMaster") or 0
	local snapMemKB = isAddonLoadedSafe("MerchantMaster_Snapshots")
		and (queryAddonMemoryKB("MerchantMaster_Snapshots") or 0) or 0
	local mapPinsMemKB = isAddonLoadedSafe("MerchantMaster_MapPins")
		and (queryAddonMemoryKB("MerchantMaster_MapPins") or 0) or 0

	local mmDB = type(_G.MerchantMasterDB) == "table" and _G.MerchantMasterDB or {}
	local profDB = type(mmDB.professor) == "table" and mmDB.professor or {}
	local ledgerDB = type(_G.MerchantMasterLedgerDB) == "table" and _G.MerchantMasterLedgerDB or {}

	local savedTables = {}
	local function addSaved(store, key, label, tbl, rowsOverride, fields)
		local entries, estBytes = CE.EstimateTable(tbl, 4)
		savedTables[#savedTables + 1] = {
			id = store .. "." .. key,
			store = store,
			key = key,
			label = label,
			rows = rowsOverride ~= nil and rowsOverride or entries,
			estBytes = estBytes,
			fields = fields,
		}
	end

	addSaved("MerchantMasterDB", "ahPrices", "Live AH Prices", mmDB.ahPrices,
		countNestedEconomyItems(mmDB.ahPrices),
		"economy -> itemID -> {price, lastPrice, lastAt, qty, absent, at, itemWide}, _scannedAt")
	addSaved("MerchantMasterDB", "ahLots", "Order-Book Lots", mmDB.ahLots,
		countNestedEconomyItems(mmDB.ahLots),
		"economy -> itemID -> {at, lots=[{price, qty, minRemain}]}")
	addSaved("MerchantMasterDB", "ahHistory", "AH Price Ring History", mmDB.ahHistory,
		countNestedEconomyItems(mmDB.ahHistory),
		"economy -> itemID -> packed 7d ring (ts, price, qty)")
	addSaved("MerchantMasterDB", "ahDaily", "AH Daily Buckets", mmDB.ahDaily,
		countNestedEconomyItems(mmDB.ahDaily),
		"economy -> itemID -> packed 14d buckets (d, minP, maxP, lastP, obsP, lastQ, maxQ, at)")
	addSaved("MerchantMasterDB", "ahSnapshots", "AH Hourly Snapshots", mmDB.ahSnapshots,
		countNestedEconomyItems(mmDB.ahSnapshots),
		"economy -> itemID -> packed snapshot deltas")
	addSaved("MerchantMasterDB", "sellerStats", "Seller Concentration Cache", mmDB.sellerStats,
		countMapItems(mmDB.sellerStats),
		"economy -> {incompleteItems, variants, sellers}")
	addSaved("MerchantMasterDB", "chars", "Characters (Bags/Bank/Mail/CDs)", mmDB.chars,
		countMapItems(mmDB.chars),
		"charKey -> {name, realm, faction, economy, bags, bank, mail, knownSpells, cooldowns, cooldownGroups, writCooldowns}")
	addSaved("MerchantMasterDB", "sniper", "Sniper Config & History", mmDB.sniper,
		countMapItems(mmDB.sniper),
		"gapScope, minGapPct, minRoiPct, minProfitCopper, maxSpendCopper, vendorIncludeCommodities, vendorAutoFromBrowse")
	addSaved("MerchantMasterDB", "ahSeller", "AH Seller & Favorites", mmDB.ahSeller,
		countMapItems(mmDB.ahSeller),
		"undercutMode, undercutOffset, postDuration, stackSize, minFloorPct, favorites")
	if CE.HasMapPinsExtension() then
		local app = ns.app
		local mapOpts = (app and app.mapPinsProvider and type(app.mapPinsProvider.GetOptions) == "function" and app.mapPinsProvider.GetOptions())
			or (_G.MerchantMaster_MapPinsDB)
			or mmDB.mapPins
		local mapStore = (_G.MerchantMaster_MapPinsDB ~= nil or (app and app.mapPinsProvider and type(app.mapPinsProvider.GetOptions) == "function"))
			and "MerchantMaster_MapPinsDB"
			or "MerchantMasterDB"
		addSaved(mapStore, "mapPins", "World Map Pins Options", mapOpts,
			countMapItems(mapOpts),
			"enabled, allProfessions, hideKnown")
	end
	addSaved("MerchantMasterDB", "shoppingList", "Shopping List Basket", mmDB.shoppingList,
		#(type(mmDB.shoppingList) == "table" and mmDB.shoppingList or {}),
		"array of {itemID, name, count, source, lineCost}")

	local profRows = countMapItems(profDB.knownSpells) + countMapItems(profDB.trainerCosts)
	addSaved("MerchantMasterDB", "professor", "Professor 1-300 Data", profDB,
		profRows,
		"knownSpells, trainerCosts, trainerReqs, trainerReqsByName, subCraftMode, activeTab")

	-- Remaining settings & queues in MerchantMasterDB
	local excludedKeys = {
		ahPrices = true, ahLots = true, ahHistory = true, ahDaily = true,
		ahSnapshots = true, sellerStats = true, chars = true, sniper = true,
		ahSeller = true, mapPins = true, shoppingList = true, professor = true,
	}
	local miscRows, miscBytes = 0, 0
	for k, v in pairs(mmDB) do
		if readable(k) and not excludedKeys[k] then
			miscRows = miscRows + 1
			if type(v) == "table" then
				local _, eb = CE.EstimateTable(v, 3)
				miscBytes = miscBytes + eb + #tostring(k)
			else
				miscBytes = miscBytes + #tostring(k) + #tostring(v) + 12
			end
		end
	end
	savedTables[#savedTables + 1] = {
		id = "MerchantMasterDB.settings",
		store = "MerchantMasterDB",
		key = "settings",
		label = "Addon Settings & Queues",
		rows = miscRows,
		estBytes = miscBytes,
		fields = "economy, priceSource, useTSMPrices, uiSkin, uiThemeMode, tableStyle, consolePerfEnabled, consoleStats, queues",
	}

	-- MerchantMasterLedgerDB breakdown
	local ledgerRows = 0
	for _, d in pairs(type(ledgerDB.days) == "table" and ledgerDB.days or {}) do
		if type(d) == "table" then
			if type(d.r) == "table" then
				ledgerRows = ledgerRows + #d.r
			elseif type(d.s) == "string" and d.s ~= "" then
				local cnt = 1
				for _ in d.s:gmatch("\n") do cnt = cnt + 1 end
				ledgerRows = ledgerRows + cnt
			end
		end
	end
	local storeMod = ns.Analytics and ns.Analytics.Store
	local ledgerBytes = (storeMod and type(storeMod.EstimateBytes) == "function")
		and storeMod.EstimateBytes() or select(2, CE.EstimateTable(ledgerDB, 3))
	savedTables[#savedTables + 1] = {
		id = "MerchantMasterLedgerDB.days",
		store = "MerchantMasterLedgerDB",
		key = "days",
		label = "Analytics Ledger Events",
		rows = ledgerRows,
		estBytes = ledgerBytes,
		fields = "days (tx events), roll, loot, basis, lots, ret, pouches, snaps, wealth, seenMail, stats, probe, archivedRoll, archivedLoot, basisEvents",
	}

	local totalSavedBytes = 0
	for _, row in ipairs(savedTables) do
		totalSavedBytes = totalSavedBytes + (row.estBytes or 0)
	end

	local snapExt = CE.GetSnapshotExtension()
	local hasSnap = (snapExt ~= nil) or (type(ns.HasSnapshots) == "function" and ns.HasSnapshots() == true)
	local sysMeta = hasSnap and ns.Pricing and type(ns.Pricing.GetSnapshotSystemMeta) == "function"
		and ns.Pricing.GetSnapshotSystemMeta() or nil
	local sqliteTables = {}
	if hasSnap then
		local extTables = (snapExt and type(snapExt.GetSQLiteTables) == "function")
			and snapExt.GetSQLiteTables() or nil
		if type(extTables) == "table" and #extTables > 0 then
			for _, t in ipairs(extTables) do
				sqliteTables[#sqliteTables + 1] = {
					id = t.id or ("sqlite." .. tostring(t.n or t.key)),
					store = t.store or "snapshots.sqlite3",
					key = tostring(t.key or t.n or ""),
					label = tostring(t.label or t.n or t.key or ""),
					rows = tonumber(t.rows or t.r) or 0,
					cols = tonumber(t.cols or t.c) or 0,
					fields = tostring(t.fields or t.f or ""),
				}
			end
		elseif type(sysMeta) == "table" and type(sysMeta.tables) == "table" then
			for _, t in ipairs(sysMeta.tables) do
				sqliteTables[#sqliteTables + 1] = {
					id = "sqlite." .. tostring(t.n),
					store = "snapshots.sqlite3",
					key = tostring(t.n),
					label = tostring(t.n),
					rows = tonumber(t.r) or 0,
					cols = tonumber(t.c) or 0,
					fields = tostring(t.f or ""),
				}
			end
		end
	end

	local mapExt = ns.app and ns.app.mapPinsProvider or nil
	local npcPinCount = nil
	if mapExt ~= nil then
		if type(mapExt.GetPinCount) == "function" then
			npcPinCount = safeNum(mapExt.GetPinCount(), 0) or 0
		else
			npcPinCount = countMapItems(ns.NPC_PINS)
		end
	end

	local staticCatalog = {
		items = countMapItems(ns.ITEMS),
		recipes = #(type(ns.RECIPES) == "table" and ns.RECIPES or {}),
		writs = #(type(ns.WRITS) == "table" and ns.WRITS or {}),
		crates = #(type(ns.CRATES) == "table" and ns.CRATES or {}),
		npcPins = npcPinCount,
	}

	local addonState = CE.GetAddonState("MerchantMaster_Snapshots")
	local dbBytes = sysMeta and (tonumber(sysMeta.dbBytes) or 0) or 0
	local walBytes = sysMeta and (tonumber(sysMeta.walBytes) or 0) or 0
	local shmBytes = sysMeta and (tonumber(sysMeta.shmBytes) or 0) or 0
	local logBytes = sysMeta and (tonumber(sysMeta.logBytes) or 0) or 0
	local exportBytes = sysMeta and (tonumber(sysMeta.exportBytes) or 0) or 0
	local exportCapBytes = sysMeta and (tonumber(sysMeta.exportCapBytes) or 0) or 0
	local sqliteBytes = dbBytes + walBytes + shmBytes
	local dataDirBytes = 0
	if sysMeta then
		dataDirBytes = max(sqliteBytes + logBytes, tonumber(sysMeta.localDataDirBytes) or 0)
	end
	local snapshotDiskTotalBytes = dataDirBytes + exportBytes
	local snapshotRows = 0
	for _, st in ipairs(sqliteTables) do
		if st.key == "snapshots" then
			snapshotRows = tonumber(st.rows) or 0
			break
		end
	end
	local diskSummary = {
		addonState = addonState,
		hasSnapshots = hasSnap,
		dbBytes = dbBytes,
		walBytes = walBytes,
		shmBytes = shmBytes,
		logBytes = logBytes,
		exportBytes = exportBytes,
		exportCapBytes = exportCapBytes,
		sqliteBytes = sqliteBytes,
		dataDirBytes = dataDirBytes,
		snapshotDiskTotalBytes = snapshotDiskTotalBytes,
		savedVarsBytes = totalSavedBytes,
		combinedTotalBytes = snapshotDiskTotalBytes + totalSavedBytes,
		snapshotRuns = sysMeta and (tonumber(sysMeta.totalRuns) or 0) or 0,
		snapshotRows = snapshotRows,
		retentionDays = sysMeta and (tonumber(sysMeta.retentionDays) or 30) or 0,
		errRuns = sysMeta and (tonumber(sysMeta.errRuns) or 0) or 0,
		intervalMin = sysMeta and (tonumber(sysMeta.intervalMin) or 15) or 0,
		truncated = sysMeta and (sysMeta.truncated == true) or false,
		dbPath = sysMeta and tostring(sysMeta.dbPath or "") or "",
		outDir = sysMeta and tostring(sysMeta.outDir or "") or "",
		exportedAt = sysMeta and (tonumber(sysMeta.exportedAt) or 0) or 0,
	}

	return {
		ram = {
			merchantMasterKB = mmMemKB,
			snapshotsKB = snapMemKB,
			mapPinsKB = mapPinsMemKB,
			totalKB = mmMemKB + snapMemKB + mapPinsMemKB,
		},
		savedTables = savedTables,
		totalSavedBytes = totalSavedBytes,
		sqliteTables = sqliteTables,
		sysMeta = sysMeta,
		diskSummary = diskSummary,
		staticCatalog = staticCatalog,
	}
end

---------------------------------------------------------------------------------------------------
-- Debugger Copy-Paste Support Bundle
---------------------------------------------------------------------------------------------------

local function isSensitiveKey(k)
	local s = tostring(k):lower()
	if s:find("secret", 1, true) or s:find("password", 1, true)
		or s:find("token", 1, true) or s:find("client_id", 1, true)
		or s:find("auth", 1, true) then
		return true
	end
	return false
end

local SKIP_SETTINGS_SUBTABLES = {
	ahPrices = true, ahLots = true, ahHistory = true, ahDaily = true,
	ahSnapshots = true, sellerStats = true, chars = true, shoppingList = true,
	learnedWritZones = true, liveVendorSell = true, liveVendorBuy = true,
	liveVendorBuyGlobal = true, regionSalesCache = true, econSnapshots = true,
	costs = true, itemIDs = true, knownSpells = true, learnedSchematics = true,
	outlierPrices = true, subCraftOverrides = true, writCraftQueue = true,
	spreadQueue = true, writTurnInQueue = true, forgedTurnInQueue = true,
	craftOrderQueue = true, professor = true, consoleStats = true,
	trainerCosts = true, trainerReqs = true, trainerReqsByName = true,
}

local function isRedactedIdentityKey(key)
	local k = tostring(key or ""):lower()
	return k == "_targetscharkey" or k == "anchar" or k:find("char", 1, true) ~= nil
		or k:find("realm", 1, true) ~= nil or k:find("player", 1, true) ~= nil or k:find("owner", 1, true) ~= nil
end

local function redactIdentityText(text, redactCtx)
	local out = tostring(text or "")
	if not redactCtx or not redactCtx.enabled then return out end
	for _, needle in ipairs(redactCtx.needles or {}) do
		if needle ~= "" then
			out = out:gsub(needle:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"), "[REDACTED]")
		end
	end
	return out
end

local function appendSortedScalars(lines, prefix, tbl, redactCtx)
	if type(tbl) ~= "table" or not readable(tbl) then return end
	local keys = {}
	for k, v in pairs(tbl) do
		if readable(k) and readable(v) and not isSensitiveKey(k) and not SKIP_SETTINGS_SUBTABLES[k] then
			local vt = type(v)
			if vt == "string" or vt == "number" or vt == "boolean" then
				keys[#keys + 1] = tostring(k)
			end
		end
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local rawVal = tbl[k]
		local valStr = asciiSafe(tostring(rawVal))
		if redactCtx and redactCtx.enabled then
			if type(rawVal) == "string" and isRedactedIdentityKey(k) then
				local low = rawVal:lower()
				if low ~= "" and low ~= "all" and low ~= "mine" and low ~= "known" and low ~= "none" and low ~= "?" then
					valStr = "[REDACTED]"
				end
			else
				valStr = redactIdentityText(valStr, redactCtx)
			end
		end
		lines[#lines + 1] = format("  %s.%s = %s", prefix, k, valStr)
	end
end

function CE.BuildDebugBundle(opts)
	opts = type(opts) == "table" and opts or {}
	local incSettings = opts.includeSettings ~= false
	local incDB = opts.includeDatabase ~= false
	local incPerf = opts.includePerf ~= false
	local incLogs = opts.includeLogs ~= false
	local redact = opts.redactNames ~= false

	local now = (_G.time and _G.time()) or 0
	local lines = {
		"=== MERCHANTMASTER DEBUG BUNDLE v1 ===",
		"generatedAt=" .. CE.FormatTimestamp(now) .. " (epoch=" .. tostring(now) .. ")",
	}

	local buildVer, buildNum, buildDate, ifaceVer = "", "", "", ""
	if type(_G.GetBuildInfo) == "function" then
		local ok, v1, v2, v3, v4 = pcall(_G.GetBuildInfo)
		if ok then
			buildVer = asciiSafe(v1 ~= nil and tostring(v1) or "")
			buildNum = asciiSafe(v2 ~= nil and tostring(v2) or "")
			buildDate = asciiSafe(v3 ~= nil and tostring(v3) or "")
			ifaceVer = asciiSafe(v4 ~= nil and tostring(v4) or "")
		end
	end
	local addonVer = asciiSafe((type(ns.GetAddonVersion) == "function" and ns.GetAddonVersion()) or "dev")
	local locale = (_G.GetLocale and safeStr(_G.GetLocale(), "enUS")) or "enUS"
	local econInfo = ns.CurrentEconomyInfo and ns.CurrentEconomyInfo() or {}
	local app = ns.app
	local charObj = (app and app.char) or {}
	local rawPlayerName = asciiSafe(safeStr(charObj.name, (ns.GetPlayerFullName and ns.GetPlayerFullName()) or (_G.UnitName and _G.UnitName("player")) or ""))
	local rawFirstName = asciiSafe(safeStr(charObj.firstName, ""))
	local rawUnitName = asciiSafe(safeStr(_G.UnitName and _G.UnitName("player") or "", ""))
	local rawRealmName = asciiSafe(safeStr(charObj.realm, (_G.GetRealmName and _G.GetRealmName()) or ""))
	local needleSeen, redactNeedles = {}, {}
	local function addRedactNeedle(s)
		if type(s) ~= "string" then return end
		local clean = asciiSafe(s)
		if #clean >= 3 and clean ~= "?" and clean ~= "all" and clean ~= "mine" and not needleSeen[clean] then
			needleSeen[clean] = true
			redactNeedles[#redactNeedles + 1] = clean
		end
	end
	addRedactNeedle(app and app.charKey or "")
	addRedactNeedle(rawPlayerName)
	addRedactNeedle(rawFirstName)
	addRedactNeedle(rawUnitName)
	addRedactNeedle(rawRealmName)
	local charsTbl = type(_G.MerchantMasterDB) == "table" and type(_G.MerchantMasterDB.chars) == "table" and _G.MerchantMasterDB.chars or nil
	if charsTbl and readable(charsTbl) then
		for ck, cdata in pairs(charsTbl) do
			if type(ck) == "string" then addRedactNeedle(ck) end
			if type(cdata) == "table" and readable(cdata) then
				addRedactNeedle(cdata.name)
				addRedactNeedle(cdata.firstName)
				addRedactNeedle(cdata.realm)
			end
		end
	end
	table.sort(redactNeedles, function(a, b) return #a > #b end)
	local redactCtx = { enabled = redact, needles = redactNeedles }
	local playerName = redact and "[REDACTED]" or (rawPlayerName ~= "" and rawPlayerName or "?")
	local realmName = redact and "[REDACTED]" or (rawRealmName ~= "" and rawRealmName or "?")
	local faction = asciiSafe(safeStr(charObj.faction, (_G.UnitFactionGroup and _G.UnitFactionGroup("player")) or "?"))
	local T = ns.Theme

	lines[#lines + 1] = ""
	lines[#lines + 1] = "[ENVIRONMENT]"
	lines[#lines + 1] = format("  addonVersion=%s wowBuild=%s(%s) buildDate=%s interface=%s locale=%s",
		addonVer, buildVer, buildNum, buildDate ~= "" and buildDate or "?", ifaceVer, asciiSafe(locale))
	lines[#lines + 1] = format("  activeTab=%s economy=%s char=%s realm=%s faction=%s",
		asciiSafe(safeStr(app and app.activeTab, "?")),
		asciiSafe(safeStr(econInfo.effectiveKey, "?")),
		playerName, realmName, faction)
	lines[#lines + 1] = format("  themeMode=%s uiSkin=%s tableStyle=%s priceDisplay=%s",
		asciiSafe(T and T.GetMode and T.GetMode() or "?"),
		asciiSafe(T and T.GetSkin and T.GetSkin() or "?"),
		asciiSafe(T and T.GetTableStyle and T.GetTableStyle() or "?"),
		asciiSafe(T and T.GetPriceDisplayMode and T.GetPriceDisplayMode() or "?"))

	local storage = CE.CollectStorageSnapshot()
	local snapExt = app and type(app.snapshotExtension) == "table" and app.snapshotExtension or nil
	local mapExt = app and type(app.mapPinsProvider) == "table" and app.mapPinsProvider or nil
	local snapStatus = getCompanionStatus("MerchantMaster_Snapshots", snapExt)
	local mapStatus = getCompanionStatus("MerchantMaster_MapPins", mapExt)

	local function fmtCompanion(name, status, provider)
		if type(provider) == "table" then
			local ver = asciiSafe(safeStr(provider.version, "?"))
			local apiV = asciiSafe(tostring(provider.apiVersion or "?"))
			return format("%s=%s(v=%s,api=%s)", name, status, ver, apiV)
		end
		return format("%s=%s", name, status)
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = "[ADDONS & MEMORY]"
	local memParts = { format("MerchantMaster=%.1f KB", storage.ram.merchantMasterKB or 0) }
	if snapStatus == "loaded" or (storage.ram.snapshotsKB or 0) > 0 then
		memParts[#memParts + 1] = format("Snapshots=%.1f KB", storage.ram.snapshotsKB or 0)
	end
	if mapStatus == "loaded" or (storage.ram.mapPinsKB or 0) > 0 then
		memParts[#memParts + 1] = format("MapPins=%.1f KB", storage.ram.mapPinsKB or 0)
	end
	lines[#lines + 1] = "  " .. table.concat(memParts, " | ")
	lines[#lines + 1] = "  " .. fmtCompanion("MerchantMaster_Snapshots", snapStatus, snapExt)
		.. ", " .. fmtCompanion("MerchantMaster_MapPins", mapStatus, mapExt)

	if incSettings then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "[SETTINGS]"
		local mmDB = type(_G.MerchantMasterDB) == "table" and _G.MerchantMasterDB or {}
		appendSortedScalars(lines, "MerchantMasterDB", mmDB, redactCtx)
		appendSortedScalars(lines, "sniper", mmDB.sniper, redactCtx)
		appendSortedScalars(lines, "ahSeller", mmDB.ahSeller, redactCtx)
		if CE.HasMapPinsExtension() then
			local mapOpts = (app and app.mapPinsProvider and type(app.mapPinsProvider.GetOptions) == "function" and app.mapPinsProvider.GetOptions())
				or _G.MerchantMaster_MapPinsDB
				or mmDB.mapPins
			if type(mapOpts) == "table" then
				appendSortedScalars(lines, "mapPins", mapOpts, redactCtx)
			end
		end
		if type(mmDB.professor) == "table" then
			appendSortedScalars(lines, "professor", mmDB.professor, redactCtx)
		end
	end

	if incDB then
		lines[#lines + 1] = ""
		lines[#lines + 1] = CE.HasSnapshotExtension() and "[DATABASE & SNAPSHOTS]" or "[DATABASE]"
		local catLine = format("  SavedVariablesEst=%s | CatalogItems=%d Recipes=%d Writs=%d Crates=%d",
			CE.FormatBytes(storage.totalSavedBytes),
			storage.staticCatalog.items, storage.staticCatalog.recipes,
			storage.staticCatalog.writs, storage.staticCatalog.crates)
		if storage.staticCatalog.npcPins ~= nil then
			catLine = catLine .. format(" NpcPins=%d", storage.staticCatalog.npcPins)
		end
		lines[#lines + 1] = catLine
		for _, r in ipairs(storage.savedTables) do
			lines[#lines + 1] = format("  SV %s.%s: rows=%d est=%s", r.store, r.key, r.rows, CE.FormatBytes(r.estBytes))
		end

		local ref = CE.GetRefreshSummary()
		lines[#lines + 1] = format("  ManualAH: full=%d partial=%d single=%d deepLot=%d lastFullAt=%s items=%d sec=%.1f",
			ref.manualFullScans, ref.manualPartialScans, ref.manualSingleRefreshes,
			ref.manualDeepLotScans, CE.FormatTimestamp(ref.lastFullScanAt),
			ref.lastFullScanItems, ref.lastFullScanSec)
		if CE.HasSnapshotExtension() or ref.snapMeta or storage.sysMeta then
			if ref.snapMeta then
				local m = ref.snapMeta
				lines[#lines + 1] = format("  SnapshotMeta(%s): updatedAt=%s source=%s items=%d heat=%d depth=%d vel=%d obsH=%d",
					ref.activeEcon, CE.FormatTimestamp(m.updatedAt), asciiSafe(m.source),
					m.itemCount or 0, m.heatmapCount or 0, m.depthCount or 0, m.velocityCount or 0, m.velocityObsHours or 0)
			end
			local sys = storage.sysMeta
			if sys then
				lines[#lines + 1] = format("  SQLite: dbBytes=%s wal=%s shm=%s pages=%d freelist=%d journal=%s export=%s/%s trunc=%s",
					CE.FormatBytes(sys.dbBytes), CE.FormatBytes(sys.walBytes), CE.FormatBytes(sys.shmBytes),
					sys.pageCount, sys.freelist, asciiSafe(sys.journalMode),
					CE.FormatBytes(sys.exportBytes), CE.FormatBytes(sys.exportCapBytes), tostring(sys.truncated))
				lines[#lines + 1] = format("  Runner: region=%s credsSet=%s task=%s(%s) every=%dm retention=%dd runs=%d blizz=%d err=%d",
					asciiSafe(sys.region), tostring(sys.credsSet), asciiSafe(sys.taskStatus),
					tostring(sys.taskEnabled), sys.intervalMin, sys.retentionDays,
					sys.totalRuns, sys.blizzRuns, sys.errRuns)
				lines[#lines + 1] = format("  HouseMap: %s | SyncLog: %s polls=%d 304=%d exports=%d logErr=%d",
					asciiSafe(sys.houseMap), CE.FormatBytes(sys.logBytes),
					sys.logPolls, sys.log304, sys.logExports, sys.logErrors)
				if sys.lastError ~= "" then
					lines[#lines + 1] = "  LastSyncError: " .. redactIdentityText(asciiSafe(sys.lastError), redactCtx)
				end
				for _, t in ipairs(storage.sqliteTables) do
					lines[#lines + 1] = format("  SQLiteTable %s: rows=%d cols=%d", t.key, t.rows, t.cols)
				end
			else
				lines[#lines + 1] = "  SnapshotCompanion: registered, SYSTEM telemetry pending"
			end
		end
	end

	if incPerf then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "[PERFORMANCE & PROFILER]"
		local ps = CE.GetPerfSnapshot()
		lines[#lines + 1] = format("  runtimeProfiler=%s txTotal=%d txAvgMs=%.3f txMaxMs=%.3f",
			ps.enabled and "ON" or "OFF", ps.txTotal, ps.txAvgMs, ps.txMaxMs)
		for _, k in ipairs(ps.txByKind) do
			lines[#lines + 1] = format("    TX %s: count=%d avg=%.3fms max=%.3fms last=%.3fms",
				asciiSafe(k.kind), k.count, k.avgMs, k.maxMs, k.lastMs)
		end
		for _, u in ipairs(ps.uiByTab) do
			lines[#lines + 1] = format("    UI %s: count=%d avg=%.3fms max=%.3fms last=%.3fms",
				asciiSafe(u.tab), u.count, u.avgMs, u.maxMs, u.lastMs)
		end
	end

	if incLogs then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "[ERRORS & PROBE LOG]"
		local ldb = type(_G.MerchantMasterLedgerDB) == "table" and _G.MerchantMasterLedgerDB or nil
		local stats = ldb and type(ldb.stats) == "table" and ldb.stats or {}
		local storeMod = ns.Analytics and ns.Analytics.Store
		lines[#lines + 1] = format("  LedgerReadOnly=%s ProbeEnabled=%s",
			tostring(storeMod and storeMod.readOnly == true),
			tostring(ldb and type(ldb.probe) == "table" and ldb.probe.enabled == true))
		local errCnt = 0
		for k, v in pairs(type(stats.errors) == "table" and stats.errors or {}) do
			errCnt = errCnt + 1
			local dis = type(stats.disabled) == "table" and stats.disabled[k] == true
			lines[#lines + 1] = format("  ErrorKind %s: count=%s disabled=%s",
				asciiSafe(tostring(k)), tostring(v), tostring(dis))
		end
		if errCnt == 0 then
			lines[#lines + 1] = "  LedgerErrors: 0"
		end
		local plog = ldb and type(ldb.probe) == "table" and type(ldb.probe.log) == "table" and ldb.probe.log or {}
		lines[#lines + 1] = format("  ProbeLogEntries=%d", #plog)
		local startIdx = max(1, #plog - 49)
		for i = startIdx, #plog do
			local e = plog[i]
			if type(e) == "table" then
				lines[#lines + 1] = format("    [%s] %s: %s",
					CE.FormatTimestamp(e.at), asciiSafe(safeStr(e.tag, "")), redactIdentityText(asciiSafe(safeStr(e.msg, "")), redactCtx))
			end
		end
	end

	lines[#lines + 1] = "=== END DEBUG BUNDLE ==="
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------------------------------
-- Data Management & Maintenance Actions
---------------------------------------------------------------------------------------------------

function CE.PreviewPruneLedger(days)
	local d = max(7, floor(tonumber(days) or 30))
	local storeMod = ns.Analytics and ns.Analytics.Store
	if not storeMod or type(storeMod.PreviewPrune) ~= "function" then
		return { ok = false, err = "Analytics Store unavailable" }
	end
	local cutoffTs = ((_G.time and _G.time()) or 0) - d * 86400
	local cutoffDay = storeMod.DayKey and storeMod.DayKey(cutoffTs) or "1970-01-01"
	local res = storeMod.PreviewPrune(cutoffDay)
	if type(res) == "table" then
		res.cutoffDay = cutoffDay
		res.days = d
	end
	return res
end

function CE.RunAction(actionKey, arg)
	local app = ns.app
	local mmDB = type(_G.MerchantMasterDB) == "table" and _G.MerchantMasterDB or nil
	local storeMod = ns.Analytics and ns.Analytics.Store
	if actionKey == "pack_ah_history" then
		if ns.MarketScan and type(ns.MarketScan.PackHistoryForSave) == "function" then
			local n = ns.MarketScan.PackHistoryForSave(mmDB)
			return { ok = true, message = format("Packed %d AH history entries.", tonumber(n) or 0) }
		end
		return { ok = false, message = "MarketScan.PackHistoryForSave unavailable." }
	elseif actionKey == "forget_live_ah" then
		if app then
			if type(app.costs) == "table" then wipe(app.costs) end
			if type(app.ahPrices) == "table" then wipe(app.ahPrices) end
		end
		if mmDB and type(mmDB.ahLots) == "table" and ns.MarketScan and ns.MarketScan.ActiveEconomyPrices then
			local _, activeEcon = ns.MarketScan.ActiveEconomyPrices()
			if activeEcon and type(mmDB.ahLots[activeEcon]) == "table" then
				wipe(mmDB.ahLots[activeEcon])
			end
		end
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
		if app and app.refresh then app.refresh() end
		return { ok = true, message = "Cleared saved Live AH prices for active economy." }
	elseif actionKey == "clear_seller_stats" then
		if mmDB and type(mmDB.sellerStats) == "table" then
			wipe(mmDB.sellerStats)
		end
		if app and app.invalidateRecipeStats then app.invalidateRecipeStats("sellers") end
		return { ok = true, message = "Cleared SellerStats cache." }
	elseif actionKey == "clear_sniper_cache" then
		local se = ns.SniperEngine
		if se then
			if type(se.ClearGapDeals) == "function" then se.ClearGapDeals() end
			if type(se.ClearVendorDeals) == "function" then se.ClearVendorDeals() end
			if type(se.ResetSessionStats) == "function" then se.ResetSessionStats() end
			if type(se.ClearDrillCache) == "function" then se.ClearDrillCache() end
			if type(se.ResetNeutralCache) == "function" then se.ResetNeutralCache() end
		end
		if mmDB and type(mmDB.sniper) == "table" then
			mmDB.sniper.history = nil
		end
		return { ok = true, message = "Cleared Sniper session cache." }
	elseif actionKey == "prune_ledger" then
		if not storeMod or type(storeMod.PruneBefore) ~= "function" then
			return { ok = false, message = "Analytics Store unavailable." }
		end
		local days = max(7, floor(tonumber(arg) or 30))
		local cutoffTs = ((_G.time and _G.time()) or 0) - days * 86400
		local cutoffDay = storeMod.DayKey and storeMod.DayKey(cutoffTs) or "1970-01-01"
		local res = storeMod.PruneBefore(cutoffDay)
		if type(res) == "table" and res.ok then
			return {
				ok = true,
				message = format("Pruned %d days (%d rows) before %s.", res.daysToPrune or 0, res.rowsToPrune or 0, cutoffDay),
			}
		end
		return { ok = false, message = "Prune failed: " .. tostring(res and res.err or "unknown") }
	elseif actionKey == "reset_ledger_errors" then
		if storeMod and type(storeMod.ResetErrors) == "function" then
			storeMod.ResetErrors()
			return { ok = true, message = "Reset Analytics capture error counters." }
		end
		return { ok = false, message = "Analytics Store unavailable." }
	elseif actionKey == "queue_wealth_snapshot" then
		local cap = ns.Analytics and ns.Analytics.Capture
		if cap and type(cap.QueueWealthSnapshot) == "function" then
			cap.QueueWealthSnapshot()
			return { ok = true, message = "Queued immediate wealth snapshot." }
		end
		return { ok = false, message = "Analytics Capture unavailable." }
	elseif actionKey == "export_ledger_csv" then
		if storeMod and type(storeMod.Export) == "function" then
			local csv = storeMod.Export({ period = "all" })
			return { ok = true, data = csv, message = format("Exported %d bytes of Ledger CSV.", #csv) }
		end
		return { ok = false, message = "Analytics Store unavailable." }
	elseif actionKey == "clear_probe_log" then
		if type(_G.MerchantMasterLedgerDB) == "table" and type(_G.MerchantMasterLedgerDB.probe) == "table" then
			_G.MerchantMasterLedgerDB.probe.log = {}
		end
		return { ok = true, message = "Cleared Ledger probe log." }
	end
	return { ok = false, message = "Unknown action: " .. tostring(actionKey) }
end
