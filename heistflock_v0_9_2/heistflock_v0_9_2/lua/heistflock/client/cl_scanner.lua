-- Scanner view: a debug view of plate scanning, for admins with View.
-- Turn it on in !heistflock → Diagnostics, or heistflock_scanner_view 1.
--
-- For every camera near you it draws:
--   * its coverage: a fan as wide as the lens plus how far the head turns,
--     with rings every 10 m out to its range,
--   * where the head points right now, and a beam to the car it follows,
--   * a line to each car near it: green read, amber blocked, grey out of
--     view or range,
-- and over each car: its name, type, plate and where the plate came from,
-- and how far it is from each camera against that camera's range.
--
-- Everything comes from the server's own scan, so it shows what the server
-- really decided, not a guess made here.

local Theme = HeistFlock.Theme
local S = HeistFlock.S
local Config = HeistFlock.Config

local UNITS_TO_METERS = 0.01905
local RING_STEP = 10 / UNITS_TO_METERS -- a ring every 10 m
local CHECK_SHOW_TIME = 25
local MAT_BEAM = Material("trails/laser")

local view = CreateClientConVar("heistflock_scanner_view", "0", false, false,
	"Show what nearby Flock cameras see (admins with the HeistFlock View permission)")

local data, receivedAt   -- the latest scan from the server
local check, checkedAt   -- the latest "check this car" result

-- Turning it on and off ----------------------------------------------------------

local function tellServer(enabled)
	net.Start("HeistFlock_ScanDebugToggle")
	net.WriteBool(enabled)
	net.SendToServer()
end

cvars.AddChangeCallback("heistflock_scanner_view", function(_, _, newValue)
	local enabled = newValue == "1"
	tellServer(enabled)
	if not enabled then data = nil end
end, "HeistFlock_ScannerView")

-- The setting lasts through a map change, but the server forgets; remind it.
hook.Add("InitPostEntity", "HeistFlock_ScannerView", function()
	if view:GetBool() then tellServer(true) end
end)

function HeistFlock.SetScannerView(enabled)
	RunConsoleCommand("heistflock_scanner_view", enabled and "1" or "0")
end

function HeistFlock.IsScannerView()
	return view:GetBool()
end

net.Receive("HeistFlock_ScanDebug", function()
	data = net.ReadTable()
	receivedAt = CurTime()
end)

-- Test tools -----------------------------------------------------------------------

function HeistFlock.CheckCar()
	net.Start("HeistFlock_ScanCheck")
	net.SendToServer()
end

function HeistFlock.SendTestAlert()
	net.Start("HeistFlock_TestAlert")
	net.SendToServer()
end

concommand.Add("heistflock_check_car", HeistFlock.CheckCar, nil,
	"Which Flock cameras can see the car you're in or looking at, and why not")
concommand.Add("heistflock_test_alert", HeistFlock.SendTestAlert, nil,
	"Send yourself a test plate alert (nobody else sees it)")

-- Words ---------------------------------------------------------------------------

local function meters(units)
	return string.format("%.1f m", units * UNITS_TO_METERS)
end

-- Why a camera does or doesn't read a car, and the color for it.
local function describeWhy(entry)
	if entry.why == "seen" then return "reading", Theme.accent end
	if entry.why == "not_target" then return "in view, waiting its turn (single-target)", Theme.textFaint end
	if entry.why == "blocked" then return "blocked by " .. (entry.blocker or "something"), Theme.amber end
	if entry.why == "view" then return "outside its view", Theme.textFaint end
	if entry.why == "range" then return "out of range", Theme.textFaint end
	if entry.why == "blind" then return "camera is blind (damaged)", Theme.red end
	if entry.why == "off" then return "plate scanning is off", Theme.red end
	return tostring(entry.why), Theme.textDim
end

local function cameraLabel(id)
	return string.format("CAM-%03d", id)
end

