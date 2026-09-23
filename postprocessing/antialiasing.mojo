# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Anti-aliasing after the render: three.js's `FXAAShader`, its three SMAA
shaders, and the jitter its `SSAARenderPass` and `TAARenderPass` draw with.

**FXAA** looks at each pixel's luminance beside its eight neighbors. Where
the contrast is high enough it finds the edge through the pixel, walks
along it to both ends, and moves the pixel's texture read across the edge
by how far the pixel sits from the nearer end. That is three.js's shader
line for line: its thresholds, its six steps along the edge and its guess
of eight past the last.

**SMAA** runs in three stages, as three.js's `SMAAPass` does. The first
marks the edges between pixels whose colors differ by a tenth, kept only
where the step is at least half the largest step around. The second walks
each edge to its ends, reads the edges that cross it there, and turns the
pattern and the two distances into how much each pixel on either side
takes from the other. The third blends each pixel with the neighbor that
weighs most.

The second stage is where this port differs, and on purpose. A shader
cannot loop cheaply over pixels, so SMAA walks two pixels at a time with a
bilinear read and decodes what it read through a 66 by 33 search texture;
and it reads the area from a 160 by 560 texture that a script fills in
advance. Both textures stand for arithmetic, and this does the arithmetic:
it walks one pixel at a time, stopping where SMAA stops, and computes the
area with the formula SMAA's `AreaTex.py` fills the texture with. See
`docs/wiki/Post-processing.md` for what that changes.

