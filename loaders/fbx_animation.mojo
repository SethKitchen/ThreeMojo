# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An FBX file's animation stacks, read into `AnimationClip`s: three.js's
`FBXLoader` `AnimationParser`.

**What an FBX animation is.** An `AnimationStack` is one clip. Its first
`AnimationLayer` holds `AnimationCurveNode`s, and each curve node drives
one property of one object: `T`, `R` or `S` of a `Model`, or the
`DeformPercent` of a blend shape channel. Each curve node holds up to
three `AnimationCurve`s, one per axis, `d|X`, `d|Y` and `d|Z`, or one
`d|DeformPercent`. A curve is a list of key times, in FBX ticks of
1/46186158000 second, and a list of values.

**What maps to what.** A `T` curve node becomes a `POSITION` track and an
`S` curve node a `SCALE` track. The keys are every time any axis has a
key, and an axis with no key at a time keeps its last value, starting
from the model's own. An `R` curve node becomes a `QUATERNION` track: the
three angles, in degrees, turn in the model's rotation order, and the
model's pre-rotation turns first and its post-rotation is undone last,
as three.js's `generateRotationTrack` turns them. A `DeformPercent` curve
becomes a morph influence track on every mesh of the model, its values
divided by one hundred. Every track is `LINEAR`: three.js reads no key
tangent and no key interpolation.

**Large turns.** Where an angle changes by 180 degrees or more between two
keys, three.js's `interpolateRotations` puts keys between them, a
`slerp` apart, and does not keep the second key. This port does the same.

**Where this differs from three.js.** A stack's first layer is read and
the rest are not, as in three.js. Then:

- three.js puts the first key between two keys at the time of the key
  before, a second time. This port does not keep a key at a time that
  does not rise, and the value is the same rotation.
- three.js makes a rotation track of one key and one number when an `R`
  curve node has no curve for an axis. That is not a rotation, and this
  port makes no track.
- A stack that makes no track is not a clip here. three.js makes a clip
  of no length.
- three.js finds a track's node, and the mesh of a morph track, by its
  sanitized name. This port uses the model the curve node is connected
  to, so two models of one name each get their own tracks.
- A morph track names its blend shape channel, where three.js names the
  channel's name. Two channels of one name each get their own target.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import (
    POSITION,
    QUATERNION,
    SCALE,
    KeyframeTrack,
    TrackKind,
    TrackTarget,
    node_target,
)
from core.object3d import NodeId
from loaders.fbx_tree import NO_FBX_NODE, FbxDocument, object_name
from math.euler import ZYX, Euler, EulerOrder
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import isnan, pi
from units.si import RADIAN, SECOND, Angle, Duration

# How many FBX ticks make one second: three.js's
# `convertFBXTimeToSeconds`.
comptime FBX_TICKS_PER_SECOND = Float64(46186158000)
# The largest id a JavaScript object orders as an array index: three.js
# meets the stacks in that order, which puts such ids first and in
# numeric order.
comptime _LARGEST_INDEX = 4294967294


struct FbxAnimatedModel(Copyable, Movable):
    """What a clip can drive of one FBX model: its node, the transform its
    tracks start from, and the meshes its morph tracks drive."""

    var node: NodeId
    # The model's position and scale as placed, which an axis with no key
    # keeps.
    var position: Vector3
    var scale: Vector3
    # The order its `Lcl Rotation` turns in, and its pre-rotation and
    # post-rotation, in degrees.
    var order: EulerOrder
    var pre_rotation: Vector3
    var post_rotation: Vector3
    # One target per mesh or skinned mesh of the model, its slot zero. A
    # morph track takes the kind and the index, and the channel's slot.
    var morphs: List[TrackTarget]

    def __init__(
        out self,
        node: NodeId,
        position: Vector3,
        scale: Vector3,
        order: EulerOrder,
        pre_rotation: Vector3,
        post_rotation: Vector3,
    ):
        """Describe a model with no meshes yet.

        Args:
            node: The model's scene node.
            position: Its position as placed.
            scale: Its scale as placed.
            order: The order its rotation turns in.
            pre_rotation: Its `PreRotation`, in degrees.
            post_rotation: Its `PostRotation`, in degrees.
        """
        self.node = node
        self.position = position
        self.scale = scale
        self.order = order
        self.pre_rotation = pre_rotation
        self.post_rotation = post_rotation
        self.morphs = List[TrackTarget]()


