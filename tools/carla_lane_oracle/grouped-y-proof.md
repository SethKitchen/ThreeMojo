# Candidate theorem: grouped Y term cannot refuse after X succeeds

Status: review candidate only. No runtime guard or coverage mask is changed.
The source graph is bound in PROOF-SOURCE-MANIFEST.json. This theorem concerns
this private helper after its actual admission and phase/selection gates. It
makes no claim about canonical caller/count reachability.

## Common admission facts

The source requires zero heading and starting curvature; finite ordered raw
distance; finite nonnegative distance error; positive finite rounded distance
strictly inside finite length; stored rate finite; and 1 <= pieces <= 64.
Every nonempty group has 1 <= high-low <= pieces. Its multiplicity is 1 or 2,
so every _grouped_term count is in [1,128], hence inside [1,320].

Let D be the raw distance's high endpoint and E its error. Positive rounded low
implies 0 <= E < raw low <= D. All grouped ideal operations are interval
extensions of their stored-constant real expressions. Error propagation is
nonnegative. Existing interval/outward-rounding contracts remain dependencies.

## Case 1: stored rate is nonzero

Its absolute real value is at least 2^-1074. The stored GL node is strictly
between -1 and 1; consequently stored (1+node) is at least 2^-53. For D and any
admitted nonempty group, the interval for t includes a positive real value at
least D/(2*pieces)*2^-53 >= D*2^-60. Start is nonnegative. The ideal theta
interval includes R*t*t/2, regardless of the sign of R. The retained rounded
phase gate bounds its magnitude by 2^20. Thus

    D^2 * 2^-1195 <= 2^20
    D^2 <= 2^1215
    D < 2^608.

This uses the exact real half of the stored rate. Underflow of a scalar half
cannot invalidate it because _stored_half retains the outward ideal interval.
An unknown/nonfinite phase is rejected before this path.

## Selector bound

The actual stored k=_INV_HALF_PI lies strictly between 1/2 and 1. The selector
is the ValueJet expression theta*k+1/2, widened by its propagated error. Its
error is at least k*theta.error: the multiplication's inherited-error interval
contains that product, and addition does not reduce it. Exact-zero shortcuts
preserve the same inequality. The admitted selector endpoints have floor 0,
so its whole interval lies in [0,1). Since its raw interval contains the exact
scaled theta endpoints, this implies

    max(abs(theta.low), abs(theta.high)) + theta.error <= 1/(2*k) < 1.

The weaker bound B(theta)<=2^1 below leaves substantial slack. Both subsequent
_sincos_expression selector evaluations use the same pure graph and take
quadrant zero. The two reduction constants are zero and their subtractions
use the source zero shortcuts.

## Conservative propagation bounds

Define B=max(1, ideal-interval magnitude, nonnegative scalar error). For positive
power-of-two upper bounds and intermediates below overflow, inspection of the
actual interval/ValueJet code yields deliberately loose inequalities:

- Interval add: magnitude <= 4*max(B1,B2).
- Interval multiply: magnitude <= 2*B1*B2.
- ValueJet add: B <= 2^6*max(B1,B2).
- ValueJet multiply: B <= 2^9*B1*B2.
- Division by an exact integer in [1,64]: B <= 2^6*B(input).

For multiplication, three inherited-error products are at most 2*B1*B2 each;
two outward additions bound their sum by 20*B1*B2 < 32*B1*B2. Value magnitude
is at most 2*B1*B2; the next-up sum is below 128*B1*B2. _roundoff is no larger
than that bound (the subnormal allowance is negligible because B>=1). The
final next-up error is below 512*B1*B2. Exact-zero/one and exact-power paths
only improve these bounds. Directed endpoint FMA paths return an endpoint or
its immediate neighbor; their source-bounded exact-range inputs also prevent
an overflowing internal product or quotient.

For division, value is at most 2B; next_down(integer)>=1/2; numerator inherited
error is the original E because denominator error is zero. Inherited error is
at most 4B. Magnitude is at most 12B and final error at most 32B. The ledger
uses the still looser dyadic bounds 16B and 64B. Addition's
value, inherited, magnitude, and final error are bounded by 4B, 4B, 16B, and
40B respectively, where B=max(B1,B2).

The complete 144-row operation replay is in EXPONENT-LEDGER.json, generated
by exponent_ledger.py. Each row records every value, inherited-product/sum,
magnitude, roundoff, and final-error bound within the corresponding ValueJet
operation. It includes every Horner step and all twelve grouped accumulator
updates, not merely the maximum. A compact summary is:

