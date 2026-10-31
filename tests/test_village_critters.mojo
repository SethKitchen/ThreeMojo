# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The fireflies and the butterflies of the village."""

from core.assets import Assets
from core.scene import Scene
from extensions.vegetation.ground import Ground, Pond
from extensions.village.critters import (
    Critters,
    DAY,
    Haunt,
    NIGHT,
    WET,
    default_haunts,
    wing_color,
)
from extensions.village.surfaces import house_looks
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import METER, SECOND, Duration, Length


def _haunt(radius: Float32, fireflies: Int, butterflies: Int) -> Haunt:
    """Return a haunt around the origin."""
    return Haunt(
        Length(0.0, METER),
        Length(0.0, METER),
        Length(radius, METER),
        fireflies,
        butterflies,
    )


def test_a_haunt_is_checked() raises:
    var fireflies = 0
    var butterflies = 0
    for haunt in default_haunts():
        haunt.check()
        fireflies += haunt.fireflies
        butterflies += haunt.butterflies
    assert_equal(fireflies, 26)
    assert_equal(butterflies, 9)
    with assert_raises(contains="radius"):
        _haunt(-1, 1, 1).check()
    with assert_raises(contains="radius"):
        _haunt(101, 1, 1).check()
    with assert_raises(contains="fireflies"):
        _haunt(1, -1, 1).check()
    with assert_raises(contains="fireflies"):
        _haunt(1, 65, 1).check()
    with assert_raises(contains="butterflies"):
        _haunt(1, 1, -1).check()
    with assert_raises(contains="butterflies"):
        _haunt(1, 1, 65).check()
    # Four colors take turns on the wings.
    assert_true(wing_color(0).x > wing_color(2).x)
    assert_true(wing_color(1).z > wing_color(3).z)
    assert_true(wing_color(2).z > wing_color(0).z)
    assert_almost_equal(wing_color(4).y, wing_color(0).y, atol=1e-6)


def _critters(mut scene: Scene, mut assets: Assets) raises -> Critters:
    """Return three fireflies and two butterflies over flat ground."""
    var haunts: List[Haunt] = [_haunt(4, 3, 2)]
    return Critters(
        scene,
        assets,
        house_looks(assets, 4, 1),
        haunts,
        Ground(),
        Length(-50.0, METER),
    )


def test_each_critter_is_built_hidden() raises:
    var assets = Assets()
    var scene = Scene()
    var critters = _critters(scene, assets)
    assert_equal(len(critters.fireflies), 3)
    assert_equal(len(critters.butterflies), 2)
    assert_equal(len(critters.wings), 4)
    assert_equal(critters.meshes, 3 + 2 * 3)
    assert_equal(len(scene.meshes), critters.meshes)
    assert_true(critters.triangles > 3 * 8)
    for node in critters.fireflies:
        assert_false(scene.node(node).visible)
    for node in critters.butterflies:
        assert_false(scene.node(node).visible)
    # Each keeps to its haunt, on the ground.
    var ground = Ground()
    for index in range(5):
        ref home = critters.homes[index]
        assert_true(home.x * home.x + home.z * home.z <= 4 + 1e-4)
        assert_almost_equal(home.y, ground.height_at(home.x, home.z), atol=1e-5)
        assert_true(critters.reaches[index] <= 4 * 0.7 + 1e-5)
    # A bad haunt is refused, and no haunt is a village with no critters.
    var bad: List[Haunt] = [_haunt(1, -1, 0)]
    with assert_raises(contains="fireflies"):
        _ = Critters(
            scene,
            assets,
            house_looks(assets, 4, 1),
            bad,
            Ground(),
            Length(0.0, METER),
        )
    var none = Critters(
        scene,
        assets,
        house_looks(assets, 4, 1),
        List[Haunt](),
        Ground(),
        Length(0.0, METER),
    )
    assert_equal(none.meshes, 0)
    none.update(scene, 1, 0, Duration(0.1, SECOND))


def test_a_critter_over_the_pond_flies_over_its_water() raises:
    var assets = Assets()
    var scene = Scene()
    var ground = Ground(
        pond=Pond(
            Length(0.0, METER),
            Length(0.0, METER),
            Length(10.0, METER),
            Length(2.0, METER),
        )
    )
    var level = ground.height_at(0, 0) + 1.5
    var haunts: List[Haunt] = [_haunt(2, 1, 0)]
    var critters = Critters(
        scene,
        assets,
        house_looks(assets, 4, 1),
        haunts,
        ground,
        Length(level, METER),
    )
    assert_almost_equal(critters.homes[0].y, level, atol=1e-5)


def test_by_day_the_butterflies_fly_and_beat_their_wings() raises:
    var assets = Assets()
    var scene = Scene()
    var critters = _critters(scene, assets)
    var step = Duration(0.1, SECOND)
    critters.update(scene, 1, 0, step)
    for node in critters.fireflies:
        assert_false(scene.node(node).visible)
    ref first = scene.node(critters.butterflies[0])
    assert_true(first.visible)
    var was = first.position
    var turned = first.quaternion.y
    var home = critters.homes[3]
    assert_true(was.y > home.y + 0.4)
    assert_true(was.y < home.y + 1.3)
    # Its wings beat against each other.
    var left = scene.node(critters.wings[0]).quaternion.z
    var right = scene.node(critters.wings[1]).quaternion.z
    assert_almost_equal(left, -right, atol=1e-6)
    for _ in range(7):
        critters.update(scene, 1, 0, step)
    ref later = scene.node(critters.butterflies[0])
    assert_true((later.position - was).length() > 0.1)
    assert_true(abs(later.quaternion.y - turned) > 1e-3)
    assert_true(abs(scene.node(critters.wings[0]).quaternion.z - left) > 1e-3)
    # Not in the dusk, and not in the rain.
    critters.update(scene, (DAY + NIGHT) / 2, 0, step)
    assert_false(scene.node(critters.butterflies[0]).visible)
    critters.update(scene, 1, WET + 0.1, step)
    assert_false(scene.node(critters.butterflies[0]).visible)
    with assert_raises(contains="negative"):
        critters.update(scene, 1, 0, Duration(-1.0, SECOND))


def test_by_night_the_fireflies_drift_and_blink() raises:
    var assets = Assets()
    var scene = Scene()
    var critters = _critters(scene, assets)
    var step = Duration(0.1, SECOND)
    var shown = List[Int](length=3, fill=0)
    var frames = 120
    for _ in range(frames):
        critters.update(scene, 0, 0, step)
        for index in range(3):
            if scene.node(critters.fireflies[index]).visible:
                shown[index] += 1
                ref at = scene.node(critters.fireflies[index]).position
                ref home = critters.homes[index]
                assert_true(at.y > home.y + 0.35)
                assert_true(at.y < home.y + 1.35)
        for node in critters.butterflies:
            assert_false(scene.node(node).visible)
    # Each glows for about half its time, and goes dark between.
    for index in range(3):
        assert_true(shown[index] > frames // 4)
        assert_true(shown[index] < frames * 3 // 4)
    # No firefly shows in the rain.
    critters.update(scene, 0, 1, step)
    for node in critters.fireflies:
        assert_false(scene.node(node).visible)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
