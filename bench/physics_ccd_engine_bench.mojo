# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Turning box chassis, turning walkers and interacting bodies on terrain.

`physics_ccd_bench.mojo` and `physics_ccd_walker_bench.mojo` stay fixed.
This bench times the conservative-advancement engine of issue 635:

- `chassis` and `chassis-fleet`: a 1500 kg box, 4.5 m by 2 m by 1.5 m,
  with its own anisotropic tensor, falls onto the terrain while it rolls,
  pitches and yaws. It is a collision probe for a vehicle body, not a
  validated vehicle model: it has no wheels or suspension.
- `walker-pairs`: turning capsule walkers in pairs that walk into each
  other while they fall onto the terrain, so each pair is one group.
- `pile`: a turning box falls onto a resting ball and a resting cube.
- `rollback`: the `pile` step with a one-impact limit, which fails and
  restores the world. The row reports the rollback storage too.

After every timed step, and outside the timing, a CCD row checks each
body: an event names its contact with the terrain or another body, and
every corner or axis end is clear of the terrain within the body's
tolerance, by an independent local-height test. Controls first show that
the checks reject a missing contact and a body pushed into raised terrain.

Run it with `mojo run -I . bench/physics_ccd_engine_bench.mojo`.
"""

from extensions.physics.body import BodyId, DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import SPHERE_MESH_CCD
from extensions.physics.shape import BOX, CAPSULE, PhysicsMaterial, Shape
from extensions.physics.world import CollisionEvent, PhysicsWorld, _StepState
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import cos, floor, sin
from std.sys import size_of
from std.testing import assert_equal, assert_true
from std.time import perf_counter_ns
from units.si import Duration, Length, Mass

comptime _CELL = 4
comptime _PEAK = Float32(0.16)
# Every terrain triangle slopes at most 0.06, so a vertical gap overstates
# a depth by at most 0.2 percent.
comptime _SLOPE = Float64(0.06)


def _height(cx: Int, cy: Int) -> Float32:
    # The corner heights repeat 0 to 0.16 m.
    return Float32((cx * 7 + cy * 13) % 5) * 0.04


def _corner(cx: Int, cy: Int) -> Vector3:
    return Vector3(Float32(cx * _CELL), Float32(cy * _CELL), _height(cx, cy))


def _ground(side: Int) -> List[Triangle]:
    var triangles = List[Triangle]()
    for y in range(side):
        for x in range(side):
            var a = _corner(x, y)
            var b = _corner(x + 1, y)
            var c = _corner(x + 1, y + 1)
            var d = _corner(x, y + 1)
            triangles.append(Triangle(a, b, c))
            triangles.append(Triangle(a, c, d))
    return triangles^


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


def _points(world: PhysicsWorld, i: Int) -> List[Vector3]:
    # A box's corners, or a sphere's or capsule's lowest point.
    ref body = world.bodies[i]
    var out = List[Vector3]()
    if body.shape.kind == BOX:
        for corner in world._shape(i).polyhedron.vertices:
            out.append(corner)
        return out^
    var at = body.shape_world_position()
    var half = Vector3(0, 0, 0)
    if body.shape.kind == CAPSULE:
        half = body.shape_world_rotation().rotate(
            Vector3(0, 0, body.shape.half_height)
        )
    var low = at - half if half.z > 0 else at + half
    out.append(low - Vector3(0, 0, body.shape.radius))
    return out^


def _clearance(world: PhysicsWorld, i: Int) -> Float64:
    """Return the body's least vertical gap to the terrain under it.

    A negative value is a depth. The terrain slopes at most `_SLOPE`, so a
    vertical depth is at most 1.002 times the depth along the normal.
    """
    var least = Float64(1e9)
    for point in _points(world, i):
        least = min(least, Float64(point.z) - _local_height(point.x, point.y))
    return least


def _missing(events: List[CollisionEvent], bodies: Int) -> Int:
    """Return how many bodies 1 to `bodies` no event names."""
    var touched = List[Bool](length=bodies + 1, fill=False)
    for event in events:
        if event.body.value > 0 and event.body.value <= bodies:
            touched[event.body.value] = True
    var missing = 0
    for i in range(1, bodies + 1):
        if not touched[i]:
            missing += 1
    return missing


def _tolerance(world: PhysicsWorld, i: Int) -> Float64:
    # Twice the engine's tolerance, which is 1/1024 of the bounding radius
    # of a box, or of the radius of a sphere or capsule, with the slope
    # allowance. A body that another body presses on can deepen an overlap
    # by one tolerance in a sub-step before its response opens it.
    ref body = world.bodies[i]
    var scale = Float64(body.shape.radius)
    if body.shape.kind == BOX:
        var most = Float64(0)
        for corner in body.shape.polyhedron.vertices:
            most = max(most, Float64(corner.length()))
        scale = most
    return 2 * scale / 1024 * 1.002 + 1e-6


def _chassis(at: Vector3) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.box(Length(2.25), Length(1), Length(0.75)),
        Mass(1500),
        at,
        Quaternion.identity(),
    )
    body.material = PhysicsMaterial(0.8, 0.1)
    return body^


def _walker(at: Vector3) raises -> RigidBody:
    # A capsule that can turn, with a solid rod's inertia.
    var body = RigidBody(
        DYNAMIC,
        Shape.capsule(Length(0.3), Length(0.6)),
        Mass(70),
        at,
        Quaternion.identity(),
    )
    var tensor = Matrix3()
    tensor.elements[0] = 0.12
    tensor.elements[4] = 0.12
    tensor.elements[8] = 0.3
    body.set_inverse_inertia(tensor)
    body.material = PhysicsMaterial(0.8, 0)
    return body^


def _controls() raises:
    # Repeated events for one body cannot stand in for another body.
    var events = List[CollisionEvent]()
    for _ in range(3):
        events.append(CollisionEvent(BodyId(1), BodyId(0), Vector3(0, 0, 1)))
    assert_equal(_missing(events, 2), 1)
    events.append(CollisionEvent(BodyId(2), BodyId(0), Vector3(0, 0, 1)))
    assert_equal(_missing(events, 2), 0)
    # A chassis 5 cm into a raised corner is rejected, and one 2 mm above
    # it passes.
    var world = PhysicsWorld()
    var raised = _corner(3, 1)
    assert_true(abs(raised.z - _PEAK) < 1e-6)
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh(_ground(8)),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    _ = world.add_body(_chassis(raised + Vector3(0.5, 0.5, 0.75 - 0.05)))
    assert_true(_clearance(world, 1) < -_tolerance(world, 1))
    world.bodies[1].position = raised + Vector3(0.5, 0.5, 0.75 + 0.2)
    assert_true(_clearance(world, 1) > -_tolerance(world, 1))
    for triangle in _ground(8):
        var normal = triangle.b - triangle.a
        normal.cross(triangle.c - triangle.a)
        var flat = Float64(normal.x) * Float64(normal.x) + Float64(
            normal.y
        ) * Float64(normal.y)
        assert_true(flat <= _SLOPE * _SLOPE * Float64(normal.z * normal.z))


def _home(group: Int, scene: String) -> Tuple[Int, Int]:
    # Groups stand 12 m apart on a grid of eight columns. A pile's ball is
    # light, so the group's energy bound lets it reach far: piles stand
    # 48 m apart, four to a row, except in the crowded scene.
    if scene == "pile":
        return (6 + 48 * (group % 4), 6 + 48 * (group // 4))
    return (6 + 12 * (group % 8), 6 + 12 * (group // 8))


def _world(
    side: Int, scene: String, bodies: Int, continuous: Bool
) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, -9.81)
    if continuous:
        world.collision_detection = SPHERE_MESH_CCD
    if scene == "pile" or scene == "pile-crowd":
        # A turning chassis that grinds on a ball over the terrain re-closes
        # each time it turns: each response costs an impact.
        world.ccd_max_impacts = 1024
        world.ccd_max_substeps = 65536
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
            Float32(_home(i, scene)[0]), Float32(_home(i, scene)[1]), 0
        )
        if scene == "walker-pairs":
            _ = world.add_body(_walker(at))
            _ = world.add_body(_walker(at + Vector3(1.0, 0, 0)))
        elif scene == "pile" or scene == "pile-crowd":
            _ = world.add_body(_chassis(at))
            var ball = RigidBody(
                DYNAMIC,
                Shape.sphere(Length(0.4)),
                Mass(20),
                at,
                Quaternion.identity(),
            )
            ball.material = PhysicsMaterial(0.5, 0)
            _ = world.add_body(ball^)
            var cube = RigidBody(
                DYNAMIC,
                Shape.box(Length(0.5), Length(0.5), Length(0.5)),
                Mass(200),
                at,
                Quaternion.identity(),
            )
            cube.material = PhysicsMaterial(0.5, 0)
            _ = world.add_body(cube^)
        else:
            _ = world.add_body(_chassis(at))
    return world^


def _reset(mut world: PhysicsWorld, scene: String):
    # Each step starts every group at its home, above the highest terrain,
    # moving fast into it. A driving chassis instead moves level, clear of
    # the terrain, and yaws.
    var i = 1
    var group = 0
    while i < len(world.bodies):
        var x = Float32(_home(group, scene)[0])
        var y = Float32(_home(group, scene)[1])
        group += 1
        if scene == "walker-pairs":
            for k in range(2):
                ref body = world.bodies[i + k]
                body.position = Vector3(
                    x + Float32(k), y, _PEAK + 0.3 + 0.6 + 0.05
                )
                body.rotation = Quaternion.identity()
                var side = Float32(1 - 2 * k)
                body.linear_velocity = Vector3(3 * side, 0, -40)
                body.angular_velocity = Vector3(0, 2 * side, 1)
            i += 2
            continue
        ref chassis = world.bodies[i]
        chassis.position = Vector3(x, y, _PEAK + 0.75 + 0.35)
        chassis.rotation = Quaternion(
            Float32(sin(0.05)), Float32(sin(0.03)), 0, Float32(cos(0.06))
        )
        chassis.rotation.normalize()
        chassis.linear_velocity = Vector3(20, 2, -40)
        chassis.angular_velocity = Vector3(1.5, -1, 2)
        if scene == "drive":
            chassis.position.z = _PEAK + 0.75 + 0.5
            chassis.linear_velocity = Vector3(20, 2, 0)
            chassis.angular_velocity = Vector3(0, 0, 0.5)
        if scene == "pile" or scene == "pile-crowd":
            # The ball and the cube rest on the terrain, and the chassis
            # starts 0.35 m above the higher of them, less its tilt.
            chassis.position.z = _PEAK + 1 + 0.75 + 0.35
            ref ball = world.bodies[i + 1]
            ball.position = Vector3(
                x, y - 0.6, Float32(_local_height(x, y - 0.6)) + 0.401
            )
            ball.linear_velocity = Vector3(0, 0, 0)
            ball.angular_velocity = Vector3(0, 0, 0)
            ref cube = world.bodies[i + 2]
            cube.position = Vector3(x + 1, y + 0.5, _PEAK + 0.5 + 0.002)
            cube.rotation = Quaternion.identity()
            cube.linear_velocity = Vector3(0, 0, 0)
            cube.angular_velocity = Vector3(0, 0, 0)
            i += 3
            continue
        i += 1


def _storage(world: PhysicsWorld) -> Int:
    # The bytes a CCD step copies so that it can roll back.
    return (
        size_of[_StepState]() * len(world.bodies)
        + size_of[CollisionEvent]() * len(world.events)
        + size_of[Int]() * len(world._order)
    )


def _run(name: String, side: Int, groups: Int, scene: String) raises:
    for continuous in [False, True]:
        var world = _world(side, scene, groups, continuous)
        _reset(world, scene)
        world.step(Duration(0.01))
        var total = Float64(0)
        var maximum = Float64(0)
        var least = Float64(1e9)
        for _ in range(20):
            _reset(world, scene)
            var start = perf_counter_ns()
            world.step(Duration(0.01))
            var elapsed = Float64(perf_counter_ns() - start) / 1000000
            total += elapsed
            maximum = max(maximum, elapsed)
            # Validation runs after the timed step.
            for i in range(1, len(world.bodies)):
                var gap = _clearance(world, i)
                least = min(least, gap)
                if continuous:
                    assert_true(
                        gap > -_tolerance(world, i), String(name, i, gap)
                    )
            if continuous and scene != "drive":
                assert_equal(_missing(world.events, len(world.bodies) - 1), 0)
        print(
            name,
            ",",
            continuous,
            ",",
            2 * side * side,
            ",",
            len(world.bodies) - 1,
            ",",
            total / 20,
            ",",
            maximum,
            ",",
            least,
            ",",
            _storage(world),
            sep="",
        )


def _rollback(side: Int, groups: Int) raises:
    # A one-impact limit cannot finish the pile, so each step fails and
    # restores every body. The row times the failed step.
    var world = _world(side, "pile", groups, True)
    world.ccd_max_impacts = 1
    var total = Float64(0)
    var maximum = Float64(0)
    for _ in range(20):
        _reset(world, "pile")
        var before = world.bodies.copy()
        var start = perf_counter_ns()
        try:
            world.step(Duration(0.01))
            raise Error("the step did not fail")
        except error:
            assert_true(String(error).find("limit exhausted") >= 0)
        var elapsed = Float64(perf_counter_ns() - start) / 1000000
        total += elapsed
        maximum = max(maximum, elapsed)
        for i in range(len(before)):
            assert_true(world.bodies[i].position == before[i].position)
            assert_true(
                world.bodies[i].linear_velocity == before[i].linear_velocity
            )
    print(
        "rollback,True,",
        2 * side * side,
        ",",
        len(world.bodies) - 1,
        ",",
        total / 20,
        ",",
        maximum,
        ",,",
        _storage(world),
        sep="",
    )


def main() raises:
    _controls()
    print(
        "scene,ccd,triangles,bodies,mean_step_ms,max_step_ms,least_gap_m,"
        "rollback_bytes"
    )
    _run("chassis-drive", 64, 32, "drive")
    _run("chassis", 32, 1, "chassis")
    _run("chassis-fleet", 64, 32, "chassis")
    _run("walker-pairs", 64, 32, "walker-pairs")
    _run("pile", 64, 16, "pile")
    _run("pile-crowd", 64, 16, "pile-crowd")
    _rollback(64, 16)
