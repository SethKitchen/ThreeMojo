# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Negative indices are refused before fallible geometry counts."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from geometries.surface_sampler import MeshSurfaceSampler
from math.utils import SeededRandom
from std.testing import TestSuite, assert_equal, assert_raises


def test_negative_indices_precede_missing_positions() raises:
    var geometry = BufferGeometry()
    with assert_raises(contains="Triangle index out of range"):
        _ = geometry.corner_index(-1, 0)
    with assert_raises(
        contains="The triangle stream has no slot of that number"
    ):
        _ = geometry.vertex_at(-1)
    with assert_raises(contains="position"):
        _ = geometry.corner_index(0, 0)
    with assert_raises(contains="position"):
        _ = geometry.vertex_at(0)


def test_negative_face_precedes_ragged_positions() raises:
    var geometry = BufferGeometry()
    var positions: List[Float32] = [0, 0, 0]
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    var sampler = MeshSurfaceSampler(geometry, SeededRandom(1))
    with assert_raises(contains="No triangle has that index"):
        _ = sampler.sample_face(-1)
    with assert_raises(contains="The positions do not make whole triangles"):
        _ = sampler.sample_face(0)


def test_nonnegative_indices_keep_their_bounds() raises:
    var geometry = BufferGeometry()
    var positions: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    assert_equal(geometry.corner_index(0, 2), 2)
    assert_equal(geometry.vertex_at(2), 2)
    with assert_raises(contains="Triangle index out of range"):
        _ = geometry.corner_index(1, 0)
    with assert_raises(
        contains="The triangle stream has no slot of that number"
    ):
        _ = geometry.vertex_at(3)
    var sampler = MeshSurfaceSampler(geometry, SeededRandom(1))
    _ = sampler.sample_face(0)
    with assert_raises(contains="No triangle has that index"):
        _ = sampler.sample_face(1)


def test_negative_attribute_index_precedes_mutated_item_size() raises:
    var values: List[Float32] = [1, 2, 3]
    var attribute = BufferAttribute(values^, 3)
    # item_size is public. A negative index needs no division by it.
    attribute.item_size = 0
    with assert_raises(contains="Attribute vertex index out of range"):
        _ = attribute.component(-1, 0)
    var destination_values: List[Float32] = [0]
    var destination = BufferAttribute(destination_values^, 1)
    destination.item_size = 0
    with assert_raises(contains="Attribute vertex index out of range"):
        destination.copy_at(0, attribute, -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
