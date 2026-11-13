# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Prints the numbers that the stochastic SSR and specular denoiser tests pin.

Run it from anywhere, with no packages installed:

    python3 assets/ssr_denoise/reference.py

It is a transcription, in Python doubles, of these files of three.js 0.186.0:

- `examples/jsm/tsl/utils/RNoise.js`: `bindAnalyticNoise`.
- `examples/jsm/tsl/utils/SpecularHelpers.js`: `SampleGGXVNDF`, `GGXVNDFPdf`,
  `ggxReflectionSample` and `getSpecularDominantFactor`.
- `examples/jsm/tsl/display/SSRNode.js`: `computeScreenBorderFactor`.
- `examples/jsm/tsl/display/TemporalReprojectNode.js`: the resolve pass, in
  its diffuse mode and its specular mode.
- `examples/jsm/tsl/display/RecurrentDenoiseNode.js`: the denoise pass, in
  both modes, with a raw signal, accumulating, and the ray length in alpha.

The first part feeds `tests/test_rnoise.mojo`,
`tests/test_importance_sampled_environment.mojo` and `tests/test_ssr_node.mojo`.
The second part runs the two nodes on the 6 by 6 frame that
`tests/test_temporal_denoise.mojo` builds, and feeds its grid tests.

Where a GPU leaves a result undefined, the transcription follows the port:
a texel read past the edge is the edge texel, a derivative is the difference
across the pixel's 2 by 2 quad, and a normalized zero vector is zero. The
inputs are rounded to Float32, as the port stores them. The port computes in
Float32, so the tests compare to four or five places.
"""
import math
import struct

EPS = 1e-6
ENV = 1e4
ENV_T = 1e3
W = H = 6


def f32(x):
    return struct.unpack("f", struct.pack("f", x))[0]


# ---- vectors and matrices (column-major, as three.js) -------------------
def vadd(a, b):
    return [x + y for x, y in zip(a, b)]


def vsub(a, b):
    return [x - y for x, y in zip(a, b)]


def vmul(a, s):
    return [x * s for x in a]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]


def length(a):
    return math.sqrt(dot(a, a))


def normalize(a):
    n = length(a)
    return [0.0 for _ in a] if n == 0 else vmul(a, 1 / n)


def reflect(i, n):
    return vsub(i, vmul(n, 2 * dot(n, i)))


def mix(a, b, t):
    return a * (1 - t) + b * t


def clamp(x, lo=0.0, hi=1.0):
    return min(max(x, lo), hi)


def smoothstep(lo, hi, x):
    t = clamp((x - lo) / (hi - lo))
    return t * t * (3 - 2 * t)


def luminance(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def mat_mul_vec4(m, v):
    return [sum(m[c * 4 + r] * v[c] for c in range(4)) for r in range(4)]


def transform_point(m, p):
    v = mat_mul_vec4(m, [p[0], p[1], p[2], 1.0])
    return [v[0] / v[3], v[1] / v[3], v[2] / v[3]]


def perspective(fov_deg, aspect, near, far):
    top = near * math.tan(math.radians(fov_deg) / 2)
    bottom, right, left = -top, top * aspect, -top * aspect
    m = [0.0] * 16
    m[0] = 2 * near / (right - left)
    m[5] = 2 * near / (top - bottom)
    m[8] = (right + left) / (right - left)
    m[9] = (top + bottom) / (top - bottom)
    m[10] = -(far + near) / (far - near)
    m[11] = -1.0
    m[14] = -2 * far * near / (far - near)
    return [f32(x) for x in m]


def invert_perspective(m):
    # The inverse of a symmetric perspective matrix.
    a, b, c, d = m[0], m[5], m[10], m[14]
    inv = [0.0] * 16
    inv[0] = 1 / a
    inv[5] = 1 / b
    inv[11] = 1 / d
    inv[14] = -1.0
    inv[15] = c / d
    return inv


def translation(x, y, z):
    m = [1.0 if i % 5 == 0 else 0.0 for i in range(16)]
    m[12], m[13], m[14] = x, y, z
    return m


IDENTITY = translation(0, 0, 0)
P = perspective(50, 1, 0.1, 20)
P_INV = invert_perspective(P)
SHIFT = f32(0.05)
PREV_WORLD = translation(SHIFT, 0, 0)
PREV_VIEW = translation(-SHIFT, 0, 0)
TAN_HALF = 1 / P[5]


def view_position(u, v_down, depth, inverse):
    return transform_point(inverse, [u * 2 - 1, (1 - v_down) * 2 - 1, depth * 2 - 1])


def inverse_view_normal(n, view):
    # normalize( vec4( n, 0 ) * view )
    return normalize(
        [
            n[0] * view[0] + n[1] * view[1] + n[2] * view[2],
            n[0] * view[4] + n[1] * view[5] + n[2] * view[6],
            n[0] * view[8] + n[1] * view[9] + n[2] * view[10],
        ]
    )


def screen_position(p, proj):
    c = transform_point(proj, p)
    return [c[0] * 0.5 + 0.5, 1 - (c[1] * 0.5 + 0.5)]


# ---- the synthetic frame ---------------------------------------------------
def build():
    depth, normals, signal, history, velocity, surfaces = [], [], [], [], [], []
    tan_half = math.tan(math.radians(25))
    for y in range(H):
        for x in range(W):
            i = y * W + x
            u = (x + 0.5) / W
            z = -3 / (1 + 0.2 * (2 * u - 1) * tan_half)
            ndc = (P[10] * z + P[14]) / (-z)
            depth.append(f32(ndc * 0.5 + 0.5))
            n = normalize([-0.2 - 0.002 * x, 0.0, 1.0])
            normals.append([f32(c) for c in n])
            ray = 0.5 + 0.25 * ((i * 7) % 4)
            if i == 15:
                ray = ENV
            signal.append(
                [
                    f32(0.2 + 0.05 * ((i * 3) % 7)),
                    f32(0.1 + 0.04 * ((i * 5) % 6)),
                    f32(0.3 + 0.03 * ((i * 2) % 5)),
                    f32(ray),
                ]
            )
            history.append(
                [
                    f32(0.25 + 0.04 * ((i * 5) % 7)),
                    f32(0.15 + 0.03 * ((i * 3) % 6)),
                    f32(0.28 + 0.02 * ((i * 4) % 5)),
                    f32(0.1 + 0.05 * ((i * 3) % 4)),
                ]
            )
            velocity.append([f32(0.01 + 0.004 * x), f32(-0.02 + 0.003 * y)])
            surfaces.append([1.0, f32(0.3 + 0.05 * (x % 3))])
    return depth, normals, signal, history, velocity, surfaces


DEPTH, NORMALS, SIGNAL, HISTORY, VELOCITY, SURFACES = build()


def slot(x, y):
    return clamp(y, 0, H - 1) * W + clamp(x, 0, W - 1)


def load(tex, x, y):
    return tex[int(slot(x, y))]


def tap(tex, px, py):
    px = clamp(px, 0, W - 1)
    py = clamp(py, 0, H - 1)
    x0, y0 = int(px), int(py)
    fx, fy = px - x0, py - y0
    x1, y1 = min(x0 + 1, W - 1), min(y0 + 1, H - 1)
    out = []
    for c in range(len(tex[0])):
        top = tex[y0 * W + x0][c] + (tex[y0 * W + x1][c] - tex[y0 * W + x0][c]) * fx
        bot = tex[y1 * W + x0][c] + (tex[y1 * W + x1][c] - tex[y1 * W + x0][c]) * fx
        out.append(top + (bot - top) * fy)
    return out


def sample(tex, u, v):
    return tap(tex, u * W - 0.5, v * H - 0.5)


# ---- TemporalReprojectNode --------------------------------------------------
def to_ycocg(c):
    return [
        0.25 * c[0] + 0.5 * c[1] + 0.25 * c[2],
        0.5 * c[0] - 0.5 * c[2],
        -0.25 * c[0] + 0.5 * c[1] - 0.25 * c[2],
    ]


def from_ycocg(c):
    return [c[0] + c[1] - c[2], c[0] + c[2], c[0] - c[1] - c[2]]


def dampen(rgb, flicker):
    scale = luminance(rgb) * flicker * 10 + 1
    return [c / scale for c in rgb]


def clip_to_aabb(history, lo, hi):
    p = [(a + b) * 0.5 for a, b in zip(hi, lo)]
    e = [(a - b) * 0.5 + 1e-7 for a, b in zip(hi, lo)]
    v = vsub(history, p)
    m = max(abs(a / b) for a, b in zip(v, e))
    return vadd(p, vmul(v, 1 / m)) if m > 1 else history


OFFSETS = [(-1, -1), (-1, 1), (1, -1), (1, 1), (1, 0), (0, -1), (0, 1), (-1, 0)]


def collect(x, y, input_color, flicker):
    center = to_ycocg(dampen(input_color[:3], flicker))
    m1 = list(center)
    m2 = [c * c for c in center]
    state = {"sum": 0.0, "count": 0.0, "mean": 0.0, "m2": 0.0}

    def accumulate(alpha):
        if alpha < ENV_T:
            state["sum"] += alpha
            state["count"] += 1
            delta = alpha - state["mean"]
            state["mean"] += delta / state["count"]
            state["m2"] += delta * (alpha - state["mean"])

    accumulate(input_color[3])
    for ox, oy in OFFSETS:
        n = [max(c, 0) for c in load(SIGNAL, x + ox, y + oy)]
        c = to_ycocg(dampen(n[:3], flicker))
        m1 = vadd(m1, c)
        m2 = vadd(m2, [a * a for a in c])
        accumulate(n[3])
    mean = vmul(m1, 1 / 9)
    std = [math.sqrt(max(a / 9 - b * b, 0)) for a, b in zip(m2, mean)]
    env_probability = 1 - state["count"] / 9
    ray = ENV if state["count"] < 0.5 else state["sum"] / max(state["count"], 1e-4)
    std_ray = max(math.sqrt(state["m2"] / max(state["count"], 1.0)), 1e-3)
    return mean, std, ray, env_probability, std_ray


def bilinear_tap(tx, ty, weight, world_position, world_normal):
    color = [max(c, 0) for c in load(HISTORY, tx, ty)]
    depth = load(DEPTH, tx, ty)
    # The port reads the clamped texel's own coordinate.
    u = (clamp(tx, 0, W - 1) + 0.5) / W
    v = (clamp(ty, 0, H - 1) + 0.5) / H
    seen = view_position(u, v, depth, P_INV)
    world = transform_point(PREV_WORLD, seen)
    normal = inverse_view_normal(load(NORMALS, tx, ty), PREV_VIEW)
    plane = abs(dot(vsub(world, world_position), world_normal)) / abs(seen[2])
    normal_confidence = smoothstep(0.95, 0.999, dot(normal, world_normal))
    confidence = (1 - smoothstep(0, 0.01, plane)) * normal_confidence
    w = weight * confidence
    return [c * w for c in color], w, confidence


def sample_history(u, v, world_position, world_normal, input_color):
    px, py = u * W - 0.5, v * H - 0.5
    ix, iy = math.floor(px), math.floor(py)
    fx, fy = px - ix, py - iy
    taps = [
        bilinear_tap(ix, iy, (1 - fx) * (1 - fy), world_position, world_normal),
        bilinear_tap(ix + 1, iy, fx * (1 - fy), world_position, world_normal),
        bilinear_tap(ix, iy + 1, (1 - fx) * fy, world_position, world_normal),
        bilinear_tap(ix + 1, iy + 1, fx * fy, world_position, world_normal),
    ]
    total = sum(t[1] for t in taps)
    best = max(t[2] for t in taps)
    worst = min(t[2] for t in taps)
    if total > 0.01:
        color = [sum(t[0][c] for t in taps) / total for c in range(4)]
    else:
        color = [input_color[0], input_color[1], input_color[2], 1.0]
    return color, best, worst


def history_uv(x, y):
    vel = load(VELOCITY, x, y)
    return [(x + 0.5) / W - vel[0] * 0.5, (y + 0.5) / H + vel[1] * 0.5]


def stretch_confidence(x, y):
    left, top = x - (x % 2), y - (y % 2)
    here, across = history_uv(left, y), history_uv(left + 1, y)
    above, below = history_uv(x, top), history_uv(x, top + 1)
    jx = [(across[0] - here[0]) * W, (across[1] - here[1]) * H]
    jy = [(below[0] - above[0]) * W, (below[1] - above[1]) * H]
    det = jx[0] * jy[1] - jx[1] * jy[0]
    fro2 = dot(jx, jx) + dot(jy, jy)
    disc = math.sqrt(max(fro2 * fro2 * 0.25 - det * det, 0))
    return clamp(math.sqrt(max(fro2 * 0.5 - disc, 0)))


def world_normal_at(x, y):
    return inverse_view_normal(load(NORMALS, x, y), IDENTITY)


def curvature(x, y):
    left, top = x - (x % 2), y - (y % 2)
    dx = vsub(world_normal_at(left + 1, y), world_normal_at(left, y))
    dy = vsub(world_normal_at(x, top + 1), world_normal_at(x, top))
    fwidth = [abs(a) + abs(b) for a, b in zip(dx, dy)]
    return clamp(length(fwidth) * 50)


def project_world_to_uv(world):
    seen = mat_mul_vec4(PREV_VIEW, world + [1.0])
    clip = mat_mul_vec4(P, seen)
    if abs(clip[3]) > 1e-5:
        return [clip[0] / clip[3] * 0.5 + 0.5, 1 - (clip[1] / clip[3] * 0.5 + 0.5)]
    return [-1.0, -1.0]


def in_unit(uv):
    return 0 <= uv[0] <= 1 and 0 <= uv[1] <= 1


def resolve(x, y, specular, hit_point=True, max_frames=32.0, clamp_intensity=1.0, flicker=1.0):
    depth = load(DEPTH, x, y)
    input_color = [max(c, 0) for c in load(SIGNAL, x, y)]
    view_normal = load(NORMALS, x, y)
    mean, std, ray, env_probability, std_ray = collect(x, y, input_color, flicker)
    world_normal = inverse_view_normal(view_normal, IDENTITY)
    u, v = (x + 0.5) / W, (y + 0.5) / H
    view_pos = view_position(u, v, depth, P_INV)
    world_position = transform_point(IDENTITY, view_pos)
    vel = load(VELOCITY, x, y)
    offset = [vel[0] * 0.5, vel[1] * -0.5]
    motion = clamp(math.hypot(offset[0] * W, offset[1] * H) / 128)
    h_uv = [u - offset[0], v - offset[1]]
    surf = sample_history(h_uv[0], h_uv[1], world_position, world_normal, input_color)
    history = list(surf[0])
    total_confidence = 1.0
    trust = 0.0
    if specular:
        camera_ray = normalize(vsub(world_position, [0.0, 0.0, 0.0]))
        hit_uv = project_world_to_uv(vadd(world_position, vmul(camera_ray, ray)))
        hit_valid = in_unit(hit_uv) and hit_point
        hit = sample_history(hit_uv[0], hit_uv[1], world_position, world_normal, input_color)
        hc_hit = [max(c, 0) for c in hit[0][:3]]
        hc_surf = [max(c, 0) for c in surf[0][:3]]
        conf_hit = hit[1] if hit_valid else 0.0
        conf_surf = surf[1] if in_unit(h_uv) else 0.0
        edge = 1 - min(std_ray * min(motion * 100, 1) * 3.5, 1)
        w_hit_raw = hit[2] * edge * (1 - curvature(x, y)) * conf_hit
        w_hit = w_hit_raw * (1 - env_probability**2)
        w_surf = (1 - w_hit) * conf_surf
        w_sum = max(w_hit + w_surf, EPS)
        rgb = [(a * w_hit + b * w_surf) / w_sum for a, b in zip(hc_hit, hc_surf)]
        history = rgb + [surf[0][3]]
        total_confidence = (conf_hit * w_hit + conf_surf * w_surf) / w_sum
        if length(rgb) < EPS:
            history = input_color[:3] + [1.0]
        trust = w_hit_raw
    a = max(history[3], EPS)
    stretch = stretch_confidence(x, y)
    total_confidence *= stretch**2
    gamma = mix(0.5, 1.0, (1 - motion) ** 2)
    lo = [m - s * gamma for m, s in zip(mean, std)]
    hi = [m + s * gamma for m, s in zip(mean, std)]
    scale = luminance(history[:3]) * flicker * 10 + 1
    clipped = vmul(from_ycocg(clip_to_aabb(to_ycocg([c / scale for c in history[:3]]), lo, hi)), scale)
    ci = clamp_intensity * max(min(motion * 10, 1), 0.25) * (1 + clamp((1 - stretch) + (1 - trust)))
    original = history[:3]
    mixed = [mix(o, c, ci) for o, c in zip(original, clipped)]
    total_confidence *= math.exp(-length(vsub(original, clipped)) * ci * 30)
    total_confidence *= mix(1.0, trust * 0.05 + 0.95, clamp(motion * 100))
    if total_confidence < EPS:
        mixed = input_color[:3]
    frames = min(1 / a * total_confidence + 1, max_frames)
    if specular and length(input_color[:3]) < EPS:
        frames = max(frames - 1, 1)
    return mixed + [1 / frames]


# ---- RecurrentDenoiseNode ----------------------------------------------------
def analytic_noise_r(px, py, index, seed):
    p = 1.32471795724474602596
    idx = index + seed
    ox = math.floor((f32(f32(idx) * f32(0.7548776662)) % 1.0) * 32)
    oy = math.floor((f32(f32(idx) * f32(0.5698402910)) % 1.0) * 32)
    cx = (px + ox) % 32
    cy = (py + oy) % 32
    t = f32(f32(f32(cx * f32(1 / p)) + f32(cy * f32(1 / p**2))) + seed)
    r = f32(f32(t * f32(p)) * f32(1 / p))
    return r - math.floor(r)


def vogel(i, radius):
    theta = (i + 0.5) * 2.399827721492203
    r = radius * math.sqrt((i + 0.5) / 8)
    return [math.cos(theta) * r, math.sin(theta) * r]


def hit_dist_factor(ray, view_z):
    return clamp(ray / max(2 * view_z * TAN_HALF, 1e-6))


def lobe_falloff(roughness, aggressivity, inv_normal_phi):
    percent = clamp(mix(inv_normal_phi**2, 0.0, math.sqrt(aggressivity)), 0.1, 0.99)
    alpha = roughness * roughness
    tan_half = alpha * math.sqrt(percent / max(1 - percent, 1e-6))
    half_angle = max(math.atan(tan_half), 1.5 / 255)
    return (1 / half_angle) ** 2 * 8


def denoise(x, y, texture, specular, frame_id=0, radius=5.0, luma_phi=5.0, depth_phi=5.0,
            normal_phi=5.0, alpha_phi=1.0, roughness_phi=100.0, adapt=0.5, strength=0.25,
            flicker=1.0, trust=0.0):
    u, v = (x + 0.5) / W, (y + 0.5) / H
    depth = DEPTH[min(int(v * H), H - 1) * W + min(int(u * W), W - 1)]
    view_normal = sample(NORMALS, u, v)
    world_normal = inverse_view_normal(view_normal, IDENTITY)
    texel = [max(c, 0) for c in sample(texture, u, v)]
    view_pos = view_position(u, v, depth, P_INV)
    metalness, roughness = sample(SURFACES, u, v)
    angle = analytic_noise_r(x, y, frame_id, 83) * 2 * math.pi
    c, s = math.cos(angle), math.sin(angle)
    frame_num = 1 / texel[3]
    variance = max(1 / frame_num ** (1 - strength), 0.05)
    aggressivity = 1 - variance
    raw = [max(a, 0) for a in sample(SIGNAL, u, v)]
    view_z = abs(view_pos[2])
    # getNeighborhoodStats, alphaSource 'raylength'
    rl_sum = rl_w = mean_luma = m2_luma = count = 0.0
    has_env = False
    for dx, dy in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)]:
        n = raw if (dx, dy) == (0, 0) else [max(a, 0) for a in sample(SIGNAL, u + dx / W, v + dy / H)]
        rl_n = n[3]
        if rl_n > ENV_T:
            rl_n = 0.25
            has_env = True
        w = 1 / (rl_n + 0.001)
        rl_sum += rl_n * w
        rl_w += w
        if trust > 0:
            luma = luminance(n)
            count += 1
            delta = luma - mean_luma
            mean_luma += delta / count
            m2_luma += delta * (luma - mean_luma)
    rl = rl_sum / rl_w
    std_luma = math.sqrt(m2_luma / max(count, 1))
    hdf = hit_dist_factor(rl, view_z)
    denoised = texel[:3]
    total = 1.0
    frame_sum, frame_weight = frame_num, 1.0
    raw_sum, raw_weight = raw[:3], 1.0
    if length(raw[:3]) < 0.0001:
        raw_sum, raw_weight = [0.0, 0.0, 0.0], 0.0
    world_radius = radius * 0.1
    if specular:
        world_radius *= rl * abs(view_pos[2])
        world_radius *= max(math.sqrt(roughness), 0.01)
        V = vmul(normalize(view_pos), -1)
        D = normalize([mix(a, b, 1 - roughness) for a, b in zip(view_normal, reflect(vmul(V, -1), view_normal))])
        R = reflect(vmul(D, -1), view_normal)
        Tv = normalize(cross(view_normal, R))
        Bv = cross(R, Tv)
        view_angle = clamp(math.acos(abs(view_normal[2])) / (math.pi * 0.5))
        T = vmul(Tv, mix(1.0, roughness, view_angle))
        B = Bv
    else:
        world_radius *= 1.0 * abs(view_pos[2])
        Tv = normalize(cross([0, 0, 1], view_normal))
        if length(Tv) < EPS:
            Tv = normalize(cross([0, 1, 0], view_normal))
        T = Tv
        B = normalize(cross(view_normal, Tv))
    world_radius *= mix(1, 0.001, aggressivity)
    T = vmul(T, world_radius)
    B = vmul(B, world_radius)
    shrink = 1.0
    bias = [0.0, 0.0]
    depth_scale = depth_phi * 500 * abs(view_normal[2]) / abs(view_pos[2])
    falloff = lobe_falloff(roughness, aggressivity, 1 - normal_phi)
    for i in range(8):
        base = vogel(i, 1)
        base_len = math.hypot(*base)
        direction = [base[0] / base_len, base[1] / base_len]
        skew = adapt * aggressivity if dot(bias, bias) > 0.001 else 0.0
        pulled = [max(bias[0], EPS), max(bias[1], EPS)]
        pl = math.hypot(*pulled)
        pulled = [pulled[0] / pl, pulled[1] / pl]
        skewed = [mix(a, b, skew) for a, b in zip(direction, pulled)]
        reach = [skewed[0] * base_len * shrink, skewed[1] * base_len * shrink]
        # mat2( cos, -sin, sin, cos ) * reach, column-major
        off = [c * reach[0] + s * reach[1], -s * reach[0] + c * reach[1]]
        sample_view = vadd(view_pos, vadd(vmul(B, off[0]), vmul(T, off[1])))
        suv = screen_position(sample_view, P)
        suv = [clamp(1 - abs(1 - abs(a))) for a in suv]
        neighbor = [max(a, 0) for a in sample(texture, suv[0], suv[1])]
        raw_n = [max(a, 0) for a in sample(SIGNAL, suv[0], suv[1])]
        n_depth = DEPTH[min(int(suv[1] * H), H - 1) * W + min(int(suv[0] * W), W - 1)]
        n_view = view_position(suv[0], suv[1], n_depth, P_INV)
        n_view_z = abs(n_view[2])
        diff = abs(luminance(raw_n) - luminance(raw)) * luma_phi * 10
        n_hdf = hit_dist_factor(raw_n[3], n_view_z)
        ray_factor = abs(hdf - n_hdf) * alpha_phi / abs(view_pos[2])
        diff += 1.0 if (raw_n[3] > ENV_T and has_env) else ray_factor
        if specular:
            diff += abs(roughness - sample(SURFACES, suv[0], suv[1])[1]) * roughness_phi
        n_world = inverse_view_normal(sample(NORMALS, suv[0], suv[1]), IDENTITY)
        plane = abs(dot(vsub(view_pos, n_view), view_normal))
        normal_w = math.exp((dot(world_normal, n_world) - 1) * falloff)
        w = math.exp(-(diff * aggressivity + plane * depth_scale)) * normal_w
        shrink = mix(shrink, w, adapt)
        bias = [mix(b, d * (w - 0.5), 0.5) for b, d in zip(bias, direction)]
        w *= mix(1 / (luminance(raw_n) ** 2 + 0.01), 1, min(frame_num / 5, 1))
        raw_sum = vadd(raw_sum, vmul(raw_n[:3], w))
        raw_weight += w
        denoised = vadd(denoised, vmul(neighbor[:3], w))
        total += w
        if neighbor[3] > texel[3]:
            share = w * 0.33
            frame_sum += 1 / neighbor[3] * share
            frame_weight += share
    denoised = [max(a / max(total, EPS), EPS) for a in denoised]
    raw_sum = vmul(raw_sum, 1 / max(raw_weight, EPS))
    a = 1 / max(frame_sum / max(frame_weight, EPS), EPS)
    cov = std_luma / max(mean_luma, 1e-4)
    suppress = clamp(cov * trust * (1 - a), 0, 0.9)
    a_trust = a * (1 - suppress)
    noisy = smoothstep(0.1, 2, cov)
    eff = flicker * mix(1 - trust, 1.0, noisy)
    w_hist = (1 - a_trust) / (luminance(denoised) * eff * 10 + 1)
    w_raw = a_trust / (luminance(raw_sum) * eff * 10 + 1)
    blended = [(d * w_hist + r * w_raw) / max(w_hist + w_raw, EPS) for d, r in zip(denoised, raw_sum)]
    return blended + [a]


def show(name, values):
    print(name, " ".join("%.7f" % v for v in values))


# ---- RNoise.js and SpecularHelpers.js -------------------------------------
def analytic_noise4(px, py, index, seed):
    """`bindAnalyticNoise`, with the shader's Float32 products."""
    p = 1.32471795724474602596
    idx = index + seed
    ox = math.floor((f32(f32(idx) * f32(0.7548776662)) % 1.0) * 32)
    oy = math.floor((f32(f32(idx) * f32(0.5698402910)) % 1.0) * 32)
    cx = (px + ox) % 32
    cy = (py + oy) % 32
    t = f32(f32(f32(cx * f32(1 / p)) + f32(cy * f32(1 / p**2))) + seed)
    factors = [
        (f32(p), f32(1 / p)),
        (f32(p * 2), f32(1 / p**2)),
        (f32(p * 3), f32(0.4198754210)),
        (f32(p * 4), f32(1 / p**3)),
    ]
    out = []
    for a, b in factors:
        r = f32(f32(t * a) * b)
        out.append(r - math.floor(r))
    return out


