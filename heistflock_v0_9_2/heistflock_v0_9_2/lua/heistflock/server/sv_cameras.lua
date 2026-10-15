-- Spawning, saving and loading cameras.
-- Saved per map in garrysmod/data/heistflock/<mapname>.json
-- Cameras save whenever an admin places, moves or removes one: from the menu,
-- the console commands, the physgun or the toolgun remover. Nothing else
-- (cleanups, other addons) changes the save file.

-- Most cameras one map can have. Every entity counts toward the engine's
-- limit, so a broken save file or a stuck key can't spawn thousands.
HeistFlock.MaxCameras = 250

function HeistFlock.CanPlaceCamera()
	return #ents.FindByClass("heistflock_camera") < HeistFlock.MaxCameras
end

function HeistFlock.CameraSavePath()
	return "heistflock/" .. game.GetMap() .. ".json"
end

-- Where a camera goes when an admin places one at what they're looking at.
-- Returns pos and ang, or nil and a reason the player can read.
function HeistFlock.GetSpawnSpot(ply, trace)
	if not trace.Hit then
		return nil, HeistFlock.L("look_at_surface")
	end

	local facePlayer = Angle(0, ply:EyeAngles().y + 180, 0)

	-- The built-in camera stands on its own pole, so it needs the ground.
	if HeistFlock.UsesBuiltInModel() then
		if trace.HitNormal.z < 0.7 then
			return nil, HeistFlock.L("look_at_ground")
		end
		return trace.HitPos, facePlayer
	end

	return trace.HitPos + trace.HitNormal * 10, facePlayer
end

function HeistFlock.SpawnCamera(pos, ang)
	local cam = ents.Create("heistflock_camera")
	if not IsValid(cam) then return end -- entity isn't registered

	cam:SetPos(pos)
	cam:SetAngles(ang)
	cam:Spawn()

	return cam
end

function HeistFlock.SaveCameras()
	local cameras = {}

	for _, cam in ipairs(ents.FindByClass("heistflock_camera")) do
		local pos = cam:GetPos()
		local ang = cam.UprightAngle

		table.insert(cameras, {
			x = pos.x, y = pos.y, z = pos.z,
			pitch = ang.p, yaw = ang.y, roll = ang.r,
		})
	end

	file.CreateDir("heistflock")
	file.Write(HeistFlock.CameraSavePath(), util.TableToJSON(cameras, true))

	HeistFlock.LastCameraSave = { time = os.time(), count = #cameras }
	HeistFlock.Log("Saved " .. #cameras .. " camera(s) to garrysmod/data/" .. HeistFlock.CameraSavePath())

	return #cameras
end

-- Saves one second after the last change, so many changes = one file write.
-- Paused during map cleanup and shutdown, when every camera gets removed.
local autoSavePaused = false

-- ply (optional) is the admin who made the change; they get told it saved.
function HeistFlock.QueueCameraSave(ply)
	if autoSavePaused then return end

	timer.Create("HeistFlock_AutoSave", 1, 1, function()
		local count = HeistFlock.SaveCameras()
		if IsValid(ply) then
			HeistFlock.Notify(ply, "Saved " .. count .. " camera(s) to garrysmod/data/" .. HeistFlock.CameraSavePath())
		end
	end)
end

function HeistFlock.RemoveAllCameras()
	for _, cam in ipairs(ents.FindByClass("heistflock_camera")) do
		cam:Remove()
	end
end

local SAVED_FIELDS = { "x", "y", "z", "pitch", "yaw", "roll" }

-- Is this one saved camera usable? Every field must be a real number.
local function isValidSavedCamera(saved)
	if not istable(saved) then return false end

	for _, field in ipairs(SAVED_FIELDS) do
		local value = saved[field]
		if not isnumber(value) or value ~= value then return false end -- value ~= value catches NaN
	end

	return true
end

local function loadCameras()
	local path = HeistFlock.CameraSavePath()
	local json = file.Read(path, "DATA")
	if not json then return end

	local saved = util.JSONToTable(json)
	if not istable(saved) then
		HeistFlock.Warn("The camera save file " .. path .. " is damaged and was ignored.")
		return
	end

	local skipped = 0
	for _, entry in ipairs(saved) do
		local pos = isValidSavedCamera(entry) and Vector(entry.x, entry.y, entry.z)

		-- Checked a little above the saved spot: built-in poles are saved
		-- exactly on the floor, which can count as outside the world.
		if pos and util.IsInWorld(pos + Vector(0, 0, 8)) and HeistFlock.CanPlaceCamera() then
			HeistFlock.SpawnCamera(pos, Angle(entry.pitch, entry.yaw, entry.roll))
		else
			skipped = skipped + 1
		end
	end

	if skipped > 0 then
		HeistFlock.Warn("Skipped " .. skipped .. " camera(s) in " .. path .. " (broken, outside the map, or over the "
			.. HeistFlock.MaxCameras .. " camera limit).")
	end
end

hook.Add("InitPostEntity", "HeistFlock_LoadCameras", loadCameras)

hook.Add("PreCleanupMap", "HeistFlock_PauseAutoSave", function()
	autoSavePaused = true
end)

hook.Add("PostCleanupMap", "HeistFlock_LoadCameras", function()
	loadCameras()
	autoSavePaused = false
end)

hook.Add("ShutDown", "HeistFlock_PauseAutoSave", function()
	autoSavePaused = true
end)

-- Console commands. The Place permission (or the server console itself).
local function isAllowed(ply)
	if not IsValid(ply) then return true end
	return HeistFlock.RequireAccess(ply, "place") and not HeistFlock.IsThrottled(ply, "action", 1)
end

local function reply(ply, message)
	if IsValid(ply) then
		HeistFlock.Notify(ply, message)
	else
		print("[HeistFlock] " .. message)
	end
end

concommand.Add("heistflock_save", function(ply)
	if not isAllowed(ply) then return end
	reply(ply, "Saved " .. HeistFlock.SaveCameras() .. " camera(s) to garrysmod/data/" .. HeistFlock.CameraSavePath())
end)

concommand.Add("heistflock_removeall", function(ply)
	if not isAllowed(ply) then return end
	HeistFlock.RemoveAllCameras()
	HeistFlock.QueueCameraSave(ply)
	HeistFlock.AdminLog(ply, "removed all Flock cameras (console)")
	reply(ply, "Removed all cameras.")
end)
