# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fills and strokes of SVG outlines, from three.js's
`SVGLoader.createShapes`, `getStrokeStyle` and `pointsToStroke`.

**Fills.** `create_shapes` sorts the outlines of an `SvgShapePath` into
shapes with holes, by the path's `fill-rule`. It runs a horizontal line
through the middle of each outline's bounding box, and counts the other
outlines that the line crosses before it reaches the outline. With
`evenodd`, an outline inside an odd number of others is a hole. With
`nonzero`, the default, an outline is a hole when the outlines around it
change direction, as three.js counts them.

**Strokes.** `points_to_stroke` turns a list of points into triangles
around them, as wide as the style's `stroke-width`: straight segments,
joins where the points turn (`miter`, `miter-clip`, `round` or
`bevel`), and caps at the ends of an open line (`butt`, `round` or
`square`). A closed list, with its last point equal to its first, has no
caps. `u` runs along the line and `v` across it, as in three.js.

**Where this port differs.** three.js throws a `TypeError` when the line
through an outline does not cross it, and when the fill rule is not
known. This refuses both. three.js returns `null` for a stroke with no
triangles. Here the stroke has a `count` of zero, and
`SvgStroke.to_geometry` refuses it.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, BufferGeometry
from loaders.svg_path import (
    JS_EPSILON,
    SvgShapePath,
    SvgStyle,
    SvgSubPath,
    SvgVector,
    same_point,
)
from math.path import Shape
from std.math import acos, cos, floor, isfinite, log10, pi, sin, sqrt


# three.js's `BIGNUMBER`.
comptime BIG_NUMBER = Float64(999999999)


@fieldwise_init
struct SvgFillRule(Equatable, ImplicitlyCopyable, Writable):
    """An SVG `fill-rule`, as a type rather than a bare int.

    `create_shapes_with_rule` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `nonzero` or `evenodd`."""
        return (
            self.value >= SVG_NONZERO.value and self.value <= SVG_EVENODD.value
        )


comptime SVG_NONZERO = SvgFillRule(0)
comptime SVG_EVENODD = SvgFillRule(1)


def svg_fill_rule(name: String) raises -> SvgFillRule:
    """Return the fill rule a style names.

    Args:
        name: `nonzero`, `evenodd`, or empty for `nonzero`.

    Returns:
        The rule.

    Raises:
        Error: If the name is another word, which three.js does not
            implement.
    """
    var nonzero = name == "" or name == "nonzero"
    if nonzero:
        return SVG_NONZERO
    if name == "evenodd":
        return SVG_EVENODD
    raise Error('SVG: fill-rule "' + name + '" is not implemented')


@fieldwise_init
struct SvgLineJoin(Equatable, ImplicitlyCopyable, Writable):
    """An SVG `stroke-linejoin`, as a type rather than a bare int.

    `points_to_stroke` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four joins."""
        return self.value >= SVG_JOIN_MITER.value and (
            self.value <= SVG_JOIN_BEVEL.value
        )


comptime SVG_JOIN_MITER = SvgLineJoin(0)
comptime SVG_JOIN_MITER_CLIP = SvgLineJoin(1)
comptime SVG_JOIN_ROUND = SvgLineJoin(2)
comptime SVG_JOIN_BEVEL = SvgLineJoin(3)


@fieldwise_init
struct SvgLineCap(Equatable, ImplicitlyCopyable, Writable):
    """An SVG `stroke-linecap`, as a type rather than a bare int.

    `points_to_stroke` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three caps."""
        return self.value >= SVG_CAP_BUTT.value and (
            self.value <= SVG_CAP_SQUARE.value
        )


comptime SVG_CAP_BUTT = SvgLineCap(0)
comptime SVG_CAP_ROUND = SvgLineCap(1)
comptime SVG_CAP_SQUARE = SvgLineCap(2)


def svg_line_join(name: String) -> SvgLineJoin:
    """Return the join a style names, as three.js's `switch` reads it.

    Args:
        name: `bevel`, `round`, `miter-clip`, or anything else for a
            miter.

    Returns:
        The join.
    """
    if name == "bevel":
        return SVG_JOIN_BEVEL
    if name == "round":
        return SVG_JOIN_ROUND
    if name == "miter-clip":
        return SVG_JOIN_MITER_CLIP
    return SVG_JOIN_MITER


def svg_line_cap(name: String) -> SvgLineCap:
    """Return the cap a style names, as three.js's `switch` reads it.

    Args:
        name: `round`, `square`, or anything else for a butt.

    Returns:
        The cap.
    """
    if name == "round":
        return SVG_CAP_ROUND
    if name == "square":
        return SVG_CAP_SQUARE
    return SVG_CAP_BUTT


