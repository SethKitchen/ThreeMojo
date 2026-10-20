# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Levels of detail for Gaussian splats, so that a far scan draws about as
many splats as it covers pixels.

A scan of a building can hold millions of splats. Seen whole in a small
frame, most of them are smaller than a pixel, and the draw spends its time
on splats that add little each. A level-of-detail tree draws a cluster of
such splats as one.

`build_splat_lod` sorts the splats along a Morton curve of their centers,
and builds an octree over the sorted splats. So each node holds one run of
them. A leaf holds `LOD_LEAF` splats or fewer. A node of more than one
splat also has a merged splat:

- **Weights.** A splat weighs its opacity times its area: the square root
  of the sum of its covariance's 2 by 2 principal minors, which is the
  product of its two widest deviations when it is flat. A node of splats
  that all weigh nothing weighs them all the same.
- **Shape.** The merged splat has the weighted mean of the centers, and
  the weighted mean of the covariances, each widened by its center's
  offset from the mean. That is the Gaussian with the same first two
  moments.
- **Widening.** Splats whose summed weight is more than that area widen
  the merged splat, until its area holds their weight or the root of its
  covariance's trace reaches the node's radius. A Gaussian of a square's
  moments is too narrow to tile a surface, and without it a wall of
  merged splats shows a seam at each edge of a node.
- **Color.** The color bytes and the spherical harmonics are weighted
  means. The opacity is the summed weight over the merged splat's own
  area, at most one. So a surface of opaque splats stays opaque.

`select_splats` walks the tree for a view. A node whose bounding sphere
covers `pixels` pixels or fewer draws as its merged splat, and its
children are skipped. A node wholly behind the camera, or past a side of
the view, is skipped with all of its splats. At `pixels` 0 every splat of
the scan is drawn.

`prepare_splat_lod` shades and projects the selected splats, and sorts
them back to front into `BIN_COUNT` bins of view depth, as
`GaussianSplat.update_sort` sorts. `draw_splat_lod` fills them with
`rasterize_splats`. The splats of one bin keep the order of the tree, so
at `pixels` 0 the picture can differ from `draw_gaussian_splat` where two
splats share a bin. More workers draw the same picture to the bit.
"""

from cameras.camera import Camera
from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    clamped_byte,
    create_gaussian_splat_geometry,
    sh_band_components,
    sh_band_words,
)
from core.object3d import NodeId
from core.ordinal import require_valid
from core.scene import Scene
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.gaussian_splat import BIN_COUNT, MIN_SORT_RANGE, GaussianSplat
from render.raster_state import DepthMode, log_depth_factor
from render.rect import Rect
from render.splat_raster import rasterize_splats, require_splat_depth
from render.splatrule import (
    CLIP_XY,
    FloatRgba,
    ProjectedSplat,
    SplatView,
    project_splat,
)
from render.target import RenderTarget
from render.tasks import TaskGroup
from std.math import floor, isfinite, max, min, sqrt

comptime LOD_LEAF = 8
"""The most splats a leaf holds, unless more share one Morton code."""
comptime LOD_BITS = 21
"""The bits of each axis in a center's Morton code."""
comptime LOD_PIXELS = Float32(2.5)
"""How many pixels a node's bounding sphere reaches, at most, for the node
to draw as its merged splat. At 2.5, the tomatoes filling a frame of 320 by
200 draw in a third of their splats, within half a level of 255."""
comptime LOD_RUN = 4096
"""The fewest splats a worker takes: a shorter run is not worth a task."""


@fieldwise_init
struct SplatLodNode(ImplicitlyCopyable):
    """One node of a level-of-detail tree."""

    var low: Int
    """Its first splat, in tree order."""
    var high: Int
    """One past its last splat."""
    var first_child: Int
    """Its first child; the children follow it in the node list."""
    var children: Int
    """How many children it has: 0 for a leaf."""
    var merged: Int
    """The splat it draws as when it is small: its merged splat, or its only splat."""
    var center: Vector3
    """The center of a sphere that holds its splats out to their cutoff."""
    var radius: Float32
    """That sphere's radius."""


struct SplatLod(Movable):
    """A level-of-detail tree over a geometry's splats; see the module
    docstring."""

    var splat: GaussianSplat
    """The scan's splats in tree order, and then the merged splats."""
    var nodes: List[SplatLodNode]
    """The tree, the root first. It is empty for no splats."""
    var source: List[Int]
    """For each of the scan's splats in tree order, its index in the scan."""

    def __init__(
        out self,
        var splat: GaussianSplat,
        var nodes: List[SplatLodNode],
        var source: List[Int],
    ):
        """Hold a tree.

        Args:
            splat: The splats, the scan's and then the merged ones.
            nodes: The tree, the root first.
            source: The scan's index of each of its splats.
        """
        self.splat = splat^
        self.nodes = nodes^
        self.source = source^

    def scan_count(self) -> Int:
        """Return how many splats the scan has.

        Returns:
            The count; the merged splats follow them.
        """
        return len(self.source)


