# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A traffic manager command's kind must be a `CommandKind`, not a bare
integer."""

from extensions.carla.traffic_manager_shared import no_command


def main() raises:
    var command = no_command()
    command.kind = 2
    print(command.kind.value)
