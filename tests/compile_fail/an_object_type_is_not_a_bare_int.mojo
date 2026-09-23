# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an object type: name it with
`OBJECT3D_TYPE` or `GROUP_TYPE`."""

from core.object3d import Object3D


def main() raises:
    var node = Object3D()
    node.object_type = 1
    print(node.name)
