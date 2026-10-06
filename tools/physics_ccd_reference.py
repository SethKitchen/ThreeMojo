# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reproduce the independent 70-digit Decimal CCD entry-time fixtures.

The oracle minimizes convex point-to-triangle squared distance, then
bisects the first radius crossing. It does not use the sweep quadratic.
The fixed seed also produces misses and initial overlaps. Only entering
hits become the 23 native reference fixtures. Separate native tests check
misses, tangency, overlap, backfaces and numeric-domain refusals.
"""

import argparse
from decimal import Decimal, localcontext
import json
from pathlib import Path
import random
import struct

D = Decimal


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def mul(a, scalar):
    return tuple(x * scalar for x in a)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def f32(value):
    return struct.unpack('f', struct.pack('f', value))[0]


def nearest_sq(point, triangle):
    a, b, c = triangle
    normal = cross(sub(b, a), sub(c, a))
    normal_sq = dot(normal, normal)
    height = dot(sub(point, a), normal)
    projected = sub(point, mul(normal, height / normal_sq))
    edges = list(zip(triangle, triangle[1:] + triangle[:1]))
    if all(dot(cross(sub(y, x), sub(projected, x)), normal) >= 0
           for x, y in edges):
        return height * height / normal_sq
    distances = []
    for x, y in edges:
        edge = sub(y, x)
        fraction = max(D(0), min(D(1), dot(sub(point, x), edge)
                                 / dot(edge, edge)))
        offset = sub(point, add(x, mul(edge, fraction)))
        distances.append(dot(offset, offset))
    return min(distances)


def oracle(start, travel, radius, triangle):
    with localcontext() as context:
        context.prec = 70
        start = tuple(D(x) for x in start)
        travel = tuple(D(x) for x in travel)
        radius = D(radius)
        triangle = tuple(tuple(D(x) for x in p) for p in triangle)
        normal = cross(sub(triangle[1], triangle[0]),
                       sub(triangle[2], triangle[0]))
        height = dot(sub(start, triangle[0]), normal)
        if height < 0:
            return None
        radius_sq = radius * radius
        if nearest_sq(start, triangle) <= radius_sq:
            return 'inside'
        high = D(1)
        normal_travel = dot(travel, normal)
        if normal_travel < 0:
            high = min(high, -height / normal_travel)
        low = D(0)

        def distance(fraction):
            return nearest_sq(add(start, mul(travel, fraction)), triangle)

        for _ in range(170):
            first = (2 * low + high) / 3
            second = (low + 2 * high) / 3
            if distance(first) < distance(second):
                high = second
            else:
                low = first
        middle = (low + high) / 2
        if distance(middle) >= radius_sq - D('1e-40'):
            return None
        low, high = D(0), middle
        for _ in range(150):
            middle = (low + high) / 2
            if distance(middle) > radius_sq:
                low = middle
            else:
                high = middle
        return float(high)


def fixtures():
    rng = random.Random(292)
    result = []
    for _ in range(500):
        triangle = tuple(tuple(float(rng.randint(-10, 10))
                               for _ in range(3)) for _ in range(3))
        normal = cross(sub(triangle[1], triangle[0]),
                       sub(triangle[2], triangle[0]))
        if dot(normal, normal) == 0:
            continue
        start = tuple(f32(rng.uniform(-12, 12)) for _ in range(3))
        travel = tuple(f32(rng.uniform(-25, 25)) for _ in range(3))
        radius = f32(rng.uniform(0.1, 3))
        expected = oracle(start, travel, radius, triangle)
        if expected is None or expected == 'inside':
            continue
        result.append(dict(start=start, travel=travel, radius=radius,
                           triangle=triangle, expected=expected))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', type=Path, required=True)
    args = parser.parse_args()
    expected = json.loads(json.dumps(fixtures()))
    actual = json.loads(args.check.read_text())
    # Feature labels are descriptive metadata. Reproduce every geometric
    # input and expected time independently of those labels.
    projected = [{key: item[key] for key in expected[0]} for item in actual]
    if expected != projected:
        raise SystemExit('CCD reference fixture mismatch')
    print(f'{len(expected)} independent Decimal CCD references reproduced')


if __name__ == '__main__':
    main()
