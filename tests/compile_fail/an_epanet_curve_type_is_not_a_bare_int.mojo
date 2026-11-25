# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An EPANET curve type must be a `CurveType`, not a bare integer."""

from extensions.epanet.kinds import CurveType


def main():
    var kind: CurveType = 0
    _ = kind.is_valid()
