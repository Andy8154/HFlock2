-- Loads, saves and shares the settings changed in the in-game menu.
-- Saved settings live in garrysmod/data/heistflock/settings.json
-- and override the defaults in sh_config.lua.

util.AddNetworkString("HeistFlock_RequestConfig")
util.AddNetworkString("HeistFlock_SyncConfig")
util.AddNetworkString("HeistFlock_ChangeSettings")
util.AddNetworkString("HeistFlock_ResetSettings")

local Config = HeistFlock.Config
local SETTINGS_PATH = "heistflock/settings.json"

HeistFlock.SettingsPath = SETTINGS_PATH
HeistFlock.Warnings = {}

-- A problem worth fixing: printed to the console and shown on the Debug page.
function HeistFlock.Warn(message)
	if table.HasValue(HeistFlock.Warnings, message) then return end -- e.g. again after a map cleanup
	table.insert(HeistFlock.Warnings, message)
	print("[HeistFlock] Warning: " .. message)
end

local warn = HeistFlock.Warn

-- A safe value to use when sh_config.lua has a broken one.
local function fallbackValue(setting)
	if setting.fallback ~= nil then return setting.fallback end
	if setting.type == "number" then return setting.min end
	if setting.type == "bool" then return false end
	if setting.type == "string" then return "" end
	if setting.type == "choice" then return setting.choices[1] end
	if setting.type == "jobs" or setting.type == "list" then return {} end
end

-- 0. Optional overrides from garrysmod/data/heistflock/config.json, for
--    installs (like the Workshop) where sh_config.lua can't be edited.
--    They become the new defaults, so "Reset to defaults" goes back to them.
local OVERRIDE_PATH = "heistflock/config.json"
local EXAMPLE_PATH = "heistflock/config.example.json"

-- Overrides players also need (language, font, stage names), sent with the settings.
HeistFlock.SharedOverrides = {}

local EXAMPLE = [[
{
	"_help": "Copy this file to config.json in the same folder and change what you need. Delete any line you don't want to override. Restart the map after editing.",
	"Language": "en",
	"FontOverride": "",
	"StripMode": "smash",
	"Payout": 0,
	"RepairTime": 600,
	"Smash_Tools": ["heistflock_pliers", "weapon_crowbar"],
	"Smash_AllowBullets": false,
	"Smash_ExplosionsDestroy": true,
	"Smash_ExplosionMaxDistance": 600,
	"Smash_AlarmPerCamera": false,
	"Smash_AlarmChance": 10,
	"Smash_AlarmOnFirstHit": false,
	"Smash_AlarmMakesWanted": true,
	"Smash_PoliceAlert": false,
	"Parts_Provider": "money",
	"Parts_OwnerTime": 10,
	"Parts_Lifetime": 120,
	"Parts_MaxLoose": 60,
	"ManagerGroups": ["superadmin"],
	"SkillChecksPerCamera": 4,
	"Check_solder": true,
	"ALPR_Enabled": true,
	"ALPR_TargetMode": "multi",
	"ALPR_Range": 1500,
	"Stages": [
		{ "hits": 4, "time": 11, "name": "Opening the housing", "scrap": 2, "checks": ["screws", "pry"], "loot": [ ["camera_lens", 1, 1], ["scrap_metal", 1, 2] ] },
		{ "hits": 5, "time": 11, "name": "Cutting the power", "scrap": 3, "checks": ["battery", "cable"], "loot": [ ["copper_wire", 2, 4], ["scrap_metal", 1, 2] ] },
		{ "hits": 6, "time": 13, "name": "Pulling the board and gold", "scrap": 4, "checks": ["board", "solder"], "loot": [ ["circuit_board", 1, 1], ["gold_contacts", 1, 3], ["solar_cell", 0, 1] ] }
	],
	"Crafting": { "Enabled": false, "ReplacePayout": false }
}
]]

-- A loot table: { { material, min, max }, ... }. Only the shape is checked
-- here: another addon may register its materials after this file loads.
-- Unknown materials are reported once everything has loaded (and are never
-- dropped).
local function cleanLoot(loot)
	local cleaned = {}
	for _, entry in ipairs(loot) do
		if istable(entry) and isstring(entry[1]) and entry[1] ~= "" then
			local low = math.Clamp(math.Round(tonumber(entry[2]) or 1), 0, 100)
			local high = math.Clamp(math.Round(tonumber(entry[3]) or low), low, 100)
			table.insert(cleaned, { entry[1], low, high })
		end
	end
	return cleaned
