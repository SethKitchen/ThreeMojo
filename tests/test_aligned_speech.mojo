# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Audio alignment, transport, mapping and metadata regression tests."""

from extensions.humanoid.skeleton.head.aligned_speech import (
    AlignedSpeech,
    AudioSpeechPlayback,
    Phoneme,
    TimedPhoneme,
    TimedViseme,
    aligned_phonemes,
    phoneme_viseme,
    read_aligned_speech,
)
from extensions.humanoid.skeleton.head.expression import (
    AA,
    OH,
    PP,
    SILENT,
    FF,
    OU,
    Viseme,
)
from extensions.humanoid.skeleton.head.speech import Speech
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_true, assert_raises
from units.si import Duration, MILLISECOND


def _track() raises -> AlignedSpeech:
    """Synthetic timing for 'pah ... of', not a pronunciation inference."""
    return AlignedSpeech(
        "synthetic-pah-of-v1",
        Duration(2),
        [
            TimedViseme(PP, Duration(0), Duration(0.125)),
            TimedViseme(AA, Duration(0.125), Duration(1)),
            TimedViseme(SILENT, Duration(1), Duration(1.25)),
            TimedViseme(OH, Duration(1.5), Duration(1.75)),
            TimedViseme(FF, Duration(1.75), Duration(1.875)),
        ],
        Duration(10),
    )


def test_exact_intervals_and_fresh_samples() raises:
    var speech = _track()
    assert_equal(speech.sample(Duration(9)).get("jawOpen"), 0)
    assert_equal(speech.sample(Duration(10)).get("mouthPress_L"), Float32(0.7))
    assert_equal(speech.sample(Duration(10.0625)).get("jawOpen"), 0)
    assert_true(speech.sample(Duration(10.125)).get("jawOpen") > 0.5)
    assert_equal(speech.sample(Duration(10.125)).get("mouthPress_L"), 0)
    assert_true(speech.sample(Duration(10.999)).get("jawOpen") > 0.5)
    for at in [Float32(11), 11.125, 11.25, 11.4, 11.875, 12, 20]:
        var face = speech.sample(Duration(at))
        for w in face.weights:
            assert_equal(w, 0)
    assert_true(speech.sample(Duration(11.5)).get("mouthFunnel") > 0)
    assert_equal(
        speech.sample(Duration(10.5)).get("jawOpen"),
        speech.sample(Duration(10.5)).get("jawOpen"),
    )
    # The track owns its input intervals.
    var items: List[TimedViseme] = [TimedViseme(AA, Duration(0), Duration(1))]
    var owned = AlignedSpeech("owned", Duration(1), items)
    items[0].viseme = SILENT
    assert_true(owned.sample(Duration(0.5)).get("jawOpen") > 0)
    assert_equal(
        AlignedSpeech("empty", Duration(0), [])
        .sample(Duration(0))
        .get("jawOpen"),
        0,
    )
    # Compare in the authoritative Float32 media-clock domain, so 10 + 0.1
    # enters the second interval despite subtraction cancellation.
    var origin = Duration(10)
    var boundary = Duration(0.1)
    var shifted = AlignedSpeech(
        "nonbinary-origin",
        Duration(1),
        [
            TimedViseme(PP, Duration(0), boundary),
            TimedViseme(AA, boundary, Duration(1)),
        ],
        origin,
    )
    assert_true(
        shifted.sample(Duration(origin.value + boundary.value)).get("jawOpen")
        > 0.5
    )
    with assert_raises(contains="clock resolution"):
        _ = AlignedSpeech(
            "too-small",
            Duration(1),
            [
                TimedViseme(PP, Duration(0), Duration(0.01)),
            ],
            Duration(1e8),
        )


