# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A kind of sound must be a `SoundKind`, not a bare integer."""

from extensions.village.sound import sound_length


def main() raises:
    print(sound_length(1))
