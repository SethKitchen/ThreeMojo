# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the engineering estimates of an outfit."""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from loaders.json import parse_json
from objects.skinned_mesh import SKIN_INDEX
from core.scene import Scene
from extensions.anatomy.evidence import DESIGN, FROM_TEXT
from extensions.anatomy.inertia import InertiaTally
from extensions.attire.estimate import (
    PIERCED,
    attire_report,
    STOPPED,
    BlowOutcome,
    coverage,
    garment_mass,
    locomotion_cost,
    locomotion_source,
    noise,
    outcome_label,
    outfit_mass,
    piercing_energy,
    piercing_source,
    protection,
    require_outcome,
    triangle_area,
    visibility,
    worn_tallies,
)
from extensions.attire.fabric import fabric
from extensions.attire.garment import (
    bascinet,
    boots,
    cuirass,
    gambeson,
    hauberk,
    hood,
    hose,
    shirt,
    surcoat,
)
from extensions.attire.kinds import (
    FABRIC_KIND_COUNT,
    LINEN,
    MAIL,
    PADDING,
    PLATE,
    FabricKind,
)
from extensions.attire.outfit import Dressed, Outfit, dress
from extensions.humanoid.canonical import (
    HEAD_NECK_REGION,
    LEFT_FOOT_REGION,
    REGION_COUNT,
    TRUNK_REGION,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    JOINT_COUNT,
    LEFT_SHIN,
    RIGHT_FOREARM,
    RIGHT_SHIN,
    Joint,
)
from math.vector3 import Vector3
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import coarse_person, empty_mesh, line_rig, strip
from units.si import JOULE, KILOGRAM, MILLIMETER, Energy, Length, Mass


def _tallies(
    trunk: Float64, arms: Float64, legs: Float64
) raises -> List[InertiaTally]:
    """Return tallies with the given masses on the chest, an arm and a
    shin."""
    var tallies = List[InertiaTally]()
    for _ in range(JOINT_COUNT):
        tallies.append(InertiaTally())
    var zero = Vector3(0, 0, 0)
    tallies[CHEST.value].add_cell(trunk, zero, zero)
    tallies[RIGHT_FOREARM.value].add_cell(arms, zero, zero)
    tallies[RIGHT_SHIN.value].add_cell(legs, zero, zero)
    return tallies^


def test_outcomes_are_named() raises:
    assert_equal(outcome_label(STOPPED), "stopped")
    assert_equal(outcome_label(PIERCED), "pierced")
    assert_equal(outcome_label(BlowOutcome(5)), "outcome")
    require_outcome(PIERCED)
    with assert_raises(contains="must be named"):
        require_outcome(BlowOutcome(-1))


def test_a_garment_weighs_its_area_times_its_fabric() raises:
    # A strip one meter square.
    var sheet = strip(0, 2, Joint(0))
    assert_almost_equal(triangle_area(sheet, 0), 0.25)
    var linen = garment_mass(sheet, fabric(LINEN))
    assert_almost_equal(linen.value, 0.2, atol=1e-6)
    var plate = garment_mass(sheet, fabric(PLATE))
    assert_almost_equal(plate.value, 15.7, atol=1e-4)


def test_walking_costs_more_with_weight_on_the_legs() raises:
    var body = Mass(75, KILOGRAM)
    assert_equal(locomotion_cost(_tallies(0, 0, 0), body), 1)
    # A 40 kg harness, 30 percent of it on the legs, costs about 2.1.
    var harness = locomotion_cost(_tallies(18, 10, 12), body)
    assert_true(harness > 2.0 and harness < 2.25)
    # The same mass on the trunk alone costs less.
    var trunk = locomotion_cost(_tallies(40, 0, 0), body)
    assert_true(trunk < harness)
    assert_almost_equal(outfit_mass(_tallies(18, 10, 12)).value, 40)
    assert_equal(locomotion_source().evidence, DESIGN)
    with assert_raises(contains="one tally per joint"):
        _ = locomotion_cost(List[InertiaTally](), body)
    with assert_raises(contains="must be positive"):
        _ = locomotion_cost(_tallies(1, 1, 1), Mass(0, KILOGRAM))


