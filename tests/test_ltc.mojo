# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `lights.ltc` and the rect area light: the tables, the lookup,
the form factors and the lighting that sums them, apart from any renderer."""

from core.layers import Layers
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import (
    DEFAULT_RECT_SIZE,
    RECT_AREA,
    directional_light,
    rect_area_light,
)
from lights.lighting import (
    DIELECTRIC_F0,
    ROUGHNESS_FLOOR,
    Lighting,
    Reflected,
    physical_surface,
)
from lights.ltc import (
    LTC_BIAS,
    LTC_FLOATS,
    LTC_PATH,
    LTC_SCALE,
    LTC_SIZE,
    LtcTables,
    load_ltc_tables,
    ltc_blend,
    ltc_clipped_sphere_form_factor,
    ltc_edge_vector_form_factor,
    ltc_evaluate,
    ltc_lookup,
    ltc_neighbor,
    ltc_texel,
    ltc_uv,
    rect_area_light as rect_terms,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import atan, inf, nan, pi, sqrt
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime UP = Vector3(0, 0, 1)
comptime ORIGIN = Vector3(0, 0, 0)
comptime WHITE = Color(255, 255, 255)
comptime IDENTITY = SIMD[DType.float32, 4](1, 0, 0, 1)
comptime EYE = Vector3(0, 0, 4)
# The four corners of a two-meter square at z = 1 shining down, as
# `rect_terms` lays them out from a half width along x and a half height
# along y.
comptime C0 = Vector3(1, -1, 1)
comptime C1 = Vector3(-1, -1, 1)
comptime C2 = Vector3(-1, 1, 1)
comptime C3 = Vector3(1, 1, 1)


def counting_table() -> List[Float32]:
    """Return a table whose every float is its texel's index, and whose
    fourth lane is the texel's column, so a lookup can be read back."""
    var table = List[Float32]()
    for row in range(LTC_SIZE):
        for column in range(LTC_SIZE):
            var texel = Float32(row * LTC_SIZE + column)
            table.append(texel)
            table.append(texel)
            table.append(texel)
            table.append(Float32(column))
    return table^


def a_chalk() -> Reflected:
    """Return a white dielectric's three colors."""
    return physical_surface(Vector3(1, 1, 1), DIELECTRIC_F0, 0, 1)


def axis_form_factor(half: Float32, height: Float32) -> Float32:
    """Return the exact form factor from a point to a parallel square of
    `half` half-size centered `height` above it: four times the corner
    formula for a rectangle seen from a point over one corner."""
    var a = half / height
    var edge = a / sqrt(1 + a * a)
    return Float32(2 / pi) * 2 * edge * atan(edge)


def rect_scene(
    x: Float32,
    y: Float32,
    z: Float32,
    intensity: Float32 = 1,
    width: Length = Length(2.0, METER),
    height: Length = Length(2.0, METER),
) raises -> Scene:
    """Return a scene with one white rectangle of light at a point, shining
    down -z, and a second node at the origin."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(x, y, z)
    var node = scene.add(lamp^)
    _ = scene.add(Object3D())
    scene.add_light(rect_area_light(WHITE, node, intensity, width, height))
    scene.update()
    return scene^


def lit_rect(scene: Scene) raises -> Lighting:
    """Return the scene's lighting with the tables loaded, seen from `EYE`."""
    return Lighting(scene, Layers.all(), EYE, ltc=load_ltc_tables())


# --- the tables -------------------------------------------------------------


