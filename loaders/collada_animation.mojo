# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A Collada file's animations and animation clips, read into
`AnimationClip`s: three.js's `ColladaLoader` `buildAnimation` and
`buildAnimationClip`.

**What a Collada animation is.** An `<animation>` of
`<library_animations>` holds sources, samplers and channels. A channel
names a sampler and a target, `node-id/sid`, the transform step of a node
it drives. A sampler names its `INPUT` source, the key times in seconds,
and its `OUTPUT` source, the values. An `<animation>` that holds other
animations is only a folder: its own channels are not read, as three.js
does not read them. An `<animation_clip>` of `<library_animation_clips>`
names the animations it plays and runs from `start` to `end`.

**What maps to what.** A channel on a `<matrix>` step makes a `POSITION`, a
`QUATERNION` and a `SCALE` track on the node, the matrix of each key
decomposed, as three.js's `createKeyframeTracks` makes them. A key is
every time any channel of the animation has on the node; a matrix entry
that a key does not give is interpolated between the keys that give it,
or held from the nearest one, or taken from the node's own matrix when no
key gives it, as three.js's `prepareAnimationData` fills it. A target of
`sid(i)(j)` gives entry `i + 4j` of the matrix, row by row, and a target
of `sid.member` or `sid` gives all sixteen. Every track is `LINEAR`: three.js
reads no interpolation source. Each clip makes one `AnimationClip`, as
long as `end - start`, or as long as its tracks when that is not above
zero. A file with animations and no clips makes one clip, `default`, of
every animation.

**Where this differs from three.js.** A channel on a `<translate>`, a
`<rotate>` or a `<scale>` step makes no track, as three.js warns and makes
none. Then:

- A clip that makes no track is not a clip here. three.js makes a clip of
  no length.
- three.js makes tracks on the node a channel names even when the scene
  does not reach it, where they drive nothing. This port makes none.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import (
    POSITION,
    QUATERNION,
    SCALE,
    KeyframeTrack,
    node_target,
)
from core.object3d import NodeId
from loaders.xml import NO_ELEMENT, XmlDocument
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import isfinite
from units.si import SECOND, Duration


@fieldwise_init
struct _Source(Copyable, Movable):
    """An animation `<source>`: its numbers and how many make one value."""

    var values: List[Float64]
    var stride: Int


struct _Key(Copyable, Movable):
    """One key of a node's matrix: its time, and the sixteen entries row
    by row, each given or not."""

    var time: Float64
    var values: List[Float64]
    var given: List[Bool]

    def __init__(out self, time: Float64):
        self.time = time
        self.values = List[Float64](length=16, fill=0)
        self.given = List[Bool](length=16, fill=False)


def _numbers(document: XmlDocument, element: Int) raises -> List[Float64]:
    """Return the numbers an element's text holds.

    Raises:
        Error: If one is not a finite number.
    """
    var out = List[Float64]()
    for piece in document.text(element).split():
        var field = String(piece)
        var value: Float64
        try:
            value = Float64(field)
        except:
            raise Error("Collada: not a number: " + field)
        if not isfinite(Float32(value)):
            raise Error("Collada: a number must be finite: " + field)
        out.append(value)
    return out^


def _whole(text: String) raises -> Int:
    """Return the whole number a text holds.

    Raises:
        Error: If it is not one.
    """
    try:
        return Int(text)
    except:
        raise Error("Collada: not a whole number: " + text)


def _reference(url: String) raises -> String:
    """Return the id a `#id` reference names.

    Raises:
        Error: If the reference does not begin with `#`.
    """
    if not url.startswith("#"):
        raise Error("Collada: a reference must be #id, not '" + url + "'")
    return String(url[byte=1:])


def _source(document: XmlDocument, element: Int) raises -> _Source:
    """Read a `<source>`'s numbers and its accessor's stride, three when
    it has none, as three.js's `parseSource` reads them.

    Raises:
        Error: If a number is malformed, or the stride is not a positive
            whole number.
    """
    var values = List[Float64]()
    var array = document.child(element, "float_array")
    if array != NO_ELEMENT:
        values = _numbers(document, array)
    var stride = 3
    var common = document.child(element, "technique_common")
    if common != NO_ELEMENT:
        var accessor = document.child(common, "accessor")
        if accessor != NO_ELEMENT:
            stride = _whole(document.attribute(accessor, "stride"))
    if stride < 1:
        raise Error("Collada: a source's stride must be positive")
    return _Source(values^, stride)


