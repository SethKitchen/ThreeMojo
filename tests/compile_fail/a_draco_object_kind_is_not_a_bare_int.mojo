# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the kind of object a Draco file is
exported from."""

from exporters.draco import DRACO_EXPORT_MESH


def main() raises:
    var kind = DRACO_EXPORT_MESH
    kind = 1
    print(kind.is_valid())
