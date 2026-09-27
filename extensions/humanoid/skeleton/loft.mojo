# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A skin envelope lofted through cross-sections of the anatomy inside it.

A limb's skin lies a fat layer and a dermis outside what it holds. This
file fits that surface directly. Each section is a transverse slice of
every inner solid at one station along the limb. The slice outline is
traced on `LOFT_RAYS` rays, closed as a convex hull, and pushed out by
the section's cover. Fat fills the gaps between muscles, so the hull
is the outline a hand feels.

    var loft = fit_loft(samples, AXIS_Y, ankle_y, hip_y, 30, covers)
    var d = loft_distance(loft, point)

An inner solid reaches the loft as `LoftSample` stations. A station
that `joins` its predecessor forms a tapered elliptical segment with
it. A lone station is an ellipsoid that reaches `reach` along the axis.

Between sections and between rays the radius is a Catmull-Rom spline.
The distance is the radial gap divided by the gradient of that radius,
a first-order signed distance that the mesher and the mass sampler
can both use.
"""

from extensions.humanoid.skeleton.field import Bounds, empty_bounds
from math.vector3 import Vector3
from std.math import atan2, cos, max, min, pi, sin, sqrt

# Rays around every section. Thirty-six resolve a calf's two heads and
# a shin's crest at a few millimeters.
comptime LOFT_RAYS = 36
# Sub-slices per section: its middle and either edge of its window. A
# lymph node narrower than the section spacing still reaches one.
comptime LOFT_SLICES = 3
# The loft runs along plus y: a leg, from the ankle to the hip.
comptime AXIS_Y = 1
# The loft runs along plus z: a foot, from the heel to the toes.
comptime AXIS_Z = 2


@fieldwise_init
struct LoftSample(ImplicitlyCopyable):
    """One elliptical cross-section of an inner solid.

    `ml` is the radius along x. `ap` is the radius along the other axis
    of the loft's plane: z for `AXIS_Y`, y for `AXIS_Z`. `reach` is the
    half-extent along the loft axis when the station stands alone, or
    zero to use the smaller radius. `joins` is True when the station
    continues the segment from the station before it.
    """

    var center: Vector3
    var ml: Float32
    var ap: Float32
    var reach: Float32
    var joins: Bool


@fieldwise_init
struct _Ellipse(ImplicitlyCopyable):
    """One slice of an inner solid in the section plane."""

    var u: Float32
    var v: Float32
    var a: Float32
    var b: Float32


struct Loft(Copyable, Movable):
    """Fitted sections and the spline through them."""

    # `AXIS_Y` or `AXIS_Z`.
    var axis: Int
    # Axis coordinate of the first section, in meters.
    var start: Float32
    # Axis distance between sections, in meters.
    var spacing: Float32
    # How many sections.
    var count: Int
    # Section centers in the plane, x then the other plane axis.
    var center_u: List[Float32]
    var center_v: List[Float32]
    # `count` rows of `LOFT_RAYS` radii, in meters.
    var radii: List[Float32]
    var low: Vector3
    var high: Vector3

    def __init__(out self, axis: Int, start: Float32, spacing: Float32):
        """Create an empty loft; `fit_loft` fills it.

        Args:
            axis: `AXIS_Y` or `AXIS_Z`.
            start: Axis coordinate of the first section.
            spacing: Axis distance between sections.
        """
        self.axis = axis
        self.start = start
        self.spacing = spacing
        self.count = 0
        self.center_u = List[Float32]()
        self.center_v = List[Float32]()
        self.radii = List[Float32]()
        self.low = Vector3(0, 0, 0)
        self.high = Vector3(0, 0, 0)

    def section_radius(self, section: Int, ray: Int) -> Float32:
        """Return one fitted radius.

        Args:
            section: Which section, from the start.
            ray: Which ray, counterclockwise from plus x.

        Returns:
            The radius, in meters.
        """
        return self.radii[section * LOFT_RAYS + ray]


def fit_loft(
    samples: List[LoftSample],
    axis: Int,
    start: Float32,
    end: Float32,
    count: Int,
    covers: List[Float32],
    fill: Int = 0,
) raises -> Loft:
    """Fit sections from `start` to `end` along `axis`.

    Args:
        samples: Stations of every inner solid.
        axis: `AXIS_Y` or `AXIS_Z`.
        start: Axis coordinate of the first section.
        end: Axis coordinate of the last section.
        count: How many sections, two or more.
        covers: Fat and dermis outside the hull, one per section.
        fill: Passes that fill a dip one section long, so a solid that
            enters one section and not its neighbors leaves no groove.
            Zero by default.

    Returns:
        The fitted loft.

    Raises:
        Error: If `axis` is not named, `count` is below two, `end` does
            not lie past `start`, or `covers` is not one per section.
    """
    if axis != AXIS_Y and axis != AXIS_Z:
        raise Error("A loft runs along AXIS_Y or AXIS_Z")
    if count < 2:
        raise Error("A loft needs two sections or more")
    if not (end > start):
        raise Error("A loft must end past its start")
    if len(covers) != count:
        raise Error("A loft needs one cover per section")
    var spacing = (end - start) / Float32(count - 1)
    var loft = Loft(axis, start, spacing)
    loft.count = count
    # First pass: every section's slices and its center. A section past
    # the last solid, behind a heel or beyond a toe, has none.
    var sections = List[List[List[_Ellipse]]]()
    var filled = List[Bool]()
    var reaches = _reaches(samples, axis)
    var section = 0
    while section < count:
        var at = start + spacing * Float32(section)
        # Only the stations whose reach meets this section's window.
        var near = _near(reaches, at - spacing, at + spacing)
        var slices = List[List[_Ellipse]]()
        var any = False
        var sub = 0
        while sub < LOFT_SLICES:
            var offset = (
                Float32(sub) / Float32(LOFT_SLICES - 1) - Float32(0.5)
            ) * spacing
            var slice = _slice(samples, near, axis, at + offset)
            if len(slice) > 0:
                any = True
            slices.append(slice^)
            sub += 1
        var center = _centroid(slices)
        loft.center_u.append(center[0])
        loft.center_v.append(center[1])
        filled.append(any)
        sections.append(slices^)
        section += 1
    # An empty section takes the center of the nearest one that is not,
    # so the solid tapers to its cover there and rounds off.
    section = 0
    while section < count:
        if not filled[section]:
            var near = _nearest_filled(filled, section)
            if near >= 0:
                loft.center_u[section] = loft.center_u[near]
                loft.center_v[section] = loft.center_v[near]
        section += 1
    # Smoothed centers keep the spline between sections from shearing.
    # A section keeps its own center when the smoothed one would fall
    # outside what it holds.
    var raw_u = loft.center_u.copy()
    var raw_v = loft.center_v.copy()
    _smooth_centers(loft)
    var box = empty_bounds()
    section = 0
    while section < count:
        var at = start + spacing * Float32(section)
        var cu = loft.center_u[section]
        var cv = loft.center_v[section]
        var support = _section_support(sections[section], cu, cv)
        if filled[section] and _least(support) < Float32(0.002):
            cu = raw_u[section]
            cv = raw_v[section]
            loft.center_u[section] = cu
            loft.center_v[section] = cv
            support = _section_support(sections[section], cu, cv)
        var ray = 0
        while ray < LOFT_RAYS:
            support[ray] += covers[section]
            ray += 1
        var hull = _polygon_radii(support)
        ray = 0
        while ray < LOFT_RAYS:
            var r = hull[ray]
            loft.radii.append(r)
            var angle = _ray_angle(ray)
            _include(
                box,
                _point(axis, cu + r * cos(angle), cv + r * sin(angle), at),
            )
            ray += 1
        section += 1
    _fill_dips(loft, fill)
    var padded = box.padded(max(spacing, Float32(0.004)))
    loft.low = padded.low
    loft.high = padded.high
    return loft^


def _fill_dips(mut loft: Loft, passes: Int):
    """Raise each inner section's reach to its neighbors' mean.

    The neighbors' reach is measured along the same ray from this
    section's center, so sections with different centers compare
    fairly. Radii only grow, so every solid stays inside. The end
    sections keep their taper.
    """
    var done = 0
    while done < passes:
        var before = loft.radii.copy()
        var section = 1
        while section < loft.count - 1:
            var cu = loft.center_u[section]
            var cv = loft.center_v[section]
            var ray = 0
            while ray < LOFT_RAYS:
                var angle = _ray_angle(ray)
                var ux = cos(angle)
                var uz = sin(angle)
                var here = section * LOFT_RAYS + ray
                var below = before[here - LOFT_RAYS] + (
                    (loft.center_u[section - 1] - cu) * ux
                    + (loft.center_v[section - 1] - cv) * uz
                )
                var above = before[here + LOFT_RAYS] + (
                    (loft.center_u[section + 1] - cu) * ux
                    + (loft.center_v[section + 1] - cv) * uz
                )
                var mean = Float32(0.5) * (below + above)
                if mean > loft.radii[here]:
                    loft.radii[here] = mean
                ray += 1
            section += 1
        done += 1


def _smooth_centers(mut loft: Loft):
    """Blend each inner center with its neighbors, twice."""
    var passes = 0
    while passes < 2:
        var u = loft.center_u.copy()
        var v = loft.center_v.copy()
        var section = 1
        while section < loft.count - 1:
            loft.center_u[section] = Float32(0.25) * (
                u[section - 1] + 2 * u[section] + u[section + 1]
            )
            loft.center_v[section] = Float32(0.25) * (
                v[section - 1] + 2 * v[section] + v[section + 1]
            )
            section += 1
        passes += 1


def _section_support(
    slices: List[List[_Ellipse]], cu: Float32, cv: Float32
) -> List[Float32]:
    """Return each ray's support over every slice of one section."""
    var support = List[Float32](length=LOFT_RAYS, fill=0)
    var sub = 0
    while sub < LOFT_SLICES:
        _extend(support, slices[sub], cu, cv)
        sub += 1
    return support^


