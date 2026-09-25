# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the transforms of `BufferGeometry` and `BufferAttribute`, the
draw range, and integer attributes.

Every expected number comes from three.js 0.180 run in Node.
"""

from core.buffer_attribute import BufferAttribute, typed_value
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    TANGENT,
    UV,
    WHOLE_STREAM,
    BufferGeometry,
    DrawRange,
)
from core.interleaved_buffer import InterleavedBuffer
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.utils import (
    ComponentType,
    FLOAT32_COMPONENT,
    INT16_COMPONENT,
    INT32_COMPONENT,
    INT8_COMPONENT,
    UINT16_COMPONENT,
    UINT32_COMPONENT,
    UINT8_COMPONENT,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, Length, METER, RADIAN


def _numbers(attribute: BufferAttribute) raises -> List[Float32]:
    """Return every number an attribute reads, item after item."""
    return attribute.packed()


def _match(
    got: List[Float32], want: List[Float64], tolerance: Float64 = 1e-5
) raises:
    """Assert two lists of numbers agree to a tolerance."""
    assert_equal(len(got), len(want))
    for at in range(len(want)):
        assert_almost_equal(Float64(got[at]), want[at], atol=tolerance)


def _triangle() raises -> BufferGeometry:
    """Return one triangle with a normal and a tangent at each corner."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([0.0, 0, 0, 1, 0, 0, 0, 2, 1], 3)
    )
    geometry.set_attribute(
        NORMAL, BufferAttribute([0.0, 0, 1, 0, 1, 0, 0.6, 0, 0.8], 3)
    )
    geometry.set_attribute(
        TANGENT,
        BufferAttribute([1.0, 0, 0, 1, 0, 0, 1, -1, 0.8, 0.6, 0, 1], 4),
    )
    return geometry^


def _matrix4() -> Matrix4:
    """Return the matrix the Node run used, three.js's `set` row by row."""
    var matrix = Matrix4()
    matrix.set(1, 0.5, 0, 2, 0, 2, 0.25, -1, 0.1, 0, 1, 3, 0, 0, 0.1, 1)
    return matrix


# --- typed storage ----------------------------------------------------------


def test_a_typed_array_wraps_and_truncates() raises:
    assert_equal(typed_value(300, UINT8_COMPONENT), 44)
    assert_equal(typed_value(-1, UINT8_COMPONENT), 255)
    assert_equal(typed_value(3.7, INT16_COMPONENT), 3)
    assert_equal(typed_value(-3.7, INT16_COMPONENT), -3)
    assert_equal(typed_value(40000, INT16_COMPONENT), -25536)
    assert_equal(typed_value(-129, INT8_COMPONENT), 127)
    assert_equal(typed_value(70000, UINT16_COMPONENT), 4464)
    assert_equal(typed_value(4294967296 + 5, UINT32_COMPONENT), 5)
    assert_equal(typed_value(2147483648, INT32_COMPONENT), -2147483648)
    assert_equal(typed_value(Float64.MAX * 2, UINT8_COMPONENT), 0)
    with assert_raises(contains="integer component"):
        _ = typed_value(1, FLOAT32_COMPONENT)
    with assert_raises(contains="integer component"):
        _ = typed_value(1, ComponentType(9))


def test_a_normalized_uint8_reads_and_writes_as_three_js_does() raises:
    var attribute = BufferAttribute(
        [0, 128, 255, 300, -1], 1, UINT8_COMPONENT, True
    )
    assert_true(attribute.is_integer())
    assert_true(attribute.is_normalized())
    assert_true(attribute.component_type() == UINT8_COMPONENT)
    assert_equal(attribute.stored_values(), [0, 128, 255, 44, 255])
    _match(
        _numbers(attribute),
        [0, 0.5019607843137255, 1, 0.17254901960784313, 1],
    )
    attribute.set_component(0, 0, 0.5)
    attribute.set_component(1, 0, 1.2)
    # -0.2 and not three.js's -0.1: a `Float32` of -0.1 is a little past
    # it, and so past the half that `normalize` rounds at.
    attribute.set_component(2, 0, -0.2)
    assert_equal(attribute.stored_values(), [128, 50, 205, 44, 255])


