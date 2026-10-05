# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Raw ASTC compared with Arm astcenc 5.3.0, plus KTX2 container boundaries."""

from render.exr import half_to_float
from render.ktx2 import KTX2Container, VkFormat, read
from render.srgb import LINEAR, SRGB
from render.texture import FLOAT_TYPE, UNSIGNED_BYTE_TYPE
from render.uastc_hdr import (
    ASTC_HDR,
    ASTC_SRGB,
    ASTC_UNORM,
    AstcProfile,
    AstcTables,
    astc_block,
    astc_image,
    astc_hdr_image,
)
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_etc import hex_bytes
from tests.test_ktx2 import Ktx2, put, zstd_frame
from tests.test_uastc_hdr import void_extent


def test_every_raw_block_mode_matches_the_independent_decoder() raises:
    var tables = AstcTables()
    var text = Path("assets/ktx2/raw_astc_reference.txt").read_text()
    var records = 0
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        var fields = line.split(" ")
        var size = Int(fields[0])
        var profile = AstcProfile(Int(fields[1]))
        var block = hex_bytes(String(fields[2]), 0, 16)
        var actual = astc_block(block, 0, tables, size, profile)
        var stride = 2 if profile == ASTC_HDR else 1
        var expected = hex_bytes(String(fields[3]), 0, size * size * 4 * stride)
        for index in range(len(actual)):
            var value = Int(expected[index * stride])
            if stride == 2:
                value |= Int(expected[index * stride + 1]) << 8
            if actual[index] != value:
                raise Error(
                    "ASTC oracle mismatch size="
                    + String(size)
                    + " profile="
                    + String(profile)
                    + " block="
                    + String(fields[2])
                    + " channel="
                    + String(index)
                    + " got="
                    + String(actual[index])
                    + " expected="
                    + String(value)
                )
        records += 1
    assert_equal(records, 2152)


def test_malformed_blocks_match_independent_rejections() raises:
    var tables = AstcTables()
    var text = Path("assets/ktx2/raw_astc_invalid.txt").read_text()
    var count = 0
    for line in text.splitlines():
        var fields = line.split(" ")
        var size = Int(fields[0])
        var block = hex_bytes(String(fields[1]), 0, 16)
        with assert_raises():
            _ = astc_block(block, 0, tables, size, ASTC_HDR)
        count += 1
    assert_equal(count, 8192)


def test_hdr_endpoint_modes_are_refused_in_ldr_profiles() raises:
    var tables = AstcTables()
    # Valid 4x4 block, CEM 11 (HDR RGB); independently decoded in the corpus.
    var text = Path("assets/ktx2/raw_astc_reference.txt").read_text()
    var checked = 0
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        var fields = line.split(" ")
        var block = hex_bytes(String(fields[2]), 0, 16)
        var config = (
            Int(block[0]) | (Int(block[1]) << 8) | (Int(block[2]) << 16)
        )
        if (
            Int(fields[1]) == 2
            and ((config >> 11) & 3) == 0
            and ((config >> 13) & 15) == 11
        ):
            for profile in [ASTC_UNORM, ASTC_SRGB]:
                with assert_raises(contains="HDR endpoints"):
                    _ = astc_block(block, 0, tables, Int(fields[0]), profile)
            checked += 1
    assert_true(checked > 0)
    with assert_raises(contains="LDR profile"):
        _ = astc_image(1, 1, void_extent(0, [0, 0, 0, 0]), 4, ASTC_HDR)


def test_all_six_formats_crop_and_route_texels() raises:
    for size in [4, 6]:
        for profile in range(3):
            var vk = (157 if size == 4 else 165) + profile
            if profile == 2:
                vk = 1000066000 if size == 4 else 1000066004
            var file = Ktx2(vk, size + 1, size - 1)
            file.color_model = 162
            file.transfer = 2 if profile == 1 else 1
            var data = void_extent(0, [0, 0xFFFF, 0x8080, 0x4040])
            data.extend(void_extent(0, [0xFFFF, 0, 0xFFFF, 0xFFFF]))
            file.level(data^)
            var container = read(file.bytes())
            assert_equal(container.image_bytes(0), 32)
            assert_equal(container.decodes_to_floats(), profile == 2)
            var texture = container.texture()
            assert_equal(texture.width, size + 1)
            assert_equal(texture.height, size - 1)
            assert_false(texture.flip_y)
            if profile == 2:
                assert_equal(texture.texel_type, FLOAT_TYPE)
                assert_equal(texture.data[0], Float32(0))
                assert_equal(texture.data[1], Float32(1))
                assert_equal(texture.data[size * 4], Float32(1))
                assert_equal(texture.data[size * 4 + 3], Float32(1))
            else:
                assert_equal(texture.texel_type, UNSIGNED_BYTE_TYPE)
                assert_equal(
                    texture.color_space, SRGB if profile == 1 else LINEAR
                )
                assert_equal(texture.pixels[2], UInt8(128))
                assert_equal(texture.pixels[3], UInt8(64))
                assert_equal(texture.pixels[size * 4], UInt8(255))
                assert_equal(texture.pixels[size * 4 + 1], UInt8(0))


