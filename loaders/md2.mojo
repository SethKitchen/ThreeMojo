# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Quake II MD2 models, from three.js `examples/jsm/loaders/MD2Loader.js`.

An MD2 file is a header of seventeen 32-bit values, texture coordinates,
triangles, and frames. Each frame is a scale, a translation, a name, and
one packed vertex for each vertex of the model: three bytes of position
and an index into a table of 162 normals. `parse_md2` reads it as
three.js does.

**The geometry.** One vertex for each corner of each triangle, with no
index: the first frame's position and normal, and the texture
coordinate the corner names, `v` turned upside down. Positions and
normals turn from z up to y up, as three.js turns them.

**The frames.** Each frame keeps its name and its positions and normals
in the same order. Each frame is also a morph target of the geometry,
named by the frame, whole and not relative, as three.js's
`morphAttributes` are.

**The animations.** three.js's `CreateClipsFromMorphTargetSequences`
groups frames by their name less its trailing digits: `run1` to `run6`
are the animation `run`. `animations` keeps each group's name and
frames, in JavaScript key order. `md2_clip` turns one into an
`AnimationClip` at ten frames a second, as three.js does: one track for
each frame that rises to one at its time and falls to zero at its
neighbors', with a last key at the end when the first frame's key is at
zero.

**Where this port differs.** `md2_clip` refuses an animation of one or
two frames, whose three.js tracks
have two keys at one time. Where three.js logs and returns nothing or
reads `undefined`, this refuses: a file that is not `IDP2` version 8, or
whose size is not the header's end; a file that ends inside a part; a
model with no frames; and an index past its vertices, its texture
coordinates or the normal table.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import KeyframeTrack, MeshIndex, morph_target
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
)
from loaders.three_mf import js_key_order
from std.memory import bitcast
from std.pathlib import Path
from units.si import SECOND, Duration