def test_a_signed_normalized_type_reads_minus_one_at_its_least() raises:
    var attribute = BufferAttribute([-128, 127, 0], 1, INT8_COMPONENT, True)
    _match(_numbers(attribute), [-1, 1, 0])
    attribute.set_component(0, 0, -1)
    attribute.set_component(1, 0, -0.5)
    attribute.set_component(2, 0, 0.25)
    assert_equal(attribute.stored_values(), [-127, -63, 32])


def test_an_integer_type_that_is_not_normalized_truncates() raises:
    var attribute = BufferAttribute([0, 0, 0], 1, INT16_COMPONENT)
    assert_false(attribute.is_normalized())
    attribute.set_component(0, 0, 3.7)
    attribute.set_component(1, 0, -3.7)
    attribute.set_component(2, 0, 40000)
    assert_equal(attribute.stored_values(), [3, -3, -25536])
    _match(_numbers(attribute), [3, -3, -25536])


def test_wide_types_normalize_as_three_js_does() raises:
    var wide = BufferAttribute([0, 0], 1, UINT32_COMPONENT, True)
    wide.set_component(0, 0, 0.5)
    wide.set_component(1, 0, 0.25)
    assert_equal(wide.stored_values(), [2147483648, 1073741824])
    _match(_numbers(wide), [0.5000000001164153, 0.25000000005820766])
    var short = BufferAttribute([0, 0], 1, UINT16_COMPONENT, True)
    short.set_component(0, 0, 0.3)
    assert_equal(short.stored_values(), [19661, 0])
    _match(_numbers(short), [0.30000762951094834, 0])


def test_the_normalized_flag_changes_the_reads_and_not_the_integers() raises:
    var attribute = BufferAttribute([255, 51], 1, UINT8_COMPONENT)
    _match(_numbers(attribute), [255, 51])
    attribute.set_normalized(True)
    _match(_numbers(attribute), [1, 0.2])
    assert_equal(attribute.stored_values(), [255, 51])
    # A float attribute carries the flag and reads the same.
    var floats = BufferAttribute([0.5], 1)
    floats.set_normalized(True)
    assert_true(floats.is_normalized())
    _match(_numbers(floats), [0.5])
    assert_false(floats.is_integer())
    with assert_raises(contains="stores no integers"):
        _ = floats.stored_values()


def test_a_float32_component_from_integers_stores_floats() raises:
    var attribute = BufferAttribute([1, 2], 2, FLOAT32_COMPONENT, True)
    assert_false(attribute.is_integer())
    assert_true(attribute.is_normalized())
    _match(_numbers(attribute), [1, 2])
    with assert_raises(contains="valid component type"):
        _ = BufferAttribute([1], 1, ComponentType(7))
    with assert_raises(contains="valid component type"):
        _ = BufferAttribute([1], 1, ComponentType(-1))


def test_an_integer_attribute_keeps_its_type_through_copies() raises:
    var attribute = BufferAttribute([1, 2, 3, 4, 5, 6], 2, INT8_COMPONENT, True)
    var cloned = attribute.clone()
    assert_true(cloned.component_type() == INT8_COMPONENT)
    assert_true(cloned.is_normalized())
    assert_equal(cloned.stored_values(), [1, 2, 3, 4, 5, 6])
    var gathered = attribute.gather([2, 0])
    assert_equal(gathered.stored_values(), [5, 6, 1, 2])
    assert_true(gathered.is_normalized())
    var copied = attribute.copy()
    assert_equal(copied.stored_values(), [1, 2, 3, 4, 5, 6])
    with assert_raises(contains="out of range"):
        _ = attribute.gather([3])
    # A float attribute keeps its flag through both too.
    var floats = BufferAttribute([0.5, 0.25], 1)
    floats.set_normalized(True)
    assert_true(floats.clone().is_normalized())
    assert_true(floats.gather([1]).is_normalized())


# --- attribute transforms ---------------------------------------------------


