# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Drawing a `GaussianSplat` into a `RenderTarget` on the CPU.

Two steps, as for every other primitive. `prepare_gaussian_splat` runs on
the host: it sorts the splats back to front when the object's `auto_sort`
is on, evaluates their spherical harmonics for the camera, and projects
each one with `render.splatrule.project_splat`, in draw order.
`rasterize_splats` fills the projected splats in that order.
`render.gpu.GpuSplats` fills the same list on the device, one thread a
pixel, and the parity tests hold the two to the same image.

A splat blends with the normal mode, source over, with straight alpha, as
three.js's transparent splat material does. It tests depth against what
is drawn and writes none. The target keeps its depth mode, so a splat
drawn after `Renderer.render_into` is hidden by the opaque surfaces in
front of it.

Draw a scene with splats in three steps:

1. `Renderer.render_into` draws the meshes, lines and points into a
   `RenderTarget`.
2. `draw_gaussian_splat` draws each `GaussianSplat` into the same target.
3. `RenderTarget.resolve` turns the light into an image.

The splats cover the whole target. A renderer's viewport does not move
them.
"""

from cameras.camera import Camera
from core.scene import Scene
from math.vector3 import Vector3
from objects.gaussian_splat import GaussianSplat
from render.framebuffer import FloatColor
from render.raster_state import DepthMode, log_depth_factor
from render.splatrule import (
    FloatRgba,
    ProjectedSplat,
    SplatView,
    project_splat,
    splat_alpha,
    splat_depth_passes,
    splat_reach,
)
from render.target import RenderTarget
from std.math import ceil, floor, max, min
from units.si import Length, METER


def prepare_gaussian_splat[
    C: Camera
](
    scene: Scene,
    mut splat: GaussianSplat,
    camera: C,
    width: Int,
    height: Int,
    depth_mode: DepthMode,
) raises -> List[ProjectedSplat]:
    """Sort, color and project a splat object's splats, in draw order.

    Args:
        scene: The scene, updated, that holds the object's node.
        splat: The splats. Their order is sorted again when `auto_sort` is
            on and the view needs it.
        camera: The camera to project through.
        width: The target's width in pixels.
        height: The target's height in pixels.
        depth_mode: How the target stores depth.

    Returns:
        The splats on the screen, furthest first once sorted. A splat
        three.js moves off the screen is left out, and so is every splat
        when the node is hidden or on no layer the camera draws.

    Raises:
        Error: If the depth mode is not valid, the node is not in the
            scene, the scene is stale, or a matrix cannot be inverted.
    """
    if not depth_mode.is_valid():
        raise Error("A Gaussian splat needs a valid depth mode")
    var out = List[ProjectedSplat]()
    if not scene.shows(splat.node, camera.visible_layers()):
        return out^
    var world = scene.world_matrix(splat.node)
    var view = camera.view_matrix_in(scene)
    if splat.auto_sort:
        _ = splat.update_sort(
            world, view, Length(camera.near_distance(), METER)
        )
    var camera_world = view
    camera_world.invert()
    var local = world
    local.invert()
    var eye = local.transform_point(
        camera_world.transform_point(Vector3(0, 0, 0))
    )
    var shading = splat.spherical_harmonics_colors(eye)
    var shaded = len(shading) > 0
    var place = SplatView(
        view * world,
        camera.projection_matrix(),
        width,
        height,
        depth_mode,
        log_depth_factor(camera.far_distance()),
    )
    ref geometry = splat.splat_geometry
    for position in range(len(splat.order)):
        var index = splat.order[position]
        var color = FloatRgba(
            Float32(geometry.colors[index * 4]) / 255,
            Float32(geometry.colors[index * 4 + 1]) / 255,
            Float32(geometry.colors[index * 4 + 2]) / 255,
            Float32(geometry.colors[index * 4 + 3]) / 255,
        )
        if shaded:
            color.r += shading[index * 3]
            color.g += shading[index * 3 + 1]
            color.b += shading[index * 3 + 2]
        var projected = project_splat(
            Vector3(
                geometry.centers[index * 3],
                geometry.centers[index * 3 + 1],
                geometry.centers[index * 3 + 2],
            ),
            geometry.covariances,
            index * 6,
            color,
            place,
        )
        if Bool(projected):
            out.append(projected.value())
    return out^


def rasterize_splats(
    mut target: RenderTarget, splats: List[ProjectedSplat]
) raises:
    """Blend projected splats into a target, one after another.

    Args:
        target: The target. Its depth is tested and left as it is.
        splats: The splats, in the order to draw them.

    Raises:
        Error: If the target's depth mode is not valid.
    """
    if not target.depth_mode.is_valid():
        raise Error("A Gaussian splat needs a valid depth mode")
    for index in range(len(splats)):
        var splat = splats[index]
        var reach = splat_reach(splat)
        var left = max(Int(floor(splat.x - reach[0])) - 1, 0)
        var right = min(Int(ceil(splat.x + reach[0])) + 1, target.width - 1)
        var top = max(Int(floor(splat.y - reach[1])) - 1, 0)
        var bottom = min(Int(ceil(splat.y + reach[1])) + 1, target.height - 1)
        for y in range(top, bottom + 1):
            _blend_row(target, splat, y, left, right)


def _blend_row(
    mut target: RenderTarget,
    splat: ProjectedSplat,
    y: Int,
    left: Int,
    right: Int,
) raises:
    """Blend one splat into one row of pixels.

    Args:
        target: The target.
        splat: The splat.
        y: The row.
        left: The first column.
        right: The last column.

    Raises:
        Error: Never; the columns and the row are inside the target.
    """
    for x in range(left, right + 1):
        var stored = target.depth[y * target.width + x]
        if not splat_depth_passes(target.depth_mode, splat.depth, stored):
            continue
        target.blend(
            x,
            y,
            FloatColor(splat.r, splat.g, splat.b, splat_alpha(splat, x, y)),
        )


def draw_gaussian_splat[
    C: Camera
](
    mut target: RenderTarget, scene: Scene, mut splat: GaussianSplat, camera: C
) raises:
    """Draw a splat object into a target on the CPU: three.js's render of a
    `GaussianSplat`.

    Args:
        target: The target, drawn into already or cleared. Its depth hides
            the splats behind it.
        scene: The scene, updated, that holds the object's node.
        splat: The splats; see `prepare_gaussian_splat`.
        camera: The camera to project through.

    Raises:
        Error: Everything `prepare_gaussian_splat` raises.
    """
    var splats = prepare_gaussian_splat(
        scene, splat, camera, target.width, target.height, target.depth_mode
    )
    rasterize_splats(target, splats)