def _least(values: List[Float32]) -> Float32:
    """Return the smallest value."""
    var least = values[0]
    for index in range(1, len(values)):
        least = min(least, values[index])
    return least


def loft_distance(loft: Loft, point: Vector3) -> Float32:
    """Return how far `point` lies outside the loft, in meters.

    Negative is inside. Past either end section the loft is cut flat,
    so the solid ends where the sections end.

    Args:
        loft: A loft from `fit_loft`.
        point: A point in the limb frame, in meters.

    Returns:
        The signed distance, in meters.
    """
    var along = _along(point, loft.axis)
    var last = loft.start + loft.spacing * Float32(loft.count - 1)
    var clamped = min(max(along, loft.start), last)
    var radial = _radial(loft, point, clamped)
    var beyond = max(loft.start - along, along - last)
    if beyond <= 0:
        return radial
    var outside = Vector3(max(radial, Float32(0)), beyond, 0)
    return outside.length() + min(max(radial, beyond), Float32(0))


def _radial(loft: Loft, point: Vector3, along: Float32) -> Float32:
    """Return the radial gap at axis coordinate `along`, normalized."""
    var s = (along - loft.start) / loft.spacing
    var index = Int(s)
    if index > loft.count - 2:
        index = loft.count - 2
    var t = s - Float32(index)
    var w = _spline_weights(t)
    var dw = _spline_slopes(t)
    var cu = Float32(0)
    var cv = Float32(0)
    var dcu = Float32(0)
    var dcv = Float32(0)
    var k = 0
    while k < 4:
        var row = _clamp_index(index - 1 + k, loft.count)
        cu += w[k] * loft.center_u[row]
        cv += w[k] * loft.center_v[row]
        dcu += dw[k] * loft.center_u[row]
        dcv += dw[k] * loft.center_v[row]
        k += 1
    var plane = _plane(point, loft.axis)
    var du = plane[0] - cu
    var dv = plane[1] - cv
    var rho = sqrt(du * du + dv * dv)
    var angle = atan2(dv, du)
    if angle < 0:
        angle += Float32(2 * pi)
    var step = Float32(2 * pi) / Float32(LOFT_RAYS)
    var r_pos = angle / step
    var ray = Int(r_pos)
    var q = r_pos - Float32(ray)
    var wq = _spline_weights(q)
    var dwq = _spline_slopes(q)
    var radius = Float32(0)
    var by_angle = Float32(0)
    var by_axis = Float32(0)
    var j = 0
    while j < 4:
        var column = (ray - 1 + j + LOFT_RAYS) % LOFT_RAYS
        var value = Float32(0)
        var slope = Float32(0)
        k = 0
        while k < 4:
            var row = _clamp_index(index - 1 + k, loft.count)
            var r = loft.section_radius(row, column)
            value += w[k] * r
            slope += dw[k] * r
            k += 1
        radius += wq[j] * value
        by_angle += dwq[j] * value
        by_axis += wq[j] * slope
        j += 1
    var gap = rho - radius
    # The gradient of rho - R(angle, along): the angular term over rho,
    # and the axial term including the drift of the center.
    var tangential = Float32(0)
    if rho > Float32(1e-6):
        tangential = by_angle / step / rho
    var axial = by_axis / loft.spacing
    if rho > Float32(1e-6):
        axial += (du * dcu + dv * dcv) / (rho * loft.spacing)
    var norm = sqrt(1 + tangential * tangential + axial * axial)
    return gap / norm


