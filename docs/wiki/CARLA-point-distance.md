<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Stored-point distance ordering

## Scope

`extensions.carla.curve_distance` compares finite stored Float64 points.
The [fixed-s lane query](CARLA-fixed-s-nearest) uses this private arithmetic.
It does not change Map queries, geometry evaluation, or trigonometry.
It does not certify the minimum of a continuous curve.

## Comparison

The first path bounds both squared distances after a common positive scale.
Adjacent Float64 values bound each potentially inexact elementary operation.
Zero and subnormal values receive adjacent representable bounds too.
Disjoint bounds decide the order.
Overlapping bounds use exact binary products.
No epsilon or rounded squared norm converts a positive gap to a tie.

The exact path cancels the common query-square terms.
For each coordinate, it sums a*a - b*b - 2*a*q + 2*b*q.
It separates the positive and negative products into fixed-size integer accumulators.
The sign of their exact difference decides the order.

Each finite Float64 has at most 53 significand bits.
Products use four 32-bit limbs, with UInt64 intermediates and explicit carries.
The smallest binary product has unit 2^-2148.
Each accumulator has 132 limbs, or 4,224 bits.
This includes the finite product exponent range, the factor of two, and the sum carry.
No floating-point product decides an ambiguous comparison.

## Reported distance

The output norm divides component gaps by their largest magnitude before squaring.
It multiplies the square root by that scale at the end.
A distinct stored point therefore cannot acquire a false zero from a squared-distance underflow.
Only the chosen lane's output norm is required.

Near the finite limit, an exact squared-norm comparison checks representability.
A true norm above the largest finite Float64 raises an error.
This includes a calculation that rounds down to the largest finite value.
An in-range norm whose reconstruction overflows returns the largest finite value.
The output is an approximation, not a correctly rounded or interval-valued norm API.

## Controls

Integer geometry and a reproducible Fraction corpus check the comparison.
The corpus includes 100 finite binary input triples across the Float64 exponent range.
It includes true ties, subnormal perturbations, sign changes, and finite-limit carries.
Exact bisection gives a norm bracket independent of the native implementation.
The output controls permit four additional ULPs around that bracket.
Nonfinite inputs and out-of-range norms must raise.

Run `python3 tools/generate_carla_distance_controls.py` to regenerate the point corpus.
Run `tools/capture_carla_fixed_s_controls.mojo` to capture geometry seeds with the pinned toolchain.
Pass the capture file to `tools/generate_carla_fixed_s_controls.py` to regenerate the road corpus.
Run `mojo format` on each generated Mojo file.
