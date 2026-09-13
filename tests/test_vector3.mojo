# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.vector3`."""

from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


def test_dot_of_parallel_vectors() raises:
    assert_equal(Vector3(3, 4, 0).dot(Vector3(3, 4, 0)), Float32(25))


def test_dot_of_perpendicular_vectors_is_zero() raises:
    assert_equal(Vector3(1, 0, 0).dot(Vector3(0, 1, 0)), Float32(0))


def test_length() raises:
    assert_equal(Vector3(3, 4, 0).length(), Float32(5))


def test_length_of_zero_vector() raises:
    assert_equal(Vector3(0, 0, 0).length(), Float32(0))


def test_add_mutates_in_place() raises:
    var v = Vector3(1, 2, 3)
    v.add(Vector3(10, 20, 30))
    assert_equal(v.x, Float32(11))
    assert_equal(v.y, Float32(22))
    assert_equal(v.z, Float32(33))


def test_assignment_copies_rather_than_aliases() raises:
    # ImplicitlyCopyable means `b` is a separate value, NOT a three.js alias.
    var a = Vector3(1, 0, 0)
    var b = a
    b.add(Vector3(0, 1, 0))
    assert_equal(a.y, Float32(0))
    assert_equal(b.y, Float32(1))


def test_cross_of_basis_vectors() raises:
    var v = Vector3(1, 0, 0)
    v.cross(Vector3(0, 1, 0))
    assert_equal(v.x, Float32(0))
    assert_equal(v.y, Float32(0))
    assert_equal(v.z, Float32(1))


def test_cross_is_anticommutative() raises:
    var v = Vector3(0, 1, 0)
    v.cross(Vector3(1, 0, 0))
    assert_equal(v.z, Float32(-1))


def test_cross_uses_original_components_throughout() raises:
    # Regression guard: computing z from an already-overwritten x would give 0.
    var v = Vector3(1, 2, 3)
    v.cross(Vector3(4, 5, 6))
    assert_equal(v.x, Float32(-3))
    assert_equal(v.y, Float32(6))
    assert_equal(v.z, Float32(-3))


def test_cross_of_parallel_vectors_is_zero() raises:
    var v = Vector3(2, 4, 6)
    v.cross(Vector3(1, 2, 3))
    assert_equal(v.length(), Float32(0))


def test_normalize_gives_unit_length() raises:
    var v = Vector3(3, 4, 0)
    v.normalize()
    assert_almost_equal(v.length(), Float32(1))
    assert_almost_equal(v.x, Float32(0.6))
    assert_almost_equal(v.y, Float32(0.8))


def test_normalize_leaves_zero_vector_unchanged() raises:
    # Covers the `magnitude > 0` guard's false branch.
    var v = Vector3(0, 0, 0)
    v.normalize()
    assert_equal(v.length(), Float32(0))
    assert_true(v.x == 0 and v.y == 0 and v.z == 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
