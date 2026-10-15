# Heist Flock 0.9.2: in-game test list

Tick each one off. When something's wrong: `!heistflock` → Diagnostics → **Copy report**, and send that plus what you did. Turn on **Debug logging** (Diagnostics, top right) before testing, so every event also prints to the server console.

You need: a superadmin, a second player (or a friend), a DarkRP job that can smash, a police job, and a car.

## 1. Cameras (admin)
- [ ] Place a camera from the menu, then move it, then turn it in place (scroll). The preview is green and the server agrees.
- [ ] Restart the map: the cameras come back where they were.
- [ ] Remove one from the Cameras page, and one with the toolgun remover. Both stay gone after a restart.
- [ ] Spawn one from the Q menu (Entities → Heist Flock).

## 2. Smashing
- [ ] Hit a camera with the **pliers**: a clang, sparks, the head shakes, the bar above it drops. 4 hits break stage 1.
- [ ] Same with a **crowbar**.
- [ ] Hit with **fists / stunstick**: nothing counts, and you're told to use a crowbar or pliers.
- [ ] **Shoot it**: nothing counts. Turn on "Bullets count" and shoot again: it counts.
- [ ] **Blow it up** with default settings (grenade, or any explosive your server has), standing within about 11 m: one blast finishes the camera, every remaining stage's parts drop, and the payout card shows. As a blocked job or police, it does nothing.
- [ ] Throw the grenade from **further than "Blast range"** (default 600 units, about 11 m): nothing happens and you're told you were too far.
- [ ] One grenade **between two or three cameras**: all of them are destroyed.
- [ ] "Explosions destroy it" **off**: a blast is one hit, and only with "Bullets count" on.
- [ ] Pliers hitting a wall or prop make a hit sound; swinging at air makes a swing sound.
- [ ] "Roll once per camera" on with "Alarm chance per hit" at 100%: the first hit trips it. At 0%, it never trips, however many hits.
- [ ] A fully smashed camera: charred housing hanging nose-down off the arm, an empty hole where the lens was, cut wire stubs out of its top, solar panel hanging off. (Send a screenshot.)
- [ ] **Spam-click** as fast as you can: hits come no faster than about 3 a second.
- [ ] **Two players** hitting the same camera: both count, parts drop once per stage, only the final hitter gets the bonus.
- [ ] As **police** (with "Block government jobs" on) and as a **blocked job**: hits don't count, and the reason shows.
- [ ] From **inside a car**: hits don't count.
- [ ] Fully smash one: payout card "Camera smashed", camera becomes a bare pole.
- [ ] Hit one camera a couple of times, walk away: Cameras page shows "DAMAGED · resets in m:ss" and it resets on time.

## 3. Alarm
- [ ] Set "Alarm on first hit" on: first hit rings the bell, LED flashes fast, you're told, you become wanted.
- [ ] It rings only once per camera until repaired.
- [ ] Turn on "Tamper alert for police": police get a card and a marker on the camera.

## 4. Parts
- [ ] Parts pop out when a stage breaks. Look at one: name, amount, price, "E Pick up".
- [ ] Press E: sold, money added, a chat notice.
- [ ] Second player presses E on your part within 10 s: refused, shows whose it is and the seconds left. After 10 s they can take it.
- [ ] Police press E on a part: "taken as evidence", no money.
- [ ] Leave parts alone: they vanish after 2 minutes.
- [ ] Set "Most parts on the ground" to 4, smash a camera: never more than 4 parts on the map.
- [ ] Try to physgun, gravity-gun punt, pocket, toolgun or duplicate a part as a normal player: all blocked. Gravity gun carry works.
- [ ] Look for any part that looks wrong (an error model or a plain scrap gib). Diagnostics lists the material if its model is missing.

## 5. Steps mode
- [ ] Settings → "How cameras are stripped" → Hands-on steps. Smashing settings hide, step settings show.
- [ ] Strip a camera the old way; steps work.
- [ ] Switch back to smash while someone is mid-stage: their work stops cleanly, no window left open.

