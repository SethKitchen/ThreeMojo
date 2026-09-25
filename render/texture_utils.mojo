# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fitting a texture to a surface, and the size of an image in bytes, from
three.js `src/extras/TextureUtils.js`.

`contain`, `cover` and `fill` are CSS's `object-fit` for a texture. Each
sets the texture's `repeat` and `offset` so that the image keeps its own
aspect ratio on a surface of another. `contain` shows the whole image and
leaves bands beside it; `cover` fills the surface and crops the image;
`fill` stretches the image to the surface. The texture's texels do not
change.

`byte_length` is three.js's `getByteLength`: how many bytes an image of a
size, a format and a data type takes in GPU memory. It needs three.js's
format and type constants, which are `TextureFormat` and `TextureDataType`
here, with three.js's numbers as their values. The answer is a `Float64`
because three.js's is not always a whole number: a red image of
four-bit texels packed four to a short has half a byte for a single
texel, and three.js says so.

Two differences from three.js. A width or a height below zero, and an
aspect ratio that is not a positive finite number, are refused. three.js
takes them and gives numbers that are not a size or a fit.
"""

from render.texture import Texture
from std.math import isfinite


@fieldwise_init
struct TextureFormat(Equatable, ImplicitlyCopyable, Writable):
    """What channels an image holds and how it is packed, three.js's
    `Texture.format`, as a type rather than a bare int.

    The value is three.js's number for the format in `constants.js`, so a
    number read from three.js's JSON is a `TextureFormat` as it is. The
    type does not stop `TextureFormat(7)`, so `byte_length` asks
    `is_valid`.
    """

    var value: Int

    # One channel, alpha only: three.js's `AlphaFormat`.
    comptime ALPHA = TextureFormat(1021)
    # Red, green and blue: `RGBFormat`.
    comptime RGB = TextureFormat(1022)
    # Red, green, blue and alpha: `RGBAFormat`.
    comptime RGBA = TextureFormat(1023)
    # Red only: `RedFormat`.
    comptime RED = TextureFormat(1028)
    # Red only, read as an integer: `RedIntegerFormat`.
    comptime RED_INTEGER = TextureFormat(1029)
    # Red and green: `RGFormat`.
    comptime RG = TextureFormat(1030)
    # Red and green, read as integers: `RGIntegerFormat`.
    comptime RG_INTEGER = TextureFormat(1031)
    # All four, read as integers: `RGBAIntegerFormat`.
    comptime RGBA_INTEGER = TextureFormat(1033)
    # The S3TC block formats: `RGB_S3TC_DXT1_Format` and the next three.
    comptime RGB_S3TC_DXT1 = TextureFormat(33776)
    comptime RGBA_S3TC_DXT1 = TextureFormat(33777)
    comptime RGBA_S3TC_DXT3 = TextureFormat(33778)
    comptime RGBA_S3TC_DXT5 = TextureFormat(33779)
    # The PVRTC formats: `RGB_PVRTC_4BPPV1_Format` and the next three.
    comptime RGB_PVRTC_4BPPV1 = TextureFormat(35840)
    comptime RGB_PVRTC_2BPPV1 = TextureFormat(35841)
    comptime RGBA_PVRTC_4BPPV1 = TextureFormat(35842)
    comptime RGBA_PVRTC_2BPPV1 = TextureFormat(35843)
    # ETC1: `RGB_ETC1_Format`.
    comptime RGB_ETC1 = TextureFormat(36196)
    # ETC2: `RGB_ETC2_Format` and `RGBA_ETC2_EAC_Format`.
    comptime RGB_ETC2 = TextureFormat(37492)
    comptime RGBA_ETC2_EAC = TextureFormat(37496)
    # The fourteen ASTC block sizes: `RGBA_ASTC_4x4_Format` to
    # `RGBA_ASTC_12x12_Format`.
    comptime RGBA_ASTC_4X4 = TextureFormat(37808)
    comptime RGBA_ASTC_5X4 = TextureFormat(37809)
    comptime RGBA_ASTC_5X5 = TextureFormat(37810)
    comptime RGBA_ASTC_6X5 = TextureFormat(37811)
    comptime RGBA_ASTC_6X6 = TextureFormat(37812)
    comptime RGBA_ASTC_8X5 = TextureFormat(37813)
    comptime RGBA_ASTC_8X6 = TextureFormat(37814)
    comptime RGBA_ASTC_8X8 = TextureFormat(37815)
    comptime RGBA_ASTC_10X5 = TextureFormat(37816)
    comptime RGBA_ASTC_10X6 = TextureFormat(37817)
    comptime RGBA_ASTC_10X8 = TextureFormat(37818)
    comptime RGBA_ASTC_10X10 = TextureFormat(37819)
    comptime RGBA_ASTC_12X10 = TextureFormat(37820)
    comptime RGBA_ASTC_12X12 = TextureFormat(37821)
    # BPTC: `RGBA_BPTC_Format`, `RGB_BPTC_SIGNED_Format` and
    # `RGB_BPTC_UNSIGNED_Format`.
    comptime RGBA_BPTC = TextureFormat(36492)
    comptime RGB_BPTC_SIGNED = TextureFormat(36494)
    comptime RGB_BPTC_UNSIGNED = TextureFormat(36495)
    # RGTC: `RED_RGTC1_Format` and the next three.
    comptime RED_RGTC1 = TextureFormat(36283)
    comptime SIGNED_RED_RGTC1 = TextureFormat(36284)
    comptime RED_GREEN_RGTC2 = TextureFormat(36285)
    comptime SIGNED_RED_GREEN_RGTC2 = TextureFormat(36286)

    def is_valid(self) -> Bool:
        """Return True if this is one of the forty formats three.js's
        `getByteLength` knows."""
        return self.channels() > 0 or self.block_bytes() > 0 or self.is_pvrtc()

    def channels(self) -> Int:
        """Return how many channels an uncompressed format holds, or zero
        for a block format or a value that is no format."""
        if self == Self.ALPHA or self == Self.RED or self == Self.RED_INTEGER:
            return 1
        if self == Self.RG or self == Self.RG_INTEGER:
            return 2
        if self == Self.RGB:
            return 3
        if self == Self.RGBA or self == Self.RGBA_INTEGER:
            return 4
        return 0

    def block_width(self) -> Int:
        """Return how many texels wide one block of a block format is:
        four, except for the ASTC sizes, whose name says it."""
        var widths: List[Int] = [4, 5, 5, 6, 6, 8, 8, 8, 10, 10, 10, 10, 12, 12]
        var at = self.value - Self.RGBA_ASTC_4X4.value
        return widths[at] if at >= 0 and at < 14 else 4

    def block_height(self) -> Int:
        """Return how many texels high one block of a block format is:
        four, except for the ASTC sizes, whose name says it."""
        var heights: List[Int] = [4, 4, 5, 5, 6, 5, 6, 8, 5, 6, 8, 10, 10, 12]
        var at = self.value - Self.RGBA_ASTC_4X4.value
        return heights[at] if at >= 0 and at < 14 else 4

    def block_bytes(self) -> Int:
        """Return how many bytes one block of a block format takes, or
        zero for an uncompressed format, a PVRTC format and a value that
        is no format. PVRTC has no blocks in three.js's arithmetic."""
        if (
            self == Self.RGB_S3TC_DXT1
            or self == Self.RGBA_S3TC_DXT1
            or self == Self.RGB_ETC1
            or self == Self.RGB_ETC2
            or self == Self.RED_RGTC1
            or self == Self.SIGNED_RED_RGTC1
        ):
            return 8
        if (
            self == Self.RGBA_S3TC_DXT3
            or self == Self.RGBA_S3TC_DXT5
            or self == Self.RGBA_ETC2_EAC
            or self == Self.RGBA_BPTC
            or self == Self.RGB_BPTC_SIGNED
            or self == Self.RGB_BPTC_UNSIGNED
            or self == Self.RED_GREEN_RGTC2
            or self == Self.SIGNED_RED_GREEN_RGTC2
            or (
                self.value >= Self.RGBA_ASTC_4X4.value
                and self.value <= Self.RGBA_ASTC_12X12.value
            )
        ):
            return 16
        return 0

    def is_pvrtc(self) -> Bool:
        """Return True for the four PVRTC formats."""
        return (
            self.value >= Self.RGB_PVRTC_4BPPV1.value
            and self.value <= Self.RGBA_PVRTC_2BPPV1.value
        )

    def write_to(self, mut writer: Some[Writer]):
        """Write the format's number, as three.js's `constants.js` has it.

        Args:
            writer: Where to write it.
        """
        writer.write("TextureFormat(", self.value, ")")