end

local function applyFileOverrides()
	local json = file.Read(OVERRIDE_PATH, "DATA")
	if not json then
		if not file.Exists(EXAMPLE_PATH, "DATA") then
			file.CreateDir("heistflock")
			file.Write(EXAMPLE_PATH, EXAMPLE)
		end
		return
	end

	local overrides = util.JSONToTable(json)
	if not istable(overrides) then
		warn("config.json is damaged (check the JSON) and was ignored.")
		return
	end

	local shared = HeistFlock.SharedOverrides

	if overrides.Language ~= nil then
		if isstring(overrides.Language) and HeistFlock.Languages[overrides.Language] then
			Config.Language = overrides.Language
			shared.Language = overrides.Language
		else
			warn("config.json: unknown Language " .. tostring(overrides.Language) .. ".")
		end
	end

	if isstring(overrides.FontOverride) then
		Config.FontOverride = string.sub(overrides.FontOverride, 1, 31) -- Garry's Mod's font name limit
		shared.FontOverride = Config.FontOverride
	end

	-- Stages: change the existing ones. How many there are is set in sh_config.lua.
	if istable(overrides.Stages) then
		shared.StageNames = {}
		for i, stage in ipairs(Config.Stages) do
			local changes = overrides.Stages[i]
			if istable(changes) then
				if isnumber(changes.time) then stage.time = math.Clamp(math.Round(changes.time), 1, 600) end
				if isnumber(changes.hits) then stage.hits = math.Clamp(math.Round(changes.hits), 1, 50) end
				if isstring(changes.name) then stage.name = string.sub(changes.name, 1, 60) end
				if isnumber(changes.scrap) then stage.scrap = math.Clamp(math.Round(changes.scrap), 0, 10) end
				if istable(changes.loot) then stage.loot = cleanLoot(changes.loot) end
				if istable(changes.checks) then stage.checks = changes.checks end -- checked below
			end
			shared.StageNames[i] = stage.name
		end
	end

	if istable(overrides.Crafting) then
		local crafting = overrides.Crafting
		if isbool(crafting.Enabled) then Config.Crafting.Enabled = crafting.Enabled end
		if isbool(crafting.ReplacePayout) then Config.Crafting.ReplacePayout = crafting.ReplacePayout end
		if isstring(crafting.Provider) then
			-- Moved to Parts_Provider in 0.8.0; still read here so old files keep working.
			Config.Parts.Provider = crafting.Provider
		end
	end

	if overrides.DarkRP ~= nil then
		warn("config.json: DarkRP switches only work in sh_config.lua (jobs must be the same on the server and every player).")
	end

	-- Anything else the menu can change, by its id (e.g. "Payout", "Check_solder").
	for _, setting in ipairs(HeistFlock.Settings) do
		local value = overrides[setting.id]
		if value ~= nil then
			local cleaned = HeistFlock.CleanValue(setting, value)
			if cleaned == nil then
				warn("config.json: invalid value for " .. setting.id .. ".")
			else
				HeistFlock.SetSetting(setting, cleaned)
			end
		end
	end

	print("[HeistFlock] Loaded overrides from garrysmod/data/" .. OVERRIDE_PATH)
end

applyFileOverrides()
HeistFlock.RefreshStageDescriptions() -- config.json may have renamed stages

-- Every stage, from sh_config.lua or config.json: known steps only, each
-- once, and hits and time set.
for i, stage in ipairs(Config.Stages) do
	local cleaned, seen = {}, {}
	for _, checkType in ipairs(istable(stage.checks) and stage.checks or {}) do
		if not table.HasValue(HeistFlock.CheckTypes, checkType) then
			warn("Stage " .. i .. " lists an unknown step \"" .. tostring(checkType) .. "\"; it was skipped.")
		elseif not seen[checkType] then
			seen[checkType] = true
			table.insert(cleaned, checkType)
		end
	end
	stage.checks = cleaned

	stage.loot = cleanLoot(istable(stage.loot) and stage.loot or {})
