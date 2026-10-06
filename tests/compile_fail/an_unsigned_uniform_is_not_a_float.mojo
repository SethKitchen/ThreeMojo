# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An exact unsigned uniform requires explicitly typed unsigned values."""

from materials.nodes import NodeProgram


def main() raises:
    var program = NodeProgram()
    program.set_uniform_uint("word", Float32(16777217))
