# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Villagers who talk, and the errands they give."""

from core.assets import Assets
from core.scene import Scene
from extensions.village.gathering import (
    CHEST,
    GatherKind,
    HERBS,
    ORE,
    Satchel,
    TRINKET,
)
from extensions.village.surfaces import house_looks
from extensions.village.talk import (
    DONE,
    Errand,
    ErrandState,
    MARKER_LIFT,
    OFFERED,
    SPEECH_SECONDS,
    Speaker,
    TAKEN,
    Talk,
    default_speakers,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import SECOND, Duration


def test_the_states_and_the_errands_are_checked() raises:
    assert_true(DONE.is_valid())
    assert_false(ErrandState(3).is_valid())
    Errand(TRINKET, 1, 5, "a", "b").check()
    with assert_raises(contains="must want"):
        Errand(CHEST, 2, 5, "a", "b").check()
    with assert_raises(contains="must want"):
        Errand(GatherKind(9), 2, 5, "a", "b").check()
    with assert_raises(contains="one thing or more"):
        Errand(HERBS, 0, 5, "a", "b").check()
    with assert_raises(contains="negative"):
        Errand(HERBS, 2, -1, "a", "b").check()
    # The default village has five speakers, four with errands.
    var speakers = default_speakers()
    assert_equal(len(speakers), 5)
    var errands = 0
    for speaker in speakers:
        if speaker.errand:
            errands += 1
            speaker.errand.value().check()
        assert_true(len(speaker.lines) > 0)
    assert_equal(errands, 4)


def _speakers() -> List[Speaker]:
    """Return a speaker with an errand for three herbs and one with none,
    and one who is no villager."""
    return [
        Speaker(
            0,
            "Ann",
            ["Hello."],
            Errand(HERBS, 3, 10, "Three herbs, please.", "Thank you."),
        ),
        Speaker(1, "Bert", ["One.", "Two."], None),
        Speaker(7, "Nobody", ["Nothing."], None),
    ]


def _talk(mut scene: Scene, mut assets: Assets) raises -> Talk:
    """Return the talk of two villagers."""
    return Talk(scene, assets, house_looks(assets, 4, 1), _speakers(), 2)


def test_a_speaker_who_is_no_villager_is_left_out() raises:
    var assets = Assets()
    var scene = Scene()
    var talk = _talk(scene, assets)
    assert_equal(len(talk.speakers), 2)
    assert_true(talk.states[0] == OFFERED)
    assert_true(talk.states[1] == DONE)
    assert_equal(len(scene.meshes), 4)
    # Two speakers of one villager are refused, and so is a bad errand.
    var twice: List[Speaker] = [
        Speaker(0, "A", ["a"], None),
        Speaker(0, "B", ["b"], None),
    ]
    with assert_raises(contains="one villager"):
        _ = Talk(scene, assets, house_looks(assets, 4, 1), twice^, 2)
    var greedy: List[Speaker] = [
        Speaker(0, "A", ["a"], Errand(HERBS, 0, 1, "x", "y"))
    ]
    with assert_raises(contains="one thing or more"):
        _ = Talk(scene, assets, house_looks(assets, 4, 1), greedy^, 2)
    # No speaker at all is a village where nobody talks.
    var nobody = Talk(
        scene, assets, house_looks(assets, 4, 1), List[Speaker](), 0
    )
    assert_equal(len(nobody.speakers), 0)
    var away: List[Speaker] = [Speaker(-1, "A", ["a"], None)]
    assert_equal(
        len(Talk(scene, assets, house_looks(assets, 4, 1), away^, 2).speakers),
        0,
    )


def test_the_nearest_speaker_in_reach_is_the_focus() raises:
    var assets = Assets()
    var scene = Scene()
    var talk = _talk(scene, assets)
    var places: List[Vector3] = [Vector3(0, 0, 0), Vector3(3, 0, 0)]
    assert_equal(talk.nearest(Vector3(0.5, 0, 0), places), 0)
    assert_equal(talk.nearest(Vector3(2.4, 0, 0), places), 1)
    assert_equal(talk.nearest(Vector3(1.5, 0, 9), places), -1)
    assert_equal(talk.nearest(Vector3(0.5, 2, 0), places), -1)
    assert_equal(talk.prompt(), "")


def test_an_errand_is_asked_taken_and_paid() raises:
    var assets = Assets()
    var scene = Scene()
    var talk = _talk(scene, assets)
    var satchel = Satchel()
    assert_equal(talk.speak(0, satchel), "Three herbs, please.")
    assert_true(talk.states[0] == TAKEN)
    assert_equal(talk.speak(0, satchel), "I still need 3 more herbs.")
    satchel.counts[HERBS.value] = 2
    assert_equal(talk.errands(satchel)[0], "herbs for Ann 2/3")
    satchel.counts[HERBS.value] = 4
    assert_equal(talk.errands(satchel)[0], "herbs for Ann 3/3")
    assert_equal(talk.speak(0, satchel), "Thank you.")
    assert_true(talk.states[0] == DONE)
    assert_equal(satchel.count(HERBS), 1)
    assert_equal(satchel.count(CHEST), 10)
    assert_equal(len(talk.errands(satchel)), 0)
    # Once done, and with no errand, a speaker says their lines in turn.
    assert_equal(talk.speak(0, satchel), "Hello.")
    assert_equal(talk.speak(1, satchel), "One.")
    assert_equal(talk.speak(1, satchel), "Two.")
    assert_equal(talk.speak(1, satchel), "One.")
    with assert_raises(contains="one of the village's"):
        _ = talk.speak(2, satchel)
    with assert_raises(contains="one of the village's"):
        _ = talk.speak(-1, satchel)


def test_a_press_speaks_and_the_markers_follow() raises:
    var assets = Assets()
    var scene = Scene()
    var talk = _talk(scene, assets)
    var satchel = Satchel()
    var places: List[Vector3] = [Vector3(0, 1, 0), Vector3(5, 1, 0)]
    var heads: List[Float32] = [1.6, 1.8]
    var step = Duration(0.1, SECOND)
    var feet = Vector3(0.8, 1, 0)
    # A held button speaks once, on its press.
    assert_true(talk.update(scene, feet, places, heads, True, satchel, step))
    assert_equal(talk.speech, "Ann: Three herbs, please.")
    assert_equal(talk.age, 0)
    assert_false(talk.update(scene, feet, places, heads, True, satchel, step))
    assert_almost_equal(talk.age, 0.1, atol=1e-6)
    assert_equal(talk.prompt(), "E  TALK TO Ann")
    # The taken errand's marker shows over her head; the offer's hides.
    assert_false(scene.node(talk.offers[0]).visible)
    ref waiting = scene.node(talk.takens[0])
    assert_true(waiting.visible)
    assert_true(waiting.position.y > 1 + 1.6 + MARKER_LIFT - 0.1)
    assert_almost_equal(waiting.position.x, 0, atol=1e-6)
    # Bert has no errand: neither of his markers shows.
    assert_false(scene.node(talk.offers[1]).visible)
    assert_false(scene.node(talk.takens[1]).visible)
    # A press with no speaker in reach says nothing.
    _ = talk.update(scene, feet, places, heads, False, satchel, step)
    var far = Vector3(20, 1, 0)
    assert_false(talk.update(scene, far, places, heads, True, satchel, step))
    assert_equal(talk.focus, -1)
    with assert_raises(contains="negative"):
        _ = talk.update(
            scene, feet, places, heads, False, satchel, Duration(-1.0, SECOND)
        )
    assert_true(SPEECH_SECONDS > 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
