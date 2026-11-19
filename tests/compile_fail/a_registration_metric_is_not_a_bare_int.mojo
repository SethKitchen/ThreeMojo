# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A registration metric must be a `RegistrationMetric`, not a bare integer.
"""

from extensions.imaging.ids import require_metric


def main() raises:
    require_metric(1)
