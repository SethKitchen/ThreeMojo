# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the humanoid spec, osteometric femur and the femur mesh."""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import MAX_STATURE, MIN_STATURE, HumanoidSpec
from extensions.humanoid.skeleton.field import (
    clamp_unit,
    empty_bounds,
    sd_ellipse_segment,
    sd_ellipsoid,
    sd_segment,
    smin,
)
from extensions.humanoid.skeleton.isosurface import (
    _axis_cells,
    _clamp01,
    _clip_tetrahedron,
    _emit_triangle,
    _lerp_zero,
    _long_cells,
    _require_triangles,
    _unit_face,
)
from extensions.humanoid.skeleton.occupancy import (
    CORTICAL_FILL,
    EMPTY,
    MARROW,
    MAX_STEP,
    MIN_STEP,
    TRABECULAR_FILL,
    BoneOccupancy,
    Tally,
    add_fill,
    apparent_density_of,
    grid_cells,
)
from extensions.humanoid.skeleton.tissue import (
    BoneKind,
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    FemurField,
    femur_dimensions,
    femur_distance,
    measured_neck_shaft_angle,
)
from extensions.humanoid.skeleton.leg.femur.geometry import (
    femur,
    femur_from_dimensions,
)
from extensions.humanoid.skeleton.leg.femur.mass import (
    femur_mass,
    femur_mass_from_dimensions,
    femur_occupancy,
)
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Angle,
    CENTIMETER,
    CUBIC_CENTIMETER,
    DEGREE,
    FOOT,
    GRAM,
    Length,
    METER,
    MILLIMETER,
    NEWTON,
    RADIAN,
    STANDARD_GRAVITY,
)

comptime TOLERANCE = Float64(1e-5)


def test_male_and_female_are_valid() raises:
    assert_true(MALE.is_valid())
    assert_true(FEMALE.is_valid())
    assert_false(Sex(2).is_valid())
    assert_false(Sex(-1).is_valid())


def test_right_and_left_are_valid() raises:
    assert_true(RIGHT.is_valid())
    assert_true(LEFT.is_valid())
    assert_false(BodySide(2).is_valid())
    assert_false(BodySide(-1).is_valid())


def test_six_foot_male_femur_length_matches_trotter_gleser() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var stature_cm = Length(6.0, FOOT).to(CENTIMETER)
    var expected_cm = (stature_cm - Float32(61.41)) / Float32(2.38)
    assert_almost_equal(dims.length.to(CENTIMETER), expected_cm, atol=TOLERANCE)
    assert_true(dims.sex == MALE)
    assert_true(dims.side == RIGHT)


def test_six_foot_female_uses_the_female_line() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), FEMALE)
    var stature_cm = Length(6.0, FOOT).to(CENTIMETER)
    var expected_cm = (stature_cm - Float32(54.10)) / Float32(2.47)
    assert_almost_equal(dims.length.to(CENTIMETER), expected_cm, atol=TOLERANCE)
    assert_true(dims.sex == FEMALE)


def test_head_diameter_scales_with_femur_length() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_almost_equal(
        dims.head_diameter.value,
        dims.length.value * Float32(0.1030),
        atol=TOLERANCE,
    )


def test_right_head_is_medial() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE, RIGHT)
    assert_true(dims.head_center.x < dims.greater_trochanter.x)
    assert_true(dims.head_center.x < dims.neck_base.x)


def test_left_head_is_medial_on_the_other_side() raises:
    var right = femur_dimensions(Length(6.0, FOOT), MALE, RIGHT)
    var left = femur_dimensions(Length(6.0, FOOT), MALE, LEFT)
    assert_almost_equal(
        left.head_center.x, -right.head_center.x, atol=TOLERANCE
    )
    assert_almost_equal(left.head_center.y, right.head_center.y, atol=TOLERANCE)
    assert_true(left.head_center.x > left.greater_trochanter.x)
    assert_true(left.side == LEFT)


def test_taller_male_has_a_longer_femur() raises:
    var short = femur_dimensions(Length(5.0, FOOT), MALE)
    var tall = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_true(tall.length > short.length)
    assert_true(tall.head_diameter > short.head_diameter)
    assert_true(tall.bicondylar_width > short.bicondylar_width)


