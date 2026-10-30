# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sword in the hand or at the hip, and its scabbard."""

from core.assets import Assets
from core.buffer_geometry import POSITION
from core.object3d import Object3D
from core.scene import Scene
from extensions.village.blade import (
    BLADE,
    BRIGHT_STEEL,
    DULL_IRON,
    HAND_GRIP,
    SHEATH_AT,
    SwordLooks,
    add_scabbard,
    add_sword,
    scabbard_sheet,
    sword_sheets,
)
from extensions.village.sheet import Sheet
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


def _reach(sheet: Sheet) -> Tuple[Float32, Float32]:
    """Return the least and the most z of a sheet's corners."""
    var low = Float32(1e9)
    var high = Float32(-1e9)
    for k in range(len(sheet.positions) // 3):  # pragma: no branch
        var z = sheet.positions[3 * k + 2]
        low = min(low, z)
        high = max(high, z)
    return (low, high)


def test_a_sword_reaches_along_plus_z_from_its_grip() raises:
    var sword = sword_sheets(1, BRIGHT_STEEL)
    assert_true(sword.metal.triangles() > 20)
    assert_equal(sword.leather.triangles(), 12)
    var metal = _reach(sword.metal)
    assert_almost_equal(metal[1], 0.092 + BLADE, atol=1e-4)
    assert_almost_equal(metal[0], -0.101, atol=1e-4)
    # A smaller fighter carries a smaller sword.
    var small = sword_sheets(0.5, DULL_IRON)
    assert_almost_equal(_reach(small.metal)[1], (0.092 + BLADE) / 2, atol=1e-4)
    # The scabbard covers the blade and its point.
    var scabbard = scabbard_sheet(1)
    assert_equal(scabbard.triangles(), 12)
    var cover = _reach(scabbard)
    assert_true(cover[1] > metal[1])
    assert_almost_equal(cover[0], 0.082, atol=1e-4)


def test_a_sword_hangs_in_the_hand_or_at_the_hip() raises:
    var assets = Assets()
    var scene = Scene()
    var looks = SwordLooks(assets)
    assert_true(assets.materials.get(looks.metal).vertex_colors)
    assert_true(assets.materials.get(looks.leather).vertex_colors)
    var hand = scene.add(Object3D())
    var hips = scene.add(Object3D())
    var held = add_sword(scene, assets, looks, hand, 1, BRIGHT_STEEL, False)
    assert_true(scene.node(held).parent == hand)
    assert_almost_equal(scene.node(held).position.y, HAND_GRIP.y, atol=1e-6)
    var sheathed = add_sword(scene, assets, looks, hips, 2, DULL_IRON, True)
    assert_almost_equal(
        scene.node(sheathed).position.x, SHEATH_AT.x * 2, atol=1e-6
    )
    # Turned so its point goes back and down.
    var q = scene.node(sheathed).quaternion
    assert_true(abs(q.x) > 0.9)
    var scabbard = add_scabbard(scene, assets, looks, hips, 2)
    assert_true(scene.node(scabbard).parent == hips)
    assert_almost_equal(
        scene.node(scabbard).position.z, SHEATH_AT.z * 2, atol=1e-6
    )
    # Two meshes a sword, and one a scabbard.
    assert_equal(len(scene.meshes), 5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
