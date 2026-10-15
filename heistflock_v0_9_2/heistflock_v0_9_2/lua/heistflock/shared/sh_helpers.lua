-- Small checks used by both server and client.

local Config = HeistFlock.Config

-- Settings added in 0.8.0 and later. An sh_config.lua kept from an older version
-- doesn't have them; fill in the defaults so everything still loads (the
-- server lists what was filled in on the Diagnostics page).
local ADDED_SINCE_0_8 = {
	StripMode = "smash",
	ManagerGroups = { "superadmin" },
	Smash = {
		Tools = { "heistflock_pliers", "weapon_crowbar" },
		AllowBullets = false,
		ExplosionsDestroy = true, -- 0.9.1
		ExplosionMaxDistance = 600, -- 0.9.2
		AlarmPerCamera = false, -- 0.9.2
		HitDelay = 0.35,
		AlarmChance = 10,
		AlarmOnFirstHit = false,
		AlarmMakesWanted = true,
		AlarmWantedReason = "Smashing a Flock camera",
		PoliceAlert = false,
	},
	ALPR = {
		Swivel = 30, -- 0.9.0
		TargetMode = "multi", -- 0.9.2: preserve the previous all-target scanning behavior
	},
	Parts = {
		Provider = "money",
		OwnerTime = 10,
		Lifetime = 120,
		MaxLoose = 60,
		PoliceConfiscate = true,
	},
}

HeistFlock.FilledConfig = {}

for key, default in pairs(ADDED_SINCE_0_8) do
	if Config[key] == nil then
		Config[key] = istable(default) and table.Copy(default) or default
		table.insert(HeistFlock.FilledConfig, key)
	elseif istable(default) and istable(Config[key]) then
		for subKey, subDefault in pairs(default) do
			if Config[key][subKey] == nil then
				Config[key][subKey] = istable(subDefault) and table.Copy(subDefault) or subDefault
				table.insert(HeistFlock.FilledConfig, key .. "." .. subKey)
			end
		end
	end
end

-- An older config named the parts provider in Crafting.
if istable(Config.Crafting) and isstring(Config.Crafting.Provider) and table.HasValue(HeistFlock.FilledConfig, "Parts") then
	Config.Parts.Provider = Config.Crafting.Provider
end

-- Every stage needs a name, hits (smash) and time (steps).
for i, stage in ipairs(Config.Stages) do
	if not isstring(stage.name) then stage.name = "Stage " .. i end
	if not isnumber(stage.hits) then stage.hits = 5 end
	if not isnumber(stage.time) then stage.time = 10 end
end

-- The built-in camera: an invisible base model, with the visible parts drawn
-- on each client (see entities/heistflock_camera/cl_init.lua).
-- Positions are relative to the bottom of the pole; +X is the way it faces.
HeistFlock.BuiltInBaseModel = "models/hunter/blocks/cube025x025x025.mdl"
HeistFlock.BuiltInHousingPos = Vector(10, 0, 77)

-- Everything the camera can occupy, used for range checks and markers.
HeistFlock.BuiltInMins = Vector(-8, -8, 0)
HeistFlock.BuiltInMaxs = Vector(18, 8, 96)

-- A little bigger than that, so the panel hanging off in stage 3 isn't cut off.
HeistFlock.BuiltInRenderMins = Vector(-10, -13, 0)
HeistFlock.BuiltInRenderMaxs = Vector(20, 13, 98)

-- What players, props and bullets actually hit: the pole, the camera head
-- and the solar panel, each as a box (min corner, max corner).
HeistFlock.BuiltInCollisionBoxes = {
	{ Vector(-2, -2, 0),   Vector(2, 2, 86) },    -- pole
	{ Vector(0, -3.5, 73), Vector(18, 3.5, 82) }, -- arm, housing and lens
	{ Vector(-7, -6, 86),  Vector(7, 6, 95) },    -- solar panel
}

-- The 8 corners of a box, the shape PhysicsInitMultiConvex expects.
function HeistFlock.BoxCorners(mins, maxs)
	return {
		Vector(mins.x, mins.y, mins.z), Vector(maxs.x, mins.y, mins.z),
		Vector(mins.x, maxs.y, mins.z), Vector(maxs.x, maxs.y, mins.z),
		Vector(mins.x, mins.y, maxs.z), Vector(maxs.x, mins.y, maxs.z),
		Vector(mins.x, maxs.y, maxs.z), Vector(maxs.x, maxs.y, maxs.z),
	}
