# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Values of three.js r186's TSL functions, for `tests/test_tsl_*.mojo`.

three.js writes these functions in TSL, which runs only on a GPU. This file
transcribes the ones the tests check, line by line, in 32-bit floats and
32-bit unsigned integers, in the same order of operations:

- `src/nodes/math/Hash.js`, `TriNoise3D.js` and the packings;
- `examples/jsm/tsl/math/curlNoise.js` and `voronoiNoise.js`;
- `examples/jsm/tsl/utils/RNoise.js` and `SpecularHelpers.js`.

Each value is also computed in 64-bit floats. A test point is one where the
two agree, so no `floor` or `fract` sits on an edge. Run it with numpy:
`python tsl_reference.py`.
"""

import math
import struct

import numpy as np

f = np.float32


def F(x):
    return f(x)


# --- hash ---------------------------------------------------------------------


def pcg_hash(seed):
    state = (int(seed) * 747796405 + 2891336453) & 0xFFFFFFFF
    word = (((state >> ((state >> 28) + 4)) ^ state) * 277803737) & 0xFFFFFFFF
    result = ((word >> 22) ^ word) & 0xFFFFFFFF
    return f(f(result) * f(1 / 2**32))


# --- bits ---------------------------------------------------------------------


def float_bits(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def half_bits(x):
    return int(np.array([x], dtype=np.float16).view(np.uint16)[0])


# --- triNoise3D ---------------------------------------------------------------


def fract(x):
    return x - np.floor(x)


def mod(x, y):
    """GLSL's `mod`: `x - y * floor(x / y)`, each step rounded."""
    return x - y * np.floor(x / y)


def dot(a, b):
    """A dot product summed from the first component, as the port sums it."""
    total = a[0] * b[0]
    for k in range(1, len(a)):
        total = total + a[k] * b[k]
    return total


def tri(x):
    return np.abs(fract(x) - F(0.5))


def tri3(p):
    return np.array(
        [tri(p[2] + tri(p[1])), tri(p[2] + tri(p[0])), tri(p[1] + tri(p[0]))],
        dtype=f,
    )


def tri_noise_3d(position, speed, time):
    p = np.array(position, dtype=f)
    z = F(1.4)
    rz = F(0)
    bp = p.copy()
    drift = F(time) * (F(0.1) * F(speed))
    for _ in range(4):
        dg = tri3(bp * F(2))
        p = p + (dg + drift)
        bp = bp * F(1.8)
        z = z * F(1.5)
        p = p * F(1.2)
        t = tri(p[2] + tri(p[0] + tri(p[1])))
        rz = rz + t / z
        bp = bp + F(0.14)
    return rz


# --- simplex and curl noise ---------------------------------------------------


def permute(x):
    return mod(x * x * F(34) + x, F(289))


def step(edge, x):
    return (x >= edge).astype(f)


