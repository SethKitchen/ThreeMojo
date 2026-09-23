# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.curve_modifier`.

The half floats and the spine texture are what three.js 0.180's
`DataUtils` and `Flow` give under node. The bent vertices are what the
reference gets by running `Flow`'s vertex shader on its texture, in
floats, with `Math.fround` after every step."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from geometries.curve_modifier import (
    Flow,
    InstancedFlow,
    TEXTURE_WIDTH,
    to_half_float,
)
from math.curve_extras import helix_curve, torus_knot
from math.matrix4 import translation
from std.math import nan
from std.testing import TestSuite, assert_equal, assert_raises


def check3(actual: List[Float32], vertex: Int, expected: List[Float64]) raises:
    """Check one vertex's three numbers to within 2e-4 of the expected,
    scaled by their size."""
    for axis in range(3):
        var got = Float64(actual[vertex * 3 + axis])
        var scale = max(1.0, abs(expected[axis]))
        if abs(got - expected[axis]) > 2e-4 * scale:
            raise Error(
                "vertex "
                + String(vertex)
                + " axis "
                + String(axis)
                + ": expected "
                + String(expected[axis])
                + " but got "
                + String(got)
            )


def points() raises -> BufferGeometry:
    """Return the four vertices and normals the reference bends."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute(
            [-3, 0.5, -0.25, 0, 0, 0, 1.5, -1, 2, 250, 0.25, 0.5], 3
        ),
    )
    geometry.set_attribute(
        String(NORMAL),
        BufferAttribute([0, 1, 0, 0, 0, 1, 1, 0, 0, 0.6, 0.8, 0], 3),
    )
    return geometry^


def test_half_floats_match_three() raises:
    var values: List[Float64] = [
        0,
        1,
        -1,
        0.1,
        1e-6,
        -3e-7,
        1e-9,
        70000,
        -70000,
        65504,
        2.5e-5,
        0.333333,
        1234.567,
    ]
    var bits: List[Int] = [
        0,
        15360,
        48128,
        11878,
        16,
        32773,
        0,
        31743,
        64511,
        31743,
        419,
        13653,
        25810,
    ]
    for index in range(len(values)):
        assert_equal(Int(to_half_float(values[index])), bits[index])
    # A quiet NaN. Node gives 65024, the same with the sign set, because
    # x86 makes a NaN negative; the sign of a NaN carries nothing.
    assert_equal(Int(to_half_float(nan[DType.float64]())) & 0x7FFF, 0x7E00)


def two_curves() raises -> Flow:
    """Return the reference's flow: a torus knot, then a helix."""
    var flow = Flow(2)
    flow.update_curve(0, torus_knot(10))
    flow.update_curve(1, helix_curve())
    return flow^


def test_the_spine_texture_matches_three_bit_for_bit() raises:
    var flow = two_curves()
    assert_equal(len(flow.spine), 32768)
    var sum = 0
    var hash = 0
    var first = 0
    for index in range(len(flow.spine)):
        var value = Int(flow.spine[index])
        sum += value
        hash = (hash * 31 + value) % 1000000007
        if index < 4 * 1024 * 4:
            first += value
    assert_equal(sum, 866886410)
    assert_equal(hash, 301607886)
    assert_equal(first, 444310935)
    var start: List[Int] = [
        20352,
        0,
        0,
        15360,
        20351,
        13968,
        12757,
        15360,
        20350,
        14991,
        13781,
        15360,
        20349,
        15595,
        14431,
        15360,
    ]
    for index in range(len(start)):
        assert_equal(Int(flow.spine[index]), start[index])
    var inside: List[Int] = [
        10307,
        46767,
        47939,
        15360,
        10209,
        46760,
        47941,
        15360,
    ]
    for index in range(len(inside)):
        assert_equal(
            Int(flow.spine[4 * 1024 * 3 + 4 * 500 + index]), inside[index]
        )
    var last: List[Int] = [10177, 15333, 12551, 15360]
    for index in range(len(last)):
        assert_equal(
            Int(flow.spine[4 * 1024 * 5 + 4 * 1023 + index]), last[index]
        )
    assert_equal(flow.curve_lengths[0].value, Float32(459.29955264679313))
    assert_equal(flow.curve_lengths[1].value, Float32(953.3831743585994))
    assert_equal(flow.spine_length.value, Float32(953.3831743585994))


