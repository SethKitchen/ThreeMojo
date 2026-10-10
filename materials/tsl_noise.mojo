# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""TSL's noises that are not MaterialX's: `triNoise3D`, the simplex and
curl noise, the Voronoi noise, and the analytic noise of `RNoise`.

three.js: `src/nodes/math/TriNoise3D.js`,
`examples/jsm/tsl/math/curlNoise.js`,
`examples/jsm/tsl/math/voronoiNoise.js` and
`examples/jsm/tsl/utils/RNoise.js`. `materials.tsl_bits` has `hash`.

Each function builds the nodes of three.js's function, in three.js's
order of operations, from the nodes `NodeGraph` already has. A TSL `Loop`
with a fixed count is a loop in Mojo here that builds each time through,
so it needs no `Loop` block. None adds an instruction to the bytecode, so
the CPU and the GPU run it with the one interpreter.

`assets/tsl/tsl_reference.py` transcribes the functions in 32-bit floats
and gives the values the tests check.
"""

from materials.tsl_check import _expect
from materials.nodes import (
    NODE_FLOAT,
    NODE_VEC2,
    NODE_VEC3,
    NODE_VEC4,
    NodeGraph,
    NodeRef,
    ValueType,
)
from std.math import pi


# --- triNoise3D ---------------------------------------------------------------


def _tri(mut g: NodeGraph, x: NodeRef) raises -> NodeRef:
    """Return three.js's `tri`: `abs(fract(x) - 0.5)`, per component."""
    return g.abs(g.sub(g.fract(x), g.float(0.5)))


def _tri3(mut g: NodeGraph, p: NodeRef) raises -> NodeRef:
    """Return three.js's `tri3`: `vec3(tri(p.z + tri(p.y)),
    tri(p.z + tri(p.x)), tri(p.y + tri(p.x)))`, as one vector."""
    return _tri(g, g.add(g.swizzle(p, "zzy"), _tri(g, g.swizzle(p, "yxx"))))


def tri_noise_3d(
    mut g: NodeGraph, position: NodeRef, speed: NodeRef, time: NodeRef
) raises -> NodeRef:
    """Return three.js's `triNoise3D`: four octaves of triangle waves, each
    warped by the last, a `float` from zero to about 0.5.

    The loop runs from zero to three inclusive, four times. Each time
    through: `p += tri3(bp * 2) + time * (0.1 * speed)`, `bp *= 1.8`,
    `z *= 1.5`, `p *= 1.2`, `rz += tri(p.z + tri(p.x + tri(p.y))) / z`
    and `bp += 0.14`. `z` starts at 1.4.

    Args:
        g: The graph to build the nodes in.
        position: A `vec3`.
        speed: A `float`.
        time: A `float`.

    Returns:
        A `float`.

    Raises:
        Error: If `position` is not a `vec3`, or `speed` or `time` is not a
            `float`, of this graph.
    """
    _expect(g, position, NODE_VEC3, "triNoise3D's position")
    _expect(g, speed, NODE_FLOAT, "triNoise3D's speed")
    _expect(g, time, NODE_FLOAT, "triNoise3D's time")
    var p = position
    var bp = position
    var z = Float32(1.4)
    var rz = g.float(0)
    var drift = g.mul(time, g.mul(g.float(0.1), speed))
    for _ in range(4):  # pragma: no branch
        var dg = _tri3(g, g.mul(bp, g.float(2)))
        p = g.add(p, g.add(dg, drift))
        bp = g.mul(bp, g.float(1.8))
        z *= 1.5
        p = g.mul(p, g.float(1.2))
        var inner = _tri(g, g.swizzle(p, "y"))
        var middle = _tri(g, g.add(g.swizzle(p, "x"), inner))
        var t = _tri(g, g.add(g.swizzle(p, "z"), middle))
        rz = g.add(rz, g.div(t, g.float(z)))
        bp = g.add(bp, g.float(0.14))
    return rz


# --- simplex and curl noise ---------------------------------------------------


def permute(mut g: NodeGraph, x: NodeRef) raises -> NodeRef:
    """Return three.js's `permute`: `mod(x * x * 34 + x, 289)`.

    Args:
        g: The graph to build the nodes in.
        x: A `vec4`.

    Returns:
        A `vec4`.

    Raises:
        Error: If `x` is not a `vec4` of this graph.
    """
    _expect(g, x, NODE_VEC4, "permute")
    return g.mod(g.add(g.mul(g.mul(x, x), g.float(34)), x), g.float(289))


