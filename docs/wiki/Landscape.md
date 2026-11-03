# Landscape

A landscape puts four methods in one picture: a procedural castle, Clearwater water, mountains with woods, and a church that was scanned as Gaussian splats. The castle is a mesh. The church is 938,000 splats. They stand on one ground, under one sun, and the picture shows the water reflecting what is near it.

![Wijnendale Castle on a plain with a scanned Danish church in front, autumn woods, a lake and snow-capped mountains behind](out/wijnendale-landscape.png)

The picture comes from `examples/wijnendale_landscape.mojo`. The render takes about 20 seconds at 1920 by 1080 on 24 CPU threads, after the compile. The church is "Seem Kirke, Danmark" by roedsgaard, under CC BY 4.0. See [Scanned buildings](Scanned-buildings). Fetch it first:

```bash
sh tools/tool.sh .venv/bin/mojo building_scans fetch seem-church --pin
.venv/bin/mojo run -I . examples/wijnendale_landscape.mojo out/wijnendale-landscape.png
```

If the scan is not fetched, the example draws the landscape without the church. A note on the standard error says how to fetch it.

## What joins what

| Part | Where it comes from | How it meets the others |
|---|---|---|
| Castle | `castle_meshes` of the plan of Wijnendale | The ground round its moat is the castle's own `ground_height` |
| Water | The Clearwater of `extensions.water` | One plane at the level of the moat. It floods every basin under that level |
| Mountains | The `TerrainGenerator` of `generators.terrain` | A weight raises them from zero at the castle to one far off |
| Woods | `extensions.castle.forest` | They stand on the drawn triangles, and stop at the shore and the treeline |
| Church | A scan, as Gaussian splats | Blended into the picture, hidden behind every nearer surface |

## The ground

`build_landscape(plan, default_landscape())` makes one ground. Round the moat it is the castle's meadow, bank and moat bed, so the plan decides the height there. Farther out it is the mountain range, lowered so that its lowest ground is the plain of the castle. A weight rises from zero to one with the distance from the moat. So the mountains start where the meadow ends, and nothing jumps.

Where the mountains sink under the plain they make lake beds. The water of the moat is the water of the lake. The one plane of Clearwater at the level of the moat floods every basin that lies under it. Where a basin is nearer than the water, the water is drawn. Where a hill is nearer, the hill is drawn.

The ground is four square rings, from fine to coarse. The finest has 1 m cells round the castle. The others have cells 5, 20 and 80 times wider, out to 9.6 km. The height at the edge of a fine ring is read from the coarse ring beside it, so two rings meet with no crack. The diagonal of each cell turns on every other cell, so no ridge runs along it.

`Landscape.height` reads the same triangles that are drawn. A tree that stands at that height stands on the ground, and not above it or in it.

| Setting | Default | Meaning |
|---|---|---|
| `relief` | 1500 m | The height from the lowest ground to the peaks |
| `footprint` | 3.2 km | The width of a mountain |
| `range` | 7 km | The width of a range, and of the basin between two ranges |
| `plain_share` | 0.10 | The share of the mountains' ground at or under the plain. A larger share leaves more lakes |
| `lake_depth` | 12 m | The depth that the lowest basins sink under the plain |
| `plain_radius`, `hills_radius` | 150 m, 700 m | Inside the first the ground is the castle's. Beyond the second the mountains stand full height |
| `near_step` | 1 m | The cell of the finest ring |
| `reach` | 9.6 km | How far the ground runs |
| `treeline`, `snow_line` | 260 m, 400 m | The altitudes over the water where the trees stop and the snow lies |
| `haze` | 0.00022 a meter | The fog of the scene, which is the color of the horizon |

## The look of the ground

A cell is meadow, rock or snow. A steep cell is rock whatever its altitude. Snow lies on the cells above the snow line that are not too steep to hold it, with a ragged edge. The meadow wears the grass texture of the castle. Its color follows the season, the altitude and the wood.

- On the low flat ground the meadow is fields of five tones: stubble, plowed earth, bright pasture, a green crop and hay. The edges of the fields are bent by noise.
- Over the treeline the meadow is yellow-green.
- Under the trees the floor is dark, and the margin of the water is dark and wet.
- At the edge of the snow, the meadow and the rock take its white, so a cell of another material is not a square.

