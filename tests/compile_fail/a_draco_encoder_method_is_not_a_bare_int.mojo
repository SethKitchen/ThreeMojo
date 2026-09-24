# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Draco encoder method."""

from exporters.draco import DRACO_MESH_EDGEBREAKER_ENCODING


def main() raises:
    var method = DRACO_MESH_EDGEBREAKER_ENCODING
    method = 0
    print(method.is_valid())
