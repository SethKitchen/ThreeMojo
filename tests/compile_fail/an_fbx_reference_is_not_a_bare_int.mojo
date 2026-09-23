# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for how an FBX layer is referenced."""

from loaders.fbx import BY_POLYGON, FbxLayer


def main() raises:
    var layer = FbxLayer(BY_POLYGON, 1, List[Float64](), List[Int](), 3)
    print(layer.size)
