# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""GPU volume headers and program addresses stay exact, issue #424."""

from materials.nodes import FRAGMENT_NODE, NodeGraph, NodeProgramStore
from render.framebuffer import FloatColor
from render.gpu import (
    VOLUME_HEADER,
    _append_block,
    _packed_index,
    _packed_offset,
    _volume_block_size,
    flatten_programs,
    volume_blocks,
)
from render.volume_texture import Data3DTexture, DataArrayTexture, VolumeImage
from render.volume_texture_store import (
    Data3DTextureId,
    Data3DTextureStore,
    DataArrayTextureId,
    DataArrayTextureStore,
)
from std.testing import TestSuite, assert_equal, assert_raises


def _image() raises -> VolumeImage:
    """Return two distinct RGBA texels."""
    return VolumeImage.of_bytes(2, 1, 1, [255, 0, 0, 255, 0, 255, 0, 255])


def test_headers_preserve_exact_boundaries_without_large_images() raises:
    for width in [(1 << 24) - 1, 1 << 24, (1 << 24) + 2]:
        var header = List[Float32]()
        _append_block(header, width, 1, 1, 0, 0, 0, 0, List[FloatColor]())
        assert_equal(Int(header[0]), width)
        assert_equal(len(header), VOLUME_HEADER)
    var refused = List[Float32]()
    with assert_raises(contains="exactly representable"):
        _append_block(
            refused, (1 << 24) + 1, 1, 1, 0, 0, 0, 0, List[FloatColor]()
        )
    assert_equal(len(refused), 0)


def test_packed_offsets_check_the_sum_before_conversion() raises:
    assert_equal(Int(_packed_offset(1 << 24, 2)), (1 << 24) + 2)
    with assert_raises(contains="exactly representable"):
        _ = _packed_offset(1 << 24, 1)
    with assert_raises(contains="Int32"):
        _ = _packed_offset(2147483647, 1)
    with assert_raises(contains="Int32"):
        _ = _packed_offset(0, -1)
    with assert_raises(contains="Int32"):
        _ = _packed_index(1 << 40)


def test_volume_extents_are_checked_before_decoding_or_multiplication() raises:
    assert_equal(_volume_block_size(2, 3, 4), VOLUME_HEADER + 2 * 3 * 4 * 4)
    for axis in range(3):
        var sizes = [1, 1, 1]
        sizes[axis] = (1 << 24) + 1
        with assert_raises(contains="exactly representable"):
            _ = _volume_block_size(sizes[0], sizes[1], sizes[2])
    with assert_raises(contains="positive"):
        _ = _volume_block_size(0, 1, 1)
    with assert_raises(contains="Int32 addressing"):
        _ = _volume_block_size(1 << 22, 1 << 22, 1 << 22)


def test_volume_and_array_blocks_keep_their_texels_and_starts() raises:
    var volumes = Data3DTextureStore()
    _ = volumes.add(Data3DTexture(_image()))
    var arrays = DataArrayTextureStore()
    _ = arrays.add(DataArrayTexture(_image()))
    var packed = volume_blocks(volumes, arrays)
    assert_equal(packed[1][0], 0)
    assert_equal(packed[2][0], VOLUME_HEADER + 8)
    assert_equal(len(packed[0]), 2 * (VOLUME_HEADER + 8))
    for block in range(2):
        var start = block * (VOLUME_HEADER + 8)
        assert_equal(packed[0][start], Float32(2))
        assert_equal(packed[0][start + VOLUME_HEADER], Float32(1))
        assert_equal(packed[0][start + VOLUME_HEADER + 5], Float32(1))


def test_mutated_volume_and_array_storage_is_refused_before_reading() raises:
    var volumes = Data3DTextureStore()
    _ = volumes.add(Data3DTexture(_image()))
    _ = volumes.textures[0].image.pixels.pop()
    with assert_raises(contains="length"):
        _ = volume_blocks(volumes, DataArrayTextureStore())
    var arrays = DataArrayTextureStore()
    _ = arrays.add(DataArrayTexture(_image()))
    arrays.textures[0].image.width = (1 << 24) + 1
    with assert_raises(contains="exactly representable"):
        _ = volume_blocks(Data3DTextureStore(), arrays)


def test_program_volume_and_array_offsets_cannot_round() raises:
    for array in [False, True]:
        var graph = NodeGraph()
        var sampled = graph.texture_array(
            graph.array_uniform("map", DataArrayTextureId(0)),
            graph.vec3(0, 0, 0),
        ) if array else graph.texture_3d(
            graph.volume_uniform("map", Data3DTextureId(0)), graph.vec3(0, 0, 0)
        )
        graph.set_output(FRAGMENT_NODE, sampled)
        var program = graph.compile()
        var offset = program.array_offsets[
            0
        ] if array else program.volume_offsets[0]
        var store = NodeProgramStore()
        _ = store.add(program^)
        var precise = flatten_programs(
            store, blocks_base=1 << 24, volume_starts=[2], array_starts=[2]
        )
        assert_equal(Int(precise[offset]), (1 << 24) + 2)
        with assert_raises(contains="exactly representable"):
            _ = flatten_programs(
                store, blocks_base=1 << 24, volume_starts=[1], array_starts=[1]
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