def _spread(value: UInt64) -> UInt64:
    """Spread 21 bits out to every third bit.

    Args:
        value: The bits, in the low 21.

    Returns:
        Bit i of `value` at bit `3 i`.
    """
    var x = value & 0x1FFFFF
    x = (x | (x << 32)) & 0x1F00000000FFFF
    x = (x | (x << 16)) & 0x1F0000FF0000FF
    x = (x | (x << 8)) & 0x100F00F00F00F00F
    x = (x | (x << 4)) & 0x10C30C30C30C30C3
    x = (x | (x << 2)) & 0x1249249249249249
    return x


def _cell(value: Float32, low: Float64, scale: Float64) -> UInt64:
    """Return a coordinate's cell along one axis of the Morton grid.

    Args:
        value: The coordinate.
        low: The least coordinate of the splats.
        scale: Cells a unit.

    Returns:
        The cell, 0 to `2^LOD_BITS - 1`. A coordinate that is not finite
        is in cell 0.
    """
    var at = (Float64(value) - low) * scale
    if not (at > 0):
        return 0
    return UInt64(Int(min(at, Float64((1 << LOD_BITS) - 1))))


def morton_order(
    geometry: GaussianSplatGeometry,
) -> Tuple[List[UInt64], List[Int]]:
    """Return the splats' Morton codes, and the splats in Morton order.

    Args:
        geometry: The splats.

    Returns:
        The codes in Morton order, and for each place the splat's index.
        Splats of one code keep their order.
    """
    var count = geometry.count()
    ref c = geometry.centers
    var low = SIMD[DType.float64, 4](Float64.MAX)
    var high = SIMD[DType.float64, 4](-Float64.MAX)
    for index in range(count):
        var at = SIMD[DType.float64, 4](
            Float64(c[index * 3]),
            Float64(c[index * 3 + 1]),
            Float64(c[index * 3 + 2]),
            0,
        )
        if isfinite(at).reduce_and():
            low = min(low, at)
            high = max(high, at)
    var span = max((high - low).reduce_max(), Float64(1e-30))
    var scale = Float64((1 << LOD_BITS) - 1) / span
    var codes = List[UInt64](capacity=count)
    var order = List[Int](capacity=count)
    for index in range(count):
        codes.append(
            _spread(_cell(c[index * 3], low[0], scale))
            | (_spread(_cell(c[index * 3 + 1], low[1], scale)) << 1)
            | (_spread(_cell(c[index * 3 + 2], low[2], scale)) << 2)
        )
        order.append(index)
    # A stable radix sort, sixteen bits a pass.
    var spare_codes = List[UInt64](length=count, fill=0)
    var spare_order = List[Int](length=count, fill=0)
    for shift in range(0, 64, 16):  # pragma: no branch
        var counts = List[Int](length=65537, fill=0)
        for index in range(count):
            counts[Int((codes[index] >> UInt64(shift)) & 0xFFFF) + 1] += 1
        for digit in range(65536):  # pragma: no branch
            counts[digit + 1] += counts[digit]
        for index in range(count):
            var digit = Int((codes[index] >> UInt64(shift)) & 0xFFFF)
            spare_codes[counts[digit]] = codes[index]
            spare_order[counts[digit]] = order[index]
            counts[digit] += 1
        swap(codes, spare_codes)
        swap(order, spare_order)
    return (codes^, order^)


def _digit(code: UInt64, level: Int) -> Int:
    """Return the octant of a code at one level of the tree.

    Args:
        code: The Morton code.
        level: The level, `LOD_BITS - 1` at the root down to 0.

    Returns:
        Its three bits at that level.
    """
    return Int((code >> UInt64(3 * level)) & 7)


def _build(
    mut nodes: List[SplatLodNode],
    codes: List[UInt64],
    low: Int,
    high: Int,
    level: Int,
    slot: Int,
):
    """Make node `slot` hold the splats from `low` to `high`, and its
    children below it.

    Args:
        nodes: The tree so far. `slot` is in it.
        codes: The Morton codes, in order.
        low: The node's first splat.
        high: One past its last.
        level: The level whose octants split it.
        slot: The node's place.
    """
    var empty = Vector3(0, 0, 0)
    if high - low <= LOD_LEAF:
        nodes[slot] = SplatLodNode(low, high, -1, 0, -1, empty, 0)
        return
    # A level at which every splat is in one octant splits nothing.
    var at = level
    while at >= 0 and _digit(codes[low], at) == _digit(codes[high - 1], at):
        at -= 1
    if at < 0:
        nodes[slot] = SplatLodNode(low, high, -1, 0, -1, empty, 0)
        return
    var starts: List[Int] = [low]
    for index in range(low + 1, high):  # pragma: no branch
        if _digit(codes[index], at) != _digit(codes[index - 1], at):
            starts.append(index)
    starts.append(high)
    var first = len(nodes)
    for _ in range(len(starts) - 1):  # pragma: no branch
        nodes.append(SplatLodNode(0, 0, -1, 0, -1, empty, 0))
    nodes[slot] = SplatLodNode(low, high, first, len(starts) - 1, -1, empty, 0)
    for child in range(len(starts) - 1):  # pragma: no branch
        _build(
            nodes,
            codes,
            starts[child],
            starts[child + 1],
            at - 1,
            first + child,
        )


