# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A solve status must be a `SolveStatus`, not a bare integer."""

from extensions.numerics.iterative import SolveStatus


def main():
    var status: SolveStatus = 0
    _ = status.is_valid()
