# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a frustum's coordinate system."""

from math.frustum import Frustum
from math.matrix4 import Matrix4


def main() raises:
    var bad = Frustum.from_projection_matrix(Matrix4(), 2000)
    print(bad.planes[0].constant)
