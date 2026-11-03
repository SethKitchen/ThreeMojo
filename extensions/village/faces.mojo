# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The faces of the village's people: they blink, they move their mouths
with the words they say, and they show what they feel.

A person who speaks keeps the preserved face of
`extensions.humanoid.rig.game_face`, with its teeth and its tongue, and a
still face of `FACE_TRIANGLES` for a distance. The still face is what the
budget counts, so a crowd costs as much as before. `face_reach` says how
near the camera must be for a face to show `FACE_PIXELS` or more. Nearer,
the preserved face shows and moves; further, the still face shows.

`FaceLife` keeps one face moving:

1. The eyes blink every 2 to 5.5 seconds, for `BLINK_SECONDS`. Each face
   blinks at its own times, by its seed.
2. `FaceLife.say` starts words. The mouth makes the shape of each sound
   of `extensions.humanoid.skeleton.head.speech` in its time.
3. `FaceLife.feel` sets an expression and how strong it is. The face
   eases to it at `MOOD_EASE` a second. A new expression comes in after
   the last one goes out, so the face does not show both at once.
4. `FaceLife.pant` opens the mouth a little, for a fighter out of breath.

This is not a three.js port. See Extensions.

    var life = FaceLife(7)
    life.say("Good day!")
    life.feel(SMILE, 0.4)
    var weights = life.advance(delta)
    person.face.value().animate(scene, weights)
"""

from extensions.humanoid.skeleton.head.expression import (
    AA,
    NEUTRAL,
    FaceWeights,
    FacialExpression,
)
from extensions.humanoid.skeleton.head.speech import Speech
from extensions.vegetation.noise import hash01
from std.math import sin, tan
from units.si import RADIAN, SECOND, Angle, Duration

comptime FACE_TRIANGLES = 900
"""The triangles of a speaking person's still face, for a distance."""
comptime FACE_PIXELS = Float32(16)
"""A face drawn this many pixels tall or more shows its preserved mesh."""
comptime HEAD_HEIGHT = Float32(0.24)
"""How tall a head is, chin to crown, in meters."""
comptime BLINK_SECONDS = Float32(0.16)
"""How long a blink takes, shut and open again."""
comptime MOOD_EASE = Float32(5)
"""How fast an expression comes in or goes out: its whole strength in
`1 / MOOD_EASE` seconds."""
comptime PANT_OPEN = Float32(0.35)
"""How far a panting mouth opens, at its widest, as a share of `AA`."""
comptime PANT_RATE = Float32(7)
"""How fast a panting mouth opens and closes, in radians a second."""


def face_reach(height: Int, field_of_view: Angle) raises -> Float32:
    """Return how near a camera must be to a face to draw it `FACE_PIXELS`
    tall.

    Args:
        height: The frame's height, in pixels.
        field_of_view: The camera's vertical field of view.

    Returns:
        The distance, in meters.

    Raises:
        Error: If the height is not positive, or the field of view is not
            between 0 and 180 degrees.
    """
    if height <= 0:
        raise Error("A frame's height must be positive")
    var half = field_of_view.to(RADIAN) / 2
    if not (half > 0 and half < 1.5707963):
        raise Error("A field of view must be between 0 and 180 degrees")
    return HEAD_HEIGHT * Float32(height) / (2 * tan(half) * FACE_PIXELS)


