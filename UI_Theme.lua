-- MerchantMaster UI_Theme.lua (v3.3.0 - Fable 5.2 Design 1 Apple HIG & Liquid Glass)
-- Supports live Dark <-> Light mode switching, concentric Liquid Glass 9-slice surfaces,
-- SF-Symbol white monochrome .tga icons, Apple semantic pills, KPI cards, and full
-- backwards compatibility with all legacy ns.Theme.* APIs.

local ADDON, ns = ...
local unpack = unpack or table.unpack

local Theme = {}
ns.Theme = Theme

Theme.ASSET_ROOT = "Interface\\AddOns\\" .. tostring(ADDON or "MerchantMaster") .. "\\Assets\\"
Theme.PRICE_DISPLAY_MODES = {
	{ key = "compact", short = "Standard", label = "1. Standard (Current)" },
	{ key = "no_copper", short = "Gold/Silver", label = "2. Gold & Silver Rounded (No Copper)" },
	{ key = "full_fixed", short = "00g 00s 00c", label = "3. Full Fixed (00g 00s 00c)" },
}
ns.PRICE_DISPLAY_MODES = Theme.PRICE_DISPLAY_MODES
local A_ROOT = Theme.ASSET_ROOT
local APPLE_ROOT = A_ROOT .. "apple\\"
Theme.APPLE_ASSET_ROOT = APPLE_ROOT

-- Warcraft skins: painted .tga art lives in Assets\skins\<skinKey>\ (+ shared files in Assets\skins\).
Theme.SKIN_ASSET_ROOT = A_ROOT .. "skins\\"
function Theme.GetSkinAsset(skinKey, name)
	if type(name) ~= "string" or name == "" then return nil end
	if skinKey and skinKey ~= "standard" then
		return Theme.SKIN_ASSET_ROOT .. skinKey .. "\\" .. name
	end
	return Theme.SKIN_ASSET_ROOT .. name
end

function Theme.GetCartMedallionAsset(skinKey)
	local key = skinKey or (Theme.GetSkin and Theme.GetSkin()) or "standard"
	return Theme.GetSkinAsset(key, "cart_medallion")
		or Theme.GetSkinAsset(key, "portrait")
		or ns.ADDON_ICON_SMALL
end

Theme.UI_SKINS = {
	{ key = "standard",  label = "Modern Glass",           short = "Modern Glass" },
	{ key = "human",     label = "Human (Stormwind)",      short = "Human" },
	{ key = "night_elf", label = "Night Elf (Kaldorei)",   short = "Night Elf" },
	{ key = "orc",       label = "Orc (Orgrimmar)",        short = "Orc" },
	{ key = "undead",    label = "Undead (Forsaken)",      short = "Undead" },
	{ key = "goblin",    label = "Goblin (Trade Baron)",   short = "Goblin" },
}
ns.UI_SKINS = Theme.UI_SKINS

Theme.TABLE_STYLES = {
	{ key = "t5_ruled",  label = "Ruled Lines", short = "Ruled Lines" },
	{ key = "t5_well",   label = "Deep Well",   short = "Deep Well" },
	{ key = "t3_strips", label = "Card Strips", short = "Card Strips" },
	{ key = "classic",   label = "Classic",     short = "Classic" },
}
ns.TABLE_STYLES = Theme.TABLE_STYLES

Theme.ASSETS = {
	glass_r22_fill           = APPLE_ROOT .. "glass_r22_fill",
	glass_r22_stroke         = APPLE_ROOT .. "glass_r22_stroke",
	glass_r22_openright_fill = APPLE_ROOT .. "glass_r22_openright_fill",
	glass_r22_openleft_fill  = APPLE_ROOT .. "glass_r22_openleft_fill",
	glass_r16_fill           = APPLE_ROOT .. "glass_r16_fill",
	glass_r16_stroke         = APPLE_ROOT .. "glass_r16_stroke",
	glass_r12_fill           = APPLE_ROOT .. "glass_r12_fill",
	glass_r12_stroke         = APPLE_ROOT .. "glass_r12_stroke",
	glass_r10_fill           = APPLE_ROOT .. "glass_r10_fill",
	glass_r10_stroke         = APPLE_ROOT .. "glass_r10_stroke",
	glass_r8_fill            = APPLE_ROOT .. "glass_r8_fill",
	glass_r8_stroke          = APPLE_ROOT .. "glass_r8_stroke",
	pill_fill                = APPLE_ROOT .. "pill_fill",
	pill_stroke              = APPLE_ROOT .. "pill_stroke",
	circle_fill              = APPLE_ROOT .. "circle_fill",
	circle_stroke            = APPLE_ROOT .. "circle_stroke",
	meter_track              = APPLE_ROOT .. "meter_track",
	meter_fill               = APPLE_ROOT .. "meter_fill",
	line_soft                = APPLE_ROOT .. "line_soft",
	shadow_r22               = APPLE_ROOT .. "shadow_r22",
	specular_top             = APPLE_ROOT .. "specular_top",

	icon_grid         = APPLE_ROOT .. "icon_grid",
	icon_basket       = APPLE_ROOT .. "icon_basket",
	icon_flask        = APPLE_ROOT .. "icon_flask",
	icon_crown        = APPLE_ROOT .. "icon_crown",
	icon_book         = APPLE_ROOT .. "icon_book",
	icon_crate        = APPLE_ROOT .. "icon_crate",
	icon_doc          = APPLE_ROOT .. "icon_doc",
	icon_shield       = APPLE_ROOT .. "icon_shield",
	icon_bars         = APPLE_ROOT .. "icon_bars",
	icon_trend        = APPLE_ROOT .. "icon_trend",
	icon_search       = APPLE_ROOT .. "icon_search",
	icon_refresh      = APPLE_ROOT .. "icon_refresh",
	icon_sun          = APPLE_ROOT .. "icon_sun",
	icon_moon         = APPLE_ROOT .. "icon_moon",
	icon_check        = APPLE_ROOT .. "icon_check",
	icon_checkcircle  = APPLE_ROOT .. "icon_checkcircle",
	icon_lock         = APPLE_ROOT .. "icon_lock",
	icon_send         = APPLE_ROOT .. "icon_send",
	icon_leaf         = APPLE_ROOT .. "icon_leaf",
	icon_vial         = APPLE_ROOT .. "icon_vial",
	icon_star         = APPLE_ROOT .. "icon_star",
	icon_coins        = APPLE_ROOT .. "icon_coins",
	icon_bolt         = APPLE_ROOT .. "icon_bolt",
	icon_chevron_down = APPLE_ROOT .. "icon_chevron_down",
	icon_close        = APPLE_ROOT .. "icon_close",
	icon_gear         = APPLE_ROOT .. "icon_gear",
}

Theme.ASSETS.icons = {
	grid         = Theme.ASSETS.icon_grid,
	basket       = Theme.ASSETS.icon_basket,
	flask        = Theme.ASSETS.icon_flask,
	crown        = Theme.ASSETS.icon_crown,
	book         = Theme.ASSETS.icon_book,
	crate        = Theme.ASSETS.icon_crate,
	doc          = Theme.ASSETS.icon_doc,
	shield       = Theme.ASSETS.icon_shield,
	bars         = Theme.ASSETS.icon_bars,
	trend        = Theme.ASSETS.icon_trend,
	search       = Theme.ASSETS.icon_search,
	refresh      = Theme.ASSETS.icon_refresh,
	sun          = Theme.ASSETS.icon_sun,
	moon         = Theme.ASSETS.icon_moon,
	check        = Theme.ASSETS.icon_check,
	checkcircle  = Theme.ASSETS.icon_checkcircle,
	lock         = Theme.ASSETS.icon_lock,
	send         = Theme.ASSETS.icon_send,
	leaf         = Theme.ASSETS.icon_leaf,
	vial         = Theme.ASSETS.icon_vial,
	star         = Theme.ASSETS.icon_star,
	coins        = Theme.ASSETS.icon_coins,
	bolt         = Theme.ASSETS.icon_bolt,
	chevron_down = Theme.ASSETS.icon_chevron_down,
	close        = Theme.ASSETS.icon_close,
	gear         = Theme.ASSETS.icon_gear,
}

local RR_TEX   = A_ROOT .. "rr_fill"
local RING_TEX = A_ROOT .. "window_ring"
local PILL_TEX = Theme.ASSETS.pill_fill

