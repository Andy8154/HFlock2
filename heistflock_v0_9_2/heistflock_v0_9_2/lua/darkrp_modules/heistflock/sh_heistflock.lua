--[[-------------------------------------------------------------------------
	HEIST FLOCK - DARKRP SETUP

	DarkRP loads this file on its own. It can add a Camera Stripper job and
	a pliers shipment for you, so you don't have to edit jobs.lua.

	Both are OFF by default. Turn them on with Config.DarkRP in
	lua/heistflock/shared/sh_config.lua, only if you haven't already added
	the same job or shipment in darkrpmodification (or you'll get it twice).
	The job and shipment details are below.
---------------------------------------------------------------------------]]

-- Reads the switches from the addon's config when it has loaded.
local function isOn(switch)
	local settings = HeistFlock and HeistFlock.Config and HeistFlock.Config.DarkRP
	return settings ~= nil and settings[switch] == true
end

local JOB = {
	name = "Camera Stripper",
	command = "camerastripper",
	color = Color(46, 230, 166, 255),
	model = { "models/player/group03/male_04.mdl" },
	description = [[Smash Flock cameras apart and sell the parts. Illegal.]],
	max = 4,
	salary = 45,
	category = "Gangsters", -- must be a job category that exists on your server
}

local SHIPMENT = {
	name = "Pliers",
	price = 1500,     -- for a crate of 5
	priceEach = 300,  -- for one
	category = "Other", -- must be a shipment category that exists on your server

	-- Which jobs can buy it, by their command (e.g. "gundealer"). Commands are
	-- used instead of TEAM_ names because they can't break if a TEAM_ variable
	-- isn't defined yet. "camerastripper" only counts if AddJob is on.
	-- Leave the list empty ({}) to use whatever DarkRP's default is.
	allowed = { "gundealer" },
}

-- Turns job commands into the team numbers DarkRP expects. Unknown commands
-- are skipped with a console message.
local function teamsFromCommands(commands)
	local teams = {}
	for _, command in ipairs(commands) do
		local found = false
		for index, job in ipairs(RPExtraTeams or {}) do
			if job.command == command then
				table.insert(teams, index)
				found = true
				break
			end
		end
		if not found then
			print("[HeistFlock] Shipment: no job with the command \"" .. command .. "\", skipped.")
		end
	end
	return teams
end

-- Runs when DarkRP loads its custom jobs and items.
hook.Add("loadCustomDarkRPItems", "HeistFlock_DarkRP", function()
	if isOn("AddJob") then
		TEAM_CAMSTRIPPER = DarkRP.createJob(JOB.name, {
			color = JOB.color,
			model = JOB.model,
			description = JOB.description,
			weapons = { "heistflock_pliers" },
			command = JOB.command,
			max = JOB.max,
			salary = JOB.salary,
			admin = 0,
			vote = false,
			hasLicense = false,
			category = JOB.category,
		})
	end

	if isOn("AddShipment") then
		DarkRP.createShipment(SHIPMENT.name, {
			model = HeistFlock.Config.PliersWorldModel,
			entity = "heistflock_pliers",
			price = SHIPMENT.price,
			amount = 5,
			separate = true,
			pricesep = SHIPMENT.priceEach,
			noship = false,
			category = SHIPMENT.category,
			-- nil (field left out) when the list is empty, so DarkRP's default applies.
			allowed = #SHIPMENT.allowed > 0 and teamsFromCommands(SHIPMENT.allowed) or nil,
		})
	end
end)
