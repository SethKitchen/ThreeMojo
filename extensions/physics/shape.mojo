# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Collision shapes, their surface materials and their mass properties.

A body has one shape. The shape is in the body's own frame: a sphere, a
box, a capsule along the local z axis, a convex hull of points, or a
static triangle mesh. The first four can move. A mesh is the road, the
sidewalks and the props of a town, and it never moves.

A box and a convex hull share one form, `Polyhedron`: corners, face planes
with the corners of each face in order, and edges. The contact code
treats both the same way.

`PhysicsMaterial` is a surface: a friction and a restitution. The
default material and the mixing rule follow Box2D (MIT): a friction of
0.6 and a restitution of 0. Two touching materials use the geometric mean
of the frictions, so a surface with no friction makes any contact
frictionless, and the larger of the restitutions, so a bouncy surface
bounces off anything.

The inertia of a convex hull is the exact inertia of a solid of uniform
density, from the signed tetrahedra that join each face to a point
inside. That is the method of Blow and Binstock, "How to find the inertia
tensor (or other mass properties) of a 3D solid body represented by a
triangle mesh" (2004).
"""

from math.convex_hull import ConvexHull
from math.matrix3 import Matrix3
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import atan2, isfinite, pi, sqrt
from units.si import Length, METER

# Two hull faces are one face when their normals and offsets agree this
# well.
comptime _COPLANAR = Float32(1e-4)


@fieldwise_init
struct ShapeKind(Equatable, ImplicitlyCopyable, Writable):
    """What a collision shape is."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the five shapes.

        Returns:
            Whether the value is 0 to 4.
        """
        return self.value >= 0 and self.value <= 4


comptime SPHERE = ShapeKind(0)
comptime BOX = ShapeKind(1)
# A segment along the local z axis with a radius around it.
comptime CAPSULE = ShapeKind(2)
comptime CONVEX = ShapeKind(3)
# Static triangles. A mesh never moves.
comptime MESH = ShapeKind(4)


@fieldwise_init
struct PhysicsMaterial(ImplicitlyCopyable):
    """A surface: its friction and its restitution."""

    # The Coulomb friction coefficient. Zero or more.
    var friction: Float32
    # The ratio of the speed apart after a hit to the speed together
    # before it. Zero to one.
    var restitution: Float32

    @staticmethod
    def default() -> PhysicsMaterial:
        """Return the default material, Box2D's default.

        Returns:
            A friction of 0.6 and a restitution of 0.
        """
        return PhysicsMaterial(0.6, 0)

    def check(self) raises:
        """Refuse a material no surface can have.

        Raises:
            Error: If the friction is negative or not finite, or the
                restitution is outside zero to one.
        """
        if not (isfinite(self.friction) and self.friction >= 0):
            raise Error("A friction must be zero or more and finite")
        if not (self.restitution >= 0 and self.restitution <= 1):
            raise Error("A restitution must be from zero to one")

    def combine(self, other: Self) -> PhysicsMaterial:
        """Return what two touching surfaces use, Box2D's mixing rule.

        Args:
            other: The other surface.

        Returns:
            The geometric mean of the frictions and the larger
            restitution.
        """
        return PhysicsMaterial(
            # The product can exceed Float32 while its square root fits.
            Float32(sqrt(Float64(self.friction) * Float64(other.friction))),
            max(self.restitution, other.restitution),
        )


def cross(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product of two vectors.

    The formula is the same in a left-handed frame. What changes is only
    which way a positive turn looks.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The product a x b.
    """
    return Vector3(
        a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x
    )


def unit_or(v: Vector3, fallback: Vector3) -> Vector3:
    """Return a vector scaled to unit length, or a fallback for a zero one.

    Args:
        v: The vector.
        fallback: What to return when `v` has no direction.

    Returns:
        The unit vector.
    """
    var length = v.length()
    if length > 1e-12:
        return v / length
    return fallback


