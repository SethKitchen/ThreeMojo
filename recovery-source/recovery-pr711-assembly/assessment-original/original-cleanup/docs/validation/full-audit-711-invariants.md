# Full-audit coverage invariants

These source changes retain the numerical models, work limits, and error
paths. The source successor record binds their exact inputs and outputs.
Native execution and current-source coverage are separate requirements.
This document does not certify a run or waive a reachable coverage outcome.

## Nonnegative stored blend allowance

The two consumers call the concrete `_stored_blend_error` producer with
full or value-only jets. The producer does not read derivative fields.

The producer rejects a nonfinite or reversed ideal interval, a negative or
nonfinite input error, and nonfinite scalar endpoints. Its rejection value
is positive infinity. It then checks each rounded-rate endpoint and scalar
endpoint. Every nonzero checked operand has magnitude from 2^-400 through
2^400. A rounded-rate overflow also takes this rejection path.

Every summand in the final allowance is nonnegative:

- An interval magnitude is the maximum of absolute endpoint values.
- The inherited error has passed the nonnegative input check.
- The complement allowance is zero or the output of `_roundoff`.
- Product and final allowances come from `_roundoff`.
- `_roundoff` returns a positive outward allowance or positive infinity.

The final expression adds products of these quantities. Zero identities
retain an upper endpoint of positive zero. Ordinary outward addition and
multiplication retain a nonnegative upper endpoint. Overflow retains a
positive infinite upper endpoint. An indeterminate interval operation
returns the whole interval, whose upper endpoint is positive infinity.
No path returns a finite negative upper endpoint. Negative zero also
satisfies the removed nonnegative comparison.

The consumers retain the finite check and the unchanged `min` assignment.
They retain the original weighted scalar graph and both ideal enclosure
intersections. The full/value source correspondence remains checked on the
actual source. Tests use the concrete producer, including invalid error
states and exceptional scalar values. They do not inject a negative
producer result.

## Rounded-axis inverse stays finite

Only the optional rounded-axis path loses its finite-seed guard. The
unrestricted axis path retains its overflow fallback.

A successful `_rounded_line_axis_context` establishes the following facts
through `_RoundedBox`, `_rounded_operand`, the checked rounded multiply-add
operations, and the concrete axis selector:

- The station endpoints are finite and their magnitudes are at most 2^400.
- The accepted stored coordinate boxes have magnitudes at most 2^400.
- The selected stored sine or cosine is nonzero. Its magnitude is at least
  2^-400 and at most 2^400.
- The query comes from finite Float32 coordinates. Its magnitude is less
  than 2^128.

The canonical LINE scalar evaluator uses the same no-inline trigonometric
producer. The rounded boxes cover its separate and permitted fused
multiply-add graphs. These premises apply to the actual checked endpoints,
not only to ideal trigonometric values.

Allowing conservative binary64 rounding, the inverse numerator has
magnitude less than 2^402. Division has magnitude less than 2^802. Adding
the low station stays below 2^803. These bounds are well below the binary64
overflow boundary. The retained clamp and exact stored-coordinate test are
unchanged. The renamed `seed_point` temporary avoids a new outer declaration
colliding with the later loop-local `point`; it retains the same value,
Float64 values and moves.

## Strict junction cuts before canonical certification

The section boundary check establishes finite 0 <= a < b on this path.
The equal-endpoint case returns earlier. The list starts with a and b.
For finite insertions, `_insert_break` rejects endpoint and exterior values,
uses an ordered insertion position, and rejects duplicates. This includes
both zero signs. Positive or negative infinity is rejected at the exterior
comparison while the list is ordered. A finite addition that overflows to
infinity cannot become an interior cut.

Public mutable profile records can contain NaN. Such a value is not a
sorted-list premise. Insertion places a NaN before the final finite b and
never removes it. The earlier proposal loop visits every retained start.
At a NaN start, every geometry lookup comparison with that station is
false, so `info_index` returns -1. `_span_box` raises before the canonical
certification loop. Later insertions cannot remove that failure. The first
loop and its existing guard are unchanged.

Reaching the second loop therefore establishes distinct sorted finite cuts
with the retained final endpoint b. Each `end` is strictly greater than
`start`. Removing that outer comparison leaves both endpoint adjustments
unchanged. The inner `start <= end` check remains necessary for adjacent
representable stations, including the smallest positive subnormal.

## Finite-width admission before local seed evaluation

