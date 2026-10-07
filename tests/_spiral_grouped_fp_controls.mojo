# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Hook for the maintained Sum2 hostile-FP suite; no process mode changes.

Construct arguments before changing CPU controls. Call this hook inside the
existing saved/restored hostile-mode block. It adds no C fixture or new mode.
"""

from extensions.carla.curve_interval import _Jet
from extensions.carla.curve_sum2 import _sum2_supported_environment
from extensions.carla.geometry import RoadGeometry
from extensions.carla.spiral_grouped_roundoff_proof import (
    _try_spiral_grouped_roundoff_envelope,
    _try_spiral_grouped_roundoff_envelope_metered,
)
from std.testing import assert_equal, assert_false


def _assert_grouped_refuses_hostile_state(
    geometry: RoadGeometry, d: _Jet, pieces: Int
) raises:
    assert_false(_sum2_supported_environment())
    assert_false(
        Bool(_try_spiral_grouped_roundoff_envelope(geometry, d, pieces))
    )
    var saved_terms = 7
    var result = _try_spiral_grouped_roundoff_envelope_metered(
        geometry, d, pieces, saved_terms, 10000
    )
    assert_false(Bool(result))
    assert_equal(saved_terms, 7)