struct SvgStrokeStyle(Copyable, Movable):
    """What `points_to_stroke` reads of a style, three.js's
    `getStrokeStyle` result."""

    # In user units.
    var width: Float64
    var join: SvgLineJoin
    var cap: SvgLineCap
    # In multiples of the width.
    var miter_limit: Float64

    def __init__(
        out self,
        width: Float64 = 1,
        join: SvgLineJoin = SVG_JOIN_MITER,
        cap: SvgLineCap = SVG_CAP_BUTT,
        miter_limit: Float64 = 4,
    ):
        """Make a stroke style, three.js's `getStrokeStyle` and its
        defaults.

        Args:
            width: The stroke's width.
            join: How corners are drawn.
            cap: How open ends are drawn.
            miter_limit: The longest miter, in widths.
        """
        self.width = width
        self.join = join
        self.cap = cap
        self.miter_limit = miter_limit

    def __init__(out self, style: SvgStyle):
        """Take the stroke of a parsed style.

        Args:
            style: The style.
        """
        self.width = style.stroke_width
        self.join = svg_line_join(style.stroke_line_join)
        self.cap = svg_line_cap(style.stroke_line_cap)
        self.miter_limit = style.stroke_miter_limit


struct SvgShape(Copyable, Movable):
    """A filled outline with holes, three.js's `Shape` as `createShapes`
    makes it."""

    var outline: SvgSubPath
    var holes: List[SvgSubPath]

    def __init__(out self, var outline: SvgSubPath):
        """Make a shape with no holes.

        Args:
            outline: Its outline.
        """
        self.outline = outline^
        self.holes = List[SvgSubPath]()

    def to_shape(self) raises -> Shape:
        """Return this shape as a `math.path.Shape`, for `shape_geometry`.

        Returns:
            The shape; see `SvgSubPath.to_path`.

        Raises:
            Error: If an outline has nothing drawn on it.
        """
        var shape = Shape(self.outline.to_path())
        for hole in self.holes:
            shape.add_hole(hole.to_path())
        return shape^


@fieldwise_init
struct _Simple(Copyable, Movable):
    """One outline as `createShapes` sees it: its points, its turn, and its
    bounding box."""

    var sub: Int
    var points: List[SvgVector]
    var is_cw: Bool
    var low: SvgVector
    var high: SvgVector


struct _Crossing(Copyable, Movable):
    """Where the scan line crosses an outline."""

    var identifier: Int
    var is_cw: Bool
    var point: SvgVector

    def __init__(out self, identifier: Int, is_cw: Bool, point: SvgVector):
        """Hold a crossing.

        Args:
            identifier: Which outline.
            is_cw: Whether it runs clockwise.
            point: Where.
        """
        self.identifier = identifier
        self.is_cw = is_cw
        self.point = point


def shape_area(contour: List[SvgVector]) -> Float64:
    """Return the signed area of a contour, three.js's `ShapeUtils.area`.

    Args:
        contour: The points.

    Returns:
        The area, positive when the contour runs counterclockwise.
    """
    var n = len(contour)
    var a = Float64(0)
    var p = n - 1
    for q in range(n):
        a += contour[p][0] * contour[q][1] - contour[q][0] * contour[p][1]
        p = q
    return a * 0.5


def _power_of_ten(k: Int) -> Float64:
    """Return `10^k` for `k` of zero or more, exact through `10^22`."""
    var power = Float64(1)
    for _ in range(k):
        power *= 10
    return power


def _digits(magnitude: Float64, e: Int) -> Float64:
    """Return `magnitude` over `10^(e - 9)`, rounded half up: its ten
    significant digits when `e` is its exponent."""
    var shift = 9 - e
    var scaled = magnitude * _power_of_ten(shift) if shift >= 0 else (
        magnitude / _power_of_ten(-shift)
    )
    return floor(scaled + 0.5)


def to_precision_10(x: Float64) -> Float64:
    """Return `+x.toPrecision(10)`: `x` rounded to ten significant digits.

    The ten digits `n` are a whole number, and the result is `n` times
    or over a power of ten. Both are exact through `10^22`, so the one
    rounding of the product or quotient is JavaScript's rounding of the
    decimal. Past that, beyond `1e31` or below `1e-13`, the power is
    rounded too.

    Args:
        x: The number.

    Returns:
        The rounded number. Zero, an infinity and NaN come back as they
        are.
    """
    var plain = x == 0 or not isfinite(x)
    if plain:
        return x
    var magnitude = abs(x)
    var e = Int(floor(log10(magnitude)))
    var n = _digits(magnitude, e)
    if n >= 1e10:
        # Rounding carried into an eleventh digit, or `log10` came out a
        # hair low.
        n = floor(n / 10 + 0.5)
        e += 1
    var k = e - 9
    var rounded = n * _power_of_ten(k) if k >= 0 else n / _power_of_ten(-k)
    return -rounded if x < 0 else rounded


@fieldwise_init
struct PointLocation(Equatable, ImplicitlyCopyable, Writable):
    """Where a point lies against an edge, three.js's
    `IntersectionLocationType`, as a type rather than a bare int.

    `find_edge_intersection` reads only what `classify_point` gives, so
    nothing takes one from outside; `is_valid` says which there are.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the seven locations."""
        return self.value >= LOCATION_ORIGIN.value and (
            self.value <= LOCATION_BEYOND.value
        )


comptime LOCATION_ORIGIN = PointLocation(0)
comptime LOCATION_DESTINATION = PointLocation(1)
comptime LOCATION_BETWEEN = PointLocation(2)
comptime LOCATION_LEFT = PointLocation(3)
comptime LOCATION_RIGHT = PointLocation(4)
comptime LOCATION_BEHIND = PointLocation(5)
comptime LOCATION_BEYOND = PointLocation(6)


