# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A walker event result must be an `EventResult`, not a bare integer."""

from extensions.carla.navigation import EVENT_END


def main() raises:
    var result = EVENT_END
    result = 1
    print(result.value)
