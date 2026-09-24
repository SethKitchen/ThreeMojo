# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One property of one node, mesh, material, light or camera, given a value
at a list of times, from three.js `src/animation/KeyframeTrack.js`, the
tracks beside it, `PropertyBinding.js` and the interpolants.

A track is two lists of the same length: when, and what. Between two
entries the value is worked out from the two around it, and outside the
ends it is the nearest end. That is all three.js's `KeyframeTrack` is, and
`VectorKeyframeTrack`, `QuaternionKeyframeTrack`, `NumberKeyframeTrack`,
`ColorKeyframeTrack`, `BooleanKeyframeTrack` and `StringKeyframeTrack`
differ only in how many numbers a value has and how two of them are
mixed.

So here there is one struct and a kind, for the reason `Curve` is one
struct and a kind: a clip has to hold a list of one type.

    POSITION           three numbers, where the node is
    SCALE              three numbers, how big it is
    QUATERNION         four numbers, which way it is turned
    VISIBLE            one number, zero or one, whether it is drawn
    NODE_NAME          a string, the node's name
    MORPH_INFLUENCE    one number, how much of a morph target a mesh wears,
                       and SKINNED_MORPH_INFLUENCE for a skinned mesh
    MATERIAL_COLOR     three linear channels, and the emissive and
                       specular colors beside it
    MATERIAL_OPACITY   one number, and the other number fields beside it
    MATERIAL_TRANSPARENT, MATERIAL_WIREFRAME   flags of a material
    LIGHT_COLOR        three linear channels
    LIGHT_INTENSITY    one number, and LIGHT_DISTANCE, LIGHT_ANGLE and
                       LIGHT_PENUMBRA beside it
    CAMERA_FOV         one number in degrees, and CAMERA_ZOOM, CAMERA_NEAR
                       and CAMERA_FAR beside it

A flag and a string are discrete, as three.js's `BooleanKeyframeTrack` and
`StringKeyframeTrack` are: `STEP` is their only interpolation. A string
track keeps each of its strings once, in `strings`, and each key's value is
the place of its string there, so a string key is one number like any
other and `optimize` finds two equal strings by their numbers.

## A target, not a path

three.js names its target with a string, `.position` or
`.material.opacity` or `.morphTargetInfluences[2]`, and `PropertyBinding`
parses it and finds the object by its name at run time. Here a track holds
a `TrackTarget`: the kind, and the index of the node, mesh, material,
light or camera. `node_target`, `morph_target`, `skinned_morph_target`,
`material_target`, `light_target`, `perspective_camera_target` and
`orthographic_camera_target` each take the id type their kind needs, a
`NodeId`, a `MeshIndex`, a `SkinnedMeshIndex`, a `MaterialId`, a
`LightIndex`, a `PerspectiveCameraIndex` or an `OrthographicCameraIndex`,
so a track cannot ask for a property that does not exist and cannot be
handed a material id where a node was meant.

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

## Bezier

`BEZIER` is three.js's `InterpolateBezier`, its `BezierInterpolant`, the
key of COLLADA and Maya. Each number of each key has two control points of
(time, value), in `in_tangents` and `out_tangents`, which is three.js's
`settings.inTangents` and `settings.outTangents`. Between two keys the
curve runs from the first key through its out control point and the
second key's in control point to the second key. The time is found on the
curve by eight steps of Newton's method, as three.js finds it, and the
value is read there. three.js falls back to `LINEAR` when a Bezier track
has no control points. Here such a track is refused, as a `CUBIC_SPLINE`
track without tangents is. A rotation is made of unit length afterward.
three.js runs a rotation one number at a time and leaves it as it comes.

## Editing a track

`shift`, `scale`, `trim`, `optimize` and `validate` are three.js's, and
work as three.js's do but where three.js leaves a track wrong. A Bezier
track's control points move with `shift` and are kept with `trim` and
`optimize`; three.js leaves them behind. A cubic spline's tangents are
divided by the factor of `scale`, since they are values per second; three.js
leaves them, which bends the curve. `shift` refuses a key before zero and
`scale` a factor that is not above zero, which make times a track cannot
have. `validate` answers True for a track its constructors would build.

## What is refused

A track with no keys, or with times that do not rise. A list of values
that does not divide into one value per key, or tangents that are not one
per value, or two per value for `BEZIER`. A kind, an interpolation or an
ending that is none of the named ones, or a morph target past the eighth.
A flag or a string track that is not `STEP`, a flag key that is neither
zero nor one, a string track built from numbers, and a `SMOOTH`
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

