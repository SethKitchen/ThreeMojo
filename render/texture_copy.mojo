# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Texture copies, from three.js's `WebGLRenderer.copyTextureToTexture`,
`WebGLRenderer.copyFramebufferToTexture` and
`src/textures/FramebufferTexture.js`.

**A copy moves stored texels and converts nothing.** WebGL's
`texSubImage` and `copyTexSubImage` write the numbers the source holds
into the destination's storage. So a byte texture takes bytes and a float
texture takes floats, and a copy between the two is refused, as WebGL
refuses a copy between formats that do not match. No color space is
applied on the way.

**Coordinates are WebGL's.** A texel's row counts up from `v = 0`, as
WebGL's texel coordinates do. For a `Texture` with `flip_y`, the default
for an image, row zero is the last stored row. Without `flip_y` it is the
first. A volume's rows already run up. A framebuffer's row counts up from
its bottom, as `render.rect` counts a scissor. A source region is a
`Rect` or a `TexelBox`, and a destination is a `TexelPoint`.

**Levels.** A 2D copy reads one level of the source and writes one level
of the destination. A write into the first level of a texture with a
chain rebuilds the chain, as three.js calls `generateMipmap` after a copy
into level zero of a texture that generates mipmaps.
"""

from render.framebuffer import Framebuffer
from render.rect import Rect
from render.srgb import LINEAR, SRGB, ColorSpace
from render.target import UNSIGNED_BYTE_TARGET, RenderTarget
from render.texture import (
    FLOAT_TYPE,
    NEAREST,
    UNSIGNED_BYTE_TYPE,
    CLAMP,
    TexelType,
    Texture,
    float_texture,
)
from render.volume_texture import VOLUME_CHANNELS, VolumeImage


@fieldwise_init
struct TexelPoint(Equatable, ImplicitlyCopyable, Writable):
    """Where a copy lands: three.js's `dstPosition`, a `Vector2` or a
    `Vector3`. The row counts up; see the module docstring."""

    var x: Int
    var y: Int
    # The layer or slice of a volume. Zero for a 2D texture.
    var z: Int


@fieldwise_init
struct TexelBox(Equatable, ImplicitlyCopyable, Writable):
    """A block of texels to copy: three.js's `srcRegion` as a `Box3`, as a
    corner and a size. The row counts up; see the module docstring."""

    var x: Int
    var y: Int
    var z: Int
    var width: Int
    var height: Int
    var depth: Int

    def is_valid(self) -> Bool:
        """Return True if the box holds at least one texel.

        Returns:
            Whether every side is positive.
        """
        return self.width > 0 and self.height > 0 and self.depth > 0


def _check_place(
    x: Int, y: Int, width: Int, height: Int, wide: Int, tall: Int
) raises:
    """Refuse a rectangle that is empty or reaches outside an image."""
    if not Rect(x, y, width, height).fits(wide, tall):
        raise Error("A texture copy must lie inside both images")


def _stored_row(texture: Texture, level: Int, row: Int) -> Int:
    """Return which stored row of `level` holds WebGL row `row`."""
    if texture.flip_y:
        return texture.level_height(level) - 1 - row
    return row


def _check_level(texture: Texture, level: Int) raises:
    """Refuse a blank texture, or a level its chain does not hold."""
    texture.validate()
    if texture.is_blank():
        raise Error("A texture copy needs a texture that holds texels")
    if level < 0 or level >= texture.levels:
        raise Error("A texture copy names a level the texture does not hold")


def _texel_start(texture: Texture, level: Int, x: Int, row: Int) -> Int:
    """Return where WebGL texel `(x, row)` of `level` starts in the texel
    buffer."""
    return (
        texture.offsets[level]
        + (_stored_row(texture, level, row) * texture.level_width(level) + x)
        * Texture.CHANNELS
    )


def _regenerate(mut texture: Texture, level: Int) raises:
    """Rebuild the chain of a texture whose first level was written."""
    if level == 0 and texture.levels > 1:
        texture.regenerate_mipmaps()


def copy_texture_to_texture(
    source: Texture,
    mut destination: Texture,
    region: Optional[Rect] = None,
    position: TexelPoint = TexelPoint(0, 0, 0),
    source_level: Int = 0,
    destination_level: Int = 0,
) raises:
    """Copy a rectangle of one 2D texture into another: three.js's
    `copyTextureToTexture(src, dst, srcRegion, dstPosition, srcLevel,
    dstLevel)`.

    Args:
        source: The texture to read.
        destination: The texture to write.
        region: The texels to copy, the corner at `v = 0`. The whole
            source level by default.
        position: Where the region's corner lands. `z` must be zero.
        source_level: The source's mip level.
        destination_level: The destination's mip level.

    Raises:
        Error: If either texture is blank, is refused by
            `Texture.validate` or has no such level, the texel types
            differ, the position has a layer, or the region is empty or
            reaches outside either level.
    """
    _check_level(source, source_level)
    _check_level(destination, destination_level)
    if source.texel_type != destination.texel_type:
        raise Error("A texture copy needs two textures of one texel type")
    if position.z != 0:
        raise Error("A 2D texture has no layers")
    var box = region.or_else(
        Rect(
            0,
            0,
            source.level_width(source_level),
            source.level_height(source_level),
        )
    )
    _check_place(
        box.x,
        box.y,
        box.width,
        box.height,
        source.level_width(source_level),
        source.level_height(source_level),
    )
    _check_place(
        position.x,
        position.y,
        box.width,
        box.height,
        destination.level_width(destination_level),
        destination.level_height(destination_level),
    )
    var floats = source.texel_type == FLOAT_TYPE
    for row in range(box.height):  # pragma: no branch
        var read = _texel_start(source, source_level, box.x, box.y + row)
        var write = _texel_start(
            destination, destination_level, position.x, position.y + row
        )
        for at in range(box.width * Texture.CHANNELS):  # pragma: no branch
            if floats:
                destination.data[write + at] = source.data[read + at]
            else:
                destination.pixels[write + at] = source.pixels[read + at]
    _regenerate(destination, destination_level)


def copy_texture_to_volume(
    source: Texture,
    mut destination: VolumeImage,
    region: Optional[Rect] = None,
    position: TexelPoint = TexelPoint(0, 0, 0),
    source_level: Int = 0,
) raises:
    """Copy a rectangle of a 2D texture into one layer of a volume:
    three.js's `copyTextureToTexture` with a 2D source and a
    `Data3DTexture` or `DataArrayTexture` destination. Pass the
    destination's `image`.

    Args:
        source: The texture to read.
        destination: The volume to write.
        region: The texels to copy, the corner at `v = 0`. The whole
            source level by default.
        position: Where the region's corner lands, and in which layer.
        source_level: The source's mip level.

    Raises:
        Error: If the source is blank, refused by `Texture.validate` or
            has no such level, the volume fails `VolumeImage.validate`,
            the texel types differ, or the region is empty or reaches
            outside either image.
    """
    _check_level(source, source_level)
    destination.validate()
    if source.texel_type != destination.texel_type:
        raise Error("A texture copy needs two textures of one texel type")
    var box = region.or_else(
        Rect(
            0,
            0,
            source.level_width(source_level),
            source.level_height(source_level),
        )
    )
    _check_place(
        box.x,
        box.y,
        box.width,
        box.height,
        source.level_width(source_level),
        source.level_height(source_level),
    )
    _check_place(
        position.x,
        position.y,
        box.width,
        box.height,
        destination.width,
        destination.height,
    )
    if position.z < 0 or position.z >= destination.depth:
        raise Error("A texture copy must lie inside both images")
    var floats = source.texel_type == FLOAT_TYPE
    for row in range(box.height):  # pragma: no branch
        var read = _texel_start(source, source_level, box.x, box.y + row)
        var write = (
            (position.z * destination.height + position.y + row)
            * destination.width
            + position.x
        ) * VOLUME_CHANNELS
        for at in range(box.width * VOLUME_CHANNELS):  # pragma: no branch
            if floats:
                destination.data[write + at] = source.data[read + at]
            else:
                destination.pixels[write + at] = source.pixels[read + at]


def copy_volume_to_volume(
    source: VolumeImage,
    mut destination: VolumeImage,
    region: Optional[TexelBox] = None,
    position: TexelPoint = TexelPoint(0, 0, 0),
) raises:
    """Copy a block of one volume into another: three.js's
    `copyTextureToTexture` between two `Data3DTexture`s or
    `DataArrayTexture`s, or one of each. Pass each texture's `image`.

    Args:
        source: The volume to read.
        destination: The volume to write.
        region: The texels to copy. The whole source by default.
        position: Where the block's corner lands.

    Raises:
        Error: If either volume fails `VolumeImage.validate`, the texel
            types differ, or the block is empty or reaches outside either
            volume.
    """
    source.validate()
    destination.validate()
    if source.texel_type != destination.texel_type:
        raise Error("A texture copy needs two textures of one texel type")
    var box = region.or_else(
        TexelBox(0, 0, 0, source.width, source.height, source.depth)
    )
    if (
        not box.is_valid()
        or box.z < 0
        or box.z + box.depth > source.depth
        or position.z < 0
        or position.z + box.depth > destination.depth
    ):
        raise Error("A texture copy must lie inside both images")
    _check_place(
        box.x, box.y, box.width, box.height, source.width, source.height
    )
    _check_place(
        position.x,
        position.y,
        box.width,
        box.height,
        destination.width,
        destination.height,
    )
    var floats = source.texel_type == FLOAT_TYPE
    for index in range(box.depth * box.height):  # pragma: no branch
        var layer = index // box.height
        var row = index % box.height
        var read = (
            ((box.z + layer) * source.height + box.y + row) * source.width
            + box.x
        ) * VOLUME_CHANNELS
        var write = (
            ((position.z + layer) * destination.height + position.y + row)
            * destination.width
            + position.x
        ) * VOLUME_CHANNELS
        for at in range(box.width * VOLUME_CHANNELS):  # pragma: no branch
            if floats:
                destination.data[write + at] = source.data[read + at]
            else:
                destination.pixels[write + at] = source.pixels[read + at]


def framebuffer_texture(
    width: Int,
    height: Int,
    texel_type: TexelType = UNSIGNED_BYTE_TYPE,
    color_space: ColorSpace = SRGB,
) raises -> Texture:
    """Return an empty texture a framebuffer is copied into: three.js's
    `new FramebufferTexture(width, height)`.

    Nearest, no chain and clamped, as three.js's is. Every texel starts
    transparent black until `copy_framebuffer_to_texture` fills it.

    Args:
        width: Width in texels.
        height: Height in texels.
        texel_type: `UNSIGNED_BYTE_TYPE` for a copy of a displayed image
            or of a byte target, `FLOAT_TYPE` for a copy of a float or
            half float target.
        color_space: How a byte texture's bytes are read. `SRGB`, the
            default, reads a displayed image back as the light it shows.
            A float texture must be `LINEAR`.

    Returns:
        The texture.

    Raises:
        Error: If a dimension is not positive, the texel type is none of
            the two, or `Texture.validate` refuses the color space.
    """
    if width <= 0 or height <= 0:
        raise Error("Texture dimensions must be positive")
    if not texel_type.is_valid():
        raise Error(
            "A texture's texel type must be UNSIGNED_BYTE_TYPE or FLOAT_TYPE"
        )
    if texel_type == FLOAT_TYPE:
        var image = float_texture(
            width,
            height,
            List[Float32](length=width * height * Texture.CHANNELS, fill=0),
            CLAMP,
            NEAREST,
        )
        image.color_space = color_space
        image.validate()
        return image^
    return Texture(
        width,
        height,
        List[UInt8](length=width * height * Texture.CHANNELS, fill=0),
        CLAMP,
        NEAREST,
        color_space,
        False,
    )


def _copy_region_start(
    texture: Texture, position: TexelPoint, level: Int, wide: Int, tall: Int
) raises -> Rect:
    """Return the framebuffer rectangle a copy into `level` reads, and
    refuse a copy that reaches outside the framebuffer."""
    _check_level(texture, level)
    if position.z != 0:
        raise Error("A 2D texture has no layers")
    var region = Rect(
        position.x,
        position.y,
        texture.level_width(level),
        texture.level_height(level),
    )
    _check_place(region.x, region.y, region.width, region.height, wide, tall)
    return region


def copy_framebuffer_to_texture(
    source: Framebuffer,
    mut texture: Texture,
    position: TexelPoint = TexelPoint(0, 0, 0),
    level: Int = 0,
) raises:
    """Copy a rectangle of a displayed image into a texture: three.js's
    `copyFramebufferToTexture(texture, position, level)` with the canvas
    bound.

    The rectangle is the size of the texture's level, its corner at
    `position`, counted up from the framebuffer's bottom left. Its bytes
    are copied as they are, sRGB, into a byte texture.

    Args:
        source: The displayed image, as `Renderer.render` or
            `GpuRenderer.read_back` returns it.
        texture: The texture to fill, a byte one.
        position: The framebuffer pixel the copy starts at. `z` must be
            zero.
        level: The texture's mip level to fill.

    Raises:
        Error: If the texture is blank, refused by `Texture.validate`, has
            no such level or holds floats, the position has a layer, or
            the rectangle reaches outside the framebuffer.
    """
    var region = _copy_region_start(
        texture, position, level, source.width, source.height
    )
    if texture.texel_type != UNSIGNED_BYTE_TYPE:
        raise Error("A displayed image is copied into a byte texture")
    for row in range(region.height):  # pragma: no branch
        # A framebuffer's rows are stored from the top.
        var read = (
            (source.height - 1 - (region.y + row)) * source.width + region.x
        ) * Framebuffer.CHANNELS
        var write = _texel_start(texture, level, 0, row)
        for at in range(region.width * Texture.CHANNELS):  # pragma: no branch
            texture.pixels[write + at] = source.pixels[read + at]
    _regenerate(texture, level)


def copy_framebuffer_to_texture(
    source: RenderTarget,
    mut texture: Texture,
    position: TexelPoint = TexelPoint(0, 0, 0),
    level: Int = 0,
) raises:
    """Copy a rectangle of a render target into a texture: three.js's
    `copyFramebufferToTexture(texture, position, level)` with a render
    target bound.

    The rectangle is the size of the texture's level, its corner at
    `position`, counted up from the target's bottom left. What is copied
    is `attachment(0)`: the light as the target's type stores it. A byte
    target fills a byte texture, and a half float or float one fills a
    float texture.

    Args:
        source: The render target.
        texture: The texture to fill.
        position: The target pixel the copy starts at. `z` must be zero.
        level: The texture's mip level to fill.

    Raises:
        Error: If the texture is blank, refused by `Texture.validate` or
            has no such level, its texel type does not match the target's
            type, the position has a layer, or the rectangle reaches
            outside the target.
    """
    var region = _copy_region_start(
        texture, position, level, source.width, source.height
    )
    var bytes = source.type == UNSIGNED_BYTE_TARGET
    if bytes != (texture.texel_type == UNSIGNED_BYTE_TYPE):
        raise Error(
            "A byte target fills a byte texture, and a float target a float one"
        )
    var light = source.attachment(0)
    for row in range(region.height):  # pragma: no branch
        var read = (
            (source.height - 1 - (region.y + row)) * source.width + region.x
        ) * Texture.CHANNELS
        var write = _texel_start(texture, level, 0, row)
        for at in range(region.width * Texture.CHANNELS):  # pragma: no branch
            var value = light.pixels[read + at]
            if bytes:
                texture.pixels[write + at] = UInt8(Int(value * 255 + 0.5))
            else:
                texture.data[write + at] = value
    _regenerate(texture, level)
