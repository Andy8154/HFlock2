--[[-------------------------------------------------------------------------
	HEIST FLOCK - CONFIGURATION

	Most of these can also be changed in-game: type !heistflock in chat.
	Changes made in-game are saved to garrysmod/data/heistflock/settings.json
	and take priority over this file. Use "Reset to defaults" in the menu
	to go back to the values below.

	Can't edit this file (e.g. installed from the Workshop)? Put your changes
	in garrysmod/data/heistflock/config.json instead. The server writes an
	example next to it, config.example.json, the first time it starts.

	GIVING STAFF ACCESS
	Heist Flock adds three permissions to your admin mod:
		HeistFlock Manage  settings and the whole menu        (superadmin by default)
		HeistFlock Place   place, move, remove, reset cameras (superadmin by default)
		HeistFlock View    see cameras and Diagnostics        (admin by default)
	Manage includes the other two.
		ULX:     ulx groupallow admin "HeistFlock Place"
		SAM:     the Permissions page in SAM's menu
		FAdmin:  the privileges settings in FAdmin's menu
		Other admin mods that use CAMI (sAdmin, xAdmin, ServerGuard...) list
		them with their other permissions.
	No admin mod at all? Then only Config.ManagerGroups (below) can use the
	menu. More in lua/heistflock/permissions_guide.lua.

	SOMETHING NOT WORKING?
	!heistflock, Diagnostics, then "Copy report" and paste it to whoever is
	helping you. From the server console: heistflock_report. Turn on
	"Debug logging" there to also print every event to the server console.
---------------------------------------------------------------------------]]

local Config = {}
HeistFlock.Config = Config


--[[ GENERAL ]]-------------------------------------------------------------

-- Language for everything players see. Available: "en"
-- Add your own in lua/heistflock/shared/sh_language.lua.
Config.Language = "en"

-- The bundled fonts cover Latin (most European accented letters), Greek and
-- Cyrillic. For anything else (Vietnamese, Chinese, Japanese, Korean,
-- Arabic...) set a font your players have, e.g. "Microsoft YaHei" or
-- "Segoe UI" (31 characters at most). Blank = bundled fonts.
Config.FontOverride = ""

-- Print every stage, hit, skill check and payout to the server console.
Config.Debug = false

-- Only used when the server has no admin mod and no CAMI at all: these
-- user groups get full access to the menu.
Config.ManagerGroups = { "superadmin" }


--[[ CAMERA ]]--------------------------------------------------------------

-- Leave blank for the built-in Flock camera: a pole with a camera head and
-- a solar panel that visibly comes apart each stage.
-- Or set your own model, e.g. "models/yourpack/flock_camera.mdl".
Config.Model = ""

-- Seconds until a stripped camera works again. 0 = stays broken until restart.
Config.RepairTime = 600

-- Only used with a custom model: how it looks after each stage.
-- color = tint, tilt = degrees it droops, model = swap to another model.
Config.Looks = {
	[0] = { color = Color(255, 255, 255), tilt = 0 },
	[1] = { color = Color(205, 205, 205), tilt = 8 },
	[2] = { color = Color(150, 140, 130), tilt = 20 },
	[3] = { color = Color(70, 65, 60),    tilt = 40 },
}

-- Scrap that flies off when a stage finishes.
Config.ScrapModels = {
	"models/gibs/metal_gib1.mdl",
	"models/gibs/metal_gib2.mdl",
	"models/gibs/metal_gib3.mdl",
	"models/gibs/metal_gib4.mdl",
	"models/gibs/metal_gib5.mdl",
}


--[[ STRIPPING ]]-----------------------------------------------------------

-- How cameras get taken apart:
--   "smash" = hit the camera with a crowbar or the pliers. Each stage takes
--             a number of hits, and the parts fall off as items to pick up.
--   "steps" = the older way: stand at the camera while a timer runs, with
--             hands-on steps on screen (see SKILL CHECKS).
Config.StripMode = "smash"

