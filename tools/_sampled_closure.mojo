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
        module, the syntax module, and the two closure groups.
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
        + '"jet_gate":"sampled jet gate: "}'
    )
