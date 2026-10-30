# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for saved outfits and dressed bakes."""

from core.assets import Assets
from core.scene import Scene
from core.user_data import UserData
from extensions.attire.garment import (
    bascinet,
    boots,
    coif,
    cuirass,
    fauld,
    gambeson,
    gloves,
    greaves,
    hauberk,
    hood,
    hose,
    pauldrons,
    shirt,
    surcoat,
    vambraces,
)
from extensions.attire.kinds import FITTED
from extensions.attire.outfit import Outfit, dress
from extensions.attire.preset import (
    OUTFIT_KEY,
    garment_record,
    joint_named,
    outfit_from_json,
    outfit_json,
    outfit_named,
    outfit_record,
    stored_outfit,
    write_dressed_bake,
)
from extensions.humanoid.fidelity import (
    CANONICAL_RECIPE,
    GAME_RECIPE,
    humanoid_provenance,
)
from extensions.humanoid.rig.game import game_build_settings
from extensions.humanoid.rig.joints import named_joints, joint_label
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from loaders.gltf import read_gltf
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_people import coarse_person, coarse_spec
from tests.test_scratch import TestScratch, temporary_path
from units.si import FOOT, Length


def _harness() raises -> Outfit:
    """Return an outfit of fifteen garments, one in each slot and layer."""
    var outfit = Outfit()
    for garment in [
        shirt(),
        hose(),
        gambeson(),
        hauberk(),
        coif(),
        hood(),
        boots(),
        gloves(),
        cuirass(),
        fauld(),
        pauldrons(),
        vambraces(),
        greaves(),
        bascinet(),
        surcoat(),
    ]:
        outfit.add(garment.copy())
    return outfit^


def _swap(text: String, old: String, new: String) raises -> String:
    """Return `text` with each `old` replaced; one must be there."""
    var at = text.find(old)
    if at < 0:
        raise Error("The text has no " + old)
    return text.replace(old, new)


def _drop(text: String, key: String) raises -> String:
    """Return `text` without one `,"key":value` field."""
    var start = text.find(',"' + key + '":')
    if start < 0:
        raise Error("The text has no " + key)
    var end = text.find(",", start + 1)
    return String(text[byte=:start]) + String(text[byte=end:])


def test_joints_are_found_by_name() raises:
    for joint in named_joints():
        assert_equal(joint_named(joint_label(joint)), joint)
    with assert_raises(contains="No joint is named"):
        _ = joint_named("tail")


def test_an_outfit_round_trips_through_text() raises:
    var outfit = _harness()
    var text = outfit_json(outfit)
    var again = outfit_from_json(text)
    assert_equal(len(again.garments), len(outfit.garments))
    for k in range(len(outfit.garments)):
        ref a = outfit.garments[k]
        ref b = again.garments[k]
        assert_equal(a.name, b.name)
        assert_equal(a.slot, b.slot)
        assert_equal(a.layer, b.layer)
        assert_equal(a.fabric, b.fabric)
        assert_equal(a.articulation, b.articulation)
        assert_equal(a.anchor, b.anchor)
        assert_equal(a.lames, b.lames)
        assert_equal(a.pattern, b.pattern)
        assert_equal(a.drape, b.drape)
        assert_equal(a.cover.face_open, b.cover.face_open)
        assert_equal(a.cover.starts, b.cover.starts)
        assert_equal(a.cover.ends, b.cover.ends)
        assert_true(abs(a.ease.value - b.ease.value) < 1e-6)
        assert_equal(a.form, b.form)
        assert_true(abs(a.flare - b.flare) < 1e-6)
        for c in range(4):
            assert_true(a.dyes[c] == b.dyes[c])
    # Written again, the text is the same.
    assert_equal(outfit_json(again), text)
    var record = garment_record(cuirass())
    assert_equal(record.string("anchor"), "chest")
    assert_equal(record.json("lames"), "0")


def test_three_outfits_are_named() raises:
    var peasant = outfit_named("peasant")
    assert_equal(len(peasant.garments), 5)
    assert_equal(peasant.garments[0].name, "shirt")
    var soldier = outfit_named("man-at-arms")
    assert_equal(len(soldier.garments), 7)
    var knight = outfit_named("knight")
    assert_equal(len(knight.garments), 13)
    assert_equal(knight.garments[12].name, "surcoat")
    peasant.check()
    soldier.check()
    knight.check()
    with assert_raises(contains="No outfit is named"):
        _ = outfit_named("jester")


def test_an_empty_outfit_round_trips() raises:
    var text = outfit_json(Outfit())
    assert_equal(len(outfit_from_json(text).garments), 0)