from core.object3d import NodeId
from materials.material import MaterialId
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import isfinite, isnan
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
            self.value >= VISIBLE.value
            and self.value <= SKINNED_MORPH_INFLUENCE.value
        )

    def is_node(self) -> Bool:
        """Return True if this kind drives a scene node: its position,
        scale, rotation, `visible` flag or name."""
        return (
            self == POSITION
            or self == SCALE
            or self == QUATERNION
            or self == VISIBLE
            or self == NODE_NAME
        )

    def is_morph(self) -> Bool:
        """Return True if this kind drives a morph target influence, of a
        mesh or of a skinned mesh."""
        return self == MORPH_INFLUENCE or self == SKINNED_MORPH_INFLUENCE

    def is_skinned(self) -> Bool:
        """Return True if this kind drives a skinned mesh's morph target
        influence."""
        return self == SKINNED_MORPH_INFLUENCE

    def is_material(self) -> Bool:
        """Return True if this kind drives a field of a material."""
        return (
            self.value >= MATERIAL_COLOR.value
            and self.value <= MATERIAL_IOR.value
        ) or (self == MATERIAL_TRANSPARENT or self == MATERIAL_WIREFRAME)

    def is_light(self) -> Bool:
        """Return True if this kind drives a light's color, intensity,
        distance, angle or penumbra."""
        return (
            self.value >= LIGHT_COLOR.value
            and self.value <= LIGHT_PENUMBRA.value
        )

    def is_camera(self) -> Bool:
        """Return True if this kind drives a camera's field of view, zoom,
        near plane or far plane."""
        return self.value >= CAMERA_FOV.value and self.value <= CAMERA_FAR.value

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
        return (
            self == VISIBLE
            or self == MATERIAL_TRANSPARENT
            or self == MATERIAL_WIREFRAME
        )

    def is_string(self) -> Bool:
        """Return True if this kind's value is a string, three.js's
        `StringKeyframeTrack`."""
        return self == NODE_NAME

    def is_discrete(self) -> Bool:
        """Return True if this kind's values cannot be mixed, only chosen:
        a flag or a string. Such a track is `STEP`, and nothing else."""
        return self.is_boolean() or self.is_string()

    def value_type_name(self) -> String:
        """Return three.js's `ValueTypeName` for this kind's track, the
        `type` a track has in JSON.

        Returns:
            `vector`, `quaternion`, `bool`, `string`, `color` or `number`,
            and an empty string for a kind that is not valid.
        """
        if self == POSITION or self == SCALE:
            return "vector"
        if self == QUATERNION:
            return "quaternion"
        if self.is_boolean():
            return "bool"
        if self.is_string():
            return "string"
        if self.is_color():
            return "color"
        if self.is_valid():
            return "number"
        return ""

    def component_count(self) -> Int:
        """Return how many numbers one of this kind's values holds.

        Returns:
            Four for `QUATERNION`, three for `POSITION`, `SCALE` and the
            colors, and one for every other kind. A string key is one
            number, its place in the track's `strings`. Zero for a kind
            that is not valid, which `KeyframeTrack.__init__` has already
            refused.
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
# A light's other numbers, three.js's `.distance`, `.angle` and `.penumbra`.
# The distance is in meters, the angle in radians, and the penumbra a share
# from zero to one, each as three.js keeps it.
comptime LIGHT_DISTANCE = TrackKind(29)
comptime LIGHT_ANGLE = TrackKind(30)
comptime LIGHT_PENUMBRA = TrackKind(31)
# A camera's numbers, three.js's `.fov`, `.zoom`, `.near` and `.far`. The
# field of view is in degrees, as three.js keeps it, and the planes are in
# meters. Only a perspective camera has a field of view.
comptime CAMERA_FOV = TrackKind(32)
comptime CAMERA_ZOOM = TrackKind(33)
comptime CAMERA_NEAR = TrackKind(34)
comptime CAMERA_FAR = TrackKind(35)
# A node's name, three.js's `.name` `StringKeyframeTrack`. Each key is a
# string, held until the next key.
comptime NODE_NAME = TrackKind(36)
# A material's flags, three.js's `.material.transparent` and
# `.material.wireframe` `BooleanKeyframeTrack`s.
comptime MATERIAL_TRANSPARENT = TrackKind(37)
comptime MATERIAL_WIREFRAME = TrackKind(38)
# How much of one morph target a skinned mesh wears, three.js's
# `.morphTargetInfluences[i]` on a `SkinnedMesh`.
comptime SKINNED_MORPH_INFLUENCE = TrackKind(39)


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
struct SkinnedMeshIndex(Equatable, ImplicitlyCopyable, Writable):
    """Which of a scene's `skinned_meshes` a track drives, as a type rather
    than a bare int.

    An index into `Scene.skinned_meshes`. Any integer makes one, so the
    mixer checks it against the scene it is given.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative."""
        return self.value >= 0


@fieldwise_init
struct PerspectiveCameraIndex(Equatable, ImplicitlyCopyable, Writable):
    """Which of a `CameraList`'s perspective cameras a track drives, as a
    type rather than a bare int.

    Any integer makes one, so the mixer checks it against the cameras it
    is given.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative."""
        return self.value >= 0


@fieldwise_init
struct OrthographicCameraIndex(Equatable, ImplicitlyCopyable, Writable):
    """Which of a `CameraList`'s orthographic cameras a track drives, as a
    type rather than a bare int.

    Any integer makes one, so the mixer checks it against the cameras it
    is given.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative."""
        return self.value >= 0


# The slot of a camera target: which of a `CameraList`'s two lists its
# index is in.
comptime PERSPECTIVE_SLOT = 0
comptime ORTHOGRAPHIC_SLOT = 1


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
    # The node, mesh, skinned mesh, material, light or camera, as its
    # index. The kind says which.
    var index: Int
    # Which morph target, for a morph kind; which list of cameras,
    # `PERSPECTIVE_SLOT` or `ORTHOGRAPHIC_SLOT`, for a camera kind; zero
    # for every other kind.
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
            return self.slot >= 0
        if self.kind == CAMERA_FOV:
            # An orthographic camera has no field of view.
            return self.slot == PERSPECTIVE_SLOT
        if self.kind.is_camera():
            return (
                self.slot == PERSPECTIVE_SLOT or self.slot == ORTHOGRAPHIC_SLOT
            )
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
        Error: If the target is negative. There is no upper limit: a mesh
            wears as many targets as its geometry carries.
    """
    if target < 0:
        raise Error("A morph target index cannot be negative")
    return TrackTarget(MORPH_INFLUENCE, mesh.value, target)


