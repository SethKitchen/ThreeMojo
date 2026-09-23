# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bend a mesh along a curve, from three.js
`examples/jsm/modifiers/CurveModifier.js`: `Flow` and `InstancedFlow`.

three.js does this in two halves. On the CPU, `updateCurve` samples the
curve at 1024 points spaced by distance, with a Frenet frame at each, and
writes them as half floats into a data texture: one row of points, one
of tangents, one of normals and one of binormals for each curve. On the
GPU, a patched vertex shader reads the texture. The vertex's x, measured
along the spine, picks a place along the curve; its y and z are carried
out along that place's normal and binormal.

This port keeps the first half as it is: `Flow.spine` holds the same
half floats three.js's texture holds, bit for bit. The second half runs on
the CPU: `deform` does to every vertex what the shader does, in floats as
a GPU does, and returns the bent geometry. The texture is read with
linear filtering along a row, wrapping at the ends, as three.js's
`LinearFilter` and `RepeatWrapping` read it. A GPU keeps only a few bits
of the filter weight; this keeps them all.

## The space the result is in

The shader bends a vertex after the mesh's model matrix has moved it,
and then applies the model and view matrices again. The bent positions
`deform` returns are the shader's `transformed`: draw them with the
mesh's own matrix and they land where three.js draws them. The normals
are the shader's `basis * objectNormal`, before the normal matrix.

## Where this differs from three.js

three.js measures a curve's length with its `arcLengthDivisions`, which
`updateCurve` sets to 512 after it has measured it. So the length three.js
stores the first time is taken over 200 runs, and a second update of the
same curve object takes it over 512. A curve here has no such memory, and
the length is always taken over 200 runs, as the first update takes it.

three.js checks a curve index only against the top of its range. This
refuses a negative index as well, and `InstancedFlow` refuses an instance
or a curve that is not there. three.js's texture sets `wrapY`, which a
texture does not have, so a curve past the last clamps to the last row.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from math.matrix4 import Matrix4
from math.space_curve import (
    Point3,
    SpaceCurve,
    frames3_of,
    length_of,
    spaced_points3,
)
from render.exr import half_to_float
from std.math import floor, isnan
from std.memory import bitcast
from units.si import Length, METER

# Numbers a texel holds: red, green, blue and alpha.
comptime CHANNELS = 4
# Texels a row of the spine texture holds, and so points along a curve.
comptime TEXTURE_WIDTH = 1024
# Rows the texture holds for each curve: points, tangents, normals and
# binormals.
comptime TEXTURE_HEIGHT = 4
# How many runs measure the length a spine texture's points are spaced
# by: three.js sets `arcLengthDivisions` to half the points.
comptime SPINE_DIVISIONS = TEXTURE_WIDTH // 2
# The largest half float, which three.js clamps to.
comptime HALF_MAX = 65504.0


def to_half_float(value: Float64) -> UInt16:
    """Return a number as the bits of a half float, three.js's
    `DataUtils.toHalfFloat`.

    The number is clamped to the largest half and rounded to a float, and
    the float's extra fraction bits are cut off, not rounded, as three.js's
    tables do.

    Args:
        value: The number.

    Returns:
        The sixteen bits.
    """
    # JavaScript's clamp lets a NaN through.
    var clamped = value if isnan(value) else max(
        -HALF_MAX, min(HALF_MAX, value)
    )
    var f = bitcast[DType.uint32](Float32(clamped))
    var e = Int((f >> 23) & 0x1FF)
    var exponent = (e & 0xFF) - 127
    var sign = 0x8000 if e >= 0x100 else 0
    var fraction = Int(f & 0x007FFFFF)
    var base: Int
    var shift: Int
    if exponent < -27:
        base = 0
        shift = 24
    elif exponent < -14:
        base = 0x0400 >> (-exponent - 14)
        shift = -exponent - 1
    elif exponent <= 15:
        base = (exponent + 15) << 10
        shift = 13
    else:
        # Clamping leaves only a NaN out here, which keeps a fraction.
        base = 0x7C00
        shift = 13
    return UInt16((base | sign) + (fraction >> shift))


