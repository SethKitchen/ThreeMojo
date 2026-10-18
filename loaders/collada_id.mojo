# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The `#id` references a Collada file uses to name another element.

The geometry reader and the animation reader both follow these references.
"""


def collada_reference(url: String) raises -> String:
    """Return the id a `#id` reference names.

    Args:
        url: The reference.

    Returns:
        The id, without `#`.

    Raises:
        Error: If the reference does not begin with `#`, which is the one
            form three.js's `parseId` reads.
    """
    if not url.startswith("#"):
        raise Error("Collada: a reference must be #id, not '" + url + "'")
    return String(url[byte=1:])
