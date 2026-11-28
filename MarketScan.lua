-- Market browse, bag pricing and order-book scanning share one event owner.
local ADDON, ns = ...
local MarketScan = {}
ns.MarketScan = MarketScan

local function readable(value)
	return not (issecretvalue and issecretvalue(value))
		and not (type(value) == "table" and issecrettable and issecrettable(value))
end
local function safeNumber(value, signed)
	return readable(value) and type(value) == "number" and value == value and value < math.huge
		and value > -math.huge and (signed or value >= 0) and value or nil
end
local function tableValue(value)
	if readable(value) and type(value) == "table" then return value end
end

-- Shared Auction House Channel Lease (MarketScan, CartBuyer, SniperEngine)
do
	local activeOwner = nil
	local activeKind = nil
	local activeSince = 0
	local preemptBrowseFn = nil

	local function channelNow()
		if type(GetTime) == "function" then
			local ok, t = pcall(GetTime)
			if ok and safeNumber(t) then return t end
		end
		return 0
	end

	local AHChannel = {}

	function AHChannel._SetBrowsePreemptor(fn)
		preemptBrowseFn = (type(fn) == "function") and fn or nil
	end

	function AHChannel.GetOwner()
		return activeOwner
	end

	function AHChannel.GetKind()
		return activeKind
	end

	function AHChannel.GetAcquiredAt()
		return activeSince
	end

	function AHChannel.IsBusy(exceptOwner)
		if activeOwner == nil then return false end
		if exceptOwner ~= nil and activeOwner == exceptOwner then return false end
		return true
	end

	function AHChannel.TryAcquire(owner, kindOrOpts)
		if not readable(owner) or type(owner) ~= "string" or owner == "" then
			return false, "invalid_owner"
		end
		local kind = nil
		local preemptScan = false
		if type(kindOrOpts) == "table" then
			if readable(kindOrOpts.kind) and type(kindOrOpts.kind) == "string" then
				kind = kindOrOpts.kind
			end
			preemptScan = (kindOrOpts.preemptScan == true)
		elseif readable(kindOrOpts) and type(kindOrOpts) == "string" then
			kind = kindOrOpts
		end

		if activeOwner ~= nil and activeOwner ~= owner then
			if activeOwner == "market_scan" and (preemptScan or owner ~= "market_scan") then
				activeOwner = nil
				activeKind = nil
				activeSince = 0
				if preemptBrowseFn then
					pcall(preemptBrowseFn)
				end
			else
				return false, "busy:" .. tostring(activeOwner)
			end
		elseif preemptScan and owner ~= "market_scan" and preemptBrowseFn then
			pcall(preemptBrowseFn)
		end

		activeOwner = owner
		activeKind = kind or activeKind or "default"
		activeSince = channelNow()
		return true, nil
	end

	function AHChannel.Release(owner)
		if owner == nil or activeOwner == owner then
			activeOwner = nil
			activeKind = nil
			activeSince = 0
			return true
		end
		return false
	end

	function AHChannel.Reset()
		activeOwner = nil
		activeKind = nil
		activeSince = 0
	end

	ns.AHChannel = AHChannel
end

local function lastPositiveQuote(value)
	local previous = tableValue(value)
	if not previous then return end
	local price = safeNumber(previous.price)
	if price and price > 0 then return price, safeNumber(previous.at) end
	price = safeNumber(previous.lastPrice)
	if price and price > 0 then return price, safeNumber(previous.lastAt) end
end

local function recordVelocity(point, dt, oldPrice, newPrice, oldQty, newQty)
	if dt < 60 or dt > 43200 then return end
	local weight = newPrice > oldPrice and 1 or (newPrice == oldPrice and 0.55 or 0.20)
	point.scanUnits = (safeNumber(point.scanUnits) or 0) + math.max(0, oldQty - newQty) * weight
	point.scanSeconds = (safeNumber(point.scanSeconds) or 0) + dt
	point.scanPairs = (safeNumber(point.scanPairs) or 0) + 1
end

local function dailyVelocity(point)
	local seconds = safeNumber(point.scanSeconds) or 0
	if seconds >= 900 and (safeNumber(point.scanPairs) or 0) >= 2 then
		return (safeNumber(point.scanUnits) or 0) / math.max(seconds / 86400, 0.25)
	end
end

local function pruneDaily(buckets, day)
	for i = #buckets, 1, -1 do
		local bucket = tableValue(buckets[i])
		local d = bucket and safeNumber(bucket.d)
		if not d or d < day - 14 then table.remove(buckets, i) end
	end
end

local SNAPSHOT_MAX_AGE, SNAPSHOT_MAX_VALUES = 36 * 3600, 96 * 3

local function pruneSnapshots(snap, cutoff)
	local n = #snap
	local limit = math.max(n, SNAPSHOT_MAX_VALUES)
	-- A gap can hide later triplets from Lua's length operator.
	for i in pairs(snap) do
		if type(i) ~= "number" or i < 1 or i > limit or i % 1 ~= 0 then
			snap[i] = nil
		elseif i > n then
			n = i
		end
	end
	local kept = 0
	for i = 1, n - 2, 3 do
		local t, p, q = safeNumber(snap[i]), safeNumber(snap[i + 1]), safeNumber(snap[i + 2])
		if t and t >= cutoff and p and q then
			if kept + 1 ~= i then snap[kept + 1], snap[kept + 2], snap[kept + 3] = t, p, q end
			kept = kept + 3
		end
	end
	for i = kept + 1, n do snap[i] = nil end
	return kept
end

local PACK_PREFIX = "v1:"
local READ_CACHE_MAX = 512
local historyReadCache, historyReadCount = {}, 0
local dailyReadCache, dailyReadCount = {}, 0
local snapshotsReadCache, snapshotsReadCount = {}, 0

local function packNum(v)
	if not safeNumber(v, true) then return "" end
	if v == 0 then return "0" end
	if v == math.floor(v) then return string.format("%.0f", v) end
	return string.format("%.12g", v)
end

local function decodeHistoryFresh(str)
	if not readable(str) or type(str) ~= "string" or str:sub(1, 3) ~= PACK_PREFIX then return nil end
	local body = str:sub(4)
	if body == "" then return nil end
	local out = {}
	for rec in string.gmatch(body, "([^;]+)") do
		local ts, ps, qs = rec:match("^([^,]+),([^,]+),([^,]+)$")
		local t, p, q = tonumber(ts), tonumber(ps), tonumber(qs)
		if t and p and q then
			out[#out + 1] = { t = t, p = p, q = q }
		end
	end
	return #out > 0 and out or nil
end

local function decodeSnapshotsFresh(str)
	if not readable(str) or type(str) ~= "string" or str:sub(1, 3) ~= PACK_PREFIX then return nil end
	local body = str:sub(4)
	if body == "" then return nil end
	local out = {}
	for rec in string.gmatch(body, "([^;]+)") do
		local ts, ps, qs = rec:match("^([^,]+),([^,]+),([^,]+)$")
		local t, p, q = tonumber(ts), tonumber(ps), tonumber(qs)
		if t and p and q then
			local n = #out
			out[n + 1], out[n + 2], out[n + 3] = t, p, q
		end
	end
	return #out >= 3 and out or nil
end

local function decodeDailyFresh(str)
	if not readable(str) or type(str) ~= "string" or str:sub(1, 3) ~= PACK_PREFIX then return nil end
	local body = str:sub(4)
	if body == "" then return nil end
	local out = {}
	for rec in string.gmatch(body, "([^;]+)") do
		local f = {}
		local pos, idx = 1, 1
		while idx <= 11 do
			local comma = string.find(rec, ",", pos, true)
			local rawField = comma and rec:sub(pos, comma - 1) or rec:sub(pos)
			if rawField ~= "" then
				f[idx] = tonumber(rawField)
			end
			if not comma then break end
			pos = comma + 1
			idx = idx + 1
		end
		if f[1] then
			out[#out + 1] = {
				d = f[1],
				minP = f[2],
				maxP = f[3],
				lastP = f[4],
				obsP = f[5],
				lastQ = f[6],
				maxQ = f[7],
				at = f[8],
				scanUnits = f[9],
				scanSeconds = f[10],
				scanPairs = f[11],
			}
		end
	end
	return #out > 0 and out or nil
end

function MarketScan.ReadHistory(val)
	local tbl = tableValue(val)
	if tbl then return tbl end
	if not readable(val) or type(val) ~= "string" or val:sub(1, 3) ~= PACK_PREFIX then return nil end
	local cached = historyReadCache[val]
	if cached then return cached end
	local decoded = decodeHistoryFresh(val)
	if not decoded then return nil end
	if historyReadCount >= READ_CACHE_MAX then
		historyReadCache, historyReadCount = {}, 0
	end
	historyReadCache[val] = decoded
	historyReadCount = historyReadCount + 1
	return decoded
end

function MarketScan.ReadDaily(val)
	local tbl = tableValue(val)
	if tbl then return tbl end
	if not readable(val) or type(val) ~= "string" or val:sub(1, 3) ~= PACK_PREFIX then return nil end
	local cached = dailyReadCache[val]
	if cached then return cached end
	local decoded = decodeDailyFresh(val)
	if not decoded then return nil end
	if dailyReadCount >= READ_CACHE_MAX then
		dailyReadCache, dailyReadCount = {}, 0
	end
	dailyReadCache[val] = decoded
	dailyReadCount = dailyReadCount + 1
	return decoded
end

function MarketScan.ReadSnapshots(val)
	local tbl = tableValue(val)
	if tbl then return tbl end
	if not readable(val) or type(val) ~= "string" or val:sub(1, 3) ~= PACK_PREFIX then return nil end
	local cached = snapshotsReadCache[val]
	if cached then return cached end
	local decoded = decodeSnapshotsFresh(val)
	if not decoded then return nil end
	if snapshotsReadCount >= READ_CACHE_MAX then
		snapshotsReadCache, snapshotsReadCount = {}, 0
	end
	snapshotsReadCache[val] = decoded
	snapshotsReadCount = snapshotsReadCount + 1
	return decoded
end

function MarketScan.PackHistoryRing(val)
	if readable(val) and type(val) == "string" and val:sub(1, 3) == PACK_PREFIX then return val end
	local tbl = tableValue(val)
	if not tbl then return nil end
	local parts = {}
	for i = 1, #tbl do
		local e = tableValue(tbl[i])
		if e and safeNumber(e.t) and safeNumber(e.p) and safeNumber(e.q) then
			parts[#parts + 1] = packNum(e.t) .. "," .. packNum(e.p) .. "," .. packNum(e.q)
		end
	end
	return #parts > 0 and (PACK_PREFIX .. table.concat(parts, ";")) or nil
end

function MarketScan.PackSnapshots(val)
	if readable(val) and type(val) == "string" and val:sub(1, 3) == PACK_PREFIX then return val end
	local tbl = tableValue(val)
	if not tbl then return nil end
	local parts = {}
	for i = 1, #tbl - 2, 3 do
		local t, p, q = safeNumber(tbl[i]), safeNumber(tbl[i + 1]), safeNumber(tbl[i + 2])
		if t and p and q then
			parts[#parts + 1] = packNum(t) .. "," .. packNum(p) .. "," .. packNum(q)
		end
	end
	return #parts > 0 and (PACK_PREFIX .. table.concat(parts, ";")) or nil
end

function MarketScan.PackDailyBuckets(val)
	if readable(val) and type(val) == "string" and val:sub(1, 3) == PACK_PREFIX then return val end
	local tbl = tableValue(val)
	if not tbl then return nil end
	local parts = {}
	for i = 1, #tbl do
		local b = tableValue(tbl[i])
		if b and safeNumber(b.d) then
			parts[#parts + 1] = table.concat({
				packNum(b.d), packNum(b.minP), packNum(b.maxP), packNum(b.lastP),
				packNum(b.obsP), packNum(b.lastQ), packNum(b.maxQ), packNum(b.at),
				packNum(b.scanUnits), packNum(b.scanSeconds), packNum(b.scanPairs),
			}, ",")
		end
	end
	return #parts > 0 and (PACK_PREFIX .. table.concat(parts, ";")) or nil
end

function MarketScan.PackHistoryForSave(db)
	db = tableValue(db) or tableValue(MerchantMasterDB)
	if not db then return 0 end
	local packed = 0
	for _, spec in ipairs({
		{ "ahHistory", MarketScan.PackHistoryRing },
		{ "ahDaily", MarketScan.PackDailyBuckets },
		{ "ahSnapshots", MarketScan.PackSnapshots },
	}) do
		local root = tableValue(db[spec[1]])
		if root then
			local packFn = spec[2]
			for _, econTbl in pairs(root) do
				if tableValue(econTbl) then
					for itemID, entry in pairs(econTbl) do
						if safeNumber(itemID) and tableValue(entry) then
							econTbl[itemID] = packFn(entry)
							packed = packed + 1
						end
					end
				end
			end
		end
	end
	return packed
end

local function recordHistorySnapshot(econKey, itemID, minPrice, totalQty, stamp)
	itemID, minPrice, totalQty, stamp = safeNumber(itemID), safeNumber(minPrice), safeNumber(totalQty), safeNumber(stamp)
	if not MerchantMasterDB or not readable(econKey) or type(econKey) ~= "string"
		or not itemID or itemID <= 0 or not minPrice or not totalQty or not stamp or stamp <= 0 then return end
	local db = MerchantMasterDB
	local dayIndex = math.floor(stamp / 86400)
	db.ahDaily = tableValue(db.ahDaily) or {}
	db.ahDaily[econKey] = tableValue(db.ahDaily[econKey]) or {}
	local daily = db.ahDaily[econKey]
	local rawBuckets = daily[itemID]
	local buckets = tableValue(rawBuckets) or decodeDailyFresh(rawBuckets) or {}
	daily[itemID] = buckets
	pruneDaily(buckets, dayIndex)
	local bucket
	for i = #buckets, 1, -1 do
		if buckets[i].d == dayIndex then
			bucket = buckets[i]
			break
		end
	end
	if not bucket then
		bucket = { d = dayIndex }
		buckets[#buckets + 1] = bucket
		table.sort(buckets, function(a, b) return safeNumber(a.d) < safeNumber(b.d) end)
	end
	db.ahHistory = tableValue(db.ahHistory) or {}
	db.ahHistory[econKey] = tableValue(db.ahHistory[econKey]) or {}
	local rawRing = db.ahHistory[econKey][itemID]
	local ring = tableValue(rawRing) or decodeHistoryFresh(rawRing) or {}
	db.ahHistory[econKey][itemID] = ring
	local previousAt, previousQty = safeNumber(bucket.at), safeNumber(bucket.lastQ)
	local isLatest = stamp >= (previousAt or 0)
	if previousAt and previousQty and isLatest then
		local previousObsP = safeNumber(bucket.obsP)
		if previousObsP == nil then
			local last = tableValue(ring[#ring])
			if last and safeNumber(last.t) == previousAt then previousObsP = safeNumber(last.p) end
			previousObsP = previousObsP or (previousQty > 0 and safeNumber(bucket.lastP)) or 0
		end
		recordVelocity(bucket, stamp - previousAt, previousObsP, minPrice, previousQty, totalQty)
	end
	if minPrice > 0 and totalQty > 0 then
		local oldMin, oldMax = safeNumber(bucket.minP), safeNumber(bucket.maxP)
		bucket.minP = oldMin and oldMin > 0 and math.min(oldMin, minPrice) or minPrice
		bucket.maxP = oldMax and math.max(oldMax, minPrice) or minPrice
		if isLatest or not safeNumber(bucket.lastP) then bucket.lastP = minPrice end
	end
	bucket.maxQ = math.max(safeNumber(bucket.maxQ) or 0, totalQty)
	if isLatest then
		bucket.lastQ, bucket.obsP = totalQty, minPrice
		bucket.at = stamp
	end
	while #buckets > 14 do table.remove(buckets, 1) end

	db.ahSnapshots = tableValue(db.ahSnapshots) or {}
	db.ahSnapshots[econKey] = tableValue(db.ahSnapshots[econKey]) or {}
	local snapshots = db.ahSnapshots[econKey]
	local rawSnap = snapshots[itemID]
	local snap = tableValue(rawSnap) or decodeSnapshotsFresh(rawSnap) or {}
	snapshots[itemID] = snap
	local n = pruneSnapshots(snap, stamp - SNAPSHOT_MAX_AGE)
	local lastT = n >= 3 and safeNumber(snap[n - 2]) or nil
	if lastT and stamp == lastT then
		snap[n - 1], snap[n] = minPrice, totalQty
	elseif not lastT or stamp > lastT then
		if n >= 6 and snap[n - 4] == minPrice and snap[n - 3] == totalQty
			and snap[n - 1] == minPrice and snap[n] == totalQty
			and math.floor(lastT / 3600) == math.floor(stamp / 3600) then
			snap[n - 2] = stamp
		else
			snap[n + 1], snap[n + 2], snap[n + 3] = stamp, minPrice, totalQty
		end
	end
	while #snap > SNAPSHOT_MAX_VALUES do
		table.remove(snap, 1)
		table.remove(snap, 1)
		table.remove(snap, 1)
	end

	for i = #ring, 1, -1 do
		local r = ring[i]
		if not readable(r) or type(r) ~= "table" or not safeNumber(r.t) or not safeNumber(r.p)
			or not safeNumber(r.q) or r.t < stamp - 14*86400 then table.remove(ring, i) end
	end
	local last = ring[#ring]
	if last and stamp < last.t then return end
	if not last or stamp-last.t >= 600 then
		ring[#ring+1] = {t=stamp, p=minPrice, q=totalQty}
	elseif last.p ~= minPrice or last.q ~= totalQty then
		if totalQty < last.q and stamp-last.t >= 120 then
			ring[#ring+1] = {t=stamp, p=minPrice, q=totalQty}
		else last.t, last.p, last.q = stamp, minPrice, totalQty end
	end
	while #ring > 16 do table.remove(ring, 1) end
end

local function trendResult(points, source, curDay, rawDayOffset)
	local inRange, seen = {}, {}
	for _, point in ipairs(points or {}) do
		local day = tableValue(point) and safeNumber(point.d)
		if not day and rawDayOffset and tableValue(point) then
			local rawDay = safeNumber(point.day)
			day = rawDay and rawDay + rawDayOffset
		end
		if day and day % 1 == 0 and day >= curDay - 6 and day <= curDay and not seen[day] then
			seen[day] = true
			inRange[#inRange + 1] = { d = day,
				price = safeNumber(point.lastP) or safeNumber(point.price),
				observedPrice = safeNumber(point.obsP),
				qty = safeNumber(point.lastQ) or safeNumber(point.qty),
				at = safeNumber(point.at), salesPerDay = dailyVelocity(point) }
		end
	end
	table.sort(inRange, function(a, b) return a.d < b.d end)
	local startPrice, currentPrice
	local priceCount = 0
	for _, point in ipairs(inRange) do
		if point.price and point.price > 0 then
			priceCount = priceCount + 1
			startPrice = startPrice or point.price
			currentPrice = point.price
		end
	end
	local pct
	if (#inRange == 7 or source == "snapshot" or source == "merged") and priceCount >= 2 then pct = (currentPrice - startPrice) / startPrice * 100 end
	local direction = "insufficient"
	if pct then direction = pct > 0 and "up" or (pct < 0 and "down" or "flat") end
	return { daysCollected = #inRange, hasFullWeek = #inRange >= 7, currentPrice = currentPrice,
		startPrice7d = startPrice, trendPct = pct, direction = direction, points = inRange, source = source }
end

local function appendHistoryDays(points, ring, curDay)
	local byDay, previous = {}, nil
	for _, entry in ipairs(ring or {}) do
		if tableValue(entry) then
			local stamp, price, qty = safeNumber(entry.t), safeNumber(entry.p), safeNumber(entry.q)
			local day = stamp and math.floor(stamp / 86400)
			if day and day >= curDay - 6 and day <= curDay and price and qty then
				local point = byDay[day]
				if not point then
					point = { d = day }
					byDay[day] = point
					points[#points + 1] = point
				end
				if previous and previous.day == day then
					recordVelocity(point, stamp - previous.stamp, previous.price, price, previous.qty, qty)
				end
				previous = { day = day, stamp = stamp, price = price, qty = qty }
				if not point.at or stamp >= point.at then point.at, point.qty, point.obsP = stamp, qty, price end
				if price > 0 and (not point.priceAt or stamp >= point.priceAt) then
					point.priceAt, point.price = stamp, price
				end
			end
		end
	end
end

function MarketScan.GetItemTrend7d(itemID, econKey, nowOverride)
	itemID = safeNumber(itemID)
	local now = safeNumber(nowOverride) or (time and safeNumber(time())) or 0
	local curDay = math.floor(now / 86400)
	local activeEcon = ns.DetectActiveEconomy and ns.DetectActiveEconomy()
	if readable(econKey) and econKey == nil then econKey = activeEcon end
	if not itemID or itemID <= 0 or not readable(econKey) or type(econKey) ~= "string" then
		return trendResult(nil, "none", curDay)
	end
	local db = tableValue(MerchantMasterDB)
	local daily = db and tableValue(db.ahDaily)
	local econDaily = daily and tableValue(daily[econKey])
	local buckets = econDaily and MarketScan.ReadDaily(econDaily[itemID])
	local points = {}
	for _, bucket in ipairs(buckets or {}) do
		local day = tableValue(bucket) and safeNumber(bucket.d)
		if day and day % 1 == 0 and day >= curDay - 6 and day <= curDay then
			points[#points + 1] = bucket
		end
	end
	local source = #points > 0 and "ahDaily" or "ahHistory"
	local history = db and tableValue(db.ahHistory)
	local econHistory = history and tableValue(history[econKey])
	-- trendResult keeps the first point for a day, so daily buckets take precedence.
	appendHistoryDays(points, econHistory and MarketScan.ReadHistory(econHistory[itemID]), curDay)
	local liveDays, liveCount = {}, 0
	for _, pt in ipairs(points) do
		local d = tableValue(pt) and safeNumber(pt.d)
		if d and d % 1 == 0 and d >= curDay - 6 and d <= curDay and not liveDays[d] then
			liveDays[d] = true
			liveCount = liveCount + 1
		end
	end
	if liveCount >= 7 then
		local localResult = trendResult(points, source, curDay)
		if localResult.trendPct ~= nil then
			return localResult
		end
	end
	local snapAdded = 0
	if liveCount < 7 and ns.Pricing and type(ns.Pricing.GetItemHeatmap) == "function" then
		local ok, hm = pcall(ns.Pricing.GetItemHeatmap, itemID, econKey)
		if ok and tableValue(hm) and tableValue(hm.daily) then
			for d = curDay - 6, curDay do
				if not liveDays[d] then
					-- Unix day 0 (1970-01-01) was Thursday (ISO dow=4 in Mon=1..Sun=7).
					local dow = ((d + 3) % 7) + 1
					local dayRec = tableValue(hm.daily[dow])
					local avgP = dayRec and safeNumber(dayRec.avgPrice)
					if avgP and avgP > 0 then
						local avgQ = safeNumber(dayRec.avgQty) or 0
						points[#points + 1] = {
							d = d,
							lastP = avgP,
							obsP = avgP,
							lastQ = avgQ,
							at = math.min(now, d * 86400),
						}
						snapAdded = snapAdded + 1
					end
				end
			end
		end
	end
	if liveCount > 0 and snapAdded > 0 then
		return trendResult(points, "merged", curDay)
	elseif liveCount > 0 then
		return trendResult(points, source, curDay)
	elseif snapAdded > 0 then
		return trendResult(points, "snapshot", curDay)
	end
	return trendResult(nil, "none", curDay)
end

local function localClockHour(ts)
	local fn = date or (os and os.date)
	if type(fn) == "function" then
		local ok, t = pcall(fn, "*t", ts)
		if ok and type(t) == "table" and type(t.hour) == "number" then
			return t.hour
		end
	end
	return math.floor((ts % 86400) / 3600)
end

function MarketScan.GetItemTrend24h(itemID, econKey, nowOverride)
	itemID = safeNumber(itemID)
	local now = safeNumber(nowOverride) or (time and safeNumber(time())) or 0
	local curHour = math.floor(now / 3600)
	local startHour = curHour - 23
	local activeEcon = ns.DetectActiveEconomy and ns.DetectActiveEconomy()
	if readable(econKey) and econKey == nil then econKey = activeEcon end

	local byStamp, hourSource = {}, {}
	local liveSource
	local liveHourCount = 0
	local function addObservation(stamp, price, qty, from)
		stamp, price, qty = safeNumber(stamp), safeNumber(price), safeNumber(qty)
		if not stamp or stamp < startHour * 3600 or stamp > now or not price or not qty then return end
		local hour = math.floor(stamp / 3600)
		local coveredBy = hourSource[hour]
		if coveredBy and (coveredBy ~= from or from == "ahDaily") then return end
		if not coveredBy then liveHourCount = liveHourCount + 1 end
		hourSource[hour] = from
		liveSource = liveSource or from
		byStamp[stamp] = { stamp = stamp, price = price, qty = qty }
	end
	local function itemEntries(root, reader)
		root = tableValue(root)
		local economy = root and tableValue(root[econKey])
		return economy and reader(economy[itemID])
	end
	local db = tableValue(MerchantMasterDB)
	if db and itemID and itemID > 0 and readable(econKey) and type(econKey) == "string" then
		local snap = itemEntries(db.ahSnapshots, MarketScan.ReadSnapshots)
		if snap then
			for i = 1, #snap - 2, 3 do
				addObservation(snap[i], snap[i + 1], snap[i + 2], "ahSnapshots")
			end
		end
		for _, entry in ipairs(itemEntries(db.ahHistory, MarketScan.ReadHistory) or {}) do
			if tableValue(entry) then addObservation(entry.t, entry.p, entry.q, "ahHistory") end
		end
		for _, bucket in ipairs(itemEntries(db.ahDaily, MarketScan.ReadDaily) or {}) do
			if tableValue(bucket) then
				local price, qty = bucket.obsP, safeNumber(bucket.lastQ)
				if readable(price) and price == nil and qty and qty > 0 then price = bucket.lastP end
				if readable(price) and price == nil then price = 0 end
				addObservation(bucket.at, price, qty, "ahDaily")
			end
		end
	end

	-- Bidirectional merge: fill missing hours in [startHour, curHour] from SnapshotData.lua baseline
	-- while live scans always win on overlapping hours.
	local snapAdded = 0
	if liveHourCount < 24 and itemID and itemID > 0 and readable(econKey) and type(econKey) == "string" and ns.Pricing then
		local hourlyPrices, fallbackQty = nil, 0
		if type(ns.Pricing.GetItemHeatStrip24h) == "function" then
			local ok, strip = pcall(ns.Pricing.GetItemHeatStrip24h, itemID, econKey)
			if ok and tableValue(strip) and tableValue(strip.hourly) then
				hourlyPrices = strip.hourly
				fallbackQty = safeNumber(strip.avgQty) or 0
			end
		end
		local hmHourly = nil
		local needHeatmap = false
		if not hourlyPrices then
			needHeatmap = true
		else
			for h = startHour, curHour do
				if not hourSource[h] then
					local p = safeNumber(hourlyPrices[localClockHour(h * 3600)])
					if not p or p <= 0 then needHeatmap = true; break end
				end
			end
		end
		if needHeatmap and type(ns.Pricing.GetItemHeatmap) == "function" then
			local ok, hm = pcall(ns.Pricing.GetItemHeatmap, itemID, econKey)
			if ok and tableValue(hm) and tableValue(hm.hourly) then
				hmHourly = hm.hourly
			end
		end
		if hourlyPrices or hmHourly then
			for h = startHour, curHour do
				if not hourSource[h] then
					local clockHour = localClockHour(h * 3600)
					local p = hourlyPrices and safeNumber(hourlyPrices[clockHour])
					local q = fallbackQty
					if (not p or p <= 0) and hmHourly then
						local hRec = tableValue(hmHourly[clockHour])
						if hRec then
							p = safeNumber(hRec.avgPrice)
							q = safeNumber(hRec.avgQty) or q
						end
					end
					if p and p > 0 then
						local stamp = math.min(now, h * 3600)
						byStamp[stamp] = { stamp = stamp, price = p, qty = q, fromSnapshot = true }
						hourSource[h] = "snapshot"
						snapAdded = snapAdded + 1
					end
				end
			end
		end
	end

	local raw = {}
	for _, observation in pairs(byStamp) do raw[#raw + 1] = observation end
	table.sort(raw, function(a, b) return a.stamp < b.stamp end)
	local inRange, point, previous = {}, nil, nil
	for _, observation in ipairs(raw) do
		local hour = math.floor(observation.stamp / 3600)
		if not point or point.h ~= hour then
			point = { h = hour }
			inRange[#inRange + 1] = point
		end
		if previous and not previous.fromSnapshot and not observation.fromSnapshot then
			recordVelocity(point, observation.stamp - previous.stamp,
				previous.price, observation.price, previous.qty, observation.qty)
		end
		point.at, point.qty, point.observedPrice = observation.stamp, observation.qty, observation.price
		if observation.price > 0 then point.price = observation.price end
		previous = observation
	end

	local startPrice, currentPrice
	local priceCount = 0
	for _, hourly in ipairs(inRange) do
		hourly.salesPerDay = dailyVelocity(hourly)
		hourly.scanUnits, hourly.scanSeconds, hourly.scanPairs = nil, nil, nil
		if hourly.price then
			priceCount = priceCount + 1
			startPrice = startPrice or hourly.price
			currentPrice = hourly.price
		end
	end
	local pct = priceCount >= 2 and (currentPrice - startPrice) / startPrice * 100 or nil
	local direction = "insufficient"
	if pct then direction = pct > 0 and "up" or (pct < 0 and "down" or "flat") end
	local finalSource
	if liveSource and snapAdded > 0 then
		finalSource = "merged"
	elseif liveSource then
		finalSource = liveSource
	elseif snapAdded > 0 then
		finalSource = "snapshot"
	else
		finalSource = "none"
	end
	return { hoursCollected = #inRange, hasFullDay = #inRange >= 24, currentPrice = currentPrice,
		startPrice24h = startPrice, trendPct = pct, direction = direction, points = inRange,
		rawPoints = raw, source = finalSource, startHour = startHour, curHour = curHour }
end

local function recordFrontTier(econKey, itemID, floor, qty, minRemain, stamp, complete)
	if not complete or not MerchantMasterDB then return end
	local db = MerchantMasterDB
	db.ahLotPrev = db.ahLotPrev or {}; db.ahLotPrev[econKey] = db.ahLotPrev[econKey] or {}
	local prev = db.ahLotPrev[econKey][itemID]
	if not readable(prev) or type(prev) ~= "table" or not safeNumber(prev.t) then prev = nil end
	local clears = prev and prev.clears
	if not readable(clears) or type(clears) ~= "table" then clears = {} end
	if prev then
		local dt = stamp-prev.t
		if dt >= 60 and dt <= 43200 and floor and safeNumber(prev.p) and floor > prev.p
			and safeNumber(prev.q) and safeNumber(prev.minRemain) and prev.minRemain > dt+60 then
			clears[#clears+1] = {t=stamp, dt=dt, q=prev.q}
		end
	end
	for i = #clears, 1, -1 do
		local c = clears[i]
		if not readable(c) or type(c) ~= "table" or not safeNumber(c.t) or c.t < stamp-72*3600 then table.remove(clears, i) end
	end
	while #clears > 16 do table.remove(clears, 1) end
	db.ahLotPrev[econKey][itemID] = {t=stamp, p=floor, q=qty, minRemain=minRemain, clears=clears}
end

function MarketScan.GetLocalVelocity(itemID, econKey)
	local result = {scanPairs=0, confidence="None"}
	itemID = safeNumber(itemID)
	if not itemID or itemID <= 0 or not readable(econKey) then return result end
	econKey = econKey or (ns.DetectActiveEconomy and ns.DetectActiveEconomy())
	if type(econKey) ~= "string" then return result end
	local db = MerchantMasterDB
	local ring = db and db.ahHistory and db.ahHistory[econKey] and MarketScan.ReadHistory(db.ahHistory[econKey][itemID])
	if not ring then return result end
	local last = ring[#ring]
	result.latestQty = readable(last) and type(last) == "table" and safeNumber(last.q) or nil
	local now, previous, totalDt, units, spanStart, spanEnd = safeNumber(time and time()), nil, 0, 0
	if not now then return result end
	for _, r in ipairs(ring) do
		if readable(r) and type(r) == "table" and safeNumber(r.t) and safeNumber(r.p) and safeNumber(r.q)
			and r.t >= now-72*3600 and r.t <= now then
			result.latestQty = r.q
			if previous then
				local dt = r.t-previous.t
				if dt >= 60 and dt <= 43200 then
					local weight = r.p > previous.p and 1 or (r.p == previous.p and 0.55 or 0.20)
					units = units + math.max(0, previous.q-r.q)*weight
					totalDt = totalDt+dt; result.scanPairs = result.scanPairs+1
					spanStart = spanStart or previous.t; spanEnd = r.t
				end
			end
			previous = r
		end
	end
	if result.scanPairs < 2 or not spanStart or spanEnd-spanStart < 900 or totalDt < 900 then
		if result.scanPairs > 0 then result.confidence = "Low" end
		return result
	end
	local prev = db.ahLotPrev and db.ahLotPrev[econKey] and db.ahLotPrev[econKey][itemID]
	local clears = readable(prev) and type(prev) == "table" and prev.clears
	if not readable(clears) or type(clears) ~= "table" then clears = {} end
	local verified, verifiedDt = 0, 0
	for _, c in ipairs(clears) do
		if readable(c) and type(c) == "table" and safeNumber(c.t) and safeNumber(c.dt) and safeNumber(c.q)
			and c.dt >= 60 and c.dt <= 43200 and c.t-c.dt >= spanStart and c.t <= spanEnd then
			verified=verified+c.q; verifiedDt=verifiedDt+c.dt
		end
	end
	-- Verified floor clears may be hidden by new listings; do not count both signals twice.
	result.clearsPerDay = math.max(units, verified)/math.max(totalDt/86400, verifiedDt/86400, 0.25)
	result.confidence = (verified > 0 and result.scanPairs >= 3 and totalDt >= 21600) and "High" or "Med"
	return result
end

local function itemKeySignature(key)
	if ns.SellerStats then return ns.SellerStats.Key(key) end
	if not readable(key) or type(key) ~= "table" then return nil end
	local id = safeNumber(key.itemID)
	if not id or id == 0 then return nil end
	local parts = {id}
	for _, field in ipairs({"itemLevel", "itemSuffix", "battlePetSpeciesID"}) do
		if not readable(key[field]) then return nil end
		parts[#parts + 1] = safeNumber(key[field], field == "itemSuffix") or 0
	end
	return table.concat(parts, ":"), key
end

local function isBaseItemKey(key)
	if not tableValue(key) then return false end
	local itemLevel, itemSuffix, speciesID = key.itemLevel, key.itemSuffix, key.battlePetSpeciesID
	return readable(itemLevel) and readable(itemSuffix) and readable(speciesID)
		and (itemLevel or 0) == 0 and (itemSuffix or 0) == 0 and (speciesID or 0) == 0
end

local function variantMarkers(economy, create)
	local db = tableValue(MerchantMasterDB)
	if not db then return end
	local root = tableValue(db.ahVariants)
	local markers = root and tableValue(root[economy])
	if not markers and create then
		root = root or {}
		markers = {}
		db.ahVariants, root[economy] = root, markers
	end
	return markers
end

local function noteVariant(key, economy)
	if key and not isBaseItemKey(key) then
		local markers = variantMarkers(economy, true)
		if markers then markers[key.itemID] = true end
		return true
	end
end

function MarketScan.HasKnownVariants(itemID, economy)
	local markers = variantMarkers(economy)
	if markers and (markers._unidentified == true or markers[itemID] == true) then return true end
	local sellers = ns.SellerStats
	if not sellers then return false end
	if sellers.HasIncompleteCoverage(itemID, economy) then return true end
	for _, key in ipairs(sellers.GetKeys(itemID, economy)) do
		local _, copy = itemKeySignature(key)
		if copy and not isBaseItemKey(copy) then return true end
	end
	return false
end

function MarketScan.Initialize(app, context)
	if MarketScan.initialized then return end
	MarketScan.initialized = true
	local L, say = context.labels, context.say
	local missingFor, lookupID = context.missingFor, context.lookupID
	local lotsPrice, lotsFor = context.lotsPrice, context.lotsFor
	local ownedCounts, bagCrates, atAH = context.ownedCounts, context.bagCrates, context.atAH

local marketScan = { economy = nil, partial = false, equipmentOnly = false, generation = 0, active = false, internal = false, hooked = false, matched = {}, matchedCount = 0, seenKeys = {}, itemKeys = {}, itemVariants = {}, incompleteItems = {}, page = 0, seen = 0, started = 0, timer = nil }
local bagScan = { queue = {} }
local pendingSearchSeq = 0
local wantedDispatch, bagBrowseDispatch

local function invalidatePendingSearch()
	pendingSearchSeq = pendingSearchSeq + 1
	local wanted = app.wanted
	if wanted then wanted.open, wanted.dispatched, wanted.pendingBar = false, nil, nil end
end

-- Live scan feedback for the toolbar status capsule / refresh button (set by the host UI).
local function notifyScanProgress()
	if app.onScanProgress then app.onScanProgress() end
end

local function scanToast(msg, variant, duration)
	local toast = app.ui and app.ui.toast
	if toast and toast.ShowToast then toast.ShowToast(msg, variant, duration) end
end

local function setBuyQuantity(itemID)
	local name = itemID and ns.ItemName(itemID)
	local w = app.wanted
	local matchedWanted = w and w.dispatched and ((w.itemID and w.itemID == itemID) or (name and w.name and w.name:lower() == name:lower()))
	local qty = matchedWanted and w.qty or (name and missingFor(name) or 0)
	if not qty or qty <= 0 then return end
	if AuctionHouseFrame and AuctionHouseFrame.TriggerEvent and AuctionHouseFrameMixin and AuctionHouseFrameMixin.Event then
		AuctionHouseFrame:TriggerEvent(AuctionHouseFrameMixin.Event.CommoditiesQuantitySelectionChanged, qty)
	end
end

local function hookBuyFrame()
	local buyFrame = not app.buyHooked and AuctionHouseFrame and AuctionHouseFrame.CommoditiesBuyFrame
	if not buyFrame or not buyFrame.SetItemIDAndPrice then return end
	app.buyHooked = true
	hooksecurefunc(buyFrame, "SetItemIDAndPrice", function(_, itemID)
		C_Timer.After(0, function() setBuyQuantity(itemID) end)
	end)
end

local activeEconomyPrices
local function normalizedSearchName(name)
	if readable(name) and type(name) == "string" then
		return name:match("^%s*(.-)%s*$"):lower()
	end
end

local function isItemSearchName(name)
	local normalized = normalizedSearchName(name)
	return normalized and normalized ~= "" and not normalized:match("^item #%d+")
end

local function itemSearchName(itemID)
	if not safeNumber(itemID) or itemID <= 0 then return nil end
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not isItemSearchName(name) then name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID) end
	if not isItemSearchName(name) then name = GetItemInfo and GetItemInfo(itemID) end
	if isItemSearchName(name) then return name end
	local locale = GetLocale and GetLocale()
	if not locale or locale == "enUS" or locale == "enGB" then name = ns.ItemName(itemID) end
	if isItemSearchName(name) then return name end
	if ns.RequestItemDataLoad then ns.RequestItemDataLoad(itemID) end
end

local function openWanted(updated, addedBatch)
	local w = app.wanted
	if not (w and w.open and C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end
	local batch
	if updated then
		w.seenRows, w.seenBySig = nil, nil
		batch = tableValue(C_AuctionHouse.GetBrowseResults())
	else
		batch = tableValue(addedBatch)
	end
	if not batch then return end
	w.seenRows, w.seenBySig = w.seenRows or {}, w.seenBySig or {}
	local results, seenBySig, changedRows = w.seenRows, w.seenBySig, {}
	for _, result in ipairs(batch) do
		local signature = itemKeySignature(tableValue(result) and tableValue(result.itemKey))
		local index = signature and seenBySig[signature] or #results + 1
		results[index], changedRows[index] = result, true
		if signature then seenBySig[signature] = index end
	end
	local full = C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults()
	if not readable(full) then full = nil end
	if full == false and C_AuctionHouse.RequestMoreBrowseResults and w.requestedAt ~= #results then
		w.requestedAt = #results
		C_AuctionHouse.RequestMoreBrowseResults()
	end

	local totalQty = 0
	local firstResult, bestResult, minPosPrice
	local allQtyValid, allPricesValid, allKeysReadable = true, true, true
	local observedKeys, stockedKeys = {}, {}
	local wantedName = not w.itemID and w.name and w.name:lower()
	local economy = ns.DetectActiveEconomy()
	for index, result in ipairs(results) do
		local key = tableValue(result) and tableValue(result.itemKey)
		local signature, copy = itemKeySignature(key)
		if not signature then allKeysReadable = false end
		local itemID = copy and copy.itemID or key and safeNumber(key.itemID)
		local matches = itemID and itemID == w.itemID
		if wantedName and signature then
			local info = C_AuctionHouse.GetItemKeyInfo and tableValue(C_AuctionHouse.GetItemKeyInfo(key))
			local name = info and info.itemName
			if not isItemSearchName(name) then name = itemSearchName(itemID) end
			matches = readable(name) and type(name) == "string" and name:lower() == wantedName
		end
		if matches then
			local price, qty = safeNumber(result.minPrice), safeNumber(result.totalQuantity)
			if signature then
				local variant = noteVariant(copy, economy)
				if changedRows[index] and qty and qty > 0 then stockedKeys[signature] = variant == true end
				observedKeys[signature] = copy
				firstResult = firstResult or result
			end
			if qty then totalQty = totalQty + qty else allQtyValid = false end
			if not signature or (qty == 0 and price and price > 0) then allQtyValid = false end
			if price and price > 0 and qty and qty > 0 then
				if signature and (not minPosPrice or price < minPosPrice) then minPosPrice, bestResult = price, result end
			elseif not price then
				allPricesValid = false
			end
		end
	end
	local selected = bestResult or firstResult
	local targetID = w.itemID or (selected and selected.itemKey.itemID)
	local unrestricted = w.unrestricted and targetID
		and normalizedSearchName(w.name) == normalizedSearchName(itemSearchName(targetID))
	local completeKeys = full == true and allKeysReadable
	local absent = totalQty == 0
	local confirmed = completeKeys and allQtyValid and allPricesValid and safeNumber(totalQty)
	if confirmed then w.open = false end
	if ns.SellerStats then
		local suppressSellers = confirmed and unrestricted and w.itemID and ns.RecipeStats and ns.RecipeStats.Invalidate or nil
		if suppressSellers then
			ns.RecipeStats.Invalidate = function(reason, ids)
				if reason == "sellers" then return end
				return suppressSellers(reason, ids)
			end
		end
		local ok, err = pcall(function()
			if targetID and not (completeKeys and unrestricted) then
				ns.SellerStats.NoteIncompleteCoverage(targetID, economy)
			end
			if next(observedKeys) then ns.SellerStats.MergeBrowseKeys(economy, observedKeys, stockedKeys) end
		end)
		if suppressSellers then ns.RecipeStats.Invalidate = suppressSellers end
		if not ok then error(err) end
	end
	if confirmed and unrestricted and w.itemID then
		local ahTbl, activeEcon = activeEconomyPrices()
		if ahTbl then
			local stamp = time()
			local previous = tableValue(ahTbl[w.itemID])
			local lastPrice, lastAt = minPosPrice, stamp
			if not minPosPrice then
				lastPrice, lastAt = lastPositiveQuote(previous)
			end
			ahTbl[w.itemID] = { price = minPosPrice, lastPrice = lastPrice, lastAt = lastAt, qty = totalQty, absent = absent,
				at = stamp, itemWide = true }
			recordHistorySnapshot(activeEcon, w.itemID, minPosPrice or 0, totalQty, stamp)
			local changedIDs = { [w.itemID] = true }
			if ns.InvalidateItemPrices then ns.InvalidateItemPrices(changedIDs)
			elseif ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
			if app.invalidateRecipeStats then app.invalidateRecipeStats("items", changedIDs) end
			if ns.ConsoleEngine and ns.ConsoleEngine.RecordAHScan then
				ns.ConsoleEngine.RecordAHScan("single", { itemID = w.itemID, economy = activeEcon })
			end
			if app.scheduleRecipeRefresh then app.scheduleRecipeRefresh() end
		end
	end
	if selected and AuctionHouseFrame and AuctionHouseFrame.SelectBrowseResult then
		AuctionHouseFrame:SelectBrowseResult(selected)
	end
end

local function resetModernFilters(ah)
	local bar = ah and ah.SearchBar
	if not bar then return end
	local filter = bar.FilterButton
	if bar.ResetFilters then
		bar:ResetFilters()
	elseif filter and filter.Reset then
		filter:Reset()
	elseif filter and filter.ClearFiltersButton and filter.ClearFiltersButton:IsShown() then
		filter.ClearFiltersButton:Click()
	end
	if ah.CategoriesList and ah.CategoriesList.SetSelectedCategory then
		ah.CategoriesList:SetSelectedCategory(nil)
	end
end

local function resetClassicFilters()
	if AuctionFrameBrowse_Reset and BrowseResetButton then
		AuctionFrameBrowse_Reset(BrowseResetButton)
		return
	end
	if BrowseMinLevel then BrowseMinLevel:SetText("") end
	if BrowseMaxLevel then BrowseMaxLevel:SetText("") end
	if IsUsableCheckButton then IsUsableCheckButton:SetChecked(false) end
	if BrowseDropDown and UIDropDownMenu_SetSelectedValue then
		UIDropDownMenu_SetSelectedValue(BrowseDropDown, -1)
	end
end

activeEconomyPrices = function()
	local activeEcon = ns.DetectActiveEconomy()
	if MerchantMasterDB then
		MerchantMasterDB.ahPrices = MerchantMasterDB.ahPrices or {}
		MerchantMasterDB.ahPrices[activeEcon] = MerchantMasterDB.ahPrices[activeEcon] or {}
		app.ahPrices = MerchantMasterDB.ahPrices[activeEcon]
		ns.ahPrices = app.ahPrices
	end
	return app.ahPrices, activeEcon
end

function MarketScan.RecordLiveItemPrice(itemID, price, qty, opts)
	local id = safeNumber(itemID)
	if not id or id <= 0 then return false end
	id = math.floor(id)
	local ahTbl, activeEcon = activeEconomyPrices()
	if not ahTbl then return false end
	opts = tableValue(opts)
	local stamp = (opts and safeNumber(opts.stamp)) or time()
	local rawQty = safeNumber(qty) or 0
	local q = math.max(0, math.floor(rawQty))
	local rawP = safeNumber(price)
	local minP = (rawP and rawP > 0 and q > 0) and math.max(1, math.floor(rawP + 0.5)) or nil
	local isAbsent = (minP == nil)
	if q == 0 and minP ~= nil then minP = nil end
	local prev = tableValue(ahTbl[id])
	local prevLast, prevLastAt = lastPositiveQuote(prev)
	local itemWide = (opts and opts.itemWide ~= nil) and (opts.itemWide == true)
		or (prev and prev.itemWide == true) or false
	local clearLots = not (opts and opts.clearLots == false)
	if clearLots and MerchantMasterDB and MerchantMasterDB.ahLots and MerchantMasterDB.ahLots[activeEcon] then
		local oldLots = tableValue(MerchantMasterDB.ahLots[activeEcon][id])
		if oldLots and (not safeNumber(oldLots.at) or oldLots.at < stamp) then
			MerchantMasterDB.ahLots[activeEcon][id] = nil
		end
	end
	local changed = (type(prev) ~= "table"
		or prev.price ~= minP
		or prev.qty ~= q
		or prev.absent ~= isAbsent
		or not prev.at
		or stamp - prev.at > 1800
		or stamp < prev.at)
	if not changed and ns.QueryLocalSnapshot then
		local _, srec = ns.QueryLocalSnapshot(id, activeEcon)
		local snapAt = srec and safeNumber(srec.updatedAt) or 0
		if snapAt > 0 and prev and safeNumber(prev.at) and prev.at <= snapAt and stamp > snapAt then
			changed = true
		end
	end
	ahTbl[id] = {
		price = minP,
		lastPrice = minP or prevLast,
		lastAt = minP and stamp or prevLastAt,
		qty = q,
		absent = isAbsent,
		at = stamp,
		itemWide = itemWide,
	}
	if opts and opts.recordHistory == true and itemWide == true then
		recordHistorySnapshot(activeEcon, id, minP or 0, q, stamp)
	end
	if changed and not (opts and opts.deferInvalidate == true) then
		local changedIDs = { [id] = true }
		if ns.InvalidateItemPrices then ns.InvalidateItemPrices(changedIDs)
		elseif ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
		if app.invalidateRecipeStats then app.invalidateRecipeStats("items", changedIDs) end
	end
	return changed
end

local function savePartialMarketMatches()
	if marketScan.unknownItem then return end
	local ahTbl = activeEconomyPrices()
	if not ahTbl then return end
	local stamp = time()
	local changedIDs = {}
	for id, entry in pairs(marketScan.matched) do
		local existing = tableValue(ahTbl[id])
		if not entry.incomplete and safeNumber(entry.qty) and entry.qty > 0
			and safeNumber(entry.minPrice) and entry.minPrice > 0
			and (not existing or not existing.at or existing.at < stamp) then
			if MarketScan.RecordLiveItemPrice(id, entry.minPrice, entry.qty, {
				stamp = stamp,
				itemWide = (existing and existing.itemWide == true) or false,
				deferInvalidate = true,
			}) then
				changedIDs[id] = true
			end
		end
	end
	if next(changedIDs) then
		if ns.InvalidateItemPrices then ns.InvalidateItemPrices(changedIDs)
		elseif ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
		if app.invalidateRecipeStats then app.invalidateRecipeStats("items", changedIDs) end
	end
end

function app.cancelMarketScan(savePartial)
	if not marketScan.active then return end
	local econ = marketScan.economy
	local isEquipmentOnly = (marketScan.equipmentOnly == true)
	marketScan.partial = savePartial and true or false
	if savePartial and not isEquipmentOnly and ns.DetectActiveEconomy() == econ then
		savePartialMarketMatches()
		if ns.ConsoleEngine and ns.ConsoleEngine.RecordAHScan then
			ns.ConsoleEngine.RecordAHScan("partial", { economy = econ, items = 0, at = time() })
		end
	end
	if not isEquipmentOnly and ns.SellerStats and (marketScan.unknownItem or next(marketScan.incompleteItems)) then
		ns.SellerStats.RecordBrowse(econ, marketScan.itemKeys, false, marketScan.incompleteItems)
	end
	marketScan.active = false
	marketScan.equipmentOnly = false
	marketScan.onReady = nil
	if marketScan.timer then
		marketScan.timer:Cancel()
		marketScan.timer = nil
	end
	if ns.AHChannel and ns.AHChannel.Release then
		ns.AHChannel.Release("market_scan")
	end
	if app.refresh then app.refresh() end
	notifyScanProgress()
	if ns.SniperEngine and type(ns.SniperEngine.OnBrowseScanCancelled) == "function" then
		pcall(ns.SniperEngine.OnBrowseScanCancelled, econ, marketScan.partial)
	end
end

if ns.AHChannel and ns.AHChannel._SetBrowsePreemptor then
	ns.AHChannel._SetBrowsePreemptor(function()
		if marketScan.active then
			app.cancelMarketScan(false)
		end
	end)
end

function app.multiSearchBuyer(titleOrTerms, maybeRows)
	invalidatePendingSearch()
	local hasExplicitTitle = (type(titleOrTerms) == "string")
	local caller = (hasExplicitTitle and titleOrTerms ~= "") and titleOrTerms or ADDON
	local rawList = hasExplicitTitle and maybeRows or titleOrTerms
	if type(rawList) ~= "table" or #rawList == 0 then return false end

	local cartTerms = {}
	local firstRow = nil
	for _, entry in ipairs(rawList) do
		if type(entry) == "table" then
			local s = entry.searchString or entry.name
			if entry.itemID then s = itemSearchName(entry.itemID) or s end
			local q = tonumber(entry.quantity or entry.qty) or 0
			if isItemSearchName(s) then
				if not firstRow then
					firstRow = { name = s, qty = q > 0 and q or nil, itemID = entry.itemID }
				end
				cartTerms[#cartTerms + 1] = {
					searchString = s,
					isExact = (entry.isExact ~= false),
					quantity = q > 0 and math.floor(q + 0.5) or 1,
					itemID = entry.itemID,
					unitPrice = safeNumber(entry.unitPrice) or safeNumber(entry.ahUnitPrice),
					maxBuyUnit = safeNumber(entry.maxBuyUnit),
					breakEvenUnit = safeNumber(entry.breakEvenUnit),
					provenance = type(entry.provenance) == "table" and entry.provenance or {},
				}
			end
		elseif isItemSearchName(entry) then
			if not firstRow then firstRow = { name = entry } end
			cartTerms[#cartTerms + 1] = { searchString = entry, isExact = true, quantity = 1 }
		end
	end
	if #cartTerms == 0 then return false end

	if app.openCartBuyer then
		return app.openCartBuyer(cartTerms, hasExplicitTitle and caller or nil)
	end
	if MarketScan.CartBuyer and MarketScan.CartBuyer.LoadTerms then
		MarketScan.CartBuyer.LoadTerms(cartTerms, hasExplicitTitle and caller or nil)
		return true
	end
	if atAH() and firstRow then
		return app.searchAH(firstRow.name, firstRow.qty, firstRow.itemID)
	end
	if hasExplicitTitle then
		say(L.openAH)
	end
	return false
end

local function mergeProvenanceEntry(list, qty, subCraftName, targetName, sourceKind, sourceLabel, subCraftItemID, targetItemID, subCraftProf)
	if type(list) ~= "table" then return end
	local tName = (type(targetName) == "string" and targetName ~= "") and targetName or "Shopping List"
	local sName = (type(subCraftName) == "string" and subCraftName ~= "") and subCraftName or nil
	local sKind = (type(sourceKind) == "string" and sourceKind ~= "") and sourceKind or "shopping"
	local sLabel = (type(sourceLabel) == "string" and sourceLabel ~= "") and sourceLabel or "Shopping"
	local sID = safeNumber(subCraftItemID)
	if (not sID or sID <= 0) and sName and lookupID then sID = safeNumber(lookupID(sName)) end
	local tID = safeNumber(targetItemID)
	if (not tID or tID <= 0) and tName and lookupID then tID = safeNumber(lookupID(tName)) end
	local sProf = (type(subCraftProf) == "string" and subCraftProf ~= "") and subCraftProf or nil
	local addQty = math.max(1, math.floor((tonumber(qty) or 1) + 0.5))
	for _, p in ipairs(list) do
		if p.targetName == tName and p.subCraftName == sName and p.sourceKind == sKind then
			p.qty = (tonumber(p.qty) or 0) + addQty
			if (not p.sourceLabel or p.sourceLabel == "Shopping") and sLabel ~= "Shopping" then
				p.sourceLabel = sLabel
			end
			if (not p.subCraftItemID or p.subCraftItemID <= 0) and sID and sID > 0 then p.subCraftItemID = sID end
			if (not p.targetItemID or p.targetItemID <= 0) and tID and tID > 0 then p.targetItemID = tID end
			if not p.subCraftProf and sProf then p.subCraftProf = sProf end
			return
		end
	end
	list[#list + 1] = {
		qty = addQty,
		subCraftName = sName,
		subCraftItemID = (sID and sID > 0) and sID or nil,
		subCraftProf = sProf,
		targetName = tName,
		targetItemID = (tID and tID > 0) and tID or nil,
		sourceKind = sKind,
		sourceLabel = sLabel,
	}
end

function app.sendShoppingRowsToBuyer(rows, callerLabel)
	local terms = {}
	local termByKey = {}
	local cartMetaByKey = {}
	local mainItemByGroup = {}
	local subItemByGroup = {}
	local subProfByGroup = {}
	for _, row in ipairs(rows or {}) do
		if row.isMainRow and row.mainGroupKey and safeNumber(row.itemID) then
			mainItemByGroup[row.mainGroupKey] = safeNumber(row.itemID)
		elseif row.isSubBranchRoot and row.subGroupKey then
			if safeNumber(row.itemID) then subItemByGroup[row.subGroupKey] = safeNumber(row.itemID) end
			if type(row.craftProf) == "string" and row.craftProf ~= "" then subProfByGroup[row.subGroupKey] = row.craftProf
			elseif type(row.prof) == "string" and row.prof ~= "" then subProfByGroup[row.subGroupKey] = row.prof end
		end
	end
	for _, row in ipairs(rows or {}) do
		if not row.isMainRow and not row.makeMyself and not row.isVendor and row.qty and row.qty > 0 then
			local key = row.itemID or row.name
			local rowUnit = safeNumber(row.ahUnitPrice) or safeNumber(row.ahUnit) or safeNumber(row.unitPrice)
			if (not rowUnit or rowUnit <= 0) and safeNumber(row.lineCost) and row.lineCost > 0 and row.qty > 0 then
				rowUnit = math.floor(row.lineCost / row.qty + 0.5)
			end
			local existing = key and termByKey[key] or nil
			if existing then
				existing.quantity = existing.quantity + row.qty
				local meta = key and cartMetaByKey[key]
				if meta then
					if rowUnit and rowUnit > 0 then
						meta.costSum = meta.costSum + rowUnit * row.qty
						meta.pricedQty = meta.pricedQty + row.qty
					end
					local rCap = tonumber(row.maxBuyUnit)
					if rCap and rCap > 0 then
						meta.maxBuyUnit = (meta.maxBuyUnit and meta.maxBuyUnit > 0) and math.min(meta.maxBuyUnit, rCap) or rCap
					end
					local rBE = tonumber(row.breakEvenUnit)
					if rBE and rBE > 0 then
						meta.breakEvenUnit = (meta.breakEvenUnit and meta.breakEvenUnit > 0) and math.min(meta.breakEvenUnit, rBE) or rBE
					end
				end
			else
				local term = { searchString = row.name, isExact = true, quantity = row.qty, itemID = row.itemID }
				terms[#terms + 1] = term
				if key then
					termByKey[key] = term
					local rCap = tonumber(row.maxBuyUnit)
					local rBE = tonumber(row.breakEvenUnit)
					cartMetaByKey[key] = {
						costSum = (rowUnit and rowUnit > 0) and (rowUnit * row.qty) or 0,
						pricedQty = (rowUnit and rowUnit > 0) and row.qty or 0,
						maxBuyUnit = (rCap and rCap > 0) and rCap or nil,
						breakEvenUnit = (rBE and rBE > 0) and rBE or nil,
						provenance = {},
					}
				end
			end
			local meta = key and cartMetaByKey[key]
			if meta and meta.provenance then
				local grpMainID = row.mainGroupKey and mainItemByGroup[row.mainGroupKey] or row.targetItemID
				local grpSubID = (row.isSubRow and row.subGroupKey and subItemByGroup[row.subGroupKey]) or row.subCraftItemID
				local grpSubProf = (row.isSubRow and row.subGroupKey and subProfByGroup[row.subGroupKey]) or row.subCraftProf
				if type(row.provenance) == "table" and #row.provenance > 0 then
					for _, p in ipairs(row.provenance) do
						if type(p) == "table" then
							mergeProvenanceEntry(
								meta.provenance,
								p.qty or row.qty,
								p.subCraftName,
								p.targetName or callerLabel or "Shopping List",
								p.sourceKind or row.sourceKind or "shopping",
								p.sourceLabel or row.sourceLabel or "Shopping",
								p.subCraftItemID or grpSubID,
								p.targetItemID or grpMainID,
								p.subCraftProf or grpSubProf
							)
						end
					end
				else
					local subCraftName = (row.isSubRow and row.parentSubName) or row.subCraftName or nil
					local targetName = (type(row.categoryName) == "string" and row.categoryName ~= "" and row.categoryName)
						or (type(row.targetName) == "string" and row.targetName ~= "" and row.targetName)
						or callerLabel
						or "Shopping List"
					mergeProvenanceEntry(
						meta.provenance,
						row.qty,
						subCraftName,
						targetName,
						row.sourceKind or "shopping",
						row.sourceLabel or "Shopping",
						grpSubID,
						grpMainID,
						grpSubProf
					)
				end
			end
		end
	end
	if MarketScan.OrderFlow and app.enterOrderFlowMode then
		local cartSig = (app.getOrderFlowCartSignature and app.getOrderFlowCartSignature()) or nil
		local ofEnv = MarketScan.OrderFlow.GetState().env
		local reused = MarketScan.OrderFlow.HasActiveSessionForSig and MarketScan.OrderFlow.HasActiveSessionForSig(cartSig)
		local counts
		if not reused then
			local curOfState = MarketScan.OrderFlow.GetState and MarketScan.OrderFlow.GetState() or nil
			local prevSig = curOfState and curOfState.cartSig
			local prevDone = (MarketScan.OrderFlow.IsCraftCycleComplete and MarketScan.OrderFlow.IsCraftCycleComplete())
				or (MarketScan.OrderFlow.IsPipelineComplete and MarketScan.OrderFlow.IsPipelineComplete())
				or false
			local canPreserve = (not prevDone) and (type(cartSig) == "string" and cartSig ~= ""
				and type(prevSig) == "string" and prevSig ~= "")
			counts = MarketScan.OrderFlow.LoadFromShoppingRows(rows, {
				title = callerLabel,
				ownershipProvider = app.getItemOwnershipBreakdown,
				preserveProgress = canPreserve,
				cartSig = cartSig,
			})
		else
			local pipe = MarketScan.OrderFlow.GetPipelineSummary and MarketScan.OrderFlow.GetPipelineSummary() or {}
			counts = { ah = 0, collect = 0, vendor = 0, craft = 0 }
			for _, s in ipairs(pipe) do counts[s.key] = s.total or 0 end
		end
		local totalAny = (counts.ah or 0) + (counts.collect or 0) + (counts.vendor or 0) + (counts.craft or 0)
		if totalAny <= 0 then
			say("No Auction House items needed in this shopping list.")
			return false
		end
		local stAH = MarketScan.OrderFlow.GetStageStats and MarketScan.OrderFlow.GetStageStats("ah")
		local stCol = MarketScan.OrderFlow.GetStageStats and MarketScan.OrderFlow.GetStageStats("collect")
		local stVen = MarketScan.OrderFlow.GetStageStats and MarketScan.OrderFlow.GetStageStats("vendor")
		local stCr = MarketScan.OrderFlow.GetStageStats and MarketScan.OrderFlow.GetStageStats("craft")
		local initialStage
		if atAH() and stAH and not stAH.empty and not stAH.complete then
			initialStage = "ah"
		elseif ofEnv and (ofEnv.atBank or ofEnv.atMail) and stCol and not stCol.empty and (stCol.actionableRemaining or 0) > 0 then
			initialStage = "collect"
		elseif ofEnv and ofEnv.atVendor and stVen and not stVen.empty and not stVen.complete then
			initialStage = "vendor"
		elseif reused then
			local curSt = MarketScan.OrderFlow.GetActiveStage and MarketScan.OrderFlow.GetActiveStage() or "ah"
			local curStats = MarketScan.OrderFlow.GetStageStats and MarketScan.OrderFlow.GetStageStats(curSt)
			if curStats and not curStats.empty and not curStats.complete then
				initialStage = curSt
			else
				initialStage = (stAH and not stAH.empty and not stAH.complete and "ah")
					or (stCol and not stCol.empty and (stCol.actionableRemaining or 0) > 0 and "collect")
					or (stVen and not stVen.empty and not stVen.complete and "vendor")
					or (stCr and not stCr.empty and not stCr.complete and "craft")
					or curSt
			end
		else
			initialStage = (counts.ah or 0) > 0 and "ah"
				or ((stCol and not stCol.empty and (stCol.actionableRemaining or 0) > 0) and "collect")
				or ((counts.vendor or 0) > 0 and "vendor")
				or ((counts.collect or 0) > 0 and "collect")
				or "craft"
		end
		MarketScan.OrderFlow.SetActiveStage(initialStage)
		return app.enterOrderFlowMode(initialStage)
	end
	if #terms == 0 then
		say("No Auction House items needed in this shopping list.")
		return false
	end
	if app.openCartBuyer then
		local cartTerms = {}
		for _, t in ipairs(terms) do
			local key = t.itemID or t.searchString
			local meta = key and cartMetaByKey[key]
			local targetUnit = (meta and meta.pricedQty > 0) and math.floor(meta.costSum / meta.pricedQty + 0.5) or nil
			cartTerms[#cartTerms + 1] = {
				searchString = t.searchString,
				isExact = t.isExact,
				quantity = t.quantity,
				itemID = t.itemID,
				unitPrice = targetUnit,
				maxBuyUnit = meta and meta.maxBuyUnit or nil,
				breakEvenUnit = meta and meta.breakEvenUnit or nil,
				provenance = meta and meta.provenance or {},
			}
		end
		return app.openCartBuyer(cartTerms, callerLabel)
	end
	local firstTerm = terms[1]
	if firstTerm then
		return app.searchAH(firstTerm.searchString, firstTerm.quantity, firstTerm.itemID)
	end
	return false
end

local function unrestrictedBrowse(query)
	for _, field in ipairs({"itemClassFilters", "filters"}) do
		local value = query[field]
		if not readable(value) or (value ~= nil and (type(value) ~= "table" or next(value))) then
			return false
		end
	end
	for _, field in ipairs({"minLevel", "maxLevel"}) do
		local value = query[field]
		if not readable(value) or (value ~= nil and value ~= 0) then return false end
	end
	local sorts = query.sorts
	if not readable(sorts) then return false end
	if sorts ~= nil then
		if type(sorts) ~= "table" then return false end
		for _, sort in pairs(sorts) do
			if not tableValue(sort) or not readable(sort.sortOrder) or not readable(sort.reverseSort) then
				return false
			end
		end
	end
	return true
end

local function ensureMarketScanHooks()
	if not C_AuctionHouse or marketScan.hooked == C_AuctionHouse or not hooksecurefunc then return end
	marketScan.hooked = C_AuctionHouse
	for _, fnName in ipairs({ "SendBrowseQuery", "SearchForItemKeys", "SearchForFavorites", "ReplicateItems" }) do
		if C_AuctionHouse[fnName] then
			local isBrowse = fnName == "SendBrowseQuery"
			hooksecurefunc(C_AuctionHouse, fnName, function(query)
				local job = bagScan.job
				if fnName ~= "ReplicateItems" and job and job.browseToken
					and (not isBrowse or not readable(query) or query ~= bagBrowseDispatch) then
					job.browseToken, job.answered, job.browseRows = nil, nil, nil
				end
				if isBrowse and wantedDispatch and app.wanted == wantedDispatch then
					local browseQuery = tableValue(query)
					local searchName = browseQuery and normalizedSearchName(browseQuery.searchString)
					if not searchName or searchName ~= normalizedSearchName(wantedDispatch.name) then
						wantedDispatch.open, wantedDispatch.dispatched = false, false
						app.wanted = nil
						return
					end
					wantedDispatch.open, wantedDispatch.dispatched = true, true
					local scopeReadable, unrestricted = pcall(unrestrictedBrowse, browseQuery)
					wantedDispatch.unrestricted = scopeReadable and unrestricted
				elseif not marketScan.internal then
					invalidatePendingSearch()
					if marketScan.active then app.cancelMarketScan(false) end
				end
			end)
		end
	end
end

local function sendWantedWhenReady(wanted, bar)
	if ns.AHChannel and ns.AHChannel.IsBusy and ns.AHChannel.IsBusy("cart_buyer") then
		wanted.pendingBar = nil
		wanted.open = false
		return
	end
	if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
		wanted.pendingBar = bar
		return
	end
	wanted.pendingBar = nil
	wantedDispatch = wanted
	local ok, err = pcall(bar.StartSearch, bar)
	wantedDispatch = nil
	if not ok then error(err, 0) end
end

function app.searchAH(name, qty, itemID, opts)
	invalidatePendingSearch()
	if itemID then name = itemSearchName(itemID) end
	if not isItemSearchName(name) then return false end
	opts = readable(opts) and type(opts) == "table" and opts or nil
	app.cancelMarketScan(false)
	local wanted = { name = name, qty = qty, itemID = itemID, open = false }
	app.wanted = wanted
	if app.markCurrent then app.markCurrent() end
	if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
		if AuctionHouseFrame.SetDisplayMode and AuctionHouseFrameDisplayMode then
			AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
		end
		resetModernFilters(AuctionHouseFrame)
		local bar = AuctionHouseFrame.SearchBar
		if bar and (bar.SetSearchText or bar.SearchBox) then
			ensureMarketScanHooks()
			if bar.SetSearchText then bar:SetSearchText(name) else bar.SearchBox:SetText(name) end
			if opts and opts.coalesce and C_Timer and C_Timer.After then
				local token = pendingSearchSeq
				local frame = AuctionHouseFrame
				C_Timer.After(0.18, function()
					if token ~= pendingSearchSeq or marketScan.active or bagScan.job then return end
					if AuctionHouseFrame ~= frame or not frame:IsShown() then return end
					sendWantedWhenReady(wanted, bar)
				end)
			else
				sendWantedWhenReady(wanted, bar)
			end
			if AuctionHouseFrame.Raise and not (app.panel and app.panel:IsShown() and app.activeTab ~= "bags") then AuctionHouseFrame:Raise() end
			return true
		end
	end
	if AuctionFrame and AuctionFrame:IsShown() and BrowseName then
		if AuctionFrameTab1 and PanelTemplates_GetSelectedTab(AuctionFrame) ~= 1 then
			AuctionFrameTab1:Click()
		end
		resetClassicFilters()
		BrowseName:SetText(name)
		AuctionFrameBrowse_Search()
		return true
	end
	if not (opts and opts.silentNoAH) then say(L.openAH) end
	return false
end

local function armMarketTimeout()
	if marketScan.timer then marketScan.timer:Cancel() end
	if not (C_Timer and C_Timer.NewTimer) then return end
	marketScan.timer = C_Timer.NewTimer(15, function()
		if marketScan.active then
			app.cancelMarketScan(true)
			say(L.noAnswer)
		end
	end)
end

local function sendWhenAHReady(fn)
	if not marketScan.active then return end
	if C_AuctionHouse.IsThrottledMessageSystemReady() then
		armMarketTimeout()
		marketScan.internal = true
		local ok, err = pcall(fn)
		marketScan.internal = false
		if not ok then
			app.cancelMarketScan(true)
			if err then say(tostring(err)) end
		end
	else
		local retry
		retry = function()
			if not marketScan.active then return end
			sendWhenAHReady(fn)
		end
		marketScan.onReady = retry
		C_Timer.After(0.25, function()
			if marketScan.onReady == retry then
				marketScan.onReady = nil
				retry()
			end
		end)
	end
end

local function finishMarketScan()
	if not marketScan.active then return end
	if ns.DetectActiveEconomy() ~= marketScan.economy then app.cancelMarketScan(false); return end
	local isEquipmentOnly = (marketScan.equipmentOnly == true)
	local ahTbl, activeEcon = activeEconomyPrices()
	local elapsed = math.max(0.1, (GetTime and GetTime() or 1) - marketScan.started)
	local stamp = time()
	local updated = 0
	if not isEquipmentOnly then
		if marketScan.coverageComplete then
			local markers = variantMarkers(activeEcon)
			if markers then
				markers._unidentified = nil
				for id in pairs(markers) do
					if marketScan.itemVariants[id] == false then markers[id] = nil end
				end
			end
		end
		-- An unidentified row could belong to any item, including one with readable variants.
		if not marketScan.unknownItem then
			local handled = {}
			local lotsRoot = MerchantMasterDB and MerchantMasterDB.ahLots and MerchantMasterDB.ahLots[activeEcon]
			for id in pairs(ns.ALL_CATALOG_IDS) do
				handled[id] = true
				local entry = marketScan.matched[id]
				if not entry or (not entry.incomplete and safeNumber(entry.qty)) then
					local prevLast, prevLastAt = lastPositiveQuote(ahTbl[id])
					local price, qty = entry and entry.minPrice, entry and entry.qty or 0
					if lotsRoot then
						local oldLots = tableValue(lotsRoot[id])
						if oldLots and (not safeNumber(oldLots.at) or oldLots.at < stamp) then
							lotsRoot[id] = nil
						end
					end
					ahTbl[id] = { price = price, lastPrice = price or prevLast, lastAt = price and stamp or prevLastAt,
						qty = qty, absent = qty == 0, at = stamp, itemWide = true }
					recordHistorySnapshot(activeEcon, id, price or 0, qty, stamp)
					if qty > 0 then updated = updated + 1 end
				end
			end
			for id, entry in pairs(marketScan.matched) do
				if not handled[id] and not entry.incomplete and safeNumber(entry.qty) and entry.qty > 0
					and safeNumber(entry.minPrice) and entry.minPrice > 0 then
					MarketScan.RecordLiveItemPrice(id, entry.minPrice, entry.qty, {
						stamp = stamp,
						itemWide = true,
						recordHistory = true,
						deferInvalidate = true,
					})
				end
			end
		end
		local historyRoot = MerchantMasterDB and tableValue(MerchantMasterDB.ahHistory)
		local history = historyRoot and tableValue(historyRoot[activeEcon])
		local prunedAt = history and safeNumber(history._prunedAt)
		local shouldPrune = not prunedAt or stamp-prunedAt >= 86400
		if history and shouldPrune then
			history._prunedAt = stamp
			for id, rawRing in pairs(history) do
				if safeNumber(id) and not ahTbl[id] then
					local ring = MarketScan.ReadHistory(rawRing)
					local last = ring and tableValue(ring[#ring])
					local seenAt = last and safeNumber(last.t)
					if not seenAt or seenAt < stamp-14*86400 then history[id] = nil end
				end
			end
		end
		if shouldPrune then
			local root = MerchantMasterDB and tableValue(MerchantMasterDB.ahSnapshots)
			local snapshots = root and tableValue(root[activeEcon])
			if snapshots then
				local cutoff = stamp - SNAPSHOT_MAX_AGE
				for id, rawSnap in pairs(snapshots) do
					if safeNumber(id) and not ahTbl[id] then
						local snap = tableValue(rawSnap)
						if snap then
							if pruneSnapshots(snap, cutoff) == 0 then snapshots[id] = nil end
						else
							local arr = MarketScan.ReadSnapshots(rawSnap)
							if not arr or #arr < 3 then
								snapshots[id] = nil
							elseif (safeNumber(arr[1]) or 0) < cutoff then
								local copy = decodeSnapshotsFresh(rawSnap)
								if not copy or pruneSnapshots(copy, cutoff) == 0 then
									snapshots[id] = nil
								else
									snapshots[id] = MarketScan.PackSnapshots(copy)
								end
							end
						end
					end
				end
			end
		end
		local dailyRoot = MerchantMasterDB and tableValue(MerchantMasterDB.ahDaily)
		local daily = dailyRoot and tableValue(dailyRoot[activeEcon])
		if daily then
			local curDay = math.floor(stamp / 86400)
			local dayCutoff = curDay - 14
			for id, rawBuckets in pairs(daily) do
				if safeNumber(id) and not ns.ALL_CATALOG_IDS[id] then
					local buckets = tableValue(rawBuckets)
					if buckets then
						pruneDaily(buckets, curDay)
						if #buckets == 0 then daily[id] = nil end
					else
						local arr = MarketScan.ReadDaily(rawBuckets)
						if not arr or #arr == 0 then
							daily[id] = nil
						else
							local hasStale = false
							for i = 1, #arr do
								local d = tableValue(arr[i]) and safeNumber(arr[i].d)
								if not d or d < dayCutoff then
									hasStale = true
									break
								end
							end
							if hasStale then
								local copy = decodeDailyFresh(rawBuckets)
								if not copy then
									daily[id] = nil
								else
									pruneDaily(copy, curDay)
									daily[id] = (#copy > 0) and MarketScan.PackDailyBuckets(copy) or nil
								end
							end
						end
					end
				end
			end
		end
	end
	marketScan.partial = not marketScan.coverageComplete or marketScan.quoteIncomplete
	if not isEquipmentOnly then
		if not marketScan.partial then
			ahTbl._scannedAt = stamp
			if MerchantMasterDB then MerchantMasterDB.lastRefreshAt = stamp end
		end
		if ns.ConsoleEngine and ns.ConsoleEngine.RecordAHScan then
			ns.ConsoleEngine.RecordAHScan(marketScan.partial and "partial" or "full", {
				economy = activeEcon,
				items = updated,
				elapsed = elapsed,
				at = stamp,
			})
		end
		if ns.SellerStats then
			ns.SellerStats.RecordBrowse(activeEcon, marketScan.itemKeys, marketScan.coverageComplete, marketScan.incompleteItems)
		end
	end
	local seenCount = marketScan.seen or 0
	marketScan.active = false
	marketScan.equipmentOnly = false
	marketScan.onReady = nil
	if marketScan.timer then
		marketScan.timer:Cancel()
		marketScan.timer = nil
	end
	if ns.AHChannel and ns.AHChannel.Release then
		ns.AHChannel.Release("market_scan")
	end
	if not isEquipmentOnly then
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
		if ns.MP and ns.MP.app then ns.MP.app.lastPathResult = nil end
		local summary = marketScan.partial
			and "Live AH scan (%s) partial: %d catalog items updated in %.1fs (incomplete results)."
			or "Live AH scan (%s) complete: %d catalog items updated in %.1fs."
		say(string.format(summary, activeEcon, updated, elapsed))
	else
		local equipChanged = {}
		if not marketScan.unknownItem then
			for id, entry in pairs(marketScan.matched) do
				if not entry.incomplete and safeNumber(entry.qty) and entry.qty > 0
					and safeNumber(entry.minPrice) and entry.minPrice > 0 then
					if MarketScan.RecordLiveItemPrice(id, entry.minPrice, entry.qty, {
						stamp = stamp,
						itemWide = false,
						deferInvalidate = true,
					}) then
						equipChanged[id] = true
					end
				end
			end
		end
		if next(equipChanged) then
			if ns.InvalidateItemPrices then ns.InvalidateItemPrices(equipChanged)
			elseif ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
			if app.invalidateRecipeStats then app.invalidateRecipeStats("items", equipChanged) end
		end
		local summary = marketScan.partial
			and "Equipment AH scan (%s) partial: %d items scanned in %.1fs (incomplete results)."
			or "Equipment AH scan (%s) complete: %d items scanned in %.1fs."
		say(string.format(summary, activeEcon, seenCount, elapsed))
	end
	if app.refresh then app.refresh() end
	notifyScanProgress()
	if isEquipmentOnly then
		if marketScan.partial then
			scanToast(string.format("Equipment AH Scan Partial - %d items scanned", seenCount), "warning", 3.2)
		else
			scanToast(string.format("Equipment AH Scan Complete - %d items scanned", seenCount), "success", 3.2)
		end
	elseif marketScan.partial then
		scanToast(string.format("AH Scan Partial · %d items updated", updated), "warning", 3.2)
	else
		scanToast(string.format("AH Scan Complete · %d items updated", updated), "success", 3.2)
	end
	if not isEquipmentOnly and app.warmSuperListCache and not (app.panel and app.panel:IsShown() and app.activeTab == "recipes") then
		app.warmSuperListCache(0.05)
	end
	if ns.SniperEngine and type(ns.SniperEngine.OnBrowseScanComplete) == "function" then
		pcall(ns.SniperEngine.OnBrowseScanComplete, activeEcon, marketScan.partial)
	end
end

local function handleMarketBrowseResults(addedBatch)
	if not marketScan.active or not marketScan.querySent then return end
	if ns.DetectActiveEconomy() ~= marketScan.economy then app.cancelMarketScan(false); return end
	local results = tableValue(addedBatch or C_AuctionHouse.GetBrowseResults())
	if not results then return end
	marketScan.seen = (marketScan.seen or 0) + #results
	local stockedKeys = {}
	local batchRows = {}
	for _, entry in ipairs(results) do
		local key = tableValue(entry) and tableValue(entry.itemKey)
		local sig, copy = itemKeySignature(key)
		local id = key and safeNumber(key.itemID)
		local qty, minP, quoteValid
		if sig then
			marketScan.itemVariants[id] = marketScan.itemVariants[id] or noteVariant(copy, marketScan.economy) or false
			qty, minP = safeNumber(entry.totalQuantity), safeNumber(entry.minPrice)
			if qty and qty > 0 then stockedKeys[sig] = copy end
			quoteValid = qty and minP and (qty > 0 or minP == 0)
			if not quoteValid then marketScan.quoteIncomplete = true end
			if id and id > 0 and qty and qty > 0 and minP and minP > 0 then
				local rowLink = readable(entry.itemLink) and type(entry.itemLink) == "string" and entry.itemLink or nil
				local rowQuality, rowIsCommodity
				if readable(C_AuctionHouse) and type(C_AuctionHouse) == "table"
					and readable(C_AuctionHouse.GetItemKeyInfo) and type(C_AuctionHouse.GetItemKeyInfo) == "function" then
					local okInfo, rawInfo = pcall(C_AuctionHouse.GetItemKeyInfo, copy, true)
					local keyInfo = okInfo and tableValue(rawInfo) or nil
					if keyInfo then
						if readable(keyInfo.quality) and type(keyInfo.quality) == "number" then
							rowQuality = keyInfo.quality
						end
						if readable(keyInfo.isCommodity) and type(keyInfo.isCommodity) == "boolean" then
							rowIsCommodity = keyInfo.isCommodity
						end
					end
				end
				if rowQuality == nil and readable(entry.quality) and type(entry.quality) == "number" then
					rowQuality = entry.quality
				end
				if rowIsCommodity == nil and readable(entry.isCommodity) and type(entry.isCommodity) == "boolean" then
					rowIsCommodity = entry.isCommodity
				end
				batchRows[#batchRows + 1] = {
					itemID = id,
					itemKey = copy,
					minPrice = minP,
					totalQuantity = qty,
					itemLink = rowLink,
					quality = rowQuality,
					isCommodity = rowIsCommodity,
				}
			end
		else
			marketScan.coverageComplete = false
			if id and id > 0 then marketScan.incompleteItems[id] = true end
		end
		if not id or id <= 0 then
			if not marketScan.unknownItem then
				local markers = variantMarkers(marketScan.economy, true)
				if markers then markers._unidentified = true end
			end
			marketScan.unknownItem = true
		else
			if sig then marketScan.itemKeys[sig] = copy end
			if not quoteValid or not marketScan.seenKeys[sig] then
				if sig then marketScan.seenKeys[sig] = true end
				local rec = marketScan.matched[id]
				if not rec then
					if ns.ALL_CATALOG_IDS and ns.ALL_CATALOG_IDS[id] then
						marketScan.matchedCount = (marketScan.matchedCount or 0) + 1
					end
					rec = { qty = 0 }
					marketScan.matched[id] = rec
				end
				if quoteValid then
					rec.qty = rec.qty + qty
					if qty > 0 and minP > 0 then rec.minPrice = rec.minPrice and math.min(minP, rec.minPrice) or minP end
				else
					rec.incomplete = true
				end
			end
		end
	end
	if #batchRows > 0 and ns.SniperEngine and type(ns.SniperEngine.OnBrowseBatch) == "function" then
		pcall(ns.SniperEngine.OnBrowseBatch, batchRows, marketScan.economy)
	end
	if ns.SellerStats and next(stockedKeys) then
		ns.SellerStats.NoteBrowseSupply(marketScan.economy, stockedKeys, marketScan.itemKeys)
	end
	marketScan.page = marketScan.page + 1
	if app.ui and app.ui.statusText and app.ui.statusText:IsVisible() then
		app.ui.statusText:SetText(string.format("Scanning Live AH… page %d", marketScan.page))
	end
	notifyScanProgress()
	local full = C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults()
	if readable(full) and full == true then
		finishMarketScan()
	elseif C_AuctionHouse.RequestMoreBrowseResults then
		sendWhenAHReady(function() C_AuctionHouse.RequestMoreBrowseResults() end)
	end
end

local function startMarketBrowseScan(equipmentOnly)
	invalidatePendingSearch()
	local ahFrame = readable(AuctionHouseFrame) and AuctionHouseFrame or nil
	local ahFrameType = type(ahFrame)
	local ahOpen = false
	if ahFrame and (ahFrameType == "table" or ahFrameType == "userdata")
		and readable(ahFrame.IsShown) and type(ahFrame.IsShown) == "function" then
		local ok, shown = pcall(ahFrame.IsShown, ahFrame)
		ahOpen = ok and readable(shown) and shown == true
	end
	local sendBrowse = readable(C_AuctionHouse) and type(C_AuctionHouse) == "table"
		and readable(C_AuctionHouse.SendBrowseQuery) and type(C_AuctionHouse.SendBrowseQuery) == "function"
	if not ahOpen or not sendBrowse then return false, "ah_closed" end
	if ns.AHChannel and ns.AHChannel.IsBusy and ns.AHChannel.IsBusy("market_scan") then
		return false, "busy"
	end
	if marketScan.active then
		app.cancelMarketScan(false)
	end
	if app.cancelOrderBookScan then app.cancelOrderBookScan() end
	if ns.AHChannel and ns.AHChannel.TryAcquire then
		ns.AHChannel.TryAcquire("market_scan", "browse")
	end
	if ns.MP and ns.MP.app then ns.MP.app.lastPathResult = nil end
	-- Ensure manual Live AH scan feeds into active economy
	ensureMarketScanHooks()
	marketScan.active = true
	marketScan.equipmentOnly = (equipmentOnly == true)
	marketScan.querySent = false
	marketScan.economy = ns.DetectActiveEconomy()
	marketScan.generation = marketScan.generation + 1
	marketScan.partial = false
	marketScan.coverageComplete = true
	marketScan.quoteIncomplete = false
	marketScan.unknownItem = false
	wipe(marketScan.matched)
	marketScan.matchedCount = 0
	wipe(marketScan.seenKeys)
	wipe(marketScan.itemKeys)
	wipe(marketScan.itemVariants)
	wipe(marketScan.incompleteItems)
	marketScan.page = 0
	marketScan.seen = 0
	marketScan.started = GetTime and GetTime() or 0
	if app.refresh then app.refresh() end
	notifyScanProgress()
	if marketScan.equipmentOnly then
		scanToast("Scanning All Equipment on AH...", "info", 2.2)
		local eqFilters = {}
		if Enum and Enum.AuctionHouseFilter then
			for _, key in ipairs({ "UncommonQuality", "RareQuality", "EpicQuality" }) do
				local val = Enum.AuctionHouseFilter[key]
				if val ~= nil then
					eqFilters[#eqFilters + 1] = val
				end
			end
		end
		sendWhenAHReady(function()
			marketScan.querySent = true
			C_AuctionHouse.SendBrowseQuery({
				searchString = "",
				sorts = {},
				filters = eqFilters,
				itemClassFilters = { { classID = 2 }, { classID = 4 } },
			})
		end)
	else
		scanToast("Scanning Live Auction House...", "info", 2.2)
		sendWhenAHReady(function()
			marketScan.querySent = true
			C_AuctionHouse.SendBrowseQuery({
				searchString = "",
				sorts = {},
				filters = {},
				itemClassFilters = {},
			})
		end)
	end
	return true, "started"
end

function app.refreshAllMarketValues()
	invalidatePendingSearch()
	if marketScan.active then
		app.cancelMarketScan(true)
		return true
	end
	local ok = startMarketBrowseScan(false)
	return ok
end

function MarketScan.StartEquipmentBrowseScan()
	if marketScan.active and marketScan.equipmentOnly then
		return true, "already_active"
	end
	return startMarketBrowseScan(true)
end

function MarketScan.EnsureBrowseRunning()
	if marketScan.active then
		return true, "already_active"
	end
	if app.refreshAllMarketValues() then
		return true, "started"
	end
	return false, "ah_closed"
end

function MarketScan.CancelBrowseScan(savePartial)
	if not marketScan.active then return false end
	app.cancelMarketScan(savePartial ~= false)
	return true
end

---------------------------------------------------------------------------------------------------
-- Bag-Crate Targeted Price Scanner (My Bag Crates tab)

local PRICE_SORT = Enum and Enum.AuctionHouseSortOrder and { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } or {}
local QUERY_GAP, ANSWER_WAIT, TRIES = 1, 6, 3
local SNIPER_QUERY_GAP, SNIPER_MAX_GAP, SNIPER_ANSWER_WAIT, SNIPER_TRIES = 0.05, 0.35, 4, 1
local nextBagJob, sendBagJob

local function whenBagScanReady(fn, job)
	if job and bagScan.job ~= job then return end
	if job and (job.economy ~= ns.DetectActiveEconomy() or not (AuctionHouseFrame and AuctionHouseFrame:IsShown())) then
		app.cancelOrderBookScan()
		return
	end
	if ns.AHChannel and ns.AHChannel.IsBusy and ns.AHChannel.IsBusy("market_scan") then
		if C_Timer and C_Timer.After then
			C_Timer.After(0.25, function() whenBagScanReady(fn, job) end)
		end
		return
	end
	if job and job.sniperKind == "queue" and ns.SniperEngine and ns.SniperEngine.purchase ~= nil then
		C_Timer.After(0.25, function() whenBagScanReady(fn, job) end)
		return
	end
	local now = GetTime and GetTime() or 0
	local gap = (job and job.isSniper) and (bagScan.sniperGap or SNIPER_QUERY_GAP) or QUERY_GAP
	local wait = (bagScan.lastSent or 0) + gap - now
	if wait > 0 then
		C_Timer.After(wait, function() whenBagScanReady(fn, job) end)
	elseif not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady() then
		bagScan.lastSent = now
		fn()
	else
		if job and job.isSniper then
			bagScan.sniperGap = math.min(SNIPER_MAX_GAP, (bagScan.sniperGap or SNIPER_QUERY_GAP) + 0.10)
		end
		local again = function() whenBagScanReady(fn, job) end
		bagScan.onReady = again
		local pollWait = (job and job.isSniper) and 0.25 or 0.5
		C_Timer.After(pollWait, function()
			if bagScan.onReady == again then
				bagScan.onReady = nil
				again()
			end
		end)
	end
end

local function runBagJobs()
	local jobs = { bagScan.job }
	for _, job in ipairs(bagScan.queue) do jobs[#jobs + 1] = job end
	return jobs
end

local function updateBagScanning()
	wipe(app.scanning)
	for _, job in pairs(runBagJobs()) do
		if job and job.targets then
			for _, target in ipairs(job.targets) do app.scanning[target.crate] = true end
		end
	end
end

local function recordOrderBookLots(itemID, lots, whole, economy, complete, marketMinPrice, marketQty, itemKey)
	if not (MerchantMasterDB and safeNumber(itemID) and itemID > 0 and readable(lots) and type(lots) == "table") then return end
	if not isBaseItemKey(itemKey) then return end
	if economy ~= ns.DetectActiveEconomy() then return end
	local ahTbl, activeEcon = activeEconomyPrices()
	MerchantMasterDB.ahLots = MerchantMasterDB.ahLots or {}
	MerchantMasterDB.ahLots[activeEcon] = MerchantMasterDB.ahLots[activeEcon] or {}

	local merged = {}
	local totalQty = 0
	for _, lot in ipairs(lots) do
		local q = safeNumber(lot.n) or safeNumber(lot.qty) or 0
		local p = safeNumber(lot.price) or 0
		if q > 0 and p > 0 then
			local unitP = math.max(1, whole and math.floor((p / q) + 0.5) or math.floor(p + 0.5))
			if unitP > 0 then
				totalQty = totalQty + q
				local last = merged[#merged]
				if last and last.price == unitP then
					last.qty = last.qty + q
					last.minRemain = last.minRemain and safeNumber(lot.minRemain) and math.min(last.minRemain, lot.minRemain) or nil
				else
					merged[#merged + 1] = { price = unitP, qty = q, minRemain = safeNumber(lot.minRemain) }
				end
			end
		end
	end

	if not complete and #merged == 0 then return end
	local stamp = time()
    local changed=false
	MerchantMasterDB.ahLots[activeEcon][itemID] = { at = stamp, lots = merged }
	if ahTbl then
		local prev = tableValue(ahTbl[itemID])
		local prevLast, prevLastAt = lastPositiveQuote(prev)
		local newPrice = merged[1] and merged[1].price or nil
		local writePrice = newPrice
		local writeQty = totalQty
		local writeAbsent = (totalQty == 0)
		local itemWide = complete == true and not MarketScan.HasKnownVariants(itemID, activeEcon)
        changed=type(prev)~="table" or prev.price~=writePrice or prev.qty~=writeQty or prev.absent~=writeAbsent
            or prev.itemWide~=itemWide or not prev.at or stamp-prev.at>1800 or stamp<prev.at
		if not changed and ns.QueryLocalSnapshot then
			local _, srec = ns.QueryLocalSnapshot(itemID, activeEcon)
			local snapAt = srec and safeNumber(srec.updatedAt) or 0
			if snapAt > 0 and prev and safeNumber(prev.at) and prev.at <= snapAt and stamp > snapAt then
				changed = true
			end
		end
		ahTbl[itemID] = {
			price = writePrice,
			lastPrice = writePrice or prevLast,
			lastAt = writePrice and stamp or prevLastAt,
			qty = writeQty,
			absent = writeAbsent,
			at = stamp,
			itemWide = itemWide,
		}
		-- A truncated result set cannot establish that supply disappeared.
		-- A base-key search cannot measure the supply of other known item variants.
		if itemWide then
			if marketQty == nil then marketQty, marketMinPrice = writeQty, writePrice end
			recordHistorySnapshot(activeEcon, itemID, marketMinPrice or 0, marketQty, stamp)
		end
		local front = merged[1]
		recordFrontTier(activeEcon, itemID, newPrice, front and front.qty or 0, front and front.minRemain, stamp, itemWide)
	end
	if changed then
		local changedIDs = { [itemID] = true }
		if ns.InvalidateItemPrices then ns.InvalidateItemPrices(changedIDs)
		elseif ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
		if app.invalidateRecipeStats then app.invalidateRecipeStats("items", changedIDs) end
	end
end

local ITEM_TIME_LEFT = { [0] = 0, [1] = 1800, [2] = 7200, [3] = 43200 }

local function readSearchLot(info, commodity)
	if not tableValue(info) then return nil, false end
	local qty = safeNumber(info.quantity)
	local competitorQty, rawPrice, price, remain
	if commodity then
		local owned = info.numOwnerItems
		if not readable(owned) then return nil, false end
		owned = owned == nil and 0 or safeNumber(owned)
		if not qty or not owned or owned > qty then return nil, false end
		competitorQty = qty - owned
		rawPrice = info.unitPrice
		remain = safeNumber(info.timeLeftSeconds)
	else
		local owned = info.containsOwnerItem
		if not readable(owned) then return nil, false end
		competitorQty = owned and 0 or qty
		rawPrice = info.buyoutAmount
		remain = ITEM_TIME_LEFT[safeNumber(info.timeLeft)]
	end
	if not readable(rawPrice) then return nil, false end
	if rawPrice ~= nil then
		price = safeNumber(rawPrice)
		if not price then return nil, false end
	else
		price = 0
	end
	if not qty then return nil, false end
	if competitorQty == 0 or price == 0 then return nil, true, qty, price end
	return { n = competitorQty, price = price, minRemain = remain }, true, qty, price
end

local function addMarketLot(marketQty, marketMinPrice, qty, price, commodity)
	if not qty or qty <= 0 then return marketQty, marketMinPrice end
	marketQty = marketQty + qty
	if not price or price <= 0 then return marketQty, marketMinPrice end
	local unitPrice = math.max(1, math.floor((commodity and price or price / qty) + 0.5))
	return marketQty, marketMinPrice and math.min(marketMinPrice, unitPrice) or unitPrice
end

-- Price checks opened by the Blizzard AH also contribute complete item history.
local function recordCompletedSearch(value, commodity, itemID)
	if marketScan.active or not C_AuctionHouse then return end
	local ah = C_AuctionHouse
	if not itemID or itemID <= 0 then return end
	if not commodity and not isBaseItemKey(value) then
		local _, key = itemKeySignature(value)
		if not key or not ah.GetNumItemSearchResults or not ah.GetItemSearchResultInfo then return end
		local count = safeNumber(ah.GetNumItemSearchResults(value))
		if not count or count % 1 ~= 0 then return end
		for i = 1, count do
			local row = tableValue(ah.GetItemSearchResultInfo(value, i))
			local qty = row and safeNumber(row.quantity)
			if qty and qty > 0 then
				noteVariant(key, ns.DetectActiveEconomy())
				break
			end
		end
		return
	end
	-- The AH can deliver multiple events for the order book we just processed this frame.
	if not bagScan.job and bagScan.recordedItemID == itemID and bagScan.recordedAt == GetTime() then return end
	local hasFull, getNum, getInfo
	if commodity then
		hasFull, getNum, getInfo = ah.HasFullCommoditySearchResults, ah.GetNumCommoditySearchResults, ah.GetCommoditySearchResultInfo
	else
		hasFull, getNum, getInfo = ah.HasFullItemSearchResults, ah.GetNumItemSearchResults, ah.GetItemSearchResultInfo
	end
	if not hasFull or not getNum or not getInfo then return end
	local full = hasFull(value)
	local count = safeNumber(getNum(value))
	if not count or count % 1 ~= 0 then return end
	if not readable(full) or full ~= true then
		local p1Qty, p1Min = 0, nil
		for i = 1, count do
			local _, valid, qty, price = readSearchLot(getInfo(value, i), commodity)
			if valid then
				p1Qty, p1Min = addMarketLot(p1Qty, p1Min, qty, price, commodity)
			end
		end
		if p1Min and p1Min > 0 and p1Qty > 0 then
			MarketScan.RecordLiveItemPrice(itemID, p1Min, p1Qty, { itemWide = false })
			if ns.ConsoleEngine and ns.ConsoleEngine.RecordAHScan then
				ns.ConsoleEngine.RecordAHScan("single", { itemID = itemID })
			end
			if app.scheduleRecipeRefresh then app.scheduleRecipeRefresh() end
		end
		return
	end
	local lots, marketQty, marketMinPrice = {}, 0, nil
	for i = 1, count do
		local lot, valid, qty, price = readSearchLot(getInfo(value, i), commodity)
		if not valid then return end
		marketQty, marketMinPrice = addMarketLot(marketQty, marketMinPrice, qty, price, commodity)
		if lot then lots[#lots + 1] = lot end
	end
	table.sort(lots, function(a, b) return a.price / (commodity and 1 or a.n) < b.price / (commodity and 1 or b.n) end)
	recordOrderBookLots(itemID, lots, not commodity, ns.DetectActiveEconomy(), true, marketMinPrice, marketQty,
		commodity and { itemID = itemID } or value)
	if ns.ConsoleEngine and ns.ConsoleEngine.RecordAHScan then
		ns.ConsoleEngine.RecordAHScan("single", { itemID = itemID })
	end
	if app.scheduleRecipeRefresh then app.scheduleRecipeRefresh() end
end

local function finishBagJob(lots, whole, failed, complete, marketMinPrice, marketQty, rawRows)
	local job = bagScan.job
	if not job then return end
	bagScan.job = nil
	if bagScan.timer then bagScan.timer:Cancel(); bagScan.timer = nil end
	if job.isOrderBookScan then
		app.lotScanDone = app.lotScanDone + 1
	end
	if job.sellers and ns.SellerStats then
		ns.SellerStats.Publish(job.sellers, failed and "Item search timed out before completion." or nil)
	end
	if job.isSniper then
		if job.itemID and not failed then
			if complete and isBaseItemKey(job.itemKey) then
				recordOrderBookLots(job.itemID, lots or {}, whole, job.economy, true, marketMinPrice, marketQty, job.itemKey)
			elseif safeNumber(marketMinPrice) and marketMinPrice > 0 and job.economy == ns.DetectActiveEconomy() then
				MarketScan.RecordLiveItemPrice(job.itemID, marketMinPrice, marketQty or 1, { itemWide = false })
			end
			bagScan.recordedItemID, bagScan.recordedAt = job.itemID, GetTime()
		end
	elseif job.itemID and not failed and not job.sellerOnly and isBaseItemKey(job.itemKey) then
		recordOrderBookLots(job.itemID, lots or {}, whole, job.economy, complete, marketMinPrice, marketQty, job.itemKey)
		if complete then bagScan.recordedItemID, bagScan.recordedAt = job.itemID, GetTime() end
	end
	if not failed and not job.isOrderBookScan and job.itemID and (job.sniperKind == "check" or not job.isSniper) then
		if ns.ConsoleEngine and ns.ConsoleEngine.RecordAHScan then
			ns.ConsoleEngine.RecordAHScan("single", { itemID = job.itemID, economy = job.economy })
		end
	end
	if type(job.onResult) == "function" then
		pcall(job.onResult, {
			itemID = job.itemID,
			itemKey = job.itemKey,
			isCommodity = job.isCommodity,
			lots = lots or {},
			rawRows = rawRows,
			whole = whole,
			failed = failed == true,
			complete = complete == true,
			marketMinPrice = marketMinPrice,
			marketQty = marketQty,
			economy = job.economy,
		})
	end
	if not job.isSniper then
		for _, target in ipairs(job.targets or {}) do
			local cost, short, kept
			if lots and not failed then
				cost, short = lotsPrice(lots, whole, target.qty)
				kept = lotsFor(lots, target.qty)
			end
			if not cost and not failed then short = target.qty end
			app.costs[target.crate] = app.costs[target.crate] or {}
			app.costs[target.crate][job.item] = {
				qty = target.qty, cost = cost, short = short, failed = failed,
				at = time(), lots = kept, whole = whole,
			}
		end
		if #bagScan.queue == 0 then
			local doneLots = app.lotScanDone or 0
			app.lotScanTotal, app.lotScanDone = 0, 0
			if doneLots > 0 and ns.ConsoleEngine and ns.ConsoleEngine.RecordAHScan then
				ns.ConsoleEngine.RecordAHScan("deep_lot", { items = doneLots, economy = job.economy })
			end
		end
		updateBagScanning()
		if app.refresh then app.refresh() end
		notifyScanProgress()
	elseif #bagScan.queue == 0 then
		local doneLots = app.lotScanDone or 0
		app.lotScanTotal, app.lotScanDone = 0, 0
		if doneLots > 0 and ns.ConsoleEngine and ns.ConsoleEngine.RecordAHScan then
			ns.ConsoleEngine.RecordAHScan("deep_lot", { items = doneLots, economy = job.economy })
		end
	end
	if not bagScan.job then
		nextBagJob(job.isSniper)
	end
end

local function largestQty(job)
	local qty = job.orderBookQty or 0
	for _, target in ipairs(job.targets or {}) do qty = math.max(qty, target.qty) end
	return math.max(1, qty)
end

local function armBagTimeout(job)
	if bagScan.timer then bagScan.timer:Cancel() end
	local answerWait = (job and job.isSniper) and SNIPER_ANSWER_WAIT or ANSWER_WAIT
	local maxTries = (job and job.isSniper) and SNIPER_TRIES or TRIES
	bagScan.timer = C_Timer.NewTimer(answerWait, function()
		if bagScan.job ~= job then return end
		job.tries = (job.tries or 1) + 1
		if job.tries > maxTries then finishBagJob(nil, nil, true) else sendBagJob(job) end
	end)
end

local function commodityKind(key)
	local info = C_AuctionHouse.GetItemKeyInfo and tableValue(C_AuctionHouse.GetItemKeyInfo(key))
	local kind = info and info.isCommodity
	if readable(kind) and type(kind) == "boolean" then return kind end
end

sendBagJob = function(job)
	if bagScan.job ~= job then return end
	if job.economy ~= ns.DetectActiveEconomy() then app.cancelOrderBookScan(); return end
	job.attempt = (job.attempt or 0) + 1
	job.browseToken = nil
	local attempt = job.attempt
	if bagScan.timer then bagScan.timer:Cancel(); bagScan.timer = nil end
	if not job.isSniper then notifyScanProgress() end
	whenBagScanReady(function()
		if bagScan.job ~= job or job.attempt ~= attempt then return end
		job.answered, job.received = nil, nil
		job.morePending, job.browseRows = nil, nil
		armBagTimeout(job)
		if job.itemID then
			job.stage = "search"
			local key = job.itemKey or C_AuctionHouse.MakeItemKey(job.itemID)
			job.itemKey = key
			job.isCommodity = commodityKind(key)
			if ns.SellerStats and not job.sellers and not job.isSniper then job.sellers = ns.SellerStats.Begin(key, job.economy) end
			local hasResults = C_AuctionHouse.HasSearchResults and C_AuctionHouse.HasSearchResults(key)
			if job.isSniper and job.isCommodity ~= true and C_AuctionHouse.SendSearchQuery then
				C_AuctionHouse.SendSearchQuery(key, PRICE_SORT, true)
			elseif hasResults and job.isCommodity == true and C_AuctionHouse.RefreshCommoditySearchResults then
				C_AuctionHouse.RefreshCommoditySearchResults(job.itemID)
			elseif hasResults and job.isCommodity == false and C_AuctionHouse.RefreshItemSearchResults then
				C_AuctionHouse.RefreshItemSearchResults(key)
			elseif C_AuctionHouse.SendSearchQuery then
				C_AuctionHouse.SendSearchQuery(key, PRICE_SORT, job.isSniper == true)
			else finishBagJob(nil, nil, true)
			end
		else
			job.stage = "browse"
			ensureMarketScanHooks()
			local query = { searchString = job.item, sorts = PRICE_SORT, filters = {}, itemClassFilters = {} }
			job.browseToken, bagBrowseDispatch = attempt, query
			C_AuctionHouse.SendBrowseQuery(query)
			bagBrowseDispatch = nil
		end
	end, job)
end

local function restoreAHView()
	local ah = AuctionHouseFrame
	if not (ah and ah:IsShown() and ah.RefreshSearchResults and AuctionHouseSearchContext) then return end
	local buy = ah.CommoditiesBuyFrame
	if buy and buy:IsShown() and buy:GetItemID() then
		ah:RefreshSearchResults(AuctionHouseSearchContext.BuyCommodities, C_AuctionHouse.MakeItemKey(buy:GetItemID()))
	elseif ah.ItemBuyFrame and ah.ItemBuyFrame:IsShown() and ah.ItemBuyFrame.GetItemKey and ah.ItemBuyFrame:GetItemKey() then
		ah:RefreshSearchResults(AuctionHouseSearchContext.BuyItems, ah.ItemBuyFrame:GetItemKey())
	elseif ah.BrowseResultsFrame and ah.BrowseResultsFrame:IsShown() and ah.SearchBar then
		local text = ah.SearchBar.SearchBox:GetText()
		if text and text:match("%S") then ah.SearchBar:StartSearch() end
	end
end

nextBagJob = function(prevWasSniper)
	local job = table.remove(bagScan.queue, 1)
	if not job then
		if not prevWasSniper then restoreAHView() end
		return
	end
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		local cancelledSniper
		if job.isSniper and type(job.onResult) == "function" then
			cancelledSniper = { job }
		end
		for i = 1, #bagScan.queue do
			local qJob = bagScan.queue[i]
			if qJob and qJob.isSniper and type(qJob.onResult) == "function" then
				cancelledSniper = cancelledSniper or {}
				cancelledSniper[#cancelledSniper + 1] = qJob
			end
		end
		wipe(bagScan.queue)
		wipe(app.scanning)
		if cancelledSniper then
			for i = 1, #cancelledSniper do
				local cJob = cancelledSniper[i]
				pcall(cJob.onResult, { cancelled = true, itemID = cJob.itemID, itemKey = cJob.itemKey })
			end
		end
		if not job.isSniper then
			say(L.openAH)
			if app.refresh then app.refresh() end
		end
		return
	end
	bagScan.job = job
	job.economy = job.economy or ns.DetectActiveEconomy()
	if job.economy ~= ns.DetectActiveEconomy() then app.cancelOrderBookScan(); return end
	job.itemID = job.itemID or lookupID(job.item)
	if not job.isSniper and app.refresh then app.refresh() end
	sendBagJob(job)
end

local function scanBrowsed(addedBatch)
	local job = bagScan.job
	if not job or job.stage ~= "browse" or job.itemID or not job.browseToken or not job.answered then return end
	if job.economy ~= ns.DetectActiveEconomy() then app.cancelOrderBookScan(); return end
	local results, added = job.browseRows, tableValue(addedBatch)
	if results and added then
		for _, row in ipairs(added) do results[#results + 1] = row end
	else
		local snapshot = tableValue(C_AuctionHouse.GetBrowseResults())
		if snapshot and (not results or #snapshot >= #results) then
			results = {}
			for _, row in ipairs(snapshot) do results[#results + 1] = row end
		end
	end
	job.browseRows = results
	local full = C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults()
	full = readable(full) and full == true
	local wantedName = normalizedSearchName(job.item)
	local selectedKey, selectedID, unknownName
	local unknownItem = not results
	local incompleteItems = {}
	for _, result in ipairs(results or {}) do
		local key = tableValue(result) and tableValue(result.itemKey)
		local itemID = key and safeNumber(key.itemID)
		local _, copy = itemKeySignature(key)
		noteVariant(copy, job.economy)
		if not itemID or itemID <= 0 then
			unknownItem = true
		elseif not copy then
			incompleteItems[itemID] = true
		elseif not selectedKey then
			local info = C_AuctionHouse.GetItemKeyInfo and tableValue(C_AuctionHouse.GetItemKeyInfo(key))
			local name = info and info.itemName
			if not isItemSearchName(name) then
				unknownName = true
				name = ns.ItemName(itemID)
			end
			if normalizedSearchName(name) == wantedName then
				selectedKey, selectedID = key, itemID
			end
		end
	end
	if selectedKey then
		if ns.SellerStats then
			local observedKeys, activeVariants = {}, {}
			for _, result in ipairs(results) do
				local key = tableValue(result) and tableValue(result.itemKey)
				local signature, copy = itemKeySignature(key)
				if copy and copy.itemID == selectedID then
					observedKeys[signature] = copy
					local qty = safeNumber(result.totalQuantity)
					if not isBaseItemKey(copy) and qty and qty > 0 then activeVariants[signature] = true end
				end
			end
			ns.SellerStats.MergeBrowseKeys(job.economy, observedKeys, activeVariants)
			if unknownItem or incompleteItems[selectedID] or not full then
				ns.SellerStats.NoteIncompleteCoverage(selectedID, job.economy)
			end
		end
		job.itemID, job.itemKey, job.tries = selectedID, selectedKey, nil
		app.itemIDs[job.item] = selectedID
		sendBagJob(job)
	elseif full and not unknownItem and not unknownName and not next(incompleteItems) then
		finishBagJob(nil)
	elseif not full and C_AuctionHouse.RequestMoreBrowseResults then
		local count = results and #results or 0
		if job.morePending == count then return end
		job.morePending = count
		local token = job.browseToken
		if bagScan.timer then bagScan.timer:Cancel(); bagScan.timer = nil end
		whenBagScanReady(function()
			if not job.itemID and job.browseToken == token and job.morePending == count then
				armBagTimeout(job)
				C_AuctionHouse.RequestMoreBrowseResults()
			end
		end, job)
	end
end

local function scanCommodity(itemID)
	local job = bagScan.job
	if not job or job.stage ~= "search" or job.itemID ~= itemID or not job.received then return end
	if job.economy ~= ns.DetectActiveEconomy() then app.cancelOrderBookScan(); return end
	if ns.SellerStats then ns.SellerStats.Commodity(job.itemKey, job.economy); job.sellers = nil end
	local lots, marketQty, marketMinPrice = {}, 0, nil
	local rawRows = job.collectRawRows and {} or nil
	local num = C_AuctionHouse.GetNumCommoditySearchResults and safeNumber(C_AuctionHouse.GetNumCommoditySearchResults(itemID))
	if not num or not C_AuctionHouse.GetCommoditySearchResultInfo then finishBagJob(nil, nil, true); return end
	local valid = true
	for i = 1, num do
		local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
		local lot, readableLot, qty, price = readSearchLot(info, true)
		valid = valid and readableLot
		marketQty, marketMinPrice = addMarketLot(marketQty, marketMinPrice, qty, price, true)
		if lot then lots[#lots + 1] = lot end
		if rawRows and readableLot and price and price > 0 and qty and qty > 0 then
			rawRows[#rawRows + 1] = {
				unitPrice = price,
				quantity = qty,
				competitorQty = lot and lot.n or 0,
			}
		end
	end
	job.pagesFetched = (job.pagesFetched or 0) + 1
	local _, short = lotsPrice(lots, false, largestQty(job))
	local full = C_AuctionHouse.HasFullCommoditySearchResults and C_AuctionHouse.HasFullCommoditySearchResults(itemID)
	full = readable(full) and full == true
	local underPageCap = not job.maxPages or job.pagesFetched < job.maxPages
	if short and not full and underPageCap and C_AuctionHouse.RequestMoreCommoditySearchResults then
		if bagScan.timer then bagScan.timer:Cancel(); bagScan.timer = nil end
		whenBagScanReady(function()
			if bagScan.job == job then
				armBagTimeout(job)
				C_AuctionHouse.RequestMoreCommoditySearchResults(itemID)
			end
		end, job)
		return
	end
	finishBagJob(lots, false, nil, full and valid, marketMinPrice, marketQty, rawRows)
end

local function scanItems(itemKey)
	local job = bagScan.job
	if not job or job.stage ~= "search" then return end
	if job.economy ~= ns.DetectActiveEconomy() then app.cancelOrderBookScan(); return end
	local signature = itemKeySignature(itemKey)
	if not signature or signature ~= itemKeySignature(job.itemKey) then return end
	local lots, rows, valid, marketQty, marketMinPrice = {}, {}, true, 0, nil
	local rawRows = job.collectRawRows and {} or nil
	local hasSupply = false
	local num = C_AuctionHouse.GetNumItemSearchResults and safeNumber(C_AuctionHouse.GetNumItemSearchResults(itemKey))
	if not num or not C_AuctionHouse.GetItemSearchResultInfo then finishBagJob(nil, nil, true); return end
	for i = 1, num do
		local row = tableValue(C_AuctionHouse.GetItemSearchResultInfo(itemKey, i))
		rows[#rows + 1] = row or false
		local lot, readableLot, qty, price = readSearchLot(row, false)
		if not hasSupply then
			local rowQty = qty or (row and safeNumber(row.quantity))
			hasSupply = rowQty ~= nil and rowQty > 0
		end
		valid = valid and readableLot
		marketQty, marketMinPrice = addMarketLot(marketQty, marketMinPrice, qty, price, false)
		if lot then lots[#lots + 1] = lot end
		if rawRows and row then
			local aid = safeNumber(row.auctionID)
			local buyout = safeNumber(row.buyoutAmount)
			local rQty = safeNumber(row.quantity)
			local rLink = readable(row.itemLink) and type(row.itemLink) == "string" and row.itemLink or nil
			local owned = (readable(row.containsOwnerItem) and row.containsOwnerItem == true)
				or (readable(row.containsAccountItem) and row.containsAccountItem == true)
				or ((safeNumber(row.numOwnerItems) or 0) > 0)
			if aid and buyout and buyout > 0 then
				rawRows[#rawRows + 1] = {
					auctionID = aid,
					buyoutAmount = buyout,
					quantity = rQty or 1,
					itemLink = rLink,
					containsOwnerItem = owned,
				}
			end
		end
	end
	job.pagesFetched = (job.pagesFetched or 0) + 1
	local full = C_AuctionHouse.HasFullItemSearchResults and C_AuctionHouse.HasFullItemSearchResults(itemKey)
	full = readable(full) and full == true
	if hasSupply then noteVariant(job.itemKey, job.economy) end
	if job.sellers then ns.SellerStats.Observe(job.sellers, rows, full, hasSupply) end
	table.sort(lots, function(a, b) return a.price / a.n < b.price / b.n end)
	local _, short = lotsPrice(lots, true, largestQty(job))
	local underPageCap = not job.maxPages or job.pagesFetched < job.maxPages
	if (short or job.countSellers) and not full and underPageCap and C_AuctionHouse.RequestMoreItemSearchResults then
		if job.morePending and num <= job.morePending then return end
		job.morePending = num
		if bagScan.timer then bagScan.timer:Cancel(); bagScan.timer = nil end
		whenBagScanReady(function()
			if bagScan.job == job then
				armBagTimeout(job)
				C_AuctionHouse.RequestMoreItemSearchResults(job.itemKey)
			end
		end, job)
		return
	end
	finishBagJob(lots, true, nil, full and valid, marketMinPrice, marketQty, rawRows)
end

local function queueBagCrate(crate, counts)
	app.folded[crate.name] = nil
	for _, b in ipairs(crate.bundles) do
		local missing = math.max(0, b.count - (counts[b.name] or 0))
		if missing > 0 then
			local job
			for _, j in pairs(runBagJobs()) do
				if j.item == b.name then job = j end
			end
			if not job then
				job = { item = b.name, targets = {} }
				bagScan.queue[#bagScan.queue + 1] = job
			end
			local joined = false
			for _, target in ipairs(job.targets) do
				if target.crate == crate.name then target.qty, joined = missing, true end
			end
			if not joined then job.targets[#job.targets + 1] = { crate = crate.name, qty = missing } end
		end
	end
end

local function scanBagCrates(crates)
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		say(L.openAH)
		return
	end
	invalidatePendingSearch()
	app.cancelMarketScan(false)
	local counts = ownedCounts()
	for _, crate in ipairs(crates or bagCrates()) do queueBagCrate(crate, counts) end
	updateBagScanning()
	if app.refresh then app.refresh() end
	if not bagScan.job then nextBagJob() end
end

function app.cancelOrderBookScan()
	invalidatePendingSearch()
	if bagScan.timer then bagScan.timer:Cancel(); bagScan.timer = nil end
	if bagScan.job and bagScan.job.sellers and ns.SellerStats then
		ns.SellerStats.Publish(bagScan.job.sellers, "Item search was cancelled before completion.")
	end
	local cancelledSniper
	if bagScan.job and bagScan.job.isSniper and type(bagScan.job.onResult) == "function" then
		cancelledSniper = { bagScan.job }
	end
	for i = 1, #bagScan.queue do
		local qJob = bagScan.queue[i]
		if qJob and qJob.isSniper and type(qJob.onResult) == "function" then
			cancelledSniper = cancelledSniper or {}
			cancelledSniper[#cancelledSniper + 1] = qJob
		end
	end
	bagScan.job, bagScan.onReady = nil, nil
	wipe(bagScan.queue)
	wipe(app.scanning)
	app.lotScanTotal, app.lotScanDone = 0, 0
	if cancelledSniper then
		for i = 1, #cancelledSniper do
			local cJob = cancelledSniper[i]
			pcall(cJob.onResult, { cancelled = true, itemID = cJob.itemID, itemKey = cJob.itemKey })
		end
	end
	if app.refresh then app.refresh() end
	notifyScanProgress()
end

function app.scanOrderBookItems(itemIDList, maxUnitsPerItem, options)
	invalidatePendingSearch()
	if app.lotScanTotal > 0 then
		app.cancelOrderBookScan()
		say("Stopped Deep AH Lot Scan.")
		return
	end
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown() and C_AuctionHouse) then
		say("Open the Auction House to scan live multi-price order-book lots (Local Snapshot / saved AH stock counts are active right now).")
		return
	end
	app.cancelMarketScan(false)
	local countSellers = type(options) == "table" and options.sellers == true
	local queued = {}
	for _, job in pairs(runBagJobs()) do
		if job and job.itemID then
			local signature = itemKeySignature(job.itemKey or C_AuctionHouse.MakeItemKey(job.itemID))
			if signature then queued[signature] = job end
		end
	end
	local added = 0
	local economy = ns.DetectActiveEconomy()
	for _, value in ipairs(itemIDList or {}) do
		local id = safeNumber(value)
		local signature, copy
		if not id then signature, copy = itemKeySignature(value); id = copy and copy.itemID end
		if id and id > 0 and not (ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[id]) then
			local keys = copy and {copy} or countSellers and ns.SellerStats and ns.SellerStats.GetKeys(id, economy) or {}
			if #keys == 0 then keys = {C_AuctionHouse.MakeItemKey(id)} end
			for _, key in ipairs(keys) do
				local sig, fullKey = itemKeySignature(key)
				if sig and queued[sig] then
					if countSellers then queued[sig].countSellers = true end
				elseif sig then
					local job = {
						item = ns.ItemName(id), itemID = id, itemKey = fullKey, economy = economy,
						targets = {}, orderBookQty = maxUnitsPerItem or 400, isOrderBookScan = true,
						countSellers = countSellers,
						sellerOnly = #keys > 1 or (fullKey.itemLevel or 0) ~= 0 or (fullKey.itemSuffix or 0) ~= 0 or (fullKey.battlePetSpeciesID or 0) ~= 0,
					}
					queued[sig] = job
					bagScan.queue[#bagScan.queue + 1] = job
					added = added + 1
				end
			end
		end
	end
	if added == 0 then
		say("No candidate items to scan.")
		return
	end
	app.lotScanTotal = added
	app.lotScanDone = 0
	say(string.format("Deep scanning multi-price AH order-book lots for %d candidate items…", added))
	if app.refresh then app.refresh() end
	if not bagScan.job then nextBagJob() end
end

function MarketScan.ScanSellers(items)
	app.scanOrderBookItems(items, 1, {sellers=true})
end

function MarketScan.CancelSniperQueue()
	for i = #bagScan.queue, 1, -1 do
		if bagScan.queue[i] and bagScan.queue[i].sniperKind == "queue" then
			table.remove(bagScan.queue, i)
		end
	end
	if bagScan.job and bagScan.job.sniperKind == "queue" then
		if bagScan.timer then bagScan.timer:Cancel(); bagScan.timer = nil end
		bagScan.job, bagScan.onReady = nil, nil
		if #bagScan.queue > 0 then
			nextBagJob(true)
		end
	end
end

function MarketScan.StartSniperQueue(items, onResult, opts)
	local ahFrame = readable(AuctionHouseFrame) and AuctionHouseFrame or nil
	local ahOpen = ahFrame and type(ahFrame.IsShown) == "function" and readable(ahFrame:IsShown()) and ahFrame:IsShown() == true
	if not (ahOpen and readable(C_AuctionHouse) and type(C_AuctionHouse) == "table") then
		return false, "ah_closed"
	end
	MarketScan.CancelSniperQueue()
	local maxPages = (tableValue(opts) and safeNumber(opts.maxPages)) or 1
	if maxPages < 1 then maxPages = 1 end
	local economy = ns.DetectActiveEconomy()
	local added = 0
	for _, value in ipairs(tableValue(items) or {}) do
		local id = safeNumber(value)
		local _, copy
		if not id then _, copy = itemKeySignature(value); id = copy and copy.itemID end
		if id and id > 0 then
			local key = copy or (C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(id)) or { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
			local _, fullKey = itemKeySignature(key)
			if fullKey then
				bagScan.queue[#bagScan.queue + 1] = {
					item = ns.ItemName(id),
					itemID = id,
					itemKey = fullKey,
					economy = economy,
					targets = {},
					orderBookQty = math.huge,
					maxPages = maxPages,
					collectRawRows = true,
					isSniper = true,
					sniperKind = "queue",
					onResult = onResult,
				}
				added = added + 1
			end
		end
	end
	if added == 0 then return false, "empty" end
	if not bagScan.job then nextBagJob(true) end
	return true, added
end

function MarketScan.CheckItemLive(itemIDOrKey, onResult)
	local ahFrame = readable(AuctionHouseFrame) and AuctionHouseFrame or nil
	local ahOpen = ahFrame and type(ahFrame.IsShown) == "function" and readable(ahFrame:IsShown()) and ahFrame:IsShown() == true
	if not (ahOpen and readable(C_AuctionHouse) and type(C_AuctionHouse) == "table") then
		return false, "ah_closed"
	end
	local id = safeNumber(itemIDOrKey)
	local _, copy
	if not id then _, copy = itemKeySignature(itemIDOrKey); id = copy and copy.itemID end
	if not id or id <= 0 then return false, "invalid_item" end
	local key = copy or (C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(id)) or { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
	local _, fullKey = itemKeySignature(key)
	if not fullKey then return false, "invalid_key" end
	local job = {
		item = ns.ItemName(id),
		itemID = id,
		itemKey = fullKey,
		economy = ns.DetectActiveEconomy(),
		targets = {},
		orderBookQty = math.huge,
		maxPages = 1,
		collectRawRows = true,
		isSniper = true,
		sniperKind = "check",
		onResult = onResult,
	}
	table.insert(bagScan.queue, 1, job)
	if not bagScan.job then nextBagJob(true) end
	return true
end


function MarketScan.GetState()
	local economy = marketScan.active and marketScan.economy or ns.DetectActiveEconomy()
	local prices = MerchantMasterDB and MerchantMasterDB.ahPrices and MerchantMasterDB.ahPrices[economy]
	return {
		active = marketScan.active, economy = economy,
		completedAt = prices and prices._scannedAt or nil,
		partial = marketScan.partial, generation = marketScan.generation,
		matchedCount = marketScan.matchedCount or 0, page = marketScan.page,
		seen = marketScan.seen or 0, total = marketScan.total or 0,
	}
end

function MarketScan.GetBagStatus()
	return bagScan.job, #bagScan.queue
end

local function handleSearchResult(value, commodity, received)
	local itemID
	if commodity then
		itemID = safeNumber(value)
	elseif tableValue(value) then
		itemID = safeNumber(value.itemID)
	end
	local job = bagScan.job
	if job and job.stage == "search" then
		local unkeyed = commodity and readable(value) and value == nil
		if itemID == job.itemID or unkeyed then
			if job.isCommodity == nil then job.isCommodity = commodityKind(job.itemKey) end
			if job.isCommodity ~= nil and commodity ~= job.isCommodity then return end
			if commodity then
				if not isBaseItemKey(job.itemKey) or (unkeyed and job.isCommodity ~= true) then return end
				if received or unkeyed then job.received = true end
				scanCommodity(job.itemID)
				return
			end
			local signature = itemKeySignature(value)
			if signature and signature == itemKeySignature(job.itemKey) then
				scanItems(value)
				return
			end
		end
	end
	recordCompletedSearch(value, commodity, itemID)
end

---------------------------------------------------------------------------------------------------
-- Unified 4-Stage Order & Crafting Task Flow Engine (AH -> Vendor -> Collect Owned -> Craft Tasks)
-- Zero-taint compliance: never invokes protected APIs; all vendor/bank/mail/craft calls execute
-- strictly from user hardware click handlers. CartBuyer remains a 100% backward-compatible facade.

local cartBuyer = {
	title = "Shopping List",
	items = {},
	activeIndex = 1,
	active = false,
	waitingForAH = false,
	spentCopper = 0,
	selectedDestKey = nil,
	pendingExternal = nil,
	pendingExternalBid = nil,
	directBuy = nil,
	notice = nil,
	noticeKind = "info",
	onUpdate = nil,
}

local orderFlow = {
	title = "Shopping List",
	cartSig = nil,
	activeStage = "ah",
	active = false,
	selectedDestKey = nil,
	stageCompletePrompt = nil,
	notice = nil,
	noticeKind = "info",
	onUpdate = nil,
	ownershipRev = 0,
	destCache = nil,
	env = {
		atAH = false,
		atVendor = false,
		vendorName = nil,
		_merchantEventOpen = false,
		_merchantEventFrame = nil,
		_merchantFrameSeenShown = false,
		_merchantAwaitFrameHide = false,
		_vendorAutoSwitched = false,
		atBank = false,
		_bankEventOpen = false,
		_bankEventFrame = nil,
		_bankFrameSeenShown = false,
		_bankAwaitFrameHide = false,
		_bankAutoSwitched = false,
		atMail = false,
		_mailEventOpen = false,
		_mailEventFrame = nil,
		_mailFrameSeenShown = false,
		_mailAwaitFrameHide = false,
		_mailAutoSwitched = false,
		openProfKey = nil,
		openProfFrame = nil,
	},
	liveVendorSlots = {},
	liveVendorSlotsByName = {},
	liveBankSlots = {},
	liveMailSlots = {},
	stages = {
		ah = {
			items = cartBuyer.items,
			activeIndex = 1,
			waitingForAH = true,
			spentCopper = 0,
			pendingExternal = nil,
			pendingExternalBid = nil,
			directBuy = nil,
			selfBidInFlight = false,
			directBuySerial = 0,
		},
		vendor = {
			items = {},
			activeIndex = 1,
			spentCopper = 0,
			baselineBagQty = {},
			pendingBuy = nil,
		},
		collect = {
			items = {},
			activeIndex = 1,
			baselineBagQty = {},
			pendingTake = nil,
			collectAll = nil,
		},
		craft = {
			tasks = {},
			activeIndex = 1,
			pendingCraft = nil,
			activeCast = nil,
			craftingBatch = nil,
		},
		sell = {
			items = {},
			activeIndex = 1,
			duration = 2,
			undercutMode = "match",
			undercutPct = 1,
			pendingPost = nil,
			pendingSearch = nil,
			pendingKeyPrime = nil,
			pendingVendorSell = nil,
			warningConfirm = nil,
			lastItemInfo = nil,
			lastItemListings = nil,
			postAllActive = false,
			totalEarnedCopper = 0,
			throttleBlockedAt = nil,
			postSerial = 0,
			searchSerial = 0,
		},
	},
}

local OrderFlow = {}
MarketScan.OrderFlow = OrderFlow
app.orderFlow = OrderFlow

local CartBuyer = {}
MarketScan.CartBuyer = CartBuyer
app.cartBuyer = CartBuyer

local handleCartBuyerEvent

do
	local STAGE_META = {
		{ key = "ah",      index = 1, label = "1. AH",      shortLabel = "AH" },
		{ key = "collect", index = 2, label = "2. Collect", shortLabel = "Collect" },
		{ key = "vendor",  index = 3, label = "3. Vendor",  shortLabel = "Vendor" },
		{ key = "craft",   index = 4, label = "4. Craft",   shortLabel = "Craft" },
	}
	local STAGE_INDEX_BY_KEY = { ah = 1, collect = 2, vendor = 3, craft = 4 }
	local STAGE_LABEL_BY_KEY = { ah = "1. AH", collect = "2. Collect", vendor = "3. Vendor", craft = "4. Craft" }

	local PROF_META_MAP = {
		alchemy        = { key = "alchemy",        name = "Alchemy",        badge = "ALCH" },
		blacksmithing  = { key = "blacksmithing",  name = "Blacksmithing",  badge = "BS" },
		enchanting     = { key = "enchanting",     name = "Enchanting",     badge = "ENCH" },
		engineering    = { key = "engineering",    name = "Engineering",    badge = "ENG" },
		leatherworking = { key = "leatherworking", name = "Leatherworking", badge = "LW" },
		tailoring      = { key = "tailoring",      name = "Tailoring",      badge = "TAIL" },
		mining         = { key = "mining",         name = "Mining",         badge = "MINE" },
		cooking        = { key = "cooking",        name = "Cooking",        badge = "COOK" },
		firstaid       = { key = "firstaid",       name = "First Aid",      badge = "FA" },
		poisons        = { key = "poisons",        name = "Poisons",        badge = "POIS" },
	}
	local PROF_NAME_TO_KEY = {
		["alchemy"] = "alchemy",
		["alch"] = "alchemy",
		["blacksmithing"] = "blacksmithing",
		["bs"] = "blacksmithing",
		["enchanting"] = "enchanting",
		["ench"] = "enchanting",
		["engineering"] = "engineering",
		["eng"] = "engineering",
		["leatherworking"] = "leatherworking",
		["lw"] = "leatherworking",
		["tailoring"] = "tailoring",
		["tailor"] = "tailoring",
		["mining"] = "mining",
		["smelting"] = "mining",
		["cooking"] = "cooking",
		["cook"] = "cooking",
		["first aid"] = "firstaid",
		["firstaid"] = "firstaid",
		["fa"] = "firstaid",
		["poisons"] = "poisons",
		["poison"] = "poisons",
	}

	local function matchProfKeyByName(raw)
		if not readable(raw) or type(raw) ~= "string" then return nil end
		local norm = raw:match("^%s*(.-)%s*$"):lower()
		if norm == "" then return nil end
		if PROF_NAME_TO_KEY[norm] then return PROF_NAME_TO_KEY[norm] end
		for _, p in ipairs(ns.PROFESSIONS or {}) do
			if p.key and p.key ~= "all" and p.key ~= "mine_profs" then
				if (p.key:lower() == norm)
					or (p.label and p.label:lower() == norm)
					or (p.full and p.full:lower() == norm) then
					return p.key
				end
			end
		end
		return nil
	end

	local function resolveProfMeta(profKeyOrName)
		local pk = matchProfKeyByName(profKeyOrName)
		if pk and PROF_META_MAP[pk] then
			local m = PROF_META_MAP[pk]
			return m.key, m.name, m.badge
		end
		local fallbackKey = (type(profKeyOrName) == "string" and profKeyOrName ~= "") and profKeyOrName:lower() or "crafting"
		local fallbackName = (type(profKeyOrName) == "string" and profKeyOrName ~= "") and profKeyOrName or "Crafting"
		local fallbackBadge = fallbackKey:sub(1, 4):upper()
		return fallbackKey, fallbackName, fallbackBadge
	end

	local function syncCartBuyerMirror()
		local ah = orderFlow.stages.ah
		cartBuyer.title = orderFlow.title
		cartBuyer.items = ah.items
		cartBuyer.activeIndex = ah.activeIndex
		cartBuyer.active = orderFlow.active
		cartBuyer.waitingForAH = ah.waitingForAH
		cartBuyer.spentCopper = ah.spentCopper
		cartBuyer.selectedDestKey = orderFlow.selectedDestKey
		cartBuyer.pendingExternal = ah.pendingExternal
		cartBuyer.pendingExternalBid = ah.pendingExternalBid
		cartBuyer.directBuy = ah.directBuy
		cartBuyer.notice = orderFlow.notice
		cartBuyer.noticeKind = orderFlow.noticeKind
	end

	local function updateStageCompletePrompt()
		local stKey = orderFlow.activeStage or "ah"
		local stats = OrderFlow.GetStageStats(stKey)
		if stats and not stats.empty and stats.complete then
			local nextKey = OrderFlow.GetNextIncompleteStage(stKey)
			if nextKey then
				orderFlow.stageCompletePrompt = {
					from = stKey,
					nextStage = nextKey,
					label = "Next: " .. (STAGE_LABEL_BY_KEY[nextKey] or nextKey) .. " ->",
				}
				return
			end
			if OrderFlow.IsPipelineComplete and OrderFlow.IsPipelineComplete() then
				orderFlow.stageCompletePrompt = {
					from = stKey,
					action = "clear_queue",
					label = "Clear Queue ->",
				}
				return
			end
		end
		orderFlow.stageCompletePrompt = nil
	end

	local function bumpOwnershipRev()
		orderFlow.ownershipRev = (orderFlow.ownershipRev or 0) + 1
	end

	local function resolveTaskCastTimeMs(task)
		if type(task) ~= "table" then return 2000 end
		local ms = nil
		if ns.GetRecipeCastTimeMs then
			local ok, val = pcall(ns.GetRecipeCastTimeMs, task.spellID, task)
			if ok and safeNumber(val) then ms = val end
		end
		if ms == nil then
			ms = safeNumber(task.castTimeMs) or 2000
		end
		return math.max(0, ms)
	end

	local PERSIST_SKIP_KEYS = {
		inStockHere = true,
		merchantSlot = true,
		maxStack = true,
		stackCount = true,
		numAvailable = true,
		hasExtendedCost = true,
		availableHere = true,
		liveUnit = true,
		liveTotal = true,
		priceDeltaPct = true,
		priceDiffCopper = true,
		priceDiffPct = true,
		priceDiffTotalCopper = true,
		priceAlert = true,
		buyCapMarginCopper = true,
		overBuyCap = true,
		liveCheckedAt = true,
		liveIsOwn = true,
		currentListings = true,
		listingsScanned = true,
		priceThreshold = true,
		existingValue = true,
		inBags = true,
	}

	local function clonePersistValue(v, depth)
		depth = depth or 0
		if depth > 8 then return nil end
		local tp = type(v)
		if tp == "string" or tp == "number" or tp == "boolean" then
			return v
		elseif tp ~= "table" then
			return nil
		end
		local out = {}
		for k, val in pairs(v) do
			if (type(k) == "string" or type(k) == "number") and not PERSIST_SKIP_KEYS[k] then
				local cv = clonePersistValue(val, depth + 1)
				if cv ~= nil then
					out[k] = cv
				end
			end
		end
		return out
	end

	local function clonePersistArray(list, normalizeFn)
		local out = {}
		for _, entry in ipairs(type(list) == "table" and list or {}) do
			if type(entry) == "table" then
				local c = clonePersistValue(entry, 0)
				if type(c) == "table" then
					if normalizeFn then normalizeFn(c) end
					out[#out + 1] = c
				end
			end
		end
		return out
	end

	function OrderFlow.SerializeState()
		local ah = orderFlow.stages.ah or {}
		local col = orderFlow.stages.collect or {}
		local ven = orderFlow.stages.vendor or {}
		local cr = orderFlow.stages.craft or {}
		local sl = orderFlow.stages.sell or {}
		local nTotal = #(ah.items or {}) + #(col.items or {}) + #(ven.items or {}) + #(cr.tasks or {}) + #(sl.items or {})
		if nTotal <= 0 then
			return nil
		end
		return {
			version = 2,
			title = orderFlow.title or "Shopping List",
			cartSig = (type(orderFlow.cartSig) == "string" and orderFlow.cartSig ~= "") and orderFlow.cartSig or nil,
			activeStage = (orderFlow.activeStage and STAGE_INDEX_BY_KEY[orderFlow.activeStage]) and orderFlow.activeStage or "ah",
			selectedDestKey = (type(orderFlow.selectedDestKey) == "string" and orderFlow.selectedDestKey ~= "") and orderFlow.selectedDestKey or nil,
			stages = {
				ah = {
					items = clonePersistArray(ah.items, function(c)
						if c.status == "active" or c.status == "confirming" then c.status = "pending" end
					end),
					activeIndex = tonumber(ah.activeIndex) or 1,
					spentCopper = tonumber(ah.spentCopper) or 0,
				},
				collect = {
					items = clonePersistArray(col.items),
					activeIndex = tonumber(col.activeIndex) or 1,
				},
				vendor = {
					items = clonePersistArray(ven.items),
					activeIndex = tonumber(ven.activeIndex) or 1,
					spentCopper = tonumber(ven.spentCopper) or 0,
				},
				craft = {
					tasks = clonePersistArray(cr.tasks),
					activeIndex = tonumber(cr.activeIndex) or 1,
				},
				sell = {
					duration = (sl.duration == 1 or sl.duration == 2 or sl.duration == 3) and sl.duration or 2,
					undercutMode = (sl.undercutMode == "match" or sl.undercutMode == "1c" or sl.undercutMode == "1s" or sl.undercutMode == "pct") and sl.undercutMode or "match",
					undercutPct = tonumber(sl.undercutPct) or 1,
					items = clonePersistArray(sl.items),
					activeIndex = tonumber(sl.activeIndex) or 1,
					totalEarnedCopper = tonumber(sl.totalEarnedCopper) or 0,
				},
			},
		}
	end

	function OrderFlow.SaveState()
		if type(_G.MerchantMasterDB) ~= "table" then return false end
		_G.MerchantMasterDB.orderFlowState = OrderFlow.SerializeState()
		return true
	end

	function OrderFlow.HasAnyItems()
		local st = orderFlow.stages
		return (#(st.ah.items or {}) + #(st.collect.items or {}) + #(st.vendor.items or {}) + #(st.craft.tasks or {})) > 0
	end

	function OrderFlow.HasSellItems()
		local sl = orderFlow.stages and orderFlow.stages.sell
		return sl ~= nil and #(sl.items or {}) > 0
	end

	function OrderFlow.IsPipelineComplete()
		if not OrderFlow.HasAnyItems() then return false end
		for _, meta in ipairs(STAGE_META) do
			local stats = OrderFlow.GetStageStats(meta.key)
			if stats and not stats.empty then
				if meta.key == "collect" then
					if (stats.actionableRemaining or 0) > 0 then return false end
				elseif not stats.complete then
					return false
				end
			end
		end
		return true
	end

	function OrderFlow.IsCraftCycleComplete()
		if OrderFlow.IsPipelineComplete() then return true end
		local crStats = OrderFlow.GetStageStats("craft")
		local ahStats = OrderFlow.GetStageStats("ah")
		local venStats = OrderFlow.GetStageStats("vendor")
		return crStats ~= nil and not crStats.empty and crStats.complete == true
			and (ahStats == nil or ahStats.complete == true)
			and (venStats == nil or venStats.complete == true)
	end

	function OrderFlow.HasActiveSessionForSig(sig)
		if type(sig) ~= "string" or sig == "" then return false end
		if not OrderFlow.HasAnyItems() then return false end
		if OrderFlow.IsCraftCycleComplete() then return false end
		return orderFlow.cartSig == sig
	end

	local function notifyOrderFlow(skipPersist)
		orderFlow.destCache = nil
		updateStageCompletePrompt()
		syncCartBuyerMirror()
		if not skipPersist and OrderFlow.SaveState then
			OrderFlow.SaveState()
		end
		local fn1 = orderFlow.onUpdate
		local fn2 = cartBuyer.onUpdate
		if type(fn1) == "function" then
			pcall(fn1, orderFlow)
		end
		if type(fn2) == "function" and fn2 ~= fn1 then
			pcall(fn2, cartBuyer)
		end
		if ns.AHSellTab and type(ns.AHSellTab.OnStateUpdated) == "function" then
			pcall(ns.AHSellTab.OnStateUpdated, orderFlow)
		end
	end

	local function itemDestQty(item, destKey)
		if not (item and destKey and destKey ~= "") then return nil end
		local prov = item.provenance
		if type(prov) ~= "table" then return nil end
		local matched, sumQty = false, 0
		for _, p in ipairs(prov) do
			if p and p.targetName == destKey then
				matched = true
				sumQty = sumQty + (tonumber(p.qty) or 0)
			end
		end
		if not matched then return nil end
		return (sumQty > 0) and sumQty or (item.needed or item.neededCrafts or 1)
	end

	local function cloneProvenanceList(prov, scaleNum, scaleDen)
		local out = {}
		if type(prov) ~= "table" then return out end
		for _, p in ipairs(prov) do
			if type(p) == "table" then
				local q = tonumber(p.qty) or 1
				if scaleNum and scaleDen and scaleDen > 0 and scaleNum ~= scaleDen then
					q = math.max(1, math.floor((q * scaleNum / scaleDen) + 0.5))
				end
				out[#out + 1] = {
					qty = q,
					subCraftName = p.subCraftName,
					subCraftItemID = p.subCraftItemID,
					subCraftProf = p.subCraftProf,
					targetName = p.targetName,
					targetItemID = p.targetItemID,
					sourceKind = p.sourceKind,
					sourceLabel = p.sourceLabel,
				}
			end
		end
		return out
	end

	local function getContainerNumSlotsSafe(bag)
		if C_Container and C_Container.GetContainerNumSlots then
			local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
			if ok and safeNumber(n) then return n end
		end
		if GetContainerNumSlots then
			local ok, n = pcall(GetContainerNumSlots, bag)
			if ok and safeNumber(n) then return n end
		end
		return 0
	end

	local function getContainerSlotInfoSafe(bag, slot)
		if C_Container and C_Container.GetContainerItemInfo then
			local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
			if ok and tableValue(info) then
				local id = safeNumber(info.itemID)
				if (not id or id <= 0) and type(info.hyperlink) == "string" then
					id = tonumber(info.hyperlink:match("item:(%d+)"))
				end
				local cnt = safeNumber(info.stackCount) or 1
				local locked = (readable(info.isLocked) and info.isLocked == true)
				return id, cnt, locked
			end
		end
		if C_Container and C_Container.GetContainerItemID then
			local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
			if ok and safeNumber(id) and id > 0 then
				return id, 1, false
			end
		end
		if GetContainerItemInfo then
			local ok, _, cnt, locked, _, _, _, link, _, _, id = pcall(GetContainerItemInfo, bag, slot)
			if ok then
				id = safeNumber(id)
				if (not id or id <= 0) and type(link) == "string" then
					id = tonumber(link:match("item:(%d+)"))
				end
				if id and id > 0 then
					return id, safeNumber(cnt) or 1, locked == true
				end
			end
		end
		return nil, 0, false
	end

	local function getBagContainerList()
		if type(app.getBagContainers) == "function" then
			local ok, list = pcall(app.getBagContainers)
			if ok and type(list) == "table" and #list > 0 then
				return list
			end
		end
		local bags = {}
		local maxBag = safeNumber(NUM_BAG_SLOTS) or 4
		for b = 0, maxBag do
			bags[#bags + 1] = b
		end
		local enumIdx = _G.Enum and _G.Enum.BagIndex
		local reagentBag = enumIdx and safeNumber(enumIdx.ReagentBag)
		local enumBankBag1 = enumIdx and safeNumber(enumIdx.BankBag_1)
		local numTotal = safeNumber(_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS) or 0
		local hasCharTabs = enumIdx and safeNumber(enumIdx.CharacterBankTab_1) ~= nil
		if reagentBag and reagentBag > maxBag and (not enumBankBag1 or reagentBag ~= enumBankBag1) then
			if numTotal > maxBag or hasCharTabs or getContainerNumSlotsSafe(reagentBag) > 0 then
				bags[#bags + 1] = reagentBag
			end
		end
		return bags
	end

	local function getBankContainerList()
		if type(app.getBankContainers) == "function" then
			local ok, list = pcall(app.getBankContainers)
			if ok and type(list) == "table" and #list > 0 then
				return list
			end
		end
		local out, seen = {}, {}
		local function add(id)
			if type(id) == "number" and not seen[id] then
				seen[id] = true
				out[#out + 1] = id
			end
		end
		local numBags = safeNumber(NUM_BAG_SLOTS) or 4
		local numTotal = safeNumber(_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS) or 0
		local enumIdx = _G.Enum and _G.Enum.BagIndex
		local reagentBag = enumIdx and safeNumber(enumIdx.ReagentBag)
		local enumBankBag1 = enumIdx and safeNumber(enumIdx.BankBag_1)
		local hasCharTabs = enumIdx and safeNumber(enumIdx.CharacterBankTab_1) ~= nil
		local hasReagentBag = reagentBag ~= nil and reagentBag > numBags and (not enumBankBag1 or reagentBag ~= enumBankBag1)
			and (numTotal > numBags or hasCharTabs)
		if hasCharTabs then
			local bRoot = enumIdx and safeNumber(enumIdx.Bank, true)
			if bRoot and bRoot ~= reagentBag then add(bRoot) end
			for ti = 1, 9 do
				local tid = enumIdx and safeNumber(enumIdx["CharacterBankTab_" .. ti])
				if tid and tid ~= reagentBag then add(tid) end
			end
			return out
		end
		add(safeNumber(BANK_CONTAINER, true) or -1)
		add(safeNumber(REAGENTBANK_CONTAINER, true) or -3)
		local firstBankBag = enumBankBag1 or (hasReagentBag and (reagentBag + 1) or (numBags + 1))
		for b = firstBankBag, 16 do
			if not (hasReagentBag and b == reagentBag) then
				add(b)
			end
		end
		return out
	end

	local function getLiveBagCount(itemID)
		itemID = safeNumber(itemID)
		if not itemID or itemID <= 0 then return 0 end
		if type(app.getBagCountByID) == "function" then
			local ok, qty = pcall(app.getBagCountByID, itemID)
			if ok and safeNumber(qty) then return math.max(0, math.floor(qty)) end
		end
		local total = 0
		for _, b in ipairs(getBagContainerList()) do
			local numSlots = getContainerNumSlotsSafe(b)
			for s = 1, numSlots do
				local sid, cnt = getContainerSlotInfoSafe(b, s)
				if sid == itemID and cnt and cnt > 0 then
					total = total + cnt
				end
			end
		end
		return total
	end

	local function createSellBagLocation(bag, slot)
		local il = _G.ItemLocation
		if (type(il) == "table" or type(il) == "userdata") and type(il.CreateFromBagAndSlot) == "function" then
			local ok, loc = pcall(il.CreateFromBagAndSlot, il, bag, slot)
			if ok and loc ~= nil then return loc end
		end
		return { bagID = bag, slotIndex = slot }
	end

	local function isSellSlotBound(loc, info)
		if tableValue(info) and readable(info.isBound) and info.isBound == true then
			return true
		end
		local ci = _G.C_Item
		if ci and type(ci.IsBound) == "function" and loc ~= nil then
			local okB, bnd = pcall(ci.IsBound, loc)
			if okB and readable(bnd) and bnd == true then
				return true
			end
		end
		return false
	end

	local function getSellableBagCount(itemID, forVendor, expectedLink)
		itemID = safeNumber(itemID)
		if not itemID or itemID <= 0 then return 0 end
		local ci = _G.C_Item
		local ah = _G.C_AuctionHouse
		local total = 0
		local hasCInfo = (C_Container and type(C_Container.GetContainerItemInfo) == "function")
		for _, bag in ipairs(getBagContainerList()) do
			local slots = getContainerNumSlotsSafe(bag)
			for slot = 1, slots do
				local sid, cnt, locked, info = nil, 0, false, nil
				if hasCInfo then
					local okI, rawInfo = pcall(C_Container.GetContainerItemInfo, bag, slot)
					if okI and tableValue(rawInfo) then
						info = rawInfo
						sid = safeNumber(rawInfo.itemID)
						if (not sid or sid <= 0) and readable(rawInfo.hyperlink) and type(rawInfo.hyperlink) == "string" then
							sid = tonumber(rawInfo.hyperlink:match("item:(%d+)"))
						end
						cnt = safeNumber(rawInfo.stackCount) or 1
						locked = (readable(rawInfo.isLocked) and rawInfo.isLocked == true)
					end
				else
					sid, cnt, locked = getContainerSlotInfoSafe(bag, slot)
				end
				if sid == itemID and not locked and cnt and cnt > 0 then
					local slotLink = (info and readable(info.hyperlink) and type(info.hyperlink) == "string") and info.hyperlink or nil
					local linkOk = (not expectedLink) or expectedLink == "" or (slotLink == nil) or (slotLink == expectedLink)
					if linkOk then
						local loc = createSellBagLocation(bag, slot)
						local exists = true
						if ci and type(ci.DoesItemExist) == "function" then
							local okE, ex = pcall(ci.DoesItemExist, loc)
							exists = (okE and readable(ex) and ex == true)
						end
						if exists then
							if forVendor then
								total = total + cnt
							elseif not isSellSlotBound(loc, info) then
								local sellable = true
								if ah and type(ah.IsSellItemValid) == "function" then
									local okV, v = pcall(ah.IsSellItemValid, loc, false)
									if okV and readable(v) and v == false then sellable = false end
								end
								if sellable then
									total = total + cnt
								end
							end
						end
					end
				end
			end
		end
		return total
	end

	local function defaultOwnershipProvider(itemID, name)
		local bags = getLiveBagCount(itemID)
		local bank, mail = 0, 0
		local db = tableValue(MerchantMasterDB)
		local ch = tableValue(app.char)
		if ch and type(name) == "string" and name ~= "" then
			if (not db or db.includeBank ~= false) and tableValue(ch.bank) then
				bank = math.max(0, safeNumber(ch.bank[name]) or 0)
			end
			if (not db or db.includeMail ~= false) and tableValue(ch.mail) then
				mail = math.max(0, safeNumber(ch.mail[name]) or 0)
			end
		end
		return { bags = bags, bank = bank, mail = mail, alts = {} }
	end

	local vendorPinIndex = nil
	local function getVendorPinIndex()
		if vendorPinIndex then return vendorPinIndex end
		vendorPinIndex = {}
		if type(ns.NPC_PINS) ~= "table" then return vendorPinIndex end
		for npcID, npc in pairs(ns.NPC_PINS) do
			if type(npc) == "table" and npc.kind == "vendor" and type(npc.recipeKeys) == "table" then
				local spawn = type(npc.spawns) == "table" and npc.spawns[1] or nil
				local rec = {
					npcID = safeNumber(npcID),
					name = npc.name,
					faction = npc.faction or "AH",
					uiMapID = spawn and safeNumber(spawn.uiMapID) or nil,
				}
				for _, rk in ipairs(npc.recipeKeys) do
					if type(rk) == "string" then
						local iid = tonumber(rk:match(":i:(%d+)$"))
						if iid and iid > 0 then
							vendorPinIndex[iid] = vendorPinIndex[iid] or {}
							vendorPinIndex[iid][#vendorPinIndex[iid] + 1] = rec
						end
					end
				end
			end
		end
		return vendorPinIndex
	end

	function OrderFlow.LookupVendorHint(itemID, playerFaction)
		itemID = safeNumber(itemID)
		local fCode = nil
		local rawFac = playerFaction or (UnitFactionGroup and UnitFactionGroup("player"))
		if rawFac == "Alliance" or rawFac == "A" then
			fCode = "A"
		elseif rawFac == "Horde" or rawFac == "H" then
			fCode = "H"
		end
		if itemID and itemID > 0 then
			local idx = getVendorPinIndex()
			local matches = idx[itemID]
			if type(matches) == "table" and #matches > 0 then
				local best = nil
				for _, rec in ipairs(matches) do
					if not fCode or rec.faction == "AH" or rec.faction == fCode then
						best = rec
						break
					end
				end
				best = best or matches[1]
				if best and type(best.name) == "string" and best.name ~= "" then
					local zone = nil
					if best.uiMapID and C_Map and C_Map.GetMapInfo then
						local ok, minfo = pcall(C_Map.GetMapInfo, best.uiMapID)
						if ok and tableValue(minfo) and type(minfo.name) == "string" and minfo.name ~= "" then
							zone = minfo.name
						end
					end
					local label = zone and (best.name .. " (" .. zone .. ")") or best.name
					return label, best.npcID
				end
			end
			local db = tableValue(MerchantMasterDB)
			local liveEntry = db and tableValue(db.liveVendorBuy) and db.liveVendorBuy[itemID]
			if tableValue(liveEntry) then
				local vn = liveEntry.vendorName or liveEntry.npcName
				if type(vn) == "string" and vn ~= "" then
					return vn, safeNumber(liveEntry.npcID)
				end
			end
			if ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[itemID] ~= nil then
				return "Trade Goods Vendor", nil
			end
		end
		return "Trade Goods Vendor", nil
	end

	local function isFrameShownSafe(frame)
		if not frame or type(frame) ~= "table" then return false end
		local fn = frame.IsShown
		if type(fn) ~= "function" then return false end
		local ok, shown = pcall(fn, frame)
		return (ok and readable(shown) and shown) and true or false
	end

	local function readLiveVendorName()
		if type(UnitName) == "function" then
			local ok, npcName = pcall(UnitName, "npc")
			if ok and readable(npcName) and type(npcName) == "string" and npcName ~= "" then
				return npcName
			end
		end
		if MerchantNameText and type(MerchantNameText.GetText) == "function" then
			local ok, npcName = pcall(MerchantNameText.GetText, MerchantNameText)
			if ok and readable(npcName) and type(npcName) == "string" and npcName ~= "" then
				return npcName
			end
		end
		return nil
	end

	local function isLiveStationOpen(frame, eventOpenKey, eventFrameKey, seenShownKey, awaitHideKey)
		local env = orderFlow.env
		local frameShown = isFrameShownSafe(frame)
		if frameShown then
			if env[awaitHideKey] then
				return false
			end
			env[seenShownKey] = true
			return true
		end
		env[awaitHideKey] = false
		if env[eventOpenKey] == true then
			if frame == nil or (env[eventFrameKey] == frame and not env[seenShownKey]) then
				return true
			end
			env[eventOpenKey] = false
			env[eventFrameKey] = nil
			env[seenShownKey] = false
		end
		return false
	end

	local function isLiveMerchantOpen()
		return isLiveStationOpen(_G.MerchantFrame, "_merchantEventOpen", "_merchantEventFrame", "_merchantFrameSeenShown", "_merchantAwaitFrameHide")
	end

	local function isLiveBankOpen()
		return isLiveStationOpen(_G.BankFrame, "_bankEventOpen", "_bankEventFrame", "_bankFrameSeenShown", "_bankAwaitFrameHide")
	end

	local function isLiveMailOpen()
		return isLiveStationOpen(_G.MailFrame, "_mailEventOpen", "_mailEventFrame", "_mailFrameSeenShown", "_mailAwaitFrameHide")
	end

	local function hasCollectItemsOfSource(src)
		for _, it in ipairs(orderFlow.stages.collect.items or {}) do
			if it and it.source == src then return true end
		end
		return false
	end

	local function syncLiveEnvironmentInternal()
		orderFlow.env.atAH = atAH() and true or false
		orderFlow.stages.ah.waitingForAH = (not orderFlow.env.atAH)

		if isLiveMerchantOpen() then
			local becameOpen = not orderFlow.env.atVendor
			orderFlow.env.atVendor = true
			local vn = readLiveVendorName()
			if vn then orderFlow.env.vendorName = vn end
			local vSt = orderFlow.stages.vendor
			local vBase = vSt.baselineBagQty
			for _, it in ipairs(vSt.items or {}) do
				if it.itemID and ((becameOpen and vSt.pendingBuy == nil) or vBase[it.itemID] == nil) then
					vBase[it.itemID] = getLiveBagCount(it.itemID)
				end
			end
			if becameOpen or (next(orderFlow.liveVendorSlots) == nil and next(orderFlow.liveVendorSlotsByName or {}) == nil and #(vSt.items or {}) > 0) then
				OrderFlow.ScanOpenVendor()
			end
		elseif orderFlow.env.atVendor then
			orderFlow.env.atVendor = false
			orderFlow.env.vendorName = nil
			OrderFlow.ScanOpenVendor()
		end

		if isLiveBankOpen() then
			local becameBank = not orderFlow.env.atBank
			orderFlow.env.atBank = true
			local cSt = orderFlow.stages.collect
			local cBase = cSt.baselineBagQty
			for _, it in ipairs(cSt.items or {}) do
				if it.source == "bank" and it.itemID and ((becameBank and cSt.pendingTake == nil) or cBase[it.itemID] == nil) then
					cBase[it.itemID] = getLiveBagCount(it.itemID)
				end
			end
			if becameBank or (next(orderFlow.liveBankSlots) == nil and hasCollectItemsOfSource("bank")) then
				OrderFlow.ScanOpenBank()
			end
		elseif orderFlow.env.atBank then
			orderFlow.env.atBank = false
			OrderFlow.ScanOpenBank()
		end

		if isLiveMailOpen() then
			local becameMail = not orderFlow.env.atMail
			orderFlow.env.atMail = true
			local cSt = orderFlow.stages.collect
			local cBase = cSt.baselineBagQty
			for _, it in ipairs(cSt.items or {}) do
				if (it.source == "mail" or it.source == "alt") and it.itemID and ((becameMail and cSt.pendingTake == nil) or cBase[it.itemID] == nil) then
					cBase[it.itemID] = getLiveBagCount(it.itemID)
				end
			end
			if becameMail or (next(orderFlow.liveMailSlots) == nil and (hasCollectItemsOfSource("mail") or hasCollectItemsOfSource("alt"))) then
				OrderFlow.ScanOpenMailbox()
			end
		elseif orderFlow.env.atMail then
			orderFlow.env.atMail = false
			OrderFlow.ScanOpenMailbox()
		end

		local pk, pf = OrderFlow.GetOpenProfession()
		orderFlow.env.openProfKey = pk
		orderFlow.env.openProfFrame = pf
	end

	OrderFlow.SyncLiveEnvironment = syncLiveEnvironmentInternal

	local function refreshLiveEnvFlags()
		syncLiveEnvironmentInternal()
	end

	local function selectNextPendingAH(fromIndex)
		local ah = orderFlow.stages.ah
		local n = #ah.items
		if n == 0 then
			ah.activeIndex = 1
			return nil
		end
		local start = fromIndex or ah.activeIndex or 1
		local destKey = orderFlow.selectedDestKey
		if destKey and destKey ~= "" then
			for offset = 0, n - 1 do
				local idx = ((start - 1 + offset) % n) + 1
				local item = ah.items[idx]
				if item and item.remaining > 0 and item.status ~= "done" and itemDestQty(item, destKey) ~= nil then
					ah.activeIndex = idx
					return idx
				end
			end
		end
		for offset = 0, n - 1 do
			local idx = ((start - 1 + offset) % n) + 1
			local item = ah.items[idx]
			if item and item.remaining > 0 and item.status ~= "done" then
				ah.activeIndex = idx
				return idx
			end
		end
		return nil
	end

	local function selectNextPendingVendorInternal(fromIndex, preferInStock)
		local vSt = orderFlow.stages.vendor
		local n = #vSt.items
		if n == 0 then
			vSt.activeIndex = 1
			return nil
		end
		local start = fromIndex or vSt.activeIndex or 1
		local destKey = orderFlow.selectedDestKey
		local function pick(requireDest, requireStock)
			for offset = 0, n - 1 do
				local idx = ((start - 1 + offset) % n) + 1
				local it = vSt.items[idx]
				if it and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
					local destOk = (not requireDest) or (itemDestQty(it, destKey) ~= nil)
					local stockOk = (not requireStock) or (it.inStockHere == true and not it.hasExtendedCost and it.numAvailable ~= 0)
					if destOk and stockOk then
						vSt.activeIndex = idx
						return idx
					end
				end
			end
			return nil
		end
		if destKey and destKey ~= "" then
			if preferInStock then
				local r = pick(true, true)
				if r then return r end
			end
			local r = pick(true, false)
			if r then return r end
		end
		if preferInStock then
			local r = pick(false, true)
			if r then return r end
		end
		return pick(false, false)
	end

	local function sortCollectItems()
		local cSt = orderFlow.stages.collect
		local activeItem = cSt.items[cSt.activeIndex]
		local preferBankHere = (orderFlow.env.atBank and not orderFlow.env.atMail)
		local function rank(src)
			if preferBankHere then
				if src == "bank" then return 1
				elseif src == "mail" then return 2
				elseif src == "alt" then return 3
				else return 4 end
			else
				if src == "mail" then return 1
				elseif src == "bank" then return 2
				elseif src == "alt" then return 3
				else return 4 end
			end
		end
		table.sort(cSt.items, function(a, b)
			local ra, rb = rank(a.source), rank(b.source)
			if ra ~= rb then return ra < rb end
			return (a._order or 0) < (b._order or 0)
		end)
		if activeItem then
			for i, it in ipairs(cSt.items) do
				if it == activeItem then
					cSt.activeIndex = i
					break
				end
			end
		end
	end

	local function selectNextPendingCollectInternal(fromIndex, preferSource)
		local cSt = orderFlow.stages.collect
		local n = #cSt.items
		if n == 0 then
			cSt.activeIndex = 1
			return nil
		end
		local start = fromIndex or cSt.activeIndex or 1
		local destKey = orderFlow.selectedDestKey
		local function pick(requireDest, requireSource)
			for offset = 0, n - 1 do
				local idx = ((start - 1 + offset) % n) + 1
				local it = cSt.items[idx]
				if it and (it.source == "bank" or it.source == "mail")
					and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
					local destOk = (not requireDest) or (itemDestQty(it, destKey) ~= nil)
					local srcOk = (not requireSource) or (it.source == requireSource)
					if destOk and srcOk then
						cSt.activeIndex = idx
						return idx
					end
				end
			end
			return nil
		end
		if destKey and destKey ~= "" then
			if preferSource then
				local r = pick(true, preferSource)
				if r then return r end
			end
			local r = pick(true, nil)
			if r then return r end
		end
		if preferSource then
			local r = pick(false, preferSource)
			if r then return r end
		end
		return pick(false, nil)
	end

	local function areDependenciesSatisfied(task)
		if not (task and type(task.dependsOn) == "table" and #task.dependsOn > 0) then
			return true
		end
		local byKey = {}
		for _, t in ipairs(orderFlow.stages.craft.tasks or {}) do
			if t and t.taskKey then byKey[t.taskKey] = t end
		end
		for _, depKey in ipairs(task.dependsOn) do
			local dep = byKey[depKey]
			if dep and (dep.remainingCrafts or 0) > 0 and dep.status ~= "done" and dep.status ~= "skipped" then
				return false
			end
		end
		return true
	end

	local function selectNextPendingCraftInternal(fromIndex, preferProfKey)
		local crSt = orderFlow.stages.craft
		local n = #crSt.tasks
		if n == 0 then
			crSt.activeIndex = 1
			return nil
		end
		local start = fromIndex or crSt.activeIndex or 1
		local destKey = orderFlow.selectedDestKey
		local function pick(requireDest, requireProf, requireUnblocked)
			for offset = 0, n - 1 do
				local idx = ((start - 1 + offset) % n) + 1
				local t = crSt.tasks[idx]
				if t and (t.remainingCrafts or 0) > 0 and t.status ~= "done" and t.status ~= "skipped" then
					local destOk = (not requireDest) or (itemDestQty(t, destKey) ~= nil)
					local profOk = (not requireProf) or (t.profKey == requireProf)
					local depOk = (not requireUnblocked) or areDependenciesSatisfied(t)
					if destOk and profOk and depOk then
						crSt.activeIndex = idx
						return idx
					end
				end
			end
			return nil
		end
		if destKey and destKey ~= "" then
			if preferProfKey then
				local r = pick(true, preferProfKey, true)
				if r then return r end
			end
			local r = pick(true, nil, true) or pick(true, nil, false)
			if r then return r end
		end
		if preferProfKey then
			local r = pick(false, preferProfKey, true)
			if r then return r end
		end
		return pick(false, nil, true) or pick(false, nil, false)
	end

	local function buildAHEntryFromTerm(t, defaultTitle)
		local id = safeNumber(t.itemID)
		if (not id or id <= 0) and t.searchString and lookupID then
			id = safeNumber(lookupID(t.searchString))
		end
		local name = (id and id > 0 and itemSearchName(id)) or t.searchString or t.name
		local qty = math.max(1, math.floor((tonumber(t.quantity or t.qty) or 1) + 0.5))
		if not (name and name ~= "") then return nil end
		local targetUnit = safeNumber(t.unitPrice)
		if not targetUnit or targetUnit <= 0 then
			targetUnit = (id and id > 0 and ns.GetItemMarketPrice and safeNumber(ns.GetItemMarketPrice(id))) or 0
		end
		local prov = {}
		if type(t.provenance) == "table" and #t.provenance > 0 then
			for _, p in ipairs(t.provenance) do
				if type(p) == "table" then
					mergeProvenanceEntry(
						prov,
						p.qty or qty,
						p.subCraftName,
						p.targetName or defaultTitle,
						p.sourceKind or "shopping",
						p.sourceLabel or "Shopping",
						p.subCraftItemID,
						p.targetItemID,
						p.subCraftProf
					)
				end
			end
		elseif (type(t.targetName) == "string" and t.targetName ~= "") or (type(t.categoryName) == "string" and t.categoryName ~= "") then
			mergeProvenanceEntry(
				prov,
				qty,
				t.subCraftName,
				t.targetName or t.categoryName,
				t.sourceKind or "shopping",
				t.sourceLabel or "Shopping",
				t.subCraftItemID,
				t.targetItemID,
				t.subCraftProf
			)
		end
		local maxBuyUnit = safeNumber(t.maxBuyUnit)
		if maxBuyUnit and maxBuyUnit <= 0 then maxBuyUnit = nil end
		local breakEvenUnit = safeNumber(t.breakEvenUnit)
		if breakEvenUnit and breakEvenUnit <= 0 then breakEvenUnit = nil end
		return {
			itemID = id,
			name = name,
			needed = qty,
			bought = 0,
			remaining = qty,
			targetUnit = targetUnit,
			unitPrice = targetUnit,
			totalPrice = targetUnit * qty,
			maxBuyUnit = maxBuyUnit,
			breakEvenUnit = breakEvenUnit,
			overBuyCap = nil,
			buyCapMarginCopper = nil,
			liveUnit = nil,
			liveTotal = nil,
			priceDeltaPct = nil,
			priceDiffCopper = nil,
			priceDiffPct = nil,
			priceDiffTotalCopper = nil,
			priceAlert = nil,
			status = "pending",
			provenance = prov,
		}
	end

	local function extractRecipeReagents(recipe)
		local out = {}
		if type(recipe) ~= "table" or type(recipe.reagents) ~= "table" then return out end
		for _, rg in ipairs(recipe.reagents) do
			if type(rg) == "table" then
				local id = safeNumber(rg.itemID or rg.id or rg[1])
				local q = safeNumber(rg.qtyPerCraft or rg.qty or rg.count or rg[2])
				if id and id > 0 and q and q > 0 then
					local nm = (type(rg.name) == "string" and rg.name ~= "" and rg.name)
						or itemSearchName(id)
						or (ns.ItemName and ns.ItemName(id))
						or ("Item #" .. tostring(id))
					out[#out + 1] = { itemID = id, name = nm, qtyPerCraft = math.max(1, math.floor(q + 0.5)) }
				end
			end
		end
		return out
	end

	local function resetAllStages(title)
		if CartBuyer.CancelDirectBuy and orderFlow.stages.ah and orderFlow.stages.ah.directBuy then
			CartBuyer.CancelDirectBuy(nil, { silent = true, cancelServer = true })
		end
		local prevSerial = (orderFlow.stages.ah and orderFlow.stages.ah.directBuySerial) or 0
		local prevExtSerial = (orderFlow.stages.ah and orderFlow.stages.ah.externalBidSerial) or 0
		orderFlow.title = (type(title) == "string" and title ~= "") and title or "Shopping List"
		orderFlow.cartSig = nil
		orderFlow.selectedDestKey = nil
		orderFlow.stageCompletePrompt = nil
		orderFlow.notice = nil
		orderFlow.noticeKind = "info"
		orderFlow.destCache = nil
		bumpOwnershipRev()
		orderFlow.liveVendorSlots = {}
		orderFlow.liveVendorSlotsByName = {}
		orderFlow.liveBankSlots = {}
		orderFlow.liveMailSlots = {}
		orderFlow.env._vendorAutoSwitched = false
		orderFlow.env._bankAutoSwitched = false
		orderFlow.env._mailAutoSwitched = false
		orderFlow.stages.ah = {
			items = {},
			activeIndex = 1,
			waitingForAH = (not atAH()),
			spentCopper = 0,
			pendingExternal = nil,
			pendingExternalBid = nil,
			directBuy = nil,
			selfBidInFlight = false,
			directBuySerial = prevSerial + 1,
			externalBidSerial = prevExtSerial + 1,
		}
		orderFlow.stages.vendor = {
			items = {},
			activeIndex = 1,
			spentCopper = 0,
			baselineBagQty = {},
			pendingBuy = nil,
		}
		orderFlow.stages.collect = {
			items = {},
			activeIndex = 1,
			baselineBagQty = {},
			pendingTake = nil,
			collectAll = nil,
		}
		orderFlow.stages.craft = {
			tasks = {},
			activeIndex = 1,
			pendingCraft = nil,
			activeCast = nil,
			craftingBatch = nil,
		}
		local prevPostSer = (orderFlow.stages.sell and orderFlow.stages.sell.postSerial) or 0
		local prevSrchSer = (orderFlow.stages.sell and orderFlow.stages.sell.searchSerial) or 0
		orderFlow.stages.sell = {
			items = {},
			activeIndex = 1,
			duration = 2,
			undercutMode = "match",
			undercutPct = 1,
			pendingPost = nil,
			pendingSearch = nil,
			pendingKeyPrime = nil,
			pendingVendorSell = nil,
			warningConfirm = nil,
			lastItemInfo = nil,
			lastItemListings = nil,
			postAllActive = false,
			totalEarnedCopper = 0,
			throttleBlockedAt = nil,
			postSerial = prevPostSer + 1,
			searchSerial = prevSrchSer + 1,
		}
		if ns.AHChannel and ns.AHChannel.Release then
			ns.AHChannel.Release("orderflow_sell")
		end
		refreshLiveEnvFlags()
	end

	function OrderFlow.ClearSavedState()
		resetAllStages("Shopping List")
		orderFlow.activeStage = "ah"
		orderFlow.active = false
		syncCartBuyerMirror()
		if type(_G.MerchantMasterDB) == "table" then
			_G.MerchantMasterDB.orderFlowState = nil
		end
		notifyOrderFlow(true)
		return true
	end

	function OrderFlow.RestoreState(saved)
		saved = saved or (type(_G.MerchantMasterDB) == "table" and _G.MerchantMasterDB.orderFlowState) or nil
		if type(saved) ~= "table" or type(saved.stages) ~= "table" then return false end
		local sAh = type(saved.stages.ah) == "table" and saved.stages.ah or {}
		local sCol = type(saved.stages.collect) == "table" and saved.stages.collect or {}
		local sVen = type(saved.stages.vendor) == "table" and saved.stages.vendor or {}
		local sCr = type(saved.stages.craft) == "table" and saved.stages.craft or {}
		local sSl = type(saved.stages.sell) == "table" and saved.stages.sell or {}
		local totalCount = #(sAh.items or {}) + #(sCol.items or {}) + #(sVen.items or {}) + #(sCr.tasks or {}) + #(sSl.items or {})
		if totalCount <= 0 then return false end

		resetAllStages(saved.title)
		orderFlow.cartSig = (type(saved.cartSig) == "string" and saved.cartSig ~= "") and saved.cartSig or nil
		orderFlow.selectedDestKey = (type(saved.selectedDestKey) == "string" and saved.selectedDestKey ~= "") and saved.selectedDestKey or nil

		local ah = orderFlow.stages.ah
		ah.items = clonePersistArray(sAh.items, function(it)
			it.needed = math.max(1, math.floor((tonumber(it.needed) or 1) + 0.5))
			it.bought = math.max(0, math.min(it.needed, math.floor((tonumber(it.bought) or 0) + 0.5)))
			if it.status == "done" then
				it.bought = math.max(it.bought, it.needed)
				it.remaining = 0
			elseif it.status == "skipped" then
				it.remaining = math.max(0, it.needed - it.bought)
			else
				it.remaining = math.max(0, it.needed - it.bought)
				it.status = (it.remaining <= 0) and "done" or "pending"
			end
			it.unitPrice = tonumber(it.targetUnit or it.unitPrice) or 0
			it.totalPrice = it.unitPrice * it.remaining
		end)
		ah.spentCopper = math.max(0, tonumber(sAh.spentCopper) or 0)
		ah.activeIndex = (#ah.items > 0) and math.max(1, math.min(#ah.items, math.floor(tonumber(sAh.activeIndex) or 1))) or 1

		local selfAltNames = {}
		local function addSelfAltName(raw)
			if not readable(raw) or type(raw) ~= "string" then return end
			local trimmed = raw:match("^%s*(.-)%s*$")
			if not trimmed or trimmed == "" then return end
			selfAltNames[trimmed:lower()] = true
			local base = trimmed:match("^([^%-]+)")
			if base then
				base = base:match("^%s*(.-)%s*$")
				if base and base ~= "" then
					selfAltNames[base:lower()] = true
					local firstW = base:match("^([^%s]+)%s+")
					if firstW and firstW ~= "" then
						selfAltNames[firstW:lower()] = true
					end
				end
			end
		end
		if type(app.char) == "table" then
			addSelfAltName(app.char.name)
			addSelfAltName(app.char.firstName)
		end
		if ns.GetPlayerFullName then
			local okU, uFull, uFirst = pcall(ns.GetPlayerFullName)
			if okU then
				addSelfAltName(uFull)
				addSelfAltName(uFirst)
			end
		elseif type(_G.UnitName) == "function" then
			local okU, uName = pcall(_G.UnitName, "player")
			if okU then addSelfAltName(uName) end
		end
		local function isSelfAltOwnerName(raw)
			if not readable(raw) or type(raw) ~= "string" then return false end
			local trimmed = raw:match("^%s*(.-)%s*$")
			if not trimmed or trimmed == "" then return false end
			if selfAltNames[trimmed:lower()] then return true end
			local base = trimmed:match("^([^%-]+)")
			if base then
				base = base:match("^%s*(.-)%s*$")
				if base and base ~= "" and selfAltNames[base:lower()] then return true end
			end
			return false
		end

		local col = orderFlow.stages.collect
		local rawColItems = clonePersistArray(sCol.items, function(it)
			it.needed = math.max(1, math.floor((tonumber(it.needed) or 1) + 0.5))
			it.collected = math.max(0, math.min(it.needed, math.floor((tonumber(it.collected) or 0) + 0.5)))
			local hasAltMeta = (type(it.altOwners) == "table" and #it.altOwners > 0)
				or (type(it.altLabel) == "string" and it.altLabel ~= "")
			if it.source == "alt" or it.status == "alt_info" or (it.source == "mail" and hasAltMeta) then
				it.source = "alt"
				it.status = "alt_info"
				it.remaining = math.max(0, it.needed - it.collected)
			elseif it.status == "done" or it.source == "bags" then
				it.collected = math.max(it.collected, it.needed)
				it.remaining = 0
				it.status = "done"
			elseif it.status == "skipped" then
				it.remaining = math.max(0, it.needed - it.collected)
			else
				it.remaining = math.max(0, it.needed - it.collected)
				it.status = (it.remaining <= 0) and "done" or "pending"
			end
			if it.itemID and it.itemID > 0 then
				col.baselineBagQty[it.itemID] = getLiveBagCount(it.itemID)
			end
		end)
		local filteredColItems = {}
		for _, it in ipairs(rawColItems) do
			local dropItem = false
			if it.source == "alt" or it.status == "alt_info" then
				if type(it.altOwners) == "table" and #it.altOwners > 0 then
					local keptAlts = {}
					for _, a in ipairs(it.altOwners) do
						if type(a) == "table" and not isSelfAltOwnerName(a.name) then
							keptAlts[#keptAlts + 1] = a
						end
					end
					if #keptAlts == 0 then
						dropItem = true
					elseif #keptAlts < #it.altOwners then
						it.altOwners = keptAlts
						local altParts = {}
						local altQtySum = 0
						for _, a in ipairs(keptAlts) do
							local aq = math.max(0, math.floor((tonumber(a.qty) or 0) + 0.5))
							altQtySum = altQtySum + aq
							altParts[#altParts + 1] = string.format("%s (%s %dx)", tostring(a.name or "Alt"), tostring(a.location or "Bags"), aq)
						end
						it.altLabel = "On Alt: " .. table.concat(altParts, ", ")
						if altQtySum > 0 and altQtySum < (it.needed or 1) then
							it.needed = altQtySum
							it.collected = math.min(it.collected or 0, it.needed)
							it.remaining = math.max(0, it.needed - it.collected)
						end
					end
				elseif type(it.altLabel) == "string" and not it.altLabel:find(",", 1, true) then
					local lblName = it.altLabel:match("^On Alt:%s*([^%(]+)")
					if lblName and isSelfAltOwnerName(lblName) then
						dropItem = true
					end
				end
			end
			if not dropItem then
				filteredColItems[#filteredColItems + 1] = it
			end
		end
		col.items = filteredColItems
		col.activeIndex = (#col.items > 0) and math.max(1, math.min(#col.items, math.floor(tonumber(sCol.activeIndex) or 1))) or 1

		local ven = orderFlow.stages.vendor
		ven.items = clonePersistArray(sVen.items, function(it)
			it.needed = math.max(1, math.floor((tonumber(it.needed) or 1) + 0.5))
			it.bought = math.max(0, math.min(it.needed, math.floor((tonumber(it.bought) or 0) + 0.5)))
			if it.status == "done" then
				it.bought = math.max(it.bought, it.needed)
				it.remaining = 0
			elseif it.status == "skipped" then
				it.remaining = math.max(0, it.needed - it.bought)
			else
				it.remaining = math.max(0, it.needed - it.bought)
				it.status = (it.remaining <= 0) and "done" or "pending"
			end
			it.unitPrice = tonumber(it.unitPrice) or 0
			it.totalPrice = it.unitPrice * it.remaining
			if it.itemID and it.itemID > 0 then
				ven.baselineBagQty[it.itemID] = getLiveBagCount(it.itemID)
			end
		end)
		ven.spentCopper = math.max(0, tonumber(sVen.spentCopper) or 0)
		ven.activeIndex = (#ven.items > 0) and math.max(1, math.min(#ven.items, math.floor(tonumber(sVen.activeIndex) or 1))) or 1

		local cr = orderFlow.stages.craft
		cr.tasks = clonePersistArray(sCr.tasks, function(t)
			t.neededCrafts = math.max(1, math.floor((tonumber(t.neededCrafts) or 1) + 0.5))
			t.completedCrafts = math.max(0, math.min(t.neededCrafts, math.floor((tonumber(t.completedCrafts) or 0) + 0.5)))
			if t.status == "done" then
				t.completedCrafts = math.max(t.completedCrafts, t.neededCrafts)
				t.remainingCrafts = 0
			elseif t.status == "skipped" then
				t.remainingCrafts = math.max(0, t.neededCrafts - t.completedCrafts)
			else
				t.remainingCrafts = math.max(0, t.neededCrafts - t.completedCrafts)
				t.status = (t.remainingCrafts <= 0) and "done" or "pending"
			end
		end)
		cr.activeIndex = (#cr.tasks > 0) and math.max(1, math.min(#cr.tasks, math.floor(tonumber(sCr.activeIndex) or 1))) or 1

		local sl = orderFlow.stages.sell
		sl.duration = (sSl.duration == 1 or sSl.duration == 2 or sSl.duration == 3) and sSl.duration or 2
		sl.undercutMode = (sSl.undercutMode == "match" or sSl.undercutMode == "1c" or sSl.undercutMode == "1s" or sSl.undercutMode == "pct") and sSl.undercutMode or "match"
		sl.undercutPct = math.max(0, math.min(50, tonumber(sSl.undercutPct) or 1))
		sl.totalEarnedCopper = math.max(0, tonumber(sSl.totalEarnedCopper) or 0)
		sl.items = clonePersistArray(sSl.items, function(it)
			it.totalQty = math.max(1, math.floor((tonumber(it.totalQty or it.needed) or 1) + 0.5))
			it.needed = it.totalQty
			it.soldQty = math.max(0, math.min(it.totalQty, math.floor((tonumber(it.soldQty) or 0) + 0.5)))
			if it.status == "done" then
				it.soldQty = math.max(it.soldQty, it.totalQty)
				it.remaining = 0
			elseif it.status == "skipped" then
				it.remaining = math.max(0, it.totalQty - it.soldQty)
			else
				it.remaining = math.max(0, it.totalQty - it.soldQty)
				it.status = (it.remaining <= 0) and "done" or "pending"
			end
			it.channel = (it.channel == "vendor") and "vendor" or "ah"
			it.bidPrice = 0
			it.inBags = it.itemID and getSellableBagCount(it.itemID, it.channel == "vendor", it.itemLink) or 0
			if it.postQty ~= nil then
				it.postQty = math.max(0, math.floor((tonumber(it.postQty) or 0) + 0.5))
			end
		end)
		sl.activeIndex = (#sl.items > 0) and math.max(1, math.min(#sl.items, math.floor(tonumber(sSl.activeIndex) or 1))) or 1

		orderFlow.activeStage = (saved.activeStage and STAGE_INDEX_BY_KEY[saved.activeStage]) and saved.activeStage or "ah"
		orderFlow.active = true
		refreshLiveEnvFlags()
		if orderFlow.env.atVendor then OrderFlow.ScanOpenVendor() end
		if orderFlow.env.atBank then OrderFlow.ScanOpenBank() end
		if orderFlow.env.atMail then OrderFlow.ScanOpenMailbox() end
		notifyOrderFlow(true)
		return true
	end

	-----------------------------------------------------------------------------------------------
	-- 4.1 Core Lifecycle & Stage Navigation
	-----------------------------------------------------------------------------------------------
	function OrderFlow.GetState()
		return orderFlow
	end

	function OrderFlow.SetOnUpdate(fn)
		orderFlow.onUpdate = fn
	end

	function OrderFlow.GetActiveStage()
		return orderFlow.activeStage or "ah"
	end

	function OrderFlow.SetActiveStage(stageKey)
		if not STAGE_INDEX_BY_KEY[stageKey] then return false end
		if orderFlow.activeStage == "ah" and stageKey ~= "ah" and orderFlow.stages.ah and orderFlow.stages.ah.directBuy then
			CartBuyer.CancelDirectBuy(nil, { silent = true, cancelServer = true })
		end
		orderFlow.activeStage = stageKey
		syncLiveEnvironmentInternal()
		if stageKey == "ah" then
			if orderFlow.env.atAH then
				orderFlow.active = true
			end
		elseif stageKey == "vendor" and orderFlow.env.atVendor then
			local stocked = OrderFlow.ScanOpenVendor()
			if stocked > 0 then
				local vSt = orderFlow.stages.vendor
				local curV = vSt.items and vSt.items[vSt.activeIndex]
				if not curV or not curV.inStockHere or (curV.remaining or 0) <= 0 or curV.status == "done" or curV.status == "skipped" then
					selectNextPendingVendorInternal(1, true)
				end
			end
		elseif stageKey == "collect" then
			if orderFlow.env.atBank then OrderFlow.ScanOpenBank() end
			if orderFlow.env.atMail then OrderFlow.ScanOpenMailbox() end
			sortCollectItems()
		elseif stageKey == "craft" then
			local pk, pf = OrderFlow.GetOpenProfession()
			orderFlow.env.openProfKey = pk
			orderFlow.env.openProfFrame = pf
		elseif stageKey == "sell" then
			local sl = orderFlow.stages.sell
			sl.warningConfirm = nil
			for _, it in ipairs(sl.items or {}) do
				if it.itemID and it.itemID > 0 then
					it.inBags = getSellableBagCount(it.itemID, it.channel == "vendor", it.itemLink)
				end
			end
			if orderFlow.env.atAH and OrderFlow.ScanSellItemMarket then
				local cur = sl.items[sl.activeIndex]
				if cur and cur.channel == "ah" and (cur.remaining or 0) > 0 and cur.status ~= "done" and cur.status ~= "skipped" then
					OrderFlow.ScanSellItemMarket(sl.activeIndex, "select")
				end
			end
		end
		notifyOrderFlow()
		return true
	end

	function OrderFlow.GetStageStats(stageKey)
		stageKey = stageKey or orderFlow.activeStage or "ah"
		if stageKey == "ah" then
			local ah = orderFlow.stages.ah
			local total, done, remaining = 0, 0, 0
			local totalUnits, doneUnits, remainingUnits = 0, 0, 0
			local totalEstCopper, remainingEstCopper = 0, 0
			for _, it in ipairs(ah.items or {}) do
				total = total + 1
				local needed = math.max(0, tonumber(it.needed) or 0)
				local bought = math.max(0, math.min(needed, tonumber(it.bought) or 0))
				local rem = math.max(0, tonumber(it.remaining) or (needed - bought))
				local targetU = tonumber(it.targetUnit) or tonumber(it.unitPrice) or 0
				local liveOrTarget = (it.liveUnit and it.liveUnit > 0) and it.liveUnit or targetU
				totalUnits = totalUnits + needed
				doneUnits = doneUnits + bought
				remainingUnits = remainingUnits + rem
				totalEstCopper = totalEstCopper + (targetU * needed)
				if it.status == "done" or rem <= 0 then
					done = done + 1
				else
					remaining = remaining + 1
					remainingEstCopper = remainingEstCopper + (liveOrTarget * rem)
				end
			end
			return {
				total = total,
				done = done,
				remaining = remaining,
				actionableRemaining = remaining,
				empty = (total == 0),
				complete = (remaining == 0),
				totalUnits = totalUnits,
				doneUnits = doneUnits,
				remainingUnits = remainingUnits,
				spentCopper = tonumber(ah.spentCopper) or 0,
				remainingEstCopper = remainingEstCopper,
				totalEstCopper = totalEstCopper,
			}
		elseif stageKey == "vendor" then
			local vSt = orderFlow.stages.vendor
			local total, done, remaining = 0, 0, 0
			local totalUnits, doneUnits, remainingUnits = 0, 0, 0
			local totalEstCopper, remainingEstCopper = 0, 0
			for _, it in ipairs(vSt.items or {}) do
				total = total + 1
				local needed = math.max(0, tonumber(it.needed) or 0)
				local bought = math.max(0, math.min(needed, tonumber(it.bought) or 0))
				local rem = math.max(0, tonumber(it.remaining) or (needed - bought))
				local unitP = tonumber(it.unitPrice) or 0
				local liveOrEst = (it.liveUnit and it.liveUnit > 0) and it.liveUnit or unitP
				totalUnits = totalUnits + needed
				doneUnits = doneUnits + bought
				totalEstCopper = totalEstCopper + (unitP * needed)
				if it.status == "done" or it.status == "skipped" or rem <= 0 then
					done = done + 1
				else
					remaining = remaining + 1
					remainingUnits = remainingUnits + rem
					remainingEstCopper = remainingEstCopper + (liveOrEst * rem)
				end
			end
			return {
				total = total,
				done = done,
				remaining = remaining,
				actionableRemaining = remaining,
				empty = (total == 0),
				complete = (remaining == 0),
				totalUnits = totalUnits,
				doneUnits = doneUnits,
				remainingUnits = remainingUnits,
				spentCopper = tonumber(vSt.spentCopper) or 0,
				remainingEstCopper = remainingEstCopper,
				totalEstCopper = totalEstCopper,
			}
		elseif stageKey == "collect" then
			local cSt = orderFlow.stages.collect
			local total, done, actionableRemaining, altCount, bagsCount = 0, 0, 0, 0, 0
			local totalUnits, doneUnits, remainingUnits = 0, 0, 0
			for _, it in ipairs(cSt.items or {}) do
				total = total + 1
				local needed = math.max(0, tonumber(it.needed) or 0)
				local coll = math.max(0, math.min(needed, tonumber(it.collected) or 0))
				local rem = math.max(0, tonumber(it.remaining) or (needed - coll))
				totalUnits = totalUnits + needed
				doneUnits = doneUnits + coll
				if it.source == "bags" then
					bagsCount = bagsCount + 1
				end
				if it.status == "done" or it.status == "skipped" or rem <= 0 then
					done = done + 1
				elseif it.source == "alt" or it.status == "alt_info" then
					altCount = altCount + 1
				else
					actionableRemaining = actionableRemaining + 1
					remainingUnits = remainingUnits + rem
				end
			end
			return {
				total = total,
				done = done,
				remaining = actionableRemaining,
				actionableRemaining = actionableRemaining,
				altCount = altCount,
				bagsCount = bagsCount,
				empty = (total == 0),
				complete = (actionableRemaining == 0 and altCount == 0),
				totalUnits = totalUnits,
				doneUnits = doneUnits,
				remainingUnits = remainingUnits,
				spentCopper = 0,
				remainingEstCopper = 0,
				totalEstCopper = 0,
			}
		elseif stageKey == "craft" then
			local crSt = orderFlow.stages.craft
			local total, done, remaining = 0, 0, 0
			local totalUnits, doneUnits, remainingUnits = 0, 0, 0
			for _, t in ipairs(crSt.tasks or {}) do
				total = total + 1
				local needed = math.max(0, tonumber(t.neededCrafts) or 0)
				local comp = math.max(0, math.min(needed, tonumber(t.completedCrafts) or 0))
				local rem = math.max(0, tonumber(t.remainingCrafts) or (needed - comp))
				totalUnits = totalUnits + needed
				doneUnits = doneUnits + comp
				if t.status == "done" or t.status == "skipped" or rem <= 0 then
					done = done + 1
				else
					remaining = remaining + 1
					remainingUnits = remainingUnits + rem
				end
			end
			return {
				total = total,
				done = done,
				remaining = remaining,
				actionableRemaining = remaining,
				empty = (total == 0),
				complete = (remaining == 0),
				totalUnits = totalUnits,
				doneUnits = doneUnits,
				remainingUnits = remainingUnits,
				spentCopper = 0,
				remainingEstCopper = 0,
				totalEstCopper = 0,
			}
		elseif stageKey == "sell" then
			local sl = orderFlow.stages.sell
			local total, done, remaining = 0, 0, 0
			local totalUnits, doneUnits, remainingUnits = 0, 0, 0
			local ahCount, vendorCount = 0, 0
			for _, it in ipairs(sl.items or {}) do
				total = total + 1
				local needed = math.max(0, tonumber(it.totalQty or it.needed) or 0)
				local sold = math.max(0, math.min(needed, tonumber(it.soldQty) or 0))
				local rem = math.max(0, tonumber(it.remaining) or (needed - sold))
				totalUnits = totalUnits + needed
				doneUnits = doneUnits + sold
				if it.channel == "vendor" then vendorCount = vendorCount + 1 else ahCount = ahCount + 1 end
				if it.status == "done" or it.status == "skipped" or rem <= 0 then
					done = done + 1
				else
					remaining = remaining + 1
					remainingUnits = remainingUnits + rem
				end
			end
			return {
				total = total,
				done = done,
				remaining = remaining,
				actionableRemaining = remaining,
				empty = (total == 0),
				complete = (remaining == 0),
				totalUnits = totalUnits,
				doneUnits = doneUnits,
				remainingUnits = remainingUnits,
				spentCopper = 0,
				earnedCopper = tonumber(sl.totalEarnedCopper) or 0,
				remainingEstCopper = 0,
				totalEstCopper = 0,
				ahCount = ahCount,
				vendorCount = vendorCount,
			}
		end
		return {
			total = 0, done = 0, remaining = 0, actionableRemaining = 0,
			empty = true, complete = true, totalUnits = 0, doneUnits = 0,
			remainingUnits = 0, spentCopper = 0, remainingEstCopper = 0, totalEstCopper = 0,
		}
	end

	function OrderFlow.GetPipelineSummary()
		local out = {}
		for i, meta in ipairs(STAGE_META) do
			local st = OrderFlow.GetStageStats(meta.key)
			out[i] = {
				key = meta.key,
				index = meta.index,
				label = meta.label,
				shortLabel = meta.shortLabel,
				done = st.done,
				total = st.total,
				remaining = st.remaining,
				actionableRemaining = st.actionableRemaining,
				complete = st.complete,
				empty = st.empty,
				active = (orderFlow.activeStage == meta.key),
			}
		end
		return out
	end

	function OrderFlow.GetNextIncompleteStage(fromStageKey)
		local fromIdx = STAGE_INDEX_BY_KEY[fromStageKey or orderFlow.activeStage] or 1
		for i = fromIdx + 1, #STAGE_META do
			local k = STAGE_META[i].key
			local st = OrderFlow.GetStageStats(k)
			if not st.empty and not st.complete then return k end
		end
		for i = 1, fromIdx - 1 do
			local k = STAGE_META[i].key
			local st = OrderFlow.GetStageStats(k)
			if not st.empty and not st.complete then return k end
		end
		return nil
	end

	function OrderFlow.AdvanceToNextStage()
		local nextKey = OrderFlow.GetNextIncompleteStage(orderFlow.activeStage)
		if nextKey then
			OrderFlow.SetActiveStage(nextKey)
			return nextKey
		end
		return nil
	end

	function OrderFlow.GetWaitingMessage(stageKey)
		stageKey = stageKey or orderFlow.activeStage or "ah"
		syncLiveEnvironmentInternal()
		if stageKey == "ah" then
			if not orderFlow.env.atAH then return "Please open Auction House to start." end
			return nil
		elseif stageKey == "vendor" then
			if not orderFlow.env.atVendor then return "Please open a Vendor to start." end
			return nil
		elseif stageKey == "collect" then
			return OrderFlow.GetCollectWaitingMessage()
		elseif stageKey == "craft" then
			local crSt = orderFlow.stages.craft
			local task = crSt.tasks[crSt.activeIndex]
			if not task or (task.remainingCrafts or 0) <= 0 or task.status == "done" or task.status == "skipped" then
				local idx = selectNextPendingCraftInternal(1, nil)
				task = idx and crSt.tasks[idx] or nil
			end
			if task and (task.remainingCrafts or 0) > 0 and task.status ~= "done" and task.status ~= "skipped" then
				local openKey = OrderFlow.GetOpenProfession()
				orderFlow.env.openProfKey = openKey
				if openKey ~= task.profKey then
					return "Please open " .. tostring(task.profName or "Profession") .. " to start."
				end
			end
			return nil
		elseif stageKey == "sell" then
			local sl = orderFlow.stages.sell
			local st = OrderFlow.GetStageStats("sell")
			if not st or st.empty or st.complete then return nil end
			local cur = sl.items[sl.activeIndex]
			if not cur or cur.status == "done" or cur.status == "skipped" or (cur.remaining or 0) <= 0 then
				for _, it in ipairs(sl.items or {}) do
					if it and it.status ~= "done" and it.status ~= "skipped" and (it.remaining or 0) > 0 then
						cur = it
						break
					end
				end
			end
			if cur and cur.channel == "vendor" then
				if not orderFlow.env.atVendor then return "Please open a Vendor to sell." end
			else
				if not orderFlow.env.atAH then return "Please open Auction House to sell." end
			end
			return nil
		end
		return nil
	end

	function OrderFlow.OnWindowHide()
		if orderFlow.stages.ah and orderFlow.stages.ah.directBuy and CartBuyer.CancelDirectBuy then
			CartBuyer.CancelDirectBuy(nil, { silent = true, cancelServer = true })
		end
		orderFlow.active = false
		orderFlow.destCache = nil
		orderFlow.stages.ah.pendingExternal = nil
		orderFlow.stages.ah.pendingExternalBid = nil
		orderFlow.stages.ah.externalBidSerial = (orderFlow.stages.ah.externalBidSerial or 0) + 1
		orderFlow.stages.ah.directBuy = nil
		orderFlow.stages.ah.selfBidInFlight = false
		local sl = orderFlow.stages.sell
		if sl and sl.pendingPost and sl.pendingPost.multisellActive
			and C_AuctionHouse and type(C_AuctionHouse.CancelSell) == "function" then
			pcall(C_AuctionHouse.CancelSell)
		end
		if ns.AHChannel and ns.AHChannel.Release then
			ns.AHChannel.Release("cart_buyer")
			ns.AHChannel.Release("orderflow_sell")
		end
		orderFlow.stages.vendor.pendingBuy = nil
		orderFlow.stages.collect.pendingTake = nil
		if orderFlow.stages.collect.collectAll then
			orderFlow.stages.collect.collectAll.active = false
			orderFlow.stages.collect.collectAll = nil
		end
		local crSt = orderFlow.stages.craft
		crSt.pendingCraft = nil
		crSt.activeCast = nil
		crSt.craftingBatch = nil
		if sl then
			sl.pendingVendorSell = nil
			sl.postAllActive = false
			sl.warningConfirm = nil
			sl.pendingPost = nil
			sl.pendingSearch = nil
			sl.pendingKeyPrime = nil
		end
		syncCartBuyerMirror()
	end

	function OrderFlow.LoadAHTerms(terms, title)
		resetAllStages(title)
		orderFlow.activeStage = "ah"
		orderFlow.active = false
		local items = orderFlow.stages.ah.items
		for _, t in ipairs(terms or {}) do
			local entry = buildAHEntryFromTerm(t, orderFlow.title)
			if entry then
				items[#items + 1] = entry
			end
		end
		notifyOrderFlow()
		return #items
	end

	function OrderFlow.LoadFromShoppingRows(rows, opts)
		opts = type(opts) == "table" and opts or {}
		local title = opts.title or "Shopping List"
		local preserveProgress = (opts.preserveProgress == true)
		local prevSnap = nil
		if preserveProgress and OrderFlow.HasAnyItems and OrderFlow.HasAnyItems() then
			local prevDone = (OrderFlow.IsCraftCycleComplete and OrderFlow.IsCraftCycleComplete())
				or (OrderFlow.IsPipelineComplete and OrderFlow.IsPipelineComplete())
				or false
			local st = orderFlow.stages
			prevSnap = {
				pipelineComplete = prevDone,
				ahSpent = (not prevDone and st.ah and tonumber(st.ah.spentCopper)) or 0,
				venSpent = (not prevDone and st.vendor and tonumber(st.vendor.spentCopper)) or 0,
				ah = {},
				collect = {},
				vendor = {},
				craft = {},
				craftBySpell = {},
				sell = {},
				sellMeta = st.sell and {
					duration = st.sell.duration,
					undercutMode = st.sell.undercutMode,
					undercutPct = st.sell.undercutPct,
					totalEarnedCopper = st.sell.totalEarnedCopper,
				} or nil,
			}
			if not prevDone then
				for _, it in ipairs((st.ah and st.ah.items) or {}) do
					local k = it.itemID or (type(it.name) == "string" and it.name:lower())
					if k then prevSnap.ah[k] = { bought = tonumber(it.bought) or 0, skipped = (it.status == "skipped") } end
				end
				for _, it in ipairs((st.collect and st.collect.items) or {}) do
					local base = it.itemID or (type(it.name) == "string" and it.name:lower())
					if base and it.source then
						prevSnap.collect[tostring(it.source) .. ":" .. tostring(base)] = { collected = tonumber(it.collected) or 0, skipped = (it.status == "skipped") }
					end
				end
				for _, it in ipairs((st.vendor and st.vendor.items) or {}) do
					local k = it.itemID or (type(it.name) == "string" and it.name:lower())
					if k then prevSnap.vendor[k] = { bought = tonumber(it.bought) or 0, skipped = (it.status == "skipped") } end
				end
				for _, t in ipairs((st.craft and st.craft.tasks) or {}) do
					local rec = {
						completedCrafts = tonumber(t.completedCrafts) or 0,
						skipped = (t.status == "skipped"),
						measuredCastMs = safeNumber(t.measuredCastMs),
					}
					if t.taskKey then prevSnap.craft[t.taskKey] = rec end
					if t.profKey and t.spellID then
						prevSnap.craftBySpell[tostring(t.profKey) .. ":" .. tostring(t.spellID)] = rec
					end
				end
			end
			for _, it in ipairs((st.sell and st.sell.items) or {}) do
				local k = it.itemID or (type(it.name) == "string" and it.name:lower())
				if k then
					prevSnap.sell[k] = {
						isFromBag = (it.isFromBag == true),
						soldQty = tonumber(it.soldQty) or 0,
						totalQty = tonumber(it.totalQty) or nil,
						postQty = it.postQty,
						customQty = (it.customQty == true),
						skipped = (it.status == "skipped"),
						channel = it.channel,
						customPrice = it.customPrice,
						bidPrice = it.bidPrice,
					}
				end
			end
		end
		resetAllStages(title)
		orderFlow.cartSig = (type(opts.cartSig) == "string" and opts.cartSig ~= "") and opts.cartSig or nil

		local profMap = opts.profMap
			or (ns.GetLivePlayerProfessions and ns.GetLivePlayerProfessions())
			or (ns.GetPlayerProfessions and ns.GetPlayerProfessions())
			or {}
		local ownershipFn = (type(opts.ownershipProvider) == "function" and opts.ownershipProvider)
			or (type(app.getItemOwnershipBreakdown) == "function" and app.getItemOwnershipBreakdown)
			or defaultOwnershipProvider

		local mainItemByGroup, mainNameByGroup = {}, {}
		local subItemByGroup, subProfByGroup = {}, {}
		for _, row in ipairs(rows or {}) do
			if type(row) == "table" then
				if row.isMainRow and row.mainGroupKey then
					if safeNumber(row.itemID) then mainItemByGroup[row.mainGroupKey] = safeNumber(row.itemID) end
					if type(row.name) == "string" and row.name ~= "" then mainNameByGroup[row.mainGroupKey] = row.name end
				elseif row.isSubBranchRoot and row.subGroupKey then
					if safeNumber(row.itemID) then subItemByGroup[row.subGroupKey] = safeNumber(row.itemID) end
					if type(row.craftProf) == "string" and row.craftProf ~= "" then
						subProfByGroup[row.subGroupKey] = row.craftProf
					elseif type(row.prof) == "string" and row.prof ~= "" then
						subProfByGroup[row.subGroupKey] = row.prof
					end
				end
			end
		end

		local ahTerms, ahByKey, ahMetaByKey = {}, {}, {}
		local vendorOrder, vendorByKey = {}, {}
		local ownedOrder, ownedByKey = {}, {}
		local craftTasksByKey, craftTaskOrder = {}, {}
		local craftStack = {}
		local childReagentsByParent = {}
		local discoverySeq = 0

		local function resolveRowRecipe(row, isMain)
			local spID = safeNumber(row.spellID)
			local outID = safeNumber(row.itemID)
			local rProf = (type(row.craftProf) == "string" and row.craftProf ~= "" and row.craftProf)
				or (type(row.prof) == "string" and row.prof ~= "" and row.prof)
				or nil
			local rec = nil
			if ns.ResolveCraftingOrderRecipe and ((spID and spID > 0) or (outID and outID > 0)) then
				local ok, resolved = pcall(ns.ResolveCraftingOrderRecipe, {
					spellID = spID,
					outputItemID = outID,
					prof = rProf,
				}, profMap, false)
				if ok and tableValue(resolved) then rec = resolved end
			end
			if not rec and outID and outID > 0 and type(ns.RECIPES_BY_OUTPUT) == "table" then
				local list = ns.RECIPES_BY_OUTPUT[outID]
				if type(list) == "table" and list[1] then
					rec = list[1]
					if rProf then
						for _, cand in ipairs(list) do
							if cand and cand.prof == rProf then rec = cand; break end
						end
					end
				end
			end
			if not rec then
				local isCraftKind = (row.sourceKind == "craft_order" or row.sourceKind == "writ_craft"
					or row.sourceKind == "spread" or row.sourceKind == "leveling" or row.asCraft == true)
				if (not isMain and row.makeMyself == true)
					or (isMain and (isCraftKind or (spID and spID > 0) or type(row.reagents) == "table")) then
					rec = {
						spellID = spID,
						outputItemID = outID,
						name = row.name,
						recipeName = row.recipeName or row.name,
						prof = rProf or "crafting",
						numMade = safeNumber(row.numMade or row.outputsPerCraft) or 1,
						reagents = type(row.reagents) == "table" and row.reagents or {},
					}
				end
			end
			return rec
		end

		local function addDepEdge(subTask, parentTask)
			if not (subTask and parentTask and subTask.taskKey ~= parentTask.taskKey) then return end
			local existsDep = false
			for _, k in ipairs(parentTask.dependsOn) do
				if k == subTask.taskKey then existsDep = true; break end
			end
			if not existsDep then
				parentTask.dependsOn[#parentTask.dependsOn + 1] = subTask.taskKey
			end
			local existsFeed = false
			for _, k in ipairs(subTask.feedsTasks) do
				if k == parentTask.taskKey then existsFeed = true; break end
			end
			if not existsFeed then
				subTask.feedsTasks[#subTask.feedsTasks + 1] = parentTask.taskKey
			end
		end

		local function addOrMergeCraftTask(tier, depth, recipe, row, targetName, targetItemID)
			local isSub = (tier == "sub_craft")
			local spID = safeNumber(recipe and recipe.spellID) or safeNumber(row.spellID)
			local outID = safeNumber(recipe and recipe.outputItemID) or safeNumber(row.itemID)
			local dispName = (type(row.name) == "string" and row.name ~= "" and row.name)
				or (recipe and recipe.name)
				or (outID and itemSearchName(outID))
				or "Recipe"
			local recName = (recipe and type(recipe.recipeName) == "string" and recipe.recipeName ~= "" and recipe.recipeName)
				or (type(row.recipeName) == "string" and row.recipeName ~= "" and row.recipeName)
				or (recipe and recipe.name)
				or dispName
			local rawProf = (recipe and recipe.prof) or row.craftProf or row.prof or "crafting"
			local profKey, profName, profBadge = resolveProfMeta(rawProf)
			local numMade = math.max(1, math.floor((safeNumber(recipe and recipe.numMade) or safeNumber(row.numMade) or 1) + 0.5))
			local addOutputs = math.max(1, math.floor((tonumber(row.qty) or 1) + 0.5))
			local idKey = (spID and spID > 0) and ("s:" .. tostring(spID))
				or ((outID and outID > 0) and ("i:" .. tostring(outID)) or ("n:" .. tostring(dispName)))
			local taskKey = (isSub and "sub:" or "main:") .. idKey
			local existing = craftTasksByKey[taskKey]
			if existing then
				existing.neededOutputs = existing.neededOutputs + addOutputs
				existing.neededCrafts = math.max(1, math.ceil(existing.neededOutputs / math.max(1, existing.outputsPerCraft)))
				existing.remainingCrafts = math.max(0, existing.neededCrafts - existing.completedCrafts)
				existing.depth = math.max(existing.depth or 0, depth)
				if #existing.reagents == 0 and recipe then
					existing.reagents = extractRecipeReagents(recipe)
				end
				mergeProvenanceEntry(
					existing.provenance,
					addOutputs,
					isSub and dispName or nil,
					targetName or dispName,
					row.sourceKind or "craft_order",
					row.sourceLabel or "Craft Order",
					isSub and outID or nil,
					targetItemID or (not isSub and outID or nil),
					isSub and profKey or nil
				)
				return existing
			end
			discoverySeq = discoverySeq + 1
			local reagents = extractRecipeReagents(recipe)
			if #reagents == 0 and type(row.reagents) == "table" then
				reagents = extractRecipeReagents({ reagents = row.reagents })
			end
			local neededCrafts = math.max(1, math.ceil(addOutputs / numMade))
			local prov = {}
			mergeProvenanceEntry(
				prov,
				addOutputs,
				isSub and dispName or nil,
				targetName or dispName,
				row.sourceKind or "craft_order",
				row.sourceLabel or "Craft Order",
				isSub and outID or nil,
				targetItemID or (not isSub and outID or nil),
				isSub and profKey or nil
			)
			local castTimeMs = (ns.GetRecipeCastTimeMs and ns.GetRecipeCastTimeMs(spID, recipe)) or 2000
			if not safeNumber(castTimeMs) or castTimeMs < 0 then castTimeMs = 2000 end
			local task = {
				taskKey = taskKey,
				tier = isSub and "sub_craft" or "main_order",
				isSubCraft = isSub,
				depth = depth,
				itemID = (outID and outID > 0) and outID or nil,
				spellID = (spID and spID > 0) and spID or nil,
				name = dispName,
				recipeName = recName,
				profKey = profKey,
				profName = profName,
				profBadge = profBadge,
				castTimeMs = castTimeMs,
				outputsPerCraft = numMade,
				neededOutputs = addOutputs,
				neededCrafts = neededCrafts,
				completedCrafts = 0,
				remainingCrafts = neededCrafts,
				reagents = reagents,
				dependsOn = {},
				feedsTasks = {},
				discoveryOrder = discoverySeq,
				status = "pending",
				provenance = prov,
			}
			craftTasksByKey[taskKey] = task
			craftTaskOrder[#craftTaskOrder + 1] = task
			return task
		end

		local function appendRowProvenance(destList, row, qty, grpMainID, grpSubID, grpSubProf, mainNameFallback)
			if type(row.provenance) == "table" and #row.provenance > 0 then
				for _, p in ipairs(row.provenance) do
					if type(p) == "table" then
						mergeProvenanceEntry(
							destList,
							p.qty or qty,
							p.subCraftName,
							p.targetName or mainNameFallback or title,
							p.sourceKind or row.sourceKind or "shopping",
							p.sourceLabel or row.sourceLabel or "Shopping",
							p.subCraftItemID or grpSubID,
							p.targetItemID or grpMainID,
							p.subCraftProf or grpSubProf
						)
					end
				end
			else
				local subCraftName = (row.isSubRow and row.parentSubName) or row.subCraftName or nil
				local targetName = (type(row.categoryName) == "string" and row.categoryName ~= "" and row.categoryName)
					or (type(row.targetName) == "string" and row.targetName ~= "" and row.targetName)
					or mainNameFallback
					or title
				mergeProvenanceEntry(
					destList,
					qty,
					subCraftName,
					targetName,
					row.sourceKind or "shopping",
					row.sourceLabel or "Shopping",
					grpSubID,
					grpMainID,
					grpSubProf
				)
			end
		end

		-- Pass 1: Row classification & craft tree reconstruction
		local currentMainName, currentMainID = nil, nil
		for _, row in ipairs(rows or {}) do
			if type(row) == "table" then
				if row.isMainRow then
					craftStack = {}
					currentMainName = (type(row.name) == "string" and row.name ~= "") and row.name or nil
					currentMainID = safeNumber(row.itemID)
					local isCraftCandidate = (safeNumber(row.spellID) ~= nil)
						or (row.sourceKind == "craft_order" or row.sourceKind == "writ_craft"
							or row.sourceKind == "spread" or row.sourceKind == "leveling")
						or (row.asCraft == true)
					if isCraftCandidate then
						local rec = resolveRowRecipe(row, true)
						if rec then
							local mainTask = addOrMergeCraftTask("main_order", 0, rec, row, row.name, safeNumber(row.itemID))
							craftStack[0] = mainTask
						end
					end
				else
					local d = safeNumber(row.indent)
					if d and d >= 1 then
						d = math.floor(d)
					else
						d = row.isSubRow and 2 or 1
					end
					for k in pairs(craftStack) do
						if k >= d then craftStack[k] = nil end
					end
					local parentTask = nil
					for k = d - 1, 0, -1 do
						if craftStack[k] then parentTask = craftStack[k]; break end
					end

					local grpMainID = (row.mainGroupKey and mainItemByGroup[row.mainGroupKey]) or safeNumber(row.targetItemID) or currentMainID
					local grpMainName = (row.mainGroupKey and mainNameByGroup[row.mainGroupKey]) or currentMainName
					local grpSubID = (row.isSubRow and row.subGroupKey and subItemByGroup[row.subGroupKey]) or safeNumber(row.subCraftItemID)
					local grpSubProf = (row.isSubRow and row.subGroupKey and subProfByGroup[row.subGroupKey]) or row.subCraftProf

					local rowID = safeNumber(row.itemID)
					if (not rowID or rowID <= 0) and type(row.name) == "string" and lookupID then
						rowID = safeNumber(lookupID(row.name))
					end
					local rowName = (rowID and rowID > 0 and itemSearchName(rowID)) or row.name or (rowID and ("Item #" .. tostring(rowID))) or ""
					local rowQty = tonumber(row.qty) or 0
					local ownedUsed = tonumber(row.ownedUsed) or 0

					-- Record direct child reagent hint for synthetic recipes that lack catalog reagents
					if parentTask and rowID and rowID > 0 and (rowQty + ownedUsed) > 0 then
						local pList = childReagentsByParent[parentTask.taskKey]
						if not pList then
							pList = {}
							childReagentsByParent[parentTask.taskKey] = pList
						end
						pList[#pList + 1] = { itemID = rowID, name = rowName, totalQty = rowQty + ownedUsed }
					end

					-- Stage 3 (Owned Allocation): fires even on split rows that also have qty > 0
					if ownedUsed > 0 and rowName ~= "" then
						local oKey = (rowID and rowID > 0) and rowID or rowName
						local oRec = ownedByKey[oKey]
						if not oRec then
							oRec = {
								itemID = (rowID and rowID > 0) and rowID or nil,
								name = rowName,
								totalNeeded = 0,
								provenance = {},
							}
							ownedByKey[oKey] = oRec
							ownedOrder[#ownedOrder + 1] = oRec
						end
						oRec.totalNeeded = oRec.totalNeeded + math.max(1, math.floor(ownedUsed + 0.5))
						appendRowProvenance(oRec.provenance, row, ownedUsed, grpMainID, grpSubID, grpSubProf, grpMainName)
					end

					if rowQty > 0 then
						if row.makeMyself == true then
							-- Stage 4 (Sub-Craft)
							local rec = resolveRowRecipe(row, false)
							if rec then
								local tName = (type(row.categoryName) == "string" and row.categoryName ~= "" and row.categoryName)
									or grpMainName or title
								local subTask = addOrMergeCraftTask("sub_craft", d, rec, row, tName, grpMainID)
								if parentTask then addDepEdge(subTask, parentTask) end
								craftStack[d] = subTask
							end
						elseif row.isVendor == true then
							-- Stage 2 (Vendor Leaf)
							local vKey = (rowID and rowID > 0) and rowID or rowName
							if vKey and vKey ~= "" then
								local rowUnit = safeNumber(row.vendorUnitPrice) or safeNumber(row.ahUnitPrice) or safeNumber(row.unitPrice)
								if (not rowUnit or rowUnit <= 0) and safeNumber(row.lineCost) and row.lineCost > 0 then
									rowUnit = math.floor(row.lineCost / rowQty + 0.5)
								end
								if (not rowUnit or rowUnit <= 0) and rowID and rowID > 0 and ns.GetVendorBuyPrice then
									rowUnit = safeNumber(ns.GetVendorBuyPrice(rowID, ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[rowID], true))
								end
								local vRec = vendorByKey[vKey]
								if not vRec then
									vRec = {
										itemID = (rowID and rowID > 0) and rowID or nil,
										name = rowName,
										needed = 0,
										costSum = 0,
										pricedQty = 0,
										provenance = {},
									}
									vendorByKey[vKey] = vRec
									vendorOrder[#vendorOrder + 1] = vRec
								end
								local addQ = math.max(1, math.floor(rowQty + 0.5))
								vRec.needed = vRec.needed + addQ
								if rowUnit and rowUnit > 0 then
									vRec.costSum = vRec.costSum + (rowUnit * addQ)
									vRec.pricedQty = vRec.pricedQty + addQ
								end
								appendRowProvenance(vRec.provenance, row, addQ, grpMainID, grpSubID, grpSubProf, grpMainName)
							end
						else
							-- Stage 1 (AH Leaf)
							local aKey = (rowID and rowID > 0) and rowID or rowName
							if aKey and aKey ~= "" then
								local rowUnit = safeNumber(row.ahUnitPrice) or safeNumber(row.ahUnit) or safeNumber(row.unitPrice)
								if (not rowUnit or rowUnit <= 0) and safeNumber(row.lineCost) and row.lineCost > 0 then
									rowUnit = math.floor(row.lineCost / rowQty + 0.5)
								end
								local existing = ahByKey[aKey]
								local addQ = math.max(1, math.floor(rowQty + 0.5))
								if existing then
									existing.quantity = existing.quantity + addQ
									local meta = ahMetaByKey[aKey]
									if meta then
										if rowUnit and rowUnit > 0 then
											meta.costSum = meta.costSum + rowUnit * addQ
											meta.pricedQty = meta.pricedQty + addQ
										end
										local rCap = tonumber(row.maxBuyUnit)
										if rCap and rCap > 0 then
											meta.maxBuyUnit = (meta.maxBuyUnit and meta.maxBuyUnit > 0) and math.min(meta.maxBuyUnit, rCap) or rCap
										end
										local rBE = tonumber(row.breakEvenUnit)
										if rBE and rBE > 0 then
											meta.breakEvenUnit = (meta.breakEvenUnit and meta.breakEvenUnit > 0) and math.min(meta.breakEvenUnit, rBE) or rBE
										end
									end
								else
									local term = { searchString = rowName, isExact = true, quantity = addQ, itemID = (rowID and rowID > 0) and rowID or nil }
									ahTerms[#ahTerms + 1] = term
									ahByKey[aKey] = term
									local rCap = tonumber(row.maxBuyUnit)
									local rBE = tonumber(row.breakEvenUnit)
									ahMetaByKey[aKey] = {
										costSum = (rowUnit and rowUnit > 0) and (rowUnit * addQ) or 0,
										pricedQty = (rowUnit and rowUnit > 0) and addQ or 0,
										maxBuyUnit = (rCap and rCap > 0) and rCap or nil,
										breakEvenUnit = (rBE and rBE > 0) and rBE or nil,
										provenance = {},
									}
								end
								local meta = ahMetaByKey[aKey]
								if meta then
									appendRowProvenance(meta.provenance, row, addQ, grpMainID, grpSubID, grpSubProf, grpMainName)
								end
							end
						end
					end
				end
			end
		end

		-- Populate Stage 1 (AH)
		local ahItems = orderFlow.stages.ah.items
		for _, t in ipairs(ahTerms) do
			local aKey = t.itemID or t.searchString
			local meta = aKey and ahMetaByKey[aKey]
			local targetUnit = (meta and meta.pricedQty > 0) and math.floor(meta.costSum / meta.pricedQty + 0.5) or nil
			local entry = buildAHEntryFromTerm({
				searchString = t.searchString,
				isExact = t.isExact,
				quantity = t.quantity,
				itemID = t.itemID,
				unitPrice = targetUnit,
				maxBuyUnit = meta and meta.maxBuyUnit or nil,
				breakEvenUnit = meta and meta.breakEvenUnit or nil,
				provenance = meta and meta.provenance or {},
			}, title)
			if entry then
				ahItems[#ahItems + 1] = entry
			end
		end

		-- Populate Stage 2 (Vendor)
		local vItems = orderFlow.stages.vendor.items
		local vBase = orderFlow.stages.vendor.baselineBagQty
		for _, vRec in ipairs(vendorOrder) do
			local unitP = (vRec.pricedQty > 0) and math.floor(vRec.costSum / vRec.pricedQty + 0.5) or 0
			local hint, npcID = OrderFlow.LookupVendorHint(vRec.itemID)
			vItems[#vItems + 1] = {
				itemID = vRec.itemID,
				name = vRec.name,
				needed = vRec.needed,
				bought = 0,
				remaining = vRec.needed,
				unitPrice = unitP,
				liveUnit = nil,
				totalPrice = unitP * vRec.needed,
				inStockHere = false,
				merchantSlot = nil,
				maxStack = nil,
				stackCount = 1,
				numAvailable = -1,
				hasExtendedCost = false,
				vendorHint = hint,
				vendorNpcID = npcID,
				status = "pending",
				provenance = vRec.provenance,
			}
			if vRec.itemID and vRec.itemID > 0 then
				vBase[vRec.itemID] = getLiveBagCount(vRec.itemID)
			end
		end

		-- Pass 2: Owned Bucket Splitting (Stage 2 Collect priority: Inventory/bags -> mail -> bank -> alt)
		local cItems = orderFlow.stages.collect.items
		local cBase = orderFlow.stages.collect.baselineBagQty
		local collectSeq = 0
		for _, oRec in ipairs(ownedOrder) do
			local ok, owned = pcall(ownershipFn, oRec.itemID, oRec.name)
			owned = (ok and type(owned) == "table") and owned or { bags = getLiveBagCount(oRec.itemID), bank = 0, mail = 0, alts = {} }
			local bagsHave = math.max(0, math.floor((tonumber(owned.bags) or 0) + 0.5))
			local bankHave = math.max(0, math.floor((tonumber(owned.bank) or 0) + 0.5))
			local mailHave = math.max(0, math.floor((tonumber(owned.mail) or 0) + 0.5))
			if oRec.itemID and oRec.itemID > 0 then
				cBase[oRec.itemID] = bagsHave
			end
			local rem = oRec.totalNeeded
			local idStr = tostring(oRec.itemID or oRec.name)
			local bagsEntry = nil

			local useBags = math.min(rem, bagsHave)
			if useBags > 0 then
				collectSeq = collectSeq + 1
				bagsEntry = {
					_order = collectSeq,
					key = idStr .. ":bags",
					itemID = oRec.itemID,
					name = oRec.name,
					source = "bags",
					needed = useBags,
					collected = useBags,
					remaining = 0,
					altOwners = {},
					altLabel = nil,
					availableHere = useBags,
					status = "done",
					provenance = cloneProvenanceList(oRec.provenance, useBags, oRec.totalNeeded),
				}
				cItems[#cItems + 1] = bagsEntry
				rem = rem - useBags
			end

			local useMail = math.min(rem, mailHave)
			if useMail > 0 then
				collectSeq = collectSeq + 1
				cItems[#cItems + 1] = {
					_order = collectSeq,
					key = idStr .. ":mail",
					itemID = oRec.itemID,
					name = oRec.name,
					source = "mail",
					needed = useMail,
					collected = 0,
					remaining = useMail,
					altOwners = {},
					altLabel = nil,
					availableHere = 0,
					status = "pending",
					provenance = cloneProvenanceList(oRec.provenance, useMail, oRec.totalNeeded),
				}
				rem = rem - useMail
			end

			local useBank = math.min(rem, bankHave)
			if useBank > 0 then
				collectSeq = collectSeq + 1
				cItems[#cItems + 1] = {
					_order = collectSeq,
					key = idStr .. ":bank",
					itemID = oRec.itemID,
					name = oRec.name,
					source = "bank",
					needed = useBank,
					collected = 0,
					remaining = useBank,
					altOwners = {},
					altLabel = nil,
					availableHere = 0,
					status = "pending",
					provenance = cloneProvenanceList(oRec.provenance, useBank, oRec.totalNeeded),
				}
				rem = rem - useBank
			end

			if rem > 0 and type(owned.alts) == "table" and #owned.alts > 0 then
				local matchedAlts = {}
				for _, a in ipairs(owned.alts) do
					if type(a) == "table" and (tonumber(a.qty) or 0) > 0 then
						matchedAlts[#matchedAlts + 1] = {
							name = tostring(a.name or "Alt"),
							location = tostring(a.location or "Bags"),
							qty = math.floor((tonumber(a.qty) or 0) + 0.5),
						}
					end
				end
				if #matchedAlts > 0 then
					local altParts = {}
					for _, a in ipairs(matchedAlts) do
						altParts[#altParts + 1] = string.format("%s (%s %dx)", a.name, a.location, a.qty)
					end
					collectSeq = collectSeq + 1
					cItems[#cItems + 1] = {
						_order = collectSeq,
						key = idStr .. ":alt",
						itemID = oRec.itemID,
						name = oRec.name,
						source = "alt",
						needed = rem,
						collected = 0,
						remaining = rem,
						altOwners = matchedAlts,
						altLabel = "On Alt: " .. table.concat(altParts, ", "),
						availableHere = 0,
						status = "alt_info",
						provenance = cloneProvenanceList(oRec.provenance, rem, oRec.totalNeeded),
					}
					rem = 0
				end
			end

			if rem > 0 then
				if bagsEntry then
					bagsEntry.needed = bagsEntry.needed + rem
					bagsEntry.collected = bagsEntry.collected + rem
					bagsEntry.availableHere = bagsEntry.needed
				else
					collectSeq = collectSeq + 1
					cItems[#cItems + 1] = {
						_order = collectSeq,
						key = idStr .. ":bags",
						itemID = oRec.itemID,
						name = oRec.name,
						source = "bags",
						needed = rem,
						collected = rem,
						remaining = 0,
						altOwners = {},
						altLabel = nil,
						availableHere = rem,
						status = "done",
						provenance = cloneProvenanceList(oRec.provenance, rem, oRec.totalNeeded),
					}
				end
			end
		end
		sortCollectItems()
		selectNextPendingCollectInternal(1, nil)

		-- Pass 3: Bottom-Up Topological Sort (Kahn's Algorithm for Stage 4)
		for _, task in ipairs(craftTaskOrder) do
			if #task.reagents == 0 and childReagentsByParent[task.taskKey] then
				local seenRg = {}
				local crafts = math.max(1, task.neededCrafts)
				for _, cr in ipairs(childReagentsByParent[task.taskKey]) do
					if not seenRg[cr.itemID] then
						seenRg[cr.itemID] = true
						task.reagents[#task.reagents + 1] = {
							itemID = cr.itemID,
							name = cr.name,
							qtyPerCraft = math.max(1, math.floor((cr.totalQty / crafts) + 0.5)),
						}
					end
				end
			end
		end

		local inDegree = {}
		local dependents = {}
		for _, task in ipairs(craftTaskOrder) do
			inDegree[task.taskKey] = 0
			dependents[task.taskKey] = {}
		end
		for _, task in ipairs(craftTaskOrder) do
			local seenDep = {}
			for _, depKey in ipairs(task.dependsOn or {}) do
				if depKey ~= task.taskKey and craftTasksByKey[depKey] and not seenDep[depKey] then
					seenDep[depKey] = true
					inDegree[task.taskKey] = inDegree[task.taskKey] + 1
					dependents[depKey][#dependents[depKey] + 1] = task.taskKey
				end
			end
		end

		local function compareReadyTasks(a, b)
			if (a.depth or 0) ~= (b.depth or 0) then
				return (a.depth or 0) > (b.depth or 0)
			end
			if (a.isSubCraft == true) ~= (b.isSubCraft == true) then
				return a.isSubCraft == true
			end
			if (a.profKey or "") ~= (b.profKey or "") then
				return (a.profKey or "") < (b.profKey or "")
			end
			return (a.discoveryOrder or 0) < (b.discoveryOrder or 0)
		end

		local ready = {}
		for _, task in ipairs(craftTaskOrder) do
			if inDegree[task.taskKey] == 0 then
				ready[#ready + 1] = task
			end
		end
		local sortedTasks = {}
		local emitted = {}
		while #ready > 0 do
			table.sort(ready, compareReadyTasks)
			local cur = table.remove(ready, 1)
			sortedTasks[#sortedTasks + 1] = cur
			emitted[cur.taskKey] = true
			for _, parentKey in ipairs(dependents[cur.taskKey] or {}) do
				inDegree[parentKey] = inDegree[parentKey] - 1
				if inDegree[parentKey] == 0 and not emitted[parentKey] then
					ready[#ready + 1] = craftTasksByKey[parentKey]
				end
			end
		end
		if #sortedTasks < #craftTaskOrder then
			local cyclic = {}
			for _, task in ipairs(craftTaskOrder) do
				if not emitted[task.taskKey] then
					cyclic[#cyclic + 1] = task
				end
			end
			table.sort(cyclic, function(a, b)
				if (a.depth or 0) ~= (b.depth or 0) then return (a.depth or 0) > (b.depth or 0) end
				if (a.isSubCraft == true) ~= (b.isSubCraft == true) then return a.isSubCraft == true end
				return (a.discoveryOrder or 0) < (b.discoveryOrder or 0)
			end)
			for _, task in ipairs(cyclic) do
				sortedTasks[#sortedTasks + 1] = task
			end
		end
		orderFlow.stages.craft.tasks = sortedTasks
		orderFlow.stages.craft.activeIndex = 1

		-- Pass 4: Populate Stage 5 (Sell) from Main Order craft outputs (default: AH Sell)
		local sellItems, sellByKey = {}, {}
		local function getDefaultSellPricing(itemID)
			local vendorSell = 0
			if ns.GetVendorSellPrice and itemID and itemID > 0 then
				local okV, v = pcall(ns.GetVendorSellPrice, itemID)
				if okV and safeNumber(v) and v > 0 then vendorSell = math.floor(v) end
			end
			local costBasis = 0
			if type(ns.GetItemCostBasis) == "function" and itemID and itemID > 0 then
				local okC, c = pcall(ns.GetItemCostBasis, itemID)
				if okC and safeNumber(c) and c > 0 then costBasis = math.floor(c) end
			elseif ns.GetItemCraftOption and itemID and itemID > 0 then
				local okC, opt = pcall(ns.GetItemCraftOption, itemID)
				if okC and tableValue(opt) and safeNumber(opt.unitCraftCost) and opt.unitCraftCost > 0 then
					costBasis = math.floor(opt.unitCraftCost + 0.5)
				end
			end
			local marketRef = 0
			if ns.GetItemMarketPrice and itemID and itemID > 0 then
				local okM, mp = pcall(ns.GetItemMarketPrice, itemID)
				if okM and safeNumber(mp) and mp > 0 then marketRef = math.floor(mp + 0.5) end
			end
			local cut = (type(ns.GetDynamicAHCut) == "function" and ns.GetDynamicAHCut()) or 0.05
			if cut <= 0 or cut >= 0.99 then cut = 0.05 end
			local vendorFloor = (vendorSell > 0) and math.ceil(vendorSell / (1 - cut)) or 0
			local costFloor = (costBasis > 0) and math.ceil(costBasis / (1 - cut)) or 0
			local defaultMin = math.max(vendorFloor, costFloor)
			local defaultFixed = (marketRef > 0) and marketRef or math.max(defaultMin, vendorSell * 2, 100)
			return vendorSell, costBasis, marketRef, defaultMin, defaultFixed
		end

		for _, task in ipairs(sortedTasks) do
			if not task.isSubCraft and task.itemID and task.itemID > 0 then
				local sKey = task.itemID
				local craftsN = math.max(1, math.floor((tonumber(task.neededCrafts) or 1) + 0.5))
				local perCraft = math.max(1, math.floor((tonumber(task.outputsPerCraft) or 1) + 0.5))
				local addQty = math.max(1, craftsN * perCraft, math.floor((tonumber(task.neededOutputs) or 1) + 0.5))
				local existing = sellByKey[sKey]
				if existing then
					existing.totalQty = existing.totalQty + addQty
					existing.needed = existing.totalQty
					existing.remaining = math.max(0, existing.totalQty - (existing.soldQty or 0))
				else
					local vendorSell, costBasis, marketRef = getDefaultSellPricing(task.itemID)
					local ciInfo = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
					local qMeta, iLvlMeta, classMeta, linkMeta, isReagMeta = 1, 0, nil, nil, false
					if type(ciInfo) == "function" then
						local okI, _, lnk, q, ilvl, _, _, _, _, _, _, sp, cid, _, _, _, _, isReag = pcall(ciInfo, task.itemID)
						if okI then
							if readable(lnk) and type(lnk) == "string" then linkMeta = lnk end
							if safeNumber(q) then qMeta = math.floor(q) end
							if safeNumber(ilvl) then iLvlMeta = math.floor(ilvl) end
							if safeNumber(cid) then classMeta = math.floor(cid) end
							if vendorSell <= 0 and safeNumber(sp) and sp > 0 then vendorSell = math.floor(sp) end
							if readable(isReag) then isReagMeta = (isReag == true) end
						end
					end
					local entry = {
						itemID = task.itemID,
						itemLink = linkMeta,
						name = task.name or itemSearchName(task.itemID) or ("Item #" .. tostring(task.itemID)),
						quality = qMeta,
						itemLevel = iLvlMeta,
						classID = classMeta,
						isCraftingReagent = isReagMeta,
						isFromBag = false,
						totalQty = addQty,
						needed = addQty,
						soldQty = 0,
						remaining = addQty,
						postQty = nil,
						inBags = getSellableBagCount(task.itemID, false, linkMeta),
						channel = "ah",
						liveUnit = nil,
						liveIsOwn = false,
						liveCheckedAt = 0,
						existingValue = nil,
						priceThreshold = nil,
						currentListings = nil,
						listingsScanned = false,
						marketRef = marketRef,
						vendorSell = vendorSell,
						costBasis = costBasis,
						customPrice = nil,
						bidPrice = 0,
						status = "pending",
						provenance = cloneProvenanceList(task.provenance, addQty, addQty),
					}
					sellByKey[sKey] = entry
					sellItems[#sellItems + 1] = entry
				end
			end
		end
		orderFlow.stages.sell.items = sellItems
		orderFlow.stages.sell.activeIndex = 1

		if prevSnap then
			local keptAHSpent, keptVenSpent = false, false
			for _, it in ipairs(ahItems) do
				local k = it.itemID or (type(it.name) == "string" and it.name:lower())
				local old = k and prevSnap.ah[k]
				if old then
					local mailCol = prevSnap.collect and prevSnap.collect["mail:" .. tostring(k)]
					local mailCollected = mailCol and (tonumber(mailCol.collected) or 0) or 0
					local netBought = math.max(0, (tonumber(old.bought) or 0) - mailCollected)
					local b = math.max(0, math.min(it.needed or 1, math.floor(netBought + 0.5)))
					if b > 0 then
						it.bought = b
						it.remaining = math.max(0, (it.needed or 1) - b)
						it.totalPrice = (it.unitPrice or 0) * it.remaining
						keptAHSpent = true
					end
					if it.remaining <= 0 then
						it.status = "done"
					elseif old.skipped then
						it.status = "skipped"
					end
				end
			end
			if keptAHSpent and prevSnap.ahSpent > 0 then
				orderFlow.stages.ah.spentCopper = prevSnap.ahSpent
			end
			for _, it in ipairs(cItems) do
				if it.source ~= "bags" and it.source ~= "alt" then
					local base = it.itemID or (type(it.name) == "string" and it.name:lower())
					local old = base and prevSnap.collect[tostring(it.source or "") .. ":" .. tostring(base)]
					if old then
						local col = math.max(0, math.min(it.needed or 1, math.floor(old.collected + 0.5)))
						if col > 0 then
							it.collected = col
							it.remaining = math.max(0, (it.needed or 1) - col)
						end
						if it.remaining <= 0 then
							it.status = "done"
						elseif old.skipped then
							it.status = "skipped"
						end
					end
				end
			end
			for _, it in ipairs(vItems) do
				local k = it.itemID or (type(it.name) == "string" and it.name:lower())
				local old = k and prevSnap.vendor[k]
				if old then
					local b = math.max(0, math.min(it.needed or 1, math.floor(old.bought + 0.5)))
					if b > 0 then
						it.bought = b
						it.remaining = math.max(0, (it.needed or 1) - b)
						it.totalPrice = (it.unitPrice or 0) * it.remaining
						keptVenSpent = true
					end
					if it.remaining <= 0 then
						it.status = "done"
					elseif old.skipped then
						it.status = "skipped"
					end
				end
			end
			if keptVenSpent and prevSnap.venSpent > 0 then
				orderFlow.stages.vendor.spentCopper = prevSnap.venSpent
			end
			for _, t in ipairs(sortedTasks) do
				local old = (t.taskKey and prevSnap.craft[t.taskKey])
					or ((t.profKey and t.spellID) and prevSnap.craftBySpell[tostring(t.profKey) .. ":" .. tostring(t.spellID)])
				if old then
					if old.measuredCastMs and old.measuredCastMs > 0 then
						t.measuredCastMs = old.measuredCastMs
					end
					local cc = math.max(0, math.min(t.neededCrafts or 1, math.floor(old.completedCrafts + 0.5)))
					if cc > 0 then
						t.completedCrafts = cc
						t.remainingCrafts = math.max(0, (t.neededCrafts or 1) - cc)
					end
					if (t.remainingCrafts or 0) <= 0 then
						t.status = "done"
					elseif old.skipped then
						t.status = "skipped"
					end
				end
			end
			if prevSnap.sellMeta then
				local sl = orderFlow.stages.sell
				sl.duration = (prevSnap.sellMeta.duration == 1 or prevSnap.sellMeta.duration == 2 or prevSnap.sellMeta.duration == 3) and prevSnap.sellMeta.duration or 2
				sl.undercutMode = (prevSnap.sellMeta.undercutMode == "match" or prevSnap.sellMeta.undercutMode == "1c" or prevSnap.sellMeta.undercutMode == "1s" or prevSnap.sellMeta.undercutMode == "pct") and prevSnap.sellMeta.undercutMode or "match"
				sl.undercutPct = tonumber(prevSnap.sellMeta.undercutPct) or 1
				sl.totalEarnedCopper = tonumber(prevSnap.sellMeta.totalEarnedCopper) or 0
			end
			if prevSnap.pipelineComplete then
				prevSnap.ah, prevSnap.collect, prevSnap.vendor, prevSnap.craft, prevSnap.craftBySpell = {}, {}, {}, {}, {}
				prevSnap.ahSpent, prevSnap.venSpent = 0, 0
			end
			for _, it in ipairs(sellItems) do
				local k = it.itemID or (type(it.name) == "string" and it.name:lower())
				local old = k and prevSnap.sell and prevSnap.sell[k]
				if old and (not prevSnap.pipelineComplete or old.isFromBag) then
					if old.channel == "vendor" or old.channel == "ah" then it.channel = old.channel end
					if old.customPrice ~= nil then it.customPrice = old.customPrice end
					if old.bidPrice ~= nil then it.bidPrice = math.max(0, math.floor((tonumber(old.bidPrice) or 0) + 0.5)) end
					if old.postQty ~= nil then it.postQty = math.max(0, math.floor((tonumber(old.postQty) or 0) + 0.5)) end
					if old.customQty and old.totalQty and old.totalQty > 0 then
						it.totalQty = math.max(1, math.floor(old.totalQty + 0.5))
						it.needed = it.totalQty
						it.customQty = true
						it.remaining = math.max(0, it.totalQty - (it.soldQty or 0))
					end
					local sq = math.max(0, math.min(it.totalQty or 1, math.floor((tonumber(old.soldQty) or 0) + 0.5)))
					if sq > 0 then
						it.soldQty = sq
						it.remaining = math.max(0, (it.totalQty or 1) - sq)
					end
					if (it.remaining or 0) <= 0 then
						it.status = "done"
					elseif old.skipped then
						it.status = "skipped"
					end
				end
			end
			sortCollectItems()
			selectNextPendingAH(1)
			selectNextPendingCollectInternal(1, nil)
			selectNextPendingVendorInternal(1, orderFlow.env.atVendor)
			selectNextPendingCraftInternal(1, orderFlow.env.openProfKey)
		end

		-- Live scans if any supported WoW frame is already open
		if orderFlow.env.atVendor then OrderFlow.ScanOpenVendor() end
		if orderFlow.env.atBank then OrderFlow.ScanOpenBank() end
		if orderFlow.env.atMail then OrderFlow.ScanOpenMailbox() end

		-- Pick initial stage (1. AH -> 2. Collect -> 3. Vendor -> 4. Craft)
		local ahRem = OrderFlow.GetStageStats("ah").remaining or 0
		local colActRem = OrderFlow.GetStageStats("collect").actionableRemaining or 0
		local venRem = OrderFlow.GetStageStats("vendor").remaining or 0
		local crRem = OrderFlow.GetStageStats("craft").remaining or 0
		if ahRem > 0 then
			orderFlow.activeStage = "ah"
		elseif colActRem > 0 then
			orderFlow.activeStage = "collect"
		elseif venRem > 0 then
			orderFlow.activeStage = "vendor"
		elseif crRem > 0 then
			orderFlow.activeStage = "craft"
		elseif #ahItems > 0 then
			orderFlow.activeStage = "ah"
		elseif #cItems > 0 then
			orderFlow.activeStage = "collect"
		elseif #vItems > 0 then
			orderFlow.activeStage = "vendor"
		elseif #sortedTasks > 0 then
			orderFlow.activeStage = "craft"
		else
			orderFlow.activeStage = "ah"
		end

		notifyOrderFlow()
		return {
			ah = #ahItems,
			collect = #cItems,
			vendor = #vItems,
			craft = #sortedTasks,
			sell = #sellItems,
		}
	end

	-----------------------------------------------------------------------------------------------
	-- 4.2 Cross-Stage Destination Filter
	-----------------------------------------------------------------------------------------------
	function OrderFlow.GetAllDestinations()
		if orderFlow.destCache then
			return orderFlow.destCache
		end
		local out = {}
		local byKey = {}

		local function collectFromStage(stageKey, list)
			for idx, it in ipairs(list or {}) do
				local provList = it.provenance
				if type(provList) == "table" and #provList > 0 then
					local isDone, uPrice, neededTotal, doneCount
					if stageKey == "craft" then
						isDone = (it.status == "done" or it.status == "skipped" or (it.remainingCrafts or 0) <= 0)
						uPrice = 0
						neededTotal = it.neededCrafts or 1
						doneCount = it.completedCrafts or 0
					elseif stageKey == "collect" then
						isDone = (it.status == "done" or it.status == "skipped" or (it.remaining or 0) <= 0)
						uPrice = 0
						neededTotal = it.needed or 1
						doneCount = it.collected or 0
					else
						isDone = (it.status == "done" or it.status == "skipped" or (it.remaining or 0) <= 0)
						uPrice = (it.liveUnit and it.liveUnit > 0) and it.liveUnit or (it.targetUnit or it.unitPrice or 0)
						neededTotal = it.needed or 1
						doneCount = it.bought or 0
					end
					local seenForItem = {}
					for _, p in ipairs(provList) do
						local tName = p.targetName or orderFlow.title or "Shopping List"
						local sKind = p.sourceKind or "shopping"
						local sLabel = p.sourceLabel or "Shopping"
						local dKey = tName
						local dest = byKey[dKey]
						if not dest then
							dest = {
								key = dKey,
								targetName = tName,
								sourceKind = sKind,
								sourceLabel = sLabel,
								items = {},
								itemIndices = {},
								totalItems = 0,
								boughtItems = 0,
								totalMats = 0,
								boughtMats = 0,
								totalUnits = 0,
								boughtUnits = 0,
								estCopper = 0,
							}
							byKey[dKey] = dest
							out[#out + 1] = dest
						end
						local pQty = math.max(1, math.floor((tonumber(p.qty) or neededTotal or 1) + 0.5))
						dest.items[#dest.items + 1] = {
							stage = stageKey,
							index = idx,
							itemID = it.itemID,
							name = it.name,
							qty = pQty,
							subCraftName = p.subCraftName,
							done = isDone,
							priceAlert = it.priceAlert,
							priceDeltaPct = it.priceDeltaPct,
						}
						dest.totalUnits = dest.totalUnits + pQty
						if isDone then
							dest.boughtUnits = dest.boughtUnits + pQty
						elseif neededTotal > 0 and doneCount > 0 then
							dest.boughtUnits = dest.boughtUnits + math.min(pQty, doneCount)
						end
						dest.estCopper = dest.estCopper + (uPrice * pQty)
						local itemKey = stageKey .. ":" .. tostring(idx) .. ":" .. dKey
						if not seenForItem[itemKey] then
							seenForItem[itemKey] = true
							if stageKey == "ah" then
								dest.itemIndices[#dest.itemIndices + 1] = idx
							end
							dest.totalItems = dest.totalItems + 1
							dest.totalMats = dest.totalItems
							if isDone then
								dest.boughtItems = dest.boughtItems + 1
								dest.boughtMats = dest.boughtItems
							end
						end
					end
				end
			end
		end

		collectFromStage("ah", orderFlow.stages.ah.items)
		collectFromStage("collect", orderFlow.stages.collect.items)
		collectFromStage("vendor", orderFlow.stages.vendor.items)
		collectFromStage("craft", orderFlow.stages.craft.tasks)
		orderFlow.destCache = out
		return out
	end

	function OrderFlow.GetDestinationFilter()
		return orderFlow.selectedDestKey
	end

	function OrderFlow.GetVisibleStageEntries(stageKey)
		stageKey = stageKey or orderFlow.activeStage or "ah"
		local list = (stageKey == "craft") and (orderFlow.stages.craft.tasks or {})
			or ((orderFlow.stages[stageKey] and orderFlow.stages[stageKey].items) or {})
		local out = {}
		local destKey = orderFlow.selectedDestKey
		for idx, it in ipairs(list) do
			if not destKey or destKey == "" then
				out[#out + 1] = { index = idx, item = it, destQty = it.needed or it.neededCrafts or 1 }
			else
				local dQty = itemDestQty(it, destKey)
				if dQty ~= nil then
					out[#out + 1] = { index = idx, item = it, destQty = dQty }
				end
			end
		end
		return out
	end

	function OrderFlow.SetDestinationFilter(destKeyOrNil)
		if destKeyOrNil == nil or destKeyOrNil == "" or destKeyOrNil == orderFlow.selectedDestKey then
			orderFlow.selectedDestKey = nil
			notifyOrderFlow()
			return nil
		end
		orderFlow.selectedDestKey = destKeyOrNil
		local stKey = orderFlow.activeStage or "ah"
		local stObj = orderFlow.stages[stKey]
		local vis = OrderFlow.GetVisibleStageEntries(stKey)
		if stObj and #vis > 0 then
			local curInVis = false
			for _, v in ipairs(vis) do
				if v.index == stObj.activeIndex then
					curInVis = true
					break
				end
			end
			if not curInVis then
				local picked = nil
				for _, v in ipairs(vis) do
					local it = v.item
					local rem = (stKey == "craft") and (it and it.remainingCrafts or 0) or (it and it.remaining or 0)
					if it and rem > 0 and it.status ~= "done" and it.status ~= "skipped" and it.status ~= "alt_info" then
						picked = v.index
						break
					end
				end
				stObj.activeIndex = picked or vis[1].index
			end
		end
		notifyOrderFlow()
		return orderFlow.selectedDestKey
	end

	-----------------------------------------------------------------------------------------------
	-- Stage 1 (AH) Event Hooks
	-----------------------------------------------------------------------------------------------
	function OrderFlow.OnAuctionHouseShow()
		orderFlow.env.atAH = atAH() and true or false
		orderFlow.stages.ah.waitingForAH = (not orderFlow.env.atAH)
		local ah = orderFlow.stages.ah
		local sl = orderFlow.stages.sell
		local ahRem = OrderFlow.GetStageStats("ah").remaining or 0
		if sl and sl.items then
			for _, it in ipairs(sl.items) do
				if it.itemID and it.itemID > 0 then it.inBags = getSellableBagCount(it.itemID, it.channel == "vendor", it.itemLink) end
			end
		end
		if #ah.items == 0 then
			notifyOrderFlow()
			return false
		end
		if orderFlow.env.atAH and ahRem > 0 then
			orderFlow.activeStage = "ah"
		end
		local idx = selectNextPendingAH(ah.activeIndex or 1) or selectNextPendingAH(1)
		if idx and orderFlow.env.atAH then
			return CartBuyer.OpenInAH(idx)
		end
		notifyOrderFlow()
		return false
	end

	function OrderFlow.OnAuctionHouseClosed()
		if orderFlow.stages.ah and orderFlow.stages.ah.directBuy and CartBuyer.CancelDirectBuy then
			CartBuyer.CancelDirectBuy(nil, { silent = true, cancelServer = false })
		end
		orderFlow.env.atAH = false
		orderFlow.active = false
		orderFlow.stages.ah.waitingForAH = true
		orderFlow.stages.ah.pendingExternal = nil
		orderFlow.stages.ah.pendingExternalBid = nil
		orderFlow.stages.ah.externalBidSerial = (orderFlow.stages.ah.externalBidSerial or 0) + 1
		orderFlow.stages.ah.directBuy = nil
		orderFlow.stages.ah.selfBidInFlight = false
		local sl = orderFlow.stages.sell
		if sl then
			sl.postSerial = (sl.postSerial or 0) + 1
			sl.searchSerial = (sl.searchSerial or 0) + 1
			sl.pendingPost = nil
			sl.pendingSearch = nil
			sl.pendingKeyPrime = nil
			sl.warningConfirm = nil
			sl.postAllActive = false
			sl.throttleBlockedAt = nil
		end
		if ns.AHChannel and ns.AHChannel.Release then
			ns.AHChannel.Release("cart_buyer")
			ns.AHChannel.Release("orderflow_sell")
		end
		for _, it in ipairs(orderFlow.stages.ah.items or {}) do
			if it.status == "active" and (it.remaining or 0) > 0 then
				it.status = "pending"
			end
		end
		notifyOrderFlow()
	end

	-----------------------------------------------------------------------------------------------
	-- 4.3 Stage 2 (Vendor) API
	-----------------------------------------------------------------------------------------------
	function OrderFlow.ScanOpenVendor()
		orderFlow.liveVendorSlots = {}
		orderFlow.liveVendorSlotsByName = {}
		local vItems = orderFlow.stages.vendor.items
		if not orderFlow.env.atVendor or not GetMerchantNumItems then
			for _, it in ipairs(vItems) do
				it.inStockHere = false
				it.merchantSlot = nil
				it.liveUnit = nil
				if it.status == "in_stock" and (it.remaining or 0) > 0 then
					it.status = "pending"
				end
			end
			return 0
		end
		if #vItems == 0 then
			return 0
		end
		local okNum, rawNum = pcall(GetMerchantNumItems)
		local numItems = (okNum and safeNumber(rawNum)) or 0
		local merchantInfoFn = C_MerchantFrame and (C_MerchantFrame.GetItemInfo or C_MerchantFrame.GetMerchantItemInfo)
		for slot = 1, numItems do
			local itemID = nil
			if GetMerchantItemID then
				local okId, mid = pcall(GetMerchantItemID, slot)
				if okId then itemID = safeNumber(mid) end
			end
			local name, price, stackCount, numAvailable, isPurchasable, hasExtendedCost
			if merchantInfoFn then
				local ok, info = pcall(merchantInfoFn, slot)
				if ok and tableValue(info) then
					name = readable(info.name) and info.name or nil
					price = safeNumber(info.price) or safeNumber(info.buyPrice)
					stackCount = safeNumber(info.stackCount) or safeNumber(info.quantity) or safeNumber(info.stackSize)
					numAvailable = safeNumber(info.numAvailable, true)
					if info.isPurchasable ~= nil then
						isPurchasable = (info.isPurchasable ~= false)
					end
					if info.hasExtendedCost ~= nil then
						hasExtendedCost = (info.hasExtendedCost == true)
					end
					if (not itemID or itemID <= 0) and info.itemID then
						itemID = safeNumber(info.itemID)
					end
				end
			end
			if (name == nil or price == nil or stackCount == nil or numAvailable == nil or isPurchasable == nil or hasExtendedCost == nil) and GetMerchantItemInfo then
				local ok, mName, _, mPrice, mQty, mAvail, mPurch, _, mExt = pcall(GetMerchantItemInfo, slot)
				if ok then
					if name == nil and readable(mName) then name = mName end
					if price == nil then price = safeNumber(mPrice) end
					if stackCount == nil then stackCount = safeNumber(mQty) end
					if numAvailable == nil then numAvailable = safeNumber(mAvail, true) end
					if isPurchasable == nil then isPurchasable = (mPurch ~= false) end
					if hasExtendedCost == nil then hasExtendedCost = (mExt == true) end
				end
			end
			if (not itemID or itemID <= 0) and GetMerchantItemLink then
				local okL, link = pcall(GetMerchantItemLink, slot)
				if okL and readable(link) and type(link) == "string" then
					itemID = tonumber(link:match("item:(%d+)"))
				end
			end
			if (not itemID or itemID <= 0) and readable(name) and type(name) == "string" and name ~= "" and lookupID then
				local okLid, lid = pcall(lookupID, name)
				if okLid then itemID = safeNumber(lid) end
			end
			if (itemID and itemID > 0) or (readable(name) and type(name) == "string" and name ~= "") then
				local maxStack = 20
				if GetMerchantItemMaxStack then
					local okMs, ms = pcall(GetMerchantItemMaxStack, slot)
					if okMs and safeNumber(ms) and ms > 0 then
						maxStack = ms
					end
				end
				stackCount = math.max(1, stackCount or 1)
				local dispName = (readable(name) and type(name) == "string" and name ~= "") and name
					or (itemID and itemSearchName(itemID))
					or ("Item #" .. tostring(itemID or slot))
				local slotEntry = {
					slot = slot,
					itemID = (itemID and itemID > 0) and itemID or nil,
					name = dispName,
					price = price or 0,
					stackCount = stackCount,
					numAvailable = (numAvailable ~= nil) and numAvailable or -1,
					maxStack = math.max(1, maxStack),
					isPurchasable = (isPurchasable ~= false),
					hasExtendedCost = (hasExtendedCost == true),
				}
				if itemID and itemID > 0 and not orderFlow.liveVendorSlots[itemID] then
					orderFlow.liveVendorSlots[itemID] = slotEntry
				end
				if type(dispName) == "string" and dispName ~= "" and not orderFlow.liveVendorSlotsByName[dispName:lower()] then
					orderFlow.liveVendorSlotsByName[dispName:lower()] = slotEntry
				end
			end
		end

		local stockedCount = 0
		for _, it in ipairs(vItems) do
			local slotInfo = (it.itemID and orderFlow.liveVendorSlots[it.itemID])
				or (type(it.name) == "string" and orderFlow.liveVendorSlotsByName[it.name:lower()])
				or nil
			if slotInfo then
				if (not it.itemID or it.itemID <= 0) and slotInfo.itemID then
					it.itemID = slotInfo.itemID
				end
				it.inStockHere = true
				it.merchantSlot = slotInfo.slot
				it.stackCount = slotInfo.stackCount
				it.packPrice = slotInfo.price
				it.maxStack = slotInfo.maxStack
				it.numAvailable = slotInfo.numAvailable
				it.isPurchasable = (slotInfo.isPurchasable ~= false)
				it.hasExtendedCost = slotInfo.hasExtendedCost
				it.liveUnit = (slotInfo.price > 0) and math.floor((slotInfo.price / slotInfo.stackCount) + 0.5) or it.unitPrice
				if (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
					it.status = "in_stock"
				end
				stockedCount = stockedCount + 1
			else
				it.inStockHere = false
				it.merchantSlot = nil
				it.packPrice = nil
				it.isPurchasable = nil
				it.liveUnit = nil
				if it.status == "in_stock" and (it.remaining or 0) > 0 then
					it.status = "pending"
				end
			end
		end
		return stockedCount
	end

	function OrderFlow.OnMerchantShow()
		local wasAtVendor = (orderFlow.env.atVendor == true)
		orderFlow.env._merchantEventOpen = true
		orderFlow.env._merchantEventFrame = _G.MerchantFrame
		orderFlow.env._merchantFrameSeenShown = isFrameShownSafe(_G.MerchantFrame)
		orderFlow.env._merchantAwaitFrameHide = false
		orderFlow.env.atVendor = true
		local vn = readLiveVendorName()
		if vn then
			orderFlow.env.vendorName = vn
		elseif not wasAtVendor then
			orderFlow.env.vendorName = nil
		end
		local vStShow = orderFlow.stages.vendor
		local vBase = vStShow.baselineBagQty
		for _, it in ipairs(vStShow.items or {}) do
			if it.itemID and (vStShow.pendingBuy == nil or vBase[it.itemID] == nil) then
				vBase[it.itemID] = getLiveBagCount(it.itemID)
			end
		end
		local stocked = OrderFlow.ScanOpenVendor()
		local vStats = OrderFlow.GetStageStats("vendor")
		local ahStats = OrderFlow.GetStageStats("ah")
		local cStats = OrderFlow.GetStageStats("collect")
		if stocked > 0 then
			local vSt = orderFlow.stages.vendor
			local curV = vSt.items and vSt.items[vSt.activeIndex]
			if not wasAtVendor or not curV or not curV.inStockHere or (curV.remaining or 0) <= 0 or curV.status == "done" or curV.status == "skipped" then
				selectNextPendingVendorInternal(1, true)
			end
		end
		if not orderFlow.env._vendorAutoSwitched and vStats.remaining > 0 and (stocked > 0 or ((ahStats.empty or ahStats.complete) and (cStats.empty or cStats.complete))) then
			orderFlow.env._vendorAutoSwitched = true
			orderFlow.activeStage = "vendor"
		end
		notifyOrderFlow()
	end

	function OrderFlow.OnMerchantUpdate()
		if not orderFlow.env.atVendor then
			if isLiveMerchantOpen() then
				OrderFlow.OnMerchantShow()
			end
			return
		end
		local vn = readLiveVendorName()
		if vn then orderFlow.env.vendorName = vn end
		local stocked = OrderFlow.ScanOpenVendor()
		local vStats = OrderFlow.GetStageStats("vendor")
		local ahStats = OrderFlow.GetStageStats("ah")
		local cStats = OrderFlow.GetStageStats("collect")
		if stocked > 0 and not orderFlow.env._vendorAutoSwitched and vStats.remaining > 0 and (stocked > 0 or ((ahStats.empty or ahStats.complete) and (cStats.empty or cStats.complete))) then
			orderFlow.env._vendorAutoSwitched = true
			orderFlow.activeStage = "vendor"
			selectNextPendingVendorInternal(1, true)
		end
		notifyOrderFlow()
	end

	function OrderFlow.OnMerchantClosed()
		orderFlow.env._merchantEventOpen = false
		orderFlow.env._merchantEventFrame = nil
		orderFlow.env._merchantFrameSeenShown = false
		orderFlow.env._merchantAwaitFrameHide = isFrameShownSafe(_G.MerchantFrame)
		orderFlow.env._vendorAutoSwitched = false
		orderFlow.env.atVendor = false
		orderFlow.env.vendorName = nil
		orderFlow.stages.vendor.pendingBuy = nil
		OrderFlow.ScanOpenVendor()
		notifyOrderFlow()
	end

	local function computeVendorBuyChunk(remaining, stackCount, maxStack, availUnits, slotPrice, unitCopper)
		stackCount = math.max(1, tonumber(stackCount) or 1)
		maxStack = math.max(1, tonumber(maxStack) or 20)
		local chunkMax = (stackCount > 1 and maxStack >= stackCount)
			and (math.floor(maxStack / stackCount) * stackCount)
			or math.max(stackCount, maxStack)
		local rawUnits = math.min(remaining, chunkMax)
		if availUnits and availUnits < math.huge then
			rawUnits = math.min(rawUnits, availUnits)
		end
		if rawUnits <= 0 then
			return 0, 0, 0
		end
		local packs = (stackCount > 1) and math.max(1, math.ceil(rawUnits / stackCount)) or rawUnits
		local buyUnits = (stackCount > 1) and (packs * stackCount) or rawUnits
		if stackCount > 1 and buyUnits > chunkMax then
			packs = math.max(1, math.floor(chunkMax / stackCount))
			buyUnits = packs * stackCount
		end
		if availUnits and availUnits < math.huge and buyUnits > availUnits then
			packs = (stackCount > 1) and math.floor(availUnits / stackCount) or math.floor(availUnits)
			buyUnits = (stackCount > 1) and (packs * stackCount) or packs
			if buyUnits <= 0 then
				return 0, 0, 0
			end
		end
		local chunkCost = (stackCount > 1) and (packs * (slotPrice or 0)) or (buyUnits * (unitCopper or 0))
		return buyUnits, chunkCost, packs
	end

	local function isReagentItemSafe(itemID)
		if not itemID or itemID <= 0 then return false end
		local ci = _G.C_Item
		local getInfo = (ci and ci.GetItemInfo) or _G.GetItemInfo
		if type(getInfo) == "function" then
			local ok, _, _, _, _, _, _, _, _, _, _, _, classID, _, _, _, _, isCraftingReagent = pcall(getInfo, itemID)
			if ok then
				if readable(isCraftingReagent) and isCraftingReagent == true then return true end
				local cid = safeNumber(classID)
				if cid == 7 then return true end
				if cid ~= nil then return false end
			end
		end
		-- If uncached/mocked without GetItemInfo, allow ReagentBag fallback
		return true
	end

	local function findFreeGeneralBagSlot(itemID)
		local maxBag = safeNumber(NUM_BAG_SLOTS) or 4
		for b = 0, maxBag do
			local bagFamily = 0
			if b > 0 and C_Container and C_Container.GetContainerNumFreeSlots then
				local ok, _, fam = pcall(C_Container.GetContainerNumFreeSlots, b)
				if ok and safeNumber(fam) then bagFamily = fam end
			elseif b > 0 and GetContainerNumFreeSlots then
				local ok, _, fam = pcall(GetContainerNumFreeSlots, b)
				if ok and safeNumber(fam) then bagFamily = fam end
			end
			if bagFamily == 0 then
				local numSlots = getContainerNumSlotsSafe(b)
				for s = 1, numSlots do
					local sid = getContainerSlotInfoSafe(b, s)
					if not sid then
						return b, s
					end
				end
			end
		end
		-- Forever 16001 / Retail ReagentBag (bag 5) when appropriate for crafting reagents
		local enumIdx = _G.Enum and _G.Enum.BagIndex
		local reagentBag = enumIdx and safeNumber(enumIdx.ReagentBag)
		if reagentBag and reagentBag > maxBag and (itemID == nil or isReagentItemSafe(itemID)) then
			local numSlots = getContainerNumSlotsSafe(reagentBag)
			for s = 1, numSlots do
				local sid = getContainerSlotInfoSafe(reagentBag, s)
				if not sid then
					return reagentBag, s
				end
			end
		end
		return nil, nil
	end

	local function hasBagSpaceForItem(itemID, incomingQty, maxStackOverride)
		local totalSlots = 0
		for _, b in ipairs(getBagContainerList()) do
			totalSlots = totalSlots + getContainerNumSlotsSafe(b)
		end
		if totalSlots <= 0 then
			-- Headless mocks without bag slots configured
			return true
		end
		local fb = findFreeGeneralBagSlot(itemID)
		if fb ~= nil then return true end
		if itemID and itemID > 0 then
			local maxS = safeNumber(maxStackOverride)
			if not maxS or maxS < 1 then
				local ci = _G.C_Item
				local getInfo = (ci and ci.GetItemInfo) or _G.GetItemInfo
				if type(getInfo) == "function" then
					local ok, _, _, _, _, _, _, _, ms = pcall(getInfo, itemID)
					if ok and safeNumber(ms) and ms >= 1 then maxS = math.floor(ms) end
				end
			end
			maxS = math.max(1, math.floor(maxS or 20))
			if maxS > 1 then
				local need = math.max(1, math.floor(safeNumber(incomingQty) or 1))
				local spareRoom = 0
				for _, b in ipairs(getBagContainerList()) do
					local nSlots = getContainerNumSlotsSafe(b)
					for s = 1, nSlots do
						local sid, cnt, locked = getContainerSlotInfoSafe(b, s)
						if sid == itemID and not locked and cnt and cnt > 0 and cnt < maxS then
							spareRoom = spareRoom + (maxS - cnt)
							if spareRoom >= need then return true end
						end
					end
				end
			end
		end
		return false
	end

	function OrderFlow.BuyVendorItem(index)
		local vSt = orderFlow.stages.vendor
		local idx = index or vSt.activeIndex
		local item = vSt.items[idx]
		if not item then return false, "no_item" end
		syncLiveEnvironmentInternal()
		if not orderFlow.env.atVendor then
			orderFlow.notice = "Please open a Vendor to start."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "vendor_closed"
		end
		if (item.remaining or 0) <= 0 or item.status == "done" then
			return false, "already_done"
		end
		local slotInfo = (item.itemID and orderFlow.liveVendorSlots[item.itemID])
			or (type(item.name) == "string" and orderFlow.liveVendorSlotsByName and orderFlow.liveVendorSlotsByName[item.name:lower()])
			or nil
		if not slotInfo then
			OrderFlow.ScanOpenVendor()
			slotInfo = (item.itemID and orderFlow.liveVendorSlots[item.itemID])
				or (type(item.name) == "string" and orderFlow.liveVendorSlotsByName and orderFlow.liveVendorSlotsByName[item.name:lower()])
				or nil
		end
		if not (slotInfo and item.inStockHere) then
			orderFlow.notice = "This vendor does not stock " .. tostring(item.name) .. "."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "not_in_stock"
		end
		if slotInfo.hasExtendedCost then
			orderFlow.notice = tostring(item.name) .. " requires special currency - buy manually."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "extended_cost"
		end
		if slotInfo.isPurchasable == false then
			orderFlow.notice = tostring(item.name) .. " is locked (reputation or level requirement)."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "not_purchasable"
		end
		if slotInfo.numAvailable == 0 then
			orderFlow.notice = tostring(item.name) .. " is sold out at this vendor."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "sold_out"
		end
		if not BuyMerchantItem then return false, "no_api" end

		local maxStack = math.max(1, tonumber(slotInfo.maxStack) or 20)
		local stackCount = math.max(1, tonumber(slotInfo.stackCount) or 1)
		local availUnits = (slotInfo.numAvailable and slotInfo.numAvailable > 0)
			and (slotInfo.numAvailable * stackCount) or math.huge
		local unitCopper = (item.liveUnit and item.liveUnit > 0) and item.liveUnit or (item.unitPrice or 0)
		local buyUnits, chunkCost = computeVendorBuyChunk(item.remaining, stackCount, maxStack, availUnits, slotInfo.price, unitCopper)
		if buyUnits <= 0 then
			orderFlow.notice = tostring(item.name) .. " is sold out at this vendor."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "sold_out"
		end
		if not hasBagSpaceForItem(item.itemID, buyUnits, maxStack) then
			orderFlow.notice = "Bags full - free bag space before buying " .. tostring(item.name) .. "."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "bags_full"
		end
		if type(GetMoney) == "function" then
			local money = safeNumber(GetMoney())
			if money ~= nil and chunkCost > 0 and money < chunkCost then
				orderFlow.notice = "Not enough gold to buy " .. tostring(item.name) .. "."
				orderFlow.noticeKind = "warning"
				notifyOrderFlow()
				return false, "insufficient_funds"
			end
		end
		if item.itemID and (not vSt.pendingBuy or vSt.pendingBuy.itemID ~= item.itemID) then
			vSt.baselineBagQty[item.itemID] = getLiveBagCount(item.itemID)
		end
		vSt.activeIndex = idx
		vSt.pendingBuy = {
			itemID = item.itemID,
			expectedQty = buyUnits,
			unitCopper = unitCopper,
			ts = (GetTime and GetTime()) or 0,
		}
		local ok = pcall(BuyMerchantItem, slotInfo.slot, buyUnits)
		if not ok then
			vSt.pendingBuy = nil
			return false, "buy_failed"
		end
		orderFlow.notice = string.format("Buying %dx %s from vendor...", buyUnits, tostring(item.name))
		orderFlow.noticeKind = "info"
		notifyOrderFlow()
		return true
	end

	function OrderFlow.BuyAllAtCurrentVendor()
		syncLiveEnvironmentInternal()
		if not orderFlow.env.atVendor or not BuyMerchantItem then return 0 end
		OrderFlow.ScanOpenVendor()
		local vSt = orderFlow.stages.vendor
		local vis = OrderFlow.GetVisibleStageEntries("vendor")
		local budget = (type(GetMoney) == "function") and safeNumber(GetMoney()) or nil
		local totalChunks = 0
		local itemsPurchased = 0
		local skippedNoGold = 0
		local skippedBagsFull = 0
		local skippedLocked = 0

		for _, entry in ipairs(vis) do
			if totalChunks >= 32 then break end
			local item = entry.item
			if item and (item.remaining or 0) > 0 and item.status ~= "done" and item.status ~= "skipped"
				and item.inStockHere and not item.hasExtendedCost and item.numAvailable ~= 0 then
				local slotInfo = (item.itemID and orderFlow.liveVendorSlots[item.itemID])
					or (type(item.name) == "string" and orderFlow.liveVendorSlotsByName and orderFlow.liveVendorSlotsByName[item.name:lower()])
					or nil
				if slotInfo and not slotInfo.hasExtendedCost and slotInfo.numAvailable ~= 0 then
					if slotInfo.isPurchasable == false or item.isPurchasable == false then
						skippedLocked = skippedLocked + 1
					else
						if item.itemID then
							vSt.baselineBagQty[item.itemID] = getLiveBagCount(item.itemID)
						end
						local left = item.remaining
						local stackCount = math.max(1, tonumber(slotInfo.stackCount) or 1)
						local maxStack = math.max(1, tonumber(slotInfo.maxStack) or 20)
						local availUnits = (slotInfo.numAvailable and slotInfo.numAvailable > 0)
							and (slotInfo.numAvailable * stackCount) or math.huge
						local unitCopper = (item.liveUnit and item.liveUnit > 0) and item.liveUnit or (item.unitPrice or 0)
						local boughtAny = false
						while left > 0 and availUnits > 0 and totalChunks < 32 do
							local buyUnits, chunkCost = computeVendorBuyChunk(left, stackCount, maxStack, availUnits, slotInfo.price, unitCopper)
							if buyUnits <= 0 then
								break
							end
							if not hasBagSpaceForItem(item.itemID, buyUnits, maxStack) then
								skippedBagsFull = skippedBagsFull + 1
								break
							end
							if budget ~= nil and chunkCost > 0 and chunkCost > budget then
								skippedNoGold = skippedNoGold + 1
								break
							end
							local ok = pcall(BuyMerchantItem, slotInfo.slot, buyUnits)
							if not ok then break end
							totalChunks = totalChunks + 1
							boughtAny = true
							left = math.max(0, left - buyUnits)
							if availUnits < math.huge then
								availUnits = math.max(0, availUnits - buyUnits)
							end
							if budget ~= nil and chunkCost > 0 then
								budget = budget - chunkCost
							end
						end
						if boughtAny then
							itemsPurchased = itemsPurchased + 1
						end
					end
				end
			end
		end

		if itemsPurchased > 0 then
			vSt.pendingBuy = { bulk = true, ts = (GetTime and GetTime()) or 0 }
			local suffix = ""
			if skippedNoGold > 0 then suffix = " (stopped: not enough gold)"
			elseif skippedBagsFull > 0 then suffix = " (stopped: bags full)" end
			orderFlow.notice = string.format("Purchased %d stocked vendor item(s)%s.", itemsPurchased, suffix)
			orderFlow.noticeKind = (suffix ~= "") and "warning" or "positive"
			notifyOrderFlow()
		elseif skippedNoGold > 0 then
			orderFlow.notice = "Not enough gold to buy stocked vendor items."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
		elseif skippedBagsFull > 0 then
			orderFlow.notice = "Bags full - free bag space before buying from vendor."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
		elseif skippedLocked > 0 then
			orderFlow.notice = "Stocked vendor item(s) locked (reputation or level requirement)."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
		end
		return itemsPurchased
	end

	function OrderFlow.MarkVendorBought(index)
		local vSt = orderFlow.stages.vendor
		local idx = index or vSt.activeIndex
		local item = vSt.items[idx]
		if not item then return false end
		local remBefore = math.max(0, tonumber(item.remaining) or 0)
		local paidUnit = (item.liveUnit and item.liveUnit > 0) and item.liveUnit or (item.unitPrice or 0)
		vSt.spentCopper = (tonumber(vSt.spentCopper) or 0) + (paidUnit * remBefore)
		item.bought = item.needed
		item.remaining = 0
		item.totalPrice = 0
		item.status = "done"
		if item.itemID then
			vSt.baselineBagQty[item.itemID] = getLiveBagCount(item.itemID)
		end
		local nextIdx = selectNextPendingVendorInternal(idx + 1, orderFlow.env.atVendor)
		if not nextIdx then
			orderFlow.notice = "All vendor items are bought!"
			orderFlow.noticeKind = "positive"
		end
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SkipVendorItem(index)
		local vSt = orderFlow.stages.vendor
		local idx = index or vSt.activeIndex
		local item = vSt.items[idx]
		if not item then return false end
		item.status = "skipped"
		selectNextPendingVendorInternal(idx + 1, orderFlow.env.atVendor)
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SelectVendorItem(index)
		local vSt = orderFlow.stages.vendor
		if not index or index < 1 or index > #vSt.items then return end
		vSt.activeIndex = index
		notifyOrderFlow()
	end

	function OrderFlow.SelectNextPendingVendor()
		local nextIdx = selectNextPendingVendorInternal((orderFlow.stages.vendor.activeIndex or 1) + 1, orderFlow.env.atVendor)
		notifyOrderFlow()
		return nextIdx
	end

	-----------------------------------------------------------------------------------------------
	-- 4.4 Stage 3 (Collect Owned: Bags / Bank / Mail / Alts) API
	-----------------------------------------------------------------------------------------------
	function OrderFlow.ScanOpenBank()
		orderFlow.liveBankSlots = {}
		local cItems = orderFlow.stages.collect.items
		if not orderFlow.env.atBank then
			for _, it in ipairs(cItems) do
				if it.source == "bank" then
					it.availableHere = 0
					if it.status == "ready" and (it.remaining or 0) > 0 then it.status = "pending" end
				end
			end
			return 0
		end
		if not hasCollectItemsOfSource("bank") then
			return 0
		end
		local bankContainers = getBankContainerList()
		local seenBag = {}
		for _, bag in ipairs(bankContainers) do
			if not seenBag[bag] then
				seenBag[bag] = true
				local numSlots = getContainerNumSlotsSafe(bag)
				if numSlots > 0 then
					for slot = 1, numSlots do
						local itemID, count, locked = getContainerSlotInfoSafe(bag, slot)
						if itemID and itemID > 0 and count and count > 0 then
							local list = orderFlow.liveBankSlots[itemID]
							if not list then
								list = {}
								orderFlow.liveBankSlots[itemID] = list
							end
							list[#list + 1] = { bag = bag, slot = slot, count = count, locked = locked }
						end
					end
				end
			end
		end
		local matchedCount = 0
		for _, it in ipairs(cItems) do
			if it.source == "bank" then
				local total = 0
				for _, entry in ipairs((it.itemID and orderFlow.liveBankSlots[it.itemID]) or {}) do
					total = total + (entry.count or 0)
				end
				it.availableHere = total
				if total > 0 and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
					it.status = "ready"
					matchedCount = matchedCount + 1
				elseif it.status == "ready" and (it.remaining or 0) > 0 then
					it.status = "pending"
				end
			end
		end
		return matchedCount
	end

	function OrderFlow.ScanOpenMailbox()
		orderFlow.liveMailSlots = {}
		local cItems = orderFlow.stages.collect.items
		if not orderFlow.env.atMail or not GetInboxNumItems then
			for _, it in ipairs(cItems) do
				if it.source == "mail" then
					it.availableHere = 0
					if it.status == "ready" and (it.remaining or 0) > 0 then it.status = "pending" end
				end
			end
			return 0
		end
		if not (hasCollectItemsOfSource("mail") or hasCollectItemsOfSource("alt")) then
			return 0
		end
		local numMail = safeNumber(GetInboxNumItems()) or 0
		local maxAttach = safeNumber(ATTACHMENTS_MAX_RECEIVE) or 12
		for mailIdx = 1, numMail do
			local skipMail = false
			local sender, subject, hasItem = nil, nil, true
			if GetInboxHeaderInfo then
				local ok, _, _, sdr, subj, _, codAmount, _, hItem = pcall(GetInboxHeaderInfo, mailIdx)
				if not ok then
					skipMail = true
				else
					if not readable(codAmount) or not readable(subj) then
						skipMail = true
					elseif RETRIEVING_DATA and subj == RETRIEVING_DATA then
						skipMail = true
					elseif (safeNumber(codAmount) or 0) > 0 then
						-- Critical safety guard: never auto-take COD mail attachments
						skipMail = true
					else
						sender = readable(sdr) and sdr or nil
						subject = subj
						if hItem ~= nil then
							hasItem = (hItem == true) or (type(hItem) == "number" and hItem > 0)
						end
					end
				end
			end
			if not skipMail and hasItem and GetInboxItem then
				for attachIdx = 1, maxAttach do
					local ok, r1, r2, r3, r4 = pcall(GetInboxItem, mailIdx, attachIdx)
					if ok and readable(r1) and r1 ~= nil then
						local linkID = nil
						if GetInboxItemLink then
							local lok, link = pcall(GetInboxItemLink, mailIdx, attachIdx)
							if lok and readable(link) and type(link) == "string" then
								linkID = tonumber(link:match("item:(%d+)"))
							end
						end
						local attItemID, attCount
						if linkID and linkID > 0 then
							attItemID = linkID
							if safeNumber(r2) == linkID and safeNumber(r4) then
								attCount = safeNumber(r4)
							else
								attCount = safeNumber(r3) or safeNumber(r4) or 1
							end
						elseif safeNumber(r2) and safeNumber(r2) > 0 and safeNumber(r4) then
							attItemID = safeNumber(r2)
							attCount = safeNumber(r4)
						end
						if attItemID and attItemID > 0 and attCount and attCount > 0 then
							local list = orderFlow.liveMailSlots[attItemID]
							if not list then
								list = {}
								orderFlow.liveMailSlots[attItemID] = list
							end
							list[#list + 1] = {
								mailIdx = mailIdx,
								attachIdx = attachIdx,
								count = attCount,
								sender = sender,
								subject = subject,
							}
						end
					end
				end
			end
		end
		local matchedCount = 0
		local mailNeededByID = {}
		for _, it in ipairs(cItems) do
			if it.source == "mail" then
				local total = 0
				for _, entry in ipairs((it.itemID and orderFlow.liveMailSlots[it.itemID]) or {}) do
					total = total + (entry.count or 0)
				end
				it.availableHere = total
				if (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
					if it.itemID then
						mailNeededByID[it.itemID] = (mailNeededByID[it.itemID] or 0) + (it.remaining or 0)
					end
					if total > 0 then
						it.status = "ready"
						matchedCount = matchedCount + 1
					elseif it.status == "ready" then
						it.status = "pending"
					end
				elseif it.status == "ready" and (it.remaining or 0) > 0 then
					it.status = "pending"
				end
			end
		end
		-- Split genuine non-AH mail sent directly by an alt into its own MAIL item without ever converting AH mail or overwriting ALT bank entries
		local function normalizeMailSenderName(raw)
			if not readable(raw) or type(raw) ~= "string" then return "" end
			local trimmed = raw:match("^%s*(.-)%s*$") or ""
			return (trimmed:gsub("%-.*$", "")):lower()
		end
		local function isEntryAuctionHouseMail(entry)
			local mIdx = entry and entry.mailIdx
			local invType, sdr, subj
			if _G.GetInboxInvoiceInfo and mIdx then
				local okI, itype = pcall(_G.GetInboxInvoiceInfo, mIdx)
				if okI and readable(itype) and type(itype) == "string" then invType = itype:lower() end
			end
			if invType == "buyer" or invType == "seller" or invType == "seller_temp_invoice" or invType == "auction" then
				return true
			end
			if _G.GetInboxHeaderInfo and mIdx then
				local okH, _, _, hSender, hSubj = pcall(_G.GetInboxHeaderInfo, mIdx)
				if okH then
					if readable(hSender) and type(hSender) == "string" then sdr = hSender:lower() end
					if readable(hSubj) and type(hSubj) == "string" then subj = hSubj:lower() end
				end
			end
			if sdr and (sdr:find("auction house", 1, true) ~= nil or sdr:find("blackwater auction", 1, true) ~= nil) then
				return true
			end
			if subj and (subj:find("^auction ") ~= nil or subj:find("^outbid on ") ~= nil) then
				return true
			end
			return false
		end
		local function entrySenderMatchesAltOwner(it, entry)
			local owners = type(it.altOwners) == "table" and it.altOwners or nil
			if not owners or #owners == 0 then return false end
			local mIdx = entry and entry.mailIdx
			if not (_G.GetInboxHeaderInfo and mIdx) then return false end
			local okH, _, _, hSender = pcall(_G.GetInboxHeaderInfo, mIdx)
			if not okH then return false end
			local senderNorm = normalizeMailSenderName(hSender)
			if senderNorm == "" then return false end
			for _, a in ipairs(owners) do
				local ownerNorm = normalizeMailSenderName(a and a.name)
				if ownerNorm ~= "" and ownerNorm == senderNorm then
					return true
				end
			end
			return false
		end
		local altMailClaimedByID = {}
		for _, it in ipairs(cItems) do
			if it.source == "mail" and it.mailFromAlt == true and it.itemID
				and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
				altMailClaimedByID[it.itemID] = (altMailClaimedByID[it.itemID] or 0) + (it.remaining or 0)
			end
		end
		local altSplitToAdd = {}
		local emptyAltRows = {}
		for idxAlt, it in ipairs(cItems) do
			if it.source == "alt" and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" and it.itemID then
				local totalAll = 0
				local totalFromAlt = 0
				for _, entry in ipairs(orderFlow.liveMailSlots[it.itemID] or {}) do
					local ec = entry.count or 0
					totalAll = totalAll + ec
					if ec > 0 and not isEntryAuctionHouseMail(entry) and entrySenderMatchesAltOwner(it, entry) then
						totalFromAlt = totalFromAlt + ec
					end
				end
				local unclaimedFromAlt = math.max(0, totalFromAlt - (altMailClaimedByID[it.itemID] or 0))
				local surplusAll = math.max(0, totalAll - (mailNeededByID[it.itemID] or 0))
				local altMailAvail = math.min(unclaimedFromAlt, surplusAll)
				if altMailAvail > 0 then
					local splitQty = math.min(it.remaining or 0, altMailAvail)
					if splitQty > 0 then
						it.needed = math.max(0, (it.needed or 0) - splitQty)
						it.remaining = math.max(0, it.needed - (it.collected or 0))
						if it.needed <= 0 and (it.collected or 0) <= 0 then
							emptyAltRows[idxAlt] = true
						elseif type(it.altOwners) == "table" and #it.altOwners > 0 then
							local decLeft = splitQty
							local keptOwners, altParts = {}, {}
							for _, a in ipairs(it.altOwners) do
								local aq = math.max(0, math.floor(tonumber(a and a.qty) or 0))
								if decLeft > 0 and aq > 0 then
									local take = math.min(aq, decLeft)
									aq = aq - take
									decLeft = decLeft - take
								end
								if aq > 0 then
									a.qty = aq
									keptOwners[#keptOwners + 1] = a
									altParts[#altParts + 1] = string.format("%s (%s %dx)", tostring(a.name or "Alt"), tostring(a.location or "Bags"), aq)
								end
							end
							it.altOwners = keptOwners
							it.altLabel = #altParts > 0 and ("On Alt: " .. table.concat(altParts, ", ")) or (it.altLabel or "On Alt")
						end
						altSplitToAdd[#altSplitToAdd + 1] = {
							itemID = it.itemID,
							name = it.name,
							itemLink = it.itemLink,
							needed = splitQty,
							availableHere = altMailAvail,
						}
						mailNeededByID[it.itemID] = (mailNeededByID[it.itemID] or 0) + splitQty
						altMailClaimedByID[it.itemID] = (altMailClaimedByID[it.itemID] or 0) + splitQty
						matchedCount = matchedCount + 1
					end
				end
			end
		end
		if next(emptyAltRows) ~= nil then
			for idxAlt = #cItems, 1, -1 do
				if emptyAltRows[idxAlt] then table.remove(cItems, idxAlt) end
			end
		end
		for _, add in ipairs(altSplitToAdd) do
			local merged = nil
			for _, it in ipairs(cItems) do
				if it.source == "mail" and it.itemID == add.itemID and it.status ~= "skipped" and it.purchasedFromAH ~= true then
					merged = it
					break
				end
			end
			if merged then
				merged.mailFromAlt = true
				merged.needed = (merged.needed or 0) + add.needed
				merged.remaining = math.max(0, merged.needed - (merged.collected or 0))
				merged.availableHere = math.max(merged.availableHere or 0, add.availableHere or 0)
				if merged.remaining > 0 then merged.status = "ready" end
			else
				cItems[#cItems + 1] = {
					itemID = add.itemID,
					name = add.name,
					itemLink = add.itemLink,
					source = "mail",
					mailFromAlt = true,
					needed = add.needed,
					collected = 0,
					remaining = add.needed,
					availableHere = add.availableHere,
					status = "ready",
					sortBucket = 2,
				}
			end
		end
		if #altSplitToAdd > 0 and sortCollectItems then
			sortCollectItems()
		end
		return matchedCount
	end

	local collectAllSerial = 0
	local stepCollectAllInternal
	local scheduleNextCollectAllStep
	local armCollectAllWatchdog

	local function hasCollectableForSource(src)
		local cSt = orderFlow.stages.collect
		if not cSt then return false end
		for _, it in ipairs(cSt.items or {}) do
			if it and it.source == src and (it.remaining or 0) > 0
				and it.status ~= "done" and it.status ~= "skipped" then
				if src == "bank" then
					local slots = it.itemID and orderFlow.liveBankSlots[it.itemID] or nil
					if (it.availableHere or 0) > 0 or (slots and #slots > 0) then
						return true
					end
				elseif src == "mail" then
					local atts = it.itemID and orderFlow.liveMailSlots[it.itemID] or nil
					if (it.availableHere or 0) > 0 or (atts and #atts > 0) then
						return true
					end
				end
			end
		end
		return false
	end

	local function hasPendingForSource(src)
		local cSt = orderFlow.stages.collect
		if not cSt then return false end
		for _, it in ipairs(cSt.items or {}) do
			if it and it.source == src and (it.remaining or 0) > 0
				and it.status ~= "done" and it.status ~= "skipped" then
				return true
			end
		end
		return false
	end

	local function isCollectActionBlocked(addonArg, funcName)
		if readable(funcName) and type(funcName) == "string" then
			if funcName == "UseContainerItem" or funcName == "SplitContainerItem"
				or funcName == "PickupContainerItem" or funcName == "TakeInboxItem"
				or funcName:find("UseContainerItem", 1, true)
				or funcName:find("SplitContainerItem", 1, true)
				or funcName:find("PickupContainerItem", 1, true)
				or funcName:find("TakeInboxItem", 1, true) then
				return true
			end
		end
		if readable(addonArg) and (addonArg == ADDON or addonArg == "MerchantMaster") then
			return true
		end
		return funcName == nil and addonArg == nil
	end

	function OrderFlow.OnBankShow()
		local wasAtBank = (orderFlow.env.atBank == true)
		orderFlow.env._bankEventOpen = true
		orderFlow.env._bankEventFrame = _G.BankFrame
		orderFlow.env._bankFrameSeenShown = isFrameShownSafe(_G.BankFrame)
		orderFlow.env._bankAwaitFrameHide = false
		orderFlow.env.atBank = true
		local cStShow = orderFlow.stages.collect
		local cBase = cStShow.baselineBagQty
		for _, it in ipairs(cStShow.items or {}) do
			if it.source == "bank" and it.itemID and (cStShow.pendingTake == nil or cBase[it.itemID] == nil) then
				cBase[it.itemID] = getLiveBagCount(it.itemID)
			end
		end
		local matched = OrderFlow.ScanOpenBank()
		sortCollectItems()
		if matched > 0 then
			selectNextPendingCollectInternal(1, "bank")
		end
		local cStats = OrderFlow.GetStageStats("collect")
		local ahStats = OrderFlow.GetStageStats("ah")
		if (not wasAtBank or not orderFlow.env._bankAutoSwitched) and cStats.actionableRemaining > 0
			and (matched > 0 or ahStats.empty or ahStats.complete) then
			orderFlow.env._bankAutoSwitched = true
			orderFlow.activeStage = "collect"
		end
		notifyOrderFlow()
	end

	function OrderFlow.OnBankClosed()
		orderFlow.env._bankEventOpen = false
		orderFlow.env._bankEventFrame = nil
		orderFlow.env._bankFrameSeenShown = false
		orderFlow.env._bankAwaitFrameHide = isFrameShownSafe(_G.BankFrame)
		orderFlow.env._bankAutoSwitched = false
		orderFlow.env.atBank = false
		local cStClose = orderFlow.stages.collect
		if cStClose.pendingTake and cStClose.pendingTake.source == "bank" then
			cStClose.pendingTake = nil
		end
		if cStClose.collectAll and cStClose.collectAll.active and cStClose.collectAll.source == "bank" then
			OrderFlow.StopCollectAll("bank_closed")
		end
		OrderFlow.ScanOpenBank()
		notifyOrderFlow()
	end

	function OrderFlow.OnBankSlotsChanged()
		if orderFlow.env.atBank then
			OrderFlow.ScanOpenBank()
			notifyOrderFlow()
			local cSt = orderFlow.stages.collect
			local ca = cSt and cSt.collectAll
			if ca and ca.active and ca.source == "bank" and cSt.pendingTake == nil and not ca.stepScheduled then
				scheduleNextCollectAllStep(ca.serial)
			end
		end
	end

	function OrderFlow.OnMailShow()
		local wasAtMail = (orderFlow.env.atMail == true)
		orderFlow.env._mailEventOpen = true
		orderFlow.env._mailEventFrame = _G.MailFrame
		orderFlow.env._mailFrameSeenShown = isFrameShownSafe(_G.MailFrame)
		orderFlow.env._mailAwaitFrameHide = false
		orderFlow.env.atMail = true
		local cStShow = orderFlow.stages.collect
		local cBase = cStShow.baselineBagQty
		for _, it in ipairs(cStShow.items or {}) do
			if (it.source == "mail" or it.source == "alt") and it.itemID and (cStShow.pendingTake == nil or cBase[it.itemID] == nil) then
				cBase[it.itemID] = getLiveBagCount(it.itemID)
			end
		end
		local matched = OrderFlow.ScanOpenMailbox()
		sortCollectItems()
		if matched > 0 then
			selectNextPendingCollectInternal(1, "mail")
		end
		local cStats = OrderFlow.GetStageStats("collect")
		local ahStats = OrderFlow.GetStageStats("ah")
		if (not wasAtMail or not orderFlow.env._mailAutoSwitched) and cStats.actionableRemaining > 0
			and (matched > 0 or ahStats.empty or ahStats.complete) then
			orderFlow.env._mailAutoSwitched = true
			orderFlow.activeStage = "collect"
		end
		notifyOrderFlow()
	end

	function OrderFlow.OnMailInboxUpdate()
		if orderFlow.env.atMail then
			OrderFlow.ScanOpenMailbox()
			notifyOrderFlow()
			local cSt = orderFlow.stages.collect
			local ca = cSt and cSt.collectAll
			if ca and ca.active and ca.source == "mail" and cSt.pendingTake == nil and not ca.stepScheduled then
				scheduleNextCollectAllStep(ca.serial)
			end
		end
	end

	function OrderFlow.OnMailClosed()
		orderFlow.env._mailEventOpen = false
		orderFlow.env._mailEventFrame = nil
		orderFlow.env._mailFrameSeenShown = false
		orderFlow.env._mailAwaitFrameHide = isFrameShownSafe(_G.MailFrame)
		orderFlow.env._mailAutoSwitched = false
		orderFlow.env.atMail = false
		local cStClose = orderFlow.stages.collect
		if cStClose.pendingTake and cStClose.pendingTake.source == "mail" then
			cStClose.pendingTake = nil
		end
		if cStClose.collectAll and cStClose.collectAll.active and cStClose.collectAll.source == "mail" then
			OrderFlow.StopCollectAll("mail_closed")
		end
		OrderFlow.ScanOpenMailbox()
		notifyOrderFlow()
	end

	function OrderFlow.GetCollectWaitingMessage()
		local needBank, needMail = false, false
		for _, it in ipairs(orderFlow.stages.collect.items or {}) do
			if (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
				if it.source == "bank" then needBank = true
				elseif it.source == "mail" then needMail = true end
			end
		end
		if needBank and needMail and not orderFlow.env.atBank and not orderFlow.env.atMail then
			return "Please open Mailbox or Bank to start."
		end
		if needBank and not needMail and not orderFlow.env.atBank then
			return "Please open Bank to start."
		end
		if needMail and not needBank and not orderFlow.env.atMail then
			return "Please open Mailbox to start."
		end
		return nil
	end

	function OrderFlow.WithdrawFromBank(index)
		local cSt = orderFlow.stages.collect
		local idx = index or cSt.activeIndex
		local item = cSt.items[idx]
		if not item then return false, "no_item" end
		if item.source ~= "bank" then return false, "not_bank_item" end
		syncLiveEnvironmentInternal()
		if not orderFlow.env.atBank then
			orderFlow.notice = "Please open Bank to start."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "bank_closed"
		end
		if (item.remaining or 0) <= 0 or item.status == "done" then
			return false, "already_done"
		end
		local slots = item.itemID and orderFlow.liveBankSlots[item.itemID] or nil
		if not slots or #slots == 0 then
			OrderFlow.ScanOpenBank()
			slots = item.itemID and orderFlow.liveBankSlots[item.itemID] or nil
		end
		local slotEntry = nil
		for _, e in ipairs(slots or {}) do
			if not e.locked and (e.count or 0) > 0 then
				slotEntry = e
				break
			end
		end
		if not slotEntry then
			orderFlow.notice = tostring(item.name) .. " was not found in Bank."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "not_in_bank"
		end

		local useFn = (C_Container and C_Container.UseContainerItem) or UseContainerItem
		local splitFn = (C_Container and C_Container.SplitContainerItem) or SplitContainerItem
		local pickupFn = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem

		if item.itemID then
			cSt.baselineBagQty[item.itemID] = getLiveBagCount(item.itemID)
		end
		cSt.activeIndex = idx

		if slotEntry.count <= item.remaining then
			if not hasBagSpaceForItem(item.itemID, slotEntry.count, nil) then
				orderFlow.notice = "Bags full - free 1 slot before withdrawing from Bank."
				orderFlow.noticeKind = "warning"
				notifyOrderFlow()
				return false, "bags_full"
			end
			if not useFn then return false, "no_api" end
			cSt.pendingTake = {
				source = "bank",
				itemID = item.itemID,
				expectedQty = slotEntry.count,
				ts = (GetTime and GetTime()) or 0,
			}
			local ok = pcall(useFn, slotEntry.bag, slotEntry.slot)
			if not ok then
				cSt.pendingTake = nil
				return false, "withdraw_failed"
			end
		else
			local freeBag, freeSlot = findFreeGeneralBagSlot(item.itemID)
			if not freeBag then
				orderFlow.notice = "Bags full - free 1 slot to split stack."
				orderFlow.noticeKind = "warning"
				notifyOrderFlow()
				return false, "bags_full"
			end
			if not (splitFn and pickupFn) then return false, "no_api" end
			if ClearCursor then pcall(ClearCursor) end
			cSt.pendingTake = {
				source = "bank",
				itemID = item.itemID,
				expectedQty = item.remaining,
				ts = (GetTime and GetTime()) or 0,
			}
			local ok1 = pcall(splitFn, slotEntry.bag, slotEntry.slot, item.remaining)
			local ok2 = ok1 and pcall(pickupFn, freeBag, freeSlot)
			if not ok2 then
				if ClearCursor then pcall(ClearCursor) end
				cSt.pendingTake = nil
				return false, "split_failed"
			end
		end

		orderFlow.notice = string.format("Withdrawing %dx %s from Bank...", cSt.pendingTake.expectedQty, tostring(item.name))
		orderFlow.noticeKind = "info"
		notifyOrderFlow()
		return true
	end

	function OrderFlow.CollectFromMail(index)
		if ns.MailHelper and type(ns.MailHelper.IsActive) == "function" and ns.MailHelper.IsActive() then
			orderFlow.notice = "Mail Helper is currently looting the inbox - wait or click Stop first."
			orderFlow.noticeKind = "info"
			notifyOrderFlow()
			return false, "mail_helper_active"
		end
		local cSt = orderFlow.stages.collect
		local idx = index or cSt.activeIndex
		local item = cSt.items[idx]
		if not item then return false, "no_item" end
		syncLiveEnvironmentInternal()
		if item.source ~= "mail" then
			return false, "not_mail_item"
		end
		if not orderFlow.env.atMail then
			orderFlow.notice = "Please open Mailbox to start."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "mail_closed"
		end
		if (item.remaining or 0) <= 0 or item.status == "done" then
			return false, "already_done"
		end
		local atts = item.itemID and orderFlow.liveMailSlots[item.itemID] or nil
		if not atts or #atts == 0 then
			OrderFlow.ScanOpenMailbox()
			atts = item.itemID and orderFlow.liveMailSlots[item.itemID] or nil
		end
		if not atts or #atts == 0 then
			orderFlow.notice = tostring(item.name) .. " was not found in Mailbox."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "not_in_mail"
		end
		local remNeed = math.max(1, math.floor(tonumber(item.remaining) or 1))
		local att = nil
		local bestFitCount, bestSmallOverCount = -1, math.huge
		for _, cand in ipairs(atts) do
			local cnt = tonumber(cand and cand.count) or 0
			if cnt > 0 and cnt <= remNeed then
				if cnt > bestFitCount then
					bestFitCount = cnt
					att = cand
				end
			elseif cnt > remNeed and bestFitCount < 0 then
				if cnt < bestSmallOverCount then
					bestSmallOverCount = cnt
					att = cand
				end
			end
		end
		if not att then att = atts[1] end
		if not att then
			orderFlow.notice = tostring(item.name) .. " was not found in Mailbox."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "not_in_mail"
		end
		if not hasBagSpaceForItem(item.itemID, att.count, nil) then
			orderFlow.notice = "Bags full - free 1 slot before looting mail."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "bags_full"
		end
		if not TakeInboxItem then return false, "no_api" end

		if item.itemID then
			cSt.baselineBagQty[item.itemID] = getLiveBagCount(item.itemID)
		end
		cSt.activeIndex = idx
		cSt.pendingTake = {
			source = "mail",
			itemID = item.itemID,
			expectedQty = att.count,
			ts = (GetTime and GetTime()) or 0,
		}
		local ok = pcall(TakeInboxItem, att.mailIdx, att.attachIdx)
		if not ok then
			cSt.pendingTake = nil
			return false, "take_failed"
		end
		orderFlow.notice = string.format("Collecting %dx %s from Mailbox...", att.count, tostring(item.name))
		orderFlow.noticeKind = "info"
		notifyOrderFlow()
		return true
	end

	function OrderFlow.IsCollectAllActive()
		local cSt = orderFlow.stages.collect
		return (cSt and cSt.collectAll and cSt.collectAll.active == true) and true or false
	end

	function OrderFlow.GetCollectAllMode()
		local cSt = orderFlow.stages.collect
		local ca = cSt and cSt.collectAll
		if ca and ca.active == true then
			return ca.mode or "all"
		end
		return nil
	end

	function OrderFlow.GetCollectAllSummary()
		syncLiveEnvironmentInternal()
		local cSt = orderFlow.stages.collect
		local activeMode = OrderFlow.GetCollectAllMode()
		local atBank = (orderFlow.env.atBank == true)
		local atMail = (orderFlow.env.atMail == true)
		local src = nil
		if atBank and atMail then
			local cur = cSt and cSt.items and cSt.items[cSt.activeIndex]
			if cur and (cur.source == "bank" or cur.source == "mail") and hasCollectableForSource(cur.source) then
				src = cur.source
			elseif hasCollectableForSource("bank") then
				src = "bank"
			elseif hasCollectableForSource("mail") then
				src = "mail"
			elseif cur and (cur.source == "bank" or cur.source == "mail") then
				src = cur.source
			else
				src = "bank"
			end
		elseif atBank then
			src = "bank"
		elseif atMail then
			src = "mail"
		end
		local itemCount, unitCount = 0, 0
		if src and cSt then
			for _, it in ipairs(cSt.items or {}) do
				if it and it.source == src and (it.remaining or 0) > 0
					and it.status ~= "done" and it.status ~= "skipped" then
					local hasSlot = false
					if src == "bank" then
						local slots = it.itemID and orderFlow.liveBankSlots[it.itemID] or nil
						hasSlot = ((it.availableHere or 0) > 0) or (slots ~= nil and #slots > 0)
					else
						local atts = it.itemID and orderFlow.liveMailSlots[it.itemID] or nil
						hasSlot = ((it.availableHere or 0) > 0) or (atts ~= nil and #atts > 0)
					end
					if hasSlot then
						itemCount = itemCount + 1
						unitCount = unitCount + (it.remaining or 0)
					end
				end
			end
		end
		return {
			source = src,
			itemCount = itemCount,
			unitCount = unitCount,
			activeMode = activeMode,
		}
	end

	function OrderFlow.HasCollectableAtCurrentSource()
		syncLiveEnvironmentInternal()
		if orderFlow.env.atBank and hasCollectableForSource("bank") then
			return true
		end
		if orderFlow.env.atMail and hasCollectableForSource("mail") then
			return true
		end
		return false
	end

	function OrderFlow.StopCollectAll(reason)
		local cSt = orderFlow.stages.collect
		local ca = cSt and cSt.collectAll
		local wasActive = (ca and ca.active == true) and true or false
		local mode = (ca and ca.mode) or "all"
		local targetItem = ca and ca.targetItem or nil
		local targetName = ca and (ca.targetName or (targetItem and targetItem.name)) or "item"
		local src = ca and ca.source or nil
		local count = ca and (ca.collectedCount or 0) or 0
		if ca then
			ca.active = false
			ca.stepScheduled = false
		end
		collectAllSerial = collectAllSerial + 1
		if cSt then
			cSt.collectAll = nil
		end
		if not wasActive then
			return false
		end
		local srcLabel = (src == "bank") and "Bank" or ((src == "mail") and "Mailbox" or "container")
		if reason == "done" then
			if mode == "item" then
				if targetItem and (targetItem.remaining or 0) <= 0 then
					orderFlow.notice = string.format("Collected all needed %s from %s!", tostring(targetName), srcLabel)
					orderFlow.noticeKind = "positive"
				elseif count > 0 then
					orderFlow.notice = string.format("Collected available %s (%d/%d) from %s.",
						tostring(targetName), (targetItem and targetItem.collected) or count, (targetItem and targetItem.needed) or count, srcLabel)
					orderFlow.noticeKind = "info"
				else
					orderFlow.notice = string.format("No matching %s found at %s.", tostring(targetName), srcLabel)
					orderFlow.noticeKind = "warning"
				end
			elseif count > 0 then
				orderFlow.notice = "Collected all needed items from " .. srcLabel .. "!"
				orderFlow.noticeKind = "positive"
			else
				orderFlow.notice = "No matching pending items found at " .. srcLabel .. "."
				orderFlow.noticeKind = "warning"
			end
		elseif reason == "user_stop" then
			orderFlow.notice = (mode == "item")
				and ("Stopped collecting " .. tostring(targetName) .. ".")
				or "Stopped Collect All."
			orderFlow.noticeKind = "info"
		elseif reason == "bank_closed" then
			orderFlow.notice = "Stopped Collect All - Bank closed."
			orderFlow.noticeKind = "warning"
		elseif reason == "mail_closed" then
			orderFlow.notice = "Stopped Collect All - Mailbox closed."
			orderFlow.noticeKind = "warning"
		elseif reason == "action_blocked" then
			orderFlow.notice = "Collect All stopped - hardware action blocked. Click item button manually."
			orderFlow.noticeKind = "warning"
		elseif reason == "timeout" then
			orderFlow.notice = "Collect All paused - waiting on server timed out. Click Collect All to retry."
			orderFlow.noticeKind = "warning"
		elseif reason == "mail_helper_active" then
			orderFlow.notice = "Mail Helper is currently looting - wait or click Stop first."
			orderFlow.noticeKind = "info"
		elseif reason == "not_in_bank" or reason == "not_in_mail" then
			orderFlow.notice = tostring(targetName) .. " was not found in " .. srcLabel .. "."
			orderFlow.noticeKind = "warning"
		elseif reason == "bags_full" then
			if not orderFlow.notice or orderFlow.notice == "" then
				orderFlow.notice = "Bags full - free 1 slot before collecting."
			end
			orderFlow.noticeKind = "warning"
		elseif reason == "withdraw_failed" or reason == "split_failed" then
			orderFlow.notice = "Stopped Collect All - bank withdrawal failed."
			orderFlow.noticeKind = "warning"
		elseif reason == "take_failed" then
			orderFlow.notice = "Stopped Collect All - mail collection failed."
			orderFlow.noticeKind = "warning"
		elseif reason == "no_api" then
			orderFlow.notice = "Stopped Collect All - container API unavailable."
			orderFlow.noticeKind = "warning"
		elseif type(reason) == "string" and reason ~= "" then
			orderFlow.notice = reason
			orderFlow.noticeKind = "info"
		end
		notifyOrderFlow()
		return true
	end

	function OrderFlow.OnActionBlocked(addonArg, funcName)
		local cSt = orderFlow.stages.collect
		if cSt and cSt.collectAll and cSt.collectAll.active and isCollectActionBlocked(addonArg, funcName) then
			cSt.pendingTake = nil
			OrderFlow.StopCollectAll("action_blocked")
			return true
		end
		return false
	end

	armCollectAllWatchdog = function(serial, takeToken)
		if not (C_Timer and type(C_Timer.After) == "function") then return end
		local arming = true
		C_Timer.After(4.0, function()
			if arming then return end
			local cSt = orderFlow.stages.collect
			local ca = cSt and cSt.collectAll
			if ca and ca.active and ca.serial == serial and cSt.pendingTake == takeToken then
				cSt.pendingTake = nil
				OrderFlow.StopCollectAll("timeout")
			end
		end)
		arming = false
	end

	scheduleNextCollectAllStep = function(serial)
		local cSt = orderFlow.stages.collect
		local ca = cSt and cSt.collectAll
		if not (ca and ca.active and ca.serial == serial) then return end
		if ca.stepScheduled then return end
		if C_Timer and type(C_Timer.After) == "function" then
			ca.stepScheduled = true
			C_Timer.After(0.15, function()
				local curCSt = orderFlow.stages.collect
				local curCa = curCSt and curCSt.collectAll
				if not (curCa and curCa.active and curCa.serial == serial) then return end
				curCa.stepScheduled = false
				stepCollectAllInternal(serial)
			end)
		else
			ca.stepScheduled = false
			stepCollectAllInternal(serial)
		end
	end

	stepCollectAllInternal = function(serial)
		local cSt = orderFlow.stages.collect
		local ca = cSt and cSt.collectAll
		if not (ca and ca.active and ca.serial == serial) then
			return false, "inactive"
		end
		syncLiveEnvironmentInternal()
		local src = ca.source
		if src == "bank" and not orderFlow.env.atBank then
			OrderFlow.StopCollectAll("bank_closed")
			return false, "bank_closed"
		elseif src == "mail" and not orderFlow.env.atMail then
			OrderFlow.StopCollectAll("mail_closed")
			return false, "mail_closed"
		end
		if src == "mail" and ns.MailHelper and type(ns.MailHelper.IsActive) == "function" and ns.MailHelper.IsActive() then
			OrderFlow.StopCollectAll("mail_helper_active")
			return false, "mail_helper_active"
		end
		if cSt.pendingTake ~= nil then
			return false, "pending"
		end

		if ca.mode == "item" and ca.targetItem then
			local targetIdx = nil
			for idx, it in ipairs(cSt.items or {}) do
				if it == ca.targetItem then
					targetIdx = idx
					break
				end
			end
			if not targetIdx or (ca.targetItem.remaining or 0) <= 0
				or ca.targetItem.status == "done" or ca.targetItem.status == "skipped" then
				local finishedCount = ca.collectedCount or 0
				OrderFlow.StopCollectAll("done")
				return finishedCount > 0, finishedCount > 0 and "done" or "already_done"
			end
			cSt.activeIndex = targetIdx
			local ok, err
			if src == "bank" then
				ok, err = OrderFlow.WithdrawFromBank(targetIdx)
			else
				ok, err = OrderFlow.CollectFromMail(targetIdx)
			end
			if ok then
				if cSt.pendingTake ~= nil then
					armCollectAllWatchdog(serial, cSt.pendingTake)
				end
				return true
			elseif err == "not_in_bank" or err == "not_in_mail" then
				if (ca.collectedCount or 0) > 0 then
					OrderFlow.StopCollectAll("done")
					return true, "done"
				end
				OrderFlow.StopCollectAll(err)
				return false, err
			else
				OrderFlow.StopCollectAll(err or "failed")
				return false, err or "failed"
			end
		end

		local maxSteps = math.max(1, #(cSt.items or {})) + 2
		for _ = 1, maxSteps do
			if not (cSt.collectAll == ca and ca.active and ca.serial == serial) then
				return false, "inactive"
			end
			local nextIdx, nextItem = nil, nil
			for idx, it in ipairs(cSt.items or {}) do
				if it and it.source == src and (it.remaining or 0) > 0
					and it.status ~= "done" and it.status ~= "skipped"
					and not (ca.skippedIdx and ca.skippedIdx[idx])
					and not (ca.skippedItems and ca.skippedItems[it]) then
					nextIdx = idx
					nextItem = it
					break
				end
			end
			if not nextIdx then
				local finishedCount = ca.collectedCount or 0
				OrderFlow.StopCollectAll("done")
				return finishedCount > 0, finishedCount > 0 and "done" or "nothing_to_collect"
			end

			local ok, err
			if src == "bank" then
				ok, err = OrderFlow.WithdrawFromBank(nextIdx)
			else
				ok, err = OrderFlow.CollectFromMail(nextIdx)
			end

			if ok then
				if cSt.pendingTake ~= nil then
					armCollectAllWatchdog(serial, cSt.pendingTake)
				end
				return true
			elseif err == "not_in_bank" or err == "not_in_mail" or err == "already_done" then
				ca.skippedIdx[nextIdx] = true
				ca.skippedItems[nextItem] = true
			else
				OrderFlow.StopCollectAll(err or "failed")
				return false, err or "failed"
			end
		end

		local finishedCount = ca.collectedCount or 0
		OrderFlow.StopCollectAll("done")
		return finishedCount > 0, "done"
	end

	function OrderFlow.CollectAllForItem(index)
		local cSt = orderFlow.stages.collect
		local idx = index or (cSt and cSt.activeIndex)
		local item = cSt and cSt.items and cSt.items[idx]
		if not item then return false, "no_item" end
		if item.source ~= "bank" and item.source ~= "mail" then
			return false, "not_collectable_source"
		end
		syncLiveEnvironmentInternal()
		if item.source == "bank" and not orderFlow.env.atBank then
			orderFlow.notice = "Please open Bank to start."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "bank_closed"
		elseif item.source == "mail" and not orderFlow.env.atMail then
			orderFlow.notice = "Please open Mailbox to start."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "mail_closed"
		end
		if item.source == "mail" and ns.MailHelper and type(ns.MailHelper.IsActive) == "function" and ns.MailHelper.IsActive() then
			orderFlow.notice = "Mail Helper is currently looting - wait or click Stop first."
			orderFlow.noticeKind = "info"
			notifyOrderFlow()
			return false, "mail_helper_active"
		end
		if (item.remaining or 0) <= 0 or item.status == "done" then
			return false, "already_done"
		end

		if item.source == "bank" then
			OrderFlow.ScanOpenBank()
		else
			OrderFlow.ScanOpenMailbox()
		end
		sortCollectItems()
		for i, it in ipairs(cSt.items or {}) do
			if it == item then
				cSt.activeIndex = i
				break
			end
		end

		collectAllSerial = collectAllSerial + 1
		local serial = collectAllSerial
		cSt.collectAll = {
			active = true,
			mode = "item",
			targetItem = item,
			targetItemID = item.itemID,
			targetName = item.name,
			source = item.source,
			serial = serial,
			skippedIdx = {},
			skippedItems = {},
			collectedCount = 0,
			stepScheduled = false,
		}
		return stepCollectAllInternal(serial)
	end

	function OrderFlow.CollectAllAtCurrentSource()
		syncLiveEnvironmentInternal()
		local atBank = (orderFlow.env.atBank == true)
		local atMail = (orderFlow.env.atMail == true)
		if not atBank and not atMail then
			orderFlow.notice = "Please open Bank or Mailbox to collect all."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "source_closed"
		end

		local cSt = orderFlow.stages.collect
		local src = nil
		if atBank and atMail then
			local cur = cSt.items and cSt.items[cSt.activeIndex]
			if cur and (cur.source == "bank" or cur.source == "mail")
				and hasPendingForSource(cur.source) then
				if hasCollectableForSource(cur.source) then
					src = cur.source
				else
					local other = (cur.source == "bank") and "mail" or "bank"
					src = hasCollectableForSource(other) and other or cur.source
				end
			elseif hasCollectableForSource("bank") then
				src = "bank"
			elseif hasCollectableForSource("mail") then
				src = "mail"
			elseif hasPendingForSource("bank") then
				src = "bank"
			else
				src = "mail"
			end
		elseif atBank then
			src = "bank"
		else
			src = "mail"
		end

		if src == "mail" and ns.MailHelper and type(ns.MailHelper.IsActive) == "function" and ns.MailHelper.IsActive() then
			orderFlow.notice = "Mail Helper is currently looting - wait or click Stop first."
			orderFlow.noticeKind = "info"
			notifyOrderFlow()
			return false, "mail_helper_active"
		end

		if src == "bank" then
			OrderFlow.ScanOpenBank()
		else
			OrderFlow.ScanOpenMailbox()
		end
		sortCollectItems()
		selectNextPendingCollectInternal(1, src)

		collectAllSerial = collectAllSerial + 1
		local serial = collectAllSerial
		cSt.collectAll = {
			active = true,
			mode = "all",
			targetItem = nil,
			source = src,
			serial = serial,
			skippedIdx = {},
			skippedItems = {},
			collectedCount = 0,
			stepScheduled = false,
		}
		return stepCollectAllInternal(serial)
	end

	if type(_G.CreateFrame) == "function" then
		local okF, af = pcall(_G.CreateFrame, "Frame")
		if okF and af and type(af.SetScript) == "function" and type(af.RegisterEvent) == "function" then
			af:SetScript("OnEvent", function(_, event, arg1, arg2)
				if event == "ADDON_ACTION_BLOCKED" then
					OrderFlow.OnActionBlocked(arg1, arg2)
				end
			end)
			pcall(af.RegisterEvent, af, "ADDON_ACTION_BLOCKED")
			OrderFlow._collectActionFrame = af
		end
	end

	function OrderFlow.MarkCollected(index)
		local cSt = orderFlow.stages.collect
		local idx = index or cSt.activeIndex
		local item = cSt.items[idx]
		if not item then return false end
		item.collected = item.needed
		item.remaining = 0
		item.status = "done"
		if item.itemID then
			cSt.baselineBagQty[item.itemID] = getLiveBagCount(item.itemID)
		end
		local pref = (orderFlow.env.atBank and not orderFlow.env.atMail) and "bank" or (orderFlow.env.atMail and "mail" or "mail")
		local nextIdx = selectNextPendingCollectInternal(idx + 1, pref)
		if not nextIdx then
			orderFlow.notice = "All owned items collected!"
			orderFlow.noticeKind = "positive"
		end
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SkipCollectItem(index)
		local cSt = orderFlow.stages.collect
		local idx = index or cSt.activeIndex
		local item = cSt.items[idx]
		if not item then return false end
		item.status = "skipped"
		local pref = (orderFlow.env.atBank and not orderFlow.env.atMail) and "bank" or "mail"
		selectNextPendingCollectInternal(idx + 1, pref)
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SelectCollectItem(index)
		local cSt = orderFlow.stages.collect
		if not index or index < 1 or index > #cSt.items then return end
		cSt.activeIndex = index
		notifyOrderFlow()
	end

	function OrderFlow.SelectNextPendingCollect()
		local pref = (orderFlow.env.atBank and not orderFlow.env.atMail) and "bank" or "mail"
		local nextIdx = selectNextPendingCollectInternal((orderFlow.stages.collect.activeIndex or 1) + 1, pref)
		notifyOrderFlow()
		return nextIdx
	end

	-----------------------------------------------------------------------------------------------
	-- 4.5 Stage 4 (Crafting Task List) API
	-----------------------------------------------------------------------------------------------
	local function isFrameShownSafe(frame)
		if not (readable(frame) and frame and type(frame.IsShown) == "function") then return false end
		local ok, shown = pcall(frame.IsShown, frame)
		return ok and readable(shown) and shown == true
	end

	function OrderFlow.GetOpenProfession()
		if ns.IsForeignTradeSkill and ns.IsForeignTradeSkill() then
			return nil, nil
		end
		local profShown = isFrameShownSafe(ProfessionsFrame)
		local tsShown = isFrameShownSafe(TradeSkillFrame)
		local craftShown = isFrameShownSafe(CraftFrame)

		-- Priority 1: Modern C_TradeSkillUI when ProfessionsFrame or TradeSkillFrame is open
		if (profShown or tsShown) and C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
			local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
			if ok and tableValue(info) then
				local pk = (safeNumber(info.professionID) and ns.PROF_BY_SKILLLINE and ns.PROF_BY_SKILLLINE[info.professionID])
					or matchProfKeyByName(info.professionName)
				if pk then
					return pk, profShown and "ProfessionsFrame" or "TradeSkillFrame"
				end
			end
		end
		-- Priority 2: Classic TradeSkillFrame
		if tsShown and GetTradeSkillLine then
			local ok, skillName = pcall(GetTradeSkillLine)
			if ok then
				local pk = matchProfKeyByName(skillName)
				if pk then return pk, "TradeSkillFrame" end
			end
		end
		-- Priority 3: Classic CraftFrame (Enchanting / Poisons / Beast Training)
		if craftShown then
			local craftName = nil
			if GetCraftDisplaySkillLine then
				local ok, cname = pcall(GetCraftDisplaySkillLine)
				if ok then craftName = cname end
			end
			local pk = matchProfKeyByName(craftName) or "enchanting"
			return pk, "CraftFrame"
		end
		return nil, nil
	end

	local PROF_OPEN_SPELL_MAP = {
		alchemy        = { spellID = 2259,  fallback = "Alchemy" },
		blacksmithing  = { spellID = 2018,  fallback = "Blacksmithing" },
		enchanting     = { spellID = 7411,  fallback = "Enchanting" },
		engineering    = { spellID = 4036,  fallback = "Engineering" },
		leatherworking = { spellID = 2108,  fallback = "Leatherworking" },
		tailoring      = { spellID = 3908,  fallback = "Tailoring" },
		mining         = { spellID = 2656,  fallback = "Smelting" },
		cooking        = { spellID = 2550,  fallback = "Cooking" },
		firstaid       = { spellID = 3273,  fallback = "First Aid" },
		poisons        = { spellID = 2842,  fallback = "Poisons" },
	}

	local function resolveOpenProfessionSpell(profKey, profName)
		local spec = profKey and PROF_OPEN_SPELL_MAP[profKey] or nil
		local spellID = spec and spec.spellID or nil
		local resolvedName = nil
		if spellID and C_Spell and type(C_Spell.GetSpellName) == "function" then
			local ok, sName = pcall(C_Spell.GetSpellName, spellID)
			if ok and readable(sName) and type(sName) == "string" and sName ~= "" then
				resolvedName = sName
			end
		end
		if (not resolvedName or resolvedName == "") and spellID and type(GetSpellInfo) == "function" then
			local ok, sName = pcall(GetSpellInfo, spellID)
			if ok and readable(sName) and type(sName) == "string" and sName ~= "" then
				resolvedName = sName
			end
		end
		if not resolvedName or resolvedName == "" then
			resolvedName = (spec and spec.fallback) or profName
		end
		return spellID, resolvedName
	end

	function OrderFlow.GetPendingCraftProfession()
		local crSt = orderFlow.stages.craft
		local tasks = crSt.tasks or {}
		local task = tasks[crSt.activeIndex]
		if not task or (task.remainingCrafts or 0) <= 0 or task.status == "done" or task.status == "skipped" then
			local idx = selectNextPendingCraftInternal(1, nil)
			task = idx and tasks[idx] or nil
		end
		if not task or (task.remainingCrafts or 0) <= 0 or task.status == "done" or task.status == "skipped" then
			return nil
		end
		local openKey = OrderFlow.GetOpenProfession()
		orderFlow.env.openProfKey = openKey
		if openKey == task.profKey then
			return nil
		end
		local profKey = task.profKey
		local _, defName = resolveProfMeta(profKey)
		local profName = (type(task.profName) == "string" and task.profName ~= "") and task.profName or defName
		local spellID, spellName = resolveOpenProfessionSpell(profKey, profName)
		return {
			profKey = profKey,
			profName = profName,
			spellID = spellID,
			spellName = spellName,
		}
	end

	function OrderFlow.ComputeTaskReadiness(task)
		if type(task) ~= "table" then
			return { matsReadyCount = 0, totalReagents = 0, canCraftNow = 0, reagentsWithStock = {} }
		end
		local rev = orderFlow.ownershipRev or 0
		local remCrafts = math.max(0, tonumber(task.remainingCrafts) or 0)
		local cache = task._readinessCache
		if cache and cache.rev == rev and cache.rem == remCrafts and cache.data then
			return cache.data
		end
		local reagents = task.reagents or {}
		local result
		if #reagents == 0 then
			result = {
				matsReadyCount = 0,
				totalReagents = 0,
				canCraftNow = remCrafts,
				reagentsWithStock = {},
			}
		else
			local matsReadyCount = 0
			local minCrafts = math.huge
			local withStock = {}
			for _, r in ipairs(reagents) do
				local have = (r.itemID and r.itemID > 0) and getLiveBagCount(r.itemID) or 0
				local needPer = math.max(1, tonumber(r.qtyPerCraft) or 1)
				local needTotal = needPer * remCrafts
				local craftsPossible = math.floor(have / needPer)
				local ready = (have >= needPer)
				if ready then matsReadyCount = matsReadyCount + 1 end
				if craftsPossible < minCrafts then minCrafts = craftsPossible end
				withStock[#withStock + 1] = {
					itemID = r.itemID,
					name = r.name,
					qtyPerCraft = needPer,
					have = have,
					needPerCraft = needPer,
					needTotal = needTotal,
					craftsPossible = craftsPossible,
					ready = ready,
				}
			end
			local canCraftNow = (minCrafts < math.huge) and math.min(remCrafts, minCrafts) or remCrafts
			result = {
				matsReadyCount = matsReadyCount,
				totalReagents = #reagents,
				canCraftNow = math.max(0, canCraftNow),
				reagentsWithStock = withStock,
			}
		end
		task._readinessCache = { rev = rev, rem = remCrafts, data = result }
		return result
	end

	function OrderFlow.FindRecipeIndexInOpenWindow(task)
		if type(task) ~= "table" then return nil end
		local openKey, openFrame = OrderFlow.GetOpenProfession()
		if not openKey or (task.profKey and openKey ~= task.profKey) then
			return nil
		end
		local targetName = type(task.recipeName) == "string" and task.recipeName or task.name
		local targetNameLower = type(targetName) == "string" and targetName:lower() or nil
		local altNameLower = type(task.name) == "string" and task.name:lower() or nil

		-- Modern ProfessionsFrame / C_TradeSkillUI
		if openFrame == "ProfessionsFrame" and task.spellID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
			local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, task.spellID)
			if ok and tableValue(info) and info.learned ~= false then
				return { api = "modern", spellID = task.spellID, index = nil }
			end
		end

		-- Classic TradeSkillFrame
		if openFrame == "TradeSkillFrame" and GetNumTradeSkills and GetTradeSkillInfo then
			local num = safeNumber(GetNumTradeSkills()) or 0
			local nameMatch = nil
			for i = 1, num do
				local ok, sName, sType = pcall(GetTradeSkillInfo, i)
				if ok and readable(sName) and sType ~= "header" then
					if task.spellID and GetTradeSkillRecipeLink then
						local lok, link = pcall(GetTradeSkillRecipeLink, i)
						if lok and readable(link) and type(link) == "string" then
							local lid = tonumber(link:match("enchant:(%d+)")) or tonumber(link:match("spell:(%d+)"))
							if lid and lid == task.spellID then
								return { api = "tradeskill", index = i, spellID = task.spellID }
							end
						end
					end
					if not nameMatch and type(sName) == "string" then
						local low = sName:lower()
						if sName == targetName or sName == task.name or (targetNameLower and low == targetNameLower) or (altNameLower and low == altNameLower) then
							nameMatch = i
						end
					end
				end
			end
			if nameMatch then
				return { api = "tradeskill", index = nameMatch, spellID = task.spellID }
			end
		end

		-- Classic CraftFrame
		if openFrame == "CraftFrame" and GetNumCrafts and GetCraftInfo then
			local num = safeNumber(GetNumCrafts()) or 0
			local nameMatch = nil
			for i = 1, num do
				local ok, cName, _, cType = pcall(GetCraftInfo, i)
				if ok and readable(cName) and cType ~= "header" then
					if task.spellID and GetCraftRecipeLink then
						local lok, link = pcall(GetCraftRecipeLink, i)
						if lok and readable(link) and type(link) == "string" then
							local lid = tonumber(link:match("enchant:(%d+)")) or tonumber(link:match("spell:(%d+)"))
							if lid and lid == task.spellID then
								return { api = "craft", index = i, spellID = task.spellID }
							end
						end
					end
					if not nameMatch and type(cName) == "string" then
						local low = cName:lower()
						if cName == targetName or cName == task.name or (targetNameLower and low == targetNameLower) or (altNameLower and low == altNameLower) then
							nameMatch = i
						end
					end
				end
			end
			if nameMatch then
				return { api = "craft", index = nameMatch, spellID = task.spellID }
			end
		end

		-- Fallback: modern C_TradeSkillUI when TradeSkillFrame is open on Forever 16001 without classic GetNumTradeSkills
		if task.spellID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.CraftRecipe then
			local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, task.spellID)
			if ok and tableValue(info) and info.learned ~= false then
				return { api = "modern", spellID = task.spellID, index = nil }
			end
		end

		return nil
	end

	function OrderFlow.SelectCraftRecipe(index, fromHardwareClick)
		local crSt = orderFlow.stages.craft
		local idx = index or crSt.activeIndex
		local task = crSt.tasks[idx]
		if not task then return false end
		local hit = OrderFlow.FindRecipeIndexInOpenWindow(task)
		if not hit then return false end
		if hit.api == "modern" then
			local rlist = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
			if rlist and type(rlist.SelectRecipe) == "function" and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
				local iok, info = pcall(C_TradeSkillUI.GetRecipeInfo, hit.spellID)
				if iok and tableValue(info) then
					pcall(rlist.SelectRecipe, rlist, info, true)
					return true
				end
			end
			if fromHardwareClick == true and C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
				pcall(C_TradeSkillUI.OpenRecipe, hit.spellID)
				return true
			end
			return false
		elseif hit.api == "tradeskill" then
			if SelectTradeSkill then pcall(SelectTradeSkill, hit.index) end
			if TradeSkillFrame_SetSelection then pcall(TradeSkillFrame_SetSelection, hit.index) end
			return true
		elseif hit.api == "craft" then
			if SelectCraft then pcall(SelectCraft, hit.index) end
			if CraftFrame_SetSelection then pcall(CraftFrame_SetSelection, hit.index) end
			return true
		end
		return false
	end

	function OrderFlow.GetTaskListBadgeCount()
		local count = 0
		for _, t in ipairs(orderFlow.stages.craft.tasks or {}) do
			if (t.remainingCrafts or 0) > 0 and t.status ~= "done" and t.status ~= "skipped" then
				count = count + 1
			end
		end
		return count
	end

	function OrderFlow.CraftActiveTask(index, qtyOverride)
		local crSt = orderFlow.stages.craft
		local idx = index or crSt.activeIndex
		local task = crSt.tasks[idx]
		if not task then return false, "no_task" end
		if (task.remainingCrafts or 0) <= 0 or task.status == "done" then
			return false, "already_done"
		end
		if InCombatLockdown and InCombatLockdown() then
			orderFlow.notice = "Cannot craft during combat."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "in_combat"
		end
		local openKey, openFrame = OrderFlow.GetOpenProfession()
		orderFlow.env.openProfKey = openKey
		orderFlow.env.openProfFrame = openFrame
		if not openKey or openKey ~= task.profKey then
			orderFlow.notice = "Please open " .. tostring(task.profName or "Profession") .. " to start."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "wrong_profession"
		end
		local readiness = OrderFlow.ComputeTaskReadiness(task)
		if readiness.canCraftNow <= 0 then
			orderFlow.notice = "Missing reagents in bags."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "missing_reagents"
		end
		local hit = OrderFlow.FindRecipeIndexInOpenWindow(task)
		if not hit then
			orderFlow.notice = "Recipe not found in open " .. tostring(task.profName or "Profession") .. " window."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "recipe_not_found"
		end
		local qty = math.max(1, math.min(safeNumber(qtyOverride) or readiness.canCraftNow, readiness.canCraftNow))
		if hit.api == "modern" then
			OrderFlow.SelectCraftRecipe(idx, true)
			if not C_TradeSkillUI.CraftRecipe then return false, "no_api" end
			pcall(C_TradeSkillUI.CraftRecipe, hit.spellID, qty)
		elseif hit.api == "tradeskill" then
			if SelectTradeSkill then pcall(SelectTradeSkill, hit.index) end
			if TradeSkillFrame_SetSelection then pcall(TradeSkillFrame_SetSelection, hit.index) end
			if not DoTradeSkill then return false, "no_api" end
			pcall(DoTradeSkill, hit.index, qty)
		elseif hit.api == "craft" then
			qty = 1
			if SelectCraft then pcall(SelectCraft, hit.index) end
			if CraftFrame_SetSelection then pcall(CraftFrame_SetSelection, hit.index) end
			if not DoCraft then return false, "no_api" end
			pcall(DoCraft, hit.index)
		else
			return false, "unknown_api"
		end
		crSt.activeIndex = idx
		task.status = "active"
		crSt.pendingCraft = {
			taskKey = task.taskKey,
			spellID = task.spellID,
			requestedQty = qty,
			ts = (GetTime and GetTime()) or 0,
		}
		orderFlow.notice = string.format("Crafting %dx %s...", qty, tostring(task.name))
		orderFlow.noticeKind = "info"
		notifyOrderFlow()
		return true
	end

	-----------------------------------------------------------------------------------------------
	-- 4.5b Recipe Batch Total-Time Loading Bar
	-----------------------------------------------------------------------------------------------
	function OrderFlow.FormatDuration(sec)
		local n = safeNumber(sec)
		if not n or n <= 0 then return "0s" end
		if n < 10 then return string.format("%.1fs", n) end
		local total = math.ceil(n)
		if total < 60 then return string.format("0:%02d", total) end
		if total < 3600 then
			local m = math.floor(total / 60)
			local s = total % 60
			return string.format("%dm %02ds", m, s)
		end
		local h = math.floor(total / 3600)
		local m = math.floor((total % 3600) / 60)
		return string.format("%dh %02dm", h, m)
	end

	local INTER_CRAFT_GRACE_SEC = 1.5

	local function resolveEffectiveUnitSec(task)
		if type(task) ~= "table" then return 2.0 end
		local ac = orderFlow.stages.craft.activeCast
		if ac and ac.taskKey == task.taskKey and safeNumber(ac.castMs) and ac.castMs > 0 then
			return ac.castMs / 1000
		end
		if safeNumber(task.measuredCastMs) and task.measuredCastMs > 0 then
			return task.measuredCastMs / 1000
		end
		return resolveTaskCastTimeMs(task) / 1000
	end

	local function findCraftTaskByKey(taskKey)
		if not taskKey then return nil, nil end
		local tasks = (orderFlow.stages.craft and orderFlow.stages.craft.tasks) or {}
		for i, t in ipairs(tasks) do
			if t.taskKey == taskKey then return t, i end
		end
		return nil, nil
	end

	function OrderFlow.GetActiveCraftingTaskKey(nowSec)
		local now = safeNumber(nowSec) or (GetTime and safeNumber(GetTime())) or 0
		local crSt = orderFlow.stages.craft
		local ac = crSt.activeCast
		if ac and ac.taskKey then
			local t = findCraftTaskByKey(ac.taskKey)
			if t and t.status ~= "done" and t.status ~= "skipped" and (t.remainingCrafts or 0) > 0 then
				return ac.taskKey
			end
		end
		local batch = crSt.craftingBatch
		if batch and batch.taskKey then
			local t = findCraftTaskByKey(batch.taskKey)
			if not t or t.status == "done" or t.status == "skipped" or (t.remainingCrafts or 0) <= 0 then
				return nil
			end
			if batch.graceUntilSec and now > batch.graceUntilSec then
				return nil
			end
			return batch.taskKey
		end
		return nil
	end

	function OrderFlow.ExpireCraftingBatchIfNeeded(nowSec)
		local crSt = orderFlow.stages.craft
		if crSt.craftingBatch and not crSt.activeCast then
			if not OrderFlow.GetActiveCraftingTaskKey(nowSec) then
				crSt.craftingBatch = nil
				notifyOrderFlow(true)
				return true
			end
		end
		return false
	end

	function OrderFlow.GetTaskEtaSec(task, nowSec)
		if type(task) ~= "table" then return 0 end
		if task.status == "done" or task.status == "skipped" then return 0 end
		local rem = math.max(0, tonumber(task.remainingCrafts) or 0)
		if rem <= 0 then return 0 end
		local unitSec = resolveEffectiveUnitSec(task)
		local ac = orderFlow.stages.craft.activeCast
		if ac and ac.taskKey == task.taskKey then
			local now = safeNumber(nowSec) or (GetTime and safeNumber(GetTime())) or 0
			local curLeft = math.max(0, (tonumber(ac.endSec) or now) - now)
			return curLeft + math.max(0, rem - 1) * unitSec
		end
		return rem * unitSec
	end

	function OrderFlow.GetCraftTimingSummary(nowSec)
		local now = safeNumber(nowSec) or (GetTime and safeNumber(GetTime())) or 0
		local crSt = orderFlow.stages.craft
		local tasks = crSt.tasks or {}
		local activeTask = tasks[crSt.activeIndex]
		local ac = crSt.activeCast
		local batch = crSt.craftingBatch
		local craftingKey = OrderFlow.GetActiveCraftingTaskKey(now)
		local craftingTask, craftingTaskIdx = findCraftTaskByKey(craftingKey)

		-- Spotlight strictly reflects the selected task; NEVER follow another background craft onto a clicked task.
		local targetTask = activeTask
		local isSelectedTaskCrafting = (targetTask ~= nil and craftingKey ~= nil and targetTask.taskKey == craftingKey)
		local isOtherTaskCrafting = (craftingKey ~= nil and not isSelectedTaskCrafting)
		local casting = isSelectedTaskCrafting
		local castLeftSec, castTotalSec, castFrac = 0, 0, 0
		if isSelectedTaskCrafting and ac and targetTask and ac.taskKey == targetTask.taskKey then
			local s = tonumber(ac.startSec) or now
			local e = tonumber(ac.endSec) or now
			castTotalSec = math.max(0, e - s)
			castLeftSec = math.max(0, e - now)
			if castTotalSec > 0 then
				castFrac = math.max(0, math.min(1, (now - s) / castTotalSec))
			else
				castFrac = 1
			end
		end

		local neededCrafts = targetTask and math.max(0, tonumber(targetTask.neededCrafts) or 0) or 0
		local completedCrafts = targetTask and math.max(0, tonumber(targetTask.completedCrafts) or 0) or 0
		local unitSec = targetTask and resolveEffectiveUnitSec(targetTask) or 0
		local taskTotalSec = neededCrafts * unitSec
		local taskLeftSec, taskElapsedSec, taskFrac = 0, 0, 0

		if targetTask then
			if isSelectedTaskCrafting and ac and ac.taskKey == targetTask.taskKey then
				local rawLeft = OrderFlow.GetTaskEtaSec(targetTask, now)
				if rawLeft > taskTotalSec then taskTotalSec = rawLeft end
				local rawFrac = (taskTotalSec > 0) and math.max(0, math.min(1, (taskTotalSec - rawLeft) / taskTotalSec)) or 0
				local floorFrac = (batch and batch.taskKey == targetTask.taskKey and safeNumber(batch.lastFrac)) or 0
				taskFrac = math.max(floorFrac, rawFrac)
				if batch and batch.taskKey == targetTask.taskKey then
					batch.lastFrac = taskFrac
				end
				taskElapsedSec = taskTotalSec * taskFrac
				taskLeftSec = math.max(0, math.min(rawLeft, taskTotalSec - taskElapsedSec))
			elseif isSelectedTaskCrafting then
				local floorFrac = (batch and batch.taskKey == targetTask.taskKey and safeNumber(batch.lastFrac)) or 0
				local compFrac = (neededCrafts > 0) and math.max(0, math.min(1, completedCrafts / neededCrafts)) or 0
				taskFrac = math.max(floorFrac, compFrac)
				taskElapsedSec = taskTotalSec * taskFrac
				taskLeftSec = math.max(0, taskTotalSec - taskElapsedSec)
			else
				taskLeftSec = (targetTask.status ~= "done" and targetTask.status ~= "skipped")
					and (math.max(0, tonumber(targetTask.remainingCrafts) or 0) * unitSec) or 0
				if taskLeftSec > taskTotalSec then taskTotalSec = taskLeftSec end
				taskElapsedSec = math.max(0, taskTotalSec - taskLeftSec)
				taskFrac = (taskTotalSec > 0) and math.max(0, math.min(1, taskElapsedSec / taskTotalSec)) or 0
				if targetTask.status == "done" or (targetTask.remainingCrafts or 0) <= 0 then
					taskFrac = (taskTotalSec > 0) and 1 or 0
					taskLeftSec = 0
					taskElapsedSec = taskTotalSec
				end
			end
		end

		local targetProf = (isSelectedTaskCrafting and ac and ac.profKey) or orderFlow.env.openProfKey or (targetTask and targetTask.profKey) or nil
		local profLeftSec, queueLeftSec, queueTotalSec = 0, 0, 0
		for _, t in ipairs(tasks) do
			if t.status ~= "skipped" then
				local tTotal = math.max(0, tonumber(t.neededCrafts) or 0) * resolveEffectiveUnitSec(t)
				local eta = OrderFlow.GetTaskEtaSec(t, now)
				if eta > tTotal then tTotal = eta end
				queueTotalSec = queueTotalSec + tTotal
				queueLeftSec = queueLeftSec + eta
				if targetProf and t.profKey == targetProf then
					profLeftSec = profLeftSec + eta
				end
			end
		end
		local queueElapsedSec = math.max(0, queueTotalSec - queueLeftSec)
		local queueFrac = (queueTotalSec > 0) and math.max(0, math.min(1, queueElapsedSec / queueTotalSec)) or 0
		return {
			casting = casting,
			isSelectedTaskCrafting = isSelectedTaskCrafting,
			isOtherTaskCrafting = isOtherTaskCrafting,
			batchActive = (craftingKey ~= nil),
			craftingTaskKey = craftingKey,
			craftingTaskIndex = craftingTaskIdx,
			craftingTaskName = craftingTask and craftingTask.name or nil,
			castLeftSec = castLeftSec,
			castTotalSec = castTotalSec,
			castFrac = castFrac,
			taskTotalSec = taskTotalSec,
			taskLeftSec = taskLeftSec,
			taskElapsedSec = taskElapsedSec,
			taskFrac = taskFrac,
			profLeftSec = profLeftSec,
			queueTotalSec = queueTotalSec,
			queueLeftSec = queueLeftSec,
			queueElapsedSec = queueElapsedSec,
			queueFrac = queueFrac,
			completedCrafts = completedCrafts,
			neededCrafts = neededCrafts,
			taskName = (targetTask and targetTask.name) or nil,
			activeCast = (isSelectedTaskCrafting and ac) or nil,
		}
	end

	function OrderFlow.OnSpellcastStart(unit, spellID, castGUID)
		if not readable(unit) or not readable(spellID) then return false end
		if unit ~= "player" or type(spellID) ~= "number" or spellID <= 0 then return false end
		local crSt = orderFlow.stages.craft
		local tasks = crSt.tasks or {}
		local matchedTask = nil
		if crSt.craftingBatch and crSt.craftingBatch.spellID == spellID and crSt.craftingBatch.taskKey then
			local bt = findCraftTaskByKey(crSt.craftingBatch.taskKey)
			if bt and (bt.remainingCrafts or 0) > 0 and bt.status ~= "done" and bt.status ~= "skipped" then
				matchedTask = bt
			end
		end
		if not matchedTask then
			local cur = tasks[crSt.activeIndex]
			if cur and cur.spellID == spellID and (cur.remainingCrafts or 0) > 0 and cur.status ~= "done" and cur.status ~= "skipped" then
				matchedTask = cur
			else
				for _, t in ipairs(tasks) do
					if t.spellID == spellID and (t.remainingCrafts or 0) > 0 and t.status ~= "done" and t.status ~= "skipped" then
						matchedTask = t
						break
					end
				end
			end
		end
		if not matchedTask then return false end
		local now = (GetTime and safeNumber(GetTime())) or 0
		local startSec, endSec, castMs = nil, nil, nil
		if type(UnitCastingInfo) == "function" then
			local ok, _, _, _, startTimeMS, endTimeMS = pcall(UnitCastingInfo, "player")
			if ok and readable(startTimeMS) and readable(endTimeMS) then
				local sMs, eMs = safeNumber(startTimeMS), safeNumber(endTimeMS)
				if sMs and eMs and eMs > sMs then
					startSec = sMs / 1000
					endSec = eMs / 1000
					castMs = eMs - sMs
				end
			end
		end
		if not startSec or not endSec then
			castMs = resolveTaskCastTimeMs(matchedTask)
			startSec = now
			endSec = now + (castMs / 1000)
		end
		if castMs and castMs > 0 then
			matchedTask.measuredCastMs = castMs
		end
		crSt.activeCast = {
			taskKey = matchedTask.taskKey,
			spellID = spellID,
			castGUID = (readable(castGUID) and castGUID) or nil,
			name = matchedTask.name,
			profKey = matchedTask.profKey,
			startSec = startSec,
			endSec = endSec,
			castMs = castMs,
		}
		local prevBatch = crSt.craftingBatch
		local compFrac = ((matchedTask.neededCrafts or 0) > 0) and ((matchedTask.completedCrafts or 0) / matchedTask.neededCrafts) or 0
		local keepFrac = (prevBatch and prevBatch.taskKey == matchedTask.taskKey and safeNumber(prevBatch.lastFrac))
			and math.max(prevBatch.lastFrac, compFrac) or compFrac
		crSt.craftingBatch = {
			taskKey = matchedTask.taskKey,
			spellID = spellID,
			name = matchedTask.name,
			lastFrac = keepFrac,
			graceUntilSec = nil,
		}
		notifyOrderFlow(true)
		return true
	end

	function OrderFlow.OnSpellcastStop(unit, spellID, interrupted)
		if not readable(unit) or unit ~= "player" then return false end
		if spellID ~= nil and not readable(spellID) then return false end
		local crSt = orderFlow.stages.craft
		local now = (GetTime and safeNumber(GetTime())) or 0
		local changed = false
		if interrupted == true then
			local activeSp = (crSt.activeCast and crSt.activeCast.spellID)
				or (crSt.craftingBatch and crSt.craftingBatch.spellID)
				or (crSt.pendingCraft and crSt.pendingCraft.spellID)
			if spellID ~= nil and activeSp ~= nil and spellID ~= activeSp then
				return false
			end
			if crSt.activeCast or crSt.craftingBatch or crSt.pendingCraft then
				local targetKey = (crSt.activeCast and crSt.activeCast.taskKey)
					or (crSt.craftingBatch and crSt.craftingBatch.taskKey)
					or (crSt.pendingCraft and crSt.pendingCraft.taskKey)
				crSt.activeCast = nil
				crSt.craftingBatch = nil
				crSt.pendingCraft = nil
				if targetKey then
					local t = findCraftTaskByKey(targetKey)
					if t and t.status == "active" and (t.remainingCrafts or 0) > 0 then
						t.status = "pending"
					end
				end
				orderFlow.notice = "Crafting interrupted."
				orderFlow.noticeKind = "warning"
				changed = true
			end
		elseif crSt.activeCast and (spellID == nil or crSt.activeCast.spellID == spellID) then
			local ac = crSt.activeCast
			local matchedTask = findCraftTaskByKey(ac.taskKey)
			local curFrac = (crSt.craftingBatch and crSt.craftingBatch.taskKey == ac.taskKey and safeNumber(crSt.craftingBatch.lastFrac)) or 0
			if matchedTask then
				local unitSec = resolveEffectiveUnitSec(matchedTask)
				local totalSec = math.max(0, tonumber(matchedTask.neededCrafts) or 0) * unitSec
				local rawLeft = OrderFlow.GetTaskEtaSec(matchedTask, now)
				if rawLeft > totalSec then totalSec = rawLeft end
				if totalSec > 0 then
					curFrac = math.max(curFrac, math.min(1, (totalSec - rawLeft) / totalSec))
				end
			end
			crSt.craftingBatch = {
				taskKey = ac.taskKey,
				spellID = ac.spellID,
				name = ac.name,
				lastFrac = curFrac,
				graceUntilSec = now + INTER_CRAFT_GRACE_SEC,
			}
			crSt.activeCast = nil
			changed = true
		end
		if changed then
			notifyOrderFlow(true)
		end
		return changed
	end

	function OrderFlow.OnSpellcastSucceeded(unit, spellID)
		if not readable(unit) or not readable(spellID) then return false end
		if unit ~= "player" or type(spellID) ~= "number" or spellID <= 0 then return false end
		local crSt = orderFlow.stages.craft
		local tasks = crSt.tasks or {}
		local matchedIdx = nil
		if crSt.activeCast and crSt.activeCast.spellID == spellID and crSt.activeCast.taskKey then
			local t, i = findCraftTaskByKey(crSt.activeCast.taskKey)
			if t and (t.remainingCrafts or 0) > 0 and t.status ~= "done" and t.status ~= "skipped" then
				matchedIdx = i
			end
		end
		if not matchedIdx and crSt.craftingBatch and crSt.craftingBatch.spellID == spellID and crSt.craftingBatch.taskKey then
			local t, i = findCraftTaskByKey(crSt.craftingBatch.taskKey)
			if t and (t.remainingCrafts or 0) > 0 and t.status ~= "done" and t.status ~= "skipped" then
				matchedIdx = i
			end
		end
		if not matchedIdx then
			local cur = tasks[crSt.activeIndex]
			if cur and cur.spellID == spellID and (cur.remainingCrafts or 0) > 0 and cur.status ~= "done" and cur.status ~= "skipped" then
				matchedIdx = crSt.activeIndex
			else
				for i, t in ipairs(tasks) do
					if t.spellID == spellID and (t.remainingCrafts or 0) > 0 and t.status ~= "done" and t.status ~= "skipped" then
						matchedIdx = i
						break
					end
				end
			end
		end
		if not matchedIdx then return false end
		local task = tasks[matchedIdx]
		local now = (GetTime and safeNumber(GetTime())) or 0
		if crSt.activeCast and (crSt.activeCast.spellID == spellID or crSt.activeCast.taskKey == task.taskKey) then
			crSt.activeCast = nil
		end
		bumpOwnershipRev()
		task.completedCrafts = (task.completedCrafts or 0) + 1
		task.remainingCrafts = math.max(0, (task.neededCrafts or 1) - task.completedCrafts)
		if task.remainingCrafts <= 0 then
			task.status = "done"
			if crSt.pendingCraft and crSt.pendingCraft.taskKey == task.taskKey then
				crSt.pendingCraft = nil
			end
			if crSt.craftingBatch and crSt.craftingBatch.taskKey == task.taskKey then
				crSt.craftingBatch = nil
			end
			local viewingCompleted = (matchedIdx == crSt.activeIndex)
			local nextIdx = nil
			if viewingCompleted then
				nextIdx = selectNextPendingCraftInternal(matchedIdx + 1, orderFlow.env.openProfKey)
				if nextIdx then
					local nextTask = tasks[nextIdx]
					if orderFlow.env.openProfKey and nextTask and nextTask.profKey == orderFlow.env.openProfKey then
						OrderFlow.SelectCraftRecipe(nextIdx, false)
					end
					orderFlow.notice = string.format("Finished %s! Next: %s.", tostring(task.name), tostring(nextTask and nextTask.name or ""))
					orderFlow.noticeKind = "positive"
				else
					orderFlow.notice = "All crafting tasks complete!"
					orderFlow.noticeKind = "positive"
				end
			else
				orderFlow.notice = string.format("Finished %s!", tostring(task.name))
				orderFlow.noticeKind = "positive"
			end
		else
			local prevBatch = crSt.craftingBatch
			local compFrac = ((task.neededCrafts or 0) > 0) and (task.completedCrafts / task.neededCrafts) or 0
			local keepFrac = (prevBatch and prevBatch.taskKey == task.taskKey and safeNumber(prevBatch.lastFrac))
				and math.max(prevBatch.lastFrac, compFrac) or compFrac
			crSt.craftingBatch = {
				taskKey = task.taskKey,
				spellID = spellID,
				name = task.name,
				lastFrac = keepFrac,
				graceUntilSec = now + INTER_CRAFT_GRACE_SEC,
			}
			orderFlow.notice = string.format("Crafted %s (%d/%d).", tostring(task.name), task.completedCrafts, task.neededCrafts)
			orderFlow.noticeKind = "info"
		end
		notifyOrderFlow()
		return true
	end

	local function handleProfessionOpened()
		bumpOwnershipRev()
		local pk, pf = OrderFlow.GetOpenProfession()
		orderFlow.env.openProfKey = pk
		orderFlow.env.openProfFrame = pf
		if pk then
			local crStats = OrderFlow.GetStageStats("craft")
			if crStats.remaining > 0 then
				local ahDone = OrderFlow.GetStageStats("ah").complete
				local cDone = OrderFlow.GetStageStats("collect").complete
				local vDone = OrderFlow.GetStageStats("vendor").complete
				local matchingIdx = nil
				for i, t in ipairs(orderFlow.stages.craft.tasks or {}) do
					if t.profKey == pk and (t.remainingCrafts or 0) > 0 and t.status ~= "done" and t.status ~= "skipped" and areDependenciesSatisfied(t) then
						matchingIdx = i
						break
					end
				end
				if orderFlow.activeStage == "craft" or (ahDone and cDone and vDone) then
					orderFlow.activeStage = "craft"
					if matchingIdx then
						orderFlow.stages.craft.activeIndex = matchingIdx
						OrderFlow.SelectCraftRecipe(matchingIdx, false)
					end
				end
			end
		end
		notifyOrderFlow()
	end

	function OrderFlow.OnTradeSkillShow()
		handleProfessionOpened()
	end

	function OrderFlow.OnCraftShow()
		handleProfessionOpened()
	end

	function OrderFlow.OnTradeSkillUpdate()
		local prevKey, prevFrame = orderFlow.env.openProfKey, orderFlow.env.openProfFrame
		local pk, pf = OrderFlow.GetOpenProfession()
		orderFlow.env.openProfKey = pk
		orderFlow.env.openProfFrame = pf
		if prevKey ~= pk or prevFrame ~= pf then
			notifyOrderFlow()
		end
	end

	function OrderFlow.OnTradeSkillClosed()
		local pk, pf = OrderFlow.GetOpenProfession()
		orderFlow.env.openProfKey = pk
		orderFlow.env.openProfFrame = pf
		local crSt = orderFlow.stages.craft
		crSt.pendingCraft = nil
		crSt.activeCast = nil
		crSt.craftingBatch = nil
		notifyOrderFlow(true)
	end

	function OrderFlow.OnBagUpdateDelayed()
		bumpOwnershipRev()
		syncLiveEnvironmentInternal()
		-- 1. Reconcile Stage 2 (Vendor) bag deltas
		local vSt = orderFlow.stages.vendor
		if orderFlow.env.atVendor or vSt.pendingBuy ~= nil then
			local vendorCompletedAny = false
			local reconciledAny = false
			for _, it in ipairs(vSt.items or {}) do
				if it.itemID and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
					local liveQty = getLiveBagCount(it.itemID)
					local base = vSt.baselineBagQty[it.itemID]
					if base == nil then
						vSt.baselineBagQty[it.itemID] = liveQty
					elseif liveQty > base then
						local delta = liveQty - base
						vSt.baselineBagQty[it.itemID] = liveQty
						local applied = math.min(it.remaining, delta)
						local sc = math.max(1, math.floor(tonumber(it.stackCount) or 1))
						local addSpent
						if sc > 1 and (tonumber(it.packPrice) or 0) > 0 then
							addSpent = math.ceil(delta / sc) * math.floor(tonumber(it.packPrice))
						else
							local unitC = (it.liveUnit and it.liveUnit > 0) and it.liveUnit or (it.unitPrice or 0)
							addSpent = applied * unitC
						end
						vSt.spentCopper = (tonumber(vSt.spentCopper) or 0) + addSpent
						it.bought = (it.bought or 0) + applied
						it.remaining = math.max(0, (it.needed or 0) - it.bought)
						it.totalPrice = (it.unitPrice or 0) * it.remaining
						reconciledAny = true
						if it.remaining <= 0 then
							it.status = "done"
							vendorCompletedAny = true
						end
					end
				end
			end
			if reconciledAny then
				vSt.pendingBuy = nil
			end
			if vendorCompletedAny then
				local nextIdx = selectNextPendingVendorInternal((vSt.activeIndex or 1) + 1, orderFlow.env.atVendor)
				if not nextIdx then
					orderFlow.notice = "All vendor items are bought!"
					orderFlow.noticeKind = "positive"
				end
			end
		end

		-- 2. Reconcile Stage 3 (Collect Owned: Bank / Mail) bag deltas
		local cSt = orderFlow.stages.collect
		local nextCollectAllSerial = nil
		local stopItemCollectAllDone = false
		if orderFlow.env.atBank or orderFlow.env.atMail or cSt.pendingTake ~= nil then
			local activeSrc = (cSt.pendingTake and cSt.pendingTake.source)
				or (orderFlow.env.atBank and "bank")
				or (orderFlow.env.atMail and "mail")
				or nil
			local pendingIDs = {}
			local seenID = {}
			for _, it in ipairs(cSt.items or {}) do
				if it.itemID and (it.source == "bank" or it.source == "mail")
					and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped"
					and not seenID[it.itemID] then
					seenID[it.itemID] = true
					pendingIDs[#pendingIDs + 1] = it.itemID
				end
			end
			local collectCompletedAny = false
			local reconciledCollect = false
			for _, itemID in ipairs(pendingIDs) do
				local liveQty = getLiveBagCount(itemID)
				local base = cSt.baselineBagQty[itemID]
				if base == nil then
					cSt.baselineBagQty[itemID] = liveQty
				elseif liveQty > base then
					local delta = liveQty - base
					cSt.baselineBagQty[itemID] = liveQty
					local function applyToSource(matchSrc)
						for _, it in ipairs(cSt.items or {}) do
							if delta <= 0 then break end
							if it.itemID == itemID and it.source == matchSrc
								and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
								local applied = math.min(it.remaining, delta)
								it.collected = (it.collected or 0) + applied
								it.remaining = math.max(0, (it.needed or 0) - it.collected)
								delta = delta - applied
								reconciledCollect = true
								if it.remaining <= 0 then
									it.status = "done"
									collectCompletedAny = true
								end
							end
						end
					end
					if activeSrc then applyToSource(activeSrc) end
					-- Never spill across Bank & Mail unless the other container is also open
					if delta > 0 then
						if activeSrc ~= "bank" and orderFlow.env.atBank then applyToSource("bank") end
						if delta > 0 and activeSrc ~= "mail" and orderFlow.env.atMail then applyToSource("mail") end
					end
				end
			end
			if reconciledCollect then
				cSt.pendingTake = nil
			end
			-- Always refresh open Bank / Mailbox slot caches so Forever Character Bank Tabs & multi-click loot never hit stale slot #1
			if orderFlow.env.atBank then OrderFlow.ScanOpenBank() end
			if orderFlow.env.atMail then OrderFlow.ScanOpenMailbox() end
			if collectCompletedAny then
				local pref = (orderFlow.env.atBank and not orderFlow.env.atMail) and "bank" or "mail"
				local nextIdx = selectNextPendingCollectInternal((cSt.activeIndex or 1) + 1, pref)
				if not nextIdx then
					orderFlow.notice = "All owned items collected!"
					orderFlow.noticeKind = "positive"
				end
			end
			if reconciledCollect and cSt.collectAll and cSt.collectAll.active then
				local ca = cSt.collectAll
				if activeSrc == nil or ca.source == activeSrc then
					ca.collectedCount = (ca.collectedCount or 0) + 1
					if ca.mode == "item" and ca.targetItem
						and ((ca.targetItem.remaining or 0) <= 0 or ca.targetItem.status == "done") then
						stopItemCollectAllDone = true
					else
						nextCollectAllSerial = ca.serial
					end
				end
			end
		end

		-- 3. Recompute Stage 4 (Craft) live bag readiness
		local crSt = orderFlow.stages.craft
		for _, t in ipairs(crSt.tasks or {}) do
			t._readiness = OrderFlow.ComputeTaskReadiness(t)
		end

		-- 4. Recompute Stage 5 (Sell) live bag counts & reconcile pending vendor sell(s)
		local sl = orderFlow.stages.sell
		if sl and type(sl.items) == "table" then
			for _, it in ipairs(sl.items) do
				if it.itemID and it.itemID > 0 then
					it.inBags = getSellableBagCount(it.itemID, it.channel == "vendor", it.itemLink)
				end
			end
			if sl.pendingVendorSell then
				local entries = (type(sl.pendingVendorSell[1]) == "table") and sl.pendingVendorSell or { sl.pendingVendorSell }
				local vendDoneAny = false
				for _, pv in ipairs(entries) do
					local it = pv and sl.items[pv.itemIndex]
					if it and it.itemID == pv.itemID then
						local curBags = getLiveBagCount(it.itemID)
						it.inBags = curBags
						local delta = math.max(0, (pv.beforeBags or curBags) - curBags)
						if delta > 0 then
							local applied = math.min(it.remaining or 0, delta)
							it.soldQty = (it.soldQty or 0) + applied
							it.remaining = math.max(0, (it.totalQty or 0) - it.soldQty)
							sl.totalEarnedCopper = (sl.totalEarnedCopper or 0) + applied * (it.vendorSell or 0)
							if it.remaining <= 0 then
								it.status = "done"
								vendDoneAny = true
							end
						end
					end
				end
				sl.pendingVendorSell = nil
				if vendDoneAny then
					selectNextPendingSellInternal(1, "vendor")
				end
			end
		end

		if stopItemCollectAllDone then
			OrderFlow.StopCollectAll("done")
		else
			notifyOrderFlow()
		end
		if nextCollectAllSerial then
			scheduleNextCollectAllStep(nextCollectAllSerial)
		end
	end

	function OrderFlow.MarkCraftDone(index)
		local crSt = orderFlow.stages.craft
		local idx = index or crSt.activeIndex
		local task = crSt.tasks[idx]
		if not task then return false end
		bumpOwnershipRev()
		if crSt.activeCast and crSt.activeCast.taskKey == task.taskKey then
			crSt.activeCast = nil
		end
		task.completedCrafts = task.neededCrafts
		task.remainingCrafts = 0
		task.status = "done"
		local nextIdx = selectNextPendingCraftInternal(idx + 1, orderFlow.env.openProfKey)
		if nextIdx then
			local nextTask = crSt.tasks[nextIdx]
			if orderFlow.env.openProfKey and nextTask and nextTask.profKey == orderFlow.env.openProfKey then
				OrderFlow.SelectCraftRecipe(nextIdx, false)
			end
		else
			orderFlow.notice = "All crafting tasks complete!"
			orderFlow.noticeKind = "positive"
		end
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SkipCraftTask(index)
		local crSt = orderFlow.stages.craft
		local idx = index or crSt.activeIndex
		local task = crSt.tasks[idx]
		if not task then return false end
		bumpOwnershipRev()
		if crSt.activeCast and crSt.activeCast.taskKey == task.taskKey then
			crSt.activeCast = nil
		end
		task.status = "skipped"
		selectNextPendingCraftInternal(idx + 1, orderFlow.env.openProfKey)
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SelectCraftTask(index)
		local crSt = orderFlow.stages.craft
		if not index or index < 1 or index > #crSt.tasks then return end
		crSt.activeIndex = index
		local task = crSt.tasks[index]
		if task and orderFlow.env.openProfKey and task.profKey == orderFlow.env.openProfKey then
			OrderFlow.SelectCraftRecipe(index, false)
		end
		notifyOrderFlow()
	end

	function OrderFlow.SelectNextPendingCraft()
		local nextIdx = selectNextPendingCraftInternal((orderFlow.stages.craft.activeIndex or 1) + 1, orderFlow.env.openProfKey)
		if nextIdx then
			local task = orderFlow.stages.craft.tasks[nextIdx]
			if task and orderFlow.env.openProfKey and task.profKey == orderFlow.env.openProfKey then
				OrderFlow.SelectCraftRecipe(nextIdx, false)
			end
		end
		notifyOrderFlow()
		return nextIdx
	end

	-----------------------------------------------------------------------------------------------
	-- 4.5 Stage 5 (Sell: Auctionator-Parity AH Selling + Vendor Channel)
	-----------------------------------------------------------------------------------------------
	local SELL_UNDERCUT_ORDER = { "match", "1c", "1s", "pct" }
	local SELL_POST_WATCHDOG_SEC = 15
	local SELL_SEARCH_WATCHDOG_SEC = 15
	local SELL_THROTTLE_WEDGE_SEC = 8
	OrderFlow.SELL_THROTTLE_WEDGE_SEC = SELL_THROTTLE_WEDGE_SEC

	local function nowSellMono(overrideSec)
		local ov = safeNumber(overrideSec)
		if ov ~= nil then return ov end
		if type(GetTime) == "function" then
			local ok, t = pcall(GetTime)
			if ok and safeNumber(t) then return t end
		end
		if type(time) == "function" then
			local ok, t = pcall(time)
			if ok and safeNumber(t) then return t end
		end
		return 0
	end

	local function isSellLegacyAH()
		return (_G.IsUsingLegacyAuctionClient and _G.IsUsingLegacyAuctionClient()) == true
	end

	local function isSellThrottledReady(nowSec)
		local sl = orderFlow.stages.sell
		if not (C_AuctionHouse and type(C_AuctionHouse.IsThrottledMessageSystemReady) == "function") then
			if sl then sl.throttleBlockedAt = nil end
			return true
		end
		local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
		if (not ok) or (readable(ready) and ready ~= false) then
			if sl then sl.throttleBlockedAt = nil end
			return true
		end
		local now = nowSellMono(nowSec)
		if sl then
			if not sl.throttleBlockedAt or now < sl.throttleBlockedAt then
				sl.throttleBlockedAt = now
				return false
			end
			if (now - sl.throttleBlockedAt) >= SELL_THROTTLE_WEDGE_SEC then
				return true
			end
		end
		return false
	end

	-- Forever 16001 supports full 1c copper precision (no 1s Retail rounding)
	function OrderFlow.NormalizeSellPrice(price)
		local n = safeNumber(price)
		if not n or n <= 0 then return 0 end
		return math.max(1, math.floor(n + 0.5))
	end

	local function isSellEquipmentClass(classID)
		return classID == 2 or classID == 4 or classID == 19
	end

	local function extractBattlePetInfo(link)
		if type(link) ~= "string" or not link:find("battlepet:", 1, true) then return nil, nil end
		local sp, lvl = link:match("battlepet:(%d+):(%d+)")
		if not sp then
			sp = link:match("battlepet:(%d+)")
		end
		return sp and tonumber(sp) or nil, lvl and tonumber(lvl) or 0
	end

	local function doesSellItemMatchFromKey(origKey, origLink, targetKey, targetLink)
		local origSpecies, origPetLvl = extractBattlePetInfo(origLink)
		if origSpecies then
			local tgtSpecies, tgtPetLvl = extractBattlePetInfo(targetLink)
			if tgtSpecies and tgtSpecies ~= origSpecies then return false end
			if tgtPetLvl and origPetLvl and origPetLvl > 0 and tgtPetLvl > 0 then
				return origPetLvl == tgtPetLvl
			end
			if targetKey and safeNumber(targetKey.battlePetSpeciesID) and targetKey.battlePetSpeciesID > 0 then
				return targetKey.battlePetSpeciesID == origSpecies
			end
			return true
		end
		if not tableValue(origKey) or not tableValue(targetKey) then return true end
		local oLvl = safeNumber(origKey.itemLevel) or 0
		local tLvl = safeNumber(targetKey.itemLevel) or 0
		local oSuf = safeNumber(origKey.itemSuffix) or 0
		local tSuf = safeNumber(targetKey.itemSuffix) or 0
		if oLvl > 0 and tLvl > 0 and oLvl ~= tLvl then return false end
		if (oSuf ~= 0 or tSuf ~= 0) and oSuf ~= tSuf then return false end
		return true
	end
	OrderFlow.DoesSellItemMatchFromKey = doesSellItemMatchFromKey

	local function sellPriceSortSpec(isCommodity)
		local enum = _G.Enum and _G.Enum.AuctionHouseSortOrder
		if isCommodity then
			local priceOrder = (type(enum) == "table" and enum.Price ~= nil) and enum.Price or 0
			return { { sortOrder = priceOrder, reverseSort = false } }
		else
			local buyoutOrder = (type(enum) == "table" and enum.Buyout ~= nil) and enum.Buyout or 4
			return { { sortOrder = buyoutOrder, reverseSort = false } }
		end
	end

	local function dispatchSellSearchQuery(ah, key, isCommodity, isEquipment)
		if not ah or not key then return false end
		local sorts = sellPriceSortSpec(isCommodity)
		local ok = false
		if isEquipment then
			if type(ah.SendSellSearchQuery) == "function" then
				ok = pcall(ah.SendSellSearchQuery, key, sorts, true)
			end
			if not ok and type(ah.SendSearchQuery) == "function" then
				ok = pcall(ah.SendSearchQuery, key, sorts, true)
			end
		else
			if type(ah.SendSearchQuery) == "function" then
				ok = pcall(ah.SendSearchQuery, key, sorts, true)
			end
			if not ok and type(ah.SendSellSearchQuery) == "function" then
				ok = pcall(ah.SendSellSearchQuery, key, sorts, true)
			end
		end
		return ok
	end

	local MAX_COMMODITY_STACKS_PER_AUCTION = 40

	local function makeSellItemKeys(itemID, loc, isCommodity, itemLink, isEquipment, itemLevelHint)
		local ah = _G.C_AuctionHouse
		local speciesID = extractBattlePetInfo(itemLink)
		local actualKey = nil
		if ah and type(ah.GetItemKeyFromItem) == "function" and loc ~= nil then
			local ok, k = pcall(ah.GetItemKeyFromItem, loc)
			if ok and tableValue(k) and safeNumber(k.itemID) then
				actualKey = {
					itemID = math.floor(safeNumber(k.itemID) or itemID),
					itemLevel = isCommodity and 0 or math.floor(safeNumber(k.itemLevel) or 0),
					itemSuffix = isCommodity and 0 or math.floor(safeNumber(k.itemSuffix) or 0),
					battlePetSpeciesID = math.floor(safeNumber(k.battlePetSpeciesID) or (speciesID or 0)),
				}
			end
		end
		if not actualKey then
			if ah and type(ah.MakeItemKey) == "function" then
				local ok, k = pcall(ah.MakeItemKey, itemID, (not isCommodity and itemLevelHint) or 0, 0, speciesID or 0)
				if ok and tableValue(k) then
					actualKey = {
						itemID = math.floor(safeNumber(k.itemID) or itemID),
						itemLevel = isCommodity and 0 or math.floor(safeNumber(k.itemLevel) or (itemLevelHint or 0)),
						itemSuffix = isCommodity and 0 or math.floor(safeNumber(k.itemSuffix) or 0),
						battlePetSpeciesID = math.floor(safeNumber(k.battlePetSpeciesID) or (speciesID or 0)),
					}
				end
			end
		end
		if not actualKey then
			actualKey = {
				itemID = itemID,
				itemLevel = isCommodity and 0 or (itemLevelHint or 0),
				itemSuffix = 0,
				battlePetSpeciesID = speciesID or 0,
			}
		end
		if (not isCommodity) and (actualKey.itemLevel or 0) <= 0 and (itemLevelHint or 0) > 0 then
			actualKey.itemLevel = math.floor(itemLevelHint)
		end

		local queryKey
		if isEquipment and not isCommodity then
			-- Auctionator SaleItem.lua:404: equipment queries itemLevel=0/itemSuffix=0 and filters locally
			queryKey = { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
		elseif speciesID then
			queryKey = { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = speciesID }
		elseif isCommodity then
			queryKey = { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
		else
			queryKey = {
				itemID = actualKey.itemID,
				itemLevel = actualKey.itemLevel or 0,
				itemSuffix = actualKey.itemSuffix or 0,
				battlePetSpeciesID = actualKey.battlePetSpeciesID or 0,
			}
		end
		return queryKey, actualKey
	end

	local function sellItemKeySig(k)
		if not tableValue(k) then return "" end
		return tostring(math.floor(safeNumber(k.itemID) or 0)) .. ":"
			.. tostring(math.floor(safeNumber(k.itemLevel) or 0)) .. ":"
			.. tostring(math.floor(safeNumber(k.itemSuffix) or 0)) .. ":"
			.. tostring(math.floor(safeNumber(k.battlePetSpeciesID) or 0))
	end

	local function resolveSellItemInfoSafe(itemID, link)
		local ci = _G.C_Item
		local getInfo = (ci and ci.GetItemInfo) or _G.GetItemInfo
		local name, outLink, quality, itemLevel, className, maxStack, icon, sellPrice, classID, isReagent = nil, link, 1, 0, nil, 1, nil, 0, nil, false
		if type(getInfo) == "function" then
			local okM, nm, lnk, q, ilvl, _, iType, _, ms, _, ic, sp, cid, _, _, _, _, isReag = pcall(getInfo, link or itemID)
			if okM then
				if readable(nm) and type(nm) == "string" and nm ~= "" then name = nm end
				if (not outLink or outLink == "") and readable(lnk) and type(lnk) == "string" then outLink = lnk end
				if safeNumber(q) then quality = math.floor(q) end
				if safeNumber(ilvl) and ilvl > 0 then itemLevel = math.floor(ilvl) end
				if readable(iType) and type(iType) == "string" and iType ~= "" then className = iType end
				if safeNumber(ms) and ms >= 1 then maxStack = math.floor(ms) end
				if readable(ic) then icon = ic end
				if safeNumber(sp) and sp > 0 then sellPrice = math.floor(sp) end
				if safeNumber(cid) then classID = math.floor(cid) end
				if readable(isReag) then isReagent = (isReag == true) end
			end
		end
		if ci and type(ci.GetDetailedItemLevelInfo) == "function" and (outLink or itemID) then
			local okD, dLvl = pcall(ci.GetDetailedItemLevelInfo, outLink or itemID)
			if okD and safeNumber(dLvl) and dLvl > 0 then
				itemLevel = math.floor(dLvl)
			end
		end
		return {
			name = name,
			itemLink = outLink,
			quality = quality,
			itemLevel = itemLevel,
			className = className,
			maxStack = maxStack,
			icon = icon,
			vendorSell = sellPrice,
			classID = classID,
			isCraftingReagent = isReagent,
		}
	end

	local function getItemMaxStackSafe(itemID, link)
		local meta = resolveSellItemInfoSafe(itemID, link)
		return meta.maxStack or 1
	end

	local function findSellableBagSlot(itemID, requiredQty, expectedLink)
		itemID = safeNumber(itemID)
		if not itemID or itemID <= 0 then return nil end
		local req = math.max(1, math.floor(safeNumber(requiredQty) or 1))
		local ci = _G.C_Item
		local ah = _G.C_AuctionHouse
		local bestLoc, bestBag, bestSlot, bestCount, bestComm, bestLink, bestMaxStack, totalAvail = nil, nil, nil, 0, nil, nil, 1, 0
		local bestMeta = nil
		local hasCInfo = (C_Container and type(C_Container.GetContainerItemInfo) == "function")
		for _, bag in ipairs(getBagContainerList()) do
			local slots = getContainerNumSlotsSafe(bag)
			for slot = 1, slots do
				local sid, cnt, locked, info = nil, 0, false, nil
				if hasCInfo then
					local okI, rawInfo = pcall(C_Container.GetContainerItemInfo, bag, slot)
					if okI and tableValue(rawInfo) then
						info = rawInfo
						sid = safeNumber(rawInfo.itemID)
						if (not sid or sid <= 0) and readable(rawInfo.hyperlink) and type(rawInfo.hyperlink) == "string" then
							sid = tonumber(rawInfo.hyperlink:match("item:(%d+)"))
						end
						cnt = safeNumber(rawInfo.stackCount) or 1
						locked = (readable(rawInfo.isLocked) and rawInfo.isLocked == true)
					end
				else
					sid, cnt, locked = getContainerSlotInfoSafe(bag, slot)
				end
				if sid == itemID and not locked and cnt and cnt > 0 then
					local slotLink = (info and readable(info.hyperlink) and type(info.hyperlink) == "string") and info.hyperlink or nil
					local loc = createSellBagLocation(bag, slot)
					local exists = true
					if ci and type(ci.DoesItemExist) == "function" then
						local okE, ex = pcall(ci.DoesItemExist, loc)
						exists = (okE and readable(ex) and ex == true)
					end
					if exists and not isSellSlotBound(loc, info) then
						local sellable = true
						if ah and type(ah.IsSellItemValid) == "function" then
							local okV, v = pcall(ah.IsSellItemValid, loc, false)
							if okV and readable(v) and v == false then sellable = false end
						end
						if sellable then
							local meta = resolveSellItemInfoSafe(itemID, slotLink)
							local maxStack = meta.maxStack or 1
							local isComm = nil
							if ah and type(ah.GetItemCommodityStatus) == "function" then
								local okS, st = pcall(ah.GetItemCommodityStatus, loc)
								local stNum = okS and safeNumber(st) or nil
								local enum = _G.Enum and _G.Enum.ItemCommodityStatus
								local commVal = (enum and safeNumber(enum.Commodity)) or 2
								local itemVal = (enum and safeNumber(enum.Item)) or 1
								if stNum == commVal then
									isComm = true
								elseif stNum == itemVal then
									isComm = false
								end
							end
							if isComm == nil then
								isComm = (maxStack > 1)
							end
							local linkMatch = isComm or (not expectedLink) or expectedLink == "" or (slotLink == nil) or (slotLink == expectedLink)
							if linkMatch then
								totalAvail = totalAvail + cnt
								if not bestLoc or cnt > bestCount then
									bestLoc, bestBag, bestSlot, bestCount, bestComm, bestLink, bestMaxStack = loc, bag, slot, cnt, isComm, slotLink, maxStack
									bestMeta = meta
								end
							end
						end
					end
				end
			end
		end
		if not bestLoc then return nil end
		local apiAvail = nil
		if ah and type(ah.GetAvailablePostCount) == "function" then
			local okA, availCnt = pcall(ah.GetAvailablePostCount, bestLoc)
			local nAvail = okA and safeNumber(availCnt) or nil
			if nAvail ~= nil and nAvail >= 0 then
				apiAvail = math.floor(nAvail)
			end
		end
		local maxPostQty
		if bestComm then
			local commCap = math.max(1, bestMaxStack) * MAX_COMMODITY_STACKS_PER_AUCTION
			maxPostQty = apiAvail ~= nil and math.min(totalAvail, apiAvail, commCap) or math.min(totalAvail, commCap)
		else
			maxPostQty = apiAvail ~= nil and math.min(totalAvail, apiAvail) or totalAvail
		end
		if maxPostQty < 1 then return nil end
		return {
			location = bestLoc,
			bag = bestBag,
			slot = bestSlot,
			stackCount = bestCount,
			totalAvail = totalAvail,
			maxPostQty = maxPostQty,
			maxStack = bestMaxStack,
			itemLink = bestLink or (bestMeta and bestMeta.itemLink) or nil,
			isCommodity = bestComm == true,
			enoughForReq = (maxPostQty >= req),
			classID = bestMeta and bestMeta.classID or nil,
			itemLevel = bestMeta and bestMeta.itemLevel or 0,
			quality = bestMeta and bestMeta.quality or 1,
			vendorSell = bestMeta and bestMeta.vendorSell or 0,
			isCraftingReagent = bestMeta and bestMeta.isCraftingReagent == true or false,
		}
	end

	function OrderFlow.IsSellItemCommodity(item)
		if not tableValue(item) or not item.itemID or item.itemID <= 0 then return false end
		local bagInfo = findSellableBagSlot(item.itemID, 1, item.itemLink)
		if bagInfo then
			item.isCommodity = (bagInfo.isCommodity == true)
			return item.isCommodity
		end
		if item.isCommodity ~= nil then return item.isCommodity == true end
		return getItemMaxStackSafe(item.itemID, item.itemLink) > 1
	end

	function OrderFlow.GetSellPostLimit(itemOrIndex)
		local sl = orderFlow.stages.sell
		local it = type(itemOrIndex) == "table" and itemOrIndex
			or (sl and sl.items and sl.items[itemOrIndex or sl.activeIndex])
		if not tableValue(it) or not it.itemID or it.itemID <= 0 then return 0, nil end
		if it.channel == "vendor" then
			local cnt = getSellableBagCount(it.itemID, true, it.itemLink)
			return cnt, nil
		end
		local bagInfo = findSellableBagSlot(it.itemID, 1, it.itemLink)
		if not bagInfo then return 0, nil end
		return bagInfo.maxPostQty or 0, bagInfo
	end

	local function resolveDefaultSellPostQty(it, limit)
		if limit <= 0 then return 0 end
		if it.isFromBag then
			local cid = it.classID
			local isSingle = (cid == 2 or cid == 4 or cid == 17)
				or (type(it.itemLink) == "string" and it.itemLink:find("battlepet:", 1, true) ~= nil)
			if isSingle then return 1 end
			return limit
		end
		local rem = math.max(0, math.floor(tonumber(it.remaining) or 0))
		if rem <= 0 then return 0 end
		return math.min(rem, limit)
	end

	function OrderFlow.GetSellPostQty(itemOrIndex)
		local sl = orderFlow.stages.sell
		local it = type(itemOrIndex) == "table" and itemOrIndex
			or (sl and sl.items and sl.items[itemOrIndex or sl.activeIndex])
		if not tableValue(it) then return 0, 0 end
		if it.channel == "vendor" then
			local limit = OrderFlow.GetSellPostLimit(it)
			local q = math.max(0, math.floor(tonumber(it.remaining) or 0))
			return q, limit
		end
		local limit = OrderFlow.GetSellPostLimit(it)
		if limit <= 0 then
			it.postQty = 0
			return 0, 0
		end
		if it.postQty == nil then
			it.postQty = resolveDefaultSellPostQty(it, limit)
		elseif it.postQty > limit then
			it.postQty = limit
		elseif it.postQty == 0 and (not it.customQty) and it.status ~= "done" and it.status ~= "skipped" and (it.remaining or 0) > 0 then
			it.postQty = resolveDefaultSellPostQty(it, limit)
		end
		return math.max(0, math.floor(it.postQty or 0)), limit
	end

	local QUALITY_HEX_FALLBACK = {
		[0] = "9d9d9d",
		[1] = "ffffff",
		[2] = "1eff00",
		[3] = "0070dd",
		[4] = "a335ee",
		[5] = "ff8000",
		[6] = "e6cc80",
		[7] = "00ccff",
	}

	function OrderFlow.FormatSellItemTitle(item)
		if not tableValue(item) then return "" end
		local base = tostring(item.name or "Item")
		local _, petLvl = extractBattlePetInfo(item.itemLink)
		local cid = item.classID
		local ilvl = safeNumber(item.itemLevel) or 0
		if (cid == nil or ilvl <= 0 or item.quality == nil) and item.itemID and item.itemID > 0 then
			local meta = resolveSellItemInfoSafe(item.itemID, item.itemLink)
			if cid == nil then cid = meta.classID; item.classID = cid end
			if ilvl <= 0 and (meta.itemLevel or 0) > 0 then ilvl = meta.itemLevel; item.itemLevel = ilvl end
			if item.quality == nil and meta.quality ~= nil then item.quality = meta.quality end
		end
		if petLvl and petLvl > 0 then
			base = string.format("%s (%d)", base, math.floor(petLvl))
		elseif isSellEquipmentClass(cid) and ilvl > 0 then
			base = string.format("%s (%d)", base, math.floor(ilvl))
		end
		local q = math.floor(safeNumber(item.quality) or 1)
		local qColors = _G.ITEM_QUALITY_COLORS
		local qc = type(qColors) == "table" and qColors[q] or nil
		if qc and qc.color and type(qc.color.WrapTextInColorCode) == "function" then
			local okW, wrapped = pcall(qc.color.WrapTextInColorCode, qc.color, base)
			if okW and type(wrapped) == "string" then return wrapped end
		elseif qc and type(qc.hex) == "string" and qc.hex ~= "" then
			return qc.hex .. base .. "|r"
		end
		local hex = QUALITY_HEX_FALLBACK[q] or "ffffff"
		return "|cff" .. hex .. base .. "|r"
	end

	local function applySellUndercut(basePrice, undercutMode, undercutPct)
		local p = math.max(1, math.floor(safeNumber(basePrice) or 1))
		if undercutMode == "match" then
			return p
		elseif undercutMode == "1c" then
			return math.max(1, p - 1)
		elseif undercutMode == "1s" then
			return math.max(1, p - 100)
		elseif undercutMode == "pct" then
			local pct = math.max(0, math.min(50, safeNumber(undercutPct) or 1))
			return math.max(1, math.floor(p * (100 - pct) / 100))
		end
		return p
	end

	function OrderFlow.CalculateItemPriceFromPrice(basePrice, undercutMode, undercutPct)
		local sl = orderFlow.stages.sell
		local mode = undercutMode or (sl and sl.undercutMode) or "match"
		local pct = undercutPct or (sl and sl.undercutPct) or 1
		return applySellUndercut(basePrice, mode, pct)
	end

	local function selectNextPendingSellInternal(fromIndex, channelFilter)
		local sl = orderFlow.stages.sell
		local n = #(sl.items or {})
		if n == 0 then sl.activeIndex = 1; return nil end
		local start = fromIndex or sl.activeIndex or 1
		for offset = 0, n - 1 do
			local idx = ((start - 1 + offset) % n) + 1
			local it = sl.items[idx]
			if it and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
				if not channelFilter or it.channel == channelFilter then
					sl.activeIndex = idx
					return idx
				end
			end
		end
		return nil
	end

	function OrderFlow.HasOtherPendingSellItem(index)
		local sl = orderFlow.stages.sell
		local idx = index or (sl and sl.activeIndex) or 1
		for i, it in ipairs((sl and sl.items) or {}) do
			if i ~= idx and it and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
				return true
			end
		end
		return false
	end

	function OrderFlow.SetSellDuration(durIdx)
		local sl = orderFlow.stages.sell
		local d = math.floor(safeNumber(durIdx) or 2)
		if d ~= 1 and d ~= 2 and d ~= 3 then d = 2 end
		sl.duration = d
		sl.warningConfirm = nil
		notifyOrderFlow()
		return d
	end

	function OrderFlow.SetSellUndercutMode(mode)
		local sl = orderFlow.stages.sell
		if mode ~= "match" and mode ~= "1c" and mode ~= "1s" and mode ~= "pct" then
			return sl.undercutMode or "match"
		end
		sl.undercutMode = mode
		sl.warningConfirm = nil
		notifyOrderFlow()
		return sl.undercutMode
	end

	function OrderFlow.CycleSellUndercutMode()
		local sl = orderFlow.stages.sell
		local cur = sl.undercutMode or "match"
		local nextMode = "match"
		for i, m in ipairs(SELL_UNDERCUT_ORDER) do
			if m == cur then
				nextMode = SELL_UNDERCUT_ORDER[(i % #SELL_UNDERCUT_ORDER) + 1]
				break
			end
		end
		sl.undercutMode = nextMode
		sl.warningConfirm = nil
		notifyOrderFlow()
		return nextMode
	end

	function OrderFlow.SetSellItemQty(index, qty)
		local sl = orderFlow.stages.sell
		local idx = index or sl.activeIndex
		local it = sl.items[idx]
		if not it then return false end
		sl.warningConfirm = nil
		local rawQ = math.max(0, math.floor((tonumber(qty) or 0) + 0.5))
		if it.channel == "vendor" then
			local q = math.max(1, rawQ)
			it.remaining = q
			it.totalQty = (it.soldQty or 0) + q
			it.needed = it.totalQty
			it.postQty = q
			it.customQty = true
			if it.itemID and it.itemID > 0 then
				it.inBags = getSellableBagCount(it.itemID, true, it.itemLink)
			end
			if it.status == "done" or it.status == "skipped" then
				it.status = "pending"
			end
			notifyOrderFlow()
			return true
		end
		local limit = OrderFlow.GetSellPostLimit(it)
		local clamped = (limit > 0) and math.min(rawQ, limit) or 0
		it.postQty = clamped
		it.customQty = true
		if it.itemID and it.itemID > 0 then
			it.inBags = getSellableBagCount(it.itemID, false, it.itemLink)
		end
		if clamped > 0 then
			if it.status == "done" or it.status == "skipped" then
				it.status = "pending"
			end
			if (it.remaining or 0) < clamped then
				it.remaining = clamped
				it.totalQty = (it.soldQty or 0) + clamped
				it.needed = it.totalQty
			end
		end
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SetSellItemMaxQty(index)
		local sl = orderFlow.stages.sell
		local idx = index or sl.activeIndex
		local it = sl.items[idx]
		if not it then return false end
		local limit = OrderFlow.GetSellPostLimit(it)
		if limit <= 0 then return false end
		return OrderFlow.SetSellItemQty(idx, limit)
	end

	function OrderFlow.SetSellItemPrice(index, buyoutCopper, bidCopper)
		local sl = orderFlow.stages.sell
		local idx = index or sl.activeIndex
		local it = sl.items[idx]
		if not it then return false end
		sl.warningConfirm = nil
		local isComm = OrderFlow.IsSellItemCommodity(it)
		if buyoutCopper == nil then
			it.customPrice = nil
		else
			it.customPrice = OrderFlow.NormalizeSellPrice(buyoutCopper)
		end
		if isComm then
			it.bidPrice = 0
		elseif bidCopper ~= nil then
			it.bidPrice = OrderFlow.NormalizeSellPrice(bidCopper)
		end
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SetSellItemBidPrice(index, bidCopper)
		local sl = orderFlow.stages.sell
		local idx = index or sl.activeIndex
		local it = sl.items[idx]
		if not it then return false end
		sl.warningConfirm = nil
		if OrderFlow.IsSellItemCommodity(it) then
			it.bidPrice = 0
			return false
		end
		it.bidPrice = OrderFlow.NormalizeSellPrice(bidCopper)
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SelectSellListingPrice(listingRow, forceMatch)
		local sl = orderFlow.stages.sell
		local it = sl and sl.items and sl.items[sl.activeIndex]
		if not it or type(listingRow) ~= "table" then return false end
		local basePrice = safeNumber(listingRow.price)
		if not basePrice or basePrice <= 0 then
			basePrice = safeNumber(listingRow.bidPrice)
		end
		if not basePrice or basePrice <= 0 then return false end
		local shouldUndercut = (forceMatch ~= true) and (listingRow.containsOwnerItem ~= true)
		local newBuyout = shouldUndercut
			and OrderFlow.CalculateItemPriceFromPrice(basePrice)
			or OrderFlow.NormalizeSellPrice(basePrice)
		local isComm = OrderFlow.IsSellItemCommodity(it)
		local newBid = 0
		if not isComm then
			local rowBid = safeNumber(listingRow.bidPrice) or 0
			local existingBid = safeNumber(it.bidPrice) or 0
			if rowBid > 0 and rowBid < newBuyout then
				newBid = OrderFlow.NormalizeSellPrice(rowBid)
			elseif rowBid <= 0 and existingBid > 0 and existingBid < newBuyout then
				newBid = OrderFlow.NormalizeSellPrice(existingBid)
			else
				newBid = 0
			end
		end
		return OrderFlow.SetSellItemPrice(sl.activeIndex, newBuyout, newBid)
	end

	function OrderFlow.ComputeSellUnitPrice(item)
		if not tableValue(item) then return 0, "none", 0 end
		local sl = orderFlow.stages.sell
		local isComm = OrderFlow.IsSellItemCommodity(item)
		local bid = isComm and 0 or math.max(0, math.floor(safeNumber(item.bidPrice) or 0))
		if item.customPrice ~= nil then
			return math.max(0, math.floor(safeNumber(item.customPrice) or 0)), "custom", bid
		end
		local live = safeNumber(item.liveUnit)
		if live and live > 0 then
			if item.liveIsOwn then
				return math.max(1, math.floor(live)), "live_own", bid
			end
			return applySellUndercut(live, sl.undercutMode or "match", sl.undercutPct or 1), "live_ah", bid
		end
		local can = (item.itemID and ns.GetCanonicalItemPrice) and ns.GetCanonicalItemPrice(item.itemID) or nil
		if can and safeNumber(can.price) and can.price > 0 then
			local cp = math.floor(can.price + 0.5)
			item.marketRef = cp
			item.marketRefSource = can.kind or "snap"
			return cp, "market_db", bid
		end
		local mref = math.floor(safeNumber(item.marketRef) or 0)
		if mref > 0 then
			return mref, "market_db", bid
		end
		local vs = math.floor(safeNumber(item.vendorSell) or 0)
		if vs > 0 then
			return vs * 2, "vendor_fallback", bid
		end
		return 0, "none", bid
	end

	function OrderFlow.ComputeSellDeposit(item, durIdx, qty)
		if not tableValue(item) then return 0, false end
		local sl = orderFlow.stages.sell
		local d = math.floor(safeNumber(durIdx) or (sl and sl.duration) or 2)
		if d ~= 1 and d ~= 2 and d ~= 3 then d = 2 end
		local count = math.max(0, math.floor(safeNumber(qty) or 0))
		if count <= 0 then return 0, false end
		local ah = _G.C_AuctionHouse
		local bagInfo = (item.itemID and item.itemID > 0) and findSellableBagSlot(item.itemID, 1, item.itemLink) or nil
		if atAH() and ah then
			if bagInfo and bagInfo.isCommodity and type(ah.CalculateCommodityDeposit) == "function" then
				local ok, dep = pcall(ah.CalculateCommodityDeposit, item.itemID, d, count)
				local n = ok and safeNumber(dep) or nil
				if n and n >= 0 then return OrderFlow.NormalizeSellPrice(n), true end
			elseif bagInfo and (not bagInfo.isCommodity) and bagInfo.location and type(ah.CalculateItemDeposit) == "function" then
				local ok, dep = pcall(ah.CalculateItemDeposit, bagInfo.location, d, count)
				local n = ok and safeNumber(dep) or nil
				if n and n >= 0 then return OrderFlow.NormalizeSellPrice(n), true end
			elseif (not bagInfo) and item.itemID and item.itemID > 0 and OrderFlow.IsSellItemCommodity(item)
				and type(ah.CalculateCommodityDeposit) == "function" then
				local ok, dep = pcall(ah.CalculateCommodityDeposit, item.itemID, d, count)
				local n = ok and safeNumber(dep) or nil
				if n and n >= 0 then return OrderFlow.NormalizeSellPrice(n), true end
			end
		end
		local durRec = ns.POST_DURATIONS and ns.POST_DURATIONS[d]
		local mult = (durRec and durRec.mult) or ((d == 1 and 0.05) or (d == 2 and 0.20) or 0.60)
		local sell = safeNumber(item.vendorSell) or 0
		if sell <= 0 and item.itemID and ns.GetVendorSellPrice then
			local okV, v = pcall(ns.GetVendorSellPrice, item.itemID)
			if okV and safeNumber(v) and v > 0 then sell = v end
		end
		local dep = (sell > 0) and math.max(100, math.floor(sell * count * mult + 0.5)) or 100
		return OrderFlow.NormalizeSellPrice(dep), false
	end

	function OrderFlow.ComputeSellTotalPrice(item, qtyOverride, buyoutOverride, bidOverride)
		if not tableValue(item) then return 0 end
		local qty = safeNumber(qtyOverride)
		if qty == nil then
			qty = OrderFlow.GetSellPostQty(item)
		end
		qty = math.max(0, math.floor(qty or 0))
		if qty <= 0 then return 0 end
		local buyout, _, bid = OrderFlow.ComputeSellUnitPrice(item)
		if buyoutOverride ~= nil then buyout = math.max(0, math.floor(safeNumber(buyoutOverride) or 0)) end
		if bidOverride ~= nil then bid = math.max(0, math.floor(safeNumber(bidOverride) or 0)) end
		local eff = (buyout > 0) and buyout or bid
		return qty * eff
	end

	-- Exact Auctionator PriceWarningThreshold.lua formula
	function OrderFlow.ComputeCommodityPriceWarningThreshold(unitPrice)
		local u = safeNumber(unitPrice) or 0
		if u <= 0 then return 0 end
		local mult = 0.3 + 0.4 * math.min(1, 10000 / u)
		return u * mult
	end

	-- Exact Auctionator IsVendorable.lua rule
	function OrderFlow.IsSellItemVendorable(item)
		if not tableValue(item) then return false, 0 end
		local sell = safeNumber(item.vendorSell) or 0
		local quality = item.quality
		local isReagent = (item.isCraftingReagent == true)
		if (sell <= 0 or quality == nil) and item.itemID and item.itemID > 0 then
			local meta = resolveSellItemInfoSafe(item.itemID, item.itemLink)
			if sell <= 0 and (meta.vendorSell or 0) > 0 then sell = meta.vendorSell end
			if quality == nil then quality = meta.quality end
			if not isReagent and meta.isCraftingReagent then isReagent = true end
		end
		if sell <= 0 and item.itemID and ns.GetVendorSellPrice then
			local okV, v = pcall(ns.GetVendorSellPrice, item.itemID)
			if okV and safeNumber(v) and v > 0 then sell = math.floor(v) end
		end
		local enumQ = _G.Enum and _G.Enum.ItemQuality
		local artQ = (enumQ and safeNumber(enumQ.Artifact)) or 6
		local legQ = (enumQ and safeNumber(enumQ.Legendary)) or 5
		local isArtifact = (quality == artQ)
		local isLegendary = (quality == legQ)
		local okVend = (sell > 0) and (not isArtifact) and (isReagent or not isLegendary)
		return okVend, sell
	end

	function OrderFlow.GetSellConfirmationWarning(itemOrIndex, opts)
		local sl = orderFlow.stages.sell
		local it = type(itemOrIndex) == "table" and itemOrIndex
			or (sl and sl.items and sl.items[itemOrIndex or sl.activeIndex])
		if not tableValue(it) or it.channel == "vendor" then return nil, nil end
		opts = type(opts) == "table" and opts or {}
		local qty = safeNumber(opts.qty)
		if qty == nil then qty = OrderFlow.GetSellPostQty(it) end
		qty = math.max(0, math.floor(qty or 0))
		local buyout, _, bid = OrderFlow.ComputeSellUnitPrice(it)
		if opts.unitPrice ~= nil then buyout = math.max(0, math.floor(safeNumber(opts.unitPrice) or 0)) end
		if opts.bidPrice ~= nil then bid = math.max(0, math.floor(safeNumber(opts.bidPrice) or 0)) end
		local isComm = OrderFlow.IsSellItemCommodity(it)
		if isComm then bid = 0 end
		local effectiveUnitPrice = (buyout > 0) and buyout or bid
		if qty <= 0 or effectiveUnitPrice <= 0 then return nil, nil end

		local isVend, vendorPrice = OrderFlow.IsSellItemVendorable(it)
		local netUnit = math.floor(effectiveUnitPrice * 0.95)
		if isVend and vendorPrice > 0
			and ((vendorPrice * qty) > math.floor(effectiveUnitPrice * qty * 0.95) or vendorPrice > netUnit) then
			return "below_vendor", string.format(
				"Below vendor value! After 5%% AH cut you receive %s/ea, while a vendor pays %s/ea. Confirm to post anyway.",
				ns.FormatMoneyCompact(netUnit),
				ns.FormatMoneyCompact(vendorPrice)
			)
		end
		if it.priceThreshold ~= nil and it.priceThreshold > 0 and effectiveUnitPrice <= it.priceThreshold then
			return "low_price", string.format("Price %s is far below market. Click Confirm Low Price to post anyway.",
				ns.FormatMoneyCompact(effectiveUnitPrice))
		end
		return nil, nil
	end

	-- Exact Auctionator SaleItem.lua:598-633 GetPostButtonState gate
	function OrderFlow.GetSellPostButtonState(index, opts)
		local sl = orderFlow.stages.sell
		if not sl then return false, "no_stage" end
		if isSellLegacyAH() then return false, "legacy_ah" end
		if not atAH() then return false, "ah_closed" end
		if sl.pendingPost ~= nil then return false, "post_in_flight" end
		if not isSellThrottledReady() then return false, "throttled" end

		local idx = index or sl.activeIndex
		local it = sl.items[idx]
		if not it then return false, "no_item" end
		if it.channel == "vendor" then return false, "vendor_channel" end
		if (it.remaining or 0) <= 0 or it.status == "done" or it.status == "skipped" then
			return false, "already_done"
		end

		local limit, bagInfo = OrderFlow.GetSellPostLimit(it)
		if not bagInfo or (bagInfo.totalAvail or 0) <= 0 or limit <= 0 then
			return false, "not_in_bags"
		end
		local ci = _G.C_Item
		if ci and type(ci.DoesItemExist) == "function" then
			local okE, ex = pcall(ci.DoesItemExist, bagInfo.location)
			if not (okE and readable(ex) and ex == true) then
				return false, "missing_location"
			end
		end

		opts = type(opts) == "table" and opts or {}
		local qty = safeNumber(opts.qty)
		if qty == nil then qty = OrderFlow.GetSellPostQty(it) end
		qty = math.floor(qty or 0)
		if qty <= 0 or qty > limit then
			return false, "invalid_qty"
		end

		local isComm = bagInfo.isCommodity == true
		local buyout, _, bid = OrderFlow.ComputeSellUnitPrice(it)
		if opts.unitPrice ~= nil then buyout = math.max(0, math.floor(safeNumber(opts.unitPrice) or 0)) end
		if opts.bidPrice ~= nil then bid = math.max(0, math.floor(safeNumber(opts.bidPrice) or 0)) end
		if isComm then bid = 0 end

		local priceValid = false
		if buyout > 0 then
			if isComm or bid < buyout then
				priceValid = true
			else
				return false, "bid_ge_buyout"
			end
		elseif (not isComm) and buyout == 0 and bid > 0 then
			priceValid = true
		end
		if not priceValid then
			return false, "invalid_price"
		end

		local dur = safeNumber(opts.duration) or sl.duration or 2
		dur = (dur == 1 or dur == 2 or dur == 3) and dur or 2
		local dep = OrderFlow.ComputeSellDeposit(it, dur, qty)
		if type(_G.GetMoney) == "function" then
			local okM, rawMoney = pcall(_G.GetMoney)
			local playerCopper = okM and safeNumber(rawMoney) or nil
			if playerCopper ~= nil and dep and playerCopper < dep then
				return false, "insufficient_money", dep
			end
		end

		return true, nil, dep
	end

	function OrderFlow.SelectSellItem(index)
		local sl = orderFlow.stages.sell
		if not index or index < 1 or index > #(sl.items or {}) then return false end
		sl.activeIndex = index
		sl.warningConfirm = nil
		sl.scanRetrySerial = (sl.scanRetrySerial or 0) + 1
		local it = sl.items[index]
		if it then
			it.bidPrice = 0
			if it.itemID and it.itemID > 0 then
				it.inBags = getSellableBagCount(it.itemID, it.channel == "vendor", it.itemLink)
			end
			OrderFlow.GetSellPostQty(it)
		end
		if atAH() and it and it.channel == "ah"
			and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
			OrderFlow.ScanSellItemMarket(index, "select")
		end
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SetSellItemChannel(index, channel)
		local sl = orderFlow.stages.sell
		local idx = index or sl.activeIndex
		local it = sl.items[idx]
		if not it then return false end
		sl.warningConfirm = nil
		sl.scanRetrySerial = (sl.scanRetrySerial or 0) + 1
		it.channel = (channel == "vendor") and "vendor" or "ah"
		if it.itemID and it.itemID > 0 then
			it.inBags = getSellableBagCount(it.itemID, it.channel == "vendor", it.itemLink)
		end
		if it.channel == "ah" and atAH() and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
			OrderFlow.ScanSellItemMarket(idx, "select")
		end
		notifyOrderFlow()
		return true
	end

	function OrderFlow.ToggleSellItemChannel(index)
		local sl = orderFlow.stages.sell
		local idx = index or sl.activeIndex
		local it = sl.items[idx]
		if not it then return false end
		local nextCh = (it.channel == "vendor") and "ah" or "vendor"
		OrderFlow.SetSellItemChannel(idx, nextCh)
		return it.channel
	end

	function OrderFlow.SetAllSellChannel(channel)
		local sl = orderFlow.stages.sell
		local ch = (channel == "vendor") and "vendor" or "ah"
		sl.warningConfirm = nil
		for _, it in ipairs(sl.items or {}) do
			if it.status ~= "done" and it.status ~= "skipped" then
				it.channel = ch
			end
		end
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SkipSellItem(index)
		local sl = orderFlow.stages.sell
		local idx = index or sl.activeIndex
		local n = #(sl.items or {})
		if n <= 1 or not sl.items[idx] then return false, "no_other_pending" end
		local nextIdx = nil
		for offset = 1, n - 1 do
			local cand = ((idx - 1 + offset) % n) + 1
			local it = sl.items[cand]
			if it and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
				nextIdx = cand
				break
			end
		end
		if not nextIdx then return false, "no_other_pending" end
		sl.warningConfirm = nil
		OrderFlow.SelectSellItem(nextIdx)
		return true, nextIdx
	end

	function OrderFlow.MarkSellDone(index)
		local sl = orderFlow.stages.sell
		local idx = index or sl.activeIndex
		local it = sl.items[idx]
		if not it then return false end
		sl.warningConfirm = nil
		it.soldQty = it.totalQty or it.needed or 1
		it.remaining = 0
		it.postQty = 0
		it.status = "done"
		local nextIdx = selectNextPendingSellInternal(idx + 1, nil)
		if nextIdx and atAH() and sl.items[nextIdx] and sl.items[nextIdx].channel == "ah" then
			sl.items[nextIdx].bidPrice = 0
			OrderFlow.ScanSellItemMarket(nextIdx, "select")
		end
		notifyOrderFlow()
		return true
	end

	local SELL_CATEGORY_META = {
		[2]  = { name = "Weapon",        order = 1 },
		[4]  = { name = "Armor",         order = 2 },
		[0]  = { name = "Consumable",    order = 3 },
		[7]  = { name = "Trade Goods",   order = 4 },
		[5]  = { name = "Reagent",       order = 5 },
		[3]  = { name = "Gem",           order = 6 },
		[9]  = { name = "Recipe",        order = 7 },
		[1]  = { name = "Container",     order = 8 },
		[17] = { name = "Battle Pets",   order = 9 },
		[15] = { name = "Miscellaneous", order = 10 },
	}

	function OrderFlow.ScanSellableBags()
		local sl = orderFlow.stages.sell
		local inQueueByKey = {}
		for _, it in ipairs((sl and sl.items) or {}) do
			if it.itemID and it.status ~= "done" and it.status ~= "skipped" then
				local itComm
				if it.isCommodity ~= nil then
					itComm = (it.isCommodity == true)
				else
					itComm = OrderFlow.IsSellItemCommodity(it)
				end
				if (not itComm) and it.itemLink and it.itemLink ~= "" then
					inQueueByKey[it.itemLink] = true
				else
					inQueueByKey[it.itemID] = true
				end
			end
		end
		local ci = _G.C_Item
		local ah = _G.C_AuctionHouse
		local hasCInfo = (C_Container and type(C_Container.GetContainerItemInfo) == "function")
		local enumComm = _G.Enum and _G.Enum.ItemCommodityStatus
		local commVal = (enumComm and safeNumber(enumComm.Commodity)) or 2
		local itemVal = (enumComm and safeNumber(enumComm.Item)) or 1
		local byKey = {}
		local out = {}
		for _, bag in ipairs(getBagContainerList()) do
			local slots = getContainerNumSlotsSafe(bag)
			for slot = 1, slots do
				local sid, cnt, locked = nil, 0, false
				local rawInfo, iconTex, quality, link = nil, nil, nil, nil
				if hasCInfo then
					local okI, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
					if okI and tableValue(info) then
						rawInfo = info
						sid = safeNumber(info.itemID)
						if readable(info.hyperlink) and type(info.hyperlink) == "string" then
							link = info.hyperlink
							if not sid or sid <= 0 then
								sid = tonumber(link:match("item:(%d+)"))
							end
						end
						cnt = safeNumber(info.stackCount) or 1
						locked = (readable(info.isLocked) and info.isLocked == true)
						if readable(info.iconFileID) then iconTex = info.iconFileID end
						if readable(info.quality) then quality = safeNumber(info.quality) end
					end
				else
					sid, cnt, locked = getContainerSlotInfoSafe(bag, slot)
				end
				if sid and sid > 0 and not locked and cnt and cnt > 0 then
					-- Fast-path duplicate commodity stacks without repeating item/AH API calls
					local existing = byKey[sid]
					if existing and existing.isCommodity then
						local boundKnown = (rawInfo ~= nil and readable(rawInfo.isBound) and type(rawInfo.isBound) == "boolean")
						local isBnd = boundKnown and (rawInfo.isBound == true)
							or ((not boundKnown) and isSellSlotBound(createSellBagLocation(bag, slot), rawInfo))
						if not isBnd then
							existing.totalCount = existing.totalCount + cnt
						end
					else
						local loc = createSellBagLocation(bag, slot)
						local exists = true
						if ci and type(ci.DoesItemExist) == "function" then
							local okE, ex = pcall(ci.DoesItemExist, loc)
							exists = (okE and readable(ex) and ex == true)
						end
						if exists and not isSellSlotBound(loc, rawInfo) then
							local ahValid = true
							if ah and type(ah.IsSellItemValid) == "function" then
								local okV, v = pcall(ah.IsSellItemValid, loc, false)
								if okV and readable(v) and v == false then ahValid = false end
							end
							local vendorSell = 0
							if ns.GetVendorSellPrice then
								local okVS, vs = pcall(ns.GetVendorSellPrice, sid)
								if okVS and safeNumber(vs) and vs > 0 then vendorSell = math.floor(vs) end
							end
							local meta = resolveSellItemInfoSafe(sid, link)
							local itemName = meta.name
							local classID = meta.classID
							local maxStack = meta.maxStack or 1
							if quality == nil then quality = meta.quality end
							if not iconTex then iconTex = meta.icon end
							if vendorSell <= 0 and (meta.vendorSell or 0) > 0 then vendorSell = meta.vendorSell end
							-- Match Auctionator: hide Poor (grey) non-equipment from AH posting
							if quality == 0 and classID ~= 2 and classID ~= 4 then
								ahValid = false
							end
							if ahValid or vendorSell > 0 then
								local isComm = nil
								if ah and type(ah.GetItemCommodityStatus) == "function" then
									local okS, st = pcall(ah.GetItemCommodityStatus, loc)
									local stNum = okS and safeNumber(st) or nil
									if stNum == commVal then isComm = true
									elseif stNum == itemVal then isComm = false end
								end
								if isComm == nil then isComm = (maxStack > 1) end
								local recKey = ((not isComm) and link and link ~= "") and link or sid
								local rec = byKey[recKey]
								if rec then
									rec.totalCount = rec.totalCount + cnt
									if ahValid then rec.ahValid = true end
								else
									local catMeta = classID and SELL_CATEGORY_META[classID] or nil
									local catName = (catMeta and catMeta.name)
										or ((meta.className and meta.className ~= "" and meta.className ~= "Misc") and meta.className)
										or "Miscellaneous"
									local catOrder = (catMeta and catMeta.order) or 10
									local inQ = (inQueueByKey[recKey] == true)
										or ((not isComm) and (not link or link == "") and inQueueByKey[sid] == true)
									rec = {
										itemID = sid,
										itemLink = link,
										name = itemName or itemSearchName(sid) or ("Item #" .. tostring(sid)),
										icon = iconTex,
										quality = quality or 1,
										itemLevel = meta.itemLevel or 0,
										classID = classID,
										className = catName,
										catOrder = catOrder,
										totalCount = cnt,
										vendorSell = vendorSell,
										ahValid = ahValid,
										isCommodity = isComm == true,
										inQueue = inQ,
									}
									byKey[recKey] = rec
									out[#out + 1] = rec
								end
							end
						end
					end
				end
			end
		end
		table.sort(out, function(a, b)
			if (a.catOrder or 99) ~= (b.catOrder or 99) then return (a.catOrder or 99) < (b.catOrder or 99) end
			if (a.quality or 1) ~= (b.quality or 1) then return (a.quality or 1) > (b.quality or 1) end
			if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
			return (a.itemID or 0) < (b.itemID or 0)
		end)
		return out
	end

	function OrderFlow.AddBagItemToSell(itemID, qtyOverride, opts)
		itemID = safeNumber(itemID)
		if not itemID or itemID <= 0 then return false, "invalid_item" end
		opts = type(opts) == "table" and opts or {}
		local sl = orderFlow.stages.sell
		sl.warningConfirm = nil
		local defaultChannel = (opts.channel == "vendor") and "vendor" or "ah"
		local reqLink = (type(opts.itemLink) == "string" and opts.itemLink ~= "") and opts.itemLink or nil
		local inBags = getSellableBagCount(itemID, defaultChannel == "vendor", reqLink)
		local explicitQty = safeNumber(qtyOverride)
		local addQty = math.max(1, math.floor(explicitQty or (inBags > 0 and inBags or 1)))

		local bagInfoAdd = findSellableBagSlot(itemID, 1, reqLink)
		local meta = resolveSellItemInfoSafe(itemID, reqLink or (bagInfoAdd and bagInfoAdd.itemLink))
		local isCommAdd = bagInfoAdd and (bagInfoAdd.isCommodity == true) or ((meta.maxStack or 1) > 1)
		local classID = (bagInfoAdd and bagInfoAdd.classID) or opts.classID or meta.classID
		local itemLevel = (bagInfoAdd and bagInfoAdd.itemLevel) or opts.itemLevel or meta.itemLevel or 0
		local quality = (bagInfoAdd and bagInfoAdd.quality) or opts.quality or meta.quality or 1
		local effLink = reqLink or (bagInfoAdd and bagInfoAdd.itemLink) or meta.itemLink
		local isSingleDefault = (classID == 2 or classID == 4 or classID == 17)
			or (type(effLink) == "string" and effLink:find("battlepet:", 1, true) ~= nil)

		-- If already present, select & refresh/reactivate (keep non-commodity random-suffix variants separate by itemLink)
		for idx, it in ipairs(sl.items or {}) do
			local linkMatch = isCommAdd
				or (not reqLink)
				or (not it.itemLink or it.itemLink == "")
				or (it.itemLink == reqLink)
			if it.itemID == itemID and linkMatch then
				if effLink and (not it.itemLink or it.itemLink == "") then it.itemLink = effLink end
				it.classID = classID or it.classID
				it.itemLevel = (itemLevel > 0) and itemLevel or it.itemLevel
				it.quality = quality or it.quality
				it.inBags = inBags
				it.bidPrice = 0
				if it.status == "done" or it.status == "skipped" then
					it.totalQty = math.max(addQty, inBags)
					it.needed = it.totalQty
					it.soldQty = 0
					it.remaining = it.totalQty
					it.status = "pending"
				else
					local nextTot = math.max(it.totalQty or 1, (it.soldQty or 0) + addQty, inBags)
					it.totalQty = nextTot
					it.needed = nextTot
					it.remaining = math.max(0, nextTot - (it.soldQty or 0))
				end
				local lim = OrderFlow.GetSellPostLimit(it)
				if explicitQty ~= nil then
					it.postQty = (lim > 0) and math.min(math.floor(explicitQty), lim) or 0
				elseif isSingleDefault then
					it.postQty = (lim > 0) and 1 or 0
				else
					it.postQty = lim
				end
				sl.activeIndex = idx
				if atAH() and it.channel == "ah" then
					OrderFlow.ScanSellItemMarket(idx, "select")
				end
				orderFlow.notice = "Updated " .. tostring(it.name) .. " in Sell list."
				orderFlow.noticeKind = "positive"
				notifyOrderFlow()
				return true, idx
			end
		end

		local vendorSell = (meta.vendorSell or 0)
		if vendorSell <= 0 and ns.GetVendorSellPrice then
			local okV, v = pcall(ns.GetVendorSellPrice, itemID)
			if okV and safeNumber(v) and v > 0 then vendorSell = math.floor(v) end
		end
		local costBasis = 0
		if type(ns.GetItemCostBasis) == "function" then
			local okC, c = pcall(ns.GetItemCostBasis, itemID)
			if okC and safeNumber(c) and c > 0 then costBasis = math.floor(c) end
		end
		local marketRef = 0
		if ns.GetItemMarketPrice then
			local okM, mp = pcall(ns.GetItemMarketPrice, itemID)
			if okM and safeNumber(mp) and mp > 0 then marketRef = math.floor(mp + 0.5) end
		end

		local dispName = (type(opts.name) == "string" and opts.name ~= "" and opts.name)
			or meta.name
			or itemSearchName(itemID)
			or ("Item #" .. tostring(itemID))
		local initLimit = (defaultChannel == "vendor") and inBags or (bagInfoAdd and bagInfoAdd.maxPostQty or 0)
		local initPostQty
		if defaultChannel == "vendor" then
			initPostQty = addQty
		elseif initLimit <= 0 then
			initPostQty = 0
		elseif explicitQty ~= nil and opts.useDefaultQty ~= true then
			initPostQty = math.min(math.floor(explicitQty), initLimit)
		elseif isSingleDefault then
			initPostQty = 1
		else
			initPostQty = initLimit
		end

		local entry = {
			itemID = itemID,
			itemLink = effLink,
			name = dispName,
			quality = quality,
			itemLevel = itemLevel,
			classID = classID,
			isCommodity = isCommAdd == true,
			isCraftingReagent = (meta.isCraftingReagent == true),
			isFromBag = true,
			totalQty = addQty,
			needed = addQty,
			soldQty = 0,
			remaining = addQty,
			postQty = initPostQty,
			inBags = inBags,
			channel = defaultChannel,
			liveUnit = nil,
			liveIsOwn = false,
			liveCheckedAt = 0,
			existingValue = nil,
			priceThreshold = nil,
			currentListings = nil,
			listingsScanned = false,
			marketRef = marketRef,
			vendorSell = vendorSell,
			costBasis = costBasis,
			customPrice = nil,
			bidPrice = 0,
			status = "pending",
			provenance = {},
		}
		sl.items[#sl.items + 1] = entry
		local newIdx = #sl.items
		sl.activeIndex = newIdx
		if atAH() and entry.channel == "ah" then
			OrderFlow.ScanSellItemMarket(newIdx, "select")
		end
		orderFlow.notice = "Added " .. tostring(dispName) .. " (" .. tostring(addQty) .. "x) to Sell list."
		orderFlow.noticeKind = "positive"
		notifyOrderFlow()
		return true, newIdx
	end

	function OrderFlow.RemoveSellItem(index)
		local sl = orderFlow.stages.sell
		local idx = index or sl.activeIndex
		if not idx or idx < 1 or idx > #(sl.items or {}) then return false end
		local removed = table.remove(sl.items, idx)
		sl.warningConfirm = nil
		if sl.pendingPost then
			if sl.pendingPost.itemIndex == idx then
				if sl.pendingPost.multisellActive and C_AuctionHouse and type(C_AuctionHouse.CancelSell) == "function" then
					pcall(C_AuctionHouse.CancelSell)
				end
				sl.pendingPost = nil
				sl.postSerial = (sl.postSerial or 0) + 1
				if sl.pendingSearch == nil and ns.AHChannel and ns.AHChannel.Release then
					ns.AHChannel.Release("orderflow_sell")
				end
			elseif sl.pendingPost.itemIndex and sl.pendingPost.itemIndex > idx then
				sl.pendingPost.itemIndex = sl.pendingPost.itemIndex - 1
			end
		end
		if sl.pendingSearch then
			if sl.pendingSearch.itemIndex == idx then
				sl.pendingSearch = nil
				sl.pendingKeyPrime = nil
				sl.searchSerial = (sl.searchSerial or 0) + 1
				if sl.pendingPost == nil and ns.AHChannel and ns.AHChannel.Release then
					ns.AHChannel.Release("orderflow_sell")
				end
			elseif sl.pendingSearch.itemIndex and sl.pendingSearch.itemIndex > idx then
				sl.pendingSearch.itemIndex = sl.pendingSearch.itemIndex - 1
			end
		end
		if #sl.items == 0 then
			sl.activeIndex = 1
		else
			if sl.activeIndex > #sl.items then
				sl.activeIndex = #sl.items
			elseif sl.activeIndex > idx then
				sl.activeIndex = sl.activeIndex - 1
			end
		end
		orderFlow.notice = "Removed " .. tostring(removed and removed.name or "item") .. " from Sell list."
		orderFlow.noticeKind = "info"
		notifyOrderFlow()
		return true
	end

	function OrderFlow.ClearSellQueue()
		local sl = orderFlow.stages and orderFlow.stages.sell
		if not sl then return false end
		if sl.pendingPost then
			if sl.pendingPost.multisellActive and _G.C_AuctionHouse and type(_G.C_AuctionHouse.CancelSell) == "function" then
				pcall(_G.C_AuctionHouse.CancelSell)
			end
			sl.pendingPost = nil
			sl.postSerial = (sl.postSerial or 0) + 1
		end
		if sl.pendingSearch then
			sl.pendingSearch = nil
			sl.pendingKeyPrime = nil
			sl.searchSerial = (sl.searchSerial or 0) + 1
		end
		if ns.AHChannel and ns.AHChannel.Release then
			ns.AHChannel.Release("orderflow_sell")
		end
		sl.items = {}
		sl.activeIndex = 1
		sl.warningConfirm = nil
		sl.postAllActive = false
		sl.lastItemInfo = nil
		sl.lastItemListings = nil
		orderFlow.notice = "Cleared Sell Queue."
		orderFlow.noticeKind = "info"
		notifyOrderFlow()
		return true
	end

	function OrderFlow.AddCursorItemToSell(bag, slot)
		local ci = _G.C_Item
		local ah = _G.C_AuctionHouse
		local cc = _G.C_Container
		local itemID, link, quality = nil, nil, nil
		if bag ~= nil and slot ~= nil then
			bag = safeNumber(bag)
			slot = safeNumber(slot)
			if not bag or not slot then return false, "invalid_slot" end
			local rawInfo = nil
			if cc and type(cc.GetContainerItemInfo) == "function" then
				local okI, info = pcall(cc.GetContainerItemInfo, bag, slot)
				if okI and tableValue(info) then
					rawInfo = info
					itemID = safeNumber(info.itemID)
					if readable(info.hyperlink) and type(info.hyperlink) == "string" then link = info.hyperlink end
					if readable(info.quality) then quality = safeNumber(info.quality) end
				end
			end
			if not itemID then
				local sid = getContainerSlotInfoSafe(bag, slot)
				itemID = sid
			end
			if not itemID or itemID <= 0 then return false, "empty_slot" end
			local loc = createSellBagLocation(bag, slot)
			if ci and type(ci.DoesItemExist) == "function" then
				local okE, ex = pcall(ci.DoesItemExist, loc)
				if not (okE and readable(ex) and ex == true) then
					return false, "missing_item"
				end
			end
			if isSellSlotBound(loc, rawInfo) then
				if type(_G.ClearCursor) == "function" then pcall(_G.ClearCursor) end
				orderFlow.notice = "Cannot sell soulbound item."
				orderFlow.noticeKind = "warning"
				notifyOrderFlow()
				return false, "bound"
			end
			if ah and type(ah.IsSellItemValid) == "function" then
				local okV, v = pcall(ah.IsSellItemValid, loc, false)
				if okV and readable(v) and v == false then
					if type(_G.ClearCursor) == "function" then pcall(_G.ClearCursor) end
					orderFlow.notice = "Item cannot be sold on Auction House."
					orderFlow.noticeKind = "warning"
					notifyOrderFlow()
					return false, "not_sellable"
				end
			end
		elseif type(_G.GetCursorInfo) == "function" then
			local okC, cType, cId, cLink = pcall(_G.GetCursorInfo)
			if okC and cType == "item" then
				itemID = safeNumber(cId)
				if readable(cLink) and type(cLink) == "string" then link = cLink end
			elseif okC and cType == "battlepet" and cId then
				-- Battlepet cages have itemID 82800 when caged
				itemID = 82800
				if readable(cLink) and type(cLink) == "string" then link = cLink end
			end
			if not itemID or itemID <= 0 then return false, "no_cursor_item" end
			local loc = (_G.C_Cursor and type(_G.C_Cursor.GetCursorItem) == "function") and _G.C_Cursor.GetCursorItem() or nil
			if loc then
				if isSellSlotBound(loc, nil) then
					if type(_G.ClearCursor) == "function" then pcall(_G.ClearCursor) end
					orderFlow.notice = "Cannot sell soulbound item."
					orderFlow.noticeKind = "warning"
					notifyOrderFlow()
					return false, "bound"
				end
				if ah and type(ah.IsSellItemValid) == "function" then
					local okV, v = pcall(ah.IsSellItemValid, loc, false)
					if okV and readable(v) and v == false then
						if type(_G.ClearCursor) == "function" then pcall(_G.ClearCursor) end
						orderFlow.notice = "Item cannot be sold on Auction House."
						orderFlow.noticeKind = "warning"
						notifyOrderFlow()
						return false, "not_sellable"
					end
				end
			end
		else
			return false, "no_cursor_item"
		end
		if type(_G.ClearCursor) == "function" then
			pcall(_G.ClearCursor)
		end
		return OrderFlow.AddBagItemToSell(itemID, nil, {
			itemLink = link,
			quality = quality,
			useDefaultQty = true,
		})
	end

	local dispatchSellScanInternal

	local function scheduleSellScanRetry(targetInfo, itemIndex, reason, attempt)
		local sl = orderFlow.stages and orderFlow.stages.sell
		if not (sl and targetInfo and targetInfo.itemID and targetInfo.itemID > 0) then return end
		local nextAttempt = (tonumber(attempt) or 0) + 1
		local isPostRefresh = (reason == "post_refresh" or reason == "post_complete_refresh")
		local maxAttempts = isPostRefresh and 4 or 2
		if nextAttempt > maxAttempts then return end
		sl.scanRetrySerial = (sl.scanRetrySerial or 0) + 1
		local retrySerial = sl.scanRetrySerial
		local baseSearchSerial = sl.searchSerial or 0
		local targetItemID = targetInfo.itemID
		sl.pendingRetryScan = {
			targetInfo = targetInfo,
			itemIndex = itemIndex,
			reason = reason or "retry",
			attempt = nextAttempt,
			retrySerial = retrySerial,
			baseSearchSerial = baseSearchSerial,
			targetItemID = targetItemID,
		}
		if not (C_Timer and type(C_Timer.After) == "function") then return end
		C_Timer.After(0.45, function()
			local s = orderFlow.stages and orderFlow.stages.sell
			if not (s and s.scanRetrySerial == retrySerial and (s.searchSerial or 0) == baseSearchSerial) then return end
			s.pendingRetryScan = nil
			if not atAH() or s.pendingPost ~= nil or s.pendingSearch ~= nil then return end
			if isPostRefresh then
				local cur = (itemIndex ~= nil) and s.items and s.items[itemIndex] or nil
				local matchesCur = (cur ~= nil and cur.itemID == targetItemID)
				local matchesLast = (s.lastItemInfo ~= nil and s.lastItemInfo.itemID == targetItemID)
				if not (matchesCur or matchesLast) then return end
				dispatchSellScanInternal(targetInfo, itemIndex, reason, nextAttempt)
				return
			end
			if itemIndex ~= nil then
				local cur = s.items and s.items[s.activeIndex]
				if s.activeIndex ~= itemIndex or not cur or cur.channel ~= "ah"
					or cur.itemID ~= targetItemID
					or (cur.remaining or 0) <= 0 or cur.status == "done" or cur.status == "skipped" then
					return
				end
			else
				if (s.items and s.items[s.activeIndex]) or not (s.lastItemInfo and s.lastItemInfo.itemID == targetItemID) then
					return
				end
			end
			dispatchSellScanInternal(targetInfo, itemIndex, "retry", nextAttempt)
		end)
	end

	dispatchSellScanInternal = function(targetInfo, itemIndex, reason, attempt)
		local sl = orderFlow.stages.sell
		if not targetInfo or not targetInfo.itemID or targetInfo.itemID <= 0 then return false, "no_item" end
		if isSellLegacyAH() then return false, "legacy_ah" end
		if not atAH() then return false, "ah_closed" end
		if sl.pendingPost ~= nil then return false, "post_in_flight" end
		local curAttempt = tonumber(attempt) or 0
		if not isSellThrottledReady() then
			if reason ~= "retry" or curAttempt > 0 then
				scheduleSellScanRetry(targetInfo, itemIndex, reason, curAttempt)
			end
			return false, "throttled"
		end
		local ah = _G.C_AuctionHouse
		if not ah then return false, "api_unavailable" end

		if sl.pendingSearch then
			sl.pendingSearch = nil
			sl.pendingKeyPrime = nil
			sl.searchSerial = (sl.searchSerial or 0) + 1
		end

		if ns.AHChannel and ns.AHChannel.TryAcquire then
			local okCh = ns.AHChannel.TryAcquire("orderflow_sell", { preemptScan = true })
			if not okCh then
				if reason ~= "retry" or curAttempt > 0 then
					scheduleSellScanRetry(targetInfo, itemIndex, reason, curAttempt)
				end
				return false, "channel_busy"
			end
		end
		sl.pendingRetryScan = nil
		sl.scanRetrySerial = (sl.scanRetrySerial or 0) + 1

		local bagInfo = findSellableBagSlot(targetInfo.itemID, 1, targetInfo.itemLink)
		local isComm = (bagInfo and bagInfo.isCommodity == true)
		if not bagInfo then
			if targetInfo.isCommodity ~= nil then
				isComm = (targetInfo.isCommodity == true)
			else
				isComm = getItemMaxStackSafe(targetInfo.itemID, targetInfo.itemLink) > 1
			end
		end
		local cid = (bagInfo and bagInfo.classID) or targetInfo.classID
		local ilvl = (bagInfo and bagInfo.itemLevel) or targetInfo.itemLevel or 0
		local isEquip = (not isComm) and isSellEquipmentClass(cid)
		local queryKey, compareKey = makeSellItemKeys(targetInfo.itemID, bagInfo and bagInfo.location or nil, isComm, targetInfo.itemLink, isEquip, ilvl)
		local sig = sellItemKeySig(queryKey)

		sl.searchSerial = (sl.searchSerial or 0) + 1
		local serial = sl.searchSerial
		sl.pendingSearch = {
			itemIndex = itemIndex,
			isLastItem = (itemIndex == nil),
			itemID = targetInfo.itemID,
			itemLink = targetInfo.itemLink or (bagInfo and bagInfo.itemLink),
			itemKey = queryKey,
			compareKey = compareKey,
			sig = sig,
			isCommodity = isComm,
			isEquipment = isEquip,
			retriedEmpty = false,
			reason = reason or "select",
			serial = serial,
			startedAt = nowSellMono(),
		}

		if C_Timer and type(C_Timer.After) == "function" then
			C_Timer.After(SELL_SEARCH_WATCHDOG_SEC, function()
				local s = orderFlow.stages.sell
				if s and s.pendingSearch and s.pendingSearch.serial == serial then
					s.pendingSearch = nil
					s.pendingKeyPrime = nil
					if s.pendingPost == nil and ns.AHChannel and ns.AHChannel.Release then
						ns.AHChannel.Release("orderflow_sell")
					end
					notifyOrderFlow()
				end
			end)
		end

		local needPrime = false
		if type(ah.GetItemKeyInfo) == "function" then
			local okK, ki = pcall(ah.GetItemKeyInfo, queryKey)
			if not (okK and tableValue(ki)) then needPrime = true end
		end
		if needPrime then
			sl.pendingKeyPrime = {
				itemIndex = itemIndex,
				itemID = targetInfo.itemID,
				itemKey = queryKey,
				sig = sig,
				isCommodity = isComm,
				isEquipment = isEquip,
				serial = serial,
			}
			if C_Timer and type(C_Timer.After) == "function" then
				C_Timer.After(1.5, function()
					local s = orderFlow.stages.sell
					if s and s.pendingKeyPrime and s.pendingKeyPrime.serial == serial
						and s.pendingSearch and s.pendingSearch.serial == serial then
						local pk = s.pendingKeyPrime
						s.pendingKeyPrime = nil
						dispatchSellSearchQuery(_G.C_AuctionHouse, pk.itemKey, pk.isCommodity, pk.isEquipment)
					end
				end)
			end
		else
			sl.pendingKeyPrime = nil
			dispatchSellSearchQuery(ah, queryKey, isComm, isEquip)
		end
		notifyOrderFlow(true)
		return true
	end

	function OrderFlow.ScanSellItemMarket(index, reason)
		local sl = orderFlow.stages.sell
		local idx = index or sl.activeIndex
		local it = sl.items[idx]
		if not it or not it.itemID or it.itemID <= 0 then return false, "no_item" end
		return dispatchSellScanInternal(it, idx, reason or "select")
	end

	function OrderFlow.RefreshSellSearch(reason)
		local sl = orderFlow.stages.sell
		if not sl then return false, "no_stage" end
		local cur = sl.items[sl.activeIndex]
		if cur and cur.channel == "ah" and cur.itemID and cur.itemID > 0 then
			return dispatchSellScanInternal(cur, sl.activeIndex, reason or "refresh")
		elseif sl.lastItemInfo and sl.lastItemInfo.itemID and sl.lastItemInfo.itemID > 0 then
			return dispatchSellScanInternal(sl.lastItemInfo, nil, (reason == "retry") and "retry" or "refresh_last")
		end
		return false, "no_item"
	end

	local function handleSellSearchResults(isCommodity, itemIDOrKey)
		local sl = orderFlow.stages.sell
		local ps = sl and sl.pendingSearch
		if not ps then return false end
		if isCommodity then
			local id = safeNumber(itemIDOrKey)
			if id and ps.itemID ~= id then return false end
			ps.isCommodity = true
		else
			local key = tableValue(itemIDOrKey)
			if key then
				local kID = safeNumber(key.itemID)
				if kID and ps.itemID and kID ~= ps.itemID then return false end
				local psSuf = ps.itemKey and safeNumber(ps.itemKey.itemSuffix) or 0
				local kSuf = safeNumber(key.itemSuffix) or 0
				if psSuf ~= 0 and kSuf ~= 0 and psSuf ~= kSuf then return false end
				local psPet = ps.itemKey and safeNumber(ps.itemKey.battlePetSpeciesID) or 0
				local kPet = safeNumber(key.battlePetSpeciesID) or 0
				if psPet ~= 0 and kPet ~= 0 and psPet ~= kPet then return false end
			end
			ps.isCommodity = false
		end

		local ah = _G.C_AuctionHouse
		-- Empty-result retry guard (Auctionator SearchScan.lua:45,59)
		if ah and not ps.retriedEmpty then
			local hasSearch = nil
			if type(ah.HasSearchResults) == "function" then
				local okH, hs = pcall(ah.HasSearchResults, isCommodity and ps.itemKey or (tableValue(itemIDOrKey) or ps.itemKey))
				if okH and readable(hs) then hasSearch = (hs == true) end
			end
			local shouldRetry = false
			if hasSearch == false then
				shouldRetry = true
			elseif hasSearch == true then
				if isCommodity and type(ah.HasFullCommoditySearchResults) == "function" then
					local okF, full = pcall(ah.HasFullCommoditySearchResults, ps.itemID)
					local q = 0
					if type(ah.GetCommoditySearchResultsQuantity) == "function" then
						local okQ, qv = pcall(ah.GetCommoditySearchResultsQuantity, ps.itemID)
						q = okQ and math.floor(safeNumber(qv) or 0) or 0
					elseif type(ah.GetNumCommoditySearchResults) == "function" then
						q = math.floor(safeNumber(ah.GetNumCommoditySearchResults(ps.itemID)) or 0)
					end
					if okF and readable(full) and full == false and q == 0 then
						shouldRetry = true
					end
				elseif (not isCommodity) and type(ah.HasFullItemSearchResults) == "function" then
					local qKey = tableValue(itemIDOrKey) or ps.itemKey
					local okF, full = pcall(ah.HasFullItemSearchResults, qKey)
					local n = type(ah.GetNumItemSearchResults) == "function" and math.floor(safeNumber(ah.GetNumItemSearchResults(qKey)) or 0) or 0
					if okF and readable(full) and full == false and n == 0 then
						shouldRetry = true
					end
				end
			end
			if shouldRetry then
				ps.retriedEmpty = true
				dispatchSellSearchQuery(ah, ps.itemKey, ps.isCommodity, ps.isEquipment)
				return true
			end
		end

		local idx = ps.itemIndex
		local it = idx and sl.items[idx] or nil
		sl.pendingSearch = nil
		sl.pendingKeyPrime = nil
		if sl.pendingPost == nil and ns.AHChannel and ns.AHChannel.Release then
			ns.AHChannel.Release("orderflow_sell")
		end

		local listings = {}
		local priceThreshold = nil
		local chosenPrice = nil
		local chosenIsOwn = false
		local sellObservedQty = 0
		local sellBuyoutMin = nil
		local sellHasFull = false

		if isCommodity and ah and ah.GetNumCommoditySearchResults and ah.GetCommoditySearchResultInfo then
			if type(ah.HasFullCommoditySearchResults) == "function" then
				local okFC, fc = pcall(ah.HasFullCommoditySearchResults, ps.itemID)
				if okFC and readable(fc) and fc == true then sellHasFull = true end
			end
			local n = math.floor(safeNumber(ah.GetNumCommoditySearchResults(ps.itemID)) or 0)
			local sumQty = 0
			for i = 1, n do
				local okR, info = pcall(ah.GetCommoditySearchResultInfo, ps.itemID, i)
				if okR and tableValue(info) then
					local up = safeNumber(info.unitPrice)
					local qty = math.max(1, math.floor(safeNumber(info.quantity) or 1))
					local ownQty = math.max(0, math.floor(safeNumber(info.numOwnerItems) or 0))
					local owners = type(info.owners) == "table" and info.owners or {}
					local totalOwners = math.max(#owners, math.floor(safeNumber(info.totalNumberOfOwners) or #owners))
					local isOwnRow = (readable(info.containsOwnerItem) and info.containsOwnerItem == true) or (ownQty > 0)
					if up and up > 0 then
						local upInt = math.floor(up)
						sumQty = sumQty + qty
						listings[#listings + 1] = {
							price = upInt,
							bidPrice = nil,
							quantity = qty,
							numOwnerItems = ownQty,
							containsOwnerItem = isOwnRow,
							owners = owners,
							totalNumberOfOwners = totalOwners,
							timeLeftSeconds = safeNumber(info.timeLeftSeconds),
							auctionID = safeNumber(info.auctionID),
							isCommodity = true,
							itemID = ps.itemID,
							itemLink = ps.itemLink,
						}
					end
				end
			end
			local totalQty = sumQty
			if type(ah.GetCommoditySearchResultsQuantity) == "function" then
				local okTQ, tq = pcall(ah.GetCommoditySearchResultsQuantity, ps.itemID)
				if okTQ and safeNumber(tq) and tq > 0 then
					totalQty = math.floor(tq)
				end
			end
			sellObservedQty = totalQty
			if #listings > 0 then
				local r1 = listings[1]
				chosenPrice = r1.price
				sellBuyoutMin = r1.price
				-- Auctionator SaleItem.lua:524 self-match check
				if r1.containsOwnerItem and ((type(r1.owners) == "table" and r1.owners[1] == "player")
					or ((r1.numOwnerItems or 0) >= (r1.quantity or 1))) then
					chosenIsOwn = true
				else
					chosenIsOwn = false
				end
				-- Auctionator SaleItem.lua:477-492 GetCommodityThreshold
				local target = math.min(5000, math.floor(totalQty * 0.2))
				local accum = 0
				for _, row in ipairs(listings) do
					accum = accum + (row.quantity or 1)
					if accum >= target then
						priceThreshold = OrderFlow.ComputeCommodityPriceWarningThreshold(row.price)
						break
					end
				end
			end
		elseif (not isCommodity) and ah and ah.GetNumItemSearchResults and ah.GetItemSearchResultInfo then
			local qKey = tableValue(itemIDOrKey) or ps.itemKey
			if type(ah.HasFullItemSearchResults) == "function" then
				local okFI, fi = pcall(ah.HasFullItemSearchResults, qKey)
				if okFI and readable(fi) and fi == true then sellHasFull = true end
			end
			local n = math.floor(safeNumber(ah.GetNumItemSearchResults(qKey)) or 0)
			local firstBuyoutRow = nil
			local firstBidOnlyRow = nil
			local groupedByKey = {}
			for i = 1, n do
				local okR, info = pcall(ah.GetItemSearchResultInfo, qKey, i)
				if okR and tableValue(info) then
					if doesSellItemMatchFromKey(ps.compareKey, ps.itemLink, info.itemKey, info.itemLink) then
						local bo = safeNumber(info.buyoutAmount)
						local bid = safeNumber(info.bidAmount) or safeNumber(info.minBid)
						local qty = math.max(1, math.floor(safeNumber(info.quantity) or 1))
						local isOwn = (readable(info.containsOwnerItem) and info.containsOwnerItem == true)
						local owners = type(info.owners) == "table" and info.owners or {}
						local totalOwners = math.max(#owners, math.floor(safeNumber(info.totalNumberOfOwners) or #owners))
						local rowLvl = math.floor((tableValue(info.itemKey) and safeNumber(info.itemKey.itemLevel)) or safeNumber(info.itemLevel) or 0)
						local boInt = (bo and bo > 0) and math.floor(bo) or nil
						local bidInt = (bid and bid > 0) and math.floor(bid) or nil
						if boInt or bidInt then
							sellObservedQty = sellObservedQty + qty
							if boInt then
								local boUnit = math.max(1, math.floor(boInt / qty + 0.5))
								sellBuyoutMin = sellBuyoutMin and math.min(sellBuyoutMin, boUnit) or boUnit
							end
							local gKey = tostring(boInt or 0) .. ":" .. tostring(bidInt or 0) .. ":" .. tostring(rowLvl) .. ":" .. (isOwn and "1" or "0")
							local existingRow = groupedByKey[gKey]
							if existingRow then
								existingRow.quantity = (existingRow.quantity or 0) + qty
								if isOwn then
									existingRow.numOwnerItems = (existingRow.numOwnerItems or 0) + qty
								end
							else
								local row = {
									price = boInt,
									bidPrice = bidInt,
									quantity = qty,
									numOwnerItems = isOwn and qty or 0,
									itemLevel = rowLvl,
									containsOwnerItem = isOwn,
									owners = owners,
									totalNumberOfOwners = totalOwners,
									timeLeft = safeNumber(info.timeLeft),
									timeLeftSeconds = safeNumber(info.timeLeftSeconds),
									auctionID = safeNumber(info.auctionID),
									itemLink = (readable(info.itemLink) and type(info.itemLink) == "string") and info.itemLink or ps.itemLink,
									isCommodity = false,
									itemID = ps.itemID,
								}
								groupedByKey[gKey] = row
								listings[#listings + 1] = row
								if boInt and not firstBuyoutRow then
									firstBuyoutRow = row
								elseif (not boInt) and bidInt and not firstBidOnlyRow then
									firstBidOnlyRow = row
								end
							end
						end
					end
				end
			end
			local pick = firstBuyoutRow or firstBidOnlyRow
			if pick then
				chosenPrice = pick.price or pick.bidPrice
				chosenIsOwn = (pick.containsOwnerItem == true)
			end
		end

		if ps.itemID and ps.itemID > 0 and (isCommodity or isBaseItemKey(ps.itemKey)) then
			if sellBuyoutMin and sellBuyoutMin > 0 and sellObservedQty > 0 then
				MarketScan.RecordLiveItemPrice(ps.itemID, sellBuyoutMin, sellObservedQty, {
					itemWide = (isCommodity == true and sellHasFull == true) or isBaseItemKey(ps.itemKey),
				})
			elseif sellHasFull and sellObservedQty == 0 then
				MarketScan.RecordLiveItemPrice(ps.itemID, nil, 0, { itemWide = true })
			end
		end

		local now = nowSellMono()
		if not it and ps.isLastItem then
			local activeIt = sl.items and sl.items[sl.activeIndex]
			if activeIt and activeIt.itemID == ps.itemID then
				local aPet = extractBattlePetInfo(activeIt.itemLink)
				local pPet = ps.itemKey and safeNumber(ps.itemKey.battlePetSpeciesID) or 0
				if pPet == 0 or (aPet or 0) == 0 or pPet == aPet then
					it = activeIt
				end
			end
		end
		if it then
			it.currentListings = listings
			it.listingsScanned = true
			it.priceThreshold = priceThreshold
			it.isCommodity = (isCommodity == true)
			if chosenPrice and chosenPrice > 0 then
				it.liveUnit = chosenPrice
				it.liveIsOwn = chosenIsOwn
				it.existingValue = chosenPrice
			else
				it.liveUnit = nil
				it.liveIsOwn = false
				it.existingValue = nil
			end
			it.liveCheckedAt = now
		end
		if ps.isLastItem or (sl.lastItemInfo and sl.lastItemInfo.itemID == ps.itemID) then
			sl.lastItemListings = listings
		end
		notifyOrderFlow()
		return true
	end

	function OrderFlow.FormatAuctionPostedMessage(info)
		if type(info) ~= "table" then return "" end
		local name = tostring(info.itemLink or info.name or "Item")
		local qty = math.max(1, math.floor(safeNumber(info.quantity or info.qty) or 1))
		local buyout = math.max(0, math.floor(safeNumber(info.buyoutAmount or info.buyout) or 0))
		local bid = math.max(0, math.floor(safeNumber(info.bidAmount or info.startBid) or 0))
		if qty > 1 then
			local eff = (buyout > 0) and buyout or bid
			return string.format("Posted %sx%d for %s (at %s each)",
				name, qty, ns.FormatMoneyCompact(qty * eff), ns.FormatMoneyCompact(eff))
		end
		local parts = {}
		if bid > 0 then
			parts[#parts + 1] = "bidding at " .. ns.FormatMoneyCompact(bid)
		end
		if buyout > 0 then
			parts[#parts + 1] = "buyout at " .. ns.FormatMoneyCompact(buyout)
		end
		if #parts > 0 then
			return string.format("Posted %s %s", name, table.concat(parts, ", "))
		end
		return string.format("Posted %s", name)
	end

	function OrderFlow.CancelPendingSellPost(reason)
		local sl = orderFlow.stages.sell
		local hadPost = (sl.pendingPost ~= nil)
		local hadWarn = (sl.warningConfirm ~= nil)
		if sl.pendingPost and sl.pendingPost.multisellActive
			and C_AuctionHouse and type(C_AuctionHouse.CancelSell) == "function" then
			pcall(C_AuctionHouse.CancelSell)
		end
		sl.postSerial = (sl.postSerial or 0) + 1
		sl.pendingPost = nil
		sl.warningConfirm = nil
		sl.postAllActive = false
		if sl.pendingSearch == nil and ns.AHChannel and ns.AHChannel.Release then
			ns.AHChannel.Release("orderflow_sell")
		end
		if hadPost or hadWarn then
			orderFlow.notice = reason or "Post cancelled."
			orderFlow.noticeKind = "info"
			notifyOrderFlow()
		end
		return true
	end

	local function armSellPostWatchdog(serial, timeoutMsg)
		if C_Timer and type(C_Timer.After) == "function" then
			C_Timer.After(SELL_POST_WATCHDOG_SEC, function()
				local s = orderFlow.stages.sell
				if s and s.pendingPost and s.pendingPost.serial == serial then
					s.pendingPost = nil
					s.postAllActive = false
					if s.pendingSearch == nil and ns.AHChannel and ns.AHChannel.Release then
						ns.AHChannel.Release("orderflow_sell")
					end
					orderFlow.notice = timeoutMsg or "Auction post timed out."
					orderFlow.noticeKind = "warning"
					notifyOrderFlow()
				end
			end)
		end
	end

	-- Synchronous hardware-click posting (Auctionator SaleItem.lua parity)
	function OrderFlow.PostSellItem(index, opts)
		local sl = orderFlow.stages.sell
		opts = type(opts) == "table" and opts or {}
		local idx = index or sl.activeIndex
		local it = sl.items[idx]
		if not it then return false, "no_item" end

		local canPost, blockReason, depCost = OrderFlow.GetSellPostButtonState(idx, opts)
		if not canPost then
			if blockReason == "not_in_bags" or blockReason == "missing_location" then
				it.inBags = 0
				orderFlow.notice = "No sellable " .. tostring(it.name) .. " found in bags."
				orderFlow.noticeKind = "warning"
				notifyOrderFlow()
			elseif blockReason == "insufficient_money" then
				orderFlow.notice = "Not enough gold for AH deposit (" .. ns.FormatMoneyCompact(depCost or 0) .. ")."
				orderFlow.noticeKind = "warning"
				notifyOrderFlow()
			elseif blockReason == "bid_ge_buyout" then
				orderFlow.notice = "Bid price must be lower than Buyout price."
				orderFlow.noticeKind = "warning"
				notifyOrderFlow()
			end
			return false, blockReason, depCost
		end

		local bagInfo = findSellableBagSlot(it.itemID, 1, it.itemLink)
		if not bagInfo then return false, "not_in_bags" end
		it.inBags = bagInfo.totalAvail

		local wantQty = safeNumber(opts.qty)
		if wantQty == nil then
			wantQty = OrderFlow.GetSellPostQty(it)
		end
		local qty = math.max(1, math.min(math.floor(wantQty or 1), bagInfo.maxPostQty))

		local buyout, _, bid = OrderFlow.ComputeSellUnitPrice(it)
		if opts.unitPrice ~= nil then buyout = OrderFlow.NormalizeSellPrice(opts.unitPrice) end
		if opts.bidPrice ~= nil then bid = OrderFlow.NormalizeSellPrice(opts.bidPrice) end
		if bagInfo.isCommodity then bid = 0 end

		local dur = safeNumber(opts.duration) or sl.duration or 2
		dur = (dur == 1 or dur == 2 or dur == 3) and dur or 2

		-- Low-price & below-vendor confirmation gate (Auctionator SaleItem.lua:635-703)
		if opts.confirmed ~= true then
			local warnReason, warnMsg = OrderFlow.GetSellConfirmationWarning(it, {
				qty = qty,
				unitPrice = buyout,
				bidPrice = bid,
			})
			if warnReason then
				sl.warningConfirm = {
					itemIndex = idx,
					reason = warnReason,
					message = warnMsg,
					unitPrice = buyout,
					bidPrice = bid,
					qty = qty,
					duration = dur,
				}
				orderFlow.notice = warnMsg
				orderFlow.noticeKind = "warning"
				notifyOrderFlow()
				return false, "confirm_low_price", warnReason
			end
		end
		sl.warningConfirm = nil

		local ah = _G.C_AuctionHouse
		if not ah then return false, "api_unavailable" end
		if bagInfo.isCommodity and type(ah.PostCommodity) ~= "function" then return false, "api_unavailable" end
		if (not bagInfo.isCommodity) and type(ah.PostItem) ~= "function" then return false, "api_unavailable" end

		if sl.pendingSearch then
			sl.pendingSearch = nil
			sl.pendingKeyPrime = nil
			sl.searchSerial = (sl.searchSerial or 0) + 1
		end

		if ns.AHChannel and ns.AHChannel.TryAcquire then
			local okCh = ns.AHChannel.TryAcquire("orderflow_sell", { preemptScan = true })
			if not okCh then return false, "channel_busy" end
		end

		local startBidArg = nil
		local buyoutArg = nil
		local okCall, needsConfirm
		if bagInfo.isCommodity then
			buyoutArg = buyout
			okCall, needsConfirm = pcall(ah.PostCommodity, bagInfo.location, dur, qty, buyoutArg)
		else
			if bid > 0 then
				startBidArg = bid
				buyoutArg = (buyout > 0) and buyout or nil
			else
				startBidArg = nil
				buyoutArg = buyout
			end
			okCall, needsConfirm = pcall(ah.PostItem, bagInfo.location, dur, qty, startBidArg, buyoutArg)
		end
		if not okCall then
			if ns.AHChannel and ns.AHChannel.Release then ns.AHChannel.Release("orderflow_sell") end
			return false, "api_error"
		end

		local now = nowSellMono(opts.nowSec)
		local confirmReq = (readable(needsConfirm) and needsConfirm == true)
		local effectiveUnit = (buyoutArg and buyoutArg > 0) and buyoutArg or (startBidArg or 0)
		sl.postSerial = (sl.postSerial or 0) + 1
		local serial = sl.postSerial
		sl.activeIndex = idx
		sl.pendingPost = {
			itemIndex = idx,
			itemID = it.itemID,
			itemLink = bagInfo.itemLink or it.itemLink,
			name = it.name,
			classID = it.classID or bagInfo.classID,
			itemLevel = it.itemLevel or bagInfo.itemLevel or 0,
			quality = it.quality or bagInfo.quality or 1,
			isCommodity = bagInfo.isCommodity == true,
			kind = bagInfo.isCommodity and "commodity" or "item",
			location = bagInfo.location,
			bag = bagInfo.bag,
			slot = bagInfo.slot,
			qty = qty,
			unitPrice = effectiveUnit,
			startBid = startBidArg,
			buyout = buyoutArg,
			duration = dur,
			state = confirmReq and "awaiting_confirm" or "posting",
			multisellActive = false,
			multisellCreated = 0,
			multisellTotal = (not bagInfo.isCommodity and qty > 1) and qty or nil,
			serial = serial,
			startedAt = now,
		}

		armSellPostWatchdog(serial, "Auction post timed out.")

		orderFlow.notice = confirmReq
			and string.format("Click Confirm Post to list %dx %s @ %s.", qty, tostring(it.name), ns.FormatMoneyCompact(effectiveUnit))
			or string.format("Posting %dx %s @ %s...", qty, tostring(it.name), ns.FormatMoneyCompact(effectiveUnit))
		orderFlow.noticeKind = "info"
		notifyOrderFlow()
		return true, sl.pendingPost.state
	end

	function OrderFlow.ConfirmLowPriceSellPost()
		local sl = orderFlow.stages.sell
		local wc = sl and sl.warningConfirm
		if not wc then return false, "no_warning_confirm" end
		sl.warningConfirm = nil
		return OrderFlow.PostSellItem(wc.itemIndex, {
			qty = wc.qty,
			unitPrice = wc.unitPrice,
			bidPrice = wc.bidPrice,
			duration = wc.duration,
			confirmed = true,
		})
	end

	function OrderFlow.ConfirmPendingSellPost()
		local sl = orderFlow.stages.sell
		local p = sl.pendingPost
		if not p or p.state ~= "awaiting_confirm" then return false, "no_pending_confirm" end
		if isSellLegacyAH() then return false, "legacy_ah" end
		if not atAH() then return false, "ah_closed" end
		if not isSellThrottledReady() then return false, "throttled" end

		local ah = _G.C_AuctionHouse
		if not ah then
			OrderFlow.CancelPendingSellPost("AH API unavailable.")
			return false, "api_unavailable"
		end

		local bagInfo = findSellableBagSlot(p.itemID, p.qty, p.itemLink)
		if not bagInfo or not bagInfo.enoughForReq then
			OrderFlow.CancelPendingSellPost("Item moved or missing in bags.")
			return false, "stale_slot"
		end
		p.location = bagInfo.location
		p.bag = bagInfo.bag
		p.slot = bagInfo.slot
		p.state = "confirming"
		sl.postSerial = (sl.postSerial or 0) + 1
		local serial = sl.postSerial
		p.serial = serial
		p.startedAt = nowSellMono()
		armSellPostWatchdog(serial, "Auction post confirmation timed out.")

		local okCall
		if p.kind == "commodity" then
			if type(ah.ConfirmPostCommodity) ~= "function" then
				OrderFlow.CancelPendingSellPost("ConfirmPostCommodity unavailable.")
				return false, "api_unavailable"
			end
			okCall = pcall(ah.ConfirmPostCommodity, p.location, p.duration, p.qty, p.buyout or p.unitPrice)
		else
			if type(ah.ConfirmPostItem) ~= "function" then
				OrderFlow.CancelPendingSellPost("ConfirmPostItem unavailable.")
				return false, "api_unavailable"
			end
			okCall = pcall(ah.ConfirmPostItem, p.location, p.duration, p.qty, p.startBid, p.buyout)
		end
		if not okCall then
			OrderFlow.CancelPendingSellPost("Confirm post failed.")
			return false, "api_error"
		end
		orderFlow.notice = "Confirming post..."
		orderFlow.noticeKind = "info"
		notifyOrderFlow()
		return true, "confirming"
	end

	-- Auctionator-style Post All: 1 hardware click posts current/next AH item and auto-advances
	function OrderFlow.PostAllNext()
		local sl = orderFlow.stages.sell
		if sl.pendingPost and sl.pendingPost.state == "awaiting_confirm" then
			return OrderFlow.ConfirmPendingSellPost()
		end
		if sl.warningConfirm then
			return OrderFlow.ConfirmLowPriceSellPost()
		end
		sl.postAllActive = true
		local cur = sl.items[sl.activeIndex]
		local idx = nil
		if cur and cur.channel == "ah" and (cur.remaining or 0) > 0 and cur.status ~= "done" and cur.status ~= "skipped"
			and getSellableBagCount(cur.itemID, false, cur.itemLink) > 0 then
			idx = sl.activeIndex
		else
			local n = #(sl.items or {})
			for offset = 0, n - 1 do
				local cand = (((sl.activeIndex or 1) - 1 + offset) % n) + 1
				local it = sl.items[cand]
				if it and it.channel == "ah" and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped"
					and getSellableBagCount(it.itemID, false, it.itemLink) > 0 then
					idx = cand
					break
				end
			end
		end
		if not idx then
			sl.postAllActive = false
			orderFlow.notice = "No remaining AH items in bags to post."
			orderFlow.noticeKind = "info"
			notifyOrderFlow()
			return false, "none_ready"
		end
		return OrderFlow.PostSellItem(idx)
	end

	-- Vendor Selling (synchronous hardware click when MerchantFrame is open)
	function OrderFlow.SellToVendor(index)
		local sl = orderFlow.stages.sell
		syncLiveEnvironmentInternal()
		if not orderFlow.env.atVendor then
			orderFlow.notice = "Please open a Vendor to sell."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "vendor_closed"
		end
		local idx = index or sl.activeIndex
		local it = sl.items[idx]
		if not it then return false, "no_item" end
		if (it.remaining or 0) <= 0 or it.status == "done" then return false, "already_done" end
		local useFn = (C_Container and C_Container.UseContainerItem) or _G.UseContainerItem
		if type(useFn) ~= "function" then return false, "no_api" end

		local beforeBags = getLiveBagCount(it.itemID)
		if beforeBags <= 0 then
			orderFlow.notice = "No " .. tostring(it.name) .. " in bags to vendor."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "not_in_bags"
		end

		local soldSlots = 0
		local soldEst = 0
		local leftToSell = it.remaining or beforeBags
		local skippedOversize = false
		local minOversizeCnt = nil
		for _, bag in ipairs(getBagContainerList()) do
			if soldSlots >= 12 or leftToSell <= 0 then break end
			local slots = getContainerNumSlotsSafe(bag)
			for slot = 1, slots do
				if soldSlots >= 12 or leftToSell <= 0 then break end
				local sid, cnt, locked = getContainerSlotInfoSafe(bag, slot)
				if sid == it.itemID and not locked and cnt and cnt > 0 then
					if cnt > leftToSell then
						skippedOversize = true
						if not minOversizeCnt or cnt < minOversizeCnt then minOversizeCnt = cnt end
					else
						local ok = pcall(useFn, bag, slot)
						if ok then
							soldSlots = soldSlots + 1
							soldEst = soldEst + cnt
							leftToSell = math.max(0, leftToSell - cnt)
						end
					end
				end
			end
		end
		if soldSlots <= 0 then
			if skippedOversize then
				orderFlow.notice = string.format("Split %s stack (%dx > %d to sell) before vendoring.",
					tostring(it.name), minOversizeCnt or 0, leftToSell)
				orderFlow.noticeKind = "warning"
				notifyOrderFlow()
				return false, "split_needed"
			end
			return false, "sell_failed"
		end

		local afterBags = getLiveBagCount(it.itemID)
		local immediateDelta = math.max(0, beforeBags - afterBags)
		if immediateDelta > 0 then
			local applied = math.min(it.remaining or 0, immediateDelta)
			it.soldQty = (it.soldQty or 0) + applied
			it.remaining = math.max(0, (it.totalQty or 0) - it.soldQty)
			it.inBags = afterBags
			sl.totalEarnedCopper = (sl.totalEarnedCopper or 0) + applied * (it.vendorSell or 0)
			if it.remaining <= 0 then
				it.status = "done"
				selectNextPendingSellInternal(idx + 1, "vendor")
			end
			sl.pendingVendorSell = nil
		else
			sl.pendingVendorSell = { { itemIndex = idx, itemID = it.itemID, beforeBags = beforeBags, expectedQty = soldEst, ts = nowSellMono() } }
		end
		orderFlow.notice = skippedOversize
			and string.format("Sold %dx %s to vendor (split remaining %dx stack to finish).", math.min(soldEst, beforeBags), tostring(it.name), minOversizeCnt or 0)
			or string.format("Sold %dx %s to vendor.", math.min(soldEst, beforeBags), tostring(it.name))
		orderFlow.noticeKind = skippedOversize and "warning" or "positive"
		notifyOrderFlow()
		return true
	end

	function OrderFlow.SellAllToVendor()
		local sl = orderFlow.stages.sell
		syncLiveEnvironmentInternal()
		if not orderFlow.env.atVendor then return 0, "vendor_closed" end
		local useFn = (C_Container and C_Container.UseContainerItem) or _G.UseContainerItem
		if type(useFn) ~= "function" then return 0, "no_api" end

		local totalSlots = 0
		local itemsSold = 0
		local skippedOversizeItems = 0
		local pendingAsync = {}
		local now = nowSellMono()
		for idx, it in ipairs(sl.items or {}) do
			if totalSlots >= 12 then break end
			if it.channel == "vendor" and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
				local beforeBags = getLiveBagCount(it.itemID)
				if beforeBags > 0 then
					local itemSlots = 0
					local itemSoldEst = 0
					local itemOversize = false
					local left = it.remaining
					for _, bag in ipairs(getBagContainerList()) do
						if totalSlots >= 12 or left <= 0 then break end
						local slots = getContainerNumSlotsSafe(bag)
						for slot = 1, slots do
							if totalSlots >= 12 or left <= 0 then break end
							local sid, cnt, locked = getContainerSlotInfoSafe(bag, slot)
							if sid == it.itemID and not locked and cnt and cnt > 0 then
								if cnt > left then
									itemOversize = true
								else
									local ok = pcall(useFn, bag, slot)
									if ok then
										totalSlots = totalSlots + 1
										itemSlots = itemSlots + 1
										itemSoldEst = itemSoldEst + cnt
										left = math.max(0, left - cnt)
									end
								end
							end
						end
					end
					if itemSlots > 0 then
						itemsSold = itemsSold + 1
						local afterBags = getLiveBagCount(it.itemID)
						local delta = math.max(0, beforeBags - afterBags)
						if delta > 0 then
							local applied = math.min(it.remaining or 0, delta)
							it.soldQty = (it.soldQty or 0) + applied
							it.remaining = math.max(0, (it.totalQty or 0) - it.soldQty)
							it.inBags = afterBags
							sl.totalEarnedCopper = (sl.totalEarnedCopper or 0) + applied * (it.vendorSell or 0)
							if it.remaining <= 0 then
								it.status = "done"
							end
						else
							pendingAsync[#pendingAsync + 1] = {
								itemIndex = idx,
								itemID = it.itemID,
								beforeBags = beforeBags,
								expectedQty = itemSoldEst,
								ts = now,
							}
						end
					elseif itemOversize then
						skippedOversizeItems = skippedOversizeItems + 1
					end
				end
			end
		end
		if #pendingAsync > 0 then
			sl.pendingVendorSell = pendingAsync
		end
		if itemsSold > 0 then
			selectNextPendingSellInternal(1, "vendor")
			local suffix = (skippedOversizeItems > 0) and string.format(" (%d item(s) need stack split)", skippedOversizeItems) or ""
			orderFlow.notice = string.format("Sold %d vendor item(s) (%d stack(s))%s.", itemsSold, totalSlots, suffix)
			orderFlow.noticeKind = (skippedOversizeItems > 0) and "warning" or "positive"
			notifyOrderFlow()
		elseif skippedOversizeItems > 0 then
			orderFlow.notice = "Split oversized bag stack(s) before vendoring partial quantities."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
		end
		return itemsSold
	end

	function OrderFlow.GetSellPrimaryAction()
		local sl = orderFlow.stages.sell
		local inAH = atAH() and true or false
		local ready = isSellThrottledReady()
		local p = sl.pendingPost
		if p then
			if p.state == "awaiting_confirm" then
				return {
					label = "Confirm Post",
					enabled = inAH and ready,
					wideConfirm = true,
					state = "awaiting_confirm",
					action = "confirm",
				}
			end
			return { label = "Posting...", enabled = false, wideConfirm = true, state = "posting", action = "none" }
		end
		if sl.warningConfirm then
			local canPost = OrderFlow.GetSellPostButtonState(sl.warningConfirm.itemIndex)
			return {
				label = "Confirm Low Price",
				enabled = canPost,
				wideConfirm = true,
				state = "confirm_warning",
				action = "confirm_warning",
			}
		end
		local cur = sl.items[sl.activeIndex]
		if not cur or cur.status == "done" or cur.status == "skipped" or (cur.remaining or 0) <= 0 then
			local hasOtherPending = OrderFlow.HasOtherPendingSellItem(sl.activeIndex)
			if hasOtherPending then
				local lbl = (cur and cur.status == "skipped") and "Skipped" or "Item Posted"
				return { label = lbl, enabled = false, wideConfirm = false, state = "item_done", action = "none" }
			end
			return { label = "All Posted!", enabled = false, wideConfirm = false, state = "done", action = "none" }
		end
		if cur.channel == "vendor" then
			local canVend = orderFlow.env.atVendor and getSellableBagCount(cur.itemID, true, cur.itemLink) > 0
			return {
				label = "Sell Vendor",
				enabled = canVend,
				wideConfirm = false,
				state = "vendor",
				action = "sell_vendor",
			}
		end
		local canPost, blockReason = OrderFlow.GetSellPostButtonState(sl.activeIndex)
		return {
			label = "Post",
			enabled = canPost,
			wideConfirm = false,
			state = "ah",
			action = "post_ah",
			reason = blockReason,
		}
	end

	local SELL_AH_UI_ERROR_GLOBALS = {
		"ERR_ITEM_NOT_FOUND",
		"ERR_AUCTION_DATABASE_ERROR",
		"ERR_AUCTION_REPAIR_ITEM",
		"ERR_AUCTION_LIMITED_DURATION_ITEM",
		"ERR_AUCTION_USED_CHARGES",
		"ERR_AUCTION_WRAPPED_ITEM",
		"ERR_AUCTION_BAG",
		"ERR_NOT_ENOUGH_MONEY",
		"ERR_AUCTION_HIGHER_BID",
		"ERR_AUCTION_MIN_BID",
		"ERR_AUCTION_HOUSE_UNAVAILABLE",
		"ERR_AUCTION_HOUSE_BUSY",
		"ERR_AUCTION_REMOVED",
	}

	local function isSellAHUIError(msg)
		if type(msg) ~= "string" or msg == "" then return false end
		for _, gName in ipairs(SELL_AH_UI_ERROR_GLOBALS) do
			local val = _G[gName]
			if readable(val) and type(val) == "string" and val ~= "" and msg == val then
				return true
			end
		end
		local lower = msg:lower()
		return lower:find("auction", 1, true) ~= nil
			or lower:find("not enough money", 1, true) ~= nil
			or lower:find("item not found", 1, true) ~= nil
			or lower:find("repair", 1, true) ~= nil
			or lower:find("deposit", 1, true) ~= nil
			or lower:find("cannot sell", 1, true) ~= nil
	end

	local function completePendingSellPost(auctionID)
		local sl = orderFlow.stages.sell
		local p = sl and sl.pendingPost
		if not p then return false end
		sl.pendingPost = nil
		sl.warningConfirm = nil
		if sl.pendingSearch == nil and ns.AHChannel and ns.AHChannel.Release then
			ns.AHChannel.Release("orderflow_sell")
		end

		sl.lastItemInfo = {
			itemID = p.itemID,
			itemLink = p.itemLink,
			name = p.name,
			classID = p.classID,
			itemLevel = p.itemLevel,
			quality = p.quality,
			isCommodity = p.isCommodity,
		}

		local it = sl.items[p.itemIndex]
		local postedQty = math.max(1, math.floor(p.qty or 1))
		local stayOnItem = false
		if it then
			it.soldQty = math.min(it.totalQty or ((it.soldQty or 0) + postedQty), (it.soldQty or 0) + postedQty)
			it.remaining = math.max(0, (it.totalQty or 0) - it.soldQty)
			it.inBags = it.itemID and getSellableBagCount(it.itemID, it.channel == "vendor", it.itemLink) or 0
			it.customPrice = nil
			it.bidPrice = 0
			sl.totalEarnedCopper = (sl.totalEarnedCopper or 0) + (postedQty * (p.unitPrice or 0))
			if it.remaining <= 0 then
				it.status = "done"
				it.postQty = 0
				it.customQty = false
			else
				local newLimit = OrderFlow.GetSellPostLimit(it)
				if newLimit > 0 then
					it.postQty = math.min(math.max(1, it.postQty or 1), it.remaining, newLimit)
					stayOnItem = true
				else
					it.postQty = 0
					it.customQty = false
				end
			end
		end

		if stayOnItem and p.itemIndex and atAH() then
			sl.activeIndex = p.itemIndex
			OrderFlow.ScanSellItemMarket(p.itemIndex, "post_refresh")
		elseif sl.postAllActive then
			local nextIdx = selectNextPendingSellInternal((p.itemIndex or 1) + 1, "ah")
			if nextIdx and atAH() then
				if sl.items[nextIdx] then sl.items[nextIdx].bidPrice = 0 end
				OrderFlow.ScanSellItemMarket(nextIdx, "select")
			else
				sl.postAllActive = false
				if atAH() and sl.lastItemInfo then
					local refreshIdx = (p.itemIndex and sl.items[p.itemIndex]) and p.itemIndex or nil
					dispatchSellScanInternal(sl.lastItemInfo, refreshIdx, "post_complete_refresh")
				end
			end
		else
			sl.postAllActive = false
			if p.itemIndex and sl.items[p.itemIndex] then
				sl.activeIndex = p.itemIndex
			end
			if atAH() and sl.lastItemInfo then
				local refreshIdx = (p.itemIndex and sl.items[p.itemIndex]) and p.itemIndex or nil
				dispatchSellScanInternal(sl.lastItemInfo, refreshIdx, "post_complete_refresh")
			end
		end

		if ns.AHSellTab and type(ns.AHSellTab.MarkBagsDirty) == "function" then
			ns.AHSellTab.MarkBagsDirty()
		end
		orderFlow.notice = OrderFlow.FormatAuctionPostedMessage({
			name = p.name,
			itemLink = p.name,
			quantity = postedQty,
			buyoutAmount = p.buyout or 0,
			bidAmount = p.startBid or 0,
		})
		orderFlow.noticeKind = "positive"
		notifyOrderFlow()
		return true
	end

	local function handleSellAuctionCreated(auctionID)
		local sl = orderFlow.stages.sell
		local p = sl and sl.pendingPost
		if not p or (p.state ~= "posting" and p.state ~= "confirming") then return false end
		if p.kind == "item" and (p.qty or 1) > 1 then
			-- Wait for AUCTION_MULTISELL_UPDATE(created == total) on multi-auction PostItem
			return false
		end
		return completePendingSellPost(auctionID)
	end

	-----------------------------------------------------------------------------------------------
	-- Backward-Compatible Stage 1 CartBuyer Facade + Direct One-Click Buying (WS4)
	-----------------------------------------------------------------------------------------------
	local DIRECT_QUOTE_TIMEOUT = 30
	local DIRECT_BUY_TIMEOUT = 15

	local function isLegacyAuctionClient()
		return (_G.IsUsingLegacyAuctionClient and _G.IsUsingLegacyAuctionClient()) == true
	end

	local function getPlayerCopper()
		if type(GetMoney) ~= "function" then return nil end
		local ok, m = pcall(GetMoney)
		return ok and safeNumber(m) or nil
	end

	local function armDirectBuyWatchdog(serial, expectedState, timeoutSec, msg, cancelServer)
		if C_Timer and type(C_Timer.After) == "function" then
			C_Timer.After(timeoutSec, function()
				local d = orderFlow.stages.ah and orderFlow.stages.ah.directBuy
				if d and d.serial == serial and d.state == expectedState then
					CartBuyer.CancelDirectBuy(msg, cancelServer)
				end
			end)
		end
	end

	function CartBuyer.GetState()
		syncCartBuyerMirror()
		return cartBuyer
	end

	function CartBuyer.SetOnUpdate(fn)
		cartBuyer.onUpdate = fn
	end

	function CartBuyer.GetOverviewStats()
		local st = OrderFlow.GetStageStats("ah")
		return {
			totalItems = st.total,
			boughtItems = st.done,
			remainingItems = st.remaining,
			totalUnits = st.totalUnits,
			boughtUnits = st.doneUnits,
			remainingUnits = st.remainingUnits,
			totalEstCopper = st.totalEstCopper,
			spentCopper = st.spentCopper,
			remainingEstCopper = st.remainingEstCopper,
		}
	end

	function CartBuyer.IsPurchaseInFlight()
		local ah = orderFlow.stages.ah
		return ah.directBuy ~= nil or ah.pendingExternal ~= nil or ah.pendingExternalBid ~= nil
	end

	function CartBuyer.GetDirectBuyState()
		return orderFlow.stages.ah.directBuy
	end

	function CartBuyer.CancelDirectBuy(reason, cancelServerOrOpts)
		local ah = orderFlow.stages.ah
		local d = ah.directBuy
		local silent = false
		local cancelServer = true
		if type(cancelServerOrOpts) == "table" then
			silent = (cancelServerOrOpts.silent == true)
			if cancelServerOrOpts.cancelServer ~= nil then
				cancelServer = (cancelServerOrOpts.cancelServer == true)
			end
		elseif cancelServerOrOpts ~= nil then
			cancelServer = (cancelServerOrOpts == true)
		end

		if d and d.kind == "commodity"
			and (d.state == "quoting" or d.state == "awaiting_confirm" or d.state == "confirming") then
			if cancelServer and C_AuctionHouse and type(C_AuctionHouse.CancelCommoditiesPurchase) == "function" then
				pcall(C_AuctionHouse.CancelCommoditiesPurchase)
			end
		end

		ah.directBuy = nil
		if ah.pendingExternal and ah.pendingExternal.fromDirectBuy then
			ah.pendingExternal = nil
		end
		ah.pendingExternalBid = nil
		ah.externalBidSerial = (ah.externalBidSerial or 0) + 1
		ah.selfBidInFlight = false
		ah.directBuySerial = (ah.directBuySerial or 0) + 1

		if ns.AHChannel and ns.AHChannel.Release then
			ns.AHChannel.Release("cart_buyer")
		end

		if not silent then
			if type(reason) == "string" and reason ~= "" then
				orderFlow.notice = reason
				orderFlow.noticeKind = "warning"
			end
			notifyOrderFlow()
		else
			syncCartBuyerMirror()
		end
		return d ~= nil
	end

	function CartBuyer.LoadTerms(terms, title)
		if orderFlow.stages.ah.directBuy then
			CartBuyer.CancelDirectBuy(nil, { silent = true, cancelServer = true })
		end
		return OrderFlow.LoadAHTerms(terms, title)
	end

	function CartBuyer.GetAllDestinations()
		return OrderFlow.GetAllDestinations()
	end

	function CartBuyer.GetDestinationFilter()
		return OrderFlow.GetDestinationFilter()
	end

	function CartBuyer.GetVisibleItems()
		return OrderFlow.GetVisibleStageEntries("ah")
	end

	function CartBuyer.SetDestinationFilter(destKeyOrNil)
		return OrderFlow.SetDestinationFilter(destKeyOrNil)
	end

	function CartBuyer.OnAuctionHouseShow()
		return OrderFlow.OnAuctionHouseShow()
	end

	function CartBuyer.OpenInAH(index)
		local ah = orderFlow.stages.ah
		if ah.directBuy then
			CartBuyer.CancelDirectBuy(nil, { silent = true, cancelServer = true })
		end
		if ns.AHChannel and ns.AHChannel.IsBusy and ns.AHChannel.IsBusy("cart_buyer") then
			orderFlow.notice = "Auction House channel is busy (" .. tostring(ns.AHChannel.GetOwner() or "busy") .. "). Try again shortly."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "ah_busy"
		end
		local idx = index or ah.activeIndex
		local item = ah.items[idx]
		if not item then return false end
		ah.activeIndex = idx
		orderFlow.active = true
		if item.remaining <= 0 or item.status == "done" then
			notifyOrderFlow()
			return false
		end
		if not atAH() then
			orderFlow.env.atAH = false
			ah.waitingForAH = true
			orderFlow.notice = "Please open Auction House to start."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false
		end
		orderFlow.env.atAH = true
		ah.waitingForAH = false
		for i, it in ipairs(ah.items) do
			if it.status == "active" and i ~= idx then
				it.status = (it.remaining > 0) and "pending" or "done"
			end
		end
		item.status = "active"
		orderFlow.notice = string.format("Loaded %s (Qty %d) in Blizzard AH - click Buy in the AH window.", tostring(item.name), item.remaining)
		orderFlow.noticeKind = "info"
		app.searchAH(item.name, item.remaining, item.itemID)
		notifyOrderFlow()
		return true
	end

	function CartBuyer.SelectItem(index)
		local ah = orderFlow.stages.ah
		if not index or index < 1 or index > #ah.items then return end
		if ah.directBuy then
			CartBuyer.CancelDirectBuy(nil, { silent = true, cancelServer = true })
		end
		ah.activeIndex = index
		local item = ah.items[index]
		if item and item.remaining > 0 and atAH() then
			CartBuyer.OpenInAH(index)
		else
			notifyOrderFlow()
		end
	end

	function CartBuyer.SelectNextPending()
		local ah = orderFlow.stages.ah
		if ah.directBuy then
			CartBuyer.CancelDirectBuy(nil, { silent = true, cancelServer = true })
		end
		local nextIdx = selectNextPendingAH((ah.activeIndex or 1) + 1)
		if nextIdx then
			if atAH() then
				CartBuyer.OpenInAH(nextIdx)
			else
				notifyOrderFlow()
			end
			return nextIdx
		end
		orderFlow.notice = "All items in the shopping cart are bought!"
		orderFlow.noticeKind = "positive"
		notifyOrderFlow()
		return nil
	end

	function CartBuyer.MarkBought(index)
		local ah = orderFlow.stages.ah
		if ah.directBuy then
			CartBuyer.CancelDirectBuy(nil, { silent = true, cancelServer = true })
		end
		ah.pendingExternalBid = nil
		ah.externalBidSerial = (ah.externalBidSerial or 0) + 1
		local idx = index or ah.activeIndex
		local item = ah.items[idx]
		if not item then return false end
		local remBefore = math.max(0, tonumber(item.remaining) or ((item.needed or 0) - (item.bought or 0)))
		local paidUnit = (item.liveUnit and item.liveUnit > 0) and item.liveUnit or (item.targetUnit or item.unitPrice or 0)
		ah.spentCopper = (tonumber(ah.spentCopper) or 0) + (paidUnit * remBefore)
		item.bought = item.needed
		item.remaining = 0
		item.totalPrice = 0
		item.status = "done"
		local nextIdx = selectNextPendingAH(idx + 1)
		if nextIdx then
			if atAH() then
				CartBuyer.OpenInAH(nextIdx)
			else
				notifyOrderFlow()
			end
		else
			orderFlow.notice = "All items in the shopping cart are bought!"
			orderFlow.noticeKind = "positive"
			notifyOrderFlow()
		end
		return true
	end

	function CartBuyer.GetRemainingTerms()
		local out = {}
		for _, it in ipairs(orderFlow.stages.ah.items or {}) do
			if it.remaining and it.remaining > 0 then
				out[#out + 1] = { searchString = it.name, isExact = true, quantity = it.remaining, itemID = it.itemID }
			end
		end
		return out
	end

	-- Synchronous hardware-click direct buy (Click 1 for commodity, 1-click for item buyout)
	function CartBuyer.StartDirectBuy(index)
		local ah = orderFlow.stages.ah
		local idx = index or ah.activeIndex
		local item = ah.items[idx]
		if not item then return false, "no_item" end
		if not atAH() then
			orderFlow.notice = "Please open Auction House to start."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "ah_closed"
		end
		if isLegacyAuctionClient() then
			orderFlow.notice = "Direct AH buying is not supported on the legacy Auction House client."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "legacy_ah"
		end
		if (item.remaining or 0) <= 0 or item.status == "done" then
			return false, "already_done"
		end
		if ah.directBuy ~= nil then
			return false, "purchase_in_flight"
		end
		if item.overBuyCap == true then
			orderFlow.notice = "Live AH price exceeds Max Buy cap - use Open in AH to inspect."
			orderFlow.noticeKind = "danger"
			notifyOrderFlow()
			return false, "over_buy_cap"
		end
		if not C_AuctionHouse then
			return false, "api_unavailable"
		end
		if type(C_AuctionHouse.IsThrottledMessageSystemReady) == "function"
			and not C_AuctionHouse.IsThrottledMessageSystemReady() then
			orderFlow.notice = "Auction House busy - click Buy again in a moment."
			orderFlow.noticeKind = "warning"
			notifyOrderFlow()
			return false, "throttled"
		end

		local money = getPlayerCopper()

		if item.liveKind == "commodity" then
			if type(C_AuctionHouse.StartCommoditiesPurchase) ~= "function" then
				return false, "api_unavailable"
			end
			local itemID = safeNumber(item.itemID)
			if not itemID or itemID <= 0 then
				return false, "invalid_item"
			end
			local remQty = math.max(1, math.floor(safeNumber(item.remaining) or 1))
			local availQty = safeNumber(item.liveAvailQty)
			local buyQty = (availQty and availQty > 0) and math.min(remQty, math.floor(availQty)) or remQty
			local expectedTotal = nil
			if availQty and availQty > 0 and safeNumber(item.liveTotal) and item.liveTotal > 0 and buyQty == math.floor(availQty) then
				expectedTotal = math.floor(item.liveTotal)
			elseif safeNumber(item.liveUnit) and item.liveUnit > 0 then
				expectedTotal = math.floor(item.liveUnit * buyQty)
			end
			if not expectedTotal or expectedTotal <= 0 then
				return false, "no_live_price"
			end
			local maxCap = (safeNumber(item.maxBuyUnit) and item.maxBuyUnit > 0) and item.maxBuyUnit or nil
			if maxCap and safeNumber(item.liveUnit) and item.liveUnit > maxCap then
				orderFlow.notice = "Live AH price exceeds Max Buy cap - purchase blocked."
				orderFlow.noticeKind = "danger"
				notifyOrderFlow()
				return false, "over_buy_cap"
			end
			if money ~= nil and expectedTotal > money then
				orderFlow.notice = "Not enough gold for this purchase."
				orderFlow.noticeKind = "danger"
				notifyOrderFlow()
				return false, "insufficient_gold"
			end

			local tolMax = math.floor(expectedTotal * 1.05)
			local capOrTolMax = maxCap and math.min(tolMax, math.floor(maxCap * buyQty)) or tolMax

			if ns.AHChannel and ns.AHChannel.TryAcquire then
				local okLease, errLease = ns.AHChannel.TryAcquire("cart_buyer", { kind = "commodity", preemptScan = true })
				if not okLease then
					orderFlow.notice = "Auction House channel busy (" .. tostring(errLease or "busy") .. ")."
					orderFlow.noticeKind = "warning"
					notifyOrderFlow()
					return false, errLease or "channel_busy"
				end
			end

			ah.directBuySerial = (ah.directBuySerial or 0) + 1
			local serial = ah.directBuySerial
			local d = {
				kind = "commodity",
				state = "quoting",
				index = idx,
				itemID = itemID,
				name = item.name,
				qty = buyQty,
				expectedTotal = expectedTotal,
				maxTotal = capOrTolMax,
				maxBuyUnit = maxCap,
				serial = serial,
				startedAt = (GetTime and GetTime()) or 0,
			}
			ah.directBuy = d
			ah.activeIndex = idx
			orderFlow.active = true
			orderFlow.notice = string.format("Quoting %dx %s...", buyQty, tostring(item.name))
			orderFlow.noticeKind = "info"
			notifyOrderFlow()

			-- Strictly 2 arguments: StartCommoditiesPurchase(itemID, buyQty)
			local ok, accepted = pcall(C_AuctionHouse.StartCommoditiesPurchase, itemID, buyQty)
			if ah.directBuy ~= d then
				return false, "aborted_during_call"
			end
			if not ok or accepted == false then
				CartBuyer.CancelDirectBuy("Could not start commodity purchase.", false)
				return false, "start_failed"
			end
			armDirectBuyWatchdog(serial, "quoting", DIRECT_QUOTE_TIMEOUT, "Commodity quote timed out (30s) - retry.", true)
			return true
		elseif item.liveKind == "item" then
			if type(C_AuctionHouse.PlaceBid) ~= "function" then
				return false, "api_unavailable"
			end
			local auctionID = safeNumber(item.liveAuctionID)
			local buyout = safeNumber(item.liveBuyout)
			local auctionQty = math.max(1, math.floor(safeNumber(item.liveAuctionQty) or 1))
			if not auctionID or auctionID <= 0 or not buyout or buyout <= 0 then
				return false, "no_live_auction"
			end
			buyout = math.floor(buyout)
			local unitBuyout = buyout / auctionQty
			local maxCap = (safeNumber(item.maxBuyUnit) and item.maxBuyUnit > 0) and item.maxBuyUnit or nil
			if maxCap and unitBuyout > maxCap then
				orderFlow.notice = "Live AH unit buyout exceeds Max Buy cap - purchase blocked."
				orderFlow.noticeKind = "danger"
				notifyOrderFlow()
				return false, "over_buy_cap"
			end
			if money ~= nil and buyout > money then
				orderFlow.notice = "Not enough gold for this auction."
				orderFlow.noticeKind = "danger"
				notifyOrderFlow()
				return false, "insufficient_gold"
			end

			if ns.AHChannel and ns.AHChannel.TryAcquire then
				local okLease, errLease = ns.AHChannel.TryAcquire("cart_buyer", { kind = "item", preemptScan = true })
				if not okLease then
					orderFlow.notice = "Auction House channel busy (" .. tostring(errLease or "busy") .. ")."
					orderFlow.noticeKind = "warning"
					notifyOrderFlow()
					return false, errLease or "channel_busy"
				end
			end

			ah.directBuySerial = (ah.directBuySerial or 0) + 1
			local serial = ah.directBuySerial
			local d = {
				kind = "item",
				state = "buying",
				index = idx,
				itemID = item.itemID,
				name = item.name,
				auctionID = auctionID,
				buyoutAmount = buyout,
				qty = auctionQty,
				serial = serial,
				startedAt = (GetTime and GetTime()) or 0,
			}
			ah.directBuy = d
			ah.activeIndex = idx
			orderFlow.active = true
			orderFlow.notice = string.format("Buying %dx %s for %s...", auctionQty, tostring(item.name), ns.FormatMoneyCompact(buyout))
			orderFlow.noticeKind = "info"
			notifyOrderFlow()

			ah.selfBidInFlight = true
			local ok, accepted = pcall(C_AuctionHouse.PlaceBid, auctionID, buyout)
			ah.selfBidInFlight = false
			if ah.directBuy ~= d then
				return false, "aborted_during_call"
			end
			if not ok or accepted == false then
				CartBuyer.CancelDirectBuy("Buyout failed - listing may have moved.", false)
				return false, "bid_failed"
			end
			armDirectBuyWatchdog(serial, "buying", DIRECT_BUY_TIMEOUT, "Item buyout timed out (15s) - listing may have been sniped.", false)
			return true
		end

		return false, "needs_live_search"
	end

	-- Synchronous hardware-click Click 2 for Commodity Buy
	function CartBuyer.ConfirmDirectBuy(index)
		local ah = orderFlow.stages.ah
		local d = ah.directBuy
		if not d or d.kind ~= "commodity" or d.state ~= "awaiting_confirm" then
			return false, "not_awaiting_confirm"
		end
		if index ~= nil and index ~= d.index then
			return false, "index_mismatch"
		end
		if not atAH() then
			CartBuyer.CancelDirectBuy("Auction House closed before confirm.", false)
			return false, "ah_closed"
		end
		if isLegacyAuctionClient() then
			CartBuyer.CancelDirectBuy("Legacy AH client unsupported.", false)
			return false, "legacy_ah"
		end
		if not (C_AuctionHouse and type(C_AuctionHouse.ConfirmCommoditiesPurchase) == "function") then
			CartBuyer.CancelDirectBuy("ConfirmCommoditiesPurchase unavailable.", true)
			return false, "api_unavailable"
		end
		if type(C_AuctionHouse.GetQuoteDurationRemaining) == "function" then
			local okQ, rem = pcall(C_AuctionHouse.GetQuoteDurationRemaining)
			local remNum = okQ and safeNumber(rem) or nil
			if remNum ~= nil and remNum <= 0 then
				CartBuyer.CancelDirectBuy("Commodity quote expired - click Buy again.", true)
				return false, "quote_expired"
			end
		end

		local money = getPlayerCopper()
		if money ~= nil and d.verifiedTotal and d.verifiedTotal > money then
			CartBuyer.CancelDirectBuy("Not enough gold for Blizzard's quote.", true)
			return false, "insufficient_gold"
		end

		ah.directBuySerial = (ah.directBuySerial or 0) + 1
		local serial = ah.directBuySerial
		d.serial = serial
		d.state = "confirming"
		ah.pendingExternal = {
			itemID = d.itemID,
			quantity = d.qty,
			verifiedTotal = d.verifiedTotal,
			fromDirectBuy = true,
		}
		orderFlow.notice = string.format("Confirming %dx %s...", d.qty, tostring(d.name))
		orderFlow.noticeKind = "info"
		notifyOrderFlow()

		local ok, accepted = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, d.itemID, d.qty)
		if ah.directBuy ~= d then
			return false, "aborted_during_call"
		end
		if not ok or accepted == false then
			CartBuyer.CancelDirectBuy("Commodity purchase confirmation failed.", true)
			return false, "confirm_failed"
		end
		armDirectBuyWatchdog(serial, "confirming", DIRECT_QUOTE_TIMEOUT, "Commodity purchase timed out (30s).", false)
		return true
	end

	function CartBuyer.GetPrimaryAction()
		local ah = orderFlow.stages.ah
		local inAH = atAH() and true or false
		local d = ah.directBuy
		if d then
			if d.state == "quoting" then
				return { label = "Quoting...", enabled = false, wideConfirm = false, state = "quoting", action = "none" }
			elseif d.state == "awaiting_confirm" then
				local amt = d.verifiedTotal or d.expectedTotal or 0
				return {
					label = "Confirm " .. ns.FormatMoneyCompact(amt),
					enabled = inAH,
					wideConfirm = true,
					state = "awaiting_confirm",
					action = "confirm",
				}
			elseif d.state == "confirming" then
				return { label = "Buying...", enabled = false, wideConfirm = true, state = "confirming", action = "none" }
			elseif d.state == "buying" then
				return { label = "Buying...", enabled = false, wideConfirm = false, state = "buying", action = "none" }
			end
		end

		local cur = ah.items[ah.activeIndex]
		if not cur then
			return { label = "Open in AH", enabled = false, wideConfirm = false, state = "idle", action = "none" }
		end
		if cur.status == "done" or (cur.remaining or 0) <= 0 then
			local stats = OrderFlow.GetStageStats("ah")
			return {
				label = (stats and stats.complete) and "All Bought!" or "Open in AH",
				enabled = false,
				wideConfirm = false,
				state = "idle",
				action = "none",
			}
		end
		if not inAH then
			return { label = "Open in AH", enabled = false, wideConfirm = false, state = "idle", action = "none" }
		end
		if isLegacyAuctionClient() or cur.overBuyCap == true then
			return { label = "Open in AH", enabled = true, wideConfirm = false, state = "idle", action = "open_in_ah" }
		end
		if cur.liveKind == "commodity" and (safeNumber(cur.liveUnit) or 0) > 0 then
			local remQty = math.max(1, math.floor(safeNumber(cur.remaining) or 1))
			local availQty = safeNumber(cur.liveAvailQty)
			local buyQty = (availQty and availQty > 0) and math.min(remQty, math.floor(availQty)) or remQty
			return {
				label = string.format("Buy %dx", buyQty),
				enabled = true,
				wideConfirm = false,
				state = "idle",
				action = "start_buy",
			}
		elseif cur.liveKind == "item" and safeNumber(cur.liveAuctionID) and (safeNumber(cur.liveBuyout) or 0) > 0 then
			local aQty = math.max(1, math.floor(safeNumber(cur.liveAuctionQty) or 1))
			local overStack = aQty > (safeNumber(cur.remaining) or 1)
			return {
				label = overStack and string.format("Buy %dx (!)", aQty) or string.format("Buy %dx", aQty),
				enabled = true,
				wideConfirm = false,
				state = "idle",
				action = "start_buy",
				overbuyStackWarning = overStack,
			}
		end
		return { label = "Open in AH", enabled = true, wideConfirm = false, state = "idle", action = "open_in_ah" }
	end

	function CartBuyer.ExecutePrimaryAction()
		local pa = CartBuyer.GetPrimaryAction()
		if not pa or not pa.enabled then
			return false, "disabled"
		end
		if pa.action == "confirm" then
			return CartBuyer.ConfirmDirectBuy()
		elseif pa.action == "start_buy" then
			return CartBuyer.StartDirectBuy()
		elseif pa.action == "open_in_ah" then
			return CartBuyer.OpenInAH()
		end
		return false, "none"
	end

	function CartBuyer.GetCancelAction()
		local ah = orderFlow.stages.ah
		if ah.directBuy ~= nil then
			return { label = "Cancel Buy", enabled = true, active = true, action = "cancel_buy" }
		end
		local cur = ah.items[ah.activeIndex]
		local canMark = cur ~= nil and cur.status ~= "done" and (cur.remaining or 0) > 0
		return { label = "Mark Bought", enabled = canMark, active = false, action = "mark_bought" }
	end

	function CartBuyer.OnCommodityPurchaseConfirmed(itemID, quantity)
		if ns.AHChannel and ns.AHChannel.GetOwner and ns.AHChannel.GetOwner() == "sniper" then
			return
		end
		local ah = orderFlow.stages.ah
		if ah.directBuy and ah.directBuy.kind == "commodity" and ah.directBuy.state == "confirming" then
			return
		end
		if not orderFlow.active or #ah.items == 0 then return end
		local id = safeNumber(itemID)
		local qty = safeNumber(quantity)
		if id and id > 0 and qty and qty > 0 then
			ah.pendingExternal = { itemID = id, quantity = qty }
			syncCartBuyerMirror()
		end
	end

	function CartBuyer.OnItemBidPlaced(auctionID, bidAmount)
		local ah = orderFlow.stages.ah
		-- Ignore self-initiated CartBuyer PlaceBid and SniperEngine bids
		if ah.selfBidInFlight then return end
		local aid = safeNumber(auctionID)
		if ah.directBuy and ah.directBuy.kind == "item" and aid and ah.directBuy.auctionID == aid then
			return
		end
		if ns.AHChannel and ns.AHChannel.GetOwner and ns.AHChannel.GetOwner() == "sniper" then
			return
		end
		if not orderFlow.active or #ah.items == 0 then return end
		local amt = safeNumber(bidAmount)
		if not aid or aid <= 0 or not amt or amt <= 0 then return end
		local matchedIdx = nil
		local cur = ah.items[ah.activeIndex]
		if cur and cur.remaining > 0 and cur.liveAuctionID == aid then
			matchedIdx = ah.activeIndex
		else
			for i, it in ipairs(ah.items) do
				if it.remaining > 0 and it.liveAuctionID == aid then
					matchedIdx = i
					break
				end
			end
		end
		if not matchedIdx then return end
		local item = ah.items[matchedIdx]
		local verifiedBuyout = safeNumber(item.liveBuyout)
		if not verifiedBuyout or verifiedBuyout <= 0 or math.floor(amt) ~= math.floor(verifiedBuyout) then
			return
		end
		local qty = safeNumber(item.liveAuctionQty) or 1
		ah.externalBidSerial = (ah.externalBidSerial or 0) + 1
		local extSerial = ah.externalBidSerial
		local entry = {
			auctionID = aid,
			buyoutAmount = math.floor(amt),
			itemID = item.itemID,
			index = matchedIdx,
			qty = math.max(1, math.floor(qty)),
			serial = extSerial,
		}
		ah.pendingExternalBid = entry
		syncCartBuyerMirror()
		if C_Timer and type(C_Timer.After) == "function" then
			C_Timer.After(DIRECT_BUY_TIMEOUT, function()
				local curAh = orderFlow.stages.ah
				if curAh == ah and curAh.pendingExternalBid == entry and curAh.externalBidSerial == extSerial then
					curAh.pendingExternalBid = nil
					syncCartBuyerMirror()
				end
			end)
		end
	end

	function CartBuyer.OnWindowHide()
		OrderFlow.OnWindowHide()
	end

	local function clearItemLiveAH(cur)
		if not cur then return end
		cur.liveKind = nil
		cur.liveUnit = nil
		cur.liveUnitExact = nil
		cur.liveAvailQty = nil
		cur.liveTotal = nil
		cur.liveAuctionID = nil
		cur.liveBuyout = nil
		cur.liveAuctionQty = nil
		cur.overbuyStackWarning = nil
		cur.overBuyCap = nil
		cur.buyCapMarginCopper = nil
		cur.priceAlert = nil
		cur.priceDiffCopper = nil
		cur.priceDiffPct = nil
		cur.priceDiffTotalCopper = nil
		cur.priceDeltaPct = nil
	end

	local function recordPurchasedToCollectMail(item, qtyBought)
		local col = orderFlow.stages and orderFlow.stages.collect
		local qty = math.max(0, math.floor((tonumber(qtyBought) or 0) + 0.5))
		if not (col and type(col.items) == "table" and item and qty > 0) then return false end
		local itemID = item.itemID
		local itemName = item.name or (itemID and itemSearchName(itemID)) or nil
		if itemID and itemID > 0 and col.baselineBagQty and col.baselineBagQty[itemID] == nil then
			col.baselineBagQty[itemID] = getLiveBagCount(itemID)
		end
		local mailEntry = nil
		local maxOrder = 0
		for _, it in ipairs(col.items) do
			if (it._order or 0) > maxOrder then maxOrder = it._order end
			if it.source == "mail" and ((itemID and it.itemID == itemID) or (itemName and it.name == itemName)) then
				mailEntry = it
			end
		end
		if mailEntry then
			mailEntry.needed = (mailEntry.needed or 0) + qty
			mailEntry.remaining = (mailEntry.remaining or 0) + qty
			if mailEntry.status == "done" or mailEntry.status == "skipped" then
				mailEntry.status = ((mailEntry.availableHere or 0) > 0) and "ready" or "pending"
			end
		else
			local idStr = tostring(itemID or itemName or "item")
			local prov = {}
			if type(item.provenance) == "table" then
				for i, p in ipairs(item.provenance) do prov[i] = p end
			end
			mailEntry = {
				_order = maxOrder + 1,
				key = idStr .. ":mail",
				itemID = itemID,
				name = itemName or ("Item #" .. idStr),
				source = "mail",
				needed = qty,
				collected = 0,
				remaining = qty,
				altOwners = {},
				altLabel = nil,
				availableHere = 0,
				status = "pending",
				provenance = prov,
			}
			col.items[#col.items + 1] = mailEntry
		end
		sortCollectItems()
		local cur = col.items[col.activeIndex]
		if not cur or cur.status == "done" or cur.status == "skipped" or cur.source == "alt" or (cur.remaining or 0) <= 0 then
			selectNextPendingCollectInternal(1, "mail")
		end
		return true
	end

	local function completePurchasedItem(ah, matchedIdx, qtyBought, spentCopperAdd)
		local item = ah.items[matchedIdx]
		if not item then return false end
		local paidUnit = (item.liveUnit and item.liveUnit > 0) and item.liveUnit or (item.targetUnit or item.unitPrice or 0)
		local addCopper = (spentCopperAdd and spentCopperAdd > 0) and spentCopperAdd or (paidUnit * qtyBought)
		ah.spentCopper = (tonumber(ah.spentCopper) or 0) + addCopper
		item.bought = (item.bought or 0) + qtyBought
		item.remaining = math.max(0, (item.needed or 0) - item.bought)
		item.totalPrice = (item.unitPrice or 0) * item.remaining
		clearItemLiveAH(item)
		recordPurchasedToCollectMail(item, qtyBought)
		if item.remaining <= 0 then
			item.status = "done"
			local nextIdx = selectNextPendingAH(matchedIdx + 1)
			if nextIdx then
				orderFlow.notice = string.format("Bought %dx %s! Loading next item...", qtyBought, tostring(item.name))
				orderFlow.noticeKind = "positive"
				notifyOrderFlow()
				if atAH() then
					if C_Timer and C_Timer.After then
						C_Timer.After(0.25, function()
							if orderFlow.active and atAH() and ah.activeIndex == nextIdx then
								CartBuyer.OpenInAH(nextIdx)
							end
						end)
					else
						CartBuyer.OpenInAH(nextIdx)
					end
				end
			else
				orderFlow.notice = string.format("Bought %dx %s - All shopping cart items complete!", qtyBought, tostring(item.name))
				orderFlow.noticeKind = "positive"
				notifyOrderFlow()
			end
		else
			orderFlow.notice = string.format("Bought %dx %s (%d still needed).", qtyBought, tostring(item.name), item.remaining)
			orderFlow.noticeKind = "info"
			notifyOrderFlow()
			if atAH() then
				if C_Timer and C_Timer.After then
					C_Timer.After(0.25, function()
						if orderFlow.active and atAH() and ah.activeIndex == matchedIdx then
							CartBuyer.OpenInAH(matchedIdx)
						end
					end)
				else
					CartBuyer.OpenInAH(matchedIdx)
				end
			end
		end
		return true
	end

	handleCartBuyerEvent = function(event, arg1, arg2)
		local ah = orderFlow.stages.ah
		if event == "AUCTION_HOUSE_CLOSED" then
			OrderFlow.OnAuctionHouseClosed()
			return false
		elseif event == "COMMODITY_PRICE_UPDATED" then
			local d = ah.directBuy
			if not (d and d.kind == "commodity" and (d.state == "quoting" or d.state == "awaiting_confirm")) then
				return false
			end
			local unit = safeNumber(arg1)
			local total = safeNumber(arg2)
			if not unit or unit <= 0 or not total or total <= 0 then
				CartBuyer.CancelDirectBuy("Invalid commodity quote received - retry.", true)
				return true
			end
			unit = math.floor(unit)
			total = math.floor(total)
			local money = getPlayerCopper()
			if money ~= nil and total > money then
				CartBuyer.CancelDirectBuy("Quote exceeds available gold - cancelled.", true)
				return true
			end
			if d.maxBuyUnit and unit > d.maxBuyUnit then
				CartBuyer.CancelDirectBuy(string.format("Quote %s ea exceeds Max Buy cap %s - cancelled.",
					ns.FormatMoneyCompact(unit), ns.FormatMoneyCompact(d.maxBuyUnit)), true)
				return true
			end
			if d.maxTotal and total > d.maxTotal then
				CartBuyer.CancelDirectBuy(string.format("Quote %s jumped above limit %s - cancelled.",
					ns.FormatMoneyCompact(total), ns.FormatMoneyCompact(d.maxTotal)), true)
				return true
			end
			ah.directBuySerial = (ah.directBuySerial or 0) + 1
			local serial = ah.directBuySerial
			d.serial = serial
			d.verifiedUnit = unit
			d.verifiedTotal = total
			d.state = "awaiting_confirm"

			local window = DIRECT_QUOTE_TIMEOUT
			if C_AuctionHouse and type(C_AuctionHouse.GetQuoteDurationRemaining) == "function" then
				local okQ, rem = pcall(C_AuctionHouse.GetQuoteDurationRemaining)
				local remNum = okQ and safeNumber(rem) or nil
				if remNum and remNum > 0 then
					window = math.max(5, math.min(120, remNum))
				end
			end

			orderFlow.notice = string.format("Quote locked: %dx %s for %s. Click Confirm to buy.",
				d.qty, tostring(d.name), ns.FormatMoneyCompact(total))
			orderFlow.noticeKind = "positive"
			notifyOrderFlow()
			armDirectBuyWatchdog(serial, "awaiting_confirm", window, "Commodity quote expired before Confirm.", true)
			return true
		elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
			if ah.directBuy and ah.directBuy.kind == "commodity" then
				CartBuyer.CancelDirectBuy("Commodity price unavailable - retry.", true)
				return true
			end
			return false
		elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
			local d = ah.directBuy
			local ext = ah.pendingExternal
			ah.pendingExternal = nil
			if d and d.kind == "commodity" and d.state == "confirming" then
				if not ext then
					ext = { itemID = d.itemID, quantity = d.qty, verifiedTotal = d.verifiedTotal, fromDirectBuy = true }
				elseif not ext.verifiedTotal and d.verifiedTotal then
					ext.verifiedTotal = d.verifiedTotal
				end
				ah.directBuy = nil
				ah.directBuySerial = (ah.directBuySerial or 0) + 1
				if ns.AHChannel and ns.AHChannel.Release then
					ns.AHChannel.Release("cart_buyer")
				end
			end
			if not (orderFlow.active and ext and ext.itemID and ext.quantity) then return false end
			local matchedIdx = nil
			local cur = ah.items[ah.activeIndex]
			if cur and cur.itemID == ext.itemID and cur.remaining > 0 then
				matchedIdx = ah.activeIndex
			else
				for i, it in ipairs(ah.items) do
					if it.itemID == ext.itemID and it.remaining > 0 then
						matchedIdx = i
						break
					end
				end
			end
			if not matchedIdx then return false end
			completePurchasedItem(ah, matchedIdx, ext.quantity, ext.verifiedTotal)
			return false
		elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
			local aid = safeNumber(arg1)
			local d = ah.directBuy
			local extBid = ah.pendingExternalBid
			local target = nil
			if d and d.kind == "item" and d.state == "buying" then
				if arg1 == nil or (aid and aid == d.auctionID) then
					target = d
					ah.directBuy = nil
					ah.directBuySerial = (ah.directBuySerial or 0) + 1
					if ns.AHChannel and ns.AHChannel.Release then
						ns.AHChannel.Release("cart_buyer")
					end
				end
			elseif extBid then
				if arg1 == nil or (aid and aid == extBid.auctionID) then
					target = extBid
					ah.pendingExternalBid = nil
				end
			end
			if not target then return false end
			local matchedIdx = nil
			if target.index and ah.items[target.index] and ah.items[target.index].remaining > 0 then
				matchedIdx = target.index
			elseif target.itemID then
				local cur = ah.items[ah.activeIndex]
				if cur and cur.itemID == target.itemID and cur.remaining > 0 then
					matchedIdx = ah.activeIndex
				else
					for i, it in ipairs(ah.items) do
						if it.itemID == target.itemID and it.remaining > 0 then
							matchedIdx = i
							break
						end
					end
				end
			end
			if not matchedIdx then return false end
			app.bagsDirty = true
			app.bagCountsDirty = true
			if app.invalidateRecipeStats then app.invalidateRecipeStats("ownership") end
			completePurchasedItem(ah, matchedIdx, math.max(1, math.floor(target.qty or 1)), target.buyoutAmount)
			return true
		elseif event == "COMMODITY_SEARCH_RESULTS_RECEIVED" or event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
			if handleSellSearchResults(true, arg1) then
				return false
			end
			local chOwner = ns.AHChannel and ns.AHChannel.GetOwner and ns.AHChannel.GetOwner()
			if chOwner == "ah_seller" or chOwner == "ah_sell" or chOwner == "ah_undercut" then
				return false
			end
			if orderFlow.active and C_AuctionHouse and C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetCommoditySearchResultInfo then
				local id = safeNumber(arg1)
				local cur = ah.items[ah.activeIndex]
				if cur and cur.itemID and (id == cur.itemID or id == nil) and cur.remaining > 0 then
					local count = C_AuctionHouse.GetNumCommoditySearchResults(cur.itemID) or 0
					local qtyLeft, total, filled = cur.remaining, 0, 0
					local mktFirstUnit, mktTotalQty = nil, 0
					for i = 1, count do
						local info = C_AuctionHouse.GetCommoditySearchResultInfo(cur.itemID, i)
						if tableValue(info) then
							local u = safeNumber(info.unitPrice)
							local q = safeNumber(info.quantity)
							if u and u > 0 and q and q > 0 then
								mktFirstUnit = mktFirstUnit and math.min(mktFirstUnit, u) or u
								mktTotalQty = mktTotalQty + math.floor(q)
							end
							if qtyLeft > 0 then
								local ownQ = math.max(0, math.floor(safeNumber(info.numOwnerItems) or 0))
								local buyableQ = (q and q > 0) and math.max(0, math.floor(q) - ownQ) or 0
								if u and u > 0 and buyableQ > 0 then
									local take = math.min(qtyLeft, buyableQ)
									total = total + take * u
									filled = filled + take
									qtyLeft = qtyLeft - take
								end
							end
						end
					end
					if type(C_AuctionHouse.GetCommoditySearchResultsQuantity) == "function" then
						local okTQ, tq = pcall(C_AuctionHouse.GetCommoditySearchResultsQuantity, cur.itemID)
						if okTQ and safeNumber(tq) and tq > 0 then
							mktTotalQty = math.max(mktTotalQty, math.floor(tq))
						end
					end
					if mktFirstUnit and mktFirstUnit > 0 and mktTotalQty > 0 then
						MarketScan.RecordLiveItemPrice(cur.itemID, mktFirstUnit, mktTotalQty, { itemWide = false })
					end
					if filled > 0 then
						local liveUnit = math.ceil(total / filled)
						cur.liveKind = "commodity"
						cur.liveAvailQty = filled
						cur.liveUnit = liveUnit
						cur.liveTotal = total
						cur.liveAuctionID = nil
						cur.liveBuyout = nil
						cur.liveAuctionQty = nil
						cur.overbuyStackWarning = nil
						if cur.maxBuyUnit and cur.maxBuyUnit > 0 then
							cur.buyCapMarginCopper = cur.maxBuyUnit - liveUnit
							cur.overBuyCap = (liveUnit > cur.maxBuyUnit)
						else
							cur.buyCapMarginCopper = nil
							cur.overBuyCap = nil
						end
						if cur.targetUnit and cur.targetUnit > 0 then
							local diff = liveUnit - cur.targetUnit
							local pct = math.floor((diff / cur.targetUnit) * 100 + 0.5)
							cur.priceDeltaPct = pct
							cur.priceDiffCopper = diff
							cur.priceDiffPct = pct
							cur.priceDiffTotalCopper = diff * (cur.remaining or 0)
							if pct >= 20 then
								cur.priceAlert = "high"
								orderFlow.notice = string.format("PRICE JUMP! Cart expected %s ea, live AH is %s ea (+%d%%).",
									ns.FormatMoneyCompact(cur.targetUnit), ns.FormatMoneyCompact(liveUnit), pct)
								orderFlow.noticeKind = "danger"
							elseif pct > 0 then
								cur.priceAlert = "up"
								orderFlow.notice = string.format("Live AH is +%d%% above cart price (%s -> %s ea).",
									pct, ns.FormatMoneyCompact(cur.targetUnit), ns.FormatMoneyCompact(liveUnit))
								orderFlow.noticeKind = "warning"
							else
								cur.priceAlert = "ok"
								orderFlow.notice = string.format("Live AH matches cart price (%s ea for %dx).",
									ns.FormatMoneyCompact(liveUnit), filled)
								orderFlow.noticeKind = "positive"
							end
						end
						notifyOrderFlow()
					else
						clearItemLiveAH(cur)
						orderFlow.notice = "No buyable AH listings for " .. tostring(cur.name) .. "."
						orderFlow.noticeKind = "warning"
						notifyOrderFlow()
					end
				end
			end
			return false
		elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
			if handleSellSearchResults(false, arg1) then
				return false
			end
			local chOwner = ns.AHChannel and ns.AHChannel.GetOwner and ns.AHChannel.GetOwner()
			if chOwner == "ah_seller" or chOwner == "ah_sell" or chOwner == "ah_undercut" then
				return false
			end
			if orderFlow.active and C_AuctionHouse and C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetItemSearchResultInfo then
				local key = tableValue(arg1)
				local cur = ah.items[ah.activeIndex]
				if cur and key and safeNumber(key.itemID) == cur.itemID and cur.remaining > 0 then
					local count = C_AuctionHouse.GetNumItemSearchResults(key) or 0
					local bestUnit, bestBuyout, bestQty, bestAuctionID = nil, nil, nil, nil
					local mktMinUnit, mktTotalQty = nil, 0
					for i = 1, count do
						local info = C_AuctionHouse.GetItemSearchResultInfo(key, i)
						if tableValue(info) then
							local buyoutAll = safeNumber(info.buyoutAmount)
							local qtyAll = math.max(1, math.floor(safeNumber(info.quantity) or 1))
							if buyoutAll and buyoutAll > 0 then
								local uAll = buyoutAll / qtyAll
								mktTotalQty = mktTotalQty + qtyAll
								mktMinUnit = mktMinUnit and math.min(mktMinUnit, uAll) or uAll
							end
							if not info.containsOwnerItem and not info.containsAccountItem
								and (safeNumber(info.numOwnerItems) or 0) <= 0 then
								local buyout = buyoutAll
								if buyout and buyout > 0 then
									local qty = qtyAll
									local unitBuyout = buyout / qty
									if not bestUnit or unitBuyout < bestUnit or (unitBuyout == bestUnit and buyout < bestBuyout) then
										bestUnit = unitBuyout
										bestBuyout = math.floor(buyout)
										bestQty = qty
										bestAuctionID = safeNumber(info.auctionID)
									end
								end
							end
						end
					end
					if mktMinUnit and mktMinUnit > 0 and mktTotalQty > 0 and isBaseItemKey(key) then
						MarketScan.RecordLiveItemPrice(cur.itemID, mktMinUnit, mktTotalQty, { itemWide = false })
					end
					if bestUnit and bestBuyout and bestBuyout > 0 then
						local liveUnit = math.ceil(bestUnit)
						cur.liveKind = "item"
						cur.liveAuctionID = bestAuctionID
						cur.liveBuyout = bestBuyout
						cur.liveAuctionQty = bestQty
						cur.liveAvailQty = bestQty
						cur.liveUnit = liveUnit
						cur.liveUnitExact = bestUnit
						cur.liveTotal = bestBuyout
						cur.overbuyStackWarning = (bestQty > (cur.remaining or 1))
						if cur.maxBuyUnit and cur.maxBuyUnit > 0 then
							cur.buyCapMarginCopper = cur.maxBuyUnit - liveUnit
							cur.overBuyCap = (bestUnit > cur.maxBuyUnit)
						else
							cur.buyCapMarginCopper = nil
							cur.overBuyCap = nil
						end
						if cur.targetUnit and cur.targetUnit > 0 then
							local diff = liveUnit - cur.targetUnit
							local pct = math.floor((diff / cur.targetUnit) * 100 + 0.5)
							cur.priceDeltaPct = pct
							cur.priceDiffCopper = diff
							cur.priceDiffPct = pct
							cur.priceDiffTotalCopper = diff * (cur.remaining or 0)
							if pct >= 20 then
								cur.priceAlert = "high"
								orderFlow.notice = string.format("PRICE JUMP! Cart expected %s ea, live AH is %s ea (+%d%%).",
									ns.FormatMoneyCompact(cur.targetUnit), ns.FormatMoneyCompact(liveUnit), pct)
								orderFlow.noticeKind = "danger"
							elseif pct > 0 then
								cur.priceAlert = "up"
								orderFlow.notice = string.format("Live AH is +%d%% above cart price (%s -> %s ea).",
									pct, ns.FormatMoneyCompact(cur.targetUnit), ns.FormatMoneyCompact(liveUnit))
								orderFlow.noticeKind = "warning"
							else
								cur.priceAlert = "ok"
								orderFlow.notice = string.format("Live AH matches cart price (%s ea).", ns.FormatMoneyCompact(liveUnit))
								orderFlow.noticeKind = "positive"
							end
						end
						if cur.overbuyStackWarning and orderFlow.noticeKind ~= "danger" then
							orderFlow.notice = string.format("Cheapest listing is a stack of %dx (need %dx) at %s total.",
								bestQty, cur.remaining or 1, ns.FormatMoneyCompact(bestBuyout))
							orderFlow.noticeKind = "warning"
						end
						notifyOrderFlow()
					else
						clearItemLiveAH(cur)
						orderFlow.notice = "No buyout AH listings for " .. tostring(cur.name) .. "."
						orderFlow.noticeKind = "warning"
						notifyOrderFlow()
					end
				end
			end
			return false
		elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
			handleSellAuctionCreated(arg1)
			return false
		elseif event == "AUCTION_MULTISELL_START" then
			local sl = orderFlow.stages.sell
			local p = sl and sl.pendingPost
			if p and (p.state == "posting" or p.state == "confirming") then
				local total = math.floor(safeNumber(arg1) or p.qty or 1)
				p.multisellActive = true
				p.multisellTotal = math.max(1, total)
				p.multisellCreated = 0
				sl.postSerial = (sl.postSerial or 0) + 1
				local serial = sl.postSerial
				p.serial = serial
				p.startedAt = nowSellMono()
				armSellPostWatchdog(serial, "Auction multisell timed out.")
				orderFlow.notice = string.format("Posting 0/%d %s...", p.multisellTotal, tostring(p.name or "item"))
				orderFlow.noticeKind = "info"
				notifyOrderFlow(true)
			end
			return false
		elseif event == "AUCTION_MULTISELL_UPDATE" then
			local sl = orderFlow.stages.sell
			local p = sl and sl.pendingPost
			if p and (p.state == "posting" or p.state == "confirming") then
				p.multisellActive = true
				local created = math.floor(safeNumber(arg1) or 0)
				local total = math.floor(safeNumber(arg2) or p.multisellTotal or 0)
				if created > (p.multisellCreated or 0) then
					p.multisellCreated = created
				end
				if total > 0 then p.multisellTotal = total end
				if total > 0 and created >= total then
					p.multisellActive = false
					completePendingSellPost(nil)
				elseif total > 0 then
					sl.postSerial = (sl.postSerial or 0) + 1
					local serial = sl.postSerial
					p.serial = serial
					p.startedAt = nowSellMono()
					armSellPostWatchdog(serial, "Auction multisell timed out.")
					orderFlow.notice = string.format("Posting %d/%d %s...", created, total, tostring(p.name or "item"))
					orderFlow.noticeKind = "info"
					notifyOrderFlow(true)
				end
			end
			return false
		elseif event == "AUCTION_MULTISELL_FAILURE" then
			local sl = orderFlow.stages.sell
			local p = sl and sl.pendingPost
			if p and (p.state == "posting" or p.state == "confirming") then
				local partial = math.floor(safeNumber(p.multisellCreated) or 0)
				local it = sl.items[p.itemIndex]
				local applied = 0
				if partial > 0 and it then
					applied = math.min(math.max(0, it.remaining or partial), math.max(0, p.qty or partial), partial)
					if applied > 0 then
						it.soldQty = math.min(it.totalQty or ((it.soldQty or 0) + applied), (it.soldQty or 0) + applied)
						it.remaining = math.max(0, (it.totalQty or 0) - it.soldQty)
						it.inBags = it.itemID and getSellableBagCount(it.itemID, it.channel == "vendor", it.itemLink) or 0
						sl.totalEarnedCopper = (sl.totalEarnedCopper or 0) + (applied * (p.unitPrice or 0))
						if it.remaining <= 0 then
							it.status = "done"
							it.postQty = 0
						else
							local newLimit = OrderFlow.GetSellPostLimit(it)
							it.postQty = (newLimit > 0) and math.min(math.max(1, it.postQty or 1), it.remaining, newLimit) or 0
						end
					end
				end
				sl.pendingPost = nil
				sl.postAllActive = false
				if sl.pendingSearch == nil and ns.AHChannel and ns.AHChannel.Release then
					ns.AHChannel.Release("orderflow_sell")
				end
				if applied > 0 then
					orderFlow.notice = string.format("Multisell stopped after %d/%d %s posted.",
						applied, math.floor(p.qty or applied), tostring(p.name or "item"))
					orderFlow.noticeKind = "warning"
				else
					orderFlow.notice = "Multisell auction failed."
					orderFlow.noticeKind = "danger"
				end
				notifyOrderFlow()
			end
			return false
		elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
			local sl = orderFlow.stages.sell
			local pk = sl and sl.pendingKeyPrime
			local id = safeNumber(arg1)
			if pk and (not id or pk.itemID == id) and sl.pendingSearch and sl.pendingSearch.serial == pk.serial then
				sl.pendingKeyPrime = nil
				dispatchSellSearchQuery(_G.C_AuctionHouse, pk.itemKey, pk.isCommodity, pk.isEquipment)
			end
			return false
		elseif event == "UI_ERROR_MESSAGE" then
			local msg = (readable(arg2) and type(arg2) == "string" and arg2)
				or (readable(arg1) and type(arg1) == "string" and arg1)
				or ""
			if ah and ah.directBuy and (ah.directBuy.state == "quoting" or ah.directBuy.state == "confirming" or ah.directBuy.state == "buying") then
				if isSellAHUIError(msg) then
					CartBuyer.CancelDirectBuy(msg, ah.directBuy.kind == "commodity")
				end
			end
			local sl = orderFlow.stages.sell
			if sl and sl.pendingPost and (sl.pendingPost.state == "posting" or sl.pendingPost.state == "confirming") then
				if isSellAHUIError(msg) then
					sl.pendingPost = nil
					sl.postAllActive = false
					if sl.pendingSearch == nil and ns.AHChannel and ns.AHChannel.Release then
						ns.AHChannel.Release("orderflow_sell")
					end
					orderFlow.notice = msg
					orderFlow.noticeKind = "danger"
					notifyOrderFlow()
				end
			end
			return false
		elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" or event == "AUCTION_HOUSE_BROWSE_FAILURE" then
			if event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" and ah and ah.directBuy
				and (ah.directBuy.state == "quoting" or ah.directBuy.state == "confirming" or ah.directBuy.state == "buying") then
				CartBuyer.CancelDirectBuy("AH throttled - please click again.", ah.directBuy.kind == "commodity")
			end
			local sl = orderFlow.stages.sell
			local changed = false
			if sl and sl.pendingPost and (sl.pendingPost.state == "posting" or sl.pendingPost.state == "confirming") then
				sl.pendingPost = nil
				sl.postAllActive = false
				orderFlow.notice = "AH throttled - please click again."
				orderFlow.noticeKind = "warning"
				changed = true
			end
			if sl and sl.pendingSearch then
				sl.pendingSearch = nil
				sl.pendingKeyPrime = nil
				changed = true
			end
			if changed then
				if sl and sl.pendingPost == nil and sl.pendingSearch == nil and ns.AHChannel and ns.AHChannel.Release then
					ns.AHChannel.Release("orderflow_sell")
				end
				notifyOrderFlow()
			elseif (orderFlow.active and orderFlow.activeStage == "sell") or (ns.AHSellTab and ns.AHSellTab.IsShown and ns.AHSellTab.IsShown()) then
				notifyOrderFlow(true)
			end
			return false
		elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED" or event == "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT" then
			local sl = orderFlow.stages.sell
			if sl and not sl.throttleBlockedAt then
				sl.throttleBlockedAt = nowSellMono()
			end
			if (orderFlow.active and orderFlow.activeStage == "sell") or (ns.AHSellTab and ns.AHSellTab.IsShown and ns.AHSellTab.IsShown()) then
				notifyOrderFlow(true)
			end
			return false
		elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED" or event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
			local sl = orderFlow.stages.sell
			if sl then
				if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY"
					or not (C_AuctionHouse and type(C_AuctionHouse.IsThrottledMessageSystemReady) == "function")
					or C_AuctionHouse.IsThrottledMessageSystemReady() ~= false then
					sl.throttleBlockedAt = nil
					local prs = sl.pendingRetryScan
					if prs and atAH() and sl.pendingPost == nil and sl.pendingSearch == nil then
						sl.pendingRetryScan = nil
						sl.scanRetrySerial = (sl.scanRetrySerial or 0) + 1
						dispatchSellScanInternal(prs.targetInfo, prs.itemIndex, prs.reason, prs.attempt)
					end
				end
			end
			if (orderFlow.active and orderFlow.activeStage == "sell") or (ns.AHSellTab and ns.AHSellTab.IsShown and ns.AHSellTab.IsShown()) then
				notifyOrderFlow(true)
			end
			return false
		elseif event == "COMMODITY_PURCHASE_FAILED" then
			if ah.directBuy and ah.directBuy.kind == "commodity" then
				CartBuyer.CancelDirectBuy("AH purchase failed (listings moved). Retry.", false)
			elseif orderFlow.active and ah.pendingExternal then
				ah.pendingExternal = nil
				orderFlow.notice = "AH purchase failed (listings moved). Retry in the Auction House window."
				orderFlow.noticeKind = "warning"
				notifyOrderFlow()
			end
			return false
		end
		return false
	end
end
function MarketScan.HandleEvent(event, arg1, arg2)
	local cbHandled = handleCartBuyerEvent(event, arg1, arg2)
	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		local updated = event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"
		if updated then arg1 = nil end
		if marketScan.active then
			handleMarketBrowseResults(arg1)
		elseif bagScan.job then
			if updated and bagScan.job.browseToken then bagScan.job.answered, bagScan.job.browseRows = true, nil end
			scanBrowsed(arg1)
		else
			openWanted(updated, arg1)
		end
	elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" or event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
		if event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
			bagScan.sniperGap = math.min(SNIPER_MAX_GAP, math.max((bagScan.sniperGap or SNIPER_QUERY_GAP) + 0.10, 0.20))
		end
		if marketScan.active and marketScan.querySent then
			app.cancelMarketScan(true)
			say(L.noAnswer)
		end
	elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
		if bagScan.sniperGap and bagScan.sniperGap > SNIPER_QUERY_GAP then
			bagScan.sniperGap = math.max(SNIPER_QUERY_GAP, bagScan.sniperGap - 0.05)
		end
		if not marketScan.active and not bagScan.job and app.wanted and app.wanted.pendingBar then
			local b = app.wanted.pendingBar
			app.wanted.pendingBar = nil
			if AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame.SearchBar == b then
				sendWantedWhenReady(app.wanted, b)
			end
		end
		if marketScan.onReady then
			local mfn = marketScan.onReady
			marketScan.onReady = nil
			mfn()
			return true
		end
		local fn = bagScan.onReady
		bagScan.onReady = nil
		if fn then fn() end
	elseif event == "COMMODITY_SEARCH_RESULTS_RECEIVED" or event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
		handleSearchResult(arg1, true, event == "COMMODITY_SEARCH_RESULTS_RECEIVED" or event == "COMMODITY_SEARCH_RESULTS_UPDATED")
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
		handleSearchResult(arg1, false)
	elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
		if bagScan.job then scanBrowsed() end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if bagScan.job then scanBrowsed() end
		return false
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if ns.AHChannel and ns.AHChannel.Reset then ns.AHChannel.Reset() end
		invalidatePendingSearch()
		return false
	elseif cbHandled then
		return true
	else
		return false
	end
	return true
end

MarketScan.ScanBagCrates = scanBagCrates
MarketScan.HookBuyFrame = hookBuyFrame
MarketScan.ActiveEconomyPrices = activeEconomyPrices
end
