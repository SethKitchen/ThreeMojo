# Village houses

A house of the [Village](Village) is a building model that a player can walk into. It has a front door that swings open, furnished rooms and a stair. Its facade is brick, fieldstone, timber framing or boards. A brick or stone house has a hearth. A house can also be a barn.

![A street of tile roofs, a framed house, a brick house, and a man in a red tunic by a fireplace and a stair](out/village_houses.png)

`examples/village_houses.mojo` draws this picture. The modules live in `extensions/village/`. See [Building model](Building-model) for the canonical model, and [Village walk](Village-walk) for the game.

## Build a house

```mojo
from core.assets import Assets
from core.scene import Scene
from extensions.vegetation.ground import Ground
from extensions.village.house import (
    TIMBER_FRAMED,
    HouseParameters,
    house_lot,
    house_model,
    lime_plaster,
)
from extensions.village.house_view import stand_house
from extensions.village.surfaces import house_looks
from units.si import DEGREE, METER, Angle, Length

var assets = Assets()
var scene = Scene()
var looks = house_looks(assets, 128, 17)
var house = HouseParameters(
    "framed house", Length(8.0, METER), Length(6.0, METER), 2,
    lime_plaster(), TIMBER_FRAMED,
)
var lot = house_lot(house, 21, -24, Angle(-80.0, DEGREE))
var standing = stand_house(
    scene, assets, looks, house, house_model(house), lot, Ground()
)
```

`house_looks` makes the textures and the materials once. Give the same looks to every house. `stand_house` returns a `StandingHouse`: its node, its meshes, its interior and the hinges of its doors.

## The model

`house_model` writes the canonical model with `assemble`. It never writes a mesh. The table gives its rooms.

| Storey | Rooms |
|---|---|
| Ground | A hall, with a counter and a table with chairs. A house 6 meters wide or more also has a chamber with a bed, on the plan's +x side. The hall takes 60 percent of the width. |
| Each storey above | One living room, with a settle, a low table and a shelf. |

