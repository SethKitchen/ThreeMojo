# Village gathering

A player of the [Village walk](Village-walk) can gather things about the village: herbs, mushrooms, berries, ore, coins from a chest, lost trinkets and fish. The use button gathers the thing in reach. A heads-up display shows what the player holds.

The modules are `extensions/village/gathering.mojo` and `extensions/village/hud.mojo`. `VillageGame` builds a `Gathering` from `PlayParameters.gathering`, and runs it in each `tick`.

## Gather a thing

Walk to a spot. A gold marker turns over it when it is in reach. Then press the use button: `E` on the keyboard, or the west button of a gamepad. The west button is X on an Xbox controller and the square on a PlayStation controller.

A held button gathers once. Let it go and press it again to gather again.

## The kinds

`GatherKind` is a type with `is_valid`. A bare integer does not compile.

| Kind | What it is | A use gives | It comes back |
|---|---|---|---|
| `HERBS` | A tuft of leaves with pale violet flowers | 1 herb | After the respawn time |
| `MUSHROOMS` | A cluster of five red-capped mushrooms | 2 mushrooms | After the respawn time |
| `BERRIES` | A low bush hung with berries. The bush stays. | 3 berries | After the respawn time |
| `ORE` | A boulder with copper nuggets. It takes `STRIKES`, three, uses. The boulder stays. | 1 ore | After the respawn time |
| `CHEST` | An iron-bound chest. Its lid swings open. | `CHEST_COINS`, twelve, coins | Never |
| `TRINKET` | A gold ring hung with a gem, which bobs and turns 90 centimeters up | 1 trinket | Never |
| `FISH` | An oak stake and a creel on the pond's shore | 1 fish, when hooked | It is never used up |

A boulder, a chest and a berry bush stop a character. `Gathering.obstacles` gives each as round: 0.6, 0.45 and 0.4 meters across. A character walks through herbs, mushrooms and trinkets.

## Fishing

A fishing spot's float lies on the water `CAST`, 3.2 meters, out along the spot's turn. Turn the spot to face the pond.

1. A press casts the float. The prompt says `E  REEL IN`.
2. After two to six seconds a fish bites. The float dips and jerks for `BITE`, 1.2 seconds. The prompt says `E  HOOK IT!`.
3. A press while the fish bites hooks it, and the satchel holds one more fish.

A press before the bite reels the line in, and nothing is caught. A bite that is missed lets the fish get away. A player who walks out of reach reels the line in.

## Build the spots

```mojo
from extensions.village.gathering import (
    HERBS,
    GatherParameters,
    Gathering,
    Spot,
)
from units.si import RADIAN, SECOND, Angle, Duration

var parameters = GatherParameters()
parameters.spots.append(Spot(HERBS, 4, 12, Angle(0.5, RADIAN)))
parameters.respawn = Duration(30.0, SECOND)
var gathering = Gathering(scene, assets, looks, parameters, ground, lots)
```

`Gathering` leaves out each spot on a lot or its apron, and each spot in the water, as the meadow does with a tree. The spots wear the houses' materials, `HouseLooks`. A boulder is the meadow's `boulder`.

`GatherParameters()` holds the default village's 17 spots, with a fishing spot on the pond's west shore. Its reach is 1.8 meters, and its respawn time is 60 seconds.

## One frame

`Gathering.update` runs one frame:

1. Each spot that waits counts down its respawn time. A spot whose time is over is ready again, and shows.
2. The focus is the ready spot nearest the player's feet. It must be within the reach, and less than 1.5 meters above or below the feet.
3. On a new press of the use button, the focus is used. What it gives goes into the `Satchel`. The part that is gathered hides. A boulder gives its ore on its last strike only.
4. Each trinket bobs and turns. Each chest's lid swings open at 2 radians a second, to 1.9 radians.
5. A shimmer of four gold motes turns over each ready spot. The marker turns and bobs over the focus, and hides when there is none.

`update` returns the kind that gave something this frame, or `None`. `Satchel.last` holds how many things it gave.

## The heads-up display

`draw_hud` writes three things over the window's frame, after the frame is stretched:

| Part | Where | What it says |
|---|---|---|
| The satchel | The bottom left | A swatch and a count for each kind the player holds |
| The prompt | The bottom middle | What the use button does at the focus, such as `E  MINE ORE 1/3` |
| The note | Over the prompt | What the player gathered, such as `+3 BERRIES`, for 2 seconds. It fades over its last half second. |
| The speech | Over the note | What a villager said, for 5 seconds. See [Village errands](Village-errands). |
| The errands | The top right | Each errand taken and not done |

The font has 5 by 7 dots and needs no font file. It draws capitals, digits, and `+ / : . , ! ? ' -`. A dot is `hud_scale` pixels on a side: one pixel for each 270 pixels of the frame's height. So the text keeps its size on the screen. Each line has a dark shadow, so it reads over the sky and the grass.

Set `PlayParameters.hud` to False for a frame with no display.

## Limits

- A spot does not stop the camera.
- The satchel counts things. It does not hold items with their own state. An errand takes things out of it: see [Village errands](Village-errands).
- The note shows the last thing gathered only.
- Coins are spent nowhere yet.
