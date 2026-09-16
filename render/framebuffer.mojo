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
`render.target`, which keeps color as linear light at full precision until an
image is finished; a byte buffer is the wrong place to accumulate, because
every layer would round and the losses compound. This type is the *result*.

Color has two forms here. `Color` is the eight bits per channel the buffer
actually stores — sRGB encoded, ready for a display. `FloatColor` is *linear*
light, which is what lighting, filtering, clipping and interpolation must work
in, because those are arithmetic on light and sRGB is not proportional to
light. The two conversions are `FloatColor(srgb=...)` on the way in and
`encode()` on the way out, each applied exactly once; see `render.srgb`.

`FloatColor` is also three.js's `Color`, which since its color management is
a float color in the linear working space. Its setters and getters each
have a default color space, and those are kept: the hex constructor decodes
sRGB on the way in and `hex()` encodes it on the way out, as `setHex` and
`getHex` do, while the HSL constructor and `hsl()` take and give their three
numbers in the linear working space, as `setHSL` and `getHSL` do, and in
sRGB only when asked with `space=SRGB`. A half-lightness gray is therefore
linear 0.5, which encodes to 188, and not the sRGB gray 128 that `0x808080`
decodes from. `lerp`, `lerp_hsl`, `offset_hsl`, `multiply` and `add` are the
same arithmetic on the same numbers, in the working space. What three.js's
`Color` lacks is an alpha, which this keeps and the HSL operations leave
alone. CSS color names and strings are not ported.