@fieldwise_init
struct TextureDataType(Equatable, ImplicitlyCopyable, Writable):
    """What one texel's numbers are stored as, three.js's `Texture.type`,
    as a type rather than a bare int.

    The value is three.js's number for the type in `constants.js`. The
    type does not stop `TextureDataType(7)`, so `byte_length` asks
    `is_valid`. `render.texture.TexelType` is the narrower choice this
    renderer samples from.
    """

    var value: Int

    # One byte a channel: three.js's `UnsignedByteType` and `ByteType`.
    comptime UNSIGNED_BYTE = TextureDataType(1009)
    comptime BYTE = TextureDataType(1010)
    # Two bytes a channel: `ShortType`, `UnsignedShortType`.
    comptime SHORT = TextureDataType(1011)
    comptime UNSIGNED_SHORT = TextureDataType(1012)
    # Four bytes a channel: `IntType`, `UnsignedIntType`, `FloatType`.
    comptime INT = TextureDataType(1013)
    comptime UNSIGNED_INT = TextureDataType(1014)
    comptime FLOAT = TextureDataType(1015)
    # Two bytes a channel, a half float: `HalfFloatType`.
    comptime HALF_FLOAT = TextureDataType(1016)
    # Four channels packed in two bytes: `UnsignedShort4444Type` and
    # `UnsignedShort5551Type`.
    comptime UNSIGNED_SHORT_4444 = TextureDataType(1017)
    comptime UNSIGNED_SHORT_5551 = TextureDataType(1018)
    # Depth and stencil packed in four bytes: `UnsignedInt248Type`. A
    # real type that `getByteLength` does not know, so `byte_length`
    # refuses it as three.js throws for it.
    comptime UNSIGNED_INT_248 = TextureDataType(1020)
    # Three channels packed in four bytes: `UnsignedInt101111Type` and
    # `UnsignedInt5999Type`.
    comptime UNSIGNED_INT_101111 = TextureDataType(35899)
    comptime UNSIGNED_INT_5999 = TextureDataType(35902)

    def is_valid(self) -> Bool:
        """Return True if this is one of three.js's thirteen texture
        types."""
        return (
            (
                self.value >= Self.UNSIGNED_BYTE.value
                and self.value <= Self.UNSIGNED_SHORT_5551.value
            )
            or self == Self.UNSIGNED_INT_248
            or self == Self.UNSIGNED_INT_101111
            or self == Self.UNSIGNED_INT_5999
        )

    def write_to(self, mut writer: Some[Writer]):
        """Write the type's number, as three.js's `constants.js` has it.

        Args:
            writer: Where to write it.
        """
        writer.write("TextureDataType(", self.value, ")")


