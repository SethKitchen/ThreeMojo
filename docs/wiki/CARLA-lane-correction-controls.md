<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Lane correction controls

These controls explain intentional differences from CARLA 1360bb9.
They keep the original queries, map fixtures and numerical tolerances.
They do not establish that every admitted map is release-qualified.
The lane implementation remains a held draft until all final gates pass.

The reproducible scripts are in `tools/carla_lane_oracle`. They bind their
proofs to evaluator and fixture source hashes and preserve the native-exported
constant bits. Their README lists the four commands and report directory.

## Lane poses

The pose follows the derivative of the actual lane-center expression.
The horizontal tangent gives yaw. Elevation change divided by horizontal
lane-center speed gives pitch. The traffic direction keeps CARLA's winding
convention. The stored trigonometric polynomials and sampled-position
interpolation are differentiated as implemented. Exact sine identities are
not substituted for those polynomials.

In the town fixture, road 1, section 1, lane -1 at s=50 has tangent
(1, 0.025, 0) in CARLA coordinates. Its yaw is atan(0.025) in degrees,
or 1.4320961841646465. The old expectation, 1.4323944878270582,
is 0.025 converted directly from radians. It treats a slope as an angle.
The tree-transform expectation uses the same corrected tangent.

Independent differentiation gives these further town poses before public
Float32 narrowing:

- Road 5, lane -1, s=10: yaw -7.1619724391352903 degrees and pitch -1.1110515913233193 degrees
- Road 5, lane +1, s=40: yaw 133.96511248044121 degrees and pitch 361.26665243151570 degrees
- Road 5, lane -2, s=50: yaw -46.95450998676703 degrees and pitch -2.0180642587511068 degrees

The horizontal speeds are 1.03125, 0.9045329833818656 and
1.1351885149427073. Thus elevation grade alone is not the pitch tangent.
The sampled-geometry controls reconstruct the small parabola chord tables
independently. Existing angular tolerances stay at 1e-4 or 1e-3 degrees.
Existing position expectations and tolerances are unchanged.

## Ordinary nearest minima

The ARC query is (70, 10, 0), on road 11, lane -1. Its center circle has
radius 18.25 and center (60, 20) in CARLA coordinates. The independent
circle minimum is s=pi/(4*stored(0.05)). The shipped half-angle polynomial
has a smooth minimum at s=15.7079632679489652900784.
The old s=15.603252062536761 loses more than 0.00707462 in squared distance.

The shoulder query is (10, 105, 0), on road 5, lane -2. Its smooth
stored-expression minimum is s=4.5865313100931020167150.
The old s=6 has a nonzero squared-distance derivative of 11.09057786
and loses more than 7.55224 in squared distance.

These are minima of smooth expressions over stored binary64 constants.
Rounded evaluation is a staircase; it need not have one unique minimizer.
The independent forward-error analysis covers each executed arithmetic
operation, permitted FMA contraction, quadrature count transitions and
ARC quadrant and sinc transitions. Exact rational moment calculations
cover all 23 possible shoulder quadrature counts and 46 endpoint signs.
The shoulder expression has second derivative greater than 1.813299999999992.

Other count boundaries have squared-distance gaps greater than 0.44312915.
Other geometry records have gaps greater than 1991.35.

The rounded-distance error bounds are 5e-11 for the shoulder and 4e-12
for the ARC. The ARC second derivative is greater than 0.912499999999998
on the relevant interior. A strong-convexity bound then encloses every
rounded global minimizer within 1.050220e-5 of the shoulder minimum and
4.187392e-6 of the ARC minimum. Endpoint and competing-lane alternatives
are excluded separately. These enclosures are smaller than the unchanged
1e-4 station tolerance. The expected values come from these bounds, not
from copying the search output.

## Public index partition

`Map.segment_count()` and `Map.segment()` expose the certified nearest-waypoint index.
The default nearest queries use CARLA's own partition, which the map keeps separately.
They do not expose a separate meshing partition. The index uses deterministic
lane order and can add subdivisions for accuracy.

The existing 250-meter gentle ARC has curvature 0.000001 and lane width 3.5.
The heading threshold does not split it. The original distance trigger
produces spans of approximately 101, 101 and 47.999999 meters.
Its lane-center radius is 1000001.75 meters. Independent circle sagitta
bounds give 1.2751272312 millimeters for each long span and
0.3187818079 millimeters for either half. The tail is below
0.2880004920 millimeters. The one-millimeter target therefore gives five
segments. The test checks every station and every exact shared endpoint.
The original final-position tolerance is unchanged.

The town index has 987 segments in the current candidate. This count is a
native regression observation, not an independent proof by itself.
Additional controls check all 26 nonzero lane sections in deterministic
order, directed parameter coverage (including closed point segments),
exact-or-adjacent joins, and required
record splits. They check finite cached full-evaluator boxes and scalar
containment. Scalar samples only check consistency; they do not certify
unsampled extrema. The separate full-curve bounds and narrow unsampled
admission controls remain required.

## Mesh rows

MeshFactory does not consume the nearest-waypoint index. Its row policy
uses the corrected section-wide straightness predicate.

Town road 1, section 1 spans s=30 through s=60. A width record changes
slope at s=40. At the unchanged two-meter mesh resolution, each of its
four nonzero lanes has 16 rows, 32 vertices and 30 triangles.
Section 0 retains 16 vertices. Thus the road has 144 vertices, and
section 1 with both walls has 192 vertices.

Joining the old two-row section-0 lane to the 16-row section-1 lane gives
36 vertices and 34 triangles with the two-triangle stitch. Plain append
and the one-vertex-wide stitch give 32 triangles. Controls independently
check both edges at all 16 rows against the fixture's piecewise width.
The old workloads and position tolerances stay unchanged.

## Remaining scope

The translated-s construction fixture near 1e20 requires an explicit
Float64 road-s resolution error. Its original inputs stay unchanged.
The [road-s proof](CARLA-road-s-resolution) establishes why the current
parameter-matched construction criterion is impossible for that fixture.
The line and its direct-Road stored-point minima remain representable.
Final consumer, coverage, format, generated-code and performance gates
remain required. These corrections do not implement global work budgets
(#580).

The OpenDRIVE reader handles border-only lanes (#577). See
[CARLA lane borders](CARLA-lane-borders).
