# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One property of one node, mesh, material or light, given a value at a
list of times, from three.js `src/animation/KeyframeTrack.js`, the tracks
beside it, and `PropertyBinding.js`.

A track is two lists of the same length: when, and what. Between two
entries the value is worked out from the two around it, and outside the
ends it is the nearest end. That is all three.js's `KeyframeTrack` is, and
`VectorKeyframeTrack`, `QuaternionKeyframeTrack`, `NumberKeyframeTrack`,
`ColorKeyframeTrack` and `BooleanKeyframeTrack` differ only in how many
numbers a value has and how two of them are mixed.

So here there is one struct and a kind, for the reason `Curve` is one
struct and a kind: a clip has to hold a list of one type.

    POSITION           three numbers, where the node is
    SCALE              three numbers, how big it is
    QUATERNION         four numbers, which way it is turned
    VISIBLE            one number, zero or one, whether it is drawn
    MORPH_INFLUENCE    one number, how much of a morph target a mesh wears
    MATERIAL_COLOR     three linear channels, and the emissive and
                       specular colors beside it
    MATERIAL_OPACITY   one number, and the other number fields beside it
    LIGHT_COLOR        three linear channels
    LIGHT_INTENSITY    one number

three.js's `StringKeyframeTrack` is not ported: nothing in this port has a
string property for it to drive.

## A target, not a path

three.js names its target with a string, `.position` or
`.material.opacity` or `.morphTargetInfluences[2]`, and `PropertyBinding`
parses it and finds the object by its name at run time. Here a track holds
a `TrackTarget`: the kind, and the index of the node, mesh, material or
light. `node_target`, `morph_target`, `material_target` and `light_target`
each take the id type their kind needs, a `NodeId`, a `MeshIndex`, a
`MaterialId` or a `LightIndex`, so a track cannot ask for a property that
does not exist and cannot be handed a material id where a node was meant.

What that does *not* prove is that the thing is there. An id is an index,
any integer makes one, and the scene and the assets it indexes are not
chosen until `AnimationMixer.update` is called. So the mixer checks, and
raises on a track that names something they do not have. The type stops
the confusion; it does not stop the index.

A color is three linear channels, as three.js's `Color` holds it. A
material or a light stores its color as sRGB bytes, and the mixer decodes
and encodes at the edge; see `animation.animation_mixer`.

## How two keys are mixed

`LINEAR` mixes two positions or two scales one number at a time, and two
rotations by `slerp`, which turns at an even rate along the shortest arc.
three.js does the same, in `LinearInterpolant` and
`QuaternionLinearInterpolant`: a rotation is not four numbers to average,
and averaging them makes a turn that speeds up in the middle and a
quaternion that is no longer a rotation.

`STEP` holds each value until the next key, three.js's
`InterpolateDiscrete`. It is the only mode a `VISIBLE` track has, as it is
the only mode of three.js's `BooleanKeyframeTrack`: a flag half way
between shown and hidden is neither.

## What is not here

three.js has a third mode, `InterpolateSmooth`, which is its
`CubicInterpolant`. It is not a Catmull-Rom spline through the keys: it
takes the uneven spacing of the times into account, and reaching for the
spline in `math.curve` instead would be a different curve wearing the same
name. It is not ported.

## What is refused

A track with no keys, or with times that do not rise. A list of values
that does not divide into one value per key. A kind or an interpolation
that is none of the named ones, or a morph target past the eighth. A
`VISIBLE` track that is not `STEP`, or a key of one that is neither zero
nor one. Each of those is a track that cannot be
read at any time at all, and three.js finds out at the first frame.

A time or a value that is not a number is refused too, and so is a time
asked for that is not a number. That last one is not tidiness. The ends
are found by comparing the time against the first key and the last, and a
comparison against a value that is not a number is false both ways, so the
search walks past the last key and reads one off the end of the list. It
was an out-of-range abort, not an error, which is the worst way for a
scene to find out that a frame time went wrong.

A rotation key must be of unit length, to within `UNIT_SLACK`, and one
that is accepted is made exactly unit before it is stored. Otherwise a key
just inside the slack comes back out of `sample` unchanged, and a caller
told that rotations are of unit length would be told wrong.