def _reaches(
    samples: List[LoftSample], axis: Int
) -> List[Tuple[Float32, Float32]]:
    """Return how far along the axis each station, and the segment it
    starts, reaches: its lowest and highest coordinate."""
    var reaches = List[Tuple[Float32, Float32]]()
    var count = len(samples)
    for index in range(count):
        var sample = samples[index]
        var here = _along(sample.center, axis)
        var widest = max(max(sample.ml, sample.ap), sample.reach)
        var low = here - widest
        var high = here + widest
        if index + 1 < count and samples[index + 1].joins:
            var next = samples[index + 1]
            var there = _along(next.center, axis)
            var far = max(next.ml, next.ap)
            low = min(low, there - far)
            high = max(high, there + far)
        reaches.append((low, high))
    return reaches^


def _near(
    reaches: List[Tuple[Float32, Float32]], low: Float32, high: Float32
) -> List[Int]:
    """Return the stations whose reach meets the window `low` to `high`."""
    var near = List[Int]()
    for index in range(len(reaches)):
        if reaches[index][1] >= low and reaches[index][0] <= high:
            near.append(index)
    return near^


def _slice(
    samples: List[LoftSample], near: List[Int], axis: Int, at: Float32
) -> List[_Ellipse]:
    """Return the outline at axis coordinate `at` of the stations `near`.

    A joined pair of stations is a tapered segment. The plane cuts it in
    an ellipse when the segment crosses the plane steeply, and in a long
    strip when the segment runs along the plane, as a tendon over an
    ankle does in a foot's section. Both are traced the same way: by
    the round slices of the segment at points along the stretch that
    lies within its radius of the plane.
    """
    var out = List[_Ellipse]()
    var count = len(samples)
    for k in range(len(near)):
        var index = near[k]
        var sample = samples[index]
        var reach = sample.reach
        if reach <= 0:
            reach = min(sample.ml, sample.ap)
        _add_round(out, sample.center, sample.ml, sample.ap, reach, at, axis)
        if index + 1 < count and samples[index + 1].joins:
            _add_segment(out, sample, samples[index + 1], at, axis)
    return out^


