<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# CARLA point-distance arithmetic

## Scope

This draft compares the stored Float64 lane centers without narrowing them.
It supports finite coordinates and finite widths.
It does not certify the global minimum of a curve.
The global lane work remains held in [#594](https://github.com/SethKitchen/ThreeMojo/pull/594).

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
The general refiner still needs scaled distance bounds and cross-candidate certificates.
The affine projection also needs a complete finite-range analysis.
Candidate admission needs a separate bound for the RTree changes in [#589](https://github.com/SethKitchen/ThreeMojo/issues/589).
Border-only lanes and total work budgets remain separate open issues.

## Controls

The retained regressions cover a wide origin and a false zero-square tie.
Focused controls include strict boundaries, subnormal widths, and finite-limit points.
A deterministic Python Fraction generator supplies 100 exact bit-pattern cases.
The integer fallback and scaled fast path each match those independent signs.
Full consumer coverage and performance remain publication gates.
