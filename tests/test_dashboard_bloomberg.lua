-- Verification suite for Bloomberg TV Multi-Pane Workstation Dashboard
-- Tests DashboardBloombergModel + UI_DashboardBloomberg end-to-end with
-- Analytics/Store, UI_Watchlist, MarketScan, UI_DashboardBrief, and MerchantMaster.
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local ns, createdFrames, hostEnv = dofile(testsDir .. "host_fixture.lua")
local check = hostEnv.check
local addonDir = hostEnv.addonDir

if not ns.DashboardBloombergModel then
	local chunk, err = loadfile(addonDir .. "DashboardBloombergModel.lua")
	assert(chunk, "load DashboardBloombergModel.lua failed: " .. tostring(err))
	chunk("MerchantMaster", ns)
end
if not ns.DashboardBloomberg then
	local chunk, err = loadfile(addonDir .. "UI_DashboardBloomberg.lua")
	assert(chunk, "load UI_DashboardBloomberg.lua failed: " .. tostring(err))
	chunk("MerchantMaster", ns)
end

local BModel = ns.DashboardBloombergModel
local BUI = ns.DashboardBloomberg
local Brief = ns.DashboardBrief
local Store = ns.Analytics and ns.Analytics.Store
local AModel = ns.Analytics and ns.Analytics.Model
local WL = ns.Watchlist
local MS = ns.MarketScan
local Theme = ns.Theme

check(type(BModel) == "table", "ns.DashboardBloombergModel loaded")
check(type(BUI) == "table", "ns.DashboardBloomberg loaded")
check(type(Store) == "table", "Analytics.Store available")
check(type(WL) == "table", "ns.Watchlist available")
check(type(MS) == "table", "ns.MarketScan available")
check(type(Brief) == "table", "ns.DashboardBrief available")

local ECON = "Normal-Horde"
local CHAR_MAIN = "Normal-Horde-Forever-Thrall Ironfist"
local BASE_NOW = 1794400000
local DAY_SEC = 86400

local function isDescendantOf(frame, ancestor)
	local cur = frame
	local guard = 0
	while cur and guard < 24 do
		if cur == ancestor then return true end
		cur = cur.GetParent and cur:GetParent() or cur._parent
		guard = guard + 1
	end
	return false
end

