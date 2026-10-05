# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Owned, deliberately frozen ray-query state.

A capture owns bounds, world-space narrow geometry, materials and a distinct
owner namespace. Queries never read the source world. World mutation and
source destruction do not invalidate a capture. Build another capture to
observe a new state; there is no bounds-only refit of a query snapshot.

The supported API has no mutating methods. Mojo 1.1 does not enforce field
privacy. The underscore fields are implementation storage, not an enforced
mutation or invalidation boundary. Editing them is outside this API.

Static mesh geometry is the world's registered triangle view, exactly as
PhysicsWorld.raycast reads it. Mesh pose edits do not rebuild that view.
A capture preserves both its dirty linear path and clean octree tie order.
Primitive queries use owned geometry. A proved coordinate-axis admission
rule can use conservative transverse bounds. Other shapes and rays use the
owned linear path. Tight mathematical half-ray bounds cannot safely cull
every answer from the existing Float32 narrow kernels.
"""

from extensions.physics.body import BodyId
from extensions.physics.collide import WorldShape
from extensions.physics.shape import (
    CAPSULE,
    MESH,
    SPHERE,
    PhysicsMaterial,
    Polyhedron,
    _finite_vector,
    cross,
    component,
    unit_or,
)
from extensions.physics.world import (
    PhysicsWorld,
    RaycastHit,
    _box_of,
    _cylinder_hit,
    _polyhedron_hit,
    _sphere_hit,
)
from math.bounds import Box3
from math.octree import Octree
from math.quaternion import Quaternion
from math.ray import Ray
from math.sort_utils import stable_sort
from extensions.physics.primitive_index import _PrimitiveIndex
from math.triangle import Line3, Triangle
from math.vector3 import Vector3
from std.math import inf, isfinite, isnan
from std.memory import ArcPointer, bitcast
from units.si import Length


@fieldwise_init
struct SnapshotOwner(Equatable, ImplicitlyCopyable):
    """A historical body slot in one capture, never a live world handle.

    Args:
        source_body: The source body's index at capture time.
        _capture: The retained capture identity. Internal construction only.

    Returns:
        A value that remains distinct from owners of other captures.

    Raises:
        None.
    """

    var source_body: BodyId
    """The source slot at capture time, never a verified live handle."""
    var _capture: ArcPointer[Int]

    def is_valid(self) -> Bool:
        """Return whether the historical slot is nonnegative.

        Returns:
            True for a nonnegative slot. Use check_owner for membership.
        """
        return self.source_body.is_valid()

    def __eq__(self, other: Self) -> Bool:
        """Compare the capture identity and the historical slot.

        Args:
            other: The owner to compare.

        Returns:
            True only for the same slot in the same capture.
        """
        return (
            self._capture.ptr() == other._capture.ptr()
            and self.source_body == other.source_body
        )


@fieldwise_init
struct SnapshotRaycastHit(ImplicitlyCopyable):
    """A ray hit whose owner is historical and capture-scoped.

    Args:
        owner: The historical owner, not a live BodyId.
        point: The captured surface point, in meters.
        normal: Its outward unit normal.
        distance: The ray distance, in meters.
        material: The captured material value.

    Returns:
        An owned hit value, independent of world and snapshot lifetime.

    Raises:
        None.
    """

    var owner: SnapshotOwner
    """The capture-scoped historical owner of the surface."""
    var point: Vector3
    """The captured surface position, in meters."""
    var normal: Vector3
    """The existing narrow kernel's outward surface normal."""
    var distance: Float32
    """The existing narrow kernel's ray distance, in meters."""
    var material: PhysicsMaterial
    """The captured surface material value."""


def _rotation(q: Quaternion) raises:
    var norm = (
        Float64(q.x) * Float64(q.x)
        + Float64(q.y) * Float64(q.y)
        + Float64(q.z) * Float64(q.z)
        + Float64(q.w) * Float64(q.w)
    )
    if not (isfinite(norm) and abs(norm - 1) <= 0.00001):
        raise Error("A query snapshot requires finite unit quaternions")


