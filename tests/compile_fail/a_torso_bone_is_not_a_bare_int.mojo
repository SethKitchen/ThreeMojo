# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A torso bone must be a `TorsoBone`, not a bare integer."""

from extensions.humanoid.skeleton.torso.bones.dimensions import torso_bone_label


def main() raises:
    print(torso_bone_label(2))
