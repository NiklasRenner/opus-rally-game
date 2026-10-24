# Retro Rally (Godot 4 prototype)

Late-90s arcade rally in the spirit of Sega Rally / Colin McRae: chunky
640x360 render, nearest-filtered procedural textures, low-poly car and
scenery, arcade HUD. Everything (track, cars, textures, sky, engine sound) is
generated in code, except four vehicles modelled in Blender: the Martello HF,
the Pleiad 555, the Veloce F1 and the KPz Pardel tank (sources in `art/`,
exported to `models/*.glb`). The three cars wear pixel-art skins from
`models/`; the tank is painted in code at startup.

## Open and play

1. Install Godot **4.3 or newer** (standard build, no .NET needed).
2. Godot Project Manager > **Import** > pick `project.godot` in this folder.
3. Press **F5** (Run Project). First launch takes a few seconds to build the stage.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Throttle | W / Up | RT or A |
| Brake / reverse (hold when stopped) | S / Down | LT or X |
| Steer | A D / Left Right | Left stick, d-pad |
| Handbrake | Space | B |
| Change camera (Chase, Far chase, Hood, Bumper, TV) | C | Y |
| Reset onto road | R | Back |
| Repair car | T | |
| Arcade / modern lighting | F2 | |
| Pause / back | Esc | Start |

The same list is in the game: Esc > CONTROLS.

## Menu, records and ghosts

The game starts on the main menu. Pick a **stage**, a **car**, the number of
**laps** (1, 3 or 5), whether to race your **ghost** and the **weather**
(random, clear or rain), then START RACE. Random is rolled again for every
race from the menu (a restart keeps the same weather).

- **Highscores:** the top 5 race times for each stage and lap count, plus the
  best lap for each stage. Make the top 5 and you enter arcade-style initials:
  up/down changes the letter, left/right moves, Enter confirms, or just type
  the letters.
- **Ghosts:** your fastest race on each stage and lap count is recorded and
  shows up as a see-through car next time. At every lap line you get a split
  against it: green `-0.85` means you're ahead, red `+1.20` means behind.
  It also shows as a blinking cyan dot on the minimap.
- **Pause** with Esc or Start: resume, restart, see the controls, or go back to
  the menu.
