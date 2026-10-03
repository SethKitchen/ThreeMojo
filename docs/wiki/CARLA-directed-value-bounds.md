<!-- Copyright (c) 2026 Seth Kitchen, PE -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# CARLA directed value bounds

These helpers tighten ideal-expression bounds without changing the scalar center evaluator.
They do not change lane tolerances, work limits, or general renderer arithmetic.
The global lane query remains under validation in draft #594.

## Bounded arithmetic path

Each nonzero endpoint must have magnitude from 2^-400 through 2^400.
Zero endpoints also qualify.
This is an arithmetic fast-path condition, not a map-coordinate limit.
Other endpoints use the existing outward interval operations.

TwoSum gives the exact residual of addition in this range.
An explicit fused multiply-add gives the exact residual of a rounded product.
The product's exact bit grid is no finer than 2^-904.
The product residual has at most 53 significant bits and is representable.

For division, first form the rounded quotient q = a / b.
The denominator must be nonzero.
The fused residual a - q*b is exact in this range.
The correlated quotient and denominator keep its bit grid no finer than 2^-505.
The sign of that residual, corrected for the denominator sign, gives the rounding direction.

A zero residual proves exactness.
Otherwise the result and its adjacent representable value enclose the exact result.
Corner bounds enclose interval products and quotients.
A denominator interval containing zero remains unknown.

These statements require correctly rounded Float64 operations and true FMA.
They permit ordinary FMA contraction, but not arbitrary fast-math reassociation.
The scalar error graph retains every permitted operation-rounding error.

## Scalar rounding allowance

A caller first bounds the magnitude of an exact pre-round result, including input error.
Half the spacing in that bound's binade encloses nearest rounding error.
An exact binade boundary selects the larger spacing.
The smallest subnormal replaces the unrepresentable half-subnormal allowance.
One outward representable step remains in the returned allowance.
Nonfinite magnitude bounds remain unknown.

## Sampled-center expression

The exact expressions r*a + (1-r)*b and b + r*(a-b) have the same value and derivatives.
Their ideal interval enclosures can be intersected.
The scalar evaluator still uses its original weighted expression.
Its original forward-error bound remains attached to the intersection.
This retains the finite original bound when the rewritten difference overflows.
An invalid intersection becomes unknown.

## Controls and remaining gates

The retained ordinary sampled-curve query exhausted the old interval work limit.
Its exact Float32 query bits are 1105004517, 3268476412, and 1069720068.
It now resolves with the same work and accuracy limits.
Building-lot construction for the ordinary town also completes.

Exact Fraction controls check the directed arithmetic independently.
The unchanged interval, trigonometric, and certificate controls remain required.
Cross-candidate selection, strict classification, index admission, full coverage, and consumer performance are separate gates.
