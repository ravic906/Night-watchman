# Night Watchman

A top-down stealth/horror patrol game made in **Godot 4.3**. You are the night watchman of an old museum.
Your shift runs from 10 PM to 6 AM, and the building is not as empty as it should be.

Everything is drawn in code, so there are no image or sound assets.

## How to play
- **Do your rounds.** Punch all 5 clocks (red blinking lights) once before 2 AM, then again before 6 AM.
- **Stop the thieves.** You hear their footsteps as rings. They head for the valuables. Keep your flashlight on one until the ring fills to scare it off. Three thefts end your shift.
- **Watch your fear.** Darkness raises it. Your flashlight and the ceiling lamps calm you. At 100% you flee.
- **Save your battery.** Toggle the light off when you can. Green blinking pickups are spare batteries.
- **From Night 2: the Shadow.** You only ever see its red eyes. It cannot move while it is in your beam.

| Action     | Keyboard / mouse            | Touch                    |
|------------|-----------------------------|--------------------------|
| Move       | WASD / arrow keys           | Left-side joystick       |
| Aim        | Mouse (or direction you walk) | Direction you walk     |
| Run        | Shift                       | RUN                      |
| Flashlight | F / Space / right click     | LIGHT                    |
| Punch clock| Hold E                      | Hold PUNCH               |

There are three nights. Each one adds more thieves, a faster battery drain and more of the dark. Progress is saved.

## Running it
1. Install [Godot 4.3](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5** (Play).

Developer flags (put them after `--` on the command line):
- `--touch` shows the on-screen controls on desktop.
- `--autotest [--night=N]` runs a short, self-playing shift and quits. Use it as a smoke test:
  `godot --headless --path . res://scenes/game.tscn -- --autotest --night=2`
- `--screenshot=/path/shot.png` saves a frame after 3 seconds and quits.

## Exporting to mobile
The project already uses the mobile-friendly **Compatibility** renderer, a landscape orientation, a stretch mode that fits any screen, and touch controls that appear on touchscreen devices.

**Android**
1. In Godot: **Editor > Manage Export Templates > Download and Install**.
2. Install the Android SDK and a JDK 17, then set their paths in **Editor > Editor Settings > Export > Android**.
3. **Project > Export > Add... > Android**. Set a package name (e.g. `com.yourname.nightwatchman`), then export an APK (for testing) or an AAB (for Google Play).

**iOS**: requires a Mac with Xcode. Add an iOS preset in **Project > Export**, export the Xcode project, then build it in Xcode.

## Project layout
```
project.godot          settings (renderer, stretch, orientation, autoload)
scenes/                menu, game and end screen (each a root node + script)
scripts/
  game_state.gd        autoload: nights/difficulty, save data, input map, scene flow
  game.gd              one shift: clock, rounds, fear, spawns, events, win/lose
  level.gd             ASCII map -> walls, light occluders, A* grid, drawing
  player.gd            watchman movement, flashlight cone and battery
  flashlight.gd        light textures generated in code
  intruder.gd          thief AI (sneak -> steal -> escape / flee)
  shadow.gd            the Shadow (moves only when not lit)
  checkpoint.gd, valuable.gd, battery_pickup.gd, wall_lamp.gd
  hud.gd, touch_controls.gd, menu.gd, end_screen.gd
```
To change the building, edit the `MAP` grid in `scripts/level.gd`. The legend is at the top of that file.
To tune difficulty, edit `NIGHTS` in `scripts/game_state.gd`.
