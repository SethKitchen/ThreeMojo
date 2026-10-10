# Water

`render_water` draws one Clearwater still of shallow water.

![Shallow water shows a sun glint over a pebbled bed](out/water.png)

The modules live in `extensions/water/`. This is a port of Clearwater by Aurélien Gimazane (Lumaris, 2026, MIT). See [Extensions](Extensions).

`bed_color` repeats `assets/pebbles.jpg`. It then mixes sand, coarse cobble and weed.

## Call it

```mojo
from extensions.water.frame import render_water
from extensions.water.pebbles import pebble_bed
from extensions.water.resolution import SpectrumResolution
from extensions.water.view import FRAME
from render.jpeg import decode
from std.pathlib import Path
from units.si import RADIAN, SECOND, Angle, Duration

var bed = pebble_bed(decode(Path("assets/pebbles.jpg").read_bytes()))
var image = render_water(
    1280,
    720,
    Duration(5.0, SECOND),
    FRAME,
    False,
    SpectrumResolution(256),
    64,
    256,
    SpectrumResolution(128),
    False,
    bed,
    Angle(-0.22, RADIAN),
)
```

`False` holds the camera still. The next `False` leaves the ripple window empty. The pitch is -0.22 radians, so the headland matches the photograph. The page starts at -0.72 radians.

## Animate it

Use a `WaterScene` to draw more than one frame. The scene keeps the resources that do not change with time. It builds the ocean spectrum once. It builds the glare kernels on the first frame that needs them. It owns the ripple window and the clock.

```mojo
from extensions.water.frame import WaterScene

var scene = WaterScene(
    SpectrumResolution(64),
    32,
    128,
    SpectrumResolution(64),
    Duration(0.0, SECOND),
)
for frame in range(60):
    scene.advance(Duration(1.0 / 30.0, SECOND), frame % 10 == 0)
    var image = scene.draw(320, 180, FRAME, True, bed, Angle(-0.72, RADIAN))
```

`advance` steps the ripple equation once, then moves the clock. Its `Bool` taps the middle of the ripple window. The step must be finite and nonnegative. The resulting clock must also be finite. A refused step leaves the ripples, clock and step count unchanged.

`draw` makes a picture at the scene's clock and does not change the simulation. Equal steps give equal pictures.

The start clock must be finite. Finite negative start times are valid. `WaterScene` checks the start before it builds resources. This also makes `render_water` refuse nonfinite time. Earlier versions could propagate a nonfinite time into the picture. Valid finite times keep the same arithmetic and step order.

`reset` returns the ripples and the clock to the start. It keeps the spectrum and the glare kernels. The buffers keep their sizes for the life of the scene.

`render_water` is one scene step and one draw.

## Compose it with a scene

Use `compose` to put the water into a picture that the renderer made. Pass the rendered framebuffer, the updated scene, its camera and the height of the still water. An attached camera uses its node and parent transforms.

```mojo
var image = renderer.render(scene, assets, camera)
var shown = water.compose(image, scene, camera, Length(0.0, METER), bed)
```

The overload without a scene accepts detached cameras. An attached camera with a stale scene or invalid node is refused before any pixels or depths change. Update the scene before rendering and composing.

Each pixel casts the camera's own ray. A ray that reaches the water shades it as the `LINEAR` picture does. Its depth is then tested against the framebuffer.

Geometry nearer than the water keeps its pixel. Water nearer than the geometry replaces the pixel and writes its depth. A ray at or above the horizon leaves the pixel alone. `compose` returns how many pixels show water.

The water is an endless plane at the given height. It repeats the ocean patch. The camera must be a centered perspective camera above the water. Water nearer than the near plane or past the far plane is not drawn. With the page's camera, `compose` gives the `LINEAR` picture below the horizon.

`set_sun` lights the water from a scene's directional light. Pass the light's position minus its target. The direction must be finite and above the horizon. The default is Clearwater's sun. The sun lights the reflections, the bed and the caustics.

The water shades the pebble bed under the surface, not the scene's geometry under the water. It has no GPU path, and it does not establish a frame rate. See [issue 300](https://github.com/SethKitchen/ThreeMojo/issues/300).

## Pictures

`WaterView` names four pictures.

| Name | What it draws |
|---|---|
| `FRAME` | The graded photograph. |
| `CAUSTICS` | The caustic texture, scaled by 0.25. |
| `LINEAR` | The water without glare or bloom. |
| `GLARE` | The diffraction spikes alone. |

## Grid

`SpectrumResolution` is a power of two from 4 through 256. The still uses 256, the same ocean grid as the page. The patch is 4.6 meters. The mean depth is 1.6 meters. The root-mean-square slope is 0.078. Mipmaps and anisotropy filter the ocean, the caustics and the pebbles.

The caustic grid in the still is 64. The page uses 256.

## Frame

`render_water` builds a `WaterScene`, steps the ripple and draws the caustics. It then shades each pixel and grades the color. The shader clock is 0.9 times the frame clock. Dispersion repeats every 60 seconds of shader time.

## Sampling and light transport

Texture coordinates name texel centers at `(i + 0.5) / n`, as in WebGL. Bilinear, cubic and mip samples use the same convention. Caustic triangles use a half-open edge rule, so a shared edge receives light once. A flat surface under a vertical sun has unit caustic intensity.

Underwater absorption and ripple lookup follow the refracted sun direction. The sun is not treated as vertical when it is near the horizon. Invalid spectrum and glare sizes are refused before their grids are allocated.

## Shader storage

`lit_radiance` shades one view ray. It reads every texture through four traits: `SurfaceTexels`, `RippleTexels`, `CausticTexels` and `PebbleTexels`. The water fields implement them, so `draw` and `compose` call it directly.

A `WaterPack` copies one frame's textures into flat float arrays, with a table of mip levels for each. Its views implement the same traits, and their address space is a parameter. A GPU kernel can read the same arrays in device memory and call `lit_radiance`. A view does not keep its pack alive. Use the pack after the last read through a view.

The CPU and a device shade with the same arithmetic. The sky azimuth uses `atan2_float32` from `math/arc_tangent.mojo`, because a GPU has no libm. The field of view uses the stored bits of the host's `tan(32°)`.

`hash12` rounds each step to Float32 once, so a fused multiply-add cannot change the hash. The CPU hash is unchanged. The sine of a large angle removes whole turns in Float64 first, because a GPU sine is accurate near zero only. A compiler can fuse a multiply and an add differently for each storage type, so the last bits of a pixel can differ.

This extension draws a CPU still. It is not a shared scene-water object or a validated fluid solver. The picture does not establish a real-time frame rate, buoyancy, or engineering fluid accuracy.

## Cost

`draw` shades and grades disjoint runs of rows on every logical core. Each pixel keeps the serial arithmetic, so the picture does not change. `compose` runs its depth test in pixel order first. It then shades only the pixels that pass, in parallel.

On an AMD Ryzen 9 5900X, a 1920 x 1080 `draw` takes about 1.7 seconds. On one thread it took about 18 seconds. One `advance` takes about 12 milliseconds. The CPU path therefore cannot reach 60 frames per second at that size. See [the water cost report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/water-cost-300.md) and `bench/water_bench.mojo`.
