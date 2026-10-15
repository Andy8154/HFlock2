AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- Config is read inside each function (not once at the top of the file),
-- so this entity still registers even if it loads before the addon's
-- autorun file.

-- With Config.RequireHold on: seconds to grab the camera again after a skill
-- check. The window closes the moment the result arrives.
local GRACE_AFTER_CHECK = 2

-- Called when an admin spawns it from the Q menu.
-- Returns nothing on purpose: a returned entity goes on sandbox's undo and
-- cleanup lists and gets a prop-protection owner, and cleanup tools would
-- then delete saved cameras. Admins remove cameras from !heistflock instead.
function ENT:SpawnFunction(ply, trace)
	-- The spawn menu lets any admin through (AdminOnly), but placing a camera
	-- saves it for good, so it needs the Place permission.
	if not HeistFlock.HasAccess(ply, "place") then
		HeistFlock.Notify(ply, "You don't have permission to place Flock cameras.", true)
		return
	end

	if not HeistFlock.CanPlaceCamera() then
		HeistFlock.Notify(ply, "There are already " .. HeistFlock.MaxCameras .. " cameras on this map.", true)
		return
	end

	local pos, ang = HeistFlock.GetSpawnSpot(ply, trace)
	if not pos then
		HeistFlock.Notify(ply, ang, true) -- ang holds the reason here
		return
	end

	local cam = HeistFlock.SpawnCamera(pos, ang)
	HeistFlock.QueueCameraSave(ply)
	HeistFlock.Notify(ply, HeistFlock.L("camera_placed"))
	if IsValid(cam) then
		HeistFlock.AdminLog(ply, "placed Flock camera #" .. cam:EntIndex() .. " (spawn menu)")
	end
end

function ENT:Initialize()
	self:SetModel(HeistFlock.UsesBuiltInModel() and HeistFlock.BuiltInBaseModel or HeistFlock.Config.Model)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetupCollisions()
	self:SetUseType(SIMPLE_USE)

	self.UprightAngle = self:GetAngles()
	self:SetStage(0)
	self:UpdateLook()
end

function ENT:Freeze()
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:EnableMotion(false)
	end
end

-- Server-side look. The built-in camera's damage is drawn by each client
-- from the stage number; a custom model is tinted, tilted or swapped here.
function ENT:UpdateLook()
	local Config = HeistFlock.Config
	local builtIn = HeistFlock.UsesBuiltInModel()
	local look = builtIn and {} or (Config.Looks[self:GetStage()] or {})
	local model = builtIn and HeistFlock.BuiltInBaseModel or (look.model or Config.Model)

	if self:GetModel() ~= model then
		self:SetModel(model)
		self:SetupCollisions() -- resize the collision box for the new model
	end

	self:DrawShadow(not builtIn)
	self:SetColor(look.color or color_white)

	local angle = Angle(self.UprightAngle)
	angle:RotateAroundAxis(angle:Right(), -(look.tilt or 0))
	self:SetAngles(angle)
end

local L = function(...) return HeistFlock.L(...) end

-- Smash mode: hits are counted here (see sv_smash.lua).
function ENT:OnTakeDamage(dmg)
	if HeistFlock.Config.StripMode ~= "smash" then return end

	local ply, destroys = HeistFlock.GetSmashHitter(self, dmg)
	if not ply then return end

	if destroys then
		HeistFlock.SmashDestroy(self, ply, dmg:GetDamagePosition())
	else
		HeistFlock.SmashHit(self, ply, dmg:GetDamagePosition())
	end
end

