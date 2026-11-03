# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The faces of the village's people: blinks, words, expressions and
breath."""

from extensions.humanoid.skeleton.head.expression import (
    ANGER,
    FacialExpression,
    SMILE,
)
from extensions.village.faces import (
    BLINK_SECONDS,
    FACE_PIXELS,
    HEAD_HEIGHT,
    FaceLife,
    face_reach,
)
from std.math import tan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, RADIAN, SECOND, Angle, Duration


def _step(mut life: FaceLife, seconds: Float32) raises -> Float32:
    """Move a face on, and return how far its left eye is shut."""
    return life.advance(Duration(seconds, SECOND)).get("eyeBlink_L")


def test_a_face_shows_its_mesh_within_its_reach() raises:
    var reach = face_reach(1080, Angle(60.0, DEGREE))
    var half = Float32(Angle(30.0, DEGREE).to(RADIAN))
    assert_almost_equal(
        reach, HEAD_HEIGHT * 1080 / (2 * tan(half) * FACE_PIXELS), atol=1e-4
    )
    # A frame twice as tall sees a face as far again.
    assert_almost_equal(
        face_reach(2160, Angle(60.0, DEGREE)), 2 * reach, atol=1e-4
    )
    with assert_raises(contains="height must be positive"):
        _ = face_reach(0, Angle(60.0, DEGREE))
    with assert_raises(contains="between 0 and 180"):
        _ = face_reach(100, Angle(0.0, DEGREE))
    with assert_raises(contains="between 0 and 180"):
        _ = face_reach(100, Angle(180.0, DEGREE))


def test_a_face_blinks_now_and_then() raises:
    var life = FaceLife(3)
    # The first blink is from 2 to 5.5 seconds in.
    assert_true(life.next_blink >= 2 and life.next_blink <= 5.5)
    var due = life.next_blink
    assert_equal(_step(life, due - 0.01), 0)
    # Halfway through it, the eyes are shut.
    var shut = _step(life, 0.01 + BLINK_SECONDS / 2)
    assert_almost_equal(shut, 1, atol=1e-3)
    # After it, they open, and the next is due later.
    assert_equal(_step(life, BLINK_SECONDS), 0)
    assert_equal(life.blinks, 1)
    assert_true(life.next_blink > due + 1.9)
    # Two faces blink at their own times.
    assert_true(FaceLife(4).next_blink != FaceLife(5).next_blink)
    with assert_raises(contains="must not be negative"):
        _ = life.advance(Duration(-1.0, SECOND))


def test_a_face_says_its_words() raises:
    var life = FaceLife(1)
    assert_false(life.speaking())
    life.say("Good ore")
    assert_true(life.speaking())
    var opened = Float32(0)
    for _ in range(10):
        var face = life.advance(Duration(0.05, SECOND))
        for w in face.weights:
            opened = max(opened, w)
    # The mouth makes the words' shapes, and stops after the last one.
    assert_true(opened > 0.5)
    _ = life.advance(Duration(5.0, SECOND))
    assert_false(life.speaking())
    var rest = life.advance(Duration(0.01, SECOND))
    for k in range(len(rest.weights)):
        if not rest.shapes[k].startswith("eyeBlink"):
            assert_equal(rest.weights[k], 0)


def test_a_face_eases_to_its_expression_and_back() raises:
    var life = FaceLife(1)
    life.feel(SMILE, 0.8, 1)
    _ = life.advance(Duration(0.0, SECOND))
    # The neutral face goes out at once, as it shows nothing.
    assert_true(life.mood == SMILE)
    _ = life.advance(Duration(0.1, SECOND))
    assert_almost_equal(life.strength, 0.5, atol=1e-4)
    _ = life.advance(Duration(0.2, SECOND))
    assert_almost_equal(life.strength, 0.8, atol=1e-4)
    # Another expression comes in after the last goes out.
    life.feel(ANGER, 0.5)
    _ = life.advance(Duration(0.1, SECOND))
    assert_true(life.mood == SMILE)
    assert_almost_equal(life.strength, 0.3, atol=1e-4)
    _ = life.advance(Duration(0.1, SECOND))
    assert_true(life.mood == ANGER)
    _ = life.advance(Duration(0.2, SECOND))
    assert_almost_equal(life.strength, 0.5, atol=1e-4)
    # A weaker goal eases down to it; a held one eases back to rest.
    life.feel(ANGER, 0.2, 0.05)
    _ = life.advance(Duration(0.04, SECOND))
    assert_almost_equal(life.strength, 0.3, atol=1e-4)
    _ = life.advance(Duration(0.5, SECOND))
    assert_equal(life.strength, 0)
    with assert_raises(contains="named expression"):
        life.feel(FacialExpression(99), 0.5)
    with assert_raises(contains="from zero to one"):
        life.feel(SMILE, 1.5)
    with assert_raises(contains="from zero to one"):
        life.feel(SMILE, -0.5)


def test_a_fighter_out_of_breath_pants() raises:
    var life = FaceLife(1)
    life.pant(4)
    assert_equal(life.breath, 1)
    life.pant(-1)
    assert_equal(life.breath, 0)
    life.pant(1)
    var opened = Float32(0)
    for _ in range(10):
        var face = life.advance(Duration(0.07, SECOND))
        for w in face.weights:
            opened = max(opened, w)
    assert_true(opened > 0.05)
    # Words take the mouth from the breath.
    life.say("Hm")
    assert_true(life.speaking())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
