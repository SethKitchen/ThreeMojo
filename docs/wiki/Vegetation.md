# Vegetation

`Meadow` builds a summer meadow: tall grass, poppies, a treeline, boulders, a sky with clouds, and a sun with soft shadows.

![Tall grass and red poppies rise to a treeline under a summer sky](out/meadow.png)

`examples/meadow.mojo` draws this picture. The modules live in `extensions/vegetation/`. See [Extensions](Extensions). [Why grass is drawn in clusters](Why-grass-is-drawn-in-clusters) explains the design.

The field holds about ten million blades. A frame grows and draws only the clusters that it can see, each at the level of detail that its distance picks. The frame above draws 443,000 blades as 1.5 million triangles.

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

`Meadow` adds the ground, the mountains, the trees, the boulders, the sky, the sun, the hemisphere light and the fog to the scene. It adds no grass. `update` grows the grass for one camera and one time. Call `update` before each `render`.

`meadow_renderer` uses every worker, ACES filmic tone mapping at an exposure of 0.8, soft shadows and four samples a pixel. `meadow_camera` stands the camera 1.05 meters above the ground and looks up the slope to the trees. Its last argument walks the camera toward the trees.

## Animate the wind

```mojo
var camera = meadow_camera(parameters, 480, 270, Length(0.0, METER))
for index in range(16):
    var seconds = Float32(index) * 0.12
    _ = meadow.update(scene, assets, camera, Duration(seconds, SECOND))
    frames.append(renderer.render(scene, assets, camera))
```

`examples/meadow_wind.mojo` writes this loop as an animated PNG. Each frame culls the clusters again and grows the drawn clusters with the wind at that time. A camera that moves is placed again before each `update`.

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

`examples/meadow.mojo` prints these counts and the time of each step as JSON. On a four-core Linux host, the meadow builds in 0.23 seconds. `update` takes 0.18 seconds, and the render takes 5.5 seconds at 1280 by 720. The render time grows with the triangle count. It changes little with the image size or the four samples a pixel.

## The parts

| Module | Holds |
|---|---|
| `kinds.mojo` | `PlantKind` and `ClusterFate`. |
| `checks.mojo` | The range checks that the parameters share. |
| `noise.mojo` | `hash01`, `value_noise` and `layered_noise`. |
| `wind.mojo` | `Wind`: gusts that travel downwind, and a flutter. |
| `blade.mojo` | `Blade`, and `BladeMesh`, which bakes blades into one geometry. |
| `ground.mojo` | `Ground`: hills, the grass masks, the ground mesh and the mountain ring. |
| `field.mojo` | `GrassField`: clusters, levels of detail and the blade stream. |
| `crown.mojo` | `leafy_tree`: branches from `TreeGenerator`, and a crown of leaf cards. |
| `rock.mojo` | `boulder`: a stone pushed out by noise, with moss on top. |
| `sky.mojo` | `paint_sky`: Preetham's sky with clouds, baked into a cube. |
| `meadow.mojo` | `Meadow`, its parameters, its camera and its renderer. |

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

## Trees

`leafy_tree` grows the branches with `TreeGenerator`. It puts `leaves_per_ring` leaf cards on each ring that is thinner than `twig_radius`. A leaf card is a diamond of two triangles.

Each leaf's normal points mostly out from the crown's center. A leaf deep in the crown, or low in it, is darker. `bush_parameters` returns a bush of three levels with a short trunk.

`default_crown_levels` returns three levels. Every leaf is kept to 28 meters, 30 percent to 60 meters, and 11 percent past that. A kept leaf grows by the inverse square root of the fraction. A far level also has lean wood: one level of branches fewer, and three vertices round each ring.

The treeline is `trees` trees in a band behind the field, and `bushes` bushes along its near edge. `solitary` lists the lone trees in the meadow.

## Ground, sky and light

`Ground` gives the height of rolling hills and four masks: the cover, the dryness, the bloom and the far color. The ground mesh carries the far color. Past the last level of detail, the ground looks like the grass that it stands in for.

`paint_sky` draws Preetham's sky into a small cube and reads it into a large cube. It then paints the clouds. `gain` scales the sky's light, and `saturation` and `tint` deepen its blue. The cube is the scene's background. Its mean color near the horizon is the fog's color.

The sun is a `SunLight` with two cascades that reach 150 meters. The trees and the boulders cast shadows. The grass and the ground receive them. A hemisphere light gives the blue light of the sky and the green light that the grass sends back. The blades and the leaves are lit from both sides: `two_sided_program` turns the normal of a back face to the front.

## Types

| Type | Values |
|---|---|
| `PlantKind` | `GRASS`, `DRY_GRASS`, `POPPY` |
| `ClusterFate` | `DRAWN`, `CULLED`, `BEYOND` |

## Limits

- The CPU culls and grows the clusters, and the CPU rasterizer draws them. There is no GPU path yet.
- Culling tests each cluster's bound against the view only. A cluster behind a hill is still drawn.
- There is no visibility buffer. The rasterizer shades each fragment as it draws it.
- The grass does not cast shadows. The dark roots stand in for its shadow on itself.
- The crowns do not receive shadows. Thin cards shadow each other into a noise.
- The indirect light is a hemisphere light and baked occlusion. The voxel and screen-space passes of the renderer are not used.
