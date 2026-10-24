# Vegetation

`Meadow` builds open summer grassland: tall grass, poppies, trees and bushes of real leaves, a canyon, mountains, a clouded sky and a soft sun.

![A lone pale-trunked tree stands in tall grass, with scattered trees, a band of cliffs and hazy mountains beyond](out/meadow.png)

`examples/meadow.mojo` draws this picture. The modules live in `extensions/vegetation/`. See [Extensions](Extensions). [Why grass is drawn in clusters](Why-grass-is-drawn-in-clusters) explains the design.

The field holds about ten million blades. A frame grows and draws only the clusters that it can see, each at the level of detail that its distance picks. The frame above draws 474,000 blades as 1.6 million triangles. The lone tree near the camera has 135,000 leaves.

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

`examples/meadow.mojo` prints these counts and the time of each step as JSON. On a four-core Linux host, the meadow builds in 12 seconds, most of it the 21 crowns. `update` takes 0.2 seconds, and the render takes 21 seconds at 1280 by 720. The 48 frames of the wind loop take about 15 minutes at 400 by 225. The render time grows with the triangle count. It changes little with the image size or the four samples a pixel.

## The parts

| Module | Holds |
|---|---|
| `kinds.mojo` | `PlantKind` and `ClusterFate`. |
| `checks.mojo` | The range checks that the parameters share. |
| `noise.mojo` | `hash01`, `value_noise` and `layered_noise`. |
| `wind.mojo` | `Wind`: gusts that travel downwind, and a flutter. |
| `blade.mojo` | `Blade`, and `BladeMesh`, which bakes blades into one geometry. |
| `ground.mojo` | `Ground`: hills, a `Canyon`, the grass masks, the ground mesh, the cliff wall and the mountain ring. |
| `field.mojo` | `GrassField`: clusters, levels of detail and the blade stream. |
| `foliage.mojo` | `Clump`, the light through clumps, `LeafMesh` and `foliage_program`. |
| `crown.mojo` | `leafy_tree`: branches from `TreeGenerator`, clumps on the twigs, and leaves with their light. |
| `rock.mojo` | `boulder`: a stone pushed out by noise, with moss on top. |
| `sky.mojo` | `paint_sky`: Preetham's sky with clouds, baked into a cube. |
| `meadow.mojo` | `Meadow`, its parameters and plantings, its camera and its renderer. |

## Grass

A blade is a strip of quads that ends in one triangle. A blade of `n` segments has `2n + 1` vertices and `2n - 1` triangles. Each segment turns toward the blade's front by its share of `curl`, and by its share of the wind's bend. The two turns add as one tilt of at most 83 degrees. Each segment keeps its length.

The width tapers as `1 - s * s`, where `s` runs from zero at the root to one at the tip. Each edge normal tilts out toward its edge, so a flat strip is lit as if it were round. Each normal also tilts up, so the field is lit as one soft surface.

The root color is dark, and the tip color is light. The dark root stands in for the shadow of the dense grass round it. `shade` mixes between two tip colors, so neighbors differ.

The blades of a tuft curl out from its middle. A tuft has `tuft_blades` blades at full detail.

| Kind | Looks |
|---|---|
| `GRASS` | Dark green at the root and yellow-green at the tip. |
| `DRY_GRASS` | Straw at the tip. More of them grow where the ground is dry. |
| `POPPY` | A thin stem with a cup of five red petals. They grow in drifts. |
| `SEED_HEAD` | A tall thin stalk with a spike of two crossed strips. It stands above the grass. `seed_share` of the blades are stalks. |

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

`Wind` has a heading, a lean, a calm, a gust length, a gust speed and a flutter. A gust is a patch of value noise that travels downwind at `gust_speed`. `gust` returns its strength at a point, from zero to one.

`tip_bend` returns the angle that the tip turns from upright, as a vector on the ground. A full gust leans the tip by `lean`. Between gusts the wind keeps `calm` of the lean. The flutter adds a wobble along the wind and a smaller one across it.

A gust also brightens the tips it reaches by up to 80 percent. The field then shows each gust as a wave of light.

With a `loop`, the gusts at a time fade into the gusts a loop earlier. The fade divides by `sqrt((1 - w)^2 + w^2)`, so a gust keeps its contrast in the middle of the loop. The flutter wobbles a whole number of times a loop.

## Trees

`leafy_tree` grows the branches with `TreeGenerator`. A twig is a tube thinner than `twig_radius` at its tip. Each twig carries a clump of leaves at its tip, and one more every `clump_spacing` back along its thin end. A clump is a sphere of about `clump_radius`.

A clump holds up to `leaves_per_clump` leaves. They crowd its shell, and the shell is lumpy, so a clump has a ragged edge. Each leaf faces out of its clump and up, and its midrib hangs a little. A near leaf is `OVATE`: a base, three pairs of edge vertices and a tip, six triangles. Its halves tilt their normals apart, so it is lit as if it were folded.

