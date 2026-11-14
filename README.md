# Night Watchman

A top-down stealth/horror patrol game made in **Godot 4.7.2**. You are a night watchman, and you pick where to work tonight.
Your shift runs from 10 PM to 6 AM, and the building is not as empty as it should be.

Everything is drawn in code, so there are no image files. The music is composed in code too.

## Locations
All four are open from the start. Each has its own layout, look and loot, plus one signature twist on top of the usual duties.

| Location | Twist |
|---|---|
| **Museum** | The classic shift: galleries, a vault and a basement. No extra twist. |
| **Apartment Block** | **Resident calls.** The intercom buzzes ("Flat 2B hears noises") and that flat's light flashes. Check it within 60 s. Some calls are false alarms; some have a thief inside. Three ignored calls and the residents get you fired. |
| **Shopping Mall** | **Shop shutters.** Valuables sit inside shops behind roll-down shutters. Close them all; thieves force them open (loud screech) to get in, and you can trap one inside a shop. |
| **Factory** | **Machinery.** Thieves switch machines on to drown out their footsteps (no sounds or rings near a running machine). After a minute a machine overheats and trips its wing's power. Shut it down at its panel. |

**Difficulty:** Easy, Normal or Hard (chosen in the menu). Harder means more and faster thieves, quicker battery drain, more fear in the dark, more sabotage, and the Shadow (Normal: one, Hard: two). Best scores are saved per location and difficulty.

## Duties and sabotage
Besides punching the clocks, the watchman has three more duties, and the thieves try to undo all of them:

| Duty | Where | What you do | What thieves do | While it's broken |
|---|---|---|---|---|
| Alarm | Panel in the lobby | Arm it (re-wire it if cut) | Cut the wires | Intruder count shows **??**, no break-in chimes |
| Power | Breaker box in the basement | Reset the breaker | Flip one wing's circuit | That wing's lamps are dark |
| Doors | The two outside doors | Lock them | Pick the lock; anyone leaving leaves it unlocked | Thieves walk straight in, and more often |
| Windows | Archive, Storage, Basement, Office | Board up a smashed one | Smash it (loud), or pry the boards off | Thieves slip in and out silently |
| Clocks | 5 punch clocks (hourly orders) | Punch the ordered ones | Jam them | Takes 3 s to fix and punch |

While the **alarm is armed**, the top-right panel shows exactly how many intruders are inside, and a chime plays at every break-in. Lose the alarm and you're guessing again.
Sabotage takes a thief a few seconds at the device, and you'll hear the work. Catch them in your beam to scare them off for a bonus.

**The night gets worse as it goes.** Thieves arrive more often and more can be inside at once after 2 AM and again after 4 AM, and at 4 AM a crew of 2–3 hits several entrances at once. Thieves go for the entrance farthest from you, and one you scare away from a door or window comes back once, somewhere else.

## Music
The score adapts to what is happening:
- a low drone and wind are always there; a music-box melody plays while things are calm
- a **heartbeat** fades in and speeds up as your fear rises
- dissonant tremolo **strings** and a ticking clock come in when the Shadow is close, a thief is nearby, or your battery is dying
- **sound effects**: the watchman's boots on the tiles (faster when running); thieves' soft sneaking steps, heard from the direction they're in; outside doors that creak when a thief comes in and slam when one leaves; and interior doors that swing when you walk through
- stingers play when you punch a clock, scare off a thief, lose an item, get touched by the Shadow, and when the shift ends

`tools/compose_music.py` composes every track and sound effect with numpy and writes them to `audio/*.ogg`. To change or regenerate the music, run `python3 tools/compose_music.py` (needs numpy and ffmpeg). The mixing logic is in `scripts/music.gd`. You can turn sound on or off from the main menu.

## How to play
The top-right **OBJECTIVES** box always shows your 3 most urgent jobs. Open it (Tab, or tap it) for the full, paused panel: **Objectives** (patrol orders, duties, tips), **Status** (intruders, thefts, score, lose conditions) and **Log** (every message so far). On your first shift it opens by itself.

- **Follow your patrol orders.** Every hour the radio names 2–3 clocks (red blinking lights) to punch before the next hour. Finish at least 60% of the night's orders or you're fired.
- **Stop the thieves.** You hear their footsteps as rings. They head for the valuables. Keep your flashlight on one until the ring fills to scare it off. Four thefts end your shift. Thieves carrying loot are slower, and while the alarm is armed it announces "footsteps heading for the west door" and points an arrow at them. A Shadow touch costs you 10 seconds of the current check and 100 points.
- **Watch your fear.** Darkness raises it. Your flashlight and the ceiling lamps calm you. At 100% you flee.
- **Save your battery.** Toggle the light off when you can. Green blinking pickups are spare batteries.
- **On Normal and Hard: the Shadow.** You only ever see its red eyes. It cannot move while it is in your beam.

