<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Lane correction controls

These controls explain intentional differences from CARLA 1360bb9.
They keep the original queries, map fixtures and numerical tolerances.
They do not establish that every admitted map is release-qualified.
The lane implementation remains a held draft until all final gates pass.

The reproducible scripts are in `tools/carla_lane_oracle`. The rounding
report is `tools/carla_rounding_bound.mojo`. They bind their
proofs to evaluator and fixture source hashes and preserve the native-exported
constant bits. Their README lists the four commands and report directory.
`tools/carla_distance_gate.mojo` checks the spiral-domain token digest and the interval token digest. `tools/carla_moment_gate.mojo` checks the moment-producer token digests and the stored coefficient bounds.

`tools/carla_selection_gate.mojo` checks the selection-producer token digests and the phase-constant bounds.

`tools/carla_grouped_gate.mojo` checks the grouped-table token digest and the stored node and weight bounds.

`tools/carla_y_gate.mojo` checks the five Y-finiteness token digests, the successor record digests, and the module token identity.

`tools/carla_speed_gate.mojo` checks the speed-parser record, its module token, and its correctness tests.

`tools/carla_raw_cut_gate.mojo` checks the raw-cut inverse record, the fixture token, the successor binding, and the operation graph.

`tools/carla_runtime_view_gate.mojo` checks the runtime-view record and its bound tests.

`tools/carla_followup_gate.mojo` checks the coverage-followup record, the pin digests, the ordered pin pair, and the pin placements.

`tools/carla_singleton_gate.mojo` checks the rounded LINE singleton record, the lane text token, the consumer graphs, and the selector path.

`tools/carla_frozen_arc_gate.mojo` checks the frozen ARC producer record, the producer functions, and the arc layout.

`tools/carla_invariant_gate.mojo` checks the coverage-invariant record, the pin digests, the ordered pin pair, and the pin placements.

`tools/carla_dispatch_gate.mojo` checks the curve support and dispatch record, the predecessor edge, and the operation graphs.

`tools/carla_cleanup_gate.mojo` checks the reviewed cleanup record, the winner-sign digest, the guard pin digest, the trig and geometry stored words, and the successor tokens.

It selects each reviewed declaration and checks that each premise fragment occurs once, in order.

The singleton, frozen ARC, dispatch, raw-cut, and optional-runtime contracts use that declaration text.

It also builds the significant token lists for the singleton, frozen ARC, dispatch, raw-cut, and selection contracts.

It reports the declaration line span used by the selection contract.

`tools/carla_frozen_arc_gate.mojo` builds the declaration routing for the frozen ARC producer.

It lists the executable names checked by the optional-runtime contract.

It removes an argument move sigil before that contract parses a function body.

It returns the top-level statements used by the spiral-moment and selection contracts.

It returns the top-level `def`, `from`, and `@` lines used by the spiral-moment block check.

It masks the stored-word routing used by the spiral-moment check.

It removes `var`, `comptime`, and the `derivatives: Bool` parameter list from one ideal function.

It returns Python source and generic parameters for one sampled declaration.

The Sum2, optional-runtime, and heading checks parse declarations through that syntax.

It slices one top-level function for the heading check.

It replaces one executable token fragment for the cleanup mutation tests.

It reads the decimal literals in one stored array or scalar declaration.

It rounds one stored decimal literal to a binary64 word.

It derives the stored moment rows in exact arithmetic.

It drops comments and blank lines from one source block.

It reads the stored moment words from the generated table.

It writes the canonical stored-moment table source.

It returns one normalized source block between two markers.

It removes the try-only parameter from one routing declaration.

It reads the current pin value at each coverage transition.

It returns the kept-token digest and declaration text for the lane-control and Sum2 checks.

The cleanup, dispatch, selection, grouped-table, and lane-control checks use that digest.

`tools/carla_lane_control_gate.mojo` checks the lane-control migration digest, its source digests, and the declaration tokens.

`tools/carla_render_actor_gate.mojo` checks the render-actor reuse record and its bound tests.

`tools/carla_runtime_boundary_gate.mojo` checks the runtime-boundary record, its bound tests, and the view-step edges.

`tools/carla_envelope_gate.mojo` checks the envelope budget predecessor record and the admission token.

`tools/carla_selection_record_gate.mojo` checks the selection predecessor record and the restored token.

`tools/carla_ideal_gate.mojo` checks the historical ideal source digest and the projected graph digest.

`tools/carla_accepted_gate.mojo` checks the accepted successor record, the pin digests, the ordered pin pair, and the pin placements.

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
