<!-- Copyright (c) 2026 Seth Kitchen, PE -->
<!-- SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 -->

# CARLA curve candidate admission

This admission bound requires the corrected segment key from issue #589.
It does not certify the lane selected from the admitted candidates.
The global lane query remains under validation in draft #594.

## Stored chord contract

Let D be the exact squared distance to a stored Float32 chord.
Let K be the RTree's computed key for that chord and query.
The corrected key satisfies K <= (1 + 2^-40) D.
The RTree returns candidates in increasing key order.
Its node bounds cannot exceed a stored entry's key.
See the segment query numerical contract for the supported finite inputs.

The lower chord radius is sqrt(K / (1 + 2^-40)).
Division and square root round outward before the lower endpoint is used.
A nonfinite or negative key disables this rejection.

## Full curve bound

Construction supplies a bound E on the distance from the full stored center evaluator to its stored chord.
This includes endpoint conversion and evaluator rounding.
It does not use the sampled one-millimeter chord target as a certificate.
The lower curve radius is max(0, lower_chord_radius - E), with outward subtraction.
An unknown or nonfinite deviation disables this rejection.

The map retains the maximum E across its indexed segments.
Thus the same lower bound applies to every later candidate in the sorted prefix.
The query can stop only when that lower radius exceeds the incumbent point's wide upper radius.
Equality retains the candidate and the insertion-order tie policy.

## Per-segment skip

Each indexed segment also stores its own bound E (issue #685, item 1).
The map's maximum is the largest of these values.
The index orders its keys only, so the query keeps the stop above with the maximum E.

After that stop, the query computes the same lower radius with the candidate's own E.
When this radius is strictly greater than the incumbent's wide upper radius, the query skips the candidate.
The skip comes before candidate admission and refinement, like the box and sampled-cover skips.
The incumbent's radius bounds the distance of an actual stored witness point.
Thus a skipped candidate cannot win or tie, and every answer and certificate stays the same.
An unknown or nonfinite E gives a zero radius, so that candidate is not skipped.

On `assets/carla/town.xodr` the skip removes about 44 percent of the candidate certifications.
See [the #685 measurement](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/certified-query-685.md).
The source edge has its own reviewed lane-oracle record, `map_deviation_contracts.py`.

## Separate limits

This bound does not prove a minimum inside an admitted segment.
Cross-candidate minimum intervals and strict on-road classification need separate certificates.
It does not change the local refinement limits or provide a global map work budget.

The query rejects a nonfinite Float32 query before it enters the index.
Construction rejects an endpoint that cannot be stored as a finite Float32 value.
It does not clamp or silently cap that coordinate.
Full center arithmetic remains Float64 inside the query.
Public transform storage still has its separate Float32 precision and range limit.