The constructor is not the last chance to get any of this wrong. A track's
fields are open, as `Texture`'s are, so `sample` checks once more that the
two lists still agree before it reads them -- the same argument
`Texture.validate` makes, and the same reason: a value that was right when
it was built can be edited afterward.
"""

from core.buffer_geometry import MAX_MORPH_TARGETS
from core.object3d import NodeId
from materials.material import MaterialId
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import isfinite
from units.si import Duration, SECOND

# How far a rotation key's length may sit from one. Wide enough for a
# quaternion written out to a few decimal places in an exported file, and
# far narrower than any mistake that matters.
comptime UNIT_SLACK = Float32(1e-3)


@fieldwise_init
struct TrackKind(Equatable, ImplicitlyCopyable, Writable):
    """Which property a track drives, as a type rather than a bare int.

    The same argument as `materials.material.MaterialKind`: small integers
    that mean different things should not be interchangeable. The type
    stops a bare integer at compile time, and `KeyframeTrack.__init__`
    stops `TrackKind(9)` with `is_valid`.

    The first three drive a node's transform and keep the numbers they have
    always had. The kinds added after them start at ten, so no number in
    between is a kind.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the kinds there are."""
        return (
            self.value >= POSITION.value and self.value <= QUATERNION.value
        ) or (
            self.value >= VISIBLE.value and self.value <= LIGHT_INTENSITY.value
        )

    def is_node(self) -> Bool:
        """Return True if this kind drives a scene node: its position,
        scale, rotation or `visible` flag."""
        return (
            self == POSITION
            or self == SCALE
            or self == QUATERNION
            or self == VISIBLE
        )

    def is_morph(self) -> Bool:
        """Return True if this kind drives a mesh's morph target
        influence."""
        return self == MORPH_INFLUENCE

    def is_material(self) -> Bool:
        """Return True if this kind drives a field of a material."""
        return (
            self.value >= MATERIAL_COLOR.value
            and self.value <= MATERIAL_IOR.value
        )

    def is_light(self) -> Bool:
        """Return True if this kind drives a light's color or intensity."""
        return self == LIGHT_COLOR or self == LIGHT_INTENSITY

    def is_color(self) -> Bool:
        """Return True if this kind's value is a color: three linear
        channels, three.js's `ColorKeyframeTrack`."""
        return (
            self == MATERIAL_COLOR
            or self == MATERIAL_EMISSIVE
            or self == MATERIAL_SPECULAR
            or self == LIGHT_COLOR
        )

    def is_boolean(self) -> Bool:
        """Return True if this kind's value is a flag, three.js's
        `BooleanKeyframeTrack`."""
        return self == VISIBLE

    def component_count(self) -> Int:
        """Return how many numbers one of this kind's values holds.

        Returns:
            Four for `QUATERNION`, three for `POSITION`, `SCALE` and the
            colors, and one for every other kind. Zero for a kind that is
            not valid, which `KeyframeTrack.__init__` has already refused.
        """
        if self == QUATERNION:
            return 4
        if self == POSITION:
            return 3
        if self == SCALE:
            return 3
        if self.is_color():
            return 3
        if self.is_valid():
            return 1
        return 0


