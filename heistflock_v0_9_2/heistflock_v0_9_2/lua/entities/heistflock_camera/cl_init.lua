include("shared.lua")

-- The built-in Flock camera: a pole with a camera head and a solar panel,
-- drawn from two shapes that ship with the game (a cube and a soda can,
-- scaled to size), so players don't need to download anything.
--
-- Positions are in units from the bottom of the pole. +X is the way the
-- camera faces, +Z is up. Each part can change at each stage: later stages
-- build on earlier ones, so hidden = true at stage 2 stays hidden at 3.

local BOX = "models/hunter/blocks/cube025x025x025.mdl"
local CYLINDER = "models/props_junk/PopCan01a.mdl"

local PAINT = "models/debug/debugwhite"
local GLOSS = "models/shiny"
local MAT_CABLE = Material("cable/cable2")
local MAT_GLOW = Material("sprites/light_glow02_add")

local DETAIL_DISTANCE = 1500 -- LED, wires and sparks are skipped further away

local METAL   = Color(58, 60, 66)
local HOUSING = Color(28, 29, 32)
local LID     = Color(40, 42, 46)
local BURNT   = Color(36, 33, 31) -- charred, not brown (brown read as a leather case)
local HOLE    = Color(6, 6, 7)
local GLASS   = Color(10, 14, 22)
local PANEL   = Color(26, 44, 92)
local FRAME   = Color(150, 152, 158)
local PCB     = Color(30, 110, 50)
local GOLD    = Color(230, 180, 60)

-- The solar panel gets knocked loose in stage 1 and hangs off in stage 3.
local PANEL_STAGES = {
	[1] = { ang = Angle(25, 0, 30) },
	[3] = { pos = Vector(0, 5, 86), ang = Angle(10, 0, 80) },
}

local PARTS = {
	-- Pole
	{ shape = "box",      size = Vector(12, 12, 1.5), pos = Vector(0, 0, 0.75), color = METAL },
	{ shape = "cylinder", size = Vector(3.2, 3.2, 84), pos = Vector(0, 0, 42.75), color = METAL },
	{ shape = "box",      size = Vector(9, 2, 2), pos = Vector(4.5, 0, 80), color = METAL },

	-- Camera head
	{ shape = "box", size = Vector(12, 6, 6), pos = Vector(10, 0, 77), color = HOUSING,
		-- Stripped: charred, and hanging nose-down off the end of the arm.
		stages = { [3] = { color = BURNT, pos = Vector(9.5, 0, 75.5), ang = Angle(25, 0, 0) } } },
	-- Stripped: an empty hole where the lens was, on the front of the hanging housing.
	{ shape = "cylinder", axis = "x", size = Vector(3.6, 3.6, 0.6), pos = Vector(16.3, 0, 77), color = HOLE, hidden = true,
		stages = { [3] = { hidden = false, pos = Vector(15.03, 0, 72.92), ang = Angle(25, 0, 0) } } },
	{ shape = "cylinder", axis = "x", size = Vector(5, 5, 1), pos = Vector(16.3, 0, 77), color = HOUSING, detail = true,
		stages = { [3] = { hidden = true } } },
	{ shape = "cylinder", axis = "x", size = Vector(4, 4, 1.6), pos = Vector(17, 0, 77), color = GLASS, material = GLOSS,
		stages = { [3] = { hidden = true } } },

	-- Lid: closed, then swung open on its back edge, then gone
	{ shape = "box", size = Vector(12.6, 6.6, 1), pos = Vector(10, 0, 80.5), color = LID,
		stages = { [1] = { pos = Vector(5.9, 0, 86.9), ang = Angle(-70, 0, 0) }, [2] = { hidden = true } } },

	-- Circuit board and gold contacts, visible once the lid is open
	{ shape = "box", size = Vector(10, 5, 0.4), pos = Vector(10, 0, 80.2), color = PCB, detail = true,
		stages = { [3] = { hidden = true } } },
	{ shape = "box", size = Vector(1.6, 1, 0.5), pos = Vector(8, 1.5, 80.5), color = GOLD, material = GLOSS, detail = true,
		stages = { [3] = { hidden = true } } },
	{ shape = "box", size = Vector(1.6, 1, 0.5), pos = Vector(8, -1.5, 80.5), color = GOLD, material = GLOSS, detail = true,
		stages = { [3] = { hidden = true } } },

	-- Solar panel
	{ shape = "cylinder", size = Vector(1.6, 1.6, 7), pos = Vector(0, 0, 87.5), color = METAL },
	{ shape = "box", size = Vector(15, 11, 0.5), pos = Vector(0, 0, 91.5), ang = Angle(25, 0, 0), color = FRAME,
		stages = PANEL_STAGES },
	{ shape = "box", size = Vector(14, 10, 0.6), pos = Vector(0, 0, 91.5), ang = Angle(25, 0, 0), color = PANEL, material = GLOSS,
		stages = PANEL_STAGES },
}

