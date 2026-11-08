# Game renderer

`GameRenderer` draws the [Village walk](Village-walk) at 24 frames a second or more, at 1920 by 1080 pixels, on four CPU cores. It draws less than `Renderer` draws, and it draws it in a different way. `GameQuality` sets how finely each part of a frame is drawn. A slow machine can turn each part down, and a fast machine can turn each part up.

The modules are `renderers/game_renderer.mojo`, `render/game_math.mojo`, `render/game_smooth.mojo`, `render/game_upscale.mojo`, `render/game_sharpen.mojo` and `extensions/village/quality.mojo`. See [Renderer](Renderer) for the general renderer.

## Choose a quality

Give a preset to `game_quality`, and give the quality to `PlayParameters`:

```mojo
from extensions.village.play import PlayParameters
from extensions.village.quality import LOW, game_quality

var parameters = PlayParameters(game_quality(LOW))
```

On the command line, give the preset after the window's size:

```sh
mojo run -I . examples/village_walk.mojo --play 1920 1080 low
```

| Setting | `LOW` | `MEDIUM` | `HIGH` | `ULTRA` |
|---|---|---|---|---|
| `render_scale` | 48 percent | A half | Two thirds | One |
| `plants` | `FEWEST_PLANTS` | `FEWER_PLANTS` | `MANY_PLANTS` | `ALL_PLANTS` |
| `grass_wind_every` | 4 frames | 2 frames | 1 frame | 1 frame |
| `sky_step` | 3 pixels | 2 pixels | 2 pixels | 1 pixel |
| `water_step` | 6 pixels | 4 pixels | 2 pixels | 1 pixel |
| `water_refresh_every` | 4 frames | 2 frames | 1 frame | 1 frame |
| `animal_coarseness` | 3 | 2 | 1.5 | 1 |
| `shadows` | `CACHED_SHADOWS` | `CACHED_SHADOWS` | `CACHED_SHADOWS` | `FULL_SHADOWS` |
| `shadow_size` | 1,024 | 2,048 | 2,048 | 4,096 |
| `smooth_edges` | True | True | True | True |
| `fight_reach` | 12 m | 20 m | 32 m | 10,000 m |
| `sharpness` | 0.8 | 0.6 | 0.4 | 0 |

You can change each setting alone. `GameQuality.check` refuses a value out of range:

```mojo
var quality = game_quality(LOW)
quality.render_scale = 0.5
quality.shadows = FULL_SHADOWS
quality.check()
```

## The settings

- **`render_scale`** is the share of the window's width and height that the frame is drawn at, from a quarter to one. `upscale_into` stretches the frame to the window by the Catmull-Rom cubic. See [Stretch and sharpen](#stretch-and-sharpen).
- **`plants`** sets how many leaves and blades grow near the camera. `planted` also draws the ground, the mountains and the canyon's wall more coarsely. `ALL_PLANTS` keeps the still picture's meadow.
- **`grass_wind_every`** sets how often a cluster of grass grows again for the wind. A cluster grows again when its level changes, too. Zero keeps the grass still.
- **`sky_step`** is the step between two samples of the sky, from 1 to 32 pixels. The samples between are mixed bilinearly. A cloud of the sky cube is smaller than 8 pixels across its edge, so a coarser step draws it as boxes. Each task finds the samples of one band of rows. A sample's direction is mixed from the directions through three corners of the window.
- **`water_step`** is the step between two shaded samples of the pond's water, from 1 to 64 pixels. The pixels between are mixed from the four samples round them.
- **`water_refresh_every`** sets how many frames share one ocean surface and its caustics. From two frames, one frame finds the next surface and the next frame finds its caustics.
- **`animal_coarseness`** multiplies the cell of each animal's mesh, from 1 to 8. It also multiplies the finer cell of the eyes, but the eyes' cell never becomes larger than the body's. A coarser animal has fewer triangles. A game given residents of its own meshes their animals no finer than its preset: `game_residents` keeps the coarser of the two.
- **`shadows`** and **`shadow_size`** set how the sun's shadows are drawn. See [Shadows](#shadows).
- **`smooth_edges`** smooths the stair steps along the frame's edges before the frame is stretched. See [Smooth edges](#smooth-edges).
- **`sharpness`** sets how strongly the stretched frame is sharpened, from 0 to 1. `LOW` uses 0.8, `MEDIUM` 0.6, `HIGH` 0.4 and `ULTRA` 0. A frame drawn at the window's size, as the GPU draws it, is not sharpened. See [Stretch and sharpen](#stretch-and-sharpen).
- **`fight_reach`** sets how far from the player a fighter is posed each frame, from 5 to 10,000 meters. A fighter further away is posed every third frame, for all the time it waited, and leaves no trail. Between, it only stands where its character stands. So a crowded fight costs less on a slow machine.

