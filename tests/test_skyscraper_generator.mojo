# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `generators.skyscraper`, three.js's `SkyscraperGenerator`.

The expected numbers were computed from three.js r186's
`examples/jsm/generators/city/SkyscraperGenerator.js`, step for step in
`Float64` with its Mulberry32 generator. The vertex counts follow from
three.js's modules: 54 vertices a window, 6 a pane, 36 a box, 72 a pier,
192 a pinnacle, and a slab or an arcade by its outline.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from generators.skyscraper import (
    ARCADE,
    AWNING,
    Affine,
    BaseStyle,
    FRAME,
    GLASS,
    ROOM_CENTER,
    ROOM_SIZE,
    STOREFRONT,
    SkyscraperGenerator,
    SkyscraperParameters,
    SkyscraperParts,
    SkyscraperStyle,
    WALL,
    bake,
    build_faces,
    build_footprint,
    building_palette,
    finial_geometry,
    glass_geometry,
    pick_building_color,
    pier_geometry,
    window_geometry,
)
from generators.utils import PART_ID, Vec3d
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def _small() -> SkyscraperParameters:
    """Return the default tower, shrunk to 24 meters on a 12 by 9 lot."""
    var p = SkyscraperParameters()
    p.total_height = Length(24, METER)
    p.footprint_width = Length(12, METER)
    p.footprint_depth = Length(9, METER)
    return p^


def _affine(a: Affine, expected: List[Float64]) raises:
    """Assert a placement: its three columns, then its translation."""
    var got: List[Float64] = [
        a.x_axis.x,
        a.x_axis.y,
        a.x_axis.z,
        a.y_axis.x,
        a.y_axis.y,
        a.y_axis.z,
        a.z_axis.x,
        a.z_axis.y,
        a.z_axis.z,
        a.position.x,
        a.position.y,
        a.position.z,
    ]
    for i in range(12):
        assert_almost_equal(got[i], expected[i], atol=1e-5)


def test_the_seed_picks_three_style() raises:
    """Seed 35 draws three.js's style, snapped to the brick module."""
    var s = SkyscraperStyle(SkyscraperParameters())
    assert_almost_equal(s.footprint_width, 38.99563393415883, atol=1e-9)
    assert_almost_equal(s.footprint_depth, 32.3406967096962, atol=1e-9)
    assert_almost_equal(s.base_fraction, 0.10052176219876856, atol=1e-12)
    assert_almost_equal(s.crown_fraction, 0.12043601356446743, atol=1e-12)
    assert_almost_equal(s.pier_width, 0.6, atol=1e-12)
    assert_almost_equal(s.pier_depth, 0.3852898622397333, atol=1e-12)
    assert_almost_equal(s.window_reveal, 0.1581933250464499, atol=1e-12)
    assert_almost_equal(s.string_course_height, 0.8724626423791051, atol=1e-12)
    assert_equal(s.arch_bay_width_ratio, 3)
    assert_almost_equal(s.arch_rise, 0.505579852941446, atol=1e-12)
    assert_true(s.base_style == STOREFRONT)
    assert_almost_equal(s.floor_height, 4.2, atol=1e-6)
    assert_almost_equal(s.window_height, 2.4, atol=1e-6)
    assert_almost_equal(s.bay_width, 2.4, atol=1e-6)