**The jitter** moves a camera's view by a fraction of a pixel, as three.js's
`setViewOffset` moves it. `JitteredCamera` wraps any camera to do it, and
`jitter_offsets` returns the sample patterns both passes draw with.
"""

from cameras.camera import Camera
from core.layers import Layers
from core.scene import Scene
from math.matrix4 import Matrix4, translation
from math.projection import viewport
from math.smoothstep import smoothstep
from math.vector2 import Vector2
from postprocessing.sampling import LightView, u_of, v_of
from render.framebuffer import FloatColor
from render.target import RenderTarget
from std.math import isfinite, sqrt

# --- FXAA -------------------------------------------------------------------

# `FXAAShader`'s `_ContrastThreshold`: a pixel whose neighborhood spans
# less luminance than this is left alone.
comptime FXAA_CONTRAST_THRESHOLD = Float32(0.0312)
# Its `_RelativeThreshold`: or less than this share of the brightest.
comptime FXAA_RELATIVE_THRESHOLD = Float32(0.063)
# Its `_SubpixelBlending`.
comptime FXAA_SUBPIXEL_BLENDING = Float32(1.0)
# Its `EDGE_STEPS`, in pixels, and how many there are.
comptime FXAA_EDGE_STEPS = SIMD[DType.float32, 8](
    1.0, 1.5, 2.0, 2.0, 2.0, 4.0, 0.0, 0.0
)
comptime FXAA_EDGE_STEP_COUNT = 6
# Its `EDGE_GUESS`: how far past the last step an unended edge is taken to
# reach.
comptime FXAA_EDGE_GUESS = Float32(8.0)


def fxaa_luminance(color: FloatColor) -> Float32:
    """Return the luminance FXAA reads: `FXAAShader`'s weights of 0.3,
    0.59 and 0.11, which are not rec. 709's.

    Args:
        color: The texel, as stored.

    Returns:
        The weighted sum of red, green and blue.
    """
    return color.r * 0.3 + color.g * 0.59 + color.b * 0.11


def _luma(source: LightView, u: Float32, v: Float32) -> Float32:
    """Return `SampleLuminance`: the luminance of a bilinear read."""
    return fxaa_luminance(source.sample(u, v))


def fxaa_pixel(source: LightView, u: Float32, v: Float32) -> FloatColor:
    """Return `FXAAShader`'s `ApplyFXAA` at one texture coordinate.

    Args:
        source: The frame before the pass.
        u: Across, at the pixel's center.
        v: Up, at the pixel's center.

    Returns:
        The smoothed light.
    """
    var du = 1 / Float32(source.width)
    var dv = 1 / Float32(source.height)
    # `SampleLuminanceNeighborhood`. North is up, where `v` grows.
    var m = _luma(source, u, v)
    var n = _luma(source, u, v + dv)
    var e = _luma(source, u + du, v)
    var s = _luma(source, u, v - dv)
    var w = _luma(source, u - du, v)
    var ne = _luma(source, u + du, v + dv)
    var nw = _luma(source, u - du, v + dv)
    var se = _luma(source, u + du, v - dv)
    var sw = _luma(source, u - du, v - dv)
    var highest = max(max(max(max(n, e), s), w), m)
    var lowest = min(min(min(min(n, e), s), w), m)
    var contrast = highest - lowest
    # `ShouldSkipPixel`.
    if contrast < max(
        FXAA_CONTRAST_THRESHOLD, FXAA_RELATIVE_THRESHOLD * highest
    ):
        return source.sample(u, v)
    # `DeterminePixelBlendFactor`.
    var f = 2 * (n + e + s + w) + ne + nw + se + sw
    f *= 1.0 / 12.0
    f = abs(f - m)
    f = min(max(f / contrast, 0), 1)
    var blend = smoothstep(0, 1, f)
    var pixel_blend = blend * blend * FXAA_SUBPIXEL_BLENDING
    # `DetermineEdge`.
    var horizontal = (
        abs(n + s - 2 * m) * 2 + abs(ne + se - 2 * e) + abs(nw + sw - 2 * w)
    )
    var vertical = (
        abs(e + w - 2 * m) * 2 + abs(ne + nw - 2 * n) + abs(se + sw - 2 * s)
    )
    var is_horizontal = horizontal >= vertical
    var p_luminance = n if is_horizontal else e
    var n_luminance = s if is_horizontal else w
    var p_gradient = abs(p_luminance - m)
    var n_gradient = abs(n_luminance - m)
    var pixel_step = dv if is_horizontal else du
    var opposite = p_luminance
    var gradient = p_gradient
    if p_gradient < n_gradient:
        pixel_step = -pixel_step
        opposite = n_luminance
        gradient = n_gradient
    # `DetermineEdgeBlendFactor`: from the middle of the edge, walk each
    # way along it until the luminance leaves the edge's.
    var edge_u = u
    var edge_v = v
    var step_u = Float32(0)
    var step_v = Float32(0)
    if is_horizontal:
        edge_v += pixel_step * 0.5
        step_u = du
    else:
        edge_u += pixel_step * 0.5
        step_v = dv
    var edge_luminance = (m + opposite) * 0.5
    var gradient_threshold = gradient * 0.25
    var pu = edge_u + step_u * FXAA_EDGE_STEPS[0]
    var pv = edge_v + step_v * FXAA_EDGE_STEPS[0]
    var p_delta = _luma(source, pu, pv) - edge_luminance
    var p_at_end = abs(p_delta) >= gradient_threshold
    var index = 1
    while index < FXAA_EDGE_STEP_COUNT and not p_at_end:
        pu += step_u * FXAA_EDGE_STEPS[index]
        pv += step_v * FXAA_EDGE_STEPS[index]
        p_delta = _luma(source, pu, pv) - edge_luminance
        p_at_end = abs(p_delta) >= gradient_threshold
        index += 1
    if not p_at_end:
        pu += step_u * FXAA_EDGE_GUESS
        pv += step_v * FXAA_EDGE_GUESS
    var nu = edge_u - step_u * FXAA_EDGE_STEPS[0]
    var nv = edge_v - step_v * FXAA_EDGE_STEPS[0]
    var n_delta = _luma(source, nu, nv) - edge_luminance
    var n_at_end = abs(n_delta) >= gradient_threshold
    index = 1
    while index < FXAA_EDGE_STEP_COUNT and not n_at_end:
        nu -= step_u * FXAA_EDGE_STEPS[index]
        nv -= step_v * FXAA_EDGE_STEPS[index]
        n_delta = _luma(source, nu, nv) - edge_luminance
        n_at_end = abs(n_delta) >= gradient_threshold
        index += 1
    if not n_at_end:
        nu -= step_u * FXAA_EDGE_GUESS
        nv -= step_v * FXAA_EDGE_GUESS
    var p_distance = (pu - u) if is_horizontal else (pv - v)
    var n_distance = (u - nu) if is_horizontal else (v - nv)
    var shortest = p_distance
    var delta_sign = p_delta >= 0
    if p_distance > n_distance:
        shortest = n_distance
        delta_sign = n_delta >= 0
    var edge_blend = Float32(0)
    if delta_sign != (m - edge_luminance >= 0):
        edge_blend = 0.5 - shortest / (p_distance + n_distance)
    # `ApplyFXAA`: move the read across the edge by the larger blend.
    var final_blend = max(pixel_blend, edge_blend)
    if is_horizontal:
        return source.sample(u, v + pixel_step * final_blend)
    return source.sample(u + pixel_step * final_blend, v)


def fxaa_light(mut frame: RenderTarget):
    """Smooth the frame's jagged edges by their luminance: three.js's
    `FXAAShader`, as its `FXAAPass` runs it.

    Every pixel reads the frame as it was before the pass. The texel is
    read as stored, premultiplied, which is what a shader's texture read
    of a composer's target sees.

    Args:
        frame: The frame, changed in place.
    """
    var width = frame.width
    var height = frame.height
    var source = frame.colors.copy()
    var light = LightView(source, width, height)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            frame.colors[y * width + x] = fxaa_pixel(
                light, u_of(x, width), v_of(y, height)
            )
            x += 1
        y += 1
    # The view does not keep the copy alive; this does.
    _ = source^


# --- SMAA -------------------------------------------------------------------

# `SMAAEdgesShader`'s `SMAA_THRESHOLD`: the least step in any channel that
# is an edge.
comptime SMAA_THRESHOLD = Float32(0.1)
# `SMAAWeightsShader`'s `SMAA_MAX_SEARCH_STEPS`. Each step reads two pixels.
comptime SMAA_MAX_SEARCH_STEPS = 8
# How far the walk along an edge reaches. The left walk's first read holds
# the pixel itself, so it reaches one pixel less than the right.
comptime SMAA_MAX_DISTANCE_LEFT = 2 * SMAA_MAX_SEARCH_STEPS - 1
comptime SMAA_MAX_DISTANCE_RIGHT = 2 * SMAA_MAX_SEARCH_STEPS
# `AreaTex.py`'s `SMOOTH_MAX_DISTANCE`: a U-shaped pattern shorter than this
# is rounded toward the square root of its area.
comptime SMAA_SMOOTH_MAX_DISTANCE = Float32(32)


def _clamped(x: Int, y: Int, width: Int, height: Int) -> Int:
    """Return the index of a pixel, held inside the frame as a clamped
    texture read holds it."""
    var cx = min(max(x, 0), width - 1)
    var cy = min(max(y, 0), height - 1)
    return cy * width + cx


struct EdgeMap(Movable):
    """Which pixels differ from the pixel to their left and from the pixel
    above: the red and green of SMAA's edges texture.
    """

    var width: Int
    var height: Int
    # One per pixel: an edge between it and the pixel to its left.
    var left: List[Bool]
    # One per pixel: an edge between it and the pixel above it.
    var top: List[Bool]

    def __init__(out self, width: Int, height: Int):
        """Start a map of the given size with no edges.

        Args:
            width: The frame's width in pixels.
            height: The frame's height in pixels.
        """
        self.width = width
        self.height = height
        self.left = List[Bool](length=width * height, fill=False)
        self.top = List[Bool](length=width * height, fill=False)

    def left_at(self, x: Int, y: Int) -> Bool:
        """Return whether a pixel has an edge on its left.

        Args:
            x: The column; outside the map reads the nearest column.
            y: The row; outside the map reads the nearest row.

        Returns:
            True if the pixel differs from the one to its left.
        """
        return self.left[_clamped(x, y, self.width, self.height)]

    def top_at(self, x: Int, y: Int) -> Bool:
        """Return whether a pixel has an edge above it.

        Args:
            x: The column; outside the map reads the nearest column.
            y: The row; outside the map reads the nearest row.

        Returns:
            True if the pixel differs from the one above it.
        """
        return self.top[_clamped(x, y, self.width, self.height)]

    def transposed(self) -> EdgeMap:
        """Return the map mirrored across its diagonal, so a column of left
        edges becomes a row of top edges.

        SMAA treats a vertical edge exactly as a horizontal one turned on
        its side. Walking the transposed map's rows is walking this map's
        columns.

        Returns:
            The map, `height` wide and `width` high.
        """
        var turned = EdgeMap(self.height, self.width)
        for y in range(self.height):  # pragma: no branch
            for x in range(self.width):  # pragma: no branch
                var slot = x * self.height + y
                turned.left[slot] = self.top[y * self.width + x]
                turned.top[slot] = self.left[y * self.width + x]
        return turned^


def _color_step(a: FloatColor, b: FloatColor) -> Float32:
    """Return the largest step between two colors in any of red, green or
    blue: `SMAAColorEdgeDetectionPS`'s `max(max(t.r, t.g), t.b)`."""
    return max(max(abs(a.r - b.r), abs(a.g - b.g)), abs(a.b - b.b))


