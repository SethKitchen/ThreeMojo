# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared texture bytes keep mutation and lifetime semantics explicit."""

from math.vector2 import Vector2
from render.srgb import SRGB
from render.texture import (
    BILINEAR,
    CLAMP,
    IGNORED,
    NEAREST,
    REPEAT,
    Texture,
    float_texture,
)
from render.texture_buffer import TextureBuffer
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from units.si import Angle, DEGREE


def _bytes() raises -> Texture:
    return Texture(
        4,
        4,
        List[UInt8](length=64, fill=128),
        REPEAT,
        BILINEAR,
        SRGB,
        True,
        IGNORED,
    )


def test_shared_byte_texture_keeps_the_complete_mip_allocation() raises:
    var original = _bytes()
    var shared = Texture(copy=original, share_data=True)
    assert_true(original.pixels.shares_with(shared.pixels))
    assert_equal(original.pixels, shared.pixels)
    assert_equal(original.levels, 3)
    assert_equal(len(shared.pixels), 84)
    assert_equal(shared.offsets, original.offsets)
    var first = original.sample(0.2, 0.7)
    var other = shared.sample(0.2, 0.7)
    assert_equal(first.r, other.r)
    assert_equal(first.g, other.g)
    assert_equal(first.b, other.b)
    assert_true(original.pixels.shares_with(shared.pixels))


def test_default_copy_stays_deep_and_independent() raises:
    var original = _bytes()
    var copy = Texture(copy=original)
    assert_false(original.pixels.shares_with(copy.pixels))
    assert_false(original.data.shares_with(copy.data))
    copy.pixels[0] = 7
    assert_equal(original.pixels[0], UInt8(128))
    assert_equal(copy.pixels[0], UInt8(7))


def test_indexed_write_detaches_only_the_written_buffer() raises:
    var source = _bytes()
    var first = Texture(copy=source, share_data=True)
    var second = Texture(copy=source, share_data=True)
    first.pixels[0] = 12
    assert_false(first.pixels.shares_with(source.pixels))
    assert_true(second.pixels.shares_with(source.pixels))
    assert_equal(source.pixels[0], UInt8(128))
    source.pixels[1] = 34
    assert_equal(second.pixels[1], UInt8(128))
    assert_equal(first.pixels[1], UInt8(128))
    assert_false(second.pixels.shares_with(source.pixels))


def test_float_mips_share_and_detach_without_byte_conversion() raises:
    var source = float_texture(
        2, 2, List[Float32](length=16, fill=2.5), mipmapped=True, alpha=IGNORED
    )
    var shared = Texture(copy=source, share_data=True)
    assert_true(source.data.shares_with(shared.data))
    assert_equal(len(shared.data), 20)
    assert_equal(shared.data[16], Float32(2.5))
    shared.data[0] = 7.25
    assert_equal(source.data[0], Float32(2.5))
    assert_equal(shared.data[0], Float32(7.25))
    assert_false(source.data.shares_with(shared.data))


def test_sampling_and_transform_state_are_independent() raises:
    var source = _bytes()
    var shared = Texture(copy=source, share_data=True)
    shared.repeat = Vector2(3, 5)
    shared.offset = Vector2(0.2, 0.3)
    shared.center = Vector2(0.4, 0.6)
    shared.rotation = Angle(35, DEGREE)
    shared.set_wrap(CLAMP)
    shared.mag_filter = NEAREST
    shared.anisotropy = 4
    shared.flip_y = not source.flip_y
    shared.offsets[0] = 1
    shared.ramp[128] = 0.75
    assert_true(source.repeat == Vector2(1, 1))
    assert_true(source.offset == Vector2(0, 0))
    assert_true(source.center == Vector2(0, 0))
    assert_equal(source.wrap_s, REPEAT)
    assert_equal(source.mag_filter, BILINEAR)
    assert_equal(source.anisotropy, 1)
    assert_equal(source.offsets[0], 0)
    assert_true(source.ramp[128] != shared.ramp[128])
    assert_true(source.pixels.shares_with(shared.pixels))


def test_regenerating_mips_changes_only_one_shared_texture() raises:
    var source = _bytes()
    var shared = Texture(copy=source, share_data=True)
    var original = source.pixels.copy()
    for index in range(0, 64, 4):
        shared.pixels[index] = 0
    shared.regenerate_mipmaps()
    assert_equal(source.pixels.values(), original)
    assert_equal(shared.levels, 3)
    assert_equal(shared.pixels[64], UInt8(0))
    assert_equal(shared.pixels[80], UInt8(0))


