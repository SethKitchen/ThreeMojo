# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The index of a grid of vertices, shared by the builders that bend one.

A torus, a torus knot and a tube are all a grid of `rows + 1` by
`columns + 1` vertices with two triangles per cell, and differ only in
which way round three.js winds the cell, which depends on which way its
rows run. One builder takes that choice, so the three agree with three.js
cell for cell.
"""


def grid_index(rows: Int, columns: Int, row_first: Bool) -> List[Int]:
    """Return the index of a grid of `rows + 1` by `columns + 1` vertices,
    two triangles per cell.

    three.js winds its tubes opposite ways round the cell, because their
    rows run opposite ways round the tube: the torus starts each cell on
    the current row and the knot and the tube on the row before.
    `row_first` picks which, so each comes out counter-clockwise seen from
    outside and cell for cell what three.js emits.

    Args:
        rows: How many rows of cells.
        columns: How many columns of cells.
        row_first: True to start each cell on its own row, False on the
            row before.

    Returns:
        Three indices per triangle, `rows * columns * 2` triangles.
    """
    var stride = columns + 1
    var index = List[Int]()
    for row in range(1, rows + 1):  # pragma: no branch
        var before = stride * (row - 1)
        var here = stride * row
        for column in range(1, columns + 1):  # pragma: no branch
            var a: Int
            var b: Int
            var c: Int
            var d: Int
            if row_first:
                a = here + column - 1
                b = before + column - 1
                c = before + column
                d = here + column
            else:
                a = before + column - 1
                b = here + column - 1
                c = here + column
                d = before + column
            index.append(a)
            index.append(b)
            index.append(d)
            index.append(b)
            index.append(c)
            index.append(d)
    return index^
