# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A head lymph group must be a `HeadLymph`, not a bare integer."""

from extensions.humanoid.skeleton.head.lymph.dimensions import head_lymph_label


def main() raises:
    print(head_lymph_label(1))