end

hook.Add("InitPostEntity", "HeistFlock_CheckLoot", function()
	for i, stage in ipairs(Config.Stages) do
		for _, entry in ipairs(stage.loot) do
			if not HeistFlock.GetMaterial(entry[1]) then
				warn("Stage " .. i .. " drops an unknown material \"" .. entry[1] .. "\"; it's skipped. Materials are in sh_materials.lua.")
			end
		end
	end
end)

-- Values that aren't menu settings, checked here so a typo in
-- sh_config.lua can't break the addon. { table, key, low, high, default }
local NUMBERS = {
	{ Config.Smash, "HitDelay", 0.1, 5, 0.35, "Smash.HitDelay" },
	{ Config.ALPR, "ScanInterval", 0.25, 10, 1, "ALPR.ScanInterval" },
}
for _, check in ipairs(NUMBERS) do
	local value = check[1][check[2]]
	if not isnumber(value) or value ~= value then
		warn(check[6] .. " in sh_config.lua isn't a number. Using " .. check[5] .. ".")
		check[1][check[2]] = check[5]
	else
		check[1][check[2]] = math.Clamp(value, check[3], check[4])
	end
end

local TEXTS = {
	{ Config.Smash, "AlarmWantedReason", "Smashing a Flock camera" },
	{ Config, "FailWantedReason", "Tripped a Flock camera alarm" },
}
for _, check in ipairs(TEXTS) do
	if not isstring(check[1][check[2]]) then check[1][check[2]] = check[3] end
end

if #HeistFlock.FilledConfig > 0 then
	warn("sh_config.lua is from an older version and is missing: " .. table.concat(HeistFlock.FilledConfig, ", ")
		.. ". Defaults are used. Copy those parts from the new sh_config.lua to change them.")
end

-- 1. Check the defaults from sh_config.lua and remember them.
for _, setting in ipairs(HeistFlock.Settings) do
	local cleaned = HeistFlock.CleanValue(setting, HeistFlock.GetSetting(setting))

	if cleaned == nil then
		warn(setting.id .. " in sh_config.lua is invalid. Using " .. tostring(fallbackValue(setting)) .. ".")
		cleaned = fallbackValue(setting)
	end

	HeistFlock.SetSetting(setting, cleaned)
end

HeistFlock.Defaults = HeistFlock.GetValues()

-- 2. Apply anything saved from the in-game menu.
local function loadSavedSettings()
	local json = file.Read(SETTINGS_PATH, "DATA")
	if not json then return end

	local saved = util.JSONToTable(json)
	if not saved then
		warn("settings.json is damaged and was ignored.")
		return
	end

	for _, setting in ipairs(HeistFlock.Settings) do
		if saved[setting.id] ~= nil then
			local cleaned = HeistFlock.CleanValue(setting, saved[setting.id])

			if cleaned == nil then
				warn("Ignored an invalid saved value for " .. setting.id .. ".")
			else
				HeistFlock.SetSetting(setting, cleaned)
			end
		end
	end
end

loadSavedSettings()

-- 3. With every source loaded (sh_config.lua, config.json, settings.json),
--    make sure the camera model exists. A missing one falls back to the
--    built-in camera instead of spawning error models, and the defaults are
--    fixed too so "Reset to defaults" can't bring the bad path back.
if Config.Model ~= "" and not util.IsValidModel(Config.Model) then
	warn("Camera model " .. Config.Model .. " wasn't found on the server. Using the built-in camera instead.")
	Config.Model = ""
end
if HeistFlock.Defaults.Model ~= "" and not util.IsValidModel(HeistFlock.Defaults.Model) then
	HeistFlock.Defaults.Model = ""
end

-- The settings that differ from the defaults (sh_config.lua plus config.json).
-- Only these are saved, so editing those files still works for every setting
-- nobody has changed in the menu.
local function getChangedValues() -- also HeistFlock.GetChangedSettings
	local changed = {}
	for id, value in pairs(HeistFlock.GetValues()) do
		local default = HeistFlock.Defaults[id]
		local same = istable(value) and istable(default)
			and table.concat(value, ",") == table.concat(default, ",")
			or value == default
		if not same then changed[id] = value end
	end
	return changed
