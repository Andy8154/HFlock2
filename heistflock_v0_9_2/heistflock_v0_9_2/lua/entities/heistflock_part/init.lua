AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- Called before Spawn by HeistFlock.DropStageParts.
function ENT:SetupPart(materialId, amount, owner)
	local Config = HeistFlock.Config
	local material = HeistFlock.GetMaterial(materialId)

	self:SetMaterialId(materialId)
	self:SetAmount(amount)
	self:SetPartOwner(IsValid(owner) and owner or NULL)
	self:SetOwnerUntil(CurTime() + Config.Parts.OwnerTime)
	self.DieAt = CurTime() + Config.Parts.Lifetime

	local model = material and material.model or HeistFlock.FallbackPartModel
	if not util.IsValidModel(model) then
		HeistFlock.Warn("The model for " .. materialId .. " (" .. model .. ") isn't on the server. Using a scrap model instead.")
		model = HeistFlock.FallbackPartModel
	end
	self:SetModel(model)
	if material and material.color then self:SetColor(material.color) end
end

function ENT:Initialize()
	local model = self:GetModel()
	if not model or model == "" then self:SetModel(HeistFlock.FallbackPartModel) end -- spawned some other way

	self:PhysicsInit(SOLID_VPHYSICS)
	if not IsValid(self:GetPhysicsObject()) then
		-- A model with no physics mesh: a small box instead.
		self:PhysicsInitBox(Vector(-3, -3, -3), Vector(3, 3, 3))
	end
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)

	-- Collides with the world and props, but players walk through it, so
	-- parts can't be used to block doors or launch people.
	self:SetCollisionGroup(COLLISION_GROUP_WEAPON)

	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetMass(5)
		phys:Wake()
	end

	self.DieAt = self.DieAt or CurTime() + HeistFlock.Config.Parts.Lifetime
end

function ENT:Think()
	if CurTime() >= self.DieAt then
		self:Remove()
		return
	end

	self:NextThink(CurTime() + 1)
	return true
end

function ENT:OnRemove()
	HeistFlock.ForgetPart(self)
end
