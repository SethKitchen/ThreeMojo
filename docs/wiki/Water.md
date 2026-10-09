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

`advance` steps the ripple equation once, then moves the clock. Its `Bool` taps the middle of the ripple window. The step must be finite and nonnegative. `draw` makes a picture at the scene's clock and does not change the simulation. Equal steps give equal pictures.

`reset` returns the ripples and the clock to the start. It keeps the spectrum and the glare kernels. The buffers keep their sizes for the life of the scene.

`render_water` is one scene step and one draw. A scene is the start of persistent scene water, [issue 300](https://github.com/SethKitchen/ThreeMojo/issues/300). It does not compose with a three.js scene yet. It has no GPU path. It does not establish a frame rate.

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

This extension draws a CPU still. It is not a shared scene-water object or a validated fluid solver. The picture does not establish a real-time frame rate, buoyancy, or engineering fluid accuracy.

## Cost

A 1920 x 1080 frame takes about 18 seconds on one thread of an AMD Ryzen 9 5900X. The draw costs about 77 milliseconds a frame plus 8.6 microseconds a pixel. Per-pixel shading is almost all of it. One `advance` takes about 13 milliseconds. The CPU path therefore cannot reach 60 frames per second at that size. See [the water cost report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/water-cost-300.md) and `bench/water_bench.mojo`.
