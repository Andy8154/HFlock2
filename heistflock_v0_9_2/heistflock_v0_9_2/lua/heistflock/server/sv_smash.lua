--[[-------------------------------------------------------------------------
	HEIST FLOCK - SMASHING (smash mode)

	Players break a camera by hitting it. Each stage takes a set number of
	hits (Config.Stages[i].hits), counted per hit, not per point of damage,
	so a strong weapon can't do it in one. When a stage's hits are done, a
	part comes off, its loot drops as items (sv_loot.lua), and the next
	stage starts. Anyone can join in; whoever lands the final hit gets the
	bonus (Config.Payout).

	What counts as a hit:
	  * a melee hit (club or slash damage) from a weapon in Config.Smash.Tools
	  * bullets, only with Config.Smash.AllowBullets
	  * explosions: with Config.Smash.ExplosionsDestroy, one blast finishes
	    the camera, dropping every remaining stage's parts. Without it, they
	    count as a normal hit if AllowBullets is on.
	  * from a player who passes HeistFlock.CanStrip (job, police, arrested,
	    dead) and isn't in a vehicle
	  * at most one every Config.Smash.HitDelay seconds per player
---------------------------------------------------------------------------]]

util.AddNetworkString("HeistFlock_TamperAlert")

local Config = HeistFlock.Config
local L = HeistFlock.L

local MELEE_DAMAGE = bit.bor(DMG_CLUB, DMG_SLASH)
local ALARM_TIME = 8          -- seconds the camera's LED flashes after the alarm
local TAMPER_MARKER_TIME = 60 -- seconds police see the marker

-- Tells a player why a hit didn't count, at most every 8 seconds per reason
-- (and notes it in the recent events, for admins).
local function explain(ply, reason, message)
	if HeistFlock.IsThrottled(ply, "smash_" .. reason, 8) then return end
	HeistFlock.Notify(ply, message, true)
	HeistFlock.Log(ply:Nick() .. "'s hit didn't count: " .. message)
end

-- The weapon behind a hit: the inflictor when it's a weapon (the pliers),
-- otherwise what the attacker is holding (engine weapons like the crowbar
-- report the player as the inflictor).
local function weaponOf(dmg, attacker)
	local inflictor = dmg:GetInflictor()
	if IsValid(inflictor) and inflictor:IsWeapon() then return inflictor end

	local active = attacker:GetActiveWeapon()
	if IsValid(active) then return active end
end

-- The player behind this damage if it counts as a hit, otherwise nil. The
-- second value is true when it's an explosion that finishes the camera.
function HeistFlock.GetSmashHitter(cam, dmg)
	local ply = dmg:GetAttacker()
	if not IsValid(ply) or not ply:IsPlayer() then return end -- props, fire, the world

	local explosion = dmg:IsExplosionDamage()
	local destroys = explosion and Config.Smash.ExplosionsDestroy
	local ranged = dmg:IsBulletDamage() or explosion
	local melee = bit.band(dmg:GetDamageType(), MELEE_DAMAGE) ~= 0

	if destroys then
		-- Allowed; the player checks below still apply.
	elseif ranged then
		if not Config.Smash.AllowBullets then
			explain(ply, "tool", L("smash_need_tool"))
			return
		end
	elseif melee then
		local weapon = weaponOf(dmg, ply)
		if not IsValid(weapon) or not table.HasValue(Config.Smash.Tools, weapon:GetClass()) then
			explain(ply, "tool", L("smash_need_tool"))
			return
		end
	else
		return -- thrown props, falling, burning: never a hit
	end

	if cam:GetStage() >= #Config.Stages then
		explain(ply, "done", L("already_stripped"))
		return
	end

	if ply:InVehicle() then return end

	local allowed, reason = HeistFlock.CanStrip(ply)
	if not allowed then
		explain(ply, "blocked", reason)
		return
	end

	-- Explosions only count from close enough (0 = any distance), so a
	-- grenade lobbed from across the map doesn't.
	local maxDistance = Config.Smash.ExplosionMaxDistance
	if explosion and maxDistance > 0 and ply:GetPos():DistToSqr(cam:GetPos()) > maxDistance ^ 2 then
		explain(ply, "far", L("smash_too_far"))
		return
	end

	if hook.Run("HeistFlock_CanSmash", ply, cam) == false then return end

	-- One hit per swing, however fast the clicks (or shotgun pellets) come.
	-- A blast is limited per camera instead, so one grenade can take out
	-- several cameras at once (its damage reaches each one separately).
	local throttleKey = explosion and ("blast_" .. cam:EntIndex()) or "smash"
	if HeistFlock.IsThrottled(ply, throttleKey, Config.Smash.HitDelay) then return end

	return ply, destroys
end

-- Alarm ---------------------------------------------------------------------

function HeistFlock.GetPolice()
	local police = {}
	for _, ply in ipairs(player.GetHumans()) do
		if DarkRP and ply:isCP() then table.insert(police, ply) end
	end
	return police
end

local function sendTamperAlert(cam)
	local police = HeistFlock.GetPolice()
	if #police == 0 then return end

	net.Start("HeistFlock_TamperAlert")
	net.WriteUInt(cam:EntIndex(), 16)
	net.WriteString(string.format("CAM-%03d", cam:EntIndex()))
	net.WriteVector(HeistFlock.GetHousingPos(cam))
	net.WriteFloat(TAMPER_MARKER_TIME)
	net.Send(police)