def test_the_tables_load_from_the_repository_file() raises:
    # Two tables of sixty-four squared texels, four floats each: the first
    # texel of the first is the identity transform, and the corner texels
    # match three.js's `LTC_MAT_1` and `LTC_MAT_2` sources.
    var tables = load_ltc_tables()
    assert_true(tables.is_loaded())
    assert_equal(len(tables.first), LTC_FLOATS)
    assert_equal(len(tables.second), LTC_FLOATS)
    assert_equal(tables.first[0], Float32(1))
    assert_equal(tables.first[1], Float32(0))
    assert_equal(tables.first[2], Float32(0))
    assert_almost_equal(tables.first[3], Float32(2e-5), atol=1e-9)
    assert_equal(tables.second[0], Float32(1))
    var last = (LTC_SIZE * LTC_SIZE - 1) * 4
    assert_almost_equal(tables.first[last], Float32(0.99638897), atol=1e-6)
    assert_almost_equal(tables.first[last + 3], Float32(1.6577), atol=1e-4)
    assert_almost_equal(tables.second[last], Float32(0.93216401), atol=1e-6)
    assert_equal(tables.second[last + 3], Float32(1))
    assert_equal(LTC_PATH, "assets/ltc.f32")
    # None until loaded.
    assert_false(LtcTables().is_loaded())


def test_a_file_or_a_list_of_the_wrong_length_is_refused() raises:
    var short = Path("out/ltc_short.f32")
    short.write_text("sixteen bytes...")
    with assert_raises():
        _ = load_ltc_tables("out/ltc_short.f32")
    with assert_raises():
        _ = load_ltc_tables("out/no_such_ltc.f32")
    var full = List[Float32]()
    for _ in range(LTC_FLOATS):
        full.append(0)
    var less = List[Float32]()
    for _ in range(LTC_FLOATS - 1):
        less.append(0)
    with assert_raises():
        _ = LtcTables(full.copy(), less.copy())
    with assert_raises():
        _ = LtcTables(less.copy(), full.copy())
    assert_true(LtcTables(full.copy(), full.copy()).is_loaded())


# --- the lookup -------------------------------------------------------------


def test_the_lookup_coordinate_is_squeezed_onto_the_texel_centers() raises:
    # Head on and smooth reads the first texel's center; grazing and rough
    # reads the last's. Across by the roughness, down by the angle.
    var first = ltc_uv(1, 0)
    assert_almost_equal(first.x, LTC_BIAS, atol=1e-7)
    assert_almost_equal(first.y, LTC_BIAS, atol=1e-7)
    var last = ltc_uv(0, 1)
    assert_almost_equal(last.x, LTC_SCALE + LTC_BIAS, atol=1e-7)
    assert_almost_equal(last.y, LTC_SCALE + LTC_BIAS, atol=1e-7)
    var half = ltc_uv(0.75, 0.5)
    assert_almost_equal(half.x, 0.5 * LTC_SCALE + LTC_BIAS, atol=1e-7)
    assert_almost_equal(half.y, 0.5 * LTC_SCALE + LTC_BIAS, atol=1e-7)
    assert_almost_equal(LTC_SCALE, Float32(63) / 64, atol=1e-7)
    assert_almost_equal(LTC_BIAS, Float32(0.5) / 64, atol=1e-7)