@fieldwise_init
struct _Link(Copyable, Movable):
    """One end of a connection: the other object's id and the connection's
    name, or empty."""

    var id: Int
    var relation: String


@fieldwise_init
struct _Curve(Copyable, Movable):
    """One `AnimationCurve`: its key times in seconds and its values."""

    var times: List[Float64]
    var values: List[Float64]


struct _CurveNode(Copyable, Movable):
    """One `AnimationCurveNode`: what it drives, and its curves by axis:
    `x`, `y`, `z` or `morph`."""

    var attr: String
    var curves: Dict[String, _Curve]

    def __init__(out self, attr: String):
        self.attr = attr
        self.curves = Dict[String, _Curve]()

    def moves(self) -> Bool:
        """Return True if it has a curve for an axis."""
        return "x" in self.curves or "y" in self.curves or "z" in self.curves

    def turns(self) -> Bool:
        """Return True if it has a curve for every axis, which three.js's
        `generateRotationTrack` needs."""
        return "x" in self.curves and "y" in self.curves and "z" in self.curves


@fieldwise_init
struct _Entry(Copyable, Movable):
    """One curve node of a layer, and the model or the blend shape channel
    it drives."""

    var curve_node: Int
    var model: Int
    # The blend shape channel of a `DeformPercent` curve node, or -1.
    var channel: Int


def _connections(
    document: FbxDocument,
) raises -> Tuple[Dict[Int, List[_Link]], Dict[Int, List[_Link]]]:
    """Return each object's parents and children, in file order, as
    three.js's `parseConnections` joins them."""
    var parents = Dict[Int, List[_Link]]()
    var children = Dict[Int, List[_Link]]()
    var connections = document.child(document.root(), "Connections")
    if connections == NO_FBX_NODE:
        return (parents^, children^)
    for link in document.children_named(connections, "C"):
        var child = document.integer(link, 1)
        var parent = document.integer(link, 2)
        var relation = String()
        if document.property_count(link) > 3:
            relation = document.string(link, 3)
        if child not in parents:
            parents[child] = List[_Link]()
        parents[child].append(_Link(parent, relation))
        if parent not in children:
            children[parent] = List[_Link]()
        children[parent].append(_Link(child, relation))
    return (parents^, children^)


def _links(table: Dict[Int, List[_Link]], id: Int) raises -> List[_Link]:
    """Return an object's connections one way, or none."""
    if id not in table:
        return List[_Link]()
    return table[id].copy()


def _named_parent(parents: Dict[Int, List[_Link]], id: Int) raises -> Int:
    """Return the first parent a curve node is connected to by a named
    connection: the object and property it drives.

    Raises:
        Error: If it has none, where three.js reads past the end.
    """
    # A curve node read here is a child of its layer: the loop always
    # runs.
    for link in _links(parents, id):  # pragma: no branch
        if link.relation != "":
            return link.id
    raise Error("FBX: an animation curve node drives nothing")


def _first_parent(parents: Dict[Int, List[_Link]], id: Int) raises -> Int:
    """Return an object's first parent.

    Raises:
        Error: If it has none, where three.js reads past the end.
    """
    var found = _links(parents, id)
    if len(found) == 0:
        raise Error("FBX: a blend shape channel is not connected to a model")
    return found[0].id


def js_key_order(ids: List[Int]) -> List[Int]:
    """Return places in a list of ids in the order a JavaScript object
    meets them as keys: the ids from zero to 2^32 - 2 first, in numeric
    order, then the rest in the order given.

    three.js keeps the FBX objects in objects keyed by id, so this is the
    order it meets them in.

    Args:
        ids: The ids, in file order.

    Returns:
        The places in `ids`, in the order met.
    """
    var small = List[Int]()
    var rest = List[Int]()
    for place in range(len(ids)):
        if ids[place] >= 0 and ids[place] <= _LARGEST_INDEX:
            # Insertion sort: a file has few stacks.
            var at = len(small)
            while at > 0 and ids[small[at - 1]] > ids[place]:
                at -= 1
            small.insert(at, place)
        else:
            rest.append(place)
    small.extend(rest^)
    return small^


