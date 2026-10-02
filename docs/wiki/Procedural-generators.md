# Procedural generators

The procedural generators of three.js's `examples/jsm/generators/`: a city, a forest, a terrain and a tree. The same seed and parameters give the same geometry and the same placements as three.js r186. The materials are not ported.

![A procedural tree turns under a lamp](out/generators.png)

`examples/sapling.mojo` draws this picture.

| Module | three.js |
|---|---|
| `generators/utils.mojo` | `createRandom`, `part` and `place` of the city, and the shared instanced lifecycle |
| `generators/tree.mojo` | `TreeGenerator` |
| `generators/terrain.mojo` | `TerrainGenerator` |
| `generators/forest.mojo` | `ForestGenerator` |
| `generators/city.mojo` | `CityGenerator` |
| `generators/skyscraper.mojo` | `city/SkyscraperGenerator` |
| `generators/sidewalk.mojo` | `city/SidewalkGenerator` |
| `generators/street_furniture.mojo` | `city/StreetlightGenerator`, `TrafficlightGenerator`, `TrashcanGenerator`, `BenchGenerator`, `HydrantGenerator`, `StreetTreeGenerator` |
| `generators/car.mojo` | `city/CarGenerator` |
| `generators/person.mojo` | `city/PersonGenerator` |
| `geometries/loft.mojo` | `geometries/LoftGeometry` |

## Seeds

Each generator makes its own seeded generator, three.js's `createRandom`. It is Mulberry32, the generator of `MathUtils.seededRandom`, so `generator_random(seed)` returns a `SeededRandom`. It keeps the low 32 bits of the seed. A seed of zero gives the numbers of a seed of one, as in three.js.

The generators compute in `Float64` and store `Float32`, as three.js does. The tests compare positions to a few `Float32` steps.

## Tree

`TreeGenerator(parameters).build()` grows a tree skeleton and bakes it into one indexed geometry with `position` and `normal`. `tubes()` returns the skeleton before the bake: each branch as a tube of rings.

- The trunk and every branch are tubes. A tube is swept in rings, one ring a step of `section_length`.
- A child forks from the upper part of its parent. It is thinner by the pipe model and tilted by `branch_angle`. The golden angle rolls it round the parent.
- `up_pull` pulls a child back toward the sky. `droop` makes a branch sag. The trunk does not sag.
- `gnarl` wobbles each step. `root_flare` swells the base of the trunk.

three.js sets a parameter with a fluent `set<Param>`. In this port, set the field of `parameters` and build again.

All tree parameters and list entries must be finite. The section length and radius exponent must be positive. The taper curve must be zero or more. An active root flare needs a positive flare fraction. These checks run before growth.

Finite parameters do not guarantee finite output. `tubes()` raises `Error` if a generated ring or branch length is nonfinite, or a generated direction is zero. Its returned frames have finite unit tangents and normals, perpendicular within floating-point precision. Large finite directions use scale-safe normalization.

Internal child sampling keeps three.js's independently normalized tangent and normal. The sampled pair need not be perpendicular. Each child tube starts with a new perpendicular normal.

`build()` also raises `Error` if a generated vertex is nonfinite or exceeds the finite `Float32` range. A finite skeleton can therefore succeed while its bake fails. Positions that round to zero remain supported. The checks apply to generated values, with no fixed upper bound on finite input parameters.

`up_pull`, `child_start` and `trunk_clear` accept finite values outside zero to one, as the three.js r186 setters do. Positive `up_pull` extrapolates the direction blend; zero and negative values disable it. Child placement clamps the sampled fraction to zero through 0.999. Other child calculations still use the original fraction. These values remain subject to the generated-output checks.

A zero child count stops branching. A level past the end of a parameter list reuses its last entry.

## Terrain

`TerrainGenerator(parameters).build()` bakes a mountain range into one indexed geometry in the ground plane, y up. The generator keeps the height grid. Then `sample_height` and `sample_slope` read the surface.

- The height is a sum of Perlin octaves from `ImprovedNoise`. A steep running slope damps each octave, so ridges stay sharp and valleys stay smooth.
- A slow noise warps the sample point first, so the ridges wander.
- Thermal erosion then relaxes each slope past the angle of repose, `talus`, over `talus_passes` passes.
- The seed moves the sample window only, because the permutation of `ImprovedNoise` is fixed.

`sample_height(x, z)` interpolates the four grid vertices round a point. `sample_slope(x, z)` is the y of the surface normal: one on level ground. `height_at` and `slope_at` do the same in `Float64` meters.

## Forest

`ForestGenerator(parameters).build(terrain)` scatters trees over a built terrain. It returns a `ForestInstances`: one blob geometry and one matrix a tree.