def _add_segment(
    mut out: List[_Ellipse],
    a: LoftSample,
    b: LoftSample,
    at: Float32,
    axis: Int,
):
    """Add the slices of the segment from `a` to `b` near the plane."""
    var za = _along(a.center, axis)
    var zb = _along(b.center, axis)
    var widest = max(max(a.ml, a.ap), max(b.ml, b.ap))
    var t0 = Float32(0)
    var t1 = Float32(1)
    var dz = zb - za
    if abs(dz) > Float32(1.0e-6):
        var ta = (at - widest - za) / dz
        var tb = (at + widest - za) / dz
        t0 = max(Float32(0), min(ta, tb))
        t1 = min(Float32(1), max(ta, tb))
    # The plane misses the segment's reach altogether.
    if t1 < t0:
        return
    # The segment's own crossing of the plane, where its slice is widest.
    if abs(dz) > Float32(1.0e-6):
        var cross = (at - za) / dz
        if cross >= 0 and cross <= 1:
            _add_round(
                out,
                a.center + (b.center - a.center) * cross,
                a.ml + (b.ml - a.ml) * cross,
                a.ap + (b.ap - a.ap) * cross,
                min(a.ml + (b.ml - a.ml) * cross, a.ap + (b.ap - a.ap) * cross),
                at,
                axis,
            )
    var run = (b.center - a.center).length() * (t1 - t0)
    var finest = max(min(min(a.ml, a.ap), min(b.ml, b.ap)), Float32(1.0e-4))
    var steps = Int(run / (Float32(0.5) * finest)) + 2
    if steps > 16:
        steps = 16
    var k = 0
    while k < steps:
        var t = t0 + (t1 - t0) * Float32(k) / Float32(steps - 1)
        var center = a.center + (b.center - a.center) * t
        var ml = a.ml + (b.ml - a.ml) * t
        var ap = a.ap + (b.ap - a.ap) * t
        _add_round(out, center, ml, ap, min(ml, ap), at, axis)
        k += 1


