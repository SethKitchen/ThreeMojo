# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A humanoid capability must be typed."""

from extensions.humanoid.fidelity import require_humanoid_use


def main() raises:
    require_humanoid_use(0)
