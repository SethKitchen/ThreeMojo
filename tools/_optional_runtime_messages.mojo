# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the optional-runtime contract messages.

The checks still run in their existing order. These texts only say how a
failure is reported.
"""


def optional_runtime_messages() -> String:
    """Return the optional-runtime contract messages.

    Returns:
        JSON with the prefix, the fragment marker, and the set messages.
    """
    return (
        '{"prefix":"optional runtime contract: ",'
        + '"move":"unsupported move-token placement",'
        + '"fragment":"invalid checker fragment:",'
        + '"fresh_fragment":"if not _sum2_supported_environment():\\n    return'
        ' None",'
        + '"fresh_label":"fresh invocation guard missing or moved: ",'
        + '"paths":"optional runtime contract: production path set changed",'
        + '"models":"optional runtime contract: model name set changed",'
        + '"frontier":"one original search frontier loop"}'
    )
