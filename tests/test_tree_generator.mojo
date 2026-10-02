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
from generators.tree import (
    TreeGenerator,
    TreeParameters,
    TreeRing,
    TreeTube,
    _grow,
    _direction,
    _perpendicular,
    _transport,
    _ring_at,
    _position32,
    _radius_at,
)
from generators.utils import Vec3d, generator_random
from std.math import inf, isfinite, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, InverseLength, Length, METER, PER_METER

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
    _vertex(
        geometry, String(POSITION), 2077, -2.4344132, 10.7338264, -0.4239750
    )
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


def _refuses_nonfinite(p: TreeParameters) raises:
    """Both public generation paths reject nonfinite parameters."""
    var generator = TreeGenerator(p.copy())
    with assert_raises(contains="finite"):
        _ = generator.tubes()
    with assert_raises(contains="finite"):
        _ = generator.build()


def test_every_scalar_tree_parameter_must_be_finite() raises:
    """No independent scalar can bypass the common parameter check."""
    for bad in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        var p = TreeParameters()
        p.angle_variance = Angle(Float32(bad), DEGREE)
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.length_ratio = bad
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.length_variance = bad
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.branch_length_falloff = bad
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.trunk_length = Length(Float32(bad), METER)
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.trunk_radius = Length(Float32(bad), METER)
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.taper = bad
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.taper_curve = bad
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.root_flare = bad
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.flare_frac = bad
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.radius_exponent = bad
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.min_radius = Length(Float32(bad), METER)
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.min_length = Length(Float32(bad), METER)
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.droop = InverseLength(Float32(bad), PER_METER)
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.up_pull = bad
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.section_length = Length(Float32(bad), METER)
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.child_start = bad
        _refuses_nonfinite(p)
        p = TreeParameters()
        p.trunk_clear = bad
        _refuses_nonfinite(p)


def test_each_tree_list_entry_must_be_finite() raises:
    """Unused tail entries are checked before the tree starts to grow."""
    for bad in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        for at in [0, 1]:
            var p = TreeParameters()
            p.levels = 1
            p.gnarl = [0.05, 0.1]
            p.gnarl[at] = bad
            _refuses_nonfinite(p)
            p = TreeParameters()
            p.levels = 1
            p.branch_angle = [Angle(30, DEGREE), Angle(40, DEGREE)]
            p.branch_angle[at] = Angle(Float32(bad), DEGREE)
            _refuses_nonfinite(p)


def test_tree_power_and_division_parameters_have_valid_domains() raises:
    """The tip's zero base cannot have a negative exponent."""
    var p = TreeParameters()
    p.taper_curve = -1
    with assert_raises(contains="taper curve"):
        _ = TreeGenerator(p^).build()
    for fraction in [Float64(0), Float64(-0.1)]:
        p = TreeParameters()
        p.flare_frac = fraction
        with assert_raises(contains="flare fraction"):
            _ = TreeGenerator(p^).build()
    # A disabled flare does not divide by its fraction. Zero taper curve
    # makes a constant radius, and a short list repeats at later levels.
    p = TreeParameters()
    p.levels = 2
    p.children = [1]
    p.branch_angle = [Angle(30, DEGREE)]
    p.gnarl = [0.0]
    p.root_flare = 0
    p.flare_frac = 0
    p.taper_curve = 0
    var geometry = TreeGenerator(p^).build()
    assert_true(geometry.vertex_count() > 48)
    for name in [String(POSITION), String(NORMAL)]:
        for number in geometry.attribute_view(name).packed():
            assert_true(isfinite(number))


def test_tree_sections_clamp_before_integer_conversion() raises:
    """A large finite length-to-step ratio still makes only 24 sections."""
    var p = TreeParameters()
    p.levels = 1
    p.gnarl = [0.0]
    p.section_length = Length(1e-30, METER)
    var generator = TreeGenerator(p^)
    var tubes = generator.tubes()
    assert_equal(len(tubes), 1)
    assert_equal(len(tubes[0].rings), 25)
    var geometry = generator.build()
    assert_equal(geometry.vertex_count(), 25 * 6)
    for number in geometry.attribute_view(String(POSITION)).packed():
        assert_true(isfinite(number))
    _vertex(geometry, String(POSITION), 24 * 6, 0, 9, -0.189)


def _unit(v: Vec3d) raises:
    """Assert finite unit components, never a NaN-blind comparison."""
    assert_true(isfinite(v.x))
    assert_true(isfinite(v.y))
    assert_true(isfinite(v.z))
    assert_almost_equal(v.length(), 1.0, atol=2e-12, rtol=0)


