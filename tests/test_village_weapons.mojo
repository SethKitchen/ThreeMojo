# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The weapons of the styles: an axe, a mace, a staff and a bow, built along
plus z from the grip, and hung in the hand or stowed."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.village.blade import SwordLooks
from extensions.village.sheet import Sheet
from extensions.village.styles import (
    ARCHERY,
    AXE,
    HAND_TO_HAND,
    MACE,
    MAGIC,
    SWORD,
)
from extensions.village.weapons import (
    BACK_AT,
    HELD_AT,
    HIP_AT,
    add_weapon,
    axe_sheets,
    bow_sheets,
    mace_sheets,
    staff_sheets,
    tube,
    weapon_sheets,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _reach(sheet: Sheet) -> Vector3:
    """Return the most of each coordinate over a sheet's vertices."""
    var most = Vector3(-1.0e9, -1.0e9, -1.0e9)
    for v in range(len(sheet.positions) // 3):
        most.x = max(most.x, sheet.positions[3 * v])
        most.y = max(most.y, sheet.positions[3 * v + 1])
        most.z = max(most.z, sheet.positions[3 * v + 2])
    return most


def _least(sheet: Sheet) -> Vector3:
    """Return the least of each coordinate over a sheet's vertices."""
    var least = Vector3(1.0e9, 1.0e9, 1.0e9)
    for v in range(len(sheet.positions) // 3):
        least.x = min(least.x, sheet.positions[3 * v])
        least.y = min(least.y, sheet.positions[3 * v + 1])
        least.z = min(least.z, sheet.positions[3 * v + 2])
    return least


def test_a_tube_runs_along_its_line() raises:
    var sheet = Sheet(1)
    tube(sheet, Vector3(0, 0, 0), Vector3(0, 0, 2), 0.1, 6, Vector3(1, 1, 1))
    assert_equal(sheet.triangles(), 6 * 4)
    assert_almost_equal(_reach(sheet).z, 2, atol=1e-5)
    assert_almost_equal(_reach(sheet).y, 0.1, atol=1e-5)
    # Along x, it finds its own sides.
    var side = Sheet(1)
    tube(side, Vector3(0, 0, 0), Vector3(3, 0, 0), 0.1, 4, Vector3(1, 1, 1))
    assert_almost_equal(_reach(side).x, 3, atol=1e-5)
    # A line of no length, or fewer than three sides, adds nothing.
    var none = Sheet(1)
    tube(none, Vector3(1, 1, 1), Vector3(1, 1, 1), 0.1, 6, Vector3(1, 1, 1))
    tube(none, Vector3(0, 0, 0), Vector3(0, 0, 1), 0.1, 2, Vector3(1, 1, 1))
    assert_equal(none.triangles(), 0)


def test_each_weapon_reaches_along_plus_z() raises:
    var axe = axe_sheets(1)
    assert_true(_reach(axe.metal).z > 0.6)
    assert_true(_reach(axe.metal).y > 0.18)
    assert_equal(axe.glow.triangles(), 0)
    var mace = mace_sheets(1)
    assert_true(_reach(mace.metal).z > 0.6)
    assert_true(mace.metal.triangles() > 6 * 4)
    var staff = staff_sheets(1)
    assert_true(_reach(staff.leather).z > 0.9)
    assert_true(_least(staff.leather).z < -0.7)
    assert_true(staff.glow.triangles() == 10)
    var bow = bow_sheets(1)
    assert_almost_equal(_reach(bow.leather).z, 0.65, atol=0.05)
    assert_almost_equal(_least(bow.leather).z, -0.65, atol=0.05)
    assert_true(bow.glow.triangles() > 0)
    # Each grows with the fighter.
    var big = axe_sheets(2)
    assert_almost_equal(_reach(big.metal).z, 2 * _reach(axe.metal).z, atol=1e-4)


def test_only_four_styles_have_a_weapon_here() raises:
    assert_true(weapon_sheets(AXE, 1).metal.triangles() > 0)
    assert_true(weapon_sheets(MACE, 1).metal.triangles() > 0)
    assert_true(weapon_sheets(MAGIC, 1).glow.triangles() > 0)
    assert_true(weapon_sheets(ARCHERY, 1).leather.triangles() > 0)
    with assert_raises(contains="Only"):
        _ = weapon_sheets(SWORD, 1)
    with assert_raises(contains="Only"):
        _ = weapon_sheets(HAND_TO_HAND, 1)


def test_a_weapon_hangs_in_the_hand_or_is_stowed() raises:
    var assets = Assets()
    var scene = Scene()
    var looks = SwordLooks(assets)
    var hand = scene.add(Object3D())
    var before = len(scene.meshes)
    var held = add_weapon(scene, assets, looks, hand, 1, AXE, False)
    # The axe has metal and wood, and nothing that glows.
    assert_equal(len(scene.meshes) - before, 2)
    assert_almost_equal(scene.node(held).position.y, HELD_AT.y, atol=1e-6)
    var hip = add_weapon(scene, assets, looks, hand, 1, MACE, True)
    assert_almost_equal(scene.node(hip).position.x, HIP_AT.x, atol=1e-6)
    # A staff and a bow are slung across the back.
    var count = len(scene.meshes)
    var back = add_weapon(scene, assets, looks, hand, 1, MAGIC, True)
    assert_almost_equal(scene.node(back).position.z, BACK_AT.z, atol=1e-6)
    assert_equal(len(scene.meshes) - count, 3)
    var bow = add_weapon(scene, assets, looks, hand, 2, ARCHERY, True)
    assert_almost_equal(scene.node(bow).position.z, 2 * BACK_AT.z, atol=1e-6)
    var held_bow = add_weapon(scene, assets, looks, hand, 1, ARCHERY, False)
    assert_almost_equal(scene.node(held_bow).position.y, HELD_AT.y, atol=1e-6)
    with assert_raises(contains="Only"):
        _ = add_weapon(scene, assets, looks, hand, 1, SWORD, False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
