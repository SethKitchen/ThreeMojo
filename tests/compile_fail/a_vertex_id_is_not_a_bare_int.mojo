# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A vertex id must be a `VertexId`, not a bare integer."""

from extensions.topology.ids import VertexId


def main():
    var id: VertexId = 0
    _ = id.is_valid()