def classify_point(
    p: SvgVector, edge_start: SvgVector, edge_end: SvgVector
) -> Tuple[PointLocation, Float64]:
    """Return where a point lies against an edge, and how far along,
    three.js's `classifyPoint`.

    Args:
        p: The point.
        edge_start: The edge's start.
        edge_end: Its end.

    Returns:
        The location, and for `LOCATION_BETWEEN`, `LOCATION_ORIGIN` and
        `LOCATION_DESTINATION` how far along the edge the point is; zero
        for the others.
    """
    var ax = edge_end[0] - edge_start[0]
    var ay = edge_end[1] - edge_start[1]
    var bx = p[0] - edge_start[0]
    var by = p[1] - edge_start[1]
    var sa = ax * by - bx * ay
    if same_point(p, edge_start):
        return (LOCATION_ORIGIN, Float64(0))
    if same_point(p, edge_end):
        return (LOCATION_DESTINATION, Float64(1))
    if sa < -JS_EPSILON:
        return (LOCATION_LEFT, Float64(0))
    if sa > JS_EPSILON:
        return (LOCATION_RIGHT, Float64(0))
    var behind = ax * bx < 0 or ay * by < 0
    if behind:
        return (LOCATION_BEHIND, Float64(0))
    if sqrt(ax * ax + ay * ay) < sqrt(bx * bx + by * by):
        return (LOCATION_BEYOND, Float64(0))
    var t: Float64
    if ax != 0:
        t = bx / ax
    else:
        t = by / ay
    return (LOCATION_BETWEEN, t)


def find_edge_intersection(
    a0: SvgVector, a1: SvgVector, b0: SvgVector, b1: SvgVector
) -> Optional[SIMD[DType.float64, 4]]:
    """Return where two edges meet, three.js's `findEdgeIntersection`.

    Args:
        a0: The first edge's start.
        a1: Its end.
        b0: The second edge's start.
        b1: Its end.

    Returns:
        The point's x and y, how far along the first edge it is, and a
        zero; or none when the edges do not meet.
    """
    var x1 = a0[0]
    var x2 = a1[0]
    var x3 = b0[0]
    var x4 = b1[0]
    var y1 = a0[1]
    var y2 = a1[1]
    var y3 = b0[1]
    var y4 = b1[1]
    # Each product is rounded before the difference, as in JavaScript, so
    # that an edge that ends on the first edge's start gives a `t1` of
    # exactly zero.
    var nom1 = _product(x4 - x3, y1 - y3) - _product(y4 - y3, x1 - x3)
    var nom2 = _product(x2 - x1, y1 - y3) - _product(y2 - y1, x1 - x3)
    var denom = _product(y4 - y3, x2 - x1) - _product(x4 - x3, y2 - y1)
    var t1 = nom1 / denom
    var t2 = nom2 / denom
    var ends: List[SvgVector] = [b0, b1]
    if _misses(denom, nom1, t1, t2):
        return None
    var colinear = nom1 == 0 and denom == 0
    if colinear:
        for end in ends:  # pragma: no branch
            var c = classify_point(end, a0, a1)
            if c[0] == LOCATION_ORIGIN:
                return SIMD[DType.float64, 4](end[0], end[1], c[1], 0)
            if c[0] == LOCATION_BETWEEN:
                return SIMD[DType.float64, 4](
                    to_precision_10(x1 + c[1] * (x2 - x1)),
                    to_precision_10(y1 + c[1] * (y2 - y1)),
                    c[1],
                    0,
                )
        return None
    # three.js next returns an end of the second edge that lies on the
    # first edge's start. Such an end makes `t1` zero, which `_misses`
    # has refused already, so that test is left out.
    return SIMD[DType.float64, 4](
        to_precision_10(x1 + t1 * (x2 - x1)),
        to_precision_10(y1 + t1 * (y2 - y1)),
        t1,
        0,
    )


def _misses(denom: Float64, nom1: Float64, t1: Float64, t2: Float64) -> Bool:
    """Return True when two edges are parallel apart, or do not reach each
    other: three.js's first test, NaN comparisons and all."""
    return (denom == 0 and nom1 != 0) or t1 <= 0 or t1 >= 1 or t2 < 0 or t2 > 1


@no_inline
def _product(a: Float64, b: Float64) -> Float64:
    """Return `a * b` rounded, where the compiler cannot fuse it into a
    multiply-add."""
    return a * b


def _add_intersections(
    mut crossings: List[_Crossing],
    line: List[SvgVector],
    path: _Simple,
    identifier: Int,
):
    """Add where a line crosses a path's edges, each distinct `t` once,
    three.js's `getIntersections`."""
    var ts = List[Float64]()
    for index in range(1, len(line)):  # pragma: no branch
        for index2 in range(1, len(path.points)):  # pragma: no branch
            var hit = find_edge_intersection(
                line[index - 1],
                line[index],
                path.points[index2 - 1],
                path.points[index2],
            )
            if not hit:
                continue
            var found = hit.value()
            var seen = False
            for t in ts:
                var seen_t = t <= found[2] + JS_EPSILON and (
                    t >= found[2] - JS_EPSILON
                )
                if seen_t:
                    seen = True
            if seen:
                continue
            ts.append(found[2])
            crossings.append(
                _Crossing(identifier, path.is_cw, SvgVector(found[0], found[1]))
            )


