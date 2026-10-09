<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# CARLA point-distance arithmetic

## Scope

The certified lane query compares the stored Float64 lane centers without narrowing them.
It supports finite coordinates and finite widths.
This comparison alone does not certify the global minimum of a curve.
[Stored-point distance ordering](CARLA-point-distance) describes the shared exact arithmetic.

## Point order

A common positive scale prevents overflow and underflow in ordinary comparisons.
Outward intervals enclose each subtraction, division, square, and sum.
The fast path accepts an order only when the intervals separate.
An ambiguous comparison uses bounded exact binary products.

The exact fallback compares the squared distances of the stored coordinates.
It uses 132 base-2^32 digits for each signed sum.
Finite Float64 inputs fit this fixed capacity, including the largest finite values.
Equal distances keep the segment insertion order.
A rounded zero square does not establish equality or coincidence.

## On-road classification

The map retains the selected wide center for the strict plan-width test.
It compares four times the plan distance squared with the width squared.
It does not form a half-width that can underflow.
It does not recompute the center through the public Float32 transform.
A nonpositive width contains no point.

Nonfinite centers or widths raise an error.
Public transform and query storage types do not change.
The correction changes results when narrowing or a rounded square hid a real gap.
It also changes false ties between unequal point distances.

## Remaining limits

Exact sample order does not establish an exact curve minimum.
The integrated general refiner uses [normalized distance bounds](CARLA-normalized-refinement)
and [cross-candidate certificates](CARLA-cross-candidate-certificates).
The exact axis specialization verifies inverse seeds and stored-point brackets.
Other affine projections do not bypass the general proof.
[Candidate admission](CARLA-index-admission) uses the separate corrected R-tree bound
from [#589](https://github.com/SethKitchen/ThreeMojo/issues/589).
[Lane borders](CARLA-lane-borders) and [map budgets](CARLA-map-budgets) cover border-only lanes and work limits.

## Controls

The retained regressions cover a wide origin and a false zero-square tie.
Focused controls include strict boundaries, subnormal widths, and finite-limit points.
A deterministic Python Fraction generator supplies 100 exact bit-pattern cases.
The integer fallback and scaled fast path each match those independent signs.
Full consumer coverage and performance remain publication gates.
