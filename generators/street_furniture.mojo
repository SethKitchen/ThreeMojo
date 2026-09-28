# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The street furniture of a city, from three.js
`examples/jsm/generators/city/`: `StreetlightGenerator`,
`TrafficlightGenerator`, `TrashcanGenerator`, `BenchGenerator`,
`HydrantGenerator` and `StreetTreeGenerator`.

Each piece is built once from boxes, cylinders and a few other primitives,
merged into one indexed geometry, and placed at every placement the city
hands it: three.js's `InstancedMeshGenerator`. Every part carries a
`partId`, so one material can shade the metal, the lenses, the wood or the
leaves apart. Each model stands on y equals zero, centered in x and z,
facing +z, so a placement whose +z faces the road turns it to the road.

The materials are not ported. The street tree's leaf clumps jitter their
vertices by a hash of `sin` of the `Float32` position times 43758.5453, as
three.js does. The hash turns a difference in the last bit of a position
into a different jitter, so the lobes of the canopy can differ from
three.js's where a primitive rounds a vertex differently.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from generators.utils import (
    Instances,
    PartId,
    Vec3d,
    compose_matrix,
    meters,
    part,
)
from geometries.box import box
from geometries.circle import ring
from geometries.cylinder import cylinder
from geometries.polyhedron import icosahedron
from geometries.sphere import sphere
from geometries.utils import merge_geometries, merge_vertices
from math.matrix4 import Matrix4
from std.math import floor, pi, sin, sqrt
from units.si import Angle, Length, METER, RADIAN

# A streetlight's parts.
comptime LIGHT_METAL = PartId(0)
comptime LIGHT_LENS = PartId(1)
# A traffic signal's parts.
comptime SIGNAL_METAL = PartId(0)
comptime SIGNAL_RED = PartId(1)
comptime SIGNAL_AMBER = PartId(2)
comptime SIGNAL_GREEN = PartId(3)
# A litter basket's parts.
comptime CAN_MESH = PartId(0)
comptime CAN_RIM = PartId(1)
comptime CAN_TRASH = PartId(2)
# A bench's parts.
comptime BENCH_WOOD = PartId(0)
comptime BENCH_IRON = PartId(1)
# A hydrant's parts.
comptime HYDRANT_BODY = PartId(0)
comptime HYDRANT_CAP = PartId(1)
# A street tree's parts.
comptime TREE_TRUNK = PartId(0)
comptime TREE_LEAF = PartId(1)
comptime TREE_GRATE = PartId(2)

# The crown sphere the street tree's clump normals blend toward, in
# meters.
comptime CROWN_CENTER_Y = 3.9
comptime CROWN_CENTER_Z = 0.1
comptime CROWN_RADIUS = 3.1


def _l(value: Float64) -> Length:
    """Return a number of meters as a length."""
    return Length(Float32(value), METER)


def _a(value: Float64) -> Angle:
    """Return a number of radians as an angle."""
    return Angle(Float32(value), RADIAN)


def _moved(
    var geometry: BufferGeometry, x: Float64, y: Float64, z: Float64
) raises -> BufferGeometry:
    """Return a geometry moved, three.js's `translate`."""
    geometry.translate(_l(x), _l(y), _l(z))
    return geometry^


def _cylinder(
    top: Float64,
    bottom: Float64,
    height: Float64,
    segments: Int,
    open_ended: Bool = False,
) raises -> BufferGeometry:
    """Return three.js's `CylinderGeometry` with one height segment."""
    return cylinder(_l(top), _l(bottom), _l(height), segments, 1, open_ended)


def _box(width: Float64, height: Float64, depth: Float64) raises -> BufferGeometry:
    """Return three.js's `BoxGeometry`."""
    return box(_l(width), _l(height), _l(depth))


def _turned_x(var geometry: BufferGeometry, angle: Float64) raises -> BufferGeometry:
    """Return a geometry turned about x, three.js's `rotateX`."""
    geometry.rotate_x(_a(angle))
    return geometry^


def _turned_y(var geometry: BufferGeometry, angle: Float64) raises -> BufferGeometry:
    """Return a geometry turned about y, three.js's `rotateY`."""
    geometry.rotate_y(_a(angle))
    return geometry^


def _turned_z(var geometry: BufferGeometry, angle: Float64) raises -> BufferGeometry:
    """Return a geometry turned about z, three.js's `rotateZ`."""
    geometry.rotate_z(_a(angle))
    return geometry^