-- When hit, everything from the arm up shakes around the top of the pole.
-- When following a car, the arm and camera head (not the solar panel above
-- them) turn around the pole.
local HEAD_HEIGHT = 70
local PANEL_HEIGHT = 85
local HEAD_PIVOT = Vector(0, 0, 80)
local SHAKE_TIME = 0.3
local SWIVEL_SPEED = 70 -- degrees per second the head turns

local LED_POS = Vector(16.8, 2.4, 79.4)
local LED_COLOR = Color(255, 40, 30)
local WIRE_COLORS = { Color(205, 125, 60), Color(190, 45, 40), Color(50, 80, 190) }

-- Where a part is, how it's turned, its color and whether it's hidden at a stage.
local function resolvePart(part, stage)
	local pos, ang, color, hidden = part.pos, part.ang or angle_zero, part.color, part.hidden or false

	if part.stages then
		for s = 1, stage do
			local change = part.stages[s]
			if change then
				pos = change.pos or pos
				ang = change.ang or ang
				color = change.color or color
				if change.hidden ~= nil then hidden = change.hidden end
			end
		end
	end

	return pos, ang, color, hidden
end

local function createPartModel(part)
	local model = ClientsideModel(part.shape == "box" and BOX or CYLINDER, RENDERGROUP_OPAQUE)
	if not IsValid(model) then return end

	model:SetNoDraw(true) -- drawn by hand in ENT:Draw, only when the camera is drawn
	model:SetMaterial(part.material or PAINT)

	-- Scale the shape to the part's size and center it on the part's position.
	local mins, maxs = model:GetModelBounds()
	local modelSize = maxs - mins
	local matrix = Matrix()
	matrix:Scale(Vector(part.size.x / modelSize.x, part.size.y / modelSize.y, part.size.z / modelSize.z))
	matrix:Translate(-(mins + maxs) / 2)
	model:EnableMatrix("RenderMultiply", matrix)

	return model
end

-- One set of part models shared by every camera: each camera moves them into
-- place and draws them in turn. Kept on the HeistFlock table so a Lua refresh
-- reuses them instead of leaking a new set.
local function getPartModels()
	local models = HeistFlock.CameraPartModels

	if not models or not IsValid(models[1]) or #models ~= #PARTS then
		-- The old set (e.g. from before a Lua refresh) would otherwise linger.
		for _, oldModel in pairs(models or {}) do
			if IsValid(oldModel) then oldModel:Remove() end
		end

		models = {}
		for i, part in ipairs(PARTS) do
			models[i] = createPartModel(part)
		end
		HeistFlock.CameraPartModels = models
	end

	return models
end

function ENT:Initialize()
	self:SetupCollisions() -- so traces on this client hit the camera too
	self:UpdateRenderBounds()
end