-- Steps mode: starts work if the player is allowed to. Called when they
-- press E on the camera, or left click it with pliers. Returns true if
-- they're working.
-- freshPress: false when the pliers fire again because the button is still
-- held; that may never switch the player away from another camera.
function ENT:TryStart(ply, freshPress)
	local Config = HeistFlock.Config
	if Config.StripMode ~= "steps" then return false end
	if freshPress == nil then freshPress = true end

	if ply:InVehicle() or not HeistFlock.IsInRange(ply, self) then return false end

	if self:GetStage() >= #Config.Stages then
		HeistFlock.Notify(ply, L("already_stripped"), true)
		return false
	end

	local worker = self:GetWorker()
	if IsValid(worker) then
		if worker ~= ply then
			HeistFlock.Notify(ply, L("someone_else"), true)
		end
		return worker == ply
	end

	-- Holding the button and glancing at another camera mustn't switch to it.
	local otherCam = ply:GetNW2Entity("HeistFlock_Camera")
	local busyElsewhere = IsValid(otherCam) and otherCam ~= self and otherCam:GetWorker() == ply
	if busyElsewhere and not freshPress then return false end

	if Config.RequirePliers and not HeistFlock.IsUsingPliers(ply) then
		HeistFlock.Notify(ply, L("need_pliers"), true)
		return false
	end

	local allowed, reason = HeistFlock.CanStrip(ply)
	if not allowed then
		HeistFlock.Notify(ply, reason, true)
		return false
	end

	-- One camera at a time: starting this one cancels the stage in progress on
	-- the other (finished stages stay finished). Done last, so a refused start
	-- never cancels anything.
	if busyElsewhere then
		otherCam:StopWorking()
		HeistFlock.Notify(ply, L("switched_camera"))
	end

	self.LastCheckType = nil
	self.RunDrops = {} -- materials handed out during this run, for the payout card
	self:StartStage(ply)
	return true
end

function ENT:Use(ply)
	if not ply:IsPlayer() then return end

	if HeistFlock.Config.StripMode == "smash" then
		if not HeistFlock.IsThrottled(ply, "smash_how", 3) then
			HeistFlock.Notify(ply, L("smash_how"))
		end
		return
	end

	self:TryStart(ply)
end

-- When in the stage (0-1) each of its skill checks pops up, e.g. { 0.33, 0.67 }.
local function planCheckPoints(count)
	local points = {}
	for i = 1, count do
		local evenSpot = i / (count + 1)
		local wiggle = math.Rand(-0.08, 0.08) / count
		table.insert(points, math.Clamp(evenSpot + wiggle, 0.15, 0.9))
	end
	table.sort(points)
	return points
end

function ENT:StartStage(ply)
	local Config = HeistFlock.Config
	local stageNumber = self:GetStage() + 1
	local stage = Config.Stages[stageNumber]

	self:SetWorker(ply)
	self:SetStageStart(CurTime())
	self:SetStageLength(stage.time)
	self.IdleResetAt = nil
	self:SetCheckActive(false)
	ply:SetNW2Entity("HeistFlock_Camera", self) -- lets the pliers and HUD find it
	self:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav")

	local checkCount = HeistFlock.DistributeChecks()[stageNumber] or 0
	self.CheckPoints = planCheckPoints(checkCount)

	HeistFlock.Log(ply:Nick() .. " started stage " .. stageNumber .. " on camera #" .. self:EntIndex()
		.. " (" .. checkCount .. " skill checks)")
end

function ENT:StopWorking()
	local worker = self:GetWorker()

	if IsValid(worker) then
		if self:GetCheckActive() then
			HeistFlock.CloseSkillCheck(worker)
		end
		if worker:GetNW2Entity("HeistFlock_Camera") == self then
			worker:SetNW2Entity("HeistFlock_Camera", NULL)
		end
	end

	self:SetWorker(NULL)
	self:SetStageLength(0)
	self:SetCheckActive(false)
	self.ActiveCheck = nil
	self.CheckPoints = nil

	-- Left partly stripped: put it back together after the repair time too,
	-- or it would stay damaged forever.
	local Config = HeistFlock.Config
	local partlyStripped = self:GetStage() > 0 and self:GetStage() < #Config.Stages
	if partlyStripped and Config.RepairTime > 0 then
		self.IdleResetAt = CurTime() + Config.RepairTime
	end
end

-- Back to untouched, e.g. after the repair time or from the admin menu.
function ENT:ResetCamera()
	self:StopWorking()
	self.RepairAt = nil
	self.IdleResetAt = nil
	self.AlarmTripped = nil
	self:SetStage(0)
	self:SetHits(0)
	self:SetAlarmUntil(0)
	self:UpdateLook()