def test_midshaft_is_inside_and_a_far_point_is_outside() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_true(femur_distance(dims, dims.neck_base) < 0)
    assert_true(femur_distance(dims, Vector3(10, 0, 0)) > 0)


def test_head_center_is_inside_the_solid() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_true(femur_distance(dims, dims.head_center) < 0)


def test_condyle_center_is_inside_the_solid() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), FEMALE, LEFT)
    assert_true(femur_distance(dims, dims.medial_condyle) < 0)
    assert_true(femur_distance(dims, dims.lateral_condyle) < 0)


def test_greater_trochanter_is_inside_the_solid() raises:
    var dims = femur_dimensions(Length(1.2, METER), MALE)
    assert_true(femur_distance(dims, dims.greater_trochanter) < 0)
    assert_true(femur_distance(dims, dims.lesser_trochanter) < 0)


def test_generated_neck_shaft_angle_matches_the_template() raises:
    var male = femur_dimensions(Length(6.0, FOOT), MALE)
    var female = femur_dimensions(Length(6.0, FOOT), FEMALE)
    assert_almost_equal(
        measured_neck_shaft_angle(male).to(DEGREE),
        Float32(126.0),
        atol=Float64(0.5),
    )
    assert_almost_equal(
        measured_neck_shaft_angle(female).to(DEGREE),
        Float32(128.0),
        atol=Float64(0.5),
    )


def test_midshaft_ap_and_ml_are_independent() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var tall_ap = dims
    tall_ap.midshaft_ap = Length(40.0, MILLIMETER)
    tall_ap.midshaft_ml = Length(20.0, MILLIMETER)
    tall_ap.validate()
    var round = dims
    round.midshaft_ap = Length(30.0, MILLIMETER)
    round.midshaft_ml = Length(30.0, MILLIMETER)
    round.validate()
    var field_ap = FemurField(tall_ap)
    var field_round = FemurField(round)
    var anterior = Vector3(
        field_ap.s2.x, field_ap.s2.y, field_ap.s2.z + Float32(0.018)
    )
    var lateral = Vector3(
        field_ap.s2.x + Float32(0.012), field_ap.s2.y, field_ap.s2.z
    )
    assert_true(field_ap.distance(anterior) < field_round.distance(anterior))
    assert_true(field_ap.distance(lateral) > field_round.distance(lateral))


def test_ellipse_segment_keeps_ap_and_ml_apart() raises:
    var a = Vector3(0, 0, 0)
    var b = Vector3(0, 1, 0)
    var hint = Vector3(1, 0, 0)
    var on_ml = sd_ellipse_segment(
        Vector3(0.20, 0.5, 0), a, b, 0.20, 0.05, 0.20, 0.05, hint
    )
    var on_ap = sd_ellipse_segment(
        Vector3(0, 0.5, 0.05), a, b, 0.20, 0.05, 0.20, 0.05, hint
    )
    assert_almost_equal(on_ml, Float32(0), atol=Float64(1e-3))
    assert_almost_equal(on_ap, Float32(0), atol=Float64(1e-3))
    var axis = sd_ellipse_segment(
        Vector3(0, 0.5, 0), a, b, 0.20, 0.05, 0.20, 0.05, hint
    )
    assert_true(axis < 0)


def test_ellipse_segment_along_x_uses_the_fallback_frame() raises:
    var a = Vector3(0, 0, 0)
    var b = Vector3(1, 0, 0)
    var hint = Vector3(1, 0, 0)
    var on_z = sd_ellipse_segment(
        Vector3(0.5, 0, 0.20), a, b, 0.20, 0.05, 0.20, 0.05, hint
    )
    var on_y = sd_ellipse_segment(
        Vector3(0.5, 0.05, 0), a, b, 0.20, 0.05, 0.20, 0.05, hint
    )
    assert_almost_equal(on_z, Float32(0), atol=Float64(2e-3))
    assert_almost_equal(on_y, Float32(0), atol=Float64(2e-3))


def test_a_degenerated_ellipse_segment_is_an_ellipsoid() raises:
    var at = Vector3(1, 2, 3)
    var hint = Vector3(1, 0, 0)
    var on = sd_ellipse_segment(at, at, at, 0.4, 0.2, 0.4, 0.2, hint)
    assert_true(on < 0)
    var away = sd_ellipse_segment(
        Vector3(1, 2, 4), at, at, 0.4, 0.2, 0.4, 0.2, hint
    )
    assert_true(away > 0)


