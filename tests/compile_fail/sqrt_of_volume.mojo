# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A volume has an odd length exponent, so its root is not expressible."""

from units.si import Volume


def main() raises:
    print(Volume(8.0).sqrt().value)
