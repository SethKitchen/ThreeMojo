# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The exact Euclidean distance from each point of a grid to the nearest
seed, after Felzenszwalb and Huttenlocher (2012).

`distance_transform(seeds, px, py, pz, sx, sy, sz)` runs the
one-dimensional transform along x, then y, then z. Each pass is the lower
envelope of parabolas, one for each point that has a seed so far, with
the spacing of its axis. It gives the squared distance to the nearest
seed and the index of that seed. A point with no seed anywhere keeps
`NO_SEED` and the index -1.
"""

from std.math import isfinite

comptime NO_SEED = 1.0e30
"""The squared distance of a point that has no seed."""


def _pass(
    mut values: List[Float64],
    mut nearest: List[Int],
    first: Int,
    stride: Int,
    count: Int,
    spacing: Float64,
    mut f: List[Float64],
    mut g: List[Int],
    mut hull: List[Int],
    mut starts: List[Float64],
):
    """Replace one line of squared distances by its exact transform.

    The line holds `count` values from `first`, `stride` apart, `spacing`
    apart. A value of `NO_SEED` is no site, so no arithmetic is done on it,
    and a line without a site stays as it is. The scratch lists are
    reused from line to line.
    """
    f.clear()
    g.clear()
    hull.clear()
    starts.clear()
    for k in range(count):  # pragma: no branch
        f.append(values[first + k * stride])
        g.append(nearest[first + k * stride])
    # The sites of the envelope, and where the region of each starts.
    for q in range(count):  # pragma: no branch
        if f[q] >= NO_SEED:
            continue
        var xq = Float64(q) * spacing
        var start = -NO_SEED
        while len(hull) > 0:
            var p = hull[len(hull) - 1]
            var xp = Float64(p) * spacing
            start = ((f[q] + xq * xq) - (f[p] + xp * xp)) / (2.0 * (xq - xp))
            if start > starts[len(starts) - 1]:
                break
            _ = hull.pop()
            _ = starts.pop()
            start = -NO_SEED
        hull.append(q)
        starts.append(start)
    if len(hull) == 0:
        return
    var at = 0
    for q in range(count):  # pragma: no branch
        var x = Float64(q) * spacing
        while at + 1 < len(hull) and starts[at + 1] < x:
            at += 1
        var d = x - Float64(hull[at]) * spacing
        values[first + q * stride] = d * d + f[hull[at]]
        nearest[first + q * stride] = g[hull[at]]


def distance_transform(
    seeds: List[Bool],
    px: Int,
    py: Int,
    pz: Int,
    sx: Float64 = 1.0,
    sy: Float64 = 1.0,
    sz: Float64 = 1.0,
) raises -> Tuple[List[Float64], List[Int]]:
    """Return the exact Euclidean distance from each grid point to a seed.

    Args:
        seeds: One flag per point, `i` fastest.
        px: Points along x. At least one.
        py: Points along y. At least one.
        pz: Points along z. At least one.
        sx: The spacing along x, positive and finite. 1 by default.
        sy: The spacing along y, positive and finite. 1 by default.
        sz: The spacing along z, positive and finite. 1 by default.

    Returns:
        The squared distance to the nearest seed, in the square of the
        unit of the spacings, and the index of that seed. A grid with no
        seed gives `NO_SEED` and -1 at each point.

    Raises:
        Error: If a size is not positive, a spacing is not positive and
            finite, or the flags do not fill the grid.
    """
    if px < 1 or py < 1 or pz < 1:
        raise Error("A distance transform needs at least one point a side")
    if not (sx > 0 and sy > 0 and sz > 0) or not (
        isfinite(sx) and isfinite(sy) and isfinite(sz)
    ):
        raise Error("A grid spacing must be positive and finite")
    if len(seeds) != px * py * pz:
        raise Error("The seeds must fill the grid")
    var count = px * py * pz
    var d = List[Float64](length=count, fill=NO_SEED)
    var nearest = List[Int](length=count, fill=-1)
    for index in range(count):  # pragma: no branch
        if seeds[index]:
            d[index] = 0
            nearest[index] = index
    var f = List[Float64]()
    var g = List[Int]()
    var hull = List[Int]()
    var starts = List[Float64]()
    for k in range(pz):  # pragma: no branch
        for j in range(py):  # pragma: no branch
            _pass(d, nearest, px * (j + py * k), 1, px, sx, f, g, hull, starts)
    for k in range(pz):  # pragma: no branch
        for i in range(px):  # pragma: no branch
            _pass(d, nearest, i + px * py * k, px, py, sy, f, g, hull, starts)
    for j in range(py):  # pragma: no branch
        for i in range(px):  # pragma: no branch
            _pass(d, nearest, i + px * j, px * py, pz, sz, f, g, hull, starts)
    return (d^, nearest^)
