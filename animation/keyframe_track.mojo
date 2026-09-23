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

## Smooth and cubic spline

`SMOOTH` is three.js's `InterpolateSmooth`, its `CubicInterpolant`. It is
not a Catmull-Rom spline through the keys: the slope at each key comes
from the keys on either side over their times, so uneven spacing is taken
into account, and reaching for the spline in `math.curve` instead would be
a different curve wearing the same name. Past either end of the track an
`Ending` says what stands in for the missing key: `ZERO_CURVATURE_ENDING`,
the default of a track read on its own, `ZERO_SLOPE_ENDING` or
`WRAP_AROUND_ENDING`. An action picks them from its loop mode, as
three.js's does.

`CUBIC_SPLINE` is glTF's cubic spline sampler, three.js's
`GLTFCubicSplineInterpolant`: each key carries an in-tangent and an
out-tangent beside its value, and the curve between two keys is the
Hermite cubic they make, the tangents scaled by the time between the keys.
It has its own constructor, which takes the tangents.

A rotation cannot be `SMOOTH`: three.js's `QuaternionKeyframeTrack` has no
smooth interpolant, warns and falls back to `LINEAR`. Here it is refused,
since a caller who asked for smooth did not ask for linear. A rotation can
be `CUBIC_SPLINE`, and is then run one number at a time and made of unit
length, which is three.js's `GLTFCubicSplineQuaternionInterpolant`. A
`VISIBLE` track is `STEP` and nothing else.

## What is refused

A track with no keys, or with times that do not rise. A list of values
that does not divide into one value per key, or tangents that are not one
per value. A kind, an interpolation or an ending that is none of the named
ones, or a morph target past the eighth. A `VISIBLE` track that is not
`STEP`, a key of one that is neither zero nor one, and a `SMOOTH`
rotation. Each of those is a track that cannot be
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
        """Return True if this is `STEP`, `LINEAR`, `SMOOTH` or
        `CUBIC_SPLINE`."""
        return self.value >= STEP.value and self.value <= CUBIC_SPLINE.value


# Hold each key's value until the next key: three.js's
# `InterpolateDiscrete`.
comptime STEP = Interpolation(0)
# Run evenly from each key to the next: three.js's `InterpolateLinear`,
# which for a rotation means `slerp`.
comptime LINEAR = Interpolation(1)
# A cubic through the keys whose slope at each key is taken from the keys
# on either side, over the uneven spacing of their times: three.js's
# `InterpolateSmooth`, its `CubicInterpolant`.
comptime SMOOTH = Interpolation(2)
# A Hermite cubic from each key's value and its own in- and out-tangent,
# scaled by the time between the two keys: glTF's `CUBICSPLINE`, three.js's
# `GLTFCubicSplineInterpolant`.
comptime CUBIC_SPLINE = Interpolation(3)


@fieldwise_init
struct Ending(Equatable, ImplicitlyCopyable, Writable):
    """What a `SMOOTH` track takes as the key past either end of the track,
    as a type rather than a bare int. three.js's ending modes."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three ending modes there
        are."""
        return (
            self.value >= ZERO_CURVATURE_ENDING.value
            and self.value <= WRAP_AROUND_ENDING.value
        )


# The curve does not bend at the end, a natural spline: three.js's
# `ZeroCurvatureEnding`, and the ending of a track read on its own.
comptime ZERO_CURVATURE_ENDING = Ending(0)
# The curve is flat at the end: three.js's `ZeroSlopeEnding`.
comptime ZERO_SLOPE_ENDING = Ending(1)
# The curve runs on into the other end of the track, for a clip that
# repeats: three.js's `WrapAroundEnding`.
comptime WRAP_AROUND_ENDING = Ending(2)