Theme.PALETTES = {
	dark = {
		mode               = "dark",
		winBg              = { 0.110, 0.110, 0.118, 0.99 }, -- #1C1C1E
		sidebarBg          = { 0.125, 0.133, 0.160, 0.97 }, -- Regular-Large dark glass (near-opaque: WoW cannot blur behind it)
		toolbarBg          = { 0.149, 0.149, 0.165, 0.95 }, -- #26262A Regular glass with an opaque backing
		cardBg             = { 0.173, 0.173, 0.180, 1.00 }, -- #2C2C2E
		cardAltBg          = { 0.204, 0.204, 0.220, 1.00 }, -- #343438
		cardHover          = { 0.224, 0.224, 0.239, 1.00 }, -- #39393D
		glassFill          = { 1.000, 1.000, 1.000, 0.07 },
		glassHover         = { 1.000, 1.000, 1.000, 0.05 },
		inputBg            = { 1.000, 1.000, 1.000, 0.075 },
		pillTrack          = { 1.000, 1.000, 1.000, 0.08 },
		pillThumb          = { 1.000, 1.000, 1.000, 0.17 },
		navActiveBg        = { 1.000, 1.000, 1.000, 0.13 },
		border             = { 1.000, 1.000, 1.000, 0.12 },
		borderStrong       = { 1.000, 1.000, 1.000, 0.22 },
		glassBorder        = { 1.000, 1.000, 1.000, 0.22 },
		windowEdge         = { 1.000, 1.000, 1.000, 0.22 },
		windowSpecular     = { 1.000, 1.000, 1.000, 0.26 },
		specular           = { 1.000, 1.000, 1.000, 0.32 },
		separator          = { 0.329, 0.329, 0.345, 0.60 },
		glassSep           = { 1.000, 1.000, 1.000, 0.14 },
		meterTrack         = { 1.000, 1.000, 1.000, 0.14 },
		meterFill          = { 1.000, 1.000, 1.000, 0.90 },
		text               = { 1.000, 1.000, 1.000, 1.00 }, -- #FFFFFF
		textGlass          = { 0.929, 0.929, 0.929, 1.00 }, -- #EDEDED
		textSecondary      = { 0.922, 0.922, 0.961, 0.62 }, -- rgba(235,235,245,0.62)
		textGlassSecondary = { 0.922, 0.922, 0.961, 0.68 }, -- Boosted for the baked sidebar substrate
		textMuted          = { 0.682, 0.682, 0.698, 1.00 }, -- #AEAEB2
		textOnAccent       = { 0.000, 0.000, 0.000, 1.00 }, -- Primary label ink on solid system blue
		accentBlue         = { 0.000, 0.569, 1.000, 1.00 }, -- #0091FF
		textBlue           = { 0.361, 0.722, 1.000, 1.00 }, -- #5CB8FF, increased-contrast system blue
		accentGreen        = { 0.188, 0.820, 0.345, 1.00 }, -- #30D158
		accentOrange       = { 1.000, 0.573, 0.188, 1.00 }, -- #FF9230
		accentRed          = { 1.000, 0.380, 0.396, 1.00 }, -- #FF6165, increased-contrast system red
		accentPurple       = { 0.918, 0.553, 1.000, 1.00 }, -- #EA8DFF, increased-contrast system purple
		gold               = { 1.000, 0.820, 0.200, 1.00 },
		silver             = { 0.780, 0.800, 0.840, 1.00 },
		copper             = { 0.840, 0.540, 0.340, 1.00 },

		-- Theme-safe WoW |cffRRGGBB hex tokens
		hexText            = "ffffff",
		hexSecondary       = "ebebf5",
		hexMuted           = "98989d",
		hexPositive        = "30d158",
		hexGreen           = "30d158",
		hexBlue            = "5ac8fa",
		hexWarning         = "ff9230",
		hexOrange          = "ff9230",
		hexRed             = "ff4245",
		hexDanger          = "ff4245",
		hexPurple          = "bf5af2",
		hexGold            = "ffd60a", -- luminous gold "g" on dark surfaces
		hexSilver          = "c7c7cc", -- cool metallic silver "s"
		hexCopper          = "e08a5e", -- warm burnished copper "c"
		hexCartSub         = "d4b3ff", -- arcane violet for nested sub-crafts
		hexCartTeal        = "56d4e8", -- cool teal accent for sub-craft connectors

		-- Online Shopping Cart semantic tokens (Main Gold vs Sub-Craft Arcane/Teal vs Pills)
		cartMainBg         = { 0.831, 0.635, 0.243, 0.14 },
		cartMainAccent     = { 0.969, 0.835, 0.486, 1.00 },
		cartSubBg          = { 0.460, 0.240, 0.820, 0.18 },
		cartSubAccent      = { 0.337, 0.831, 0.910, 1.00 },
		cartSubInk         = { 0.831, 0.702, 1.000, 1.00 },
		pillBuyBg          = { 0.080, 0.460, 0.260, 0.38 },
		pillBuyBorder      = { 0.180, 0.949, 0.561, 0.80 },
		pillCraftBg        = { 0.440, 0.220, 0.780, 0.44 },
		pillCraftBorder    = { 0.788, 0.627, 1.000, 0.85 },
		pillVendorBg       = { 0.640, 0.400, 0.080, 0.36 },
		pillVendorBorder   = { 0.960, 0.702, 0.259, 0.82 },
		pillOwnedBg        = { 0.120, 0.360, 0.220, 0.30 },
		pillOwnedBorder    = { 0.373, 0.976, 0.678, 0.48 },
		dangerBg           = { 0.545, 0.090, 0.161, 0.94 },
		dangerHover        = { 0.671, 0.114, 0.200, 0.98 },
		dangerBorder       = { 0.878, 0.310, 0.373, 0.95 },
		dangerInk          = { 1.000, 0.890, 0.906, 1.00 },

		-- Legacy Theme.COLORS compatibility
		base        = { 0.110, 0.110, 0.118, 0.99 },
		panel       = { 0.173, 0.173, 0.180, 1.00 },
		panelBorder = { 1.000, 1.000, 1.000, 0.14 },
		cardFill    = { 0.173, 0.173, 0.180, 1.00 },
		cardBorder  = { 1.000, 1.000, 1.000, 0.00 },
		perimeter   = { 1.000, 1.000, 1.000, 0.14 },
		cornerAcc   = { 1.000, 1.000, 1.000, 0.26 },
		headGold    = { 1.000, 1.000, 1.000, 1.00 },
		subGold     = { 0.922, 0.922, 0.961, 0.62 },
		titleCream  = { 1.000, 1.000, 1.000, 1.00 },
		btnText     = { 1.000, 1.000, 1.000, 1.00 },
		btnTextOn   = { 1.000, 1.000, 1.000, 1.00 },
		tabText     = { 0.922, 0.922, 0.961, 0.62 },
		tabTextOn   = { 1.000, 1.000, 1.000, 1.00 },
		tabIcon     = { 0.922, 0.922, 0.961, 0.62 },
		tabIconOn   = { 1.000, 1.000, 1.000, 1.00 },
	},
	light = {
		mode               = "light",
		winBg              = { 0.949, 0.949, 0.969, 0.99 }, -- #F2F2F7
		sidebarBg          = { 0.935, 0.938, 0.956, 0.97 }, -- Frosted light glass (near-opaque: WoW cannot blur behind it)
		toolbarBg          = { 0.949, 0.949, 0.969, 0.96 }, -- #F2F2F7 grouped background backing for Regular glass
		cardBg             = { 1.000, 1.000, 1.000, 1.00 }, -- #FFFFFF
		cardAltBg          = { 0.949, 0.949, 0.969, 1.00 }, -- #F2F2F7
		cardHover          = { 0.898, 0.898, 0.918, 1.00 }, -- #E5E5EA
		glassFill          = { 0.000, 0.000, 0.000, 0.045 },
		glassHover         = { 0.000, 0.000, 0.000, 0.045 },
		inputBg            = { 0.000, 0.000, 0.000, 0.06 },
		pillTrack          = { 0.000, 0.000, 0.000, 0.075 },
		pillThumb          = { 1.000, 1.000, 1.000, 1.00 },
		navActiveBg        = { 0.000, 0.000, 0.000, 0.10 },
		border             = { 0.000, 0.000, 0.000, 0.08 },
		borderStrong       = { 0.000, 0.000, 0.000, 0.14 },
		glassBorder        = { 1.000, 1.000, 1.000, 0.78 },
		windowEdge         = { 1.000, 1.000, 1.000, 0.78 },
		windowSpecular     = { 1.000, 1.000, 1.000, 0.90 },
		specular           = { 1.000, 1.000, 1.000, 0.95 },
		separator          = { 0.235, 0.235, 0.263, 0.29 },
		glassSep           = { 0.000, 0.000, 0.000, 0.14 },
		meterTrack         = { 0.000, 0.000, 0.000, 0.12 },
		meterFill          = { 0.110, 0.110, 0.118, 0.90 },
		text               = { 0.000, 0.000, 0.000, 1.00 }, -- #000000
		textGlass          = { 0.102, 0.102, 0.102, 1.00 }, -- #1A1A1A
		textSecondary      = { 0.235, 0.235, 0.263, 0.76 }, -- rgba(60,60,67,0.76)
		textGlassSecondary = { 0.000, 0.000, 0.000, 0.64 }, -- Boosted for the baked sidebar substrate
		textMuted          = { 0.369, 0.384, 0.416, 1.00 }, -- #5E626A (6.2:1 on #FFFFFF)
		textOnAccent       = { 0.000, 0.000, 0.000, 1.00 }, -- Primary label ink on solid system blue
		accentBlue         = { 0.000, 0.533, 1.000, 1.00 }, -- #0088FF
		textBlue           = { 0.000, 0.384, 0.800, 1.00 }, -- #0062CC, contrast-adjusted blue ink
		-- Light semantic accents also serve as ink on grouped surfaces.
		accentGreen        = { 0.000, 0.478, 0.169, 1.00 }, -- #007A2B
		accentOrange       = { 0.702, 0.290, 0.000, 1.00 }, -- #B34A00
		accentRed          = { 0.722, 0.078, 0.102, 1.00 }, -- #B8141A
		accentPurple       = { 0.620, 0.125, 0.706, 1.00 },
		gold               = { 0.740, 0.520, 0.040, 1.00 },
		silver             = { 0.440, 0.460, 0.500, 1.00 },
		copper             = { 0.660, 0.360, 0.160, 1.00 },

		-- Theme-safe WoW |cffRRGGBB hex tokens
		hexText            = "000000",
		hexSecondary       = "3c3c43",
		hexMuted           = "5e626a", -- 6.2:1 on #FFFFFF
		hexPositive        = "007a2b", -- 5.4:1 on #FFFFFF
		hexGreen           = "007a2b",
		hexBlue            = "0062cc", -- 6.0:1 on #FFFFFF
		hexWarning         = "9e4b00", -- 6.1:1 on #FFFFFF (never pale yellow)
		hexOrange          = "9e4b00",
		hexRed             = "b8141a", -- 6.6:1 on #FFFFFF
		hexDanger          = "b8141a",
		hexPurple          = "8a2fb8", -- 6.6:1 on #FFFFFF
		hexGold            = "8a5a00", -- dark burnished gold "g": 5.9:1 on #FFFFFF
		hexSilver          = "5a606d", -- slate-pewter silver "s": 6.3:1 on #FFFFFF, distinct from hexMuted
		hexCopper          = "9c4616", -- deep burnished copper "c" on white
		hexCartSub         = "6b24a8", -- deep arcane violet (>7:1 on #FFFFFF)
		hexCartTeal        = "0a6b82", -- deep cool teal (>5.8:1 on #FFFFFF)

		-- Online Shopping Cart semantic tokens (Light mode: dark high-contrast inks, soft surfaces)
		cartMainBg         = { 0.780, 0.580, 0.080, 0.11 },
		cartMainAccent     = { 0.680, 0.450, 0.020, 1.00 },
		cartSubBg          = { 0.420, 0.160, 0.760, 0.09 },
		cartSubAccent      = { 0.040, 0.460, 0.580, 1.00 },
		cartSubInk         = { 0.420, 0.140, 0.660, 1.00 },
		pillBuyBg          = { 0.000, 0.480, 0.180, 0.12 },
		pillBuyBorder      = { 0.000, 0.480, 0.180, 0.55 },
		pillCraftBg        = { 0.440, 0.160, 0.700, 0.13 },
		pillCraftBorder    = { 0.440, 0.160, 0.700, 0.55 },
		pillVendorBg       = { 0.680, 0.340, 0.000, 0.12 },
		pillVendorBorder   = { 0.680, 0.340, 0.000, 0.55 },
		pillOwnedBg        = { 0.000, 0.460, 0.200, 0.09 },
		pillOwnedBorder    = { 0.000, 0.460, 0.200, 0.40 },
		dangerBg           = { 0.780, 0.110, 0.150, 0.12 },
		dangerHover        = { 0.780, 0.110, 0.150, 0.20 },
		dangerBorder       = { 0.722, 0.078, 0.102, 0.68 },
		dangerInk          = { 0.722, 0.078, 0.102, 1.00 },

		-- Legacy Theme.COLORS compatibility
		base        = { 0.949, 0.949, 0.969, 0.99 },
		panel       = { 1.000, 1.000, 1.000, 1.00 },
		panelBorder = { 0.235, 0.235, 0.263, 0.14 },
		cardFill    = { 1.000, 1.000, 1.000, 1.00 },
		cardBorder  = { 0.000, 0.000, 0.000, 0.00 },
		perimeter   = { 1.000, 1.000, 1.000, 0.55 },
		cornerAcc   = { 1.000, 1.000, 1.000, 0.90 },
		headGold    = { 0.000, 0.000, 0.000, 1.00 },
		subGold     = { 0.235, 0.235, 0.263, 0.76 },
		titleCream  = { 0.000, 0.000, 0.000, 1.00 },
		btnText     = { 0.000, 0.000, 0.000, 1.00 },
		btnTextOn   = { 1.000, 1.000, 1.000, 1.00 },
		tabText     = { 0.235, 0.235, 0.263, 0.76 },
		tabTextOn   = { 0.000, 0.000, 0.000, 1.00 },
		tabIcon     = { 0.235, 0.235, 0.263, 0.76 },
		tabIconOn   = { 0.000, 0.000, 0.000, 1.00 },
	},
}

---------------------------------------------------------------------------------------------------
-- Warcraft skin palettes (never touch PALETTES.dark / PALETTES.light: Standard stays byte-identical).
-- Every skin carries EVERY key of PALETTES.dark (cloned, then overridden) plus the skin-only keys
-- frameBorder, frameInnerBorder, plaqueTitle, meterAccent, socketBorder and headGold (title ink).
-- All text inks are >= 4.5:1 on the surfaces they sit on (sidebar / toolbar / card / window).

local function rgbHex(hex, a)
	return {
		tonumber(hex:sub(1, 2), 16) / 255,
		tonumber(hex:sub(3, 4), 16) / 255,
		tonumber(hex:sub(5, 6), 16) / 255,
		a or 1,
	}
end

local function buildSkinPalette(key, s)
	local p = {}
	for k, v in pairs(Theme.PALETTES.dark) do
		p[k] = (type(v) == "table") and { v[1], v[2], v[3], v[4] } or v
	end
	local accentText = s.accentText or s.accent
	p.skin = key
	p.mode = "dark"
	p.winBg, p.sidebarBg, p.toolbarBg = rgbHex(s.win), rgbHex(s.sidebar), rgbHex(s.toolbar)
	p.cardBg, p.cardAltBg, p.cardHover = rgbHex(s.card), rgbHex(s.cardAlt), rgbHex(s.hover)
	p.glassFill, p.glassHover = { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.07 }
	p.inputBg, p.pillTrack = { 0, 0, 0, 0.38 }, { 0, 0, 0, 0.42 }
	p.pillThumb = rgbHex(s.frameInner, 0.90)
	p.navActiveBg = rgbHex(s.navActive or s.accent, 0.26)
	p.border, p.borderStrong = rgbHex(s.frameInner, 0.95), rgbHex(s.frameBorder, 0.90)
	p.glassBorder, p.windowEdge = rgbHex(s.frameBorder, 0.55), rgbHex(s.frameBorder, 0.80)
	p.windowSpecular, p.specular = { 1, 1, 1, 0.10 }, { 1, 1, 1, 0.14 }
	p.separator, p.glassSep = rgbHex(s.frameInner, 0.95), rgbHex(s.frameBorder, 0.40)
	p.meterTrack, p.meterFill = { 0, 0, 0, 0.50 }, rgbHex(s.meter)
	p.text, p.textGlass = rgbHex(s.text), rgbHex(s.text)
	p.textSecondary, p.textGlassSecondary = rgbHex(s.sec), rgbHex(s.sec)
	p.textMuted, p.textOnAccent = rgbHex(s.muted), rgbHex(s.onAccent)
	p.accentBlue, p.textBlue = rgbHex(s.accent), rgbHex(accentText)
	p.accentGreen, p.accentOrange = rgbHex(s.green), rgbHex(s.orange)
	p.accentRed, p.accentPurple = rgbHex(s.red), rgbHex(s.purple)
	p.gold, p.silver, p.copper = rgbHex(s.coinGold), rgbHex(s.coinSilver), rgbHex(s.coinCopper)

	p.hexText, p.hexSecondary, p.hexMuted = s.text, s.sec, s.muted
	p.hexPositive, p.hexGreen = s.green, s.green
	p.hexBlue = accentText
	p.hexWarning, p.hexOrange = s.orange, s.orange
	p.hexRed, p.hexDanger = s.red, s.red
	p.hexPurple = s.purple
	p.hexGold, p.hexSilver, p.hexCopper = s.coinGold, s.coinSilver, s.coinCopper

	p.base, p.panel, p.cardFill = p.winBg, p.cardBg, p.cardBg
	p.panelBorder, p.cardBorder = rgbHex(s.frameInner, 0.95), rgbHex(s.frameInner, 0.80)
	p.perimeter, p.cornerAcc = rgbHex(s.frameBorder, 0.90), rgbHex(s.gold)
	p.headGold, p.subGold, p.titleCream = rgbHex(s.gold), rgbHex(s.sec), rgbHex(s.text)
	p.btnText, p.btnTextOn = rgbHex(s.text), rgbHex(s.text)
	p.tabText, p.tabTextOn = rgbHex(s.sec), rgbHex(s.text)
	p.tabIcon, p.tabIconOn = rgbHex(s.sec), rgbHex(s.text)

	p.frameBorder, p.frameInnerBorder = rgbHex(s.frameBorder), rgbHex(s.frameInner)
	p.plaqueTitle, p.meterAccent = rgbHex(s.plaque), rgbHex(s.meter)
	p.socketBorder = rgbHex(s.socket)
	p.cartMainAccent = rgbHex(s.gold)
	p.cartMainBg = rgbHex(s.frameBorder, 0.18)
	p.cartSubBg = (key == "goblin") and { 0.420, 0.200, 0.740, 0.22 } or { 0.460, 0.240, 0.820, 0.18 }
	p.cartSubAccent = { 0.337, 0.831, 0.910, 1.00 }
	p.cartSubInk = rgbHex(s.purple)
	p.hexCartSub = s.purple
	p.hexCartTeal = "56d4e8"
	p.pillCraftBg      = { 0.36, 0.14, 0.72, 0.92 }
	p.pillCraftBorder  = { 0.78, 0.58, 1.00, 0.96 }
	p.pillBuyBg        = { 0.07, 0.36, 0.21, 0.90 }
	p.pillBuyBorder    = { 0.18, 0.95, 0.56, 0.95 }
	p.pillVendorBg     = { 0.46, 0.27, 0.06, 0.88 }
	p.pillVendorBorder = { 0.96, 0.70, 0.26, 0.95 }
	p.pillOwnedBg      = { 0.10, 0.28, 0.18, 0.82 }
	p.pillOwnedBorder  = { 0.37, 0.98, 0.68, 0.72 }
	return p
end

Theme.SKIN_PALETTES = {
	human = buildSkinPalette("human", {
		win = "232833", sidebar = "161a22", toolbar = "132446", card = "2d3442", cardAlt = "232833", hover = "343c4d",
		text = "f4efe4", sec = "bcc6d8", muted = "aab5c9", accent = "7ab0f5", onAccent = "0b1220",
		green = "45db84", orange = "f5b53c", red = "ff8080", purple = "c9a0ff",
		gold = "fad87a", plaque = "fad87a", meter = "e3b448",
		frameBorder = "b98a2e", frameInner = "4f3a14", socket = "b98a2e",
		coinGold = "fad87a", coinSilver = "cbd5e1", coinCopper = "d98a54",
	}),
	night_elf = buildSkinPalette("night_elf", {
		win = "111e2e", sidebar = "0c1522", toolbar = "211a33", card = "142436", cardAlt = "16283b", hover = "1d354d",
		text = "f1f6fa", sec = "b4c6d8", muted = "93a8be", accent = "67e8f9", onAccent = "06121a",
		green = "4ade80", orange = "f5b85a", red = "ff8a94", purple = "c4a3ff",
		gold = "cfdbe8", plaque = "eef5fc", meter = "67e8f9",
		frameBorder = "7b8ea8", frameInner = "2e2447", socket = "7b8ea8",
		coinGold = "f6d57a", coinSilver = "d6e1ed", coinCopper = "df925d",
	}),
	orc = buildSkinPalette("orc", {
		win = "1a1412", sidebar = "120e0d", toolbar = "2b1b14", card = "271f1c", cardAlt = "1e1410", hover = "3a2d28",
		text = "f3e6d0", sec = "d2c0a6", muted = "ad9a80", accent = "dfa64b", onAccent = "1a0f08",
		green = "4ade80", orange = "f59e0b", red = "ff6b5e", purple = "d29bff",
		gold = "f6c854", plaque = "f6c854", meter = "e5503a",
		frameBorder = "9c6828", frameInner = "5c3b16", socket = "9c6828",
		coinGold = "f6c854", coinSilver = "cbd5e1", coinCopper = "dc8850",
	}),
	undead = buildSkinPalette("undead", {
		win = "141922", sidebar = "0d1117", toolbar = "1c2330", card = "1c2330", cardAlt = "141922", hover = "252d3a",
		text = "e6dcc6", sec = "cfc3aa", muted = "a39d8c", accent = "62cfc8", onAccent = "06100f",
		green = "68f54b", orange = "f0b04a", red = "ff7a7a", purple = "c9a7ff",
		gold = "e6dcc6", plaque = "e6dcc6", meter = "4ad633",
		frameBorder = "647184", frameInner = "3c4656", socket = "8794a8",
		coinGold = "f0c869", coinSilver = "cbd5e1", coinCopper = "d68956",
	}),
	goblin = buildSkinPalette("goblin", {
		win = "0d261a", sidebar = "5c0c1c", toolbar = "29050c", card = "0d261a", cardAlt = "091c13", hover = "164029",
		text = "f5eedc", sec = "d3dcd5", muted = "a9b8ae", accent = "2ef28f", onAccent = "04120a",
		green = "5ff9ad", orange = "f7a93c", red = "ff8a9a", purple = "d6a8ff",
		gold = "f7d57c", plaque = "f7d57c", meter = "d4a23e", navActive = "d4a23e",
		frameBorder = "c0902e", frameInner = "4f370c", socket = "d4a23e",
		coinGold = "f7d57c", coinSilver = "d3dde6", coinCopper = "dc8b55",
	}),
}

Theme.COLORS = {}
Theme.PALETTE = {}
local currentMode = "dark"
local currentSkin = "standard"
local currentTableStyle = "t5_ruled"
local modeCallbacks = {}
local skinCallbacks = {}
local tableStyleCallbacks = {}
local moneyInkByMode = {} -- palette key -> ink table (declared early: Theme.SetSkin resets it)
local themeHexMaps = {}   -- palette key -> legacy-hex translation map
local registeredWidgets = {}
local registeredByWidget = {} -- widget -> entry: O(1) re-registration (table rows register per frame)

-- Palette key: "dark" / "light" for the Standard skin, the skin key itself for a Warcraft skin.
local function paletteByKey(key)
	return (Theme.SKIN_PALETTES and Theme.SKIN_PALETTES[key]) or Theme.PALETTES[key] or Theme.PALETTES.dark
end
local function paletteKey()
	return currentSkin == "standard" and currentMode or currentSkin
end

function Theme.GetActivePalette()
	return paletteByKey(paletteKey())
end

local function syncColorsTable(mode)
	local pal = paletteByKey(mode)
	for k in pairs(Theme.COLORS) do Theme.COLORS[k] = nil end
	for k in pairs(Theme.PALETTE) do Theme.PALETTE[k] = nil end
	for k, v in pairs(pal) do
		if type(v) == "table" then
			Theme.COLORS[k] = { v[1], v[2], v[3], v[4] }
			Theme.PALETTE[k] = { v[1], v[2], v[3], v[4] }
		else
			Theme.COLORS[k] = v
			Theme.PALETTE[k] = v
		end
	end
end
syncColorsTable(currentMode)

-- Effective appearance: "dark" / "light" on the Standard skin, always "dark" on a Warcraft skin
-- (every Warcraft palette is a dark one), so legacy `GetMode() == "light"` ink checks stay correct.
function Theme.GetMode()
	if currentSkin ~= "standard" then return "dark" end
	return currentMode
end

-- The Dark / Light choice the player made (persisted; restored when returning to Standard).
function Theme.GetUserMode()
	return currentMode
end

function Theme.GetPriceDisplayMode()
	local db = MerchantMasterDB
	local mode = type(db) == "table" and db.priceDisplayMode or nil
	if mode == "no_copper" or mode == "full_fixed" then return mode end
	return "compact"
end

function Theme.RegisterWidget(widget, applyFn)
	if not widget or type(applyFn) ~= "function" then return end
	local entry = registeredByWidget[widget]
	if entry then
		entry.apply = applyFn
		return
	end
	entry = { widget = widget, apply = applyFn }
	registeredByWidget[widget] = entry
	registeredWidgets[#registeredWidgets + 1] = entry
end

function Theme.OnModeChanged(fn)
	if type(fn) ~= "function" then return end
	for _, existing in ipairs(modeCallbacks) do
		if existing == fn then return end
	end
	modeCallbacks[#modeCallbacks + 1] = fn
	return function()
		for i = #modeCallbacks, 1, -1 do
			if modeCallbacks[i] == fn then
				table.remove(modeCallbacks, i)
			end
		end
	end
end

local pendingRepaint = false
local lastPaintedSig = "dark|t5_ruled|standard"

local function repaintAll(effMode, pal, silent)
	lastPaintedSig = tostring(currentMode) .. "|" .. tostring(currentTableStyle) .. "|" .. tostring(currentSkin)
	pendingRepaint = false
	for _, entry in ipairs(registeredWidgets) do
		if entry.apply then
			pcall(entry.apply, effMode, pal)
		end
	end
	if not silent then
		for _, fn in ipairs(modeCallbacks) do
			pcall(fn, effMode, pal)
		end
	end
end

function Theme.FlushPendingRepaint()
	if not pendingRepaint then return false end
	pendingRepaint = false
	local effMode = Theme.GetMode()
	repaintAll(effMode, Theme.GetActivePalette(), true)
	return true
end

function Theme.HasPendingRepaint()
	return pendingRepaint == true
end

function Theme.ApplySavedSettings(mode, tableStyle, skinKey, deferRepaint)
	local nextMode = (mode == "light") and "light" or "dark"
	local nextStyle = Theme.IsValidTableStyle(tableStyle) and tableStyle or "t5_ruled"
	local nextSkin = Theme.IsValidSkin(skinKey) and skinKey or "standard"
	currentMode = nextMode
	currentTableStyle = nextStyle
	currentSkin = nextSkin
	local effMode = Theme.GetMode()
	Theme.mode = effMode
	Theme.tableStyle = nextStyle
	Theme.skin = nextSkin
	moneyInkByMode = {}
	themeHexMaps = {}
	syncColorsTable(paletteKey())
	local nextSig = tostring(nextMode) .. "|" .. tostring(nextStyle) .. "|" .. tostring(nextSkin)
	if nextSig == lastPaintedSig then
		pendingRepaint = false
		return nextMode, nextStyle, nextSkin
	end
	if deferRepaint then
		pendingRepaint = true
	else
		repaintAll(effMode, Theme.GetActivePalette(), true)
	end
	return nextMode, nextStyle, nextSkin
end

function Theme.SetMode(mode, silent)
	local nextMode = (mode == "light") and "light" or "dark"
	currentMode = nextMode
	local effMode = Theme.GetMode()
	Theme.mode = effMode
	syncColorsTable(paletteKey())

	repaintAll(effMode, Theme.GetActivePalette(), silent)
	return nextMode
end

function Theme.ToggleMode()
	return Theme.SetMode(currentMode == "dark" and "light" or "dark")
end

---------------------------------------------------------------------------------------------------
-- UI Skins (Modern Glass + 5 Warcraft skins)

function Theme.GetSkin()
	return currentSkin
end

function Theme.IsCustomSkin()
	return currentSkin ~= "standard"
end

function Theme.GetSkinInfo(key)
	key = key or currentSkin
	for _, info in ipairs(Theme.UI_SKINS) do
		if info.key == key then return info end
	end
	return Theme.UI_SKINS[1]
end

function Theme.IsValidSkin(key)
	for _, info in ipairs(Theme.UI_SKINS) do
		if info.key == key then return true end
	end
	return false
end

function Theme.OnSkinChanged(fn)
	if type(fn) ~= "function" then return end
	for _, existing in ipairs(skinCallbacks) do
		if existing == fn then return end
	end
	skinCallbacks[#skinCallbacks + 1] = fn
	return function()
		for i = #skinCallbacks, 1, -1 do
			if skinCallbacks[i] == fn then
				table.remove(skinCallbacks, i)
			end
		end
	end
end

-- Switches the whole UI between Modern Glass (keeps the player's Dark / Light choice)
-- and a Warcraft skin. Re-paints every registered widget; `silent` skips the change callbacks.
function Theme.SetSkin(skinKey, silent)
	local nextSkin = Theme.IsValidSkin(skinKey) and skinKey or "standard"
	local changed = (nextSkin ~= currentSkin)
	currentSkin = nextSkin
	Theme.skin = nextSkin
	local effMode = Theme.GetMode()
	Theme.mode = effMode
	-- Money ink / theme-hex maps are keyed by palette key, so nothing stale survives a switch,
	-- but dropping them keeps memory bounded and guarantees a rebuild from the live palette.
	moneyInkByMode = {}
	themeHexMaps = {}
	syncColorsTable(paletteKey())

	local pal = Theme.GetActivePalette()
	repaintAll(effMode, pal, silent)
	if not silent then
		for _, fn in ipairs(skinCallbacks) do
			pcall(fn, nextSkin, pal, changed)
		end
	end
	return nextSkin
end

function Theme.GetTableStyle()
	return currentTableStyle
end

function Theme.GetTableStyleInfo(key)
	for _, info in ipairs(Theme.TABLE_STYLES) do
		if info.key == key then return info end
	end
	return Theme.TABLE_STYLES[1]
end

function Theme.IsValidTableStyle(key)
	for _, info in ipairs(Theme.TABLE_STYLES) do
		if info.key == key then return true end
	end
	return false
end

function Theme.OnTableStyleChanged(fn)
	if type(fn) ~= "function" then return end
	for _, existing in ipairs(tableStyleCallbacks) do
		if existing == fn then return end
	end
	tableStyleCallbacks[#tableStyleCallbacks + 1] = fn
	return function()
		for i = #tableStyleCallbacks, 1, -1 do
			if tableStyleCallbacks[i] == fn then table.remove(tableStyleCallbacks, i) end
		end
	end
end

function Theme.SetTableStyle(styleKey, silent)
	local nextStyle = Theme.IsValidTableStyle(styleKey) and styleKey or "t5_ruled"
	local changed = (nextStyle ~= currentTableStyle)
	currentTableStyle = nextStyle
	Theme.tableStyle = nextStyle
	local pal = Theme.GetActivePalette()
	repaintAll(Theme.GetMode(), pal, silent)
	if not silent then
		for _, fn in ipairs(tableStyleCallbacks) do
			pcall(fn, nextStyle, pal, changed)
		end
	end
	return nextStyle
end

local VALID_FONT_FLAGS = {
	[""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true,
	["OUTLINE, MONOCHROME"] = true, ["OUTLINE,MONOCHROME"] = true,
	["THICKOUTLINE, MONOCHROME"] = true, ["THICKOUTLINE,MONOCHROME"] = true,
}

local FONTS_ROOT    = "Interface\\AddOns\\" .. tostring(ADDON or "MerchantMaster") .. "\\Assets\\fonts\\"
local FONT_REGULAR  = FONTS_ROOT .. "Inter-Regular.ttf"
local FONT_SEMIBOLD = FONTS_ROOT .. "Inter-SemiBold.ttf"
local FONT_FALLBACK = "Fonts\\ARIALN.TTF"

Theme.FONTS = {
	regular  = FONT_REGULAR,
	semibold = FONT_SEMIBOLD,
	fallback = FONT_FALLBACK,
}

Theme.NON_LATIN_LOCALES = {
	ruRU = true,
	koKR = true,
	zhCN = true,
	zhTW = true,
}

function Theme.ShouldUseLocaleFallback(locale)
	local loc = locale
	if loc == nil and type(GetLocale) == "function" then
		loc = GetLocale()
	end
	return (type(loc) == "string" and Theme.NON_LATIN_LOCALES[loc] == true) or false
end

function Theme.ResolveFontPath(weight, locale)
	if Theme.ShouldUseLocaleFallback(locale) then
		return STANDARD_TEXT_FONT or FONT_FALLBACK
	end
	local wLower = type(weight) == "string" and weight:lower() or ""
	return (wLower == "semibold" or wLower == "bold" or wLower == "heavy") and FONT_SEMIBOLD or FONT_REGULAR
end

function Theme.ApplyFont(fs, size, weight, flags)
	if not fs or not fs.SetFont then return end
	local n = tonumber(size)
	if size ~= nil then
		if not n or n <= 0 then return end
	elseif fs.GetFont then
		local _, curSize = fs:GetFont()
		n = tonumber(curSize) or 12
	else
		n = 12
	end

	local fontPath = Theme.ResolveFontPath(weight)

	local curFlags = ""
	if fs.GetFont then
		local _, _, cf = fs:GetFont()
		curFlags = cf or ""
	end
	local f = (flags ~= nil) and tostring(flags) or curFlags
	if not VALID_FONT_FLAGS[f] then f = "" end

	local ok = fs:SetFont(fontPath, n, f)
	local curAfter = fs.GetFont and fs:GetFont()
	if ok == false or (ok == nil and curAfter ~= fontPath) then
		local fb = STANDARD_TEXT_FONT or FONT_FALLBACK
		local okFb = fs:SetFont(fb, n, f)
		if okFb == false and fb ~= FONT_FALLBACK then
			fs:SetFont(FONT_FALLBACK, n, f)
		end
	end
	if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
	if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
end

function Theme.SetFont(fs, size, flags)
	return Theme.ApplyFont(fs, size, nil, flags)
end

---------------------------------------------------------------------------------------------------
-- Consistent Sales / Day & Tabular Money Formatting

function Theme.FormatSalesPerDay(val)
	local pal = Theme.GetActivePalette()
	local isLight = (pal.mode == "light")
	if val == nil then
		local nilHex = isLight and (pal.hexMuted or "6e6e73") or "6e6b64"
		return "|cff" .. nilHex .. "—|r"
	end
	if val <= 0 then
		local zeroHex = isLight and (pal.hexMuted or "6e6e73") or "7a766e"
		return "|cff" .. zeroHex .. "0.0|r"
	end
	local colHex = isLight and "0066cc" or "7fd4ff"
	if val >= 1000 then
		return string.format("|cff%s%.1fk|r", colHex, val / 1000)
	elseif val >= 100 then
		return string.format("|cff%s%.0f|r", colHex, val)
	elseif val >= 10 then
		return string.format("|cff%s%.1f|r", colHex, val)
	elseif val >= 0.1 then
		return string.format("|cff%s%.2f|r", colHex, val)
	else
		return string.format("|cff%s%.3f|r", colHex, val)
	end
end

local function commaInt(n)
	if n < 1000 then return tostring(n) end
	local s = tostring(math.floor(n))
	local pos = #s % 3
	if pos == 0 then pos = 3 end
	local out = { s:sub(1, pos) }
	for i = pos + 1, #s, 3 do
		out[#out + 1] = s:sub(i, i + 2)
	end
	return table.concat(out, ",")
end

-- Per-appearance money ink: numerals in text / positive / negative ink, golden g, silver s, copper c.
-- Built once per mode (this runs for every money cell of every table row).
moneyInkByMode = {}
local function moneyInk(mode)
	local ink = moneyInkByMode[mode]
	if not ink then
		local pal = paletteByKey(mode)
		ink = {
			text = "|cff" .. (pal.hexText or "ffffff"),
			pos  = "|cff" .. (pal.hexPositive or "30d158"),
			neg  = "|cff" .. (pal.hexRed or "ff4245"),
			g    = "|r|cff" .. (pal.hexGold or "ffd60a") .. "g|r",
			s    = "|r|cff" .. (pal.hexSilver or "c7c7cc") .. "s|r",
			c    = "|r|cff" .. (pal.hexCopper or "e08a5e") .. "c|r",
			dash = "|cff" .. (pal.hexMuted or "98989d") .. "—|r",
		}
		moneyInkByMode[mode] = ink
	end
	return ink
end
local TWO_DIGITS = {}
for i = 0, 99 do TWO_DIGITS[i] = string.format("%02d", i) end

-- signed: true = +green / -red, "neutral" = signed in text ink,
-- "cost" = unsigned text ink (a negative cost is a gain: "-" in positive green).
-- Returns text, gold, silver, copper.
local function formatMoneyText(copper, signed, noCopperWhenGold, modeOverride)
	local ink = moneyInk(paletteKey())
	if type(_G.issecretvalue) == "function" then
		local ok, secret = pcall(_G.issecretvalue, copper)
		if not ok or secret then return ink.dash, 0, 0, 0 end
	end
	if type(copper) ~= "number" or copper ~= copper or copper == math.huge or copper == -math.huge then
		return ink.dash, 0, 0, 0
	end
	local neutralSign = (signed == "neutral")
	local neg = copper < 0
	local pos = (signed == true or neutralSign) and copper > 0
	local absVal = math.floor(math.abs(copper) + 0.5)
	local g = math.floor(absVal / 10000)
	local s = math.floor((absVal % 10000) / 100)
	local c = absVal % 100
	local effMode = modeOverride or Theme.GetPriceDisplayMode()
	local roundedS
	if effMode == "no_copper" then
		roundedS = math.floor((math.abs(copper) + 50) / 100)
		if roundedS == 0 then
			neg = false
			pos = false
		end
	end

	local num = ink.text
	if signed == "cost" then
		if neg then num = ink.pos end
	elseif not neutralSign then
		if pos then
			num = ink.pos
		elseif neg then
			num = ink.neg
		end
	end
	local sign = neg and "-" or (pos and "+" or "")

	local text
	if effMode == "no_copper" then
		g = math.floor(roundedS / 100)
		s = roundedS % 100
		c = 0
		if g > 0 then
			text = num .. sign .. commaInt(g) .. ink.g .. " " .. num .. TWO_DIGITS[s] .. ink.s
		else
			text = num .. sign .. s .. ink.s
		end
	elseif effMode == "full_fixed" then
		local gStr = g < 10 and TWO_DIGITS[g] or commaInt(g)
		text = num .. sign .. gStr .. ink.g .. " " .. num .. TWO_DIGITS[s] .. ink.s .. " " .. num .. TWO_DIGITS[c] .. ink.c
	elseif g > 0 then
		if c > 0 and not noCopperWhenGold then
			text = num .. sign .. commaInt(g) .. ink.g .. " " .. num .. TWO_DIGITS[s] .. ink.s .. " " .. num .. TWO_DIGITS[c] .. ink.c
		else
			text = num .. sign .. commaInt(g) .. ink.g .. " " .. num .. TWO_DIGITS[s] .. ink.s
		end
	elseif s > 0 then
		text = num .. sign .. s .. ink.s .. " " .. num .. TWO_DIGITS[c] .. ink.c
	else
		text = num .. sign .. c .. ink.c
	end
	return text, g, s, c
end

function Theme.FormatMoneyParts(copper, signed, noCopperWhenGold, modeOverride)
	local text, g, s, c = formatMoneyText(copper, signed, noCopperWhenGold, modeOverride)
	return { text = text, g = g, s = s, c = c }
end

-- Same string as Theme.FormatMoneyParts(...).text without the per-call table (hot path for table cells).
function Theme.FormatMoneyText(copper, signed, noCopperWhenGold, modeOverride)
	return (formatMoneyText(copper, signed, noCopperWhenGold, modeOverride))
end

function Theme.FormatMoneyFable(copper, signed, opts)
	local effSigned = (opts and opts.neutral) and "neutral" or signed
	local effMode = (opts and opts.priceDisplayMode) or Theme.GetPriceDisplayMode()
	local noCop = (effMode == "compact") and true or false
	return (formatMoneyText(copper, effSigned, noCop, effMode))
end

---------------------------------------------------------------------------------------------------
-- Theme-Safe |cff Colour Translation (legacy hardcoded hexes + the other appearance's palette)

-- Legacy WoW-style literals still emitted by the data model (Pricing / Calculators) and older views.
local LEGACY_HEX_ROLES = {
	hexText      = { "ffffff" },
	hexSecondary = { "dddddd", "cccccc", "c8c0b0" },
	hexMuted     = { "b0b0b0", "bbbbbb", "aaaaaa", "9d9d9d", "999999", "888888", "777777", "6e6b64", "6e6e73", "555555" },
	hexPositive  = { "1eff00", "00ff00", "33ff33", "33ff66", "55ff55", "66ee66", "66ee88", "88ff88", "44ff88", "44ffaa",
		"44ee66", "99ee99", "88dd88", "55ff88", "55ee88", "44ddaa" },
	hexBlue      = { "44ddff", "66ccff", "77ddff", "88ddff", "88eeff", "66aaff", "88ccff", "66eeff", "0091ff", "0088ff" },
	hexWarning   = { "ffd100", "ffd200", "ffdf7a", "ffe080", "ffcc00", "ffcc44", "ffcc55", "ffb833", "ffaa33", "ffaa44",
		"ffc844", "ffc855", "eecc55", "ffd244", "ff9944", "ff9933", "ff5533", "b34a00" }, -- ff5533 = "Hot" demand
	hexDanger    = { "ff5555", "ff6644", "ff6666", "ff7744", "ff8844", "ff8888", "ff6655", "d62429" },
	hexPurple    = { "cc88ff", "a335ee" },
}
-- Literals that are already appearance-aware pairs (Theme.FormatSalesPerDay): only swap sides.
local MODE_PAIRED_HEX = {
	{ dark = "7fd4ff", light = "0066cc" }, -- Sales / Day value
}
local PALETTE_HEX_KEYS = {
	"hexText", "hexSecondary", "hexMuted", "hexPositive", "hexBlue", "hexWarning", "hexDanger", "hexPurple",
	"hexGold", "hexSilver", "hexCopper",
}
themeHexMaps = {}

local function themeHexMap(mode)
	local map = themeHexMaps[mode]
	if map then return map end
	local pal = paletteByKey(mode)
	local custom = Theme.SKIN_PALETTES and Theme.SKIN_PALETTES[mode] ~= nil
	local others = { Theme.PALETTES[mode == "light" and "dark" or "light"] }
	if custom then
		-- A Warcraft skin also adopts text baked under Dark, Light and every other Warcraft skin.
		others = { Theme.PALETTES.dark, Theme.PALETTES.light }
		for _, info in ipairs(Theme.UI_SKINS or {}) do
			local sp = Theme.SKIN_PALETTES[info.key]
			if sp and sp ~= pal then others[#others + 1] = sp end
		end
	end
	map = {}
	for role, list in pairs(LEGACY_HEX_ROLES) do
		for _, hex in ipairs(list) do map[hex] = pal[role] end
	end
	-- Text baked while the other appearance was active (cached rows, re-set labels) follows the switch.
	for _, other in ipairs(others) do
		for _, key in ipairs(PALETTE_HEX_KEYS) do
			if other[key] and pal[key] and map[other[key]] == nil then map[other[key]] = pal[key] end
		end
	end
	local otherMode = (mode == "light") and "dark" or "light"
	if custom then otherMode = "light" end
	for _, pair in ipairs(MODE_PAIRED_HEX) do
		map[pair[otherMode]] = pair[custom and "dark" or mode]
	end
	if mode == "light" then map["7a766e"] = pal.hexMuted end -- dark-only Sales / Day zero ink
	-- The active palette always maps onto itself.
	for _, key in ipairs(PALETTE_HEX_KEYS) do
		if pal[key] then map[pal[key]] = pal[key] end
	end
	for _, pair in ipairs(MODE_PAIRED_HEX) do
		local m = custom and "dark" or mode
		map[pair[m]] = pair[m]
	end
	themeHexMaps[mode] = map
	return map
end

-- Cell strings repeat heavily across rows and refreshes: memoize per hex map (bounded, then reset).
local strfind = string.find
local translateMemo = setmetatable({}, { __mode = "k" })
local function translateHex(str, map)
	if type(str) ~= "string" or not strfind(str, "|cff", 1, true) then return str end
	local memo = translateMemo[map]
	if not memo then
		memo = { n = 0 }
		translateMemo[map] = memo
	end
	local hit = memo[str]
	if hit then return hit end
	local out = str:gsub("|cff(%x%x%x%x%x%x)", function(hex)
		local to = map[hex] or map[hex:lower()]
		if to then return "|cff" .. to end
	end)
	if memo.n >= 4096 then
		memo = { n = 0 }
		translateMemo[map] = memo
	end
	memo[str] = out
	memo.n = memo.n + 1
	return out
end

-- Translate every legacy / other-appearance colour code in `str` to the active palette.
function Theme.ThemeText(str)
	return translateHex(str, themeHexMap(paletteKey()))
end

-- GameTooltip keeps its dark Blizzard backdrop in both appearances, so ink baked from the Light
-- palette is lifted back to the Dark palette there. Light-palette hexes only: LEGACY_HEX_ROLES
-- (1eff00, ffd100, a335ee, ...) are Blizzard's own item-quality / spell / quest tooltip colours and
-- the OnShow hook below sees every tooltip in the game.
local tooltipLiftMap
local function lightToDarkTooltipMap()
	if tooltipLiftMap then return tooltipLiftMap end
	local light, dark = Theme.PALETTES.light, Theme.PALETTES.dark
	local map = {}
	for _, key in ipairs(PALETTE_HEX_KEYS) do
		if light[key] and dark[key] and map[light[key]] == nil then map[light[key]] = dark[key] end
	end
	for _, pair in ipairs(MODE_PAIRED_HEX) do
		map[pair.light] = pair.dark
	end
	tooltipLiftMap = map
	return map
end

function Theme.TooltipText(str)
	if not (currentSkin == "standard" and currentMode == "light") then return str end
	return translateHex(str, lightToDarkTooltipMap())
end

-- Route every later SetText on a FontString through Theme.ThemeText.
-- One shared override (no per-widget closure): table rows create dozens of cells per frame.
local function themedSetText(self, text, alreadyThemed)
	-- Plain strings (most cells) and pre-themed cell strings skip the translator entirely
	if not alreadyThemed and type(text) == "string" and strfind(text, "|c", 1, true) then
		local pk = paletteKey()
		text = translateHex(text, themeHexMaps[pk] or themeHexMap(pk))
	end
	return self._mmRawSetText(self, text)
end
function Theme.AutoThemeText(fs)
	if not fs or fs._mmThemedText or not fs.SetText then return fs end
	fs._mmRawSetText = fs.SetText
	fs._mmThemedText = true
	fs.SetText = themedSetText
	return fs
end

-- Theme-translate every cell of a freshly built table row (cells are FontStrings or { fs = FontString }).
function Theme.AutoThemeCells(row)
	for _, cell in ipairs((row and row.cells) or {}) do
		local fs = (type(cell) == "table" and cell.fs) or cell
		if fs and fs.SetText and not fs._mmThemedText then
			Theme.AutoThemeText(fs)
			-- Re-apply only text that already carries a colour code from the row's first fill
			local txt = fs.GetText and fs:GetText()
			if type(txt) == "string" and strfind(txt, "|c", 1, true) then fs:SetText(txt) end
		end
	end
end

-- Light appearance bakes dark ink (black numerals, burnished g / s / c) into money strings; lift it
-- back to the dark palette whenever those strings land on the always-dark GameTooltip.
do
	local LINE_SIDES = { "TextLeft", "TextRight" }
	local function lineText(fs) return fs:GetText() end
	local function liftTooltip(tip)
		if (currentSkin ~= "standard" or currentMode ~= "light") or not tip or not tip.GetName or not tip.NumLines then return end
		local name = tip:GetName()
		if not name then return end
		local map = lightToDarkTooltipMap()
		for i = 1, tip:NumLines() or 0 do
			for s = 1, #LINE_SIDES do
				local fs = _G[name .. LINE_SIDES[s] .. i]
				if fs and fs.GetText then
					local ok, txt = pcall(lineText, fs)
					-- Secret check first: a secret value must not be truth-tested, compared or indexed
					if ok and not (issecretvalue and issecretvalue(txt)) and type(txt) == "string" then
						local lifted = translateHex(txt, map)
						if lifted ~= txt then fs:SetText(lifted) end
					end
				end
			end
		end
	end
	Theme.LiftTooltip = liftTooltip
	for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
		if type(tip) == "table" and tip.HookScript then
			tip:HookScript("OnShow", liftTooltip)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- 9-Slice Rounded Rectangles, Liquid Glass Surfaces, Icons & Cards

local function setTex(tex, path)
	if tex and tex.SetTexture then
		tex:SetTexture(path)
	end
	return tex
end

local function unpackColor(r, g, b, a, fallback)
	if type(r) == "table" then
		return r[1] or 1, r[2] or 1, r[3] or 1, (r[4] ~= nil) and r[4] or 1
	end
	if r ~= nil then
		return r, g or 1, b or 1, (a ~= nil) and a or 1
	end
	if fallback then
		return fallback[1] or 1, fallback[2] or 1, fallback[3] or 1, (fallback[4] ~= nil) and fallback[4] or 1
	end
	return 1, 1, 1, 1
end

local function sliceTex(owner, layer, sub, texPath, l, r, t, b)
	local s = math.max(-8, math.min(7, math.floor(tonumber(sub) or 0)))
	local x = owner:CreateTexture(nil, layer or "BACKGROUND", nil, s)
	setTex(x, texPath)
	if x.SetTexCoord then x:SetTexCoord(l, r, t, b) end
	return x
end

local function resolveIconPath(name)
	if type(name) ~= "string" or name == "" then
		return Theme.ASSETS.icon_grid
	end
	if name:find("\\", 1, true) or name:find("/", 1, true) then
		return name
	end
	if Theme.ASSETS[name] then
		return Theme.ASSETS[name]
	end
	local short = name:gsub("^i%-", ""):gsub("^icon_", "")
	if Theme.ASSETS.icons[short] then
		return Theme.ASSETS.icons[short]
	end
	return APPLE_ROOT .. "icon_" .. short
end

function Theme.AppleIcon(parent, name, size, colorTbl)
	local sz = size or 16
	local ic = parent:CreateTexture(nil, "ARTWORK")
	ic:SetSize(sz, sz)
	setTex(ic, resolveIconPath(name))
	local col = colorTbl or Theme.COLORS.textSecondary
	if ic.SetVertexColor and col then
		ic:SetVertexColor(col[1] or 1, col[2] or 1, col[3] or 1, (col[4] ~= nil) and col[4] or 1)
	end
	return ic
end

local function pill3Slice(owner, anchor, layer, sub, capW, inset, cr, cg, cb, ca, texPath)
	anchor = anchor or owner
	inset = inset or 0
	capW = math.max(4, capW or 16)
	local lef = sliceTex(owner, layer, sub, texPath, 0, 0.5, 0, 1)
	lef:SetWidth(capW)
	lef:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
	lef:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", inset, inset)

	local rig = sliceTex(owner, layer, sub, texPath, 0.5, 1, 0, 1)
	rig:SetWidth(capW)
	rig:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -inset, -inset)
	rig:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)

	local mid = sliceTex(owner, layer, sub, texPath, 0.49, 0.51, 0, 1)
	mid:SetPoint("TOPLEFT", lef, "TOPRIGHT")
	mid:SetPoint("BOTTOMRIGHT", rig, "BOTTOMLEFT")

	local p = { pieces = { lef, mid, rig } }
	function p:SetColor(r, g, b, a)
		local rr, gg, bb, aa = unpackColor(r, g, b, a)
		for _, t in ipairs(self.pieces) do
			if t.SetVertexColor then t:SetVertexColor(rr, gg, bb, aa) end
		end
	end
	function p:SetAlpha(a)
		for _, t in ipairs(self.pieces) do
			if t.SetAlpha then t:SetAlpha(a) end
		end
	end
	function p:SetShown(v)
		for _, t in ipairs(self.pieces) do
			if t.SetShown then t:SetShown(v) elseif v then t:Show() else t:Hide() end
		end
	end
	function p:SetCapWidth(newCapW)
		local w = math.max(4, math.floor((tonumber(newCapW) or capW) + 0.5))
		lef:SetWidth(w)
		rig:SetWidth(w)
	end
	local rr, gg, bb, aa = unpackColor(cr, cg, cb, ca)
	p:SetColor(rr, gg, bb, aa)
	return p
end

function Theme.RoundRect(owner, anchor, layer, sub, c, inset, cr, cg, cb, ca, texPath, opts)
	anchor = anchor or owner
	inset = inset or 0
	local useTex = texPath or RR_TEX
	if useTex == Theme.ASSETS.pill_fill or useTex == Theme.ASSETS.pill_stroke then
		return pill3Slice(owner, anchor, layer, sub, c, inset, cr, cg, cb, ca, useTex)
	end
	local openRight = opts and opts.openRight
	local openLeft = opts and opts.openLeft
	if useTex == Theme.ASSETS.glass_r22_fill then
		if openRight then
			useTex = Theme.ASSETS.glass_r22_openright_fill
		elseif openLeft then
			useTex = Theme.ASSETS.glass_r22_openleft_fill
		end
	end
	local isRing = (useTex == RING_TEX) or (type(useTex) == "string" and useTex:find("_stroke", 1, true) ~= nil)
	local A, B = 0.25, 0.75
	local tlU0, tlU1, tlV0, tlV1 = 0, A, 0, A
	local trU0, trU1, trV0, trV1 = B, 1, 0, A
	local blU0, blU1, blV0, blV1 = 0, A, B, 1
	local brU0, brU1, brV0, brV1 = B, 1, B, 1
	local lefU0, lefU1 = 0, A
	local rigU0, rigU1 = B, 1
	if openRight then
		trU0, trU1 = A, B
		brU0, brU1 = A, B
		if not isRing then rigU0, rigU1 = A, B end
	end
	if openLeft then
		tlU0, tlU1 = A, B
		blU0, blU1 = A, B
		if not isRing then lefU0, lefU1 = A, B end
	end

	local tl  = sliceTex(owner, layer, sub, useTex, tlU0, tlU1, tlV0, tlV1); tl:SetSize(c, c); tl:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
	local tr  = sliceTex(owner, layer, sub, useTex, trU0, trU1, trV0, trV1); tr:SetSize(c, c); tr:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -inset, -inset)
	local bl  = sliceTex(owner, layer, sub, useTex, blU0, blU1, blV0, blV1); bl:SetSize(c, c); bl:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", inset, inset)
	local br  = sliceTex(owner, layer, sub, useTex, brU0, brU1, brV0, brV1); br:SetSize(c, c); br:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)
	local top = sliceTex(owner, layer, sub, useTex, A, B, 0, A); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
	local bot = sliceTex(owner, layer, sub, useTex, A, B, B, 1); bot:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
	local pieces = { tl, tr, bl, br, top, bot }
	if not (isRing and openLeft) then
		local lef = sliceTex(owner, layer, sub, useTex, lefU0, lefU1, A, B)
		lef:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lef:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
		pieces[#pieces + 1] = lef
	end
	if not (isRing and openRight) then
		local rig = sliceTex(owner, layer, sub, useTex, rigU0, rigU1, A, B)
		rig:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); rig:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
		pieces[#pieces + 1] = rig
	end
	local p = { pieces = pieces }
	if not isRing then
		local mid = sliceTex(owner, layer, sub, useTex, A, B, A, B)
		mid:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
		mid:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
		p.pieces[#p.pieces + 1] = mid
	end
	function p:SetColor(r, g, b, a)
		local rr, gg, bb, aa = unpackColor(r, g, b, a)
		for _, t in ipairs(self.pieces) do
			if t.SetVertexColor then t:SetVertexColor(rr, gg, bb, aa) end
		end
	end
	function p:SetAlpha(a)
		for _, t in ipairs(self.pieces) do
			if t.SetAlpha then t:SetAlpha(a) end
		end
	end
	function p:SetShown(v)
		for _, t in ipairs(self.pieces) do
			if t.SetShown then t:SetShown(v) elseif v then t:Show() else t:Hide() end
		end
	end
	local rr, gg, bb, aa = unpackColor(cr, cg, cb, ca)
	p:SetColor(rr, gg, bb, aa)
	return p
end

function Theme.Nine(owner, anchor, texPath, c, out, layer, sub, opts)
	anchor = anchor or owner
	out = out or 0
	local openRight = opts and opts.openRight
	local openLeft = opts and opts.openLeft
	local useTex = texPath
	if useTex == Theme.ASSETS.glass_r22_fill then
		if openRight then
			useTex = Theme.ASSETS.glass_r22_openright_fill
		elseif openLeft then
			useTex = Theme.ASSETS.glass_r22_openleft_fill
		end
	end
	local A, B = 0.25, 0.75
	local tl  = sliceTex(owner, layer, sub, useTex, openLeft and A or 0, openLeft and B or A, 0, A); tl:SetSize(c, c); tl:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
	local tr  = sliceTex(owner, layer, sub, useTex, openRight and A or B, openRight and B or 1, 0, A); tr:SetSize(c, c); tr:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out)
	local bl  = sliceTex(owner, layer, sub, useTex, openLeft and A or 0, openLeft and B or A, B, 1); bl:SetSize(c, c); bl:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
	local br  = sliceTex(owner, layer, sub, useTex, openRight and A or B, openRight and B or 1, B, 1); br:SetSize(c, c); br:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
	local top = sliceTex(owner, layer, sub, useTex, A, B, 0, A); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
	local bot = sliceTex(owner, layer, sub, useTex, A, B, B, 1); bot:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
	local lef = sliceTex(owner, layer, sub, useTex, openLeft and A or 0, openLeft and B or A, A, B); lef:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lef:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
	local rig = sliceTex(owner, layer, sub, useTex, openRight and A or B, openRight and B or 1, A, B); rig:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); rig:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
	local mid = sliceTex(owner, layer, sub, useTex, A, B, A, B); mid:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); mid:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
	local o = { pieces = { tl, tr, bl, br, top, bot, lef, rig, mid } }
	function o:SetShown(v)
		for _, t in ipairs(self.pieces) do
			if t.SetShown then t:SetShown(v) elseif v then t:Show() else t:Hide() end
		end
	end
	function o:SetAlpha(a)
		for _, t in ipairs(self.pieces) do if t.SetAlpha then t:SetAlpha(a) end end
	end
	function o:SetColor(r, g, b, a)
		local rr, gg, bb, aa = unpackColor(r, g, b, a)
		for _, t in ipairs(self.pieces) do
			if t.SetVertexColor then t:SetVertexColor(rr, gg, bb, aa) end
		end
	end
	function o:SetDesaturated(v)
		for _, t in ipairs(self.pieces) do
			if t.SetDesaturated then t:SetDesaturated(v and true or false) end
		end
	end
	return o
end

-- Apply a true WoW linear gradient to a Texture:
--   orientation == "HORIZONTAL": c1 = LEFT, c2 = RIGHT
--   orientation == "VERTICAL":   c1 = TOP,  c2 = BOTTOM
-- WoW Texture:SetGradient("VERTICAL", minColor, maxColor) treats minColor as BOTTOM (y=0) and maxColor as TOP (y=1).
function Theme.SetGradientFill(tex, orientation, c1, c2)
	if not tex or not c1 or not c2 then return end
	local dir = (orientation == "VERTICAL") and "VERTICAL" or "HORIZONTAL"
	local minC = (dir == "VERTICAL") and c2 or c1
	local maxC = (dir == "VERTICAL") and c1 or c2
	local r1, g1, b1, a1 = minC[1] or 0, minC[2] or 0, minC[3] or 0, (minC[4] ~= nil) and minC[4] or 1
	local r2, g2, b2, a2 = maxC[1] or 0, maxC[2] or 0, maxC[3] or 0, (maxC[4] ~= nil) and maxC[4] or 1
	if tex.SetColorTexture then tex:SetColorTexture(1, 1, 1, 1) end
	if tex.SetGradient and CreateColor then
		tex:SetGradient(dir, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
	elseif tex.SetGradientAlpha then
		tex:SetGradientAlpha(dir, r1, g1, b1, a1, r2, g2, b2, a2)
	elseif tex.SetColorTexture then
		tex:SetColorTexture((r1 + r2) * 0.5, (g1 + g2) * 0.5, (b1 + b2) * 0.5, (a1 + a2) * 0.5)
	end
end

local APPLE_SURFACE_META = {
	glass_r22 = { fill = "glass_r22_fill", stroke = "glass_r22_stroke", c = 22, defaultFill = "winBg",     defaultStroke = "windowEdge",  specular = true  },
	glass_r16 = { fill = "glass_r16_fill", stroke = "glass_r16_stroke", c = 16, defaultFill = "toolbarBg", defaultStroke = "glassBorder", specular = true  },
	glass_r12 = { fill = "glass_r12_fill", stroke = "glass_r12_stroke", c = 12, defaultFill = "cardBg",    defaultStroke = false,         specular = false },
	glass_r10 = { fill = "glass_r10_fill", stroke = "glass_r10_stroke", c = 16, defaultFill = "cardBg",    defaultStroke = false,         specular = false },
	glass_r8  = { fill = "glass_r8_fill",  stroke = "glass_r8_stroke",  c = 16, defaultFill = "cardAltBg", defaultStroke = false,         specular = false },
	glass_r4  = { fill = "glass_r8_fill",  stroke = "glass_r8_stroke",  c = 4,  defaultFill = "cardAltBg", defaultStroke = false,         specular = false },
	pill      = { fill = "pill_fill",      stroke = "pill_stroke",      c = 16, defaultFill = "pillTrack", defaultStroke = false,         specular = false },
}

local function normalizeAppleKind(kind)
	if type(kind) ~= "string" then return "glass_r10" end
	if APPLE_SURFACE_META[kind] then return kind end
	if APPLE_SURFACE_META["glass_" .. kind] then return "glass_" .. kind end
	return "glass_r10"
end

function Theme.NineApple(frame, kind, fillColor, strokeColor, inset)
	local k = normalizeAppleKind(kind)
	local meta = APPLE_SURFACE_META[k]
	local opts = type(inset) == "table" and inset or { inset = tonumber(inset) or 0 }
	local pad = opts.inset or 0
	local anchor = opts.anchor or frame
	local layer = opts.layer or "BACKGROUND"
	local sub = opts.sub or 0

	local c = opts.cornerSize or meta.c
	local aw = (anchor.GetWidth and anchor:GetWidth()) or 0
	local ah = (anchor.GetHeight and anchor:GetHeight()) or 0
	if k == "pill" and not opts.cornerSize then
		local h = (ah > 0) and ah or 32
		c = math.max(4, math.min(24, math.floor(h * 0.5)))
	end
	if aw > 0 then c = math.min(c, math.floor(aw * 0.5)) end
	if ah > 0 then c = math.min(c, math.floor(ah * 0.5)) end
	c = math.max(1, c)

	local fillTex = Theme.ASSETS[meta.fill]
	if k == "glass_r22" then
		if opts.openRight then
			fillTex = Theme.ASSETS.glass_r22_openright_fill
		elseif opts.openLeft then
			fillTex = Theme.ASSETS.glass_r22_openleft_fill
		end
	end
	local strokeTex = Theme.ASSETS[meta.stroke]

	local function resolveCol(spec, fallbackKey)
		if spec == false then return nil end
		if spec == nil then
			if fallbackKey == false or fallbackKey == nil then return nil end
			return Theme.COLORS[fallbackKey]
		end
		if type(spec) == "string" then return Theme.COLORS[spec] or (fallbackKey and Theme.COLORS[fallbackKey]) end
		if type(spec) == "table" then return spec end
		return fallbackKey and Theme.COLORS[fallbackKey] or nil
	end

	local fc = resolveCol(fillColor, meta.defaultFill)
	local sc = resolveCol(strokeColor, meta.defaultStroke)
	local wantSpec = opts.specular
	if wantSpec == nil then wantSpec = meta.specular end
	local rimOnly = not sc and wantSpec and not opts.noSpecular
	local sliceOpts = (opts.openRight or opts.openLeft) and { openRight = opts.openRight, openLeft = opts.openLeft } or nil

	local surface = { kind = k }
	if fc then
		surface.fill = Theme.RoundRect(frame, anchor, layer, sub, c, pad, fc[1], fc[2], fc[3], fc[4] or 1, fillTex, sliceOpts)
	end
	if sc or rimOnly then
		local strokeLayer = opts.strokeLayer or ((layer == "BACKGROUND") and "BORDER" or layer)
		local color = sc or Theme.COLORS.glassBorder
		local ring = Theme.RoundRect(frame, anchor, strokeLayer, math.min(7, sub + 1), c, pad, color[1], color[2], color[3], color[4] or 1, strokeTex, sliceOpts)
		if rimOnly then
			-- Borderless controls can refresh their fill and keep the optical rim.
			surface.rim = ring
		else
			surface.stroke = ring
		end
	end

	function surface:SetFill(r, g, b, a)
		if self.fill then self.fill:SetColor(r, g, b, a) end
	end
	function surface:SetStroke(r, g, b, a)
		if self.stroke then self.stroke:SetColor(r, g, b, a) end
	end
	surface.SetBorder = surface.SetStroke
	function surface:SetShown(v)
		if self.fill then self.fill:SetShown(v) end
		local ring = self.stroke or self.rim
		if ring then ring:SetShown(v) end
	end
	function surface:SetAlpha(a)
		if self.fill then self.fill:SetAlpha(a) end
		local ring = self.stroke or self.rim
		if ring then ring:SetAlpha(a) end
	end
	function surface:SetCapWidth(capW)
		if self.fill and self.fill.SetCapWidth then self.fill:SetCapWidth(capW) end
		local ring = self.stroke or self.rim
		if ring and ring.SetCapWidth then ring:SetCapWidth(capW) end
	end
	function surface:UpdateTheme(newFill, newStroke)
		if newFill ~= nil then
			local nf = resolveCol(newFill, meta.defaultFill)
			if self.fill and nf then self.fill:SetColor(nf[1], nf[2], nf[3], nf[4] or 1) end
		elseif fillColor == nil or type(fillColor) == "string" then
			local nf = resolveCol(fillColor, meta.defaultFill)
			if self.fill and nf then self.fill:SetColor(nf[1], nf[2], nf[3], nf[4] or 1) end
		end
		if newStroke ~= nil then
			if newStroke == false then
				if self.stroke then self.stroke:SetShown(false) end
			else
				local nsCol = resolveCol(newStroke, meta.defaultStroke)
				if self.stroke and nsCol then
					self.stroke:SetShown(true)
					self.stroke:SetColor(nsCol[1], nsCol[2], nsCol[3], nsCol[4] or 1)
				end
			end
		elseif strokeColor == nil or type(strokeColor) == "string" then
			local nsCol = resolveCol(strokeColor, meta.defaultStroke)
			if self.stroke and nsCol then self.stroke:SetColor(nsCol[1], nsCol[2], nsCol[3], nsCol[4] or 1) end
		end
		if self.rim then self.rim:SetColor(Theme.COLORS.glassBorder) end
	end

	if fillColor == nil or type(fillColor) == "string" or (strokeColor == nil and meta.defaultStroke) or type(strokeColor) == "string" or surface.rim then
		Theme.RegisterWidget(surface, function() surface:UpdateTheme() end)
	end

	return surface
end

function Theme.Card(owner, anchor, c, border, fill, layer, sub)
	layer = layer or "BACKGROUND"
	sub = sub or 0
	anchor = anchor or owner
	local radius = c or 10
	local kind = (radius >= 16 and "glass_r16") or (radius >= 12 and "glass_r12") or (radius <= 6 and "glass_r8") or "glass_r10"
	local meta = APPLE_SURFACE_META[kind]
	local autoFill = (fill == nil)
	local fc = fill or Theme.COLORS.cardBg

	local card = {}
	if type(border) == "table" then
		card.border = Theme.RoundRect(owner, anchor, layer, math.min(7, sub + 1), meta.c, 0, border[1], border[2], border[3], border[4] or 1, Theme.ASSETS[meta.stroke])
	end
	card.fill = Theme.RoundRect(owner, anchor, layer, sub, meta.c, 0, fc[1], fc[2], fc[3], fc[4] or 1, Theme.ASSETS[meta.fill])
	function card:SetBorder(r, g, b, a)
		if self.border then self.border:SetColor(r, g, b, a) end
	end
	function card:SetFill(r, g, b, a) self.fill:SetColor(r, g, b, a) end
	function card:SetShown(v)
		if self.border then self.border:SetShown(v) end
		self.fill:SetShown(v)
	end
	if autoFill then
		Theme.RegisterWidget(card, function(_, pal)
			if autoFill then card:SetFill(pal.cardBg[1], pal.cardBg[2], pal.cardBg[3], pal.cardBg[4] or 1) end
		end)
	end
	return card
end

local function hideTemplateChrome(f)
	if not f then return end
	if type(f.NineSlice) == "table" and f.NineSlice.SetAlpha then f.NineSlice:SetAlpha(0) end
	if type(f.Bg) == "table" and f.Bg.SetAlpha then f.Bg:SetAlpha(0) end
	for _, k in ipairs({
		"TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner",
		"TopBorder", "BottomBorder", "LeftBorder", "RightBorder",
		"InsetBorderTop", "InsetBorderBottom", "InsetBorderLeft", "InsetBorderRight",
		"InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottomLeft", "InsetBorderBottomRight",
	}) do
		if type(f[k]) == "table" and f[k].SetAlpha then f[k]:SetAlpha(0) end
	end
end

function Theme.FramedPanel(f, fillCol, borderCol)
	if not f or f._mmFramed then return f and f._mmCard end
	f._mmFramed = true
	hideTemplateChrome(f)
	for _, r in ipairs(f.GetRegions and { f:GetRegions() } or {}) do
		if r.GetObjectType and r:GetObjectType() == "Texture" and r.SetAlpha then
			r:SetAlpha(0)
		end
	end
	local autoFill = (fillCol == nil)
	local fc = fillCol or Theme.COLORS.cardBg
	local fill = Theme.RoundRect(f, f, "BACKGROUND", 0, 16, 0, fc[1], fc[2], fc[3], fc[4] or 1, Theme.ASSETS.glass_r10_fill)
	local ring
	if type(borderCol) == "table" then
		ring = Theme.RoundRect(f, f, "OVERLAY", 3, 16, 0, borderCol[1], borderCol[2], borderCol[3], borderCol[4] or 0.85, Theme.ASSETS.glass_r10_stroke)
	end
	f._mmCard = { fill = fill, border = ring }
	if autoFill then
		Theme.RegisterWidget(f._mmCard, function(_, pal)
			if autoFill then fill:SetColor(pal.cardBg[1], pal.cardBg[2], pal.cardBg[3], pal.cardBg[4] or 1) end
		end)
	end
	return f._mmCard
end

function Theme.WindowFrame(deco, frame)
	local pCol = Theme.COLORS.windowEdge or Theme.COLORS.perimeter
	local ring = Theme.RoundRect(deco, frame, "OVERLAY", 0, 22, 0, pCol[1], pCol[2], pCol[3], pCol[4] or 0.14, Theme.ASSETS.glass_r22_stroke)
	Theme.RegisterWidget(ring, function(_, pal)
		local pe = pal.windowEdge or pal.perimeter
		ring:SetColor(pe[1], pe[2], pe[3], pe[4] or 0.14)
		-- Warcraft skins draw their own metallic frame chrome instead of the Modern Glass ring.
		if ring.SetShown then ring:SetShown(not Theme.IsCustomSkin()) end
	end)
	if ring.SetShown and Theme.IsCustomSkin() then ring:SetShown(false) end
	return ring
end

---------------------------------------------------------------------------------------------------
-- Apple HIG Buttons, Pill Switches, EditBoxes & Slim Scrollbars

local function resolveButtonVariant(opts)
	if opts.variant then return opts.variant end
	if opts.primary then return "primary" end
	if opts.danger then return "danger" end
	if opts.ghost then return "ghost" end
	return "secondary"
end

local function buttonPalette(variant, active, pal, withBorder)
	if variant == "primary" then
		return pal.accentBlue, withBorder and { 1, 1, 1, 0.30 } or { 0, 0, 0, 0 }, pal.textOnAccent
	elseif variant == "danger" then
		local ar = pal.accentRed
		if pal.mode == "light" then
			return { ar[1], ar[2], ar[3], 0.11 }, withBorder and { ar[1], ar[2], ar[3], 0.32 } or { 0, 0, 0, 0 }, ar
		end
		return { ar[1], ar[2], ar[3], 0.16 }, withBorder and { ar[1], ar[2], ar[3], 0.45 } or { 0, 0, 0, 0 }, pal.textGlass
	elseif variant == "ghost" then
		if active then
			return pal.pillThumb, withBorder and pal.border or { 0, 0, 0, 0 }, pal.text
		end
		return { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, pal.textSecondary
	elseif variant == "badge" then
		return pal.glassFill or pal.pillTrack, { 0, 0, 0, 0 }, pal.textSecondary
	else -- secondary
		if active then
			return pal.pillThumb, withBorder and pal.borderStrong or { 0, 0, 0, 0 }, pal.text
		end
		return pal.pillTrack, withBorder and pal.border or { 0, 0, 0, 0 }, pal.text
	end
end

local function attachApplePlate(b, h, opts)
	local variant = resolveButtonVariant(opts)
	local withBorder = opts.border == true
	local primaryRim = variant == "primary" and not opts.noSpecular
	local isPill = (opts.pill == true) or (variant == "primary" and opts.pill ~= false)
	local c = isPill and math.max(6, math.floor((h or 28) * 0.5)) or math.min(16, math.max(6, math.floor((h or 22) * 0.45)))
	local fillTex = isPill and Theme.ASSETS.pill_fill or Theme.ASSETS.glass_r8_fill
	local strokeTex = isPill and Theme.ASSETS.pill_stroke or Theme.ASSETS.glass_r8_stroke

	local normal = Theme.RoundRect(b, b, "BACKGROUND", 0, c, 0, 1, 1, 1, 1, fillTex)
	local stroke
	if withBorder or primaryRim then
		stroke = Theme.RoundRect(b, b, "BORDER", 0, c, 0, 1, 1, 1, 1, strokeTex)
	end
	local hover = Theme.RoundRect(b, b, "HIGHLIGHT", 0, c, 0, 1, 1, 1, 0.08, fillTex)

	local p = { active = false, enabled = true, variant = variant }
	local function paint()
		local pal = Theme.GetActivePalette()
		local isLight = (pal.mode == "light")
		local variant = opts.readableDisabled and not p.enabled and "secondary" or p.variant
		local fc, sc = buttonPalette(variant, p.active, pal, withBorder or (primaryRim and variant == "primary"))
		local alphaMul = p.enabled and 1 or 0.45
		normal:SetColor(fc[1], fc[2], fc[3], (fc[4] or 1) * alphaMul)
		if stroke then
			stroke:SetColor(sc[1], sc[2], sc[3], (sc[4] or 1) * alphaMul)
		end
		if isLight then
			hover:SetColor(0, 0, 0, 0.05)
		else
			hover:SetColor(1, 1, 1, 0.08)
		end
		hover:SetShown(p.enabled)
	end
	function p:SetActive(on)
		self.active = on and true or false
		paint()
	end
	function p:SetEnabledLook(en)
		self.enabled = en and true or false
		paint()
	end
	function p:UpdateTheme()
		paint()
	end
	paint()
	return p
end

function Theme.SkinButton(b, opts)
	if not b or b._mmSkinned then return b end
	b._mmSkinned = true
	opts = opts or {}
	for _, k in ipairs({ "Left", "Middle", "Right" }) do
		if type(b[k]) == "table" and b[k].SetAlpha then b[k]:SetAlpha(0) end
	end
	for _, fn in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local t = b[fn] and b[fn](b)
		if t and t.SetAlpha then t:SetAlpha(0) end
	end

	local h = (b.GetHeight and b:GetHeight()) or 22
	local plate = attachApplePlate(b, h, opts)
	b._mmPlate = plate

	local fs = (b.GetFontString and b:GetFontString()) or b.fs
	if not fs then
		fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("CENTER", 0, 0)
		if b.SetFontString then b:SetFontString(fs) end
	end
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
	b._mmLabel = fs
	local weight = opts.weight or (plate.variant == "primary" and "semibold" or "regular")
	Theme.ApplyFont(fs, opts.fontSize or 12, weight)

	local function syncLabelColor()
		local pal = Theme.GetActivePalette()
		local _, _, tc = buttonPalette(plate.variant, plate.active, pal, opts.border == true)
		if not plate.enabled then
			local muted = pal.textMuted
			if fs.SetTextColor then fs:SetTextColor(muted[1], muted[2], muted[3], opts.readableDisabled and 1 or 0.7) end
		else
			if fs.SetTextColor then fs:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1) end
		end
		if b._mmIcon and b._mmIcon.SetVertexColor then
			b._mmIcon:SetVertexColor(tc[1], tc[2], tc[3], plate.enabled and (tc[4] or 1) or 0.5)
		end
		if b._mmDropArrow and b._mmDropArrow.SetVertexColor then
			local sc = pal.textSecondary
			b._mmDropArrow:SetVertexColor(sc[1], sc[2], sc[3], sc[4] or 0.8)
		end
	end

	local iconSize = opts.iconSize or math.max(12, h - 8)
	local function layoutIconAndText()
		if not b._mmIcon then return end
		local ic = b._mmIcon
		ic:ClearAllPoints()
		local txt = fs and fs.GetText and fs:GetText() or ""
		if txt ~= "" and not opts.dropdown then
			local strW = (fs.GetStringWidth and fs:GetStringWidth()) or (#txt * 6)
			local totalW = iconSize + 6 + strW
			ic:SetPoint("LEFT", b, "CENTER", -totalW * 0.5, 0)
			if fs.ClearAllPoints then
				fs:ClearAllPoints()
				fs:SetPoint("LEFT", ic, "RIGHT", 6, 0)
			end
		else
			ic:SetPoint("CENTER", 0, 0)
		end
	end

	if opts.icon then
		local ic = b:CreateTexture(nil, "ARTWORK")
		ic:SetSize(iconSize, iconSize)
		setTex(ic, resolveIconPath(opts.icon))
		b._mmIcon = ic
		layoutIconAndText()
	end

	if opts.dropdown then
		local arrow = b:CreateTexture(nil, "OVERLAY")
		arrow:SetSize(10, 10)
		arrow:SetPoint("RIGHT", b, "RIGHT", -8, 0)
		setTex(arrow, Theme.ASSETS.icon_chevron_down)
		b._mmDropArrow = arrow
		if fs.ClearAllPoints then
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", b, "LEFT", 9, 0)
			fs:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
			fs:SetJustifyH("LEFT")
		end
	end

	syncLabelColor()

	if opts.icon and b.SetText then
		local origSetText = b.SetText
		function b:SetText(t)
			origSetText(self, t)
			if fs and fs.SetText then fs:SetText(t) end
			layoutIconAndText()
		end
	end

	function b:SetActive(on)
		plate:SetActive(on)
		syncLabelColor()
	end
	function b:SetVariant(v)
		plate.variant = v or "secondary"
		Theme.ApplyFont(fs, opts.fontSize or 12, opts.weight or (plate.variant == "primary" and "semibold" or "regular"))
		layoutIconAndText()
		plate:UpdateTheme()
		syncLabelColor()
	end

	local origSetEnabled = b.SetEnabled
	if origSetEnabled then
		function b:SetEnabled(en)
			origSetEnabled(self, en)
			plate:SetEnabledLook(en and true or false)
			syncLabelColor()
		end
	end

	if b.HookScript and not opts.icon then
		b:HookScript("OnMouseDown", function(self)
			if not self.IsEnabled or self:IsEnabled() then
				if opts.dropdown then
					fs:ClearAllPoints(); fs:SetPoint("LEFT", self, "LEFT", 10, -1); fs:SetPoint("RIGHT", self._mmDropArrow, "LEFT", -3, -1)
				else
					fs:ClearAllPoints(); fs:SetPoint("CENTER", 0, -1)
				end
			end
		end)
		b:HookScript("OnMouseUp", function(self)
			if opts.dropdown then
				fs:ClearAllPoints(); fs:SetPoint("LEFT", self, "LEFT", 9, 0); fs:SetPoint("RIGHT", self._mmDropArrow, "LEFT", -4, 0)
			else
				fs:ClearAllPoints(); fs:SetPoint("CENTER", 0, 0)
			end
		end)
	end

	Theme.RegisterWidget(b, function()
		plate:UpdateTheme()
		syncLabelColor()
	end)

	return b
end

function Theme.CreatePlateButton(parent, text, w, h, opts)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 100, h or 24)
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("CENTER", 0, 0)
	fs:SetWordWrap(false)
	fs:SetText(text or "")
	if b.SetFontString then b:SetFontString(fs) end
	b.fs = fs
	return Theme.SkinButton(b, opts)
end

-- Apple HIG 34x18 Pill Switch for CheckButtons
local SW_W, SW_H = 34, 18

function Theme.SkinCheckButton(cb, opts)
	if not cb or cb._mmPillSwitch then return cb end
	cb._mmPillSwitch = true
	opts = opts or {}
	for _, fn in ipairs({
		"GetNormalTexture", "GetPushedTexture", "GetHighlightTexture",
		"GetCheckedTexture", "GetDisabledCheckedTexture", "GetDisabledTexture",
	}) do
		local t = cb[fn] and cb[fn](cb)
		if t then
			if t.SetTexture then t:SetTexture(nil) end
			if t.SetAlpha then t:SetAlpha(0) end
		end
	end

	local origSetSize = cb.SetSize
	function cb:SetSize(_, h)
		origSetSize(self, SW_W + 6, math.max(h or SW_H, SW_H))
	end
	cb:SetSize(SW_W, cb.GetHeight and cb:GetHeight() or SW_H)

	local pill = CreateFrame("Frame", nil, cb)
	pill:SetSize(SW_W, SW_H)
	pill:SetPoint("CENTER", 0, 0)
	local track = Theme.RoundRect(cb, pill, "ARTWORK", 0, SW_H / 2, 0, 1, 1, 1, 1, PILL_TEX)
	local hov = Theme.RoundRect(cb, pill, "HIGHLIGHT", 0, SW_H / 2, 0, 1, 1, 1, 0.08, PILL_TEX)
	local knob = cb:CreateTexture(nil, "OVERLAY")
	knob:SetSize(14, 14)
	setTex(knob, Theme.ASSETS.circle_fill)

	local function hideDuplicateLabels(primaryFs)
		for _, cand in ipairs({ cb.Text, cb.text }) do
			if type(cand) == "table" and cand ~= primaryFs then
				if cand.SetText then cand:SetText("") end
				if cand.Hide then cand:Hide() end
				if cand.SetAlpha then cand:SetAlpha(0) end
			end
		end
		if cb.GetRegions then
			for _, r in ipairs({ cb:GetRegions() }) do
				if r ~= primaryFs and r.GetObjectType and r:GetObjectType() == "FontString" then
					if r.SetText then r:SetText("") end
					if r.Hide then r:Hide() end
					if r.SetAlpha then r:SetAlpha(0) end
				end
			end
		end
	end

	local function paint()
		local pal = Theme.GetActivePalette()
		local on = cb.GetChecked and cb:GetChecked() and true or false
		local en = (not cb.IsEnabled) or (cb:IsEnabled() and true or false)
		local tr = on and pal.accentGreen or pal.pillTrack
		local readableDisabled = opts.readableDisabled and not en
		local trackAlpha = (tr[4] or 1) * (readableDisabled and 0.45 or 1)
		track:SetColor(tr[1], tr[2], tr[3], trackAlpha)
		if knob.SetVertexColor then knob:SetVertexColor(1, 1, 1, readableDisabled and 0.45 or 1) end
		knob:ClearAllPoints()
		knob:SetPoint(on and "RIGHT" or "LEFT", pill, on and "RIGHT" or "LEFT", on and -2 or 2, 0)
		if cb.SetAlpha then cb:SetAlpha((en or readableDisabled) and 1 or 0.45) end
		hov:SetShown(en)
		local lbl = cb.label or cb.Text or cb.text
		hideDuplicateLabels(lbl)
		if lbl and lbl.SetTextColor then
			local tc = readableDisabled and pal.textMuted or (on and pal.text or pal.textSecondary)
			lbl:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
	end

	local origSetChecked = cb.SetChecked
	if origSetChecked then
		function cb:SetChecked(v) origSetChecked(self, v); paint() end
	end
	local origSetEnabled = cb.SetEnabled
	if origSetEnabled then
		function cb:SetEnabled(v) origSetEnabled(self, v); paint() end
	end
	if cb.SetScript then cb:SetScript("PostClick", paint) end
	if cb.HookScript then cb:HookScript("OnShow", paint) end

	local fs = cb.label or cb.Text or cb.text
	hideDuplicateLabels(fs)
	if type(fs) == "table" and fs.ClearAllPoints then
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
		if fs.SetWordWrap then fs:SetWordWrap(false) end
		if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
		Theme.ApplyFont(fs, 12, "regular")
	end
	paint()
	Theme.RegisterWidget(cb, paint)
	return cb
end

function Theme.StyleEditBox(box, opts)
	if not box or box._mmStyled then return box end
	box._mmStyled = true
	opts = opts or {}
	for _, k in ipairs({ "Left", "Middle", "Right" }) do
		if type(box[k]) == "table" and box[k].SetAlpha then box[k]:SetAlpha(0) end
	end
	for _, r in ipairs(box.GetRegions and { box:GetRegions() } or {}) do
		if r.GetObjectType and r:GetObjectType() == "Texture" and r.SetAlpha then r:SetAlpha(0) end
	end
	local leftPad = opts.leftInset or 10
	local rightPad = opts.rightInset or (opts.withClear and 24 or 10)
	if box.SetTextInsets then box:SetTextInsets(leftPad, rightPad, 0, 0) end
	Theme.ApplyFont(box, opts.fontSize or 12, "regular")

	local kind = (opts.pill == false) and "glass_r8" or "pill"
	local focused = false
	local withBorder = (opts.border == true)
	local card = Theme.NineApple(box, kind, "inputBg", withBorder and "border" or false, { noSpecular = true })
	box._mmCard = card

	local function syncBoxColors()
		local pal = Theme.GetActivePalette()
		card:SetFill(pal.inputBg[1], pal.inputBg[2], pal.inputBg[3], pal.inputBg[4] or 1)
		if card.stroke then
			local sc = focused and pal.accentBlue or pal.border
			card:SetStroke(sc[1], sc[2], sc[3], sc[4] or 1)
		end
		if box.SetTextColor then
			local tc = pal.text
			box:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
	end
	syncBoxColors()

	if box.HookScript and card.stroke then
		box:HookScript("OnEditFocusGained", function()
			focused = true
			local ac = Theme.GetActivePalette().accentBlue
			card:SetStroke(ac[1], ac[2], ac[3], ac[4] or 1)
		end)
		box:HookScript("OnEditFocusLost", function()
			focused = false
			local bc = Theme.GetActivePalette().border
			card:SetStroke(bc[1], bc[2], bc[3], bc[4] or 1)
		end)
	end

	if opts.withClear then
		local clr = Theme.CreatePlateButton(box:GetParent(), "", 20, 20, { icon = Theme.ASSETS.icon_close, iconSize = 10, variant = "ghost", pill = true })
		clr:SetPoint("LEFT", box, "RIGHT", 3, 0)
		clr:Hide()
		clr:SetScript("OnClick", function()
			box:SetText("")
			if box.ClearFocus then box:ClearFocus() end
		end)
		box._mmClearBtn = clr
	end

	Theme.RegisterWidget(box, syncBoxColors)
	return box
end

-- 4px Slim ScrollBar (supports both MinimalScrollBar and UIPanelScrollFrameTemplate)
function Theme.SlimScrollBar(bar)
	if type(bar) ~= "table" or bar._mmSlim then return bar end
	bar._mmSlim = true
	for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton", "Back", "Forward" }) do
		local btn = bar[k]
		if type(btn) == "table" then
			if btn.SetAlpha then btn:SetAlpha(0) end
			if btn.EnableMouse then btn:EnableMouse(false) end
		end
	end

	local trkTex, thTex
	local function paintScroll(_, pal)
		pal = pal or Theme.GetActivePalette()
		local isLight = (pal.mode == "light")
		if trkTex and trkTex.SetColorTexture then
			if isLight then trkTex:SetColorTexture(0, 0, 0, 0.05) else trkTex:SetColorTexture(1, 1, 1, 0.05) end
		end
		if thTex and thTex.SetColorTexture then
			if isLight then thTex:SetColorTexture(0, 0, 0, 0.28) else thTex:SetColorTexture(1, 1, 1, 0.28) end
		end
	end

	if bar.Track and type(bar.Track) == "table" then
		for _, r in ipairs(bar.Track.GetRegions and { bar.Track:GetRegions() } or {}) do
			if r.SetAlpha then r:SetAlpha(0) end
		end
		trkTex = bar.Track:CreateTexture(nil, "BACKGROUND")
		trkTex:SetPoint("TOP", 0, 0)
		trkTex:SetPoint("BOTTOM", 0, 0)
		trkTex:SetWidth(4)
		local thumb = bar.Track.Thumb
		if type(thumb) == "table" then
			for _, r in ipairs(thumb.GetRegions and { thumb:GetRegions() } or {}) do
				if r.SetAlpha then r:SetAlpha(0) end
			end
			thTex = thumb:CreateTexture(nil, "ARTWORK")
			thTex:SetPoint("TOP", 0, 0)
			thTex:SetPoint("BOTTOM", 0, 0)
			thTex:SetWidth(4)
		end
	elseif bar.GetRegions then
		local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
		for _, r in ipairs({ bar:GetRegions() }) do
			if r ~= thumb and r.GetObjectType and r:GetObjectType() == "Texture" and r.SetAlpha then r:SetAlpha(0) end
		end
		trkTex = bar:CreateTexture(nil, "BACKGROUND")
		trkTex:SetPoint("TOP", 0, 0)
		trkTex:SetPoint("BOTTOM", 0, 0)
		trkTex:SetWidth(4)
		if thumb and thumb.SetColorTexture then
			thTex = thumb
			thTex:SetWidth(4)
		end
	end
	paintScroll(Theme.GetMode(), Theme.GetActivePalette())
	Theme.RegisterWidget(bar, paintScroll)
	return bar
end

---------------------------------------------------------------------------------------------------
-- Fable 5.2 Design 1 Apple HIG Components (Section 5 Contracts)

function Theme.CreateSegmentedControl(parent, items, opts)
	opts = opts or {}
	local height = opts.height or 32
	local pad = opts.padding or 2
	local gap = opts.gap or 2
	local fontSize = opts.fontSize or 12

	local frame = CreateFrame("Frame", nil, parent)
	frame:SetHeight(height)
	local withBorder = (opts.border == true)
	local track = Theme.NineApple(frame, "pill", "pillTrack", withBorder and "border" or false, { noSpecular = true })

	local thumb = CreateFrame("Frame", nil, frame)
	if frame.GetFrameLevel and thumb.SetFrameLevel then
		thumb:SetFrameLevel(frame:GetFrameLevel() + 1)
	end
	local thumbBg = Theme.NineApple(thumb, "pill", "pillThumb", false, { noSpecular = true })

	local buttons = {}
	local ordered = {}
	local activeKey = opts.activeKey or (items and items[1] and items[1].key)
	local x = pad

	local ctrl = {
		frame = frame,
		buttons = buttons,
		track = track,
		thumb = thumb,
		thumbBg = thumbBg,
	}

	local function syncVisuals()
		local pal = Theme.GetActivePalette()
		if frame._mmSkinFramed == true then
			if track and track.SetShown then track:SetShown(false) end
			if thumbBg and thumbBg.SetShown then thumbBg:SetShown(false) end
			for _, item in ipairs(ordered) do
				local btn = item.button
				local on = (item.key == activeKey)
				local tc = on and pal.text or pal.textSecondary
				if btn._label and btn._label.SetTextColor then
					btn._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
				end
				if on then
					thumb:ClearAllPoints()
					thumb:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
					thumb:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
					thumb:Show()
					if thumb.skinFill and thumb.skinFill.SetShown then
						thumb.skinFill:SetShown(true)
					end
				end
			end
			return
		end
		if track and track.SetShown then track:SetShown(true) end
		if thumbBg and thumbBg.SetShown then thumbBg:SetShown(true) end
		track:SetFill(pal.pillTrack[1], pal.pillTrack[2], pal.pillTrack[3], pal.pillTrack[4] or 1)
		if track.stroke then
			track:SetStroke(pal.border[1], pal.border[2], pal.border[3], pal.border[4] or 1)
		end
		thumbBg:SetFill(pal.pillThumb[1], pal.pillThumb[2], pal.pillThumb[3], pal.pillThumb[4] or 1)
		for _, item in ipairs(ordered) do
			local btn = item.button
			local on = (item.key == activeKey)
			local tc = on and pal.text or pal.textSecondary
			if btn._label and btn._label.SetTextColor then
				btn._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
			end
			if on then
				thumb:ClearAllPoints()
				thumb:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
				thumb:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
				thumb:Show()
			end
		end
	end

	function ctrl.SetActive(arg1, arg2, arg3)
		local key, silent
		if arg1 == ctrl then
			key, silent = arg2, arg3
		else
			key, silent = arg1, arg2
		end
		if key == nil then return end
		activeKey = key
		syncVisuals()
		if not silent and opts.onChange then
			opts.onChange(key)
		end
	end
	-- Support both dot and colon call syntax safely
	function ctrl:UpdateTheme()
		syncVisuals()
	end

	for i, def in ipairs(items or {}) do
		local b = CreateFrame("Button", nil, frame)
		if frame.GetFrameLevel and b.SetFrameLevel then
			b:SetFrameLevel(frame:GetFrameLevel() + 2)
		end
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("CENTER", 0, 0)
		fs:SetWordWrap(false)
		Theme.ApplyFont(fs, fontSize, "regular")
		fs:SetText(def.label or tostring(def.key or ""))
		if b.SetFontString then b:SetFontString(fs) end
		b._label = fs

		local strW = (fs.GetStringWidth and fs:GetStringWidth()) or (#(def.label or "") * 6.5)
		local bw = def.width or math.max(44, math.ceil(strW) + 28)
		b:SetSize(bw, height - pad * 2)
		b:SetPoint("LEFT", frame, "LEFT", x, 0)
		if i > 1 then x = x + gap end
		local key = def.key
		b:SetScript("OnClick", function()
			ctrl.SetActive(key, false)
		end)
		buttons[key] = b
		ordered[#ordered + 1] = { key = key, button = b }
		x = x + bw + (i < #(items or {}) and gap or 0)
	end

	frame:SetWidth(math.max(48, x + pad))
	syncVisuals()
	Theme.RegisterWidget(ctrl, function() syncVisuals() end)
	return ctrl
end

function Theme.CreateAppearanceSwitch(parent, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(84, 48)
	local bg = Theme.NineApple(frame, "pill", "toolbarBg", "glassBorder", { cornerSize = 24 })

	local thumb = CreateFrame("Frame", nil, frame)
	thumb:SetSize(32, 32)
	if frame.GetFrameLevel and thumb.SetFrameLevel then
		thumb:SetFrameLevel(frame:GetFrameLevel() + 1)
	end
	local thumbFill = thumb:CreateTexture(nil, "ARTWORK")
	thumbFill:SetAllPoints()
	setTex(thumbFill, Theme.ASSETS.circle_fill)

	local sunBtn = CreateFrame("Button", nil, frame)
	sunBtn:SetSize(32, 32)
	sunBtn:SetPoint("LEFT", frame, "LEFT", 8, 0)
	sunBtn.accessibilityLabel = "Light Mode"
	if frame.GetFrameLevel and sunBtn.SetFrameLevel then
		sunBtn:SetFrameLevel(frame:GetFrameLevel() + 2)
	end
	local sunIcon = Theme.AppleIcon(sunBtn, "sun", 16)
	sunIcon:SetPoint("CENTER", 0, 0)

	local moonBtn = CreateFrame("Button", nil, frame)
	moonBtn:SetSize(32, 32)
	moonBtn:SetPoint("LEFT", frame, "LEFT", 44, 0)
	moonBtn.accessibilityLabel = "Dark Mode"
	if frame.GetFrameLevel and moonBtn.SetFrameLevel then
		moonBtn:SetFrameLevel(frame:GetFrameLevel() + 2)
	end
	local moonIcon = Theme.AppleIcon(moonBtn, "moon", 16)
	moonIcon:SetPoint("CENTER", 0, 0)

	local sw = {
		frame = frame,
		sunBtn = sunBtn,
		moonBtn = moonBtn,
		thumb = thumb,
		sunIcon = sunIcon,
		moonIcon = moonIcon,
	}

	function sw.UpdateTheme()
		local isLight = (Theme.GetMode() == "light")
		local pal = Theme.GetActivePalette()
		bg:SetFill(pal.toolbarBg[1], pal.toolbarBg[2], pal.toolbarBg[3], pal.toolbarBg[4] or (isLight and 0.78 or 0.88))
		local gb = pal.glassBorder or pal.borderStrong
		bg:SetStroke(gb[1], gb[2], gb[3], gb[4] or 0.22)

		thumb:ClearAllPoints()
		thumb:SetPoint("LEFT", frame, "LEFT", isLight and 8 or 44, 0)

		if thumbFill.SetVertexColor then
			if isLight then
				thumbFill:SetVertexColor(1.00, 1.00, 1.00, 0.98)
			else
				thumbFill:SetVertexColor(1.00, 1.00, 1.00, 0.17)
			end
		end

		local activeCol = pal.textGlass or pal.text
		local mutedCol = pal.textGlassSecondary or pal.textSecondary
		if sunIcon.SetVertexColor then
			local c = isLight and activeCol or mutedCol
			sunIcon:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		end
		if moonIcon.SetVertexColor then
			local c = isLight and mutedCol or activeCol
			moonIcon:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		end
	end

	sunBtn:SetScript("OnClick", function()
		Theme.SetMode("light")
		if opts.onChange then opts.onChange("light") end
	end)
	moonBtn:SetScript("OnClick", function()
		Theme.SetMode("dark")
		if opts.onChange then opts.onChange("dark") end
	end)

	sw.UpdateTheme()
	Theme.RegisterWidget(sw, function() sw.UpdateTheme() end)
	return sw
end

function Theme.CreateTrafficLights(parent, onClose, onMin, onMax)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(56, 16)
	if frame.EnableMouse then frame:EnableMouse(true) end

	local specs = {
		{ key = "closeBtn", x = 0,  color = { 1.000, 0.373, 0.341 }, fn = onClose, label = "Close", tip = "Close" },             -- #FF5F57
		{ key = "minBtn",   x = 20, color = { 0.996, 0.737, 0.180 }, fn = onMin,   label = "Minimize", tip = "Minimize" },       -- #FEBC2E
		{ key = "maxBtn",   x = 40, color = { 0.157, 0.784, 0.251 }, fn = onMax,   label = "Zoom", tip = "Full Window" },        -- #28C840
	}
	local out = { frame = frame, _hovered = false }

	local function isClusterMouseOver()
		if frame.IsMouseOver and frame:IsMouseOver() then return true end
		for _, k in ipairs({ "closeBtn", "minBtn", "maxBtn" }) do
			local btn = out[k]
			if btn and btn.IsMouseOver and btn:IsMouseOver() then return true end
		end
		return false
	end

	function out.SetHovered(hovered)
		local show = (hovered == true)
		out._hovered = show
		for _, k in ipairs({ "closeBtn", "minBtn", "maxBtn" }) do
			local btn = out[k]
			if btn and btn.glyph and btn.glyph.SetShown then
				btn.glyph:SetShown(show)
			end
		end
	end

	for _, s in ipairs(specs) do
		local b = CreateFrame("Button", nil, frame)
		b:SetSize(14, 14)
		b:SetPoint("LEFT", frame, "LEFT", s.x, 0)
		b.accessibilityLabel = s.label
		local dot = b:CreateTexture(nil, "ARTWORK")
		dot:SetSize(12, 12)
		dot:SetPoint("CENTER", 0, 0)
		setTex(dot, Theme.ASSETS.circle_fill)
		if dot.SetVertexColor then dot:SetVertexColor(s.color[1], s.color[2], s.color[3], 1) end
		local rim = b:CreateTexture(nil, "OVERLAY")
		rim:SetSize(12, 12)
		rim:SetPoint("CENTER", 0, 0)
		setTex(rim, Theme.ASSETS.circle_stroke)
		if rim.SetVertexColor then rim:SetVertexColor(0, 0, 0, 0.18) end

		if s.key == "closeBtn" then
			local g = b:CreateTexture(nil, "OVERLAY", nil, 2)
			g:SetSize(7, 7)
			g:SetPoint("CENTER", 0, 0)
			setTex(g, Theme.ASSETS.icon_close)
			if g.SetVertexColor then g:SetVertexColor(0.28, 0.02, 0.02, 0.82) end
			g:Hide()
			b.glyph = g
		elseif s.key == "minBtn" then
			local g = b:CreateTexture(nil, "OVERLAY", nil, 2)
			g:SetSize(6, 1.5)
			g:SetPoint("CENTER", 0, 0)
			if g.SetColorTexture then g:SetColorTexture(0.36, 0.20, 0.00, 0.82) end
			g:Hide()
			b.glyph = g
		else
			local gf = CreateFrame("Frame", nil, b)
			gf:SetSize(6, 6)
			gf:SetPoint("CENTER", 0, 0)
			local tlH = gf:CreateTexture(nil, "OVERLAY", nil, 2)
			tlH:SetSize(3.5, 1.5); tlH:SetPoint("TOPLEFT", 0, 0)
			if tlH.SetColorTexture then tlH:SetColorTexture(0.02, 0.24, 0.05, 0.82) end
			local tlV = gf:CreateTexture(nil, "OVERLAY", nil, 2)
			tlV:SetSize(1.5, 3.5); tlV:SetPoint("TOPLEFT", 0, 0)
			if tlV.SetColorTexture then tlV:SetColorTexture(0.02, 0.24, 0.05, 0.82) end
			local brH = gf:CreateTexture(nil, "OVERLAY", nil, 2)
			brH:SetSize(3.5, 1.5); brH:SetPoint("BOTTOMRIGHT", 0, 0)
			if brH.SetColorTexture then brH:SetColorTexture(0.02, 0.24, 0.05, 0.82) end
			local brV = gf:CreateTexture(nil, "OVERLAY", nil, 2)
			brV:SetSize(1.5, 3.5); brV:SetPoint("BOTTOMRIGHT", 0, 0)
			if brV.SetColorTexture then brV:SetColorTexture(0.02, 0.24, 0.05, 0.82) end
			gf:Hide()
			b.glyph = gf
		end

		if s.fn then
			b:SetScript("OnClick", s.fn)
		elseif s.key == "closeBtn" and parent then
			b:SetScript("OnClick", function()
				local target = parent.GetParent and parent:GetParent() or parent
				if target and target.Hide then target:Hide() end
			end)
		end
		b:SetScript("OnEnter", function(self)
			out.SetHovered(true)
			if GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
				GameTooltip:SetText(s.tip)
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function()
			out.SetHovered(isClusterMouseOver())
			if GameTooltip_Hide then GameTooltip_Hide() end
		end)
		out[s.key] = b
	end

	frame:SetScript("OnEnter", function() out.SetHovered(true) end)
	frame:SetScript("OnLeave", function() out.SetHovered(isClusterMouseOver()) end)
	return out
end

local function badgeColors(variant, pal)
	local isLight = (pal.mode == "light")
	if variant == "plain" then
		return { 0, 0, 0, 0 }, pal.textSecondary
	elseif isLight and (variant == "positive" or variant == "green" or variant == "ok") then
		return { 0.000, 0.478, 0.169, 0.11 }, { 0.000, 0.478, 0.169, 1 } -- #007A2B
	elseif isLight and (variant == "hot" or variant == "orange" or variant == "warning") then
		return { 0.878, 0.420, 0.000, 0.11 }, { 0.620, 0.294, 0.000, 1 } -- #9E4B00
	elseif isLight and (variant == "danger" or variant == "red") then
		return { 0.839, 0.141, 0.161, 0.11 }, { 0.722, 0.078, 0.102, 1 } -- #B8141A
	elseif isLight and (variant == "blue" or variant == "info" or variant == "primary") then
		return { 0.000, 0.451, 0.902, 0.11 }, { 0.000, 0.384, 0.800, 1 } -- #0062CC
	elseif variant == "positive" or variant == "green" or variant == "ok" then
		return { isLight and 0.204 or 0.188, isLight and 0.780 or 0.820, isLight and 0.349 or 0.345, 0.16 }, pal.accentGreen
	elseif variant == "hot" or variant == "orange" or variant == "warning" then
		return { 1.000, isLight and 0.553 or 0.573, isLight and 0.157 or 0.188, isLight and 0.18 or 0.16 }, pal.accentOrange
	elseif variant == "danger" or variant == "red" then
		return { 1.000, 0.259, 0.271, 0.16 }, pal.accentRed
	elseif variant == "blue" or variant == "info" or variant == "primary" then
		return { 0.000, 0.533, 1.000, 0.16 }, pal.accentBlue
	elseif variant == "purple" then
		return { 0.800, 0.200, 0.880, 0.16 }, pal.accentPurple
	elseif variant == "strong" then
		-- Light pillThumb is pure white: invisible on a white card, so the capsule uses neutral ink instead
		if isLight then return { 0.000, 0.000, 0.000, 0.085 }, pal.text end
		return pal.pillThumb, pal.text
	else -- neutral / default
		if isLight then
			return { 0.463, 0.463, 0.502, 0.12 }, pal.textSecondary
		else
			return { 0.463, 0.463, 0.502, 0.24 }, pal.textSecondary
		end
	end
end

local KNOWN_BADGE_VARIANTS = {
	neutral = true, default = true, plain = true,
	positive = true, green = true, ok = true,
	hot = true, orange = true, warning = true,
	danger = true, red = true,
	blue = true, info = true, primary = true,
	purple = true, strong = true,
}

function Theme.CreateBadgePill(parent, text, variant, opts)
	opts = opts or {}
	local h = opts.height or 20
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetHeight(h)
	local bg = Theme.RoundRect(frame, frame, "BACKGROUND", 0, math.floor(h * 0.5), 0, 1, 1, 1, 0.16, PILL_TEX)
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER", 0, 0)
	label:SetWordWrap(false)
	Theme.ApplyFont(label, opts.fontSize or 11, opts.weight or "regular")

	local pill = {
		frame = frame,
		bg = bg,
		label = label,
		variant = variant or "neutral",
	}

	local function apply()
		local pal = Theme.GetActivePalette()
		local fillCol, textCol = badgeColors(pill.variant, pal)
		local isPlain = (pill.variant == "plain")
		bg:SetShown(not isPlain)
		if not isPlain then
			bg:SetColor(fillCol[1], fillCol[2], fillCol[3], fillCol[4] or 0.16)
		end
		if label.SetTextColor then
			label:SetTextColor(textCol[1], textCol[2], textCol[3], textCol[4] or 1)
		end
	end

	function pill.SetVariant(arg1, arg2, arg3)
		local newVariant, newText
		if arg1 == pill then
			newVariant, newText = arg2, arg3
		else
			newVariant, newText = arg1, arg2
		end
		if newVariant ~= nil and not KNOWN_BADGE_VARIANTS[newVariant] then
			if KNOWN_BADGE_VARIANTS[newText] then
				newVariant, newText = newText, newVariant
			elseif newText == nil then
				newText = newVariant
				newVariant = pill.variant
			end
		end
		if newVariant ~= nil then pill.variant = newVariant end
		if newText ~= nil then
			label:SetText(tostring(newText))
		end
		local strW = (label.GetStringWidth and label:GetStringWidth()) or (#(label:GetText() or "") * 5.5)
		local isPlain = (pill.variant == "plain")
		local padX = opts.padX or (isPlain and 4 or 18)
		local minW = opts.minWidth or (isPlain and 16 or 24)
		frame:SetWidth(math.max(minW, math.ceil(strW) + padX))
		apply()
	end

	pill:SetVariant(variant or "neutral", text or "")
	Theme.RegisterWidget(pill, apply)
	return pill
end

function Theme.CreateGlyphBadge(parent, iconName, size, iconSize, opts)
	opts = opts or {}
	local sz = size or 28
	local icSz = iconSize or math.max(10, math.floor(sz * 0.535 + 0.5))
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(sz, sz)

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	setTex(bg, Theme.ASSETS.circle_fill)

	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(icSz, icSz)
	icon:SetPoint("CENTER", 0, 0)

	local badge = {
		frame = frame,
		bg = bg,
		icon = icon,
		_isCustomTex = false,
		_customBg = opts.bgColor,
		_customIconCol = opts.iconColor,
	}

	local function paint()
		local pal = Theme.GetActivePalette()
		local isLight = (pal.mode == "light")
		local bc = badge._customBg
		if bc then
			if bg.SetVertexColor then bg:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 0.12) end
		elseif bg.SetVertexColor then
			bg:SetVertexColor(0.463, 0.463, 0.502, isLight and 0.12 or 0.16)
		end
		if icon.SetVertexColor then
			if badge._isCustomTex then
				icon:SetVertexColor(1, 1, 1, 1)
			else
				local ic = badge._customIconCol or pal.textSecondary
				icon:SetVertexColor(ic[1], ic[2], ic[3], ic[4] or 1)
			end
		end
	end

	function badge:SetIcon(nameOrPath)
		if type(nameOrPath) == "number" then
			self._isCustomTex = true
			setTex(icon, nameOrPath)
			if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
		elseif type(nameOrPath) == "string" and (nameOrPath:find("\\", 1, true) or nameOrPath:find("/", 1, true)) and not nameOrPath:find("Assets\\apple\\icon_", 1, true) then
			self._isCustomTex = true
			setTex(icon, nameOrPath)
			if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
		else
			self._isCustomTex = false
			setTex(icon, resolveIconPath(nameOrPath))
			if icon.SetTexCoord then icon:SetTexCoord(0, 1, 0, 1) end
		end
		paint()
	end
	function badge:SetBgColor(r, g, b, a)
		if r == false or r == nil then
			self._customBg = nil
		else
			self._customBg = { unpackColor(r, g, b, a) }
		end
		paint()
	end
	function badge:SetIconColor(r, g, b, a)
		if r == false or r == nil then
			self._customIconCol = nil
		else
			self._customIconCol = { unpackColor(r, g, b, a) }
		end
		paint()
	end
	function badge:SetShown(v)
		if frame.SetShown then frame:SetShown(v) elseif v then frame:Show() else frame:Hide() end
	end

	badge:SetIcon(iconName or "flask")
	Theme.RegisterWidget(badge, paint)
	return badge
end
Theme.CreateCircularGlyph = Theme.CreateGlyphBadge

function Theme.CreateProgressBar(parent, h, opts)
	opts = opts or {}
	local barH = h or 6
	local capW = math.max(2, math.floor(barH * 0.5))
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetHeight(barH)
	if opts.width then frame:SetWidth(opts.width) end

	local track = pill3Slice(frame, frame, "BACKGROUND", 0, capW, 0, 1, 1, 1, 0.14, Theme.ASSETS.meter_track)
	local fillFrame = CreateFrame("Frame", nil, frame)
	if frame.GetFrameLevel and fillFrame.SetFrameLevel then
		fillFrame:SetFrameLevel(frame:GetFrameLevel() + 1)
	end
	fillFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	fillFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	fillFrame:SetWidth(barH)
	local fill = pill3Slice(fillFrame, fillFrame, "ARTWORK", 2, capW, 0, 1, 1, 1, 0.90, Theme.ASSETS.meter_fill)

	local bar = {
		frame = frame,
		track = track,
		fill = fill,
		fillFrame = fillFrame,
		_frac = 0,
		_color = opts.color,
	}

	local function colorKey(c, fallbackA)
		return string.format("%.3f,%.3f,%.3f,%.3f", tonumber(c[1]) or 0, tonumber(c[2]) or 0, tonumber(c[3]) or 0, tonumber(c[4]) or fallbackA or 1)
	end

	local function layoutFill()
		local frac = math.max(0, math.min(1, tonumber(bar._frac) or 0))
		if frac <= 0 then
			if bar._lastShown ~= false then
				fill:SetShown(false)
				fillFrame:Hide()
				bar._lastShown = false
				bar._lastFw = nil
			end
			return
		end
		if bar._lastShown ~= true then
			fill:SetShown(true)
			fillFrame:Show()
			bar._lastShown = true
		end
		local w = (frame.GetWidth and frame:GetWidth()) or 0
		if w <= 0 then w = opts.width or 160 end
		local fw = math.max(barH, math.min(w, math.floor(w * frac + 0.5)))
		if bar._lastFw ~= fw then
			fillFrame:SetWidth(fw)
			bar._lastFw = fw
		end
	end

	local function paint(skipLayout)
		local pal = Theme.GetActivePalette()
		local isLight = (pal.mode == "light")
		local mt = pal.meterTrack or (isLight and { 0, 0, 0, 0.12 } or { 1, 1, 1, 0.14 })
		local mtK = colorKey(mt, 0.14)
		if bar._lastTrackKey ~= mtK then
			track:SetColor(mt[1], mt[2], mt[3], mt[4] or 0.14)
			bar._lastTrackKey = mtK
		end
		local fc = bar._color or pal.meterFill or (isLight and { 0.110, 0.110, 0.118, 0.90 } or { 1, 1, 1, 0.90 })
		local fcK = colorKey(fc, 0.90)
		if bar._lastFillKey ~= fcK then
			fill:SetColor(fc[1], fc[2], fc[3], fc[4] or 0.90)
			bar._lastFillKey = fcK
		end
		if not skipLayout and (bar._frac or 0) > 0 then
			layoutFill()
		end
	end

	function bar.SetValue(arg1, arg2, arg3)
		local frac, colorTbl
		if arg1 == bar then
			frac, colorTbl = arg2, arg3
		else
			frac, colorTbl = arg1, arg2
		end
		bar._frac = math.max(0, math.min(1, tonumber(frac) or 0))
		if colorTbl ~= nil then
			bar._color = (colorTbl == false) and nil or colorTbl
		end
		paint(true)
		layoutFill()
	end
	function bar:SetColor(col)
		self._color = (col == false) and nil or col
		paint()
	end

	if frame.HookScript then
		frame:HookScript("OnSizeChanged", layoutFill)
		frame:HookScript("OnShow", layoutFill)
	end
	bar:SetValue(opts.value or 0, opts.color)
	Theme.RegisterWidget(bar, paint)
	return bar
end

function Theme.CreateKpiCard(parent, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetHeight(opts.height or 104)
	if opts.width then frame:SetWidth(opts.width) end
	local surface = Theme.NineApple(frame, "glass_r10", "cardBg", false, { noSpecular = true })

	local accentBar = frame:CreateTexture(nil, "ARTWORK")
	accentBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -10)
	accentBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 10)
	accentBar:SetWidth(3)
	if accentBar.SetAlpha then accentBar:SetAlpha(0) end
	accentBar:Hide()

	-- Warcraft skins: stretched 0..1 surface substrate + translucent kpi_bg plate + 1px metallic perimeter
	-- (shown ONLY on a custom skin, so Standard keeps `surface.stroke == nil` and renders byte-identically).
	local skinTile = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	skinTile:SetAllPoints(frame)
	skinTile:Hide()
	local skinBg = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
	skinBg:SetAllPoints(frame)
	skinBg:Hide()
	local skinEdges = {}
	for _, e in ipairs({ "top", "bottom", "left", "right" }) do
		local t = frame:CreateTexture(nil, "BORDER", nil, 2)
		if e == "top" then
			t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); t:SetHeight(1)
		elseif e == "bottom" then
			t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); t:SetHeight(1)
		elseif e == "left" then
			t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); t:SetWidth(1)
		else
			t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); t:SetWidth(1)
		end
		t:Hide()
		skinEdges[#skinEdges + 1] = t
	end

	local titleX = 16
	local iconTex
	if opts.icon then
		iconTex = Theme.AppleIcon(frame, opts.icon, 14)
		iconTex:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -15)
		titleX = 36
	end

	local titleFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	titleFs:SetPoint("TOPLEFT", frame, "TOPLEFT", titleX, -14)
	titleFs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -14)
	titleFs:SetJustifyH("LEFT")
	titleFs:SetWordWrap(false)
	if titleFs.SetMaxLines then titleFs:SetMaxLines(1) end
	Theme.ApplyFont(titleFs, 12, "regular")

	local valueFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	valueFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -36)
	valueFs:SetJustifyH(opts.alignValue or "LEFT")
	valueFs:SetWordWrap(false)
	if valueFs.SetMaxLines then valueFs:SetMaxLines(1) end
	Theme.ApplyFont(valueFs, 26, "semibold")

	local unitFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	unitFs:SetPoint("BOTTOMLEFT", valueFs, "BOTTOMRIGHT", 10, 4)
	unitFs:SetJustifyH("LEFT")
	unitFs:SetWordWrap(false)
	if unitFs.SetMaxLines then unitFs:SetMaxLines(1) end
	Theme.ApplyFont(unitFs, 13, "regular")
	unitFs:Hide()

	local tagPill = Theme.CreateBadgePill(frame, "", opts.tagVariant or opts.pillVariant or "positive", { height = 20 })
	tagPill.frame:SetPoint("LEFT", valueFs, "RIGHT", 10, -2)
	tagPill.frame:Hide()

	local subFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	subFs:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
	subFs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
	subFs:SetJustifyH("LEFT")
	subFs:SetWordWrap(false)
	if subFs.SetMaxLines then subFs:SetMaxLines(1) end
	Theme.ApplyFont(subFs, 12, "regular")

	local card = {
		frame = frame,
		surface = surface,
		titleFs = titleFs,
		valueFs = valueFs,
		unitFs = unitFs,
		tagPill = tagPill,
		pill = tagPill,
		subFs = subFs,
		accentBar = accentBar,
		skinTile = skinTile,
		skinBg = skinBg,
		skinEdges = skinEdges,
		iconTex = iconTex,
		valueColor = opts.valueColor,
		_alignValue = opts.alignValue or "LEFT",
		_unitText = nil,
		_tagText = nil,
		_tagVariant = opts.tagVariant or opts.pillVariant or "positive",
	}

	local function syncSkinTile()
		if not (Theme.IsCustomSkin and Theme.IsCustomSkin()) then return end
		if skinTile.SetHorizTile then skinTile:SetHorizTile(false) end
		if skinTile.SetVertTile then skinTile:SetVertTile(false) end
		if skinTile.SetTexCoord then skinTile:SetTexCoord(0, 1, 0, 1) end
	end
	card.syncSkinTile = syncSkinTile
	if frame.HookScript then
		frame:HookScript("OnSizeChanged", syncSkinTile)
		frame:HookScript("OnShow", syncSkinTile)
	end

	local function syncInlineLayout()
		local custom = Theme.IsCustomSkin and Theme.IsCustomSkin()
		local hasUnit = (type(card._unitText) == "string" and card._unitText ~= "")
		if hasUnit then
			unitFs:SetText(card._unitText)
			unitFs:Show()
		else
			unitFs:SetText("")
			unitFs:Hide()
		end
		local hasTag = (type(card._tagText) == "string" and card._tagText ~= "")
		if hasTag then
			tagPill:SetVariant(card._tagVariant or "positive", card._tagText)
			tagPill.frame:ClearAllPoints()
			if hasUnit then
				tagPill.frame:SetPoint("LEFT", unitFs, "RIGHT", custom and 8 or 9, custom and 0 or 1)
			else
				tagPill.frame:SetPoint("LEFT", valueFs, "RIGHT", custom and 8 or 10, custom and 0 or -2)
			end
			tagPill.frame:Show()
		else
			tagPill.frame:Hide()
		end
		if custom then
			if valueFs.SetWidth then valueFs:SetWidth(0) end
			unitFs:ClearAllPoints()
			unitFs:SetPoint("BOTTOMLEFT", valueFs, "BOTTOMRIGHT", 4, 1)
		elseif opts.alignValue == "RIGHT" then
			local accessories = (hasUnit and (10 + unitFs:GetStringWidth()) or 0)
				+ (hasTag and (10 + tagPill.frame:GetWidth()) or 0)
			valueFs:ClearAllPoints()
			valueFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -36)
			valueFs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16 - accessories, -36)
			unitFs:ClearAllPoints()
			unitFs:SetPoint("BOTTOMLEFT", valueFs, "BOTTOMRIGHT", 10, 4)
		else
			unitFs:ClearAllPoints()
			unitFs:SetPoint("BOTTOMLEFT", valueFs, "BOTTOMRIGHT", 10, 4)
		end
	end
	card.syncInlineLayout = syncInlineLayout

	local function paint()
		local pal = Theme.GetActivePalette()
		surface:UpdateTheme()
		if Theme.IsCustomSkin() and pal.frameBorder then
			skinTile:SetTexture(Theme.GetSkinAsset(Theme.GetSkin(), "surface"), "CLAMP", "CLAMP")
			syncSkinTile()
			skinTile:Show()
			skinBg:SetTexture(Theme.GetSkinAsset(Theme.GetSkin(), "kpi_bg"))
			skinBg:Show()
			local fb = pal.frameBorder
			for _, t in ipairs(skinEdges) do
				t:SetColorTexture(fb[1], fb[2], fb[3], 0.85)
				t:Show()
			end
		else
			skinTile:Hide()
			skinBg:Hide()
			for _, t in ipairs(skinEdges) do t:Hide() end
		end
		if titleFs.SetTextColor then
			local tc = pal.textSecondary
			titleFs:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
		if iconTex and iconTex.SetVertexColor then
			local ic = pal.textSecondary
			iconTex:SetVertexColor(ic[1], ic[2], ic[3], ic[4] or 1)
		end
		if valueFs.SetTextColor then
			local vc = card.valueColor or pal.text
			valueFs:SetTextColor(vc[1], vc[2], vc[3], vc[4] or 1)
		end
		if unitFs.SetTextColor then
			local uc = pal.textSecondary
			unitFs:SetTextColor(uc[1], uc[2], uc[3], uc[4] or 1)
		end
		if subFs.SetTextColor then
			local sc = pal.textSecondary
			subFs:SetTextColor(sc[1], sc[2], sc[3], sc[4] or 1)
		end
		syncInlineLayout()
	end

	function card.SetData(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
		local titleOrTbl, value, sub, _, valueColor, unitArg, tagArg, tagVarArg
		if arg1 == card then
			titleOrTbl, value, sub, _, valueColor, unitArg, tagArg, tagVarArg = arg2, arg3, arg4, arg5, arg6, arg7, arg8, nil
		else
			titleOrTbl, value, sub, _, valueColor, unitArg, tagArg, tagVarArg = arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8
		end
		local t, v, s, vc, u, tg, tgv, ucFlag
		if type(titleOrTbl) == "table" then
			t = titleOrTbl.title
			v = titleOrTbl.value
			s = titleOrTbl.sub
			vc = titleOrTbl.valueColor
			u = titleOrTbl.unit
			tg = (titleOrTbl.tag ~= nil) and titleOrTbl.tag or titleOrTbl.pill
			tgv = titleOrTbl.tagVariant or titleOrTbl.pillVariant
			ucFlag = titleOrTbl.uppercase
		else
			t, v, s, vc, u, tg, tgv = titleOrTbl, value, sub, valueColor, unitArg, tagArg, tagVarArg
		end
		if t ~= nil then
			local str = tostring(t)
			local wantUpper = (ucFlag ~= nil) and (ucFlag == true) or (opts.uppercase == true)
			if wantUpper then str = str:upper() end
			if Theme.IsCustomSkin and Theme.IsCustomSkin() then
				card._skinTitle = str
				titleFs:SetText(str:upper())
			else
				titleFs:SetText(str)
			end
		end
		if v ~= nil then valueFs:SetText(tostring(v)) end
		if s ~= nil then subFs:SetText(tostring(s)) end
		if vc == false then
			card.valueColor = nil
		elseif vc ~= nil then
			card.valueColor = vc
		end
		if u == false then
			card._unitText = nil
		elseif u ~= nil then
			card._unitText = tostring(u)
		end
		if tg == false then
			card._tagText = nil
		elseif type(tg) == "table" then
			card._tagText = tg.text and tostring(tg.text) or nil
			if tg.variant then card._tagVariant = tg.variant end
		elseif tg ~= nil then
			card._tagText = tostring(tg)
		end
		if tgv ~= nil then
			card._tagVariant = tgv
		end
		syncInlineLayout()
		paint()
	end

	if opts.title or opts.value or opts.sub or opts.unit or opts.tag or opts.pill or opts.accent then
		card:SetData(opts)
	else
		syncInlineLayout()
		paint()
	end

	Theme.RegisterWidget(card, paint)
	return card
end

function Theme.CreateToast(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetHeight(36)
	frame:SetWidth(240)
	frame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 24)
	if parent.GetFrameLevel and frame.SetFrameLevel then
		frame:SetFrameLevel(parent:GetFrameLevel() + 30)
	end
	frame:Hide()

	local bg = Theme.NineApple(frame, "pill", "toolbarBg", "glassBorder", { cornerSize = 18 })
	local icon = Theme.AppleIcon(frame, "checkcircle", 16, Theme.COLORS.accentGreen)
	icon:SetPoint("LEFT", frame, "LEFT", 12, 0)

	local textFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	textFs:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	textFs:SetJustifyH("LEFT")
	textFs:SetWordWrap(false)
	Theme.ApplyFont(textFs, 13, "regular")

	local toast = {
		frame = frame,
		icon = icon,
		textFs = textFs,
		variant = "success",
	}
	local token = 0

	local function paint()
		local pal = Theme.GetActivePalette()
		bg:UpdateTheme()
		if textFs.SetTextColor then
			local tc = pal.text
			textFs:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
		local icCol = pal.accentGreen
		if toast.variant == "error" or toast.variant == "red" or toast.variant == "danger" then
			icCol = pal.accentRed
		elseif toast.variant == "warn" or toast.variant == "orange" or toast.variant == "warning" then
			icCol = pal.accentOrange
		elseif toast.variant == "info" or toast.variant == "blue" then
			icCol = pal.accentBlue
		end
		if icon.SetVertexColor then
			icon:SetVertexColor(icCol[1], icCol[2], icCol[3], icCol[4] or 1)
		end
	end

	function toast.ShowToast(arg1, arg2, arg3, arg4)
		local msg, variant, duration
		if arg1 == toast then
			msg, variant, duration = arg2, arg3, arg4
		else
			msg, variant, duration = arg1, arg2, arg3
		end
		toast.variant = variant or "success"
		textFs:SetText(tostring(msg or ""))
		local strW = (textFs.GetStringWidth and textFs:GetStringWidth()) or (#(tostring(msg or "")) * 6)
		frame:SetWidth(math.max(140, math.ceil(strW) + 52))
		paint()
		frame:Show()
		token = token + 1
		local myToken = token
		local dur = duration or 2.6
		if dur > 0 then
			if C_Timer and type(C_Timer.After) == "function" then
				C_Timer.After(dur, function()
					if token == myToken then frame:Hide() end
				end)
			else
				local elapsed = 0
				frame:SetScript("OnUpdate", function(self, dt)
					elapsed = elapsed + (dt or 0)
					if elapsed >= dur then
						self:SetScript("OnUpdate", nil)
						if token == myToken then self:Hide() end
					end
				end)
			end
		end
	end

	paint()
	Theme.RegisterWidget(toast, paint)
	return toast
end

---------------------------------------------------------------------------------------------------
-- Browser-Style Top Tabs (Updated to Apple HIG Palette)

local function openBottom(rr, anchor, c)
	c = c or 16
	local p = rr.pieces
	p[3]:Hide(); p[4]:Hide(); p[6]:Hide()
	rr.pieces = { p[1], p[2], p[5], p[7], p[8], p[9] }
	p[7]:ClearAllPoints(); p[7]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT"); p[7]:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", c, 0)
	p[8]:ClearAllPoints(); p[8]:SetPoint("TOPRIGHT", p[2], "BOTTOMRIGHT"); p[8]:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", -c, 0)
	if p[9] then
		p[9]:ClearAllPoints()
		p[9]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT")
		p[9]:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -c, 0)
	end
	return rr
end

function Theme.CreateBrowserTab(parent, text, w, h, iconID)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 110, (h or 29) + 1)

	local inner = CreateFrame("Frame", nil, b)
	inner:SetPoint("TOPLEFT", 0, 0)
	inner:SetPoint("BOTTOMRIGHT", 0, 1)

	local plateOff = openBottom(Theme.RoundRect(b, inner, "BACKGROUND", 0, 16, 0, 1, 1, 1, 0, Theme.ASSETS.glass_r8_fill), inner)
	local edgeOff  = openBottom(Theme.RoundRect(b, inner, "BORDER", 0, 16, 0, 1, 1, 1, 0.1, Theme.ASSETS.glass_r8_stroke), inner)
	local plateOn  = openBottom(Theme.RoundRect(b, b, "BACKGROUND", 1, 16, 0, 1, 1, 1, 0.14, Theme.ASSETS.glass_r8_fill), b)
	local edgeOn   = openBottom(Theme.RoundRect(b, b, "BORDER", 2, 16, 0, 1, 1, 1, 0.25, Theme.ASSETS.glass_r8_stroke), b)
	local hov      = openBottom(Theme.RoundRect(b, inner, "HIGHLIGHT", 0, 16, 0, 1, 1, 1, 0.06, Theme.ASSETS.glass_r8_fill), inner)

	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	Theme.ApplyFont(label, 12, "regular")
	label:SetWordWrap(false)
	label:SetText(text or "")

	if iconID then
		local ic = b:CreateTexture(nil, "OVERLAY")
		ic:SetSize(15, 15)
		ic:SetTexture(iconID)
		if ic.SetTexCoord then ic:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
		b.glyph = ic
	end

	local function place(dx, dy)
		label:ClearAllPoints()
		if b.glyph then
			local strW = label.GetStringWidth and label:GetStringWidth() or 60
			local tw = 15 + 5 + strW
			b.glyph:ClearAllPoints()
			b.glyph:SetPoint("LEFT", b, "CENTER", -tw * 0.5 + dx, dy + 1)
			label:SetPoint("LEFT", b.glyph, "RIGHT", 5, 0)
		else
			label:SetPoint("CENTER", dx, dy + 1)
		end
	end
	place(0, 0)

	b._label = label
	local isActive = false
	local function paint()
		local pal = Theme.GetActivePalette()
		plateOff:SetColor(pal.pillTrack)
		edgeOff:SetColor(pal.border)
		plateOn:SetColor(pal.navActiveBg)
		edgeOn:SetColor(pal.borderStrong)
		hov:SetColor(pal.glassHover)
		plateOff:SetShown(not isActive); edgeOff:SetShown(not isActive)
		plateOn:SetShown(isActive); edgeOn:SetShown(isActive)
		local tc = isActive and pal.tabTextOn or pal.tabText
		if label.SetTextColor then label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1) end
		if b.glyph and b.glyph.SetAlpha then
			b.glyph:SetAlpha(isActive and 1.0 or 0.82)
		end
	end

	local origSetText = b.SetText
	function b:SetText(t)
		if origSetText then origSetText(self, t) end
		label:SetText(t or "")
		place(0, 0)
	end
	function b:ContentWidth()
		local strW = label.GetStringWidth and label:GetStringWidth() or 64
		return (b.glyph and 20 or 0) + math.ceil(strW)
	end
	function b:SetActive(on)
		isActive = on and true or false
		paint()
	end
	b:SetActive(false)
	b:SetScript("OnMouseDown", function() place(1, -1) end)
	b:SetScript("OnMouseUp", function() place(0, 0) end)
	Theme.RegisterWidget(b, paint)
	return b
