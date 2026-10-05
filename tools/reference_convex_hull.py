# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate independent Fraction controls for the public convex-hull API.

The oracle decodes the retained binary64 words, enumerates supporting
triangles, and compares squared exact plane distances against tolerance.
It uses no production predicates or rounded plane normals. Run --check to
verify the saved fixture; use --write to replace it deliberately.
"""

import argparse
from fractions import Fraction
from itertools import combinations
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "assets/convex_hull/exact.txt"


def word(value):
    """Return a signed decimal word that fits Mojo's Int parser."""
    return struct.unpack("<q", struct.pack("<d", value))[0]


def decode(value):
    """Decode finite binary64 directly, including the subnormal quantum."""
    bits = word(value) & ((1 << 64) - 1)
    exponent = (bits >> 52) & 2047
    significand = bits & ((1 << 52) - 1)
    assert exponent != 2047
    if exponent:
        significand |= 1 << 52
    result = Fraction(significand) * Fraction(2) ** (max(1, exponent) - 1075)
    return -result if bits >> 63 else result


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def facets(points):
    """Enumerate all outward supporting triangles, including coplanar ones."""
    exact = [tuple(map(decode, p)) for p in points]
    result = []
    for a, b, c in combinations(range(len(points)), 3):
        normal = cross(sub(exact[b], exact[a]), sub(exact[c], exact[a]))
        if not dot(normal, normal):
            continue
        signs = [dot(normal, sub(p, exact[a])) for p in exact]
        if max(signs) == 0 and min(signs) < 0:
            result.append((a, b, c))
        elif min(signs) == 0 and max(signs) > 0:
            result.append((a, c, b))
    assert result, "The fixture must have three-dimensional volume"
    return exact, result


def contains(points, planes, query, tolerance):
    query = tuple(map(decode, query))
    tolerance = decode(tolerance)
    assert tolerance >= 0
    for a, b, c in planes:
        normal = cross(sub(points[b], points[a]), sub(points[c], points[a]))
        determinant = dot(normal, sub(query, points[a]))
        if determinant > 0 and determinant * determinant > (
                tolerance * tolerance * dot(normal, normal)):
            return False
    return True


def cases():
    tiny = math.ulp(0.0)
    slanted = [(0, 0, 0), (2, 1, 0), (0, 3, 1), (1, 0, 4)]
    probes = [(0, 0, 0), (1, 1, 1), (2, 2, 2), (-1, 0, 0),
              (2, 1, 1), (1, 2, 1), (0, 1, 0), (1, 0, 0)]
    result = []
    for exponent in [-1074, -1000, -500, 0, 500, 1000]:
        scale = math.ldexp(1.0, exponent)
        points = [tuple(v * scale for v in p) for p in slanted]
        queries = [(tuple(v * scale for v in p), t)
                   for p in probes for t in (0.0, scale)]
        result.append((f"slanted_{exponent}", points, queries))
    # A scaling-only representation loses these nonzero plane anchors.
    huge = math.ldexp(1.0, 1000)
    points = [(tiny, tiny, tiny), (huge, tiny, tiny),
              (tiny, huge, tiny), (tiny, tiny, huge)]
    queries = [(p, 0.0) for p in points]
    for axis in range(3):
        p = [tiny, tiny, tiny]
        p[axis] = 0.0
        queries.extend([(tuple(p), 0.0), (tuple(p), tiny)])
    queries.extend([((0.0, 0.0, 0.0), t) for t in (0.0, tiny)])
    result.append(("retained_subnormal_anchors", points, queries))
    # Large translations expose cancellation in affine differences.
    side, offset = math.ldexp(1.0, 460), math.ldexp(1.0, 500)
    def move(p):
        return (offset + p[0] * side, -offset + p[1] * side,
                offset + p[2] * side)
    result.append(("translated_slanted", list(map(move, slanted)),
                   [(move(p), t) for p in probes for t in (0.0, side)]))
    # This supporting plane has the exact normal (3, 4, 12) / 13.
    # The query is exactly one scale unit outside it, even at exponent ends.
    for exponent in [-1074, -500, 0, 500, 1000]:
        s = math.ldexp(1.0, exponent)
        points = [(0.0, 0.0, 0.0), (4*s, 0.0, 0.0),
                  (0.0, 3*s, 0.0), (0.0, 0.0, s)]
        q = (3*s, 4*s, 0.0)
        queries = [(q, math.nextafter(s, 0.0)), (q, s),
                   (q, math.nextafter(s, math.inf)), (q, 0.0)]
        result.append((f"positive_boundary_{exponent}", points, queries))
    # A rotated cube keeps the last point out of the initial axis extremes.
    # A tolerance-based horizon can retain an adjacent visible face and
    # create a new face that excludes old vertices by much more than t.
    cube = [(0., 0., 0.), (1., 1., -1.), (1., -1., 1.), (2., 0., 0.),
            (1., 1., 1.), (2., 2., 0.), (2., 0., 2.), (3., 1., 1.)]
    horizon_eye = (2.5000000000000053, 0.4999999999999982,
                   1.5000000000000053)
    # This extremal point is less than the positive tolerance outside the
    # original cube. Exact assignment must retain it for zero queries.
    delta = math.ldexp(1., -50)
    assignment_eye = (2. + delta, 1. + delta, 1. + delta)
    for name, eye in [("horizon", horizon_eye), ("assignment", assignment_eye)]:
        for exponent in [-500, 0, 500]:
            scale = math.ldexp(1., exponent)
            points = [tuple(v * scale for v in p) for p in cube + [eye]]
            queries = [(p, 0.) for p in points]
            queries.extend([((1.5 * scale, .5 * scale, .5 * scale), 0.),
                            ((4. * scale, 0., 0.), 0.)])
            result.append((f"strict_{name}_{exponent}", points, queries))
    return result


def render():
    lines = []
    query_count = 0
    for name, points, queries in cases():
        exact, planes = facets(points)
        lines.append(f"{name} {len(points)} {len(planes)} {len(queries)}")
        lines.extend(" ".join(str(word(v)) for v in p) for p in points)
        lines.extend(" ".join(map(str, plane)) for plane in planes)
        for query, tolerance in queries:
            expected = int(contains(exact, planes, query, tolerance))
            lines.append(" ".join(map(str, (*map(word, query),
                                              word(tolerance), expected))))
            query_count += 1
    return "\n".join(lines) + "\n", query_count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()
    text, queries = render()
    if args.write:
        FIXTURE.parent.mkdir(parents=True, exist_ok=True)
        FIXTURE.write_text(text)
    else:
        assert FIXTURE.read_text() == text, "Exact hull fixture differs"
    print(f"Verified {len(cases())} convex hulls and {queries} exact queries")


if __name__ == "__main__":
    main()
