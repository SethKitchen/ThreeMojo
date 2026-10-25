# Village walk

`VillageGame` puts people and animals in the [Village](Village), and lets a player walk, run and jump through it. A third-person camera follows the player. A gamepad or the keyboard moves the player.

![Seen from behind, a man walks past a pond and a dog, then runs, jumps and looks round, while cows graze](out/village_walk.png)

`examples/village_walk.mojo` draws this picture. A gamepad of the web backend plays a fixed script. The modules live in `extensions/village/` and `controls/`. See [Gamepads](Gamepads) and [Game humanoid](Game-humanoid).

## Play the game

The game needs an X11 window. Linux has one. Windows under WSL 2 with WSLg and macOS with XQuartz have one too.

```sh
mojo run -I . examples/village_walk.mojo --play
mojo run -I . examples/village_walk.mojo --play 640 360
```

The window is 480 by 270 pixels by default. Give a width and a height for a different size. The game reads every gamepad on the machine, and the keyboard:

| Control | Gamepad | Keyboard |
|---|---|---|
| Move | Left stick, or the d-pad | `W`, `A`, `S`, `D` |
| Look | Right stick | The arrows |
| Run | Hold the right trigger, the east button or the left stick | Hold Shift, or `R` |
| Jump | The south button | Space |
| Quit | The start button | Escape or `q` |

The buttons are named by position, as SDL names them. The south button is A on an Xbox controller and the cross on a PlayStation controller.

The game builds for about 25 seconds before the window opens. On a four-core Linux host, a frame at 480 by 270 takes about 3 seconds on the CPU. The game moves by the time each frame takes. So the player crosses the village at a walking pace, in large steps.

The game prints the frames a second to the standard error.

## Run the game loop in code

```mojo
from core.assets import Assets
from core.scene import Scene
from extensions.vegetation.meadow import meadow_renderer
from extensions.village.character import MoveInput
from extensions.village.play import PlayParameters, VillageGame
from extensions.water.pebbles import pebble_bed
from render.jpeg import decode
from std.pathlib import Path
from units.si import SECOND, Duration

var renderer = meadow_renderer(480, 270)
var assets = Assets()
var scene = Scene()
var bed = pebble_bed(decode(Path("assets/pebbles.jpg").read_bytes()))
var game = VillageGame(scene, assets, renderer, PlayParameters(), bed^, None)
var ahead = MoveInput(1, 0, 0, 0, False, False)
_ = game.tick(scene, assets, ahead, Duration(0.1, SECOND))
var image = game.render(renderer, scene, assets)
```

`tick` runs one frame of the game. Call it once each frame with the frame's input and its time. Then call `render`.

To read a gamepad, give its `Gamepad` to `gamepad_input`. To read the keyboard, give the held keys to `keyboard_input`. `combined` adds two inputs:

```mojo
from extensions.village.pad_input import combined, gamepad_input, keyboard_input

var input = combined(gamepad_input(pad), keyboard_input(keys, shift))
```

## One frame

`tick` does these steps in this order:

1. The look stick turns the camera round the player.
2. The player's `Character` steps by the move stick. Forward is the way the camera looks.
3. While the player moves and the look stick rests, the camera turns behind the player.
4. The player's `Body` stands where the character stands, and plays the clip of its stance.
5. Each resident steps along its route, and its body or its mesh is posed.
6. The camera's focus follows the player. The eye stays above the ground.
7. The village grows the grass for the camera, and moves the water's clock on.

## The parts

| Module | Holds |
|---|---|
| `controls/third_person_controls.mojo` | `ThirdPersonControls`, `ground_direction`, `yaw_of`, `wrap_angle` and `turn_toward`. |
| `character.mojo` | `Stance`, `MoveInput`, `Obstacle`, `CharacterParameters`, `Character`, `lot_push` and `obstacle_push`. |
| `pad_input.mojo` | `stick`, `gamepad_input`, `keyboard_input` and `combined`. |
| `residents.mojo` | `Body`, `Route`, `wander_route`, `Villager`, `Herd`, `ResidentsParameters`, `Flipbook` and `Residents`. |
| `play.mojo` | `play_village`, `default_residents`, `PlayParameters`, `tree_obstacles` and `VillageGame`. |

## The character

`Character.step` moves a character by one frame. It cuts the frame into steps of at most 1/60 second. A frame longer than 1 second counts as 1 second.

