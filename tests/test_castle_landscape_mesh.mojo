# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the triangles and the colors of the ground of a landscape.

A ground of known shape gives each material a place: a plateau of meadow, a
ramp of rock, and a shelf above the snow line.
"""

from core.buffer_geometry import COLOR, NORMAL
from extensions.castle.landscape_mesh import _field, _mix, add_ground
from extensions.castle.parts import Kit
from generators.utils import Vec3d
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from tests._castle_land import plateau, small_landscape
from units.si import Length64, METER


def test_every_cell_of_a_ground_is_two_triangles() raises:
    var land = plateau()
    land.settings.treeline = Length64(20.0, METER)
    land.settings.snow_line = Length64(40.0, METER)
    var kit = Kit()
    add_ground(land, kit)
    # 40 by 40 cells, each of two triangles, whatever its material.
    assert_equal(kit.triangles(), 40 * 40 * 2)


def test_meadow_rock_and_snow_each_have_a_place() raises:
    var land = plateau()
    land.settings.treeline = Length64(20.0, METER)
    land.settings.snow_line = Length64(40.0, METER)
    var kit = Kit()
    add_ground(land, kit)
    # The plateau is meadow, the ramp that climbs at 45 degrees is rock, and
    # the shelf over the snow line is snow.
    assert_true(kit.lawn.count() > 1000)
    assert_true(kit.gravel.count() > 20)
    assert_true(kit.wood.count() > 20)
    # A ground of one height has neither rock nor snow.
    var flat = plateau()
    var calm = Kit()
    add_ground(flat, calm)
    assert_true(calm.gravel.count() > 20)
    assert_equal(calm.wood.count(), 0)


def test_the_rings_leave_a_hole_for_the_finer_ring() raises:
    var land = small_landscape()
    var kit = Kit()
    add_ground(land, kit)
    var cells = 0
    for ring in range(len(land.rings)):
        ref grid = land.rings[ring]
        var across = grid.columns - 1
        var hole = Int(2.0 * grid.hole / grid.step)
        cells += across * across - hole * hole
    assert_equal(kit.triangles(), cells * 2)


def test_the_far_rings_are_all_meadow_material() raises:
    # With the snow line at 10 m, the far mountains are all snow and rock, but
    # a cell of a far ring still goes to the meadow builder, with the white in
    # its vertex colors, so that it does not stand out as a square.
    var land = small_landscape()
    land.settings.treeline = Length64(5.0, METER)
    land.settings.snow_line = Length64(10.0, METER)
    var kit = Kit()
    add_ground(land, kit)
    var far = 0
    for ring in range(2, len(land.rings)):
        ref grid = land.rings[ring]
        var across = grid.columns - 1
        var hole = Int(2.0 * grid.hole / grid.step)
        far += (across * across - hole * hole) * 2
    assert_true(kit.lawn.count() >= far)


def test_every_vertex_has_a_finite_color_and_an_upward_normal() raises:
    var land = plateau()
    land.settings.treeline = Length64(20.0, METER)
    land.settings.snow_line = Length64(40.0, METER)
    var kit = Kit()
    add_ground(land, kit)
    var colors = kit.lawn.geometry().clone_attribute(String(COLOR))
    for at in range(len(colors.data)):
        assert_true(colors.data[at] >= 0.0 and colors.data[at] < 1.0e4)
    var snow = kit.wood.geometry().clone_attribute(String(COLOR))
    for at in range(len(snow.data)):
        assert_true(snow.data[at] > 0.5 and snow.data[at] <= 1.0)
    # The meadow faces up: the y of a normal, in the mesh frame, is its up.
    var normals = kit.lawn.geometry().clone_attribute(String(NORMAL))
    var up = Float64(0)
    var count = 0
    for at in range(1, len(normals.data), 3):
        up += Float64(normals.data[at])
        count += 1
    assert_true(up / Float64(count) > 0.8)


def test_a_field_has_one_of_five_colors() raises:
    var seen = List[Float64]()
    for index in range(5):
        var color = _field(index)
        assert_true(color.x > 0.0 and color.y > 0.0 and color.z > 0.0)
        var key = color.x * 1000.0 + color.y * 10.0 + color.z
        assert_true(key not in seen)
        seen.append(key)


def test_a_mix_runs_from_one_color_to_the_other() raises:
    var a = Vec3d(1, 0, 0)
    var b = Vec3d(0, 1, 0)
    var half = _mix(a, b, 0.5)
    assert_almost_equal(half.x, 0.5)
    assert_almost_equal(half.y, 0.5)
    assert_almost_equal(_mix(a, b, 0.0).x, 1.0)
    assert_almost_equal(_mix(a, b, 1.0).y, 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
