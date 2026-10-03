<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# CARLA normalized lane refinement

## Draft scope

This draft removes raw squared-distance overflow and underflow from local search decisions.
It retains finite Float64 center coordinates and the existing parameter domain.
It remains part of the held global lane work in [#594](https://github.com/SethKitchen/ThreeMojo/pull/594).
It does not complete cross-candidate minimum certification or RTree admission.

## Distance units

The search uses a power-of-two scale from the current center-to-query gap.
It divides component intervals before it squares them.
Each scale change recomputes the normalized distance bounds.
A rounded zero square cannot establish coincidence.
Only equal stored coordinates establish an exact zero distance.

The local seed and sample order use exact point-distance predicates.
The returned legacy square can still be zero or infinite.
The search does not use that legacy value for order or pruning.
Nonfinite centers and invalid parameter intervals raise errors.

## Accuracy and bounds

The spatial target remains the smaller of the interval length and positive lane width, times 2^-20.
The rounding term uses 64 ULPs at a lower enclosure of the normalized score.
Power-of-two scaling preserves normal squared-distance ULP units.
It gives a tighter unit when the original square underflows.
The search consumes a downward enclosure of the complete allowance.
Outward normalization does not enlarge the permitted gap.

Derivative bounds describe the stored polynomial expression.
The separate scalar-rounding enclosure remains in each lower-bound argument.
Direct center-value boxes also work when derivative arithmetic is unbounded.
The 40-step local search supplies a seed, not a global proof of unimodality.

An endpoint winner uses an interior expansion center with the same evaluator branch.
The search retains each tolerance-pruned interval and its lower certificate.
It rechecks those certificates when the final winner changes the allowed gap.
An unresolved certificate reopens its interval within the same work limits.

## Work and unresolved intervals

The local limits remain 16,384 intervals, 2,000,000 quadrature terms, and depth 96.
An unresolved interval raises a numerical or work-limit error.
It does not become an off-road answer.
Certificate rechecks also count against the interval limit.
The ordinary town fixture remains a required consumer gate.
Total map-wide budgets remain a separate issue.

## Evaluator precision

The distance predicate compares exact real distances between stored center points.
Its bound carries the center evaluator's rounding errors.
It does not add fictitious scalar rounding for mathematical distance arithmetic.
Normal power-of-two scalings keep exact interval endpoints when this is proved.
The smallest normal result can be rounded up from an inexact subnormal.
That boundary, subnormal results, and unproved operations retain the outward fallback.

Expansion values translate constant origins before ideal interval evaluation.
This reduces cancellation without changing the underlying polynomial or derivatives.
The full unshifted domain still supplies the actual evaluator's rounding-error bound.
An expansion alone has no finite standalone rounded-value guarantee.

Spiral quadrature sums displacement before it adds the world origin once.
It retains the nodes, weights, piece-count rule, and local work limits.
This avoids losing sub-ULP terms at a large origin.
Final rounding and signed-zero results can differ from the former accumulation order.
Frozen sources and independent controls retain those differences for review.

## Candidate enclosures

Segment construction caches a box for the full rounded center evaluator.
Unresolved sample or quadrature branches are subdivided with finite local limits.
This adds 48 bytes of internal bounds per segment.
A box rejects a candidate only when its lower distance exceeds the known point's upper distance.
The quarter-point chord target is not used as a certified deviation.

An unresolved enclosure becomes the whole coordinate space.
It disables this rejection and does not become an empty candidate.
The cache has the same geometry snapshot as the segment index.
A separate RTree key-error bound remains required for index-level admission.

## Controls

The retained sampled-center controls use scales 1e-200 and 1e200.
Their stored reference samples have an independently known central minimum.
Near the middle, complementary interpolation products share one binary spacing.
They sum exactly to twice the scale, including ordinary FMA contraction.
Farther away, the x contribution exceeds any y reduction from rounding.

The prior refiner retains the wrong underflowed seed or rejects the overflowed square.
Both controls pass with normalized bounds.
Full module coverage, consumer validation, and ordinary-query cost remain gates.
