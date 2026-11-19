# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic dose of the RT Dose fixtures.

Run it from the repository root: `mojo run -I . tools/make_rtdose.mojo`.
It writes `assets/dicom/rtdose_field.txt`: the dose in Gy of each voxel
of a grid of 24 by 20 by 4 voxels of 2 by 2.5 by 3 mm, from (-23, -24, 0)
mm, one voxel a line with i fastest and k from z = 0. The dose is a
Gaussian of 62 Gy about (1, -2, 4) mm, with deviations of 9 mm across and
7 mm along z, plus uniform noise from 0 to 1.5 Gy.
`assets/dicom/make_rtdose.py` then writes the DICOM files with pydicom.
"""

from extensions.numerics.elementary import precise_exp
from extensions.numerics.noise import Xorshift64
from tools._fixtures import SEED, write_text


def main() raises:
    """Write the dose.

    Raises:
        Error: If the file cannot be written.
    """
    var noise = Xorshift64(SEED)
    var text = String()
    for k in range(4):
        for j in range(20):
            for i in range(24):
                var x = -23.0 + Float64(i) * 2.0
                var y = -24.0 + Float64(j) * 2.5
                var z = Float64(k) * 3.0
                var r2 = ((x - 1.0) ** 2 + (y + 2.0) ** 2) / (2.0 * 81.0) + (
                    z - 4.0
                ) ** 2 / (2.0 * 49.0)
                var dose = 62.0 * precise_exp(-r2) + noise.between(0.0, 1.5)
                text += String(dose, "\n")
    write_text("assets/dicom/rtdose_field.txt", text)
