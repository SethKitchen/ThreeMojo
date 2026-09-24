# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""BVH motion capture, from three.js `examples/jsm/loaders/BVHLoader.js`.

A Biovision Hierarchy file has two parts. `HIERARCHY` is a tree of
joints, each with an `OFFSET` from its parent and the `CHANNELS` it
moves by; an `End Site` ends a branch. `MOTION` gives the number of
frames, the time a frame takes, and one line of channel values for each
frame, joint by joint in the order the tree lists them.

`parse_bvh` adds one scene node for each joint and end site, placed at
its offset under its parent, and returns them as a `Skeleton` with an
`AnimationClip` named `animation`. For each joint, the clip has a
`POSITION` track of the joint's offset plus its position channels, and
a `QUATERNION` track of its rotation channels multiplied in file order.
An end site has no track. Angles in the file are degrees.

**The skeleton.** three.js's `Skeleton` takes the inverse of each bone's
world matrix as it is made, and the bones' world matrices are not yet
updated then, so every inverse is the identity. The inverse binds here
are the identity too.

**Where this port differs.** three.js logs an error and reads on when a
keyword it expects is not there, a count or an offset is not a number,
or a channel is not known. This port refuses each of these. It also
refuses a file that ends early, where three.js throws a `TypeError`.
A clip must last longer than no time here, so a file of fewer than two
frames, or a frame time of zero or less, gives no clip. So does a file whose tracks
are all turned off.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import POSITION, QUATERNION, KeyframeTrack
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.js_number import js_parse_float, js_parse_int
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.skeleton import Bone, Skeleton
from std.math import cos, isnan, pi, sin
from std.pathlib import Path
from units.si import SECOND, Duration

# A rotation as x, y, z and w, in `Float64` as three.js computes it.
comptime Rotation = SIMD[DType.float64, 4]


@fieldwise_init
struct BvhChannel(Equatable, ImplicitlyCopyable, Writable):
    """One of the six channels a joint moves by, as a type rather than a
    bare int.

    `axis_rotation` refuses one that is not a valid rotation.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the six channels."""
        return self.value >= X_POSITION.value and self.value <= Z_ROTATION.value

    def is_rotation(self) -> Bool:
        """Return True for `Xrotation`, `Yrotation` and `Zrotation`."""
        return self.value >= X_ROTATION.value


comptime X_POSITION = BvhChannel(0)
comptime Y_POSITION = BvhChannel(1)
comptime Z_POSITION = BvhChannel(2)
comptime X_ROTATION = BvhChannel(3)
comptime Y_ROTATION = BvhChannel(4)
comptime Z_ROTATION = BvhChannel(5)


def bvh_channel(name: String) raises -> BvhChannel:
    """Return the channel a `CHANNELS` line names.

    Args:
        name: `Xposition`, `Yposition`, `Zposition`, `Xrotation`,
            `Yrotation` or `Zrotation`.

    Returns:
        The channel.

    Raises:
        Error: If the name is none of the six.
    """
    var names: List[String] = [
        "Xposition",
        "Yposition",
        "Zposition",
        "Xrotation",
        "Yrotation",
        "Zrotation",
    ]
    for index in range(len(names)):  # pragma: no branch
        if names[index] == name:
            return BvhChannel(index)
    raise Error("BVH: a channel that is not known: `" + name + "`")


def axis_rotation(channel: BvhChannel, degrees: Float64) raises -> Rotation:
    """Return a turn about one axis, three.js's `setFromAxisAngle`.

    Args:
        channel: `X_ROTATION`, `Y_ROTATION` or `Z_ROTATION`.
        degrees: The angle.

    Returns:
        The rotation.

    Raises:
        Error: If the channel is not a rotation.
    """
    var turns = channel.is_valid() and channel.is_rotation()
    if not turns:
        raise Error("BVH: a rotation about a channel that is not one")
    var half = degrees * pi / 180 / 2
    var s = sin(half)
    var out = Rotation(0, 0, 0, cos(half))
    out[channel.value - X_ROTATION.value] = s
    return out


def multiply_rotations(a: Rotation, b: Rotation) -> Rotation:
    """Return `a` times `b`, three.js's `multiplyQuaternions`.

    Args:
        a: The rotation on the left.
        b: The rotation on the right.

    Returns:
        The product.
    """
    return Rotation(
        a[0] * b[3] + a[3] * b[0] + a[1] * b[2] - a[2] * b[1],
        a[1] * b[3] + a[3] * b[1] + a[2] * b[0] - a[0] * b[2],
        a[2] * b[3] + a[3] * b[2] + a[0] * b[1] - a[1] * b[0],
        a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    )


