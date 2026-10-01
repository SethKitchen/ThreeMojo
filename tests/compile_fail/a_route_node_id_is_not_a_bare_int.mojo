# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A route node id must be a `RouteNodeId`, not a bare integer."""

from extensions.carla.agents_route import RouteNodeId


def main() raises:
    var node = RouteNodeId(0)
    node = 3
    print(node.value)
