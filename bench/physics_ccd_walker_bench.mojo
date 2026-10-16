# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Walker capsules and spinning anisotropic spheres on a terrain mesh.

`physics_ccd_bench.mojo` times isotropic sphere probes and stays fixed.
This bench times the two later CCD contracts: rotation-locked capsules,
as character and walker bodies use, and spheres with an anisotropic
inertia tensor that spin into the ground with friction. The bodies are
collision probes, not validated walker or vehicle models.

After every timed step, and outside the timing, a CCD row checks each
body: an event names its contact with the terrain, and an independent
point-to-triangle distance finds it clear of the nearby terrain within
`_TOLERANCE`. Controls first show that the checks reject a missing
contact and a body pushed into raised terrain.

Run it with `mojo run -I . bench/physics_ccd_walker_bench.mojo`.
"""

from extensions.physics.body import BodyId, DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import SPHERE_MESH_CCD
from extensions.physics.shape import Shape, PhysicsMaterial
from bench.contacts import bodies_missing_contact
from extensions.physics.world import CollisionEvent, PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import floor, sqrt
from std.testing import assert_equal, assert_true
from std.time import perf_counter_ns
from units.si import Length, Mass, Duration

comptime _RADIUS = Float32(0.3)
comptime _HALF = Float32(0.6)
comptime _CELL = 4
# The largest corner height, and the largest slope of any terrain triangle.
comptime _PEAK = Float32(0.16)
comptime _SLOPE = Float64(0.06)
# This bench's numerical allowance for Float32 positions near 100 m, not
# the solver's 5 mm contact slop. A body more than 1 mm inside the
# terrain fails.
comptime _TOLERANCE = Float64(0.001)


def _height(cx: Int, cy: Int) -> Float32:
    # The corner heights repeat 0 to 0.16 m.
    return Float32((cx * 7 + cy * 13) % 5) * 0.04


def _corner(cx: Int, cy: Int) -> Vector3:
    return Vector3(Float32(cx * _CELL), Float32(cy * _CELL), _height(cx, cy))


def _cell(x: Int, y: Int) -> Tuple[Triangle, Triangle]:
    var a = _corner(x, y)
    var b = _corner(x + 1, y)
    var c = _corner(x + 1, y + 1)
    var d = _corner(x, y + 1)
    return (Triangle(a, b, c), Triangle(a, c, d))


def _ground(side: Int) -> List[Triangle]:
    # A gently rolling terrain, 4 m cells, z up.
    var triangles = List[Triangle]()
    for y in range(side):
        for x in range(side):
            var pair = _cell(x, y)
            triangles.append(pair[0])
            triangles.append(pair[1])
    return triangles^


def _wide(v: Vector3) -> SIMD[DType.float64, 4]:
    return SIMD[DType.float64, 4](Float64(v.x), Float64(v.y), Float64(v.z), 0)


def _dot(a: SIMD[DType.float64, 4], b: SIMD[DType.float64, 4]) -> Float64:
    return (a * b).reduce_add()


def _distance(point: Vector3, triangle: Triangle) -> Float64:
    # Ericson's closest point on a triangle, in Float64. It shares no code
    # with the CCD sweep under test.
    var p = _wide(point)
    var a = _wide(triangle.a)
    var b = _wide(triangle.b)
    var c = _wide(triangle.c)
    var ab = b - a
    var ac = c - a
    var ap = p - a
    var d1 = _dot(ab, ap)
    var d2 = _dot(ac, ap)
    var closest: SIMD[DType.float64, 4]
    var bp = p - b
    var d3 = _dot(ab, bp)
    var d4 = _dot(ac, bp)
    var cp = p - c
    var d5 = _dot(ab, cp)
    var d6 = _dot(ac, cp)
    var va = d3 * d6 - d5 * d4
    var vb = d5 * d2 - d1 * d6
    var vc = d1 * d4 - d3 * d2
    if d1 <= 0 and d2 <= 0:
        closest = a
    elif d3 >= 0 and d4 <= d3:
        closest = b
    elif vc <= 0 and d1 >= 0 and d3 <= 0:
        closest = a + ab * (d1 / (d1 - d3))
    elif d6 >= 0 and d5 <= d6:
        closest = c
    elif vb <= 0 and d2 >= 0 and d6 <= 0:
        closest = a + ac * (d2 / (d2 - d6))
    elif va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
        closest = b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
    else:
        var denominator = 1 / (va + vb + vc)
        closest = a + ab * (vb * denominator) + ac * (vc * denominator)
    var gap = p - closest
    return sqrt(_dot(gap, gap))


def _local_height(x: Float32, y: Float32) -> Float64:
    # The terrain height under (x, y): the plane of the triangle there.
    var cx = Int(floor(x / Float32(_CELL)))
    var cy = Int(floor(y / Float32(_CELL)))
    var u = Float64(x) / _CELL - Float64(cx)
    var v = Float64(y) / _CELL - Float64(cy)
    var h00 = Float64(_height(cx, cy))
    var h10 = Float64(_height(cx + 1, cy))
    var h11 = Float64(_height(cx + 1, cy + 1))
    var h01 = Float64(_height(cx, cy + 1))
    if u >= v:
        return h00 + (h10 - h00) * u + (h11 - h10) * v
    return h00 + (h11 - h01) * u + (h01 - h00) * v


def _clearance(center: Vector3, walker: Bool) -> Float64:
    """Return the body's least gap to the nearby terrain, in meters.

    The gap is negative when the body's lowest point is under the local
    terrain height. Otherwise it is the distance from the sphere center,
    or from the lower end of the capsule axis, to the nine nearest cells,
    less the radius. Every terrain triangle slopes at most `_SLOPE`, far
    below 1, so the lower end of an upright axis is its nearest point.
    """
    var radius = Float64(_RADIUS) if walker else Float64(0.1)
    var low = center
    if walker:
        low = center - Vector3(0, 0, _HALF)
    var under = Float64(low.z) - _local_height(low.x, low.y)
    if under < radius - _TOLERANCE:
        return under - radius
    var cx = Int(floor(low.x / Float32(_CELL)))
    var cy = Int(floor(low.y / Float32(_CELL)))
    var nearest = Float64(1e9)
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            var pair = _cell(cx + dx, cy + dy)
            nearest = min(nearest, _distance(low, pair[0]))
            nearest = min(nearest, _distance(low, pair[1]))
    return nearest - radius


def _controls() raises:
    # Repeated events for one body cannot stand in for another body.
    var events = List[CollisionEvent]()
    for _ in range(3):
        events.append(CollisionEvent(BodyId(1), BodyId(0), Vector3(0, 0, 1)))
    assert_equal(bodies_missing_contact(events, 2), 1)
    events.append(CollisionEvent(BodyId(0), BodyId(2), Vector3(0, 0, -1)))
    assert_equal(bodies_missing_contact(events, 2), 1)
    events.append(CollisionEvent(BodyId(2), BodyId(0), Vector3(0, 0, 1)))
    assert_equal(bodies_missing_contact(events, 2), 0)
    # A corner raised 0.16 m. The old check, a global floor at the lowest
    # terrain height, passes a body 5 cm into this corner.
    var raised = _corner(3, 1)
    assert_true(abs(raised.z - _PEAK) < 1e-6)
    for walker in [True, False]:
        var radius = _RADIUS if walker else Float32(0.1)
        var lift = radius + (_HALF if walker else Float32(0))
        var sunk = raised + Vector3(0.2, 0.1, lift - 0.05)
        assert_true(sunk.z >= lift)
        assert_true(_clearance(sunk, walker) < -_TOLERANCE)
        var resting = raised + Vector3(0, 0, lift + 0.002)
        assert_true(_clearance(resting, walker) > -_TOLERANCE)
    # Each terrain triangle is as gentle as `_clearance` assumes.
    for triangle in _ground(8):
        var normal = triangle.b - triangle.a
        normal.cross(triangle.c - triangle.a)
        var flat = sqrt(
            Float64(normal.x) * Float64(normal.x)
            + Float64(normal.y) * Float64(normal.y)
        )
        assert_true(flat <= _SLOPE * Float64(abs(normal.z)) + 1e-9)


def _tensor(xx: Float32, yy: Float32, zz: Float32) -> Matrix3:
    var tensor = Matrix3()
    tensor.elements[0] = xx
    tensor.elements[4] = yy
    tensor.elements[8] = zz
    return tensor


def _world(
    side: Int, bodies: Int, walkers: Bool, continuous: Bool
) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, -9.81)
    if continuous:
        world.collision_detection = SPHERE_MESH_CCD
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh(_ground(side)),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    for i in range(bodies):
        var at = Vector3(
            Float32(2 + 6 * (i % 16)), Float32(2 + 6 * (i // 16)), 0
        )
        if walkers:
            var body = RigidBody(
                DYNAMIC,
                Shape.capsule(Length(_RADIUS), Length(_HALF)),
                Mass(70),
                at,
                Quaternion.identity(),
            )
            # Rotation-locked: every inverse inertia element is zero.
            body.set_inverse_inertia(_tensor(0, 0, 0))
            body.material = PhysicsMaterial(0.8, 0)
            _ = world.add_body(body^)
        else:
            var body = RigidBody(
                DYNAMIC,
                Shape.sphere(Length(0.1)),
                Mass(1),
                at,
                Quaternion.identity(),
            )
            body.set_inverse_inertia(_tensor(250, 500, 125))
            body.material = PhysicsMaterial(0.5, 0.2)
            _ = world.add_body(body^)
    return world^


def _reset(mut world: PhysicsWorld, walkers: Bool):
    # Each step starts above the highest terrain, moving fast into it.
    var lift = _RADIUS + _HALF + _PEAK + 0.1 if walkers else Float32(0.36)
    for i in range(1, len(world.bodies)):
        world.bodies[i].position.z = lift
        world.bodies[i].linear_velocity = Vector3(1.5, -0.5, -30)
        if not walkers:
            world.bodies[i].angular_velocity = Vector3(3, 1, -2)


def _run(name: String, side: Int, bodies: Int, walkers: Bool) raises:
    for continuous in [False, True]:
        var world = _world(side, bodies, walkers, continuous)
        _reset(world, walkers)
        world.step(Duration(0.01))
        var total = Float64(0)
        var maximum = Float64(0)
        var least = Float64(1e9)
        for _ in range(20):
            _reset(world, walkers)
            var start = perf_counter_ns()
            world.step(Duration(0.01))
            var elapsed = Float64(perf_counter_ns() - start) / 1000000
            total += elapsed
            maximum = max(maximum, elapsed)
            # Validation runs after the timed step.
            for i in range(1, len(world.bodies)):
                least = min(
                    least, _clearance(world.bodies[i].position, walkers)
                )
            if continuous:
                assert_equal(bodies_missing_contact(world.events, bodies), 0)
        if continuous:
            assert_true(least > -_TOLERANCE, String(least))
        print(
            name,
            ",",
            continuous,
            ",",
            2 * side * side,
            ",",
            bodies,
            ",",
            total / 20,
            ",",
            maximum,
            ",",
            least,
            sep="",
        )


def main() raises:
    _controls()
    print("scene,ccd,triangles,bodies,mean_step_ms,max_step_ms,least_gap_m")
    # Every body count runs on every terrain size, so the triangle count
    # and the body count change one at a time.
    for side in [32, 64]:
        _run("walker", side, 1, True)
        _run("walker-crowd", side, 64, True)
        _run("spinning-probe", side, 1, False)
        _run("spinning-fleet", side, 64, False)
