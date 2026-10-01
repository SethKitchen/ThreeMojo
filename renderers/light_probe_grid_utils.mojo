# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Baking a box of light probes, from three.js
`examples/jsm/lighting/LightProbeGrid.js`'s `bake` and
`examples/jsm/lighting/LightProbeGridUtils.js`.

`bake_light_probe_grid` is three.js's `LightProbeGrid.bake( renderer,
scene, options )`. For each probe it draws the scene into a cube at the
probe, three.js's `CubeCamera`, and projects the cube onto the nine
spherical harmonic terms with `project_sh`: `sample_count` directions on
an equal-area Fibonacci sphere, each sample times the basis, times
`4 pi / sample_count`.

**Bounces.** With `bounces` above zero, the bake runs again that many
times. Each pass draws the scene lit by a copy of the grid as the pass
before left it, so light bounces once more each pass. The first pass
draws the scene without the grid.

**Suns.** A sun's shadow is fit to one view camera, and a cube has six.
So the bake does as three.js's `replaceSunLights` does. Each sun that
casts is drawn as one directional light, whose shadow camera is fit to
the sphere around every mesh that casts: `replace_sun_lights`. The sun
comes back after the bake, `restore_sun_lights`.

It is here, beside the renderer, and not in `lights/`, because it draws.
"""

from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from lights.light import DIRECTIONAL, Light
from lights.light_probe_grid import LightProbeGrid
from lights.shadow import SUN_BLEND, ShadowCascade
from math.bounds import Box3
from math.spherical_harmonics3 import SH_COUNT, SphericalHarmonics3, sh_basis
from math.vector3 import Vector3
from render.cube_texture import CubeTexture
from renderers.environment import scene_cube
from renderers.renderer import Renderer
from std.math import cos, max, pi, sin, sqrt
from units.si import Length, METER

# three.js's `bake` options: an 8-texel cube, planes at a tenth of a meter
# and a hundred, and 512 directions a probe.
comptime DEFAULT_CUBEMAP_SIZE = 8
comptime DEFAULT_PROBE_NEAR = Length(0.1, METER)
comptime DEFAULT_PROBE_FAR = Length(100.0, METER)
comptime DEFAULT_SAMPLE_COUNT = 512
# What `count` means when it is left out: every probe from `start` on.
comptime ALL_PROBES = -1
# three.js's `GOLDEN_ANGLE`, the turn between two Fibonacci directions.
comptime GOLDEN_ANGLE = Float32(pi * (3.0 - 2.2360679774997896))


def fibonacci_direction(index: Int, sample_count: Int) -> Vector3:
    """Return direction `index` of an equal-area Fibonacci sphere of
    `sample_count`, three.js's `projectSHNode`.

    Args:
        index: Which direction, from zero.
        sample_count: How many directions the sphere holds.

    Returns:
        The unit direction.
    """
    var step = Float32(index)
    var z = 1 - (step * 2 + 1) / Float32(sample_count)
    var r = sqrt(max(1 - z * z, Float32(0)))
    var phi = step * GOLDEN_ANGLE
    return Vector3(r * cos(phi), z, r * sin(phi))


def project_sh(
    cube: CubeTexture, sample_count: Int
) raises -> SphericalHarmonics3:
    """Return the nine terms of a cube's light, three.js's `projectSHNode`:
    each of `sample_count` Fibonacci directions read from the cube at its
    full size, times `sh_basis`, summed, and scaled by `4 pi /
    sample_count`.

    Args:
        cube: The cube drawn at the probe.
        sample_count: How many directions to read.

    Returns:
        The coefficients, linear.

    Raises:
        Error: If the sample count is below one, or the cube is refused by
            `CubeTexture.validate`.
    """
    if sample_count < 1:
        raise Error("A probe bake reads one direction or more")
    cube.validate()
    var sh = SphericalHarmonics3()
    for sample in range(sample_count):  # pragma: no branch
        var direction = fibonacci_direction(sample, sample_count)
        var radiance = cube.sample(direction)
        for index in range(SH_COUNT):  # pragma: no branch
            var basis = sh_basis(index, direction)
            var at = index * 3
            sh.lanes[at] += radiance.r * basis
            sh.lanes[at + 1] += radiance.g * basis
            sh.lanes[at + 2] += radiance.b * basis
    sh.scale(Float32(4.0 * pi) / Float32(sample_count))
    return sh


struct SunReplacement(Movable):
    """What `replace_sun_lights` changed, for `restore_sun_lights`."""

    # The lights as they were.
    var lights: List[Light]
    # The nodes that were moved, and where each stood.
    var nodes: List[NodeId]
    var positions: List[Vector3]

    def __init__(out self, var lights: List[Light]):
        """Remember the lights as they are.

        Args:
            lights: A copy of the scene's lights.
        """
        self.lights = lights^
        self.nodes = List[NodeId]()
        self.positions = List[Vector3]()


def caster_sphere(
    scene: Scene, assets: Assets
) raises -> Tuple[Vector3, Float32]:
    """Return the middle and the radius of the sphere around every mesh
    that casts, three.js's `_casterSphere`, the radius at least one.

    Args:
        scene: The scene, updated.
        assets: The geometry the meshes name.

    Returns:
        The middle, and the radius.

    Raises:
        Error: If a mesh names a geometry or a node that is not there.
    """
    var box = Box3.empty()
    for index in range(len(scene.meshes)):
        ref mesh = scene.meshes[index]
        if not mesh.cast_shadow:
            continue
        var bounds = assets.geometries.get(mesh.geometry).bounding_box()
        bounds.apply_matrix4(scene.world_matrix(mesh.node))
        box.union(bounds)
    var sphere = box.bounding_sphere()
    var center = sphere.center
    if box.is_empty():
        center = Vector3(0, 0, 0)
    return (center, max(sphere.radius, Float32(1)))


def replace_sun_lights(
    mut scene: Scene, assets: Assets
) raises -> SunReplacement:
    """Draw each sun that casts as one directional light fit to the
    casters, three.js's `replaceSunLights`.

    A sun is two directional lights of `SUN_BLEND`. The last becomes a
    plain directional light: no cascade, its shadow camera a square the
    casters' radius to each side, from half the radius to three and a
    half, standing two radii from their middle, back toward the sun. The
    others light nothing until `restore_sun_lights`. All replacement
    values and node references are checked before the first scene write.

    Args:
        scene: The scene, updated.
        assets: The geometry the meshes name.

    Returns:
        What changed.

    Raises:
        Error: If a mesh or a light names a node that is not there.
    """
    var saved = SunReplacement(scene.lights.copy())
    var sphere = caster_sphere(scene, assets)
    var center = sphere[0]
    var radius = sphere[1]
    var changed_slots = List[Int]()
    var changed_lights = List[Light]()
    var moved_positions = List[Vector3]()
    for index in range(len(scene.lights)):
        var light = scene.lights[index]
        if (
            light.kind != DIRECTIONAL
            or light.cascade.blend != SUN_BLEND
            or not light.cascade.is_cascade()
            or not light.cast_shadow
        ):
            continue
        if not light.cascade.last:
            light.intensity = 0
        else:
            var toward = scene.world_position(
                light.node
            ) - scene.world_position(light.target)
            toward.normalize()
            saved.nodes.append(light.node)
            saved.positions.append(scene.get(light.node).position)
            saved.nodes.append(light.target)
            saved.positions.append(scene.get(light.target).position)
            light.cascade = ShadowCascade.none()
            light.shadow.set_extent(Length(radius, METER))
            light.shadow.near = Length(radius * 0.5, METER)
            light.shadow.far = Length(radius * 3.5, METER)
            moved_positions.append(center + toward * (radius * 2))
            moved_positions.append(center)
        light.validate()
        changed_slots.append(index)
        changed_lights.append(light)
    # Resolve every world transform before any node edit makes the scene
    # stale, and reject invalid references before changing the first sun.
    for index in range(len(changed_slots)):
        scene.lights[changed_slots[index]] = changed_lights[index]
    for index in range(len(saved.nodes)):
        var at = moved_positions[index]
        scene.node(saved.nodes[index]).set_position(at.x, at.y, at.z)
    scene.update()
    return saved^


def restore_sun_lights(mut scene: Scene, saved: SunReplacement) raises:
    """Put back what `replace_sun_lights` changed, three.js's
    `restoreSunLights`.

    Args:
        scene: The scene.
        saved: What `replace_sun_lights` returned.

    Raises:
        Error: If a node that was moved is gone.
    """
    scene.lights = saved.lights.copy()
    for index in range(len(saved.nodes)):
        var at = saved.positions[index]
        scene.node(saved.nodes[index]).set_position(at.x, at.y, at.z)
    scene.update()


def bake_light_probe_grid(
    mut grid: LightProbeGrid,
    renderer: Renderer,
    mut scene: Scene,
    assets: Assets,
    cubemap_size: Int = DEFAULT_CUBEMAP_SIZE,
    near: Length = DEFAULT_PROBE_NEAR,
    far: Length = DEFAULT_PROBE_FAR,
    bounces: Int = 0,
    sample_count: Int = DEFAULT_SAMPLE_COUNT,
    start: Int = 0,
    count: Int = ALL_PROBES,
) raises:
    """Measure the light at the probes of a grid, three.js's
    `LightProbeGrid.bake`.

    Args:
        grid: The grid. The probes from `start` on are replaced.
        renderer: What to take the drawing settings from. Its own grid is
            not used.
        scene: The scene to measure, updated. Its suns are replaced for
            the bake and put back after it.
        assets: The geometry, materials and textures it names.
        cubemap_size: How many texels a side each probe's cube is.
        near: Each cube's near plane.
        far: Each cube's far plane.
        bounces: How many more passes to draw, each lit by the grid the
            pass before left.
        sample_count: How many directions `project_sh` reads a cube in.
        start: The first probe to bake.
        count: How many probes to bake, or `ALL_PROBES` for every probe
            from `start` on.

    Raises:
        Error: If the grid is refused by `LightProbeGrid.validate`; the
            range is outside the grid; `bounces` is negative, or above
            zero for a range that is not the whole grid; the sample count
            is below one; or `scene_cube` refuses a probe's cube.
    """
    grid.validate()
    var total = grid.count()
    var amount = count
    if amount == ALL_PROBES:
        amount = total - start
    var end = start + amount
    if start < 0 or amount < 0 or end > total:
        raise Error("A light probe grid bake names probes the grid lacks")
    if bounces < 0:
        raise Error("A light probe grid bake's bounces cannot be negative")
    if bounces > 0 and amount != total:
        raise Error(
            "A light probe grid bakes every probe when the light bounces"
        )
    if sample_count < 1:
        raise Error("A probe bake reads one direction or more")
    if amount == 0:
        return
    var saved = replace_sun_lights(scene, assets)
    try:
        for bounce in range(bounces + 1):  # pragma: no branch
            var lit = LightProbeGrid.none()
            if bounce > 0:
                lit = LightProbeGrid(copy=grid)
            for index in range(start, end):  # pragma: no branch
                var cube = scene_cube(
                    renderer,
                    scene,
                    assets,
                    near,
                    far,
                    cubemap_size,
                    grid.position_of(index),
                    lit,
                )
                grid.probes[index] = project_sh(cube, sample_count)
    finally:
        restore_sun_lights(scene, saved)
