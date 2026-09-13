# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An RGBA pixel buffer.

three.js renders into a WebGLRenderTarget and lets the browser present it. With
no graphics API underneath us, the equivalent is a plain byte buffer we fill
ourselves. Displaying it is somebody else's job — a canvas, a window, a texture
upload — so this module knows nothing about file formats. The encoders in
`render.ppm` and `render.png` read the buffer; the buffer never writes itself.

Keeping the buffer separate from the rasterizer also means the per-pixel logic
can be tested without capturing stdout, and later lets a GPU kernel fill the
same bytes.
"""


struct Color(ImplicitlyCopyable):
    """An 8-bit-per-channel RGBA color."""

    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    def __init__(out self, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255):
        """Create a color, opaque unless an alpha is given."""
        self.r = r
        self.g = g
        self.b = b
        self.a = a


struct Framebuffer(Movable):
    """A width x height buffer of RGBA pixels, stored row-major from the top."""

    comptime CHANNELS = 4

    var width: Int
    var height: Int
    var pixels: List[UInt8]

    def __init__(out self, width: Int, height: Int, clear: Color) raises:
        """Create a buffer of the given size, filled with `clear`."""
        if width <= 0 or height <= 0:
            raise Error("Framebuffer dimensions must be positive")
        self.width = width
        self.height = height
        self.pixels = List[UInt8](length=width * height * Self.CHANNELS, fill=0)
        # Both dimensions are proven positive above, so neither loop can
        # run zero times.
        for y in range(height):  # pragma: no branch
            for x in range(width):  # pragma: no branch
                self.set_pixel(x, y, clear)

    def __init__(
        out self, width: Int, height: Int, var pixels: List[UInt8]
    ) raises:
        """Adopt an existing RGBA byte buffer.

        Used when the pixels came from somewhere that already filled them — a
        GPU kernel, say — so that wrapping them costs nothing. The clearing
        constructor would otherwise overwrite the work that was just done.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.
            pixels: Row-major RGBA bytes, exactly width * height * 4 of them.

        Raises:
            Error: If the dimensions are not positive, or the buffer length
                disagrees with them.
        """
        if width <= 0 or height <= 0:
            raise Error("Framebuffer dimensions must be positive")
        if len(pixels) != width * height * Self.CHANNELS:
            raise Error("Pixel buffer length does not match the dimensions")
        self.width = width
        self.height = height
        self.pixels = pixels^

    def _offset(self, x: Int, y: Int) raises -> Int:
        """Return the index of pixel (x, y)'s red channel."""
        if x < 0 or x >= self.width or y < 0 or y >= self.height:
            raise Error("Pixel coordinate out of bounds")
        return (y * self.width + x) * Self.CHANNELS

    def set_pixel(mut self, x: Int, y: Int, color: Color) raises:
        """Write `color` to pixel (x, y)."""
        var i = self._offset(x, y)
        self.pixels[i] = color.r
        self.pixels[i + 1] = color.g
        self.pixels[i + 2] = color.b
        self.pixels[i + 3] = color.a

    def get_pixel(self, x: Int, y: Int) raises -> Color:
        """Return the color at pixel (x, y)."""
        var i = self._offset(x, y)
        return Color(
            self.pixels[i],
            self.pixels[i + 1],
            self.pixels[i + 2],
            self.pixels[i + 3],
        )
