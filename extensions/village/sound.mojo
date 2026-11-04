# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's sound: footsteps, splashes, blows, coins, and the air.

Every sound is made from noise and sine waves, so the village needs no
recording. `Sounds` holds the sounds that play now. `play` starts one, and
`mix` makes the next samples of all of them, with the air under them:

| Kind | What it is | How long |
|---|---|---|
| `STEP` | A footfall on grass: a soft thud of low noise | 0.12 seconds |
| `SPLASH` | A foot or a drop in water: bright noise that falls away | 0.4 seconds |
| `SWING` | A blade through the air: noise that rises and falls | 0.25 seconds |
| `HIT` | A blow that lands: a low knock with a crack on it | 0.18 seconds |
| `COIN` | Coins into the satchel: two bright, ringing notes | 0.5 seconds |
| `BIRD` | A bird's chirp: a quick rising whistle | 0.15 seconds |

The air is the wind, as soft noise that swells and fades, and the rain, as
loud hiss in a downpour. By day, birds chirp now and then. At night,
crickets trill. `set_air` sets how much of each there is.

The samples are stereo, the left first, from -1 to 1. A host plays them,
or `write_wav` keeps them in a file.

This is not a three.js port: three.js plays sound through the browser's
Web Audio. See Extensions.
"""

from core.ordinal import ordinal_valid
from extensions.vegetation.noise import hash01
from std.math import exp, pi, sin
from std.pathlib import Path

comptime SAMPLE_RATE = 44100
"""The samples a second of the village's sound, on each side."""
comptime VOICES = 32
"""The most sounds that play at once. A new sound past them is let go."""
comptime TWO_PI = Float32(2 * pi)


@fieldwise_init
struct SoundKind(Equatable, ImplicitlyCopyable, Writable):
    """What a sound is, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the six kinds there are.

        Returns:
            Whether the value names a kind.
        """
        return ordinal_valid(self.value, 5)


comptime STEP = SoundKind(0)
comptime SPLASH = SoundKind(1)
comptime SWING = SoundKind(2)
comptime HIT = SoundKind(3)
comptime COIN = SoundKind(4)
comptime BIRD = SoundKind(5)


def sound_length(kind: SoundKind) -> Float32:
    """Return how long a kind of sound lasts, in seconds.

    Args:
        kind: The kind.

    Returns:
        The length from the module's table, or zero for a kind that is not
        one.
    """
    if kind == STEP:
        return 0.12
    if kind == SPLASH:
        return 0.4
    if kind == SWING:
        return 0.25
    if kind == HIT:
        return 0.18
    if kind == COIN:
        return 0.5
    if kind == BIRD:
        return 0.15
    return 0


@fieldwise_init
struct Voice(Copyable, ImplicitlyCopyable):
    """One sound that plays."""

    var kind: SoundKind
    """What it is."""
    var age: Float32
    """How long it has played, in seconds."""
    var gain: Float32
    """How loud it is, from 0 to 1."""
    var pan: Float32
    """Where it is, from -1, the left, to 1, the right."""
    var seed: Int
    """Which noise it is made of."""


def _noise(index: Int, seed: Int) -> Float32:
    """Return white noise from -1 to 1."""
    return hash01(index, seed, 911) * 2 - 1