def test_ellipse_t_clamps_beyond_the_end() raises:
    var a = Vector3(0, 0, 0)
    var b = Vector3(0, 1, 0)
    var hint = Vector3(1, 0, 0)
    var below = sd_ellipse_segment(
        Vector3(0, -1, 0), a, b, 0.1, 0.1, 0.1, 0.1, hint
    )
    var above = sd_ellipse_segment(
        Vector3(0, 2, 0), a, b, 0.1, 0.1, 0.1, 0.1, hint
    )
    assert_true(below > 0)
    assert_true(above > 0)


def test_a_degenerated_segment_is_a_sphere() raises:
    var at = Vector3(1, 2, 3)
    var on = sd_segment(at, at, at, 0.5, 0.25)
    assert_almost_equal(on, Float32(-0.5), atol=TOLERANCE)
    var away = sd_segment(Vector3(1, 2, 4), at, at, 0.5, 0.25)
    assert_almost_equal(away, Float32(0.5), atol=TOLERANCE)


def test_ellipsoid_center_uses_the_zero_gradient_path() raises:
    var center = Vector3(1, 2, 3)
    var radii = Vector3(0.4, 0.2, 0.5)
    var inside = sd_ellipsoid(center, center, radii)
    assert_true(inside < 0)
    var far = sd_ellipsoid(Vector3(10, 2, 3), center, radii)
    assert_true(far > 0)


def test_smin_skips_the_blend_when_values_are_far() raises:
    var blended = smin(Float32(0), Float32(0.01), Float32(0.1))
    assert_true(blended < 0)
    var apart = smin(Float32(0), Float32(2), Float32(0.1))
    assert_equal(apart, Float32(0))


def test_empty_bounds_grows_from_the_first_sphere() raises:
    var box = empty_bounds()
    box.include_sphere(Vector3(1, 2, 3), Float32(0.5))
    box.include_ellipsoid(Vector3(0, 2, 3), Vector3(0.2, 0.2, 0.2))
    var padded = box.padded(Float32(0.1))
    assert_true(padded.low.x < box.low.x)
    assert_true(padded.high.x > box.high.x)
    assert_true(box.low.x < Float32(0.9))


def test_clamp_unit_holds_the_acos_domain() raises:
    assert_equal(clamp_unit(Float32(-2)), Float32(-1))
    assert_equal(clamp_unit(Float32(2)), Float32(1))
    assert_equal(clamp_unit(Float32(0.25)), Float32(0.25))


def test_lerp_zero_covers_midpoint_and_clamps() raises:
    var a = Vector3(0, 0, 0)
    var b = Vector3(1, 0, 0)
    var mid = _lerp_zero(a, b, 1, 1)
    assert_almost_equal(mid.x, Float32(0.5), atol=TOLERANCE)
    var interior = _lerp_zero(a, b, -1, 1)
    assert_almost_equal(interior.x, Float32(0.5), atol=TOLERANCE)
    var lo = _lerp_zero(a, b, 1, 2)
    assert_equal(lo.x, Float32(0))
    var hi = _lerp_zero(a, b, 2, 1)
    assert_equal(hi.x, Float32(1))


def test_clamp01_holds_the_unit_interval() raises:
    assert_equal(_clamp01(Float32(-0.2)), Float32(0))
    assert_equal(_clamp01(Float32(1.2)), Float32(1))
    assert_equal(_clamp01(Float32(0.4)), Float32(0.4))


def test_grid_counts_honor_the_floor() raises:
    assert_equal(_long_cells(5), 24)
    assert_equal(_long_cells(10), 30)
    assert_equal(_axis_cells(Float32(0.1), Float32(0.02), 12), 12)
    assert_equal(_axis_cells(Float32(1.0), Float32(0.1), 8), 10)


def test_empty_isosurface_is_refused() raises:
    with assert_raises():
        _require_triangles(List[Int](), "femur")
    var keep = List[Int]()
    keep.append(0)
    keep.append(1)
    keep.append(2)
    _require_triangles(keep, "femur")