def test_apply_matrix3_moves_two_and_turns_three() raises:
    var matrix = Matrix3()
    matrix.set(1, 2, 3, 4, 5, 6, 7, 8, 10)
    var flat = BufferAttribute([1.0, 2, -1, 0.5], 2)
    flat.apply_matrix3(matrix)
    _match(_numbers(flat), [8, 20, 3, 4.5])
    var solid = BufferAttribute([1.0, 2, 3, -1, 0.5, 2], 3)
    solid.apply_matrix3(matrix)
    _match(_numbers(solid), [14, 32, 53, 6, 10.5, 17])
    # Four numbers an item are left alone, as in three.js.
    var four = BufferAttribute([1.0, 2, 3, 4], 4)
    four.apply_matrix3(matrix)
    _match(_numbers(four), [1, 2, 3, 4])
    # And an empty attribute has nothing to move.
    var empty = BufferAttribute(List[Float32](), 2)
    empty.apply_matrix3(matrix)
    var none = BufferAttribute(List[Float32](), 3)
    none.apply_matrix3(matrix)
    assert_equal(none.count(), 0)


def test_apply_matrix4_moves_points_with_the_divide() raises:
    var points = BufferAttribute([1.0, 2, 3, -1, 0.5, 2], 3)
    points.apply_matrix4(_matrix4())
    _match(
        _numbers(points),
        [
            3.076923131942749,
            2.884615421295166,
            4.692307472229004,
            1.0416666269302368,
            0.4166666567325592,
            4.083333492279053,
        ],
    )
    with assert_raises(contains="three numbers or more"):
        var flat = BufferAttribute([1.0, 2], 2)
        flat.apply_matrix4(_matrix4())


def test_apply_normal_matrix_turns_and_normalizes() raises:
    var normals = BufferAttribute([1.0, 2, 3, -1, 0.5, 2], 3)
    normals.apply_normal_matrix(Matrix3.normal_matrix(_matrix4()))
    _match(
        _numbers(normals),
        [
            0.24011880159378052,
            0.2732386291027069,
            0.9314953684806824,
            -0.521334707736969,
            0.2401961088180542,
            0.8188503384590149,
        ],
    )
    with assert_raises(contains="three numbers"):
        var flat = BufferAttribute([1.0, 2], 2)
        flat.apply_normal_matrix(Matrix3())


def test_transform_direction_keeps_the_fourth_number() raises:
    var tangents = BufferAttribute([1.0, 2, 3, 1, -1, 0.5, 2, -1], 4)
    tangents.transform_direction(_matrix4())
    _match(
        _numbers(tangents),
        [
            0.33253759145736694,
            0.7897767424583435,
            0.5154332518577576,
            1,
            -0.2959437668323517,
            0.5918875336647034,
            0.7497242093086243,
            -1,
        ],
    )
    with assert_raises(contains="three numbers or more"):
        var flat = BufferAttribute([1.0, 2], 2)
        flat.transform_direction(_matrix4())


def test_a_transform_of_quantized_positions_quantizes_again() raises:
    var points = BufferAttribute(
        [0, 0, 0, 16384, 0, -16384], 3, INT16_COMPONENT, True
    )
    var move = Matrix4()
    move.set(1, 0, 0, 0.25, 0, 1, 0, 0.1, 0, 0, 1, 0, 0, 0, 0, 1)
    points.apply_matrix4(move)
    assert_equal(points.stored_values(), [8192, 3277, 0, 24576, 3277, -16384])


def test_set_writes_the_array_as_it_stores() raises:
    var attribute = BufferAttribute([0, 0, 0, 0], 2, UINT8_COMPONENT, True)
    attribute.set([Float32(255), 3.9, 300], 1)
    assert_equal(attribute.stored_values(), [0, 255, 3, 44])
    attribute.set_stored([7])
    assert_equal(attribute.stored_values(), [7, 255, 3, 44])
    var floats = BufferAttribute([0.0, 0, 0], 3)
    floats.set([Float32(1.5), 2.5], 1)
    _match(_numbers(floats), [0, 1.5, 2.5])
    floats.set_stored([4])
    _match(_numbers(floats), [4, 1.5, 2.5])
    with assert_raises(contains="do not fit"):
        floats.set([Float32(1), 2], 2)
    with assert_raises(contains="do not fit"):
        floats.set_stored([1], -1)
    var shared = BufferAttribute(InterleavedBuffer([1.0, 2, 3, 4], 2), 1, 0)
    with assert_raises(contains="no array of its own"):
        shared.set_stored([1])


