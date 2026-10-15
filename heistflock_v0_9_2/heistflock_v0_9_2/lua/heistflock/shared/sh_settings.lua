-- The settings the in-game menu can change, plus helpers to read, check
-- and change them. Used by both server and client. Every setting can also
-- be set in garrysmod/data/heistflock/config.json by its id.
--
-- Each setting has:
--   id          unique name; also the key in HeistFlock.Config unless path is set
--   path        for nested values, e.g. { "SkillCheckTypes", "screws" }
--   stage       for per-stage values: which stage; field = "time" or "hits"
--   section     the group it's shown under in the menu
--   mode        "smash" or "steps": only shown in the menu in that strip mode
--   label       name shown in the menu
--   description shown when hovering the setting
--   type        "number", "bool", "string", "choice", "list" or "jobs"
--   min/max     limits for numbers,  unit = shown after the number
--   fallback    used when sh_config.lua has a broken value (otherwise min, false or "")

local Config = HeistFlock.Config
local settings = {}

local function add(setting)
	table.insert(settings, setting)
end

-- Stripping
add({ id = "StripMode", section = "Stripping", type = "choice",
	choices = { "smash", "steps" }, choiceLabels = { "Smash", "Hands-on steps" },
	label = "How cameras are stripped", description = "Smash: hit it with a crowbar or pliers, parts fall off. Steps: the timed stripping with steps on screen." })
add({ id = "RepairTime", fallback = 600, section = "Stripping", type = "number", min = 0, max = 86400, unit = "sec",
	label = "Repair time", description = "Until a stripped or damaged camera works again. 0 = never." })
add({ id = "MaxDistance", fallback = 100, section = "Stripping", type = "number", min = 32, max = 500, unit = "units",
	label = "Work distance", description = "How close players must stay (steps), and where the prompt shows. 100 is about arm's length." })

-- Payout
add({ id = "Payout", section = "Payout", type = "number", min = 0, max = 1000000, unit = "$",
	label = "Bonus per camera", description = "Smash: paid to whoever lands the final hit. Steps: paid when the last stage finishes." })
add({ id = "MakeWanted", section = "Payout", type = "bool",
	label = "Wanted when finished", description = "Roll for wanted status when a camera is finished off." })
add({ id = "WantedChance", fallback = 100, section = "Payout", type = "number", min = 0, max = 100, unit = "%",
	label = "Wanted chance", description = "Chance of becoming wanted when finishing a camera." })
add({ id = "WantedReason", fallback = "Stripping a Flock camera", section = "Payout", type = "string", maxLength = 100,
	label = "Wanted reason", description = "Shown to police in the wanted list." })

-- Smashing
for i in ipairs(Config.Stages) do
	add({ id = "Stage" .. i .. "Hits", fallback = 5, section = "Smashing", mode = "smash", type = "number", min = 1, max = 50, unit = "hits",
		stage = i, field = "hits", label = "Stage " .. i .. " hits", description = "" }) -- filled in by RefreshStageDescriptions
end
add({ id = "Smash_Tools", path = { "Smash", "Tools" }, section = "Smashing", mode = "smash", type = "list",
	label = "Tools", description = "Weapon classes whose melee hits count, separated by commas." })
add({ id = "Smash_AllowBullets", path = { "Smash", "AllowBullets" }, section = "Smashing", mode = "smash", type = "bool",
	label = "Bullets count", description = "On: shooting a camera counts as hits too." })
add({ id = "Smash_ExplosionsDestroy", path = { "Smash", "ExplosionsDestroy" }, section = "Smashing", mode = "smash", type = "bool",
	label = "Explosions destroy it", description = "On: one explosion finishes a camera and drops all its parts. Off: an explosion is one hit (with bullets on)." })
add({ id = "Smash_ExplosionMaxDistance", fallback = 600, path = { "Smash", "ExplosionMaxDistance" }, section = "Smashing", mode = "smash", type = "number", min = 0, max = 10000, unit = "units",
	label = "Blast range", description = "Explosions only count when the player who set them off is this close. 600 is about 11 m. 0 = any distance." })
