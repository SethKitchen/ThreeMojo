# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Label maps: one label for each voxel of a volume.

Label zero is the background. A label map has the grid and the spacing
of the volume it was made for. `threshold` labels the voxels in a range
of values. `region_grow` labels the voxels in a range that connect to a
seed. `keep_largest` keeps the largest connected piece of a label. Two
voxels connect when they share a face, so each voxel has six neighbors.

`label_surface` returns the boundary of a label as a triangle mesh in
the volume frame, in meters. The surface passes halfway between a voxel
inside the label and a voxel outside it.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.skeleton.isosurface import SampleGrid, mesh_samples
from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from math.vector3 import Vector3
from std.math import isfinite
from units.si import Length64, METER


struct LabelMap(Copyable, Movable):
    """One label for each voxel, on the grid of a volume."""

    var nx: Int
    """Voxels along `i`."""
    var ny: Int
    """Voxels along `j`."""
    var nz: Int
    """Voxels along `k`."""
    var spacing_x: Length64
    """The spacing along `i`."""
    var spacing_y: Length64
    """The spacing along `j`."""
    var spacing_z: Length64
    """The spacing along `k`."""
    var labels: List[UInt8]
    """One label per voxel, `i` fastest."""

    def __init__(out self, volume: ImageVolume):
        """Create a map of background on the grid of a volume.

        Args:
            volume: The volume whose grid and spacing the map takes.
        """
        self.nx = volume.nx
        self.ny = volume.ny
        self.nz = volume.nz
        self.spacing_x = volume.spacing_x
        self.spacing_y = volume.spacing_y
        self.spacing_z = volume.spacing_z
        self.labels = List[UInt8](length=volume.count(), fill=0)

    def count(self) -> Int:
        """Return how many voxels the map holds.

        Returns:
            `nx * ny * nz`.
        """
        return self.nx * self.ny * self.nz

    def index(self, i: Int, j: Int, k: Int) -> Int:
        """Return the place of a voxel in `labels`, without a check.

        Args:
            i: The column.
            j: The row.
            k: The slice.

        Returns:
            `i + nx * (j + ny * k)`.
        """
        return i + self.nx * (j + self.ny * k)

    def contains(self, i: Int, j: Int, k: Int) -> Bool:
        """Return whether a voxel index is inside the grid.

        Args:
            i: The column.
            j: The row.
            k: The slice.

        Returns:
            Whether each index is from zero to one below its size.
        """
        if i < 0 or j < 0 or k < 0:
            return False
        return i < self.nx and j < self.ny and k < self.nz

    def get(self, i: Int, j: Int, k: Int) raises -> LabelId:
        """Return the label of one voxel.

        Args:
            i: The column.
            j: The row.
            k: The slice.

        Returns:
            The label.

        Raises:
            Error: If the index is outside the grid.
        """
        _require_inside(self, i, j, k)
        return LabelId(Int(self.labels[self.index(i, j, k)]))

    def set(mut self, i: Int, j: Int, k: Int, label: LabelId) raises:
        """Store the label of one voxel.

        Args:
            i: The column.
            j: The row.
            k: The slice.
            label: The label, from 0 to 255.

        Raises:
            Error: If the index is outside the grid, or the label is not
                valid.
        """
        _require_inside(self, i, j, k)
        require_label(label)
        self.labels[self.index(i, j, k)] = UInt8(label.value)

    def voxels(self, label: LabelId) raises -> Int:
        """Return how many voxels have a label.

        Args:
            label: The label to count.

        Returns:
            The count.

        Raises:
            Error: If the label is not valid.
        """
        require_label(label)
        var want = UInt8(label.value)
        var total = 0
        # A map holds at least one voxel.
        for value in self.labels:  # pragma: no branch
            if value == want:
                total += 1
        return total


def _require_inside(map: LabelMap, i: Int, j: Int, k: Int) raises:
    """Refuse a voxel index outside the grid."""
    if not map.contains(i, j, k):
        raise Error("The voxel index is outside the label map")


def require_same_grid(map: LabelMap, volume: ImageVolume) raises:
    """Refuse a label map made for a grid of another size.

    Args:
        map: The label map.
        volume: The volume.

    Raises:
        Error: If the two grids differ in size.
    """
    if map.nx != volume.nx or map.ny != volume.ny or map.nz != volume.nz:
        raise Error("The label map and the volume have different grids")


def _require_range(low: Float64, high: Float64) raises:
    """Refuse a value range that is not finite or that falls."""
    if not isfinite(low) or not isfinite(high) or not (low <= high):
        raise Error("A value range needs finite ends that do not fall")


def threshold(
    volume: ImageVolume, low: Float64, high: Float64, label: LabelId
) raises -> LabelMap:
    """Return a map that gives `label` to each voxel in a range.

    Args:
        volume: The volume.
        low: The lowest value to label.
        high: The highest value to label.
        label: The label. Not the background.

    Returns:
        The map. Every other voxel is background.

    Raises:
        Error: If the range is not finite or falls, or the label is not
            valid or is the background.
    """
    _require_range(low, high)
    _require_foreground(label)
    var map = LabelMap(volume)
    var mark = UInt8(label.value)
    for index in range(volume.count()):  # pragma: no branch
        var value = Float64(volume.values[index])
        if value >= low and value <= high:
            map.labels[index] = mark
    return map^