def test_edge_images_match_the_cropped_independent_texels() raises:
    var text = Path("assets/ktx2/raw_astc_reference.txt").read_text()
    var seen = List[Bool](length=6, fill=False)
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        var fields = line.split(" ")
        var size = Int(fields[0])
        var profile = Int(fields[1])
        var slot = (0 if size == 4 else 3) + profile
        if seen[slot]:
            continue
        seen[slot] = True
        var block = hex_bytes(String(fields[2]), 0, 16)
        var stride = 2 if profile == 2 else 1
        var reference = hex_bytes(
            String(fields[3]), 0, size * size * 4 * stride
        )
        var payload = List[UInt8]()
        for _ in range(4):
            payload.extend(block.copy())
        var width = size * 2 - 1
        var height = size * 2 - 2
        var vk = (157 if size == 4 else 165) + profile
        if profile == 2:
            vk = 1000066000 if size == 4 else 1000066004
        var file = Ktx2(vk, width, height)
        file.color_model = 162
        file.transfer = 2 if profile == 1 else 1
        file.level(payload^)
        var image = read(file.bytes()).texture()
        for y in range(height):
            for x in range(width):
                for channel in range(4):
                    var at = ((y % size) * size + x % size) * 4 + channel
                    var value = Int(reference[at * stride])
                    var to = (y * width + x) * 4 + channel
                    if profile == 2:
                        value |= Int(reference[at * stride + 1]) << 8
                        assert_equal(
                            image.data[to], half_to_float(UInt16(value))
                        )
                    else:
                        assert_equal(image.pixels[to], UInt8(value))
    for found in seen:
        assert_true(found)


def test_raw_hdr_alpha_is_independent_of_the_basis_restriction() raises:
    for size in [4, 6]:
        var file = Ktx2(1000066000 if size == 4 else 1000066004, 1, 1)
        file.color_model = 162
        file.level(void_extent(1, [0x0001, 0x4000, 0x7BFF, 0x3800]))
        var bytes = file.bytes()
        put(bytes, 104 + 31, 3, 1)
        var container = read(bytes)
        assert_false(container.is_uastc_hdr())
        var image = container.texture()
        assert_equal(image.data[0], half_to_float(0x0001))
        assert_equal(image.data[1], Float32(2))
        assert_equal(image.data[2], Float32(65504))
        assert_equal(image.data[3], Float32(0.5))