def test_a_texel_center_reads_one_texel_and_a_midpoint_blends_two() raises:
    var at_first = ltc_texel(Vector2(LTC_BIAS, LTC_BIAS))
    assert_equal(at_first[0], Float32(0))
    assert_equal(at_first[1], Float32(0))
    assert_almost_equal(at_first[2], Float32(0), atol=1e-5)
    assert_almost_equal(at_first[3], Float32(0), atol=1e-5)
    var at_last = ltc_texel(Vector2(LTC_SCALE + LTC_BIAS, LTC_SCALE + LTC_BIAS))
    assert_equal(at_last[0], Float32(LTC_SIZE - 1))
    assert_equal(at_last[1], Float32(LTC_SIZE - 1))
    assert_almost_equal(at_last[2], Float32(0), atol=1e-5)
    # Between the first two columns, and the third and fourth rows.
    var between = ltc_texel(
        Vector2(Float32(1) / LTC_SIZE, Float32(3) / LTC_SIZE)
    )
    assert_equal(between[0], Float32(0))
    assert_equal(between[1], Float32(2))
    assert_almost_equal(between[2], Float32(0.5), atol=1e-5)
    assert_almost_equal(between[3], Float32(0.5), atol=1e-5)
    # Outside the table, the edges are held.
    var below = ltc_texel(Vector2(-1, -1))
    assert_equal(below[0], Float32(0))
    assert_equal(below[2], Float32(0))
    var beyond = ltc_texel(Vector2(2, 2))
    assert_equal(beyond[0], Float32(LTC_SIZE - 1))
    assert_equal(beyond[1], Float32(LTC_SIZE - 1))
    # A neighbor one past the last column or row is the last.
    assert_equal(ltc_neighbor(0, 0), 0)
    assert_equal(ltc_neighbor(1, 0), 4)
    assert_equal(ltc_neighbor(0, 1), LTC_SIZE * 4)
    assert_equal(ltc_neighbor(LTC_SIZE, 0), (LTC_SIZE - 1) * 4)
    assert_equal(ltc_neighbor(0, LTC_SIZE), (LTC_SIZE - 1) * LTC_SIZE * 4)
    assert_equal(
        ltc_neighbor(LTC_SIZE, LTC_SIZE), (LTC_SIZE * LTC_SIZE - 1) * 4
    )


def test_the_lookup_is_bilinear() raises:
    var table = counting_table()
    var first = ltc_lookup(table, Vector2(LTC_BIAS, LTC_BIAS))
    assert_almost_equal(first[0], Float32(0), atol=1e-3)
    var last = ltc_lookup(
        table, Vector2(LTC_SCALE + LTC_BIAS, LTC_SCALE + LTC_BIAS)
    )
    assert_almost_equal(last[0], Float32(LTC_SIZE * LTC_SIZE - 1), atol=1e-2)
    assert_almost_equal(last[3], Float32(LTC_SIZE - 1), atol=1e-3)
    # Halfway between columns zero and one on row zero: half a texel.
    var across = ltc_lookup(table, Vector2(Float32(1) / LTC_SIZE, LTC_BIAS))
    assert_almost_equal(across[0], Float32(0.5), atol=1e-3)
    assert_almost_equal(across[3], Float32(0.5), atol=1e-3)
    # Halfway between rows zero and one: half a row of texels.
    var down = ltc_lookup(table, Vector2(LTC_BIAS, Float32(1) / LTC_SIZE))
    assert_almost_equal(down[0], Float32(LTC_SIZE) * 0.5, atol=1e-3)
    assert_almost_equal(down[3], Float32(0), atol=1e-3)
    # The blend itself, on four made-up texels.
    var blend = ltc_blend(
        SIMD[DType.float32, 4](0, 0, 0, 0),
        SIMD[DType.float32, 4](1, 0, 0, 0),
        SIMD[DType.float32, 4](0, 1, 0, 0),
        SIMD[DType.float32, 4](1, 1, 0, 8),
        0.25,
        0.5,
    )
    assert_almost_equal(blend[0], Float32(0.25), atol=1e-6)
    assert_almost_equal(blend[1], Float32(0.5), atol=1e-6)
    assert_almost_equal(blend[3], Float32(1), atol=1e-6)


# --- the form factors -------------------------------------------------------