def smaa_edges(colors: List[FloatColor], width: Int, height: Int) -> EdgeMap:
    """Return where the frame has edges: three.js's `SMAAEdgesShader`, its
    color edge detection.

    A pixel has an edge on its left, or above, where the step to that
    neighbor is at least `SMAA_THRESHOLD` in some channel and at least half
    the largest step to its four neighbors and to the pixels two to the
    left and two above. A read past the frame reads the edge pixel.

    Args:
        colors: The frame's pixels, as stored.
        width: The frame's width in pixels.
        height: The frame's height in pixels.

    Returns:
        The edges.
    """
    var edges = EdgeMap(width, height)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var here = colors[_clamped(x, y, width, height)]
            var to_left = _color_step(
                here, colors[_clamped(x - 1, y, width, height)]
            )
            var to_top = _color_step(
                here, colors[_clamped(x, y - 1, width, height)]
            )
            var left = to_left >= SMAA_THRESHOLD
            var top = to_top >= SMAA_THRESHOLD
            # The shader discards a pixel with neither, leaving no edge.
            if left or top:
                var largest = max(
                    max(to_left, to_top),
                    max(
                        _color_step(
                            here, colors[_clamped(x + 1, y, width, height)]
                        ),
                        _color_step(
                            here, colors[_clamped(x, y + 1, width, height)]
                        ),
                    ),
                )
                largest = max(
                    largest,
                    max(
                        _color_step(
                            here, colors[_clamped(x - 2, y, width, height)]
                        ),
                        _color_step(
                            here, colors[_clamped(x, y - 2, width, height)]
                        ),
                    ),
                )
                edges.left[y * width + x] = left and to_left >= 0.5 * largest
                edges.top[y * width + x] = top and to_top >= 0.5 * largest
            x += 1
        y += 1
    return edges^