def test_raw_astc_mips_faces_layers_and_zstandard() raises:
    for size in [4, 6]:
        for profile in range(3):
            var vk = (157 if size == 4 else 165) + profile
            if profile == 2:
                vk = 1000066000 if size == 4 else 1000066004
            var file = Ktx2(vk, size + 1, size + 1)
            file.color_model = 162
            file.transfer = 2 if profile == 1 else 1
            file.layers = 2
            file.faces = 6
            file.scheme = 2
            for level in range(3):
                var width = max(1, (size + 1) >> level)
                var blocks = ((width + size - 1) // size) ** 2
                var payload = List[UInt8]()
                for image in range(12):
                    for _ in range(blocks):
                        payload.extend(
                            void_extent(
                                0, [(image + 1) * 4096, level * 4096, 0, 0xFFFF]
                            )
                        )
                var full = len(payload)
                file.level(zstd_frame(payload), full)
            var container = read(file.bytes())
            for level in range(3):
                for layer in range(2):
                    for face in range(6):
                        var image = container.texture(
                            face=face, layer=layer, level=level
                        )
                        var red = (layer * 6 + face + 1) * 4096
                        if profile == 2:
                            var expected = astc_hdr_image(
                                1,
                                1,
                                void_extent(0, [red, level * 4096, 0, 0xFFFF]),
                                size,
                            )
                            assert_equal(
                                image.data[0],
                                expected[0],
                            )
                        else:
                            assert_equal(image.pixels[0], UInt8(red >> 8))
                            assert_equal(image.pixels[1], UInt8(level * 16))


def test_raw_astc_boundaries_fail_before_unsafe_reads_or_allocations() raises:
    var tables = AstcTables()
    var good = void_extent(0, [0, 0, 0, 0xFFFF])
    for profile in [AstcProfile(-1), AstcProfile(3)]:
        assert_false(profile.is_valid())
        with assert_raises(contains="profile"):
            _ = astc_block(good, 0, tables, 4, profile)
        with assert_raises(contains="profile"):
            _ = astc_image(1, 1, good, 4, profile)
    for size in [0, 5, 12]:
        with assert_raises(contains="4x4 and 6x6"):
            _ = astc_block(good, 0, tables, size, ASTC_HDR)
        with assert_raises(contains="4x4 and 6x6"):
            _ = astc_hdr_image(1, 1, good, size)
    for at in [-1, 1, 17]:
        with assert_raises(contains="truncated"):
            _ = astc_block(good, at, tables, 6, ASTC_HDR)
    for count in [0, 1, 15]:
        with assert_raises(contains="truncated"):
            _ = astc_block(
                List[UInt8](length=count, fill=0), 0, tables, 6, ASTC_HDR
            )
    for size in [4, 6]:
        with assert_raises(contains="positive"):
            _ = astc_hdr_image(0, 1, good, size)
        with assert_raises(contains="positive"):
            _ = astc_hdr_image(1, -1, good, size)
        with assert_raises(contains="MAX_DECODED_BYTES"):
            _ = astc_hdr_image(1 << 40, 1 << 40, good, size)
        with assert_raises(contains="one block"):
            _ = astc_image(size + 1, 1, good, size, ASTC_UNORM)
        for profile in [ASTC_UNORM, ASTC_SRGB]:
            with assert_raises(contains="HDR void"):
                _ = astc_block(
                    void_extent(1, [0, 0, 0, 0x3C00]), 0, tables, size, profile
                )
    for vk in [157, 158, 165, 166, 1000066000, 1000066004]:
        var file = Ktx2(vk, 1, 1)
        file.color_model = 162
        file.transfer = 2 if vk == 158 or vk == 166 else 1
        file.level(List[UInt8](length=15, fill=0))
        with assert_raises(contains="length"):
            _ = read(file.bytes())
        file.levels[0] = good.copy()
        file.full[0] = 16
        file.transfer = 1 if file.transfer == 2 else 2
        with assert_raises(contains="transfer function disagree"):
            _ = read(file.bytes())


def test_each_raw_format_uses_its_decoded_allocation_guard() raises:
    for vk in [157, 158, 165, 166, 1000066000, 1000066004]:
        var hdr = vk >= 1000066000
        var width = (1 << 26) + 1 if hdr else (1 << 28) + 1
        var file = Ktx2(vk, width, 1)
        file.color_model = 162
        file.transfer = 2 if vk == 158 or vk == 166 else 1
        file.level(void_extent(0, [0, 0, 0, 0]))
        with assert_raises(contains="MAX_DECODED_BYTES"):
            _ = read(file.bytes())
        file.width = 1
        file.layers = 0xFFFFFFFF
        file.faces = 6
        with assert_raises(contains="length"):
            _ = read(file.bytes())


def test_raw_astc_requires_the_matching_descriptor_color_model() raises:
    for vk in [157, 158, 165, 166, 1000066000, 1000066004]:
        var file = Ktx2(vk, 1, 1)
        file.transfer = 2 if vk == 158 or vk == 166 else 1
        file.level(void_extent(0, [0, 0, 0, 0xFFFF]))
        for model in [0, 1, 161, 164, 255]:
            file.color_model = model
            with assert_raises(contains="ASTC descriptor color model"):
                _ = read(file.bytes())
        file.color_model = 162
        var container = read(file.bytes())
        assert_equal(container.color_model, 162)
        assert_equal(container.image_bytes(0), 16)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