# three.js's `_normalData`: the 162 normals a vertex can name, z up.
comptime NORMAL_TABLE: List[Float32] = [
    -0.525731,
    0.000000,
    0.850651,
    -0.442863,
    0.238856,
    0.864188,
    -0.295242,
    0.000000,
    0.955423,
    -0.309017,
    0.500000,
    0.809017,
    -0.162460,
    0.262866,
    0.951056,
    0.000000,
    0.000000,
    1.000000,
    0.000000,
    0.850651,
    0.525731,
    -0.147621,
    0.716567,
    0.681718,
    0.147621,
    0.716567,
    0.681718,
    0.000000,
    0.525731,
    0.850651,
    0.309017,
    0.500000,
    0.809017,
    0.525731,
    0.000000,
    0.850651,
    0.295242,
    0.000000,
    0.955423,
    0.442863,
    0.238856,
    0.864188,
    0.162460,
    0.262866,
    0.951056,
    -0.681718,
    0.147621,
    0.716567,
    -0.809017,
    0.309017,
    0.500000,
    -0.587785,
    0.425325,
    0.688191,
    -0.850651,
    0.525731,
    0.000000,
    -0.864188,
    0.442863,
    0.238856,
    -0.716567,
    0.681718,
    0.147621,
    -0.688191,
    0.587785,
    0.425325,
    -0.500000,
    0.809017,
    0.309017,
    -0.238856,
    0.864188,
    0.442863,
    -0.425325,
    0.688191,
    0.587785,
    -0.716567,
    0.681718,
    -0.147621,
    -0.500000,
    0.809017,
    -0.309017,
    -0.525731,
    0.850651,
    0.000000,
    0.000000,
    0.850651,
    -0.525731,
    -0.238856,
    0.864188,
    -0.442863,
    0.000000,
    0.955423,
    -0.295242,
    -0.262866,
    0.951056,
    -0.162460,
    0.000000,
    1.000000,
    0.000000,
    0.000000,
    0.955423,
    0.295242,
    -0.262866,
    0.951056,
    0.162460,
    0.238856,
    0.864188,
    0.442863,
    0.262866,
    0.951056,
    0.162460,
    0.500000,
    0.809017,
    0.309017,
    0.238856,
    0.864188,
    -0.442863,
    0.262866,
    0.951056,
    -0.162460,
    0.500000,
    0.809017,
    -0.309017,
    0.850651,
    0.525731,
    0.000000,
    0.716567,
    0.681718,
    0.147621,
    0.716567,
    0.681718,
    -0.147621,
    0.525731,
    0.850651,
    0.000000,
    0.425325,
    0.688191,
    0.587785,
    0.864188,
    0.442863,
    0.238856,
    0.688191,
    0.587785,
    0.425325,
    0.809017,
    0.309017,
    0.500000,
    0.681718,
    0.147621,
    0.716567,
    0.587785,
    0.425325,
    0.688191,
    0.955423,
    0.295242,
    0.000000,
    1.000000,
    0.000000,
    0.000000,
    0.951056,
    0.162460,
    0.262866,
    0.850651,
    -0.525731,
    0.000000,
    0.955423,
    -0.295242,
    0.000000,
    0.864188,
    -0.442863,
    0.238856,
    0.951056,
    -0.162460,
    0.262866,
    0.809017,
    -0.309017,
    0.500000,
    0.681718,
    -0.147621,
    0.716567,
    0.850651,
    0.000000,
    0.525731,
    0.864188,
    0.442863,
    -0.238856,
    0.809017,
    0.309017,
    -0.500000,
    0.951056,
    0.162460,
    -0.262866,
    0.525731,
    0.000000,
    -0.850651,
    0.681718,
    0.147621,
    -0.716567,
    0.681718,
    -0.147621,
    -0.716567,
    0.850651,
    0.000000,
    -0.525731,
    0.809017,
    -0.309017,
    -0.500000,
    0.864188,
    -0.442863,
    -0.238856,
    0.951056,
    -0.162460,
    -0.262866,
    0.147621,
    0.716567,
    -0.681718,
    0.309017,
    0.500000,
    -0.809017,
    0.425325,
    0.688191,
    -0.587785,
    0.442863,
    0.238856,
    -0.864188,
    0.587785,
    0.425325,
    -0.688191,
    0.688191,
    0.587785,
    -0.425325,
    -0.147621,
    0.716567,
    -0.681718,
    -0.309017,
    0.500000,
    -0.809017,
    0.000000,
    0.525731,
    -0.850651,
    -0.525731,
    0.000000,
    -0.850651,
    -0.442863,
    0.238856,
    -0.864188,
    -0.295242,
    0.000000,
    -0.955423,
    -0.162460,
    0.262866,
    -0.951056,
    0.000000,
    0.000000,
    -1.000000,
    0.295242,
    0.000000,
    -0.955423,
    0.162460,
    0.262866,
    -0.951056,
    -0.442863,
    -0.238856,
    -0.864188,
    -0.309017,
    -0.500000,
    -0.809017,
    -0.162460,
    -0.262866,
    -0.951056,
    0.000000,
    -0.850651,
    -0.525731,
    -0.147621,
    -0.716567,
    -0.681718,
    0.147621,
    -0.716567,
    -0.681718,
    0.000000,
    -0.525731,
    -0.850651,
    0.309017,
    -0.500000,
    -0.809017,
    0.442863,
    -0.238856,
    -0.864188,
    0.162460,
    -0.262866,
    -0.951056,
    0.238856,
    -0.864188,
    -0.442863,
    0.500000,
    -0.809017,
    -0.309017,
    0.425325,
    -0.688191,
    -0.587785,
    0.716567,
    -0.681718,
    -0.147621,
    0.688191,
    -0.587785,
    -0.425325,
    0.587785,
    -0.425325,
    -0.688191,
    0.000000,
    -0.955423,
    -0.295242,
    0.000000,
    -1.000000,
    0.000000,
    0.262866,
    -0.951056,
    -0.162460,
    0.000000,
    -0.850651,
    0.525731,
    0.000000,
    -0.955423,
    0.295242,
    0.238856,
    -0.864188,
    0.442863,
    0.262866,
    -0.951056,
    0.162460,
    0.500000,
    -0.809017,
    0.309017,
    0.716567,
    -0.681718,
    0.147621,
    0.525731,
    -0.850651,
    0.000000,
    -0.238856,
    -0.864188,
    -0.442863,
    -0.500000,
    -0.809017,
    -0.309017,
    -0.262866,
    -0.951056,
    -0.162460,
    -0.850651,
    -0.525731,
    0.000000,
    -0.716567,
    -0.681718,
    -0.147621,
    -0.716567,
    -0.681718,
    0.147621,
    -0.525731,
    -0.850651,
    0.000000,
    -0.500000,
    -0.809017,
    0.309017,
    -0.238856,
    -0.864188,
    0.442863,
    -0.262866,
    -0.951056,
    0.162460,
    -0.864188,
    -0.442863,
    0.238856,
    -0.809017,
    -0.309017,
    0.500000,
    -0.688191,
    -0.587785,
    0.425325,
    -0.681718,
    -0.147621,
    0.716567,
    -0.442863,
    -0.238856,
    0.864188,
    -0.587785,
    -0.425325,
    0.688191,
    -0.309017,
    -0.500000,
    0.809017,
    -0.147621,
    -0.716567,
    0.681718,
    -0.425325,
    -0.688191,
    0.587785,
    -0.162460,
    -0.262866,
    0.951056,
    0.442863,
    -0.238856,
    0.864188,
    0.162460,
    -0.262866,
    0.951056,
    0.309017,
    -0.500000,
    0.809017,
    0.147621,
    -0.716567,
    0.681718,
    0.000000,
    -0.525731,
    0.850651,
    0.425325,
    -0.688191,
    0.587785,
    0.587785,
    -0.425325,
    0.688191,
    0.688191,
    -0.587785,
    0.425325,
    -0.955423,
    0.295242,
    0.000000,
    -0.951056,
    0.162460,
    0.262866,
    -1.000000,
    0.000000,
    0.000000,
    -0.850651,
    0.000000,
    0.525731,
    -0.955423,
    -0.295242,
    0.000000,
    -0.951056,
    -0.162460,
    0.262866,
    -0.864188,
    0.442863,
    -0.238856,
    -0.951056,
    0.162460,
    -0.262866,
    -0.809017,
    0.309017,
    -0.500000,
    -0.864188,
    -0.442863,
    -0.238856,
    -0.951056,
    -0.162460,
    -0.262866,
    -0.809017,
    -0.309017,
    -0.500000,
    -0.681718,
    0.147621,
    -0.716567,
    -0.681718,
    -0.147621,
    -0.716567,
    -0.850651,
    0.000000,
    -0.525731,
    -0.688191,
    0.587785,
    -0.425325,
    -0.587785,
    0.425325,
    -0.688191,
    -0.425325,
    0.688191,
    -0.587785,
    -0.425325,
    -0.688191,
    -0.587785,
    -0.587785,
    -0.425325,
    -0.688191,
    -0.688191,
    -0.587785,
    -0.425325,
]


