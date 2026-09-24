# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Color lookup tables stored as images, from three.js
`examples/jsm/loaders/LUTImageLoader.js`.

A table of `size` entries a side is an image of `size` squares, each
`size` by `size` texels: one square for each blue value, red across and
green down. The squares are stacked in a column, or set side by side in
a row. `lut_image_from` takes a decoded image of either shape, turns a
row into a column as three.js's `_horz2Vert` draws it, and makes a
`Data3DTexture` of the bytes as three.js's `parse` does: `size` texels a
side, clamped, bilinear and linear.

**Where this port differs.** three.js draws the image on a canvas; this
reads the decoded bytes. three.js's `flip` is not ported: with a row of
squares, three.js draws the first square above its canvas. A column must
be `size` squares tall and a row `size` squares wide; three.js makes a
texture whose data does not fill it for any other shape, and this
refuses it.
"""

from loaders.gltf import decode_image
from render.png import DecodedImage
from render.srgb import LINEAR
from render.texture import BILINEAR, CLAMP
from render.volume_texture import Data3DTexture, VolumeImage
from std.pathlib import Path


struct LutImage(Movable):
    """What three.js's `LUTImageLoader` gives: `{ size, texture3D }`."""

    var size: Int
    var texture: Data3DTexture

    def __init__(out self, size: Int, var texture: Data3DTexture):
        """Hold a table.

        Args:
            size: Entries a side.
            texture: The table.
        """
        self.size = size
        self.texture = texture^


def parse_lut_image(data: List[UInt8], size: Int) raises -> LutImage:
    """Make a table of RGBA bytes, three.js's `LUTImageLoader.parse`.

    Args:
        data: Four bytes a texel: a column of `size` squares, each `size`
            by `size`, row by row from the top.
        size: Entries a side.

    Returns:
        The table.

    Raises:
        Error: If the size is below one, or the data does not hold `size`
            cubed texels.
    """
    if size < 1:
        raise Error("LUT image: a size below one")
    if len(data) != size * size * size * 4:
        raise Error(
            "LUT image: a table of size "
            + String(size)
            + " needs "
            + String(size * size * size)
            + " texels"
        )
    var image = VolumeImage.of_bytes(size, size, size, data, 4)
    return LutImage(size, Data3DTexture(image^, CLAMP, BILINEAR, LINEAR))


def lut_image_from(image: DecodedImage) raises -> LutImage:
    """Make a table of a decoded image, three.js's `LUTImageLoader.load`
    after the image is drawn.

    Args:
        image: A column of squares, taller than it is wide, or a row of
            them.

    Returns:
        The table; its size is the image's smaller side.

    Raises:
        Error: If the image is not `size` squares long, or `parse_lut_image`
            refuses the bytes.
    """
    var width = image.width
    var height = image.height
    if width < height:
        if height != width * width:
            raise Error("LUT image: a column must be as many squares as wide")
        return parse_lut_image(image.pixels, width)
    var size = height
    if width != size * size:
        raise Error("LUT image: a row must be as many squares as tall")
    var column = List[UInt8](length=size * width * 4, fill=0)
    for i in range(size):
        # Inside the loop over `size`, so `size` is one or more here.
        for y in range(size):  # pragma: no branch
            for x in range(size):  # pragma: no branch
                var source = (y * width + i * size + x) * 4
                var target = ((i * size + y) * size + x) * 4
                for c in range(4):  # pragma: no branch
                    column[target + c] = image.pixels[source + c]
    return parse_lut_image(column, size)


def read_lut_image(path: String) raises -> LutImage:
    """Read a table from an image file.

    Args:
        path: A PNG, a JPEG or a TGA.

    Returns:
        What `lut_image_from` gives.

    Raises:
        Error: If the file cannot be read or decoded, or for anything
            `lut_image_from` refuses.
    """
    return lut_image_from(decode_image(Path(path).read_bytes()))
