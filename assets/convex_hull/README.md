<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Exact convex hull controls

`exact.txt` stores binary64 words as signed decimal integers. It contains 19 small hulls and 210 containment queries. Expected oriented triangles and distance comparisons come from Python `Fraction` arithmetic.

Run `python3 tools/reference_convex_hull.py --check` to verify the saved data. Use `--write` to regenerate it. The generator does not call production predicates or use rounded normals.

The controls include slanted subnormal clouds, mixed exponents, translated clouds and one-ULP tolerance boundaries. The `strict_horizon` cases expose tolerance-based fan folding. The `strict_assignment` cases retain exact near-plane vertices that a positive assignment threshold would omit.

`tests/test_convex_hull_exact.mojo` checks exact supporting facets, paired edges, winding and source containment. A separate integer oracle checks larger subnormal clouds. The ordinary face-order control comes from the retained three.js r180 fixture.
