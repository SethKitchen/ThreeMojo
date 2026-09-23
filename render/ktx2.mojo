# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A KTX 2.0 file read into its levels, from three.js
`examples/jsm/loaders/KTX2Loader.js` and the Khronos KTX 2.0
specification.

`read(bytes)` returns a `KTX2Container`: the header, what the data format
descriptor says about color, and every level's bytes with any
supercompression removed. `KTX2Container.texture` decodes one level of
one face of one layer into a `Texture`.

**The header.** Twelve identifier bytes, then nine little-endian words:
the Vulkan format, the type size, the width, height and depth, the layer,
face and level counts, and the supercompression scheme. An index follows
with where the data format descriptor, the key and value data and the
supercompression global data are. Then comes the level index: for each
level, where its bytes are, how many there are, and how many there are
once decompressed.

**The data format descriptor.** A basic descriptor block names the color
model, the primaries, the transfer function and the flags. three.js reads
the transfer function to pick the color space, `SRGB` for the sRGB
transfer and `LINEAR` otherwise, and so does this reader. The color model
says whether the data is Basis Universal.

**The levels.** Each level holds every layer, then every face, then every
depth slice, of that level's size. A level is stored whole, or
compressed whole by the supercompression scheme.

| Scheme | Here |
|---|---|
| 0, none | Read. |
| 1, BasisLZ | Read for ETC1S data, through `render.etc1s`. |
| 2, Zstandard | Read, through `render.zstd`. |
| 3, zlib | Read, through `render.inflate`. three.js refuses it. |