def _valid_tree(p: TreeParameters) raises:
    """Check both public outputs, including orthogonal ring frames."""
    var generator = TreeGenerator(p.copy())
    var tubes = generator.tubes()
    for tube in tubes:
        for ring in tube.rings:
            _unit(ring.tangent)
            _unit(ring.normal)
            assert_almost_equal(ring.tangent.dot(ring.normal), 0.0, atol=2e-12)
            assert_true(isfinite(ring.radius))
            assert_true(isfinite(ring.position.x))
            assert_true(isfinite(ring.position.y))
            assert_true(isfinite(ring.position.z))
    var geometry = generator.build()
    for value in geometry.attribute_view(String(POSITION)).packed():
        assert_true(isfinite(value))
    for i in range(geometry.vertex_count()):
        var n = geometry.attribute_view(String(NORMAL)).vector3(i)
        assert_true(isfinite(n.x))
        assert_true(isfinite(n.y))
        assert_true(isfinite(n.z))
        assert_almost_equal(n.length(), Float32(1), atol=2e-6, rtol=0)


def test_extreme_finite_gnarl_keeps_frames_and_normal_directions() raises:
    """The native failing gnarl case now has unit, correctly oriented normals.
    """
    for gnarl in [Float64(1e200), Float64(1e308), Float64(-1e308)]:
        var p = TreeParameters()
        p.levels = 1
        p.gnarl = [gnarl]
        _valid_tree(p)
    var p = TreeParameters()
    p.levels = 1
    p.gnarl = [1e200]
    var generator = TreeGenerator(p^)
    var tubes = generator.tubes()
    var t = tubes[0].rings[1].tangent
    # Independent scaled direction and Rodrigues rotation from seed 1's
    # first signed draws, not from the production normalization routine.
    assert_almost_equal(t.x, 0.24723637912427904, atol=2e-14)
    assert_almost_equal(t.y, -0.9674825475169307, atol=2e-14)
    assert_almost_equal(t.z, 0.0534012461246534, atol=2e-14)
    var geometry = generator.build()
    _vertex(
        geometry,
        String(NORMAL),
        6,
        0.40601983625432897,
        0.0534012461246534,
        -0.912302690711993,
    )


def test_extreme_flare_has_a_finite_skeleton_but_refuses_float32_bake() raises:
    """Float64 rings may exceed Float32; only the bake must refuse them."""
    var p = TreeParameters()
    p.levels = 1
    p.gnarl = [0.0]
    p.root_flare = 1e308
    var generator = TreeGenerator(p^)
    var tubes = generator.tubes()
    assert_true(isfinite(tubes[0].rings[0].radius))
    assert_true(tubes[0].rings[0].radius > 1e307)
    with assert_raises(contains="Float32 range"):
        _ = generator.build()


def test_large_finite_parameters_can_have_representable_output() raises:
    """No arbitrary parameter bound replaces generated-output checks."""
    var p = TreeParameters()
    p.levels = 1
    p.gnarl = [1e308]
    p.trunk_radius = Length(1e-30, METER)
    p.taper = 1e60
    # The product of the large taper and radius fits Float32 too.
    p.root_flare = 0
    _valid_tree(p)
    p = TreeParameters()
    p.levels = 1
    p.gnarl = [0.0]
    p.trunk_radius = Length(1e-30, METER)
    p.root_flare = 1e60
    _valid_tree(p)


def test_generated_nonfinite_radius_and_branch_length_are_refused() raises:
    """Finite inputs can overflow derived Float64 arithmetic."""
    var p = TreeParameters()
    p.levels = 1
    p.trunk_radius = Length(1e30, METER)
    p.root_flare = 1e308
    with assert_raises(contains="generated tree radius"):
        _ = TreeGenerator(p^).tubes()
    # All preceding rings fit Float64; the terminal radius does not.
    p = TreeParameters()
    p.levels = 1
    p.trunk_radius = Length(1e30, METER)
    p.root_flare = 0
    p.taper = 2e278
    for section in range(7):
        assert_true(isfinite(_radius_at(p, 1e30, 0, Float64(section) / 7)))
    assert_true(not isfinite(_radius_at(p, 1e30, 0, 1)))
    with assert_raises(contains="generated tree radius"):
        _ = TreeGenerator(p^).tubes()
    p = TreeParameters()
    p.levels = 2
    p.children = [1]
    p.length_ratio = 1e308
    with assert_raises(contains="generated branch length"):
        _ = TreeGenerator(p^).tubes()


