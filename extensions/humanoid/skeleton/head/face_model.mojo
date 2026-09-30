# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A morphable face model: a head learned from scans, shaped by weights.

A sculpted face reads as a doll's: its forms are too even, and nothing
in it comes from a real face. A morphable model is learned from many
scanned faces. It is a mean head plus a set of shape modes, each a
displacement of every vertex. An identity is a weighted sum of the
identity modes, and an expression a weighted sum of the expression
shapes on top:

    vertex = neutral + sum(identity[i] * mode[i]) + sum(weight[j] * shape[j])

The identity modes are principal components, scaled so each weight is
a standard normal: drawing every weight from one gives a plausible
face. The expressions follow Apple's ARKit blend shapes, with the left
and the right side apart.

The model is the ICT Face Model Light of USC's Institute for Creative
Technologies, MIT license. `tools/ict_face_model.py` converts its OBJ
files into `assets/face/ict_face.bin`, keeping the first sixty identity
modes. Its frame: meters, plus y up, plus z out of the face. See
THIRD-PARTY-NOTICES.md.

This is not a three.js port. See Extensions.

    var model = FaceModel(FACE_MODEL_PATH)
    var points = model.shape(model.no_identity(), model.no_expression())
    var face = model.part(points, FACE_AND_HEAD)
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from math.vector3 import Vector3
from std.math import min

# Where the converted model is kept, from the repository's root.
comptime FACE_MODEL_PATH = "assets/face/ict_face.bin"
comptime _VERSION = 4
# The header: the tag, the version and ten counts.
comptime HEADER = 48


@fieldwise_init
struct FacePart(ImplicitlyCopyable):
    """A run of the model's vertices that makes one part of the head.

    The type stops a bare integer at compile time. A run that is empty
    or starts below zero is still constructible, and the boundary that
    reads it refuses it.
    """

    var first: Int
    var end: Int

    def is_valid(self) -> Bool:
        """Return True if the run starts at zero or above and is not
        empty."""
        return self.first >= 0 and self.end > self.first


# The model's parts.
comptime FACE_AND_HEAD = FacePart(0, 11248)
comptime MOUTH_SOCKET = FacePart(11248, 13294)
comptime EYE_SOCKETS = FacePart(13294, 14062)
comptime GUMS_AND_TONGUE = FacePart(14062, 17039)
comptime TEETH = FacePart(17039, 21451)
comptime LEFT_EYEBALL = FacePart(21451, 23021)
comptime RIGHT_EYEBALL = FacePart(23021, 24591)
comptime TEAR_FILM = FacePart(24591, 24999)
comptime EYE_BLEND = FacePart(24999, 25047)
comptime EYE_OCCLUSION = FacePart(25047, 25351)
comptime EYELASHES = FacePart(25351, 26719)


def _need(bytes: List[UInt8], at: Int, count: Int) raises:
    """Raise unless `count` bytes follow `at`."""
    if at + count > len(bytes):
        raise Error("The face model ends early")


