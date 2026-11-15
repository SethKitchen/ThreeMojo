# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write DCE-MRI reference curves with dcmri, a Python toolbox for DCE-MRI.

    python3 make_dce.py > dce_expected.txt

Run it with dcmri 0.6.20 and numpy. The times are 0 to 297.5 s in steps
of 2.5 s, from the arrival of the bolus. Each line holds a name and one
value for each time:

- `times`: the times, in seconds.
- `blood`: dcmri's Parker population AIF, in mM of blood.
- `plasma`: the blood over 1 - 0.42, the hematocrit.
- `standard`: a standard Tofts tissue, Ktrans 0.25 /min and ve 0.3.
- `extended`: an extended Tofts tissue, Ktrans 0.12 /min, ve 0.45 and
  vp 0.06.

A tissue is `ve * expconv(plasma, ve / Ktrans) + vp * plasma`. dcmri's
`expconv` is exact for a curve that is linear between its samples.
"""

import dcmri
import numpy

times = numpy.arange(0, 300, 2.5)
blood = 1000.0 * dcmri.aif_parker(times)
plasma = blood / (1.0 - 0.42)


def tissue(ktrans, ve, vp):
    # Ktrans in 1/min; expconv takes the time constant in seconds.
    return ve * dcmri.utils.expconv(plasma, 60.0 * ve / ktrans, times) + vp * plasma


rows = [
    ("times", times),
    ("blood", blood),
    ("plasma", plasma),
    ("standard", tissue(0.25, 0.3, 0.0)),
    ("extended", tissue(0.12, 0.45, 0.06)),
]
for name, values in rows:
    print(name, " ".join(repr(float(v)) for v in values))