def any_perpendicular(n: Vector3) -> Vector3:
    """Return a unit vector at right angles to a unit vector.

    Args:
        n: A unit vector.

    Returns:
        A unit vector u with u . n = 0.
    """
    if abs(n.x) < 0.57:
        return unit_or(cross(n, Vector3(1, 0, 0)), Vector3(0, 1, 0))
    return unit_or(cross(n, Vector3(0, 1, 0)), Vector3(0, 0, 1))


struct Polyhedron(Copyable, Movable):
    """A convex solid as corners, faces and edges.

    Face `f` has the outward unit normal `normals[f]` and the plane
    `normals[f] . x = offsets[f]`. Its corners are
    `face_corners[face_start[f]]` up to, and not including,
    `face_corners[face_start[f + 1]]`, in counter-clockwise order seen from
    outside.
    """

    var vertices: List[Vector3]
    var normals: List[Vector3]
    var offsets: List[Float32]
    var face_start: List[Int]
    var face_corners: List[Int]
    # Edge e joins `vertices[edge_a[e]]` and `vertices[edge_b[e]]`.
    var edge_a: List[Int]
    var edge_b: List[Int]

    def __init__(out self):
        """Create a polyhedron with no corners."""
        self.vertices = List[Vector3]()
        self.normals = List[Vector3]()
        self.offsets = List[Float32]()
        self.face_start = [0]
        self.face_corners = List[Int]()
        self.edge_a = List[Int]()
        self.edge_b = List[Int]()

    def face_count(self) -> Int:
        """Return how many faces the polyhedron has.

        Returns:
            The count.
        """
        return len(self.normals)

    def add_face(mut self, corners: List[Int]):
        """Add a face from its corners, and its new edges.

        Args:
            corners: The corner indices, counter-clockwise from outside.
                There must be three at least, not all on one line.
        """
        var a = self.vertices[corners[0]]
        var b = self.vertices[corners[1]]
        var normal = Vector3(0, 0, 0)
        # `corners[1]` above: there are two at least, and a face has three.
        for i in range(2, len(corners)):  # pragma: no branch
            normal = normal + cross(b - a, self.vertices[corners[i]] - a)
        normal = unit_or(normal, Vector3(0, 0, 1))
        self.normals.append(normal)
        self.offsets.append(normal.dot(a))
        # `corners[0]` above: the list is not empty.
        for i in range(len(corners)):  # pragma: no branch
            self.face_corners.append(corners[i])
            self._add_edge(corners[i], corners[(i + 1) % len(corners)])
        self.face_start.append(len(self.face_corners))

    def _add_edge(mut self, a: Int, b: Int):
        for e in range(len(self.edge_a)):
            if self.edge_a[e] == b and self.edge_b[e] == a:
                return
        self.edge_a.append(a)
        self.edge_b.append(b)

    def transformed(self, position: Vector3, rotation: Matrix3) -> Polyhedron:
        """Return this polyhedron turned and then moved.

        Args:
            position: Where the local origin goes.
            rotation: The turn, a pure rotation.

        Returns:
            The polyhedron in the parent frame.
        """
        var out = self.copy()
        for i in range(len(out.vertices)):
            out.vertices[i] = rotation.transform(self.vertices[i]) + position
        for f in range(len(out.normals)):
            out.normals[f] = rotation.transform(self.normals[f])
            out.offsets[f] = out.normals[f].dot(
                out.vertices[self.face_corners[self.face_start[f]]]
            )
        return out^

    def center(self) -> Vector3:
        """Return the mean of the corners.

        Returns:
            A point inside the solid.
        """
        var sum = Vector3(0, 0, 0)
        for v in self.vertices:
            sum = sum + v
        return sum / Float32(len(self.vertices))

    def support(self, direction: Vector3) -> Float32:
        """Return how far the solid reaches along a direction.

        Args:
            direction: The direction.

        Returns:
            The largest `direction . v` over the corners.
        """
        var best = self.vertices[0].dot(direction)
        for i in range(1, len(self.vertices)):
            best = max(best, self.vertices[i].dot(direction))
        return best

    @staticmethod
    def box(half: Vector3) -> Polyhedron:
        """Return a box centered on the origin.

        Args:
            half: Half the size along x, y and z, in meters.

        Returns:
            Eight corners, six faces and twelve edges.
        """
        var out = Polyhedron()
        for i in range(8):  # pragma: no branch
            out.vertices.append(
                Vector3(
                    half.x if (i & 1) != 0 else -half.x,
                    half.y if (i & 2) != 0 else -half.y,
                    half.z if (i & 4) != 0 else -half.z,
                )
            )
        out.add_face([0, 4, 6, 2])
        out.add_face([1, 3, 7, 5])
        out.add_face([0, 1, 5, 4])
        out.add_face([2, 6, 7, 3])
        out.add_face([0, 2, 3, 1])
        out.add_face([4, 5, 7, 6])
        return out^

    @staticmethod
    def triangle(triangle: Triangle) -> Polyhedron:
        """Return a triangle as a flat solid with one face, its front.

        Args:
            triangle: The triangle. Its front is where (b - a) x (c - a)
                points.

        Returns:
            Three corners, one face and three edges.
        """
        var out = Polyhedron()
        out.vertices = [triangle.a, triangle.b, triangle.c]
        out.add_face([0, 1, 2])
        return out^

    @staticmethod
    def hull(points: List[Vector3]) raises -> Polyhedron:
        """Return the convex hull of points, with coplanar faces merged.

        Args:
            points: Four points at least, not all on one plane.

        Returns:
            The hull.

        Raises:
            Error: If `ConvexHull` refuses the points.
        """
        var hull = ConvexHull(points)
        var out = Polyhedron()
        # Map from an input point to its corner, -1 while unused.
        var corner = List[Int](length=len(points), fill=-1)
        var plane_normals = List[Vector3]()
        var plane_members = List[List[Int]]()
        # A hull has four faces at least.
        for f in range(hull.face_count()):  # pragma: no branch
            var n = hull.face_normal(f)
            var ids = [
                hull.face_vertex(f, 0),
                hull.face_vertex(f, 1),
                hull.face_vertex(f, 2),
            ]
            var plane = _find_plane(plane_normals, n)
            if plane < 0:
                plane = len(plane_normals)
                plane_normals.append(n)
                plane_members.append(List[Int]())
            for id in ids:  # pragma: no branch
                if corner[id] < 0:
                    corner[id] = len(out.vertices)
                    out.vertices.append(points[id])
                if not (corner[id] in plane_members[plane]):
                    plane_members[plane].append(corner[id])
        # A hull has four faces at least.
        for p in range(len(plane_normals)):  # pragma: no branch
            out.add_face(
                _ordered(out.vertices, plane_members[p], plane_normals[p])
            )
        return out^


