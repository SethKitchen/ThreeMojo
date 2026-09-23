# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a glTF camera's kind."""

from loaders.gltf import GLTF_PERSPECTIVE, GltfCameraKind


def main() raises:
    var kind: GltfCameraKind = 1
    print(kind == GLTF_PERSPECTIVE)