def _center(path: _Simple) -> SvgVector:
    """Return the middle of an outline's bounding box."""
    return (path.low + path.high) * 0.5


def _out_of_order(crossings: List[_Crossing], j: Int) -> Bool:
    """Return True if crossing `j` lies left of the one before it."""
    return j > 0 and crossings[j - 1].point[0] > crossings[j].point[0]


def _before(crossings: List[_Crossing], i: Int, x: Float64) -> Bool:
    """Return True if crossing `i` exists and lies left of `x`."""
    return i < len(crossings) and crossings[i].point[0] < x


def _sort_by_x(mut crossings: List[_Crossing]):
    """Sort crossings by x, keeping equal ones in order, as JavaScript's
    stable `sort` does."""
    for i in range(1, len(crossings)):
        var j = i
        while _out_of_order(crossings, j):
            crossings.swap_elements(j - 1, j)
            j -= 1


def _is_hole_to(
    simple: Int,
    paths: List[_Simple],
    min_x: Float64,
    max_x: Float64,
    rule: SvgFillRule,
) raises -> Tuple[Bool, Int]:
    """Return whether an outline is a hole, and which outline it is a hole
    in, three.js's `isHoleTo`."""
    var center = _center(paths[simple])
    var line: List[SvgVector] = [
        SvgVector(min_x, center[1]),
        SvgVector(max_x, center[1]),
    ]
    var all = List[_Crossing]()
    for identifier in range(len(paths)):  # pragma: no branch
        ref other = paths[identifier]
        var inside = (
            center[0] >= other.low[0]
            and center[0] <= other.high[0]
            and center[1] >= other.low[1]
            and center[1] <= other.high[1]
        )
        if inside:
            _add_intersections(all, line, other, identifier)
    _sort_by_x(all)
    var base_x = Float64(0)
    var found = False
    var others = List[_Crossing]()
    for crossing in all:
        if crossing.identifier == simple:
            if not found:
                base_x = crossing.point[0]
                found = True
        else:
            others.append(crossing.copy())
    if not found:
        raise Error(
            "SVG: the scan line through outline "
            + String(simple)
            + " does not cross it"
        )
    var stack = List[Int]()
    var i = 0
    while _before(others, i, base_x):
        var id = others[i].identifier
        var closes = len(stack) > 0 and stack[len(stack) - 1] == id
        if closes:
            _ = stack.pop()
        else:
            stack.append(id)
        i += 1
    stack.append(simple)
    if rule == SVG_EVENODD:
        var hole = len(stack) % 2 == 0
        var hole_for = stack[len(stack) - 2] if len(stack) >= 2 else -1
        return (hole, hole_for)
    var is_hole = True
    var hole_for = -1
    var last_cw = False
    for identifier in stack:  # pragma: no branch
        if is_hole:
            last_cw = paths[identifier].is_cw
            is_hole = False
            hole_for = identifier
        elif last_cw != paths[identifier].is_cw:
            last_cw = paths[identifier].is_cw
            is_hole = True
    return (is_hole, hole_for)


def create_shapes_with_rule(
    shape_path: SvgShapePath, rule: SvgFillRule
) raises -> List[SvgShape]:
    """Sort a shape path's outlines into shapes with holes by a fill rule.

    Args:
        shape_path: The outlines.
        rule: `SVG_NONZERO` or `SVG_EVENODD`.

    Returns:
        One shape for each outline that is not a hole, in order, each with
        its holes. An outline of fewer than two points is left out.

    Raises:
        Error: If the rule is not valid, or the scan line through an
            outline does not cross it.
    """
    if not rule.is_valid():
        raise Error("SVG: a fill rule that is not valid")
    var min_x = BIG_NUMBER
    var max_x = -BIG_NUMBER
    var simple = List[_Simple]()
    for sub in range(len(shape_path.sub_paths)):
        var points = shape_path.sub_paths[sub].get_points()
        var low = SvgVector(BIG_NUMBER, BIG_NUMBER)
        var high = SvgVector(-BIG_NUMBER, -BIG_NUMBER)
        for p in points:
            if p[1] > high[1]:
                high[1] = p[1]
            if p[1] < low[1]:
                low[1] = p[1]
            if p[0] > high[0]:
                high[0] = p[0]
            if p[0] < low[0]:
                low[0] = p[0]
        if max_x <= high[0]:
            max_x = high[0] + 1
        if min_x >= low[0]:
            min_x = low[0] - 1
        if len(points) > 1:
            var cw = shape_area(points) < 0
            simple.append(_Simple(sub, points^, cw, low, high))
    var holes = List[Tuple[Bool, Int]]()
    for index in range(len(simple)):
        holes.append(_is_hole_to(index, simple, min_x, max_x, rule))
    var shapes = List[SvgShape]()
    for index in range(len(simple)):
        if holes[index][0]:
            continue
        var shape = SvgShape(shape_path.sub_paths[simple[index].sub].copy())
        shape.outline.auto_close = False
        # This outline is one of them: the loop always runs.
        for other in range(len(simple)):  # pragma: no branch
            var is_mine = holes[other][0] and holes[other][1] == index
            if is_mine:
                var hole = shape_path.sub_paths[simple[other].sub].copy()
                hole.auto_close = False
                shape.holes.append(hole^)
        shapes.append(shape^)
    return shapes^


