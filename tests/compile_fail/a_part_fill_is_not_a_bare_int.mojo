# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A part fill must be a `PartFill`, not a bare integer."""

from extensions.scan.parts import PartFill


def main():
    var kind: PartFill = 0
    _ = kind.is_valid()