- distance B < 2^608
- step / integer: exponent 614
- half_step: exponent 623; three weight factors: exponent 632
- admitted theta and zero-reduced value: exponent 1
- square: exponent 11
- ten Horner iterations: exponent 260 (each adds 11+9+6)
- sine multiply by reduced: exponent 270
- weighted Y term: exponent 911 (632+270+9)
- rounded Y: exponent 913
- multiplied by a count <=320: exponent 923
- twelve magnitude-accumulator updates: exponents 925, 927, ..., 947
- twelve ideal/inherited updates: exponents 923, 925, ..., 945

The maximum is exactly 947 in this conservative ledger, leaving 77 exponent
bits below the overflow boundary. Each intermediate bound is evaluated before
using the next operation; no bound assumes its own lack of overflow. In
particular _roundoff is invoked only after its bounded finite magnitude has
been established. All intervals stay ordered; ideal/magnitude/inherited
accumulators remain finite; propagated errors stay nonnegative. This satisfies
every Y _grouped_term predicate.

### Directed helper intermediates

The exact-range predicate admits zero or endpoint magnitudes in [2^-400,2^400].
For directed sum, bounding the actual sequence gives exponents 401 for value,
402 for second, 403 for first, 404 for one-first, 403 for two-second, and 405
for the residual sum. The returned bracket is the rounded value or its adjacent
float and satisfies the much tighter ordinary interval-add bound above.

For directed product, the exact product magnitude is <=2^800; its rounded value
is <=2^801. The fused residual is <=2^802 by a triangle bound. FMA computes that
residual without an intermediate rounded product. The returned bracket again
satisfies the ordinary interval-product bound.

For directed quotient with nonzero admitted denominator, the exact quotient
magnitude is in [2^-800,2^800] or zero, so rounded value is <=2^801. Correlation
must be retained here: rounded_quotient*denominator has magnitude <=2*abs(numerator)
<=2^401. One must not independently multiply the quotient's 2^801 bound by the
denominator's 2^400 bound. The fused residual is therefore <=2^402. Zero-denominator
and outside-exact-range cases use the existing interval/power fallbacks, whose
endpoint bounds are included in the ledger. Power scaling and next-up/down
cannot overflow at any ledger exponent.

### Operations before the retained gates

This lemma does not assert that phase-construction operations always stay
finite: those operations deliberately refuse unsupported input through the
retained phase and selector guards. Their ValueJet sequence is distance/pieces,
stored_half(step), stored_half(rate), step*group_bounds, half_step*node_range,
start+that_product, half_rate*t, zero_curvature+that_product, t*that_sum,
zero_heading+that_product, theta*k, and that_product+0.5. There are no hidden
state overwrites. The first two operations receive the distance bounds in the
ledger once the admitted nonzero-rate path is established. The remaining
pre-gate values are used only through the actual finite admitted phase and
selector intervals. No phase/refusal guard is removed by this candidate. Their
interval-enclosure and nonnegative-error contracts are essential antecedents,
not outcomes claimed from the Y finite-growth ledger.

## Case 2: stored rate is zero

The actual rate half, theta, reduced value, and sine are exact zero after the
finite phase admission. Cosine is exact one. If X passed, its term is the same
factor value/error, because multiplication by exact one retains those fields.
Thus the factor has finite ordered value, nonnegative finite error, and finite
rounded value. Multiplication by exact zero sine now takes the finite-operand
zero shortcut: Y is exact zero value/error. Previous Y values and all three
accumulators are also exact zero, so the current admitted count cannot fail.
This case explicitly needs the preceding X success; it does not assume a
bound on arbitrarily large zero-rate distance.

## Review requirements

Before any source removal, independently check the selector-error lower bound,
the interval enclosure dependency, every exponent bound, subnormal half-rate
behavior, zero-rate nonfinite-factor ordering, and finite-range assumptions in
_directed_endpoint_* and _roundoff. Bind the exact full function graph and
constant tables. Add maintained mutation controls for changes in admission,
count range, phase/selector bounds, constants, loop multiplicities, polynomial
length, arithmetic/error routing, zero shortcuts, and preceding X ordering.
A diagnostic search is useful as a counterexample check but cannot prove this
theorem. No original obligation is counted as executed by this candidate.
