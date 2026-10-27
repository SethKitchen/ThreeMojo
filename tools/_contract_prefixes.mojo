# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the reviewed contract prefixes.

Each checker still applies its own rule. These texts only open the failure.
"""


def contract_prefixes() -> String:
    """Return the reviewed contract prefixes.

    Returns:
        JSON with one prefix for each reviewed checker.
    """
    return (
        '{"cleanup":"reviewed cleanup source contract: ",'
        + '"frozen":"frozen ARC producer contract: ",'
        + '"speed":"reviewed speed parser successor: ",'
        + '"render":"reviewed render actor reuse successor: ",'
        + '"runtime":"reviewed runtime boundary successor: ",'
        + '"invariant":"coverage invariant successor: ",'
        + '"singleton":"rounded LINE singleton contract: ",'
        + '"dispatch":"curve support/dispatch contract: ",'
        + '"scalar":"missing or ambiguous scalar: "}'
    )
