# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for colliders fit to a dressed person, for a cloak to fall over."""

from core.assets import Assets
from core.buffer_geometry import POSITION, BufferGeometry
from core.scene import Scene
from extensions.attire.apparel import wizard_robe
from extensions.attire.armory import great_helm, great_pauldrons
from extensions.attire.drape import (
    DRAPE_BAND,
    DRAPE_GROWTH,
    DRAPE_PARTS,
    body_parts,
    dressed_colliders,
    skirt_bands,
)
from extensions.attire.garment import boots, shirt
from extensions.attire.outfit import Dressed, Outfit, dress
from extensions.attire.skirt import skirt_scale, skirt_top
from extensions.attire.springs import body_colliders, nearest_on_segment
from extensions.humanoid.rig.game import GameHumanoid
from extensions.humanoid.rig.joints import HIPS, LEFT_UPPER_ARM, RIGHT_UPPER_ARM
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_people import coarse_person


def _joint_of(person: GameHumanoid, node: Int) -> Int:
    """Return the joint whose bone is a node, or -1."""
    for j in range(len(person.bones)):
        if person.bones[j].value == node:
            return j
    return -1


def test_each_capsule_of_the_body_is_cut_into_parts() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var whole = body_colliders(person)
    var parts = body_parts(person)
    assert_equal(len(parts), DRAPE_PARTS * len(whole))
    for k in range(len(whole)):
        var first = parts[DRAPE_PARTS * k]
        var last = parts[DRAPE_PARTS * k + DRAPE_PARTS - 1]
        assert_true(first.node == whole[k].node)
        assert_true(first.radius == whole[k].radius)
        assert_true((first.start - whole[k].start).length() < 1e-6)
        assert_true((last.end - whole[k].end).length() < 1e-6)


def test_a_hat_grows_nothing_and_a_pauldron_grows_the_shoulder() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.add(great_helm())
    outfit.add(great_pauldrons())
    outfit.add(boots())
    var dressed = dress(scene, assets, person, outfit)
    var base = body_parts(person)
    var fit = dressed_colliders(person, outfit, dressed)
    # No skirt: one collider for each part of the body.
    assert_equal(len(fit), len(base))
    var s = skirt_scale(person.rig)
    var shoulders = 0
    for k in range(len(fit)):
        assert_true(fit[k].radius >= base[k].radius)
        assert_true(fit[k].radius <= base[k].radius + DRAPE_GROWTH * s + 1e-6)
        assert_true(fit[k].radius <= 2 * base[k].radius + 1e-6)
        var joint = _joint_of(person, fit[k].node.value)
        if joint == RIGHT_UPPER_ARM.value or joint == LEFT_UPPER_ARM.value:
            if fit[k].radius > base[k].radius:
                shoulders += 1
    # Each pauldron grows a part of its shoulder.
    assert_true(shoulders >= 2)
    # A hat alone grows nothing.
    var hatted = Outfit()
    hatted.add(great_helm())
    var other = Scene()
    var more = Assets()
    var bare = coarse_person(other, more)
    var helmed = dress(other, more, bare, hatted)
    var same = dressed_colliders(bare, hatted, helmed)
    var plain = body_parts(bare)
    for k in range(len(same)):
        assert_true(same[k].radius == plain[k].radius)


def test_a_robe_is_held_in_bands_across_the_hips() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.add(shirt())
    outfit.add(wizard_robe())
    var dressed = dress(scene, assets, person, outfit)
    var parts = len(body_parts(person))
    var fit = dressed_colliders(person, outfit, dressed)
    assert_true(len(fit) > parts + 5)
    var hips = person.rig.joints[HIPS.value]
    var deepest = Float32(0)
    for k in range(parts, len(fit)):
        assert_true(fit[k].node == person.bones[HIPS.value])
        # Each band lies level across the person.
        assert_almost_equal(fit[k].start.y, fit[k].end.y)
        assert_almost_equal(fit[k].start.z, fit[k].end.z)
        deepest = max(deepest, fit[k].radius)
    # The bands deepen toward the hem, as the robe flares.
    assert_true(fit[len(fit) - 1].radius > fit[parts].radius)
    assert_true(deepest > 1.5 * fit[parts].radius)
    # The robe's back, below the skirt's top, lies inside its bands.
    var top = skirt_top(person.rig)
    ref placed = dressed.shells[1].attribute_view(String(POSITION))
    var middle = hips.x
    var checked = 0
    for v in range(placed.count()):
        var p = placed.vector3(v)
        if p.y >= top or abs(p.x - middle) > 0.015 or p.z > hips.z:
            continue
        var inside = False
        for k in range(parts, len(fit)):
            var a = hips + fit[k].start
            var b = hips + fit[k].end
            if (p - nearest_on_segment(p, a, b)).length() <= fit[k].radius:
                inside = True
        assert_true(inside)
        checked += 1
    assert_true(checked > 10)


def test_a_band_with_no_point_has_no_capsule() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var top = skirt_top(person.rig)
    var band = DRAPE_BAND * skirt_scale(person.rig)
    # A point in the first band and one in the sixth: four empty between.
    var points: List[Vector3] = [
        Vector3(0.1, top - 0.5 * band, -0.1),
        Vector3(-0.1, top - 5.5 * band, 0.1),
    ]
    var bands = skirt_bands(person, points)
    assert_equal(len(bands), 2)
    # The lower band is deeper, as it swings farther.
    assert_true(bands[1].radius > bands[0].radius)


def test_a_mismatch_is_refused_and_an_empty_shell_grows_nothing() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.add(shirt())
    with assert_raises(contains="one shell per garment"):
        _ = dressed_colliders(person, outfit, Dressed([], []))
    var empty = Dressed([-1], [BufferGeometry()])
    var fit = dressed_colliders(person, outfit, empty)
    var base = body_parts(person)
    assert_equal(len(fit), len(base))
    for k in range(len(fit)):
        assert_true(fit[k].radius == base[k].radius)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
