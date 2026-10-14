# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the LDraw files that reach the corners of three.js's loader:
`kitchen.mpd`, the parts it needs in `library/`, and the files the loader
refuses in `broken/`, all in `assets/ldraw/`. Run it from the repository
root: `mojo run -I . tools/make_ldraw_kitchen.mojo`.
"""

from std.os import makedirs
from std.os.path import dirname
from std.pathlib import Path


def write(root: String, path: String, lines: List[String]) raises:
    """Write lines, each ended by a newline.

    Args:
        root: The folder to write in.
        path: The file, relative to the folder.
        lines: The lines.

    Raises:
        Error: If the file cannot be written.
    """
    var target = root + "/" + path
    makedirs(dirname(target), exist_ok=True)
    Path(target).write_text("\n".join(lines) + "\n")


def _add(
    mut result: List[Tuple[String, List[String]]],
    path: String,
    lines: List[String],
):
    """Add a file and its lines."""
    result.append((path, lines.copy()))


def files() -> List[Tuple[String, List[String]]]:
    """Return every file and its lines, in the order they are written.

    Returns:
        The relative paths and their lines.
    """
    var result = List[Tuple[String, List[String]]]()

    # A primitive with its own color: a face and edges in it, two edges on one
    # line, and faces with an edge along those lines and one off them.
    _add(
        result,
        "library/p/edgy.dat",
        [
            "0 Edges on a line",
            "0 !LDRAW_ORG Primitive",
            "0 !COLOUR Green CODE 2 VALUE #237841 EDGE #333333",
            "0 BFC CERTIFY CCW",
            "3 2 0 0 0 2 0 0 0 0 2",
            "2 2 0 0 0 0 0 2",
            "2 24 3 0 0 4 0 0",
            "2 24 6 0 0 5 0 0",
            "5 2 0 0 0 0 0 2 1 0 0 0 1 0",
            "3 16 3 0 0 3.5 0 0 3.2 0 1",
            "3 16 4.5 0 0 5.8 0 0 5 0 1",
            "3 16 3.5 0 0 3 0 0 3.2 0 -1",
        ],
    )
    # A primitive that places a part: its group keeps the part's group.
    _add(
        result,
        "library/p/holder.dat",
        [
            "0 Holds a part",
            "0 !LDRAW_ORG Primitive",
            "1 16 0 0 0 1 0 0 0 1 0 0 0 1 plate.dat",
            "3 16 0 0 0 1 0 0 0 0 1",
        ],
    )
    # A part of edges only, found only by its name in lower case.
    _add(
        result,
        "library/wire/mixed.dat",
        [
            "0 Wire",
            "0 !LDRAW_ORG Part",
            "2 24 0 0 0 1 0 0",
            "5 24 0 0 0 1 0 0 0 1 0 0 -1 0",
        ],
    )
    # A part that places a file that is not there: three.js leaves it out.
    _add(
        result,
        "library/parts/broken.dat",
        [
            "0 Broken",
            "0 !LDRAW_ORG Part",
            "1 16 0 0 0 1 0 0 0 1 0 0 0 1 nothere.dat",
        ],
    )
    # A grid of triangles, first and apart, whose walk grows two shared
    # normals around a corner that later meet, and merges them. The model
    # file places it, and two files share one name.
    _add(
        result,
        "kitchen.mpd",
        [
            "0 FILE kitchen.ldr",
            "0 Kitchen",
            (
                "0 !COLOUR Blue CODE 1 VALUE #0055bf EDGE #05131D ALPHA 255"
                " LUMINANCE 0x10"
            ),
            "0 !COLOUR Blue_Again CODE 1 VALUE #0055BF EDGE #05131D",
            "0 !COLOUR Orange CODE 25 VALUE #F80 EDGE 0x333333 ALPHA -5",
            "0 !COLOUR Bad CODE 26 VALUE #GG0000 EDGE #XYZ LUMINANCE 12",
            "0 !COLOUR Short CODE 27 VALUE #12345 EDGE # +40",
            "0 !COLOUR Mixed CODE 28 VALUE #0055BF EDGE 1 LUMINANCE0X7f",
            "0 !COLOUR Plain VALUE #808080",
            "0 !KEYWORDS",
            "0 BFC NOCERTIFY",
            "1 1 0 0 0 1 0 0 0 -1 0 0 0 -1 fan.ldr",
            "1 25 10 0 0 -1 0 0 0 1 0 0 0 -1 fan.ldr",
            "1 26 20 0 0 -1 0 0 0 -1 0 0 0 1 fan.ldr",
            "1 26 30 0 0 -0.5 0 0.8660254 0 -1 0 0.8660254 0 0.5 fan.ldr",
            "1 16 0 10 0 1 0 0 0 1 0 0 0 1 Wire/Mixed.DAT",
            "1 16 0 20 0 1 0 0 0 1 0 0 0 1 broken.dat",
            "1 16 0 30 0 1 0 0 0 1 0 0 0 1 holder.dat",
            "1 16 0 40 0 1 0 0 0 1 0 0 0 1 dup.ldr",
            "2 1 0 0 0 1 1 1",
            "5 1 0 0 0 1 1 1 0 1 0 1 0 0",
            "3 4 0 0 0 1 0 0 0 1 0",
            "3 16 0 0 0 1 0 0 0 1 0",
            "3 16 1e308 0 0 0 1 0 x 0 0",
            "3 16 -1e308 0 0 0 1 0 0 0 1",
            "0",
            "0 FILE fan.ldr",
            "0 !LDRAW_ORG Unofficial_Model",
            "0 BFC CERTIFY CCW",
            "3 16 100 0 0 100 0 1 101 0 1",
            "3 16 100 0 0 101 0 1 101 0 0",
            "3 16 101 0 0 101 0 1 102 0 0",
            "3 16 101 0 1 102 0 1 102 0 0",
            "3 16 102 0 0 102 0 1 103 0 1",
            "3 16 102 0 0 103 0 1 103 0 0",
            "3 16 100 0 1 100 0 2 101 0 1",
            "3 16 100 0 2 101 0 2 101 0 1",
            "3 16 101 0 1 101 0 2 102 0 2",
            "3 16 101 0 1 102 0 2 102 0 1",
            "3 16 102 0 1 102 0 2 103 0 1",
            "3 16 102 0 2 103 0 2 103 0 1",
            "3 16 100 0 2 100 0 3 101 0 3",
            "3 16 100 0 2 101 0 3 101 0 2",
            "3 16 101 0 2 101 0 3 102 0 2",
            "3 16 101 0 3 102 0 3 102 0 2",
            "3 16 102 0 2 102 0 3 103 0 3",
            "3 16 102 0 2 103 0 3 103 0 2",
            "3 16 0 0.1 0 1 0 1 1 0 -1",
            "3 16 0 0.1 0 1 0 -1 -1 0 -1",
            "3 16 0 0.1 0 -1 0 -1 -1 0 1",
            "3 16 0 0.1 0 -1 0 1 1 0 1",
            "1 16 0 0 0 1 0 0 0 1 0 0 0 1 edgy.dat",
            "0 FILE dup.ldr",
            "3 16 0 0 0 1 0 0 0 1 0",
            "0 FILE dup.ldr",
            "3 16 0 0 0 2 0 0 0 2 0",
        ],
    )
    # Files the loader refuses.
    _add(
        result,
        "broken/no_name.ldr",
        [
            "0 !COLOUR",
        ],
    )
    _add(
        result,
        "broken/bad_value.ldr",
        [
            "0 !COLOUR Bad CODE 5 VALUE red",
        ],
    )
    _add(
        result,
        "broken/bad_edge.ldr",
        [
            "0 !COLOUR Bad CODE 5 VALUE #FF0000 EDGE 999",
        ],
    )
    _add(
        result,
        "broken/bad_alpha.ldr",
        [
            "0 !COLOUR Bad CODE 5 VALUE #FF0000 ALPHA x",
        ],
    )
    _add(
        result,
        "broken/bad_luminance.ldr",
        [
            "0 !COLOUR Bad CODE 5 VALUE #FF0000 LUMINANCE x",
        ],
    )
    _add(
        result,
        "broken/bad_token.ldr",
        [
            "0 !COLOUR Bad CODE 5 VALUE #FF0000 GLITTER",
        ],
    )
    _add(
        result,
        "broken/bad_line.ldr",
        [
            "7 16 0 0 0",
        ],
    )
    _add(
        result,
        "broken/missing.ldr",
        [
            "1 16 0 0 0 1 0 0 0 1 0 0 0 1 nowhere.dat",
        ],
    )
    return result^


def write_all(root: String) raises:
    """Write every file.

    Args:
        root: The folder to write in.

    Raises:
        Error: If a file cannot be written.
    """
    for entry in files():
        write(root, entry[0], entry[1])


def main() raises:
    write_all("assets/ldraw")
    print("written")