def create_shapes(shape_path: SvgShapePath) raises -> List[SvgShape]:
    """Sort a shape path's outlines into shapes with holes, three.js's
    `SVGLoader.createShapes`, by the path's own `fill-rule`.

    Args:
        shape_path: The outlines, with their style.

    Returns:
        See `create_shapes_with_rule`.

    Raises:
        Error: If the fill rule is not `nonzero` or `evenodd`, or for
            anything `create_shapes_with_rule` refuses.
    """
    return create_shapes_with_rule(
        shape_path, svg_fill_rule(shape_path.style.fill_rule)
    )


struct SvgStroke(Movable):
    """The triangles of a stroke, three.js's `pointsToStrokeWithBuffers`
    buffers."""

    # Three values a vertex: x, y and a zero.
    var vertices: List[Float64]
    # Three values a vertex: 0, 0, 1.
    var normals: List[Float64]
    # Two values a vertex.
    var uvs: List[Float64]
    # What three.js returns: three times the vertices.
    var count: Int

    def __init__(out self):
        """Start with no triangles."""
        self.vertices = List[Float64]()
        self.normals = List[Float64]()
        self.uvs = List[Float64]()
        self.count = 0

    def to_geometry(self) raises -> BufferGeometry:
        """Return the stroke as a geometry, three.js's `pointsToStroke`.

        Returns:
            A geometry with `position`, `normal` and `uv`.

        Raises:
            Error: If the stroke has no triangles, where three.js returns
                `null`.
        """
        if self.count == 0:
            raise Error("SVG: a stroke with no triangles")
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(_f32(self.vertices), 3)
        )
        geometry.set_attribute(
            String(NORMAL), BufferAttribute(_f32(self.normals), 3)
        )
        geometry.set_attribute(String(UV), BufferAttribute(_f32(self.uvs), 2))
        return geometry^


def _f32(values: List[Float64]) -> List[Float32]:
    """Return values narrowed to `Float32`, as a `Float32BufferAttribute`
    holds them."""
    var out = List[Float32](capacity=len(values))
    # A stroke with triangles has values: the loop always runs.
    for v in values:  # pragma: no branch
        out.append(Float32(v))
    return out^


def _length(v: SvgVector) -> Float64:
    """Return a vector's length, three.js's `Vector2.length`."""
    return sqrt(v[0] * v[0] + v[1] * v[1])


def _normalize(v: SvgVector) -> SvgVector:
    """Return a vector of length one, three.js's `normalize`: it divides by
    the length, or by one for a zero vector, as a multiply by the
    reciprocal."""
    var length = _length(v)
    if length == 0:
        length = 1
    return v * (1 / length)


def _dot(a: SvgVector, b: SvgVector) -> Float64:
    """Return the dot product."""
    return a[0] * b[0] + a[1] * b[1]


def _normal(p1: SvgVector, p2: SvgVector) -> SvgVector:
    """Return the left normal of the edge from `p1` to `p2`, three.js's
    `getNormal`."""
    var r = p2 - p1
    return _normalize(SvgVector(-r[1], r[0]))


def _rotate_around(
    v: SvgVector, center: SvgVector, angle: Float64
) -> SvgVector:
    """Return a point turned about a center, three.js's `rotateAround`."""
    var c = cos(angle)
    var s = sin(angle)
    var x = v[0] - center[0]
    var y = v[1] - center[1]
    return SvgVector(x * c - y * s + center[0], x * s + y * c + center[1])


def remove_duplicated_points(
    points: List[SvgVector], min_distance: Float64
) -> List[SvgVector]:
    """Return the points with each one closer than `min_distance` to the
    next removed, three.js's `removeDuplicatedPoints`. The first and last
    points stay.

    Args:
        points: The points.
        min_distance: The distance below which two points are one.

    Returns:
        The points left.
    """
    var n = len(points)
    var dup = False
    for i in range(1, n - 1):
        if _length(points[i] - points[i + 1]) < min_distance:
            dup = True
            break
    if not dup:
        return points.copy()
    var out = List[SvgVector]()
    out.append(points[0])
    for i in range(1, n - 1):  # pragma: no branch
        if _length(points[i] - points[i + 1]) >= min_distance:
            out.append(points[i])
    out.append(points[n - 1])
    return out^


