# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A dose-volume level must be an `AbsorbedDose64`, not a length."""

from extensions.imaging.dvh import DoseVolumeHistogram
from units.si import CUBIC_METER, Length64, METER, Volume64


def main() raises:
    var doses: List[Float64] = [1.0, 2.0]
    var dvh = DoseVolumeHistogram(doses^, Volume64(1e-9, CUBIC_METER))
    _ = dvh.volume_at_dose(Length64(20.0, METER))