def _image_aspect(texture: Texture) -> Float64:
    """Return a texture's width over its height, or one for the blank
    texture, which has no image, as three.js's `imageAspect`."""
    if texture.width == 0:
        return 1
    return Float64(texture.width) / Float64(texture.height)


def _check_aspect(aspect: Float64) raises:
    """Refuse an aspect ratio that is not a positive finite number."""
    if not isfinite(aspect) or aspect <= 0:
        raise Error("An aspect ratio must be a positive finite number")


def _place(
    mut texture: Texture,
    repeat_x: Float64,
    repeat_y: Float64,
    offset_x: Float64,
    offset_y: Float64,
):
    """Set a texture's repeat and offset, each rounded to a `Float32`
    once."""
    texture.repeat.x = Float32(repeat_x)
    texture.repeat.y = Float32(repeat_y)
    texture.offset.x = Float32(offset_x)
    texture.offset.y = Float32(offset_y)


def contain(mut texture: Texture, aspect: Float64) raises:
    """Fit the whole image on a surface, three.js's `TextureUtils.contain`.

    The image keeps its aspect ratio and is centered. The surface shows
    the edge texels beside it, as the texture's wrap resolves them.

    Args:
        texture: The texture. Its `repeat` and `offset` are set.
        aspect: The surface's width over its height.

    Raises:
        Error: If `aspect` is not a positive finite number. The texture is
            left as it was.
    """
    _check_aspect(aspect)
    var image = _image_aspect(texture)
    if image > aspect:
        var repeat = image / aspect
        _place(texture, 1, repeat, 0, (1 - repeat) / 2)
    else:
        var repeat = aspect / image
        _place(texture, repeat, 1, (1 - repeat) / 2, 0)


