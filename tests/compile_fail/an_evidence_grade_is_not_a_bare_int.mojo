# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An evidence grade must be an `Evidence`, not a bare integer."""

from extensions.anatomy.evidence import evidence_label


def main() raises:
    print(evidence_label(1))