def unit_vectors_turn(start: Vec3d, end: Vec3d) -> Matrix4:
    """Return the turn that carries one unit vector onto another,
    three.js's `Quaternion.setFromUnitVectors`, as a matrix.

    Args:
        start: The unit vector to turn.
        end: The unit vector to turn it onto.

    Returns:
        The turn.
    """
    var r = start.dot(end) + 1
    # Opposite vectors have no cross product; three.js turns a half turn
    # about an axis across the start instead.
    var flip = r < 1e-8
    var across = Vec3d(-start.y, start.x, 0) if abs(start.x) > abs(
        start.z
    ) else Vec3d(0, -start.z, start.y)
    var q = across if flip else start.cross(end)
    var w = 0.0 if flip else r
    var length = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + w * w)
    var inverse = 1 / length
    return compose_matrix(
        Vec3d(0, 0, 0),
        q.x * inverse,
        q.y * inverse,
        q.z * inverse,
        w * inverse,
        Vec3d(1, 1, 1),
    )


def _strut(a: Vec3d, b: Vec3d, radius: Float64) raises -> BufferGeometry:
    """Return a cylinder spanning two points, three.js's `strut`."""
    var direction = b - a
    var geometry = _cylinder(radius, radius, direction.length(), 6)
    geometry.apply_matrix4(
        unit_vectors_turn(Vec3d(0, 1, 0), direction.normalized())
    )
    return _moved(
        geometry^, (a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2
    )


def placed(
    name: String,
    var geometry: BufferGeometry,
    placements: List[Matrix4],
    receive_shadow: Bool = True,
) -> Instances:
    """Return a geometry placed at every placement, three.js's
    `InstancedMeshGenerator.build`.

    Args:
        name: The mesh's name.
        geometry: The model.
        placements: One matrix an instance.
        receive_shadow: Whether shadows fall on the instances. They all
            cast shadows.

    Returns:
        The instances.
    """
    var instances = Instances(name, geometry^)
    instances.matrices = placements.copy()
    instances.cast_shadow = True
    instances.receive_shadow = receive_shadow
    return instances^


@fieldwise_init
struct StreetlightGenerator(Copyable, Movable):
    """A New York cobra-head streetlight, three.js's
    `StreetlightGenerator`: a tapered mast with a curved arm reaching over
    the road toward +z to a drop luminaire."""

    # The mast's height.
    var height: Length
    # How far the arm reaches out over the road.
    var reach: Length
    # The mast's radius at its top.
    var radius: Length

    def __init__(out self):
        """Create three.js's default streetlight."""
        self.height = Length(9, METER)
        self.reach = Length(2.4, METER)
        self.radius = Length(0.1, METER)

    def geometry(self) raises -> BufferGeometry:
        """Return the streetlight, three.js's `buildStreetlightGeometry`.

        Returns:
            The model, indexed, with a `partId`: metal, or the lens.

        Raises:
            Error: If a size is not positive.
        """
        var h = meters(self.height)
        var reach = meters(self.reach)
        var r = meters(self.radius)
        var arm_base = Vec3d(0, h - 0.4, 0)
        var arm_knee = Vec3d(0, h + 0.5, reach * 0.35)
        var arm_end = Vec3d(0, h + 0.2, reach)
        var arm = merge_geometries(
            [
                _strut(arm_base, arm_knee, 0.07),
                _strut(arm_knee, arm_end, 0.06),
            ]
        )
        return merge_geometries(
            [
                part(_moved(_cylinder(0.18, 0.22, 0.6, 8), 0, 0.3, 0), LIGHT_METAL),
                part(_moved(_cylinder(r, r * 1.7, h, 8), 0, h / 2, 0), LIGHT_METAL),
                part(arm, LIGHT_METAL),
                part(
                    _moved(
                        _box(0.26, 0.16, 0.7),
                        arm_end.x,
                        arm_end.y - 0.05,
                        arm_end.z + 0.2,
                    ),
                    LIGHT_METAL,
                ),
                part(
                    _moved(
                        _box(0.2, 0.05, 0.5),
                        arm_end.x,
                        arm_end.y - 0.14,
                        arm_end.z + 0.2,
                    ),
                    LIGHT_LENS,
                ),
            ]
        )

    def build(self, placements: List[Matrix4]) raises -> Instances:
        """Place the streetlight, three.js's `build`. Shadows do not fall
        on it, as in three.js.

        Args:
            placements: One matrix a streetlight.

        Returns:
            The instances, named `Streetlights`.

        Raises:
            Error: If a size is not positive.
        """
        return placed("Streetlights", self.geometry(), placements, False)


def _lens_disc(y: Float64, z: Float64, id: PartId) raises -> BufferGeometry:
    """Return one lens of a signal head, facing back down the arm."""
    return part(
        _moved(_turned_x(_cylinder(0.13, 0.13, 0.08, 12), pi / 2), 0, y, z), id
    )


@fieldwise_init
struct TrafficlightGenerator(Copyable, Movable):
    """A New York traffic signal, three.js's `TrafficlightGenerator`: a
    pole with a mast arm over the road toward +z, a three-lens head at its
    end and a pedestrian signal on the pole."""

    # The pole's height.
    var height: Length
    # How far the mast arm reaches over the road.
    var reach: Length
    # The pole's radius.
    var radius: Length

    def __init__(out self):
        """Create three.js's default traffic signal."""
        self.height = Length(6.5, METER)
        self.reach = Length(5.5, METER)
        self.radius = Length(0.14, METER)

    def geometry(self) raises -> BufferGeometry:
        """Return the signal, three.js's `buildTrafficlightGeometry`.

        Returns:
            The model, indexed, with a `partId`: metal, or the red, amber
            or green lens.

        Raises:
            Error: If a size is not positive.
        """
        var h = meters(self.height)
        var reach = meters(self.reach)
        var r = meters(self.radius)
        var arm_y = h - 0.3
        var head_z = reach - 0.6
        var head_y = arm_y - 1.05
        var drop = arm_y - (head_y + 0.475)
        var lens_z = head_z - 0.19
        return merge_geometries(
            [
                part(_moved(_cylinder(0.2, 0.26, 0.5, 8), 0, 0.25, 0), SIGNAL_METAL),
                part(_moved(_cylinder(r, r * 1.2, h, 8), 0, h / 2, 0), SIGNAL_METAL),
                part(
                    _moved(
                        _turned_x(_cylinder(0.07, 0.1, reach, 8), pi / 2),
                        0,
                        arm_y,
                        reach / 2,
                    ),
                    SIGNAL_METAL,
                ),
                part(
                    _moved(
                        _cylinder(0.05, 0.05, drop, 6),
                        0,
                        head_y + 0.475 + drop / 2,
                        head_z,
                    ),
                    SIGNAL_METAL,
                ),
                part(_moved(_box(0.4, 0.42, 0.2), 0, 2.6, r + 0.1), SIGNAL_METAL),
                part(_moved(_box(0.36, 0.95, 0.32), 0, head_y, head_z), SIGNAL_METAL),
                _lens_disc(head_y + 0.28, lens_z, SIGNAL_RED),
                _lens_disc(head_y, lens_z, SIGNAL_AMBER),
                _lens_disc(head_y - 0.28, lens_z, SIGNAL_GREEN),
            ]
        )

    def build(self, placements: List[Matrix4]) raises -> Instances:
        """Place the signal, three.js's `build`.

        Args:
            placements: One matrix a signal.

        Returns:
            The instances, named `Trafficlights`.

        Raises:
            Error: If a size is not positive.
        """
        return placed("Trafficlights", self.geometry(), placements)


@fieldwise_init
struct TrashcanGenerator(Copyable, Movable):
    """The green wire-mesh litter basket of New York, three.js's
    `TrashcanGenerator`: an open drum with a heavy rim, a foot ring, a
    bag inside and a mound of refuse cresting over the rim."""

    var radius: Length
    var height: Length

    def __init__(out self):
        """Create three.js's default basket."""
        self.radius = Length(0.28, METER)
        self.height = Length(0.8, METER)

    def geometry(self) raises -> BufferGeometry:
        """Return the basket, three.js's `buildTrashcanGeometry`.

        Returns:
            The model, indexed, with a `partId`: the mesh, the rims, or
            the trash.

        Raises:
            Error: If a size is not positive.
        """
        var r = meters(self.radius)
        var h = meters(self.height)
        var mound = icosahedron(_l(r * 0.82), 1)
        mound.scale(1, 0.55, 1)
        return merge_geometries(
            [
                part(_moved(_cylinder(r, r * 0.92, h, 16, True), 0, h / 2, 0), CAN_MESH),
                part(_moved(_cylinder(r + 0.03, r + 0.03, 0.07, 16), 0, h, 0), CAN_RIM),
                part(_moved(_cylinder(r * 0.92, r * 0.86, 0.06, 16), 0, 0.03, 0), CAN_RIM),
                part(_moved(_cylinder(r * 0.86, r * 0.7, h * 0.9, 12), 0, h * 0.5, 0), CAN_TRASH),
                part(_moved(mound^, 0.02, h + 0.02, -0.01), CAN_TRASH),
            ]
        )

    def build(self, placements: List[Matrix4]) raises -> Instances:
        """Place the basket, three.js's `build`.

        Args:
            placements: One matrix a basket.

        Returns:
            The instances, named `Trashcans`.

        Raises:
            Error: If a size is not positive.
        """
        return placed("Trashcans", self.geometry(), placements)


@fieldwise_init
struct BenchGenerator(Copyable, Movable):
    """A public bench, three.js's `BenchGenerator`: timber slats on two
    cast-iron end frames that curl into armrests, with a reclined back.
    It runs along x and seats toward +z."""

    var length: Length
    var depth: Length
    var seat_height: Length
    var back_height: Length

    def __init__(out self):
        """Create three.js's default bench."""
        self.length = Length(1.8, METER)
        self.depth = Length(0.55, METER)
        self.seat_height = Length(0.45, METER)
        self.back_height = Length(0.85, METER)

    def geometry(self) raises -> BufferGeometry:
        """Return the bench, three.js's `buildBenchGeometry`.

        Returns:
            The model, indexed, with a `partId`: wood, or iron.

        Raises:
            Error: If a size is not positive.
        """
        var half_length = meters(self.length) / 2
        var seat_y = meters(self.seat_height)
        var back_y = meters(self.back_height)
        var front_z = meters(self.depth) / 2 - 0.075
        var back_z = -front_z
        var parts = List[BufferGeometry]()
        for side in range(2):  # pragma: no branch
            var x = Float64(side * 2 - 1) * (half_length - 0.07)
            parts.append(
                part(_moved(_box(0.05, seat_y, 0.06), x, seat_y / 2, front_z), BENCH_IRON)
            )
            parts.append(
                part(_moved(_box(0.05, back_y, 0.06), x, back_y / 2, back_z), BENCH_IRON)
            )
            parts.append(
                part(
                    _moved(_box(0.06, 0.05, front_z - back_z + 0.1), x, seat_y - 0.04, 0),
                    BENCH_IRON,
                )
            )
            parts.append(
                part(_moved(_box(0.05, 0.22, 0.05), x, seat_y + 0.11, front_z), BENCH_IRON)
            )
            parts.append(
                part(
                    _moved(_box(0.05, 0.05, front_z - back_z + 0.06), x, seat_y + 0.22, 0),
                    BENCH_IRON,
                )
            )
            parts.append(
                part(
                    _moved(
                        _turned_x(_box(0.05, 0.16, 0.05), -0.6),
                        x,
                        seat_y + 0.18,
                        front_z + 0.07,
                    ),
                    BENCH_IRON,
                )
            )
        var slat_length = meters(self.length) - 0.1
        var z0 = back_z + 0.02
        var z1 = front_z - 0.02
        for i in range(5):  # pragma: no branch
            var z = z0 + (z1 - z0) * (Float64(i) / 4)
            parts.append(
                part(_moved(_box(slat_length, 0.03, 0.07), 0, seat_y, z), BENCH_WOOD)
            )
        for i in range(3):  # pragma: no branch
            var t = Float64(i) / 2
            parts.append(
                part(
                    _moved(
                        _turned_x(_box(slat_length, 0.09, 0.025), 0.18),
                        0,
                        seat_y + 0.13 + t * 0.27,
                        back_z + 0.01 - t * 0.06,
                    ),
                    BENCH_WOOD,
                )
            )
        return merge_geometries(parts)

    def build(self, placements: List[Matrix4]) raises -> Instances:
        """Place the bench, three.js's `build`.

        Args:
            placements: One matrix a bench.

        Returns:
            The instances, named `Benches`.

        Raises:
            Error: If a size is not positive.
        """
        return placed("Benches", self.geometry(), placements)


@fieldwise_init
struct HydrantGenerator(Copyable, Movable):
    """A cast-iron fire hydrant, three.js's `HydrantGenerator`: a barrel on
    a flared footing, a domed bonnet with an operating nut, two side
    outlets and a larger pumper outlet facing +z."""

    # The barrel's radius.
    var radius: Length
    # The barrel's height.
    var height: Length

    def __init__(out self):
        """Create three.js's default hydrant."""
        self.radius = Length(0.13, METER)
        self.height = Length(0.55, METER)

    def geometry(self) raises -> BufferGeometry:
        """Return the hydrant, three.js's `buildHydrantGeometry`.

        Returns:
            The model, indexed, with a `partId`: the body, or a bare cap.

        Raises:
            Error: If a size is not positive.
        """
        var r = meters(self.radius)
        var h = meters(self.height)
        var dome = sphere(
            _l(r * 0.65), 10, 4, _a(0), _a(pi * 2), _a(0), _a(pi / 2)
        )
        var parts: List[BufferGeometry] = [
            part(_moved(_cylinder(r * 1.5, r * 1.7, 0.08, 12), 0, 0.04, 0), HYDRANT_BODY),
            part(_moved(_cylinder(r, r * 1.1, h, 12), 0, 0.08 + h / 2, 0), HYDRANT_BODY),
            part(_moved(_cylinder(r * 0.65, r, 0.12, 12), 0, 0.69, 0), HYDRANT_BODY),
            part(_moved(dome^, 0, 0.75, 0), HYDRANT_BODY),
            part(_moved(_cylinder(r * 1.18, r * 1.18, 0.035, 12), 0, 0.645, 0), HYDRANT_BODY),
            part(_moved(_cylinder(r * 1.28, r * 1.28, 0.04, 12), 0, 0.11, 0), HYDRANT_BODY),
            part(_side_stub(0.06, 0.12, -(r + 0.03)), HYDRANT_BODY),
            part(_side_stub(0.06, 0.12, r + 0.03), HYDRANT_BODY),
            part(
                _moved(_turned_x(_cylinder(0.075, 0.075, 0.12, 8), pi / 2), 0, 0.4, r + 0.03),
                HYDRANT_BODY,
            ),
            part(_side_stub(0.07, 0.025, -(r + 0.102)), HYDRANT_CAP),
            part(_side_stub(0.07, 0.025, r + 0.102), HYDRANT_CAP),
            part(
                _moved(_turned_x(_cylinder(0.085, 0.085, 0.025, 8), pi / 2), 0, 0.4, r + 0.102),
                HYDRANT_CAP,
            ),
            part(_moved(_cylinder(0.05, 0.05, 0.07, 6), 0, 0.87, 0), HYDRANT_CAP),
        ]
        return merge_geometries(parts)

    def build(self, placements: List[Matrix4]) raises -> Instances:
        """Place the hydrant, three.js's `build`.

        Args:
            placements: One matrix a hydrant.

        Returns:
            The instances, named `Hydrants`.

        Raises:
            Error: If a size is not positive.
        """
        return placed("Hydrants", self.geometry(), placements)


def _side_stub(radius: Float64, length: Float64, x: Float64) raises -> BufferGeometry:
    """Return a hydrant's side outlet or cap: a short cylinder along x."""
    return _moved(
        _turned_z(_cylinder(radius, radius, length, 8), pi / 2), x, 0.45, 0
    )


def clump_hash(x: Float32, y: Float32, z: Float32) -> Float64:
    """Return the street tree's position hash, three.js's `hash` in
    `StreetTreeGenerator.js`.

    Args:
        x: The x of a vertex, as its attribute stores it.
        y: The y.
        z: The z.

    Returns:
        A number from zero up to one.
    """
    var s = (
        sin(Float64(x) * 127.1 + Float64(y) * 311.7 + Float64(z) * 74.7)
        * 43758.5453
    )
    return s - floor(s)


def leaf_clump(
    radius: Float64, x: Float64, y: Float64, z: Float64
) raises -> BufferGeometry:
    """Return one leaf clump, three.js's `leafClump`: a welded
    icosahedron, flattened, its vertices pushed in and out by a hash, and
    its normals blended toward the shared crown sphere.

    Args:
        radius: The clump's radius, in meters.
        x: The x of its center, in meters.
        y: The y of its center.
        z: The z of its center.

    Returns:
        The clump, indexed.

    Raises:
        Error: If the radius is not positive.
    """
    var ball = icosahedron(_l(radius), 1)
    ball.scale(1, 0.82, 1)
    var g = merge_vertices(ball)
    var count = g.vertex_count()
    var jittered = List[Float32]()
    for i in range(count):  # pragma: no branch
        var v = g.attribute_view(String(POSITION)).vector3(i)
        var k = 0.86 + clump_hash(v.x, v.y, v.z) * 0.3
        jittered.append(Float32(Float64(v.x) * k))
        jittered.append(Float32(Float64(v.y) * k))
        jittered.append(Float32(Float64(v.z) * k))
    g.set_attribute(String(POSITION), BufferAttribute(jittered^, 3))
    g = _moved(g^, x, y, z)
    g.compute_vertex_normals()
    var blended = List[Float32]()
    var center = Vec3d(0, CROWN_CENTER_Y, CROWN_CENTER_Z)
    for i in range(count):  # pragma: no branch
        var p = g.attribute_view(String(POSITION)).vector3(i)
        var n = g.attribute_view(String(NORMAL)).vector3(i)
        var out = (
            Vec3d(Float64(p.x), Float64(p.y), Float64(p.z)) - center
        ).normalized()
        blended.append(Float32(Float64(n.x) * 0.45 + out.x * 0.55))
        blended.append(Float32(Float64(n.y) * 0.45 + out.y * 0.55))
        blended.append(Float32(Float64(n.z) * 0.45 + out.z * 0.55))
    g.set_attribute(String(NORMAL), BufferAttribute(blended^, 3))
    g.normalize_normals()
    return g^


@fieldwise_init
struct StreetTreeGenerator(Copyable, Movable):
    """A young street tree in a curbside pit, three.js's
    `StreetTreeGenerator`: a flared trunk rising through a cast-iron
    grate, four bare limbs, and a crown of six jittered leaf clumps."""

    # The clear trunk below the canopy.
    var trunk_height: Length
    # The trunk's radius at its base.
    var trunk_radius: Length

    def __init__(out self):
        """Create three.js's default street tree."""
        self.trunk_height = Length(2.6, METER)
        self.trunk_radius = Length(0.18, METER)

    def geometry(self) raises -> BufferGeometry:
        """Return the tree, three.js's `buildStreetTreeGeometry`.

        Returns:
            The model, indexed, with a `partId`: the trunk and soil, the
            leaves, or the grate.

        Raises:
            Error: If a size is not positive.
        """
        var r = meters(self.trunk_radius)
        var h = meters(self.trunk_height)
        var grate = ring(_l(0.24), _l(0.62), 16, 4)
        grate.rotate_x(_a(-pi / 2))
        var wood: List[BufferGeometry] = [
            _moved(_cylinder(r * 1.15, r * 1.6, 0.22, 8), 0, 0.11, 0),
            _moved(_cylinder(r * 0.55, r * 1.1, h, 8), 0, h / 2, 0),
        ]
        var limb_x: List[Float64] = [0.5, -0.45, 0.1, -0.15]
        var limb_z: List[Float64] = [0.2, -0.3, -0.55, 0.5]
        var limb_length: List[Float64] = [1.5, 1.4, 1.2, 1.3]
        for i in range(4):  # pragma: no branch
            var length = limb_length[i]
            var limb = _moved(_cylinder(0.03, 0.07, length, 5), 0, length / 2, 0)
            limb = _turned_z(_turned_x(limb^, limb_x[i]), limb_z[i])
            wood.append(_moved(limb^, 0, h - 0.15, 0))
        var parts: List[BufferGeometry] = [
            part(_moved(_cylinder(0.24, 0.3, 0.05, 10), 0, 0.025, 0), TREE_TRUNK),
            part(_moved(grate^, 0, 0.045, 0), TREE_GRATE),
            part(merge_geometries(wood), TREE_TRUNK),
            part(leaf_clump(2.15, 0, 3.9, 0.1), TREE_LEAF),
            part(leaf_clump(1.5, 1.15, 4.35, 0.5), TREE_LEAF),
            part(leaf_clump(1.45, -1.05, 3.55, -0.5), TREE_LEAF),
            part(leaf_clump(1.3, 0.35, 4.75, -0.65), TREE_LEAF),
            part(leaf_clump(1.25, -0.35, 4.5, 0.9), TREE_LEAF),
            part(leaf_clump(1.1, 0.9, 3.3, -0.85), TREE_LEAF),
        ]
        return merge_geometries(parts)

    def build(self, placements: List[Matrix4]) raises -> Instances:
        """Place the tree, three.js's `build`.

        Args:
            placements: One matrix a tree.

        Returns:
            The instances, named `StreetTrees`.

        Raises:
            Error: If a size is not positive.
        """
        return placed("StreetTrees", self.geometry(), placements)