def test_an_edge_at_a_right_angle_is_a_quarter_along_its_normal() raises:
    # theta / sin(theta) / 2pi at ninety degrees is a quarter, which the
    # rational fit reaches exactly; an edge of no length adds nothing; and
    # an edge past ninety degrees goes through the other branch.
    var quarter = ltc_edge_vector_form_factor(
        Vector3(1, 0, 0), Vector3(0, 1, 0)
    )
    assert_almost_equal(quarter.x, Float32(0), atol=1e-6)
    assert_almost_equal(quarter.y, Float32(0), atol=1e-6)
    assert_almost_equal(quarter.z, Float32(0.25), atol=1e-6)
    var none = ltc_edge_vector_form_factor(Vector3(1, 0, 0), Vector3(1, 0, 0))
    assert_equal(none.z, Float32(0))
    var wide = ltc_edge_vector_form_factor(
        Vector3(1, 0, 0), Vector3(-0.8, 0.6, 0)
    )
    # theta / sin(theta) / 2pi for cos(theta) = -0.8: 2.498 / 0.6 / 2pi.
    assert_almost_equal(
        wide.z / 0.6, Float32(2.4981 / 0.6 / (2 * pi)), atol=2e-3
    )
    # An edge folded straight back is held off the pole.
    var folded = ltc_edge_vector_form_factor(
        Vector3(1, 0, 0), Vector3(-1, 0, 0)
    )
    assert_equal(folded.z, Float32(0))
    # And the fit's other side is a mirror: the same for a negative cosine
    # as for its opposite, before the branch.
    var mirrored = ltc_edge_vector_form_factor(
        Vector3(1, 0, 0), Vector3(0.8, 0.6, 0)
    )
    assert_almost_equal(
        mirrored.z / 0.6, Float32(0.6435 / 0.6 / (2 * pi)), atol=2e-3
    )


def test_the_clipped_sphere_form_factor_is_one_overhead_and_zero_under() raises:
    assert_almost_equal(
        ltc_clipped_sphere_form_factor(Vector3(0, 0, 1)), Float32(1), atol=1e-6
    )
    assert_equal(ltc_clipped_sphere_form_factor(Vector3(0, 0, -1)), Float32(0))
    assert_equal(
        ltc_clipped_sphere_form_factor(Vector3(0, 0, -0.5)), Float32(0)
    )
    assert_almost_equal(
        ltc_clipped_sphere_form_factor(Vector3(0, 0, 0.5)),
        Float32(0.5),
        atol=1e-6,
    )


def test_a_square_overhead_is_seen_by_its_exact_form_factor() raises:
    # A two-meter square one meter up: 0.554 by the closed form, which the
    # rational fit and the clipped-sphere approximation reach within a
    # hundredth. A wide one fills the hemisphere, a far one vanishes.
    var near = ltc_evaluate(UP, UP, ORIGIN, IDENTITY, C0, C1, C2, C3)
    assert_almost_equal(near, axis_form_factor(1, 1), atol=1e-2)
    var wide = ltc_evaluate(
        UP,
        UP,
        ORIGIN,
        IDENTITY,
        Vector3(1000, -1000, 1),
        Vector3(-1000, -1000, 1),
        Vector3(-1000, 1000, 1),
        Vector3(1000, 1000, 1),
    )
    assert_almost_equal(wide, axis_form_factor(1000, 1), atol=1e-2)
    assert_true(wide > 0.97, "a huge square did not fill the hemisphere")
    var far = ltc_evaluate(UP, UP, Vector3(0, 0, -99), IDENTITY, C0, C1, C2, C3)
    assert_almost_equal(far, axis_form_factor(1, 100), atol=1e-4)
    assert_true(far < 2e-4, "a far square still lit")
    # Behind the rectangle, nothing: it shines one way.
    var behind = ltc_evaluate(
        -UP, -UP, Vector3(0, 0, 2), IDENTITY, C0, C1, C2, C3
    )
    assert_equal(behind, Float32(0))
    # Seen along the normal, the frame has no eye to lean on and takes
    # the axis least along the normal; the answer is the same as from any
    # other eye, and the same whichever axis that is.
    var leaning = ltc_evaluate(
        UP, Vector3(0.6, 0, 0.8), ORIGIN, IDENTITY, C0, C1, C2, C3
    )
    assert_almost_equal(leaning, near, atol=1e-5)
    var across = ltc_evaluate(
        Vector3(-1, 0, 0),
        Vector3(-1, 0, 0),
        Vector3(1, 0, 0),
        IDENTITY,
        Vector3(0, -1, 1),
        Vector3(0, -1, -1),
        Vector3(0, 1, -1),
        Vector3(0, 1, 1),
    )
    assert_almost_equal(across, near, atol=1e-5)
    # A surface turned to face sideways sees the square edge on.
    var sideways = ltc_evaluate(
        Vector3(1, 0, 0), Vector3(1, 0, 0), ORIGIN, IDENTITY, C0, C1, C2, C3
    )
    assert_true(sideways < near, "edge on was not dimmer")
    assert_true(sideways > 0, "edge on saw nothing")
    # A surface on the square's own plane, seen through the transform
    # that shrinks the world to a point: the corners land on the surface
    # and are left unnormalized rather than divided by zero.
    var squashed = ltc_evaluate(
        UP,
        UP,
        Vector3(0, 0, 1),
        SIMD[DType.float32, 4](0, 0, 0, 0),
        C0,
        C1,
        C2,
        C3,
    )
    assert_equal(squashed, Float32(0))