## 6. Plate scanning
- [ ] Become wanted, drive past a working camera: police get a plate card, the car is outlined.
- [ ] The same car isn't reported again until the cooldown ends.
- [ ] Hit a camera once: it stops reading plates (Dashboard "Cameras reading" drops by one, and a car driving past isn't read). It reads again after it resets.
- [ ] With Realistic Police: the plate on the card matches the police tablet, including for a car that was just spawned.
- [ ] Try a simfphys or LVS car if you have one: no errors.

### Target mode and sightings (new in 0.9.2)
- [ ] Settings → Plate scanning → Targeting mode **Multi-target** (default): two cars on **opposite sides** of a camera's sweep are both read, even though the head points at one.
- [ ] **Single-target**: same two cars. The head follows one, and only that one is read; the other shows "in view, waiting its turn". About every 3 seconds it turns to the other car and reads it.
- [ ] Single-target with a car **parked** in view: drive a wanted car past. The camera still turns to it within a few seconds and police get the alert.
- [ ] "Check a car" on the waiting car says "in view, waiting its turn"; on the followed car, "reading".
- [ ] Switch modes with both cars in view: the new behavior starts on the next scan.
- [ ] Drive past several cameras in a row: Diagnostics shows **one** read for your plate with "+N more" cameras, and "Plates read" goes up by one, not by the number of cameras.
- [ ] Park in view of a camera for over 5 minutes: a new read for your plate appears about every 5 minutes, not every second.
- [ ] Scanner view open, then turn Plate scanning **off** in Settings: the fans and lines disappear and the panel says scanning is off.

## 6b. Tracking and the scanner tools (new in 0.9.0)
Turn on **Scanner view** (`!heistflock` → Diagnostics → Plate scanning).
- [ ] A fan appears at each nearby camera: two edge lines, an arc at full range, and faint rings every 10 m. Green = reading, red = blind.
- [ ] Drive past a camera: its head turns to follow you (up to 30° each way), a beam joins it to your car, and it turns back to straight when you've gone.
- [ ] Two cars in view: it keeps following the first one while it can, then switches to the closest.
- [ ] Over your car: name, type (Source vehicle / simfphys / LVS), plate and where the plate came from, and "CAM-083: 18.2 m of 28.6 m (10.4 m left) · reading".
- [ ] Drive out to the arc: "reading" changes to "out of range" right at the arc. Drive beside or behind the camera: "outside its view".
- [ ] Park behind a wall or prop: "blocked by …" with what's in the way, and an amber line.
- [ ] Compare the plate shown with the plate on the car (e.g. "ZN-975-VE", dashes and all) and the Realistic Police tablet. Spawn a fresh car: it says "waiting for Realistic Police" for a moment, then the real plate.
- [ ] Hit a camera once: its fan turns red and its head stops following.
- [ ] Top-left panel: "Last scan … ms". With all your cameras and some cars, it should stay well under 2 ms. Note the numbers for me.
- [ ] **Check**: sit in or look at a car, press Check (or `heistflock_check_car`): every camera within range × 1.5 is listed in chat and on screen with distance and reason.
- [ ] **Send**: a test alert card and marker appear only for you (another player sees nothing).
- [ ] Diagnostics lists the last plates read; they match what you drove past.
- [ ] Settings → Plate scanning → "Head turns" set to 0: heads stay still and the fan narrows to the lens's own view.
- [ ] Change map with Scanner view on: it comes back on its own after the map loads.

## 6c. Other checks from the 0.9.1 review
- [ ] A Realistic Police plate on a police **alert card** matches the plate on the car.
- [ ] Diagnostics → Plate scanning scan times with many cameras and several cars (send me the numbers).
- [ ] A Lua refresh after updating the addon (or `lua_openscript` of the camera file) leaves no floating extra camera parts.

## 7. Permissions (SAM)
- [ ] A rank with only **HeistFlock View**: menu opens with Dashboard, Cameras, Diagnostics; no place/move/remove buttons; Settings and Access hidden.
- [ ] A rank with **HeistFlock Place**: can place, move, remove, reset and skip; no Settings page.
- [ ] Take a permission away in SAM while that player is on: within 15 s the menu loses it.
- [ ] A player with no Heist Flock permission: `!heistflock` says no permission.
- [ ] Diagnostics → Permissions shows SAM, CAMI yes, all three registered.

## 8. Logs and recovery
- [ ] Place, move (menu and physgun), remove, reset, skip, change a setting: each shows in Activity and Diagnostics → Recent events.
- [ ] Break `garrysmod/data/heistflock/config.json` on purpose (delete a bracket), restart: the server still loads and Diagnostics says the file was ignored.
- [ ] Copy report and paste it to me after the session, even if everything worked.

## 9. Disconnects
- [ ] A player leaves mid-smash, and one leaves with parts reserved for them: no errors, their parts become free.
- [ ] `heistflock_report` in the server console prints the report.
