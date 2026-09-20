# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which pixels a point covers, in arithmetic both backends share.

`render.fillrule` is this module's opposite number for triangles and
`render.linerule` for lines, and it exists for the same reason: the CPU
pass and the GPU kernel have to agree about coverage exactly, so the rule
lives in one place and both import it. Nothing here allocates, raises,
prints or touches a framebuffer, so it compiles for a device as readily as
for the host.

## The rule

A point is a square of pixels, `size` across, centered on where the point
projects. A pixel is covered when its center lies inside that square. That
is what OpenGL's point rasterization does, and what three.js's
`gl_PointSize` means: a point is not a disc and not anti-aliased, and its
size is measured in pixels rather than in the scene.

The square is half open: a pixel center on its left or top edge is in and
one on its right or bottom edge is out, so two points a size apart share
no pixel and leave no gap. OpenGL leaves the edge to the implementation;
this one decides it, and both backends decide it the same way.

`covers` is the whole rule. The CPU walks the square's bounding box and
asks it of every pixel; the kernel asks it whether *this* pixel is inside.
The two loops are shaped differently and cannot disagree, because both get
the answer from one expression.

## The coordinate

A point has no surface, but it has a place on its own square: OpenGL's
`gl_PointCoord`, which three.js samples a `PointsMaterial` map with. `coord`
gives it, with `v` counting up from the bottom of the square as a texture
coordinate does, so the image's top row lands at the top of the point.
three.js flips `gl_PointCoord.y` the same way.

## Size with distance

three.js's `sizeAttenuation` scales a point's pixel size by `scale /
-mvPosition.z`, where `scale` is half the image height in pixels. So a
point is `size` pixels across when it is as many meters from the camera
as half the image is pixels tall; nearer it grows, and a point twice as
far away is half the size. Under a parallel projection three.js leaves
the size alone, because nothing else shrinks with distance either.
`attenuated_size` is that arithmetic.
"""

from math.vector2 import Vector2
from std.math import ceil, floor, log2


def attenuated_size(
    size: Float32,
    view_z: Float32,
    scale: Float32,
    perspective: Bool,
    render_scale: Int = 1,
) -> Float32:
    """Return how many raster pixels across a point is at one distance.

    three.js's `points_vert` under `USE_SIZEATTENUATION`: `gl_PointSize *=
    scale / -mvPosition.z` when the projection is a perspective one, and
    nothing when it is not.

    **Two kinds of pixel meet here, and the whole of the conversion is
    here.** A material's size and three.js's `scale` are *output* pixels:
    what the caller asked for and what the finished image shows. The answer
    is *raster* pixels: the grid the frame is actually drawn on, which is
    `render_scale` times finer each way when the renderer is supersampling.
    Every route in takes the same last step, so neither can be missed and
    neither can be taken twice.

    That matters most for the sizes three.js does *not* attenuate -- a
    point with `sizeAttenuation` off, and every point under a parallel
    projection, which three.js leaves alone because nothing else shrinks
    with distance either. Those used to come through untouched, so an
    eight-pixel point drawn on a doubled grid stayed eight raster pixels
    and averaged down to four: turning anti-aliasing on shrank the point
    to a quarter of its area. The attenuated size is multiplied here too,
    and the caller passes half the *output* height as `scale` rather than
    half the target's, so the two routes scale once each rather than one
    of them twice.

    Args:
        size: The material's size, in output pixels.
        view_z: The point's camera-space z, negative in front of the
            camera. A point at or behind the camera is clipped away before
            this is asked.
        scale: Half the *output* image height, in output pixels,
            three.js's `scale`.
        perspective: Whether the camera's rays converge. Under a parallel
            projection the size is not attenuated.
        render_scale: How many raster pixels stand for one output pixel.
            One, the default, is a frame drawn at its own size.

    Returns:
        The size on the raster grid, in raster pixels.
    """
    if not perspective:
        return size * Float32(render_scale)
    return size * scale / -view_z * Float32(render_scale)


def covers(center: Vector2, size: Float32, x: Int, y: Int) -> Bool:
    """Return True if the point covers the pixel at `x`, `y`.

    The whole rule: the pixel's center is inside the half-open square
    `size` across centered on `center`.

    Args:
        center: Where the point projects, in pixels.
        size: How many pixels across the point is.
        x: The pixel's column.
        y: The pixel's row.

    Returns:
        True if the pixel is covered.
    """
    var half = size / 2
    var px = Float32(x) + 0.5
    var py = Float32(y) + 0.5
    return (
        px >= center.x - half
        and px < center.x + half
        and py >= center.y - half
        and py < center.y + half
    )


def coord(center: Vector2, size: Float32, x: Int, y: Int) -> Vector2:
    """Return the texture coordinate of one pixel on the point's square.

    OpenGL's `gl_PointCoord` with its y flipped, as three.js samples it:
    zero at the left edge and one at the right, zero at the bottom edge
    and one at the top. Asked only of a pixel `covers` says is inside, so
    both come back within zero and one.

    Args:
        center: Where the point projects, in pixels.
        size: How many pixels across the point is.
        x: The pixel's column.
        y: The pixel's row.

    Returns:
        The coordinate.
    """
    var half = size / 2
    var px = Float32(x) + 0.5
    var py = Float32(y) + 0.5
    return Vector2(
        (px - (center.x - half)) / size, ((center.y + half) - py) / size
    )


def first_covered(center: Float32, size: Float32) -> Int:
    """Return a column or row at or before the first the point covers
    along one axis.

    The bound the CPU walks from. It is a bound and not the answer: it is
    rounded outward, so it can name one pixel the point does not cover,
    and `covers` is asked of every pixel between the bounds. That is what
    keeps the walk on the rule the kernel reads, whatever a rounding does
    to the bound. It is never more than one pixel early, so the walk
    visits at most two pixels per axis it need not.

    Args:
        center: The point's center along the axis, in pixels.
        size: How many pixels across the point is.

    Returns:
        The column or row.
    """
    return Int(floor(center - size / 2 - 0.5))


def last_covered(center: Float32, size: Float32) -> Int:
    """Return a column or row at or after the last the point covers along
    one axis.

    See `first_covered`. Rounded outward the same way, so it is never
    more than one pixel late.

    Args:
        center: The point's center along the axis, in pixels.
        size: How many pixels across the point is.

    Returns:
        The column or row.
    """
    return Int(ceil(center + size / 2 - 0.5))


def mip_level_of(size: Float32, width: Int, height: Int) -> Float32:
    """Return how far down the mip chain a point's map is read.

    A point's coordinate runs from zero to one across `size` pixels along
    both axes, so a pixel's footprint is one over the size in each. That
    is `render.rasterizer.mip_level` with those two footprints: the log of
    the longer image edge measured in texels per pixel. Nothing here
    depends on which pixel is asked, so it is worked out once per point
    rather than once per pixel.

    Args:
        size: How many pixels across the point is.
        width: The map's full-size width in texels.
        height: Its full-size height.

    Returns:
        The fractional level. Negative where the point is larger than the
        image, which is where the full-size image is already the right
        answer, and zero for a size of nothing.
    """
    var longest = Float32(width)
    if Float32(height) > longest:
        longest = Float32(height)
    if size <= 0 or longest <= 0:
        return 0
    return log2(longest / size)