def _area(
    p1x: Float32, p1y: Float32, p2x: Float32, p2y: Float32, x: Float32
) -> SIMD[DType.float32, 2]:
    """Return `AreaTex.py`'s `area`: how much of the pixel from `x` to
    `x + 1` lies between the edge, at height zero, and the line from `p1`
    to `p2`. The first entry is the area below the edge and the second
    the area above."""
    var dx = p2x - p1x
    var dy = p2y - p1y
    var x1 = x
    var x2 = x + 1
    var y1 = p1y + dy * (x1 - p1x) / dx
    var y2 = p1y + dy * (x2 - p1x) / dx
    var inside = (x1 >= p1x and x1 < p2x) or (x2 > p1x and x2 <= p2x)
    if not inside:
        return SIMD[DType.float32, 2](0, 0)
    var trapezoid = (y1 >= 0) == (y2 >= 0) or abs(y1) < 1e-4 or abs(y2) < 1e-4
    if trapezoid:
        var a = (y1 + y2) / 2
        if a < 0:
            return SIMD[DType.float32, 2](abs(a), 0)
        return SIMD[DType.float32, 2](0, abs(a))
    # The line crosses the edge inside the pixel: two triangles.
    var cross = -p1y * dx / dy + p1x
    var a1 = y1 * (cross - x1) / 2 if cross > p1x else Float32(0)
    var a2 = y2 * (x2 - cross) / 2 if cross < p2x else Float32(0)
    var a = a1 if abs(a1) > abs(a2) else -a2
    if a < 0:
        return SIMD[DType.float32, 2](abs(a1), abs(a2))
    return SIMD[DType.float32, 2](abs(a2), abs(a1))


