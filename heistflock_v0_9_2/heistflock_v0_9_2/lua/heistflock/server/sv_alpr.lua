--[[-------------------------------------------------------------------------
	HEIST FLOCK - PLATE SCANNING (ALPR)

	Working cameras read the plates of vehicles in front of them, and turn
	their head (up to ALPR.Swivel degrees each way) to follow one. When a
	vehicle's owner or driver is wanted, police get an alert and the vehicle
	is highlighted for them for a while. Damaged cameras are blind, so
	stripping one opens a gap in the network.

	Debug tools (admins with View, from Diagnostics): the scanner view, which
	draws what nearby cameras see and why each car is or isn't read; "check
	this car"; and a test alert sent only to yourself.

	Plates: Realistic Police's plate (the "rpt_plate" value it puts on every
	vehicle) when it's installed, otherwise a plate this addon makes up and
	keeps for that vehicle. Other plate addons can answer the
	HeistFlock_GetPlate hook (see hooks_reference.lua).
---------------------------------------------------------------------------]]

util.AddNetworkString("HeistFlock_ALPRHit")

local Config = HeistFlock.Config

HeistFlock.ALPRReads = HeistFlock.ALPRReads or {}  -- recent reads, newest first
local MAX_READS = 40

-- Vehicles --------------------------------------------------------------------
-- Tracked as they appear, so scanning never has to search every entity.

local vehicles = {}

-- Is this a drivable vehicle (not a chair or seat)?
local function isCar(ent)
	if not IsValid(ent) then return false end
	local class = ent:GetClass()

	if class == "prop_vehicle_prisoner_pod" then return false end -- seats and chairs
	if ent:IsVehicle() then return true end
	if class == "gmod_sent_vehicle_fphysics_base" then return true end -- simfphys
	return ent.LVS == true and ent.GetDriver ~= nil -- LVS
end

hook.Add("OnEntityCreated", "HeistFlock_ALPRTrack", function(ent)
	timer.Simple(0, function() -- the class isn't set up until the next tick
		if isCar(ent) then
			vehicles[ent] = true
			ent.HeistFlockSpawnedAt = CurTime()
		end
	end)
end)

hook.Add("EntityRemoved", "HeistFlock_ALPRTrack", function(ent)
	vehicles[ent] = nil
end)

-- A camera was removed: drop it from every vehicle's "last looked at by" list.
function HeistFlock.ForgetCamera(cam)
	for vehicle in pairs(vehicles) do
		if vehicle.HeistFlockLookedAt then vehicle.HeistFlockLookedAt[cam] = nil end
	end
end

-- Pick up vehicles that existed before this file loaded (e.g. a Lua refresh).
for _, ent in ipairs(ents.GetAll()) do
	if isCar(ent) then vehicles[ent] = true end
end

-- Plates, owners, names -------------------------------------------------------

local PLATE_LETTERS = "ABCDEFGHJKLMNPRSTUVWXYZ"

