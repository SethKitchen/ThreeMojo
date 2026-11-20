# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A file path's directory, its name, and confined relative resolution.

`path_directory` keeps the text through the last `/`. `path_name` keeps
the text after it. A path with no `/` has an empty directory and is its
own name. `confined_path` resolves a relative companion path inside a
directory and refuses parent escapes, schemes, backslashes, null bytes and
symbolic links that leave the containment root.
"""

from std.os.path import realpath
from std.pathlib import Path


def path_directory(path: String) -> String:
    """Return `path` through its last `/`, or empty when it has none.

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

    Args:
        path: A file's path.

    Returns:
        The name.
    """
    return String(path[byte = path.rfind("/") + 1 :])


def confined_path(
    directory: String,
    relative: String,
    label: String = "Path",
    allow_sibling_dir: Bool = False,
) raises -> String:
    """Join a relative companion path onto `directory` and keep it inside.

    The containment root is `directory`. When `allow_sibling_dir` is true
    and `directory` is not empty, the root is the parent of `directory`, so
    that a companion can be in a sibling folder, as in `../brick.png`. The
    rule does not depend on the working directory. It is the same for a
    relative `directory` and an absolute one.

    Args:
        directory: The base folder, or empty for the current directory.
        relative: The relative companion path from an untrusted document.
        label: The caller's prefix for error messages.
        allow_sibling_dir: True when the path can step up one folder from
            `directory`, to a sibling folder. An empty `directory` has no
            sibling folder.

    Returns:
        The joined path inside the containment root.

    Raises:
        Error: If `relative` is empty, holds a null byte, a colon or a
            backslash, starts with `/`, steps outside its containment root,
            names no file, or resolves through an escaping symbolic link.
    """
    if relative.byte_length() == 0:
        raise Error(label + ": a relative path must not be empty")
    if "\0" in relative:
        raise Error(label + ": a relative path has a null byte")
    if relative.startswith("/"):
        raise Error(label + ": only a relative path is read: " + relative)
    if "\\" in relative:
        raise Error(label + ": a relative path has a backslash: " + relative)
    if ":" in relative:
        raise Error(label + ": only a relative path is read: " + relative)
    # How many folders the walk is below the containment root. A sibling
    # folder is one step up from `directory`, so the walk starts one folder
    # below the root when a sibling folder is allowed.
    var depth = 0
    if allow_sibling_dir:
        if directory != "":
            depth = 1
    var parts = List[String]()
    var names_file = False
    for raw in relative.split("/"):  # pragma: no branch
        var part = String(raw)
        if part == "..":
            if depth == 0:
                raise Error(
                    label
                    + ": a relative path leaves its directory: "
                    + relative
                )
            depth -= 1
            names_file = False
            parts.append(part^)
        elif part != "":
            if part != ".":
                depth += 1
                names_file = True
                parts.append(part^)
    if not names_file:
        raise Error(label + ": a relative path names no file: " + relative)
    var clean = "/".join(parts)
    var joined = clean
    if directory != "":
        if directory.endswith("/"):
            joined = directory + clean
        else:
            joined = directory + "/" + clean
    # The walk above reads the text only. A symbolic link can still lead
    # out, so the real path of a file that exists must be under the real
    # path of the same root.
    if Path(joined).exists():
        var root = "."
        if directory != "":
            root = directory
            if allow_sibling_dir:
                root = directory + "/.."
        var prefix = realpath(root)
        if not prefix.endswith("/"):
            prefix += "/"
        if not realpath(joined).startswith(prefix):
            raise Error(
                label + ": a companion path leaves its root: " + relative
            )
    return joined^
