# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the checker failure prefixes.

Each checker still reports its own error. These texts only open that line.
"""


def cli_failures() -> String:
    """Return the checker failure prefixes.

    Returns:
        JSON with the moment, sampled, and runtime prefixes, the KeyError
        mark, and the moment-word prefix.
    """
    return (
        '{"moments":"FAIL: ",'
        + '"sampled":"FAIL:",'
        + '"runtime":"FAIL:",'
        + '"key":"KeyError: ",'
        + '"word":"spiral moment word: "}'
    )