def sample_ggx_vndf(v, ax, ay, r1, r2):
    wi = normalize([ax * v[0], ay * v[1], v[2]])
    a = min(ax, ay)
    s = 1.0 + math.hypot(v[0], v[1])
    a2, s2 = a * a, s * s
    k = (1 - a2) * s2 / (s2 + a2 * v[2] * v[2])
    b = wi[2] * k
    phi = 6.283185307179586 * r1
    z = (1 - r2) * (1.0 + b) - b
    sin_theta = math.sqrt(max(0.0, 1.0 - z * z))
    c = [sin_theta * math.cos(phi), sin_theta * math.sin(phi), z]
    wm = vadd(c, wi)
    return normalize([ax * wm[0], ay * wm[1], max(0.0, wm[2])])


def d_gtr(roughness, noh, k):
    a2 = roughness * roughness
    return a2 / (math.pi * (noh * noh * (a2 - 1.0) + 1.0) ** k)


def smith_g(ndx, alpha):
    a2 = alpha * alpha
    return 2.0 * ndx / (ndx + math.sqrt(a2 + (1 - a2) * ndx * ndx))


def ggx_vndf_pdf(noh, nov, roughness):
    d = d_gtr(roughness, noh, 2.0)
    a2 = roughness * roughness
    sin_v2 = max(0.0, 1.0 - nov * nov)
    s = 1.0 + math.sqrt(sin_v2)
    s2 = s * s
    k = (1.0 - a2) * s2 / (s2 + a2 * nov * nov)
    t = math.sqrt(a2 * sin_v2 + nov * nov)
    return d / max(1e-6, 2.0 * (k * nov + t))


