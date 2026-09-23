# Water

`render_water` draws one Clearwater still of shallow water.

![Shallow water shows a sun glint, a sandy bed and one ripple](out/water.png)

The modules live in `extensions/water/`. This is a port of Clearwater by Aurélien Gimazane (Lumaris, 2026, MIT). See [Extensions](Extensions).

The pebble photograph is not in this port. `bed_color` keeps the sand, cobble and weed mix. It paints each stone from `hash12`.

## Call it

```mojo
from extensions.water.frame import render_water
from extensions.water.resolution import SpectrumResolution
from extensions.water.view import FRAME
from units.si import SECOND, Duration

var image = render_water(
    320,
    180,
    Duration(5.0, SECOND),
    FRAME,
    False,
    SpectrumResolution(64),
    24,
    96,
    SpectrumResolution(32),
    True,
)
```

`False` holds the camera still. `True` places one tap in the ripple window.

## Pictures

`WaterView` names four pictures.

| Name | What it draws |
|---|---|
| `FRAME` | The graded photograph. |
| `CAUSTICS` | The caustic texture, scaled by 0.25. |
| `LINEAR` | The water without glare or bloom. |
| `GLARE` | The diffraction spikes alone. |

## Grid

`SpectrumResolution` is a power of two from 4 through 256. The page uses 256 for the ocean. This still uses 64 so the software frame stays fast. The patch is 4.6 meters. The mean depth is 1.6 meters. The root-mean-square slope is 0.078.

## Frame

`render_water` builds the spectrum, steps the ripple and draws the caustics. It then shades each pixel and grades the color. The shader clock is 0.9 times the frame clock. Dispersion repeats every 60 seconds of shader time.
