-- Police side of the cameras:
--   * Plate hits: an alert card when a camera flags a vehicle, and the
--     vehicle highlighted (outline through walls plus a marker with the
--     distance) for as long as the server says.
--   * Tamper alerts (smash mode, optional): a card and a marker on the
--     camera whose alarm went off.

local Theme = HeistFlock.Theme
local S = HeistFlock.S

local CARD_SHOW_TIME = 8
local UNITS_TO_METERS = 0.01905
local EDGE_MARGIN = 48

local hits = {}    -- vehicle entity index -> hit info
local tampers = {} -- camera entity index -> tamper alert
local cards = {}   -- alert cards on screen, newest first

local function addCard(card)
	card.shownAt = CurTime()
	table.insert(cards, 1, card)
	cards[4] = nil -- at most three cards at once

	surface.PlaySound("buttons/blip2.wav")
	timer.Simple(0.15, function() surface.PlaySound("buttons/blip2.wav") end)
end

net.Receive("HeistFlock_ALPRHit", function()
	local hit = {
		vehicleId = net.ReadUInt(16),
		plate = net.ReadString(),
		vehicleName = net.ReadString(),
		suspect = net.ReadString(),
		reason = net.ReadString(),
		role = net.ReadString(),
		camera = net.ReadString(),
		lastSeen = net.ReadVector(),
	}
	local highlightTime = net.ReadFloat()
	hit.untilTime = CurTime() + highlightTime
	hit.kind = "plate"

	-- 0 = a test alert with no car (Diagnostics): card and marker only.
	hits[hit.vehicleId == 0 and "test" or hit.vehicleId] = hit
	addCard(hit)
end)

net.Receive("HeistFlock_TamperAlert", function()
	local tamper = {
		kind = "tamper",
		cameraId = net.ReadUInt(16),
		camera = net.ReadString(),
		pos = net.ReadVector(),
	}
	tamper.untilTime = CurTime() + net.ReadFloat()

	tampers[tamper.cameraId] = tamper
	addCard(tamper)
end)

local function reasonText(hit)
	local who = hit.role == "driver" and "driver" or "owner"
	local what = hit.reason == "warrant" and "warrant" or "wanted"
	return HeistFlock.L("alpr_" .. who .. "_" .. what, { name = hit.suspect })
end

-- Drop expired hits.
local function cleanUp()
	local now = CurTime()
	for id, hit in pairs(hits) do
		if now > hit.untilTime then hits[id] = nil end
	end
	for id, tamper in pairs(tampers) do
		if now > tamper.untilTime then tampers[id] = nil end
	end
	for i = #cards, 1, -1 do
		if now - cards[i].shownAt > CARD_SHOW_TIME then table.remove(cards, i) end
	end
end

-- Outline flagged vehicles through walls.
hook.Add("PreDrawHalos", "HeistFlock_ALPR", function()
	if next(hits) == nil then return end

	local outlined = {}
	for _, hit in pairs(hits) do
		local vehicle = hit.vehicleId ~= 0 and Entity(hit.vehicleId)
		if IsValid(vehicle) then table.insert(outlined, vehicle) end
	end

	if #outlined > 0 then
		local pulse = 0.65 + math.sin(CurTime() * 6) * 0.35
		halo.Add(outlined, ColorAlpha(Theme.red, 255 * pulse), 2, 2, 2, true, true)
	end
end)

-- Screen position, pushed to the edge when off screen or behind you.
local function toScreenClamped(pos)
	local screen = pos:ToScreen()
	local x, y, w, h = screen.x, screen.y, ScrW(), ScrH()

	if screen.visible and x > EDGE_MARGIN and x < w - EDGE_MARGIN and y > EDGE_MARGIN and y < h - EDGE_MARGIN then
		return x, y, true
	end
	if not screen.visible then x, y = w - x, h - y end

	local cx, cy = w / 2, h / 2
	local dx, dy = x - cx, y - cy
	local scale = math.min((cx - EDGE_MARGIN) / math.max(math.abs(dx), 1), (cy - EDGE_MARGIN) / math.max(math.abs(dy), 1))
	return cx + dx * scale, cy + dy * scale, false
end

