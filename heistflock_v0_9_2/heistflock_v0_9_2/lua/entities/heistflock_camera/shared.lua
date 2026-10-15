ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Flock Camera"
ENT.Category = "Heist Flock"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH -- the LED and wires are drawn as translucent

-- Cameras are only made by admins (spawn menu, !heistflock) and the save file,
-- never copied with the duplicator or Advanced Duplicator.
ENT.DisableDuplicator = true
ENT.DoNotDuplicate = true

-- Values the server sets and every client can read.
function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Stage")           -- 0 = untouched, 3 = stripped
	self:NetworkVar("Int", 1, "Hits")            -- smash mode: hits on the current stage so far
	self:NetworkVar("Float", 3, "LastHit")       -- smash mode: when it was last hit (the head shakes)
	self:NetworkVar("Float", 4, "AlarmUntil")    -- the LED flashes until then
	self:NetworkVar("Entity", 1, "TrackTarget")  -- the car the head turns to follow (plate scanning)
	-- Steps mode:
	self:NetworkVar("Entity", 0, "Worker")       -- player working on it right now
	self:NetworkVar("Float", 0, "StageStart")    -- when the current stage began
	self:NetworkVar("Float", 1, "StageLength")   -- 0 when nobody is working
	self:NetworkVar("Bool", 0, "CheckActive")    -- a skill check is open; the stage timer is paused
	self:NetworkVar("Float", 2, "PauseFraction") -- how far through the stage it paused (0-1)
end

-- How far through the current stage the worker is, from 0 to 1.
function ENT:GetStageProgress()
	if self:GetStageLength() <= 0 then return 0 end
	if self:GetCheckActive() then return self:GetPauseFraction() end

	local progress = (CurTime() - self:GetStageStart()) / self:GetStageLength()
	return math.Clamp(progress, 0, 1)
end

local CAMERA_MASS = 50

function ENT:GetCameraBounds()
	if HeistFlock.UsesBuiltInModel() then
		return HeistFlock.BuiltInMins, HeistFlock.BuiltInMaxs
	end
	return self:GetModelBounds()
end

-- Frozen collisions for the camera. The built-in camera gets one box for the
-- pole, one for the head and one for the panel, so the empty space around the
-- thin pole doesn't block anyone. A custom model gets one box around it,
-- which works even for models with no physics mesh.
-- Runs on server and client so both agree on where the camera is.
function ENT:SetupCollisions()
	local mins, maxs = self:GetCameraBounds()

	if HeistFlock.UsesBuiltInModel() then
		local shapes = {}
		for _, box in ipairs(HeistFlock.BuiltInCollisionBoxes) do
			table.insert(shapes, HeistFlock.BoxCorners(box[1], box[2]))
		end
		self:PhysicsInitMultiConvex(shapes)
	else
		self:PhysicsInitBox(mins, maxs)
	end

	self:SetCollisionBounds(mins, maxs) -- the overall size, used by range checks
	self:SetSolid(SOLID_VPHYSICS)
	self:EnableCustomCollisions(true)

	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:EnableMotion(false)

		-- The collision shape's mass is worked out from its size, so a big
		-- camera ends up heavy and drags behind the physgun. A fixed, light
		-- mass makes it follow the beam smoothly.
		phys:SetMass(CAMERA_MASS)
	end

	self.CollisionModel = self:GetModel() -- lets the client notice a model change
end
