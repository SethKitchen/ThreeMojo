# Open channels

`extensions/hydraulics/channel.mojo` solves steady flow with a free surface in a prismatic channel. It gives the normal depth, the critical depth, the depth after a hydraulic jump and a gradually varied profile. The profile uses the standard step method, which HEC-RAS uses for steady flow. A checked result is a numerical result. It does not establish engineering validity.

## The channel

A `Channel` is a trapezoid with a bed slope and a Manning coefficient. A side slope of zero gives a rectangle. A bottom width of zero gives a triangle.

```mojo
var channel = Channel(Length64(6, METER), 2, 0.001, 0.025)
var flow = VolumeFlowRate64(12, CUBIC_METER_PER_SECOND)
var normal = normal_depth(channel, flow)
var critical = critical_depth(channel, flow)
```

| Argument | Meaning |
|---|---|
| `bottom_width` | The width b of the bed |
| `side_slope` | The horizontal run z of each side for a rise of one |
| `bed_slope` | The fall S₀ of the bed per length. Zero is a horizontal bed. A negative value is an adverse bed. |
| `manning_n` | The Manning coefficient n, in s / m^(1/3) |

For a depth y, the area is (b + z y) y. The wetted perimeter is b + 2 y sqrt(1 + z²). The top width is b + 2 z y. The methods `area`, `wetted_perimeter`, `top_width` and `hydraulic_radius` give them.

## Depths and numbers

| Function | Gives |
|---|---|
| `manning_flow(channel, depth)` | The uniform flow at a depth: A R^(2/3) sqrt(S₀) / n |
| `normal_depth(channel, flow)` | The depth of uniform flow. The bed slope must be positive. |
| `critical_depth(channel, flow)` | The depth with a Froude number of one: Q² T = g A³ |
| `froude_number(channel, flow, depth)` | The velocity over sqrt(g A / T) |
| `specific_energy(channel, flow, depth)` | The depth plus the velocity head |
| `friction_slope(channel, flow, depth)` | The slope of the energy line: n² Q² / (A² R^(4/3)) |
| `sequent_depth(channel, flow, depth)` | The depth on the other side of a hydraulic jump |

A flow deeper than the critical depth is subcritical. A shallower flow is supercritical. A channel is mild when its normal depth is above its critical depth, and steep when it is below.

A hydraulic jump takes a supercritical flow to a subcritical one. The two depths have the same momentum function Q² / (g A) + A ȳ. Here A ȳ is the first moment of the area about the surface. `sequent_depth` takes either depth and gives the other.

Each depth comes from a bisection of a function that rises or falls with the depth. So each call finds its depth to the last bit, and it cannot fail to converge.

## Water surface profiles

`water_surface_profile(channel, flow, start_depth, reach, steps)` gives a gradually varied profile from a control section at station zero.

```mojo
var profile = water_surface_profile(channel, flow, Length64(2, METER), Length64(1500, METER), 50)
var far = profile[50].depth
```

A start depth above the critical depth gives a subcritical profile. A control downstream fixes it, so the function computes it upstream and its stations are negative. A start depth below the critical depth gives a supercritical profile, which runs downstream.

The standard step method keeps the energy between two sections. The specific energy changes by (S₀ - S_f) Δx along the flow, with S_f the mean of the friction slopes of the two sections. Each step solves this equation for the unknown depth by bisection on the same side of the critical depth.

The error falls with the square of the step. Use more steps for a profile near the critical depth, where the depth changes fast.

A gradually varied profile cannot pass through the critical depth. If a step reaches it, the function raises an error. A supercritical flow on a mild slope ends in a hydraulic jump before that point. Use `sequent_depth` to place the jump.

## Differences from HEC-RAS

- HEC-RAS takes natural cross-sections with overbanks, bridges and culverts. This port takes one prismatic trapezoid.
- HEC-RAS has four formulas for the mean friction slope, and its default is the mean conveyance. This port uses the mean of the two friction slopes.
- HEC-RAS adds contraction and expansion losses. A prismatic channel has none.

HEC-RAS is in the public domain. The code follows the published method and is original.

## Validation

Each row is a test in `tests/test_hydraulics_channel.mojo`.

| Case | Reference | Error |
|---|---|---|
| Rectangle, critical depth | (q² / g)^(1/3), and a specific energy of 1.5 times it | Below 1e-12 m |
| Rectangle, hydraulic jump | y (sqrt(1 + 8 Fr²) - 1) / 2, from both sides | Below 1e-11 m |
| Rectangle, uniform flow | Manning's formula, and its normal depth | Below 1e-12 |
| Triangle, critical depth | (2 Q² / (g z²))^(1/5) | Below 1e-12 m |
| Trapezoid of Chow: 20 ft wide, sides 2 to 1, 400 ft³/s | Normal depth 3.36 ft and critical depth 2.15 ft | Below 0.006 ft, the digits of the book |
| M1 backwater profile, 1500 m, 25 steps | The profile equation, by Runge-Kutta in 4000 steps | Below 0.2 mm |
| The same profile, 25 and 50 steps | Second order | The error falls by 3.5 to 4.5 |
| Profile from the normal depth | The normal depth at every station | Below 1e-9 m |
| S3 profile in a steep chute, 60 m, 40 steps | The profile equation, by Runge-Kutta | Below 0.5 mm |

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| A width or a side slope is negative, or both are zero | `Channel` |
| A bed slope is not finite, or a Manning coefficient is not positive | `Channel` |
| A flow or a depth is not positive and finite | All functions that take one |
| The bed slope is not positive | `normal_depth` |
| The bed slope is negative | `manning_flow` |
| A reach is not positive, or a step count is out of range | `water_surface_profile` |
| A profile starts at the critical depth or reaches it | `water_surface_profile` |

## Limits

- The channel is prismatic and trapezoidal. It has no natural section and no structures.
- The flow is steady and one-dimensional.
- A profile is on one side of the critical depth. The function does not place a hydraulic jump.
- The Manning coefficient is one value for the whole section.

## References

- Chow, "Open-Channel Hydraulics", McGraw-Hill, 1959: examples 4-2 and 6-2, and chapter 10.
- Henderson, "Open Channel Flow", Macmillan, 1966: chapters 3 to 5.
- Brunner, "HEC-RAS River Analysis System Hydraulic Reference Manual", US Army Corps of Engineers, 2016: chapter 2.
