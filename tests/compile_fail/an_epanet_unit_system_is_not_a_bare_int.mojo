# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An EPANET unit system must be a `UnitSystem`, not a bare integer."""

from extensions.epanet.kinds import UnitSystem


def main():
    var kind: UnitSystem = 0
    _ = kind.is_valid()
