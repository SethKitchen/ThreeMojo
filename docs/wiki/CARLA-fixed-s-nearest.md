<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Fixed-s nearest lane queries

## Scope

`Road.nearest_lane(s, location, lane_type)` measures in the OpenDRIVE frame.
It selects a lane at the supplied road s, rather than minimizing along a lane.
The query remains a `Vector3`, with Float32 coordinates.
Map nearest-waypoint queries use a separate search in the CARLA frame.
The two APIs do not call each other.

## Center precision

The fixed-s walk keeps width values, lane offsets, elevation, and centers in Float64.
It does not pass an internal center through `Vector3` or an offset through `Length`.
The [point-distance predicate](CARLA-point-distance) compares the stored centers exactly.
A rounded square or returned distance does not decide the selected lane.
The guarantee concerns the computed Float64 centers, not an unrounded ideal road model.
Center evaluation still uses Float64 arithmetic and its representable spacing.

This corrects [issue #604](https://github.com/SethKitchen/ThreeMojo/issues/604).
For a line at y=1000000001 and width-2 lanes, the centers are y=1000000000 and y=1000000002.
A query at y=1000000000 selects lane -1 at zero distance.
The old Float32 conversion made both centers coincide and selected lane +1.
The pinned upstream reference is CARLA 1360bb9, `road/Road.cpp`.

## Existing walk and record rules

The walk visits right lanes from inner to outer, then left lanes from inner to outer.
It compares every eligible center, including outer centers after a farther one.
The later eligible lane replaces an earlier lane on an exact stored-point tie.
The lane-type mask and lane-0 exclusion do not change.
`lanes_at` still merges sections that start together and retains the later duplicate lane id.

Plan geometry and lane-offset lookup use s clamped to the road.
Width and elevation records use the original s.
A missing lane-offset record means zero offset.
Missing geometry, elevation, or a nonzero lane's width record raises an error.
The Map center evaluator has different record and section rules, so it is not a replacement for this walk.

This deliberately removes CARLA's early-distance stop.
Signed negative widths can reverse direction and make an outer lane closer.
Even with nonnegative widths, rounding at extreme origins can make consecutive centers farther and then closer.
The query therefore compares all computed finite eligible centers.
Finite signed widths remain admitted; no new nonnegative-width restriction is imposed.
A malformed outer record that the old early stop skipped can now raise an error.

## Distance and checked failures

The reported distance is a scale-safe Float64 approximation of the selected center's norm.
Its precision is no longer reduced to Float32.
For example, a distance of sqrt(2) is approximately 1.4142135623730951.
The previous Float32 calculation returned approximately 1.4142135381698608.
Exact ordinary distances such as the 3-4-12 norm of 13 remain unchanged.

A distinct stored center cannot return a false zero from squared-distance underflow.
A representable subnormal distance remains positive.

A nonfinite s, query coordinate, visited width, reference point, or visited center raises an error.
Every nonzero lane's width and center is visited, even when its type does not match the mask.
Only the final selected lane needs a representable reported distance.
A losing candidate with a huge norm does not fail the query solely because of that norm.
No eligible lane returns `None` and the largest finite Float64, as before.

The largest component gap above half the finite Float64 limit triggers an exact range check.
A nonfinite reconstruction also triggers this check.
The check compares the exact squared norm with the largest finite Float64 squared.
If a nonfinite reconstruction has an exact norm in range, the method returns the largest finite Float64.
A finite reconstruction keeps its approximate value when the exact norm is in range.
This handles rounding on both sides of the finite limit.

If the exact norm exceeds the limit, the method raises an error.
For example, a center at (DOUBLE_MAX, 1, 0) has an out-of-range exact norm.
The method raises even when the scaled calculation rounds to DOUBLE_MAX.
The reported norm is not a correctly rounded or interval-certified distance API.

## Controls

Focused controls cover translated origins, lane signs, true ties, filters, and section rules.
They cover tiny widths, optional offsets, wide elevation, finite-limit centers, and checked failures.
Independent Fraction calculations use the exact stored input values.

The controls include 100 Fraction point cases and 135 fixed-s cases across all five geometry kinds.
The geometry cases use three non-axis headings and translated origins of both signs.
A seed capture records only unchanged geometry points and ordinary sine and cosine values.
Python computes the lane centers and exact distance order independently of `nearest_lane`.
The existing Map and OpenDRIVE controls remain unchanged.

## Benchmark

`bench/carla_road_fixed_s_bench.mojo` compares two methods in one build.
The baseline method comes from commit e53600eb4b0551bbe9900ea0e8b7151e49553a2d.
Both methods call the same unchanged geometry helpers and ordinary trigonometry.
This is a same-build method comparison, not a historical binary comparison.
The benchmark warms both paths and alternates their order across eight samples.

It checks 101 ordinary query identities for each lane count and heading.
It times 1,000 queries per sample, with 1, 2, 4, 16, and 64 lanes per side.
The headings are 0 and 0.37 radians.
The output includes distance changes, timing, and a consumed checksum.

The exact ordering and complete lane scan have a cost.
A larger lane count must not restore the incorrect early-distance stop.
The benchmark does not establish Map-query performance or global lane-search accuracy.

### Measured result

A Linux x86-64 run used Mojo 1.1.0 (8189361e) with `--Werror`.
All 1,010 ordinary lane identities matched the baseline method.
Returned distances can change because the old method rounded to Float32.
The largest observed change was about 0.00000112 meter.

| Lanes per side | Heading (radians) | Baseline microseconds/query | Corrected microseconds/query | Ratio |
|---|---|---|---|---|
| 1 | 0.0 | 0.300 | 0.659 | 2.20x |
| 2 | 0.0 | 0.549 | 1.422 | 2.59x |
| 4 | 0.0 | 0.786 | 2.869 | 3.65x |
| 16 | 0.0 | 2.919 | 12.688 | 4.35x |
| 64 | 0.0 | 28.898 | 69.713 | 2.41x |
| 1 | 0.37 | 0.319 | 0.626 | 1.96x |
| 2 | 0.37 | 0.491 | 1.411 | 2.87x |
| 4 | 0.37 | 0.834 | 2.883 | 3.46x |
| 16 | 0.37 | 2.835 | 13.084 | 4.61x |
| 64 | 0.37 | 28.337 | 70.346 | 2.48x |

Each time is the median 1,000-query batch time divided by 1,000.
The road has twice the listed lane count, split equally between its two sides.
Each ratio divides the corrected median time by the baseline median time.
A ratio above 1 means that the corrected method is slower.
These measurements are local observations, not a cross-machine speed guarantee.