end

---------------------------------------------------------------------------------------------------
-- Modern Glass Popup Dropdown Menu (Shared Singleton, Click-Outside Dismissal)

local ddMenu, ddCatcher
function Theme.OpenDropDown(owner, options, currentKey, onPick, minWidth, ddOpts)
	ddOpts = ddOpts or {}
	if not ddMenu then
		ddCatcher = CreateFrame("Button", nil, UIParent)
		ddCatcher:SetAllPoints(UIParent)
		ddCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
		ddCatcher:SetFrameLevel(1)
		ddCatcher:RegisterForClicks("AnyUp")
		ddCatcher:Hide()

		ddMenu = CreateFrame("Frame", nil, UIParent)
		ddMenu:SetFrameStrata("FULLSCREEN_DIALOG")
		ddMenu:SetFrameLevel(25)
		ddMenu:EnableMouse(true)
		ddMenu:Hide()
		ddMenu._appleBg = Theme.NineApple(ddMenu, "glass_r12", "toolbarBg", "borderStrong")
		ddMenu.rows = {}

		ddCatcher:SetScript("OnClick", function() ddMenu:Hide() end)
		ddMenu:SetScript("OnHide", function() ddCatcher:Hide() end)
	end

	if ddMenu:IsShown() and ddMenu.owner == owner then
		ddMenu:Hide()
		return
	end

	local function isOptSelected(opt)
		if type(ddOpts.isSelected) == "function" then
			return ddOpts.isSelected(opt.key, opt) == true
		elseif type(opt.checked) == "function" then
			return opt.checked(opt) == true
		elseif opt.checked ~= nil then
			return opt.checked == true
		end
		return opt.key == currentKey
	end

	local function syncRowStates()
		local pal = Theme.GetActivePalette()
		local selCol = pal.accentBlue
		local txtCol = pal.text
		for idx, o in ipairs(ddMenu.options or {}) do
			local row = ddMenu.rows[idx]
			if row then
				local sel = isOptSelected(o)
				row.check:SetShown(sel)
				if row.check.SetVertexColor then
					row.check:SetVertexColor(selCol[1], selCol[2], selCol[3], 1)
				end
				if row.text.SetTextColor then
					local tc = sel and selCol or txtCol
					row.text:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
				end
				if row.hl and row.hl.SetColorTexture then
					row.hl:SetColorTexture(selCol[1], selCol[2], selCol[3], 0.16)
				end
			end
		end
	end

	local w = math.max(minWidth or 176, (owner and owner.GetWidth and owner:GetWidth()) or 176)
	for _, r in ipairs(ddMenu.rows) do r:Hide() end

	for i, opt in ipairs(options or {}) do
		local r = ddMenu.rows[i]
		if not r then
			r = CreateFrame("Button", nil, ddMenu)
			r:SetHeight(24)
			local hi = r:CreateTexture(nil, "HIGHLIGHT")
			hi:SetAllPoints()
			r.hl = hi
			r.check = r:CreateTexture(nil, "OVERLAY")
			r.check:SetSize(12, 12)
			r.check:SetPoint("LEFT", 8, 0)
			setTex(r.check, Theme.ASSETS.icon_check)
			r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			Theme.ApplyFont(r.text, 12, "regular")
			r.text:SetPoint("LEFT", 26, 0)
			r.text:SetJustifyH("LEFT")
			r.text:SetWordWrap(false)
			ddMenu.rows[i] = r
		end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 24)
		r.text:SetText(opt.label or tostring(opt.key or ""))
		local need = (r.text.GetStringWidth and r.text:GetStringWidth() or 120) + 42
		if need > w then w = math.ceil(need) end
		local pickedKey, pickedIdx = opt.key, i
		r:SetScript("OnClick", function()
			local keepOpen = (ddOpts.multiSelect == true or opt.keepOpen == true) and (opt.closeOnPick ~= true)
			if not keepOpen then
				ddMenu:Hide()
			end
			if onPick then onPick(pickedKey, pickedIdx, opt) end
			if keepOpen and ddMenu:IsShown() then
				syncRowStates()
			end
		end)
		r:Show()
	end
	ddMenu.options = options
	syncRowStates()

	for i = 1, #(options or {}) do
		ddMenu.rows[i]:SetWidth(w - 12)
	end
	ddMenu:SetSize(w, #(options or {}) * 24 + 12)
	ddMenu:ClearAllPoints()
	ddMenu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
	ddMenu.owner = owner
	ddCatcher:Show()
	ddMenu:Show()
	Theme.RegisterWidget(ddMenu, function()
		if ddMenu._appleBg then ddMenu._appleBg:UpdateTheme() end
		if ddMenu:IsShown() then syncRowStates() end
	end)
end

function Theme.GetDropDownMenu()
	return ddMenu
end

function Theme.CloseDropDown()
	if ddMenu then ddMenu:Hide() end
end

---------------------------------------------------------------------------------------------------
-- Warcraft Frame Chrome (rails, corners, crest, banners) for the 5 Warcraft skins

-- Native tile sizes (px) of the painted .blp/.tga art and the on-screen dimensions (UI units) per skin.
--   railH / railV : { texW, texH, thick, nativeAspect } on-screen thickness & aspect of rail strip
--   outH / outV   : how far the top+bottom / left+right rails overhang the panel edge
--   railInset     : distance from panel edges where horizontal & vertical rails begin (behind corners)
--   inset         : { left, top, right, bottom } the shell content keeps clear of the chrome
--   corner / cornerOut : { w, h } corner ornament size and { outX, outY } overhang
--   crest         : { w, h, up, vMax } on-screen crest size, rise above panel top, and normalized [0..1] vertical UV crop (resolution-independent for 256x128 / 512x256 crest.blp)
local SKIN_ART = {
	human = {
		railH = { 512, 128, 36, 10.9859 }, railV = { 64, 512, 22, 8.8243 }, outH = 21, outV = 14,
		railInset = 64, inset = { 14, 14, 14, 14 }, corner = { 88, 88 }, cornerOut = { 18, 18 },
		crest = { 266, 98, 79, 0.8125 }, banner = { 128, 256, 54, 88, 181, 75 },
	},
	night_elf = {
		railH = { 512, 64, 34, 6.5581 }, railV = { 64, 512, 34, 6.5581 }, outH = 14, outV = 14,
		railInset = 56, inset = { 16, 16, 16, 16 }, corner = { 124, 129 }, cornerOut = { 25, 25 },
		crest = { 249, 100, 73, 0.800781 },
	},
	orc = {
		railH = { 512, 128, 40, 3.7727 }, railV = { 128, 512, 40, 3.7727 }, outH = 19, outV = 19,
		railInset = 26, inset = { 16, 16, 16, 16 }, corner = { 120, 126 }, cornerOut = { 23, 22 },
		crest = { 290, 99, 65, 0.683594 },
	},
	undead = {
		railH = { 512, 64, 26, 8.5000 }, railV = { 64, 512, 26, 8.5000 }, outH = 6, outV = 6,
		railInset = 28, inset = { 16, 16, 16, 16 }, corner = { 196, 199 }, cornerOut = { 20, 19 },
		crest = { 268, 102, 76, 0.757812 },
	},
	goblin = {
		railH = { 256, 128, 22, 1.9718 }, railV = { 128, 256, 22, 1.9718 }, outH = 0, outV = 0,
		railInset = 14, inset = { 20, 20, 20, 20 }, corner = { 128, 125 }, cornerOut = { 4, 4 },
		crest = { 246, 106, 80, 0.863281 },
	},
}
Theme.SKIN_ART = SKIN_ART

-- Content inset (left, top, right, bottom) a Warcraft skin keeps clear for its frame; zeros on Standard.
function Theme.GetSkinInset(skinKey)
	local art = SKIN_ART[skinKey or currentSkin]
	if not art then return 0, 0, 0, 0 end
	return art.inset[1], art.inset[2], art.inset[3], art.inset[4]
end

local MAX_RAIL_TILES = 96

local function skinTex(skin, name)
	return Theme.GetSkinAsset(skin, name)
end

-- Fills `pool` with exactly the tiles needed to cover `span` px with tiles of `tileLen` px; the final
-- tile is cropped with SetTexCoord (never stretched) so the art stays razor sharp from 1320 to 3840 px.
local function layoutTilePool(owner, pool, span, tileLen, thick, texPath, horizontal, flip, place, cropBottom)
	local count = 0
	if span > 0 and tileLen > 0 then count = math.min(MAX_RAIL_TILES, math.ceil(span / tileLen - 0.001)) end
	for i = 1, count do
		local tex = pool[i]
		if not tex then
			tex = owner:CreateTexture(nil, "OVERLAY", nil, 1)
			pool[i] = tex
		end
		tex:SetTexture(texPath)
		local off = (i - 1) * tileLen
		local len = math.min(tileLen, span - off)
		local frac = len / tileLen
		tex:ClearAllPoints()
		place(tex, off, len)
		if horizontal then
			tex:SetSize(len, thick)
			local vEnd = cropBottom or 1
			if flip then tex:SetTexCoord(0, frac, vEnd, 0) else tex:SetTexCoord(0, frac, 0, vEnd) end
		else
			tex:SetSize(thick, len)
			if flip then tex:SetTexCoord(1, 0, 0, frac) else tex:SetTexCoord(0, 1, 0, frac) end
		end
		tex:Show()
	end
	for i = count + 1, #pool do pool[i]:Hide() end
	return count
end

function Theme.CreateWarcraftFrameChrome(panel)
	local f = CreateFrame("Frame", nil, panel)
	f:SetAllPoints(panel)
	if panel.GetFrameLevel and f.SetFrameLevel then f:SetFrameLevel(panel:GetFrameLevel() + 22) end
	if f.EnableMouse then f:EnableMouse(false) end

	local chrome = {
		frame = f,
		pools = { top = {}, bottom = {}, left = {}, right = {} },
		shell = {}, shellInner = {}, corners = {},
	}

	-- Dark base so the painted shell never lets the game world through.
	chrome.base = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
	chrome.base:SetAllPoints(panel)

	-- Outer metallic shell (2px) + inner dark bevel (1px) on the four panel edges.
	local function edge(list, layer, sub, e)
		local t = f:CreateTexture(nil, layer, nil, sub)
		list[e] = t
		return t
	end
	for _, e in ipairs({ "top", "bottom", "left", "right" }) do
		edge(chrome.shell, "OVERLAY", 0, e)
		edge(chrome.shellInner, "OVERLAY", 0, e)
	end

	local cornerKeys = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
	for _, k in ipairs(cornerKeys) do
		local t = f:CreateTexture(nil, "OVERLAY", nil, 3)
		chrome.corners[k] = t
	end
	chrome.crest = f:CreateTexture(nil, "OVERLAY", nil, 5)
	chrome.bannerL = f:CreateTexture(nil, "OVERLAY", nil, 0)
	chrome.bannerR = f:CreateTexture(nil, "OVERLAY", nil, 0)
	chrome.chainL = f:CreateTexture(nil, "OVERLAY", nil, 0)
	chrome.chainR = f:CreateTexture(nil, "OVERLAY", nil, 0)

	local function allHide()
		f:Hide()
		chrome.base:Hide()
	end

	function chrome:Layout()
		local skin = currentSkin
		local art = SKIN_ART[skin]
		if not art or panel._mmCompactBackdrop then allHide(); return end
		f:Show()
		chrome.base:Show()
		local W = (panel.GetWidth and panel:GetWidth()) or 0
		local H = (panel.GetHeight and panel:GetHeight()) or 0
		if W <= 0 or H <= 0 then return end
		local minimized = panel._mmMinimized == true
		local compact = panel._mmCompactChrome == true

		-- Shell edges
		local s, si = chrome.shell, chrome.shellInner
		s.top:ClearAllPoints();    s.top:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0);       s.top:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0);       s.top:SetHeight(2)
		s.bottom:ClearAllPoints(); s.bottom:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0); s.bottom:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0); s.bottom:SetHeight(2)
		s.left:ClearAllPoints();   s.left:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0);      s.left:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0);   s.left:SetWidth(2)
		s.right:ClearAllPoints();  s.right:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0);   s.right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0); s.right:SetWidth(2)
		si.top:ClearAllPoints();    si.top:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -2);       si.top:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2);       si.top:SetHeight(1)
		si.bottom:ClearAllPoints(); si.bottom:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 2, 2); si.bottom:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2); si.bottom:SetHeight(1)
		si.left:ClearAllPoints();   si.left:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -2);      si.left:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 2, 2);   si.left:SetWidth(1)
		si.right:ClearAllPoints();  si.right:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2);  si.right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2); si.right:SetWidth(1)
		for _, e in ipairs({ "top", "bottom", "left", "right" }) do
			-- Keep the 1px/2px perimeter shell on all 4 sides even when minimized.
			s[e]:SetShown(true); si[e]:SetShown(true)
		end

		-- Corners (OVERLAY sublevel 3, drawn OVER rail joints so corners overlap rails with zero gap)
		local cw = type(art.corner) == "table" and art.corner[1] or art.corner
		local ch = type(art.corner) == "table" and art.corner[2] or art.corner
		local cox = type(art.cornerOut) == "table" and art.cornerOut[1] or art.cornerOut
		local coy = type(art.cornerOut) == "table" and art.cornerOut[2] or art.cornerOut
		if compact then
			local cScale = math.min(1, 64 / math.max(1, cw))
			cw = math.max(36, math.floor(cw * cScale + 0.5))
			ch = math.max(36, math.floor(ch * cScale + 0.5))
			cox = math.min(cox, 2)
			coy = math.min(coy, 2)
		end
		local cornerArt = skinTex(skin, "corner")
		local ct = chrome.corners
		local function corner(key, x, y, coords)
			local t = ct[key]
			t:SetTexture(cornerArt)
			t:ClearAllPoints()
			t:SetPoint(key, panel, key, x, y)
			t:SetSize(cw, ch)
			t:SetTexCoord(unpack(coords))
			-- Hide tall corner clasps on the 72px minimized header strip so they never dangle below it.
			t:SetShown(not minimized)
		end
		corner("TOPLEFT", -cox, coy, { 0, 1, 0, 1 })
		corner("TOPRIGHT", cox, coy, { 1, 0, 0, 1 })
		corner("BOTTOMLEFT", -cox, -coy, { 0, 1, 1, 0 })
		corner("BOTTOMRIGHT", cox, -coy, { 1, 0, 1, 0 })

		-- Rails (OVERLAY sublevel 1, BEHIND corners): tile segments using native asset aspect.
		local rh, rv = art.railH, art.railV
		local rhThick = compact and math.min(rh[3], 15) or rh[3]
		local rvThick = compact and math.min(rv[3], 15) or rv[3]
		local tileHW = rhThick * (rh[4] or (rh[1] / rh[2]))   -- on-screen width of one horizontal tile
		local tileVH = rvThick * (rv[4] or (rv[2] / rv[1]))   -- on-screen height of one vertical tile
		local railTex = skinTex(skin, "rail_h")
		local railVTex = skinTex(skin, "rail_v")
		local x0 = minimized and 0 or (compact and math.min(art.railInset or 14, 10) or (art.railInset or (cw - cox)))
		local spanX = math.max(0, W - 2 * x0)
		local function runPool(pool, span, tileLen, horizontal, flip, place, texPath, thick)
			layoutTilePool(f, pool, span, tileLen, thick, texPath, horizontal, flip, place, horizontal and art.railHCrop)
		end

		local outH = compact and math.min(art.outH or 0, 2) or (art.outH or 0)
		local outV = compact and math.min(art.outV or 0, 2) or (art.outV or 0)
		runPool(chrome.pools.top, spanX, tileHW, true, false, function(t, off)
			t:SetPoint("TOPLEFT", panel, "TOPLEFT", x0 + off, outH)
		end, railTex, rhThick)
		if minimized then
			for _, t in ipairs(chrome.pools.bottom) do t:Hide() end
		else
			runPool(chrome.pools.bottom, spanX, tileHW, true, true, function(t, off)
				t:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x0 + off, -outH)
			end, railTex, rhThick)
		end
		local y0 = compact and math.min(art.railInset or 14, 10) or (art.railInset or (ch - coy))
		local spanY = math.max(0, H - 2 * y0)
		if minimized then
			for _, t in ipairs(chrome.pools.left) do t:Hide() end
			for _, t in ipairs(chrome.pools.right) do t:Hide() end
		else
			runPool(chrome.pools.left, spanY, tileVH, false, false, function(t, off)
				t:SetPoint("TOPLEFT", panel, "TOPLEFT", -outV, -(y0 + off))
			end, railVTex, rvThick)
			runPool(chrome.pools.right, spanY, tileVH, false, true, function(t, off)
				t:SetPoint("TOPRIGHT", panel, "TOPRIGHT", outV, -(y0 + off))
			end, railVTex, rvThick)
		end

		-- Crest (centered, protruding above the top rail) + skin extras
		local hideCrest = panel._mmHideCrest == true
		if hideCrest then
			chrome.crest:Hide()
		else
			local cr = art.crest
			local crW, crH, crTop = cr[1], cr[2], cr[3]
			if compact then
				local crScale = math.min(1, 168 / math.max(1, crW))
				crW = math.floor(crW * crScale + 0.5)
				crH = math.floor(crH * crScale + 0.5)
				crTop = math.floor(crTop * crScale + 0.5)
			end
			chrome.crest:SetTexture(skinTex(skin, "crest"))
			chrome.crest:ClearAllPoints()
			chrome.crest:SetPoint("TOP", panel, "TOP", 0, crTop)
			chrome.crest:SetSize(crW, crH)
			chrome.crest:SetTexCoord(0, 1, 0, cr[4] or 1)
			chrome.crest:Show()
		end

		local bn = art.banner
		for _, side in ipairs({ "bannerL", "bannerR" }) do
			local t = chrome[side]
			if bn and not compact and not hideCrest and W > 760 then
				t:SetTexture(skinTex(skin, "banner"))
				t:ClearAllPoints()
				t:SetPoint("TOP", panel, "TOP", (side == "bannerL") and -bn[5] or bn[5], bn[6] + 6)
				t:SetSize(bn[3], bn[4])
				t:Show()
			else
				t:Hide()
			end
		end
		local ch = art.chain
		for _, side in ipairs({ "chainL", "chainR" }) do
			local t = chrome[side]
			if ch and not compact and not hideCrest and W > 900 then
				t:SetTexture(skinTex(skin, "chain"))
				t:ClearAllPoints()
				local x = math.min(ch[5], W / 2 - 60)
				t:SetPoint("BOTTOM", panel, "TOP", (side == "chainL") and -x or x, -2)
				t:SetSize(ch[3], ch[4])
				t:Show()
			else
				t:Hide()
			end
		end
	end

	function chrome:Paint(pal)
		pal = pal or Theme.GetActivePalette()
		if not pal.skin then return end
		local b, fb, fi = pal.winBg, pal.frameBorder, pal.frameInnerBorder
		chrome.base:SetColorTexture(b[1], b[2], b[3], 1)
		for _, e in ipairs({ "top", "bottom", "left", "right" }) do
			chrome.shell[e]:SetColorTexture(fb[1], fb[2], fb[3], fb[4] or 1)
			chrome.shellInner[e]:SetColorTexture(fi[1], fi[2], fi[3], fi[4] or 1)
		end
	end

	Theme.RegisterWidget(chrome, function(_, pal)
		if Theme.IsCustomSkin() then
			chrome:Paint(pal)
			chrome:Layout()
		else
			allHide()
		end
	end)
	if panel.HookScript then
		panel:HookScript("OnSizeChanged", function()
			if Theme.IsCustomSkin() then chrome:Layout() end
		end)
		panel:HookScript("OnShow", function()
			if Theme.IsCustomSkin() then chrome:Layout() end
		end)
	end
	if Theme.IsCustomSkin() then
		chrome:Paint(); chrome:Layout()
	else
		allHide()
	end
	return chrome