struct _Stroker:
    """The state of three.js's `pointsToStrokeWithBuffers`, its closures'
    shared variables as fields."""

    var out: SvgStroke
    var style: SvgStrokeStyle
    var arc_divisions: Int
    var t1: SvgVector
    var t2: SvgVector
    var t3: SvgVector
    var t4: SvgVector
    var t5: SvgVector
    var t6: SvgVector
    var t7: SvgVector
    var last_l: SvgVector
    var last_r: SvgVector
    var point0_l: SvgVector
    var point0_r: SvgVector
    var current_l: SvgVector
    var current_r: SvgVector
    var next_l: SvgVector
    var next_r: SvgVector
    var inner: SvgVector
    var outer: SvgVector
    var u0: Float64
    var u1: Float64

    def __init__(out self, style: SvgStrokeStyle, arc_divisions: Int):
        """Start with every point at the origin."""
        self.out = SvgStroke()
        self.style = style.copy()
        self.arc_divisions = arc_divisions
        var zero = SvgVector(0, 0)
        self.t1 = zero
        self.t2 = zero
        self.t3 = zero
        self.t4 = zero
        self.t5 = zero
        self.t6 = zero
        self.t7 = zero
        self.last_l = zero
        self.last_r = zero
        self.point0_l = zero
        self.point0_r = zero
        self.current_l = zero
        self.current_r = zero
        self.next_l = zero
        self.next_r = zero
        self.inner = zero
        self.outer = zero
        self.u0 = 0
        self.u1 = 0

    def take(deinit self) -> SvgStroke:
        """Return the triangles."""
        return self.out^

    def add(mut self, p: SvgVector, u: Float64, v: Float64):
        """Add one vertex, three.js's `addVertex`."""
        self.out.vertices.append(p[0])
        self.out.vertices.append(p[1])
        self.out.vertices.append(0)
        self.out.normals.append(0)
        self.out.normals.append(0)
        self.out.normals.append(1)
        self.out.uvs.append(u)
        self.out.uvs.append(v)
        self.out.count += 3

    def put(mut self, p: SvgVector, at: Int):
        """Overwrite a vertex's x and y, three.js's `toArray(vertices, at)`."""
        self.out.vertices[at] = p[0]
        self.out.vertices[at + 1] = p[1]

    def sector(
        mut self,
        center: SvgVector,
        p1: SvgVector,
        p2: SvgVector,
        u: Float64,
        v: Float64,
    ):
        """Add a fan of triangles round a center from `p1` to `p2`,
        three.js's `makeCircularSector`."""
        self.t1 = _normalize(p1 - center)
        self.t2 = _normalize(p2 - center)
        var angle = pi
        var dot = _dot(self.t1, self.t2)
        if abs(dot) < 1:
            angle = abs(acos(dot))
        angle /= Float64(self.arc_divisions)
        self.t3 = p1
        for _ in range(self.arc_divisions - 1):
            self.t4 = _rotate_around(self.t3, center, angle)
            self.add(self.t3, u, v)
            self.add(self.t4, u, v)
            self.add(center, u, 0.5)
            self.t3 = self.t4
        self.add(self.t4, u, v)
        self.add(p2, u, v)
        self.add(center, u, 0.5)

    def segment(mut self):
        """Add a segment's two triangles, three.js's
        `makeSegmentTriangles`."""
        self.add(self.last_r, self.u0, 1)
        self.add(self.last_l, self.u0, 0)
        self.add(self.current_l, self.u1, 0)
        self.add(self.last_r, self.u0, 1)
        self.add(self.current_l, self.u1, 0)
        self.add(self.current_r, self.u1, 1)

    def bevel(
        mut self, left: Bool, modified: Bool, u: Float64, current: SvgVector
    ):
        """Add a bevel join, three.js's `makeSegmentWithBevelJoin`."""
        if modified:
            if left:
                self.add(self.last_r, self.u0, 1)
                self.add(self.last_l, self.u0, 0)
                self.add(self.current_l, self.u1, 0)
                self.add(self.last_r, self.u0, 1)
                self.add(self.current_l, self.u1, 0)
                self.add(self.inner, self.u1, 1)
                self.add(self.current_l, u, 0)
                self.add(self.next_l, u, 0)
                self.add(self.inner, u, 0.5)
            else:
                self.add(self.last_r, self.u0, 1)
                self.add(self.last_l, self.u0, 0)
                self.add(self.current_r, self.u1, 1)
                self.add(self.last_l, self.u0, 0)
                self.add(self.inner, self.u1, 0)
                self.add(self.current_r, self.u1, 1)
                self.add(self.current_r, u, 1)
                self.add(self.inner, u, 0)
                self.add(self.next_r, u, 1)
        elif left:
            self.add(self.current_l, u, 0)
            self.add(self.next_l, u, 0)
            self.add(current, u, 0.5)
        else:
            self.add(self.current_r, u, 1)
            self.add(self.next_r, u, 0)
            self.add(current, u, 0.5)

    def middle(mut self, left: Bool, modified: Bool, current: SvgVector):
        """Add a segment with a middle section, three.js's
        `createSegmentTrianglesWithMiddleSection`."""
        if not modified:
            return
        if left:
            self.add(self.last_r, self.u0, 1)
            self.add(self.last_l, self.u0, 0)
            self.add(self.current_l, self.u1, 0)
            self.add(self.last_r, self.u0, 1)
            self.add(self.current_l, self.u1, 0)
            self.add(self.inner, self.u1, 1)
            self.add(self.current_l, self.u0, 0)
            self.add(current, self.u1, 0.5)
            self.add(self.inner, self.u1, 1)
            self.add(current, self.u1, 0.5)
            self.add(self.next_l, self.u0, 0)
            self.add(self.inner, self.u1, 1)
        else:
            self.add(self.last_r, self.u0, 1)
            self.add(self.last_l, self.u0, 0)
            self.add(self.current_r, self.u1, 1)
            self.add(self.last_l, self.u0, 0)
            self.add(self.inner, self.u1, 0)
            self.add(self.current_r, self.u1, 1)
            self.add(self.current_r, self.u0, 1)
            self.add(self.inner, self.u1, 0)
            self.add(current, self.u1, 0.5)
            self.add(current, self.u1, 0.5)
            self.add(self.inner, self.u1, 0)
            self.add(self.next_r, self.u0, 1)

    def cap(
        mut self,
        center: SvgVector,
        p1: SvgVector,
        p2: SvgVector,
        left: Bool,
        start: Bool,
        u: Float64,
    ):
        """Add a cap at an end, three.js's `addCapGeometry`."""
        if self.style.cap == SVG_CAP_ROUND:
            if start:
                self.sector(center, p2, p1, u, 0.5)
            else:
                self.sector(center, p1, p2, u, 0.5)
        elif self.style.cap == SVG_CAP_SQUARE:
            if start:
                self.t1 = p1 - center
                self.t2 = SvgVector(self.t1[1], -self.t1[0])
                self.t3 = self.t1 + self.t2 + center
                self.t4 = self.t2 - self.t1 + center
                if left:
                    self.put(self.t3, 3)
                    self.put(self.t4, 0)
                    self.put(self.t4, 9)
                else:
                    self.put(self.t3, 3)
                    if self.out.uvs[7] == 1:
                        self.put(self.t4, 9)
                    else:
                        self.put(self.t3, 9)
                    self.put(self.t4, 0)
            else:
                self.t1 = p2 - center
                self.t2 = SvgVector(self.t1[1], -self.t1[0])
                self.t3 = self.t1 + self.t2 + center
                self.t4 = self.t2 - self.t1 + center
                var vl = len(self.out.vertices)
                if left:
                    self.put(self.t3, vl - 3)
                    self.put(self.t4, vl - 6)
                    self.put(self.t4, vl - 12)
                else:
                    self.put(self.t4, vl - 6)
                    self.put(self.t3, vl - 3)
                    self.put(self.t4, vl - 12)


