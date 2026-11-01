# Warp drives

`extensions/warp/` ports [WarpFactory](https://github.com/NerdsWithAttitudes/WarpFactory), a toolkit that analyzes warp drive spacetimes in general relativity. It samples a metric on a grid and finds the stress-energy tensor by the Einstein equations. It then checks the energy conditions and finds the expansion, shear and vorticity. The port runs on the CPU in `Float64`.

![An Alcubierre bubble: its energy density, its null energy condition and its expansion](out/warp-drive.png)

Rendered by `examples/warp_drive.mojo`. The bubble moves along x at half the speed of light. The panels cut the plane z = 0. From the left, they show the energy density, the null energy condition and the expansion. Red is negative, blue is positive and white is zero.

The port follows WarpFactory at commit `03b10cb`, dated 2024-05-23. Its method is in [Helmerich et al. (2024)](https://arxiv.org/abs/2404.03095).

## Modules

| Module | What it gives | WarpFactory |
|---|---|---|
| `kinds` | `Axis`, `TensorIndex`, `EnergyCondition`, `DifferenceOrder` and `Frame` | The strings "covariant", "Null", "fourth" and others |
| `quantities` | `EnergyDensity64`, `SPEED_OF_LIGHT`, `GRAVITATIONAL_CONSTANT` and `fraction_of_light` | `Units/` |
| `grid` | `SpacetimeGrid` and `SpacetimeCenter` | `gridSize`, `gridScaling` and `worldCenter` |
| `tensor` | `TensorField`, `Metric`, `change_index` and `trace` | The tensor struct, `changeTensorIndex`, `getTrace`, `c4Inv` |
| `three_plus_one` | `ThreePlusOne` and `decompose` | `threePlusOneBuilder` and `threePlusOneDecomposer` |
| `metrics` | Minkowski, Alcubierre, Lentz, Van Den Broeck, modified time and Schwarzschild | `Metrics/` |
| `warp_shell` | `warp_shell_comoving` and its radial profiles | `metricGet_WarpShellComoving` |
| `derivatives` | `derivative`, `second_derivative` and `Stencil` | `takeFiniteDifference1` and `2` |
| `solver` | `stress_energy` and `curvature` | `getEnergyTensor`, `ricciT`, `ricciS`, `einT`, `einE` |
| `frame` | `to_eulerian` and `eulerian_transform` | `doFrameTransfer` and `getEulerianTransformationMatrix` |
| `conditions` | `energy_condition`, `energy_condition_samples` and the sampled directions | `getEnergyConditions` and `generateUniformField` |
| `scalars` | `metric_scalars` | `getScalars` |
| `flow` | `momentum_flow_lines` | `getMomentumFlowLines` |
| `evaluation` | `evaluate_metric` | `evalMetric` |
| `plot` | `slice_plane`, `red_blue` and `draw_plane` | `getSliceData` and `redblue` |

## Analyze a metric

Make a grid, build a metric on it, and call `evaluate_metric`. The result holds the stress-energy tensor, the four energy conditions and the three scalars.

```mojo
from extensions.warp.evaluation import evaluate_metric
from extensions.warp.grid import SpacetimeGrid
from extensions.warp.metrics import alcubierre_comoving
from extensions.warp.quantities import fraction_of_light
from units.si import Duration64, InverseLength64, Length64

var grid = SpacetimeGrid.uniform(
    1, 20, 20, 20, Duration64(1.0), Length64(1.0)
)
var metric = alcubierre_comoving(
    grid,
    grid.center(),
    fraction_of_light(0.5),
    Length64(5.0),
    InverseLength64(0.5),
)
var result = evaluate_metric(metric)
print(result.null.worst().value)         # the most negative value, J/m^3
print(result.null.violations())          # points that violate it
print(result.eulerian.tensor.get(0, 0, grid.index(0, 10, 13, 10)))
```

Each step is also a function of its own. Call `stress_energy` for the tensor and `to_eulerian` to move it into the Eulerian frame. Call `energy_condition` for one condition and `metric_scalars` for the scalars.

## The grid

A `SpacetimeGrid` has a count of points and a step along t, x, y and z. The time step is a `Duration64`, and the space steps are `Length64` values. The grid holds at most 1048576 points. A tensor of that size takes 128 MiB.

The time coordinate is x⁰ = c t. So every coordinate is a length, the metric is dimensionless, and every stress-energy component is in J/m³. WarpFactory gets the same result when it divides each time derivative by c.

A `SpacetimeCenter` is the place of the origin. Point i along an axis sits at (i + 1) times the step, minus the center. Indexes count from 0, but this keeps the places of WarpFactory, which counts from 1. `grid.center()` puts the origin in the middle of the grid, as the WarpFactory examples do.

The derivatives need points on both sides. The fourth-order stencils need 5 points along an axis, and the second-order stencils need 3. An axis with fewer points has no derivative. So a grid with one time slice is static.

## Build a metric

Each metric function takes the grid and the center. Then it takes the metric's own parameters, each with its unit.

| Function | Parameters | Time slices |
|---|---|---|
| `minkowski` | None | Any |
| `alcubierre`, `alcubierre_comoving` | Speed, radius R, steepness σ | 5 or more, or 1 |
| `lentz`, `lentz_comoving` | Speed, size of one region | 5 or more, or 1 |
| `van_den_broeck`, `van_den_broeck_comoving` | Speed, R₁, σ₁, R₂, σ₂, expansion A | 5 or more, or 1 |
| `modified_time`, `modified_time_comoving` | Speed, R, σ, lapse factor A | 5 or more, or 1 |
| `schwarzschild` | Schwarzschild radius | 1 |
| `warp_shell_comoving` | Mass, R₁, R₂, buffer, σ, smoothing, speed, warp | 1 |

A `_comoving` function gives the metric in the frame that moves with the drive. It needs one time slice. The other functions move the drive across the time slices.

To build a metric of your own, start from `ThreePlusOne(grid)`. Set the lapse, the shift β_i and the spatial metric γ_ij at each point. Then call `metric(name)`.

## The warp shell

`warp_shell_comoving` builds the shell of [Fuchs et al. (2024)](https://arxiv.org/abs/2405.02709). A shell of ordinary matter holds a static spacetime, and a shift inside it moves the inside along x. The function first builds radial profiles of the density, the pressure and the metric. The pressure comes from the Tolman-Oppenheimer-Volkoff equation for a constant density.

The profiles use WarpFactory's 100000 radial samples. `samples` changes that count. The shell's Schwarzschild radius must be less than 8/9 of the outer radius. A heavier shell has an infinite pressure at its center.

The grid must reach past the outer radius. The samples reach to 1.2 times the distance of the last grid point, and every grid point must be inside that radius.

## The energy conditions

`energy_condition` moves the tensor into the Eulerian frame. Then it samples a set of directions at each point, and keeps the most violating value. A negative value violates the condition.

| Condition | Directions | Value at a point |
|---|---|---|
| Null | `count` null directions | min T_ab k^a k^b |
| Weak | `count` times `shells` timelike directions | min T_ab V^a V^b |
| Strong | `count` times `shells` timelike directions | min (T_ab - T η_ab / 2) V^a V^b |
| Dominant | `count` null directions | -max s(F) √abs(F·F), with F^a = -T^a_b k^b |

The defaults are 100 directions and 10 shells, as in WarpFactory. `energy_condition_samples` also keeps the value of every direction at every point. `ConditionMap.violations_only` keeps only the negative values, as `evaluate_metric` does with `keep_positive` set to False.

## Units

| Quantity | Type | Unit |
|---|---|---|
| A stress-energy component, an energy condition | `EnergyDensity64` | J/m³ |
| The expansion θ | `InverseLength64` | 1/m |
| The shear σ² and the vorticity ω² | `InverseArea64` | 1/m² |
| The Ricci scalar | `InverseArea64` | 1/m² |
| A warp speed | `Velocity64` | m/s |
| The flow line step | `Compliance64` | m³/J |

The fields store plain `Float64` values in these units. The accessors, such as `StressEnergy.component` and `ConditionMap.at`, return the typed quantity.

## Differences from WarpFactory

Each difference corrects a WarpFactory result or makes a refusal explicit.

- The null and weak conditions lower the Eulerian tensor with the Minkowski metric. WarpFactory uses the metric of the coordinate frame for these two, and the Minkowski metric for the other two. The Eulerian frame is orthonormal, so its metric is the Minkowski metric. Where g is not η, the null and weak values differ from WarpFactory's.
- `change_index` moves a tensor between the two mixed index positions. WarpFactory changes only the label.
- `metric_scalars` uses the grid's steps, with x⁰ = c t. WarpFactory uses a step of 1 on every axis. The two agree on a grid with 1 m space steps and a time step of 1/c.
- `modified_time` reads the x, y and z steps and centers. WarpFactory reads them one axis too early, and copies g_01 to g_10 from the wrong point. Its time-dependent version stops on an undefined variable.
- The second-order solver uses the same G and c as the fourth-order solver. WarpFactory's `einE2` uses rounded values.
- The warp shell's cubic interpolation returns the sample itself at a whole index. WarpFactory divides zero by zero there, so a grid point at the center is NaN.
- The moving average keeps its window sums in two floats. A window of zeros sums to exactly zero, as in MATLAB.
- A metric with no Eulerian frame, no real lapse or a singular point raises an error. WarpFactory warns and goes on with complex or infinite values.
- Flow line places count from 0. A line keeps every place it reaches, up to `max_steps`.

## Verification

The tests compare the port with independent results, not with WarpFactory's output.

| Test | Reference |
|---|---|
| The Alcubierre energy density | Alcubierre (1994), equation 19. The error falls by 16 when the step halves. |
| The Alcubierre expansion and shear | The derivatives of the shift, worked out in the test |
| Schwarzschild is a vacuum | The Ricci tensor falls to zero at the fourth order |
| A moving bubble | The same energy density as the comoving bubble |
| The warp shell | The energy density inside the shell is ρ c² |
| The energy conditions | Closed forms for a perfect fluid |
| The Lentz regions | WarpFactory's own region tests, on 6954 points |
| The finite differences | Exact results for polynomials |

## Limits

- The port has no GPU path. WarpFactory can use a GPU through MATLAB's Parallel Computing Toolbox.
- Coordinates are Cartesian. WarpFactory also refuses other coordinates.
- The plot draws one plane on the red-blue map. It has no titles, axes or 3D views.
- The derivatives at the edge of the grid copy the nearest derivative, as in WarpFactory. Values in the two outer layers of points are not reliable.

## References

- Helmerich, Fuchs, Bobrick, Sellers, Melcher and Martire, "Analyzing warp drive spacetimes with Warp Factory", Classical and Quantum Gravity 41 (2024) 095009.
- Fuchs, Helmerich, Bobrick, Sellers, Melcher and Martire, "Constant velocity physical warp drive solution", Classical and Quantum Gravity 41 (2024) 095013.
- Alcubierre, "The warp drive: hyper-fast travel within general relativity", Classical and Quantum Gravity 11 (1994) L73.
- Van Den Broeck, "A 'warp drive' with more reasonable total energy requirements", Classical and Quantum Gravity 16 (1999) 3973.
- Lentz, "Breaking the warp barrier: hyper-fast solitons in Einstein-Maxwell-plasma theory", Classical and Quantum Gravity 38 (2021) 075015.
- Hawking and Ellis, "The Large Scale Structure of Space-Time", 1973, section 4.3.
