# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a node JSON type: name it with
`JSON_VAR_NODE` and the rest, or read it with `node_json_type_of`."""

from loaders.node_loader import JSON_CONST_NODE, NodeJsonType


def main() raises:
    var type: NodeJsonType = 3
    print(type == JSON_CONST_NODE)
