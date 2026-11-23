# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pipe network formula must be a `HeadLossFormula`, not a bare integer."""

from extensions.hydraulics.kinds import HeadLossFormula


def main():
    var formula: HeadLossFormula = 0
    _ = formula.is_valid()