struct Md2Frame(Copyable, Movable):
    """One frame: its name, and a position and a normal for each corner
    of each triangle, y up."""

    var name: String
    var positions: List[Float32]
    var normals: List[Float32]

    def __init__(out self, var name: String):
        """Start a frame with no corners.

        Args:
            name: The frame's name.
        """
        self.name = name^
        self.positions = List[Float32]()
        self.normals = List[Float32]()


struct Md2Animation(Copyable, Movable):
    """A run of frames that share a name less its trailing digits."""

    var name: String
    # Which frames, in file order.
    var frames: List[Int]

    def __init__(out self, var name: String):
        """Start an animation with no frames.

        Args:
            name: Its name.
        """
        self.name = name^
        self.frames = List[Int]()


struct Md2Model(Movable):
    """What `parse_md2` gives: the geometry, the frames and the
    animations."""

    var geometry: BufferGeometry
    var frames: List[Md2Frame]
    var animations: List[Md2Animation]

    def __init__(
        out self,
        var geometry: BufferGeometry,
        var frames: List[Md2Frame],
        var animations: List[Md2Animation],
    ):
        """Hold what a file gave.

        Args:
            geometry: The geometry.
            frames: The frames.
            animations: The animations.
        """
        self.geometry = geometry^
        self.frames = frames^
        self.animations = animations^


struct _Reader:
    """Reads little-endian values, refusing a read past the end."""

    var bytes: List[UInt8]

    def __init__(out self, var bytes: List[UInt8]):
        """Hold the file."""
        self.bytes = bytes^

    def unsigned(self, at: Int, size: Int) raises -> Int:
        """Return an unsigned value of `size` bytes.

        Raises:
            Error: If it runs past the end of the file.
        """
        var outside = at < 0 or at + size > len(self.bytes)
        if outside:
            raise Error(
                "MD2: the file ends inside a value, at byte " + String(at)
            )
        var value = 0
        for k in range(size):  # pragma: no branch
            value |= Int(self.bytes[at + k]) << (8 * k)
        return value

    def signed(self, at: Int, size: Int) raises -> Int:
        """Return a two's complement value of `size` bytes."""
        var value = self.unsigned(at, size)
        var half = 1 << (8 * size - 1)
        return value - 2 * half if value >= half else value

    def float(self, at: Int) raises -> Float32:
        """Return a 32-bit float."""
        return bitcast[DType.float32](UInt32(self.unsigned(at, 4)))