def test_default_tower_lays_out_as_three() raises:
    """The default tower has three.js's floors and pieces."""
    var parts = SkyscraperGenerator().layout()
    assert_equal(parts.floors, 33)
    assert_equal(parts.base_floors, 3)
    assert_equal(parts.shaft_floors, 26)
    assert_equal(parts.crown_floors, 4)
    assert_almost_equal(parts.style.total_height, 138.6, atol=1e-6)
    assert_false(parts.use_arcade)
    assert_equal(len(parts.footprint), 5)
    assert_equal(len(parts.windows), 1756)
    assert_equal(len(parts.glass), 1756)
    assert_equal(len(parts.glass_rooms), 1756)
    assert_equal(len(parts.back_walls), 20)
    assert_equal(len(parts.bands), 175)
    assert_equal(len(parts.shop_glass), 27)
    assert_equal(len(parts.mullions), 54)
    assert_equal(len(parts.store_bands), 10)
    assert_equal(len(parts.awnings), 13)
    assert_equal(parts.pier_count(), 186)
    assert_equal(len(parts.pier_keys), 4)
    assert_equal(parts.pier_keys[0], 109200)
    assert_equal(parts.pier_keys[1], 15404)
    assert_equal(parts.pier_keys[2], 8400)
    assert_equal(parts.pier_keys[3], 4200)
    assert_equal(len(parts.trim), 65)
    assert_equal(len(parts.ac_units), 171)
    assert_equal(len(parts.finials), 47)
    assert_equal(len(parts.extras), 2)


def test_small_tower_matches_three() raises:
    """A small tower's placements and its bake follow three.js."""
    var generator = SkyscraperGenerator(_small())
    var parts = generator.layout()
    assert_equal(parts.floors, 6)
    assert_equal(len(parts.windows), 67)
    assert_equal(len(parts.back_walls), 15)
    assert_equal(len(parts.bands), 35)
    assert_equal(len(parts.shop_glass), 6)
    assert_equal(len(parts.awnings), 3)
    assert_equal(parts.pier_count(), 28)
    assert_equal(len(parts.trim), 25)
    assert_equal(len(parts.ac_units), 7)
    assert_equal(len(parts.finials), 7)
    _affine(
        parts.windows[0],
        [0.7071068, 0, -0.7071068, 0, 1, 0, 0.7071068, 0, 0.7071068,
         3.1514719, 6.3, 3.3485281],
    )
    _affine(
        parts.glass[5],
        [0.7071068, 0, -0.7071068, 0, 1, 0, 0.7071068, 0, 0.7071068,
         4.7366686, 14.7, 1.5396123],
    )
    var room = parts.glass_rooms[5]
    assert_almost_equal(room.center.x, 3.8881404, atol=1e-6)
    assert_almost_equal(room.center.y, 14.7, atol=1e-6)
    assert_almost_equal(room.center.z, 2.3881404, atol=1e-6)
    assert_almost_equal(room.width, 4.8, atol=1e-9)
    assert_almost_equal(room.height, 3.2, atol=1e-9)
    _affine(
        parts.ac_units[0],
        [0.66, 0, 0, 0, 0.396, 0, 0, 0, 0.33, -4.4, 9.598, 4.5468067],
    )
    _affine(
        parts.bands[3],
        [3.5757359, 0, -3.5757359, 0, 1.8, 0, 0.4242641, 0, 0.4242641,
         3.7878680, 16.8, 2.2878680],
    )
    _affine(
        parts.trim[24],
        [0, 0, -4.4, 0, 1.4, 0, 0.3082319, 0, 0, 2.5541159, 25.9, -0.2],
    )
    _affine(
        parts.finials[0],
        [1, 0, 0, 0, 1, 0, 0, 0, 1, 1.4876924, 25.2, 3.1847487],
    )
    _affine(
        parts.shop_glass[0],
        [2.8849957, 0, -2.8849957, 0, 2.8, 0, 0.7071068, 0, 0.7071068,
         3.8727208, 1.9, 2.3727208],
    )
    assert_almost_equal(parts.shop_rooms[0].width, 4.08, atol=1e-9)
    _affine(
        parts.awnings[0],
        [3.1819805, 0, -3.1819805, 0, 0.14, 0, 0.9192388, 0, 0.9192388,
         4.4949747, 3.18, 2.9949747],
    )
    _affine(
        parts.back_walls[0],
        [5.1313708, 0, -5.1313708, 0, 16.8, 0, 0.5656854, 0, 0.5656854,
         3.2928932, 12.6, 1.7928932],
    )
    var geometry = bake(parts)
    assert_equal(geometry.vertex_count(), 11364)
    assert_false(geometry.is_indexed())
    # The first vertex is a window's, and the last a back wall's.
    assert_equal(
        geometry.attribute_view(String(PART_ID)).component(0, 0),
        Float32(FRAME.value),
    )
    assert_equal(
        geometry.attribute_view(String(PART_ID)).component(11363, 0),
        Float32(WALL.value),
    )
    # The first pane follows the 67 windows of 54 vertices each, and
    # carries its room.
    var pane = 67 * 54
    assert_equal(
        geometry.attribute_view(String(PART_ID)).component(pane, 0),
        Float32(GLASS.value),
    )
    ref size = geometry.attribute_view(String(ROOM_SIZE))
    assert_almost_equal(
        size.component(pane, 0), Float32(parts.glass_rooms[0].width), atol=1e-6
    )
    assert_equal(size.component(0, 0), 0)
    # Every normal is unit length.
    var normal = geometry.attribute_view(String(NORMAL)).vector3(pane)
    assert_almost_equal(normal.length(), 1, atol=1e-6)
    assert_equal(generator.build().vertex_count(), 11364)


