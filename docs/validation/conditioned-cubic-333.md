<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Conditioned CARLA cubic successor (#333)

The new scalar and all its bounds use the record's local coefficients.
This is a numerical correction to CARLA `1360bb9`. It changes computed
values. It is not a claim of bit equality with the old evaluator.

## Counterexample and scope

Use the local coefficients `(3.5, 0, 0, 1)` and record start `1e6`.
At road station `1e6`, the correct local coordinate is zero and the value
is `3.5`. The old constructor stored expanded coefficients. The rounded
expanded evaluator returns zero for this case.

The successor stores each input coefficient and the record start unchanged.
It first computes `local = x - s`. It then computes
`a + local * (b + local * (c + local * d))`.
The tangent is `b + local * (2*c + local*3*d)`.
The public coefficient fields now mean local coefficients. Code that read
expanded coefficients must change. They were never a serialized byte format.
OpenDRIVE input still supplies the same local coefficients and record start.
Typed adapters are a separate source edge. They must keep the Float64 input
bits and check the documented finite-value conditions.

The theorem below assumes finite stored coefficients, a finite record start,
and an ordered finite station interval. A finite input can still overflow
an intermediate. Such a result must not become a finite certificate.
Existing whole-interval, absent-proof, and error paths remain in force.
Native execution also needs the repository's supported floating-point mode.

## New enclosure theorem

Let `u = x - s` in exact real arithmetic. Define
`P(u) = a + u*(b + u*(c + u*d))` from the stored binary64 coefficients.
The smooth reference for the new scalar is this local polynomial. It is
not the polynomial formed from the old rounded expanded coefficients.

The full Jet starts with station interval `[low, high]`, first derivative
one, second derivative zero, and scalar error zero. The constant record
start has zero derivatives and zero error. Jet subtraction encloses exact
`x - s` and carries the error of its rounded scalar subtraction. The local
Horner graph then uses the same additions and multiplications as the scalar.

The unchanged `curve_interval.mojo` provider supplies these induction steps:

1. Each value interval contains the exact real expression.
2. An addition inherits the sum of the two operand errors.
3. A product inherits `|A|*eB + |B|*eA + eA*eB`.
4. Each step adds an outward bound on rounding at the full pre-round
   magnitude, including inherited error. The bound includes gradual
   underflow. It does not assume that relative error alone covers zero.
5. Product and sum derivative rules enclose the exact first and second
   derivatives. They do not differentiate the rounded scalar staircase.

Each permitted fused multiply-add removes a product rounding. Keeping its
nonnegative error allowance remains conservative for the following sum.
This argument permits contraction inside the local Horner expression. It
does not permit reassociation or contraction across an unrelated stored
operation. Forming `x - s` has no multiplication to contract.

Thus the Jet's rounded value contains the new scalar. Its first and second
fields contain `b + 2*c*u + 3*d*u*u` and `2*c + 6*d*u` for every exact station
in the interval. The derivative-elided ValueJet executes the same value
and error graph. It must not consume its unused derivative fields.

This scalar claim uses a zero shift. A nonzero translation in a local
expansion changes the association of arithmetic. The existing translated
callers use its ideal value and derivatives and set scalar error to
infinity. They retain the original full-domain scalar error separately.
This successor does not turn that expansion into a standalone scalar bound.

## Certificate consumers

The following consumers must change with the scalar:

- `curve_bounds._polynomial_jet` subtracts the stored polynomial origin.
- `lane_value_bounds._polynomial_value` makes the same subtraction.
- `junction_bounds._polynomial_bounds` uses the full Jet. It returns the
  rounded value magnitude, the two ideal derivative magnitudes, and scalar
  error. It no longer applies endpoint Bernstein arithmetic to expanded
  stored coefficients.
- `Road._lane_distance_derivative` uses `c + 3*d*(low - s)` for each active
  width, offset, and elevation record. These are local quadratic Taylor
  coefficients. The method's floating-point coefficients remain a search
  proposal. They are not an exact polynomial for the rounded staircase.

The constant rounded-box shortcut has a new premise. Its ARC and LINE
callers admit stations only in `[-2^400, 2^400]`. `_rounded_constant` now
requires its polynomial origin to meet the same supported-operand check.
Their difference has magnitude at most `2^401`, so it is finite. Every
variable product in a constant local polynomial is then exact zero.
NaN, infinity, and an origin outside the supported range return an unknown
box. The old check of zero `b`, `c`, and `d` alone was no longer sufficient.

Two other direct coefficient readers need no numerical edit:

- `_constant_axis_polynomial` supplies only an eligibility predicate.
  `_axis_lane_minimum` evaluates both ordered endpoints through
  `_checked_center` before any return or search step. Finite endpoint
  values of a constant profile establish a finite local subtraction over
  that interval. A nonfinite origin or endpoint evaluation raises first.
- `Map._use_projected_spiral_seed` uses a constant width only to choose
  heuristic initialization. It does not create or waive a certificate.
  All admitted candidates retain the ordinary bound and witness checks.

The Road straight-lane classifier reads only `c` and `d`. Zero values still
mean an affine local polynomial. Public scalar evaluation and the map's
full bounds retain their finite-result checks. No polynomial byte writer
or expanded-coefficient serializer exists in this source closure.

The centered elevation enclosure has a separate identity. Let `center` be
the stored midpoint, `m = center - s`, and `delta = x - center`. Then

`P(x-s) = P(m) + delta*(P'(m) + delta*(c + 3*d*m + delta*d))`.

Every operation in this reconstruction uses an outward interval. The
identity holds for any stored midpoint. It does not require the midpoint
to equal the exact average. Each interval may lose correlation and widen;
it cannot exclude the exact expression. Adding the original scalar error
then encloses the same new scalar. Intersecting this enclosure with the
original enclosure is safe because both enclose that scalar. Subtracting
`m` from world station `x` instead of subtracting `center` is incorrect.

A constant local polynomial keeps exact zero ideal derivatives. The Jet's
zero shortcuts retain this case when the local range is finite. A
zero-width station interval still includes local subtraction error. A
record start and station near the largest binary64 value can overflow
`x - s`; even a constant polynomial can then evaluate `infinity * 0`.
The bound must remain uncertain and the checked boundary must refuse it.

## Source admission and historical records

`conditioned-cubic-successor.json` records six complete numerical
intermediate modules. `conditioned_cubic_contracts.py` checks exact source
and token endpoints, the fixed inverse spans, and the explicit local
evaluation and enclosure operations. It refuses a mixture of old scalar
and new bounds, or new scalar and old bounds.

The inverse reconstructs historical bytes for provenance. It does not
transfer a theorem about old computed values to new computed values.
Thirteen historical lane-oracle records and the coverage loop source
record remain unchanged. A consumer must admit the current numerical
edge and the typed API edge before consulting a historical view. Its
current operation owns all physical source, proof, test, and helper reads.
It must bind the unchanged primitive provider, preserve resolver checks,
and reread the consumed inputs before it issues a receipt.

The three historical claims that the cubic constructor, evaluator, and
tangent are byte-identical apply only to their historical source. The
new claims are the local-polynomial and enclosure theorems above.
Independent finite-town and translated-station controls keep their stated
fixture scope. They cannot establish arbitrary-map equivalence by reading
an inverse source. A fixture that uses a changed nonzero-origin polynomial
needs its own current local-coefficient analysis and native controls.

## Retained fixture and loop obligations

The ordinary shoulder oracle uses road 5's first elevation and offset
records and the two right-lane widths. Their polynomial origins are zero.
Their coefficients are small, finite values. Subtracting zero is exact, and
the local Horner graph has the same arithmetic on that smooth piece.
The constant-offset ARC controls keep the same property. Their retained
native outputs remain labeled historical observations.

The pose controls at road 5 stations 40 and 50 already use the original
local offset `.5 + .01*(s-20)` and elevation derivative `.002*(s-30)`.
Those formulas match the new exact local model. They do not assert equality
to the old rounded expanded coefficients. Native pose checks remain needed.
The shoulder oracle's other-record lower bound also survives the changed
nonzero-origin offset. On road 5's later pieces, the new local offset is
`.5 + .01*(s-20)` for `20 <= s <= 57`, hence it stays between `.5` and `.88` (the upper endpoint is
loose enough for the stored binary64 `.01` coefficient).
The selected shoulder's total half-width is `4.25`, so its lateral distance
from the reference curve is at most `3.75`. The later plan pieces have
nonnegative local x and y, headings in the first quadrant, and reference
origins with y at least `105`. Their smooth center y is therefore at least
`101.25`. Against query y `-105`, its squared y residual alone is at least
`206.25^2 = 42539.0625`; the changed elevation cannot lower that bound.
This is a fixture-specific geometric inequality, not old scalar parity.
The rounding allowance and native-execution requirements remain separate.

The translated-station fixture changes the geometry and section stations
to `1e20` but keeps its polynomial origin zero. Its constant width and its
separate quadratic-width mutation therefore retain the same polynomial
graph. The parameter-grid and nonprogress proofs do not change.

The coverage loop masks have narrower premises than polynomial equality:

- The rounded ARC, rounded LINE, and axis-search lane loops remain nonempty
  because `Road._check_lane` succeeds before each loop. A selected valid
  lane index proves that its lane list is not empty. A new origin refusal
  can leave before a loop, but it cannot create a zero-iteration entry.
- The construction boundary loop remains nonempty. Every `_add_segment`
  call is dominated by a successful same-owner `_build_transform` call.
  Its current Road implementation still rejects a missing geometry.
  `_lane_record_boundaries` appends each geometry to a fresh owned list.
  The consumer does not remove its entries. No numeric ordering premise
  occurs in this proof.
- The junction break loop retains its two explicit endpoints. The changed
  polynomial enclosure does not change its list construction or lifetime.
- The seed count, local support, midpoint, and budget guard theorems concern
  geometry-relative distance and the unchanged primitive error graph.
  Their finite-range, positive-band, finite-score, and debit checks remain.
  Local polynomial values can change candidate proposals. They cannot
  bypass those checks or enlarge the scope of a removed guard.

Each transported loop must be found at its exact new lexical owner and
location. Complete current source admission must precede transport. A
historical byte match alone cannot justify a current coverage mask.

## Controls and qualification

The Python test suite checks complete old and new source graphs, each
changed expression, missing and mixed endpoints, same-token byte drift,
mutated inverse data, a hash-only repin, and optimized-Python refusal.

Its mathematical controls use exact fractions and a separate forward-error
model. They check the original cancellation defect, all eight Horner FMA
choices, adjacent stations on both sides of a large origin, negative
origins, constants, zero-width intervals, subnormal coefficients, extreme
finite scales, and local-subtraction overflow. Sparse symbolic algebra
proves the derivative and centered identities for arbitrary coefficients
and origins. It also rejects the incorrect world/local delta identity.

The standalone `oracle.py` and `translated_parameter_resolution.py`
runners admit the complete physical current graph before reconstructing
historical pin views. They check their actual fixture profiles, record
current graph hashes in their reports, and reread and reverify the graph
before writing results. Their retained native numbers remain explicitly
historical observations. A source-only report is not new native evidence.

The native suite `test_carla_conditioned_polynomial.mojo` exercises the
actual evaluator and certificate consumers, including the new constant
origin guard at its supported boundary and one ULP outside it. The Python suite does not
execute Mojo or establish native compilation, contraction choices,
coverage, search cost, or whole-map acceptance. Those remain separate
qualification gates. No budget, tolerance, or coverage requirement is
relaxed by this successor.
