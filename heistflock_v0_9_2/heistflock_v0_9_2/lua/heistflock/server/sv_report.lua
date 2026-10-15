-- The support report: everything needed to work out what's wrong, in plain
-- text, ready to paste to whoever is helping. Shown by Diagnostics' "Copy
-- report" button, and printed by the heistflock_report console command.
-- It holds no IP addresses or SteamIDs: only names, settings and counts.

local Config = HeistFlock.Config

-- Other addons Heist Flock works with or around, by the global each creates.
local OTHER_ADDONS = {
	{ "DarkRP", function() return DarkRP ~= nil end },
	{ "Realistic Police", function() return Realistic_Police ~= nil end },
	{ "VCMod", function() return VC ~= nil end },
	{ "simfphys", function() return simfphys ~= nil end },
	{ "LVS", function() return LVS ~= nil end },
	{ "Photon 2", function() return Photon2 ~= nil end },
	{ "ItemStore", function() return itemstore ~= nil end },
	{ "gProtect", function() return gProtect ~= nil end },
	{ "FPP (DarkRP prop protection)", function() return FPP ~= nil end },
}

local function yesNo(value) return value and "yes" or "no" end

local function valueText(value)
	if istable(value) then return "{" .. table.concat(value, ", ") .. "}" end
	return tostring(value)
end

-- ply: whose permissions to show (nil from the server console).
function HeistFlock.BuildReport(ply)
	local lines = {}
	local function add(text) table.insert(lines, text) end

	add("Heist Flock support report")
	add(string.format("Version %s  ·  map %s  ·  %d tick  ·  %d players  ·  %s", HeistFlock.Version, game.GetMap(),
		math.Round(1 / engine.TickInterval()), player.GetCount(), os.date("%Y-%m-%d %H:%M")))
	add("")

	-- Setup
	local provider = HeistFlock.GetActiveProvider()
	local providerText = provider.id
	if provider.id ~= Config.Parts.Provider then
		providerText = providerText .. " (chosen: " .. tostring(Config.Parts.Provider) .. ", not available)"
	end
	local hits = {}
	for _, stage in ipairs(Config.Stages) do table.insert(hits, stage.hits) end

	add("Mode: " .. Config.StripMode .. (Config.StripMode == "smash" and ("  ·  hits per stage " .. table.concat(hits, "/")) or ""))
	add("Parts go to: " .. providerText .. "  ·  on the ground: " .. #(HeistFlock.LooseParts or {}) .. "/" .. Config.Parts.MaxLoose)
	add("Bonus per camera: " .. Config.Payout .. "  ·  repair time: " .. Config.RepairTime .. "s")
	add("Plate scanning: " .. (Config.ALPR.Enabled and ("on, plates from " .. HeistFlock.PlateSource()) or "off")
		.. string.format("  ·  %s-target  ·  range %d, lens %d°, head turns %d°, every %.2gs",
			Config.ALPR.TargetMode == "single" and "single" or "multi", Config.ALPR.Range, Config.ALPR.FieldOfView,
			Config.ALPR.Swivel, Config.ALPR.ScanInterval))
	local scan = HeistFlock.ScanStats
	add(string.format("Scan cost: last %.2f ms, average %.2f ms, peak %.2f ms  ·  %d cameras reading, %d cars, %d checks, %d sight lines per scan",
		scan.lastMs, scan.averageMs, scan.peakMs, scan.cameras, scan.vehicles, scan.checks, scan.traces))
	add("Camera model: " .. (HeistFlock.UsesBuiltInModel() and "built-in" or Config.Model))

	local found = {}
	for _, other in ipairs(OTHER_ADDONS) do
		if other[2]() then table.insert(found, other[1]) end
	end
	add("Addons found: " .. (#found > 0 and table.concat(found, ", ") or "none"))
	add("")

	-- Permissions
	local permissions = HeistFlock.PermissionInfo(ply)
	add("Admin mod: " .. (#permissions.adminMods > 0 and table.concat(permissions.adminMods, ", ") or "none")
		.. "  ·  CAMI: " .. yesNo(permissions.cami) .. (permissions.camiVersion and (" v" .. permissions.camiVersion) or ""))
	local access = {}
	for _, privilege in ipairs(permissions.privileges) do
		table.insert(access, privilege.name .. " " .. (privilege.registered and "registered" or "NOT registered")
			.. (IsValid(ply) and (", you: " .. yesNo(privilege.yours)) or ""))
	end
	add("Permissions: " .. table.concat(access, "  ·  "))
	if not permissions.cami then
		add("No CAMI: menu limited to groups " .. valueText(permissions.fallbackGroups))
	end
	add("")

	-- Cameras
	local counts = { ready = 0, damaged = 0, stripped = 0, working = 0 }
	local cameras = ents.FindByClass("heistflock_camera")
	for _, cam in ipairs(cameras) do
		if cam:GetStage() >= #Config.Stages then
			counts.stripped = counts.stripped + 1
		elseif IsValid(cam:GetWorker()) then
			counts.working = counts.working + 1
		elseif cam:GetStage() > 0 or cam:GetHits() > 0 then
			counts.damaged = counts.damaged + 1
		else
			counts.ready = counts.ready + 1
		end
	end
	add(string.format("Cameras: %d (%d ready, %d damaged, %d being stripped, %d stripped)  ·  save file: %s", #cameras,
		counts.ready, counts.damaged, counts.working, counts.stripped, yesNo(file.Exists(HeistFlock.CameraSavePath(), "DATA"))))

	-- Settings changed from sh_config.lua / config.json
	local changed = HeistFlock.GetChangedSettings()
	local changedText = {}
	for id, value in SortedPairs(changed) do
		table.insert(changedText, id .. " = " .. valueText(value))
	end
	add("Changed in the menu: " .. (#changedText > 0 and table.concat(changedText, ", ") or "nothing"))
	add("config.json: " .. yesNo(file.Exists("heistflock/config.json", "DATA")))
	add("")

	-- Problems
	add("Warnings: " .. (#HeistFlock.Warnings == 0 and "none" or ""))
	for _, warning in ipairs(HeistFlock.Warnings) do
		add("  - " .. warning)
	end
	add("")

	-- Since the server started
	local stats = HeistFlock.Stats
	add(string.format("This session: %d cameras finished, %s paid, %d hits, %d parts picked up, %d alarms, %d plates read, %d plate hits",
		stats.camerasStripped or 0, HeistFlock.FormatMoney(stats.moneyPaid or 0), stats.hits or 0, stats.partsCollected or 0,
		stats.alarms or 0, stats.platesRead or 0, stats.alprHits or 0))
	add("")

	add("Recent events (oldest first):")
	if #HeistFlock.RecentLog == 0 then add("  none yet") end
	for _, entry in ipairs(HeistFlock.RecentLog) do
		add("  " .. os.date("%H:%M:%S", entry.time) .. "  " .. entry.text)
	end

	return table.concat(lines, "\n")
end

-- heistflock_report: prints the report (server console, or players with View).
concommand.Add("heistflock_report", function(ply)
	if IsValid(ply) and (not HeistFlock.RequireAccess(ply, "view") or HeistFlock.IsThrottled(ply, "report", 2)) then return end

	local report = HeistFlock.BuildReport(ply)
	if IsValid(ply) then
		-- Long text is split, since one console message can only be so long.
		for _, line in ipairs(string.Explode("\n", report)) do
			ply:PrintMessage(HUD_PRINTCONSOLE, line)
		end
		HeistFlock.Notify(ply, "Report printed to your console.")
	else
		print(report)
	end
end)
