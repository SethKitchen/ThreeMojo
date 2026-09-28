# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A PlayStation-style scene pass: three.js r186's `RetroPassNode`, from
`examples/jsm/tsl/display/RetroPassNode.js`.

The pass draws the scene at `resolution_scale` of the frame's size, a
quarter by default, with each corner rounded to a whole pixel from the
screen's center: three.js's vertex snap, which makes the geometry wobble
as it moves. The small image is stored in eight bits and shown at the
frame's size with nearest filtering, as three.js's `UnsignedByteType`
target with `NearestFilter` shows it.

**Not ported.** three.js swaps each material for a `MeshPhongNodeMaterial`
unless it is a basic one, mixes a standard material's environment into its
color by its metalness, and can map textures without the perspective
divide, `affineDistortion`. This port draws each material as it is and
with the perspective divide.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.scene import Scene
from postprocessing.display_nodes import scaled_size
from render.framebuffer import FloatColor
from render.target import RenderTarget, UNSIGNED_BYTE_TARGET, stored
from renderers.renderer import Renderer
from std.math import isfinite


struct RetroSettings(ImplicitlyCopyable):
    """What a retro pass reads, with three.js's defaults."""

    # The share of the frame's size the scene is drawn at, three.js's
    # `setResolutionScale( .25 )`.
    var resolution_scale: Float32

    def __init__(out self):
        """Start with three.js's default."""
        self.resolution_scale = 0.25


def check_retro(settings: RetroSettings) raises:
    """Refuse settings no retro pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the resolution scale is not in (0, 1].
    """
    if not (
        isfinite(settings.resolution_scale)
        and settings.resolution_scale > 0
        and settings.resolution_scale <= 1
    ):
        raise Error("A retro pass's resolution scale must be in (0, 1]")


def byte_color(color: FloatColor) -> FloatColor:
    """Return a straight color as an eight-bit target holds it.

    Args:
        color: The color, straight.

    Returns:
        Each channel clamped to zero through one and rounded to a 255th.
    """
    return FloatColor(
        stored(color.r, UNSIGNED_BYTE_TARGET),
        stored(color.g, UNSIGNED_BYTE_TARGET),
        stored(color.b, UNSIGNED_BYTE_TARGET),
        stored(color.a, UNSIGNED_BYTE_TARGET),
    )


def retro_render[
    C: Camera
](
    mut frame: RenderTarget,
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: C,
    settings: RetroSettings,
) raises:
    """Draw one frame of three.js's `RetroPassNode` into `frame`.

    Args:
        frame: The composer's frame: its light and depth are replaced.
        renderer: What the scene is drawn with, at the frame's size.
        scene: The transform hierarchy, and the meshes and lights in it.
        assets: The geometry, materials and textures the meshes name.
        camera: The camera.
        settings: The resolution scale.

    Raises:
        Error: Everything `check_retro` and `Renderer.render_into` raise.
    """
    check_retro(settings)
    var w = frame.width
    var h = frame.height
    var small_w = scaled_size(w, settings.resolution_scale)
    var small_h = scaled_size(h, settings.resolution_scale)
    var small = renderer.resized(small_w, small_h)
    small.snap_vertices = True
    var drawn = RenderTarget(small_w, small_h, renderer.background)
    small.render_into(drawn, scene, assets, camera)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            # `NearestFilter`: the small pixel whose square holds the
            # frame pixel's center.
            var sx = min(((2 * x + 1) * small_w) // (2 * w), small_w - 1)
            var sy = min(((2 * y + 1) * small_h) // (2 * h), small_h - 1)
            var from_slot = sy * small_w + sx
            var slot = y * w + x
            frame.colors[slot] = byte_color(
                drawn.straight_at(from_slot)
            ).premultiplied()
            frame.data[slot] = False
            frame.depth[slot] = drawn.depth[from_slot]
    frame.depth_mode = drawn.depth_mode