def _smooth(
    d: Float32, a1: SIMD[DType.float32, 2], a2: SIMD[DType.float32, 2]
) -> SIMD[DType.float32, 2]:
    """Return `AreaTex.py`'s `smootharea`, summed: a short U pattern's two
    areas moved toward the square root of twice each, halved."""
    var p = min(d / SMAA_SMOOTH_MAX_DISTANCE, 1)
    var b1 = sqrt(a1 * 2) * 0.5
    var b2 = sqrt(a2 * 2) * 0.5
    return (b1 + (a1 - b1) * p) + (b2 + (a2 - b2) * p)


def smaa_area(
    left_below: Bool,
    left_above: Bool,
    right_below: Bool,
    right_above: Bool,
    left: Int,
    right: Int,
) -> SIMD[DType.float32, 2]:
    """Return how much the pixels on either side of an edge take from each
    other: `AreaTex.py`'s `areaortho` with no subpixel offset, the numbers
    SMAA 1x reads from its area texture.

    The edge runs `left` pixels to the left of this pixel and `right` to
    the right. At each end an edge can cross it below, above, both or
    neither; the sixteen patterns are revectorized into a line as SMAA
    revectorizes them, and the area between that line and the edge, over
    this pixel, is the answer.

    Args:
        left_below: Whether an edge crosses at the left end, below.
        left_above: Whether an edge crosses at the left end, above.
        right_below: Whether an edge crosses at the right end, below.
        right_above: Whether an edge crosses at the right end, above.
        left: How many pixels the edge runs to the left of this one.
        right: How many pixels it runs to the right.

    Returns:
        What the pixel below the edge takes from the one above, then what
        the pixel above takes from the one below.
    """
    var d = Float32(left + right + 1)
    var x = Float32(left)
    var half = d / 2
    # `o1` and `o2`: half a pixel above the edge and half a pixel below.
    comptime ABOVE = Float32(0.5)
    comptime BELOW = Float32(-0.5)
    var pattern = (
        Int(left_below)
        + 2 * Int(right_below)
        + 4 * Int(left_above)
        + 8 * Int(right_above)
    )
    if pattern == 1:
        if left <= right:
            return _area(0, BELOW, half, 0, x)
    elif pattern == 2:
        if left >= right:
            return _area(half, 0, d, BELOW, x)
    elif pattern == 3:
        return _smooth(
            d, _area(0, BELOW, half, 0, x), _area(half, 0, d, BELOW, x)
        )
    elif pattern == 4:
        if left <= right:
            return _area(0, ABOVE, half, 0, x)
    elif pattern == 6 or pattern == 7 or pattern == 14:
        return _area(0, ABOVE, d, BELOW, x)
    elif pattern == 8:
        if left >= right:
            return _area(half, 0, d, ABOVE, x)
    elif pattern == 9 or pattern == 11 or pattern == 13:
        return _area(0, BELOW, d, ABOVE, x)
    elif pattern == 12:
        return _smooth(
            d, _area(0, ABOVE, half, 0, x), _area(half, 0, d, ABOVE, x)
        )
    # Patterns 0, 5, 10 and 15 are a straight edge or a cross, and are
    # not filtered; an L whose corner is the far end is left to the pixel
    # nearer it.
    return SIMD[DType.float32, 2](0, 0)