def specular_dominant_factor(nov, roughness):
    a = 0.298475 * math.log(39.4115 - 39.0029 * roughness)
    return clamp((1.0 - nov) ** 10.8649 * (1.0 - a) + a)


def ggx_reflection_sample(n, v, roughness, metalness, albedo, xi):
    a = max(roughness * roughness, 0.001)
    t = normalize(cross([0, 0, 1], n))
    if length(t) < 1e-3:
        t = normalize(cross([0, 1, 0], n))
    b = normalize(cross(n, t))
    v_local = [dot(t, v), dot(b, v), dot(n, v)]
    h_local = sample_ggx_vndf(v_local, a, a, xi[0], xi[1])
    h = normalize(vadd(vadd(vmul(t, h_local[0]), vmul(b, h_local[1])), vmul(n, h_local[2])))
    l = normalize(reflect(vmul(v, -1), h))
    half = normalize(vadd(v, l))
    nov = max(0.0, dot(n, v))
    nol = max(0.0, dot(n, l))
    noh = max(0.0, dot(n, half))
    voh = max(0.0, dot(v, half))
    f0 = [mix(0.04, c, metalness) for c in albedo]
    fresnel = [c + (1.0 - c) * (1.0 - voh) ** 5 for c in f0]
    pdf = ggx_vndf_pdf(noh, nov, a)
    a2 = a * a
    sin_v2 = max(1 - nov * nov, 0.0)
    s = 1.0 + math.sqrt(sin_v2)
    s2 = s * s
    k = (1 - a2) * s2 / (s2 + a2 * nov * nov)
    tb = math.sqrt(a2 * sin_v2 + nov * nov)
    g = smith_g(nov, a) * smith_g(nol, a)
    weight = [c * g * (k * nov + tb) / max(2.0 * nov, 1e-4) for c in fresnel]
    return l, weight, pdf, nov, a, f0


