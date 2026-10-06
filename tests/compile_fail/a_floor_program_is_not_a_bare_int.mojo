# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A floor program must be a `FloorProgram`, not a bare integer."""

from extensions.building.generate.plan import FloorProgram


def main():
    var id: FloorProgram = 0
    _ = id.is_valid()
