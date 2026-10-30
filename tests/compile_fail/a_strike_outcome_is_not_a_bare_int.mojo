# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A strike's outcome must be a `StrikeOutcome`, not a bare integer."""

from extensions.village.combat import outcome_word


def main() raises:
    print(outcome_word(1))
