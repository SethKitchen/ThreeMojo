# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A body plan must be a `BodyPlan`, not a bare integer."""

from extensions.animals.anatomy.tissue import segment_of


def main() raises:
    print(segment_of(0, "head"))
