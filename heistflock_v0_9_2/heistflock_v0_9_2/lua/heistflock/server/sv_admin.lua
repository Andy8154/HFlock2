-- Admin tools used by the in-game menu: camera actions and server status.

util.AddNetworkString("HeistFlock_Action")
util.AddNetworkString("HeistFlock_RequestInfo")
util.AddNetworkString("HeistFlock_Info")
util.AddNetworkString("HeistFlock_PlaceAt")

local Config = HeistFlock.Config

-- Everything the Dashboard, Cameras and Diagnostics pages show, for ply.
local function buildInfo(ply)
	local cameras = {}

	for _, cam in ipairs(ents.FindByClass("heistflock_camera")) do
		local worker = cam:GetWorker()

		-- Stripped cameras repair at RepairAt; damaged ones nobody is working
		-- on reset at IdleResetAt. 0 = never (or not damaged).
		local resetAt = cam.RepairAt or (not IsValid(worker) and cam.IdleResetAt) or nil
		local repairIn = resetAt and math.ceil(resetAt - CurTime()) or 0

		table.insert(cameras, {
			id = cam:EntIndex(),
			pos = cam:GetPos(),
			ang = cam:GetAngles(),
			stage = cam:GetStage(),
			hits = cam:GetHits(),
			worker = IsValid(worker) and worker:Nick() or "",
			scanning = Config.ALPR.Enabled and HeistFlock.CameraCanScan(cam) or false,
			repairIn = math.max(repairIn, 0),
		})
	end

	local looseParts = 0
	for _, part in ipairs(HeistFlock.LooseParts or {}) do
		if IsValid(part) then looseParts = looseParts + 1 end
	end

	return {
		version = HeistFlock.Version,
		gamemode = engine.ActiveGamemode(),
		darkrp = DarkRP ~= nil,
		tickrate = math.Round(1 / engine.TickInterval()),
		map = game.GetMap(),
		entityRegistered = scripted_ents.Get("heistflock_camera") ~= nil,
		builtInModel = HeistFlock.UsesBuiltInModel(),
		modelValid = HeistFlock.UsesBuiltInModel() or util.IsValidModel(Config.Model),
		pliersRegistered = weapons.Get("heistflock_pliers") ~= nil,
		cameraFile = file.Exists(HeistFlock.CameraSavePath(), "DATA"),
		cameraSavePath = "garrysmod/data/" .. HeistFlock.CameraSavePath(),
		lastSave = HeistFlock.LastCameraSave, -- { time, count } or nil if not saved since startup
		changedSettings = HeistFlock.ChangedSettingsCount or 0, -- saved in settings.json
		plateSource = HeistFlock.PlateSource and HeistFlock.PlateSource() or "",
		alprReads = HeistFlock.ALPRReads or {},
		looseParts = looseParts,
		scanStats = HeistFlock.ScanStats,
		coverage = HeistFlock.CoverageAngle(),
		report = HeistFlock.BuildReport(ply), -- for Diagnostics' "Copy report"
		recentLog = HeistFlock.RecentLog,
		-- Steps mode with no payout and no crafting: players earn nothing.
		noIncome = Config.StripMode == "steps" and Config.Payout == 0 and not Config.Crafting.Enabled,
		partsProvider = HeistFlock.GetActiveProvider().id, -- the one actually in use
		permissions = HeistFlock.PermissionInfo(ply),
		warnings = HeistFlock.Warnings,
		stats = HeistFlock.Stats,
		activity = HeistFlock.Activity,
		serverTime = os.time(),
		players = player.GetCount(),
		cameras = cameras,
	}
end