def _reach(c: List[Float32], at: Int) -> Float64:
    """Return how far a splat reaches from its center: twice the square
    root of a bound on its covariance's largest eigenvalue.

    Args:
        c: The covariances.
        at: Where the splat's six floats start.

    Returns:
        Twice the root of the largest row sum of absolute values.
    """
    var c00 = abs(Float64(c[at]))
    var c01 = abs(Float64(c[at + 1]))
    var c02 = abs(Float64(c[at + 2]))
    var c11 = abs(Float64(c[at + 3]))
    var c12 = abs(Float64(c[at + 4]))
    var c22 = abs(Float64(c[at + 5]))
    return 2 * sqrt(max(c00 + c01 + c02, max(c01 + c11 + c12, c02 + c12 + c22)))


def _area(c: SIMD[DType.float64, 8]) -> Float64:
    """Return a covariance's area: the root of its 2 by 2 principal minors.

    Args:
        c: `c00 c01 c02 c11 c12 c22` in the first six lanes.

    Returns:
        The area, zero for a covariance that is not positive.
    """
    var minors = (
        c[0] * c[3]
        - c[1] * c[1]
        + c[0] * c[5]
        - c[2] * c[2]
        + c[3] * c[5]
        - c[4] * c[4]
    )
    return sqrt(max(minors, 0))


def _covariance(c: List[Float32], at: Int) -> SIMD[DType.float64, 8]:
    """Return a splat's covariance as lanes.

    Args:
        c: The covariances.
        at: Where the splat's six floats start.

    Returns:
        `c00 c01 c02 c11 c12 c22` and two zeros.
    """
    return SIMD[DType.float64, 8](
        Float64(c[at]),
        Float64(c[at + 1]),
        Float64(c[at + 2]),
        Float64(c[at + 3]),
        Float64(c[at + 4]),
        Float64(c[at + 5]),
        0,
        0,
    )