local function findButtonsIn(ancestor, predicate)
	local found = {}
	for i = 1, #createdFrames do
		local f = createdFrames[i]
		if f and f ~= ancestor and f:GetObjectType() == "Button" and isDescendantOf(f, ancestor) then
			if not predicate or predicate(f) then
				found[#found + 1] = f
			end
		end
	end
	return found
end

local function findButtonByLabel(ancestor, labelText)
	local list = findButtonsIn(ancestor, function(b)
		return b.label and b.label.GetText and b.label:GetText() == labelText
	end)
	return list[1]
end

local function rectsOverlap(a, b)
	if not a or not b then return false end
	local aL, aR = a.x, a.x + a.w
	local aT, aB = a.y, a.y + a.h
	local bL, bR = b.x, b.x + b.w
	local bT, bB = b.y, b.y + b.h
	return (aL < bR - 0.5) and (aR > bL + 0.5) and (aT < bB - 0.5) and (aB > bT + 0.5)
end

local function resetState(nowTs)
	hostEnv.setFixtureNow(nowTs or BASE_NOW)
	_G.MerchantMasterLedgerDB = {}
	Store.Init()
	if WL and WL.Clear then WL.Clear() end
	if BModel and BModel.InvalidateCache then BModel.InvalidateCache() end
	if Brief and Brief.InvalidateCache then Brief.InvalidateCache() end
	if AModel and AModel.Invalidate then AModel.Invalidate() end
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
end

local function seedCommonMarket(nowTs, opts)
	opts = opts or {}
	local db = _G.MerchantMasterDB
	db.ahPrices = db.ahPrices or {}
	db.ahPrices[ECON] = db.ahPrices[ECON] or {}
	db.ahPrices[ECON]._scannedAt = nowTs - 180
	db.ahDaily = db.ahDaily or {}
	db.ahDaily[ECON] = {}
	db.ahSnapshots = db.ahSnapshots or {}
	db.ahSnapshots[ECON] = {}
	db.ahHistory = db.ahHistory or {}
	db.ahHistory[ECON] = {}

	local curDay = math.floor(nowTs / DAY_SEC)

	-- Green Lens (spell 12622, item 10504) reagents:
	-- 4304 Thick Leather x8, 1529 Jade x3, 7909 Aquamarine x3, 10286 Heart of the Wild x2, 8153 Wildvine x2
	-- Historical baseline: 8*800 + 3*8000 + 3*12000 + 2*16000 + 2*25800 = 6400 + 24000 + 36000 + 32000 + 51600 = 150000c (15g)
	-- Live spiked cost: Wildvine jumps 25800 -> 51600 (+100%, +51600c impact on 2x) -> total 200000c (20g, +33.3%)
	local thickCur = opts.thickCur or 600
	local wildvineCur = opts.wildvineCur or 51600
	local dreamfoilCur = opts.dreamfoilCur or 2600
	local silversageCur = opts.silversageCur or 5200
	local crystalVialCur = opts.crystalVialCur or 500

	local priceMap = {
		[10504] = { cur = 265000, base = 248000, qty = 7 },   -- Green Lens
		[4304]  = { cur = thickCur, base = 800, qty = 140 },  -- Thick Leather
		[1529]  = { cur = 8000, base = 8000, qty = 28 },      -- Jade
		[7909]  = { cur = 12000, base = 12000, qty = 22 },    -- Aquamarine
		[10286] = { cur = 16000, base = 16000, qty = 19 },    -- Heart of the Wild
		[8153]  = { cur = wildvineCur, base = 25800, qty = 14 }, -- Wildvine (top cost driver)
		[13454] = { cur = 78000, base = 74000, qty = 18 },    -- Greater Arcane Elixir
		[13463] = { cur = dreamfoilCur, base = 4200, qty = 64 }, -- Dreamfoil
		[13465] = { cur = silversageCur, base = 6800, qty = 42 }, -- Mountain Silversage
		[8925]  = { cur = crystalVialCur, base = 500, qty = 100 }, -- Crystal Vial
		[13512] = { cur = 685000, base = 610000, qty = 9 },   -- Flask of Supreme Power
		[13452] = { cur = 69000, base = 64000, qty = 24 },    -- Elixir of the Mongoose
	}

	local dailyCurves = { 0.96, 1.02, 0.99, 1.04, 0.98, 1.01 }
	local volCurves = { 0.85, 1.10, 0.95, 1.25, 0.90, 1.05 }

	for id, spec in pairs(priceMap) do
		db.ahPrices[ECON][id] = { price = spec.cur, qty = spec.qty, at = nowTs - 180 }

		-- 7d daily points (d = curDay-6 .. curDay)
		local daily = {}
		for dIdx = 1, 6 do
			local d = curDay - (7 - dIdx)
			daily[#daily + 1] = {
				d = d,
				lastP = math.floor(spec.base * dailyCurves[dIdx] + 0.5),
				lastQ = math.max(2, math.floor(spec.qty * volCurves[dIdx] + 0.5)),
				at = nowTs - (7 - dIdx) * DAY_SEC,
			}
		end
		daily[#daily + 1] = {
			d = curDay,
			lastP = spec.cur,
			lastQ = spec.qty,
			at = nowTs - 180,
		}
		db.ahDaily[ECON][id] = daily

		-- 24h snapshot points (every 3h -> 8 points) with supply volume
		local snap = {}
		local hourOffsets = { -21, -18, -15, -12, -9, -6, -3, 0 }
		for hIdx, hOff in ipairs(hourOffsets) do
			local ts = (hOff == 0) and (nowTs - 180) or (nowTs + hOff * 3600)
			local p = (hOff == 0) and spec.cur or math.floor(spec.base * (0.94 + hIdx * 0.014) + 0.5)
			local q = (hOff == 0) and spec.qty or math.max(3, math.floor(spec.qty * (0.75 + (hIdx % 4) * 0.18) + 0.5))
			snap[#snap + 1] = ts
			snap[#snap + 1] = p
			snap[#snap + 1] = q
		end
		db.ahSnapshots[ECON][id] = snap
	end

	-- Deterministic price bank override matching db.ahPrices[ECON]
	local priceBank = {}
	for id, spec in pairs(priceMap) do
		priceBank[id] = { price = spec.cur, source = "AH Scan" }
	end
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	return priceBank, priceMap
end

local savedOrigGetMarket = ns.GetItemMarketPrice
local savedOrigGetReagent = ns.GetReagentUnitCost
local savedOrigGetListed = ns.GetNumListed
local savedOrigEvalRecipe = ns.EvaluateRecipe

local function installMarketHooks(priceMap)
	ns.GetItemMarketPrice = function(itemID)
		local rec = priceMap[itemID]
		if rec then return rec.cur, "AH Scan" end
		return nil, nil
	end
	ns.GetReagentUnitCost = function(itemID)
		local rec = priceMap[itemID]
		if rec then return rec.cur, "AH Scan", false end
		return nil, nil, false
	end
	ns.GetNumListed = function(itemID)
		local rec = priceMap[itemID]
		if rec then return rec.qty end
		return 0
	end
	ns.EvaluateRecipe = nil
end

local function restoreMarketHooks()
	ns.GetItemMarketPrice = savedOrigGetMarket
	ns.GetReagentUnitCost = savedOrigGetReagent
	ns.GetNumListed = savedOrigGetListed
	ns.EvaluateRecipe = savedOrigEvalRecipe
end

---------------------------------------------------------------------------------------------------
-- 1. Ledger CRAFT Avg Craft Cost + Craft Cost Spike/Drop Headlines + Top Driver Reagent
---------------------------------------------------------------------------------------------------
do
	resetState(BASE_NOW)
	local priceBank, priceMap = seedCommonMarket(BASE_NOW, {
		thickCur = 600,     -- -25% below 800c avg buy
		wildvineCur = 51600, -- +100% spike -> drives Green Lens craft cost 15g -> ~19.84g (+32.3%)
		dreamfoilCur = 2600,
		silversageCur = 5200,
	})
	installMarketHooks(priceMap)

	-- Record 250 crafts of Green Lens (spellID=12622, itemID=10504) at 15g (150000c) avg craft cost
	for i = 1, 10 do
		Store.Append({
			time = BASE_NOW - i * 3600,
			type = "CRAFT",
			char = CHAR_MAIN,
			econ = ECON,
			itemID = 10504,
			qty = 25,
			unit = 150000,
			total = 0,
			cogs = 25 * 150000,
			extra = { spellID = 12622, name = "Green Lens" },
		})
	end

	-- Record 20 crafts of Greater Arcane Elixir (spellID=17573, itemID=13454) at high historical avg 50000c
	-- Live reagents (Dreamfoil x3=7800 + Mountain Silversage x1=5200 + Crystal Vial x1=500 = 13500c -> -73% drop!)
	Store.Append({
		time = BASE_NOW - 7200,
		type = "CRAFT",
		char = CHAR_MAIN,
		econ = ECON,
		itemID = 13454,
		qty = 20,
		unit = 50000,
		total = 0,
		cogs = 20 * 50000,
		extra = { spellID = 17573, name = "Greater Arcane Elixir" },
	})

	-- Record 400x AH_BUY Thick Leather (4304) at 800c avg buy
	for i = 1, 4 do
		Store.Append({
			time = BASE_NOW - (i + 2) * 3600,
			type = "AH_BUY",
			char = CHAR_MAIN,
			econ = ECON,
			itemID = 4304,
			qty = 100,
			unit = 800,
			total = -80000,
			extra = { name = "Thick Leather" },
		})
	end

	-- Record AH_SELL rows so profit & sales headlines populate too
	Store.Append({
		time = BASE_NOW - 1800,
		type = "AH_SELL",
		char = CHAR_MAIN,
		econ = ECON,
		itemID = 10504,
		qty = 3,
		unit = 265000,
		total = 755250,
		cogs = 450000,
		extra = { name = "Green Lens", gross = 795000, fee = 39750 },
	})

	local snap = BModel.BuildSnapshot(ECON, "7d", "all", nil, BASE_NOW, { priceBank = priceBank })
	check(type(snap) == "table", "BuildSnapshot returned table")

	local gl = snap.stocksByKey["recipe:12622"]
	check(gl ~= nil, "Green Lens recipe:12622 present in stock universe")
	check(gl.craftCount == 250, "Green Lens craftCount == 250 (got " .. tostring(gl.craftCount) .. ")")
	check(gl.ledgerAvgCraftCost == 150000, "Green Lens ledgerAvgCraftCost == 150000 (got " .. tostring(gl.ledgerAvgCraftCost) .. ")")
	-- Live craft cost: 8*600 + 3*8000 + 3*12000 + 2*16000 + 2*51600 = 4800 + 24000 + 36000 + 32000 + 103200 = 200000c
	check(gl.craftCost == 200000, "Green Lens live craftCost == 200000c (got " .. tostring(gl.craftCost) .. ")")
	check(gl.craftDeltaCopper == 50000, "Green Lens craftDeltaCopper == +50000c")
	check(gl.craftDeltaPct ~= nil and math.abs(gl.craftDeltaPct - 33.3333) < 0.2,
		"Green Lens craftDeltaPct approx +33.3% (got " .. tostring(gl.craftDeltaPct) .. ")")
	check(gl.topDriverName == "Wildvine", "Green Lens topDriverName is Wildvine (got " .. tostring(gl.topDriverName) .. ")")
	check(gl.topDriverPct ~= nil and gl.topDriverPct > 90, "Wildvine topDriverPct > +90% (got " .. tostring(gl.topDriverPct) .. ")")

	-- Check craft cost jump headline for Green Lens
	local glHeadline, gaeHeadline, thickDealHeadline = nil, nil, nil
	for _, h in ipairs(snap.headlines or {}) do
		if h.id == "cost:recipe:12622" then glHeadline = h end
		if h.id == "cost:recipe:17573" then gaeHeadline = h end
		if h.id == "deal_buy:item:4304" then thickDealHeadline = h end
	end
	check(glHeadline ~= nil, "Green Lens craft cost jump headline generated")
	check(glHeadline.category == "costs" and glHeadline.tone == "bad" and glHeadline.severity == "alert",
		"Green Lens cost spike headline categorized as costs/bad/alert")
	check(glHeadline.title:find("Green Lens", 1, true) ~= nil
		and glHeadline.title:find("up", 1, true) ~= nil
		and glHeadline.title:find("+33.3%", 1, true) ~= nil
		and glHeadline.title:find("250 crafts", 1, true) ~= nil,
		"Green Lens headline states name, up +33.3%, and 250 crafts (got: " .. tostring(glHeadline.title) .. ")")
	check(glHeadline.detail:find("Wildvine", 1, true) ~= nil,
		"Green Lens headline detail names top driver reagent Wildvine (got: " .. tostring(glHeadline.detail) .. ")")

	-- Check craft cost drop headline for Greater Arcane Elixir
	check(gaeHeadline ~= nil, "Greater Arcane Elixir craft cost drop headline generated")
	check(gaeHeadline.category == "costs" and gaeHeadline.tone == "good" and gaeHeadline.severity == "down",
		"Greater Arcane Elixir cost drop headline categorized as costs/good/down")
	check(gaeHeadline.title:find("down", 1, true) ~= nil,
		"Greater Arcane Elixir headline states 'down' (got: " .. tostring(gaeHeadline.title) .. ")")

	-- Check Thick Leather dip below avg buy headline
	check(thickDealHeadline ~= nil, "Thick Leather buy-zone dip headline generated")
	check(thickDealHeadline.category == "deals" and thickDealHeadline.tone == "good",
		"Thick Leather dip headline is deals/good")

	---------------------------------------------------------------------------------------------------
	-- 2. Top AH_BUY Reagent (Thick Leather) Vol vs Min Price Slide (7d + 24h) + refValue/refLabel
	---------------------------------------------------------------------------------------------------
	check(#snap.slides == 4, "Broadcast Stage emits exactly 4 slides")
	local sVol = snap.slides[1]
	check(sVol.id == "vol_price" and sVol.kind == "vol_price", "Slide 1 is vol_price")
	check(sVol.itemID == 4304, "Slide 1 selects top AH_BUY reagent Thick Leather (4304), got " .. tostring(sVol.itemID))
	check(sVol.title:find("Thick Leather", 1, true) ~= nil, "Slide 1 title names Thick Leather")
	check(sVol.hasVolume == true, "Slide 1 hasVolume == true")
	check(#sVol.points == 7, "Slide 1 has 7 daily points in 7d range (got " .. tostring(#sVol.points) .. ")")
	local seenDates = {}
	for idx = 1, #sVol.points do
		local pt = sVol.points[idx]
		check((pt.value or 0) > 0 and (pt.volume or 0) > 0,
			"7d vol_price point " .. idx .. " has positive price and volume")
		check(pt.label and not seenDates[pt.label],
			"7d vol_price point " .. idx .. " has unique day label: " .. tostring(pt.label))
		seenDates[pt.label or idx] = true
		check(pt.open and pt.high and pt.low and pt.close
			and pt.low <= math.min(pt.open, pt.close)
			and math.max(pt.open, pt.close) <= pt.high,
			"7d vol_price point " .. idx .. " has valid OHLC bounds")
	end
	local tlStock = snap.stocksByKey["item:4304"]
	check(tlStock and type(tlStock.points) == "table" and #tlStock.points == 7
		and tlStock.points[1].open and tlStock.points[1].high and tlStock.points[1].low and tlStock.points[1].close,
		"Stock item:4304 series includes 7d OHLC fields")
	do
		-- Simulate late-UTC daily buckets (23:55 UTC) across 7 consecutive days: no duplicate MM-DD labels
		local lateDayBase = math.floor(BASE_NOW / 86400)
		local origDaily = _G.MerchantMasterDB.ahDaily[ECON][4304]
		local lateRows = {}
		for i = 1, 7 do
			local d = lateDayBase - (7 - i)
			lateRows[i] = {
				d = d,
				openP = 700 + i * 10,
				minP = 680 + i * 10,
				maxP = 760 + i * 10,
				lastP = 720 + i * 10,
				lastQ = 30 + i,
				at = d * 86400 + 86100,
			}
		end
		_G.MerchantMasterDB.ahDaily[ECON][4304] = lateRows
		BModel.InvalidateCache()
		local lateSnap = BModel.BuildSnapshot(ECON, "7d", "all", nil, BASE_NOW, { priceBank = priceBank })
		local lateSeen, lateUnique = {}, 0
		for _, pt in ipairs(lateSnap.slides[1].points or {}) do
			if pt.label and not lateSeen[pt.label] then
				lateSeen[pt.label] = true
				lateUnique = lateUnique + 1
			end
		end
		check(lateUnique == 7, "7d late-UTC daily timestamps still yield 7 unique day labels (got " .. tostring(lateUnique) .. ")")
		_G.MerchantMasterDB.ahDaily[ECON][4304] = origDaily
		BModel.InvalidateCache()
	end
	check(sVol.refValue == 800, "Slide 1 refValue == 800 (Your Avg Buy), got " .. tostring(sVol.refValue))
	check(sVol.refLabel == "Your Avg Buy", "Slide 1 refLabel == 'Your Avg Buy', got " .. tostring(sVol.refLabel))

	-- 24h range: uses ahSnapshots hourly points with volume
	local snap24 = BModel.BuildSnapshot(ECON, "24h", "all", nil, BASE_NOW, { priceBank = priceBank })
	local sVol24 = snap24.slides[1]
	check(sVol24.id == "vol_price" and sVol24.itemID == 4304, "24h Slide 1 selects Thick Leather")
	check(sVol24.hasVolume == true and #sVol24.points >= 6,
		"24h vol_price populates hourly snapshot points with volume (got " .. tostring(#sVol24.points) .. ")")

	-- Fallback refLabel ("7d Avg") when item has no AH_BUY ledger average
	WL.Add({ kind = "item", itemID = 13512, name = "Flask of Supreme Power" })
	local snapPinnedFlask = BModel.BuildSnapshot(ECON, "7d", "all", "item:13512", BASE_NOW, {
		priceBank = priceBank,
		pinnedKey = "item:13512",
	})
	check(snapPinnedFlask.slides[1].itemID == 13512 and snapPinnedFlask.slides[1].pinned == true,
		"Pinned non-bought item drives Slide 1")
	check(snapPinnedFlask.slides[1].refLabel == "7d Avg",
		"Unbought item falls back to refLabel == '7d Avg' (got " .. tostring(snapPinnedFlask.slides[1].refLabel) .. ")")
	check(snapPinnedFlask.slides[1].refValue ~= nil and snapPinnedFlask.slides[1].refValue > 0,
		"Unbought item populates positive 7d Avg refValue")

	-- Also verify Slide 2 (wealth), Slide 3 (profit), Slide 4 (craft_spread)
	check(snap.slides[2].id == "wealth", "Slide 2 is wealth")
	check(snap.slides[3].id == "profit" and snap.slides[3].isBarChart == true, "Slide 3 is profit bar chart")
	check(snap.slides[4].id == "craft_spread" and snap.slides[4].spellID == 12622,
		"Slide 4 is craft_spread featuring top crafted recipe Green Lens (12622)")
	check(#snap.slides[4].points == 7 and snap.slides[4].points[7].value2 ~= nil and snap.slides[4].points[7].value2 > 0,
		"Slide 4 craft_spread emits dual series (sale price + craft cost)")

	---------------------------------------------------------------------------------------------------
	-- 3. Filters, Watchlist Star Toggle Sync, Spotlight Click, MOST ACTIVE Ordering, Pin/Unpin
	---------------------------------------------------------------------------------------------------
	-- Watchlist currently has item:13512 (Flask of Supreme Power)
	local snapAll = BModel.BuildSnapshot(ECON, "7d", "all", nil, BASE_NOW, { priceBank = priceBank })
	local snapWatch = BModel.BuildSnapshot(ECON, "7d", "watchlist", nil, BASE_NOW, { priceBank = priceBank })
	local snapCrafts = BModel.BuildSnapshot(ECON, "7d", "crafts", nil, BASE_NOW, { priceBank = priceBank })
	local snapMats = BModel.BuildSnapshot(ECON, "7d", "reagents", nil, BASE_NOW, { priceBank = priceBank })

	check(#snapAll.stocks >= 4, "filter=all includes watched + crafts + reagents (got " .. tostring(#snapAll.stocks) .. ")")
	check(#snapWatch.stocks == 1 and snapWatch.stocks[1].key == "item:13512",
		"filter=watchlist returns only watched items (got " .. tostring(#snapWatch.stocks) .. ")")
	check(#snapCrafts.stocks >= 2, "filter=crafts returns crafted recipes (got " .. tostring(#snapCrafts.stocks) .. ")")
	for _, st in ipairs(snapCrafts.stocks) do
		check(st.kind == "recipe" or (st.craftCount or 0) > 0, "filter=crafts entry is a craft: " .. tostring(st.key))
	end
	check(#snapMats.stocks >= 1, "filter=reagents returns bought reagents (got " .. tostring(#snapMats.stocks) .. ")")
	for _, st in ipairs(snapMats.stocks) do
		check(st.kind == "item" and (st.buyCount or 0) >= (st.craftCount or 0),
			"filter=reagents entry is a reagent item: " .. tostring(st.key))
	end

	-- MOST ACTIVE ordering: strictly descending by activityScore (Thick Leather 400 > Green Lens 253 > GAE 20)
	check(#snapAll.mostActive >= 3, "mostActive has at least 3 stocks")
	check(snapAll.mostActive[1].key == "item:4304" and snapAll.mostActive[1].activityScore == 400,
		"MOST ACTIVE #1 is Thick Leather (400 activity)")
	check(snapAll.mostActive[2].key == "recipe:12622" and snapAll.mostActive[2].activityScore == 253,
		"MOST ACTIVE #2 is Green Lens (250 crafts + 3 sales = 253 activity)")
	for i = 2, #snapAll.mostActive do
		check((snapAll.mostActive[i - 1].activityScore or 0) >= (snapAll.mostActive[i].activityScore or 0),
			"mostActive sorted descending at index " .. i)
	end

	-- Create real UI view and test interactive Watchlist star toggle, Spotlight update, Pin/Unpin
	local host = CreateFrame("Frame", "MMTestBloombergHost", UIParent)
	host:SetSize(1600, 642)
	local view = BUI.Create(host, {
		getEconKey = function() return ECON end,
		getPriceBank = function() return priceBank end,
		getPlayerName = function() return "Thrall Ironfist" end,
	})
	view:Layout(1600, 642)
	view:Refresh(true, BASE_NOW)

	-- Locate Spotlight star button (icon_star), Pin button, and Stage Unpin button
	local starBtns = findButtonsIn(view.spotlightPanel, function(b)
		return b.icon and b.icon.GetTexture and tostring(b.icon:GetTexture() or ""):find("icon_star", 1, true) ~= nil
	end)
	local starBtn = starBtns[1]
	check(starBtn ~= nil, "Spotlight exposes icon_star Watchlist toggle button")

	local pinBtn = findButtonByLabel(view.spotlightPanel, "Pin")
	check(pinBtn ~= nil, "Spotlight exposes Pin button")

	local unpinBtn = findButtonByLabel(view.stagePanel, "Unpin")
	check(unpinBtn ~= nil, "Broadcast Stage exposes Unpin button")
	check(not unpinBtn:IsShown(), "Unpin button hidden when nothing is pinned")

	-- Click a rail tile for Green Lens (recipe:12622) -> Spotlight updates to Green Lens
	local railTiles = findButtonsIn(view.railPanel, function(b) return b._stock ~= nil end)
	check(#railTiles >= 3, "Right rail renders clickable stock tiles")
	local glTile = nil
	for _, t in ipairs(railTiles) do
		if t._stock and t._stock.key == "recipe:12622" then glTile = t; break end
	end
	check(glTile ~= nil, "Green Lens tile rendered on Stocks rail")
	glTile:Click("LeftButton")
	check(view:GetState().selectedKey == "recipe:12622", "Clicking rail tile selects recipe:12622 in Spotlight")
	check(view:GetState().selectedStock and view:GetState().selectedStock.name == "Green Lens",
		"Spotlight selectedStock updated to Green Lens")

	-- Toggle Watchlist Star button in Spotlight ON -> syncs into ns.Watchlist
	check(not WL.IsFavorite("recipe:12622"), "Green Lens not initially in Watchlist")
	starBtn:Click("LeftButton")
	check(WL.IsFavorite("recipe:12622") == true, "Clicking Spotlight icon_star adds Green Lens to ns.Watchlist")
	check(view:GetState().selectedStock and view:GetState().selectedStock.isWatched == true,
		"Spotlight stock reflects isWatched == true after star click")

	-- Toggle Watchlist Star button OFF -> removes from ns.Watchlist
	starBtn:Click("LeftButton")
	check(WL.IsFavorite("recipe:12622") == false, "Second icon_star click removes Green Lens from ns.Watchlist")
	check(view:GetState().selectedStock and view:GetState().selectedStock.isWatched == false,
		"Spotlight stock reflects isWatched == false after unstar")

	-- External Watchlist.Add / Watchlist.Remove sync via registered listener
	WL.Add({ kind = "recipe", spellID = 12622, itemID = 10504, name = "Green Lens" })
	check(view:GetState().selectedStock and view:GetState().selectedStock.isWatched == true,
		"External Watchlist.Add syncs Spotlight watched state automatically")
	WL.Remove("recipe:12622")
	check(view:GetState().selectedStock and view:GetState().selectedStock.isWatched == false,
		"External Watchlist.Remove syncs Spotlight watched state automatically")

	-- Pin Green Lens via Spotlight Pin button -> Stage pins craft_spread as slide 1 and shows Unpin
	pinBtn:Click("LeftButton")
	check(view:GetState().pinnedKey == "recipe:12622", "Pin button sets pinnedKey == recipe:12622")
	check(view:GetState().slideIndex == 1, "Pin resets Broadcast Stage to slide 1")
	check(view:GetState().activeSlide and view:GetState().activeSlide.stockKey == "recipe:12622"
		and view:GetState().activeSlide.pinned == true,
		"Broadcast Stage slide 1 displays pinned Green Lens")
	check(pinBtn.label:GetText() == "Pinned", "Pin button text updates to 'Pinned'")
	check(unpinBtn:IsShown(), "Stage Unpin button shown while stock is pinned")

	-- Unpin via Stage Unpin button -> clears pin and hides Unpin
	unpinBtn:Click("LeftButton")
	check(view:GetState().pinnedKey == nil, "Unpin button clears pinnedKey")
	check(not unpinBtn:IsShown(), "Stage Unpin button hides after unpin")
	check(pinBtn.label:GetText() == "Pin", "Spotlight Pin button restores text 'Pin'")

	-- Test Rail filter buttons ("Favs", "Crafts", "Mats", "All")
	local btnFavs = findButtonByLabel(view.railPanel, "Favs")
	local btnCrafts = findButtonByLabel(view.railPanel, "Crafts")
	local btnMats = findButtonByLabel(view.railPanel, "Mats")
	local btnAll = findButtonByLabel(view.railPanel, "All")
	check(btnFavs and btnCrafts and btnMats and btnAll, "All 4 rail filter buttons exist")
	btnFavs:Click("LeftButton")
	check(view:GetState().filterKey == "watchlist" and #view:GetState().snap.stocks == 1,
		"Clicking Favs filters rail to watchlist")
	btnCrafts:Click("LeftButton")
	check(view:GetState().filterKey == "crafts" and #view:GetState().snap.stocks >= 2,
		"Clicking Crafts filters rail to crafted recipes")
	btnMats:Click("LeftButton")
	check(view:GetState().filterKey == "reagents" and #view:GetState().snap.stocks >= 1,
		"Clicking Mats filters rail to reagents")
	btnAll:Click("LeftButton")
	check(view:GetState().filterKey == "all" and #view:GetState().snap.stocks >= 4,
		"Clicking All restores full stock rail")

	---------------------------------------------------------------------------------------------------
	-- 4. Broadcast Stage 4-Slide Navigation, Auto-Rotate Tick Rules & Zero app.refresh() Calls
	---------------------------------------------------------------------------------------------------
	local app = ns.app
	local origAppRefresh = app and app.refresh
	local appRefreshCalls = 0
	if app then
		app.refresh = function(...)
			appRefreshCalls = appRefreshCalls + 1
			if origAppRefresh then return origAppRefresh(...) end
		end
	end

	-- Confirm zero OnUpdate scripts on view and all descendant frames
	local onUpdateCount = 0
	for i = 1, #createdFrames do
		local f = createdFrames[i]
		if f and isDescendantOf(f, view) and f:GetScript("OnUpdate") ~= nil then
			onUpdateCount = onUpdateCount + 1
		end
	end
	check(onUpdateCount == 0, "Bloomberg view has zero OnUpdate scripts (got " .. tostring(onUpdateCount) .. ")")

	-- 4-slide wraparound NextSlide / PrevSlide
	check(view:GetState().slideIndex == 1, "Starts on slide 1")
	check(view:NextSlide(true) == 2 and view:GetState().slideIndex == 2, "NextSlide 1 -> 2")
	check(view:NextSlide(true) == 3 and view:GetState().slideIndex == 3, "NextSlide 2 -> 3")
	check(view:NextSlide(true) == 4 and view:GetState().slideIndex == 4, "NextSlide 3 -> 4")
	check(view:NextSlide(true) == 1 and view:GetState().slideIndex == 1, "NextSlide wraps 4 -> 1")
	check(view:PrevSlide(true) == 4 and view:GetState().slideIndex == 4, "PrevSlide wraps 1 -> 4")
	check(view:PrevSlide(true) == 3 and view:GetState().slideIndex == 3, "PrevSlide 4 -> 3")
	view:NextSlide(true)
	view:NextSlide(true) -- back to 1
	check(view:GetState().slideIndex == 1, "Returned to slide 1")

	-- OnAutoTick: advances when visible + unhovered + autoRotate=true
	view:Show()
	check(view:GetState().autoRotate == true and view:GetState().stageHovered == false,
		"autoRotate enabled and stage unhovered")
	check(view:OnAutoTick() == true and view:GetState().slideIndex == 2,
		"OnAutoTick advances slide 1 -> 2 when visible and unhovered")

	-- OnAutoTick pauses when hovered
	view.stageCanvas:GetScript("OnEnter")(view.stageCanvas)
	check(view:GetState().stageHovered == true, "stageCanvas OnEnter sets stageHovered = true")
	check(view:OnAutoTick() == false and view:GetState().slideIndex == 2,
		"OnAutoTick pauses while stageCanvas is hovered")
	view.stageCanvas:GetScript("OnLeave")(view.stageCanvas)
	check(view:GetState().stageHovered == false, "stageCanvas OnLeave clears stageHovered")
	check(view:OnAutoTick() == true and view:GetState().slideIndex == 3,
		"OnAutoTick resumes after mouse leaves stageCanvas (2 -> 3)")

	-- OnAutoTick pauses when hidden
	view:Hide()
	check(view:OnAutoTick() == false and view:GetState().slideIndex == 3,
		"OnAutoTick pauses while view is hidden")
	view:Show()
	check(view:OnAutoTick() == true and view:GetState().slideIndex == 4,
		"OnAutoTick resumes when view is shown again (3 -> 4)")

	-- ToggleAutoRotate disables and re-enables OnAutoTick
	check(view:ToggleAutoRotate() == false and view:GetState().autoRotate == false,
		"ToggleAutoRotate switches autoRotate OFF")
	check(view:OnAutoTick() == false and view:GetState().slideIndex == 4,
		"OnAutoTick does not advance when autoRotate is OFF")
	check(view:ToggleAutoRotate() == true and view:GetState().autoRotate == true,
		"ToggleAutoRotate switches autoRotate back ON")
	check(view:OnAutoTick() == true and view:GetState().slideIndex == 1,
		"OnAutoTick advances 4 -> 1 after autoRotate re-enabled")

	-- CRITICAL: Stage rotation/navigation NEVER calls app.refresh()
	check(appRefreshCalls == 0,
		"NextSlide/PrevSlide/ToggleAutoRotate/OnAutoTick NEVER call app.refresh() (got " .. tostring(appRefreshCalls) .. ")")

	if app then app.refresh = origAppRefresh end

	---------------------------------------------------------------------------------------------------
	-- 4b. Regression Check: Every Rendered Line Segment Uses 4-Arg SetStartPoint/SetEndPoint In Bounds
	---------------------------------------------------------------------------------------------------
	do
		view:Layout(1600, 642)
		view:Refresh(false, BASE_NOW)
		local function verifyPanelLines(panelFrame, label)
			local checked = 0
			for i = 1, #createdFrames do
				local f = createdFrames[i]
				if f and isDescendantOf(f, panelFrame) and type(f._regions) == "table" then
					for _, r in ipairs(f._regions) do
						if r and r._isLine == true and r:IsShown() then
							checked = checked + 1
							local sp = r._startPoint
							local ep = r._endPoint
							check(type(sp) == "table" and #sp == 4,
								label .. " line #" .. checked .. " SetStartPoint has exact 4 args (got " .. tostring(sp and #sp) .. ")")
							check(type(ep) == "table" and #ep == 4,
								label .. " line #" .. checked .. " SetEndPoint has exact 4 args (got " .. tostring(ep and #ep) .. ")")
							check(type(sp[1]) == "string" and type(sp[2]) == "table"
								and type(sp[3]) == "number" and type(sp[4]) == "number",
								label .. " line #" .. checked .. " SetStartPoint(pt, relTo, numX, numY) valid")
							check(type(ep[1]) == "string" and type(ep[2]) == "table"
								and type(ep[3]) == "number" and type(ep[4]) == "number",
								label .. " line #" .. checked .. " SetEndPoint(pt, relTo, numX, numY) valid")
							local rel = sp[2]
							local pw = (rel.GetWidth and rel:GetWidth()) or 0
							local ph = (rel.GetHeight and rel:GetHeight()) or 0
							-- Two-point anchored sub-frames (e.g. tile.spark) inherit width from their parent tile in host_fixture
							local relParent = rel.GetParent and rel:GetParent()
							if relParent and relParent.GetWidth then
								pw = math.max(pw, (relParent:GetWidth() or 0))
							end
							check(pw > 0 and ph > 0, label .. " line #" .. checked .. " parent has positive bounds")
							check(sp[3] >= -2 and sp[3] <= pw + 2 and sp[4] >= -2 and sp[4] <= ph + 2,
								string.format("%s line #%d start (%s,%s) inside parent (%sx%s)",
									label, checked, tostring(sp[3]), tostring(sp[4]), tostring(pw), tostring(ph)))
							check(ep[3] >= -2 and ep[3] <= pw + 2 and ep[4] >= -2 and ep[4] <= ph + 2,
								string.format("%s line #%d end (%s,%s) inside parent (%sx%s)",
									label, checked, tostring(ep[3]), tostring(ep[4]), tostring(pw), tostring(ph)))
						end
					end
				end
			end
			return checked
		end

		view:SetChartStyle("candles")
		view:Refresh(false, BASE_NOW)
		local stageCandleLines = verifyPanelLines(view.stagePanel, "StageCandles")
		local spotCandleLines = verifyPanelLines(view.spotlightPanel, "SpotlightCandles")
		check(stageCandleLines >= 5, "Stage Candles mode rendered >= 5 verified 4-arg line segments (got " .. tostring(stageCandleLines) .. ")")
		check(spotCandleLines >= 5, "Spotlight Candles mode rendered >= 5 verified 4-arg line segments (got " .. tostring(spotCandleLines) .. ")")
		check(view.spotlightPanel and tostring(view.GetState and view:GetState().chartStyle) == "candles", "Chart style defaults/sets cleanly to candles")

		view:SetChartStyle("line")
		view:Refresh(false, BASE_NOW)
		local stageLines = verifyPanelLines(view.stagePanel, "StageLine")
		local spotLines = verifyPanelLines(view.spotlightPanel, "SpotlightLine")
		local railLines = verifyPanelLines(view.railPanel, "Rail")
		check(stageLines >= 5, "Stage Line mode rendered >= 5 verified 4-arg line segments (got " .. tostring(stageLines) .. ")")
		check(spotLines >= 5, "Spotlight Line mode rendered >= 5 verified 4-arg line segments (got " .. tostring(spotLines) .. ")")
		check(railLines >= 5, "Right Rail rendered >= 5 verified 4-arg line segments (got " .. tostring(railLines) .. ")")
		view:SetChartStyle("candles")
		view:Refresh(false, BASE_NOW)
	end

	---------------------------------------------------------------------------------------------------
	-- 6. Geometry Non-Overlap Across 1036x612, 1600x642, and 2252x1298
	---------------------------------------------------------------------------------------------------
	local viewports = {
		{ w = 1036, h = 612,  label = "1036x612" },
		{ w = 1600, h = 642,  label = "1600x642" },
		{ w = 2252, h = 1298, label = "2252x1298" },
	}
	local panelKeys = {
		"banner", "stagePanel", "newsPanel",
		"spotlightPanel", "activePanel", "timingPanel", "railPanel",
	}
	local bannerSubKeys = { "bloomBadge", "greeting", "metaPill", "rangeSeg", "modeSeg" }

	for _, vp in ipairs(viewports) do
		view:Layout(vp.w, vp.h)
		local g = view._geometry
		check(type(g) == "table", vp.label .. " exposes view._geometry")
		check(g.W == vp.w and g.H == vp.h, vp.label .. " records exact viewport W/H")
		check(g.col1W + g.col2W + g.col3W + 2 * g.gap == vp.w,
			vp.label .. " 3 columns + gaps equal exact viewport width")
		check(g.timH >= 68, vp.label .. " timingPanel height >= 68 (got " .. tostring(g.timH) .. ")")

		-- All 7 panels fit inside [0, W] x [0, H]
		for _, pk in ipairs(panelKeys) do
			local r = g[pk]
			check(type(r) == "table" and r.w > 0 and r.h > 0, vp.label .. " " .. pk .. " has positive size")
			check(r.x >= 0 and r.y >= 0 and (r.x + r.w) <= vp.w + 0.5 and (r.y + r.h) <= vp.h + 0.5,
				string.format("%s %s fits viewport (x=%s y=%s w=%s h=%s vs %dx%d)",
					vp.label, pk, tostring(r.x), tostring(r.y), tostring(r.w), tostring(r.h), vp.w, vp.h))
		end

		-- Pairwise non-overlap between all 7 top-level panels
		for i = 1, #panelKeys do
			for j = i + 1, #panelKeys do
				local kA, kB = panelKeys[i], panelKeys[j]
				check(not rectsOverlap(g[kA], g[kB]),
					vp.label .. " " .. kA .. " does not overlap " .. kB)
			end
		end

		-- Pairwise non-overlap between banner sub-elements
		for i = 1, #bannerSubKeys do
			local r = g[bannerSubKeys[i]]
			check(type(r) == "table" and r.w > 0 and r.h > 0, vp.label .. " banner." .. bannerSubKeys[i] .. " valid")
			check(r.x >= 0 and (r.x + r.w) <= vp.w + 0.5, vp.label .. " banner." .. bannerSubKeys[i] .. " within width")
			for j = i + 1, #bannerSubKeys do
				check(not rectsOverlap(g[bannerSubKeys[i]], g[bannerSubKeys[j]]),
					vp.label .. " banner " .. bannerSubKeys[i] .. " does not overlap " .. bannerSubKeys[j])
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- 7. Clean Repaint Across Modern Glass Dark, Modern Glass Light, Goblin Baron & All 4 Warcraft Skins
	---------------------------------------------------------------------------------------------------
	if Theme and Theme.SetSkin and Theme.SetMode then
		local prevSkin = Theme.GetSkin and Theme.GetSkin() or "standard"
		local prevMode = Theme.GetMode and Theme.GetMode() or "dark"

		Theme.SetSkin("standard", false)
		Theme.SetMode("dark", false)
		view:ApplyTheme()
		view:Refresh(false, BASE_NOW)
		check(Theme.GetSkin() == "standard" and Theme.GetMode() == "dark", "Repainted Modern Glass Dark")

		Theme.SetMode("light", false)
		view:ApplyTheme()
		view:Refresh(false, BASE_NOW)
		check(Theme.GetSkin() == "standard" and Theme.GetMode() == "light", "Repainted Modern Glass Light")

		Theme.SetMode("dark", false)
		local skins = { "goblin", "human", "night_elf", "orc", "undead" }
		for _, sk in ipairs(skins) do
			Theme.SetSkin(sk, false)
			view:ApplyTheme()
			view:Refresh(false, BASE_NOW)
			check(Theme.GetSkin() == sk, "Repainted Warcraft skin: " .. sk)
		end

		Theme.SetSkin(prevSkin, false)
		Theme.SetMode(prevMode, false)
		view:ApplyTheme()
	end

	restoreMarketHooks()
end

---------------------------------------------------------------------------------------------------
-- 5. 3-Way modeSeg Pixel Symmetry & Full Round-Trip (bloomberg -> brief -> classic -> bloomberg)
---------------------------------------------------------------------------------------------------
do
	local app = ns.app
	local ui = app and app.ui
	check(type(app) == "table" and type(ui) == "table", "ns.app and app.ui loaded for modeSeg checks")

	local prevMode = _G.MerchantMasterDB and _G.MerchantMasterDB.dashboardMode
	app.panel:Show()
	app.setTab("dashboard")

	-- Ensure all three views exist
	app.setDashboardMode("bloomberg")
	local bloomView = app.ensureDashboardBloomberg()
	local briefView = app.ensureDashboardBrief()
	local classicSeg = ui.dashClassicModeSeg

	check(bloomView ~= nil, "app.ensureDashboardBloomberg returns bloomView")
	check(briefView ~= nil, "app.ensureDashboardBrief returns briefView")
	check(classicSeg ~= nil, "ui.dashClassicModeSeg exists")

	local segSpecs = {
		{ name = "dashBloombergView", seg = bloomView.modeSeg, banner = bloomView.banner },
		{ name = "dashBriefView",     seg = briefView.modeSeg, banner = briefView.banner },
		{ name = "dashClassicModeSeg", seg = classicSeg,       banner = ui.dashClassicBanner },
	}

	local function lblTxtOf(widget)
		if not widget then return nil end
		if widget._label and widget._label.GetText then return widget._label:GetText() end
		if widget.label and widget.label.GetText then return widget.label:GetText() end
		if widget.fs and widget.fs.GetText then return widget.fs:GetText() end
		if widget.GetText then return widget:GetText() end
		return nil
	end
	check(lblTxtOf(bloomView.bloomBadge) == "GOBLINTV",
		"GoblinTV badge pill renders visible 'GOBLINTV', got " .. tostring(lblTxtOf(bloomView.bloomBadge)))
	for _, spec in ipairs(segSpecs) do
		local seg = spec.seg
		check(seg ~= nil and seg.frame ~= nil and seg.buttons ~= nil, spec.name .. " has modeSeg frame and buttons")
		check(seg.buttons.bloomberg ~= nil and seg.buttons.brief ~= nil and seg.buttons.classic ~= nil,
			spec.name .. " exposes bloomberg, brief, and classic buttons")
		check(lblTxtOf(seg.buttons.bloomberg) == "GoblinTV",
			spec.name .. " bloomberg button visible text is GoblinTV, got " .. tostring(lblTxtOf(seg.buttons.bloomberg)))
		check(seg.buttons.bloomberg:GetWidth() == 88, spec.name .. " bloomberg button width == 88")
		check(seg.buttons.brief:GetWidth() == 102, spec.name .. " brief button width == 102")
		check(seg.buttons.classic:GetWidth() == 96, spec.name .. " classic button width == 96")
		local btnSum = seg.buttons.bloomberg:GetWidth() + seg.buttons.brief:GetWidth() + seg.buttons.classic:GetWidth()
		check(btnSum == 286, spec.name .. " modeSeg button widths sum == 286 (got " .. tostring(btnSum) .. ")")
		check(seg.frame:GetWidth() >= 286 and seg.frame:GetWidth() == 298,
			spec.name .. " modeSeg total frame width == 298 (286 buttons + pill track padding, got " .. tostring(seg.frame:GetWidth()) .. ")")
		check(seg.frame:GetHeight() == 26,
			spec.name .. " modeSeg height == 26 (got " .. tostring(seg.frame:GetHeight()) .. ")")
		local pt = seg.frame._points and seg.frame._points[#seg.frame._points]
		check(pt and pt[1] == "RIGHT" and pt[2] == spec.banner and pt[3] == "RIGHT" and pt[4] == -2 and pt[5] == 0,
			spec.name .. " modeSeg anchored RIGHT, banner, RIGHT, -2, 0")
	end

	-- Exact cross-view dimensional equality
	check(bloomView.modeSeg.frame:GetWidth() == briefView.modeSeg.frame:GetWidth()
		and briefView.modeSeg.frame:GetWidth() == classicSeg.frame:GetWidth(),
		"All 3 dashboard modeSeg switchers have identical width (286)")
	check(bloomView.modeSeg.frame:GetHeight() == briefView.modeSeg.frame:GetHeight()
		and briefView.modeSeg.frame:GetHeight() == classicSeg.frame:GetHeight(),
		"All 3 dashboard modeSeg switchers have identical height (26)")

	-- Full round-trip: bloomberg -> brief -> classic -> bloomberg
	app.setDashboardMode("bloomberg")
	check(_G.MerchantMasterDB.dashboardMode == "bloomberg", "Initial DB mode is bloomberg")
	check(bloomView:IsShown() and not briefView:IsShown() and not ui.dashClassicWrap:IsShown(),
		"bloomberg mode shows bloomView and hides briefView + dashClassicWrap")
	local bThumb = bloomView.modeSeg.thumb and bloomView.modeSeg.thumb._points and bloomView.modeSeg.thumb._points[1]
	check(bThumb and bThumb[2] == bloomView.modeSeg.buttons.bloomberg,
		"bloomView modeSeg highlights bloomberg segment")

	-- bloomberg -> brief
	bloomView.modeSeg.buttons.brief:GetScript("OnClick")(bloomView.modeSeg.buttons.brief, "LeftButton")
	check(_G.MerchantMasterDB.dashboardMode == "brief", "Clicking Morning Brief switches DB mode to brief")
	check(not bloomView:IsShown() and briefView:IsShown() and not ui.dashClassicWrap:IsShown(),
		"brief mode shows briefView and hides bloomView + dashClassicWrap")
	local brThumb = briefView.modeSeg.thumb and briefView.modeSeg.thumb._points and briefView.modeSeg.thumb._points[1]
	check(brThumb and brThumb[2] == briefView.modeSeg.buttons.brief,
		"briefView modeSeg highlights brief segment")

	-- brief -> classic
	briefView.modeSeg.buttons.classic:GetScript("OnClick")(briefView.modeSeg.buttons.classic, "LeftButton")
	check(_G.MerchantMasterDB.dashboardMode == "classic", "Clicking Market Pulse switches DB mode to classic")
	check(not bloomView:IsShown() and not briefView:IsShown() and ui.dashClassicWrap:IsShown(),
		"classic mode shows dashClassicWrap and hides bloomView + briefView")
	local cThumb = classicSeg.thumb and classicSeg.thumb._points and classicSeg.thumb._points[1]
	check(cThumb and cThumb[2] == classicSeg.buttons.classic,
		"dashClassicModeSeg highlights classic segment")

	-- classic -> bloomberg
	classicSeg.buttons.bloomberg:GetScript("OnClick")(classicSeg.buttons.bloomberg, "LeftButton")
	check(_G.MerchantMasterDB.dashboardMode == "bloomberg", "Clicking Bloomberg switches DB mode back to bloomberg")
	check(bloomView:IsShown() and not briefView:IsShown() and not ui.dashClassicWrap:IsShown(),
		"bloomberg mode restored after full 3-way round-trip")
	local bThumb2 = bloomView.modeSeg.thumb and bloomView.modeSeg.thumb._points and bloomView.modeSeg.thumb._points[1]
	check(bThumb2 and bThumb2[2] == bloomView.modeSeg.buttons.bloomberg,
		"bloomView modeSeg highlights bloomberg segment after round-trip")

	if _G.MerchantMasterDB then _G.MerchantMasterDB.dashboardMode = prevMode end
	app.syncDashboardMode()
end

print("PASS dashboard_bloomberg: " .. tostring(hostEnv.assertions()) .. " assertions, 0 failures")
