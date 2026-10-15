--[[-------------------------------------------------------------------------
	HEIST FLOCK - PERMISSIONS GUIDE (this file is not loaded; it's documentation)

	THE THREE PERMISSIONS

		HeistFlock Manage   settings, reset, and the whole menu     default: superadmin
		HeistFlock Place    place, move, remove, reset, skip and    default: superadmin
		                    teleport to cameras; save the camera file
		HeistFlock View     camera markers, and the Dashboard,      default: admin
		                    Cameras and Diagnostics pages (read-only)

	Manage includes Place and View. Place includes View, since cameras are
	placed from the menu. The menu hides what you can't use, and the server
	checks every action again, so a modified menu gets nowhere.


	GIVING STAFF ACCESS

	ULX
		ulx groupallow admin "HeistFlock Place"
		ulx groupallow moderator "HeistFlock View"
		(or XGUI: Groups, pick the group, then the permission under "Other")

	SAM
		Open SAM's menu, go to the Permissions page for the rank, and tick
		the HeistFlock permissions.

	FAdmin (DarkRP's own admin mod)
		Open FAdmin's menu (the Scoreboard menu), go to the privileges
		settings, pick the group, and tick the HeistFlock privileges.

	sAdmin, xAdmin, ServerGuard and other CAMI admin mods
		They list the three permissions with their other permissions.

	No admin mod at all
		Only the user groups in Config.ManagerGroups (sh_config.lua, or
		"ManagerGroups" in config.json) can use the menu, with full access.
		Default: superadmin.


	HOW IT WORKS

	Every admin mod above shares permissions through CAMI, a small standard
	library most of them include. Heist Flock registers its permissions with
	CAMI when it loads, and asks CAMI about each player:
	  * when they join and first spawn,
	  * whenever their rank changes,
	  * and every 15 seconds, for permissions changed without a rank change.
	It always asks with a callback, because some admin mods only answer that
	way, and keeps the answer. Until the first answer arrives, a player has
	no access.

	Diagnostics, Permissions shows which admin mod was found, whether CAMI
	is there, whether the three permissions are registered, and your own
	access to each.


	LOGGING

	Placing, moving, removing, resetting and skipping cameras, and changing
	settings, are written to:
	  * the activity feed on the Dashboard,
	  * the server log (garrysmod/logs/ with "log on"),
	  * ULX's log, when ULX is installed,
	  * the HeistFlock_AdminAction hook, for logging addons.
---------------------------------------------------------------------------]]
