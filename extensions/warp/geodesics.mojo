# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Geodesics through a closed-form metric, and the sky that a passenger sees.

A free particle or a ray of light follows a geodesic:

    d²xᵃ/dλ² = -Γᵃ_bc (dxᵇ/dλ)(dxᶜ/dλ)

`trace_geodesic` integrates it with the classical fourth-order
Runge-Kutta method, from the exact Christoffel symbols of an
`AnalyticMetric`. Places are c t, x, y and z, in meters.

`passenger_view` traces one ray back in time from an observer for each
pixel of a camera that looks along +x, the direction of travel, with +z
up. Each ray ends where it leaves a sphere about the origin. There the
Eulerian observer, at rest with the stars in a comoving warp metric,
says which direction of the sky the light came from. `draw_view` paints
those directions with a grid of lines on the sky, so the picture shows
how the bubble bends and shifts the stars.

The camera is at rest in the Eulerian frame at its place. Light from the
sky reaches it along the traced rays, so the picture includes the
aberration and the lensing of the metric, but not the change of color.
"""

from std.math import asin, atan2, cos, isfinite, nan, round, sqrt, tan

from extensions.warp.analytic import AnalyticMetric, christoffel_symbols
from extensions.warp.frame import eulerian_transform
from extensions.warp.jet import Jet
from extensions.warp.quantities import SPEED_OF_LIGHT
from extensions.warp.solver import task_count
from extensions.warp.tensor import Matrix4, Vector4, apply4, inverse4
from render.framebuffer import Color, Framebuffer
from render.tasks import TaskGroup
from units.si import Angle64, Duration64, Length64

comptime _PI = 3.141592653589793


def metric_at[M: AnalyticMetric](metric: M, place: Vector4) -> Matrix4:
    """Return g_ab of a closed-form metric at a place.

    Parameters:
        M: The type of the metric.

    Args:
        metric: The metric.
        place: The coordinates c t, x, y and z, in meters.

    Returns:
        The covariant components.
    """
    var jets: List[Jet] = [
        Jet.constant(place[0]),
        Jet.constant(place[1]),
        Jet.constant(place[2]),
        Jet.constant(place[3]),
    ]
    var g = metric.components(jets)
    var out = Matrix4(0)
    for k in range(16):
        out[k] = g[k].value
    return out


def geodesic_acceleration[
    M: AnalyticMetric
](metric: M, place: Vector4, velocity: Vector4) raises -> Vector4:
    """Return d²xᵃ/dλ² = -Γᵃ_bc uᵇ uᶜ.

    Parameters:
        M: The type of the metric.

    Args:
        metric: The metric.
        place: The coordinates, in meters.
        velocity: The tangent uᵃ = dxᵃ/dλ.

    Returns:
        The acceleration of the coordinates.

    Raises:
        Error: If the metric is singular at the place.
    """
    var gamma = christoffel_symbols(metric, place)
    var out = Vector4(0)
    for a in range(4):
        var total = 0.0
        for b in range(4):
            for c in range(4):
                total += gamma[16 * a + 4 * b + c] * velocity[b] * velocity[c]
        out[a] = -total
    return out


struct Geodesic(Copyable, Movable):
    """The places along a traced geodesic."""

    var places: List[Vector4]
    """The coordinates at each step, from the start, in meters."""
    var velocity: Vector4
    """The tangent at the last place."""
    var escaped: Bool
    """Whether the geodesic left the escape sphere."""

    def __init__(
        out self, var places: List[Vector4], velocity: Vector4, escaped: Bool
    ):
        """Hold a traced geodesic.

        Args:
            places: The places along it.
            velocity: The tangent at the last place.
            escaped: Whether it left the escape sphere.
        """
        self.places = places^
        self.velocity = velocity
        self.escaped = escaped


def _distance(place: Vector4) -> Float64:
    """Return the distance of a place from the spatial origin."""
    return sqrt(place[1] * place[1] + place[2] * place[2] + place[3] * place[3])


def trace_geodesic[
    M: AnalyticMetric
](
    metric: M,
    place: Vector4,
    velocity: Vector4,
    step: Length64,
    max_steps: Int,
    escape: Length64,
) raises -> Geodesic:
    """Integrate a geodesic by the fourth-order Runge-Kutta method.

    Parameters:
        M: The type of the metric.

    Args:
        metric: The metric.
        place: The start, c t, x, y and z, in meters.
        velocity: The tangent at the start. A ray of light needs a null
            tangent: see `null_velocity`.
        step: The step in the affine parameter, in meters of the tangent.
        max_steps: The most steps to take. 1 or more.
        escape: The radius of the sphere about the origin where tracing
            stops.

    Returns:
        The places, the last tangent and whether the sphere was left.

    Raises:
        Error: If the step or the escape radius is not positive and
            finite, `max_steps` is less than 1, or the metric is singular
            along the way.
    """
    if not (isfinite(step.value) and step.value > 0.0):
        raise Error("A geodesic step must be positive and finite")
    if not (isfinite(escape.value) and escape.value > 0.0):
        raise Error("An escape radius must be positive and finite")
    if max_steps < 1:
        raise Error("A geodesic needs at least one step")
    var h = step.value
    var x = place
    var u = velocity
    var places: List[Vector4] = [x]
    for _ in range(max_steps):  # pragma: no branch
        var a1 = geodesic_acceleration(metric, x, u)
        var a2 = geodesic_acceleration(
            metric, x + 0.5 * h * u, u + 0.5 * h * a1
        )
        var a3 = geodesic_acceleration(
            metric, x + 0.5 * h * u + 0.25 * h * h * a1, u + 0.5 * h * a2
        )
        var a4 = geodesic_acceleration(
            metric, x + h * u + 0.5 * h * h * a2, u + h * a3
        )
        x = x + h * u + (h * h / 6.0) * (a1 + a2 + a3)
        u = u + (h / 6.0) * (a1 + 2.0 * a2 + 2.0 * a3 + a4)
        places.append(x)
        if _distance(x) > escape.value:
            return Geodesic(places^, u, True)
    return Geodesic(places^, u, False)


def null_velocity[
    M: AnalyticMetric
](metric: M, place: Vector4, spatial: Vector4) raises -> Vector4:
    """Return the future-directed null tangent with given space parts.

    Solves g_ab uᵃ uᵇ = 0 for u⁰ with u¹, u², u³ from `spatial`.

    Parameters:
        M: The type of the metric.

    Args:
        metric: The metric.
        place: The coordinates, in meters.
        spatial: The space components, in lanes 1 to 3.

    Returns:
        The tangent, with u⁰ > 0.

    Raises:
        Error: If g_00 is not negative there, so the time direction is not
            timelike, or there is no real root.
    """
    var g = metric_at(metric, place)
    if not (g[0] < 0.0):
        raise Error("The time direction is not timelike at this place")
    var b = 0.0
    var c = 0.0
    for i in range(1, 4):
        b += g[i] * spatial[i]
        for j in range(1, 4):
            c += g[4 * i + j] * spatial[i] * spatial[j]
    var root = b * b - g[0] * c
    if not (root >= 0.0):
        raise Error("There is no null direction with these space parts")
    var out = spatial
    out[0] = (-b - sqrt(root)) / g[0]
    return out


def proper_time[
    M: AnalyticMetric
](metric: M, places: List[Vector4]) raises -> Duration64:
    """Return the proper time along a worldline of places.

    Each step adds √(-g_ab Δxᵃ Δxᵇ) / c, with g at the midpoint.

    Parameters:
        M: The type of the metric.

    Args:
        metric: The metric.
        places: The places, in order.

    Returns:
        The time that a clock carried along the places shows.

    Raises:
        Error: If a step is not timelike.
    """
    var total = 0.0
    for k in range(1, len(places)):
        var d = places[k] - places[k - 1]
        var g = metric_at(metric, 0.5 * (places[k] + places[k - 1]))
        var square = 0.0
        for a in range(4):
            for b in range(4):
                square -= g[4 * a + b] * d[a] * d[b]
        if not (square > 0.0):
            raise Error("A worldline step is not timelike")
        total += sqrt(square)
    return Duration64(total / SPEED_OF_LIGHT.value)


def view_direction(
    column: Int, row: Int, columns: Int, rows: Int, field: Angle64
) -> Vector4:
    """Return the direction a camera pixel looks in.

    The camera looks along +x with +z up, so +y is to the left.

    Args:
        column: The pixel's column, from the left.
        row: The pixel's row, from the top.
        columns: The image width in pixels.
        rows: The image height in pixels.
        field: The horizontal field of view.

    Returns:
        The unit direction, in lanes 1 to 3.
    """
    var half = tan(field.value / 2.0)
    var right = half * (2.0 * (Float64(column) + 0.5) / Float64(columns) - 1.0)
    var up = (
        half
        * (1.0 - 2.0 * (Float64(row) + 0.5) / Float64(rows))
        * Float64(rows)
        / Float64(columns)
    )
    var v = Vector4(0.0, 1.0, -right, up)
    return v / sqrt((v * v).reduce_add())


def sky_direction[
    M: AnalyticMetric
](
    metric: M,
    observer: Vector4,
    look: Vector4,
    step: Length64,
    max_steps: Int,
    escape: Length64,
) raises -> Vector4:
    """Return the direction of the sky that an observer sees along a look.

    The observer is the Eulerian observer at its place. The ray that
    arrives from `look` is traced back in time until it leaves the escape
    sphere. The Eulerian observer there names the direction it came from.

    Parameters:
        M: The type of the metric.

    Args:
        metric: The metric.
        observer: The observer's place, in meters.
        look: The direction the observer looks in, in its own frame, as a
            unit vector in lanes 1 to 3.
        step: The step in the affine parameter.
        max_steps: The most steps to take.
        escape: The radius where the sky is read.

    Returns:
        The unit direction of the sky in lanes 1 to 3, or all NaN if the
        ray did not escape.

    Raises:
        Error: For the input that `trace_geodesic` refuses, or if a
            metric has no Eulerian frame at either end.
    """
    var start = eulerian_transform(metric_at(metric, observer))
    var back = look
    back[0] = -1.0
    var ray = trace_geodesic(
        metric, observer, apply4(start, back), step, max_steps, escape
    )
    if not ray.escaped:
        return Vector4(nan[DType.float64]())
    var end = eulerian_transform(
        metric_at(metric, ray.places[len(ray.places) - 1])
    )
    var local = apply4(inverse4(end), ray.velocity)
    local[0] = 0.0
    return local / sqrt((local * local).reduce_add())


__async def _view_chunk[
    M: AnalyticMetric
](
    metric: Pointer[M, ImmutAnyOrigin],
    observer: Vector4,
    columns: Int,
    rows: Int,
    field: Angle64,
    step: Length64,
    max_steps: Int,
    escape: Length64,
    skies: MutPointer[Vector4, MutAnyOrigin],
    failed: MutPointer[Int, MutAnyOrigin],
    task: Int,
    first: Int,
    past: Int,
):
    """Trace the pixels from `first` to `past`."""
    for pixel in range(first, past):  # pragma: no branch
        var look = view_direction(
            pixel % columns, pixel // columns, columns, rows, field
        )
        try:
            skies[unsafe_offset=pixel] = sky_direction(
                metric[], observer, look, step, max_steps, escape
            )
        except:
            failed[unsafe_offset=task] = 1


def passenger_view[
    M: AnalyticMetric
](
    metric: M,
    observer: Vector4,
    columns: Int,
    rows: Int,
    field: Angle64,
    step: Length64,
    max_steps: Int,
    escape: Length64,
    threads: Int = 0,
) raises -> List[Vector4]:
    """Return the sky direction seen in each pixel of a camera.

    Parameters:
        M: The type of the metric.

    Args:
        metric: The metric.
        observer: The camera's place, in meters.
        columns: The image width in pixels. 1 or more.
        rows: The image height in pixels. 1 or more.
        field: The horizontal field of view, above 0 and below π.
        step: The step in the affine parameter.
        max_steps: The most steps for each ray.
        escape: The radius where the sky is read.
        threads: The tasks to use. 0 means one for each logical core.

    Returns:
        One sky direction for each pixel, row by row from the top.

    Raises:
        Error: If the image is empty, the field of view is out of range,
            `threads` is negative, or a ray fails as `sky_direction`
            fails.
    """
    if columns < 1 or rows < 1:
        raise Error("A view needs at least one pixel")
    if not (field.value > 0.0 and field.value < _PI):
        raise Error("A field of view must be between 0 and pi")
    var count = columns * rows
    var tasks = task_count(threads, count)
    var out = List[Vector4](length=count, fill=Vector4(0))
    var failed = List[Int](length=tasks, fill=0)
    var group = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        group.create_task(
            _view_chunk(
                Pointer(to=metric).unsafe_origin_cast[ImmutAnyOrigin](),
                observer,
                columns,
                rows,
                field,
                step,
                max_steps,
                escape,
                out.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                failed.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                task,
                task * count // tasks,
                (task + 1) * count // tasks,
            )
        )
    group.wait()
    _ = len(out)
    for task in range(tasks):  # pragma: no branch
        if failed[task] != 0:
            raise Error("A ray could not be traced")
    return out^


def sky_color(direction: Vector4) -> Color:
    """Return the color of the test sky in a direction.

    The sky is a globe with its poles along ±x: lines every 15 degrees of
    latitude and longitude on a background whose hue turns with the
    longitude. The pole ahead, +x, is a red disk and the pole behind is a
    blue disk. A direction that is NaN, a ray that did not escape, is
    black.

    Args:
        direction: A unit direction in lanes 1 to 3.

    Returns:
        The color.
    """
    if not isfinite(direction[1]):
        return Color(0, 0, 0)
    var latitude = asin(max(-1.0, min(1.0, direction[1])))
    var longitude = atan2(direction[3], direction[2])
    var degrees = 180.0 / _PI
    if latitude * degrees > 85.0:
        return Color(230, 40, 40)
    if latitude * degrees < -85.0:
        return Color(40, 90, 230)
    var lat = latitude * degrees / 15.0
    var lon = longitude * degrees / 15.0
    var near_line = min(
        abs(lat - Float64(Int(round(lat)))), abs(lon - Float64(Int(round(lon))))
    )
    if near_line < 0.06:
        return Color(235, 235, 235)
    var turn = (longitude + _PI) / (2.0 * _PI)
    var shade = 0.35 + 0.25 * (latitude / _PI + 0.5)
    return Color(
        UInt8(Int(255.0 * shade * (0.6 + 0.4 * cos(2.0 * _PI * turn)))),
        UInt8(
            Int(
                255.0
                * shade
                * (0.6 + 0.4 * cos(2.0 * _PI * (turn - 1.0 / 3.0)))
            )
        ),
        UInt8(
            Int(
                255.0
                * shade
                * (0.6 + 0.4 * cos(2.0 * _PI * (turn - 2.0 / 3.0)))
            )
        ),
    )


def draw_view(
    directions: List[Vector4], columns: Int, rows: Int
) raises -> Framebuffer:
    """Return a picture of the sky directions of a view.

    Args:
        directions: One direction for each pixel, row by row from the top.
        columns: The image width.
        rows: The image height.

    Returns:
        The frame.

    Raises:
        Error: If the list does not hold one direction for each pixel, or
            the frame is too large.
    """
    if len(directions) != columns * rows:
        raise Error("A view needs one direction for each pixel")
    var frame = Framebuffer(columns, rows, Color(0, 0, 0))
    for row in range(rows):  # pragma: no branch
        for column in range(columns):  # pragma: no branch
            frame.set_pixel(
                column, row, sky_color(directions[row * columns + column])
            )
    return frame^
