# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Checks that the long-bone suites share."""

from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from std.testing import assert_true


def assert_outward_and_short(bone: BufferGeometry) raises:
    """Refuse a triangle that winds against its stored normals or spans a
    gap.

    Args:
        bone: The bone's surface.

    Raises:
        Error: If an edge is 8 centimeters or longer, or a triangle with
            area faces away from the mean of its corner normals.
    """
    ref pos = bone.attribute_view(String(POSITION))
    ref normals = bone.attribute_view(String(NORMAL))
    for triangle in range(bone.triangle_count()):
        var ia = bone.corner_index(triangle, 0)
        var ib = bone.corner_index(triangle, 1)
        var ic = bone.corner_index(triangle, 2)
        var a = pos.vector3(ia)
        var b = pos.vector3(ib)
        var c = pos.vector3(ic)
        var ab = b - a
        var ac = c - a
        var bc = c - b
        assert_true(ab.length() < Float32(0.08))
        assert_true(ac.length() < Float32(0.08))
        assert_true(bc.length() < Float32(0.08))
        ab.cross(ac)
        if ab.length() < Float32(1e-10):
            continue
        var mean = (
            normals.vector3(ia) + normals.vector3(ib) + normals.vector3(ic)
        )
        assert_true(ab.dot(mean) > 0)
