# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One property of one node, given a value at a list of times, from three.js
`src/animation/KeyframeTrack.js` and the tracks beside it.

A track is two lists of the same length: when, and what. Between two
entries the value is worked out from the two around it, and outside the
ends it is the nearest end. That is all three.js's `KeyframeTrack` is, and
`VectorKeyframeTrack` and `QuaternionKeyframeTrack` differ only in how
many numbers a value has and how two of them are mixed.

So here there is one struct and a kind, for the reason `Curve` is one
struct and a kind: a clip has to hold a list of one type.

    POSITION    three numbers, where the node is
    SCALE       three numbers, how big it is
    QUATERNION  four numbers, which way it is turned

three.js names its target with a string, `.position` or `.quaternion`, and
finds the object by its name at run time. Here a track names a `NodeId`
and a kind, both of which the compiler checks. A string that does not
match anything is three.js's most common animation bug, and it is not
expressible here.

## How two keys are mixed

`LINEAR` mixes two positions or two scales one number at a time, and two
rotations by `slerp`, which turns at an even rate along the shortest arc.
three.js does the same, in `LinearInterpolant` and
`QuaternionLinearInterpolant`: a rotation is not four numbers to average,
and averaging them makes a turn that speeds up in the middle and a
quaternion that is no longer a rotation.

`STEP` holds each value until the next key, three.js's
`InterpolateDiscrete`.

## What is not here

three.js has a third mode, `InterpolateSmooth`, which is its
`CubicInterpolant`. It is not a Catmull-Rom spline through the keys: it
takes the uneven spacing of the times into account, and reaching for the
spline in `math.curve` instead would be a different curve wearing the same
name. It is not ported.

## What is refused