def voice_sample(voice: Voice, t: Float32, index: Int) -> Float32:
    """Return one sample of a sound.

    Args:
        voice: The sound.
        t: How long it has played, in seconds.
        index: The sample's place in the sound, for its noise.

    Returns:
        The sample, from -1 to 1, before its gain.
    """
    var kind = voice.kind
    var length = sound_length(kind)
    if t < 0 or t >= length:
        return 0
    var left = 1 - t / length
    var n = _noise(index, voice.seed)
    if kind == STEP:
        # A thud: noise, smoothed by its own last samples, that dies fast.
        var thud = (n + _noise(index - 1, voice.seed)) * 0.5
        return thud * left * left * left
    if kind == SPLASH:
        return n * exp(-t * 9) * (0.6 + 0.4 * sin(TWO_PI * 900 * t))
    if kind == SWING:
        var swell = sin(Float32(pi) * t / length)
        return n * swell * swell * 0.8
    if kind == HIT:
        var knock = sin(TWO_PI * 110 * t) * exp(-t * 25)
        return knock + n * exp(-t * 60) * 0.6
    if kind == COIN:
        var high = sin(TWO_PI * 1568 * t) + 0.5 * sin(TWO_PI * 2093 * t)
        return high * exp(-t * 8) * 0.5
    # A bird's chirp rises in pitch.
    var pitch = 2600 + 9000 * t
    return sin(TWO_PI * pitch * t) * sin(Float32(pi) * t / length) * 0.5


struct Sounds(Movable):
    """The village's sounds that play now, and the air under them."""

    var voices: List[Voice]
    """The sounds that play."""
    var clock: Float32
    """How long the sound has played, in seconds."""
    var made: Int
    """How many samples have been made, on each side."""
    var wind: Float32
    """How loud the wind is, from 0 to 1."""
    var rain: Float32
    """How loud the rain is, from 0 to 1."""
    var day: Float32
    """The share of the day's light, from 0 to 1: birds by day, crickets by
    night."""
    var volume: Float32
    """How loud all of it is, from 0 to 1."""
    var started: Int
    """How many sounds have been started."""
    var next_bird: Float32
    """When the next bird chirps, on `clock`."""

    def __init__(out self):
        """Make the sound of a calm, quiet day."""
        self.voices = List[Voice]()
        self.clock = 0
        self.made = 0
        self.wind = 0.2
        self.rain = 0
        self.day = 1
        self.volume = 0.8
        self.started = 0
        self.next_bird = 2

    def play(mut self, kind: SoundKind, gain: Float32, pan: Float32) raises:
        """Start a sound now.

        Args:
            kind: What it is.
            gain: How loud, from 0 to 1.
            pan: Where, from -1, the left, to 1, the right.

        Raises:
            Error: If the kind is not one, or the gain or the pan is out of
                range.
        """
        if not kind.is_valid():
            raise Error("A sound must be one of the six")
        if not (gain >= 0 and gain <= 1):
            raise Error("A sound's gain must be from 0 to 1")
        if not (pan >= -1 and pan <= 1):
            raise Error("A sound's pan must be from -1 to 1")
        if len(self.voices) >= VOICES:
            return
        self.started += 1
        self.voices.append(Voice(kind, 0, gain, pan, self.started))

    def set_air(mut self, wind: Float32, rain: Float32, day: Float32) raises:
        """Set how much wind and rain there is, and how much of the day.

        Args:
            wind: How loud the wind is, from 0 to 1.
            rain: How loud the rain is, from 0 to 1.
            day: The share of the day's light, from 0 to 1.

        Raises:
            Error: If a value is not from 0 to 1.
        """
        for value in [wind, rain, day]:
            if not (value >= 0 and value <= 1):
                raise Error("The air's sound must be from 0 to 1")
        self.wind = wind
        self.rain = rain
        self.day = day

    def mix(mut self, frames: Int) raises -> List[Float32]:
        """Make the next samples of every sound and of the air.

        A sound that has ended is let go. Birds chirp now and then by day.

        Args:
            frames: How many samples to make on each side, from 0 to
                `SAMPLE_RATE`.

        Returns:
            `2 * frames` samples, the left and then the right of each,
            from -1 to 1.

        Raises:
            Error: If `frames` is out of range.
        """
        if frames < 0 or frames > SAMPLE_RATE:
            raise Error("A mix must be from 0 to 44,100 samples long")
        var samples = List[Float32](length=2 * frames, fill=0)
        var step = 1 / Float32(SAMPLE_RATE)
        # By day a bird chirps every few seconds, somewhere.
        var span = Float32(frames) * step
        while self.day > 0.5 and self.next_bird < self.clock + span:
            self.started += 1
            var pan = hash01(self.started, 1, 913) * 2 - 1
            var wait = self.next_bird - self.clock
            self.voices.append(Voice(BIRD, -wait, 0.25, pan, self.started))
            self.next_bird += 2 + 5 * hash01(self.started, 2, 913)
        if self.day <= 0.5 and self.next_bird < self.clock:
            self.next_bird = self.clock + 2
        for k in range(frames):
            var t = self.clock + Float32(k) * step
            var index = self.made + k
            var l = Float32(0)
            var r = Float32(0)
            # The wind swells and fades; the rain hisses.
            var gust = 0.6 + 0.4 * sin(t * 0.7) * sin(t * 0.23 + 1)
            var hiss = _noise(index, 7) * 0.5 + _noise(index - 1, 7) * 0.5
            var air = hiss * (self.wind * 0.08 * gust)
            var drops = _noise(index, 8) * self.rain * 0.18
            l += air + drops
            r += air * 0.9 + _noise(index, 9) * self.rain * 0.18
            # Crickets trill at night.
            var night = 1 - self.day
            if night > 0.5:
                var trill = sin(TWO_PI * 4200 * t) * (
                    0.5 + 0.5 * sin(TWO_PI * 30 * t)
                )
                var chirping = Float32(0)
                if sin(TWO_PI * 0.8 * t) > 0.3:
                    chirping = 1
                l += trill * 0.025 * chirping * night
                r += trill * 0.02 * chirping * night
            for ref voice in self.voices:
                var s = (
                    voice_sample(voice, voice.age + Float32(k) * step, index)
                    * voice.gain
                )
                l += s * (1 - max(Float32(0), voice.pan))
                r += s * (1 + min(Float32(0), voice.pan))
            samples[2 * k] = max(Float32(-1), min(Float32(1), l * self.volume))
            samples[2 * k + 1] = max(
                Float32(-1), min(Float32(1), r * self.volume)
            )
        self.clock += span
        self.made += frames
        var kept = List[Voice]()
        for voice in self.voices:
            var aged = voice
            aged.age += span
            if aged.age < sound_length(aged.kind):
                kept.append(aged)
        self.voices = kept^
        return samples^


