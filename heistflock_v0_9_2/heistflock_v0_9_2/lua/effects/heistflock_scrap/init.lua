-- Scrap that flies off a camera when a stage finishes. Each client makes its
-- own pieces, so they cost the server nothing and aren't networked.
-- Started by the server with util.Effect("heistflock_scrap", data):
--   data:GetOrigin()    where the scrap comes from
--   data:GetMagnitude() how many pieces

local LIFETIME = 8
local MAX_PIECES = 10

function EFFECT:Init(data)
	local origin = data:GetOrigin()
	local count = math.Clamp(math.floor(data:GetMagnitude()), 0, MAX_PIECES)
	local models = HeistFlock and HeistFlock.Config.ScrapModels or {}
	if #models == 0 then return end

	for i = 1, count do
		local scrap = ents.CreateClientProp(models[math.random(#models)])

		if IsValid(scrap) then
			scrap:SetPos(origin + VectorRand() * 4)
			scrap:SetAngles(AngleRand())
			scrap:Spawn()
			scrap:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

			local phys = scrap:GetPhysicsObject()
			if IsValid(phys) then
				phys:Wake()
				phys:SetVelocity(VectorRand() * 80 + Vector(0, 0, 60))
			end

			SafeRemoveEntityDelayed(scrap, LIFETIME)
		end
	end
end

-- Nothing to keep running: the pieces remove themselves.
function EFFECT:Think()
	return false
end

function EFFECT:Render()
end