def read_fbx_animations(
    document: FbxDocument,
    objects: Int,
    models: Dict[Int, FbxAnimatedModel],
    morph_slots: Dict[Int, Int],
) raises -> List[AnimationClip]:
    """Return one clip per animation stack that makes a track, as
    three.js's `AnimationParser.parse` builds them.

    Args:
        document: The file's tree.
        objects: Its `Objects` node.
        models: Each placed model by id.
        morph_slots: Each blend shape channel's morph target, by the
            channel's id. A channel that is not here drives nothing.

    Returns:
        The clips, in the order three.js meets the stacks.

    Raises:
        Error: If a curve has no key times or values, or not as many of
            each; a curve drives a curve node that is not read; a curve
            node drives nothing; a stack has no layer; a blend shape
            channel is not connected to a model; or a track refuses its
            keys.
    """
    var clips = List[AnimationClip]()
    if len(document.children_named(objects, "AnimationCurve")) == 0:
        return clips^
    var joined = _connections(document)
    ref parents = joined[0]
    ref children = joined[1]
    var nodes = Dict[Int, _CurveNode]()
    for node in document.children_named(objects, "AnimationCurveNode"):
        var attr = object_name(document.string(node, 1), document.format)
        # three.js's `/S|R|T|DeformPercent/`.
        if _is_read(attr):
            nodes[document.integer(node, 0)] = _CurveNode(attr)
    # There is a curve, or the function returned above.
    for node in document.children_named(  # pragma: no branch
        objects, "AnimationCurve"
    ):
        var id = document.integer(node, 0)
        var curve = _read_curve(document, node)
        var found = _links(parents, id)
        if len(found) == 0:
            continue
        var owner = found[0].id
        var relation = found[0].relation
        var axis: String
        if relation.find("X") >= 0:
            axis = "x"
        elif relation.find("Y") >= 0:
            axis = "y"
        elif relation.find("Z") >= 0:
            axis = "z"
        elif relation.find("DeformPercent") >= 0 and owner in nodes:
            axis = "morph"
        else:
            continue
        if owner not in nodes:
            raise Error("FBX: an animation curve drives no curve node")
        nodes[owner].curves[axis] = curve^
    var layers = Dict[Int, List[_Entry]]()
    for layer in document.children_named(objects, "AnimationLayer"):
        var id = document.integer(layer, 0)
        var entries = List[_Entry]()
        for link in _links(children, id):
            if link.id not in nodes:
                continue
            if nodes[link.id].moves():
                var model = _named_parent(parents, link.id)
                if model in models:
                    entries.append(_Entry(link.id, model, -1))
            elif "morph" in nodes[link.id].curves:
                # The channel, its blend shape, its geometry, its model.
                var channel = _named_parent(parents, link.id)
                var morpher = _first_parent(parents, channel)
                var geometry = _first_parent(parents, morpher)
                entries.append(
                    _Entry(link.id, _first_parent(parents, geometry), channel)
                )
        layers[id] = entries^
    var stacks = document.children_named(objects, "AnimationStack")
    var ids = List[Int]()
    for stack in stacks:
        ids.append(document.integer(stack, 0))
    for place in js_key_order(ids):
        var below = _links(children, ids[place])
        if not _has_layer(below, layers):
            raise Error("FBX: an animation stack has no layer")
        var tracks = List[KeyframeTrack]()
        for entry in layers[below[0].id]:
            _entry_tracks(entry, nodes, models, morph_slots, tracks)
        if len(tracks) == 0:
            continue
        clips.append(
            AnimationClip(
                object_name(document.string(stacks[place], 1), document.format),
                tracks^,
            )
        )
    return clips^


def _is_read(attr: String) -> Bool:
    """Return True for a curve node three.js reads: one whose name matches
    `/S|R|T|DeformPercent/`."""
    return (
        attr.find("S") >= 0
        or attr.find("R") >= 0
        or attr.find("T") >= 0
        or attr.find("DeformPercent") >= 0
    )


def _has_layer(below: List[_Link], layers: Dict[Int, List[_Entry]]) -> Bool:
    """Return True if a stack's first child is a layer."""
    return len(below) > 0 and below[0].id in layers


def _drives(
    entry: _Entry,
    models: Dict[Int, FbxAnimatedModel],
    morph_slots: Dict[Int, Int],
) -> Bool:
    """Return True if a morph curve's model is placed and its channel is a
    morph target."""
    return entry.model in models and entry.channel in morph_slots