def check_interpolation(kind: TrackKind, how: Interpolation) raises:
    """Refuse an interpolation that a kind of track does not have.

    Args:
        kind: The kind of the track.
        how: The interpolation asked for.

    Raises:
        Error: If the interpolation is none of the named ones, if a
            `VISIBLE` track is anything but `STEP`, or if a `QUATERNION`
            track is `SMOOTH`.
    """
    if not how.is_valid():
        raise Error(
            "A track's interpolation must be STEP, LINEAR, SMOOTH or"
            " CUBIC_SPLINE"
        )
    if kind.is_boolean() and how != STEP:
        # three.js's `BooleanKeyframeTrack` has no other mode: a flag half
        # way between shown and hidden is neither.
        raise Error("A flag track holds each key: it must be STEP")
    if kind == QUATERNION and how == SMOOTH:
        # three.js's `QuaternionKeyframeTrack` sets its smooth factory to
        # `undefined`: four numbers on a cubic each are not a rotation.
        raise Error("A rotation track cannot be SMOOTH")


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
    # Every key's in-tangent and out-tangent, laid out as `values` is, for
    # a `CUBIC_SPLINE` track. Empty for every other interpolation.
    var in_tangents: List[Float32]
    var out_tangents: List[Float32]

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
            interpolation: `LINEAR`, `STEP` or `SMOOTH`. None takes the
                kind's own: `STEP` for `VISIBLE` and `LINEAR` for the
                others, as in three.js.

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
            interpolation: `LINEAR`, `STEP` or `SMOOTH`. None takes the
                kind's own: `STEP` for `VISIBLE`, three.js's
                `BooleanKeyframeTrack` default, and `LINEAR` for the
                others. `CUBIC_SPLINE` needs tangents, which the
                constructor that takes them is given.

        Raises:
            Error: If the target's kind is none of the named ones or its
                slot does not fit it, if the interpolation is none of the
                named ones, if a `VISIBLE` track is asked to be anything
                but `STEP`, if a `QUATERNION` track is asked to be
                `SMOOTH`, if the interpolation is `CUBIC_SPLINE`, which
                has no tangents here, if there are no keys, if a time or a value is not a number,
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
        check_interpolation(kind, how)
        if how == CUBIC_SPLINE:
            raise Error(
                "A CUBIC_SPLINE track needs tangents: use the constructor"
                " that takes them"
            )
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
        self.in_tangents = List[Float32]()
        self.out_tangents = List[Float32]()

    def __init__(
        out self,
        target: TrackTarget,
        times: List[Duration],
        *,
        var in_tangents: List[Float32],
        var values: List[Float32],
        var out_tangents: List[Float32],
    ) raises:
        """Create a `CUBIC_SPLINE` track, glTF's cubic spline sampler, from
        each key's in-tangent, value and out-tangent.

        glTF interleaves the three for each key, in-tangent first. Here
        they are three lists laid out alike, so `values` means what it
        means on every other track.

        Args:
            target: What the track drives. Any kind but `VISIBLE`.
            times: When each key is, as for any track.
            in_tangents: Every key's in-tangent end to end, in value units
                per second, `target.kind.component_count()` numbers each.
                The first key's is never read.
            values: Every key's value end to end, as for any track. A
                rotation key must be of unit length.
            out_tangents: Every key's out-tangent, laid out as
                `in_tangents`. The last key's is never read.

        Raises:
            Error: If the target is a `VISIBLE` flag, if either list of
                tangents is not as long as the values, or if a tangent is
                not a number; and as the constructor that takes an
                interpolation does, for the times and the values.
        """
        check_interpolation(target.kind, CUBIC_SPLINE)
        if len(in_tangents) != len(values) or len(out_tangents) != len(values):
            raise Error("A cubic spline track needs two tangents a value")
        for index in range(len(values)):
            if not isfinite(in_tangents[index]) or not isfinite(
                out_tangents[index]
            ):
                raise Error("A track's tangents must be numbers")
        self = Self(target, times, values^, LINEAR)
        self.interpolation = CUBIC_SPLINE
        self.in_tangents = in_tangents^
        self.out_tangents = out_tangents^

    def __init__(out self, *, copy: Self):
        """Copy another track."""
        self.target = copy.target
        self.interpolation = copy.interpolation
        self.times = copy.times.copy()
        self.values = copy.values.copy()
        self.in_tangents = copy.in_tangents.copy()
        self.out_tangents = copy.out_tangents.copy()

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

    def _smooth(
        self, key: Int, seconds: Float32, start: Ending, end: Ending
    ) -> List[Float32]:
        """Return a `SMOOTH` track's value between `key` and the key after
        it, three.js's `CubicInterpolant`, number for number.

        The slope at each key is the slope between the keys on either side
        of it, over their times, so uneven spacing is taken into account.
        The two keys around the time are weighted with the key before them
        and the key after them. Past either end of the track the ending
        mode says which key stands in, and at what time.
        """
        var width = self.target.kind.component_count()
        var count = len(self.times)
        var t0 = self.times[key]
        var t1 = self.times[key + 1]
        var prev = key - 1
        var next = key + 2
        var t_prev: Float32
        var t_next: Float32
        if prev >= 0:
            t_prev = self.times[prev]
        elif start == ZERO_SLOPE_ENDING:
            # f'(t0) = 0.
            prev = key + 1
            t_prev = 2 * t0 - t1
        elif start == WRAP_AROUND_ENDING:
            # The other end of the track, as though it came before.
            prev = count - 2
            t_prev = t0 + self.times[prev] - self.times[prev + 1]
        else:
            # f''(t0) = 0, a natural spline.
            prev = key + 1
            t_prev = t1
        if next < count:
            t_next = self.times[next]
        elif end == ZERO_SLOPE_ENDING:
            next = key + 1
            t_next = 2 * t1 - t0
        elif end == WRAP_AROUND_ENDING:
            next = 1
            t_next = t1 + self.times[1] - self.times[0]
        else:
            next = key
            t_next = t0
        var half = (t1 - t0) * 0.5
        var w_prev = half / (t0 - t_prev)
        var w_next = half / (t_next - t1)
        var p = (seconds - t0) / (t1 - t0)
        var pp = p * p
        var ppp = pp * p
        var s_prev = -w_prev * ppp + 2 * w_prev * pp - w_prev * p
        var s0 = (
            (1 + w_prev) * ppp
            + (-1.5 - 2 * w_prev) * pp
            + (-0.5 + w_prev) * p
            + 1
        )
        var s1 = (-1 - w_next) * ppp + (1.5 + w_next) * pp + 0.5 * p
        var s_next = w_next * ppp - w_next * pp
        var out = List[Float32]()
        for offset in range(width):  # pragma: no branch
            out.append(
                s_prev * self.values[prev * width + offset]
                + s0 * self.values[key * width + offset]
                + s1 * self.values[(key + 1) * width + offset]
                + s_next * self.values[next * width + offset]
            )
        return out^

    def _cubic_spline(self, key: Int, seconds: Float32) -> List[Float32]:
        """Return a `CUBIC_SPLINE` track's value between `key` and the key
        after it, three.js's `GLTFCubicSplineInterpolant` and, for a
        rotation, `GLTFCubicSplineQuaternionInterpolant`.

        A Hermite cubic from the first key's value and out-tangent to the
        second key's value and in-tangent. A tangent is in value units per
        second, so it is scaled by the time between the keys. A rotation is
        made of unit length afterward, which is all the quaternion form
        adds.
        """
        var width = self.target.kind.component_count()
        var span = self.times[key + 1] - self.times[key]
        var p = (seconds - self.times[key]) / span
        var pp = p * p
        var ppp = pp * p
        var s2 = -2 * ppp + 3 * pp
        var s3 = ppp - pp
        var s0 = 1 - s2
        var s1 = s3 - pp + p
        var out = List[Float32]()
        for offset in range(width):  # pragma: no branch
            var here = key * width + offset
            var there = (key + 1) * width + offset
            out.append(
                s0 * self.values[here]
                + s1 * self.out_tangents[here] * span
                + s2 * self.values[there]
                + s3 * self.in_tangents[there] * span
            )
        if self.target.kind == QUATERNION:
            var turned = Quaternion(out[0], out[1], out[2], out[3])
            turned.normalize()
            return [turned.x, turned.y, turned.z, turned.w]
        return out^

    def sample(
        self,
        at: Duration,
        start: Ending = ZERO_CURVATURE_ENDING,
        end: Ending = ZERO_CURVATURE_ENDING,
    ) raises -> List[Float32]:
        """Return the track's value at a time.

        Before the first key the value is the first key's, and after the
        last it is the last key's, which is what three.js's interpolants do
        at their ends.

        Args:
            at: When to read the track, from the start of the clip.
            start: What a `SMOOTH` track takes as the key before the first.
                `ZERO_CURVATURE_ENDING` by default, as a three.js
                `CubicInterpolant` has it on its own. An action sets it
                from its loop mode; see `animation.animation_mixer`.
            end: The same, for the key after the last.

        Returns:
            `kind.component_count()` numbers. A `QUATERNION` track returns
            a rotation of unit length.

        Raises:
            Error: If `at` is not a number, if either ending is none of the
                three, if the track's interpolation is not one its kind
                has, if the track has no keys left, or if the track's lists
                no longer agree with each other.

                The first would make both end tests false, and the search
                for the key before it would walk off the end of the track.
                The last two are the same walk by another route: a track's
                fields are open, the constructor is not the last chance to
                change them, and a `times` list emptied afterward or a
                `values` list made shorter reads past its end on the next
                frame. An emptied track passed the agreement check, since
                no values match no keys, and crashed on the first key. It is
                a few comparisons per sample, which is what the checks being
                cheap buys.
        """
        var seconds = at.to(SECOND)
        if not isfinite(seconds):
            raise Error("A track cannot be read at a time that is not a number")
        if not start.is_valid() or not end.is_valid():
            raise Error("A track needs an ending mode that exists")
        check_interpolation(self.target.kind, self.interpolation)
        if len(self.times) == 0:
            raise Error("A track's keys were removed after it was built")
        if (
            len(self.values)
            != len(self.times) * self.target.kind.component_count()
        ):
            raise Error("A track's values no longer match its keys")
        if self.interpolation == CUBIC_SPLINE:
            if len(self.in_tangents) != len(self.values) or len(
                self.out_tangents
            ) != len(self.values):
                raise Error("A track's tangents no longer match its values")
        var last = len(self.times) - 1
        if seconds <= self.times[0]:
            return self._value_at_key(0)
        if seconds >= self.times[last]:
            return self._value_at_key(last)
        var key = self._key_before(seconds)
        if self.interpolation == STEP:
            return self._value_at_key(key)
        if self.interpolation == SMOOTH:
            return self._smooth(key, seconds, start, end)
        if self.interpolation == CUBIC_SPLINE:
            return self._cubic_spline(key, seconds)
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

    def sample_vector3(
        self,
        at: Duration,
        start: Ending = ZERO_CURVATURE_ENDING,
        end: Ending = ZERO_CURVATURE_ENDING,
    ) raises -> Vector3:
        """Return a `POSITION` or `SCALE` track's value at a time.

        Args:
            at: When to read the track.
            start: The ending before the first key, as for `sample`.
            end: The ending after the last key, as for `sample`.

        Returns:
            The value as a vector.

        Raises:
            Error: If this is a `QUATERNION` track, whose value is not a
                vector, or as `sample` does.
        """
        if self.target.kind == QUATERNION:
            raise Error("A rotation track's value is not a vector")
        var numbers = self.sample(at, start, end)
        return Vector3(numbers[0], numbers[1], numbers[2])

    def sample_quaternion(self, at: Duration) raises -> Quaternion:
        """Return a `QUATERNION` track's value at a time.

        A rotation track is never `SMOOTH`, so it takes no ending modes.

        Args:
            at: When to read the track.

        Returns:
            The value as a rotation.

        Raises:
            Error: If this is not a `QUATERNION` track, or as `sample`
                does.
        """
        if self.target.kind != QUATERNION:
            raise Error("Only a rotation track's value is a rotation")
        var numbers = self.sample(at)
        return Quaternion(numbers[0], numbers[1], numbers[2], numbers[3])
