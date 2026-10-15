--[[-------------------------------------------------------------------------
	HEIST FLOCK - LANGUAGE

	Every message players see. To translate, copy the "en" block, change
	"en" to your language code, translate the right-hand side, then set
	Config.Language in sh_config.lua. Keep {words in braces} as they are:
	they're filled in by the addon.
---------------------------------------------------------------------------]]

HeistFlock.Languages = HeistFlock.Languages or {}

HeistFlock.Languages.en = {
	-- Messages
	already_stripped = "This camera has already been stripped.",
	someone_else     = "Someone else is working on this camera.",
	switched_camera  = "Switched cameras. Progress on the other one was cancelled.",
	need_pliers      = "You need pliers to strip this camera.",
	stopped_working  = "You stopped working on the camera.",
	you_are_dead     = "You're dead.",
	you_are_arrested = "You're arrested.",
	gov_blocked      = "Government jobs can't strip Flock cameras.",
	job_blocked      = "Your job can't strip Flock cameras.",
	camera_placed    = "Camera placed and saved. Manage it with !heistflock.",
	look_at_ground   = "Look at the ground to place the camera pole.",
	look_at_surface  = "Look at a surface first.",

	-- Smashing
	smash_how            = "Hit it with a crowbar or pliers to break it apart.",
	smash_need_tool      = "That won't break it. Use a crowbar or pliers.",
	smash_too_far        = "You were too far away for the blast to count.",
	alarm_tripped        = "You set off the camera's alarm!",
	alarm_tripped_wanted = "You set off the camera's alarm! You're now wanted.",
	part_reserved        = "That part is {name}'s for {seconds} more seconds.",
	part_confiscated     = "{part} taken as evidence.",
	part_not_taken       = "You can't carry that part right now.",
	part_error           = "Something went wrong picking that up. An admin can see why in !heistflock.",

	-- Prompt above the camera
	prompt_strip   = "Strip camera",
	prompt_pliers  = "Pliers required",
	prompt_done    = "Already stripped",
	prompt_in_use  = "{name} is on it",
	prompt_smash   = "Smash it",
	prompt_tool    = "Crowbar or pliers needed",
	prompt_smashed = "Smashed",
	prompt_camera  = "Flock camera",
	part_pick_up   = "Pick up",
	part_whose     = "{name}'s for {seconds}s",
	part_evidence  = "Take as evidence",

	-- Progress card
	stage_of       = "STAGE {stage}/{total}",
	hint_stay      = "Stay close  ·  walk away to stop",
	hint_hold      = "Keep holding",
	hint_check     = "Hands full: finish the step on screen",

	-- Payout card
	payout_title   = "Camera stripped",
	payout_detail  = "Scrap sold",
	payout_parts   = "Parts: {list}",
	payout_smash_title  = "Camera smashed",
	payout_smash_detail = "Grab the parts before someone else does",
	now_wanted     = "You're now wanted by the police",

	-- Plate scanner alerts, for police. Whole sentences so the name can move.
	alpr_hit            = "PLATE HIT",
	alpr_driver_wanted  = "Driver {name} is wanted",
	alpr_driver_warrant = "Driver {name} has a warrant",
	alpr_owner_wanted   = "Owner {name} is wanted",
	alpr_owner_warrant  = "Owner {name} has a warrant",
	tamper_title        = "CAMERA TAMPERED",
	tamper_text         = "Its alarm just went off",

	-- Hands-on steps. Each has a title, what to do, and what to avoid.
	check_back_off   = "Back off",
	check_tamper     = "TAMPER",
	check_waiting    = "...",
	check_steady     = "Steady...",

	screws_title     = "Security screws",
	screws_do        = "Click and HOLD on a screw until it backs out. Do all four.",
	screws_avoid     = "Keep the mouse on the screw while holding, or the bit slips.",

	pry_title        = "Pry the lid",
	pry_do           = "HOLD the mouse button to lean on the bar. Let go in the green zone.",
	pry_avoid        = "Let go too early and it won't give. Too late and the lid cracks.",

	battery_title    = "Battery leads",
	battery_do       = "Click the leads to unplug them, in the order on the white sticker.",
	battery_avoid    = "Wrong order shorts the battery.",
	battery_sticker  = "SERVICE: UNPLUG IN THIS ORDER",

	cable_title      = "Wiring loom",
	cable_do         = "Read the work tag at the top, then click that cable to snip it.",
	cable_avoid      = "Leave the green TAMPER loop alone.",
	cable_tag        = "CUT:",
	cable_1          = "SOLAR IN",
	cable_2          = "LTE ANT",
	cable_3          = "CAM DATA",
	cable_4          = "IR LED",
	cable_5          = "BATT",
	cable_6          = "TAMPER",

	board_title      = "Modem board",
	board_do         = "HOLD the mouse button and sway left and right to rock the board out.",
	board_avoid      = "Gently: whipping it side to side bends the gold contacts.",

	solder_title     = "Gold contacts",
	solder_do        = "HOLD the mouse button with the iron on the glowing contact. Follow it.",
	solder_avoid     = "Stray off it for too long and the iron slips.",

	-- Results
	result_pass      = "Clean work",
	result_too_slow  = "You took too long.",
	result_wrong     = "That went wrong.",
	result_gave_up   = "You backed off.",
	result_error     = "Something went wrong.",
	result_alarm     = "{reason} Tamper alarm tripped.",
	fail_not_loose   = "It didn't give.",
	fail_cracked     = "The lid cracked.",
	fail_short       = "Short circuit.",
	fail_tamper      = "You cut the tamper loop.",
	fail_wrong_cable = "Wrong cable.",
	fail_bent        = "You bent the contacts.",
	fail_slipped     = "The iron slipped.",
}

-- Looks up a message in the configured language (falling back to English)
-- and fills in {words in braces} from the vars table.
function HeistFlock.L(key, vars)
	local language = HeistFlock.Languages[HeistFlock.Config.Language] or HeistFlock.Languages.en
	local text = language[key] or HeistFlock.Languages.en[key] or key

	if vars then
		text = string.gsub(text, "{(%w+)}", function(name)
			return vars[name] ~= nil and tostring(vars[name]) or "{" .. name .. "}"
		end)
	end

	return text
end
