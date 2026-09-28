# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The depth of six square renders as one cube, ported from three.js
`src/textures/CubeDepthTexture.js`.

three.js's `CubeDepthTexture` is a `DepthTexture` with six images, one a
face, read by direction with `CubeReflectionMapping` and `NearestFilter`.
A cube render target holds one to keep the depth of each face.

Here each face is what `render.texture.depth_texture_of_buffer` makes of
one depth buffer: the window depth, from zero at the near plane to one at
the far plane, as a gray texel read nearest. The six faces make a
`CubeTexture`, so `CubeTexture.sample` reads the depth in a direction.
Draw the six faces with the six cameras of a `CubeCamera`.
"""

from render.cube_texture import FACE_COUNT, CubeTexture
from render.framebuffer import Framebuffer
from render.raster_state import STANDARD_DEPTH, DepthMode
from render.texture import CLAMP, Texture, depth_texture_of_buffer


def cube_depth_texture(
    size: Int, depths: List[Float32], mode: DepthMode = STANDARD_DEPTH
) raises -> CubeTexture:
    """Return six depth buffers as one cube, three.js's
    `new CubeDepthTexture( size )` holding them.

    Args:
        size: The width and the height of each face, in texels.
        depths: The six buffers one after another, in `POSITIVE_X` through
            `NEGATIVE_Z` order, each row-major from the top, as a render
            target stores its depth.
        mode: How the depth is stored; see `render.raster_state`.

    Returns:
        The cube, its faces read nearest and wrapped `CLAMP`.

    Raises:
        Error: If the size is not positive, the buffers do not hold six
            faces of that size, or the depth mode is none of the three.
    """
    if size <= 0:
        raise Error("A cube depth texture needs a face of one texel at least")
    var face_length = size * size
    if len(depths) != FACE_COUNT * face_length:
        raise Error("A cube depth texture needs six square depth buffers")
    var faces = List[Texture]()
    for face in range(FACE_COUNT):  # pragma: no branch
        var start = face * face_length
        faces.append(
            depth_texture_of_buffer(
                size,
                size,
                List[Float32](depths[start : start + face_length]),
                CLAMP,
                mode,
            )
        )
    return CubeTexture(faces^)


def cube_depth_texture_of(
    images: List[Framebuffer], mode: DepthMode = STANDARD_DEPTH
) raises -> CubeTexture:
    """Return the depth of six rendered images as one cube.

    Args:
        images: Six square images of one size, in `POSITIVE_X` through
            `NEGATIVE_Z` order, as a `CubeCamera`'s six cameras render
            them.
        mode: How the renderer stored the depth.

    Returns:
        The cube; see `cube_depth_texture`.

    Raises:
        Error: If there are not six images, they are not square and of one
            size, or the depth mode is none of the three.
    """
    if len(images) != FACE_COUNT:
        raise Error("A cube depth texture is built from exactly six images")
    var size = images[0].width
    var depths = List[Float32]()
    for face in range(FACE_COUNT):  # pragma: no branch
        if images[face].width != size or images[face].height != size:
            raise Error(
                "A cube depth texture needs six square images of one size"
            )
        depths.extend(Span(images[face].depth))
    return cube_depth_texture(size, depths, mode)