end

---------------------------------------------------------------------------------------------------
-- Main Window Liquid Glass Shell, Grips & Pixel Snapping

function Theme.DecorateMainWindow(panel, opts)
	opts = opts or {}
	local bannerH = opts.bannerH or 70
	local isFable = opts.fableShell == true

	-- Hide Blizzard template square/portrait borders
	for _, r in ipairs(panel.GetRegions and { panel:GetRegions() } or {}) do
		if r.GetObjectType and r:GetObjectType() == "Texture" and r.SetAlpha then r:SetAlpha(0) end
	end
	hideTemplateChrome(panel)
	if type(panel.TitleBg) == "table" and panel.TitleBg.SetAlpha then panel.TitleBg:SetAlpha(0) end
	if type(panel.TopTileStreaks) == "table" and panel.TopTileStreaks.SetAlpha then panel.TopTileStreaks:SetAlpha(0) end
	if type(panel.PortraitContainer) == "table" and panel.PortraitContainer.Hide then panel.PortraitContainer:Hide() end
	if type(panel.portrait) == "table" and panel.portrait.Hide then panel.portrait:Hide() end
	if type(panel.CloseButton) == "table" and panel.CloseButton.Hide then panel.CloseButton:Hide() end
	local tFs = panel.TitleText or (panel.TitleContainer and panel.TitleContainer.TitleText)
	if tFs and tFs.Hide then tFs:Hide() end
	if type(panel.TitleContainer) == "table" and panel.TitleContainer.Hide then panel.TitleContainer:Hide() end

	-- Soft macOS drop shadow behind outer 22px Liquid Glass frame
	local outerShadow = Theme.Nine(panel, panel, Theme.ASSETS.shadow_r22, 24, 16, "BACKGROUND", -8)
	outerShadow:SetColor(0, 0, 0, 0.45)

	-- 22px outer Liquid Glass rounded frame (fableShell paints split sidebar/rightPane fills + single WindowFrame perimeter)
	local outerGlass = Theme.NineApple(panel, "glass_r22", "winBg", "windowEdge", { layer = "BACKGROUND", sub = -7, noSpecular = true })
	if isFable then
		outerGlass:SetAlpha(0)
	end

	local deco = CreateFrame("Frame", nil, panel)
	deco:SetAllPoints(panel)
	if panel.GetFrameLevel and deco.SetFrameLevel then
		deco:SetFrameLevel(panel:GetFrameLevel() + 18)
	end
	Theme.WindowFrame(deco, panel)
	-- Warcraft skins: painted rails / corners / crest drawn over the shell (hidden on Standard).
	local warcraftChrome = isFable and Theme.CreateWarcraftFrameChrome(panel) or nil
	panel.warcraftChrome = warcraftChrome

	local bannerWash = panel:CreateTexture(nil, "BORDER", nil, 0)
	bannerWash:SetPoint("TOPLEFT", 2, -2)
	bannerWash:SetPoint("TOPRIGHT", -2, -2)
	bannerWash:SetHeight(bannerH)
	bannerWash:Hide()

	-- Legacy header controls kept hidden in fableShell mode while preserving returned API refs
	local crestBox = CreateFrame("Frame", nil, panel)
	crestBox:SetSize(44, 44)
	crestBox:SetPoint("TOPLEFT", 16, -13)
	Theme.Card(crestBox, crestBox, 10)
	local crestIcon = crestBox:CreateTexture(nil, "ARTWORK")
	crestIcon:SetPoint("TOPLEFT", 3, -3)
	crestIcon:SetPoint("BOTTOMRIGHT", -3, 3)
	local crestTex = opts.icon or ns.ADDON_ICON or ns.CRATE_ICON
	if crestIcon.SetTexCoord then
		if crestTex == ns.ADDON_ICON or crestTex == ns.ADDON_ICON_SMALL then
			crestIcon:SetTexCoord(0, 1, 0, 1)
		else
			crestIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		end
	end
	crestIcon:SetTexture(crestTex)

	local brandTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	brandTitle:SetPoint("TOPLEFT", 70, -15)
	Theme.ApplyFont(brandTitle, 20, "semibold")
	brandTitle:SetText(opts.title or "MerchantMaster")

	local brandSub = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	brandSub:SetPoint("TOPLEFT", brandTitle, "BOTTOMLEFT", 1, -3)
	Theme.ApplyFont(brandSub, 10, "regular")
	brandSub:SetText(opts.subtitle or "WOW FOREVER  ·  FAVOR, WRITS & MARKET OPTIMIZER")

	local closeBtn = Theme.CreatePlateButton(panel, "", 28, 24, { icon = Theme.ASSETS.icon_close, iconSize = 13, variant = "ghost", pill = true })
	closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -12)
	if panel.GetFrameLevel and closeBtn.SetFrameLevel then closeBtn:SetFrameLevel(panel:GetFrameLevel() + 25) end
	closeBtn:SetScript("OnClick", function() panel:Hide() end)
	closeBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(CLOSE or "Close")
		GameTooltip:Show()
	end)
	closeBtn:SetScript("OnLeave", GameTooltip_Hide)

	local gearBtn = Theme.CreatePlateButton(panel, "", 28, 24, { icon = Theme.ASSETS.icon_gear, iconSize = 14, variant = "ghost", pill = true })
	gearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -5, 0)
	if panel.GetFrameLevel and gearBtn.SetFrameLevel then gearBtn:SetFrameLevel(panel:GetFrameLevel() + 25) end
	if opts.onSettings then gearBtn:SetScript("OnClick", opts.onSettings) end
	gearBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(opts.settingsTitle or "MerchantMaster Settings", 1, 1, 1)
		GameTooltip:AddLine(opts.settingsDesc or "Open Options (Economy, Price Source, Mail/Bank/Alt Inventory & Minimap).", 0.85, 0.85, 0.88, true)
		GameTooltip:Show()
	end)
	gearBtn:SetScript("OnLeave", GameTooltip_Hide)

	local rightAnchor = gearBtn
	local ahRefresh
	if opts.refreshAH and not isFable then
		ahRefresh = ns.AHRefresh.Create(panel, rightAnchor)
		rightAnchor = ahRefresh.button
	end
	local companionBtn
	if opts.companionBtn and not isFable then
		local cb = opts.companionBtn
		companionBtn = Theme.CreatePlateButton(panel, cb.label or "Professor", cb.width or 78, 24, { variant = "secondary", pill = true })
		companionBtn:SetPoint("RIGHT", rightAnchor, "LEFT", -6, 0)
		if panel.GetFrameLevel and companionBtn.SetFrameLevel then companionBtn:SetFrameLevel(panel:GetFrameLevel() + 25) end
		if cb.onClick then companionBtn:SetScript("OnClick", cb.onClick) end
		companionBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(cb.tooltipTitle or cb.label or "Companion Addon", 1, 1, 1)
			if cb.tooltipBody then GameTooltip:AddLine(cb.tooltipBody, 0.85, 0.85, 0.88, true) end
			GameTooltip:Show()
		end)
		companionBtn:SetScript("OnLeave", GameTooltip_Hide)
		rightAnchor = companionBtn
	end

	local kpiPill = CreateFrame("Frame", nil, panel)
	kpiPill:SetSize(opts.kpiWidth or 330, 24)
	kpiPill:SetPoint("RIGHT", rightAnchor, "LEFT", -8, 0)
	Theme.NineApple(kpiPill, "pill", "pillTrack", false, { noSpecular = true })
	local kpiText = kpiPill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	kpiText:SetPoint("LEFT", 10, 0)
	kpiText:SetPoint("RIGHT", -10, 0)
	kpiText:SetJustifyH("CENTER")
	kpiText:SetWordWrap(false)
	Theme.ApplyFont(kpiText, 11, "regular")

	local verFs = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	verFs:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -34, 4)
	Theme.ApplyFont(verFs, 10, "regular")
	local verLabel = opts.versionText
	if verLabel == nil then
		local v = tostring((ns.GetAddonVersion and ns.GetAddonVersion()) or "dev")
		local prefix = (v:sub(1, 1) == "v" or v:sub(1, 1) == "V") and "" or "v"
		verLabel = prefix .. v .. "  \194\183  /mm"
	end
	verFs:SetText(verLabel)

	if isFable then
		crestBox:Hide()
		brandTitle:Hide()
		brandSub:Hide()
		closeBtn:Hide()
		gearBtn:Hide()
		kpiPill:Hide()
		verFs:Hide()
	end

	local resizeGrip
	local function paintChrome(_, pal)
		pal = pal or Theme.GetActivePalette()
		outerGlass:UpdateTheme()
		-- The split-pane shell paints its own panes; only the compact (bags) layout needs this backdrop.
		if isFable then outerGlass:SetAlpha(panel._mmCompactBackdrop and 1 or 0) end
		outerShadow:SetColor(0, 0, 0, (pal.mode == "light") and 0.28 or 0.50)
		if brandTitle.SetTextColor then brandTitle:SetTextColor(pal.text[1], pal.text[2], pal.text[3], pal.text[4] or 1) end
		if brandSub.SetTextColor then brandSub:SetTextColor(pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], pal.textSecondary[4] or 1) end
		if kpiText.SetTextColor then kpiText:SetTextColor(pal.text[1], pal.text[2], pal.text[3], pal.text[4] or 1) end
		if verFs.SetTextColor then verFs:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], pal.textMuted[4] or 1) end
		if resizeGrip then
			local gc = pal.textSecondary or pal.textMuted
			if gc then
				local nt = resizeGrip.GetNormalTexture and resizeGrip:GetNormalTexture()
				if nt and nt.SetVertexColor then nt:SetVertexColor(gc[1], gc[2], gc[3], gc[4] or 1) end
				local ht = resizeGrip.GetHighlightTexture and resizeGrip:GetHighlightTexture()
				if ht and ht.SetVertexColor then ht:SetVertexColor(gc[1], gc[2], gc[3], 0.55) end
			end
			if isFable and resizeGrip.SetAlpha then
				resizeGrip:SetAlpha(resizeGrip._hovered and 0.95 or 0.45)
			end
		end
	end

	local function winDB()
		if opts.getWindowDB then return opts.getWindowDB() end
		if type(_G.MerchantMasterDB) ~= "table" then return {} end
		if type(_G.MerchantMasterDB.window) ~= "table" then _G.MerchantMasterDB.window = {} end
		return _G.MerchantMasterDB.window
	end

	local function snapToPixels()
		if not (panel.GetLeft and panel.GetTop and panel.GetEffectiveScale) then return end
		local left, top = panel:GetLeft(), panel:GetTop()
		local s = panel:GetEffectiveScale()
		if not left or not top or not s or s <= 0 then return end
		local pl, pt = math.floor(left * s + 0.5) / s, math.floor(top * s + 0.5) / s
		if math.abs(pl - left) > 0.001 or math.abs(pt - top) > 0.001 then
			panel:ClearAllPoints()
			panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pl, pt)
		end
	end

	resizeGrip = CreateFrame("Button", nil, panel)
	resizeGrip:SetSize(22, 22)
	resizeGrip:SetPoint("BOTTOMRIGHT", -4, 4)
	resizeGrip:SetFrameLevel(panel:GetFrameLevel() + 30)
	resizeGrip:SetNormalTexture(A_ROOT .. "grip_resize")
	resizeGrip:SetHighlightTexture(A_ROOT .. "grip_resize", "ADD")
	if isFable then
		resizeGrip._hovered = false
		if resizeGrip.SetAlpha then resizeGrip:SetAlpha(0.45) end
		local nt = resizeGrip.GetNormalTexture and resizeGrip:GetNormalTexture()
		if nt and nt.SetDesaturated then nt:SetDesaturated(true) end
		local ht = resizeGrip.GetHighlightTexture and resizeGrip:GetHighlightTexture()
		if ht and ht.SetDesaturated then ht:SetDesaturated(true) end
	end
	paintChrome(Theme.GetMode(), Theme.GetActivePalette())
	Theme.RegisterWidget(panel, paintChrome)
	local heightGrip = CreateFrame("Button", nil, panel)
	heightGrip:SetSize(130, 14)
	heightGrip:SetPoint("CENTER", panel, "BOTTOM", 0, 2)
	heightGrip:SetFrameLevel(panel:GetFrameLevel() + 25)
	local bar = heightGrip:CreateTexture(nil, "ARTWORK")
	bar:SetSize(64, 14); bar:SetPoint("CENTER"); setTex(bar, A_ROOT .. "grip_height")
	if isFable then
		if bar.SetAlpha then bar:SetAlpha(0) end
		bar:Hide()
	else
		if bar.SetAlpha then bar:SetAlpha(0.55) end
	end

	local window = ns.Window.Attach(panel, resizeGrip, heightGrip, {
		getWindowDB = winDB,
		onLayout = opts.onLayout,
		defaultW = opts.defaultW,
		defaultH = opts.defaultH,
	})
	if isFable and resizeGrip.HookScript then
		resizeGrip:HookScript("OnEnter", function(self)
			self._hovered = true
			if self.SetAlpha then self:SetAlpha(0.95) end
		end)
		resizeGrip:HookScript("OnLeave", function(self)
			self._hovered = false
			if self.SetAlpha then self:SetAlpha(0.45) end
		end)
	end

	return {
		outerGlass  = outerGlass,
		outerShadow = outerShadow,
		warcraftChrome = warcraftChrome,
		crestBox    = crestBox,
		crestIcon   = crestIcon,
		brandTitle  = brandTitle,
		brandSub    = brandSub,
		kpiPill     = kpiPill,
		kpiText     = kpiText,
		closeBtn    = closeBtn,
		gearBtn     = gearBtn,
		resizeGrip  = resizeGrip,
		heightGrip  = heightGrip,
		verFs       = verFs,
		bannerWash  = bannerWash,
		snapToPixels = snapToPixels,
		window      = window,
		ahRefresh   = ahRefresh,
	}