**Basis Universal.** A file whose color model is UASTC or ETC1S names no
Vulkan format. three.js transcodes its data to whatever the GPU takes
with the Basis Universal WebAssembly transcoder. Here `texture` decodes
it to RGBA bytes, the texels that transcoder gives for its `RGBA32`
target: UASTC through `render.uastc`, and ETC1S, which BasisLZ always
stores, through `render.etc1s`. UASTC HDR is not ported. The Vulkan
formats read are in `VkFormat`.
"""

from render.compressed_texture import (
    R11_EAC_FORMAT,
    RED_GREEN_RGTC2_FORMAT,
    RED_RGTC1_FORMAT,
    RG11_EAC_FORMAT,
    RGB_BPTC_SIGNED_FORMAT,
    RGB_BPTC_UNSIGNED_FORMAT,
    RGB_ETC2_FORMAT,
    RGB_S3TC_DXT1_FORMAT,
    RGBA_BPTC_FORMAT,
    RGBA_ETC2_EAC_FORMAT,
    RGBA_S3TC_DXT1_FORMAT,
    RGBA_S3TC_DXT3_FORMAT,
    RGBA_S3TC_DXT5_FORMAT,
    SIGNED_R11_EAC_FORMAT,
    SIGNED_RED_GREEN_RGTC2_FORMAT,
    SIGNED_RED_RGTC1_FORMAT,
    SIGNED_RG11_EAC_FORMAT,
    CompressedFormat,
    chain_length,
    check_decoded_size,
    compressed_texture,
    level_bytes,
)
from render.etc1s import Etc1sGlobal, etc1s_image
from render.exr import half_to_float
from render.inflate import zlib_inflate
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    Alpha,
    Filter,
    Texture,
    Wrap,
    float_from_bytes,
    float_texture,
)
from render.uastc import UASTC_BLOCK_BYTES, uastc_image
from render.zstd import zstd_decompress

# The identifier, nine header words and the index.
comptime HEADER_BYTES = 80
# A level index entry: three eight-byte numbers.
comptime LEVEL_ENTRY_BYTES = 24
# The data format descriptor's color models for Basis Universal data.
comptime KHR_DF_MODEL_ETC1S = 163
comptime KHR_DF_MODEL_UASTC = 166
# The size of a basic descriptor block with one sample; each more sample
# adds sixteen bytes.
comptime ONE_SAMPLE_BLOCK_BYTES = 40
# The transfer function that means sRGB.
comptime KHR_DF_TRANSFER_SRGB = 2
# The flag that means the color is premultiplied by alpha.
comptime KHR_DF_FLAG_ALPHA_PREMULTIPLIED = 1


@fieldwise_init
struct VkFormat(Equatable, ImplicitlyCopyable, Writable):
    """A KTX 2.0 file's Vulkan format number, as a type rather than a bare
    int.

    `is_valid` is True for the formats this reader decodes: the
    block-compressed BC1 to BC7, ETC2 and EAC formats, and the
    uncompressed eight-bit, half and float formats three.js reads.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this reader decodes the format."""
        return self.is_uncompressed() or (
            self.value >= 131
            and self.value <= 156
            and self.value != 149
            and self.value != 150
        )

    def is_uncompressed(self) -> Bool:
        """Return True for an uncompressed format this reader decodes."""
        return self.channels() > 0

    def channels(self) -> Int:
        """Return how many channels an uncompressed format stores, or zero
        for any other number."""
        if self == VK_R8_UNORM or self == VK_R8_SRGB:
            return 1
        if self == VK_R8G8_UNORM or self == VK_R8G8_SRGB:
            return 2
        if self == VK_R8G8B8A8_UNORM or self == VK_R8G8B8A8_SRGB:
            return 4
        if self == VK_R16_SFLOAT or self == VK_R32_SFLOAT:
            return 1
        if self == VK_R16G16_SFLOAT or self == VK_R32G32_SFLOAT:
            return 2
        if self == VK_R16G16B16A16_SFLOAT or self == VK_R32G32B32A32_SFLOAT:
            return 4
        return 0

    def channel_bytes(self) -> Int:
        """Return how many bytes one channel of an uncompressed format
        takes: one, two for a half or four for a float."""
        if self.value >= 100:
            return 4
        if self.value >= 76:
            return 2
        return 1

    def write_to(self, mut writer: Some[Writer]):
        """Write the format's number.

        Args:
            writer: Where to write it.
        """
        writer.write("VkFormat(", self.value, ")")


# The uncompressed formats three.js's KTX2Loader reads.
comptime VK_R8_UNORM = VkFormat(9)
comptime VK_R8_SRGB = VkFormat(15)
comptime VK_R8G8_UNORM = VkFormat(16)
comptime VK_R8G8_SRGB = VkFormat(22)
comptime VK_R8G8B8A8_UNORM = VkFormat(37)
comptime VK_R8G8B8A8_SRGB = VkFormat(43)
comptime VK_R16_SFLOAT = VkFormat(76)
comptime VK_R16G16_SFLOAT = VkFormat(83)
comptime VK_R16G16B16A16_SFLOAT = VkFormat(97)
comptime VK_R32_SFLOAT = VkFormat(100)
comptime VK_R32G32_SFLOAT = VkFormat(103)
comptime VK_R32G32B32A32_SFLOAT = VkFormat(109)
# The number a Basis Universal file stores: no Vulkan format.
comptime VK_FORMAT_UNDEFINED = VkFormat(0)


def compressed_format_of(format: VkFormat) raises -> CompressedFormat:
    """Return the block layout a block-compressed Vulkan format names.

    Args:
        format: A block-compressed Vulkan format, 131 to 156.

    Returns:
        The layout. A format's sRGB and UNORM forms name the same one.

    Raises:
        Error: If the format is not a block-compressed one this reader
            decodes.
    """
    var layouts: List[CompressedFormat] = [
        RGB_S3TC_DXT1_FORMAT,
        RGB_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT3_FORMAT,
        RGBA_S3TC_DXT3_FORMAT,
        RGBA_S3TC_DXT5_FORMAT,
        RGBA_S3TC_DXT5_FORMAT,
        RED_RGTC1_FORMAT,
        SIGNED_RED_RGTC1_FORMAT,
        RED_GREEN_RGTC2_FORMAT,
        SIGNED_RED_GREEN_RGTC2_FORMAT,
        RGB_BPTC_UNSIGNED_FORMAT,
        RGB_BPTC_SIGNED_FORMAT,
        RGBA_BPTC_FORMAT,
        RGBA_BPTC_FORMAT,
        RGB_ETC2_FORMAT,
        RGB_ETC2_FORMAT,
        # 149 and 150, ETC2 with punch-through alpha, are refused below.
        RGB_ETC2_FORMAT,
        RGB_ETC2_FORMAT,
        RGBA_ETC2_EAC_FORMAT,
        RGBA_ETC2_EAC_FORMAT,
        R11_EAC_FORMAT,
        SIGNED_R11_EAC_FORMAT,
        RG11_EAC_FORMAT,
        SIGNED_RG11_EAC_FORMAT,
    ]
    if not format.is_valid() or format.is_uncompressed():
        raise Error(
            "KTX2: "
            + String(format)
            + " is not a block format this reader decodes"
        )
    return layouts[format.value - 131]


@fieldwise_init
struct Supercompression(Equatable, ImplicitlyCopyable, Writable):
    """A KTX 2.0 file's supercompression scheme, as a type rather than a
    bare int.

    `is_valid` is True for the four schemes the specification defines.
    This reader reads `NO_SUPERCOMPRESSION` and `ZLIB_SUPERCOMPRESSION`
    and refuses the other two by name.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the specification defines the scheme."""
        return self.value >= 0 and self.value <= 3

    def write_to(self, mut writer: Some[Writer]):
        """Write the scheme's name.

        Args:
            writer: Where to write it.
        """
        var names: List[String] = ["none", "BasisLZ", "Zstandard", "zlib"]
        if self.is_valid():
            writer.write(names[self.value])
        else:
            writer.write("Supercompression(", self.value, ")")


comptime NO_SUPERCOMPRESSION = Supercompression(0)
comptime BASISLZ_SUPERCOMPRESSION = Supercompression(1)
comptime ZSTD_SUPERCOMPRESSION = Supercompression(2)
comptime ZLIB_SUPERCOMPRESSION = Supercompression(3)


def identifier() -> List[UInt8]:
    """Return the twelve bytes every KTX 2.0 file starts with, «KTX 20».

    Returns:
        The identifier.
    """
    return [
        0xAB,
        0x4B,
        0x54,
        0x58,
        0x20,
        0x32,
        0x30,
        0xBB,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
    ]


def _u32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian word at `at`; the caller has checked the
    length."""
    return (
        Int(bytes[at])
        | (Int(bytes[at + 1]) << 8)
        | (Int(bytes[at + 2]) << 16)
        | (Int(bytes[at + 3]) << 24)
    )


