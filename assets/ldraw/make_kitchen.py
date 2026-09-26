# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the LDraw files that reach the corners of three.js's loader:
`kitchen.mpd`, the parts it needs in `library/`, and the files the loader
refuses in `broken/`. Run it in this folder: `python make_kitchen.py`."""

import os


def write(path, lines):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    open(path, "w", newline="\n").write("\n".join(lines) + "\n")


# A primitive with its own color: a face and edges in it, two edges on one
# line, and faces with an edge along those lines and one off them.
write("library/p/edgy.dat", [
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
])
# A primitive that places a part: its group keeps the part's group.
write("library/p/holder.dat", [
    "0 Holds a part",
    "0 !LDRAW_ORG Primitive",
    "1 16 0 0 0 1 0 0 0 1 0 0 0 1 plate.dat",
    "3 16 0 0 0 1 0 0 0 0 1",
])
# A part of edges only, found only by its name in lower case.
write("library/wire/mixed.dat", [
    "0 Wire",
    "0 !LDRAW_ORG Part",
    "2 24 0 0 0 1 0 0",
    "5 24 0 0 0 1 0 0 0 1 0 0 -1 0",
])
# A part that places a file that is not there: three.js leaves it out.
write("library/parts/broken.dat", [
    "0 Broken",
    "0 !LDRAW_ORG Part",
    "1 16 0 0 0 1 0 0 0 1 0 0 0 1 nothere.dat",
])

# A grid of triangles, first and apart, whose walk grows two shared
# normals around a corner that later meet, and merges them.
fan = [
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
]
kitchen = [
    "0 FILE kitchen.ldr",
    "0 Kitchen",
    "0 !COLOUR Blue CODE 1 VALUE #0055bf EDGE #05131D ALPHA 255 LUMINANCE 0x10",
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
] + fan + [
    "0 FILE dup.ldr",
    "3 16 0 0 0 1 0 0 0 1 0",
    "0 FILE dup.ldr",
    "3 16 0 0 0 2 0 0 0 2 0",
]
write("kitchen.mpd", kitchen)

broken = {
    "no_name": ["0 !COLOUR"],
    "bad_value": ["0 !COLOUR Bad CODE 5 VALUE red"],
    "bad_edge": ["0 !COLOUR Bad CODE 5 VALUE #FF0000 EDGE 999"],
    "bad_alpha": ["0 !COLOUR Bad CODE 5 VALUE #FF0000 ALPHA x"],
    "bad_luminance": ["0 !COLOUR Bad CODE 5 VALUE #FF0000 LUMINANCE x"],
    "bad_token": ["0 !COLOUR Bad CODE 5 VALUE #FF0000 GLITTER"],
    "bad_line": ["7 16 0 0 0"],
    "missing": ["1 16 0 0 0 1 0 0 0 1 0 0 0 1 nowhere.dat"],
}
for name, lines in broken.items():
    write("broken/" + name + ".ldr", lines)
print("written")