def test_generated_direction_overflow_and_exact_cancellation_are_refused() raises:
    """Check before normalization, which must not hide invalid arithmetic."""
    var p = TreeParameters()
    p.levels = 2
    p.children = [1]
    p.gnarl = [0.0]
    p.branch_angle = [Angle(180, DEGREE)]
    p.angle_variance = Angle(0, DEGREE)
    p.up_pull = 1e308
    with assert_raises(contains="generated tree direction"):
        _ = TreeGenerator(p^).tubes()
    p = TreeParameters()
    p.levels = 2
    p.children = [1]
    p.gnarl = [0.0]
    p.branch_angle = [Angle(0, DEGREE)]
    p.angle_variance = Angle(0, DEGREE)
    p.up_pull = 1
    p.trunk_length = Length(8, METER)
    p.section_length = Length(2, METER)
    p.length_ratio = 1
    p.droop = InverseLength(0.5, PER_METER)
    with assert_raises(contains="nonzero"):
        _ = TreeGenerator(p^).build()


def test_generated_position_overflow_is_refused_before_return() raises:
    """Overflow in path accumulation cannot escape through tubes."""
    var p = TreeParameters()
    p.levels = 1
    p.gnarl = [0.0]
    var tubes = List[TreeTube]()
    var random = generator_random(1)
    with assert_raises(contains="generated tree position"):
        _grow(
            tubes,
            Vec3d(0, 1e308, 0),
            Vec3d(0, 1, 0),
            8e307,
            1,
            0,
            p,
            random,
        )


def test_public_tubes_refuses_generated_position_overflow() raises:
    """A one-child chain must reject overflow before returning its skeleton."""
    var p = TreeParameters()
    p.levels = 1000
    p.children = [1]
    p.gnarl = [0.0]
    p.branch_angle = [Angle(0, DEGREE)]
    p.angle_variance = Angle(0, DEGREE)
    p.up_pull = 1
    p.droop = InverseLength(0, PER_METER)
    p.trunk_clear = 1
    p.child_start = 1
    p.trunk_length = Length(3e38, METER)
    p.length_ratio = 2
    with assert_raises(contains="generated tree position"):
        _ = TreeGenerator(p^).tubes()


def test_transport_repairs_near_parallel_and_antiparallel_frames() raises:
    """Skipped turns still need perpendicular unit normals."""
    var up = Vec3d(0, 1, 0)
    var normal = Vec3d(0, 0, -1)
    for next in [
        up,
        Vec3d(0, -1, 0),
        Vec3d(0, 1, 5e-7).normalized(),
        Vec3d(0, -1, 5e-7).normalized(),
    ]:
        var n = _transport(up, next, normal)
        _unit(n)
        assert_almost_equal(n.dot(next), 0.0, atol=2e-15)
        if next.y < 0 and next.z > 0:
            assert_almost_equal(n.z, 1.0, atol=2e-12)
            assert_almost_equal(n.y, 5e-7, atol=2e-12)
        else:
            assert_true(n.z < 0)
    # A subnormal cross product must not overflow a reciprocal axis scale.
    var almost_opposite = Vec3d(0, -1, 5e-324)
    var tiny_axis_normal = _transport(up, almost_opposite, normal)
    _unit(tiny_axis_normal)
    assert_equal(tiny_axis_normal.z, 1.0)
    assert_almost_equal(tiny_axis_normal.dot(almost_opposite), 0.0, atol=1e-15)
    var perpendicular = _perpendicular(Vec3d(1, 0, 0))
    assert_equal(perpendicular.z, 1.0)


def test_generated_direction_guard_handles_every_component_and_zero() raises:
    """Finite nonzero directions normalize at all Float64 magnitudes."""
    for direction in [
        Vec3d(1, 0, 0),
        Vec3d(0, 1, 0),
        Vec3d(0, 0, 1),
        Vec3d(1e308, -1e308, 1e308),
        Vec3d(5e-324, 0, 0),
    ]:
        _unit(_direction(direction))
    with assert_raises(contains="nonzero"):
        _ = _direction(Vec3d(0, 0, 0))
    for direction in [
        Vec3d(inf[DType.float64](), 0, 0),
        Vec3d(0, inf[DType.float64](), 0),
        Vec3d(0, 0, nan[DType.float64]()),
    ]:
        with assert_raises(contains="finite"):
            _ = _direction(direction)


