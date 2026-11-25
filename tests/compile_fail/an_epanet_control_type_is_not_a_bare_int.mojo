# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An EPANET control type must be a `ControlType`, not a bare integer."""

from extensions.epanet.kinds import ControlType


def main():
    var kind: ControlType = 0
    _ = kind.is_valid()
