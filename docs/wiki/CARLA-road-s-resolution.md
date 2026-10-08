<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# CARLA road-s subdivision resolution

Map construction raises a resolution error when Float64 road s cannot represent a required subdivision or sampling step.
The line and its stored-point nearest minima can still be representable.
This page explains the construction criterion and its exact counterexample.

## The construction criterion

Each index segment compares three lane-center samples with its chord.
The samples use fractions one quarter, one half, and three quarters.
The sample parameter rounds to Float64 before the center evaluation.
The chord keeps the requested fraction.
The squared coordinate residual must be at most `0.000001`.
This is the existing one-millimeter sampled target.

The turn limit remains `0.5` radians. The subdivision depth limit remains `24`.
A failed target requires an interior midpoint.
If its rounded midpoint equals either endpoint, construction raises a Float64 road-s resolution error.
This error replaces repeated subdivision of the same failed interval.
The depth error still applies when midpoint subdivision advances but reaches the cap.

## The exact retained input

The original translated Map fixture starts at `B = Float64(1e20)`.
Its zero-heading line has zero origin and local length `81920`.
Its width is constant `0.0002`; its elevation and lane offset are zero.
The lane section and geometry record both start at B.

| Value | Exact stored decimal | Binary64 bits |
|---|---:|---|
| B | 100000000000000000000 | `0x4415af1d78b58c40` |
| Length | 81920 | `0x40f4000000000000` |
| End | 100000000000000081920 | `0x4415af1d78b58c45` |

B lies between `2^66` and `2^67`.
Binary64 has 53 significant bits, so its spacing here is `U = 2^(66-52) = 16384`.
The interval contains exactly six stored parameters, `B + kU`, for integer k from zero through five.
Their x coordinates are exactly `kU`.
The y and z coordinates are constant.

The existing inward offset rounds away at B.
The end step also rounds to the exact final parameter.
Neither inset removes one ULP from the interval.

## Why no contiguous subdivision works

An interval spanning n ULPs has a first quarter-chord position at `nU/4` from its start.
If n is divisible by four, all three quarter parameters are representable.
Their residuals are zero for this fixture.
Otherwise the first quarter differs from every stored center by at least `U/4`, or 4096 meters.
It cannot meet the one-millimeter target.

Every accepted nonzero leaf must therefore span a multiple of four ULPs.
The complete interval spans five ULPs.
No contiguous partition can cover five ULPs with such leaves.
Zero-width leaves do not change this sum.
Increasing the depth cap cannot make the missing parameters representable.

| Depth | Interval in k | Rounded sample k values | x residuals in meters | Midpoint k |
|---:|---|---|---|---:|
| 0 | 0 to 5 | 1, 2, 4 | -4096, -8192, 4096 | 2 |
| 1 | 0 to 2 | 0, 1, 2 | -8192, 0, 8192 | 1 |
| 2 | 0 to 1 | 0, 0, 1 | -4096, -8192, 4096 | 0 |

At depth two, the midpoint equals the first endpoint.
The former recursion repeats this failed interval until depth 24.
The resolution guard rejects it immediately.

This is a limitation of the parameter-matched construction criterion.
It is not a proof that a different geometric index cannot represent this straight line.
A four-ULP interval at the same origin meets the current criterion.
A large ULP alone does not trigger rejection.

## Stored-point query results

The direct-Road minimum remains well-defined over the six stored parameters.
A query at x=10000 selects `B+16384`.
A query at x=8192 ties exactly and selects B.
A query at x=5000 selects B.
The common y residual does not change these comparisons.

The direct-Road controls retain these successful results.
The full-Map control instead checks explicit construction refusal with its original inputs.
It does not claim successful construction or an invented intermediate waypoint.
A caller can rebase all affected road-s records when its external references permit that representation change.
Map construction does not silently rebase them.

## Non-affine sampling progress

The non-affine index path requests steps of at most one meter.
Each positive nonterminal step must advance in the lane's direction.
An unchanged or wrong-directed result raises a Float64 road-s resolution error.
The terminal branch remains before this check.
It can retain the existing zero-span index entries.

A new regression uses the same B and end bits with a quadratic width coefficient of `1e-40`.
That nonzero coefficient selects the non-affine path.
Adding or subtracting the requested one-meter step rounds to the unchanged s.
Both lane directions must reject promptly.
This guard prevents the demonstrated nonprogress loop. It does not implement the separate map-wide work budgets in issue #580.

## Independent proof and controls

Run `python3 tools/carla_lane_oracle/translated_parameter_resolution.py`.
The script needs only the Python standard library.
It writes its report under `out/carla-lane-oracle` by default.
Set `CARLA_LANE_ORACLE_OUTPUT` to choose another directory.

The proof uses exact integer and Fraction arithmetic for nearest-even rounding.
It checks all 15 nonzero fixture subintervals and all 16 complete contiguous partitions.
It also checks both signed directions, midpoint parity, exact stored-point distances, and the nonterminal one-meter step.
Its source pin binds the proof to the reviewed scalar operations.
These are source-only controls. Native suite, coverage, format, consumer, and performance gates remain required.
