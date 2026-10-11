# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A canonical-to-visual mapping must be typed."""

from extensions.humanoid.mapping import require_physical_mapping


def main() raises:
    require_physical_mapping(0)
