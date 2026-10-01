# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A mesh quality must be a `Quality`, not a bare integer."""

from extensions.humanoid.quality import anatomy_detail


def main() raises:
    print(anatomy_detail(2))