The local-seed admission retains all three predicates. It checks finite
`hi - lo` before positive second derivative and stationary-point inclusion.
This is an explicit interpolation-domain admission check. It does not make
the old trailing condition's missing False observation reachable.

All three expressions are pure and do not change work counters. Their
conjunction selects the same local-seed branch in either order. Every path
that reaches this admission already called `_midpoint(lo, hi)`, which
computed the same `hi - lo`. The new order therefore introduces no first
overflow operation on this path. The subtraction result is used only as a
finite-domain admission predicate in this change.

Fresh and resumed helpers accept finite negative lower stations. Finite
opposite-sign endpoints can have an infinite difference. Regression
controls construct preflight-admitted direct `Road` records and an authentic
seed-only certificate. Both `RoadInfoGeometry.s` and its contained
`RoadGeometry.s` denote the geometry start station. Public construction
stores the fields separately, and preflight does not enforce their equality;
`MapBuilder` maintains equality. This fallback input is not claimed to be
a builder-generated road. Existing public-record controls already exercise
this distinction. No derivative model or certificate is fabricated to
force an admission vector.

The isolated baseline/order-only diagnostic preserves identical result or
exception, incumbent words, retained cells and work counters. On both the
overflow-width domain and its finite-width neighbor, the exact error is
`Lane refinement exhausted its numerical accuracy limit`, seed work is
1 node/1 term, and resumed work is 3 nodes/6 terms. A normal convex domain
returns the same certificate with 2 fresh nodes or 4 resumed nodes and
48 terms. The maintained domain suite keeps these result and ledger
checks, signed-zero-sensitive failure-state words, and same-build
fresh/resumed certificate equality. It does not pin the normal minimizer's
architecture-sensitive low bits.

## Post-local natural exclusion

The earlier general `natural > best_upper` exclusion remains. After a
local seed attempt, only two cases are possible:

1. The seed did not improve. The stored point, power-of-two scale, and
   deterministic natural-bound expression are unchanged from the admitted
   values. The repeated exclusion is false.
2. The seed improved. `_local_seed` returns one of its actual checked
   in-cell scalar points. Its interpolation was admitted only for finite
   width. Golden-section updates retain stations in the closed cell under
   binary64 rounding, including endpoint collapse. The full point-domain
   enclosure therefore bounds that stored point's exact distance. Its
   natural lower endpoint cannot exceed the retained upward witness bound.

The production witness bound is `_refinement_square`, including its tighter
error-free-residual upper endpoint. The control compares against that
actual bound. It does not substitute the looser original square. The
original work debits, scale refresh, goal checks, and derivative refresh
remain in the same order.

## Endpoint-work refusals remain

The junction endpoint refusal and the lane expansion/chord endpoint
refusals are unchanged in this candidate. An admitted whole-span count
alone does not justify assuming computational enclosure inclusion after
a clamp changes ideal-plus-error representation to an error-zero uncertain
interval. A finite scan without a counterexample is not a proof. These
outcomes require a separate concrete witness or independently reviewed
restricted theorem before any removal.


## Genuine first-endpoint refusal control

The complete-cell count does not universally imply singleton admission.
An exact normal-environment count-only example has whole work 5,000,000,005
and a refused low endpoint. An adjusted-center example also admits the
whole cell, both endpoints and midpoint but refuses the actual interior
neighbor selected by `_expansion_center`. These do not execute enormous
quadrature or justify removing any defensive guard.

The maintained domain suite exercises the junction helper's real first-end
refusal cheaply under the existing test-process-only flush-to-zero mode.
It preflights real public Road records, derives `terms` from `_reference_work`
in that same state, and obtains incoming bounds from `_lane_value_bound`.
The unsupported-state SPIRAL graph returns unknown plan coordinates before
quadrature; an independent finite elevation still needs monotone enclosure.
A finite proposal box is a target, not an injected proof or derivative Jet.

This is a direct-helper negative-station test. The outer junction section
caller has a narrower nonnegative domain and public Map entry points reject
unsupported arithmetic states. The test does not claim that ordinary
public path is reachable. Its explicit checked `MapBuildBudget` reserves
the actual whole work without changing any default. The refusal retains
all incoming bound words, charges exactly five steps and the complete
whole work, and does not charge endpoint traversals. A one-term-short
budget fails before evaluation with its original exhausted ledger. The
existing C fixture restores the saved control state on success or exception.
Only the first OR operand/refusal is exercised; the last-endpoint and
refinement/chord refusal obligations remain separately unresolved.
