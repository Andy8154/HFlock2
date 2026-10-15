-- The Heist Flock look: colors, fonts, icons and drawing helpers.
-- Loaded before the other client files (alphabetical). Widgets built on
-- these are in cl_base_ui.lua.

local Theme = {
	background = Color(15, 16, 18),
	surface    = Color(21, 22, 25),
	raised     = Color(28, 29, 33),
	hover      = Color(35, 37, 42),
	input      = Color(12, 13, 15),
	line       = Color(38, 40, 46),

	text      = Color(234, 235, 237),
	textDim   = Color(148, 151, 158),
	textFaint = Color(88, 91, 98),

	accent     = Color(46, 230, 166),  -- night-vision mint
	accentSoft = Color(46, 230, 166, 28),
	accentText = Color(8, 28, 20),
	red        = Color(255, 82, 82),
	redSoft    = Color(255, 82, 82, 28),
	amber      = Color(255, 186, 74),
	amberSoft  = Color(255, 186, 74, 28),

	wires = {
		Color(235, 72, 72),   -- red
		Color(72, 140, 255),  -- blue
		Color(250, 210, 70),  -- yellow
		Color(60, 210, 120),  -- green
	},
}
HeistFlock.Theme = Theme

-- Scaling ------------------------------------------------------------------

-- Designed at 1080p; everything scales with screen height.
function HeistFlock.S(pixels)
	return math.Round(pixels * math.Clamp(ScrH() / 1080, 0.7, 2))
end
local S = HeistFlock.S

-- Fonts ----------------------------------------------------------------------
-- The font files ship in resource/fonts and download when players join.

-- Windows and macOS find fonts by their internal name; Linux (including the
-- Steam Deck) may need the file name instead, which is case-sensitive.
local SANS, SANS_BOLD, MONO = "HeistFlock Sans", "HeistFlock Sans Bold", "HeistFlock Mono"
if system.IsLinux() then
	SANS, SANS_BOLD, MONO = "heistflock_sans", "heistflock_sans_bold", "heistflock_mono"
end

-- The font files didn't download (no FastDL or Workshop content): use fonts
-- every player has, so text stays readable. Diagnostics shows it as "fonts NO".
local HAS_OWN_FONTS = file.Exists("resource/fonts/heistflock_sans.ttf", "GAME")
if not HAS_OWN_FONTS then
	SANS, SANS_BOLD, MONO = "Tahoma", "Tahoma", "Courier New"
end

-- name, face, size, bold
local FONTS = {
	{ "Huge",    SANS_BOLD, 40, true },
	{ "Big",     SANS_BOLD, 28, true },
	{ "Title",   SANS_BOLD, 22, true },
	{ "Heading", SANS_BOLD, 16, true },
	{ "Body",    SANS,      15 },
	{ "Small",   SANS,      13 },
	{ "Label",   SANS_BOLD, 11, true },
	{ "MonoBig", MONO,      28 },
	{ "Mono",    MONO,      14 },
	{ "MonoSm",  MONO,      12 },
}

local function createFonts()
	local override = HeistFlock.Config.FontOverride
	local useOverride = isstring(override) and override ~= ""
	if useOverride then override = string.sub(override, 1, 31) end -- Garry's Mod's font name limit

	for _, font in ipairs(FONTS) do
		surface.CreateFont("HeistFlock." .. font[1], {
			font = useOverride and override or font[2],
			size = S(font[3]),
			-- The bundled bold font is bold by itself; fallbacks need the weight.
			weight = (font[4] and (useOverride or not HAS_OWN_FONTS)) and 700 or 500,
			extended = true,
			antialias = true,
		})
	end
end

createFonts()
hook.Add("OnScreenSizeChanged", "HeistFlock_Fonts", createFonts)
HeistFlock.CreateFonts = createFonts -- run again if the server's config.json changes the font

-- Icons ----------------------------------------------------------------------
-- White line icons in materials/heistflock/ui, tinted when drawn.

local iconCache = {}

function HeistFlock.Icon(name)
	if not iconCache[name] then
		iconCache[name] = Material("heistflock/ui/" .. name .. ".png", "smooth mips")
	end
	return iconCache[name]
end

function HeistFlock.DrawIcon(name, x, y, size, color)
	local icon = HeistFlock.Icon(name)
	if icon:IsError() then return end -- not downloaded: draw nothing rather than a checkerboard
	surface.SetMaterial(icon)
	surface.SetDrawColor(color or Theme.text)
	surface.DrawTexturedRect(x, y, size, size)
end

-- Drawing helpers ----------------------------------------------------------

-- A rounded box with an optional 1px border.
function HeistFlock.DrawBox(x, y, w, h, fill, border, radius)
	radius = radius or S(4)

	if border then
		draw.RoundedBox(radius, x, y, w, h, border)
		draw.RoundedBox(math.max(radius - 1, 0), x + 1, y + 1, w - 2, h - 2, fill)
	else
		draw.RoundedBox(radius, x, y, w, h, fill)
	end
end

-- A keyboard key, e.g. E or LMB. Returns its width.
function HeistFlock.DrawKey(text, x, y, alpha)
	surface.SetFont("HeistFlock.MonoSm")
	local textWidth = surface.GetTextSize(text)
	local w, h = math.max(textWidth + S(10), S(20)), S(20)

	draw.RoundedBox(S(3), x, y, w, h, ColorAlpha(Theme.text, alpha or 255))
	draw.SimpleText(text, "HeistFlock.MonoSm", x + w / 2, y + h / 2, ColorAlpha(Theme.background, alpha or 255),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	return w
end

-- Moves a color toward another, for smooth hover effects.
function HeistFlock.LerpColor(t, from, to)
	return Color(
		Lerp(t, from.r, to.r),
		Lerp(t, from.g, to.g),
		Lerp(t, from.b, to.b),
		Lerp(t, from.a or 255, to.a or 255)
	)
end

-- 272 -> "4:32"
function HeistFlock.FormatTime(seconds)
	seconds = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Seconds ago -> "now", "4m", "2h"
function HeistFlock.FormatAgo(seconds)
	if seconds < 60 then return "now" end
	if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
	return math.floor(seconds / 3600) .. "h"
end

-- The button that starts work right now, for on-screen hints.
function HeistFlock.WorkKeyName()
	return HeistFlock.IsUsingPliers(LocalPlayer()) and "LMB" or "E"
end