def test_transport_is_driven_by_audio_not_frame_delta() raises:
    var speech = _track()
    for rate in [24, 30, 60, 144]:
        var player = AudioSpeechPlayback(speech)
        player.resume(Duration(10))
        for frame in range(rate * 2 + 1):
            var at = Duration(10 + Float32(frame) / Float32(rate))
            var expected = speech.sample(at)
            var got = player.sample(at)
            for k in range(len(expected.weights)):
                assert_equal(got.weights[k], expected.weights[k])
        player.pause(Duration(10.5))
        assert_true(player.sample(Duration(19)).get("jawOpen") > 0.5)
        assert_equal(player.seek(Duration(10.0625)).get("jawOpen"), 0)
        assert_equal(
            player.sample(Duration(19)).get("mouthPress_L"), Float32(0.7)
        )
        player.resume(Duration(11.4))
        assert_equal(player.sample(Duration(11.4)).get("mouthPress_L"), 0)
        # Backward audio-clock discontinuity requires no accumulated-state reset.
        assert_equal(
            player.sample(Duration(10.0625)).get("mouthPress_L"), Float32(0.7)
        )
        assert_equal(player.reset().get("mouthPress_L"), Float32(0.7))
        assert_equal(
            player.sample(Duration(20)).get("mouthPress_L"), Float32(0.7)
        )
        with assert_raises(contains="finite"):
            player.pause(Duration(-1))
        with assert_raises(contains="finite"):
            player.resume(Duration(inf[DType.float32]()))
        with assert_raises(contains="finite"):
            _ = player.seek(Duration(nan[DType.float32]()))
        with assert_raises(contains="finite"):
            _ = player.sample(Duration(-1))
        assert_equal(
            player.sample(Duration(20)).get("mouthPress_L"), Float32(0.7)
        )


def test_phonemes_handle_irregular_spelling_without_a_backend() raises:
    # 'of' is AH V, not spelling O F; 'queue' can be K Y UW.
    var track = aligned_phonemes(
        "of-queue-caller-aligned",
        Duration(2),
        [
            TimedPhoneme(Phoneme("AH"), Duration(0), Duration(0.2)),
            TimedPhoneme(Phoneme("V"), Duration(0.2), Duration(0.375)),
            TimedPhoneme(Phoneme("SIL"), Duration(0.375), Duration(0.75)),
            TimedPhoneme(Phoneme("K"), Duration(0.75), Duration(0.8)),
            TimedPhoneme(Phoneme("Y"), Duration(0.8), Duration(0.9)),
            TimedPhoneme(Phoneme("UW"), Duration(0.9), Duration(1.8)),
        ],
    )
    assert_equal(phoneme_viseme(Phoneme("V")), FF)
    assert_equal(phoneme_viseme(Phoneme("UW")), OU)
    assert_equal(track.sample(Duration(0.1)).get("mouthFunnel"), 0)
    assert_true(track.sample(Duration(1.4)).get("mouthPucker") > 0.7)
    assert_equal(track.sample(Duration(0.5)).get("jawOpen"), 0)
    var old = Speech("of queue")
    assert_true(old.duration() > 0)
    for symbol in [
        "SIL",
        "AA",
        "AE",
        "AH",
        "AO",
        "AW",
        "AY",
        "B",
        "CH",
        "D",
        "DH",
        "EH",
        "ER",
        "EY",
        "F",
        "G",
        "HH",
        "IH",
        "IY",
        "JH",
        "K",
        "L",
        "M",
        "N",
        "NG",
        "OW",
        "OY",
        "P",
        "R",
        "S",
        "SH",
        "T",
        "TH",
        "UH",
        "UW",
        "V",
        "W",
        "Y",
        "Z",
        "ZH",
    ]:
        assert_true(Phoneme(symbol).is_valid())
        assert_true(phoneme_viseme(Phoneme(symbol)).is_valid())
    for symbol in ["", "aa", "AH0", "UNKNOWN"]:
        assert_true(not Phoneme(symbol).is_valid())
        with assert_raises(contains="Unknown aligned phoneme"):
            _ = phoneme_viseme(Phoneme(symbol))