add({ id = "Smash_AlarmChance", fallback = 10, path = { "Smash", "AlarmChance" }, section = "Smashing", mode = "smash", type = "number", min = 0, max = 100, unit = "%",
	label = "Alarm chance per hit", description = "Rolled on every hit until it goes off, so it adds up: 10% with the default 15 hits trips about 79% of cameras. See \"Roll once per camera\"." })
add({ id = "Smash_AlarmPerCamera", path = { "Smash", "AlarmPerCamera" }, section = "Smashing", mode = "smash", type = "bool",
	label = "Roll once per camera", description = "On: the alarm chance is rolled once, on the first hit, so 10% means 10% of cameras." })
add({ id = "Smash_AlarmOnFirstHit", path = { "Smash", "AlarmOnFirstHit" }, section = "Smashing", mode = "smash", type = "bool",
	label = "Alarm on first hit", description = "The first hit on a camera always trips its alarm." })
add({ id = "Smash_AlarmMakesWanted", path = { "Smash", "AlarmMakesWanted" }, section = "Smashing", mode = "smash", type = "bool",
	label = "Alarm makes wanted", description = "Whoever trips the alarm becomes wanted." })
add({ id = "Smash_PoliceAlert", path = { "Smash", "PoliceAlert" }, section = "Smashing", mode = "smash", type = "bool",
	label = "Tamper alert for police", description = "Police get a card and a marker when a camera's alarm goes off." })
add({ id = "Parts_Provider", fallback = "money", path = { "Parts", "Provider" }, section = "Smashing", type = "string", maxLength = 32,
	label = "Picked-up parts go to", description = "money (sold on the spot), hooks (your own addon), itemstore, or a provider another addon added." })
add({ id = "Parts_OwnerTime", fallback = 10, path = { "Parts", "OwnerTime" }, section = "Smashing", mode = "smash", type = "number", min = 0, max = 600, unit = "sec",
	label = "Parts reserved for", description = "Only whoever broke the stage can pick its parts up. After that anyone can. 0 = anyone right away." })
add({ id = "Parts_Lifetime", fallback = 120, path = { "Parts", "Lifetime" }, section = "Smashing", mode = "smash", type = "number", min = 10, max = 3600, unit = "sec",
	label = "Parts stay for", description = "Before a part on the ground disappears." })
add({ id = "Parts_MaxLoose", fallback = 60, path = { "Parts", "MaxLoose" }, section = "Smashing", mode = "smash", type = "number", min = 4, max = 300, unit = "parts",
	label = "Most parts on the ground", description = "Across the map. When there are more, the oldest go first." })
add({ id = "Parts_PoliceConfiscate", path = { "Parts", "PoliceConfiscate" }, section = "Smashing", mode = "smash", type = "bool",
	label = "Police confiscate parts", description = "Police pressing E on a part take it as evidence, for no money." })

-- Steps mode
for i in ipairs(Config.Stages) do
	add({ id = "Stage" .. i .. "Time", fallback = 10, section = "Hands-on steps", mode = "steps", type = "number", min = 1, max = 600, unit = "sec",
		stage = i, field = "time", label = "Stage " .. i .. " length", description = "" })
end
add({ id = "RequirePliers", section = "Hands-on steps", mode = "steps", type = "bool",
	label = "Require pliers", description = "Off: players can also strip cameras with bare hands." })
add({ id = "RequireHold", section = "Hands-on steps", mode = "steps", type = "bool",
	label = "Hold to work", description = "Off: press once, then stay close. On: hold the button the whole time." })
add({ id = "SkillChecks", section = "Hands-on steps", mode = "steps", type = "bool",
	label = "Steps on screen", description = "Hands-on steps while a camera is being stripped." })
add({ id = "SkillChecksPerCamera", fallback = 4, section = "Hands-on steps", mode = "steps", type = "number", min = 1, max = 8, unit = "steps",
	label = "Steps per camera", description = "Spread across the stages; longer stages get more." })
add({ id = "SkillCheckTime", fallback = 15, section = "Hands-on steps", mode = "steps", type = "number", min = 10, max = 60, unit = "sec",
	label = "Time limit", description = "To finish a step before it fails." })
