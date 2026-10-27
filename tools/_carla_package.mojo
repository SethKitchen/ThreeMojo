# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the CARLA extension package.

Callers still open the files inside this package. This path only says
where those files live.
"""


def carla_package() -> String:
    """Return the CARLA extension package path.

    Returns:
        The repository directory `extensions/carla`.
    """
    return "extensions/carla"