struct FaceLife(Copyable, Movable):
    """One face's blinks, words and expression, over time."""

    var seed: Int
    # Seconds since the face began, and when it next blinks, and how many
    # times it has blinked.
    var clock: Float32
    var next_blink: Float32
    var blinks: Int
    # The words, and how long ago they began, in seconds.
    var speech: Speech
    var spoken: Float32
    # The expression the face eases to, and how strong; the one it shows,
    # and how strong it shows now.
    var goal: FacialExpression
    var goal_strength: Float32
    # How long the expression is held yet, in seconds, or below zero to
    # hold it until another is set.
    var holding: Float32
    var mood: FacialExpression
    var strength: Float32
    # How out of breath the face is, from zero to one.
    var breath: Float32

    def __init__(out self, seed: Int) raises:
        """Start a face at rest, silent, with no expression.

        Args:
            seed: Which times the face blinks at.

        Raises:
            Error: Never: empty words are timed.
        """
        self.seed = seed
        self.clock = 0
        self.blinks = 0
        self.next_blink = 0
        self.speech = Speech("")
        self.spoken = 0
        self.goal = NEUTRAL
        self.goal_strength = 0
        self.holding = -1
        self.mood = NEUTRAL
        self.strength = 0
        self.breath = 0
        self.next_blink = self._wait()

    def _wait(self) -> Float32:
        """Return when the next blink is due, in the face's seconds."""
        return self.clock + 2 + 3.5 * hash01(self.blinks, 0, self.seed)

    def say(mut self, text: String) raises:
        """Start saying words, from their first sound.

        Args:
            text: English words.

        Raises:
            Error: Never: the rate is one.
        """
        self.speech = Speech(text)
        self.spoken = 0

    def speaking(self) -> Bool:
        """Return whether the mouth is still saying its words.

        Returns:
            True until the last sound of the words.
        """
        return self.spoken < self.speech.duration()

    def feel(
        mut self,
        expression: FacialExpression,
        strength: Float32,
        seconds: Float32 = -1,
    ) raises:
        """Set the expression the face eases to.

        Args:
            expression: A named expression.
            strength: How strong, from zero to one.
            seconds: How long the face holds it before it eases back to
                rest, or below zero to hold it until another is set.

        Raises:
            Error: If the expression is not named, or the strength is not
                from zero to one.
        """
        if not expression.is_valid():
            raise Error("A face must feel a named expression")
        if not (strength >= 0 and strength <= 1):
            raise Error("An expression's strength must be from zero to one")
        self.goal = expression
        self.goal_strength = strength
        self.holding = seconds

    def pant(mut self, breath: Float32):
        """Set how out of breath the face is.

        Args:
            breath: From zero, at rest, to one, out of breath. A value
                past either end is held to it.
        """
        self.breath = min(Float32(1), max(Float32(0), breath))

    def advance(mut self, delta: Duration) raises -> FaceWeights:
        """Move the face on by a frame, and return its weights.

        Args:
            delta: The frame's time.

        Returns:
            Fresh weights: the blink, the words' sound, the breath and the
            expression.

        Raises:
            Error: If the time is negative.
        """
        var seconds = delta.to(SECOND)
        if not (seconds >= 0):
            raise Error("A frame's time must not be negative")
        self.clock += seconds
        self.spoken += seconds
        if self.holding >= 0:
            self.holding -= seconds
            if self.holding < 0:
                self.goal_strength = 0
        # The expression goes out before another comes in.
        var step = MOOD_EASE * seconds
        if self.goal != self.mood:
            self.strength = max(Float32(0), self.strength - step)
            if self.strength == 0:
                self.mood = self.goal
        elif self.strength < self.goal_strength:
            self.strength = min(self.goal_strength, self.strength + step)
        else:
            self.strength = max(self.goal_strength, self.strength - step)
        var face = FaceWeights()
        if self.strength > 0:
            face.add_expression(self.mood, self.strength)
        # A blink shuts the eyes and opens them again.
        if self.clock >= self.next_blink + BLINK_SECONDS:
            self.blinks += 1
            self.next_blink = self._wait()
        # A blink past its end is moved on above, so it is under way here
        # from its start.
        var into = (self.clock - self.next_blink) / BLINK_SECONDS
        if into >= 0:
            face.blink(1 - abs(2 * into - 1))
        if self.speaking():
            self.speech.speak(face, self.spoken)
        elif self.breath > 0:
            var swing = 0.5 + 0.5 * sin(self.clock * PANT_RATE)
            face.add_viseme(AA, self.breath * PANT_OPEN * swing)
        return face^
