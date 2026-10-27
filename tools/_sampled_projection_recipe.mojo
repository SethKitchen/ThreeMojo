# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the sampled projection steps and their comparison texts.

Python still parses those texts. This recipe only says which helper,
which role, and which source text each comparison uses.
"""


def sampled_projection_recipe() -> String:
    """Return the sampled projection steps and comparison texts.

    Returns:
        JSON with the copy rule and the projection steps, in reviewed order.
    """
    return (
        '{"trig_prefix":"_atan","trig_module":"curve_trig.mojo","bounds_module":"curve_bounds.mojo","blend":{"name":"_sample_blend_jet","fields":["first","second"]},"steps":[{"kind":"project","module":"curve_bounds.mojo","name":"_union_points","role":"union","mode":"--project-union","target":"_union_value_points"},{"kind":"project","module":"curve_bounds.mojo","name":"_reference_jet_capture","role":"reference","mode":"--project-reference","target":"_reference_sampled_value"},{"kind":"rename","pairs":[["_sinc_jet","curve_trig.mojo"],["_arc_offset_jet","curve_bounds.mojo"]]},{"kind":"constant","module":"curve_trig.mojo","name":"_constant_sincos_jet","role":"constant","mode":"--project-constant","target":"_constant_sincos_value","constructor_index":2,"constructor":"zero'
        ' = _Interval.point(0.0)","constructor_message":"constant heading'
        " derivative constructor"
        ' changed","pair_index":3,"field":{"prefix":"_ValueJet(result[","suffix":"].rounded_value(),'
        ' zero, zero, 0.0)"},"field_message":"constant heading field projection'
        ' changed"},{"kind":"lane","module":"curve_bounds.mojo","name":"_lane_jet_model_proof","role":"lane","mode":"--project-lane","target":"_lane_value_bound_impl","refusal_index":0,"refusal":"if'
        " proof and not _sum2_supported_environment():\\n        return"
        ' _unknown_value_point()\\n    ","refusal_message":"cached-proof'
        " environment refusal changed or"
        ' moved","capture_index":15,"capture":"if capture:\\n           '
        " captured.record_at = geometry_at\\n            captured.low = low\\n "
        '           captured.high = high\\n    ","capture_message":"capture'
        ' bookkeeping projection changed"}]}'
    )
