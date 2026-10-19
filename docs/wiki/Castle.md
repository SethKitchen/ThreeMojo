# Castle

`extensions/castle/` holds a moated brick castle as data, as a scene and as a set of engineering checks. The Wijnendale plan is the one plan it ships.

![Wijnendale Castle in autumn, seen from the air, with the towers mirrored in the moat](out/castle.png)

`examples/wijnendale.mojo` renders the picture. The sun stands where it stood over Torhout at 15:30 on 19 October. The moat is a mirror. The analysis modules read the same plan. See [Castle analysis](Castle-analysis).

## Modules

| Module | What it gives |
|---|---|
| `kinds` | `TowerShape`, `RoofForm`, `Surface` and `LimitState`, and `tower_shape_from_name` and `roof_form_from_name` |
| `masonry` | `Masonry`, `characteristic_strength`, `clay_brick_masonry` and `dressed_limestone` |
| `plan` | `PlanPoint`, `Tower`, `Block`, `Moat`, `Bridge`, `CastlePlan` and `wijnendale` |
| `survey` | `plan_to_json` and `plan_from_json`, which carry a surveyed plan in and out as JSON |
| `render` | `CastleOptions`, `add_castle`, `surface_color` and `foliage_color` |
| `wind` | `Wind`, `flanders_wind`, `peak_velocity_pressure`, `tower_wind_load`, `cantilever_frequency` and `check_tower_base` |
| `arch` | `analyze_arch` and `analyze_bridge` |
| `wall` | `GravityWall`, `check_wall` and `required_thickness` |
| `water_balance` | `Climate`, `Weir`, `flanders_climate`, `simulate_year` and `required_inflow` |
| `sun` | `castle_sun`, `scene_direction`, `shadow_length` and `day_length` |

Every quantity has a unit type: `Length64`, `Angle64`, `Force64` and `Pressure64`. Every kind is a type with `is_valid`.

## What the plan documents and what it estimates

The plan states which facts are documented and which numbers are estimated. No published survey of the castle was available. A reader can replace each estimate with a survey value.

| Item | Value | Status |
|---|---|---|
| Place | Torhout, West Flanders, Belgium | Documented |
| Moat and courtyard | A circular moat around a round inner courtyard | Documented |
| Coordinates | 51°04′44″ N, 3°03′34″ E | Documented |
| First castle | About 1085, built by Robert I, Count of Flanders | Documented |
| North wing | Parts date from the 15th century | Documented |
| Present form | Neo-Gothic, mainly of the 19th century | Documented |
| Gatehouse and keep | Designed by Félix Laureys, 1877 and 1878 | Documented |
| Walls | Red brick; the right wing has a round keep, and the left wing stands on a base of yellow or white brick | Documented |
| Enclosure | A square brick wall with gate turrets and battlements, protected with the castle on 22 September 1982 | Documented |
| Gatehouse plan | Square, because the sources I could reach disagree on its plan | Estimated |
| Stone dressings, dormers and window rows | From the aerial photograph | Estimated |
| Dimensions of every part | From the aerial photograph, good to about 15 percent | Estimated |
| Wall thickness, bridge arch, moat depth | Typical values for the building type | Estimated |
| Monthly rain | The 1991-2020 normals of Uccle, 837 mm a year | Measured, at a station about 90 km away |
| Wind, evaporation, soil and masonry strength | Typical values from the Eurocodes and the Flemish lowland | Assumed |

## Sources and what is missing

The documented facts come from these pages:

- [Flemish heritage inventory, Kasteeldomein van Wijnendale](https://inventaris.onroerenderfgoed.be/erfgoedobjecten/87491) gives the work of Félix Laureys in 1877 and 1878, and the gatehouse and keep.
- [Wijnendale Castle on Wikipedia](https://en.wikipedia.org/wiki/Wijnendale_Castle) gives the coordinates and the history.
- [Eupedia](https://eupedia.com/belgium/wynendale.shtml) and [RTBF](https://www.rtbf.be/article/le-chateau-de-wijnendale-la-ou-leopold-iii-a-lance-la-question-royale-11329444) describe a circular moat.
- [Brussels Environment, climate fact sheet](https://document.environnement.brussels/opac_css/elecfile/Clim_02) gives the Uccle rain normals of the Royal Meteorological Institute.

No source that I could reach gives the height of a tower, the length of a wall or the size of the moat. I searched in Dutch, French and English. I could read only search summaries of these pages, not the pages themselves. The protection decree refers to a plan that I could not open. A survey or that plan would replace the estimates.

The measured footprint is in three records. The container could not reach any of them. Direct fetches failed at name resolution, and the egress gateway denied the same hosts with 403.

- The protection file DW000432 of Onroerend Erfgoed, with the decree and its plan.
- [The plan record of the castle](https://plannen.onroerenderfgoed.be/plannen/1671), which gives boundary geometry in Belgian Lambert 72 (EPSG:31370).
- The Flemish building footprints of Geopunt, which have the outline of every wing and tower.

To use them, allow the hosts in the environment settings and ask for a second run. Read the outlines, write them as a survey JSON file and pass that file to both examples.

## Replace the estimates with a survey

A survey replaces the estimates without a change in the code. `plan_to_json(wijnendale())` writes the estimated plan as JSON. Edit the numbers in that text. `plan_from_json(text)` reads the plan back and runs `plan.check()`.

All lengths are in meters. All angles are in degrees. The top-level keys are `name`, `latitude`, `longitude`, `towers`, `blocks`, `moat` and `bridge`.

| Part | Keys |
|---|---|
| Tower | `name`, `shape` (`round` or `square`), `x`, `y`, `radius`, `wall`, `height`, `roof` (`cone` or `parapet`), `roof_rise` |
| Block | `name`, `x`, `y`, `length`, `width`, `heading`, `wall`, `height`, `roof` (`gable` or `parapet`), `roof_rise` |
| Moat | `x`, `y`, `semi_x`, `semi_y`, `island_x`, `island_y`, `island_semi_x`, `island_semi_y`, `depth`, `freeboard` |
| Bridge | `x`, `y`, `heading`, `spans`, `span`, `pier`, `rise`, `ring`, `width`, `fill`, `springing`, `parapet` |

A missing key, a value of the wrong kind, an unnamed shape and a plan that cannot stand are all refused with a message. Both examples take the survey as a second argument:

```bash
mojo run -I . examples/wijnendale.mojo out/castle.png survey.json
mojo run -I . examples/wijnendale_simulation.mojo out/castle-simulation.png survey.json
```

`plan.scaled(factor)` multiplies every length of a plan by a factor. It gives the sensitivity of an analysis to the error of an estimate. See [Castle analysis](Castle-analysis#sensitivity-to-the-estimates).

## The plan frame

The plan has x to the east, y to the north and z up, in meters. The origin is the middle of the courtyard. The ground of the island is z = 0. The water stands `freeboard` below it. The scene is y up. A plan point (x, y, z) is the scene point (x, z, -y).

A `CastlePlan` holds:

| Part | Type | What it is |
|---|---|---|
| Towers | `Tower` | A round or square shaft with a cone or a battlemented parapet |
| Blocks | `Block` | A rectangle of wall with a gable roof, or a gatehouse with a parapet |
| Moat | `Moat` | An ellipse of water around an elliptical island. A circle has equal axes. |
| Bridge | `Bridge` | A row of equal segmental masonry arches on piers |

`plan.check()` refuses a part that cannot stand. It refuses a wall as thick as its radius and a gable with no rise. It refuses an island outside the moat and a tower off the island. It refuses an arch that rises more than half its span.

## The Wijnendale plan

`wijnendale()` returns the plan. All sizes are in meters.

| Part | Shape | Size | Height to eave | Roof |
|---|---|---|---|---|
| Keep | Round | Radius 3.6, wall 1.2 | 28 | Parapet |
| Courtyard turrets | Round | Radius 1.6 and 1.7 | 12 and 13 | Cone |
| Front towers | Round | Radius 2.8 to 3.3 | 15 | Parapet and cones |
| Gate turrets | Round | Radius 1.7 | 21 | Cone |
| Rear range | Block | 30 by 9 | 11 | Gable, rise 7 |
| Front range | Block | 34 by 9 | 11 | Gable, rise 6.5 |
| Gatehouse | Block | 16 by 16 | 19 | Parapet |
| Moat | Circle | Outer radius 46, island radius 33 | Water depth 1.6 | |
| Bridge | Three arches | Span 5, pier 1.4, rise 1.4, ring 0.4 | Length 20.6 | |

## Draw a plan

`add_castle(scene, assets, plan, options)` adds one node for the castle and one mesh for each surface that has triangles. The surfaces are brick, stone, slate, water, lawn, gravel, trunk and foliage. Each mesh takes its color from its vertex colors. A seed sets the shade of every brick, slate and tree.

| Option | Meaning |
|---|---|
| `sides` | Facets of a round tower. It must be six or more. |
| `trees` | Trees in the wood around the castle. It must be zero or more. |
| `seed` | The seed of every shade and of the trees |
| `shadows` | Whether the meshes cast and receive shadows |
| `water` | Whether to draw the water as a mesh. Turn it off to put a mirror there. |
| `clearing`, `clearing_radius` | No tree stands within this radius of a point. Put it under the camera. |

The view draws round towers with a stone plinth, a string course and arrow slits. It draws blocks with windows, dormers and a ridge cap, or with a corbelled parapet of merlons and a gate arch. It draws the bridge with stone arch rings, brick piers, spandrel walls and parapets. It draws the moat between a brick revetment and a lawn bank. The wood has autumn crowns and dark conifers.

A mirror gives the moat its reflections. `examples/wijnendale.mojo` creates an `objects.reflector.Reflector` at the water level. It sets `options.water` to `False`, so the ring is not drawn twice.

## Limits

- The view does not draw interiors. It does not cut openings through walls. A window is a dark pane on the wall.
- A block has no wall thickness in the view. The plan holds the thickness for analysis.
- The plan is a reconstruction. Do not use it as a survey.
- A checked box in the README records implemented scope. It does not establish engineering validity for a real structure.

## Related pages

- [Castle analysis](Castle-analysis) gives the wind, arch, wall, moat and sun checks.
- [Building model](Building-model) holds buildings as one canonical model.
- [Retaining walls](Retaining-walls) gives the earth pressure that the moat wall check uses.
- [Water](Water) gives the Clearwater ocean.