def test_unit_face_normalizes_and_handles_a_degenerate_triangle() raises:
    var n = _unit_face(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))
    assert_almost_equal(n.z, Float32(1), atol=TOLERANCE)
    var flat = _unit_face(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0))
    assert_equal(flat.x, Float32(0))
    assert_equal(flat.y, Float32(1))
    assert_equal(flat.z, Float32(0))


def test_emit_triangle_flips_when_the_normal_points_in() raises:
    var positions = List[Float32]()
    var indices = List[Int]()
    _emit_triangle(
        positions,
        indices,
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0.1, 0.1, 1),
    )
    assert_equal(indices[0], 0)
    assert_equal(indices[1], 2)
    assert_equal(indices[2], 1)
    var keep = List[Float32]()
    var wind = List[Int]()
    _emit_triangle(
        keep,
        wind,
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0.1, 0.1, -1),
    )
    assert_equal(wind[0], 0)
    assert_equal(wind[1], 1)
    assert_equal(wind[2], 2)


def test_every_tetrahedron_sign_pattern_emits_the_expected_triangles() raises:
    var a = Vector3(0, 0, 0)
    var b = Vector3(1, 0, 0)
    var c = Vector3(0, 1, 0)
    var d = Vector3(0, 0, 1)
    var mask = 0
    while mask < 16:
        var da = Float32(1)
        var db = Float32(1)
        var dc = Float32(1)
        var dd = Float32(1)
        if mask % 2 == 1:
            da = Float32(-1)
        if (mask // 2) % 2 == 1:
            db = Float32(-1)
        if (mask // 4) % 2 == 1:
            dc = Float32(-1)
        if (mask // 8) % 2 == 1:
            dd = Float32(-1)
        var positions = List[Float32]()
        var indices = List[Int]()
        _clip_tetrahedron(positions, indices, a, b, c, d, da, db, dc, dd)
        var bits = 0
        if da < 0:
            bits = bits + 1
        if db < 0:
            bits = bits + 1
        if dc < 0:
            bits = bits + 1
        if dd < 0:
            bits = bits + 1
        if bits == 0:
            assert_equal(len(indices), 0)
        elif bits == 4:
            assert_equal(len(indices), 0)
        elif bits == 2:
            assert_equal(len(indices), 6)
        else:
            assert_equal(len(indices), 3)
        mask = mask + 1


def test_gradient_at_a_far_point_points_out() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var field = FemurField(dims)
    var n = field.gradient(Vector3(10, 0, 0))
    assert_almost_equal(n.length(), Float32(1), atol=Float64(1e-3))
    assert_true(n.x > 0)


def test_spec_holds_stature_and_sex() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    assert_equal(person.stature.value, Length(6.0, FOOT).value)
    assert_true(person.sex == MALE)


def test_femur_mesh_has_positions_normals_and_uvs() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = femur(person, RIGHT, 8)
    assert_true(bone.has_attribute(String(POSITION)))
    assert_true(bone.has_attribute(String(NORMAL)))
    assert_true(bone.has_attribute(String(UV)))
    assert_true(bone.vertex_count() > 0)
    assert_true(bone.triangle_count() > 0)
    assert_true(len(bone.index) > 0)
    ref normals = bone.attribute_view(String(NORMAL))
    for vertex in range(bone.vertex_count()):
        var n = normals.vector3(vertex)
        assert_almost_equal(n.length(), Float32(1), atol=Float64(1e-3))
    var box = bone.bounding_box()
    var span = box.max.y - box.min.y
    var length = femur_dimensions(Length(6.0, FOOT), MALE).length.value
    assert_true(span > length * Float32(0.70))
    assert_true(span < length * Float32(1.30))


def test_isosurface_winding_and_interior_residual() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var field = FemurField(dims)
    var coarse = femur_from_dimensions(dims, 8)
    var finer = femur_from_dimensions(dims, 12)
    _assert_outward_and_short(coarse)
    _assert_outward_and_short(finer)
    var e8 = _max_positive_centroid(coarse, field)
    var e12 = _max_positive_centroid(finer, field)
    assert_true(e8 < Float32(0.020))
    assert_true(e12 < Float32(0.015))
    assert_true(e12 < e8 * Float32(1.05))


def test_more_detail_makes_more_triangles() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), FEMALE)
    var coarse = femur(person, LEFT, 8)
    var finer = femur(person, LEFT, 12)
    assert_true(finer.triangle_count() > coarse.triangle_count())


def test_left_mesh_mirrors_the_right() raises:
    var person = HumanoidSpec(Length(5.5, FOOT), MALE)
    var right = femur(person, RIGHT, 8)
    var left = femur(person, LEFT, 8)
    var right_box = right.bounding_box()
    var left_box = left.bounding_box()
    assert_true(right_box.min.x < 0)
    assert_true(left_box.max.x > 0)
    assert_almost_equal(-right_box.min.x, left_box.max.x, atol=Float64(1e-3))


def test_refuses_an_invalid_sex() raises:
    with assert_raises():
        _ = femur_dimensions(Length(6.0, FOOT), Sex(9))


def test_refuses_an_invalid_side() raises:
    with assert_raises():
        _ = femur_dimensions(Length(6.0, FOOT), MALE, BodySide(9))


def test_refuses_a_short_stature() raises:
    with assert_raises():
        _ = femur_dimensions(Length(1.19, METER), MALE)


def test_refuses_a_tall_stature() raises:
    with assert_raises():
        _ = femur_dimensions(Length(2.51, METER), FEMALE)


def test_refuses_a_non_finite_stature() raises:
    with assert_raises():
        _ = femur_dimensions(Length(nan[DType.float32](), METER), MALE)
    with assert_raises():
        _ = femur_dimensions(Length(inf[DType.float32](), METER), FEMALE)


def test_stature_bounds_are_accepted() raises:
    var short = femur_dimensions(MIN_STATURE, FEMALE)
    var tall = femur_dimensions(MAX_STATURE, MALE)
    assert_true(tall.length > short.length)
    short.validate()
    tall.validate()


def test_refuses_a_low_detail() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = femur_from_dimensions(dims, 7)


def test_refuses_a_high_detail() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = femur_from_dimensions(dims, 65)


def test_validate_refuses_a_zero_head_diameter() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.head_diameter = Length(0)
    with assert_raises():
        dims.validate()
    with assert_raises():
        _ = femur_from_dimensions(dims, 8)
    with assert_raises():
        _ = femur_distance(dims, Vector3(0, 0, 0))
    with assert_raises():
        _ = femur_occupancy(dims, Vector3(0, 0, 0))
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(20.0, MILLIMETER),
        )


