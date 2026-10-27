# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the dispatch path, the choice names, and the premise messages.

The live texts still come from the repository. These labels only say which
path is the dispatch source and which message each refusal uses.
"""


def dispatch_labels() -> String:
    """Return the dispatch path, choice names, and premise messages.

    Returns:
        JSON with those labels in reviewed order.
    """
    return (
        '{"dispatch_path":"extensions/carla/curve_sample_dispatch.mojo",'
        + '"current":"current","restore":"restore",'
        + '"unreviewed":"curve support/dispatch contract: unreviewed source'
        ' successor: ",'
        + '"successor_operations":"successor operations changed: ",'
        + '"premise_modules":"interval/environment premise changed: ",'
        + '"seed":"seed",'
        + '"seed_message":"reviewed Map caller premise changed: ",'
        + '"lane":"lane",'
        + '"lane_message":"reviewed lane caller premise changed: ",'
        + '"premise_function":"index or guarded caller premise changed: ",'
        + '"reference":"native predecessor reference changed: ",'
        + '"complete":"complete successor changed: "}'
    )
