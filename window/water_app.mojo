# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The water app that the C ABI's water libraries share.

`window.capi_water` draws it on the CPU, and `window.capi_water_gpu` shades it
on a GPU. Each exports the same C names, so a program must never import both.
They take their state and their rules from here, which exports nothing: how
events move the camera, how time becomes ripple steps, and where the pebble
photograph comes from.

The ripple equation moves one step at a time, so its speed depends on how
many steps run. `WaterApp.advance` therefore gathers the time that hosts give
it and runs a step for each 1/30 s, which makes the ripples move at one speed
on a host that draws at 60 or at 120 frames a second.
"""

from extensions.water.frame import WaterScene, camera_look
from extensions.water.packed import pack_pebbles
from extensions.water.pebbles import PebbleBed, pebble_bed
from extensions.water.resolution import SpectrumResolution
from extensions.water.upload import FrameUpload, convolve_glare, glare_grid
from extensions.water.view import FRAME
from render.framebuffer import Color, Framebuffer
from render.jpeg import decode
from std.pathlib import Path
from units.si import RADIAN, SECOND, Angle, Duration
from window.capi_abi import (
    GPU_CAUSTIC,
    GPU_CAUSTIC_TABLE,
    GPU_GRID,
    GPU_INFO_GRID_HEIGHT,
    GPU_INFO_GRID_WIDTH,
    GPU_INFO_RIPPLE_SIDE,
    GPU_PEBBLE,
    GPU_PEBBLE_TABLE,
    GPU_RIPPLE,
    GPU_SAMPLES,
    GPU_SURFACE,
    GPU_SURFACE_TABLE,
    GPU_VALUES,
    GpuInfo,
    GpuPart,
    KEY_DOWN,
    KEY_SPACE,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
)

comptime BED = "assets/pebbles.jpg"
"""The pebble photograph, relative to the folder the program runs in."""
comptime STEP_MICROSECONDS = 33333
"""The time of one ripple step: 1/30 s, as the page's animation runs."""
comptime LONGEST_MICROSECONDS = 100000
"""The most time that one `advance` counts. A host that was stopped for a
while does not make the ripples run a thousand steps at once."""
comptime START_PITCH = Float32(-0.72)
"""The camera's pitch, in radians, where the page starts."""
comptime LOWEST_PITCH = Float32(-1.2)
"""The camera's lowest pitch, in radians: looking steeply down."""
comptime HIGHEST_PITCH = Float32(-0.05)
"""The camera's highest pitch, in radians: nearly level."""
comptime RADIANS_PER_PIXEL = Float32(0.004)
"""How far a drag of one pixel tilts the camera."""


def _plain_bed() raises -> PebbleBed:
    """Return a bed of one sand-colored texel, for an app with no photograph.

    Returns:
        The bed.

    Raises:
        Error: Never in practice. The texel is one valid linear color.
    """
    return PebbleBed(1, 1, [Float32(0.34), Float32(0.27), Float32(0.17)])


def _bed(path: String) raises -> PebbleBed:
    """Read the pebble photograph, or return plain sand if it cannot be read.

    Args:
        path: The JPEG file.

    Returns:
        The photograph's bed, or the plain bed.

    Raises:
        Error: Never in practice. See `_plain_bed`.
    """
    try:
        return pebble_bed(decode(Path(path).read_bytes()))
    except:
        return _plain_bed()


def _floats(values: List[Float32]) -> Tuple[Int, Int]:
    """Return the address and the size in words of a list of floats.

    Args:
        values: The list.

    Returns:
        The address of the first float and the count, or 0 and 0 for an empty
        list, which has no address worth giving.
    """
    if len(values) == 0:
        return (0, 0)
    return (Int(values.unsafe_ptr()), len(values))


def _table(entries: List[Int64]) -> Tuple[Int, Int]:
    """Return the address and the size in words of a table of 64-bit integers.

    Args:
        entries: The table.

    Returns:
        The address of the first entry and two words an entry, or 0 and 0 for
        an empty table.
    """
    if len(entries) == 0:
        return (0, 0)
    return (Int(entries.unsafe_ptr()), 2 * len(entries))