def _all_keyed(x: _Curve, y: _Curve, z: _Curve) -> Bool:
    """Return True if each of three curves has a key."""
    return len(x.times) > 0 and len(y.times) > 0 and len(z.times) > 0


def _all_reach(key: Int, y: _Curve, z: _Curve) -> Bool:
    """Return True if the y and z curves have a value at a key of x."""
    return key < len(y.values) and key < len(z.values)


def _numbers_all(before: List[Float64], now: List[Float64]) -> Bool:
    """Return True if six angles are all numbers, as three.js's `isNaN`
    test asks."""
    return not (
        isnan(before[0])
        or isnan(before[1])
        or isnan(before[2])
        or isnan(now[0])
        or isnan(now[1])
        or isnan(now[2])
    )


def _flips(key: Int, previous: Quaternion, turned: Quaternion) -> Bool:
    """Return True if a key's rotation points away from the one before, so
    that its negation, the same rotation, is kept: three.js's unroll."""
    return key > 0 and previous.dot(turned) < 0


def _read_curve(document: FbxDocument, node: Int) raises -> _Curve:
    """Read one curve's key times, in seconds, and its values.

    Raises:
        Error: If it has no `KeyTime` or no `KeyValueFloat`, or not as
            many of each.
    """
    var times = document.child(node, "KeyTime")
    var values = document.child(node, "KeyValueFloat")
    if times == NO_FBX_NODE or values == NO_FBX_NODE:
        raise Error("FBX: an animation curve needs KeyTime and KeyValueFloat")
    var seconds = List[Float64]()
    for tick in document.integers(times):
        seconds.append(Float64(tick) / FBX_TICKS_PER_SECOND)
    var numbers = document.numbers(values)
    if len(numbers) != len(seconds):
        raise Error("FBX: an animation curve needs one value per key time")
    return _Curve(seconds^, numbers^)


def _entry_tracks(
    entry: _Entry,
    nodes: Dict[Int, _CurveNode],
    models: Dict[Int, FbxAnimatedModel],
    morph_slots: Dict[Int, Int],
    mut tracks: List[KeyframeTrack],
) raises:
    """Add the tracks one curve node of a layer makes, as three.js's
    `generateTracks` makes them."""
    ref node = nodes[entry.curve_node]
    if entry.channel >= 0:
        # A model with no mesh, or a channel whose shape was not read,
        # has no influence to drive.
        if not _drives(entry, models, morph_slots):
            return
        ref curve = node.curves["morph"]
        var times = _durations(curve.times)
        var values = List[Float32]()
        for value in curve.values:
            values.append(Float32(value / 100))
        var slot = morph_slots[entry.channel]
        for target in models[entry.model].morphs:
            tracks.append(
                KeyframeTrack(
                    TrackTarget(target.kind, target.index, slot),
                    times,
                    values.copy(),
                )
            )
        return
    ref model = models[entry.model]
    if node.attr == "T":
        tracks.append(_vector_track(model.node, POSITION, node, model.position))
    elif node.attr == "S":
        tracks.append(_vector_track(model.node, SCALE, node, model.scale))
    elif node.attr == "R":
        if node.turns():
            tracks.append(_rotation_track(model, node))


def _durations(seconds: List[Float64]) -> List[Duration]:
    """Return times in seconds as durations."""
    var out = List[Duration]()
    for at in seconds:
        out.append(Duration(Float32(at), SECOND))
    return out^


def _vector_track(
    node: NodeId, kind: TrackKind, curves: _CurveNode, initial: Vector3
) raises -> KeyframeTrack:
    """Return a position or scale track, as three.js's
    `generateVectorTrack` makes it: a key at every time any axis has one,
    and an axis with no key there keeping its last value."""
    var times = List[Float64]()
    for axis in ["x", "y", "z"]:  # pragma: no branch
        if axis in curves.curves:
            times.extend(curves.curves[axis].times.copy())
    sort(times)
    var unique = List[Float64]()
    for at in times:  # pragma: no branch
        if len(unique) == 0 or unique[len(unique) - 1] != at:
            unique.append(at)
    var last: List[Float64] = [
        Float64(initial.x),
        Float64(initial.y),
        Float64(initial.z),
    ]
    var values = List[Float32]()
    # A curve node with a curve has a key: the loop always runs.
    for at in unique:  # pragma: no branch
        var lane = 0
        for axis in ["x", "y", "z"]:  # pragma: no branch
            if axis in curves.curves:
                ref curve = curves.curves[axis]
                # The first key at the time, as `indexOf` finds it.
                for key in range(len(curve.times)):
                    if curve.times[key] == at:
                        last[lane] = curve.values[key]
                        break
            values.append(Float32(last[lane]))
            lane += 1
    return KeyframeTrack(node_target(node, kind), _durations(unique), values^)