end

-- The save file is not touched here: cameras get removed by map cleanups,
-- shutdowns and cleanup addons too. Removals by admins save explicitly
-- (menu, console command, toolgun remover).
function ENT:OnRemove()
	self:StopWorking()
	if HeistFlock.ForgetCamera then HeistFlock.ForgetCamera(self) end
end

-- Is the worker still next to the camera and allowed to work on it?
function ENT:IsWorkerStillHere(ply)
	if not IsValid(ply) then return false end
	if ply:InVehicle() then return false end -- no stripping from a car seat
	if not HeistFlock.IsInRange(ply, self) then return false end

	return HeistFlock.CanStrip(ply)
end

-- Can work carry on this tick?
--   Default: stay close, and keep the pliers out if they're required.
--   With Config.RequireHold: also keep holding the button and looking at it.
function ENT:IsStillWorking(ply)
	local Config = HeistFlock.Config

	if not self:IsWorkerStillHere(ply) then return false end
	if Config.RequirePliers and not HeistFlock.IsUsingPliers(ply) then return false end
	if not Config.RequireHold then return true end

	if CurTime() < (self.GraceUntil or 0) then return true end -- just closed a skill check
	if not HeistFlock.IsHoldingWorkKey(ply) then return false end

	return ply:GetEyeTrace().Entity == self
end

function ENT:Think()
	local ply = self:GetWorker()

	if self:GetStageLength() > 0 then
		if self:GetCheckActive() then
			self:ThinkSkillCheck(ply)
		else
			self:ThinkWork(ply)
		end
	end

	local repairDue = self.RepairAt and CurTime() >= self.RepairAt
	local idleResetDue = self.IdleResetAt and CurTime() >= self.IdleResetAt and not IsValid(self:GetWorker())
	if repairDue or idleResetDue then
		self:ResetCamera()
	end

	-- Check often while someone is working, rarely when idle.
	local delay = self:GetStageLength() > 0 and 0.1 or 1
	self:NextThink(CurTime() + delay)
	return true
end

function ENT:ThinkWork(ply)
	local stageDone = CurTime() >= self:GetStageStart() + self:GetStageLength()
	local nextCheck = self.CheckPoints and self.CheckPoints[1]

	local function stop()
		if IsValid(ply) then
			HeistFlock.Notify(ply, L("stopped_working"), true)
			HeistFlock.Log(ply:Nick() .. " stopped working on camera #" .. self:EntIndex())
		end
		self:StopWorking()
	end

	if not self:IsWorkerStillHere(ply) then
		stop()
	elseif nextCheck and self:GetStageProgress() >= nextCheck then
		table.remove(self.CheckPoints, 1)
		self:StartSkillCheck(ply)
	elseif stageDone then
		-- The timer ran out, so they worked long enough, even if they let go
		-- of the button on this exact tick.
		self:FinishStage(ply)
	elseif not self:IsStillWorking(ply) then
		stop()
	end
end

function ENT:ThinkSkillCheck(ply)
	if not self:IsWorkerStillHere(ply) then
		self:StopWorking()
	elseif not self.ActiveCheck then
		self:FailSkillCheck(ply, "result_error") -- never treat a missing check as passed
	elseif CurTime() > self.ActiveCheck.deadline then
		self:FailSkillCheck(ply, "result_too_slow")
	end
end

-- Skill checks -----------------------------------------------------------

function ENT:StartSkillCheck(ply)
	local stage = HeistFlock.Config.Stages[self:GetStage() + 1]
	local checkType = HeistFlock.PickCheckType(self.LastCheckType, stage and stage.checks)
	if not checkType then return end -- this stage's steps were turned off meanwhile
	self.LastCheckType = checkType

	self.ActiveCheck = HeistFlock.CreateSkillCheck(checkType)
	self:SetPauseFraction(self:GetStageProgress())
	self:SetCheckActive(true) -- pauses the stage timer

	HeistFlock.SendSkillCheck(ply, self, self.ActiveCheck)
	HeistFlock.Log(ply:Nick() .. " got a " .. checkType .. " skill check on camera #" .. self:EntIndex())