def test_bending_matches_three_s_shader() raises:
    var flow = two_curves()
    flow.move_along_curve(0.125)
    var bent = flow.deform(points())
    var moved = bent.attribute_view(String(POSITION)).packed()
    var turned = bent.attribute_view(String(NORMAL)).packed()
    check3(
        moved, 0, [15.274446487426758, -22.921369552612305, 6.652117729187012]
    )
    check3(
        turned,
        0,
        [0.5254052877426147, -0.051617853343486786, -0.8490146398544312],
    )
    check3(
        moved, 1, [15.662163734436035, -21.612808227539062, 7.41585111618042]
    )
    check3(
        turned,
        1,
        [-0.6525901556015015, 0.6069906949996948, -0.45281583070755005],
    )
    check3(
        moved, 2, [14.154101371765137, -19.836666107177734, 7.530303955078125]
    )
    check3(
        turned, 2, [0.501794159412384, 0.8144259452819824, 0.2905675768852234]
    )
    check3(
        moved, 3, [-16.832061767578125, -18.462854385375977, 8.62313461303711]
    )
    check3(
        turned,
        3,
        [0.26979389786720276, -0.7713342308998108, 0.5759783983230591],
    )
    var moved_model = flow.deform(points(), translation(1, 2, 3))
    check3(
        moved_model.attribute_view(String(POSITION)).packed(),
        1,
        [15.016450881958008, -19.54587173461914, 4.498456001281738],
    )


def test_a_flow_that_does_not_bend_sits_at_the_offset() raises:
    var flow = two_curves()
    flow.move_along_curve(0.125)
    flow.flow = False
    var bent = flow.deform(points())
    var moved = bent.attribute_view(String(POSITION)).packed()
    var turned = bent.attribute_view(String(NORMAL)).packed()
    check3(moved, 0, [-5.289207458496094, 8.627166748046875, 2.260101318359375])
    check3(turned, 0, [0.901611328125, -0.09954833984375, -0.4202880859375])
    check3(moved, 1, [-6.974609375, 7.166015625, 0.179443359375])


def test_an_instance_rides_its_own_curve() raises:
    var flow = InstancedFlow(2, 2)
    flow.flow.update_curve(0, torus_knot(10))
    flow.flow.update_curve(1, helix_curve())
    flow.flow.move_along_curve(0.125)
    flow.move_individual_along_curve(0, 0.3)
    flow.move_individual_along_curve(1, 0.3)
    flow.set_curve(1, 1)
    var matrix = flow.instance_matrix(1)
    assert_equal(matrix.elements[12], Float32(953.3831743585994))
    assert_equal(matrix.elements[13], 1)
    assert_equal(matrix.elements[14], Float32(0.3))
    var first = flow.deform_instance(points(), 0)
    check3(
        first.attribute_view(String(POSITION)).packed(),
        2,
        [-12.576704978942871, 28.03709602355957, 4.830323696136475],
    )
    check3(
        first.attribute_view(String(NORMAL)).packed(),
        2,
        [-0.7496145367622375, -0.5525734424591064, 0.3633080720901489],
    )
    var second = flow.deform_instance(points(), 1)
    check3(
        second.attribute_view(String(POSITION)).packed(),
        2,
        [29.958961486816406, -4.433074951171875, 87.0293960571289],
    )


def test_a_geometry_without_normals_bends_its_positions() raises:
    var flow = two_curves()
    flow.move_along_curve(0.125)
    var bare = BufferGeometry()
    bare.set_attribute(String(POSITION), BufferAttribute([0, 0, 0], 3))
    var bent = flow.deform(bare)
    assert_equal(bent.attribute_count(), 1)
    var none = BufferGeometry()
    none.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    assert_equal(flow.deform(none).vertex_count(), 0)
    check3(
        bent.attribute_view(String(POSITION)).packed(),
        0,
        [15.662163734436035, -21.612808227539062, 7.41585111618042],
    )


def test_a_flow_refuses_what_is_not_there() raises:
    with assert_raises():
        _ = Flow(0)
    var flow = Flow(1)
    with assert_raises():
        flow.update_curve(1, torus_knot())
    with assert_raises():
        flow.update_curve(-1, torus_knot())
    with assert_raises():
        _ = flow.texel(TEXTURE_WIDTH, 0)
    with assert_raises():
        _ = flow.texel(-1, 0)
    with assert_raises():
        _ = flow.texel(0, 4)
    with assert_raises():
        _ = flow.texel(0, -1)
    var flat = BufferGeometry()
    flat.set_attribute(String(POSITION), BufferAttribute([0, 0], 2))
    with assert_raises():
        _ = flow.deform(flat)
    with assert_raises():
        _ = InstancedFlow(-1, 1)
    var instanced = InstancedFlow(1, 2)
    with assert_raises():
        instanced.set_curve(0, 2)
    with assert_raises():
        instanced.set_curve(0, -1)
    with assert_raises():
        instanced.set_curve(1, 0)
    with assert_raises():
        instanced.move_individual_along_curve(-1, 0.5)
    with assert_raises():
        _ = instanced.deform_instance(points(), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