def _merge(
    mut g: GaussianSplatGeometry, mut node: SplatLodNode, slot: Int
) raises:
    """Merge a node's splats into splat `slot`, and bound them.

    Args:
        g: The splats, the scan's in tree order first. Splat `slot` is
            written.
        node: The node. Its sphere is written, and its merged splat when it
            has more than one splat.
        slot: Where the merged splat goes.

    Raises:
        Error: Never, for the bands that `g` holds.
    """
    ref centers = g.centers
    # The bounding sphere: the box of the splats' reach, and its center.
    var low = SIMD[DType.float64, 4](Float64.MAX)
    var high = SIMD[DType.float64, 4](-Float64.MAX)
    for index in range(node.low, node.high):  # pragma: no branch
        var at = SIMD[DType.float64, 4](
            Float64(centers[index * 3]),
            Float64(centers[index * 3 + 1]),
            Float64(centers[index * 3 + 2]),
            0,
        )
        var reach = _reach(g.covariances, index * 6)
        low = min(low, at - reach)
        high = max(high, at + reach)
    var middle = (low + high) * 0.5
    var radius = Float64(0)
    for index in range(node.low, node.high):  # pragma: no branch
        var at = SIMD[DType.float64, 4](
            Float64(centers[index * 3]),
            Float64(centers[index * 3 + 1]),
            Float64(centers[index * 3 + 2]),
            0,
        )
        var offset = at - middle
        radius = max(
            radius,
            sqrt((offset * offset).reduce_add())
            + _reach(g.covariances, index * 6),
        )
    node.center = Vector3(
        Float32(middle[0]), Float32(middle[1]), Float32(middle[2])
    )
    node.radius = Float32(radius)
    if node.high - node.low == 1:
        node.merged = node.low
        return
    node.merged = slot
    # The weights, and the mean.
    var total = Float64(0)
    for index in range(node.low, node.high):  # pragma: no branch
        total += (
            Float64(g.colors[index * 4 + 3])
            / 255
            * _area(_covariance(g.covariances, index * 6))
        )
    var even = not (total > 0)
    var weight_sum = Float64(0)
    var mean = SIMD[DType.float64, 4](0)
    for index in range(node.low, node.high):  # pragma: no branch
        var w = (
            Float64(1) if even else Float64(g.colors[index * 4 + 3])
            / 255
            * _area(_covariance(g.covariances, index * 6))
        )
        weight_sum += w
        mean += w * SIMD[DType.float64, 4](
            Float64(centers[index * 3]),
            Float64(centers[index * 3 + 1]),
            Float64(centers[index * 3 + 2]),
            0,
        )
    mean = mean / weight_sum
    # The second moment about the mean, the colors and the harmonics.
    var spread = SIMD[DType.float64, 8](0)
    var color = SIMD[DType.float64, 4](0)
    var degree = g.spherical_harmonics_degree()
    var sums = List[Float64](length=45, fill=0)
    for index in range(node.low, node.high):  # pragma: no branch
        var w = (
            Float64(1) if even else Float64(g.colors[index * 4 + 3])
            / 255
            * _area(_covariance(g.covariances, index * 6))
        )
        var d = (
            SIMD[DType.float64, 4](
                Float64(centers[index * 3]),
                Float64(centers[index * 3 + 1]),
                Float64(centers[index * 3 + 2]),
                0,
            )
            - mean
        )
        spread += w * (
            _covariance(g.covariances, index * 6)
            + SIMD[DType.float64, 8](
                d[0] * d[0],
                d[0] * d[1],
                d[0] * d[2],
                d[1] * d[1],
                d[1] * d[2],
                d[2] * d[2],
                0,
                0,
            )
        )
        color += w * SIMD[DType.float64, 4](
            Float64(g.colors[index * 4]),
            Float64(g.colors[index * 4 + 1]),
            Float64(g.colors[index * 4 + 2]),
            0,
        )
        var at = 0
        for band in range(1, degree + 1):
            var stride = sh_band_words(band) * 4
            for k in range(sh_band_components(band)):  # pragma: no branch
                var byte: UInt8
                if band == 1:
                    byte = g.sh1[index * stride + k]
                elif band == 2:
                    byte = g.sh2[index * stride + k]
                else:
                    byte = g.sh3[index * stride + k]
                sums[at] += w * (Float64(byte) - 128)
                at += 1
    spread = spread / weight_sum
    # Splats that cover more than the merged splat's area widen it, until
    # its opacity times its area holds their weight, or its deviation
    # reaches the sphere. So the merged splats of a wall meet with no seam.
    var cover = total / max(_area(spread), 1e-30)
    var limit = radius * radius / max(spread[0] + spread[3] + spread[5], 1e-30)
    spread = spread * max(Float64(1), min(cover, limit))
    color = color / weight_sum
    for n in range(3):  # pragma: no branch
        centers[slot * 3 + n] = Float32(mean[n])
    for n in range(6):  # pragma: no branch
        g.covariances[slot * 6 + n] = Float32(spread[n])
    for n in range(3):  # pragma: no branch
        g.colors[slot * 4 + n] = clamped_byte(color[n])
    var opacity = min(Float64(1), total / max(_area(spread), 1e-30))
    g.colors[slot * 4 + 3] = clamped_byte(opacity * 255)
    var at = 0
    for band in range(1, degree + 1):
        var stride = sh_band_words(band) * 4
        for k in range(sh_band_components(band)):  # pragma: no branch
            var byte = clamped_byte(128 + sums[at] / weight_sum)
            if band == 1:
                g.sh1[slot * stride + k] = byte
            elif band == 2:
                g.sh2[slot * stride + k] = byte
            else:
                g.sh3[slot * stride + k] = byte
            at += 1


def _gather_band(
    source: List[UInt8], order: List[Int], band: Int, degree: Int, total: Int
) raises -> List[UInt8]:
    """Return one band's bytes in tree order, with room for the merged
    splats.

    Args:
        source: The band's bytes in the scan's order.
        order: The scan's index of each splat in tree order.
        band: The band, 1 to 3.
        degree: The scan's degree.
        total: How many splats, the merged ones with them.

    Returns:
        The bytes, 128 past the scan's splats, or none above the degree.

    Raises:
        Error: Never, for a band of 1 to 3.
    """
    if band > degree:
        return List[UInt8]()
    var stride = sh_band_words(band) * 4
    var out = List[UInt8](length=total * stride, fill=128)
    for place in range(len(order)):  # pragma: no branch
        for k in range(stride):  # pragma: no branch
            out[place * stride + k] = source[order[place] * stride + k]
    return out^