end

function HeistFlock.WriteSavedSettings()
	local changed = getChangedValues()
	HeistFlock.ChangedSettingsCount = table.Count(changed)

	if HeistFlock.ChangedSettingsCount == 0 then
		file.Delete(SETTINGS_PATH)
		return
	end

	file.CreateDir("heistflock")
	file.Write(SETTINGS_PATH, util.TableToJSON(changed, true))
end

HeistFlock.ChangedSettingsCount = table.Count(getChangedValues())
HeistFlock.GetChangedSettings = getChangedValues

-- Sending settings to players
function HeistFlock.SyncConfig(target)
	net.Start("HeistFlock_SyncConfig")
	net.WriteTable(HeistFlock.GetValues())
	net.WriteTable(HeistFlock.SharedOverrides)

	if target then
		net.Send(target)
	else
		net.Broadcast()
	end
end

-- Each player asks once, after their game has fully loaded.
net.Receive("HeistFlock_RequestConfig", function(len, ply)
	if ply.HeistFlockHasConfig then return end
	ply.HeistFlockHasConfig = true

	HeistFlock.SyncConfig(ply)
end)

local function onSettingsChanged(oldMode)
	HeistFlock.SyncConfig()
	hook.Run("HeistFlock_SettingsChanged")

	for _, cam in ipairs(ents.FindByClass("heistflock_camera")) do
		-- Switched modes: nobody keeps working the old way, and smash hits
		-- on the current stage don't carry over (they'd keep it blind).
		if oldMode ~= Config.StripMode then
			cam:StopWorking()
			cam:SetHits(0)
		end
		cam:UpdateLook() -- pick up a new model straight away
	end
end

local function valueToText(value)
	if istable(value) then
		return "{" .. table.concat(value, ", ") .. "}"
	end
	return tostring(value)
end

net.Receive("HeistFlock_ChangeSettings", function(len, ply)
	if not HeistFlock.RequireAccess(ply, "manage") then return end
	if HeistFlock.IsThrottled(ply, "settings", 0.5) then
		HeistFlock.Notify(ply, "Slow down: settings weren't saved. Try again.", true)
		return
	end

	local changes = net.ReadTable()
	local changedCount = 0
	local oldMode = Config.StripMode

	-- At most one value per setting; anything bigger isn't from the menu.
	if not istable(changes) or table.Count(changes) > #HeistFlock.Settings then return end
	local rejected = {}

	for id, value in pairs(changes) do
		local setting = isstring(id) and HeistFlock.FindSetting(id)
		local cleaned = setting and HeistFlock.CleanValue(setting, value)

		if cleaned ~= nil and id == "Model" and cleaned ~= "" and not util.IsValidModel(cleaned) then
			cleaned = nil
		end

		if cleaned == nil then
			table.insert(rejected, tostring(id))
		else
			HeistFlock.SetSetting(setting, cleaned)
			changedCount = changedCount + 1
			print("[HeistFlock] " .. ply:Nick() .. " set " .. id .. " to " .. valueToText(cleaned))
		end
	end

	if changedCount > 0 then
		HeistFlock.WriteSavedSettings()
		onSettingsChanged(oldMode)
		HeistFlock.Notify(ply, "Saved " .. changedCount .. " setting(s).")
		HeistFlock.AdminLog(ply, "changed " .. changedCount .. " Heist Flock setting(s)")
	end

	if #rejected > 0 then
		HeistFlock.Notify(ply, "Invalid value for: " .. table.concat(rejected, ", "), true)
	end
end)

net.Receive("HeistFlock_ResetSettings", function(len, ply)
	if not HeistFlock.RequireAccess(ply, "manage") then return end
	if HeistFlock.IsThrottled(ply, "settings", 0.5) then return end

	local oldMode = Config.StripMode
	file.Delete(SETTINGS_PATH)
	HeistFlock.ApplyValues(HeistFlock.Defaults)
	HeistFlock.ChangedSettingsCount = 0
	onSettingsChanged(oldMode)

	HeistFlock.AdminLog(ply, "reset all Heist Flock settings to defaults")
	HeistFlock.Notify(ply, "All settings reset to the defaults in sh_config.lua.")
end)