- Everything is saved in Godot's user folder. On Windows that's
  `%APPDATA%\Godot\app_userdata\Retro Rally\` (`records.json`, plus
  `ghosts/*.ghost`). Delete those files to reset your records.

## Cars

| Car | Style | Handling |
|---|---|---|
| Martello HF | Boxy Delta-style hatch with flared arches, Martini-style stripes | All-rounder |
| Pleiad 555 | Blue Impreza-style saloon, gold wheels, bonnet scoop, big wing | Most grip, a bit less power |
| Kaze GT4 | Red fastback coupe | Most power, heaviest |
| Falke RS | White, big whale-tail wing | Stable, slightly grippier |
| Cuneo Stradale | Short wedge, green nose | Lightest, sharpest turn-in, least grip |
| Kart 125 | Go-kart with the driver out in the open | Tiny and twitchy: quickest turn-in, about 110 km/h flat out |
| Veloce F1 | Modern single-seater: halo, sidepods, multi-element wings, black with red and silver | About 225 km/h, fierce acceleration, downforce gives more grip the faster it goes; hopeless off the tarmac |
| KPz Pardel | Boxy German-style tank in NATO camo, wedge turret, stabilised gun | Just for fun: slow, grippy, pivots on the spot, shrugs off most damage; skirts, lights and the turret basket get knocked off |

The rally cars are kept close (a few percent) so times stay comparable; the
kart, F1 and tank are the odd ones out. The menu bars compare acceleration,
top speed, grip and turn-in across the whole garage.
Chassis forces (springs, brakes, steering assists) scale with each vehicle's
mass so a 300 kg kart and a 1800 kg tank both ride and turn sensibly; engine
power doesn't, so weight still counts.
Most cars are a side profile plus livery in `scripts/cars.gd`; `CarModel`
lofts it into a dentable low-poly body. Copy an entry to add a car.

The modelled cars come from `art/cars/build_cars.py`: run it in Blender's
Scripting tab (with `build_all("<path to this folder>")`) to rebuild their
.blend files and re-export `models/martello.glb`, `models/pleiad.glb` and
`models/veloce.glb` (the F1 car).

All three wear a skin painted in separate panel pieces (each side, top, front,
back, windscreen) in `art/cars/<car>_pieces/`, combined into
`models/<car>_skin.png`. `python art/cars/paint_skin.py <car>` recombines the
pieces (needs Pillow), so you can retouch any piece in a pixel editor such as
LibreSprite, Krita or GIMP and run it again; `--repaint` paints the pieces
from scratch. The builder writes `art/cars/<car>_layout.json` with every
face's outline in the skin.

The tank lives in `art/tank/`.

## Stages

| Stage | Length | Character |
|---|---|---|
| Col de Pixel | 2.6 km | Mixed: tarmac village, gravel forest with a jump, tarmac mountain hairpins |
| Pine Forest | 1.5 km | Gravel: fast and flowing through dense forest, two crests |
| Old Town | 1.1 km | Tarmac: tight town corners lined with houses and walls |
| Spa F1 | 3.1 km | Spa-Francorchamps: La Source, down to Eau Rouge and up Raidillon, the Kemmel straight, Les Combes, Bruxelles, a wet Pouhon, Stavelot, Blanchimont and the Bus Stop. Kerbs, armco and the Ardennes forest |
| Jungle Temple | 2.1 km | Gravel and mud through dense rainforest (palms, vine-hung giants, ferns), over a plank bridge, through a river ford that slows you right down, past overgrown temples and a stepped pyramid |
| Monaco Ruins | 3.2 km | The Monaco GP street circuit after a nuclear war: Sainte Devote, Casino Square, the Grand Hotel hairpin, a half-collapsed tunnel, the chicane, the flooded swimming pool section and La Rascasse, past bombed-out blocks, wrecks and a toxic harbour |

Stages are defined in `scripts/maps.gd`: a list of route points, surface
sections, elevation keyframes, jumps, a village range and forest density.
Copy an entry to make a new stage. Optional keys add a `theme` ("wasteland"
swaps the sky, houses, trees, barriers and cones; "jungle" brings palms,
temples and log barriers; "circuit" adds kerbs and armco), a `tunnel`,
`water` areas (route sections on "ford" dip under the water, sections on
"wood" become a bridge over it) and a `landmark` pyramid.

## Weather and tyre marks

- **Rain**: every surface loses grip (tarmac the most, about a quarter),
  roads go dark and shiny, all four tyres throw spray, rain streaks fall
  around the camera and the sky closes in. Headlights come on.
- **Tyre marks** (`scripts/skid_marks.gd`): sliding or spinning tyres leave
  black rubber on tarmac; gravel gets dug into ruts with ridges of thrown-up
  stones (a faint track even when you're just driving through, deep grooves
  when you drift); grass and mud get brown mud tracks; ice gets white
  scratches. The tank chews up everything.

## The stage: Col de Pixel

A 2.6 km closed loop, roughly 1:45 a lap: tarmac start straight and a village
chicane, a gravel forest run with a tight hairpin and a crest jump, tarmac
mountain hairpins climbing to 22 m, then gravel back down to the finish.
Stone walls line the tarmac corners and hay bales line the gravel, with
chevrons, houses, crowds at the hairpins and the jump, and grass shoulders.
The terrain follows the road's elevation. The surface table
(`scripts/surfaces.gd`) also has wet, ice, grass, mud, river (ford) and wooden
bridge surfaces.

## Handling model (v2)

Based on how arcade rally games and classic game car-physics write-ups do it:

- **Slip-angle tyres** (Marco Monster's "Car Physics for Games", simplified
  Pacejka): sideways force climbs steeply to a peak at a few degrees of slip,
  then falls off to a fraction of the peak, so slides are progressive and
  holdable rather than on/off. Tarmac peaks early and hard (crisp), gravel
  later and softer (floaty, drifty).
- **Weight transfer**: braking or lifting off moves grip to the front and
  takes it from the rear, accelerating does the opposite. Lift or brake into a
  corner and the tail comes round (lift-off oversteer / Scandinavian flick);
  engine braking makes lifting off count.
- **Arcade layer** (the Sega Rally approach: slides are part of going fast,
  and you don't get punished with an instant spin): a yaw-rate assist turns
  the car as much as the stick asks, within what the surface can plausibly
  give. Counter-steer catches slides, a drift-angle cap stops held slides
  from becoming spins, and the handbrake pivots the car for hairpins.
- Faster steering input (full lock in about 0.12 s on keys) and more lock at
  speed.

Measured against v1 (60 km/h step steer on a flat pad): yaw response about
35% quicker (90% in 0.13 s vs 0.20 s); full-lock rotation +20% on tarmac and
+30% on gravel; a 1 s handbrake turn at 45 km/h on gravel goes from 38 deg
to about 100 deg.

## Also in it

- **Damage** (`scripts/car_model.gd`): panels dent where hit and scuff;
  bumpers, the light pod, mirrors and the rear wing fall off. Front damage
  costs power and makes the engine smoke, side damage pulls the steering.
- **Cameras** (`scripts/camera_rig.gd`): chase, far chase, hood, bumper,
  trackside TV.
- **HUD** (`scripts/hud.gd`): total, lap and best times, a start-to-goal
  progress bar, tach with redline, gear, big italic speed, a minimap coloured
  by surface, and a damage diagram. A synthesised engine and skid sound is in
  `scripts/engine_audio.gd`.

## Tuning tips

- Surface feel: edit the table in `scripts/surfaces.gd`.
- Car power, gearing, steering, suspension, assists: constants at the top of
  `scripts/car.gd` (`YAW_ASSIST` = how eagerly it turns, `WEIGHT_TRANSFER`,
  `DRIFT_CAP`, `STEER_LOW/HIGH`).
- Stage layouts: `scripts/maps.gd`.
- Pixel chunkiness: `display/window/size/viewport_width/height` in Project
  Settings (480x270 is chunkier, 960x540 is cleaner).
