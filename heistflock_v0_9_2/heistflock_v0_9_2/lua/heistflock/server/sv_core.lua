local Config = HeistFlock.Config
local L = HeistFlock.L

util.AddNetworkString("HeistFlock_Payout")

AddCSLuaFile("effects/heistflock_scrap/init.lua")

-- Fonts, UI icons and spawn menu icons. Players download these when they join.
resource.AddFile("resource/fonts/heistflock_sans.ttf")
resource.AddFile("resource/fonts/heistflock_sans_bold.ttf")
resource.AddFile("resource/fonts/heistflock_mono.ttf")
resource.AddFile("materials/entities/heistflock_camera.png")
resource.AddFile("materials/entities/heistflock_pliers.png")
for _, fileName in ipairs(file.Find("materials/heistflock/ui/*.png", "GAME")) do
	resource.AddFile("materials/heistflock/ui/" .. fileName)
end

-- Counted since the server started; shown on the menu's dashboard.
HeistFlock.Stats = HeistFlock.Stats or {
	camerasStripped = 0,
	moneyPaid = 0,
	checksPassed = 0,
	checksFailed = 0,
	hits = 0,
	alarms = 0,
	partsCollected = 0,
}

-- The last few things that happened, for the dashboard's activity feed.
-- kind: "strip", "fail", "admin", "wanted" or "alpr"
local ACTIVITY_SIZE = 30
HeistFlock.Activity = HeistFlock.Activity or {}

function HeistFlock.AddActivity(kind, text)
	table.insert(HeistFlock.Activity, 1, { kind = kind, text = text, time = os.time() })
	HeistFlock.Activity[ACTIVITY_SIZE + 1] = nil
end

function HeistFlock.Notify(ply, message, isError)
	-- Don't repeat the same message more than once every 2 seconds.
	if ply.HeistFlockLastMessage == message and CurTime() < ply.HeistFlockMessageTime then return end
	ply.HeistFlockLastMessage = message
	ply.HeistFlockMessageTime = CurTime() + 2

	if DarkRP then
		DarkRP.notify(ply, isError and 1 or 0, 4, message)
	else
		ply:ChatPrint(message) -- fallback so it can be tested in sandbox
	end
end

-- Returns true if the player did this too recently (and shouldn't again yet).
-- Used to stop network messages and admin actions being spammed.
function HeistFlock.IsThrottled(ply, key, delay)
	ply.HeistFlockThrottle = ply.HeistFlockThrottle or {}

	local now = CurTime()
	if (ply.HeistFlockThrottle[key] or 0) > now then return true end

	ply.HeistFlockThrottle[key] = now + delay
	return false
end

-- What just happened, in plain words. The last LOG_SIZE lines are always
-- kept (cheap), for Diagnostics' "Recent events" and the support report.
-- With Debug logging on, every line is also printed to the server console.
local LOG_SIZE = 60
HeistFlock.RecentLog = HeistFlock.RecentLog or {}

function HeistFlock.Log(message)
	table.insert(HeistFlock.RecentLog, { time = os.time(), text = message })
	if #HeistFlock.RecentLog > LOG_SIZE then table.remove(HeistFlock.RecentLog, 1) end

	if Config.Debug then
		print("[HeistFlock debug] " .. message)
	end
end

-- Returns true if the player may work on a camera,
-- or false and a message explaining why not.
function HeistFlock.CanStrip(ply)
	if not ply:Alive() then
		return false, L("you_are_dead")
	end

	if not DarkRP then
		return true
	end

	if ply:isArrested() then
		return false, L("you_are_arrested")
	end

	if Config.BlockPolice and ply:isCP() then
		return false, L("gov_blocked")
	end

	local job = ply:getJobTable()
	local inList = job ~= nil and HeistFlock.IsJobListed(job)

	if Config.JobMode == "whitelist" and not inList then
		return false, L("job_blocked")
	end
	if Config.JobMode == "blacklist" and inList then
		return false, L("job_blocked")
	end

	return true
end

-- Makes the player wanted, unless they already are. Returns true if it did.
function HeistFlock.MakeWanted(ply, reason)
	if not DarkRP or ply:getDarkRPVar("wanted") then return false end

	ply:wanted(nil, reason)
	HeistFlock.AddActivity("wanted", ply:Nick() .. " is now wanted")
	return true
end

-- A camera is finished: the final hit (smash mode) or the last stage (steps
-- mode). Pays the bonus, rolls for wanted and shows the payout card.
function HeistFlock.Payout(ply, cam)
	local smash = Config.StripMode == "smash"
	local flatPayout = (smash or HeistFlock.ShouldPayFlatPayout()) and Config.Payout or 0
	local drops = smash and {} or (cam.RunDrops or {}) -- smash mode parts are picked up separately

	-- The payout card shows what this player earned from this camera: the
	-- flat payout plus whatever their own run's parts sold for (the money
	-- provider already paid those stage by stage, and counted them in Stats).
	local lootValue = 0
	for _, drop in ipairs(drops) do
		lootValue = lootValue + (drop.value or 0)
	end
	local total = flatPayout + lootValue

	local becameWanted = false
	if Config.MakeWanted and math.random(1, 100) <= Config.WantedChance then
		becameWanted = HeistFlock.MakeWanted(ply, Config.WantedReason)
	end

	if flatPayout > 0 and ply.addMoney then
		ply:addMoney(flatPayout)
	end

	HeistFlock.Stats.camerasStripped = HeistFlock.Stats.camerasStripped + 1
	HeistFlock.Stats.moneyPaid = HeistFlock.Stats.moneyPaid + flatPayout -- loot was counted when it was sold
	HeistFlock.AddActivity("strip", ply:Nick() .. " stripped camera #" .. cam:EntIndex()
		.. (total > 0 and (" for " .. HeistFlock.FormatMoney(total)) or ""))
	HeistFlock.Log(ply:Nick() .. " was paid " .. total .. " for camera #" .. cam:EntIndex())

	hook.Run("HeistFlock_CameraStripped", ply, cam, total, drops)

	-- The line under the amount: the parts handed out when crafting is on.
	local detail = HeistFlock.L("payout_detail")
	if smash then
		detail = HeistFlock.L("payout_smash_detail")
	elseif Config.Crafting.Enabled and #drops > 0 then
		detail = HeistFlock.L("payout_parts", { list = HeistFlock.SummarizeDrops(drops) })
	end

	-- The client shows a payout card (see cl_hud.lua).
	net.Start("HeistFlock_Payout")
	net.WriteUInt(total, 32)
	net.WriteBool(ply.addMoney ~= nil and total > 0)
	net.WriteBool(becameWanted)
	net.WriteString(detail)
	net.Send(ply)
