# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.ktx2`: hand-built KTX 2.0 files of block and
uncompressed formats, stored whole and through zlib and Zstandard; Basis
Universal files; and every file this reader refuses.

The Basis Universal files under `assets/ktx2/` were written by the Basis
Universal 2.50 encoder that ktx2-encoder 0.6.0 bundles. Each level's
expected texels are what the Basis Universal transcoder of three.js r186,
`examples/jsm/libs/basis/basis_transcoder.wasm`, gives for its `RGBA32`
target; the tests compare their XXH64 hash."""

from render.compressed_texture import (
    RGB_S3TC_DXT1_FORMAT,
    RGBA_BPTC_FORMAT,
    SIGNED_RG11_EAC_FORMAT,
)
from render.ktx2 import (
    BASISLZ_SUPERCOMPRESSION,
    NO_SUPERCOMPRESSION,
    VK_FORMAT_UNDEFINED,
    VK_R8G8B8A8_SRGB,
    ZLIB_SUPERCOMPRESSION,
    ZSTD_SUPERCOMPRESSION,
    KTX2Container,
    Supercompression,
    VkFormat,
    compressed_format_of,
    identifier,
    read,
)
from render.png import zlib_stream
from render.srgb import LINEAR, SRGB
from render.texture import FLOAT_TYPE, UNSIGNED_BYTE_TYPE
from render.zstd import xxh64
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def put(mut bytes: List[UInt8], at: Int, value: Int, count: Int = 4):
    """Write a little-endian number of `count` bytes."""
    for byte in range(count):
        bytes[at + byte] = UInt8((value >> (byte * 8)) & 0xFF)


struct Ktx2(Movable):
    """A KTX 2.0 file under construction."""

    var vk_format: Int
    var width: Int
    var height: Int
    var depth: Int
    var layers: Int
    var faces: Int
    var scheme: Int
    var color_model: Int
    var transfer: Int
    var flags: Int
    var levels: List[List[UInt8]]
    var full: List[Int]

    def __init__(out self, vk_format: Int, width: Int, height: Int):
        self.vk_format = vk_format
        self.width = width
        self.height = height
        self.depth = 0
        self.layers = 0
        self.faces = 1
        self.scheme = 0
        self.color_model = 1
        self.transfer = 1
        self.flags = 0
        self.levels = List[List[UInt8]]()
        self.full = List[Int]()

    def level(mut self, var data: List[UInt8], full: Int = -1):
        """Add a level; `full` is its decompressed length, by default the
        data's own."""
        var length = full
        if length < 0:
            length = len(data)
        self.full.append(length)
        self.levels.append(data^)

    def bytes(self) -> List[UInt8]:
        """Return the file: header, index, level index, descriptor, levels."""
        var count = len(self.levels)
        var dfd_at = 80 + count * 24
        var out = identifier()
        out.resize(dfd_at + 44, 0)
        var header: List[Int] = [
            self.vk_format, 1, self.width, self.height, self.depth,
            self.layers, self.faces, count, self.scheme,
        ]  # fmt: skip
        for index in range(9):
            put(out, 12 + index * 4, header[index])
        put(out, 48, dfd_at)
        put(out, 52, 44)
        # The descriptor: its total size, then the basic block's words.
        put(out, dfd_at, 44)
        put(out, dfd_at + 8, 40, 2)
        out[dfd_at + 12] = UInt8(self.color_model)
        out[dfd_at + 13] = 1
        out[dfd_at + 14] = UInt8(self.transfer)
        out[dfd_at + 15] = UInt8(self.flags)
        for level in range(count):
            var entry = 80 + level * 24
            put(out, entry, len(out), 8)
            put(out, entry + 8, len(self.levels[level]), 8)
            put(out, entry + 16, self.full[level], 8)
            out.extend(self.levels[level].copy())
        return out^


def bc1(value: Int) -> List[UInt8]:
    """Return a flat BC1 block of one 565 color."""
    return [
        UInt8(value & 0xFF),
        UInt8(value >> 8),
        UInt8(value & 0xFF),
        UInt8(value >> 8),
        0,
        0,
        0,
        0,
    ]


