# Retaining walls

`extensions/geotech/` analyzes cantilever retaining walls and the ground around them. It gives earth and water pressures and the loads on a unit length of wall. It checks external stability by AASHTO LRFD and the strength of the concrete strips. It finds circular slip surfaces by Bishop's method. It gives the motions and colors that show how a wall fails. [Engineering views](Engineering-views) covers the meshes and labels that draw the results.

## Modules

| Module | What it gives |
|---|---|
| `quantities` | `UnitWeight64`, `MomentPerLength64`, and the US units `PCF`, `KCF`, `KIP`, `KSF`, `PSF`, `KSI`, `KLF`, `PLF` |
| `kinds` | `LoadKind` (`DC`, `EV`, `EH`, `ES`, `LS`, `LS_V`, `WA`, `PW`, `EQ`), `PipeRun`, `ContactMode` and `FailureMode` |
| `profile` | `GradePoint` and `GradeProfile`, a broken-line ground that ends level |
| `pipes` | `BuriedPipe`, `pipe_weights` and `circle_band_area` |
| `earth_pressure` | `rankine_active`, `rankine_passive`, `at_rest`, `coulomb_active`, `mononobe_okabe_active`, `trial_wedge` and `trial_wedge_resultant` |
| `water` | `net_hydrostatic` and `effective_unit_weight` |
| `surcharge` | `parallel_wall_height` and `abutment_height`, the AASHTO h_eq tables |
| `loads` | `VerticalLoad`, `LateralLoad`, `LoadFactors`, the Strength I, Service I and Extreme Event I presets, `factored` and `Resultant` |
| `wall` | `Soil`, `CantileverWall`, `RetainedSide`, `WallMaterials`, `wall_loads` and `stem_effects` |
| `stability` | `base_pressure`, `bearing_factors`, `StabilitySettings`, `check_stability` and `StabilityResult` |
| `concrete` | `ConcreteStrip`, `flexural_resistance`, `cracking_moment` and `shear_resistance` |
| `slope` | `SlopeSection`, `SlopeRegion`, `Surcharge`, `SlipCircle`, `bishop_factor` and `critical_circle` |
| `failure` | `RigidMotion`, the motions of each failure mode, `failure_motion` and `utilization_color` |

## Units and axes

A wall is analyzed per unit length along it. A force per length is a `LineLoad64`. A moment per length is a `MomentPerLength64`. A unit weight is a `UnitWeight64`.

In a wall section, x runs from the toe edge toward the heel, and y runs up from the bottom of the footing. A lateral load pushes toward the toe. The front of the wall faces -x. In a slope section, the ground fails toward -x.

## Analyze a wall

1. Make a `CantileverWall` with its height, footing, stem, width, toe, key, exposed height and stem openings.
2. Make a `RetainedSide` with the retained `Soil`. Set the grade, the traffic surcharge height, the top load, the water levels and the pipes that apply.
3. Call `wall_loads` with the wall, the side and the `WallMaterials`.
4. Call `check_stability` with the loads, the foundation `Soil` and a `StabilitySettings`.

```mojo
var wall = CantileverWall(
    Length64(4), Length64(0.5), Length64(0.4), Length64(3), Length64(0.6),
    Length64(0), Length64(0.3), Length64(0), Length64(0),
)
var side = RetainedSide(Soil(UnitWeight64(18, KILONEWTON_PER_CUBIC_METER), Angle64(30, DEGREE64), Pressure64(0)))
side.live_height = Length64(0.6)
var loads = wall_loads(wall, side, WallMaterials(UnitWeight64(24000), WATER_SI))
var result = check_stability(wall, side, loads, side.soil, WATER_SI, StabilitySettings(Length64(0.5)))
print(result.ratio(SLIDING), result.ratio(OVERTURNING), result.ratio(BEARING))
```

A ratio above one fails. `ratio(BEARING)` reads the required factored resistance when the settings give one. Otherwise it reads the theoretical resistance. A resultant outside the footing gives infinite bearing ratios.

## The checks

| Check | Load factors | Rule |
|---|---|---|
| Eccentricity | Strength I minimum | The resultant stays within `eccentricity_fraction` B of the center: B / 4 on soil (Art. 11.6.3.3, 2010) |
| Sliding | Strength I minimum | The lateral load is at most phi_tau V tan(phi_f), phi_tau = 0.80. The key's passive resistance counts only if `credit_passive` is True (Art. 10.6.3.4) |
| Bearing | Strength I maximum | The load over B' = B - 2e is at most phi_b q_n, phi_b = 0.45, with depth and inclination factors and Cwq and Cwg (Art. 10.6.3.1.2) |
| Service pressure | Service I | The larger of the effective-width pressure and the peak linear pressure is at most `allowed_service` |

## Earth pressure under a broken grade

`trial_wedge` tries planes from the base of a vertical plane at angles from phi to 89 degrees. It weighs the soil above each plane, with buoyant soil below the water and with the pipes that cross the wall. It returns the plane of largest thrust. A scan of 720 angles finds the peak, and a golden-section search refines it.

`trial_wedge_resultant` also gives the moment and the arm. It cuts the soil at 100 heights and finds the critical thrust above each cut. The integral of these thrusts over the height is the moment. Under level ground the result is Rankine's: P = Ka gamma H^2 / 2 at H / 3.

## Global stability

`bishop_factor` gives the factor of safety of one circle by Bishop's simplified method. `critical_circle` searches a grid of centers and radii. It keeps only the circles whose sliding mass holds every point you give, for example the corners of a footing. Regions of other materials, a water table, ponded water and surcharges are allowed.

## Failure motions

`failure_motion` gives a rigid motion of the section for a mode and a progress from 0 to 1. Sliding moves the wall forward. Overturning turns it about the toe. Bearing turns it about the heel edge and lowers it. A global slip turns it about the circle's center.

The motions show how a wall fails. They do not predict displacements.

`utilization_color` maps a ratio to a color. Green is below 0.7, and yellow to orange is from 0.7 to 1.0. Red is above 1.0, and dark red is 2.0 and above.

## Limits

- The checks are those of AASHTO LRFD 2010 for a cantilever wall on soil. The wall friction on the virtual back is zero.
- The trial wedge is two-dimensional. It does not model corners, returns or three-dimensional pipe effects.
- Settlement and the internal design of keys, steps and openings are not checked.
- A slip circle search covers the grid you give. Use enough centers and radii to find the minimum inside the grid, not on its edge.