def _corner(
    mut g: NodeGraph, lane: String, i1: NodeRef, i2: NodeRef
) raises -> NodeRef:
    """Return `vec4(0, i1.lane, i2.lane, 1)`, the four corners' offsets
    along one axis."""
    return g.join(
        [g.float(0), g.swizzle(i1, lane), g.swizzle(i2, lane), g.float(1)]
    )


def _lanes(mut g: NodeGraph, a: NodeRef, b: NodeRef) raises -> NodeRef:
    """Return `vec4(a.xy, b.xy)`."""
    return g.join([g.swizzle(a, "xy"), g.swizzle(b, "xy")])


def snoise(mut g: NodeGraph, v: NodeRef) raises -> NodeRef:
    """Return three.js's `snoise`: 3D simplex noise, remapped to about zero
    to one as `0.5 + 12 * dot(m * m * m, gradients)`.

    Args:
        g: The graph to build the nodes in.
        v: A `vec3`.

    Returns:
        A `float`.

    Raises:
        Error: If `v` is not a `vec3` of this graph.
    """
    _expect(g, v, NODE_VEC3, "snoise")
    var c = g.vec2(Float32(1.0) / 6, Float32(1.0) / 3)
    var i = g.floor(g.add(v, g.dot(v, g.swizzle(c, "yyy"))))
    var x0 = g.add(g.sub(v, i), g.dot(i, g.swizzle(c, "xxx")))
    var step = g.step(g.swizzle(x0, "yzx"), g.swizzle(x0, "xyz"))
    var l = g.sub(g.float(1), step)
    var i1 = g.min(g.swizzle(step, "xyz"), g.swizzle(l, "zxy"))
    var i2 = g.max(g.swizzle(step, "xyz"), g.swizzle(l, "zxy"))
    var x1 = g.add(g.sub(x0, i1), g.swizzle(c, "x"))
    var x2 = g.add(g.sub(x0, i2), g.swizzle(c, "y"))
    var x3 = g.sub(x0, g.vec3(0.5, 0.5, 0.5))
    i = g.mod(i, g.float(289))
    var p = permute(g, g.add(g.swizzle(i, "z"), _corner(g, "z", i1, i2)))
    p = permute(
        g,
        g.add(g.add(p, g.swizzle(i, "y")), _corner(g, "y", i1, i2)),
    )
    p = permute(
        g,
        g.add(g.add(p, g.swizzle(i, "x")), _corner(g, "x", i1, i2)),
    )
    # `ns = 0.142857142857 * D.wyz - D.xzx`, `D = vec4(0, 0.5, 1, 2)`.
    var ns = g.sub(
        g.mul(g.float(0.142857142857), g.vec3(2, 0.5, 1)), g.vec3(0, 1, 0)
    )
    var ns_z = g.swizzle(ns, "z")
    var ns_x = g.swizzle(ns, "x")
    var ns_yyyy = g.swizzle(ns, "yyyy")
    var j = g.sub(p, g.mul(g.float(49), g.floor(g.mul(g.mul(p, ns_z), ns_z))))
    var x_ = g.floor(g.mul(j, ns_z))
    var x = g.add(g.mul(x_, ns_x), ns_yyyy)
    var y = g.add(
        g.mul(g.floor(g.sub(j, g.mul(g.float(7), x_))), ns_x), ns_yyyy
    )
    var h = g.sub(g.sub(g.float(1), g.abs(x)), g.abs(y))
    var b0 = _lanes(g, x, y)
    var b1 = g.join([g.swizzle(x, "zw"), g.swizzle(y, "zw")])
    var sh = g.negate(g.step(h, g.vec4(0, 0, 0, 0)))
    var a0 = g.add(
        g.swizzle(b0, "xzyw"),
        g.mul(
            g.swizzle(
                g.add(g.mul(g.floor(b0), g.float(2)), g.float(1)), "xzyw"
            ),
            g.swizzle(sh, "xxyy"),
        ),
    )
    var a1 = g.add(
        g.swizzle(b1, "xzyw"),
        g.mul(
            g.swizzle(
                g.add(g.mul(g.floor(b1), g.float(2)), g.float(1)), "xzyw"
            ),
            g.swizzle(sh, "zzww"),
        ),
    )
    var p0 = g.join([g.swizzle(a0, "xy"), g.swizzle(h, "x")])
    var p1 = g.join([g.swizzle(a0, "zw"), g.swizzle(h, "y")])
    var p2 = g.join([g.swizzle(a1, "xy"), g.swizzle(h, "z")])
    var p3 = g.join([g.swizzle(a1, "zw"), g.swizzle(h, "w")])
    var norm = g.inverse_sqrt(
        g.join([g.dot(p0, p0), g.dot(p1, p1), g.dot(p2, p2), g.dot(p3, p3)])
    )
    p0 = g.mul(p0, g.swizzle(norm, "x"))
    p1 = g.mul(p1, g.swizzle(norm, "y"))
    p2 = g.mul(p2, g.swizzle(norm, "z"))
    p3 = g.mul(p3, g.swizzle(norm, "w"))
    var m = g.max(
        g.sub(
            g.float(0.6),
            g.join(
                [g.dot(x0, x0), g.dot(x1, x1), g.dot(x2, x2), g.dot(x3, x3)]
            ),
        ),
        g.float(0),
    )
    var grades = g.join(
        [g.dot(p0, x0), g.dot(p1, x1), g.dot(p2, x2), g.dot(p3, x3)]
    )
    return g.add(
        g.float(0.5),
        g.mul(g.float(12), g.dot(g.mul(g.mul(m, m), m), grades)),
    )


