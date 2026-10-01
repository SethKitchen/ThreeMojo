# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The mouth moving with words: text to visemes, over time.

`visemes_of` reads English text by its spelling. Letters that make one
sound together come first, as "th", "ch", "sh", "ph", "ng", "oo" and
"ee". A silent final "e" and an "h" on its own make no shape.
Each other letter is one viseme. Spaces are a short pause, and the
marks that end a phrase a long one.

`Speech` gives each viseme its time: a vowel is held longer than a
consonant. At any moment each viseme's weight rises over a short ramp
before it starts and falls over one after it ends, so a mouth moving
from one shape to the next passes through both, as a speaker's does.

Spelling is not sound in English. The shapes still follow the words
well, since a viseme stands for a whole group of sounds that look
alike, but a word spelled far from how it sounds moves the mouth as it
is spelled.

This is not a three.js port. See Extensions.

    var speech = Speech("Hello there")
    var face = FaceWeights()
    speech.speak(face, 0.4)
    face.apply(scene.meshes[skin])
"""

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
from extensions.humanoid.skeleton.morph import smoothstep

# How long each kind of sound is held, at a rate of one, in seconds.
comptime VOWEL_TIME = Float32(0.13)
comptime CONSONANT_TIME = Float32(0.075)
comptime SPACE_TIME = Float32(0.06)
comptime PAUSE_TIME = Float32(0.32)
# How long a viseme takes to come in and to go, either side of its time,
# in seconds.
comptime BLEND_TIME = Float32(0.035)


@fieldwise_init
struct Spoken(Copyable, Movable):
    """One viseme of a text, and whether it is a vowel or a pause."""

    var viseme: Viseme
    # 0 a consonant, 1 a vowel, 2 a space, 3 a pause.
    var kind: Int


def _is_vowel(c: String) -> Bool:
    """Return True for a vowel letter, y among them."""
    return (
        c == "a" or c == "e" or c == "i" or c == "o" or c == "u" or (c == "y")
    )


def _letter(c: String) -> Bool:
    """Return True for a letter a to z."""
    return c.byte_length() == 1 and ord(c) >= ord("a") and ord(c) <= ord("z")


def _single(c: String) -> Viseme:
    """Return the viseme of one letter."""
    if c == "a":
        return AA
    if c == "e":
        return E
    if c == "i" or c == "y":
        return IH
    if c == "o":
        return OH
    if c == "u" or c == "w":
        return OU
    if c == "b" or c == "m" or c == "p":
        return PP
    if c == "f" or c == "v":
        return FF
    if c == "t" or c == "d":
        return DD
    if c == "j":
        return CH
    if c == "s" or c == "z":
        return SS
    if c == "n" or c == "l":
        return NN
    if c == "r":
        return RR
    # c, g, k, q and x.
    return KK


def _pair(a: String, b: String) -> Viseme:
    """Return the viseme two letters make together, or `SILENT` if they
    make none."""
    var two = a + b
    if two == "th":
        return TH
    if two == "ch" or two == "sh":
        return CH
    if two == "ph":
        return FF
    if two == "ng":
        return NN
    if two == "ck":
        return KK
    if two == "oo" or two == "ou" or two == "ew":
        return OU
    if two == "ee" or two == "ea" or two == "ie":
        return IH
    if two == "wh":
        return OU
    return SILENT


def visemes_of(text: String) -> List[Spoken]:
    """Return the visemes of English text, read by its spelling.

    Args:
        text: Any text. Letters are read in either case; digits and other
            signs are left out.

    Returns:
        One entry per sound, spaces and pauses among them. Runs of spaces
        and pauses are one entry, and a viseme repeated is one.
    """
    var letters = List[String]()
    for c in text.lower().codepoint_slices():  # pragma: no branch
        letters.append(String(c))
    var out = List[Spoken]()
    var k = 0
    var n = len(letters)
    while k < n:  # pragma: no branch
        var c = letters[k]
        if not _letter(c):
            var kind = 2
            if (
                c == "."
                or c == ","
                or c == "!"
                or c == "?"
                or c == ";"
                or (c == ":")
            ):
                kind = 3
            elif c != " " and c != "\n" and c != "\t" and c != "-":
                k += 1
                continue
            if len(out) > 0 and out[len(out) - 1].kind >= 2:
                out[len(out) - 1].kind = max(out[len(out) - 1].kind, kind)
            else:
                out.append(Spoken(SILENT, kind))
            k += 1
            continue
        var next = letters[k + 1] if k + 1 < n else String(" ")
        # A silent final e: after a consonant, at the end of a word of
        # four letters or more, as in "make" but not "the".
        if c == "e" and not _letter(next) and k >= 3:
            if (
                _letter(letters[k - 3])
                and _letter(letters[k - 2])
                and not _is_vowel(letters[k - 1])
            ):
                k += 1
                continue
        # An h on its own only breathes; "th", "ch", "sh", "ph" and
        # "wh" are read as pairs before it.
        if c == "h":
            k += 1
            continue
        var both = _pair(c, next)
        var viseme = _single(c)
        var vowel = _is_vowel(c)
        var step = 1
        if both != SILENT:
            viseme = both
            vowel = _is_vowel(c) and _is_vowel(next)
            step = 2
        elif c == "q" and next == "u":
            out.append(Spoken(KK, 0))
            viseme = OU
            vowel = False
            step = 2
        elif c == "x":
            out.append(Spoken(KK, 0))
            viseme = SS
        var kind = 1 if vowel else 0
        if len(out) == 0 or out[len(out) - 1].viseme != viseme:
            out.append(Spoken(viseme, kind))
        k += step
    return out^


struct Speech(Copyable, Movable):
    """A text's visemes, each with its time."""

    var spoken: List[Spoken]
    var starts: List[Float32]
    var ends: List[Float32]

    def __init__(out self, text: String, rate: Float32 = 1) raises:
        """Time the visemes of `text`.

        Args:
            text: English text.
            rate: How fast it is spoken: one for an ordinary pace, two
                twice as fast.

        Raises:
            Error: If `rate` is not above zero.
        """
        if not (rate > 0):
            raise Error("A speech's rate must be above zero")
        self.spoken = visemes_of(text)
        self.starts = List[Float32]()
        self.ends = List[Float32]()
        var times: List[Float32] = [
            CONSONANT_TIME,
            VOWEL_TIME,
            SPACE_TIME,
            PAUSE_TIME,
        ]
        var at = Float32(0)
        for item in self.spoken:  # pragma: no branch
            self.starts.append(at)
            at += times[item.kind] / rate
            self.ends.append(at)

    def duration(self) -> Float32:
        """Return how long the text takes to say, in seconds."""
        if len(self.ends) == 0:
            return 0
        return self.ends[len(self.ends) - 1]

    def weight(self, index: Int, time: Float32) -> Float32:
        """Return how much of one viseme the mouth shows at `time`.

        Args:
            index: Which of the speech's visemes.
            time: Seconds from the start.

        Returns:
            Zero through one: up over a ramp into its time and down over
            one out of it.
        """
        var rise = smoothstep(
            self.starts[index] - BLEND_TIME,
            self.starts[index] + BLEND_TIME,
            time,
        )
        var fall = smoothstep(
            self.ends[index] - BLEND_TIME, self.ends[index] + BLEND_TIME, time
        )
        return rise * (1 - fall)

    def speak(self, mut face: FaceWeights, time: Float32) raises:
        """Add the mouth's shape at `time` to a face.

        Args:
            face: The face, which may already wear an expression.
            time: Seconds from the start. Before it and after the end,
                the mouth is at rest.

        Raises:
            Error: Never, for the named visemes.
        """
        for k in range(len(self.spoken)):  # pragma: no branch
            if self.spoken[k].viseme == SILENT:
                continue
            if time < self.starts[k] - BLEND_TIME:
                break
            var w = self.weight(k, time)
            if w > 0:
                face.add_viseme(self.spoken[k].viseme, w)
