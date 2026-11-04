# Village walk

`VillageGame` puts people and animals in the [Village](Village), and lets a player walk, run and jump through it, and into its houses. A third-person camera follows the player. A gamepad or the keyboard moves the player.

![Seen from behind, a man in a red tunic walks past a pond and a stone cottage, then runs, jumps and looks around](out/village_walk.png)

`examples/village_walk.mojo` draws this picture. A gamepad of the web backend plays a fixed script. The modules live in `extensions/village/` and `controls/`. See [Gamepads](Gamepads) and [Game humanoid](Game-humanoid).

## Play the game

The game runs in a macOS window or in an X11 window. Both read the keys of the table below.

### On a Mac

The macOS window needs no XQuartz. It needs macOS 14 or later, and the Xcode command line tools.

```sh
examples/capi/run.sh native village
examples/capi/run.sh native village 1280 720 --quality low
```

The script builds the game first. The window is 1280 by 720 points by default. Give a width and a height for a different size. `--quality` takes `low`, `medium`, `high` or `ultra`. The default is `medium`. See [Game renderer](Game-renderer).

The game builds the village for about 10 seconds. Then the window shows its first frame.

A Retina display has two pixels for each point. The game draws a frame of the display's own pixels, so the picture is sharp. A window of 1280 by 720 points shows a frame of 2560 by 1440 pixels. On a Mac with 16 cores, `low` draws that frame at 74 frames a second and `medium` at 39. `high` draws 15 frames a second, and `ultra` draws 4.

`--scale 1` draws a frame of the window's own size. `medium` then draws 65 frames a second, but the display stretches the frame, and it looks blurry. `--scale 2` or `--scale 3` sets the factor by hand.

`--gpu` draws the frame on the Mac's GPU. The library prepares the triangles, the shadow maps and the water's tables on the CPU. Metal then draws the sky with its clouds and stars, and the triangles with a depth test. Metal also composes the pond's water and smooths the edges.