def test_copy_at_copies_the_stored_numbers() raises:
    var target = BufferAttribute([1, 2, 3, 4, 5, 6], 2, UINT8_COMPONENT, True)
    var source = BufferAttribute([-5, 600, 7, 9, 10, 11], 3, INT16_COMPONENT)
    target.copy_at(1, source, 1)
    assert_equal(target.stored_values(), [1, 2, 9, 10, 5, 6])
    target.copy_at(0, source, 0)
    assert_equal(target.stored_values(), [251, 88, 9, 10, 5, 6])
    var floats = BufferAttribute([0.0, 0], 2)
    floats.copy_at(0, target, 2)
    _match(_numbers(floats), [5, 6])
    with assert_raises(contains="fewer numbers"):
        source.copy_at(0, floats, 0)
    with assert_raises(contains="out of range"):
        floats.copy_at(0, target, 3)
    with assert_raises(contains="out of range"):
        floats.copy_at(0, target, -1)
    with assert_raises(contains="do not fit"):
        floats.copy_at(1, target, 0)
    var shared = BufferAttribute(InterleavedBuffer([1.0, 2, 3, 4], 2), 2, 0)
    with assert_raises(contains="no array of its own"):
        floats.copy_at(0, shared, 0)
    with assert_raises(contains="no array of its own"):
        shared.copy_at(0, floats, 0)


# --- geometry transforms ----------------------------------------------------


def _check(geometry: BufferGeometry, name: String, want: List[Float64]) raises:
    """Assert one attribute's numbers."""
    _match(_numbers(geometry.attribute_view(name)), want)


def test_apply_matrix4_moves_positions_normals_and_tangents() raises:
    var geometry = _triangle()
    geometry.apply_matrix4(_matrix4())
    _check(
        geometry,
        POSITION,
        [
            2,
            -1,
            3,
            3,
            -1,
            3.0999999046325684,
            2.7272727489471436,
            2.954545497894287,
            3.6363637447357178,
        ],
    )
    _check(
        geometry,
        NORMAL,
        [
            -0.09947294741868973,
            0.024868236854672432,
            0.9947294592857361,
            0.02424643188714981,
            0.9698572754859924,
            -0.2424643188714981,
            0.5229614973068237,
            -0.13074037432670593,
            0.8422697186470032,
        ],
    )
    _check(
        geometry,
        TANGENT,
        [
            0.9950371980667114,
            0,
            0.09950371831655502,
            1,
            0,
            0.24253562092781067,
            0.9701424837112427,
            -1,
            0.6749101281166077,
            0.7362655997276306,
            0.04908437281847,
            1,
        ],
    )


def test_rotations_turn_the_geometry_about_each_axis() raises:
    var about_x = _triangle()
    about_x.rotate_x(Angle(0.5, RADIAN))
    _check(
        about_x,
        POSITION,
        [0, 0, 0, 1, 0, 0, 0, 1.2757395505905151, 1.8364336490631104],
    )
    _check(
        about_x,
        TANGENT,
        [
            1,
            0,
            0,
            1,
            0,
            -0.4794255495071411,
            0.8775825500488281,
            -1,
            0.800000011920929,
            0.5265495181083679,
            0.2876553237438202,
            1,
        ],
    )
    var about_y = _triangle()
    about_y.rotate_y(Angle(0.5, RADIAN))
    _check(
        about_y,
        NORMAL,
        [
            0.4794255495071411,
            0,
            0.8775825500488281,
            0,
            1,
            0,
            0.9100899696350098,
            0,
            0.41441071033477783,
        ],
    )
    var about_z = _triangle()
    about_z.rotate_z(Angle(0.5, RADIAN))
    _check(
        about_z,
        POSITION,
        [
            0,
            0,
            0,
            0.8775825500488281,
            0.4794255495071411,
            0,
            -0.9588510990142822,
            1.7551651000976562,
            1,
        ],
    )


