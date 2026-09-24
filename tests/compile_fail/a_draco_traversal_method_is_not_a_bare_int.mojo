# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Draco traversal method."""

from loaders.draco_mesh import DRACO_DEPTH_FIRST


def main() raises:
    var method = DRACO_DEPTH_FIRST
    method = 1
    print(method.is_valid())
