# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the companion migration records.

Each checker still reads its own migration. These paths are the extra
records those checks also open.
"""


def record_paths() -> String:
    """Return the companion migration record paths.

    Returns:
        JSON with `accepted`, `lane_control`, `reviewed_cleanup`,
        `winner_sign`, and `runtime_pins`.
    """
    return (
        '{"accepted":"tools/carla_lane_oracle/accepted-successor-migration.json",'
        + '"lane_control":"tools/carla_lane_oracle/lane-control-migration.json",'
        + '"reviewed_cleanup":"tools/carla_lane_oracle/reviewed-cleanup-migration.json",'
        + '"winner_sign":"tools/carla_lane_oracle/winner-sign-query-migration.json",'
        + '"runtime_pins":"tools/carla_lane_oracle/runtime-source-pins.json"}'
    )