| Crown | Looks |
|---|---|
| `CrownParameters()` | A slender tree 14 meters tall. The pale trunk is bare for half its height, and long limbs spread a crown of separate clumps. |
| `broad_tree()` | A broad tree 12 meters tall that forks low, with more and larger clumps. |
| `bush_parameters()` | A bush 1.3 meters tall that forks from the ground, with leaves 12 centimeters long. |

The bark is pale with dark patches, and darker near the ground.

### The light in a crown

`sun_through` follows the ray from a leaf toward the sun and adds the length of each clump that it crosses. The light that comes through is `exp(-density * length)`. `sky_through` averages the same over seven directions of the open sky. Both are exact for spheres.

Each leaf keeps the two numbers as its `sunlit` and `skylit` attributes. `foliage_program` uses the first as the leaf's shadow, so it dims only the sun. It uses the second as the ambient occlusion, so it dims only the sky. A leaf that sees neither is left out. A planting is never turned, because the sun's direction is baked into its leaves.

### Levels of detail

`default_crown_levels` returns three levels.

| Reach | Keeps | Leaves | Wood |
|---|---|---|---|
| 40 meters | every leaf | ovate | full |
| 110 meters | 40 percent | ovate | full |
| past that | 16 percent | cards | lean |

A kept leaf grows by the inverse square root of the fraction, so the crown keeps its cover. A card is a diamond of two triangles. Lean wood has one level of branches fewer, and three vertices round each ring.

## Layout

`MeadowParameters.crowns` lists the kinds of tree and bush. `plantings` lists each tree and bush: the crown it wears, where it stands, and its size. `scatter_plantings` scatters plantings across the view toward -z, between two distances.

`default_crowns` returns three slender trees, two broad trees and two bushes, each of its own seed. `default_plantings` places a lone tree and a bush near the camera, and a second lone tree. It scatters 22 trees from 45 to 160 meters and 26 bushes from 12 to 120 meters. 45 broad trees stand from 435 to 700 meters, on the far side of the canyon.

## Ground, sky and light

`Ground` gives the height of rolling hills and four masks: the cover, the dryness, the bloom and the far color. The ground mesh carries the far color. Past the last level of detail, the ground looks like the grass that it stands in for.

A `Canyon` crosses the ground toward -z. Its floor is `depth` below the near side, and its far plateau is `rise` above it. Each rim is a smooth step 6 meters wide. The default canyon's near rim is 300 meters from the origin and its far rim 420 meters. It is 80 meters deep, and the far side rises 38 meters. The far wall then shows above the near rim as a band of cliffs.

`cliff_wall` builds that wall as a dense face of rock. It stands just in front of the far rim, and hides the ground mesh's coarse step there. Buttresses and flutes run down it, a few ledges cross it, and dark strata band it. Moss grows along its top, and its crest is ragged.

`paint_sky` draws Preetham's sky into a small cube and reads it into a large cube. It then paints the clouds. `gain` scales the sky's light, and `saturation` and `tint` deepen its blue. The cube is the scene's background. Its mean color near the horizon is the fog's color.

The sun is a `SunLight` with two cascades of 4,096 texels that reach 150 meters. The trees, the bushes, the grass and the boulders cast shadows. The grass, the ground and the wood receive them. A hemisphere light gives the blue light of the sky and the green light that the grass sends back. The blades and the leaves are lit from both sides: `two_sided_program` and `foliage_program` turn the normal of a back face to the front.

The mountains are `ridge_ring`, a ring of rugged peaks 900 meters away. Each column of the ring rises to its crest over nine rows, and gullies cut its slopes. Snow lies on the highest tips. The fog veils them to a hazy blue.

`paint_sky` lights each cloud by how much cloud lies between it and the sun. So a cloud is white on its sunward edge and gray where more cloud shades it.

## Types

| Type | Values |
|---|---|
| `PlantKind` | `GRASS`, `DRY_GRASS`, `POPPY`, `SEED_HEAD` |
| `ClusterFate` | `DRAWN`, `CULLED`, `BEYOND` |

## Limits

- The CPU culls and grows the clusters, and the CPU rasterizer draws them. There is no GPU path yet.
- Culling tests each cluster's bound against the view only. A cluster behind a hill is still drawn.
- There is no visibility buffer. The rasterizer shades each fragment as it draws it.
- The grass casts into the same two cascades as the trees. Its shadow on itself is only as sharp as their texels. So the dark roots still stand in for the shadow at the base of each tuft.
- A crown is shadowed by its own clumps only. The shadow of another tree does not fall on its leaves.
- The indirect light is a hemisphere light and baked occlusion. The voxel and screen-space passes of the renderer are not used.
