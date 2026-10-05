<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# CARLA lane orientation

A known waypoint faces along its evaluated lane centerline. `Road.lane_transform`
and `Map.compute_transform` use its geometric tangent for yaw and pitch.
They keep the existing center-coordinate arithmetic and zero roll.
This is an engineering correction to CARLA 1360bb9, not exact output parity.

## Supported centerlines

The correction covers line, arc, spiral, poly3 and paramPoly3 references.
It includes the lane-offset polynomial, each full inner-lane width, and half
of the selected lane width. Lane 0 uses the lane offset without a width.
Each width and offset contributes both its value and its derivative.
Elevation contributes its derivative to the vertical tangent.

The derivative is taken from the selected position expression before its
Float32 conversions. The returned position still uses the existing two
Float32 lateral offsets, Float32 elevation, and final Float32 coordinates.
A finite difference of rounded positions is meaningful only when its step
resolves that storage precision. For example, rounding can collapse a very
small offset circle to one stored point while its unrounded tangent still
has a direction.

This correction does not evaluate border-only widths or centerlines.
[Issue #577](https://github.com/SethKitchen/ThreeMojo/issues/577) tracks that
separate parser and width contract. Superelevation, crossfall, shape and
lane-height geometry remain outside this centerline model.
[Issue #302](https://github.com/SethKitchen/ThreeMojo/issues/302) tracks the
separate nearest-waypoint and index consistency work.

## Tangent calculation

Let P(s) be the reference position, theta(s) its offset-frame heading,
and t(s) the signed lane-center offset. Positive t points right in the
OpenDRIVE frame. The lane center in that frame is:

```text
C(s) = P(s) + t(s) * (sin(theta), -cos(theta))
C'(s) = P'(s)
      + t'(s) * (sin(theta), -cos(theta))
      + t(s) * theta'(s) * (cos(theta), sin(theta))
```

The returned frame negates the y coordinate and y derivative. Its forward
vector follows `(C'.x, -C'.y, elevation')`. The yaw correction is measured
relative to the reference heading. This retains its existing whole turns.

Pitch is the negative arctangent of vertical speed over horizontal speed.
The norm calculation scales all components first to avoid squared overflow
and underflow. It does not assume that horizontal speed is one.

A lane traveling against increasing s gains 180 degrees of yaw. Its pitch
becomes `360 - pitch`. This retains the established CARLA angle convention.
Right lanes travel with s under RHT. Left lanes travel with s under LHT.
Lane 0 always travels with s.

### Geometry selection

- A line has a constant heading and unit reference speed
- An arc includes its curvature in the offset derivative. A center can
  stop or reverse when an offset reaches or passes the circle center
- A spiral differentiates its existing Gauss-Legendre position expression,
  including the moving quadrature nodes and weights. It uses the selected
  partition, with no change to reference positions
- Poly3 and paramPoly3 differentiate their sampled position chords and
  their interpolated heading separately. The chord direction can differ
  from that heading. Both normalized and arc-length parameter ranges keep
  the existing sample tables and extrapolated final interval

At a geometry, width, offset or elevation record start, the new record
applies. A supplied lane section keeps its own lane records. At an internal
sample knot, the interval ending at that knot applies, as in `pos_at`.
A spiral partition switch uses the partition selected at the exact s.

These are one-sided derivative conventions. A discontinuous position has
no two-sided tangent. The method does not smooth or join such positions.
A clamped reference outside its geometry record has zero reference speed
and heading derivative; any active lateral or elevation derivative remains.

## Degenerate and invalid data

Zero horizontal speed keeps the reference yaw. A stationary center has
zero pitch before traffic reversal. A vertical tangent has a pitch of
minus or plus 90 degrees, according to its vertical direction.
No small-speed tolerance changes a moving center into a stationary one.

The method raises an error for a nonfinite s or missing required records.
An undefined sampled offset frame or nonfinite derivative arithmetic also
raises an error. The center and yaw must fit in their public Float32
representations.
A paramPoly3 whose interpolated `(u', v')` is zero has no offset-frame
heading and raises an error. A selected sample span must be finite and
positive. Required geometry lengths and curvatures must be finite.

This is not a complete OpenDRIVE model validator.

## Correction and compatibility

The pinned [CARLA lane transform](https://github.com/carla-simulator/carla/blob/1360bb9/LibCarla/source/carla/road/Lane.cpp)
subtracts the lateral slope directly from its heading as an angle.
A straight road with lane offset `t = s` has tangent `(1, -1)` in the
returned frame. Its yaw must be -45 degrees. The inherited calculation
returned about -57.2958 degrees. Curved offsets also change horizontal
speed, so elevation grade alone does not give the lane pitch.

Existing callers keep their waypoint identity and center coordinates.
Orientation changes can affect steering, trigger direction, lane-crossing
classification, crosswalk placement, and scenario replay.
The current Map index subdivides lanes using heading differences. Corrected
headings can therefore change its segmentation and approximate query
results. This does not claim to fix its separate global-search limitations.
[Fixed-s nearest-lane queries](CARLA-fixed-s-nearest) are unchanged.

## Verification

`tests/test_carla_lane_orientation.mojo` combines analytic direction controls
with independent finite differences of public positions. It covers both
lane signs, lane 0, inner widths, positive and negative slopes, RHT and LHT,
and all five geometries. It checks record boundaries, sample knots, partition
switches, stationary and vertical centers, winding, and numerical failures.

`tools/generate_carla_lane_orientation_controls.py` independently reads the
hand-authored town XML. It reconstructs the polynomial samples and analytic
geometry tangents without reading Mojo output. It derives the corrected
map fixture angles and the 230-segment count. Its 292 heading decisions
stay at least 0.000112 radians from the subdivision threshold.
The map tests retain their
original tolerances and workloads.

`bench/carla_lane_orientation_bench.mojo` compares the complete old and new
methods in one build. It alternates timing order for each geometry and
checks that all sampled center positions remain exactly equal. It reports
the measured cost of correcting the orientation. It is not a historical
binary benchmark.