def snoise_vec3(mut g: NodeGraph, x: NodeRef) raises -> NodeRef:
    """Return three.js's `snoiseVec3`: three simplex noises of moved points.

    As three.js writes it, the first component is `snoise(x * 2 - 1)` and
    the second is `snoise(x.yzx + (-19.1, 33.4, 47.2)) * 2 - 1`. The third
    is `snoise((x.zxy + (74.2, -124.5, 99.4)) * 2 - 1)`.

    Args:
        g: The graph to build the nodes in.
        x: A `vec3`.

    Returns:
        A `vec3`.

    Raises:
        Error: If `x` is not a `vec3` of this graph.
    """
    _expect(g, x, NODE_VEC3, "snoiseVec3")
    var two = g.float(2)
    var one = g.float(1)
    var first = snoise(g, g.sub(g.mul(x, two), one))
    var second = g.sub(
        g.mul(
            snoise(g, g.add(g.swizzle(x, "yzx"), g.vec3(-19.1, 33.4, 47.2))),
            two,
        ),
        one,
    )
    var moved = g.add(g.swizzle(x, "zxy"), g.vec3(74.2, -124.5, 99.4))
    var third = snoise(g, g.sub(g.mul(moved, two), one))
    return g.join([first, second, third])


def curl_noise(mut g: NodeGraph, p: NodeRef) raises -> NodeRef:
    """Return three.js's `curlNoise`: the curl of `snoise_vec3`, by central
    differences 0.1 apart.

    Args:
        g: The graph to build the nodes in.
        p: A `vec3`.

    Returns:
        A `vec3`.

    Raises:
        Error: If `p` is not a `vec3` of this graph.
    """
    _expect(g, p, NODE_VEC3, "curlNoise")
    var e = Float32(0.1)
    var dx = g.vec3(e, 0, 0)
    var dy = g.vec3(0, e, 0)
    var dz = g.vec3(0, 0, e)
    var p_x0 = snoise_vec3(g, g.sub(p, dx))
    var p_x1 = snoise_vec3(g, g.add(p, dx))
    var p_y0 = snoise_vec3(g, g.sub(p, dy))
    var p_y1 = snoise_vec3(g, g.add(p, dy))
    var p_z0 = snoise_vec3(g, g.sub(p, dz))
    var p_z1 = snoise_vec3(g, g.add(p, dz))
    var x = g.add(
        g.sub(
            g.sub(g.swizzle(p_y1, "z"), g.swizzle(p_y0, "z")),
            g.swizzle(p_z1, "y"),
        ),
        g.swizzle(p_z0, "y"),
    )
    var y = g.add(
        g.sub(
            g.sub(g.swizzle(p_z1, "x"), g.swizzle(p_z0, "x")),
            g.swizzle(p_x1, "z"),
        ),
        g.swizzle(p_x0, "z"),
    )
    var z = g.add(
        g.sub(
            g.sub(g.swizzle(p_x1, "y"), g.swizzle(p_x0, "y")),
            g.swizzle(p_y1, "x"),
        ),
        g.swizzle(p_y0, "x"),
    )
    var divisor = g.div(g.float(1), g.mul(g.float(2), g.float(e)))
    return g.mul(g.join([x, y, z]), divisor)


