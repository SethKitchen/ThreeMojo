# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Repeat the complete small-world control after a shared-host timing outlier.

Keep this separate from the original full matrix. Do not replace or discard
its samples. The nine native repetitions have the same setup and checks.
"""

from bench.physics_snapshot_bench import _measure_small
from bench.physics_static_bench import _Meter


def main() raises:
    """Print a nine-sample repeat of every small-world case.

    Raises:
        Error: If construction or exact parity fails.
    """
    var meter = _Meter("")
    print(
        "group,phase,static,moving,distribution,repetition,ns,peak_bytes,total_bytes,allocations,live_bytes,work,pairs,checksum,geometry_bytes,index_bytes,metadata_bytes"
    )
    for count in [0, 1, 4, 8, 16, 32, 64]:
        for distribution in range(4):
            _measure_small(count, distribution, meter, 9)