def test_a_block_compressed_file_decodes_each_level() raises:
    # BC1 RGBA sRGB, an 8x4 image and its 4x2 level.
    var file = Ktx2(134, 8, 4)
    file.transfer = 2
    var first = bc1(0xF800)
    first.extend(bc1(0x001F))
    file.level(first^)
    file.level(bc1(0x07E0))
    var container = read(file.bytes())
    assert_equal(container.vk_format, VkFormat(134))
    assert_equal(container.width, 8)
    assert_equal(container.levels, 2)
    assert_equal(container.color_space, SRGB)
    assert_equal(container.supercompression, NO_SUPERCOMPRESSION)
    assert_false(container.premultiplied)
    var top = container.texture()
    assert_equal(top.color_space, SRGB)
    assert_equal(top.texel(0, 0).r, UInt8(255))
    assert_equal(top.texel(7, 3).b, UInt8(255))
    var small = container.texture(level=1)
    assert_equal(small.width, 4)
    assert_equal(small.texel(3, 1).g, UInt8(255))


def test_a_cube_array_picks_a_face_of_a_layer() raises:
    # Two layers of six faces, each a flat BC1 block of its own number.
    var file = Ktx2(131, 4, 4)
    file.layers = 2
    file.faces = 6
    file.flags = 1
    var data = List[UInt8]()
    for image in range(12):
        data.extend(bc1(image << 11))
    file.level(data^)
    var container = read(file.bytes())
    assert_equal(container.layers, 2)
    assert_equal(container.faces, 6)
    assert_true(container.premultiplied)
    assert_equal(container.color_space, LINEAR)
    # Layer 1, face 3 is image 9: a red of 9 in five bits.
    var face = container.texture(face=3, layer=1)
    assert_equal(face.texel(0, 0).r, UInt8((9 << 3) | (9 >> 2)))
    for bad in [-1, 6]:
        with assert_raises(contains="no face"):
            _ = container.texture(face=bad)
    for bad in [-1, 2]:
        with assert_raises(contains="no layer"):
            _ = container.texture(layer=bad)
    for bad in [-1, 1]:
        with assert_raises(contains="no level"):
            _ = container.texture(level=bad)


def test_eight_bit_formats_fill_the_channels_they_have() raises:
    # R8, RG8 and RGBA8, one texel each.
    var formats: List[Int] = [9, 16, 37]
    var sizes: List[Int] = [1, 2, 4]
    for index in range(3):
        var file = Ktx2(formats[index], 1, 1)
        var texel: List[UInt8] = [10, 20, 30, 40]
        texel.resize(sizes[index], 0)
        file.level(texel^)
        var image = read(file.bytes()).texture()
        assert_equal(image.texel_type, UNSIGNED_BYTE_TYPE)
        assert_equal(image.color_space, LINEAR)
        var color = image.texel(0, 0)
        assert_equal(color.r, UInt8(10))
        if sizes[index] >= 2:
            assert_equal(color.g, UInt8(20))
        else:
            assert_equal(color.g, UInt8(0))
        if sizes[index] == 4:
            assert_equal(color.a, UInt8(40))
        else:
            assert_equal(color.b, UInt8(0))
            assert_equal(color.a, UInt8(255))
    # An sRGB format's descriptor says so.
    var srgb = Ktx2(VK_R8G8B8A8_SRGB.value, 1, 1)
    srgb.transfer = 2
    srgb.level([1, 2, 3, 4])
    assert_equal(read(srgb.bytes()).texture().color_space, SRGB)


def test_half_and_float_formats_are_float_textures() raises:
    # Halves: 1.5 is 0x3E00, -2 is 0xC000, 0.5 is 0x3800, 4 is 0x4400.
    var halves: List[UInt8] = [0x00, 0x3E, 0x00, 0xC0, 0x00, 0x38, 0x00, 0x44]
    var formats: List[Int] = [76, 83, 97]
    var channels: List[Int] = [1, 2, 4]
    var expected: List[Float32] = [1.5, -2, 0.5, 4]
    for index in range(3):
        var file = Ktx2(formats[index], 1, 1)
        var data = halves.copy()
        data.resize(channels[index] * 2, 0)
        file.level(data^)
        var image = read(file.bytes()).texture()
        assert_equal(image.texel_type, FLOAT_TYPE)
        for channel in range(channels[index]):
            assert_equal(image.data[channel], expected[channel])
        assert_equal(image.data[3], expected[3] if channels[index] == 4 else 1)
    # Floats: 1.5 is 0x3FC00000.
    for format in [100, 103, 109]:
        var file = Ktx2(format, 1, 1)
        var width = 4
        if format == 103:
            width = 8
        if format == 109:
            width = 16
        var data = List[UInt8](length=width, fill=0)
        for at in range(0, width, 4):
            data[at + 2] = 0xC0
            data[at + 3] = 0x3F
        file.level(data^)
        var image = read(file.bytes()).texture()
        assert_equal(image.data[0], Float32(1.5))
    # A half or float format holds linear light.
    var srgb = Ktx2(97, 1, 1)
    srgb.transfer = 2
    srgb.level(halves.copy())
    with assert_raises(contains="transfer function"):
        _ = read(srgb.bytes()).texture()


