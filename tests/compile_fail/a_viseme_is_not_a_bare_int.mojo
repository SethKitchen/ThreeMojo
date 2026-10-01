# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A viseme must be a `Viseme`, not a bare integer."""

from extensions.humanoid.skeleton.head.expression import viseme_recipe


def main() raises:
    _ = viseme_recipe(1)