def test_validate_refuses_non_finite_and_non_positive_lengths() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.length = Length(nan[DType.float32](), METER)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.neck_length = Length(-0.01, METER)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.anterior_bow = Length(nan[DType.float32](), METER)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.anterior_bow = Length(-0.01, METER)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.anterior_bow = Length(0)
    dims.validate()


def test_validate_refuses_bad_angles_and_landmarks() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.neck_shaft_angle = Angle(nan[DType.float32](), RADIAN)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.neck_shaft_angle = Angle(0, DEGREE)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.neck_shaft_angle = Angle(180.0, DEGREE)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.anteversion = Angle(nan[DType.float32](), RADIAN)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.bicondylar_angle = Angle(-1.0, DEGREE)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.bicondylar_angle = Angle(90.0, DEGREE)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.head_center = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.head_center = Vector3(0, nan[DType.float32](), 0)
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.head_center = Vector3(0, 0, nan[DType.float32]())
    with assert_raises():
        dims.validate()
    dims = femur_dimensions(Length(6.0, FOOT), MALE)
    dims.sex = Sex(9)
    with assert_raises():
        dims.validate()


def test_occupancy_outside_is_empty() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_true(femur_occupancy(dims, Vector3(10, 0, 0)) == EMPTY)
    assert_false(BoneOccupancy(9).is_valid())
    assert_false(BoneOccupancy(-1).is_valid())
    assert_true(EMPTY.is_valid())
    assert_true(CORTICAL_FILL.is_valid())
    assert_true(TRABECULAR_FILL.is_valid())
    assert_true(MARROW.is_valid())


def test_head_interior_is_trabecular() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_true(femur_occupancy(dims, dims.head_center) == TRABECULAR_FILL)


