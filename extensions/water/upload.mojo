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
from extensions.water.frame import CameraLook, WaterScene, _ComposePlan
from extensions.water.glare import (
    glare_convolve,
    glare_grid_size,
    glare_kernels,
)
from extensions.water.packed import (
    pack_caustics,
    pack_pebbles,
    pack_surface,
)
from extensions.water.pebbles import PebbleBed
from extensions.water.surface import SurfaceField
from std.memory import bitcast

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
        Error: If the kernels cannot be made, or the image is below one
            pixel either way.
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


comptime COMPOSE_WORDS = 256
"""How many 32-bit words `ComposeUpload.words` holds."""
comptime WORD_WIDTH = 24
"""The word that holds the frame's width."""
comptime WORD_HEIGHT = 25
"""The word that holds the frame's height."""
comptime WORD_RIPPLE_SIDE = 26
"""The word that holds the ripple texels on one side."""
comptime WORD_GRID_WIDTH = 27
"""The word that holds the width of the grid of shaded samples."""
comptime WORD_GRID_HEIGHT = 28
"""The word that holds the height of the grid of shaded samples."""
comptime WORD_STEP = 29
"""The word that holds the pixels between two shaded samples."""
comptime WORD_SURFACE_TABLE = 32
"""The first word of the surface level table."""
comptime WORD_CAUSTIC_TABLE = 96
"""The first word of the caustic level table."""
comptime WORD_PEBBLE_TABLE = 160
"""The first word of the pebble level table."""


def grid_samples(size: Int, step: Int) -> Int:
    """Return how many shaded samples lie along a side of a frame.

    The samples are the pixels whose index is a multiple of `step`, and the
    last pixel.

    Args:
        size: The frame's width or height, in pixels.
        step: The pixels between two samples.

    Returns:
        The samples along that side.
    """
    return (size - 1 + step - 1) // step + 1


def _words(
    mut words: List[UInt32], at: Int, room: Int, table: List[Int64]
) raises:
    """Write a level table at word `at`, two words an entry as a GPU's
    shader reads it, and refuse a table that is longer than `room` words."""
    if 2 * len(table) > room:
        raise Error("A level table is longer than the words kept for it")
    for k in range(len(table)):  # pragma: no branch
        words[at + 2 * k] = UInt32(table[k])


struct ComposeUpload(Movable):
    """What a GPU shades the village's water from, kept from frame to frame.

    The surface and the caustics are packed again only when the scene has
    found new ones, the ripples when they have changed, and the photograph
    once. The counters tell a host which of its copies are old. The frame's
    words are made again every frame.
    """

    var surface: List[Float32]
    """The surface texels, base grid first."""
    var ripple: List[Float32]
    """The ripple normal texture."""
    var caustic: List[Float32]
    """The caustic texels, base texture first."""
    var pebble: List[Float32]
    """The pebble photograph and its mips."""
    var words: List[UInt32]
    """The frame values, the sizes and the level tables, `COMPOSE_WORDS`
    words, as the water shader reads `frame_words`."""
    var surface_made: Int
    """How many times `surface` and `caustic` were packed."""
    var ripple_made: Int
    """How many times `ripple` was copied."""
    var bed_made: Int
    """How many times `pebble` was packed: one after the first frame."""
    var _surface_table: List[Int64]
    var _caustic_table: List[Int64]
    var _pebble_table: List[Int64]
    var _seen_kept: Int
    var _seen_ripples: Int

    def __init__(out self):
        """Make an upload that holds nothing yet."""
        self.surface = List[Float32]()
        self.ripple = List[Float32]()
        self.caustic = List[Float32]()
        self.pebble = List[Float32]()
        self.words = List[UInt32](length=COMPOSE_WORDS, fill=0)
        self.surface_made = 0
        self.ripple_made = 0
        self.bed_made = 0
        self._surface_table = List[Int64]()
        self._caustic_table = List[Int64]()
        self._pebble_table = List[Int64]()
        self._seen_kept = -1
        self._seen_ripples = -1

    def refresh(
        mut self,
        mut scene: WaterScene,
        plan: _ComposePlan,
        bed: PebbleBed,
        width: Int,
        height: Int,
    ) raises:
        """Make the arrays that a GPU composes one frame of water from.

        This does what `WaterScene.compose` does before it shades a pixel:
        it finds the surface and the caustics, or keeps the last ones. It
        counts as a call to `compose` for `refresh_every`.

        Args:
            scene: The water. Its `shade_step` must be from 2 to 64, and its
                `refresh_every` one or more.
            plan: The scene camera's view, from `_compose_plan`.
            bed: The pebble photograph. It is packed once, the first time.
            width: The frame's width, in pixels.
            height: The frame's height, in pixels.

        Raises:
            Error: If the shade step or the refresh is not valid, a level
                table is too long, or the surface cannot be made. The
                arrays of the last frame stay.
        """
        if scene.shade_step < 2 or scene.shade_step > 64:
            raise Error("The water on a GPU needs a shade step from 2 to 64")
        if scene.refresh_every < 1:
            raise Error("The water's refresh must come every frame or more")
        scene._refresh_kept()
        ref surface = scene._surface_kept.value()
        ref caustics = scene._caustics_kept.value()
        if scene._kept_made != self._seen_kept:
            var packed_surface = pack_surface(surface)
            var packed_caustics = pack_caustics(caustics)
            self.surface = packed_surface[0].copy()
            self._surface_table = packed_surface[1].copy()
            self.caustic = packed_caustics[0].copy()
            self._caustic_table = packed_caustics[1].copy()
            self._seen_kept = scene._kept_made
            self.surface_made += 1
        if scene._ripples_made != self._seen_ripples:
            self.ripple = scene._ripples.normal.copy()
            self._seen_ripples = scene._ripples_made
            self.ripple_made += 1
        if self.bed_made == 0:
            var packed_bed = pack_pebbles(bed)
            self.pebble = packed_bed[0].copy()
            self._pebble_table = packed_bed[1].copy()
            self.bed_made = 1
        var values = frame_values(scene, plan.look, surface, caustics)
        var words = List[UInt32](length=COMPOSE_WORDS, fill=0)
        for k in range(len(values)):  # pragma: no branch
            words[k] = bitcast[DType.uint32](values[k])
        words[WORD_WIDTH] = UInt32(width)
        words[WORD_HEIGHT] = UInt32(height)
        words[WORD_RIPPLE_SIDE] = UInt32(scene._ripples.n)
        words[WORD_GRID_WIDTH] = UInt32(grid_samples(width, scene.shade_step))
        words[WORD_GRID_HEIGHT] = UInt32(grid_samples(height, scene.shade_step))
        words[WORD_STEP] = UInt32(scene.shade_step)
        _words(words, WORD_SURFACE_TABLE, 64, self._surface_table)
        _words(words, WORD_CAUSTIC_TABLE, 64, self._caustic_table)
        _words(words, WORD_PEBBLE_TABLE, 96, self._pebble_table)
        self.words = words^
