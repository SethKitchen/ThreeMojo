# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A groundwater kind must be a `CellKind`, not a bare integer."""

from extensions.groundwater.kinds import CellKind


def main():
    var kind: CellKind = 0
    _ = kind.is_valid()