def _half_row(x: Float32, y: Float32, z: Float32) -> SIMD[DType.uint16, 4]:
    """Return one texel: three numbers and an alpha of one, as halves."""
    return SIMD[DType.uint16, 4](
        to_half_float(Float64(x)),
        to_half_float(Float64(y)),
        to_half_float(Float64(z)),
        to_half_float(1),
    )


struct Flow(Movable):
    """A spine texture and the uniforms that bend a mesh along it,
    three.js's `Flow`."""

    # The texture's numbers: `TEXTURE_WIDTH` texels a row, `CHANNELS`
    # halves a texel, `TEXTURE_HEIGHT` rows a curve.
    var spine: List[UInt16]
    var curve_count: Int
    # Each curve's length, zero until it is set.
    var curve_lengths: List[Length]
    # How far along the path the mesh has moved, in shares of the path:
    # three.js's `pathOffset`.
    var path_offset: Float32
    # What share of the path the spine covers: three.js's `pathSegment`.
    var path_segment: Float32
    # Where along x the spine starts: three.js's `spineOffset`.
    var spine_offset: Length
    # How long the spine is: three.js's `spineLength`, the length of the
    # last curve given.
    var spine_length: Length
    # Whether to bend: three.js's `flow`. False places the mesh at the
    # start of the curve without bending it.
    var flow: Bool

    def __init__(out self, curve_count: Int = 1) raises:
        """Create an empty spine texture for some number of curves.

        Args:
            curve_count: How many curves the texture has room for, one or
                more.

        Raises:
            Error: If `curve_count` is less than one.
        """
        if curve_count < 1:
            raise Error("A flow needs room for one curve or more")
        self.spine = List[UInt16](
            length=TEXTURE_WIDTH * TEXTURE_HEIGHT * curve_count * CHANNELS,
            fill=0,
        )
        self.curve_count = curve_count
        self.curve_lengths = List[Length](
            length=curve_count, fill=Length(0, METER)
        )
        self.path_offset = 0
        self.path_segment = 1
        self.spine_offset = Length(161, METER)
        self.spine_length = Length(400, METER)
        self.flow = True

    def update_curve[C: SpaceCurve](mut self, index: Int, curve: C) raises:
        """Write a curve into its rows of the texture, three.js's
        `updateCurve`.

        Parameters:
            C: The type of the curve.

        Args:
            index: Which curve's rows to write, from zero.
            curve: The curve.

        Raises:
            Error: If there is no room for a curve of that index, or the
                curve refuses a point.
        """
        if index < 0 or index >= self.curve_count:
            raise Error("A flow has no curve of that index")
        var length = length_of(curve)
        self.spine_length = length
        self.curve_lengths[index] = length
        var points = spaced_points3(curve, TEXTURE_WIDTH, SPINE_DIVISIONS)
        var frames = frames3_of(curve, TEXTURE_WIDTH, True, SPINE_DIVISIONS)
        for i in range(TEXTURE_WIDTH):  # pragma: no branch
            var rows = List[Point3]()
            rows.append(points[i])
            rows.append(frames.tangents[i])
            rows.append(frames.normals[i])
            rows.append(frames.binormals[i])
            for row in range(TEXTURE_HEIGHT):  # pragma: no branch
                var texel = _half_row(
                    Float32(rows[row][0]),
                    Float32(rows[row][1]),
                    Float32(rows[row][2]),
                )
                var at = self._at(i, row + TEXTURE_HEIGHT * index)
                for channel in range(CHANNELS):  # pragma: no branch
                    self.spine[at + channel] = texel[channel]

    def move_along_curve(mut self, amount: Float32):
        """Move the mesh along the path, three.js's `moveAlongCurve`.

        Args:
            amount: How far, in shares of the path.
        """
        self.path_offset += amount

    def _at(self, x: Int, row: Int) -> Int:
        """Return where a texel starts in `spine`."""
        return (row * TEXTURE_WIDTH + x) * CHANNELS

    def texel(self, x: Int, row: Int) raises -> SIMD[DType.float32, 4]:
        """Return one texel's four numbers, decoded from halves.

        Args:
            x: Which texel along the row, from zero.
            row: Which row, from zero.

        Returns:
            The texel.

        Raises:
            Error: If the texel is not in the texture.
        """
        if x < 0 or x >= TEXTURE_WIDTH:
            raise Error("A spine texel must lie along the row")
        if row < 0 or row >= TEXTURE_HEIGHT * self.curve_count:
            raise Error("A spine texel must lie in a row of the texture")
        var at = self._at(x, row)
        return SIMD[DType.float32, 4](
            half_to_float(self.spine[at]),
            half_to_float(self.spine[at + 1]),
            half_to_float(self.spine[at + 2]),
            half_to_float(self.spine[at + 3]),
        )

    def sample(self, u: Float32, row: Int) raises -> SIMD[DType.float32, 4]:
        """Return the texture read at `u` along a row, with linear
        filtering and repeat wrapping, as `texture2D` reads it at the
        middle of the row.

        Args:
            u: Where along the row, zero at its left edge and one at its
                right.
            row: Which row.

        Returns:
            The filtered texel.

        Raises:
            Error: If the row is not in the texture.
        """
        var place = u * Float32(TEXTURE_WIDTH) - 0.5
        var left = floor(place)
        var weight = place - left
        var first = (Int(left) % TEXTURE_WIDTH + TEXTURE_WIDTH) % TEXTURE_WIDTH
        var second = (first + 1) % TEXTURE_WIDTH
        var a = self.texel(first, row)
        var b = self.texel(second, row)
        return a * (1 - weight) + b * weight

    def _bend(
        self,
        world: SIMD[DType.float32, 4],
        normal: SIMD[DType.float32, 4],
        spine_length: Float32,
        instance_offset: Float32,
        row_offset: Int,
    ) raises -> List[SIMD[DType.float32, 4]]:
        """Return a vertex and its normal bent as the shader bends them."""
        var x_weight = Float32(0) if self.flow else Float32(1)
        var portion = Float32(0)
        if self.flow:
            portion = (world[0] + self.spine_offset.value) / spine_length
        var mt = portion * self.path_segment + self.path_offset
        mt = mt + instance_offset
        mt = mt - floor(mt)
        var row = Int(floor(mt)) + row_offset
        var spine_pos = self.sample(mt, row)
        var a = self.sample(mt, row + 1)
        var b = self.sample(mt, row + 2)
        var c = self.sample(mt, row + 3)
        var local = SIMD[DType.float32, 4](
            world[0] * x_weight, world[1], world[2], 0
        )
        var moved = a * local[0] + b * local[1] + c * local[2] + spine_pos
        var turned = a * normal[0] + b * normal[1] + c * normal[2]
        return [moved, turned]

    def _deformed(
        self,
        geometry: BufferGeometry,
        model: Matrix4,
        spine_length: Float32,
        instance_offset: Float32,
        row_offset: Int,
    ) raises -> BufferGeometry:
        """Return a geometry with every vertex bent."""
        var result = geometry.clone()
        ref positions = geometry.attribute_view(String(POSITION))
        if positions.item_size != 3:
            raise Error("A flow bends positions of three numbers")
        var has_normals = geometry.has_attribute(String(NORMAL))
        var count = positions.count()
        var moved = List[Float32](length=count * 3, fill=0)
        var turned = List[Float32](length=count * 3, fill=0)
        for vertex in range(count):
            var p = model.transform_point(positions.vector3(vertex))
            var world = SIMD[DType.float32, 4](p.x, p.y, p.z, 1)
            var normal = SIMD[DType.float32, 4](0)
            if has_normals:
                var n = geometry.attribute_view(String(NORMAL)).vector3(vertex)
                normal = SIMD[DType.float32, 4](n.x, n.y, n.z, 0)
            var bent = self._bend(
                world, normal, spine_length, instance_offset, row_offset
            )
            for axis in range(3):  # pragma: no branch
                moved[vertex * 3 + axis] = bent[0][axis]
                turned[vertex * 3 + axis] = bent[1][axis]
        result.set_attribute(String(POSITION), BufferAttribute(moved^, 3))
        if has_normals:
            result.set_attribute(String(NORMAL), BufferAttribute(turned^, 3))
        return result^

    def deform(
        self, geometry: BufferGeometry, model: Matrix4 = Matrix4()
    ) raises -> BufferGeometry:
        """Return a geometry bent along the first curve, as three.js's
        patched vertex shader bends it.

        Args:
            geometry: The geometry, with positions of three numbers. Its
                normals, if it has them, turn with it.
            model: The mesh's model matrix, which the shader applies
                before it bends. The identity unless said otherwise.

        Returns:
            A copy of the geometry with `position`, and `normal` if it has
            one, bent; see the module docstring for the space they are in.

        Raises:
            Error: If the geometry has no positions of three numbers, or
                the normals do not cover every vertex.
        """
        return self._deformed(
            geometry,
            model,
            self.spine_length.value,
            0,
            0,
        )


