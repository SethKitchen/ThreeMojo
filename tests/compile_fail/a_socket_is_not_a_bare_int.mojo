# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A socket must be a `Socket`, not a bare integer."""

from extensions.attire.sockets import socket_joint


def main() raises:
    _ = socket_joint(1)