def test_alignment_rejects_bad_boundaries() raises:
    for value in [Float32(-1), inf[DType.float32](), nan[DType.float32]()]:
        with assert_raises(contains="finite"):
            _ = AlignedSpeech("bad", Duration(value), [])
        with assert_raises(contains="finite"):
            _ = AlignedSpeech("bad", Duration(1), [], Duration(value))
        with assert_raises(contains="finite"):
            _ = AlignedSpeech(
                "bad",
                Duration(1),
                [TimedViseme(AA, Duration(value), Duration(1))],
            )
        with assert_raises(contains="finite"):
            _ = AlignedSpeech(
                "bad",
                Duration(1),
                [TimedViseme(AA, Duration(0), Duration(value))],
            )
        with assert_raises(contains="finite"):
            _ = _track().sample(Duration(value))
    with assert_raises(contains="label"):
        _ = AlignedSpeech("", Duration(1), [])
    with assert_raises(contains="origin plus"):
        _ = AlignedSpeech("overflow", Duration(3e38), [], Duration(3e38))
    with assert_raises(contains="named viseme"):
        _ = AlignedSpeech(
            "bad",
            Duration(1),
            [TimedViseme(Viseme(88), Duration(0), Duration(1))],
        )
    for start in [Float32(1), 2]:
        with assert_raises(contains="ordered"):
            _ = AlignedSpeech(
                "bad",
                Duration(3),
                [TimedViseme(AA, Duration(start), Duration(1))],
            )
    with assert_raises(contains="exceeds"):
        _ = AlignedSpeech(
            "bad", Duration(1), [TimedViseme(AA, Duration(0), Duration(2))]
        )
    for start in [Float32(0), 0.5]:
        with assert_raises(contains="ordered"):
            _ = AlignedSpeech(
                "bad",
                Duration(2),
                [
                    TimedViseme(AA, Duration(0), Duration(1)),
                    TimedViseme(PP, Duration(start), Duration(1.5)),
                ],
            )
    # Unit conversions are used, not mistaken for raw seconds.
    var ms = AlignedSpeech(
        "milliseconds",
        Duration(1000, MILLISECOND),
        [TimedViseme(AA, Duration(0), Duration(1000, MILLISECOND))],
    )
    assert_true(ms.sample(Duration(500, MILLISECOND)).get("jawOpen") > 0)


def test_metadata_roundtrip_validates_revisions_and_input() raises:
    var original = _track()
    var restored = read_aligned_speech(original.metadata())
    assert_equal(restored.metadata().to_json(), original.metadata().to_json())
    assert_equal(
        restored.sample(Duration(10.5)).get("jawOpen"),
        original.sample(Duration(10.5)).get("jawOpen"),
    )
    for key in ["mapping", "timing"]:
        var data = original.metadata()
        data.set_string(key, "future-unsupported")
        with assert_raises(contains="revision"):
            _ = read_aligned_speech(data)
    var data = original.metadata()
    data.set_json("intervals", "{}")
    with assert_raises(contains="array"):
        _ = read_aligned_speech(data)
    for value in ["-1", "15", "0.5"]:
        data.set_json(
            "intervals",
            '[{"viseme":' + value + ',"start_seconds":0,"end_seconds":1}]',
        )
        with assert_raises(contains="integer named viseme"):
            _ = read_aligned_speech(data)
    for key in ["origin_seconds", "duration_seconds"]:
        var changed = original.metadata()
        changed.set_json(key, "-1e-100")
        with assert_raises(contains="finite and nonnegative"):
            _ = read_aligned_speech(changed)
    data = original.metadata()
    data.set_json(
        "intervals", '[{"viseme":1,"start_seconds":-1e-100,"end_seconds":1}]'
    )
    with assert_raises(contains="finite and nonnegative"):
        _ = read_aligned_speech(data)
    data.set_json(
        "intervals", '[{"viseme":1,"start_seconds":0,"end_seconds":1e-100}]'
    )
    with assert_raises(contains="clock resolution"):
        _ = read_aligned_speech(data)
    data.set_json(
        "intervals", '[{"viseme":1,"start_seconds":1,"end_seconds":0.5}]'
    )
    with assert_raises(contains="ordered"):
        _ = read_aligned_speech(data)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
