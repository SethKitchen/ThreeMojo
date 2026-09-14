# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An RGBA pixel buffer with a depth buffer alongside it.

three.js renders into a WebGLRenderTarget and lets the browser present it. With
no graphics API underneath us, the equivalent is a plain byte buffer we fill
ourselves. Displaying it is somebody else's job — a canvas, a window, a texture
upload — so this module knows nothing about file formats. The encoders in
`render.ppm` and `render.png` read the buffer; the buffer never writes itself.

Keeping the buffer separate from the rasterizer also means the per-pixel logic
can be tested without capturing stdout, and later lets a GPU kernel fill the
same bytes.

Compositing does not happen here. Blending and depth-passing live on
`render.target`, which keeps colour as linear light at full precision until an
image is finished; a byte buffer is the wrong place to accumulate, because
every layer would round and the losses compound. This type is the *result*.

Colour has two forms here. `Color` is the eight bits per channel the buffer
actually stores — sRGB encoded, ready for a display. `FloatColor` is *linear*
light, which is what lighting, filtering, clipping and interpolation must work
in, because those are arithmetic on light and sRGB is not proportional to
light. The two conversions are `FloatColor(srgb=...)` on the way in and
`encode()` on the way out, each applied exactly once; see `render.srgb`.

The depth buffer holds one NDC depth per pixel, cleared to infinity so that
the first fragment to arrive always wins. Depth is what lets geometry be drawn
in any order: without it, correctness depends on the draw order or on the
scene happening to be convex.
"""

from render.srgb import linear_to_srgb, srgb_to_linear
from std.math import inf


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


struct FloatColor(ImplicitlyCopyable):
    """An RGBA colour with channels as floats, nominally zero to one.

    Lighting multiplies, interpolation mixes, and clipping mixes again. Doing
    any of that in eight bits throws away precision at every step: the old
    path rounded to a byte when the vertex was lit and rounded again when a
    clipped corner was built, so a gradient crossing the near plane could
    band before it was ever rasterized.

    Colour stays in this form all the way to the framebuffer, where
    `quantize` converts once. Values may exceed one on the way — a bright
    light, an accumulated highlight — and are clamped only at that final step
    rather than after each operation.
    """

    var r: Float32
    var g: Float32
    var b: Float32
    var a: Float32

    def __init__(
        out self, r: Float32, g: Float32, b: Float32, a: Float32 = 1.0
    ):
        """Create a colour, opaque unless an alpha is given."""
        self.r = r
        self.g = g
        self.b = b
        self.a = a

    def __init__(out self, *, srgb: Color):
        """Decode an authored eight-bit colour into linear light.

        Colours written as bytes — in a paint program, in a hex literal, in
        this source — are sRGB encoded, so shading them without decoding
        multiplies light by a number that is not proportional to light. Alpha
        is not colour and is not decoded; see `render.srgb`.
        """
        self.r = srgb_to_linear(Float32(srgb.r) / 255)
        self.g = srgb_to_linear(Float32(srgb.g) / 255)
        self.b = srgb_to_linear(Float32(srgb.b) / 255)
        self.a = Float32(srgb.a) / 255

    def __init__(out self, *, of: Color):
        """Convert an eight-bit colour, mapping 0-255 onto 0-1.

        No transfer function: this is for values that are already linear, or
        that are not colour at all. `srgb=` is what an authored colour wants.
        """
        self.r = Float32(of.r) / 255
        self.g = Float32(of.g) / 255
        self.b = Float32(of.b) / 255
        self.a = Float32(of.a) / 255

    def premultiplied(self) -> Self:
        """Return this colour with its channels scaled by its own alpha.

        *Associated* alpha: the stored numbers are the light the surface
        actually contributes, rather than the light it would contribute if it
        were opaque. Compositing and filtering both want this form, because
        both are weighted sums and a hidden colour must weigh nothing. See
        `render.target`.
        """
        return FloatColor(
            self.r * self.a, self.g * self.a, self.b * self.a, self.a
        )

    def unpremultiplied(self) -> Self:
        """Return the colour this would be if it were opaque, with its alpha.

        The inverse of `premultiplied`, undefined where nothing is covered —
        a colour that contributes no light has no colour to recover — so a
        zero alpha gives transparent black, which is what PNG wants written.
        """
        if self.a <= 0:
            return FloatColor(0.0, 0.0, 0.0, 0.0)
        return FloatColor(
            self.r / self.a, self.g / self.a, self.b / self.a, self.a
        )

    def scaled(self, factor: Float32) -> Self:
        """Return this colour with its three channels scaled, alpha kept."""
        return FloatColor(
            self.r * factor, self.g * factor, self.b * factor, self.a
        )

    def encode(self) -> Color:
        """Return the eight-bit colour a display should show for this light.

        The other end of `FloatColor(srgb=...)`, applied once at the very end.
        A framebuffer holds what a display should show, not what the light
        was, so this is where linear stops. Alpha is not colour and is not
        encoded.
        """
        return Color(
            _to_byte(linear_to_srgb(self.r)),
            _to_byte(linear_to_srgb(self.g)),
            _to_byte(linear_to_srgb(self.b)),
            _to_byte(self.a),
        )

    def quantize(self) -> Color:
        """Return the eight-bit colour nearest this one.

        No transfer function. `encode` is what a pixel bound for a display
        wants; this is for values that were never in a colour space.

        Rounds rather than truncates. Truncating costs a level everywhere: a
        face square-on to the light has a Lambert term of 0.99999 rather than
        1, and converting that straight to an integer turns 200 into 199.
        """
        return Color(
            _to_byte(self.r),
            _to_byte(self.g),
            _to_byte(self.b),
            _to_byte(self.a),
        )


def _to_byte(value: Float32) -> UInt8:
    """Return `value` in 0-1 as a rounded, clamped byte."""
    var scaled = value * 255 + 0.5
    if scaled <= 0:
        return 0
    if scaled >= 255:
        return 255
    return UInt8(scaled)


struct Framebuffer(Movable):
    """A width x height buffer of RGBA pixels, stored row-major from the top."""

    comptime CHANNELS = 4

    var width: Int
    var height: Int
    var pixels: List[UInt8]
    # One depth per pixel, not per channel. Infinity means "nothing here yet".
    var depth: List[Float32]

    def __init__(out self, width: Int, height: Int, clear: Color) raises:
        """Create a buffer of the given size, filled with `clear`."""
        if width <= 0 or height <= 0:
            raise Error("Framebuffer dimensions must be positive")
        self.width = width
        self.height = height
        self.pixels = List[UInt8](length=width * height * Self.CHANNELS, fill=0)
        self.depth = List[Float32](
            length=width * height, fill=inf[DType.float32]()
        )
        # Both dimensions are proven positive above, so neither loop can
        # run zero times.
        for y in range(height):  # pragma: no branch
            for x in range(width):  # pragma: no branch
                self.set_pixel(x, y, clear)

    def __init__(
        out self, width: Int, height: Int, var pixels: List[UInt8]
    ) raises:
        """Adopt an existing RGBA byte buffer.

        Used when the pixels came from somewhere that already filled them so
        that wrapping them costs nothing; the clearing constructor would
        overwrite the work that was just done. The depth buffer is set to
        infinity, meaning "nothing here yet" — if the source knows the depths
        too, use the four-argument version instead and say so.

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
        self.depth = List[Float32](
            length=width * height, fill=inf[DType.float32]()
        )

    def __init__(
        out self,
        width: Int,
        height: Int,
        var pixels: List[UInt8],
        var depth: List[Float32],
    ) raises:
        """Adopt existing pixels *and* the depth that goes with them.

        The three-argument version above fills the depth buffer with infinity,
        which is right for pixels that arrived without any — but wrong for
        pixels that arrived *with* some. A GPU readback that used it returned
        an image whose `depth_at` said nothing was there, so drawing one more
        depth-tested triangle into it would paint straight over a nearer
        surface.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.
            pixels: Row-major RGBA bytes, exactly width * height * 4 of them.
            depth: One NDC depth per pixel, infinity where nothing was drawn.

        Raises:
            Error: If the dimensions are not positive, or either buffer's
                length disagrees with them.
        """
        if width <= 0 or height <= 0:
            raise Error("Framebuffer dimensions must be positive")
        if len(pixels) != width * height * Self.CHANNELS:
            raise Error("Pixel buffer length does not match the dimensions")
        if len(depth) != width * height:
            raise Error("Depth buffer length does not match the dimensions")
        self.width = width
        self.height = height
        self.pixels = pixels^
        self.depth = depth^

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

    def depth_at(self, x: Int, y: Int) raises -> Float32:
        """Return the depth recorded at pixel (x, y)."""
        if x < 0 or x >= self.width or y < 0 or y >= self.height:
            raise Error("Pixel coordinate out of bounds")
        return self.depth[y * self.width + x]

    def test_depth(mut self, x: Int, y: Int, z: Float32) raises -> Bool:
        """Return True if `z` is nearer than what is stored, and claim it.

        The test and the write are one operation because separating them
        invites the caller to do one without the other, which is how a depth
        buffer quietly stops working.
        """
        if x < 0 or x >= self.width or y < 0 or y >= self.height:
            raise Error("Pixel coordinate out of bounds")
        var slot = y * self.width + x
        if z >= self.depth[slot]:
            return False
        self.depth[slot] = z
        return True

    def get_pixel(self, x: Int, y: Int) raises -> Color:
        """Return the color at pixel (x, y)."""
        var i = self._offset(x, y)
        return Color(
            self.pixels[i],
            self.pixels[i + 1],
            self.pixels[i + 2],
            self.pixels[i + 3],
        )