struct InstancedFlow(Movable):
    """A flow whose instances each ride a curve of their own at an
    offset of their own, three.js's `InstancedFlow`."""

    var flow: Flow
    # How far along its curve each instance is, in shares of the path.
    var offsets: List[Float32]
    # Which curve each instance rides.
    var which_curve: List[Int]

    def __init__(out self, count: Int, curve_count: Int) raises:
        """Create a flow for `count` instances over `curve_count` curves.

        Args:
            count: How many instances, zero or more.
            curve_count: How many curves, one or more.

        Raises:
            Error: If `count` is negative or `curve_count` is less than
                one.
        """
        if count < 0:
            raise Error("An instanced flow cannot have a negative count")
        self.flow = Flow(curve_count)
        self.offsets = List[Float32](length=count, fill=0)
        self.which_curve = List[Int](length=count, fill=0)

    def _check(self, index: Int) raises:
        """Refuse an instance that is not there."""
        if index < 0 or index >= len(self.offsets):
            raise Error("An instanced flow has no instance of that index")

    def instance_matrix(self, index: Int) raises -> Matrix4:
        """Return the matrix three.js writes for an instance, its
        `writeChanges`: a translation by the curve's length, the curve's
        number and the offset.

        Args:
            index: Which instance.

        Returns:
            The matrix.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        var curve = self.which_curve[index]
        var matrix = Matrix4()
        matrix.elements[12] = self.flow.curve_lengths[curve].value
        matrix.elements[13] = Float32(curve)
        matrix.elements[14] = self.offsets[index]
        return matrix

    def move_individual_along_curve(
        mut self, index: Int, offset: Float32
    ) raises:
        """Move one instance along its curve, three.js's
        `moveIndividualAlongCurve`.

        Args:
            index: Which instance.
            offset: How far, in shares of the path.

        Raises:
            Error: If there is no such instance.
        """
        self._check(index)
        self.offsets[index] += offset

    def set_curve(mut self, index: Int, curve: Int) raises:
        """Put one instance on a curve, three.js's `setCurve`.

        Args:
            index: Which instance.
            curve: Which curve.

        Raises:
            Error: If there is no such instance or no such curve.
        """
        self._check(index)
        if curve < 0 or curve >= self.flow.curve_count:
            raise Error("An instanced flow has no curve of that index")
        self.which_curve[index] = curve

    def deform_instance(
        self, geometry: BufferGeometry, index: Int, model: Matrix4 = Matrix4()
    ) raises -> BufferGeometry:
        """Return a geometry bent as one instance of it is drawn, as
        three.js's shader bends it under `USE_INSTANCING`.

        The spine length is the instance's curve's, and the offset is the
        flow's plus the instance's. The instance matrix moves nothing
        else: the shader reads it and does not apply it.

        Args:
            geometry: The geometry, with positions of three numbers.
            index: Which instance.
            model: The mesh's model matrix.

        Returns:
            A copy of the geometry, bent.

        Raises:
            Error: If there is no such instance, or the geometry cannot be
                bent; see `Flow.deform`.
        """
        var matrix = self.instance_matrix(index)
        return self.flow._deformed(
            geometry,
            model,
            matrix.elements[12],
            matrix.elements[14],
            Int(matrix.elements[13]) * TEXTURE_HEIGHT,
        )
