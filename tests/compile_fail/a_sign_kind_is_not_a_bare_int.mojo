# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sign kind must be a `SignKind`, not a bare integer."""

from extensions.carla.traffic_sign import STOP_SIGN, sign_type_id


def main() raises:
    print(sign_type_id(0, ""))
