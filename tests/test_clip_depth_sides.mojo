# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named depth clipping sides keep their documented camera-space half."""

from renderers.clip import _DepthClipSide, _KEEP_FARTHER, _KEEP_NEARER, _inside
from std.testing import TestSuite, assert_false, assert_true


def test_only_the_two_depth_sides_are_valid() raises:
    assert_true(_KEEP_FARTHER.is_valid())
    assert_true(_KEEP_NEARER.is_valid())
    assert_false(_DepthClipSide(-1).is_valid())
    assert_false(_DepthClipSide(2).is_valid())


def test_farther_keeps_smaller_z_and_nearer_keeps_larger_z() raises:
    # The same half-spaces apply in front of or behind the camera.
    var planes: List[Float32] = [-3, 0, 3]
    for plane_z in planes:
        assert_true(_inside[_KEEP_FARTHER](plane_z - 1, plane_z))
        assert_true(_inside[_KEEP_FARTHER](plane_z, plane_z))
        assert_false(_inside[_KEEP_FARTHER](plane_z + 1, plane_z))
        assert_false(_inside[_KEEP_NEARER](plane_z - 1, plane_z))
        assert_true(_inside[_KEEP_NEARER](plane_z, plane_z))
        assert_true(_inside[_KEEP_NEARER](plane_z + 1, plane_z))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
