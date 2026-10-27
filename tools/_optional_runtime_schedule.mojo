# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the optional-runtime declarations and edge groups.

The live texts still come from the repository. This schedule only says
which declaration each group checks, and which earlier declaration it reuses.
"""


def optional_runtime_schedule() -> String:
    """Return the optional-runtime declaration groups in reviewed order.

    Returns:
        JSON with `before` and `after`. The model-consumer scan stays
        between those two lists.
    """
    return (
        '{"before":['
        + '{"group":"helper","bind":[{"key":"helper","module":"lane_refinement","name":"_same_cache_key","label":"exact'
        ' UInt64 pair helper comparison"}],"edges":["helper"]},'
        + '{"group":"guards","bind":[{"key":"model","module":"curve_objective_model","name":"_try_objective_model"},{"key":"restrict","module":"curve_objective_model","name":"_restrict_objective_model"},{"key":"cut","module":"curve_sample_dispatch","name":"_sample_dispatch_cut"},{"key":"cuts","module":"curve_sample_dispatch","name":"_try_sample_dispatch_cuts"},{"key":"lane","module":"spiral_grouped_lane","name":"_try_grouped_lane_jet"},{"key":"raw","module":"spiral_grouped_roundoff_proof","name":"_try_spiral_grouped_roundoff_envelope"},{"key":"metered","module":"spiral_grouped_roundoff_proof","name":"_try_spiral_grouped_roundoff_envelope_metered"}],"edges":["model","restrict","cut","cuts","lane","raw","metered"]},'
        + '{"group":"origin","bind":[{"key":"origin","module":"spiral_grouped_roundoff_proof","name":"_grouped_origin_error","label":"grouped'
        " origin must use the canonical checked error"
        ' arguments"}],"check":[{"key":"raw","label":"complete X stored-term'
        ' count and origin"}],"edges":["origin","raw"]},'
        + '{"group":"work","bind":[{"key":"work","module":"spiral_grouped_roundoff_proof","name":"_spiral_grouped_roundoff_work","label":"whole'
        ' count work bound"}],"check":[{"key":"lane","label":"whole optional'
        ' union admission"},{"key":"metered","label":"standalone adapter'
        " preserves independent fallback"
        ' reservation"}],"edges":["work","lane","metered"]},'
        + '{"group":"model","bind":[],"check":[{"key":"model","label":"model'
        ' ordered owner"},{"key":"restrict","label":"restriction cannot widen'
        ' owner low"}],"edges":["model","restrict"]},'
        + '{"group":"support","bind":[{"key":"support","module":"curve_minimizer_support","name":"_minimizer_support","label":"actual'
        ' witness lower containment"}],"edges":["support"]},'
        + '{"group":"dispatch","bind":[{"key":"predicate","module":"curve_sample_dispatch","name":"_sample_dispatch_predicate","label":"exact'
        " stored subtraction/clamp dispatch"
        ' predicate"}],"check":[{"key":"cuts","label":"actual predecessor'
        ' sample index"}],"edges":["predicate","cuts"]}'
        + '],"after":['
        + '{"group":"followup","bind":[{"key":"room","module":"curve_objective_model","name":"_objective_followup_room","label":"complete'
        ' overflow-safe integer followup admission"}],"edges":["room"]},'
        + '{"group":"recheck","bind":[{"key":"recheck","module":"curve_objective_model","name":"_objective_recheck_room","label":"complete'
        ' integer cached-closure recheck admission"}],"edges":["recheck"]},'
        + '{"group":"fee","bind":[{"key":"fee","module":"map","name":"_query_node_step_cost","label":"reviewed'
        ' goal node fee"}],"edges":["fee"]}]}'
    )
