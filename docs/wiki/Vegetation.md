# Vegetation

`Meadow` builds open summer grassland: tall grass and flowers, bare dirt and a trail, trees and bushes of real leaves, and a canyon. Mountains, a clouded sky and a soft sun surround it.

![A dirt trail winds through wind-bent grass with poppies past a lone pale-trunked tree, with birches, groves, a band of cliffs and a woodland beyond](out/meadow.png)

`examples/meadow.mojo` draws this picture. The modules live in `extensions/vegetation/`. See [Extensions](Extensions). [Why grass is drawn in clusters](Why-grass-is-drawn-in-clusters) explains the design.

The field holds about ten million blades. A frame grows and draws only the clusters that it can see, each at the level of detail that its distance picks. The frame above draws 508,000 blades as 1.7 million triangles. The lone tree near the camera has 71,000 leaves.

## Draw one frame

```mojo
from core.assets import Assets
from core.scene import Scene
from extensions.vegetation.meadow import (
    Meadow,
    MeadowParameters,
    meadow_camera,
    meadow_renderer,
)
from units.si import METER, SECOND, Duration, Length

var renderer = meadow_renderer(1280, 720)
var assets = Assets()
var scene = Scene()
var parameters = MeadowParameters()
var meadow = Meadow(scene, assets, renderer, parameters)
var camera = meadow_camera(parameters, 1280, 720, Length(0.0, METER))
var stats = meadow.update(scene, assets, camera, Duration(2.0, SECOND))
var image = renderer.render(scene, assets, camera)
```

`Meadow` adds the ground, the cliff wall, the mountains, the plants and the boulders to the scene. It also adds the sky, the sun, the hemisphere light and the fog. It adds no grass. `update` grows the grass for one camera and one time. Call `update` before each `render`.

`meadow_renderer` uses every worker, ACES filmic tone mapping at an exposure of 0.8, soft shadows and four samples a pixel. `meadow_camera` stands the camera 1.6 meters above the ground and looks out over the grassland toward -z. Its last argument walks the camera toward -z.

## Animate the wind

```mojo
parameters.wind.loop = Duration(2.0, SECOND)
var meadow = Meadow(scene, assets, renderer, parameters)
var camera = meadow_camera(parameters, 400, 225, Length(0.0, METER))
for index in range(48):
    var seconds = 2.0 * Float32(index) / 48
    _ = meadow.update(scene, assets, camera, Duration(seconds, SECOND))
    frames.append(renderer.render(scene, assets, camera))
```

`examples/meadow_wind.mojo` writes this loop as an animated PNG, at 24 frames a second. Each frame culls the clusters again and grows the drawn clusters with the wind at that time. A camera that moves is placed again before each `update`.

A wind with a `loop` repeats itself after that time, so the animation plays round and round with no jump. Divide the loop evenly into the frames. Do not put a frame at the end of the loop: it is the first frame again.

### Blur each frame

A thin blade that moves a few pixels a frame jumps from frame to frame, and the field looks as if it buzzes. A film camera's shutter is open for part of each frame, so a moving blade smears. `blend_frames` gives the same blur: render a few moments inside the frame's shutter, and blend them.

```mojo
var moments = List[Framebuffer]()
for k in range(4):
    var within = (Float32(k) + 0.5) / 4 - 0.5
    var seconds = step * (Float32(index) + 0.5 * within)
    _ = meadow.update(scene, assets, camera, Duration(seconds, SECOND))
    moments.append(renderer.render(scene, assets, camera))
frames.append(blend_frames(moments))
```

`examples/meadow_wind.mojo` blends four moments across half of each frame's time. Each frame then costs four renders.

## What a frame draws

`update` returns a `FieldStats`.

| Field | Counts |
|---|---|
| `clusters` | Every cluster of the field. |
| `drawn` | The clusters in view and within the reach of a level. |
| `culled` | The clusters whose bound is outside the view. |
| `beyond` | The clusters past the reach of the last level. The ground stands in for them. |
| `empty` | The drawn clusters whose level grew no blade. They are hidden. |
| `blades` | The blades that the drawn clusters read from their streams. |
| `triangles` | The grass triangles of the drawn clusters. |

`examples/meadow.mojo` prints these counts and the time of each step as JSON. On a four-core Linux host, the meadow builds in 3 seconds. Each of its 12 crowns grows once, and each of its 4 levels draws from that. `update` takes 0.3 seconds, and the render takes 21 seconds at 1280 by 720.

