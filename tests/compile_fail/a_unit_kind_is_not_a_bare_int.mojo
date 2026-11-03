# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A unit kind must be a `UnitKind`, not a bare integer."""

from extensions.chemistry.flowsheet import UnitKind


def main():
    var kind: UnitKind = 0
    _ = kind.is_valid()
