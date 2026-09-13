# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Adding a length to a duration must not compile."""

from units.si import Duration, Length, METRE, SECOND


def main() raises:
    var bad = Length(1.0, METRE) + Duration(1.0, SECOND)
    print(bad.value)