-- Sent compressed: with a lot of cameras a plain table would go past the
-- 64 KB limit on a single network message.
local function sendInfo(ply)
	local data = util.Compress(util.TableToJSON(buildInfo(ply)))
	if not data or #data > 60000 then
		HeistFlock.Warn("Status info is too big to send.")
		return
	end

	net.Start("HeistFlock_Info")
	net.WriteUInt(#data, 32)
	net.WriteData(data, #data)
	net.Send(ply)
end

net.Receive("HeistFlock_RequestInfo", function(len, ply)
	if not HeistFlock.HasAccess(ply, "view") then return end

	-- At most one update a second per admin. A request that comes too soon
	-- gets one reply when the second is up, so the menu never waits forever.
	local wait = (ply.HeistFlockNextInfo or 0) - CurTime()
	if wait > 0 then
		timer.Create("HeistFlock_Info_" .. ply:EntIndex(), wait, 1, function()
			if IsValid(ply) then
				ply.HeistFlockNextInfo = CurTime() + 1
				sendInfo(ply)
			end
		end)
		return
	end

	ply.HeistFlockNextInfo = CurTime() + 1
	sendInfo(ply)
end)

-- Actions that don't need a camera selected.
local globalActions = {}

function globalActions.place(ply)
	if not HeistFlock.CanPlaceCamera() then
		return "There are already " .. HeistFlock.MaxCameras .. " cameras on this map."
	end

	local pos, ang = HeistFlock.GetSpawnSpot(ply, ply:GetEyeTrace())
	if not pos then return ang end -- ang holds the reason here

	local cam = HeistFlock.SpawnCamera(pos, ang)
	if not IsValid(cam) then return "Couldn't spawn the camera. Check the Debug page." end

	HeistFlock.QueueCameraSave(ply)
	HeistFlock.AdminLog(ply, "placed Flock camera #" .. cam:EntIndex())
	return "Camera placed."
end

function globalActions.save(ply)
	return "Saved " .. HeistFlock.SaveCameras() .. " camera(s) to garrysmod/data/" .. HeistFlock.CameraSavePath()
end

function globalActions.removeall(ply)
	HeistFlock.RemoveAllCameras()
	HeistFlock.QueueCameraSave(ply)
	HeistFlock.AdminLog(ply, "removed all Flock cameras")
	return "Removed all cameras."
end

function globalActions.resetall(ply)
	for _, cam in ipairs(ents.FindByClass("heistflock_camera")) do
		cam:ResetCamera()
	end
	HeistFlock.AdminLog(ply, "reset all Flock cameras")
	return "All cameras reset to untouched."
end

-- Actions on the camera selected in the menu.
local cameraActions = {}

-- Puts the admin next to the camera, trying each side until there's room.
function cameraActions.teleport(ply, cam)
	if ply:InVehicle() then ply:ExitVehicle() end

	local base = cam:GetPos()
	local mins, maxs = ply:OBBMins(), ply:OBBMaxs()
	local directions = { cam:GetForward(), -cam:GetRight(), cam:GetRight(), -cam:GetForward() }

	for _, direction in ipairs(directions) do
		local spot = base + direction * 60 + Vector(0, 0, 8)
		local blocked = util.TraceHull({ start = spot, endpos = spot, mins = mins, maxs = maxs, filter = { cam, ply } }).Hit

		if not blocked then
			local ground = util.TraceHull({ start = spot, endpos = spot - Vector(0, 0, 2000), mins = mins, maxs = maxs, filter = { cam, ply } })
			ply:SetPos(ground.HitPos)
			return "Teleported to camera #" .. cam:EntIndex() .. "."
		end
	end

	return "There's no room to stand next to camera #" .. cam:EntIndex() .. "."
end

function cameraActions.advance(ply, cam)
	if cam:GetStage() >= #Config.Stages then return "That camera is already stripped." end

	cam:StopWorking()
	cam:BreakNextPart()
	HeistFlock.AdminLog(ply, "skipped Flock camera #" .. cam:EntIndex() .. " to stage " .. cam:GetStage())
	return "Camera #" .. cam:EntIndex() .. " moved to stage " .. cam:GetStage() .. ". Nobody was paid and no parts dropped."
end

function cameraActions.reset(ply, cam)
	cam:ResetCamera()
	HeistFlock.AdminLog(ply, "reset Flock camera #" .. cam:EntIndex())
	return "Camera #" .. cam:EntIndex() .. " reset."
end

function cameraActions.remove(ply, cam)
	local id = cam:EntIndex()
	cam:Remove()
	HeistFlock.QueueCameraSave(ply)
	HeistFlock.AdminLog(ply, "removed Flock camera #" .. id)
	return "Camera #" .. id .. " removed."
end

-- Every action here changes cameras or moves the admin, so all of them
-- need the Place permission.
local MAX_ACTION_NAME = 32

net.Receive("HeistFlock_Action", function(len, ply)
	if not HeistFlock.RequireAccess(ply, "place") then return end
	if HeistFlock.IsThrottled(ply, "action", 0.25) then
		HeistFlock.Notify(ply, "Slow down, try again.", true)
		return
	end

	local actionName = net.ReadString()
	local cam = Entity(net.ReadUInt(16))
	local message

	if #actionName > MAX_ACTION_NAME or not (globalActions[actionName] or cameraActions[actionName]) then
		return -- not something the menu sends
	end

	if globalActions[actionName] then
		message = globalActions[actionName](ply)
	elseif cameraActions[actionName] then
		if IsValid(cam) and cam:GetClass() == "heistflock_camera" then
			message = cameraActions[actionName](ply, cam)
		else
			message = "That camera doesn't exist anymore."
		end
	end

	if message then
		HeistFlock.Notify(ply, message)
	end

	-- Removed entities disappear at the end of the tick, so wait one tick.
	timer.Simple(0, function()
		if IsValid(ply) then sendInfo(ply) end
	end)
end)

-- Placing or moving a camera from the preview (cl_placement.lua).
local PLACE_MAX_DISTANCE = 2500

local function isFinite(number)
	return isnumber(number) and number == number and math.abs(number) < 1e9
end

local function ignoreCameras(ent)
	return ent:GetClass() ~= "heistflock_camera"
end

-- Is there something solid within 20 units of pos, in any of the six
-- directions? 20 rather than 10 so slanted walls still count.
local SURFACE_DIRECTIONS = {
	Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0),
	Vector(0, -1, 0), Vector(0, 0, 1), Vector(0, 0, -1),
}

local function isNearSurface(pos)
	for _, direction in ipairs(SURFACE_DIRECTIONS) do
		local trace = util.TraceLine({ start = pos, endpos = pos + direction * 20, mask = MASK_SOLID, filter = ignoreCameras })
		if trace.Hit and not trace.StartSolid then return true end
	end
	return false
end

net.Receive("HeistFlock_PlaceAt", function(len, ply)
	if not HeistFlock.RequireAccess(ply, "place") then return end
	if HeistFlock.IsThrottled(ply, "action", 0.25) then
		HeistFlock.Notify(ply, "Slow down, try again.", true)
		return
	end

	local cameraId = net.ReadUInt(16)
	local pos = net.ReadVector()
	local yaw = net.ReadFloat()

	if not (isFinite(pos.x) and isFinite(pos.y) and isFinite(pos.z) and isFinite(yaw)) then return end
	if ply:GetPos():DistToSqr(pos) > PLACE_MAX_DISTANCE ^ 2 or not util.IsInWorld(pos + Vector(0, 0, 8)) then
		HeistFlock.Notify(ply, "Can't place a camera there.", true)
		return
	end

	if HeistFlock.UsesBuiltInModel() then
		-- The built-in pole has to stand on the ground. Cameras are ignored,
		-- so a camera can be turned in place without hitting its own pole.
		local ground = util.TraceLine({
			start = pos + Vector(0, 0, 8),
			endpos = pos - Vector(0, 0, 16),
			mask = MASK_SOLID,
			filter = ignoreCameras,
		})
		if not ground.Hit or ground.HitNormal.z < 0.7 then
			HeistFlock.Notify(ply, HeistFlock.L("look_at_ground"), true)
			return
		end
	elseif not isNearSurface(pos) then
		-- Custom models sit 10 units off whatever the admin aimed at, so
		-- there has to be a wall, ceiling or floor right next to the spot.
		HeistFlock.Notify(ply, "Can't place a camera there.", true)
		return
	end

	local ang = Angle(0, yaw, 0)

	if cameraId == 0 then
		if not HeistFlock.CanPlaceCamera() then
			HeistFlock.Notify(ply, "There are already " .. HeistFlock.MaxCameras .. " cameras on this map.", true)
			return
		end

		local cam = HeistFlock.SpawnCamera(pos, ang)
		if not IsValid(cam) then return end
		HeistFlock.AdminLog(ply, "placed Flock camera #" .. cam:EntIndex())
		HeistFlock.Notify(ply, "Camera placed.")
	else
		local cam = Entity(cameraId)
		if not IsValid(cam) or cam:GetClass() ~= "heistflock_camera" then
			HeistFlock.Notify(ply, "That camera doesn't exist anymore.", true)
			return
		end

		cam:StopWorking()
		cam:SetPos(pos)
		cam.UprightAngle = ang
		cam:UpdateLook()
		cam:Freeze()
		HeistFlock.AdminLog(ply, "moved Flock camera #" .. cam:EntIndex())
		HeistFlock.Notify(ply, "Camera moved.")
	end

	HeistFlock.QueueCameraSave(ply)
	timer.Simple(0, function()
		if IsValid(ply) then sendInfo(ply) end
	end)
end)

-- !heistflock or /heistflock in chat opens the menu.
hook.Add("PlayerSay", "HeistFlock_ChatCommand", function(ply, text)
	local command = string.lower(string.Trim(text))

	if command == "!heistflock" or command == "/heistflock" then
		ply:ConCommand("heistflock_menu")
		return ""
	end
end)
