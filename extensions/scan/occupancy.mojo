# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An occupancy grid: which cubes of a scanned place hold a surface.

A splat scan holds surfaces, not solids: the splats sit on the walls, the
floors and the furniture. The grid divides a box of the building's
coordinates into cubes of one edge length, the voxels. Each splat adds
its opacity to the voxel that holds its center, and to the voxels within
one standard deviation of it along each building axis, up to `reach`
voxels on each side. A voxel whose sum reaches `solid_weight` is solid.

Two filters keep the grid on the place and off the noise of a scan:

- A splat whose opacity is below `min_opacity` adds nothing. Faint
  splats in the air are what a scan's floaters mostly are.
- With no region given, the box is the splat centers' range on each axis
  with a fraction `trim` of the splats left out at each end. The sky and
  the far background of a scan are a few splats far away.

The grid is dense. `max_voxels` refuses a box and an edge that would need
more voxels than a caller wants to hold: four bytes each.
"""

from core.gaussian_splat_utils import GaussianSplatGeometry
from extensions.scan.frame import ScanFrame
from generators.utils import Vec3d
from math.finite import (
    require_positive_finite,
    require_unit_finite,
)
from std.math import ceil, floor, isfinite, sqrt
from units.si import Length64, METER


@fieldwise_init
struct OccupancyOptions(ImplicitlyCopyable):
    """How splats fill an occupancy grid; see the module docstring."""

    var voxel: Length64
    """The edge of a voxel."""
    var min_opacity: Float64
    """The least opacity, 0 to 1, of a splat that counts."""
    var solid_weight: Float64
    """The summed opacity that makes a voxel solid."""
    var reach: Int
    """The most voxels a splat reaches on each side of its center."""
    var trim: Float64
    """The fraction, 0 to under one half, of splats left out at each end of each axis when no region is given."""
    var max_voxels: Int
    """The most voxels a grid may have."""

    def check(self) raises:
        """Refuse options that cannot make a grid.

        Raises:
            Error: If the voxel or the solid weight is not positive and
                finite, the least opacity is not 0 to 1, the reach is
                negative, the trim is not 0 to under one half, or the
                voxel limit is not positive.
        """
        require_positive_finite(
            self.voxel.to(METER), "Occupancy: the voxel must be positive"
        )
        require_unit_finite(
            self.min_opacity, "Occupancy: the least opacity must be 0 to 1"
        )
        require_positive_finite(
            self.solid_weight, "Occupancy: the solid weight must be positive"
        )
        if self.reach < 0:
            raise Error("Occupancy: the reach cannot be negative")
        if not (self.trim >= 0 and self.trim < 0.5):
            raise Error("Occupancy: the trim must be 0 to under one half")
        if self.max_voxels < 1:
            raise Error("Occupancy: the voxel limit must be positive")


def default_occupancy_options() -> OccupancyOptions:
    """Return options for a room or a house.

    Returns:
        Ten centimeter voxels, splats of a quarter opacity or more, a solid
        weight of one half, a reach of two voxels, half a percent trimmed
        at each end, and up to 2^27 voxels.
    """
    return OccupancyOptions(Length64(0.1, METER), 0.25, 0.5, 2, 0.005, 1 << 27)


@fieldwise_init
struct ScanRegion(ImplicitlyCopyable):
    """A box of building coordinates, in meters."""

    var low: Vec3d
    """The corner with the least x, y and z."""
    var high: Vec3d
    """The corner with the most x, y and z."""

    def check(self) raises:
        """Refuse a box that is not finite or has no volume.

        Raises:
            Error: If a corner is not finite, or `high` is not above `low`
                on each axis.
        """
        var corners: List[Float64] = [
            self.low.x,
            self.low.y,
            self.low.z,
            self.high.x,
            self.high.y,
            self.high.z,
        ]
        for value in corners:  # pragma: no branch
            if not isfinite(value):
                raise Error("Occupancy: a region corner must be finite")
        if not (
            self.high.x > self.low.x
            and self.high.y > self.low.y
            and self.high.z > self.low.z
        ):
            raise Error("Occupancy: a region must be above its low corner")


struct OccupancyGrid(Copyable, Movable):
    """The summed opacity of each voxel of a box; see the module
    docstring."""

    var origin: Vec3d
    """The low corner of voxel (0, 0, 0), in meters."""
    var voxel: Length64
    """The edge of a voxel."""
    var nx: Int
    """How many voxels along x."""
    var ny: Int
    """How many voxels along y."""
    var nz: Int
    """How many voxels along z."""
    var weights: List[Float32]
    """The summed opacity of each voxel, x fastest, then y, then z."""
    var solid_weight: Float64
    """The sum that makes a voxel solid."""

    def __init__(
        out self,
        origin: Vec3d,
        voxel: Length64,
        nx: Int,
        ny: Int,
        nz: Int,
        solid_weight: Float64,
    ) raises:
        """Make a grid with every voxel empty.

        Args:
            origin: The low corner, in meters.
            voxel: The edge of a voxel.
            nx: Voxels along x.
            ny: Voxels along y.
            nz: Voxels along z.
            solid_weight: The sum that makes a voxel solid.

        Raises:
            Error: If a count is not positive, or the voxel or the solid
                weight is not positive and finite.
        """
        if nx < 1 or ny < 1 or nz < 1:
            raise Error("Occupancy: a grid has at least one voxel each way")
        require_positive_finite(
            voxel.to(METER), "Occupancy: the voxel must be positive"
        )
        require_positive_finite(
            solid_weight, "Occupancy: the solid weight must be positive"
        )
        self.origin = origin
        self.voxel = voxel
        self.nx = nx
        self.ny = ny
        self.nz = nz
        self.weights = List[Float32](length=nx * ny * nz, fill=0)
        self.solid_weight = solid_weight

    def contains(self, i: Int, j: Int, k: Int) -> Bool:
        """Return True if a voxel index is inside the grid.

        Args:
            i: The index along x.
            j: The index along y.
            k: The index along z.

        Returns:
            Whether each index is from zero to below its count.
        """
        return (
            i >= 0
            and i < self.nx
            and j >= 0
            and j < self.ny
            and k >= 0
            and k < self.nz
        )

    def index(self, i: Int, j: Int, k: Int) -> Int:
        """Return where a voxel's weight is in `weights`.

        Args:
            i: The index along x.
            j: The index along y.
            k: The index along z.

        Returns:
            `(k * ny + j) * nx + i`.
        """
        return (k * self.ny + j) * self.nx + i

    def is_solid(self, i: Int, j: Int, k: Int) -> Bool:
        """Return True if a voxel is inside the grid and solid.

        Args:
            i: The index along x.
            j: The index along y.
            k: The index along z.

        Returns:
            Whether the voxel's weight reaches the solid weight. A voxel
            outside the grid is empty.
        """
        if not self.contains(i, j, k):
            return False
        return Float64(self.weights[self.index(i, j, k)]) >= self.solid_weight

    def solid_count(self) -> Int:
        """Return how many voxels are solid.

        Returns:
            The count.
        """
        var count = 0
        for weight in self.weights:  # pragma: no branch
            if Float64(weight) >= self.solid_weight:
                count += 1
        return count

    def corner(self, i: Int, j: Int, k: Int) -> Vec3d:
        """Return the low corner of a voxel, in meters.

        Args:
            i: The index along x.
            j: The index along y.
            k: The index along z.

        Returns:
            The corner. An index outside the grid gives a corner outside it.
        """
        var edge = self.voxel.to(METER)
        return self.origin + Vec3d(Float64(i), Float64(j), Float64(k)) * edge

    def top(self) -> Float64:
        """Return the elevation of the grid's top face, in meters.

        Returns:
            The origin's z plus nz voxels.
        """
        return self.origin.z + Float64(self.nz) * self.voxel.to(METER)


struct _Kept(Copyable, Movable):
    """The splats that count, in building coordinates."""

    var centers: List[Vec3d]
    """The centers, in meters."""
    var sigmas: List[Vec3d]
    """The standard deviations along x, y and z, in meters."""
    var opacities: List[Float64]
    """The opacities, 0 to 1."""

    def __init__(out self):
        self.centers = List[Vec3d]()
        self.sigmas = List[Vec3d]()
        self.opacities = List[Float64]()


def _kept(
    geometry: GaussianSplatGeometry, frame: ScanFrame, min_opacity: Float64
) raises -> _Kept:
    """Return the splats whose opacity counts, with the standard deviation
    of each along the turned building axes.

    Args:
        geometry: The splats.
        frame: The scan's frame.
        min_opacity: The least opacity that counts.

    Returns:
        The splats.

    Raises:
        Error: If the frame is not valid.
    """
    var kept = _Kept()
    var map = frame.map()
    var c = map.cos
    var s = map.sin
    for splat in range(geometry.count()):
        var opacity = Float64(geometry.colors[splat * 4 + 3]) / 255
        if opacity < min_opacity:
            continue
        var at = splat * 3
        kept.centers.append(
            map.place(
                Vec3d(
                    Float64(geometry.centers[at]),
                    Float64(geometry.centers[at + 1]),
                    Float64(geometry.centers[at + 2]),
                )
            )
        )
        var v = map.covariance(geometry.covariances, splat * 6)
        # The variances along x and y after the heading turn.
        var xx = c * c * v[0] - 2 * c * s * v[1] + s * s * v[3]
        var yy = s * s * v[0] + 2 * c * s * v[1] + c * c * v[3]
        kept.sigmas.append(
            Vec3d(
                sqrt(max(xx, Float64(0))),
                sqrt(max(yy, Float64(0))),
                sqrt(max(v[5], Float64(0))),
            )
        )
        kept.opacities.append(opacity)
    return kept^


def _trimmed(values: List[Float64], trim: Float64) -> Tuple[Float64, Float64]:
    """Return the range of values with a fraction left out at each end.

    Args:
        values: At least one value.
        trim: The fraction, 0 to under one half.

    Returns:
        The least and the most of the values that are kept.
    """
    var sorted = values.copy()
    sort(sorted)
    var count = len(sorted)
    var cut = Int(floor(trim * Float64(count)))
    return (sorted[cut], sorted[count - 1 - cut])


def trimmed_region(
    geometry: GaussianSplatGeometry,
    frame: ScanFrame,
    options: OccupancyOptions,
) raises -> ScanRegion:
    """Return the box that holds a scan's splats, less the far few.

    Args:
        geometry: The splats.
        frame: The scan's frame.
        options: The least opacity and the trim.

    Returns:
        The box, one voxel larger than the kept range on each side.

    Raises:
        Error: If the frame or the options are not valid, or no splat is
            opaque enough.
    """
    frame.check()
    options.check()
    var kept = _kept(geometry, frame, options.min_opacity)
    if len(kept.centers) == 0:
        raise Error("Occupancy: no splat is opaque enough to count")
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    for p in kept.centers:  # pragma: no branch
        xs.append(p.x)
        ys.append(p.y)
        zs.append(p.z)
    var x = _trimmed(xs, options.trim)
    var y = _trimmed(ys, options.trim)
    var z = _trimmed(zs, options.trim)
    var edge = options.voxel.to(METER)
    return ScanRegion(
        Vec3d(x[0] - edge, y[0] - edge, z[0] - edge),
        Vec3d(x[1] + edge, y[1] + edge, z[1] + edge),
    )


def _count(low: Float64, high: Float64, edge: Float64) -> Float64:
    """Return how many voxels cover a range, as a float that cannot
    overflow.

    Args:
        low: The range's start.
        high: Its end, above the start.
        edge: The voxel edge.

    Returns:
        At least one.
    """
    return max(Float64(1), ceil((high - low) / edge))


def occupancy_grid(
    geometry: GaussianSplatGeometry,
    frame: ScanFrame,
    options: OccupancyOptions,
    region: ScanRegion,
) raises -> OccupancyGrid:
    """Return the occupancy grid of a scan inside a box.

    Args:
        geometry: The splats.
        frame: The scan's frame.
        options: How splats fill the grid.
        region: The box, in building coordinates. `trimmed_region` gives
            the box of the whole scan.

    Returns:
        The grid; see the module docstring.

    Raises:
        Error: If the frame, the options or the region is not valid, or
            the grid would have more than `max_voxels` voxels.
    """
    frame.check()
    options.check()
    region.check()
    var edge = options.voxel.to(METER)
    var x = _count(region.low.x, region.high.x, edge)
    var y = _count(region.low.y, region.high.y, edge)
    var z = _count(region.low.z, region.high.z, edge)
    # In floats, so a huge region is refused instead of overflowing.
    if x * y * z > Float64(options.max_voxels):
        raise Error(
            "Occupancy: the region needs more than "
            + String(options.max_voxels)
            + " voxels; use a larger voxel or a smaller region"
        )
    var nx = Int(x)
    var ny = Int(y)
    var nz = Int(z)
    var grid = OccupancyGrid(
        region.low, options.voxel, nx, ny, nz, options.solid_weight
    )
    var kept = _kept(geometry, frame, options.min_opacity)
    for splat in range(len(kept.centers)):
        var d = (kept.centers[splat] - region.low) * (1 / edge)
        var i = Int(floor(d.x))
        var j = Int(floor(d.y))
        var k = Int(floor(d.z))
        if not grid.contains(i, j, k):
            continue
        var sigma = kept.sigmas[splat]
        var ri = min(options.reach, Int(sigma.x / edge))
        var rj = min(options.reach, Int(sigma.y / edge))
        var rk = min(options.reach, Int(sigma.z / edge))
        var weight = Float32(kept.opacities[splat])
        for kk in range(
            max(0, k - rk), min(nz, k + rk + 1)
        ):  # pragma: no branch
            for jj in range(
                max(0, j - rj), min(ny, j + rj + 1)
            ):  # pragma: no branch
                for ii in range(
                    max(0, i - ri), min(nx, i + ri + 1)
                ):  # pragma: no branch
                    grid.weights[grid.index(ii, jj, kk)] += weight
    return grid^
