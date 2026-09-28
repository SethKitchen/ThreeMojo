# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pelvic bone must be a `PelvisBone`, not a bare integer."""

from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    pelvis_bone_label,
)


def main() raises:
    print(pelvis_bone_label(2))