def test_empty_shared_buffers_have_independent_mutation() raises:
    var original = Texture()
    var shared = Texture(copy=original, share_data=True)
    assert_true(original.pixels.shares_with(shared.pixels))
    assert_true(original.data.shares_with(shared.data))
    assert_equal(len(shared.pixels), 0)
    shared.pixels.append(7)
    shared.data.append(1.5)
    assert_equal(len(original.pixels), 0)
    assert_equal(len(original.data), 0)
    assert_equal(shared.pixels[0], UInt8(7))
    assert_equal(shared.data[0], Float32(1.5))


def _share_after_local_owner_dies() raises -> Texture:
    var source = _bytes()
    return Texture(copy=source, share_data=True)


def test_shared_allocation_outlives_original_owner_and_moves() raises:
    var shared = _share_after_local_owner_dies()
    var moved = shared^
    assert_equal(len(moved.pixels), 84)
    assert_equal(moved.pixels[80], UInt8(128))
    var next = Texture(copy=moved, share_data=True)
    moved = Texture()
    assert_true(moved.is_blank())
    assert_equal(next.pixels[0], UInt8(128))
    next.pixels[0] = 9
    assert_equal(next.pixels[0], UInt8(9))


def test_writable_pointer_before_sharing_forces_a_snapshot() raises:
    var source = _bytes()
    var pointer = (
        source.pixels.mutable_values()
        .unsafe_ptr()
        .unsafe_origin_cast[MutAnyOrigin]()
    )
    var shared = Texture(copy=source, share_data=True)
    assert_false(source.pixels.shares_with(shared.pixels))
    pointer[unsafe_offset=0] = 11
    assert_equal(source.pixels[0], UInt8(11))
    assert_equal(shared.pixels[0], UInt8(128))
    # Exposure is sticky after an ordinary write and after earlier copies die.
    source.pixels[1] = 22
    var later = Texture(copy=source, share_data=True)
    pointer[unsafe_offset=2] = 33
    assert_equal(later.pixels[1], UInt8(22))
    assert_equal(later.pixels[2], UInt8(128))


def test_writable_pointer_after_sharing_detaches_first() raises:
    var source = _bytes()
    var shared = Texture(copy=source, share_data=True)
    var pointer = (
        shared.pixels.mutable_values()
        .unsafe_ptr()
        .unsafe_origin_cast[MutAnyOrigin]()
    )
    pointer[unsafe_offset=0] = 44
    assert_equal(source.pixels[0], UInt8(128))
    assert_equal(shared.pixels[0], UInt8(44))
    assert_false(source.pixels.shares_with(shared.pixels))


def test_float_writable_alias_gets_the_same_snapshot_contract() raises:
    var source = float_texture(1, 1, List[Float32](length=4, fill=2.5))
    var pointer = (
        source.data.mutable_values()
        .unsafe_ptr()
        .unsafe_origin_cast[MutAnyOrigin]()
    )
    var shared = Texture(copy=source, share_data=True)
    pointer[unsafe_offset=0] = 9
    assert_equal(source.data[0], Float32(9))
    assert_equal(shared.data[0], Float32(2.5))
    assert_false(source.data.shares_with(shared.data))


def test_explicit_mutable_list_borrow_detaches_and_can_resize() raises:
    var source = TextureBuffer(List[UInt8](length=4, fill=1))
    var shared = TextureBuffer(shared=source)
    shared.mutable_values().resize(8, 2)
    assert_equal(len(source), 4)
    assert_equal(len(shared), 8)
    assert_equal(shared[7], UInt8(2))
    assert_false(shared.shares_with(source))
    source.resize(2, 0)
    assert_equal(len(shared), 8)


def test_immutable_reads_do_not_mark_a_buffer_as_mutably_exposed() raises:
    var source = _bytes()
    ref values = source.pixels.values()
    assert_equal(values[0], UInt8(128))
    assert_equal(source.pixels.unsafe_ptr()[unsafe_offset=0], UInt8(128))
    assert_equal(source.pixels.unsafe_get(0), UInt8(128))
    var shared = Texture(copy=source, share_data=True)
    assert_true(source.pixels.shares_with(shared.pixels))
    assert_equal(String(shared.pixels), String(source.pixels))


def test_replacing_one_payload_keeps_shared_storage_alive() raises:
    var source = _bytes()
    var shared = Texture(copy=source, share_data=True)
    source.pixels = List[UInt8](length=84, fill=3)
    assert_equal(shared.pixels[0], UInt8(128))
    assert_equal(source.pixels[0], UInt8(3))
    assert_false(source.pixels.shares_with(shared.pixels))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
