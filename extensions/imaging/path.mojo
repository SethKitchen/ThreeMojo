# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A centered path through a label, such as the centerline of a vessel.

`label_path` finds the path between two voxels of a label that stays in
the middle of the label. Each step goes to one of the 26 neighbors of a
voxel, inside the label. A step of length `s` between voxels at the
distances `d1` and `d2` from the label's edge costs

    s * (1 / d1^2 + 1 / d2^2) / 2

so a step near the edge costs much more than a step down the middle.
Dijkstra's method finds the path of least total cost. The distances come
from `seed_distances`, exact and with the spacing of each axis, so a
voxel on the grid's edge counts as near the outside.

The path is a list of voxel centers in patient space, from the start to
the end. Pass it to `curved_reformat` to straighten the structure.

A chain of voxel centers turns in steps of 45 degrees. `smooth_path`
averages each inner point with its neighbors, with the weights 1, 2 and
1, and keeps the two ends. A straight run stays where it is, and a zigzag
of one voxel goes flat in one pass. `resample_path` then places points
evenly along the path's length, for a curved reformat with even columns.
"""

from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from extensions.imaging.thickness import seed_distances
from extensions.sdf.vector import V3, distance
from std.math import inf, isfinite, sqrt
from units.si import Length64, METER


struct _Heap(Movable):
    """A binary heap of costs and voxels, the least cost on top."""

    var costs: List[Float64]
    var voxels: List[Int]

    def __init__(out self):
        self.costs = List[Float64]()
        self.voxels = List[Int]()

    def push(mut self, cost: Float64, voxel: Int):
        self.costs.append(cost)
        self.voxels.append(voxel)
        var at = len(self.costs) - 1
        while at > 0:
            var up = (at - 1) // 2
            if self.costs[up] <= self.costs[at]:
                break
            self._swap(at, up)
            at = up

    def pop(mut self) -> Tuple[Float64, Int]:
        var top = (self.costs[0], self.voxels[0])
        var last = len(self.costs) - 1
        self._swap(0, last)
        _ = self.costs.pop()
        _ = self.voxels.pop()
        var at = 0
        var n = len(self.costs)
        while True:
            var left = 2 * at + 1
            var right = left + 1
            var least = at
            if left < n and self.costs[left] < self.costs[least]:
                least = left
            if right < n and self.costs[right] < self.costs[least]:
                least = right
            if least == at:
                break
            self._swap(at, least)
            at = least
        return top

    def _swap(mut self, a: Int, b: Int):
        var cost = self.costs[a]
        self.costs[a] = self.costs[b]
        self.costs[b] = cost
        var voxel = self.voxels[a]
        self.voxels[a] = self.voxels[b]
        self.voxels[b] = voxel


def label_path(
    map: LabelMap,
    volume: ImageVolume,
    label: LabelId,
    start: Tuple[Int, Int, Int],
    end: Tuple[Int, Int, Int],
) raises -> List[V3]:
    """Return the centered path through a label from one voxel to another.

    Args:
        map: The label map.
        volume: The volume of the map. Its placement applies.
        label: The label. Not the background.
        start: The first voxel, `(i, j, k)`, in the label.
        end: The last voxel, `(i, j, k)`, in the label.

    Returns:
        The voxel centers of the path in patient space, in meters, from
        `start` to `end`. Two points in a row are neighbors.

    Raises:
        Error: If the grids differ, the label is not valid or is the
            background, an end is outside the grid or the label, or no
            path through the label joins the two ends.
    """
    require_same_grid(map, volume)
    require_label(label)
    if label == BACKGROUND:
        raise Error("A path needs a label other than the background")
    var mark = UInt8(label.value)
    for voxel in [start, end]:  # pragma: no branch
        if not volume.contains(voxel[0], voxel[1], voxel[2]):
            raise Error("An end of the path is outside the grid")
        if map.labels[map.index(voxel[0], voxel[1], voxel[2])] != mark:
            raise Error("An end of the path is outside the label")
    var outside = List[Bool](capacity=map.count())
    for index in range(map.count()):  # pragma: no branch
        outside.append(map.labels[index] != mark)
    var distances = seed_distances(map, outside, True)
    var weight = List[Float64](length=map.count(), fill=0)
    for index in range(map.count()):  # pragma: no branch
        if not outside[index]:
            var d = distances[index].to(METER)
            weight[index] = 1.0 / (d * d)
    var sx = map.spacing_x.to(METER)
    var sy = map.spacing_y.to(METER)
    var sz = map.spacing_z.to(METER)
    var first = map.index(start[0], start[1], start[2])
    var last = map.index(end[0], end[1], end[2])
    var best = List[Float64](length=map.count(), fill=inf[DType.float64]())
    var before = List[Int](length=map.count(), fill=-1)
    var heap = _Heap()
    best[first] = 0
    heap.push(0, first)
    while len(heap.costs) > 0:
        var item = heap.pop()
        var current = item[1]
        if item[0] > best[current]:
            continue
        if current == last:
            break
        var i = current % map.nx
        var j = (current // map.nx) % map.ny
        var k = current // (map.nx * map.ny)
        for dk in range(-1, 2):  # pragma: no branch
            for dj in range(-1, 2):  # pragma: no branch
                for di in range(-1, 2):  # pragma: no branch
                    var x = i + di
                    var y = j + dj
                    var z = k + dk
                    if not volume.contains(x, y, z):
                        continue
                    var next = map.index(x, y, z)
                    if next == current or outside[next]:
                        continue
                    var step = sqrt(
                        (Float64(di) * sx) ** 2
                        + (Float64(dj) * sy) ** 2
                        + (Float64(dk) * sz) ** 2
                    )
                    var cost = best[current] + step * 0.5 * (
                        weight[current] + weight[next]
                    )
                    if cost < best[next]:
                        best[next] = cost
                        before[next] = current
                        heap.push(cost, next)
    if before[last] < 0 and last != first:
        raise Error("No path through the label joins the two ends")
    var voxels = List[Int]()
    var at = last
    while at >= 0:
        voxels.append(at)
        at = before[at]
    voxels.reverse()
    var out = List[V3]()
    for index in voxels:  # pragma: no branch
        var i = index % map.nx
        var j = (index // map.nx) % map.ny
        var k = index // (map.nx * map.ny)
        out.append(volume.patient_point(Float64(i), Float64(j), Float64(k)))
    return out^


def smooth_path(path: List[V3], passes: Int) raises -> List[V3]:
    """Return a path with its inner points averaged with their neighbors.

    Each pass puts each inner point at `(before + 2 * point + after) / 4`.
    The two ends stay.

    Args:
        path: The points, in meters. At least two.
        passes: How many passes, from 0 to 1000.

    Returns:
        The smoothed path, with as many points.

    Raises:
        Error: If the path has fewer than two points, or `passes` is out
            of range.
    """
    if len(path) < 2:
        raise Error("A path to smooth needs two or more points")
    if passes < 0 or passes > 1000:
        raise Error("A path is smoothed from 0 to 1000 times")
    var out = path.copy()
    for _ in range(passes):
        var before = out.copy()
        for k in range(1, len(out) - 1):
            out[k] = (before[k - 1] + before[k] * 2.0 + before[k + 1]) * 0.25
    return out^


def resample_path(path: List[V3], spacing: Length64) raises -> List[V3]:
    """Return points evenly spaced along a path.

    The points lie at the arc lengths 0, `spacing`, `2 * spacing` and on,
    and the path's last point ends the list when the last step is shorter.

    Args:
        path: The points, in meters. At least two, and two in a row must
            differ.
        spacing: The distance along the path between two points.
            Positive and finite.

    Returns:
        The points, from the first point of the path to its last.

    Raises:
        Error: If the path has fewer than two points or two equal points
            in a row, or the spacing is not positive and finite.
    """
    if len(path) < 2:
        raise Error("A path to resample needs two or more points")
    var step = spacing.to(METER)
    if not (step > 0) or not isfinite(step):
        raise Error("A path's spacing must be positive and finite")
    var starts = List[Float64]()
    var total = 0.0
    for k in range(len(path) - 1):  # pragma: no branch
        var piece = distance(path[k], path[k + 1])
        if not (piece > 0):
            raise Error("Two points in a row of a path are one")
        starts.append(total)
        total += piece
    var out = List[V3]()
    var segment = 0
    var s = 0.0
    var index = 0
    while s < total - 1e-12 * total:
        while segment + 1 < len(starts) and s >= starts[segment + 1]:
            segment += 1
        var piece = distance(path[segment], path[segment + 1])
        var t = (s - starts[segment]) / piece
        out.append(path[segment] + (path[segment + 1] - path[segment]) * t)
        index += 1
        s = Float64(index) * step
    out.append(path[len(path) - 1])
    return out^