end

function HeistFlock.UsesBuiltInModel()
	return Config.Model == ""
end

-- The point work happens at: the camera head, not the bottom of the pole.
function HeistFlock.GetHousingPos(cam)
	if HeistFlock.UsesBuiltInModel() then
		return cam:LocalToWorld(HeistFlock.BuiltInHousingPos)
	end
	return cam:WorldSpaceCenter()
end

-- Is this DarkRP job (a table from RPExtraTeams) in the config's job list?
function HeistFlock.IsJobListed(job)
	for _, listed in ipairs(Config.Jobs) do
		listed = string.lower(listed)
		if listed == string.lower(job.command or "") or listed == string.lower(job.name or "") then
			return true
		end
	end
	return false
end

function HeistFlock.IsUsingPliers(ply)
	local weapon = ply:GetActiveWeapon()
	return IsValid(weapon) and weapon:GetClass() == "heistflock_pliers"
end

-- Is the player holding the button that keeps work going? Only matters when
-- Config.RequireHold is on. With pliers out: left click or E. Without
-- pliers: E, if pliers aren't required.
function HeistFlock.IsHoldingWorkKey(ply)
	if HeistFlock.IsUsingPliers(ply) then
		return ply:KeyDown(IN_ATTACK) or ply:KeyDown(IN_USE)
	end
	return not Config.RequirePliers and ply:KeyDown(IN_USE)
end

-- The steps a stage can use right now: its own "checks" list, without
-- duplicates, keeping only steps that exist and are turned on.
function HeistFlock.GetStageCheckTypes(stagePool)
	local result, seen = {}, {}
	for _, checkType in ipairs(stagePool or {}) do
		if not seen[checkType] and Config.SkillCheckTypes[checkType] == true then
			seen[checkType] = true
			table.insert(result, checkType)
		end
	end
	return result
end

-- How many skill checks each stage gets: Config.SkillChecksPerCamera spread
-- across the stages that have at least one step turned on, by their length,
-- with leftovers going to the longest ones. A stage whose steps are all
-- turned off gets none. 4 checks over stages of 11, 11 and 13 seconds gives
-- 1, 1 and 2.
function HeistFlock.DistributeChecks()
	local stages = Config.Stages
	local counts, shares = {}, {}
	for i = 1, #stages do counts[i], shares[i] = 0, -1 end

	local total = Config.SkillChecks and Config.SkillChecksPerCamera or 0

	local usable, totalTime = {}, 0
	for i, stage in ipairs(stages) do
		if #HeistFlock.GetStageCheckTypes(stage.checks) > 0 then
			table.insert(usable, i)
			totalTime = totalTime + stage.time
		end
	end
	if total <= 0 or #usable == 0 then return counts end

	local assigned = 0
	for _, i in ipairs(usable) do
		local exact = total * stages[i].time / math.max(totalTime, 1)
		counts[i] = math.floor(exact)
		shares[i] = exact - counts[i]
		assigned = assigned + counts[i]
	end

	while assigned < total do
		local best = usable[1]
		for _, i in ipairs(usable) do
			if shares[i] > shares[best] then best = i end
		end
		counts[best] = counts[best] + 1
		shares[best] = -1
		assigned = assigned + 1
	end

	return counts
end

function HeistFlock.FormatMoney(amount)
	if DarkRP and DarkRP.formatMoney then
		return DarkRP.formatMoney(amount)
	end
	return "$" .. string.Comma(amount)
end

-- The skill check types turned on in the config, e.g. { "screws", "pry" }.
function HeistFlock.GetEnabledCheckTypes()
	local enabled = {}
	for checkType, isOn in SortedPairs(Config.SkillCheckTypes) do
		if isOn then table.insert(enabled, checkType) end
	end
	return enabled
end

-- Is the player close enough to the camera to work on it?
-- Measures to the camera's nearest edge, not its center.
function HeistFlock.IsInRange(ply, cam)
	local eyes = ply:EyePos()
	return eyes:DistToSqr(cam:NearestPoint(eyes)) <= Config.MaxDistance ^ 2
end