## Smooth edges

`smooth_edges` in `render/game_smooth.mojo` is the simplest form of FXAA. It runs on the small frame, after the water and before the stretch, so a step is smoothed before the stretch makes it larger.

1. A pixel and its four diagonal neighbors give a range of brightness. Where the range is less than 0.0833, or less than a sixth of the brightest, the pixel keeps its color. These are FXAA's own defaults.
2. The edge runs across the larger change between the neighbors. The step along it is scaled so that its shorter part is one pixel, and each part is held within 8 pixels.
3. The samples at a third and at two thirds of the step are averaged. The samples at its two ends are mixed in too, unless the mix leaves the range of brightness.

Each sample is bilinear between pixel centers. The brightness is the luma of the sRGB bytes. Sixteen pixels are tested and blended at once. The rows are cut into small runs over the cores, and every count of cores gives the same frame. `VillageGame.smooth_ms` holds the time it took. At `LOW` it is about a millisecond.

## Stretch and sharpen

A frame drawn at 48 percent of the window must be stretched more than twice. A bilinear stretch mixes only the two nearest pixels on each axis. It smears each edge over a whole small pixel, so a moving fighter looks soft. Two passes keep the edges hard:

1. `upscale_into` in `render/game_upscale.mojo` mixes the four nearest pixels on each axis by the Catmull-Rom cubic. The two far pixels get a small negative weight, so an edge keeps its contrast. A result is clamped to the bytes' range. The pass stretches the rows across first, then blends four stretched rows for each row of the window.
2. `sharpen` in `render/game_sharpen.mojo` is contrast-adaptive sharpening, as in AMD's CAS and the last pass of FSR. Each channel of a pixel and its four neighbors gives a least and a greatest value. The room to sharpen is the distance from them to black or to white, as a share of the greatest. A pixel takes its neighbors away by a weight from that room and `sharpness`, and the result is divided by the weights' sum. A flat area does not change, and the result stays within the neighbors' range.

The game does both in one pass over the window. `upscale_into(frame, window, workers, sharpness)` gives each task a band of rows. The task stretches its rows, and one more above and below, into a buffer of its own. It then sharpens from that buffer into the window. So the window is written once, and no copy of it is made. The result is the same, to the byte, as the stretch and then `sharpen`.

`VillageGame.upscale_ms` holds the time of the pass. At 1280 by 720 pixels from `MEDIUM` it is about 2.4 milliseconds on four cores.

## Draw more pixels when there is time

A fast machine can draw more of the window's pixels than its quality asks, so a fight in motion is sharper. `VillageGame.set_dynamic(True)` turns this on. The village's window and `examples/village_walk.mojo --play` turn it on.

`adapt_scale` measures each frame. After `DYNAMIC_QUICK`, 30, quick frames in a row, it grows the frame's share of the window by `DYNAMIC_STEP`, 0.04. A frame is quick when it takes less than `DYNAMIC_ROOM`, three quarters, of `DYNAMIC_BUDGET_MS`, 33.3 milliseconds. The share grows to the quality's `render_scale` and `DYNAMIC_REACH`, 0.24, more at the most. A frame over the budget shrinks the share by a step, to the quality's at the least.

`GameRenderer.resize` changes the size that the renderer draws at. It keeps the shapes, the maps and the shadows, so a step costs no more than a frame.

## Measure a frame

```sh
mojo run -I . bench/village_game_bench.mojo low 1920 1080 240
```

The bench walks a scripted player through the village. It prints the median, the 95th percentile and the slowest time of each stage, as JSON. These are the times on the four-core host that the project tests on:

| Preset | Frame size | Median frame | 95th percentile | Median frames a second |
|---|---|---|---|---|
| `LOW` | 922 by 518 | 45.5 ms | 56.8 ms | 22 |
| `MEDIUM` | 960 by 540 | 72.6 ms | 89.7 ms | 14 |

`GameRenderer.timings` holds the time of each stage of the last frame, in milliseconds. The stages are the shadow maps, the gathering, the vertices, the setup, the bins, the raster, the sky and the resolve. The bench prints the median of each of these stages under `draw_stages`. It also prints the triangles, the vertices and the draws of the median frame.

## How a frame is drawn