end

---------------------------------------------------------------------------------------------------
-- Shared Sidebar Section Header, Sub-Panel Switcher & Floating Modal Helpers

function Theme.CreateSidebarSection(parent, title, topY, opts)
	opts = opts or {}
	local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.leftPad or 10, topY)
	hdr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(opts.rightPad or 10), topY)
	hdr:SetJustifyH("LEFT")
	hdr:SetWordWrap(false)
	Theme.ApplyFont(hdr, 11, "semibold")
	hdr:SetText(tostring(title or ""):upper())

	local line = parent:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.leftPad or 10, topY - 14)
	line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(opts.rightPad or 10), topY - 14)
	line:SetHeight(1)
	if opts.noLine then line:Hide() end

	local function paint(_, pal)
		pal = pal or Theme.GetActivePalette()
		if hdr.SetTextColor then
			local mc = pal.textGlassSecondary or pal.textMuted
			hdr:SetTextColor(mc[1], mc[2], mc[3], mc[4] or 1)
		end
		if line.SetColorTexture then
			local sep = pal.separator
			line:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.4) * 0.6)
		end
	end
	paint(Theme.GetMode(), Theme.GetActivePalette())
	Theme.RegisterWidget(hdr, paint)

	return topY - 18, hdr, line
end

function Theme.CreateSubTabBar(parent, defs, onSelect)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(26)
	Theme.NineApple(bar, "glass_r8", "pillTrack", false, { noSpecular = true })
	bar.buttons = {}
	local x = 4
	for _, d in ipairs(defs or {}) do
		local w = d.width or 118
		local b = Theme.CreatePlateButton(bar, d.label, w, 20, { fontSize = 11, variant = "ghost", pill = true })
		b:SetPoint("LEFT", bar, "LEFT", x, 0)
		local key = d.key
		b:SetScript("OnClick", function()
			if onSelect then onSelect(key) end
		end)
		if d.hint then
			b:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:AddLine(d.label, 1, 1, 1)
				GameTooltip:AddLine(d.hint, 0.85, 0.85, 0.88, true)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", GameTooltip_Hide)
		end
		bar.buttons[key] = b
		x = x + w + 4
	end
	bar.rightStart = x + 6
	function bar:SetActiveKey(activeKey)
		for k, btn in pairs(self.buttons) do
			btn:SetActive(k == activeKey)
		end
	end
	return bar