## The woods

`plant_forest` plants the trees by rules, and not by a hand. A tree needs dry ground above the water, ground that is not too steep, and room round the moat. The woods grow in groves: a slow noise draws the groves and the clearings. The plain is mostly fields with woodlots, and the hills are mostly wood.

- The treeline is ragged. The wood thins and the trees shrink toward it. None grows over it.
- The kind follows the altitude: broadleaf trees in the lowland, spruce and fir higher, and larch near the treeline.
- The size follows the stand. A stand is a patch of trees of one age. A few dominant trees stand taller than the rest.
- A clearing keeps a round place free of trees, such as a churchyard or a line of sight.

A tree is drawn by what its distance from the eye asks. A tree near the eye needs its leaves. A wood a kilometer away needs its silhouette, its layers and its shade.

| Tier | Distance | The tree |
|---|---|---|
| 0 | To 110 m | The branching skeleton with a card of leaves at every twig, in full detail: 9,000 to 19,000 triangles |
| 1 | To 320 m | The same skeleton in reduced detail: 4,000 to 7,000 triangles |
| 2 | To 1.2 km | A crown: tiers of drooping sprays for a conifer, clusters of crossed leaf cards for a broadleaf tree. A few hundred triangles |
| 3 | To 2.6 km | A stack of cones, or a lumpy ball on a trunk. Muted by the air |

Every vertex of a crown has a color that is the shade of the tree at that place. The inside and the lower tiers lie in the shade of the rest. The tips and the top catch the light. The color of an instance tints it, so one shape stands for a wood in autumn. Past 2.6 km the color of the ground gives the forest.

A caller can give the camera's heading and field of view. Then only the trees that the camera sees are planted, with a margin and the ground round the eye. That keeps a picture of a kilometer-wide wood to a few million triangles.

## Splats in a mesh scene

A scanned building is a million Gaussian splats, and the castle is triangles. They meet in the picture.

1. The renderer draws the meshes, and the sky is painted. That leaves a picture and a depth for each pixel.
2. `composite_splats` blends the splats of each scan into that picture. It hides a splat where a surface of the mesh scene is nearer.
3. The water is composed, and the mirror image is added.

So a hill, a wall or a tree stands in front of the scan, and the scan stands in front of what lies behind it. A splat writes no depth, as every transparent surface does not. `splat_layer` stands a scan on the ground. It puts the middle of the scan's box at a place of the plan and its floor at a height. Then it turns the scan about the vertical. `find_site` finds open, level, dry ground for it, as near as it can be to a place.

```mojo
var land = build_landscape(plan, default_landscape())
var site = find_site(land, -100.0, 40.0, 24.0, 45.0)
var clearings = List[Clearing]()
clearings.append(Clearing(site.x.value, site.y.value, 55.0))
var castle = build_landscape_scene(plan, default_settings(), land, woods, clearings)
add_splat_layer(castle, splat_layer(scan.splats, scan.frame, site.x.value, site.y.value,
                                    land.height(site.x.value, site.y.value), 0.0))
var image = draw_castle(castle, renderer, camera, 0.5, 5)
```

The splats keep the colors of the capture. The sun that lit the church is not the sun of the scene, and a splat has no shadow of the trees. The church is not in the mirror image of the water. Keep the church away from the shore.

## Limits

- The picture is made for one camera. The woods and the ground follow the eye that the caller gives. A fly-through needs the woods planted again at each stop.
- The ground has no rivers, roads or buildings other than the castle and the scans. A river needs a flow field over the mountains.
- The splats of a scan are drawn on the CPU here. `scan_view_gpu.mojo` draws the same scan on a GPU. See [GPU splats](GPU-splats).
- The water is one level. A lake higher than the moat needs a second plane.

## See also

[Castle](Castle) for the plan and the mesh view. [Scanned buildings](Scanned-buildings) for the scans and their credits. [Gaussian splats](Gaussian-splats) for the splat format and the draw. [Water](Water) for Clearwater.