-- The stages, in order.
--   hits   = hits it takes (smash mode)
--   time   = seconds of work (steps mode)
--   name   = what this stage is called on screen
--   scrap  = pieces of scrap that fly off when it breaks (just for looks)
--   checks = which hands-on steps can come up during it (steps mode, see
--            SKILL CHECKS). If every step in a stage's list is turned off,
--            that stage has no steps, and its share goes to the other stages.
--   loot   = the parts it drops: { material, fewest, most }. Materials are
--            in lua/heistflock/shared/sh_materials.lua.
Config.Stages = {
	{ hits = 4, time = 11, name = "Opening the housing", scrap = 2,
		checks = { "screws", "pry" },
		loot = { { "camera_lens", 1, 1 }, { "scrap_metal", 1, 2 } } },
	{ hits = 5, time = 11, name = "Cutting the power", scrap = 3,
		checks = { "battery", "cable" },
		loot = { { "copper_wire", 2, 4 }, { "scrap_metal", 1, 2 } } },
	{ hits = 6, time = 13, name = "Pulling the board and gold", scrap = 4,
		checks = { "board", "solder" },
		loot = { { "circuit_board", 1, 1 }, { "gold_contacts", 1, 3 }, { "solar_cell", 0, 1 } } },
}

-- Smash mode: a bonus for whoever lands the final hit. The parts are the
-- main income, so this is 0 by default.
-- Steps mode: paid the moment the last stage finishes. Set it (e.g. 1000)
-- if you use steps mode without crafting, or players earn nothing.
Config.Payout = 0

-- Steps mode: players need the pliers weapon (heistflock_pliers).
-- false = they can also use bare hands (press E).
Config.RequirePliers = true

-- Steps mode: false = press once to start, then stay close (walk away to stop).
--             true  = hold the button the whole time.
Config.RequireHold = false

-- How close players must stay while working (steps mode), and how close
-- the prompt above a camera shows up, in units. 100 is about arm's length.
Config.MaxDistance = 100


--[[ SMASHING ]]------------------------------------------------------------

Config.Smash = {
	-- Weapons that count as hits, by class. Only their melee hits count
	-- (club or slash damage), not anything else they do.
	Tools = { "heistflock_pliers", "weapon_crowbar" },

	-- true = bullets from any weapon count as hits too.
	AllowBullets = false,

	-- true = one explosion (grenade, C4, RPG...) finishes the camera at once,
	-- dropping every remaining stage's parts. false = explosions count as
	-- one hit, and only with AllowBullets on.
	ExplosionsDestroy = true,

	-- Explosions only count when the player who set them off is this close
	-- to the camera, in units (600 is about 11 m). 0 = any distance.
	ExplosionMaxDistance = 600,

	-- The fastest one player can land hits, in seconds. Stops autoclickers.
	HitDelay = 0.35,

	-- Percent chance each hit trips the camera's alarm. Once it has gone
	-- off, it doesn't roll again until the camera is repaired.
	AlarmChance = 10,
	-- AlarmChance is rolled on every hit, so it adds up: at 10% with the
	-- default 15 hits, about 79% of cameras trip it. true = roll it only
	-- once per camera, on the first hit (then 10% means 10% of cameras).
	AlarmPerCamera = false,
	AlarmOnFirstHit = false, -- true = the first hit always trips it
	AlarmMakesWanted = true, -- the player whose hit tripped it becomes wanted
	AlarmWantedReason = "Smashing a Flock camera",

	-- Send police a "camera tampered" alert with a marker when the alarm
	-- goes off.
	PoliceAlert = false,
}

-- The parts that fall off.
Config.Parts = {
	-- Where a picked-up part goes:
	--   "money"     sold on the spot for its value (no inventory addon needed)
	--   "hooks"     only the HeistFlock_GiveMaterial hook, for your own
	--               crafting or inventory addon (see hooks_reference.lua)
	--   "itemstore" ItemStore inventory, if installed (see providers/itemstore.lua)
	Provider = "money",

	-- Seconds only the player who broke the stage can pick its parts up.
	-- After that anyone can, so parts can be stolen. 0 = anyone right away.
	OwnerTime = 10,

	Lifetime = 120,         -- seconds before a part on the ground disappears
	MaxLoose = 60,          -- most parts on the ground at once; the oldest go first
	PoliceConfiscate = true, -- police pressing E on a part take it as evidence (no money)
}

