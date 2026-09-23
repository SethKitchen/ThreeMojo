# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare int must not stand in for what a render target's attachment
holds: name it with `OUTPUT_COLOR` or `OUTPUT_NORMAL`."""

from render.target import FLOAT_TARGET, TargetOutput, check_target


def main() raises:
    var outputs: List[TargetOutput] = [0, 1]
    check_target(FLOAT_TARGET, outputs)