# --- Voronoi noise ------------------------------------------------------------


def hash2d(mut g: NodeGraph, p: NodeRef) raises -> NodeRef:
    """Return three.js's `hash2d` of `voronoiNoise.js`:
    `fract(sin(vec2(dot(p, (127.1, 311.7)), dot(p, (269.5, 183.3)))) *
    18.5453)`.

    Args:
        g: The graph to build the nodes in.
        p: A `vec2`.

    Returns:
        A `vec2` from zero to one.

    Raises:
        Error: If `p` is not a `vec2` of this graph.
    """
    _expect(g, p, NODE_VEC2, "hash2d")
    var dots = g.join(
        [g.dot(p, g.vec2(127.1, 311.7)), g.dot(p, g.vec2(269.5, 183.3))]
    )
    return g.fract(g.mul(g.sin(dots), g.float(18.5453)))


def hash3d(mut g: NodeGraph, p: NodeRef) raises -> NodeRef:
    """Return three.js's `hash3d` of `voronoiNoise.js`: three dots of `p`,
    their sines times 18.5453, and the fractions.

    Args:
        g: The graph to build the nodes in.
        p: A `vec3`.

    Returns:
        A `vec3` from zero to one.

    Raises:
        Error: If `p` is not a `vec3` of this graph.
    """
    _expect(g, p, NODE_VEC3, "hash3d")
    var dots = g.join(
        [
            g.dot(p, g.vec3(127.1, 311.7, 74.7)),
            g.dot(p, g.vec3(269.5, 183.3, 246.1)),
            g.dot(p, g.vec3(113.5, 271.9, 124.6)),
        ]
    )
    return g.fract(g.mul(g.sin(dots), g.float(18.5453)))


def _jittered(
    mut g: NodeGraph, cell: NodeRef, f: NodeRef, o: NodeRef, time: NodeRef
) raises -> NodeRef:
    """Return `g - f + sin(time + o * 2 PI) * 0.5 + 0.5`, one cell's point
    from the fragment."""
    var wave = g.sin(g.add(time, g.mul(o, g.float(Float32(pi * 2)))))
    return g.add(g.sub(cell, f), g.add(g.mul(wave, g.float(0.5)), g.float(0.5)))


def voronoi2d(mut g: NodeGraph, p: NodeRef, time: NodeRef) raises -> NodeRef:
    """Return three.js's `voronoi2d`: the squared distance to the nearest of
    the points that move in the nine cells around `p`.

    Args:
        g: The graph to build the nodes in.
        p: A `vec2`.
        time: A `float` that moves the points.

    Returns:
        A `float`, at most eight.

    Raises:
        Error: If `p` is not a `vec2`, or `time` is not a `float`, of this
            graph.
    """
    _expect(g, p, NODE_VEC2, "voronoi2d")
    _expect(g, time, NODE_FLOAT, "voronoi2d's time")
    var n = g.floor(p)
    var f = g.fract(p)
    var nearest = g.float(8)
    for x in range(-1, 2):  # pragma: no branch
        for y in range(-1, 2):  # pragma: no branch
            var cell = g.vec2(Float32(x), Float32(y))
            var o = hash2d(g, g.add(n, cell))
            var r = _jittered(g, cell, f, o, time)
            nearest = g.min(nearest, g.dot(r, r))
    return nearest


def _voronoi3d_row(
    mut g: NodeGraph,
    x: Int,
    n: NodeRef,
    f: NodeRef,
    time: NodeRef,
    nearest: NodeRef,
) raises -> NodeRef:
    """Return the nearest squared distance after the nine cells of one `x`.
    Two loops a function keep the compiler from hanging."""
    var found = nearest
    for y in range(-1, 2):  # pragma: no branch
        for z in range(-1, 2):  # pragma: no branch
            var cell = g.vec3(Float32(x), Float32(y), Float32(z))
            var o = hash3d(g, g.add(n, cell))
            var r = _jittered(g, cell, f, o, time)
            found = g.min(found, g.dot(r, r))
    return found


