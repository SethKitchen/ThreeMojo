# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clean a scan of a building: leave out the splats that are not the building.

A trained scan holds more than its subject. A drone or a video sees the
sky, the far hills and the trees, and the trainer puts a few huge, faint
splats there. It also leaves floaters near the camera paths. These splats
cost time and hide the building when they are drawn. `clean_scan` leaves
out three kinds, each by one rule that does not depend on the scan's frame:

- **Outside.** A splat whose center is outside the box of the scan's body.
  The box holds all but `trim` of the centers at each end of each axis, and
  grows by `margin` of its size on each side.
- **Faint.** A splat whose opacity is below `min_opacity`. It adds almost
  nothing to a picture.
- **Huge.** A splat whose largest axis, taken out to three standard
  deviations, is longer than `max_extent` of the box's diagonal. A wall or
  a roof is made of many small splats. A splat that big is a sky or a haze.

`splat_subset` copies chosen splats of a scan, with their spherical
harmonics, into a new scan. `clean_scan` uses it, and so does
`part_splats`.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
    sh_band_words,
)
from extensions.scan.orient import largest_variance
from math.finite import require_finite
from std.math import sqrt

comptime CLEAN_SAMPLES = 1000000
"""How many centers set the box of a scan's body, at most."""


@fieldwise_init
struct CleanOptions(ImplicitlyCopyable):
    """The rules of `clean_scan`."""

    var trim: Float64
    """The share of the centers left out at each end of each axis when the
    box is found, from 0 up to 0.5."""
    var margin: Float64
    """How much the box grows on each side, as a share of its size, 0 or
    more."""
    var min_opacity: Float64
    """The least opacity a splat keeps, from 0 to 1."""
    var max_extent: Float64
    """The longest a splat's three-deviation extent can be, as a share of
    the box's diagonal, above 0."""

    def check(self) raises:
        """Refuse options that cannot clean a scan.

        Raises:
            Error: If a number is not finite, the trim is not 0 up to 0.5,
                the margin is negative, the opacity is not 0 to 1, or the
                extent is not positive.
        """
        require_finite(self.trim, "Scan clean: the trim must be finite")
        require_finite(self.margin, "Scan clean: the margin must be finite")
        require_finite(
            self.min_opacity, "Scan clean: the opacity must be finite"
        )
        require_finite(self.max_extent, "Scan clean: the extent must be finite")
        if not (self.trim >= 0 and self.trim < 0.5):
            raise Error("Scan clean: the trim is 0 up to 0.5")
        if self.margin < 0:
            raise Error("Scan clean: the margin is 0 or more")
        if not (self.min_opacity >= 0 and self.min_opacity <= 1):
            raise Error("Scan clean: the opacity is 0 to 1")
        if not (self.max_extent > 0):
            raise Error("Scan clean: the extent must be positive")


def default_clean_options() -> CleanOptions:
    """Return the options that suit a scan of a building.

    Returns:
        A trim of 0.5 percent, a margin of 15 percent, an opacity of 0.05
        and an extent of 5 percent of the diagonal.
    """
    return CleanOptions(0.005, 0.15, 0.05, 0.05)


@fieldwise_init
struct CleanReport(ImplicitlyCopyable):
    """What `clean_scan` kept and left out."""

    var kept: Int
    """How many splats it kept."""
    var outside: Int
    """How many it left out for a center outside the box."""
    var faint: Int
    """How many it left out for too little opacity, and not already outside."""
    var huge: Int
    """How many it left out for too long an axis, and not already out."""


struct CleanedScan(Movable):
    """The cleaned splats of a scan, and the report."""

    var geometry: GaussianSplatGeometry
    """The kept splats, in the scan's order and coordinates."""
    var report: CleanReport
    """What was kept and what was left out."""

    def __init__(
        out self, var geometry: GaussianSplatGeometry, report: CleanReport
    ):
        """Hold a cleaned scan.

        Args:
            geometry: The kept splats.
            report: The counts.
        """
        self.geometry = geometry^
        self.report = report


def _band_of(
    source: List[UInt8], kept: List[Int], band: Int, degree: Int
) raises -> List[UInt8]:
    """Return the bytes of one band of the kept splats.

    Args:
        source: The band's bytes for every splat.
        kept: The splats kept, in order.
        band: The band, 1 to 3.
        degree: The scan's degree.

    Returns:
        The kept splats' bytes of the band, or none above the degree.

    Raises:
        Error: Never, for a band of 1 to 3.
    """
    var out = List[UInt8]()
    if band > degree:
        return out^
    var words = sh_band_words(band) * 4
    out.reserve(len(kept) * words)
    for index in kept:  # pragma: no branch
        for n in range(words):  # pragma: no branch
            out.append(source[index * words + n])
    return out^