def test_an_arcade_tower_matches_three() raises:
    """A tall base on an arcade-styled seed takes the pointed arches."""
    var p = SkyscraperParameters()
    p.seed = 3
    p.total_height = Length(30, METER)
    p.footprint_width = Length(14, METER)
    p.footprint_depth = Length(10, METER)
    p.base_fraction = 0.4
    var parts = SkyscraperGenerator(p^).layout()
    assert_true(parts.use_arcade)
    assert_true(parts.style.base_style == ARCADE)
    assert_equal(parts.base_floors, 3)
    assert_equal(len(parts.windows), 59)
    assert_equal(len(parts.shop_glass), 0)
    assert_equal(len(parts.store_bands), 0)
    assert_equal(parts.pier_count(), 25)
    assert_equal(len(parts.pier_keys), 2)
    assert_equal(len(parts.ac_units), 6)
    assert_equal(len(parts.finials), 8)
    # An arcade wall and the dark plane behind it on every face, and the
    # two slabs.
    assert_equal(len(parts.extras), 12)
    # Neighboring arches share the sill line, so earcut's bridge between
    # two holes leaves collinear points that it filters out: two
    # triangles fewer for each second arch on a face, three faces here.
    assert_equal(bake(parts).vertex_count(), 11004 - 3 * 2 * 3)


def test_string_courses_and_a_square_corner() raises:
    """A course every second floor bands the shaft, and no chamfer keeps
    the four corners."""
    var p = _small()
    p.string_course_every = 2
    p.chamfer_width = Length(0, METER)
    var parts = SkyscraperGenerator(p^).layout()
    assert_equal(len(parts.footprint), 4)
    assert_equal(len(parts.windows), 72)
    assert_equal(len(parts.trim), 28)
    assert_equal(parts.pier_count(), 30)
    assert_equal(len(parts.awnings), 4)
    assert_equal(bake(parts).vertex_count(), 11652)


def test_no_string_course() raises:
    """A course count of zero bands nothing; only the cornices remain."""
    var p = _small()
    p.string_course_every = 0
    var parts = SkyscraperGenerator(p^).layout()
    assert_equal(len(parts.trim), 25)


