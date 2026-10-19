# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The numbers that the C ABI's two builds share.

`window.capi_core` and `window.capi_scene` export the same C names, so a
program must never import both. They import these numbers from here,
which exports nothing. The water's GPU functions take a part and an info
number, which are the types `GpuPart` and `GpuInfo` here. The splat
library's take the types `SplatPart` and `SplatInfo`.
"""

comptime ABI_VERSION = 1
"""The version of the C ABI. It changes when a function changes."""
comptime MAX_SIDE = 4096
"""The largest frame width or height, in pixels."""
comptime KEY_DOWN = 0
"""The event kind of a key press. The value of `InputKind` `KEY_DOWN`."""
comptime POINTER_DOWN = 1
"""The event kind of a button press. The value of `POINTER_DOWN`."""
comptime POINTER_MOVE = 2
"""The event kind of a pointer move. The value of `POINTER_MOVE`."""
comptime POINTER_UP = 3
"""The event kind of a button release. The value of `POINTER_UP`."""
comptime WHEEL = 4
"""The event kind of a wheel notch. The value of `InputKind` `WHEEL`. Its
detail is the notches, positive toward the user."""
comptime KEY_UP = 6
"""The event kind of a key release. The value of `InputKind` `KEY_UP`."""
comptime KEY_SPACE = 32
"""The key code of the space bar, which pauses and resumes an app."""


@fieldwise_init
struct GpuPart(Equatable, ImplicitlyCopyable, Writable):
    """Which array of a prepared frame a host asks for, as a type rather than
    a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the ten parts there are.

        Returns:
            Whether the value names a part.
        """
        return self.value >= 0 and self.value <= 9


@fieldwise_init
struct GpuInfo(Equatable, ImplicitlyCopyable, Writable):
    """Which number about a prepared frame a host asks for, as a type rather
    than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three numbers there are.

        Returns:
            Whether the value names a number.
        """
        return self.value >= 0 and self.value <= 2


comptime GPU_SURFACE = GpuPart(0)
"""The part of a prepared frame that holds the surface texels: floats."""
comptime GPU_SURFACE_TABLE = GpuPart(1)
"""The part that holds the surface level table: 64-bit integers."""
comptime GPU_RIPPLE = GpuPart(2)
"""The part that holds the ripple normal texture: floats."""
comptime GPU_CAUSTIC = GpuPart(3)
"""The part that holds the caustic texels: floats."""
comptime GPU_CAUSTIC_TABLE = GpuPart(4)
"""The part that holds the caustic level table: 64-bit integers."""
comptime GPU_PEBBLE = GpuPart(5)
"""The part that holds the pebble photograph's texels: floats."""
comptime GPU_PEBBLE_TABLE = GpuPart(6)
"""The part that holds the photograph's level table: 64-bit integers."""
comptime GPU_VALUES = GpuPart(7)
"""The part that holds the frame values: floats."""
comptime GPU_SAMPLES = GpuPart(8)
"""The part that the host fills with the glare's glints: floats."""
comptime GPU_GRID = GpuPart(9)
"""The part that holds the glare after `tm_gpu_glare`: floats."""
comptime GPU_INFO_RIPPLE_SIDE = GpuInfo(0)
"""The info number of the ripple texels on one side."""
comptime GPU_INFO_GRID_WIDTH = GpuInfo(1)
"""The info number of the glare grid's width."""
comptime GPU_INFO_GRID_HEIGHT = GpuInfo(2)
"""The info number of the glare grid's height."""


@fieldwise_init
struct SplatPart(Equatable, ImplicitlyCopyable, Writable):
    """Which array of a splat scan a host asks for, as a type rather than a
    bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the eight parts there are.

        Returns:
            Whether the value names a part.
        """
        return self.value >= 0 and self.value <= 7


@fieldwise_init
struct SplatInfo(Equatable, ImplicitlyCopyable, Writable):
    """Which number about a splat scan a host asks for, as a type rather than
    a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four numbers there are.

        Returns:
            Whether the value names a number.
        """
        return self.value >= 0 and self.value <= 3


comptime SPLAT_CENTERS = SplatPart(0)
"""The part that holds the splats' centers: three floats a splat."""
comptime SPLAT_COVARIANCES = SplatPart(1)
"""The part that holds the splats' covariances: six floats a splat."""
comptime SPLAT_COLORS = SplatPart(2)
"""The part that holds the splats' colors: one word a splat, red in the low
byte and opacity in the high byte."""
comptime SPLAT_SH1 = SplatPart(3)
"""The part that holds the first spherical harmonics band: three words a splat."""
comptime SPLAT_SH2 = SplatPart(4)
"""The part that holds the second band: four words a splat."""
comptime SPLAT_SH3 = SplatPart(5)
"""The part that holds the third band: six words a splat."""
comptime SPLAT_ORDER = SplatPart(6)
"""The part that holds the draw order: one word a splat, furthest first."""
comptime SPLAT_VIEW = SplatPart(7)
"""The part that holds the view: `SPLAT_VIEW_FLOATS` floats."""
comptime SPLAT_INFO_COUNT = SplatInfo(0)
"""The info number of how many splats the scan has."""
comptime SPLAT_INFO_DEGREE = SplatInfo(1)
"""The info number of the highest spherical harmonics band, 0 through 3."""
comptime SPLAT_INFO_SCAN = SplatInfo(2)
"""The info number of how many scans the app has loaded. A host uploads the
static parts again when it changes."""
comptime SPLAT_INFO_ORDER = SplatInfo(3)
"""The info number of how many times the order has been made. A host uploads
`SPLAT_ORDER` again when it changes."""
comptime SPLAT_VIEW_FLOATS = 48
"""How many floats the `SPLAT_VIEW` part holds."""
