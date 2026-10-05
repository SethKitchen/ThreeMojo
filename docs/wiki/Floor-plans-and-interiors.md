# Floor plans and interiors

`extensions/building/generate/` lays out seeded floor plans, cuts doors and windows, and furnishes rooms. Each step writes the canonical [building model](Building-model). The render, structural, thermal and IFC views then read the furniture and the openings from it.

![A furnished office floor, cut away above its ceiling, turns under a lamp](out/floor-plans-and-interiors.png)

## Modules

| Module | What it gives |
|---|---|
| `plan` | `plan_floor`, `FloorProgram`, `PlanOptions`, `clip_half` and `is_convex` |
| `openings` | `add_doors`, `add_windows` and `WindowOptions` |
| `furnish` | `furnish` |
| `tower` | `generate_tower`, which uses all three. See [Procedural towers](Procedural-towers). |

## Lay out a floor

`plan_floor(footprint, program, seed, options)` returns the spaces of one storey in a convex footprint, as `SpacePlan` values for `assemble`.

```mojo
var spaces = plan_floor(footprint, OFFICE_FLOOR, 7, default_plan_options())
```

The plan is a double-loaded corridor. The corridor runs along the footprint's longest edge, through its middle. A band of rooms lies on each side. Cuts across each band at seeded widths make the rooms. Each room spans its band from the corridor to the outside wall. Every room therefore has a corridor wall, and every room on the outside has a window wall.

| Program | Corridor | Band rooms | Core |
|---|---|---|---|
| `OFFICE_FLOOR` | A corridor | Offices, one in five a meeting room | Stairs and lifts, toilets, plant |
| `RESIDENTIAL_FLOOR` | A corridor | Living rooms, bedrooms and kitchens in turn | Stairs and lifts, storage |
| `LOBBY_FLOOR` | A lobby 2.5 corridors wide | Shops | Stairs and lifts, toilets |

The core is a run of rooms at the middle of one band. `PlanOptions` sets the corridor width, the smallest and largest room widths, and the core length. The defaults are a 1.8 m corridor, rooms from 3 to 6 m wide and a 12 m core.

`plan_floor` refuses a footprint that is not convex. It also refuses one narrower than a corridor and two rooms, or shorter than the core and two rooms.

## Cut doors and windows

Call `add_doors` before `add_windows`, so that windows stay clear of doors.

```mojo
_ = add_doors(building, Length64(0.9, METER), Length64(2.1, METER))
_ = add_windows(building, WindowOptions(bay, pier, sill, height, double_glazing()))
```

`add_doors` gives each room one door, in the middle of the longest wall it shares with a corridor or lobby. A room with no such wall, or with one too short for the door, gets a door into a neighbor. The door goes in the longest wall that has no door yet, as in a suite. A lobby gets a double-width entrance in its longest outside wall.

`add_windows` cuts a row of windows in every outside wall. The wall is divided evenly into the fewest bays no wider than the bay width. Each window is its bay less the pier. A window that would cut a door is left out. A row taller than the wall cuts nothing.

## Furnish rooms

`furnish(building, seed)` places furniture room by room, by rules:

| Use | Pieces |
|---|---|
| Office | A desk with a chair for every 10 m², and a shelf |
| Meeting room | A table with six chairs, and a cabinet |
| Living room | A sofa, a coffee table and a shelf |
| Bedroom | A bed, a nightstand and a wardrobe |
| Kitchen | A counter, and a table with four chairs |
| Bathroom | Two toilets and a sink |
| Storage and plant | A shelf and a cabinet |
| Shop | A counter and two shelves |
| Lobby | A sofa and a coffee table |

A wall piece stands with its back to a wall and keeps a clear strip in front. A center piece stands in the open with a clear margin all round. A chair goes in front of its desk or around its table.

A candidate place is refused when the piece leaves the room, or overlaps a piece or a clear strip already placed. It is also refused in the swing of a door, and for a tall piece in front of a window.

Among the places left, the piece takes the best by a score. A desk prefers to be near a window. A bed prefers to be far from the door. A small seeded term breaks ties. A piece with no place left is skipped.

The rules follow the clearance, circulation and pairing guidelines of interior layout. See Merrell, Schkufza, Li, Agrawala and Koltun, "Interactive furniture layout using interior design guidelines", 2011.

## Furniture in the model

Each piece is a `Furnishing`: a kind, a space, a plan center, a rotation and a box size. `Building.add_furnishing` refuses a piece that leaves its space or overlaps another piece in it. The render view draws each piece as a few boxes in wood, fabric, ceramic or metal. IFC exchange writes each piece as an `IfcFurniture` in its space.

## Limits

- A footprint must be convex. The plan has one corridor.
- A room in a deep band is deep. The plan does not add a second corridor.
- A cut beyond the corridor's ends in an unusual convex footprint can leave a room without a corridor wall. That room opens into a neighbor instead.
- The placer is greedy. It does not move a placed piece to make room for a later one.
- Furniture is boxes. It has no mass or heat gain in the structural and thermal views.

## References

- Sutherland and Hodgman, "Reentrant polygon clipping", 1974.
- Merrell, Schkufza and Koltun, "Computer-generated residential building layouts", 2010.
- Merrell, Schkufza, Li, Agrawala and Koltun, "Interactive furniture layout using interior design guidelines", 2011.
- Neufert, "Architects' Data", 5th edition, 2019.