The wind loop renders 4 moments for each of its 48 frames, and takes about 55 minutes at 640 by 360. The render time grows with the triangle count. It changes little with the image size or the four samples a pixel.

## The parts

| Module | Holds |
|---|---|
| `kinds.mojo` | `PlantKind` and `ClusterFate`. |
| `checks.mojo` | The range checks that the parameters share. |
| `noise.mojo` | `hash01`, `value_noise`, `value_noise3` and `layered_noise`. |
| `wind.mojo` | `Wind`: gusts that travel downwind, a sway, and a flutter. |
| `blade.mojo` | `Blade`, and `BladeMesh`, which bakes blades into one geometry. |
| `ground.mojo` | `Ground`: hills, a `Canyon`, the grass masks, the ground mesh, the cliff wall and the mountain ring. |
| `field.mojo` | `GrassField`: clusters, levels of detail and the blade stream. |
| `limbs.mojo` | `CrownShape`, `LimbParameters` and `grow_limbs`: branches grown by space colonization, and `limb_mesh`. |
| `litter.mojo` | `ground_litter`: fallen leaves, twigs and pebbles on bare ground. |
| `foliage.mojo` | `LeafShade`, the light through the leaves, `LeafMesh`, `foliage_program`, `wood_program` and `sway_offset`. |
| `crown.mojo` | `grow_crown`, `dress` and `leafy_tree`: the limbs, the leaves on the twigs, and their light. |
| `rock.mojo` | `boulder`: a stone pushed out by noise, with moss on top. |
| `sky.mojo` | `paint_sky`: Preetham's sky with clouds, baked into a cube. |
| `meadow.mojo` | `Meadow`, its parameters and plantings, its camera and its renderer. |

## Grass

A blade is a strip of quads that ends in one triangle. A blade of `n` segments has `2n + 1` vertices and `2n - 1` triangles. Each segment turns toward the blade's front by its share of `curl`, and by its share of the wind's bend. The two turns add as one tilt of at most 83 degrees. Each segment keeps its length.

The width tapers as `1 - s * s`, where `s` runs from zero at the root to one at the tip. Each edge normal tilts out toward its edge, so a flat strip is lit as if it were round. Each normal also tilts up, so the field is lit as one soft surface.

The root color is dark, and the tip color is light. The dark root stands in for the shadow of the dense grass round it. `shade` mixes between two tip colors, so neighbors differ.

The blades of a tuft curl out from its middle. A tuft has `tuft_blades` blades at full detail. Each tuft is a plant of its own. Its height, the width of its blades, how far they curl, their shade and their sway are its own, and its blades vary round them. So the field has tall tufts beside short ones, and broad blades beside fine ones.