def _add_round(
    mut out: List[_Ellipse],
    center: Vector3,
    ml: Float32,
    ap: Float32,
    reach: Float32,
    at: Float32,
    axis: Int,
):
    """Add the slice of an ellipsoid at `center` if the plane cuts it."""
    var gap = at - _along(center, axis)
    if gap >= reach or gap <= -reach:
        return
    var ratio = gap / reach
    var scale = sqrt(1 - ratio * ratio)
    var plane = _plane(center, axis)
    out.append(_Ellipse(plane[0], plane[1], ml * scale, ap * scale))


def _nearest_filled(filled: List[Bool], section: Int) -> Int:
    """Return the nearest section that holds a solid, or -1."""
    var step = 1
    while step < len(filled):
        if section - step >= 0 and filled[section - step]:
            return section - step
        if section + step < len(filled) and filled[section + step]:
            return section + step
        step += 1
    return -1


def _centroid(slices: List[List[_Ellipse]]) -> Tuple[Float32, Float32]:
    """Return the middle of the extent of every slice of a section.

    The middle of the extent and not the centroid of area: at the ankle
    the Achilles tendon behind and the tendons in front are small, and
    an area centroid would sit with whichever side had more of them.
    An empty section returns the origin; `fit_loft` replaces it.
    """
    var all = List[_Ellipse]()
    for sub in range(len(slices)):
        for index in range(len(slices[sub])):
            all.append(slices[sub][index])
    if len(all) > 0:
        return _middle_of(all)
    return (Float32(0), Float32(0))


def _middle_of(outline: List[_Ellipse]) -> Tuple[Float32, Float32]:
    """Return the middle of the box that holds every ellipse."""
    var low_u = outline[0].u - outline[0].a
    var high_u = outline[0].u + outline[0].a
    var low_v = outline[0].v - outline[0].b
    var high_v = outline[0].v + outline[0].b
    for index in range(1, len(outline)):
        var e = outline[index]
        low_u = min(low_u, e.u - e.a)
        high_u = max(high_u, e.u + e.a)
        low_v = min(low_v, e.v - e.b)
        high_v = max(high_v, e.v + e.b)
    return (
        Float32(0.5) * (low_u + high_u),
        Float32(0.5) * (low_v + high_v),
    )