def test_layers_stop_a_blow_from_the_outside_in() raises:
    var rig = line_rig()
    var outfit = Outfit()
    outfit.add(gambeson())
    outfit.add(hauberk())
    var hit = Energy(110, JOULE)
    # Mail takes 80 J and the padding 40 J: 110 J stops in the padding.
    var stopped = protection(outfit, rig, CHEST, 0.5, hit)
    assert_equal(stopped.outcome, STOPPED)
    assert_equal(stopped.stopped_by, "gambeson")
    assert_equal(stopped.left.value, 0)
    var hard = protection(outfit, rig, CHEST, 0.5, Energy(150, JOULE))
    assert_equal(hard.outcome, PIERCED)
    assert_almost_equal(hard.left.value, 30)
    # Over the shin there is nothing.
    var bare = protection(outfit, rig, RIGHT_SHIN, 0.5, hit)
    assert_equal(bare.outcome, PIERCED)
    assert_almost_equal(bare.left.value, 110)
    outfit.add(cuirass())
    var plated = protection(outfit, rig, CHEST, 0.5, Energy(170, JOULE))
    assert_equal(plated.stopped_by, "cuirass")
    with assert_raises(contains="named joint"):
        _ = protection(outfit, rig, Joint(JOINT_COUNT), 0.5, hit)
    with assert_raises(contains="zero or more"):
        _ = protection(outfit, rig, CHEST, 0.5, Energy(-1, JOULE))
    var refused = Outfit()
    refused.garments.append(hose())
    refused.garments.append(hose())
    with assert_raises(contains="already has"):
        _ = protection(refused, rig, CHEST, 0.5, hit)


def test_each_fabric_has_a_piercing_energy() raises:
    for k in range(FABRIC_KIND_COUNT):
        var kind = FabricKind(k)
        assert_true(piercing_energy(fabric(kind)).value > 0)
        _ = piercing_source(kind)
    # Plate at 2 mm takes 175 J; at 1 mm a quarter of that.
    assert_almost_equal(piercing_energy(fabric(PLATE)).value, 175, atol=1e-3)
    var thin = fabric(PLATE)
    thin.thickness = Length(1, MILLIMETER)
    assert_almost_equal(piercing_energy(thin).value, 43.75, atol=1e-3)
    assert_equal(piercing_source(MAIL).evidence, FROM_TEXT)
    assert_equal(piercing_source(PADDING).evidence, FROM_TEXT)
    assert_equal(piercing_source(LINEN).evidence, DESIGN)
    var unnamed = fabric(LINEN)
    unnamed.kind = FabricKind(-1)
    with assert_raises(contains="named kind"):
        _ = piercing_energy(unnamed)
    with assert_raises(contains="named kind"):
        _ = piercing_source(FabricKind(77))


def test_noise_and_visibility_are_game_hooks() raises:
    var quiet = Outfit()
    quiet.add(shirt())
    quiet.add(hood())
    var loud = Outfit()
    loud.add(gambeson())
    loud.add(hauberk())
    loud.add(cuirass())
    loud.add(bascinet())
    loud.add(boots())
    assert_true(noise(quiet) < 0.1)
    assert_equal(noise(loud), 1)
    # The shirt is hidden under the surcoat; the coat's red shows.
    var coated = Outfit()
    coated.add(shirt())
    coated.add(surcoat())
    var shown = visibility(coated)
    var red = surcoat().dyes[0]
    var expected = (
        0.2126 * Float32(red.r)
        + 0.7152 * Float32(red.g)
        + 0.0722 * Float32(red.b)
    ) / 255
    assert_almost_equal(shown, expected, atol=1e-5)
    assert_true(visibility(loud) > visibility(quiet))
    assert_equal(visibility(Outfit()), 0)
    var refused = Outfit()
    refused.garments.append(hose())
    refused.garments.append(hose())
    with assert_raises(contains="already has"):
        _ = noise(refused)
    with assert_raises(contains="already has"):
        _ = visibility(refused)