-- "Check this car" result: in chat (and the console), and on screen for a bit.
net.Receive("HeistFlock_ScanCheckResult", function()
	check = net.ReadTable()
	checkedAt = CurTime()

	local vehicle = check.vehicle
	chat.AddText(Theme.accent, "[Heist Flock] ", Theme.text, vehicle.name .. "  ·  " .. (vehicle.plate ~= "" and vehicle.plate or "no plate yet"),
		Theme.textDim, "  (" .. vehicle.kind .. ", plate from " .. vehicle.plateSource .. ")")

	if #check.cameras == 0 then
		chat.AddText(Theme.textDim, "    No cameras within " .. meters(check.range * 1.5) .. ".")
	end
	for _, entry in ipairs(check.cameras) do
		local why, color = describeWhy(entry)
		chat.AddText(Theme.text, "    " .. cameraLabel(entry.id) .. "  " .. meters(entry.distance) .. " of " .. meters(check.range) .. "  ",
			color, why .. (entry.following and " (following it)" or ""))
	end
end)

-- Helpers ---------------------------------------------------------------------------

local function isStale()
	return not receivedAt or CurTime() - receivedAt > math.max((Config.ALPR.ScanInterval or 1) * 3, 3)
end

local function directionAt(yaw)
	return Angle(0, yaw, 0):Forward()
end

-- The car the local player is in, if the server described it.
local function myVehicleId()
	local seat = LocalPlayer():GetVehicle()
	if not IsValid(seat) then return end
	local parent = seat:GetParent()
	if IsValid(parent) and data.vehicles[parent:EntIndex()] then return parent:EntIndex() end
	return seat:EntIndex()
end

-- Every camera's entry for one car, read first, then closest.
local function entriesFor(vehicleId)
	local list = {}
	for _, camInfo in ipairs(data.cameras) do
		for _, entry in ipairs(camInfo.vehicles) do
			if entry.id == vehicleId then
				table.insert(list, { camera = camInfo.id, distance = entry.distance, why = entry.why, blocker = entry.blocker })
			end
		end
	end
	table.sort(list, function(a, b)
		if (a.why == "seen") ~= (b.why == "seen") then return a.why == "seen" end
		return a.distance < b.distance
	end)
	return list
end

local function active()
	return view:GetBool() and HeistFlock.HasAccess(LocalPlayer(), "view")
end

-- In the world: coverage fans, rings and lines ---------------------------------------