struct BvhJoint(Copyable, Movable):
    """One joint or end site of the hierarchy, and its frames."""

    var name: String
    var is_end_site: Bool
    # Which joint it is under, or -1 for the root.
    var parent: Int
    var offset: SIMD[DType.float64, 4]
    var channels: List[BvhChannel]
    # One position and one rotation a frame.
    var positions: List[SIMD[DType.float64, 4]]
    var rotations: List[Rotation]

    def __init__(out self, var name: String, is_end_site: Bool, parent: Int):
        """Start a joint with no offset, channels or frames.

        Args:
            name: Its name; `ENDSITE` for an end site, as in three.js.
            is_end_site: Whether it is an end site.
            parent: The joint it is under, or -1.
        """
        self.name = name^
        self.is_end_site = is_end_site
        self.parent = parent
        self.offset = SIMD[DType.float64, 4](0)
        self.channels = List[BvhChannel]()
        self.positions = List[SIMD[DType.float64, 4]]()
        self.rotations = List[Rotation]()


struct _Lines:
    """The lines of a file, read one by one, three.js's `nextLine`."""

    var lines: List[String]
    var at: Int

    def __init__(out self, text: String):
        """Split a text on line breaks."""
        self.lines = List[String]()
        for line in text.replace("\r", "\n").split("\n"):  # pragma: no branch
            self.lines.append(String(line))
        self.at = 0

    def next(mut self) raises -> String:
        """Return the next line that is not empty, trimmed.

        Raises:
            Error: If the file ends first.
        """
        while self.at < len(self.lines):
            var line = String(self.lines[self.at].strip())
            self.at += 1
            if line.byte_length() > 0:
                return line^
        raise Error("BVH: the file ends early")

    def tokens(mut self) raises -> List[String]:
        """Return the next line split on white space.

        Raises:
            Error: If the file ends first.
        """
        var out = List[String]()
        for token in self.next().split():  # pragma: no branch
            out.append(String(token))
        return out^


def _number(text: String, what: String) raises -> Float64:
    """Return `parseFloat(text)`, refusing NaN."""
    var value = js_parse_float(text)
    if isnan(value):
        raise Error("BVH: " + what + " is not a number: `" + text + "`")
    return value


def _read_joint(
    mut lines: _Lines,
    first: List[String],
    parent: Int,
    mut joints: List[BvhJoint],
    depth: Int,
) raises:
    """Read one joint and what is under it, three.js's `readNode`.

    Raises:
        Error: If a keyword is missing, a number is not one, a channel is
            not known, or the file ends early.
    """
    if depth > 256:
        raise Error("BVH: the hierarchy is nested too deep")
    if len(first) < 2:
        raise Error("BVH: a joint needs a type and a name")
    var end_site = first[0].upper() == "END" and first[1].upper() == "SITE"
    var name = "ENDSITE" if end_site else first[1]
    var index = len(joints)
    joints.append(BvhJoint(name, end_site, parent))
    if lines.next() != "{":
        raise Error("BVH: expected `{` after `" + first[0] + "`")
    var offset = lines.tokens()
    if offset[0] != "OFFSET":
        raise Error("BVH: expected OFFSET but got `" + offset[0] + "`")
    if len(offset) != 4:
        raise Error("BVH: OFFSET needs three values")
    for axis in range(3):  # pragma: no branch
        joints[index].offset[axis] = _number(offset[axis + 1], "an OFFSET")
    if not end_site:
        var channels = lines.tokens()
        if channels[0] != "CHANNELS":
            raise Error("BVH: expected CHANNELS")
        if len(channels) < 2:
            raise Error("BVH: CHANNELS needs a count")
        var count = js_parse_int(channels[1])
        var matches = count >= 0 and Int(count) == len(channels) - 2
        if not matches:
            raise Error("BVH: CHANNELS does not name as many as it counts")
        for name in channels[2:]:
            joints[index].channels.append(bvh_channel(String(name)))
    var line = lines.tokens()
    while line[0] != "}":
        if end_site:
            raise Error("BVH: an end site has no joints under it")
        _read_joint(lines, line, index, joints, depth + 1)
        line = lines.tokens()


def _read_frame(
    mut joints: List[BvhJoint], data: List[String], mut at: Int
) raises:
    """Read one frame's values into every joint, three.js's
    `readFrameData`.

    Raises:
        Error: If the line has too few values, or one is not a number.
    """
    for j in range(len(joints)):  # pragma: no branch
        if joints[j].is_end_site:
            continue
        var position = SIMD[DType.float64, 4](0)
        var rotation = Rotation(0, 0, 0, 1)
        for channel in joints[j].channels:
            if at >= len(data):
                raise Error("BVH: a frame has too few values")
            var value = _number(data[at], "a frame value")
            at += 1
            if channel.is_rotation():
                rotation = multiply_rotations(
                    rotation, axis_rotation(channel, value)
                )
            else:
                position[channel.value] = value
        joints[j].positions.append(position)
        joints[j].rotations.append(rotation)


