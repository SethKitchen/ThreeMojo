# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A STEP value kind must be a `StepKind`, not a bare integer."""

from extensions.building.ifc.step import StepKind


def main():
    var kind: StepKind = 0
    _ = kind.is_valid()
