# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A triangle-budget reason must be a typed value, not a bare integer."""

from extensions.humanoid.skeleton.simplify import TriangleBudgetResult


def main() raises:
    var result = TriangleBudgetResult(1, 1, 1, 1, 0)
    _ = result.has_reason(0)
