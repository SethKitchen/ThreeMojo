# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the mouth moving with words."""

from extensions.humanoid.skeleton.head.expression import (
    AA,
    CH,
    DD,
    E,
    FF,
    IH,
    KK,
    NN,
    OH,
    OU,
    PP,
    RR,
    SILENT,
    SS,
    TH,
    FaceWeights,
    Viseme,
)
from extensions.humanoid.skeleton.head.speech import (
    BLEND_TIME,
    CONSONANT_TIME,
    PAUSE_TIME,
    VOWEL_TIME,
    Speech,
    visemes_of,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _shapes(text: String) -> List[Viseme]:
    """Return the visemes of `text`, pauses among them."""
    var out = List[Viseme]()
    for item in visemes_of(text):  # pragma: no branch
        out.append(item.viseme)
    return out^


def _same(a: List[Viseme], b: List[Viseme]) -> Bool:
    """Return True if two runs of visemes are the same."""
    if len(a) != len(b):
        return False
    for k in range(len(a)):  # pragma: no branch
        if a[k] != b[k]:
            return False
    return True


def test_words_are_read_by_their_spelling() raises:
    # Pairs of letters, a silent final e, and an h on its own.
    assert_true(_same(_shapes("the"), [TH, E]))
    assert_true(_same(_shapes("make"), [PP, AA, KK]))
    # A short word after a boundary keeps its final e.
    assert_true(_same(_shapes("  be"), [SILENT, PP, E]))
    assert_true(_same(_shapes("chop"), [CH, OH, PP]))
    assert_true(_same(_shapes("shoe"), [CH, OH, E]))
    assert_true(_same(_shapes("phone"), [FF, OH, NN]))
    assert_true(_same(_shapes("sing"), [SS, IH, NN]))
    assert_true(_same(_shapes("back"), [PP, AA, KK]))
    assert_true(_same(_shapes("food"), [FF, OU, DD]))
    assert_true(_same(_shapes("seen"), [SS, IH, NN]))
    assert_true(_same(_shapes("when"), [OU, E, NN]))
    assert_true(_same(_shapes("hi"), [IH]))
    assert_true(_same(_shapes("queen"), [KK, OU, IH, NN]))
    assert_true(_same(_shapes("box"), [PP, OH, KK, SS]))
    assert_true(_same(_shapes("jar"), [CH, AA, RR]))
    assert_true(_same(_shapes("you"), [IH, OU]))
    # A letter repeated is one shape; case does not matter.
    assert_true(_same(_shapes("BELL"), [PP, E, NN]))
    # Words part with a short pause, phrases with a long one, and other
    # signs are left out.
    var said = visemes_of("go, now 2 go")
    assert_equal(said[2].kind, 3)
    assert_equal(said[2].viseme, SILENT)
    assert_true(
        _same(
            _shapes("go, now 2 go"),
            [KK, OH, SILENT, NN, OH, OU, SILENT, KK, OH],
        )
    )
    assert_equal(len(visemes_of("")), 0)
    # Every single letter and pair.
    assert_true(
        _same(
            _shapes("up wax van zoo new sea pie qat"),
            [
                OU,
                PP,
                SILENT,
                OU,
                AA,
                KK,
                SS,
                SILENT,
                FF,
                AA,
                NN,
                SILENT,
                SS,
                OU,
                SILENT,
                NN,
                OU,
                SILENT,
                SS,
                IH,
                SILENT,
                PP,
                IH,
                SILENT,
                KK,
                AA,
                DD,
            ],
        )
    )
    # Every mark that ends a phrase, and every sign that parts words.
    var marked = visemes_of(" a! b? c; d: e\nf\tg-h")
    assert_equal(marked[0].viseme, SILENT)
    var pauses = 0
    for item in marked:  # pragma: no branch
        if item.kind == 3:
            pauses += 1
    assert_equal(pauses, 4)
    # The hyphen parts "g" from an "h" on its own, which makes no shape.
    assert_equal(marked[len(marked) - 1].kind, 2)
    assert_equal(marked[len(marked) - 2].viseme, KK)


def test_speech_is_timed_and_blended() raises:
    var speech = Speech("pa")
    assert_true(abs(speech.duration() - (CONSONANT_TIME + VOWEL_TIME)) < 1e-6)
    var fast = Speech("pa.", 2)
    assert_true(
        abs(fast.duration() - (CONSONANT_TIME + VOWEL_TIME + PAUSE_TIME) / 2)
        < 1e-6
    )
    assert_equal(Speech("").duration(), 0)
    with assert_raises(contains="rate"):
        _ = Speech("pa", 0)
    # In the middle of each sound its shape is whole; between them the
    # mouth passes through both.
    assert_equal(speech.weight(0, CONSONANT_TIME / 2), 1)
    var between = speech.weight(0, CONSONANT_TIME)
    assert_true(between > 0 and between < 1)
    assert_equal(speech.weight(1, -1), 0)
    var face = FaceWeights()
    speech.speak(face, CONSONANT_TIME + VOWEL_TIME / 2)
    assert_true(face.get("jawOpen") > 0.5)
    assert_equal(face.get("mouthPress_L"), 0)
    var still = FaceWeights()
    speech.speak(still, -1)
    speech.speak(still, 10)
    assert_equal(still.get("jawOpen"), 0)
    # A pause leaves the mouth at rest.
    var paused = Speech("a. a")
    var rest = FaceWeights()
    paused.speak(rest, VOWEL_TIME + PAUSE_TIME / 2)
    assert_true(rest.get("jawOpen") < 1e-6)
    _ = BLEND_TIME


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
