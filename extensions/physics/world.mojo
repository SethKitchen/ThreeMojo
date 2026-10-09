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
6. Split impulses push overlapping bodies apart. They change pose and
   not the stored velocities. For anisotropic bodies this correction
   can change rotational energy.
7. Velocities move the bodies. A symmetric split of exact rotations
   advances free anisotropic rotation while preserving world momentum
   up to rounding. Isotropic and custom constrained bodies retain the
   normalized-quaternion prescribed-velocity update.

A ray cast, `raycast`, finds the nearest shape a ray meets. It is what a
wheel's suspension and a walker's floor test use.

The gravity is standard gravity rounded to 9.8 m/s^2, down: minus z in
CARLA's frame. The bounce threshold is 1 m/s, Box2D's default
restitution threshold: slower hits do not bounce, so a resting body does
not jitter.
"""

from extensions.physics.ccd import (
    CollisionDetection,
    DISCRETE,
    SPHERE_MESH_CCD,
    _sweep_capsule_triangle,
    _SweepHit,
    _initial_capsule_contact,
    _initial_triangle_contact,
    _sweep_triangle,
    _sweep_domain,
)
from extensions.physics.ccd_index import _CCDIndex
from extensions.physics.body import (
    BodyId,
    BodyKind,
    DYNAMIC,
    KINEMATIC,
    RigidBody,
    STATIC,
    rotation_matrix,
)
from extensions.physics.collide import (
    ContactPoint,
    WorldShape,
    collide,
    mesh_contacts,
)
from extensions.physics.shape import (
    CAPSULE,
    MESH,
    SPHERE,
    PhysicsMaterial,
    Polyhedron,
    any_perpendicular,
    cross,
    unit_or,
    _wide,
    _wide_cross,
    _wide_dot,
    _finite_vector,
    _narrow_finite,
)
from math.bounds import Box3, Sphere
from math.matrix3 import Matrix3
from math.octree import Octree
from math.quaternion import Quaternion
from math.ray import Ray
from math.triangle import Line3, Triangle
from math.vector3 import Vector3
from std.math import fma, inf, isfinite, sqrt
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


@fieldwise_init
struct _StepState(ImplicitlyCopyable):
    var position: Vector3
    var rotation: Quaternion
    var velocity: Vector3
    var angular: Vector3
    var force: Vector3
    var torque: Vector3
    var push: Vector3
    var push_angular: Vector3


@fieldwise_init
struct _CCDImpact(ImplicitlyCopyable):
    var time: Float64
    var body: Int
    var triangle: Int
    var impulse: Vector3


struct PhysicsWorld(Movable):
    """Bodies, static meshes, and the solver that steps them."""

    var bodies: List[RigidBody]
    # Discrete by default. CCD refuses unsupported colliding worlds.
    var collision_detection: CollisionDetection
    # Per sphere and step. Exhaustion rolls back the complete step.
    var ccd_max_impacts: Int
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
    # Validated acceleration belongs only to the immutable triangle snapshot.
    # Independent of the contact octree's dirty/rebuild transaction state.
    var _ccd_index: _CCDIndex
    # Independent original scans for parity controls and diagnostic fallback.
    var _ccd_brute_force: Bool
    # Non-mesh bodies, sorted by the low x of their bounds.
    var _order: List[Int]

    def __init__(out self):
        """Create an empty world with standard gravity."""
        self.bodies = List[RigidBody]()
        self.collision_detection = DISCRETE
        self.ccd_max_impacts = 16
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
        self._ccd_index = _CCDIndex()
        self._ccd_brute_force = False
        self._order = List[Int]()

    def add_body(mut self, var body: RigidBody) raises -> BodyId:
        """Add a body. A mesh body's triangles go into the static octree.

        Args:
            body: The body.

        Returns:
            Its id.

        Raises:
            Error: If the body's mode or mass state is inconsistent.
        """
        body.validate()
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
            self._ccd_index = _CCDIndex()
        else:
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
            Error: If the step is not more than zero and finite, or a
                body's mode or mass state is inconsistent.
        """
        var h = dt.value
        if not (isfinite(h) and h > 0):
            raise Error("A physics step must be more than zero")
        # Validate the complete batch before any body or pending force changes.
        for body in self.bodies:
            body.validate()
        if not self.collision_detection.is_valid():
            raise Error("Collision detection mode is not valid")
        if self.collision_detection == DISCRETE:
            self._step(h)
            return
        # CCD is transactional, including pending forces and prior reports.
        var states = List[_StepState]()
        for body in self.bodies:
            states.append(
                _StepState(
                    body.position,
                    body.rotation,
                    body.linear_velocity,
                    body.angular_velocity,
                    body.force,
                    body.torque,
                    body.push_velocity,
                    body.push_angular,
                )
            )
        var events = self.events.copy()
        var order = self._order.copy()
        var count = self.contact_count
        var dirty = self._dirty
        try:
            self._validate_ccd()
            self._step(h)
        except error:
            for i in range(len(states)):
                self.bodies[i].position = states[i].position
                self.bodies[i].rotation = states[i].rotation
                self.bodies[i].linear_velocity = states[i].velocity
                self.bodies[i].angular_velocity = states[i].angular
                self.bodies[i].force = states[i].force
                self.bodies[i].torque = states[i].torque
                self.bodies[i].push_velocity = states[i].push
                self.bodies[i].push_angular = states[i].push_angular
            self.events = events^
            self._order = order^
            self.contact_count = count
            self._dirty = dirty
            raise error

    def _step(mut self, h: Float32) raises:
        self._integrate_velocities(h)
        if self.collision_detection == SPHERE_MESH_CCD:
            self._ccd_separation(h)
        if self._dirty:
            self._rebuild()
        var manifolds = self._find_contacts()
        if self.collision_detection == SPHERE_MESH_CCD:
            manifolds = self._ccd_contacts(manifolds, h)
        self._prepare(manifolds, h)
        for _ in range(self.velocity_iterations):
            for m in range(len(manifolds)):
                self._solve_velocity(manifolds[m], h)
        for m in range(len(manifolds)):
            self._restitution(manifolds[m])
        for _ in range(self.position_iterations):
            for m in range(len(manifolds)):
                self._solve_push(manifolds[m], h)
        var impacts = List[_CCDImpact]()
        if self.collision_detection == SPHERE_MESH_CCD:
            impacts = self._ccd_positions(h)
        else:
            self._integrate_positions(h)
        self._report(manifolds)
        for impact in impacts:
            var owner = self._triangle_body[impact.triangle]
            self.contact_count += 1
            self.events.append(
                CollisionEvent(
                    BodyId(impact.body), BodyId(owner), impact.impulse
                )
            )
            self.events.append(
                CollisionEvent(
                    BodyId(owner), BodyId(impact.body), -impact.impulse
                )
            )

    def _validate_ccd(mut self) raises:
        if not (isfinite(self.margin) and self.margin >= 0):
            raise Error("CCD contact margin must be finite and nonnegative")
        if not (isfinite(self.slop) and self.slop >= 0):
            raise Error("CCD contact slop must be finite and nonnegative")
        if not (isfinite(self.push_factor) and self.push_factor >= 0):
            raise Error("CCD push factor must be finite and nonnegative")
        if self.ccd_max_impacts < 1 or self.ccd_max_impacts > 1024:
            raise Error("CCD impact limit must be between 1 and 1024")
        _finite_vector(self.gravity)
        if not (isfinite(self.bounce_threshold) and self.bounce_threshold >= 0):
            raise Error("CCD bounce threshold must be finite and nonnegative")
        for body in self.bodies:
            _ccd_coordinate(body.position)
            _ccd_rotation(body.rotation)
            _ccd_rotation(body.shape_rotation)
            _finite_vector(body.linear_velocity)
            _finite_vector(body.angular_velocity)
            _finite_vector(body.force)
            _finite_vector(body.torque)
            _finite_vector(body.push_velocity)
            _finite_vector(body.push_angular)
            body.material.check()
            if not body.collides:
                continue
            if body.shape.kind == MESH:
                if body.linear_velocity != Vector3(
                    0, 0, 0
                ) or body.angular_velocity != Vector3(0, 0, 0):
                    raise Error("CCD requires motionless static meshes")
                continue
            if body.kind() != DYNAMIC or (
                body.shape.kind != SPHERE and body.shape.kind != CAPSULE
            ):
                raise Error(
                    "CCD supports dynamic spheres and rotation-locked"
                    " capsules against static meshes only"
                )
            if body.shape_position != Vector3(
                0, 0, 0
            ) or body.center_of_mass != Vector3(0, 0, 0):
                raise Error(
                    "CCD requires a shape centered on its body and mass"
                )
            var inverse = body.inverse_inertia()
            if body.shape.kind == CAPSULE:
                # A capsule only translates: every inverse inertia element,
                # its spin and its spin push are zero. Its sweep is then the
                # exact translation of its segment.
                for k in range(9):  # pragma: no branch
                    if inverse.elements[k] != 0:
                        raise Error("CCD requires a rotation-locked capsule")
                if body.angular_velocity != Vector3(
                    0, 0, 0
                ) or body.push_angular != Vector3(0, 0, 0):
                    raise Error("CCD requires a rotation-locked capsule")
                if not (
                    isfinite(body.shape.half_height)
                    and body.shape.half_height >= 0
                    and body.shape.half_height <= 10000
                ):
                    raise Error(
                        "CCD capsule half height must be between 0 and"
                        " 10000 meters"
                    )
            elif not _positive_definite(inverse):
                raise Error(
                    "CCD requires symmetric positive definite sphere inertia"
                )
            if not (
                isfinite(body.shape.radius)
                and body.shape.radius >= 0.0001
                and body.shape.radius <= 10000
            ):
                raise Error(
                    "CCD radius must be between 0.0001 and 10000 meters"
                )
            _ccd_position(body.position, body.shape.radius)
        # Never cache body flags, materials, radius or live solver state.
        # All triangles, even disabled and distant ones, must pass once for
        # this immutable snapshot. Failed validation never marks it valid.
        if not self._ccd_brute_force and self._ccd_index.count == len(
            self._triangles
        ):
            return
        for t in range(len(self._triangles)):
            var triangle = self._triangles[t]
            _ccd_coordinate(triangle.a)
            _ccd_coordinate(triangle.b)
            _ccd_coordinate(triangle.c)
            var normal = _wide_cross(
                _wide(triangle.b) - _wide(triangle.a),
                _wide(triangle.c) - _wide(triangle.a),
            )
            var ab = _wide(triangle.b) - _wide(triangle.a)
            var ac = _wide(triangle.c) - _wide(triangle.a)
            var bc = _wide(triangle.c) - _wide(triangle.b)
            var edge = max(
                _wide_dot(ab, ab), max(_wide_dot(ac, ac), _wide_dot(bc, bc))
            )
            if (
                _wide_dot(normal, normal) == 0
                or triangle.raw_normal() == Vector3(0, 0, 0)
                or _wide_dot(normal, normal) * 1099511627776 < edge * edge
            ):
                raise Error(
                    "CCD requires resolved, well-conditioned static triangles"
                )

        if not self._ccd_brute_force:
            self._ccd_index.rebuild(self._triangles)

    def _ccd_separation(self, h: Float32) raises:
        # A total-energy bound includes friction transferring spin to travel.
        # Disjoint reachable balls ensure there are no moving-body contacts,
        # including after an arbitrary number of static-mesh rebounds.
        var reach = List[Float64](length=len(self.bodies), fill=-1)
        var indexed = (
            not self._ccd_brute_force and len(self._ccd_index.nodes) > 0
        )
        var candidates = List[Int]()
        for i in range(len(self.bodies)):
            ref body = self.bodies[i]
            _finite_vector(body.linear_velocity)
            _finite_vector(body.angular_velocity)
            if not body.collides or body.kind() != DYNAMIC:
                continue
            var v = _wide(body.linear_velocity)
            var w = _wide(body.angular_velocity)
            # A rotation-locked capsule has no spin energy to transfer.
            var spin = Float64(0)
            var inverse = body.inverse_inertia()
            if _isotropic(inverse):
                var inertia = Float64(inverse.elements[0])
                if inertia > 0:
                    spin = (
                        _wide_dot(w, w) * Float64(body.inverse_mass()) / inertia
                    )
            else:
                # w^T I w = u^T M^-1 u with u = R^T w in the body frame.
                var turn = rotation_matrix(body.rotation)
                var u = _turn_in(turn, w)
                spin = _wide_dot(u, _solve(inverse, u)) * Float64(
                    body.inverse_mass()
                )
            var speed = sqrt(_wide_dot(v, v) + spin)
            var push = _wide(body.push_velocity)
            var bound = _ccd_bound(body)
            reach[i] = bound + Float64(h) * (
                speed + sqrt(_wide_dot(push, push))
            )
            if reach[i] > bound * 1048576:
                raise Error(
                    "CCD travel exceeds the radius-relative precision bound"
                )
            var count = len(self._triangles)
            if indexed:
                _ = self._ccd_index.query(
                    _wide(body.position),
                    SIMD[DType.float64, 4](0),
                    reach[i] + Float64(self.margin),
                    candidates,
                )
                count = len(candidates)
            for k in range(count):
                var t = candidates[k] if indexed else k
                if self.bodies[self._triangle_body[t]].collides:
                    _ = _sweep_domain(
                        _wide(body.position),
                        SIMD[DType.float64, 4](0),
                        bound,
                        reach[i] + Float64(self.margin),
                        self._triangles[t],
                    )
            for j in range(i):
                if reach[j] < 0:
                    continue
                var offset = _wide(body.position) - _wide(
                    self.bodies[j].position
                )
                var limit = reach[i] + reach[j] + Float64(self.margin)
                if _wide_dot(offset, offset) <= limit * limit:
                    raise Error(
                        "CCD moving-sphere reachable regions must be disjoint"
                    )

    def _ccd_contacts(
        self, manifolds: List[_Manifold], h: Float32
    ) -> List[_Manifold]:
        var out = List[_Manifold]()
        for manifold in manifolds:
            var points = List[_Point]()
            for point in manifold.points:  # pragma: no branch
                var travel = -Float64(
                    self.bodies[manifold.b].linear_velocity.dot(
                        point.contact.normal
                    )
                ) * Float64(h)
                # Keep slow speculative contacts unchanged. A fast body
                # must reach the surface before restitution acts on it.
                if point.contact.depth < 0 and travel > Float64(self.margin):
                    continue
                points.append(point)
            if len(points) > 0:
                out.append(
                    _Manifold(
                        manifold.a, manifold.b, manifold.material, points^
                    )
                )
        return out^

    def _ccd_positions(mut self, h: Float32) raises -> List[_CCDImpact]:
        self._ccd_separation(h)
        var impacts = List[_CCDImpact]()
        var positions = List[Vector3]()
        var rotations = List[Quaternion]()
        var spins = List[Vector3]()
        # Split correction remains the original pose-only correction. The
        # analytic sweep follows the physical, post-solve velocity from it.
        for i in range(len(self.bodies)):
            ref body = self.bodies[i]
            positions.append(body.position)
            rotations.append(body.rotation)
            spins.append(body.angular_velocity)
            if not body.collides or body.kind() != DYNAMIC:
                continue
            var result = self._ccd_sphere(i, h, impacts)
            positions[i] = result[0]
            rotations[i] = result[1]
            spins[i] = self.bodies[i].angular_velocity
        self._integrate_positions(h)
        for i in range(len(self.bodies)):
            for impact in impacts:
                if impact.body == i:
                    # The impact path turns at a constant spin, so the spin
                    # stays the one that made its pose. The integrator's
                    # torque-free precession of an anisotropic tensor
                    # resumes on the next step.
                    self.bodies[i].position = positions[i]
                    self.bodies[i].rotation = rotations[i]
                    self.bodies[i].angular_velocity = spins[i]
                    break
            _ccd_coordinate(self.bodies[i].position)
            _ccd_rotation(self.bodies[i].rotation)
            if self.bodies[i].collides and self.bodies[i].kind() == DYNAMIC:
                _ccd_position(
                    self.bodies[i].position, self.bodies[i].shape.radius
                )
            _finite_vector(self.bodies[i].linear_velocity)
            _finite_vector(self.bodies[i].angular_velocity)
        # Stable time order, then body insertion order and triangle order.
        for i in range(1, len(impacts)):
            var j = i
            while j > 0 and impacts[j - 1].time > impacts[j].time:
                impacts.swap_elements(j - 1, j)
                j -= 1
        return impacts^

    def _ccd_sphere(
        mut self, i: Int, h: Float32, mut impacts: List[_CCDImpact]
    ) raises -> Tuple[Vector3, Quaternion]:
        var rotation = self.bodies[i].rotation
        var push_angular = _wide(self.bodies[i].push_angular)
        var at = _wide(self.bodies[i].position) + _wide(
            self.bodies[i].push_velocity
        ) * Float64(h)
        var velocity = _wide(self.bodies[i].linear_velocity)
        var angular = _wide(self.bodies[i].angular_velocity)
        var radius = Float64(self.bodies[i].shape.radius)
        # A capsule's half axis in the world. Its rotation does not change.
        var half_axis = SIMD[DType.float64, 4](0)
        var capsule = self.bodies[i].shape.kind == CAPSULE
        if capsule:
            half_axis = _wide(
                self.bodies[i]
                .shape_world_rotation()
                .rotate(Vector3(0, 0, self.bodies[i].shape.half_height))
            )
        var bound = _ccd_bound(self.bodies[i])
        var remaining = Float64(h)
        var count = 0
        var indexed = (
            not self._ccd_brute_force and len(self._ccd_index.nodes) > 0
        )
        var candidates = List[Int]()
        while remaining > 0:
            var fraction = Float64(2)
            var normal = SIMD[DType.float64, 4](0)
            var triangle = -1
            var travel = velocity * remaining
            var candidate_count = len(self._triangles)
            if indexed:
                _ = self._ccd_index.query(at, travel, bound, candidates)
                candidate_count = len(candidates)
            for k in range(candidate_count):
                var t = candidates[k] if indexed else k
                if not self.bodies[self._triangle_body[t]].collides:
                    continue
                var hit = _sweep_triangle(
                    at, travel, radius, self._triangles[t]
                )
                if capsule:
                    hit = _sweep_capsule_triangle(
                        at - half_axis,
                        at + half_axis,
                        travel,
                        radius,
                        self._triangles[t],
                    )
                # Tree traversal order cannot choose an equal-time owner.
                # The miss sentinel (2, triangle -1) must never become a hit.
                if hit.fraction < fraction or (
                    hit.fraction == fraction and t < triangle
                ):
                    fraction = hit.fraction
                    normal = hit.normal
                    triangle = t
            if triangle < 0:
                at += travel
                rotation = _ccd_rotate(
                    rotation, angular + push_angular, remaining
                )
                break
            if count == self.ccd_max_impacts:
                raise Error("CCD impact limit exhausted; step rolled back")
            at += travel * fraction
            # Rebuild the shape from the retained center. The original
            # sweep's translated closest point can round differently.
            # Inspect only an initial contact on the winning triangle;
            # incoming travel remains a direction even at the step's end.
            var retained: _SweepHit
            if capsule:
                retained = _initial_capsule_contact(
                    at - half_axis,
                    at + half_axis,
                    travel,
                    radius,
                    self._triangles[triangle],
                )
            else:
                retained = _initial_triangle_contact(
                    at, travel, radius, self._triangles[triangle]
                )
            if retained.fraction == 0:
                normal = retained.normal
            rotation = _ccd_rotate(
                rotation, angular + push_angular, remaining * fraction
            )
            remaining *= 1 - fraction
            var material = self.bodies[i].material.combine(
                self.bodies[self._triangle_body[triangle]].material
            )
            var approach = _wide_dot(velocity, normal)
            var restitution = Float64(0)
            if approach <= -Float64(self.bounce_threshold):
                restitution = Float64(material.restitution)
            var inverse_mass = Float64(self.bodies[i].inverse_mass())
            var inverse_inertia = Float64(
                self.bodies[i].inverse_inertia().elements[0]
            )
            var normal_impulse = -(1 + restitution) * approach / inverse_mass
            velocity += normal * (normal_impulse * inverse_mass)
            var arm = -normal * radius
            var slip = velocity + _wide_cross(angular, arm)
            var tangent = slip - normal * _wide_dot(slip, normal)
            var speed = sqrt(_wide_dot(tangent, tangent))
            var tensor = self.bodies[i].inverse_inertia()
            if speed > 0 and _isotropic(tensor):
                var impulse = min(
                    speed / (inverse_mass + radius * radius * inverse_inertia),
                    Float64(material.friction) * normal_impulse,
                )
                var friction = -tangent * (impulse / speed)
                velocity += friction * inverse_mass
                angular += _wide_cross(arm, friction) * inverse_inertia
            elif speed > 0:
                # W = R M R^T at the step's start orientation, the one
                # the separation bound measured, so no impact in this step
                # adds energy in that metric. Along the slip,
                # K = 1/m + (r x t)^T W (r x t), which is positive.
                var turn = rotation_matrix(self.bodies[i].rotation)
                var along = tangent / speed
                var lever = _wide_cross(arm, along)
                var resist = inverse_mass + _wide_dot(
                    lever,
                    _turn_out(turn, _apply(tensor, _turn_in(turn, lever))),
                )
                var impulse = min(
                    speed / resist,
                    Float64(material.friction) * normal_impulse,
                )
                var friction = -along * impulse
                velocity += friction * inverse_mass
                angular += _turn_out(
                    turn,
                    _apply(tensor, _turn_in(turn, _wide_cross(arm, friction))),
                )
            velocity = _ccd_close_normal_velocity(
                velocity, normal, -restitution * approach
            )
            impacts.append(
                _CCDImpact(
                    Float64(h) - remaining,
                    i,
                    triangle,
                    _ccd_narrow(normal * normal_impulse),
                )
            )
            count += 1
        self.bodies[i].linear_velocity = _ccd_narrow(velocity)
        self.bodies[i].angular_velocity = _ccd_narrow(angular)
        return (_ccd_narrow(at), rotation)

    def _integrate_velocities(mut self, h: Float32):
        for i in range(len(self.bodies)):
            ref body = self.bodies[i]
            if body.kind() == DYNAMIC:
                var accel = (
                    self.gravity * body.gravity_scale
                    + body.force * body.inverse_mass()
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
            if self.bodies[i].shape.kind == MESH or not self.bodies[i].collides:
                shapes.append(
                    WorldShape.round(Vector3(0, 0, 0), Vector3(0, 0, 0), 0)
                )
                boxes.append(Box3.empty())
            else:
                shapes.append(self._shape(i))
                boxes.append(_box_of(shapes[i]))
        # Keep disabled bodies out of the sweep. Parked actors can share
        # one location; filtering inside _may_touch still visits every pair.
        # Keep their ids so changing collides back to True works next step.
        var active = List[Int]()
        var inactive = List[Int]()
        for i in self._order:
            if self.bodies[i].collides:
                active.append(i)
            else:
                inactive.append(i)
        var count = len(active)
        self._order = active^
        # Insertion sort: the active order changes little from step to step.
        for i in range(1, count):
            var j = i
            while (
                j > 0
                and boxes[self._order[j - 1]].min.x
                > boxes[self._order[j]].min.x
            ):
                self._order.swap_elements(j - 1, j)
                j -= 1
        for i in inactive:
            self._order.append(i)
        var out = List[_Manifold]()
        for i in range(count):
            var a = self._order[i]
            for j in range(i + 1, count):
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
        if not body.is_dynamic():
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
            if self.collision_detection == SPHERE_MESH_CCD:
                var triangle = self._triangles[t]
                var normal = _wide_cross(
                    _wide(triangle.b) - _wide(triangle.a),
                    _wide(triangle.c) - _wide(triangle.a),
                )
                # A sphere's two endpoints are equal. A capsule is behind
                # only when both of its endpoints are, as in mesh_contacts.
                if (
                    _wide_dot(_wide(shape.start) - _wide(triangle.a), normal)
                    < 0
                    and _wide_dot(_wide(shape.end) - _wide(triangle.a), normal)
                    < 0
                ):
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
            ba.inverse_mass()
            + bb.inverse_mass()
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
        ba.linear_velocity = ba.linear_velocity - j * ba.inverse_mass()
        ba.angular_velocity = (
            ba.angular_velocity
            - ba.world_inverse_inertia().transform(cross(p.ra, j))
        )
        ref bb = self.bodies[b]
        bb.linear_velocity = bb.linear_velocity + j * bb.inverse_mass()
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
        ba.push_velocity = ba.push_velocity - j * ba.inverse_mass()
        ba.push_angular = (
            ba.push_angular
            - ba.world_inverse_inertia().transform(cross(p.ra, j))
        )
        ref bb = self.bodies[b]
        bb.push_velocity = bb.push_velocity + j * bb.inverse_mass()
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
            if body.kind() == STATIC:
                continue
            var com = body.world_center_of_mass()
            var w = body.angular_velocity + body.push_angular
            var free_rotation = False
            if body.kind() == DYNAMIC and body._rotate_free(h):
                # Physical drift already updated pose and omega. Split
                # correction remains pose-only, as in the contact solver.
                free_rotation = True
                w = body.push_angular
            var q = body.rotation
            # A second normalization can change the Float32 pose after
            # free drift reconstructed omega from it. Leave that pose
            # untouched unless an actual split correction is required.
            if not free_rotation or w != Vector3(0, 0, 0):
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
    # Round the radius square before subtracting the squared offset.
    # A fused radius*radius - inf can produce -inf instead of the legacy
    # inf - inf NaN. Rounding both squared terms also avoids a one-sided
    # product residual at an exact axis-aligned tangent.
    var h = fma(radius, radius, Float32(0)) - drop.dot(drop)
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


def _ccd_close_normal_velocity(
    var velocity: SIMD[DType.float64, 4],
    normal: SIMD[DType.float64, 4],
    target: Float64,
) -> SIMD[DType.float64, 4]:
    # The sweep normal is a rounded unit vector. Solve its dominant
    # component after friction so the restitution target survives the
    # cancellation of a nearly axial incoming velocity. In exact
    # arithmetic a unit normal makes this closure a no-op. Its residual
    # scales with the final dot-product operands, as _approaches requires.
    var axis = 0
    if abs(normal[1]) > abs(normal[axis]):
        axis = 1
    if abs(normal[2]) > abs(normal[axis]):
        axis = 2
    var first = (axis + 1) % 3
    var second = (axis + 2) % 3
    var other = (
        velocity[first] * normal[first] + velocity[second] * normal[second]
    )
    velocity[axis] = (target - other) / normal[axis]
    return velocity


def _ccd_narrow(value: SIMD[DType.float64, 4]) raises -> Vector3:
    return Vector3(
        _narrow_finite(value[0]),
        _narrow_finite(value[1]),
        _narrow_finite(value[2]),
    )


def _ccd_rotate(
    rotation: Quaternion, angular: SIMD[DType.float64, 4], h: Float64
) raises -> Quaternion:
    var w = _ccd_narrow(angular * h)
    var spin = Quaternion(w.x, w.y, w.z, 0) * rotation
    var out = Quaternion(
        rotation.x + spin.x * 0.5,
        rotation.y + spin.y * 0.5,
        rotation.z + spin.z * 0.5,
        rotation.w + spin.w * 0.5,
    )
    out.normalize()
    return out


def _ccd_coordinate(value: Vector3) raises:
    _finite_vector(value)
    if max(abs(value.x), max(abs(value.y), abs(value.z))) > 1000000:
        raise Error(
            "CCD coordinates must stay within one million meters of the origin"
        )


def _isotropic(inverse: Matrix3) -> Bool:
    # The tensor is its first diagonal element times the identity.
    ref e = inverse.elements
    for k in [1, 2, 3, 5, 6, 7]:  # pragma: no branch
        if e[k] != 0:
            return False
    return e[4] == e[0] and e[8] == e[0]


def _positive_definite(inverse: Matrix3) -> Bool:
    # Exactly symmetric and positive definite by Sylvester's leading
    # principal minors, in Float64. The body already refused a nonfinite
    # entry, and Float64 products of finite Float32 entries stay finite.
    ref e = inverse.elements
    if e[1] != e[3] or e[2] != e[6] or e[5] != e[7]:
        return False
    var first = Float64(e[0])
    var second = first * Float64(e[4]) - Float64(e[1]) * Float64(e[1])
    var third = _determinant(inverse)
    return first > 0 and second > 0 and third > 0


def _determinant(m: Matrix3) -> Float64:
    ref e = m.elements
    return (
        Float64(e[0])
        * (Float64(e[4]) * Float64(e[8]) - Float64(e[7]) * Float64(e[5]))
        - Float64(e[3])
        * (Float64(e[1]) * Float64(e[8]) - Float64(e[7]) * Float64(e[2]))
        + Float64(e[6])
        * (Float64(e[1]) * Float64(e[5]) - Float64(e[4]) * Float64(e[2]))
    )


def _apply(m: Matrix3, v: SIMD[DType.float64, 4]) -> SIMD[DType.float64, 4]:
    # Column-major: element (row, column) is e[column * 3 + row].
    ref e = m.elements
    return SIMD[DType.float64, 4](
        Float64(e[0]) * v[0] + Float64(e[3]) * v[1] + Float64(e[6]) * v[2],
        Float64(e[1]) * v[0] + Float64(e[4]) * v[1] + Float64(e[7]) * v[2],
        Float64(e[2]) * v[0] + Float64(e[5]) * v[1] + Float64(e[8]) * v[2],
        0,
    )


def _turn_in(
    turn: Matrix3, v: SIMD[DType.float64, 4]
) -> SIMD[DType.float64, 4]:
    # R^T v: world to body.
    ref e = turn.elements
    return SIMD[DType.float64, 4](
        Float64(e[0]) * v[0] + Float64(e[1]) * v[1] + Float64(e[2]) * v[2],
        Float64(e[3]) * v[0] + Float64(e[4]) * v[1] + Float64(e[5]) * v[2],
        Float64(e[6]) * v[0] + Float64(e[7]) * v[1] + Float64(e[8]) * v[2],
        0,
    )


def _turn_out(
    turn: Matrix3, v: SIMD[DType.float64, 4]
) -> SIMD[DType.float64, 4]:
    # R v: body to world.
    return _apply(turn, v)


def _solve(m: Matrix3, v: SIMD[DType.float64, 4]) -> SIMD[DType.float64, 4]:
    # Cramer's rule for a validated positive definite tensor.
    ref e = m.elements
    var a = Float64(e[0])
    var b = Float64(e[3])
    var c = Float64(e[6])
    var d = Float64(e[1])
    var f = Float64(e[4])
    var g = Float64(e[7])
    var h = Float64(e[2])
    var k = Float64(e[5])
    var l = Float64(e[8])
    var det = _determinant(m)
    return SIMD[DType.float64, 4](
        (
            v[0] * (f * l - g * k)
            - b * (v[1] * l - g * v[2])
            + c * (v[1] * k - f * v[2])
        )
        / det,
        (
            a * (v[1] * l - g * v[2])
            - v[0] * (d * l - g * h)
            + c * (d * v[2] - v[1] * h)
        )
        / det,
        (
            a * (f * v[2] - v[1] * k)
            - b * (d * v[2] - v[1] * h)
            + v[0] * (d * k - f * h)
        )
        / det,
        0,
    )


def _ccd_bound(body: RigidBody) -> Float64:
    # The radius of a sphere around the body's center that holds its shape.
    # A capsule uses its world half axis, because a quaternion within the
    # unit tolerance can lengthen the axis past its nominal half height.
    var bound = Float64(body.shape.radius)
    if body.shape.kind != CAPSULE:
        return bound
    var half = _wide(
        body.shape_world_rotation().rotate(
            Vector3(0, 0, body.shape.half_height)
        )
    )
    # Round outward: the sum, the root and the addition each round.
    return (bound + sqrt(_wide_dot(half, half))) * 1.000000000000001


def _ccd_rotation(value: Quaternion) raises:
    var norm = (
        Float64(value.x) ** 2
        + Float64(value.y) ** 2
        + Float64(value.z) ** 2
        + Float64(value.w) ** 2
    )
    if not (isfinite(norm) and abs(norm - 1) <= 0.00001):
        raise Error("CCD requires finite unit quaternions")


def _ccd_position(value: Vector3, radius: Float32) raises:
    if (
        Float64(max(abs(value.x), max(abs(value.y), abs(value.z))))
        > Float64(radius) * 65536
    ):
        raise Error(
            "CCD sphere coordinates exceed the radius-relative pose bound"
        )
