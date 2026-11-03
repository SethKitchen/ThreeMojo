# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A hazard must be a `Hazard`, not a bare integer."""

from extensions.chemistry.kinds import Hazard


def main():
    var hazard: Hazard = 0
    _ = hazard.is_valid()