1. **The geometry is read once.** Each geometry is copied into flat arrays the first time it is drawn. `GeometryStore.replace` gives a geometry a new generation, and the renderer reads it again then. A geometry replaced by one of the same triangles keeps its parts, and only its values are read again.
2. **The light is found at the vertices.** Each vertex keeps its ambient and sky light apart from its sun light. The fog veils both at the vertex.
3. **What the camera cannot see is left out.** A mesh whose bounding sphere lies outside the view is not drawn. A skinned mesh's sphere is its bound at rest, grown 1.5 times (`POSE_REACH`), so any pose of a person stays inside it. So a person behind the camera costs no skinning and no setup. In the village this saves about a fifth of each frame's draw.
4. **The triangles are binned into tiles.** Each triangle is clipped at the near plane and culled by its facing and its bounds. It is listed in each 64-pixel tile it touches.
5. **Each tile is drawn on its own core, sixteen pixels at a time.** The raster writes only the depth and the triangle's number. A pixel that is drawn over ten times costs ten depth tests and one shading.
6. **Each tile is resolved.** A pixel's triangle gives its light, and its shadow is looked up. An empty pixel shows the sky. The light is tone mapped and encoded as sRGB bytes.

The pond's water is composed into the frame before it is stretched, because the water needs the depth.

## Draw on the GPU

`GameRenderer.prepare_gpu` does the first half of a frame and stops. It draws the shadow maps, gathers the meshes, lights the vertices and sets up the triangles. It also fills a grid of sky colors. `gpu_frame` then describes the arrays to a GPU. A host draws the triangles, and `VillageGame.finish_gpu` adds what the GPU did not draw.

The GPU does the work of the bins, the raster, the sky and the resolve. Its raster is the hardware's, with a depth test. Its pixel shader does the arithmetic of the CPU resolve: the shadow lookup, the map at the pixel, the fog, ACES and the sRGB encoding. The vertex layout is the same, and a clip depth from -1 to 1 becomes 0 to 1 for Metal.

The sky is the CPU's grid, mixed between samples. The GPU path draws at the window's size, so the sky and the water steps grow by the render scale. This keeps the sampling density of the CPU path.

A host can also take the passes that follow the triangles. Call `VillageGame.prepare_gpu` with `passes` set. `GpuPost` in `extensions/village/gpu_post.mojo` then holds the numbers of four passes. They are the weather's clouds and fog, the night's darkness and stars, the pond's water, and the smoothing of edges. `finish_gpu` leaves them out, and the host need not return the depths.

The order on the GPU is not the order on the CPU, and the frame is the same. The weather and the night change only the pixels of the sky. The water replaces whole pixels. So the GPU can mix the weather and the night into the sky, compose the water over the triangles, and smooth last.

The water uses the same arithmetic as the CPU. The CPU still finds the surface and the caustics, because they need an FFT. `ComposeUpload` in `extensions/water/upload.mojo` packs them and counts each change. The GPU shades a grid of samples and fills the pixels between them, so the water's step must be from 2 to 64 pixels.