def _radians(degrees: Float64) -> Angle:
    """Return an angle in degrees as three.js's `degToRad` turns it."""
    return Angle(Float32(degrees * pi / 180), RADIAN)


def _turn(
    x: Float64, y: Float64, z: Float64, order: EulerOrder
) raises -> Quaternion:
    """Return the rotation three angles in radians make in an order."""
    return Euler(
        Angle(Float32(x), RADIAN),
        Angle(Float32(y), RADIAN),
        Angle(Float32(z), RADIAN),
        order,
    ).to_quaternion()


def _rotation_track(
    model: FbxAnimatedModel, curves: _CurveNode
) raises -> KeyframeTrack:
    """Return a rotation track, as three.js's `generateRotationTrack`
    makes it from `interpolateRotations`."""
    ref x = curves.curves["x"]
    ref y = curves.curves["y"]
    ref z = curves.curves["z"]
    if not _all_keyed(x, y, z):
        raise Error("FBX: a rotation curve has no keys")
    var times: List[Float64] = [x.times[0]]
    var angles: List[Float64] = [
        x.values[0] * pi / 180,
        y.values[0] * pi / 180,
        z.values[0] * pi / 180,
    ]
    for key in range(1, len(x.values)):
        # three.js reads past the end of a shorter curve and skips the key
        # it cannot read, as it skips one that is not a number.
        if not _all_reach(key, y, z):
            continue
        var before: List[Float64] = [
            x.values[key - 1],
            y.values[key - 1],
            z.values[key - 1],
        ]
        var now: List[Float64] = [x.values[key], y.values[key], z.values[key]]
        if not _numbers_all(before, now):
            continue
        var span = max(
            abs(now[0] - before[0]),
            abs(now[1] - before[1]),
            abs(now[2] - before[2]),
        )
        if span < 180:
            times.append(x.times[key])
            for lane in range(3):  # pragma: no branch
                angles.append(now[lane] * pi / 180)
            continue
        var start = _turn(
            before[0] * pi / 180,
            before[1] * pi / 180,
            before[2] * pi / 180,
            model.order,
        )
        var end = _turn(
            now[0] * pi / 180, now[1] * pi / 180, now[2] * pi / 180, model.order
        )
        var steps = span / 180
        var from_time = x.times[key - 1]
        var length = x.times[key] - from_time
        var t = Float64(0)
        while t < 1:
            var at = from_time + t * length
            if at > times[len(times) - 1]:
                var between = Euler.from_quaternion(
                    start.slerp(end, Float32(t)), model.order
                )
                times.append(at)
                angles.append(Float64(between.x.value))
                angles.append(Float64(between.y.value))
                angles.append(Float64(between.z.value))
            t += 1 / steps
    var pre = Euler(
        _radians(Float64(model.pre_rotation.x)),
        _radians(Float64(model.pre_rotation.y)),
        _radians(Float64(model.pre_rotation.z)),
        ZYX,
    ).to_quaternion()
    var post = (
        Euler(
            _radians(Float64(model.post_rotation.x)),
            _radians(Float64(model.post_rotation.y)),
            _radians(Float64(model.post_rotation.z)),
            ZYX,
        )
        .to_quaternion()
        .conjugate()
    )
    var values = List[Float32]()
    var previous = Quaternion.identity()
    for key in range(len(times)):  # pragma: no branch
        var turned = _turn(
            angles[key * 3],
            angles[key * 3 + 1],
            angles[key * 3 + 2],
            model.order,
        )
        turned.premultiply(pre)
        turned.multiply(post)
        # Unroll: the same rotation on the side of the key before.
        if _flips(key, previous, turned):
            turned = Quaternion(-turned.x, -turned.y, -turned.z, -turned.w)
        values.append(turned.x)
        values.append(turned.y)
        values.append(turned.z)
        values.append(turned.w)
        previous = turned
    return KeyframeTrack(
        node_target(model.node, QUATERNION), _durations(times), values^
    )