def skinned_morph_target(
    mesh: SkinnedMeshIndex, target: Int
) raises -> TrackTarget:
    """Return the target for one morph target influence of one skinned
    mesh, three.js's `.morphTargetInfluences[target]` on a `SkinnedMesh`.

    Args:
        mesh: Which of the scene's skinned meshes.
        target: Which morph target, from zero.

    Returns:
        The target.

    Raises:
        Error: If the target is negative. There is no upper limit.
    """
    if target < 0:
        raise Error("A morph target index cannot be negative")
    return TrackTarget(SKINNED_MORPH_INFLUENCE, mesh.value, target)


def perspective_camera_target(
    camera: PerspectiveCameraIndex, kind: TrackKind
) raises -> TrackTarget:
    """Return the target for one number of one perspective camera.

    Args:
        camera: Which of a `CameraList`'s perspective cameras.
        kind: `CAMERA_FOV`, `CAMERA_ZOOM`, `CAMERA_NEAR` or `CAMERA_FAR`.

    Returns:
        The target.

    Raises:
        Error: If the kind does not drive a camera.
    """
    if not kind.is_camera():
        raise Error("A camera target needs a kind that drives a camera")
    return TrackTarget(kind, camera.value, PERSPECTIVE_SLOT)


def orthographic_camera_target(
    camera: OrthographicCameraIndex, kind: TrackKind
) raises -> TrackTarget:
    """Return the target for one number of one orthographic camera.

    Args:
        camera: Which of a `CameraList`'s orthographic cameras.
        kind: `CAMERA_ZOOM`, `CAMERA_NEAR` or `CAMERA_FAR`.

    Returns:
        The target.

    Raises:
        Error: If the kind does not drive a camera, or is `CAMERA_FOV`,
            which an orthographic camera does not have.
    """
    if not kind.is_camera() or kind == CAMERA_FOV:
        raise Error("An orthographic camera target needs its zoom, near or far")
    return TrackTarget(kind, camera.value, ORTHOGRAPHIC_SLOT)


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
    """Return the target for one property of one light.

    Args:
        light: Which of the scene's lights.
        kind: `LIGHT_COLOR`, `LIGHT_INTENSITY`, `LIGHT_DISTANCE`,
            `LIGHT_ANGLE` or `LIGHT_PENUMBRA`.

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
        """Return True if this is `STEP`, `LINEAR`, `SMOOTH`,
        `CUBIC_SPLINE` or `BEZIER`."""
        return self.value >= STEP.value and self.value <= BEZIER.value


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
# A cubic Bezier curve per number from each key's value and two control
# points of (time, value) beside it: three.js's `InterpolateBezier`, its
# `BezierInterpolant`, the COLLADA and Maya kind of key.
comptime BEZIER = Interpolation(4)


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
        Error: If the interpolation is none of the named ones, if a flag
            or a string track is anything but `STEP`, or if a
            `QUATERNION` track is `SMOOTH`.
    """
    if not how.is_valid():
        raise Error(
            "A track's interpolation must be STEP, LINEAR, SMOOTH,"
            " CUBIC_SPLINE or BEZIER"
        )
    if kind.is_discrete() and how != STEP:
        # three.js's `BooleanKeyframeTrack` and `StringKeyframeTrack` have
        # no other mode: a flag half way between shown and hidden is
        # neither, and there is no string half way between two others.
        raise Error("A flag or a string track holds each key: it must be STEP")
    if kind == QUATERNION and how == SMOOTH:
        # three.js's `QuaternionKeyframeTrack` sets its smooth factory to
        # `undefined`: four numbers on a cubic each are not a rotation.
        raise Error("A rotation track cannot be SMOOTH")


