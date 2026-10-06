# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Complete Gaussian and physics-mesh ray workloads for issue 550."""

from core.gaussian_splat_utils import create_gaussian_splat_geometry
from core.object3d import NodeId
from core.raycaster import Raycaster
from extensions.physics.body import BodyId, STATIC, RigidBody
from extensions.physics.shape import Shape
from extensions.physics.world import PhysicsWorld
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from objects.gaussian_splat import GaussianSplat
from std.time import perf_counter_ns
from std.testing import assert_true
from units.si import Length, Mass


@no_inline
def gaussian(
    mut shape: GaussianSplat, queries: List[Raycaster]
) raises -> Float64:
    """Raycast every splat set and consume all returned hit fields.

    Args:
        shape: The complete 4096-splat object.
        queries: The 1000 stored ray queries.

    Returns:
        The deterministic result checksum.

    Raises:
        Error: If a raycast fails.
    """
    var sum = Float64(0)
    for query in queries:
        var hits = shape.raycast(Matrix4(), query)
        sum += Float64(len(hits))
        for hit in hits:
            sum += (
                Float64(hit.point.x)
                + 3 * Float64(hit.point.y)
                + 7 * Float64(hit.point.z)
                + Float64(hit.index)
                + 11 * Float64(hit.distance.value)
            )
    return sum


@no_inline
def physics(world: PhysicsWorld) raises -> Float64:
    """Run 5600 complete mesh raycasts and consume all returned fields.

    Args:
        world: The static 2048-triangle world with a prepared Octree.

    Returns:
        The deterministic result checksum.

    Raises:
        Error: If a raycast fails or an expected hit is absent.
    """
    var sum = Float64(0)
    for i in range(5600):
        var x = Float32((i * 17) % 128) + 0.25
        var y = Float32((i * 29 + (i // 128) * 13) % 128) + 0.5
        var hit = world.raycast(
            Vector3(x, y, 5), Vector3(0, 0, -1), Length(10), BodyId(-1)
        )
        assert_true(Bool(hit))
        var found = hit.value()
        var point = found.point
        sum += (
            Float64(point.x)
            + 3 * Float64(point.y)
            + 7 * Float64(point.z)
            + 11 * Float64(found.distance)
            + 13 * Float64(found.normal.x)
            + 17 * Float64(found.normal.y)
            + 19 * Float64(found.normal.z)
            + 23 * Float64(found.body.value)
            + 29 * Float64(found.material.friction)
            + 31 * Float64(found.material.restitution)
        )
    return sum


def main() raises:
    """Build both fixed consumers and measure their complete ray workloads.

    Raises:
        Error: If setup or query execution fails.
    """
    var centers = List[Float32]()
    var covariances = List[Float32]()
    var colors = List[UInt8]()
    for y in range(64):
        for x in range(64):
            centers.extend([Float32(x - 32) * 0.5, Float32(y - 32) * 0.5, -10])
            covariances.extend([Float32(0.04), 0.01, 0, 0.06, 0, 0.03])
            colors.extend([UInt8(255), 255, 255, 255])
    var shape = GaussianSplat(
        create_gaussian_splat_geometry(centers^, covariances^, colors^),
        NodeId(0),
    )
    shape.compute_bounding_sphere()
    var queries = List[Raycaster]()
    for i in range(1000):
        queries.append(
            Raycaster(
                Vector3(Float32(i % 10) * 0.1, Float32(i % 7) * 0.1, 0),
                Vector3(0, 0, -1),
            )
        )
    var start = perf_counter_ns()
    var sum = gaussian(shape, queries)
    print("gaussian", 4096000, perf_counter_ns() - start, sum, sep=",")
    var world = PhysicsWorld()
    var triangles = List[Triangle]()
    for y in range(32):
        for x in range(32):
            var a = Vector3(Float32(x * 4), Float32(y * 4), 0)
            var b = a + Vector3(4, 0, 0)
            var c = a + Vector3(4, 4, 0)
            var d = a + Vector3(0, 4, 0)
            triangles.append(Triangle(a, b, c))
            triangles.append(Triangle(a, c, d))
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh(triangles^),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    world._rebuild()
    start = perf_counter_ns()
    sum = physics(world)
    print("physics_mesh", 5600, perf_counter_ns() - start, sum, sep=",")
