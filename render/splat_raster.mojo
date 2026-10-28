# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Drawing a `GaussianSplat` into a `RenderTarget` on the CPU.

Two steps, as for every other primitive. `prepare_gaussian_splat` runs on
the host: it sorts the splats back to front when the object's `auto_sort`
is on, evaluates their spherical harmonics for the camera, and projects
each one with `render.splatrule.project_splat`, in draw order.
`rasterize_splats` fills the projected splats in that order.
`render.gpu.GpuSplats` fills the same list on the device, one thread a
pixel, and the parity tests hold the two to the same image.

A splat blends with the normal mode, source over, with straight alpha, as
three.js's transparent splat material does. It tests depth against what
is drawn and writes none. The target keeps its depth mode, so a splat
drawn after `Renderer.render_into` is hidden by the opaque surfaces in
front of it. A center that does not fit in an integer lies past the image.

Draw a scene with splats in three steps:

1. `Renderer.render_into` draws the meshes, lines and points into a
   `RenderTarget`.
2. `draw_gaussian_splat` draws each `GaussianSplat` into the same target.
3. `RenderTarget.resolve` turns the light into an image.

Pass the renderer's viewport to place the splats in the same camera rectangle.
The target's scissor limits the pixels that blending can touch.

**Workers.** Each step takes a count of workers, one by default. The
sort and the projection share the splats out in runs. The projection
reads the splats in their own order, front to back, and then gathers them
in draw order. The fill shares the rows out in bands. It sorts the splats
by the bands their rows reach, keeping draw order in each band, and every
band blends its own splats in that order. So each pixel takes the same
blends in the same order as on one thread, and the picture is the same to
the bit. A row of a splat visits only the columns of its disc;
`splat_row_span` says why that draws what the whole box draws.
"""

from cameras.camera import Camera
from core.scene import Scene
from math.vector3 import Vector3
from objects.gaussian_splat import GaussianSplat
from render.framebuffer import FloatColor
from render.raster_state import DepthMode, log_depth_factor
from render.splatrule import (
    FloatRgba,
    ProjectedSplat,
    SPLAT_LANES,
    SPLAT_RADIUS_SQ,
    SplatView,
    project_splat,
    splat_alphas,
    splat_depth_passes,
    splat_reach,
)
from render.target import RenderTarget
from render.rect import Rect
from render.tasks import TaskGroup
from std.math import ceil, floor, fma, isfinite, max, min, sqrt
from units.si import Length, METER
from core.ordinal import require_valid

comptime SPLAT_BANDS_PER_WORKER = 8
"""How many bands of rows a fill worker has: a scan's splats crowd some rows, and more bands than workers share them out evenly."""
comptime SPLAT_RUN = 4096
"""The fewest splats a projection worker takes: a shorter run is not worth a task."""
comptime SPLAT_ROW_SLACK = Float64(1e-6)
"""How much taller, as a share, the rows that `splat_disc_rows` keeps are
than the disc: more than the rounding of `splat_row_span`'s `Float64`
discriminant."""
comptime SPLAT_SPAN_SLACK = Float64(1e-4)
"""How much wider, as a share of `SPLAT_RADIUS_SQ`, the disc whose row
spans `splat_row_span` finds is: far more than the rounding of
`splat_alpha`'s `Float32` arithmetic."""


def require_splat_depth(depth_mode: DepthMode) raises:
    """Refuse a Gaussian splat depth mode that is not named.

    Nothing. The call returns when the mode is named.

    Args:
        depth_mode: How the target stores depth.

    Raises:
        Error: If the mode is not one of the named depth modes.
    """
    require_valid(
        depth_mode.is_valid(), "A Gaussian splat needs a valid depth mode"
    )


