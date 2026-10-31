# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the tailor's garments: shirts, skirts, aprons, coats and
gowns, cut and shaped."""

from core.assets import Assets
from core.buffer_geometry import POSITION, BufferGeometry
from core.scene import Scene
from extensions.attire.apparel import apparel, trousers
from extensions.attire.armory import armory
from extensions.attire.garment import shirt, wardrobe
from extensions.attire.kinds import (
    COLLAR_RUFFLE,
    CUFF_RUFFLES,
    BISHOP_SLEEVE,
    FRONT_ONLY,
    FRONT_PANEL,
    OPEN_BELOW,
    OPEN_FRONT,
    PUFFED_SHOULDER,
    SCOOP_NECK,
    SKIRTED,
    SLIT_NECK,
    SQUARE_NECK,
    V_NECK,
)
from extensions.attire.outfit import Outfit, dress
from extensions.attire.tailor import (
    apron,
    ball_gown,
    chemise,
    doublet,
    frock_coat,
    laced_bodice,
    laced_shirt,
    long_coat,
    open_robe,
    skirt,
    tailored,
    waistcoat,
)
from extensions.humanoid.rig.game import GameHumanoid
from extensions.humanoid.rig.joints import (
    HIPS,
    NECK,
    RIGHT_FOREARM,
    SPINE,
)
from extensions.attire.skirt import skirt_top
from extensions.attire.springs import nearest_on_segment
from objects.skinned_mesh import SKIN_INDEX
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)
from core.object3d import Object3D
from extensions.humanoid.rig.game import add_game_humanoid
from std.sys import num_logical_cores
from tests._attire_people import coarse_person, coarse_spec


def _mesh_of(scene: Scene, assets: Assets, mesh: Int) raises -> BufferGeometry:
    """Return the geometry a garment draws, in its bind pose."""
    return assets.geometries.get(scene.skinned_meshes[mesh].geometry).clone()


def test_each_garment_checks_and_is_shaped_as_its_table_says() raises:
    var names = List[String]()
    for garment in wardrobe():
        names.append(garment.name)
    for garment in armory():
        names.append(garment.name)
    for garment in apparel():
        names.append(garment.name)
    var made = tailored()
    assert_equal(len(made), 11)
    for garment in made:
        garment.check()
        assert_false(garment.name in names)
        names.append(garment.name)
    assert_true(chemise().neckline == SCOOP_NECK)
    assert_true(chemise().sleeve == BISHOP_SLEEVE)
    assert_true(laced_shirt().neckline == SLIT_NECK)
    assert_true(laced_bodice().neckline == SQUARE_NECK)
    assert_true(skirt().form == SKIRTED)
    assert_true(apron().opening == FRONT_ONLY)
    assert_true(doublet().sleeve == PUFFED_SHOULDER)
    assert_true(doublet().pattern == FRONT_PANEL)
    assert_true(waistcoat().neckline == V_NECK)
    assert_true(frock_coat().opening == OPEN_BELOW)
    assert_true(long_coat().opening == OPEN_FRONT)
    assert_true(open_robe().opening == OPEN_FRONT)
    assert_true(ball_gown().neckline == SQUARE_NECK)
    assert_true(ball_gown().flare > 0.5)
    assert_true(chemise().ruffles == CUFF_RUFFLES | COLLAR_RUFFLE)
    assert_true(ball_gown().ruffles == CUFF_RUFFLES)


def test_an_apron_covers_the_front_alone() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.add(chemise())
    outfit.add(skirt())
    outfit.add(apron())
    var dressed = dress(scene, assets, person, outfit)
    var hips = person.rig.joints[HIPS.value]
    ref placed = dressed.shells[2].attribute_view(String(POSITION))
    assert_true(placed.count() > 0)
    for v in range(placed.count()):
        assert_true(placed.vector3(v).z > hips.z)
    # The skirt behind it is drawn whole.
    assert_true(dressed.meshes[1] >= 0)


def _front_of(
    person: GameHumanoid, mesh: BufferGeometry, low: Float32, high: Float32
) raises -> Int:
    """Return how many vertices of a mesh lie on the front's middle, from
    `low` to `high` up."""
    var hips = person.rig.joints[HIPS.value]
    ref placed = mesh.attribute_view(String(POSITION))
    var count = 0
    for v in range(placed.count()):
        var p = placed.vector3(v)
        if (
            abs(p.x - hips.x) < 0.03
            and p.z > hips.z
            and p.y > low
            and (p.y < high)
        ):
            count += 1
    return count


def test_a_parted_coat_shows_the_waistcoat_and_a_v_the_shirt() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.add(shirt())
    outfit.add(trousers())
    outfit.add(waistcoat())
    outfit.add(frock_coat())
    var dressed = dress(scene, assets, person, outfit)
    var waist = person.rig.joints[SPINE.value].y
    var neck = person.rig.joints[NECK.value].y
    var top = skirt_top(person.rig)
    var coat = _mesh_of(scene, assets, dressed.meshes[3])
    var vest = _mesh_of(scene, assets, dressed.meshes[2])
    # Below the waist, the coat's skirts are parted down the front, and
    # the waistcoat shows there.
    assert_equal(_front_of(person, coat, top - 0.3, top - 0.02), 0)
    assert_true(_front_of(person, vest, waist - 0.12, waist - 0.02) > 0)
    # Above the waist, the coat closes over it.
    assert_true(_front_of(person, coat, waist + 0.05, waist + 0.2) > 0)
    # A waistcoat alone shows the shirt in its V. The coarse person's
    # triangles are wider than the V, so a finer one wears it.
    var other = Scene()
    var more = Assets()
    var bare = add_game_humanoid(
        other,
        more,
        other.add(Object3D()),
        coarse_spec(),
        9000,
        24,
        8,
        8,
        workers=num_logical_cores(),
    )
    var vested = Outfit()
    vested.add(shirt())
    vested.add(waistcoat())
    var worn = dress(other, more, bare, vested)
    var linen = _mesh_of(other, more, worn.meshes[0])
    var silk = worn.shells[1].clone()
    assert_true(_front_of(bare, linen, neck - 0.09, neck - 0.03) > 0)
    # The waistcoat's own shell is cut away in the V.
    var hips = bare.rig.joints[HIPS.value]
    ref placed = silk.attribute_view(String(POSITION))
    for v in range(placed.count()):
        var p = placed.vector3(v)
        assert_false(
            abs(p.x - hips.x) < 0.015
            and p.z > hips.z
            and p.y > neck - 0.09
            and p.y < neck - 0.03
        )


def _sleeve_reach(
    person: GameHumanoid, shell: BufferGeometry
) raises -> Float32:
    """Return how far a shell stands on average from the right forearm's
    axis, on the middle of the forearm, where the forearm weighs most."""
    var a = person.rig.joints[RIGHT_FOREARM.value]
    var b = person.rig.ends[RIGHT_FOREARM.value]
    var bone = b - a
    var length = bone.length()
    ref placed = shell.attribute_view(String(POSITION))
    ref bones = shell.attribute_view(String(SKIN_INDEX))
    var total = Float32(0)
    var count = 0
    for v in range(placed.count()):
        if Int(bones.component(v, 0)) != RIGHT_FOREARM.value:
            continue
        var p = placed.vector3(v)
        var t = (p - a).dot(bone) / (length * length)
        if t > 0.5 and t < 0.8:
            total += (p - nearest_on_segment(p, a, b)).length()
            count += 1
    return total / Float32(max(count, 1))


def test_a_bishop_sleeve_stands_out_round_the_forearm() raises:
    var scene = Scene()
    var assets = Assets()
    var plain = coarse_person(scene, assets)
    var full = coarse_person(scene, assets)
    var fitted = Outfit()
    fitted.add(shirt())
    var gathered = Outfit()
    gathered.add(chemise())
    var one = dress(scene, assets, plain, fitted)
    var two = dress(scene, assets, full, gathered)
    var narrow = _sleeve_reach(plain, one.shells[0])
    var wide = _sleeve_reach(full, two.shells[0])
    assert_true(narrow > 0)
    assert_true(wide > narrow + 0.012)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
