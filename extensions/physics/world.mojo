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
    _approaches,
    _segment_gap,
    _segment_triangle_gap,
    _sweep_segments,
    _turning_step,
    _sweep_capsule_triangle,
    _sweep_convex_triangle,
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
    BOX,
    CAPSULE,
    CONVEX,
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
from math.finite import positive_finite
from math.matrix3 import Matrix3
from math.octree import Octree
from math.quaternion import Quaternion
from math.ray import Ray
from math.triangle import Line3, Triangle
from math.norm import squared_length2
from math.vector3 import Vector3
from std.math import cos, fma, inf, isfinite, sin, sqrt
from units.si import Duration, Length, METER, SECOND


def _impact_exhausted(count: Int, limit: Int) raises:
    """Refuse a step that has used every CCD impact.

    Args:
        count: How many impacts this step has taken.
        limit: How many impacts the step may take.

    Returns:
        Nothing. The call returns when another impact is allowed.

    Raises:
        Error: If the count has reached the limit.
    """
    if count == limit:
        raise Error("CCD impact limit exhausted; step rolled back")


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
    # The static triangle hit, or -1 for another moving body.
    var triangle: Int
    # The other moving body hit, or -1 for a triangle.
    var other: Int
    var impulse: Vector3


struct PhysicsWorld(Movable):
    """Bodies, static meshes, and the solver that steps them."""

    var bodies: List[RigidBody]
    # Discrete by default. CCD refuses unsupported colliding worlds.
    var collision_detection: CollisionDetection
    # Per sphere and step. Exhaustion rolls back the complete step.
    var ccd_max_impacts: Int
    # Per turning body and step. Exhaustion rolls back the complete step.
    var ccd_max_substeps: Int
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
        self.ccd_max_substeps = 256
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
        if not (positive_finite(Float64(h))):
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
            # Refuse an unsupported world before any contact work. The
            # groups are found again after the solver changes velocities.
            _ = self._ccd_separation(h)
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
            var owner = impact.other
            if owner < 0:
                owner = self._triangle_body[impact.triangle]
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
        if self.ccd_max_substeps < 1 or self.ccd_max_substeps > 65536:
            raise Error("CCD sub-step limit must be between 1 and 65536")
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
            var kinematic = body.kind() == KINEMATIC
            if kinematic:
                # A kinematic sphere follows its set velocity. With no spin,
                # an impact in its frame cannot add energy; see
                # _ccd_separation.
                if body.shape.kind != SPHERE:
                    raise Error("CCD supports kinematic spheres only")
                if body.angular_velocity != Vector3(
                    0, 0, 0
                ) or body.push_angular != Vector3(0, 0, 0):
                    raise Error("CCD requires a kinematic sphere without spin")
            elif body.kind() != DYNAMIC:
                raise Error(
                    "CCD supports dynamic spheres, capsules, boxes and hulls"
                    " against static meshes only"
                )
            if kinematic and (
                body.shape_position != Vector3(0, 0, 0)
                or body.center_of_mass != Vector3(0, 0, 0)
            ):
                raise Error(
                    "CCD requires a kinematic shape centered on its body"
                    " and mass"
                )
            if not (
                body.shape_position.length() <= 10000
                and body.center_of_mass.length() <= 10000
            ):
                raise Error(
                    "CCD shape and mass offsets must be at most 10000 m"
                )
            var inverse = body.inverse_inertia()
            if _solid(body):
                # A box or hull only translates, swept exactly; see
                # _ccd_convex. It must not turn.
                if (
                    not _locked(inverse)
                    or body.angular_velocity != Vector3(0, 0, 0)
                    or body.push_angular != Vector3(0, 0, 0)
                ):
                    raise Error("CCD requires a box or hull that cannot turn")
            elif body.shape.kind == CAPSULE:
                # A capsule with every inverse inertia element zero cannot
                # turn, so it must have no spin or spin push. Any other
                # capsule turns, with a positive definite tensor.
                if _locked(inverse):
                    if body.angular_velocity != Vector3(
                        0, 0, 0
                    ) or body.push_angular != Vector3(0, 0, 0):
                        raise Error(
                            "CCD requires a capsule that cannot turn to have"
                            " no spin"
                        )
                elif not _positive_definite(inverse):
                    raise Error(
                        "CCD requires symmetric positive definite capsule"
                        " inertia"
                    )
                if not (
                    isfinite(body.shape.half_height)
                    and body.shape.half_height >= 0
                    and body.shape.half_height <= 10000
                ):
                    raise Error(
                        "CCD capsule half height must be between 0 and"
                        " 10000 meters"
                    )
            elif not kinematic and not _positive_definite(inverse):
                raise Error(
                    "CCD requires symmetric positive definite sphere inertia"
                )
            if not (
                isfinite(_ccd_scale(body))
                and _ccd_scale(body) >= 0.0001
                and _ccd_scale(body) <= 10000
            ):
                raise Error(
                    "CCD radius must be between 0.0001 and 10000 meters"
                )
            _ccd_position(body.position, _ccd_scale(body))
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

    def _ccd_separation(self, h: Float32) raises -> List[Int]:
        # A total-energy bound includes friction transferring spin to travel.
        # Moving bodies whose reachable balls overlap form a group. An impact
        # can give one member every other member's energy, so each member of
        # a group reaches as far as the group's whole energy can take it.
        # Groups grow until no two of them overlap. A body alone keeps its
        # own bound, which covers any number of static-mesh rebounds. Each
        # body's group is named by its lowest member, or -1 when it does not
        # move or collide.
        var count = len(self.bodies)
        var speed = List[Float64](length=count, fill=-1)
        var push = List[Float64](length=count, fill=0)
        var bound = List[Float64](length=count, fill=0)
        var group = List[Int](length=count, fill=-1)
        var center = List[SIMD[DType.float64, 4]](
            length=count, fill=SIMD[DType.float64, 4](0)
        )
        var kinematic = List[Bool](length=count, fill=False)
        for i in range(count):
            ref body = self.bodies[i]
            _finite_vector(body.linear_velocity)
            _finite_vector(body.angular_velocity)
            if not body.collides or body.kind() == STATIC:
                continue
            kinematic[i] = body.kind() == KINEMATIC
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
            speed[i] = sqrt(_wide_dot(v, v) + spin)
            var p = _wide(body.push_velocity)
            push[i] = sqrt(_wide_dot(p, p))
            bound[i] = _ccd_bound(body)
            center[i] = _wide(body.position)
            if self._ccd_turns(i):
                # A turning shape's points move at |v| + |w| L, and
                # |w|^2 <= w^T I w lambda_max(I^-1), at most the energy
                # times the mass times the trace of I^-1.
                var lever = self._ccd_lever(i)
                var trace = (
                    Float64(inverse.elements[0])
                    + Float64(inverse.elements[4])
                    + Float64(inverse.elements[8])
                )
                speed[i] *= 1 + lever * sqrt(
                    trace / Float64(body.inverse_mass())
                )
                bound[i] = lever + Float64(body.shape.radius)
                center[i] = _wide(body.world_center_of_mass())
            group[i] = i
        var reach = List[Float64](length=count, fill=-1)
        var merged = True
        while merged:
            merged = False
            # Twice each group's dynamic kinetic energy, the sum of m s^2,
            # its fastest kinematic speed, its heaviest dynamic mass and
            # its dynamic member count.
            var energy = List[Float64](length=count, fill=0)
            var fast = List[Float64](length=count, fill=0)
            var heaviest = List[Float64](length=count, fill=0)
            var dynamic = List[Int](length=count, fill=0)
            var size = List[Int](length=count, fill=0)
            for i in range(count):
                if group[i] < 0:
                    continue
                size[group[i]] += 1
                if kinematic[i]:
                    fast[group[i]] = max(fast[group[i]], speed[i])
                    continue
                var mass = 1 / Float64(self.bodies[i].inverse_mass())
                energy[group[i]] += speed[i] * speed[i] * mass
                heaviest[group[i]] = max(heaviest[group[i]], mass)
                dynamic[group[i]] += 1
            for i in range(count):
                if group[i] < 0:
                    continue
                var most = speed[i]
                if size[group[i]] > 1 and not kinematic[i]:
                    # In a kinematic sphere's frame an impact cannot add
                    # energy, so it raises a member's speed by at most twice
                    # the kinematic speed, and the square root of the
                    # group's energy by at most that times the root of the
                    # heaviest mass. Each such impact counts against the
                    # impact limit of a dynamic member.
                    var g = group[i]
                    var root = sqrt(energy[g]) + 2 * fast[g] * sqrt(
                        heaviest[g]
                    ) * Float64(self.ccd_max_impacts * dynamic[g])
                    most = root * sqrt(Float64(self.bodies[i].inverse_mass()))
                reach[i] = bound[i] + Float64(h) * (most + push[i])
            for i in range(count):
                for j in range(i):
                    if group[j] < 0 or group[i] < 0 or group[i] == group[j]:
                        continue
                    var offset = center[i] - center[j]
                    var limit = reach[i] + reach[j] + Float64(self.margin)
                    if _wide_dot(offset, offset) <= limit * limit:
                        var keep = min(group[i], group[j])
                        var drop = max(group[i], group[j])
                        for k in range(count):  # pragma: no branch
                            if group[k] == drop:
                                group[k] = keep
                        merged = True
        var indexed = (
            not self._ccd_brute_force and len(self._ccd_index.nodes) > 0
        )
        var candidates = List[Int]()
        for i in range(count):
            if group[i] < 0:
                continue
            if reach[i] > bound[i] * 1048576:
                raise Error(
                    "CCD travel exceeds the radius-relative precision bound"
                )
            if self._ccd_turns(i) or _solid(self.bodies[i]):
                for j in range(count):  # pragma: no branch
                    if j != i and group[j] == group[i]:
                        raise Error(
                            "CCD turning bodies, boxes and hulls must not"
                            " reach another moving body"
                        )
            if kinematic[i]:
                # A kinematic sphere passes through static meshes.
                continue
            var triangles = len(self._triangles)
            if indexed:
                _ = self._ccd_index.query(
                    center[i],
                    SIMD[DType.float64, 4](0),
                    reach[i] + Float64(self.margin),
                    candidates,
                )
                triangles = len(candidates)
            for k in range(triangles):
                var t = candidates[k] if indexed else k
                if self.bodies[self._triangle_body[t]].collides:
                    _ = _sweep_domain(
                        center[i],
                        SIMD[DType.float64, 4](0),
                        bound[i],
                        reach[i] + Float64(self.margin),
                        self._triangles[t],
                    )
        return group^

    def _ccd_contacts(
        self, manifolds: List[_Manifold], h: Float32
    ) -> List[_Manifold]:
        var out = List[_Manifold]()
        for manifold in manifolds:
            var points = List[_Point]()
            for point in manifold.points:  # pragma: no branch
                var travel = -Float64(
                    (
                        self.bodies[manifold.b].linear_velocity
                        - self.bodies[manifold.a].linear_velocity
                    ).dot(point.contact.normal)
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
        var group = self._ccd_separation(h)
        var impacts = List[_CCDImpact]()
        var positions = List[Vector3]()
        var rotations = List[Quaternion]()
        var spins = List[Vector3]()
        var members = List[List[Int]]()
        for i in range(len(self.bodies)):
            ref body = self.bodies[i]
            positions.append(body.position)
            rotations.append(body.rotation)
            spins.append(body.angular_velocity)
            members.append(List[Int]())
            if group[i] >= 0:
                members[group[i]].append(i)
        # Split correction remains the original pose-only correction. The
        # analytic sweep follows the physical, post-solve velocity from it.
        # A body alone sweeps by itself; a group sweeps in time order.
        var turned = List[Bool](length=len(self.bodies), fill=False)
        for i in range(len(self.bodies)):
            if len(members[i]) == 1 and self.bodies[i].kind() == DYNAMIC:
                var result: Tuple[Vector3, Quaternion]
                if self._ccd_turns(i):
                    # Its pose and spin always come from the sweep, which
                    # turns at a constant spin along the certified path.
                    result = self._ccd_turning(i, h, impacts)
                    turned[i] = True
                elif _solid(self.bodies[i]):
                    result = self._ccd_convex(i, h, impacts)
                else:
                    result = self._ccd_sphere(i, h, impacts)
                positions[i] = result[0]
                rotations[i] = result[1]
                spins[i] = self.bodies[i].angular_velocity
            elif len(members[i]) > 1:
                var poses = self._ccd_group(members[i], h, impacts)
                for k in range(len(members[i])):  # pragma: no branch
                    var j = members[i][k]
                    positions[j] = poses[k][0]
                    rotations[j] = poses[k][1]
                    spins[j] = self.bodies[j].angular_velocity
        self._integrate_positions(h)
        var impacted = List[Bool](length=len(self.bodies), fill=False)
        for impact in impacts:
            impacted[impact.body] = True
            if impact.other >= 0:
                impacted[impact.other] = True
        for i in range(len(self.bodies)):
            # A kinematic sphere keeps the integrator's prescribed path.
            if (impacted[i] or turned[i]) and self.bodies[i].kind() == DYNAMIC:
                # The impact path turns at a constant spin, so the spin
                # stays the one that made its pose. The integrator's
                # torque-free precession of an anisotropic tensor
                # resumes on the next step.
                self.bodies[i].position = positions[i]
                self.bodies[i].rotation = rotations[i]
                self.bodies[i].angular_velocity = spins[i]
            _ccd_coordinate(self.bodies[i].position)
            _ccd_rotation(self.bodies[i].rotation)
            if self.bodies[i].collides and self.bodies[i].kind() == DYNAMIC:
                _ccd_position(
                    self.bodies[i].position, _ccd_scale(self.bodies[i])
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
        var half_axis = self._ccd_half_axis(i)
        var remaining = Float64(h)
        var count = 0
        var candidates = List[Int]()
        while remaining > 0:
            var travel = velocity * remaining
            var first = self._ccd_first_hit(
                i, at, travel, half_axis, candidates
            )
            var fraction = first[0].fraction
            var triangle = first[1]
            if triangle < 0:
                at += travel
                rotation = _ccd_rotate(
                    rotation, angular + push_angular, remaining
                )
                break
            _impact_exhausted(count, self.ccd_max_impacts)
            at += travel * fraction
            rotation = _ccd_rotate(
                rotation, angular + push_angular, remaining * fraction
            )
            remaining *= 1 - fraction
            var wall = self._ccd_wall(
                i,
                triangle,
                at,
                travel,
                half_axis,
                first[0].normal,
                velocity,
                angular,
            )
            impacts.append(
                _CCDImpact(
                    Float64(h) - remaining,
                    i,
                    triangle,
                    -1,
                    _ccd_narrow(wall[1] * wall[0]),
                )
            )
            count += 1
        self.bodies[i].linear_velocity = _ccd_narrow(velocity)
        self.bodies[i].angular_velocity = _ccd_narrow(angular)
        return (_ccd_narrow(at), rotation)

    def _ccd_convex(
        mut self, i: Int, h: Float32, mut impacts: List[_CCDImpact]
    ) raises -> Tuple[Vector3, Quaternion]:
        # A box or hull that only translates, swept exactly by the
        # separating-axis test over time; see _sweep_convex_triangle. Each
        # impact is a linear impulse with restitution and friction.
        var shape = self._shape(i)
        var shift = _wide(self.bodies[i].push_velocity) * Float64(h)
        var corners = List[SIMD[DType.float64, 4]]()
        for corner in shape.polyhedron.vertices:  # pragma: no branch
            corners.append(_wide(corner) + shift)
        var faces = List[SIMD[DType.float64, 4]]()
        for normal in shape.polyhedron.normals:  # pragma: no branch
            faces.append(_wide(normal))
        var edges = List[SIMD[DType.float64, 4]]()
        for k in range(len(shape.polyhedron.edge_a)):  # pragma: no branch
            edges.append(
                _wide(shape.polyhedron.vertices[shape.polyhedron.edge_b[k]])
                - _wide(shape.polyhedron.vertices[shape.polyhedron.edge_a[k]])
            )
        var start = _wide(self.bodies[i].position) + shift
        var moved = SIMD[DType.float64, 4](0)
        var velocity = _wide(self.bodies[i].linear_velocity)
        var angular = SIMD[DType.float64, 4](0)
        var bound = _ccd_bound(self.bodies[i])
        var indexed = (
            not self._ccd_brute_force and len(self._ccd_index.nodes) > 0
        )
        var candidates = List[Int]()
        var remaining = Float64(h)
        var count = 0
        while remaining > 0:
            var travel = velocity * remaining
            var near = len(self._triangles)
            if indexed:
                _ = self._ccd_index.query(
                    start + moved, travel, bound, candidates
                )
                # In triangle order, so an equal time keeps the lowest.
                sort(candidates)
                near = len(candidates)
            var now = List[SIMD[DType.float64, 4]]()
            for corner in corners:  # pragma: no branch
                now.append(corner + moved)
            var fraction = Float64(2)
            var normal = SIMD[DType.float64, 4](0)
            var triangle = -1
            for c in range(near):
                var index = candidates[c] if indexed else c
                if not self.bodies[self._triangle_body[index]].collides:
                    continue
                var hit = _sweep_convex_triangle(
                    now, faces, edges, travel, self._triangles[index]
                )
                if hit.fraction < fraction:
                    fraction = hit.fraction
                    normal = hit.normal
                    triangle = index
            if triangle < 0:
                moved += travel
                break
            _impact_exhausted(count, self.ccd_max_impacts)
            count += 1
            moved += travel * fraction
            remaining *= 1 - fraction
            var impulse = self._ccd_rigid(
                i,
                self._triangle_body[triangle],
                SIMD[DType.float64, 4](0),
                normal,
                velocity,
                angular,
            )
            impacts.append(
                _CCDImpact(
                    Float64(h) - remaining,
                    i,
                    triangle,
                    -1,
                    _ccd_narrow(normal * impulse),
                )
            )
        self.bodies[i].linear_velocity = _ccd_narrow(velocity)
        return (_ccd_narrow(start + moved), self.bodies[i].rotation)

    def _ccd_turns(self, i: Int) -> Bool:
        # A dynamic shape that can turn, or that sits off its body or mass
        # center, takes the sub-stepped sweep. A centered sphere and a
        # centered capsule that cannot turn keep their exact sweeps.
        ref body = self.bodies[i]
        if body.kind() != DYNAMIC or _solid(body):
            return False
        if body.shape_position != Vector3(
            0, 0, 0
        ) or body.center_of_mass != Vector3(0, 0, 0):
            return True
        return body.shape.kind == CAPSULE and not _locked(
            body.inverse_inertia()
        )

    def _ccd_ends(
        self, i: Int, rotation: Quaternion
    ) -> Tuple[SIMD[DType.float64, 4], SIMD[DType.float64, 4]]:
        # The shape's segment ends from the mass center, in the world, at
        # this rotation; a sphere's two ends are its center.
        ref body = self.bodies[i]
        var half = Vector3(0, 0, 0)
        if body.shape.kind == CAPSULE:
            half = body.shape_rotation.rotate(
                Vector3(0, 0, body.shape.half_height)
            )
        var middle = body.shape_position - body.center_of_mass
        return (
            _wide(rotation.rotate(middle - half)),
            _wide(rotation.rotate(middle + half)),
        )

    def _ccd_lever(self, i: Int) -> Float64:
        # The farthest segment end from the mass center, rounded outward.
        var ends = self._ccd_ends(i, self.bodies[i].rotation)
        return (
            max(
                sqrt(_wide_dot(ends[0], ends[0])),
                sqrt(_wide_dot(ends[1], ends[1])),
            )
            * 1.000000000000001
        )

    def _ccd_turning(
        mut self, i: Int, h: Float32, mut impacts: List[_CCDImpact]
    ) raises -> Tuple[Vector3, Quaternion]:
        # Conservative advancement with a second-order bound. Each
        # sub-step lasts as long as every nearby triangle stays clear of
        # the true rigid path, within a radius-relative tolerance; see
        # _turning_step. A triangle that the shape touches and closes on
        # takes a rigid impulse at the contact point. The mass center moves
        # at a constant velocity and the body turns at a constant spin.
        var rotation = self.bodies[i].rotation
        var center = _wide(self.bodies[i].world_center_of_mass()) + _wide(
            self.bodies[i].push_velocity
        ) * Float64(h)
        var velocity = _wide(self.bodies[i].linear_velocity)
        var angular = _wide(self.bodies[i].angular_velocity)
        var turning = _wide(self.bodies[i].push_angular)
        var radius = Float64(self.bodies[i].shape.radius)
        var tolerance = radius / 1024
        var indexed = (
            not self._ccd_brute_force and len(self._ccd_index.nodes) > 0
        )
        # An impulse can turn spin into translation, changing the reach.
        # Query again after each impact; between impacts the velocities
        # stay fixed, so this segment's endpoint-speed bound is sufficient.
        var candidates = List[Int]()
        var near = len(self._triangles)
        var refresh = indexed
        var lever = self._ccd_lever(i)
        var remaining = Float64(h)
        var steps = 0
        var count = 0
        while remaining > 0:
            if steps == self.ccd_max_substeps:
                raise Error("CCD sub-step limit exhausted; step rolled back")
            steps += 1
            var spin = angular + turning
            if refresh:
                var speed = (
                    sqrt(_wide_dot(velocity, velocity))
                    + sqrt(_wide_dot(spin, spin)) * lever
                )
                _ = self._ccd_index.query(
                    center,
                    SIMD[DType.float64, 4](0),
                    lever + radius + remaining * speed + Float64(self.margin),
                    candidates,
                )
                # Equal-time closing contacts keep triangle insertion order.
                sort(candidates)
                near = len(candidates)
                refresh = False
            var ends = self._ccd_ends(i, rotation)
            var at = (center + ends[0], center + ends[1])
            var speeds = (
                velocity + _wide_cross(spin, ends[0]),
                velocity + _wide_cross(spin, ends[1]),
            )
            # A point's path bends at |w|^2 times its distance from the
            # spin axis through the mass center: the ends bound it.
            var curvature = Float64(0)
            var square = _wide_dot(spin, spin)
            if square > 0:
                var low = ends[0] - spin * (_wide_dot(ends[0], spin) / square)
                var high = ends[1] - spin * (_wide_dot(ends[1], spin) / square)
                curvature = (
                    square
                    * max(
                        sqrt(_wide_dot(low, low)), sqrt(_wide_dot(high, high))
                    )
                    * 1.000000000000001
                )
            var step = remaining
            var triangle = -1
            var normal = SIMD[DType.float64, 4](0)
            var point = SIMD[DType.float64, 4](0)
            for c in range(near):
                var index = candidates[c] if indexed else c
                if not self.bodies[self._triangle_body[index]].collides:
                    continue
                var clear = _turning_step(
                    at,
                    speeds,
                    radius,
                    tolerance,
                    curvature,
                    self._triangles[index],
                )
                if clear < 0:
                    continue
                var gap = _segment_triangle_gap(
                    at[0], at[1] - at[0], self._triangles[index]
                )
                if triangle < 0 and gap[0] <= radius + tolerance:
                    # The contact point's velocity closes on the triangle.
                    var contact = gap[2] - gap[1] * radius
                    if _approaches(
                        velocity + _wide_cross(angular, contact - center),
                        gap[1],
                    ):
                        triangle = index
                        normal = gap[1]
                        point = contact
                step = min(step, clear)
            if triangle >= 0:
                _impact_exhausted(count, self.ccd_max_impacts)
                count += 1
                var impulse = self._ccd_rigid(
                    i,
                    self._triangle_body[triangle],
                    point - center,
                    normal,
                    velocity,
                    angular,
                )
                impacts.append(
                    _CCDImpact(
                        Float64(h) - remaining,
                        i,
                        triangle,
                        -1,
                        _ccd_narrow(normal * impulse),
                    )
                )
                refresh = indexed
                continue
            center += velocity * step
            rotation = _ccd_turn(rotation, spin, step)
            remaining -= step
        self.bodies[i].linear_velocity = _ccd_narrow(velocity)
        self.bodies[i].angular_velocity = _ccd_narrow(angular)
        var final = _ccd_narrow(center) - rotation.rotate(
            self.bodies[i].center_of_mass
        )
        return (final, rotation)

    def _ccd_rigid(
        self,
        i: Int,
        other: Int,
        arm: SIMD[DType.float64, 4],
        normal: SIMD[DType.float64, 4],
        mut velocity: SIMD[DType.float64, 4],
        mut angular: SIMD[DType.float64, 4],
    ) -> Float64:
        # A rigid impulse on body i at `arm` from its mass center, against
        # a static body, along `normal` toward body i. The tensor is the
        # world one at the step's start orientation, the one the reach
        # bound measured, so no impulse adds energy in that metric. Returns
        # the normal impulse.
        var mass = Float64(self.bodies[i].inverse_mass())
        var material = self.bodies[i].material.combine(
            self.bodies[other].material
        )
        var approach = _wide_dot(velocity + _wide_cross(angular, arm), normal)
        var restitution = Float64(0)
        if approach <= -Float64(self.bounce_threshold):
            restitution = Float64(material.restitution)
        var lever = _wide_cross(arm, normal)
        var impulse = (
            -(1 + restitution)
            * approach
            / (mass + _wide_dot(lever, self._ccd_spin(i, lever)))
        )
        velocity += normal * (impulse * mass)
        angular += self._ccd_spin(i, lever * impulse)
        var slip = velocity + _wide_cross(angular, arm)
        var tangent = slip - normal * _wide_dot(slip, normal)
        var speed = sqrt(_wide_dot(tangent, tangent))
        if speed > 0:
            var along = tangent / speed
            var side = _wide_cross(arm, along)
            var friction = min(
                speed / (mass + _wide_dot(side, self._ccd_spin(i, side))),
                Float64(material.friction) * impulse,
            )
            velocity -= along * (friction * mass)
            angular -= self._ccd_spin(i, side * friction)
            # A tangential impulse at an arm turns the body, which can close
            # the contact again. Open it to zero closing speed: that impulse
            # changes the energy by -v^2 / (2 K), so it cannot add any.
            var closing = _wide_dot(
                velocity + _wide_cross(angular, arm), normal
            )
            if closing < 0:
                var extra = -closing / (
                    mass + _wide_dot(lever, self._ccd_spin(i, lever))
                )
                velocity += normal * (extra * mass)
                angular += self._ccd_spin(i, lever * extra)
                impulse += extra
        return impulse

    def _ccd_half_axis(self, i: Int) -> SIMD[DType.float64, 4]:
        # A capsule's half axis in the world, or zero for a sphere. A
        # rotation-locked capsule's axis does not change during a step.
        if self.bodies[i].shape.kind != CAPSULE:
            return SIMD[DType.float64, 4](0)
        return _wide(
            self.bodies[i]
            .shape_world_rotation()
            .rotate(Vector3(0, 0, self.bodies[i].shape.half_height))
        )

    def _ccd_first_hit(
        self,
        i: Int,
        at: SIMD[DType.float64, 4],
        travel: SIMD[DType.float64, 4],
        half_axis: SIMD[DType.float64, 4],
        mut candidates: List[Int],
    ) raises -> Tuple[_SweepHit, Int]:
        # The earliest static triangle that body i reaches along `travel`,
        # or the miss sentinel (2, -1).
        var radius = Float64(self.bodies[i].shape.radius)
        var capsule = self.bodies[i].shape.kind == CAPSULE
        var indexed = (
            not self._ccd_brute_force and len(self._ccd_index.nodes) > 0
        )
        var fraction = Float64(2)
        var normal = SIMD[DType.float64, 4](0)
        var triangle = -1
        var candidate_count = len(self._triangles)
        if indexed:
            _ = self._ccd_index.query(
                at, travel, _ccd_bound(self.bodies[i]), candidates
            )
            candidate_count = len(candidates)
        for k in range(candidate_count):
            var t = candidates[k] if indexed else k
            if not self.bodies[self._triangle_body[t]].collides:
                continue
            var hit = _sweep_triangle(at, travel, radius, self._triangles[t])
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
        return (_SweepHit(fraction, normal), triangle)

    def _ccd_wall(
        self,
        i: Int,
        triangle: Int,
        at: SIMD[DType.float64, 4],
        travel: SIMD[DType.float64, 4],
        half_axis: SIMD[DType.float64, 4],
        var normal: SIMD[DType.float64, 4],
        mut velocity: SIMD[DType.float64, 4],
        mut angular: SIMD[DType.float64, 4],
    ) raises -> Tuple[Float64, SIMD[DType.float64, 4]]:
        # Body i's response to a static triangle at the impact center `at`.
        # Returns the normal impulse and the normal it acts along.
        var radius = Float64(self.bodies[i].shape.radius)
        # Rebuild the shape from the retained center. The original
        # sweep's translated closest point can round differently.
        # Inspect only an initial contact on the winning triangle;
        # incoming travel remains a direction even at the step's end.
        var retained: _SweepHit
        if self.bodies[i].shape.kind == CAPSULE:
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
        return (normal_impulse, normal)

    def _ccd_group(
        mut self, members: List[Int], h: Float32, mut impacts: List[_CCDImpact]
    ) raises -> List[Tuple[Vector3, Quaternion]]:
        # Spheres whose reachable balls overlap move together in time order.
        # Each pass finds the earliest impact of any member with a static
        # triangle or another member, moves every member to that time, and
        # applies that one impulse. Equal times keep the lower member, a
        # triangle before a member, and then the lower other member.
        var n = len(members)
        var at = List[SIMD[DType.float64, 4]]()
        var velocity = List[SIMD[DType.float64, 4]]()
        var angular = List[SIMD[DType.float64, 4]]()
        var turning = List[SIMD[DType.float64, 4]]()
        var rotation = List[Quaternion]()
        var count = List[Int](length=n, fill=0)
        # Dynamic members respond; kinematic ones keep their velocity.
        var moves = List[Bool]()
        var half = List[SIMD[DType.float64, 4]]()
        for i in members:  # pragma: no branch
            ref body = self.bodies[i]
            moves.append(body.kind() == DYNAMIC)
            half.append(self._ccd_half_axis(i))
            at.append(
                _wide(body.position) + _wide(body.push_velocity) * Float64(h)
            )
            velocity.append(_wide(body.linear_velocity))
            angular.append(_wide(body.angular_velocity))
            turning.append(_wide(body.push_angular))
            rotation.append(body.rotation)
        var none = SIMD[DType.float64, 4](0)
        var candidates = List[Int]()
        var remaining = Float64(h)
        # The remaining time at the previous impact, and how many impacts
        # this instant has had. A second impact at the same instant starts
        # a cascade.
        var last = Float64(-1)
        var instant = 0
        while remaining > 0:
            var fraction = Float64(2)
            var normal = none
            var first = -1
            var second = -1
            var triangle = -1
            for k in range(n):  # pragma: no branch
                if moves[k]:
                    var hit = self._ccd_first_hit(
                        members[k],
                        at[k],
                        velocity[k] * remaining,
                        half[k],
                        candidates,
                    )
                    if hit[0].fraction < fraction:
                        fraction = hit[0].fraction
                        normal = hit[0].normal
                        first = k
                        second = -1
                        triangle = hit[1]
                for l in range(k + 1, n):
                    if not (moves[k] or moves[l]):
                        continue
                    # Each member is a segment: a capsule's axis, or a
                    # sphere's center. The normal runs from l toward k.
                    var pair = _sweep_segments(
                        at[k] - half[k],
                        half[k] * 2,
                        at[l] - half[l],
                        half[l] * 2,
                        (velocity[k] - velocity[l]) * remaining,
                        Float64(self.bodies[members[k]].shape.radius)
                        + Float64(self.bodies[members[l]].shape.radius),
                    )
                    if pair.fraction < fraction:
                        fraction = pair.fraction
                        normal = pair.normal
                        first = k
                        second = l
                        triangle = -1
            if first < 0:
                for k in range(n):  # pragma: no branch
                    at[k] += velocity[k] * remaining
                    rotation[k] = _ccd_rotate(
                        rotation[k], angular[k] + turning[k], remaining
                    )
                break
            var cascade = fraction == 0 and remaining == last
            instant = instant + 1 if cascade else 1
            last = remaining * (1 - fraction)
            var incoming = velocity[first] * remaining
            var step = remaining * fraction
            for k in range(n):  # pragma: no branch
                at[k] += velocity[k] * step
                rotation[k] = _ccd_rotate(
                    rotation[k], angular[k] + turning[k], step
                )
            remaining *= 1 - fraction
            var i = members[first]
            var other = (
                members[second] if second
                >= 0 else self._triangle_body[triangle]
            )
            var approach = _wide_dot(velocity[first], normal)
            if second >= 0:
                approach -= _wide_dot(velocity[second], normal)
            # A cascade of plastic impacts at one instant only halves the
            # speeds each round, and a bouncing one can go on too. Settle
            # every touching contact together, plastically, instead.
            if cascade and (
                instant > 2 * n or not self._ccd_bounces(i, other, approach)
            ):
                # Each settling pass costs an impact, so a pass that opens
                # nothing cannot repeat at one instant without bound.
                _ccd_spend(count, first, self.ccd_max_impacts, moves)
                if second >= 0:
                    _ccd_spend(count, second, self.ccd_max_impacts, moves)
                self._ccd_settle(
                    members,
                    moves,
                    half,
                    at,
                    velocity,
                    Float64(h) - remaining,
                    count,
                    impacts,
                    candidates,
                )
                continue
            _ccd_spend(count, first, self.ccd_max_impacts, moves)
            if second < 0:
                var wall = self._ccd_wall(
                    i,
                    triangle,
                    at[first],
                    incoming,
                    half[first],
                    normal,
                    velocity[first],
                    angular[first],
                )
                impacts.append(
                    _CCDImpact(
                        Float64(h) - remaining,
                        i,
                        triangle,
                        -1,
                        _ccd_narrow(wall[1] * wall[0]),
                    )
                )
                continue
            _ccd_spend(count, second, self.ccd_max_impacts, moves)
            var j = members[second]
            # Two elements of one list cannot both be passed mutably.
            var va = velocity[first]
            var wa = angular[first]
            var vb = velocity[second]
            var wb = angular[second]
            var impulse = self._ccd_pair(i, j, normal, va, wa, vb, wb)
            velocity[first] = va
            angular[first] = wa
            velocity[second] = vb
            angular[second] = wb
            impacts.append(
                _CCDImpact(
                    Float64(h) - remaining,
                    i,
                    -1,
                    j,
                    _ccd_narrow(normal * impulse),
                )
            )
        var poses = List[Tuple[Vector3, Quaternion]]()
        for k in range(n):  # pragma: no branch
            ref body = self.bodies[members[k]]
            body.linear_velocity = _ccd_narrow(velocity[k])
            body.angular_velocity = _ccd_narrow(angular[k])
            poses.append((_ccd_narrow(at[k]), rotation[k]))
        return poses^

    def _ccd_bounces(self, i: Int, other: Int, approach: Float64) -> Bool:
        # Whether an impact of body i and `other` at this approach speed
        # rebounds: restitution above zero and a hit above the threshold.
        var material = self.bodies[i].material.combine(
            self.bodies[other].material
        )
        return material.restitution > 0 and approach <= -Float64(
            self.bounce_threshold
        )

    def _ccd_settle(
        self,
        members: List[Int],
        moves: List[Bool],
        half: List[SIMD[DType.float64, 4]],
        at: List[SIMD[DType.float64, 4]],
        mut velocity: List[SIMD[DType.float64, 4]],
        time: Float64,
        mut count: List[Int],
        mut impacts: List[_CCDImpact],
        mut candidates: List[Int],
    ) raises:
        # Every contact touching at this instant: member pairs at their
        # summed radius, and member triangles that the member approaches.
        # A sphere's impulses act through its center, and a capsule cannot
        # turn, so they only change velocities, and the contact matrix
        # needs only inverse masses.
        var n = len(members)
        var body = List[Int]()
        var partner = List[Int]()
        var triangle = List[Int]()
        var normal = List[SIMD[DType.float64, 4]]()
        var indexed = (
            not self._ccd_brute_force and len(self._ccd_index.nodes) > 0
        )
        for k in range(n):  # pragma: no branch
            var radius = Float64(self.bodies[members[k]].shape.radius)
            # A kinematic member passes through static meshes.
            var near = 0
            if moves[k]:
                near = len(self._triangles)
                if indexed:
                    _ = self._ccd_index.query(
                        at[k],
                        SIMD[DType.float64, 4](0),
                        # A contact lies within the radius of the whole
                        # segment: the capsule-aware bound, plus the radius.
                        _ccd_bound(self.bodies[members[k]]) + radius,
                        candidates,
                    )
                    near = len(candidates)
            for c in range(near):
                var index = candidates[c] if indexed else c
                if not self.bodies[self._triangle_body[index]].collides:
                    continue
                # A sphere is a capsule of no length.
                var hit = _initial_capsule_contact(
                    at[k] - half[k],
                    at[k] + half[k],
                    velocity[k],
                    radius,
                    self._triangles[index],
                )
                if hit.fraction == 0:
                    body.append(k)
                    partner.append(-1)
                    triangle.append(index)
                    normal.append(hit.normal)
            for l in range(k + 1, n):
                if not (moves[k] or moves[l]):
                    continue
                var reach = radius + Float64(
                    self.bodies[members[l]].shape.radius
                )
                var gap = _segment_gap(
                    at[k] - half[k], half[k] * 2, at[l] - half[l], half[l] * 2
                )
                if gap[0] <= reach * (1 + 1e-9):
                    body.append(k)
                    partner.append(l)
                    triangle.append(-1)
                    normal.append(gap[1])
        var m = len(body)
        var inverse = List[Float64]()
        for k in range(n):  # pragma: no branch
            inverse.append(Float64(self.bodies[members[k]].inverse_mass()))
        var matrix = List[Float64](length=m * m, fill=0)
        var closing = List[Float64](length=m, fill=0)
        for c in range(m):  # pragma: no branch
            closing[c] = _wide_dot(velocity[body[c]], normal[c])
            if partner[c] >= 0:
                closing[c] -= _wide_dot(velocity[partner[c]], normal[c])
            for d in range(m):  # pragma: no branch
                # The change in contact c's closing speed per unit impulse
                # at contact d.
                var share = Float64(0)
                if body[c] == body[d]:
                    share += inverse[body[c]]
                if body[c] == partner[d]:
                    share -= inverse[body[c]]
                if partner[c] >= 0 and partner[c] == body[d]:
                    share -= inverse[partner[c]]
                if partner[c] >= 0 and partner[c] == partner[d]:
                    share += inverse[partner[c]]
                matrix[c * m + d] = share * _wide_dot(normal[c], normal[d])
        var impulse = _ccd_lcp(matrix, closing)
        for c in range(m):  # pragma: no branch
            if impulse[c] <= 0:
                continue
            _ccd_spend(count, body[c], self.ccd_max_impacts, moves)
            velocity[body[c]] += normal[c] * (impulse[c] * inverse[body[c]])
            if partner[c] >= 0:
                _ccd_spend(count, partner[c], self.ccd_max_impacts, moves)
                velocity[partner[c]] -= normal[c] * (
                    impulse[c] * inverse[partner[c]]
                )
            impacts.append(
                _CCDImpact(
                    time,
                    members[body[c]],
                    triangle[c],
                    members[partner[c]] if partner[c] >= 0 else -1,
                    _ccd_narrow(normal[c] * impulse[c]),
                )
            )

    def _ccd_pair(
        self,
        i: Int,
        j: Int,
        normal: SIMD[DType.float64, 4],
        mut va: SIMD[DType.float64, 4],
        mut wa: SIMD[DType.float64, 4],
        mut vb: SIMD[DType.float64, 4],
        mut wb: SIMD[DType.float64, 4],
    ) -> Float64:
        # Spheres i and j touch along `normal`, from j's center to i's.
        # Returns the normal impulse on i. The arms are parallel to the
        # normal, so spin does not change the normal response. Restitution
        # between zero and one and Coulomb friction that at most stops the
        # slip cannot add kinetic energy.
        var ma = Float64(self.bodies[i].inverse_mass())
        var mb = Float64(self.bodies[j].inverse_mass())
        var ra = -normal * Float64(self.bodies[i].shape.radius)
        var rb = normal * Float64(self.bodies[j].shape.radius)
        var material = self.bodies[i].material.combine(self.bodies[j].material)
        var approach = _wide_dot(va - vb, normal)
        var restitution = Float64(0)
        if approach <= -Float64(self.bounce_threshold):
            restitution = Float64(material.restitution)
        var impulse = -(1 + restitution) * approach / (ma + mb)
        va += normal * (impulse * ma)
        vb -= normal * (impulse * mb)
        var slip = va + _wide_cross(wa, ra) - vb - _wide_cross(wb, rb)
        var tangent = slip - normal * _wide_dot(slip, normal)
        var speed = sqrt(_wide_dot(tangent, tangent))
        if speed > 0:
            var along = tangent / speed
            var la = _wide_cross(ra, along)
            var lb = _wide_cross(rb, along)
            var resist = (
                ma
                + mb
                + _wide_dot(la, self._ccd_spin(i, la))
                + _wide_dot(lb, self._ccd_spin(j, lb))
            )
            var friction = -along * min(
                speed / resist, Float64(material.friction) * impulse
            )
            va += friction * ma
            wa += self._ccd_spin(i, _wide_cross(ra, friction))
            vb -= friction * mb
            wb += self._ccd_spin(j, _wide_cross(rb, -friction))
        return impulse

    def _ccd_spin(
        self, i: Int, torque: SIMD[DType.float64, 4]
    ) -> SIMD[DType.float64, 4]:
        # The world inverse inertia at the step's start orientation, the one
        # the separation bound measured, times an angular impulse.
        var tensor = self.bodies[i].inverse_inertia()
        if _isotropic(tensor):
            return torque * Float64(tensor.elements[0])
        var turn = rotation_matrix(self.bodies[i].rotation)
        return _turn_out(turn, _apply(tensor, _turn_in(turn, torque)))

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
                # A box or hull is behind when all of its corners are.
                var ahead = False
                if shape.is_round():
                    ahead = (
                        _wide_dot(
                            _wide(shape.start) - _wide(triangle.a), normal
                        )
                        >= 0
                        or _wide_dot(
                            _wide(shape.end) - _wide(triangle.a), normal
                        )
                        >= 0
                    )
                else:
                    for (
                        corner
                    ) in shape.polyhedron.vertices:  # pragma: no branch
                        if (
                            _wide_dot(_wide(corner) - _wide(triangle.a), normal)
                            >= 0
                        ):
                            ahead = True
                if not ahead:
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
            var size = sqrt(squared_length2[DType.float32](t1, t2))
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
        return _triangle_ray_hit(
            ray,
            tri.a,
            tri.b,
            tri.c,
            reach,
            best,
            owner,
            self.bodies[owner].material,
        )

    def _shape_hit(self, ray: Ray, i: Int) -> Optional[RaycastHit]:
        return _shape_ray_hit(ray, self._shape(i), i, self.bodies[i].material)


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


def _triangle_ray_hit(
    ray: Ray,
    a: Vector3,
    b: Vector3,
    c: Vector3,
    reach: Float32,
    best: Optional[RaycastHit],
    owner: Int,
    material: PhysicsMaterial,
) -> Optional[RaycastHit]:
    """Return the nearer hit of a ray on one triangle, or `best`."""
    var met = ray.intersect_triangle(a, b, c, True)
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
        unit_or(cross(b - a, c - a), Vector3(0, 0, 1)),
        distance,
        material,
    )


def _shape_ray_hit(
    ray: Ray, shape: WorldShape, body: Int, material: PhysicsMaterial
) -> Optional[RaycastHit]:
    """Return where a ray enters one placed shape.

    A round shape is the nearest of its two end spheres and its side.
    A box or a hull is the convex clip.

    Args:
        ray: The ray, in world space.
        shape: The shape, already placed.
        body: The body that owns the shape.
        material: The body's material.

    Returns:
        The hit, or none when the ray misses.
    """
    if not shape.is_round():
        return _polyhedron_hit(ray, shape.polyhedron, body, material)
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
        BodyId(body),
        point,
        unit_or(point - on, -ray.direction),
        best,
        material,
    )


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