- A patch of the field 3.5 meters wide is a deeper or a yellower green.
- `Ground.tallness` makes islands of tall grass and patches of short grass, a fifth as tall, as on a path or where animals graze.
- 14 percent of the tufts are laid over by wind and rain. Their blades arch over and lie.
- Where the ground is bare, no grass grows. Toward a bare patch the grass thins, and it is trodden down to 30 percent of its height. See [Bare ground and litter](#bare-ground-and-litter).

| Kind | Looks |
|---|---|
| `GRASS` | Dark green at the root and yellow-green at the tip. |
| `DRY_GRASS` | Straw at the tip. More of them grow where the ground is dry. |
| `POPPY` | A thin stem with a cup of five red petals. They grow in drifts. |
| `SEED_HEAD` | A tall thin stalk with a spike of two crossed strips. It stands above the grass. `seed_share` of the blades are stalks. |
| `BROADLEAF` | A low rosette of five oval leaves, 12 to 28 centimeters long, as a plantain or a dock is. More grow where `Ground.weeds` is high. |
| `BUTTERCUP` | A thin stem with a small cup of five yellow petals, in the grass. They grow with the weeds. |

### Levels of detail

`default_bands` returns four levels.

| Reach | Keeps | Segments | Widens |
|---|---|---|---|
| 7 meters | every blade | 4 | 1 |
| 18 meters | 40 percent | 3 | 1.9 |
| 40 meters | 13 percent | 2 | 4.2 |
| 85 meters | 4 percent | 1 | 9.5 |

A cluster takes the first level whose reach holds its nearest point. A level that keeps fewer blades widens each by `keep ** -0.7`. A level must reach further than the one before, and it must keep no more.

## Wind

`Wind` has a heading, a lean, a calm, gusts, a sway and a flutter. The default wind blows across the view, from left to right.

- **A gust** is a patch of value noise that travels downwind at `gust_speed`. It is `gust_length` long along the wind, and 1.8 times that across it, so a gust front is a band. A slower noise bends each front into a ragged curve, and smaller gusts cross the large ones at 35 degrees. `gust` returns its strength at a point, from zero to one. The noise between 0.39 and 0.61 of its range maps onto that, so a gust front is sharp.
- **A sway** is a wave that rolls downwind every `sway_length`, `sway_rate` times a second. Its shape is a sine and a third of its double, so a tip snaps forward and springs back. The sway is mostly in the gusts.
- **A flutter** is a slight tremble of each blade on its own, with its own phase.

`tip_bend` returns the angle that the tip turns from upright, as a vector on the ground. Calm air leans the tip by `calm` of `lean`, and a full gust by all of `lean`. The sway and the flutter add to that. Each segment of a blade turns by a share of the bend that grows with its height. So the blade arcs over, and its root stays put.

The gust is the largest part. A gust front that passes bends the whole patch over and lets it rise again. A full gust also brightens the tips it reaches by up to 100 percent, so the gusts roll across the field as bands of light. Keep the flutter small and slow: a large, fast flutter of thin blades reads as jitter, not as wind.

A poppy's stem and a seed stalk bend as a blade does. Their heads ride high, so they swing the most. A broad-leaf rosette moves its tips a quarter as far as a blade.

`tree_sway` leans a tree from its foot by a small share of the lean. A full gust leans it 2.5 percent of `lean` downwind, about 1.3 degrees. It also rocks by 0.8 percent of `lean`, once every 2 seconds. `Meadow.update` turns each tree by its sway, about a level axis only, so the sun baked into its leaves stays true.

With a `loop`, the gusts at a time fade into the gusts a loop earlier. The fade divides by `sqrt((1 - w)^2 + w^2)`, so a gust keeps its contrast in the middle of the loop. The sway and the flutter swing a whole number of times a loop.

## Trees

`grow_crown` grows a tree in two steps. `grow_limbs` grows the branches by space colonization, and `hang_leaves` hangs the leaves on the twigs. `dress` then makes the meshes of one level of detail. `leafy_tree` does all three.

### Branches

`CrownShape` says where the crown is. It is an egg round the trunk, from `bottom` to `top`, `radius` wide where it is widest. The crown is made of `lobes` balls of about `lobe_size`. Their middles lie in the outer part of the egg, and they can bulge past it. `ragged` dents the outline and carves small gaps. `hollow` keeps the middle of the crown bare.

`grow_limbs` scatters `points` in the lobes. These are the places that the leaves reach for. Then the tree grows:

1. The trunk climbs from the ground to `fork` of the way up the crown, and on until a point is within `reach` of its top.
2. Each point pulls the node nearest to it, if the node is within `reach`.
3. Each node that is pulled grows a new node a `step` away, toward the mean of its pulls. `up_pull` bends the growth up. `droop` bends it down far out from the trunk. `gnarl` turns it a little at random.
4. A point within `kill` of a node is reached, and pulls no more.
5. The growth stops when no node grows.

Points close together pull one branch. Points apart split it in two. So a limb grows into each lobe, and the lobes have sky between them. A node's radius to the power `pipe` is the sum of its children's, and each twig tip is `tip_radius` thick. The trunk flares at its foot by `flare`.

`limb_mesh` draws a tube along each chain of nodes. A chain follows the thickest child at each fork. A branch thinner than `wood_radius` is left out, because the leaves hide it. The bark is pale with dark patches, and darker near the ground. `bark_marks` patches climb each meter of the trunk: a birch has many short ones.

### Leaves

Each node within `leaf_reach` of a twig's tip carries `leaves_per_node` leaves on the stretch of twig below it. A leaf splays out from its twig, toward the twig's tip and a little down. It turns its face up and out of the crown. The leaves of one twig make a spray, and the sprays of one limb make a lobe. Neighboring twigs share a tint, and a slow noise makes patches of the crown 2 meters wide lighter or darker.

A near leaf is `OVATE`: a base, three pairs of edge vertices and a tip, six triangles. Its halves tilt their normals apart, so it is lit as if it were folded.

| Crown | Looks |
|---|---|
| `CrownParameters()` | An open tree 14.5 meters tall. Its pale trunk is bare for 5 meters and forks into thin limbs. Its crown is 12 meters across, nine lobes of 15-centimeter leaves. |
| `windswept_tree()` | A slender tree 12.5 meters tall. Its dark trunk leans and wanders, and its narrow crown is a few wisps of leaves. |
| `birch_tree()` | A birch 16 meters tall. Its white trunk has short dark marks and is bare for 6 meters. Its narrow crown is small, light leaves on limbs that droop. |
| `young_tree()` | A young tree 9.4 meters tall. Its crown is a tall oval from 2 meters up, 4 meters across. |
| `round_tree()` | A dense tree 11 meters tall. Its dark crown reaches nearly to the ground, 9 meters across. |
| `bush_parameters()` | A bush 1.9 meters tall that forks from the ground, with leaves 12 centimeters long. |

### The light in a crown

`LeafShade` counts the leaves in a grid of cells. Each leaf adds its area to its cell. A cell's leaf area over its volume, times `shade`, is how much a meter of it dims light. The grid is blurred once along each axis.

`LeafShade.through` follows the ray from a leaf toward the sun, and steps three quarters of a cell at a time. The light that comes through is `exp(-sum)` of the dimming along the ray. `LeafShade.sky` averages the same over 13 directions of the open sky: straight up, six at 45 degrees and six at 10 degrees. A leaf in the shade still gets a tenth of the sun, which the leaves between pass on.

Each leaf keeps the two numbers as its `sunlit` and `skylit` attributes. `foliage_program` uses the first as the leaf's shadow, so it dims only the sun. It uses the second as the ambient occlusion, so it dims only the sky. A leaf that sees neither is left out. A planting is never turned about +y, because the sun's direction is baked into its leaves.

### Levels of detail

`default_crown_levels` returns four levels. A crown is grown and lit once, and `dress` draws each level from it.

| Reach | Keeps | Leaves | Wood |
|---|---|---|---|
| 40 meters | every leaf | ovate | full |
| 110 meters | 40 percent | ovate | full |
| 300 meters | 16 percent | cards | lean |
| past that | 5 percent | cards | lean |

A kept leaf grows by the inverse square root of the fraction, so the crown keeps its cover. A card is a diamond of two triangles. Lean wood draws only the branches three times as thick as `wood_radius`, with three vertices round each ring. A level of ovate leaves sways in the wind, and a level of cards stands still.

### The wind in a crown

`foliage_program(motion)` and `wood_program(motion)` move each vertex of the leaves and of the wood by `sway_offset`. The offset is a swing along the wind and a flutter up and down. `Wind.crown_motion` gives both. In the default wind, an outer twig swings 30 centimeters once a second. A leaf flutters 3.5 centimeters 2.5 times a second.

A vertex sways by its place in the tree. The share is the square of its height over 12 meters, at most 1.5. It is 0.35 of that at the trunk, and all of it 4 meters out from it. A bush only rustles.

The swing's phase changes slowly through the crown, so a limb and its leaves move together and the lobes move apart. The flutter's phase changes fast, so each spray flutters on its own. The leaves and the wood read the same offset, so a leaf stays on its twig.

The time is the `SWAY_TIME` uniform, which `Meadow.update` sets each frame. A looping wind's rates are whole numbers a loop, so the crowns loop with the grass.

## Layout

`MeadowParameters.crowns` lists the kinds of tree and bush. `plantings` lists each tree and bush: the crown it wears, where it stands, and its size. `scatter_plantings` scatters plantings across the view toward -z, between two distances. `grove_plantings` stands plantings together round a point.

`default_crowns` returns twelve crowns: three open trees, a windswept tree, two young trees, two round trees, two birches, a green bush and a gray-green bush.

`default_plantings` places a lone open tree and a bush near the camera, a second open tree, and a windswept tree. A grove of mixed trees, a grove of birches and a grove at the back stand from 60 to 140 meters. 14 trees and 30 bushes are scattered from 12 to 160 meters. A woodland of 120 young and round trees stands from 428 to 520 meters, just past the canyon's far rim. They are 1.3 to 1.9 times their crowns' size, so their tops show above the band of cliffs.

## Bare ground and litter

`Ground.bare` is one where the ground is bare dirt, and the grass's cover is zero there.

- **Dirt patches.** `dirt` sets how much of the field is bare, from 0 to 1. The patches are about 13 meters across, with soft edges. The meadow's ground has a `dirt` of 0.2.
- **The trail.** A trail `trail_width` wide winds away from the camera's side of the field and drifts toward the groves on the right. Its middle is 92 percent bare, so a few tufts grow on it, and its edge is 1.3 meters wide. The meadow's trail is 1.2 meters wide.
- **Clearings.** A `Clearing` is the shade round a tree's foot, 80 percent of its crown's radius. `openness` is zero in its inner quarter and rises smoothly to one at its edge. `GrassField.cover_at` thins the grass by it. `litter_shade` browns the ground mesh under it, toward leaf litter. The meadow makes a clearing for each tree and bush near the field.

Bare ground is mottled dirt, light and dark brown.

`ground_litter` scatters fallen leaves, twigs and pebbles on the bare ground. It tries `litter` points within `litter_reach` of the field's middle. A point in full shade is littered 90 times in a hundred, and a point of bare dirt 50 times.

Of the litter, 78 percent is leaves, 17 percent is pebbles and the rest is twigs. A leaf is a diamond that lies on the ground, brown, ochre or a dull green. A pebble has eight faces, each with its own normal. All of it is one mesh that takes the sun's shadow.

## Ground, sky and light

`Ground` gives the height of rolling hills and its masks. They are the bareness, the cover, the tallness, the dryness, the weeds, the bloom and the far color. The ground mesh carries the far color. Past the last level of detail, the ground looks like the grass that it stands in for. The meadow's ground mesh has 512 cells across, so its cells near the camera are half a meter to a meter wide.

A `Canyon` crosses the ground toward -z. Its floor is `depth` below the near side, and its far plateau is `rise` above it. Each rim is a smooth step 6 meters wide. The default canyon's near rim is 300 meters from the origin and its far rim 420 meters. It is 80 meters deep, and the far side rises 38 meters. The far wall then shows above the near rim as a band of cliffs.

`cliff_wall` builds that wall as a dense face of rock. It stands just in front of the far rim, and hides the ground mesh's coarse step there. Buttresses and flutes run down it, a few ledges cross it, and dark strata band it. Moss grows along its top, and its crest is ragged.

`paint_sky` draws Preetham's sky into a small cube and reads it into a large cube. It then paints the clouds. `gain` scales the sky's light, and `saturation` and `tint` deepen its blue. The cube is the scene's background. Its mean color near the horizon is the fog's color.

The sun stands 38 degrees high, ahead of the camera and to its right. The grass glows against it, the trees are dark toward the camera with bright edges, and their shadows fall toward the camera.

The sun is a `SunLight` with two cascades of 4,096 texels that reach 150 meters. The trees, the bushes, the grass and the boulders cast shadows. The grass, the ground and the wood receive them. A hemisphere light gives the blue light of the sky and the green light that the grass sends back. The blades and the leaves are lit from both sides: `two_sided_program` and `foliage_program` turn the normal of a back face to the front.

The mountains are `ridge_ring`, a ring of rugged peaks 900 meters away. Each column of the ring rises to its crest over nine rows, and gullies cut its slopes. Snow lies on the highest tips. The fog veils them to a hazy blue.

`paint_sky` lights each cloud by how much cloud lies between it and the sun. So a cloud is white on its sunward edge and gray where more cloud shades it.

## Types

| Type | Values |
|---|---|
| `PlantKind` | `GRASS`, `DRY_GRASS`, `POPPY`, `SEED_HEAD`, `BROADLEAF`, `BUTTERCUP` |
| `ClusterFate` | `DRAWN`, `CULLED`, `BEYOND` |

## Limits

- The CPU culls and grows the clusters, and the CPU rasterizer draws them. There is no GPU path yet.
- Culling tests each cluster's bound against the view only. A cluster behind a hill is still drawn.
- There is no visibility buffer. The rasterizer shades each fragment as it draws it.
- The grass casts into the same two cascades as the trees. Its shadow on itself is only as sharp as their texels. So the dark roots still stand in for the shadow at the base of each tuft.
- A crown is shadowed by its own leaves only. The shadow of another tree does not fall on its leaves.
- A crown sways by the place of each vertex in the tree, not by the gusts that reach it. Only the lean from its foot follows the gusts.
- Litter lies only within `litter_reach` of the field's middle.
- The indirect light is a hemisphere light and baked occlusion. The voxel and screen-space passes of the renderer are not used.
