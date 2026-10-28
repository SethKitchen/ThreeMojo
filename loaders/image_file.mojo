# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An image file decoded by what its first bytes say it is.

The model loaders read the textures their files name with
`decode_image`: glTF, Collada's neighbors, MTL, 3MF, LWO, 3DS, VRML, USD
and the CARLA assets.
"""

from render.jpeg import decode as decode_jpeg
from render.png import DecodedImage, decode as decode_png
from render.tga import decode as decode_tga
from render.webp import decode as decode_webp, is_webp


def decode_image(bytes: List[UInt8]) raises -> DecodedImage:
    """Return an image decoded by what its first bytes say it is.

    A PNG, a JPEG and a WebP file each begin with a signature. A TGA has
    none, so bytes that begin as none of those are read as a TGA, whose
    header check refuses most other files. glTF names PNG and JPEG, and
    `EXT_texture_webp` WebP; the TGA fallback is this port's, for a model
    that points at a TGA texture.

    Args:
        bytes: A PNG, a JPEG, a WebP or a TGA file.

    Returns:
        The image.

    Raises:
        Error: If the bytes begin as none of PNG, JPEG and WebP and are not
            a TGA either, or the decoder refuses them.
    """
    if len(bytes) >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50:
        return decode_png(bytes)
    if len(bytes) >= 2 and bytes[0] == 0xFF and bytes[1] == 0xD8:
        return decode_jpeg(bytes)
    if is_webp(bytes):
        return decode_webp(bytes)
    try:
        return decode_tga(bytes)
    except error:
        raise Error(
            "glTF: an image that is neither PNG nor JPEG, and not a TGA: "
            + String(error)
        )
