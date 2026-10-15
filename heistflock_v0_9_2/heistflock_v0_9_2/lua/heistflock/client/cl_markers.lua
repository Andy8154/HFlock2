-- Camera markers for admins:
--   * Highlight one camera (click it in the menu): an outline through walls,
--     a beam of light above it, and an on-screen marker with the distance.
--     The marker sticks to the edge of the screen when the camera is behind you.
--   * Show all cameras (toggle in the menu): a small marker on every camera.
--
-- Positions come from the server's status info, so this works even for
-- cameras too far away for your game to have loaded.

local Config = HeistFlock.Config
local Theme = HeistFlock.Theme
local S = HeistFlock.S

local showAll = CreateClientConVar("heistflock_show_cameras", "0", true, false,
	"Show every Flock camera through walls (admins only)")

local HIGHLIGHT_TIME = 30     -- seconds a highlight lasts
local REFRESH_INTERVAL = 5    -- seconds between position updates while markers are on
local EDGE_MARGIN = 48
local UNITS_TO_METERS = 0.01905

local MAT_BEAM = Material("trails/laser")
local highlight -- { id, untilTime }
local nextRefresh = 0

function HeistFlock.HighlightCamera(id)
	if highlight and highlight.id == id then
		highlight = nil -- clicking the same camera again turns it off
	else
		highlight = { id = id, untilTime = CurTime() + HIGHLIGHT_TIME }
	end
end

function HeistFlock.GetHighlightedCamera()
	return highlight and highlight.id
end

function HeistFlock.SetShowAllCameras(enabled)
	RunConsoleCommand("heistflock_show_cameras", enabled and "1" or "0")
end

function HeistFlock.IsShowingAllCameras()
	return showAll:GetBool()
end

local function markersEnabled()
	return (highlight or showAll:GetBool()) and HeistFlock.HasAccess(LocalPlayer(), "view")
end

-- Where a camera is right now. Uses the live entity when this client has it,
-- otherwise the last position the server sent.
local function getCameraTransform(info)
	local cam = Entity(info.id)
	if IsValid(cam) and cam:GetClass() == "heistflock_camera" then
		return cam:GetPos(), cam:GetAngles(), cam:GetStage()
	end
	return info.pos, info.ang or angle_zero, info.stage
end

local function getBounds()
	if HeistFlock.UsesBuiltInModel() then
		return HeistFlock.BuiltInMins, HeistFlock.BuiltInMaxs
	end
	return Vector(-12, -12, -12), Vector(12, 12, 12)
end

-- The point to put the label at: the camera head.
local function getLabelPos(pos, ang)
	local offset = HeistFlock.UsesBuiltInModel() and HeistFlock.BuiltInHousingPos + Vector(0, 0, 22) or Vector(0, 0, 24)
	return LocalToWorld(offset, angle_zero, pos, ang)
end

-- Turns a world position into a screen position. Points off screen or
-- behind you are pushed to the screen edge. Returns x, y, onScreen.
local function toScreenClamped(pos)
	local screen = pos:ToScreen()
	local x, y = screen.x, screen.y
	local w, h = ScrW(), ScrH()

	if screen.visible and x > EDGE_MARGIN and x < w - EDGE_MARGIN and y > EDGE_MARGIN and y < h - EDGE_MARGIN then
		return x, y, true
	end

	if not screen.visible then
		x, y = w - x, h - y -- behind you: mirror so the marker points the right way
	end

	local centerX, centerY = w / 2, h / 2
	local dx, dy = x - centerX, y - centerY
	local scale = math.min((centerX - EDGE_MARGIN) / math.max(math.abs(dx), 1),
		(centerY - EDGE_MARGIN) / math.max(math.abs(dy), 1))

	return centerX + dx * scale, centerY + dy * scale, false
end

