# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the reviewed roundoff envelope for one module path."""


def roundoff_envelope_name(path: String) -> String:
    """Return the reviewed roundoff envelope for one module path.

    Args:
        path: A repository path.

    Returns:
        `_try_spiral_grouped_roundoff_envelope` when `path` ends with
        `/spiral_grouped_roundoff_proof.mojo`. Otherwise
        `_try_spiral_roundoff_envelope`.
    """
    var suffix = "/spiral_grouped_roundoff_proof.mojo"
    if path.byte_length() >= suffix.byte_length():
        var start = path.byte_length() - suffix.byte_length()
        var tail = path[byte = start : path.byte_length()]
        if String(tail) == suffix:
            return "_try_spiral_grouped_roundoff_envelope"
    return "_try_spiral_roundoff_envelope"
