# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A flow thermal kind must be a `ThermalKind`, not a bare integer."""

from extensions.cfd.kinds import ThermalKind


def main():
    var kind: ThermalKind = 0
    _ = kind.is_valid()
