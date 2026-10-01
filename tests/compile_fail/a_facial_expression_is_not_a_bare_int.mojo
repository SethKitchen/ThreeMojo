# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A facial expression must be a `FacialExpression`, not a bare integer."""

from extensions.humanoid.skeleton.head.expression import expression_recipe


def main() raises:
    _ = expression_recipe(1)
