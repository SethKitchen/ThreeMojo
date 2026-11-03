# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The negative energy of an Alcubierre bubble, as a solid that turns.

    mojo run -I . examples/warp_surface.mojo [path.png]

The page is Warp drives. The exact solver finds the energy density that
the Eulerian observer measures, on a grid around a bubble that moves
along x at half the speed of light. The surface holds every place where
the density is below a third of its least value. It is a ring around the
direction of travel: the bubble needs no energy straight ahead or
behind. The thin rod marks the direction of travel.
"""

from tools._example_output import (
    example_destination,
    gallery_camera,
    gallery_renderer,
    spin_gallery,
    warm_lamp,
)
from tools._example_preview import Triangles

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.surface_nets import mesh_surface
from extensions.warp.analytic import exact_stress_energy, sample_metric
from extensions.warp.frame import to_eulerian
from extensions.warp.grid import SpacetimeGrid
from extensions.warp.metrics import AlcubierreMetric
from extensions.warp.quantities import fraction_of_light
from generators.utils import Vec3d
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import floor
from units.si import (
    Angle,
    DEGREE,
    Duration64,
    InverseLength64,
    Length,
    Length64,
    METER,
)

comptime DEFAULT_OUTPUT = "out/warp-surface.png"
comptime WIDTH = 320
comptime HEIGHT = 220
comptime FRAMES = 36
comptime DELAY_MS = 60
# Points along each axis, and the step between them, in meters.
comptime SIDE = 41
comptime STEP = 0.2


@fieldwise_init
struct DensityField(DistanceField):
    """The energy density on a grid, as an implicit solid.

    The solid holds the places where the density is below a level. The
    value between grid points is the trilinear interpolation. Scene x is
    the direction of travel, scene y is the physical z and scene z is the
    physical y.
    """

    var values: List[Float64]
    var level: Float64
    var scale: Float64

    def distance(self, point: Vector3) -> Float32:
        """Return how far a place is outside the solid, roughly in meters.

        Args:
            point: The place in the scene, in meters.

        Returns:
            Negative inside the solid.
        """
        var half = Float64(SIDE - 1) / 2.0
        var gx = Float64(point.x) / STEP + half
        var gy = Float64(point.z) / STEP + half
        var gz = Float64(point.y) / STEP + half
        var top = Float64(SIDE - 1) - 1e-9
        gx = min(max(gx, 0.0), top)
        gy = min(max(gy, 0.0), top)
        gz = min(max(gz, 0.0), top)
        var x0 = Int(floor(gx))
        var y0 = Int(floor(gy))
        var z0 = Int(floor(gz))
        var fx = gx - Float64(x0)
        var fy = gy - Float64(y0)
        var fz = gz - Float64(z0)
        var total = 0.0
        for corner in range(8):
            var dx = corner // 4
            var dy = (corner // 2) % 2
            var dz = corner % 2
            var w = (
                (1.0 - fx + Float64(dx) * (2.0 * fx - 1.0))
                * (1.0 - fy + Float64(dy) * (2.0 * fy - 1.0))
                * (1.0 - fz + Float64(dz) * (2.0 * fz - 1.0))
            )
            total += (
                w
                * self.values[((x0 + dx) * SIDE + (y0 + dy)) * SIDE + (z0 + dz)]
            )
        return Float32((total - self.level) * self.scale)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var grid = SpacetimeGrid.uniform(
        1, SIDE, SIDE, SIDE, Duration64(1.0), Length64(STEP)
    )
    var center = grid.center()
    var bubble = AlcubierreMetric(
        fraction_of_light(0.5), Length64(2.0), InverseLength64(1.5), True
    )
    var metric = sample_metric(bubble, grid, center)
    var eulerian = to_eulerian(
        exact_stress_energy(bubble, grid, center), metric
    )
    var values = eulerian.tensor.component(0, 0)
    var least = 0.0
    for value in values:
        least = min(least, value)
    print("Least energy density:", least, "J/m^3")
    var field = DensityField(values^, least / 3.0, 1.0 / abs(least))
    var reach = Float32(STEP * Float64(SIDE - 1) / 2.0)
    var shell = mesh_surface(
        field,
        Vector3(-reach, -reach, -reach),
        Vector3(reach, reach, reach),
        24,
        "Alcubierre density",
        workers=0,
    )

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))
    var assets = Assets()
    var ring = assets.geometries.add(shell^)
    var red = assets.materials.add(Material(Color(214, 72, 64)))
    var rod = Triangles()
    rod.box(Vec3d(-4.0, 0.0, 0.0), Vec3d(4.0, 0.0, 0.0), 0.04, Vec3d(1, 1, 1))

    var scene = Scene()
    var pivot = scene.add(Object3D())
    scene.add_mesh(Mesh(ring, red, scene.attach(Object3D(), pivot)))
    rod.add_to(scene, assets, pivot)
    warm_lamp(scene, 4.0, 6.0, 8.0)
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(5.5, 4.0, 9.0),
        Vector3(0.0, 0.0, 0.0),
        field_of_view=Angle(34.0, DEGREE),
        far=Length(60.0, METER),
    )
    spin_gallery(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