def _leaves(
    document: XmlDocument,
    element: Int,
    mut ids: List[String],
    mut elements: List[Int],
) raises:
    """Gather the animations that hold no other animation, in document
    order, as three.js's `parseAnimation` registers them."""
    var inner = document.children_named(element, "animation")
    if len(inner) == 0:
        ids.append(document.attribute(element, "id"))
        elements.append(element)
        return
    # `inner` is not empty here: the loop always runs.
    for child in inner:  # pragma: no branch
        _leaves(document, child, ids, elements)


def read_collada_animations(
    document: XmlDocument,
    nodes: Dict[String, Int],
    placed: Dict[Int, NodeId],
    matrices: Dict[Int, Matrix4],
) raises -> List[AnimationClip]:
    """Return the clips of a Collada document, as three.js's
    `setupAnimations` builds them.

    Args:
        document: The document.
        nodes: Every `<node>` element by `id`.
        placed: The scene node each placed `<node>` element became, where
            it was placed itself and not as a copy.
        matrices: Each placed element's own matrix.

    Returns:
        One clip per `<animation_clip>` that makes a track, or one clip,
        `default`, of every animation when the file has no clips and its
        animations make a track.

    Raises:
        Error: If a clip names no animation; a channel names no sampler, a
            sampler no source, or a target no node; a target has no `sid`
            or an array index outside the matrix; a key's matrix flattens
            an axis; or a track refuses its keys.
    """
    var clips = List[AnimationClip]()
    var ids = List[String]()
    var elements = List[Int]()
    var library = document.child(document.root(), "library_animations")
    if library != NO_ELEMENT:
        for animation in document.children_named(library, "animation"):
            _leaves(document, animation, ids, elements)
    var clip_library = document.child(
        document.root(), "library_animation_clips"
    )
    var listed = List[Int]()
    if clip_library != NO_ELEMENT:
        listed = document.children_named(clip_library, "animation_clip")
    if len(listed) == 0:
        var tracks = List[KeyframeTrack]()
        for element in elements:
            _animation_tracks(
                document, element, nodes, placed, matrices, tracks
            )
        if len(tracks) > 0:
            clips.append(AnimationClip("default", tracks^))
        return clips^
    # `listed` is not empty here: the loop always runs.
    for clip in listed:  # pragma: no branch
        var tracks = List[KeyframeTrack]()
        for instance in document.children_named(clip, "instance_animation"):
            var id = _reference(document.attribute(instance, "url"))
            var found = -1
            # An animation with no id cannot be named: three.js gives it a
            # random one.
            for at in range(len(ids)):
                if ids[at] == id:
                    found = at
                    break
            if id == "":
                found = -1
            if found < 0:
                raise Error("Collada: a clip names no animation: " + id)
            _animation_tracks(
                document, elements[found], nodes, placed, matrices, tracks
            )
        if len(tracks) == 0:
            continue
        var name = document.attribute(clip, "id")
        if name == "":
            name = "default"
        var start = _numbers_or_zero(document.attribute(clip, "start"))
        var end = _numbers_or_zero(document.attribute(clip, "end"))
        # three.js's `( end - start ) || - 1`: a length that is not above
        # zero is the tracks' own.
        var duration = Optional[Duration](None)
        if end - start > 0:
            duration = Duration(Float32(end - start), SECOND)
        clips.append(AnimationClip(name, tracks^, duration=duration))
    return clips^


def _numbers_or_zero(text: String) raises -> Float64:
    """Return the number a `start` or `end` holds, or zero for none.

    Raises:
        Error: If it is not a number.
    """
    var field = String(text.strip())
    if field == "":
        return 0
    try:
        return Float64(field)
    except:
        raise Error("Collada: not a number: " + field)