A track with no keys, or with times that do not rise. A list of values
that does not divide into one value per key. A kind or an interpolation
that is none of the named ones. Each of those is a track that cannot be
read at any time at all, and three.js finds out at the first frame.
"""

from core.object3d import NodeId
from math.quaternion import Quaternion
from math.vector3 import Vector3
from units.si import Duration, SECOND

# How far a rotation key's length may sit from one. Wide enough for a
# quaternion written out to a few decimal places in an exported file, and
# far narrower than any mistake that matters.
comptime UNIT_SLACK = Float32(1e-3)


@fieldwise_init
struct TrackKind(Equatable, ImplicitlyCopyable, Writable):
    """Which property of a node a track drives, as a type rather than a
    bare int.

    The same argument as `materials.material.MaterialKind`: three small
    integers that mean three different things should not be
    interchangeable. The type stops a bare integer at compile time, and
    `KeyframeTrack.__init__` stops `TrackKind(9)` with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three kinds there are."""
        return self == POSITION or self == SCALE or self == QUATERNION

    def component_count(self) -> Int:
        """Return how many numbers one of this kind's values holds.

        Returns:
            Four for `QUATERNION` and three for the others. Zero for a kind
            that is not valid, which `KeyframeTrack.__init__` has already
            refused.
        """
        if self == QUATERNION:
            return 4
        if self == POSITION:
            return 3
        if self == SCALE:
            return 3
        return 0


# Where the node is, three.js's `.position` track.
comptime POSITION = TrackKind(0)
# How big the node is, three.js's `.scale` track.
comptime SCALE = TrackKind(1)
# Which way the node is turned, three.js's `.quaternion` track.
comptime QUATERNION = TrackKind(2)


@fieldwise_init
struct Interpolation(Equatable, ImplicitlyCopyable, Writable):
    """How the value between two keys is worked out, as a type rather than
    a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `STEP` or `LINEAR`."""
        return self == STEP or self == LINEAR


# Hold each key's value until the next key: three.js's
# `InterpolateDiscrete`.
comptime STEP = Interpolation(0)
# Run evenly from each key to the next: three.js's `InterpolateLinear`,
# which for a rotation means `slerp`.
comptime LINEAR = Interpolation(1)


struct KeyframeTrack(Copyable, Movable):
    """One node's one property, given a value at a list of times."""

    var node: NodeId
    var kind: TrackKind
    var interpolation: Interpolation
    # When each key is, in seconds from the start of the clip, rising.
    var times: List[Float32]
    # Every key's value end to end, `kind.component_count()` numbers each.
    var values: List[Float32]

    def __init__(
        out self,
        node: NodeId,
        kind: TrackKind,
        times: List[Duration],
        var values: List[Float32],
        interpolation: Interpolation = LINEAR,
    ) raises:
        """Create a track on one node's one property.

        Args:
            node: Which node the track drives.
            kind: Which of its properties.
            times: When each key is, from the start of the clip, rising and
                none of them negative. At least one.
            values: Every key's value end to end, three numbers each for
                `POSITION` and `SCALE` and four for `QUATERNION`.
            interpolation: `LINEAR`, the default and three.js's, or `STEP`.

        Raises:
            Error: If the kind or the interpolation is none of the named
                ones, if there are no keys, if a time is negative or does
                not rise above the one before it, or if the values do not
                divide into one value per key.
        """
        if not kind.is_valid():
            raise Error("A track needs a kind that exists")
        if not interpolation.is_valid():
            raise Error("A track's interpolation must be STEP or LINEAR")
        if len(times) == 0:
            raise Error("A track needs at least one key")
        if len(values) != len(times) * kind.component_count():
            raise Error("A track needs one value for every key")
        var seconds = List[Float32]()
        for index in range(len(times)):  # pragma: no branch
            var at = times[index].to(SECOND)
            if at < 0:
                raise Error("A track's times cannot be negative")
            if index > 0:
                if at <= seconds[index - 1]:
                    raise Error("A track's times must rise")
            seconds.append(at)
        if kind == QUATERNION:
            # A rotation of any other length is not a rotation, and `slerp`
            # cannot make one out of two of them. three.js leaves this to
            # whoever built the track, and a rig exported wrong shows as a
            # model that swells as it turns.
            for key in range(len(times)):  # pragma: no branch
                var turn = Quaternion(
                    values[key * 4],
                    values[key * 4 + 1],
                    values[key * 4 + 2],
                    values[key * 4 + 3],
                )
                if abs(turn.length() - 1) > UNIT_SLACK:
                    raise Error("A rotation key must be of unit length")
        self.node = node
        self.kind = kind
        self.interpolation = interpolation
        self.times = seconds^
        self.values = values^

    def __init__(out self, *, copy: Self):
        """Copy another track."""
        self.node = copy.node
        self.kind = copy.kind
        self.interpolation = copy.interpolation
        self.times = copy.times.copy()
        self.values = copy.values.copy()

    def key_count(self) -> Int:
        """Return how many keys the track holds."""
        return len(self.times)

    def duration(self) -> Duration:
        """Return when the last key is, which is how long the track runs."""
        return Duration(self.times[len(self.times) - 1], SECOND)

    def _value_at_key(self, key: Int) -> List[Float32]:
        """Return the value stored at one key, its own numbers alone."""
        var width = self.kind.component_count()
        var out = List[Float32]()
        for offset in range(width):  # pragma: no branch
            out.append(self.values[key * width + offset])
        return out^

    def _key_before(self, seconds: Float32) -> Int:
        """Return the last key at or before `seconds`. The caller has
        checked that the time falls inside the track."""
        var found = 0
        for key in range(1, len(self.times)):  # pragma: no branch
            if self.times[key] > seconds:
                break
            found = key
        return found

    def sample(self, at: Duration) -> List[Float32]:
        """Return the track's value at a time.

        Before the first key the value is the first key's, and after the
        last it is the last key's, which is what three.js's interpolants do
        at their ends.

        Args:
            at: When to read the track, from the start of the clip.

        Returns:
            `kind.component_count()` numbers. A `QUATERNION` track returns
            a rotation of unit length.
        """
        var seconds = at.to(SECOND)
        var last = len(self.times) - 1
        if seconds <= self.times[0]:
            return self._value_at_key(0)
        if seconds >= self.times[last]:
            return self._value_at_key(last)
        var key = self._key_before(seconds)
        if self.interpolation == STEP:
            return self._value_at_key(key)
        var span = self.times[key + 1] - self.times[key]
        var part = (seconds - self.times[key]) / span
        var near = self._value_at_key(key)
        var far = self._value_at_key(key + 1)
        if self.kind == QUATERNION:
            var mixed = Quaternion(near[0], near[1], near[2], near[3]).slerp(
                Quaternion(far[0], far[1], far[2], far[3]), part
            )
            return [mixed.x, mixed.y, mixed.z, mixed.w]
        var out = List[Float32]()
        for offset in range(len(near)):  # pragma: no branch
            out.append(near[offset] + (far[offset] - near[offset]) * part)
        return out^

    def sample_vector3(self, at: Duration) raises -> Vector3:
        """Return a `POSITION` or `SCALE` track's value at a time.

        Args:
            at: When to read the track.

        Returns:
            The value as a vector.

        Raises:
            Error: If this is a `QUATERNION` track, whose value is not a
                vector.
        """
        if self.kind == QUATERNION:
            raise Error("A rotation track's value is not a vector")
        var numbers = self.sample(at)
        return Vector3(numbers[0], numbers[1], numbers[2])

    def sample_quaternion(self, at: Duration) raises -> Quaternion:
        """Return a `QUATERNION` track's value at a time.

        Args:
            at: When to read the track.

        Returns:
            The value as a rotation.

        Raises:
            Error: If this is not a `QUATERNION` track.
        """
        if self.kind != QUATERNION:
            raise Error("Only a rotation track's value is a rotation")
        var numbers = self.sample(at)
        return Quaternion(numbers[0], numbers[1], numbers[2], numbers[3])