def _row_weights(edges: EdgeMap) -> List[SIMD[DType.float32, 2]]:
    """Return, for every pixel with an edge above it, what it takes from
    the pixel above and what that pixel takes from it:
    `SMAABlendingWeightCalculationPS`'s edge at north."""
    var width = edges.width
    var weights = List[SIMD[DType.float32, 2]](
        length=width * edges.height, fill=SIMD[DType.float32, 2](0, 0)
    )
    var y = 0
    while y < edges.height:
        var x = 0
        while x < width:
            if edges.top_at(x, y):
                # Walk left while no edge crosses and the edge goes on.
                var left = 0
                var end = x
                while (
                    left < SMAA_MAX_DISTANCE_LEFT
                    and not edges.left_at(end, y)
                    and not edges.left_at(end, y - 1)
                    and edges.top_at(end - 1, y)
                ):
                    end -= 1
                    left += 1
                var left_below = edges.left_at(end, y)
                var left_above = edges.left_at(end, y - 1)
                var right = 0
                end = x
                while (
                    right < SMAA_MAX_DISTANCE_RIGHT
                    and not edges.left_at(end + 1, y)
                    and not edges.left_at(end + 1, y - 1)
                    and edges.top_at(end + 1, y)
                ):
                    end += 1
                    right += 1
                weights[y * width + x] = smaa_area(
                    left_below,
                    left_above,
                    edges.left_at(end + 1, y),
                    edges.left_at(end + 1, y - 1),
                    left,
                    right,
                )
            x += 1
        y += 1
    return weights^


struct BlendWeights(Movable):
    """What each pixel takes from its neighbors: SMAA's blend texture.

    `r` and `g` belong to the edge above the pixel, `b` and `a` to the edge
    on its left, as SMAA packs them.
    """

    var width: Int
    var height: Int
    # Per pixel: red, what it takes from above; green, what the pixel above
    # takes from it; blue, what it takes from the left; alpha, what the
    # pixel to the left takes from it.
    var rgba: List[SIMD[DType.float32, 4]]

    def __init__(out self, width: Int, height: Int):
        """Start a set of weights of the given size, all zero.

        Args:
            width: The frame's width in pixels.
            height: The frame's height in pixels.
        """
        self.width = width
        self.height = height
        self.rgba = List[SIMD[DType.float32, 4]](
            length=width * height, fill=SIMD[DType.float32, 4](0)
        )

    def at(self, x: Int, y: Int) -> SIMD[DType.float32, 4]:
        """Return a pixel's weights, the read held inside the frame.

        Args:
            x: The column; outside reads the nearest column.
            y: The row; outside reads the nearest row.

        Returns:
            The red, green, blue and alpha of SMAA's blend texture.
        """
        return self.rgba[_clamped(x, y, self.width, self.height)]


def smaa_weights(edges: EdgeMap) -> BlendWeights:
    """Return how much each pixel blends across each edge: three.js's
    `SMAAWeightsShader`, walking one pixel at a time and computing the
    area rather than reading it.

    Args:
        edges: What `smaa_edges` found.

    Returns:
        The weights.
    """
    var width = edges.width
    var height = edges.height
    var rows = _row_weights(edges)
    var columns = _row_weights(edges.transposed())
    var weights = BlendWeights(width, height)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var row = rows[y * width + x]
            var column = columns[x * height + y]
            weights.rgba[y * width + x] = SIMD[DType.float32, 4](
                row[0], row[1], column[0], column[1]
            )
    return weights^


def _gamma(value: Float32) -> Float32:
    """Return a channel raised to 2.2, as SMAA's blend decodes it; below
    zero reads as zero, where GLSL's `pow` has no answer."""
    return max(value, 0) ** 2.2


def _degamma(value: Float32) -> Float32:
    """Return a channel raised to one over 2.2, as SMAA's blend encodes it."""
    return value ** (1 / 2.2)