def test_the_rect_terms_take_the_identity_for_diffuse_and_the_table_for_specular() raises:
    # With the identity transform and a Fresnel of (1, 0), the specular is
    # the reflectance times the form factor and the diffuse the color
    # times it; with a Fresnel of (0, 1) the specular is one minus the
    # reflectance times it.
    var flat = axis_form_factor(1, 1)
    var chalk = a_chalk()
    var head_on = rect_terms(
        UP,
        UP,
        ORIGIN,
        Vector3(0, 0, 1),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        chalk.diffuse,
        chalk.specular,
        IDENTITY,
        SIMD[DType.float32, 4](1, 0, 0, 0),
    )
    assert_almost_equal(head_on.diffuse.x, flat, atol=1e-2)
    assert_almost_equal(head_on.specular.x, flat * 0.04, atol=1e-3)
    var grazing = rect_terms(
        UP,
        UP,
        ORIGIN,
        Vector3(0, 0, 1),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        chalk.diffuse,
        chalk.specular,
        IDENTITY,
        SIMD[DType.float32, 4](0, 1, 0, 0),
    )
    assert_almost_equal(grazing.specular.x, flat * 0.96, atol=1e-2)
    assert_almost_equal(grazing.diffuse.x, head_on.diffuse.x, atol=1e-7)
    # The table's first texel, a mirror seen head on, flattens the
    # rectangle onto the horizon: the mirror direction lands inside it
    # and the whole lobe is reflected, while the diffuse is unchanged.
    var mirror = rect_terms(
        UP,
        UP,
        ORIGIN,
        Vector3(0, 0, 1),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        chalk.diffuse,
        chalk.specular,
        SIMD[DType.float32, 4](1, 0, 0, 2e-5),
        SIMD[DType.float32, 4](1, 0, 0, 0),
    )
    assert_almost_equal(mirror.specular.x, Float32(0.04), atol=1e-3)
    assert_almost_equal(mirror.diffuse.x, head_on.diffuse.x, atol=1e-7)
    # From behind, both are zero.
    var behind = rect_terms(
        UP,
        UP,
        Vector3(0, 0, 2),
        Vector3(0, 0, 1),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        chalk.diffuse,
        chalk.specular,
        IDENTITY,
        SIMD[DType.float32, 4](1, 0, 0, 0),
    )
    assert_equal(behind.diffuse.x, Float32(0))
    assert_equal(behind.specular.x, Float32(0))


# --- the light --------------------------------------------------------------


