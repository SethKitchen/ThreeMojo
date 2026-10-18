# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A file path's directory and its name.

`path_directory` keeps the text through the last `/`. `path_name` keeps
the text after it. A path with no `/` has an empty directory and is its
own name.
"""


def path_directory(path: String) -> String:
    """Return `path` through its last `/`, or empty when it has none.

    Error: Never.

    Args:
        path: A file's path.

    Returns:
        The directory, ending in `/` when there is one.

    """
    return String(path[byte = 0 : path.rfind("/") + 1])


def path_name(path: String) -> String:
    """Return the text of `path` after its last `/`.

    A path with no `/` is returned whole. `path.split('/').pop()` gives
    the same text.

    Error: Never.

    Args:
        path: A file's path.

    Returns:
        The name.

    """
    return String(path[byte = path.rfind("/") + 1 :])