def prepare_gaussian_splat[
    C: Camera
](
    scene: Scene,
    mut splat: GaussianSplat,
    camera: C,
    width: Int,
    height: Int,
    depth_mode: DepthMode,
    viewport: Optional[Rect] = None,
    workers: Int = 1,
) raises -> List[ProjectedSplat]:
    """Sort, color and project a splat object's splats, in draw order.

    Parameters:
        C: The camera's type.

    Args:
        scene: The scene, updated, that holds the object's node.
        splat: The splats. Their order is sorted again when `auto_sort` is
            on and the view needs it.
        camera: The camera to project through.
        width: The target's width in pixels.
        height: The target's height in pixels.
        depth_mode: How the target stores depth.
        viewport: The camera rectangle, or the whole target.
        workers: How many threads sort and project the splats; see the
            module docstring.

    Returns:
        The splats on the screen, furthest first once sorted. A splat
        three.js moves off the screen is left out, and so is every splat
        when the node is hidden or on no layer the camera draws.

    Raises:
        Error: If the depth mode is not valid, the node is not in the
            scene, the scene is stale, or a matrix cannot be inverted.
    """
    require_splat_depth(depth_mode)
    var rect = viewport.value() if Bool(viewport) else Rect.whole(width, height)
    require_valid(rect.is_valid(), "A Gaussian splat needs a valid viewport")
    var out = List[ProjectedSplat]()
    if not scene.shows(splat.node, camera.visible_layers()):
        return out^
    var world = scene.world_matrix(splat.node)
    var view = camera.view_matrix_in(scene)
    if splat.auto_sort:
        _ = splat.update_sort(
            world, view, Length(camera.near_distance(), METER), workers
        )
    var camera_world = view
    camera_world.invert()
    var local = world
    local.invert()
    var eye = local.transform_point(
        camera_world.transform_point(Vector3(0, 0, 0))
    )
    var place = SplatView(
        view * world,
        camera.projection_matrix(),
        rect.width,
        rect.height,
        depth_mode,
        log_depth_factor(camera.far_distance()),
    )
    var run = _SplatRun(
        place,
        eye,
        splat.splat_geometry.spherical_harmonics_degree(),
        Float32(rect.x),
        Float32(rect.top(height)),
    )
    var count = len(splat.order)
    var tasks = max(1, min(workers, count // SPLAT_RUN))
    # Project the splats in their own order, so that their arrays are read
    # front to back, and then gather them in draw order.
    var projected = List[ProjectedSplat](capacity=count)
    projected.resize(unsafe_uninit_length=count)
    var shown = List[Bool](length=count, fill=False)
    var projected_at = projected.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    var shown_at = shown.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    var order_at = splat.order.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    var starts = List[Int](length=tasks + 1, fill=0)
    if tasks == 1:
        _project_span(projected_at, shown_at, splat, run, 0, count)
        starts[1] = _shown_count(order_at, shown_at, 0, count)
    else:
        var group = TaskGroup()
        for task in range(tasks):  # pragma: no branch
            group.create_task(
                _project_task(
                    projected_at,
                    shown_at,
                    Pointer(to=splat).unsafe_origin_cast[MutAnyOrigin](),
                    Pointer(to=run).unsafe_origin_cast[MutAnyOrigin](),
                    task * count // tasks,
                    (task + 1) * count // tasks,
                )
            )
        group.wait()
        var counting = TaskGroup()
        for task in range(tasks):  # pragma: no branch
            counting.create_task(
                _count_task(
                    starts.unsafe_ptr()
                    .unsafe_offset(task + 1)
                    .unsafe_origin_cast[MutAnyOrigin](),
                    order_at,
                    shown_at,
                    task * count // tasks,
                    (task + 1) * count // tasks,
                )
            )
        counting.wait()
    for task in range(tasks):  # pragma: no branch
        starts[task + 1] += starts[task]
    out.resize(unsafe_uninit_length=starts[tasks])
    var out_at = out.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    if tasks == 1:
        _gather(out_at, order_at, shown_at, projected_at, 0, count)
    else:
        var gathering = TaskGroup()
        for task in range(tasks):  # pragma: no branch
            gathering.create_task(
                _gather_task(
                    out_at.unsafe_offset(starts[task]),
                    order_at,
                    shown_at,
                    projected_at,
                    task * count // tasks,
                    (task + 1) * count // tasks,
                )
            )
        gathering.wait()
    # The tasks reach the lists, `splat` and `run` through pointers the
    # compiler cannot see. These reads keep them alive until every task
    # has finished.
    _ = len(projected)
    _ = len(shown)
    _ = len(splat.order)
    _ = len(starts)
    _ = run.degree
    return out^


@fieldwise_init
struct _SplatRun(ImplicitlyCopyable):
    """What projecting a run of the draw order needs of the view."""

    var place: SplatView
    """The camera and the camera rectangle."""
    var eye: Vector3
    """The camera's position, in the object's space."""
    var degree: Int
    """The splats' spherical harmonics degree."""
    var left: Float32
    """The camera rectangle's first column in the target."""
    var top: Float32
    """The camera rectangle's first row in the target, from the top."""


def _project_span(
    projected: MutPointer[ProjectedSplat, MutAnyOrigin],
    shown: MutPointer[Bool, MutAnyOrigin],
    splat: GaussianSplat,
    run: _SplatRun,
    first: Int,
    past: Int,
):
    """Shade and project a run of the splats, in their own order.

    Args:
        projected: Each splat on the screen, written where `shown` is
            True.
        shown: Whether each splat is on the screen.
        splat: The splats.
        run: The view.
        first: The run's first splat.
        past: One past its last.
    """
    ref geometry = splat.splat_geometry
    # The run is inside the splats, so their arrays are read unchecked.
    var colors = geometry.colors.unsafe_ptr()
    var centers = geometry.centers.unsafe_ptr()
    for index in range(first, past):
        var color = FloatRgba(
            Float32(colors[unsafe_offset=index * 4]) / 255,
            Float32(colors[unsafe_offset=index * 4 + 1]) / 255,
            Float32(colors[unsafe_offset=index * 4 + 2]) / 255,
            Float32(colors[unsafe_offset=index * 4 + 3]) / 255,
        )
        if run.degree > 0:
            var shading = splat.spherical_harmonics_color(
                index, run.eye, run.degree
            )
            color.r += shading.x
            color.g += shading.y
            color.b += shading.z
        var found = project_splat(
            Vector3(
                centers[unsafe_offset=index * 3],
                centers[unsafe_offset=index * 3 + 1],
                centers[unsafe_offset=index * 3 + 2],
            ),
            geometry.covariances,
            index * 6,
            color,
            run.place,
        )
        if Bool(found):
            var placed = found.value()
            placed.x += run.left
            placed.y += run.top
            projected[unsafe_offset=index] = placed
            shown[unsafe_offset=index] = True


__async def _project_task(
    projected: MutPointer[ProjectedSplat, MutAnyOrigin],
    shown: MutPointer[Bool, MutAnyOrigin],
    splat: MutPointer[GaussianSplat, MutAnyOrigin],
    run: MutPointer[_SplatRun, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """`_project_span` as a task of `prepare_gaussian_splat`.

    The tasks only read the splats and the view, and each writes its own
    run of `projected` and `shown`.

    Args:
        projected: Each splat on the screen.
        shown: Whether each splat is on the screen.
        splat: The splats.
        run: The view.
        first: The run's first splat.
        past: One past its last.
    """
    _project_span(projected, shown, splat[], run[], first, past)


def _shown_count(
    order: MutPointer[Int, MutAnyOrigin],
    shown: MutPointer[Bool, MutAnyOrigin],
    first: Int,
    past: Int,
) -> Int:
    """Return how many splats of a run of the draw order are on the screen.

    Args:
        order: The draw order.
        shown: Whether each splat is on the screen.
        first: The run's first place in the order.
        past: One past its last place.

    Returns:
        The count.
    """
    var count = 0
    for position in range(first, past):
        if shown[unsafe_offset=order[unsafe_offset=position]]:
            count += 1
    return count


__async def _count_task(
    count: MutPointer[Int, MutAnyOrigin],
    order: MutPointer[Int, MutAnyOrigin],
    shown: MutPointer[Bool, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """`_shown_count` as a task of `prepare_gaussian_splat`.

    Args:
        count: Where the run's count goes.
        order: The draw order.
        shown: Whether each splat is on the screen.
        first: The run's first place in the order.
        past: One past its last place.
    """
    count[] = _shown_count(order, shown, first, past)


def _gather(
    drawn: MutPointer[ProjectedSplat, MutAnyOrigin],
    order: MutPointer[Int, MutAnyOrigin],
    shown: MutPointer[Bool, MutAnyOrigin],
    projected: MutPointer[ProjectedSplat, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Copy the splats of a run of the draw order that are on the screen,
    in that order.

    Args:
        drawn: Where the run's splats go.
        order: The draw order.
        shown: Whether each splat is on the screen.
        projected: Each splat on the screen.
        first: The run's first place in the order.
        past: One past its last place.
    """
    var at = 0
    for position in range(first, past):
        var index = order[unsafe_offset=position]
        if shown[unsafe_offset=index]:
            drawn[unsafe_offset=at] = projected[unsafe_offset=index]
            at += 1


__async def _gather_task(
    drawn: MutPointer[ProjectedSplat, MutAnyOrigin],
    order: MutPointer[Int, MutAnyOrigin],
    shown: MutPointer[Bool, MutAnyOrigin],
    projected: MutPointer[ProjectedSplat, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """`_gather` as a task of `prepare_gaussian_splat`.

    Args:
        drawn: Where the run's splats go.
        order: The draw order.
        shown: Whether each splat is on the screen.
        projected: Each splat on the screen.
        first: The run's first place in the order.
        past: One past its last place.
    """
    _gather(drawn, order, shown, projected, first, past)


def rasterize_splats(
    mut target: RenderTarget, splats: List[ProjectedSplat], workers: Int = 1
) raises:
    """Blend projected splats into a target, one after another.

    Args:
        target: The target. Its depth is tested and left as it is.
        splats: The splats, in the order to draw them.
        workers: How many bands of rows fill at once; see the module
            docstring.

    Raises:
        Error: If the target's depth mode is not valid.
    """
    require_splat_depth(target.depth_mode)
    var bands = min(workers * SPLAT_BANDS_PER_WORKER, target.height)
    if workers <= 1 or bands <= 1:
        for index in range(len(splats)):
            rasterize_splat(target, splats[index], 0, target.height - 1)
        return
    # Each band's splats, in draw order: a counting sort of the splats by
    # the bands that their rows reach, in runs, as `GaussianSplat.sort_cpu`
    # sorts. So a band reads only the splats that reach it.
    var count = len(splats)
    var runs = max(1, min(workers, count // SPLAT_RUN))
    var band_of = List[Int](capacity=target.height)
    for band in range(bands):  # pragma: no branch
        for _ in range(
            band * target.height // bands, (band + 1) * target.height // bands
        ):  # pragma: no branch
            band_of.append(band)
    var reach = List[Int32](length=count * 2, fill=0)
    var counts = List[Int](length=runs * bands, fill=0)
    var splats_at = splats.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    var band_at = band_of.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    var reach_at = reach.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    var count_at = counts.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    if runs == 1:
        _band_reach(
            splats_at, band_at, target.height, reach_at, count_at, 0, count
        )
    else:
        var reaching = TaskGroup()
        for run in range(runs):  # pragma: no branch
            reaching.create_task(
                _band_reach_task(
                    splats_at,
                    band_at,
                    target.height,
                    reach_at,
                    count_at.unsafe_offset(run * bands),
                    run * count // runs,
                    (run + 1) * count // runs,
                )
            )
        reaching.wait()
    # Each run's first place in each band: band by band, run by run.
    var starts = List[Int](length=bands + 1, fill=0)
    var sum = 0
    for band in range(bands):  # pragma: no branch
        starts[band] = sum
        for run in range(runs):  # pragma: no branch
            var here = counts[run * bands + band]
            counts[run * bands + band] = sum
            sum += here
    starts[bands] = sum
    var members = List[Int](capacity=sum)
    members.resize(unsafe_uninit_length=sum)
    var member_at = members.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    if runs == 1:
        _band_place(member_at, reach_at, count_at, 0, count)
    else:
        var placing = TaskGroup()
        for run in range(runs):  # pragma: no branch
            placing.create_task(
                _band_place_task(
                    member_at,
                    reach_at,
                    count_at.unsafe_offset(run * bands),
                    run * count // runs,
                    (run + 1) * count // runs,
                )
            )
        placing.wait()
    var errors = List[String](length=bands, fill=String())
    var group = TaskGroup()
    for band in range(bands):  # pragma: no branch
        group.create_task(
            _splat_band(
                Pointer(to=target).unsafe_origin_cast[MutAnyOrigin](),
                splats_at,
                member_at.unsafe_offset(starts[band]),
                starts[band + 1] - starts[band],
                errors.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                band,
                band * target.height // bands,
                (band + 1) * target.height // bands - 1,
            )
        )
    group.wait()
    # The tasks read the lists through pointers the compiler cannot see.
    # These reads keep them alive until every task has finished.
    _ = len(splats)
    _ = len(band_of)
    _ = len(reach)
    _ = len(counts)
    _ = len(members)
    raise_splat_band_errors(errors)


def _band_reach(
    splats: Pointer[ProjectedSplat, ImmutAnyOrigin],
    band_of: MutPointer[Int, MutAnyOrigin],
    height: Int,
    reach: MutPointer[Int32, MutAnyOrigin],
    counts: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Find the bands that a run of splats reaches, and count them.

    Args:
        splats: The splats, in draw order.
        band_of: The band of each row.
        height: The target's height in rows.
        reach: Each splat's first and last band, written for the run. The
            last is before the first for a splat that reaches no row.
        counts: The run's count of the splats that reach each band.
        first: The run's first splat.
        past: One past its last.
    """
    for index in range(first, past):
        var rows = splat_disc_rows(splats[unsafe_offset=index])
        var top = max(rows[0], 0)
        var bottom = min(rows[1], height - 1)
        var low = 1
        var high = 0
        if top <= bottom:
            low = band_of[unsafe_offset=top]
            high = band_of[unsafe_offset=bottom]
        reach[unsafe_offset=index * 2] = Int32(low)
        reach[unsafe_offset=index * 2 + 1] = Int32(high)
        for band in range(low, high + 1):
            counts[unsafe_offset=band] += 1


__async def _band_reach_task(
    splats: Pointer[ProjectedSplat, ImmutAnyOrigin],
    band_of: MutPointer[Int, MutAnyOrigin],
    height: Int,
    reach: MutPointer[Int32, MutAnyOrigin],
    counts: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """`_band_reach` as a task of `rasterize_splats`.

    Args:
        splats: The splats.
        band_of: The band of each row.
        height: The target's height.
        reach: Each splat's bands.
        counts: The run's counts.
        first: The run's first splat.
        past: One past its last.
    """
    _band_reach(splats, band_of, height, reach, counts, first, past)


def _band_place(
    members: MutPointer[Int, MutAnyOrigin],
    reach: MutPointer[Int32, MutAnyOrigin],
    next: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Put each splat of a run among the members of the bands it reaches.

    Args:
        members: Each band's splats, band after band.
        reach: Each splat's first and last band.
        next: The run's next place in each band.
        first: The run's first splat.
        past: One past its last.
    """
    for index in range(first, past):
        for band in range(
            Int(reach[unsafe_offset=index * 2]),
            Int(reach[unsafe_offset=index * 2 + 1]) + 1,
        ):
            members[unsafe_offset=next[unsafe_offset=band]] = index
            next[unsafe_offset=band] += 1


__async def _band_place_task(
    members: MutPointer[Int, MutAnyOrigin],
    reach: MutPointer[Int32, MutAnyOrigin],
    next: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """`_band_place` as a task of `rasterize_splats`.

    Args:
        members: Each band's splats.
        reach: Each splat's bands.
        next: The run's next places.
        first: The run's first splat.
        past: One past its last.
    """
    _band_place(members, reach, next, first, past)


__async def _splat_band(
    target: MutPointer[RenderTarget, MutAnyOrigin],
    splats: Pointer[ProjectedSplat, ImmutAnyOrigin],
    members: MutPointer[Int, MutAnyOrigin],
    count: Int,
    errors: MutPointer[String, MutAnyOrigin],
    band: Int,
    first_row: Int,
    last_row: Int,
):
    """Blend the splats that reach one band of rows into it, a task of
    `rasterize_splats`.

    A band owns its rows, so no two bands touch one pixel. A task cannot
    raise, so an error goes into the band's slot.

    Args:
        target: The target.
        splats: The splats, in draw order.
        members: The places in `splats` of the splats that reach the
            band, in draw order.
        count: How many members.
        errors: One slot a band.
        band: This band.
        first_row: Its first row.
        last_row: Its last row, inclusive.
    """
    try:
        require_splat_depth(target[].depth_mode)
        for member in range(count):
            rasterize_splat(
                target[],
                splats[unsafe_offset=members[unsafe_offset=member]],
                first_row,
                last_row,
            )
    except error:
        errors[unsafe_offset=band] = String(error)


def raise_splat_band_errors(errors: List[String]) raises:
    """Raise the first error a band of `rasterize_splats` carried back.

    `rasterize_splats` checks the depth mode before any band starts, and
    each band clamps its rows and columns to the target, so a band meets no
    error. This net catches a check that a later change puts inside a band.

    Args:
        errors: One slot a band, empty where the band finished.

    Raises:
        Error: The first band's error, if any band has one.
    """
    for band in range(len(errors)):
        if errors[band] != "":
            raise Error(errors[band])


def _splat_index(value: Float32, round_up: Bool) -> Int:
    """Return the pixel index of a splat edge.

    A value that is not finite, or that does not fit in an integer, is
    past every pixel. `Int` of such a float is not that coordinate.

    Args:
        value: The edge, in pixels.
        round_up: True to round toward positive infinity.

    Returns:
        The index, or `Int.MAX` or `Int.MIN` when `value` does not fit.
    """
    # `Float32(Int.MAX)` is 2^63, as `Float64(Int.MAX)` is, and the floor
    # of a `Float32` is a `Float32`: the same test and index without
    # `Float64`, which a Metal kernel cannot run.
    if not isfinite(value) or value >= Float32(Int.MAX):
        return Int.MAX
    if value <= -Float32(Int.MAX):
        return Int.MIN
    if round_up:
        return Int(ceil(value))
    return Int(floor(value))


def _splat_low(value: Float32, floor_at: Int) -> Int:
    """Return the first pixel at or before `value`, held at `floor_at`.

    Args:
        value: The near edge, in pixels.
        floor_at: The first pixel the band may touch.

    Returns:
        The column or row the walk starts at, or past the image.
    """
    var index = _splat_index(value, False)
    if index == Int.MIN:
        return floor_at
    if index == Int.MAX:
        return Int.MAX
    return max(index - 1, floor_at)


def _splat_high(value: Float32, ceil_at: Int) -> Int:
    """Return the last pixel at or after `value`, held at `ceil_at`.

    Args:
        value: The far edge, in pixels.
        ceil_at: The last pixel the band may touch.

    Returns:
        The column or row the walk ends at, or before the image.
    """
    var index = _splat_index(value, True)
    if index == Int.MAX:
        return ceil_at
    if index == Int.MIN:
        return Int.MIN
    return min(index + 1, ceil_at)


def rasterize_splat(
    mut target: RenderTarget,
    splat: ProjectedSplat,
    first_row: Int,
    last_row: Int,
) raises:
    """Blend one splat into a disjoint worker band.

    Args:
        target: The checked target.
        splat: One projected splat.
        first_row: The band's first row.
        last_row: The band's last row, inclusive.

    Raises:
        Error: If a target blend is refused.
    """
    var reach = splat_reach(splat)
    # The box, inside the target and its scissor. The scissor's corner
    # counts up from the bottom. An edge that is not finite, or that does
    # not fit in an integer, is past every pixel.
    ref cut = target.scissor
    var left = _splat_low(splat.x - reach[0], max(0, cut.x))
    var right = _splat_high(
        splat.x + reach[0], min(target.width - 1, cut.x + cut.width - 1)
    )
    var rule = _row_rule(splat)
    var rows = _rule_rows(rule, splat_rows(splat))
    var top = max(
        rows[0], max(max(0, first_row), target.height - cut.y - cut.height)
    )
    var bottom = min(
        rows[1],
        min(min(target.height - 1, last_row), target.height - 1 - cut.y),
    )
    if left > right or top > bottom:
        return
    # The return above leaves at least one row.
    for y in range(top, bottom + 1):  # pragma: no branch
        var span = _rule_span(rule, y, left, right)
        _blend_row(target, splat, y, span[0], span[1])


def splat_rows(splat: ProjectedSplat) -> Tuple[Int, Int]:
    """Return the rows that a splat's box spans, before any clamp.

    Args:
        splat: The splat.

    Returns:
        The first and the last row of its quad, with a row of margin at
        each end, as `rasterize_splat` takes them. An edge that is not
        finite, or that does not fit in an integer, is `Int.MAX` or
        `Int.MIN`, past every row.
    """
    var reach = splat_reach(splat)
    return (
        _splat_low(splat.y - reach[1], Int.MIN),
        _splat_high(splat.y + reach[1], Int.MAX),
    )


def splat_disc_rows(splat: ProjectedSplat) -> Tuple[Int, Int]:
    """Return the rows whose spans can hold a splat's disc.

    `splat_row_span` solves a quadratic along a row. Its discriminant is
    `4 a R - 4 dy^2 A B (ax^2 + ay^2)^2`, with `A` and `B` the inverse
    squared scales and `R` the slackened radius squared. So a row whose
    center is further than `h = sqrt(a R / (A B (ax^2 + ay^2)^2))` from
    the splat's center spans nothing. These are the rows within `h`, with
    `h` widened by `SPLAT_ROW_SLACK`, inside the box's rows. A tiny splat
    takes one or two rows, where its box takes four or five.

    Args:
        splat: The splat.

    Returns:
        The first and the last row. A splat with a scale that is zero,
        infinite or not a number, or with no axis, gets the box's rows, as
        its spans get the box's columns.
    """
    return _rule_rows(_row_rule(splat), splat_rows(splat))


def _rule_rows(rule: _RowRule, box: Tuple[Int, Int]) -> Tuple[Int, Int]:
    """Return the rows of a splat's disc from its quadratic; see
    `splat_disc_rows`.

    Args:
        rule: The splat's quadratic.
        box: The rows of its box, from `splat_rows`.

    Returns:
        The first and the last row.
    """
    var reach = sqrt(
        rule.a
        * Float64(SPLAT_RADIUS_SQ)
        * (1 + SPLAT_SPAN_SLACK)
        / (rule.across * rule.along * rule.norm * rule.norm)
    ) * (1 + SPLAT_ROW_SLACK)
    # Below these bounds no product of the quadratic can overflow. A
    # reach that is not finite is a splat that crosses every row.
    if not (
        rule.across < 1e30
        and rule.along < 1e30
        and rule.a > 0
        and isfinite(reach)
    ):
        return box
    # A row's center is half a row below its top.
    var center = rule.y - 0.5
    var first = max(Float64(box[0]), ceil(center - reach))
    var last = min(Float64(box[1]), floor(center + reach))
    return (Int(first), Int(last))


@fieldwise_init
struct _RowRule(ImplicitlyCopyable):
    """What `splat_row_span` needs of a splat for every row: the quadratic
    of the disc along a row, less the row's own terms."""

    var x: Float64
    """The splat's center column."""
    var y: Float64
    """Its center row."""
    var a: Float64
    """The square term's coefficient."""
    var b: Float64
    """The linear term's coefficient, a unit of row offset."""
    var c: Float64
    """The constant term's coefficient, a unit of squared row offset."""
    var across: Float64
    """The inverse squared scale across the first axis."""
    var along: Float64
    """The inverse squared scale along it."""
    var norm: Float64
    """The axis's squared length."""


def _row_rule(splat: ProjectedSplat) -> _RowRule:
    """Return the quadratic of a splat's disc along its rows.

    Args:
        splat: The splat.

    Returns:
        The coefficients; see `splat_row_span`.
    """
    var ax = Float64(splat.axis_x)
    var ay = Float64(splat.axis_y)
    var across = 1 / (Float64(splat.scale1) * Float64(splat.scale1))
    var along = 1 / (Float64(splat.scale2) * Float64(splat.scale2))
    return _RowRule(
        Float64(splat.x),
        Float64(splat.y),
        ax * ax * across + ay * ay * along,
        2 * ax * ay * (across - along),
        ay * ay * across + ax * ax * along,
        across,
        along,
        ax * ax + ay * ay,
    )


def _rule_span(
    rule: _RowRule, y: Int, left: Int, right: Int
) -> Tuple[Int, Int]:
    """Return a row's span from a splat's quadratic; see `splat_row_span`.

    Args:
        rule: The splat's quadratic.
        y: The row, down from the top.
        left: The box's first column.
        right: The box's last column.

    Returns:
        The first and the last column of the span.
    """
    var dy = rule.y - (Float64(y) + 0.5)
    var b = rule.b * dy
    var c = dy * dy * rule.c - Float64(SPLAT_RADIUS_SQ) * (1 + SPLAT_SPAN_SLACK)
    var discriminant = b * b - 4 * rule.a * c
    if not isfinite(discriminant) or not (rule.a > 0):
        return (left, right)
    if discriminant < 0:
        return (left, left - 1)
    var root = sqrt(discriminant)
    var low = (-b - root) / (2 * rule.a)
    var high = (-b + root) / (2 * rule.a)
    # A pixel's center is half a pixel right of its left edge.
    var first = Int(ceil(rule.x + low - 0.5))
    var last = Int(floor(rule.x + high - 0.5))
    return (max(first, left), min(last, right))


def splat_row_span(
    splat: ProjectedSplat, y: Int, left: Int, right: Int
) -> Tuple[Int, Int]:
    """Return the columns of one row that a splat's disc can cover.

    The disc is `u^2 + v^2 <= 4`, which along a row is a quadratic in the
    pixel center's offset from the splat's center. Its roots are found for
    a disc wider by `SPLAT_SPAN_SLACK`, in `Float64`, and the span is the
    pixels whose centers are between them. So every pixel whose center
    `splat_alpha` puts in the disc is in the span, and `splat_alpha` still
    decides each pixel: a row draws what its whole box draws, and the
    pixels it skips are the ones that would add nothing.

    Args:
        splat: The splat.
        y: The row, down from the top.
        left: The box's first column.
        right: The box's last column.

    Returns:
        The first and the last column of the span, inside `left` and
        `right`. The first is past the last for a row that the disc misses.
        A splat with a scale that is not positive and finite gets the whole
        box.
    """
    return _rule_span(_row_rule(splat), y, left, right)


def blend_splat_pixel(
    mut target: RenderTarget, slot: Int, splat: ProjectedSplat, alpha: Float32
):
    """Blend a splat's color into one pixel: source over, with straight
    alpha, as `RenderTarget.blend` mixes under the normal mode.

    Each sum of products is one fused multiply-add, which rounds once
    wherever the compiler puts it. So the fill gives a pixel the same bits
    in any band and on any count of workers. `render.blend.blend_fragment`
    leaves the compiler to fuse, so the two can differ in the last bit.

    Args:
        target: The target. Its normal attachment is left alone, and the
            pixel becomes light.
        slot: The pixel, row by row. It must be inside the target and its
            scissor: it is read and written unchecked.
        splat: The splat.
        alpha: Its opacity at the pixel, above zero.
    """
    var colors = target.colors.unsafe_ptr()
    var data = target.data.unsafe_ptr()
    var stored = colors[unsafe_offset=slot]
    # A data pixel is stored straight; see `RenderTarget.light_at`.
    var behind = stored.premultiplied() if data[unsafe_offset=slot] else stored
    data[unsafe_offset=slot] = False
    var share = min(max(alpha, 0), 1)
    var keep = 1 - share
    colors[unsafe_offset=slot] = FloatColor(
        max(Float32(0), fma(splat.r, share, behind.r * keep)),
        max(Float32(0), fma(splat.g, share, behind.g * keep)),
        max(Float32(0), fma(splat.b, share, behind.b * keep)),
        min(max(fma(behind.a, keep, share), 0), 1),
    )


def _blend_row(
    mut target: RenderTarget,
    splat: ProjectedSplat,
    y: Int,
    left: Int,
    right: Int,
) raises:
    """Blend one splat into one row of pixels, `SPLAT_LANES` opacities at
    a time.

    Args:
        target: The target.
        splat: The splat.
        y: The row.
        left: The first column.
        right: The last column.

    Raises:
        Error: Never; the columns and the row are inside the target and its
            scissor.
    """
    # The row is inside the target, so it is read and written unchecked.
    var depth = target.depth.unsafe_ptr().unsafe_offset(y * target.width)
    var first = left
    while first <= right:
        var alphas = splat_alphas(splat, first, y)
        for lane in range(
            min(SPLAT_LANES, right - first + 1)
        ):  # pragma: no branch
            var x = first + lane
            # A clear fragment blends nothing under source-over, so the
            # pixels of the box outside the disc stop here.
            var alpha = alphas[lane]
            if not alpha > 0:
                continue
            if not splat_depth_passes(
                target.depth_mode, splat.depth, depth[unsafe_offset=x]
            ):
                continue
            blend_splat_pixel(target, y * target.width + x, splat, alpha)
        first += SPLAT_LANES


def draw_gaussian_splat[
    C: Camera
](
    mut target: RenderTarget,
    scene: Scene,
    mut splat: GaussianSplat,
    camera: C,
    viewport: Optional[Rect] = None,
    workers: Int = 1,
) raises:
    """Draw a splat object into a target on the CPU: three.js's render of a
    `GaussianSplat`.

    Parameters:
        C: The camera's type.

    Args:
        target: The target, drawn into already or cleared. Its depth hides
            the splats behind it.
        scene: The scene, updated, that holds the object's node.
        splat: The splats; see `prepare_gaussian_splat`.
        camera: The camera to project through.
        viewport: The camera rectangle, or the whole target.
        workers: How many threads draw; see the module docstring.

    Raises:
        Error: Everything `prepare_gaussian_splat` raises.
    """
    var splats = prepare_gaussian_splat(
        scene,
        splat,
        camera,
        target.width,
        target.height,
        target.depth_mode,
        viewport,
        workers,
    )
    rasterize_splats(target, splats, workers)