def _digit_before(bytes: Span[UInt8, _], end: Int) -> Bool:
    """Return True if the byte before `end` is a digit."""
    return end > 0 and bytes[end - 1] >= 48 and bytes[end - 1] <= 57


def md2_animation_name(frame: String) -> Optional[String]:
    """Return the animation a frame belongs to, three.js's pattern
    `^([\\w-]*?)([\\d]+)$`.

    Args:
        frame: The frame's name.

    Returns:
        The name less its trailing digits, when there are digits and the
        rest is letters, digits, `_` and `-`; none otherwise.
    """
    var bytes = frame.as_bytes()
    var end = len(bytes)
    while _digit_before(bytes, end):
        end -= 1
    if end == len(bytes):
        return None
    for k in range(end):
        var b = bytes[k]
        var word = (
            (b >= 48 and b <= 57)
            or (b >= 65 and b <= 90)
            or (b >= 97 and b <= 122)
            or b == 95
            or b == 45
        )
        if not word:
            return None
    return String(frame[byte=:end])


def parse_md2(bytes: List[UInt8]) raises -> Md2Model:
    """Read an MD2 file's bytes, three.js's `MD2Loader.parse`.

    Args:
        bytes: The whole file.

    Returns:
        The geometry, the frames and the animations.

    Raises:
        Error: For anything the module docstring lists.
    """
    var r = _Reader(bytes.copy())
    var header = List[Int]()
    for i in range(17):  # pragma: no branch
        header.append(r.signed(i * 4, 4))
    var ok = header[0] == 844121161 and header[1] == 8
    if not ok:
        raise Error("MD2: not a valid MD2 file")
    if header[16] != len(bytes):
        raise Error("MD2: the file's size is not its header's end")
    var skin_width = Float64(header[2])
    var skin_height = Float64(header[3])
    var num_vertices = header[6]
    var num_st = header[7]
    var num_tris = header[8]
    var num_frames = header[10]
    if num_frames < 1:
        raise Error("MD2: a model with no frames")

    var uvs = List[Float64]()
    var offset = header[12]
    for _ in range(num_st):
        var u = Float64(r.signed(offset, 2))
        var v = Float64(r.signed(offset + 2, 2))
        uvs.append(u / skin_width)
        uvs.append(1 - v / skin_height)
        offset += 4

    offset = header[13]
    var vertex_indices = List[Int]()
    var uv_indices = List[Int]()
    for _ in range(num_tris):
        for k in range(3):  # pragma: no branch
            var vertex = r.unsigned(offset + k * 2, 2)
            if vertex >= num_vertices:
                raise Error("MD2: a triangle names a vertex that is not there")
            vertex_indices.append(vertex)
        for k in range(3):  # pragma: no branch
            var uv = r.unsigned(offset + 6 + k * 2, 2)
            if uv >= num_st:
                raise Error(
                    "MD2: a triangle names a texture coordinate that is not"
                    " there"
                )
            uv_indices.append(uv)
        offset += 12

    var frames = List[Md2Frame]()
    offset = header[14]
    var table = materialize[NORMAL_TABLE]()
    # At least one frame, checked above: the loop always runs.
    for _ in range(num_frames):  # pragma: no branch
        var scale = SIMD[DType.float64, 4](0)
        var move = SIMD[DType.float64, 4](0)
        for k in range(3):  # pragma: no branch
            scale[k] = Float64(r.float(offset + k * 4))
            move[k] = Float64(r.float(offset + 12 + k * 4))
        offset += 24
        var name = String()
        for j in range(16):  # pragma: no branch
            var c = r.unsigned(offset + j, 1)
            if c == 0:
                break
            name += chr(c)
        offset += 16
        var vertices = List[Float32]()
        var normals = List[Float32]()
        for _ in range(num_vertices):
            var p = SIMD[DType.float64, 4](0)
            for k in range(3):  # pragma: no branch
                p[k] = Float64(r.unsigned(offset + k, 1)) * scale[k] + move[k]
            var n = r.unsigned(offset + 3, 1)
            if n >= 162:
                raise Error("MD2: a normal index past the table")
            offset += 4
            vertices.append(Float32(p[0]))
            vertices.append(Float32(p[2]))
            vertices.append(Float32(p[1]))
            normals.append(table[n * 3])
            normals.append(table[n * 3 + 2])
            normals.append(table[n * 3 + 1])
        var frame = Md2Frame(name^)
        for vertex in vertex_indices:
            for k in range(3):  # pragma: no branch
                frame.positions.append(vertices[vertex * 3 + k])
                frame.normals.append(normals[vertex * 3 + k])
        frames.append(frame^)

    var geometry = BufferGeometry()
    var uv_values = List[Float32]()
    for uv in uv_indices:
        uv_values.append(Float32(uvs[uv * 2]))
        uv_values.append(Float32(uvs[uv * 2 + 1]))
    geometry.set_attribute(
        String(POSITION), BufferAttribute(frames[0].positions.copy(), 3)
    )
    geometry.set_attribute(
        String(NORMAL), BufferAttribute(frames[0].normals.copy(), 3)
    )
    geometry.set_attribute(String(UV), BufferAttribute(uv_values^, 2))
    # At least one frame: the loop always runs.
    for frame in frames:  # pragma: no branch
        geometry.add_morph_target(
            BufferAttribute(frame.positions.copy(), 3),
            BufferAttribute(frame.normals.copy(), 3),
            name=frame.name,
        )
    geometry.morph_relative = False

    var names = List[String]()
    var groups = List[Md2Animation]()
    for index in range(len(frames)):  # pragma: no branch
        var animation = md2_animation_name(frames[index].name)
        if not Bool(animation):
            continue
        var name = animation.value()
        var slot = -1
        for k in range(len(names)):
            if names[k] == name:
                slot = k
        if slot < 0:
            names.append(name)
            groups.append(Md2Animation(name))
            slot = len(groups) - 1
        groups[slot].frames.append(index)
    var animations = List[Md2Animation]()
    for name in js_key_order(names):
        # Every name has its group: the loop always runs.
        for group in groups:  # pragma: no branch
            if group.name == name:
                animations.append(group.copy())
    return Md2Model(geometry^, frames^, animations^)


