# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the selection contract and the predecessor messages.

The live producer texts still come from the repository. These labels only
say which record to read and which refusal each check reports.
"""


def selection_labels() -> String:
    """Return the selection contract path and the predecessor messages.

    Returns:
        JSON with `contract`, `producer_set`, `predecessor`, `body`,
        `scalar`, and `interval`.
    """
    return (
        '{"contract":"tools/carla_lane_oracle/selection-finiteness-contract.json",'
        + '"producer_set":"Wrong selection producer set",'
        + '"predecessor":"Wrong selection predecessor module",'
        + '"body":"Selection complete successor body changed",'
        + '"scalar":"Missing or ambiguous selector constant",'
        + '"interval":"e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11"}'
    )
