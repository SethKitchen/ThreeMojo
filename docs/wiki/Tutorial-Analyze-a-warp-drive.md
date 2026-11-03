# Tutorial: Analyze a warp drive

In this tutorial you build an Alcubierre warp bubble and find the energy it needs. You check one energy condition, add up the energy, and draw a picture. It takes about fifteen minutes.

You need ThreeMojo installed. See [How to install](How-to-install). The [Warp drives](Warp-drives) page describes every function that this tutorial uses.

## 1. Make a program

Make the file `warp_tutorial.mojo` in the repository folder. Put these imports at the top:

```mojo
from extensions.warp.analytic import exact_stress_energy
from extensions.warp.conditions import energy_condition
from extensions.warp.frame import to_eulerian
from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import NULL_ENERGY, T_AXIS, Z_AXIS
from extensions.warp.metrics import AlcubierreMetric, alcubierre_comoving
from extensions.warp.plot import draw_plane, slice_plane
from extensions.warp.quantities import fraction_of_light
from extensions.warp.solver import stress_energy
from extensions.warp.totals import energy_totals
from render.png import encode
from std.pathlib import Path
from units.si import Duration64, InverseLength64, Length64
```

## 2. Make a grid

A grid holds the points where the metric is sampled. Add a `main` function that makes 41 points along x, y and z, 0.2 m apart, in one time slice:

```mojo
def main() raises:
    var grid = SpacetimeGrid.uniform(
        1, 41, 41, 41, Duration64(1.0), Length64(0.2)
    )
    print(grid, grid.points())
```

Run it with `.venv/bin/mojo run -I . warp_tutorial.mojo`. It prints `[1, 41, 41, 41] 68921`.

## 3. Build the bubble

Add an Alcubierre bubble that moves along x at half the speed of light. Its radius is 2 m, and its wall has a steepness of 1.5 per meter. The comoving form keeps the bubble at the origin, so one time slice is enough.

```mojo
    var metric = alcubierre_comoving(
        grid,
        grid.center(),
        fraction_of_light(0.5),
        Length64(2.0),
        InverseLength64(1.5),
    )
```

## 4. Find the energy density

The Einstein equations give the stress-energy tensor that the metric needs. Move it into the frame of the Eulerian observer, who is at rest in each slice of time. Then read the energy density at a point in the bubble wall, 2 m from the center along y:

```mojo
    var energy = stress_energy(metric)
    var eulerian = to_eulerian(energy, metric)
    var wall = grid.index(0, 20, 30, 20)
    print(eulerian.component(0, 0, wall).value, "J/m^3")
```

It prints about `-1.697e+41 J/m^3`. The energy density is negative. No known matter has a negative energy density.

## 5. Check the null energy condition

The null energy condition holds if no ray of light sees a negative energy density. Add these lines:

```mojo
    var null = energy_condition(eulerian, metric, NULL_ENERGY)
    print(null.violations(), "of", grid.points(), "points violate it")
    print(null.at(wall).value)
```

It prints `68737 of 68921 points violate it`, and about `-7.878e+41` for the wall. Far from the wall the values are rounding noise near zero, so the count includes many points where the energy is almost nothing.

## 6. Add up the energy

Add the energy density over the slice, times the volume of each cell. Leave out the two outer layers of points, where the stencils copy the nearest derivative:

```mojo
    var totals = energy_totals(eulerian, metric, margin=2)
    print(totals.total.value, "J")
```

It prints about `-5.271e+42 J`. The sun gives out about 1.2e34 J in a year, so this is the sun's output for some 400 million years, and it is negative.

## 7. Draw the energy density

Cut the plane z = 0 through the bubble and save it as a picture:

```mojo
    var plane = slice_plane(
        eulerian.tensor.component(0, 0), grid, T_AXIS, 0, Z_AXIS, 20
    )
    Path("out/tutorial-warp.png").write_bytes(encode(draw_plane(plane, 4)))
```

Open `out/tutorial-warp.png`. Two red arcs lie above and below the center: the bubble needs negative energy around its sides, and none straight ahead or behind.

## 8. Use exact derivatives

The finite differences have a truncation error. The Alcubierre metric has a closed form, so its derivatives can be exact. Add these lines:

```mojo
    var bubble = AlcubierreMetric(
        fraction_of_light(0.5), Length64(2.0), InverseLength64(1.5), True
    )
    var exact = to_eulerian(
        exact_stress_energy(bubble, grid, grid.center()), metric
    )
    print(exact.component(0, 0, wall).value, "J/m^3")
    print(energy_totals(exact, metric).total.value, "J")
```

It prints about `-1.710e+41 J/m^3` and `-5.275e+42 J`. The exact value at the wall differs from the grid value by less than 1 percent. The exact solver has no edge, so the total uses every point.

## What you did

You built a warp bubble, found the negative energy it needs, checked the null energy condition and added up the energy. To go on:

- Try `natario_comoving` for a drive that does not expand space.
- Try `warp_shell_comoving` for a shell of ordinary matter.
- Run `examples/warp_view.mojo` to see the sky from inside a bubble.
- Read [Why the energy conditions use the Eulerian frame](Why-the-energy-conditions-use-the-Eulerian-frame).