def md2_clip(
    model: Md2Model,
    animation: Int,
    mesh: MeshIndex,
    fps: Float64 = 10,
    loop: Bool = True,
) raises -> AnimationClip:
    """Return one animation as a clip of morph target tracks, three.js's
    `CreateFromMorphTargetSequence`.

    Args:
        model: The model.
        animation: Which of its animations.
        mesh: The mesh the tracks drive, which wears the model's geometry.
        fps: Frames a second; three.js's loader uses ten.
        loop: Whether each track gets a last key at the end when its
            first key is at zero, three.js's `! noLoop`.

    Returns:
        The clip, named as the animation.

    Raises:
        Error: If there is no such animation, it has fewer than three
            frames, or `fps` is not
            above zero.
    """
    var missing = animation < 0 or animation >= len(model.animations)
    if missing:
        raise Error("MD2: no animation at index " + String(animation))
    if not fps > 0:
        raise Error("MD2: frames a second must be above zero")
    ref sequence = model.animations[animation].frames
    var n = len(sequence)
    if n < 3:
        raise Error("MD2: an animation of fewer than three frames")
    var tracks = List[KeyframeTrack]()
    for i in range(n):  # pragma: no branch
        var keys: List[Int] = [(i + n - 1) % n, i, (i + 1) % n]
        var values: List[Float32] = [0, 1, 0]
        # three.js's `getKeyframeOrder` and `sortedArray`: the three keys
        # by time, and they are distinct when there are three frames or
        # more.
        for a in range(3):  # pragma: no branch
            for b in range(2 - a):  # pragma: no branch
                if keys[b] > keys[b + 1]:
                    keys.swap_elements(b, b + 1)
                    values.swap_elements(b, b + 1)
        var wraps = loop and keys[0] == 0
        if wraps:
            keys.append(n)
            values.append(values[0])
        var times = List[Duration]()
        for key in keys:  # pragma: no branch
            times.append(Duration(Float32(Float64(key) / fps), SECOND))
        tracks.append(
            KeyframeTrack(morph_target(mesh, sequence[i]), times, values^)
        )
    return AnimationClip(model.animations[animation].name, tracks^)


def read_md2(path: String) raises -> Md2Model:
    """Read an MD2 file.

    Args:
        path: The file.

    Returns:
        What `parse_md2` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_md2`
            refuses.
    """
    return parse_md2(Path(path).read_bytes())
