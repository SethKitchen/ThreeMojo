# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for how an FBX layer is mapped."""

from loaders.fbx import DIRECT, FbxLayer


def main() raises:
    var layer = FbxLayer(0, DIRECT, List[Float64](), List[Int](), 3)
    print(layer.size)