def snoise(v):
    v = np.array(v, dtype=f)
    C = np.array([F(1) / F(6), F(1) / F(3)], dtype=f)
    i = np.floor(v + dot(v, np.array([C[1]] * 3, dtype=f)))
    x0 = v - i + dot(i, np.array([C[0]] * 3, dtype=f))
    g = step(x0[[1, 2, 0]], x0)
    l = F(1) - g
    i1 = np.minimum(g, l[[2, 0, 1]])
    i2 = np.maximum(g, l[[2, 0, 1]])
    x1 = x0 - i1 + C[0]
    x2 = x0 - i2 + C[1]
    x3 = x0 - F(0.5)
    i = mod(i, F(289))
    p = permute(i[2] + np.array([0, i1[2], i2[2], 1], dtype=f))
    p = permute(p + i[1] + np.array([0, i1[1], i2[1], 1], dtype=f))
    p = permute(p + i[0] + np.array([0, i1[0], i2[0], 1], dtype=f))
    ns = F(0.142857142857) * np.array([2, 0.5, 1], dtype=f) - np.array(
        [0, 1, 0], dtype=f
    )
    j = p - F(49) * np.floor(p * ns[2] * ns[2])
    x_ = np.floor(j * ns[2])
    x = x_ * ns[0] + ns[1]
    y = np.floor(j - F(7) * x_) * ns[0] + ns[1]
    h = F(1) - np.abs(x) - np.abs(y)
    b0 = np.array([x[0], x[1], y[0], y[1]], dtype=f)
    b1 = np.array([x[2], x[3], y[2], y[3]], dtype=f)
    sh = -step(h, np.zeros(4, dtype=f))
    a0 = b0[[0, 2, 1, 3]] + (np.floor(b0) * F(2) + F(1))[[0, 2, 1, 3]] * sh[[0, 0, 1, 1]]
    a1 = b1[[0, 2, 1, 3]] + (np.floor(b1) * F(2) + F(1))[[0, 2, 1, 3]] * sh[[2, 2, 3, 3]]
    p0 = np.array([a0[0], a0[1], h[0]], dtype=f)
    p1 = np.array([a0[2], a0[3], h[1]], dtype=f)
    p2 = np.array([a1[0], a1[1], h[2]], dtype=f)
    p3 = np.array([a1[2], a1[3], h[3]], dtype=f)
    norm = F(1) / np.sqrt(
        np.array([dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)], dtype=f)
    )
    p0 = p0 * norm[0]
    p1 = p1 * norm[1]
    p2 = p2 * norm[2]
    p3 = p3 * norm[3]
    m = np.maximum(
        F(0.6)
        - np.array([dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)], dtype=f),
        F(0),
    )
    grades = np.array([dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)], dtype=f)
    return F(0.5) + F(12) * dot(m * m * m, grades)


def snoise_vec3(x):
    x = np.array(x, dtype=f)
    first = snoise(x * F(2) - F(1))
    second = snoise(
        np.array([x[1] - F(19.1), x[2] + F(33.4), x[0] + F(47.2)], dtype=f)
    ) * F(2) - F(1)
    third = snoise(
        np.array([x[2] + F(74.2), x[0] - F(124.5), x[1] + F(99.4)], dtype=f) * F(2) - F(1)
    )
    return np.array([first, second, third], dtype=f)


def curl_noise(p):
    p = np.array(p, dtype=f)
    e = F(0.1)
    dx = np.array([e, 0, 0], dtype=f)
    dy = np.array([0, e, 0], dtype=f)
    dz = np.array([0, 0, e], dtype=f)
    p_x0 = snoise_vec3(p - dx)
    p_x1 = snoise_vec3(p + dx)
    p_y0 = snoise_vec3(p - dy)
    p_y1 = snoise_vec3(p + dy)
    p_z0 = snoise_vec3(p - dz)
    p_z1 = snoise_vec3(p + dz)
    x = p_y1[2] - p_y0[2] - p_z1[1] + p_z0[1]
    y = p_z1[0] - p_z0[0] - p_x1[2] + p_x0[2]
    z = p_x1[1] - p_x0[1] - p_y1[0] + p_y0[0]
    divisor = F(1) / (F(2) * e)
    return np.array([x, y, z], dtype=f) * divisor


# --- Voronoi ------------------------------------------------------------------


def hash2d(p):
    d = np.array(
        [dot(p, np.array([127.1, 311.7], dtype=f)), dot(p, np.array([269.5, 183.3], dtype=f))],
        dtype=f,
    )
    return fract(np.sin(d) * F(18.5453))


def hash3d(p):
    d = np.array(
        [
            dot(p, np.array([127.1, 311.7, 74.7], dtype=f)),
            dot(p, np.array([269.5, 183.3, 246.1], dtype=f)),
            dot(p, np.array([113.5, 271.9, 124.6], dtype=f)),
        ],
        dtype=f,
    )
    return fract(np.sin(d) * F(18.5453))


def voronoi(p, time, hasher, dims):
    p = np.array(p, dtype=f)
    n = np.floor(p)
    fr = fract(p)
    nearest = F(8)
    import itertools

    for cell in itertools.product([-1, 0, 1], repeat=dims):
        g = np.array(cell, dtype=f)
        o = hasher(n + g)
        r = g - fr + (np.sin(F(time) + o * F(2 * math.pi)) * F(0.5) + F(0.5))
        nearest = min(nearest, dot(r, r))
    return nearest


# --- RNoise -------------------------------------------------------------------