hook.Add("PostDrawTranslucentRenderables", "HeistFlock_ScannerView", function(depth, skybox)
	if depth or skybox or not active() or not data or data.disabled then return end

	local range, fov, swivel = data.range, data.fov, data.swivel
	local coverage = math.min(fov / 2 + swivel, 180)

	cam.IgnoreZ(true)
	for _, camInfo in ipairs(data.cameras) do
		local lens, baseYaw = camInfo.lens, camInfo.yaw
		local color = camInfo.scanning and Theme.accent or Theme.red
		local faint = ColorAlpha(color, 60)

		-- Coverage edges and the outer arc at full range.
		render.DrawLine(lens, lens + directionAt(baseYaw - coverage) * range, color, false)
		render.DrawLine(lens, lens + directionAt(baseYaw + coverage) * range, color, false)

		-- Rings every 10 m, so distances can be read off at a glance.
		local segments = 24
		for radius = RING_STEP, range, RING_STEP do
			local last
			for i = 0, segments do
				local point = lens + directionAt(baseYaw - coverage + coverage * 2 * i / segments) * radius
				if last then render.DrawLine(last, point, faint, false) end
				last = point
			end
		end
		local last
		for i = 0, segments do
			local point = lens + directionAt(baseYaw - coverage + coverage * 2 * i / segments) * range
			if last then render.DrawLine(last, point, color, false) end
			last = point
		end

		-- Where the head points now (the lens's own view, without turning).
		local ent = Entity(camInfo.id)
		local headYaw = baseYaw + (IsValid(ent) and ent.SwivelYaw or 0)
		render.DrawLine(lens, lens + directionAt(headYaw) * range * 0.4, Theme.text, false)
		render.DrawLine(lens, lens + directionAt(headYaw - fov / 2) * range * 0.25, ColorAlpha(Theme.text, 90), false)
		render.DrawLine(lens, lens + directionAt(headYaw + fov / 2) * range * 0.25, ColorAlpha(Theme.text, 90), false)

		-- A line to each car near it.
		for _, entry in ipairs(camInfo.vehicles) do
			local vehicle = Entity(entry.id)
			if IsValid(vehicle) then
				local _, lineColor = describeWhy(entry)
				render.DrawLine(lens, vehicle:WorldSpaceCenter(), lineColor, false)
			end
		end

		-- A beam to the car it follows.
		local target = camInfo.target ~= 0 and Entity(camInfo.target)
		if IsValid(target) then
			render.SetMaterial(MAT_BEAM)
			render.DrawBeam(lens, target:WorldSpaceCenter(), 4, 0, 1, ColorAlpha(Theme.accent, 200))
		end
	end
	cam.IgnoreZ(false)
end)

-- On screen: labels, the panel, and the last check ------------------------------------

-- A box of text lines ({ text, color }). anchor: "above" (centered above
-- x, y), "topleft" or "topright".
local function drawLines(lines, x, y, anchor)
	surface.SetFont("HeistFlock.Small")
	local width = 0
	for _, line in ipairs(lines) do
		width = math.max(width, surface.GetTextSize(line[1]))
	end

	local lineH = S(16)
	local w, h = width + S(16), #lines * lineH + S(10)
	local left, top = x, y
	if anchor == "above" then
		left, top = x - w / 2, y - h
	elseif anchor == "topright" then
		left = x - w
	end
	HeistFlock.DrawBox(left, top, w, h, ColorAlpha(Theme.background, 225), Theme.line)

	for i, line in ipairs(lines) do
		draw.SimpleText(line[1], "HeistFlock.Small", left + S(8), top + S(5) + (i - 1) * lineH, line[2] or Theme.text)
	end
end

local function drawCameraLabels()
	for _, camInfo in ipairs(data.cameras) do
		local screen = (camInfo.lens + Vector(0, 0, 26)):ToScreen()
		if screen.visible then
			local status, color
			if not camInfo.scanning then
				status, color = "blind", Theme.red
			else
				local target = camInfo.target ~= 0 and data.vehicles[camInfo.target]
				status = target and ("following " .. target.name) or "reading, nothing to follow"
				color = Theme.accent
			end
			drawLines({ { cameraLabel(camInfo.id) .. "  ·  " .. status, color } }, screen.x, screen.y, "above")
		end
	end
end

local function drawVehicleLabels()
	for id, info in pairs(data.vehicles) do
		local vehicle = Entity(id)
		if IsValid(vehicle) then
			local screen = (vehicle:WorldSpaceCenter() + Vector(0, 0, 70)):ToScreen()
			if screen.visible then
				local lines = {
					{ info.name .. "  ·  " .. (info.plate ~= "" and info.plate or "no plate yet"), Theme.text },
					{ info.kind .. "  ·  plate from " .. info.plateSource
						.. (info.plateStored ~= "" and ("  ·  stored as \"" .. info.plateStored .. "\"") or ""), Theme.textDim },
				}
				if info.flagged ~= "" then
					table.insert(lines, { "FLAGGED: " .. info.flagged .. (info.cooldown > 0 and ("  (next alert in " .. info.cooldown .. "s)") or ""), Theme.red })
				end

				for i, entry in ipairs(entriesFor(id)) do
					if i > 3 then break end
					local why, color = describeWhy(entry)
					local left = data.range - entry.distance
					local distanceText = meters(entry.distance) .. " of " .. meters(data.range)
						.. (left > 0 and ("  (" .. meters(left) .. " left)") or "")
					table.insert(lines, { cameraLabel(entry.camera) .. ": " .. distanceText .. "  ·  " .. why, color })
				end

				drawLines(lines, screen.x, screen.y, "above")
			end
		end
	end
end

local function drawPanel()
	if data and data.disabled then
		drawLines({
			{ "SCANNER VIEW", Theme.accent },
			{ "Plate scanning is turned off (Settings → Plate scanning), so cameras aren't reading anything.", Theme.amber },
			{ "Turn off: !heistflock → Diagnostics, or heistflock_scanner_view 0", Theme.textFaint },
		}, S(20), S(20), "topleft")
		return
	end

	if not data then
		drawLines({
			{ "SCANNER VIEW", Theme.accent },
			{ "Waiting for the server... (plate scanning off, or no permission?)", Theme.amber },
			{ "Turn off: !heistflock → Diagnostics, or heistflock_scanner_view 0", Theme.textFaint },
		}, S(20), S(20), "topleft")
		return
	end

	local stats = data.stats or {}
	local lines = {
		{ "SCANNER VIEW  ·  " .. #data.cameras .. " camera(s) near you", Theme.accent },
		{ string.format("Last scan %.2f ms  ·  average %.2f ms  ·  peak %.2f ms", stats.lastMs or 0, stats.averageMs or 0, stats.peakMs or 0), Theme.text },
		{ string.format("%d cameras reading  ·  %d cars on the map  ·  %d checks  ·  %d sight lines per scan",
			stats.cameras or 0, stats.vehicles or 0, stats.checks or 0, stats.traces or 0), Theme.textDim },
		{ string.format("Range %s  ·  lens %d°  ·  head turns %d° each way  ·  covers %d° in total",
			meters(data.range), data.fov, data.swivel, math.min(data.fov + data.swivel * 2, 360)), Theme.textDim },
		{ data.targetMode == "single" and "Single-target: only the car the camera follows is read; other visible cars wait." or "Multi-target: every eligible car in the full sweep can be read.", Theme.text },
		{ "Lines: green eligible/read  ·  amber blocked  ·  grey out of view/range/not selected  ·  beam = followed car", Theme.textFaint },
	}

	-- The car you're in.
	local myId = myVehicleId()
	local mine = myId and data.vehicles[myId]
	if mine then
		local entries = entriesFor(myId)
		local best = entries[1]
		local text = "Your car: " .. mine.name .. "  ·  " .. (mine.plate ~= "" and mine.plate or "no plate yet")
		if best then
			local why = describeWhy(best)
			text = text .. "  ·  " .. cameraLabel(best.camera) .. " " .. meters(best.distance) .. ", " .. why
			if best.why == "seen" then
				text = text .. ", leaves range in " .. meters(math.max(data.range - best.distance, 0))
			end
		end
		table.insert(lines, { text, Theme.text })
	end

	if isStale() then
		table.insert(lines, { "Waiting for the server... (plate scanning off, or no permission?)", Theme.amber })
	end
	table.insert(lines, { "Turn off: !heistflock → Diagnostics, or heistflock_scanner_view 0", Theme.textFaint })

	drawLines(lines, S(20), S(20), "topleft")
end

local function drawCheckResult()
	if CurTime() - checkedAt > CHECK_SHOW_TIME then
		check = nil
		return
	end

	local vehicle = check.vehicle
	local lines = {
		{ "CHECKED  ·  " .. vehicle.name .. "  ·  " .. (vehicle.plate ~= "" and vehicle.plate or "no plate yet"), Theme.accent },
		{ vehicle.kind .. "  ·  plate from " .. vehicle.plateSource
			.. (vehicle.plateStored ~= "" and (" (stored as \"" .. vehicle.plateStored .. "\")") or "")
			.. (vehicle.owner ~= "" and ("  ·  owner " .. vehicle.owner) or "")
			.. (vehicle.driver ~= "" and ("  ·  driver " .. vehicle.driver) or ""), Theme.textDim },
	}
	if vehicle.flagged ~= "" then table.insert(lines, { "Flagged: " .. vehicle.flagged, Theme.red }) end
	if #check.cameras == 0 then
		table.insert(lines, { "No cameras within " .. meters(check.range * 1.5) .. ".", Theme.textDim })
	end
	for i, entry in ipairs(check.cameras) do
		if i > 8 then break end
		local why, color = describeWhy(entry)
		table.insert(lines, { cameraLabel(entry.id) .. "  " .. meters(entry.distance) .. " of " .. meters(check.range)
			.. "  ·  " .. why .. (entry.following and " (following it)" or ""), color })
	end

	drawLines(lines, ScrW() - S(24), ScrH() * 0.55, "topright")
end

hook.Add("HUDPaint", "HeistFlock_ScannerView", function()
	if check then drawCheckResult() end
	if not active() then return end

	-- Old scans are dropped, not just labelled: what's drawn is always current.
	if data and isStale() then data = nil end

	if data and not data.disabled then
		drawCameraLabels()
		drawVehicleLabels()
	end
	drawPanel()
end)
