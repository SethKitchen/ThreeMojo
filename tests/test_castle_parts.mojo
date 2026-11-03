# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the parts that a castle is built of: what a part leaves out when
its shape has no area or no length, and which materials a kit hands over."""

from extensions.castle.kinds import BARK, FOLIAGE
from extensions.castle.parts import (
    Kit,
    Opening,
    box_at,
    merlon_row,
    quad_uv,
    ridge_cap,
    round_wall,
    tri_uv,
    wall,
    white,
    window_row,
)
from extensions.visual.mesh import MeshBuilder
from generators.utils import Vec3d
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


def _box(mut mesh: MeshBuilder):
    """Put a unit box in a builder."""
    box_at(
        mesh,
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(0, 1, 0),
        Vec3d(0, 0, 1),
        0.5,
        0.5,
        0.5,
        white(),
    )


def test_a_kit_with_no_triangles_has_no_mesh() raises:
    var kit = Kit()
    assert_equal(kit.triangles(), 0)
    assert_equal(len(kit.meshes()), 0)


def test_a_kit_hands_over_the_materials_that_have_triangles() raises:
    var kit = Kit()
    _box(kit.foliage)
    _box(kit.bark)
    assert_equal(kit.triangles(), 24)
    var meshes = kit.meshes()
    assert_equal(len(meshes), 2)
    assert_equal(meshes[0].material.value, FOLIAGE.value)
    assert_equal(meshes[1].material.value, BARK.value)


def test_a_triangle_or_quad_with_no_area_adds_nothing() raises:
    var mesh = MeshBuilder()
    var origin = Vec3d(0, 0, 0)
    var a = Vec3d(0, 0, 0)
    var b = Vec3d(1, 0, 0)
    var c = Vec3d(2, 0, 0)
    var up = Vec3d(0, 0, 1)
    var uv = (0.0, 0.0)
    tri_uv(mesh, a, b, c, up, up, up, uv, uv, uv, white())
    quad_uv(
        mesh, a, b, c, Vec3d(3, 0, 0), up, white(), origin, b, Vec3d(0, 1, 0)
    )
    assert_equal(mesh.count(), 0)
    # The same corners lifted into a plane give triangles.
    var d = Vec3d(0, 1, 0)
    tri_uv(mesh, a, b, d, up, up, up, uv, uv, uv, white())
    quad_uv(
        mesh,
        a,
        b,
        Vec3d(1, 1, 0),
        d,
        up,
        white(),
        origin,
        Vec3d(1, 0, 0),
        Vec3d(0, 1, 0),
    )
    assert_equal(mesh.count(), 3)


def test_a_wall_of_no_length_adds_nothing() raises:
    var kit = Kit()
    var here = Vec3d(2, 3, 0)
    wall(
        kit,
        False,
        here,
        here,
        Vec3d(0, -1, 0),
        0.0,
        5.0,
        List[Opening](),
        white(),
    )
    assert_equal(kit.triangles(), 0)
    wall(
        kit,
        False,
        here,
        Vec3d(8, 3, 0),
        Vec3d(0, -1, 0),
        0.0,
        5.0,
        List[Opening](),
        white(),
    )
    assert_true(kit.triangles() > 0)


def test_windows_are_spaced_along_the_room_a_wall_leaves() raises:
    # Too short for one window.
    assert_equal(len(window_row(2.0, 1.4, 3.0, 1.0, 1.5, 1.0, False)), 0)
    # Room for one only: it stands in the middle.
    var one = window_row(4.0, 1.4, 3.0, 1.0, 1.5, 1.0, False)
    assert_equal(len(one), 1)
    assert_equal(one[0].at, 2.0)
    # Room for several: the first and the last are a margin from the ends.
    var many = window_row(20.0, 1.4, 3.0, 1.0, 1.5, 1.0, True)
    assert_true(len(many) > 2)
    assert_almost_equal(many[0].at, 1.4, atol=1.0e-12)
    assert_true(many[0].pointed)
    assert_almost_equal(many[len(many) - 1].at, 18.6, atol=1.0e-12)


def test_the_slits_of_a_round_tower_follow_its_stride() raises:
    var levels: List[Float64] = [2.0]
    var plain = Kit()
    round_wall(plain, 0, 0, 3.0, 0, 6.0, 8, False, white(), levels, 0, 0, 0.3)
    var every_other = Kit()
    round_wall(
        every_other, 0, 0, 3.0, 0, 6.0, 8, False, white(), levels, 2, 0, 0.3
    )
    var all = Kit()
    round_wall(all, 0, 0, 3.0, 0, 6.0, 8, False, white(), levels, 1, 0, 0.3)
    assert_true(every_other.triangles() > plain.triangles())
    assert_true(all.triangles() > every_other.triangles())
    # A plate narrower than its slit has none.
    var narrow = Kit()
    var narrow_plain = Kit()
    round_wall(narrow, 0, 0, 0.5, 0, 6.0, 8, False, white(), levels, 1, 0, 0.3)
    round_wall(
        narrow_plain, 0, 0, 0.5, 0, 6.0, 8, False, white(), levels, 0, 0, 0.3
    )
    assert_equal(narrow.triangles(), narrow_plain.triangles())


def test_a_ridge_of_no_length_has_no_cap() raises:
    var mesh = MeshBuilder()
    ridge_cap(mesh, Vec3d(1, 1, 5), Vec3d(1, 1, 5), 0.3)
    assert_equal(mesh.count(), 0)
    ridge_cap(mesh, Vec3d(1, 1, 5), Vec3d(9, 1, 5), 0.3)
    assert_true(mesh.count() > 0)


def test_an_edge_under_a_meter_has_no_parapet() raises:
    var kit = Kit()
    merlon_row(kit, Vec3d(0, 0, 0), Vec3d(0.8, 0, 0), Vec3d(0, -1, 0), 5.0, 1.0)
    assert_equal(kit.triangles(), 0)
    merlon_row(kit, Vec3d(0, 0, 0), Vec3d(6, 0, 0), Vec3d(0, -1, 0), 5.0, 1.0)
    assert_true(kit.triangles() > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
