-- A part that fell off a smashed camera (smash mode). Players press E on it
-- to pick it up (see sv_loot.lua). Made only by the server, never saved,
-- copied or spawned from the menu.

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Camera Part"
ENT.Category = "Heist Flock"
ENT.Spawnable = false
ENT.DisableDuplicator = true
ENT.DoNotDuplicate = true

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "MaterialId")  -- e.g. "copper_wire"
	self:NetworkVar("Int", 0, "Amount")
	self:NetworkVar("Entity", 0, "PartOwner")   -- who broke the stage it came from
	self:NetworkVar("Float", 0, "OwnerUntil")   -- only the owner can pick it up until then
end
