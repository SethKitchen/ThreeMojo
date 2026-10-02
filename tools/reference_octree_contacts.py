# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent Float64 oracle: projected face solve and all segment candidates.

No production Mojo code or three.js arithmetic is imported. Candidate order is
an unchanged broadphase fixture from test_octree.mojo. Run from the repo root:
`python3 tools/reference_octree_contacts.py`.
"""
import json
import math
add = lambda a, b: tuple((x + y for x, y in zip(a, b)))
sub = lambda a, b: tuple((x - y for x, y in zip(a, b)))
mul = lambda a, t: tuple((x * t for x in a))
dot = lambda a, b: sum((x * y for x, y in zip(a, b)))
cross = lambda a, b: (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
length = lambda a: math.sqrt(dot(a, a))
unit = lambda a: mul(a, 1 / length(a)) if length(a) else a
clamp = lambda a: max(0, min(1, a))

def near_segment(p, a, b):
    d = sub(b, a)
    return add(a, mul(d, clamp(dot(sub(p, a), d) / dot(d, d)))) if dot(d, d) else a

def segments(a, b, c, d):
    """Minimize the convex squared gap on all four boundaries and its interior."""
    u, v, r = (sub(b, a), sub(d, c), sub(a, c))
    candidates = [
        (a, near_segment(a, c, d)),
        (b, near_segment(b, c, d)),
        (near_segment(c, a, b), c),
        (near_segment(d, a, b), d),
    ]
    A, B, C, D, E = (dot(u, u), dot(u, v), dot(v, v), dot(u, r), dot(v, r))
    det = A * C - B * B
    if det > 0:
        s, t = ((B * E - C * D) / det, (A * E - B * D) / det)
        if 0 <= s <= 1 and 0 <= t <= 1:
            candidates.append((add(a, mul(u, s)), add(c, mul(v, t))))
    return min(candidates, key=lambda pq: dot(sub(*pq), sub(*pq)))

def face(t, p):
    a, b, c = t
    u, v = (sub(b, a), sub(c, a))
    n = unit(cross(u, v))
    z = dot(n, sub(p, a))
    projected = sub(p, mul(n, z))
    k = max(range(3), key=lambda i: abs(n[i]))
    axes = [i for i in range(3) if i != k]
    i, j = axes
    q = sub(projected, a)
    den = u[i] * v[j] - u[j] * v[i]
    if den == 0:
        return (False, n, z, projected)
    s = (q[i] * v[j] - q[j] * v[i]) / den
    w = (u[i] * q[j] - u[j] * q[i]) / den
    return (s >= 0 and w >= 0 and (s + w <= 1), n, z, projected)

def sphere(t, p, r):
    inside, n, z, projected = face(t, p)
    if abs(z) > r:
        return None
    if inside:
        return (n, r - z)
    nearest = min(
        (near_segment(p, t[i], t[(i + 1) % 3]) for i in range(3)),
        key=lambda q: dot(sub(p, q), sub(p, q)),
    )
    delta = sub(p, nearest)
    dist = length(delta)
    if dist <= r:
        return (unit(delta), r - dist)
    return None

def capsule(t, a, b, r):
    _, n, z1, _ = face(t, a)
    _, _, z2, _ = face(t, b)
    d1, d2 = (z1 - r, z2 - r)
    if min(d1, d2) > 0 or max(z1, z2) < 0:
        return None
    span = abs(d1) + abs(d2)
    frac = abs(d1) / span if span else 0
    p = add(a, mul(sub(b, a), frac))
    if face(t, p)[0]:
        return (n, abs(min(d1, d2)))
    for i in range(3):
        x, y = segments(a, b, t[i], t[(i + 1) % 3])
        delta = sub(x, y)
        dist = length(delta)
        if dist <= r:
            return (unit(delta), r - dist)
    return None

def level():
    h = lambda i, j: (i * 7 + j * 3) % 5 * 0.25
    out = []
    for i in range(6):
        for j in range(6):
            a = (i - 3, h(i, j), j - 3)
            b = (i - 3, h(i, j + 1), j - 2)
            c = (i - 2, h(i + 1, j + 1), j - 2)
            d = (i - 2, h(i + 1, j), j - 3)
            out.extend(((a, b, c), (a, c, d)))
    out.extend((((2, 0, -2), (2, 3, -2), (2, 3, 2)), ((2, 0, -2), (2, 3, 2), (2, 0, 2))))
    return out
triangles = level()
queries = {'sphere_ground': ('sphere',
                   (0.3, 0.3, 0.2),
                   None,
                   0.5,
                   [14,
                    15,
                    16,
                    17,
                    26,
                    27,
                    28,
                    29,
                    31,
                    30,
                    40,
                    41,
                    52,
                    38,
                    39,
                    50,
                    53,
                    43,
                    42,
                    54,
                    55,
                    33,
                    44,
                    45]),
 'sphere_shallow': ('sphere',
                    (0.3, 0.3, 0.2),
                    None,
                    0.5,
                    [29, 28, 31, 30, 40, 41, 52, 42, 43, 54, 55]),
 'sphere_wall': ('sphere',
                 (1.7, 1, 0),
                 None,
                 0.5,
                 [52,
                  41,
                  40,
                  27,
                  38,
                  39,
                  50,
                  53,
                  73,
                  64,
                  62,
                  63,
                  65,
                  72,
                  55,
                  54,
                  43,
                  30,
                  31,
                  33,
                  42,
                  44,
                  45,
                  66,
                  67,
                  69]),
 'capsule_ground': ('capsule',
                    (0.3, 0.2, 0.2),
                    (0.3, 1.2, 0.2),
                    0.35,
                    [14,
                     15,
                     16,
                     17,
                     26,
                     27,
                     28,
                     29,
                     31,
                     30,
                     40,
                     41,
                     38,
                     39,
                     50,
                     52,
                     53,
                     43,
                     42,
                     33,
                     44,
                     45,
                     55,
                     73,
                     72]),
 'capsule_wall': ('capsule',
                  (1.8, 0.8, 0.1),
                  (1.8, 1.8, 0.1),
                  0.3,
                  [73, 64, 53, 52, 62, 63, 65, 72, 66, 55, 54, 67, 69]),
 'capsule_slope': ('capsule',
                   (-1.2, 0.3, -1.4),
                   (-0.4, 0.5, -1),
                   0.3,
                   [12, 13, 14, 15, 24, 25, 26, 27, 16, 17, 28, 29])}
results = {}
for name, (kind, a, b, r, indices) in queries.items():
    original = a
    trace = []
    for index in indices:
        if kind == 'sphere':
            hit = sphere(triangles[index], a, r)
        else:
            hit = capsule(triangles[index], a, b, r)
        if hit:
            n, depth = hit
            offset = mul(n, depth)
            a = add(a, offset)
            if b is not None:
                b = add(b, offset)
            trace.append({
                'triangle': index, 'normal': n,
                'depth': depth, 'moved_start': a,
            })
    push = sub(a, original)
    results[name] = {'normal': unit(push), 'depth': length(push), 'trace': trace}
a, b = segments((0, 0, 0), (1, 0, 0), (2, -1, 0), (3, 1, 0))
assert all((abs(x - y) < 1e-14 for x, y in zip(a, (1, 0, 0))))
assert all((abs(x - y) < 1e-14 for x, y in zip(b, (2.2, -0.6, 0))))
assert abs(dot(sub(a, b), sub(a, b)) - 1.8) < 1e-14
edge = sphere(((0, 0, 0), (0, 0, 1), (1, 0, 0)), (-0.1, 0, 0.5), 0.3)
assert edge[0] == (-1, 0, 0)
assert abs(edge[1] - 0.2) < 1e-14
print(json.dumps(results, indent=2))