def _u32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian 32-bit integer at `at`."""
    return (
        Int(bytes[at])
        | (Int(bytes[at + 1]) << 8)
        | (Int(bytes[at + 2]) << 16)
        | (Int(bytes[at + 3]) << 24)
    )


def _prefix(header: List[UInt8], identities: Int) -> Int:
    """Return how many bytes after the header hold the mean head, its
    mesh and the first `identities` identity modes."""
    var vertices = _u32(header, 8)
    var drawn = _u32(header, 12)
    var shorts = (
        drawn
        + _u32(header, 16) * 3
        + _u32(header, 28) * 3
        + _u32(header, 32) * 2
        + _u32(header, 36)
        + _u32(header, 40)
        + _u32(header, 44) * 3
    )
    var modes = _u32(header, 20)
    if identities >= 0:
        modes = min(modes, identities)
    return _aligned(vertices * 12 + drawn * 8 + shorts * 2) + modes * _aligned(
        4 + vertices * 3
    )


def _aligned(at: Int) -> Int:
    """Return `at` rounded up to a multiple of four."""
    return (at + 3) // 4 * 4


def _shorts(bytes: List[UInt8], at: Int, count: Int) -> List[Int]:
    """Return `count` little-endian 16-bit integers from `at`, a
    multiple of two."""
    var values = List[Int](capacity=count)
    var words = bytes.unsafe_ptr().unsafe_bitcast[UInt16]()
    var first = at // 2
    for index in range(count):  # pragma: no branch
        values.append(Int(words[unsafe_offset=first + index]))
    return values^


def _floats(bytes: List[UInt8], at: Int, count: Int) -> List[Float32]:
    """Return `count` 32-bit floats from `at`, a multiple of four."""
    var values = List[Float32](capacity=count)
    var words = bytes.unsafe_ptr().unsafe_bitcast[Float32]()
    var first = at // 4
    for index in range(count):  # pragma: no branch
        values.append(words[unsafe_offset=first + index])
    return values^


struct FaceModel(Movable):
    """The mean head, its identity modes and its expression shapes."""

    var neutral: List[Vector3]
    # Each drawn vertex's position in `neutral`, and its texture
    # coordinates: a position on a seam of the texture is drawn twice.
    var position_of: List[Int]
    var uvs: List[Float32]
    # Three drawn vertices a triangle.
    var triangles: List[Int]
    # The skin, the face and the head: its triangles, three vertices
    # each; its edges, two each; and its holes, the mouth, the eyes and
    # the base of the neck, each a loop of vertices in the order its
    # triangles run its edges.
    var skin_triangles: List[Int]
    var skin_edges: List[Int]
    # The skin's coarse copy, over its own vertices, for distances.
    var coarse_triangles: List[Int]
    var hole_starts: List[Int]
    var hole_corners: List[Int]
    # The file, whose shape modes are read where they lie: each identity
    # mode's scale and its displacements, three signed bytes a vertex,
    # start at its offset.
    var bytes: List[UInt8]
    var identity_offsets: List[Int]
    var identity_scales: List[Float32]
    # Each expression's name, scale, and the offsets of the vertices it
    # moves and of their displacements.
    var expression_names: List[String]
    var expression_scales: List[Float32]
    var expression_counts: List[Int]
    var expression_vertices: List[Int]
    var expression_moves: List[Int]

    def __init__(
        out self, path: String, identities: Int = -1, expressions: Bool = True
    ) raises:
        """Read a converted model.

        The file holds the mean head and its mesh first, then the
        identity modes, then the expressions. Only as much of it is read
        as is asked for, so a head that needs no expressions loads in a
        few milliseconds.

        Args:
            path: The file `tools/ict_face_model.py` writes.
            identities: How many identity modes to read. All of them by
                default. More than the file holds reads all it holds.
            expressions: Whether to read the expressions. True by
                default.

        Raises:
            Error: If the file cannot be read, is not a face model, or is
                cut short.
        """
        with open(path, "r") as source:
            self.bytes = source.read_bytes(HEADER)
            if len(self.bytes) == HEADER:
                var wanted = -1
                if not expressions:
                    wanted = _prefix(self.bytes, identities)
                elif identities >= 0:
                    raise Error(
                        "A face model with its expressions reads every"
                        " identity mode"
                    )
                self.bytes.extend(source.read_bytes(wanted))
        if (
            len(self.bytes) < HEADER
            or self.bytes[0] != 73
            or self.bytes[1] != 67
            or self.bytes[2] != 84
            or self.bytes[3] != 70
        ):
            raise Error("Not a face model: " + path)
        if _u32(self.bytes, 4) != _VERSION:
            raise Error("A face model of another version: " + path)
        var vertices = _u32(self.bytes, 8)
        var drawn = _u32(self.bytes, 12)
        var triangle_count = _u32(self.bytes, 16)
        var modes = _u32(self.bytes, 20)
        var shapes = _u32(self.bytes, 24)
        if identities >= 0:
            modes = min(modes, identities)
        if not expressions:
            shapes = 0
        var skin = _u32(self.bytes, 28)
        var edges = _u32(self.bytes, 32)
        var holes = _u32(self.bytes, 36)
        var corners = _u32(self.bytes, 40)
        var coarse = _u32(self.bytes, 44)
        var at = HEADER
        var shorts = (
            drawn
            + triangle_count * 3
            + skin * 3
            + edges * 2
            + holes
            + corners
            + coarse * 3
        )
        _need(self.bytes, at, vertices * 12 + drawn * 8 + shorts * 2)
        var coordinates = _floats(self.bytes, at, vertices * 3)
        self.neutral = List[Vector3](capacity=vertices)
        for v in range(vertices):  # pragma: no branch
            self.neutral.append(
                Vector3(
                    coordinates[v * 3],
                    coordinates[v * 3 + 1],
                    coordinates[v * 3 + 2],
                )
            )
        at += vertices * 12
        self.uvs = _floats(self.bytes, at, drawn * 2)
        at += drawn * 8
        self.position_of = _shorts(self.bytes, at, drawn)
        at += drawn * 2
        self.triangles = _shorts(self.bytes, at, triangle_count * 3)
        at += triangle_count * 6
        self.skin_triangles = _shorts(self.bytes, at, skin * 3)
        at += skin * 6
        self.skin_edges = _shorts(self.bytes, at, edges * 2)
        at += edges * 4
        var lengths = _shorts(self.bytes, at, holes)
        at += holes * 2
        self.hole_corners = _shorts(self.bytes, at, corners)
        at += corners * 2
        self.coarse_triangles = _shorts(self.bytes, at, coarse * 3)
        at = _aligned(at + coarse * 6)
        self.hole_starts = [0]
        for length in lengths:  # pragma: no branch
            self.hole_starts.append(
                self.hole_starts[len(self.hole_starts) - 1] + length
            )
        if self.hole_starts[len(self.hole_starts) - 1] != corners:
            raise Error("A face model's holes miscount their corners")
        var mode = _aligned(4 + vertices * 3)
        _need(self.bytes, at, modes * mode)
        self.identity_offsets = List[Int](capacity=modes)
        self.identity_scales = List[Float32](capacity=modes)
        for _ in range(modes):  # pragma: no branch
            self.identity_scales.append(_floats(self.bytes, at, 1)[0])
            self.identity_offsets.append(at + 4)
            at += mode
        self.expression_names = List[String]()
        self.expression_scales = List[Float32]()
        self.expression_counts = List[Int]()
        self.expression_vertices = List[Int]()
        self.expression_moves = List[Int]()
        for _ in range(shapes):  # pragma: no branch
            _need(self.bytes, at, 1)
            var length = Int(self.bytes[at])
            _need(self.bytes, at + 1, length)
            var name = String()
            for k in range(length):  # pragma: no branch
                name += chr(Int(self.bytes[at + 1 + k]))
            self.expression_names.append(name)
            at = _aligned(at + 1 + length)
            _need(self.bytes, at, 8)
            var moved = _u32(self.bytes, at)
            self.expression_scales.append(_floats(self.bytes, at + 4, 1)[0])
            at += 8
            _need(self.bytes, at, _aligned(moved * 2) + moved * 3)
            self.expression_counts.append(moved)
            self.expression_vertices.append(at)
            at = _aligned(at + moved * 2)
            self.expression_moves.append(at)
            at = _aligned(at + moved * 3)

    def holes(self) -> Int:
        """Return how many holes the skin has."""
        return len(self.hole_starts) - 1

    def hole(self, index: Int) -> List[Int]:
        """Return one hole of the skin, as a loop of vertex indices in the
        order the skin's triangles run its edges.

        Args:
            index: Which hole, from zero.

        Returns:
            The loop.
        """
        var loop = List[Int]()
        for k in range(
            self.hole_starts[index], self.hole_starts[index + 1]
        ):  # pragma: no branch
            loop.append(self.hole_corners[k])
        return loop^

    def identities(self) -> Int:
        """Return how many identity modes the model has."""
        return len(self.identity_scales)

    def expressions(self) -> Int:
        """Return how many expression shapes the model has."""
        return len(self.expression_names)

    def no_identity(self) -> List[Float32]:
        """Return identity weights that give the mean head."""
        return List[Float32](length=self.identities(), fill=0)

    def no_expression(self) -> List[Float32]:
        """Return expression weights that give a neutral expression."""
        return List[Float32](length=self.expressions(), fill=0)

    def expression(self, name: String) raises -> Int:
        """Return the index of the expression called `name`.

        Args:
            name: An ARKit name with `_L` or `_R`, as `jawOpen` or
                `eyeBlink_L`.

        Returns:
            Its index among the expression weights.

        Raises:
            Error: If the model has no expression of that name.
        """
        for index in range(len(self.expression_names)):  # pragma: no branch
            if self.expression_names[index] == name:
                return index
        raise Error("The face model has no expression " + name)

    def shape(
        self, identity: List[Float32], expression: List[Float32]
    ) raises -> List[Vector3]:
        """Return every vertex for an identity and an expression, in the
        model's frame.

        Args:
            identity: One weight per identity mode, each about a standard
                normal.
            expression: One weight per expression shape, zero through one.

        Returns:
            One position per vertex of the model, in meters.

        Raises:
            Error: If a list has the wrong length.
        """
        if len(identity) != self.identities():
            raise Error("A face needs one weight per identity mode")
        if len(expression) != self.expressions():
            raise Error("A face needs one weight per expression")
        var points = self.neutral.copy()
        var count = len(points)
        for mode in range(len(identity)):  # pragma: no branch
            var w = identity[mode] * self.identity_scales[mode]
            if w == 0:
                continue
            var moves = self.bytes.unsafe_ptr().unsafe_bitcast[Int8]()
            var first = self.identity_offsets[mode]
            for v in range(count):  # pragma: no branch
                var at = first + v * 3
                points[v] = (
                    points[v]
                    + Vector3(
                        Float32(moves[unsafe_offset=at]),
                        Float32(moves[unsafe_offset=at + 1]),
                        Float32(moves[unsafe_offset=at + 2]),
                    )
                    * w
                )
        for shape in range(len(expression)):  # pragma: no branch
            var w = expression[shape] * self.expression_scales[shape]
            if w == 0:
                continue
            var words = self.bytes.unsafe_ptr().unsafe_bitcast[UInt16]()
            var moves = self.bytes.unsafe_ptr().unsafe_bitcast[Int8]()
            var first = self.expression_vertices[shape] // 2
            var start = self.expression_moves[shape]
            for k in range(self.expression_counts[shape]):  # pragma: no branch
                var v = Int(words[unsafe_offset=first + k])
                var at = start + k * 3
                points[v] = (
                    points[v]
                    + Vector3(
                        Float32(moves[unsafe_offset=at]),
                        Float32(moves[unsafe_offset=at + 1]),
                        Float32(moves[unsafe_offset=at + 2]),
                    )
                    * w
                )
        return points^

    def _check(self, part: FacePart) raises:
        """Raise unless `part` is a valid run of the model's vertices."""
        if not part.is_valid() or part.end > len(self.neutral):
            raise Error("A face part must be a run of the model's vertices")

    def triangles_of(self, parts: List[FacePart]) raises -> List[Int]:
        """Return the triangles that lie in any of `parts`.

        A texture seam draws a vertex twice; these triangles name the
        vertices themselves, so they join across the seams.

        Args:
            parts: The parts to keep.

        Returns:
            Three indices into the model's vertices a triangle.

        Raises:
            Error: If a part is not a valid run of the model's vertices.
        """
        for part in parts:  # pragma: no branch
            self._check(part)
        var kept = List[Int]()
        for t in range(0, len(self.triangles), 3):  # pragma: no branch
            var a = self.position_of[self.triangles[t]]
            var b = self.position_of[self.triangles[t + 1]]
            var c = self.position_of[self.triangles[t + 2]]
            if _in_parts(parts, a, b, c):
                kept.append(a)
                kept.append(b)
                kept.append(c)
        return kept^

    def part(
        self, points: List[Vector3], part: FacePart
    ) raises -> BufferGeometry:
        """Return one part of the head as a mesh.

        Args:
            points: Every vertex, from `shape`, in any frame.
            part: Which part.

        Returns:
            A geometry with `position`, `normal` and `uv`. The normals
            are the mean of the faces round each vertex, weighted by
            their area; vertices on a seam of the texture share theirs.

        Raises:
            Error: If `points` is not one per vertex of the model, the
                part is not a valid run of its vertices, or the part has
                no triangles.
        """
        self._check(part)
        if len(points) != len(self.neutral):
            raise Error("A face part needs one point per model vertex")
        var remap = List[Int](length=len(self.position_of), fill=-1)
        var positions = List[Float32]()
        var uvs = List[Float32]()
        var owners = List[Int]()
        var indices = List[Int]()
        var parts: List[FacePart] = [part]
        for t in range(0, len(self.triangles), 3):  # pragma: no branch
            if not _in_parts(
                parts,
                self.position_of[self.triangles[t]],
                self.position_of[self.triangles[t + 1]],
                self.position_of[self.triangles[t + 2]],
            ):
                continue
            for c in range(3):  # pragma: no branch
                var d = self.triangles[t + c]
                if remap[d] < 0:
                    remap[d] = len(owners)
                    var p = self.position_of[d]
                    owners.append(p)
                    positions.append(points[p].x)
                    positions.append(points[p].y)
                    positions.append(points[p].z)
                    uvs.append(self.uvs[d * 2])
                    uvs.append(self.uvs[d * 2 + 1])
                indices.append(remap[d])
        if len(indices) == 0:
            raise Error("That face part has no triangles")
        # Smooth normals, summed per position so a seam does not show.
        var sums = List[Vector3](
            length=len(self.neutral), fill=Vector3(0, 0, 0)
        )
        for t in range(0, len(indices), 3):  # pragma: no branch
            var a = points[owners[indices[t]]]
            var b = points[owners[indices[t + 1]]]
            var c = points[owners[indices[t + 2]]]
            var e1 = b - a
            var e2 = c - a
            var n = Vector3(
                e1.y * e2.z - e1.z * e2.y,
                e1.z * e2.x - e1.x * e2.z,
                e1.x * e2.y - e1.y * e2.x,
            )
            for c in range(3):  # pragma: no branch
                var p = owners[indices[t + c]]
                sums[p] = sums[p] + n
        var normals = List[Float32]()
        for i in range(len(owners)):  # pragma: no branch
            var n = sums[owners[i]]
            n.normalize()
            normals.append(n.x)
            normals.append(n.y)
            normals.append(n.z)
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
        geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
        geometry.set_index(indices^)
        return geometry^


def _in_any(parts: List[FacePart], vertex: Int) -> Bool:
    """Return True if one of `parts` holds `vertex`."""
    for part in parts:  # pragma: no branch
        if vertex >= part.first and vertex < part.end:
            return True
    return False


def _in_parts(parts: List[FacePart], a: Int, b: Int, c: Int) -> Bool:
    """Return True if `parts` hold all three vertices, one part or
    several between them."""
    return _in_any(parts, a) and _in_any(parts, b) and _in_any(parts, c)