def analytic_noise(uv, sample_index, resolution, seed=0):
    P = 1.32471795724474602596
    index = F(int(sample_index) + seed)
    pixel = np.floor(np.array(uv, dtype=f) * np.array(resolution, dtype=f))
    offset = np.floor(
        fract(np.array([index * F(0.7548776662), index * F(0.5698402910)], dtype=f)) * F(32)
    )
    c = mod(pixel + offset, F(32))
    t = c[0] * F(1 / P) + c[1] * F(1 / P**2) + F(seed)
    return np.array(
        [
            fract(t * F(P) * F(1 / P)),
            fract(t * F(P * 2) * F(1 / P**2)),
            fract(t * F(P * 3) * F(0.4198754210)),
            fract(t * F(P * 4) * F(1 / P**3)),
        ],
        dtype=f,
    )


# --- specular helpers ---------------------------------------------------------


def normalize(v):
    n = np.sqrt(dot(v, v))
    return v / n if n != 0 else v


def sample_ggx_vndf(V, ax, ay, r1, r2):
    V = np.array(V, dtype=f)
    ax, ay, r1, r2 = F(ax), F(ay), F(r1), F(r2)
    wi = normalize(np.array([ax * V[0], ay * V[1], V[2]], dtype=f))
    a = min(ax, ay)
    s = F(1) + np.sqrt(V[0] * V[0] + V[1] * V[1])
    a2 = a * a
    s2 = s * s
    k = (F(1) - a2) * s2 / (s2 + a2 * V[2] * V[2])
    b = wi[2] * k
    phi = F(6.283185307179586) * r1
    z = (F(1) - r2) * (F(1) + b) - b
    sin_theta = np.sqrt(max(F(0), F(1) - z * z))
    c = np.array([sin_theta * np.cos(phi), sin_theta * np.sin(phi), z], dtype=f)
    wm = c + wi
    return normalize(np.array([ax * wm[0], ay * wm[1], max(F(0), wm[2])], dtype=f))


def d_gtr(r, noh, k):
    a2 = F(r) * F(r)
    base = F(noh) * F(noh) * (a2 - F(1)) + F(1)
    return a2 / (F(math.pi) * np.power(base, F(k)))


def smith_g(ndx, alpha):
    a2 = F(alpha) * F(alpha)
    ndx = F(ndx)
    return F(2) * ndx / (ndx + np.sqrt(a2 + (F(1) - a2) * ndx * ndx))


def ggx_vndf_pdf(noh, nov, r):
    D = d_gtr(r, noh, 2)
    r, nov = F(r), F(nov)
    a2 = r * r
    sin_v2 = max(F(0), F(1) - nov * nov)
    s = F(1) + np.sqrt(sin_v2)
    s2 = s * s
    k = (F(1) - a2) * s2 / (s2 + a2 * nov * nov)
    t = np.sqrt(a2 * sin_v2 + nov * nov)
    return D / max(F(1e-6), F(2) * (k * nov + t))


def specular_dominant(nov, r):
    a = F(0.298475) * np.log(F(39.4115) - F(39.0029) * F(r))
    return min(max(np.power(F(1) - F(nov), F(10.8649)) * (F(1) - a) + a, 0), 1)


def ggx_reflection_sample(N, V, roughness, metalness, albedo, xi):
    N = np.array(N, dtype=f)
    V = np.array(V, dtype=f)
    albedo = np.array(albedo, dtype=f)
    a = max(F(roughness) * F(roughness), F(0.001))
    T = normalize(np.cross(np.array([0, 0, 1], dtype=f), N))
    if np.sqrt(dot(T, T)) < 1e-3:
        T = normalize(np.cross(np.array([0, 1, 0], dtype=f), N))
    B = normalize(np.cross(N, T))
    vl = np.array([dot(T, V), dot(B, V), dot(N, V)], dtype=f)
    hl = sample_ggx_vndf(vl, a, a, xi[0], xi[1])
    if hl[2] < 0:
        hl = -hl
    h = normalize(T * hl[0] + B * hl[1] + N * hl[2])
    L = normalize(-V - F(2) * dot(h, -V) * h)
    H = normalize(V + L)
    nov = max(F(0), dot(N, V))
    nol = max(F(0), dot(N, L))
    noh = max(F(0), dot(N, H))
    voh = max(F(0), dot(V, H))
    f0 = np.array([0.04] * 3, dtype=f) * (F(1) - F(metalness)) + albedo * F(metalness)
    om = F(1) - voh
    om5 = om * om * om * om * om
    fres = f0 + (F(1) - f0) * om5
    pdf = ggx_vndf_pdf(noh, nov, a)
    a2 = a * a
    sin_v2 = max(F(1) - nov * nov, F(0))
    s = F(1) + np.sqrt(sin_v2)
    s2 = s * s
    k = (F(1) - a2) * s2 / (s2 + a2 * nov * nov)
    t = np.sqrt(a2 * sin_v2 + nov * nov)
    g2 = smith_g(nov, a) * smith_g(nol, a)
    weight = fres * g2 * (k * nov + t) / max(F(2) * nov, F(1e-4))
    return L, weight, pdf, nov, a, f0