def _extend(
    mut support: List[Float32],
    slice: List[_Ellipse],
    cu: Float32,
    cv: Float32,
):
    """Grow each ray's support to the farthest reach of every ellipse.

    The support along a direction is how far the slice reaches that
    way, measured from the center. It is exact for every ellipse, so no
    solid can fall between two rays.
    """
    for ray in range(LOFT_RAYS):
        var angle = _ray_angle(ray)
        var ux = cos(angle)
        var uz = sin(angle)
        for index in range(len(slice)):
            support[ray] = max(
                support[ray], _support_of(slice[index], cu, cv, ux, uz)
            )


def _support_of(
    e: _Ellipse, cu: Float32, cv: Float32, ux: Float32, uz: Float32
) -> Float32:
    """Return how far one ellipse reaches from (cu, cv) along (ux, uz)."""
    return (
        (e.u - cu) * ux
        + (e.v - cv) * uz
        + sqrt(e.a * e.a * ux * ux + e.b * e.b * uz * uz)
    )


def _polygon_radii(support: List[Float32]) -> List[Float32]:
    """Return the radii of the polygon the support lines enclose.

    Each ray's support is a tangent line of the hull. Those lines bound
    a polygon that holds the hull and exceeds it by less than half a
    percent at thirty-six rays. Along one ray the polygon ends at the
    nearest of the lines within a quarter turn either side.
    """
    var quarter = LOFT_RAYS // 4
    var facing = List[Float32]()
    for turn in range(quarter):
        facing.append(cos(_ray_angle(turn)))
    var radii = List[Float32](length=LOFT_RAYS, fill=0)
    for ray in range(LOFT_RAYS):
        var nearest = support[ray]
        for turn in range(1, quarter):
            nearest = min(
                nearest,
                min(
                    support[(ray + turn) % LOFT_RAYS],
                    support[(ray - turn + LOFT_RAYS) % LOFT_RAYS],
                )
                / facing[turn],
            )
        radii[ray] = max(nearest, Float32(1.0e-4))
    return radii^


def _spline_weights(t: Float32) -> SIMD[DType.float32, 4]:
    """Return the Catmull-Rom weights of four stations at `t`."""
    var t2 = t * t
    var t3 = t2 * t
    return SIMD[DType.float32, 4](
        Float32(0.5) * (-t3 + 2 * t2 - t),
        Float32(0.5) * (3 * t3 - 5 * t2 + 2),
        Float32(0.5) * (-3 * t3 + 4 * t2 + t),
        Float32(0.5) * (t3 - t2),
    )


def _spline_slopes(t: Float32) -> SIMD[DType.float32, 4]:
    """Return the derivatives of `_spline_weights` at `t`."""
    var t2 = t * t
    return SIMD[DType.float32, 4](
        Float32(0.5) * (-3 * t2 + 4 * t - 1),
        Float32(0.5) * (9 * t2 - 10 * t),
        Float32(0.5) * (-9 * t2 + 8 * t + 1),
        Float32(0.5) * (3 * t2 - 2 * t),
    )


def _clamp_index(index: Int, count: Int) -> Int:
    """Return `index` held inside `0 ..< count`."""
    return min(max(index, 0), count - 1)


def _ray_angle(ray: Int) -> Float32:
    """Return the angle of one ray, counterclockwise from plus x."""
    return Float32(ray) * Float32(2 * pi) / Float32(LOFT_RAYS)


def _along(point: Vector3, axis: Int) -> Float32:
    """Return the coordinate of `point` along the loft axis."""
    if axis == AXIS_Y:
        return point.y
    return point.z


def _plane(point: Vector3, axis: Int) -> Tuple[Float32, Float32]:
    """Return x and the other plane coordinate of `point`."""
    if axis == AXIS_Y:
        return (point.x, point.z)
    return (point.x, point.y)


def _point(axis: Int, u: Float32, v: Float32, along: Float32) -> Vector3:
    """Return the limb-frame point at plane (u, v) and `along`."""
    if axis == AXIS_Y:
        return Vector3(u, along, v)
    return Vector3(u, v, along)


def _include(mut box: Bounds, point: Vector3):
    """Grow `box` to hold `point`."""
    box.include_sphere(point, 0)