# Where the node is, three.js's `.position` track.
comptime POSITION = TrackKind(0)
# How big the node is, three.js's `.scale` track.
comptime SCALE = TrackKind(1)
# Which way the node is turned, three.js's `.quaternion` track.
comptime QUATERNION = TrackKind(2)
# Whether the node is drawn, three.js's `.visible` `BooleanKeyframeTrack`.
# One number a key, zero or one, and held until the next key.
comptime VISIBLE = TrackKind(10)
# How much of one morph target a mesh wears, three.js's
# `.morphTargetInfluences[i]` `NumberKeyframeTrack`.
comptime MORPH_INFLUENCE = TrackKind(11)
# A material's colors, three.js's `.material.color`, `.material.emissive`
# and `.material.specular` `ColorKeyframeTrack`s. Three linear channels a
# key, from zero to one.
comptime MATERIAL_COLOR = TrackKind(12)
comptime MATERIAL_EMISSIVE = TrackKind(13)
comptime MATERIAL_SPECULAR = TrackKind(14)
# A material's number fields, three.js's `.material.opacity` and the
# others, as `NumberKeyframeTrack`s. One number a key.
comptime MATERIAL_OPACITY = TrackKind(15)
comptime MATERIAL_EMISSIVE_INTENSITY = TrackKind(16)
comptime MATERIAL_ROUGHNESS = TrackKind(17)
comptime MATERIAL_METALNESS = TrackKind(18)
comptime MATERIAL_SHININESS = TrackKind(19)
comptime MATERIAL_ALPHA_TEST = TrackKind(20)
comptime MATERIAL_REFLECTIVITY = TrackKind(21)
comptime MATERIAL_ENV_MAP_INTENSITY = TrackKind(22)
comptime MATERIAL_CLEARCOAT = TrackKind(23)
comptime MATERIAL_CLEARCOAT_ROUGHNESS = TrackKind(24)
comptime MATERIAL_SPECULAR_INTENSITY = TrackKind(25)
comptime MATERIAL_IOR = TrackKind(26)
# A light's color, three linear channels, and its intensity.
comptime LIGHT_COLOR = TrackKind(27)
comptime LIGHT_INTENSITY = TrackKind(28)


@fieldwise_init
struct MeshIndex(Equatable, ImplicitlyCopyable, Writable):
    """Which of a scene's `meshes` a track drives, as a type rather than a
    bare int.

    An index into `Scene.meshes`. Any integer makes one, so the mixer
    checks it against the scene it is given.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative."""
        return self.value >= 0


@fieldwise_init
struct LightIndex(Equatable, ImplicitlyCopyable, Writable):
    """Which of a scene's `lights` a track drives, as a type rather than a
    bare int.

    An index into `Scene.lights`. Any integer makes one, so the mixer
    checks it against the scene it is given.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative."""
        return self.value >= 0


@fieldwise_init
struct TrackTarget(Equatable, ImplicitlyCopyable, Writable):
    """What one track drives: a kind, and which node, mesh, material or
    light it drives it on. This port's `PropertyBinding` path.

    three.js names the target with a string, `.material.opacity` or
    `.morphTargetInfluences[2]`, and parses it at run time. Here the kind
    is a type, and `node_target`, `morph_target`, `material_target` and
    `light_target` each take the id type their kind needs, so a material
    track cannot be handed a node by mistake.
    """

    var kind: TrackKind
    # The node, mesh, material or light, as its index. The kind says
    # which.
    var index: Int
    # Which morph target, for `MORPH_INFLUENCE`; zero for every other
    # kind.
    var slot: Int

    def is_valid(self) -> Bool:
        """Return True if the kind exists and the slot fits it.

        The index is not checked here. Whether it names something is a
        question for the scene and the assets, which the mixer is given at
        `update`.
        """
        if not self.kind.is_valid():
            return False
        if self.kind.is_morph():
            return self.slot >= 0 and self.slot < MAX_MORPH_TARGETS
        return self.slot == 0


def node_target(node: NodeId, kind: TrackKind) raises -> TrackTarget:
    """Return the target for one property of one node.

    Args:
        node: Which node.
        kind: `POSITION`, `SCALE`, `QUATERNION` or `VISIBLE`.

    Returns:
        The target.

    Raises:
        Error: If the kind does not drive a node.
    """
    if not kind.is_node():
        raise Error("A node target needs a kind that drives a node")
    return TrackTarget(kind, node.value, 0)


def morph_target(mesh: MeshIndex, target: Int) raises -> TrackTarget:
    """Return the target for one morph target influence of one mesh,
    three.js's `.morphTargetInfluences[target]`.

    Args:
        mesh: Which of the scene's meshes.
        target: Which morph target, from zero.

    Returns:
        The target.

    Raises:
        Error: If there is no such morph target: a mesh has
            `MAX_MORPH_TARGETS` influences.
    """
    if target < 0 or target >= MAX_MORPH_TARGETS:
        raise Error("A mesh has eight morph target influences")
    return TrackTarget(MORPH_INFLUENCE, mesh.value, target)