def _find_plane(normals: List[Vector3], n: Vector3) -> Int:
    # Two faces of a convex hull that face the same way lie in one plane:
    # the one farther out would leave the other inside.
    for p in range(len(normals)):
        if normals[p].dot(n) > 1 - _COPLANAR:
            return p
    return -1


def _ordered(
    vertices: List[Vector3], members: List[Int], normal: Vector3
) -> List[Int]:
    """Return the corners of one face in counter-clockwise order."""
    var middle = Vector3(0, 0, 0)
    # A face has three corners at least.
    for m in members:  # pragma: no branch
        middle = middle + vertices[m]
    middle = middle / Float32(len(members))
    var u = any_perpendicular(normal)
    var w = cross(normal, u)
    var angles = List[Float32]()
    for m in members:  # pragma: no branch
        var r = vertices[m] - middle
        angles.append(atan2(r.dot(w), r.dot(u)))
    var out = members.copy()
    # Insertion sort by angle: a face has few corners.
    for i in range(1, len(out)):  # pragma: no branch
        var j = i
        while j > 0 and angles[j - 1] > angles[j]:
            angles.swap_elements(j - 1, j)
            out.swap_elements(j - 1, j)
            j -= 1
    return out^


struct MassProperties(ImplicitlyCopyable):
    """Where a solid's mass centers, and how it resists a turn."""

    # The center of mass, in the shape's frame.
    var center: Vector3
    # The inertia tensor about the center of mass, in kg m^2.
    var inertia: Matrix3

    def __init__(out self, center: Vector3, inertia: Matrix3):
        """Create mass properties.

        Args:
            center: The center of mass, in meters.
            inertia: The inertia tensor about it.
        """
        self.center = center
        self.inertia = inertia


