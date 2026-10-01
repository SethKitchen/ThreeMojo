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

`render_water` builds the spectrum, steps the ripple and draws the caustics. It then shades each pixel and grades the color. The shader clock is 0.9 times the frame clock. Dispersion repeats every 60 seconds of shader time.