def screen_border_factor(u, v, border_width):
    border = max(border_width, 1e-4)
    edge = min(min(u, 1 - u), min(v, 1 - v))
    return smoothstep(0, 1, smoothstep(0, border, edge)) ** 0.125


def specular_dominant_direction(n, v, roughness):
    r = reflect(vmul(v, -1), n)
    return normalize([mix(a, b, 1 - roughness) for a, b in zip(n, r)])


def helpers():
    for args in [(0, 0, 1, 47), (5, 7, 3, 47), (40, 3, 1, 59), (0, 0, 0, 83)]:
        show("noise %d %d %d %d" % args, analytic_noise4(*args))
    for nov, rough in [(0.5, 0.3), (1, 1), (0, 0)]:
        show("dominant factor %g %g" % (nov, rough), [specular_dominant_factor(nov, rough)])
    show("vndf", sample_ggx_vndf(normalize([0.3, 0.2, 0.9]), 0.25, 0.25, 0.3, 0.6))
    show("pdf", [ggx_vndf_pdf(0.9, 0.7, 0.25)])
    n1 = normalize([0.1, 0.3, 0.9])
    v1 = normalize([-0.2, 0.4, 0.8])
    cases = [
        ("tilted", n1, 0.5, 0.7, [0.9, 0.5, 0.2], [0.3, 0.6]),
        ("facing", [0, 0, 1], 0.5, 0.0, [1, 1, 1], [0.3, 0.6]),
        ("mirror", n1, 0.0, 1.0, [1, 1, 1], [0.8, 0.1]),
    ]
    for name, n, rough, metal, albedo, xi in cases:
        l, weight, pdf, nov, alpha, f0 = ggx_reflection_sample(n, v1, rough, metal, albedo, xi)
        show("ggx %s dir" % name, l)
        show("ggx %s weight" % name, weight)
        show("ggx %s pdf nov alpha" % name, [pdf, nov, alpha])
        show("ggx %s f0" % name, f0)
    for u, v, width in [(0.5, 0.5, 0.2), (0.05, 0.5, 0.2), (0.5, 0.98, 0.2), (0.3, 0.3, 0), (0, 0.3, 0.2)]:
        show("border %g %g %g" % (u, v, width), [screen_border_factor(u, v, width)])
    show("dominant direction", specular_dominant_direction(n1, v1, 0.25))


if __name__ == "__main__":
    helpers()
    for (x, y) in [(2, 3), (3, 2), (4, 1), (0, 5)]:
        show("resolve diffuse %d %d" % (x, y), resolve(x, y, False))
        show("resolve specular %d %d" % (x, y), resolve(x, y, True))
        show("resolve specular nohit %d %d" % (x, y), resolve(x, y, True, hit_point=False))
        show("stats %d %d" % (x, y), list(collect(x, y, [max(c, 0) for c in load(SIGNAL, x, y)], 1.0)[2:]))
        show("curvature %d %d" % (x, y), [curvature(x, y)])
    for (x, y) in [(2, 3), (3, 2), (4, 1)]:
        show("denoise diffuse %d %d" % (x, y), denoise(x, y, HISTORY, False, radius=12))
        show("denoise specular %d %d" % (x, y), denoise(x, y, HISTORY, True, radius=12))
        show("denoise specular trust %d %d" % (x, y), denoise(x, y, HISTORY, True, radius=12, trust=0.5, frame_id=3))
