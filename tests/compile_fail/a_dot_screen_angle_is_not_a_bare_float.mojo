# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a dot screen's angle: degrees and
radians would be indistinguishable."""

from postprocessing.composer import dot_screen_pass


def main() raises:
    var bad = dot_screen_pass(angle=1.57)
    print(bad.scale)