def _ccd_lcp(
    matrix: List[Float64], closing: List[Float64]
) raises -> List[Float64]:
    # Plastic simultaneous contacts: impulses x >= 0 with closing speeds
    # w = A x + b >= 0 and x_c w_c = 0. A = J M^-1 J^T is positive
    # semidefinite, so the impulses cannot add kinetic energy: the change
    # is -x^T A x / 2. Active sets are tried in one fixed order, so the
    # answer is deterministic.
    var m = len(closing)
    if m > 10:
        raise Error("CCD simultaneous contacts exceed ten; step rolled back")
    var scale = Float64(0)
    var largest = Float64(0)
    for c in range(m):
        scale = max(scale, abs(closing[c]))
        for d in range(m):  # pragma: no branch
            largest = max(largest, abs(matrix[c * m + d]))
    var tolerance = scale * 1e-9
    for mask in range(1 << m):  # pragma: no branch
        var active = List[Int]()
        for c in range(m):
            if (mask >> c) & 1 == 1:
                active.append(c)
        var size = len(active)
        var width = size + 1
        # Solve A_SS x_S = -b_S by elimination with partial pivoting.
        var rows = List[Float64](length=size * width, fill=0)
        for r in range(size):
            for s in range(size):  # pragma: no branch
                rows[r * width + s] = matrix[active[r] * m + active[s]]
            rows[r * width + size] = -closing[active[r]]
        var solved = True
        for column in range(size):
            var pivot = column
            for r in range(column + 1, size):
                if abs(rows[r * width + column]) > abs(
                    rows[pivot * width + column]
                ):
                    pivot = r
            if abs(rows[pivot * width + column]) <= largest * 1e-12:
                solved = False
                break
            for s in range(width):  # pragma: no branch
                var swap = rows[column * width + s]
                rows[column * width + s] = rows[pivot * width + s]
                rows[pivot * width + s] = swap
            for r in range(column + 1, size):
                var factor = (
                    rows[r * width + column] / rows[column * width + column]
                )
                for s in range(column, width):  # pragma: no branch
                    rows[r * width + s] -= factor * rows[column * width + s]
        if not solved:
            continue
        var impulse = List[Float64](length=m, fill=0)
        for r in reversed(range(size)):
            var value = rows[r * width + size]
            for s in range(r + 1, size):
                value -= rows[r * width + s] * impulse[active[s]]
            impulse[active[r]] = value / rows[r * width + r]
        var valid = True
        for c in range(m):
            var speed = closing[c]
            for d in range(m):  # pragma: no branch
                speed += matrix[c * m + d] * impulse[d]
            if impulse[c] < -tolerance or speed < -tolerance:
                valid = False
        if valid:
            for c in range(m):
                impulse[c] = max(impulse[c], Float64(0))
            return impulse^
    raise Error("CCD could not resolve simultaneous contacts; step rolled back")