def points_to_stroke(
    points_in: List[SvgVector],
    style: SvgStrokeStyle,
    arc_divisions: Int = 12,
    min_distance: Float64 = 0.001,
) raises -> SvgStroke:
    """Return the triangles of a stroke along points, three.js's
    `pointsToStrokeWithBuffers`.

    Args:
        points_in: The points, two or more; closed when the last equals the
            first.
        style: The stroke's width, join, cap and miter limit.
        arc_divisions: How many triangles a round join or cap takes.
        min_distance: Points closer than this are one.

    Returns:
        The triangles. None when fewer than two points are left.

    Raises:
        Error: If the join or the cap is not valid, or `arc_divisions` is
            below one.
    """
    var refused = not style.join.is_valid() or not style.cap.is_valid()
    if refused:
        raise Error("SVG: a stroke join or cap that is not valid")
    if arc_divisions < 1:
        raise Error("SVG: a stroke needs at least one arc division")
    var points = remove_duplicated_points(points_in, min_distance)
    var n = len(points)
    var s = _Stroker(style, arc_divisions)
    if n < 2:
        return s^.take()
    var is_closed = same_point(points[0], points[n - 1])
    var current = points[0]
    var previous = points[0]
    var half = style.width / 2
    var delta_u = 1 / Float64(n - 1)
    var modified = False
    var left = False
    var is_miter = False
    var initial_left = False

    s.t1 = _normal(points[0], points[1]) * half
    s.last_l = points[0] - s.t1
    s.last_r = points[0] + s.t1
    s.point0_l = s.last_l
    s.point0_r = s.last_r

    # Two points or more: the loop always runs.
    for i in range(1, n):  # pragma: no branch
        current = points[i]
        var has_next = True
        var next = points[0]
        if i == n - 1:
            has_next = is_closed
            if is_closed:
                next = points[1]
        else:
            next = points[i + 1]
        s.t1 = _normal(previous, current)
        var normal1 = s.t1
        s.t3 = normal1 * half
        s.current_l = current - s.t3
        s.current_r = current + s.t3
        s.u1 = s.u0 + delta_u
        modified = False
        if has_next:
            s.t2 = _normal(current, next)
            s.t3 = s.t2 * half
            s.next_l = current - s.t3
            s.next_r = current + s.t3
            left = True
            s.t3 = next - previous
            if _dot(normal1, s.t3) < 0:
                left = False
            if i == 1:
                initial_left = left
            s.t3 = _normalize(next - current)
            var dot = abs(_dot(normal1, s.t3))
            if dot > JS_EPSILON:
                var miter_side = half / dot
                s.t3 = s.t3 * -miter_side
                s.t4 = current - previous
                s.t5 = _normalize(s.t4) * miter_side + s.t3
                s.inner = -s.t5
                var miter_length2 = _length(s.t5)
                var prev_length = _length(s.t4)
                s.t4 = s.t4 * (1 / prev_length)
                s.t6 = next - current
                var next_length = _length(s.t6)
                s.t6 = s.t6 * (1 / next_length)
                var clear = _dot(s.t4, s.inner) < prev_length and (
                    _dot(s.t6, s.inner) < next_length
                )
                if clear:
                    modified = True
                s.outer = s.t5 + current
                s.inner = s.inner + current
                is_miter = False
                if modified:
                    if left:
                        s.next_r = s.inner
                        s.current_r = s.inner
                    else:
                        s.next_l = s.inner
                        s.current_l = s.inner
                else:
                    s.segment()
                if style.join == SVG_JOIN_BEVEL:
                    s.bevel(left, modified, s.u1, current)
                elif style.join == SVG_JOIN_ROUND:
                    s.middle(left, modified, current)
                    if left:
                        s.sector(current, s.current_l, s.next_l, s.u1, 0)
                    else:
                        s.sector(current, s.next_r, s.current_r, s.u1, 1)
                else:
                    var fraction = half * style.miter_limit / miter_length2
                    if fraction < 1:
                        if style.join != SVG_JOIN_MITER_CLIP:
                            s.bevel(left, modified, s.u1, current)
                        else:
                            s.middle(left, modified, current)
                            _miter_clip(s, left, fraction, current)
                    else:
                        _miter(s, left, modified, current)
                        is_miter = True
            else:
                s.segment()
        else:
            s.segment()
        var first_cap = not is_closed and i == n - 1
        if first_cap:
            s.cap(points[0], s.point0_l, s.point0_r, left, True, s.u0)
        s.u0 = s.u1
        previous = current
        s.last_l = s.next_l
        s.last_r = s.next_r

    if not is_closed:
        s.cap(current, s.current_l, s.current_r, left, False, s.u1)
    elif modified:
        var last_outer = s.outer
        var last_inner = s.inner
        if initial_left != left:
            last_outer = s.inner
            last_inner = s.outer
        # three.js adjusts the first segment when the path ends on a miter,
        # or when the first join is on the same side as the last.
        var adjust = is_miter or initial_left == left
        if adjust:
            if left:
                s.put(last_inner, 0)
                s.put(last_inner, 9)
                if is_miter:
                    s.put(last_outer, 3)
            else:
                s.put(last_inner, 3)
                s.put(last_inner, 9)
                if is_miter:
                    s.put(last_outer, 0)
    return s^.take()