def test_a_rect_area_light_carries_its_size_and_refuses_a_bad_one() raises:
    var glow = rect_area_light(WHITE, NodeId(0))
    assert_equal(glow.kind, RECT_AREA)
    assert_true(RECT_AREA.is_valid())
    assert_almost_equal(
        glow.width.to(METER), DEFAULT_RECT_SIZE.to(METER), atol=1e-6
    )
    assert_almost_equal(glow.height.to(METER), Float32(10), atol=1e-6)
    var sized = rect_area_light(
        WHITE, NodeId(0), 2.0, Length(3.0, METER), Length(0.5, METER)
    )
    assert_almost_equal(sized.width.to(METER), Float32(3), atol=1e-6)
    assert_almost_equal(sized.height.to(METER), Float32(0.5), atol=1e-6)
    assert_almost_equal(sized.intensity, Float32(2), atol=1e-6)
    with assert_raises():
        _ = rect_area_light(WHITE, NodeId(0), 1.0, Length(0.0, METER))
    with assert_raises():
        _ = rect_area_light(WHITE, NodeId(0), 1.0, height=Length(-1.0, METER))
    with assert_raises():
        _ = rect_area_light(
            WHITE, NodeId(0), 1.0, Length(nan[DType.float32](), METER)
        )
    with assert_raises():
        _ = rect_area_light(
            WHITE, NodeId(0), 1.0, height=Length(inf[DType.float32](), METER)
        )
    with assert_raises():
        _ = rect_area_light(WHITE, NodeId(0), -1.0)
    # A directional light carries no size, and validates without one.
    var sun = directional_light(WHITE, NodeId(0))
    assert_equal(sun.width.to(METER), Float32(0))


def test_a_rect_area_light_needs_the_tables() raises:
    var scene = rect_scene(0, 0, 1)
    with assert_raises():
        _ = Lighting(scene, Layers.all(), EYE)
    var lighting = lit_rect(scene)
    assert_equal(lighting.rect_count(), 1)
    assert_equal(lighting.count(), 0)
    # A scene without one resolves without them, and holds none.
    var plain = Scene()
    var bare = Lighting(plain, Layers.all(), EYE)
    assert_equal(bare.rect_count(), 0)
    assert_false(bare.ltc.is_loaded())
    assert_equal(Lighting.uniform().rect_count(), 0)


def test_a_rect_area_light_is_resolved_through_its_nodes_world_matrix() raises:
    var lighting = lit_rect(rect_scene(1, 2, 3, 0.5, Length(4.0, METER)))
    assert_almost_equal(lighting.rect_positions[0].x, Float32(1), atol=1e-6)
    assert_almost_equal(lighting.rect_positions[0].z, Float32(3), atol=1e-6)
    assert_almost_equal(lighting.rect_half_widths[0].x, Float32(2), atol=1e-6)
    assert_almost_equal(lighting.rect_half_widths[0].y, Float32(0), atol=1e-6)
    assert_almost_equal(lighting.rect_half_heights[0].y, Float32(1), atol=1e-6)
    assert_almost_equal(lighting.rect_radiances[0].r, Float32(0.5), atol=1e-6)
    # A turned node turns the rectangle, and its scale does not grow it:
    # three.js takes only the rotation of the world matrix, by
    # `extractRotation`, to the half width and half height.
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    lamp.set_scale(3, 4, 1)
    lamp.rotate_z(Angle(90.0, DEGREE))
    var node = scene.add(lamp^)
    scene.add_light(rect_area_light(WHITE, node, 1, Length(2.0, METER)))
    scene.update()
    var turned = lit_rect(scene)
    # The width now runs along y, one meter each way as the light says,
    # and the default ten-meter height along -x.
    assert_almost_equal(turned.rect_half_widths[0].x, Float32(0), atol=1e-5)
    assert_almost_equal(turned.rect_half_widths[0].y, Float32(1), atol=1e-5)
    assert_almost_equal(turned.rect_half_heights[0].x, Float32(-5), atol=1e-5)
    assert_almost_equal(turned.rect_half_heights[0].y, Float32(0), atol=1e-5)