| Property | Default |
|---|---|
| Walking speed | 1.4 meters a second, at a full lean of the stick. |
| Running speed | 4.5 meters a second, while the run button is held. |
| Acceleration | 14 meters a second squared on the ground, and 30 percent of that in the air. |
| Turning speed | 600 degrees a second, toward the way the character moves. |
| Jump | 4.2 meters a second up, under standard gravity: about 0.9 meters high. |
| Radius | 0.3 meters. |
| Wade depth | 0.5 meters of water. |
| Step down | 0.4 meters. A larger drop under one step starts a fall. |
| Bounds | 250 meters from the middle. |

A jump starts only on a new press of the jump button. Hold the button and the character jumps once.

These things stop a character:

- **A house.** `lot_push` moves the character out of each `Lot` by the shortest way.
- **A tree or a resident.** `obstacle_push` moves the character straight away from each `Obstacle`. `tree_obstacles` gives each planting a trunk of 0.35 meters times its size.
- **Deep water.** The character does not step where the water is deeper than the wade depth.
- **The bounds.** The character stays within the bounds.

Where a step is refused, the character slides along the edge if it can.

`Stance` is `STANDING`, `WALKING`, `RUNNING` or `AIRBORNE`. A character in the air is airborne. On the ground, a character below 0.15 meters a second is standing, and one above 1.15 times the walking speed is running.

## The camera

`ThirdPersonControls` looks at a focus 1.45 meters above the player's feet. The eye stands 4 meters back along the look.

| Property | Default |
|---|---|
| Pitch | -15 degrees, from -70 to 25 degrees. |
| Look speed | 150 degrees a second of yaw, and 90 of pitch, at a full lean of the look stick. |
| Trail speed | 60 degrees a second at the running speed, and less at a slower speed. |
| Follow rate | 10 a second. Each second, the focus closes all but `exp(-10)` of its gap to the player. |
| Clearance | 0.3 meters above the ground under the eye. |

The yaw is the way the camera looks, about +y. Yaw 0 looks toward -z. `ground_direction` turns a yaw and the two leans of a stick into a direction on the ground.

## The residents

`default_residents` puts these residents in the default village:

| Residents | Where they wander |
|---|---|
| A woman of 65 inches | By the brick house. |
| A man of 70 inches | Along the trail. |
| A child of 50 inches, who runs | Round the pond. |
| Four sheep and a goat | Right of the trail. |
| Two cows and a horse | Left of the trail. |
| A pig | By the barn. |
| A dog | Near the start. |
| Two rabbits | By the trail. |
| Two deer | Past the pond. |

Each resident walks a `Route`. It walks to a point, rests there for 3 seconds, and walks on to the next point. `wander_route` scatters the points round a middle. It does not put a point on or near a lot, or under the water.

**A person** is a `Body`: a game humanoid of 3,000 triangles, with its idle, walk, run and jump clips. The body fades to the clip of its stance in 0.2 seconds. The walk and the run play from 0.6 to 1.6 times their own rate, by the speed. So the feet keep pace with the ground. A jump plays from the moment the feet leave the ground. The player is a `Body` too.

**An animal** is a flipbook: its mesh in six poses of its walk, and one mesh standing. The mesh shows the pose of how far the animal has walked, so one stride covers one stride of ground. An animal walks at its stride times its stride frequency at a Froude number of 0.25. An animal that does not walk on four legs keeps its standing mesh.

## The lighter village

`play_village` changes the default village so a frame draws in about 3 seconds instead of 20:

| Part | Default village | Game village |
|---|---|---|
| Tree leaves | Every leaf to 40 meters | 35 percent to 20 meters, then cards |
| Grass | 700 blades a square meter, to 85 meters | 200 blades a square meter, to 40 meters |
| Ground litter | 160,000 tries | 20,000 tries |
| Ground mesh | 512 cells on a side | 128 cells on a side |
| Sky and water textures | 512 and 256 texels | 256 and 64 texels |

## Limits

- The renderer draws on the CPU. A frame takes seconds, not milliseconds.
- The people have no clothes. The game humanoid has none.
- The characters do not swim. Deep water stops them.
- Residents do not bump into each other. Each resident bumps into the trees and the player.
- An animal slides across the ground while it turns on the spot.
- The camera does not move in front of a wall or a tree that hides the player.
