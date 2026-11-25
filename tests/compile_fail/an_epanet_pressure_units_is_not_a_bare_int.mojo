# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An EPANET pressure unit must be a `PressureUnits`, not a bare integer."""

from extensions.epanet.kinds import PressureUnits


def main():
    var kind: PressureUnits = 0
    _ = kind.is_valid()