def voronoi3d(mut g: NodeGraph, p: NodeRef, time: NodeRef) raises -> NodeRef:
    """Return three.js's `voronoi3d`: the squared distance to the nearest of
    the points that move in the 27 cells around `p`.

    Args:
        g: The graph to build the nodes in.
        p: A `vec3`.
        time: A `float` that moves the points.

    Returns:
        A `float`, at most eight.

    Raises:
        Error: If `p` is not a `vec3`, or `time` is not a `float`, of this
            graph.
    """
    _expect(g, p, NODE_VEC3, "voronoi3d")
    _expect(g, time, NODE_FLOAT, "voronoi3d's time")
    var n = g.floor(p)
    var f = g.fract(p)
    var nearest = g.float(8)
    for x in range(-1, 2):  # pragma: no branch
        nearest = _voronoi3d_row(g, x, n, f, time, nearest)
    return nearest


# --- RNoise -------------------------------------------------------------------

# The plastic number, the ratio of `RNoise`'s low-discrepancy sequence.
comptime _PLASTIC = Float64(1.32471795724474602596)


def _sequence(
    mut g: NodeGraph, t: NodeRef, times: Float64, scale: Float64
) raises -> NodeRef:
    """Return `fract(t * times * scale)`, two products as three.js writes
    them, of the constants rounded to floats."""
    var moved = g.mul(
        g.mul(t, g.float(Float32(times))), g.float(Float32(scale))
    )
    return g.fract(moved)


def analytic_noise(
    mut g: NodeGraph,
    uv: NodeRef,
    sample_index: NodeRef,
    resolution: NodeRef,
    seed: Int = 0,
) raises -> NodeRef:
    """Return four numbers from zero to one of a low-discrepancy sequence
    that tiles the screen every 32 pixels, the function that three.js's
    `bindAnalyticNoise( resolution, seed )` returns.

    The pixel is `floor(uv * resolution)`. The sample moves it by
    `floor(fract(vec2(i * 0.7548776662, i * 0.5698402910)) * 32)`, where
    `i = int(sample_index) + seed`. Then `t = c.x / P + c.y / P ** 2 + seed`
    for the pixel `c` modulo 32, and `P` the plastic number. The four
    numbers are the fractions of `t * P / P`, `t * 2P / P ** 2`,
    `t * 3P * 0.4198754210` and `t * 4P / P ** 3`.

    Args:
        g: The graph to build the nodes in.
        uv: A `vec2`, the place on the screen from zero to one.
        sample_index: A `float`, which sample.
        resolution: A `vec2`, the screen's size in pixels.
        seed: A whole number that moves the sequence.

    Returns:
        A `vec4`.

    Raises:
        Error: If `uv` or `resolution` is not a `vec2`, or `sample_index`
            is not a `float`, of this graph.
    """
    _expect(g, uv, NODE_VEC2, "RNoise's uv")
    _expect(g, sample_index, NODE_FLOAT, "RNoise's sample index")
    _expect(g, resolution, NODE_VEC2, "RNoise's resolution")
    var index = g.add(g.integer(sample_index), g.float(Float32(seed)))
    var tile = g.float(32)
    var pixel = g.floor(g.mul(uv, resolution))
    var offset = g.floor(
        g.mul(
            g.fract(
                g.join(
                    [
                        g.mul(index, g.float(0.7548776662)),
                        g.mul(index, g.float(0.5698402910)),
                    ]
                )
            ),
            tile,
        )
    )
    var coords = g.mod(g.add(pixel, offset), tile)
    var t = g.add(
        g.add(
            g.mul(g.swizzle(coords, "x"), g.float(Float32(1 / _PLASTIC))),
            g.mul(
                g.swizzle(coords, "y"),
                g.float(Float32(1 / (_PLASTIC * _PLASTIC))),
            ),
        ),
        g.float(Float32(seed)),
    )
    var squared = _PLASTIC * _PLASTIC
    return g.join(
        [
            _sequence(g, t, _PLASTIC, 1 / _PLASTIC),
            _sequence(g, t, _PLASTIC * 2, 1 / squared),
            _sequence(g, t, _PLASTIC * 3, 0.4198754210),
            _sequence(g, t, _PLASTIC * 4, 1 / (squared * _PLASTIC)),
        ]
    )
