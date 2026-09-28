# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pelvic lymph part must be a `PelvisLymph`, not a bare integer."""

from extensions.humanoid.skeleton.pelvis.lymph.dimensions import (
    pelvis_lymph_label,
)


def main() raises:
    print(pelvis_lymph_label(2))
