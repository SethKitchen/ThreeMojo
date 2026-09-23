# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a glTF container."""

from core.assets import Assets
from core.scene import Scene
from exporters.gltf import export_gltf


def main() raises:
    var files = export_gltf(Scene(), Assets(), 2)
    print(len(files.document))