def smaa_blend(
    colors: List[FloatColor], width: Int, height: Int, weights: BlendWeights
) -> List[FloatColor]:
    """Return every pixel blended with the neighbor it takes most from:
    three.js's `SMAABlendShader`.

    A pixel reads its own red and blue, the green of the pixel below and
    the alpha of the pixel to its right. With all four near zero it is
    kept. Otherwise it is mixed toward the neighbor of the largest weight,
    by that weight, with red, green and blue raised to 2.2 first and
    lowered back after, as three.js's WebGL port does.

    Args:
        colors: The frame's pixels, as stored.
        width: The frame's width in pixels.
        height: The frame's height in pixels.
        weights: What `smaa_weights` found.

    Returns:
        The blended pixels.
    """
    var out = colors.copy()
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var own = weights.at(x, y)
            var from_top = own[0]
            var from_left = own[2]
            var from_bottom = weights.at(x, y + 1)[1]
            var from_right = weights.at(x + 1, y)[3]
            if from_top + from_bottom + from_left + from_right >= 1e-5:
                # Right against left and up against down, the larger of
                # each; then the larger of the two.
                var across = (
                    from_right if from_right > from_left else -from_left
                )
                var up = -from_bottom if from_bottom > from_top else from_top
                var ox = 0
                var oy = 0
                var amount = abs(up)
                if abs(across) > abs(up):
                    ox = 1 if across > 0 else -1
                    amount = abs(across)
                else:
                    # Up in `v` is up the frame, one row less.
                    oy = -1 if up > 0 else (1 if up < 0 else 0)
                var here = colors[y * width + x]
                var there = colors[_clamped(x + ox, y + oy, width, height)]
                out[y * width + x] = FloatColor(
                    _degamma(
                        _gamma(here.r)
                        + (_gamma(there.r) - _gamma(here.r)) * amount
                    ),
                    _degamma(
                        _gamma(here.g)
                        + (_gamma(there.g) - _gamma(here.g)) * amount
                    ),
                    _degamma(
                        _gamma(here.b)
                        + (_gamma(there.b) - _gamma(here.b)) * amount
                    ),
                    here.a + (there.a - here.a) * amount,
                )
            x += 1
        y += 1
    return out^


def smaa_light(mut frame: RenderTarget):
    """Smooth the frame's jagged edges by their shape: three.js's
    `SMAAPass`, its edges, weights and blend in turn.

    Args:
        frame: The frame, changed in place.
    """
    var edges = smaa_edges(frame.colors, frame.width, frame.height)
    var weights = smaa_weights(edges)
    frame.colors = smaa_blend(frame.colors, frame.width, frame.height, weights)


# --- the jitter -------------------------------------------------------------

# The highest sample level; level `n` has two to the `n` samples.
comptime JITTER_LEVELS = 6
# `SSAARenderPass`'s `_JitterVectors`, every level in order, each pair an
# x and a y in sixteenths of a pixel: one sample, then 2, 4, 8, 16 and 32.
comptime _JITTER = SIMD[DType.int8, 128](
    # 1
    0,
    0,
    # 2
    4,
    4,
    -4,
    -4,
    # 4
    -2,
    -6,
    6,
    -2,
    -6,
    2,
    2,
    6,
    # 8
    1,
    -3,
    -1,
    3,
    5,
    1,
    -3,
    -5,
    -5,
    5,
    -7,
    -1,
    3,
    7,
    7,
    -7,
    # 16
    1,
    1,
    -1,
    -3,
    -3,
    2,
    4,
    -1,
    -5,
    -2,
    2,
    5,
    5,
    3,
    3,
    -5,
    -2,
    6,
    0,
    -7,
    -4,
    -6,
    -6,
    4,
    -8,
    0,
    7,
    -4,
    6,
    7,
    -7,
    -8,
    # 32
    -4,
    -7,
    -7,
    -5,
    -3,
    -5,
    -5,
    -4,
    -1,
    -4,
    -2,
    -2,
    -6,
    -1,
    -4,
    0,
    -7,
    1,
    -1,
    2,
    -6,
    3,
    -3,
    3,
    -7,
    6,
    -3,
    6,
    -5,
    7,
    -1,
    7,
    5,
    -7,
    1,
    -6,
    6,
    -5,
    4,
    -4,
    2,
    -3,
    7,
    -2,
    1,
    -1,
    4,
    -1,
    2,
    1,
    6,
    2,
    0,
    4,
    4,
    4,
    2,
    5,
    7,
    5,
    5,
    6,
    3,
    7,
    # Padding to a power of two.
    0,
    0,
)


