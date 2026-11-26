-- Warcraft skin regressions. Synthetic host state only; never load SavedVariables.
local testsDir = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "./"
local ns, frames, host = dofile(testsDir .. "host_fixture.lua")
local Theme, app = ns.Theme, ns.app
local count = 0
local function check(ok, message)
	count = count + 1
	if not ok then error("WARCRAFT SKINS FAIL [" .. count .. "]: " .. tostring(message), 2) end
end
local skins = { "goblin", "human", "night_elf", "orc", "undead", "standard" }
local customSkins = { "human", "night_elf", "orc", "undead", "goblin" }
local API, panel, ui = MerchantMasterAPI, app.panel, app.ui
local function click(button, mouseButton)
	check(button and type(button:GetScript("OnClick")) == "function", "button has a click handler")
	button:GetScript("OnClick")(button, mouseButton or "LeftButton")
end
local function fire(event)
	host.eventFrame:GetScript("OnEvent")(host.eventFrame, event, "MerchantMaster")
end
local function textureIs(texture, key, name)
	check(texture and texture:GetTexture() == Theme.GetSkinAsset(key, name), key .. " uses " .. name .. " art")
end

-- Public selection and persistence. Simulate the real ADDON_LOADED path with an in-memory DB.
check(#Theme.UI_SKINS == 6, "exactly six choices are advertised")
check(#host.tocFiles == host.COUNTS.tocFiles, "TOC retains exactly " .. host.COUNTS.tocFiles .. " Lua files")
do
	local tocFh = assert(io.open(testsDir .. "../MerchantMaster.toc", "r"))
	local tocText = tocFh:read("*a")
	tocFh:close()
	local iconTex = tocText:match("##%s*IconTexture:%s*([^\r\n]+)")
	check(iconTex == "Interface\\AddOns\\MerchantMaster\\Textures\\MerchantMasterLogo",
		"TOC IconTexture points to Logo A (got " .. tostring(iconTex) .. ")")
end
check(ns.CRATE_ICON == 236994, "CRATE_ICON retained for crate rows")
check(ns.ADDON_ICON == "Interface\\AddOns\\MerchantMaster\\Textures\\MerchantMasterLogo", "ADDON_ICON points to 256px Logo A")
check(ns.ADDON_ICON_SMALL == "Interface\\AddOns\\MerchantMaster\\Textures\\MerchantMasterLogo64", "ADDON_ICON_SMALL points to 64px Logo A")
check(API.Theme == Theme and type(API.GetSkin) == "function" and type(API.SetSkin) == "function", "public skin API exists")
for i, key in ipairs(skins) do
	check(Theme.UI_SKINS[i].key == key and Theme.IsValidSkin(key), "advertised skin order: " .. key)
	check(Theme.GetSkinInfo(key).key == key, "skin info resolves " .. key)
end
check(not Theme.IsValidSkin("bogus"), "unknown skin is rejected")
for _, mode in ipairs({ "dark", "light" }) do
	API.SetSkin("standard")
	Theme.SetMode(mode)
	for _, key in ipairs(skins) do
		check(API.SetSkin(key) == key and API.GetSkin() == key, "API selects " .. key)
		check(MerchantMasterDB.uiSkin == key, "DB persists " .. key)
		check(Theme.GetUserMode() == mode and MerchantMasterDB.uiThemeMode == mode, "skin preserves user appearance " .. mode)
		check(Theme.GetMode() == (key == "standard" and mode or "dark"), "effective appearance is correct for " .. key)
		Theme.SetSkin(key == "human" and "orc" or "human", true)
		Theme.SetMode(mode == "dark" and "light" or "dark", true)
		fire("ADDON_LOADED")
		check(API.GetSkin() == key and MerchantMasterDB.uiSkin == key, "reload restores " .. key)
		check(Theme.GetUserMode() == mode and MerchantMasterDB.uiThemeMode == mode, "reload restores appearance " .. mode)
	end
end
check(API.SetSkin("invalid") == "goblin" and MerchantMasterDB.uiSkin == "goblin", "API invalid key falls back to Goblin")
MerchantMasterDB.uiSkin = "removed_skin"
fire("ADDON_LOADED")
check(API.GetSkin() == "goblin" and MerchantMasterDB.uiSkin == "goblin", "saved unknown skin recovers to Goblin")

-- Exercise the actual shared dropdown rows, rather than replacing OpenDropDown with a spy.
for _, buttonName in ipairs({ "optUiSkinBtn", "uiSkinBtn" }) do
	local button = ui[buttonName]
	check(button ~= nil, buttonName .. " exists")
	for _, key in ipairs(skins) do
		Theme.CloseDropDown()
		click(button)
		local menu
		for _, frame in ipairs(frames) do
			if frame.owner == button and frame.rows and frame:IsShown() then menu = frame; break end
		end
		check(menu and #menu.options == 6, buttonName .. " opens six-choice dropdown")
		local selectedRow
		for i, option in ipairs(menu.options) do
			check(menu.rows[i]:IsShown(), "dropdown choice is visible")
			if option.key == key then selectedRow = menu.rows[i] end
		end
		click(selectedRow)
		check(API.GetSkin() == key and MerchantMasterDB.uiSkin == key, buttonName .. " selects " .. key)
		check(not menu:IsShown(), "skin dropdown closes after selection")
		for _, name in ipairs({ "optUiSkinBtn", "uiSkinBtn" }) do
			check(ui[name]:GetText():find(Theme.GetSkinInfo(key).short, 1, true) ~= nil, name .. " label stays synchronized")
		end
	end
	click(button, "RightButton")
	check(API.GetSkin() == "goblin", buttonName .. " right-click resets Goblin")
end

local aliases = {
	{ "apple", "standard" }, { "default", "goblin" }, { "stormwind", "human" }, { "alliance", "human" },
	{ "nightelf", "night_elf" }, { "ne", "night_elf" }, { "kaldorei", "night_elf" }, { "night elf", "night_elf" },
	{ "night-elf", "night_elf" }, { "orgrimmar", "orc" }, { "horde", "orc" }, { "forsaken", "undead" },
	{ "ud", "undead" }, { "baron", "goblin" }, { "trade", "goblin" }, { "tradebaron", "goblin" },
	{ "trade baron", "goblin" }, { "bilgewater", "goblin" },
}
local originalPrint, messages = print, {}
print = function(message) messages[#messages + 1] = tostring(message) end
for _, command in ipairs({ "theme", "skin" }) do
	for _, key in ipairs(skins) do
		SlashCmdList.MERCHANTMASTER(command .. " " .. key)
		check(API.GetSkin() == key, "slash selects primary key " .. key)
	end
	for _, spec in ipairs(aliases) do
		SlashCmdList.MERCHANTMASTER(command .. " " .. spec[1])
		check(API.GetSkin() == spec[2] and MerchantMasterDB.uiSkin == spec[2], "slash alias " .. command .. " " .. spec[1])
	end
end
SlashCmdList.MERCHANTMASTER("  THEME HUMAN  ")
check(API.GetSkin() == "human", "slash accepts casing and surrounding whitespace")
SlashCmdList.MERCHANTMASTER("theme invalid")
check(API.GetSkin() == "human", "unknown slash choice preserves selection")
check(messages[#messages]:find("Unknown UI Theme", 1, true) ~= nil, "unknown slash choice reports valid choices")
SlashCmdList.MERCHANTMASTER("theme")
check(API.GetSkin() == "human", "bare theme command only reports selection")
check(messages[#messages]:find("human", 1, true) ~= nil, "bare theme command reports current selection")
print = originalPrint

-- Every skin texture used by the shell/cards is a client-compatible BLP2 (DXT1/DXT5) or TGA.
local commonAssets = { "surface", "socket", "sidebar_bg", "rail_v", "rail_h", "portrait", "panel_hdr",
	"nav_active", "kpi_bg", "header_bg", "header_tile", "cta_bg", "crest", "corner", "send_btn", "task_btn" }
local function powerOfTwo(n)
	if n < 1 then return false end
	while n > 1 do if n % 2 ~= 0 then return false end; n = n / 2 end
	return true
end
local function u32le(s, i)
	local b1, b2, b3, b4 = s:byte(i, i + 3)
	return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end
local function checkAsset(key, name)
	local blpFile = testsDir .. "../Assets/skins/" .. key .. "/" .. name .. ".blp"
	local f = io.open(blpFile, "rb")
	if f then
		local hdr, length = f:read(148), f:seek("end")
		f:close()
		check(#hdr == 148 and hdr:sub(1, 4) == "BLP2", key .. "/" .. name .. " has valid BLP2 header")
		local btype = u32le(hdr, 5)
		local enc, _, aenc = hdr:byte(9, 11)
		local w, h = u32le(hdr, 13), u32le(hdr, 17)
		local mip0Off, mip0Len = u32le(hdr, 21), u32le(hdr, 85)
		check(btype == 1 and enc == 2 and (aenc == 0 or aenc == 7), key .. "/" .. name .. " is BLP2 DXT1/DXT5")
		check(powerOfTwo(w) and powerOfTwo(h), key .. "/" .. name .. " dimensions are powers of two")
		if name == "crest" then
			check(w == 256 and h == 128, key .. "/crest.blp is downscaled 256x128, got " .. tostring(w) .. "x" .. tostring(h))
		end
		check(mip0Off >= 1172 and mip0Len > 0 and length >= mip0Off + mip0Len, key .. "/" .. name .. " mip0 data is complete")
		return
	end
	local file = testsDir .. "../Assets/skins/" .. key .. "/" .. name .. ".tga"
	f = io.open(file, "rb")
	check(f ~= nil, "skin asset exists: " .. key .. "/" .. name)
	local header, length = f:read(18), f:seek("end")
	f:close()
	check(#header == 18, "TGA has a complete header")
	local id, cmap, kind = header:byte(1, 3)
	local wl, wh, hl, hh, bits, descriptor = header:byte(13, 18)
	local w, h = wl + wh * 256, hl + hh * 256
	check(id == 0 and cmap == 0 and kind == 2, key .. "/" .. name .. " is uncompressed truecolor")
	check(bits == 32 and descriptor % 16 == 8, key .. "/" .. name .. " has 32-bit BGRA alpha")
	check(powerOfTwo(w) and powerOfTwo(h), key .. "/" .. name .. " dimensions are powers of two")
	check(length >= 18 + w * h * 4, key .. "/" .. name .. " pixel data is complete")
end
for _, key in ipairs(customSkins) do
	for _, name in ipairs(commonAssets) do checkAsset(key, name) end
end
checkAsset("human", "banner")
check(Theme.GetSkinInfo("standard").label == "Modern Glass", "standard skin label is Modern Glass")
do
	local blpFh = io.open(testsDir .. "../Textures/MerchantMasterLogo.blp", "rb")
	check(blpFh ~= nil, "256px logo BLP2 exists: Textures/MerchantMasterLogo.blp")
	local hdr, length = blpFh:read(148), blpFh:seek("end")
	blpFh:close()
	check(#hdr == 148 and hdr:sub(1, 4) == "BLP2", "MerchantMasterLogo.blp has valid BLP2 header")
	local btype = u32le(hdr, 5)
	local enc, _, aenc = hdr:byte(9, 11)
	local w, h = u32le(hdr, 13), u32le(hdr, 17)
	local mip0Off, mip0Len = u32le(hdr, 21), u32le(hdr, 85)
	check(btype == 1 and enc == 2 and aenc == 7, "MerchantMasterLogo.blp is BLP2 DXT5")
	check(w == 256 and h == 256, "MerchantMasterLogo.blp is 256x256, got " .. tostring(w) .. "x" .. tostring(h))
	check(mip0Off >= 1172 and mip0Len > 0 and length >= mip0Off + mip0Len, "MerchantMasterLogo.blp mip0 data is complete")

	local footerMagic = string.rep("\0", 8) .. "TRUEVISION-XFILE.\0"
	local function checkLogoTga(relPath, expectedSize)
		local f = io.open(testsDir .. "../" .. relPath, "rb")
		check(f ~= nil, "logo TGA exists: " .. relPath)
		local data = f:read("*a")
		f:close()
		local expectedLen = 18 + expectedSize * expectedSize * 4 + 26
		check(#data == expectedLen, relPath .. " exact TGA 2.0 byte length (" .. tostring(#data) .. " == " .. expectedLen .. ")")
		local id, cmap, kind = data:byte(1, 3)
		local wl, wh, hl, hh, bits, descriptor = data:byte(13, 18)
		local w2, h2 = wl + wh * 256, hl + hh * 256
		check(id == 0 and cmap == 0 and kind == 2, relPath .. " is uncompressed truecolor")
		check(bits == 32 and descriptor == 0x08, relPath .. " has 32-bit BGRA bottom-left descriptor 0x08")
		check(w2 == expectedSize and h2 == expectedSize, relPath .. " is " .. expectedSize .. "x" .. expectedSize)
		check(data:sub(-26) == footerMagic, relPath .. " has TGA 2.0 TRUEVISION-XFILE footer")
	end
	checkLogoTga("Textures/MerchantMasterLogo64.tga", 64)
end

-- Capture original Standard geometry in the same host and compare after each custom round trip.
check(type(app.refreshSkinLayout) == "function", "live skin layout refresh must exist")
local chrome = ui.winChrome.warcraftChrome
check(chrome and chrome.frame and chrome.base and chrome.pools, "window exposes Warcraft chrome")
local geometryNames = { "sidebar", "rightPane", "toolbar", "mainArea", "walletCard", "brandLogoTex", "brandTitleFs", "brandSubFs", "searchWrap",
	"topCartBtn", "topTaskListBtn", "topSendAuctionatorBtn", "viewTitleFs", "scopeSeg", "charScopeSeg", "trafficLights", "appearanceSwitch",
	"dashBasketFooter", "dashBasketTotalBar", "dashBasketTotalLabel", "dashBasketTotalFs", "dashBasketHint" }
for i = 1, 3 do
	for _, field in ipairs({ "frame", "titleFs", "valueFs", "unitFs", "subFs", "iconTex" }) do geometryNames[#geometryNames + 1] = "kpi" .. i .. ":" .. field end
end
local function geometryWidget(name)
	local kpiIndex, field = name:match("^kpi(%d):(.+)$")
	if kpiIndex then return ui.dashKpis[tonumber(kpiIndex)][field] end
	local widget = ui[name]
	return widget and (widget.GetWidth and widget or widget.frame)
end
local function snapshot(widget)
	check(widget ~= nil, "snapshot widget exists")
	local result = { parent = widget:GetParent(), shown = widget:IsShown(), width = widget:GetWidth(), height = widget:GetHeight(), points = {} }
	if widget:GetObjectType() == "FontString" then result.font = { widget:GetFont() } end
	for i, point in ipairs(widget._points or {}) do
		result.points[i] = {}
		for k, v in pairs(point) do result.points[i][k] = v end
	end
	return result
end
local function sameGeometry(widget, expected, label)
	check(widget:GetParent() == expected.parent, label .. " restores parent")
	check(widget:IsShown() == expected.shown, label .. " restores visibility")
	check(widget:GetWidth() == expected.width and widget:GetHeight() == expected.height, label .. " restores dimensions")
	if expected.font then
		local font = { widget:GetFont() }
		for i, value in ipairs(expected.font) do check(font[i] == value, label .. " restores font") end
	end
	local points = widget._points or {}
	check(#points == #expected.points, label .. " restores anchor count")
	for i, point in ipairs(expected.points) do
		for k, v in pairs(point) do check(points[i][k] == v, label .. " restores anchor " .. i .. ":" .. k) end
		for k, v in pairs(points[i]) do check(point[k] == v, label .. " has no additional anchor values") end
	end
end
local rowNames = { "dashCraftRows", "dashOutlierRows", "dashTurninRows", "dashBasketRows" }
local cardNames = { "dashLeftCard", "dashRightCard", "dashTurninCard", "dashBasketCard" }
local function checkRows(custom, key)
	for _, group in ipairs(rowNames) do
		check(type(ui[group]) == "table" and #ui[group] > 0, group .. " contains rows")
		for _, row in ipairs(ui[group]) do
			check(row.icon and row.iconSocket and row.glyphBadge, group .. " has reversible icon regions")
			check(row.icon:IsShown() == custom and row.iconSocket:IsShown() == custom, group .. " swaps icon and socket visibility")
			check(row.glyphBadge.frame:IsShown() ~= custom, group .. " swaps Standard glyph visibility")
			if custom then textureIs(row.iconSocket, key, "socket"); check(row.icon:GetTexture() ~= nil, group .. " icon is populated") end
		end
	end
end
local function standardHidden()
	check(not chrome.frame:IsShown() and not chrome.base:IsShown(), "Standard hides Warcraft chrome and base")
	check(ui.skinControls and not ui.skinControls:IsShown(), "Standard hides Warcraft window controls")
	check(ui.skinPortrait and not ui.skinPortrait:IsShown(), "Standard hides portrait")
	check(ui.skinHeader and not ui.skinHeader:IsShown(), "Standard hides Warcraft header")
	check(ui.skinWalletPortrait and not ui.skinWalletPortrait:IsShown(), "Standard hides wallet portrait")
	for _, name in ipairs({ "sidebar", "rightPane", "walletCard", "searchWrap" }) do
		check(ui[name].skinBackground and not ui[name].skinBackground:IsShown(), "Standard hides " .. name .. " custom substrate")
	end
	for _, name in ipairs(cardNames) do
		local card = ui[name]
		check(not card.skinFill:IsShown() and not card.hdrPlate:IsShown(), "Standard restores " .. name .. " plates")
		for _, edge in ipairs(card.skinEdges) do check(not edge:IsShown(), "Standard hides card perimeter") end
	end
	if ui.scopeSeg and ui.scopeSeg.frame and ui.scopeSeg.frame.skinEdges then
		for _, edge in ipairs(ui.scopeSeg.frame.skinEdges) do check(not edge:IsShown(), "Standard hides scopeSeg perimeter") end
	end
	for _, ck in ipairs({ "minimize", "maximize", "close" }) do
		local cb = ui.skinControls and ui.skinControls[ck]
		if cb and cb.skinEdges then
			for _, edge in ipairs(cb.skinEdges) do check(not edge:IsShown(), "Standard hides skinControls." .. ck .. " perimeter") end
		end
	end
	checkRows(false)
end
local function captureTexCoord(tex)
	if not tex or tex._tcWrapped then return end
	local orig = tex.SetTexCoord
	tex._tcWrapped = true
	function tex:SetTexCoord(a, b, c, d, ...)
		self._texCoord = { a, b, c, d }
		if orig then return orig(self, a, b, c, d, ...) end
	end
end
local function assertUnitUV(tex, label)
	local tc = tex and tex._texCoord
	check(tc and tc[1] == 0 and tc[2] == 1 and tc[3] == 0 and tc[4] == 1, label)
end
captureTexCoord(ui.skinHeader.skinHeaderTile)
captureTexCoord(ui.sidebar.skinBackground)
captureTexCoord(ui.rightPane.skinBackground)
captureTexCoord(ui.mainArea.skinBackground)
captureTexCoord(ui.walletCard.skinSurface)
for _, name in ipairs(cardNames) do
	captureTexCoord(ui[name].skinSurface)
	captureTexCoord(ui[name].hdrBar.hdrTile)
end
for _, grpName in ipairs({ "dashKpis", "spreadKpis", "cratesKpis", "forgedKpis" }) do
	for _, kpi in ipairs(ui[grpName] or {}) do captureTexCoord(kpi.skinTile) end
end
panel:Show()
for _, mode in ipairs({ "dark", "light" }) do
	API.SetSkin("standard")
	Theme.SetMode(mode)
	app.setTab("dashboard")
	app.refreshSkinLayout()
	local original = {}
	for _, name in ipairs(geometryNames) do original[name] = snapshot(geometryWidget(name)) end
	local originalNav = {}
	for i, nav in ipairs(ui.navOrder) do originalNav[i] = snapshot(nav) end
	local originalSections = {}
	for i, sec in ipairs(ui.sidebarSections) do originalSections[i] = snapshot(sec) end
	for _, key in ipairs(customSkins) do
		API.SetSkin(key)
		check(chrome.frame:IsShown() and chrome.base:IsShown(), key .. " shows frame chrome")
		local art = Theme.SKIN_ART[key]
		local cw, ch = art.corner[1], art.corner[2]
		check(chrome.corners.TOPLEFT:GetWidth() == cw and chrome.corners.TOPLEFT:GetHeight() == ch,
			key .. " corner uses exact {w, h} geometry")
		check(chrome.crest:GetWidth() == art.crest[1] and chrome.crest:GetHeight() == art.crest[2],
			key .. " crest uses exact {w, h} geometry")
		check(ui.skinControls:IsShown() and ui.skinPortrait:IsShown(), key .. " shows Warcraft header")
		check(ui.skinPortrait:GetTexture() == ns.ADDON_ICON_SMALL, key .. " top-left brand icon uses Logo A 64")
		check(ui.brandLogoTex and not ui.brandLogoTex:IsShown(), key .. " hides Standard sidebar brandLogoTex")
		local bgLayer = ui.skinHeader.skinBackground and ui.skinHeader.skinBackground:GetDrawLayer()
		local tileLayer = ui.skinHeader.skinHeaderTile and ui.skinHeader.skinHeaderTile:GetDrawLayer()
		local iconLayer = ui.skinPortrait:GetDrawLayer()
		local titleLayer = ui.brandTitleFs:GetDrawLayer()
		local subLayer = ui.brandSubFs:GetDrawLayer()
		check(tileLayer == "BACKGROUND" and bgLayer == "BACKGROUND" and iconLayer == "ARTWORK" and titleLayer == "OVERLAY" and subLayer == "OVERLAY",
			key .. " top-left header brand icon, title, and subtitle render strictly above header_tile and header_bg")
		check(ui.skinHeader.skinHeaderTile and ui.skinHeader.skinHeaderTile._wrapH == "REPEAT" and ui.skinHeader.skinHeaderTile._wrapV == "REPEAT",
			key .. " header_tile uses REPEAT wrap mode")
		check(ui.rightPane.skinBackground and ui.rightPane.skinBackground._wrapH == "CLAMP" and ui.rightPane.skinBackground._wrapV == "CLAMP",
			key .. " rightPane surface uses CLAMP wrap mode")
		assertUnitUV(ui.rightPane.skinBackground, key .. " rightPane surface stretches 0..1")
		check(ui.mainArea.skinBackground and ui.mainArea.skinBackground._wrapH == "CLAMP" and ui.mainArea.skinBackground._wrapV == "CLAMP",
			key .. " mainArea surface uses CLAMP wrap mode")
		assertUnitUV(ui.mainArea.skinBackground, key .. " mainArea surface stretches 0..1")
		check(ui.walletCard.skinSurface and ui.walletCard.skinSurface._wrapH == "CLAMP" and ui.walletCard.skinSurface._wrapV == "CLAMP",
			key .. " walletCard surface uses CLAMP wrap mode")
		assertUnitUV(ui.walletCard.skinSurface, key .. " walletCard surface stretches 0..1")
		check(ui.sidebar.skinBackground and ui.sidebar.skinBackground._wrapH == "REPEAT" and ui.sidebar.skinBackground._wrapV == "REPEAT",
			key .. " sidebar_bg uses REPEAT horizontal and vertical wrap mode")
		local sbUV = ui.sidebar.skinBackground._texCoord
		check(sbUV and sbUV[1] == 0 and sbUV[2] > 0 and sbUV[3] == 0 and sbUV[4] and math.abs(sbUV[4] - 1) > 1e-4,
			key .. " sidebar_bg tiles vertically 1:1 (v1 ~= 1 when height ~= 210)")
		check(ui.skinPortrait:GetParent() == ui.skinHeader and ui.brandSubFs:GetParent() == ui.skinHeader and ui.brandSubFs:IsShown(),
			key .. " header parents and shows brand icon and subtitle")
		textureIs(ui.skinWalletPortrait, key, "portrait")
		textureIs(chrome.crest, key, "crest")
		local left, top, right, bottom = Theme.GetSkinInset(key)
		check(left > 0 and top > 0 and right > 0 and bottom > 0, key .. " reserves positive chrome insets")
		local _, headerParent, _, headerX, headerY = ui.skinHeader:GetPoint(1)
		check(ui.skinHeader:IsShown() and headerParent == panel and headerX == left and headerY == -top, key .. " header uses chrome insets")
		local _, _, _, portraitX = ui.skinPortrait:GetPoint(1)
		local ctrlPt, ctrlRel, ctrlRelPt, ctrlX = ui.skinControls:GetPoint(1)
		check(portraitX == 44 and ctrlPt == "TOPRIGHT" and ctrlRel == ui.skinHeader and ctrlRelPt == "TOPRIGHT" and ctrlX == -42,
			key .. " insets header portrait (44) and far-right skinControls (-42) clear of top corners")
		local tbPt, tbRel, tbRelPt, tbX = ui.topTaskListBtn:GetPoint(1)
		check(tbPt == "TOPRIGHT" and tbRel == ui.skinControls and tbRelPt == "TOPLEFT" and tbX == -10,
			key .. " anchors topTaskListBtn -10 left of skinControls")
		textureIs(ui.topTaskListBtn.skinArt, key, "task_btn")
		local sbPt, sbRel, sbRelPt, sbX = ui.topSendAuctionatorBtn:GetPoint(1)
		check(sbPt == "TOPRIGHT" and sbRel == ui.topTaskListBtn and sbRelPt == "TOPLEFT" and sbX == -6,
			key .. " anchors topSendAuctionatorBtn -6 left of topTaskListBtn")
		local cbPt, cbRel, cbRelPt, cbX = ui.topCartBtn:GetPoint(1)
		check(cbPt == "TOPRIGHT" and cbRel == ui.topSendAuctionatorBtn and cbRelPt == "TOPLEFT" and cbX == -6,
			key .. " anchors topCartBtn -6 left of topSendAuctionatorBtn")
		check(ui.scopeSeg.frame.skinEdges and #ui.scopeSeg.frame.skinEdges == 4, key .. " frames scopeSeg with 4 perimeter edges")
		for _, edge in ipairs(ui.scopeSeg.frame.skinEdges) do check(edge:IsShown(), key .. " shows scopeSeg perimeter edge") end
		for _, ck in ipairs({ "minimize", "maximize", "close" }) do
			local cb = ui.skinControls[ck]
			check(cb and cb.skinEdges and #cb.skinEdges == 4, key .. " frames skinControls." .. ck .. " with 4 edges")
			for _, edge in ipairs(cb.skinEdges) do check(edge:IsShown(), key .. " shows skinControls." .. ck .. " edge") end
		end
		local _, sidebarParent, _, sidebarX, sidebarY = ui.sidebar:GetPoint(1)
		check(sidebarParent == panel and sidebarX == left and sidebarY == -top - ui.skinHeader:GetHeight(), key .. " sidebar clears full-width header")
		check(ui.brandTitleFs:GetParent() == ui.skinHeader and ui.toolbar:GetParent() == ui.skinHeader, key .. " header hosts brand and toolbar")
		check(ui.searchWrap and ui.searchWrap:IsShown(), key .. " shows sidebar searchWrap")
		check(#ui.sidebarSections == 6, key .. " has all 6 sidebar sections")
		check(#ui.navOrder == 16, key .. " has all 16 sidebar nav buttons")
		check(ui.navBtns.auction_house == nil, key .. " has no auction_house nav button")
		local sidebarH = 730 - top - bottom - ui.skinHeader:GetHeight()
		local walletTopOffset = -(sidebarH - 24 - ui.walletCard:GetHeight())
		local expectedSecTitles = { "OVERVIEW", "MARKET", "TURN-INS", "PROGRESS & LEDGER", "SNIPER", "SYSTEM" }
		local secBands = {}
		for si, sec in ipairs(ui.sidebarSections) do
			check(sec:IsShown(), key .. " shows sidebar section " .. si)
			check(sec:GetHeight() >= 12, key .. " sidebar section " .. si .. " has explicit non-zero height >= 12, got " .. tostring(sec:GetHeight()))
			check(sec:GetParent() ~= ui.sidebar and sec:GetParent() == ui.sidebarSectionLayer,
				key .. " sidebar section " .. si .. " is parented to dedicated child layer above sidebar background")
			check(sec:GetParent():GetFrameLevel() > ui.sidebar:GetFrameLevel(),
				key .. " sidebar section layer sits above sidebar FrameLevel")
			check(sec:GetText() ~= "" and sec:GetText() == expectedSecTitles[si],
				key .. " sidebar section " .. si .. " renders non-empty title '" .. expectedSecTitles[si] .. "', got '" .. tostring(sec:GetText()) .. "'")
			local secLayer = sec:GetDrawLayer()
			check(secLayer == "OVERLAY", key .. " sidebar section " .. si .. " uses OVERLAY draw layer")
			local _, _, _, _, sy = sec:GetPoint(1)
			check(sy > walletTopOffset, key .. " sidebar section " .. si .. " stays clear above walletCard")
			secBands[si] = { top = sy, bottom = sy - sec:GetHeight(), title = expectedSecTitles[si] }
		end
		local prevNavY, prevNavH
		for ni, nb in ipairs(ui.navOrder) do
			local _, _, _, _, curY = nb:GetPoint(1)
			local curH = nb:GetHeight()
			check(type(curY) == "number" and type(curH) == "number" and curH > 0,
				key .. " nav button " .. ni .. " has numeric Y and positive height")
			if prevNavY ~= nil then
				check(prevNavY - prevNavH > curY,
					string.format("%s nav button %d overlaps previous (prevY=%s, prevH=%s, curY=%s)",
						key, ni, tostring(prevNavY), tostring(prevNavH), tostring(curY)))
			end
			for si, band in ipairs(secBands) do
				local overlaps = (curY > band.bottom) and ((curY - curH) < band.top)
				check(not overlaps,
					string.format("%s nav button %d [%s..%s] overlaps section %d (%s) [%s..%s]",
						key, ni, tostring(curY), tostring(curY - curH), si, band.title, tostring(band.top), tostring(band.bottom)))
			end
			prevNavY, prevNavH = curY, curH
		end
		local _, _, _, _, basketY = ui.skinBasketNav:GetPoint(1)
		local basketH = ui.skinBasketNav:GetHeight()
		check(basketY == -101 and basketH == 18,
			key .. " skinBasketNav sits at y=-101 h=18, got y=" .. tostring(basketY) .. " h=" .. tostring(basketH))
		for si, band in ipairs(secBands) do
			local overlaps = (basketY > band.bottom) and ((basketY - basketH) < band.top)
			check(not overlaps,
				string.format("%s skinBasketNav [%s..%s] overlaps section %d (%s) [%s..%s]",
					key, tostring(basketY), tostring(basketY - basketH), si, band.title, tostring(band.top), tostring(band.bottom)))
		end
		local _, _, _, _, lastNavY = ui.navOrder[#ui.navOrder]:GetPoint(1)
		check(lastNavY == -473, key .. " 16th sidebar nav button sits at customNavY[16] = -473, got " .. tostring(lastNavY))
		check(lastNavY - ui.navOrder[#ui.navOrder]:GetHeight() > walletTopOffset,
			key .. " final sidebar nav button stays clear above walletCard")
		check(ui.skinBasketNav:IsShown(), key .. " exposes the Shopping Basket navigation row")
		check(ui.dashBasketFooter:GetHeight() == 44 and not ui.dashBasketTotalBar:IsShown(), key .. " uses the compact shared basket footer")
		for _, kpi in ipairs(ui.dashKpis) do
			check(kpi.frame:GetHeight() == 68 and not kpi.iconTex:IsShown(), key .. " uses reference KPI height without Apple glyphs")
			local effectiveCardW = math.max(320, kpi.frame:GetWidth() or 0)
			check(kpi.valueFs:GetWidth() >= 0 and kpi.valueFs:GetWidth() <= effectiveCardW,
				key .. " KPI valueFs width is non-negative and clamped inside card")
			check(kpi.skinTile and kpi.skinTile:IsShown() and kpi.skinTile._wrapH == "CLAMP" and kpi.skinTile._wrapV == "CLAMP",
				key .. " KPI card stretches surface underneath translucent kpi_bg")
			assertUnitUV(kpi.skinTile, key .. " KPI card skinTile stretches 0..1")
			local _, fontSize = kpi.valueFs:GetFont()
			check(fontSize == 16, key .. " uses the compact KPI value type")
		end
		for _, grpName in ipairs({ "spreadKpis", "cratesKpis", "forgedKpis" }) do
			for idx, kpi in ipairs(ui[grpName] or {}) do
				check(kpi.frame:GetHeight() == 104, key .. " " .. grpName .. "[" .. idx .. "] keeps 104px height above tab table")
				check(not kpi.iconTex or not kpi.iconTex:IsShown(), key .. " " .. grpName .. "[" .. idx .. "] hides Apple iconTex")
				check(kpi.valueFs:GetWidth() == 0 and kpi.valueFs:GetNumPoints() == 1,
					key .. " " .. grpName .. "[" .. idx .. "] uses single TOPLEFT anchor and width=0")
				check(kpi.valueFs:GetJustifyH() == "LEFT", key .. " " .. grpName .. "[" .. idx .. "] left-aligns valueFs")
				check(kpi.skinTile and kpi.skinTile:IsShown() and kpi.skinTile._wrapH == "CLAMP" and kpi.skinTile._wrapV == "CLAMP",
					key .. " " .. grpName .. "[" .. idx .. "] skinTile uses CLAMP wrap mode")
				assertUnitUV(kpi.skinTile, key .. " " .. grpName .. "[" .. idx .. "] skinTile stretches 0..1")
			end
		end
		for _, name in ipairs(cardNames) do
			check(ui[name].skinFill:IsShown() and ui[name].hdrPlate:IsShown(), key .. " paints " .. name)
			check(ui[name].skinSurface and ui[name].skinSurface:IsShown() and ui[name].skinSurface._wrapH == "CLAMP" and ui[name].skinSurface._wrapV == "CLAMP",
				key .. " " .. name .. " surface uses CLAMP wrap mode")
			assertUnitUV(ui[name].skinSurface, key .. " " .. name .. " surface stretches 0..1")
			check(ui[name].hdrBar.hdrTile and ui[name].hdrBar.hdrTile:IsShown() and ui[name].hdrBar.hdrTile._wrapH == "REPEAT" and ui[name].hdrBar.hdrTile._wrapV == "REPEAT",
				key .. " tiles header_tile underneath " .. name .. " hdrPlate")
			textureIs(ui[name].hdrPlate, key, "panel_hdr")
		end
		checkRows(true, key)
		API.SetSkin("standard")
		check(Theme.GetMode() == mode, "Standard returns to " .. mode)
		for _, name in ipairs(geometryNames) do sameGeometry(geometryWidget(name), original[name], mode .. " " .. name) end
		for i, nav in ipairs(ui.navOrder) do sameGeometry(nav, originalNav[i], "Standard navigation " .. i) end
		for i, sec in ipairs(ui.sidebarSections) do sameGeometry(sec, originalSections[i], "Standard section " .. i) end
		for _, grpName in ipairs({ "spreadKpis", "cratesKpis", "forgedKpis" }) do
			for idx, kpi in ipairs(ui[grpName] or {}) do
				check(not kpi.iconTex or kpi.iconTex:IsShown(), "Standard restores " .. grpName .. "[" .. idx .. "] iconTex")
				if kpi._alignValue == "RIGHT" then
					check(kpi.valueFs:GetNumPoints() == 2 and kpi.valueFs:GetJustifyH() == "RIGHT",
						"Standard restores " .. grpName .. "[" .. idx .. "] alignValue=RIGHT anchors")
				end
			end
		end
		standardHidden()
	end
end

-- Changing bound item/recipe data updates every icon group and removes stale textures.
check(type(app.refreshDashRowIcons) == "function", "row icon refresh is exposed")
local savedItemIcon, savedSpellTexture = ns.ItemIcon, GetSpellTexture
ns.ItemIcon = function(id) return id and ("synthetic_item_" .. tostring(id)) end
GetSpellTexture = function(id) return "synthetic_spell_" .. tostring(id) end
API.SetSkin("orc")
for groupIndex, group in ipairs(rowNames) do
	local row = ui[group][1]
	local data, rowData, itemID = row.data, row.rowData, row.itemID
	row.itemID, row.rowData = nil, nil
	local field = ({ "outputItemID", "itemID", "crateID", "writID" })[groupIndex]
	row.data = { [field] = 91001 }
	app.refreshDashRowIcons()
	check(row.icon:GetTexture() == "synthetic_item_91001", group .. " resolves bound item ID")
	row.data = { [field] = 91002 }
	app.refreshDashRowIcons()
	check(row.icon:GetTexture() == "synthetic_item_91002", group .. " replaces previous item icon")
	row.data = { spellID = 91003 }
	app.refreshDashRowIcons()
	check(row.icon:GetTexture() == "synthetic_spell_91003", group .. " resolves recipe spell fallback")
	row.data = {}
	app.refreshDashRowIcons()
	check(row.icon:GetTexture() ~= "synthetic_spell_91003" and row.icon:GetTexture() ~= nil, group .. " clears missing-data stale texture")
	row.data, row.rowData, row.itemID = data, rowData, itemID
end
ns.ItemIcon, GetSpellTexture = savedItemIcon, savedSpellTexture
app.refreshDashRowIcons()

-- Runtime lifecycle: resize and OnShow rebuild the rails, minimized has no lower/side rails.
API.SetSkin("human")
panel:SetSize(1781, 843)
panel:GetScript("OnSizeChanged")(panel, 1781, 843)
check(#chrome.pools.top > 0 and chrome.pools.top[1]:IsShown(), "live resize lays out top rail")
local grownTop = 0
for _, tile in ipairs(chrome.pools.top) do if tile:IsShown() then grownTop = grownTop + 1 end end
panel:SetSize(1320, 730)
panel:GetScript("OnSizeChanged")(panel, 1320, 730)
local shrunkTop = 0
for _, tile in ipairs(chrome.pools.top) do if tile:IsShown() then shrunkTop = shrunkTop + 1 end end
check(shrunkTop < grownTop, "shrinking hides surplus rail tiles")
chrome.frame:Hide()
panel:Hide(); panel:Show()
check(chrome.frame:IsShown(), "OnShow restores custom chrome")
app.setMinimized(true)
check(app._minimized and not ui.mainArea:IsShown(), "minimized hides content")
for _, side in ipairs({ "bottom", "left", "right" }) do
	for _, tile in ipairs(chrome.pools[side]) do check(not tile:IsShown(), "minimized hides " .. side .. " rails") end
end
for _, cornerKey in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
	check(not chrome.corners[cornerKey]:IsShown(), "minimized hides tall corner clasp " .. cornerKey)
end
for _, edgeKey in ipairs({ "top", "bottom", "left", "right" }) do
	check(chrome.shell[edgeKey]:IsShown() and chrome.shellInner[edgeKey]:IsShown(), "minimized keeps 4-side perimeter " .. edgeKey)
end
API.SetSkin("goblin")
check(app._minimized and not ui.mainArea:IsShown(), "live skin selection preserves minimized state")
panel:Hide()
API.SetSkin("standard")
check(app._minimized and not chrome.frame:IsShown() and ui.sidebar:IsShown() and ui.rightPane:IsShown(),
	"Standard restores minimized chrome and sidebar/rightPane even while closed")
panel:Show()
app.setMinimized(false)
check(not app._minimized and ui.mainArea:IsShown(), "restore from minimized shows content")
app.setTab("bags")
local bags = {}
for _, name in ipairs(geometryNames) do bags[name] = snapshot(geometryWidget(name)) end
for _, key in ipairs(customSkins) do
	API.SetSkin(key)
	check(app.activeTab == "bags", "skin selection preserves compact Bags route")
	API.SetSkin("standard")
	for _, name in ipairs(geometryNames) do sameGeometry(geometryWidget(name), bags[name], "Bags " .. name) end
end
app.setTab("dashboard")
-- The custom sidebar uses the compact Craftable Now toggle for character scope.
local savedKnown, savedUnlock, savedAllChars = MerchantMasterDB.knownRecipesOnly, MerchantMasterDB.unlockFilter, MerchantMasterDB.craftableAllChars
for _, key in ipairs(customSkins) do
	API.SetSkin(key)
	check(ui.dashAucBtn._mmPlate.variant == "secondary", key .. " uses light text on the painted CTA")
	local cr, cg, cb = ui.dashAucBtn._mmLabel:GetTextColor()
	local ctaInk = Theme.GetActivePalette().text
	check(cr == ctaInk[1] and cg == ctaInk[2] and cb == ctaInk[3], key .. " CTA text uses readable skin ink")
	MerchantMasterDB.knownRecipesOnly, MerchantMasterDB.unlockFilter, MerchantMasterDB.craftableAllChars = true, "known", false
	app.syncToolbarCharScope(true)
	check(not app.canFitToolbarCharScope() and not ui.charScopeSeg.frame:IsShown(), key .. " uses the compact character scope toggle")
	click(ui.scopeSeg.buttons.known)
	check(MerchantMasterDB.craftableAllChars == true, key .. " can select all characters")
	click(ui.scopeSeg.buttons.known)
	check(MerchantMasterDB.craftableAllChars == false, key .. " can return to the current character")
end
MerchantMasterDB.knownRecipesOnly, MerchantMasterDB.unlockFilter, MerchantMasterDB.craftableAllChars = savedKnown, savedUnlock, savedAllChars
API.SetSkin("standard")
check(ui.dashAucBtn._mmPlate.variant == "primary", "Standard restores original primary CTA styling")

-- Logo A brand wiring: Minimap button, AH SearchBar button, Options logo, Standard sidebar logo, and window crest.
check(app.launcher and app.launcher.icon == ns.ADDON_ICON_SMALL, "LDB launcher uses Logo A 64")
app.refresh()
check(app.launcher.icon == ns.ADDON_ICON_SMALL, "bagCrates()/refresh() never overwrites launcher icon with crate icon")
check(ui.winChrome and ui.winChrome.crestIcon and ui.winChrome.crestIcon:GetTexture() == ns.ADDON_ICON,
	"window crestIcon retains Logo A 256 after refresh")
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
local mmBtn = DBIcon and DBIcon.GetMinimapButton and DBIcon:GetMinimapButton("MerchantMaster")
check(mmBtn ~= nil, "LibDBIcon minimap button registered")
check(mmBtn.border and not mmBtn.border:IsShown(), "minimap button hides default Blizzard border ring")
check(mmBtn.background and not mmBtn.background:IsShown(), "minimap button hides default Blizzard circular backing")
check(mmBtn.icon and mmBtn.icon:GetTexture() == ns.ADDON_ICON_SMALL and mmBtn.icon:GetWidth() == 30 and mmBtn.icon:GetHeight() == 30,
	"minimap button icon uses 30x30 Logo A 64")

check(ui.brandLogoTex and ui.brandLogoTex:IsShown() and ui.brandLogoTex:GetTexture() == ns.ADDON_ICON_SMALL
	and ui.brandLogoTex:GetWidth() == 28 and ui.brandLogoTex:GetHeight() == 28,
	"Standard sidebar shows 28x28 Logo A 64 brandLogoTex")

check(ui.optLogoTex and ui.optLogoTex:IsShown() and ui.optLogoTex:GetTexture() == ns.ADDON_ICON
	and ui.optLogoTex:GetWidth() == 36 and ui.optLogoTex:GetHeight() == 36,
	"Options header shows 36x36 Logo A 256 optLogoTex")
check(app.buildSlashHelp and not app.buildSlashHelp():find("|night_elf", 1, true),
	"Options slash help avoids WoW |n newline escape before night_elf")

AuctionHouseFrame:Show()
host.eventFrame:GetScript("OnEvent")(host.eventFrame, "AUCTION_HOUSE_SHOW")
check(ui.ahBtn ~= nil, "AH SearchBar Logo A open button created on AUCTION_HOUSE_SHOW")
check(ui.ahBtn:GetWidth() == 28 and ui.ahBtn:GetHeight() == 28, "AH button is 28x28")
check(ui.ahBtn:GetText() == "", "AH icon button has empty text")
check(ui.ahBtn.icon and ui.ahBtn.icon:GetTexture() == ns.ADDON_ICON_SMALL, "AH button icon uses Logo A 64")
local wasShown = panel:IsShown()
click(ui.ahBtn, "LeftButton")
check(panel:IsShown() == (not wasShown), "AH button left-click toggles panel visibility")
click(ui.ahBtn, "LeftButton")
check(panel:IsShown() == wasShown, "AH button second left-click restores panel visibility")
AuctionHouseFrame:Hide()
host.eventFrame:GetScript("OnEvent")(host.eventFrame, "AUCTION_HOUSE_CLOSED")

print("Warcraft skins suite: " .. count .. " assertions passed")