if __name__ == "__main__":
    for seed in [0, 1, 7, 12345, 16777215]:
        print("hash", seed, repr(float(pcg_hash(seed))))
    for x in [1.0, -2.5, 0.1, 8.0, 0.99999994, 3.0e38, 1.1754944e-38, 123456.789]:
        b = float_bits(np.float32(x))
        print("bits", x, hex(b), b & 0xFFFF, b >> 16)
    for x in [1.0, -2.0, 65504.0, 65519.0, 65520.0, 1e-5, 0.1, 6.1035156e-05, -0.33333334, 5.9604645e-08, 2.9802322e-08, 8.940697e-08]:
        print("half", x, hex(half_bits(x)))
    for p, s, t in [((0.3, 0.7, 1.1), 1.0, 0.5), ((2.5, -1.25, 0.4), 0.3, 3.0)]:
        print("triNoise3D", p, s, t, repr(float(tri_noise_3d(p, s, t))))
    for p in [(0.3, 0.7, 1.1), (2.5, -1.25, 0.4), (-3.7, 5.2, 0.05)]:
        print("snoise", p, repr(float(snoise(p))))
        print("snoiseVec3", p, [repr(float(c)) for c in snoise_vec3(p)])
        print("curl", p, [repr(float(c)) for c in curl_noise(p)])
    for p, t in [((0.3, 0.7), 0.0), ((2.5, -1.25), 1.5)]:
        print("voronoi2d", p, t, repr(float(voronoi(p, t, hash2d, 2))))
        print("hash2d", p, [repr(float(c)) for c in hash2d(np.array(p, dtype=f))])
    for p, t in [((0.3, 0.7, 1.1), 0.0), ((2.5, -1.25, 0.4), 1.5)]:
        print("voronoi3d", p, t, repr(float(voronoi(p, t, hash3d, 3))))
        print("hash3d", p, [repr(float(c)) for c in hash3d(np.array(p, dtype=f))])
    for uv, i, res, seed in [((0.25, 0.75), 0, (64, 32), 0), ((0.6, 0.1), 3, (800, 600), 2)]:
        print("rnoise", uv, i, res, seed, [repr(float(c)) for c in analytic_noise(uv, i, res, seed)])
    print("vndf", [repr(float(c)) for c in sample_ggx_vndf((0.3, 0.2, 0.9327379), 0.4, 0.4, 0.25, 0.6)])
    print("d_gtr", repr(float(d_gtr(0.5, 0.8, 2))))
    print("smith_g", repr(float(smith_g(0.7, 0.3))))
    print("pdf", repr(float(ggx_vndf_pdf(0.9, 0.6, 0.4))))
    print("dominant", repr(float(specular_dominant(0.5, 0.3))))
    L, w, pdf, nov, a, f0 = ggx_reflection_sample(
        (0, 0.6, 0.8), (0.28, 0.0, 0.96), 0.5, 0.3, (0.9, 0.5, 0.2), (0.3, 0.7)
    )
    print("ggx L", [repr(float(c)) for c in L])
    print("ggx w", [repr(float(c)) for c in w])
    print("ggx pdf nov a", repr(float(pdf)), repr(float(nov)), repr(float(a)))
    print("ggx f0", [repr(float(c)) for c in f0])