@fieldwise_init
struct _Channel(Copyable, Movable):
    """A `<channel>`: its target and its sampler's id."""

    var target: String
    var sampler: String


def _animation_tracks(
    document: XmlDocument,
    element: Int,
    nodes: Dict[String, Int],
    placed: Dict[Int, NodeId],
    matrices: Dict[Int, Matrix4],
    mut tracks: List[KeyframeTrack],
) raises:
    """Add the tracks one animation makes, as three.js's `buildAnimation`
    makes them: one set per channel, in the order the targets first
    appear, a later channel of one target replacing an earlier one."""
    var sources = Dict[String, _Source]()
    var samplers = Dict[String, Int]()
    var channels = List[_Channel]()
    for child in document.children(element):
        var name = document.name(child)
        var id = document.attribute(child, "id")
        if name == "source":
            sources[id] = _source(document, child)
        elif name == "sampler":
            samplers[id] = child
        elif name == "channel":
            var target = document.attribute(child, "target")
            var sampler = _reference(document.attribute(child, "source"))
            var replaced = False
            for at in range(len(channels)):
                if channels[at].target == target:
                    channels[at].sampler = sampler
                    replaced = True
            if not replaced:
                channels.append(_Channel(target, sampler))
    for channel in channels:
        if channel.sampler not in samplers:
            raise Error("Collada: a channel names no sampler")
        var input = String()
        var output = String()
        for put in document.children_named(samplers[channel.sampler], "input"):
            var semantic = document.attribute(put, "semantic")
            if semantic == "INPUT":
                input = _reference(document.attribute(put, "source"))
            elif semantic == "OUTPUT":
                output = _reference(document.attribute(put, "source"))
        if input not in sources or output not in sources:
            raise Error("Collada: a sampler names no source")
        _channel_tracks(
            document,
            channel.target,
            sources[input],
            sources[output],
            nodes,
            placed,
            matrices,
            tracks,
        )