def _miter_clip(
    mut s: _Stroker, left: Bool, fraction: Float64, current: SvgVector
):
    """Add a clipped miter join, three.js's `miter-clip` branch."""
    if left:
        s.t6 = (s.outer - s.current_l) * fraction + s.current_l
        s.t7 = (s.outer - s.next_l) * fraction + s.next_l
        s.add(s.current_l, s.u1, 0)
        s.add(s.t6, s.u1, 0)
        s.add(current, s.u1, 0.5)
        s.add(current, s.u1, 0.5)
        s.add(s.t6, s.u1, 0)
        s.add(s.t7, s.u1, 0)
        s.add(current, s.u1, 0.5)
        s.add(s.t7, s.u1, 0)
        s.add(s.next_l, s.u1, 0)
    else:
        s.t6 = (s.outer - s.current_r) * fraction + s.current_r
        s.t7 = (s.outer - s.next_r) * fraction + s.next_r
        s.add(s.current_r, s.u1, 1)
        s.add(s.t6, s.u1, 1)
        s.add(current, s.u1, 0.5)
        s.add(current, s.u1, 0.5)
        s.add(s.t6, s.u1, 1)
        s.add(s.t7, s.u1, 1)
        s.add(current, s.u1, 0.5)
        s.add(s.t7, s.u1, 1)
        s.add(s.next_r, s.u1, 1)


def _miter(mut s: _Stroker, left: Bool, modified: Bool, current: SvgVector):
    """Add a miter join, three.js's `miter` branch within its limit."""
    if modified:
        if left:
            s.add(s.last_r, s.u0, 1)
            s.add(s.last_l, s.u0, 0)
            s.add(s.outer, s.u1, 0)
            s.add(s.last_r, s.u0, 1)
            s.add(s.outer, s.u1, 0)
            s.add(s.inner, s.u1, 1)
            s.next_l = s.outer
        else:
            s.add(s.last_r, s.u0, 1)
            s.add(s.last_l, s.u0, 0)
            s.add(s.outer, s.u1, 1)
            s.add(s.last_l, s.u0, 0)
            s.add(s.inner, s.u1, 0)
            s.add(s.outer, s.u1, 1)
            s.next_r = s.outer
    elif left:
        s.add(s.current_l, s.u1, 0)
        s.add(s.outer, s.u1, 0)
        s.add(current, s.u1, 0.5)
        s.add(current, s.u1, 0.5)
        s.add(s.outer, s.u1, 0)
        s.add(s.next_l, s.u1, 0)
    else:
        s.add(s.current_r, s.u1, 1)
        s.add(s.outer, s.u1, 1)
        s.add(current, s.u1, 0.5)
        s.add(current, s.u1, 0.5)
        s.add(s.outer, s.u1, 1)
        s.add(s.next_r, s.u1, 1)