def test_interpolated_zero_direction_and_nonfinite_fraction_are_refused() raises:
    """Cancellation cannot leave an invalid sampled branch direction."""
    var rings = List[TreeRing](
        [
            TreeRing(Vec3d(0, 0, 0), Vec3d(0, 1, 0), Vec3d(0, 0, -1), 1),
            TreeRing(Vec3d(0, 1, 0), Vec3d(0, -1, 0), Vec3d(0, 0, -1), 1),
        ]
    )
    with assert_raises(contains="nonzero"):
        _ = _ring_at(rings, 0.5)
    with assert_raises(contains="generated child fraction"):
        _ = _ring_at(rings, inf[DType.float64]())


def test_float32_coordinate_boundary_is_symmetric_and_finite() raises:
    """Accept the exact maximum and rounded underflow; refuse overflow."""
    var largest = Float64(3.4028234663852886e38)
    assert_equal(Float64(_position32(largest)), largest)
    assert_equal(Float64(_position32(-largest)), -largest)
    var neighbor = Float64(3.4028232635611926e38)
    assert_equal(Float64(_position32(neighbor)), neighbor)
    assert_equal(Float64(_position32(-neighbor)), -neighbor)
    assert_equal(_position32(1e-300), Float32(0))
    for value in [largest * 1.0000001, -largest * 1.0000001]:
        with assert_raises(contains="Float32 range"):
            _ = _position32(value)
    with assert_raises(contains="generated tree vertex"):
        _ = _position32(inf[DType.float64]())


def test_straight_ring_normals_have_exact_cardinal_directions() raises:
    """Check orientation and sign, not only length or vertex count."""
    var p = TreeParameters()
    p.levels = 1
    p.gnarl = [0.0]
    p.radial_segments = 4
    var geometry = TreeGenerator(p^).build()
    for ring in range(geometry.vertex_count() // 4):
        _vertex(geometry, String(NORMAL), ring * 4, 0, 0, -1)
        _vertex(geometry, String(NORMAL), ring * 4 + 1, -1, 0, 0)
        _vertex(geometry, String(NORMAL), ring * 4 + 2, 0, 0, 1)
        _vertex(geometry, String(NORMAL), ring * 4 + 3, 1, 0, 0)


def test_fraction_extrapolation_and_repeated_lists_remain_supported() raises:
    """The three.js setters allow finite extrapolation and ringAt clamps it."""
    for fraction in [Float64(-0.5), Float64(0), Float64(1), Float64(1.5)]:
        var p = TreeParameters()
        p.levels = 3
        p.children = [1]
        p.gnarl = [0.0]
        p.branch_angle = [Angle(30, DEGREE)]
        p.up_pull = fraction
        p.child_start = fraction
        p.trunk_clear = fraction
        _valid_tree(p)
    var p = TreeParameters()
    p.children = [0]
    p.gnarl = [1e308]
    _valid_tree(p)


def test_high_gnarl_seeds_keep_every_public_frame_orthogonal() raises:
    """Seeded extreme turns cannot leave invalid recursive tube frames."""
    for seed in [1, 2, 7, 19, 12345]:
        for gnarl in [Float64(1e200), Float64(-1e308)]:
            var p = TreeParameters()
            p.seed = seed
            p.levels = 3
            p.children = [2]
            p.gnarl = [gnarl]
            _valid_tree(p)


def test_default_and_clamped_fraction_frames_are_valid() raises:
    """Check every default frame and both ring sampling clamp endpoints."""
    _valid_tree(TreeParameters())
    for clearance in [Float64(-10), Float64(10)]:
        var p = TreeParameters()
        p.levels = 2
        p.children = [1]
        p.gnarl = [0.0]
        p.trunk_clear = clearance
        var tubes = TreeGenerator(p^).tubes()
        var expected = 0.0 if clearance < 0 else 8.991
        assert_almost_equal(tubes[1].rings[0].position.y, expected, atol=2e-14)


def test_shared_vec3d_norms_keep_ordinary_and_extreme_directions() raises:
    """Shared generator math uses safe length and normalization primitives."""
    assert_equal(Vec3d(3, 4, 0).length(), 5.0)
    assert_equal(Vec3d(3, 4, 0).normalized().x, Float64(3) * (1.0 / 5.0))
    var large = Vec3d(1e200, 1e200, 0)
    assert_almost_equal(large.length() / 1e200, sqrt(Float64(2)), atol=1e-15)
    _unit(large.normalized())
    _unit(Vec3d(1e308, 1e308, 1e308).normalized())
    _unit(Vec3d(1e-300, -1e-300, 1e-300).normalized())
    assert_equal(Vec3d(5e-324, 0, 0).normalized().x, 1.0)
    assert_equal(Vec3d(0, 0, 0).normalized().length(), 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
