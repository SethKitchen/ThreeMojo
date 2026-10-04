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
The shared [point-distance predicate](CARLA-point-distance) compares the stored centers exactly.
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

A nonfinite scaled norm triggers an exact comparison with the largest finite Float64 squared.
If the exact norm is in range, the method returns the largest finite Float64.
This handles a rounded reconstruction that overflows just below the limit.
If the exact norm exceeds the limit, the method raises an error.
Finite approximate outputs retain ordinary Float64 rounding, including rounding to the largest finite value.
The reported norm is not a correctly rounded or interval-certified distance API.

## Controls

Focused controls cover translated origins, lane signs, true ties, filters, and section rules.
They cover tiny widths, optional offsets, wide elevation, finite-limit centers, and checked failures.
Independent Fraction calculations use the exact stored input values.
The shared exact-product kernel has no new arithmetic implementation.
An ordinary fixed-s benchmark compares lane identity, distance changes, and elapsed time.
