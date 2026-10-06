# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Caller-aligned visual speech sampled from an authoritative audio clock.

No audio decoder, forced aligner, pronunciation model or neural asset is
included. The caller supplies alignment and the media player's position.
Intervals are half-open and held exactly. Gaps and explicit SIL are silent.
The spelling-only `Speech` API is unchanged.
"""

from core.user_data import UserData
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
from loaders.json import ARRAY, parse_json
from std.math import isfinite
from units.si import Duration

comptime SPEECH_MAPPING = "threemojo-arpabet-viseme-v1"
comptime SPEECH_TIMING = "audio-clock-half-open-held-v1"


@fieldwise_init
struct Phoneme(Copyable, Movable):
    """An uppercase, unstressed ARPABET symbol, or SIL.

    Args:
        symbol: A label in `phoneme_viseme`'s documented inventory.

    Returns:
        A typed label; conversion checks its validity.

    Raises:
        None: Unknown labels are refused at consumption boundaries.
    """

    var symbol: String

    def is_valid(self) -> Bool:
        """Return whether the label belongs to this mapping.

        Returns:
            True for the 39 ARPABET phonemes and SIL.
        """
        return self.symbol in _phonemes()


def _phonemes() -> List[String]:
    """Return the fixed, unstressed ARPABET inventory and explicit silence."""
    return [
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
    ]


def phoneme_viseme(phoneme: Phoneme) raises -> Viseme:
    """Map one caller-supplied phoneme to a visual recipe.

    Diphthongs map to one held shape. Supply timed visemes to split them.
    HH uses an open vowel shape; it is not an implicit pause.

    Args:
        phoneme: Uppercase ARPABET without stress digits, or SIL.

    Returns:
        A named visual viseme.

    Raises:
        Error: If the label is unknown. No spelling inference is used.
    """
    var names = _phonemes()
    var values: List[Viseme] = [
        SILENT,
        AA,
        AA,
        AA,
        OH,
        AA,
        AA,
        PP,
        CH,
        DD,
        TH,
        E,
        RR,
        E,
        FF,
        KK,
        AA,
        IH,
        IH,
        CH,
        KK,
        NN,
        PP,
        NN,
        NN,
        OH,
        OH,
        PP,
        RR,
        SS,
        CH,
        DD,
        TH,
        OU,
        OU,
        FF,
        OU,
        IH,
        SS,
        CH,
    ]
    # The phoneme mapping is a fixed nonempty table.
    for i in range(len(names)):  # pragma: no branch
        if phoneme.symbol == names[i]:
            return values[i]
    raise Error("Unknown aligned phoneme: " + phoneme.symbol)


@fieldwise_init
struct TimedViseme(ImplicitlyCopyable):
    """One utterance-relative interval in seconds.

    Args:
        viseme: A named visual shape, including SILENT.
        start: Inclusive start, relative to the utterance's audio origin.
        end: Exclusive end, strictly after start.

    Returns:
        A value record, validated when a track consumes it.

    Raises:
        None: `AlignedSpeech` validates all records together.
    """

    var viseme: Viseme
    var start: Duration
    var end: Duration


@fieldwise_init
struct TimedPhoneme(Copyable, Movable):
    """One caller-aligned phoneme interval.

    Args:
        phoneme: Uppercase unstressed ARPABET, or SIL.
        start: Inclusive utterance-relative time.
        end: Exclusive utterance-relative time.

    Returns:
        A value record for `aligned_phonemes`.

    Raises:
        None: The conversion boundary validates it.
    """

    var phoneme: Phoneme
    var start: Duration
    var end: Duration


def _time(time: Duration) raises:
    """Require a finite, nonnegative number of seconds."""
    if not isfinite(time.value) or time.value < 0:
        raise Error("Audio time must be finite and nonnegative")


struct AlignedSpeech(Copyable, Movable):
    """An immutable-by-interface visual utterance with caller-owned timing.

    The caller owns audio playback. Samples have no accumulated frame delta.
    Timestamps must already be sorted; overlap is refused, never blended.
    """

    var _utterance: String
    var _origin: Duration
    var _duration: Duration
    var _intervals: List[TimedViseme]

    def __init__(
        out self,
        utterance: String,
        duration: Duration,
        intervals: List[TimedViseme],
        origin: Duration = Duration(0),
    ) raises:
        """Copy and validate an alignment before it can be sampled.

        Args:
            utterance: Nonempty caller label identifying the audio asset.
            duration: Utterance duration, including leading or trailing silence.
            intervals: Ordered, nonoverlapping intervals within duration.
            origin: Position of utterance time zero on the audio media clock.

        Returns:
            A track that owns its alignment copy.

        Raises:
            Error: If times, labels, shapes, order or interval bounds are invalid.
        """
        _time(duration)
        _time(origin)
        if not isfinite(origin.value + duration.value):
            raise Error("Audio origin plus duration must be finite")
        if utterance.byte_length() == 0:
            raise Error("An aligned utterance needs an audio label")
        var previous = Float32(0)
        for item in intervals:
            _time(item.start)
            _time(item.end)
            if not item.viseme.is_valid():
                raise Error("Aligned speech requires a named viseme")
            if (
                item.start.value < previous
                or item.end.value <= item.start.value
            ):
                raise Error(
                    "Aligned intervals must be ordered and nonoverlapping"
                )
            if item.end.value > duration.value:
                raise Error("Aligned interval exceeds utterance duration")
            if origin.value + item.end.value <= origin.value + item.start.value:
                raise Error(
                    "Aligned interval is below the audio clock resolution"
                )
            previous = item.end.value
        self._utterance = utterance
        self._duration = duration
        self._origin = origin
        self._intervals = intervals.copy()

    def origin(self) -> Duration:
        """Return the audio media position of utterance time zero.

        Returns:
            A time in seconds.
        """
        return self._origin

    def sample(self, audio_position: Duration) raises -> FaceWeights:
        """Return fresh weights at the audio player's current position.

        Args:
            audio_position: Authoritative media position, not wall or frame time.

        Returns:
            The held interval shape, or rest before, after and in silence.
            Repeated samples and backward seeks return the same weights.

        Raises:
            Error: If the media position is negative or nonfinite.
        """
        _time(audio_position)
        var face = FaceWeights()
        var clock = audio_position.value
        if (
            clock < self._origin.value
            or clock >= self._origin.value + self._duration.value
        ):
            return face^
        for item in self._intervals:
            if clock < self._origin.value + item.start.value:
                break
            if clock < self._origin.value + item.end.value:
                face.add_viseme(item.viseme)
                break
        return face^

    def metadata(self) raises -> UserData:
        """Serialize the exact timing and visual mapping contract for a bake.

        Returns:
            JSON-compatible metadata; it includes no audio bytes or model.

        Raises:
            Error: If a stored value is not valid JSON.
        """
        var data = UserData()
        data.set_string("mapping", String(SPEECH_MAPPING))
        data.set_string("timing", String(SPEECH_TIMING))
        data.set_string("utterance", self._utterance)
        data.set_number("origin_seconds", Float64(self._origin.value))
        data.set_number("duration_seconds", Float64(self._duration.value))
        var items = String("[")
        for i in range(len(self._intervals)):
            if i > 0:
                items += ","
            var item = self._intervals[i]
            var entry = UserData()
            entry.set_number("viseme", Float64(item.viseme.value))
            entry.set_number("start_seconds", Float64(item.start.value))
            entry.set_number("end_seconds", Float64(item.end.value))
            items += entry.to_json()
        data.set_json("intervals", items + "]")
        return data^


def aligned_phonemes(
    utterance: String,
    duration: Duration,
    phonemes: List[TimedPhoneme],
    origin: Duration = Duration(0),
) raises -> AlignedSpeech:
    """Convert caller-provided phonemes without deriving timing from text.

    Args:
        utterance: Caller label for the audio asset.
        duration: Duration including silence.
        phonemes: Ordered, nonoverlapping, caller-aligned phonemes.
        origin: Media clock position of utterance time zero.

    Returns:
        A track that uses the pinned phoneme-to-viseme mapping.

    Raises:
        Error: If labels or intervals are invalid.
    """
    var items = List[TimedViseme]()
    for item in phonemes:
        items.append(
            TimedViseme(phoneme_viseme(item.phoneme), item.start, item.end)
        )
    return AlignedSpeech(utterance, duration, items, origin)


def _json_time(seconds: Float64) raises -> Duration:
    """Validate JSON precision before reducing to the media clock's precision.
    """
    if not isfinite(seconds) or seconds < 0:
        raise Error("JSON audio time must be finite and nonnegative")
    var clock = Float32(seconds)
    if not isfinite(clock) or (seconds > 0 and clock == 0):
        raise Error("JSON audio time exceeds the audio clock resolution")
    return Duration(clock)


def read_aligned_speech(data: UserData) raises -> AlignedSpeech:
    """Validate a baked timing record and reconstruct its track.

    Args:
        data: The record from `AlignedSpeech.metadata`.

    Returns:
        A validated alignment with the same audio origin and intervals.

    Raises:
        Error: If a revision, JSON field, viseme or timing value is invalid.
    """
    if (
        data.string("mapping") != SPEECH_MAPPING
        or data.string("timing") != SPEECH_TIMING
    ):
        raise Error("Unsupported aligned speech mapping or timing revision")
    var duration = data.number("duration_seconds")
    var origin = data.number("origin_seconds")
    var checked_duration = _json_time(duration)
    var checked_origin = _json_time(origin)
    var previous = Float64(0)
    var doc = parse_json(data.json("intervals"))
    if doc.kind(0) != ARRAY:
        raise Error("Aligned intervals must be a JSON array")
    var items = List[TimedViseme]()
    for i in range(doc.length(0)):
        var entry = doc.at(0, i)
        var shape = doc.number(doc.get(entry, "viseme"))
        if shape < 0 or shape > 14 or shape != Float64(Int(shape)):
            raise Error("Aligned speech requires an integer named viseme")
        var start = doc.number(doc.get(entry, "start_seconds"))
        var end = doc.number(doc.get(entry, "end_seconds"))
        var checked_start = _json_time(start)
        var checked_end = _json_time(end)
        if start < previous or end <= start or end > duration:
            raise Error(
                "JSON aligned intervals must be ordered and within duration"
            )
        previous = end
        items.append(
            TimedViseme(Viseme(Int(shape)), checked_start, checked_end)
        )
    return AlignedSpeech(
        data.string("utterance"),
        checked_duration,
        items,
        checked_origin,
    )


struct AudioSpeechPlayback(Copyable, Movable):
    """Transport state driven only by supplied media-clock observations."""

    var _speech: AlignedSpeech
    var _position: Duration
    var _paused: Bool

    def __init__(out self, speech: AlignedSpeech):
        """Start paused at utterance time zero.

        Args:
            speech: The validated track, copied for this player.
        """
        self._speech = speech.copy()
        self._position = speech.origin()
        self._paused = True

    def sample(mut self, audio_position: Duration) raises -> FaceWeights:
        """Read the media clock while playing, or retain the paused position.

        Args:
            audio_position: A finite, nonnegative media-clock observation.

        Returns:
            Fresh weights without accumulating any previous expression.

        Raises:
            Error: If the observation is invalid, even while paused.
        """
        _time(audio_position)
        if not self._paused:
            self._position = audio_position
        return self._speech.sample(self._position)

    def pause(mut self, audio_position: Duration) raises:
        """Freeze exactly where the audio player reports its pause.

        Args:
            audio_position: The authoritative paused position.

        Raises:
            Error: If the position is invalid; state stays unchanged.
        """
        _time(audio_position)
        self._position = audio_position
        self._paused = True

    def resume(mut self, audio_position: Duration) raises:
        """Resume from the audio player's actual position.

        Args:
            audio_position: The current media position, including seeks.

        Raises:
            Error: If the position is invalid; state stays unchanged.
        """
        _time(audio_position)
        self._position = audio_position
        self._paused = False

    def seek(mut self, audio_position: Duration) raises -> FaceWeights:
        """Sample a seek immediately without changing paused/playing state.

        Args:
            audio_position: The player's acknowledged seek destination.

        Returns:
            Fresh weights for that exact destination, also on backward seeks.

        Raises:
            Error: If the destination is invalid; state stays unchanged.
        """
        _time(audio_position)
        self._position = audio_position
        return self._speech.sample(self._position)

    def reset(mut self) raises -> FaceWeights:
        """Pause and sample at utterance time zero.

        Returns:
            The origin's weights, identical to a repeated paused sample.

        Raises:
            Error: Never for the built-in face recipes.
        """
        self._position = self._speech.origin()
        self._paused = True
        return self._speech.sample(self._position)