The depth buffer holds one NDC depth per pixel, cleared to infinity so that
the first fragment to arrive always wins. Depth is what lets geometry be drawn
in any order: without it, correctness depends on the draw order or on the
scene happening to be convex.
"""

from render.srgb import (
    LINEAR,
    SRGB,
    ColorSpace,
    linear_to_srgb,
    srgb_to_linear,
)
from std.math import floor, inf


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

    def __init__(out self, *, hex: Int) raises:
        """Create an opaque color from a 24-bit value such as `0xFF8000`,
        three.js's `setHex` at the byte level.

        Args:
            hex: Red in the top byte, green in the middle, blue in the
                bottom.

        Raises:
            Error: If the value does not fit in 24 bits.
        """
        if hex < 0 or hex > 0xFFFFFF:
            raise Error("A hex color is 24 bits: 0x000000 to 0xFFFFFF")
        self.r = UInt8((hex >> 16) & 0xFF)
        self.g = UInt8((hex >> 8) & 0xFF)
        self.b = UInt8(hex & 0xFF)
        self.a = 255

    def hex(self) -> Int:
        """Return this color as a 24-bit value, three.js's `getHex`. Alpha
        is left out, as there."""
        return (Int(self.r) << 16) | (Int(self.g) << 8) | Int(self.b)


@fieldwise_init
struct HSL(ImplicitlyCopyable):
    """A color as hue, saturation and lightness, each nominally zero to
    one, in whichever color space they were asked in: the linear working
    space unless `hsl` was told `SRGB`. Hue runs once around the wheel
    from red through green and blue back to red."""

    var hue: Float32
    var saturation: Float32
    var lightness: Float32


def _hue_to_channel(low: Float32, high: Float32, hue: Float32) -> Float32:
    """Return one channel of a color from its hue, three.js's `hue2rgb`:
    `high` for a third of the wheel, `low` for another third, and a ramp
    between them either side. In whatever space the hue was given.

    Args:
        low: The channel's floor, from the lightness and saturation.
        high: Its ceiling.
        hue: Where on the wheel, offset for the channel; wrapped here.

    Returns:
        The channel, zero to one.
    """
    var t = hue
    if t < 0:
        t += 1
    if t > 1:
        t -= 1
    if t < 1.0 / 6:
        return low + (high - low) * 6 * t
    if t < 0.5:
        return high
    if t < 2.0 / 3:
        return low + (high - low) * 6 * (2.0 / 3 - t)
    return low


struct FloatColor(Equatable, ImplicitlyCopyable):
    """An RGBA color with channels as floats, nominally zero to one.

    Lighting multiplies, interpolation mixes, and clipping mixes again. Doing
    any of that in eight bits throws away precision at every step: the old
    path rounded to a byte when the vertex was lit and rounded again when a
    clipped corner was built, so a gradient crossing the near plane could
    band before it was ever rasterized.

    Color stays in this form all the way to the framebuffer, where
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
        """Create a color, opaque unless an alpha is given."""
        self.r = r
        self.g = g
        self.b = b
        self.a = a

    def __init__(out self, *, srgb: Color):
        """Decode an authored eight-bit color into linear light.

        Colors written as bytes — in a paint program, in a hex literal, in
        this source — are sRGB encoded, so shading them without decoding
        multiplies light by a number that is not proportional to light. Alpha
        is not color and is not decoded; see `render.srgb`.
        """
        self.r = srgb_to_linear(Float32(srgb.r) / 255)
        self.g = srgb_to_linear(Float32(srgb.g) / 255)
        self.b = srgb_to_linear(Float32(srgb.b) / 255)
        self.a = Float32(srgb.a) / 255

    def __init__(out self, *, of: Color):
        """Convert an eight-bit color, mapping 0-255 onto 0-1.

        No transfer function: this is for values that are already linear, or
        that are not color at all. `srgb=` is what an authored color wants.
        """
        self.r = Float32(of.r) / 255
        self.g = Float32(of.g) / 255
        self.b = Float32(of.b) / 255
        self.a = Float32(of.a) / 255

    def __init__(out self, *, hex: Int) raises:
        """Decode a 24-bit sRGB value such as `0xFF8000` to linear light,
        three.js's `setHex`. Opaque.

        Args:
            hex: Red in the top byte, green in the middle, blue in the
                bottom, as authored in sRGB.

        Raises:
            Error: If the value does not fit in 24 bits.
        """
        var bytes = Color(hex=hex)
        self.r = srgb_to_linear(Float32(bytes.r) / 255)
        self.g = srgb_to_linear(Float32(bytes.g) / 255)
        self.b = srgb_to_linear(Float32(bytes.b) / 255)
        self.a = 1.0

    def __init__(
        out self,
        *,
        hue: Float32,
        saturation: Float32,
        lightness: Float32,
        space: ColorSpace = LINEAR,
    ) raises:
        """Create a color from hue, saturation and lightness, three.js's
        `setHSL`. Opaque.

        The three describe a color in `space`: the linear working space by
        default, as three.js's `setHSL` defaults to, so that a lightness
        of a half is linear 0.5; or sRGB when asked, which is then decoded,
        so that the same half is the gray `0x808080` decodes to. Hue wraps
        around the wheel, so 1.25 is 0.25; saturation and lightness are
        clamped to zero to one.

        Args:
            hue: Where on the wheel: 0 red, 1/3 green, 2/3 blue, 1 red.
            saturation: Zero for gray, one for the pure hue.
            lightness: Zero for black, a half for the pure hue, one for
                white.
            space: `LINEAR` to take the three as they are, `SRGB` to
                decode the color they describe.

        Raises:
            Error: If `space` is neither `LINEAR` nor `SRGB`.
        """
        var raw = FloatColor._from_hsl(hue, saturation, lightness)
        if space == SRGB:
            self.r = srgb_to_linear(raw.r)
            self.g = srgb_to_linear(raw.g)
            self.b = srgb_to_linear(raw.b)
        elif space == LINEAR:
            self.r = raw.r
            self.g = raw.g
            self.b = raw.b
        else:
            raise Error("An HSL color is given in LINEAR or SRGB")
        self.a = 1.0

    @staticmethod
    def _from_hsl(
        hue: Float32, saturation: Float32, lightness: Float32
    ) -> FloatColor:
        """Return the color three numbers describe, in whatever space they
        are in: three.js's `setHSL` before its color conversion. Opaque."""
        var h = hue - floor(hue)
        var s = min(max(saturation, Float32(0)), Float32(1))
        var l = min(max(lightness, Float32(0)), Float32(1))
        var r = l
        var g = l
        var b = l
        if s > 0:
            var high = l + s - l * s
            if l <= 0.5:
                high = l * (1 + s)
            var low = 2 * l - high
            r = _hue_to_channel(low, high, h + 1.0 / 3)
            g = _hue_to_channel(low, high, h)
            b = _hue_to_channel(low, high, h - 1.0 / 3)
        return FloatColor(r, g, b, 1.0)

    def hex(self) -> Int:
        """Return this color encoded to sRGB as a 24-bit value, three.js's
        `getHex`: what `encode` gives, packed. Alpha is left out."""
        return self.encode().hex()

    def hsl(self, space: ColorSpace = LINEAR) raises -> HSL:
        """Return this color as hue, saturation and lightness, three.js's
        `getHSL`: in the linear working space by default, as three.js
        gives them, or of the color encoded to sRGB when asked. A gray has
        a hue and a saturation of zero.

        Args:
            space: `LINEAR` to take the channels apart as they are, `SRGB`
                to encode them first.

        Returns:
            The three, each nominally zero to one.

        Raises:
            Error: If `space` is neither `LINEAR` nor `SRGB`.
        """
        if space == SRGB:
            return FloatColor(
                linear_to_srgb(self.r),
                linear_to_srgb(self.g),
                linear_to_srgb(self.b),
                self.a,
            )._to_hsl()
        if space != LINEAR:
            raise Error("An HSL color is asked for in LINEAR or SRGB")
        return self._to_hsl()

    def _to_hsl(self) -> HSL:
        """Return this color's channels as hue, saturation and lightness,
        taken apart as they are: three.js's `getHSL` after its color
        conversion."""
        var r = self.r
        var g = self.g
        var b = self.b
        var high = max(r, max(g, b))
        var low = min(r, min(g, b))
        var lightness = (low + high) / 2
        var hue = Float32(0)
        var saturation = Float32(0)
        if low != high:
            var delta = high - low
            if lightness <= 0.5:
                saturation = delta / (high + low)
            else:
                saturation = delta / (2 - high - low)
            if high == r:
                hue = (g - b) / delta
                if g < b:
                    hue += 6
            elif high == g:
                hue = (b - r) / delta + 2
            else:
                hue = (r - g) / delta + 4
            hue /= 6
        return HSL(hue, saturation, lightness)

    def lerp(mut self, other: Self, alpha: Float32):
        """Move this color toward `other` by `alpha`, three.js's `lerp`:
        zero leaves it, one makes it `other`. Every channel, alpha too.

        Args:
            other: The color to move toward.
            alpha: How far, zero to one.
        """
        self.r += (other.r - self.r) * alpha
        self.g += (other.g - self.g) * alpha
        self.b += (other.b - self.b) * alpha
        self.a += (other.a - self.a) * alpha

    def lerp_hsl(mut self, other: Self, alpha: Float32):
        """Move this color toward `other` by `alpha` in hue, saturation and
        lightness, three.js's `lerpHSL`.

        The hue goes the way the numbers say and not the short way round
        the wheel, as in three.js: halfway from red at 0 to blue at 2/3 is
        green at 1/3. In the linear working space, as three.js's is. This
        color's own alpha is kept.

        Args:
            other: The color to move toward.
            alpha: How far, zero to one.
        """
        var here = self._to_hsl()
        var there = other._to_hsl()
        var mixed = FloatColor._from_hsl(
            here.hue + (there.hue - here.hue) * alpha,
            here.saturation + (there.saturation - here.saturation) * alpha,
            here.lightness + (there.lightness - here.lightness) * alpha,
        )
        self.r = mixed.r
        self.g = mixed.g
        self.b = mixed.b

    def offset_hsl(
        mut self, hue: Float32, saturation: Float32, lightness: Float32
    ):
        """Add to this color's hue, saturation and lightness, three.js's
        `offsetHSL`, in the linear working space as three.js's is. The hue
        wraps; the other two clamp. Alpha is kept.

        Args:
            hue: How far round the wheel.
            saturation: How much more saturated.
            lightness: How much lighter.
        """
        var now = self._to_hsl()
        var moved = FloatColor._from_hsl(
            now.hue + hue,
            now.saturation + saturation,
            now.lightness + lightness,
        )
        self.r = moved.r
        self.g = moved.g
        self.b = moved.b

    def multiply(mut self, other: Self):
        """Multiply this color's red, green and blue by `other`'s,
        three.js's `multiply`. Alpha is kept.

        Args:
            other: The color to multiply by.
        """
        self.r *= other.r
        self.g *= other.g
        self.b *= other.b

    def add(mut self, other: Self):
        """Add `other`'s red, green and blue to this color's, three.js's
        `add`. Alpha is kept.

        Args:
            other: The color to add.
        """
        self.r += other.r
        self.g += other.g
        self.b += other.b

    def __eq__(self, other: Self) -> Bool:
        """Return True if every channel is exactly equal, three.js's
        `equals`, alpha included."""
        return (
            self.r == other.r
            and self.g == other.g
            and self.b == other.b
            and self.a == other.a
        )

    def __ne__(self, other: Self) -> Bool:
        """Return True if any channel differs."""
        return not self == other

    def premultiplied(self) -> Self:
        """Return this color with its channels scaled by its own alpha.

        *Associated* alpha: the stored numbers are the light the surface
        actually contributes, rather than the light it would contribute if it
        were opaque. Compositing and filtering both want this form, because
        both are weighted sums and a hidden color must weigh nothing. See
        `render.target`.
        """
        return FloatColor(
            self.r * self.a, self.g * self.a, self.b * self.a, self.a
        )

    def unpremultiplied(self) -> Self:
        """Return the color this would be if it were opaque, with its alpha.

        The inverse of `premultiplied`, undefined where nothing is covered —
        a color that contributes no light has no color to recover — so a
        zero alpha gives transparent black, which is what PNG wants written.
        """
        if self.a <= 0:
            return FloatColor(0.0, 0.0, 0.0, 0.0)
        return FloatColor(
            self.r / self.a, self.g / self.a, self.b / self.a, self.a
        )

    def scaled(self, factor: Float32) -> Self:
        """Return this color with its three channels scaled, alpha kept."""
        return FloatColor(
            self.r * factor, self.g * factor, self.b * factor, self.a
        )

    def encode(self) -> Color:
        """Return the eight-bit color a display should show for this light.

        The other end of `FloatColor(srgb=...)`, applied once at the very end.
        A framebuffer holds what a display should show, not what the light
        was, so this is where linear stops. Alpha is not color and is not
        encoded.
        """
        return Color(
            _to_byte(linear_to_srgb(self.r)),
            _to_byte(linear_to_srgb(self.g)),
            _to_byte(linear_to_srgb(self.b)),
            _to_byte(self.a),
        )

    def quantize(self) -> Color:
        """Return the eight-bit color nearest this one.

        No transfer function. `encode` is what a pixel bound for a display
        wants; this is for values that were never in a color space.

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