The front door is 1 meter wide and 2.1 meters tall. A barn is different: see [The barn](#the-barn). It stands in the middle of the hall's front wall, the outside wall on the plan's -y side. `front_wall` finds that wall. `add_doors` then gives the chamber a door into the hall, 0.9 meters wide.

`add_windows` cuts a row of windows in each outside wall, clear of the doors. A brick or stone house then gets a chimney breast. `furnish` places the furniture by its rules. See [Floor plans and interiors](Floor-plans-and-interiors).

## Facades

`Facade` is a type with `is_valid`. A bare integer does not compile.

| Facade | Walls | Dressings | Roof |
|---|---|---|---|
| `BRICK_FACADE` | Red brick in running bond | Stone quoins, a stone band at each upper floor, stone lintels and sills, cream window frames, a hearth and a chimney | Clay tiles |
| `STONE_FACADE` | Fieldstone in lime mortar | Stone quoins, oak lintels, cream window frames, a hearth and a chimney | Slates |
| `TIMBER_FRAMED` | Lime plaster | Oak posts, rails and braces, a king post on each gable | Clay tiles |
| `BOARDED` | Vertical boards, with battens over the joints in the texture | Oak sills, no shutters | Clay tiles |

`fieldstone` and `lime_plaster` give the materials of a stone wall and a framed wall. Their physical values are typical values, not design values.

## The village's view of the model

`stand_house` reads the model as the general render view does. It draws more of what an eye sees from close by.

1. **Walls.** Each face of a wall is cut into cells at the edges of its openings. No cell is more than 1 meter across. The outside face wears the facade's texture. Its vertex colors darken it at its foot and under the eaves. The inside face wears lime plaster, and is darker in the corners of the room.
2. **Windows.** A window has a painted frame, a mullion and a transom, panes of glass and a stone sill. From outside, a pane shows the sky at its top and darkens toward its foot. The panes show the day from inside. A pair of shutters stands open against the wall, in the trim's paint.
3. **Doors.** A door has an oak frame and a stone threshold. Its leaf is boards on ledges, with iron straps. The leaf hangs from a hinge node of its own. A door 2 meters wide or more hangs two leaves, one at each jamb. A leaf 1.2 meters wide or more has diagonal braces.
4. **Rooms.** Each room has a floor of planks and a plastered ceiling. The ground storey's ceiling has oak joists.
5. **The roof.** Two slopes of tiles or slates, 16 centimeters thick, reach 35 centimeters past the long walls. Boards line the underside of the eaves. A fascia, barge boards and a ridge close the edges. A chimney stack rises over the chimney breast. Each gable is cut into cells no more than 1 meter across, as a wall is. A zinc gutter runs along each eave. A downpipe runs from each end of each gutter down the wall to the ground.
6. **The plinth and the steps.** A stone plinth reaches 40 centimeters below the lowest ground under the house. Stone steps lead up to the front door.

The house hangs from one node at its lot's middle, at the floor's height. Its shell shows from outside: its outside walls, its windows and doors, its roof, its plinth and its steps. Its inside hangs from a node of its own, `StandingHouse.inside`. The inside holds the rooms, the stair, the hearth, the furniture, the dressing and the inside faces of the walls. A game can hide the inside from far away. The inside casts no shadow, because a still shadow map is drawn only once.

Each material of the shell is one mesh, and so is each material of the inside. A dwelling with windows is fifteen meshes with its two door leaves.

## Surfaces

`extensions/village/surfaces.mojo` draws each texture from seeded noise. Each texture tiles, and each covers a known size of wall. So a brick keeps its true size on every wall.

| Texture | Covers | What it shows |
|---|---|---|
| `brick_texture` | 0.9 m | Running bond: bricks of 22.5 by 7.5 centimeters in a pale mortar |
| `fieldstone_texture` | 1.2 m | Rounded stones of four tints, in a deep mortar |
| `plaster_texture` | 2 m | Lime plaster, clouded |
| `boards_texture` | 1.2 m | Six boards of 20 centimeters, with a batten over each joint, lit on one edge and shaded on the other |
| `wood_texture` | 1 m | Grain, with rare knots |
| `ashlar_texture` | 0.8 m | Dressed blocks of 40 by 20 centimeters |
| `tile_texture` | 1 m | Five courses of clay tiles |
| `slate_texture` | 0.9 m | Six courses of slates |
| `plank_texture` | 1.2 m | Floor planks of 15 centimeters |
| `cloth_texture` | 0.25 m | Undyed wool in a two-over-two twill, for rugs, quilts and cushions |

A `Sheet` holds the triangles of one material, with a normal, a color and texture coordinates at each vertex. Its texture coordinates are meters divided by its texture's size. The game renderer reads these maps at each pixel. See [Game renderer](Game-renderer#maps-at-each-pixel).

## Where a character can walk

`house_interior` reads the same model and gives a `HouseInterior`. It is a view of the model, as the render view is.

| Part | What it is |
|---|---|
| `walls` | One `WallSpan` for each piece of each wall. A door cuts a gap to its head, and the wall over the door is a span of its own. A span along the face of each column follows, then the stair's railings. |
| `floors` | The ground floor over the plan and its plinth, then each step, then each tread of the stair and the upper floor round its well. A floor's ceiling is the underside of the slab over it. |
| `furniture` | A `WallSpan` for each piece, along its longer side and as high as the piece, on its storey's floor. |
| `doorways` | Each door of the ground storey: the jamb it hangs on, its width and the way it swings. |

A step is 32 centimeters deep and at most 18 centimeters high. A door whose sill is less than 12 centimeters above the ground has no step. A door has at most six steps.

## The stair

A house of two storeys or more has a stair from the ground floor up to the first storey above. `house_stair` finds it in the model. It runs along the back wall of the hall, the first room of the ground storey, and climbs along the plan's +x.

| Part | Size |
|---|---|
| Width | 1 meter. |
| Riser | As few risers as keep each one at most 19 centimeters. A storey of 2.8 meters has 15 risers of 18.7 centimeters. |
| Tread | 25 centimeters deep, one fewer than the risers. |
| Landing | 0.9 meters of floor clear before the foot. |

A hall too short for the landing and the treads has no stair. `house_model` takes away the furniture that would stand on the stair, on its landing or over its well.

A railing 1 meter high guards the well's open side upstairs. It reaches down to the ground floor, so it closes the stair's side as well. A railing crosses the well's foot upstairs, and a wall closes the space under the stair's top. `stand_house` draws oak treads and risers, a stringer, a handrail on balusters, a newel post and a balustrade. It cuts the well out of the hall's ceiling and the floor above, with oak trimmers round it.

`Doors` opens each door while someone stands within 1.8 meters of its middle, on its floor. The leaf turns at 2.5 radians a second, to a little over a right angle. It closes when nobody is near. A leaf is not solid: the gap in the wall is where a character walks through.

## The barn

`HouseParameters.use` is a `HouseUse`: `DWELLING` or `BARN`. A bare integer does not compile. A dwelling is the default.

| Part | A barn |
|---|---|
| Rooms | One open storage floor on each storey: the threshing floor, and a loft over it. |
| Front door | 3.2 meters wide and 3 meters tall, in the middle of the front wall. Two leaves hang in it, and they swing out. |
| Windows | 0.8 meters wide and 0.7 meters tall, with their sills 2.3 meters up, 3.6 meters apart. |
| Stock | Stacks of hay along the west half of the back wall, and mangers along its east half. |
| Hearth | None. |

A barn must be 5 meters wide or more. Its storey must be 3.4 meters tall or more.

The model holds the hay as shelves and the mangers as cabinets, with the sizes of `HAY` and `MANGER`. `stand_house` draws each shelf of a barn as a stack of straw bales tied with cords. It draws each other piece as a trough of boards on posts, with hay in it and a rack of slats over it.

A barn's inside walls are bare boards, and its ceilings are planks. A loft door of two leaves is shut high in its east gable. A hoist beam reaches out over it, with a pulley and a rope. A gable too low for a loft door 60 centimeters tall has none.

## The hearth

A brick or stone house has a chimney breast against its west gable wall. `house_breast` finds it in the model. It is a `COLUMN` element on each storey, from the floor to the floor above.

| Part | Size |
|---|---|
| Breast | 1.5 meters wide along the wall. It stands 55 centimeters out from the wall. Its middle is 45 centimeters to the plan's -y of the wall's middle. |
| Fireplace | An opening 90 centimeters wide and 85 centimeters high, in the breast's face on the ground storey. |
| Clear floor | 60 centimeters round the breast, on every storey. |

`house_model` takes away the furniture on the clear floor. It also takes away each window of the gable wall behind the breast.

`stand_house` plasters the breast on each storey. On the ground storey it draws stone jambs and a stone lintel round the fireplace, with an oak mantel shelf over them. A sooty back, a stone hearth slab, two logs and glowing embers fill the fireplace. The embers and their glow on the back are unlit, so they glow in a dark room. The chimney stack on the roof stands over the breast.

`house_interior` gives a `WallSpan` along the breast's face, as high as the storey. So a character walks round the breast and does not walk into the fire.

## Furnishings and light

A dwelling's rooms are dressed. A barn's are not. `extensions/village/dressing.mojo` draws the small things, and `stand_house` places them:

| Where | What |
|---|---|
| Each wall of each room | Oak paneling to `DADO`, 95 centimeters up, with a rail along its top. |
| Each room's floor | A woven rug of 16 by 10 cells: a border, a cream line, a field and a medallion. It keeps 75 centimeters off the walls and 30 centimeters off the stair's band. It is at most 2.6 by 1.8 meters. A room with less than a meter of rug each way has no rug. |
| Over each rug | A lantern of iron and glowing glass, on a chain 75 centimeters long. |
| The hall | A pole of drying herbs under the ceiling, by the front wall. |
| A table | A plate and a mug at each place on both long sides, a bowl, and a candle. |
| A desk | A stack of four books, and a candle. |
| A low table | A jug and two cups. |
| A counter | A board with a loaf on it, and a crock. |
| A shelf | Three jars and pots of glazed earthenware on each board. |
| A bed | A mattress, a quilt of 4 by 5 patches and a pillow, in wool. |
| A settle | A wool cushion. |

The rugs, the quilts and the cushions wear `cloth_texture`. Each dye is one of `dye`: madder, woad, weld, nettle and walnut. Each glaze is one of `glaze`. A flame is drawn on the unlit material, so it shows in a dark room.

### Light inside a house

The game renderer has no lamps. So `warm` bakes the light inside a dwelling into the vertex colors of its plaster, wood, stone, planks and cloth:

1. **The fill.** Each color inside the walls is multiplied by `FILL`. This is the warm light that bounces round a room off its floor and its walls.
2. **The flames.** Each `Glow` adds `FIRELIGHT` times `warmth`. `warmth` starts at the glow's strength. It is multiplied by the cosine between the surface's normal and the way to the flame. It is also multiplied by the square of the share of its reach that is left.

| Glow | Strength | Reach |
|---|---|---|
| `HEARTH`, at the embers | 1.6 | 5 meters |
| `LANTERN`, at its flame | 0.9 | 4 meters |
| `CANDLE`, at its flame | 0.6 | 2.5 meters |

A glow warms only its own storey. A vertex outside the middle of the walls is not warmed, so a flame does not light the outside face of a wall.

## Limits

- Only the first storey above the ground has a stair. A character does not reach a higher storey.
- A door leaf does not stop a character or a camera.
- A flame does not light the room as a lamp does. Its light is baked into the vertex colors when the house is built, so a character does not catch it, and it casts no shadow.
- A house of timber framing or boards has no hearth.
- A house is a box of storeys under one gable roof. It has no porch and no wing.
