# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's mood must be a `Mood`, not a bare integer."""

from extensions.village.talk import mood_line


def main() raises:
    print(mood_line(1, 0))