| Action     | Keyboard / mouse            | Touch                    |
|------------|-----------------------------|--------------------------|
| Move       | WASD / arrow keys           | Left-side joystick       |
| Aim        | Mouse (or direction you walk) | Direction you walk     |
| Run        | Shift                       | RUN                      |
| Flashlight | F / Space / right click     | LIGHT                    |
| Use (punch, lock, arm, reset) | Hold E          | Hold USE                 |
| Pause / objectives panel | Tab, O or Esc; Left/Right switch tabs | Tap the OBJECTIVES box, or Back; tap outside to close |

Pick a location and a difficulty in the menu. Your choice and best scores are saved.

## Running it
1. Install [Godot 4.7.2](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5** (Play).

Developer flags (put them after `--` on the command line):
- `--touch` shows the on-screen controls on desktop.
- `--location=museum|apartment|mall|factory` and `--difficulty=easy|normal|hard` pick the shift (`--night=1..3` still works as a difficulty alias).
- `--autotest [--survive]` runs a self-playing shift (6x speed) and quits; `--survive` disables losing so the whole night plays out. Use it as a smoke test:
  `godot --headless --path . res://scenes/game.tscn -- --autotest --location=mall --difficulty=hard`
- `--screenshot=/path/shot.png` saves a frame after 3 seconds and quits.
- `--start-cell=X,Y` starts the watchman at that map cell.

## Automated playtesting
The game can be played by a script, which lets bots and test agents play the real game reproducibly:

```
godot --headless --fixed-fps 60 --path . res://scenes/game.tscn -- \
    --location=museum --difficulty=normal --seed=7 \
    --inputs=inputs.txt --snap=5,30,60 --until=60 --out=/tmp/run1 [--fast]
```

- `--seed=N` makes every run with the same inputs identical (use `--fixed-fps 60` too).
- `--inputs=FILE` holds one timed command per line, in game seconds (45 s = one in-game hour):
  `T move DX DY` (keep walking that way; `0 0` stops), `T aim DX DY`, `T hold use` / `T release use`,
  `T run on|off`, `T light` (toggle the flashlight). Lines starting with `#` are comments.
- `--snap=T1,T2,...` writes `state_T.json` (player, orders, duties, thieves, Shadow, messages) to `--out`,
  plus `shot_T.png` when rendering (run under `xvfb-run` without `--headless` for screenshots).
- `--until=T` stops at game time T; `--fast` runs at 4x speed.
- `--radio-hours=1|2` and `--rooms=1|2` override the patrol schedule; `--log-windows` prints one
  `WINDOW` line per radio check (rooms, slack, distance walked, break-ins, sabotage).

## Exporting to mobile
The project already uses the mobile-friendly **Compatibility** renderer, a landscape orientation, a stretch mode that fits any screen, and touch controls that appear on touchscreen devices.

**Android: install the ready-made APK**
Install `NightWatchman.apk` on your phone: open it from your downloads and allow "Install unknown apps" when Android asks. It needs Android 7.0 or newer (64-bit or 32-bit ARM).
That APK is **debug-signed**: fine for your own phones and testers, but not accepted by Google Play.

**Android: build it yourself**
1. In Godot: **Editor > Manage Export Templates > Download and Install**, then **Project > Install Android Build Template** (creates the git-ignored `android/` folder).
2. Install the Android SDK (build-tools 36.x, platform android-36) and a JDK 17+, and set their paths in **Editor > Editor Settings > Export > Android**.
3. Two presets are ready in `export_presets.cfg`:
   - **Android APK** – quick sideload build for testing: `godot --headless --path . --export-debug "Android APK" build/NightWatchman.apk`
   - **Android** – the Play Store bundle (Gradle, release): `godot --headless --path . --export-release "Android" build/NightWatchman.aab`

## Publishing to Google Play
Everything in the game is ready for review: it targets Android 16 (API 36), is 64-bit, 16 KB page-aligned, requests **no permissions**, collects **no data**, and downloads at about **28 MB** per phone. The store kit is in `store/`:
`listing.md` (title, descriptions, and answers for the content rating, target audience and Data safety forms), `icon_512.png`, `feature_1024x500.png` and six 1920×1080 screenshots. The privacy policy is `docs/privacy.html`.

1. **Developer account:** sign up at play.google.com/console (one-off US$25 fee, identity verification).
2. **Privacy policy URL:** in the repository settings on GitHub, turn on **Pages** for the default branch, folder `/docs`. The URL is `https://<your-user>.github.io/<repo>/privacy.html`. Put your contact email in `docs/privacy.html` and `store/listing.md` first (search for `[your contact email]`).
3. **Your upload key (keep it safe and backed up):**
   ```
   keytool -genkeypair -v -keystore nightwatchman-upload.keystore -alias upload \
       -keyalg RSA -keysize 2048 -validity 10000
   ```
   Then build the signed bundle (the password never goes into the project files):
   ```
   export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/nightwatchman-upload.keystore
   export GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload
   export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD='<your password>'
   godot --headless --path . --export-release "Android" build/NightWatchman.aab
   ```
   When Play Console asks, accept **Play App Signing**: Google keeps the app signing key, and a lost upload key can be reset.
4. **Create the app** in Play Console (name "Night Watchman", game, free) and fill in the store listing, content rating, target audience, Data safety and privacy policy from `store/listing.md`.
5. **Test before release:** upload the `.aab` to **Internal testing** first. New personal developer accounts must then run a **Closed test with at least 12 testers for 14 days** before they can apply for production. Read the **pre-launch report** (Google's automatic tests on real phones) and fix anything it flags.
6. **Release:** apply for production access, then promote the tested build. For updates, raise `version/code` (and `version/name`) in both presets.
7. The package name `com.nightwatchman.game` becomes permanent with the first upload – change it in both presets before then if you want your own name in it.

## Quality checklist
What was verified before release (re-run these after changes):

| Area | Check | How |
|---|---|---|
| Standards | Pauses on phone calls / home button; Back opens the pause menu (asks before quitting on the title screen); HUD and controls avoid notches | Lifecycle test scene; `--safe-inset=48 --touch` screenshots |
| Standards | Release bundle: valid, not debuggable, no permissions, 16 KB aligned | `bundletool validate`, `aapt dump badging`, `zipalign -c -P 16` |
| Bugs | Zero script errors across all locations × difficulties × seeds, normal + survive + random-input "monkey" runs; watchdog for stuck thieves / anyone inside a wall | `--autotest [--survive]`, harness with random inputs |
| Bugs | No leaks over 10 shifts in one session (nodes, objects, memory flat) | Soak test scene |
| Performance | ~90 draw calls per frame (was ~1,800); lamp shadows only near the player; 60 FPS cap in shifts, 30 FPS in menus | Harness `perf` in snapshots |
| Polish | Tutorial, settings (volume, shadows, vibration), stars on the end screen, fades, shake/vibration | Screenshots in `store/` |

**iOS**: requires a Mac with Xcode. Add an iOS preset in **Project > Export**, export the Xcode project, then build it in Xcode.

## Project layout
```
project.godot          settings (renderer, stretch, orientation, autoload)
scenes/                menu, game and end screen (each a root node + script)
audio/                 music loops and stingers (generated by tools/compose_music.py)
scripts/
  game_state.gd        autoload: locations, difficulty, save data, input map, scene flow
  maps/                one file per location (layout, names, theme, twist); map_def.gd has the legend
  shutter.gd, call_spot.gd, machine.gd   location twists
  music.gd             autoload: adaptive music layers + stingers
  game.gd              one shift: clock, rounds, fear, spawns, events, win/lose
  level.gd             ASCII map -> walls, light occluders, A* grid, drawing
  player.gd            watchman movement, flashlight cone and battery
  flashlight.gd        light textures generated in code
  intruder.gd          thief AI (pick lock -> sabotage? -> sneak -> steal -> escape / flee)
  alarm_panel.gd, breaker_box.gd, outside_door.gd, window.gd   sabotageable duties / entrances
  shadow.gd            the Shadow (moves only when not lit)
  checkpoint.gd, valuable.gd, battery_pickup.gd, wall_lamp.gd
  hud.gd, touch_controls.gd, menu.gd, end_screen.gd
```
To change a building or add a new location, edit or copy a file in `scripts/maps/` (the tile legend is in `map_def.gd`) and add its id to `LOCATIONS` in `scripts/game_state.gd`.
To tune difficulty, edit `DIFFICULTY` in `scripts/game_state.gd`.