def _locked(inverse: Matrix3) -> Bool:
    # Every inverse inertia element is zero: the body cannot turn.
    for k in range(9):  # pragma: no branch
        if inverse.elements[k] != 0:
            return False
    return True


def _ccd_turn(
    rotation: Quaternion, spin: SIMD[DType.float64, 4], h: Float64
) -> Quaternion:
    # The exact turn at a constant spin for a time h, about the spin axis
    # by |spin| h, so the pose lies on the path that the sweep certified.
    var size = sqrt(_wide_dot(spin, spin))
    if size == 0:
        return rotation
    var half = size * h / 2
    var axis = spin * (sin(half) / size)
    var turn = Quaternion(
        Float32(axis[0]), Float32(axis[1]), Float32(axis[2]), Float32(cos(half))
    )
    var out = turn * rotation
    out.normalize()
    return out


def _ccd_spend(
    mut count: List[Int], k: Int, limit: Int, moves: List[Bool]
) raises:
    # One impact of a group member. Exhaustion rolls back the whole step.
    # A kinematic member's impacts count against the dynamic member hit.
    if not moves[k]:
        return
    _impact_exhausted(count[k], limit)
    count[k] += 1


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


def _solid(body: RigidBody) -> Bool:
    # A box or a hull: a flat-faced convex shape.
    return body.shape.kind == BOX or body.shape.kind == CONVEX


def _ccd_scale(body: RigidBody) -> Float32:
    # The length that relative precision bounds use: the radius of a round
    # shape, or the bounding radius of a box or hull.
    if _solid(body):
        return Float32(_ccd_bound(body))
    return body.shape.radius


def _ccd_bound(body: RigidBody) -> Float64:
    # The radius of a sphere around the body's center that holds its shape.
    # A capsule uses its world half axis, because a quaternion within the
    # unit tolerance can lengthen the axis past its nominal half height. A
    # box or hull uses its farthest world corner.
    if _solid(body):
        var turn = body.shape_world_rotation()
        var offset = _wide(body.shape_world_position() - body.position)
        var most = Float64(0)
        for corner in body.shape.polyhedron.vertices:  # pragma: no branch
            var at = offset + _wide(turn.rotate(corner))
            most = max(most, sqrt(_wide_dot(at, at)))
        return most * 1.000000000000001
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
