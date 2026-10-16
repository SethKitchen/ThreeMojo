# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the procedural generators share, from three.js
`examples/jsm/generators/`: the seeded generator, a vector in `Float64`,
the part codes a merged geometry carries, and the placement matrices.

Every three.js generator seeds its own `createRandom`, a Mulberry32
generator. It is the generator of `MathUtils.seededRandom`, so
`generator_random` returns a `SeededRandom`. The only difference is the
seed: three.js keeps its low 32 bits and turns a zero into a one.

three.js computes in `Float64` and stores the result in `Float32` arrays.
`Vec3d` is a vector in `Float64`, so the generators compute as three.js
does and round once, when they write a geometry or a matrix.

A generator that merges parts into one geometry writes a `partId`
attribute: one number per vertex that says which zone of the model the
vertex belongs to. three.js's materials branch on it. `PartId` is that
number as a type, and `part` tags a geometry with one.
"""
from core.ordinal import ordinal_valid

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry
from geometries.utils import merge_vertices
from math.cross import cross_components
from math.matrix4 import Matrix4
from math.norm import (
    dot3,
    length3,
    normalized3,
    _ordinary_squared,
    squared_length3,
)
from math.quaternion import quaternion_rotate, quaternion_terms
from math.utils import SeededRandom
from math.vector3 import Vector3
from std.math import cos, isfinite, sin, sqrt
from units.si import Angle, Length, METER, RADIAN

# The name of the per-vertex part attribute, as three.js names it.
comptime PART_ID = "partId"

# How many part codes there are. The skyscraper and the car use the most,
# nine each, from zero to eight.
comptime PART_ID_COUNT = 9


@fieldwise_init
struct PartId(Equatable, ImplicitlyCopyable, Writable):
    """Which zone of a merged model a vertex belongs to, three.js's
    `partId` codes, as a type rather than a bare int.

    Each generator names its own codes: a skyscraper's `WALL` and a
    streetlight's `METAL` are both zero. `part` stops a code outside the
    range with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the codes there are.

        Returns:
            Whether the code is from zero to eight.
        """
        return ordinal_valid(self.value, PART_ID_COUNT - 1)


def generator_random(seed: Int) -> SeededRandom:
    """Return a generator seeded as three.js's generators seed theirs,
    `createRandom`.

    three.js keeps the low 32 bits of the seed, `seed >>> 0`, and takes
    one for a zero, `|| 1`.

    Args:
        seed: The seed. Any whole number.

    Returns:
        The generator.
    """
    var kept = seed & 0xFFFFFFFF
    return SeededRandom(kept if kept != 0 else 1)


@fieldwise_init
struct Vec3d(ImplicitlyCopyable):
    """A point or direction in `Float64`, for arithmetic that three.js does
    in `Float64`.

    The methods return a new vector. Ordinary arithmetic follows three.js's
    `Vector3` method of the same name. Length and normalization also support
    extreme finite magnitudes with scale-safe norms.
    """

    var x: Float64
    var y: Float64
    var z: Float64

    def __add__(self, other: Self) -> Self:
        """Return the sum.

        Args:
            other: The other vector.

        Returns:
            The sum.
        """
        return Vec3d(self.x + other.x, self.y + other.y, self.z + other.z)

    def __sub__(self, other: Self) -> Self:
        """Return the difference.

        Args:
            other: The vector to take away.

        Returns:
            The difference.
        """
        return Vec3d(self.x - other.x, self.y - other.y, self.z - other.z)

    def __mul__(self, factor: Float64) -> Self:
        """Return the vector scaled.

        Args:
            factor: The factor.

        Returns:
            The scaled vector.
        """
        return Vec3d(self.x * factor, self.y * factor, self.z * factor)

    def __neg__(self) -> Self:
        """Return the vector pointing the other way, three.js's `negate`.

        Returns:
            The opposite vector.
        """
        return Vec3d(-self.x, -self.y, -self.z)

    def min(self, other: Self) -> Self:
        """Return the smaller of each component, three.js's `min`.

        Args:
            other: The other vector.

        Returns:
            The smaller components.
        """
        return Vec3d(
            min(self.x, other.x), min(self.y, other.y), min(self.z, other.z)
        )

    def max(self, other: Self) -> Self:
        """Return the larger of each component, three.js's `max`.

        Args:
            other: The other vector.

        Returns:
            The larger components.
        """
        return Vec3d(
            max(self.x, other.x), max(self.y, other.y), max(self.z, other.z)
        )

    def dot(self, other: Self) -> Float64:
        """Return the dot product.

        Args:
            other: The other vector.

        Returns:
            The dot product.
        """
        return dot3[DType.float64](
            self.x, self.y, self.z, other.x, other.y, other.z
        )

    def cross(self, other: Self) -> Self:
        """Return the cross product, three.js's `crossVectors(self, other)`.

        Args:
            other: The other vector.

        Returns:
            The cross product.
        """
        var x, y, z = cross_components[DType.float64](
            self.x, self.y, self.z, other.x, other.y, other.z
        )
        return Vec3d(x, y, z)

    def length(self) -> Float64:
        """Return the scale-safe length.

        Returns:
            The length, or infinity if it exceeds the Float64 range.
        """
        return length3(self.x, self.y, self.z)

    def is_finite(self) -> Bool:
        """Return True if every component is finite.

        Returns:
            True when `x`, `y`, and `z` are all finite.
        """
        return isfinite(self.x) and isfinite(self.y) and isfinite(self.z)

    def distance_to(self, other: Self) -> Float64:
        """Return the distance to another point.

        Args:
            other: The other point.

        Returns:
            The distance.
        """
        return (self - other).length()

    def normalized(self) -> Self:
        """Return the vector made unit length, three.js's `normalize`.

        A zero vector stays zero. Finite nonzero vectors use a scale-safe
        norm, even when their length cannot fit in Float64.

        Returns:
            The unit vector, or the zero vector.
        """
        var squared = squared_length3[DType.float64](self.x, self.y, self.z)
        # Keep three.js's reciprocal multiply for ordinary seeded fixtures.
        if _ordinary_squared(squared):
            return self * (1.0 / sqrt(squared))
        var components = normalized3(self.x, self.y, self.z)
        return Vec3d(components[0], components[1], components[2])

    def lerp(self, other: Self, alpha: Float64) -> Self:
        """Return the point a fraction of the way to another, three.js's
        `lerp`.

        Args:
            other: The other end.
            alpha: The fraction.

        Returns:
            The point.
        """
        return self + (other - self) * alpha

    def rotated(self, axis: Self, angle: Float64) -> Self:
        """Return the vector turned about a unit axis, three.js's
        `applyAxisAngle`: a quaternion from the axis and angle, applied.

        Args:
            axis: The unit axis.
            angle: How far, in radians.

        Returns:
            The turned vector.
        """
        var half = angle / 2
        var s = sin(half)
        var qx = axis.x * s
        var qy = axis.y * s
        var qz = axis.z * s
        var qw = cos(half)
        var rx, ry, rz = quaternion_rotate[DType.float64](
            qx, qy, qz, qw, self.x, self.y, self.z
        )
        return Vec3d(rx, ry, rz)

    def vector3(self) -> Vector3:
        """Return the vector rounded to `Float32`.

        Returns:
            The vector.
        """
        return Vector3(Float32(self.x), Float32(self.y), Float32(self.z))


@fieldwise_init
struct Quat64(ImplicitlyCopyable):
    """A quaternion in `Float64`, for turns three.js computes in
    `Float64`."""

    var x: Float64
    var y: Float64
    var z: Float64
    var w: Float64

    def apply(self, v: Vec3d) -> Vec3d:
        """Return a vector turned by the quaternion, three.js's
        `applyQuaternion`.

        Args:
            v: The vector.

        Returns:
            The turned vector.
        """
        var rx, ry, rz = quaternion_rotate[DType.float64](
            self.x, self.y, self.z, self.w, v.x, v.y, v.z
        )
        return Vec3d(rx, ry, rz)


def unit_vectors_quaternion(start: Vec3d, end: Vec3d) -> Quat64:
    """Return the turn that carries one unit vector onto another,
    three.js's `Quaternion.setFromUnitVectors`.

    Opposite vectors have no cross product, so three.js turns a half turn
    about an axis across the start instead.

    Args:
        start: The unit vector to turn.
        end: The unit vector to turn it onto.

    Returns:
        The turn, unit length.
    """
    var r = start.dot(end) + 1
    var flip = r < 1e-8
    var across = Vec3d(-start.y, start.x, 0) if abs(start.x) > abs(
        start.z
    ) else Vec3d(0, -start.z, start.y)
    var q = across if flip else start.cross(end)
    var w = 0.0 if flip else r
    var inverse = 1 / sqrt(q.x * q.x + q.y * q.y + q.z * q.z + w * w)
    return Quat64(q.x * inverse, q.y * inverse, q.z * inverse, w * inverse)


def meters(length: Length) -> Float64:
    """Return a length in meters, in `Float64`.

    Args:
        length: The length.

    Returns:
        Its size in meters.
    """
    return Float64(length.to(METER))


def radians(angle: Angle) -> Float64:
    """Return an angle in radians, in `Float64`.

    Args:
        angle: The angle.

    Returns:
        Its size in radians.
    """
    return Float64(angle.to(RADIAN))


def length_meters(value: Float64) -> Length:
    """Return a number of meters as a length.

    Args:
        value: The size in meters.

    Returns:
        The length.
    """
    return Length(Float32(value), METER)


def angle_radians(value: Float64) -> Angle:
    """Return a number of radians as an angle.

    Args:
        value: The size in radians.

    Returns:
        The angle.
    """
    return Angle(Float32(value), RADIAN)


def check_finite(value: Float64, what: String) raises:
    """Refuse a number that is infinite or not a number.

    Args:
        value: The number.
        what: What the number is, for the message.

    Raises:
        Error: If the number is not finite.
    """
    if not isfinite(value):
        raise Error(what + " must be a finite number")


def part(geometry: BufferGeometry, id: PartId) raises -> BufferGeometry:
    """Return a geometry tagged with one part code on every vertex,
    three.js's `part` in `CityGeneratorUtils.js`.

    A geometry without an index is welded first, as three.js welds it
    with `mergeVertices`, so every part merges as an indexed geometry.

    Args:
        geometry: The part.
        id: Its code.

    Returns:
        The part, indexed, with a `partId` attribute.

    Raises:
        Error: If the code is not one there is, or the geometry cannot be
            welded; see `merge_vertices`.
    """
    if not id.is_valid():
        raise Error("A part code must be from zero to eight")
    var tagged = geometry.clone() if geometry.is_indexed() else merge_vertices(
        geometry
    )
    var count = tagged.vertex_count()
    tagged.set_attribute(
        String(PART_ID),
        BufferAttribute(List[Float32](length=count, fill=Float32(id.value)), 1),
    )
    return tagged^


def basis_matrix(
    x_axis: Vec3d, y_axis: Vec3d, z_axis: Vec3d, position: Vec3d
) -> Matrix4:
    """Return three.js's `makeBasis(x, y, z).setPosition(position)`.

    Args:
        x_axis: The first column.
        y_axis: The second column.
        z_axis: The third column.
        position: The translation.

    Returns:
        The matrix, rounded to `Float32`.
    """
    var matrix = Matrix4()
    matrix.set(
        Float32(x_axis.x),
        Float32(y_axis.x),
        Float32(z_axis.x),
        Float32(position.x),
        Float32(x_axis.y),
        Float32(y_axis.y),
        Float32(z_axis.y),
        Float32(position.y),
        Float32(x_axis.z),
        Float32(y_axis.z),
        Float32(z_axis.z),
        Float32(position.z),
        0,
        0,
        0,
        1,
    )
    return matrix


def place(
    x: Float64, y: Float64, z: Float64, face_x: Float64, face_z: Float64
) -> Matrix4:
    """Return a placement at a point whose local +z faces a direction in
    the ground plane, three.js's `place` in `CityGenerator.js`.

    A model authored facing +z turns to face that way, and stays upright.

    Args:
        x: The x of the point, in meters.
        y: The y of the point, in meters.
        z: The z of the point, in meters.
        face_x: The x of the direction to face.
        face_z: The z of the direction to face.

    Returns:
        The placement.
    """
    var up = Vec3d(0, 1, 0)
    var forward = Vec3d(face_x, 0, face_z).normalized()
    var right = up.cross(forward).normalized()
    return basis_matrix(right, up, forward, Vec3d(x, y, z))


def compose_matrix(
    position: Vec3d,
    qx: Float64,
    qy: Float64,
    qz: Float64,
    qw: Float64,
    scale: Vec3d,
) -> Matrix4:
    """Return three.js's `Matrix4.compose`: a scale, then a turn by a
    quaternion, then a move.

    Args:
        position: The move.
        qx: The quaternion's x.
        qy: The quaternion's y.
        qz: The quaternion's z.
        qw: The quaternion's w.
        scale: The scale along each axis.

    Returns:
        The matrix, rounded to `Float32`.
    """
    var xx, xy, xz, yy, yz, zz, wx, wy, wz = quaternion_terms[DType.float64](
        qx, qy, qz, qw
    )
    return basis_matrix(
        Vec3d(
            (1 - (yy + zz)) * scale.x, (xy + wz) * scale.x, (xz - wy) * scale.x
        ),
        Vec3d(
            (xy - wz) * scale.y, (1 - (xx + zz)) * scale.y, (yz + wx) * scale.y
        ),
        Vec3d(
            (xz + wy) * scale.z, (yz - wx) * scale.z, (1 - (xx + yy)) * scale.z
        ),
        position,
    )


def place_yaw_scale(
    x: Float64, y: Float64, z: Float64, yaw: Float64, scale: Float64
) -> Matrix4:
    """Return a placement turned about +y and scaled evenly, three.js's
    `placeYawScale` in `CityGenerator.js`.

    Args:
        x: The x of the point, in meters.
        y: The y of the point, in meters.
        z: The z of the point, in meters.
        yaw: The turn about +y, in radians.
        scale: The scale.

    Returns:
        The placement.
    """
    var half = yaw / 2
    return compose_matrix(
        Vec3d(x, y, z),
        0,
        sin(half),
        0,
        cos(half),
        Vec3d(scale, scale, scale),
    )


def euler_matrix(
    position: Vec3d, rx: Float64, ry: Float64, rz: Float64, scale: Vec3d
) -> Matrix4:
    """Return an `Object3D`'s matrix, three.js's `updateMatrix`, for a
    rotation in the default `XYZ` order.

    Args:
        position: The position.
        rx: The turn about x, in radians.
        ry: The turn about y, in radians.
        rz: The turn about z, in radians.
        scale: The scale along each axis.

    Returns:
        The matrix.
    """
    var c1 = cos(rx / 2)
    var c2 = cos(ry / 2)
    var c3 = cos(rz / 2)
    var s1 = sin(rx / 2)
    var s2 = sin(ry / 2)
    var s3 = sin(rz / 2)
    return compose_matrix(
        position,
        s1 * c2 * c3 + c1 * s2 * s3,
        c1 * s2 * c3 - s1 * c2 * s3,
        c1 * c2 * s3 + s1 * s2 * c3,
        c1 * c2 * c3 - s1 * s2 * s3,
        scale,
    )


struct Instances(Movable):
    """One geometry placed many times: what three.js's instanced
    generators return as an `InstancedMesh`.

    The scene graph here keeps geometries in a store and an instanced mesh
    names one by id, so a generator returns the geometry and the matrices,
    and the caller adds them to a scene. `values` is the per-instance data
    three.js keeps in an `InstancedBufferAttribute`, `item_size` numbers an
    instance: a car's paint, a person's seed, a tree's cull data. It is
    empty where three.js has none.
    """

    var name: String
    var geometry: BufferGeometry
    var matrices: List[Matrix4]
    var values: List[Float32]
    var item_size: Int
    # Whether the instances are drawn into shadow maps, and whether
    # shadows fall on them, three.js's `castShadow` and `receiveShadow`.
    var cast_shadow: Bool
    var receive_shadow: Bool

    def __init__(out self, name: String, var geometry: BufferGeometry):
        """Create an empty set of instances of one geometry.

        Args:
            name: The mesh's name, as three.js names it.
            geometry: The geometry every instance draws.
        """
        self.name = name
        self.geometry = geometry^
        self.matrices = List[Matrix4]()
        self.values = List[Float32]()
        self.item_size = 0
        self.cast_shadow = False
        self.receive_shadow = False

    def count(self) -> Int:
        """Return how many instances there are, three.js's `count`.

        Returns:
            The count.
        """
        return len(self.matrices)

    def visible(self) -> Bool:
        """Return whether there is anything to draw, three.js's `visible`,
        which `updateInstances` sets.

        Returns:
            True if there is an instance at least.
        """
        return len(self.matrices) > 0
