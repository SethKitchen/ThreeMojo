# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the fresh heading consumers.

The domain proof comes first. The two moment consumers follow it.
"""

from tools._carla_package import carla_package


def heading_consumers() -> String:
    """Return the three heading consumers in reviewed order.

    Returns:
        A JSON object. Each key is a file name and each value is a function.
    """
    return (
        '{"spiral_domain_proof.mojo":"_spiral_proof_branch",'
        + '"spiral_moment_proof.mojo":"_try_spiral_moment_expansion",'
        + '"spiral_moment_table.mojo":"_try_spiral_moment_expansion"}'
    )


def heading_plan() -> String:
    """Return the package path, then the heading consumers.

    Returns:
        JSON with `package` and `consumers` in that order.
    """
    return (
        '{"package":"'
        + carla_package()
        + '","consumers":'
        + heading_consumers()
        + "}"
    )
