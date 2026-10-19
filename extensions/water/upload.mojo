# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a GPU draws one water frame from.

The shader reads the surface, the ripple window and the caustics as flat
arrays, and a few frame values. `GpuWater` copies them into device memory. A
browser's GPU cannot be reached from Mojo, so a `FrameUpload` keeps them in the
module's memory, where the page reads them and writes them to its own device.
Both use `frame_values`, so the two shaders get the same numbers. The glare is
one small FFT, which stays on the CPU in both: `glare_grid` sizes its grid and
`convolve_glare` runs it.

This module imports no GPU library, so it builds for WebAssembly.
"""

from extensions.water.caustics import CausticField
from extensions.water.frame import CameraLook, WaterScene
from extensions.water.glare import (
    glare_convolve,
    glare_grid_size,
    glare_kernels,
)
from extensions.water.packed import pack_caustics, pack_surface
from extensions.water.surface import SurfaceField

comptime FRAME_FLOATS = 23
"""How many floats `frame_values` returns."""


def frame_values(
    scene: WaterScene,
    look: CameraLook,
    surface: SurfaceField,
    caustics: CausticField,
) -> List[Float32]:
    """Return the values that one frame's shader reads from one small array.

    They are the camera's forward, right and up axes and its position, the sun
    direction, then the clock, the ocean patch, the ripple window and the
    caustic placement.

    Args:
        scene: The water at its current clock.
        look: The camera basis and position.
        surface: The resolved surface of this clock.
        caustics: The caustic texture of this surface.

    Returns:
        `FRAME_FLOATS` floats, in the order above.
    """
    return [
        look.fx,
        look.fy,
        look.fz,
        look.rx,
        look.ry,
        look.rz,
        look.ux,
        look.uy,
        look.uz,
        look.px,
        look.py,
        look.pz,
        scene.sun.x,
        scene.sun.y,
        scene.sun.z,
        scene.clock.value,
        surface.surface_patch(),
        scene._ripples.size,
        scene._ripples.center_x,
        scene._ripples.center_z,
        caustics.patch,
        caustics.shift_x,
        caustics.shift_z,
    ]


struct FrameUpload(Movable):
    """The arrays that change every frame, as a shader reads them."""

    var surface: List[Float32]
    """The surface texels, base grid first."""
    var surface_table: List[Int64]
    """The surface level table."""
    var ripple: List[Float32]
    """The ripple normal texture."""
    var ripple_side: Int
    """Ripple texels on one side."""
    var caustic: List[Float32]
    """The caustic texels, base texture first."""
    var caustic_table: List[Int64]
    """The caustic level table."""
    var values: List[Float32]
    """The frame values, as `frame_values` returns them."""

    def __init__(out self, scene: WaterScene, look: CameraLook) raises:
        """Resolve the surface and the caustics of a scene, and pack them.

        Args:
            scene: The water at its current clock.
            look: The camera basis and position.

        Raises:
            Error: If the surface or the caustics cannot be made.
        """
        var surface = scene._surface()
        var caustics = scene._caustics(surface)
        var packed_surface = pack_surface(surface)
        var packed_caustics = pack_caustics(caustics)
        self.values = frame_values(scene, look, surface, caustics)
        self.surface = packed_surface[0].copy()
        self.surface_table = packed_surface[1].copy()
        self.ripple = scene._ripples.normal.copy()
        self.ripple_side = scene._ripples.n
        self.caustic = packed_caustics[0].copy()
        self.caustic_table = packed_caustics[1].copy()


def glare_grid(
    mut scene: WaterScene, width: Int, height: Int
) raises -> Tuple[Int, Int]:
    """Return the size of the glare grid of a frame, making the kernels first.

    The scene keeps the kernels, so only the first call builds them.

    Args:
        scene: The water. It keeps the glare kernels.
        width: Image width. It must be positive.
        height: Image height. It must be positive.

    Returns:
        The width and the height of the glare grid.

    Raises:
        Error: If the kernels cannot be made.
    """
    if not scene._glare:
        scene._glare = glare_kernels(scene.glare_resolution)
    return glare_grid_size(scene._glare.value().red_green.n, width, height)


def convolve_glare(
    scene: WaterScene, samples: List[Float32], sw: Int, sh: Int
) raises -> List[Float32]:
    """Spread the glints of a frame into its glare.

    Args:
        scene: The water, after `glare_grid` made its kernels.
        samples: The glints at the grid's points, three floats a point,
            row-major.
        sw: The grid's width, from `glare_grid`.
        sh: The grid's height, from `glare_grid`.

    Returns:
        The glare at the grid's points, three floats a point.

    Raises:
        Error: If the scene has no kernels, or the samples do not fit the grid.
    """
    if not scene._glare:
        raise Error("The glare kernels are not made")
    return glare_convolve(samples, sw, sh, scene._glare.value())