def test_translate_moves_positions_and_not_normals() raises:
    var geometry = _triangle()
    geometry.translate(Length(1, METER), Length(-2, METER), Length(3, METER))
    _check(geometry, POSITION, [1, -2, 3, 2, -2, 3, 1, 0, 4])
    _check(geometry, NORMAL, [0, 0, 1, 0, 1, 0, 0.6, 0, 0.8])


def test_scale_squashes_the_normals_the_other_way() raises:
    var geometry = _triangle()
    geometry.scale(2, 1, 0.5)
    _check(geometry, POSITION, [0, 0, 0, 2, 0, 0, 0, 2, 0.5])
    _check(
        geometry,
        NORMAL,
        [0, 0, 1, 0, 1, 0, 0.18428854644298553, 0, 0.9828721880912781],
    )
    _check(
        geometry,
        TANGENT,
        [1, 0, 0, 1, 0, 0, 1, -1, 0.936329185962677, 0.3511234521865845, 0, 1],
    )
    # A flattening scale leaves a normal nothing to be square to.
    var flat = _triangle()
    with assert_raises(contains="collapses a dimension"):
        flat.scale(1, 0, 1)


def test_apply_quaternion_rotates() raises:
    var turn = Quaternion(0.1, 0.2, 0.3, 0.9)
    turn.normalize()
    var geometry = _triangle()
    geometry.apply_quaternion(turn)
    _check(
        geometry,
        POSITION,
        [
            0,
            0,
            0,
            0.7263157963752747,
            0.6105263233184814,
            -0.31578946113586426,
            -0.6105263233184814,
            1.51578950881958,
            1.5263158082962036,
        ],
    )


def test_look_at_points_plus_z_at_the_target() raises:
    var geometry = _triangle()
    geometry.look_at(Vector3(1, 2, 3))
    _check(
        geometry,
        POSITION,
        [
            0,
            0,
            0,
            0.9486833214759827,
            0,
            -0.3162277638912201,
            -0.07080046087503433,
            2.2248311042785645,
            -0.2124013751745224,
        ],
    )
    _check(
        geometry,
        NORMAL,
        [
            0.26726123690605164,
            0.5345224738121033,
            0.8017837405204773,
            -0.16903084516525269,
            0.8451542258262634,
            -0.5070925354957581,
            0.7830190062522888,
            0.42761799693107605,
            0.45169031620025635,
        ],
    )


def test_a_transform_without_positions_or_normals_is_harmless() raises:
    var empty = BufferGeometry()
    empty.apply_matrix4(_matrix4())
    assert_equal(empty.attribute_count(), 0)
    # Normals without positions turn on their own.
    var turned = BufferGeometry()
    turned.set_attribute(NORMAL, BufferAttribute([0.0, 0, 1], 3))
    turned.rotate_x(Angle(0.5, RADIAN))
    _check(turned, NORMAL, [0, -0.4794255495071411, 0.8775825500488281])


def test_morph_targets_follow_the_transform() raises:
    var geometry = _triangle()
    geometry.add_morph_target(
        BufferAttribute([0.0, 0, 1, 1, 0, 1, 0, 2, 2], 3),
        BufferAttribute([0.0, 1, 0, 0, 1, 0, 0, 1, 0], 3),
    )
    geometry.translate(Length(1, METER), Length(0, METER), Length(0, METER))
    _match(_numbers(geometry.morph_positions[0]), [1, 0, 1, 2, 0, 1, 1, 2, 2])
    geometry.scale(1, 2, 1)
    _match(_numbers(geometry.morph_normals[0]), [0, 1, 0, 0, 1, 0, 0, 1, 0])
    # Offsets turn and do not move.
    var relative = _triangle()
    relative.add_morph_target(BufferAttribute([0.0, 1, 0, 0, 1, 0, 0, 1, 0], 3))
    relative.morph_relative = True
    relative.translate(Length(5, METER), Length(0, METER), Length(0, METER))
    relative.scale(1, 2, 1)
    _match(_numbers(relative.morph_positions[0]), [0, 2, 0, 0, 2, 0, 0, 2, 0])


