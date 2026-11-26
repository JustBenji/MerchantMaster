-- Fable 5.2 Design 1 Apple HIG & Liquid Glass Contract Suite (Pure Lua 5.1)
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local COUNTS = dofile(testsDir .. "catalog_counts.lua")
local addonDir = testsDir .. "../"

local count = 0
local function check(ok, msg)
	count = count + 1
	if not ok then
		error("FABLE APPLE HIG FAIL [" .. count .. "]: " .. tostring(msg), 2)
	end
end

local function approxCol(c, r, g, b, eps, label)
	eps = eps or 0.01
	check(type(c) == "table", label .. " is a color table")
	check(math.abs((c[1] or -1) - r) <= eps and math.abs((c[2] or -1) - g) <= eps and math.abs((c[3] or -1) - b) <= eps,
		string.format("%s expected (%.3f, %.3f, %.3f), got (%.3f, %.3f, %.3f)",
			label, r, g, b, tonumber(c[1]) or -1, tonumber(c[2]) or -1, tonumber(c[3]) or -1))
end

---------------------------------------------------------------------------------------------------
-- 1. MerchantMaster.toc invariant: strictly COUNTS.tocFiles .lua files
---------------------------------------------------------------------------------------------------
do
	local fh = assert(io.open(addonDir .. "MerchantMaster.toc", "rb"))
	local luaFiles = {}
	for line in fh:lines() do
		local clean = line:gsub("\r", ""):match("^%s*([^#%s].-)%s*$")
		if clean and clean:match("%.lua$") then
			luaFiles[#luaFiles + 1] = clean
		end
	end
	fh:close()
	check(#luaFiles == COUNTS.tocFiles, "MerchantMaster.toc must list exactly " .. COUNTS.tocFiles .. " .lua files, got " .. #luaFiles)
end

---------------------------------------------------------------------------------------------------
-- 2. All 46 Assets\apple\*.tga headers (type=2, bpp=32, descriptor=0x08, dimensions, non-empty alpha)
---------------------------------------------------------------------------------------------------
do
	local requiredTgas = {
		{ "glass_r22_fill.tga", 64, 64 },
		{ "glass_r22_openright_fill.tga", 64, 64 },
		{ "glass_r22_openleft_fill.tga", 64, 64 },
		{ "glass_r22_stroke.tga", 64, 64, true },
		{ "glass_r16_fill.tga", 64, 64 },
		{ "glass_r16_stroke.tga", 64, 64, true },
		{ "glass_r12_fill.tga", 64, 64 },
		{ "glass_r12_stroke.tga", 64, 64 },
		{ "glass_r10_fill.tga", 64, 64 },
		{ "glass_r10_stroke.tga", 64, 64 },
		{ "glass_r8_fill.tga", 64, 64 },
		{ "glass_r8_stroke.tga", 64, 64 },
		{ "pill_fill.tga", 64, 64 },
		{ "pill_stroke.tga", 64, 64, true },
		{ "circle_fill.tga", 64, 64 },
		{ "circle_stroke.tga", 64, 64 },
		{ "meter_track.tga", 32, 32 },
		{ "meter_fill.tga", 32, 32 },
		{ "shadow_r22.tga", 128, 128 },
		{ "specular_top.tga", 64, 16, true },
		{ "icon_grid.tga", 64, 64 },
		{ "icon_basket.tga", 64, 64 },
		{ "icon_flask.tga", 64, 64 },
		{ "icon_crown.tga", 64, 64 },
		{ "icon_book.tga", 64, 64 },
		{ "icon_crate.tga", 64, 64 },
		{ "icon_doc.tga", 64, 64 },
		{ "icon_shield.tga", 64, 64 },
		{ "icon_bars.tga", 64, 64 },
		{ "icon_trend.tga", 64, 64 },
		{ "icon_search.tga", 64, 64 },
		{ "icon_refresh.tga", 64, 64 },
		{ "icon_sun.tga", 64, 64 },
		{ "icon_moon.tga", 64, 64 },
		{ "icon_check.tga", 64, 64 },
		{ "icon_checkcircle.tga", 64, 64 },
		{ "icon_lock.tga", 64, 64 },
		{ "icon_send.tga", 64, 64 },
		{ "icon_leaf.tga", 64, 64 },
		{ "icon_vial.tga", 64, 64 },
		{ "icon_star.tga", 64, 64 },
		{ "icon_coins.tga", 64, 64 },
		{ "icon_bolt.tga", 64, 64 },
		{ "icon_chevron_down.tga", 64, 64 },
		{ "icon_close.tga", 64, 64 },
		{ "icon_gear.tga", 64, 64 },
	}
	for _, spec in ipairs(requiredTgas) do
		local name, expW, expH, opticalRim = spec[1], spec[2], spec[3], spec[4]
		local path = addonDir .. "Assets/apple/" .. name
		local fh = io.open(path, "rb")
		check(fh ~= nil, "Missing required Apple TGA asset: " .. path)
		local data = fh:read("*a")
		fh:close()
		check(#data >= 18 + expW * expH * 4, name .. " size too small: " .. #data)
		local idLen, cmapType, imgType = string.byte(data, 1, 3)
		local wLo, wHi, hLo, hHi, bpp, desc = string.byte(data, 13, 18)
		local w = wLo + wHi * 256
		local h = hLo + hHi * 256
		check(idLen == 0 and cmapType == 0, name .. " header idLen/cmapType == 0")
		check(imgType == 2, name .. " TGA image_type == 2, got " .. tostring(imgType))
		check(bpp == 32, name .. " TGA bpp == 32, got " .. tostring(bpp))
		check(desc == 0x08, string.format("%s TGA descriptor == 0x08, got 0x%02X", name, desc or 0))
		check(w == expW and h == expH, string.format("%s expected %dx%d, got %dx%d", name, expW, expH, w, h))
		local hasAlpha = false
		local pixStart = 18 + idLen + 1
		local pixEnd = 18 + idLen + w * h * 4
		for i = pixStart + 3, pixEnd, 4 do
			if string.byte(data, i) > 0 then
				hasAlpha = true
				break
			end
		end
		check(hasAlpha, name .. " has non-empty alpha channel")
		if opticalRim then
			check(#data == pixEnd + 26 and data:sub(-18) == "TRUEVISION-XFILE.\0", name .. " keeps its TGA 2.0 footer and size")
			local alphas, levels = {}, 0
			for i = pixStart + 3, pixEnd, 4 do
				local alpha = string.byte(data, i)
				if not alphas[alpha] then alphas[alpha], levels = true, levels + 1 end
			end
			check(levels >= 16, name .. " has at least 16 alpha levels in its optical rim")
		end
	end
end

---------------------------------------------------------------------------------------------------
-- 2B. Bundled Static Inter TTF Fonts (TrueType 0x00010000 sfnt, no fvar) + OFL.txt
---------------------------------------------------------------------------------------------------
do
	local requiredFonts = { "Inter-Regular.ttf", "Inter-SemiBold.ttf" }
	for _, fname in ipairs(requiredFonts) do
		local path = addonDir .. "Assets/fonts/" .. fname
		local fh = io.open(path, "rb")
		check(fh ~= nil, "Missing bundled font file: " .. path)
		local raw = fh:read("*a")
		fh:close()
		check(type(raw) == "string" and #raw >= 1024, fname .. " file size >= 1024 bytes, got " .. tostring(raw and #raw))
		local b1, b2, b3, b4 = string.byte(raw, 1, 4)
		check(b1 == 0x00 and b2 == 0x01 and b3 == 0x00 and b4 == 0x00,
			string.format("%s TTF sfnt header expected 0x00010000, got 0x%02X%02X%02X%02X",
				fname, b1 or 0, b2 or 0, b3 or 0, b4 or 0))
		local nHi, nLo = string.byte(raw, 5, 6)
		local numTables = nHi * 256 + nLo
		check(#raw >= 12 + numTables * 16, fname .. " table directory complete")
		local hasFvar = false
		for i = 0, numTables - 1 do
			if raw:sub(13 + i * 16, 16 + i * 16) == "fvar" then hasFvar = true; break end
		end
		check(not hasFvar, fname .. " is a static TrueType font (no fvar table)")
	end
	local oflPath = addonDir .. "Assets/fonts/OFL.txt"
	local oflFh = io.open(oflPath, "rb")
	check(oflFh ~= nil, "Missing SIL OFL license file: " .. oflPath)
	local oflText = oflFh:read("*a")
	oflFh:close()
	check(type(oflText) == "string" and #oflText >= 1000 and oflText:find("SIL OPEN FONT LICENSE", 1, true) ~= nil,
		"Assets/fonts/OFL.txt contains SIL Open Font License text")
end

---------------------------------------------------------------------------------------------------
-- 3. Load Full Addon via host_fixture.lua & Verify Theme, Palettes, Widgets, and Shell Layout
---------------------------------------------------------------------------------------------------
local ns, createdFrames, hostEnv = dofile(testsDir .. "host_fixture.lua")
local Theme = ns.Theme
local app = ns.app
Theme.SetSkin("standard", true)

-- 3A. Theme palettes match Fable 5.2 Design 1 core tokens
do
	check(type(Theme.PALETTES) == "table" and type(Theme.PALETTES.dark) == "table" and type(Theme.PALETTES.light) == "table",
		"Theme.PALETTES.dark and Theme.PALETTES.light exist")

	local dk = Theme.PALETTES.dark
	approxCol(dk.winBg, 28/255, 28/255, 30/255, 0.01, "dark.winBg (#1C1C1E)")
	approxCol(dk.cardBg, 44/255, 44/255, 46/255, 0.01, "dark.cardBg (#2C2C2E)")
	approxCol(dk.sidebarBg, 0.133, 0.137, 0.160, 0.02, "dark.sidebarBg")
	approxCol(dk.text, 1, 1, 1, 0.01, "dark.text (#FFFFFF)")
	approxCol(dk.accentBlue, 0, 145/255, 1, 0.01, "dark.accentBlue (rgb(0,145,255))")
	approxCol(dk.accentGreen, 48/255, 209/255, 88/255, 0.01, "dark.accentGreen (rgb(48,209,88))")
	approxCol(dk.accentOrange, 1, 146/255, 48/255, 0.01, "dark.accentOrange (rgb(255,146,48))")

	local lt = Theme.PALETTES.light
	approxCol(lt.winBg, 242/255, 242/255, 247/255, 0.01, "light.winBg (#F2F2F7)")
	approxCol(lt.cardBg, 1, 1, 1, 0.01, "light.cardBg (#FFFFFF)")
	approxCol(lt.sidebarBg, 0.950, 0.952, 0.968, 0.02, "light.sidebarBg")
	approxCol(lt.text, 0, 0, 0, 0.01, "light.text (#000000)")
	approxCol(lt.accentBlue, 0, 136/255, 1, 0.01, "light.accentBlue (rgb(0,136,255))")
	approxCol(lt.accentGreen, 0, 122/255, 43/255, 0.01, "light.accentGreen (#007A2B)")
	approxCol(lt.accentOrange, 179/255, 74/255, 0, 0.01, "light.accentOrange (#B34A00)")
end

-- 3B. GetMode / SetMode / ToggleMode / OnModeChanged
do
	local events = {}
	local unsub = Theme.OnModeChanged(function(mode, pal)
		events[#events + 1] = { mode = mode, pal = pal }
	end)

	Theme.SetMode("dark", true)
	local countBefore = #events
	check(Theme.GetMode() == "dark", "GetMode returns dark")
	approxCol(Theme.COLORS.winBg, Theme.PALETTES.dark.winBg[1], Theme.PALETTES.dark.winBg[2], Theme.PALETTES.dark.winBg[3], 0.002, "Theme.COLORS synced to dark")

	local m1 = Theme.SetMode("light")
	check(m1 == "light" and Theme.GetMode() == "light", "SetMode('light') switches to light")
	check(#events == countBefore + 1 and events[#events].mode == "light" and events[#events].pal == Theme.PALETTES.light,
		"OnModeChanged fired on SetMode('light')")
	approxCol(Theme.COLORS.cardBg, 1, 1, 1, 0.002, "Theme.COLORS.cardBg updated to light #FFFFFF")
	approxCol(Theme.COLORS.text, 0, 0, 0, 0.002, "Theme.COLORS.text updated to light #000000")

	local m2 = Theme.ToggleMode()
	check(m2 == "dark" and Theme.GetMode() == "dark", "ToggleMode switches light -> dark")
	check(#events == countBefore + 2 and events[#events].mode == "dark", "OnModeChanged fired on ToggleMode")

	Theme.SetMode("light", true)
	check(Theme.GetMode() == "light" and #events == countBefore + 2, "SetMode(..., true) suppresses OnModeChanged")
	check(Theme.PALETTE == Theme.PALETTES.light or (Theme.PALETTE and Theme.PALETTE.mode == "light"), "Theme.PALETTE aliases active light palette")
	Theme.SetMode("dark", true)
	check(Theme.PALETTE == Theme.PALETTES.dark or (Theme.PALETTE and Theme.PALETTE.mode == "dark"), "Theme.PALETTE aliases active dark palette")
	if type(unsub) == "function" then unsub() end

	-- Verify colon-call safety on Fable widget methods
	local badge = Theme.CreateBadgePill(app.panel, "init", "neutral")
	badge:SetVariant("positive", "4 items")
	check(badge.label:GetText() == "4 items", "CreateBadgePill:SetVariant colon call preserves text, got " .. tostring(badge.label:GetText()))
	badge.SetVariant("blue", "12s/tok")
	check(badge.label:GetText() == "12s/tok", "CreateBadgePill.SetVariant dot call preserves text, got " .. tostring(badge.label:GetText()))
	if Theme.CreateProgressBar then
		local meter = Theme.CreateProgressBar(app.panel, 6)
		check(meter.frame and math.floor((meter.frame:GetHeight() or 0) + 0.5) == 6, "CreateProgressBar height is 6px")
		meter:SetValue(0.5)
	end

	-- Verify NineApple UpdateTheme(newFill, newStroke) works when initial colors were tables
	local box = CreateFrame("Frame", nil, app.panel)
	local surf = Theme.NineApple(box, "glass_r10", Theme.PALETTES.dark.cardBg, Theme.PALETTES.dark.border)
	local fillColSeen, strokeColSeen
	local origSetFill, origSetStroke = surf.fill.SetColor, surf.stroke.SetColor
	surf.fill.SetColor = function(self, r, g, b, a) fillColSeen = type(r) == "table" and r or { r, g, b, a }; return origSetFill(self, r, g, b, a) end
	surf.stroke.SetColor = function(self, r, g, b, a) strokeColSeen = type(r) == "table" and r or { r, g, b, a }; return origSetStroke(self, r, g, b, a) end
	surf:UpdateTheme(Theme.PALETTES.light.cardBg, Theme.PALETTES.light.border)
	approxCol(fillColSeen, 1, 1, 1, 0.002, "NineApple:UpdateTheme(newFill, newStroke) applies light cardBg")
	approxCol(strokeColSeen, 0, 0, 0, 0.005, "NineApple:UpdateTheme(newFill, newStroke) applies light border")

	-- Verify seamless split-pane NineApple (openRight / openLeft) & borderless defaults
	check(type(Theme.ASSETS.glass_r22_openright_fill) == "string" and not Theme.ASSETS.glass_r22_openright_fill:match("%.tga$"),
		"Theme.ASSETS.glass_r22_openright_fill is extensionless")
	check(type(Theme.ASSETS.glass_r22_openleft_fill) == "string" and not Theme.ASSETS.glass_r22_openleft_fill:match("%.tga$"),
		"Theme.ASSETS.glass_r22_openleft_fill is extensionless")
	local splitL = Theme.NineApple(box, "glass_r22", "sidebarBg", false, { openRight = true, noSpecular = true })
	local splitR = Theme.NineApple(box, "glass_r22", "winBg", false, { openLeft = true, noSpecular = true })
	check(splitL.fill ~= nil and splitL.stroke == nil, "NineApple openRight borderless surface created")
	check(splitR.fill ~= nil and splitR.stroke == nil, "NineApple openLeft borderless surface created")

	-- Verify CreateTexture subLevel enforcement across window chrome and Theme.ApplyFont / SetFont safety
	for _, piece in ipairs(app.ui.winChrome.outerShadow.pieces or {}) do
		local s = piece._subLevel
		check(s == nil or (type(s) == "number" and s >= -8 and s <= 7), "outerShadow subLevel in [-8,7], got " .. tostring(s))
	end
	for _, piece in ipairs(app.ui.winChrome.outerGlass.fill.pieces or {}) do
		local s = piece._subLevel
		check(s == nil or (type(s) == "number" and s >= -8 and s <= 7), "outerGlass.fill subLevel in [-8,7], got " .. tostring(s))
	end
	if app.ui.winChrome.outerGlass.stroke then
		for _, piece in ipairs(app.ui.winChrome.outerGlass.stroke.pieces or {}) do
			local s = piece._subLevel
			check(s == nil or (type(s) == "number" and s >= -8 and s <= 7), "outerGlass.stroke subLevel in [-8,7], got " .. tostring(s))
		end
	end

	local function makeSpyFs(failMode)
		local spy = {
			_path = "Fonts\\FRIZQT__.TTF",
			_size = 12,
			_flags = "",
			_shadowX = 1,
			_shadowY = -1,
			_shadowA = 1,
			_calls = {},
		}
		function spy:GetFont() return self._path, self._size, self._flags end
		function spy:SetFont(p, sz, fl)
			self._calls[#self._calls + 1] = p
			if failMode == "false" and tostring(p):find("Assets\\fonts\\Inter%-") then
				return false
			end
			if failMode == "nil" and tostring(p):find("Assets\\fonts\\Inter%-") then
				return nil
			end
			self._path, self._size, self._flags = p, sz, fl or ""
			return true
		end
		function spy:SetShadowOffset(x, y) self._shadowX, self._shadowY = x, y end
		function spy:SetShadowColor(r, g, b, a) self._shadowR, self._shadowG, self._shadowB, self._shadowA = r, g, b, a end
		return spy
	end

	check(type(Theme.ApplyFont) == "function" and type(Theme.FONTS) == "table", "Theme.ApplyFont and Theme.FONTS exported")
	local spyOk = makeSpyFs("ok")
	Theme.ApplyFont(spyOk, 16, "semibold", "SEMIBOLD")
	local sp1, ss1, sf1 = spyOk:GetFont()
	check(sp1 == Theme.FONTS.semibold and ss1 == 16 and sf1 == "", "Theme.ApplyFont applies font_semibold and clamps invalid flags")
	check(spyOk._shadowX == 0 and spyOk._shadowY == 0 and spyOk._shadowA == 0, "Theme.ApplyFont clears FontString drop shadow")

	spyOk._shadowX, spyOk._shadowY = 2, -2
	Theme.SetFont(spyOk, 14, "SEMIBOLD")
	local sp2, ss2, sf2 = spyOk:GetFont()
	check(sp2 == Theme.FONTS.regular and ss2 == 14 and sf2 == "", "Theme.SetFont delegates to ApplyFont regular and clamps flags")
	check(spyOk._shadowX == 0 and spyOk._shadowY == 0, "Theme.SetFont clears FontString drop shadow")

	local spyFailFalse = makeSpyFs("false")
	Theme.ApplyFont(spyFailFalse, 15, "semibold", "OUTLINE")
	local fpFail, fsFail, flFail = spyFailFalse:GetFont()
	check(fpFail == "Fonts\\ARIALN.TTF" and fsFail == 15 and flFail == "OUTLINE",
		"Theme.ApplyFont falls back to Fonts\\ARIALN.TTF when SetFont returns false")
	check(spyFailFalse._shadowX == 0 and spyFailFalse._shadowY == 0, "Theme.ApplyFont clears shadow after false fallback")

	local spyFailNil = makeSpyFs("nil")
	Theme.SetFont(spyFailNil, 13, "")
	local fpNil, fsNil, flNil = spyFailNil:GetFont()
	check(fpNil == "Fonts\\ARIALN.TTF" and fsNil == 13 and flNil == "",
		"Theme.SetFont falls back to Fonts\\ARIALN.TTF when SetFont leaves old font")
	check(spyFailNil._shadowX == 0 and spyFailNil._shadowY == 0, "Theme.SetFont clears shadow after nil fallback")

	local fsTest = app.panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	Theme.SetFont(fsTest, 14, "SEMIBOLD")
	local fp, fsz, ffl = fsTest:GetFont()
	check(fp == Theme.FONTS.regular and fsz == 14 and ffl == "", "Theme.SetFont clamps invalid flags cleanly on host FontString")
end

-- 3C. Golden g / Silver s / Copper c in Theme.FormatMoneyParts and ns.FormatMoneyCompact (Dark + Light)
do
	local function has(text, needle) return type(text) == "string" and text:find(needle, 1, true) ~= nil end

	Theme.SetMode("dark", true)
	local dk = Theme.PALETTES.dark
	check(dk.hexGold == "ffd60a" and dk.hexSilver == "c7c7cc" and dk.hexCopper == "e08a5e", "Dark palette g/s/c hex tokens")
	local p = Theme.FormatMoneyParts(123456)
	check(p.g == 12 and p.s == 34 and p.c == 56, "FormatMoneyParts splits 12g 34s 56c")
	check(has(p.text, "|cffffd60ag|r"), "Dark mode golden g (#FFD60A), got " .. p.text)
	check(has(p.text, "|cffc7c7ccs|r"), "Dark mode silver s (#C7C7CC), got " .. p.text)
	check(has(p.text, "|cffe08a5ec|r"), "Dark mode copper c (#E08A5E), got " .. p.text)
	check(has(p.text, "|cffffffff12|r") and has(p.text, "|cffffffff34|r") and has(p.text, "|cffffffff56|r"),
		"Dark mode keeps numerals bright white")
	local compact = ns.FormatMoneyCompact(123456)
	check(has(compact, "|cffffd60ag|r") and has(compact, "|cffc7c7ccs|r") and has(compact, "|cffe08a5ec|r"),
		"Dark ns.FormatMoneyCompact emits golden g / silver s / copper c, got " .. compact)
	check(not has(compact, "|T") and not has(compact, "+"), "ns.FormatMoneyCompact has no coin textures and no stray sign")
	check(ns.FormatMoneyCompact(nil) == "|cff98989d—|r", "Dark ns.FormatMoneyCompact(nil) is a muted dash")
	check(has(ns.FormatMoneyCompact(250, true), "|cff30d158+2|r"), "Signed positive compact money uses positive green numerals")
	check(has(ns.FormatMoneyCompact(-250, true), "|cffff4245-2|r"), "Signed negative compact money uses red numerals")
	check(has(ns.FormatMoneyCompact(-250), "|cff30d158-2|r"), "Unsigned negative cost (a gain) keeps its positive green ink")
	check(has(Theme.FormatMoneyParts(0).text, "|cffe08a5ec|r"), "Zero copper uses the copper c unit")

	Theme.SetMode("light", true)
	local lt = Theme.PALETTES.light
	check(lt.hexGold == "8a5a00" and lt.hexSilver == "5a606d" and lt.hexCopper == "9c4616", "Light palette g/s/c hex tokens")
	check(lt.hexMuted == "5e626a" and lt.hexSilver ~= lt.hexMuted, "Light silver s is a distinct hex from muted grey")
	local pLight = Theme.FormatMoneyParts(123456)
	check(has(pLight.text, "|cff8a5a00g|r"), "Light mode burnished gold g (#8A5A00), got " .. pLight.text)
	check(has(pLight.text, "|cff5a606ds|r"), "Light mode pewter silver s (#5A606D), got " .. pLight.text)
	check(has(pLight.text, "|cff9c4616c|r"), "Light mode deep copper c (#9C4616), got " .. pLight.text)
	check(has(pLight.text, "|cff00000012|r"), "Light mode keeps numerals dark #000000")
	local compactLight = ns.FormatMoneyCompact(123456)
	check(has(compactLight, "|cff8a5a00g|r") and has(compactLight, "|cff5a606ds|r") and has(compactLight, "|cff9c4616c|r"),
		"Light ns.FormatMoneyCompact emits golden g / silver s / copper c, got " .. compactLight)
	check(not has(compactLight, "|cffffffff") and not has(compactLight, "ffd60a"), "Light compact money carries no white / pale-yellow ink")
	check(ns.FormatMoneyCompact(nil) == "|cff5e626a—|r", "Light ns.FormatMoneyCompact(nil) is a muted dash")

	-- Always-dark GameTooltip: Light-palette ink is lifted back to the Dark palette, nothing else is touched
	local QUALITY_LINE = "|cff1eff00Uncommon Item|r |cff00ff00Use: Restores mana|r |cffffd100Quest Title|r |cffa335eeEpic Item|r"
	local LEGACY_LINE = "|cffffffffWhite|r |cffaaaaaaGrey|r |cffffd200Yellow|r"
	local lifted = Theme.TooltipText(compactLight)
	check(has(lifted, "|cffffffff12|r") and has(lifted, "|cffffd60ag|r") and has(lifted, "|cffc7c7ccs|r") and has(lifted, "|cffe08a5ec|r"),
		"Theme.TooltipText lifts light money ink to dark-palette ink, got " .. lifted)
	check(Theme.TooltipText(QUALITY_LINE) == QUALITY_LINE, "Theme.TooltipText leaves WoW quality / spell hexes untouched")

	local function makeTip(name, lines)
		local sets = {}
		for i, pair in ipairs(lines) do
			for side, text in pairs(pair) do
				local fs = { _text = text }
				function fs:GetText() return self._text end
				function fs:SetText(t) self._text = t; sets[#sets + 1] = { line = i, side = side, text = t } end
				_G[name .. side .. i] = fs
			end
		end
		return { GetName = function() return name end, NumLines = function() return #lines end }, sets
	end
	local function lineText(name, side, i) return _G[name .. side .. i]._text end

	local tip, sets = makeTip("MMLiftTip", {
		{ TextLeft = "Sell Price", TextRight = compactLight },
		{ TextLeft = QUALITY_LINE, TextRight = LEGACY_LINE },
		{ TextLeft = "|cff5e626a—|r" },
	})
	Theme.LiftTooltip(tip)
	local money = lineText("MMLiftTip", "TextRight", 1)
	check(money == "|cffffffff12|r|cffffd60ag|r |cffffffff34|r|cffc7c7ccs|r |cffffffff56|r|cffe08a5ec|r",
		"LiftTooltip restores 12g 34s 56c to #ffffff / #ffd60a / #c7c7cc / #e08a5e, got " .. money)
	check(lineText("MMLiftTip", "TextLeft", 3) == "|cff98989d—|r" and not has(money, "98989d"),
		"LiftTooltip keeps silver (#5a606d -> #c7c7cc) distinct from muted grey (#5e626a -> #98989d)")
	check(lineText("MMLiftTip", "TextLeft", 2) == QUALITY_LINE,
		"LiftTooltip leaves |cff1eff00 / |cff00ff00 / |cffffd100 / |cffa335ee untouched, got " .. lineText("MMLiftTip", "TextLeft", 2))
	check(lineText("MMLiftTip", "TextRight", 2) == LEGACY_LINE, "LiftTooltip leaves legacy white / grey / yellow literals untouched")
	check(#sets == 2, "LiftTooltip only rewrites the two lines that carried Light-palette ink, rewrote " .. #sets)

	-- Secret values: skipped before any truth test, type test, comparison or indexing
	local savedIsSecret = _G.issecretvalue
	local secretTable = setmetatable({}, {
		__index = function() error("indexed a secret value") end,
		__eq = function() error("compared a secret value") end,
	})
	local secretString = "|cff000000secret|r"
	local probed = 0
	_G.issecretvalue = function(v)
		probed = probed + 1
		return rawequal(v, secretTable) or rawequal(v, secretString)
	end
	local secretTip, secretSets = makeTip("MMSecretTip", {
		{ TextLeft = secretTable, TextRight = secretString },
		{ TextLeft = compactLight },
	})
	local okSecret, errSecret = pcall(Theme.LiftTooltip, secretTip)
	_G.issecretvalue = savedIsSecret
	check(okSecret, "LiftTooltip survives secret tooltip lines, got " .. tostring(errSecret))
	check(probed == 3, "LiftTooltip probes issecretvalue on every line it reads, probed " .. probed)
	check(rawequal(_G.MMSecretTipTextLeft1._text, secretTable) and lineText("MMSecretTip", "TextRight", 1) == secretString,
		"LiftTooltip never rewrites a secret line (even one that carries Light-palette ink)")
	check(#secretSets == 1 and secretSets[1].line == 2 and has(secretSets[1].text, "|cffffd60ag|r"),
		"LiftTooltip still lifts the readable line next to a secret one")

	-- Dark appearance: tooltips are left alone entirely
	Theme.SetMode("dark", true)
	local darkTip, darkSets = makeTip("MMDarkTip", { { TextLeft = compactLight } })
	Theme.LiftTooltip(darkTip)
	check(#darkSets == 0, "LiftTooltip is a no-op in Dark Mode")
	for _, name in ipairs({ "MMLiftTip", "MMSecretTip", "MMDarkTip" }) do
		for i = 1, 3 do
			_G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i] = nil, nil
		end
	end

	-- "strong" pill: Light pillThumb is white-on-white, so the capsule switches to neutral 8.5% ink
	local strongPill = Theme.CreateBadgePill(app.panel, "0 listed", "strong")
	local fillSeen
	local origPillColor = strongPill.bg.SetColor
	strongPill.bg.SetColor = function(self, r, g, b, a) fillSeen = { r, g, b, a }; return origPillColor(self, r, g, b, a) end
	Theme.SetMode("light", true)
	strongPill:SetVariant("strong", "0 listed")
	check(fillSeen and fillSeen[1] == 0 and fillSeen[2] == 0 and fillSeen[3] == 0 and math.abs(fillSeen[4] - 0.085) < 1e-6,
		"Light 'strong' pill fill is rgba(0,0,0,0.085), not white pillThumb")
	Theme.SetMode("dark", true)
	strongPill:SetVariant("strong", "0 listed")
	local thumb = Theme.PALETTES.dark.pillThumb
	check(fillSeen[1] == thumb[1] and fillSeen[2] == thumb[2] and fillSeen[3] == thumb[3] and fillSeen[4] == thumb[4],
		"Dark 'strong' pill keeps the pillThumb fill")
end

-- 3D. Window default geometry (1840x730, MIN_W=1320, MIN_H=730 preserved)
do
	MerchantMasterDB.window = {}
	app.panel:Show()
	app.setTab("dashboard")
	app.refresh()
	check(app.panel:GetWidth() == 1840, "Default main window width is 1840, got " .. tostring(app.panel:GetWidth()))
	check(app.panel:GetHeight() == 730, "Default main window height is 730 (MIN_H=730 preserved), got " .. tostring(app.panel:GetHeight()))
	check(app.ui.winChrome and app.ui.winChrome.window, "winChrome.window controller attached")
	app.ui.winChrome.window:SetSize(800, 400)
	check(app.panel:GetWidth() == 1320 and app.panel:GetHeight() == 730, "Minimum window clamp enforces 1320x730")
	MerchantMasterDB.window.width, MerchantMasterDB.window.height = 1840, 730
	app.ui.winChrome.window:ApplyFull()
end

-- 3E. Fable 5.2 Design 1 Shell & Overview Geometry
do
	local ui = app.ui
	check(ui.sidebar ~= nil, "Fable sidebar frame exposed on app.ui.sidebar")
	check(math.floor((ui.sidebar:GetWidth() or 0) + 0.5) == 216, "Sidebar width is 216px, got " .. tostring(ui.sidebar and ui.sidebar:GetWidth()))

	-- 6 section headers: OVERVIEW, MARKET, TURN-INS, PROGRESS & LEDGER, SNIPER, SYSTEM
	local expectedHeaders = { "OVERVIEW", "MARKET", "TURN-INS", "PROGRESS & LEDGER", "SNIPER", "SYSTEM" }
	check(type(ui.sidebarSections) == "table" and #ui.sidebarSections == 6,
		"Sidebar exposes 6 section headers, got " .. tostring(ui.sidebarSections and #ui.sidebarSections))
	for i, exp in ipairs(expectedHeaders) do
		local sec = ui.sidebarSections[i]
		local txt = sec and (sec.GetText and sec:GetText() or (sec.hdr and sec.hdr:GetText())) or ""
		check(txt == exp, string.format("Sidebar section %d expected '%s', got '%s'", i, exp, tostring(txt)))
	end

	-- 17 nav items including Watchlist in OVERVIEW, All Items, Vendor Crafter & Disenchantment Crafter in MARKET, Forged Delivery in TURN-INS, Snipers in SNIPER, and Console in SYSTEM.
	check(type(ui.navOrder) == "table" and #ui.navOrder == 17,
		"Sidebar exposes 17 nav items, got " .. tostring(ui.navOrder and #ui.navOrder))
	check(ui.navBtns.auction_house == nil, "Standalone Auction House nav button has been removed")
	local wlBtn = ui.navBtns.watchlist
	check(wlBtn and wlBtn.key == "watchlist" and wlBtn.targetTab == "watchlist"
		and wlBtn.labelFs:GetText() == "Watchlist",
		"Watchlist has a sidebar button routed to the watchlist tab")
	local aiBtn = ui.navBtns.all_items
	check(aiBtn and aiBtn.key == "all_items" and aiBtn.targetTab == "all_items"
		and aiBtn.labelFs:GetText() == "All Items",
		"All Items has a sidebar button routed to the all_items tab")
	local vcBtn = ui.navBtns.vendor_crafter
	check(vcBtn and vcBtn.key == "vendor_crafter" and vcBtn.targetTab == "vendor_crafter"
		and vcBtn.labelFs:GetText() == "Vendor Crafter",
		"Vendor Crafter has a sidebar button routed to the vendor_crafter tab")
	local dcBtn = ui.navBtns.disenchant_crafter
	check(dcBtn and dcBtn.key == "disenchant_crafter" and dcBtn.targetTab == "disenchant_crafter"
		and dcBtn.labelFs:GetText() == "Disenchantment Crafter",
		"Disenchantment Crafter has a sidebar button routed to the disenchant_crafter tab")
	local forgedBtn = ui.navBtns.forged
	check(forgedBtn and forgedBtn.key == "forged" and forgedBtn.targetTab == "forged"
		and forgedBtn.labelFs:GetText() == "Forged delivery (rep)",
		"Forged Delivery has a sidebar button routed to the forged tab")
	local consoleBtn = ui.navBtns.console
	check(consoleBtn and consoleBtn.key == "console" and consoleBtn.targetTab == "console_overview"
		and consoleBtn.labelFs:GetText() == "Console",
		"Console has a sidebar button routed to the console_overview tab")
	local positions = {}
	for i, btn in ipairs(ui.navOrder) do positions[btn.key] = i end
	check(positions.all_items and positions.vendor_crafter and positions.disenchant_crafter and positions.recipes and positions.crates
		and positions.recipes < positions.all_items
		and positions.all_items == positions.recipes + 1
		and positions.vendor_crafter == positions.all_items + 1
		and positions.disenchant_crafter == positions.vendor_crafter + 1
		and positions.disenchant_crafter < positions.crates,
		"All Items sits immediately after All Recipes and before Vendor Crafter & Disenchantment Crafter inside MARKET")
	check(positions.forged and positions.crates < positions.writs and positions.writs < positions.forged
		and positions.forged < positions.reputation, "Forged Delivery sits between Writs and Standing in TURN-INS")
	check(positions.auction_house == nil and positions.sniper_gap and positions.sniper_vendor
		and positions.sniper_gap < positions.sniper_vendor
		and positions.sniper_vendor < positions.console,
		"Gap Sniper precedes Vendor Sniper in SNIPER, followed by Console in SYSTEM")

	-- The host fixture records anchors without solving the sidebar's stretched height.
	local sidebarHeight = ui.sidebar:GetHeight()
	local top, bottom = unpack(ui.sidebar._points)
	if top and bottom and top[2] == app.panel and bottom[2] == app.panel
		and top[3] == "TOPLEFT" and bottom[3] == "BOTTOMLEFT" then
		sidebarHeight = app.panel:GetHeight() + top[5] - bottom[5]
	end
	local lastNav = ui.navOrder[#ui.navOrder]
	local navBottomY = lastNav._points[1][5] - lastNav:GetHeight()
	local walletTopY = -(sidebarHeight - 12 - ui.walletCard:GetHeight())
	check(app.panel:GetHeight() == 730 and navBottomY > walletTopY,
		string.format("The 17th nav item clears the wallet card at 730px min height (navBottomY=%s > walletTopY=%s)",
			tostring(navBottomY), tostring(walletTopY)))

	local priorTab, priorSavedTab = app.activeTab, MerchantMasterDB.activeTab
	local ok, failure = pcall(function()
		local function checkNoFlatHighlight(frame, label)
			for _, region in ipairs({ frame:GetRegions() }) do
				local anchor = region._points and region._points[1]
				local shown = (region.IsShown == nil) or region:IsShown()
				check(not (shown and region._colorTexture and region:GetHeight() == 1 and anchor and anchor[1]:match("^TOP")),
					label .. " has no flat 1px top highlight")
			end
		end
		wlBtn:Click("LeftButton")
		check(app.activeTab == "watchlist" and ui.watchlistView and ui.watchlistView:IsShown(),
			"Clicking Watchlist switches to its visible view")
		checkNoFlatHighlight(ui.watchlistView, "Watchlist view")

		aiBtn:Click("LeftButton")
		check(app.activeTab == "all_items" and ui.allItemsView and ui.allItemsView:IsShown(),
			"Clicking All Items switches to its visible view")
		checkNoFlatHighlight(ui.allItemsView, "All Items view")

		vcBtn:Click("LeftButton")
		check(app.activeTab == "vendor_crafter" and ui.vendorCrafterView and ui.vendorCrafterView:IsShown(),
			"Clicking Vendor Crafter switches to its visible view")
		checkNoFlatHighlight(ui.vendorCrafterView, "Vendor Crafter view")

		dcBtn:Click("LeftButton")
		check(app.activeTab == "disenchant_crafter" and ui.disenchantCrafterView and ui.disenchantCrafterView:IsShown(),
			"Clicking Disenchantment Crafter switches to its visible view")
		checkNoFlatHighlight(ui.disenchantCrafterView, "Disenchantment Crafter view")

		forgedBtn:Click("LeftButton")
		check(app.activeTab == "forged" and ui.forgedView and ui.forgedView:IsShown(),
			"Clicking Forged Delivery switches to its visible view")
		check(type(ui.forgedKpis) == "table" and #ui.forgedKpis == 3, "Forged Delivery exposes 3 KPI cards")
		checkNoFlatHighlight(ui.forgedView, "Forged view")
		for i, kpi in ipairs(ui.forgedKpis) do
			check(kpi.surface and kpi.surface.stroke == nil, "Forged KPI card " .. i .. " is borderless")
			checkNoFlatHighlight(kpi.frame, "Forged KPI card " .. i)
		end

		for _, legacyAH in ipairs({ "auction_house", "ah_sell", "ah_auctions" }) do
			app.setTab(legacyAH)
			check(app.activeTab == "dashboard" and ui.dashboardView and ui.dashboardView:IsShown(),
				"Legacy tab '" .. legacyAH .. "' routes cleanly to dashboard")
		end

		consoleBtn:Click("LeftButton")
		check(app.activeTab == "console_overview" and ui.consoleView and ui.consoleView:IsShown(),
			"Clicking Console opens app.ui.consoleView on console_overview")
		checkNoFlatHighlight(ui.consoleView, "Console view")
		app.setTab("console_settings")
		check(app.activeTab == "console_settings" and ui.consoleView and ui.consoleView:IsShown(),
			"Switching to console_settings keeps app.ui.consoleView visible")
	end)
	app.setTab(priorTab)
	MerchantMasterDB.activeTab = priorSavedTab
	if not ok then error(failure, 0) end

	-- 48px toolbar + 84x48 Sun/Moon appearance switch
	check(ui.toolbar ~= nil, "Fable floating toolbar exposed on app.ui.toolbar")
	check(math.floor((ui.toolbar:GetHeight() or 0) + 0.5) == 48, "Toolbar height is 48px, got " .. tostring(ui.toolbar and ui.toolbar:GetHeight()))

	local sw = ui.appearanceSwitch
	check(sw ~= nil and sw.frame ~= nil and sw.sunBtn ~= nil and sw.moonBtn ~= nil and sw.thumb ~= nil,
		"Appearance switch exposed with frame, sunBtn, moonBtn, thumb")
	check(math.floor((sw.frame:GetWidth() or 0) + 0.5) == 84 and math.floor((sw.frame:GetHeight() or 0) + 0.5) == 48,
		string.format("Appearance switch is 84x48, got %sx%s", tostring(sw.frame:GetWidth()), tostring(sw.frame:GetHeight())))

	sw.sunBtn:Click("LeftButton")
	check(Theme.GetMode() == "light", "Clicking Sun button switches to light mode")
	sw.moonBtn:Click("LeftButton")
	check(Theme.GetMode() == "dark", "Clicking Moon button switches to dark mode")

	-- 104px borderless KPI cards
	check(type(ui.dashKpis) == "table" and #ui.dashKpis == 3,
		"Overview exposes 3 KPI cards, got " .. tostring(ui.dashKpis and #ui.dashKpis))
	for i, kpi in ipairs(ui.dashKpis) do
		check(kpi.frame and math.floor((kpi.frame:GetHeight() or 0) + 0.5) == 104,
			"Overview KPI card " .. i .. " height is 104px")
		check(kpi.surface ~= nil and kpi.surface.stroke == nil,
			"Overview KPI card " .. i .. " defaults borderless (stroke == nil)")
	end
	local extraKpi = Theme.CreateKpiCard(app.panel, { title = "Sample", value = "10g" })
	check(extraKpi.surface ~= nil and extraKpi.surface.stroke == nil,
		"Theme.CreateKpiCard defaults borderless (stroke == nil)")

	-- Row 2 Bento headers: Title Case by default vs KNOWN CRAFTS / BEST KNOWN OPTIONS when enabled
	MerchantMasterDB.knownRecipesOnly = false
	MerchantMasterDB.dashboardScope = "smart"
	app.setTab("dashboard")
	app.refresh()
	check(ui.dashLeftHdrFs and ui.dashLeftHdrFs:GetText() == "Daily Velocity Crafts",
		"Row 2 left Bento header uses Title Case 'Daily Velocity Crafts' when knownRecipesOnly == false, got " .. tostring(ui.dashLeftHdrFs and ui.dashLeftHdrFs:GetText()))
	check(ui.dashRightHdrFs and ui.dashRightHdrFs:GetText() == "Monopoly Opportunities",
		"Row 2 right Bento header uses Title Case 'Monopoly Opportunities' when knownRecipesOnly == false, got " .. tostring(ui.dashRightHdrFs and ui.dashRightHdrFs:GetText()))

	do
		local prevKnownSpells = app.char.knownSpells
		local prevAHPool = MerchantMasterDB.ahPrices and MerchantMasterDB.ahPrices["Normal-Horde"]
		local prevPriceSource = MerchantMasterDB.priceSource
		local mockKnownSpells = {}
		local mockPool = { _scannedAt = time() }
		local seededKnown = 0
		for _, r in ipairs(ns.RECIPES) do
			local outID = r.outputItemID or r.itemID
			if r.prof == "leatherworking" and r.spellID and outID and ns.IsItemSellable(outID) and r.reagents and #r.reagents > 0 then
				seededKnown = seededKnown + 1
				mockKnownSpells[r.spellID] = true
				mockPool[outID] = { price = 15000 + seededKnown * 500, qty = 15 + seededKnown, absent = false, at = time() }
				for _, rg in ipairs(r.reagents) do
					local rgID = rg.itemID or rg[1]
					if rgID then mockPool[rgID] = { price = 100, qty = 500, absent = false, at = time() } end
				end
				if seededKnown >= 12 then break end
			end
		end
		check(seededKnown >= 12, "Seeded >=12 known Leatherworking recipes for header fallback check")
		app.char.knownSpells = mockKnownSpells
		MerchantMasterDB.ahPrices["Normal-Horde"] = mockPool
		MerchantMasterDB.priceSource = "live"
		ns.InvalidatePriceCache()
		MerchantMasterDB.knownRecipesOnly = true
		app.setTab("dashboard")
		app.refresh()
		check(ui.dashLeftHdrFs and ui.dashLeftHdrFs:GetText():find("KNOWN CRAFTS", 1, true) ~= nil,
			"Row 2 left Bento header preserves 'KNOWN CRAFTS' when knownRecipesOnly == true, got " .. tostring(ui.dashLeftHdrFs and ui.dashLeftHdrFs:GetText()))
		check(ui.dashRightHdrFs and ui.dashRightHdrFs:GetText():find("BEST KNOWN OPTIONS", 1, true) ~= nil,
			"Row 2 right Bento header preserves 'BEST KNOWN OPTIONS' on fallback, got " .. tostring(ui.dashRightHdrFs and ui.dashRightHdrFs:GetText()))

		MerchantMasterDB.knownRecipesOnly = false
		MerchantMasterDB.priceSource = prevPriceSource
		app.char.knownSpells = prevKnownSpells
		MerchantMasterDB.ahPrices["Normal-Horde"] = prevAHPool
		ns.InvalidatePriceCache()
		app.setTab("dashboard")
		app.refresh()
		check(ui.dashLeftHdrFs:GetText() == "Daily Velocity Crafts" and ui.dashRightHdrFs:GetText() == "Monopoly Opportunities",
			"Row 2 Bento headers restore Title Case after leaving knownRecipesOnly mode")
	end

	-- 36px toast frame
	check(ui.toast ~= nil and ui.toast.frame ~= nil, "Toast widget exposed on app.ui.toast")
	check(math.floor((ui.toast.frame:GetHeight() or 0) + 0.5) == 36,
		"Toast frame height is 36px, got " .. tostring(ui.toast.frame:GetHeight()))
end

---------------------------------------------------------------------------------------------------
-- 3F. Status capsule: complete economy label, zero overlap, live AH scan "working" state
--     (indeterminate shuttle for browse scans, determinate fill for lot scans, jitter-free width)
---------------------------------------------------------------------------------------------------
do
	local ui = app.ui
	local chrome = ui.winChrome
	local rb = chrome.ahRefresh.button
	local icon = chrome.ahRefresh.icon
	local function near(col, ref) return type(col) == "table" and math.abs(col[1] - ref[1]) < 0.01 and math.abs(col[2] - ref[2]) < 0.01 and math.abs(col[3] - ref[3]) < 0.01 end
	local function fits()
		local need = 12 + 6 + 7 + ui.statusEconFs:GetStringWidth() + 8 + 1 + 8 + ui.statusSyncFs:GetStringWidth() + 32
		return ui.statusCapsule:GetWidth() >= need, need
	end
	local bar, fill = ui.statusScanBar, ui.statusScanFill
	local function fillLeft()
		local pt = fill._points and fill._points[1]
		check(#fill._points == 1 and pt[1] == "LEFT" and pt[2] == bar and pt[3] == "LEFT" and pt[5] == 0,
			"Scan fill is positioned by a single LEFT, scanBar, LEFT, offset, 0 anchor")
		return pt[4]
	end

	Theme.SetMode("dark", true)
	local savedToolbarW = ui.toolbar:GetWidth()
	ui.toolbar:SetWidth(1080) -- real toolbar width at the 1320px window: the 440px capsule cap applies
	local prevEconomy = MerchantMasterDB.economy
	MerchantMasterDB.economy = "auto"
	ns.InvalidatePriceCache()
	app.panel:Show()
	app.setTab("dashboard")
	app.refresh()

	check(ui.statusEconFs:GetText() == "Auto · Normal · Horde",
		"Auto economy label is the complete middle-dot string, got '" .. tostring(ui.statusEconFs:GetText()) .. "'")
	check(not ui.statusEconFs:GetText():find("(", 1, true), "Economy label has no dangling parenthesis")
	local okIdle, needIdle = fits()
	check(okIdle, string.format("Idle capsule (%s) fits econ + sync + 32px refresh margin (%s)", tostring(ui.statusCapsule:GetWidth()), tostring(needIdle)))
	check(icon ~= nil and type(icon.SetRotation) == "function", "AH refresh controller exposes its icon")
	local rbPoint = rb._points and rb._points[#rb._points]
	check(rbPoint and rbPoint[1] == "RIGHT" and rbPoint[2] == ui.statusCapsule and rbPoint[3] == "RIGHT" and rbPoint[4] == -5,
		"24x24 refresh button is anchored RIGHT, statusCapsule, RIGHT, -5, 0")
	local clamped = false
	for _, pt in ipairs(ui.statusSyncFs._points or {}) do
		if pt[1] == "RIGHT" and pt[2] == ui.statusCapsule and (pt[4] or 0) <= -(24 + 5) then clamped = true end
	end
	check(clamped, "Sync label has a hard right clearance in front of the refresh button")
	check(ui.statusScanBar ~= nil and not ui.statusScanBar:IsShown(), "Scan progress strip is hidden while idle")
	check(not rb.scanning and (icon._rotation or 0) == 0, "Refresh icon rests unrotated while idle")

	-- Start a real browse scan through the public API
	local economyKey = ns.DetectActiveEconomy()
	local savedPool = MerchantMasterDB.ahPrices[economyKey]
	local scratchPool = {}
	for k, v in pairs(savedPool or {}) do scratchPool[k] = v end
	MerchantMasterDB.ahPrices[economyKey] = scratchPool
	local savedFull, savedMore = C_AuctionHouse.HasFullBrowseResults, C_AuctionHouse.RequestMoreBrowseResults
	local toasts = {}
	local savedToast = ui.toast.ShowToast
	ui.toast.ShowToast = function(msg, variant, duration)
		toasts[#toasts + 1] = { msg = msg, variant = variant, duration = duration }
		return savedToast(msg, variant, duration)
	end
	AuctionHouseFrame:Show()
	C_AuctionHouse.HasFullBrowseResults = function() return false end
	C_AuctionHouse.RequestMoreBrowseResults = function() end
	MerchantMasterAPI.RefreshMarket()

	check(MerchantMasterAPI.IsScanning(), "Refresh at an open AH starts a live scan")
	check(toasts[1] and toasts[1].msg == "Scanning Live Auction House..." and toasts[1].variant == "info",
		"Scan start fires the info toast")
	check(ui.statusSyncFs:GetText() == "Scanning AH…", "Sync label flips to 'Scanning AH…' before the first page, got " .. tostring(ui.statusSyncFs:GetText()))
	check(bar:IsShown() and bar.indeterminate == true and bar.fraction == nil,
		"Browse scan (unknown page total) shows an indeterminate shuttle, not a fake progress fraction")
	local lockedW = ui.statusCapsule:GetWidth()
	local trackW = lockedW - 28
	local shuttleW = math.floor(trackW * 0.28)
	check(fill:GetWidth() == shuttleW and bar.shuttlePos == 0 and fillLeft() == 0,
		"Shuttle is a 28% capsule resting at the left end before the first frame, width " .. tostring(fill:GetWidth()))
	local probeFs = app.panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	probeFs:SetText("Scanning p.999 · 999 items")
	check(lockedW >= 12 + 6 + 7 + ui.statusEconFs:GetStringWidth() + 8 + 1 + 8 + probeFs:GetStringWidth() + 12 + 24 + 5,
		"Capsule reserves room for 'Scanning p.999 · 999 items' at scan start, got " .. tostring(lockedW))
	check(near(ui.statusDot._vertexColor, Theme.PALETTES.dark.accentBlue), "Status dot tints Apple Blue while scanning")
	check(rb.scanning == true and near(icon._vertexColor, Theme.PALETTES.dark.accentBlue), "Refresh icon tints Apple Blue while scanning")

	for page = 1, 3 do
		ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {
			{ itemKey = { itemID = 2447 }, totalQuantity = 7, minPrice = 111 },
			{ itemKey = { itemID = 990000 + page }, totalQuantity = 1, minPrice = 5 },
		})
		check(ui.statusSyncFs:GetText():find("Scanning p." .. page, 1, true) ~= nil,
			"Sync label reports page " .. page .. ", got " .. tostring(ui.statusSyncFs:GetText()))
		check(ui.statusCapsule:GetWidth() == lockedW,
			string.format("Capsule width stays locked on page %d (%s vs %s): its left edge never jitters", page, tostring(ui.statusCapsule:GetWidth()), tostring(lockedW)))
		check(bar.indeterminate == true and bar.fraction == nil and bar.shuttlePos == 0 and fillLeft() == 0,
			"Incoming page " .. page .. " never moves the shuttle (only OnUpdate does)")
	end
	local scanState = ns.MarketScan.GetState()
	check(scanState.page == 3 and scanState.seen == 6 and scanState.matchedCount == 1, "MarketScan tracks pages, seen results and matched items")
	check(ui.statusSyncFs:GetText() == "Scanning p.3 · 1 items", "Sync label shows page + matched items, got " .. tostring(ui.statusSyncFs:GetText()))
	check(MerchantMasterAPI.GetScanStatus() == "Scanning page 3 · 1 items matched", "GetScanStatus reports page + matched items")
	local okScan, needScan = fits()
	check(okScan and ui.statusCapsule:GetWidth() >= 256,
		string.format("Scanning capsule (%s) grows past the old 256px clamp and fits its labels (%s)", tostring(ui.statusCapsule:GetWidth()), tostring(needScan)))

	rb:GetScript("OnUpdate")(rb, 0.15)
	check(type(icon._rotation) == "number" and icon._rotation ~= 0, "Refresh icon rotates on OnUpdate(0.15) while scanning")
	check(rb:GetScript("OnUpdate") ~= nil, "Freshness OnUpdate stays armed while the panel is shown")
	check(bar.shuttlePos > 0 and bar.shuttlePos < 1, "OnUpdate(0.15) advances the shuttle, shuttlePos " .. tostring(bar.shuttlePos))
	check(math.abs(fillLeft() - (trackW - shuttleW) * bar.shuttlePos) < 1e-9 and fill:GetWidth() == shuttleW,
		"Shuttle LEFT offset is (trackW - shuttleW) * shuttlePos")
	local minPos, maxPos = 1, 0
	for _ = 1, 40 do
		app.stepScanShuttle(0.1)
		minPos, maxPos = math.min(minPos, bar.shuttlePos), math.max(maxPos, bar.shuttlePos)
		local left = fillLeft()
		check(bar.shuttlePos >= 0 and bar.shuttlePos <= 1 and left >= 0 and left + shuttleW <= trackW + 1e-9,
			"Shuttle stays inside the track, offset " .. tostring(left))
	end
	check(minPos < 0.1 and maxPos > 0.9, string.format("Shuttle sweeps the whole track back and forth (%.3f .. %.3f)", minPos, maxPos))
	check(ui.statusCapsule:GetWidth() == lockedW, "Shuttle animation never resizes the capsule")

	-- One MarketScan.GetState() per chrome repaint (the refresh button reuses the state it is handed)
	local realGetState, stateCalls = ns.MarketScan.GetState, 0
	ns.MarketScan.GetState = function(...)
		stateCalls = stateCalls + 1
		return realGetState(...)
	end
	app.updateScanChrome()
	check(stateCalls == 1, "updateScanChrome reads MarketScan.GetState() exactly once, read " .. stateCalls)
	stateCalls = 0
	app.updateScanChrome(realGetState())
	check(stateCalls == 0, "updateScanChrome reuses a state table passed by its caller, read " .. stateCalls)
	ns.MarketScan.GetState = realGetState
	check(rb.scanning == true and ui.statusSyncFs:GetText() == "Scanning p.3 · 1 items", "Passed-through state paints the same scanning chrome")
	do
		local fh = assert(io.open(addonDir .. "MarketScan.lua", "rb"))
		local src = fh:read("*a")
		fh:close()
		local body = src:match("function MarketScan%.GetState%(%)(.-)[\r\n]end[\r\n]")
		check(body and body:find("matchedCount = marketScan.matchedCount", 1, true) ~= nil and not body:find("pairs(", 1, true),
			"MarketScan.GetState returns the tracked matchedCount in O(1) (no pairs() walk)")
	end

	-- Final page completes the scan
	C_AuctionHouse.HasFullBrowseResults = function() return true end
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { { itemKey = { itemID = 765 }, totalQuantity = 3, minPrice = 90 } })
	check(not MerchantMasterAPI.IsScanning(), "Full browse results finish the scan")
	check(icon._rotation == 0 and not rb.scanning, "Refresh icon rotation resets to 0 when the scan ends")
	check(not ui.statusScanBar:IsShown(), "Scan progress strip hides when the scan ends")
	check(not ui.statusSyncFs:GetText():find("Scanning", 1, true), "Sync label returns to the source / age readout, got " .. tostring(ui.statusSyncFs:GetText()))
	check(near(ui.statusDot._vertexColor, Theme.PALETTES.dark.accentGreen), "Status dot returns to fresh green after a completed scan")
	local doneToast = toasts[#toasts]
	check(doneToast and doneToast.variant == "success" and doneToast.msg:find("AH Scan Complete · 2 items updated", 1, true) ~= nil,
		"Scan completion fires the success toast, got " .. tostring(doneToast and doneToast.msg))

	-- A second scan starts from zero: counter, shuttle and width lock all reset
	C_AuctionHouse.HasFullBrowseResults = function() return false end
	MerchantMasterAPI.RefreshMarket()
	local restart = ns.MarketScan.GetState()
	check(restart.active and restart.matchedCount == 0 and restart.page == 0, "A new scan resets matchedCount / page to 0")
	check(bar:IsShown() and bar.indeterminate == true and bar.shuttlePos == 0 and fillLeft() == 0, "A new scan restarts the shuttle at the left end")
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {
		{ itemKey = { itemID = 2447 }, totalQuantity = 7, minPrice = 111 },
		{ itemKey = { itemID = 2447, itemSuffix = 7 }, totalQuantity = 2, minPrice = 99 },
		{ itemKey = { itemID = 765 }, totalQuantity = 3, minPrice = 90 },
	})
	check(ns.MarketScan.GetState().matchedCount == 2, "matchedCount counts each catalog item once (suffix variants share one ID), got "
		.. tostring(ns.MarketScan.GetState().matchedCount))
	check(ui.statusSyncFs:GetText() == "Scanning p.1 · 2 items" and ui.statusCapsule:GetWidth() == lockedW,
		"Second scan locks the same capsule width, got " .. tostring(ui.statusCapsule:GetWidth()))
	app.cancelMarketScan(false)
	check(not MerchantMasterAPI.IsScanning() and not bar:IsShown() and bar.indeterminate == false and bar.shuttlePos == nil,
		"Cancelling hides the strip and clears the shuttle state")

	-- Deep order-book lot scan: total is known, so the fill is a genuine left-anchored 0 -> trackW * done / total
	local savedLotTotal, savedLotDone = app.lotScanTotal, app.lotScanDone
	app.lotScanTotal, app.lotScanDone = 40, 10
	app.updateScanChrome()
	local lotW = ui.statusCapsule:GetWidth()
	local lotTrackW = lotW - 28
	check(bar:IsShown() and bar.indeterminate == false and bar.fraction == 0.25, "Lot scan shows a determinate 10/40 fraction")
	check(ui.statusSyncFs:GetText() == "Deep Scan 10/40" and rb.scanning == true, "Lot scan label + refresh icon state")
	check(fillLeft() == 0 and fill:GetWidth() == math.floor(lotTrackW * 0.25 + 0.5), "Determinate fill is anchored at the track's left edge")
	app.stepScanShuttle(0.3)
	check(fillLeft() == 0 and bar.shuttlePos == nil, "Shuttle stepping never moves a determinate fill")
	app.lotScanDone = 40
	app.updateScanChrome()
	check(bar.fraction == 1 and fill:GetWidth() == lotTrackW and ui.statusCapsule:GetWidth() == lotW,
		"Determinate fill reaches the full track at 40/40 without resizing the capsule")
	app.lotScanTotal, app.lotScanDone = savedLotTotal, savedLotDone
	app.updateScanChrome()
	check(not bar:IsShown() and bar.fraction == nil and not rb.scanning, "Strip hides again when the lot scan ends")

	-- Manual refresh away from the AH: show the closed-AH state without changing scan freshness or status
	AuctionHouseFrame:Hide()
	local prevLastRefresh = MerchantMasterDB.lastRefreshAt
	local prevSyncText = ui.statusSyncFs:GetText()
	local prevToastCount = #toasts
	rb:GetScript("OnEnter")(rb)
	rb:Click("LeftButton")
	check(not MerchantMasterAPI.IsScanning() and #toasts == prevToastCount,
		"Closed-AH refresh adds no toast and starts no scan")
	check(MerchantMasterDB.lastRefreshAt == prevLastRefresh and ui.statusSyncFs:GetText() == prevSyncText,
		"Closed-AH refresh preserves refresh timestamp and sync text")
	check(rb.ahNotOpen == true and icon:GetTexture() == Theme.ASSETS.icon_close,
		"Closed-AH refresh marks the button and shows the red cross")
	check(GameTooltip._lines and GameTooltip._lines[1] == "AH not open",
		"Closed-AH click immediately shows the AH not open tooltip")
	AuctionHouseFrame:Show()
	ui.winChrome.ahRefresh:Update()
	check(not rb.ahNotOpen and icon:GetTexture() == Theme.ASSETS.icon_refresh,
		"Opening the AH clears the cross and restores the refresh icon")
	AuctionHouseFrame:Hide()

	ui.toast.ShowToast = savedToast
	C_AuctionHouse.HasFullBrowseResults, C_AuctionHouse.RequestMoreBrowseResults = savedFull, savedMore
	MerchantMasterDB.ahPrices[economyKey] = savedPool
	ns.MarketScan.ActiveEconomyPrices()
	MerchantMasterDB.economy = prevEconomy
	ui.toolbar:SetWidth(savedToolbarW)
	ns.InvalidatePriceCache()
	app.refresh()
end

---------------------------------------------------------------------------------------------------
-- 3G. Light Mode Shopping List: zero white / pale-yellow / red-on-red ink across rows + summary
---------------------------------------------------------------------------------------------------
do
	local ui = app.ui
	local function strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	local function cellText(cell)
		if type(cell) ~= "table" then return "" end
		local t = (cell.fs and cell.fs.GetText and cell.fs:GetText()) or (cell.GetText and cell:GetText()) or ""
		return t or ""
	end

	local box = ui.shopPanel.table.scrollBox
	local pool = {}
	local function render()
		local items = box._dp and box._dp:GetCollection() or {}
		for i = 1, math.max(#items, #pool) do
			local r = pool[i]
			if i <= #items then
				if not r then
					r = CreateFrame("Button", nil, box)
					pool[i] = r
				end
				r:Show()
				box._view._initFn(r, items[i])
			elseif r then
				r:Hide()
			end
		end
	end
	local savedSetDP = box.SetDataProvider
	function box:SetDataProvider(dp)
		self._dp = dp
		render()
	end

	local saved = {
		profs = ns.GetPlayerProfessions, cost = ns.GetReagentUnitCost, listed = ns.GetNumListed,
		daily = ns.GetDailySold, owned = ns.GetOwnedItemCounts,
		queue = MerchantMasterDB.craftOrderQueue, shoppingList = MerchantMasterDB.shoppingList,
		overrides = MerchantMasterDB.subCraftOverrides, mode = MerchantMasterDB.subCraftMode,
		deduct = MerchantMasterDB.craftOrderDeductOwned, scope = MerchantMasterDB.shoppingSortScope,
		writQ = MerchantMasterDB.writCraftQueue, spreadQ = MerchantMasterDB.spreadQueue, turnQ = MerchantMasterDB.writTurnInQueue,
	}
	local PRICES = {
		[6049] = { 22000, "AH", false },     -- Fire Protection Potion
		[6371] = { 8000, "AH", false },      -- Fire Oil (cheaper to craft)
		[6359] = { 1500, "AH", false },      -- Firefin Snapper
		[3371] = { 40, "Vendor", true },     -- Empty Vial (owned)
		[3372] = { 200, "Vendor", true },    -- Leaded Vial
		[4402] = { 5000, "AH", false },      -- Small Flame Sac
	}
	ns.GetPlayerProfessions = function() return { alchemy = 300 } end
	ns.GetOwnedItemCounts = function() return { [ns.ItemName(3371)] = 40, [3371] = 40 } end
	ns.GetReagentUnitCost = function(itemID)
		local hit = PRICES[itemID]
		if hit then return hit[1], hit[2], hit[3] end
		return saved.cost(itemID)
	end
	ns.GetNumListed = function(itemID) if PRICES[itemID] then return 25 end return saved.listed(itemID) end
	ns.GetDailySold = function(itemID) if PRICES[itemID] then return 12.5 end return saved.daily(itemID) end
	ns.InvalidatePriceCache()

	MerchantMasterDB.shoppingList, MerchantMasterDB.subCraftOverrides = {}, {}
	MerchantMasterDB.writCraftQueue, MerchantMasterDB.spreadQueue, MerchantMasterDB.writTurnInQueue = {}, {}, {}
	MerchantMasterDB.subCraftMode = "smart"
	MerchantMasterDB.craftOrderDeductOwned = false
	MerchantMasterDB.shoppingSortScope = "main"
	MerchantMasterDB.craftOrderQueue = { { spellID = 7257, outputItemID = 6049, prof = "alchemy", qty = 1 } }
	app.sortState.shopping_list = { col = "default", asc = true }

	Theme.SetMode("light")
	app.panel:Show()
	app.setTab("recipes")
	app.toggleShoppingWindow(true)
	app.refresh()
	render()

	local function collect()
		local texts, joined = {}, {}
		for _, r in ipairs(pool) do
			if r:IsShown() then
				for _, cell in ipairs(r.cells or {}) do
					texts[#texts + 1] = cellText(cell)
				end
				if r.qtyBadge and r.qtyBadge:IsShown() and r.qtyBadge.fs then
					texts[#texts + 1] = r.qtyBadge.fs:GetText() or ""
				end
				if r.inlineMetaFs and r.inlineMetaFs:IsShown() then
					texts[#texts + 1] = r.inlineMetaFs:GetText() or ""
				end
			end
		end
		texts[#texts + 1] = ui.shopPanel.titleFs:GetText() or ""
		if ui.shopPanel.orderCountFs then texts[#texts + 1] = ui.shopPanel.orderCountFs:GetText() or "" end
		if ui.shopPanel.legendFs then texts[#texts + 1] = ui.shopPanel.legendFs:GetText() or "" end
		for _, card in ipairs({ ui.shopPanel.ahCard, ui.shopPanel.craftCard, ui.shopPanel.vendorCard, ui.shopPanel.ownedCard, ui.shopPanel.outlayCard }) do
			if card then
				texts[#texts + 1] = card.labelFs:GetText() or ""
				texts[#texts + 1] = card.valFs:GetText() or ""
				texts[#texts + 1] = card.subFs:GetText() or ""
				texts[#texts + 1] = card.tagFs:GetText() or ""
			end
		end
		for i, t in ipairs(texts) do joined[i] = strip(t) end
		return texts, table.concat(joined, "\n")
	end

	local texts, plain = collect()
	check(#texts > 9 * 4, "Light Shopping Cart rendered Main + Sub rows + Order Summary (" .. #texts .. " strings)")
	for _, forbidden in ipairs({ "|cffffffff", "|cffffd200", "|cffffdf7a", "|cffff8888", "|cffcccccc", "|cffffd60a" }) do
		for _, t in ipairs(texts) do
			check(not t:lower():find(forbidden, 1, true), "Light Shopping Cart string must not contain " .. forbidden:sub(3) .. ": " .. t)
		end
	end
	check(plain:find("CART ORDERS & BREAKDOWN", 1, true) ~= nil and plain:find("1 Main Order", 1, true) ~= nil, "V6 summary heading + Main Order count pill rendered")
	check(plain:find("BUY ON AUCTION HOUSE", 1, true) ~= nil and plain:find("CRAFT YOURSELF", 1, true) ~= nil, "Order Summary rail splits Buy on AH vs Craft Yourself")
	check(plain:find("Not sent to AH", 1, true) ~= nil and plain:find("Sent to AH", 1, true) ~= nil, "Order Summary rail clearly marks Sent to AH vs Not sent to AH")
	local mainRow = pool[1]
	check(mainRow.data and mainRow.data.isMainRow, "Row 1 is the Main Order row")
	check(mainRow.qtyMinusBtn and mainRow.qtyMinusBtn:IsShown() and mainRow.qtyPlusBtn and mainRow.qtyPlusBtn:IsShown(), "Main Order row exposes visible - / + quantity steppers")
	check(cellText(mainRow.cells[1]):find("|cff000000Fire Protection Potion|r", 1, true) ~= nil,
		"Main Order name uses #000000 ink in Light Mode, got " .. cellText(mainRow.cells[1]))
	check(cellText(mainRow.cells[2]):find("|cff0062ccMain: ", 1, true) ~= nil, "Main Order category uses accessible blue #0062CC")
	check(mainRow.cells[8]._actionTag == "Remove" and mainRow.cells[8].icon and mainRow.cells[8].icon:IsShown() and mainRow.cells[8].sqPlate ~= nil,
		"Main Order card renders framed square X remove button")
	check(mainRow.card ~= nil and mainRow.card.plate ~= nil and mainRow.tierBadge and mainRow.tierBadge:IsShown(), "Main Order card uses NineApple 9-slice plate + MAIN ORDER badge pill")
	check(mainRow.accentBar and mainRow.accentBar:IsShown(), "Main Order card renders left gold accent bar")
	local subCraftRow
	for _, r in ipairs(pool) do
		if r:IsShown() and r.data and not r.data.isMainRow and r.data.makeMyself then subCraftRow = r; break end
	end
	check(subCraftRow ~= nil and subCraftRow.card ~= nil and subCraftRow.tierBadge and subCraftRow.tierBadge:IsShown(), "Sub-Craft row renders NineApple card + SUB-CRAFT badge pill")
	check(cellText(mainRow.cells[9]):find("|cff8a5a00g|r", 1, true) ~= nil or cellText(mainRow.cells[9]):find("|cff5a606ds|r", 1, true) ~= nil,
		"Line Total uses themed g / s units without a yellow wrapper, got " .. cellText(mainRow.cells[9]))
	check(plain:find("CRAFT", 1, true) ~= nil, "Sub-craft toggle pill rendered")
	check(plain:find("VENDOR", 1, true) ~= nil and plain:find("BUY AH", 1, true) ~= nil, "VENDOR + BUY AH pills rendered")
	check(ui.shopModal.warcraftChrome ~= nil and ui.shopModal.resizeGrip ~= nil, "Shopping Cart modal attaches Warcraft chrome & resize grip")
	check(ui.shopPanel.buyAllBtn.subFs ~= nil and ui.optBuiltInBuyerCheck == nil and ui.shopPanel.buyerModeSeg == nil,
		"V7: Order Summary rail uses 2-line Hero Checkout CTA with pure built-in AH Buyer (no Auctionator buyer toggle)")
	local fs1 = mainRow.cells[1].fs
	local _, cellSize = fs1:GetFont()
	check(cellSize == 12, "Shopping Cart cells use the 12pt Apple font, got " .. tostring(cellSize))
	local _, titleSize = ui.shopPanel.titleFs:GetFont()
	check(titleSize == 13, "Shopping Cart summary uses the 13pt semibold Apple font, got " .. tostring(titleSize))

	-- Flip to Dark while the modal is open: rows + Order Summary re-render immediately with dark-palette ink
	Theme.SetMode("dark")
	local darkTexts = collect()
	check(cellText(pool[1].cells[1]):find("|cffffffffFire Protection Potion|r", 1, true) ~= nil,
		"Open modal re-renders in Dark Mode on toggle, got " .. cellText(pool[1].cells[1]))
	check(pool[1].cells[8]._actionTag == "Remove" and pool[1].cells[8].icon:IsShown(), "Main Order card keeps framed X remove button after Dark toggle")
	for _, t in ipairs(darkTexts) do
		check(not t:find("|cff000000", 1, true) and not t:find("|cffb8141a", 1, true), "Dark re-render carries no light-palette ink: " .. t)
	end

	app.toggleShoppingWindow(false)
	box.SetDataProvider = savedSetDP
	ns.GetPlayerProfessions, ns.GetReagentUnitCost, ns.GetNumListed = saved.profs, saved.cost, saved.listed
	ns.GetDailySold, ns.GetOwnedItemCounts = saved.daily, saved.owned
	MerchantMasterDB.craftOrderQueue, MerchantMasterDB.shoppingList = saved.queue, saved.shoppingList
	MerchantMasterDB.subCraftOverrides, MerchantMasterDB.subCraftMode = saved.overrides, saved.mode
	MerchantMasterDB.craftOrderDeductOwned, MerchantMasterDB.shoppingSortScope = saved.deduct, saved.scope
	MerchantMasterDB.writCraftQueue, MerchantMasterDB.spreadQueue, MerchantMasterDB.writTurnInQueue = saved.writQ, saved.spreadQ, saved.turnQ
	ns.InvalidatePriceCache()
	app.setTab("dashboard")
	app.refresh()
end

---------------------------------------------------------------------------------------------------
-- 3H. Liquid Glass sidebar: baked frost assets + near-opaque substrate (no game-UI bleed-through)
---------------------------------------------------------------------------------------------------
do
	local function checkTexturedRim(owner, asset, count, label)
		local pieces = {}
		for _, region in ipairs({ owner:GetRegions() }) do
			check(region._colorTexture == nil, label .. " creates no flat SetColorTexture highlight")
			if region:GetTexture() == asset then pieces[#pieces + 1] = region end
		end
		check(#pieces == count, label .. " draws its curved rim with the expected texture slices")
		return pieces
	end
	for _, kind in ipairs({ "glass_r22", "glass_r16" }) do
		local panel = CreateFrame("Frame", nil, app.panel)
		panel:SetSize(240, 96)
		local surf = Theme.NineApple(panel, kind)
		check(surf.specular == nil, kind .. " has no separate specular bar")
		checkTexturedRim(panel, Theme.ASSETS[kind .. "_stroke"], 8, kind)
	end
	local pill = CreateFrame("Frame", nil, app.panel)
	pill:SetSize(120, 28)
	local surface = Theme.NineApple(pill, "pill", "toolbarBg", false, { specular = true })
	check(surface.specular == nil, "Borderless specular pill has no flat specular bar")
	local left, right, center = unpack(checkTexturedRim(pill, Theme.ASSETS.pill_stroke, 3, "Specular pill"))
	check(left._points[1][1] == "TOPLEFT" and right._points[1][1] == "TOPRIGHT"
		and center._points[1][2] == left and center._points[1][3] == "TOPRIGHT"
		and center._points[2][2] == right and center._points[2][3] == "BOTTOMLEFT",
		"Pill rim caps and center share edges")

	local window = CreateFrame("Frame", nil, app.panel)
	window:SetSize(420, 240)
	local deco = CreateFrame("Frame", nil, window)
	local frameCount = #createdFrames
	local ring = Theme.WindowFrame(deco, window)
	check(#createdFrames == frameCount and select("#", deco:GetRegions()) == #ring.pieces,
		"WindowFrame creates only its ring, with no extra 1px line region or child")
	checkTexturedRim(deco, Theme.ASSETS.glass_r22_stroke, 8, "WindowFrame")

	local function u32le(s, i)
		local b1, b2, b3, b4 = s:byte(i, i + 3)
		return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
	end
	local glassBlps = {
		{ "shade_v.blp", 256, 512 },
		{ "header_wash.blp", 256, 512 },
		{ "fade_lr.blp", 256, 512 },
	}
	for _, spec in ipairs(glassBlps) do
		local name, expW, expH = spec[1], spec[2], spec[3]
		local fh = io.open(addonDir .. "Assets/" .. name, "rb")
		check(fh ~= nil, "Liquid Glass BLP2 asset exists: " .. name)
		local hdr, length = fh:read(148), fh:seek("end")
		fh:close()
		check(#hdr == 148 and hdr:sub(1, 4) == "BLP2", name .. " has valid BLP2 header")
		local btype = u32le(hdr, 5)
		local enc, _, aenc = hdr:byte(9, 11)
		local w, h = u32le(hdr, 13), u32le(hdr, 17)
		local mip0Off, mip0Len = u32le(hdr, 21), u32le(hdr, 85)
		check(btype == 1 and enc == 2 and aenc == 7, name .. " is BLP2 DXT5")
		check(w == expW and h == expH, string.format("%s is %dx%d, got %dx%d", name, expW, expH, w, h))
		check(mip0Off >= 1172 and mip0Len > 0 and length >= mip0Off + mip0Len, name .. " mip0 data is complete")
	end
	do
		local name, expW, expH = "glow_line.tga", 128, 16
		local fh = io.open(addonDir .. "Assets/" .. name, "rb")
		check(fh ~= nil, "Liquid Glass asset exists: " .. name)
		local data = fh:read("*a")
		fh:close()
		local idLen, cmapType, imgType = string.byte(data, 1, 3)
		local wLo, wHi, hLo, hHi, bpp, desc = string.byte(data, 13, 18)
		local w, h = wLo + wHi * 256, hLo + hHi * 256
		check(idLen == 0 and cmapType == 0 and imgType == 2 and bpp == 32 and desc == 0x08,
			name .. " keeps the TGA type=2 bpp=32 desc=0x08 contract")
		check(w == expW and h == expH, string.format("%s is %dx%d, got %dx%d", name, expW, expH, w, h))
		check(#data == 18 + w * h * 4 + 26 and data:sub(#data - 17, #data - 1) == "TRUEVISION-XFILE.", name .. " has the TGA 2.0 footer")
		local alphas, alphaKinds = {}, 0
		for i = 0, w * h - 1 do
			local a = string.byte(data, 22 + i * 4)
			if not alphas[a] then alphas[a] = true; alphaKinds = alphaKinds + 1 end
		end
		check(alphaKinds >= 16, name .. " carries a feathered refraction ramp (" .. alphaKinds .. " alpha levels)")
	end
	-- Verify renamed player-facing theme and table style labels
	local stdSkin = Theme.GetSkinInfo and Theme.GetSkinInfo("standard")
	check(stdSkin and stdSkin.label == "Modern Glass", "Standard skin displays as Modern Glass, got " .. tostring(stdSkin and stdSkin.label))
	local styleLabels = {}
	for _, st in ipairs(Theme.TABLE_STYLES or {}) do styleLabels[st.key] = st.label end
	check(styleLabels.t5_ruled == "Ruled Lines" and styleLabels.t5_well == "Deep Well" and styleLabels.t3_strips == "Card Strips",
		"Table styles use player-facing names (Ruled Lines, Deep Well, Card Strips)")

	check(Theme.PALETTES.dark.sidebarBg[4] >= 0.96, "Dark sidebarBg is near-opaque (>= 0.96)")
	check(Theme.PALETTES.light.sidebarBg[4] >= 0.96, "Light sidebarBg is near-opaque (>= 0.96)")
	check(Theme.PALETTES.dark.toolbarBg[4] >= 0.95 and Theme.PALETTES.light.toolbarBg[4] >= 0.95, "Toolbar pills occlude game text (>= 0.95)")

	local sb = app.ui.sidebar
	check(sb.surface and sb.surface.fill ~= nil, "Sidebar keeps its exact r=22 open-right 9-slice surface")
	check(sb.refractWash and #sb.refractWash.pieces == 3 and sb.refractLens and #sb.refractLens.pieces == 3,
		"Sidebar layers 3-slice refraction wash + lens over the surface")
	local glow = sb.refractGlow
	check(glow and glow:GetTexture() == "Interface\\AddOns\\MerchantMaster\\Assets\\glow_line"
		and glow._points[1][4] == 22 and glow._colorTexture == nil, "Sidebar uses the textured glow inset to its outer corner")
	Theme.SetMode("dark")
	check(sb.refractWash.texture == "shade_v" and sb.refractWash.alpha == 0.92, "Dark sidebar uses the shade_v frosted substrate at 0.92")
	check(sb.refractLens.texture == "fade_lr" and sb.refractLens.alpha == 0.55, "Dark sidebar lens overlay at 0.55")
	check(glow._vertexColor[4] == 0.07, "Dark sidebar uses the subtler glow")
	Theme.SetMode("light")
	check(sb.refractWash.texture == "header_wash" and sb.refractWash.alpha == 0.92, "Light sidebar switches live to the header_wash pearl substrate")
	check(sb.refractLens.alpha == 0.70, "Light sidebar lens overlay at 0.70")
	check(glow._vertexColor[4] == 0.16, "Light sidebar uses the brighter glow")
	Theme.SetMode("dark")
	for _, set in ipairs({ sb.refractWash, sb.refractLens }) do
		for _, piece in ipairs(set.pieces) do
			check(piece._subLevel == -1, "Refraction layers sit at subLevel -1 above the -3 surface")
		end
	end
end

---------------------------------------------------------------------------------------------------
-- 3I. Global CreateTexture subLevel Invariant (Zero values outside [-8, 7] across all routes)
---------------------------------------------------------------------------------------------------
do
	for _, tab in ipairs({ "dashboard", "spread", "outliers", "superlist", "vendor_crafter", "disenchant_crafter", "waylaid", "writs", "forged", "reputation", "leveling", "analytics", "console_overview", "console_database", "console_perf", "console_setup", "console_settings", "console_ui", "console_data", "calc", "bags", "dashboard" }) do
		app.setTab(tab)
	end
	Theme.SetMode("light")
	Theme.SetMode("dark")

	local allFrames = { UIParent, Minimap, GameTooltip }
	for _, f in ipairs(createdFrames) do
		allFrames[#allFrames + 1] = f
	end
	-- The host scrollbox creates row frames outside createdFrames.
	for _, f in ipairs(app.ui.forgedTable.scrollBox._frames) do
		allFrames[#allFrames + 1] = f
	end
	local texChecked, badSubLevels = 0, 0
	for _, f in ipairs(allFrames) do
		for _, r in ipairs(f._regions or {}) do
			if r._type == "Texture" then
				texChecked = texChecked + 1
				local s = r._subLevel
				if s ~= nil and (type(s) ~= "number" or s < -8 or s > 7) then
					badSubLevels = badSubLevels + 1
				end
			end
		end
	end
	check(texChecked > 0, "Global texture scan inspected >0 textures (" .. texChecked .. ")")
	check(badSubLevels == 0, "Zero CreateTexture subLevel values outside [-8, 7], found " .. badSubLevels)
end

---------------------------------------------------------------------------------------------------
-- 3J. Top-Right Shopping Cart Pill, Blue Icon-Only Send Button & Clean 72px Minimize Bar
---------------------------------------------------------------------------------------------------
do
	local ui = app.ui
	app.panel:Show()
	app.setTab("dashboard")
	app.refresh()

	-- Top-right cart pill + 48x48 blue icon-only Send-to-Auctionator button
	check(ui.topCartBtn ~= nil and ui.topCartBtn:IsShown(), "Top-right Shopping Cart pill exposed and visible")
	check(ui.cartSummaryFs ~= nil and (ui.cartSummaryFs:GetText() or ""):find("·", 1, true) ~= nil,
		"Top-right Shopping Cart displays '<count> · <spend>', got " .. tostring(ui.cartSummaryFs and ui.cartSummaryFs:GetText()))
	check(ui.topSendAuctionatorBtn ~= nil and ui.topSendAuctionatorBtn:IsShown(), "Top-right Send-to-Auctionator button exposed and visible")
	check(math.floor((ui.topSendAuctionatorBtn:GetWidth() or 0) + 0.5) == 48
		and math.floor((ui.topSendAuctionatorBtn:GetHeight() or 0) + 0.5) == 48,
		"Top-right Send-to-Auctionator button is 48x48")
	check((ui.topSendAuctionatorBtn:GetText() or "") == "", "Top-right Send-to-Auctionator button is icon-only (empty text)")
	check(ui.topTaskListBtn ~= nil and ui.topTaskListBtn:IsShown(), "Top-right Craft Task List button exposed and visible")
	check(math.floor((ui.topTaskListBtn:GetWidth() or 0) + 0.5) == 48
		and math.floor((ui.topTaskListBtn:GetHeight() or 0) + 0.5) == 48,
		"Top-right Craft Task List button is 48x48")
	check((ui.topTaskListBtn:GetText() or "") == "", "Top-right Craft Task List button is icon-only (empty text)")
	check(ui.topTaskListBtn.hl == nil, "topTaskListBtn removes rectangular .hl HIGHLIGHT texture")

	-- Clicking topTaskListBtn opens Stage 4 Craft Task List and updates badge when craft orders are queued
	if app.orderFlow and app.orderFlow.LoadFromShoppingRows then
		app.orderFlow.LoadFromShoppingRows({
			{ isMainRow = true, mainGroupKey = "hig_c1", name = "Fire Oil", itemID = 6371, spellID = 7837, prof = "alchemy", qty = 2, sourceKind = "craft_order", sourceLabel = "Crafting Order",
				reagents = { { itemID = 6359, name = "Firefin Snapper", qty = 2 } } },
		}, { title = "HIG Craft Check" })
		if ui._updateTopTaskListBadge then ui._updateTopTaskListBadge() end
		check(ui.topTaskListBtn.badge and ui.topTaskListBtn.badge:IsShown() and ui.topTaskListBtn.badgeFs:GetText() == "1",
			"topTaskListBtn badge shows '1' when 1 craft task is queued")
	end
	ui.topTaskListBtn:Click("LeftButton")
	check(ui.cartBuyerModal ~= nil and ui.cartBuyerModal:IsShown() == true
		and app.orderFlow and app.orderFlow.GetActiveStage and app.orderFlow.GetActiveStage() == "craft",
		"Clicking topTaskListBtn opens Stage 4 Craft Task List")
	ui.topTaskListBtn:Click("LeftButton")
	check(ui.cartBuyerModal == nil or not ui.cartBuyerModal:IsShown(), "Second topTaskListBtn click toggles Stage 4 closed")
	app.panel:Show()
	if app.orderFlow and app.orderFlow.Reset then app.orderFlow.Reset() end
	if ui._updateTopTaskListBadge then ui._updateTopTaskListBadge() end

	local savedCartRows = {
		{ itemID = 2447, name = "Peacebloom", count = 5, unitCost = 1000, lineCost = 5000, source = "AH" },
	}
	app.setActiveShoppingList(savedCartRows, "Test Cart", "Shopping List", "dashboard")
	local cartPlain = (ui.cartSummaryFs:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	check(cartPlain:find("1 · ", 1, true) ~= nil and cartPlain:find("50s", 1, true) ~= nil,
		"Top-right Shopping Cart pill updates count and Est. Spend live: " .. tostring(cartPlain))

	ui.topCartBtn:Click("LeftButton")
	check(ui.shopModal ~= nil and ui.shopModal:IsShown() == true, "Clicking topCartBtn opens Shopping List modal")
	ui.shopModal:Hide()

	local sentRows, sentLabel
	local origSend = app.sendShoppingRowsToBuyer
	app.sendShoppingRowsToBuyer = function(rows, lbl)
		sentRows, sentLabel = rows, lbl
		return true
	end
	ui.topSendAuctionatorBtn:Click("LeftButton")
	app.sendShoppingRowsToBuyer = origSend
	check(sentRows ~= nil and sentLabel == "Shopping List", "Clicking topSendAuctionatorBtn forwards Shopping List to active AH buyer")

	-- Orange minimize button collapses window cleanly to 72px top row while preserving 730px height
	MerchantMasterDB.window = MerchantMasterDB.window or {}
	MerchantMasterDB.window.height = 730
	app.setMinimized(false)
	local orangeBtn = ui.trafficLights and ui.trafficLights.minBtn
	check(orangeBtn ~= nil, "Orange traffic-light minimize button exposed")
	orangeBtn:Click("LeftButton")
	check(app._minimized == true and math.floor((app.panel:GetHeight() or 0) + 0.5) == 72,
		"Clicking orange minimize button collapses panel height to 72px, got " .. tostring(app.panel:GetHeight()))
	check(not ui.mainArea:IsShown() and not ui.walletCard:IsShown() and not ui.searchWrap:IsShown(),
		"Minimized mode hides mainArea, walletCard, and searchWrap")
	for _, nb in ipairs(ui.navOrder or {}) do
		check(not nb:IsShown(), "Minimized mode hides sidebar nav item")
	end
	check(ui.toolbar:IsShown() and ui.topCartBtn:IsShown() and ui.topTaskListBtn:IsShown() and ui.topSendAuctionatorBtn:IsShown() and ui.appearanceSwitch.frame:IsShown(),
		"Minimized mode keeps toolbar, topCartBtn, topTaskListBtn, topSendAuctionatorBtn, and appearanceSwitch visible")
	check(MerchantMasterDB.window.height == 730,
		"Minimized mode preserves saved 730px full height, got " .. tostring(MerchantMasterDB.window.height))

	orangeBtn:Click("LeftButton")
	check(app._minimized == false and math.floor((app.panel:GetHeight() or 0) + 0.5) == 730,
		"Second orange click restores 730px window height, got " .. tostring(app.panel:GetHeight()))
	check(ui.mainArea:IsShown() and ui.walletCard:IsShown() and ui.searchWrap:IsShown() and ui.navOrder[1]:IsShown(),
		"Restore reveals mainArea, walletCard, searchWrap, and sidebar nav")

	-- Traffic-light hover micro-glyphs, green maxBtn full-window zoom, pill-only topCartBtn hover, visible resizeGrip
	local tl = ui.trafficLights
	check(tl and type(tl.SetHovered) == "function", "trafficLights.SetHovered helper exposed")
	for _, k in ipairs({ "closeBtn", "minBtn", "maxBtn" }) do
		local b = tl[k]
		check(b and b.glyph ~= nil and not b.glyph:IsShown(), k .. " micro-glyph starts hidden")
		for _, r in ipairs(b._regions or {}) do
			check(r._type ~= "FontString", k .. " uses vector/texture glyphs only (no FontString)")
			local s = r._subLevel
			check(s == nil or (type(s) == "number" and s >= -8 and s <= 7), k .. " subLevel in [-8,7]")
		end
	end
	tl.closeBtn:GetScript("OnEnter")(tl.closeBtn)
	check(tl.closeBtn.glyph:IsShown() and tl.minBtn.glyph:IsShown() and tl.maxBtn.glyph:IsShown(),
		"Cluster hover shows all 3 traffic-light micro-glyphs together")
	tl.closeBtn:GetScript("OnLeave")(tl.closeBtn)
	check(not tl.closeBtn.glyph:IsShown() and not tl.minBtn.glyph:IsShown() and not tl.maxBtn.glyph:IsShown(),
		"Leaving cluster hides all 3 traffic-light micro-glyphs")

	local win = ui.winChrome.window
	MerchantMasterDB.window.width, MerchantMasterDB.window.height = 1840, 730
	win:ApplyFull()
	tl.maxBtn:Click("LeftButton")
	check(win:IsZoomed() == true and math.floor(app.panel:GetWidth() + 0.5) == 1896 and math.floor(app.panel:GetHeight() + 0.5) == 1056,
		string.format("Green maxBtn zooms to full screen (1896x1056), got %sx%s", tostring(app.panel:GetWidth()), tostring(app.panel:GetHeight())))
	tl.maxBtn:Click("LeftButton")
	check(win:IsZoomed() == false and math.floor(app.panel:GetWidth() + 0.5) == 1840 and math.floor(app.panel:GetHeight() + 0.5) == 730,
		string.format("Second green maxBtn click restores 1840x730, got %sx%s", tostring(app.panel:GetWidth()), tostring(app.panel:GetHeight())))

	-- Pill-only topCartBtn & topSendAuctionatorBtn hover (no unmasked rectangular HIGHLIGHT texture)
	check(ui.topCartBtn.hl == nil and ui.topSendAuctionatorBtn.hl == nil,
		"topCartBtn and topSendAuctionatorBtn remove rectangular .hl HIGHLIGHT textures")
	check(math.floor((ui.topCartBtn.iconTex:GetWidth() or 0) + 0.5) == 18 and math.floor((ui.topCartBtn.iconTex:GetHeight() or 0) + 0.5) == 18,
		"topCartBtn basket icon is 18x18")
	ui.topCartBtn:GetScript("OnEnter")(ui.topCartBtn)
	check(ui.topCartBtn._hovered == true, "topCartBtn OnEnter enters pill hover state")
	ui.topCartBtn:GetScript("OnLeave")(ui.topCartBtn)
	check(ui.topCartBtn._hovered == false, "topCartBtn OnLeave restores rest pill state")

	-- Visible resizeGrip (>= 20x20, resting alpha > 0, hover brightening)
	local rg = ui.winChrome.resizeGrip
	check(rg ~= nil and (rg:GetWidth() or 0) >= 20 and (rg:GetHeight() or 0) >= 20,
		string.format("resizeGrip >= 20x20, got %sx%s", tostring(rg and rg:GetWidth()), tostring(rg and rg:GetHeight())))
	local seenAlphas = {}
	local origSetAlpha = rg.SetAlpha
	rg.SetAlpha = function(self, a) seenAlphas[#seenAlphas + 1] = a; return origSetAlpha(self, a) end
	Theme.SetMode("light", true)
	check(#seenAlphas >= 1 and seenAlphas[#seenAlphas] > 0, "resizeGrip resting alpha > 0 on theme paint")
	rg:GetScript("OnEnter")(rg)
	check(seenAlphas[#seenAlphas] >= 0.90, "resizeGrip OnEnter brightens alpha to >= 0.90")
	rg:GetScript("OnLeave")(rg)
	check(seenAlphas[#seenAlphas] > 0 and seenAlphas[#seenAlphas] <= 0.50, "resizeGrip OnLeave restores resting alpha > 0")
	rg.SetAlpha = origSetAlpha
	Theme.SetMode("dark", true)

	app.setActiveShoppingList({}, "Empty", "Shopping List", "dashboard")

	-- Adaptive Craftable Now -> All Chars toolbar pill: shows alongside scopeSeg at 1840px,
	-- auto-collapses with compact indicator at 1320px minimum window width so zero overlap occurs.
	local prevKnown = MerchantMasterDB.knownRecipesOnly
	local prevUnlock = MerchantMasterDB.unlockFilter
	local prevAllChars = MerchantMasterDB.craftableAllChars
	MerchantMasterDB.window.width, MerchantMasterDB.window.height = 1840, 730
	win:ApplyFull()
	ui.scopeSeg:SetActive("known", false)
	check(ui.charScopeSeg and ui.charScopeSeg.frame and ui.charScopeSeg.frame:IsShown(),
		"charScopeSeg shows next to scopeSeg when Craftable Now is active at 1840px")
	ui.charScopeSeg:SetActive("all_chars", false)
	check(MerchantMasterDB.craftableAllChars == true,
		"Clicking All Chars in charScopeSeg enables MerchantMasterDB.craftableAllChars")
	ui.winChrome.window:SetSize(800, 400)
	ui.winChrome.window:Flush()
	check(app.panel:GetWidth() == 1320 and not ui.charScopeSeg.frame:IsShown()
		and ui.scopeSeg.buttons.known._label:GetText() == "Craftable (All)",
		"Shrinking to 1320px hides charScopeSeg and marks scopeSeg button as Craftable (All)")
	MerchantMasterDB.window.width, MerchantMasterDB.window.height = 1840, 730
	win:ApplyFull()
	if app.layoutWindow then app.layoutWindow() end
	ui.scopeSeg:SetActive("all", false)
	MerchantMasterDB.knownRecipesOnly = prevKnown
	MerchantMasterDB.unlockFilter = prevUnlock
	MerchantMasterDB.craftableAllChars = prevAllChars
	if app.invalidateCraftableScope then app.invalidateCraftableScope() end
	app.refresh()
end

print(string.format("Fable Apple HIG suite: %d assertions, 0 failures", count))