end

-- Cameras and dropped parts ------------------------------------------------
-- Only staff with the Place permission can physgun, toolgun or right-click
-- them. Parts can be carried with the gravity gun (to steal them), but not
-- punted, pocketed or copied.

local function isCamera(ent)
	return IsValid(ent) and ent:GetClass() == "heistflock_camera"
end

local function isOurs(ent)
	if not IsValid(ent) then return false end
	local class = ent:GetClass()
	return class == "heistflock_camera" or class == "heistflock_part"
end

hook.Add("PhysgunPickup", "HeistFlock_BlockPhysgun", function(ply, ent)
	if isOurs(ent) and not HeistFlock.HasAccess(ply, "place") then
		return false
	end
end)

hook.Add("CanTool", "HeistFlock_BlockTool", function(ply, trace, toolName)
	local ent = trace.Entity
	if not isOurs(ent) then return end

	if not HeistFlock.HasAccess(ply, "place") then
		return false
	end
	if not isCamera(ent) then return end

	-- An admin removing a camera with the remover tool. Another addon (prop
	-- protection, say) can still block it after this hook, so only save and
	-- log once the camera is actually gone.
	if toolName == "remover" then
		local cameraId = ent:EntIndex()
		timer.Simple(0.5, function()
			if IsValid(ent) then return end
			HeistFlock.QueueCameraSave(ply)
			HeistFlock.AdminLog(ply, "removed Flock camera #" .. cameraId .. " (toolgun)")
		end)
	end
end)

-- After an admin moves a camera, freeze it and remember its new position.
hook.Add("PhysgunDrop", "HeistFlock_Refreeze", function(ply, ent)
	if not IsValid(ent) or ent:GetClass() ~= "heistflock_camera" then return end

	ent:Freeze()

	-- Remember its new upright angle (the one that gets saved).
	local ang = ent:GetAngles()
	if HeistFlock.UsesBuiltInModel() then
		-- The pole always stands straight; only which way it faces is kept.
		ent.UprightAngle = Angle(0, ang.y, 0)
	else
		-- A damaged custom model is drooping by its stage's tilt (see
		-- ENT:UpdateLook, which tilts by -tilt); undo that first.
		local look = Config.Looks[ent:GetStage()] or {}
		ang:RotateAroundAxis(ang:Right(), look.tilt or 0)
		ent.UprightAngle = ang
	end
	ent:UpdateLook()

	HeistFlock.QueueCameraSave(ply)
	HeistFlock.AdminLog(ply, "moved Flock camera #" .. ent:EntIndex() .. " (physgun)")
end)

-- The gravity gun can't pick up cameras, or punt cameras or parts.
hook.Add("GravGunPickupAllowed", "HeistFlock_BlockGravGun", function(ply, ent)
	if isCamera(ent) then return false end
end)

hook.Add("GravGunPunt", "HeistFlock_BlockGravGun", function(ply, ent)
	if isOurs(ent) then return false end
end)

-- DarkRP's pocket would let players store and respawn them.
hook.Add("canPocket", "HeistFlock_BlockPocket", function(ply, ent)
	if isOurs(ent) then return false, "You can't pocket that." end
end)

-- Right-click options (C menu). Only staff with the Place permission may
-- use them, and nobody may "make persistent": sandbox would then spawn the
-- camera on every map load on top of the one from the save file.
hook.Add("CanProperty", "HeistFlock_BlockProperties", function(ply, property, ent)
	if not isOurs(ent) then return end
	if property == "persist" or property == "drive" then return false end
	if not HeistFlock.HasAccess(ply, "place") then return false end
	if not isCamera(ent) then return end

	-- Removing through the C menu: update the save file once it's gone.
	if property == "remover" then
		local cameraId = ent:EntIndex()
		timer.Simple(0.5, function()
			if IsValid(ent) then return end
			HeistFlock.QueueCameraSave(ply)
			HeistFlock.AdminLog(ply, "removed Flock camera #" .. cameraId .. " (C menu)")
		end)
	end
end)

hook.Add("CanDrive", "HeistFlock_BlockDrive", function(ply, ent)
	if isOurs(ent) then return false end
end)