def test_a_zlib_level_is_inflated() raises:
    var file = Ktx2(131, 4, 4)
    file.scheme = 3
    file.level(zlib_stream(bc1(0xF800)), 8)
    var container = read(file.bytes())
    assert_equal(container.supercompression, ZLIB_SUPERCOMPRESSION)
    assert_equal(len(container.level_data[0]), 8)
    assert_equal(container.texture().texel(1, 1).r, UInt8(255))
    # A stream that inflates to less than it says is refused.
    var short = Ktx2(131, 4, 4)
    short.scheme = 3
    short.level(zlib_stream(List[UInt8](length=4, fill=0)), 8)
    with assert_raises(contains="does not match its size"):
        _ = read(short.bytes())


def zstd_frame(data: List[UInt8]) -> List[UInt8]:
    """Return a Zstandard frame of one raw block holding `data`."""
    var out: List[UInt8] = [0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x00]
    var header = 1 | (len(data) << 3)
    out.extend([UInt8(header & 0xFF), UInt8(header >> 8), 0])
    out.extend(data.copy())
    return out^


def test_a_zstandard_level_is_decompressed() raises:
    var file = Ktx2(131, 4, 4)
    file.scheme = 2
    file.level(zstd_frame(bc1(0x001F)), 8)
    var container = read(file.bytes())
    assert_equal(container.supercompression, ZSTD_SUPERCOMPRESSION)
    assert_equal(container.texture().texel(2, 2).b, UInt8(255))
    # A frame that holds more than the level's size is refused.
    var long = Ktx2(131, 4, 4)
    long.scheme = 2
    long.level(zstd_frame(List[UInt8](length=9, fill=0)), 8)
    with assert_raises(contains="more than was expected"):
        _ = read(long.bytes())


def fixture_hash(name: String, level: Int = 0) raises -> Tuple[Int, UInt64]:
    """Return the width of a level of a Basis Universal fixture and the
    XXH64 hash of its texels."""
    var container = read(Path("assets/ktx2/" + name).read_bytes())
    var image = container.texture(level=level)
    return (image.width, xxh64(image.pixels, 0, len(image.pixels)))


def test_uastc_files_decode_as_three_js_transcodes_them() raises:
    # Between them the four files use all nineteen UASTC modes.
    var alpha = fixture_hash("uastc_alpha.ktx2")
    assert_equal(alpha[1], 0x027A81AC150B2E5E)
    assert_equal(fixture_hash("uastc_gradient.ktx2")[1], 0xD03CC6155E6F8407)
    assert_equal(
        fixture_hash("uastc_gradient_alpha.ktx2")[1], 0x00381657619671CD
    )
    # Zstandard supercompression, sRGB, and levels of 61x47 down to 1x1.
    var hashes: List[UInt64] = [
        0x0F3E436C03B25F5C, 0xF2801657166EBAF0, 0xE301CDA8C2B52E61,
        0x15669C4E2269807D, 0xABF4C0440B493F17, 0x6B824CBF8A283B39,
    ]  # fmt: skip
    var widths: List[Int] = [61, 30, 15, 7, 3, 1]
    for level in range(6):
        var got = fixture_hash("uastc_rgb_zstd_mips.ktx2", level)
        assert_equal(got[0], widths[level])
        assert_equal(got[1], hashes[level])
    var container = read(
        Path("assets/ktx2/uastc_rgb_zstd_mips.ktx2").read_bytes()
    )
    assert_true(container.is_uastc())
    assert_false(container.is_etc1s())
    assert_equal(container.supercompression, ZSTD_SUPERCOMPRESSION)
    assert_equal(container.color_space, SRGB)
    assert_equal(container.texture().color_space, SRGB)


