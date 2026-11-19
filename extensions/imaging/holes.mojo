# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fill the holes of a label.

A hole is a part of the grid outside a label that the label closes off:
no path through voxels outside the label joins it to the grid's edge. A
threshold of a bone or an organ often leaves holes, such as the marrow
of a bone or a vessel in the liver.

- `fill_holes` gives the label to the background voxels of each hole in
  three dimensions.
- `fill_slice_holes` does the same in each slice along one axis. A tube
  that is open at its two ends has no hole in three dimensions, but each
  of its slices does.

The connectivity is that of the voxels outside the label, as they look
for a path to the edge. With `FACES`, the default, they move through
faces only, so a wall of the label closes a hole where its voxels touch
at an edge or a corner. With `CORNERS` they also pass between two voxels
of the label that share only a corner. In a slice, `FACES` gives four
neighbors, and `EDGES` and `CORNERS` give eight. These are the rules of
scipy's `binary_fill_holes` with the matching structure.

A voxel of another label in a hole keeps its label. It is outside the
label, so a path to the edge can pass through it.
"""

from extensions.imaging.ids import (
    BACKGROUND,
    Connectivity,
    FACES,
    LabelId,
    SliceAxis,
    require_axis,
    require_connectivity,
    require_label,
)
from extensions.imaging.labels import LabelMap


def _fill(
    map: LabelMap, label: LabelId, connectivity: Connectivity, axis: Int
) raises -> LabelMap:
    """Fill the holes of a label in 3D, or in each slice across `axis`
    when it is from 0 to 2."""
    require_label(label)
    if label == BACKGROUND:
        raise Error("Holes are filled in a label other than the background")
    require_connectivity(connectivity)
    var mark = UInt8(label.value)
    # An edge step moves along two axes and a corner step along three.
    var most = connectivity.value + 1
    var steps = List[Int]()
    for dk in range(-1, 2):  # pragma: no branch
        for dj in range(-1, 2):  # pragma: no branch
            for di in range(-1, 2):  # pragma: no branch
                var moves = abs(di) + abs(dj) + abs(dk)
                if moves == 0 or moves > most:
                    continue
                var d: List[Int] = [di, dj, dk]
                if axis >= 0 and d[axis] != 0:
                    continue
                steps.append(di)
                steps.append(dj)
                steps.append(dk)
    var sizes: List[Int] = [map.nx, map.ny, map.nz]
    var count = map.count()
    var reached = List[Bool](length=count, fill=False)
    var queue = List[Int]()
    for index in range(count):  # pragma: no branch
        if map.labels[index] == mark:
            continue
        var at: List[Int] = [
            index % map.nx,
            (index // map.nx) % map.ny,
            index // (map.nx * map.ny),
        ]
        for a in range(3):  # pragma: no branch
            if a != axis and (at[a] == 0 or at[a] == sizes[a] - 1):
                reached[index] = True
                queue.append(index)
                break
    var head = 0
    while head < len(queue):
        var current = queue[head]
        head += 1
        var i = current % map.nx
        var j = (current // map.nx) % map.ny
        var k = current // (map.nx * map.ny)
        for s in range(0, len(steps), 3):  # pragma: no branch
            var x = i + steps[s]
            var y = j + steps[s + 1]
            var z = k + steps[s + 2]
            if not map.contains(x, y, z):
                continue
            var next = map.index(x, y, z)
            if reached[next] or map.labels[next] == mark:
                continue
            reached[next] = True
            queue.append(next)
    var out = map.copy()
    for index in range(count):  # pragma: no branch
        if not reached[index] and map.labels[index] == 0:
            out.labels[index] = mark
    return out^


def fill_holes(
    map: LabelMap, label: LabelId, connectivity: Connectivity = FACES
) raises -> LabelMap:
    """Return a copy with the holes of a label filled in three dimensions.

    Args:
        map: The label map.
        label: The label. Not the background.
        connectivity: How the voxels outside the label connect: `FACES`,
            the default, `EDGES` or `CORNERS`.

    Returns:
        The new map. Each background voxel that no path outside the label
        joins to the grid's edge takes the label.

    Raises:
        Error: If the label is not valid or is the background, or the
            connectivity is not valid.
    """
    return _fill(map, label, connectivity, -1)


def fill_slice_holes(
    map: LabelMap,
    label: LabelId,
    axis: SliceAxis,
    connectivity: Connectivity = FACES,
) raises -> LabelMap:
    """Return a copy with the holes of a label filled in each slice.

    Args:
        map: The label map.
        label: The label. Not the background.
        axis: The axis across the slices. `K_AXIS` fills each axial slice
            of an axial series.
        connectivity: How the voxels outside the label connect in a
            slice: `FACES`, the default, for four neighbors, or `EDGES`
            or `CORNERS` for eight.

    Returns:
        The new map. Each background voxel that no path outside the label
        and inside its slice joins to the slice's edge takes the label.

    Raises:
        Error: If the label is not valid or is the background, or the
            axis or the connectivity is not valid.
    """
    require_axis(axis)
    return _fill(map, label, connectivity, axis.value)
