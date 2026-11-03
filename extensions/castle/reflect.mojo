# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The castle in the water: a mirror image, weighted by Fresnel's law.

Clearwater shades the surface of the moat and reflects the sky in it. It does
not reflect what stands on the bank. This module does, in two steps.

1. The scene is drawn again through a camera that is mirrored in the plane of
   the water, with everything below the plane cut away. A point on the water
   has the same pixel in this picture as in the real one, so the picture is
   read at the pixel that is being shaded.
2. At each pixel where the water was drawn, a share of the mirror image is
   added. The share is the reflectance of a clean water surface, Schlick's
   form of Fresnel's equations with an index of 1.333, at the angle that the
   view ray makes with the surface.

The mirror image is drawn without the sky, on a clear ground, because
Clearwater already reflects the sky and the share must not be counted twice.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from math.bounds import Plane
from math.matrix4 import Matrix4, rotation_x, translation
from objects.reflector import (
    camera_world,
    follow_camera,
    mirror_view,
    view_renderer,
)
from render.framebuffer import Color, Framebuffer
from render.srgb import SRGB
from renderers.renderer import Renderer
from std.math import abs, pow, sqrt
from units.si import Angle, DEGREE

# The reflectance of water at normal incidence: ((n - 1) / (n + 1))^2 for an
# index of 1.333.
comptime WATER_REFLECTANCE = 0.02


def fresnel(cosine: Float64) -> Float64:
    """Return the share of light that clean water reflects, by Schlick's
    form of Fresnel's equations.

    Args:
        cosine: The cosine of the angle between the view ray and the normal
            of the surface, from 0 to 1.

    Returns:
        The reflectance, from 0.02 at normal incidence up to 1 at grazing
        incidence.
    """
    var c = min(max(cosine, 0.0), 1.0)
    return WATER_REFLECTANCE + (1.0 - WATER_REFLECTANCE) * pow(1.0 - c, 5.0)


def _linear(byte: UInt8) -> Float64:
    """Return the linear value of an sRGB byte."""
    var c = Float64(byte) / 255.0
    if c <= 0.04045:
        return c / 12.92
    return pow((c + 0.055) / 1.055, 2.4)


def _encode(value: Float64) -> UInt8:
    """Return the sRGB byte of a linear value."""
    var c = min(max(value, 0.0), 1.0)
    var e = c * 12.92
    if c > 0.0031308:
        e = 1.055 * pow(c, 1.0 / 2.4) - 0.055
    return UInt8(Int(e * 255.0 + 0.5))


def _show(mut scene: Scene, node: NodeId, visible: Bool) raises:
    """Set a node's visibility and update the scene."""
    var held = scene.get(node)
    held.visible = visible
    scene.set(node, held^)
    scene.update()


def reflect_in_water[
    C: Camera
](
    renderer: Renderer,
    mut scene: Scene,
    assets: Assets,
    camera: C,
    sky: NodeId,
    mut image: Framebuffer,
    before: List[UInt8],
    level: Float32,
    murk: Float64 = 0.0,
    murk_red: Float64 = 0.02,
    murk_green: Float64 = 0.05,
    murk_blue: Float64 = 0.035,
    gain: Float64 = 1.0,
) raises -> Int:
    """Add the mirror image of a scene to the pixels where water was drawn.

    Args:
        renderer: The renderer that drew the image.
        scene: The scene, updated. It is drawn again without its sky.
        assets: The stores the scene names.
        camera: The camera that drew the image.
        sky: The node of the sky dome, which Clearwater reflects itself.
        image: The picture with the water in it. It is changed.
        before: The bytes of the picture before the water was drawn. A pixel
            that differs is a water pixel.
        level: The height of the water, in the frame of the scene.
        murk: How much of the light from the bed the silt of the moat
            hides, from 0 for the clear water that Clearwater models to 1
            for water that is opaque. The light is replaced by the color
            of the silt.
        murk_red: The linear red of the silt.
        murk_green: The linear green of the silt.
        murk_blue: The linear blue of the silt.
        gain: A factor on the share, one for clean water.

    Returns:
        How many pixels took a share of the mirror image.

    Raises:
        Error: If the camera's view raises, or the render does.
    """
    var width = image.width
    var height = image.height
    var surface = rotation_x(Angle(-90.0, DEGREE))
    surface.premultiply(translation(0, level, 0))
    var mirror = mirror_view(surface, camera_world(camera, scene))
    if mirror.facing_away:
        return 0
    var seen_by = follow_camera(camera, mirror.view)
    var view = view_renderer(renderer, width, height)
    view.set_antialias(True)
    view.set_background(Color(0, 0, 0, 0))
    view.clipping_planes.append(
        Plane(mirror.normal, -mirror.normal.dot(mirror.point))
    )
    var was = scene.get(sky).visible
    _show(scene, sky, False)
    var seen = Framebuffer(width, height, Color(0, 0, 0, 0))
    try:
        seen = view.render(scene, assets, seen_by)
    finally:
        _show(scene, sky, was)
    # The ray through each pixel, from the view and the projection.
    var world = camera_world(camera, scene)
    var projection = camera.projection_matrix()
    var tan_x = 1.0 / Float64(projection.get(0, 0))
    var tan_y = 1.0 / Float64(projection.get(1, 1))
    var right_x = Float64(world.get(0, 0))
    var right_y = Float64(world.get(1, 0))
    var right_z = Float64(world.get(2, 0))
    var up_x = Float64(world.get(0, 1))
    var up_y = Float64(world.get(1, 1))
    var up_z = Float64(world.get(2, 1))
    var back_x = Float64(world.get(0, 2))
    var back_y = Float64(world.get(1, 2))
    var back_z = Float64(world.get(2, 2))
    var shared = 0
    for row in range(height):  # pragma: no branch
        var ndc_y = 1.0 - (Float64(row) + 0.5) / Float64(height) * 2.0
        for column in range(width):  # pragma: no branch
            var at = (row * width + column) * 4
            if (
                image.pixels[at] == before[at]
                and image.pixels[at + 1] == before[at + 1]
                and image.pixels[at + 2] == before[at + 2]
            ):
                continue
            var alpha = Float64(seen.pixels[at + 3]) / 255.0
            var ndc_x = (Float64(column) + 0.5) / Float64(width) * 2.0 - 1.0
            var dx = right_x * ndc_x * tan_x + up_x * ndc_y * tan_y - back_x
            var dy = right_y * ndc_x * tan_x + up_y * ndc_y * tan_y - back_y
            var dz = right_z * ndc_x * tan_x + up_z * ndc_y * tan_y - back_z
            var length = sqrt(dx * dx + dy * dy + dz * dz)
            var reflectance = fresnel(abs(dy) / length)
            var share = min(reflectance * gain, 1.0) * alpha
            for channel in range(3):
                var water = _linear(image.pixels[at + channel])
                # The silt hides the bed, but not the light that the surface
                # reflects, which Clearwater has added to the water.
                var silt = murk_red
                if channel == 1:
                    silt = murk_green
                elif channel == 2:
                    silt = murk_blue
                water = water * (1.0 - murk) + silt * murk
                var mirrored = 0.0
                if alpha > 0.0:
                    mirrored = _linear(seen.pixels[at + channel]) / alpha
                image.pixels[at + channel] = _encode(
                    water * (1.0 - share) + mirrored * share
                )
            if alpha > 0.0:
                shared += 1
    return shared