def test_set_from_points_makes_or_fills_the_positions() raises:
    var geometry = BufferGeometry()
    geometry.set_from_points([Vector2(1, 2), Vector2(3, 4)])
    _check(geometry, POSITION, [1, 2, 0, 3, 4, 0])
    geometry.set_from_points(
        [Vector3(9, 9, 9), Vector3(8, 8, 8), Vector3(7, 7, 7)]
    )
    _check(geometry, POSITION, [9, 9, 9, 8, 8, 8])
    var flat = BufferGeometry()
    flat.set_attribute(POSITION, BufferAttribute([0.0, 0], 2))
    with assert_raises(contains="three numbers"):
        flat.set_from_points([Vector3(1, 2, 3)])
    var none = BufferGeometry()
    none.set_from_points(List[Vector3]())
    assert_equal(none.vertex_count(), 0)


def test_normalize_normals_makes_each_unit_length() raises:
    var geometry = _triangle()
    geometry.set_attribute(
        NORMAL, BufferAttribute([0.0, 0, 2, 3, 4, 0, 0, 0, 0], 3)
    )
    geometry.normalize_normals()
    _check(geometry, NORMAL, [0, 0, 1, 0.6, 0.8, 0, 0, 0, 0])
    geometry.delete_attribute(NORMAL)
    assert_false(geometry.has_attribute(NORMAL))
    with assert_raises(contains="no attribute named normal"):
        geometry.normalize_normals()
    geometry.set_attribute(NORMAL, BufferAttribute([0.0, 0], 2))
    with assert_raises(contains="three numbers"):
        geometry.normalize_normals()


def test_delete_attribute_removes_one_and_ignores_the_unknown() raises:
    var geometry = _triangle()
    geometry.delete_attribute(NORMAL)
    geometry.delete_attribute(UV)
    assert_equal(geometry.attribute_count(), 2)
    assert_true(geometry.has_attribute(POSITION))
    assert_true(geometry.has_attribute(TANGENT))


# --- draw range -------------------------------------------------------------


def test_a_draw_range_is_whole_until_set() raises:
    var geometry = _triangle()
    assert_true(geometry.draw_range == WHOLE_STREAM)
    geometry.set_draw_range(3, 6)
    assert_true(geometry.draw_range == DrawRange(3, 6))
    assert_false(geometry.draw_range == DrawRange(3, None))
    assert_equal(String(geometry.draw_range), "DrawRange(3, 6)")
    assert_equal(String(WHOLE_STREAM), "DrawRange(0, Infinity)")
    geometry.set_draw_range(1)
    assert_true(geometry.draw_range == DrawRange(1, None))
    with assert_raises(contains="negative distance"):
        geometry.set_draw_range(-1, 3)
    with assert_raises(contains="negative distance"):
        geometry.set_draw_range(0, -3)
    assert_false(DrawRange(0, -1).is_valid())
    assert_false(DrawRange(-1, None).is_valid())
    assert_true(DrawRange(0, 0).is_valid())


def _strip() raises -> BufferGeometry:
    """Return four triangles without an index: twelve vertices."""
    var numbers = List[Float32]()
    for vertex in range(12):
        numbers.append(Float32(vertex))
        numbers.append(0)
        numbers.append(0)
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(numbers^, 3))
    return geometry^


def test_a_drawn_run_is_the_group_inside_the_range() raises:
    var geometry = _strip()
    var whole = geometry.drawn_run(0, -1)
    assert_equal(whole[0], 0)
    assert_equal(whole[1], 4)
    geometry.set_draw_range(3, 6)
    var ranged = geometry.drawn_run(0, -1)
    assert_equal(ranged[0], 3)
    assert_equal(ranged[1], 2)
    # A group that starts later and runs past the range's end.
    var group = geometry.drawn_run(6, 6)
    assert_equal(group[0], 6)
    assert_equal(group[1], 1)
    # A group before the range draws nothing.
    var before = geometry.drawn_run(0, 3)
    assert_equal(before[1], 0)
    # Slots left over after the last whole triangle are not drawn.
    geometry.set_draw_range(1, 7)
    var odd = geometry.drawn_run(0, -1)
    assert_equal(odd[0], 1)
    assert_equal(odd[1], 2)
    # A range past the stream draws nothing.
    geometry.set_draw_range(20)
    assert_equal(geometry.drawn_run(0, -1)[1], 0)
    with assert_raises(contains="before the stream"):
        _ = geometry.drawn_run(-1, 3)
    geometry.draw_range = DrawRange(0, -3)
    with assert_raises(contains="negative distance"):
        _ = geometry.drawn_run(0, 3)