local function drawArrow(x, y, size, color)
	local angle = math.atan2(y - ScrH() / 2, x - ScrW() / 2)
	local function point(a, r)
		return { x = x + math.cos(angle + a) * r, y = y + math.sin(angle + a) * r }
	end

	surface.SetDrawColor(color)
	draw.NoTexture()
	surface.DrawPoly({ point(0, size), point(2.4, size * 0.7), point(-2.4, size * 0.7) })
	surface.DrawPoly({ point(0, size), point(-2.4, size * 0.7), point(2.4, size * 0.7) })
end

-- Keep positions fresh while markers are on and the menu isn't doing it.
hook.Add("Think", "HeistFlock_RefreshMarkers", function()
	if not markersEnabled() or CurTime() < nextRefresh then return end

	nextRefresh = CurTime() + REFRESH_INTERVAL
	HeistFlock.RequestServerInfo()
end)

-- Outlines and beam, drawn through walls.
hook.Add("PostDrawTranslucentRenderables", "HeistFlock_DrawMarkers", function(depth, skybox)
	if depth or skybox or not markersEnabled() or not HeistFlock.ServerInfo then return end

	if highlight and CurTime() > highlight.untilTime then
		highlight = nil
	end

	local mins, maxs = getBounds()
	local pulse = 0.6 + math.sin(CurTime() * 5) * 0.4

	cam.IgnoreZ(true)
	for _, info in ipairs(HeistFlock.ServerInfo.cameras) do
		local isHighlighted = highlight and highlight.id == info.id

		if isHighlighted or showAll:GetBool() then
			local pos, ang = getCameraTransform(info)
			local color = isHighlighted and ColorAlpha(Theme.accent, 255 * pulse) or ColorAlpha(Theme.text, 60)
			render.DrawWireframeBox(pos, ang, mins, maxs, color, false)

			if isHighlighted then
				render.SetMaterial(MAT_BEAM)
				render.DrawBeam(pos, pos + Vector(0, 0, 800), 10, 0, 1, ColorAlpha(Theme.accent, 160 * pulse))
			end
		end
	end
	cam.IgnoreZ(false)
end)

-- Labels on screen.
hook.Add("HUDPaint", "HeistFlock_DrawMarkerLabels", function()
	if not markersEnabled() or not HeistFlock.ServerInfo then return end

	local eyes = EyePos()
	local stageCount = #Config.Stages

	for _, info in ipairs(HeistFlock.ServerInfo.cameras) do
		local isHighlighted = highlight and highlight.id == info.id
		local pos, ang, stage = getCameraTransform(info)
		local meters = math.Round(eyes:Distance(pos) * UNITS_TO_METERS)

		if isHighlighted then
			local x, y, onScreen = toScreenClamped(getLabelPos(pos, ang))
			local text = string.format("CAM-%03d  ·  %d m  ·  %d/%d", info.id, meters, stage, stageCount)

			surface.SetFont("HeistFlock.MonoSm")
			local w, h = surface.GetTextSize(text) + S(20), S(26)

			HeistFlock.DrawBox(x - w / 2, y - h - S(10), w, h, ColorAlpha(Theme.background, 235), Theme.accent)
			draw.SimpleText(text, "HeistFlock.MonoSm", x, y - h / 2 - S(10), Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

			if onScreen then
				draw.RoundedBox(S(4), x - S(4), y - S(4), S(8), S(8), Theme.accent)
			else
				drawArrow(x, y, S(14), Theme.accent)
			end

		elseif showAll:GetBool() then
			local screen = getLabelPos(pos, ang):ToScreen()
			if screen.visible then
				local color = stage >= stageCount and Theme.red or Theme.text
				draw.RoundedBox(S(3), screen.x - S(3), screen.y - S(3), S(6), S(6), color)
				draw.SimpleText(string.format("CAM-%03d  %d m", info.id, meters), "HeistFlock.MonoSm", screen.x, screen.y - S(8),
					ColorAlpha(color, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			end
		end
	end
end)