end

-- Carry on from where the stage was paused.
function ENT:ResumeStage()
	self:SetStageStart(CurTime() - self:GetPauseFraction() * self:GetStageLength())
	self:SetCheckActive(false)
	self.ActiveCheck = nil
	self.GraceUntil = CurTime() + GRACE_AFTER_CHECK
end

function ENT:PassSkillCheck(ply)
	HeistFlock.Stats.checksPassed = HeistFlock.Stats.checksPassed + 1
	HeistFlock.SendSkillResult(ply, true, L("result_pass"))
	self:ResumeStage()
	HeistFlock.Log(ply:Nick() .. " passed a skill check")
end

-- reasonKey is a language key, e.g. "result_too_slow".
function ENT:FailSkillCheck(ply, reasonKey)
	local Config = HeistFlock.Config

	HeistFlock.Stats.checksFailed = HeistFlock.Stats.checksFailed + 1
	HeistFlock.SendSkillResult(ply, false, L("result_alarm", { reason = L(reasonKey) }))
	HeistFlock.AddActivity("fail", ply:Nick() .. " failed a skill check on camera #" .. self:EntIndex())
	self:EmitSound("ambient/alarms/warningbell1.wav", 80)
	HeistFlock.Log(ply:Nick() .. " failed a skill check (" .. reasonKey .. ")")

	if Config.FailMakesWanted then
		HeistFlock.MakeWanted(ply, Config.FailWantedReason)
	end

	self:ResumeStage()

	if Config.FailRestartsStage then
		self:StartStage(ply)
		self.GraceUntil = CurTime() + GRACE_AFTER_CHECK
	end
end

-- Finishing stages -------------------------------------------------------

-- Moves the camera to its next state. Returns true if it's now fully stripped.
function ENT:BreakNextPart()
	local Config = HeistFlock.Config
	local stageNumber = self:GetStage() + 1

	self:SetStage(stageNumber)
	self:SetHits(0)
	self:UpdateLook()
	self:BreakEffects(Config.Stages[stageNumber].scrap)

	local fullyStripped = stageNumber >= #Config.Stages

	if Config.RepairTime > 0 then
		if fullyStripped then
			self.RepairAt = CurTime() + Config.RepairTime
			self.IdleResetAt = nil
		elseif not IsValid(self:GetWorker()) then
			-- Damaged with nobody on it (smashed, or an admin skipped a stage): reset later too.
			self.IdleResetAt = CurTime() + Config.RepairTime
		end
	end

	return fullyStripped
end

function ENT:FinishStage(ply)
	local stageNumber = self:GetStage() + 1
	local fullyStripped = self:BreakNextPart()

	-- Does nothing unless crafting is on. Keeps what was given for the payout card.
	self.RunDrops = self.RunDrops or {}
	for _, drop in ipairs(HeistFlock.GiveStageLoot(ply, self, stageNumber)) do
		table.insert(self.RunDrops, drop)
	end

	if fullyStripped then
		self:StopWorking()
		HeistFlock.Payout(ply, self)
	else
		self:StartStage(ply) -- still working, so go straight into the next stage
	end
end

function ENT:BreakEffects(scrapCount)
	local center = HeistFlock.GetHousingPos(self)

	local sparks = EffectData()
	sparks:SetOrigin(center)
	sparks:SetMagnitude(2)
	sparks:SetScale(1)
	sparks:SetRadius(3)
	util.Effect("Sparks", sparks)

	-- Scrap pieces are made on each client (lua/effects/heistflock_scrap).
	local scrap = EffectData()
	scrap:SetOrigin(center)
	scrap:SetMagnitude(scrapCount or 0)
	util.Effect("heistflock_scrap", scrap)

	self:EmitSound("ambient/energy/spark" .. math.random(1, 6) .. ".wav")
	self:EmitSound("physics/metal/metal_box_break" .. math.random(1, 2) .. ".wav")
end