def _u64(bytes: List[UInt8], at: Int) raises -> Int:
    """Return the little-endian eight-byte number at `at`, refusing one
    past the top of an `Int`; the caller has checked the length."""
    if bytes[at + 7] >= 0x80:
        raise Error("KTX2: an offset or a length is too large")
    return _u32(bytes, at) | (_u32(bytes, at + 4) << 32)


def _outside(offset: Int, length: Int, size: Int) -> Bool:
    """Return True if `length` bytes from `offset` do not fit in `size`."""
    return offset > size or length > size - offset


struct KTX2Container(Movable):
    """A KTX 2.0 file's header, color information and levels.

    three.js's `KTX2Container` from `ktx-parse`, reduced to what a decode
    reads. `level_data[level]` holds every layer and face of a level,
    decompressed.
    """

    var vk_format: VkFormat
    """The Vulkan format."""
    var width: Int
    """The first level's width in texels."""
    var height: Int
    """Its height."""
    var layers: Int
    """How many array layers: one for a file that is not an array."""
    var faces: Int
    """Six for a cube, one otherwise."""
    var levels: Int
    """How many levels there are."""
    var supercompression: Supercompression
    """How the file stored its levels."""
    var color_model: Int
    """The data format descriptor's color model."""
    var transfer_function: Int
    """The data format descriptor's transfer function."""
    var premultiplied: Bool
    """Whether the descriptor says color is premultiplied by alpha."""
    var color_space: ColorSpace
    """`SRGB` if the transfer function is sRGB's, `LINEAR` otherwise."""
    var has_alpha: Bool
    """Whether the descriptor has more than one sample: for ETC1S, an
    alpha slice per image."""
    var level_data: List[List[UInt8]]
    """Each level's bytes, largest first, decompressed. For ETC1S, the
    BasisLZ slices of the level."""
    var etc1s: Etc1sGlobal
    """The decoded BasisLZ global data of an ETC1S file; empty otherwise."""

    def __init__(out self):
        """Make an empty container, for `read` to fill."""
        self.vk_format = VK_FORMAT_UNDEFINED
        self.width = 0
        self.height = 0
        self.layers = 1
        self.faces = 1
        self.levels = 1
        self.supercompression = NO_SUPERCOMPRESSION
        self.color_model = 0
        self.transfer_function = 0
        self.premultiplied = False
        self.color_space = LINEAR
        self.has_alpha = False
        self.level_data = List[List[UInt8]]()
        self.etc1s = Etc1sGlobal()

    def is_uastc(self) -> Bool:
        """Return True if the data is Basis Universal UASTC.

        Returns:
            True for the UASTC color model.
        """
        return self.color_model == KHR_DF_MODEL_UASTC

    def is_etc1s(self) -> Bool:
        """Return True if the data is Basis Universal ETC1S.

        Returns:
            True for the ETC1S color model.
        """
        return self.color_model == KHR_DF_MODEL_ETC1S

    def level_width(self, level: Int) -> Int:
        """Return a level's width: halved per level, never below one.

        Args:
            level: The level, zero the largest.

        Returns:
            The width in texels.
        """
        return max(1, self.width >> level)

    def level_height(self, level: Int) -> Int:
        """Return a level's height: halved per level, never below one.

        Args:
            level: The level, zero the largest.

        Returns:
            The height in texels.
        """
        return max(1, self.height >> level)

    def decodes_to_floats(self) -> Bool:
        """Return True if the format decodes to floats rather than bytes.

        Returns:
            True for a half or float format, BC6H, the signed RGTC forms
            and the eleven-bit EAC forms.
        """
        if self.vk_format.is_uncompressed():
            return self.vk_format.channel_bytes() > 1
        # 139 to 144 are BC4 to BC6H, and 153 to 156 are EAC R11 and RG11:
        # all but the unsigned BC4 and BC5 decode to floats.
        return (
            self.vk_format == VkFormat(140)
            or self.vk_format == VkFormat(142)
            or self.vk_format == VkFormat(143)
            or self.vk_format == VkFormat(144)
            or (self.vk_format.value >= 153 and self.vk_format.value <= 156)
        )

    def image_bytes(self, level: Int) raises -> Int:
        """Return how many bytes one face of one layer of a level takes.

        Args:
            level: The level, zero the largest.

        Returns:
            The size in bytes. For UASTC, sixteen bytes a 4x4 block.

        Raises:
            Error: If the format is not one this reader decodes.
        """
        var width = self.level_width(level)
        var height = self.level_height(level)
        if self.is_uastc():
            return (width + 3) // 4 * ((height + 3) // 4) * UASTC_BLOCK_BYTES
        if self.vk_format.is_uncompressed():
            return (
                width
                * height
                * self.vk_format.channels()
                * self.vk_format.channel_bytes()
            )
        return level_bytes(width, height, compressed_format_of(self.vk_format))

    def texture(
        self,
        face: Int = 0,
        layer: Int = 0,
        level: Int = 0,
        wrap: Wrap = CLAMP,
        filter: Filter = BILINEAR,
        mipmapped: Bool = False,
        alpha: Alpha = COVERAGE,
    ) raises -> Texture:
        """Return one level of one face of one layer as a texture, in the
        file's color space.

        UASTC and ETC1S data decode to a byte texture, as the Basis
        Universal transcoder decodes them to RGBA32. A block format
        decodes through `compressed_texture`. An eight-bit
        format gives a byte texture, and a half or float format a float
        texture. A channel the format does not store is zero, and alpha
        is one, as WebGL samples a red or a red-green texture.

        Args:
            face: Zero, or up to five for a cube: +x, -x, +y, -y, +z, -z.
            layer: Which array layer.
            level: Which level, zero the largest.
            wrap: How coordinates outside the unit square are resolved.
            filter: `NEAREST` or `BILINEAR`.
            mipmapped: Build the chain of halved copies from this level.
            alpha: `COVERAGE` or `IGNORED`; see `render.texture`.

        Returns:
            The texture.

        Raises:
            Error: If there is no such face, layer or level; a half or
                float format is not `LINEAR`, or holds an infinity or a
                NaN; a UASTC or ETC1S image is malformed; and everything
                `compressed_texture` raises.
        """
        if face < 0 or face >= self.faces:
            raise Error("KTX2: this file has no face " + String(face))
        if layer < 0 or layer >= self.layers:
            raise Error("KTX2: this file has no layer " + String(layer))
        if level < 0 or level >= self.levels:
            raise Error("KTX2: this file has no level " + String(level))
        var width = self.level_width(level)
        var height = self.level_height(level)
        if self.is_etc1s():
            var image = (level * self.layers + layer) * self.faces + face
            return Texture(
                width,
                height,
                etc1s_image(
                    self.etc1s,
                    image,
                    self.level_data[level],
                    width,
                    height,
                    self.has_alpha,
                ),
                wrap,
                filter,
                self.color_space,
                mipmapped,
                alpha,
            )
        var size = self.image_bytes(level)
        var start = (layer * self.faces + face) * size
        var bytes = List[UInt8](self.level_data[level][start : start + size])
        if self.is_uastc():
            return Texture(
                width,
                height,
                uastc_image(width, height, bytes),
                wrap,
                filter,
                self.color_space,
                mipmapped,
                alpha,
            )
        if not self.vk_format.is_uncompressed():
            return compressed_texture(
                width,
                height,
                bytes,
                compressed_format_of(self.vk_format),
                wrap,
                filter,
                self.color_space,
                mipmapped,
                alpha,
            )
        var channels = self.vk_format.channels()
        var stride = self.vk_format.channel_bytes()
        if stride == 1:
            var pixels = List[UInt8](length=width * height * 4, fill=0)
            for texel in range(width * height):  # pragma: no branch
                pixels[texel * 4 + 3] = 255
                for channel in range(channels):  # pragma: no branch
                    pixels[texel * 4 + channel] = bytes[
                        texel * channels + channel
                    ]
            return Texture(
                width,
                height,
                pixels^,
                wrap,
                filter,
                self.color_space,
                mipmapped,
                alpha,
            )
        if self.color_space != LINEAR:
            raise Error(
                "KTX2: a half or float format holds linear light; its"
                " transfer function must not be sRGB"
            )
        var floats = List[Float32](length=width * height * 4, fill=0)
        for texel in range(width * height):  # pragma: no branch
            floats[texel * 4 + 3] = 1
            for channel in range(channels):  # pragma: no branch
                var at = (texel * channels + channel) * stride
                if stride == 2:
                    floats[texel * 4 + channel] = half_to_float(
                        UInt16(bytes[at]) | (UInt16(bytes[at + 1]) << 8)
                    )
                else:
                    floats[texel * 4 + channel] = float_from_bytes(
                        bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]
                    )
        return float_texture(
            width, height, floats^, wrap, filter, mipmapped, alpha
        )