function ENT:UpdateRenderBounds()
	if HeistFlock.UsesBuiltInModel() then
		self:SetRenderBounds(HeistFlock.BuiltInRenderMins, HeistFlock.BuiltInRenderMaxs)
	else
		self:SetRenderBounds(self:GetModelBounds())
	end
end

-- Turns the head toward the car the server says to follow, at a steady
-- speed, within ALPR.Swivel either way. Back to straight when there's none.
function ENT:UpdateSwivel()
	local maxTurn = HeistFlock.Config.ALPR.Swivel or 0
	local target = self:GetTrackTarget()
	local wanted = 0

	if maxTurn > 0 and IsValid(target) then
		local localPos = self:WorldToLocal(target:WorldSpaceCenter())
		wanted = math.Clamp(math.deg(math.atan2(localPos.y, localPos.x)), -maxTurn, maxTurn)
	end

	self.SwivelYaw = math.Approach(self.SwivelYaw or 0, wanted, FrameTime() * SWIVEL_SPEED)
end

function ENT:Think()
	self:UpdateSwivel()

	-- The settings can arrive before the server's model change does, so redo
	-- collisions whenever the model actually changes.
	if self:GetModel() ~= self.CollisionModel then
		self:SetupCollisions()
		self:UpdateRenderBounds()
	end

	-- This client's copy of the collision shape (used for aiming at the
	-- camera) doesn't move on its own. Keep it on the camera, or it stays
	-- behind while an admin moves the camera with the physgun.
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		local pos, ang = self:GetPos(), self:GetAngles()
		if phys:GetPos() ~= pos or phys:GetAngles() ~= ang then
			phys:SetPos(pos)
			phys:SetAngles(ang)
		end
	end
end

-- How much the head is knocked about by the last hit, or nil when still.
local function getShake(ent)
	local age = CurTime() - ent:GetLastHit()
	if age < 0 or age > SHAKE_TIME then return end

	local strength = (1 - age / SHAKE_TIME) * 6
	return Angle(math.sin(age * 60) * strength, math.sin(age * 45 + 1) * strength * 0.6, 0)
end

-- A point on the head, turned by the swivel. For the LED and wires.
local function turnHead(localPos, swivel)
	if not swivel or swivel == 0 then return localPos end
	local offset = localPos - HEAD_PIVOT
	offset:Rotate(Angle(0, swivel, 0))
	return HEAD_PIVOT + offset
end

-- Draws the built-in camera at any spot. Used by every camera, and by the
-- placement preview (tint = one color for every part, e.g. a see-through ghost).
-- shake (optional) knocks the head about; swivel (optional, degrees) turns it.
function HeistFlock.DrawBuiltInCamera(entPos, entAng, stage, tint, shake, swivel)
	local partModels = getPartModels()
	local closeUp = EyePos():DistToSqr(entPos) < DETAIL_DISTANCE ^ 2

	for i, part in ipairs(PARTS) do
		local model = partModels[i]
		local pos, ang, color, hidden = resolvePart(part, stage)

		if IsValid(model) and not hidden and (closeUp or not part.detail) then
			if part.axis == "x" then
				ang = Angle(ang.p + 90, ang.y, ang.r) -- lay the can on its side
			end

			-- Which group a part is in goes by where it starts, so the lid
			-- still turns with the head when it's swung open above it.
			local isHead = part.pos.z >= HEAD_HEIGHT and part.pos.z < PANEL_HEIGHT
			if swivel and swivel ~= 0 and isHead then
				pos, ang = LocalToWorld(pos - HEAD_PIVOT, ang, HEAD_PIVOT, Angle(0, swivel, 0))
			end
			if shake and pos.z >= HEAD_HEIGHT then
				pos, ang = LocalToWorld(pos - HEAD_PIVOT, ang, HEAD_PIVOT, shake)
			end

			-- The same part models are drawn for every camera, so move each one
			-- into place and make the engine recalculate its position. Without
			-- SetupBones it reuses the first position it worked out this frame,
			-- and every camera gets drawn where the first one stands.
			local worldPos, worldAng = LocalToWorld(pos, ang, entPos, entAng)
			model:SetPos(worldPos)
			model:SetAngles(worldAng)
			model:SetupBones()

			local drawColor = tint or color
			render.SetColorModulation(drawColor.r / 255, drawColor.g / 255, drawColor.b / 255)
			model:DrawModel()
		end
	end

	render.SetColorModulation(1, 1, 1)
