# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the rounded LINE singleton paths and the consumer messages.

The live texts still come from the repository. These names only say which
module is the lane and which module is the rounded line.
"""

from tools._python_json import PY_LIST, PyJson


def singleton_paths() -> String:
    """Return the lane path, the rounded-line path, and the messages.

    Returns:
        JSON with `lane`, `rounded_line`, `import_scope`, and `declaration`.
    """
    return (
        '{"lane":"extensions/carla/lane_refinement.mojo",'
        + '"rounded_line":"extensions/carla/curve_rounded_line.mojo",'
        + '"import_scope":"consumer import scope changed: ",'
        + '"declaration":"consumer/reference declaration changed: "}'
    )


def rounded_line_flags(paths_json: String) raises -> String:
    """Read the singleton paths, then compare each module path.

    Args:
        paths_json: A JSON list of module paths.

    Returns:
        JSON with `paths` and `flags`. `paths` is first. Each flag says
        whether that module path is the rounded line.

    Raises:
        Error: The path list cannot be read. The singleton paths are read
            before the comparison.
    """
    var spec = singleton_paths()
    var named = PyJson.parse(spec)
    var rounded = named.text(named.at(named.root, "rounded_line"))
    var paths = PyJson.parse(paths_json)
    if paths.kind(paths.root) != PY_LIST:
        raise Error("rounded line path list changed")
    var out = String("[")
    var index = 0
    var count = paths.length(paths.root)
    while index < count:
        if index > 0:
            out += ","
        var path = paths.text(paths.item(paths.root, index))
        out += "true" if path == rounded else "false"
        index += 1
    out += "]"
    return '{"paths":' + spec + ',"flags":' + out + "}"