end

function Theme.CreateFloatingWindow(frameName, title, width, height, opts)
	opts = opts or {}
	local defaultW = width or 980
	local defaultH = height or 430
	local f = CreateFrame("Frame", frameName, UIParent)
	f:SetSize(defaultW, defaultH)
	local defaultCenterY = (opts.centerY ~= nil) and opts.centerY or (defaultH >= 600 and 0 or -40)
	f:SetPoint("CENTER", 0, defaultCenterY)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	if opts.dontSaveLayout or opts.resizable then
		if f.SetDontSavePosition then f:SetDontSavePosition(true) end
		if f.SetUserPlaced then f:SetUserPlaced(false) end
	end
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		if self.StopMovingOrSizing then self:StopMovingOrSizing() end
		if opts.dontSaveLayout or opts.resizable then
			if self.SetUserPlaced then self:SetUserPlaced(false) end
		end
		if opts.onMove then
			local pt, _, relPt, x, y = self:GetPoint(1)
			opts.onMove(pt, relPt, x, y)
		end
	end)
	f:Hide()
	if frameName and UISpecialFrames then
		tinsert(UISpecialFrames, frameName)
	end

	local shadow = Theme.Nine(f, f, Theme.ASSETS.shadow_r22, 24, 14, "BACKGROUND", -2)
	shadow:SetColor(0, 0, 0, 0.45)
	local appleGlass = Theme.NineApple(f, "glass_r16", "winBg", "borderStrong", { layer = "BACKGROUND", sub = 0 })

	local wantWarcraft = opts.warcraftChrome == true
	local compactChrome = opts.compactChrome == true
	local hideCrest = opts.hideCrest == true
	local useCartMedallion = opts.useCartMedallion == true
	local customTitleUpper = opts.customTitleUpper == true
	f._mmCompactChrome = compactChrome
	f._mmHideCrest = hideCrest
	f._mmUseCartMedallion = useCartMedallion
	f._mmBaseTitle = tostring(title or "Shopping List")
	local skinBaseBg, skinSurface, hdrSkinTile, hdrSkinBg, warcraftChrome
	if wantWarcraft then
		skinBaseBg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
		skinBaseBg:Hide()
		f.skinBaseBg = skinBaseBg
		skinSurface = f:CreateTexture(nil, "BACKGROUND", nil, -6)
		skinSurface:Hide()
		f.skinSurface = skinSurface
		warcraftChrome = Theme.CreateWarcraftFrameChrome(f)
		f.warcraftChrome = warcraftChrome
	end

	local hdr = CreateFrame("Frame", nil, f)
	hdr:SetPoint("TOPLEFT", 2, -2)
	hdr:SetPoint("TOPRIGHT", -2, -2)
	hdr:SetHeight(opts.headerHeight or (compactChrome and 38 or 42))
	local function syncHdrTileCoords(fallbackW, fallbackH)
		if not (hdrSkinTile and wantWarcraft and Theme.IsCustomSkin()) then return end
		local w = (hdr.GetWidth and hdr:GetWidth()) or 0
		local h = (hdr.GetHeight and hdr:GetHeight()) or 0
		if w <= 1 then w = fallbackW or defaultW end
		if h <= 1 then h = fallbackH or (opts.headerHeight or 44) end
		if hdrSkinTile.SetHorizTile then hdrSkinTile:SetHorizTile(false) end
		if hdrSkinTile.SetVertTile then hdrSkinTile:SetVertTile(false) end
		if hdrSkinTile.SetTexCoord then hdrSkinTile:SetTexCoord(0, w / 210, 0, h / 210) end
	end
	if wantWarcraft then
		hdrSkinTile = hdr:CreateTexture(nil, "BACKGROUND", nil, -2)
		hdrSkinTile:SetAllPoints(hdr)
		hdrSkinTile:Hide()
		f.hdrSkinTile = hdrSkinTile
		hdrSkinBg = hdr:CreateTexture(nil, "BACKGROUND", nil, -1)
		hdrSkinBg:SetAllPoints(hdr)
		hdrSkinBg:Hide()
		f.hdrSkinBg = hdrSkinBg
		if hdr.HookScript then
			hdr:HookScript("OnSizeChanged", function() syncHdrTileCoords() end)
		end
	end
	local hdrLine = hdr:CreateTexture(nil, "BORDER")
	hdrLine:SetPoint("BOTTOMLEFT", 12, 0)
	hdrLine:SetPoint("BOTTOMRIGHT", -12, 0)
	hdrLine:SetHeight(1)

	local hdrPortraitWrap, hdrPortraitSocket, hdrPortraitImg, hdrSubFs
	if opts.showPortrait or useCartMedallion then
		hdrPortraitWrap = CreateFrame("Frame", nil, hdr)
		hdrPortraitWrap:SetSize(34, 34)
		hdrPortraitWrap:SetPoint("LEFT", hdr, "LEFT", 36, 0)
		hdrPortraitSocket = hdrPortraitWrap:CreateTexture(nil, "BORDER")
		hdrPortraitSocket:SetAllPoints(hdrPortraitWrap)
		hdrPortraitImg = hdrPortraitWrap:CreateTexture(nil, "ARTWORK")
		hdrPortraitImg:SetPoint("TOPLEFT", 4, -4)
		hdrPortraitImg:SetPoint("BOTTOMRIGHT", -4, 4)
		if hdrPortraitImg.SetTexCoord then hdrPortraitImg:SetTexCoord(0.06, 0.94, 0.06, 0.94) end
		hdrPortraitWrap:Hide()
		f.hdrPortraitWrap = hdrPortraitWrap
		f.hdrPortraitSocket = hdrPortraitSocket
		f.hdrPortraitImg = hdrPortraitImg

		hdrSubFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hdrSubFs:SetJustifyH("LEFT")
		hdrSubFs:SetWordWrap(false)
		Theme.ApplyFont(hdrSubFs, 10, "semibold")
		f.hdrSubFs = hdrSubFs
	end

	local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleFs:SetPoint("LEFT", 16, 0)
	titleFs:SetJustifyH("LEFT")
	Theme.ApplyFont(titleFs, 14, "semibold")
	titleFs:SetText(tostring(title or "Shopping List"))
	f.titleFs = titleFs

	local closeBtn = Theme.CreatePlateButton(hdr, "", 26, 26, { icon = Theme.ASSETS.icon_close, iconSize = 11, variant = "ghost", pill = false })
	closeBtn:SetPoint("RIGHT", -10, 0)
	closeBtn:SetScript("OnClick", function() f:Hide() end)
	local closeSkinFrame = Theme.NineApple(closeBtn, "glass_r8", { 0.28, 0.05, 0.09, 0.94 }, { 0.78, 0.56, 0.20, 0.88 }, { layer = "BACKGROUND", sub = 2, cornerSize = 8, noSpecular = true })
	closeSkinFrame:SetShown(false)
	closeBtn._skinFrame = closeSkinFrame
	titleFs:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
	titleFs:SetWordWrap(false)
	f.closeBtn = closeBtn
	f.header = hdr

	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", 12, -48)
	body:SetPoint("BOTTOMRIGHT", -12, 12)
	f.body = body

	local resizeGrip, resizeSizePill
	local function paintResizeGrip(pal, isCustom)
		if not resizeGrip then return end
		pal = pal or Theme.GetActivePalette()
		local isLight = pal and pal.mode == "light"
		local hovered = resizeGrip._hovered == true or resizeGrip._resizing == true
		if f.GetFrameLevel and resizeGrip.SetFrameLevel then
			local targetLvl = f:GetFrameLevel() + 35
			resizeGrip._mmFrameLevel = targetLvl
			resizeGrip:SetFrameLevel(targetLvl)
		end
		if resizeSizePill and f.GetFrameLevel and resizeSizePill.SetFrameLevel then
			resizeSizePill:SetFrameLevel(f:GetFrameLevel() + 36)
		end
		resizeGrip:ClearAllPoints()
		if isCustom then
			resizeGrip:SetSize(26, 26)
			local gOff = compactChrome and 4 or 6
			resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -gOff, gOff)
		else
			resizeGrip:SetSize(24, 24)
			resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
		end
		if resizeGrip.plate then
			local bg = isCustom and { 0.08, 0.05, 0.04, hovered and 0.96 or 0.90 }
				or (isLight and { 0.90, 0.91, 0.94, hovered and 0.96 or 0.86 } or { 0.14, 0.16, 0.20, hovered and 0.96 or 0.86 })
			local bd = isCustom and (pal.gold or pal.frameBorder or { 0.95, 0.78, 0.34, 1 })
				or (isLight and (pal.borderStrong or { 0.42, 0.46, 0.54, 0.85 }) or (pal.borderStrong or { 0.62, 0.68, 0.78, 0.85 }))
			resizeGrip.plate:SetFill(bg[1], bg[2], bg[3], bg[4])
			resizeGrip.plate:SetStroke(bd[1], bd[2], bd[3], hovered and 1.0 or (isCustom and 0.92 or 0.75))
		end
		if resizeGrip.gripIcon then
			if resizeGrip.gripIcon.SetDesaturated then
				resizeGrip.gripIcon:SetDesaturated(not isCustom)
			end
			if isCustom then
				local gc = hovered and { 1.0, 0.96, 0.72, 1.0 } or { 0.98, 0.84, 0.44, 0.96 }
				resizeGrip.gripIcon:SetVertexColor(gc[1], gc[2], gc[3], gc[4])
			elseif isLight then
				local gc = hovered and { 0.08, 0.10, 0.14, 1.0 } or { 0.20, 0.24, 0.30, 0.92 }
				resizeGrip.gripIcon:SetVertexColor(gc[1], gc[2], gc[3], gc[4])
			else
				local gc = hovered and { 1.0, 1.0, 1.0, 1.0 } or { 0.82, 0.86, 0.92, 0.90 }
				resizeGrip.gripIcon:SetVertexColor(gc[1], gc[2], gc[3], gc[4])
			end
		end
		if resizeSizePill then
			if resizeSizePill.plate and resizeSizePill.plate.UpdateTheme then
				resizeSizePill.plate:UpdateTheme()
			end
			if resizeSizePill.fs and resizeSizePill.fs.SetTextColor then
				local tc = (isCustom and (pal.headGold or pal.text)) or pal.text
				if tc then resizeSizePill.fs:SetTextColor(tc[1], tc[2], tc[3], 1) end
			end
		end
	end

	if opts.resizable then
		if f.SetResizable then f:SetResizable(true) end
		local minW, minH = opts.minW or 780, opts.minH or 420
		local maxW, maxH = opts.maxW or 1440, opts.maxH or 860
		f._mmDefaultW, f._mmDefaultH = defaultW, defaultH
		f._mmMinW, f._mmMinH = minW, minH
		f._mmMaxW, f._mmMaxH = maxW, maxH
		if f.SetResizeBounds then
			f:SetResizeBounds(minW, minH, maxW, maxH)
		else
			if f.SetMinResize then f:SetMinResize(minW, minH) end
			if f.SetMaxResize then f:SetMaxResize(maxW, maxH) end
		end

		resizeGrip = CreateFrame("Button", nil, f)
		resizeGrip:SetSize(26, 26)
		resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
		if f.GetFrameLevel and resizeGrip.SetFrameLevel then
			local targetLvl = f:GetFrameLevel() + 35
			resizeGrip._mmFrameLevel = targetLvl
			resizeGrip:SetFrameLevel(targetLvl)
		end
		resizeGrip:EnableMouse(true)
		if resizeGrip.RegisterForClicks then
			resizeGrip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		end
		resizeGrip.plate = Theme.NineApple(resizeGrip, "glass_r8", "cardAltBg", "frameBorder", { cornerSize = 8, noSpecular = true })
		resizeGrip.gripIcon = resizeGrip:CreateTexture(nil, "OVERLAY")
		resizeGrip.gripIcon:SetSize(16, 16)
		resizeGrip.gripIcon:SetPoint("CENTER", 0, 0)
		resizeGrip.gripIcon:SetTexture(A_ROOT .. "grip_resize")
		resizeGrip:SetNormalTexture(A_ROOT .. "grip_resize")
		local nt0 = resizeGrip.GetNormalTexture and resizeGrip:GetNormalTexture()
		if nt0 and nt0.SetAlpha then nt0:SetAlpha(0) end
		resizeGrip:SetHighlightTexture(A_ROOT .. "grip_resize", "ADD")
		resizeGrip._hovered = false
		resizeGrip._resizing = false

		resizeSizePill = CreateFrame("Frame", nil, f)
		resizeSizePill:SetSize(96, 22)
		resizeSizePill:SetPoint("BOTTOMRIGHT", resizeGrip, "TOPLEFT", -4, 4)
		if f.GetFrameLevel and resizeSizePill.SetFrameLevel then
			resizeSizePill:SetFrameLevel(f:GetFrameLevel() + 36)
		end
		resizeSizePill.plate = Theme.NineApple(resizeSizePill, "glass_r8", "winBg", "frameBorder", { cornerSize = 8, noSpecular = true })
		resizeSizePill.fs = resizeSizePill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		resizeSizePill.fs:SetAllPoints(resizeSizePill)
		resizeSizePill.fs:SetJustifyH("CENTER")
		resizeSizePill.fs:SetWordWrap(false)
		Theme.ApplyFont(resizeSizePill.fs, 11, "semibold")
		resizeSizePill:Hide()
		f.resizeSizePill = resizeSizePill

		local function updateSizePill(nw, nh)
			if not resizeSizePill then return end
			resizeSizePill.fs:SetText(string.format("%d x %d", math.floor((nw or 0) + 0.5), math.floor((nh or 0) + 0.5)))
		end

		local function applyDragSize(nw, nh, isUser)
			nw = math.floor(math.max(minW, math.min(maxW, nw)) + 0.5)
			nh = math.floor(math.max(minH, math.min(maxH, nh)) + 0.5)
			f._mmApplyingSize = true
			f:SetSize(nw, nh)
			f._mmApplyingSize = false
			if warcraftChrome and Theme.IsCustomSkin() then warcraftChrome:Layout() end
			updateSizePill(nw, nh)
			if opts.onResize then opts.onResize(nw, nh, isUser == true) end
			return nw, nh
		end

		local function stopResize(self)
			if not self._resizing then return end
			self._resizing = false
			self:SetScript("OnUpdate", nil)
			if resizeSizePill then resizeSizePill:Hide() end
			if f.SetUserPlaced then f:SetUserPlaced(false) end
			paintResizeGrip(Theme.GetActivePalette(), wantWarcraft and Theme.IsCustomSkin())
			local cw = (f.GetWidth and f:GetWidth()) or defaultW
			local ch = (f.GetHeight and f:GetHeight()) or defaultH
			if warcraftChrome and Theme.IsCustomSkin() then warcraftChrome:Layout() end
			if opts.onResize then opts.onResize(cw, ch, true) end
		end

		resizeGrip:SetScript("OnMouseDown", function(self, btn)
			if btn == "RightButton" then
				stopResize(self)
				local rw, rh = applyDragSize(defaultW, defaultH, true)
				if opts.onResetSize then opts.onResetSize(rw, rh) end
				return
			end
			if btn ~= "LeftButton" or not GetCursorPosition then return end
			local startX, startY = GetCursorPosition()
			local startW = (f.GetWidth and f:GetWidth()) or defaultW
			local startH = (f.GetHeight and f:GetHeight()) or defaultH
			local effScale = (f.GetEffectiveScale and f:GetEffectiveScale()) or (f.GetScale and f:GetScale()) or 1
			if not effScale or effScale <= 0 then effScale = 1 end
			local left = f.GetLeft and f:GetLeft()
			local top = f.GetTop and f:GetTop()
			if left and top then
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
			end
			self._resizing = true
			paintResizeGrip(Theme.GetActivePalette(), wantWarcraft and Theme.IsCustomSkin())
			updateSizePill(startW, startH)
			if resizeSizePill then resizeSizePill:Show() end
			self:SetScript("OnUpdate", function()
				local cx, cy = GetCursorPosition()
				if not cx or not cy then return end
				local nw = startW + (cx - startX) / effScale
				local nh = startH + (startY - cy) / effScale
				applyDragSize(nw, nh, true)
			end)
		end)
		resizeGrip:SetScript("OnMouseUp", function(self, btn)
			if btn == "LeftButton" or self._resizing then
				stopResize(self)
			end
		end)
		resizeGrip:SetScript("OnHide", stopResize)
		resizeGrip:SetScript("OnEnter", function(self)
			self._hovered = true
			paintResizeGrip(Theme.GetActivePalette(), wantWarcraft and Theme.IsCustomSkin())
			if GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
				GameTooltip:AddLine(opts.resizeTitle or "Resize Window", 1, 0.85, 0.25)
				GameTooltip:AddLine(string.format("Drag to resize · Right-click to reset (%d x %d)", defaultW, defaultH), 0.90, 0.92, 0.96, true)
				if opts.getResizeTooltipInfo then
					local info = opts.getResizeTooltipInfo()
					if info and info ~= "" then
						GameTooltip:AddLine(info, 0.65, 0.88, 1.0, true)
					end
				end
				if Theme.LiftTooltip then Theme.LiftTooltip(GameTooltip) end
				GameTooltip:Show()
			end
		end)
		resizeGrip:SetScript("OnLeave", function(self)
			self._hovered = false
			paintResizeGrip(Theme.GetActivePalette(), wantWarcraft and Theme.IsCustomSkin())
			if GameTooltip_Hide then GameTooltip_Hide() elseif GameTooltip then GameTooltip:Hide() end
		end)
		if f.HookScript then
			f:HookScript("OnHide", function() stopResize(resizeGrip) end)
		end
		f.resizeGrip = resizeGrip
	end

	if f.HookScript then
		f:HookScript("OnSizeChanged", function(_, nw, nh)
			if warcraftChrome and Theme.IsCustomSkin() then warcraftChrome:Layout() end
			syncHdrTileCoords(nw or (f.GetWidth and f:GetWidth()), nil)
			if f._mmApplyingSize then return end
			if opts.onResize then
				opts.onResize(nw or f:GetWidth(), nh or f:GetHeight(), resizeGrip and resizeGrip._resizing == true)
			end
		end)
	end

	function f:SetWindowTitle(txt)
		self._mmBaseTitle = tostring(txt or "Shopping List")
		local isCustom = wantWarcraft and Theme.IsCustomSkin()
		titleFs:SetText((customTitleUpper and isCustom) and string.upper(self._mmBaseTitle) or self._mmBaseTitle)
	end

	local function paintModal(_, pal)
		pal = pal or Theme.GetActivePalette()
		local isCustom = wantWarcraft and Theme.IsCustomSkin()
		local skinKey = isCustom and Theme.GetSkin() or "standard"
		if appleGlass and appleGlass.UpdateTheme then appleGlass:UpdateTheme() end
		if appleGlass and appleGlass.SetAlpha then appleGlass:SetAlpha(isCustom and 0 or 1) end
		shadow:SetColor(0, 0, 0, (pal.mode == "light") and 0.28 or 0.48)

		local il, it, ir, ib = 0, 0, 0, 0
		if isCustom then
			il, it, ir, ib = Theme.GetSkinInset(skinKey)
			if compactChrome then
				il, it, ir, ib = math.min(il, 12), math.min(it, 12), math.min(ir, 12), math.min(ib, 12)
			end
		end

		if skinBaseBg then
			if isCustom then
				skinBaseBg:ClearAllPoints()
				skinBaseBg:SetPoint("TOPLEFT", f, "TOPLEFT", il, -it)
				skinBaseBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ir, ib)
				if skinKey == "goblin" then
					skinBaseBg:SetColorTexture(0.059, 0.169, 0.118, 1.0)
				else
					local wb = pal.winBg or { 0.08, 0.09, 0.11, 1.0 }
					skinBaseBg:SetColorTexture(wb[1], wb[2], wb[3], 1.0)
				end
				skinBaseBg:Show()
			else
				skinBaseBg:Hide()
			end
		end

		if skinSurface then
			if isCustom then
				skinSurface:SetTexture(Theme.GetSkinAsset(skinKey, "surface"), "CLAMP", "CLAMP")
				skinSurface:ClearAllPoints()
				skinSurface:SetPoint("TOPLEFT", f, "TOPLEFT", il, -it)
				skinSurface:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ir, ib)
				if skinSurface.SetTexCoord then skinSurface:SetTexCoord(0, 1, 0, 1) end
				skinSurface:SetVertexColor(1, 1, 1, skinKey == "goblin" and 0.88 or 0.92)
				skinSurface:Show()
			else
				skinSurface:Hide()
			end
		end

		local hdrH = isCustom and (opts.headerHeight or (compactChrome and 38 or 44)) or (opts.showPortrait and 46 or 36)
		hdr:ClearAllPoints()
		hdr:SetPoint("TOPLEFT", f, "TOPLEFT", isCustom and il or 2, isCustom and -it or -2)
		hdr:SetPoint("TOPRIGHT", f, "TOPRIGHT", isCustom and -ir or -2, isCustom and -it or -2)
		hdr:SetHeight(hdrH)

		if hdrSkinTile then
			if isCustom then
				hdrSkinTile:SetTexture(Theme.GetSkinAsset(skinKey, "header_tile"), "REPEAT", "REPEAT")
				hdrSkinTile:SetVertexColor(1, 1, 1, 1)
				hdrSkinTile:Show()
				local fw = (f.GetWidth and f:GetWidth()) or defaultW
				syncHdrTileCoords(math.max(1, fw - il - ir), hdrH)
			else
				hdrSkinTile:Hide()
			end
		end

		if hdrSkinBg then
			if isCustom then
				hdrSkinBg:SetTexture(Theme.GetSkinAsset(skinKey, "header_bg"))
				hdrSkinBg:SetVertexColor(1, 1, 1, skinKey == "goblin" and 0.72 or 0.85)
				hdrSkinBg:Show()
			else
				hdrSkinBg:Hide()
			end
		end

		closeBtn:ClearAllPoints()
		closeBtn:SetPoint("RIGHT", hdr, "RIGHT", isCustom and (compactChrome and -14 or -26) or -10, 0)
		if closeBtn._skinFrame then
			if isCustom then
				local fb = pal.frameBorder or { 0.78, 0.56, 0.20, 0.90 }
				local cFill = (skinKey == "goblin") and { 0.30, 0.05, 0.09, 0.94 } or { pal.toolbarBg[1] * 1.15, pal.toolbarBg[2] * 1.15, pal.toolbarBg[3] * 1.15, 0.92 }
				closeBtn._skinFrame:SetFill(cFill[1], cFill[2], cFill[3], cFill[4])
				closeBtn._skinFrame:SetStroke(fb[1], fb[2], fb[3], 0.85)
				closeBtn._skinFrame:SetShown(true)
			else
				closeBtn._skinFrame:SetShown(false)
			end
		end

		local titleLeft = isCustom and (compactChrome and 22 or 36) or 16
		if hdrPortraitWrap then
			if useCartMedallion then
				hdrPortraitWrap:ClearAllPoints()
				if isCustom then
					hdrPortraitWrap:SetPoint("LEFT", hdr, "LEFT", 36, 0)
					titleLeft = 78
				else
					hdrPortraitWrap:SetPoint("LEFT", hdr, "LEFT", 14, 0)
					titleLeft = 56
				end
				hdrPortraitSocket:Hide()
				hdrPortraitImg:ClearAllPoints()
				hdrPortraitImg:SetAllPoints(hdrPortraitWrap)
				if hdrPortraitImg.SetTexCoord then hdrPortraitImg:SetTexCoord(0, 1, 0, 1) end
				hdrPortraitImg:SetTexture(Theme.GetCartMedallionAsset(skinKey))
				hdrPortraitWrap:Show()
			elseif isCustom then
				hdrPortraitWrap:ClearAllPoints()
				hdrPortraitWrap:SetPoint("LEFT", hdr, "LEFT", 36, 0)
				hdrPortraitSocket:SetTexture(Theme.GetSkinAsset(skinKey, "socket"))
				hdrPortraitSocket:Show()
				hdrPortraitImg:ClearAllPoints()
				hdrPortraitImg:SetPoint("TOPLEFT", 4, -4)
				hdrPortraitImg:SetPoint("BOTTOMRIGHT", -4, 4)
				if hdrPortraitImg.SetTexCoord then hdrPortraitImg:SetTexCoord(0.06, 0.94, 0.06, 0.94) end
				hdrPortraitImg:SetTexture(Theme.GetSkinAsset(skinKey, "portrait"))
				hdrPortraitWrap:Show()
				titleLeft = 78
			else
				hdrPortraitWrap:Hide()
			end
		end

		if customTitleUpper then
			Theme.ApplyFont(titleFs, isCustom and 15 or 14, "semibold")
			titleFs:SetText(isCustom and string.upper(f._mmBaseTitle) or f._mmBaseTitle)
		end

		titleFs:ClearAllPoints()
		if hdrSubFs then
			titleFs:SetPoint("TOPLEFT", hdr, "TOPLEFT", titleLeft, -8)
			if opts.titleMaxWidth then
				titleFs:SetWidth(opts.titleMaxWidth)
			else
				titleFs:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
			end
			hdrSubFs:ClearAllPoints()
			hdrSubFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -2)
			if opts.titleMaxWidth then
				hdrSubFs:SetWidth(opts.titleMaxWidth)
			else
				hdrSubFs:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
			end
			local subCol = isCustom and (pal.accentGreen or pal.textSecondary) or (pal.textSecondary or pal.textMuted)
			hdrSubFs:SetTextColor(subCol[1], subCol[2], subCol[3], 1)
		else
			titleFs:SetPoint("LEFT", hdr, "LEFT", titleLeft, 0)
			titleFs:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
		end

		body:ClearAllPoints()
		local bodyPadX = isCustom and (il + (compactChrome and 6 or 14)) or 14
		local bodyPadB = isCustom and (ib + (compactChrome and 8 or 14)) or 14
		body:SetPoint("TOPLEFT", f, "TOPLEFT", bodyPadX, -(isCustom and (it + hdrH + 6) or (hdrH + 8)))
		body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -bodyPadX, bodyPadB)

		if resizeGrip then
			paintResizeGrip(pal, isCustom)
		end

		if hdrLine.SetColorTexture then
			local sep = (isCustom and pal.frameBorder) or pal.separator
			hdrLine:ClearAllPoints()
			hdrLine:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", isCustom and 0 or 12, 0)
			hdrLine:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", isCustom and 0 or -12, 0)
			hdrLine:SetHeight(isCustom and 2 or 1)
			hdrLine:SetColorTexture(sep[1], sep[2], sep[3], isCustom and 0.92 or (sep[4] or 0.45))
		end
		if titleFs.SetTextColor then
			local tc = (isCustom and pal.headGold) or pal.text
			titleFs:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
		if warcraftChrome and isCustom then
			warcraftChrome:Paint(pal)
			warcraftChrome:Layout()
		end
	end
	paintModal(Theme.GetMode(), Theme.GetActivePalette())
	Theme.RegisterWidget(f, paintModal)

	return f
end