def test_a_dressed_person_carries_the_outfit_s_mass() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.add(hose())
    outfit.add(hauberk())
    outfit.add(hood())
    var skin = assets.geometries.get(
        scene.skinned_meshes[person.skins[0]].geometry
    ).clone()
    var shares = coverage(skin, person.rig, outfit)
    assert_equal(len(shares), REGION_COUNT)
    assert_true(shares[TRUNK_REGION.value] > 0.9)
    assert_true(shares[HEAD_NECK_REGION.value] > 0.5)
    assert_true(shares[HEAD_NECK_REGION.value] < 0.95)
    # The body mesh has no hand skin: the hands' regions have none.
    var dressed = dress(scene, assets, person, outfit)
    var tallies = worn_tallies(outfit, dressed)
    var total = outfit_mass(tallies).value
    # A hauberk weighs about 9 kg; the hose and the hood a little more.
    assert_true(total > 7 and total < 14)
    assert_true(tallies[CHEST.value].mass > tallies[LEFT_SHIN.value].mass)
    # The hauberk weighs its whole shell, though the hood hides some.
    ref drawn = assets.geometries.get(
        scene.skinned_meshes[dressed.meshes[1]].geometry
    )
    assert_true(
        garment_mass(dressed.shells[1], fabric(MAIL)).value
        >= garment_mass(drawn, fabric(MAIL)).value
    )
    var shells = List[BufferGeometry]()
    shells.append(BufferGeometry())
    with assert_raises(contains="one per garment"):
        _ = worn_tallies(outfit, Dressed([0], shells^))
    with assert_raises(contains="one shell per garment"):
        _ = Dressed([0, 1], List[BufferGeometry]())
    # A garment with no shell weighs nothing.
    var empty = List[BufferGeometry]()
    for _ in range(3):
        empty.append(BufferGeometry())
    var none = Dressed([-1, -1, -1], empty^)
    assert_equal(outfit_mass(worn_tallies(outfit, none)).value, 0)
    # A shell whose weight names no joint is refused.
    var bad = dressed.shells[0].clone()
    var bones = bad.clone_attribute(String(SKIN_INDEX))
    bones.set_component(0, 0, 99)
    bad.set_attribute(String(SKIN_INDEX), bones^)
    var broken = List[BufferGeometry]()
    broken.append(bad^)
    broken.append(BufferGeometry())
    broken.append(BufferGeometry())
    with assert_raises(contains="names no joint"):
        _ = worn_tallies(outfit, Dressed([-1, -1, -1], broken^))
    # The report gathers every estimate.
    var report = attire_report(
        skin, person.rig, outfit, dressed, Mass(80, KILOGRAM)
    )
    assert_true(report.boolean("template_estimate"))
    var parsed = parse_json(report.json("protection"))
    assert_equal(parsed.length(parsed.root()), 12)
    assert_true(report.number("total_mass_kg") > 7)
    var refused = Outfit()
    refused.garments.append(hose())
    refused.garments.append(hose())
    with assert_raises(contains="already has"):
        _ = coverage(skin, person.rig, refused)


def test_an_empty_outfit_weighs_covers_and_stops_nothing() raises:
    var rig = line_rig()
    var body = Mass(80, KILOGRAM)
    assert_equal(garment_mass(BufferGeometry(), fabric(LINEN)).value, 0)
    assert_equal(garment_mass(empty_mesh(), fabric(LINEN)).value, 0)
    var bare = Outfit()
    var nothing = Dressed(List[Int](), List[BufferGeometry]())
    var tallies = worn_tallies(bare, nothing)
    assert_equal(len(tallies), JOINT_COUNT)
    assert_equal(outfit_mass(tallies).value, 0)
    assert_equal(outfit_mass(List[InertiaTally]()).value, 0)
    assert_equal(locomotion_cost(tallies, body), 1)
    var covered = coverage(empty_mesh(), rig, bare)
    assert_equal(len(covered), REGION_COUNT)
    assert_equal(noise(bare), 0)
    var report = attire_report(empty_mesh(), rig, bare, nothing, body)
    assert_true(report.boolean("template_estimate"))
    # A garment whose shell has no triangle weighs nothing.
    var one = Outfit()
    one.add(shirt())
    assert_equal(len(coverage(empty_mesh(), rig, one)), REGION_COUNT)
    var shells = List[BufferGeometry]()
    shells.append(empty_mesh())
    assert_equal(
        outfit_mass(worn_tallies(one, Dressed([-1], shells^))).value, 0
    )


def test_out_of_range_estimates_are_refused() raises:
    var rig = line_rig()
    with assert_raises(contains="positive"):
        _ = locomotion_cost(_tallies(1, 1, 1), Mass(1e7, KILOGRAM))
    var outfit = Outfit()
    outfit.add(shirt())
    with assert_raises(contains="zero or more"):
        _ = protection(outfit, rig, CHEST, 0.5, Energy(1e13, JOULE))
    # A shell whose weight names a bone below zero is refused.
    var shell = strip(0, 1, CHEST)
    var bones = shell.clone_attribute(String(SKIN_INDEX))
    for v in range(4):
        bones.set_component(v, 0, -1)
    shell.set_attribute(String(SKIN_INDEX), bones^)
    var shells = List[BufferGeometry]()
    shells.append(shell^)
    with assert_raises(contains="names no joint"):
        _ = worn_tallies(outfit, Dressed([-1], shells^))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