local function drawMarker(hit)
	local vehicle = hit.vehicleId ~= 0 and Entity(hit.vehicleId)
	local pos
	if IsValid(vehicle) then
		pos = vehicle:WorldSpaceCenter() + Vector(0, 0, 60)
		hit.lastSeen = vehicle:GetPos() -- remember it in case it drives out of range
	else
		pos = hit.lastSeen + Vector(0, 0, 60) -- too far away to see: show where it was
	end

	local x, y, onScreen = toScreenClamped(pos)
	local meters = math.Round(EyePos():Distance(pos) * UNITS_TO_METERS)
	local text = hit.plate .. "  ·  " .. meters .. " m"

	surface.SetFont("HeistFlock.MonoSm")
	local w, h = surface.GetTextSize(text) + S(20), S(24)
	HeistFlock.DrawBox(x - w / 2, y - h - S(8), w, h, ColorAlpha(Theme.background, 235), Theme.red)
	draw.SimpleText(text, "HeistFlock.MonoSm", x, y - h / 2 - S(8), Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.RoundedBox(S(4), x - S(4), y - S(4), S(8), S(8), onScreen and Theme.red or Theme.amber)
end

local function drawTamperMarker(tamper)
	local pos = tamper.pos + Vector(0, 0, 30)
	local x, y, onScreen = toScreenClamped(pos)
	local meters = math.Round(EyePos():Distance(pos) * UNITS_TO_METERS)
	local text = tamper.camera .. "  ·  " .. meters .. " m"

	surface.SetFont("HeistFlock.MonoSm")
	local w, h = surface.GetTextSize(text) + S(20), S(24)
	HeistFlock.DrawBox(x - w / 2, y - h - S(8), w, h, ColorAlpha(Theme.background, 235), Theme.amber)
	draw.SimpleText(text, "HeistFlock.MonoSm", x, y - h / 2 - S(8), Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.RoundedBox(S(4), x - S(4), y - S(4), S(8), S(8), onScreen and Theme.amber or Theme.red)
end

local function drawCard(hit, index)
	local age = CurTime() - hit.shownAt
	local slide = math.ease.OutCubic(math.min(age / 0.3, 1))
	local fade = math.Clamp((CARD_SHOW_TIME - age) / 0.6, 0, 1)
	local a = 255 * fade

	local w, h = S(320), S(96)
	local x = math.Round(ScrW() - (w + S(24)) * slide)
	local y = math.Round(S(24) + (index - 1) * (h + S(10)))
	local pad = S(14)

	HeistFlock.DrawBox(x, y, w, h, ColorAlpha(Theme.background, 240 * fade), ColorAlpha(Theme.red, a))
	draw.RoundedBox(0, x, y + S(10), S(3), h - S(20), ColorAlpha(Theme.red, a))

	if hit.kind == "tamper" then
		draw.SimpleText(HeistFlock.L("tamper_title"), "HeistFlock.Label", x + pad, y + S(10), ColorAlpha(Theme.red, a))
		draw.SimpleText(hit.camera, "HeistFlock.MonoBig", x + pad, y + S(22), ColorAlpha(Theme.text, a))
		draw.SimpleText(HeistFlock.L("tamper_text"), "HeistFlock.Small", x + pad, y + S(70), ColorAlpha(Theme.text, a))
		return
	end

	draw.SimpleText(HeistFlock.L("alpr_hit") .. "  ·  " .. hit.camera, "HeistFlock.Label", x + pad, y + S(10), ColorAlpha(Theme.red, a))
	draw.SimpleText(hit.plate, "HeistFlock.MonoBig", x + pad, y + S(22), ColorAlpha(Theme.text, a))
	draw.SimpleText(hit.vehicleName, "HeistFlock.Small", x + w - pad, y + S(32), ColorAlpha(Theme.textDim, a), TEXT_ALIGN_RIGHT)
	draw.SimpleText(reasonText(hit), "HeistFlock.Small", x + pad, y + S(70), ColorAlpha(Theme.text, a))
end

hook.Add("HUDPaint", "HeistFlock_ALPR", function()
	if next(hits) == nil and next(tampers) == nil and #cards == 0 then return end
	cleanUp()

	for _, hit in pairs(hits) do
		drawMarker(hit)
	end
	for _, tamper in pairs(tampers) do
		drawTamperMarker(tamper)
	end
	for index, hit in ipairs(cards) do
		drawCard(hit, index)
	end
end)
