-- Works out each player's Heist Flock access from the admin mod, keeps the
-- answer, and shares it with that player's game (see sh_permissions.lua).
--
-- Every admin mod listed in permissions_guide.lua answers through CAMI, so
-- there is no code for any one mod here. CAMI is asked with a callback,
-- because some mods only answer that way, and the answer is kept until the
-- next one arrives. Until the first answer, a player has no access.

local Config = HeistFlock.Config
local REFRESH_INTERVAL = 15 -- permissions can change without a rank change (e.g. edited in SAM)

-- Admin mods, by the global table each one creates. Only for Diagnostics.
local ADMIN_MODS = {
	{ "ULX", function() return ulx ~= nil and ULib ~= nil end },
	{ "SAM", function() return sam ~= nil end },
	{ "FAdmin", function() return FAdmin ~= nil end },
	{ "sAdmin", function() return sAdmin ~= nil end },
	{ "xAdmin", function() return xAdmin ~= nil end },
	{ "ServerGuard", function() return serverguard ~= nil end },
}

function HeistFlock.DetectAdminMods()
	local found = {}
	for _, adminMod in ipairs(ADMIN_MODS) do
		if adminMod[2]() then table.insert(found, adminMod[1]) end
	end
	return found
end

local function usesCAMI()
	return CAMI ~= nil and isfunction(CAMI.PlayerHasAccess)
end

-- Stores one answer and shares the result with the player's game.
local function setAnswer(ply, key, allowed)
	ply.HeistFlockAnswers = ply.HeistFlockAnswers or {}
	ply.HeistFlockAnswers[key] = allowed

	local mask = 0
	for answerKey, answer in pairs(ply.HeistFlockAnswers) do
		if answer then mask = bit.bor(mask, HeistFlock.AccessBits[answerKey]) end
	end

	ply.HeistFlockAccess = mask
	if ply:GetNW2Int("HeistFlock_Access", 0) ~= mask then
		ply:SetNW2Int("HeistFlock_Access", mask)
	end
end

local warnedAboutCAMI = false

function HeistFlock.RefreshAccess(ply)
	if not IsValid(ply) or ply:IsBot() then return end

	-- No admin mod and no CAMI: Config.ManagerGroups gets full access.
	if not usesCAMI() then
		local allowed = table.HasValue(Config.ManagerGroups, string.lower(ply:GetUserGroup()))
		for _, privilege in ipairs(HeistFlock.Privileges) do
			setAnswer(ply, privilege.key, allowed)
		end
		return
	end

	for _, privilege in ipairs(HeistFlock.Privileges) do
		local key = privilege.key
		local ok, err = pcall(CAMI.PlayerHasAccess, ply, privilege.name, function(hasAccess)
			if IsValid(ply) then setAnswer(ply, key, hasAccess == true) end
		end)

		if not ok then
			setAnswer(ply, key, false) -- a broken check never grants access
			if not warnedAboutCAMI then
				warnedAboutCAMI = true
				HeistFlock.Warn("The admin mod gave an error when asked about Heist Flock permissions: " .. tostring(err))
			end
		end
	end
end

-- Joining: ask straight away, and again once admin mods have loaded the rank.
hook.Add("PlayerInitialSpawn", "HeistFlock_Access", function(ply)
	HeistFlock.RefreshAccess(ply)
	timer.Simple(3, function() HeistFlock.RefreshAccess(ply) end)
end)

-- The first spawn, for admin mods that set the rank only then.
hook.Add("PlayerSpawn", "HeistFlock_Access", function(ply)
	if ply.HeistFlockSpawnedOnce then return end
	ply.HeistFlockSpawnedOnce = true
	timer.Simple(0, function() HeistFlock.RefreshAccess(ply) end)
end)

hook.Add("CAMI.PlayerUsergroupChanged", "HeistFlock_Access", function(ply)
	timer.Simple(0, function() HeistFlock.RefreshAccess(ply) end)
end)

hook.Add("CAMI.SteamIDUsergroupChanged", "HeistFlock_Access", function(steamId)
	timer.Simple(0, function()
		local ply = isstring(steamId) and player.GetBySteamID(steamId)
		if IsValid(ply) then HeistFlock.RefreshAccess(ply) end
	end)
end)

timer.Create("HeistFlock_Access", REFRESH_INTERVAL, 0, function()
	for _, ply in ipairs(player.GetHumans()) do
		HeistFlock.RefreshAccess(ply)
	end
end)

-- After a Lua refresh, players already on the server need asking again.
for _, ply in ipairs(player.GetHumans()) do
	HeistFlock.RefreshAccess(ply)
end

local PRIVILEGE_NAMES = {}
for _, privilege in ipairs(HeistFlock.Privileges) do
	PRIVILEGE_NAMES[privilege.key] = privilege.name
end

-- For server handlers: true if the player has this access. If not, they're
-- told which permission is missing (at most every few seconds), so a denied
-- action never just silently does nothing.
function HeistFlock.RequireAccess(ply, level)
	if HeistFlock.HasAccess(ply, level) then return true end

	if IsValid(ply) and not HeistFlock.IsThrottled(ply, "denied", 3) then
		HeistFlock.Notify(ply, "You don't have the \"" .. PRIVILEGE_NAMES[level] .. "\" permission. Ask a server owner (see permissions_guide.lua).", true)
	end
	return false
end

-- Config.ManagerGroups may have changed (only matters without CAMI).
hook.Add("HeistFlock_SettingsChanged", "HeistFlock_Access", function()
	for _, ply in ipairs(player.GetHumans()) do
		HeistFlock.RefreshAccess(ply)
	end
end)

-- For the Diagnostics page: what was found, and this player's own access.
function HeistFlock.PermissionInfo(ply)
	local privileges = {}
	for _, privilege in ipairs(HeistFlock.Privileges) do
		table.insert(privileges, {
			name = privilege.name,
			registered = CAMI ~= nil and CAMI.GetPrivilege ~= nil and CAMI.GetPrivilege(privilege.name) ~= nil,
			yours = HeistFlock.HasAccess(ply, privilege.key),
		})
	end

	return {
		adminMods = HeistFlock.DetectAdminMods(),
		cami = usesCAMI(),
		camiVersion = CAMI and CAMI.Version or nil,
		privileges = privileges,
		fallbackGroups = Config.ManagerGroups,
	}
end

-- Admin actions: the activity feed, the server log, ULX's log, and a hook
-- for logging addons.
function HeistFlock.AdminLog(ply, text)
	local line = (IsValid(ply) and ply:Nick() or "Console") .. " " .. text

	HeistFlock.AddActivity("admin", line)
	ServerLog("[HeistFlock] " .. line .. "\n")

	if ulx and isfunction(ulx.logString) then
		pcall(ulx.logString, "[HeistFlock] " .. line)
	end

	hook.Run("HeistFlock_AdminAction", ply, text)
end
