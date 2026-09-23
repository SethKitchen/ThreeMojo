# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An image of linear light read from an HDR file: what `render.rgbe` and
`render.exr` return, and what `render.texture.float_texture_from` takes.

The float counterpart of `render.png.DecodedImage`, and apart from it for
the reason that one is apart from `Framebuffer`: samples carry a meaning.
A `DecodedImage` holds bytes and says which curve encodes them. This holds
floats, and floats from an HDR file mean one thing only, linear light with
no upper bound, so there is no color space to carry.
"""


struct FloatImage(Movable):
    """Linear RGBA floats, row-major from the top."""

    comptime CHANNELS = 4

    var width: Int
    var height: Int
    # Four floats a pixel, red, green, blue and alpha, from the top row
    # down, as `DecodedImage.pixels` holds bytes. A file with no alpha
    # reads as an alpha of one.
    var pixels: List[Float32]

    def __init__(out self, width: Int, height: Int, var pixels: List[Float32]):
        """Adopt decoded samples.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.
            pixels: Row-major RGBA floats from the top, width * height * 4.
        """
        self.width = width
        self.height = height
        self.pixels = pixels^

    def get_pixel(self, x: Int, y: Int) raises -> SIMD[DType.float32, 4]:
        """Return the sample at (x, y).

        Args:
            x: Column.
            y: Row from the top.

        Returns:
            Red, green, blue and alpha, as stored.

        Raises:
            Error: If the coordinate is outside the image.
        """
        if x < 0 or x >= self.width or y < 0 or y >= self.height:
            raise Error("Pixel coordinate out of bounds")
        var at = (y * self.width + x) * Self.CHANNELS
        return SIMD[DType.float32, 4](
            self.pixels[at],
            self.pixels[at + 1],
            self.pixels[at + 2],
            self.pixels[at + 3],
        )