def _polyhedron(poly: Polyhedron) raises:
    # Validate before transformed() or _box_of() reads any indexed corner.
    var faces = poly.face_count()
    if len(poly.vertices) < 4 or faces < 4:
        raise Error("A primitive solid needs four vertices and faces")
    if len(poly.offsets) != faces or len(poly.face_start) != faces + 1:
        raise Error("A primitive solid has inconsistent face lists")
    if poly.face_start[0] != 0 or poly.face_start[faces] != len(
        poly.face_corners
    ):
        raise Error("A primitive solid has invalid face limits")
    # The vertex-count guard proves this loop is nonempty.
    for vertex in poly.vertices:  # pragma: no branch
        _finite_vector(vertex)
    # The face-count guard proves this loop is nonempty.
    for f in range(faces):  # pragma: no branch
        _finite_vector(poly.normals[f])
        if poly.normals[f] == Vector3(0, 0, 0) or not isfinite(poly.offsets[f]):
            raise Error("A primitive solid has an invalid plane")
        var low = poly.face_start[f]
        var high = poly.face_start[f + 1]
        if high > len(poly.face_corners) or high - low < 3:
            raise Error("A primitive solid has an invalid face")
    # Every validated face has three corners, and there are four faces.
    for corner in poly.face_corners:  # pragma: no branch
        if corner < 0 or corner >= len(poly.vertices):
            raise Error("A primitive solid corner is out of range")
    if len(poly.edge_a) != len(poly.edge_b):
        raise Error("A primitive solid has inconsistent edge lists")
    for e in range(len(poly.edge_a)):
        if (
            poly.edge_a[e] < 0
            or poly.edge_a[e] >= len(poly.vertices)
            or poly.edge_b[e] < 0
            or poly.edge_b[e] >= len(poly.vertices)
        ):
            raise Error("A primitive solid edge is out of range")


def _bounded(v: Vector3) -> Bool:
    return max(abs(v.x), max(abs(v.y), abs(v.z))) <= 1e12


def _axis(v: Vector3) -> Int:
    # Only exact coordinate-axis vectors qualify; no angular tolerance.
    if v.y == 0 and v.z == 0 and v.x != 0:
        return 0
    if v.x == 0 and v.z == 0 and v.y != 0:
        return 1
    if v.x == 0 and v.y == 0 and v.z != 0:
        return 2
    return -1


def _up(value: Float32) -> Float32:
    # Admission bounds keep this operation finite, including both zeros.
    if value == 0:
        return bitcast[DType.float32](UInt32(1))
    var bits = bitcast[DType.uint32](value)
    return bitcast[DType.float32](bits + 1 if value > 0 else bits - 1)


def _round_box(shape: WorldShape) -> Box3:
    # u=2^-24. The admitted Float32 transverse sphere calculation implies
    # exact |center-origin| < radius*(1+4*u). Use 1+8*u, then round outward.
    # This also encloses radius collapse at a large Float32 center.
    var radius = _up(Float32(Float64(shape.radius) * 1.000000476837158203125))
    return Box3(
        Vector3(
            -_up(-(min(shape.start.x, shape.end.x) - radius)),
            -_up(-(min(shape.start.y, shape.end.y) - radius)),
            -_up(-(min(shape.start.z, shape.end.z) - radius)),
        ),
        Vector3(
            _up(max(shape.start.x, shape.end.x) + radius),
            _up(max(shape.start.y, shape.end.y) + radius),
            _up(max(shape.start.z, shape.end.z) + radius),
        ),
    )


def _admitted_axes(shape: WorldShape) -> Int:
    if shape.is_round():
        if not _bounded(shape.start) or not _bounded(shape.end):
            return 0
        if shape.radius < 0.0000152587890625 or shape.radius > 65536:
            return 0
        if shape.start == shape.end:
            return 7
        var axis = shape.end - shape.start
        var direction = _axis(axis)
        if direction < 0:
            return 0
        # Bounded endpoints give |axis| <= 2e12 per component, so its
        # squared length is finite. Parallel rays make cylinder a exactly zero.
        return 1 << direction
    for vertex in shape.polyhedron.vertices:
        if not _bounded(vertex):
            return 0
    var planes = 0
    for normal in shape.polyhedron.normals:
        var axis = _axis(normal)
        if axis < 0:
            return 0
        var value = component(normal, axis)
        if abs(value) != 1:
            return 0
        planes |= 1 << (2 * axis + Int(value < 0))
    # Both signs on all three axes are necessary; topology need not be convex.
    return 7 if planes == 63 else 0