def build_splat_lod(
    geometry: GaussianSplatGeometry, node: NodeId
) raises -> SplatLod:
    """Build a level-of-detail tree over splats; see the module docstring.

    Args:
        geometry: The splats.
        node: The scene node that places them.

    Returns:
        The tree, its splats at `node`.

    Raises:
        Error: Everything `create_gaussian_splat_geometry` and
            `GaussianSplat` raise.
    """
    var count = geometry.count()
    var sorted = morton_order(geometry)
    ref codes = sorted[0]
    ref order = sorted[1]
    var nodes = List[SplatLodNode]()
    if count > 0:
        nodes.append(SplatLodNode(0, 0, -1, 0, -1, Vector3(0, 0, 0), 0))
        _build(nodes, codes, 0, count, LOD_BITS - 1, 0)
    var merged = 0
    for at in range(len(nodes)):
        if nodes[at].high - nodes[at].low > 1:
            merged += 1
    var total = count + merged
    var centers = List[Float32](length=total * 3, fill=0)
    var covariances = List[Float32](length=total * 6, fill=0)
    var colors = List[UInt8](length=total * 4, fill=0)
    for place in range(count):
        var index = order[place]
        for n in range(3):  # pragma: no branch
            centers[place * 3 + n] = geometry.centers[index * 3 + n]
        for n in range(6):  # pragma: no branch
            covariances[place * 6 + n] = geometry.covariances[index * 6 + n]
        for n in range(4):  # pragma: no branch
            colors[place * 4 + n] = geometry.colors[index * 4 + n]
    var degree = geometry.spherical_harmonics_degree()
    var g = create_gaussian_splat_geometry(
        centers^,
        covariances^,
        colors^,
        _gather_band(geometry.sh1, order, 1, degree, total),
        _gather_band(geometry.sh2, order, 2, degree, total),
        _gather_band(geometry.sh3, order, 3, degree, total),
    )
    # The merged splats go level by level, and in tree order in a level,
    # so that the merged splats a view selects at one level are near each
    # other in memory.
    var levels = List[List[Int]]()
    var stack = List[Tuple[Int, Int]]()
    if count > 0:
        stack.append((0, 0))
    while len(stack) > 0:
        var top = stack.pop()
        var at = top[0]
        var depth = top[1]
        while len(levels) <= depth:
            levels.append(List[Int]())
        levels[depth].append(at)
        ref here = nodes[at]
        for child in range(
            here.first_child + here.children - 1, here.first_child - 1, -1
        ):  # pragma: no branch
            stack.append((child, depth + 1))
    var slot = count
    for depth in range(len(levels)):
        for at in levels[depth]:  # pragma: no branch
            var current = nodes[at]
            _merge(g, current, slot)
            if current.merged == slot:
                slot += 1
            nodes[at] = current
    return SplatLod(GaussianSplat(g^, node), nodes^, order.copy())


comptime _SKIP = 0
"""`_decide`: the node is wholly behind the camera or past a side."""
comptime _MERGED = 1
"""`_decide`: the node draws as its merged splat."""
comptime _LEAF = 2
"""`_decide`: the node is a leaf that draws its own splats."""
comptime _DESCEND = 3
"""`_decide`: the node's children decide."""
comptime _FRONTIER = 16
"""How many subtrees a selection worker takes, about: enough to share an
uneven tree out evenly."""


@fieldwise_init
struct _Selector(ImplicitlyCopyable):
    """What deciding a node needs of the view."""

    var view: Matrix4
    """The view matrix times the object's world matrix."""
    var focal: Float32
    """Pixels a unit of size at a unit of depth."""
    var px: Float32
    """The projection's x scale."""
    var py: Float32
    """Its y scale."""
    var side_x: Float32
    """The length of the normal of a left or a right side of the view."""
    var side_y: Float32
    """The length of the normal of a top or a bottom side."""
    var pixels: Float32
    """See `select_splats`."""

    def decide(self, node: SplatLodNode) -> Int:
        """Return what the view does with a node.

        Args:
            node: The node.

        Returns:
            `_SKIP`, `_MERGED`, `_LEAF` or `_DESCEND`.
        """
        ref m = self.view.elements
        var c = node.center
        var r = node.radius
        var vx = m[0] * c.x + m[4] * c.y + m[8] * c.z + m[12]
        var vy = m[1] * c.x + m[5] * c.y + m[9] * c.z + m[13]
        var depth = -(m[2] * c.x + m[6] * c.y + m[10] * c.z + m[14])
        # Wholly behind the camera, or past a side of the view.
        if (
            depth < -r
            or abs(vx) * self.px - CLIP_XY * depth > r * self.side_x
            or abs(vy) * self.py - CLIP_XY * depth > r * self.side_y
        ):
            return _SKIP
        if depth > r and r * self.focal <= self.pixels * depth:
            return _MERGED
        if node.children == 0:
            return _LEAF
        return _DESCEND


def _select_from(
    mut found: List[Int],
    lod: SplatLod,
    selector: _Selector,
    frontier: List[Int],
    first: Int,
    past: Int,
):
    """Select the splats of a run of subtrees, depth first.

    Args:
        found: Where the selected splats go, in tree order.
        lod: The tree.
        selector: The view.
        frontier: The subtrees' roots, in tree order.
        first: The run's first subtree.
        past: One past its last.
    """
    var stack = List[Int]()
    for at in range(first, past):  # pragma: no branch
        stack.append(frontier[at])
        while len(stack) > 0:
            var node = lod.nodes[stack.pop()]
            var decision = selector.decide(node)
            if decision == _MERGED:
                found.append(node.merged)
            elif decision == _LEAF:
                for index in range(node.low, node.high):  # pragma: no branch
                    found.append(index)
            elif decision == _DESCEND:
                # Pushed last to first, so that the first child comes first.
                for child in range(
                    node.first_child + node.children - 1,
                    node.first_child - 1,
                    -1,
                ):  # pragma: no branch
                    stack.append(child)


