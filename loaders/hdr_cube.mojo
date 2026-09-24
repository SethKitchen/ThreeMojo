# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Six Radiance `.hdr` files as one float cube texture: three.js's
`HDRCubeTextureLoader`.

`read_hdr_cube_texture` reads six files with `render.rgbe`, in `px`,
`nx`, `py`, `ny`, `pz`, `nz` order, as three.js reads its six URLs.
`hdr_cube_texture_from` does the same for six decoded images. Each face
is a float texture, `LINEAR`, `CLAMP` and `BILINEAR`, with no chain of
smaller copies: three.js's settings for the loader's textures. The
layout is `cube_texture_from`'s: `SEEN_FROM_OUTSIDE` reads the files as
three.js's cube loaders do.

**Where this port differs.** three.js's default type is
`HalfFloatType`, which rounds each value to a half. This port keeps the
floats, as three.js's `setDataType(FloatType)` does: see "What is not
ported" in the textures page.
"""

from render.cube_texture import (
    FACE_COUNT,
    NEGATIVE_X,
    SEEN_FROM_INSIDE,
    SEEN_FROM_OUTSIDE,
    CubeLayout,
    CubeTexture,
)
from render.float_image import FloatImage
from render.rgbe import decode as decode_rgbe
from render.texture import BILINEAR, CLAMP, Texture, float_texture
from std.pathlib import Path


def hdr_cube_texture_from(
    images: List[FloatImage],
    layout: CubeLayout = SEEN_FROM_INSIDE,
    mipmapped: Bool = False,
) raises -> CubeTexture:
    """Return a float cube texture of six HDR images, as three.js's
    `HDRCubeTextureLoader` builds it.

    Args:
        images: Six images, all square and of one size, in `px`, `nx`,
            `py`, `ny`, `pz`, `nz` order.
        layout: `SEEN_FROM_INSIDE` if each image is what a camera at the
            center sees along its own axis, `SEEN_FROM_OUTSIDE` for
            three.js's layout of six image files.
        mipmapped: Build each face's chain of smaller copies. three.js
            builds none.

    Returns:
        The cube texture.

    Raises:
        Error: If there are not six images, the layout is neither named
            value, a value is not finite, or the faces are refused by
            `CubeTexture.validate`.
    """
    if len(images) != FACE_COUNT:
        raise Error("An HDR cube texture is built from exactly six images")
    if not layout.is_valid():
        raise Error(
            "A cube layout must be SEEN_FROM_INSIDE or SEEN_FROM_OUTSIDE"
        )
    var faces = List[Texture]()
    # A cube has six faces. The loop always runs.
    for index in range(FACE_COUNT):  # pragma: no branch
        var source = index
        if layout == SEEN_FROM_OUTSIDE and index < NEGATIVE_X + 1:
            # POSITIVE_X reads the nx image and NEGATIVE_X the px one.
            source = NEGATIVE_X - index
        ref image = images[source]
        faces.append(
            float_texture(
                image.width,
                image.height,
                image.pixels.copy(),
                CLAMP,
                BILINEAR,
                mipmapped,
            )
        )
    return CubeTexture(faces^)


def read_hdr_cube_texture(
    paths: List[String],
    layout: CubeLayout = SEEN_FROM_INSIDE,
    mipmapped: Bool = False,
) raises -> CubeTexture:
    """Read six Radiance `.hdr` files into a float cube texture, as
    three.js's `HDRCubeTextureLoader.load` reads six URLs.

    Args:
        paths: Six files, in `px`, `nx`, `py`, `ny`, `pz`, `nz` order.
        layout: `SEEN_FROM_INSIDE` or `SEEN_FROM_OUTSIDE`; see
            `hdr_cube_texture_from`.
        mipmapped: Build each face's chain of smaller copies.

    Returns:
        The cube texture.

    Raises:
        Error: If there are not six paths, a file cannot be read or is
            refused by `render.rgbe.decode`, or the images are refused by
            `hdr_cube_texture_from`.
    """
    if len(paths) != FACE_COUNT:
        raise Error("An HDR cube texture is read from exactly six files")
    var images = List[FloatImage]()
    # Six files. The loop always runs.
    for path in paths:  # pragma: no branch
        images.append(decode_rgbe(Path(path).read_bytes()))
    return hdr_cube_texture_from(images, layout, mipmapped)