-- Placeholder models for the pliers until custom ones are made.
Config.PliersViewModel  = "models/weapons/c_crowbar.mdl"
Config.PliersWorldModel = "models/weapons/w_crowbar.mdl"


--[[ SKILL CHECKS ]]--------------------------------------------------------

-- Steps mode only. Hands-on steps that pop up while a camera is being
-- stripped, each one a real part of taking it apart. Every step explains
-- itself on screen.
Config.SkillChecks = true

-- How many per camera. They're spread across the stages, with longer
-- stages getting more, and each stage picks from its own "checks" list.
Config.SkillChecksPerCamera = 4

-- Seconds to finish a step before the tamper alarm goes off (10 to 60).
Config.SkillCheckTime = 15

-- Turn individual steps on or off.
Config.SkillCheckTypes = {
	screws  = true, -- hold on each security screw until it backs out
	pry     = true, -- lean on the pry bar, let go when the lid gives
	battery = true, -- unplug the battery leads in the order on the sticker
	cable   = true, -- snip the cable named on the work tag
	board   = true, -- rock the modem board out of its slot, gently
	solder  = true, -- keep the iron on the moving gold contact
}

-- Failing a check (wrong answer, too slow or giving up):
Config.FailRestartsStage = true -- restart the current stage
Config.FailMakesWanted   = true -- trip the alarm and make the player wanted
Config.FailWantedReason  = "Tripped a Flock camera alarm"


--[[ WHO CAN STRIP CAMERAS ]]-----------------------------------------------

-- "blacklist" = every job except the ones listed
-- "whitelist" = only the jobs listed
Config.JobMode = "blacklist"

-- Jobs by their command (e.g. "thief") or name (e.g. "Thief").
-- Easier to set in-game on the Access page.
Config.Jobs = {}

-- Police, the police chief and the mayor can never strip cameras.
Config.BlockPolice = false


--[[ WANTED ]]--------------------------------------------------------------

-- Roll for wanted status when a camera is finished (the final hit in smash
-- mode, the last stage in steps mode).
Config.MakeWanted   = true
Config.WantedChance = 100 -- percent
Config.WantedReason = "Stripping a Flock camera"


--[[ PLATE SCANNING (ALPR) ]]-----------------------------------------------

-- Working cameras read the plates of vehicles in front of them. When the
-- owner or driver is wanted, police get an alert and the vehicle is
-- highlighted for them. With Realistic Police installed, cameras read the
-- same plates police see; otherwise each vehicle gets its own plate.
Config.ALPR = {
	Enabled = true,
	TargetMode = "multi", -- "multi" reads every eligible vehicle in the full sweep; "single" reads only the vehicle being tracked
	Range = 1500,          -- how far a camera reads plates, in units (1500 is about 28 m)
	FieldOfView = 70,      -- how wide the lens sees, in degrees
	Swivel = 30,           -- how far the head turns each way to follow a car, in degrees (0 = fixed).
	                       -- A camera covers FieldOfView / 2 + Swivel degrees either side.
	ScanInterval = 1,      -- seconds between scans
	AlertCooldown = 90,    -- seconds before the same vehicle is reported again
	HighlightTime = 60,    -- seconds police see the vehicle highlighted
	IncludeWarrants = false, -- also report players with a search warrant
	AnyDamageBlinds = true,  -- true: a camera stops scanning from the first hit (or once stripping starts)
	                         -- false: it only stops once fully stripped
}


--[[ DARKRP ]]--------------------------------------------------------------

-- Add a "Camera Stripper" job (spawns with pliers) and a pliers shipment,
-- without editing darkrpmodification. Leave off if you already added them
-- there yourself, or you'll get them twice. Job details are in
-- lua/darkrp_modules/heistflock/sh_heistflock.lua.
Config.DarkRP = {
	AddJob = false,
	AddShipment = false,
}


--[[ CRAFTING (STEPS MODE) ]]-----------------------------------------------

-- Steps mode only (smash mode always drops parts). When enabled, each
-- finished stage hands its "loot" straight to Config.Parts.Provider.
-- See lua/heistflock/crafting_guide.lua.
Config.Crafting = {
	Enabled = false,

	-- true = materials replace the flat payout above. false = players get both.
	ReplacePayout = false,
}