async def _select_task(
    found: MutPointer[List[Int], MutAnyOrigin],
    lod: Pointer[SplatLod, ImmutAnyOrigin],
    selector: _Selector,
    frontier: MutPointer[List[Int], MutAnyOrigin],
    first: Int,
    past: Int,
):
    """`_select_from` as a task of `select_splats`.

    Args:
        found: The run's own list.
        lod: The tree.
        selector: The view.
        frontier: The subtrees' roots.
        first: The run's first subtree.
        past: One past its last.
    """
    _select_from(found[], lod[], selector, frontier[], first, past)


def select_splats(
    lod: SplatLod,
    model_view: Matrix4,
    projection: Matrix4,
    height: Int,
    pixels: Float32,
    workers: Int = 1,
) -> List[Int]:
    """Return the splats that a view draws; see the module docstring.

    The workers share out subtrees: the tree is opened, level by level,
    into about `_FRONTIER` subtrees a worker, and the subtrees' splats are
    joined in tree order. So the selection is the same for any count.

    Args:
        lod: The tree.
        model_view: The view matrix times the object's world matrix.
        projection: The camera's projection.
        height: The camera rectangle's height in pixels.
        pixels: How many pixels a node's sphere covers, at most, for the
            node to draw as its merged splat. 0 draws every splat.
        workers: How many threads walk the tree.

    Returns:
        The splats of `lod.splat` to draw, in tree order.
    """
    var out = List[Int]()
    if len(lod.nodes) == 0:
        return out^
    ref p = projection.elements
    var px = abs(p[0])
    var py = abs(p[5])
    var selector = _Selector(
        model_view,
        Float32(height) * 0.5 * py,
        px,
        py,
        sqrt(px * px + CLIP_XY * CLIP_XY),
        sqrt(py * py + CLIP_XY * CLIP_XY),
        pixels,
    )
    # Open the tree into subtrees, in tree order, while a level opens one.
    var frontier: List[Int] = [0]
    var opened = True
    while opened and len(frontier) < workers * _FRONTIER:
        opened = False
        var next = List[Int]()
        for node in frontier:  # pragma: no branch
            ref here = lod.nodes[node]
            if selector.decide(here) == _DESCEND:
                opened = True
                for child in range(
                    here.first_child, here.first_child + here.children
                ):  # pragma: no branch
                    next.append(child)
            else:
                next.append(node)
        frontier = next^
    var runs = max(1, min(workers, len(frontier)))
    if runs == 1:
        _select_from(out, lod, selector, frontier, 0, len(frontier))
        return out^
    var found = List[List[Int]]()
    for _ in range(runs):  # pragma: no branch
        found.append(List[Int]())
    var group = TaskGroup()
    for run in range(runs):  # pragma: no branch
        group.create_task(
            _select_task(
                found.unsafe_ptr()
                .unsafe_offset(run)
                .unsafe_origin_cast[MutAnyOrigin](),
                Pointer(to=lod).unsafe_origin_cast[ImmutAnyOrigin](),
                selector,
                Pointer(to=frontier).unsafe_origin_cast[MutAnyOrigin](),
                run * len(frontier) // runs,
                (run + 1) * len(frontier) // runs,
            )
        )
    group.wait()
    # The tasks read the tree and the frontier through pointers the
    # compiler cannot see. These reads keep them alive until every task has
    # finished.
    _ = len(lod.nodes)
    _ = len(frontier)
    var total = 0
    for run in range(runs):  # pragma: no branch
        total += len(found[run])
    out.reserve(total)
    for run in range(runs):  # pragma: no branch
        out.extend(Span(found[run]))
    return out^


@fieldwise_init
struct _LodView(ImplicitlyCopyable):
    """What shading, projecting and binning the selected splats needs."""

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
    var near: Float64
    """The nearest view depth of the bins."""
    var scale: Float64
    """Bins a unit of view depth."""