def test_footprint_and_faces() raises:
    """The cut corner faces out at 45 degrees, and each face frame has its
    origin where `u` runs away from."""
    var points = build_footprint(12, 9, 4, 1, 1)
    assert_equal(len(points), 5)
    assert_almost_equal(points[0].x, 6.0, atol=1e-12)
    assert_almost_equal(points[0].z, 0.5, atol=1e-12)
    assert_almost_equal(points[1].x, 2.0, atol=1e-12)
    var faces = build_faces(points)
    assert_almost_equal(faces[0].origin.x, 2.0, atol=1e-12)
    assert_almost_equal(faces[0].origin.z, 4.5, atol=1e-12)
    assert_almost_equal(faces[0].n.x, 0.7071067811865475, atol=1e-12)
    assert_almost_equal(faces[0].length, 5.656854249492381, atol=1e-12)
    assert_almost_equal(faces[4].origin.z, 0.5, atol=1e-12)
    assert_almost_equal(faces[4].n.x, 1, atol=1e-12)
    # Another corner, and a corner that is none.
    assert_almost_equal(build_footprint(12, 9, 4, -1, -1)[3].x, -2.0, atol=1e-12)
    assert_equal(len(build_footprint(12, 9, 4, 0, 1)), 4)
    assert_equal(len(build_faces(List[Vec3d]())), 0)
    var bays = faces[3].bays(2.4)
    assert_equal(bays.count, 5)
    assert_almost_equal(bays.margin, 0.0, atol=1e-12)
    assert_equal(faces[0].bays(100).count, 1)


def test_modules_match_three_counts() raises:
    """The authored modules have three.js's vertex counts."""
    var s = SkyscraperStyle(_small())
    assert_equal(window_geometry(s).vertex_count(), 54)
    assert_equal(glass_geometry(s).vertex_count(), 6)
    assert_equal(pier_geometry(s, 16.8).vertex_count(), 72)
    assert_equal(finial_geometry(s).vertex_count(), 192)
    var pier = pier_geometry(s, 16.8).bounding_box()
    assert_almost_equal(pier.max.y, 16.8, atol=1e-5)
    # A pier too short for its pilaster keeps a one-meter pilaster.
    assert_almost_equal(
        pier_geometry(s, 0.5).bounding_box().max.y, 1.0, atol=1e-5
    )


def test_palette_and_placements() raises:
    """The palette pick is three.js's hash, and a collapsed placement
    turns normals to zero as three.js's does."""
    assert_equal(len(building_palette()), 17)
    assert_equal(pick_building_color(0), 0xA8553C)
    assert_equal(pick_building_color(35), building_palette()[9])
    var flat = Affine(Vec3d(1, 0, 0), Vec3d(0, 0, 0), Vec3d(0, 0, 1), Vec3d(1, 2, 3))
    var turn = flat.normal_turn()
    assert_equal(turn.x_axis.x, 0)
    var m = flat.matrix4()
    assert_equal(m.elements[12], 1)
    var stretched = Affine(
        Vec3d(2, 0, 0), Vec3d(0, 4, 0), Vec3d(0, 0, 1), Vec3d(0, 0, 0)
    ).normal_turn()
    assert_almost_equal(stretched.x_axis.x, 0.5, atol=1e-12)
    assert_almost_equal(stretched.y_axis.y, 0.25, atol=1e-12)
    var empty = SkyscraperParts(SkyscraperStyle(SkyscraperParameters()))
    assert_equal(empty.pier_count(), 0)


def test_tower_parameters_are_checked() raises:
    """A tower refuses a style or a size it cannot build."""
    var p = SkyscraperParameters()
    p.base_style = BaseStyle(2)
    with assert_raises(contains="base style"):
        _ = SkyscraperGenerator(p^).layout()
    p = SkyscraperParameters()
    p.chamfer_corner_x = 2
    with assert_raises(contains="chamfer corner"):
        _ = SkyscraperGenerator(p^).layout()
    p = SkyscraperParameters()
    p.chamfer_corner_z = -2
    with assert_raises(contains="chamfer corner"):
        _ = SkyscraperGenerator(p^).layout()
    p = SkyscraperParameters()
    p.total_height = Length(0, METER)
    with assert_raises(contains="positive and finite"):
        _ = SkyscraperGenerator(p^).layout()
    p = SkyscraperParameters()
    p.bay_width = Length(inf[DType.float32](), METER)
    with assert_raises(contains="positive and finite"):
        _ = SkyscraperGenerator(p^).layout()
    p = SkyscraperParameters()
    p.arch_rise = nan[DType.float64]()
    with assert_raises(contains="style"):
        _ = SkyscraperGenerator(p^).layout()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