def material_target(
    material: MaterialId, kind: TrackKind
) raises -> TrackTarget:
    """Return the target for one field of one material.

    Args:
        material: Which material in the assets.
        kind: One of the `MATERIAL_` kinds.

    Returns:
        The target.

    Raises:
        Error: If the kind does not drive a material.
    """
    if not kind.is_material():
        raise Error("A material target needs a kind that drives a material")
    return TrackTarget(kind, material.value, 0)


def light_target(light: LightIndex, kind: TrackKind) raises -> TrackTarget:
    """Return the target for the color or the intensity of one light.

    Args:
        light: Which of the scene's lights.
        kind: `LIGHT_COLOR` or `LIGHT_INTENSITY`.

    Returns:
        The target.

    Raises:
        Error: If the kind does not drive a light.
    """
    if not kind.is_light():
        raise Error("A light target needs a kind that drives a light")
    return TrackTarget(kind, light.value, 0)


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
    """One property of one node, mesh, material or light, given a value at
    a list of times."""

    var target: TrackTarget
    var interpolation: Interpolation
    # When each key is, in seconds from the start of the clip, rising.
    var times: List[Float32]
    # Every key's value end to end, `target.kind.component_count()`
    # numbers each.
    var values: List[Float32]

    def __init__(
        out self,
        node: NodeId,
        kind: TrackKind,
        times: List[Duration],
        var values: List[Float32],
        interpolation: Optional[Interpolation] = None,
    ) raises:
        """Create a track on one node's one property.

        Args:
            node: Which node the track drives.
            kind: Which of its properties: `POSITION`, `SCALE`,
                `QUATERNION` or `VISIBLE`.
            times: When each key is, from the start of the clip, rising and
                none of them negative. At least one.
            values: Every key's value end to end, three numbers each for
                `POSITION` and `SCALE`, four for `QUATERNION` and one for
                `VISIBLE`.
            interpolation: `LINEAR` or `STEP`. None takes the kind's own:
                `STEP` for `VISIBLE` and `LINEAR` for the others, as in
                three.js.

        Raises:
            Error: As the constructor that takes a `TrackTarget` does, and
                if the kind does not drive a node.
        """
        self = Self(node_target(node, kind), times, values^, interpolation)

    def __init__(
        out self,
        target: TrackTarget,
        times: List[Duration],
        var values: List[Float32],
        interpolation: Optional[Interpolation] = None,
    ) raises:
        """Create a track on any property a track can drive.

        Args:
            target: What the track drives. Build it with `node_target`,
                `morph_target`, `material_target` or `light_target`.
            times: When each key is, from the start of the clip, rising and
                none of them negative. At least one.
            values: Every key's value end to end,
                `target.kind.component_count()` numbers each. A `VISIBLE`
                key is zero or one.
            interpolation: `LINEAR` or `STEP`. None takes the kind's own:
                `STEP` for `VISIBLE`, three.js's `BooleanKeyframeTrack`
                default, and `LINEAR` for the others.

        Raises:
            Error: If the target's kind is none of the named ones or its
                slot does not fit it, if the interpolation is none of the
                named ones, if a `VISIBLE` track is asked to be `LINEAR`,
                if there are no keys, if a time or a value is not a number,
                if a time is negative or does not rise above the one before
                it, if the values do not divide into one value per key, if
                a rotation key is not of unit length, or if a `VISIBLE` key
                is neither zero nor one.
        """
        if not target.is_valid():
            raise Error("A track needs a kind that exists and fits its slot")
        var kind = target.kind
        var how = STEP if kind.is_boolean() else LINEAR
        if Bool(interpolation):
            how = interpolation.value()
        if not how.is_valid():
            raise Error("A track's interpolation must be STEP or LINEAR")
        if kind.is_boolean() and how != STEP:
            # three.js's `BooleanKeyframeTrack` has no other mode: a flag
            # half way between shown and hidden is neither.
            raise Error("A flag track holds each key: it must be STEP")
        if len(times) == 0:
            raise Error("A track needs at least one key")
        if len(values) != len(times) * kind.component_count():
            raise Error("A track needs one value for every key")
        for index in range(len(values)):  # pragma: no branch
            if not isfinite(values[index]):
                raise Error("A track's values must be numbers")
            if not kind.is_boolean():
                continue
            if values[index] != 0 and values[index] != 1:
                raise Error("A flag track's keys must be zero or one")
        var seconds = List[Float32]()
        for index in range(len(times)):  # pragma: no branch
            var at = times[index].to(SECOND)
            if not isfinite(at):
                raise Error("A track's times must be numbers")
            if at < 0:
                raise Error("A track's times cannot be negative")
            if index > 0:
                if at <= seconds[index - 1]:
                    raise Error("A track's times must rise")
            seconds.append(at)
        var stored = values^
        if kind == QUATERNION:
            # A rotation of any other length is not a rotation, and `slerp`
            # cannot make one out of two of them. three.js leaves this to
            # whoever built the track, and a rig exported wrong shows as a
            # model that swells as it turns.
            for key in range(len(times)):  # pragma: no branch
                var turned = Quaternion(
                    stored[key * 4],
                    stored[key * 4 + 1],
                    stored[key * 4 + 2],
                    stored[key * 4 + 3],
                )
                if abs(turned.length() - 1) > UNIT_SLACK:
                    raise Error("A rotation key must be of unit length")
                # Inside the slack, and now exactly on it, so `sample`
                # hands back a rotation of unit length at a key as well as
                # between two of them.
                turned.normalize()
                stored[key * 4] = turned.x
                stored[key * 4 + 1] = turned.y
                stored[key * 4 + 2] = turned.z
                stored[key * 4 + 3] = turned.w
        self.target = target
        self.interpolation = how
        self.times = seconds^
        self.values = stored^

    def __init__(out self, *, copy: Self):
        """Copy another track."""
        self.target = copy.target
        self.interpolation = copy.interpolation
        self.times = copy.times.copy()
        self.values = copy.values.copy()

    def kind(self) -> TrackKind:
        """Return which property the track drives."""
        return self.target.kind

    def key_count(self) -> Int:
        """Return how many keys the track holds."""
        return len(self.times)

    def duration(self) -> Duration:
        """Return when the last key is, which is how long the track runs.

        No time at all for a track whose keys were removed after it was
        built: the fields are open, and reading the last of no keys was a
        crash rather than an answer.
        """
        if len(self.times) == 0:
            return Duration(0, SECOND)
        return Duration(self.times[len(self.times) - 1], SECOND)

    def _value_at_key(self, key: Int) -> List[Float32]:
        """Return the value stored at one key, its own numbers alone."""
        var width = self.target.kind.component_count()
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

    def sample(self, at: Duration) raises -> List[Float32]:
        """Return the track's value at a time.

        Before the first key the value is the first key's, and after the
        last it is the last key's, which is what three.js's interpolants do
        at their ends.

        Args:
            at: When to read the track, from the start of the clip.

        Returns:
            `kind.component_count()` numbers. A `QUATERNION` track returns
            a rotation of unit length.

        Raises:
            Error: If `at` is not a number, if the track has no keys left,
                or if the track's lists no longer agree with each other.

                The first would make both end tests false, and the search
                for the key before it would walk off the end of the track.
                The other two are the same walk by another route: a track's
                fields are open, the constructor is not the last chance to
                change them, and a `times` list emptied afterward or a
                `values` list made shorter reads past its end on the next
                frame. An emptied track passed the agreement check, since
                no values match no keys, and crashed on the first key. It is
                two comparisons per sample, which is what the checks being
                cheap buys.
        """
        var seconds = at.to(SECOND)
        if not isfinite(seconds):
            raise Error("A track cannot be read at a time that is not a number")
        if len(self.times) == 0:
            raise Error("A track's keys were removed after it was built")
        if (
            len(self.values)
            != len(self.times) * self.target.kind.component_count()
        ):
            raise Error("A track's values no longer match its keys")
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
        if self.target.kind == QUATERNION:
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
        if self.target.kind == QUATERNION:
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
        if self.target.kind != QUATERNION:
            raise Error("Only a rotation track's value is a rotation")
        var numbers = self.sample(at)
        return Quaternion(numbers[0], numbers[1], numbers[2], numbers[3])