def test_drawn_vertices_clamps_the_range_to_the_vertices() raises:
    var geometry = _strip()
    var whole = geometry.drawn_vertices()
    assert_equal(whole[0], 0)
    assert_equal(whole[1], 12)
    geometry.set_draw_range(2, 5)
    var ranged = geometry.drawn_vertices()
    assert_equal(ranged[0], 2)
    assert_equal(ranged[1], 5)
    geometry.set_draw_range(10, 5)
    assert_equal(geometry.drawn_vertices()[1], 2)
    geometry.set_draw_range(30)
    var past = geometry.drawn_vertices()
    assert_equal(past[0], 12)
    assert_equal(past[1], 0)
    geometry.draw_range = DrawRange(-1, None)
    with assert_raises(contains="negative distance"):
        _ = geometry.drawn_vertices()


def test_a_clone_keeps_the_name_the_user_data_and_the_range() raises:
    var geometry = _triangle()
    geometry.name = "tri"
    geometry.user_data.set_number("a", 1)
    geometry.set_draw_range(0, 3)
    var copied = geometry.clone()
    assert_equal(copied.name, "tri")
    assert_equal(copied.user_data.number("a"), 1)
    assert_true(copied.draw_range == DrawRange(0, 3))


def test_a_geometry_of_integer_attributes_transforms_through_them() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION,
        BufferAttribute([0, 0, 0, 16384, 0, -16384], 3, INT16_COMPONENT, True),
    )
    geometry.set_attribute(
        COLOR,
        BufferAttribute([255, 0, 128, 0, 255, 0], 3, UINT8_COMPONENT, True),
    )
    geometry.translate(
        Length(0.25, METER), Length(0.1, METER), Length(0, METER)
    )
    assert_equal(
        geometry.attribute_view(POSITION).stored_values(),
        [8192, 3277, 0, 24576, 3277, -16384],
    )
    assert_equal(
        geometry.attribute_view(COLOR).stored_values(),
        [255, 0, 128, 0, 255, 0],
    )


def test_empty_attributes_have_nothing_to_move() raises:
    var none = BufferAttribute(List[Float32](), 3)
    none.apply_matrix4(_matrix4())
    none.apply_normal_matrix(Matrix3())
    none.transform_direction(_matrix4())
    none.set(List[Float32]())
    none.set_stored(List[Int]())
    assert_equal(none.count(), 0)
    var bytes = BufferAttribute(List[Int](), 3, UINT8_COMPONENT, True)
    assert_equal(bytes.count(), 0)
    assert_equal(bytes.gather(List[Int]()).count(), 0)
    # A float source is copied as its floats.
    var floats = BufferAttribute([1.5, 2.5], 2)
    var target = BufferAttribute([0, 0], 2, INT16_COMPONENT)
    target.copy_at(0, floats, 0)
    assert_equal(target.stored_values(), [1, 2])


def test_a_geometry_with_nothing_to_set_or_normalize_is_left_alone() raises:
    var geometry = _triangle()
    geometry.set_from_points(List[Vector3]())
    _check(geometry, POSITION, [0, 0, 0, 1, 0, 0, 0, 2, 1])
    var flat = BufferGeometry()
    flat.set_from_points(List[Vector2]())
    assert_equal(flat.vertex_count(), 0)
    flat.set_attribute(NORMAL, BufferAttribute(List[Float32](), 3))
    flat.normalize_normals()
    assert_equal(flat.attribute_view(NORMAL).count(), 0)


def test_morph_normals_turn_without_a_base_normal() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute([0.0, 0, 0], 3))
    geometry.add_morph_target(
        BufferAttribute([0.0, 0, 0], 3), BufferAttribute([0.0, 0, 1], 3)
    )
    geometry.rotate_x(Angle(0.5, RADIAN))
    _match(
        _numbers(geometry.morph_normals[0]),
        [0, -0.4794255495071411, 0.8775825500488281],
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
