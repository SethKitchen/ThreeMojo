# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A canonical record part must be typed."""

from extensions.humanoid.canonical import canonical_part_label


def main() raises:
    _ = canonical_part_label(0)