def _less(a: Int, b: Int) -> Bool:
    return a < b


struct PhysicsQuerySnapshot(Movable):
    """One owned ray-query view with no live-world references.

    Args:
        world: The source to capture through the constructor.

    Returns:
        A deliberately frozen query object.

    Raises:
        Error: If capture geometry, materials or registered owners are invalid.
    """

    var _capture: ArcPointer[Int]
    var _shapes: List[WorldShape]
    var _boxes: List[Box3]
    var _owners: List[Int]
    var _materials: List[PhysicsMaterial]
    var _enabled: List[Bool]
    var _triangles: List[Triangle]
    var _triangle_body: List[Int]
    var _octree: Octree
    var _mesh_dirty: Bool
    var _index: _PrimitiveIndex
    var _index_entries: List[Int]
    var _safe_axes: List[Int]
    var _axis_linear: List[List[Int]]

    def __init__(out self, world: PhysicsWorld) raises:
        """Capture the complete current ray view without changing the world.

        Args:
            world: The source. Registered mesh geometry follows raycast.

        Raises:
            Error: If source state is malformed, nonfinite or inconsistent.
        """
        self._capture = ArcPointer(Int(0))
        self._shapes = List[WorldShape]()
        self._boxes = List[Box3]()
        self._owners = List[Int]()
        self._materials = List[PhysicsMaterial]()
        self._enabled = List[Bool]()
        self._triangles = List[Triangle]()
        self._triangle_body = List[Int]()
        self._octree = Octree()
        self._mesh_dirty = world._dirty
        self._index = _PrimitiveIndex()
        self._index_entries = List[Int]()
        self._safe_axes = List[Int]()
        self._axis_linear = List[List[Int]]()
        for i in range(len(world.bodies)):
            ref body = world.bodies[i]
            body.validate()
            if not body.shape.kind.is_valid():
                raise Error("A query snapshot requires a valid shape kind")
            body.material.check()
            self._materials.append(body.material)
            self._enabled.append(body.collides)
            if not body.collides or body.shape.kind == MESH:
                continue
            _finite_vector(body.position)
            _finite_vector(body.shape_position)
            _rotation(body.rotation)
            _rotation(body.shape_rotation)
            if body.shape.kind == SPHERE or body.shape.kind == CAPSULE:
                if not (isfinite(body.shape.radius) and body.shape.radius > 0):
                    raise Error(
                        "A query snapshot requires a finite positive radius"
                    )
                if body.shape.kind == CAPSULE:
                    if not (
                        isfinite(body.shape.half_height)
                        and body.shape.half_height >= 0
                    ):
                        raise Error(
                            "A query snapshot requires a finite nonnegative"
                            " half height"
                        )
            else:
                _polyhedron(body.shape.polyhedron)
            var shape = world._shape(i)
            _finite_vector(shape.start)
            _finite_vector(shape.end)
            if not shape.is_round():
                _polyhedron(shape.polyhedron)
            var box = _box_of(shape)
            _finite_vector(box.min)
            _finite_vector(box.max)
            self._boxes.append(box)
            self._shapes.append(shape^)
            self._owners.append(i)
        if len(world._triangle_body) != len(world._triangles):
            raise Error("Registered mesh triangle owners are inconsistent")
        for i in range(len(world._triangles)):
            var owner = world._triangle_body[i]
            if owner < 0 or owner >= len(world.bodies):
                raise Error("A registered mesh owner is out of range")
            if world.bodies[owner].shape.kind != MESH:
                raise Error("A registered mesh owner is no longer a mesh")
            var triangle = world._triangles[i]
            _finite_vector(triangle.a)
            _finite_vector(triangle.b)
            _finite_vector(triangle.c)
            self._triangles.append(triangle)
            self._triangle_body.append(owner)
        if not self._mesh_dirty and len(self._triangles) > 0:
            # Copying retains the exact current mesh traversal and tie order.
            self._octree.box = world._octree.box
            self._octree.bounds = world._octree.bounds
            self._octree.layers = world._octree.layers
            self._octree.triangles_per_leaf = world._octree.triangles_per_leaf
            self._octree.max_level = world._octree.max_level
            self._octree.triangles = world._octree.triangles.copy()
            self._octree._nodes = world._octree._nodes.copy()

        self._build_index()

    def _build_index(mut self) raises:
        # Tiny worlds retain the allocation-free primitive scan.
        if len(self._shapes) < 32:
            return
        var masks = List[Int]()
        var entries = List[Int]()
        var boxes = List[Box3]()
        var common = Box3.empty()
        for i in range(len(self._shapes)):
            ref shape = self._shapes[i]
            var axes = _admitted_axes(shape)
            masks.append(axes)
            if axes == 0:
                continue
            var box = _round_box(shape) if shape.is_round() else self._boxes[i]
            if len(boxes) == 0:
                common = box
            else:
                common.intersect(box)
            boxes.append(box)
            entries.append(i)
        # An index cannot prune a set whose bounds all share one point well.
        # Keep complete-overlap and mostly unsupported worlds on the scan.
        if len(entries) < 32 or not common.is_empty():
            return
        self._index.rebuild(boxes)
        self._index_entries = entries^
        self._safe_axes = masks^
        for axis in range(3):  # pragma: no branch
            var linear = List[Int]()
            for i in range(len(self._shapes)):
                if self._safe_axes[i] & (1 << axis) == 0:
                    linear.append(i)
            self._axis_linear.append(linear^)

    def body_count(self) -> Int:
        """Return the number of source slots at capture time.

        Returns:
            The captured count, including disabled bodies and mesh owners.
        """
        return len(self._materials)

    def check_owner(self, owner: SnapshotOwner) raises:
        """Check membership in this capture, without consulting a world.

        Args:
            owner: A historical owner returned by a captured query.

        Raises:
            Error: If the owner is invalid, out of range or from another capture.
        """
        if not owner.is_valid() or owner.source_body.value >= self.body_count():
            raise Error("The historical owner names no captured body")
        if owner._capture.ptr() != self._capture.ptr():
            raise Error("The historical owner belongs to another capture")

    def _shape_hit(self, ray: Ray, entry: Int) -> Optional[RaycastHit]:
        ref shape = self._shapes[entry]
        var i = self._owners[entry]
        var material = self._materials[i]
        if not shape.is_round():
            return _polyhedron_hit(ray, shape.polyhedron, i, material)
        var best = _sphere_hit(ray, shape.start, shape.radius)
        var other = _sphere_hit(ray, shape.end, shape.radius)
        if other < best:
            best = other
        other = _cylinder_hit(ray, shape.start, shape.end, shape.radius)
        if other < best:
            best = other
        if best == inf[DType.float32]():
            return None
        var point = ray.at(best)
        var on = Vector3(0, 0, 0)
        var on_ray = Vector3(0, 0, 0)
        _ = Line3(shape.start, shape.end).closest_points_to_line(
            Line3(point, point), on, on_ray
        )
        return RaycastHit(
            BodyId(i),
            point,
            unit_or(point - on, -ray.direction),
            best,
            material,
        )

    def _triangle_hit(
        self,
        ray: Ray,
        t: Int,
        reach: Float32,
        best: Optional[RaycastHit],
        ignore: BodyId,
    ) -> Optional[RaycastHit]:
        var owner = self._triangle_body[t]
        if owner == ignore.value or not self._enabled[owner]:
            return best
        ref tri = self._triangles[t]
        var met = ray.intersect_triangle(tri.a, tri.b, tri.c, True)
        if not Bool(met):
            return best
        var distance = (met.value() - ray.origin).length()
        if distance > reach:
            return best
        if Bool(best) and best.value().distance <= distance:
            return best
        return RaycastHit(
            BodyId(owner),
            met.value(),
            unit_or(cross(tri.b - tri.a, tri.c - tri.a), Vector3(0, 0, 1)),
            distance,
            self._materials[owner],
        )

    def _mesh_hit(
        self, ray: Ray, reach: Float32, ignore: BodyId
    ) -> Optional[RaycastHit]:
        var best: Optional[RaycastHit] = None
        if self._mesh_dirty:
            for t in range(len(self._triangles)):
                best = self._triangle_hit(ray, t, reach, best, ignore)
        elif len(self._triangles) > 0:
            for t in self._octree.ray_triangles(ray):
                best = self._triangle_hit(ray, t, reach, best, ignore)
        return best

    def _entry_hit(
        self,
        ray: Ray,
        entry: Int,
        reach: Float32,
        best: Optional[RaycastHit],
        ignore: BodyId,
    ) -> Optional[RaycastHit]:
        if self._owners[entry] == ignore.value:
            return best
        var hit = self._shape_hit(ray, entry)
        if not Bool(hit):
            return best
        var found = hit.value()
        if found.distance > reach:
            return best
        if Bool(best) and best.value().distance <= found.distance:
            return best
        return found

    def _linear_hit(
        self,
        ray: Ray,
        reach: Float32,
        ignore: BodyId,
    ) -> Optional[RaycastHit]:
        var best = self._mesh_hit(ray, reach, ignore)
        for entry in range(len(self._shapes)):
            best = self._entry_hit(ray, entry, reach, best, ignore)
        return best

    def _query_hit(
        self,
        ray: Ray,
        reach: Float32,
        ignore: BodyId,
    ) -> Optional[RaycastHit]:
        var axis = _axis(ray.direction)
        if len(self._index.nodes) == 0 or axis < 0 or not _bounded(ray.origin):
            return self._linear_hit(ray, reach, ignore)
        var candidates = List[Int]()
        _ = self._index.axis_line(ray.origin, axis, candidates)
        # Do not pay sort/merge costs for a query that retains most entries.
        if len(candidates) * 4 >= len(self._shapes):
            return self._linear_hit(ray, reach, ignore)
        stable_sort[_less](candidates)
        ref linear = self._axis_linear[axis]
        var next_linear = 0
        var next_candidate = 0
        var best = self._mesh_hit(ray, reach, ignore)
        while next_linear < len(linear) or next_candidate < len(candidates):
            var candidate = len(self._shapes)
            if next_candidate < len(candidates):
                candidate = self._index_entries[candidates[next_candidate]]
                if self._safe_axes[candidate] & (1 << axis) == 0:
                    next_candidate += 1
                    continue
            var entry = candidate
            if next_linear < len(linear) and linear[next_linear] < candidate:
                entry = linear[next_linear]
                next_linear += 1
            else:
                next_candidate += 1
            best = self._entry_hit(ray, entry, reach, best, ignore)
        return best

    def _owned_hit(
        self, best: Optional[RaycastHit]
    ) -> Optional[SnapshotRaycastHit]:
        if not Bool(best):
            return None
        var hit = best.value()
        return SnapshotRaycastHit(
            SnapshotOwner(hit.body, self._capture),
            hit.point,
            hit.normal,
            hit.distance,
            hit.material,
        )

    def raycast(
        self,
        origin: Vector3,
        direction: Vector3,
        max_distance: Length,
        ignore: BodyId,
    ) raises -> Optional[SnapshotRaycastHit]:
        """Return the nearest captured surface with historical owner identity.

        Args:
            origin: The ray origin, in meters.
            direction: A nonzero finite direction. Ray normalizes it.
            max_distance: The inclusive reach for finite hit distances.
                Legacy nonfinite narrow-phase results keep their behavior.
            ignore: A capture-time source slot. BodyId(-1) ignores none.
                A nonnegative slot outside this capture ignores none.

        Returns:
            The same hit values as the captured ray view, or None.
            Mesh hits precede primitive ties; lower primitive slots win ties.

        Raises:
            Error: If the ray is invalid, reach is NaN, or ignore is below -1.
        """
        if ignore.value < -1 or isnan(max_distance.value):
            raise Error("The captured ray ignore slot or reach is invalid")
        _finite_vector(origin)
        _finite_vector(direction)
        var ray = Ray(origin, direction)
        return self._owned_hit(self._query_hit(ray, max_distance.value, ignore))
