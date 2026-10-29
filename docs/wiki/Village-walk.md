# Village walk

`VillageGame` puts people and animals in the [Village](Village), and lets a player walk, run and jump through it, and into its houses. A third-person camera follows the player. A gamepad or the keyboard moves the player.

![Seen from behind, a man in a red tunic walks past a pond and a stone cottage, then runs, jumps and looks round](out/village_walk.png)

`examples/village_walk.mojo` draws this picture. A gamepad of the web backend plays a fixed script. The modules live in `extensions/village/` and `controls/`. See [Gamepads](Gamepads) and [Game humanoid](Game-humanoid).

## Play the game

The game needs an X11 window. Linux has one. Windows under WSL 2 with WSLg and macOS with XQuartz have one too.

```sh
mojo run -I . examples/village_walk.mojo --play
mojo run -I . examples/village_walk.mojo --play 1280 720 medium
```

The window is 1920 by 1080 pixels by default. Give a width and a height for a different size. After the size, give a quality: `low`, `medium`, `high` or `ultra`. The default is `low`. See [Game renderer](Game-renderer). The game reads every gamepad on the machine, and the keyboard:

| Control | Gamepad | Keyboard |
|---|---|---|
| Move | Left stick, or the d-pad | `W`, `A`, `S`, `D` |
| Look | Right stick | The arrows |
| Run | Hold the right trigger, the east button or the left stick | Hold Shift, or `R` |
| Jump | The south button | Space |
| Use | The west button | `E` |
| Weather | | `1` clear, `2` overcast, `3` rain, `4` fog |
| Time | | `5` moves the day on three hours |
| Quit | The start button | Escape or `q` |

The buttons are named by position, as SDL names them. The south button is A on an Xbox controller and the cross on a PlayStation controller.

The game builds for about 15 seconds before the window opens. On a four-core Linux host, the `low` quality draws about 34 frames a second at 1920 by 1080 on the CPU. The game moves by the time each frame takes. So a slow frame moves the player as far as many quick frames do.

The game prints the frames a second to the standard error.

## Run the game loop in code

```mojo
from core.assets import Assets
from core.scene import Scene
from extensions.village.character import MoveInput
from extensions.village.play import PlayParameters, VillageGame
from extensions.village.quality import LOW, game_quality
from extensions.water.pebbles import pebble_bed
from render.jpeg import decode
from renderers.renderer import Renderer
from std.pathlib import Path
from units.si import SECOND, Duration

var painter = Renderer(64, 64)
var assets = Assets()
var scene = Scene()
var bed = pebble_bed(decode(Path("assets/pebbles.jpg").read_bytes()))
var parameters = PlayParameters(game_quality(LOW))
var game = VillageGame(
    scene, assets, painter, parameters, bed^, None, 1920, 1080
)
var ahead = MoveInput(1, 0, 0, 0, False, False)
_ = game.tick(scene, assets, ahead, Duration(0.1, SECOND))
game.render(scene, assets)
var image = game.window.pixels.copy()
```

`tick` runs one frame of the game. Call it once each frame with the frame's input and its time. Then call `render`. `render` draws the frame into `window`, the window's size. The meadow paints its sky with `painter` once, when the game is built.

To read a gamepad, give its `Gamepad` to `gamepad_input`. To read the keyboard, give the held keys to `keyboard_input`. `combined` adds two inputs:

```mojo
from extensions.village.pad_input import combined, gamepad_input, keyboard_input

var input = combined(gamepad_input(pad), keyboard_input(keys, shift))
```

## One frame

`tick` does these steps in this order:

1. The look stick turns the camera round the player.
2. The player's `Character` steps by the move stick, on the village's `Terrain`. Forward is the way the camera looks.
3. While the player moves and the look stick rests, the camera turns behind the player.
4. The player's `Body` stands where the character stands, and plays the clip of its stance.
5. Each resident steps along its route, and its body or its mesh is posed.
6. Each door swings open while someone stands near it, and shut after.
7. The use button uses the spot in reach: see [Village gathering](Village-gathering). With no spot in reach, it talks to the villager in reach: see [Village errands](Village-errands).
8. The camera's focus follows the player. The eye comes in before a wall, and stays below a ceiling and above the ground. The inside of each house hides while the eye is more than `INSIDE_REACH`, 18 meters, past the house's edge. The fireflies and the butterflies fly on: see [Village critters](Village-critters).
9. The village grows the grass for the camera, and moves the water's clock on.
10. The weather moves on, and scales the lights and the fog. See [Village weather](Village-weather). The day moves on, and dims and tints them for the hour. See [Village day and night](Village-day).

