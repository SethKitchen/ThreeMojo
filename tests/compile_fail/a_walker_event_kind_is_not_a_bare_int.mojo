# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A walker event kind must be a `WalkerEventKind`, not a bare integer."""

from extensions.carla.navigation import ignore_event


def main() raises:
    var event = ignore_event()
    event.kind = 2
    print(event.kind.value)