def _channel_tracks(
    document: XmlDocument,
    target: String,
    input: _Source,
    output: _Source,
    nodes: Dict[String, Int],
    placed: Dict[Int, NodeId],
    matrices: Dict[Int, Matrix4],
    mut tracks: List[KeyframeTrack],
) raises:
    """Add the position, rotation and scale tracks one channel makes, as
    three.js's `buildAnimationChannel` and `createKeyframeTracks` make
    them."""
    var parts = target.split("/")
    if len(parts) < 2:
        raise Error("Collada: a channel target has no sid: " + target)
    var id = String(parts[0])
    var sid = String(parts[1])
    var indices = List[Int]()
    var array = sid.find("(") >= 0
    if sid.find(".") >= 0:
        # A member of the step: three.js reads the whole matrix.
        array = False
        var member = String(sid[byte = 0 : sid.find(".")])
        sid = member
    elif array:
        var pieces = List[String]()
        # A `sid` with `(` splits into two pieces at least: both loops run.
        for piece in sid.split("("):  # pragma: no branch
            pieces.append(String(piece))
        sid = pieces[0]
        for at in range(1, len(pieces)):  # pragma: no branch
            indices.append(_whole(pieces[at].replace(")", "")))
        if len(indices) < 2:
            raise Error("Collada: a matrix target needs two indices")
    if id not in nodes:
        raise Error("Collada: a channel names no node: " + id)
    var element = nodes[id]
    if element not in placed:
        return
    # The step the sid names: the last of that sid, as three.js's
    # `transforms` keeps it.
    var step = String()
    for child in document.children(element):
        var name = document.name(child)
        if _is_step(name) and document.attribute(child, "sid") == sid:
            step = name
    if step != "matrix":
        return
    var keys = List[_Key]()
    for at in range(len(input.values)):
        var time = input.values[at]
        var key = -1
        for known in range(len(keys)):
            if keys[known].time == time:
                key = known
        if key < 0:
            key = len(keys)
            keys.append(_Key(time))
        var start = at * output.stride
        if array:
            var entry = indices[0] + 4 * indices[1]
            if entry < 0 or entry > 15:
                raise Error("Collada: a matrix target outside the matrix")
            if start < len(output.values):
                keys[key].values[entry] = output.values[start]
                keys[key].given[entry] = True
        else:
            # A stride is one at least: the loop always runs.
            for lane in range(min(output.stride, 16)):  # pragma: no branch
                # three.js marks a value past the end of the output as
                # missing.
                if start + lane < len(output.values):
                    keys[key].values[lane] = output.values[start + lane]
                    keys[key].given[lane] = True
    if len(keys) == 0:
        return
    keys = _by_time(keys)
    ref own = matrices[element]
    for entry in range(16):  # pragma: no branch
        _fill(keys, entry, own.get(entry // 4, entry % 4))
    var times = List[Duration]()
    var positions = List[Float32]()
    var rotations = List[Float32]()
    var scales = List[Float32]()
    for key in keys:  # pragma: no branch
        var matrix = Matrix4()
        for entry in range(16):  # pragma: no branch
            matrix.put(entry // 4, entry % 4, Float32(key.values[entry]))
        var position = Vector3(0, 0, 0)
        var rotation = Quaternion.identity()
        var scale = Vector3(1, 1, 1)
        matrix.decompose(position, rotation, scale)
        times.append(Duration(Float32(key.time), SECOND))
        positions.extend([position.x, position.y, position.z])
        rotations.extend([rotation.x, rotation.y, rotation.z, rotation.w])
        scales.extend([scale.x, scale.y, scale.z])
    var node = placed[element]
    tracks.append(KeyframeTrack(node_target(node, POSITION), times, positions^))
    tracks.append(
        KeyframeTrack(node_target(node, QUATERNION), times, rotations^)
    )
    tracks.append(KeyframeTrack(node_target(node, SCALE), times, scales^))


def _is_step(name: String) -> Bool:
    """Return True for a transform step three.js records by its `sid`."""
    return (
        name == "matrix"
        or name == "translate"
        or name == "rotate"
        or name == "scale"
    )


def _by_time(keys: List[_Key]) -> List[_Key]:
    """Return keys sorted by time, equal times keeping their order, as
    JavaScript's stable sort keeps them."""
    var order = List[Int]()
    for at in range(len(keys)):  # pragma: no branch
        var place = len(order)
        for known in range(len(order)):
            if keys[order[known]].time > keys[at].time:
                place = known
                break
        order.insert(place, at)
    var out = List[_Key]()
    for at in order:  # pragma: no branch
        out.append(keys[at].copy())
    return out^


def _given_after(keys: List[_Key], entry: Int, at: Int) -> Int:
    """Return the first key after `at` that gives an entry, or the count
    of keys."""
    for ahead in range(at + 1, len(keys)):
        if keys[ahead].given[entry]:
            return ahead
    return len(keys)


def _fill(mut keys: List[_Key], entry: Int, own: Float32):
    """Fill one matrix entry of every key that does not give it, as
    three.js's `transformAnimationData` fills it: from the node's own
    matrix when no key gives it, and otherwise from the keys around it,
    interpolated in time, or held from the one there is."""
    var any = False
    for key in keys:  # pragma: no branch
        if key.given[entry]:
            any = True
    if not any:
        for at in range(len(keys)):  # pragma: no branch
            keys[at].values[entry] = Float64(own)
        return
    for at in range(len(keys)):  # pragma: no branch
        if keys[at].given[entry]:
            continue
        # Every key before this one gives the entry by now, as three.js's
        # `getPrev` finds the key it has just filled.
        var before = at - 1
        var after = _given_after(keys, entry, at)
        if before < 0:
            keys[at].values[entry] = keys[after].values[entry]
        elif after == len(keys):
            keys[at].values[entry] = keys[before].values[entry]
        else:
            # Two keys of one time are one key, so the two times differ.
            ref a = keys[before]
            ref b = keys[after]
            keys[at].values[entry] = (keys[at].time - a.time) * (
                b.values[entry] - a.values[entry]
            ) / (b.time - a.time) + a.values[entry]
        # A filled entry counts as given for the keys after it, as three.js
        # writes it in place before it looks at the next key.
        keys[at].given[entry] = True