def _project_selected(
    projected: MutPointer[ProjectedSplat, MutAnyOrigin],
    bins: MutPointer[Int32, MutAnyOrigin],
    counts: MutPointer[Int, MutAnyOrigin],
    splat: GaussianSplat,
    selected: MutPointer[Int, MutAnyOrigin],
    view: _LodView,
    first: Int,
    past: Int,
):
    """Shade, project and bin a run of the selected splats.

    Args:
        projected: Each selected splat on the screen.
        bins: Each selected splat's bin, furthest first, or -1 off the
            screen.
        counts: The run's count of each bin.
        splat: The tree's splats.
        selected: The selected splats.
        view: The view.
        first: The run's first place in the selection.
        past: One past its last.
    """
    ref g = splat.splat_geometry
    ref m = view.place.model_view.elements
    # The selected splats are the tree's, so their arrays are read
    # unchecked.
    var colors = g.colors.unsafe_ptr()
    var centers = g.centers.unsafe_ptr()
    for place in range(first, past):
        var index = selected[unsafe_offset=place]
        var color = FloatRgba(
            Float32(colors[unsafe_offset=index * 4]) / 255,
            Float32(colors[unsafe_offset=index * 4 + 1]) / 255,
            Float32(colors[unsafe_offset=index * 4 + 2]) / 255,
            Float32(colors[unsafe_offset=index * 4 + 3]) / 255,
        )
        if view.degree > 0:
            var shading = splat.spherical_harmonics_color(
                index, view.eye, view.degree
            )
            color.r += shading.x
            color.g += shading.y
            color.b += shading.z
        var center = Vector3(
            centers[unsafe_offset=index * 3],
            centers[unsafe_offset=index * 3 + 1],
            centers[unsafe_offset=index * 3 + 2],
        )
        var found = project_splat(
            center, g.covariances, index * 6, color, view.place
        )
        bins[unsafe_offset=place] = -1
        if Bool(found):
            var placed = found.value()
            placed.x += view.left
            placed.y += view.top
            projected[unsafe_offset=place] = placed
            var depth = -(
                Float64(m[2]) * Float64(center.x)
                + Float64(m[6]) * Float64(center.y)
                + Float64(m[10]) * Float64(center.z)
                + Float64(m[14])
            )
            var bin = (
                BIN_COUNT
                - 1
                - Int(
                    min(
                        Float64(BIN_COUNT - 1),
                        max(
                            Float64(0), floor((depth - view.near) * view.scale)
                        ),
                    )
                )
            )
            bins[unsafe_offset=place] = Int32(bin)
            counts[unsafe_offset=bin] += 1