def _read_descriptor(bytes: List[UInt8], mut container: KTX2Container) raises:
    """Read the basic block of the data format descriptor.

    Args:
        bytes: The whole file.
        container: Where to put the color model, the transfer function,
            the premultiplied flag and the color space.

    Raises:
        Error: If the descriptor does not fit in the file, or is shorter
            than a basic block.
    """
    var offset = _u32(bytes, 48)
    var length = _u32(bytes, 52)
    # The total size word, then the basic block's first six words.
    if length < 28 or _outside(offset, length, len(bytes)):
        raise Error("KTX2: the data format descriptor is missing or cut short")
    container.color_model = Int(bytes[offset + 12])
    container.transfer_function = Int(bytes[offset + 14])
    container.premultiplied = (
        Int(bytes[offset + 15]) & KHR_DF_FLAG_ALPHA_PREMULTIPLIED
    ) != 0
    if container.transfer_function == KHR_DF_TRANSFER_SRGB:
        container.color_space = SRGB
    # The descriptor block's size, after its vendor and type word and its
    # version.
    container.has_alpha = (
        Int(bytes[offset + 10]) | (Int(bytes[offset + 11]) << 8)
    ) > ONE_SAMPLE_BLOCK_BYTES


def read(bytes: List[UInt8]) raises -> KTX2Container:
    """Return a KTX 2.0 file's header, color information and levels.

    Args:
        bytes: The whole file.

    Returns:
        The container; see `KTX2Container`.

    Raises:
        Error: If the identifier is wrong; its Vulkan format or
            supercompression scheme is one this reader does not decode;
            Basis Universal data names a Vulkan format; ETC1S data does
            not use BasisLZ, or other data does; it is 1D or 3D; it has a
            face count other than one or six, or more levels than its size
            has; its size would decode to more than `MAX_DECODED_BYTES`;
            the descriptor, the global data or a level does not fit in the
            file; a level's length is not its size; a Zstandard or zlib
            stream is malformed; or the BasisLZ global data is.
    """
    if len(bytes) < HEADER_BYTES:
        raise Error("KTX2: the file is shorter than its header")
    var magic = identifier()
    for index in range(12):  # pragma: no branch
        if bytes[index] != magic[index]:
            raise Error(
                "KTX2: the file does not start with the KTX 2.0 identifier"
            )
    var container = KTX2Container()
    container.vk_format = VkFormat(_u32(bytes, 12))
    container.width = _u32(bytes, 20)
    container.height = _u32(bytes, 24)
    var depth = _u32(bytes, 28)
    container.layers = max(1, _u32(bytes, 32))
    container.faces = _u32(bytes, 36)
    container.levels = max(1, _u32(bytes, 40))
    container.supercompression = Supercompression(_u32(bytes, 44))
    _read_descriptor(bytes, container)
    var etc1s = container.is_etc1s()
    if etc1s != (container.supercompression == BASISLZ_SUPERCOMPRESSION):
        raise Error(
            "KTX2: ETC1S data must use BasisLZ supercompression, and no"
            " other data can"
        )
    if etc1s or container.is_uastc():
        if container.vk_format != VK_FORMAT_UNDEFINED:
            raise Error("KTX2: Basis Universal data must name no Vulkan format")
    elif not container.vk_format.is_valid():
        raise Error(
            "KTX2: "
            + String(container.vk_format)
            + " is not a format this reader decodes; ASTC, PVRTC, ETC2 with"
            " punch-through alpha, UASTC HDR and the other Vulkan formats"
            " are not ported"
        )
    if not container.supercompression.is_valid():
        raise Error(
            "KTX2: "
            + String(container.supercompression)
            + " is not a supercompression scheme"
        )
    if container.width <= 0 or container.height <= 0:
        raise Error("KTX2: only 2D textures are ported; 1D files are not")
    if depth != 0:
        raise Error("KTX2: only 2D textures are ported; 3D files are not")
    if container.faces != 1 and container.faces != 6:
        raise Error("KTX2: a file must have one face or six")
    check_decoded_size(
        container.width, container.height, container.decodes_to_floats()
    )
    if container.levels > chain_length(container.width, container.height):
        raise Error("KTX2: the file names more levels than its size has")
    if _outside(HEADER_BYTES, container.levels * LEVEL_ENTRY_BYTES, len(bytes)):
        raise Error("KTX2: the file ends inside its level index")
    var images = container.layers * container.faces
    for level in range(container.levels):  # pragma: no branch
        var entry = HEADER_BYTES + level * LEVEL_ENTRY_BYTES
        var offset = _u64(bytes, entry)
        var length = _u64(bytes, entry + 8)
        var full = _u64(bytes, entry + 16)
        if _outside(offset, length, len(bytes)):
            raise Error("KTX2: a level lies outside the file")
        var data = List[UInt8](bytes[offset : offset + length])
        if not etc1s:
            # Divided rather than multiplied, so a huge layer count cannot
            # overflow the check.
            var size = container.image_bytes(level)
            if full % images != 0 or full // images != size:
                raise Error("KTX2: a level's length does not match its size")
            if container.supercompression == ZLIB_SUPERCOMPRESSION:
                data = zlib_inflate(data, full)
            elif container.supercompression == ZSTD_SUPERCOMPRESSION:
                data = zstd_decompress(data, full)
            if len(data) != full:
                raise Error("KTX2: a level's length does not match its size")
        container.level_data.append(data^)
    if etc1s:
        # The supercompression global data: its offset and length.
        var offset = _u64(bytes, 64)
        var length = _u64(bytes, 72)
        if _outside(offset, length, len(bytes)):
            raise Error("KTX2: the supercompression global data lies outside")
        container.etc1s = Etc1sGlobal(
            List[UInt8](bytes[offset : offset + length]),
            images * container.levels,
            container.has_alpha,
        )
    return container^
