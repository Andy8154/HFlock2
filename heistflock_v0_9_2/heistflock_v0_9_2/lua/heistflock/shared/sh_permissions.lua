-- Who may do what. Three permissions, registered with the admin mod through
-- CAMI (ULX, SAM, FAdmin, sAdmin, xAdmin, ServerGuard all read it):
--
--   manage  "HeistFlock Manage"  settings, reset, and the whole menu
--   place   "HeistFlock Place"   place, move, remove, reset and skip cameras
--   view    "HeistFlock View"    camera markers, Cameras and Diagnostics pages
--
-- Manage includes the other two, and Place includes View (placing is done
-- from the menu, so it has to open). The server works out each player's access
-- (sv_permissions.lua) and shares it; players' games only use it to decide
-- what to show. Every action is checked again on the server.

HeistFlock.Privileges = {
	{ key = "manage", name = "HeistFlock Manage", minAccess = "superadmin",
		description = "Heist Flock: change settings and use the whole menu" },
	{ key = "place", name = "HeistFlock Place", minAccess = "superadmin",
		description = "Heist Flock: place, move, remove, reset and skip cameras" },
	{ key = "view", name = "HeistFlock View", minAccess = "admin",
		description = "Heist Flock: see cameras on the map and the Diagnostics page" },
}

-- Bits in the number the server shares with each player.
HeistFlock.AccessBits = { view = 1, place = 2, manage = 4 }

-- Registers the privileges once. Called when this file loads and again in
-- Initialize, in case CAMI itself loads after Heist Flock.
local function registerPrivileges()
	if not CAMI or not CAMI.RegisterPrivilege then return end

	for _, privilege in ipairs(HeistFlock.Privileges) do
		if not (CAMI.GetPrivilege and CAMI.GetPrivilege(privilege.name)) then
			CAMI.RegisterPrivilege({
				Name = privilege.name,
				MinAccess = privilege.minAccess,
				Description = privilege.description,
			})
		end
	end
end

registerPrivileges()
hook.Add("Initialize", "HeistFlock_RegisterPrivileges", registerPrivileges)

-- Does this player have this access? level = "manage", "place" or "view".
-- On the server it's the answer from the admin mod, worked out ahead of
-- time; until that answer arrives, the answer is no.
function HeistFlock.HasAccess(ply, level)
	if not IsValid(ply) or not ply:IsPlayer() then return false end

	local mask = SERVER and (ply.HeistFlockAccess or 0) or ply:GetNW2Int("HeistFlock_Access", 0)
	local bits = HeistFlock.AccessBits
	if not bits[level] then return false end

	if bit.band(mask, bits.manage) ~= 0 then return true end -- manage includes everything
	if level == "view" and bit.band(mask, bits.place) ~= 0 then return true end
	return bit.band(mask, bits[level]) ~= 0
end

-- Older name, kept for addons that used it: full access.
function HeistFlock.IsManager(ply)
	return HeistFlock.HasAccess(ply, "manage")
end