- The blob is an icosahedron welded to twelve vertices. It is squashed into a lumpy teardrop, and its `ao` attribute runs from zero at the base to one at the crown.
- A tree stands only in the altitude band, on ground flatter than `min_slope`, and inside a density mask of slow noise.
- The draw stops after fourteen tries a tree.
- `instances.values` holds three.js's `cull` attribute, and `region` holds its color drift.

The forest material culls far trees in a shader. `keeps(index, camera)` answers the same question on the CPU. A tree is drawn while its random threshold is at least its place in the band from `from_distance` to `to_distance`.

## City

`CityGenerator(parameters).plan()` lays the city out. It gives every tower's parameters and every placement of the furniture, and builds nothing. `build()` builds everything. It returns a `City` with one geometry a tower, the sidewalk, and the furniture as `Instances`.

- The city is a grid of blocks. A block is cut into lots inside a sidewalk strip.
- Each lot takes a skyscraper of its own seed, height and footprint. Only the four corner lots of a block cut a chamfer, toward their own corner.
- The furniture walks each curb edge: streetlights, street trees, a hydrant, sometimes a bench, pedestrians, parked cars and a few cars in the lanes. Two corners take a traffic signal, and every corner takes a litter basket.
- One seeded generator draws the towers lot by lot, then the furniture edge by edge, in three.js's order.

`build_proxy(plan)` returns three.js's `buildProxy`: one plain box a tower, for a global illumination bake.

The sidewalk needs a curb with a height. With a curb height of zero, `City.sidewalk` is none. three.js then builds a sidewalk with no instance.

## Skyscraper

`SkyscraperGenerator(parameters).layout()` returns every placement of every piece. `build()` bakes them into one geometry without an index. Every vertex has a `partId` for its zone, and the glass has the room behind it, `roomCenter` and `roomSize`.

The bake transforms normals as directions. A rigid placement rotates the normal without adding its translation. A scaled placement uses the inverse transpose of its linear part.

- The footprint is a rectangle with one corner cut at 45 degrees. Each edge is a face with a frame: `u` along the edge, `v` up, `n` out.
- The tower has three tiers: a base, a shaft and a crown. The crown steps back by `setback_depth` bays.
- The ground floor is a row of shopfronts. On a few seeds it is a pointed-arch arcade, `ARCADE`.
- The seed fills each style field that is left empty: the footprint, the tier split, the piers, the reveals and the arches.
- The floor and the bay snap to the brick module, three tenths of a meter high and six tenths long.

## Street furniture

Each piece is one merged geometry with a `partId`. `build(placements)` returns it as `Instances`, one matrix an instance. Each model stands on y equals zero and faces +z.

| Generator | Parts |
|---|---|
| `StreetlightGenerator` | metal, the lens |
| `TrafficlightGenerator` | metal, the red, amber and green lenses |
| `TrashcanGenerator` | the mesh, the rims, the trash |
| `BenchGenerator` | wood, iron |
| `HydrantGenerator` | the body, the bare caps |
| `StreetTreeGenerator` | the trunk, the leaves, the grate |
| `SidewalkGenerator` | a slab and a curb, two sets of instances |

`CarGenerator().build(cars)` deals each car a body: `SEDAN`, `SUV` or `TAXI`. The taxi's yellow takes the taxi. It returns one set of instances a body, with the linear paint of each car in `values`.

`PersonGenerator().build(placements)` deals each figure a pose, `WALK` or `STAND`, and its proportions. It returns the walking figures, then the standing figures. `values` holds each figure's seed.

## Loft

`loft(sections, closed, cap_start, cap_end)` is three.js's `LoftGeometry`. It skins a surface through cross sections that have the same number of points.

- A closed section is a ring. Its seam is smooth.
- `u` follows the loft by distance, and `v` follows each section by distance.
- A cap is a flat polygon with a hard edge. It faces away from the surface.

## Types

| Type | Values |
|---|---|
| `PartId` | The zone of a vertex, zero to eight. `part` refuses another value. |
| `BaseStyle` | `ARCADE`, `STOREFRONT` |
| `BodyType` | `SEDAN`, `SUV`, `TAXI` |
| `Pose` | `WALK`, `STAND` |

## What is not ported

- The materials: the bark, the canopy, the terrain, the road, the buildings, the concrete, the granite and each piece of furniture. They are TSL node graphs. The generators return geometry and placements only.
- `createBuildingMaterial`, `buildingColorNode`, `createRoadMaterial`, `createTreeMaterial` and `createForestMaterial`. `pick_building_color` and `building_palette` are ported.
- The shader sway of the street trees, and the distance fade of the forest's detail.
- The fluent `set<Param>` methods of `TreeGenerator`. Set the parameter fields.
- The lifecycle of three.js's meshes: `dispose`, and the reuse of a mesh when a city is built again. Each build returns new values.
- The street tree jitters its leaf clumps by a hash of the `Float32` positions. The hash turns a difference of one bit into a different jitter. So the lobes of the canopy can differ from three.js's where a primitive rounds a vertex differently.