def _diagonal(x: Float32, y: Float32, z: Float32) -> Matrix3:
    var m = Matrix3()
    m.elements[0] = x
    m.elements[4] = y
    m.elements[8] = z
    return m


struct Shape(Copyable, Movable):
    """One collision shape in its body's frame."""

    var kind: ShapeKind
    # The sphere's or the capsule's radius, in meters.
    var radius: Float32
    # Half the capsule's segment, along its local z, in meters.
    var half_height: Float32
    # The corners, faces and edges of a box or a hull.
    var polyhedron: Polyhedron
    # The triangles of a mesh.
    var triangles: List[Triangle]

    def __init__(out self, kind: ShapeKind):
        """Create an empty shape of one kind. Use the named constructors.

        Args:
            kind: What the shape is.
        """
        self.kind = kind
        self.radius = 0
        self.half_height = 0
        self.polyhedron = Polyhedron()
        self.triangles = List[Triangle]()

    @staticmethod
    def sphere(radius: Length) raises -> Shape:
        """Return a sphere centered on the body's origin.

        Args:
            radius: The radius. It must be more than zero.

        Returns:
            The shape.

        Raises:
            Error: If the radius is not more than zero and finite.
        """
        _check_size(radius.value)
        var out = Shape(SPHERE)
        out.radius = radius.value
        return out^

    @staticmethod
    def box(x: Length, y: Length, z: Length) raises -> Shape:
        """Return a box centered on the body's origin.

        Args:
            x: Half the size along x.
            y: Half the size along y.
            z: Half the size along z.

        Returns:
            The shape.

        Raises:
            Error: If a half size is not more than zero and finite.
        """
        _check_size(x.value)
        _check_size(y.value)
        _check_size(z.value)
        var out = Shape(BOX)
        out.polyhedron = Polyhedron.box(Vector3(x.value, y.value, z.value))
        return out^

    @staticmethod
    def capsule(radius: Length, half_height: Length) raises -> Shape:
        """Return a capsule along the body's z axis, centered on its origin.

        Args:
            radius: The radius. It must be more than zero.
            half_height: Half the length of the segment between the two
                half spheres. It can be zero.

        Returns:
            The shape. It reaches `half_height + radius` up and down.

        Raises:
            Error: If the radius is not more than zero and finite, or the
                half height is negative or not finite.
        """
        _check_size(radius.value)
        if not (isfinite(half_height.value) and half_height.value >= 0):
            raise Error("A capsule's half height must be zero or more")
        var out = Shape(CAPSULE)
        out.radius = radius.value
        out.half_height = half_height.value
        return out^

    @staticmethod
    def convex(points: List[Vector3]) raises -> Shape:
        """Return the convex hull of points.

        Args:
            points: The points, in the body's frame, in meters.

        Returns:
            The shape.

        Raises:
            Error: If there are fewer than four points, or they are not
                finite, or they lie on one plane.
        """
        var out = Shape(CONVEX)
        out.polyhedron = Polyhedron.hull(points)
        return out^

    @staticmethod
    def mesh(var triangles: List[Triangle]) raises -> Shape:
        """Return a static triangle mesh.

        Args:
            triangles: The triangles, in the body's frame. Each is solid
                from its front, where (b - a) x (c - a) points.

        Returns:
            The shape.

        Raises:
            Error: If there are no triangles.
        """
        if len(triangles) == 0:
            raise Error("A mesh needs at least one triangle")
        var out = Shape(MESH)
        out.triangles = triangles^
        return out^

    def mass_properties(self, mass: Float32) raises -> MassProperties:
        """Return the center of mass and inertia of the solid shape.

        Args:
            mass: The mass, in kilograms.

        Returns:
            The mass properties, for a uniform density.

        Raises:
            Error: If the shape is a mesh, which has no volume.
        """
        if self.kind == SPHERE:
            var i = 0.4 * mass * self.radius * self.radius
            return MassProperties(Vector3(0, 0, 0), _diagonal(i, i, i))
        if self.kind == CAPSULE:
            return MassProperties(Vector3(0, 0, 0), self._capsule(mass))
        if self.kind == MESH:
            raise Error("A mesh is static and has no mass")
        return _polyhedron_mass(self.polyhedron, mass)

    def _capsule(self, mass: Float32) -> Matrix3:
        var r = self.radius
        var h = 2 * self.half_height
        var cylinder = Float32(pi) * r * r * h
        var ball = Float32(4.0 / 3.0 * pi) * r * r * r
        var mc = mass * cylinder / (cylinder + ball)
        var ms = mass - mc
        var axial = mc * r * r * 0.5 + ms * 0.4 * r * r
        var across = mc * (r * r * 0.25 + h * h / 12) + ms * (
            0.4 * r * r + h * h * 0.25 + 0.375 * h * r
        )
        return _diagonal(across, across, axial)