def test_etc1s_files_decode_as_three_js_transcodes_them() raises:
    assert_equal(fixture_hash("etc1s_rgb.ktx2")[1], 0xE0FB278EC3D1D4EE)
    assert_equal(fixture_hash("etc1s_gray.ktx2")[1], 0xF6C8FABD798A1F96)
    # An alpha slice per image, sRGB, and levels of 37x29 down to 1x1.
    var hashes: List[UInt64] = [
        0xB8622C967DBF6F76, 0xB5F103C9ACABAF9C, 0x7DE696D2BB60C756,
        0x2680FB6C61E66249, 0xAB1A60011FDB3CA9, 0xD3033A9604DB6AE7,
    ]  # fmt: skip
    for level in range(6):
        assert_equal(
            fixture_hash("etc1s_alpha_mips.ktx2", level)[1], hashes[level]
        )
    var container = read(Path("assets/ktx2/etc1s_alpha_mips.ktx2").read_bytes())
    assert_true(container.is_etc1s())
    assert_true(container.has_alpha)
    assert_equal(container.supercompression, BASISLZ_SUPERCOMPRESSION)
    assert_equal(container.color_space, SRGB)


def test_basis_universal_files_are_checked() raises:
    # ETC1S must use BasisLZ, and nothing else can.
    var etc1s = Ktx2(0, 4, 4)
    etc1s.color_model = 163
    etc1s.level(bc1(0))
    with assert_raises(contains="must use BasisLZ"):
        _ = read(etc1s.bytes())
    var basislz = Ktx2(131, 4, 4)
    basislz.scheme = 1
    basislz.level(bc1(0))
    with assert_raises(contains="must use BasisLZ"):
        _ = read(basislz.bytes())
    # Basis Universal data names no Vulkan format.
    var uastc = Ktx2(131, 4, 4)
    uastc.color_model = 166
    uastc.level(List[UInt8](length=16, fill=0))
    with assert_raises(contains="no Vulkan format"):
        _ = read(uastc.bytes())
    var named = Ktx2(131, 4, 4)
    named.color_model = 163
    named.scheme = 1
    named.level(bc1(0))
    with assert_raises(contains="no Vulkan format"):
        _ = read(named.bytes())
    # A UASTC level is sixteen bytes a block.
    var short = Ktx2(0, 4, 4)
    short.color_model = 166
    short.level(bc1(0))
    with assert_raises(contains="does not match its size"):
        _ = read(short.bytes())
    # An ETC1S file whose global data lies outside it.
    var file = Path("assets/ktx2/etc1s_rgb.ktx2").read_bytes()
    var outside = file.copy()
    put(outside, 72, 100000, 8)
    with assert_raises(contains="global data lies outside"):
        _ = read(outside)
    # A malformed UASTC block surfaces from the texture, not the read.
    var reserved = Ktx2(0, 4, 4)
    reserved.color_model = 166
    var block = List[UInt8](length=16, fill=0)
    block[0] = 0x45
    reserved.level(block^)
    var container = read(reserved.bytes())
    with assert_raises(contains="reserved mode"):
        _ = container.texture()


def test_unknown_supercompression_is_refused() raises:
    var unknown = Ktx2(131, 4, 4)
    unknown.scheme = 7
    unknown.level(bc1(0))
    with assert_raises(contains="Supercompression(7) is not a"):
        _ = read(unknown.bytes())


def test_formats_this_reader_does_not_decode_are_refused() raises:
    # Undefined, ETC2 with punch-through alpha, ASTC 4x4, and R8G8B8.
    for format in [0, 149, 150, 157, 23]:
        var file = Ktx2(format, 4, 4)
        file.level(bc1(0))
        with assert_raises(contains="not ported"):
            _ = read(file.bytes())