def test_malformed_outfits_are_refused() raises:
    var outfit = Outfit()
    outfit.add(boots())
    var text = outfit_json(outfit)
    with assert_raises(contains="version 2"):
        _ = outfit_from_json(_swap(text, '"version":1', '"version":2'))
    with assert_raises(contains="needs a version"):
        _ = outfit_from_json("{}")
    with assert_raises(contains="list of garments"):
        _ = outfit_from_json('{"version":1}')
    with assert_raises(contains="one value per joint"):
        _ = outfit_from_json(_swap(text, '"starts":[0,', '"starts":['))
    with assert_raises(contains="list of ends"):
        _ = outfit_from_json(_swap(text, '"ends":', '"end":'))
    with assert_raises(contains="four dyes"):
        _ = outfit_from_json(_swap(text, '"dyes":[[84,54,32],', '"dyes":['))
    with assert_raises(contains="three channels"):
        _ = outfit_from_json(_swap(text, "[84,54,32]", "[84,54]"))
    with assert_raises(contains="0 through 255"):
        _ = outfit_from_json(_swap(text, "[84,54,32]", "[84,54,320]"))
    with assert_raises(contains="0 through 255"):
        _ = outfit_from_json(_swap(text, "[84,54,32]", "[-1,54,32]"))
    with assert_raises(contains="No slot is named"):
        _ = outfit_from_json(_swap(text, '"slot":"feet"', '"slot":"toes"'))
    with assert_raises(contains="needs name"):
        _ = outfit_from_json(_swap(text, '"name":', '"title":'))
    with assert_raises(contains="list of dyes"):
        _ = outfit_from_json(_swap(text, '"dyes":', '"paints":'))
    with assert_raises(contains="No joint is named"):
        _ = outfit_from_json(_swap(text, '"anchor":null', '"anchor":"tail"'))
    with assert_raises(contains="No form is named"):
        _ = outfit_from_json(_swap(text, '"form":"shod"', '"form":"bare"'))
    # A garment that reads but does not check.
    with assert_raises(contains="A drape"):
        _ = outfit_from_json(_swap(text, '"drape":24', '"drape":-5'))
    with assert_raises(contains="A flare"):
        _ = outfit_from_json(_swap(text, '"flare":0', '"flare":2'))


def test_an_outfit_saved_before_forms_is_fitted() raises:
    var outfit = Outfit()
    outfit.add(surcoat())
    var text = outfit_json(outfit)
    assert_true(text.find('"form":"skirted"') >= 0)
    var old = _drop(_drop(text, "form"), "flare")
    assert_true(old.find("flare") < 0)
    var again = outfit_from_json(old)
    assert_equal(again.garments[0].form, FITTED)
    assert_equal(again.garments[0].flare, 0)


def test_a_dressed_bake_remembers_its_outfit_and_its_body() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.add(hose())
    outfit.add(boots())
    _ = dress(scene, assets, person, outfit)
    var record = humanoid_provenance(
        coarse_spec(),
        game_build_settings(3000, 12, 8, 8),
        String(CANONICAL_RECIPE),
        String(GAME_RECIPE),
        "unverified-converted-ICTF-THRS",
    )
    var path = temporary_path("dressed.glb")
    write_dressed_bake(path, scene, assets, record, outfit, coarse_spec())
    var loaded = Scene()
    var loaded_assets = Assets()
    var model = read_gltf(path, loaded, loaded_assets)
    var kept = stored_outfit(model.scene_extras, coarse_spec())
    assert_equal(len(kept.garments), 2)
    assert_equal(kept.garments[1].name, "boots")
    var other = HumanoidSpec(Length(5.0, FOOT), FEMALE)
    with assert_raises(contains="fitted to another body"):
        _ = stored_outfit(model.scene_extras, other)
    with assert_raises(contains="keeps no outfit"):
        _ = stored_outfit(UserData(), coarse_spec())
    var made = outfit_record(outfit, coarse_spec())
    assert_true(made.has("spec_fingerprint"))
    var bare = UserData()
    bare.set_json(String(OUTFIT_KEY), "{}")
    with assert_raises(contains="needs a fingerprint"):
        _ = stored_outfit(bare, coarse_spec())
    var hollow = UserData()
    hollow.set_json(
        String(OUTFIT_KEY),
        '{"spec_fingerprint":"' + made.string("spec_fingerprint") + '"}',
    )
    with assert_raises(contains="needs an outfit"):
        _ = stored_outfit(hollow, coarse_spec())


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
