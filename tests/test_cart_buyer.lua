local S = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns, frames = dofile(S .. "host_fixture.lua")

local n = 0
local function check(ok, msg)
	n = n + 1
	if not ok then
		error("FAIL [" .. n .. "]: " .. tostring(msg), 2)
	end
end

local app = ns.app
local cb = app.cartBuyer
local modal = app.ui.cartBuyerModal
check(cb ~= nil, "app.cartBuyer engine exposed")
check(modal ~= nil, "app.ui.cartBuyerModal floating window exposed")
check(app.isBuiltInAHBuyerEnabled == nil, "legacy app.isBuiltInAHBuyerEnabled removed")
check(app.setBuiltInAHBuyer == nil, "legacy app.setBuiltInAHBuyer removed")
check(app.multiSearchAuctionator == nil, "legacy app.multiSearchAuctionator removed")
check(app.sendShoppingRowsToAuctionator == nil, "legacy app.sendShoppingRowsToAuctionator removed")
check(type(app.multiSearchBuyer) == "function", "app.multiSearchBuyer defined")
check(type(app.sendShoppingRowsToBuyer) == "function", "app.sendShoppingRowsToBuyer defined")
check(type(app.openCartBuyer) == "function", "app.openCartBuyer defined")

-- 1. Standalone Built-in AH Buyer is the sole native path even if Auctionator global exists
local origAuctionator = _G.Auctionator
local atrCalled = 0
_G.Auctionator = { API = { v1 = { MultiSearchAdvanced = function() atrCalled = atrCalled + 1 end } } }
check(app.ui.shopPanel.buyerModeBtn == nil, "Legacy Buyer mode toggle button removed from Shopping panel")
check(app.ui.shopPanel.buyAllBtn:GetText() == "Send to Auction House", "Standalone CTA shows Send to Auction House")
local dashAucLabel = (app.ui.dashAucBtn._mmLabel and app.ui.dashAucBtn._mmLabel:GetText()) or app.ui.dashAucBtn:GetText()
check(dashAucLabel == "Buy on AH", "Dashboard CTA shows Buy on AH")

-- Track Blizzard searchAH calls and ensure protected purchase APIs are NEVER called by addon code
_G.AuctionHouseFrame:Show()
local protectedCalled = false
local mockLiveCommodity = {
	[2770] = { { unitPrice = 1500, quantity = 50 } }, -- 15s live vs 1s cart target (+1400%!)
	[2771] = { { unitPrice = 90, quantity = 50 } },   -- 90c live vs 100c cart target (OK)
}
_G.C_AuctionHouse = {
	StartCommoditiesPurchase = function() protectedCalled = true end,
	ConfirmCommoditiesPurchase = function() protectedCalled = true end,
	PlaceBid = function() protectedCalled = true end,
	GetNumCommoditySearchResults = function(itemID)
		return mockLiveCommodity[itemID] and #mockLiveCommodity[itemID] or 0
	end,
	GetCommoditySearchResultInfo = function(itemID, idx)
		return mockLiveCommodity[itemID] and mockLiveCommodity[itemID][idx] or nil
	end,
}

local ahSearches = {}
local origSearchAH = app.searchAH
app.searchAH = function(name, qty, itemID)
	ahSearches[#ahSearches + 1] = { name = name, qty = qty, itemID = itemID }
	return true
end

-- Also make C_Timer.After immediate for deterministic auto-advance check
local origAfter = _G.C_Timer and _G.C_Timer.After
if _G.C_Timer then
	_G.C_Timer.After = function(_, fn) fn() end
end

-- 3. Send shopping rows -> opens sidecar, deduplicates Copper Ore (5 + 3 = 8), opens item 1 in Blizzard native AH
atrCalled = 0
local opened = app.sendShoppingRowsToBuyer({
	{ name = "Copper Ore", itemID = 2770, qty = 5, ahUnitPrice = 100 },
	{ name = "Copper Ore", itemID = 2770, qty = 3, ahUnitPrice = 100 },
	{ name = "Tin Ore", itemID = 2771, qty = 5, ahUnitPrice = 100 },
	{ name = "Rare Recipe", itemID = 19019, qty = 1, ahUnitPrice = 25000 },
	{ name = "Crafted Bar", itemID = 2840, qty = 2, makeMyself = true },
	{ name = "Vendor Flux", itemID = 2880, qty = 3, isVendor = true },
}, "Shopping List")
_G.Auctionator = origAuctionator

check(opened == true, "sendShoppingRowsToBuyer returns true in standalone built-in mode")
check(atrCalled == 0, "Standalone built-in mode never invokes Auctionator")
check(modal:IsShown(), "Built-in AH Cart sidecar opens")
check(protectedCalled == false, "Zero protected purchase APIs called by addon code")

local st = cb.GetState()
check(#st.items == 3, "Cart loaded 3 deduplicated AH items, got " .. #st.items)
check(st.items[1].needed == 8 and st.items[1].itemID == 2770, "Duplicate Copper Ore merged to qty 8")
check(#ahSearches == 1 and ahSearches[1].itemID == 2770 and ahSearches[1].qty == 8,
	"Item 1 opened directly in Blizzard native AH with qty 8 pre-filled")
check(st.items[1].status == "active", "Item 1 marked active (In AH)")
check(st.items[1].targetUnit == 100, "Item 1 preserves shopping cart target price (100c = 1s)")

-- 3b. Blizzard live AH results arrive at 15s (1500c) vs 1s (100c) cart price -> flags +1400% PRICE JUMP!
ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
check(st.items[1].liveUnit == 1500, "Item 1 captures live AH unit price (1500c = 15s)")
check(st.items[1].priceDeltaPct == 1400 and st.items[1].priceAlert == "high",
	"1s -> 15s jump triggers high price alert (+1400%)")
check(st.noticeKind == "danger", "Price jump sets danger notice banner")

-- 4. User buys in Blizzard's native AH: ConfirmCommoditiesPurchase hook + COMMODITY_PURCHASE_SUCCEEDED
-- Partial buy (3 of 8) keeps item 1 active with remaining=5 and reloads AH qty to 5
cb.OnCommodityPurchaseConfirmed(2770, 3)
ns.MarketScan.HandleEvent("COMMODITY_PURCHASE_SUCCEEDED")
check(st.items[1].bought == 3 and st.items[1].remaining == 5 and st.items[1].status == "active",
	"Partial native purchase updates bought=3 remaining=5")
check(#ahSearches == 2 and ahSearches[2].itemID == 2770 and ahSearches[2].qty == 5,
	"Partial native purchase reloads Blizzard AH with remaining qty 5")

-- Remaining buy (5 of 8) marks item 1 done and auto-opens item 2 (Tin Ore, qty 5) in Blizzard AH!
cb.OnCommodityPurchaseConfirmed(2770, 5)
ns.MarketScan.HandleEvent("COMMODITY_PURCHASE_SUCCEEDED")
check(st.items[1].bought == 8 and st.items[1].remaining == 0 and st.items[1].status == "done",
	"Completed native purchase marks item 1 done")
check(st.activeIndex == 2 and st.items[2].status == "active", "Auto-advanced to item 2 (Tin Ore)")
check(#ahSearches == 3 and ahSearches[3].itemID == 2771 and ahSearches[3].qty == 5,
	"Auto-opened item 2 (Tin Ore, qty 5) in Blizzard native AH")
ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 2771)
check(st.items[2].liveUnit == 90 and st.items[2].priceAlert == "ok" and st.noticeKind == "positive",
	"Live price at/below cart target (90c <= 100c) marks priceAlert=ok")

-- 5. MarkBought on item 2 marks it done and auto-opens item 3 (Rare Recipe, qty 1)
cb.MarkBought()
check(st.items[2].status == "done" and st.items[2].remaining == 0, "MarkBought completes item 2")
check(st.activeIndex == 3 and st.items[3].status == "active", "MarkBought auto-advances to item 3")
check(#ahSearches == 4 and ahSearches[4].itemID == 19019 and ahSearches[4].qty == 1,
	"Auto-opened item 3 (Rare Recipe, qty 1) in Blizzard native AH")
check(protectedCalled == false, "Protected purchase APIs still never called directly by addon")

-- 6. Legacy Switch to Auctionator button is completely removed from Cart sidecar
check(modal.modeBtn == nil, "Legacy Switch to Auctionator button removed from Cart sidecar")
modal:Hide()

-- Helper to dispatch WoW events through all registered frames
local function fireEvent(ev, ...)
	for _, f in ipairs(frames) do
		if f._events and f._events[ev] and f._scripts and f._scripts.OnEvent then
			f._scripts.OnEvent(f, ev, ...)
		end
	end
end

-- 7. Provenance threading, multi-recipe merging, main panel minimize/restore, waiting state & Buying For slide-out
MerchantMasterDB.ahBuyerExtended = false
local mainPanel = app.panel
local shopModal = app.ui.shopModal
check(mainPanel ~= nil and shopModal ~= nil, "Main panel and shopModal exposed")

-- Show both main panel and shopping cart modal, then close AH to test AH Closed Waiting state
mainPanel:Show()
shopModal:Show()
_G.AuctionHouseFrame:Hide()
ahSearches = {}

local provOpened = app.sendShoppingRowsToBuyer({
	{
		name = "Small Flame Sac",
		itemID = 4402,
		qty = 22,
		ahUnitPrice = 1450,
		isSubRow = true,
		parentSubName = "Fire Oil",
		categoryName = "Fire Protection Potion",
		sourceKind = "leveling",
		sourceLabel = "Leveling #12",
	},
	{
		name = "Dreamfoil",
		itemID = 13463,
		qty = 6,
		ahUnitPrice = 8200,
		categoryName = "Elixir of the Mongoose",
		sourceKind = "craft_order",
		sourceLabel = "Daily Craft",
	},
	{
		name = "Dreamfoil",
		itemID = 13463,
		qty = 4,
		ahUnitPrice = 8200,
		categoryName = "Elixir of the Mongoose",
		sourceKind = "craft_order",
		sourceLabel = "Daily Craft",
	},
	{
		name = "Dreamfoil",
		itemID = 13463,
		qty = 2,
		ahUnitPrice = 8200,
		categoryName = "Greater Fire Protection Potion",
		sourceKind = "craft_order",
		sourceLabel = "Craft Order",
	},
}, "Shopping List")

check(provOpened == true, "enterAHBuyingMode succeeds when AH is closed")
check(app._ahBuyingMode == true, "app._ahBuyingMode flag active")
check(modal:IsShown(), "AH Trade Strip opens when AH is closed")
check(not mainPanel:IsShown(), "enterAHBuyingMode hides giant main panel cleanly")
check(not shopModal:IsShown(), "enterAHBuyingMode hides shopping cart modal cleanly")

-- Provenance verification
local pst = cb.GetState()
check(#pst.items == 2, "Loaded 2 deduplicated AH items with provenance")
check(pst.items[1].itemID == 4402 and pst.items[1].needed == 22, "Item 1 is 22x Small Flame Sac")
check(pst.items[1].provenance and #pst.items[1].provenance == 1, "Small Flame Sac has 1 provenance chain")
check(pst.items[1].provenance[1].subCraftName == "Fire Oil", "Sub-craft Fire Oil preserved")
check(pst.items[1].provenance[1].targetName == "Fire Protection Potion", "Target Fire Protection Potion preserved")
check(pst.items[1].provenance[1].sourceLabel == "Leveling #12", "Leveling #12 source label preserved")

check(pst.items[2].itemID == 13463 and pst.items[2].needed == 12, "Shared Dreamfoil summed to 12")
check(pst.items[2].provenance and #pst.items[2].provenance == 2, "Dreamfoil merged duplicate Mongoose rows into 2 distinct destinations")
check(pst.items[2].provenance[1].targetName == "Elixir of the Mongoose" and pst.items[2].provenance[1].qty == 10,
	"Duplicate Dreamfoil -> Mongoose entries merged (6 + 4 = 10)")
check(pst.items[2].provenance[2].targetName == "Greater Fire Protection Potion" and pst.items[2].provenance[2].qty == 2,
	"Second Dreamfoil destination preserved (2x Greater Fire Protection Potion)")

local dests = cb.GetAllDestinations()
check(#dests == 3, "GetAllDestinations returns 3 unique destination goals, got " .. #dests)

-- Strict AH Closed Waiting state checks (NO Open AH button, NO subtext, ONLY exact text!)
check(pst.waitingForAH == true, "CartBuyer tracks waitingForAH = true while AH closed")
check(modal.waitingBanner and modal.waitingBanner:IsShown(), "Waiting banner shown while AH is closed")
check(modal.waitingFs and modal.waitingFs:GetText() == "Please open Auction House to start.",
	"Waiting banner text is strictly 'Please open Auction House to start.'")
check(modal.spotlightCard and not modal.spotlightCard:IsShown(),
	"Spotlight card (with Open in AH button) is completely hidden while AH is closed")
check(modal.rows[1]:IsShown() and modal.rows[2]:IsShown(), "Item cards remain visible while waiting for AH")
check(#ahSearches == 0, "No Blizzard AH search fired while AH is closed")

-- Buying For slide-out toggle works even while waiting
check(math.floor(modal:GetWidth() + 0.5) == 396, "Compact AH Trade Strip width is 396")
check(modal.treePane and not modal.treePane:IsShown(), "Craft Tree slide-out pane hidden when compact")
modal.extendBtn:Click("LeftButton")
check(math.floor(modal:GetWidth() + 0.5) == 706, "Extended Buying For widens AH Trade Strip to 706")
check(MerchantMasterDB.ahBuyerExtended == true, "Buying For extended state persisted to SavedVariables")
check(modal.treePane:IsShown(), "Craft Tree slide-out pane visible when Buying For is toggled ON")
check(modal.treeChainNodes[1]:IsShown() and modal.treeChainNodes[2]:IsShown() and modal.treeChainNodes[3]:IsShown(),
	"3-step sub-craft chain (Small Flame Sac -> Fire Oil -> Fire Protection Potion) rendered in Craft Tree")
check(modal.treeChainNodes[2].textFs:GetText():find("Fire Oil", 1, true) ~= nil, "Chain node 2 mentions Fire Oil sub-craft")
check(modal.treeDestRows[1]:IsShown() and modal.treeDestRows[2]:IsShown() and modal.treeDestRows[3]:IsShown(),
	"All 3 Cart Destinations populated in right pane")

-- AUCTION_HOUSE_SHOW while waiting: hides waitingBanner, shows spotlightCard, auto-loads item #1, keeps main panel hidden!
_G.AuctionHouseFrame:Show()
fireEvent("AUCTION_HOUSE_SHOW")
check(not modal.waitingBanner:IsShown(), "AUCTION_HOUSE_SHOW hides waiting banner")
check(modal.spotlightCard:IsShown(), "AUCTION_HOUSE_SHOW reveals Active Deal Spotlight card")
check(pst.waitingForAH == false, "waitingForAH cleared on AUCTION_HOUSE_SHOW")
check(not mainPanel:IsShown(), "AUCTION_HOUSE_SHOW keeps giant main panel hidden while in AH Buying Mode")
check(#ahSearches == 1 and ahSearches[1].itemID == 4402 and ahSearches[1].qty == 22,
	"AUCTION_HOUSE_SHOW auto-loads item #1 (22x Small Flame Sac) in Blizzard AH")

-- AUCTION_HOUSE_CLOSED returns modal cleanly to Waiting state when items remain unbought
_G.AuctionHouseFrame:Hide()
fireEvent("AUCTION_HOUSE_CLOSED")
check(modal:IsShown(), "AH Trade Strip stays visible when AH closes mid-queue")
check(modal.waitingBanner:IsShown(), "Waiting banner returns on AUCTION_HOUSE_CLOSED")
check(not modal.spotlightCard:IsShown(), "Spotlight card hides again on AUCTION_HOUSE_CLOSED")
check(modal.waitingFs:GetText() == "Please open Auction House to start.", "Exact waiting text preserved after AH closes")

-- Collapse Buying For back to compact 396
modal.extendBtn:Click("LeftButton")
check(math.floor(modal:GetWidth() + 0.5) == 396, "Toggling Buying For OFF collapses width back to 396")
check(not modal.treePane:IsShown(), "Craft Tree pane hidden after collapse")

-- Restore Full button exits AH Buying Mode and restores main MerchantMaster panel
modal.restoreBtn:Click("LeftButton")
check(app._ahBuyingMode == false, "Restore Full clears app._ahBuyingMode")
check(not modal:IsShown(), "Restore Full hides AH Trade Strip")
check(mainPanel:IsShown(), "Restore Full restores full MerchantMaster window")

-- 8. V3 Owner Upgrades: Overview stats (qty+price), Expected/Live/Diff Spotlight, centered Open in AH,
--    Auctionator hidden, NO "For ..." row hints, NO "Crafting Order" dest pills, selectable destination filter,
--    and genuine scrolling + visible scrollbars on BOTH Buying List and All Cart Destinations!
_G.AuctionHouseFrame:Show()
MerchantMasterDB.ahBuyerExtended = true
local v3Rows = {}
for idx = 1, 10 do
	local destName = "Craft Goal " .. tostring(idx <= 8 and idx or (idx - 2))
	v3Rows[#v3Rows + 1] = {
		name = "Reagent " .. tostring(idx),
		itemID = 50000 + idx,
		qty = 5,
		ahUnitPrice = 1000, -- 10s expected each
		categoryName = destName,
		sourceKind = "craft_order",
		sourceLabel = "Crafting Order",
	}
end
mockLiveCommodity[50001] = { { unitPrice = 800, quantity = 50 } }  -- -20% cheaper (-2s)
mockLiveCommodity[50002] = { { unitPrice = 1000, quantity = 50 } } -- exact match (0c / 0%)
mockLiveCommodity[50003] = { { unitPrice = 1300, quantity = 50 } } -- +30% jump (+3s)

ahSearches = {}
local v3Ok = app.sendShoppingRowsToBuyer(v3Rows, "Shopping List")
check(v3Ok == true, "V3 10-item / 8-destination cart loaded")

-- 8a. Auctionator button completely removed from AH Trade Strip
check(modal.modeBtn == nil, "Auctionator button is removed from AH Trade Strip")

-- 8b. Centered Open in AH button (no off-center left dot!)
check(modal.buyBtn.dot == nil, "Open in AH has no off-center left dot")
check(modal.buyBtn:GetText() == "Open in AH", "Open in AH label preserved")

local function stripColors(s)
	return tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

-- 8c. Bigger Spotlight with Expected / Live AH / Difference + zero clutter
ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 50001)
local v3st = cb.GetState()
check(v3st.items[1].priceDiffCopper == -200 and v3st.items[1].priceDiffPct == -20,
	"Cheaper live AH stores signed priceDiffCopper=-200 and priceDiffPct=-20")
check(modal.metricsBox and modal.metricsBox:IsShown(), "Expected / Live AH / Difference metrics box shown in Spotlight")
check(stripColors(modal.spotExpectedFs:GetText()):find("10s", 1, true) ~= nil, "Spotlight Expected shows 10s, got: " .. stripColors(modal.spotExpectedFs:GetText()))
check(stripColors(modal.spotLiveFs:GetText()):find("8s", 1, true) ~= nil, "Spotlight Live AH shows 8s, got: " .. stripColors(modal.spotLiveFs:GetText()))
check(stripColors(modal.spotDiffFs:GetText()):find("-20%", 1, true) ~= nil, "Spotlight Difference shows negative -20% savings")
check(modal.noticeFs:IsShown() and modal.noticeBar and modal.noticeBar:IsShown(), "Live notice pill bar shown when notice text is active")

-- Exact match check on item 2
cb.SelectItem(2)
ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 50002)
check(v3st.items[2].priceDiffCopper == 0 and v3st.items[2].priceDiffPct == 0, "Exact match diff is 0c / 0%")
check(modal.spotDiffFs:GetText():find("0%", 1, true) ~= nil, "Spotlight Difference shows 0c (0%) on exact match")

-- Pricier check on item 3
cb.SelectItem(3)
ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 50003)
check(v3st.items[3].priceDiffCopper == 300 and v3st.items[3].priceDiffPct == 30, "Pricier live AH stores +300c / +30%")
check(modal.spotDiffFs:GetText():find("+30%", 1, true) ~= nil, "Spotlight Difference shows +30% warning")

-- 8d. Overview stats track Bought & To Buy in BOTH price and quantities
cb.MarkBought(1) -- 5 units at 800c live = 4000c spent
local ov = cb.GetOverviewStats()
check(ov.totalItems == 10 and ov.boughtItems == 1 and ov.remainingItems == 9, "Overview item counts: 1/10 bought, 9 remaining")
check(ov.totalUnits == 50 and ov.boughtUnits == 5 and ov.remainingUnits == 45, "Overview unit counts: 5/50 qty bought, 45 remaining")
check(ov.spentCopper == 4000, "Overview spentCopper tracks exact 4000c (40s) spent")
check(ov.totalEstCopper == 50000, "Overview totalEstCopper is 50000c (5g)")
check(modal.summaryFs:GetText():find("Bought:", 1, true) ~= nil and modal.summaryFs:GetText():find("5/50 qty", 1, true) ~= nil,
	"Ribbon line 1 displays Bought items, qty, and spent price")
check(modal.toBuySummaryFs:GetText():find("To Buy:", 1, true) ~= nil and modal.toBuySummaryFs:GetText():find("45 qty", 1, true) ~= nil,
	"Ribbon line 2 displays To Buy items, qty, and remaining/total price")

-- 8e. Buying List rows have NO "For ..." subtitle & visible scrollbar when > 8 items
check(not modal.rows[1].cells.hint:IsShown(), "Buying List rows hide 'For ...' subtitle")
check(modal.listScrollTrack:IsShown(), "Buying List scrollbar visible for 10 items (> 8 visible)")
local firstIdxBefore = modal.rows[1]._itemIndex
modal.SetListScrollOffset(2)
check(modal.GetListScrollOffset() == 2 and modal.rows[1]._itemIndex == firstIdxBefore + 2,
	"Buying List scrolls cleanly via offset")
modal.SetListScrollOffset(0)

-- 8f. All Cart Destinations: NO "Crafting Order" pills, visible scrollbar when > 5 goals, and clickable filtering!
local allDests = cb.GetAllDestinations()
check(#allDests == 8, "GetAllDestinations returns all 8 destinations (no cap), got " .. #allDests)
check(modal.treeDestRows[1].tagPill == nil, "All Cart Destinations have NO 'Crafting Order' source pills")
check(modal.treeDestRows[1].progFs:GetText():find("1/1", 1, true) ~= nil, "Destination 1 shows clean bought progress 1/1")
check(modal.destScrollTrack:IsShown(), "All Cart Destinations scrollbar visible for 8 goals (> 5 visible)")
local firstDestBefore = modal.treeDestRows[1]._destKey
modal.SetDestScrollOffset(2)
check(modal.GetDestScrollOffset() == 2 and modal.treeDestRows[1]._destKey ~= firstDestBefore,
	"All Cart Destinations scrolls cleanly via offset")
modal.SetDestScrollOffset(0)

-- Click Craft Goal 7 (which has 2 reagents: Reagent 7 and Reagent 9)
modal.SetDestScrollOffset(3) -- brings Craft Goal 7 into visible slots (goals 4,5,6,7,8 -> slot 4)
local clickedGoal7 = false
for _, dr in ipairs(modal.treeDestRows) do
	if dr:IsShown() and dr._destKey == "Craft Goal 7" then
		dr:Click("LeftButton")
		clickedGoal7 = true
		break
	end
end
check(clickedGoal7 == true, "Found and clicked Craft Goal 7 in scrolled Destinations list")
check(cb.GetDestinationFilter() == "Craft Goal 7", "Clicking destination activates destination filter")
check(modal.filterBar:IsShown() and modal.filterFs:GetText():find("Craft Goal 7", 1, true) ~= nil,
	"Active destination filter bar shown above Buying List")
local visFiltered = cb.GetVisibleItems()
check(#visFiltered == 2 and visFiltered[1].item.itemID == 50007 and visFiltered[2].item.itemID == 50009,
	"Buying List filtered strictly to Craft Goal 7's 2 reagents")
check(modal.rows[1]:IsShown() and modal.rows[2]:IsShown() and not modal.rows[3]:IsShown(),
	"Only 2 filtered rows rendered in Buying List")

-- Click Clear button to restore all items
modal.filterClearBtn:Click("LeftButton")
check(cb.GetDestinationFilter() == nil, "Clear button removes destination filter")
check(not modal.filterBar:IsShown(), "Filter bar hides after clearing filter")
check(#cb.GetVisibleItems() == 10, "All 10 items restored after clearing destination filter")

-- Clicking same destination twice toggles filter ON then OFF
modal.SetDestScrollOffset(0)
modal.treeDestRows[2]:Click("LeftButton")
check(cb.GetDestinationFilter() == "Craft Goal 2", "Click 1 selects Craft Goal 2 filter")
modal.treeDestRows[2]:Click("LeftButton")
check(cb.GetDestinationFilter() == nil, "Click 2 on active destination toggles filter back to All")

-- 9. Compact Proposal B: Buy-Cap Thermometer Price Gauge + OVER! row badge
check(modal.capGauge and not modal.capGauge:IsShown(), "Non-cap cart hides thermometer capGauge")
check(modal.spotlightCard:GetHeight() == 156, "Non-cap cart keeps 156px Spotlight height, got " .. tostring(modal.spotlightCard:GetHeight()))

app.exitAHBuyingMode(false)

local capRows = {
	{
		name = "Heavy Blasting Powder",
		qty = 20,
		itemID = 50101,
		ahUnitPrice = 310,
		maxBuyUnit = 395,
		breakEvenUnit = 436,
		categoryName = "Heavy Dynamite",
		targetName = "Heavy Dynamite",
		targetItemID = 4378,
		sourceKind = "craft_order",
		sourceLabel = "Crafting Order",
	},
	{
		name = "Solid Stone",
		qty = 40,
		itemID = 50102,
		ahUnitPrice = 350,
		maxBuyUnit = 395,
		breakEvenUnit = 436,
		categoryName = "Solid Dynamite",
		targetName = "Solid Dynamite",
		targetItemID = 10507,
		sourceKind = "craft_order",
		sourceLabel = "Crafting Order",
	},
}
mockLiveCommodity[50101] = { { unitPrice = 310, quantity = 40 } } -- safe (85c under 395c cap)
mockLiveCommodity[50102] = { { unitPrice = 420, quantity = 40 } } -- over cap (+25c over 395c cap)

local capOk = app.sendShoppingRowsToBuyer(capRows, "Vendor Crafter Plan")
check(capOk == true, "Capped cart loaded into AH Trade Strip")
check(modal.capGauge and modal.capGauge:IsShown(), "Capped cart reveals thermometer capGauge when AH open")
check(modal.spotlightCard:GetHeight() == 182, "Capped cart expands Spotlight height to 182px, got " .. tostring(modal.spotlightCard:GetHeight()))
check(not modal.capLivePin:IsShown(), "Live AH needle hidden before commodity scan returns")
check(stripColors(modal.capLeftFs:GetText()):find("MAX BUY", 1, true) ~= nil,
	"Cap gauge left label shows MAX BUY threshold, got: " .. stripColors(modal.capLeftFs:GetText()))

-- Item 1 live scan below cap: safe green margin + needle < 80%
ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 50101)
check(modal.capLivePin:IsShown(), "Safe item reveals live AH needle on thermometer")
check(type(modal.capGauge._liveFrac) == "number" and modal.capGauge._liveFrac < 0.80,
	"Safe item positions live AH needle left of 80% cap tick, got " .. tostring(modal.capGauge._liveFrac))
local capSafeRight = stripColors(modal.capRightFs:GetText())
check(capSafeRight:find("85c", 1, true) ~= nil and capSafeRight:find("left", 1, true) ~= nil,
	"Safe item right label shows 85c left headroom, got: " .. capSafeRight)

-- Item 2 live scan above cap: STOP warning + needle > 80% + OVER! row pill
cb.SelectItem(2)
ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 50102)
check(modal.capLivePin:IsShown(), "Over-cap item reveals live AH needle on thermometer")
check(type(modal.capGauge._liveFrac) == "number" and modal.capGauge._liveFrac > 0.80,
	"Over-cap item positions live AH needle right of 80% cap tick, got " .. tostring(modal.capGauge._liveFrac))
local capOverRight = stripColors(modal.capRightFs:GetText())
check(capOverRight:find("STOP", 1, true) ~= nil and capOverRight:find("25c", 1, true) ~= nil,
	"Over-cap item right label shows STOP +25c over, got: " .. capOverRight)
check(stripColors(modal.rows[2].statusPill.fs:GetText()) == "OVER!",
	"Over-cap Buying List row pill shows OVER!, got: " .. stripColors(modal.rows[2].statusPill.fs:GetText()))

-- Repaint across Goblin skin, Standard Dark, and Standard Light without errors
if ns.Theme and ns.Theme.SetSkin and ns.Theme.SetMode then
	ns.Theme.SetSkin("goblin")
	modal.Render()
	check(modal.capGauge:IsShown() and stripColors(modal.rows[2].statusPill.fs:GetText()) == "OVER!",
		"Goblin skin repaints thermometer gauge and OVER! badge cleanly")
	ns.Theme.SetSkin("standard")
	ns.Theme.SetMode("dark")
	modal.Render()
	check(modal.capGauge:IsShown(), "Standard Dark repaints thermometer gauge cleanly")
	ns.Theme.SetMode("light")
	modal.Render()
	check(modal.capGauge:IsShown() and stripColors(modal.rows[2].statusPill.fs:GetText()) == "OVER!",
		"Standard Light repaints thermometer gauge and OVER! badge cleanly")
	ns.Theme.SetMode("dark")
	modal.Render()
end

app.exitAHBuyingMode(false)

-- Restore mocks from V1-V3 AH Buyer suite
app.searchAH = origSearchAH
if _G.C_Timer and origAfter then _G.C_Timer.After = origAfter end

---------------------------------------------------------------------------------------------------
-- 10. 4-Stage OrderFlow Engine Suite (AH -> Vendor -> Collect Owned -> Crafting Task List)
---------------------------------------------------------------------------------------------------
local of = app.orderFlow
check(of ~= nil and of == ns.MarketScan.OrderFlow, "app.orderFlow / ns.MarketScan.OrderFlow exposed")

-- Track CastSpellByName to guarantee zero-taint compliance (must NEVER be invoked)
local origCastSpellByName = _G.CastSpellByName
local castSpellCalled = false
_G.CastSpellByName = function() castSpellCalled = true end

-- Save globals we mock for Stages 2-4
local origCContainer = _G.C_Container
local origGetMerchantNumItems = _G.GetMerchantNumItems
local origGetMerchantItemID = _G.GetMerchantItemID
local origGetMerchantItemInfo = _G.GetMerchantItemInfo
local origGetMerchantItemMaxStack = _G.GetMerchantItemMaxStack
local origBuyMerchantItem = _G.BuyMerchantItem
local origGetMoney = _G.GetMoney
local origMerchantFrame = _G.MerchantFrame
local origBankFrame = _G.BankFrame
local origMailFrame = _G.MailFrame
local origTradeSkillFrame = _G.TradeSkillFrame
local origCraftFrame = _G.CraftFrame
local origProfessionsFrame = _G.ProfessionsFrame
local origCTradeSkillUI = _G.C_TradeSkillUI
local origGetInboxNumItems = _G.GetInboxNumItems
local origGetInboxHeaderInfo = _G.GetInboxHeaderInfo
local origGetInboxItem = _G.GetInboxItem
local origGetInboxItemLink = _G.GetInboxItemLink
local origTakeInboxItem = _G.TakeInboxItem
local origClearCursor = _G.ClearCursor
local origGetTradeSkillLine = _G.GetTradeSkillLine
local origGetNumTradeSkills = _G.GetNumTradeSkills
local origGetTradeSkillInfo = _G.GetTradeSkillInfo
local origGetTradeSkillRecipeLink = _G.GetTradeSkillRecipeLink
local origSelectTradeSkill = _G.SelectTradeSkill
local origTradeSkillFrameSetSel = _G.TradeSkillFrame_SetSelection
local origDoTradeSkill = _G.DoTradeSkill
local origGetCraftDisplaySkillLine = _G.GetCraftDisplaySkillLine
local origGetNumCrafts = _G.GetNumCrafts
local origGetCraftInfo = _G.GetCraftInfo
local origGetCraftRecipeLink = _G.GetCraftRecipeLink
local origSelectCraft = _G.SelectCraft
local origCraftFrameSetSel = _G.CraftFrame_SetSelection
local origDoCraft = _G.DoCraft
local origIsForeignTS = ns.IsForeignTradeSkill
local origGetBagCountByID = app.getBagCountByID

-- Reusable live bag + bank + container mock
local mockBags = { [0] = {}, [1] = {} }
local mockBank = { [-1] = {}, [5] = {} }
local mockBagMaxSlots = { [0] = 4, [1] = 4 }
local mockBankMaxSlots = { [-1] = 6, [5] = 4 }
local bankUseCalls, bankSplitCalls, bankPickupCalls, cursorClears = {}, {}, {}, 0

local function setBagItem(bag, slot, itemID, qty)
	if itemID and qty and qty > 0 then
		mockBags[bag][slot] = { itemID = itemID, stackCount = qty, isLocked = false }
	else
		mockBags[bag][slot] = nil
	end
end

local function setBankItem(bag, slot, itemID, qty, locked)
	if itemID and qty and qty > 0 then
		mockBank[bag][slot] = { itemID = itemID, stackCount = qty, isLocked = locked == true }
	else
		mockBank[bag][slot] = nil
	end
end

local function getMockBagQty(itemID)
	local sum = 0
	for b = 0, 1 do
		for s = 1, mockBagMaxSlots[b] do
			local it = mockBags[b][s]
			if it and it.itemID == itemID then sum = sum + it.stackCount end
		end
	end
	return sum
end

local function addMockBagQty(itemID, delta)
	if delta <= 0 then return end
	for b = 0, 1 do
		for s = 1, mockBagMaxSlots[b] do
			local it = mockBags[b][s]
			if it and it.itemID == itemID then
				it.stackCount = it.stackCount + delta
				return
			end
		end
	end
	for b = 0, 1 do
		for s = 1, mockBagMaxSlots[b] do
			if not mockBags[b][s] then
				mockBags[b][s] = { itemID = itemID, stackCount = delta, isLocked = false }
				return
			end
		end
	end
end

app.getBagCountByID = nil -- exercise live C_Container bag scanner directly
_G.C_Container = {
	GetContainerNumSlots = function(b)
		if mockBags[b] then return mockBagMaxSlots[b] or 0 end
		if mockBank[b] then return mockBankMaxSlots[b] or 0 end
		return 0
	end,
	GetContainerItemInfo = function(b, s)
		if mockBags[b] then return mockBags[b][s] end
		if mockBank[b] then return mockBank[b][s] end
		return nil
	end,
	GetContainerNumFreeSlots = function(b)
		if not mockBags[b] then return 0, 0 end
		local free = 0
		for s = 1, mockBagMaxSlots[b] do
			if not mockBags[b][s] then free = free + 1 end
		end
		return free, 0
	end,
	UseContainerItem = function(b, s)
		bankUseCalls[#bankUseCalls + 1] = { bag = b, slot = s }
		local entry = mockBank[b] and mockBank[b][s]
		if entry then
			addMockBagQty(entry.itemID, entry.stackCount)
			mockBank[b][s] = nil
		end
	end,
	SplitContainerItem = function(b, s, qty)
		bankSplitCalls[#bankSplitCalls + 1] = { bag = b, slot = s, qty = qty }
		local entry = mockBank[b] and mockBank[b][s]
		if entry and entry.stackCount >= qty then
			entry.stackCount = entry.stackCount - qty
			if entry.stackCount <= 0 then mockBank[b][s] = nil end
			_G._mmSplitPayload = { itemID = entry.itemID, stackCount = qty }
		end
	end,
	PickupContainerItem = function(b, s)
		bankPickupCalls[#bankPickupCalls + 1] = { bag = b, slot = s }
		if _G._mmSplitPayload and mockBags[b] and not mockBags[b][s] then
			mockBags[b][s] = { itemID = _G._mmSplitPayload.itemID, stackCount = _G._mmSplitPayload.stackCount, isLocked = false }
			_G._mmSplitPayload = nil
		end
	end,
}
_G.ClearCursor = function() cursorClears = cursorClears + 1 end

-- Mock frames for Vendor / Bank / Mail / TradeSkill / Craft / Professions
local function makeSimpleFrame(name)
	local f = { _name = name, _shown = false }
	function f:Show() self._shown = true end
	function f:Hide() self._shown = false end
	function f:IsShown() return self._shown end
	return f
end
_G.MerchantFrame = makeSimpleFrame("MerchantFrame")
_G.BankFrame = makeSimpleFrame("BankFrame")
_G.MailFrame = makeSimpleFrame("MailFrame")
_G.TradeSkillFrame = makeSimpleFrame("TradeSkillFrame")
_G.CraftFrame = makeSimpleFrame("CraftFrame")
_G.ProfessionsFrame = makeSimpleFrame("ProfessionsFrame")
_G.AuctionHouseFrame:Hide()

-- 9a. Unified 4-stage extraction from mixed hierarchical shopping rows
--     Includes: 2-level nested Sub-Craft (Depth 2 -> Depth 1 -> Main Order),
--               split row (ownedUsed > 0 AND qty > 0), vendor items, AH items,
--               and a second Main Order for cross-stage destination filtering.
setBagItem(0, 1, 70001, 4) -- 4x Owned Herb already in bags
local mixedRows = {
	-- Main Order 1: Greater Fire Elixir (Alchemy, spell 90010, Depth 0)
	{
		isMainRow = true, indent = 0, mainGroupKey = "grp:fire",
		name = "Greater Fire Elixir", itemID = 70100, spellID = 90010, prof = "alchemy",
		qty = 2, sourceKind = "craft_order", sourceLabel = "Craft Order",
		reagents = { { itemID = 70090, qty = 1 }, { itemID = 70010, qty = 5 } },
	},
	-- Depth 1 Sub-Craft: Refined Fire Oil (Alchemy, spell 90005)
	{
		isMainRow = false, indent = 1, mainGroupKey = "grp:fire", isSubBranchRoot = true, subGroupKey = "grp:fire:sub:1",
		name = "Refined Fire Oil", itemID = 70090, spellID = 90005, craftProf = "alchemy",
		qty = 2, makeMyself = true, categoryName = "Greater Fire Elixir",
		sourceKind = "craft_order", sourceLabel = "Craft Order",
		reagents = { { itemID = 70080, qty = 2 }, { itemID = 70001, qty = 5 } },
	},
	-- Depth 2 Sub-Craft: Smelted Ember Core (Mining, spell 90001, deepest!)
	{
		isMainRow = false, indent = 2, mainGroupKey = "grp:fire", isSubRow = true, parentSubName = "Refined Fire Oil",
		name = "Smelted Ember Core", itemID = 70080, spellID = 90001, craftProf = "mining",
		qty = 4, makeMyself = true, categoryName = "Greater Fire Elixir",
		sourceKind = "craft_order", sourceLabel = "Craft Order",
		reagents = { { itemID = 70002, qty = 1 } },
	},
	-- AH Leaf under Depth 2 Sub-Craft: Raw Ember Ore (item 70002)
	{
		isMainRow = false, indent = 3, mainGroupKey = "grp:fire", isSubRow = true, parentSubName = "Smelted Ember Core",
		name = "Raw Ember Ore", itemID = 70002, qty = 4, ahUnitPrice = 250,
		categoryName = "Greater Fire Elixir", sourceKind = "craft_order", sourceLabel = "Craft Order",
	},
	-- Split Row: Owned Herb (item 70001) -> 10 ownedUsed (4 bags + 3 bank + 2 mail + 1 alt) AND 6 AH qty!
	{
		isMainRow = false, indent = 2, mainGroupKey = "grp:fire", isSubRow = true, parentSubName = "Refined Fire Oil",
		name = "Sunfire Herb", itemID = 70001, qty = 6, ownedUsed = 10, ahUnitPrice = 500,
		categoryName = "Greater Fire Elixir", sourceKind = "craft_order", sourceLabel = "Craft Order",
	},
	-- Vendor Leaf 1: Crystal Vial (item 70010, qty 45 -> tests maxStack=20 chunking!)
	{
		isMainRow = false, indent = 1, mainGroupKey = "grp:fire",
		name = "Crystal Vial", itemID = 70010, qty = 45, isVendor = true, vendorUnitPrice = 50,
		categoryName = "Greater Fire Elixir", sourceKind = "craft_order", sourceLabel = "Craft Order",
	},
	-- Main Order 2: Enchant Bracer - Firepower (Enchanting, spell 90020, CraftFrame!)
	{
		isMainRow = true, indent = 0, mainGroupKey = "grp:ench",
		name = "Enchant Bracer - Firepower", itemID = nil, spellID = 90020, prof = "enchanting",
		qty = 1, sourceKind = "craft_order", sourceLabel = "Craft Order",
		reagents = { { itemID = 70011, qty = 7 }, { itemID = 70003, qty = 2 } },
	},
	-- Vendor Leaf 2: Pack Vial (item 70011, qty 7, vendor sells stackCount=5)
	{
		isMainRow = false, indent = 1, mainGroupKey = "grp:ench",
		name = "Enchanting Flux", itemID = 70011, qty = 7, isVendor = true, vendorUnitPrice = 100,
		categoryName = "Enchant Bracer - Firepower", sourceKind = "craft_order", sourceLabel = "Craft Order",
	},
	-- Vendor Leaf 3: Token Item (extended cost - skipped by BuyAll)
	{
		isMainRow = false, indent = 1, mainGroupKey = "grp:ench",
		name = "Token Reagent", itemID = 70012, qty = 2, isVendor = true, vendorUnitPrice = 100,
		categoryName = "Enchant Bracer - Firepower", sourceKind = "craft_order", sourceLabel = "Craft Order",
	},
	-- Vendor Leaf 4: Sold-Out Limited Item (numAvailable=0 - skipped by BuyAll)
	{
		isMainRow = false, indent = 1, mainGroupKey = "grp:ench",
		name = "Limited Pattern", itemID = 70013, qty = 1, isVendor = true, vendorUnitPrice = 500,
		categoryName = "Enchant Bracer - Firepower", sourceKind = "craft_order", sourceLabel = "Craft Order",
	},
	-- AH Leaf under Main Order 2: Arcane Dust (item 70003)
	{
		isMainRow = false, indent = 1, mainGroupKey = "grp:ench",
		name = "Arcane Dust", itemID = 70003, qty = 2, ahUnitPrice = 300,
		categoryName = "Enchant Bracer - Firepower", sourceKind = "craft_order", sourceLabel = "Craft Order",
	},
}

local counts = of.LoadFromShoppingRows(mixedRows, {
	title = "4-Stage Test Cart",
	ownershipProvider = function(itemID)
		if itemID == 70001 then
			return {
				bags = 4,
				bank = 3,
				mail = 2,
				alts = { { name = "Bankalt", location = "Bank", qty = 5 } },
			}
		end
		return { bags = getMockBagQty(itemID), bank = 0, mail = 0, alts = {} }
	end,
})

check(counts.ah == 3, "Stage 1 extracted 3 AH items (including split row qty=6), got " .. tostring(counts.ah))
check(counts.vendor == 4, "Stage 2 extracted 4 Vendor items, got " .. tostring(counts.vendor))
check(counts.collect == 4, "Stage 3 split 10x Sunfire Herb across 4 buckets (bags/bank/mail/alt), got " .. tostring(counts.collect))
check(counts.craft == 4, "Stage 4 extracted 4 Craft tasks (2 sub-crafts + 2 main orders), got " .. tostring(counts.craft))

local ofState = of.GetState()
check(of.GetActiveStage() == "ah", "Initial activeStage is ah when AH items present")
local pipe = of.GetPipelineSummary()
check(#pipe == 4 and pipe[1].key == "ah" and pipe[2].key == "collect" and pipe[3].key == "vendor" and pipe[4].key == "craft",
	"GetPipelineSummary returns all 4 Task Strip stages in canonical order (1. AH -> 2. Collect -> 3. Vendor -> 4. Craft)")
check(pipe[1].total == 3 and pipe[2].total == 4 and pipe[3].total == 4 and pipe[4].total == 4 and of.HasSellItems(),
	"Pipeline summary stage totals match extracted counts (and main output queued in MM Sell)")

-- 9b. Stage 3 Vendor Flow: NPC_PINS hint, merchant scan, maxStack chunking, BuyAll guards, BAG_UPDATE_DELAYED
check(of.GetNextIncompleteStage("ah") == "collect" and of.GetNextIncompleteStage("collect") == "vendor"
	and of.GetNextIncompleteStage("vendor") == "craft",
	"Canonical pipeline order is 1. AH -> 2. Collect -> 3. Vendor -> 4. Craft")
local pinHint, pinNpcID = of.LookupVendorHint(6270, "Alliance")
check(pinHint == "Trade Goods Vendor" and pinNpcID == nil,
	"LookupVendorHint falls back cleanly to Trade Goods Vendor when NPC_PINS is absent, got " .. tostring(pinHint))
local fallbackHint = of.LookupVendorHint(70010, "Horde")
check(fallbackHint == "Trade Goods Vendor", "LookupVendorHint falls back to Trade Goods Vendor")

of.SetActiveStage("vendor")
check(of.GetActiveStage() == "vendor", "SetActiveStage switches to vendor")
check(of.GetWaitingMessage("vendor") == "Please open a Vendor to start.", "Closed vendor waiting message exact")
local okClosedBuy, errClosedBuy = of.BuyVendorItem(1)
check(okClosedBuy == false and errClosedBuy == "vendor_closed", "BuyVendorItem refuses when vendor is closed")

local merchantBuyCalls = {}
local mockMerchantStock = {
	{ itemID = 70010, name = "Crystal Vial",    price = 50,  stackCount = 1, numAvailable = -1, maxStack = 20, hasExtendedCost = false },
	{ itemID = 70011, name = "Enchanting Flux", price = 500, stackCount = 5, numAvailable = -1, maxStack = 20, hasExtendedCost = false },
	{ itemID = 70012, name = "Token Reagent",   price = 0,   stackCount = 1, numAvailable = -1, maxStack = 20, hasExtendedCost = true  },
	{ itemID = 70013, name = "Limited Pattern", price = 500, stackCount = 1, numAvailable = 0,  maxStack = 1,  hasExtendedCost = false },
}
_G.GetMerchantNumItems = function() return #mockMerchantStock end
_G.GetMerchantItemID = function(slot) return mockMerchantStock[slot] and mockMerchantStock[slot].itemID end
_G.GetMerchantItemInfo = function(slot)
	local s = mockMerchantStock[slot]
	if not s then return nil end
	return s.name, 134400, s.price, s.stackCount, s.numAvailable, true, true, s.hasExtendedCost
end
_G.GetMerchantItemMaxStack = function(slot) return mockMerchantStock[slot] and mockMerchantStock[slot].maxStack or 20 end
_G.GetMoney = function() return 500000 end
_G.BuyMerchantItem = function(slot, qty)
	merchantBuyCalls[#merchantBuyCalls + 1] = { slot = slot, qty = qty }
	local s = mockMerchantStock[slot]
	if s then
		addMockBagQty(s.itemID, qty)
	end
end

_G.MerchantFrame:Show()
of.OnMerchantShow()
check(of.GetWaitingMessage("vendor") == nil, "Open vendor clears waiting message")
local vItems = ofState.stages.vendor.items
check(vItems[1].inStockHere == true and vItems[1].merchantSlot == 1 and vItems[1].maxStack == 20 and vItems[1].status == "in_stock",
	"MERCHANT_SHOW matches Crystal Vial slot 1 in stock")
check(vItems[2].inStockHere == true and vItems[2].stackCount == 5 and vItems[2].liveUnit == 100,
	"MERCHANT_SHOW computes liveUnit = price/stackCount (500/5 = 100c)")
check(vItems[3].hasExtendedCost == true and vItems[4].numAvailable == 0,
	"MERCHANT_SHOW captures hasExtendedCost and numAvailable=0 flags")

-- Single click BuyVendorItem on Crystal Vial (needed=45, maxStack=20) -> buys first 20-stack chunk
local okBuy1 = of.BuyVendorItem(1)
check(okBuy1 == true and #merchantBuyCalls == 1 and merchantBuyCalls[1].slot == 1 and merchantBuyCalls[1].qty == 20,
	"BuyVendorItem chunks 45 needed by maxStack=20 -> BuyMerchantItem(1, 20)")
of.OnBagUpdateDelayed()
check(vItems[1].bought == 20 and vItems[1].remaining == 25 and ofState.stages.vendor.spentCopper == 1000,
	"BAG_UPDATE_DELAYED reconciles first 20 Crystal Vials (bought=20, remaining=25, spent=1000c)")

-- BuyAllAtCurrentVendor finishes remaining 25 Crystal Vials (20 + 5) AND 7 Enchanting Flux (2 packs of 5),
-- while skipping Token Reagent (hasExtendedCost) and Limited Pattern (numAvailable == 0)!
merchantBuyCalls = {}
local bulkCount = of.BuyAllAtCurrentVendor()
check(bulkCount == 2, "BuyAllAtCurrentVendor bought 2 valid items and skipped extended-cost + sold-out, got " .. tostring(bulkCount))
check(#merchantBuyCalls == 3
	and merchantBuyCalls[1].slot == 1 and merchantBuyCalls[1].qty == 20
	and merchantBuyCalls[2].slot == 1 and merchantBuyCalls[2].qty == 5
	and merchantBuyCalls[3].slot == 2 and merchantBuyCalls[3].qty == 10,
	"BuyAllAtCurrentVendor chunked 25 -> (20, 5) and 7-pack5 -> (10 units)")
of.OnBagUpdateDelayed()
check(vItems[1].status == "done" and vItems[1].remaining == 0, "Crystal Vial completed via BAG_UPDATE_DELAYED")
check(vItems[2].status == "done" and vItems[2].remaining == 0, "Enchanting Flux completed via BAG_UPDATE_DELAYED")
check(vItems[3].remaining == 2 and vItems[4].remaining == 1, "Skipped extended-cost and sold-out items untouched")

-- Refusing direct BuyVendorItem on extended cost & sold out, then skipping them to finish Stage 2
local okExt, errExt = of.BuyVendorItem(3)
check(okExt == false and errExt == "extended_cost", "BuyVendorItem blocks hasExtendedCost item")
local okSold, errSold = of.BuyVendorItem(4)
check(okSold == false and errSold == "sold_out", "BuyVendorItem blocks numAvailable==0 sold-out item")
of.SkipVendorItem(3)
of.SkipVendorItem(4)
local vStatsDone = of.GetStageStats("vendor")
check(vStatsDone.complete == true and vStatsDone.remaining == 0, "Stage 3 Vendor complete after buying/skipping")
check(ofState.stageCompletePrompt and ofState.stageCompletePrompt.nextStage == "craft"
	and ofState.stageCompletePrompt.label == "Next: 4. Craft ->",
	"Vendor completion surfaces 'Next: 4. Craft ->' prompt while Craft pending")

_G.MerchantFrame:Hide()
of.OnMerchantClosed()
check(ofState.env.atVendor == false and vItems[3].inStockHere == false, "MERCHANT_CLOSED clears atVendor and liveVendorSlots")

-- 9c. Stage 2 Collect Owned Flow: Bags -> Mail -> Bank -> Alt, dynamic waiting plaques, Bank full+partial split, Mail + COD guard, Alt non-blocking
of.SetActiveStage("collect")
check(of.GetActiveStage() == "collect", "SetActiveStage moves to Stage 2 Collect")

local cItems = ofState.stages.collect.items
local bySrc = {}
for idx, it in ipairs(cItems) do bySrc[it.source] = { idx = idx, item = it } end
check(bySrc.bags and bySrc.bags.item.status == "done" and bySrc.bags.item.needed == 4 and bySrc.bags.item.remaining == 0,
	"In Bags bucket auto-marked done (4/4)")
check(bySrc.mail and bySrc.mail.item.needed == 2 and bySrc.mail.item.remaining == 2 and bySrc.mail.item.status == "pending",
	"In Mail bucket pending (2) before Bank")
check(bySrc.bank and bySrc.bank.item.needed == 3 and bySrc.bank.item.remaining == 3 and bySrc.bank.item.status == "pending",
	"In Bank bucket pending (3)")
check(bySrc.mail.item._order < bySrc.bank.item._order and bySrc.mail.idx < bySrc.bank.idx,
	"Mail bucket allocated and ordered strictly before Bank bucket (Inventory > Mail > Bank)")
check(bySrc.alt and bySrc.alt.item.status == "alt_info" and bySrc.alt.item.altLabel == "On Alt: Bankalt (Bank 5x)",
	"On Alt bucket passive alt_info with exact label including alt count, got: " .. tostring(bySrc.alt and bySrc.alt.item.altLabel))
check(of.GetCollectWaitingMessage() == "Please open Mailbox or Bank to start.",
	"Both Mail and Bank pending -> 'Please open Mailbox or Bank to start.'")

-- Open Bank with a stack of 10 Sunfire Herb in BANK_CONTAINER (-1) slot 1 (needs 3 -> partial SplitContainerItem!)
setBankItem(-1, 1, 70001, 10, false)
_G.BankFrame:Show()
of.OnBankShow()
check(of.GetCollectWaitingMessage() == nil, "Opening Bank clears Collect waiting message")
-- Re-index after sort
bySrc = {}
for idx, it in ipairs(ofState.stages.collect.items) do bySrc[it.source] = { idx = idx, item = it } end
check(bySrc.bank.item.availableHere == 10 and bySrc.bank.item.status == "ready",
	"BANKFRAME_OPENED scans BANK_CONTAINER(-1) and marks bank item ready (10 available)")

-- Test bags-full guard on partial split
for b = 0, 1 do
	for s = 1, mockBagMaxSlots[b] do
		if not mockBags[b][s] then setBagItem(b, s, 99999, 1) end
	end
end
local okFull, errFull = of.WithdrawFromBank(bySrc.bank.idx)
check(okFull == false and errFull == "bags_full" and ofState.notice == "Bags full - free 1 slot to split stack.",
	"Partial bank split guards against full bags cleanly")

-- Free 1 bag slot -> partial stack split uses ClearCursor + SplitContainerItem + PickupContainerItem!
setBagItem(1, 4, nil, nil)
bankSplitCalls, bankPickupCalls, cursorClears = {}, {}, 0
local okSplit = of.WithdrawFromBank(bySrc.bank.idx)
check(okSplit == true and cursorClears == 1 and #bankSplitCalls == 1 and bankSplitCalls[1].qty == 3 and #bankPickupCalls == 1,
	"Partial bank withdrawal calls ClearCursor + SplitContainerItem(3) + PickupContainerItem")
of.OnBagUpdateDelayed()
check(bySrc.bank.item.collected == 3 and bySrc.bank.item.remaining == 0 and bySrc.bank.item.status == "done",
	"BAG_UPDATE_DELAYED completes bank withdrawal (3/3)")
for b = 0, 1 do
	for s = 1, mockBagMaxSlots[b] do
		if mockBags[b][s] and mockBags[b][s].itemID == 99999 then setBagItem(b, s, nil, nil) end
	end
end

-- Test full-stack UseContainerItem path on a dedicated bank item
of.OnBankClosed()
_G.BankFrame:Hide()
check(of.GetCollectWaitingMessage() == "Please open Mailbox to start.",
	"After Bank done with Mail pending -> 'Please open Mailbox to start.'")

-- Open Mailbox: mail #1 is COD (codAmount = 5000 -> MUST BE SKIPPED!), mail #2 is safe (2x item 70001)
local mailTakeCalls = {}
local mockInbox = {
	{ sender = "Scammer", subject = "COD Trap", cod = 5000, hasItem = 1, attach = { [1] = { name = "Sunfire Herb", itemID = 70001, count = 2 } } },
	{ sender = "Auction", subject = "Won",      cod = 0,    hasItem = 1, attach = { [1] = { name = "Sunfire Herb", itemID = 70001, count = 2 } } },
}
_G.GetInboxNumItems = function() return #mockInbox end
_G.GetInboxHeaderInfo = function(idx)
	local m = mockInbox[idx]
	if not m then return nil end
	return nil, nil, m.sender, m.subject, 0, m.cod, 30, m.hasItem
end
_G.GetInboxItem = function(mailIdx, attachIdx)
	local m = mockInbox[mailIdx]
	local a = m and m.attach and m.attach[attachIdx]
	if not a then return nil end
	return a.name, a.itemID, 134400, a.count, 1, true
end
_G.GetInboxItemLink = function(mailIdx, attachIdx)
	local m = mockInbox[mailIdx]
	local a = m and m.attach and m.attach[attachIdx]
	if not a then return nil end
	return "|cffffffff|Hitem:" .. tostring(a.itemID) .. "::::::::60:::::|h[" .. a.name .. "]|h|r"
end
_G.TakeInboxItem = function(mailIdx, attachIdx)
	mailTakeCalls[#mailTakeCalls + 1] = { mailIdx = mailIdx, attachIdx = attachIdx }
	local m = mockInbox[mailIdx]
	local a = m and m.attach and m.attach[attachIdx]
	if a then
		addMockBagQty(a.itemID, a.count)
		m.attach[attachIdx] = nil
	end
end

_G.MailFrame:Show()
of.OnMailShow()
bySrc = {}
for idx, it in ipairs(ofState.stages.collect.items) do bySrc[it.source] = { idx = idx, item = it } end
check(bySrc.mail.item.availableHere == 2 and bySrc.mail.item.status == "ready",
	"MAIL_SHOW ignores COD mail #1 and finds 2x Sunfire Herb in safe mail #2")
local okMail = of.CollectFromMail(bySrc.mail.idx)
check(okMail == true and #mailTakeCalls == 1 and mailTakeCalls[1].mailIdx == 2 and mailTakeCalls[1].attachIdx == 1,
	"CollectFromMail invokes TakeInboxItem strictly on non-COD mail #2 (never COD mail #1)")
of.OnBagUpdateDelayed()
check(bySrc.mail.item.collected == 2 and bySrc.mail.item.remaining == 0 and bySrc.mail.item.status == "done",
	"BAG_UPDATE_DELAYED completes mail collection (2/2)")

-- Verify On Alt item keeps Stage 2 complete=false until resolved, while actionableRemaining == 0
local cStatsDone = of.GetStageStats("collect")
check(cStatsDone.actionableRemaining == 0 and cStatsDone.complete == false and cStatsDone.altCount == 1,
	"Stage 2 Collect keeps complete=false while On Alt items remain (altCount=1, actionableRemaining=0)")
check(ofState.stageCompletePrompt == nil,
	"Stage 2 does not prematurely prompt completion while On Alt items are still outstanding")

_G.MailFrame:Hide()
of.OnMailClosed()

-- 9d. Stage 4 Crafting Task List: Bottom-up topo sort, TradeSkillFrame + CraftFrame + C_TradeSkillUI,
--     foreign-skill guard, bag readiness, UNIT_SPELLCAST_SUCCEEDED auto-progress & auto-advance
local advCraft = of.AdvanceToNextStage()
check(advCraft == "craft" and of.GetActiveStage() == "craft", "AdvanceToNextStage moves collect -> craft")

local tasks = ofState.stages.craft.tasks
check(#tasks == 4, "Stage 4 has 4 sorted craft tasks")
-- Strict bottom-up topological order:
-- 1) Depth 2 SUB-CRAFT: Smelted Ember Core (mining, spell 90001)
-- 2) Depth 1 SUB-CRAFT: Refined Fire Oil (alchemy, spell 90005)
-- 3) Depth 0 MAIN ORDER: Greater Fire Elixir (alchemy, spell 90010) OR Enchant Bracer (enchanting, spell 90020)
check(tasks[1].spellID == 90001 and tasks[1].isSubCraft == true and tasks[1].depth == 2 and tasks[1].profBadge == "MINE",
	"Task 1 is deepest Depth-2 SUB-CRAFT Smelted Ember Core (MINE)")
check(tasks[2].spellID == 90005 and tasks[2].isSubCraft == true and tasks[2].depth == 1 and tasks[2].profBadge == "ALCH",
	"Task 2 is Depth-1 SUB-CRAFT Refined Fire Oil (ALCH)")
-- Greater Fire Elixir must strictly follow Refined Fire Oil
local fireElixirIdx, enchBracerIdx = nil, nil
for i, t in ipairs(tasks) do
	if t.spellID == 90010 then fireElixirIdx = i end
	if t.spellID == 90020 then enchBracerIdx = i end
end
check(fireElixirIdx and fireElixirIdx > 2 and tasks[fireElixirIdx].tier == "main_order",
	"Main Order Greater Fire Elixir sorted strictly after its sub-crafts")
check(enchBracerIdx and enchBracerIdx > 2 and tasks[enchBracerIdx].profBadge == "ENCH",
	"Main Order Enchant Bracer sorted after sub-crafts with ENCH badge")

-- Closed profession waiting message & zero CastSpellByName calls
check(of.GetWaitingMessage("craft") == "Please open Mining to start.",
	"Closed profession shows 'Please open Mining to start.'")
local okClosedCraft, errClosedCraft = of.CraftActiveTask(1)
check(okClosedCraft == false and errClosedCraft == "wrong_profession" and castSpellCalled == false,
	"CraftActiveTask refuses when profession closed and never calls CastSpellByName")

-- Classic TradeSkillFrame: Smelting -> mining, foreign-skill guard, SelectTradeSkill + DoTradeSkill
local tsSelCalls, tsDoCalls = {}, {}
local mockTSSkillLine = "Smelting"
local mockTSList = {
	{ name = "Smelting", sType = "header" },
	{ name = "Smelted Ember Core", sType = "optimal", spellID = 90001 },
	{ name = "Refined Fire Oil", sType = "optimal", spellID = 90005 },
	{ name = "Greater Fire Elixir", sType = "optimal", spellID = 90010 },
}
_G.C_TradeSkillUI = { GetBaseProfessionInfo = function() return nil end, GetRecipeInfo = function() return nil end }
_G.GetTradeSkillLine = function() return mockTSSkillLine, 300, 300 end
_G.GetNumTradeSkills = function() return #mockTSList end
_G.GetTradeSkillInfo = function(i) local r = mockTSList[i]; return r and r.name, r and r.sType end
_G.GetTradeSkillRecipeLink = function(i)
	local r = mockTSList[i]
	return r and r.spellID and ("|cffffd000|Henchant:" .. tostring(r.spellID) .. "|h[" .. r.name .. "]|h|r") or nil
end
_G.SelectTradeSkill = function(i) tsSelCalls[#tsSelCalls + 1] = i end
_G.TradeSkillFrame_SetSelection = function(i) tsSelCalls[#tsSelCalls + 1] = "set:" .. tostring(i) end
_G.DoTradeSkill = function(i, qty) tsDoCalls[#tsDoCalls + 1] = { index = i, qty = qty } end

-- Foreign TradeSkill rejection
ns.IsForeignTradeSkill = function() return true end
_G.TradeSkillFrame:Show()
check(of.GetOpenProfession() == nil, "GetOpenProfession rejects foreign/linked trade skill window")
ns.IsForeignTradeSkill = function() return false end

of.OnTradeSkillShow()
local openPK, openPF = of.GetOpenProfession()
check(openPK == "mining" and openPF == "TradeSkillFrame", "Smelting maps to mining on TradeSkillFrame")
check(of.GetWaitingMessage("craft") == nil, "Matching profession clears waiting message")

-- Missing reagents check before putting Raw Ember Ore (70002) in bags
local r0 = of.ComputeTaskReadiness(tasks[1])
check(r0.matsReadyCount == 0 and r0.canCraftNow == 0, "Zero Raw Ember Ore in bags -> canCraftNow = 0")
local okNoMats, errNoMats = of.CraftActiveTask(1)
check(okNoMats == false and errNoMats == "missing_reagents", "CraftActiveTask refuses when reagents missing")

-- Put 4x Raw Ember Ore (70002) into bags -> readiness jumps to 4/4!
setBagItem(0, 2, 70002, 4)
of.OnBagUpdateDelayed()
local r1 = of.ComputeTaskReadiness(tasks[1])
check(r1.matsReadyCount == 1 and r1.totalReagents == 1 and r1.canCraftNow == 4,
	"Live bag readiness updates to matsReady=1/1, canCraftNow=4")

tsSelCalls, tsDoCalls = {}, {}
local okTSCraft = of.CraftActiveTask(1)
check(okTSCraft == true and #tsDoCalls == 1 and tsDoCalls[1].index == 2 and tsDoCalls[1].qty == 4,
	"CraftActiveTask executes SelectTradeSkill + DoTradeSkill(2, 4)")
check(tsSelCalls[1] == 2 and tsSelCalls[2] == "set:2", "TradeSkillFrame selection synced before DoTradeSkill")

-- Non-player UNIT_SPELLCAST_SUCCEEDED ignored; 4 player casts complete Task 1 and advance to Task 2
check(of.OnSpellcastSucceeded("party1", 90001) == false, "Non-player UNIT_SPELLCAST_SUCCEEDED ignored")
check(of.OnSpellcastSucceeded("player", 90001) == true and tasks[1].completedCrafts == 1 and tasks[1].remainingCrafts == 3,
	"Player spellcast #1 decrements remainingCrafts to 3")
of.OnSpellcastSucceeded("player", 90001)
of.OnSpellcastSucceeded("player", 90001)
of.OnSpellcastSucceeded("player", 90001)
check(tasks[1].status == "done" and tasks[1].remainingCrafts == 0 and ofState.stages.craft.activeIndex == 2,
	"4th spellcast marks Task 1 done and auto-advances activeIndex to Task 2 (Refined Fire Oil)")

-- Switch to Modern ProfessionsFrame + C_TradeSkillUI for Alchemy (Tasks 2 -> 3)
_G.TradeSkillFrame:Hide()
_G.ProfessionsFrame:Show()
local modernOpenCalls, modernSelectCalls, modernCraftCalls = {}, {}, {}
_G.ProfessionsFrame.CraftingPage = {
	RecipeList = {
		SelectRecipe = function(_, info, skipScroll)
			modernSelectCalls[#modernSelectCalls + 1] = { recipeID = info and info.recipeID, skipScroll = skipScroll }
		end,
	},
}
_G.C_TradeSkillUI = {
	GetBaseProfessionInfo = function() return { professionID = 171, professionName = "Alchemy" } end,
	GetRecipeInfo = function(spID)
		if spID == 90005 or spID == 90010 then return { recipeID = spID, learned = true } end
		return nil
	end,
	OpenRecipe = function(spID) modernOpenCalls[#modernOpenCalls + 1] = spID end,
	CraftRecipe = function(spID, qty) modernCraftCalls[#modernCraftCalls + 1] = { spellID = spID, qty = qty } end,
}
-- Provide 4x Smelted Ember Core (70080) + 10x Sunfire Herb (70001) in bags for 2x Refined Fire Oil
setBagItem(0, 3, 70080, 4)
setBagItem(0, 1, 70001, 10)
of.OnTradeSkillShow()
local modPK, modPF = of.GetOpenProfession()
check(modPK == "alchemy" and modPF == "ProfessionsFrame", "C_TradeSkillUI detects Alchemy on ProfessionsFrame")
check(#modernOpenCalls == 0, "OnTradeSkillShow NEVER calls hardware-protected C_TradeSkillUI.OpenRecipe (zero Forever 16001 taint)")
check(modernSelectCalls[#modernSelectCalls] and modernSelectCalls[#modernSelectCalls].recipeID == 90005,
	"Opening Alchemy auto-selects unblocked task Refined Fire Oil (90005) via unprotected RecipeList:SelectRecipe")

local okModCraft = of.CraftActiveTask(2)
check(okModCraft == true and #modernCraftCalls == 1 and modernCraftCalls[1].spellID == 90005 and modernCraftCalls[1].qty == 2,
	"Modern ProfessionsFrame calls C_TradeSkillUI.CraftRecipe(90005, 2)")

-- Finish Refined Fire Oil (2 casts) -> auto-advances to same-profession Greater Fire Elixir (90010) via unprotected SelectRecipe!
modernOpenCalls, modernSelectCalls = {}, {}
of.OnSpellcastSucceeded("player", 90005)
of.OnSpellcastSucceeded("player", 90005)
check(tasks[2].status == "done" and ofState.stages.craft.activeIndex == fireElixirIdx,
	"Completing Refined Fire Oil auto-advances to same-profession Greater Fire Elixir")
check(#modernOpenCalls == 0, "OnSpellcastSucceeded NEVER calls hardware-protected C_TradeSkillUI.OpenRecipe")
check(modernSelectCalls[1] and modernSelectCalls[1].recipeID == 90010,
	"Auto-advance auto-highlights next same-profession recipe (90010) via unprotected RecipeList:SelectRecipe")

-- Verify hardware-click fallback when CraftingPage.RecipeList.SelectRecipe is unavailable
local savedCP = _G.ProfessionsFrame.CraftingPage
_G.ProfessionsFrame.CraftingPage = nil
modernOpenCalls = {}
of.SelectCraftRecipe(fireElixirIdx, false)
check(#modernOpenCalls == 0, "SelectCraftRecipe(idx, false) refuses to call OpenRecipe even without RecipeList")
of.SelectCraftRecipe(fireElixirIdx, true)
check(modernOpenCalls[1] == 90010, "SelectCraftRecipe(idx, true) falls back to OpenRecipe during hardware clicks")
_G.ProfessionsFrame.CraftingPage = savedCP

of.MarkCraftDone(fireElixirIdx)
check(tasks[fireElixirIdx].status == "done", "MarkCraftDone completes Greater Fire Elixir")

-- Classic CraftFrame for Enchanting (Enchant Bracer - Firepower, spell 90020)
_G.ProfessionsFrame:Hide()
_G.CraftFrame:Show()
local craftSelCalls, craftDoCalls = {}, {}
_G.GetCraftDisplaySkillLine = function() return "Enchanting", 300, 300 end
_G.GetNumCrafts = function() return 1 end
_G.GetCraftInfo = function(i) if i == 1 then return "Enchant Bracer - Firepower", nil, "optimal" end end
_G.GetCraftRecipeLink = function(i)
	if i == 1 then return "|cffffd000|Henchant:90020|h[Enchant Bracer - Firepower]|h|r" end
end
_G.SelectCraft = function(i) craftSelCalls[#craftSelCalls + 1] = i end
_G.CraftFrame_SetSelection = function(i) craftSelCalls[#craftSelCalls + 1] = "set:" .. tostring(i) end
_G.DoCraft = function(i) craftDoCalls[#craftDoCalls + 1] = i end

-- Provide reagents for Enchant Bracer (7x 70011 + 2x 70003)
setBagItem(0, 4, 70011, 7)
setBagItem(1, 1, 70003, 2)
of.OnCraftShow()
local crPK, crPF = of.GetOpenProfession()
check(crPK == "enchanting" and crPF == "CraftFrame", "CraftFrame detects Enchanting")
local okEnchCraft = of.CraftActiveTask(enchBracerIdx)
check(okEnchCraft == true and #craftDoCalls == 1 and craftDoCalls[1] == 1,
	"CraftActiveTask on CraftFrame executes SelectCraft + DoCraft(1)")
of.OnSpellcastSucceeded("player", 90020)
check(tasks[enchBracerIdx].status == "done" and of.GetStageStats("craft").complete == true,
	"Enchanting spellcast completes final Stage 4 task")
check(castSpellCalled == false, "Zero CastSpellByName calls across entire 4-stage crafting workflow")

-- 9e. Cross-Stage Destination Filter & Full-Stack Bank Withdrawal + Auto-Skip Empty Stage Check
local crossDests = of.GetAllDestinations()
check(#crossDests == 2, "GetAllDestinations aggregates 2 goals across all 4 stages, got " .. tostring(#crossDests))
of.SetDestinationFilter("Enchant Bracer - Firepower")
check(#of.GetVisibleStageEntries("ah") == 1 and of.GetVisibleStageEntries("ah")[1].item.itemID == 70003,
	"Destination filter scopes Stage 1 AH strictly to Enchant Bracer reagents")
check(#of.GetVisibleStageEntries("vendor") == 3,
	"Destination filter scopes Stage 2 Vendor strictly to Enchant Bracer vendor items")
check(#of.GetVisibleStageEntries("collect") == 0,
	"Destination filter scopes Stage 3 Collect strictly to Enchant Bracer owned items (0)")
check(#of.GetVisibleStageEntries("craft") == 1 and of.GetVisibleStageEntries("craft")[1].item.spellID == 90020,
	"Destination filter scopes Stage 4 Craft strictly to Enchant Bracer craft task")
of.SetDestinationFilter("Enchant Bracer - Firepower") -- toggle off
check(of.GetDestinationFilter() == nil and #of.GetVisibleStageEntries("craft") == 4,
	"Toggling active destination clears cross-stage filter")

-- Full-stack Bank UseContainerItem + Auto-skip empty Stage 2 (Vendor) check
mockBags = { [0] = {}, [1] = {} }
mockBank = { [-1] = {}, [5] = {} }
setBankItem(5, 2, 70055, 5, false) -- exact 5 needed -> UseContainerItem(5, 2)
local skipCounts = of.LoadFromShoppingRows({
	{ name = "AH Only Mat", itemID = 70050, qty = 2, ahUnitPrice = 100, categoryName = "Goal X" },
	{ name = "Bank Exact Mat", itemID = 70055, qty = 0, ownedUsed = 5, categoryName = "Goal X" },
}, {
	title = "Auto-Skip Test",
	ownershipProvider = function(id)
		if id == 70055 then return { bags = 0, bank = 5, mail = 0, alts = {} } end
		return { bags = 0, bank = 0, mail = 0, alts = {} }
	end,
})
check(skipCounts.ah == 1 and skipCounts.vendor == 0 and skipCounts.collect == 1 and skipCounts.craft == 0,
	"Loaded AH + Collect with empty Vendor & Craft stages")
check(of.GetNextIncompleteStage("ah") == "collect",
	"GetNextIncompleteStage auto-skips empty Stage 2 (vendor) -> Stage 3 (collect)")
cb.MarkBought(1)
check(ofState.stageCompletePrompt and ofState.stageCompletePrompt.nextStage == "collect",
	"Completing Stage 1 auto-prompts Stage 3 Collect when Stage 2 Vendor is empty")
of.AdvanceToNextStage()
bankUseCalls = {}
_G.BankFrame:Show()
of.OnBankShow()
local okFullWithdraw = of.WithdrawFromBank(1)
check(okFullWithdraw == true and #bankUseCalls == 1 and bankUseCalls[1].bag == 5 and bankUseCalls[1].slot == 2,
	"Full-stack bank withdrawal (count <= remaining) invokes UseContainerItem(5, 2)")
of.OnBagUpdateDelayed()
check(ofState.stages.collect.items[1].status == "done" and of.GetNextIncompleteStage("collect") == nil,
	"All non-empty stages complete -> GetNextIncompleteStage returns nil")

-- Restore all mocked globals cleanly
_G.CastSpellByName = origCastSpellByName
_G.C_Container = origCContainer
_G.GetMerchantNumItems = origGetMerchantNumItems
_G.GetMerchantItemID = origGetMerchantItemID
_G.GetMerchantItemInfo = origGetMerchantItemInfo
_G.GetMerchantItemMaxStack = origGetMerchantItemMaxStack
_G.BuyMerchantItem = origBuyMerchantItem
_G.GetMoney = origGetMoney
_G.MerchantFrame = origMerchantFrame
_G.BankFrame = origBankFrame
_G.MailFrame = origMailFrame
_G.TradeSkillFrame = origTradeSkillFrame
_G.CraftFrame = origCraftFrame
_G.ProfessionsFrame = origProfessionsFrame
_G.C_TradeSkillUI = origCTradeSkillUI
_G.GetInboxNumItems = origGetInboxNumItems
_G.GetInboxHeaderInfo = origGetInboxHeaderInfo
_G.GetInboxItem = origGetInboxItem
_G.GetInboxItemLink = origGetInboxItemLink
_G.TakeInboxItem = origTakeInboxItem
_G.ClearCursor = origClearCursor
_G.GetTradeSkillLine = origGetTradeSkillLine
_G.GetNumTradeSkills = origGetNumTradeSkills
_G.GetTradeSkillInfo = origGetTradeSkillInfo
_G.GetTradeSkillRecipeLink = origGetTradeSkillRecipeLink
_G.SelectTradeSkill = origSelectTradeSkill
_G.TradeSkillFrame_SetSelection = origTradeSkillFrameSetSel
_G.DoTradeSkill = origDoTradeSkill
_G.GetCraftDisplaySkillLine = origGetCraftDisplaySkillLine
_G.GetNumCrafts = origGetNumCrafts
_G.GetCraftInfo = origGetCraftInfo
_G.GetCraftRecipeLink = origGetCraftRecipeLink
_G.SelectCraft = origSelectCraft
_G.CraftFrame_SetSelection = origCraftFrameSetSel
_G.DoCraft = origDoCraft
ns.IsForeignTradeSkill = origIsForeignTS
app.getBagCountByID = origGetBagCountByID

---------------------------------------------------------------------------------------------------
-- 11. 4-Stage UI Shell, Stage Switching, Auto-Docking & WoW Event Integration Suite
---------------------------------------------------------------------------------------------------
;(function()
	check(type(app.enterOrderFlowMode) == "function", "app.enterOrderFlowMode exposed")
	check(type(app.getItemOwnershipBreakdown) == "function", "app.getItemOwnershipBreakdown exposed")
	check(modal.stageBar ~= nil, "cartBuyerModal.stageBar exposed")
	check(modal.stageBtns and modal.stageBtns.ah and modal.stageBtns.vendor and modal.stageBtns.collect and modal.stageBtns.craft,
		"cartBuyerModal.stageBtns exposes all 4 stage buttons")
	check(modal.nextStageBtn ~= nil and modal.extraBtn ~= nil, "cartBuyerModal exposes nextStageBtn and extraBtn")
	check(math.floor(modal:GetHeight() + 0.5) == 684, "4-stage Baron Trade Strip height is 684, got " .. tostring(modal:GetHeight()))

	-- Test app.getItemOwnershipBreakdown returns structured bags/bank/mail/alts table
	app.char = app.char or {}
	app.char.bank = app.char.bank or {}
	app.char.mail = app.char.mail or {}
	local origBankVal = app.char.bank["Small Flame Sac"]
	local origMailVal = app.char.mail["Small Flame Sac"]
	app.char.bank["Small Flame Sac"] = 4
	app.char.mail["Small Flame Sac"] = 2
	local ob = app.getItemOwnershipBreakdown(4402, "Small Flame Sac")
	check(type(ob) == "table" and ob.bank == 4 and ob.mail == 2 and type(ob.alts) == "table",
		"getItemOwnershipBreakdown reads bank/mail/alts breakdown")
	app.char.bank["Small Flame Sac"] = origBankVal
	app.char.mail["Small Flame Sac"] = origMailVal

	-- Setup deterministic mock frames & APIs for UI + WoW Event integration tests
	local sMF = _G.MerchantFrame
	local sBF = _G.BankFrame
	local sMLF = _G.MailFrame
	local sTSF = _G.TradeSkillFrame
	local sCF = _G.CraftFrame
	local sPF = _G.ProfessionsFrame
	local sGetMNum, sGetMID, sGetMInfo, sGetMMax, sBuyM = _G.GetMerchantNumItems, _G.GetMerchantItemID, _G.GetMerchantItemInfo, _G.GetMerchantItemMaxStack, _G.BuyMerchantItem
	local sCCont, sGetInNum, sGetInHdr, sGetInItem, sGetInLink, sTakeIn = _G.C_Container, _G.GetInboxNumItems, _G.GetInboxHeaderInfo, _G.GetInboxItem, _G.GetInboxItemLink, _G.TakeInboxItem
	local sGetTSL, sGetNTS, sGetTSI, sGetTSLink, sSelTS, sDoTS = _G.GetTradeSkillLine, _G.GetNumTradeSkills, _G.GetTradeSkillInfo, _G.GetTradeSkillRecipeLink, _G.SelectTradeSkill, _G.DoTradeSkill
	local sGetBag = app.getBagCountByID
	local sIsForeign = ns.IsForeignTradeSkill
	local sCTrade = _G.C_TradeSkillUI

	local uiMF = CreateFrame("Frame", "UIMockMerchant", UIParent); uiMF:SetSize(400, 480); uiMF:Hide()
	local uiBF = CreateFrame("Frame", "UIMockBank", UIParent); uiBF:SetSize(400, 480); uiBF:Hide()
	local uiMLF = CreateFrame("Frame", "UIMockMail", UIParent); uiMLF:SetSize(400, 480); uiMLF:Hide()
	local uiTSF = CreateFrame("Frame", "UIMockTS", UIParent); uiTSF:SetSize(420, 480); uiTSF:Hide()
	_G.MerchantFrame = uiMF
	_G.BankFrame = uiBF
	_G.MailFrame = uiMLF
	_G.TradeSkillFrame = uiTSF
	_G.CraftFrame = nil
	_G.ProfessionsFrame = nil
	_G.C_TradeSkillUI = nil
	ns.IsForeignTradeSkill = function() return false end

	local uiBags = { [71001] = 6, [71002] = 0, [71003] = 0, [71004] = 0, [71005] = 0 }
	app.getBagCountByID = function(id) return uiBags[id] or 0 end

	local uiMerchantBuyCalls = {}
	_G.GetMerchantNumItems = function() return 1 end
	_G.GetMerchantItemID = function(s) return (s == 1) and 71002 or nil end
	_G.GetMerchantItemInfo = function(s)
		if s == 1 then return "UI Crystal Vial", nil, 500, 1, -1, true, false, false end
	end
	_G.GetMerchantItemMaxStack = function() return 20 end
	_G.BuyMerchantItem = function(slot, qty)
		uiMerchantBuyCalls[#uiMerchantBuyCalls + 1] = { slot = slot, qty = qty }
		uiBags[71002] = (uiBags[71002] or 0) + qty
	end

	local uiBankUseCalls = {}
	_G.C_Container = {
		GetContainerNumSlots = function(b) return (b == -1) and 2 or 4 end,
		GetContainerItemInfo = function(b, s)
			if b == -1 and s == 1 and uiBags[71003] == 0 then
				return { itemID = 71003, stackCount = 3, isLocked = false }
			end
			return nil
		end,
		GetContainerItemID = function(b, s)
			if b == -1 and s == 1 and uiBags[71003] == 0 then return 71003 end
			return nil
		end,
		GetContainerNumFreeSlots = function() return 4, 0 end,
		UseContainerItem = function(b, s)
			uiBankUseCalls[#uiBankUseCalls + 1] = { bag = b, slot = s }
			uiBags[71003] = 3
		end,
	}

	local uiMailTakeCalls = {}
	local uiSnapperTaken = false
	_G.GetInboxNumItems = function() return 2, 2 end
	_G.GetInboxHeaderInfo = function(i)
		if i == 1 then return nil, nil, "Bankalt", "Mats", 0, 0, 10, (uiBags[71004] == 0) and 1 or 0
		elseif i == 2 then return nil, nil, "Auction House", "Auction won: UI Snapper", 0, 0, 10, uiSnapperTaken and 0 or 1 end
	end
	_G.GetInboxItem = function(m, a)
		if m == 1 and a == 1 and uiBags[71004] == 0 then return "UI Mail Herb", 71004, nil, 4
		elseif m == 2 and a == 1 and not uiSnapperTaken then return "UI Snapper", 71001, nil, 4 end
	end
	_G.GetInboxItemLink = function(m, a)
		if m == 1 and a == 1 and uiBags[71004] == 0 then return "|cffffffff|Hitem:71004::::::::60:::::::|h[UI Mail Herb]|h|r"
		elseif m == 2 and a == 1 and not uiSnapperTaken then return "|cffffffff|Hitem:71001::::::::60:::::::|h[UI Snapper]|h|r" end
	end
	_G.TakeInboxItem = function(m, a)
		uiMailTakeCalls[#uiMailTakeCalls + 1] = { mail = m, attach = a }
		if m == 1 then
			uiBags[71004] = 4
		elseif m == 2 and not uiSnapperTaken then
			uiSnapperTaken = true
			uiBags[71001] = (uiBags[71001] or 0) + 4
		end
	end

	local uiCraftCalls = {}
	_G.GetTradeSkillLine = function() return "Alchemy", 300, 300 end
	_G.GetNumTradeSkills = function() return 2 end
	_G.GetTradeSkillInfo = function(i)
		if i == 1 then return "UI Fire Oil", "optimal"
		elseif i == 2 then return "UI Fire Pot", "optimal" end
	end
	_G.GetTradeSkillRecipeLink = function(i)
		if i == 1 then return "|cffffd000|Henchant:91001|h[UI Fire Oil]|h|r"
		elseif i == 2 then return "|cffffd000|Henchant:91002|h[UI Fire Pot]|h|r" end
	end
	_G.SelectTradeSkill = function() end
	_G.DoTradeSkill = function(idx, qty)
		uiCraftCalls[#uiCraftCalls + 1] = { idx = idx, qty = qty }
	end

	_G.AuctionHouseFrame:Hide()
	MerchantMasterDB.ahBuyerExtended = false

	-- Load 4-stage pipeline through OrderFlow and enterOrderFlowMode
	local countsUI = of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "u1", name = "UI Fire Pot", itemID = 71010, spellID = 91002, prof = "alchemy", qty = 2, sourceKind = "craft_order", sourceLabel = "Crafting Order",
			reagents = { { itemID = 71005, name = "UI Fire Oil", qty = 1 }, { itemID = 71002, name = "UI Crystal Vial", qty = 1 } } },
		{ indent = 1, mainGroupKey = "u1", isSubBranchRoot = true, subGroupKey = "us1", name = "UI Fire Oil", itemID = 71005, spellID = 91001, prof = "alchemy", craftProf = "alchemy", qty = 2, makeMyself = true, categoryName = "UI Fire Pot",
			reagents = { { itemID = 71001, name = "UI Snapper", qty = 2 } } },
		{ indent = 2, isSubRow = true, mainGroupKey = "u1", subGroupKey = "us1", parentSubName = "UI Fire Oil", name = "UI Snapper", itemID = 71001, qty = 4, ahUnitPrice = 200, categoryName = "UI Fire Pot" },
		{ indent = 1, mainGroupKey = "u1", name = "UI Crystal Vial", itemID = 71002, qty = 2, isVendor = true, vendorUnitPrice = 500, categoryName = "UI Fire Pot" },
		{ indent = 1, mainGroupKey = "u1", name = "UI Bank Sac", itemID = 71003, qty = 0, ownedUsed = 3, categoryName = "UI Fire Pot" },
		{ indent = 1, mainGroupKey = "u1", name = "UI Mail Herb", itemID = 71004, qty = 0, ownedUsed = 4, categoryName = "UI Fire Pot" },
	}, {
		title = "UI 4-Stage Test",
		ownershipProvider = function(id)
			if id == 71003 then return { bags = 0, bank = 3, mail = 0, alts = {} } end
			if id == 71004 then return { bags = 0, bank = 0, mail = 4, alts = {} } end
			return { bags = uiBags[id] or 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	check(countsUI.ah == 1 and countsUI.collect == 2 and countsUI.vendor == 1 and countsUI.craft == 2,
		"UI test loaded all 4 stages (1 AH, 2 Collect, 1 Vendor, 2 Craft)")
	app.enterOrderFlowMode("ah")
	check(modal:IsShown() and modal.titleFs:GetText() == "AH TRADE STRIP", "Stage 1 opens with AH TRADE STRIP title")

	-- Complete Stage 1 -> Next Stage emerald CTA appears and advances to Stage 2 Collect
	cb.MarkBought(1)
	check(modal.nextStageBtn:IsShown() and modal.nextStageBtn:GetText():find("2. Collect", 1, true) ~= nil,
		"Stage 1 completion shows emerald Next: 2. Collect -> button")
	modal.nextStageBtn:Click("LeftButton")
	check(of.GetActiveStage() == "collect" and modal.titleFs:GetText() == "COLLECT OWNED STRIP", "Stage 2 Collect active")
	check(modal.waitingBanner:IsShown() and modal.waitingFs:GetText() == "Please open Mailbox or Bank to start.",
		"Stage 2 waiting plaque dynamically requests Mailbox or Bank")
	check(not modal.openProfBtn:IsShown(), "Secure openProfBtn stays hidden on Collect stage")

	-- MAIL_SHOW -> docks beside MailFrame, takes mail via UI click + BAG_UPDATE_DELAYED
	uiMLF:Show()
	fireEvent("MAIL_SHOW")
	local _, dockRelM = modal:GetPoint(1)
	check(dockRelM == uiMLF, "MAIL_SHOW auto-docks strip beside MailFrame")
	check(modal.spotlightCard:IsShown() and modal.buyBtn:GetText() == "Collect 1x" and modal.markBtn:GetText() == "All This Item",
		"Stage 2 Mail open shows Collect 1x and All This Item buttons")
	modal.buyBtn:Click("LeftButton")
	check(#uiMailTakeCalls == 1, "Stage 2 UI click executes TakeInboxItem")
	fireEvent("BAG_UPDATE_DELAYED")
	modal.buyBtn:Click("LeftButton")
	check(#uiMailTakeCalls == 2, "Stage 2 UI second click collects AH-bought UI Snapper from Mail")
	fireEvent("BAG_UPDATE_DELAYED")
	uiMLF:Hide()
	fireEvent("MAIL_CLOSED")
	check(modal.waitingBanner:IsShown() and modal.waitingFs:GetText() == "Please open Bank to start.",
		"After Mail done, waiting plaque narrows strictly to 'Please open Bank to start.'")

	-- BANKFRAME_OPENED -> docks beside BankFrame, withdraws via UI click + BAG_UPDATE_DELAYED -> Next: 3. Vendor ->
	uiBF:Show()
	fireEvent("BANKFRAME_OPENED")
	local _, dockRelB = modal:GetPoint(1)
	check(dockRelB == uiBF, "BANKFRAME_OPENED auto-docks strip beside BankFrame")
	check(modal.spotlightCard:IsShown() and modal.buyBtn:GetText() == "Take 1x" and modal.markBtn:GetText() == "All This Item",
		"Stage 2 Bank open shows Take 1x and All This Item buttons")
	modal.buyBtn:Click("LeftButton")
	check(#uiBankUseCalls == 1, "Stage 2 UI click executes Bank withdrawal")
	fireEvent("BAG_UPDATE_DELAYED")
	uiBF:Hide()
	fireEvent("BANKFRAME_CLOSED")
	check(of.GetStageStats("collect").complete == true, "Stage 2 Collect completes after Mail & Bank collected")
	check(modal.nextStageBtn:IsShown() and modal.nextStageBtn:GetText():find("3. Vendor", 1, true) ~= nil,
		"Stage 2 Collect completion prompts Next: 3. Vendor ->")

	-- Advance to Stage 3 Vendor: MERCHANT_SHOW docks beside MerchantFrame, buys via click + BAG_UPDATE_DELAYED
	modal.nextStageBtn:Click("LeftButton")
	check(of.GetActiveStage() == "vendor", "Clicking nextStageBtn advances cleanly to Stage 3 Vendor")
	check(modal.titleFs:GetText() == "VENDOR ORDER STRIP", "Stage 3 updates header to VENDOR ORDER STRIP")
	check(modal.waitingBanner:IsShown() and modal.waitingFs:GetText() == "Please open a Vendor to start.",
		"Stage 3 closed vendor displays strict waiting plaque")
	check(not modal.spotlightCard:IsShown(), "Stage 3 closed vendor hides Spotlight")

	uiMF:Show()
	fireEvent("MERCHANT_SHOW")
	local _, dockRelV = modal:GetPoint(1)
	check(dockRelV == uiMF, "MERCHANT_SHOW auto-docks strip beside MerchantFrame")
	check(not modal.waitingBanner:IsShown() and modal.spotlightCard:IsShown(), "MERCHANT_SHOW reveals Stage 3 Spotlight")
	check(modal.buyBtn:GetText() == "Buy from Vendor" and modal.buyBtn:IsEnabled(), "Stage 3 primary CTA is Buy from Vendor")
	modal.buyBtn:Click("LeftButton")
	check(#uiMerchantBuyCalls == 1 and uiMerchantBuyCalls[1].qty == 2, "Stage 3 UI click executes BuyMerchantItem(1, 2)")
	fireEvent("BAG_UPDATE_DELAYED")
	check(of.GetStageStats("vendor").complete == true, "BAG_UPDATE_DELAYED completes Stage 3 Vendor")
	check(modal.nextStageBtn:IsShown() and modal.nextStageBtn:GetText():find("4. Craft", 1, true) ~= nil,
		"Stage 3 Vendor completion prompts Next: 4. Craft ->")
	uiMF:Hide()
	fireEvent("MERCHANT_CLOSED")

	-- Switch to Stage 4 Craft via nextStageBtn -> Clickable 'Click to open Alchemy' SecureActionButton
	modal.stageBtns.craft:Click("LeftButton")
	check(of.GetActiveStage() == "craft" and modal.titleFs:GetText() == "CRAFTING TASK STRIP",
		"Stage 4 button switches to CRAFTING TASK STRIP")
	check(modal.waitingBanner:IsShown() and modal.waitingFs:GetText() == "Click to open Alchemy",
		"Stage 4 closed profession displays clickable 'Click to open Alchemy' waiting plaque, got " .. tostring(modal.waitingFs:GetText()))
	check(modal.openProfBtn:IsShown() and modal.openProfBtn:GetAttribute("type") == "spell"
		and modal.openProfBtn:GetAttribute("spell") == "Alchemy",
		"Secure openProfBtn configures type='spell', spell='Alchemy'")

	-- TRADE_SKILL_SHOW -> docks beside TradeSkillFrame, hides openProfBtn, shows SUB-CRAFT + ALCH + Craft 2x + Extended Reagents Drawer
	uiTSF:Show()
	fireEvent("TRADE_SKILL_SHOW")
	local _, dockRelT = modal:GetPoint(1)
	check(dockRelT == uiTSF, "TRADE_SKILL_SHOW auto-docks strip beside TradeSkillFrame")
	check(not modal.waitingBanner:IsShown() and not modal.openProfBtn:IsShown() and modal.spotlightCard:IsShown(),
		"TRADE_SKILL_SHOW hides waiting plaque/openProfBtn and reveals Stage 4 Spotlight")
	check(modal.spotTierPill:IsShown() and stripColors(modal.spotTierPill.fs:GetText()) == "SUB-CRAFT",
		"Stage 4 active sub-craft shows SUB-CRAFT badge pill")
	check(modal.spotProfPill:IsShown() and stripColors(modal.spotProfPill.fs:GetText()) == "ALCH",
		"Stage 4 active task shows ALCH profession badge pill")
	check(modal.buyBtn:GetText() == "Craft 2x" and modal.buyBtn:IsEnabled(), "Stage 4 primary CTA shows Craft 2x")

	-- Open Extended Drawer on Stage 4 -> shows CURRENT TASK REAGENTS with In Bags stock
	local compactBtnW = modal.stageBtns.craft:GetWidth()
	local compactTotalStageW = modal.stageBtns.ah:GetWidth() + modal.stageBtns.collect:GetWidth() + modal.stageBtns.vendor:GetWidth() + compactBtnW + 12
	check(compactTotalStageW <= 396 - 24, "Compact stageBar 4 pills fit cleanly inside 396px frame, got totalW=" .. tostring(compactTotalStageW))
	modal.SetExtended(true)
	local extBtnW = modal.stageBtns.craft:GetWidth()
	check(extBtnW > compactBtnW + 50, "Expanding 396->706 immediately widens stageBtns.craft (" .. tostring(compactBtnW) .. " -> " .. tostring(extBtnW) .. ")")
	check(modal.treePane:IsShown() and modal.treeChainNodes[1]:IsShown(), "Stage 4 extended drawer shows reagent card")
	check(stripColors(modal.treeChainNodes[1].subFs:GetText()):find("In Bags: 10 / 4", 1, true) ~= nil,
		"Stage 4 reagent card displays live bag stock (In Bags: 10 / 4)")
	modal.SetExtended(false)
	local reCompactBtnW = modal.stageBtns.craft:GetWidth()
	local reCompactTotalW = modal.stageBtns.ah:GetWidth() + modal.stageBtns.collect:GetWidth() + modal.stageBtns.vendor:GetWidth() + reCompactBtnW + 12
	check(reCompactTotalW <= 396 - 24 and reCompactBtnW == compactBtnW,
		"Collapsing 706->396 immediately shrinks stageBtns back inside 396px frame (no overflow), got " .. tostring(reCompactTotalW))
	modal.SetExtended(true)

	-- Click Craft 2x and fire UNIT_SPELLCAST_SUCCEEDED twice -> completes sub-craft & advances to Main Order!
	modal.buyBtn:Click("LeftButton")
	check(#uiCraftCalls == 1 and uiCraftCalls[1].idx == 1 and uiCraftCalls[1].qty == 2,
		"Stage 4 UI Craft click invokes DoTradeSkill(1, 2)")
	fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-u1", 91001)
	fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-u2", 91001)
	local crStUI = of.GetState().stages.craft
	check(crStUI.tasks[1].status == "done" and crStUI.activeIndex == 2,
		"UNIT_SPELLCAST_SUCCEEDED completes sub-craft and auto-advances to Main Order task")
	check(stripColors(modal.spotTierPill.fs:GetText()) == "MAIN ORDER",
		"Main Order task displays gold MAIN ORDER badge pill")

	-- TRADE_SKILL_CLOSE returns clickable waiting plaque cleanly when craft tasks remain
	uiTSF:Hide()
	fireEvent("TRADE_SKILL_CLOSE")
	check(modal.waitingBanner:IsShown() and modal.waitingFs:GetText() == "Click to open Alchemy"
		and modal.openProfBtn:IsShown() and modal.openProfBtn:GetAttribute("spell") == "Alchemy",
		"TRADE_SKILL_CLOSE returns Stage 4 to clickable 'Click to open Alchemy' plaque")

	-- Cleanup
	modal.SetExtended(false)
	app.exitAHBuyingMode(false)
	_G.MerchantFrame, _G.BankFrame, _G.MailFrame, _G.TradeSkillFrame, _G.CraftFrame, _G.ProfessionsFrame = sMF, sBF, sMLF, sTSF, sCF, sPF
	_G.GetMerchantNumItems, _G.GetMerchantItemID, _G.GetMerchantItemInfo, _G.GetMerchantItemMaxStack, _G.BuyMerchantItem = sGetMNum, sGetMID, sGetMInfo, sGetMMax, sBuyM
	_G.C_Container, _G.GetInboxNumItems, _G.GetInboxHeaderInfo, _G.GetInboxItem, _G.GetInboxItemLink, _G.TakeInboxItem = sCCont, sGetInNum, sGetInHdr, sGetInItem, sGetInLink, sTakeIn
	_G.GetTradeSkillLine, _G.GetNumTradeSkills, _G.GetTradeSkillInfo, _G.GetTradeSkillRecipeLink, _G.SelectTradeSkill, _G.DoTradeSkill = sGetTSL, sGetNTS, sGetTSI, sGetTSLink, sSelTS, sDoTS
	app.getBagCountByID = sGetBag
	ns.IsForeignTradeSkill = sIsForeign
	_G.C_TradeSkillUI = sCTrade
end)()

---------------------------------------------------------------------------------------------------
-- 12. Total-Time Craft Loading Bar, Forever 16001 ReagentBag, Collect Priority & Clickable Prof
---------------------------------------------------------------------------------------------------
;(function()
	check(modal.craftTimerBar ~= nil and modal.craftTimerFs ~= nil and modal.craftTimerFill ~= nil,
		"Exposes craftTimerBar, craftTimerFs, and craftTimerFill on cartBuyerModal")
	check(modal.craftFooter == nil and modal.autoCraftBtn == nil and modal.autoCraftConfirmModal == nil,
		"Auto Craft footer, button, and confirmation modal removed cleanly")
	check(_G.MerchantMasterAutoCraftBtn == nil and of.StartAutoCraft == nil and of.ContinueAutoCraft == nil,
		"Auto Craft global API and Start/ContinueAutoCraft functions removed cleanly")
	check(modal.openProfBtn ~= nil and _G.MerchantMasterOpenProfBtn == modal.openProfBtn,
		"Exposes SecureActionButtonTemplate MerchantMasterOpenProfBtn on modal")

	local sTSF = _G.TradeSkillFrame
	local sCF = _G.CraftFrame
	local sPF = _G.ProfessionsFrame
	local sCTrade = _G.C_TradeSkillUI
	local sCSpell = _G.C_Spell
	local sUnitCast = _G.UnitCastingInfo
	local sGetTime = _G.GetTime
	local sGetTSL, sGetNTS, sGetTSI, sGetTSLink, sSelTS, sDoTS = _G.GetTradeSkillLine, _G.GetNumTradeSkills, _G.GetTradeSkillInfo, _G.GetTradeSkillRecipeLink, _G.SelectTradeSkill, _G.DoTradeSkill
	local sGetBag = app.getBagCountByID
	local sIsForeign = ns.IsForeignTradeSkill
	local sCCont = _G.C_Container
	local sEnum = _G.Enum
	local sNumBags = _G.NUM_BAG_SLOTS
	local sNumTotalBags = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS

	local simNow = 1000
	_G.GetTime = function() return simNow end

	local wTSF = CreateFrame("Frame", "Wave3MockTS", UIParent); wTSF:SetSize(420, 480); wTSF:Hide()
	_G.TradeSkillFrame = wTSF
	_G.CraftFrame = nil
	_G.ProfessionsFrame = nil
	_G.C_TradeSkillUI = nil
	ns.IsForeignTradeSkill = function() return false end

	local wBags = { [6359] = 10, [3371] = 10, [6371] = 0, [4402] = 6, [3372] = 6 }
	app.getBagCountByID = function(id) return wBags[id] or 0 end

	local tsScanCount = 0
	local wCraftCalls = {}
	local wSelectedIdx = nil
	_G.GetTradeSkillLine = function() return "Alchemy", 300, 300 end
	_G.GetNumTradeSkills = function()
		tsScanCount = tsScanCount + 1
		return 2
	end
	_G.GetTradeSkillInfo = function(i)
		if i == 1 then return "Fire Oil", "optimal"
		elseif i == 2 then return "Fire Protection Potion", "optimal" end
	end
	_G.GetTradeSkillRecipeLink = function(i)
		if i == 1 then return "|cffffd000|Henchant:7837|h[Fire Oil]|h|r"
		elseif i == 2 then return "|cffffd000|Henchant:7257|h[Fire Protection Potion]|h|r" end
	end
	_G.SelectTradeSkill = function(idx) wSelectedIdx = idx end
	_G.DoTradeSkill = function(idx, qty)
		wCraftCalls[#wCraftCalls + 1] = { idx = idx, qty = qty }
	end

	-- Load 2-recipe Alchemy chain (Sub-Craft: Fire Oil qty=4 -> 2 crafts at c=2 yield, ct=5000ms; Main Order: Fire Protection Potion x2)
	MerchantMasterDB.ahBuyerExtended = false
	of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "w1", name = "Fire Protection Potion", itemID = 6049, spellID = 7257, prof = "alchemy", qty = 2, sourceKind = "craft_order", sourceLabel = "Crafting Order",
			reagents = { { itemID = 4402, name = "Small Flame Sac", qty = 1 }, { itemID = 6371, name = "Fire Oil", qty = 1 }, { itemID = 3372, name = "Leaded Vial", qty = 1 } } },
		{ indent = 1, mainGroupKey = "w1", isSubBranchRoot = true, subGroupKey = "ws1", name = "Fire Oil", itemID = 6371, spellID = 7837, prof = "alchemy", craftProf = "alchemy", qty = 4, makeMyself = true, categoryName = "Fire Protection Potion",
			reagents = { { itemID = 6359, name = "Firefin Snapper", qty = 2 }, { itemID = 3371, name = "Empty Vial", qty = 1 } } },
	}, { title = "Batch Loading Bar Craft Plan" })

	app.enterOrderFlowMode("craft")
	-- Closed Alchemy shows Click to open Alchemy with SecureActionButton spell="Alchemy"
	check(modal.waitingBanner:IsShown() and modal.waitingFs:GetText() == "Click to open Alchemy",
		"Stage 4 closed Alchemy shows 'Click to open Alchemy'")
	check(modal.openProfBtn:IsShown() and modal.openProfBtn:GetAttribute("type") == "spell"
		and modal.openProfBtn:GetAttribute("spell") == "Alchemy",
		"Closed Alchemy wires openProfBtn spell='Alchemy'")

	-- Verify Mining resolves to spell='Smelting'
	of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "m_mine", name = "Smelt Copper", itemID = 2840, spellID = 2657, prof = "mining", qty = 2, sourceKind = "craft_order", sourceLabel = "Crafting Order" },
	}, { title = "Mining Open Spell Check" })
	app.enterOrderFlowMode("craft")
	check(modal.waitingFs:GetText() == "Click to open Smelting (Mining)"
		and modal.openProfBtn:GetAttribute("spell") == "Smelting",
		"Closed Mining displays 'Click to open Smelting (Mining)' and binds spell='Smelting', got " .. tostring(modal.waitingFs:GetText()))

	-- Restore Alchemy 2-recipe batch and open Alchemy
	of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "w1", name = "Fire Protection Potion", itemID = 6049, spellID = 7257, prof = "alchemy", qty = 2, sourceKind = "craft_order", sourceLabel = "Crafting Order",
			reagents = { { itemID = 4402, name = "Small Flame Sac", qty = 1 }, { itemID = 6371, name = "Fire Oil", qty = 1 }, { itemID = 3372, name = "Leaded Vial", qty = 1 } } },
		{ indent = 1, mainGroupKey = "w1", isSubBranchRoot = true, subGroupKey = "ws1", name = "Fire Oil", itemID = 6371, spellID = 7837, prof = "alchemy", craftProf = "alchemy", qty = 4, makeMyself = true, categoryName = "Fire Protection Potion",
			reagents = { { itemID = 6359, name = "Firefin Snapper", qty = 2 }, { itemID = 3371, name = "Empty Vial", qty = 1 } } },
	}, { title = "Batch Loading Bar Craft Plan" })
	app.enterOrderFlowMode("craft")
	wTSF:Show()
	app._tsSessionScanned = false
	app._lastTradeSkillScanTime = 0
	app._lastCraftEventTime = 0
	fireEvent("TRADE_SKILL_SHOW")

	-- 1. Cast time population from Data_Recipes + C_Spell.GetSpellInfo haste override
	local crSt = of.GetState().stages.craft
	check(crSt.tasks[1] and crSt.tasks[1].castTimeMs == 5000,
		"Craft task castTimeMs populated from Data_Recipes (Fire Oil = 5000ms), got " .. tostring(crSt.tasks[1] and crSt.tasks[1].castTimeMs))
	local baseEta = of.GetTaskEtaSec(crSt.tasks[1], simNow)
	check(math.abs(baseEta - 10.0) < 0.01, "GetTaskEtaSec returns 10.0s for 2 crafts x 5000ms, got " .. tostring(baseEta))
	_G.C_Spell = {
		GetSpellInfo = function(sid)
			if sid == 7837 then return { castTime = 1500 } end
			if sid == 7257 then return { castTime = 2000 } end
			return nil
		end,
	}
	local hastedEta = of.GetTaskEtaSec(crSt.tasks[1], simNow)
	check(math.abs(hastedEta - 3.0) < 0.01, "C_Spell.GetSpellInfo haste override scales 2x 1500ms -> 3.0s, got " .. tostring(hastedEta))
	if modal.Render then modal.Render() end

	-- 2. Full-width Stage 4 Loading Bar & 7-row capacity without bottom footer
	check(modal.craftTimerBar:IsShown(), "Stage 4 shows craftTimerBar when profession is open")
	check(not modal.openProfBtn:IsShown(), "openProfBtn hides when profession is open")
	local _, _, _, trX2 = modal.craftTimerTrack:GetPoint(2)
	check(trX2 == 0, "cbCraftTimerBar track spans full width inside Spotlight (TOPRIGHT offset 0, got " .. tostring(trX2) .. ")")
	check(math.floor(modal.spotlightCard:GetHeight() + 0.5) == 182,
		"Stage 4 expands spotlightCard height to 182px for craftTimerBar, got " .. tostring(modal.spotlightCard:GetHeight()))
	check(modal.getVisCap(false, true) == 7,
		"Stage 4 visCap allows full 7 rows without Auto-Craft footer (got " .. tostring(modal.getVisCap(false, true)) .. ")")
	check(not modal.craftTimerFill:IsShown(), "craftTimerFill is hidden while idle at 0%")
	local idleTxt = modal.craftTimerFs:GetText() or ""
	check(idleTxt:find("Est. ", 1, true) ~= nil and idleTxt:find("Queue ", 1, true) ~= nil,
		"Idle craftTimerFs shows 'Est. ... | Queue ...', got: " .. tostring(idleTxt))

	-- Simulate live UNIT_SPELLCAST_START with 0.75s elapsed / 1.5s on Craft #1 of 2 (total batch = 3.0s -> taskFrac = 0.25!)
	_G.UnitCastingInfo = function(u)
		if u == "player" then
			return "Fire Oil", "Fire Oil", nil, (simNow - 0.75) * 1000, (simNow + 0.75) * 1000, true, "cast-w3-1", false, 7837
		end
	end
	fireEvent("UNIT_SPELLCAST_START", "player", "cast-w3-1", 7837)
	local midTiming = of.GetCraftTimingSummary(simNow)
	check(math.abs((midTiming.taskFrac or 0) - 0.25) < 0.02 and math.abs((midTiming.taskLeftSec or 0) - 2.25) < 0.02,
		"Total-time loading bar computes taskFrac=0.25 and taskLeftSec=2.25s mid-craft #1 (got frac=" .. tostring(midTiming.taskFrac) .. ", left=" .. tostring(midTiming.taskLeftSec) .. ")")
	check(modal.craftTimerFill:IsShown() and modal.craftTimerFill:GetWidth() >= 4,
		"UNIT_SPELLCAST_START shows craftTimerFill with positive width")
	local castTxt = modal.craftTimerFs:GetText() or ""
	check(castTxt:find("Crafting 2.2s left", 1, true) ~= nil or castTxt:find("Crafting 2.3s left", 1, true) ~= nil,
		"Mid-cast craftTimerFs shows total batch time remaining ('Crafting ~2.3s left'), got: " .. tostring(castTxt))

	-- Switching around in Craft list while Recipe #1 is crafting keeps active timer pinned ONLY to Recipe #1 and marks Row 1 pill 'CRAFTING'!
	of.SelectCraftTask(2)
	local otherTiming = of.GetCraftTimingSummary(simNow)
	check(otherTiming.isSelectedTaskCrafting == false and otherTiming.isOtherTaskCrafting == true
		and otherTiming.craftingTaskKey == crSt.tasks[1].taskKey and (otherTiming.taskFrac or 0) == 0,
		"Clicking Recipe #2 while Recipe #1 casts does NOT move active timer onto Recipe #2")
	check(not modal.craftTimerFill:IsShown() and (modal.craftTimerFs:GetText() or ""):find("Est. ", 1, true) ~= nil,
		"Selected Recipe #2 displays static Est. timer instead of moving fill from Recipe #1")
	check((modal.rows[1].cells.status:GetText() or ""):find("CRAFTING", 1, true) ~= nil
		and (modal.rows[2].cells.status:GetText() or ""):find("No Mats", 1, true) ~= nil,
		"Background crafting Recipe #1 displays 'CRAFTING' status pill while Recipe #2 displays 'No Mats', got r1="
		.. tostring(modal.rows[1].cells.status:GetText()) .. ", r2=" .. tostring(modal.rows[2].cells.status:GetText()))
	of.SelectCraftTask(1)
	check(of.GetCraftTimingSummary(simNow).isSelectedTaskCrafting == true and modal.craftTimerFill:IsShown(),
		"Selecting back to actively crafting Recipe #1 immediately resumes live timer fill")

	-- Complete Craft #1 of 2: UNIT_SPELLCAST_STOP (non-interrupted) -> SUCCEEDED bridges smoothly with ZERO flash!
	_G.UnitCastingInfo = function() return nil end
	fireEvent("UNIT_SPELLCAST_STOP", "player", "cast-w3-1", 7837)
	local stopBridgeTiming = of.GetCraftTimingSummary(simNow)
	check(modal.craftTimerFill:IsShown() and (stopBridgeTiming.taskFrac or 0) >= 0.24
		and of.GetActiveCraftingTaskKey(simNow) == crSt.tasks[1].taskKey,
		"UNIT_SPELLCAST_STOP before SUCCEEDED keeps fill visible & monotonic (no flash), got frac=" .. tostring(stopBridgeTiming.taskFrac))
	fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-w3-1", 7837)
	local after1Timing = of.GetCraftTimingSummary(simNow)
	check(math.abs((after1Timing.taskFrac or 0) - 0.50) < 0.02,
		"Between Craft #1 and #2, taskFrac remains 0.50 (does not reset to 0), got " .. tostring(after1Timing.taskFrac))
	check(modal.craftTimerFill:IsShown() and modal.craftTimerFill:GetWidth() >= 100,
		"Between crafts of a multi-craft batch, loading fill stays visible at 50% progress")

	-- After the 1.5s grace window expires idle, batch flag clears back to Ready while 50% batch fill stays intact
	simNow = simNow + 2.0
	local expiredGrace = of.ExpireCraftingBatchIfNeeded(simNow)
	check(expiredGrace == true and of.GetActiveCraftingTaskKey(simNow) == nil,
		"ExpireCraftingBatchIfNeeded clears CRAFTING status after 1.5s idle grace")
	check((modal.rows[1].cells.status:GetText() or ""):find("Ready", 1, true) ~= nil and modal.craftTimerFill:IsShown(),
		"After grace expiry, Row 1 returns to 'Ready' while 50% fill stays visible")
	wBags[6371] = 4
	fireEvent("UNIT_SPELLCAST_START", "player", "cast-w3-2", 7837)
	check((modal.rows[1].cells.status:GetText() or ""):find("CRAFTING", 1, true) ~= nil, "Craft #2 start re-activates CRAFTING pill")

	-- Finish Craft #2 -> advances cleanly to task #2 & badge count drops 2 -> 1
	check(of.GetTaskListBadgeCount and of.GetTaskListBadgeCount() == 2,
		"OrderFlow.GetTaskListBadgeCount() reports 2 before recipe 1 completes")
	fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-w3-2", 7837)
	check(of.GetTaskListBadgeCount() == 1, "GetTaskListBadgeCount drops to 1 after recipe 1 completes")
	check(wSelectedIdx == 2, "Completing recipe 1 auto-selects next recipe index (2)")

	-- Interrupted cast immediately clears CRAFTING state
	fireEvent("UNIT_SPELLCAST_START", "player", "cast-w3-int", 7257)
	check(of.GetActiveCraftingTaskKey(simNow) == crSt.tasks[2].taskKey, "Started task #2 cast activates CRAFTING")
	fireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-w3-int", 7257)
	check(of.GetActiveCraftingTaskKey(simNow) == nil and (modal.rows[2].cells.status:GetText() or ""):find("Ready", 1, true) ~= nil,
		"UNIT_SPELLCAST_INTERRUPTED clears CRAFTING status immediately")

	-- 3. Craft-Finish Lag Fix: TRADE_SKILL_UPDATE session scan guard prevents repeat full rescans
	local scansAfterShow = tsScanCount
	simNow = simNow + 10
	fireEvent("TRADE_SKILL_UPDATE")
	simNow = simNow + 10
	fireEvent("TRADE_SKILL_UPDATE")
	simNow = simNow + 10
	fireEvent("TRADE_SKILL_UPDATE")
	check(tsScanCount == scansAfterShow,
		"Repeat TRADE_SKILL_UPDATE events do not trigger redundant GetNumTradeSkills scans while session scanned (" .. tostring(scansAfterShow) .. " vs " .. tostring(tsScanCount) .. ")")

	-- TRADE_SKILL_CLOSE resets session guard, hides craftTimerBar, and restores clickable openProfBtn
	wTSF:Hide()
	fireEvent("TRADE_SKILL_CLOSE")
	check(app._tsSessionScanned == false, "TRADE_SKILL_CLOSE resets app._tsSessionScanned to false")
	check(not modal.craftTimerBar:IsShown(), "TRADE_SKILL_CLOSE hides craftTimerBar")
	check(modal.openProfBtn:IsShown() and modal.waitingFs:GetText() == "Click to open Alchemy",
		"TRADE_SKILL_CLOSE restores clickable 'Click to open Alchemy' plaque")

	-- 4. WoW: Forever 16001 ReagentBag (bag 5) + CharacterBankTab_1..9 + Collect Priority (Inventory > Mail > Bank)
	app.getBagCountByID = sGetBag
	_G.NUM_BAG_SLOTS = 4
	_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
	_G.Enum = {
		PlayerInteractionType = { Merchant = 5, Banker = 8, CharacterBanker = 44, MailInfo = 17 },
		BagIndex = {
			Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4,
			ReagentBag = 5,
			CharacterBankTab_1 = 12, CharacterBankTab_2 = 13, CharacterBankTab_3 = 14,
			-- Notice BankBag_1 is intentionally nil just like WoW: Forever 16001!
		},
	}
	local bagListF = app.getBagContainers()
	local hasBag5 = false
	for _, bid in ipairs(bagListF) do if bid == 5 then hasBag5 = true end end
	check(hasBag5 == true, "Forever 16001: getBagContainers() includes ReagentBag (bag 5) even when BankBag_1 is nil")

	local bankListF = app.getBankContainers()
	local hasTab12, hasReagentInBank = false, false
	for _, bid in ipairs(bankListF) do
		if bid == 12 then hasTab12 = true end
		if bid == 5 then hasReagentInBank = true end
	end
	check(hasTab12 == true and hasReagentInBank == false,
		"Forever 16001: getBankContainers() includes CharacterBankTab_1 (12) and excludes ReagentBag (5)")

	_G.C_Container = {
		GetContainerNumSlots = function(bag)
			if bag == 0 then return 1 end
			if bag == 5 then return 4 end
			if bag == 12 then return 2 end
			return 0
		end,
		GetContainerItemInfo = function(bag, slot)
			if bag == 0 and slot == 1 then
				return {
					itemID = 6359,
					stackCount = 7,
					hyperlink = "|cffffffff|Hitem:6359::::::::60:::::::|h[Firefin Snapper]|h|r",
				}
			end
			if bag == 5 and slot == 1 then
				return {
					itemID = 3372,
					stackCount = 99,
					hyperlink = "|cffffffff|Hitem:3372::::::::60:::::::|h[Leaded Vial]|h|r",
				}
			end
			return nil
		end,
		GetContainerItemLink = function(bag, slot)
			if bag == 0 and slot == 1 then return "|cffffffff|Hitem:6359::::::::60:::::::|h[Firefin Snapper]|h|r" end
			if bag == 5 and slot == 1 then return "|cffffffff|Hitem:3372::::::::60:::::::|h[Leaded Vial]|h|r" end
			return nil
		end,
		GetContainerItemID = function(bag, slot)
			if bag == 0 and slot == 1 then return 6359 end
			if bag == 5 and slot == 1 then return 3372 end
			return nil
		end,
	}
	app.bagCountsDirty = true
	app.cachedBagCountsByID = nil
	local vialCnt = app.getBagCountByID(3372)
	check(vialCnt == 99, "Forever 16001: getBagCountByID finds 99x Leaded Vial inside ReagentBag (5), got " .. tostring(vialCnt))

	-- Priority: 10 needed with bags=3, mail=4, bank=5 -> strictly allocates 3 bags, 4 mail, 3 bank!
	of.LoadFromShoppingRows({
		{ name = "Priority Herb", itemID = 13463, qty = 0, ownedUsed = 10, categoryName = "Priority Goal" },
		{ name = "Leaded Vial", itemID = 3372, qty = 0, ownedUsed = 15, categoryName = "Priority Goal" },
	}, {
		title = "Collect Priority Test",
		ownershipProvider = function(id)
			if id == 13463 then return { bags = 3, mail = 4, bank = 5, alts = {} } end
			return { bags = app.getBagCountByID(id), mail = 0, bank = 20, alts = {} }
		end,
	})
	local prioItems = of.GetState().stages.collect.items
	local herbMail, herbBank, herbBags, vialBags, vialBank = 0, 0, 0, 0, 0
	for _, it in ipairs(prioItems) do
		if it.itemID == 13463 then
			if it.source == "bags" then herbBags = it.needed
			elseif it.source == "mail" then herbMail = it.needed
			elseif it.source == "bank" then herbBank = it.needed end
		elseif it.itemID == 3372 then
			if it.source == "bags" then vialBags = it.needed
			elseif it.source == "bank" then vialBank = it.needed end
		end
	end
	check(herbBags == 3 and herbMail == 4 and herbBank == 3,
		string.format("Collect prioritizes Inventory > Mail > Bank (expected bags=3, mail=4, bank=3; got %d, %d, %d)", herbBags, herbMail, herbBank))
	check(vialBags == 15 and vialBank == 0,
		"ReagentBag (5) vials fulfill entire 15x requirement in Inventory (bags=15, bank=0)")

	-- 5. bagCounts / app.getBagCountByID cache fix: app.bagsDirty alone must not bust bagCounts cache
	local containerSlotCalls = 0
	local origNumSlots = _G.C_Container.GetContainerNumSlots
	_G.C_Container.GetContainerNumSlots = function(bag)
		containerSlotCalls = containerSlotCalls + 1
		return origNumSlots(bag)
	end
	app.bagCountsDirty = true
	app.cachedBagCountsByID = nil
	local cnt1 = app.getBagCountByID(6359)
	check(cnt1 == 7 and app.bagCountsDirty == false, "Initial getBagCountByID populates cache (got " .. tostring(cnt1) .. ")")
	local callsAfterPopulate = containerSlotCalls
	app.bagsDirty = true
	for _ = 1, 5 do
		check(app.getBagCountByID(6359) == 7, "Cached getBagCountByID returns 7 even when app.bagsDirty=true")
	end
	check(containerSlotCalls == callsAfterPopulate,
		"app.bagsDirty alone does NOT bust app.getBagCountByID cache (calls " .. tostring(callsAfterPopulate) .. " vs " .. tostring(containerSlotCalls) .. ")")

	-- Cleanup
	if tab and tab.HideTab then tab.HideTab() end
	app.exitAHBuyingMode(false)
	_G.TradeSkillFrame, _G.CraftFrame, _G.ProfessionsFrame = sTSF, sCF, sPF
	_G.C_TradeSkillUI, _G.C_Spell, _G.UnitCastingInfo, _G.GetTime = sCTrade, sCSpell, sUnitCast, sGetTime
	_G.GetTradeSkillLine, _G.GetNumTradeSkills, _G.GetTradeSkillInfo, _G.GetTradeSkillRecipeLink, _G.SelectTradeSkill, _G.DoTradeSkill = sGetTSL, sGetNTS, sGetTSI, sGetTSLink, sSelTS, sDoTS
	app.getBagCountByID = sGetBag
	ns.IsForeignTradeSkill = sIsForeign
	_G.C_Container = sCCont
	_G.Enum = sEnum
	_G.NUM_BAG_SLOTS = sNumBags
	_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = sNumTotalBags
end)()

---------------------------------------------------------------------------------------------------
-- 11. WS4: Shared ns.AHChannel Lease, Direct One-Click Cart Buying & Sniper Unlisted/Cap Guards
---------------------------------------------------------------------------------------------------
local function runWS4Tests()
	local ch = ns.AHChannel
	check(ch ~= nil and type(ch.TryAcquire) == "function" and type(ch.Release) == "function"
		and type(ch.GetOwner) == "function" and type(ch.GetKind) == "function" and type(ch.IsBusy) == "function",
		"WS4: ns.AHChannel lease API exported")

	-- 11a. AHChannel lease semantics: acquire, mutual exclusion, market_scan preemption, release, AH close reset
	ch.Reset()
	check(ch.GetOwner() == nil and ch.IsBusy() == false and ch.IsBusy("cart_buyer") == false,
		"WS4: AHChannel starts idle")
	local ok1, err1 = ch.TryAcquire("market_scan", "browse")
	check(ok1 == true and err1 == nil and ch.GetOwner() == "market_scan" and ch.GetKind() == "browse",
		"WS4: market_scan acquires AHChannel")
	check(ch.IsBusy("market_scan") == false and ch.IsBusy("sniper") == true and ch.IsBusy("cart_buyer") == true,
		"WS4: IsBusy excludes current owner and flags others")
	-- Explicit player action preempts background market_scan
	local ok2 = ch.TryAcquire("cart_buyer", { kind = "commodity", preemptScan = true })
	check(ok2 == true and ch.GetOwner() == "cart_buyer" and ch.GetKind() == "commodity",
		"WS4: cart_buyer preempts market_scan cleanly")
	-- Mutual exclusion between active non-scan owners
	local ok3, err3 = ch.TryAcquire("sniper", "commodity")
	check(ok3 == false and tostring(err3):find("cart_buyer", 1, true) ~= nil,
		"WS4: sniper blocked while cart_buyer holds AHChannel")
	check(ch.Release("sniper") == false and ch.GetOwner() == "cart_buyer",
		"WS4: wrong owner cannot release cart_buyer lease")
	check(ch.Release("cart_buyer") == true and ch.GetOwner() == nil and ch.IsBusy() == false,
		"WS4: owner releases AHChannel cleanly")

	-- Save globals for WS4 direct buy tests
	local origCAH = _G.C_AuctionHouse
	local origMoney = _G.GetMoney
	local origTimerAfter = _G.C_Timer and _G.C_Timer.After
	local origLegacy = _G.IsUsingLegacyAuctionClient
	local origSearchAH2 = app.searchAH
	local origMailHelper = ns.MailHelper
	local origOpenCart = app.openCartBuyer

	local pendingTimers = {}
	if _G.C_Timer then
		_G.C_Timer.After = function(delay, fn)
			pendingTimers[#pendingTimers + 1] = { delay = delay, fn = fn, fired = false }
		end
	end
	local function flushTimers(minDelay)
		local list = pendingTimers
		pendingTimers = {}
		for _, t in ipairs(list) do
			if not t.fired and (not minDelay or t.delay >= minDelay) then
				t.fired = true
				t.fn()
			end
		end
	end

	local ahCalls = { start = {}, confirm = {}, cancel = 0, bid = {} }
	local mockMoney = 1000000 -- 100g
	local mockThrottledReady = true
	local mockQuoteRemaining = 25
	local mockCommResults = {}
	local mockItemResults = {}

	_G.GetMoney = function() return mockMoney end
	_G.IsUsingLegacyAuctionClient = function() return false end
	_G.C_AuctionHouse = {
		IsThrottledMessageSystemReady = function() return mockThrottledReady end,
		GetQuoteDurationRemaining = function() return mockQuoteRemaining end,
		StartCommoditiesPurchase = function(...)
			ahCalls.start[#ahCalls.start + 1] = { n = select("#", ...), a1 = select(1, ...), a2 = select(2, ...), a3 = select(3, ...) }
			return true
		end,
		ConfirmCommoditiesPurchase = function(id, qty)
			ahCalls.confirm[#ahCalls.confirm + 1] = { itemID = id, qty = qty }
			-- Simulate host hook firing synchronously during ConfirmCommoditiesPurchase
			cb.OnCommodityPurchaseConfirmed(id, qty)
			return true
		end,
		CancelCommoditiesPurchase = function()
			ahCalls.cancel = ahCalls.cancel + 1
		end,
		PlaceBid = function(auctionID, amount)
			ahCalls.bid[#ahCalls.bid + 1] = { auctionID = auctionID, amount = amount }
			-- Simulate host hook firing synchronously during PlaceBid (must be ignored for self-initiated bids!)
			cb.OnItemBidPlaced(auctionID, amount)
			return true
		end,
		GetNumCommoditySearchResults = function(itemID)
			return mockCommResults[itemID] and #mockCommResults[itemID] or 0
		end,
		GetCommoditySearchResultInfo = function(itemID, i)
			return mockCommResults[itemID] and mockCommResults[itemID][i] or nil
		end,
		GetNumItemSearchResults = function(key)
			local id = type(key) == "table" and key.itemID or nil
			return id and mockItemResults[id] and #mockItemResults[id] or 0
		end,
		GetItemSearchResultInfo = function(key, i)
			local id = type(key) == "table" and key.itemID or nil
			return id and mockItemResults[id] and mockItemResults[id][i] or nil
		end,
	}

	local searchCount = 0
	app.searchAH = function() searchCount = searchCount + 1; return true end
	_G.AuctionHouseFrame:Show()

	-- 11b. app.multiSearchBuyer delegates to openCartBuyer natively
	local delegatedTerms = nil
	app.openCartBuyer = function(ct) delegatedTerms = ct; return true end
	local multiRes = app.multiSearchBuyer("Test Multi", { { name = "Peacebloom", itemID = 2447, qty = 4 } })
	app.openCartBuyer = origOpenCart
	check(multiRes == true and delegatedTerms and #delegatedTerms == 1 and delegatedTerms[1].itemID == 2447,
		"WS4: multiSearchBuyer delegates to openCartBuyer natively")

	-- 11c. OrderFlow.CollectFromMail defers when ns.MailHelper.IsActive() is true
	ns.MailHelper = { IsActive = function() return true end }
	local mailTakeCalled = false
	local origTakeMail = _G.TakeInboxItem
	_G.TakeInboxItem = function() mailTakeCalled = true end
	of.LoadFromShoppingRows({
		{ name = "Sunfire Herb", itemID = 70001, qty = 0, ownedUsed = 2, categoryName = "Mail Test" },
	}, {
		title = "Mail Guard Test",
		ownershipProvider = function() return { bags = 0, bank = 0, mail = 2, alts = {} } end,
	})
	of.SetActiveStage("collect")
	local colOk, colReason = of.CollectFromMail(1)
	check(colOk == false and colReason == "mail_helper_active" and mailTakeCalled == false,
		"WS4: OrderFlow.CollectFromMail pauses/defers when MailHelper.IsActive() is true")
	ns.MailHelper = origMailHelper
	_G.TakeInboxItem = origTakeMail

	-- 11d. Direct 2-click commodity buy (quote, confirm, verifiedTotal in spentCopper, all 5 GetPrimaryAction states)
	app.sendShoppingRowsToBuyer({
		{ name = "Copper Ore", itemID = 61001, qty = 5, ahUnitPrice = 1000, maxBuyUnit = 1200 },
		{ name = "Rare Blade", itemID = 61002, qty = 2, ahUnitPrice = 20000, maxBuyUnit = 25000 },
		{ name = "Final Herb", itemID = 61003, qty = 1, ahUnitPrice = 500 },
	}, "WS4 Direct Cart")
	local dst = cb.GetState()
	check(cb.GetPrimaryAction().state == "idle" and cb.GetPrimaryAction().label == "Open in AH",
		"WS4: idle before live search shows Open in AH")

	-- Zero cross-talk when ah_seller owns channel
	ch.TryAcquire("ah_seller", "sell_search")
	mockCommResults[61001] = { { unitPrice = 99999, quantity = 50 } }
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 61001)
	check(dst.items[1].liveUnit == nil and dst.items[1].liveKind == nil,
		"WS4: handleCartBuyerEvent ignores COMMODITY_SEARCH_RESULTS_UPDATED when ah_seller owns AHChannel")
	ch.Release("ah_seller")

	-- Real live commodity search arrives for Copper Ore: 5x at 1000c = 5000c
	mockCommResults[61001] = { { unitPrice = 1000, quantity = 20 } }
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 61001)
	check(dst.items[1].liveKind == "commodity" and dst.items[1].liveAvailQty == 5 and dst.items[1].liveTotal == 5000,
		"WS4: commodity search records liveKind='commodity', liveAvailQty=5, liveTotal=5000")
	local paIdle = cb.GetPrimaryAction()
	check(paIdle.state == "idle" and paIdle.label == "Buy 5x" and paIdle.enabled == true and paIdle.wideConfirm == false,
		"WS4: GetPrimaryAction idle commodity shows 'Buy 5x', got " .. tostring(paIdle.label))
	check(cb.GetCancelAction().active == false and cb.GetCancelAction().label == "Mark Bought",
		"WS4: GetCancelAction idle shows Mark Bought")

	-- Click 1: ExecutePrimaryAction starts commodity quote with STRICTLY 2 args
	pendingTimers = {}
	local sOk = cb.ExecutePrimaryAction()
	check(sOk == true, "WS4: Click 1 StartDirectBuy succeeds")
	check(#ahCalls.start == 1 and ahCalls.start[1].n == 2 and ahCalls.start[1].a1 == 61001 and ahCalls.start[1].a2 == 5,
		"WS4: StartCommoditiesPurchase invoked with strictly 2 args (61001, 5)")
	check(ch.GetOwner() == "cart_buyer" and cb.IsPurchaseInFlight() == true,
		"WS4: AHChannel acquired by cart_buyer during quoting")
	local paQuoting = cb.GetPrimaryAction()
	check(paQuoting.state == "quoting" and paQuoting.enabled == false and paQuoting.label == "Quoting...",
		"WS4: GetPrimaryAction quoting state verified")
	check(cb.GetCancelAction().active == true and cb.GetCancelAction().label == "Cancel Buy",
		"WS4: GetCancelAction during quoting shows Cancel Buy")

	-- COMMODITY_PRICE_UPDATED with slight jump within 5% tolerance (1020c ea, 5100c total <= 5250c)
	local evHandled = ns.MarketScan.HandleEvent("COMMODITY_PRICE_UPDATED", 1020, 5100)
	check(evHandled == true, "WS4: MarketScan.HandleEvent returns true for COMMODITY_PRICE_UPDATED")
	local paConfirm = cb.GetPrimaryAction()
	check(paConfirm.state == "awaiting_confirm" and paConfirm.enabled == true and paConfirm.wideConfirm == true,
		"WS4: GetPrimaryAction awaiting_confirm sets wideConfirm=true")
	check(cb.GetDirectBuyState().verifiedTotal == 5100, "WS4: verifiedTotal preserved from arg2 (5100)")

	-- Expired quote blocks ConfirmDirectBuy
	mockQuoteRemaining = 0
	local expOk, expErr = cb.ConfirmDirectBuy()
	check(expOk == false and expErr == "quote_expired" and ch.GetOwner() == nil,
		"WS4: GetQuoteDurationRemaining()==0 aborts ConfirmDirectBuy and releases lease")
	mockQuoteRemaining = 25

	-- Price jump above 5% tolerance / cap rejects quote automatically
	check(cb.StartDirectBuy() == true, "WS4: restart commodity quote for jump test")
	local cancelBefore = ahCalls.cancel
	ns.MarketScan.HandleEvent("COMMODITY_PRICE_UPDATED", 1100, 5500) -- 5500 > floor(5000*1.05)=5250
	check(cb.GetDirectBuyState() == nil and ch.GetOwner() == nil and ahCalls.cancel == cancelBefore + 1,
		"WS4: price jump above 5% tolerance cancels quote and releases lease")

	-- COMMODITY_PRICE_UNAVAILABLE aborts cleanly
	check(cb.StartDirectBuy() == true, "WS4: restart commodity quote for unavailable test")
	local unavailHandled = ns.MarketScan.HandleEvent("COMMODITY_PRICE_UNAVAILABLE")
	check(unavailHandled == true and cb.GetDirectBuyState() == nil and ch.GetOwner() == nil,
		"WS4: COMMODITY_PRICE_UNAVAILABLE cancels quote and releases lease")

	-- Full 2-click commodity buy completion records exact verifiedTotal (5100c) and advances to item 2
	pendingTimers = {}
	check(cb.StartDirectBuy() == true, "WS4: start commodity quote for full confirm")
	ns.MarketScan.HandleEvent("COMMODITY_PRICE_UPDATED", 1020, 5100)
	local cOk = cb.ExecutePrimaryAction()
	check(cOk == true, "WS4: Click 2 ConfirmDirectBuy succeeds")
	local paConfirming = cb.GetPrimaryAction()
	check(paConfirming.state == "confirming" and paConfirming.enabled == false and paConfirming.wideConfirm == true,
		"WS4: GetPrimaryAction confirming state verified")
	check(#ahCalls.confirm == 1 and ahCalls.confirm[1].itemID == 61001 and ahCalls.confirm[1].qty == 5,
		"WS4: ConfirmCommoditiesPurchase called with (61001, 5)")
	-- Confirm hook did NOT overwrite verifiedTotal
	ns.MarketScan.HandleEvent("COMMODITY_PURCHASE_SUCCEEDED")
	check(dst.spentCopper == 5100, "WS4: COMMODITY_PURCHASE_SUCCEEDED records exact verifiedTotal (5100c), got " .. tostring(dst.spentCopper))
	check(dst.items[1].status == "done" and dst.activeIndex == 2 and ch.GetOwner() == nil,
		"WS4: commodity purchase completes item 1, releases lease, and advances to item 2")

	-- 11e. Non-commodity 1-click buyout: unit cap, stack warning, self-hook no-lockout, AUCTION_HOUSE_PURCHASE_COMPLETED auto-advance
	-- First test over-cap block (unitBuyout = 60000 / 2 = 30000 > maxBuyUnit 25000)
	mockItemResults[61002] = {
		{ auctionID = 9001, buyoutAmount = 60000, quantity = 2, containsOwnerItem = false },
	}
	ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 61002 })
	check(dst.items[2].liveKind == "item" and dst.items[2].overBuyCap == true,
		"WS4: item search flags overBuyCap when unitBuyout > maxBuyUnit")
	local capBlkOk, capBlkErr = cb.StartDirectBuy()
	check(capBlkOk == false and capBlkErr == "over_buy_cap",
		"WS4: overBuyCap blocks StartDirectBuy for non-commodity item")
	check(cb.GetPrimaryAction().action == "open_in_ah",
		"WS4: overBuyCap primary action falls back to Open in AH")

	-- Now provide valid listing: stack of 3x for 54000c (18000c ea <= 25000c cap, stack 3 > remaining 2 -> warning!)
	mockItemResults[61002] = {
		{ auctionID = 9000, buyoutAmount = 10000, quantity = 1, containsOwnerItem = true }, -- owner listing skipped
		{ auctionID = 9002, buyoutAmount = 54000, quantity = 3, containsOwnerItem = false },
	}
	ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 61002 })
	check(dst.items[2].liveAuctionID == 9002 and dst.items[2].liveAuctionQty == 3 and dst.items[2].liveBuyout == 54000
		and dst.items[2].overbuyStackWarning == true and dst.items[2].overBuyCap == false,
		"WS4: item search skips owner listing, records liveAuctionQty=3 and overbuyStackWarning=true")
	local paItem = cb.GetPrimaryAction()
	check(paItem.state == "idle" and paItem.label == "Buy 3x (!)" and paItem.overbuyStackWarning == true,
		"WS4: GetPrimaryAction shows stack warning 'Buy 3x (!)', got " .. tostring(paItem.label))

	-- Legacy AH guard blocks direct buy
	_G.IsUsingLegacyAuctionClient = function() return true end
	local legOk, legErr = cb.StartDirectBuy()
	check(legOk == false and legErr == "legacy_ah", "WS4: IsUsingLegacyAuctionClient blocks StartDirectBuy")
	_G.IsUsingLegacyAuctionClient = function() return false end

	-- Click 1: non-commodity PlaceBid (self-initiated OnItemBidPlaced must NOT create pendingExternalBid!)
	pendingTimers = {}
	local bOk = cb.ExecutePrimaryAction()
	check(bOk == true, "WS4: 1-click non-commodity buyout succeeds")
	check(#ahCalls.bid == 1 and ahCalls.bid[1].auctionID == 9002 and ahCalls.bid[1].amount == 54000,
		"WS4: PlaceBid invoked with (9002, 54000)")
	check(dst.pendingExternalBid == nil, "WS4: self-initiated PlaceBid hook does not create pendingExternalBid lockout")
	local paBuying = cb.GetPrimaryAction()
	check(paBuying.state == "buying" and paBuying.enabled == false and paBuying.label == "Buying...",
		"WS4: GetPrimaryAction buying state verified")

	-- AUCTION_HOUSE_PURCHASE_COMPLETED completes item 2, adds 54000c, releases lease, and auto-advances to item 3
	local buyCompHandled = ns.MarketScan.HandleEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 9002)
	check(buyCompHandled == true, "WS4: HandleEvent returns true for AUCTION_HOUSE_PURCHASE_COMPLETED")
	check(dst.spentCopper == 5100 + 54000, "WS4: item buyout adds exact 54000c to spentCopper")
	check(dst.items[2].status == "done" and dst.activeIndex == 3 and ch.GetOwner() == nil,
		"WS4: item buyout marks item 2 done, releases lease, and advances to item 3")

	-- 11f. Serial-guarded watchdog timeout releases wedged lease without cancelling newer serial
	mockCommResults[61003] = { { unitPrice = 500, quantity = 10 } }
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 61003)
	pendingTimers = {}
	check(cb.StartDirectBuy() == true, "WS4: start quote for watchdog test")
	local firstWatchdog = pendingTimers[#pendingTimers]
	check(firstWatchdog ~= nil and firstWatchdog.delay == 30, "WS4: 30s quote watchdog armed")
	-- Cancel & restart -> first watchdog becomes stale and must NOT cancel the new directBuy
	cb.CancelDirectBuy("user cancel")
	check(cb.StartDirectBuy() == true, "WS4: restart quote with new serial")
	firstWatchdog.fn()
	check(cb.GetDirectBuyState() ~= nil and ch.GetOwner() == "cart_buyer",
		"WS4: stale watchdog serial does not cancel active directBuy")
	-- Firing active watchdog cancels and releases lease
	flushTimers(30)
	check(cb.GetDirectBuyState() == nil and ch.GetOwner() == nil,
		"WS4: active 30s watchdog cancels wedged quote and releases AHChannel")

	-- 11g. SniperEngine WS4/WS2 guards: AHChannel mutual exclusion, qty==0 skip, 1.25x snapHist cap
	local SE = ns.SniperEngine
	check(SE ~= nil, "WS4: ns.SniperEngine loaded for cross-subsystem checks")
	SE.atAH = true
	-- Hold cart_buyer lease -> Sniper StartCommodityBuy must refuse with cart_buyer_busy
	ch.TryAcquire("cart_buyer", "commodity")
	local snBlk, snErr = SE.StartCommodityBuy({ idKey = "c:61003", itemID = 61003, buyQty = 1, totalCost = 500, mode = "gap" })
	check(snBlk == false and snErr == "cart_buyer_busy",
		"WS4: Sniper StartCommodityBuy blocked when cart_buyer holds AHChannel, got " .. tostring(snErr))
	ch.Release("cart_buyer")

	-- Hold sniper lease via SE.StartCommodityBuy -> CartBuyer StartDirectBuy must refuse
	local snStartOk = SE.StartCommodityBuy({ idKey = "c:61003", itemID = 61003, buyQty = 1, totalCost = 500, mode = "gap" })
	check(snStartOk == true and ch.GetOwner() == "sniper", "WS4: Sniper acquires 'sniper' AHChannel lease on purchase start")
	local cbBlk, cbBlkErr = cb.StartDirectBuy()
	check(cbBlk == false and tostring(cbBlkErr):find("sniper", 1, true) ~= nil,
		"WS4: CartBuyer StartDirectBuy blocked while sniper holds AHChannel")
	SE.CancelActivePurchase("test cleanup")
	check(ch.GetOwner() == nil, "WS4: Sniper CancelActivePurchase releases 'sniper' AHChannel lease")

	-- Sniper qty==0 skip + 1.25x snapHist anti-manipulation cap
	local origQuerySnap = ns.QueryLocalSnapshot
	local origSnapParsed = ns.snapshotParsed
	local origRegSaleFn = ns.Pricing and ns.Pricing.GetItemSnapshotRegionSale
	local origVendorFn = ns.GetVendorSellPrice
	local origConserv = ns.GetConservativeSaleUnitPrice
	local origDemandFn = ns.GetMultiSourceDemand

	local testEcon = "WS4-Test-Econ"
	local testSnap = {
		-- Unlisted 14d item (qty=0, even if minBuyout were non-zero): MUST be skipped by both Vendor & Gap scans!
		[62001] = { minBuyout = 100, marketValue = 50000, historical = 50000, qty = 0 },
		-- Listed item with inflated marketValue (50000) vs historical (10000) and no regSale -> capped at 12500!
		[62002] = { minBuyout = 2000, marketValue = 50000, historical = 10000, qty = 10 },
	}
	ns.snapshotParsed = { [testEcon] = { items = testSnap, meta = { updatedAt = 1760000000 } } }
	ns.QueryLocalSnapshot = function(id)
		local r = testSnap[id]
		return r and (r.minBuyout or r.marketValue) or nil, r
	end
	if ns.Pricing then ns.Pricing.GetItemSnapshotRegionSale = function() return nil end end
	ns.GetVendorSellPrice = function(id) return (id == 62001) and 50000 or 10 end
	ns.GetConservativeSaleUnitPrice = nil
	ns.GetMultiSourceDemand = function() return { effectiveDailySold = 20, dailySold = 20, demandSource = "velocity", confidence = 2 } end

	local refP, refSrc = SE.GetReferencePrice(62002, testEcon)
	check(refP == 12500 and refSrc == "snapshot_hist_cap",
		"WS4: GetReferencePrice caps snapMV at 1.25 * snapHist when regSale==nil (expected 12500/snapshot_hist_cap, got "
		.. tostring(refP) .. "/" .. tostring(refSrc) .. ")")

	SE.ClearVendorDeals()
	SE.ScanSnapshotForVendorDeals(testEcon, { minProfitCopper = 100 })
	check(SE.vendorDealsByKey["vendor:62001"] == nil,
		"WS4: ScanSnapshotForVendorDeals skips unlisted snapshot row with qty==0")

	local sl = SE.BuildGapShortlist({ econ = testEcon, minDailySales = 1, minProfitCopper = 100, minQuality = 0 })
	local foundUnlisted = false
	for _, entry in ipairs(sl) do
		if entry.itemID == 62001 then foundUnlisted = true end
	end
	check(not foundUnlisted, "WS4: BuildGapShortlist skips unlisted snapshot row with qty==0")

	-- Restore WS4 mocks cleanly
	ns.QueryLocalSnapshot = origQuerySnap
	ns.snapshotParsed = origSnapParsed
	if ns.Pricing then ns.Pricing.GetItemSnapshotRegionSale = origRegSaleFn end
	ns.GetVendorSellPrice = origVendorFn
	ns.GetConservativeSaleUnitPrice = origConserv
	ns.GetMultiSourceDemand = origDemandFn
	ch.Reset()
	app.exitAHBuyingMode(false)
	app.searchAH = origSearchAH2
	_G.C_AuctionHouse = origCAH
	_G.GetMoney = origMoney
	_G.IsUsingLegacyAuctionClient = origLegacy
	if _G.C_Timer and origTimerAfter then _G.C_Timer.After = origTimerAfter end
end
runWS4Tests()

---------------------------------------------------------------------------------------------------
-- 12. WS4 Review Regressions (Majors #1-#4 from review_ws1_ws4.md)
---------------------------------------------------------------------------------------------------
local function runWS4ReviewRegressions()
	local ch = ns.AHChannel
	local SE = ns.SniperEngine
	local origCAH = _G.C_AuctionHouse
	local origMoney = _G.GetMoney
	local origTimerAfter = _G.C_Timer and _G.C_Timer.After
	local origLegacy = _G.IsUsingLegacyAuctionClient
	local origSearchAH3 = app.searchAH
	local origSearchBar = _G.AuctionHouseFrame and _G.AuctionHouseFrame.SearchBar

	local timers = {}
	if _G.C_Timer then
		_G.C_Timer.After = function(delay, fn)
			timers[#timers + 1] = { delay = delay, fn = fn }
		end
	end

	local mockThrottled = true
	local mockItems = {}
	_G.GetMoney = function() return 1000000 end
	_G.IsUsingLegacyAuctionClient = function() return false end
	_G.C_AuctionHouse = {
		IsThrottledMessageSystemReady = function() return mockThrottled end,
		GetQuoteDurationRemaining = function() return 25 end,
		StartCommoditiesPurchase = function() return true end,
		ConfirmCommoditiesPurchase = function(id, qty)
			cb.OnCommodityPurchaseConfirmed(id, qty)
			return true
		end,
		CancelCommoditiesPurchase = function() end,
		PlaceBid = function() return true end,
		GetNumItemSearchResults = function(key)
			local id = type(key) == "table" and key.itemID or nil
			return id and mockItems[id] and #mockItems[id] or 0
		end,
		GetItemSearchResultInfo = function(key, i)
			local id = type(key) == "table" and key.itemID or nil
			return id and mockItems[id] and mockItems[id][i] or nil
		end,
	}

	local searchCalls = 0
	app.searchAH = function() searchCalls = searchCalls + 1; return true end
	ch.Reset()
	_G.AuctionHouseFrame:Show()

	-- Load 2 items: item 1 non-commodity (63001, liveAuctionID=111, liveBuyout=5000), item 2 commodity (63002)
	app.sendShoppingRowsToBuyer({
		{ name = "Relic Sword", itemID = 63001, qty = 1, ahUnitPrice = 5000 },
		{ name = "Peacebloom", itemID = 63002, qty = 5, ahUnitPrice = 200 },
	}, "WS4 Regressions")
	mockItems[63001] = {
		{ auctionID = 111, buyoutAmount = 5000, quantity = 1, containsOwnerItem = false },
	}
	ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 63001 })
	local st = cb.GetState()
	check(st.items[1].liveAuctionID == 111 and st.items[1].liveBuyout == 5000,
		"WS4-R: item 1 seeded with liveAuctionID=111, liveBuyout=5000")

	-- MAJOR #1: Unrelated auctionID (999) must NOT bind to cart item (111) or complete it
	cb.OnItemBidPlaced(999, 5000)
	check(st.pendingExternalBid == nil and cb.IsPurchaseInFlight() == false,
		"WS4-R1: unmatched auctionID 999 does not set pendingExternalBid")
	local handledUnrelated = ns.MarketScan.HandleEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 999)
	check(handledUnrelated == false and st.items[1].remaining == 1 and st.items[1].status ~= "done",
		"WS4-R1: AUCTION_HOUSE_PURCHASE_COMPLETED(999) never completes cart item 111")

	-- MAJOR #2a: Ordinary below-buyout bid (2500 < 5000) must NOT set pendingExternalBid
	cb.OnItemBidPlaced(111, 2500)
	check(st.pendingExternalBid == nil and cb.IsPurchaseInFlight() == false,
		"WS4-R2: below-buyout bid (2500 vs 5000) ignored by OnItemBidPlaced")

	-- MAJOR #2b: Exact buyout bid sets pendingExternalBid + 15s serial watchdog
	timers = {}
	cb.OnItemBidPlaced(111, 5000)
	check(st.pendingExternalBid ~= nil and st.pendingExternalBid.auctionID == 111 and cb.IsPurchaseInFlight() == true,
		"WS4-R2: matching buyout bid sets pendingExternalBid")
	check(#timers == 1 and timers[1].delay == 15, "WS4-R2: 15s expiration watchdog armed on pendingExternalBid")
	local firstExtTimer = timers[1]
	-- CancelDirectBuy clears pendingExternalBid and bumps serial so stale timer is harmless
	cb.CancelDirectBuy("test cancel")
	check(st.pendingExternalBid == nil and cb.IsPurchaseInFlight() == false,
		"WS4-R2: CancelDirectBuy clears pendingExternalBid")

	-- Re-arm, test stale watchdog does not clear newer pendingExternalBid, then active watchdog expires it
	timers = {}
	cb.OnItemBidPlaced(111, 5000)
	firstExtTimer.fn()
	check(st.pendingExternalBid ~= nil, "WS4-R2: stale watchdog serial does not clear newer pendingExternalBid")
	timers[1].fn()
	check(st.pendingExternalBid == nil and cb.IsPurchaseInFlight() == false,
		"WS4-R2: active 15s watchdog expires pendingExternalBid cleanly")

	-- AUCTION_HOUSE_CLOSED clears pendingExternalBid
	cb.OnItemBidPlaced(111, 5000)
	check(st.pendingExternalBid ~= nil, "WS4-R2: pendingExternalBid set before AH close")
	_G.AuctionHouseFrame:Hide()
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_CLOSED")
	check(st.pendingExternalBid == nil and cb.IsPurchaseInFlight() == false,
		"WS4-R2: AUCTION_HOUSE_CLOSED clears pendingExternalBid")

	-- MarkBought clears pendingExternalBid
	_G.AuctionHouseFrame:Show()
	cb.OpenInAH(1)
	ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 63001 })
	cb.OnItemBidPlaced(111, 5000)
	check(st.pendingExternalBid ~= nil, "WS4-R2: pendingExternalBid set before MarkBought")
	cb.MarkBought(1)
	check(st.pendingExternalBid == nil and cb.IsPurchaseInFlight() == false,
		"WS4-R2: MarkBought clears pendingExternalBid")

	-- MAJOR #3: OnCommodityPurchaseConfirmed ignores confirmations while Sniper holds AHChannel
	-- CartBuyer is now active on item 2 (itemID 63002, qty 5)
	check(st.active == true and st.items[2].itemID == 63002 and st.items[2].remaining == 5,
		"WS4-R3: CartBuyer active on item 2 (63002)")
	SE.atAH = true
	local snDeal = { idKey = "c:63002", itemID = 63002, itemName = "Peacebloom", buyQty = 5, totalCost = 1000, mode = "gap", status = "ready" }
	local sOk = SE.StartCommodityBuy(snDeal)
	check(sOk == true and ch.GetOwner() == "sniper", "WS4-R3: Sniper acquired 'sniper' lease for commodity buy")
	SE.OnEvent("COMMODITY_PRICE_UPDATED", 200, 1000)
	local scOk = SE.ConfirmCommodityBuy(snDeal)
	check(scOk == true, "WS4-R3: Sniper ConfirmCommodityBuy succeeded")
	-- Host ConfirmCommoditiesPurchase hook fired cb.OnCommodityPurchaseConfirmed(63002, 5) synchronously;
	-- CartBuyer MUST have ignored it so pendingExternal stays nil!
	check(st.pendingExternal == nil, "WS4-R3: OnCommodityPurchaseConfirmed ignored while sniper owns AHChannel")
	SE.OnEvent("COMMODITY_PURCHASE_SUCCEEDED")
	check(SE.GetPurchaseState() == nil and snDeal.status == "bought" and ch.GetOwner() == nil,
		"WS4-R3: Sniper completed its own COMMODITY_PURCHASE_SUCCEEDED cleanly")
	check(st.items[2].bought == 0 and st.items[2].remaining == 5,
		"WS4-R3: CartBuyer item 2 untouched by Sniper commodity purchase")

	-- MAJOR #4a: OpenInAH rejected with "ah_busy" when another subsystem holds AHChannel
	ch.TryAcquire("ah_sell", { kind = "sell_search", preemptScan = true })
	local callsBeforeBusy = searchCalls
	local openOk, openErr = cb.OpenInAH(2)
	check(openOk == false and openErr == "ah_busy" and searchCalls == callsBeforeBusy,
		"WS4-R4: OpenInAH rejects with 'ah_busy' when ah_sell owns AHChannel")
	ch.Release("ah_sell")

	-- MAJOR #4b: sendWantedWhenReady re-checks IsBusy("cart_buyer") before deferred StartSearch dispatch
	app.searchAH = origSearchAH3
	local startSearchCount = 0
	local mockBar = {
		SetSearchText = function() end,
		StartSearch = function() startSearchCount = startSearchCount + 1 end,
	}
	_G.AuctionHouseFrame.SearchBar = mockBar
	mockThrottled = false
	app.searchAH("Peacebloom", 5, 2447)
	check(startSearchCount == 0 and app.wanted and app.wanted.pendingBar == mockBar,
		"WS4-R4: throttled searchAH defers StartSearch via pendingBar")
	-- Another subsystem acquires AHChannel before throttle becomes ready
	ch.TryAcquire("ah_undercut", { kind = "undercut", preemptScan = true })
	mockThrottled = true
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	check(startSearchCount == 0,
		"WS4-R4: deferred sendWantedWhenReady aborts StartSearch when AHChannel is busy")
	ch.Release("ah_undercut")

	-- Once channel is free, deferred search dispatches cleanly on throttle ready
	mockThrottled = false
	app.searchAH("Peacebloom", 5, 2447)
	mockThrottled = true
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	check(startSearchCount == 1,
		"WS4-R4: deferred sendWantedWhenReady dispatches StartSearch when AHChannel is idle")

	-- MAJOR #5 (re-review): Cross-cart externalBidSerial watchdog isolation across resetAllStages
	app.searchAH = function() return true end
	timers = {}
	app.sendShoppingRowsToBuyer({
		{ name = "Relic Sword", itemID = 63001, qty = 1, ahUnitPrice = 5000 },
	}, "Cart 1")
	mockItems[63001] = {
		{ auctionID = 211, buyoutAmount = 5000, quantity = 1, containsOwnerItem = false },
	}
	ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 63001 })
	cb.OnItemBidPlaced(211, 5000)
	check(#timers == 1 and timers[1].delay == 15, "WS4-R5: Cart 1 manual buyout armed 15s watchdog")
	local cart1Watchdog = timers[1]

	-- Load Cart 2 before Cart 1's watchdog fires, and start manual buyout on Cart 2
	timers = {}
	app.sendShoppingRowsToBuyer({
		{ name = "Arcane Staff", itemID = 63003, qty = 1, ahUnitPrice = 9000 },
	}, "Cart 2")
	mockItems[63003] = {
		{ auctionID = 222, buyoutAmount = 9000, quantity = 1, containsOwnerItem = false },
	}
	ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 63003 })
	cb.OnItemBidPlaced(222, 9000)
	local st2 = cb.GetState()
	check(st2.pendingExternalBid ~= nil and st2.pendingExternalBid.auctionID == 222,
		"WS4-R5: Cart 2 manual buyout staged pendingExternalBid for auction 222")

	-- Fire Cart 1's stale watchdog: Cart 2's pendingExternalBid MUST survive and complete normally!
	cart1Watchdog.fn()
	check(st2.pendingExternalBid ~= nil and st2.pendingExternalBid.auctionID == 222,
		"WS4-R5: Cart 1 watchdog does not clear Cart 2 pendingExternalBid after resetAllStages")
	local comp2 = ns.MarketScan.HandleEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 222)
	check(comp2 == true and st2.items[1].status == "done" and st2.spentCopper == 9000,
		"WS4-R5: Cart 2 manual buyout completes normally after Cart 1 watchdog fired")

	-- Cleanup
	ch.Reset()
	app.exitAHBuyingMode(false)
	app.searchAH = origSearchAH3
	if _G.AuctionHouseFrame then _G.AuctionHouseFrame.SearchBar = origSearchBar end
	_G.C_AuctionHouse = origCAH
	_G.GetMoney = origMoney
	_G.IsUsingLegacyAuctionClient = origLegacy
	if _G.C_Timer and origTimerAfter then _G.C_Timer.After = origTimerAfter end
end
runWS4ReviewRegressions()

local function runVendorRecognitionRegressions()
	local of = app.orderFlow
	local origMF = _G.MerchantFrame
	local origAHF = _G.AuctionHouseFrame
	local origUnitName = _G.UnitName
	local origEnum = _G.Enum
	local origGetMNum, origGetMID, origGetMLink, origGetMInfo, origGetMMax, origBuyM =
		_G.GetMerchantNumItems, _G.GetMerchantItemID, _G.GetMerchantItemLink, _G.GetMerchantItemInfo, _G.GetMerchantItemMaxStack, _G.BuyMerchantItem
	local origCMerchant = _G.C_MerchantFrame
	local origMoney = _G.GetMoney
	local origCapture = ns.CaptureMerchantVendorPrices
	local origGetBag = app.getBagCountByID
	local origCContVR = _G.C_Container
	local origTimerAfter = _G.C_Timer and _G.C_Timer.After

	_G.C_Container = {
		GetContainerNumSlots = function(b) return b == 0 and 8 or 0 end,
		GetContainerNumFreeSlots = function(b) return b == 0 and 8 or 0, 0 end,
		GetContainerItemInfo = function() return nil end,
	}

	if _G.C_Timer then _G.C_Timer.After = function(_, fn) fn() end end
	local vMF = CreateFrame("Frame", "MockRegressMerchant", UIParent); vMF:Hide()
	_G.MerchantFrame = vMF
	if _G.AuctionHouseFrame then _G.AuctionHouseFrame:Hide() end
	_G.UnitName = function(unit)
		if unit == "npc" then return "Mani Winterhoof" end
		return origUnitName and origUnitName(unit) or "TestPlayer"
	end
	_G.GetMoney = function() return 500000 end

	local bags = { [4711] = 0 }
	app.getBagCountByID = function(id) return bags[id] or 0 end

	local buyCalls = {}
	_G.GetMerchantNumItems = function() return 1 end
	_G.GetMerchantItemID = function() return nil end
	_G.GetMerchantItemLink = function() return nil end
	_G.GetMerchantItemInfo = nil
	_G.C_MerchantFrame = {
		GetItemInfo = function(slot)
			if slot == 1 then
				return {
					itemID = 4711,
					name = "Leaded Vial",
					price = 162,
					stackCount = 5,
					numAvailable = -1,
					isPurchasable = true,
					hasExtendedCost = false,
				}
			end
		end,
	}
	_G.GetMerchantItemMaxStack = function() return 20 end
	_G.BuyMerchantItem = function(slot, qty)
		buyCalls[#buyCalls + 1] = { slot = slot, qty = qty }
		bags[4711] = (bags[4711] or 0) + qty
	end

	-- 1) CaptureMerchantVendorPrices throwing on MERCHANT_SHOW while modal is hidden still tracks vendor;
	--    opening OrderFlow on "ah" then switching to "2. Vendor" recognizes open vendor, renders Spotlight,
	--    reconciles manual bag purchases, and buys bundled Leaded Vial with qty=20 (4x5).
	ns.CaptureMerchantVendorPrices = function() error("simulated vendor capture failure") end
	modal:Hide()
	vMF:Show()
	fireEvent("MERCHANT_SHOW")
	check(of.GetState().env.atVendor == true and of.GetState().env.vendorName == "Mani Winterhoof",
		"VR-1: MERCHANT_SHOW sets atVendor even when modal is hidden and CaptureMerchantVendorPrices errors")

	of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "vr1", name = "Stonescale Oil", itemID = 13423, spellID = 17559, prof = "alchemy", qty = 6,
			reagents = { { itemID = 13422, name = "Stonescale Eel", qty = 1 }, { itemID = 4711, name = "Leaded Vial", qty = 1 } } },
		{ indent = 1, mainGroupKey = "vr1", name = "Stonescale Eel", itemID = 13422, qty = 473, ahUnitPrice = 500 },
		{ indent = 1, mainGroupKey = "vr1", name = "Leaded Vial", itemID = 4711, qty = 496, isVendor = true, vendorUnitPrice = 32 },
	}, {
		title = "Vendor Recognition Test",
		ownershipProvider = function(id) return { bags = bags[id] or 0, bank = 0, mail = 0, alts = {} } end,
	})
	app.enterOrderFlowMode("ah")
	modal.stageBtns.vendor:Click("LeftButton")
	check(of.GetActiveStage() == "vendor", "VR-1b: clicking stageBtns.vendor switches to vendor")
	check(not modal.waitingBanner:IsShown() and modal.spotlightCard:IsShown(),
		"VR-1c: open vendor hides waiting plaque and shows Spotlight")
	check((modal.hdrSubFs:GetText() or ""):find("MANI WINTERHOOF", 1, true) ~= nil,
		"VR-1d: header shows DOCKED TO VENDOR - MANI WINTERHOOF")
	check(modal.buyBtn:IsEnabled(), "VR-1e: Buy from Vendor button enabled when vendor stocked via C_MerchantFrame.GetItemInfo")

	-- Manual buy of 2x5 Leaded Vial while open reconciles via BAG_UPDATE_DELAYED
	bags[4711] = 10
	fireEvent("BAG_UPDATE_DELAYED")
	local vItem = of.GetState().stages.vendor.items[1]
	check(vItem.bought == 10 and vItem.remaining == 486,
		"VR-1f: manual vendor purchase reconciles via BAG_UPDATE_DELAYED (10/496)")

	-- Click Buy from Vendor on bundled 5-pack item -> passes 20 individual units (maxStack=20), NOT 4 packs
	modal.buyBtn:Click("LeftButton")
	check(#buyCalls == 1 and buyCalls[1].slot == 1 and buyCalls[1].qty == 20,
		"VR-1g: BuyVendorItem passes individual unit count (20) to BuyMerchantItem for 5-pack Leaded Vial (got calls="
		.. tostring(#buyCalls) .. " qty=" .. tostring(buyCalls[1] and buyCalls[1].qty) .. " notice=" .. tostring(of.GetState().notice) .. ")")
	fireEvent("BAG_UPDATE_DELAYED")
	check(vItem.bought == 30 and vItem.remaining == 466,
		"VR-1h: BAG_UPDATE_DELAYED reconciles bundled purchase (30/496)")

	-- 2) PLAYER_INTERACTION_MANAGER_FRAME_SHOW / HIDE opens & closes vendor without MERCHNAT_SHOW/CLOSED
	vMF:Hide()
	fireEvent("MERCHANT_CLOSED")
	check(of.GetState().env.atVendor == false and modal.waitingBanner:IsShown(),
		"VR-2a: MERCHANT_CLOSED returns strip to waiting state")
	_G.Enum = { PlayerInteractionType = { Merchant = 5, Banker = 8, CharacterBanker = 8, MailInfo = 17 } }
	vMF:Show()
	fireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
	check(of.GetState().env.atVendor == true and not modal.waitingBanner:IsShown() and modal.spotlightCard:IsShown(),
		"VR-2b: PLAYER_INTERACTION_MANAGER_FRAME_SHOW(Merchant) opens vendor recognition")
	vMF:Hide()
	fireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
	check(of.GetState().env.atVendor == false and modal.waitingBanner:IsShown(),
		"VR-2c: PLAYER_INTERACTION_MANAGER_FRAME_HIDE(Merchant) closes vendor recognition")

	-- 3) Live MerchantFrame:IsShown() without ANY event fired is still detected on BuyVendorItem & Render
	local silentMF = CreateFrame("Frame", "MockSilentMerchant", UIParent)
	_G.MerchantFrame = silentMF
	silentMF:Show()
	check(modal.waitingBanner:IsShown(), "Pre-sync banner check before render")
	modal.Render()
	check(of.GetState().env.atVendor == true and not modal.waitingBanner:IsShown() and modal.spotlightCard:IsShown(),
		"VR-3a: Render SyncLiveEnvironment detects open MerchantFrame without events")
	buyCalls = {}
	local okSilentBuy = of.BuyVendorItem(1)
	check(okSilentBuy == true and #buyCalls == 1 and buyCalls[1].qty == 20,
		"VR-3b: BuyVendorItem succeeds when MerchantFrame is open without prior event")

	-- 4) sendShoppingRowsToBuyer while standing at open vendor (AH closed) opens directly to Stage 2 vendor
	ns.CaptureMerchantVendorPrices = origCapture
	app.enterOrderFlowMode("ah")
	app.exitAHBuyingMode(false)
	app.sendShoppingRowsToBuyer({
		{ name = "Stonescale Eel", itemID = 13422, qty = 10, ahUnitPrice = 500 },
		{ name = "Leaded Vial", itemID = 4711, qty = 20, isVendor = true, vendorUnitPrice = 32 },
	}, "At Vendor Cart")
	check(of.GetActiveStage() == "vendor" and modal:IsShown() and modal.spotlightCard:IsShown(),
		"VR-4: sendShoppingRowsToBuyer at open vendor lands directly on Stage 2 vendor Spotlight")

	-- Cleanup
	silentMF:Hide()
	fireEvent("MERCHANT_CLOSED")
	app.exitAHBuyingMode(false)
	_G.MerchantFrame = origMF
	_G.AuctionHouseFrame = origAHF
	_G.UnitName = origUnitName
	_G.Enum = origEnum
	_G.GetMerchantNumItems, _G.GetMerchantItemID, _G.GetMerchantItemLink, _G.GetMerchantItemInfo, _G.GetMerchantItemMaxStack, _G.BuyMerchantItem =
		origGetMNum, origGetMID, origGetMLink, origGetMInfo, origGetMMax, origBuyM
	_G.C_MerchantFrame = origCMerchant
	_G.GetMoney = origMoney
	ns.CaptureMerchantVendorPrices = origCapture
	app.getBagCountByID = origGetBag
	_G.C_Container = origCContVR
	if _G.C_Timer and origTimerAfter then _G.C_Timer.After = origTimerAfter end
end
runVendorRecognitionRegressions()

local function runReloadPersistenceRegressions()
	local savedQueue = MerchantMasterDB.craftOrderQueue
	local savedRows = app.rawUnifiedShoppingRows
	local savedActiveRows = app.activeShoppingRows
	local savedSpentAH

	MerchantMasterDB.craftOrderQueue = {
		{ idx = 1, spellID = 7257, outputItemID = 6049, qty = 3 },
	}
	local sig1 = app.getOrderFlowCartSignature()
	check(type(sig1) == "string" and sig1:find("cq:", 1, true) ~= nil,
		"getOrderFlowCartSignature encodes queued craft orders deterministically")

	local persistRows = {
		{ isMainRow = true, mainGroupKey = "rp1", name = "Fire Protection Potion", itemID = 6049, spellID = 7257, prof = "alchemy", qty = 3, sourceKind = "craft_order", sourceLabel = "Crafting Order",
			reagents = { { itemID = 4402, name = "Small Flame Sac", qty = 1 }, { itemID = 3372, name = "Leaded Vial", qty = 1 } } },
		{ indent = 1, mainGroupKey = "rp1", name = "Small Flame Sac", itemID = 4402, qty = 3, ahUnitPrice = 400 },
		{ indent = 1, mainGroupKey = "rp1", name = "Firefin Snapper", itemID = 6359, qty = 0, ownedUsed = 4 },
		{ indent = 1, mainGroupKey = "rp1", name = "Leaded Vial", itemID = 3372, qty = 3, isVendor = true, vendorUnitPrice = 40 },
	}
	of.LoadFromShoppingRows(persistRows, {
		title = "Reload Progress Cart",
		cartSig = sig1,
		ownershipProvider = function(id)
			if id == 6359 then return { bags = 0, mail = 4, bank = 0, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	local ahSt = of.GetState().stages.ah
	ahSt.items[1].bought = 2
	ahSt.items[1].remaining = 1
	ahSt.spentCopper = 800
	savedSpentAH = ahSt.spentCopper
	local colSt = of.GetState().stages.collect
	colSt.items[1].collected = 3
	colSt.items[1].remaining = 1
	local venSt = of.GetState().stages.vendor
	venSt.items[1].bought = 1
	venSt.items[1].remaining = 2
	venSt.spentCopper = 40
	local crSt = of.GetState().stages.craft
	crSt.tasks[1].completedCrafts = 1
	crSt.tasks[1].remainingCrafts = 2
	of.SetActiveStage("craft")

	local blob = MerchantMasterDB.orderFlowState
	check(type(blob) == "table" and blob.cartSig == sig1 and blob.activeStage == "craft",
		"SaveState persists OrderFlow snapshot into MerchantMasterDB.orderFlowState")
	check(blob.stages.ah.items[1].bought == 2 and blob.stages.collect.items[1].collected == 3
		and blob.stages.vendor.items[1].bought == 1 and blob.stages.craft.tasks[1].completedCrafts == 1,
		"Serialized snapshot stores partial counters across ALL 4 stages (AH/Collect/Vendor/Craft)")

	-- Simulate fresh /reload Lua VM: wipe in-memory state via ClearSavedState, re-inject saved SavedVariables, call RestoreState()
	local diskSnapshot = blob
	of.ClearSavedState()
	check(not of.HasAnyItems() and MerchantMasterDB.orderFlowState == nil,
		"ClearSavedState clears both memory and MerchantMasterDB.orderFlowState")
	MerchantMasterDB.orderFlowState = diskSnapshot
	local restoredOk = of.RestoreState()
	check(restoredOk == true and of.HasActiveSessionForSig(sig1) == true and of.GetActiveStage() == "craft",
		"RestoreState recovers session & cartSig after simulated /reload")
	local rSt = of.GetState()
	check(rSt.stages.ah.items[1].bought == 2 and rSt.stages.ah.items[1].remaining == 1 and rSt.stages.ah.spentCopper == savedSpentAH,
		"Restored Stage 1 AH preserves bought=2, remaining=1, and spentCopper")
	check(rSt.stages.collect.items[1].collected == 3 and rSt.stages.collect.items[1].remaining == 1,
		"Restored Stage 2 Collect preserves collected=3 and remaining=1")
	check(rSt.stages.vendor.items[1].bought == 1 and rSt.stages.vendor.items[1].remaining == 2 and rSt.stages.vendor.spentCopper == 40,
		"Restored Stage 3 Vendor preserves bought=1, remaining=2, and spentCopper")
	check(rSt.stages.craft.tasks[1].completedCrafts == 1 and rSt.stages.craft.tasks[1].remainingCrafts == 2,
		"Restored Stage 4 Craft preserves completedCrafts=1 and remainingCrafts=2")

	-- Re-opening via sendShoppingRowsToBuyer when cart signature matches reuses restored progress instead of resetting!
	app.sendShoppingRowsToBuyer(persistRows, "Reload Progress Cart")
	local afterSendSt = of.GetState()
	check(afterSendSt.stages.ah.items[1].bought == 2 and afterSendSt.stages.craft.tasks[1].completedCrafts == 1,
		"Re-opening Send to AH / Task List after /reload keeps all stage counters intact")
	app.exitAHBuyingMode(false)

	-- Changing cart order (sig2 ~= sig1) rebuilds with preserveProgress=true so partial progress carries over cleanly
	MerchantMasterDB.craftOrderQueue[1].qty = 4
	local sig2 = app.getOrderFlowCartSignature()
	check(sig2 ~= sig1, "Changing craft queue changes getOrderFlowCartSignature")
	persistRows[1].qty = 4
	persistRows[2].qty = 4
	app.sendShoppingRowsToBuyer(persistRows, "Expanded Cart")
	local afterGrowSt = of.GetState()
	check(afterGrowSt.stages.ah.items[1].needed == 4 and afterGrowSt.stages.ah.items[1].bought == 2
		and afterGrowSt.stages.craft.tasks[1].neededCrafts == 4 and afterGrowSt.stages.craft.tasks[1].completedCrafts == 1,
		"Expanding cart preserves existing bought/completedCrafts counters while updating needed totals")
	cb.MarkBought(1)
	check(MerchantMasterDB.orderFlowState and MerchantMasterDB.orderFlowState.stages.ah.items[1].status == "done",
		"cb.MarkBought(1) automatically persists status='done' to MerchantMasterDB.orderFlowState")
	app.exitAHBuyingMode(false)

	-- Empty Cart clears persisted orderFlowState
	app.clearUnifiedShoppingList()
	check(MerchantMasterDB.orderFlowState == nil and not of.HasAnyItems(),
		"clearUnifiedShoppingList clears MerchantMasterDB.orderFlowState and in-memory OrderFlow")

	MerchantMasterDB.craftOrderQueue = savedQueue
	app.rawUnifiedShoppingRows = savedRows
	app.activeShoppingRows = savedActiveRows
end
runReloadPersistenceRegressions()

-- 15. Stage 5 Sell (100% Auctionator-Parity AH Selling + Bag Grid + Vendor Channel)
local function runStage5AuctionatorParityTests()
	local of = app.orderFlow
	local origAH = _G.C_AuctionHouse
	local origCCont = _G.C_Container
	local origAHF = _G.AuctionHouseFrame
	local origMF = _G.MerchantFrame
	local origIL = _G.ItemLocation
	local origGetTime = _G.GetTime
	local origTimerAfter = _G.C_Timer and _G.C_Timer.After
	local origGetItemInfo = _G.GetItemInfo
	local origCItem = _G.C_Item
	local origSetOverrideClick = _G.SetOverrideBindingClick
	local origClearOverride = _G.ClearOverrideBindings
	local origInCombat = _G.InCombatLockdown
	local origShiftDown = _G.IsShiftKeyDown
	local origGetMoney = _G.GetMoney

	-- 0. Zero legacy symbols / Bindings.xml removed
	local legLo, legHi = "dr" .. "ip", "Dr" .. "ip"
	check(_G.BINDING_HEADER_MERCHANTMASTER == nil and _G["MerchantMaster" .. legHi .. "PostFromKey"] == nil,
		"Zero legacy keybind globals remain after removal")
	check(of.SetSellMode == nil and of["Start" .. legHi] == nil and of["Tick" .. legHi] == nil and of["Get" .. legHi .. "DueItems"] == nil
		and of["Set" .. legHi .. "ItemConfig"] == nil and of["SetAll" .. legHi .. "Enabled"] == nil and of["PostNextDue" .. legHi] == nil,
		"Zero legacy scheduling APIs remain on OrderFlow")
	check(modal.sellModeStdBtn == nil and modal["sellMode" .. legHi .. "Btn"] == nil and modal["sell" .. legHi .. "Bar"] == nil
		and modal[legLo .. "TickFrame"] == nil and modal[legLo .. "WheelBtn"] == nil,
		"Zero legacy mode/panel widgets remain on cartBuyerModal")
	check(modal.buyBtn and modal.buyBtn.GetName and modal.buyBtn:GetName() == "MerchantMasterTaskActionBtn",
		"Task Strip primary button renamed to MerchantMasterTaskActionBtn")
	local tab = ns.AHSellTab
	check(tab ~= nil, "ns.AHSellTab module loaded")
	tab.EnsureAttached()
	check(tab.postBtn and tab.postBtn.GetName and tab.postBtn:GetName() == "MerchantMasterSellPostBtn",
		"MM Sell primary Post button owns global name MerchantMasterSellPostBtn")
	check(modal.stageBtns.sell == nil and modal.sellForm == nil and modal.sellBagPane == nil,
		"Task Strip has 4 stages with no inline Stage 5 Sell widgets")
	local fBind = io.open("../Bindings.xml", "r")
	if fBind then fBind:close() end
	check(fBind == nil, "Bindings.xml has been deleted from addon root")

	local mockNow = 5000
	local scheduledTimers = {}
	_G.GetTime = function() return mockNow end
	if _G.C_Timer then
		_G.C_Timer.After = function(delay, fn)
			if not delay or delay <= 0 then
				fn()
			else
				scheduledTimers[#scheduledTimers + 1] = { at = mockNow + delay, fn = fn, fired = false }
			end
		end
	end
	local function advanceTimers(sec)
		mockNow = mockNow + sec
		for _, t in ipairs(scheduledTimers) do
			if not t.fired and mockNow >= t.at then
				t.fired = true
				t.fn()
			end
		end
	end

	local mockMoney = 5000000
	_G.GetMoney = function() return mockMoney end
	local mockShift = false
	_G.IsShiftKeyDown = function() return mockShift end
	local mockInCombat = false
	_G.InCombatLockdown = function() return mockInCombat end
	local overrideBindCalls = {}
	local clearOverrideCalls = 0
	_G.SetOverrideBindingClick = function(owner, prio, key, btnName, mouseBtn)
		overrideBindCalls[#overrideBindCalls + 1] = { owner = owner, prio = prio, key = key, btn = btnName, mouse = mouseBtn }
	end
	_G.ClearOverrideBindings = function(owner)
		clearOverrideCalls = clearOverrideCalls + 1
	end

	local itemMetaMap = {
		[81001] = { name = "Daily Potion A", quality = 1, itemLevel = 35, maxStack = 20, sellPrice = 200, classID = 0, isReagent = false },
		[81002] = { name = "Daily Elixir B", quality = 2, itemLevel = 40, maxStack = 20, sellPrice = 300, classID = 0, isReagent = false },
		[81003] = { name = "Vendor Craft C", quality = 1, itemLevel = 20, maxStack = 20, sellPrice = 500, classID = 7, isReagent = true },
		[81004] = { name = "Bag Herb D", quality = 1, itemLevel = 15, maxStack = 20, sellPrice = 50, classID = 7, isReagent = true },
		[81005] = { name = "Tempered Blade", quality = 3, itemLevel = 58, maxStack = 1, sellPrice = 4000, classID = 2, isReagent = false },
		[81008] = { name = "Runed Ring", quality = 3, itemLevel = 52, maxStack = 1, sellPrice = 1500, classID = 4, isReagent = false },
		[81009] = { name = "Silver Dagger", quality = 2, itemLevel = 44, maxStack = 1, sellPrice = 1000, classID = 2, isReagent = false },
		[81010] = { name = "Caged Whelp", quality = 3, itemLevel = 1, maxStack = 1, sellPrice = 0, classID = 17, isReagent = false },
	}
	local mockDoesExist = true
	_G.GetItemInfo = function(idOrLink)
		local id = tonumber(idOrLink)
		if not id and type(idOrLink) == "string" then
			id = tonumber(idOrLink:match("item:(%d+)"))
		end
		local m = id and itemMetaMap[id] or nil
		if m then
			local lnk = (type(idOrLink) == "string" and idOrLink:find("|H", 1, true)) and idOrLink
				or ("|cffffffff|Hitem:" .. tostring(id) .. "::::::::60:::::::|h[" .. m.name .. "]|h|r")
			return m.name, lnk, m.quality, m.itemLevel, 1, "Misc", "Misc", m.maxStack, "", 134400, m.sellPrice, m.classID, 0, 0, 0, nil, m.isReagent
		end
		if origGetItemInfo then return origGetItemInfo(idOrLink) end
		return nil
	end
	_G.C_Item = {
		GetItemInfo = _G.GetItemInfo,
		GetDetailedItemLevelInfo = function(idOrLink)
			local id = tonumber(idOrLink) or (type(idOrLink) == "string" and tonumber(idOrLink:match("item:(%d+)")))
			return (id and itemMetaMap[id] and itemMetaMap[id].itemLevel) or nil
		end,
		DoesItemExist = function() return mockDoesExist end,
		IsBound = function() return false end,
		GetItemIconByID = function() return 134400 end,
	}

	local bagState = {
		[0] = {
			[1] = { itemID = 81001, stackCount = 5, isLocked = false, isBound = false },
			[2] = { itemID = 81002, stackCount = 6, isLocked = false, isBound = false },
			[3] = { itemID = 81003, stackCount = 4, isLocked = false, isBound = false },
		},
	}
	local function markBagsDirty()
		app.bagsDirty = true
		app.bagCountsDirty = true
		app.cachedBagCountsByID = nil
	end
	markBagsDirty()

	local vendorUseCalls = {}
	local postCommCalls = {}
	local confirmCommCalls = {}
	local postItemCalls = {}
	local confirmItemCalls = {}
	local cancelSellCalls = 0
	local searchCalls = {}
	local mockCommLadder = {}
	local mockItemLadder = {}
	local mockNeedsConfirm = false
	local mockIsNonCommodity = { [81005] = true, [81008] = true, [81009] = true, [81010] = true }
	local mockSellValidByID = {}
	local mockAvailPostCount = nil
	local mockThrottleReady = true
	local mockHasSearchResults = nil
	local mockHasFullComm = nil
	local mockCommDepositOverride = nil

	_G.ItemLocation = {
		CreateFromBagAndSlot = function(_, bag, slot) return { bagID = bag, slotIndex = slot } end,
	}
	_G.C_Container = {
		GetContainerNumSlots = function(b) return (b == 0) and 8 or 0 end,
		GetContainerItemInfo = function(b, s) return bagState[b] and bagState[b][s] or nil end,
		UseContainerItem = function(b, s)
			vendorUseCalls[#vendorUseCalls + 1] = { bag = b, slot = s }
			if bagState[b] and bagState[b][s] then
				bagState[b][s] = nil
				markBagsDirty()
			end
		end,
	}
	_G.C_AuctionHouse = {
		IsThrottledMessageSystemReady = function() return mockThrottleReady end,
		IsSellItemValid = function(loc)
			local slot = loc and bagState[loc.bagID] and bagState[loc.bagID][loc.slotIndex]
			if slot and mockSellValidByID[slot.itemID] ~= nil then return mockSellValidByID[slot.itemID] end
			return true
		end,
		GetAvailablePostCount = function(loc)
			return mockAvailPostCount
		end,
		GetItemCommodityStatus = function(loc)
			local slot = loc and bagState[loc.bagID] and bagState[loc.bagID][loc.slotIndex]
			if slot and mockIsNonCommodity[slot.itemID] then return 1 end
			return 2
		end,
		GetItemKeyFromItem = function(loc)
			local slot = bagState[loc.bagID] and bagState[loc.bagID][loc.slotIndex]
			local id = slot and slot.itemID or 0
			local m = itemMetaMap[id]
			return {
				itemID = id,
				itemLevel = (not mockIsNonCommodity[id]) and 0 or (m and m.itemLevel or 0),
				itemSuffix = 0,
				battlePetSpeciesID = 0,
			}
		end,
		MakeItemKey = function(id, ilvl, suf, sp)
			return { itemID = id, itemLevel = ilvl or 0, itemSuffix = suf or 0, battlePetSpeciesID = sp or 0 }
		end,
		GetItemKeyInfo = function(k)
			return { itemID = k.itemID, isCommodity = not mockIsNonCommodity[k.itemID] }
		end,
		SendSellSearchQuery = function(k, sorts, splitOwned)
			searchCalls[#searchCalls + 1] = { fn = "SendSellSearchQuery", key = k, sorts = sorts, splitOwned = splitOwned }
		end,
		SendSearchQuery = function(k, sorts, splitOwned)
			searchCalls[#searchCalls + 1] = { fn = "SendSearchQuery", key = k, sorts = sorts, splitOwned = splitOwned }
		end,
		HasSearchResults = function()
			if mockHasSearchResults ~= nil then return mockHasSearchResults end
			return true
		end,
		HasFullCommoditySearchResults = function()
			if mockHasFullComm ~= nil then return mockHasFullComm end
			return true
		end,
		GetCommoditySearchResultsQuantity = function(id)
			local tot = 0
			for _, r in ipairs(mockCommLadder[id] or {}) do tot = tot + (r.quantity or 1) end
			return tot
		end,
		GetNumCommoditySearchResults = function(id) return mockCommLadder[id] and #mockCommLadder[id] or 0 end,
		GetCommoditySearchResultInfo = function(id, idx) return mockCommLadder[id] and mockCommLadder[id][idx] or nil end,
		GetNumItemSearchResults = function(k)
			local id = type(k) == "table" and k.itemID or k
			return mockItemLadder[id] and #mockItemLadder[id] or 0
		end,
		GetItemSearchResultInfo = function(k, idx)
			local id = type(k) == "table" and k.itemID or k
			return mockItemLadder[id] and mockItemLadder[id][idx] or nil
		end,
		CalculateCommodityDeposit = function(id, dur, qty)
			if mockCommDepositOverride ~= nil then return mockCommDepositOverride end
			local mult = (dur == 1 and 15) or (dur == 2 and 60) or 180
			return mult * (qty or 1)
		end,
		CalculateItemDeposit = function(loc, dur, qty)
			local mult = (dur == 1 and 25) or (dur == 2 and 100) or 300
			return mult * (qty or 1)
		end,
		PostCommodity = function(loc, dur, qty, unitPrice)
			postCommCalls[#postCommCalls + 1] = { loc = loc, dur = dur, qty = qty, unitPrice = unitPrice }
			return mockNeedsConfirm
		end,
		PostItem = function(loc, dur, qty, bid, buyout)
			postItemCalls[#postItemCalls + 1] = { loc = loc, dur = dur, qty = qty, bid = bid, buyout = buyout }
			return mockNeedsConfirm
		end,
		ConfirmPostCommodity = function(loc, dur, qty, unitPrice)
			confirmCommCalls[#confirmCommCalls + 1] = { loc = loc, dur = dur, qty = qty, unitPrice = unitPrice }
		end,
		ConfirmPostItem = function(loc, dur, qty, bid, buyout)
			confirmItemCalls[#confirmItemCalls + 1] = { loc = loc, dur = dur, qty = qty, bid = bid, buyout = buyout }
		end,
		CancelSell = function()
			cancelSellCalls = cancelSellCalls + 1
		end,
	}
	local ahShown = true
	local mfShown = false
	_G.AuctionHouseFrame = { IsShown = function() return ahShown end }
	_G.MerchantFrame = { IsShown = function() return mfShown end }

	-- 1. Load crafted outputs & check Forever defaults (8h duration=2, Match undercut="match") + clean serialization
	local sellRows = {
		{ isMainRow = true, mainGroupKey = "m1", name = "Daily Potion A", itemID = 81001, spellID = 98001, prof = "alchemy", qty = 5, sourceKind = "spread", sourceLabel = "Daily Spread" },
		{ name = "Sub Oil", itemID = 81099, spellID = 98099, prof = "alchemy", qty = 5, makeMyself = true, indent = 1, mainGroupKey = "m1" },
		{ isMainRow = true, mainGroupKey = "m2", name = "Daily Elixir B", itemID = 81002, spellID = 98002, prof = "alchemy", qty = 6, sourceKind = "spread", sourceLabel = "Daily Spread" },
		{ isMainRow = true, mainGroupKey = "m3", name = "Vendor Craft C", itemID = 81003, spellID = 98003, prof = "alchemy", qty = 4, sourceKind = "craft_order", sourceLabel = "Craft Order" },
	}
	local cnts = of.LoadFromShoppingRows(sellRows, { title = "Auctionator Parity Sell Test" })
	check(cnts.sell == 3, "Stage 5 Sell extracted 3 main craft outputs (excluding sub-craft), got " .. tostring(cnts.sell))
	local sl = of.GetState().stages.sell
	check(sl.duration == 2 and sl.undercutMode == "match",
		"Stage 5 defaults match Auctionator Forever 16001: duration=2 (8h) and undercutMode='match'")
	check(sl.mode == nil and sl[legLo .. "Running"] == nil, "Stage 5 state contains zero legacy mode/running fields")
	local serClean = of.SerializeState()
	check(serClean and serClean.stages and serClean.stages.sell
		and serClean.stages.sell.duration == 2 and serClean.stages.sell.undercutMode == "match"
		and serClean.stages.sell.mode == nil and serClean.stages.sell.items[1][legLo .. "Enabled"] == nil,
		"SerializeState preserves Stage 5 parity fields with zero legacy fields")

	-- Open MM Sell AH Tab & verify AH-scoped SPACE override shortcut binds cleanly (priority=false!)
	overrideBindCalls = {}
	clearOverrideCalls = 0
	tab.SelectTab()
	check(tab.IsShown(), "tab.SelectTab() displays standalone MM Sell tab")
	check(#overrideBindCalls == 1 and overrideBindCalls[1].key == "SPACE"
		and overrideBindCalls[1].prio == false and overrideBindCalls[1].btn == "MerchantMasterSellPostBtn",
		"MM Sell binds non-priority SPACE override to MerchantMasterSellPostBtn while at AH")
	check(#searchCalls >= 1 and searchCalls[#searchCalls].splitOwned == true,
		"MM Sell search passes splitOwnedItems=true")

	-- 2. Commodity UI: Unit Price label, Bid Price hidden, Duration 2h/8h/24h, Undercut cycle, Copper precision, Deposit + Total Price
	check(tab.sellForm:IsShown() and not tab.sellBidRow:IsShown(),
		"Commodity shows sellForm and hides Bid Price row")
	check(stripColors(tab.sellPriceLbl:GetText()) == "Unit Price",
		"Commodity price label is 'Unit Price', got: " .. tostring(stripColors(tab.sellPriceLbl:GetText())))
	check(tab.sellDurBtns[1]:GetText() == "2h" and tab.sellDurBtns[2]:GetText() == "8h" and tab.sellDurBtns[3]:GetText() == "24h",
		"Duration pills show WoW Forever 2h / 8h / 24h")
	check(tab.sellMaxBtn and not tab.sellMaxBtn:IsEnabled(),
		"Max button is auto-disabled when Quantity == GetPostLimit() (5 == 5)")

	-- Quantity clamp & Max re-enable
	of.SetSellItemQty(1, 2)
	tab.Render()
	check(of.GetSellPostQty(sl.items[1]) == 2 and tab.sellMaxBtn:IsEnabled(),
		"Reducing qty to 2 enables Max button")
	of.SetSellItemQty(1, 99)
	check(of.GetSellPostQty(sl.items[1]) == 5, "Quantity > GetPostLimit() auto-clamps down to GetPostLimit (5)")
	of.SetSellItemQty(1, 2)
	tab.sellMaxBtn:Click("LeftButton")
	check(of.GetSellPostQty(sl.items[1]) == 5 and not tab.sellMaxBtn:IsEnabled(),
		"Clicking Max sets qty=5 and disables Max button")

	-- Duration click immediately recalculates Deposit
	tab.sellDurBtns[1]:Click("LeftButton")
	local dep2h = of.ComputeSellDeposit(sl.items[1], 1, 5)
	local depTxt2h = stripColors(tab.sellDepFs:GetText())
	tab.sellDurBtns[3]:Click("LeftButton")
	local dep24h = of.ComputeSellDeposit(sl.items[1], 3, 5)
	local depTxt24h = stripColors(tab.sellDepFs:GetText())
	check(sl.duration == 3 and dep24h > dep2h and depTxt2h ~= depTxt24h and depTxt24h:find("Deposit:", 1, true) ~= nil,
		"Switching Duration 2h -> 24h immediately recalculates live Deposit (" .. tostring(dep2h) .. " -> " .. tostring(dep24h) .. ")")
	tab.sellDurBtns[2]:Click("LeftButton")

	-- 3. Live Current Prices ladder (commodities) + self-match + undercut modes + click-row-to-price + Shift-click exact match
	mockCommLadder[81001] = {
		{ unitPrice = 25000, quantity = 10, numOwnerItems = 0, containsOwnerItem = false, owners = { "RivalA" }, totalNumberOfOwners = 1, timeLeftSeconds = 7200 },
		{ unitPrice = 25500, quantity = 5, numOwnerItems = 5, containsOwnerItem = true, owners = { "player" }, totalNumberOfOwners = 1, timeLeftSeconds = 3600 },
		{ unitPrice = 26000, quantity = 40, numOwnerItems = 0, containsOwnerItem = false, owners = { "RivalB", "RivalC" }, totalNumberOfOwners = 4, timeLeftSeconds = 1800 },
	}
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 81001)
	check(tab.sellPricesBox:IsShown() and tab.sellPricesRows[1]:IsShown() and tab.sellPricesRows[2]:IsShown() and tab.sellPricesRows[3]:IsShown(),
		"Current Prices panel renders 3 live commodity rows")
	check(stripColors(tab.sellPricesCol1:GetText()) == "Unit Price" and stripColors(tab.sellPricesCol3:GetText()) == "Avail"
		and stripColors(tab.sellPricesCol5:GetText()) == "Owned?"
		and not tab.sellPricesCol2:IsShown() and not tab.sellPricesCol4:IsShown(),
		"Current Prices commodity headers show Unit Price | Avail | Owned?")
	check(tab.sellPricesVDivs and tab.sellPricesVDivs[1]:IsShown() and tab.sellPricesVDivs[2]:IsShown()
		and not tab.sellPricesVDivs[3]:IsShown() and not tab.sellPricesVDivs[4]:IsShown(),
		"Current Prices commodity mode displays 2 vertical column guide lines")
	check(stripColors(tab.sellPricesRows[2].c5:GetText()) == "Yes" and stripColors(tab.sellPricesRows[1].c5:GetText()) == "-",
		"Current Prices marks own listing with 'Yes' and competitor with '-'")
	check(tab.sellPricesRows[1].c1:GetText():find("UI-GoldIcon", 1, true) ~= nil,
		"Current Prices formats money with WoW Gold/Silver/Copper coin icons")
	check(of.ComputeSellUnitPrice(sl.items[1]) == 25000,
		"Default Match (0% LIFO) matches competitor price 25000c")

	-- Cycle undercut: match -> 1c -> 1s -> pct -> match
	tab.sellUcBtn:Click("LeftButton")
	check(sl.undercutMode == "1c" and of.ComputeSellUnitPrice(sl.items[1]) == 24999,
		"Undercut -1c computes 24999c (exact 1c copper precision on Forever 16001)")
	tab.sellUcBtn:Click("LeftButton")
	check(sl.undercutMode == "1s" and of.ComputeSellUnitPrice(sl.items[1]) == 24900,
		"Undercut -1s computes 24900c")
	tab.sellUcBtn:Click("LeftButton")
	check(sl.undercutMode == "pct" and of.ComputeSellUnitPrice(sl.items[1]) == 24750,
		"Undercut -1% computes 24750c")
	of.SetSellUndercutMode("1c")

	-- Click competitor row 3 (26000c) -> sets customPrice = 25999c (undercut -1c); Shift-click row 3 -> exact 26000c; Click own row 2 -> exact 25500c!
	tab.sellPricesRows[3]:Click("LeftButton")
	check(sl.items[1].customPrice == 25999, "Left-clicking competitor Current Prices row sets undercut price (25999c)")
	mockShift = true
	tab.sellPricesRows[3]:Click("LeftButton")
	mockShift = false
	check(sl.items[1].customPrice == 26000, "Shift-clicking competitor Current Prices row sets exact price (26000c)")
	tab.sellPricesRows[2]:Click("LeftButton")
	check(sl.items[1].customPrice == 25500, "Left-clicking own Current Prices row matches exact price (25500c) without undercutting self")

	-- Copper precision G/S/C input + zero mid-keystroke corruption + live Total Price update
	sl.items[1].customPrice = 25500
	tab.Render()
	tab.sellPriceGBox:SetText("1")
	tab.sellPriceSBox:SetText("23")
	tab.sellPriceCBox:SetText("45")
	local onTxtPrice = tab.sellPriceGBox:GetScript("OnTextChanged")
	if onTxtPrice then onTxtPrice(tab.sellPriceGBox, true) end
	check(sl.items[1].customPrice == 25500,
		"Typing in sellPriceGBox does NOT corrupt model mid-keystroke (stays 25500)")
	local liveTotRaw = stripColors(tab.sellTotalFs:GetText())
	check(liveTotRaw:find("UI-GoldIcon", 1, true) ~= nil and liveTotRaw:find("6|T", 1, true) ~= nil
		and liveTotRaw:find("17|T", 1, true) ~= nil and liveTotRaw:find("25|T", 1, true) ~= nil,
		"Typing updates Total Price live with coin icons (5 * 1g23s45c = 6g 17s 25c), got: " .. tostring(liveTotRaw))
	local onLost = tab.sellPriceCBox:GetScript("OnEditFocusLost")
	if onLost then onLost(tab.sellPriceCBox) end
	check(sl.items[1].customPrice == 12345,
		"OnEditFocusLost commits exact copper precision 1g 23s 45c -> 12345c (no 1s rounding)")

	-- Self-match when player is lowest commodity seller (containsOwnerItem + owners[1]=="player")
	sl.items[1].customPrice = nil
	mockCommLadder[81001] = {
		{ unitPrice = 28000, quantity = 5, numOwnerItems = 5, containsOwnerItem = true, owners = { "player" }, totalNumberOfOwners = 1 },
		{ unitPrice = 29000, quantity = 20, numOwnerItems = 0, containsOwnerItem = false, owners = { "RivalX" }, totalNumberOfOwners = 1 },
	}
	of.ScanSellItemMarket(1, "select")
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 81001)
	check(sl.items[1].liveUnit == 28000 and sl.items[1].liveIsOwn == true and of.ComputeSellUnitPrice(sl.items[1]) == 28000,
		"Self-match when lowest row is player: matches 28000c without undercutting self even under -1c rule")

	-- Empty-result retry guard (SearchScan.lua:45,59)
	searchCalls = {}
	mockHasSearchResults = false
	of.ScanSellItemMarket(1, "select")
	local beforeRetry = #searchCalls
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 81001)
	check(#searchCalls == beforeRetry + 1 and sl.pendingSearch ~= nil,
		"Empty-result retry guard retries once when HasSearchResults()==false")
	mockHasSearchResults = true
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 81001)
	check(sl.pendingSearch == nil, "Retry search completes cleanly once HasSearchResults()==true")
	mockHasSearchResults = nil

	-- 4. Low-Price Commodity Threshold & Below-Vendor Warning Confirmation Gate
	mockCommLadder[81001] = {
		{ unitPrice = 50000, quantity = 500, numOwnerItems = 0, containsOwnerItem = false, owners = { "MarketA" }, totalNumberOfOwners = 1 },
	}
	of.ScanSellItemMarket(1, "select")
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 81001)
	check(sl.items[1].priceThreshold and math.abs(sl.items[1].priceThreshold - 19000) < 1,
		"Commodity PriceWarningThreshold computed accurately (19000c for 5g market), got: " .. tostring(sl.items[1].priceThreshold))
	check(tab.postAllBtn == nil and tab.doneBtn == nil and tab.skipBtn == nil
		and tab.sellChBtn == nil and tab.sellVendorBar == nil,
		"Removed legacy UI buttons (postAllBtn/doneBtn/skipBtn/sellChBtn/sellVendorBar)")
	check(tab.cancelBtn ~= nil and not tab.cancelBtn:IsShown(),
		"Context-only cancelBtn is hidden when idle")
	of.SetSellItemPrice(1, 15000, 0) -- 1g 50s <= 1g 90s threshold!
	local okLow, errLow, whyLow = of.PostSellItem(1)
	check(okLow == false and errLow == "confirm_low_price" and whyLow == "low_price",
		"Posting <= PriceWarningThreshold triggers low_price confirmation gate")
	check(tab.postBtn:GetText() == "Confirm Low Price" and tab.cancelBtn:IsShown() and tab.cancelBtn:GetText() == "Cancel",
		"UI switches to 'Confirm Low Price' and reveals context-only 'Cancel' when warningConfirm is pending")
	tab.cancelBtn:Click("LeftButton")
	check(sl.warningConfirm == nil and tab.postBtn:GetText() == "Post" and not tab.cancelBtn:IsShown(),
		"Clicking context-only Cancel clears warningConfirm and hides cancelBtn cleanly")

	-- Below-vendor guard: vendorSell=200c; posting at 205c -> after 5% cut floor(205*0.95)=194 < 200 -> below_vendor!
	-- Also verify sellVendorRow warning tint + StaticPopup MERCHANTMASTER_CONFIRM_BELOW_VENDOR flow!
	local savedPopupShow = _G.StaticPopup_Show
	local savedPopupHide = _G.StaticPopup_Hide
	local shownPopups, hiddenPopups = {}, {}
	local dlgBV = _G.StaticPopupDialogs and _G.StaticPopupDialogs["MERCHANTMASTER_CONFIRM_BELOW_VENDOR"]
	check(dlgBV ~= nil and dlgBV.button1 == "Post on AH" and dlgBV.button2 == "Cancel"
		and type(dlgBV.text) == "string" and dlgBV.text:find("5%% AH cut", 1, true) ~= nil,
		"StaticPopupDialogs['MERCHANTMASTER_CONFIRM_BELOW_VENDOR'] registered with exact buttons & 5% AH cut text")
	_G.StaticPopup_Show = function(which, a1, a2, a3, a4)
		check(a3 == nil and a4 == nil, "StaticPopup_Show passes strictly (which, arg1, arg2) with no 4th/5th args")
		local formatted = string.format(dlgBV.text, a1, a2)
		shownPopups[#shownPopups + 1] = { which = which, a1 = a1, a2 = a2, formatted = formatted }
	end
	_G.StaticPopup_Hide = function(which)
		hiddenPopups[#hiddenPopups + 1] = which
	end
	of.SetSellItemPrice(1, 205, 0)
	tab.Render()
	check(tab.sellVendorRow ~= nil and tab.sellVendorRow._isBelowVendor == true
		and stripColors(tab.sellVendorValFs:GetText()):find("(> AH Net!)", 1, true) ~= nil,
		"sellVendorRow highlights warning and displays '(> AH Net!)' when 95% AH net < vendor value")
	tab.postBtn:Click("LeftButton")
	check(sl.warningConfirm ~= nil and sl.warningConfirm.reason == "below_vendor" and tab.cancelBtn:IsShown(),
		"Clicking Post below vendor value (after 5% AH cut) triggers below_vendor confirmation gate")
	check(#shownPopups == 1 and shownPopups[1].which == "MERCHANTMASTER_CONFIRM_BELOW_VENDOR"
		and shownPopups[1].formatted:find("5% AH cut", 1, true) ~= nil
		and shownPopups[1].formatted:find("more at vendor).", 1, true) ~= nil,
		"Clicking Post on below_vendor shows MERCHANTMASTER_CONFIRM_BELOW_VENDOR StaticPopup with valid 2-arg WoW format")
	-- Cancel via popup OnCancel clears warningConfirm and hides cancelBtn
	dlgBV.OnCancel()
	check(sl.warningConfirm == nil and not tab.cancelBtn:IsShown(),
		"MERCHANTMASTER_CONFIRM_BELOW_VENDOR OnCancel clears warningConfirm cleanly")
	-- Re-trigger via Enter key in price box, then verify item change auto-hides StaticPopup
	tab.sellPriceGBox:GetScript("OnEnterPressed")(tab.sellPriceGBox)
	check(#shownPopups == 2 and sl.warningConfirm ~= nil and sl.warningConfirm.reason == "below_vendor",
		"Pressing Enter on below_vendor also shows MERCHANTMASTER_CONFIRM_BELOW_VENDOR StaticPopup")
	of.SelectSellItem(2)
	check(#hiddenPopups >= 1 and hiddenPopups[#hiddenPopups] == "MERCHANTMASTER_CONFIRM_BELOW_VENDOR",
		"Changing active item auto-hides MERCHANTMASTER_CONFIRM_BELOW_VENDOR StaticPopup")
	of.SelectSellItem(1)
	-- Verify OnAccept ("Post on AH") confirms and dispatches PostCommodity, and OnAuctionHouseClosed auto-hides popup
	tab.postBtn:Click("LeftButton")
	check(#shownPopups == 3 and sl.warningConfirm ~= nil and sl.warningConfirm.reason == "below_vendor",
		"Re-clicking Post below vendor opens popup #3")
	local beforeHideAH = #hiddenPopups
	tab.OnAuctionHouseClosed()
	check(#hiddenPopups == beforeHideAH + 1 and hiddenPopups[#hiddenPopups] == "MERCHANTMASTER_CONFIRM_BELOW_VENDOR",
		"OnAuctionHouseClosed auto-hides MERCHANTMASTER_CONFIRM_BELOW_VENDOR StaticPopup")
	tab.SelectTab()
	of.CancelPendingSellPost("clear")
	postCommCalls = {}
	tab.postBtn:Click("LeftButton")
	check(sl.warningConfirm ~= nil and sl.warningConfirm.reason == "below_vendor",
		"Below-vendor confirmation armed before popup OnAccept")
	dlgBV.OnAccept()
	check(sl.warningConfirm == nil and #postCommCalls == 1 and postCommCalls[1].unitPrice == 205,
		"MERCHANTMASTER_CONFIRM_BELOW_VENDOR OnAccept ('Post on AH') dispatches PostCommodity at 205c")
	of.CancelPendingSellPost("clear")
	-- Direct backend check for exact floor(effectiveUnitPrice * 0.95) < vendorPrice (qty=1 edge)
	local warnR1, warnMsg1 = of.GetSellConfirmationWarning(1, { qty = 1, unitPrice = 210 })
	check(warnR1 == "below_vendor" and type(warnMsg1) == "string" and warnMsg1:find("5% AH cut", 1, true) ~= nil,
		"GetSellConfirmationWarning checks per-unit floor(210*0.95)=199 < 200 -> below_vendor")
	local warnR2 = of.GetSellConfirmationWarning(1, { qty = 1, unitPrice = 211 })
	check(warnR2 ~= "below_vendor",
		"GetSellConfirmationWarning allows floor(211*0.95)=200 >= 200 (not below_vendor)")
	_G.StaticPopup_Show = savedPopupShow
	_G.StaticPopup_Hide = savedPopupHide

	-- 5. PostCommodity + needsConfirmation -> ConfirmPostCommodity + ComposeAuctionPostedMessage + auto-advance
	of.SetSellItemPrice(1, 49999, 0)
	mockNeedsConfirm = true
	postCommCalls = {}
	confirmCommCalls = {}
	local okP1, stP1 = of.PostSellItem(1)
	check(okP1 == true and stP1 == "awaiting_confirm" and #postCommCalls == 1 and postCommCalls[1].qty == 5 and postCommCalls[1].unitPrice == 49999 and postCommCalls[1].dur == 2,
		"PostCommodity passes exact (loc, dur=2, qty=5, unitPrice=49999) and enters awaiting_confirm")
	check(tab.postBtn:GetText() == "Confirm Post" and tab.cancelBtn:IsShown() and tab.cancelBtn:GetText() == "Cancel",
		"UI switches to 'Confirm Post' and reveals context-only 'Cancel' when needsConfirmation==true")
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_AUCTION_CREATED", 55499)
	check(sl.pendingPost ~= nil and sl.pendingPost.state == "awaiting_confirm",
		"AUCTION_HOUSE_AUCTION_CREATED ignored while awaiting_confirm")
	local okC1, stC1 = of.ConfirmPendingSellPost()
	check(okC1 == true and stC1 == "confirming" and #confirmCommCalls == 1 and confirmCommCalls[1].unitPrice == 49999,
		"ConfirmPostCommodity called with exact params")
	bagState[0][1] = nil
	markBagsDirty()
	searchCalls = {}
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_AUCTION_CREATED", 55501)
	tab.Render()
	check(sl.items[1].status == "done" and sl.items[1].remaining == 0 and sl.activeIndex == 1
		and #searchCalls >= 1 and searchCalls[1].key.itemID == sl.items[1].itemID,
		"AUCTION_HOUSE_AUCTION_CREATED marks item 1 done, stays on item 1, and refreshes same item")
	check(stripColors(tab.activeFs:GetText()) == "No Item Selected"
		and tab.iconDropBtn.countFs:GetText() == ""
		and stripColors(tab.spotSubFs:GetText()):find("Posted!", 1, true) ~= nil
		and tab.postBtn:GetText() == "Item Posted"
		and not tab.postBtn:IsEnabled()
		and tab.sellRefreshBtn:IsEnabled(),
		"Single post clears top-left slot as posted confirmation while keeping Refresh enabled and 'Item Posted' when pending items remain")
	check((of.GetState().notice or ""):find("Daily Potion Ax5", 1, true) ~= nil
		and (of.GetState().notice or ""):find("each)", 1, true) ~= nil,
		"Posted summary matches ComposeAuctionPostedMessage format for qty>1, got: " .. tostring(of.GetState().notice))
	mockNeedsConfirm = false

	-- 6. Non-Commodity UI & all 4 Bid/Buyout combinations + Equipment (iLvl) + BattlePet (petLvl) + OnEnterPressed posts!
	bagState[0][4] = { itemID = 81005, stackCount = 1, isLocked = false, isBound = false,
		hyperlink = "|cff0070dd|Hitem:81005::::::::60:::::::|h[Tempered Blade]|h|r" }
	bagState[0][5] = { itemID = 81005, stackCount = 1, isLocked = false, isBound = false,
		hyperlink = "|cff0070dd|Hitem:81005::::::::60:::::::|h[Tempered Blade]|h|r" }
	bagState[0][6] = { itemID = 81010, stackCount = 1, isLocked = false, isBound = false,
		hyperlink = "|cff0070dd|Hbattlepet:200:25:3:100:100:100:0|h[Caged Whelp]|h|r" }
	markBagsDirty()

	-- Add weapon from bag (no explicit qty) -> defaults to postQty = 1 (even though 2 in bags!)
	of.AddBagItemToSell(81005, nil, { name = "Tempered Blade", itemLink = bagState[0][4].hyperlink, classID = 2, itemLevel = 58, quality = 3, useDefaultQty = true })
	local bladeIdx = #sl.items
	tab.Render()
	check(of.GetSellPostQty(sl.items[bladeIdx]) == 1 and of.GetSellPostLimit(sl.items[bladeIdx]) == 2,
		"Weapon bag item defaults Quantity to 1 (while GetPostLimit == 2)")
	check(stripColors(tab.activeFs:GetText()) == "Tempered Blade (58)",
		"Equipment header appends (itemLevel), got: " .. tostring(stripColors(tab.activeFs:GetText())))
	check(stripColors(tab.sellPriceLbl:GetText()) == "Buyout Price" and tab.sellBidRow:IsShown(),
		"Non-commodity shows 'Buyout Price' and displays Bid Price row")

	-- Non-commodity Current Prices ladder filters by itemLevel (58 matches, 40 ignored!), aggregates identical rows (Avail=2), and shows 5 cols: Buyout Price | Bid Price | Avail | iLvl | Owned?
	mockItemLadder[81005] = {
		{ itemKey = { itemID = 81005, itemLevel = 40, itemSuffix = 0 }, buyoutAmount = 10000, bidAmount = 8000, quantity = 1, containsOwnerItem = false },
		{ itemKey = { itemID = 81005, itemLevel = 58, itemSuffix = 0 }, buyoutAmount = 90000, bidAmount = 75000, quantity = 1, containsOwnerItem = false, owners = { "SmithX" } },
		{ itemKey = { itemID = 81005, itemLevel = 58, itemSuffix = 0 }, buyoutAmount = 90000, bidAmount = 75000, quantity = 1, containsOwnerItem = false, owners = { "SmithY" } },
		{ itemKey = { itemID = 81005, itemLevel = 58, itemSuffix = 0 }, buyoutAmount = 95000, bidAmount = 80000, quantity = 1, containsOwnerItem = true, owners = { "player" } },
	}
	of.ScanSellItemMarket(bladeIdx, "select")
	ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 81005, itemLevel = 0, itemSuffix = 0 })
	check(#(sl.items[bladeIdx].currentListings or {}) == 2 and sl.items[bladeIdx].liveUnit == 90000
		and sl.items[bladeIdx].currentListings[1].quantity == 2 and sl.items[bladeIdx].currentListings[2].containsOwnerItem == true,
		"Equipment search filters iLvl 40, aggregates duplicate competitor rows (Avail=2), and keeps owned row separate")
	check(stripColors(tab.sellPricesCol1:GetText()) == "Buyout Price" and stripColors(tab.sellPricesCol2:GetText()) == "Bid Price"
		and stripColors(tab.sellPricesCol3:GetText()) == "Avail" and stripColors(tab.sellPricesCol4:GetText()) == "iLvl"
		and stripColors(tab.sellPricesCol5:GetText()) == "Owned?"
		and tab.sellPricesCol2:IsShown() and tab.sellPricesCol4:IsShown(),
		"Equipment Current Prices displays all 5 columns: Buyout Price | Bid Price | Avail | iLvl | Owned?")
	check(stripColors(tab.sellPricesRows[1].c3:GetText()) == "2" and stripColors(tab.sellPricesRows[1].c4:GetText()) == "58"
		and stripColors(tab.sellPricesRows[2].c5:GetText()) == "Yes",
		"Equipment Current Prices renders aggregated Avail=2, iLvl=58, and Owned?=Yes")
	check(tab.sellPricesVDivs and tab.sellPricesVDivs[1]:IsShown() and tab.sellPricesVDivs[2]:IsShown()
		and tab.sellPricesVDivs[3]:IsShown() and tab.sellPricesVDivs[4]:IsShown(),
		"Equipment Current Prices shows all 4 vertical column guide lines")
	-- Click row 1 (90000 BO, 75000 Bid) under -1c -> sets BO=89999 and carries Bid=75000 (< 89999)
	tab.sellPricesRows[1]:Click("LeftButton")
	check(sl.items[bladeIdx].customPrice == 89999 and sl.items[bladeIdx].bidPrice == 75000,
		"Clicking non-commodity row sets undercut Buyout (89999c) and carries Bid (75000c)")

	-- Mode (a): Bid >= Buyout > 0 -> Post MUST be DISABLED!
	of.SetSellItemPrice(bladeIdx, 80000, 80000)
	tab.Render()
	local okGe, errGe = of.GetSellPostButtonState(bladeIdx)
	check(okGe == false and errGe == "bid_ge_buyout" and not tab.postBtn:IsEnabled(),
		"Post button is DISABLED when Bid >= Buyout > 0")
	of.SetSellItemPrice(bladeIdx, 80000, 85000)
	check(of.GetSellPostButtonState(bladeIdx) == false, "Post button stays DISABLED when Bid > Buyout > 0")

	-- Mode (b): Buyout-only (Buyout=90000, Bid=0) -> PostItem(loc, dur, 1, nil, 90000)
	postItemCalls = {}
	of.SetSellItemPrice(bladeIdx, 90000, 0)
	local okBO = of.PostSellItem(bladeIdx)
	check(okBO == true and #postItemCalls == 1 and postItemCalls[1].bid == nil and postItemCalls[1].buyout == 90000,
		"Non-commodity Buyout-only calls PostItem(loc, dur, 1, nil, 90000)")
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_AUCTION_CREATED", 55601)
	check((of.GetState().notice or ""):find("buyout at", 1, true) ~= nil and not (of.GetState().notice or ""):find("bidding at", 1, true),
		"Single-item buyout-only message formats 'buyout at <price>'")

	-- Mode (c): Bid + Buyout (Buyout=90000, Bid=70000) -> PostItem(loc, dur, 1, 70000, 90000)
	bagState[0][4] = { itemID = 81005, stackCount = 1, isLocked = false, isBound = false,
		hyperlink = "|cff0070dd|Hitem:81005::::::::60:::::::|h[Tempered Blade]|h|r" }
	markBagsDirty()
	of.SelectSellItem(bladeIdx)
	check(sl.items[bladeIdx].bidPrice == 0, "Selecting item clears bidPrice to 0")
	of.SetSellItemPrice(bladeIdx, 90000, 70000)
	local okBB = of.PostSellItem(bladeIdx)
	check(okBB == true and #postItemCalls == 2 and postItemCalls[2].bid == 70000 and postItemCalls[2].buyout == 90000,
		"Non-commodity Bid+Buyout calls PostItem(loc, dur, 1, 70000, 90000)")
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_AUCTION_CREATED", 55602)
	check((of.GetState().notice or ""):find("bidding at", 1, true) ~= nil and (of.GetState().notice or ""):find("buyout at", 1, true) ~= nil,
		"Single-item bid+buyout message includes both 'bidding at' and 'buyout at'")

	-- Mode (d): Bid-only (Buyout=0, Bid=60000) via OnEnterPressed -> PostItem(loc, dur, 1, 60000, nil)
	bagState[0][4] = { itemID = 81005, stackCount = 1, isLocked = false, isBound = false,
		hyperlink = "|cff0070dd|Hitem:81005::::::::60:::::::|h[Tempered Blade]|h|r" }
	markBagsDirty()
	of.SelectSellItem(bladeIdx)
	of.SetSellItemQty(bladeIdx, 1)
	of.SetSellItemPrice(bladeIdx, 0, 0)
	tab.Render()
	tab.sellBidGBox:SetText("6")
	tab.sellBidSBox:SetText("0")
	tab.sellBidCBox:SetText("0")
	tab.sellBidGBox:GetScript("OnEnterPressed")(tab.sellBidGBox)
	check(#postItemCalls == 3 and postItemCalls[3].bid == 60000 and postItemCalls[3].buyout == nil,
		"Bid-only (Buyout=0, Bid=60000) via OnEnterPressed commits and invokes PostItem(loc, dur, 1, 60000, nil)")
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_AUCTION_CREATED", 55603)

	-- Battlepet header formatting (petLevel) & default qty = 1
	of.AddBagItemToSell(81010, nil, { name = "Caged Whelp", itemLink = bagState[0][6].hyperlink, classID = 17, quality = 3, useDefaultQty = true })
	local petIdx = #sl.items
	tab.Render()
	check(stripColors(tab.activeFs:GetText()) == "Caged Whelp (25)" and of.GetSellPostQty(sl.items[petIdx]) == 1,
		"Battlepet appends (petLevel) and defaults qty=1, got: " .. tostring(stripColors(tab.activeFs:GetText())))
	of.RemoveSellItem(petIdx)
	of.RemoveSellItem(bladeIdx)

	-- 7. Backend SkipSellItem + Refresh + Bags grid + Sell Queue tab + backend Vendor channel (AH form stays shown in MM Sell!)
	of.SelectSellItem(2)
	local okSkip, nextSkipIdx = of.SkipSellItem()
	check(okSkip == true and nextSkipIdx == 3 and sl.activeIndex == 3,
		"Backend OrderFlow.SkipSellItem advances to next pending item (3)")
	-- Vendor channel clears SPACE override binding while MM Sell keeps AH pricing form visible cleanly
	clearOverrideCalls = 0
	of.ToggleSellItemChannel(3)
	check(sl.items[3].channel == "vendor", "ToggleSellItemChannel switches item 3 to Vendor")
	mfShown = true
	of.OnMerchantShow()
	tab.Render()
	tab.SyncSpaceBinding()
	check(clearOverrideCalls >= 1 and tab.sellForm:IsShown() and tab.sellVendorBar == nil,
		"Vendor channel clears SPACE override while MM Sell keeps AH pricing form visible cleanly")
	local soldVend = of.SellAllToVendor()
	check(soldVend == 1 and #vendorUseCalls == 1 and sl.items[3].status == "done",
		"SellAllToVendor sells vendor-flagged item 3 and marks it done")
	mfShown = false
	of.OnMerchantClosed()

	-- Only item 2 remains pending -> backend SkipSellItem returns false
	of.SelectSellItem(2)
	tab.Render()
	local okSkip2, errSkip2 = of.SkipSellItem()
	check(okSkip2 == false and errSkip2 == "no_other_pending",
		"Backend OrderFlow.SkipSellItem returns no_other_pending when no other pending item exists")

	-- Left-side Bags grid & Sell Queue mini-tab per-row X remove
	bagState[0][7] = { itemID = 81004, stackCount = 9, isLocked = false, isBound = false }
	markBagsDirty()
	tab.Render()
	check(tab.sellBagPane:IsShown(), "MM Sell left-side categorized Bags pane is shown")
	local tileNew = nil
	for _, tile in ipairs(tab.sellBagTiles or {}) do
		if tile:IsShown() and tile._bagRec and tile._bagRec.itemID == 81004 then tileNew = tile; break end
	end
	check(tileNew ~= nil, "Bag grid displays sellable unqueued item 81004")
	tileNew:Click("LeftButton")
	check(#sl.items == 4 and sl.items[4].itemID == 81004 and of.GetSellPostQty(sl.items[4]) == 9,
		"Clicking commodity bag tile adds item 81004 with default qty = GetPostLimit() (9)")
	tab.SetSubTab("queue")
	check(tab.sellQueueView:IsShown(), "Sell Queue sub-tab displays queue view")
	local row4 = nil
	for _, r in ipairs(tab.sellQueueRows or {}) do
		if r:IsShown() and r._itemIndex == 4 then row4 = r; break end
	end
	check(row4 ~= nil and row4.removeBtn and row4.removeBtn:IsShown() and row4.chBtn == nil,
		"Sell Queue row displays per-row X remove button with channel toggle removed")
	row4.removeBtn:Click("LeftButton")
	check(#sl.items == 3, "Clicking per-row X removes item from Sell queue")
	tab.SetSubTab("prices")

	-- 8. GetMoney() < deposit block + Throttle events (all 6) & 8s wedge + UI_ERROR_MESSAGE + Multisell + Refresh lastItemInfo + Combat safety
	of.SelectSellItem(2)
	of.SetSellItemPrice(2, 20000, 0)
	mockMoney = 5
	tab.Render()
	local okLowGold, errLowGold = of.PostSellItem(2)
	check(okLowGold == false and errLowGold == "insufficient_money" and not tab.postBtn:IsEnabled(),
		"GetMoney() < deposit blocks PostSellItem and disables Post button")
	local lowDepRaw = tab.sellDepValFs:GetText()
	local _, cOpen = lowDepRaw:gsub("|cff", "")
	local _, cClose = lowDepRaw:gsub("|r", "")
	check(cOpen > 0 and cOpen == cClose and lowDepRaw:find("UI-", 1, true) ~= nil,
		"Low-money deposit applies override danger hex with balanced |cff/|r tags (no nested/unmatched |r): " .. tostring(lowDepRaw))
	mockMoney = 5000000

	-- Throttle gating across events + 8s safety valve
	mockThrottleReady = false
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED")
	check(of.GetSellPrimaryAction().enabled == false, "Throttled AH disables Post button")
	mockNow = mockNow + 9
	check(of.GetSellPrimaryAction().enabled == true, "Throttle wedge safety valve releases after 8s")
	mockThrottleReady = true
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")

	-- ConfirmPostItem watchdog + UI_ERROR_MESSAGE recovery + AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED
	scheduledTimers = {}
	mockNeedsConfirm = true
	of.PostSellItem(2, { qty = 1, duration = 1, unitPrice = 20000 })
	of.ConfirmPendingSellPost()
	advanceTimers(16)
	check(sl.pendingPost == nil, "ConfirmPendingSellPost watchdog clears wedged post after 15s")
	mockNeedsConfirm = false
	of.PostSellItem(2, { qty = 1, duration = 1, unitPrice = 20000 })
	ns.MarketScan.HandleEvent("UI_ERROR_MESSAGE", 1, "Out of range.")
	check(sl.pendingPost ~= nil, "Unrelated UI_ERROR_MESSAGE ignored during post")
	ns.MarketScan.HandleEvent("UI_ERROR_MESSAGE", 1, "Not enough money")
	check(sl.pendingPost == nil, "AH UI_ERROR_MESSAGE cleanly clears pendingPost")
	of.PostSellItem(2, { qty = 1, duration = 1, unitPrice = 20000 })
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
	check(sl.pendingPost == nil, "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED cleanly clears pendingPost")

	-- Multisell START / UPDATE / FAILURE (partial credit) + CancelSell on cancel during multisell
	bagState[0][5] = { itemID = 81009, stackCount = 3, isLocked = false, isBound = false }
	markBagsDirty()
	of.AddBagItemToSell(81009, 3)
	local msIdx = #sl.items
	of.SetSellItemQty(msIdx, 3)
	of.SetSellItemPrice(msIdx, 15000, 0)
	local okMs = of.PostSellItem(msIdx)
	check(okMs == true and sl.pendingPost ~= nil, "Started qty=3 non-commodity multisell")
	ns.MarketScan.HandleEvent("AUCTION_MULTISELL_START", 3)
	check(sl.pendingPost.multisellActive == true and (of.GetState().notice or ""):find("0/3", 1, true) ~= nil,
		"AUCTION_MULTISELL_START activates multisell progress tracking")
	ns.MarketScan.HandleEvent("AUCTION_MULTISELL_UPDATE", 2, 3)
	bagState[0][5].stackCount = 1
	markBagsDirty()
	ns.MarketScan.HandleEvent("AUCTION_MULTISELL_FAILURE")
	check(sl.pendingPost == nil and sl.items[msIdx].soldQty == 2 and sl.items[msIdx].remaining == 1,
		"AUCTION_MULTISELL_FAILURE credits partial 2/3 posted and cleans up")

	-- Cancel during active multisell calls C_AuctionHouse.CancelSell()
	bagState[0][5].stackCount = 2
	markBagsDirty()
	of.SetSellItemQty(msIdx, 2)
	of.SetSellItemPrice(msIdx, 15000, 0)
	of.PostSellItem(msIdx)
	ns.MarketScan.HandleEvent("AUCTION_MULTISELL_START", 2)
	cancelSellCalls = 0
	of.CancelPendingSellPost("user_cancel")
	check(cancelSellCalls == 1 and sl.pendingPost == nil,
		"Cancelling active multisell calls C_AuctionHouse.CancelSell()")
	of.RemoveSellItem(msIdx)

	-- Refresh scans lastItemInfo when queue becomes empty!
	of.RemoveSellItem(3); of.RemoveSellItem(2); of.RemoveSellItem(1)
	check(#sl.items == 0 and sl.lastItemInfo ~= nil, "Queue empty retains sl.lastItemInfo for Refresh")
	searchCalls = {}
	local okRefLast = of.RefreshSellSearch()
	check(okRefLast == true and #searchCalls == 1 and searchCalls[1].key.itemID == sl.lastItemInfo.itemID,
		"RefreshSellSearch re-scans sl.lastItemInfo when Sell queue is empty")
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", sl.lastItemInfo.itemID)

	-- 9. Strict Review Regression Tests (Fixes 1-8)
	local focusBoxes = {
		tab.sellQtyBox, tab.sellPriceGBox, tab.sellPriceSBox, tab.sellPriceCBox,
		tab.sellBidGBox, tab.sellBidSBox, tab.sellBidCBox,
	}
	local curFocusedBox = nil
	for _, bx in ipairs(focusBoxes) do
		if bx then
			bx._origHasFocus = bx.HasFocus
			bx._origClearFocus = bx.ClearFocus
			bx._origSetFocus = bx.SetFocus
			bx.HasFocus = function(self) return curFocusedBox == self end
			bx.ClearFocus = function(self)
				if curFocusedBox == self then
					curFocusedBox = nil
					local lost = self.GetScript and self:GetScript("OnEditFocusLost")
					if lost then lost(self) end
				end
			end
			bx.SetFocus = function(self)
				if curFocusedBox and curFocusedBox ~= self then
					curFocusedBox:ClearFocus()
				end
				curFocusedBox = self
			end
		end
	end

	-- Ensure fresh commodity item 81004 in bags (10x)
	bagState[0][7] = { itemID = 81004, stackCount = 10, isLocked = false, isBound = false }
	markBagsDirty()
	of.AddBagItemToSell(81004, 10, { name = "Bag Herb D", useDefaultQty = true })
	local rIdx = #sl.items
	mockCommLadder[81004] = {
		{ itemID = 81004, unitPrice = 25000, quantity = 15, owners = { "RivalHerb" }, containsOwnerItem = false },
		{ itemID = 81004, unitPrice = 28000, quantity = 8, owners = { "SellerTwo" }, containsOwnerItem = false },
	}
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 81004)
	of.SetSellUndercutMode("match")
	tab.Render()

	-- Fix #3: Tabbing/blurring through Qty -> G -> S -> C without editing must NOT lock customPrice
	check(sl.items[rIdx].customPrice == nil, "Fix #3 precondition: customPrice starts nil (follows live AH)")
	tab.sellQtyBox:SetFocus()
	tab.sellQtyBox:GetScript("OnTabPressed")(tab.sellQtyBox)
	tab.sellPriceGBox:GetScript("OnTabPressed")(tab.sellPriceGBox)
	tab.sellPriceSBox:GetScript("OnTabPressed")(tab.sellPriceSBox)
	tab.sellPriceCBox:GetScript("OnEditFocusLost")(tab.sellPriceCBox)
	check(sl.items[rIdx].customPrice == nil,
		"Fix #3: Tabbing/blurring through Price boxes without editing does NOT lock customPrice")
	of.SetSellUndercutMode("1c")
	check((of.ComputeSellUnitPrice(sl.items[rIdx])) == 24999,
		"Fix #3: Undercut Rule still recalculates live price cleanly after tabbing through inputs")
	of.SetSellUndercutMode("match")

	-- Fix #4: Setting Quantity = 0 must NOT bounce back to GetPostLimit(); Max stays enabled, Post stays disabled
	of.SetSellItemQty(rIdx, 0)
	tab.Render()
	local qZero, limZero = of.GetSellPostQty(sl.items[rIdx])
	check(qZero == 0 and limZero == 10 and tab.sellQtyBox:GetText() == "0"
		and tab.sellMaxBtn:IsEnabled() == true and tab.postBtn:IsEnabled() == false,
		"Fix #4: User-entered Quantity=0 stays 0 across Render(), keeps Max enabled and Post disabled")
	tab.sellMaxBtn:Click("LeftButton")
	check(of.GetSellPostQty(sl.items[rIdx]) == 10, "Fix #4: Clicking Max restores full GetPostLimit (10) from 0")

	-- Fix #2: Clicking Current Prices row / Max / - / + / Rule while an EditBox has focus clears focus & leaves zero stale hybrid price
	tab.sellPriceGBox:SetFocus()
	tab.sellPriceGBox:SetText("99")
	tab.sellPricesRows[2]:Click("LeftButton")
	check((not tab.sellPriceGBox:HasFocus()) and tab.sellPriceGBox:GetText() == "2" and tab.sellPriceSBox:GetText() == "80" and tab.sellPriceCBox:GetText() == "0",
		"Fix #2: Clicking Current Prices row while Gold box focused clears focus and updates ALL G/S/C boxes (no hybrid 99g80s)")
	tab.sellQtyBox:SetFocus()
	tab.sellQtyBox:SetText("99")
	tab.sellQtyMinus:Click("LeftButton")
	check((not tab.sellQtyBox:HasFocus()) and tab.sellQtyBox:GetText() == "9",
		"Fix #2: Clicking Qty - while Qty box focused clears focus and updates box text cleanly")
	tab.sellPriceGBox:SetFocus()
	tab.sellPriceGBox:SetText("77")
	tab.sellUcBtn:Click("LeftButton")
	check((not tab.sellPriceGBox:HasFocus()) and tab.sellPriceGBox:GetText() == "2",
		"Fix #2: Clicking Rule button while Price box focused clears focus and updates price boxes cleanly")
	of.SetSellUndercutMode("match")

	-- Fix #1: Typing new Price & Qty in focused EditBoxes and clicking Post commits BOTH before PostCommodity
	postCommCalls = {}
	tab.sellQtyBox:SetFocus()
	tab.sellQtyBox:SetText("4")
	tab.sellQtyBox:GetScript("OnTextChanged")(tab.sellQtyBox, true)
	tab.sellPriceGBox:SetFocus()
	tab.sellPriceGBox:SetText("3")
	tab.sellPriceSBox:SetText("15")
	tab.sellPriceCBox:SetText("7")
	tab.sellPriceGBox:GetScript("OnTextChanged")(tab.sellPriceGBox, true)
	tab.postBtn:Click("LeftButton")
	check(#postCommCalls == 1 and postCommCalls[1].qty == 4 and postCommCalls[1].unitPrice == 31507
		and (not tab.sellPriceGBox:HasFocus()) and (not tab.sellQtyBox:HasFocus()),
		"Fix #1: Clicking Post while EditBoxes focused commits qty=4 & price=31507 and clears focus BEFORE PostCommodity")
	bagState[0][7].stackCount = 6
	markBagsDirty()
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_AUCTION_CREATED", 55701)

	-- Fix #5: Completing the LAST item in queue refreshes Current Prices directly into the displayed ladder (Owned? = Yes)
	-- Also test backend PostAllNext and throttled post_complete_refresh 0.45s retry!
	postCommCalls = {}
	of.SetSellItemQty(rIdx, 6)
	tab.Render()
	tab.sellPriceGBox:SetFocus()
	tab.sellPriceGBox:SetText("2")
	tab.sellPriceSBox:SetText("45")
	tab.sellPriceCBox:SetText("0")
	tab.sellPriceGBox:GetScript("OnTextChanged")(tab.sellPriceGBox, true)
	tab.commitSellInputsAndClearFocus()
	of.PostAllNext()
	check(#postCommCalls == 1 and postCommCalls[1].qty == 6 and postCommCalls[1].unitPrice == 24500,
		"Fix #1: Backend PostAllNext posts committed 24500 via PostCommodity")
	bagState[0][7] = nil
	markBagsDirty()
	searchCalls = {}
	-- Simulate AH throttle busy immediately after posting -> 0.45s retry MUST still dispatch post_complete_refresh even though item is done!
	scheduledTimers = {}
	mockThrottleReady = false
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_AUCTION_CREATED", 55702)
	check(sl.items[rIdx].status == "done" and #searchCalls == 0 and #scheduledTimers >= 1,
		"Addendum #4: Throttled post_complete_refresh schedules 0.45s retry instead of dropping refresh")
	mockThrottleReady = true
	advanceTimers(1)
	check(#searchCalls >= 1,
		"Addendum #4: 0.45s throttled post_complete_refresh retry dispatches live refresh even when item status=='done'")
	mockCommLadder[81004] = {
		{ itemID = 81004, unitPrice = 24500, quantity = 6, owners = { "player" }, containsOwnerItem = true },
		{ itemID = 81004, unitPrice = 25000, quantity = 15, owners = { "RivalHerb" }, containsOwnerItem = false },
	}
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 81004)
	tab.Render()
	check(tab.sellPricesRows[1] and tab.sellPricesRows[1]:IsShown()
		and tab.sellPricesRows[1]._listing and tab.sellPricesRows[1]._listing.containsOwnerItem == true
		and stripColors(tab.sellPricesRows[1].c5:GetText()) == "Yes",
		"Fix #5: Post-completion Current Prices immediately displays player's new listing (Owned? = Yes)")
	check(tab.postBtn:GetText() == "All Posted!" and of.GetSellPrimaryAction().label == "All Posted!"
		and not tab.postBtn:IsEnabled()
		and stripColors(tab.activeFs:GetText()) == "No Item Selected"
		and stripColors(tab.spotMetaFs:GetText()):find("Posted", 1, true) ~= nil,
		"Completing all items clears top-left slot, updates button to 'All Posted!', and keeps Current Prices on posted item")

	-- Fix #8: Action row geometry (postBtn + sellRefreshBtn height 30 + context-only cancelBtn hidden) & non-clipped spotSubFs/activeFs
	check(tab.sellRefreshBtn:GetWidth() >= 56 and tab.sellRefreshBtn:GetHeight() == 30
		and not tab.cancelBtn:IsShown()
		and tab.sellQtyMinus:GetWidth() >= 22 and tab.sellQtyPlus:GetWidth() >= 22,
		"Fix #8: Sell Refresh (h=30) sits on Row 4 with cancelBtn hidden when idle and non-truncating widths")
	local subH = tab.spotSubFs and tab.spotSubFs.GetHeight and tab.spotSubFs:GetHeight() or 0
	local actH = tab.activeFs and tab.activeFs.GetHeight and tab.activeFs:GetHeight() or 0
	check(subH >= 12 and actH >= 16,
		"Fix #8: MM Sell spotSubFs (h=" .. tostring(subH) .. ") and activeFs (h=" .. tostring(actH) .. ") have non-clipping heights")

	-- Fix #6: Non-commodity click buyout-only row preserves existing Bid when existingBid < newBuyout, clears when >= newBuyout
	bagState[0][4] = { itemID = 81005, stackCount = 1, isLocked = false, isBound = false,
		hyperlink = "|cff0070dd|Hitem:81005::::::::60:::::::|h[Tempered Blade]|h|r" }
	markBagsDirty()
	of.AddBagItemToSell(81005, 1, { name = "Tempered Blade", itemLink = bagState[0][4].hyperlink, classID = 2, itemLevel = 58, quality = 3 })
	local b6Idx = #sl.items
	of.SetSellItemPrice(b6Idx, 120000, 50000)
	of.SelectSellListingPrice({ price = 90000, bidPrice = nil, containsOwnerItem = false }, true)
	check(sl.items[b6Idx].customPrice == 90000 and sl.items[b6Idx].bidPrice == 50000,
		"Fix #6: Clicking buyout-only row (90000) preserves existing Bid (50000 < 90000)")
	of.SelectSellListingPrice({ price = 40000, bidPrice = nil, containsOwnerItem = false }, true)
	check(sl.items[b6Idx].customPrice == 40000 and sl.items[b6Idx].bidPrice == 0,
		"Fix #6: Clicking lower buyout-only row (40000) clears existing Bid (50000 >= 40000)")
	of.RemoveSellItem(b6Idx)

	-- Fix #7: Battlepet battlePetSpeciesID mismatch rejected + unbagged 0c commodity deposit returns 0, true
	bagState[0][6] = { itemID = 82800, stackCount = 1, isLocked = false, isBound = false,
		hyperlink = "|cff0070dd|Hbattlepet:239:25:3:1400:260:260:0000000000000000|h[Caged Whelp]|h|r" }
	mockIsNonCommodity[82800] = true
	itemMetaMap[82800] = { name = "Pet Cage", quality = 3, itemLevel = 1, maxStack = 1, sellPrice = 0, classID = 17, isReagent = false }
	markBagsDirty()
	of.AddBagItemToSell(82800, 1, { name = "Caged Whelp", itemLink = bagState[0][6].hyperlink, classID = 17, quality = 3 })
	local bpIdx = #sl.items
	mockItemLadder[82800] = {
		{ itemKey = { itemID = 82800, itemLevel = 25, itemSuffix = 0, battlePetSpeciesID = 999 }, buyoutAmount = 11111, quantity = 1, owners = { "WrongPet" }, containsOwnerItem = false },
	}
	ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 82800, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 999 })
	check(sl.pendingSearch ~= nil and (not sl.items[bpIdx].listingsScanned),
		"Fix #7: ITEM_SEARCH_RESULTS_UPDATED with mismatched battlePetSpeciesID (999 vs 239) is rejected")
	mockItemLadder[82800] = {
		{ itemKey = { itemID = 82800, itemLevel = 25, itemSuffix = 0, battlePetSpeciesID = 239 }, buyoutAmount = 77700, quantity = 1, owners = { "RightPet" }, containsOwnerItem = false },
	}
	ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 82800, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 239 })
	check(sl.items[bpIdx].listingsScanned == true and sl.items[bpIdx].liveUnit == 77700,
		"Fix #7: Matching battlePetSpeciesID (239) is accepted and populates liveUnit=77700")
	of.RemoveSellItem(bpIdx)
	mockCommDepositOverride = 0
	local depZero, depLive = of.ComputeSellDeposit({ itemID = 81004, isCommodity = true, vendorSell = 500 }, 2, 5)
	mockCommDepositOverride = nil
	check(depZero == 0 and depLive == true,
		"Fix #7: Unbagged commodity CalculateCommodityDeposit returning 0c returns (0, true) instead of fallback 100c")
	of.RemoveSellItem(rIdx)
	for _, bx in ipairs(focusBoxes) do
		if bx then
			bx.HasFocus = bx._origHasFocus
			bx.ClearFocus = bx._origClearFocus
			bx.SetFocus = bx._origSetFocus
			bx._origHasFocus, bx._origClearFocus, bx._origSetFocus = nil, nil, nil
		end
	end

	-- Combat lockdown defers SPACE override clear & HideTab clears cleanly
	of.AddBagItemToSell(81004, 5)
	tab.Render()
	clearOverrideCalls = 0
	mockInCombat = true
	tab.SyncSpaceBinding(true)
	check(clearOverrideCalls == 0 and tab.IsSpacePendingSync() == true,
		"InCombatLockdown defers ClearOverrideBindings cleanly without error")
	mockInCombat = false
	fireEvent("PLAYER_REGEN_ENABLED")
	check(tab.IsSpacePendingSync() == false, "PLAYER_REGEN_ENABLED flushes deferred SPACE binding sync")
	clearOverrideCalls = 0
	tab.HideTab()
	check(clearOverrideCalls >= 1 and not tab.IsShown(), "tab.HideTab clears SPACE override binding cleanly")

	-- Cleanup
	tab.HideTab()
	_G.C_AuctionHouse = origAH
	_G.C_Container = origCCont
	_G.AuctionHouseFrame = origAHF
	_G.MerchantFrame = origMF
	_G.ItemLocation = origIL
	_G.GetTime = origGetTime
	if _G.C_Timer and origTimerAfter then _G.C_Timer.After = origTimerAfter end
	_G.GetItemInfo = origGetItemInfo
	_G.C_Item = origCItem
	_G.SetOverrideBindingClick = origSetOverrideClick
	_G.ClearOverrideBindings = origClearOverride
	_G.InCombatLockdown = origInCombat
	_G.IsShiftKeyDown = origShiftDown
	_G.GetMoney = origGetMoney
end
runStage5AuctionatorParityTests()

---------------------------------------------------------------------------------------------------
-- 14. Audit Fixes Regressions (#46 Backend + #47 UI/Events + #48 Live-WoW Scan Timeout)
---------------------------------------------------------------------------------------------------
local function runAuditFix46_47_48Regressions()
	local of = app.orderFlow
	local origAH = _G.C_AuctionHouse
	local origAHF = _G.AuctionHouseFrame
	local origMF = _G.MerchantFrame
	local origBF = _G.BankFrame
	local origTSF = _G.TradeSkillFrame
	local origCF = _G.CraftFrame
	local origCCont = _G.C_Container
	local origIL = _G.ItemLocation
	local origGetTime = _G.GetTime
	local origTimerAfter = _G.C_Timer and _G.C_Timer.After
	local origInCombat = _G.InCombatLockdown
	local origEnum = _G.Enum
	local origGetMNum, origGetMID, origGetMLink, origGetMInfo, origGetMMax, origBuyM =
		_G.GetMerchantNumItems, _G.GetMerchantItemID, _G.GetMerchantItemLink, _G.GetMerchantItemInfo, _G.GetMerchantItemMaxStack, _G.BuyMerchantItem
	local origCMerchant = _G.C_MerchantFrame
	local origCTrade = _G.C_TradeSkillUI
	local origMoney = _G.GetMoney
	local origSearchAH = app.searchAH
	local origGetBag = app.getBagCountByID

	local mockNow = 50000
	_G.GetTime = function() return mockNow end
	local scheduledTimers = {}
	if _G.C_Timer then
		_G.C_Timer.After = function(delay, fn)
			scheduledTimers[#scheduledTimers + 1] = { at = mockNow + (tonumber(delay) or 0), fn = fn }
		end
	end
	local function advanceTimers(sec)
		mockNow = mockNow + sec
		local keep = {}
		local run = {}
		for _, t in ipairs(scheduledTimers) do
			if t.at <= mockNow then run[#run + 1] = t.fn else keep[#keep + 1] = t end
		end
		scheduledTimers = keep
		for _, fn in ipairs(run) do fn() end
	end

	local ahOpen = true
	local ahFrame = CreateFrame("Frame", "Audit46AHFrame", UIParent)
	ahFrame.IsShown = function() return ahOpen end
	_G.AuctionHouseFrame = ahFrame
	local mfFrame = CreateFrame("Frame", "Audit46MerchantFrame", UIParent); mfFrame:Hide()
	_G.MerchantFrame = mfFrame
	local bfFrame = CreateFrame("Frame", "Audit46BankFrame", UIParent); bfFrame:Hide()
	_G.BankFrame = bfFrame
	local tsfFrame = CreateFrame("Frame", "Audit46TSF", UIParent); tsfFrame:Hide()
	_G.TradeSkillFrame = tsfFrame
	local cfFrame = CreateFrame("Frame", "Audit46CF", UIParent); cfFrame:Hide()
	_G.CraftFrame = cfFrame
	local mockCombat = false
	_G.InCombatLockdown = function() return mockCombat end
	_G.GetMoney = function() return 9000000 end
	_G.Enum = {
		PlayerInteractionType = { Merchant = 5, Banker = 8, CharacterBanker = 8, MailInfo = 17 },
		AuctionHouseSortOrder = { Price = 0, Buyout = 4 },
		BagIndex = { CharacterBankTab_1 = 6 },
	}

	local bagState = { [0] = {}, [6] = {} }
	local bankMainSlots = 0
	local usedVendorSlots = {}
	_G.C_Container = {
		GetContainerNumSlots = function(b)
			if b == -1 then return bankMainSlots end
			if b == 0 then return 8 end
			if b == 6 then return 4 end
			return 0
		end,
		GetContainerNumFreeSlots = function(b)
			if b == 0 then return 4, 0 end
			return 0, 0
		end,
		GetContainerItemInfo = function(b, s)
			return bagState[b] and bagState[b][s] or nil
		end,
		UseContainerItem = function(b, s)
			usedVendorSlots[#usedVendorSlots + 1] = { bag = b, slot = s }
		end,
	}
	_G.ItemLocation = {
		CreateFromBagAndSlot = function(a, b, c)
			local bag, slot
			if type(a) == "table" then bag, slot = b, c else bag, slot = a, b end
			return { bagID = bag, slotIndex = slot }
		end,
	}
	app.getBagCountByID = function(id)
		local total = 0
		for s = 1, 8 do
			local it = bagState[0][s]
			if it and it.itemID == id then total = total + (it.stackCount or 1) end
		end
		return total
	end

	local commLadder = {}
	local itemLadder = {}
	local keyInfoMap = {}
	local searchLog = {}
	local mockAH = {
		IsThrottledMessageSystemReady = function() return true end,
		GetItemKeyFromItem = function(loc)
			local info = bagState[loc.bagID] and bagState[loc.bagID][loc.slotIndex]
			if info and info.itemID then return { itemID = info.itemID, itemLevel = info.itemLevel or 0, itemSuffix = 0 } end
			return nil
		end,
		GetItemKeyInfo = function(key)
			return key and keyInfoMap[key.itemID] or nil
		end,
		SendSellSearchQuery = function(key, sorts, minLvl)
			searchLog[#searchLog + 1] = { fn = "SendSellSearchQuery", itemID = key and key.itemID, sortOrder = sorts and sorts[1] and sorts[1].sortOrder }
		end,
		SendSearchQuery = function(key, sorts, minLvl)
			searchLog[#searchLog + 1] = { fn = "SendSearchQuery", itemID = key and key.itemID, sortOrder = sorts and sorts[1] and sorts[1].sortOrder }
		end,
		GetNumCommoditySearchResults = function(id) return commLadder[id] and #commLadder[id] or 0 end,
		GetCommoditySearchResultInfo = function(id, idx) return commLadder[id] and commLadder[id][idx] or nil end,
		GetNumItemSearchResults = function(key)
			local id = type(key) == "table" and key.itemID or key
			return itemLadder[id] and #itemLadder[id] or 0
		end,
		GetItemSearchResultInfo = function(key, idx)
			local id = type(key) == "table" and key.itemID or key
			return itemLadder[id] and itemLadder[id][idx] or nil
		end,
		IsSellItemValid = function(loc)
			local info = bagState[loc.bagID] and bagState[loc.bagID][loc.slotIndex]
			return info ~= nil and not info.isBound and info.ahValid ~= false
		end,
		CalculateItemDeposit = function() return 100 end,
		PostCommodity = function() return false end,
		PostItem = function() return false end,
		StartCommoditiesPurchase = function() end,
		ConfirmCommoditiesPurchase = function() end,
		CancelCommoditiesPurchase = function() end,
		PlaceBid = function() end,
	}
	_G.C_AuctionHouse = mockAH

	-- 1) #47 Blocker #1: cbNoticeFs / cbNoticeBar visible & tinted across stages, hides when empty
	of.LoadFromShoppingRows({
		{ name = "Audit Herb A", itemID = 92001, qty = 5, ahUnitPrice = 500 },
		{ name = "Audit Herb B", itemID = 92002, qty = 5, ahUnitPrice = 600 },
	}, { title = "Audit47 Notice & AH Test" })
	local openedIndices = {}
	app.searchAH = function(name, qty, itemID)
		openedIndices[#openedIndices + 1] = itemID
		return true
	end
	local ahSt = cb.GetState()
	ahSt.items[1].status = "done"; ahSt.items[1].remaining = 0; ahSt.items[1].bought = 5
	app.enterOrderFlowMode("ah")
	check(cb.GetState().activeIndex == 2 and openedIndices[#openedIndices] == 92002,
		"enterOrderFlowMode('ah') opens first pending item #2 (92002), not hardcoded #1")

	local ofSt = of.GetState()
	ofSt.notice = "Deposit too high for test"
	ofSt.noticeKind = "danger"
	modal.Render()
	check(modal.noticeBar:IsShown() and modal.noticeFs:IsShown()
		and stripColors(modal.noticeFs:GetText()) == "Deposit too high for test",
		"cbNoticeBar & cbNoticeFs display live danger notice text")
	local visWithNotice = modal.getVisCap(false, false)
	ofSt.notice = nil
	cb.GetState().notice = nil
	modal.Render()
	check(not modal.noticeBar:IsShown() and not modal.noticeFs:IsShown(),
		"cbNoticeBar & cbNoticeFs auto-hide when notice is cleared")
	local visNoNotice = modal.getVisCap(false, false)
	check(visWithNotice == visNoNotice - 1,
		"getVisCap(hasFilter, hasCap) auto-deducts 1 row when cbNoticeBar is shown (" .. tostring(visWithNotice) .. " vs " .. tostring(visNoNotice) .. ")")

	-- Stage 1 empty/done waiting banner guard + clearItemLiveAH + numOwnerItems subtraction + throttle recovery
	commLadder[92002] = { { unitPrice = 550, quantity = 5, numOwnerItems = 5 } }
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 92002)
	check(cb.GetState().items[2].liveUnit == nil,
		"Stage 1 commodity scan subtracts numOwnerItems and clears stale liveUnit when 0 buyable units remain")
	commLadder[92002] = { { unitPrice = 550, quantity = 6, numOwnerItems = 2 } }
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 92002)
	check(cb.GetState().items[2].liveAvailQty == 4 and cb.GetState().items[2].liveUnit == 550,
		"Stage 1 commodity scan subtracts 2 own items from 6 total -> liveAvailQty=4")
	commLadder[92002] = {}
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 92002)
	check(cb.GetState().items[2].liveUnit == nil and cb.GetState().items[2].liveAvailQty == nil,
		"Empty commodity search clears stale Stage 1 liveUnit/liveAvailQty")
	cb.GetState().items[2].status = "done"; cb.GetState().items[2].remaining = 0; cb.GetState().items[2].bought = 5
	ahOpen = false
	of.OnAuctionHouseClosed()
	modal.Render()
	check(not modal.waitingBanner:IsShown(), "Completed Stage 1 with AH closed does NOT show 'Please open Auction House to start.'")
	ahOpen = true
	of.OnAuctionHouseShow()

	-- 2) #47.3 Stage 2 Collect: '0 in Bank' warning tint + BANKFRAME_CLOSED / PLAYER_INTERACTION_MANAGER Forever Bank Tab scan
	of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "b1", name = "Bank Potion", itemID = 92100, spellID = 99100, prof = "alchemy", qty = 1,
			reagents = { { itemID = 92101, name = "Bank Herb", qty = 4 } } },
		{ indent = 1, mainGroupKey = "b1", name = "Bank Herb", itemID = 92101, qty = 0, ownedUsed = 4 },
	}, {
		title = "Stage 2 Bank Tab Test",
		ownershipProvider = function(id)
			if id == 92101 then return { bags = 0, bank = 4, mail = 0, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	bagState[6][1] = { itemID = 92101, stackCount = 4, isLocked = false,
		hyperlink = "|cffffffff|Hitem:92101::::::::60:::::::|h[Bank Herb]|h|r" }
	bankMainSlots = 0 -- Forever 16001 Character Bank Tabs only (BANK_CONTAINER -1 has 0 slots)
	bfFrame:Show()
	fireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
	check(app.atBank == true and of.GetState().env.atBank == true,
		"PLAYER_INTERACTION_MANAGER_FRAME_SHOW(CharacterBanker) sets app.atBank and env.atBank")
	-- Simulate 0 in bank to check warning tint on '0 in Bank'
	local colItem = of.GetState().stages.collect.items[1]
	colItem.availableHere = 0
	modal.Render()
	local liveTxt = modal.spotLiveFs:GetText() or ""
	check(liveTxt:find("0 in Bank", 1, true) ~= nil and not liveTxt:find("30d158", 1, true),
		"Stage 2 '0 in Bank' uses warning tint instead of green hexPositive, got: " .. tostring(liveTxt))
	-- Close bank with bankMainSlots == 0 -> scanBank still flushes Character Bank Tab!
	bagState[6][1] = { itemID = 92101, stackCount = 2, isLocked = false,
		hyperlink = "|cffffffff|Hitem:92101::::::::60:::::::|h[Bank Herb]|h|r" }
	bfFrame:Hide()
	fireEvent("BANKFRAME_CLOSED")
	check(app.atBank == false and app.char and app.char.bank and app.char.bank["Bank Herb"] == 2,
		"BANKFRAME_CLOSED flushes Forever Character Bank Tab even when BANK_CONTAINER(-1) has 0 slots")

	-- 3) #46 + #47.3 Stage 3 Vendor: 'Done' label, pack-rounded TOTAL COST, Buy All Here disabled when 0 stocked, isPurchasable==false blocked
	_G.GetMerchantNumItems = function() return 2 end
	_G.GetMerchantItemID = function(s) return s == 1 and 92201 or 92202 end
	_G.GetMerchantItemLink = function() return nil end
	_G.GetMerchantItemInfo = nil
	_G.GetMerchantItemMaxStack = function() return 20 end
	local vendBuys = {}
	_G.BuyMerchantItem = function(s, q) vendBuys[#vendBuys + 1] = { slot = s, qty = q } end
	_G.C_MerchantFrame = {
		GetItemInfo = function(slot)
			if slot == 1 then
				return { itemID = 92201, name = "Locked Pattern", price = 5000, stackCount = 1, numAvailable = -1, isPurchasable = false, hasExtendedCost = false }
			elseif slot == 2 then
				return { itemID = 92202, name = "Pack Vial", price = 1000, stackCount = 5, numAvailable = -1, isPurchasable = true, hasExtendedCost = false }
			end
		end,
	}
	of.LoadFromShoppingRows({
		{ name = "Locked Pattern", itemID = 92201, qty = 1, isVendor = true, vendorUnitPrice = 5000 },
	}, { title = "Vendor Locked Test" })
	of.SetActiveStage("vendor")
	mfFrame:Show()
	of.OnMerchantShow()
	modal.Render()
	check(modal.nextBtn:GetText() == "Done", "Stage 3 Vendor cbNextBtn renamed from 'Mark' to 'Done'")
	check(not modal.buyBtn:IsEnabled() and not modal.markBtn:IsEnabled(),
		"Stage 3 disables Buy and Buy All Here when only item is isPurchasable=false")
	local okLock, errLock = of.BuyVendorItem(1)
	check(okLock == false and errLock == "not_purchasable", "BuyVendorItem rejects isPurchasable=false with 'not_purchasable'")

	-- Pack-rounded TOTAL COST: need 3 of 5-pack @ 1000c (10s) -> 1 pack = 10s (NOT 6s)
	of.LoadFromShoppingRows({
		{ name = "Pack Vial", itemID = 92202, qty = 3, isVendor = true, vendorUnitPrice = 200 },
	}, { title = "Vendor Pack Cost Test" })
	of.SetActiveStage("vendor")
	of.OnMerchantShow()
	modal.Render()
	check(stripColors(modal.spotDiffFs:GetText()):find("10s", 1, true) ~= nil,
		"Stage 3 pack-sold TOTAL COST rounds up to full 5-pack cost (10s), got: " .. stripColors(modal.spotDiffFs:GetText()))
	check(modal.markBtn:IsEnabled(), "Stage 3 enables Buy All Here when stocked purchasable item is present")
	mfFrame:Hide()
	of.OnMerchantClosed()

	-- 4) #46 + #47.3 Stage 4 Craft: minimized spellcast tracking, interrupt reset, multi-output qty, combat banner, CraftFrame 1x, >4 reagents + overflow
	local eightReagents = {}
	for rIdx = 1, 8 do
		eightReagents[rIdx] = { itemID = 92310 + rIdx, name = "Reagent " .. rIdx, qty = 1 }
	end
	of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "c8", name = "Grand Elixir", itemID = 92300, spellID = 99300, prof = "alchemy", qty = 3, numMade = 2,
			reagents = eightReagents },
	}, { title = "Stage 4 Audit Test" })
	of.SetActiveStage("craft")
	-- Combat waiting banner
	mockCombat = true
	modal.Render()
	check((modal.waitingFs:GetText() or ""):find("Leave combat to open", 1, true) ~= nil,
		"Stage 4 waiting banner in combat displays 'Leave combat to open ...', got: " .. tostring(modal.waitingFs:GetText()))
	mockCombat = false
	-- Open Alchemy + check 6 reagents + '+2 more reagents' overflow in right drawer
	_G.C_TradeSkillUI = {
		GetBaseProfessionInfo = function() return { professionName = "Alchemy" } end,
	}
	tsfFrame:Show()
	of.OnTradeSkillShow()
	modal.SetExtended(true)
	modal.Render()
	check(modal.treeChainNodes[6] and modal.treeChainNodes[6]:IsShown(),
		"Stage 4 Reagents drawer renders up to 6 reagent nodes without truncating at 4")
	check(modal.treeChainOverflowFs and modal.treeChainOverflowFs:IsShown()
		and stripColors(modal.treeChainOverflowFs:GetText()):find("+2 more reagents", 1, true) ~= nil,
		"Stage 4 Reagents drawer shows '+2 more reagents' when recipe has 8 reagents")
	modal.SetExtended(false)
	-- Minimized Trade Strip still tracks UNIT_SPELLCAST_START/INTERRUPTED/SUCCEEDED + multi-output (numMade=2 -> 2 queued in Sell per craft!)
	modal:Hide()
	app._ahBuyingMode = false
	fireEvent("UNIT_SPELLCAST_START", "player", "cast-1", 99300)
	of.GetState().stages.craft.tasks[1].status = "active"
	fireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-1", 99300)
	check(of.GetState().stages.craft.tasks[1].status == "pending"
		and (of.GetState().notice or ""):find("interrupted", 1, true) ~= nil,
		"UNIT_SPELLCAST_INTERRUPTED while minimized resets active craft to pending with notice")
	fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 99300)
	check(of.GetState().stages.craft.tasks[1].completedCrafts == 1,
		"UNIT_SPELLCAST_SUCCEEDED tracks craft progress even when Trade Strip is hidden/minimized")
	local sellQItem = of.GetState().stages.sell.items[1]
	check(sellQItem and sellQItem.totalQty == 4,
		"Multi-output recipe (qty=3, numMade=2 -> 2 crafts) queues 4 units into Stage 5 Sell, got: " .. tostring(sellQItem and sellQItem.totalQty))
	tsfFrame:Hide()
	_G.C_TradeSkillUI = nil
	-- Classic CraftFrame shows 'Craft 1x' instead of 'Craft Nx'
	of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "ce", name = "Enchant Test", itemID = 92350, spellID = 99350, prof = "enchanting", qty = 5,
			reagents = { { itemID = 92351, name = "Strange Dust", qty = 1 } } },
	}, { title = "Classic CraftFrame 1x Test" })
	bagState[0][1] = { itemID = 92351, stackCount = 10, isLocked = false }
	cfFrame:Show()
	of.GetState().env.openProfKey = "enchanting"
	app.enterOrderFlowMode("craft")
	modal.Render()
	check(modal.buyBtn:GetText() == "Craft 1x",
		"Classic CraftFrame shows 'Craft 1x' (crafts 1 at a time), got: " .. tostring(modal.buyBtn:GetText()))
	cfFrame:Hide()

	-- 5) Stage 5 Sell Audit Regressions (Vendor split guard, Legacy AH gate, scan key-prime fallback & bid-only preference)
	bagState[0][1] = { itemID = 92401, stackCount = 5, isLocked = false, isBound = false, ahValid = true, itemLevel = 25,
		hyperlink = "|cffffffff|Hitem:92401::::::::60:::::::|h[Audit Flask]|h|r" }
	bagState[0][2] = { itemID = 92402, stackCount = 4, isLocked = false, isBound = false, ahValid = true, itemLevel = 45,
		hyperlink = "|cff1eff00|Hitem:92402::::::::60:::::::|h[Crafted Blade]|h|r" }
	keyInfoMap[92401] = { itemName = "Audit Flask", isCommodity = true }
	keyInfoMap[92402] = { itemName = "Crafted Blade", isCommodity = false }
	of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "s1", name = "Audit Flask", itemID = 92401, spellID = 99401, prof = "alchemy", qty = 5 },
		{ isMainRow = true, mainGroupKey = "s2", name = "Crafted Blade", itemID = 92402, spellID = 99402, prof = "blacksmithing", qty = 2 },
	}, { title = "MM Sell Audit Test" })
	local tab = ns.AHSellTab
	tab.SelectTab()
	local sl = of.GetState().stages.sell

	-- MM Sell left categorized bag pane shown cleanly while Task Strip keeps no sellBagPane
	tab.Render()
	check(tab.sellBagPane:IsShown() and modal.sellBagPane == nil, "MM Sell displays categorized Bags pane independently of Task Strip")

	-- Vendor-flagged item keeps AH pricing form visible cleanly in MM Sell while backend SellToVendor guards oversell
	of.SetSellItemChannel(2, "vendor")
	of.SelectSellItem(2)
	mfFrame:Show()
	of.OnMerchantShow()
	tab.Render()
	check(tab.sellForm:IsShown() and tab.sellVendorBar == nil,
		"Vendor-flagged item keeps AH pricing form visible cleanly in MM Sell (no sellVendorBar)")
	of.SetSellItemQty(2, 2)
	usedVendorSlots = {}
	local okVendOver, errVendOver = of.SellToVendor(2)
	check(okVendOver == false and errVendOver == "split_needed" and #usedVendorSlots == 0,
		"SellToVendor refuses to oversell stack of 4 when remaining=2 (returns split_needed)")
	mfFrame:Hide()
	of.OnMerchantClosed()

	-- Legacy AH disables Post button (tab.postBtn) via both nil C_AuctionHouse and IsUsingLegacyAuctionClient()
	of.SelectSellItem(1)
	_G.C_AuctionHouse = nil
	tab.Render()
	check(not tab.postBtn:IsEnabled(), "MM Sell disables 'Post' when C_AuctionHouse is nil")
	_G.C_AuctionHouse = mockAH
	local origLegacyClient = _G.IsUsingLegacyAuctionClient
	_G.IsUsingLegacyAuctionClient = function() return true end
	tab.Render()
	check(not tab.postBtn:IsEnabled(), "MM Sell disables 'Post' when IsUsingLegacyAuctionClient() == true")
	_G.IsUsingLegacyAuctionClient = origLegacyClient

	-- Live-WoW Scan Resilience:
	-- (a) Mismatched isCommodity guess (guessed false, server answers COMMODITY_SEARCH_RESULTS_UPDATED)
	of.SelectSellItem(1)
	keyInfoMap[92401] = { itemName = "Audit Flask", isCommodity = false }
	commLadder[92401] = { { unitPrice = 32000, quantity = 8, numOwnerItems = 0 } }
	searchLog = {}
	of.ScanSellItemMarket(1, "select")
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 92401)
	check(sl.pendingSearch == nil and sl.items[1].liveUnit == 32000,
		"COMMODITY_SEARCH_RESULTS_UPDATED accepted despite mismatched isCommodity=false guess (liveUnit=32000)")

	-- (b) Non-commodity prefers lowest buyout listing over bid-only bait (88000c over 5000c bid-only)
	of.SetSellItemChannel(2, "ah")
	of.SelectSellItem(2)
	keyInfoMap[92402] = { itemName = "Crafted Blade", isCommodity = true }
	itemLadder[92402] = {
		{ buyoutAmount = 0, bidAmount = 5000, quantity = 1, containsOwnerItem = false },
		{ buyoutAmount = 88000, bidAmount = 70000, quantity = 1, containsOwnerItem = false },
	}
	of.ScanSellItemMarket(2, "select")
	ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 92402, itemLevel = 45, itemSuffix = 0 })
	check(sl.pendingSearch == nil and sl.items[2].liveUnit == 88000,
		"ITEM_SEARCH_RESULTS_UPDATED prefers buyout (88000c) over bid-only bait (5000c)")

	-- (c) GetItemKeyInfo returns nil -> 1.5s prime fallback fires search query automatically without hanging 15s!
	keyInfoMap[92401] = nil
	scheduledTimers = {}
	searchLog = {}
	of.ScanSellItemMarket(1, "select")
	check(sl.pendingKeyPrime ~= nil and #searchLog == 0, "Unprimed key awaits ITEM_KEY_ITEM_INFO_RECEIVED initially")
	advanceTimers(2)
	check(#searchLog == 1 and sl.pendingSearch ~= nil,
		"1.5s prime fallback dispatches search query automatically when ITEM_KEY_ITEM_INFO_RECEIVED never fires")
	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 92401)
	check(sl.pendingSearch == nil and sl.items[1].liveUnit == 32000,
		"Prime-fallback scan completes cleanly instead of timing out")

	-- Cleanup
	if tab and tab.HideTab then tab.HideTab() end
	app.exitAHBuyingMode(false)
	_G.C_AuctionHouse = origAH
	_G.AuctionHouseFrame = origAHF
	_G.MerchantFrame = origMF
	_G.BankFrame = origBF
	_G.TradeSkillFrame = origTSF
	_G.CraftFrame = origCF
	_G.C_Container = origCCont
	_G.ItemLocation = origIL
	_G.GetTime = origGetTime
	if _G.C_Timer and origTimerAfter then _G.C_Timer.After = origTimerAfter end
	_G.InCombatLockdown = origInCombat
	_G.Enum = origEnum
	_G.GetMerchantNumItems, _G.GetMerchantItemID, _G.GetMerchantItemLink, _G.GetMerchantItemInfo, _G.GetMerchantItemMaxStack, _G.BuyMerchantItem =
		origGetMNum, origGetMID, origGetMLink, origGetMInfo, origGetMMax, origBuyM
	_G.C_MerchantFrame = origCMerchant
	_G.C_TradeSkillUI = origCTrade
	_G.GetMoney = origMoney
	app.searchAH = origSearchAH
	app.getBagCountByID = origGetBag
end
runAuditFix46_47_48Regressions()

---------------------------------------------------------------------------------------------------
-- 15. Forever 16001 Two-Word Surname Character Identity & Syndicator Self-Exclusion (#57)
---------------------------------------------------------------------------------------------------
local function runForeverSurnameAltRegression()
	local of = app.orderFlow
	local origRegNames = _G.RegionalUniqueNamesEnabled
	local origConstants = _G.Constants
	local origUnitName = _G.UnitName
	local origUnitGUID = _G.UnitGUID
	local origGetRealm = _G.GetRealmName
	local origNormRealm = _G.GetNormalizedRealmName
	local origSyn = _G.Syndicator
	local origCCont = _G.C_Container
	local origChars = MerchantMasterDB.chars
	local origCharKey = app.charKey
	local origChar = app.char
	local origActiveChar = ns.activeChar
	local origIncludeAlts = MerchantMasterDB.includeAlts
	local origLegacy = MerchantMasterDB.enableLegacyPriceAddons
	local origTimerAfter = _G.C_Timer and _G.C_Timer.After

	if _G.C_Timer then _G.C_Timer.After = function() end end
	_G.RegionalUniqueNamesEnabled = function() return true end
	_G.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
	_G.UnitName = function(u)
		if u == "player" then return "Aldric", "Stone" end
		return origUnitName and origUnitName(u) or "NPC"
	end
	_G.UnitGUID = function(u)
		if u == "player" then return "Player-16001-0001" end
		return origUnitGUID and origUnitGUID(u) or nil
	end
	_G.GetRealmName = function() return "Forever" end
	_G.GetNormalizedRealmName = function() return "Forever" end
	_G.C_Container = {
		GetContainerNumSlots = function(b) return b == 0 and 4 or 0 end,
		GetContainerNumFreeSlots = function(b) return b == 0 and 3 or 0, 0 end,
		GetContainerItemInfo = function(b, s)
			if b == 0 and s == 1 then
				return { itemID = 92901, stackCount = 10, isLocked = false,
					hyperlink = "|cffffffff|Hitem:92901::::::::60:::::::|h[Test Surname Herb]|h|r" }
			end
			return nil
		end,
	}

	local fullNm, firstNm = app.getForeverPlayerName()
	check(fullNm == "Aldric Stone" and firstNm == "Aldric",
		"getForeverPlayerName returns 'Aldric Stone', 'Aldric' when RegionalUniqueNamesEnabled() == true")

	local activeEcon = ns.DetectActiveEconomy()
	local oldKey = activeEcon .. "-Forever-Aldric"
	local newKey = activeEcon .. "-Forever-Aldric Stone"
	MerchantMasterDB.chars = {
		[oldKey] = {
			name = "Aldric",
			realm = "Forever",
			faction = "Horde",
			economy = activeEcon,
			bags = { ["Test Surname Herb"] = 10 },
			bank = { ["Test Surname Herb"] = 7 },
			mail = {},
		},
	}

	fireEvent("PLAYER_LOGIN")
	check(app.charKey == newKey, "PLAYER_LOGIN builds full surname charKey '" .. tostring(newKey) .. "', got '" .. tostring(app.charKey) .. "'")
	check(app.char.name == "Aldric Stone" and app.char.firstName == "Aldric" and app.char.guid == "Player-16001-0001",
		"PLAYER_LOGIN records full name, firstName, and player GUID on app.char")
	check(MerchantMasterDB.chars[oldKey] == nil,
		"PLAYER_LOGIN migrates and removes legacy single-word self key '" .. tostring(oldKey) .. "'")
	check(app.char.bank and app.char.bank["Test Surname Herb"] == 7,
		"PLAYER_LOGIN migration preserves saved bank counts from legacy single-word self entry")

	-- Also inject a stale unmigrated single-word 'Aldric' char entry + same-GUID entry -> alts() MUST skip both!
	MerchantMasterDB.chars[activeEcon .. "-Forever-AldricStale"] = {
		name = "Aldric",
		realm = "Forever",
		faction = "Horde",
		economy = activeEcon,
		bags = { ["Test Surname Herb"] = 10 },
	}
	MerchantMasterDB.chars[activeEcon .. "-Forever-SameGuidAlias"] = {
		name = "OldAldric",
		guid = "Player-16001-0001",
		realm = "Forever",
		faction = "Horde",
		economy = activeEcon,
		bags = { ["Test Surname Herb"] = 10 },
	}
	local altList = app.getAlts()
	check(#altList == 0, "alts() excludes stale single-word self and same-GUID self entries, got count=" .. tostring(#altList))

	-- Seed real alt ('BankAlt Last') in native MerchantMasterDB.chars (Syndicator legacy bridge removed)
	MerchantMasterDB.chars[activeEcon .. "-Forever-BankAlt Last"] = {
		name = "BankAlt Last",
		realm = "Forever",
		faction = "Horde",
		economy = activeEcon,
		bags = { ["Test Surname Herb"] = 5 },
		bank = {},
		mail = {},
	}
	MerchantMasterDB.includeAlts = true
	app.ownershipRev = (app.ownershipRev or 0) + 1

	local bd = app.getItemOwnershipBreakdown(92901, "Test Surname Herb")
	check(#bd.alts == 1 and bd.alts[1].name == "BankAlt Last" and bd.alts[1].qty == 5 and bd.alts[1].location == "Bags",
		"getItemOwnershipBreakdown excludes self ('Aldric'/'Aldric Stone') and reports only real alt 'BankAlt Last' (5x), got count="
		.. tostring(#bd.alts) .. " first=" .. tostring(bd.alts[1] and bd.alts[1].name))

	-- Stage 2 Collect using live getItemOwnershipBreakdown never lists Aldric / Aldric Stone as an alt
	of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "sn1", name = "Surname Potion", itemID = 92900, spellID = 99900, prof = "alchemy", qty = 1,
			reagents = { { itemID = 92901, name = "Test Surname Herb", qty = 22 } } },
		{ indent = 1, mainGroupKey = "sn1", name = "Test Surname Herb", itemID = 92901, qty = 0, ownedUsed = 22 },
	}, {
		title = "Forever Surname Stage 2 Collect Test",
		ownershipProvider = function(id, nm) return app.getItemOwnershipBreakdown(id, nm) end,
	})
	local altItems = {}
	for _, it in ipairs(of.GetState().stages.collect.items or {}) do
		if it.source == "alt" then altItems[#altItems + 1] = it end
	end
	check(#altItems == 1 and altItems[1].altLabel == "On Alt: BankAlt Last (Bags 5x)",
		"Stage 2 Collect alt bucket shows only real alt 'BankAlt Last' (never self Aldric/Aldric Stone), got: "
		.. tostring(altItems[1] and altItems[1].altLabel))

	-- #62.1: Single-string "Aldric Stone" from UnitName("player") (with second == nil and RegionalUniqueNamesEnabled() == false) still splits firstName == "Aldric"
	_G.RegionalUniqueNamesEnabled = function() return false end
	_G.UnitName = function(u)
		if u == "player" then return "Aldric Stone", nil end
		return origUnitName and origUnitName(u) or "NPC"
	end
	local singleFull, singleFirst = app.getForeverPlayerName()
	check(singleFull == "Aldric Stone" and singleFirst == "Aldric",
		"#62: Single-string UnitName('player')='Aldric Stone' (second=nil) still splits firstName='Aldric', got: "
		.. tostring(singleFull) .. " / " .. tostring(singleFirst))

	-- #62.2: Stale "Aldric" under a DIFFERENT key with stale old bags (Mageweave Cloth / Gold Power Core / Thorium Bar) is purged on PLAYER_LOGIN without copying old bags
	local weirdKey = activeEcon .. "-OldRealmName-Aldric"
	MerchantMasterDB.chars = {
		[weirdKey] = {
			name = "Aldric",
			realm = "OldRealmName",
			faction = "Horde",
			economy = activeEcon,
			bags = { ["Mageweave Cloth"] = 40, ["Gold Power Core"] = 12, ["Thorium Bar"] = 25 },
			bank = { ["Test Surname Herb"] = 9 },
			mail = {},
		},
	}
	fireEvent("PLAYER_LOGIN")
	check(MerchantMasterDB.chars[weirdKey] == nil,
		"#62: PLAYER_LOGIN purges stale 'Aldric' under arbitrary key '" .. tostring(weirdKey) .. "'")
	check(app.char.bank and app.char.bank["Test Surname Herb"] == 9,
		"#62: PLAYER_LOGIN preserves bank counts when migrating arbitrary stale 'Aldric' key")
	check(not (app.char.bags and (app.char.bags["Mageweave Cloth"] or app.char.bags["Gold Power Core"] or app.char.bags["Thorium Bar"])),
		"#62: PLAYER_LOGIN never copies stale old bags (Mageweave/Gold Power Core/Thorium Bar) into 'Aldric Stone'")

	-- #61: OrderFlow.RestoreState strips stale "On Alt: Aldric" rows on /reload
	local origSavedOrderFlow = MerchantMasterDB.orderFlowState
	MerchantMasterDB.orderFlowState = {
		active = true,
		activeStage = "collect",
		stages = {
			collect = {
				activeIndex = 2,
				items = {
					{
						name = "Mageweave Cloth",
						itemID = 4338,
						source = "alt",
						status = "alt_info",
						needed = 20,
						collected = 0,
						remaining = 20,
						altLabel = "On Alt: Aldric (Bags 20x)",
						altOwners = { { name = "Aldric", location = "Bags", qty = 20 } },
					},
					{
						name = "Thorium Bar",
						itemID = 12359,
						source = "alt",
						status = "alt_info",
						needed = 15,
						collected = 0,
						remaining = 15,
						altLabel = "On Alt: Aldric (Bags 10x), BankAlt Last (Bank 5x)",
						altOwners = {
							{ name = "Aldric", location = "Bags", qty = 10 },
							{ name = "BankAlt Last", location = "Bank", qty = 5 },
						},
					},
				},
			},
		},
	}
	of.RestoreState()
	local restoredCol = of.GetState().stages.collect
	check(#restoredCol.items == 1 and restoredCol.items[1].itemID == 12359,
		"#61: OrderFlow.RestoreState drops self-only 'On Alt: Aldric' collect row cleanly, got count=" .. tostring(#restoredCol.items))
	check(restoredCol.items[1].altLabel == "On Alt: BankAlt Last (Bank 5x)" and restoredCol.items[1].remaining == 5 and restoredCol.items[1].needed == 5,
		"#61: OrderFlow.RestoreState strips self from mixed alt row, rebuilds altLabel, and clamps qty to 5, got: "
		.. tostring(restoredCol.items[1].altLabel) .. " rem=" .. tostring(restoredCol.items[1].remaining))
	check(restoredCol.activeIndex == 1,
		"#61: OrderFlow.RestoreState clamps collect activeIndex to valid range (1), got: " .. tostring(restoredCol.activeIndex))
	MerchantMasterDB.orderFlowState = origSavedOrderFlow

	-- Cleanup
	_G.RegionalUniqueNamesEnabled = origRegNames
	_G.Constants = origConstants
	_G.UnitName = origUnitName
	_G.UnitGUID = origUnitGUID
	_G.GetRealmName = origGetRealm
	_G.GetNormalizedRealmName = origNormRealm
	_G.Syndicator = origSyn
	_G.C_Container = origCCont
	MerchantMasterDB.chars = origChars
	app.charKey = origCharKey
	app.char = origChar
	ns.activeChar = origActiveChar
	MerchantMasterDB.includeAlts = origIncludeAlts
	MerchantMasterDB.enableLegacyPriceAddons = origLegacy
	if _G.C_Timer and origTimerAfter then _G.C_Timer.After = origTimerAfter end
	app.cachedBagCounts = nil
	app.cachedBagCountsByID = nil
	app._cachedOwnedCounts = nil
	app._cachedOwnedCountsByID = nil
	app.bagsDirty = true
	app.bagCountsDirty = true
	app.ownershipRev = (app.ownershipRev or 0) + 1
end
runForeverSurnameAltRegression()

---------------------------------------------------------------------------------------------------
-- 16. Forever 16001 TSM-Style BAG_UPDATE / PLAYER_ENTERING_WORLD Resync & /mm resync (#67)
---------------------------------------------------------------------------------------------------
local function runForeverBagResyncRegression()
	local origCCont = _G.C_Container
	local origTimerAfter = _G.C_Timer and _G.C_Timer.After
	local origRegNames = _G.RegionalUniqueNamesEnabled
	local origUnitName = _G.UnitName
	local origUnitGUID = _G.UnitGUID
	local origGetRealm = _G.GetRealmName
	local origSynData = _G.SYNDICATOR_DATA
	local origChars = MerchantMasterDB.chars
	local origCharKey = app.charKey
	local origChar = app.char
	local origActiveChar = ns.activeChar

	local timers = {}
	if _G.C_Timer then
		_G.C_Timer.After = function(delay, fn)
			timers[#timers + 1] = { delay = tonumber(delay) or 0, fn = fn }
		end
	end
	local function runTimersByDelay(maxDelay)
		local keep, toRun = {}, {}
		for _, t in ipairs(timers) do
			if t.delay <= maxDelay then toRun[#toRun + 1] = t.fn else keep[#keep + 1] = t end
		end
		timers = keep
		for _, fn in ipairs(toRun) do fn() end
	end

	local liveBags = {
		[0] = {},
		[1] = { [1] = { itemID = 93001, stackCount = 6, isLocked = false, hyperlink = "|cffffffff|Hitem:93001::::::::60:::::::|h[Live Bag1 Herb]|h|r" } },
		[2] = {},
	}
	_G.C_Container = {
		GetContainerNumSlots = function(b) return liveBags[b] and 4 or 0 end,
		GetContainerNumFreeSlots = function(b) return liveBags[b] and 3 or 0, 0 end,
		GetContainerItemInfo = function(b, s) return liveBags[b] and liveBags[b][s] or nil end,
	}
	_G.RegionalUniqueNamesEnabled = function() return true end
	_G.UnitName = function(u)
		if u == "player" then return "Aldric", "Stone" end
		return origUnitName and origUnitName(u) or "NPC"
	end
	_G.UnitGUID = function(u)
		if u == "player" then return "Player-16001-0001" end
		return origUnitGUID and origUnitGUID(u) or nil
	end
	_G.GetRealmName = function() return "Forever" end

	local activeEcon = ns.DetectActiveEconomy()
	local charKey = activeEcon .. "-Forever-Aldric Stone"
	MerchantMasterDB.chars = {
		[charKey] = {
			name = "Aldric Stone",
			firstName = "Aldric",
			guid = "Player-16001-0001",
			realm = "Forever",
			faction = "Horde",
			economy = activeEcon,
			bags = { ["Mageweave Cloth"] = 40, ["Thorium Bar"] = 25 },
			bank = {},
			mail = {},
		},
	}
	app.charKey = charKey
	app.char = MerchantMasterDB.chars[charKey]
	ns.activeChar = app.char

	local mmEventFrame = nil
	for _, fr in ipairs(frames) do
		if fr._events and fr._events["BAG_UPDATE"] and fr._events["PLAYER_ENTERING_WORLD"] then
			mmEventFrame = fr
			break
		end
	end
	check(mmEventFrame ~= nil, "#67: Main MerchantMaster event frame registers BAG_UPDATE and PLAYER_ENTERING_WORLD")
	local function fireMM(ev, ...)
		if mmEventFrame and mmEventFrame._scripts and mmEventFrame._scripts.OnEvent then
			mmEventFrame._scripts.OnEvent(mmEventFrame, ev, ...)
		end
	end

	-- 1) Burst of BAG_UPDATE events coalesces into 1 next-frame timer and clears stale bag items from bag 1..5
	timers = {}
	fireMM("BAG_UPDATE", 1)
	fireMM("BAG_UPDATE", 1)
	fireMM("BAG_UPDATE", 2)
	check(#timers == 1 and timers[1].delay == 0,
		"#67: Multiple BAG_UPDATE events coalesce into 1 next-frame C_Timer.After(0), got count=" .. tostring(#timers))
	runTimersByDelay(0)
	check(app.char.bags["Live Bag1 Herb"] == 6 and app.char.bags["Mageweave Cloth"] == nil and app.char.bags["Thorium Bar"] == nil,
		"#67: BAG_UPDATE resyncs non-backpack bag 1 and drops stale Mageweave Cloth / Thorium Bar")

	-- 2) PLAYER_ENTERING_WORLD schedules next-frame (0s) + 1.0s safety resync for slow Forever container load
	liveBags[1][1] = nil
	timers = {}
	fireMM("PLAYER_ENTERING_WORLD", true, false)
	runTimersByDelay(0)
	check(app.char.bags["Live Bag1 Herb"] == nil,
		"#67: PLAYER_ENTERING_WORLD next-frame resync removes emptied bag item")
	liveBags[2][1] = { itemID = 93002, stackCount = 4, isLocked = false, hyperlink = "|cffffffff|Hitem:93002::::::::60:::::::|h[Late Loaded Ore]|h|r" }
	runTimersByDelay(1.0)
	check(app.char.bags["Late Loaded Ore"] == 4,
		"#67: PLAYER_ENTERING_WORLD 1.0s safety resync captures late-loaded Forever bag 2 item")

	-- 3) /mm resync (app.resyncBags) clears stale caches, purges stale single-word 'Aldric', and omits removed Syndicator ghost scan
	app.char.bags["Gold Power Core"] = 12
	local staleAldricKey = activeEcon .. "-Forever-Aldric"
	MerchantMasterDB.chars[staleAldricKey] = {
		name = "Aldric",
		realm = "Forever",
		faction = "Horde",
		economy = activeEcon,
		bags = { ["Gold Power Core"] = 12 },
		bank = {},
	}
	local res = app.resyncBags(false)
	check(res.purged == 1 and MerchantMasterDB.chars[staleAldricKey] == nil,
		"#67: app.resyncBags purges stale single-word 'Aldric' record")
	check(app.char.bags["Gold Power Core"] == nil and app.char.bags["Late Loaded Ore"] == 4 and res.bagTypes == 1,
		"#67: app.resyncBags refreshes app.char.bags from live containers and removes stale Gold Power Core")
	check(res.syndicatorGhosts == nil, "#67: app.resyncBags omits removed Syndicator ghost scan in standalone mode")
	SlashCmdList.MERCHANTMASTER("resync")
	check(app.char.bags["Late Loaded Ore"] == 4 and app.char.bags["Gold Power Core"] == nil,
		"#67: /mm resync slash command executes cleanly")

	-- Cleanup
	_G.C_Container = origCCont
	if _G.C_Timer and origTimerAfter then _G.C_Timer.After = origTimerAfter end
	_G.RegionalUniqueNamesEnabled = origRegNames
	_G.UnitName = origUnitName
	_G.UnitGUID = origUnitGUID
	_G.GetRealmName = origGetRealm
	_G.SYNDICATOR_DATA = origSynData
	MerchantMasterDB.chars = origChars
	app.charKey = origCharKey
	app.char = origChar
	ns.activeChar = origActiveChar
	app.cachedBagCounts = nil
	app.cachedBagCountsByID = nil
	app._cachedOwnedCounts = nil
	app._cachedOwnedCountsByID = nil
	app.bagsDirty = true
	app.bagCountsDirty = true
	app.ownershipRev = (app.ownershipRev or 0) + 1
end
runForeverBagResyncRegression()

-- 22. Regression A: Craft-Complete Clear Queue, Unblocked Re-Buy & Mid-Session Mail Non-Double-Deduction
local function runCraftCompleteClearAndRebuyRegression()
	local modal = app.ui and app.ui.cartBuyerModal
	local origAHF = _G.AuctionHouseFrame
	local origMailF = _G.MailFrame
	local origTSF = _G.TradeSkillFrame
	local origCCont = _G.C_Container
	local origGetBag = app.getBagCountByID
	local origOwn = app.getItemOwnershipBreakdown
	local origSendSig = app.getOrderFlowCartSignature

	local ahShown = true
	local mailShown = false
	local bagCounts = { [95001] = 0 }
	_G.AuctionHouseFrame = { IsShown = function() return ahShown end }
	_G.MailFrame = { IsShown = function() return mailShown end }
	_G.TradeSkillFrame = { IsShown = function() return true end }
	_G.C_Container = {
		GetContainerNumSlots = function() return 0 end,
		GetContainerItemInfo = function() return nil end,
	}
	app.getBagCountByID = function(id) return bagCounts[id] or 0 end
	app.getItemOwnershipBreakdown = function(id)
		return { bags = bagCounts[id] or 0, bank = 0, mail = 0, alts = {} }
	end

	local sigIdx = "sig-rebuy-same"
	app.getOrderFlowCartSignature = function() return sigIdx end

	local buyCraftRows = {
		{ name = "Reg Herb", itemID = 95001, qty = 4, unitPrice = 500, estUnitCost = 500 },
		{ isMainRow = true, mainGroupKey = "rc1", name = "Reg Potion", itemID = 95002, spellID = 99502, prof = "alchemy", qty = 1,
			reagents = { { itemID = 95001, name = "Reg Herb", qty = 4 } } },
	}
	check(app.sendShoppingRowsToBuyer(buyCraftRows, "Rebuy Regression") == true,
		"RegA: Initial sendShoppingRowsToBuyer succeeds")
	of.SetActiveStage("ah")
	of.GetState().stages.ah.items[1].bought = 4
	of.GetState().stages.ah.items[1].remaining = 0
	of.GetState().stages.ah.items[1].status = "done"

	-- Simulate craft completion after mail collect
	bagCounts[95001] = 4
	local colSt = of.GetState().stages.collect
	colSt.items = { { itemID = 95001, name = "Reg Herb", source = "mail", needed = 4, collected = 4, remaining = 0, status = "done" } }
	bagCounts[95001] = 0
	of.SetActiveStage("craft")
	of.MarkCraftDone(1)
	check(of.IsPipelineComplete() == true and of.IsCraftCycleComplete() == true,
		"RegA: Pipeline and craft cycle report complete after craft finishes")
	local stComp = of.GetState()
	check(stComp.stageCompletePrompt and stComp.stageCompletePrompt.action == "clear_queue"
		and stComp.stageCompletePrompt.label == "Clear Queue ->",
		"RegA: Completed craft surfaces Clear Queue -> stage prompt")
	modal.Render()
	check(modal.clearBtn and modal.clearBtn:IsShown() and modal.nextStageBtn:GetText() == "Clear Queue ->",
		"RegA: Header Clear button and Clear Queue -> CTA both visible after craft completion")

	-- Re-buying with IDENTICAL signature must NOT be blocked or marked done!
	check(of.HasActiveSessionForSig(sigIdx) == false,
		"RegA: HasActiveSessionForSig returns false once craft cycle is complete")
	check(app.sendShoppingRowsToBuyer(buyCraftRows, "Rebuy Same Sig") == true,
		"RegA: Re-sending identical rows after craft completion succeeds")
	local reAH = of.GetState().stages.ah.items[1]
	local reCr = of.GetState().stages.craft.tasks[1]
	check(of.GetActiveStage() == "ah" and reAH and reAH.bought == 0 and reAH.remaining == 4 and reAH.status ~= "done",
		"RegA: Re-buying resets activeStage to 'ah' with full remaining=4 (craft does not block buying)")
	check(reCr and reCr.completedCrafts == 0 and reCr.remainingCrafts == 1 and reCr.status ~= "done",
		"RegA: Re-buying resets craft task completedCrafts to 0")

	-- Direct LoadFromShoppingRows(preserveProgress=true) after craft complete also clears prior bought/craft state
	of.GetState().stages.ah.items[1].bought = 4
	of.GetState().stages.ah.items[1].remaining = 0
	of.GetState().stages.ah.items[1].status = "done"
	of.SetActiveStage("craft")
	of.MarkCraftDone(1)
	of.LoadFromShoppingRows(buyCraftRows, { title = "Direct Reload", preserveProgress = true, cartSig = sigIdx })
	check(of.GetState().stages.ah.items[1].bought == 0 and of.GetState().stages.ah.items[1].remaining == 4
		and of.GetState().stages.craft.tasks[1].completedCrafts == 0,
		"RegA: Direct LoadFromShoppingRows(preserveProgress=true) after completed craft does not carry over bought or craft counts")

	-- Mid-session queue expansion: bought 4, collected 4 into bags -> adding 4 more must NOT double-deduct mail-collected 4!
	of.GetState().stages.ah.items[1].bought = 4
	of.GetState().stages.ah.items[1].remaining = 0
	of.GetState().stages.ah.items[1].status = "done"
	of.GetState().stages.collect.items = {
		{ itemID = 95001, name = "Reg Herb", source = "mail", needed = 4, collected = 4, remaining = 0, status = "done" },
	}
	bagCounts[95001] = 4 -- Already in bags so BuildUnifiedShoppingList asks only for the new 4
	of.LoadFromShoppingRows({
		{ name = "Reg Herb", itemID = 95001, qty = 4, unitPrice = 500, estUnitCost = 500 },
		{ isMainRow = true, mainGroupKey = "rc2", name = "Reg Potion", itemID = 95002, spellID = 99502, prof = "alchemy", qty = 2,
			reagents = { { itemID = 95001, name = "Reg Herb", qty = 8 } } },
	}, { title = "Mid-session Expand", preserveProgress = true, cartSig = "sig-mid-2" })
	local midAH = of.GetState().stages.ah.items[1]
	check(midAH and midAH.bought == 0 and midAH.remaining == 4,
		"RegA: Mid-session expansion subtracts mailCollected (4) from old.bought (4) so remaining stays 4 (zero double-deduction)")

	-- Clear Queue wipes craftOrderQueue, crateTurnInQueue, and OrderFlow cleanly
	bagCounts[95001] = 0
	of.GetState().stages.ah.items[1].bought = 4; of.GetState().stages.ah.items[1].remaining = 0; of.GetState().stages.ah.items[1].status = "done"
	of.SetActiveStage("craft")
	of.MarkCraftDone(1)
	MerchantMasterDB.craftOrderQueue = { { spellID = 99502, count = 1 } }
	MerchantMasterDB.crateTurnInQueue = { ["999"] = 2 }
	modal.Render()
	modal.nextStageBtn:Click("LeftButton")
	check(not of.HasAnyItems() and MerchantMasterDB.orderFlowState == nil
		and #MerchantMasterDB.craftOrderQueue == 0 and next(MerchantMasterDB.crateTurnInQueue) == nil,
		"RegA: Clicking Clear Queue -> clears OrderFlow, craftOrderQueue, and crateTurnInQueue")

	-- Header Clear button works equivalently
	of.LoadFromShoppingRows(buyCraftRows, { title = "Header Clear Test" })
	MerchantMasterDB.crateTurnInQueue = { ["998"] = 1 }
	modal.clearBtn:Click("LeftButton")
	check(not of.HasAnyItems() and next(MerchantMasterDB.crateTurnInQueue) == nil,
		"RegA: Clicking header Clear button clears OrderFlow and crateTurnInQueue")

	app.exitAHBuyingMode(false)
	_G.AuctionHouseFrame = origAHF
	_G.MailFrame = origMailF
	_G.TradeSkillFrame = origTSF
	_G.C_Container = origCCont
	app.getBagCountByID = origGetBag
	app.getItemOwnershipBreakdown = origOwn
	app.getOrderFlowCartSignature = origSendSig
end
runCraftCompleteClearAndRebuyRegression()

-- 23. Regression B: Alt Bank Stays ALT Despite AH Mail (No False Conversion + Genuine Alt Mail Split)
local function runAltBankVsMailRegression()
	local origMailF = _G.MailFrame
	local origNumItems = _G.GetInboxNumItems
	local origHdrInfo = _G.GetInboxHeaderInfo
	local origInvInfo = _G.GetInboxInvoiceInfo
	local origGetItem = _G.GetInboxItem
	local origGetLink = _G.GetInboxItemLink
	local origOwn = app.getItemOwnershipBreakdown
	local origGetBag = app.getBagCountByID

	local inbox = {
		{ sender = "Auction House", subj = "Auction won: Sun Copper (5)", invoice = "buyer",
			atts = { { itemID = 95100, name = "Sun Copper", count = 5 } } },
		{ sender = "Auction House", subj = "Auction expired: Sun Copper (3)", invoice = "seller",
			atts = { { itemID = 95100, name = "Sun Copper", count = 3 } } },
	}
	_G.MailFrame = { IsShown = function() return true end }
	_G.GetInboxNumItems = function() return #inbox, #inbox end
	_G.GetInboxHeaderInfo = function(idx)
		local m = inbox[idx]
		if not m then return nil end
		return nil, nil, m.sender, m.subj, 0, 0, 30, #m.atts
	end
	_G.GetInboxInvoiceInfo = function(idx)
		local m = inbox[idx]
		return m and m.invoice or nil
	end
	_G.GetInboxItem = function(idx, aIdx)
		local att = inbox[idx] and inbox[idx].atts[aIdx]
		if not att then return nil end
		return att.name, att.itemID, 134400, att.count, 1, true
	end
	_G.GetInboxItemLink = function(idx, aIdx)
		local att = inbox[idx] and inbox[idx].atts[aIdx]
		return att and ("|cffffffff|Hitem:" .. tostring(att.itemID) .. "::::::::60:::::::|h[" .. att.name .. "]|h|r") or nil
	end
	app.getBagCountByID = function() return 0 end
	app.getItemOwnershipBreakdown = function(id)
		if id == 95100 then
			return { bags = 0, bank = 0, mail = 0, alts = { { name = "Bankalt", location = "Bank", qty = 5 } } }
		end
		return { bags = 0, bank = 0, mail = 0, alts = {} }
	end

	of.LoadFromShoppingRows({
		{ name = "Sun Copper", itemID = 95100, qty = 5, ownedUsed = 5, ahUnitPrice = 400 },
	}, { title = "Alt vs AH Mail", ownershipProvider = app.getItemOwnershipBreakdown })

	-- Simulate AH buying the remaining 5 -> creates a MAIL row for 5 beside the ALT Bank row for 5
	of.GetState().stages.ah.items[1].bought = 0
	if of.SetActiveStage then of.SetActiveStage("collect") end
	local colItems = of.GetState().stages.collect.items
	colItems[#colItems + 1] = {
		itemID = 95100, name = "Sun Copper", source = "mail", needed = 5, collected = 0, remaining = 5,
		status = "pending", purchasedFromAH = true,
	}

	if of.OnMailShow then of.OnMailShow() end
	of.ScanOpenMailbox()
	local foundAlt, foundAHMail = nil, nil
	for _, it in ipairs(of.GetState().stages.collect.items) do
		if it.itemID == 95100 and it.source == "alt" then foundAlt = it
		elseif it.itemID == 95100 and it.source == "mail" then foundAHMail = it end
	end
	check(foundAlt ~= nil and foundAlt.status == "alt_info" and foundAlt.needed == 5,
		"RegB: Alt Bank item remains ALT (alt_info, 5x) even with AH buyer + AH expired mail in inbox")
	check(foundAHMail ~= nil and foundAHMail.status == "ready" and foundAHMail.needed == 5,
		"RegB: AH mail entry matches inbox attachment as MAIL (ready, 5x)")

	-- Direct CollectFromMail on ALT index refuses cleanly
	local altIdx = nil
	for idx, it in ipairs(of.GetState().stages.collect.items) do
		if it.source == "alt" and it.itemID == 95100 then altIdx = idx; break end
	end
	local colAltOk, colAltErr = of.CollectFromMail(altIdx)
	check(colAltOk == false and colAltErr == "not_mail_item" and of.GetState().stages.collect.items[altIdx].source == "alt",
		"RegB: CollectFromMail rejects source=='alt' without converting it to 'mail'")

	-- RestoreState self-healing on saved legacy mail row holding altOwners/altLabel
	local savedCorrupt = of.SerializeState()
	for _, it in ipairs(savedCorrupt.stages.collect.items) do
		if it.source == "alt" and it.itemID == 95100 then
			it.source = "mail"
			it.status = "pending"
		end
	end
	of.ClearSavedState()
	MerchantMasterDB.orderFlowState = savedCorrupt
	of.RestoreState()
	local healedAlt = nil
	for _, it in ipairs(of.GetState().stages.collect.items) do
		if it.source == "alt" and it.altOwners and #it.altOwners > 0 then healedAlt = it; break end
	end
	check(healedAlt ~= nil and healedAlt.status == "alt_info",
		"RegB: RestoreState self-heals saved mail row with altOwners/altLabel back to source='alt', status='alt_info'")

	-- Genuine non-AH mail sent directly by Bankalt-Realm splits cleanly without wiping remaining Alt Bank qty!
	inbox[3] = { sender = "Bankalt-Forever", subj = "Here is some copper", invoice = nil,
		atts = { { itemID = 95100, name = "Sun Copper", count = 3 } } }
	of.ScanOpenMailbox()
	local altAfterSplit, altMailRow = nil, nil
	for _, it in ipairs(of.GetState().stages.collect.items) do
		if it.itemID == 95100 and it.source == "alt" then altAfterSplit = it
		elseif it.itemID == 95100 and it.source == "mail" and it.purchasedFromAH ~= true then altMailRow = it end
	end
	check(altAfterSplit ~= nil and altAfterSplit.needed == 2 and altAfterSplit.altLabel == "On Alt: Bankalt (Bank 2x)",
		"RegB: Genuine 3x non-AH mail from Bankalt leaves remaining 2x as ALT ('Bankalt (Bank 2x)')")
	check(altMailRow ~= nil and altMailRow.needed == 3 and altMailRow.status == "ready",
		"RegB: Genuine 3x non-AH mail from Bankalt splits into its own ready MAIL entry")
	-- Re-scanning is idempotent (no duplicate deduction)
	of.ScanOpenMailbox()
	check(altAfterSplit.needed == 2 and altMailRow.needed == 3,
		"RegB: Second ScanOpenMailbox is idempotent after alt-mail split")

	of.ClearSavedState()
	_G.MailFrame = origMailF
	_G.GetInboxNumItems = origNumItems
	_G.GetInboxHeaderInfo = origHdrInfo
	_G.GetInboxInvoiceInfo = origInvInfo
	_G.GetInboxItem = origGetItem
	_G.GetInboxItemLink = origGetLink
	app.getItemOwnershipBreakdown = origOwn
	app.getBagCountByID = origGetBag
end
runAltBankVsMailRegression()

-- 24. Regression C: Standalone MM Sell AH Tab (LibAHTab, Drag-and-Drop, Categories, Sub-Tabs)
local function runStandaloneMMSellTabRegression()
	local origAHF = _G.AuctionHouseFrame
	local origAH = _G.C_AuctionHouse
	local origCCont = _G.C_Container
	local origCurInfo = _G.GetCursorInfo
	local origClearCur = _G.ClearCursor
	local origGetItemInfo = _G.GetItemInfo
	local origCItem = _G.C_Item

	local mockTabs = { CreateFrame("Button", "MockAHBuyTab", UIParent), CreateFrame("Button", "MockAHSellTab", UIParent) }
	local ahTitle = ""
	local displayModeHooked = {}
	local ahShown = true
	local mockFullAH = CreateFrame("Frame", "MockFullAHFrame", UIParent)
	mockFullAH:SetSize(820, 540)
	mockFullAH.Tabs = mockTabs
	mockFullAH.IsShown = function() return ahShown end
	mockFullAH.SetTitle = function(_, t) ahTitle = t end
	mockFullAH.SetDisplayMode = function(_, mode)
		-- Trigger posthooks on fallback lib if hooksecurefunc isn't stubbed
		for _, fn in ipairs(displayModeHooked) do fn(mockFullAH, mode) end
	end
	local origHookSec = _G.hooksecurefunc
	_G.hooksecurefunc = function(tbl, fnName, cb)
		if tbl == mockFullAH and fnName == "SetDisplayMode" then
			displayModeHooked[#displayModeHooked + 1] = cb
		elseif origHookSec then
			return origHookSec(tbl, fnName, cb)
		end
	end
	_G.AuctionHouseFrame = mockFullAH

	local bagItems = {
		[1] = { itemID = 96001, stackCount = 1, isLocked = false, isBound = false, quality = 3,
			hyperlink = "|cff0070dd|Hitem:96001::::::::60:::::::|h[Runed Sword]|h|r" },
		[2] = { itemID = 96002, stackCount = 1, isLocked = false, isBound = true, quality = 3,
			hyperlink = "|cff0070dd|Hitem:96002::::::::60:::::::|h[Bound Helmet]|h|r" },
		[3] = { itemID = 96003, stackCount = 5, isLocked = false, isBound = false, quality = 1,
			hyperlink = "|cffffffff|Hitem:96003::::::::60:::::::|h[Mana Draft]|h|r" },
		[4] = { itemID = 96004, stackCount = 10, isLocked = false, isBound = false, quality = 2,
			hyperlink = "|cff1eff00|Hitem:96004::::::::60:::::::|h[Green Gem]|h|r" },
	}
	local metaTbl = {
		[96001] = { name = "Runed Sword", classID = 2, quality = 3, ilvl = 55, maxStack = 1, sell = 1000 },
		[96002] = { name = "Bound Helmet", classID = 4, quality = 3, ilvl = 55, maxStack = 1, sell = 1000 },
		[96003] = { name = "Mana Draft", classID = 0, quality = 1, ilvl = 20, maxStack = 20, sell = 50 },
		[96004] = { name = "Green Gem", classID = 7, quality = 2, ilvl = 30, maxStack = 20, sell = 250 },
	}
	local bagDirtyReset = function()
		app.bagsDirty = true
		app.bagCountsDirty = true
		app.cachedBagCountsByID = nil
	end
	bagDirtyReset()

	_G.GetItemInfo = function(idOrLink)
		local id = tonumber(idOrLink) or (type(idOrLink) == "string" and tonumber(idOrLink:match("item:(%d+)")))
		local m = id and metaTbl[id]
		if m then
			return m.name, bagItems[1] and bagItems[1].hyperlink or ("item:" .. id), m.quality, m.ilvl, 1, "Misc", "Misc", m.maxStack, "", 134400, m.sell, m.classID, 0, 0, 0, nil, false
		end
		return origGetItemInfo and origGetItemInfo(idOrLink) or nil
	end
	_G.C_Item = {
		GetItemInfo = _G.GetItemInfo,
		GetDetailedItemLevelInfo = function(idOrLink)
			local id = tonumber(idOrLink) or (type(idOrLink) == "string" and tonumber(idOrLink:match("item:(%d+)")))
			return (id and metaTbl[id] and metaTbl[id].ilvl) or nil
		end,
		DoesItemExist = function() return true end,
		IsBound = function(loc)
			local slot = loc and bagItems[loc.slotIndex]
			return slot and slot.isBound == true or false
		end,
		GetItemIconByID = function() return 134400 end,
	}
	_G.C_Container = {
		GetContainerNumSlots = function(b) return (b == 0) and 4 or 0 end,
		GetContainerItemInfo = function(b, s) return (b == 0) and bagItems[s] or nil end,
	}
	_G.C_AuctionHouse = {
		IsSellItemValid = function(loc)
			local slot = loc and bagItems[loc.slotIndex]
			return not (slot and slot.isBound == true)
		end,
		GetItemCommodityStatus = function(loc)
			local slot = loc and bagItems[loc.slotIndex]
			return (slot and metaTbl[slot.itemID] and metaTbl[slot.itemID].maxStack == 1) and 1 or 2
		end,
		GetItemKeyFromItem = function(loc)
			local slot = loc and bagItems[loc.slotIndex]
			return { itemID = slot and slot.itemID or 0, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
		end,
		MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
		GetItemKeyInfo = function() return { isCommodity = true } end,
		SendSellSearchQuery = function() end,
		SendSearchQuery = function() end,
		IsThrottledMessageSystemReady = function() return true end,
	}

	local cursorCleared = 0
	_G.ClearCursor = function() cursorCleared = cursorCleared + 1 end
	_G.GetCursorInfo = function() return nil end

	of.ClearSavedState()
	local tab = ns.AHSellTab
	tab.EnsureAttached()
	check(tab.tabButton and tab.tabButton:GetText() == "MM Sell",
		"RegC: Standalone AH tab attaches cleanly with label 'MM Sell'")

	tab.SelectTab()
	check(tab.IsShown() and ahTitle == "MerchantMaster - Sell",
		"RegC: Selecting MM Sell shows tab frame and sets AH title to 'MerchantMaster - Sell'")

	mockFullAH:SetDisplayMode({ 1 })
	check(not tab.IsShown(), "RegC: Switching AH displayMode hides MM Sell tab cleanly")

	SlashCmdList.MERCHANTMASTER("sell")
	check(tab.IsShown(), "RegC: /mm sell selects MM Sell tab when Auction House is open")

	-- Drag-and-drop: valid sword adds; soulbound helmet rejects & clears cursor!
	local okDropSword = tab.HandleBagDrop(0, 1)
	check(okDropSword == true and #of.GetState().stages.sell.items == 1 and of.GetState().stages.sell.items[1].itemID == 96001,
		"RegC: Drag/drop bag item adds sellable Weapon (96001) to MM Sell")

	cursorCleared = 0
	local okDropBound, errDropBound = tab.HandleBagDrop(0, 2)
	check(okDropBound == false and errDropBound == "bound" and cursorCleared >= 1,
		"RegC: Drag/drop rejects soulbound item cleanly and clears cursor")

	-- Bag categories rendered on left pane (Weapon, Consumable, Trade Goods; Bound Helmet excluded)
	local hdrTexts = {}
	for _, h in ipairs(tab.sellBagCatHdrs or {}) do
		if h:IsShown() then hdrTexts[#hdrTexts + 1] = stripColors(h:GetText()) end
	end
	local hasWep, hasCons, hasTG = false, false, false
	for _, ht in ipairs(hdrTexts) do
		if ht == "Weapon" then hasWep = true
		elseif ht == "Consumable" then hasCons = true
		elseif ht == "Trade Goods" then hasTG = true end
	end
	check(hasWep and hasCons and hasTG,
		"RegC: Left bag grid groups items by category headers (Weapon, Consumable, Trade Goods)")

	-- Price History sub-tab renders daily trend points cleanly
	local econ = ns.DetectActiveEconomy and ns.DetectActiveEconomy() or "Alliance"
	local origDaily = MerchantMasterDB and MerchantMasterDB.ahDaily
	MerchantMasterDB = MerchantMasterDB or {}
	MerchantMasterDB.ahDaily = MerchantMasterDB.ahDaily or {}
	MerchantMasterDB.ahDaily[econ] = MerchantMasterDB.ahDaily[econ] or {}
	local curDay = math.floor(((time and time()) or 1700000000) / 86400)
	MerchantMasterDB.ahDaily[econ][96001] = {
		{ d = curDay - 1, lastP = 42000, lastQ = 12 },
		{ d = curDay, lastP = 45000, lastQ = 8 },
	}
	tab.SetSubTab("history")
	check(tab.sellHistoryView:IsShown() and tab.sellHistoryRows[1]:IsShown(),
		"RegC: Price History sub-tab renders recorded daily price rows for active item")

	-- Sell Queue sub-tab + Clear Queue button
	tab.SetSubTab("queue")
	check(tab.sellQueueView:IsShown() and tab.sellQueueClearBtn:IsEnabled(),
		"RegC: Sell Queue sub-tab shows queue and enabled Clear button")
	tab.sellQueueClearBtn:Click("LeftButton")
	check(#of.GetState().stages.sell.items == 0 and not tab.sellQueueClearBtn:IsEnabled(),
		"RegC: Clicking Clear in Sell Queue sub-tab empties queue and disables Clear")

	-- Closing AH hides tab and clears SPACE binding
	tab.OnAuctionHouseClosed()
	check(not tab.IsShown(), "RegC: Closing AH hides MM Sell tab cleanly")

	-- Auctionator LibAHTab-1-0 compatibility: CreateTab returns nil & tabFrame reparents to AuctionHouseFrame
	local origLibStub = _G.LibStub
	local extTabs = {}
	local extBtn = CreateFrame("Button", "LibAHFrame-1.0-MerchantMaster_Sell", UIParent)
	local extSelected = nil
	local extLibAHTab = {
		DoesIDExist = function(_, id) return extTabs[id] ~= nil end,
		CreateTab = function(_, id, attachedFrame, displayText, tabHeader)
			extTabs[id] = { frameRef = attachedFrame, displayText = displayText, tabHeader = tabHeader, btn = extBtn }
			extBtn:SetText(displayText)
			attachedFrame:Hide()
			return nil
		end,
		GetButton = function(_, id) return extTabs[id] and extTabs[id].btn or nil end,
		SetSelected = function(_, id)
			extSelected = id
			if extTabs[id] and extTabs[id].frameRef then extTabs[id].frameRef:Show() end
		end,
	}
	_G.LibStub = setmetatable({}, {
		__call = function(_, name)
			if name == "LibAHTab-1-0" then return extLibAHTab end
			if origLibStub then return origLibStub(name) end
			return nil
		end,
	})
	local mockAuctionatorAH = CreateFrame("Frame", "MockAuctionatorAHFrame", UIParent)
	mockAuctionatorAH:SetSize(820, 540)
	mockAuctionatorAH.Tabs = { CreateFrame("Button", "MockAucTab1", UIParent) }
	mockAuctionatorAH.IsShown = function() return true end
	mockAuctionatorAH.SetDisplayMode = function() end
	_G.AuctionHouseFrame = mockAuctionatorAH
	tab.EnsureAttached()
	check(tab.tabButton == extBtn and extBtn:GetText() == "MM Sell",
		"RegC: Real LibAHTab CreateTab returning nil resolves tabButton via GetButton")
	check(tab.frame and tab.frame.GetParent and tab.frame:GetParent() == mockAuctionatorAH,
		"RegC: EnsureAttached reparents MM Sell frame onto active AuctionHouseFrame")
	tab.SelectTab()
	check(extSelected == "MerchantMaster_Sell" and tab.IsShown(),
		"RegC: SelectTab delegates through external LibAHTab SetSelected cleanly")
	tab.OnAuctionHouseClosed()
	_G.LibStub = origLibStub

	if MerchantMasterDB then
		if MerchantMasterDB.ahDaily and MerchantMasterDB.ahDaily[econ] then
			MerchantMasterDB.ahDaily[econ][96001] = nil
		end
		MerchantMasterDB.ahDaily = origDaily
	end
	_G.hooksecurefunc = origHookSec
	_G.AuctionHouseFrame = origAHF
	_G.C_AuctionHouse = origAH
	_G.C_Container = origCCont
	_G.GetCursorInfo = origCurInfo
	_G.ClearCursor = origClearCur
	_G.GetItemInfo = origGetItemInfo
	_G.C_Item = origCItem
	bagDirtyReset()
end
runStandaloneMMSellTabRegression()

-- Regression D: Sell Auto-Refresh (SelectTab / atAH / 0.45s retry + cancel) & TopBar Redesign (UcBtns, Equip/Vendor, Wide/Compact Bounds)
local function runSellAutoRefreshAndTopBarRedesignTests()
	local of = ns.MarketScan.OrderFlow
	local tab = ns.AHSellTab
	local origAHF = _G.AuctionHouseFrame
	local origAH = _G.C_AuctionHouse
	local origCCont = _G.C_Container
	local origGetItemInfo = _G.GetItemInfo
	local origCItem = _G.C_Item
	local origGetTime = _G.GetTime
	local origTimerAfter = _G.C_Timer and _G.C_Timer.After
	local origTryAcquire = ns.AHChannel and ns.AHChannel.TryAcquire

	local simTime = 1000.0
	_G.GetTime = function() return simTime end

	local pendingTimers = {}
	if _G.C_Timer then
		_G.C_Timer.After = function(delay, fn)
			pendingTimers[#pendingTimers + 1] = { at = simTime + (delay or 0), delay = delay or 0, fn = fn, fired = false }
		end
	end
	local function runTimers(dt)
		simTime = simTime + (dt or 0)
		local i = 1
		while i <= #pendingTimers do
			local t = pendingTimers[i]
			if not t.fired and t.at <= simTime + 1e-6 then
				t.fired = true
				t.fn()
			end
			i = i + 1
		end
	end

	local ahOpen = true
	local mockAHF = CreateFrame("Frame", "MockSellRefreshAHFrame", UIParent)
	mockAHF:SetSize(1080, 660)
	mockAHF.IsShown = function() return ahOpen end
	mockAHF.SetDisplayMode = function() end
	_G.AuctionHouseFrame = mockAHF

	local mockBag = {
		[1] = { itemID = 97001, stackCount = 12, quality = 1, isLocked = false, isBound = false,
			hyperlink = "|cffffffff|Hitem:97001::::::::60:::::::|h[Refresh Elixir]|h|r" },
		[2] = { itemID = 97002, stackCount = 1, quality = 3, isLocked = false, isBound = false,
			hyperlink = "|cff0070dd|Hitem:97002::::::::60:::::::|h[Refresh Helm]|h|r" },
	}
	local meta = {
		[97001] = { name = "Refresh Elixir", quality = 1, ilvl = 55, class = "Consumable", classID = 0, maxStack = 20, vendor = 500 },
		[97002] = { name = "Refresh Helm", quality = 3, ilvl = 62, class = "Armor", classID = 4, maxStack = 1, vendor = 2500 },
	}
	_G.C_Container = {
		GetContainerNumSlots = function(b) return (b == 0) and 2 or 0 end,
		GetContainerItemInfo = function(b, s) return (b == 0) and mockBag[s] or nil end,
	}
	_G.GetItemInfo = function(q)
		local id = tonumber(q) or tonumber(tostring(q or ""):match("item:(%d+)"))
		local m = id and meta[id]
		if not m then return nil end
		return m.name, "|cffffffff|Hitem:" .. id .. "|h[" .. m.name .. "]|h|r", m.quality, m.ilvl, 45, m.class, m.class, m.maxStack, "", 134400, m.vendor, m.classID, 0
	end
	_G.C_Item = {
		GetItemInfo = _G.GetItemInfo,
		GetItemIconByID = function() return 134400 end,
		DoesItemExist = function(loc) return loc and mockBag[loc.slotIndex] ~= nil end,
		IsBound = function() return false end,
	}

	local throttleReady = true
	local channelBusy = false
	local searchDispatches = {}
	_G.C_AuctionHouse = {
		IsSellItemValid = function() return true end,
		GetItemCommodityStatus = function(loc)
			local s = loc and mockBag[loc.slotIndex]
			return (s and s.itemID == 97002) and 1 or 2
		end,
		GetItemKeyFromItem = function(loc)
			local s = loc and mockBag[loc.slotIndex]
			local id = s and s.itemID or 0
			return { itemID = id, itemLevel = (id == 97002) and 62 or 0, itemSuffix = 0, battlePetSpeciesID = 0 }
		end,
		MakeItemKey = function(id, ilvl) return { itemID = id, itemLevel = ilvl or 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
		GetItemKeyInfo = function(k) return { itemID = k.itemID, isCommodity = (k.itemID ~= 97002) } end,
		SendSellSearchQuery = function(k) searchDispatches[#searchDispatches + 1] = k.itemID end,
		SendSearchQuery = function(k) searchDispatches[#searchDispatches + 1] = k.itemID end,
		IsThrottledMessageSystemReady = function() return throttleReady end,
		CalculateCommodityDeposit = function(_, dur, qty) return (dur or 2) * 100 * (qty or 1) end,
		CalculateItemDeposit = function(_, dur, qty) return (dur or 2) * 200 * (qty or 1) end,
	}
	if ns.AHChannel and origTryAcquire then
		ns.AHChannel.TryAcquire = function(owner, opts)
			if channelBusy then return false end
			return origTryAcquire(owner, opts)
		end
	end

	of.ClearSavedState()
	local st = of.GetState()
	local sl = st.stages.sell
	st.env.atAH = false -- intentionally stale to prove live atAH() works!

	-- 1. AddBagItemToSell & SelectSellItem trigger live scan via atAH() even when orderFlow.env.atAH == false
	searchDispatches = {}
	of.AddBagItemToSell(97001, nil, { useDefaultQty = true })
	check(#searchDispatches == 1 and searchDispatches[1] == 97001,
		"RegD: AddBagItemToSell triggers live AH scan via atAH() even when orderFlow.env.atAH == false")
	sl.pendingSearch = nil
	if ns.AHChannel and ns.AHChannel.Release then ns.AHChannel.Release("orderflow_sell") end

	searchDispatches = {}
	of.AddBagItemToSell(97002, nil, { useDefaultQty = true })
	check(#searchDispatches == 1 and searchDispatches[1] == 97002,
		"RegD: AddBagItemToSell triggers live AH scan for equipment (97002) via atAH()")
	sl.pendingSearch = nil
	if ns.AHChannel and ns.AHChannel.Release then ns.AHChannel.Release("orderflow_sell") end

	searchDispatches = {}
	of.SelectSellItem(1)
	check(#searchDispatches == 1 and searchDispatches[1] == 97001,
		"RegD: SelectSellItem triggers live AH scan via atAH() even when orderFlow.env.atAH == false")
	sl.pendingSearch = nil
	if ns.AHChannel and ns.AHChannel.Release then ns.AHChannel.Release("orderflow_sell") end

	-- 2. SelectTab ALWAYS refreshes even when cur.listingsScanned == true, dedupes within 2s, resets on HideTab
	sl.items[1].listingsScanned = true
	tab.HideTab()
	searchDispatches = {}
	tab.SelectTab()
	check(#searchDispatches == 1 and searchDispatches[1] == 97001,
		"RegD: SelectTab triggers live AH scan even when cur.listingsScanned == true")
	sl.pendingSearch = nil
	if ns.AHChannel and ns.AHChannel.Release then ns.AHChannel.Release("orderflow_sell") end

	-- Rapid re-call within 2s dedupes
	simTime = simTime + 0.5
	searchDispatches = {}
	tab.SelectTab()
	check(#searchDispatches == 0,
		"RegD: Rapid SelectTab within 2s dedupes redundant same-item scan")

	-- HideTab resets dedupe -> reopening immediately scans even within 2s
	tab.HideTab()
	searchDispatches = {}
	tab.SelectTab()
	check(#searchDispatches == 1 and searchDispatches[1] == 97001,
		"RegD: HideTab resets auto-scan dedupe so reopening MM Sell immediately refreshes live AH")
	sl.pendingSearch = nil
	if ns.AHChannel and ns.AHChannel.Release then ns.AHChannel.Release("orderflow_sell") end

	-- 3. Throttled / channel_busy schedule a single 0.45s retry; executes when ready & cancels on AH close or Vendor switch
	pendingTimers = {}
	searchDispatches = {}
	throttleReady = false
	local okTh, errTh = of.ScanSellItemMarket(1, "select")
	check(okTh == false and errTh == "throttled" and #pendingTimers == 1 and math.abs(pendingTimers[1].delay - 0.45) < 0.01,
		"RegD: Throttled ScanSellItemMarket schedules a single 0.45s retry timer")
	throttleReady = true
	runTimers(0.45)
	check(#searchDispatches == 1 and searchDispatches[1] == 97001,
		"RegD: 0.45s throttled retry dispatches live scan once AH throttle clears")
	sl.pendingSearch = nil
	if ns.AHChannel and ns.AHChannel.Release then ns.AHChannel.Release("orderflow_sell") end

	-- channel_busy schedules 0.45s retry -> executes once channel releases
	pendingTimers = {}
	searchDispatches = {}
	channelBusy = true
	local okBusy, errBusy = of.ScanSellItemMarket(1, "select")
	check(okBusy == false and errBusy == "channel_busy" and #pendingTimers == 1,
		"RegD: channel_busy ScanSellItemMarket schedules a single 0.45s retry timer")
	channelBusy = false
	runTimers(0.45)
	check(#searchDispatches == 1 and searchDispatches[1] == 97001,
		"RegD: 0.45s channel_busy retry dispatches live scan once AHChannel clears")
	sl.pendingSearch = nil
	if ns.AHChannel and ns.AHChannel.Release then ns.AHChannel.Release("orderflow_sell") end

	-- Retry cancels cleanly if OnAuctionHouseClosed fires before 0.45s (even if AH reopens before 0.45s!)
	pendingTimers = {}
	searchDispatches = {}
	throttleReady = false
	of.ScanSellItemMarket(1, "select")
	of.OnAuctionHouseClosed()
	throttleReady = true
	ahOpen = true
	runTimers(0.45)
	check(#searchDispatches == 0,
		"RegD: 0.45s retry cancels cleanly after OnAuctionHouseClosed (searchSerial guard)")

	-- Retry cancels cleanly if item switches to vendor before 0.45s
	pendingTimers = {}
	searchDispatches = {}
	throttleReady = false
	of.ScanSellItemMarket(1, "select")
	of.SetSellItemChannel(1, "vendor")
	throttleReady = true
	runTimers(0.45)
	check(#searchDispatches == 0,
		"RegD: 0.45s retry cancels cleanly when item channel switches to vendor")
	of.SetSellItemChannel(1, "ah")
	sl.pendingSearch = nil
	if ns.AHChannel and ns.AHChannel.Release then ns.AHChannel.Release("orderflow_sell") end

	-- 4. Side-by-side sellUcBtns (Match, -1c, -1s, -1%) + backward-compat sellUcBtn
	check(tab.sellUcBtns and #tab.sellUcBtns == 4,
		"RegD: sellUcBtns exposes 4 side-by-side undercut rule buttons")
	tab.sellUcBtns[2]:Click("LeftButton")
	check(sl.undercutMode == "1c", "RegD: sellUcBtns[2] sets undercutMode = '1c'")
	tab.sellUcBtns[3]:Click("LeftButton")
	check(sl.undercutMode == "1s", "RegD: sellUcBtns[3] sets undercutMode = '1s'")
	tab.sellUcBtns[4]:Click("LeftButton")
	check(sl.undercutMode == "pct", "RegD: sellUcBtns[4] sets undercutMode = 'pct'")
	tab.sellUcBtns[1]:Click("LeftButton")
	check(sl.undercutMode == "match", "RegD: sellUcBtns[1] sets undercutMode = 'match'")
	tab.sellUcBtn:Click("LeftButton")
	check(sl.undercutMode == "1c", "RegD: Backward-compat sellUcBtn proxy still cycles match -> 1c")

	-- 5. Commodity vs Equipment vs Vendor visibility & live vendor typing readout
	of.SelectSellItem(1)
	sl.pendingSearch = nil
	tab.Render()
	check(tab.sellUnitRow:IsShown() and not tab.sellBidRow:IsShown(),
		"RegD: Commodity shows Price/Item summary row and hides Starting Bid row")

	of.SelectSellItem(2)
	sl.pendingSearch = nil
	tab.Render()
	check(tab.sellBidRow:IsShown() and tab.sellUnitRow:IsShown() and tab.sellSummaryCard:IsShown(),
		"RegD: Equipment shows Starting Bid row and keeps Price/Item summary card visible")

	-- Vendor-flagged item keeps AH form & Zone 3 Vendor Value alert bar visible cleanly; typing live updates Vendor Value warning!
	of.SetSellItemChannel(1, "vendor")
	of.SelectSellItem(1)
	tab.Render()
	check(tab.sellForm:IsShown() and tab.sellVendorBar == nil and tab.sellVendorRow:IsShown()
		and tab.postBtn:IsShown() and tab.sellRefreshBtn:IsShown()
		and tab.sellDurLbl:IsShown() and tab.sellDurBtns[1]:IsShown()
		and tab.sellRuleLbl:IsShown() and tab.sellUcBtns[1]:IsShown(),
		"RegD: MM Sell keeps AH form, Vendor Value bar, Duration, and Rule buttons visible cleanly")

	of.SetSellItemChannel(1, "ah")
	sl.pendingSearch = nil
	tab.Render()
	-- Live typing in price boxes triggers sellVendorRow 5% AH cut warning live (vendorSell=500c -> 526c * 0.95 = 499c < 500c!)
	tab.sellPriceGBox:SetText("0")
	tab.sellPriceSBox:SetText("5")
	tab.sellPriceCBox:SetText("26")
	local pOnTxt = tab.sellPriceCBox:GetScript("OnTextChanged")
	if pOnTxt then pOnTxt(tab.sellPriceCBox, true) end
	check(tab.sellVendorRow._isBelowVendor == true and stripColors(tab.sellVendorValFs:GetText()):find("(> AH Net!)", 1, true) ~= nil,
		"RegD: Live typing price 5s26c (95% net 499c < 500c vendor) flags sellVendorRow warning live")
	tab.sellPriceCBox:SetText("27")
	if pOnTxt then pOnTxt(tab.sellPriceCBox, true) end
	check(tab.sellVendorRow._isBelowVendor == false and stripColors(tab.sellVendorValFs:GetText()):find("(> AH Net!)", 1, true) == nil,
		"RegD: Live typing price 5s27c (95% net 500c >= 500c vendor) clears sellVendorRow warning live")

	-- Scroll-perf assertion: 20 bag scrolls + 20 prices scrolls execute ZERO ScanSellableBags / GetContainerItemInfo calls!
	local perfListings = {}
	for i = 1, 30 do
		perfListings[i] = { price = 10000 + i * 100, quantity = 5, containsOwnerItem = (i == 2) }
	end
	sl.items[1].currentListings = perfListings
	sl.items[1].listingsScanned = true
	tab.SetSubTab("prices")
	tab.Render()
	local scanCallsDuringScroll = 0
	local contCallsDuringScroll = 0
	local origScanBags = of.ScanSellableBags
	local origGetCont = _G.C_Container.GetContainerItemInfo
	of.ScanSellableBags = function(...)
		scanCallsDuringScroll = scanCallsDuringScroll + 1
		return origScanBags(...)
	end
	_G.C_Container.GetContainerItemInfo = function(...)
		contCallsDuringScroll = contCallsDuringScroll + 1
		return origGetCont(...)
	end
	local bagWheelFn = tab.sellBagGrid:GetScript("OnMouseWheel")
	local pricesWheelFn = tab.sellPricesListArea:GetScript("OnMouseWheel")
	for i = 1, 20 do
		bagWheelFn(tab.sellBagGrid, (i % 2 == 1) and -1 or 1)
		pricesWheelFn(tab.sellPricesListArea, (i % 2 == 1) and -1 or 1)
	end
	of.ScanSellableBags = origScanBags
	_G.C_Container.GetContainerItemInfo = origGetCont
	check(scanCallsDuringScroll == 0 and contCallsDuringScroll == 0,
		"RegD Perf: 20 bag scrolls + 20 prices scrolls execute 0 ScanSellableBags ("
			.. tostring(scanCallsDuringScroll) .. ") and 0 GetContainerItemInfo (" .. tostring(contCallsDuringScroll) .. ") calls")

	-- 6. Wide (1080px host -> 1048px topBar) and Compact (796px host -> 764px topBar) layoutTopBar bounds: zero overflow past topDiv2
	local function getPointX(widget)
		if widget and widget.GetPoint then
			local _, _, _, x = widget:GetPoint(1)
			return tonumber(x) or 0
		end
		return 0
	end
	mockAHF:SetSize(1080, 660)
	tab.topBar:SetWidth(1048)
	tab.Render()
	local wideFormRight = getPointX(tab.sellForm) + (tab.sellForm:GetWidth() or 0)
	local wideDiv2X = getPointX(tab.topDiv2)
	check(wideDiv2X > 0 and wideFormRight < wideDiv2X,
		"RegD: Wide layoutTopBar keeps sellForm strictly left of topDiv2 (" .. tostring(wideFormRight) .. " < " .. tostring(wideDiv2X) .. ")")

	mockAHF:SetSize(800, 540)
	tab.topBar:SetWidth(768)
	tab.Render()
	local cmpFormRight = getPointX(tab.sellForm) + (tab.sellForm:GetWidth() or 0)
	local cmpDiv2X = getPointX(tab.topDiv2)
	check(cmpDiv2X > 0 and cmpFormRight < cmpDiv2X,
		"RegD: Compact (768px) layoutTopBar keeps sellForm strictly left of topDiv2 (" .. tostring(cmpFormRight) .. " < " .. tostring(cmpDiv2X) .. ")")

	-- 7. Wave 2 MM Sell UX Upgrades: Zero-shift Notice Bar, hint removal, hover/press polish, Zone 2/3 layout, 5-row live Summary Card
	mockAHF:SetSize(1080, 660)
	tab.topBar:SetWidth(1048)

	-- 7a. Always-shown noticeBar ("Waiting for first action..." when nil) & zero layout shift on sellBagPane
	st.notice = nil
	st.noticeKind = nil
	tab.Render()
	check(tab.noticeBar ~= nil and tab.noticeBar:IsShown() == true
		and stripColors(tab.noticeFs:GetText()) == "Waiting for first action...",
		"Sell UX: noticeBar stays visible with 'Waiting for first action...' when st.notice is nil")
	local bagP1, bagRel1, bagRp1, bagX1, bagY1 = tab.sellBagPane:GetPoint(1)

	st.notice = "Added [Refresh Elixir] x12 to Sell Queue"
	st.noticeKind = "positive"
	tab.Render()
	check(tab.noticeBar:IsShown() == true
		and stripColors(tab.noticeFs:GetText()):find("Added [Refresh Elixir]", 1, true) ~= nil,
		"Sell UX: noticeBar renders active positive notice text")
	local bagP2, bagRel2, bagRp2, bagX2, bagY2 = tab.sellBagPane:GetPoint(1)
	check(bagP1 == bagP2 and bagRel1 == tab.noticeBar and bagRel2 == tab.noticeBar
		and bagRp1 == bagRp2 and bagX1 == bagX2 and bagY1 == bagY2,
		"Sell UX: sellBagPane anchor never shifts between nil notice and active notice")

	-- 7b. Removed dropHintBox / sellBagHintFs while iconDropBtn drag/click drop still works
	check(tab.dropHintBox == nil and tab.sellBagHintFs == nil,
		"Sell UX: dropHintBox and sellBagHintFs are removed (nil)")
	local origGetCursorInfo = _G.GetCursorInfo
	local origCCursor = _G.C_Cursor
	local origClearCursor = _G.ClearCursor
	_G.GetCursorInfo = function() return "item", 97001, "|cffffffff|Hitem:97001|h[Refresh Elixir]|h|r" end
	_G.C_Cursor = { GetCursorItem = function() return { bagID = 0, slotIndex = 1 } end }
	_G.ClearCursor = function() end
	local dropOk = false
	local origDropPulse = tab.iconDropBtn.PlayPressPulse
	local dropPulsed = false
	tab.iconDropBtn.PlayPressPulse = function(self, ...)
		dropPulsed = true
		return origDropPulse(self, ...)
	end
	if tab.iconDropBtn:GetScript("OnReceiveDrag") then
		tab.iconDropBtn:GetScript("OnReceiveDrag")(tab.iconDropBtn)
		dropOk = true
	end
	tab.iconDropBtn.PlayPressPulse = origDropPulse
	_G.GetCursorInfo = origGetCursorInfo
	_G.C_Cursor = origCCursor
	_G.ClearCursor = origClearCursor
	runTimers(0.12)
	check(dropOk and dropPulsed and sl.items[1] and sl.items[1].itemID == 97001,
		"Sell UX: iconDropBtn OnReceiveDrag triggers PlayPressPulse and stages cursor item cleanly")

	-- 7c. Hover highlight (hoverTex), press micro-animation (pressTex, OnMouseDown/OnMouseUp/PostClick, PlayPressPulse) & ZERO OnUpdate
	local function verifyInteractivePolish(widget, label, isTile)
		check(widget ~= nil, "Sell UX: " .. label .. " exists")
		check(widget.hoverTex ~= nil and widget.pressTex ~= nil,
			"Sell UX: " .. label .. " pre-allocates hoverTex and pressTex")
		check(type(widget.PlayPressPulse) == "function",
			"Sell UX: " .. label .. " exposes PlayPressPulse()")
		check(widget.GetScript and widget:GetScript("OnUpdate") == nil,
			"Sell UX: " .. label .. " has ZERO OnUpdate script")
		local onEnter = widget:GetScript("OnEnter")
		local onLeave = widget:GetScript("OnLeave")
		local onDown = widget:GetScript("OnMouseDown")
		local onUp = widget:GetScript("OnMouseUp")
		local postClick = widget:GetScript("PostClick")
		check(type(onEnter) == "function" and type(onLeave) == "function"
			and type(onDown) == "function" and type(onUp) == "function",
			"Sell UX: " .. label .. " defines OnEnter, OnLeave, OnMouseDown, OnMouseUp")
		if not isTile then
			check(type(postClick) == "function", "Sell UX: " .. label .. " defines PostClick press pulse")
		end
		onEnter(widget)
		check(widget.hoverTex:IsShown() == true, "Sell UX: " .. label .. " OnEnter shows hoverTex")
		onLeave(widget)
		check(widget.hoverTex:IsShown() == false, "Sell UX: " .. label .. " OnLeave hides hoverTex")
		onDown(widget)
		check(widget._pressed == true, "Sell UX: " .. label .. " OnMouseDown sets _pressed")
		if not isTile then
			check(widget.pressTex:IsShown() == true, "Sell UX: " .. label .. " OnMouseDown shows pressTex")
		end
		onUp(widget)
		check(widget._pressed == false and widget.pressTex:IsShown() == false,
			"Sell UX: " .. label .. " OnMouseUp clears _pressed and hides pressTex")
		widget:PlayPressPulse()
		check(widget.pressTex:IsShown() == true, "Sell UX: " .. label .. " PlayPressPulse shows pressTex")
		runTimers(0.12)
		check(widget.pressTex:IsShown() == false, "Sell UX: " .. label .. " PlayPressPulse restores pressTex after timer")
	end

	of.SelectSellItem(1)
	sl.pendingSearch = nil
	tab.Render()
	verifyInteractivePolish(tab.sellBagTiles[1], "sellBagTiles[1]", true)
	verifyInteractivePolish(tab.postBtn, "postBtn", false)
	verifyInteractivePolish(tab.sellRefreshBtn, "sellRefreshBtn", false)
	verifyInteractivePolish(tab.sellUcBtns[1], "sellUcBtns[1]", false)
	verifyInteractivePolish(tab.sellDurBtns[1], "sellDurBtns[1]", false)

	-- 7d. Layout hierarchy: sellUcBtns in sellForm below sellPriceRow; sellDurBtns in sellZone3 between sellVendorRow and sellSummaryCard
	local function getPointY(widget)
		if widget and widget.GetPoint then
			local _, _, _, _, y = widget:GetPoint(1)
			return tonumber(y) or 0
		end
		return 0
	end
	check(tab.sellRuleRow:GetParent() == tab.sellForm
		and tab.sellUcBtns[1]:GetParent() == tab.sellRuleRow
		and getPointY(tab.sellRuleRow) < getPointY(tab.sellPriceRow),
		"Sell UX: sellUcBtns sit inside sellForm strictly below sellPriceRow")
	check(tab.sellDurRow:GetParent() == tab.sellZone3
		and tab.sellDurBtns[1]:GetParent() == tab.sellDurRow
		and tab.sellDepRow and tab.sellDepRow:GetParent() == tab.sellZone3
		and getPointY(tab.sellDurRow) < getPointY(tab.sellVendorRow)
		and getPointY(tab.sellDepRow) < getPointY(tab.sellDurRow)
		and getPointY(tab.sellSummaryCard) < getPointY(tab.sellDepRow),
		"Sell UX: sellDepRow stands alone in sellZone3 strictly between sellDurRow and sellSummaryCard")

	local function fsSizeOf(fs)
		if fs and fs.GetFont then return select(2, fs:GetFont()) end
		return nil
	end
	check(fsSizeOf(tab.sellVendorLbl) == 10 and fsSizeOf(tab.sellVendorValFs) == 10
		and fsSizeOf(tab.sellDepLbl) == 10 and fsSizeOf(tab.sellDepValFs) == 10
		and fsSizeOf(tab.sellUnitLbl) == 10 and fsSizeOf(tab.sellUnitSummaryFs) == 10
		and fsSizeOf(tab.sellTotalLbl) == 10 and fsSizeOf(tab.sellTotalValFs) == 10
		and fsSizeOf(tab.sellCutLbl) == 10 and fsSizeOf(tab.sellCutValFs) == 10
		and fsSizeOf(tab.sellNetLbl) == 10.5 and fsSizeOf(tab.sellNetValFs) == 10.5,
		"Sell UX: uniform 10pt summary/deposit row fonts and 10.5pt Net Payout font")

	-- 7e. sellSummaryCard renders all 5 summary rows and updates live on Price/Qty typing & Duration switch
	check(tab.sellSummaryCard:IsShown() == true and tab.sellUnitRow:IsShown() == true,
		"Sell UX: sellSummaryCard and sellUnitRow are visible")
	check(stripColors(tab.sellUnitLbl:GetText()):find("Price / Item", 1, true) ~= nil
		and stripColors(tab.sellTotalLbl:GetText()):find("Total Price", 1, true) ~= nil
		and stripColors(tab.sellCutLbl:GetText()):find("AH Cut (5%)", 1, true) ~= nil
		and stripColors(tab.sellDepLbl:GetText()):find("Deposit", 1, true) ~= nil
		and stripColors(tab.sellNetLbl:GetText()):find("Net Payout (95%)", 1, true) ~= nil,
		"Sell UX: sellSummaryCard displays all 5 summary row labels")

	of.SelectSellItem(1)
	sl.pendingSearch = nil
	tab.Render()
	tab.sellQtyBox:SetText("3")
	local qOnTxt = tab.sellQtyBox:GetScript("OnTextChanged")
	if qOnTxt then qOnTxt(tab.sellQtyBox, true) end
	tab.sellPriceGBox:SetText("10")
	tab.sellPriceSBox:SetText("0")
	tab.sellPriceCBox:SetText("0")
	if pOnTxt then pOnTxt(tab.sellPriceCBox, true) end
	-- 3 * 10g = 30g gross; 5% cut = 1g 50s; 95% net = 28g 50s
	local function normCoin(s)
		return stripColors(s)
			:gsub("|T[^|]*GoldIcon[^|]*|t", "g")
			:gsub("|T[^|]*SilverIcon[^|]*|t", "s")
			:gsub("|T[^|]*CopperIcon[^|]*|t", "c")
	end
	local unitTxt = normCoin(tab.sellUnitSummaryFs:GetText())
	local totalTxt = normCoin(tab.sellTotalValFs:GetText())
	local cutTxt = normCoin(tab.sellCutValFs:GetText())
	local netTxt = normCoin(tab.sellNetValFs:GetText())
	check(unitTxt:find("10g", 1, true) ~= nil and unitTxt:find("9g 50s", 1, true) ~= nil,
		"Sell UX: Price/Item summary updates live to 10g (Net 9g 50s), got: " .. unitTxt)
	check(totalTxt:find("30g", 1, true) ~= nil,
		"Sell UX: Total Price updates live to 30g, got: " .. totalTxt)
	check(cutTxt:find("1g 50s", 1, true) ~= nil,
		"Sell UX: AH Cut (5%) updates live to -1g 50s, got: " .. cutTxt)
	check(netTxt:find("28g 50s", 1, true) ~= nil,
		"Sell UX: Net Payout (95%) updates live to 28g 50s, got: " .. netTxt)

	local depBeforeDur = stripColors(tab.sellDepValFs:GetText())
	tab.sellDurBtns[3]:Click("LeftButton") -- switch 8h -> 24h
	local depLblAfter = stripColors(tab.sellDepLbl:GetText())
	local depAfterDur = stripColors(tab.sellDepValFs:GetText())
	check(depLblAfter:find("24h", 1, true) ~= nil and depAfterDur ~= depBeforeDur,
		"Sell UX: switching duration to 24h updates Deposit label and value live")

	-- 7f. Bottom AH MerchantMaster logo button next to MM Sell opens AH Buying Task Strip
	if app.ensureAuctionHouseMMTab then
		local ahMMTab = app.ensureAuctionHouseMMTab()
		check(ahMMTab ~= nil and ahMMTab == _G.MerchantMasterAHTabBtn and ahMMTab:IsShown(),
			"AH bottom MerchantMaster logo tab button is created and visible beside MM Sell")
		local pt = ahMMTab._points and ahMMTab._points[1]
		check(pt and pt[1] == "TOPLEFT" and pt[3] == "TOPRIGHT",
			"MerchantMasterAHTabBtn anchors TOPLEFT -> TOPRIGHT beside MM Sell tab")
		local onClick = ahMMTab:GetScript("OnClick")
		check(type(onClick) == "function", "MerchantMasterAHTabBtn registers Left/Right OnClick")
		onClick(ahMMTab, "LeftButton")
		check(app.ui and app.ui.cartBuyerModal and app.ui.cartBuyerModal:IsShown(),
			"Clicking MerchantMasterAHTabBtn opens the AH Buying Task Strip")
		if app.exitAHBuyingMode then app.exitAHBuyingMode(false) end
		if app.ui and app.ui.cartBuyerModal and app.ui.cartBuyerModal.Hide then
			app.ui.cartBuyerModal:Hide()
		end
		ahMMTab:Hide()
	end

	-- Cleanup
	tab.HideTab()
	of.ClearSavedState()
	if ns.AHChannel and origTryAcquire then ns.AHChannel.TryAcquire = origTryAcquire end
	if _G.C_Timer and origTimerAfter then _G.C_Timer.After = origTimerAfter end
	_G.GetTime = origGetTime
	_G.AuctionHouseFrame = origAHF
	_G.C_AuctionHouse = origAH
	_G.C_Container = origCCont
	_G.GetItemInfo = origGetItemInfo
	_G.C_Item = origCItem
	if ns.MarketScan and ns.MarketScan.MarkBagsDirty then ns.MarketScan.MarkBagsDirty() end
end
runSellAutoRefreshAndTopBarRedesignTests()

-- =============================================================================
-- Stage 2 Collect All (Bank + Mail batch workflow + UI spotlight buttons)
-- =============================================================================
local function runCollectAllTests()
	local of = app.orderFlow
	local modal = app.ui and app.ui.cartBuyerModal
	local origCCont = _G.C_Container
	local origClearCursor = _G.ClearCursor
	local origBF = _G.BankFrame
	local origMailF = _G.MailFrame
	local origGetTime = _G.GetTime
	local origTimerAfter = _G.C_Timer and _G.C_Timer.After
	local origGetInboxNum = _G.GetInboxNumItems
	local origGetInboxHeader = _G.GetInboxHeaderInfo
	local origGetInboxItem = _G.GetInboxItem
	local origGetInboxLink = _G.GetInboxItemLink
	local origTakeInbox = _G.TakeInboxItem
	local origMailHelper = ns.MailHelper
	local origGetBag = app.getBagCountByID

	local mockNow = 70000
	_G.GetTime = function() return mockNow end

	local scheduledTimers = {}
	if _G.C_Timer then
		_G.C_Timer.After = function(delay, fn)
			scheduledTimers[#scheduledTimers + 1] = { at = mockNow + (tonumber(delay) or 0), delay = tonumber(delay) or 0, fn = fn }
		end
	end
	local function advanceTimers(sec)
		mockNow = mockNow + sec
		local keep, run = {}, {}
		for _, t in ipairs(scheduledTimers) do
			if t.at <= mockNow then run[#run + 1] = t.fn else keep[#keep + 1] = t end
		end
		scheduledTimers = keep
		for _, fn in ipairs(run) do fn() end
	end

	-- Mock bags (0..1, 4 slots each) and bank (-1, 6 slots)
	local mockBagMax = { [0] = 4, [1] = 4, [-1] = 6 }
	local mockCont = { [0] = {}, [1] = {}, [-1] = {} }
	local function clearCont(bag)
		mockCont[bag] = {}
	end
	local function setSlot(bag, slot, itemID, qty, locked)
		if itemID and qty and qty > 0 then
			mockCont[bag][slot] = { itemID = itemID, stackCount = qty, isLocked = locked or false }
		else
			mockCont[bag][slot] = nil
		end
	end
	local function addBagItem(itemID, qty)
		for b = 0, 1 do
			for s = 1, mockBagMax[b] do
				local cell = mockCont[b][s]
				if cell and cell.itemID == itemID then
					cell.stackCount = cell.stackCount + qty
					return true
				end
			end
		end
		for b = 0, 1 do
			for s = 1, mockBagMax[b] do
				if not mockCont[b][s] then
					mockCont[b][s] = { itemID = itemID, stackCount = qty, isLocked = false }
					return true
				end
			end
		end
		return false
	end
	local function bagCount(itemID)
		local tot = 0
		for b = 0, 1 do
			for s = 1, mockBagMax[b] do
				local cell = mockCont[b][s]
				if cell and cell.itemID == itemID then tot = tot + (cell.stackCount or 0) end
			end
		end
		return tot
	end

	local useCalls, splitCalls, pickupCalls, clearCursorCount = {}, {}, {}, 0
	local splitPending = nil
	_G.ClearCursor = function()
		clearCursorCount = clearCursorCount + 1
		splitPending = nil
	end
	_G.C_Container = {
		GetContainerNumSlots = function(b) return mockBagMax[b] or 0 end,
		GetContainerItemInfo = function(b, s)
			local c = mockCont[b] and mockCont[b][s]
			if not c then return nil end
			return { itemID = c.itemID, stackCount = c.stackCount, isLocked = c.isLocked }
		end,
		GetContainerItemID = function(b, s)
			local c = mockCont[b] and mockCont[b][s]
			return c and c.itemID or nil
		end,
		UseContainerItem = function(b, s)
			useCalls[#useCalls + 1] = { bag = b, slot = s }
			local c = mockCont[b] and mockCont[b][s]
			if c then
				addBagItem(c.itemID, c.stackCount)
				mockCont[b][s] = nil
			end
		end,
		SplitContainerItem = function(b, s, qty)
			splitCalls[#splitCalls + 1] = { bag = b, slot = s, qty = qty }
			local c = mockCont[b] and mockCont[b][s]
			if c and c.stackCount >= qty then
				c.stackCount = c.stackCount - qty
				if c.stackCount <= 0 then mockCont[b][s] = nil end
				splitPending = { itemID = c.itemID, qty = qty }
			end
		end,
		PickupContainerItem = function(b, s)
			pickupCalls[#pickupCalls + 1] = { bag = b, slot = s }
			if splitPending then
				setSlot(b, s, splitPending.itemID, splitPending.qty, false)
				splitPending = nil
			end
		end,
	}
	app.getBagCountByID = bagCount

	local bf = _G.CreateFrame("Frame")
	bf:Hide()
	_G.BankFrame = bf
	local mf = _G.CreateFrame("Frame")
	mf:Hide()
	_G.MailFrame = mf

	local mockInbox = {}
	local mailTakeCalls = {}
	_G.GetInboxNumItems = function() return #mockInbox end
	_G.GetInboxHeaderInfo = function(idx)
		local m = mockInbox[idx]
		if not m then return nil end
		return nil, nil, m.sender, m.subject, 0, m.cod or 0, 30, m.hasItem
	end
	_G.GetInboxItem = function(mailIdx, attachIdx)
		local m = mockInbox[mailIdx]
		local a = m and m.attach and m.attach[attachIdx]
		if not a then return nil end
		return a.name, a.itemID, 134400, a.count, 1, true
	end
	_G.GetInboxItemLink = function(mailIdx, attachIdx)
		local m = mockInbox[mailIdx]
		local a = m and m.attach and m.attach[attachIdx]
		if not a then return nil end
		return "|cffffffff|Hitem:" .. tostring(a.itemID) .. "::::::::60:::::|h[" .. a.name .. "]|h|r"
	end
	_G.TakeInboxItem = function(mailIdx, attachIdx)
		mailTakeCalls[#mailTakeCalls + 1] = { mailIdx = mailIdx, attachIdx = attachIdx }
		local m = mockInbox[mailIdx]
		local a = m and m.attach and m.attach[attachIdx]
		if a then
			addBagItem(a.itemID, a.count)
			m.attach[attachIdx] = nil
		end
	end

	-- 1. Closed Bank & Mail guard
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Batch Herb A", itemID = 78101, qty = 0, ownedUsed = 4, ahUnitPrice = 100 },
		{ name = "Batch Herb B", itemID = 78102, qty = 0, ownedUsed = 3, ahUnitPrice = 100 },
		{ name = "Batch Herb C", itemID = 78103, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
	}, {
		title = "Collect All Bank Test",
		ownershipProvider = function(id)
			if id == 78101 then return { bags = 0, bank = 4, mail = 0, alts = {} } end
			if id == 78102 then return { bags = 0, bank = 3, mail = 0, alts = {} } end
			if id == 78103 then return { bags = 0, bank = 2, mail = 0, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	check(of.HasCollectableAtCurrentSource() == false,
		"CollectAll: HasCollectableAtCurrentSource is false when Bank and Mail are closed")
	local closedOk, closedErr = of.CollectAllAtCurrentSource()
	check(closedOk == false and closedErr == "source_closed" and of.IsCollectAllActive() == false
		and of.GetState().notice == "Please open Bank or Mailbox to collect all.",
		"CollectAll: Refuses cleanly when neither Bank nor Mailbox is open")

	-- 2. Bank multi-item batch: Item A exact stack (UseContainerItem), Item B missing (skip), Item C larger stack (SplitContainerItem)
	clearCont(0); clearCont(1); clearCont(-1)
	setSlot(-1, 1, 78101, 4, false)  -- exact match for Item A (4)
	-- Item B (78102) intentionally missing from bank
	setSlot(-1, 2, 78103, 10, false) -- stack of 10 > needed 2 -> split stack!
	bf:Show()
	of.OnBankShow()
	check(of.HasCollectableAtCurrentSource() == true,
		"CollectAll: HasCollectableAtCurrentSource is true when open Bank has matching items")

	useCalls, splitCalls, pickupCalls, clearCursorCount = {}, {}, {}, 0
	scheduledTimers = {}
	local bStartOk = of.CollectAllAtCurrentSource()
	check(bStartOk == true and of.IsCollectAllActive() == true and #useCalls == 1 and useCalls[1].slot == 1,
		"CollectAll Bank: Starts batch and withdraws Item A (exact stack via UseContainerItem)")

	-- Bag update completes Item A and schedules next step after 0.15s
	of.OnBagUpdateDelayed()
	local cItems = of.GetState().stages.collect.items
	local byID = {}
	for _, it in ipairs(cItems) do byID[it.itemID] = it end
	check(byID[78101].status == "done" and byID[78101].collected == 4 and of.IsCollectAllActive() == true,
		"CollectAll Bank: Bag update reconciles Item A (4/4) and keeps batch active")

	-- Advance 0.2s -> skips missing Item B (not_in_bank) and immediately splits Item C (2 from 10)
	advanceTimers(0.2)
	check(#splitCalls == 1 and splitCalls[1].qty == 2 and #pickupCalls == 1 and clearCursorCount >= 1
		and of.IsCollectAllActive() == true,
		"CollectAll Bank: Skips missing Item B and splits 2x Item C from bank stack of 10")

	-- Bag update completes Item C -> advance 0.2s -> finishes cleanly!
	of.OnBagUpdateDelayed()
	advanceTimers(0.2)
	check(byID[78103].status == "done" and byID[78103].collected == 2
		and byID[78102].status ~= "done" and byID[78102].remaining == 3
		and of.IsCollectAllActive() == false
		and of.GetState().notice == "Collected 2 item(s) from Bank (some needed items still pending)."
		and of.GetState().noticeKind == "info",
		"CollectAll Bank: Completes all present items, leaves missing item untouched, and posts honest pending notice")

	-- 3. Bank bags-full stop
	clearCont(0); clearCont(1); clearCont(-1)
	for b = 0, 1 do
		for s = 1, mockBagMax[b] do setSlot(b, s, 99991, 1, false) end
	end
	setSlot(-1, 1, 78102, 10, false)
	of.ScanOpenBank()
	local fullOk, fullErr = of.CollectAllAtCurrentSource()
	check(fullOk == false and fullErr == "bags_full" and of.IsCollectAllActive() == false
		and of.GetState().noticeKind == "warning",
		"CollectAll Bank: Stops cleanly with warning when bags are full")
	clearCont(0); clearCont(1)

	-- 4. Bank close cancel mid-batch + stale timer safety
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Cancel Herb 1", itemID = 78111, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
		{ name = "Cancel Herb 2", itemID = 78112, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
	}, {
		title = "Collect All Bank Close Test",
		ownershipProvider = function(id)
			if id == 78111 or id == 78112 then return { bags = 0, bank = 2, mail = 0, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	clearCont(-1)
	setSlot(-1, 1, 78111, 2, false)
	setSlot(-1, 2, 78112, 2, false)
	bf:Show()
	of.OnBankShow()
	useCalls = {}
	scheduledTimers = {}
	of.CollectAllAtCurrentSource()
	check(of.IsCollectAllActive() == true and #useCalls == 1, "CollectAll Bank close test: batch active after item 1")
	bf:Hide()
	of.OnBankClosed()
	check(of.IsCollectAllActive() == false and of.GetState().stages.collect.pendingTake == nil
		and of.GetState().notice == "Stopped Collect All - Bank closed.",
		"CollectAll Bank: Closing Bank mid-batch cancels cleanly and clears pendingTake")
	advanceTimers(5.0)
	check(#useCalls == 1, "CollectAll Bank: Stale timers do not fire withdrawals after Bank closes")

	-- 5. ADDON_ACTION_BLOCKED cancel mid-batch
	clearCont(0); clearCont(1); clearCont(-1)
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Blocked Herb", itemID = 78121, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
	}, {
		title = "Collect All Action Blocked Test",
		ownershipProvider = function(id)
			if id == 78121 then return { bags = 0, bank = 2, mail = 0, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	setSlot(-1, 1, 78121, 2, false)
	bf:Show()
	of.OnBankShow()
	scheduledTimers = {}
	of.CollectAllAtCurrentSource()
	check(of.IsCollectAllActive() == true, "CollectAll ActionBlocked: batch active before block event")
	if of._collectActionFrame and of._collectActionFrame.GetScript then
		local onEv = of._collectActionFrame:GetScript("OnEvent")
		if onEv then onEv(of._collectActionFrame, "ADDON_ACTION_BLOCKED", "MerchantMaster", "UseContainerItem") end
	else
		of.OnActionBlocked("MerchantMaster", "UseContainerItem")
	end
	check(of.IsCollectAllActive() == false and of.GetState().stages.collect.pendingTake == nil
		and (of.GetState().notice or ""):find("hardware action blocked", 1, true) ~= nil,
		"CollectAll: ADDON_ACTION_BLOCKED cancels active Collect All cleanly")
	bf:Hide()
	of.OnBankClosed()

	-- 6. Mail Collect All: MailHelper.IsActive guard, multi-item batch + COD skip + missing skip, bags full stop, user StopCollectAll
	clearCont(0); clearCont(1); clearCont(-1)
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Mail Herb 1", itemID = 78201, qty = 0, ownedUsed = 3, ahUnitPrice = 100 },
		{ name = "Mail Herb Missing", itemID = 78202, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
		{ name = "Mail Herb 3", itemID = 78203, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
	}, {
		title = "Collect All Mail Test",
		ownershipProvider = function(id)
			if id == 78201 then return { bags = 0, bank = 0, mail = 3, alts = {} } end
			if id == 78202 then return { bags = 0, bank = 0, mail = 2, alts = {} } end
			if id == 78203 then return { bags = 0, bank = 0, mail = 2, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	mockInbox = {
		{ sender = "Scam", subject = "COD", cod = 9999, hasItem = 1, attach = { [1] = { name = "Mail Herb 1", itemID = 78201, count = 3 } } },
		{ sender = "AH",   subject = "Won", cod = 0,    hasItem = 1, attach = { [1] = { name = "Mail Herb 1", itemID = 78201, count = 3 } } },
		{ sender = "AH",   subject = "Won", cod = 0,    hasItem = 1, attach = { [1] = { name = "Mail Herb 3", itemID = 78203, count = 2 } } },
	}
	mf:Show()
	of.OnMailShow()

	-- MailHelper.IsActive() guard
	mailTakeCalls = {}
	ns.MailHelper = { IsActive = function() return true end }
	local mhOk, mhErr = of.CollectAllAtCurrentSource()
	check(mhOk == false and mhErr == "mail_helper_active" and of.IsCollectAllActive() == false and #mailTakeCalls == 0,
		"CollectAll Mail: Refuses cleanly when ns.MailHelper.IsActive() is true")

	-- Multi-item Mail batch
	ns.MailHelper = { IsActive = function() return false end }
	scheduledTimers = {}
	local mStartOk = of.CollectAllAtCurrentSource()
	check(mStartOk == true and of.IsCollectAllActive() == true and #mailTakeCalls == 1 and mailTakeCalls[1].mailIdx == 2,
		"CollectAll Mail: Starts batch and takes non-COD mail #2 (skipping COD mail #1)")
	of.OnBagUpdateDelayed()
	advanceTimers(0.2)
	check(#mailTakeCalls == 2 and mailTakeCalls[2].mailIdx == 3 and of.IsCollectAllActive() == true,
		"CollectAll Mail: Skips missing Mail Herb 2 and loots Mail Herb 3 from mail #3")
	of.OnBagUpdateDelayed()
	advanceTimers(0.2)
	local mByID = {}
	for _, it in ipairs(of.GetState().stages.collect.items) do mByID[it.itemID] = it end
	check(mByID[78201].status == "done" and mByID[78203].status == "done" and mByID[78202].status ~= "done"
		and of.IsCollectAllActive() == false
		and of.GetState().notice == "Collected 2 item(s) from Mailbox (some needed items still pending)."
		and of.GetState().noticeKind == "info",
		"CollectAll Mail: Finishes batch with honest pending Mailbox notice")

	-- Mail bags-full stop
	clearCont(0); clearCont(1)
	for b = 0, 1 do
		for s = 1, mockBagMax[b] do setSlot(b, s, 99992, 1, false) end
	end
	mockInbox = {
		{ sender = "AH", subject = "Won", cod = 0, hasItem = 1, attach = { [1] = { name = "Mail Herb Missing", itemID = 78202, count = 2 } } },
	}
	of.ScanOpenMailbox()
	mailTakeCalls = {}
	local mFullOk, mFullErr = of.CollectAllAtCurrentSource()
	check(mFullOk == false and mFullErr == "bags_full" and of.IsCollectAllActive() == false and #mailTakeCalls == 0
		and of.GetState().noticeKind == "warning",
		"CollectAll Mail: Stops cleanly with bags_full warning when bags are full")
	clearCont(0); clearCont(1)

	-- User StopCollectAll("user_stop") mid-batch
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Stop Mail 1", itemID = 78211, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
		{ name = "Stop Mail 2", itemID = 78212, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
	}, {
		title = "Collect All User Stop Test",
		ownershipProvider = function(id)
			if id == 78211 or id == 78212 then return { bags = 0, bank = 0, mail = 2, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	mockInbox = {
		{ sender = "AH", subject = "Won", cod = 0, hasItem = 1, attach = { [1] = { name = "Stop Mail 1", itemID = 78211, count = 2 } } },
		{ sender = "AH", subject = "Won", cod = 0, hasItem = 1, attach = { [1] = { name = "Stop Mail 2", itemID = 78212, count = 2 } } },
	}
	of.OnMailShow()
	mailTakeCalls = {}
	scheduledTimers = {}
	of.CollectAllAtCurrentSource()
	check(of.IsCollectAllActive() == true and #mailTakeCalls == 1, "CollectAll UserStop: active after first mail take")
	local stopped = of.StopCollectAll("user_stop")
	check(stopped == true and of.IsCollectAllActive() == false and of.GetState().notice == "Stopped Collect All.",
		"CollectAll UserStop: StopCollectAll cancels loop cleanly")
	of.OnBagUpdateDelayed()
	advanceTimers(1.0)
	check(#mailTakeCalls == 1, "CollectAll UserStop: Does not take second mail after user Stop")
	mf:Hide()
	of.OnMailClosed()

	-- 7. UI Button Wiring & Layout Assertions on Collect Stage
	-- Spotlight: Take 1x | All This Item | Mark Done | Skip, plus bottom-left Collect All
	if modal and modal.Render then
		clearCont(0); clearCont(1); clearCont(-1)
		of.ClearSavedState()
		of.LoadFromShoppingRows({
			{ name = "UI Bank Herb 1", itemID = 78301, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
			{ name = "UI Bank Herb 2", itemID = 78302, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
		}, {
			title = "Collect All UI Button Test",
			ownershipProvider = function(id)
				if id == 78301 or id == 78302 then return { bags = 0, bank = 2, mail = 0, alts = {} } end
				return { bags = 0, bank = 0, mail = 0, alts = {} }
			end,
		})
		of.SetActiveStage("collect")
		-- Open Bank with 0 matching items -> Spotlight shows Take 1x / All This Item disabled, Mark Done enabled, Skip shown & enabled, bottom Collect All disabled
		bf:Show()
		of.OnBankShow()
		modal.Render()
		check(modal.buyBtn:GetText() == "Take 1x" and not modal.buyBtn:IsEnabled()
			and modal.markBtn:GetText() == "All This Item" and not modal.markBtn:IsEnabled()
			and modal.nextBtn:GetText() == "Mark Done" and modal.nextBtn:IsEnabled()
			and modal.extraBtn:GetText() == "Skip" and modal.extraBtn:IsShown() and modal.extraBtn:IsEnabled()
			and modal.collectAllBtn ~= nil and not modal.collectAllBtn:IsEnabled(),
			"CollectAll UI: Open Bank with 0 matches shows Take 1x, All This Item, Mark Done, Skip, and disabled bottom Collect All")

		-- Check 4-button row fits cleanly inside 332px span (no overlap! 3 gaps * 5px = 15px)
		local totalW = (modal.buyBtn:GetWidth() or 0) + (modal.markBtn:GetWidth() or 0)
			+ (modal.nextBtn:GetWidth() or 0) + (modal.extraBtn:GetWidth() or 0) + 15
		check(totalW == 332, "CollectAll UI: 4-button Collect spotlight row spans exact 332px without overflow (got " .. tostring(totalW) .. ")")

		-- Populate matching Bank items -> Take 1x, All This Item, and bottom Collect All enable cleanly
		setSlot(-1, 1, 78301, 2, false)
		setSlot(-1, 2, 78302, 2, false)
		of.OnBankShow()
		modal.Render()
		check(modal.buyBtn:IsEnabled()
			and modal.markBtn:GetText() == "All This Item" and modal.markBtn:IsEnabled()
			and (modal.collectAllBtn:GetText() or ""):find("Collect All from Bank", 1, true) ~= nil
			and modal.collectAllBtn:IsEnabled(),
			"CollectAll UI: Take 1x, All This Item, and bottom Collect All enable when Bank has matching items")

		-- Bottom Collect All starts overview-wide batch ("all" mode) and flips to Stop Collect All
		scheduledTimers = {}
		modal.collectAllBtn:Click("LeftButton")
		modal.Render()
		check(of.IsCollectAllActive() == true and of.GetCollectAllMode() == "all"
			and modal.collectAllBtn:GetText() == "Stop Collect All"
			and modal.collectAllBtn:IsEnabled() and not modal.markBtn:IsEnabled(),
			"CollectAll UI: Clicking bottom Collect All starts overview batch in 'all' mode and flips to Stop Collect All")

		modal.collectAllBtn:Click("LeftButton")
		modal.Render()
		check(of.IsCollectAllActive() == false
			and (modal.collectAllBtn:GetText() or ""):find("Collect All from Bank", 1, true) ~= nil,
			"CollectAll UI: Clicking Stop Collect All cancels overview batch")

		-- Reload fresh Bank items so Spotlight item batch can be tested cleanly
		clearCont(0); clearCont(1); clearCont(-1)
		of.ClearSavedState()
		of.LoadFromShoppingRows({
			{ name = "UI Bank Herb 1", itemID = 78301, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
			{ name = "UI Bank Herb 2", itemID = 78302, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
		}, {
			title = "Collect All Item UI Test",
			ownershipProvider = function(id)
				if id == 78301 or id == 78302 then return { bags = 0, bank = 2, mail = 0, alts = {} } end
				return { bags = 0, bank = 0, mail = 0, alts = {} }
			end,
		})
		of.SetActiveStage("collect")
		setSlot(-1, 1, 78301, 2, false)
		setSlot(-1, 2, 78302, 2, false)
		of.OnBankShow()
		modal.Render()

		-- Spotlight "All This Item" starts per-item batch ("item" mode) and disables bottom Collect All
		scheduledTimers = {}
		modal.markBtn:Click("LeftButton")
		modal.Render()
		check(of.IsCollectAllActive() == true and of.GetCollectAllMode() == "item"
			and modal.markBtn:GetText() == "Stop" and modal.markBtn:IsEnabled()
			and not modal.collectAllBtn:IsEnabled(),
			"CollectAll UI: Clicking All This Item starts per-item batch and flips to Stop")

		modal.markBtn:Click("LeftButton")
		modal.Render()
		check(of.IsCollectAllActive() == false and modal.markBtn:GetText() == "All This Item",
			"CollectAll UI: Clicking Stop cancels per-item batch and restores All This Item label")

		-- Reload fresh Bank items and test Spotlight "Take 1x" (cbBuyBtn) takes only a single item stack
		clearCont(0); clearCont(1); clearCont(-1)
		of.ClearSavedState()
		of.LoadFromShoppingRows({
			{ name = "UI Bank Herb 1", itemID = 78301, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
			{ name = "UI Bank Herb 2", itemID = 78302, qty = 0, ownedUsed = 2, ahUnitPrice = 100 },
		}, {
			title = "Take 1x UI Test",
			ownershipProvider = function(id)
				if id == 78301 or id == 78302 then return { bags = 0, bank = 2, mail = 0, alts = {} } end
				return { bags = 0, bank = 0, mail = 0, alts = {} }
			end,
		})
		of.SetActiveStage("collect")
		setSlot(-1, 1, 78301, 2, false)
		setSlot(-1, 2, 78302, 2, false)
		of.OnBankShow()
		modal.Render()

		modal.buyBtn:Click("LeftButton")
		of.OnBagUpdateDelayed()
		modal.Render()
		local stAfterSingle = of.GetState().stages.collect
		local byID = {}
		for _, it in ipairs(stAfterSingle.items or {}) do byID[it.itemID] = it end
		check(byID[78301] and byID[78301].status == "done"
			and byID[78302] and byID[78302].status ~= "done",
			"CollectAll UI: Clicking Take 1x takes only the active item stack without touching other items")

		-- Clicking Mark Done (cbNextBtn) calls MarkCollected; clicking Skip (cbExtraBtn) calls SkipCollectItem
		local curItem = of.GetState().stages.collect.items[of.GetState().stages.collect.activeIndex]
		modal.nextBtn:Click("LeftButton")
		check(curItem.status == "done" and curItem.remaining == 0,
			"CollectAll UI: Clicking Mark Done (cbNextBtn) marks active collect item done")

		of.ClearSavedState()
		of.LoadFromShoppingRows({
			{ name = "Skip Herb", itemID = 78309, qty = 0, ownedUsed = 1, ahUnitPrice = 100 },
		}, {
			ownershipProvider = function() return { bags = 0, bank = 1, mail = 0, alts = {} } end,
		})
		of.SetActiveStage("collect")
		modal.Render()
		local activeBeforeSkip = of.GetState().stages.collect.items[of.GetState().stages.collect.activeIndex]
		modal.extraBtn:Click("LeftButton")
		check(activeBeforeSkip.status == "skipped",
			"CollectAll UI: Clicking Skip (cbExtraBtn) marks active collect item skipped")

		bf:Hide()
		of.OnBankClosed()
	end

	-- Cleanup
	of.ClearSavedState()
	_G.C_Container = origCCont
	_G.ClearCursor = origClearCursor
	_G.BankFrame = origBF
	_G.MailFrame = origMailF
	_G.GetTime = origGetTime
	if _G.C_Timer and origTimerAfter then _G.C_Timer.After = origTimerAfter end
	_G.GetInboxNumItems = origGetInboxNum
	_G.GetInboxHeaderInfo = origGetInboxHeader
	_G.GetInboxItem = origGetInboxItem
	_G.GetInboxItemLink = origGetInboxLink
	_G.TakeInboxItem = origTakeInbox
	ns.MailHelper = origMailHelper
	app.getBagCountByID = origGetBag
end
runCollectAllTests()

-- 11. Free Dragging & Per-Window Position Persistence (order_flow, main, resetWindowPositions)
;(function()
	ns.Window.ClearSavedPosition(nil)
	mainPanel.userMoved = false
	if shopModal then shopModal._mmUserPositioned = false end

	local origMailFrame = _G.MailFrame
	local origBankFrame = _G.BankFrame
	local origMerchantFrame = _G.MerchantFrame
	local origTradeSkillFrame = _G.TradeSkillFrame
	local mockMail = {
		_shown = true,
		IsShown = function(self) return self._shown end,
		IsVisible = function(self) return self._shown end,
		GetLeft = function() return 50 end,
		GetRight = function() return 450 end,
		GetTop = function() return 820 end,
		GetScale = function() return 1 end,
		GetEffectiveScale = function() return 1 end,
	}
	local mockBank = {
		_shown = false,
		IsShown = function(self) return self._shown end,
		IsVisible = function(self) return self._shown end,
		GetLeft = function() return 80 end,
		GetRight = function() return 520 end,
		GetEffectiveScale = function() return 1 end,
	}
	local mockMerchant = {
		_shown = false,
		IsShown = function(self) return self._shown end,
		IsVisible = function(self) return self._shown end,
		GetLeft = function() return 90 end,
		GetRight = function() return 480 end,
		GetEffectiveScale = function() return 1 end,
	}
	local mockTS = {
		_shown = false,
		IsShown = function(self) return self._shown end,
		IsVisible = function(self) return self._shown end,
		GetLeft = function() return 110 end,
		GetRight = function() return 660 end,
		GetEffectiveScale = function() return 1 end,
	}
	_G.MailFrame = mockMail
	_G.BankFrame = mockBank
	_G.MerchantFrame = mockMerchant
	_G.TradeSkillFrame = mockTS

	modal:Show()
	app.dockCartBuyerModal()
	local dp, drel, drp = modal:GetPoint(1)
	check(dp == "TOPLEFT" and drel == mockMail and drp == "TOPRIGHT",
		"Undragged AH Trade / Order Flow Strip smart-docks beside visible MailFrame")
	check(modal.dockModeBtn ~= nil and modal.dockModeBtn:GetText() == "Snap",
		"Order Flow dock toggle defaults to Snap mode")

	local origModalLeft, origModalTop = modal.GetLeft, modal.GetTop

	-- Click Snap -> Lock: blocks dragging and keeps panel attached to MailFrame
	modal.dockModeBtn:Click("LeftButton")
	check(ns.Window.GetMode("order_flow") == "lock" and modal.dockModeBtn:GetText() == "Lock",
		"Clicking Snap switches order_flow to Lock mode")
	modal.GetLeft = function() return 700 end
	modal.GetTop = function() return 900 end
	modal.header:GetScript("OnDragStart")(modal.header)
	modal.header:GetScript("OnDragStop")(modal.header)
	local lp, lrel, lrp = modal:GetPoint(1)
	check(lp == "TOPLEFT" and lrel == mockMail and lrp == "TOPRIGHT"
		and ns.Window.GetMode("order_flow") == "lock"
		and not ns.Window.HasSavedPosition("order_flow"),
		"Lock mode prevents dragging Order Flow Strip and keeps it attached to MailFrame")

	-- Click Lock -> Free -> Snap re-docks immediately beside open MailFrame
	modal.dockModeBtn:Click("LeftButton")
	check(ns.Window.GetMode("order_flow") == "free" and modal.dockModeBtn:GetText() == "Free",
		"Clicking Lock switches order_flow to Free mode")
	modal.dockModeBtn:Click("LeftButton")
	local reP, reRel, reRp = modal:GetPoint(1)
	check(ns.Window.GetMode("order_flow") == "snap" and modal.dockModeBtn:GetText() == "Snap"
		and reP == "TOPLEFT" and reRel == mockMail and reRp == "TOPRIGHT",
		"Clicking Free switches back to Snap and immediately re-docks beside MailFrame")

	-- Drag Order Flow Strip header in Snap mode -> switches to Free, saves order_flow position, resists NPC re-docking
	modal.GetLeft = function() return 620 end
	modal.GetTop = function() return 820 end
	modal.header:GetScript("OnDragStart")(modal.header)
	modal.header:GetScript("OnDragStop")(modal.header)
	check(ns.Window.GetMode("order_flow") == "free"
		and modal.dockModeBtn:GetText() == "Free"
		and ns.Window.HasSavedPosition("order_flow")
		and MerchantMasterDB.windowPositions.order_flow.x == 620
		and MerchantMasterDB.windowPositions.order_flow.y == 820,
		"Dragging Order Flow Strip in Snap switches to Free and saves order_flow position")

	mockBank._shown = true
	mockMerchant._shown = true
	mockTS._shown = true
	app.dockCartBuyerModal()
	fireEvent("MAIL_SHOW")
	fireEvent("BANKFRAME_OPENED")
	fireEvent("MERCHANT_SHOW")
	fireEvent("TRADE_SKILL_SHOW")
	fireEvent("BAG_UPDATE_DELAYED")
	local sp, srel, srp, sx, sy = modal:GetPoint(1)
	check(sp == "TOPLEFT" and srel == UIParent and srp == "BOTTOMLEFT"
		and math.abs((sx or 0) - 620) < 1 and math.abs((sy or 0) - 820) < 1,
		"Dragged Order Flow Strip stays in place across dockCartBuyerModal and NPC events")

	-- Drag Main MerchantMaster Window via toolbar -> saves 'main' shared across tabs
	mainPanel:Show()
	local origPanLeft, origPanTop = mainPanel.GetLeft, mainPanel.GetTop
	mainPanel.GetLeft = function() return 40 end
	mainPanel.GetTop = function() return 940 end
	mainPanel:ClearAllPoints()
	mainPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 40, 940)
	app.ui.toolbar:GetScript("OnDragStart")(app.ui.toolbar)
	app.ui.toolbar:GetScript("OnDragStop")(app.ui.toolbar)
	check(ns.Window.HasSavedPosition("main") and mainPanel.userMoved == true
		and MerchantMasterDB.windowPositions.main.x == 40
		and MerchantMasterDB.windowPositions.main.y == 940,
		"Dragging main toolbar saves per-window 'main' position")

	app.setTab("sniper_de")
	app.setTab("dashboard")
	_G.AuctionHouseFrame:Show()
	fireEvent("AUCTION_HOUSE_SHOW")
	local countKeys = 0
	for _ in pairs(MerchantMasterDB.windowPositions) do countKeys = countKeys + 1 end
	check(countKeys == 2 and MerchantMasterDB.windowPositions.sniper_de == nil
		and MerchantMasterDB.windowPositions.dashboard == nil,
		"Switching tabs keeps single shared 'main' position without per-tab keys")
	local mp, mrel, mrp, mx, my = mainPanel:GetPoint(1)
	check(mp == "TOPLEFT" and mrel == UIParent and mrp == "BOTTOMLEFT"
		and math.abs((mx or 0) - 40) < 1 and math.abs((my or 0) - 940) < 1,
		"Dragged Main window stays in place across tab switches and AUCTION_HOUSE_SHOW")

	-- Reload simulation: fresh userMoved=false + CENTER reset restores saved 'main' position
	mainPanel.userMoved = false
	mainPanel:ClearAllPoints()
	mainPanel:SetPoint("CENTER")
	mainPanel:Hide()
	app.togglePanel()
	local rpMain, rrMain, rrpMain, rxMain, ryMain = mainPanel:GetPoint(1)
	check(rpMain == "TOPLEFT" and rrMain == UIParent and rrpMain == "BOTTOMLEFT"
		and math.abs((rxMain or 0) - 40) < 1 and math.abs((ryMain or 0) - 940) < 1,
		"Reopening Main window after reload restores saved 'main' position")

	-- Reset Window Positions clears saved positions and returns windows to smart defaults
	_G.AuctionHouseFrame:Hide()
	mockBank._shown = false
	mockMerchant._shown = false
	mockTS._shown = false
	app.resetWindowPositions()
	check(not ns.Window.HasSavedPosition("order_flow")
		and not ns.Window.HasSavedPosition("main")
		and ns.Window.GetMode("order_flow") == "snap"
		and modal.dockModeBtn:GetText() == "Snap"
		and mainPanel.userMoved == false,
		"app.resetWindowPositions clears saved positions, resets mode to snap, and resets userMoved")
	local rp, rrel, rrp = modal:GetPoint(1)
	check(rp == "TOPLEFT" and rrel == mockMail and rrp == "TOPRIGHT",
		"app.resetWindowPositions immediately re-docks open Order Flow Strip to default anchor")

	modal.GetLeft, modal.GetTop = origModalLeft, origModalTop
	mainPanel.GetLeft, mainPanel.GetTop = origPanLeft, origPanTop
	modal:Hide()
	mainPanel:Hide()
	_G.AuctionHouseFrame:Hide()
	_G.MailFrame = origMailFrame
	_G.BankFrame = origBankFrame
	_G.MerchantFrame = origMerchantFrame
	_G.TradeSkillFrame = origTradeSkillFrame
	ns.Window.ClearSavedPosition(nil)
end)()

---------------------------------------------------------------------------------------------------
-- 17. ProfessionsFrame Dock Clearance & MerchantMaster Top Side Tab
---------------------------------------------------------------------------------------------------
;(function()
	local origProfFrame = _G.ProfessionsFrame
	local origTabGlobal = _G.MerchantMasterProfTabBtn
	local origUiTab = app.ui.profMMTab
	local origOverviewGlobal = _G.ProfessionsOverviewTab

	local mockPF = CreateFrame("Frame", "MockProfFrameDockTest", UIParent)
	mockPF:SetSize(760, 580)
	mockPF:ClearAllPoints()
	mockPF:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 40, 820)
	mockPF.GetLeft = function() return 40 end
	mockPF.GetRight = function() return 800 end
	mockPF.GetTop = function() return 820 end
	mockPF.GetBottom = function() return 240 end
	mockPF.GetEffectiveScale = function() return 1 end
	mockPF:Show()

	local mockOverviewTab = CreateFrame("Button", "MockProfOverviewTab", mockPF)
	mockOverviewTab:SetSize(42, 38)
	mockOverviewTab:SetPoint("TOPLEFT", mockPF, "TOPRIGHT", 0, -28)
	mockOverviewTab.GetLeft = function() return 800 end
	mockOverviewTab.GetRight = function() return 842 end
	mockOverviewTab.GetEffectiveScale = function() return 1 end
	mockOverviewTab:Show()
	mockPF.ProfessionsOverviewTab = mockOverviewTab
	_G.ProfessionsOverviewTab = mockOverviewTab
	_G.ProfessionsFrame = mockPF

	-- Force fresh attachment on our test ProfessionsFrame
	app.ui.profMMTab = nil
	_G.MerchantMasterProfTabBtn = nil
	local mmTab = app.ensureProfessionsMMTab()
	check(mmTab ~= nil and mmTab == app.ui.profMMTab, "app.ensureProfessionsMMTab creates and attaches app.ui.profMMTab")
	local tp, trel, trp = mmTab:GetPoint(1)
	check(tp == "BOTTOMLEFT" and trel == mockOverviewTab and trp == "TOPLEFT",
		"MerchantMaster Prof side tab anchors BOTTOMLEFT -> ProfessionsOverviewTab TOPLEFT")
	local iconTexPath = mmTab.iconTex and mmTab.iconTex.GetTexture and mmTab.iconTex:GetTexture() or ""
	check(tostring(iconTexPath):find("MerchantMasterLogo", 1, true) ~= nil,
		"MerchantMaster Prof side tab displays MerchantMasterLogo, got: " .. tostring(iconTexPath))

	-- Dock Crafting Task Strip in Snap mode -> must clear 42px tab protrusion by >= 52px
	ns.Window.SetMode("order_flow", "snap")
	ns.Window.ClearSavedPosition("order_flow")
	app.enterOrderFlowMode("craft")
	check(modal:IsShown(), "Order Flow opens in craft stage")
	local dp, drel, drp, dx = modal:GetPoint(1)
	check(dp == "TOPLEFT" and drel == mockPF and drp == "TOPRIGHT" and type(dx) == "number" and dx >= 52,
		"dockCartBuyerModal clears 42px ProfessionsOverviewTab by >= 52px, got gap=" .. tostring(dx))

	-- Left-click on MerchantMaster Prof side tab opens Crafting Task Strip ('craft' stage)
	app.exitAHBuyingMode(false)
	check(not modal:IsShown(), "Order Flow hidden before Left-click tab test")
	mmTab:Click("LeftButton")
	check(modal:IsShown() and of.GetActiveStage() == "craft",
		"Left-click on MerchantMaster Prof side tab enters Crafting Task Strip ('craft' stage)")

	-- Right-click opens MerchantMaster Recipes panel
	mainPanel:Hide()
	mmTab:Click("RightButton")
	check(mainPanel:IsShown() and app.activeTab == "recipes",
		"Right-click on MerchantMaster Prof side tab opens MerchantMaster Recipes")

	-- Cleanup restored globals
	if app.exitAHBuyingMode then app.exitAHBuyingMode(false) end
	mainPanel:Hide()
	mmTab:Hide()
	mockPF:Hide()
	_G.ProfessionsFrame = origProfFrame
	_G.ProfessionsOverviewTab = origOverviewGlobal
	_G.MerchantMasterProfTabBtn = origTabGlobal
	app.ui.profMMTab = origUiTab
	ns.Window.ClearSavedPosition(nil)
end)()

-- 12. Collect Refresh Button, Cross-Char Rebucket, Heart-of-the-Wild Bank->Mail Promotion,
--     Honest Completion Notices, AH inTransit Lifecycle, Locked Bank Slots, Quick-Close Grace,
--     Inventory.ScanMailbox Guards, alts() GUID Dedup & Partial-Craft Resize Conservation
;(function()
	local of = app.orderFlow
	local origCharKey = app.charKey
	local origChar = app.char
	local origMailboxItems = app.mailboxItems
	local origAtBank, origAtMail = app.atBank, app.atMail
	local origCharsDB = MerchantMasterDB.chars
	local origOrderFlowState = MerchantMasterDB.orderFlowState
	local origLedgerDB = _G.MerchantMasterLedgerDB
	local origCCont = _G.C_Container
	local origBF = _G.BankFrame
	local origMailF = _G.MailFrame
	local origAHF = _G.AuctionHouseFrame
	local origGetTime = _G.GetTime
	local origTimerAfter = _G.C_Timer and _G.C_Timer.After
	local origGetInboxNum = _G.GetInboxNumItems
	local origGetInboxHeader = _G.GetInboxHeaderInfo
	local origGetInboxItem = _G.GetInboxItem
	local origGetInboxLink = _G.GetInboxItemLink
	local origTakeInbox = _G.TakeInboxItem
	local origRetrieving = _G.RETRIEVING_DATA
	local origMailHelper = ns.MailHelper
	local origGetBag = app.getBagCountByID
	local origUnitName = _G.UnitName
	local origIncludeMail = MerchantMasterDB.includeMail
	local origIncludeBank = MerchantMasterDB.includeBank
	local origIncludeAlts = MerchantMasterDB.includeAlts

	local mockNow = 80000
	_G.GetTime = function() return mockNow end

	local scheduledTimers = {}
	if _G.C_Timer then
		_G.C_Timer.After = function(delay, fn)
			scheduledTimers[#scheduledTimers + 1] = { at = mockNow + (tonumber(delay) or 0), fn = fn }
		end
	end
	local function advanceTimers(sec)
		mockNow = mockNow + sec
		local keep, run = {}, {}
		for _, t in ipairs(scheduledTimers) do
			if t.at <= mockNow then run[#run + 1] = t.fn else keep[#keep + 1] = t end
		end
		scheduledTimers = keep
		for _, fn in ipairs(run) do fn() end
	end

	local itemNames = {
		[79101] = "Refresh Herb",
		[79102] = "Skipped Root",
		[79103] = "Switch Ore",
		[8140]  = "Heart of the Wild",
		[79104] = "Reg Snapper",
		[79105] = "Locked Crystal",
		[79106] = "Quick Mail Moss",
		[79107] = "SlotTwo Bar",
		[79108] = "COD Scam Pearl",
		[79109] = "Safe Ink",
		[79110] = "Alt Dedup Silk",
		[79111] = "Partial AH Bloom",
		[79112] = "Partial Vendor Vial",
		[79113] = "Partial Bank Dust",
	}
	local origNames, origIDs = {}, {}
	for id, nm in pairs(itemNames) do
		origNames[id] = ns.ITEM_NAMES_BY_ID and ns.ITEM_NAMES_BY_ID[id]
		origIDs[nm] = ns.ITEM_IDS_BY_NAME and ns.ITEM_IDS_BY_NAME[nm]
		if ns.ITEM_NAMES_BY_ID then ns.ITEM_NAMES_BY_ID[id] = nm end
		if ns.ITEM_IDS_BY_NAME then ns.ITEM_IDS_BY_NAME[nm] = id end
		app.itemIDs[nm] = id
	end

	local mockBagMax = { [0] = 6, [1] = 6, [-1] = 6 }
	local mockCont = { [0] = {}, [1] = {}, [-1] = {} }
	local function resetContainers()
		mockCont[0] = {}
		mockCont[1] = {}
		mockCont[-1] = {}
	end
	local function setSlot(bag, slot, itemID, qty, locked)
		if itemID and qty and qty > 0 then
			local nm = itemNames[itemID] or ("Item #" .. tostring(itemID))
			local lnk = "|cffffffff|Hitem:" .. tostring(itemID) .. "::::::::60:::::|h[" .. nm .. "]|h|r"
			mockCont[bag][slot] = { itemID = itemID, stackCount = qty, isLocked = locked or false, hyperlink = lnk }
		else
			mockCont[bag][slot] = nil
		end
	end
	local function addBagItem(itemID, qty)
		for b = 0, 1 do
			for s = 1, mockBagMax[b] do
				local c = mockCont[b][s]
				if c and c.itemID == itemID then
					c.stackCount = c.stackCount + qty
					return true
				end
			end
		end
		for b = 0, 1 do
			for s = 1, mockBagMax[b] do
				if not mockCont[b][s] then
					setSlot(b, s, itemID, qty, false)
					return true
				end
			end
		end
		return false
	end
	local function countBag(itemID)
		local tot = 0
		for b = 0, 1 do
			for s = 1, mockBagMax[b] do
				local c = mockCont[b][s]
				if c and c.itemID == itemID then tot = tot + (c.stackCount or 0) end
			end
		end
		return tot
	end

	_G.C_Container = {
		GetContainerNumSlots = function(b) return mockBagMax[b] or 0 end,
		GetContainerItemInfo = function(b, s)
			local c = mockCont[b] and mockCont[b][s]
			if not c then return nil end
			return { itemID = c.itemID, stackCount = c.stackCount, isLocked = c.isLocked, hyperlink = c.hyperlink }
		end,
		GetContainerItemID = function(b, s)
			local c = mockCont[b] and mockCont[b][s]
			return c and c.itemID or nil
		end,
		GetContainerNumFreeSlots = function() return 4, 0 end,
		UseContainerItem = function(b, s)
			local c = mockCont[b] and mockCont[b][s]
			if c and not c.isLocked then
				addBagItem(c.itemID, c.stackCount)
				mockCont[b][s] = nil
			end
		end,
	}
	app.getBagCountByID = function(id) return countBag(id) end

	local bf = _G.CreateFrame("Frame")
	bf:Hide()
	_G.BankFrame = bf
	local mf = _G.CreateFrame("Frame")
	mf:Hide()
	_G.MailFrame = mf
	if _G.AuctionHouseFrame then _G.AuctionHouseFrame:Hide() end
	ns.MailHelper = { IsActive = function() return false end }

	local mockInbox = {}
	local mockInboxTotal = nil
	_G.RETRIEVING_DATA = "Retrieving data"
	_G.GetInboxNumItems = function()
		return #mockInbox, (mockInboxTotal ~= nil and mockInboxTotal or #mockInbox)
	end
	_G.GetInboxHeaderInfo = function(idx)
		local m = mockInbox[idx]
		if not m then return nil end
		return nil, nil, m.sender, m.subject, 0, m.cod or 0, 30, m.hasItem
	end
	_G.GetInboxItem = function(mailIdx, attachIdx)
		local m = mockInbox[mailIdx]
		local a = m and m.attach and m.attach[attachIdx]
		if not a then return nil end
		return a.name, a.itemID, 134400, a.count, 1, true
	end
	_G.GetInboxItemLink = function(mailIdx, attachIdx)
		local m = mockInbox[mailIdx]
		local a = m and m.attach and m.attach[attachIdx]
		if not a then return nil end
		return "|cffffffff|Hitem:" .. tostring(a.itemID) .. "::::::::60:::::|h[" .. a.name .. "]|h|r"
	end
	_G.TakeInboxItem = function(mailIdx, attachIdx)
		local m = mockInbox[mailIdx]
		local a = m and m.attach and m.attach[attachIdx]
		if a then
			addBagItem(a.itemID, a.count)
			m.attach[attachIdx] = nil
		end
	end

	local function switchChar(charKey, charTbl, firstName)
		MerchantMasterDB.chars[charKey] = charTbl
		app.charKey = charKey
		app.char = charTbl
		_G.UnitName = function() return firstName or charTbl.firstName or charTbl.name end
		if ns.Analytics and ns.Analytics.Store and ns.Analytics.Store.ResetForTest then
			-- leave Store untouched if ResetForTest absent; SyncCurrentChar handles below
		end
		app.bagsDirty = true
		app.bagCountsDirty = true
		app.ownershipRev = (app.ownershipRev or 0) + 1
	end

	MerchantMasterDB.includeMail = true
	MerchantMasterDB.includeBank = true
	MerchantMasterDB.includeAlts = true
	MerchantMasterDB.chars = {
		["Benji Mongoose-Forever"] = {
			name = "Benji Mongoose", firstName = "Benji", guid = "Player-99-0001",
			realm = "Forever", faction = "Horde", economy = "EU|Horde|Forever|sc",
			bags = {}, bank = { ["Refresh Herb"] = 20, ["Skipped Root"] = 5 }, mail = {}, updatedAt = 100,
		},
		["The Endboss-Forever"] = {
			name = "The Endboss", firstName = "The", guid = "Player-99-0002",
			realm = "Forever", faction = "Horde", economy = "EU|Horde|Forever|sc",
			bags = {}, bank = { ["Switch Ore"] = 10, ["Heart of the Wild"] = 20 }, mail = {}, updatedAt = 100,
		},
	}
	if ns.Analytics and ns.Analytics.Store and ns.Analytics.Store.db then
		ns.Analytics.Store.db.inTransitMail = {}
		ns.Analytics.Store.db.inventory = {}
	end
	switchChar("Benji Mongoose-Forever", MerchantMasterDB.chars["Benji Mongoose-Forever"], "Benji")

	-- (1) Collect Refresh button UI + RefreshCollectForCurrentChar (closed-station snapshot preservation + mail/bags rebucket + 50-mail cap warning)
	resetContainers()
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Refresh Herb", itemID = 79101, qty = 0, ownedUsed = 20, ahUnitPrice = 100 },
		{ name = "Skipped Root", itemID = 79102, qty = 0, ownedUsed = 5, ahUnitPrice = 100 },
	}, {
		title = "Collect Refresh Test",
		ownershipProvider = function(id)
			if id == 79101 then return { bags = 0, bank = 20, mail = 0, alts = {} } end
			if id == 79102 then return { bags = 0, bank = 5, mail = 0, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	-- Mark Skipped Root as skipped before refresh
	for idx, it in ipairs(of.GetState().stages.collect.items) do
		if it.itemID == 79102 then
			of.SetActiveStage("collect")
			of.SkipCollectItem(idx)
			break
		end
	end
	app.enterOrderFlowMode("collect")
	modal.Render()
	check(modal.collectRefreshBtn ~= nil and modal.collectRefreshBtn:IsShown() and modal.collectRefreshBtn:IsEnabled()
		and modal.collectRefreshBtn:GetText() == "Refresh",
		"Regress 1: Stage 2 Collect shows enabled Refresh footer button")
	local caW = (modal.collectAllBtn and modal.collectAllBtn:GetWidth()) or 0
	local crW = (modal.collectRefreshBtn and modal.collectRefreshBtn:GetWidth()) or 0
	check(crW == 82 and (caW + 6 + crW) <= 372,
		"Regress 1: Collect All + Refresh widths fit footer cleanly without overlap")

	-- Closed Bank & Mail: cached bank/mail snapshots must be preserved when clicking Refresh!
	app.char.bank["Refresh Herb"] = 5
	app.char.mail["Refresh Herb"] = 15
	app.ownershipRev = (app.ownershipRev or 0) + 1
	modal.collectRefreshBtn:Click("LeftButton")
	check(app.char.bank["Refresh Herb"] == 5 and app.char.mail["Refresh Herb"] == 15,
		"Regress 1: Refresh preserves cached Bank and Mail snapshots while stations are closed")
	local mailQty1, bankQty1, skipStatus1 = 0, 0, nil
	for _, it in ipairs(of.GetState().stages.collect.items) do
		if it.itemID == 79101 and it.source == "mail" then mailQty1 = mailQty1 + (it.remaining or 0)
		elseif it.itemID == 79101 and it.source == "bank" then bankQty1 = bankQty1 + (it.remaining or 0)
		elseif it.itemID == 79102 then skipStatus1 = it.status end
	end
	check(mailQty1 == 15 and bankQty1 == 5 and skipStatus1 == "skipped",
		"Regress 1: Refresh re-buckets Bank->Mail (15 Mail, 5 Bank) and preserves skipped status")

	-- Now put 5x in Bags + open Mailbox with 15x and total=55 (50-mail cap overflow)
	setSlot(0, 1, 79101, 5, false)
	mockInbox = {
		{ sender = "The Endboss", subject = "Mats", cod = 0, hasItem = 1, attach = { [1] = { name = "Refresh Herb", itemID = 79101, count = 15 } } },
	}
	mockInboxTotal = 55
	app.atMailbox = true
	mf:Show()
	of.OnMailShow()
	of.RefreshCollectForCurrentChar()
	local bagsDone1, mailRem1 = 0, 0
	for _, it in ipairs(of.GetState().stages.collect.items) do
		if it.itemID == 79101 and it.source == "bags" and it.status == "done" then bagsDone1 = bagsDone1 + (it.collected or 0)
		elseif it.itemID == 79101 and it.source == "mail" then mailRem1 = mailRem1 + (it.remaining or 0) end
	end
	check(bagsDone1 == 5 and mailRem1 == 15 and of.GetState().noticeKind == "warning"
		and (of.GetState().notice or ""):find("50%-mail cap", 1, false) ~= nil,
		"Regress 1: Refresh marks 5x Bags [OK], keeps 15x Mail, and warns on 50-mail cap overflow")
	mf:Hide()
	app.atMailbox = false
	of.OnMailClosed()
	mockInboxTotal = nil

	-- (2) Cross-character RestoreState auto-rebucket via ownerCharKey
	resetContainers()
	switchChar("The Endboss-Forever", MerchantMasterDB.chars["The Endboss-Forever"], "The")
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Switch Ore", itemID = 79103, qty = 0, ownedUsed = 10, ahUnitPrice = 100 },
	}, { title = "Cross Char Switch Test" })
	local savedEndboss = of.SerializeState()
	check(savedEndboss and savedEndboss.ownerCharKey == "The Endboss-Forever",
		"Regress 2: SerializeState stamps ownerCharKey")
	MerchantMasterDB.chars["Benji Mongoose-Forever"].bank = {}
	MerchantMasterDB.chars["Benji Mongoose-Forever"].mail = { ["Switch Ore"] = 10 }
	switchChar("Benji Mongoose-Forever", MerchantMasterDB.chars["Benji Mongoose-Forever"], "Benji")
	local restoredOk = of.RestoreState(savedEndboss)
	local switchIt = of.GetState().stages.collect.items[1]
	check(restoredOk == true and of.GetState().ownerCharKey == "Benji Mongoose-Forever"
		and switchIt and switchIt.source == "mail" and switchIt.remaining == 10,
		"Regress 2: RestoreState auto-rebuckets Bank->Mail when switched to a different character")

	-- (3) Bank-only Mailbox scan & Heart of the Wild Bank->Mail promotion + Alt subject guard
	resetContainers()
	MerchantMasterDB.chars["Benji Mongoose-Forever"].bank = { ["Heart of the Wild"] = 20 }
	MerchantMasterDB.chars["Benji Mongoose-Forever"].mail = {}
	app.ownershipRev = (app.ownershipRev or 0) + 1
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Heart of the Wild", itemID = 8140, qty = 0, ownedUsed = 20, ahUnitPrice = 100 },
	}, { title = "Heart Bank->Mail Test" })
	of.SetActiveStage("collect")
	check(of.GetState().stages.collect.items[1].source == "bank", "Regress 3: Precondition starts in Bank")
	mockInbox = {
		{ sender = "The Endboss", subject = "Auction mats from bank", cod = 0, hasItem = 1, attach = { [1] = { name = "Heart of the Wild", itemID = 8140, count = 160 } } },
	}
	app.atMailbox = true
	mf:Show()
	of.OnMailShow()
	local heartIt = of.GetState().stages.collect.items[1]
	check(heartIt.source == "mail" and heartIt.remaining == 20 and heartIt.availableHere == 160 and heartIt.status == "ready",
		"Regress 3a: Bank-only Mailbox open promotes Heart of the Wild Bank->Mail (availableHere=160)")
	mf:Hide()
	app.atMailbox = false
	of.OnMailClosed()

	-- Alt source with known alt sender + 'Auction ...' subject promotes Alt->Mail with mailFromAlt=true
	resetContainers()
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Heart of the Wild", itemID = 8140, qty = 0, ownedUsed = 20, ahUnitPrice = 100 },
	}, {
		title = "Alt Subject Guard Test",
		ownershipProvider = function(id)
			if id == 8140 then
				return { bags = 0, bank = 0, mail = 0, alts = { { name = "The Endboss", location = "Bank", qty = 20 } } }
			end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	check(of.GetState().stages.collect.items[1].source == "alt", "Regress 3b: Precondition starts in Alt")
	mockInbox = {
		{ sender = "The Endboss", subject = "Auction mats from bank", cod = 0, hasItem = 1, attach = { [1] = { name = "Heart of the Wild", itemID = 8140, count = 20 } } },
	}
	app.atMailbox = true
	mf:Show()
	of.OnMailShow()
	local altPromoIt = of.GetState().stages.collect.items[1]
	check(altPromoIt.source == "mail" and altPromoIt.mailFromAlt == true and altPromoIt.remaining == 20,
		"Regress 3b: Known alt sender promotes Alt->Mail with mailFromAlt=true despite 'Auction' subject")
	mf:Hide()
	app.atMailbox = false
	of.OnMailClosed()

	-- (4) StopCollectAll('done') honest outcomes (positive vs warning overflow) + altCount pending guard
	resetContainers()
	MerchantMasterDB.chars["Benji Mongoose-Forever"].bank = {}
	MerchantMasterDB.chars["Benji Mongoose-Forever"].mail = { ["Heart of the Wild"] = 10 }
	app.ownershipRev = (app.ownershipRev or 0) + 1
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Heart of the Wild", itemID = 8140, qty = 0, ownedUsed = 10, ahUnitPrice = 100 },
	}, {
		title = "StopCollectAll Outcomes",
		ownershipProvider = function(id)
			if id == 8140 then return { bags = 0, bank = 0, mail = 10, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	mockInbox = {
		{ sender = "AH", subject = "Won Heart", cod = 0, hasItem = 1, attach = { [1] = { name = "Heart of the Wild", itemID = 8140, count = 6 } } },
	}
	for i = 2, 50 do
		mockInbox[i] = { sender = "Other", subject = "Other", cod = 0, hasItem = 0 }
	end
	mockInboxTotal = 54 -- 4 behind 50-mail cap
	app.atMailbox = true
	mf:Show()
	of.OnMailShow()
	scheduledTimers = {}
	of.CollectAllAtCurrentSource()
	of.OnBagUpdateDelayed()
	advanceTimers(0.2)
	check(of.GetState().noticeKind == "warning" and (of.GetState().notice or ""):find("4 more mail", 1, true) ~= nil,
		"Regress 4a: Partial Mail Collect All + 50-mail cap emits honest warning banner (not green)")
	mockInboxTotal = nil
	mf:Hide()
	app.atMailbox = false
	of.OnMailClosed()

	-- Partial pending without 50-mail cap overflow -> info pending notice; full Bank completion -> positive notice
	resetContainers()
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Heart of the Wild", itemID = 8140, qty = 0, ownedUsed = 10, ahUnitPrice = 100 },
	}, {
		title = "StopCollectAll Info Outcome",
		ownershipProvider = function(id)
			if id == 8140 then return { bags = 0, bank = 0, mail = 10, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	mockInbox = {
		{ sender = "AH", subject = "Won Heart", cod = 0, hasItem = 1, attach = { [1] = { name = "Heart of the Wild", itemID = 8140, count = 6 } } },
	}
	app.atMailbox = true
	mf:Show()
	of.OnMailShow()
	scheduledTimers = {}
	of.CollectAllAtCurrentSource()
	of.OnBagUpdateDelayed()
	advanceTimers(0.2)
	check(of.GetState().noticeKind == "info" and (of.GetState().notice or ""):find("still pending", 1, true) ~= nil,
		"Regress 4b: Partial Mail Collect All without overflow emits honest info pending banner")
	mf:Hide()
	app.atMailbox = false
	of.OnMailClosed()

	resetContainers()
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Heart of the Wild", itemID = 8140, qty = 0, ownedUsed = 4, ahUnitPrice = 100 },
	}, {
		title = "StopCollectAll Positive Outcome",
		ownershipProvider = function(id)
			if id == 8140 then return { bags = 0, bank = 4, mail = 0, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	setSlot(-1, 1, 8140, 4, false)
	app.atBank = true
	bf:Show()
	of.OnBankShow()
	scheduledTimers = {}
	of.CollectAllAtCurrentSource()
	of.OnBagUpdateDelayed()
	advanceTimers(0.2)
	check(of.GetState().noticeKind == "positive" and of.GetState().notice == "Collected all needed items from Bank!",
		"Regress 4c: Complete Bank Collect All emits positive completion banner")
	bf:Hide()
	app.atBank = false
	of.OnBankClosed()

	-- Pending Alt item blocks false 'All owned items collected!' notice
	resetContainers()
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Alt Dedup Silk", itemID = 79110, qty = 0, ownedUsed = 5, ahUnitPrice = 100 },
	}, {
		title = "Pending Alt Notice Guard",
		ownershipProvider = function(id)
			if id == 79110 then
				return { bags = 0, bank = 0, mail = 2, alts = { { name = "The Endboss", location = "Bank", qty = 3 } } }
			end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	mockInbox = {
		{ sender = "The Endboss", subject = "Silk", cod = 0, hasItem = 1, attach = { [1] = { name = "Alt Dedup Silk", itemID = 79110, count = 2 } } },
	}
	app.atMailbox = true
	mf:Show()
	of.OnMailShow()
	local okTake2 = of.CollectFromMail(1)
	check(okTake2 == true, "Regress 4d: Mail portion collected")
	of.OnBagUpdateDelayed()
	local altStats = of.GetStageStats("collect")
	check(altStats.complete == false and altStats.altCount == 1
		and of.GetState().notice ~= "All owned items collected!",
		"Regress 4d: Pending Alt item prevents false 'All owned items collected!' notice")
	mf:Hide()
	app.atMailbox = false
	of.OnMailClosed()

	-- (5) MarkBought -> Collect Mail (_createdByAH, purchasedFromAH), GetAllDestinations exclusion, AH inTransitMail settle
	resetContainers()
	if ns.Analytics and ns.Analytics.Store and ns.Analytics.Store.db then
		ns.Analytics.Store.db.inTransitMail = {}
	end
	MerchantMasterDB.chars["Benji Mongoose-Forever"].mail = {}
	app.ownershipRev = (app.ownershipRev or 0) + 1
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "r5", name = "Dest Potion", itemID = 79901, qty = 1, sourceKind = "craft_order", sourceLabel = "Craft Order" },
		{ indent = 1, mainGroupKey = "r5", name = "Reg Snapper", itemID = 79104, qty = 4, ahUnitPrice = 50, categoryName = "Dest Potion", sourceKind = "craft_order", sourceLabel = "Craft Order" },
	}, {
		title = "AH MarkBought Lifecycle",
		ownershipProvider = function() return { bags = 0, bank = 0, mail = 0, alts = {} } end,
	})
	cb.MarkBought(1)
	local ahMailRow = nil
	for _, it in ipairs(of.GetState().stages.collect.items) do
		if it.itemID == 79104 and it.source == "mail" then ahMailRow = it end
	end
	local destList = of.GetAllDestinations()
	local ahTransitFound = 0
	if ns.Analytics and ns.Analytics.Store and ns.Analytics.Store.db then
		for _, e in ipairs(ns.Analytics.Store.db.inTransitMail or {}) do
			if e and e.fromChar == "Auction House" and e.items and e.items[79104] then
				ahTransitFound = ahTransitFound + (e.items[79104] or 0)
			end
		end
	end
	local bdBeforeMail = app.getItemOwnershipBreakdown(79104, "Reg Snapper")
	check(ahMailRow ~= nil and ahMailRow.purchasedFromAH == true and ahMailRow._createdByAH == true and ahMailRow.remaining == 4,
		"Regress 5: MarkBought queues Collect Mail item with purchasedFromAH & _createdByAH flags")
	check(#destList == 1 and destList[1].totalItems == 2 and destList[1].boughtItems == 1,
		"Regress 5: _createdByAH dynamic mail entry is excluded from GetAllDestinations counts (2 not 3)")
	check(ahTransitFound == 4 and (bdBeforeMail.inTransit or 0) == 0,
		"Regress 5: AH purchase records inTransitMail without double-counting active OrderFlow purchase in owned breakdown")
	of.MarkCollected(1)
	local ahTransitAfter = 0
	if ns.Analytics and ns.Analytics.Store and ns.Analytics.Store.db then
		for _, e in ipairs(ns.Analytics.Store.db.inTransitMail or {}) do
			if e and e.fromChar == "Auction House" and e.items and e.items[79104] then
				ahTransitAfter = ahTransitAfter + (e.items[79104] or 0)
			end
		end
	end
	check(ahTransitAfter == 0, "Regress 5: Collecting AH Mail settles Auction House inTransitMail to 0")

	-- (6) Locked Bank slot exclusion
	resetContainers()
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Locked Crystal", itemID = 79105, qty = 0, ownedUsed = 10, ahUnitPrice = 100 },
	}, {
		title = "Locked Bank Slot Test",
		ownershipProvider = function(id)
			if id == 79105 then return { bags = 0, bank = 10, mail = 0, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	setSlot(-1, 1, 79105, 10, true)
	app.atBank = true
	bf:Show()
	of.OnBankShow()
	check(of.GetState().stages.collect.items[1].availableHere == 0 and of.GetCollectAllSummary().itemCount == 0,
		"Regress 6: Locked Bank slot is excluded from availableHere and CollectAllSummary")
	setSlot(-1, 1, 79105, 10, false)
	of.ScanOpenBank()
	check(of.GetState().stages.collect.items[1].availableHere == 10 and of.GetCollectAllSummary().itemCount == 1,
		"Regress 6: Unlocked Bank slot becomes availableHere=10 on ScanOpenBank")
	bf:Hide()
	app.atBank = false
	of.OnBankClosed()

	-- (7) Post-MAIL_CLOSED _recentCloseGrace + cached char.mail / mailboxItems decrement
	resetContainers()
	app.char.mail = { ["Quick Mail Moss"] = 5 }
	app.mailboxItems = { [79106] = 5 }
	app.ownershipRev = (app.ownershipRev or 0) + 1
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Quick Mail Moss", itemID = 79106, qty = 0, ownedUsed = 5, ahUnitPrice = 100 },
	}, {
		title = "Quick Close Grace Test",
		ownershipProvider = function(id)
			if id == 79106 then return { bags = 0, bank = 0, mail = 5, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	mockInbox = {
		{ sender = "AH", subject = "Won Moss", cod = 0, hasItem = 1, attach = { [1] = { name = "Quick Mail Moss", itemID = 79106, count = 5 } } },
	}
	app.atMailbox = true
	mf:Show()
	of.OnMailShow()
	-- Simulate TakeInboxItem where bag delta arrives right AFTER MAIL_CLOSED
	local origTakeTmp = _G.TakeInboxItem
	_G.TakeInboxItem = function() end
	of.CollectFromMail(1)
	_G.TakeInboxItem = origTakeTmp
	mf:Hide()
	app.atMailbox = false
	of.OnMailClosed()
	local cSt7 = of.GetState().stages.collect
	check(cSt7.pendingTake == nil and cSt7._recentCloseGrace ~= nil and cSt7._recentCloseGrace.hadPendingTake == true,
		"Regress 7: OnMailClosed clears pendingTake=nil while arming _recentCloseGrace")
	mockNow = mockNow + 0.5
	setSlot(0, 1, 79106, 5, false)
	of.OnBagUpdateDelayed()
	check(cSt7.items[1].status == "done" and (app.char.mail["Quick Mail Moss"] or 0) == 0
		and (app.mailboxItems[79106] or 0) == 0,
		"Regress 7: Late BAG_UPDATE_DELAYED within 3s grace completes Mail item and decrements cached char.mail & mailboxItems")

	-- (8) Inventory.ScanMailbox slot-1-empty + COD skip + RETRIEVING_DATA abort + alts() GUID dedup
	if ns.Analytics and ns.Analytics.Inventory and ns.Analytics.Inventory.ScanMailbox and ns.Analytics.Store then
		local invMod = ns.Analytics.Inventory
		local storeMod = ns.Analytics.Store
		local charK, econK = storeMod.CurrentCharAndEcon and storeMod.CurrentCharAndEcon()
		if charK then
			mockInbox = {
				{ sender = "Friend", subject = "Looted Slot 1", cod = 0, hasItem = 1, attach = { [2] = { name = "SlotTwo Bar", itemID = 79107, count = 8 } } },
				{ sender = "Scam", subject = "COD Trap", cod = 50000, hasItem = 1, attach = { [1] = { name = "COD Scam Pearl", itemID = 79108, count = 10 } } },
				{ sender = "Banker", subject = "Ink", cod = 0, hasItem = 1, attach = { [1] = { name = "Safe Ink", itemID = 79109, count = 4 } } },
			}
			local snapMail = invMod.ScanMailbox()
			check(snapMail ~= nil and snapMail.mail and snapMail.mail[79107] == 8 and (snapMail.mail[79108] or 0) == 0 and snapMail.mail[79109] == 4,
				"Regress 8a: Inventory.ScanMailbox counts attachment slot 2 when slot 1 is nil and skips COD mail")
			mockInbox[3].subject = _G.RETRIEVING_DATA
			local nilSnap = invMod.ScanMailbox()
			check(nilSnap == nil and snapMail.mail[79107] == 8,
				"Regress 8b: Inventory.ScanMailbox aborts with nil on RETRIEVING_DATA without corrupting prior snapshot")
		end
	end
	MerchantMasterDB.chars = {
		["ThirdChar-Forever"] = {
			name = "Third Char", firstName = "Third", guid = "Player-99-0003",
			realm = "Forever", faction = "Horde", economy = "EU|Horde|Forever|sc",
			bags = {}, bank = {}, mail = {}, updatedAt = 100,
		},
		["Endboss-Forever"] = {
			name = "Endboss", guid = "Player-99-DEDUP",
			realm = "Forever", faction = "Horde", economy = "EU|Horde|Forever|sc",
			bags = {}, bank = { ["Alt Dedup Silk"] = 20 }, mail = {}, updatedAt = 100,
		},
		["Endboss Forever-Forever"] = {
			name = "Endboss Forever", firstName = "Endboss", guid = "Player-99-DEDUP",
			realm = "Forever", faction = "Horde", economy = "EU|Horde|Forever|sc",
			bags = {}, bank = { ["Alt Dedup Silk"] = 20 }, mail = {}, updatedAt = 200,
		},
	}
	switchChar("ThirdChar-Forever", MerchantMasterDB.chars["ThirdChar-Forever"], "Third")
	local bdDedup = app.getItemOwnershipBreakdown(79110, "Alt Dedup Silk")
	local altSum = 0
	for _, ae in ipairs(bdDedup.alts or {}) do altSum = altSum + (ae.qty or 0) end
	check(altSum == 20, "Regress 8c: alts() GUID dedup counts shared-GUID Endboss once (20, not 40)")

	-- (9) Partial-craft resize conservation (never double-credits consumed crafts or falsifies unbought/uncollected rows)
	resetContainers()
	MerchantMasterDB.chars["ThirdChar-Forever"].bank = { ["Partial Bank Dust"] = 5 }
	app.ownershipRev = (app.ownershipRev or 0) + 1
	of.ClearSavedState()
	local r9RowsA = {
		{ isMainRow = true, mainGroupKey = "p9", name = "Resized Elix", itemID = 79909, spellID = 99909, prof = "alchemy", qty = 5, sourceKind = "craft_order", sourceLabel = "Craft Order",
			reagents = { { itemID = 79111, qty = 2 }, { itemID = 79112, qty = 1 }, { itemID = 79113, qty = 1 } } },
		{ indent = 1, mainGroupKey = "p9", name = "Partial AH Bloom", itemID = 79111, qty = 10, ahUnitPrice = 100, categoryName = "Resized Elix" },
		{ indent = 1, mainGroupKey = "p9", name = "Partial Vendor Vial", itemID = 79112, qty = 5, isVendor = true, vendorUnitPrice = 10, categoryName = "Resized Elix" },
		{ indent = 1, mainGroupKey = "p9", name = "Partial Bank Dust", itemID = 79113, qty = 0, ownedUsed = 5, categoryName = "Resized Elix" },
	}
	local prov9 = function(id)
		if id == 79113 then return { bags = 0, bank = 5, mail = 0, alts = {} } end
		return { bags = countBag(id), bank = 0, mail = 0, alts = {} }
	end
	of.LoadFromShoppingRows(r9RowsA, { title = "Resize A", ownershipProvider = prov9 })
	-- Bought all 10 AH Bloom, bought all 5 Vendor Vial, withdrew 5 Bank Dust, crafted 2 of 5 (consumed 4 AH, 2 Vial, 2 Dust; unconsumed in bags: 6 AH, 3 Vial, 3 Dust)
	cb.MarkBought(1)
	local ven9 = of.GetState().stages.vendor.items[1]
	ven9.bought, ven9.remaining, ven9.status = 5, 0, "done"
	setSlot(0, 1, 79111, 6, false)
	setSlot(0, 2, 79112, 3, false)
	setSlot(0, 3, 79113, 3, false)
	local crT9 = of.GetState().stages.craft.tasks[1]
	crT9.completedCrafts, crT9.remainingCrafts = 2, 3
	-- Resize order from 5 -> 7 (+2 crafts total => net remaining crafts = 5, needing 4 more AH Bloom, 2 more Vendor Vial, 2 more Bank Dust; Bank still has 5? no, suppose 3 uncollected in bags, 2 new need in AH or remaining bank)
	local r9RowsB = {
		{ isMainRow = true, mainGroupKey = "p9", name = "Resized Elix", itemID = 79909, spellID = 99909, prof = "alchemy", qty = 5, _origOrderQty = 7, _completedCraftsDeducted = 2, sourceKind = "craft_order", sourceLabel = "Craft Order",
			reagents = { { itemID = 79111, qty = 2 }, { itemID = 79112, qty = 1 }, { itemID = 79113, qty = 1 } } },
		{ indent = 1, mainGroupKey = "p9", name = "Partial AH Bloom", itemID = 79111, qty = 4, ownedUsed = 6, ahUnitPrice = 100, categoryName = "Resized Elix" },
		{ indent = 1, mainGroupKey = "p9", name = "Partial Vendor Vial", itemID = 79112, qty = 2, ownedUsed = 3, isVendor = true, vendorUnitPrice = 10, categoryName = "Resized Elix" },
		{ indent = 1, mainGroupKey = "p9", name = "Partial Bank Dust", itemID = 79113, qty = 0, ownedUsed = 5, categoryName = "Resized Elix" },
	}
	r9RowsB._deductedReagentsTotal = { [79111] = 4, [79112] = 2, [79113] = 2 }
	-- Put 3 AH in bags (say bags consumed), suppose bags have 0 unbought; live check: AH bought was 10, minus 4 consumed & any bags growth -> wait: row qty=4 already reflects live bags, old AH bought (10) - accounted(4 + mailCollected(0)) = 6? Wait: if live row says qty=4 more needed when AH row was preserved... let's verify exact conservation!
	MerchantMasterDB.chars["ThirdChar-Forever"].bank = { ["Partial Bank Dust"] = 2 }
	of.LoadFromShoppingRows(r9RowsB, {
		title = "Resize B",
		preserveProgress = true,
		deductOwned = true,
		ownershipProvider = function(id)
			if id == 79113 then return { bags = 3, bank = 2, mail = 0, alts = {} } end
			return { bags = countBag(id), bank = 0, mail = 0, alts = {} }
		end,
	})
	local ah9After = of.GetState().stages.ah.items[1]
	local ven9After = of.GetState().stages.vendor.items[1]
	local bankDustRem = 0
	for _, it in ipairs(of.GetState().stages.collect.items) do
		if it.itemID == 79113 and it.source == "bank" then bankDustRem = bankDustRem + (it.remaining or 0) end
	end
	check(ah9After ~= nil and ah9After.remaining == 4 and ah9After.status ~= "done",
		"Regress 9: Resized AH row keeps unbought qty 4 pending cleanly")
	check(ven9After ~= nil and ven9After.remaining == 2 and ven9After.status ~= "done",
		"Regress 9: Resized Vendor row keeps unbought qty 2 pending instead of falsely copying prior bought=5")
	check(bankDustRem == 2,
		"Regress 9: Resized Bank Collect row keeps uncollected Bank Dust remaining=2 instead of falsely copying prior done")

	-- (10) Finding #1: ReceiveTransitMail alias cleanup clears single-word Forever alias inTransitMail
	if ns.Analytics and ns.Analytics.Inventory and ns.Analytics.Store and ns.Analytics.Store.db then
		local invMod = ns.Analytics.Inventory
		local storeDb = ns.Analytics.Store.db
		storeDb.inTransitMail = {}
		storeDb.inventory = {
			["Normal-Horde-Forever-Benji Mongoose"] = { econ = "Normal-Horde", bags = {}, bank = {}, mail = {} },
		}
		local nowEpoch = _G.time()
		invMod.RecordInTransitMail("Normal-Horde-Forever-Benji", { { itemID = 4304, qty = 25 } }, 0, nowEpoch, "Normal-Horde-Forever-The Endboss", "Normal-Horde")
		local bdAliasBefore = invMod.GetItemBreakdown(4304)
		invMod.ReceiveTransitMail("Normal-Horde-Forever-Benji Mongoose", {}, { fullScan = true, snapshotAt = nowEpoch + 10 })
		local bdAliasAfter = invMod.GetItemBreakdown(4304)
		check((bdAliasBefore.inTransit or 0) == 25 and (bdAliasAfter.inTransit or 0) == 0,
			"Regress 10: ReceiveTransitMail clears single-word alias inTransitMail cleanly (no shadow upvalue bug)")
	end

	-- (11) Finding #2: Sub-craft completedCrafts + leaf subDeductedTotal conservation on resize
	resetContainers()
	of.ClearSavedState()
	local r11RowsA = {
		{ isMainRow = true, mainGroupKey = "m11", name = "Main Tonic", itemID = 79911, spellID = 99911, prof = "alchemy", qty = 10, sourceKind = "craft_order", sourceLabel = "Craft Order",
			reagents = { { itemID = 79109, qty = 1 } } },
		{ indent = 1, mainGroupKey = "m11", isSubBranchRoot = true, subGroupKey = "s11", name = "Sub Vial", itemID = 79109, spellID = 99910, prof = "alchemy", craftProf = "alchemy", qty = 10, makeMyself = true, categoryName = "Main Tonic",
			reagents = { { itemID = 79112, qty = 1 } } },
		{ indent = 2, isSubRow = true, mainGroupKey = "m11", subGroupKey = "s11", parentSubName = "Sub Vial", name = "Partial Vendor Vial", itemID = 79112, qty = 10, isVendor = true, vendorUnitPrice = 10, categoryName = "Main Tonic" },
	}
	of.LoadFromShoppingRows(r11RowsA, { title = "Subcraft Resize A", ownershipProvider = function() return { bags = 0, bank = 0, mail = 0, alts = {} } end })
	local v11 = of.GetState().stages.vendor.items[1]
	v11.bought, v11.remaining, v11.status = 10, 0, "done"
	for _, t in ipairs(of.GetState().stages.craft.tasks) do
		t.completedCrafts = 5
		t.remainingCrafts = 5
	end
	setSlot(0, 1, 79112, 5, false) -- 5 left in bags, 5 already crafted into 5 Sub Vials and consumed
	local r11RowsB = {
		{ isMainRow = true, mainGroupKey = "m11", name = "Main Tonic", itemID = 79911, spellID = 99911, prof = "alchemy", qty = 9, _origOrderQty = 14, _completedCraftsDeducted = 5, sourceKind = "craft_order", sourceLabel = "Craft Order",
			reagents = { { itemID = 79109, qty = 1 } } },
		{ indent = 1, mainGroupKey = "m11", isSubBranchRoot = true, subGroupKey = "s11", name = "Sub Vial", itemID = 79109, spellID = 99910, prof = "alchemy", craftProf = "alchemy", qty = 9, makeMyself = true, categoryName = "Main Tonic",
			reagents = { { itemID = 79112, qty = 1 } } },
		{ indent = 2, isSubRow = true, mainGroupKey = "m11", subGroupKey = "s11", parentSubName = "Sub Vial", name = "Partial Vendor Vial", itemID = 79112, qty = 4, ownedUsed = 5, isVendor = true, vendorUnitPrice = 10, categoryName = "Main Tonic" },
	}
	r11RowsB._deductedReagentsTotal = { [79109] = 5, [79112] = 5 }
	of.LoadFromShoppingRows(r11RowsB, {
		title = "Subcraft Resize B",
		preserveProgress = true,
		deductOwned = true,
		ownershipProvider = function(id) return { bags = countBag(id), bank = 0, mail = 0, alts = {} } end,
	})
	local subTask11 = nil
	for _, t in ipairs(of.GetState().stages.craft.tasks) do
		if t.isSubCraft then subTask11 = t end
	end
	local v11After = of.GetState().stages.vendor.items[1]
	check(subTask11 and subTask11.neededCrafts == 14 and subTask11.completedCrafts == 5 and subTask11.remainingCrafts == 9,
		"Regress 11: Resized sub-craft restores consumed crafts cleanly (remaining=9, not double-subtracted to 4)")
	check(v11After and v11After.remaining == 4 and v11After.status ~= "done",
		"Regress 11: Resized leaf Vendor mat behind sub-craft keeps 4 remaining pending cleanly")

	-- (12) Finding #3: Pre-existing owned Mail (10) + AH buy (50) preserves S3.5 merge, GetAllDestinations units, ah.bought, and Refresh _createdByAH
	resetContainers()
	MerchantMasterDB.chars["ThirdChar-Forever"].mail = { ["Reg Snapper"] = 10 }
	app.ownershipRev = (app.ownershipRev or 0) + 1
	of.ClearSavedState()
	local r12Rows = {
		{ isMainRow = true, mainGroupKey = "m12", name = "Snapper Dish", itemID = 79912, qty = 1, sourceKind = "craft_order", sourceLabel = "Craft Order" },
		{ indent = 1, mainGroupKey = "m12", name = "Reg Snapper", itemID = 79104, qty = 50, ownedUsed = 10, ahUnitPrice = 50, categoryName = "Snapper Dish", sourceKind = "craft_order", sourceLabel = "Craft Order" },
	}
	of.LoadFromShoppingRows(r12Rows, {
		title = "Merged Owned + AH Mail",
		ownershipProvider = function(id)
			if id == 79104 then return { bags = 0, bank = 0, mail = 10, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	cb.MarkBought(1)
	local mRow12 = nil
	for _, it in ipairs(of.GetState().stages.collect.items) do
		if it.itemID == 79104 and it.source == "mail" then mRow12 = it end
	end
	local dest12 = of.GetAllDestinations()
	check(mRow12 and mRow12.needed == 60 and mRow12._ahAddedQty == 50 and mRow12._createdByAH == nil,
		"Regress 12a: Merged owned (10) + AH (50) mail row preserves needed=60 and tracks _ahAddedQty=50")
	check(#dest12 == 1 and dest12[1].totalItems == 3 and dest12[1].totalUnits == 61,
		"Regress 12b: GetAllDestinations caps merged Mail provenance at owned portion (50+10+1=61, not 111)")
	of.LoadFromShoppingRows(r12Rows, {
		title = "Merged Owned + AH Mail Sync",
		preserveProgress = true,
		deductOwned = true,
		ownershipProvider = function(id)
			if id == 79104 then return { bags = 0, bank = 0, mail = 10, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	check(of.GetState().stages.ah.items[1].bought == 50 and of.GetState().stages.ah.items[1].remaining == 0,
		"Regress 12c: preserveProgress reload keeps ah.bought=50 intact alongside 10 pre-owned mail")

	-- Pure _createdByAH survives RefreshCollectForCurrentChar
	resetContainers()
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ isMainRow = true, mainGroupKey = "m12b", name = "Pure AH Potion", itemID = 79913, qty = 1, sourceKind = "craft_order", sourceLabel = "Craft Order" },
		{ indent = 1, mainGroupKey = "m12b", name = "Reg Snapper", itemID = 79104, qty = 4, ahUnitPrice = 50, categoryName = "Pure AH Potion", sourceKind = "craft_order", sourceLabel = "Craft Order" },
	}, { title = "Pure AH Refresh", ownershipProvider = function() return { bags = 0, bank = 0, mail = 0, alts = {} } end })
	cb.MarkBought(1)
	of.RefreshCollectForCurrentChar({ silent = true, ownershipProvider = function() return { bags = 0, bank = 0, mail = 0, alts = {} } end })
	local dest12p = of.GetAllDestinations()
	local r12Pure = of.GetState().stages.collect.items[1]
	check(r12Pure and r12Pure._createdByAH == true and #dest12p == 1 and dest12p[1].totalItems == 2,
		"Regress 12d: RefreshCollectForCurrentChar preserves _createdByAH=true and GetAllDestinations excludes dynamic AH mail")

	-- (13) Finding #4: RETRIEVING_DATA during RefreshCollectForCurrentChar never wipes cached app.char.mail
	resetContainers()
	app.char.mail = { ["Refresh Herb"] = 100 }
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Refresh Herb", itemID = 79101, qty = 0, ownedUsed = 100, ahUnitPrice = 100 },
	}, {
		title = "RETRIEVING_DATA Guard",
		ownershipProvider = function(id)
			if id == 79101 then return { bags = 0, bank = 0, mail = 100, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	mockInbox = {
		{ sender = "AH", subject = _G.RETRIEVING_DATA, cod = 0, hasItem = 1, attach = { [1] = { name = _G.RETRIEVING_DATA, itemID = nil, count = 1 } } },
	}
	app.atMailbox = true
	mf:Show()
	of.RefreshCollectForCurrentChar()
	check(app.char.mail["Refresh Herb"] == 100,
		"Regress 13: RETRIEVING_DATA inbox during Refresh preserves cached app.char.mail (no wipe to 0)")
	mf:Hide()
	app.atMailbox = false
	of.OnMailClosed()

	-- (14) Finding #5: preserveProgress=true with opts.deductOwned=false honors opts even if DB default is true
	resetContainers()
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Reg Snapper", itemID = 79104, qty = 100, ahUnitPrice = 50 },
	}, { title = "DeductOwned False Test", ownershipProvider = function() return { bags = 0, bank = 0, mail = 0, alts = {} } end })
	local origSearch14 = app.searchAH
	app.searchAH = function() return true end
	if _G.AuctionHouseFrame and _G.AuctionHouseFrame.Show then _G.AuctionHouseFrame:Show() end
	app.enterOrderFlowMode("ah")
	cb.OnCommodityPurchaseConfirmed(79104, 40)
	ns.MarketScan.HandleEvent("COMMODITY_PURCHASE_SUCCEEDED")
	if _G.AuctionHouseFrame and _G.AuctionHouseFrame.Hide then _G.AuctionHouseFrame:Hide() end
	app.searchAH = origSearch14
	local st14Pre = of.GetState().stages.ah.items[1]
	check(st14Pre and st14Pre.bought == 40,
		"Regress 14 precheck: bought=40, got " .. tostring(st14Pre and st14Pre.bought) .. ", col=" .. tostring(#(of.GetState().stages.collect.items)))
	of.MarkCollected(1)
	setSlot(0, 1, 79104, 40, false)
	of.LoadFromShoppingRows({
		{ name = "Reg Snapper", itemID = 79104, qty = 100, ahUnitPrice = 50 },
	}, {
		title = "DeductOwned False Sync",
		preserveProgress = true,
		deductOwned = false,
		ownershipProvider = function() return { bags = 40, bank = 0, mail = 0, alts = {} } end,
	})
	local st14After = of.GetState().stages.ah.items[1]
	check(st14After.bought == 40 and st14After.remaining == 60,
		"Regress 14: preserveProgress with opts.deductOwned=false keeps bought=40, remaining=60; got b=" .. tostring(st14After.bought) .. ", r=" .. tostring(st14After.remaining))
	if app.exitAHBuyingMode then app.exitAHBuyingMode(false) end

	-- (15) Finding #6: Over-stack MAIL_CLOSED grace decrements full stack (20->0) & completeSendMail updates cachedBagCounts + ownershipRev
	resetContainers()
	app.char.mail = { ["Quick Mail Moss"] = 20 }
	app.mailboxItems = { [79106] = 20 }
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Quick Mail Moss", itemID = 79106, qty = 0, ownedUsed = 5, ahUnitPrice = 100 },
	}, {
		title = "Over-Stack Grace Test",
		ownershipProvider = function(id)
			if id == 79106 then return { bags = 0, bank = 0, mail = 20, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	mockInbox = {
		{ sender = "AH", subject = "Stack 20", cod = 0, hasItem = 1, attach = { [1] = { name = "Quick Mail Moss", itemID = 79106, count = 20 } } },
	}
	app.atMailbox = true
	mf:Show()
	of.OnMailShow()
	local origTake15 = _G.TakeInboxItem
	_G.TakeInboxItem = function() end
	of.CollectFromMail(1)
	_G.TakeInboxItem = origTake15
	mf:Hide()
	app.atMailbox = false
	of.OnMailClosed()
	mockNow = mockNow + 0.4
	setSlot(0, 1, 79106, 20, false)
	of.OnBagUpdateDelayed()
	check((app.char.mail["Quick Mail Moss"] or 0) == 0 and (app.mailboxItems[79106] or 0) == 0,
		"Regress 15a: Over-stack MAIL_CLOSED grace decrements cached char.mail by full attachment stack (20->0, not 15)")

	if ns.Analytics and ns.Analytics.Capture and ns.Analytics.Capture._StageSendMail then
		local origGetSendMailItem = _G.GetSendMailItem
		local origGetSendMailItemLink = _G.GetSendMailItemLink
		local origGetSendMailMoney = _G.GetSendMailMoney
		local origGetSendMailCOD = _G.GetSendMailCOD
		local origGetSendMailPrice = _G.GetSendMailPrice
		if ns.Analytics.Store and ns.Analytics.Store.CurrentCharAndEcon then
			local curK, curE = ns.Analytics.Store.CurrentCharAndEcon()
			local revBefore = app.ownershipRev or 0
			app.charKey = curK
			app.char = { name = "Third Char", realm = "Forever", faction = "Horde", economy = curE, bags = { ["Safe Ink"] = 10 }, mail = {}, bank = {} }
			app.cachedBagCounts = { ["Safe Ink"] = 10 }
			app.cachedBagCountsByID = { [79109] = 10 }
			app._cachedOwnedCounts = { ["Safe Ink"] = 10 }
			MerchantMasterDB.chars[curK] = app.char
			local recKey15 = tostring(curE or "Normal-Horde") .. "-Forever-Benji Mongoose"
			MerchantMasterDB.chars[recKey15] = { name = "Benji Mongoose", realm = "Forever", faction = "Horde", economy = curE, bags = {}, bank = {}, mail = {} }
			_G.GetSendMailItem = function(idx) if idx == 1 then return "Safe Ink", 79109, 134400, 4 end end
			_G.GetSendMailItemLink = function(idx) if idx == 1 then return "|cffffffff|Hitem:79109::::::::60:::::|h[Safe Ink]|h|r" end end
			_G.GetSendMailMoney = function() return 0 end
			_G.GetSendMailCOD = function() return 0 end
			_G.GetSendMailPrice = function() return 0 end
			ns.Analytics.Capture._StageSendMail("Benji Mongoose")
			ns.Analytics.Capture.OnEvent(nil, "MAIL_SEND_SUCCESS")
			check((app.cachedBagCounts["Safe Ink"] or 0) == 6 and (app.cachedBagCountsByID[79109] or 0) == 6
				and app._cachedOwnedCounts == nil and (app.ownershipRev or 0) > revBefore,
				"Regress 15b: completeSendMail decrements cachedBagCounts & cachedBagCountsByID and bumps ownershipRev")
		end
		_G.GetSendMailItem = origGetSendMailItem
		_G.GetSendMailItemLink = origGetSendMailItemLink
		_G.GetSendMailMoney = origGetSendMailMoney
		_G.GetSendMailCOD = origGetSendMailCOD
		_G.GetSendMailPrice = origGetSendMailPrice
	end

	-- (16) Finding #7e: Partial Bank->Mail split marks residual Bank row 'done' cleanly
	resetContainers()
	of.ClearSavedState()
	of.LoadFromShoppingRows({
		{ name = "Heart of the Wild", itemID = 8140, qty = 0, ownedUsed = 20, ahUnitPrice = 100 },
	}, {
		title = "Partial Bank Split Status",
		ownershipProvider = function(id)
			if id == 8140 then return { bags = 0, bank = 20, mail = 0, alts = {} } end
			return { bags = 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	of.SetActiveStage("collect")
	local origBankIt16 = of.GetState().stages.collect.items[1]
	origBankIt16.collected = 5
	origBankIt16.remaining = 15
	mockInbox = {
		{ sender = "The Endboss", subject = "Heart", cod = 0, hasItem = 1, attach = { [1] = { name = "Heart of the Wild", itemID = 8140, count = 15 } } },
	}
	app.atMailbox = true
	mf:Show()
	of.OnMailShow()
	local residualBank16, promotedMail16 = nil, nil
	for _, it in ipairs(of.GetState().stages.collect.items) do
		if it.itemID == 8140 and it.source == "bank" then residualBank16 = it
		elseif it.itemID == 8140 and it.source == "mail" then promotedMail16 = it end
	end
	check(residualBank16 and residualBank16.needed == 5 and residualBank16.remaining == 0 and residualBank16.status == "done"
		and promotedMail16 and promotedMail16.needed == 15 and promotedMail16.status == "ready",
		"Regress 16: Partial Bank->Mail split marks residual Bank row status='done' (no zombie pending row)")
	mf:Hide()
	app.atMailbox = false
	of.OnMailClosed()

	-- Cleanup restored state
	of.ClearSavedState()
	resetContainers()
	for id, nm in pairs(itemNames) do
		if ns.ITEM_NAMES_BY_ID then ns.ITEM_NAMES_BY_ID[id] = origNames[id] end
		if ns.ITEM_IDS_BY_NAME then ns.ITEM_IDS_BY_NAME[nm] = origIDs[nm] end
		app.itemIDs[nm] = origIDs[nm]
	end
	MerchantMasterDB.chars = origCharsDB
	MerchantMasterDB.orderFlowState = origOrderFlowState
	MerchantMasterDB.includeMail = origIncludeMail
	MerchantMasterDB.includeBank = origIncludeBank
	MerchantMasterDB.includeAlts = origIncludeAlts
	_G.MerchantMasterLedgerDB = origLedgerDB
	app.charKey = origCharKey
	app.char = origChar
	app.mailboxItems = origMailboxItems
	app.atBank, app.atMail = origAtBank, origAtMail
	_G.C_Container = origCCont
	_G.BankFrame = origBF
	_G.MailFrame = origMailF
	_G.AuctionHouseFrame = origAHF
	_G.GetTime = origGetTime
	if _G.C_Timer and origTimerAfter then _G.C_Timer.After = origTimerAfter end
	_G.GetInboxNumItems = origGetInboxNum
	_G.GetInboxHeaderInfo = origGetInboxHeader
	_G.GetInboxItem = origGetInboxItem
	_G.GetInboxItemLink = origGetInboxLink
	_G.TakeInboxItem = origTakeInbox
	_G.RETRIEVING_DATA = origRetrieving
	ns.MailHelper = origMailHelper
	app.getBagCountByID = origGetBag
	_G.UnitName = origUnitName
	app.cachedBagCounts = nil
	app.cachedBagCountsByID = nil
	app._cachedOwnedCounts = nil
	app._cachedOwnedCountsByID = nil
	app.bagsDirty = true
	app.bagCountsDirty = true
	app.ownershipRev = (app.ownershipRev or 0) + 1
end)()

print("PASS: test_cart_buyer (" .. n .. " assertions)")
