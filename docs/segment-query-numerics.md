# Numerical contract and bounds for issue 589

Inputs covered here are finite IEEE Float32 coordinates. A box may have
infinite outer faces, which are skipped without arithmetic. NaN input is not a
newly supported contract. Distances are Float64 estimates, not exact rational
values or a promise of correctly rounded nearest ordering at every ulp tie.
All calculations below assume ordinary IEEE round-to-nearest arithmetic, not
unsafe reassociation. The production expansion uses the existing FMA/TwoSum
primitive in math.matrix_determinant.

## Dynamic range

An exact nonzero Float32 difference is at least 2^-149 and below 2^129.
Squared differences are therefore in [2^-298, 2^258); a three-term norm is
below 2^260. Raw degree-two products and all endpoint-dot/cross sums remain
normal Float64. Squared cross products extend to 2^-596 and below 2^520.
Their ratio to a length squared remains normal: the most conservative lower
bound is 2^-856. There is no overflow, underflow, or tolerance-based zero
classification in this finite domain. Degenerate identical endpoints are
recognized because their wide squared length is zero.

## Fast endpoint signs

Let u = 2^-53 and gamma_n = nu/(1-nu). A wide difference has relative error at
most u. A product of two rounded differences has error at most gamma_3. The
three-term dot adds at most two nontrivial sum roundings. Its absolute error
is bounded by gamma_5 times the sum of absolute exact products. Converting
that bound to the computed positive-product sum and allowing its two sum
roundings stays below 16u times the computed sum.

The fast path accepts an exterior endpoint only when its dot is farther from
zero than this guard. It computes that endpoint's gap directly from p-a or
p-b. It never reconstructs the endpoint using a rounded projection parameter.
A dot at or near zero goes to an exact-sign original-coordinate polynomial.
Thus an interior foot whose t rounds to 1 cannot be silently snapped to b.

## Fast interior distance

Each component C of (p-a) cross (b-a) has absolute error below 16u times
S = abs(rounded left product) + abs(rounded right product), by the same
rounded-difference/product argument and one final subtraction. The norm of
the cross-vector error is therefore below 16u norm(S).

The acceptance check is fl(norm2(C)) >= 2^-12 fl(norm2(S)). Each positive norm
sum has at most gamma_3 relative error. This implies a cross-vector relative
error below 1025u (the extra u accommodates the norm comparison's rounding).
The relative error after squaring, summing, dividing by the wide length norm,
and accounting for the rounded differences in that norm is below 2^-40.
A zero S is exact and gives an exact zero cross product. Otherwise severe
cancellation fails the check and evaluates original-coordinate expansions.

## Expansion fallback

Endpoint dot products expand into 12 signed products of original widened
Float32 coordinates. Each cross component expands into 8 such products.
Every product is exact in Float64; the shared TwoSum expansion preserves its
sum and its sign before estimating the magnitude. A nonzero expansion has
nonoverlapping components; their absolute sum is below twice its magnitude.
Even the conservative gamma_23 summation bound is far below the fast path's
2^-40 relative distance budget after the positive norm and division.
Endpoint distances use the direct endpoint gap, with at most gamma_5 relative
error. No intermediate rounded t is used on either interior path.

A lexicographic canonical endpoint order ensures exactly the same floating
operations after reversal, including the rounding path and the returned bits.
This is a computed-key invariance statement, not a claim that two unrelated
segments with equal exact rational distances always have identical estimates.

## Node-box floor and nearest ordering

For each axis, a containing node interval contains the segment's endpoint
interval. Its exact distance to p is no greater. The implemented gap is
computed by ordered Float32 comparisons and a monotone Float64 subtraction.
Squaring nonnegative values and summing in the same axis order are monotone
IEEE operations. Therefore the computed node-box key is no greater than the
computed endpoint-box key, not merely within an epsilon.

The final segment key is max(robust_distance, endpoint_box_key). It follows
that every ancestor node key is <= that segment key. The heap's existing
node-before-entry tie rule can then expose all possible equal-key entries
before returning an entry. This restores the needed pruning invariant.

The floor is not a substitute for the robust distance: the scalar oracle
checks its geometric result independently. The computed box key is at most
(1+gamma_5) times the true box distance squared, which itself is <= the true
segment distance squared. Thus taking the maximum cannot enlarge the stated
relative error budget or change the ordering of well-separated distances.
For two positive distances d1 < d2, ordering is guaranteed whenever
(1+2^-40)*d1 < (1-2^-40)*d2. Distances inside the rounding band can still tie or
exchange their computed order; the patch does not claim universal exact-real
nearest ordering. Equal computed keys keep insertion order.

## Slab classification

Each retained parameter is (face-start)/(end-start) with a positive
denominator. Original coordinates are widened before any subtraction.
The fast comparison cross-multiplies the two ratios. Its absolute error is
below 16u times the sum of absolute computed products. Outside that guard its
sign is resolved. Inside it, the 8-term polynomial expands original inputs
and yields the exact sign. Division never collapses distinct near-0.5 slabs.
The active near/far parameters start at exact 0 and 1. This gives exact
closed-interval classification for the stated finite-coordinate domain.

## Validation boundaries

`tools/reference_segment_geometry.py` uses stdlib Fraction. It computes exact
clamped projection and exact slab intervals. It does not use the production
cross-product formula. The native fixtures retain the Float32 input words.
They cover finite limits, subnormals, endpoint interiors, exact boundaries,
mixed exponents, and cancellation. Each case also checks endpoint reversal.

`tests/test_carla_rtree_numerics.mojo` checks the public nearest and intersection
APIs. It checks prefixes, filters, insertion ties, and node bounds.
`bench/carla_segment_numerics_bench.mojo` measures ordinary queries separately
from difficult arithmetic. Run the same benchmark against both revisions.
The original CPU test limit remains five seconds per suite.

A finite corpus does not prove compiler floating-point semantics for all
inputs. The error bounds above require ordinary IEEE rounding. Neither the
benchmark nor the oracle replaces native tests and changed-module coverage.