def _cubic_bezier(
    s: Float64, p0: Float64, p1: Float64, p2: Float64, p3: Float64
) -> Float64:
    """Return a cubic Bezier curve's value at `s`, three.js's
    `cubicBezier`."""
    var k = 1 - s
    return (
        k * k * k * p0
        + 3 * k * k * s * p1
        + 3 * k * s * s * p2
        + s * s * s * p3
    )


def _cubic_bezier_slope(
    s: Float64, p0: Float64, p1: Float64, p2: Float64, p3: Float64
) -> Float64:
    """Return a cubic Bezier curve's slope at `s`, three.js's
    `cubicBezierSlope`."""
    var k = 1 - s
    return 3 * k * k * (p1 - p0) + 6 * k * s * (p2 - p1) + 3 * s * s * (p3 - p2)


def solve_bezier_parameter(
    x: Float64, x0: Float64, x1: Float64, x2: Float64, x3: Float64
) -> Float64:
    """Return where along a cubic Bezier curve its first coordinate is `x`,
    three.js's `solveBezierParameter`.

    Eight steps of Newton's method from the straight-line guess, each kept
    between zero and one, as three.js takes them. The search stops when the
    curve is within `1e-10` of `x`. Where the curve is flat, a step of
    nothing is taken, which is three.js's stop by another route.

    Args:
        x: The time wanted.
        x0: The time of the first key.
        x1: The time of the first key's out control point.
        x2: The time of the second key's in control point.
        x3: The time of the second key.

    Returns:
        The curve parameter, from zero to one.
    """
    var s = (x - x0) / (x3 - x0)
    for _ in range(8):  # pragma: no branch
        var error = _cubic_bezier(s, x0, x1, x2, x3) - x
        if abs(error) < 1e-10:
            break
        var slope = _cubic_bezier_slope(s, x0, x1, x2, x3)
        s = s if abs(slope) < 1e-10 else max(
            Float64(0), min(Float64(1), s - error / slope)
        )
    return s


