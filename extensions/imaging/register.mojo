# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rigid registration of two volumes: the turn and the shift that align them.

Two scans of one patient seldom line up. The patient moves between them,
and two scanners place their volumes apart. `register_rigid(fixed,
moving, metric, start, levels, stride)` finds the rigid transform `T`
that takes each point of the fixed volume to the same tissue in the
moving volume, so that `moving(T(p))` matches `fixed(p)`:

1. `T(p) = R (p - c) + c + t`. `R` turns by an angle about an axis
   through the center `c`, and `t` is a shift. The search varies the
   rotation vector of `R`, in radians, and `t`, in millimeters.
2. The metric compares the fixed values at a lattice of voxels, one each
   `s` voxels along each axis, with the moving values at `T(p)` by
   trilinear interpolation. A point that `T` takes outside the box of the
   moving voxel centers does not count. When fewer than a tenth of the
   points count, the cost is 1e300.
3. `MEAN_SQUARES` is the mean of the squared differences, for two scans
   of one kind. `MUTUAL_INFORMATION` is minus the mutual information of
   a joint histogram of 32 by 32 bins, for two kinds of scans such as CT
   and MR. Each value spreads over its two nearest bins, so the cost
   changes smoothly.
4. `minimize_simplex` minimizes the cost at each level, from steps of
   0.05 rad and 4 mm at the first level, halved at each level after it.
   The lattice of level `n` from 0 is `stride * 2^(levels - 1 - n)`
   voxels. A Gaussian of half that lattice blurs both volumes at a level
   whose lattice is more than one voxel.