add({ id = "FailRestartsStage", section = "Hands-on steps", mode = "steps", type = "bool",
	label = "Failing restarts the stage", description = "Off: the stage carries on after a failed step." })
add({ id = "FailMakesWanted", section = "Hands-on steps", mode = "steps", type = "bool",
	label = "Failing makes players wanted", description = "A failed step trips the camera's alarm." })

local CHECK_NAMES = {
	{ "screws", "Security screws", "Hold on each screw until it backs out." },
	{ "pry", "Pry the lid", "Lean on the bar, let go when the lid gives." },
	{ "battery", "Battery leads", "Unplug the leads in the order on the sticker." },
	{ "cable", "Wiring loom", "Snip the cable named on the work tag." },
	{ "board", "Modem board", "Rock the board out of its slot, gently." },
	{ "solder", "Gold contacts", "Keep the iron on the moving contact." },
}

-- Every step's id, for checking config files.
HeistFlock.CheckTypes = {}
for _, check in ipairs(CHECK_NAMES) do
	table.insert(HeistFlock.CheckTypes, check[1])
end

for _, check in ipairs(CHECK_NAMES) do
	add({ id = "Check_" .. check[1], path = { "SkillCheckTypes", check[1] }, section = "Which steps", mode = "steps",
		type = "bool", label = check[2], description = check[3] })
end

-- Plate scanning
add({ id = "ALPR_Enabled", path = { "ALPR", "Enabled" }, section = "Plate scanning", type = "bool",
	label = "Plate scanning", description = "Working cameras read plates and alert police about wanted players' vehicles." })
add({ id = "ALPR_TargetMode", path = { "ALPR", "TargetMode" }, section = "Plate scanning", type = "choice",
	choices = { "multi", "single" }, choiceLabels = { "Multi-target", "Single-target" },
	label = "Targeting mode", description = "Multi-target: reads every car in its whole sweep. Single-target: reads only the car its head is following, taking turns between cars in view every few seconds, so players can see what it's reading." })
add({ id = "ALPR_Range", fallback = 1500, path = { "ALPR", "Range" }, section = "Plate scanning", type = "number", min = 200, max = 6000, unit = "units",
	label = "Read range", description = "How far a camera reads plates. 1500 is about 28 m." })
add({ id = "ALPR_FieldOfView", fallback = 70, path = { "ALPR", "FieldOfView" }, section = "Plate scanning", type = "number", min = 10, max = 180, unit = "deg",
	label = "Field of view", description = "How wide each camera's lens sees." })
add({ id = "ALPR_Swivel", fallback = 30, path = { "ALPR", "Swivel" }, section = "Plate scanning", type = "number", min = 0, max = 90, unit = "deg",
	label = "Head turns", description = "How far the head turns each way to follow a car. Adds to the field of view. 0 = fixed." })
add({ id = "ALPR_AlertCooldown", fallback = 90, path = { "ALPR", "AlertCooldown" }, section = "Plate scanning", type = "number", min = 10, max = 3600, unit = "sec",
	label = "Alert cooldown", description = "Before the same vehicle is reported to police again." })
add({ id = "ALPR_HighlightTime", fallback = 60, path = { "ALPR", "HighlightTime" }, section = "Plate scanning", type = "number", min = 5, max = 600, unit = "sec",
	label = "Highlight time", description = "How long police see a flagged vehicle highlighted." })
add({ id = "ALPR_IncludeWarrants", path = { "ALPR", "IncludeWarrants" }, section = "Plate scanning", type = "bool",
	label = "Report warrants too", description = "Also flag vehicles of players with a search warrant." })
add({ id = "ALPR_AnyDamageBlinds", path = { "ALPR", "AnyDamageBlinds" }, section = "Plate scanning", type = "bool",
	label = "Any damage blinds it", description = "On: a camera stops scanning from the first hit. Off: only once fully stripped." })

-- Access
add({ id = "JobMode", section = "Access", type = "choice",
	choices = { "blacklist", "whitelist" }, choiceLabels = { "All except listed", "Only listed" },
	label = "Job list", description = "Which jobs can strip cameras. Pick them on the Access page." })
