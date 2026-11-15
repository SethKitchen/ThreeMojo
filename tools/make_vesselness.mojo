# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the synthetic volume of the vesselness tests.

Run it from the repository root: `mojo run -I . tools/make_vesselness.mojo`.
It writes `assets/vesselness/volume.txt`: the 20 by 18 by 16 voxels of 1
mm, one 32-bit value a line, with x the fastest axis. The volume holds a
bright tube along (1, 0.5, 0.25) through (8, 8, 6) mm, of height 100 and
a Gaussian profile of 1.2 mm; a bright blob at (14, 4, 10) mm, of height
80 and 2 mm; and a bright plate at z = 13 mm, of height 40 and 1 mm,
where x is 12 mm or more. The tests and
`assets/vesselness/make_vesselness.py` both read it.
"""

from extensions.numerics.elementary import precise_exp
from std.math import sqrt
from tools._fixtures import write_text


def main() raises:
    """Write the volume.

    Raises:
        Error: If the file cannot be written.
    """
    var ux = 1.0
    var uy = 0.5
    var uz = 0.25
    var norm = sqrt(ux * ux + uy * uy + uz * uz)
    ux /= norm
    uy /= norm
    uz /= norm
    var text = String()
    for k in range(16):
        for j in range(18):
            for i in range(20):
                var dx = Float64(i) - 8.0
                var dy = Float64(j) - 8.0
                var dz = Float64(k) - 6.0
                var along = dx * ux + dy * uy + dz * uz
                var d2 = dx * dx + dy * dy + dz * dz - along * along
                var v = 100.0 * precise_exp(-d2 / (2.0 * 1.2 * 1.2))
                var bx = Float64(i) - 14.0
                var by = Float64(j) - 4.0
                var bz = Float64(k) - 10.0
                v += 80.0 * precise_exp(-(bx * bx + by * by + bz * bz) / 8.0)
                if i >= 12:
                    var pz = Float64(k) - 13.0
                    v += 40.0 * precise_exp(-pz * pz / 2.0)
                text += String(Float32(v), "\n")
    write_text("assets/vesselness/volume.txt", text)
