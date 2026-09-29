# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Head contents must be `HeadContents`, not a bare integer."""

from extensions.humanoid.skeleton.head.contents import HeadContents


def main() raises:
    print(HeadContents(1).plus(3).value)