struct WaterApp(Movable):
    """The state that a host's handle points at."""

    var width: Int
    """The frame's width, in pixels."""
    var height: Int
    """The frame's height, in pixels."""
    var water: WaterScene
    """The water: its spectrum, its ripples and its clock."""
    var bed: PebbleBed
    """The pebble photograph under the water."""
    var pitch: Float32
    """The camera's pitch, in radians."""
    var owed: Int
    """Microseconds that `advance` has been given and has not yet run."""
    var tap: Bool
    """Whether the next ripple step taps the middle of the water."""
    var dragging: Bool
    """Whether a button is down."""
    var last_y: Int
    """The row of the pointer at the last press or drag."""
    var paused: Bool
    """Whether `advance` ignores time."""
    var frame: Framebuffer
    """The last frame drawn."""
    var upload: Optional[FrameUpload]
    """The arrays of the last frame that `prepare` made, or none."""
    var pebble: List[Float32]
    """The photograph's texels, packed for a GPU by the first `prepare`."""
    var pebble_table: List[Int64]
    """The packed photograph's level table."""
    var bed_generation: Int
    """How many times `prepare` has packed a photograph."""
    var bed_packed: Bool
    """Whether `pebble` holds the current photograph."""
    var samples: List[Float32]
    """The glints that a host's GPU cut at the glare grid's points."""
    var grid: List[Float32]
    """The glare at the grid's points, after `glare`."""
    var grid_width: Int
    """The glare grid's width, from the last `prepare`."""
    var grid_height: Int
    """The glare grid's height, from the last `prepare`."""

    def __init__(out self, width: Int, height: Int, bed: String) raises:
        """Read the bed and build the water. No frame is drawn yet.

        Args:
            width: The frame's width, in pixels.
            height: The frame's height, in pixels.
            bed: The pebble photograph's path. Plain sand takes its place if
                the file cannot be read.

        Raises:
            Error: If a side is not positive.
        """
        self.width = width
        self.height = height
        # The frame first, so that a bad size is refused before the bed is
        # read and the spectrum is built.
        self.frame = Framebuffer(width, height, Color(0, 0, 0))
        self.bed = _bed(bed)
        self.water = WaterScene(
            SpectrumResolution(64),
            32,
            128,
            SpectrumResolution(64),
            Duration(0.0, SECOND),
        )
        self.pitch = START_PITCH
        self.owed = 0
        self.tap = False
        self.dragging = False
        self.last_y = 0
        self.paused = False
        self.upload = None
        self.pebble = List[Float32]()
        self.pebble_table = List[Int64]()
        self.bed_generation = 0
        self.bed_packed = False
        self.samples = List[Float32]()
        self.grid = List[Float32]()
        self.grid_width = 0
        self.grid_height = 0

    def handle(mut self, kind: Int, y: Int, detail: Int):
        """Take one input event.

        The space bar pauses the app, and resumes it when pressed again. A
        press of any button taps the middle of the water on the next step and
        starts a drag. While a button is down, a move up or down tilts the
        camera. Any other event is dropped.

        Args:
            kind: The event kind, as `window.capi_abi` numbers it.
            y: The pointer's row, in pixels.
            detail: The key code of a key event. A pointer event's button is
                not used.
        """
        if kind == KEY_DOWN:
            if detail == KEY_SPACE:
                self.paused = not self.paused
        elif kind == POINTER_DOWN:
            self.dragging = True
            self.tap = True
            self.last_y = y
        elif kind == POINTER_MOVE:
            if self.dragging:
                var tilt = Float32(y - self.last_y) * RADIANS_PER_PIXEL
                var pitch = self.pitch + tilt
                self.pitch = min(HIGHEST_PITCH, max(LOWEST_PITCH, pitch))
                self.last_y = y
        elif kind == POINTER_UP:
            self.dragging = False

    def advance(mut self, microseconds: Int):
        """Move the water on by a time delta.

        The time is gathered, and one ripple step runs for each 1/30 s of it.
        Time that is negative, or that comes while the app is paused, is
        ignored. A single call counts at most 0.1 s. A step that the water
        refuses ends the call and leaves the ripples as they were.

        Args:
            microseconds: The time since the last call, in microseconds.
        """
        if self.paused or microseconds < 0:
            return
        self.owed += min(microseconds, LONGEST_MICROSECONDS)
        while self.owed >= STEP_MICROSECONDS:
            self.owed -= STEP_MICROSECONDS
            try:
                self.water.advance(
                    Duration(Float32(STEP_MICROSECONDS) / 1000000.0, SECOND),
                    self.tap,
                )
            except:
                return
            self.tap = False

    def draw(mut self) raises:
        """Draw the water on the CPU into `frame`.

        Raises:
            Error: If the size is not valid. `frame` is not changed then.
        """
        self.frame = self.water.draw(
            self.width,
            self.height,
            FRAME,
            True,
            self.bed,
            Angle(self.pitch, RADIAN),
        )

    def set_bed(mut self, file: List[UInt8]) raises:
        """Replace the pebble photograph.

        Args:
            file: A JPEG file.

        Raises:
            Error: If the bytes are not a JPEG that the decoder can read. The
                bed is not changed then.
        """
        self.bed = pebble_bed(decode(file))
        self.bed_packed = False

    def prepare(mut self) raises -> Int:
        """Make the arrays that a host's GPU draws the frame from.

        The surface, the ripples and the caustics are packed as the shader
        reads them, with the camera that `draw` uses. The photograph is packed
        again only after `set_bed`. The glare grid is sized, and `samples` is
        made ready to take the glints.

        Returns:
            How many times a photograph has been packed. A host uploads the
            photograph again when this number changes.

        Raises:
            Error: If the surface, the caustics or the glare kernels cannot be
                made. The arrays of the last frame stay.
        """
        var look = camera_look(
            self.water.clock, True, Angle(self.pitch, RADIAN)
        )
        self.upload = FrameUpload(self.water, look)
        if not self.bed_packed:
            var packed = pack_pebbles(self.bed)
            self.pebble = packed[0].copy()
            self.pebble_table = packed[1].copy()
            self.bed_generation += 1
            self.bed_packed = True
        var size = glare_grid(self.water, self.width, self.height)
        self.grid_width = size[0]
        self.grid_height = size[1]
        var floats = size[0] * size[1] * 3
        if len(self.samples) != floats:
            self.samples = List[Float32](length=floats, fill=0.0)
        return self.bed_generation

    def glare(mut self) raises:
        """Spread the glints in `samples` into the glare in `grid`.

        Raises:
            Error: If `prepare` has not run, or the samples do not fit the
                grid.
        """
        self.grid = convolve_glare(
            self.water, self.samples, self.grid_width, self.grid_height
        )

    def info(self, which: GpuInfo) -> Int:
        """Return one number about the prepared frame.

        Args:
            which: `GPU_INFO_RIPPLE_SIDE`, `GPU_INFO_GRID_WIDTH` or
                `GPU_INFO_GRID_HEIGHT`.

        Returns:
            The number, or 0 before `prepare`. `which` must be valid.
        """
        if which == GPU_INFO_GRID_WIDTH:
            return self.grid_width
        if which == GPU_INFO_GRID_HEIGHT:
            return self.grid_height
        if not self.upload:
            return 0
        return self.upload.value().ripple_side

    def part(self, which: GpuPart) -> Tuple[Int, Int]:
        """Return where one array of the prepared frame is in memory.

        Args:
            which: A `GPU_*` part from `window.capi_abi`.

        Returns:
            The address of the first byte, and the size in 32-bit words. A
            64-bit table counts two words an entry. The address and the size
            are both 0 before `prepare`. `which` must be valid.
        """
        if which == GPU_PEBBLE:
            return _floats(self.pebble)
        if which == GPU_PEBBLE_TABLE:
            return _table(self.pebble_table)
        if which == GPU_SAMPLES:
            return _floats(self.samples)
        if which == GPU_GRID:
            return _floats(self.grid)
        if not self.upload:
            return (0, 0)
        ref upload = self.upload.value()
        if which == GPU_SURFACE:
            return _floats(upload.surface)
        if which == GPU_SURFACE_TABLE:
            return _table(upload.surface_table)
        if which == GPU_RIPPLE:
            return _floats(upload.ripple)
        if which == GPU_CAUSTIC:
            return _floats(upload.caustic)
        if which == GPU_CAUSTIC_TABLE:
            return _table(upload.caustic_table)
        return _floats(upload.values)
