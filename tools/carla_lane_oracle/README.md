<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Independent town lane controls

Run these controls with Python 3 and mpmath 1.3.0:

    python3 tools/carla_lane_oracle/oracle.py
    python3 tools/carla_lane_oracle/rounding.py
    python3 tools/carla_lane_oracle/poses.py
    python3 tools/carla_lane_oracle/counts.py
    python3 tools/carla_lane_oracle/translated_parameter_resolution.py

The reports go to `out/carla-lane-oracle`. Set `CARLA_LANE_ORACLE_OUTPUT`
to choose another directory. The scripts do not run Mojo or change source.

Reports label earlier measured query outputs as retained observations.
They do not claim a new native run.

The source hashes bind the proofs to the reviewed evaluator and town fixture.
A later evaluator change requires proof review, not a blind hash update.
The road hash starts at the first import, so module commentary can change.
`constants.json` preserves the native-exported binary64 constants as both
hexadecimal values and exact fractions. The source pin checks the quadrature
nodes and weights; rounded `1 + node` values are checked independently.

`oracle.py` uses exact rational coefficients and Gauss-Legendre moments.
It checks derivative signs, convexity perturbations and root brackets.
High-precision mpmath values display the roots; they are not substituted
for the exact rational sign checks.

`rounding.py` bounds the full rounded operation graph, including quadrature
count transitions, ARC quadrant and sinc transitions, and permitted FMA
contraction. It distinguishes ideal smooth values from operation error.
It does not assume that rounded evaluation is continuous.

`poses.py` differentiates the stored center expressions and independently
reconstructs the small sampled parabola tables.
`counts.py` derives the gentle-circle and mesh counts and enumerates the
26 town lane groups. The town index total is a retained native observation,
not an independent scalar-count proof.

These controls establish the specific ordinary fixtures described in
`docs/wiki/CARLA-lane-correction-controls.md`. They do not certify arbitrary
maps or replace native suite, coverage or performance gates.

`translated_parameter_resolution.py` needs only the Python standard library.
It proves the exact translated road-s construction limit with integer and
Fraction arithmetic. It also checks the positive nonterminal sampling step
that rounds to unchanged s. Its separate source pin covers the relevant
methods and fixture helper. It does not replace native refusal regressions.
