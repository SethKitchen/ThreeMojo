# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the frozen runtime-pin labels and the public successor message.

The live pin bytes still come from the repository. These labels only say
which failure may be relabeled and which digest kind each check uses.
"""


def frozen_pin_labels() -> String:
    """Return the frozen runtime-pin labels and the public message.

    Returns:
        JSON with the premise text, the decision names, and the digest kinds.
    """
    return (
        '{"premise":"full-audit cleanup successor: unchanged premise, record or'
        ' fixture changed: tools/carla_lane_oracle/runtime-source-pins.json",'
        + '"expected_error_prefix":"unreviewed complete successor: ",'
        + '"stage_error":"error","stage_cause":"cause",'
        + '"decision_cause":"cause","decision_relabel":"relabel",'
        + '"public":"frozen ARC producer contract: unreviewed runtime pin'
        ' successor",'
        + '"guard":"guard","after":"after","before":"before","groups":"groups"}'
    )