def test_condyle_interior_is_trabecular() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), FEMALE, LEFT)
    assert_true(femur_occupancy(dims, dims.medial_condyle) == TRABECULAR_FILL)


def test_just_inside_the_head_is_cortical() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var radius = dims.head_diameter.value * Float32(0.5)
    var shell = Vector3(
        dims.head_center.x + radius - Float32(0.002),
        dims.head_center.y,
        dims.head_center.z,
    )
    assert_true(femur_occupancy(dims, shell) == CORTICAL_FILL)


def test_midshaft_cavity_is_marrow() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var field = FemurField(dims)
    assert_true(femur_occupancy(dims, field.s2) == MARROW)


def test_distal_shaft_center_is_not_marrow() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var field = FemurField(dims)
    assert_true(femur_occupancy(dims, field.s0) != MARROW)


def test_proximal_shaft_center_is_not_marrow() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var field = FemurField(dims)
    assert_true(femur_occupancy(dims, field.s4) != MARROW)


def test_apparent_density_matches_the_fill() raises:
    var cortical = cortical_tissue()
    var trabecular = trabecular_tissue()
    assert_equal(
        apparent_density_of(EMPTY, cortical, trabecular).value, Float32(0)
    )
    assert_equal(
        apparent_density_of(MARROW, cortical, trabecular).value, Float32(0)
    )
    assert_equal(
        apparent_density_of(CORTICAL_FILL, cortical, trabecular).value,
        cortical.apparent_density().value,
    )
    assert_equal(
        apparent_density_of(TRABECULAR_FILL, cortical, trabecular).value,
        trabecular.apparent_density().value,
    )
    with assert_raises():
        _ = apparent_density_of(BoneOccupancy(9), cortical, trabecular)


def test_six_foot_male_mass_is_a_few_hundred_grams() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = femur_mass(person, RIGHT, Length(20.0, MILLIMETER))
    var grams = report.mass.to(GRAM)
    assert_true(grams > Float32(80))
    assert_true(grams < Float32(1500))
    var envelope_cm3 = report.envelope.to(CUBIC_CENTIMETER)
    assert_true(envelope_cm3 > Float32(50))
    assert_true(envelope_cm3 < Float32(2000))
    var region = report.cortical_region.value + report.trabecular_region.value
    assert_true(report.envelope.value >= region)
    assert_true(report.cortical_region.value > 0)
    assert_true(report.trabecular_region.value > 0)
    assert_true(report.solid_tissue.value > 0)
    assert_true(report.solid_tissue.value < region)
    var weight = report.weight()
    assert_almost_equal(
        weight.value, report.mass.value * STANDARD_GRAVITY.value, atol=TOLERANCE
    )
    assert_true(weight.to(NEWTON) > Float32(0.5))
    var moon = report.weight(STANDARD_GRAVITY.scaled(0.165))
    assert_true(moon < weight)


def test_full_porosity_has_no_mass_but_keeps_regions() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var cortical = cortical_tissue()
    cortical.porosity = Float32(1)
    var trabecular = trabecular_tissue()
    trabecular.porosity = Float32(1)
    var report = femur_mass_from_dimensions(
        dims, cortical, trabecular, Length(20.0, MILLIMETER)
    )
    assert_equal(report.mass.value, Float32(0))
    assert_equal(report.solid_tissue.value, Float32(0))
    assert_true(report.cortical_region.value > 0)
    assert_true(report.trabecular_region.value > 0)
    assert_true(report.envelope.value > 0)


def test_left_and_right_masses_agree() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var step = Length(20.0, MILLIMETER)
    var right = femur_mass(person, RIGHT, step)
    var left = femur_mass(person, LEFT, step)
    var scale = right.mass.value
    if scale < left.mass.value:
        scale = left.mass.value
    var gap = right.mass.value - left.mass.value
    if gap < 0:
        gap = -gap
    assert_true(gap < scale * Float32(0.15))


def test_a_taller_femur_has_more_mass() raises:
    var step = Length(20.0, MILLIMETER)
    var short = femur_mass(HumanoidSpec(Length(5.0, FOOT), FEMALE), LEFT, step)
    var tall = femur_mass(HumanoidSpec(Length(6.5, FOOT), MALE), RIGHT, step)
    assert_true(tall.mass > short.mass)
    assert_true(tall.envelope > short.envelope)