end

function ENT:Draw()
	local shake = getShake(self)

	local swivel = self.SwivelYaw or 0

	if not HeistFlock.UsesBuiltInModel() then
		-- A custom model turns as a whole.
		local turned = shake or swivel ~= 0
		if turned then
			self:SetRenderAngles(self:GetAngles() + Angle(0, swivel, 0) + (shake and shake * 0.5 or angle_zero))
		end
		self:DrawModel()
		if turned then self:SetRenderAngles(nil) end
		return
	end

	HeistFlock.DrawBuiltInCamera(self:GetPos(), self:GetAngles(), self:GetStage(), nil, shake, swivel)
end

-- LED, wires and sparks. Drawn in the translucent pass, after ENT:Draw.
function ENT:DrawTranslucent()
	if not HeistFlock.UsesBuiltInModel() then return end

	local entPos, entAng = self:GetPos(), self:GetAngles()
	if EyePos():DistToSqr(entPos) > DETAIL_DISTANCE ^ 2 then return end

	local stage = self:GetStage()

	-- A short red blink while the camera still works, and fast flashing
	-- while its alarm is going off.
	local blink
	if CurTime() < self:GetAlarmUntil() then
		blink = CurTime() % 0.3 < 0.15
	else
		blink = stage <= 1 and CurTime() % 1.2 < 0.15
	end
	local swivel = self.SwivelYaw or 0

	if blink then
		local ledPos = LocalToWorld(turnHead(LED_POS, swivel), angle_zero, entPos, entAng)
		render.SetMaterial(MAT_GLOW)
		render.DrawSprite(ledPos, 7, 7, LED_COLOR)
	end

	-- Wires: pulled out and dangling in stage 2; in stage 3, cut stubs
	-- sticking out of the top of the hanging housing.
	if stage >= 2 then
		render.SetMaterial(MAT_CABLE)

		for i, color in ipairs(WIRE_COLORS) do
			local side = (i - 2) * 1.6
			local startLocal, bendLocal, endLocal
			if stage == 2 then
				startLocal, bendLocal, endLocal = Vector(9, side, 80.4), Vector(12, side * 1.3, 82), Vector(14, side * 1.8, 69.4)
			else
				startLocal, bendLocal, endLocal = Vector(10.8, side, 78.2), Vector(12.2, side * 1.6, 79.6), Vector(13.4, side * 2.1, 79)
			end
			local startPos = LocalToWorld(turnHead(startLocal, swivel), angle_zero, entPos, entAng)
			local bendPos = LocalToWorld(turnHead(bendLocal, swivel), angle_zero, entPos, entAng)
			local endPos = LocalToWorld(turnHead(endLocal, swivel), angle_zero, entPos, entAng)

			render.StartBeam(3)
			render.AddBeam(startPos, 0.6, 0, color)
			render.AddBeam(bendPos, 0.6, 0.5, color)
			render.AddBeam(endPos, 0.6, 1, color)
			render.EndBeam()
		end
	end

	-- The exposed wiring sparks now and then.
	if stage == 2 and CurTime() >= (self.NextSpark or 0) then
		self.NextSpark = CurTime() + math.Rand(2, 5)

		local sparkPos = LocalToWorld(turnHead(Vector(10, 0, 81), swivel), angle_zero, entPos, entAng)
		local effect = EffectData()
		effect:SetOrigin(sparkPos)
		effect:SetMagnitude(1)
		effect:SetScale(0.5)
		effect:SetRadius(1)
		util.Effect("Sparks", effect)
	end
end