def splat_subset(
    geometry: GaussianSplatGeometry, kept: List[Int]
) raises -> GaussianSplatGeometry:
    """Copy chosen splats of a scan into a scan of their own.

    Args:
        geometry: The scan's splats.
        kept: The index of each splat to copy, in the order to copy them,
            each less than the count.

    Returns:
        The splats, with their centers, covariances, colors and spherical
        harmonics bytes as they are.

    Raises:
        Error: If an index is outside the scan.
    """
    var centers = List[Float32](capacity=len(kept) * 3)
    var covariances = List[Float32](capacity=len(kept) * 6)
    var colors = List[UInt8](capacity=len(kept) * 4)
    var count = geometry.count()
    for index in kept:  # pragma: no branch
        if index < 0 or index >= count:
            raise Error("Scan clean: splat " + String(index) + " is not there")
        for n in range(3):  # pragma: no branch
            centers.append(geometry.centers[index * 3 + n])
        for n in range(6):  # pragma: no branch
            covariances.append(geometry.covariances[index * 6 + n])
        for n in range(4):  # pragma: no branch
            colors.append(geometry.colors[index * 4 + n])
    var degree = geometry.spherical_harmonics_degree()
    return create_gaussian_splat_geometry(
        centers^,
        covariances^,
        colors^,
        _band_of(geometry.sh1, kept, 1, degree),
        _band_of(geometry.sh2, kept, 2, degree),
        _band_of(geometry.sh3, kept, 3, degree),
    )


def _bounds(
    geometry: GaussianSplatGeometry, axis: Int, trim: Float64
) -> Tuple[Float64, Float64]:
    """Return the trimmed least and most of the centers along one axis.

    Args:
        geometry: The splats.
        axis: 0, 1 or 2.
        trim: The share left out at each end.

    Returns:
        The least and the most value that remain.
    """
    var count = geometry.count()
    var step = max(1, count // CLEAN_SAMPLES)
    var values = List[Float32](capacity=count // step + 1)
    var index = 0
    while index < count:
        values.append(geometry.centers[index * 3 + axis])
        index += step
    sort(values)
    var last = len(values) - 1
    var low = Int(trim * Float64(last))
    var high = last - low
    return (Float64(values[low]), Float64(values[high]))


def _is_huge(covariances: List[Float32], at: Int, limit: Float64) -> Bool:
    """Return whether a splat's largest variance is above a limit.

    The trace bounds the largest variance from above. So a splat whose
    trace is within the limit is not huge, and only a splat with a large
    trace takes the exact power method.

    Args:
        covariances: Six numbers a splat.
        at: The first of the splat's six.
        limit: The variance that a splat must not pass.

    Returns:
        Whether it passes the limit.
    """
    var trace = (
        Float64(covariances[at])
        + Float64(covariances[at + 3])
        + Float64(covariances[at + 5])
    )
    return trace > limit and largest_variance(covariances, at) > limit


def clean_scan(
    geometry: GaussianSplatGeometry, options: CleanOptions
) raises -> CleanedScan:
    """Leave out the splats of a scan that are not its building.

    Args:
        geometry: The scan's splats.
        options: The rules.

    Returns:
        The kept splats, in the scan's order, and what was left out.

    Raises:
        Error: If the options are refused, the scan has no splat, or no
            splat is kept.
    """
    options.check()
    var count = geometry.count()
    if count == 0:
        raise Error("Scan clean: the scan has no splat")
    var low = List[Float64]()
    var high = List[Float64]()
    var diagonal = Float64(0)
    for axis in range(3):  # pragma: no branch
        var bounds = _bounds(geometry, axis, options.trim)
        var size = bounds[1] - bounds[0]
        low.append(bounds[0] - options.margin * size)
        high.append(bounds[1] + options.margin * size)
        var grown = high[axis] - low[axis]
        diagonal += grown * grown
    # A three-deviation extent: the variance's root, three times.
    var longest = options.max_extent * sqrt(diagonal) / 3
    var longest_variance = longest * longest
    var kept = List[Int]()
    var outside = 0
    var faint = 0
    var huge = 0
    for index in range(count):
        var inside = True
        for axis in range(3):  # pragma: no branch
            var c = Float64(geometry.centers[index * 3 + axis])
            if c < low[axis] or c > high[axis]:
                inside = False
        if not inside:
            outside += 1
        elif (
            Float64(geometry.colors[index * 4 + 3]) / 255 < options.min_opacity
        ):
            faint += 1
        elif _is_huge(geometry.covariances, index * 6, longest_variance):
            huge += 1
        else:
            kept.append(index)
    if len(kept) == 0:
        raise Error("Scan clean: no splat is kept")
    var report = CleanReport(len(kept), outside, faint, huge)
    return CleanedScan(splat_subset(geometry, kept), report)
