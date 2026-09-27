# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Values of three.js 0.180's MaterialX noises, for `tests/test_nodes.mojo`.

three.js writes these noises in TSL, `src/nodes/materialx/lib/mx_noise.js`,
which runs only on a GPU. This file transcribes the functions the tests
check, line by line, in 32-bit floats and 32-bit unsigned integers, in the
same order of operations. Run it with numpy: `python mx_noise.py`.
"""

import numpy as np

f = np.float32
u32 = np.uint32


def rotl(x, k):
    x = u32(x)
    return u32((int(x) << k | int(x) >> (32 - k)) & 0xFFFFFFFF)


def sub(a, b):
    return u32((int(a) - int(b)) & 0xFFFFFFFF)


def add(a, b):
    return u32((int(a) + int(b)) & 0xFFFFFFFF)


def bjmix(a, b, c):
    a = sub(a, c); a ^= rotl(c, 4); c = add(c, b)
    b = sub(b, a); b ^= rotl(a, 6); a = add(a, c)
    c = sub(c, b); c ^= rotl(b, 8); b = add(b, a)
    a = sub(a, c); a ^= rotl(c, 16); c = add(c, b)
    b = sub(b, a); b ^= rotl(a, 19); a = add(a, c)
    c = sub(c, b); c ^= rotl(b, 4); b = add(b, a)
    return a, b, c


def bjfinal(a, b, c):
    c ^= b; c = sub(c, rotl(b, 14))
    a ^= c; a = sub(a, rotl(c, 11))
    b ^= a; b = sub(b, rotl(a, 25))
    c ^= b; c = sub(c, rotl(b, 16))
    a ^= c; a = sub(a, rotl(c, 4))
    b ^= a; b = sub(b, rotl(a, 14))
    c ^= b; c = sub(c, rotl(b, 24))
    return c


def hash_int(*xs):
    seed = add(add(u32(0xDEADBEEF), u32(len(xs) << 2)), 13)
    ints = [u32(x & 0xFFFFFFFF) for x in xs]
    if len(xs) == 1:
        return bjfinal(add(seed, ints[0]), seed, seed)
    a = add(seed, ints[0])
    b = add(seed, ints[1])
    c = add(seed, ints[2]) if len(xs) >= 3 else seed
    if len(xs) <= 3:
        return bjfinal(a, b, c)
    a, b, c = bjmix(a, b, c)
    a = add(a, ints[3])
    if len(xs) == 5:
        b = add(b, ints[4])
    return bjfinal(a, b, c)


def bits_to_01(bits):
    return f(f(bits) / f(4294967295))


def floorfrac(x):
    i = int(np.floor(f(x)))
    return f(f(x) - f(i)), i


def fade(t):
    return f(f(f(t * t) * t) * f(f(t * f(f(t * f(6.0)) - f(15.0))) + f(10.0)))


def gradient(h, x, y, z=None):
    if z is None:
        h &= 7
        uu = x if h < 4 else y
        vv = f(f(2.0) * (y if h < 4 else x))
    else:
        h &= 15
        uu = x if h < 8 else y
        vv = y if h < 4 else (x if h in (12, 14) else z)
    uu = -uu if h & 1 else uu
    vv = -vv if h & 2 else vv
    return f(uu + vv)


def bilerp(v0, v1, v2, v3, s, t):
    s1 = f(f(1.0) - s)
    return f(f(f(1.0) - t) * f(f(v0 * s1) + f(v1 * s))) + f(t * f(f(v2 * s1) + f(v3 * s)))


def trilerp(v, s, t, r):
    s1 = f(f(1.0) - s)
    t1 = f(f(1.0) - t)
    r1 = f(f(1.0) - r)
    near = f(t1 * f(f(v[0] * s1) + f(v[1] * s))) + f(t * f(f(v[2] * s1) + f(v[3] * s)))
    far = f(t1 * f(f(v[4] * s1) + f(v[5] * s))) + f(t * f(f(v[6] * s1) + f(v[7] * s)))
    return f(f(r1 * f(near)) + f(r * f(far)))


def perlin_vec3(p):
    if len(p) == 2:
        fx, X = floorfrac(p[0])
        fy, Y = floorfrac(p[1])
        uu, vv = fade(fx), fade(fy)
        out = []
        for k in range(3):
            def g(dx, dy):
                h = (int(hash_int(X + dx, Y + dy)) >> (8 * k)) & 0xFF
                return gradient(h, f(fx - f(dx)), f(fy - f(dy)))
            out.append(f(f(0.6616) * bilerp(g(0, 0), g(1, 0), g(0, 1), g(1, 1), uu, vv)))
        return out
    fx, X = floorfrac(p[0])
    fy, Y = floorfrac(p[1])
    fz, Z = floorfrac(p[2])
    uu, vv, ww = fade(fx), fade(fy), fade(fz)
    out = []
    for k in range(3):
        v = []
        for dz in (0, 1):
            for dy in (0, 1):
                for dx in (0, 1):
                    h = (int(hash_int(X + dx, Y + dy, Z + dz)) >> (8 * k)) & 0xFF
                    v.append(gradient(h, f(fx - f(dx)), f(fy - f(dy)), f(fz - f(dz))))
        out.append(f(f(0.9820) * trilerp(v, uu, vv, ww)))
    return out


def cell_float(p):
    return bits_to_01(hash_int(*[int(np.floor(f(x))) for x in p]))


def cell_vec3(p):
    ints = [int(np.floor(f(x))) for x in p]
    return [bits_to_01(hash_int(*(ints + [k]))) for k in range(3)]


def worley(p, jitter, width):
    ints = []
    local = []
    for x in p:
        fr, i = floorfrac(x)
        ints.append(i)
        local.append(fr)
    best = [f(1e6)] * width
    ranges = [(-1, 0, 1)] * len(p)
    import itertools
    for offs in itertools.product(*ranges):
        tmp = cell_vec3([f(o + i) for o, i in zip(offs, ints)])
        off = [f(f(f(tmp[k] - f(0.5)) * f(jitter)) + f(0.5)) for k in range(len(p))]
        diff = [f(f(f(offs[k]) + off[k]) - local[k]) for k in range(len(p))]
        dist = f(0)
        for d in diff:
            dist = f(dist + f(d * d))
        if dist < best[0]:
            best = [dist] + best[:-1]
        elif width > 1 and dist < best[1]:
            best = [best[0], dist] + best[1:-1]
        elif width > 2 and dist < best[2]:
            best[2] = dist
    return best


if __name__ == "__main__":
    for p in ([0.3, 0.7], [-1.25, 2.5], [0.3, 0.7, 0.2], [3.1, -2.3, 5.9]):
        print("perlin_vec3", p, [float(x) for x in perlin_vec3(p)])
    for p in ([0.3], [-1.25, 2.5], [0.3, 0.7, 0.2], [3.1, -2.3, 5.9, -0.4]):
        print("cell_float", p, float(cell_float(p)), "cell_vec3", [float(x) for x in cell_vec3(p)])
    for p in ([0.3, 0.7], [-1.25, 2.5, 0.6]):
        for jitter in (1.0, 0.5):
            for width in (1, 2, 3):
                print("worley", p, jitter, width, [float(x) for x in worley(p, jitter, width)])