def test_a_physical_surface_under_a_rectangle_takes_its_form_factor() raises:
    # A two-meter square one meter over a white chalk: the diffuse is the
    # closed-form factor, and the specular a rough surface's small share;
    # a smooth surface reflects the square's image more strongly. No
    # coat is lit by it, as three.js lights none.
    var lighting = lit_rect(rect_scene(0, 0, 1))
    var rough = lighting.physical_at(UP, UP, ORIGIN, a_chalk(), 1, 1, 0.5)
    assert_almost_equal(rough.diffuse.x, axis_form_factor(1, 1), atol=1e-2)
    assert_almost_equal(rough.diffuse.y, rough.diffuse.x, atol=1e-7)
    assert_true(rough.specular.x > 0, "a rough chalk reflected nothing")
    assert_true(rough.specular.x < 0.1, "a rough chalk reflected too much")
    assert_equal(rough.clearcoat.x, Float32(0))
    var smooth = lighting.physical_at(
        UP, UP, ORIGIN, a_chalk(), ROUGHNESS_FLOOR, 0, ROUGHNESS_FLOOR
    )
    assert_true(smooth.specular.x > rough.specular.x, "smooth was duller")
    assert_almost_equal(smooth.diffuse.x, rough.diffuse.x, atol=1e-6)
    # Twice the intensity is twice the light.
    var bright = lit_rect(rect_scene(0, 0, 1, 2)).physical_at(
        UP, UP, ORIGIN, a_chalk(), 1, 0, ROUGHNESS_FLOOR
    )
    assert_almost_equal(bright.diffuse.x, rough.diffuse.x * 2, atol=1e-5)
    # Turned away, nothing; behind the rectangle, nothing.
    var away = lighting.physical_at(
        -UP, -UP, ORIGIN, a_chalk(), 1, 0, ROUGHNESS_FLOOR
    )
    assert_equal(away.diffuse.x, Float32(0))
    var behind = lit_rect(rect_scene(0, 0, -1)).physical_at(
        UP, UP, ORIGIN, a_chalk(), 1, 0, ROUGHNESS_FLOOR
    )
    assert_equal(behind.diffuse.x, Float32(0))
    assert_equal(behind.specular.x, Float32(0))
    # A rectangle adds to a sun rather than replacing it, after the scale.
    var scene = rect_scene(0, 0, 1)
    scene.add_light(directional_light(WHITE, NodeId(0), Float32(pi)))
    scene.update()
    var both = lit_rect(scene).physical_at(
        UP, UP, ORIGIN, a_chalk(), 1, 0, ROUGHNESS_FLOOR
    )
    assert_almost_equal(both.diffuse.x, 1 + rough.diffuse.x, atol=1e-2)
    # And the other lit sums leave it out.
    var lambert = lighting.intensity_at(UP, ORIGIN)
    assert_equal(lambert.r, Float32(0))
    assert_equal(
        lighting.specular_at(UP, ORIGIN, Vector3(1, 1, 1), 30).r, Float32(0)
    )


def test_two_rectangles_add_and_a_hidden_layer_leaves_one_out() raises:
    var scene = rect_scene(0, 0, 1)
    var second = Object3D()
    second.set_position(0, 0, 1)
    var node = scene.add(second^)
    var glow = rect_area_light(
        WHITE, node, 1, Length(2.0, METER), Length(2.0, METER)
    )
    var upper = Layers()
    upper.set(1)
    glow.layers = upper
    scene.add_light(glow)
    scene.update()
    var one = lit_rect(scene).physical_at(
        UP, UP, ORIGIN, a_chalk(), 1, 0, ROUGHNESS_FLOOR
    )
    var both = Lighting(
        scene, Layers.all(), EYE, ltc=load_ltc_tables()
    ).physical_at(UP, UP, ORIGIN, a_chalk(), 1, 0, ROUGHNESS_FLOOR)
    var only_first = Lighting(scene, Layers(), EYE, ltc=load_ltc_tables())
    assert_equal(only_first.rect_count(), 1)
    var first = only_first.physical_at(
        UP, UP, ORIGIN, a_chalk(), 1, 0, ROUGHNESS_FLOOR
    )
    assert_almost_equal(both.diffuse.x, first.diffuse.x * 2, atol=1e-5)
    assert_almost_equal(one.diffuse.x, both.diffuse.x, atol=1e-7)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
