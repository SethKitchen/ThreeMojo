# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `materials.tsl_noise`: `triNoise3D`, the simplex and curl
noise, the Voronoi noise and `RNoise`.

`assets/tsl/tsl_reference.py` transcribes three.js's functions in 32-bit
floats and gives each expected value. Each test point is one where a small
change of the point makes a small change of the value, so no `floor`
sits on an edge.
"""

from materials.nodes import (
    FRAGMENT_NODE,
    NODE_FLOAT,
    NODE_VEC2,
    NODE_VEC3,
    NodeGraph,
    NodeInputs,
    NodeRef,
    ProgramSource,
    run_nodes,
)
from materials.tsl_noise import (
    analytic_noise,
    curl_noise,
    hash2d,
    hash3d,
    permute,
    snoise,
    snoise_vec3,
    tri_noise_3d,
    voronoi2d,
    voronoi3d,
)
from math.vector3 import Vector3
from std.testing import TestSuite, assert_almost_equal, assert_raises

comptime Lanes = SIMD[DType.float32, 4]


def value_of(mut g: NodeGraph, node: NodeRef) raises -> Lanes:
    """Return a node's value, padded to a `vec4`, through the fragment
    output."""
    var type = g.type_of(node)
    var shown = node
    if type == NODE_FLOAT:
        shown = g.join([node, g.vec3(0, 0, 0)])
    elif type == NODE_VEC2:
        shown = g.join([node, g.vec2(0, 0)])
    elif type == NODE_VEC3:
        shown = g.join([node, g.float(0)])
    g.set_output(FRAGMENT_NODE, shown)
    var program = g.compile()
    var none = Vector3(0, 0, 0)
    return run_nodes(
        ProgramSource(Pointer(to=program)),
        FRAGMENT_NODE,
        NodeInputs(0, 0, none, none, none, none, False),
    )


def assert_near(got: Lanes, expected: List[Float32], tolerance: Float64) raises:
    """Assert as many lanes as `expected` has."""
    for index in range(len(expected)):
        assert_almost_equal(got[index], expected[index], atol=tolerance)


def test_tri_noise_3d_is_three_js_numbers() raises:
    var g = NodeGraph()
    var near = tri_noise_3d(g, g.vec3(0.3, 0.7, 1.1), g.float(1), g.float(0.5))
    assert_near(value_of(g, near), [0.402042955160141], 1e-5)
    var far = tri_noise_3d(g, g.vec3(2.5, -1.25, 0.4), g.float(0.3), g.float(3))
    assert_near(value_of(g, far), [0.06113876402378082], 1e-5)
    with assert_raises(contains="position reads a vec3, not a vec2"):
        _ = tri_noise_3d(g, g.vec2(1, 2), g.float(1), g.float(0))
    with assert_raises(contains="speed reads a float, not a vec2"):
        _ = tri_noise_3d(g, g.vec3(1, 2, 3), g.vec2(1, 2), g.float(0))
    with assert_raises(contains="time reads a float, not a vec2"):
        _ = tri_noise_3d(g, g.vec3(1, 2, 3), g.float(1), g.vec2(1, 2))


def test_simplex_noise_is_three_js_numbers() raises:
    var g = NodeGraph()
    assert_near(
        value_of(g, snoise(g, g.vec3(2.5, -1.25, 0.4))),
        [0.3145197629928589],
        1e-4,
    )
    assert_near(
        value_of(g, snoise(g, g.vec3(-3.7, 5.2, 0.05))),
        [0.5830848217010498],
        1e-4,
    )
    assert_near(
        value_of(g, snoise_vec3(g, g.vec3(2.5, -1.25, 0.4))),
        [0.27860206365585327, -0.5938605666160583, 0.792390763759613],
        1e-4,
    )
    assert_near(
        value_of(g, snoise_vec3(g, g.vec3(-3.7, 5.2, 0.05))),
        [0.426505446434021, -0.26778411865234375, 0.6214171648025513],
        1e-4,
    )
    # `mod(x * x * 34 + x, 289)`.
    assert_near(
        value_of(g, permute(g, g.vec4(0, 1, 10, 288))),
        [0, 35, 231, 33],
        1e-4,
    )
    with assert_raises(contains="permute reads a vec4, not a vec3"):
        _ = permute(g, g.vec3(1, 2, 3))
    with assert_raises(contains="snoise reads a vec3, not a vec2"):
        _ = snoise(g, g.vec2(1, 2))
    with assert_raises(contains="snoiseVec3 reads a vec3, not a float"):
        _ = snoise_vec3(g, g.float(1))


def test_curl_noise_is_three_js_numbers() raises:
    var g = NodeGraph()
    assert_near(
        value_of(g, curl_noise(g, g.vec3(2.5, -1.25, 0.4))),
        [-4.0702667236328125, 1.4919123649597168, 1.5741939544677734],
        1e-3,
    )
    var other = NodeGraph()
    assert_near(
        value_of(other, curl_noise(other, other.vec3(-3.7, 5.2, 0.05))),
        [-1.1120107173919678, 4.447781562805176, 2.1441240310668945],
        1e-3,
    )
    with assert_raises(contains="curlNoise reads a vec3, not a vec4"):
        _ = curl_noise(g, g.vec4(1, 2, 3, 4))


def test_voronoi_noise_is_three_js_numbers() raises:
    var g = NodeGraph()
    assert_near(
        value_of(g, hash2d(g, g.vec2(0.3, 0.7))),
        [0.1779956817626953, 0.9955635070800781],
        1e-4,
    )
    assert_near(
        value_of(g, voronoi2d(g, g.vec2(0.3, 0.7), g.float(0))),
        [0.07999999076128006],
        1e-4,
    )
    assert_near(
        value_of(g, voronoi2d(g, g.vec2(2.5, -1.25), g.float(1.5))),
        [0.312418133020401],
        1e-4,
    )
    assert_near(
        value_of(g, hash3d(g, g.vec3(0.3, 0.7, 1.1))),
        [0.6703910827636719, 0.22127437591552734, 0.10313200950622559],
        1e-4,
    )
    assert_near(
        value_of(g, voronoi3d(g, g.vec3(0.3, 0.7, 1.1), g.float(0))),
        [0.23083476722240448],
        1e-4,
    )
    assert_near(
        value_of(g, voronoi3d(g, g.vec3(2.5, -1.25, 0.4), g.float(1.5))),
        [0.5298106074333191],
        1e-4,
    )
    with assert_raises(contains="hash2d reads a vec2, not a vec3"):
        _ = hash2d(g, g.vec3(1, 2, 3))
    with assert_raises(contains="hash3d reads a vec3, not a vec2"):
        _ = hash3d(g, g.vec2(1, 2))
    with assert_raises(contains="voronoi2d reads a vec2, not a vec3"):
        _ = voronoi2d(g, g.vec3(1, 2, 3), g.float(0))
    with assert_raises(contains="voronoi2d's time reads a float, not a vec2"):
        _ = voronoi2d(g, g.vec2(1, 2), g.vec2(1, 2))
    with assert_raises(contains="voronoi3d reads a vec3, not a vec2"):
        _ = voronoi3d(g, g.vec2(1, 2), g.float(0))
    with assert_raises(contains="voronoi3d's time reads a float, not a vec2"):
        _ = voronoi3d(g, g.vec3(1, 2, 3), g.vec2(1, 2))


def test_analytic_noise_is_three_js_numbers() raises:
    var g = NodeGraph()
    assert_near(
        value_of(
            g,
            analytic_noise(g, g.vec2(0.25, 0.75), g.float(0), g.vec2(64, 32)),
        ),
        [
            0.7542152404785156,
            0.8825645446777344,
            0.9747505187988281,
            0.703155517578125,
        ],
        1e-5,
    )
    assert_near(
        value_of(
            g,
            analytic_noise(
                g, g.vec2(0.6, 0.1), g.float(3.7), g.vec2(800, 600), seed=2
            ),
        ),
        [
            0.22339630126953125,
            0.15919876098632812,
            0.43819427490234375,
            0.728118896484375,
        ],
        1e-5,
    )
    with assert_raises(contains="RNoise's uv reads a vec2, not a float"):
        _ = analytic_noise(g, g.float(0), g.float(0), g.vec2(1, 1))
    with assert_raises(contains="sample index reads a float, not a vec2"):
        _ = analytic_noise(g, g.vec2(0, 0), g.vec2(0, 0), g.vec2(1, 1))
    with assert_raises(contains="resolution reads a vec2, not a float"):
        _ = analytic_noise(g, g.vec2(0, 0), g.float(0), g.float(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
