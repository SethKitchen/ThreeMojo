# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the reviewed migration records.

Each checker still reads its own record. These fields only name that file
and the digest the checker compares.
"""


def migration_records() -> String:
    """Return the reviewed migration paths and digests.

    Returns:
        JSON with one path and one digest for each reviewed checker.
    """
    return (
        '{"cleanup":{"path":"tools/carla_lane_oracle/reviewed-cleanup-migration.json",'
        + '"sha":"01753344fe01d885eb3bbaf253815bca01816c57c09b6e7cc1c3a233808b42a9"},'
        + '"render":{"path":"tools/carla_lane_oracle/render-actor-reuse-successor.json",'
        + '"sha":"c4d146fe145289a1ad443956d2941d1e90186d448b8056f8be97d72f4f672771"},'
        + '"singleton":{"path":"tools/carla_lane_oracle/rounded-line-singleton-migration.json",'
        + '"sha":"e4a0eb6c9e527dd66b2b803ee69754334feecc9bea33ce001cdf584d3a693506"},'
        + '"speed":{"path":"tools/carla_lane_oracle/speed-parser-successor.json",'
        + '"sha":"47e949673fb8740816c06d455654c7e7ae43f65ce7d7568a201e83ae16c49364"},'
        + '"runtime":{"path":"tools/carla_lane_oracle/runtime-boundary-successor.json",'
        + '"sha":"992854b1191bd365fca3e5e8d3a7fc751ac2eb3196b33684e04ebad833baab00"},'
        + '"dispatch":{"path":"tools/carla_lane_oracle/curve-support-dispatch-migration.json",'
        + '"sha":"1a6d7794bf0869a1e717685e556d8400e075ab97917ce8d855da6bd61c3ee19f"},'
        + '"invariant":{"path":"tools/carla_lane_oracle/coverage-invariant-migration.json",'
        + '"sha":"56a72d9bccbf9e7b8a6b51db2b9944ef4bbf55d9bcc7311f7f9615be3b3b36ac"},'
        + '"frozen":{"path":"tools/carla_lane_oracle/frozen-arc-producer-migration.json",'
        + '"sha":"70091e23400193257514363570187b47890e3c08c352fe79eb08bf291737cc9f"}}'
    )