def test_the_formats_say_what_they_are() raises:
    assert_true(VkFormat(9).is_uncompressed())
    assert_false(VkFormat(131).is_uncompressed())
    assert_true(VkFormat(131).is_valid())
    assert_true(VkFormat(156).is_valid())
    assert_false(VkFormat(130).is_valid())
    assert_false(VkFormat(157).is_valid())
    assert_false(VK_FORMAT_UNDEFINED.is_valid())
    assert_equal(VkFormat(22).channels(), 2)
    assert_equal(VkFormat(15).channels(), 1)
    assert_equal(VkFormat(43).channel_bytes(), 1)
    assert_equal(VkFormat(83).channel_bytes(), 2)
    assert_equal(VkFormat(103).channel_bytes(), 4)
    assert_equal(String(VkFormat(145)), "VkFormat(145)")
    assert_equal(compressed_format_of(VkFormat(146)), RGBA_BPTC_FORMAT)
    assert_equal(compressed_format_of(VkFormat(131)), RGB_S3TC_DXT1_FORMAT)
    assert_equal(compressed_format_of(VkFormat(156)), SIGNED_RG11_EAC_FORMAT)
    with assert_raises(contains="block format"):
        _ = compressed_format_of(VkFormat(37))
    with assert_raises(contains="block format"):
        _ = compressed_format_of(VkFormat(157))
    assert_equal(String(BASISLZ_SUPERCOMPRESSION), "BasisLZ")
    assert_equal(String(ZSTD_SUPERCOMPRESSION), "Zstandard")
    assert_equal(String(Supercompression(-1)), "Supercompression(-1)")
    assert_false(Supercompression(4).is_valid())
    # Which formats decode to floats.
    var container = KTX2Container()
    var floats: List[Int] = [76, 97, 109, 140, 142, 143, 144, 153, 156]
    var bytes: List[Int] = [9, 37, 131, 139, 141, 145, 151, 157]
    for format in floats:
        container.vk_format = VkFormat(format)
        assert_true(container.decodes_to_floats())
    for format in bytes:
        container.vk_format = VkFormat(format)
        assert_false(container.decodes_to_floats())


def test_a_malformed_file_is_refused() raises:
    with assert_raises(contains="shorter than its header"):
        _ = read(List[UInt8](length=79, fill=0))
    var good = Ktx2(131, 4, 4)
    good.level(bc1(0))
    var magic = good.bytes()
    magic[6] = 0x31
    with assert_raises(contains="identifier"):
        _ = read(magic)
    # The descriptor: too short, and past the end.
    var brief = good.bytes()
    put(brief, 52, 20)
    with assert_raises(contains="descriptor"):
        _ = read(brief)
    var past = good.bytes()
    put(past, 48, 100000)
    with assert_raises(contains="descriptor"):
        _ = read(past)
    for dims in [(0, 4), (4, 0)]:
        var flat = Ktx2(131, dims[0], dims[1])
        flat.level(bc1(0))
        with assert_raises(contains="1D"):
            _ = read(flat.bytes())
    var deep = Ktx2(131, 4, 4)
    deep.depth = 2
    deep.level(bc1(0))
    with assert_raises(contains="3D"):
        _ = read(deep.bytes())
    var faces = Ktx2(131, 4, 4)
    faces.faces = 2
    faces.level(bc1(0))
    with assert_raises(contains="one face or six"):
        _ = read(faces.bytes())
    var huge = Ktx2(131, 100000, 100000)
    huge.level(bc1(0))
    with assert_raises(contains="MAX_DECODED_BYTES"):
        _ = read(huge.bytes())
    var many = Ktx2(131, 4, 4)
    for _ in range(4):
        many.level(bc1(0))
    with assert_raises(contains="more levels"):
        _ = read(many.bytes())
    # A level index that runs past the end: say three levels, and end the
    # file after the descriptor, four bytes short of the third entry.
    var index = good.bytes()
    put(index, 40, 3)
    index.resize(80 + 24 + 44, 0)
    with assert_raises(contains="level index"):
        _ = read(index)
    var outside = good.bytes()
    put(outside, 80, 100000, 8)
    with assert_raises(contains="outside the file"):
        _ = read(outside)
    var huge_offset = good.bytes()
    put(huge_offset, 80 + 7, 0x80, 1)
    with assert_raises(contains="too large"):
        _ = read(huge_offset)
    # A decompressed length not a whole number of images, one of the
    # wrong size, and a stored length that differs from it.
    var ragged = Ktx2(131, 4, 4)
    ragged.faces = 6
    ragged.level(List[UInt8](length=48, fill=0), 49)
    with assert_raises(contains="does not match its size"):
        _ = read(ragged.bytes())
    var wrong = Ktx2(131, 4, 4)
    wrong.level(bc1(0), 16)
    with assert_raises(contains="does not match its size"):
        _ = read(wrong.bytes())
    var stored = Ktx2(131, 4, 4)
    var nine = bc1(0)
    nine.append(0)
    stored.level(nine^, 8)
    with assert_raises(contains="does not match its size"):
        _ = read(stored.bytes())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
