# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A hairstyle must be a `HairStyle`, not a bare integer."""

from extensions.humanoid.skeleton.head.hair.styles import hair_style_path


def main() raises:
    print(hair_style_path(1))
