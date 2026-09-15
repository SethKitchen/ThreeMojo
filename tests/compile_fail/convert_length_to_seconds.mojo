# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reading a length in seconds must not compile."""

from units.si import Length, METER, SECOND


def main() raises:
    print(Length(1.0, METER).to(SECOND))
