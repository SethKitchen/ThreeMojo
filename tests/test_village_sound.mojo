# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's sound: its kinds, its mix, the air, and a WAV file."""

from extensions.village.sound import (
    BIRD,
    COIN,
    HIT,
    SAMPLE_RATE,
    SPLASH,
    STEP,
    SWING,
    SoundKind,
    Sounds,
    VOICES,
    Voice,
    sound_length,
    voice_sample,
    wav_bytes,
    write_wav,
)
from std.os import getenv
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_each_sound_is_a_kind_and_has_its_length() raises:
    for kind in [STEP, SPLASH, SWING, HIT, COIN, BIRD]:
        assert_true(kind.is_valid())
        assert_true(sound_length(kind) > 0)
        # Each kind makes a sound, and none after it ends or before it
        # starts.
        var voice = Voice(kind, 0, 1, 0, 3)
        var loud = Float32(0)
        for k in range(200):
            var s = voice_sample(voice, Float32(k) / Float32(SAMPLE_RATE), k)
            loud = max(loud, abs(s))
        assert_true(loud > 0)
        assert_equal(voice_sample(voice, sound_length(kind), 0), 0)
        assert_equal(voice_sample(voice, -0.1, 0), 0)
    assert_false(SoundKind(6).is_valid())
    assert_equal(sound_length(SoundKind(9)), 0)


def test_a_sound_plays_and_ends() raises:
    var sounds = Sounds()
    sounds.set_air(0, 0, 0.2)
    var quiet = sounds.mix(100)
    assert_equal(len(quiet), 200)
    sounds.play(HIT, 1, -1)
    assert_equal(len(sounds.voices), 1)
    var heard = sounds.mix(2000)
    var left = Float32(0)
    var right = Float32(0)
    for k in range(2000):
        left = max(left, abs(heard[2 * k]))
        right = max(right, abs(heard[2 * k + 1]))
    # Panned to the left, it is louder there.
    assert_true(left > 0.1 and left > right)
    for s in heard:
        assert_true(s >= -1 and s <= 1)
    # It ends, and is let go.
    _ = sounds.mix(SAMPLE_RATE // 2)
    assert_equal(len(sounds.voices), 0)
    # At most `VOICES` play at once.
    for _ in range(VOICES + 5):
        sounds.play(STEP, 0.5, 0)
    assert_equal(len(sounds.voices), VOICES)
    with assert_raises(contains="six"):
        sounds.play(SoundKind(8), 0.5, 0)
    with assert_raises(contains="gain"):
        sounds.play(STEP, 2, 0)
    with assert_raises(contains="gain"):
        sounds.play(STEP, -1, 0)
    with assert_raises(contains="pan"):
        sounds.play(STEP, 0.5, 3)
    with assert_raises(contains="pan"):
        sounds.play(STEP, 0.5, -3)
    with assert_raises(contains="44,100"):
        _ = sounds.mix(-1)
    with assert_raises(contains="44,100"):
        _ = sounds.mix(SAMPLE_RATE + 1)
    assert_equal(len(sounds.mix(0)), 0)
    with assert_raises(contains="from 0 to 1"):
        sounds.set_air(2, 0, 0)
    with assert_raises(contains="from 0 to 1"):
        sounds.set_air(0, -1, 0)


def test_the_air_holds_wind_rain_birds_and_crickets() raises:
    var day = Sounds()
    day.set_air(0.8, 1, 1)
    # By day, a bird chirps within a few seconds.
    for _ in range(10):
        _ = day.mix(SAMPLE_RATE)
    assert_true(day.started > 0)
    # At night, crickets trill, and the birds wait for the day.
    var night = Sounds()
    night.set_air(0, 0, 0)
    night.next_bird = -5
    var trill = night.mix(SAMPLE_RATE)
    var loud = Float32(0)
    for s in trill:
        loud = max(loud, abs(s))
    assert_true(loud > 0)
    assert_true(night.next_bird > night.clock)


def test_the_sound_is_kept_as_a_wav_file() raises:
    assert_equal(len(wav_bytes(List[Float32]())), 44)
    var samples: List[Float32] = [0, 1, -1, 2]
    var bytes = wav_bytes(samples)
    assert_equal(len(bytes), 44 + 8)
    assert_equal(Int(bytes[0]), 82)
    assert_equal(Int(bytes[8]), 87)
    # Full scale, and clamped past it.
    assert_equal(Int(bytes[46]), 0xFF)
    assert_equal(Int(bytes[47]), 0x7F)
    assert_equal(Int(bytes[50]), 0xFF)
    var path = String(getenv("TMPDIR", "/tmp"), "/village_sound.wav")
    write_wav(path, samples)
    assert_true(Path(path).exists())
    assert_equal(len(Path(path).read_bytes()), 52)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