The CPU adds the rain and the heads-up display. The window shows `CPU` and `GPU` milliseconds for each frame. See [Game renderer](Game-renderer#draw-on-the-gpu).

```sh
examples/capi/run.sh native village --gpu
```

The GPU frame has the size of the window's pixels, so `--scale` does not change it. The CPU path draws the 3D scene at a smaller size and stretches it. The GPU path draws every pixel of the 3D scene. At 2560 by 1440 pixels, the library needs 10 ms for a `low` frame and 18 ms for `medium`. A `high` frame takes 45 ms, and an `ultra` frame takes 141 ms. That is 95, 57, 22 and 7 frames a second.

The CPU draws `medium` at 18 frames a second when it draws every pixel too. The stretched CPU frame draws `medium` at 39 frames a second, but it is softer. So the GPU path is both faster and sharper. If the Mac has no Metal device, the host says so and draws on the CPU.

`--hour H` starts the day at hour H, from 0 to less than 24. `--weather NAME` starts in `clear`, `overcast`, `rain` or `fog`. Both work with or without `--gpu`. They show the night or the rain at once:

```sh
examples/capi/run.sh native village --gpu --hour 22
examples/capi/run.sh native village --gpu --weather rain
```

Escape and Command+Q quit. `Q` is the companion's assist attack, and does not quit here. The window reads the keyboard only. It does not read a gamepad yet. The window code is in [C ABI and hosts](C-ABI-and-hosts).

### On Linux

The game needs an X11 window. Linux has one. Windows under WSL 2 with WSLg has one too. A Mac can use XQuartz, but the macOS window above is faster to set up.

```sh
mojo run -I . examples/village_walk.mojo --play
mojo run -I . examples/village_walk.mojo --play 1280 720 medium
```

The window is 1920 by 1080 pixels by default. Give a width and a height for a different size. After the size, give a quality: `low`, `medium`, `high` or `ultra`. The default is `low`. See [Game renderer](Game-renderer). The X11 game reads every gamepad on the machine, and the keyboard.

### The controls

| Control | Gamepad | Keyboard |
|---|---|---|
| Move | Left stick, or the d-pad | `W`, `A`, `S`, `D` |
| Look | Right stick | The arrows |
| Run, and sprint after 0.6 seconds | Hold the right trigger, the east button or the left stick | Hold Shift, or `R` |
| Jump | The south button | Space |
| Use | The west button | `E` |
| Light attack | The right shoulder | `F` |
| Heavy attack | The north button | `G` |
| Plunge, in the air | Jump, and press the north button | Jump, and press `G` |
| Rising edge, whirlwind and ground wave | Hold the left trigger, and press the right shoulder, the north or the west button | `Z`, `X` and `B` |
| Ultimate, in a surge | Hold the left trigger, and press the right shoulder and the north button together | `M` |
| The companion's assist attack | Hold the left trigger, and press the left shoulder | `Q` |
| Dodge | The east button | `C` |
| Guard, and a stamina recovery | The left shoulder | `V` |
| Lock on | The right stick | `T` |
| Stance | Hold the left shoulder, and press the north, the west or the south button | `6`, `7` and `8` |
| Eat herbs to heal | The back button | `H` |
| Change the fighting style | Hold the left trigger, and press the south button | `Y` |
| Taunt the Stone Warden | Hold the left trigger, and press the east button | `U` |
| Show the combo book | Hold the left trigger, and press the back button | `K` |
| Weather | | `1` clear, `2` overcast, `3` rain, `4` fog, `9` snow |
| Time | | `5` moves the day on three hours |
| Quit | The start button | Escape. Command+Q in the macOS window. |

The buttons are named by position, as SDL names them. The south button is A on an Xbox controller and the cross on a PlayStation controller. The fight's controls are on [Village combat](Village-combat#the-controls). The styles and the combos are on [Village fighting styles](Village-styles) and [Village combos](Village-combos), and the raid on [Village raid](Village-raid).

The X11 game builds for about 15 seconds before the window opens. On a four-core Linux host, the `low` quality draws about 34 frames a second at 1920 by 1080 on the CPU. The game moves by the time each frame takes. So a slow frame moves the player as far as many quick frames do. This holds in the macOS window too, where a step is at most a tenth of a second.

The X11 game prints the frames a second to the standard error. The macOS window shows them in its title bar and prints them each second.

## Sound

The village has sound. `extensions/village/sound.mojo` makes every sound from noise and sine waves, so the game needs no recording. `VillageGame.audio` gives a host the next samples: stereo, `SAMPLE_RATE`, 44,100, a second, the left first, from -1 to 1.

| Sound | When |
|---|---|
| A footfall | Each stride of the player on the ground: quicker and louder at a run |
| A splash | A footfall in the pond |
| A swing | As an attack of the player begins |
| A knock | When a blow takes a foe's health |
| A chime | When coins come into the satchel |
| A bird's chirp | Now and then by day |

The wind and the rain are under every sound, as soft noise and as hiss. At night, crickets trill. `examples/village_walk.mojo path.png --wav path.wav` keeps the scripted walk's sound in a WAV file.

## Pause and the map

`VillageGame.paused` stops the game: its frames run with no time and no input, and the frame shows the controls. `VillageGame.show_map` shows a map of the village round the player in the top left corner, 60 meters each way. The map shows the houses, the pond, the trail, the player, the villagers, those with an errand to give, and the foes. `P` pauses the game, and `N` shows the map.

## The mouse

A drag of the mouse with a button held turns the camera. A click with the primary button is a light attack, and with the secondary a heavy one. `MouseLook` in `extensions/village/mouse.mojo` reads the window's pointer events.

## Saved progress

The player keeps their progress from one game to the next. With `--play`, the game keeps it in `out/village_progress.bin`. It reads the file as it begins, and writes it as the player quits. A file that the game cannot read is left as it is until the player quits, and the game begins as new.

The module is `extensions/village/progress.mojo`. `VillageGame.progress` gives a `Progress`, and `VillageGame.restore` takes one up. `pack_progress` packs it into bytes, and `unpack_progress` reads them back.

| Part | What it keeps |
|---|---|
| `experience` | Each skill's experience. The levels teach the combos again. |
| `satchel` | How many of each thing the satchel holds. |
| `mastery` | Each combo's mastery, so its rank and its perks. |
| `specialty` | The style the player specializes in. |
| `style` | The style in hand. The game takes it up if the player carries it. |
| `errands` and `rounds` | Each speaker's errand state, and how many of their errands are done. |
| `spent` | Each spot used up for good: a chest opened, a trinket taken. |
| `place` | Where the player stands, the hour and the weather. |

So the world comes back as the player left it, and an errand or a chest cannot be done again by beginning a new game. Each file is a save slot: `THREEMOJO_PROGRESS` names another file for `--play`. The macOS host keeps the progress in the file that `--save FILE` names.

The bytes begin with the letters `TMVP` and the version, 2. A record of version 1 has no errands, spots or place, and the game keeps its own. Each number takes 4 bytes. A record from an earlier game, of fewer skills, things or combos, reads with zero for the rest. A record of a later version, or of more than this game holds, is refused. Where the bytes are kept is the game's: a file, or anywhere it likes.

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

1. The look stick turns the camera around the player.
2. The fight runs: see [Village combat](Village-combat#one-frame-of-the-fight). The player's `Character` steps by the move stick, on the village's `Terrain`. Forward is the way the camera looks. An attack, a dodge or a blow carries the character instead.
3. While the player moves, the look stick rests and no lock holds, the camera turns behind the player.
4. The player's `Body` stands where the character stands. It plays the clip of its stance, or of its sword.
5. Each resident steps along its route, and its body or its mesh is posed.
6. Each door swings open while someone stands near it, and shut after.
7. The use button uses the spot in reach: see [Village gathering](Village-gathering). With no spot in reach, it talks to the villager in reach: see [Village errands](Village-errands).
8. The camera's focus follows the player. The eye comes in before a wall and before a tree's trunk, and stays below a ceiling and above the ground. The inside of each house hides while the eye is more than `INSIDE_REACH`, 18 meters, past the house's edge. The fireflies and the butterflies fly on: see [Village critters](Village-critters).
9. The village grows the grass for the camera, and moves the water's clock on.
10. The weather moves on, and scales the lights and the fog. See [Village weather](Village-weather). The day moves on, and dims and tints them for the hour. See [Village day and night](Village-day).

## The parts

| Module | Holds |
|---|---|
| `controls/third_person_controls.mojo` | `ThirdPersonControls`, `ground_direction`, `yaw_of`, `wrap_angle` and `turn_toward`. |
| `character.mojo` | `Stance`, `MoveInput`, `Obstacle`, `CharacterParameters`, `Character`, `lot_push` and `obstacle_push`. `Character.drive` carries a character at a set speed. |
| `terrain.mojo` | `WallSpan`, `Floor`, `Terrain`, `wall_push` and `view_entry`. See [Village houses](Village-houses#where-a-character-can-walk). |
| `clothes.mojo` | The natural dyes, `natural_dye`, `village_outfit` and `dyed_outfit`. |
| `pad_input.mojo` | `stick`, `fight_input`, `gamepad_input`, `keyboard_input` and `combined`. |
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

The feet follow `Terrain.height_at`: the highest floor under them that they can reach, or the ground. Feet reach a floor at most `CLIMB`, 0.45 meters, above them. A higher floor, such as an upper story, passes over them. A house's floor, the steps to its door and each tread of its stair are floors. So the character climbs the steps, walks on the floor, and goes up the stair one tread at a time. A floor stands over water, so a character does not wade on it.

`Stance` is `STANDING`, `WALKING`, `RUNNING` or `AIRBORNE`. A character in the air is airborne. On the ground, a character below 0.15 meters a second is standing, and one above 1.15 times the walking speed is running.

## The player's movement

The player moves by `player_movement`, which adds these to a person's movement. The residents and the foes move as before.

| Property | The player | What it does |
|---|---|---|
| `sprint_speed` | 6.6 meters a second | A run with the stick leaned all the way for `sprint_after`, 0.6 seconds, becomes a sprint. A sprint spends 11 stamina a second. With no stamina left, the player runs until they have 25 again. |
| `sprint_turn` | 320 degrees a second | A sprint turns more slowly, in wide arcs. |
| `deceleration` | 22 meters a second squared | The player slows and turns back faster than they speed up. |
| `coyote` | 0.12 seconds | A player who walks off an edge can still jump for this long. A body that a blow throws up cannot. |
| `jump_buffer` | 0.15 seconds | A press of the jump this long before the feet land jumps as they land. |
| `jump_cut` | 0.45 | A jump whose button is let go while it rises keeps this share of its upward speed. So a tap jumps lower than a hold. |
| `back_share` | 0.7 | A player locked on a target faces it, and strafes around it. They back away at this share of their speed. |
| `climb_drag` | 0.4 | Uphill, the speed drops by this share for each meter of rise a meter, to 30 percent at least. |
| `hard_landing` | 9 meters a second | A landing faster than this is hard. The player walks for `landing_time`, 0.3 seconds, and the camera shakes. |

**The roll.** Out of a fight, a tap of the dodge button rolls the player the way the stick leans, or steps them back with no lean. The roll starts as the button comes up, within 0.3 seconds of its press. A longer hold of the east button runs.

The roll spends a dodge's stamina, and does not draw the weapon. A roll in a sprint keeps the sprint. Hold the jump as a roll ends, and the player jumps with the roll's speed: a long jump.

A character with a `sprint_speed` no faster than its run never sprints. `CharacterParameters()` gives a person who does not sprint, and slows as fast as it speeds up. Its jump has no grace, no buffer and no cut. It backs away and climbs at its full speed, and never lands hard.

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
| A woman of 65 inches, dressed as a goodwife | By the green, before the brick house, which she visits. |
| A man of 70 inches, dressed as a peasant | Along the trail. He visits the stone cottage. |
| A child of 50 inches, dressed as a farmer, who runs | Around the pond. |
| A man of 67 inches, dressed as a monk | By the framed cottage, which he visits. |
| A woman of 64 inches, dressed as a noblewoman | By the framed house, which she visits. |
| Four sheep and a goat | In their pen, right of the trail. Its gate faces the trail. |
| Two cows and a horse | Left of the trail. |
| A pig | By the barn. |
| A dog | Near the start. It follows the player who comes within 30 meters. |
| Two rabbits | By the trail. |
| Two deer | Past the pond. |

Each resident walks a `Route`. It walks to a point, rests there for 3 seconds, and walks on to the next point. `wander_route` scatters the points around a middle. It does not put a point on or near a lot, or under the water.

A resident that stays slower than 0.1 meters a second for `SIDESTEP`, 0.6 seconds, is stuck. It walks aside for `DETOUR`, 1.2 seconds, to one side, and then to the other side when it is stuck again. After `DETOURS`, four, it gives up on its point, and rests as if it had arrived.

### Stops

A `Stop` is a place where a person does something, as an `Activity`: `IDLE`, `SIT` or `WORK`. `prop_stops` gives the village's stops from its props:

| Prop | Stop | Where the person stands |
|---|---|---|
| A bench | `SIT` | 45 centimeters before it, facing away from it |
| A woodpile | `WORK` | 90 centimeters before its logs, facing them |
| A bed of crops | `WORK` | 1.3 meters before it, facing it |
| A well | `WORK` | 70 centimeters past its wall, facing it |

A person stops at each stop within `STOP_REACH`, 14 meters, of the middle of where they wander. They turn to the stop's way, and rest there `ACTIVITY_REST`, four, times as long. On a bench they play `sit_clip`. At work they play `work_clip`: a bent back, and a tool swung down to the ground and up.

### Home at night

At night, while the daylight is below `SHELTER_LIGHT`, 0.2, the people go home. They also go home in hard rain or snow, above `SHELTER_FALL`, 0.6, of the heaviest. Each walks to their front door, over the threshold and in, and stays there. A person with no home of their own shelters in the first house. Once the night or the storm is over, they walk their routes again.

### Danger

A person, or an animal that is shy of the player, runs from each standing foe within `PANIC`, 9 meters. `Battle.dangers` gives where the foes stand. A dummy is no danger.

A villager with a home visits it. `Villager.home` is a `HouseId`, the house's place among the village's houses, or `NO_HOUSE`. `visit` adds five points to the end of the route. They stand 3.2 meters before the home's front door, 1 meter before it, and 1.8 meters inside it, and then back out the same way. The door opens as the villager comes near.

Each resident bumps into the trees, the player and every other resident. A resident that moved this frame is an obstacle where it stands now.

**A person** is a `Body`: a game humanoid of 3,000 triangles, dressed in its `Outfit`, with its idle, walk, run and jump clips. The body fades to the clip of its stance in 0.2 seconds. The walk and the run play from 0.6 to 1.6 times their own rate, by the speed. So the feet keep pace with the ground. A jump plays from the moment the feet leave the ground. The player is a `Body` too.

A person's skin, hair and beard are meshed on every core.

**An animal** is a flipbook: its mesh in six poses of its walk, and one mesh standing. The mesh shows the pose of how far the animal has walked, so one stride covers one stride of ground. An animal that turns on the spot faster than `TURNING`, half a radian a second, steps round. Each radian it turns counts as `TURN_STEP`, 35 centimeters, of its walk. An animal walks at its stride times its stride frequency at a Froude number of 0.25. An animal that does not walk on four legs keeps its standing mesh.

**A shy animal** runs from the player. `Herd.flee` is how near the player can come before the herd runs, a `Length`. Zero, the default, is tame. An animal nearer than that runs straight away from the player, at three times its walk, and its flipbook plays faster. It walks back to its route once the player is further away. The deer run from 12 meters, the rabbits from 6, the sheep from 3 and the goat from 2.

## Faces

Every villager and the player has a face that moves. A `Body` built with `speaks=True` keeps the preserved face, teeth and tongue of [Audio-aligned game faces](Audio-aligned-game-faces). It also keeps a still face of `FACE_TRIANGLES`, 900 triangles, for a distance. The still face is what the budget counts, so a person costs about as much as before. `ResidentsParameters.faces` turns the villagers' faces on or off. It is on by default.

`face_reach` gives the distance at which a face is drawn `FACE_PIXELS`, 16 pixels, tall. It reads the quality's frame height and the camera's field of view. Nearer than that, `Body.show_face` shows the preserved face and sets its weights. Further, the still face shows. At the `medium` quality, the reach is about 2.6 meters.

`FaceLife`, in `extensions/village/faces.mojo`, keeps one face moving:

1. The eyes blink every 2 to 5.5 seconds, for 0.16 seconds. Each face blinks at its own times, by its seed.
2. `say` starts words. The mouth makes the shape of each sound of the words, in its time. See [Head](Head#expressions-and-speech) for the shapes.
3. `feel` sets an expression, how strong it is, and how long it is held. The face eases to it at `MOOD_EASE`, 5 a second. A new expression comes in after the last goes out.
4. `pant` opens the mouth a little, in and out, for a fighter out of breath.

`player_mood` sets the player's face by the fight. An attack shows anger, at 0.55. The heavy attack and the specials show more anger, at 0.9. A blow that lands on the player shows fear, and so does stamina run out. A fall shows sadness.

Each expression is held for `GRIMACE`, 0.5 seconds. Below `WINDED`, 60 % of their stamina, the player pants.

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

The villagers, the bandits, the companion and the raiders are dressed by calling: `dressed_as` from [Outfits and armor](Outfits-and-armor#archetypes) gives each their outfit. `calling_groom` gives the hair and the beard that suit the calling, as a `Groom`. `Villager`, `Bandit` and `Raider` each hold a `groom`; a plain one, grown hair and no beard, by default. The raiders wear plate, a monk's robe, a knight's harness and a ranger's green.

The player wears a madder-red tunic trimmed in weld yellow, over walnut hose. `PlayParameters.outfit` holds the player's clothes. An empty `Outfit` leaves a person bare.

The clothes follow the skin, and the skin follows the bones, so they move together as a person runs, jumps and fights. Six things keep them apart where they must part:

- The skin's arms are parted from the trunk before it is weighed. So an arm swung out does not stretch the skin or the tunic to the hip. See [Game humanoid](Game-humanoid#the-skin-and-its-weights).
- A boot's last takes its weights from its own leg only. So a kick does not stretch the boot to the other foot.
- The scabbard swings clear of the thigh beside it: see [Village combat](Village-combat#the-sword-clips).
- Round the armpits, a garment under a closed one is cut deeper. So it does not show through when an arm rises. See [Garments](Garments).
- A platebody keeps off the arms. So its side does not tear open under a raised arm. See [Outfits and armor](Outfits-and-armor#plate).
- A long robe or gown hides the legs inside it. So a running leg does not push out through its front. See [Garments](Garments).

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
- A resident walks straight to its next point. Round a house, it walks aside and tries again, but it does not plan a way. It can give up on a point it cannot reach.
- The camera comes in before a wall and a trunk, but not before a crown of leaves or a roof.
- The X11 window and the macOS window do not play the sound: `--wav` keeps it, and a host can take it with `tm_village_audio`.
- The macOS window reads no gamepad. A key cannot be bound to another action, and the game has no menu of settings: its options are its command line.
- The game draws on a GPU only through Metal, in the macOS window. The web host draws the water and the splats, and not the village.
