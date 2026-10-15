--[[-------------------------------------------------------------------------
	HEIST FLOCK - HOOKS AND FUNCTIONS REFERENCE (this file is not loaded)

	For other addons that want to react to or change what Heist Flock does.
	Add hooks with hook.Add as usual, e.g.:

		hook.Add("HeistFlock_CameraStripped", "MyAddon", function(ply, cam, total, drops)
			print(ply:Nick() .. " earned " .. total)
		end)


	SERVER HOOKS
	------------

	Smashing (smash mode)

	HeistFlock_CanSmash(ply, cam)
		Before a hit counts (after the tool, job and police checks).
		Return false to ignore it.

	HeistFlock_AlarmTripped(ply, cam)
		A hit set off the camera's alarm. ply is who hit it.

	HeistFlock_CameraStripped(ply, cam, total, drops)
		A camera was finished: the final hit (smash mode) or the last stage
		(steps mode), and the player was paid.
		ply    the player
		cam    the camera entity (heistflock_camera)
		total  money this player earned from this camera: the bonus, plus
		       in steps mode what their run's parts sold for
		drops  steps mode: parts handed out during their run, a list of
		       { material = "copper_wire", amount = 3, value = 180 }.
		       Smash mode: always empty; parts are picked up separately.
		Return value is ignored.


	Parts

	HeistFlock_CanGetLoot(ply, cam, stageNumber)
		Before a finished stage drops its parts (smash mode) or hands them
		out (steps mode with crafting). ply is who broke the stage.
		Return false to give nothing for this stage.

	HeistFlock_CanCollectPart(ply, part)
		A player pressed E on a part, after the "reserved for whoever broke
		it" check. Return false to stop them picking it up.

	HeistFlock_GiveMaterial(ply, materialId, amount, source)
		For every part a player gets, before Config.Parts.Provider does.
		source is the part entity (smash mode) or "stage" (steps mode).
		Return true if your addon took it; the provider is then skipped.
		If your hook errors, the part counts as used up (it may have been
		half given) and the error shows on the Diagnostics page.
		Works with any provider, but set Parts_Provider to "hooks" if your
		addon should be the only place parts go: then a part no hook takes
		stays on the ground instead of being sold.

		Example: every camera part becomes another addon's "metal" resource.

			local METAL_PER_PART = {
				scrap_metal = 1, copper_wire = 2, camera_lens = 2,
				circuit_board = 4, gold_contacts = 5, solar_cell = 3,
			}

			hook.Add("HeistFlock_GiveMaterial", "MyCrafting_Metal", function(ply, materialId, amount)
				local metal = (METAL_PER_PART[materialId] or 1) * amount
				MyCrafting.GiveResource(ply, "metal", metal) -- your addon's own function
				ply:ChatPrint("+" .. metal .. " metal")
				return true
			end)

	HeistFlock_PartCollected(ply, materialId, amount, value)
		A player picked up a part. value is the cash it sold for (0 unless
		the money provider sold it).

	HeistFlock_PartConfiscated(ply, materialId, amount)
		Police took a part as evidence (Parts_PoliceConfiscate).

	HeistFlock_LootGiven(ply, drops)
		Steps mode with crafting: after a stage's parts were handed out.
		drops is the same format as in HeistFlock_CameraStripped.


	Plate scanning

	HeistFlock_GetPlate(vehicle)
		Plate scanning asks this first for a vehicle's plate. Return a string
		(or number) to use your own plate addon's plate, exactly as it should
		show; any format works. Return nothing to fall back to
		Realistic Police's plate, then a plate Heist Flock makes up. (With
		Realistic Police installed, a new vehicle isn't read for its first
		4 seconds, until Realistic Police has given it a plate.)

	HeistFlock_ALPRHit(cam, vehicle, plate, suspect, reason)
		A camera read the plate of a vehicle whose owner or driver is wanted
		(reason "wanted") or has a warrant (reason "warrant"), and police are
		about to be alerted. Return false to stop the alert. A stopped alert
		doesn't start the vehicle's alert cooldown, so this is called again on
		every scan (every ALPR.ScanInterval seconds) while a camera sees the
		vehicle. Only called while at least one police player is online.

	Admin

	HeistFlock_SettingsChanged()
		An admin saved or reset settings in the menu.

	HeistFlock_AdminAction(ply, text)
		An admin placed, moved, removed, reset or skipped a camera, or changed
		settings. text reads like "moved Flock camera #83". ply is nil for
		the server console. For logging addons; these also go to the
		activity feed, the server log and ULX's log.


	CLIENT HOOKS
	------------

	HeistFlock_ConfigChanged()
		The server sent new settings (on join, and whenever an admin saves).

	HeistFlock_InfoUpdated()
		Admins only: new status info arrived for the menu, in
		HeistFlock.ServerInfo.


	USEFUL FUNCTIONS
	----------------

	Shared:
		HeistFlock.HasAccess(ply, level)       "manage", "place" or "view" (see permissions_guide.lua)
		HeistFlock.IsManager(ply)              same as HasAccess(ply, "manage"), kept for older addons
		HeistFlock.IsUsingPliers(ply)          is the player holding the pliers?
		HeistFlock.RegisterMaterial(id, data)  add a crafting part (see crafting_guide.lua)
		HeistFlock.RegisterRecipe(id, data)    add a recipe (see crafting_guide.lua)
		HeistFlock.L(key, vars)                a message in the configured language

	Server:
		HeistFlock.CanStrip(ply)               true, or false and a reason
		HeistFlock.RegisterProvider(id, data)  add a place for parts to go
		HeistFlock.SpawnCamera(pos, ang)       spawn a camera (call SaveCameras to keep it)
		HeistFlock.SaveCameras()               write this map's cameras to the save file
		HeistFlock.Notify(ply, text, isError)  a DarkRP notification (chat in sandbox)
		HeistFlock.GetPlate(vehicle)           the plate cameras read for a vehicle (formatted the way
		                                       it shows on the car), where it came from, and how it
		                                       was stored. nil if not ready yet
		HeistFlock.VehicleKind(vehicle)        "Source vehicle", "simfphys", "LVS"...
		HeistFlock.CoverageAngle()             degrees either side a camera can cover (lens / 2 + swivel)
		Config.ALPR.TargetMode                 "multi" reads all eligible cars in that sweep; "single" reads the car
		                                       the head follows, taking turns between cars in view
		HeistFlock.ALPRReads                   recent sightings, newest first:
		                                       { plate, camera (first), cameras = { ids }, flagged, time }
		cam:GetTrackTarget()                   the car a camera's head is following (shared)
		HeistFlock.CameraCanScan(cam)          is this camera reading plates right now?
		HeistFlock.GiveMaterial(ply, id, n)    give a player parts, the same way picking them up does;
		                                       returns "given", "refused" or "error", and the cash value
		HeistFlock.BuildReport(ply)            the support report as text (Diagnostics, heistflock_report)
		HeistFlock.TripAlarm(cam, ply)         set off a camera's alarm as if ply's hit did
		HeistFlock.AdminLog(ply, text)         log an admin action everywhere Heist Flock logs them
---------------------------------------------------------------------------]]
