# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an animation event kind."""

from animation.animation_mixer import AnimationEvent


def main() raises:
    var bad = AnimationEvent(1, 0, 0, 1)
    print(bad.action)