add({ id = "BlockPolice", section = "Access", type = "bool",
	label = "Block government jobs", description = "Police, chief and mayor can never strip cameras." })

-- Camera
add({ id = "Model", section = "Camera", type = "string", maxLength = 200,
	label = "Custom model", description = "Leave blank for the built-in Flock camera." })

-- Advanced
add({ id = "Debug", section = "Advanced", type = "bool",
	label = "Debug logging", description = "Print every stage, hit, step and payout to the server console." })
add({ id = "ManagerGroups", section = "Advanced", type = "list",
	label = "Groups with access (no admin mod)", description = "Only used when the server has no admin mod and no CAMI. Separated by commas." })

-- Edited on the Access page, not the Settings page.
add({ id = "Jobs", section = "Access", type = "jobs", label = "Job list" })

HeistFlock.Settings = settings

-- Stage settings describe their stage by name. Names can change after this
-- file loads (config.json on the server, then sent to players), so this runs
-- again whenever they do.
function HeistFlock.RefreshStageDescriptions()
	for _, setting in ipairs(settings) do
		if setting.stage then
			local stage = Config.Stages[setting.stage]
			setting.description = stage and (stage.name .. ".") or ""
		end
	end
end

HeistFlock.RefreshStageDescriptions()

function HeistFlock.FindSetting(id)
	for _, setting in ipairs(settings) do
		if setting.id == id then return setting end
	end
end

function HeistFlock.GetSetting(setting)
	if setting.stage then
		return Config.Stages[setting.stage][setting.field]
	end
	if setting.path then
		return Config[setting.path[1]][setting.path[2]]
	end
	return Config[setting.id]
end

function HeistFlock.SetSetting(setting, value)
	if setting.stage then
		Config.Stages[setting.stage][setting.field] = value
	elseif setting.path then
		Config[setting.path[1]][setting.path[2]] = value
	else
		Config[setting.id] = value
	end
end

-- Returns a safe version of the value, or nil if it can't be used.
function HeistFlock.CleanValue(setting, value)
	if setting.type == "number" then
		value = tonumber(value)
		if not value or value ~= value then return nil end -- value ~= value catches NaN
		return math.Clamp(math.Round(value), setting.min, setting.max)

	elseif setting.type == "bool" then
		if isbool(value) then return value end

	elseif setting.type == "string" then
		if isstring(value) then return string.Trim(string.sub(value, 1, setting.maxLength)) end

	elseif setting.type == "choice" then
		if table.HasValue(setting.choices, value) then return value end

	elseif setting.type == "jobs" then
		if not istable(value) then return nil end
		local jobs = {}
		for _, job in ipairs(value) do
			if isstring(job) and job ~= "" then
				table.insert(jobs, string.sub(job, 1, 64))
			end
		end
		return jobs

	elseif setting.type == "list" then
		-- Names like weapon classes and user groups: letters, digits, _ - .
		if not istable(value) then return nil end
		local list, seen = {}, {}
		for _, entry in ipairs(value) do
			if isstring(entry) then
				entry = string.lower(string.Trim(entry))
				if entry ~= "" and #entry <= 64 and not string.find(entry, "[^%w_%-%.]") and not seen[entry] then
					seen[entry] = true
					table.insert(list, entry)
				end
			end
			if #list >= 32 then break end
		end
		return list
	end

	return nil
end

-- Every setting's current value, keyed by id. Safe to send or save.
function HeistFlock.GetValues()
	local values = {}
	for _, setting in ipairs(settings) do
		local value = HeistFlock.GetSetting(setting)
		values[setting.id] = istable(value) and table.Copy(value) or value
	end
	return values
end

-- Applies a table of { id = value }, skipping anything invalid.
function HeistFlock.ApplyValues(values)
	for _, setting in ipairs(settings) do
		local cleaned = HeistFlock.CleanValue(setting, values[setting.id])
		if cleaned ~= nil then
			HeistFlock.SetSetting(setting, cleaned)
		end
	end
end
