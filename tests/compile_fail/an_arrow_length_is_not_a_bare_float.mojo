# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for an arrow helper's length."""

from helpers.arrow import arrow_helper
from math.vector3 import Vector3


def main() raises:
    var arrow = arrow_helper(Vector3(0, 1, 0), Vector3(0, 0, 0), 2.0)
    print(arrow.vertex_count())
