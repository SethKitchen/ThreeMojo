# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A rigid-body world that steps at a fixed time step.

One `step` does this, in order:

1. Gravity, forces and damping change the velocities of dynamic bodies.
2. The broad phase sorts the bounds of the moving shapes along x, sweep
   and prune, and pairs the ones that overlap. The static meshes are in
   one `Octree`, and each moving shape asks it for the triangles near it.
3. The narrow phase, `collide`, gives the contact points of each pair.
4. Sequential impulses (Erin Catto, "Iterative Dynamics with Temporal
   Coherence", 2005) solve the contacts: a normal impulse that stops the
   bodies moving together, and a friction impulse in the contact plane
   that the Coulomb cone limits to the friction times the normal impulse.
   A contact with a gap lets the bodies close the gap and no more, so a
   fast body stops at a surface instead of in it.
5. Restitution is a second pass, as in Box2D 3.0: each point that hit
   faster than the bounce threshold gets the speed apart that the
   restitution asks for.
6. Split impulses push overlapping bodies apart. They change the
   positions and not the velocities, so they add no energy.
7. Velocities move the bodies. The orientation integrates as a
   quaternion and is normalized.

A ray cast, `raycast`, finds the nearest shape a ray meets. It is what a
wheel's suspension and a walker's floor test use.

The gravity is standard gravity rounded to 9.8 m/s^2, down: minus z in
CARLA's frame. The bounce threshold is 1 m/s, Box2D's default
restitution threshold: slower hits do not bounce, so a resting body does
not jitter.
"""

from extensions.carla.physics.body import (
    BodyId,
    BodyKind,
    DYNAMIC,
    KINEMATIC,
    RigidBody,
    STATIC,
    rotation_matrix,
)
from extensions.carla.physics.collide import (
    ContactPoint,
    WorldShape,
    collide,
    mesh_contacts,
)
from extensions.carla.physics.shape import (
    CAPSULE,
    MESH,
    SPHERE,
    PhysicsMaterial,
    Polyhedron,
    any_perpendicular,
    cross,
    unit_or,
)
from math.bounds import Box3, Sphere
from math.octree import Octree
from math.quaternion import Quaternion
from math.ray import Ray
from math.triangle import Line3, Triangle
from math.vector3 import Vector3
from std.math import inf, isfinite, sqrt
from units.si import Duration, Length, METER, SECOND


@fieldwise_init
struct RaycastHit(ImplicitlyCopyable):
    """The nearest shape a ray meets."""

    var body: BodyId
    # Where the ray meets the surface.
    var point: Vector3
    # The outward unit normal of the surface there.
    var normal: Vector3
    # How far along the ray, in meters.
    var distance: Float32
    # The surface's material.
    var material: PhysicsMaterial


@fieldwise_init
struct CollisionEvent(ImplicitlyCopyable):
    """Two bodies that pushed on each other during the last step, as
    CARLA's collision sensor reports them."""

    var body: BodyId
    var other: BodyId
    # The impulse `other` gave `body`, in N s.
    var normal_impulse: Vector3


@fieldwise_init
struct _Point(ImplicitlyCopyable):
    """One contact point with its solver state."""

    var contact: ContactPoint
    # From each body's center of mass to the point.
    var ra: Vector3
    var rb: Vector3
    var tangent1: Vector3
    var tangent2: Vector3
    var normal_mass: Float32
    var tangent_mass1: Float32
    var tangent_mass2: Float32
    # The speed together along the normal before the solve.
    var approach: Float32
    var normal_impulse: Float32
    var tangent_impulse1: Float32
    var tangent_impulse2: Float32
    var push_impulse: Float32


@fieldwise_init
struct _Manifold(Copyable, Movable):
    var a: Int
    var b: Int
    var material: PhysicsMaterial
    var points: List[_Point]


struct PhysicsWorld(Movable):
    """Bodies, static meshes, and the solver that steps them."""

    var bodies: List[RigidBody]
    # In m/s^2.
    var gravity: Vector3
    var velocity_iterations: Int
    var position_iterations: Int
    # The widest gap that still makes a contact, in meters.
    var margin: Float32
    # The overlap left alone, so resting contacts do not flicker.
    var slop: Float32
    # How much of the overlap one step removes.
    var push_factor: Float32
    # Below this speed together, in m/s, a hit does not bounce.
    var bounce_threshold: Float32
    # The collision events of the last step.
    var events: List[CollisionEvent]
    # How many contact points the last step solved.
    var contact_count: Int
    var _octree: Octree
    var _triangles: List[Triangle]
    # The body each triangle belongs to.
    var _triangle_body: List[Int]
    var _dirty: Bool
    # Moving bodies, sorted by the low x of their bounds.
    var _order: List[Int]

    def __init__(out self):
        """Create an empty world with standard gravity."""
        self.bodies = List[RigidBody]()
        self.gravity = Vector3(0, 0, -9.8)
        self.velocity_iterations = 10
        self.position_iterations = 4
        self.margin = 0.02
        self.slop = 0.005
        self.push_factor = 0.2
        self.bounce_threshold = 1.0
        self.events = List[CollisionEvent]()
        self.contact_count = 0
        self._octree = Octree()
        self._triangles = List[Triangle]()
        self._triangle_body = List[Int]()
        self._dirty = False
        self._order = List[Int]()

    def add_body(mut self, var body: RigidBody) -> BodyId:
        """Add a body. A mesh body's triangles go into the static octree.

        Args:
            body: The body.

        Returns:
            Its id.
        """
        var id = len(self.bodies)
        if body.shape.kind == MESH:
            var turn = rotation_matrix(body.shape_world_rotation())
            var at = body.shape_world_position()
            # A mesh has one triangle at least.
            for t in body.shape.triangles:  # pragma: no branch
                self._triangles.append(
                    Triangle(
                        turn.transform(t.a) + at,
                        turn.transform(t.b) + at,
                        turn.transform(t.c) + at,
                    )
                )
                self._triangle_body.append(id)
            self._dirty = True
        elif body.kind != STATIC:
            self._order.append(id)
        self.bodies.append(body^)
        return BodyId(id)

    def body_count(self) -> Int:
        """Return how many bodies the world has.

        Returns:
            The count.
        """
        return len(self.bodies)

    def check(self, id: BodyId) raises:
        """Refuse an id that names no body.

        Args:
            id: The id.

        Raises:
            Error: If the id is not valid or is out of range.
        """
        if not id.is_valid() or id.value >= len(self.bodies):
            raise Error("Body id names no body")

    def _shape(self, i: Int) -> WorldShape:
        ref body = self.bodies[i]
        var at = body.shape_world_position()
        var turn = body.shape_world_rotation()
        if body.shape.kind == SPHERE:
            return WorldShape.round(at, at, body.shape.radius)
        if body.shape.kind == CAPSULE:
            var half = turn.rotate(Vector3(0, 0, body.shape.half_height))
            return WorldShape.round(at - half, at + half, body.shape.radius)
        return WorldShape.solid(
            body.shape.polyhedron.transformed(at, rotation_matrix(turn))
        )

    def bounds(self, id: BodyId) raises -> Box3:
        """Return the world bounds of a moving body's shape.

        Args:
            id: The body.

        Returns:
            The axis-aligned box around the shape, in meters.

        Raises:
            Error: If the id names no body, or the body is a mesh.
        """
        self.check(id)
        if self.bodies[id.value].shape.kind == MESH:
            raise Error("A mesh has no bounds of its own")
        return _box_of(self._shape(id.value))

    def step(mut self, dt: Duration) raises:
        """Advance the world by one fixed step.

        Args:
            dt: The step. It must be more than zero and finite.

        Raises:
            Error: If the step is not more than zero and finite.
        """
        var h = dt.value
        if not (isfinite(h) and h > 0):
            raise Error("A physics step must be more than zero")
        self._integrate_velocities(h)
        if self._dirty:
            self._rebuild()
        var manifolds = self._find_contacts()
        self._prepare(manifolds, h)
        for _ in range(self.velocity_iterations):
            for m in range(len(manifolds)):
                self._solve_velocity(manifolds[m], h)
        for m in range(len(manifolds)):
            self._restitution(manifolds[m])
        for _ in range(self.position_iterations):
            for m in range(len(manifolds)):
                self._solve_push(manifolds[m], h)
        self._integrate_positions(h)
        self._report(manifolds)

    def _integrate_velocities(mut self, h: Float32):
        for i in range(len(self.bodies)):
            ref body = self.bodies[i]
            if body.kind == DYNAMIC:
                var accel = (
                    self.gravity * body.gravity_scale
                    + body.force * body.inverse_mass
                )
                body.linear_velocity = (body.linear_velocity + accel * h) * (
                    1 / (1 + h * body.linear_damping)
                )
                body.angular_velocity = (
                    body.angular_velocity
                    + body.world_inverse_inertia().transform(body.torque) * h
                ) * (1 / (1 + h * body.angular_damping))
            body.force = Vector3(0, 0, 0)
            body.torque = Vector3(0, 0, 0)

    def _rebuild(mut self):
        self._octree = Octree()
        # The octree is dirty only after a mesh added triangles.
        for t in self._triangles:  # pragma: no branch
            self._octree.add_triangle(t)
        self._octree.build()
        self._dirty = False

    def _find_contacts(mut self) raises -> List[_Manifold]:
        var shapes = List[WorldShape]()
        var boxes = List[Box3]()
        for i in range(len(self.bodies)):
            if self.bodies[i].shape.kind == MESH:
                shapes.append(
                    WorldShape.round(Vector3(0, 0, 0), Vector3(0, 0, 0), 0)
                )
                boxes.append(Box3.empty())
            else:
                shapes.append(self._shape(i))
                boxes.append(_box_of(shapes[i]))
        # Insertion sort: the order changes little from step to step.
        for i in range(1, len(self._order)):
            var j = i
            while (
                j > 0
                and boxes[self._order[j - 1]].min.x
                > boxes[self._order[j]].min.x
            ):
                self._order.swap_elements(j - 1, j)
                j -= 1
        var out = List[_Manifold]()
        for i in range(len(self._order)):
            var a = self._order[i]
            for j in range(i + 1, len(self._order)):
                var b = self._order[j]
                if boxes[b].min.x > boxes[a].max.x + self.margin:
                    break
                if not self._may_touch(a, b, boxes):
                    continue
                var points = collide(shapes[a], shapes[b], self.margin)
                self._add(out, a, b, points)
            self._mesh_pairs(out, a, shapes[a], boxes[a])
        return out^

    def _may_touch(self, a: Int, b: Int, boxes: List[Box3]) -> Bool:
        ref ba = self.bodies[a]
        ref bb = self.bodies[b]
        if not (ba.collides and bb.collides):
            return False
        if not (ba.is_dynamic() or bb.is_dynamic()):
            return False
        var grown = boxes[a]
        grown.expand_by_scalar(self.margin)
        return grown.intersects_box(boxes[b])

    def _mesh_pairs(
        self,
        mut out: List[_Manifold],
        a: Int,
        shape: WorldShape,
        box: Box3,
    ) raises:
        if len(self._triangles) == 0:
            return
        ref body = self.bodies[a]
        if not (body.is_dynamic() and body.collides):
            return
        var center = box.center()
        var reach = (box.max - center).length() + self.margin
        var found = self._octree.sphere_triangles(Sphere(center, reach))
        # One manifold for each mesh body this shape touches.
        var owners = List[Int]()
        var lists = List[List[ContactPoint]]()
        for t in found:
            var owner = self._triangle_body[t]
            if not self.bodies[owner].collides:
                continue
            var points = mesh_contacts(self._triangles[t], shape, self.margin)
            if len(points) == 0:
                continue
            var k = 0
            while k < len(owners) and owners[k] != owner:
                k += 1
            if k == len(owners):
                owners.append(owner)
                lists.append(List[ContactPoint]())
            lists[k].extend(points^)
        for k in range(len(owners)):
            self._add(out, owners[k], a, lists[k])

    def _add(
        self,
        mut out: List[_Manifold],
        a: Int,
        b: Int,
        points: List[ContactPoint],
    ):
        if len(points) == 0:
            return
        var solver = List[_Point]()
        # `points` is not empty, checked above.
        for p in points:  # pragma: no branch
            solver.append(
                _Point(
                    p,
                    Vector3(0, 0, 0),
                    Vector3(0, 0, 0),
                    Vector3(0, 0, 0),
                    Vector3(0, 0, 0),
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                )
            )
        out.append(
            _Manifold(
                a,
                b,
                self.bodies[a].material.combine(self.bodies[b].material),
                solver^,
            )
        )

    def _effective_mass(
        self, a: Int, b: Int, ra: Vector3, rb: Vector3, n: Vector3
    ) -> Float32:
        ref ba = self.bodies[a]
        ref bb = self.bodies[b]
        var ca = cross(ra, n)
        var cb = cross(rb, n)
        var k = (
            ba.inverse_mass
            + bb.inverse_mass
            + ca.dot(ba.world_inverse_inertia().transform(ca))
            + cb.dot(bb.world_inverse_inertia().transform(cb))
        )
        return 1 / k

    def _prepare(mut self, mut manifolds: List[_Manifold], h: Float32):
        self.contact_count = 0
        for m in range(len(manifolds)):
            var a = manifolds[m].a
            var b = manifolds[m].b
            var ca = self.bodies[a].world_center_of_mass()
            var cb = self.bodies[b].world_center_of_mass()
            # A manifold has one point at least.
            for k in range(len(manifolds[m].points)):  # pragma: no branch
                ref p = manifolds[m].points[k]
                var n = p.contact.normal
                p.ra = p.contact.point - ca
                p.rb = p.contact.point - cb
                p.tangent1 = any_perpendicular(n)
                p.tangent2 = cross(n, p.tangent1)
                p.normal_mass = self._effective_mass(a, b, p.ra, p.rb, n)
                p.tangent_mass1 = self._effective_mass(
                    a, b, p.ra, p.rb, p.tangent1
                )
                p.tangent_mass2 = self._effective_mass(
                    a, b, p.ra, p.rb, p.tangent2
                )
                p.approach = self._relative(a, b, p).dot(n)
                self.contact_count += 1

    def _relative(self, a: Int, b: Int, p: _Point) -> Vector3:
        ref ba = self.bodies[a]
        ref bb = self.bodies[b]
        return (
            bb.linear_velocity
            + cross(bb.angular_velocity, p.rb)
            - ba.linear_velocity
            - cross(ba.angular_velocity, p.ra)
        )

    def _impulse(mut self, a: Int, b: Int, p: _Point, j: Vector3):
        """Give `b` the impulse `j` at the point and `a` its opposite."""
        ref ba = self.bodies[a]
        ba.linear_velocity = ba.linear_velocity - j * ba.inverse_mass
        ba.angular_velocity = (
            ba.angular_velocity
            - ba.world_inverse_inertia().transform(cross(p.ra, j))
        )
        ref bb = self.bodies[b]
        bb.linear_velocity = bb.linear_velocity + j * bb.inverse_mass
        bb.angular_velocity = (
            bb.angular_velocity
            + bb.world_inverse_inertia().transform(cross(p.rb, j))
        )

    def _solve_velocity(mut self, mut m: _Manifold, h: Float32):
        var friction = m.material.friction
        for k in range(len(m.points)):  # pragma: no branch
            var p = m.points[k]
            var n = p.contact.normal
            # The normal: close no more than the gap.
            var vn = self._relative(m.a, m.b, p).dot(n)
            var bias = min(p.contact.depth, 0) / h
            var total = max(p.normal_impulse + p.normal_mass * (bias - vn), 0)
            var dn = total - p.normal_impulse
            p.normal_impulse = total
            self._impulse(m.a, m.b, p, n * dn)
            # Friction: stop the sliding, inside the Coulomb cone.
            var v = self._relative(m.a, m.b, p)
            var t1 = p.tangent_impulse1 - p.tangent_mass1 * v.dot(p.tangent1)
            var t2 = p.tangent_impulse2 - p.tangent_mass2 * v.dot(p.tangent2)
            var limit = friction * p.normal_impulse
            var size = sqrt(t1 * t1 + t2 * t2)
            if size > limit:
                t1 *= limit / size
                t2 *= limit / size
            var dt = p.tangent1 * (t1 - p.tangent_impulse1) + p.tangent2 * (
                t2 - p.tangent_impulse2
            )
            p.tangent_impulse1 = t1
            p.tangent_impulse2 = t2
            self._impulse(m.a, m.b, p, dt)
            m.points[k] = p

    def _restitution(mut self, mut m: _Manifold):
        var e = m.material.restitution
        for k in range(len(m.points)):  # pragma: no branch
            var p = m.points[k]
            if p.approach > -self.bounce_threshold or p.normal_impulse <= 0:
                continue
            var vn = self._relative(m.a, m.b, p).dot(p.contact.normal)
            var total = max(
                p.normal_impulse + p.normal_mass * (-e * p.approach - vn), 0
            )
            self._impulse(
                m.a, m.b, p, p.contact.normal * (total - p.normal_impulse)
            )
            p.normal_impulse = total
            m.points[k] = p

    def _push(mut self, a: Int, b: Int, p: _Point, j: Vector3):
        ref ba = self.bodies[a]
        ba.push_velocity = ba.push_velocity - j * ba.inverse_mass
        ba.push_angular = (
            ba.push_angular
            - ba.world_inverse_inertia().transform(cross(p.ra, j))
        )
        ref bb = self.bodies[b]
        bb.push_velocity = bb.push_velocity + j * bb.inverse_mass
        bb.push_angular = (
            bb.push_angular
            + bb.world_inverse_inertia().transform(cross(p.rb, j))
        )

    def _solve_push(mut self, mut m: _Manifold, h: Float32):
        for k in range(len(m.points)):  # pragma: no branch
            var p = m.points[k]
            var overlap = p.contact.depth - self.slop
            if overlap <= 0:
                continue
            ref ba = self.bodies[m.a]
            ref bb = self.bodies[m.b]
            var vn = (
                bb.push_velocity
                + cross(bb.push_angular, p.rb)
                - ba.push_velocity
                - cross(ba.push_angular, p.ra)
            ).dot(p.contact.normal)
            var target = self.push_factor * overlap / h
            var total = max(p.push_impulse + p.normal_mass * (target - vn), 0)
            self._push(m.a, m.b, p, p.contact.normal * (total - p.push_impulse))
            p.push_impulse = total
            m.points[k] = p

    def _integrate_positions(mut self, h: Float32):
        for i in range(len(self.bodies)):
            ref body = self.bodies[i]
            if body.kind == STATIC:
                continue
            var com = body.world_center_of_mass()
            var w = body.angular_velocity + body.push_angular
            var q = body.rotation
            var spin = Quaternion(w.x, w.y, w.z, 0) * q
            q = Quaternion(
                q.x + spin.x * 0.5 * h,
                q.y + spin.y * 0.5 * h,
                q.z + spin.z * 0.5 * h,
                q.w + spin.w * 0.5 * h,
            )
            q.normalize()
            body.rotation = q
            com = com + (body.linear_velocity + body.push_velocity) * h
            body.position = com - q.rotate(body.center_of_mass)
            body.push_velocity = Vector3(0, 0, 0)
            body.push_angular = Vector3(0, 0, 0)

    def _report(mut self, manifolds: List[_Manifold]):
        self.events = List[CollisionEvent]()
        for m in manifolds:
            var total = Vector3(0, 0, 0)
            for p in m.points:  # pragma: no branch
                total = total + p.contact.normal * p.normal_impulse
            if total.length() > 0:
                self.events.append(
                    CollisionEvent(BodyId(m.b), BodyId(m.a), total)
                )
                self.events.append(
                    CollisionEvent(BodyId(m.a), BodyId(m.b), -total)
                )

    def raycast(
        self,
        origin: Vector3,
        direction: Vector3,
        max_distance: Length,
        ignore: BodyId,
    ) raises -> Optional[RaycastHit]:
        """Return the nearest shape a ray meets within a distance.

        Args:
            origin: Where the ray starts, in meters.
            direction: Which way it goes. It is normalized.
            max_distance: How far it reaches.
            ignore: A body the ray passes through, such as the one that
                casts it. `BodyId(-1)` ignores none.

        Returns:
            The nearest hit, or None.

        Raises:
            Error: If the direction is zero.
        """
        var ray = Ray(origin, direction)
        var best: Optional[RaycastHit] = None
        var reach = max_distance.value
        if self._dirty:
            # A mesh added since the last step: search it by brute force.
            # The octree is dirty only after a mesh added triangles.
            for t in range(len(self._triangles)):  # pragma: no branch
                best = self._triangle_hit(ray, t, reach, best, ignore)
        elif len(self._triangles) > 0:
            for t in self._octree.ray_triangles(ray):
                best = self._triangle_hit(ray, t, reach, best, ignore)
        for i in range(len(self.bodies)):
            if i == ignore.value or self.bodies[i].shape.kind == MESH:
                continue
            if not self.bodies[i].collides:
                continue
            var hit = self._shape_hit(ray, i)
            if not Bool(hit):
                continue
            var found = hit.value()
            if found.distance > reach:
                continue
            if Bool(best) and best.value().distance <= found.distance:
                continue
            best = found
        return best

    def _triangle_hit(
        self,
        ray: Ray,
        t: Int,
        reach: Float32,
        best: Optional[RaycastHit],
        ignore: BodyId,
    ) -> Optional[RaycastHit]:
        var owner = self._triangle_body[t]
        if owner == ignore.value or not self.bodies[owner].collides:
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
            self.bodies[owner].material,
        )

    def _shape_hit(self, ray: Ray, i: Int) -> Optional[RaycastHit]:
        var shape = self._shape(i)
        var material = self.bodies[i].material
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


