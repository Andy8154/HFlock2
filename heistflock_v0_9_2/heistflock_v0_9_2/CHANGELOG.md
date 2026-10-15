# Heist Flock changelog

## 0.9.2
Targeting mode (Settings → Plate scanning)
- **Multi-target** (default, as before): a camera reads every car in its whole sweep (half its lens's view plus how far the head turns, either side) and follows one of them with its head.
- **Single-target**: a camera reads only the car its head is following, so players can see what it's reading and judge blind spots. It takes turns: after about 3 seconds on one car it turns to the car in view it looked at longest ago, so a parked car can't hold it and a passing wanted car is still read within a few seconds. Cars in view but not followed show as "in view, waiting its turn" in the scanner view and "Check a car".
- New key `ALPR_TargetMode` ("multi" or "single") for config.json. The mode is in the support report.

Plate reads
- A car is one **sighting** across the whole camera network: a car passing seven cameras is one entry with all seven listed ("+6 more" in Diagnostics), and "Plates read" counts it once. A new sighting starts once the car has been out of every camera's view for 60 seconds, or 5 minutes after the last one began (a parked car shows up every 5 minutes instead of every scan). Wanted checks and alerts still happen on every scan.

Scanner view
- Turning plate scanning off now clears the view and says so, instead of leaving the last scan on screen. Data older than a few seconds is dropped rather than labelled stale.

Smashing
- Explosions only count when the player who set them off is within "Blast range" (`Smash.ExplosionMaxDistance`, 600 units ≈ 11 m; 0 = any distance). Too far away, the player is told so.
- One blast can now destroy several cameras. The hit limit for explosions is per camera; melee stays one hit per swing.
- "Alarm chance per hit" now says the chance adds up over hits (10% with the default 15 hits trips about 79% of cameras). New option "Roll once per camera" (`Smash.AlarmPerCamera`): roll only on the first hit, so the chance is per camera.
- Pliers make a hit sound on walls and props in smash mode (cameras play their own clang).

Housekeeping
- After a Lua refresh that changes the camera's parts, the old part models are removed before new ones are made.

Reviewed: the Targeting mode setting was first built by another agent. It was checked line by line and kept, with one fix: in Single-target, a car staying in view held the camera forever.

Not in this version: police plate tracking (sighting history, /plate lookup, colour/heading/speed on alert cards). It's the next feature (0.10.0); this version's sightings are the groundwork for it.

Upgrading from 0.8
- "Explosions destroy it" is on by default since 0.9.1, so explosions now finish cameras even with "Bullets count" off. Turn it off for the 0.8 behaviour.

Not tested in game yet. Every Lua file parses (Lua 5.1), with no undefined globals.

## 0.9.1
From the 0.8.1 playtest (sections 1–3 of TESTING.md passed).

- Explosions now destroy a camera in one go: every remaining stage breaks and drops its parts, and whoever set it off gets the bonus. The usual job, police, arrested and in-a-vehicle checks still apply, and it rolls the alarm once like a hit. New setting "Explosions destroy it" (`Smash.ExplosionsDestroy`, on); turn it off to make a blast count as one hit, and only with bullets on. "Bullets and explosions count" is now just "Bullets count".
- A fully smashed camera looks wrecked instead of like a brown case with a handle. The housing is charred dark grey and hangs nose-down off the arm, with an empty hole where the lens was. The cut wires are short stubs out of its top, not an arch over it.
- After a Lua refresh, the camera's shared part models are rebuilt if the number of parts changed.
- Plates from Realistic Police now show exactly as they look on the car, whatever the plate style: "ZN-975-VE" with EU, "PR917AI" with US or a custom US-based plate, following per-vehicle styles too. This copies Realistic Police's own drawing rule. They used to show as stored ("PR 917 AI"). A plate in any other shape is shown as stored. If Realistic Police's config is missing or different, the stored plate is used instead of an error.
- Plate text from any source (Realistic Police, the HeistFlock_GetPlate hook, numbers) is cleaned: no control characters or edge spaces, at most 32 characters.
- The scanner view and "Check a car" show how a plate was stored when it differs from what's on the car (e.g. stored as "PR 917 AI").

Not tested in game yet. Every Lua file parses, with no undefined globals.

## 0.9.0
Cameras follow cars
- A working camera turns its head toward a car it can see, up to `ALPR.Swivel` degrees each way (30 by default; "Head turns" in Settings, 0 = fixed). It keeps following the same car while it can, otherwise the closest, and turns back to straight when nothing's there. Blind cameras don't move.
- The server picks the car; each player's game does the turning (smoothly, 70° a second), so following costs one networked value per camera, sent only when the car changes.
- On the built-in camera the arm and head turn and the solar panel stays put; the LED, wires and sparks turn with the head. A custom model turns as a whole.
- A camera now covers half its lens's field of view plus however far it can turn, either side (35° + 30° = 65° each way by default). Range is unchanged. (In 0.9.2's Single-target mode it only reads the car it's following.)

Scanner tools (admins with HeistFlock View, in Diagnostics → Plate scanning)
- **Scanner view**: draws, for every camera within about 76 m of you, its coverage fan with rings every 10 m out to its range, where its head points, a beam to the car it follows, and a line to each car near it (green read, amber blocked, grey out of view or range). Over each car: name, type (Source vehicle, VCMod, simfphys, LVS), plate and where the plate came from, the owner or driver if flagged, and for each camera "18.2 m of 28.6 m (10.4 m left) · reading" or why not ("blocked by prop_physics", "outside its view", "out of range"). A panel shows how long scans take and how much work they do, and your own car's status. It comes from the server's real scan, once a second, only to admins who turned it on. Also `heistflock_scanner_view 1`.
- **Check a car**: sit in or look at a car; every camera within 1.5× range reports its distance and whether it reads the car, and why not. In chat, the console and on screen. Also `heistflock_check_car`.
- **Send me a test alert**: a fake plate hit only you see, to check what police get. Also `heistflock_test_alert`.
- Diagnostics also shows scan time (last, average, peak), work per scan (cameras, cars, checks, sight lines), coverage, and the last plates read. The support report includes the scan settings and cost.

Under the hood
- Scanning now records why a car isn't read (range, view, blocked and by what), counts its own work, and times each scan.
- `HeistFlock.GetPlate` also returns where the plate came from. New: `HeistFlock.VehicleKind`, `HeistFlock.CoverageAngle`.
- An sh_config.lua without `ALPR.Swivel` gets the default.

Testing
- Not tested in game yet. Every Lua file parses (Lua 5.1), with no undefined globals, and network messages and functions were cross-checked. See TESTING.md section 6b.

Upgrading from 0.8.1
- Replace the addon folder. Settings, config.json and camera saves carry over. Cameras now see wider (the swivel adds to the field of view); set "Head turns" to 0 to keep the old coverage.

## 0.8.1
A stability and safety pass on 0.8.0. No gameplay changes.

Bugs fixed (found by reading the code, not yet reproduced in game)
- Parts could be paid twice. If a provider or HeistFlock_GiveMaterial hook gave part of a reward and then errored, the part stayed on the ground. A part is now marked taken before anything is handed out, and an error uses it up and goes to Diagnostics. A part nothing took (no error) still stays on the ground.
- Steps mode with crafting: an erroring GiveMaterial hook stopped the stage half-finished, so the next tick finished it again (skipped a stage, loot twice). Hooks and providers are now always called safely.
- Loot in config.json naming a material from another addon was dropped at load, because that addon hadn't registered it yet. Loot is now only shape-checked at load, and unknown materials are reported once everything has loaded.
- Switching strip modes left smash hits on cameras, which kept them blind in steps mode. Hits are now cleared on a mode switch (either way), and work in progress stops.
- A removed camera stayed referenced in each vehicle's plate-read history.
- Removed parts stayed in the loose-part list until the next drop.
- Without DarkRP's addMoney, the money provider and the bonus would error. They now skip the payment.
- An sh_config.lua kept from before 0.8.0 broke loading (no Smash or Parts section). The missing values now use the defaults, and Diagnostics lists them.
- A non-number Smash.HitDelay or ALPR.ScanInterval in sh_config.lua caused errors. Both are now checked and clamped (0.1–5 s, 0.25–10 s).
- A broken value in sh_config.lua fell back to the setting's minimum (a bad RepairTime meant "never repair"). Settings now fall back to sensible defaults.
- Missing fonts or icons (no FastDL or Workshop content) showed checkerboards. Icons are skipped and text uses Tahoma / Courier New; the pliers' weapon icon falls back to its name.

Hardening
- Denied admin actions now say which permission is missing, instead of doing nothing.
- The settings message rejects more entries than there are settings and non-text ids. Unknown admin action names are ignored.
- heistflock_save, heistflock_removeall and heistflock_report are rate limited.
- Access is refreshed for everyone when settings change (Config.ManagerGroups, when there's no CAMI).
- Moving a camera with the physgun is now logged like other admin actions.
- The per-hit clang uses the game's SolidMetal.ImpactHard sound instead of numbered files.

Debug tools
- Diagnostics → **Copy report**: a plain-text summary to paste when asking for help (version, mode, parts provider, addons found, admin mod and permissions, camera counts, settings changed in the menu, warnings, session stats, the last 60 events). No IPs or SteamIDs. "Print to console" prints the same.
- Diagnostics → **Recent events**: the last events in plain words ("Andy hit camera #83 (stage 1: 3/4)", "Sam's hit didn't count: …", "…dropping 1x Camera Lens, 2x Scrap Metal", pickups, confiscations).
- `heistflock_report` in the server console prints the report.
- Events are kept whether or not Debug logging is on. Debug logging also prints them to the console.
- TESTING.md: a step-by-step in-game test list.

Checked
- Every network handler: who can send it, rate limit, payload checks. Smashing: one hit per swing, tools, bullets, attackers, simultaneous hits (rewards can't repeat). Parts: single collection, owner window, police, expiry, cap, duplicator, pocket, physgun, toolgun. Plate scanning: blinding, cooldowns, vehicle checks. Hooks: every one has a fixed name and is added once.
- Static: every Lua file parses (Lua 5.1), no undefined globals, every HeistFlock function, network message, language key, font and custom icon/font file cross-checked.
- Not checked here: base-game model and sound paths (no game files to check against).
- Not tested in game: everything above. See TESTING.md.

Upgrading from 0.8.0
- Replace the addon folder. settings.json, config.json and the camera save files carry over unchanged.

## 0.8.0
Smash mode (new default)
- Cameras are broken by hitting them with the pliers or a crowbar (`Config.Smash.Tools`). Hits are counted, not damage, so no weapon can do it in one. Each stage takes `Config.Stages[i].hits` hits (4 / 5 / 6).
- Only melee hits from listed tools count. Bullets and explosions count only with `Smash.AllowBullets`. The usual job, police, arrested, dead and in-a-vehicle checks apply to every hit, and the reason is shown when a hit doesn't count.
- One hit per `Smash.HitDelay` (0.35 s) per player, so autoclickers and shotgun pellets can't speed it up. Several players can smash the same camera; whoever lands the final hit gets the bonus.
- Every hit: a metal clang, sparks, and the camera head shakes. A finished stage breaks off a part as before.
- Hits don't wear off. A damaged camera resets after the repair time, counted from its last hit.
- HUD: looking at a camera shows "Stage 2/3" and how much of the stage is left. Players whose job can't smash cameras just see "Flock camera".

Parts
- New `heistflock_part` entity: each finished stage drops its loot as items (one per material, at most 4 per stage) that pop off the camera head. Six materials, each with a base-game model: lens, copper wire, circuit board, gold contacts, solar cell, scrap metal.
- Press E to pick one up. It goes through `Config.Parts.Provider`: "money" sells it on the spot, "hooks" sends it to your own addon through HeistFlock_GiveMaterial (example in hooks_reference.lua). A part nothing takes stays on the ground.
- For `Parts.OwnerTime` (10 s) only whoever broke the stage can pick its parts up; after that anyone can steal them. Police take parts as evidence for no money (`Parts.PoliceConfiscate`).
- Parts vanish after `Parts.Lifetime` (120 s), there are at most `Parts.MaxLoose` (60) on the map (oldest go first), and they can't be saved, copied, pocketed, punted, or physgunned/toolgunned by players without the Place permission. They can be carried with the gravity gun.
- `Config.Payout` is now a bonus for the final hit, 0 by default, since parts are the income. If your settings.json has a payout saved from the menu, that value still applies.
- `Config.Crafting.Provider` moved to `Config.Parts.Provider` ("Parts_Provider" in config.json); old config.json files still work.

Getting caught
- Failing a step no longer applies in smash mode. Instead, each hit has `Smash.AlarmChance` (10 %) to trip the camera's alarm, or the first hit always does (`Smash.AlarmOnFirstHit`). The alarm rings at the camera, its LED flashes, and the player can be made wanted. It goes off once per camera until repaired.
- Optional police alert (`Smash.PoliceAlert`, off): a "Camera tampered" card and a marker on the camera, like plate hits.
- With "Any damage blinds it", a camera stops reading plates from its first hit.

Steps mode
- The hands-on steps are kept as `Config.StripMode = "steps"`. Their settings (stage times, pliers, hold to work, steps) only show in the menu in steps mode, and the Smashing settings only in smash mode.
- Switching to smash mode stops anyone mid-stage.

Settings
- New "Smashing" section: hits per stage, tools, bullets, alarm chance, alarm on first hit, alarm makes wanted, police alert, where parts go, how long they're reserved and last, the most on the map, and police confiscating. All of them also work in config.json by their id (see config.example.json).
- New "list" setting type for weapon classes and user groups, typed as "a, b, c".

Permissions
- Three permissions instead of one: "HeistFlock Manage" (settings and the whole menu, superadmin), "HeistFlock Place" (place, move, remove, reset, skip and teleport to cameras, superadmin), "HeistFlock View" (markers, Dashboard, Cameras and Diagnostics, read-only, admin). Manage includes both others; Place includes View.
- Checked only on the server. CAMI is asked with a callback (some admin mods only answer that way), the answer is kept per player and refreshed on join, first spawn, rank changes (both CAMI hooks) and every 15 seconds. Until the first answer, a player has no access.
- Privileges are registered when the file loads and again in Initialize, only once.
- No admin mod and no CAMI: only `Config.ManagerGroups` (superadmin) can use the menu, and Diagnostics warns about it.
- The menu hides pages and buttons you can't use.
- Admin actions (place, move, remove, reset, skip, settings) go to the activity feed, the server log, ULX's log when ULX is installed, and a new HeistFlock_AdminAction hook.
- Diagnostics: a Permissions section with the admin mod found, CAMI, whether each permission is registered, and your own access.
- Docs: "Giving staff access" at the top of sh_config.lua, and lua/heistflock/permissions_guide.lua.

Fixes
- Partly stripped cameras showed no repair countdown in Diagnostics and on the Cameras page. They now show "resets in m:ss".
- Duplicate steps in config.json weren't removed on load (0.7.1 checked the stages before config.json was read). Fixed.
- With Realistic Police installed, a camera that saw a car in its first seconds could log a made-up plate before Realistic Police set the real one. New vehicles are now read once their plate is set (or after 4 seconds).

Testing
- Tested in game: nothing in 0.8.0 yet. Every Lua file passes a full Lua 5.1 parse with no undefined globals, and functions, settings, language keys and network messages were cross-checked.
- Permissions follow the CAMI standard. SAM will be tested on the live server. ULX, FAdmin, sAdmin, xAdmin and ServerGuard only follow the standard so far.
- SAM's own log isn't written to: no public SAM log function could be confirmed. The server log and the HeistFlock_AdminAction hook still record everything.
- The ItemStore provider is still not finished (it needs ItemStore's code), so choosing it sells parts for cash, with a Diagnostics warning.

## 0.7.1
Hands-on steps
- Fixed: picking a step could hang the server when a stage listed the same step twice. The picker no longer loops, and duplicate or unknown steps in a stage's "checks" (sh_config.lua or config.json) are dropped on load, with a warning for unknown ones.
- Fixed: turning every step off still gave Security screws. Now no steps happen at all.
- A stage whose own steps are all turned off now gets no steps; its share goes to the stages that still have some (it used to borrow other stages' steps).
- Clicks during the short "Steady..." intro are ignored for every step, not just Pry and Gold contacts. The hint now shows for every step.
- Battery leads and Wiring loom answers that arrive impossibly fast are refused.
- Time limit can't be set below 10 seconds any more (menu, sh_config.lua and config.json).
- Fixed: the Modem board could jitter at very low frame rates. Same fix for menu hover fades and toggle switches.

Plate scanning
- Wanted and warrant status is checked every scan a camera can see the vehicle, so newly wanted players are flagged straight away (it used to wait up to 30 seconds).
- The reads list and "plates read" count log a vehicle once per camera every 5 minutes, so parked cars don't flood them.
- The alert cooldown only starts once police were actually told. With no police online, the first officer to come on duty gets the alert. If HeistFlock_ALPRHit blocks an alert, the cooldown doesn't start either.
- Fixed: with "Any damage blinds" on, a camera kept scanning during the first stage. It now goes blind as soon as someone starts on it, and sees again if they give up before the first stage is done.
- Police alert text ("PLATE HIT", "Driver ... is wanted" and so on) is in sh_language.lua now.

Placing cameras
- Fixed: turning a camera in place was refused with "Look at the ground" because the server hit the camera's own pole. Both preview and server now ignore cameras.
- Custom models must be placed next to a wall, floor or ceiling; the server checks this too.

## 0.7.0
Hands-on steps (replaces the minigames)
- Six steps, each a real part of taking a camera apart, shown as a close-up of the hardware instead of a puzzle:
  - Opening the housing: Security screws (hold on each until it backs out) and Pry the lid (lean on the bar, let go when it gives).
  - Cutting the power: Battery leads (unplug in the order on the service sticker) and Wiring loom (snip the cable on the work tag, not the tamper loop).
  - Pulling the board and gold: Modem board (rock it out gently) and Gold contacts (keep the iron on the moving contact).
- Every step says what to do and what to avoid, right under the picture, for players who've never done it.
- Failing says what went wrong ("Short circuit.", "The lid cracked.", "You cut the tamper loop.").
- Each stage picks from its own steps (Config.Stages[i].checks, also settable in config.json). Each step can be turned off in Settings.
- The tamper meter replaces the countdown, and the window no longer blurs the screen.

Plate scanning (ALPR)
- Working cameras read the plates of vehicles in front of them (range, field of view and line of sight).
- When a vehicle's driver or owner is wanted (optionally: has a warrant), police get an alert card, and the vehicle is outlined through walls with a marker showing its plate and distance.
- With Realistic Police installed, cameras read the same plates police see on their tablets. Otherwise each vehicle gets its own plate.
- Damaged cameras are blind (by default, as soon as stripping starts), so stripping one opens a gap in the network.
- New Settings section, dashboard stats (cameras reading, plates read, wanted hits) and Diagnostics row. Each camera row shows "reading plates" or "blind".
- New hooks: HeistFlock_GetPlate, HeistFlock_ALPRHit, HeistFlock_SettingsChanged.

Placing and moving cameras
- "Place camera" and the new Move button show a see-through preview at your crosshair: scroll to rotate, R to face you, left click to place, right click to cancel. The camera moves once, so there's no physgun lag. Red preview = not allowed there.

## 0.6.8
Found in a full review
- Settings saved from the menu no longer freeze every other setting. settings.json used to store every value, so after one change in the menu, later edits to sh_config.lua or config.json did nothing. It now stores only what differs from the defaults, and Diagnostics shows how many settings are changed in-game.
- Ranks given the "HeistFlock Manage" permission in an admin mod (SAM, ULX...) can open the menu. Players' games used to check the permission themselves, which many admin mods don't support; the server now tells them.
- Only players with that permission can place cameras from the spawn menu. Before, any admin could place cameras, which are saved permanently, but couldn't move or remove them.
- The optional pliers shipment uses Config.PliersWorldModel instead of always the crowbar.
- A fresh click with the pliers is recognised even if it lands during the swing delay, so switching cameras doesn't sometimes need a second click.
- The scrap effect is explicitly sent to players.

## 0.6.7
- The optional DarkRP pliers shipment says who can buy it: `allowed` in the module, by job command (default: Gun Dealer). An empty list uses DarkRP's default.
- Stage descriptions in the Settings page follow stage names from config.json.
- New hooks and functions reference: lua/heistflock/hooks_reference.lua (HeistFlock_CameraStripped, HeistFlock_CanGetLoot, HeistFlock_GiveMaterial, HeistFlock_LootGiven, and the client hooks).
- A misspelled Config.Crafting.Provider shows a warning on the Diagnostics page instead of silently selling parts for cash.
- Removed two unused messages and two unused icons.

## 0.6.6
- Fixed built-in cameras popping in and out of view when more than one is on the map. All cameras share one set of part models; each camera now makes the engine recalculate the parts' position before drawing them, instead of reusing the first camera's. Parts are also lit where the camera actually stands.

## 0.6.5
- A custom camera model that doesn't exist on the server now falls back to the built-in camera, whichever file it came from (sh_config.lua, config.json or settings.json), with a warning on the Diagnostics page. "Reset to defaults" can't bring the bad path back.
- Linux and Steam Deck players get the bundled fonts by file name. FontOverride is cut to 31 characters, Garry's Mod's limit for font names.
- The dashboard's "Paid out" now counts crafting loot when it's sold, including loot from cameras that were abandoned or finished by someone else. The payout card still shows what you earned from that camera.

## 0.6.4
- Holding left click with the pliers and glancing at another camera no longer switches to it. Only a fresh click (or E) switches.
- "Skip a stage" in the admin menu now starts the reset timer, so a skipped camera doesn't stay damaged forever.
- Saved cameras are checked a little above the floor when loading, so poles standing on the ground (including displacements) are never skipped.
- Admins get "Slow down, try again." when menu actions come too fast, instead of nothing happening.
- New: garrysmod/data/heistflock/config.json overrides sh_config.lua for installs that can't edit it (like the Workshop): language, font, stage times/names/scrap/loot, crafting, and any setting from the menu by its id. The server writes config.example.json next to it on first start. (The DarkRP job and shipment switches still have to be set in sh_config.lua, because jobs must be the same on the server and every player.)
- The FontOverride comment now mentions that Vietnamese needs it.

## 0.6.3
- Starting a camera while working on another now switches to the new one: the stage in progress on the old camera is cancelled (finished stages stay done, and it resets after the repair time like any abandoned camera). Players see "Switched cameras. Progress on the other one was cancelled."

## 0.6.2
Review fixes
- A player can only work on one camera at a time ("You're already working on another camera").
- Torque check: letting go of the mouse anywhere (off the window, over Give up) counts as letting go.
- Timing and torque checks allow for the player's ping, so lag spikes don't move the needle or gauge that gets judged.
- Moving a damaged custom-model camera keeps its new angle. The built-in pole always saves standing straight, keeping only which way it faces.
- Dashboard activity times and the Cameras save bar count up live again.
- Each skill check has its own ID; a late answer to an old check is ignored.
- The remover tool only logs and saves once the camera is actually gone (another addon may block it).
- Payout card: shows "Scrap sold" by default. With crafting on, it lists the parts handed out and includes what they sold for.
- Fonts now include accented Latin letters, Greek and Cyrillic. Config.FontOverride sets a system font for other scripts.
- The crafting guide is also in lua/heistflock/crafting_guide.lua, so Workshop uploads keep it.
- The DarkRP job and shipment switches moved into Config.DarkRP.
- The menu's scroll restore no longer stacks when two refreshes come close together.

Found in a full audit
- Cameras left partly stripped reset after the repair time instead of staying damaged forever.
- Nobody can "make persistent" a camera (it would have spawned twice on every map load), drive it, or pick it up or punt it with the gravity gun. Only managers can use other right-click options on it, and removing it that way updates the save file.
- Cameras can't be copied with the duplicator or Advanced Duplicator.
- No stripping from inside a vehicle.
- At most 250 cameras per map (spawn menu, menu and save file), and saved cameras outside the map are skipped with a warning.
- The admin menu's status info is compressed, so a map with many cameras can't go past the network message size limit.
- Skill check answers are size-checked and rate-limited before being read. Admin actions and settings saves are rate-limited too.

## 0.6.1
- Moving a camera with the physgun is smooth: cameras now have a fixed light mass (big collision boxes made them heavy), and each player's copy of the collision shape follows the camera while it moves.
- Menu pages no longer jump back to the top every few seconds. Pages only rebuild when what they show changes, and the scroll position is held until the new page finishes laying out.
- Camera saving is easy to find: a save bar on the Cameras page shows the save file, how many cameras it holds and when it last saved, with a Save now button. Admins also get a "Saved N cameras to garrysmod/data/heistflock/<map>.json" message after every save they trigger, and Diagnostics shows the file's path.

## 0.6
Gameplay
- No more holding: press once to start, then stay close. Walking away or putting the pliers away stops the work. ("Hold to work" in Settings brings the old way back.)
- Pliers keep swinging on their own while you work.
- Four new skill checks: Sequence (repeat a light pattern), Screws (undo them in order), Torque (hold, let go in the green zone) and Frequency (tune a dial to match a signal). Seven in total.
- Checks are picked at random from the ones turned on (each can be toggled in Settings), and the same one won't come up twice in a row.
- 4 skill checks per camera by default, spread across the stages by length.
- Stages are 9 seconds longer in total (11, 11, 13). The timing needle is slower with a wider zone, and the time limit is 15 seconds.

Look and feel
- New design: night-vision mint brand color, tighter layout, custom fonts (Inter and JetBrains Mono) and a custom icon set instead of GMod's default icons.
- Everything scales with screen resolution.
- Menu redesigned: sidebar with logo and your avatar, Dashboard with live activity feed, Cameras as a table, Settings as grouped lists with hover help, Access page for jobs, Diagnostics.
- New HUD prompt, progress bar, skill check result toast and payout card.
- Skill check windows redesigned to match.

For server owners
- Language file (sh_language.lua): every player-facing message can be translated.
- Config file rewritten with every option explained.
- Optional DarkRP module adds the Camera Stripper job and pliers shipment without editing jobs.lua (off by default).
- Crafting groundwork: materials, loot per stage, providers (sell for cash, hooks, ItemStore planned) and a recipe format. Off by default; see CRAFTING.md.
- New hooks: HeistFlock_CameraStripped, HeistFlock_CanGetLoot, HeistFlock_GiveMaterial, HeistFlock_LootGiven.

## 0.5
Fixes
- Skill check window closes the moment the result arrives; the result shows on the HUD instead, so players have time to grab the camera again.
- Grace period after a skill check raised to 2 seconds.
- Broken or malformed skill check answers now always count as a fail, never a pass.
- Late skill check answers are rejected as "Too slow!".
- The timing check is judged against the exact needle the player saw, using the shared game clock instead of ping.
- The code check's reveal time no longer comes out of the time limit.
- Cleanup tools and cleanup addons no longer delete saved cameras. Cameras only save when an admin places, moves or removes one.
- Cameras spawned from the Q menu are no longer put on undo or cleanup lists or given a prop-protection owner.
- The built-in camera's collision is now the pole, head and panel instead of one large box.
- Damaged camera save files are skipped with a warning on the Debug page.
- The CAMI permission check can't error, and never grants access on failure.
- Custom models are checked with util.IsValidModel.
- The admin menu can be dragged by its whole header.
- Text settings with spaces at the ends no longer stay "unsaved".
- Status requests that hit the rate limit get a delayed reply instead of being dropped.
- Client collisions update when the camera model changes.
- Physgun and toolgun access on cameras uses the same permission as the menu.

Polish
- All cameras share one set of part models instead of 14 each.
- Scrap pieces are made on each client instead of as networked props.
- Pliers animate once per swing under prediction.
- Teleport looks for a clear spot next to the camera.
- The hanging solar panel no longer pops out of view at the edge of the screen.
- The DarkRP example moved to lua/heistflock/darkrp_example.lua so a Workshop upload keeps it.