def test_add_fill_counts_every_occupancy() raises:
    var cortical = cortical_tissue()
    var trabecular = trabecular_tissue()
    var tally = Tally(0, 0, 0, 0, 0)
    add_fill(tally, EMPTY, 1.0, cortical, trabecular)
    assert_equal(tally.envelope, Float32(0))
    assert_equal(tally.mass, Float32(0))
    add_fill(tally, CORTICAL_FILL, 2.0, cortical, trabecular)
    assert_almost_equal(tally.cortical, Float32(2), atol=TOLERANCE)
    assert_almost_equal(tally.solid, Float32(2) * Float32(0.90), atol=TOLERANCE)
    add_fill(tally, TRABECULAR_FILL, 3.0, cortical, trabecular)
    assert_almost_equal(tally.trabecular, Float32(3), atol=TOLERANCE)
    var mass_before = tally.mass
    add_fill(tally, MARROW, 4.0, cortical, trabecular)
    assert_almost_equal(tally.envelope, Float32(9), atol=TOLERANCE)
    assert_equal(tally.mass, mass_before)
    with assert_raises():
        add_fill(tally, BoneOccupancy(9), 1.0, cortical, trabecular)


def test_a_span_shorter_than_the_step_still_has_one_cell() raises:
    assert_equal(grid_cells(Float32(0.01), Float32(1.0)), 1)
    assert_true(grid_cells(Float32(0.55), Float32(0.005)) > 1)


def test_refuses_a_short_mass_step() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims, cortical_tissue(), trabecular_tissue(), MIN_STEP.scaled(0.5)
        )


def test_refuses_a_long_mass_step() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            MAX_STEP + Length(1.0, MILLIMETER),
        )


def test_refuses_a_non_finite_mass_step() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(nan[DType.float32](), MILLIMETER),
        )
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(inf[DType.float32](), MILLIMETER),
        )


def test_mass_refuses_invalid_tissue() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var bad = cortical_tissue()
    bad.kind = BoneKind(9)
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims, bad, trabecular_tissue(), Length(10.0, MILLIMETER)
        )
    var worse = trabecular_tissue()
    worse.kind = BoneKind(9)
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims, cortical_tissue(), worse, Length(10.0, MILLIMETER)
        )


def _max_positive_centroid(
    bone: BufferGeometry, field: FemurField
) raises -> Float32:
    """Return the largest positive field value at a triangle centroid."""
    ref pos = bone.attribute_view(String(POSITION))
    var worst = Float32(0)
    for triangle in range(bone.triangle_count()):
        var ia = bone.corner_index(triangle, 0)
        var ib = bone.corner_index(triangle, 1)
        var ic = bone.corner_index(triangle, 2)
        var a = pos.vector3(ia)
        var b = pos.vector3(ib)
        var c = pos.vector3(ic)
        var centroid = Vector3(
            (a.x + b.x + c.x) * Float32(1.0 / 3.0),
            (a.y + b.y + c.y) * Float32(1.0 / 3.0),
            (a.z + b.z + c.z) * Float32(1.0 / 3.0),
        )
        var d = field.distance(centroid)
        if d > worst:
            worst = d
    return worst


def _assert_outward_and_short(bone: BufferGeometry) raises:
    """Refuse a triangle that winds against its stored normals or spans a gap.
    """
    ref pos = bone.attribute_view(String(POSITION))
    ref normals = bone.attribute_view(String(NORMAL))
    for triangle in range(bone.triangle_count()):
        var ia = bone.corner_index(triangle, 0)
        var ib = bone.corner_index(triangle, 1)
        var ic = bone.corner_index(triangle, 2)
        var a = pos.vector3(ia)
        var b = pos.vector3(ib)
        var c = pos.vector3(ic)
        var ab = b - a
        var ac = c - a
        var bc = c - b
        assert_true(ab.length() < Float32(0.08))
        assert_true(ac.length() < Float32(0.08))
        assert_true(bc.length() < Float32(0.08))
        ab.cross(ac)
        if ab.length() < Float32(1e-10):
            continue
        var mean = (
            normals.vector3(ia) + normals.vector3(ib) + normals.vector3(ic)
        )
        assert_true(ab.dot(mean) > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