def _box_of(shape: WorldShape) -> Box3:
    if shape.is_round():
        var r = Vector3(shape.radius, shape.radius, shape.radius)
        var box = Box3(shape.start, shape.start)
        box.expand_by_point(shape.end)
        box.min = box.min - r
        box.max = box.max + r
        return box
    var box = Box3(shape.polyhedron.vertices[0], shape.polyhedron.vertices[0])
    # A polyhedron has three corners at least.
    for v in shape.polyhedron.vertices:  # pragma: no branch
        box.expand_by_point(v)
    return box


def _sphere_hit(ray: Ray, center: Vector3, radius: Float32) -> Float32:
    """Return how far along a ray it enters a sphere, or infinity."""
    var toward = center - ray.origin
    var foot = toward.dot(ray.direction)
    var drop = toward - ray.direction * foot
    var h = radius * radius - drop.dot(drop)
    if h < 0:
        return inf[DType.float32]()
    var t = foot - sqrt(h)
    if t < 0:
        return inf[DType.float32]()
    return t


def _cylinder_hit(
    ray: Ray, start: Vector3, end: Vector3, radius: Float32
) -> Float32:
    """Return how far along a ray it enters the side of a capsule, or
    infinity."""
    var axis = end - start
    var length_sq = axis.dot(axis)
    var o = ray.origin - start
    var d = ray.direction
    var ad = axis.dot(d)
    var ao = axis.dot(o)
    var a = length_sq - ad * ad
    var b = length_sq * d.dot(o) - ao * ad
    var c = length_sq * o.dot(o) - ao * ao - radius * radius * length_sq
    var h = b * b - a * c
    if a < 1e-12 or h < 0:
        return inf[DType.float32]()
    var t = (-b - sqrt(h)) / a
    var y = ao + t * ad
    if t < 0 or y < 0 or y > length_sq:
        return inf[DType.float32]()
    return t


def _polyhedron_hit(
    ray: Ray, poly: Polyhedron, i: Int, material: PhysicsMaterial
) -> Optional[RaycastHit]:
    """Return where a ray enters a convex solid, the Cyrus-Beck clip."""
    var enter = Float32(0)
    var leave = inf[DType.float32]()
    var normal = Vector3(0, 0, 0)
    var entered = False
    # A polyhedron has one face at least.
    for f in range(poly.face_count()):  # pragma: no branch
        var denom = poly.normals[f].dot(ray.direction)
        var dist = poly.normals[f].dot(ray.origin) - poly.offsets[f]
        if abs(denom) < 1e-12:
            if dist > 0:
                return None
            continue
        var t = -dist / denom
        if denom < 0:
            if t >= enter:
                enter = t
                normal = poly.normals[f]
                entered = True
        else:
            leave = min(leave, t)
    if not entered or enter > leave:
        return None
    return RaycastHit(BodyId(i), ray.at(enter), normal, enter, material)