def _require_foreground(label: LabelId) raises:
    """Refuse an invalid label or the background."""
    require_label(label)
    if label == BACKGROUND:
        raise Error("This operation needs a label other than the background")


def _neighbors(nx: Int, ny: Int, nz: Int, index: Int) -> List[Int]:
    """Return the indexes of the face neighbors of a voxel."""
    var i = index % nx
    var j = (index // nx) % ny
    var k = index // (nx * ny)
    var out = List[Int]()
    if i > 0:
        out.append(index - 1)
    if i + 1 < nx:
        out.append(index + 1)
    if j > 0:
        out.append(index - nx)
    if j + 1 < ny:
        out.append(index + nx)
    if k > 0:
        out.append(index - nx * ny)
    if k + 1 < nz:
        out.append(index + nx * ny)
    return out^


def region_grow(
    volume: ImageVolume,
    i: Int,
    j: Int,
    k: Int,
    low: Float64,
    high: Float64,
    label: LabelId,
) raises -> LabelMap:
    """Return a map of the voxels in a range that connect to a seed.

    Args:
        volume: The volume.
        i: The seed column.
        j: The seed row.
        k: The seed slice.
        low: The lowest value to grow into.
        high: The highest value to grow into.
        label: The label. Not the background.

    Returns:
        The map. Every voxel outside the grown region is background.

    Raises:
        Error: If the seed is outside the volume or its value is outside
            the range, the range is not finite or falls, or the label is
            not valid or is the background.
    """
    _require_range(low, high)
    _require_foreground(label)
    if not volume.contains(i, j, k):
        raise Error("The seed is outside the volume")
    var seed = volume.index(i, j, k)
    var seed_value = Float64(volume.values[seed])
    if not (seed_value >= low) or not (seed_value <= high):
        raise Error("The seed's value is outside the range")
    var map = LabelMap(volume)
    var mark = UInt8(label.value)
    map.labels[seed] = mark
    var queue = List[Int]()
    queue.append(seed)
    var head = 0
    while head < len(queue):
        var current = queue[head]
        head += 1
        for next in _neighbors(volume.nx, volume.ny, volume.nz, current):
            if map.labels[next] == mark:
                continue
            var value = Float64(volume.values[next])
            if value >= low and value <= high:
                map.labels[next] = mark
                queue.append(next)
    return map^


def keep_largest(map: LabelMap, label: LabelId) raises -> LabelMap:
    """Return a copy that keeps only the largest connected piece of a label.

    The other pieces of the label become background. Of two pieces of one
    size, the piece with the lowest voxel index stays. Other labels do not
    change.

    Args:
        map: The label map.
        label: The label. Not the background.

    Returns:
        The new map.

    Raises:
        Error: If the label is not valid, is the background, or has no
            voxels.
    """
    _require_foreground(label)
    var mark = UInt8(label.value)
    var count = map.count()
    var piece = List[Int](length=count, fill=-1)
    var best_piece = -1
    var best_size = 0
    var pieces = 0
    for start in range(count):  # pragma: no branch
        if map.labels[start] != mark or piece[start] >= 0:
            continue
        piece[start] = pieces
        var queue = List[Int]()
        queue.append(start)
        var head = 0
        while head < len(queue):
            var current = queue[head]
            head += 1
            for next in _neighbors(map.nx, map.ny, map.nz, current):
                if map.labels[next] == mark and piece[next] < 0:
                    piece[next] = pieces
                    queue.append(next)
        if len(queue) > best_size:
            best_size = len(queue)
            best_piece = pieces
        pieces += 1
    if best_piece < 0:
        raise Error("The label has no voxels")
    var out = map.copy()
    for index in range(count):  # pragma: no branch
        if map.labels[index] == mark and piece[index] != best_piece:
            out.labels[index] = 0
    return out^


def label_surface(map: LabelMap, label: LabelId) raises -> BufferGeometry:
    """Return the boundary of a label as a triangle mesh.

    The mesh is in the volume frame, in meters: voxel `(i, j, k)` has its
    center at `(i * spacing_x, j * spacing_y, k * spacing_z)`. The mesh is
    closed, because the grid is padded with background on every side.

    Args:
        map: The label map.
        label: The label. Not the background.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes. The `uv`
        attribute is cylindrical about y.

    Raises:
        Error: If the label is not valid, is the background, or has no
            voxels.
    """
    _require_foreground(label)
    if map.voxels(label) == 0:
        raise Error("The label has no voxels")
    var mark = UInt8(label.value)
    var px = map.nx + 2
    var py = map.ny + 2
    var pz = map.nz + 2
    var samples = List[Float32](length=px * py * pz, fill=0.5)
    for k in range(map.nz):  # pragma: no branch
        for j in range(map.ny):  # pragma: no branch
            for i in range(map.nx):  # pragma: no branch
                if map.labels[map.index(i, j, k)] == mark:
                    samples[(i + 1) + px * ((j + 1) + py * (k + 1))] = -0.5
    var dx = Float32(map.spacing_x.to(METER))
    var dy = Float32(map.spacing_y.to(METER))
    var dz = Float32(map.spacing_z.to(METER))
    var grid = SampleGrid(
        px - 1, py - 1, pz - 1, dx, dy, dz, px, py, pz, dy * Float32(py - 1)
    )
    return mesh_samples(samples, Vector3(-dx, -dy, -dz), grid, "label")