def _check_size(value: Float32) raises:
    if not (isfinite(value) and value > 0):
        raise Error("A shape's size must be more than zero and finite")


def _polyhedron_mass(poly: Polyhedron, mass: Float32) -> MassProperties:
    """Return the mass properties of a solid polyhedron of uniform density.

    Each face is cut into a fan of triangles. Each triangle and a point
    inside make a tetrahedron, whose volume, first moment and second
    moment add up.
    """
    var origin = poly.center()
    var volume = Float32(0)
    var moment = Vector3(0, 0, 0)
    # The covariance: the integral of x x^T over the solid.
    var c = List[Float32](length=9, fill=0)
    # A solid has four faces at least.
    for f in range(poly.face_count()):  # pragma: no branch
        var first = poly.face_start[f]
        var a = poly.vertices[poly.face_corners[first]] - origin
        # A face has three corners at least: one triangle of the fan.
        for k in range(
            first + 1, poly.face_start[f + 1] - 1
        ):  # pragma: no branch
            var b = poly.vertices[poly.face_corners[k]] - origin
            var d = poly.vertices[poly.face_corners[k + 1]] - origin
            var det = a.dot(cross(b, d))
            volume += det / 6
            moment = moment + (a + b + d) * (det / 24)
            var s = a + b + d
            var p = [a, b, d]
            for i in range(3):  # pragma: no branch
                for j in range(3):  # pragma: no branch
                    var sum = component(s, i) * component(s, j)
                    for v in p:  # pragma: no branch
                        sum += component(v, i) * component(v, j)
                    c[i * 3 + j] += det * sum / 120
    var density = mass / volume
    var center = moment / volume
    var inertia = Matrix3()
    for i in range(3):  # pragma: no branch
        for j in range(3):  # pragma: no branch
            # Shift the covariance from the origin to the center of mass.
            var cov = density * (
                c[i * 3 + j]
                - volume * component(center, i) * component(center, j)
            )
            inertia.elements[j * 3 + i] = -cov
    var trace = -(
        inertia.elements[0] + inertia.elements[4] + inertia.elements[8]
    )
    for i in range(3):  # pragma: no branch
        inertia.elements[i * 4] += trace
    return MassProperties(center + origin, inertia)


def component(v: Vector3, i: Int) -> Float32:
    """Return one component of a vector by index.

    Args:
        v: The vector.
        i: 0 for x, 1 for y, anything else for z.

    Returns:
        The component.
    """
    if i == 0:
        return v.x
    if i == 1:
        return v.y
    return v.z
