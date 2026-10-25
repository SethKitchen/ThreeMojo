# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A blow's outcome must be a `BlowOutcome`, not a bare integer."""

from extensions.attire.estimate import require_outcome


def main() raises:
    require_outcome(1)
