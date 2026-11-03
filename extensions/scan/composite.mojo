# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scan drawn into a picture that a mesh scene has drawn.

A scanned building is a million Gaussian splats, and a scene of meshes is
triangles. They meet in the picture. The mesh scene is drawn first, with its
sky, and it leaves a picture and a depth for each pixel. A `SplatLayer` then
blends the splats of the scan into that picture. A splat is hidden where a
surface of the mesh scene is nearer, so a hill, a wall or a tree stands in
front of the scan, and the scan stands in front of what lies behind it. A
splat writes no depth, as every transparent surface does not.

A layer stands a scan in the scene of the mesh view: y up, x east and z south,
in meters. `splat_layer` puts the middle of the scan's box at a place of the
plan, its floor at a height, and turns it about the vertical.

The splats blend in the values of the picture, as every viewer of splats
does. The picture is already tone mapped, so the scan keeps the colors that
its capture gave it.
"""

from cameras.camera import Camera
from core.gaussian_splat_utils import GaussianSplatGeometry
from core.object3d import Object3D
from core.scene import Scene
from extensions.scan.frame import ScanFrame
from extensions.scan.occupancy import default_occupancy_options, trimmed_region
from extensions.scan.place import scan_placement
from render.framebuffer import Color, FloatColor, Framebuffer
from render.splat_lod import (
    LOD_PIXELS,
    SplatLod,
    build_splat_lod,
    prepare_splat_lod,
)
from render.splat_raster import rasterize_splats
from render.working_space import resolve_srgb_working, srgb_working_target
from units.si import Angle, RADIAN


struct SplatLayer(Movable):
    """A scan standing in a scene, ready to draw into a picture."""

    var scene: Scene
    """The scene that holds the scan's node."""
    var lod: SplatLod
    """The level-of-detail tree over the scan's splats."""
    var width: Float64
    """The size of the scan's box along its x, in meters."""
    var depth: Float64
    """The size of the scan's box along its y, in meters."""
    var height: Float64
    """The size of the scan's box up, in meters."""

    def __init__(
        out self,
        var scene: Scene,
        var lod: SplatLod,
        width: Float64,
        depth: Float64,
        height: Float64,
    ):
        self.scene = scene^
        self.lod = lod^
        self.width = width
        self.depth = depth
        self.height = height


def splat_layer(
    geometry: GaussianSplatGeometry,
    frame: ScanFrame,
    east: Float64,
    north: Float64,
    ground: Float64,
    heading: Float64,
) raises -> SplatLayer:
    """Stand a scan in a scene.

    Args:
        geometry: The splats, cleaned.
        frame: The scan's frame, which says its up, its north and its unit.
        east: The east coordinate of the middle of the scan's box, in meters
            in the plan.
        north: The north coordinate of the same.
        ground: The height at which the floor of the scan stands, in meters.
        heading: The turn about the vertical, in radians, counterclockwise
            seen from above.

    Returns:
        The layer.

    Raises:
        Error: If the frame is not valid, or the scan has no splat.
    """
    var region = trimmed_region(geometry, frame, default_occupancy_options())
    var mid_x = (region.low.x + region.high.x) / 2.0
    var mid_y = (region.low.y + region.high.y) / 2.0
    var scene = Scene()
    # The scan's own node stands it upright in meters. Above it, a node moves
    # the middle of its box to the origin and the floor to zero, and above
    # that a node turns it and sets it down at its place. The plan's y is
    # the scene's -z.
    var turning = Object3D()
    turning.set_position(Float32(east), Float32(ground), Float32(-north))
    turning.set_euler(
        Angle(0.0, RADIAN), Angle(Float32(heading), RADIAN), Angle(0.0, RADIAN)
    )
    var turning_node = scene.add(turning^)
    var centering = Object3D()
    centering.set_position(
        Float32(-mid_x), Float32(-region.low.z), Float32(mid_y)
    )
    var centering_node = scene.attach(centering^, turning_node)
    var standing = Object3D()
    scan_placement(frame).apply(standing)
    var node = scene.attach(standing^, centering_node)
    scene.update()
    var lod = build_splat_lod(geometry, node)
    return SplatLayer(
        scene^,
        lod^,
        region.high.x - region.low.x,
        region.high.y - region.low.y,
        region.high.z - region.low.z,
    )


def composite_splats[
    C: Camera
](
    mut image: Framebuffer,
    mut layer: SplatLayer,
    camera: C,
    workers: Int = 1,
    pixels: Float32 = LOD_PIXELS,
) raises -> Int:
    """Blend a scan into a picture, hidden where a surface is nearer.

    Args:
        image: The picture and its depth, from `Renderer.render`. Its colors
            are changed. Its depth is left as it is.
        layer: The scan.
        camera: The centered perspective camera that drew the picture.
        workers: How many threads select, project and fill.
        pixels: The level-of-detail limit of `render.splat_lod`.

    Returns:
        How many splats were drawn.

    Raises:
        Error: If the camera's view raises.
    """
    var width = image.width
    var height = image.height
    var target = srgb_working_target(width, height, Color(0, 0, 0))
    for at in range(width * height):  # pragma: no branch
        var base = at * 4
        target.colors[at] = FloatColor(
            of=Color(
                image.pixels[base],
                image.pixels[base + 1],
                image.pixels[base + 2],
            )
        ).premultiplied()
        target.depth[at] = image.depth[at]
    layer.scene.update()
    var selected = prepare_splat_lod(
        layer.scene,
        layer.lod,
        camera,
        width,
        height,
        target.depth_mode,
        None,
        workers,
        pixels,
    )
    rasterize_splats(target, selected, workers)
    var resolved = resolve_srgb_working(target)
    for at in range(width * height):  # pragma: no branch
        var base = at * 4
        image.pixels[base] = resolved.pixels[base]
        image.pixels[base + 1] = resolved.pixels[base + 1]
        image.pixels[base + 2] = resolved.pixels[base + 2]
    return len(selected)