struct KeyframeTrack(Copyable, Movable):
    """One property of one node, mesh, material, light or camera, given a
    value at a list of times."""

    var target: TrackTarget
    var interpolation: Interpolation
    # When each key is, in seconds from the start of the clip, rising.
    var times: List[Float32]
    # Every key's value end to end, `target.kind.component_count()`
    # numbers each. A string key is its place in `strings`.
    var values: List[Float32]
    # Every key's in-tangent and out-tangent. For a `CUBIC_SPLINE` track
    # they are laid out as `values` is. For a `BEZIER` track each number
    # of each key has a control point of two numbers, a time in seconds
    # and a value, so the lists are twice as long as `values`. Empty for
    # every other interpolation.
    var in_tangents: List[Float32]
    var out_tangents: List[Float32]
    # The strings a string track's keys name, each once. Empty for every
    # other kind.
    var strings: List[String]

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
        """Create a track on any property a track can drive but a string.

        Args:
            target: What the track drives. Build it with `node_target`,
                `morph_target`, `skinned_morph_target`, `material_target`,
                `light_target`, `perspective_camera_target` or
                `orthographic_camera_target`.
            times: When each key is, from the start of the clip, rising and
                none of them negative. At least one.
            values: Every key's value end to end,
                `target.kind.component_count()` numbers each. A flag key is
                zero or one.
            interpolation: `LINEAR`, `STEP` or `SMOOTH`. None takes the
                kind's own: `STEP` for a flag, three.js's
                `BooleanKeyframeTrack` default, and `LINEAR` for the
                others. `CUBIC_SPLINE` and `BEZIER` need tangents, which
                the constructor that takes them is given.

        Raises:
            Error: If the target's kind is none of the named ones or its
                slot does not fit it, if it is a string kind, which the
                constructor that takes strings builds, if the
                interpolation is none of the named ones, if a flag track
                is asked to be anything but `STEP`, if a `QUATERNION`
                track is asked to be `SMOOTH`, if the interpolation is
                `CUBIC_SPLINE` or `BEZIER`, which have no tangents here, if
                there are no keys, if a time or a value is not a number,
                if a time is negative or does not rise above the one before
                it, if the values do not divide into one value per key, if
                a rotation key is not of unit length, or if a flag key is
                neither zero nor one.
        """
        if not target.is_valid():
            raise Error("A track needs a kind that exists and fits its slot")
        var kind = target.kind
        if kind.is_string():
            raise Error("A string track takes strings, not numbers")
        var how = STEP if kind.is_discrete() else LINEAR
        if Bool(interpolation):
            how = interpolation.value()
        check_interpolation(kind, how)
        if how == CUBIC_SPLINE or how == BEZIER:
            raise Error(
                "A CUBIC_SPLINE or BEZIER track needs tangents: use the"
                " constructor that takes them"
            )
        self = Self(checked_target=target, times=times, values=values^, how=how)

    def __init__(
        out self,
        *,
        checked_target: TrackTarget,
        times: List[Duration],
        var values: List[Float32],
        how: Interpolation,
    ) raises:
        """Check the times and the values of a track whose target and
        interpolation the caller has checked, and build it with no
        tangents and no strings. The other constructors end here.

        Args:
            checked_target: What the track drives, already checked.
            times: When each key is.
            values: Every key's value end to end.
            how: The interpolation, already checked against the kind.

        Raises:
            Error: If there are no keys, if a time or a value is not a
                number, if a time is negative or does not rise, if the
                values do not divide into one value per key, if a rotation
                key is not of unit length, or if a flag key is neither
                zero nor one.
        """
        var target = checked_target
        var kind = target.kind
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
        self.strings = List[String]()

    def __init__(
        out self,
        target: TrackTarget,
        times: List[Duration],
        *,
        var in_tangents: List[Float32],
        var values: List[Float32],
        var out_tangents: List[Float32],
        interpolation: Interpolation = CUBIC_SPLINE,
    ) raises:
        """Create a `CUBIC_SPLINE` track, glTF's cubic spline sampler, or a
        `BEZIER` track, three.js's `InterpolateBezier`, from each key's
        value and its two tangents.

        glTF interleaves the three for each key, in-tangent first. Here
        they are three lists, so `values` means what it means on every
        other track. three.js keeps a Bezier track's tangents in its
        `settings`, as `inTangents` and `outTangents`, laid out as here.

        Args:
            target: What the track drives. Any kind but a flag or a
                string.
            times: When each key is, as for any track.
            in_tangents: For `CUBIC_SPLINE`, every key's in-tangent end to
                end, in value units per second,
                `target.kind.component_count()` numbers each. For
                `BEZIER`, every number's in control point, a time in
                seconds and a value, so two numbers for each number of
                `values`. The first key's is never read.
            values: Every key's value end to end, as for any track. A
                rotation key must be of unit length.
            out_tangents: Every key's out-tangent or out control points,
                laid out as `in_tangents`. The last key's is never read.
            interpolation: `CUBIC_SPLINE`, the default, or `BEZIER`.

        Raises:
            Error: If the interpolation is neither of the two, if the
                target is a flag or a string, if either list of tangents
                is not as long as it must be, or if a tangent is not a
                number; and as the constructor that takes an interpolation
                does, for the target, the times and the values.
        """
        if not target.is_valid():
            raise Error("A track needs a kind that exists and fits its slot")
        if interpolation != CUBIC_SPLINE and interpolation != BEZIER:
            raise Error("A track with tangents is CUBIC_SPLINE or BEZIER")
        check_interpolation(target.kind, interpolation)
        var per_value = 2 if interpolation == BEZIER else 1
        var wanted = len(values) * per_value
        if len(in_tangents) != wanted or len(out_tangents) != wanted:
            raise Error(
                "A cubic spline track needs two tangents a value, and a"
                " Bezier track two control points a value"
            )
        for index in range(wanted):
            if not isfinite(in_tangents[index]) or not isfinite(
                out_tangents[index]
            ):
                raise Error("A track's tangents must be numbers")
        self = Self(
            checked_target=target,
            times=times,
            values=values^,
            how=interpolation,
        )
        self.in_tangents = in_tangents^
        self.out_tangents = out_tangents^

    def __init__(
        out self,
        target: TrackTarget,
        times: List[Duration],
        strings: List[String],
    ) raises:
        """Create a string track, three.js's `StringKeyframeTrack`.

        Each key's string is held until the next key. The track keeps each
        string once, in `strings`, and each key's value is its place
        there, so two keys of the same string have the same value.

        Args:
            target: What the track drives: a string kind, `NODE_NAME`.
            times: When each key is, as for any track.
            strings: Every key's string, one a key.

        Raises:
            Error: If the target is not a string kind, if there is not one
                string a key, and as the constructor that takes numbers
                does, for the target and the times.
        """
        if not target.is_valid():
            raise Error("A track needs a kind that exists and fits its slot")
        if not target.kind.is_string():
            raise Error("Only a string track takes strings")
        if len(strings) != len(times):
            raise Error("A track needs one value for every key")
        var kept = List[String]()
        var places = List[Float32]()
        for index in range(len(strings)):
            var found = -1
            for known in range(len(kept)):
                if kept[known] == strings[index]:
                    found = known
                    break
            if found < 0:
                found = len(kept)
                kept.append(strings[index])
            places.append(Float32(found))
        self = Self(
            checked_target=target, times=times, values=places^, how=STEP
        )
        self.strings = kept^

    def __init__(out self, *, copy: Self):
        """Copy another track."""
        self.target = copy.target
        self.interpolation = copy.interpolation
        self.times = copy.times.copy()
        self.values = copy.values.copy()
        self.in_tangents = copy.in_tangents.copy()
        self.out_tangents = copy.out_tangents.copy()
        self.strings = copy.strings.copy()

    def kind(self) -> TrackKind:
        """Return which property the track drives."""
        return self.target.kind

    def key_count(self) -> Int:
        """Return how many keys the track holds."""
        return len(self.times)

    def value_size(self) -> Int:
        """Return how many numbers one key's value holds, three.js's
        `getValueSize`."""
        return self.target.kind.component_count()

    def duration(self) -> Duration:
        """Return when the last key is, which is how long the track runs.

        No time at all for a track whose keys were removed after it was
        built: the fields are open, and reading the last of no keys was a
        crash rather than an answer.
        """
        if len(self.times) == 0:
            return Duration(0, SECOND)
        return Duration(self.times[len(self.times) - 1], SECOND)

    def key_strings(self) raises -> List[String]:
        """Return a string track's keys as the strings they name.

        Returns:
            One string a key.

        Raises:
            Error: If the track is not a string track, or a key names no
                string of `strings`.
        """
        if not self.target.kind.is_string():
            raise Error("Only a string track's keys are strings")
        var out = List[String]()
        for key in range(len(self.values)):
            var place = Int(self.values[key])
            if (
                Float32(place) != self.values[key]
                or place < 0
                or place >= len(self.strings)
            ):
                raise Error("A string track's key names no string it holds")
            out.append(self.strings[place])
        return out^

    def _rebuilt(self) raises -> Self:
        """Return the track built again from its fields, which checks every
        field as the constructors check them."""
        var at = List[Duration]()
        for key in range(len(self.times)):
            at.append(Duration(self.times[key], SECOND))
        if self.target.kind.is_string():
            return Self(self.target, at, self.key_strings())
        if self.interpolation == CUBIC_SPLINE or self.interpolation == BEZIER:
            return Self(
                self.target,
                at,
                in_tangents=self.in_tangents.copy(),
                values=self.values.copy(),
                out_tangents=self.out_tangents.copy(),
                interpolation=self.interpolation,
            )
        return Self(self.target, at, self.values.copy(), self.interpolation)

    def validate(self) -> Bool:
        """Return True if the track is one its constructors would build,
        three.js's `validate`.

        A track's fields are open, so a track that was right when it was
        built can be edited into one that is not. three.js's `validate`
        checks that the value size is whole, that there are keys, and that
        the times and values are numbers and do not fall. This checks what
        the constructors check, which is all of that and more: the times
        must rise, none of them negative, and the tangents, the strings, a
        rotation's length and a flag's value must be as the kind needs.

        Returns:
            True if the track is sound. three.js logs what is wrong; here
            `_rebuilt` raises it, for a caller who wants to know.
        """
        try:
            _ = self._rebuilt()
            return True
        except:
            return False

    def shift(mut self, offset: Duration) raises:
        """Move every key by `offset`, three.js's `shift`.

        A `BEZIER` track's control points are moved too, since their times
        are times on the same clock. three.js moves the keys and leaves the
        control points behind, which bends the curve.

        Args:
            offset: How far to move the keys; negative moves them earlier.

        Raises:
            Error: If the offset is not a number, the track holds no keys,
                or the first key would move before zero, which is a time a
                track cannot have.
        """
        var by = offset.to(SECOND)
        if not isfinite(by):
            raise Error("A track cannot shift by a time that is not a number")
        if len(self.times) == 0:
            raise Error("A track's keys were removed after it was built")
        if self.times[0] + by < 0:
            raise Error("A track's times cannot be negative")
        for key in range(len(self.times)):  # pragma: no branch
            self.times[key] += by
        if self.interpolation == BEZIER:
            for at in range(0, len(self.in_tangents), 2):
                self.in_tangents[at] += by
            for at in range(0, len(self.out_tangents), 2):
                self.out_tangents[at] += by

    def scale(mut self, factor: Float32) raises:
        """Multiply every key's time by `factor`, three.js's `scale`: from
        frames to seconds, or to play a track slower or faster.

        A `BEZIER` track's control point times are scaled too, as three.js
        scales them. A `CUBIC_SPLINE` track's tangents are divided by the
        factor, since a tangent is value per second and a second is now
        longer or shorter. three.js leaves them, which makes the curve
        between two keys bulge more as the keys move apart.

        Args:
            factor: What to multiply the times by; above zero.

        Raises:
            Error: If the factor is not a number above zero. Zero would
                put every key at one time, and a negative factor would
                make the times fall.
        """
        if not isfinite(factor) or factor <= 0:
            raise Error(
                "A track's times can only be scaled by a number above zero"
            )
        for key in range(len(self.times)):
            self.times[key] *= factor
        if self.interpolation == BEZIER:
            for at in range(0, len(self.in_tangents), 2):
                self.in_tangents[at] *= factor
            for at in range(0, len(self.out_tangents), 2):
                self.out_tangents[at] *= factor
        elif self.interpolation == CUBIC_SPLINE:
            for at in range(len(self.in_tangents)):
                self.in_tangents[at] /= factor
            for at in range(len(self.out_tangents)):
                self.out_tangents[at] /= factor

    def _tangent_width(self) -> Int:
        """Return how many tangent numbers go with one key: none, a value's
        worth, or two for each number of a value."""
        var width = self.target.kind.component_count()
        if self.interpolation == BEZIER:
            return width * 2
        if self.interpolation == CUBIC_SPLINE:
            return width
        return 0

    def _keep(mut self, keys: List[Int]):
        """Keep only the keys listed, in order, with their values and
        tangents."""
        var width = self.target.kind.component_count()
        var tangents = self._tangent_width()
        var times = List[Float32]()
        var values = List[Float32]()
        var ins = List[Float32]()
        var outs = List[Float32]()
        for index in range(len(keys)):  # pragma: no branch
            var key = keys[index]
            times.append(self.times[key])
            for offset in range(width):  # pragma: no branch
                values.append(self.values[key * width + offset])
            for offset in range(tangents):
                ins.append(self.in_tangents[key * tangents + offset])
                outs.append(self.out_tangents[key * tangents + offset])
        self.times = times^
        self.values = values^
        self.in_tangents = ins^
        self.out_tangents = outs^

    def trim(mut self, start: Duration, end: Duration) raises:
        """Drop the keys before `start` and after `end`, three.js's `trim`.

        No key is made at either cut and none is moved, so the values
        inside the range are as they were. A track keeps at least one key,
        as in three.js: a range that holds none keeps the key nearest
        after it, or the last. The tangents of the keys kept are kept too;
        three.js keeps a Bezier track's control points whole, and they no
        longer line up with the keys.

        Args:
            start: The earliest time kept.
            end: The latest time kept.

        Raises:
            Error: If either time is not a number, or the track's lists no
                longer agree with each other.
        """
        var first = start.to(SECOND)
        var last = end.to(SECOND)
        if isnan(first) or isnan(last):
            raise Error(
                "A track cannot be trimmed at a time that is not a number"
            )
        self._check_lists()
        var count = len(self.times)
        var start_key = 0
        var stop_key = count - 1
        while start_key != count and self.times[start_key] < first:
            start_key += 1
        while stop_key != -1 and self.times[stop_key] > last:
            stop_key -= 1
        stop_key += 1
        if start_key == 0 and stop_key == count:
            return
        if start_key >= stop_key:
            stop_key = max(stop_key, 1)
            start_key = stop_key - 1
        var kept = List[Int]()
        for key in range(start_key, stop_key):  # pragma: no branch
            kept.append(key)
        self._keep(kept)

    def _same(self, key: Int, other: Int) -> Bool:
        """Return True if two keys hold the same value and the same
        tangents."""
        var width = self.target.kind.component_count()
        for offset in range(width):  # pragma: no branch
            if (
                self.values[key * width + offset]
                != self.values[other * width + offset]
            ):
                return False
        var tangents = self._tangent_width()
        for offset in range(tangents):
            var here = key * tangents + offset
            var there = other * tangents + offset
            if self.in_tangents[here] != self.in_tangents[there]:
                return False
            if self.out_tangents[here] != self.out_tangents[there]:
                return False
        return True

    def optimize(mut self) raises:
        """Drop every key that holds the same value as the keys on both
        sides of it, three.js's `optimize`: `0 0 0 1 1 1 0 0` keeps
        `0 0 1 1 0 0`.

        The first and the last key are always kept. A `SMOOTH` track keeps
        every key, as in three.js, since each key bends the curve on either
        side of it. A `CUBIC_SPLINE` or `BEZIER` key is dropped only if its
        tangents match too. three.js compares a Bezier key's value alone
        and does not drop its control points, which leaves them out of line
        with the keys.

        three.js also drops a key at the same time as the one after it.
        Here the times of a track rise, so there is none.

        Raises:
            Error: If the track's lists no longer agree with each other.
        """
        self._check_lists()
        var last = len(self.times) - 1
        var kept: List[Int] = [0]
        var smooth = self.interpolation == SMOOTH
        for key in range(1, last):
            if (
                smooth
                or not self._same(key, key - 1)
                or not self._same(key, key + 1)
            ):
                kept.append(key)
        if last > 0:
            kept.append(last)
        self._keep(kept)

    def _value_at_key(self, key: Int) -> List[Float32]:
        """Return the value stored at one key, its own numbers alone."""
        var width = self.target.kind.component_count()
        var out = List[Float32]()
        for offset in range(width):  # pragma: no branch
            out.append(self.values[key * width + offset])
        return out^

    def _key_before(self, seconds: Float32) -> Int:
        """Return the last key at or before `seconds`. The caller has
        checked that the time falls inside the track.

        A binary search: the times rise, so the key is found in a number of
        steps that grows with the logarithm of the keys rather than with
        the keys, and a long clip read every frame does not walk its whole
        track to find where it is. The caller's check means the first key
        is at or before the time and the last key after it.
        """
        var low = 0
        var high = len(self.times) - 1
        while high - low > 1:
            var middle = (low + high) // 2
            if self.times[middle] <= seconds:
                low = middle
            else:
                high = middle
        return low

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

    def _bezier(self, key: Int, seconds: Float32) -> List[Float32]:
        """Return a `BEZIER` track's value between `key` and the key after
        it, three.js's `BezierInterpolant`, number for number.

        Each number has its own curve, from the first key's value through
        its out control point and the second key's in control point to the
        second key's value. The curve parameter is found where the curve's
        time is `seconds`, and the value is read there. The arithmetic is
        in double precision, as three.js's is. A rotation is made of unit
        length afterward: three.js runs a rotation one number at a time
        and hands the mixer what comes out.
        """
        var width = self.target.kind.component_count()
        var t0 = Float64(self.times[key])
        var t1 = Float64(self.times[key + 1])
        var out = List[Float32]()
        for offset in range(width):  # pragma: no branch
            var leaving = (key * width + offset) * 2
            var arriving = ((key + 1) * width + offset) * 2
            var along = solve_bezier_parameter(
                Float64(seconds),
                t0,
                Float64(self.out_tangents[leaving]),
                Float64(self.in_tangents[arriving]),
                t1,
            )
            out.append(
                Float32(
                    _cubic_bezier(
                        along,
                        Float64(self.values[key * width + offset]),
                        Float64(self.out_tangents[leaving + 1]),
                        Float64(self.in_tangents[arriving + 1]),
                        Float64(self.values[(key + 1) * width + offset]),
                    )
                )
            )
        if self.target.kind == QUATERNION:
            var turned = Quaternion(out[0], out[1], out[2], out[3])
            turned.normalize()
            return [turned.x, turned.y, turned.z, turned.w]
        return out^

    def _check_lists(self) raises:
        """Refuse a track whose lists no longer agree with each other.

        Raises:
            Error: If the track has no keys, if the values do not divide
                into one a key, or if the tangents do not match the values.
        """
        if len(self.times) == 0:
            raise Error("A track's keys were removed after it was built")
        if (
            len(self.values)
            != len(self.times) * self.target.kind.component_count()
        ):
            raise Error("A track's values no longer match its keys")
        var tangents = self._tangent_width() * len(self.times)
        if (
            len(self.in_tangents) != tangents
            or len(self.out_tangents) != tangents
        ):
            raise Error("A track's tangents no longer match its values")

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
            a rotation of unit length. A string track returns the place
            of its string in `strings`; `sample_string` returns the string.

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
        self._check_lists()
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
        if self.interpolation == BEZIER:
            return self._bezier(key, seconds)
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

    def sample_string(self, at: Duration) raises -> String:
        """Return a string track's value at a time.

        Args:
            at: When to read the track.

        Returns:
            The string of the last key at or before `at`, or of the first
            key before it.

        Raises:
            Error: If this is not a string track, if its key names no
                string it holds, or as `sample` does.
        """
        if not self.target.kind.is_string():
            raise Error("Only a string track's value is a string")
        var place = Int(self.sample(at)[0])
        if place < 0 or place >= len(self.strings):
            raise Error("A string track's key names no string it holds")
        return self.strings[place]

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