def _word(mut bytes: List[UInt8], value: Int, count: Int):
    """Append a number's `count` lowest bytes, the lowest first."""
    for k in range(count):
        bytes.append(UInt8((value >> (8 * k)) & 0xFF))


def _text(mut bytes: List[UInt8], text: String):
    """Append the bytes of a text."""
    for c in text.as_bytes():
        bytes.append(c)


def wav_bytes(samples: List[Float32]) -> List[UInt8]:
    """Return stereo samples as the bytes of a WAV file: 16 bits a sample,
    at `SAMPLE_RATE`.

    Args:
        samples: The samples, the left and then the right of each, from -1
            to 1.

    Returns:
        The file's bytes: a RIFF header, then the samples.
    """
    var bytes = List[UInt8]()
    var data = len(samples) * 2
    _text(bytes, "RIFF")
    _word(bytes, 36 + data, 4)
    _text(bytes, "WAVEfmt ")
    _word(bytes, 16, 4)
    _word(bytes, 1, 2)
    _word(bytes, 2, 2)
    _word(bytes, SAMPLE_RATE, 4)
    _word(bytes, SAMPLE_RATE * 4, 4)
    _word(bytes, 4, 2)
    _word(bytes, 16, 2)
    _text(bytes, "data")
    _word(bytes, data, 4)
    for s in samples:
        var v = Int(max(Float32(-1), min(Float32(1), s)) * 32767)
        _word(bytes, v & 0xFFFF, 2)
    return bytes^


def write_wav(path: String, samples: List[Float32]) raises:
    """Keep stereo samples in a WAV file.

    Args:
        path: The file.
        samples: The samples, the left and then the right of each.

    Raises:
        Error: If the file cannot be written.
    """
    Path(path).write_bytes(wav_bytes(samples))