## The parts

| Module | Holds |
|---|---|
| `controls/third_person_controls.mojo` | `ThirdPersonControls`, `ground_direction`, `yaw_of`, `wrap_angle` and `turn_toward`. |
| `character.mojo` | `Stance`, `MoveInput`, `Obstacle`, `CharacterParameters`, `Character`, `lot_push` and `obstacle_push`. |
| `terrain.mojo` | `WallSpan`, `Floor`, `Terrain`, `wall_push` and `view_entry`. See [Village houses](Village-houses#where-a-character-can-walk). |
| `clothes.mojo` | The natural dyes, `natural_dye`, `village_outfit` and `dyed_outfit`. |
| `pad_input.mojo` | `stick`, `gamepad_input`, `keyboard_input` and `combined`. |
| `gathering.mojo`, `hud.mojo` | What the player gathers, and the heads-up display. See [Village gathering](Village-gathering). |
| `talk.mojo` | The villagers who talk, and their errands. See [Village errands](Village-errands). |
| `weather.mojo` | The clouds, the rain and the fog. See [Village weather](Village-weather). |
| `day.mojo` | The hour, the night's light and its sky. See [Village day and night](Village-day). |
| `skills.mojo` | The player's foraging, mining and fishing levels. See [Village skills](Village-skills). |
| `critters.mojo` | The fireflies and the butterflies. See [Village critters](Village-critters). |
| `residents.mojo` | `Body`, `Route`, `wander_route`, `visit`, `Villager`, `Herd`, `ResidentsParameters`, `Flipbook` and `Residents`. |
| `play.mojo` | `default_residents`, `PlayParameters`, `tree_obstacles` and `VillageGame`. |
| `quality.mojo` | `QualityPreset`, `PlantDetail`, `GameQuality`, `game_quality` and `planted`. See [Game renderer](Game-renderer). |

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

- **A wall.** `wall_push` moves the character straight away from each `WallSpan` that overlaps the 1.5 meters over its feet. A door's gap lets it into a house. The span over the door stands too high to stop it. A railing and a piece of furniture are spans too, so a piece upstairs does not stop a character on the floor below.
- **A solid lot.** `lot_push` moves the character out of each solid `Lot` by the shortest way. A well, a barrel and a scanned building are solid lots.
- **A tree or a resident.** `obstacle_push` moves the character straight away from each `Obstacle`. `tree_obstacles` gives each planting a trunk of 0.35 meters times its size.
- **Deep water.** The character does not step where the water is deeper than the wade depth.
- **The bounds.** The character stays within the bounds.

Where a step is refused, the character slides along the edge if it can.

The feet follow `Terrain.height_at`: the highest floor under them that they can reach, or the ground. Feet reach a floor at most `CLIMB`, 0.45 meters, above them. A higher floor, such as an upper storey, passes over them. A house's floor, the steps to its door and each tread of its stair are floors. So the character climbs the steps, walks on the floor, and goes up the stair one tread at a time. A floor stands over water, so a character does not wade on it.

`Stance` is `STANDING`, `WALKING`, `RUNNING` or `AIRBORNE`. A character in the air is airborne. On the ground, a character below 0.15 meters a second is standing, and one above 1.15 times the walking speed is running.

## The camera

`ThirdPersonControls` looks at a focus 1.45 meters above the player's feet. The eye stands 4 meters back along the look.

| Property | Default |
|---|---|
| Pitch | -15 degrees, from -70 to 25 degrees. |
| Look speed | 150 degrees a second of yaw, and 90 of pitch, at a full lean of the look stick. |
| Trail speed | 60 degrees a second at the running speed, and less at a slower speed. |
| Follow rate | 10 a second. Each second, the focus closes all but `exp(-10)` of its gap to the player. |
| Clearance | 0.3 meters above the ground under the eye. Below the ceiling over the focus, and indoors below the ceiling over the eye too. |
| Arm | The eye stops 0.3 meters before the first wall between it and the focus. It goes back out at a rate of 3 a second. |

The yaw is the way the camera looks, about +y. Yaw 0 looks toward -z. `ground_direction` turns a yaw and the two leans of a stick into a direction on the ground.

`Terrain.view_reach` finds how much of the way from the focus to the eye is clear of the walls. `place_within` then stands the camera that share of the way out, below the ceilings that `Terrain.view_ceiling` gives. Each is the ceiling over the floor that the player's feet reach there. Under a ceiling, the eye stays below that ceiling and below the one over itself. So in a room, the camera stays in the room.

Under the open sky, a house's ceiling under the eye does not hold it. A sight line that clears the walls passes over their tops, so the eye looks down on the roof. Four points along the camera's last sight hold a door open, so the camera can look through it.

## The residents

`default_residents` puts these residents in the default village:

| Residents | Where they wander |
|---|---|
| A woman of 65 inches, in a hooded green tunic | By the brick house, which she visits. |
| A man of 70 inches, in a blue tunic | Along the trail. He visits the stone cottage. |
| A child of 50 inches, in a yellow tunic, who runs | Round the pond. |
| A man of 67 inches, in a hooded gray tunic | By the framed cottage, which he visits. |
| A woman of 64 inches, in a red tunic | By the framed house, which she visits. |
| Four sheep and a goat | Right of the trail. |
| Two cows and a horse | Left of the trail. |
| A pig | By the barn. |
| A dog | Near the start. |
| Two rabbits | By the trail. |
| Two deer | Past the pond. |

Each resident walks a `Route`. It walks to a point, rests there for 3 seconds, and walks on to the next point. `wander_route` scatters the points round a middle. It does not put a point on or near a lot, or under the water. A resident that stays slower than 0.1 meters a second for 2.5 seconds gives up on its point, and rests as if it had arrived.

A villager with a home visits it. `Villager.home` is a `HouseId`, the house's place among the village's houses, or `NO_HOUSE`. `visit` adds five points to the end of the route. They stand 3.2 meters before the home's front door, 1 meter before it, and 1.8 meters inside it, and then back out the same way. The door opens as the villager comes near.

Each resident bumps into the trees, the player and every other resident. A resident that moved this frame is an obstacle where it stands now.

**A person** is a `Body`: a game humanoid of 3,000 triangles, dressed in its `Outfit`, with its idle, walk, run and jump clips. The body fades to the clip of its stance in 0.2 seconds. The walk and the run play from 0.6 to 1.6 times their own rate, by the speed. So the feet keep pace with the ground. A jump plays from the moment the feet leave the ground. The player is a `Body` too.

**An animal** is a flipbook: its mesh in six poses of its walk, and one mesh standing. The mesh shows the pose of how far the animal has walked, so one stride covers one stride of ground. An animal walks at its stride times its stride frequency at a Froude number of 0.25. An animal that does not walk on four legs keeps its standing mesh.

**A shy animal** runs from the player. `Herd.flee` is how near the player can come before the herd runs, a `Length`. Zero, the default, is tame. An animal nearer than that runs straight away from the player, at three times its walk, and its flipbook plays faster. It walks back to its route once the player is further away. The deer run from 12 meters, the rabbits from 6, the sheep from 3 and the goat from 2.

## Clothes

Every person of the village is dressed, and so is the player. `village_outfit` gives a linen shirt, wool hose, a wool tunic, leather boots and, if asked, a wool hood. The tunic, its trim and the hose take the dyes that you give. `dyed_outfit` picks three different dyes by a seed. `Body` dresses the person with `dress` from [Outfits and armor](Outfits-and-armor). Each garment is a skinned mesh on the person's skeleton, and casts a shadow.

| Dye | From |
|---|---|
| `MADDER` | Madder red |
| `WOAD` | Woad blue |
| `WELD` | Weld yellow |
| `WALNUT` | Walnut brown |
| `NETTLE` | Nettle green |
| `GRAY_WOOL`, `CREAM_WOOL` | Undyed wool |

The player wears a madder-red tunic trimmed in weld yellow, over walnut hose. `PlayParameters.outfit` holds the player's clothes. An empty `Outfit` leaves a person bare.

## The lighter village

`planted` changes the default village to the quality's plant detail. This table compares the default village with `FEWEST_PLANTS`, the `low` detail:

| Part | Default village | `FEWEST_PLANTS` |
|---|---|---|
| Tree leaves | Every leaf to 40 meters | Cards of 8 percent of the leaves to 20 meters, and fewer past that |
| Grass | 700 blades a square meter, to 85 meters | 120 blades a square meter, to 30 meters |
| Ground litter | 160,000 tries | 8,000 tries |
| Ground mesh | 512 cells on a side | 96 cells on a side |
| Sky and water textures | 512 and 256 texels | 256 and 64 texels |

## Limits

- The game renderer lights each vertex, not each pixel. See [Game renderer](Game-renderer#why-it-agrees-with-renderer).
- A garment bends with the skin. It does not swing as cloth does.
- The characters do not swim. Deep water stops them.
- A resident walks straight to its next point. It does not find a way round a house: it slides along the wall, or gives up.
- An animal slides across the ground while it turns on the spot.
- The camera comes in before a wall, but not before a tree or a roof.