`resample_transformed` and `resample_labels_transformed` then bring the
moving volume and its labels onto the fixed grid through `T`.
"""

from extensions.imaging.filter import gaussian_filter
from extensions.imaging.ids import (
    MEAN_SQUARES,
    MUTUAL_INFORMATION,
    RegistrationMetric,
    require_metric,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from extensions.imaging.reformat import sample_point
from extensions.imaging.simplex import SimplexCost, minimize_simplex
from extensions.sdf.vector import V3, cross, dot, length, v3
from std.math import atan2, cos, floor, isfinite, log, max, min, sin
from units.si import Angle64, Length64, METER, RADIAN

# The bins of each axis of the joint histogram.
comptime BINS = 32
# The first steps of the search: radians of rotation and millimeters of
# shift.
comptime ROTATION_STEP = 0.05
comptime SHIFT_STEP = 4.0
# The search of a level stops when the simplex is this many steps across.
comptime TOLERANCE = 1.0e-3
comptime MOST_ITERATIONS = 600
# The cost when too few points of the lattice fall in the moving volume.
comptime NO_OVERLAP = 1.0e300


def _rows(r: V3) -> Tuple[V3, V3, V3]:
    """Return the rows of the rotation of a rotation vector, in radians."""
    var theta = length(r)
    if not (theta > 0):
        return (v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1))
    var k = r * (1.0 / theta)
    var c = cos(theta)
    var s = sin(theta)
    var t = 1.0 - c
    return (
        v3(t * k.x * k.x + c, t * k.x * k.y - s * k.z, t * k.x * k.z + s * k.y),
        v3(t * k.x * k.y + s * k.z, t * k.y * k.y + c, t * k.y * k.z - s * k.x),
        v3(t * k.x * k.z - s * k.y, t * k.y * k.z + s * k.x, t * k.z * k.z + c),
    )


struct RigidTransform(Copyable, ImplicitlyCopyable, Movable):
    """A turn about a center, then a shift: `T(p) = R (p - c) + c + t`."""

    var axis: V3
    """The unit axis of the turn."""
    var angle: Angle64
    """The angle of the turn, right-handed about the axis."""
    var center: V3
    """The center of the turn, in meters."""
    var shift: V3
    """The shift after the turn, in meters."""

    def __init__(out self, center: V3):
        """Create the transform that moves no point, about a center.

        Args:
            center: The center of the turns that a search tries, such as
                the middle of the fixed volume.
        """
        self.axis = v3(0, 0, 1)
        self.angle = Angle64(0.0, RADIAN)
        self.center = center
        self.shift = v3(0, 0, 0)

    def __init__(
        out self, axis: V3, angle: Angle64, center: V3, shift: V3
    ) raises:
        """Create a turn about an axis through a center, and a shift.

        Args:
            axis: The axis of the turn. It need not be a unit vector.
            angle: The angle of the turn.
            center: The center of the turn, in meters.
            shift: The shift after the turn, in meters.

        Raises:
            Error: If the axis is zero or not finite, or the angle is not
                finite.
        """
        var size = length(axis)
        if not (size > 0) or not isfinite(size):
            raise Error("A rotation axis must be finite and not zero")
        if not isfinite(angle.to(RADIAN)):
            raise Error("A rotation angle must be finite")
        self.axis = axis * (1.0 / size)
        self.angle = angle
        self.center = center
        self.shift = shift

    def _vector(self) -> V3:
        """Return the rotation vector, in radians."""
        return self.axis * self.angle.to(RADIAN)

    def apply(self, point: V3) -> V3:
        """Return the transform of a point.

        Args:
            point: The point, in meters.

        Returns:
            `R (point - c) + c + t`, in meters.
        """
        var rows = _rows(self._vector())
        var d = point - self.center
        return (
            v3(dot(rows[0], d), dot(rows[1], d), dot(rows[2], d))
            + self.center
            + self.shift
        )

    def inverse(self) -> RigidTransform:
        """Return the transform that undoes this one.

        Returns:
            The turn back about `c + t`, and the shift `-t`.
        """
        var out = RigidTransform(self.center + self.shift)
        out.axis = self.axis
        out.angle = Angle64(-self.angle.to(RADIAN), RADIAN)
        out.shift = self.shift * -1.0
        return out


def _from_vector(point: List[Float64], center: V3) -> RigidTransform:
    """Return the transform of a search point: a rotation vector in
    radians and a shift in millimeters."""
    var r = v3(point[0], point[1], point[2])
    var out = RigidTransform(center)
    var theta = length(r)
    if theta > 0:
        out.axis = r * (1.0 / theta)
        out.angle = Angle64(theta, RADIAN)
    out.shift = v3(point[3], point[4], point[5]) * 0.001
    return out


def largest_difference(
    a: RigidTransform, b: RigidTransform, volume: ImageVolume
) -> Length64:
    """Return how far apart two transforms take the corners of a volume.

    Args:
        a: One transform.
        b: The other transform.
        volume: The volume whose eight corner voxel centers are moved.

    Returns:
        The largest distance between `a(p)` and `b(p)` over the corners.
    """
    var most = 0.0
    for corner in range(8):  # pragma: no branch
        var p = volume.patient_point(
            Float64((corner & 1) * (volume.nx - 1)),
            Float64(((corner >> 1) & 1) * (volume.ny - 1)),
            Float64(((corner >> 2) & 1) * (volume.nz - 1)),
        )
        most = max(most, length(a.apply(p) - b.apply(p)))
    return Length64(most, METER)


def resample_transformed(
    volume: ImageVolume,
    target: ImageVolume,
    transform: RigidTransform,
    outside: Float32,
) raises -> ImageVolume:
    """Return a volume brought onto another grid through a transform.

    Each voxel of the result takes the trilinear value of `volume` at the
    transform of the patient position of the same voxel of `target`.

    Args:
        volume: The moving volume.
        target: The fixed volume, whose grid the result takes.
        transform: The transform from the fixed to the moving volume, as
            `register_rigid` gives it.
        outside: The value where the transform leaves the box of the
            voxel centers of `volume`.

    Returns:
        The volume on the fixed grid, with the window of `volume`.

    Raises:
        Error: If the target's grid cannot be made.
    """
    var out = ImageVolume(
        target.nx,
        target.ny,
        target.nz,
        target.spacing_x,
        target.spacing_y,
        target.spacing_z,
    )
    out.origin = target.origin
    out.axis_x = target.axis_x
    out.axis_y = target.axis_y
    out.axis_z = target.axis_z
    out.window_center = volume.window_center
    out.window_width = volume.window_width
    for k in range(out.nz):  # pragma: no branch
        for j in range(out.ny):  # pragma: no branch
            for i in range(out.nx):  # pragma: no branch
                var p = out.patient_point(Float64(i), Float64(j), Float64(k))
                out.values[out.index(i, j, k)] = sample_point(
                    volume, transform.apply(p), outside
                )
    return out^


def resample_labels_transformed(
    map: LabelMap,
    placed: ImageVolume,
    target: ImageVolume,
    transform: RigidTransform,
) raises -> LabelMap:
    """Return a label map brought onto another grid through a transform.

    Each voxel of the result takes the label of the voxel of `map` whose
    center is nearest the transform of its patient position, rounded half
    up along each axis.

    Args:
        map: The labels of the moving volume.
        placed: The moving volume, which places the map.
        target: The fixed volume, whose grid the result takes.
        transform: The transform from the fixed to the moving volume.

    Returns:
        The labels on the fixed grid. A voxel whose nearest center is
        outside the map is the background.

    Raises:
        Error: If `map` and `placed` differ in grid.
    """
    require_same_grid(map, placed)
    var out = LabelMap(target)
    for k in range(target.nz):  # pragma: no branch
        for j in range(target.ny):  # pragma: no branch
            for i in range(target.nx):  # pragma: no branch
                var p = target.patient_point(Float64(i), Float64(j), Float64(k))
                var q = placed.voxel_point(transform.apply(p))
                var x = Int(floor(q.x + 0.5))
                var y = Int(floor(q.y + 0.5))
                var z = Int(floor(q.z + 0.5))
                if map.contains(x, y, z):
                    out.labels[out.index(i, j, k)] = map.labels[
                        map.index(x, y, z)
                    ]
    return out^


struct Registration(Copyable, Movable):
    """The end of a registration."""

    var transform: RigidTransform
    """The transform from the fixed volume to the moving volume."""
    var cost: Float64
    """The metric at the end of the last level: a mean square, or minus
    the mutual information in nats."""
    var overlap: Float64
    """The part of the last lattice that falls in the moving volume."""
    var evaluations: Int
    """How many times the metric was taken, over every level."""

    def __init__(
        out self,
        transform: RigidTransform,
        cost: Float64,
        overlap: Float64,
        evaluations: Int,
    ):
        """Create a result.

        Args:
            transform: The transform.
            cost: The metric at the end.
            overlap: The part of the lattice in the moving volume.
            evaluations: The evaluations of the metric.
        """
        self.transform = transform
        self.cost = cost
        self.overlap = overlap
        self.evaluations = evaluations


def _spread(mut joint: List[Float64], row: Int, u: Float64, place: Float64):
    """Add one pair of values to a joint histogram, each spread over its
    two nearest bins: the fixed bin row and weight, and the moving place
    in bins."""
    var bin = max(0, min(Int(floor(place)), BINS - 2))
    var w = place - Float64(bin)
    joint[row + bin] += (1.0 - u) * (1.0 - w)
    joint[row + bin + 1] += (1.0 - u) * w
    joint[row + BINS + bin] += u * (1.0 - w)
    joint[row + BINS + bin + 1] += u * w


struct _Problem(SimplexCost):
    """The metric of one level, over a lattice of the fixed volume."""

    var moving: ImageVolume
    var metric: RegistrationMetric
    var center: V3
    var points: List[V3]
    var values: List[Float64]
    var bins: List[Int]
    var weights: List[Float64]
    var low: Float64
    var span: Float64
    var inside: Int

    def __init__(
        out self,
        fixed: ImageVolume,
        var moving: ImageVolume,
        metric: RegistrationMetric,
        center: V3,
        stride: Int,
    ) raises:
        self.moving = moving^
        self.metric = metric
        self.center = center
        self.points = List[V3]()
        self.values = List[Float64]()
        self.bins = List[Int]()
        self.weights = List[Float64]()
        self.low = 0.0
        self.span = 1.0
        self.inside = 0
        # Each axis starts at a voxel of the grid, so each loop runs.
        var half = stride // 2
        for k in range(  # pragma: no branch
            min(half, fixed.nz - 1), fixed.nz, stride
        ):
            for j in range(  # pragma: no branch
                min(half, fixed.ny - 1), fixed.ny, stride
            ):
                for i in range(  # pragma: no branch
                    min(half, fixed.nx - 1), fixed.nx, stride
                ):
                    self.points.append(
                        fixed.patient_point(Float64(i), Float64(j), Float64(k))
                    )
                    self.values.append(Float64(fixed.get(i, j, k)))
        if metric == MUTUAL_INFORMATION:
            var a = fixed.value_range()
            var b = self.moving.value_range()
            if not (a[1] > a[0]) or not (b[1] > b[0]):
                raise Error(
                    "Mutual information needs two volumes whose values vary"
                )
            var low = Float64(a[0])
            var span = Float64(a[1]) - low
            for v in self.values:  # pragma: no branch
                var place = (v - low) / span * Float64(BINS - 1)
                var bin = min(Int(floor(place)), BINS - 2)
                self.bins.append(bin)
                self.weights.append(place - Float64(bin))
            self.low = Float64(b[0])
            self.span = Float64(b[1]) - self.low

    def cost(mut self, point: List[Float64]) -> Float64:
        """Return the metric of the transform of a search point.

        Args:
            point: A rotation vector in radians and a shift in mm.

        Returns:
            The mean square, or minus the mutual information, or 1e300
            when too few points fall in the moving volume.
        """
        ref m = self.moving
        var rows = _rows(v3(point[0], point[1], point[2]))
        var shift = v3(point[3], point[4], point[5]) * 0.001
        # voxel = A (R (p - c) + c + t - origin), with A the rows of the
        # moving axes over their spacings.
        var a0 = m.axis_x * (1.0 / m.spacing_x.to(METER))
        var a1 = m.axis_y * (1.0 / m.spacing_y.to(METER))
        var a2 = m.axis_z * (1.0 / m.spacing_z.to(METER))
        var r0 = rows[0] * a0.x + rows[1] * a0.y + rows[2] * a0.z
        var r1 = rows[0] * a1.x + rows[1] * a1.y + rows[2] * a1.z
        var r2 = rows[0] * a2.x + rows[1] * a2.y + rows[2] * a2.z
        var reach = self.center + shift - m.origin
        var b0 = dot(a0, reach) - dot(r0, self.center)
        var b1 = dot(a1, reach) - dot(r1, self.center)
        var b2 = dot(a2, reach) - dot(r2, self.center)
        var top = v3(Float64(m.nx - 1), Float64(m.ny - 1), Float64(m.nz - 1))
        var mean = self.metric == MEAN_SQUARES
        var sum = 0.0
        var joint = List[Float64]()
        if not mean:
            joint = List[Float64](length=BINS * BINS, fill=0.0)
        var inside = 0
        for s in range(len(self.points)):  # pragma: no branch
            ref p = self.points[s]
            var q = v3(dot(r0, p) + b0, dot(r1, p) + b1, dot(r2, p) + b2)
            # The least distance to a face of the box of voxel centers. It
            # is negative, or not a number, outside the box.
            var margin = min(
                min(min(q.x, q.y), q.z),
                min(min(top.x - q.x, top.y - q.y), top.z - q.z),
            )
            if not (margin >= 0):
                continue
            inside += 1
            var value = Float64(m.trilinear(q.x, q.y, q.z))
            if mean:
                sum += (self.values[s] - value) ** 2
                continue
            _spread(
                joint,
                self.bins[s] * BINS,
                self.weights[s],
                (value - self.low) / self.span * Float64(BINS - 1),
            )
        self.inside = inside
        # A lattice holds one point or more, so no point is too few.
        if inside * 10 < len(self.points):
            return NO_OVERLAP
        var total = Float64(inside)
        if mean:
            return sum / total
        var by_fixed = List[Float64](length=BINS, fill=0.0)
        var by_moving = List[Float64](length=BINS, fill=0.0)
        for a in range(BINS):  # pragma: no branch
            for b in range(BINS):  # pragma: no branch
                by_fixed[a] += joint[a * BINS + b]
                by_moving[b] += joint[a * BINS + b]
        var information = 0.0
        for a in range(BINS):  # pragma: no branch
            for b in range(BINS):  # pragma: no branch
                var h = joint[a * BINS + b]
                if h > 0:
                    information += (
                        h
                        / total
                        * log(h * total / (by_fixed[a] * by_moving[b]))
                    )
        return -information


def register_rigid(
    fixed: ImageVolume,
    moving: ImageVolume,
    metric: RegistrationMetric,
    start: RigidTransform,
    levels: Int,
    stride: Int,
) raises -> Registration:
    """Find the rigid transform that aligns a moving volume to a fixed one.

    Args:
        fixed: The fixed volume, whose lattice of voxels the metric reads.
        moving: The moving volume.
        metric: `MEAN_SQUARES` or `MUTUAL_INFORMATION`.
        start: The first transform. Its center is the center of every turn
            that the search tries, such as the middle of the fixed volume.
        levels: The levels of the search, from 1 to 4.
        stride: The lattice of the last level, from 1 to 8 voxels.

    Returns:
        The transform, the metric at its end, the part of the lattice in
        the moving volume, and the count of evaluations.

    Raises:
        Error: If the metric is not valid, a count is out of range, the
            volumes do not overlap at the start, or mutual
            information has a volume whose values do not vary.
    """
    require_metric(metric)
    if levels < 1 or levels > 4:
        raise Error("A registration has 1 to 4 levels")
    if stride < 1 or stride > 8:
        raise Error("A registration lattice is 1 to 8 voxels")
    var r = start._vector()
    var point: List[Float64] = [
        r.x,
        r.y,
        r.z,
        start.shift.x * 1000.0,
        start.shift.y * 1000.0,
        start.shift.z * 1000.0,
    ]
    var finest = min(
        fixed.spacing_x.to(METER),
        min(fixed.spacing_y.to(METER), fixed.spacing_z.to(METER)),
    )
    var cost = 0.0
    var overlap = 0.0
    var evaluations = 0
    for level in range(levels):  # pragma: no branch
        var lattice = stride << (levels - 1 - level)
        var problem: _Problem
        if lattice > 1:
            var sigma = Length64(0.5 * Float64(lattice) * finest, METER)
            problem = _Problem(
                gaussian_filter(fixed, sigma),
                gaussian_filter(moving, sigma),
                metric,
                start.center,
                lattice,
            )
        else:
            problem = _Problem(fixed, moving.copy(), metric, start.center, 1)
        # A later level starts where the level before it ended. When that
        # end overlaps too little, the search stays there, and `overlap`
        # shows it.
        if level == 0:
            if problem.cost(point) >= NO_OVERLAP:
                raise Error("The volumes do not overlap at the start")
        var scale = 1.0 / Float64(1 << level)
        var steps: List[Float64] = [
            ROTATION_STEP * scale,
            ROTATION_STEP * scale,
            ROTATION_STEP * scale,
            SHIFT_STEP * scale,
            SHIFT_STEP * scale,
            SHIFT_STEP * scale,
        ]
        var result = minimize_simplex(
            problem, point, steps, TOLERANCE, MOST_ITERATIONS
        )
        point = result.point.copy()
        cost = result.value
        evaluations += result.evaluations + 1
        _ = problem.cost(point)
        overlap = Float64(problem.inside) / Float64(len(problem.points))
    return Registration(
        _from_vector(point, start.center), cost, overlap, evaluations
    )