`window/threemojo.h` and `renderers/game_gpu.mojo` give the layout. See [C ABI and hosts](C-ABI-and-hosts#draw-the-village-on-the-gpu) for the host's side. Two stages still run on the CPU, and they cost most of a GPU frame:

- The preparation takes about 8 ms at `MEDIUM`, and the gathering alone takes 14 ms at `HIGH`.
- The readback, the rain and the heads-up display take about 5 ms at `MEDIUM`.

## Maps at each pixel

By default the renderer reads a material's map at each vertex. Set `pixel_maps` to read it at each pixel instead:

```mojo
var fast = GameRenderer(640, 360)
fast.pixel_maps = True
```

The village game sets it, so the houses show their brick, plaster, wood and tiles. See [Village houses](Village-houses#surfaces).

1. **The levels.** The first time a map is drawn, the renderer reads it into linear floats. Each level halves the one before it, by the mean of each 2 by 2 block of texels. The chain stops at one texel or 16 levels.
2. **The level of a triangle.** The setup compares a triangle's area on the screen with its area in texels. A triangle reads the level at which one texel covers about one pixel.
3. **The texel.** The resolve mixes each pixel's texture coordinates from its three corners, with perspective. It mixes the four texels round them, bilinear. Each side wraps by its own mode, as `Texture.sample` wraps it. A repeated side wraps round. A mirrored side folds back on every other tile. A clamped side holds its edge.
4. **The light.** The texel tints the pixel's light, the sun's and the sky's. The fog veils the tinted light after, at the pixel, so a far textured roof keeps its haze.

The texel scales all the light of the vertices. A material that shines or glows, a phong material or one with an emissive color, would have its highlight or its glow tinted too. So such a material reads its map at each vertex, where the map tints only its albedo.

The renderer keeps each map by its texture id. After a texture's texels or wraps change, or before it draws a scene of another `Assets`, call `forget_maps`. Each map is then read again when it is next drawn.

A map read at each pixel ignores the texture's offset, repeat and rotation.

## Depth across a long triangle

The setup keeps each triangle's depth as a plane over the screen. It writes the plane from the first corner's depth and the other two corners' differences from it. A long thin triangle near the horizon has huge edge terms, which cancel. Weighted by the depths themselves, they once left a far triangle of ground nearer than a wall at some pixels. Weighted by the small differences, the far ground stays behind the wall.

## No pinholes between small triangles

The setup measures each triangle's edge planes from the triangle's own corner, the least pixel of its box. The raster and the resolve read them from that corner too. Measured from the frame's corner, a triangle of two square pixels near pixel 1,000 has constant terms of about 500,000, which cancel. The rounding left over was about 3 % of the triangle.

Where two triangles that share an edge both rounded outward, no triangle covered the pixel, and what was behind showed through. On a close face, the back of the head showed as dark specks. A floor of 180,000 small triangles in a 1920 by 1080 frame had 751 such pixels, and now has none.

## Shadows

| Mode | What is drawn |
|---|---|
| `NO_SHADOWS` | No shadow. |
| `STILL_SHADOWS` | One map of the still casters, drawn once. The moving casters cast no shadow. |
| `CACHED_SHADOWS` | The still map, drawn once, and a small map round `focus` of the moving casters, drawn each frame. |
| `FULL_SHADOWS` | Both maps, drawn each frame. The swaying trees' shadows sway too. |

`set_moving` names the moving nodes, such as the people and the animals. `refresh_shadows` draws the still map again at the next frame. A pixel takes the darker of the two maps, with a 2 by 2 filter.

The still map keeps the casters as they were when it was drawn. So in the village game, the grass casts only with `FULL_SHADOWS`: its clusters are shown, hidden and grown again as the player walks. A tree's shadow keeps the crown level that the tree wore in the first frame. Call `refresh_shadows` after the still casters change.

## What it draws

- `scene.meshes` and `scene.skinned_meshes`, opaque, on a layer that the camera sees. A part whose material is not `visible` is not drawn. The sun's maps use the camera's layers too, as three.js's shadow map does, and the still map is drawn again when the camera's layers change.
- `BASIC`, `LAMBERT`, `PHONG`, `STANDARD` and `PHYSICAL` materials. A standard or a physical material is lit as a Lambert one.
- Vertex colors, a color, an emissive color, and a map read at each vertex or at each pixel.
- Morph targets on a mesh, relative or absolute, with or without normals. The renderer reads only the vertices each target moves. It moves the shape again only when the mesh's weights change. A geometry that two meshes wear at once, in different weights, shows the weights of the mesh drawn last. A skinned mesh's morph targets are not drawn.
- A node program, only as a `GameShading` registered for it says. It can light a back face as its front, read a baked sun and sky, and sway in the wind.
- Ambient, hemisphere and directional lights. The cascades of one sun count once.
- At most `GAME_LAMPS`, eight, point lights. A point light falls off as `lights.lighting.falloff` has it, and lights each vertex that faces it. It casts no shadow.
- Exponential squared fog, or no fog.
- A color or a cube background.

The renderer refuses other materials, a second hemisphere light, a second sun, a ninth point light, and spot lights.

## Why it agrees with `Renderer`

The two renderers share the ACES curve, the fog and the sRGB encoding. The ACES curve is `aces_tone` in `render/tonemap.mojo`, and the fog is `exp2_veil` in `core/fog.mojo`. The game renderer calls each of them at sixteen lanes. Both scale each light by three.js's `RECIPROCAL_PI`. A flat floor in the parity tests is within two levels of a byte in each channel.

The two renderers differ in one way. `GameRenderer` lights each vertex and mixes the light across the triangle. `Renderer` lights each pixel. A curved surface and a highlight are therefore less exact in a game frame.

## Limits

- The renderer draws no transparent or alpha-tested surface.
- Without `pixel_maps`, a map is read at the vertices, so a map's detail between the vertices is lost.
- The GPU path runs on Metal only, and in the macOS window only. The CPU still prepares each frame, draws the rain and the heads-up display, and finds the water's surface.
- The water on a GPU needs a shade step of 2 pixels or more.