end

-- The camera's alarm goes off because of this player's hit.
function HeistFlock.TripAlarm(cam, ply)
	cam.AlarmTripped = true
	cam:SetAlarmUntil(CurTime() + ALARM_TIME)

	cam:EmitSound("ambient/alarms/warningbell1.wav", 85)
	timer.Simple(1.4, function()
		if IsValid(cam) then cam:EmitSound("ambient/alarms/warningbell1.wav", 85) end
	end)

	HeistFlock.Stats.alarms = (HeistFlock.Stats.alarms or 0) + 1
	HeistFlock.AddActivity("fail", ply:Nick() .. " tripped the alarm on camera #" .. cam:EntIndex())
	HeistFlock.Log(ply:Nick() .. " tripped the alarm on camera #" .. cam:EntIndex())

	local becameWanted = Config.Smash.AlarmMakesWanted and HeistFlock.MakeWanted(ply, Config.Smash.AlarmWantedReason)
	HeistFlock.Notify(ply, becameWanted and L("alarm_tripped_wanted") or L("alarm_tripped"), true)

	if Config.Smash.PoliceAlert then
		sendTamperAlert(cam)
	end

	hook.Run("HeistFlock_AlarmTripped", ply, cam)
end

-- Rolled on every hit until the alarm has gone off once; it stays quiet
-- after that until the camera is repaired. With AlarmPerCamera, it's only
-- rolled once, on the camera's first hit.
local function rollAlarm(cam, ply, isFirstHit)
	if cam.AlarmTripped then return end
	if Config.Smash.AlarmPerCamera and not isFirstHit then return end

	local trips = (Config.Smash.AlarmOnFirstHit and isFirstHit)
		or math.random(1, 100) <= Config.Smash.AlarmChance

	if trips then HeistFlock.TripAlarm(cam, ply) end
end

-- Hits ----------------------------------------------------------------------

local function hitEffects(cam, hitPos)
	local head = HeistFlock.GetHousingPos(cam)
	if not hitPos or hitPos:IsZero() or hitPos:DistToSqr(head) > 64 ^ 2 then
		hitPos = head
	end

	local sparks = EffectData()
	sparks:SetOrigin(hitPos)
	sparks:SetMagnitude(1)
	sparks:SetScale(0.6)
	sparks:SetRadius(1)
	util.Effect("Sparks", sparks)

	-- The game's own solid-metal impact sound (it picks a variation itself).
	cam:EmitSound("SolidMetal.ImpactHard", 75, math.random(95, 110))
	cam:SetLastHit(CurTime()) -- each player's game shakes the camera head
end

-- A hit that counts. Called by the camera's OnTakeDamage.
function HeistFlock.SmashHit(cam, ply, hitPos)
	local stageNumber = cam:GetStage() + 1
	local stage = Config.Stages[stageNumber]
	if not stage then return end

	local isFirstHit = cam:GetStage() == 0 and cam:GetHits() == 0
	local hits = cam:GetHits() + 1
	cam:SetHits(hits)
	HeistFlock.Stats.hits = (HeistFlock.Stats.hits or 0) + 1

	-- A damaged camera puts itself back together after the repair time,
	-- counted from the last hit.
	if Config.RepairTime > 0 then
		cam.IdleResetAt = CurTime() + Config.RepairTime
	end

	hitEffects(cam, hitPos)
	HeistFlock.Log(ply:Nick() .. " hit camera #" .. cam:EntIndex() .. " (stage " .. stageNumber .. ": " .. hits .. "/" .. stage.hits .. ")")
	rollAlarm(cam, ply, isFirstHit)

	if hits < stage.hits then return end

	-- The stage is done: a part comes off and its loot drops.
	local fullyStripped = cam:BreakNextPart()
	local drops = HeistFlock.DropStageParts(cam, stageNumber, ply)
	HeistFlock.Log(ply:Nick() .. " broke stage " .. stageNumber .. " of camera #" .. cam:EntIndex()
		.. (#drops > 0 and (", dropping " .. HeistFlock.SummarizeDrops(drops)) or ", no parts dropped"))

	if fullyStripped then
		HeistFlock.Payout(ply, cam)
	end
end

-- An explosion: every remaining stage breaks at once, each dropping its
-- parts, and the camera is finished. Counts as one hit for the alarm.
function HeistFlock.SmashDestroy(cam, ply, hitPos)
	local stageCount = #Config.Stages
	if cam:GetStage() >= stageCount then return end

	local isFirstHit = cam:GetStage() == 0 and cam:GetHits() == 0
	HeistFlock.Stats.hits = (HeistFlock.Stats.hits or 0) + 1
	hitEffects(cam, hitPos)
	rollAlarm(cam, ply, isFirstHit)

	local allDrops = {}
	while cam:GetStage() < stageCount do -- at most one pass per stage
		local stageNumber = cam:GetStage() + 1
		cam:BreakNextPart()
		table.Add(allDrops, HeistFlock.DropStageParts(cam, stageNumber, ply))
	end

	HeistFlock.Log(ply:Nick() .. " blew up camera #" .. cam:EntIndex()
		.. (#allDrops > 0 and (", dropping " .. HeistFlock.SummarizeDrops(allDrops)) or ""))
	HeistFlock.Payout(ply, cam)
end