struct BvhModel(Movable):
    """What a BVH file holds, three.js's `{ skeleton, clip }`."""

    # Every joint and end site, in file order, with its frames.
    var joints: List[BvhJoint]
    # One scene node for each joint, in the same order.
    var nodes: List[NodeId]
    # The nodes as bones, each with the identity as its inverse bind.
    var skeleton: Skeleton
    # How many frames the file has, and how long each takes.
    var frame_count: Int
    var frame_time: Duration
    # The animation, or none; see the module docstring.
    var clip: Optional[AnimationClip]

    def __init__(
        out self,
        var joints: List[BvhJoint],
        var nodes: List[NodeId],
        var skeleton: Skeleton,
        frame_count: Int,
        frame_time: Duration,
        var clip: Optional[AnimationClip],
    ):
        """Hold what a file gave.

        Args:
            joints: The joints.
            nodes: Their nodes.
            skeleton: The skeleton.
            frame_count: The frames.
            frame_time: The time a frame takes.
            clip: The animation.
        """
        self.joints = joints^
        self.nodes = nodes^
        self.skeleton = skeleton^
        self.frame_count = frame_count
        self.frame_time = frame_time
        self.clip = clip^


def parse_bvh(
    text: String,
    mut scene: Scene,
    parent: NodeId = NO_PARENT,
    animate_positions: Bool = True,
    animate_rotations: Bool = True,
) raises -> BvhModel:
    """Read a BVH file's text, three.js's `BVHLoader.parse`.

    Args:
        text: The file.
        scene: The scene the joints' nodes go into.
        parent: The node the root joint goes under.
        animate_positions: Whether the clip has position tracks,
            three.js's `animateBonePositions`.
        animate_rotations: Whether it has rotation tracks, three.js's
            `animateBoneRotations`.

    Returns:
        The joints, their nodes, the skeleton and the clip.

    Raises:
        Error: If a keyword is missing, a count or a value is not a
            number, a channel is not known, the file ends early, or the
            scene refuses a node.
    """
    var lines = _Lines(text)
    if lines.next() != "HIERARCHY":
        raise Error("BVH: HIERARCHY expected")
    var joints = List[BvhJoint]()
    _read_joint(lines, lines.tokens(), -1, joints, 0)
    if lines.next() != "MOTION":
        raise Error("BVH: MOTION expected")
    var frames_line = lines.tokens()
    var frames = js_parse_int(frames_line[1]) if len(frames_line) > 1 else (
        js_parse_int("")
    )
    if isnan(frames):
        raise Error("BVH: the number of frames is not a number")
    var time_line = lines.tokens()
    var time = js_parse_float(time_line[2]) if len(time_line) > 2 else (
        js_parse_float("")
    )
    if isnan(time):
        raise Error("BVH: the frame time is not a number")
    var frame_count = max(0, Int(frames))
    for _ in range(frame_count):
        var data = lines.tokens()
        var at = 0
        _read_frame(joints, data, at)

    var nodes = List[NodeId]()
    var bones = List[Bone]()
    for j in range(len(joints)):  # pragma: no branch
        var node = Object3D()
        node.name = joints[j].name
        ref offset = joints[j].offset
        node.set_position(
            Float32(offset[0]), Float32(offset[1]), Float32(offset[2])
        )
        var above = parent if joints[j].parent < 0 else nodes[joints[j].parent]
        var id = scene.attach(node^, above)
        nodes.append(id)
        bones.append(Bone(id, Matrix4()))

    var clip: Optional[AnimationClip] = None
    var lasts = frame_count > 1 and time > 0
    var tracks = List[KeyframeTrack]()
    if lasts:
        var times = List[Duration]()
        for i in range(frame_count):  # pragma: no branch
            times.append(Duration(Float32(Float64(i) * time), SECOND))
        for j in range(len(joints)):  # pragma: no branch
            ref joint = joints[j]
            if joint.is_end_site:
                continue
            var positions = List[Float32]()
            var rotations = List[Float32]()
            for f in range(frame_count):  # pragma: no branch
                for axis in range(3):  # pragma: no branch
                    positions.append(
                        Float32(joint.positions[f][axis] + joint.offset[axis])
                    )
                for axis in range(4):  # pragma: no branch
                    rotations.append(Float32(joint.rotations[f][axis]))
            if animate_positions:
                tracks.append(
                    KeyframeTrack(nodes[j], POSITION, times, positions^)
                )
            if animate_rotations:
                tracks.append(
                    KeyframeTrack(nodes[j], QUATERNION, times, rotations^)
                )
    if len(tracks) > 0:
        clip = AnimationClip("animation", tracks^)
    return BvhModel(
        joints^,
        nodes^,
        Skeleton(bones^),
        frame_count,
        Duration(Float32(time), SECOND),
        clip^,
    )


def read_bvh(
    path: String,
    mut scene: Scene,
    parent: NodeId = NO_PARENT,
    animate_positions: Bool = True,
    animate_rotations: Bool = True,
) raises -> BvhModel:
    """Read a BVH file.

    Args:
        path: The file.
        scene: The scene the joints' nodes go into.
        parent: The node the root joint goes under.
        animate_positions: Whether the clip has position tracks.
        animate_rotations: Whether it has rotation tracks.

    Returns:
        What `parse_bvh` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_bvh`
            refuses.
    """
    return parse_bvh(
        Path(path).read_text(),
        scene,
        parent,
        animate_positions,
        animate_rotations,
    )
