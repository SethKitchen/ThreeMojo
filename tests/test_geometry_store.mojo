# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The geometry store's generations: what a cache of a geometry reads to
know that it changed."""

from core.buffer_geometry import BufferGeometry
from core.geometry_store import GeometryId, GeometryStore
from std.testing import TestSuite, assert_equal, assert_raises


def test_a_replaced_or_reused_geometry_has_a_new_generation() raises:
    var store = GeometryStore()
    var first = store.add(BufferGeometry())
    var second = store.add(BufferGeometry())
    assert_equal(store.generation(first), 0)
    store.replace(first, BufferGeometry())
    store.replace(first, BufferGeometry())
    assert_equal(store.generation(first), 2)
    assert_equal(store.generation(second), 0)
    # An id freed by popping and taken again reads as changed.
    _ = store.geometries.pop()
    var again = store.add(BufferGeometry())
    assert_equal(again.value, second.value)
    assert_equal(store.generation(again), 1)
    with assert_raises():
        _ = store.generation(GeometryId(7))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