async def _project_task(
    projected: MutPointer[ProjectedSplat, MutAnyOrigin],
    bins: MutPointer[Int32, MutAnyOrigin],
    counts: MutPointer[Int, MutAnyOrigin],
    splat: MutPointer[GaussianSplat, MutAnyOrigin],
    selected: MutPointer[Int, MutAnyOrigin],
    view: MutPointer[_LodView, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """`_project_selected` as a task of `prepare_splat_lod`.

    Args:
        projected: Each selected splat on the screen.
        bins: Each selected splat's bin.
        counts: The run's counts.
        splat: The tree's splats.
        selected: The selected splats.
        view: The view.
        first: The run's first place in the selection.
        past: One past its last.
    """
    _project_selected(
        projected, bins, counts, splat[], selected, view[], first, past
    )


def _place_selected(
    drawn: MutPointer[ProjectedSplat, MutAnyOrigin],
    projected: MutPointer[ProjectedSplat, MutAnyOrigin],
    bins: MutPointer[Int32, MutAnyOrigin],
    next: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Put a run of the selected splats in draw order, each at its bin's
    next place.

    Args:
        drawn: The splats in draw order.
        projected: Each selected splat on the screen.
        bins: Each selected splat's bin, or -1.
        next: The run's next place in each bin.
        first: The run's first place in the selection.
        past: One past its last.
    """
    for place in range(first, past):
        var bin = Int(bins[unsafe_offset=place])
        if bin < 0:
            continue
        drawn[unsafe_offset=next[unsafe_offset=bin]] = projected[
            unsafe_offset=place
        ]
        next[unsafe_offset=bin] += 1


async def _place_task(
    drawn: MutPointer[ProjectedSplat, MutAnyOrigin],
    projected: MutPointer[ProjectedSplat, MutAnyOrigin],
    bins: MutPointer[Int32, MutAnyOrigin],
    next: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """`_place_selected` as a task of `prepare_splat_lod`.

    Args:
        drawn: The splats in draw order.
        projected: Each selected splat on the screen.
        bins: Each selected splat's bin.
        next: The run's next places.
        first: The run's first place in the selection.
        past: One past its last.
    """
    _place_selected(drawn, projected, bins, next, first, past)


def prepare_splat_lod[
    C: Camera
](
    scene: Scene,
    mut lod: SplatLod,
    camera: C,
    width: Int,
    height: Int,
    depth_mode: DepthMode,
    viewport: Optional[Rect] = None,
    workers: Int = 1,
    pixels: Float32 = LOD_PIXELS,
) raises -> List[ProjectedSplat]:
    """Select, shade, project and sort a tree's splats for a view.

    Parameters:
        C: The camera's type.

    Args:
        scene: The scene, updated, that holds the tree's node.
        lod: The tree.
        camera: The camera to project through.
        width: The target's width in pixels.
        height: The target's height in pixels.
        depth_mode: How the target stores depth.
        viewport: The camera rectangle, or the whole target.
        workers: How many threads project and sort.
        pixels: See `select_splats`.

    Returns:
        The splats on the screen, furthest first. None when the node is
        hidden or on no layer the camera draws.

    Raises:
        Error: If the depth mode or the viewport is not valid, the node is
            not in the scene, the scene is stale, or a matrix cannot be
            inverted.
    """
    require_splat_depth(depth_mode)
    var rect = viewport.value() if Bool(viewport) else Rect.whole(width, height)
    require_valid(rect.is_valid(), "A Gaussian splat needs a valid viewport")
    var out = List[ProjectedSplat]()
    if not scene.shows(lod.splat.node, camera.visible_layers()):
        return out^
    var world = scene.world_matrix(lod.splat.node)
    var view = camera.view_matrix_in(scene)
    var model_view = view * world
    var projection = camera.projection_matrix()
    var selected = select_splats(
        lod, model_view, projection, rect.height, pixels, workers
    )
    var camera_world = view
    camera_world.invert()
    var local = world
    local.invert()
    var eye = local.transform_point(
        camera_world.transform_point(Vector3(0, 0, 0))
    )
    # The bins span the root's sphere, as the object's sort spans its
    # bounding sphere.
    var near = Float64(camera.near_distance())
    var far = near + MIN_SORT_RANGE
    if len(lod.nodes) > 0:
        ref m = model_view.elements
        var c = lod.nodes[0].center
        var depth = -Float64(m[2] * c.x + m[6] * c.y + m[10] * c.z + m[14])
        near = max(near, depth - Float64(lod.nodes[0].radius))
        far = max(near + MIN_SORT_RANGE, depth + Float64(lod.nodes[0].radius))
    var lod_view = _LodView(
        SplatView(
            model_view,
            projection,
            rect.width,
            rect.height,
            depth_mode,
            log_depth_factor(camera.far_distance()),
        ),
        eye,
        lod.splat.splat_geometry.spherical_harmonics_degree(),
        Float32(rect.x),
        Float32(rect.top(height)),
        near,
        Float64(BIN_COUNT - 1) / (far - near),
    )
    var count = len(selected)
    var runs = max(1, min(workers, count // LOD_RUN))
    var projected = List[ProjectedSplat](capacity=count)
    projected.resize(unsafe_uninit_length=count)
    var bins = List[Int32](length=count, fill=-1)
    var counts = List[Int](length=runs * BIN_COUNT, fill=0)
    var projected_at = projected.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    var bin_at = bins.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    var count_at = counts.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    var selected_at = selected.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    if runs == 1:
        _project_selected(
            projected_at,
            bin_at,
            count_at,
            lod.splat,
            selected_at,
            lod_view,
            0,
            count,
        )
    else:
        var group = TaskGroup()
        for run in range(runs):  # pragma: no branch
            group.create_task(
                _project_task(
                    projected_at,
                    bin_at,
                    count_at.unsafe_offset(run * BIN_COUNT),
                    Pointer(to=lod.splat).unsafe_origin_cast[MutAnyOrigin](),
                    selected_at,
                    Pointer(to=lod_view).unsafe_origin_cast[MutAnyOrigin](),
                    run * count // runs,
                    (run + 1) * count // runs,
                )
            )
        group.wait()
    # Each run's first place in each bin: bin by bin, run by run.
    var sum = 0
    for bin in range(BIN_COUNT):  # pragma: no branch
        for run in range(runs):  # pragma: no branch
            var here = counts[run * BIN_COUNT + bin]
            counts[run * BIN_COUNT + bin] = sum
            sum += here
    out.resize(unsafe_uninit_length=sum)
    var out_at = out.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()
    if runs == 1:
        _place_selected(out_at, projected_at, bin_at, count_at, 0, count)
    else:
        var placing = TaskGroup()
        for run in range(runs):  # pragma: no branch
            placing.create_task(
                _place_task(
                    out_at,
                    projected_at,
                    bin_at,
                    count_at.unsafe_offset(run * BIN_COUNT),
                    run * count // runs,
                    (run + 1) * count // runs,
                )
            )
        placing.wait()
    # The tasks reach the lists, the splats and the view through pointers
    # the compiler cannot see. These reads keep them alive until every
    # task has finished.
    _ = len(projected)
    _ = len(bins)
    _ = len(counts)
    _ = len(selected)
    _ = lod.splat.count()
    _ = lod_view.degree
    return out^


def draw_splat_lod[
    C: Camera
](
    mut target: RenderTarget,
    scene: Scene,
    mut lod: SplatLod,
    camera: C,
    viewport: Optional[Rect] = None,
    workers: Int = 1,
    pixels: Float32 = LOD_PIXELS,
) raises:
    """Draw a tree's splats into a target on the CPU.

    Parameters:
        C: The camera's type.

    Args:
        target: The target, drawn into already or cleared. Its depth hides
            the splats behind it.
        scene: The scene, updated, that holds the tree's node.
        lod: The tree.
        camera: The camera to project through.
        viewport: The camera rectangle, or the whole target.
        workers: How many threads draw.
        pixels: See `select_splats`.

    Raises:
        Error: Everything `prepare_splat_lod` raises.
    """
    var splats = prepare_splat_lod(
        scene,
        lod,
        camera,
        target.width,
        target.height,
        target.depth_mode,
        viewport,
        workers,
        pixels,
    )
    rasterize_splats(target, splats, workers)
