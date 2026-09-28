# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `generators.tree`, three.js's `TreeGenerator`.

The expected numbers were computed from three.js r186's
`examples/jsm/generators/TreeGenerator.js`, step for step in `Float64`
with its Mulberry32 generator. The port computes in `Float64` too and
stores `Float32`, so positions agree to a few `Float32` steps.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from generators.tree import TreeGenerator, TreeParameters
from generators.utils import generator_random
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = 2e-5


def _vertex(
    geometry: BufferGeometry,
    name: String,
    index: Int,
    x: Float32,
    y: Float32,
    z: Float32,
) raises:
    """Assert one vertex of an attribute."""
    var v = geometry.attribute_view(name).vector3(index)
    assert_almost_equal(v.x, x, atol=TOLERANCE)
    assert_almost_equal(v.y, y, atol=TOLERANCE)
    assert_almost_equal(v.z, z, atol=TOLERANCE)


def test_generator_random_seeds_as_three() raises:
    """The generators' seed keeps 32 bits and turns zero into one."""
    var one = generator_random(1)
    assert_equal(one.next(), 0.6270739405881613)
    assert_equal(one.next(), 0.002735721180215478)
    var zero = generator_random(0)
    assert_equal(zero.next(), 0.6270739405881613)
    var wrapped = generator_random(1 + 0x100000000)
    assert_equal(wrapped.next(), 0.6270739405881613)


def test_default_tree_matches_three() raises:
    """The default tree has three.js's tubes, vertices and triangles."""
    var generator = TreeGenerator()
    var tubes = generator.tubes()
    assert_equal(len(tubes), 328)
    assert_equal(len(tubes[0].rings), 8)
    assert_equal(len(tubes[1].rings), 5)
    assert_equal(tubes[1].radial, 5)
    assert_almost_equal(tubes[1].rings[0].radius, 0.2604985238214788, atol=1e-6)
    var tip = tubes[0].rings[7].position
    assert_almost_equal(tip.x, 0.5471709214793684, atol=1e-6)
    assert_almost_equal(tip.y, 8.961999736558603, atol=1e-6)
    assert_almost_equal(tip.z, -0.4203447555520826, atol=1e-6)
    var geometry = generator.build()
    assert_equal(geometry.vertex_count(), 4155)
    assert_equal(len(geometry.index), 18756)
    _vertex(geometry, String(POSITION), 0, 0, 0, -0.672)
    _vertex(geometry, String(NORMAL), 0, 0, 0, -1)
    _vertex(geometry, String(POSITION), 2077, -2.4344132, 10.7338264, -0.4239750)
    _vertex(geometry, String(NORMAL), 2077, 0.0749140, 0.9095214, 0.4088506)
    _vertex(geometry, String(POSITION), 4154, 0.4016370, 17.6735287, 1.1806126)
    _vertex(geometry, String(NORMAL), 4154, 0.8521077, -0.2042644, 0.4818595)
    assert_equal(geometry.index[0], 0)
    assert_equal(geometry.index[1], 7)
    assert_equal(geometry.index[2], 6)
    assert_equal(geometry.index[5], 7)
    assert_equal(geometry.index[18755], 4152)


def test_varied_tree_matches_three() raises:
    """Length variance, length falloff, no up pull and no root flare
    follow three.js."""
    var p = TreeParameters()
    p.seed = 7
    p.length_variance = 0.2
    p.branch_length_falloff = 0.3
    p.up_pull = 0
    p.root_flare = 0
    p.levels = 3
    var geometry = TreeGenerator(p^).build()
    assert_equal(geometry.vertex_count(), 689)
    assert_equal(len(geometry.index), 3144)
    _vertex(geometry, String(POSITION), 0, 0, 0, -0.42)
    _vertex(geometry, String(POSITION), 344, -0.2006435, 7.6180082, -1.9924916)
    _vertex(geometry, String(NORMAL), 344, 0.7298029, -0.3147675, 0.6068848)
    _vertex(geometry, String(POSITION), 688, -1.1676888, 13.4109899, 1.8975902)


def test_a_trunk_without_gnarl_stays_straight() raises:
    """With no wobble the tangent never turns, so the frame is carried
    unchanged, as three.js skips a transport between parallel tangents."""
    var p = TreeParameters()
    p.gnarl = [0.0]
    p.levels = 1
    var geometry = TreeGenerator(p^).build()
    assert_equal(geometry.vertex_count(), 48)
    assert_equal(len(geometry.index), 252)
    _vertex(geometry, String(POSITION), 24, 0, 5.1428571, -0.3166522)
    _vertex(geometry, String(NORMAL), 24, 0, 0, -1)
    _vertex(geometry, String(POSITION), 47, 0.1636788, 9, -0.0945)


def test_a_short_trunk_has_no_branches() raises:
    """A branch shorter than the minimum length stops the recursion."""
    var p = TreeParameters()
    p.min_length = Length(100, METER)
    var geometry = TreeGenerator(p^).build()
    assert_equal(geometry.vertex_count(), 48)
    _vertex(geometry, String(POSITION), 24, 0.3314757, 5.1192452, -0.4017635)
    _vertex(geometry, String(POSITION), 47, 0.7100274, 8.9452096, -0.5147738)


def test_no_children_leaves_the_trunk() raises:
    """A child count of zero grows the trunk alone, as the short trunk."""
    var p = TreeParameters()
    p.children = [0]
    var tubes = TreeGenerator(p^).tubes()
    assert_equal(len(tubes), 1)
    assert_almost_equal(tubes[0].rings[4].position.x, 0.33, atol=0.01)


def test_seed_zero_grows_seed_one() raises:
    """A zero seed grows what a seed of one grows, as in three.js."""
    var a = TreeParameters()
    a.seed = 0
    a.levels = 2
    var b = TreeParameters()
    b.levels = 2
    var first = TreeGenerator(a^).build()
    var second = TreeGenerator(b^).build()
    assert_equal(first.vertex_count(), second.vertex_count())
    var last = first.vertex_count() - 1
    assert_true(
        first.attribute_view(String(POSITION)).vector3(last)
        == second.attribute_view(String(POSITION)).vector3(last)
    )


def test_tree_parameters_are_checked() raises:
    """Parameters three.js grows nothing sensible from are refused."""
    var p = TreeParameters()
    p.levels = 0
    with assert_raises(contains="one level"):
        _ = TreeGenerator(p^).build()
    p = TreeParameters()
    p.children = List[Int]()
    with assert_raises(contains="child count for one level"):
        _ = TreeGenerator(p^).build()
    p = TreeParameters()
    p.branch_angle = List[Angle]()
    with assert_raises(contains="branch angle"):
        _ = TreeGenerator(p^).build()
    p = TreeParameters()
    p.gnarl = List[Float64]()
    with assert_raises(contains="gnarl"):
        _ = TreeGenerator(p^).build()
    p = TreeParameters()
    p.children = [3, -1]
    with assert_raises(contains="zero or more"):
        _ = TreeGenerator(p^).build()
    p = TreeParameters()
    p.section_length = Length(0, METER)
    with assert_raises(contains="section length"):
        _ = TreeGenerator(p^).build()
    p = TreeParameters()
    p.radius_exponent = 0
    with assert_raises(contains="radius exponent"):
        _ = TreeGenerator(p^).build()
    p = TreeParameters()
    p.trunk_length = Length(inf[DType.float32](), METER)
    with assert_raises(contains="trunk length"):
        _ = TreeGenerator(p^).build()
    p = TreeParameters()
    p.taper = nan[DType.float64]()
    with assert_raises(contains="taper"):
        _ = TreeGenerator(p^).build()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
