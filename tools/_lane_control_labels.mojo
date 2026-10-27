# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the lane-control comparison labels and the frozen reference prefix.

The live declarations still come from the repository. These labels only say
which comparison failed and how the frozen name is spelled.
"""


def lane_control_labels() -> String:
    """Return the lane-control labels and the frozen reference prefix.

    Returns:
        JSON with the labels, the `def` prefix pieces, and the pass line.
    """
    return (
        '{"successor":"lane-control successor module changed",'
        + '"before":"lane-control before declaration drift",'
        + '"after":"lane-control after declaration drift",'
        + '"frozen":"lane-control frozen predecessor changed",'
        + '"premise":"lane-control guarded premise changed: ",'
        + '"producer":"lane-control IEEE producer module changed: ",'
        + '"definition":"def ","call":"(","reference":"_reference",'
        + '"pass":"Lane control-flow migration: PASS"}'
    )
