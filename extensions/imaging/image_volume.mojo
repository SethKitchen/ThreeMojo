# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scalar volume on a regular grid, with physical spacing.

Voxel `(i, j, k)` has its center at `i * spacing_x` along `axis_x`,
`j * spacing_y` along `axis_y` and `k * spacing_z` along `axis_z`, from
`origin`. This is the DICOM convention: the image position is the center
of the first voxel. `i` counts columns, `j` counts rows and `k` counts
slices. The values are stored with `i` fastest, then `j`, then `k`.
"""

from extensions.imaging.ids import MONOCHROME2, Photometric
from extensions.sdf.vector import V3, dot, v3
from std.math import floor, isfinite, max, min
from units.quantity import Unit
from units.si import Length64, METER

# A millimeter with a Float64 scale, so a DICOM length keeps every digit.
comptime MILLIMETER64 = Unit[1, 0, 0, 0, 0, DType.float64](0.001, "mm")

# The most voxels one volume can hold: 2^28, a 640 by 640 by 655 volume.
comptime MAX_VOXELS = 268435456


def require_grid(nx: Int, ny: Int, nz: Int) raises:
    """Refuse a grid with no voxels or too many.

    Args:
        nx: Voxels along `i`.
        ny: Voxels along `j`.
        nz: Voxels along `k`.

    Raises:
        Error: If a size is not positive, or the grid holds more than
            `MAX_VOXELS` voxels.
    """
    if nx <= 0 or ny <= 0 or nz <= 0:
        raise Error("A volume needs at least one voxel on each axis")
    if nx > MAX_VOXELS // ny // nz:
        raise Error("A volume can hold at most 2^28 voxels")


def require_spacing(spacing: Length64) raises:
    """Refuse a voxel spacing that is not a positive finite length.

    Args:
        spacing: The spacing to check.

    Raises:
        Error: If `spacing` is not positive and finite.
    """
    var meters = spacing.to(METER)
    if not (meters > 0) or not isfinite(meters):
        raise Error("A voxel spacing must be positive and finite")


struct ImageVolume(Copyable, Movable):
    """A grid of scalar samples with a physical size and placement."""

    var nx: Int
    """Voxels along `i`, the columns."""
    var ny: Int
    """Voxels along `j`, the rows."""
    var nz: Int
    """Voxels along `k`, the slices."""
    var spacing_x: Length64
    """The distance between the centers of two neighbors along `i`."""
    var spacing_y: Length64
    """The distance between the centers of two neighbors along `j`."""
    var spacing_z: Length64
    """The distance between the centers of two neighbors along `k`."""
    var origin: V3
    """The center of voxel `(0, 0, 0)` in patient space, in meters."""
    var axis_x: V3
    """The unit direction of increasing `i` in patient space."""
    var axis_y: V3
    """The unit direction of increasing `j` in patient space."""
    var axis_z: V3
    """The unit direction of increasing `k` in patient space."""
    var window_center: Float64
    """The center of the display window, in the units of the values."""
    var window_width: Float64
    """The width of the display window, in the units of the values."""
    var photometric: Photometric
    """Whether the lowest value shows as black or as white."""
    var values: List[Float32]
    """One value per voxel, `i` fastest."""

    def __init__(
        out self,
        nx: Int,
        ny: Int,
        nz: Int,
        spacing_x: Length64,
        spacing_y: Length64,
        spacing_z: Length64,
    ) raises:
        """Create a volume of zeros at the origin, on the patient axes.

        Args:
            nx: Voxels along `i`.
            ny: Voxels along `j`.
            nz: Voxels along `k`.
            spacing_x: The spacing along `i`.
            spacing_y: The spacing along `j`.
            spacing_z: The spacing along `k`.

        Raises:
            Error: If the grid is empty or too large, or a spacing is not
                positive and finite.
        """
        require_grid(nx, ny, nz)
        require_spacing(spacing_x)
        require_spacing(spacing_y)
        require_spacing(spacing_z)
        self.nx = nx
        self.ny = ny
        self.nz = nz
        self.spacing_x = spacing_x
        self.spacing_y = spacing_y
        self.spacing_z = spacing_z
        self.origin = v3(0, 0, 0)
        self.axis_x = v3(1, 0, 0)
        self.axis_y = v3(0, 1, 0)
        self.axis_z = v3(0, 0, 1)
        self.window_center = 0.5
        self.window_width = 1.0
        self.photometric = MONOCHROME2
        self.values = List[Float32](length=nx * ny * nz, fill=0)

    def count(self) -> Int:
        """Return how many voxels the volume holds.

        Returns:
            `nx * ny * nz`.
        """
        return self.nx * self.ny * self.nz

    def index(self, i: Int, j: Int, k: Int) -> Int:
        """Return the place of a voxel in `values`, without a check.

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

    def get(self, i: Int, j: Int, k: Int) raises -> Float32:
        """Return the value of one voxel.

        Args:
            i: The column.
            j: The row.
            k: The slice.

        Returns:
            The stored value.

        Raises:
            Error: If the index is outside the grid.
        """
        _require_inside(self, i, j, k)
        return self.values[self.index(i, j, k)]

    def set(mut self, i: Int, j: Int, k: Int, value: Float32) raises:
        """Store the value of one voxel.

        Args:
            i: The column.
            j: The row.
            k: The slice.
            value: The value to store.

        Raises:
            Error: If the index is outside the grid.
        """
        _require_inside(self, i, j, k)
        self.values[self.index(i, j, k)] = value

    def trilinear(self, x: Float64, y: Float64, z: Float64) -> Float32:
        """Return the value at a point between voxel centers.

        The point is in voxel units: `(1, 2, 3)` is the center of voxel
        `(1, 2, 3)`. A point outside the centers takes the value of the
        nearest edge.

        Args:
            x: The position along `i`.
            y: The position along `j`.
            z: The position along `k`.

        Returns:
            The blend of the eight nearest voxels.
        """
        var cx = _clamp_index(x, self.nx)
        var cy = _clamp_index(y, self.ny)
        var cz = _clamp_index(z, self.nz)
        var i0 = Int(floor(cx))
        var j0 = Int(floor(cy))
        var k0 = Int(floor(cz))
        var i1 = min(i0 + 1, self.nx - 1)
        var j1 = min(j0 + 1, self.ny - 1)
        var k1 = min(k0 + 1, self.nz - 1)
        var fx = Float32(cx - Float64(i0))
        var fy = Float32(cy - Float64(j0))
        var fz = Float32(cz - Float64(k0))
        var c00 = _mix(
            self.values[self.index(i0, j0, k0)],
            self.values[self.index(i1, j0, k0)],
            fx,
        )
        var c10 = _mix(
            self.values[self.index(i0, j1, k0)],
            self.values[self.index(i1, j1, k0)],
            fx,
        )
        var c01 = _mix(
            self.values[self.index(i0, j0, k1)],
            self.values[self.index(i1, j0, k1)],
            fx,
        )
        var c11 = _mix(
            self.values[self.index(i0, j1, k1)],
            self.values[self.index(i1, j1, k1)],
            fx,
        )
        return _mix(_mix(c00, c10, fy), _mix(c01, c11, fy), fz)

    def value_range(self) -> Tuple[Float32, Float32]:
        """Return the smallest and the largest value.

        Returns:
            The minimum and the maximum over every voxel.
        """
        var low = self.values[0]
        var high = self.values[0]
        # A volume holds at least one voxel.
        for value in self.values:  # pragma: no branch
            low = min(low, value)
            high = max(high, value)
        return (low, high)

    def extent(self) -> V3:
        """Return the size of the grid of voxel centers, in meters.

        Returns:
            `(nx - 1) * spacing_x` and the same for `j` and `k`.
        """
        return v3(
            Float64(self.nx - 1) * self.spacing_x.to(METER),
            Float64(self.ny - 1) * self.spacing_y.to(METER),
            Float64(self.nz - 1) * self.spacing_z.to(METER),
        )

    def patient_point(self, x: Float64, y: Float64, z: Float64) -> V3:
        """Return the patient-space position of a point in voxel units.

        Args:
            x: The position along `i`.
            y: The position along `j`.
            z: The position along `k`.

        Returns:
            The position in meters.
        """
        return (
            self.origin
            + self.axis_x * (x * self.spacing_x.to(METER))
            + self.axis_y * (y * self.spacing_y.to(METER))
            + self.axis_z * (z * self.spacing_z.to(METER))
        )

    def voxel_point(self, p: V3) -> V3:
        """Return the voxel units of a patient-space point.

        This is the inverse of `patient_point` when the three axes are
        square to each other, as the readers make them.

        Args:
            p: The point in patient space, in meters.

        Returns:
            The point in voxel units: `(1, 2, 3)` is the center of voxel
            `(1, 2, 3)`.
        """
        var d = p - self.origin
        return v3(
            dot(d, self.axis_x) / self.spacing_x.to(METER),
            dot(d, self.axis_y) / self.spacing_y.to(METER),
            dot(d, self.axis_z) / self.spacing_z.to(METER),
        )

    def fit_window(mut self):
        """Set the display window to the range of the values.

        A volume of one value gets a window of width one around it.
        A window fits values that are not whole numbers too, because the
        window is DICOM's `LINEAR_EXACT` function.
        """
        var span = self.value_range()
        var low = Float64(span[0])
        var high = Float64(span[1])
        self.window_center = (low + high) / 2
        self.window_width = max(high - low, 1.0)


def _require_inside(volume: ImageVolume, i: Int, j: Int, k: Int) raises:
    """Refuse a voxel index outside the grid."""
    if not volume.contains(i, j, k):
        raise Error("The voxel index is outside the volume")


def _clamp_index(x: Float64, size: Int) -> Float64:
    """Return `x` held between zero and `size - 1`."""
    return min(max(x, 0.0), Float64(size - 1))


def _mix(a: Float32, b: Float32, t: Float32) -> Float32:
    """Return the blend of `a` and `b` at `t`."""
    return a + (b - a) * t
