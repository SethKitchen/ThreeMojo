# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the sampled reference modules and the closure groups.

The graph digests stay in their own table. This list is the separate
reviewed order those digests must match.
"""


def sampled_closure() -> String:
    """Return the sampled reference names and the closure groups.

    Returns:
        JSON with the reference names, the reviewed module, the primitive
        module, the syntax module, the two closure groups, and the bounds
        path. The import block stays with those names.
    """
    return (
        '{"reference_names":["curve_bounds.mojo","curve_trig.mojo","curve_interval.mojo"],'
        + '"reviewed":"curve_bounds.mojo","primitive":"curve_interval.mojo",'
        + '"syntax":"curve_trig.mojo",'
        + '"groups":["stored_arithmetic","canonical_accumulation"],'
        + '"closure":"wrong reference-module closure",'
        + '"primitive_message":"Jet primitive graph changed; renewed'
        ' derivative-independence review required",'
        + '"reference_changed":"reference module changed; renewed review'
        ' required: ",'
        + '"shared":"shared generic or full-Jet bridge changed: ",'
        + '"diverged":"sampled helper diverged: ",'
        + '"frame":"sampled source frame changed",'
        + '"step":"sampled projection step changed",'
        + '"function":"missing or ambiguous function: ",'
        + '"primitive_declaration":"unsupported primitive declaration",'
        + '"value_gate":"sampled value gate: ",'
        + '"jet_gate":"sampled jet gate: ",'
        + '"bounds_path":"extensions/carla/curve_bounds.mojo",'
        + '"imports":"from extensions.carla.curve_interval import (\\n   '
        " _stored_difference,\\n    _stored_half,\\n   "
        " _stored_blend_error,\\n    _Interval,\\n    _ValueJet,\\n   "
        " _without_derivatives,\\n)\\nfrom extensions.carla.curve_bounds"
        " import (\\n    _sample_index,\\n    _intersect_ideal_bounds,\\n   "
        " _lane_jet,\\n)\\nfrom extensions.carla.curve_trig import (\\n   "
        " _expression_polynomial,\\n    _uncertain_expression,\\n   "
        " _sincos_expression,\\n    _PI,\\n    _HALF_PI,\\n   "
        " _QUARTER_PI,\\n    _ATAN_REDUCE,\\n    _ATAN_COEFFICIENTS,\\n   "
        " _SIN_COEFFICIENTS,\\n    _PHASE_LIMIT,\\n    _sign_bit,\\n   "
        " _curve_cos,\\n    _curve_sin,\\n    _curve_atan2,\\n)\\nfrom"
        " extensions.carla.geometry import (\\n    RoadGeometry,\\n   "
        " PARAM_POLY3,\\n    POLY3,\\n    LINE,\\n    ARC,\\n   "
        " SPIRAL,\\n)\\nfrom std.math import isfinite\\nfrom"
        " extensions.carla.polynomial import CubicPolynomial\\nfrom"
        " extensions.carla.road import Road\\nfrom extensions.carla.road_info"
        ' import info_index\\nfrom math.vector3 import Vector3\\n"}'
    )
