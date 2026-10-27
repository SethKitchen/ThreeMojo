# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the rounded LINE singleton paths and the consumer messages.

The live texts still come from the repository. These names only say which
module is the lane and which module is the rounded line.
"""


def singleton_paths() -> String:
    """Return the lane path, the rounded-line path, and the messages.

    Returns:
        JSON with `lane`, `rounded_line`, `import_scope`, and `declaration`.
    """
    return (
        '{"lane":"extensions/carla/lane_refinement.mojo",'
        + '"rounded_line":"extensions/carla/curve_rounded_line.mojo",'
        + '"import_scope":"consumer import scope changed: ",'
        + '"declaration":"consumer/reference declaration changed: "}'
    )