def cover(mut texture: Texture, aspect: Float64) raises:
    """Fill a surface with the image, three.js's `TextureUtils.cover`.

    The image keeps its aspect ratio and is centered. What does not fit is
    cropped.

    Args:
        texture: The texture. Its `repeat` and `offset` are set.
        aspect: The surface's width over its height.

    Raises:
        Error: If `aspect` is not a positive finite number. The texture is
            left as it was.
    """
    _check_aspect(aspect)
    var image = _image_aspect(texture)
    if image > aspect:
        var repeat = aspect / image
        _place(texture, repeat, 1, (1 - repeat) / 2, 0)
    else:
        var repeat = image / aspect
        _place(texture, 1, repeat, 0, (1 - repeat) / 2)


def fill(mut texture: Texture):
    """Stretch the image over a surface, three.js's `TextureUtils.fill`: a
    repeat of one and no offset.

    Args:
        texture: The texture. Its `repeat` and `offset` are set.
    """
    _place(texture, 1, 1, 0, 0)


def _type_bytes(type: TextureDataType) raises -> Float64:
    """Return how many bytes a type packs its channels into, three.js's
    `getTextureTypeByteLength().byteLength`."""
    if type == TextureDataType.UNSIGNED_BYTE or type == TextureDataType.BYTE:
        return 1
    if (
        type == TextureDataType.SHORT
        or type == TextureDataType.UNSIGNED_SHORT
        or type == TextureDataType.HALF_FLOAT
        or type == TextureDataType.UNSIGNED_SHORT_4444
        or type == TextureDataType.UNSIGNED_SHORT_5551
    ):
        return 2
    if type == TextureDataType.UNSIGNED_INT_248:
        raise Error("A texture of UnsignedInt248Type has no byte length")
    return 4


def _type_components(type: TextureDataType) -> Float64:
    """Return how many channels a type packs into its bytes, three.js's
    `getTextureTypeByteLength().components`."""
    if (
        type == TextureDataType.UNSIGNED_SHORT_4444
        or type == TextureDataType.UNSIGNED_SHORT_5551
    ):
        return 4
    if (
        type == TextureDataType.UNSIGNED_INT_101111
        or type == TextureDataType.UNSIGNED_INT_5999
    ):
        return 3
    return 1


def byte_length(
    width: Int, height: Int, format: TextureFormat, type: TextureDataType
) raises -> Float64:
    """Return how many bytes an image takes, three.js's
    `TextureUtils.getByteLength`.

    An uncompressed image is its texels times its channels, over the
    channels the type packs together, times the bytes it packs them in.
    A block format is its blocks times the bytes a block takes, a partial
    block counted whole. PVRTC is three.js's formula for its two and four
    bits a texel, with its smallest sizes. `AlphaFormat` counts one byte a
    texel whatever the type, as three.js does.

    Args:
        width: The image's width in texels.
        height: The image's height in texels.
        format: What the image holds.
        type: What each texel's numbers are stored as. It is checked for
            every format, as three.js checks it first.

    Returns:
        The bytes, not always a whole number, as three.js's are not.

    Raises:
        Error: If the width or the height is below zero, the format or the
            type is not one of its named values, or the type is
            `UNSIGNED_INT_248`, which three.js's `getByteLength` does not
            know.
    """
    if width < 0 or height < 0:
        raise Error("An image's width and height cannot be negative")
    if not format.is_valid():
        raise Error("Unable to determine texture byte length for this format")
    if not type.is_valid():
        raise Error("A texture's data type must be one of three.js's")
    var bytes = _type_bytes(type)
    var components = _type_components(type)
    var texels = width * height
    if format == TextureFormat.ALPHA:
        return Float64(texels)
    var channels = format.channels()
    if channels > 0:
        return Float64(texels * channels) / components * bytes
    if format.is_pvrtc():
        var two_bits = (
            format == TextureFormat.RGB_PVRTC_2BPPV1
            or format == TextureFormat.RGBA_PVRTC_2BPPV1
        )
        if two_bits:
            return Float64(max(width, 16) * max(height, 8)) / 4
        return Float64(max(width, 8) * max(height, 8)) / 2
    var across = (width + format.block_width() - 1) // format.block_width()
    var down = (height + format.block_height() - 1) // format.block_height()
    return Float64(across * down * format.block_bytes())