local function makePlate()
	local plate = ""
	for i = 1, 3 do
		local index = math.random(#PLATE_LETTERS)
		plate = plate .. string.sub(PLATE_LETTERS, index, index)
	end
	return plate .. "-" .. math.random(1000, 9999)
end

-- Where the plate comes from, for the Diagnostics page.
function HeistFlock.PlateSource()
	if Realistic_Police then return "Realistic Police" end
	return "Heist Flock"
end

-- Realistic Police sets a new vehicle's plate 2 seconds after it spawns.
-- Until then, cameras wait instead of reading a made-up plate.
local RPT_PLATE_WAIT = 4

-- Any plate text from any source, made safe to show: no control
-- characters, no spaces at the ends, at most 32 characters. Numbers from a
-- plate addon are turned into text. Returns nil if nothing is left.
local function cleanPlate(plate)
	if isnumber(plate) then plate = tostring(plate) end
	if not isstring(plate) then return end
	plate = string.Trim(string.gsub(plate, "%c", ""))
	if plate == "" then return end
	return string.sub(plate, 1, 32)
end

-- Realistic Police stores plates with spaces ("PR 917 AI") and only formats
-- them when it draws them on the car. This copies its drawing rule
-- (cl_rpt_main.lua) so alerts show exactly what's on the car:
--   * the plate style is PlateVehicle[the car's class], else LangagePlate
--   * if the stored plate splits on spaces into at least three pieces, the
--     first three are joined: with "-" for styles with PlateText (EU, "PR-917-AI"),
--     with nothing otherwise (US, "PR917AI")
--   * anything else is shown as stored.
-- Any style name works, including custom ones. If Realistic Police's config
-- is missing or different, the plate is shown as stored.
local function formatRealisticPolicePlate(vehicle, plate)
	local RP = Realistic_Police
	if not istable(RP) or not istable(RP.PlateConfig) then return plate end

	local class = isfunction(RP.GetVehicleClass) and RP.GetVehicleClass(vehicle) or vehicle:GetClass()
	local style = RP.LangagePlate
	if istable(RP.PlateVehicle) and isstring(RP.PlateVehicle[class]) then
		style = RP.PlateVehicle[class]
	end

	local config = RP.PlateConfig[style]
	if not istable(config) then return plate end

	local parts = string.Explode(" ", plate)
	if not (isstring(parts[1]) and isstring(parts[2]) and isstring(parts[3])) then return plate end

	local separator = config.PlateText and "-" or ""
	return parts[1] .. separator .. parts[2] .. separator .. parts[3]
end

-- The plate a camera reads, where it came from, and how it was stored
-- before formatting. nil if it isn't ready yet.
function HeistFlock.GetPlate(vehicle)
	local fromHook = cleanPlate(hook.Run("HeistFlock_GetPlate", vehicle))
	if fromHook then return fromHook, "another addon (HeistFlock_GetPlate)", fromHook end

	local stored = cleanPlate(vehicle:GetNWString("rpt_plate", ""))
	if stored then
		local plate = stored
		if Realistic_Police then
			local ok, formatted = pcall(formatRealisticPolicePlate, vehicle, stored)
			plate = (ok and cleanPlate(formatted)) or stored
		end
		return plate, "Realistic Police", stored
	end

	if Realistic_Police and CurTime() - (vehicle.HeistFlockSpawnedAt or 0) < RPT_PLATE_WAIT then
		return nil
	end

	-- Our own plate, made once per vehicle.
	if not vehicle.HeistFlockPlate then
		vehicle.HeistFlockPlate = makePlate()
	end
	return vehicle.HeistFlockPlate, Realistic_Police and "Heist Flock (Realistic Police gave none)" or "Heist Flock", vehicle.HeistFlockPlate
end

-- The player who owns the vehicle: DarkRP keys, then prop protection, then
-- the engine's owner.
function HeistFlock.GetVehicleOwner(vehicle)
	if vehicle.getDoorOwner then
		local owner = vehicle:getDoorOwner()
		if IsValid(owner) then return owner end
	end
	if vehicle.CPPIGetOwner then
		local owner = vehicle:CPPIGetOwner()
		if IsValid(owner) and owner:IsPlayer() then return owner end
	end
	local owner = vehicle:GetOwner()
	if IsValid(owner) and owner:IsPlayer() then return owner end
end

local function getDriver(vehicle)
	if vehicle.GetDriver then
		local driver = vehicle:GetDriver()
		if IsValid(driver) and driver:IsPlayer() then return driver end
	end
end

local function getVehicleName(vehicle)
	if vehicle.VC_getName then
		local ok, name = pcall(vehicle.VC_getName, vehicle)
		if ok and isstring(name) and name ~= "" then return name end
	end
	local class = vehicle.GetVehicleClass and vehicle:GetVehicleClass()
	local listed = class and list.Get("Vehicles")[class]
	if listed and listed.Name then return listed.Name end
	return vehicle.PrintName or "Vehicle"
end

-- Is this player someone police should hear about? Returns the reason or nil.
local function flagFor(ply)
	if not IsValid(ply) or not DarkRP then return end
	if ply:getDarkRPVar("wanted") then return "wanted" end
	if Config.ALPR.IncludeWarrants and ply.warranted then return "warrant" end -- DarkRP keeps warrants server-side
end

-- Alerts ------------------------------------------------------------------------

-- Returns true if police were told. False when no police are on, or another
-- addon blocked it; the vehicle is then tried again on the next scan.
local function sendAlert(cam, vehicle, plate, suspect, reason, role)
	local police = HeistFlock.GetPolice() -- sv_smash.lua
	if #police == 0 then return false end

	if hook.Run("HeistFlock_ALPRHit", cam, vehicle, plate, suspect, reason) == false then return false end

	local vehicleName = getVehicleName(vehicle)
	local cameraLabel = string.format("CAM-%03d", cam:EntIndex())

	net.Start("HeistFlock_ALPRHit")
	net.WriteUInt(vehicle:EntIndex(), 16)
	net.WriteString(plate)
	net.WriteString(vehicleName)
	net.WriteString(suspect:Nick())
	net.WriteString(reason) -- "wanted" or "warrant"
	net.WriteString(role)   -- "owner" or "driver"
	net.WriteString(cameraLabel)
	net.WriteVector(vehicle:GetPos())
	net.WriteFloat(Config.ALPR.HighlightTime)
	net.Send(police)

	HeistFlock.Stats.alprHits = (HeistFlock.Stats.alprHits or 0) + 1
	HeistFlock.AddActivity("alpr", cameraLabel .. " flagged " .. plate .. " (" .. suspect:Nick() .. ", " .. reason .. ")")
	HeistFlock.Log("ALPR hit: " .. plate .. " by " .. cameraLabel .. ", " .. role .. " " .. suspect:Nick() .. " is " .. reason)
	return true
end

-- Scanning ----------------------------------------------------------------------

-- Can this camera see right now? Damaged cameras are blind. With
-- AnyDamageBlinds, it goes blind from the first hit, or as soon as someone
-- starts stripping it (and sees again if they give up before the first
-- stage is done).
function HeistFlock.CameraCanScan(cam)
	local stage = cam:GetStage()
	if Config.ALPR.AnyDamageBlinds then
		return stage == 0 and cam:GetHits() == 0 and not IsValid(cam:GetWorker())
	end
	return stage < #Config.Stages
end

-- Where the lens is and which way the camera faces (before any swivel).
local function lensOf(cam)
	return HeistFlock.GetHousingPos(cam) + cam:GetForward() * 10, cam:GetForward()
end
HeistFlock.LensOf = lensOf

-- How wide a camera covers, in degrees either side of where it faces: half
-- the lens's field of view, plus however far the head can turn.
function HeistFlock.CoverageAngle()
	return math.min(Config.ALPR.FieldOfView / 2 + Config.ALPR.Swivel, 180)
end

-- Numbers from the last scans, for Diagnostics: how long scanning takes and
-- how much work it does.
local stats = { scans = 0, lastMs = 0, averageMs = 0, peakMs = 0, cameras = 0, vehicles = 0, checks = 0, traces = 0 }
HeistFlock.ScanStats = stats

-- Can this camera see this vehicle? Returns:
--   true, nil, distance                 it can
--   false, why, distance, blocker       "range", "view" or "blocked" (blocker = what's in the way)
local function canSee(cam, lensPos, facing, vehicle, maxRangeSqr, minDot)
	local target = vehicle:WorldSpaceCenter()
	local offset = target - lensPos
	local distSqr = offset:LengthSqr()
	if distSqr > maxRangeSqr or distSqr < 1 then return false, "range", math.sqrt(distSqr) end

	offset:Normalize()
	if offset:Dot(facing) < minDot then return false, "view", math.sqrt(distSqr) end

	-- Walls and props block the view; people (including whoever is in the
	-- car) don't.
	stats.traces = stats.traces + 1
	local trace = util.TraceLine({
		start = lensPos,
		endpos = target,
		mask = MASK_SOLID,
		filter = function(ent)
			return ent ~= cam and not ent:IsPlayer()
		end,
	})

	local hitEnt = trace.Entity
	if not trace.Hit or hitEnt == vehicle or (IsValid(hitEnt) and hitEnt:GetParent() == vehicle) then
		return true, nil, math.sqrt(distSqr)
	end
	return false, "blocked", math.sqrt(distSqr), IsValid(hitEnt) and hitEnt:GetClass() or "the map"
end

-- Sightings: one car seen by the camera network. While cameras keep seeing
-- it, the same sighting grows (each camera that saw it is added). A new one
-- starts once the car has gone unseen for SIGHTING_GAP seconds, or
-- SIGHTING_MAX seconds after the last one began, so a car driving past
-- seven cameras is one entry, and a parked car is logged every few minutes
-- rather than every scan. "Plates read" counts sightings.
local SIGHTING_GAP = 60
local SIGHTING_MAX = 300
local MAX_CAMERAS_PER_SIGHTING = 16

local function inSighting(sighting, now)
	return sighting ~= nil and now - sighting.lastSeen < SIGHTING_GAP and now - sighting.started < SIGHTING_MAX
end

local function addToSighting(sighting, cam, flagged, now)
	sighting.lastSeen = now
	local cameras = sighting.entry.cameras
	local id = cam:EntIndex()
	if not table.HasValue(cameras, id) and #cameras < MAX_CAMERAS_PER_SIGHTING then
		table.insert(cameras, id)
	end
	if flagged then sighting.entry.flagged = true end
end

local function startSighting(cam, vehicle, plate, flagged, now)
	local entry = {
		camera = cam:EntIndex(), -- the first camera that saw it
		cameras = { cam:EntIndex() },
		plate = plate,
		flagged = flagged,
		time = os.time(),
	}
	table.insert(HeistFlock.ALPRReads, 1, entry)
	HeistFlock.ALPRReads[MAX_READS + 1] = nil
	HeistFlock.Stats.platesRead = (HeistFlock.Stats.platesRead or 0) + 1

	vehicle.HeistFlockSighting = { entry = entry, plate = plate, started = now, lastSeen = now }
end

-- The flagged player in or behind this vehicle: the driver first, then the owner.
local function findSuspect(vehicle)
	local driver = getDriver(vehicle)
	local driverFlag = flagFor(driver)
	if driverFlag then return driver, driverFlag, "driver" end

	local owner = HeistFlock.GetVehicleOwner(vehicle)
	local ownerFlag = flagFor(owner)
	if ownerFlag then return owner, ownerFlag, "owner" end
end

local function readVehicle(cam, vehicle, now)
	local suspect, reason, role = findSuspect(vehicle)
	local sighting = vehicle.HeistFlockSighting
	local wantsAlert = suspect ~= nil and now >= (vehicle.HeistFlockAlertUntil or 0)

	-- Already sighted and nothing to report: just note this camera saw it
	-- too (no plate lookup needed).
	if inSighting(sighting, now) and not wantsAlert then
		addToSighting(sighting, cam, suspect ~= nil, now)
		return
	end

	local plate = HeistFlock.GetPlate(vehicle)
	if not plate then return end -- not set yet; try again next scan

	-- One alert per vehicle per cooldown, whichever camera sees it. The
	-- cooldown only starts once police were actually told.
	if wantsAlert and sendAlert(cam, vehicle, plate, suspect, reason, role) then
		vehicle.HeistFlockAlertUntil = now + Config.ALPR.AlertCooldown
	end

	if inSighting(sighting, now) and sighting.plate == plate then
		addToSighting(sighting, cam, suspect ~= nil, now)
	else
		startSighting(cam, vehicle, plate, suspect ~= nil, now) -- new, or the plate changed
	end
end

-- Tracking: each camera turns its head toward one car it can see. It keeps
-- following the same car while it can, otherwise picks the closest. Players'
-- games do the turning (cl_init.lua); the server only says which car.
local function setTarget(cam, vehicle)
	if cam:GetTrackTarget() == (vehicle or NULL) then return end
	cam:SetTrackTarget(vehicle or NULL)

	if IsValid(vehicle) then
		cam.TrackSince = CurTime()
		vehicle.HeistFlockLookedAt = vehicle.HeistFlockLookedAt or {}
		vehicle.HeistFlockLookedAt[cam] = CurTime()
	end
end

-- Single-target: how long a camera stays on one car before it looks at the
-- next one in view. Without this, a parked car would hold the camera
-- forever and a wanted car driving past would never be read.
local SINGLE_TARGET_DWELL = 3

-- Single-target: stay on the current car for a moment, then move to the
-- car in view this camera looked at longest ago (closest first when tied),
-- so every car in view gets read in turn.
local function pickSingleTarget(cam, visible, current, now)
	local currentVisible = false
	for _, seen in ipairs(visible) do
		if seen.vehicle == current then currentVisible = true break end
	end
	if currentVisible and now - (cam.TrackSince or 0) < SINGLE_TARGET_DWELL then return current end

	local best, bestLooked, bestDistance
	for _, seen in ipairs(visible) do
		local looked = seen.vehicle.HeistFlockLookedAt and seen.vehicle.HeistFlockLookedAt[cam] or 0
		if not best or looked < bestLooked or (looked == bestLooked and seen.distance < bestDistance) then
			best, bestLooked, bestDistance = seen.vehicle, looked, seen.distance
		end
	end
	return best
end

-- Admins watching the scanner (see "Scanner view" below).
local debugWatchers = {}
local DEBUG_RADIUS = 4000 -- only cameras this close to the admin are sent

local function scan()
	local settings = Config.ALPR
	local cameras = ents.FindByClass("heistflock_camera")

	if not settings.Enabled then
		for _, cam in ipairs(cameras) do setTarget(cam, nil) end
		HeistFlock.SendScanDebugDisabled()
		return
	end

	local started = SysTime()
	stats.checks, stats.traces, stats.cameras, stats.vehicles = 0, 0, 0, table.Count(vehicles)

	local maxRangeSqr = settings.Range ^ 2
	local minDot = math.cos(math.rad(HeistFlock.CoverageAngle()))
	local now = CurTime()

	-- Which cameras each watching admin is near, worked out once per scan.
	local watched = {}
	for ply in pairs(debugWatchers) do
		if not IsValid(ply) or not HeistFlock.HasAccess(ply, "view") then
			debugWatchers[ply] = nil
		end
	end
	local anyWatchers = next(debugWatchers) ~= nil

	for _, cam in ipairs(cameras) do
		local debugEntry
		if anyWatchers then
			for ply in pairs(debugWatchers) do
				if ply:GetPos():DistToSqr(cam:GetPos()) <= DEBUG_RADIUS ^ 2 then
					debugEntry = { vehicles = {} }
					watched[cam] = debugEntry
					break
				end
			end
		end

		if not HeistFlock.CameraCanScan(cam) then
			setTarget(cam, nil)
		else
			stats.cameras = stats.cameras + 1
			local lensPos, facing = lensOf(cam)
			local current = cam:GetTrackTarget()
			local single = settings.TargetMode == "single"
			local keepCurrent, closest, closestDist = false, nil, math.huge
			local visibleList = {}

			for vehicle in pairs(vehicles) do
				if not IsValid(vehicle) then
					vehicles[vehicle] = nil
				else
					stats.checks = stats.checks + 1
					local visible, why, distance, blocker = canSee(cam, lensPos, facing, vehicle, maxRangeSqr, minDot)

					if visible then
						if single then
							table.insert(visibleList, { vehicle = vehicle, distance = distance })
						else
							readVehicle(cam, vehicle, now)
						end
						if vehicle == current then keepCurrent = true end
						if distance < closestDist then closest, closestDist = vehicle, distance end
					end

					-- Only cars somewhat near the camera, so the list stays short.
					if debugEntry and distance <= settings.Range * 1.5 and #debugEntry.vehicles < 8 then
						table.insert(debugEntry.vehicles, { id = vehicle:EntIndex(), distance = math.Round(distance),
							why = why or "seen", blocker = blocker })
					end
				end
			end

			-- Both modes find cars across the whole sweep. Multi-target reads
			-- every car in it and follows one (the same one while it can, else
			-- the closest). Single-target reads only the car it follows, and
			-- takes turns between the cars in view (see pickSingleTarget).
			local target
			if single then
				target = pickSingleTarget(cam, visibleList, current, now)
			else
				target = keepCurrent and current or closest
			end
			setTarget(cam, target)

			if single then
				if IsValid(target) then readVehicle(cam, target, now) end
				if debugEntry then
					local targetId = IsValid(target) and target:EntIndex() or 0
					for _, entry in ipairs(debugEntry.vehicles) do
						if entry.why == "seen" and entry.id ~= targetId then entry.why = "not_target" end
					end
				end
			end
		end
	end

	local elapsedMs = (SysTime() - started) * 1000
	stats.scans = stats.scans + 1
	stats.lastMs = elapsedMs
	stats.averageMs = stats.averageMs + (elapsedMs - stats.averageMs) * 0.1 -- a running average
	stats.peakMs = math.max(stats.peakMs * 0.995, elapsedMs)                -- slowly forgets old peaks

	if anyWatchers then HeistFlock.SendScanDebug(watched) end
end

local function startScanning()
	timer.Create("HeistFlock_ALPR", math.max(Config.ALPR.ScanInterval, 0.25), 0, scan)
end

startScanning()
hook.Add("HeistFlock_SettingsChanged", "HeistFlock_ALPR", startScanning) -- the interval may have changed

-- What kind of vehicle this is, in words, for the debug tools.
function HeistFlock.VehicleKind(vehicle)
	local class = vehicle:GetClass()
	if class == "gmod_sent_vehicle_fphysics_base" then return "simfphys" end
	if vehicle.LVS then return "LVS" end
	if vehicle:IsVehicle() then
		return (VC and vehicle.VC_getName) and "Source vehicle (VCMod)" or "Source vehicle"
	end
	return class
end

-- Everything the debug tools show about one vehicle.
local function describeVehicle(vehicle)
	local plate, plateSource, stored = HeistFlock.GetPlate(vehicle)
	local owner, driver = HeistFlock.GetVehicleOwner(vehicle), getDriver(vehicle)
	local suspect, reason, role = findSuspect(vehicle)

	return {
		id = vehicle:EntIndex(),
		name = getVehicleName(vehicle),
		class = vehicle:GetClass(),
		kind = HeistFlock.VehicleKind(vehicle),
		plate = plate or "",
		plateSource = plateSource or "waiting for Realistic Police",
		plateStored = (stored and stored ~= plate) and stored or "", -- e.g. "PR 917 AI" shown as "PR917AI"
		owner = IsValid(owner) and owner:Nick() or "",
		driver = IsValid(driver) and driver:Nick() or "",
		flagged = suspect and (role .. " " .. suspect:Nick() .. " is " .. reason) or "",
		cooldown = math.max(math.ceil((vehicle.HeistFlockAlertUntil or 0) - CurTime()), 0),
	}
end

-- Scanner view (debug) --------------------------------------------------------
-- Admins with View can turn on a live view of what nearby cameras see. Once
-- per scan they're sent each nearby camera's coverage, the car it follows,
-- and why each car near it is or isn't read.

util.AddNetworkString("HeistFlock_ScanDebugToggle")
util.AddNetworkString("HeistFlock_ScanDebug")
util.AddNetworkString("HeistFlock_ScanCheck")
util.AddNetworkString("HeistFlock_ScanCheckResult")
util.AddNetworkString("HeistFlock_TestAlert")

net.Receive("HeistFlock_ScanDebugToggle", function(len, ply)
	if HeistFlock.IsThrottled(ply, "scandebug", 0.5) then return end
	local enabled = net.ReadBool()

	if enabled and HeistFlock.RequireAccess(ply, "view") then
		debugWatchers[ply] = true
	else
		debugWatchers[ply] = nil
	end
end)

-- Scanning is off: tell watching admins, so their view clears instead of
-- showing the last scan.
function HeistFlock.SendScanDebugDisabled()
	for ply in pairs(debugWatchers) do
		if IsValid(ply) then
			net.Start("HeistFlock_ScanDebug")
			net.WriteTable({ disabled = true })
			net.Send(ply)
		else
			debugWatchers[ply] = nil
		end
	end
end

function HeistFlock.SendScanDebug(watched)
	local settings = Config.ALPR

	for ply in pairs(debugWatchers) do
		local cameras, described = {}, {}
		local myPos = ply:GetPos()

		for cam, entry in pairs(watched) do
			if myPos:DistToSqr(cam:GetPos()) <= DEBUG_RADIUS ^ 2 and #cameras < 12 then
				local lensPos, facing = lensOf(cam)
				local target = cam:GetTrackTarget()

				for _, seen in ipairs(entry.vehicles) do
					local vehicle = Entity(seen.id)
					if not described[seen.id] and IsValid(vehicle) then
						described[seen.id] = describeVehicle(vehicle)
					end
				end

				table.insert(cameras, {
					id = cam:EntIndex(),
					lens = lensPos,
					yaw = facing:Angle().y,
					scanning = HeistFlock.CameraCanScan(cam),
					target = IsValid(target) and target:EntIndex() or 0,
					vehicles = entry.vehicles,
				})
			end
		end

		net.Start("HeistFlock_ScanDebug")
		net.WriteTable({
			range = settings.Range,
			targetMode = settings.TargetMode or "multi",
			fov = settings.FieldOfView,
			swivel = settings.Swivel,
			cameras = cameras,
			vehicles = described,
			stats = stats,
		})
		net.Send(ply)
	end
end

-- The car a player means: the one they're in, or the one they look at.
local function vehicleFor(ply)
	local seat = ply:GetVehicle()
	if IsValid(seat) then
		if vehicles[seat] then return seat end
		local parent = seat:GetParent() -- simfphys and LVS seats sit on the car
		if IsValid(parent) and vehicles[parent] then return parent end
	end

	local looked = ply:GetEyeTrace().Entity
	if IsValid(looked) then
		if vehicles[looked] then return looked end
		local parent = looked:GetParent()
		if IsValid(parent) and vehicles[parent] then return parent end
	end
end

-- "Check this car": every camera within 1.5x range says whether it can see
-- the car, and if not, why.
net.Receive("HeistFlock_ScanCheck", function(len, ply)
	if not HeistFlock.RequireAccess(ply, "view") or HeistFlock.IsThrottled(ply, "scancheck", 1) then return end

	local vehicle = vehicleFor(ply)
	if not vehicle then
		HeistFlock.Notify(ply, "Look at a car (or sit in one) first. Seats and chairs don't count.", true)
		return
	end

	local settings = Config.ALPR
	local maxRangeSqr = settings.Range ^ 2
	local minDot = math.cos(math.rad(HeistFlock.CoverageAngle()))
	local results = {}

	for _, cam in ipairs(ents.FindByClass("heistflock_camera")) do
		local lensPos, facing = lensOf(cam)
		local visible, why, distance, blocker = canSee(cam, lensPos, facing, vehicle, maxRangeSqr, minDot)

		if distance <= settings.Range * 1.5 then
			local following = cam:GetTrackTarget() == vehicle
			if not settings.Enabled then
				why = "off"
			elseif not HeistFlock.CameraCanScan(cam) then
				why = "blind"
			elseif visible and settings.TargetMode == "single" and not following then
				why = "not_target"
			end
			table.insert(results, { id = cam:EntIndex(), distance = math.Round(distance), why = why or "seen",
				blocker = blocker, following = following })
		end
	end
	table.SortByMember(results, "distance", true)

	local info = describeVehicle(vehicle)
	HeistFlock.Log(ply:Nick() .. " checked " .. info.name .. " (" .. info.plate .. "): " .. #results .. " camera(s) nearby")

	net.Start("HeistFlock_ScanCheckResult")
	net.WriteTable({ vehicle = info, cameras = results, range = settings.Range })
	net.Send(ply)
end)

-- "Send me a test alert": a fake plate hit to this admin only, to see what
-- police get. Changes nothing else.
net.Receive("HeistFlock_TestAlert", function(len, ply)
	if not HeistFlock.RequireAccess(ply, "view") or HeistFlock.IsThrottled(ply, "testalert", 3) then return end

	local vehicle = vehicleFor(ply)
	net.Start("HeistFlock_ALPRHit")
	net.WriteUInt(vehicle and vehicle:EntIndex() or 0, 16)
	net.WriteString(vehicle and (HeistFlock.GetPlate(vehicle) or "TEST-0000") or "TEST-0000")
	net.WriteString(vehicle and getVehicleName(vehicle) or "Test vehicle")
	net.WriteString("Test suspect")
	net.WriteString("wanted")
	net.WriteString("driver")
	net.WriteString("CAM-TEST")
	net.WriteVector(vehicle and vehicle:GetPos() or (ply:GetPos() + ply:GetForward() * 300))
	net.WriteFloat(15)
	net.Send(ply)

	HeistFlock.Log(ply:Nick() .. " sent themselves a test plate alert")
end)