def jitter_offsets(level: Int) raises -> List[Vector2]:
    """Return the sample offsets of a level: three.js's `_JitterVectors`,
    in pixels.

    Args:
        level: Zero through five, for 1, 2, 4, 8, 16 or 32 samples.

    Returns:
        Each sample's offset across and down, in pixels, from minus a half
        up to a half.

    Raises:
        Error: If the level is outside zero through five.
    """
    if level < 0 or level >= JITTER_LEVELS:
        raise Error("A sample level runs from zero to five")
    var count = 1 << level
    var first = count - 1
    var offsets = List[Vector2](capacity=count)
    for index in range(count):  # pragma: no branch
        var at = 2 * (first + index)
        offsets.append(
            Vector2(
                Float32(_JITTER[at]) * 0.0625, Float32(_JITTER[at + 1]) * 0.0625
            )
        )
    return offsets^


struct JitteredCamera(Camera, ImplicitlyCopyable):
    """A camera whose view is moved by a fraction of a pixel: what three.js's
    `setViewOffset` does when `SSAARenderPass` and `TAARenderPass` call it
    with a jitter.

    A view offset of `x` pixels across and `y` down moves the window the
    camera sees by that much, so the picture moves the other way. That is
    a move of normalized device space after the projection, so any camera
    can be jittered and nothing but its projection changes.

    The wrapped camera's answers are taken once, in the scene it draws, so
    a camera that rides a node is jittered from where the node is.
    """

    # The wrapped camera's view matrix in the scene.
    var view: Matrix4
    # Its projection, followed by the move.
    var projection: Matrix4
    # Its near and far clipping distances, in meters.
    var near: Float32
    var far: Float32
    # The layers it draws.
    var layers: Layers

    def __init__[
        C: Camera
    ](
        out self,
        camera: C,
        scene: Scene,
        offset_x: Float32,
        offset_y: Float32,
        width: Int,
        height: Int,
    ) raises:
        """Take a camera's view in a scene and move it.

        Args:
            camera: The camera to move.
            scene: The scene the camera draws, and may ride a node of.
            offset_x: How far the view moves across, in pixels; the picture
                moves left.
            offset_y: How far the view moves down, in pixels; the picture
                moves up.
            width: The image's width in pixels: three.js's `fullWidth`.
            height: The image's height in pixels: three.js's `fullHeight`.

        Raises:
            Error: If an offset is not finite, a size is not positive, or
                the camera's `view_matrix_in` or `projection_matrix` raises.
        """
        if not (isfinite(offset_x) and isfinite(offset_y)):
            raise Error("A view offset must be finite")
        if width <= 0 or height <= 0:
            raise Error("A view offset's image must have a positive size")
        self.view = camera.view_matrix_in(scene)
        self.projection = translation(
            -2 * offset_x / Float32(width), 2 * offset_y / Float32(height), 0
        )
        self.projection.multiply(camera.projection_matrix())
        self.near = camera.near_distance()
        self.far = camera.far_distance()
        self.layers = camera.visible_layers()

    def view_matrix(self) raises -> Matrix4:
        """Return the wrapped camera's view matrix, unmoved.

        Returns:
            The view matrix.
        """
        return self.view

    def view_matrix_in(self, scene: Scene) raises -> Matrix4:
        """Return the wrapped camera's view matrix, unmoved.

        Args:
            scene: The scene, which the view was taken in already.

        Returns:
            The view matrix.
        """
        return self.view

    def projection_matrix(self) raises -> Matrix4:
        """Return the wrapped camera's projection followed by the move.

        Returns:
            The projection, its picture moved by the offset.
        """
        return self.projection

    def view_to_screen_matrix(self, width: Int, height: Int) raises -> Matrix4:
        """Return the transform from camera space to pixels, moved.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.

        Returns:
            The product viewport * moved projection.

        Raises:
            Error: If either dimension is not positive.
        """
        var combined = viewport(width, height)
        combined.multiply(self.projection)
        return combined^

    def near_distance(self) -> Float32:
        """Return the wrapped camera's near clipping distance, in meters."""
        return self.near

    def far_distance(self) -> Float32:
        """Return the wrapped camera's far clipping distance, in meters."""
        return self.far

    def visible_layers(self) -> Layers:
        """Return which layers the wrapped camera draws."""
        return self.layers
