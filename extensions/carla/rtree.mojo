# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's R-trees, `PointCloudRtree` and `SegmentCloudRtree`, from
`LibCarla/source/carla/geom/Rtree.h`.

CARLA wraps Boost.Geometry's R-tree with the linear split and at most 16
entries a node. The map keeps its lane segments in one to find the
nearest waypoint, with a filter on the lane type, and to find the
segments in a junction's box. This port is an R-tree of its own with the
same split and node size and CARLA's query surface: the k nearest
entries to a point, with or without a filter, and the segments that meet
a box. ThreeMojo's `math.octree.Octree` holds triangles for collision and
has no nearest-k query, so it does not serve here. The boxes are
`math.bounds.Box3`.

An entry carries one whole number (a segment two), the caller's own
data, such as an index into a list of waypoints. CARLA carries any type
there. A filter is a struct with an `accepts` method, as CARLA's is a
lambda.

**Order of results.** Boost leaves the order of a query's results open.
This port gives the nearest first, and entries at the same distance in
the order they were inserted. `intersections` gives entries in the order
they were inserted.

A query point has three coordinates. For CARLA's one- and
two-dimensional trees, set the unused coordinates to zero: the distances
come out the same.

**Finite-coordinate correction (#589).** Segment distance retains small
endpoint gaps and uses the same arithmetic after endpoint reversal. Slab
queries widen before subtraction and compare uncertain parameter intervals
with exact-sign expansions. These fix the former finite-extreme misses and
false hits. Distances remain Float64 estimates, with a box-key floor that
keeps nearest-query node bounds conservative. This correction does not change
CARLA's segment construction or the insertion-order tie rule.
"""

from math.bounds import Box3
from math.vector3 import Vector3
from math.segment import _difference_determinant, _point_segment_distance2

# Boost's `linear<16>`: at most 16 entries a node, at least 30 percent.
comptime _MAX_ENTRIES = 16
comptime _MIN_ENTRIES = 4


@fieldwise_init
struct PointElement(ImplicitlyCopyable):
    """A point and its value, CARLA's `PointCloudRtree::TreeElement`."""

    var point: Vector3
    # The caller's data.
    var value: Int


@fieldwise_init
struct SegmentElement(ImplicitlyCopyable):
    """A segment and one value for each end, CARLA's
    `SegmentCloudRtree::TreeElement`."""

    var start: Vector3
    var end: Vector3
    # The caller's data for the start and for the end.
    var start_value: Int
    var end_value: Int


trait PointFilter:
    """A test that a nearest-neighbor query applies to each candidate."""

    def accepts(self, element: PointElement) -> Bool:
        """Return True to keep the candidate.

        Args:
            element: The candidate.

        Returns:
            Whether the query may return it.
        """
        ...


trait SegmentFilter:
    """A test that a nearest-neighbor query applies to each candidate."""

    def accepts(self, element: SegmentElement) -> Bool:
        """Return True to keep the candidate.

        Args:
            element: The candidate.

        Returns:
            Whether the query may return it.
        """
        ...


# --- the tree --------------------------------------------------------------


def _volume(box: Box3) -> Float64:
    var size = box.max - box.min
    return Float64(size.x) * Float64(size.y) * Float64(size.z)


def _joined(a: Box3, b: Box3) -> Box3:
    var out = a
    out.union(b)
    return out


def _gap(low: Float32, high: Float32, p: Float32) -> Float64:
    if p < low:
        return Float64(low) - Float64(p)
    if p > high:
        return Float64(p) - Float64(high)
    return 0.0


@no_inline
def _box_distance2(box: Box3, p: Vector3) -> Float64:
    # One compiled boundary gives node and endpoint-box keys the same
    # operation graph, including any permitted multiply-add contraction.
    var dx = _gap(box.min.x, box.max.x, p.x)
    var dy = _gap(box.min.y, box.max.y, p.y)
    var dz = _gap(box.min.z, box.max.z, p.z)
    return dx * dx + dy * dy + dz * dz


def _segment_distance2(a: Vector3, b: Vector3, p: Vector3) -> Float64:
    """A wide segment distance with a monotone index lower-bound floor."""
    var box = Box3(
        Vector3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)),
        Vector3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)),
    )
    # Rounding can put an interior distance a few ulps below its box key.
    # Gap, square and sum are monotone, so every containing node's key is
    # no greater than this floor. Nodes still precede entries at equal keys.
    return max(_point_segment_distance2(a, b, p), _box_distance2(box, p))


@fieldwise_init
struct _SegmentParameter(ImplicitlyCopyable):
    """(face-start)/(end-start), with a positive denominator."""

    var face: Float64
    var start: Float64
    var end: Float64


def _parameter_before(a: _SegmentParameter, b: _SegmentParameter) -> Bool:
    var left = (a.face - a.start) * (b.end - b.start)
    var right = (b.face - b.start) * (a.end - a.start)
    var difference = left - right
    # Four rounded differences, products and a subtraction: 16u bounds
    # the absolute error relative to the sum of computed product magnitudes.
    var guard = 1.7763568394002505e-15 * (abs(left) + abs(right))
    if abs(difference) > guard:
        return difference < 0
    return (
        _difference_determinant(
            a.face,
            a.start,
            b.end,
            b.start,
            b.face,
            b.start,
            a.end,
            a.start,
        )
        < 0
    )


def _axis_clip(
    a: Float64,
    b: Float64,
    low: Float64,
    high: Float64,
    mut near: _SegmentParameter,
    mut far: _SegmentParameter,
) -> Bool:
    """Clip one slab without dividing or rounding the retained endpoints."""
    var first = min(a, b)
    var last = max(a, b)
    if last < low or first > high:
        return False
    # These comparisons also skip parallel axes and infinite outer faces.
    if first >= low and last <= high:
        return True
    var lo = _SegmentParameter(0, 0, 1)
    var hi = _SegmentParameter(1, 0, 1)
    if a < b:
        if low > a:
            lo = _SegmentParameter(low, a, b)
        if high < b:
            hi = _SegmentParameter(high, a, b)
    else:
        if high < a:
            lo = _SegmentParameter(-high, -a, -b)
        if low > b:
            hi = _SegmentParameter(-low, -a, -b)
    if _parameter_before(near, lo):
        near = lo
    if _parameter_before(hi, far):
        far = hi
    return not _parameter_before(far, near)


def segment_intersects_box(start: Vector3, end: Vector3, box: Box3) -> Bool:
    """Return whether a finite segment meets an axis-aligned box.

    Args:
        start: One finite end of the segment.
        end: The other finite end.
        box: The box. Its faces count as inside.

    Returns:
        Whether any point of the segment is in the box. An empty box
        meets nothing. Infinite outer faces need no clipping.

    Raises:
        None.
    """
    if box.is_empty():
        return False
    var near = _SegmentParameter(0, 0, 1)
    var far = _SegmentParameter(1, 0, 1)
    return (
        _axis_clip(
            Float64(start.x),
            Float64(end.x),
            Float64(box.min.x),
            Float64(box.max.x),
            near,
            far,
        )
        and _axis_clip(
            Float64(start.y),
            Float64(end.y),
            Float64(box.min.y),
            Float64(box.max.y),
            near,
            far,
        )
        and _axis_clip(
            Float64(start.z),
            Float64(end.z),
            Float64(box.min.z),
            Float64(box.max.z),
            near,
            far,
        )
    )


@fieldwise_init
struct _Node(Copyable, Movable):
    var leaf: Bool
    var box: Box3
    # Child nodes, or entries for a leaf.
    var children: List[Int]


@fieldwise_init
struct _Candidate(ImplicitlyCopyable):
    var distance2: Float64
    # Zero for a node, one for an entry, so a node goes first at a tie.
    var kind: Int
    var index: Int

    def before(self, other: Self) -> Bool:
        if self.distance2 != other.distance2:
            return self.distance2 < other.distance2
        if self.kind != other.kind:
            return self.kind < other.kind
        return self.index < other.index


struct _Heap(Movable):
    var items: List[_Candidate]

    def __init__(out self):
        self.items = List[_Candidate]()

    def push(mut self, item: _Candidate):
        self.items.append(item)
        var i = len(self.items) - 1
        while i > 0:
            var parent = (i - 1) // 2
            if not self.items[i].before(self.items[parent]):
                break
            self.items.swap_elements(i, parent)
            i = parent

    def pop(mut self) -> _Candidate:
        var top = self.items[0]
        var last = self.items.pop()
        if len(self.items) > 0:
            self.items[0] = last
            var i = 0
            while True:
                var best = i
                for child in [2 * i + 1, 2 * i + 2]:  # pragma: no branch
                    if child < len(self.items) and self.items[child].before(
                        self.items[best]
                    ):
                        best = child
                if best == i:
                    break
                self.items.swap_elements(i, best)
                i = best
        return top


trait _EntryFilter:
    def accepts_entry(self, tree: _Rtree, entry: Int) -> Bool:
        ...


@fieldwise_init
struct _AcceptAll(ImplicitlyCopyable, _EntryFilter):
    def accepts_entry(self, tree: _Rtree, entry: Int) -> Bool:
        return True


@fieldwise_init
struct _PointAdapter[F: PointFilter & ImplicitlyCopyable & Deinitable](
    ImplicitlyCopyable, _EntryFilter
):
    var inner: Self.F

    def accepts_entry(self, tree: _Rtree, entry: Int) -> Bool:
        return self.inner.accepts(
            PointElement(tree.starts[entry], tree.start_values[entry])
        )


@fieldwise_init
struct _SegmentAdapter[F: SegmentFilter & ImplicitlyCopyable & Deinitable](
    ImplicitlyCopyable, _EntryFilter
):
    var inner: Self.F

    def accepts_entry(self, tree: _Rtree, entry: Int) -> Bool:
        return self.inner.accepts(tree.segment(entry))


struct _Rtree(Movable):
    """The shared tree: every entry is a segment, and a point is a segment
    of no length."""

    var starts: List[Vector3]
    var ends: List[Vector3]
    var start_values: List[Int]
    var end_values: List[Int]
    var nodes: List[_Node]
    var root: Int

    def __init__(out self):
        self.starts = List[Vector3]()
        self.ends = List[Vector3]()
        self.start_values = List[Int]()
        self.end_values = List[Int]()
        self.nodes = List[_Node]()
        self.nodes.append(_Node(True, Box3.empty(), List[Int]()))
        self.root = 0

    def size(self) -> Int:
        return len(self.starts)

    def segment(self, entry: Int) -> SegmentElement:
        return SegmentElement(
            self.starts[entry],
            self.ends[entry],
            self.start_values[entry],
            self.end_values[entry],
        )

    def _entry_box(self, entry: Int) -> Box3:
        var box = Box3.empty()
        box.expand_by_point(self.starts[entry])
        box.expand_by_point(self.ends[entry])
        return box

    def _child_box(self, node: Int, child: Int) -> Box3:
        if self.nodes[node].leaf:
            return self._entry_box(child)
        return self.nodes[child].box

    def _refit(mut self, node: Int):
        var box = Box3.empty()
        for child in self.nodes[node].children:  # pragma: no branch
            box.union(self._child_box(node, child))
        self.nodes[node].box = box

    def insert(
        mut self, start: Vector3, end: Vector3, start_value: Int, end_value: Int
    ):
        self.starts.append(start)
        self.ends.append(end)
        self.start_values.append(start_value)
        self.end_values.append(end_value)
        var entry = len(self.starts) - 1
        var box = self._entry_box(entry)
        # Guttman's ChooseLeaf: the child that grows least, then the
        # smallest.
        var path = List[Int]()
        var node = self.root
        while not self.nodes[node].leaf:
            path.append(node)
            var best = -1
            var best_growth = 0.0
            var best_volume = 0.0
            for child in self.nodes[node].children:  # pragma: no branch
                var volume = _volume(self.nodes[child].box)
                var growth = (
                    _volume(_joined(self.nodes[child].box, box)) - volume
                )
                if (
                    best < 0
                    or growth < best_growth
                    or (growth == best_growth and volume < best_volume)
                ):
                    best = child
                    best_growth = growth
                    best_volume = volume
            node = best
        self.nodes[node].children.append(entry)
        self.nodes[node].box.union(box)
        var split = -1
        if len(self.nodes[node].children) > _MAX_ENTRIES:
            split = self._split(node)
        while len(path) > 0:
            var parent = path.pop()
            if split >= 0:
                self.nodes[parent].children.append(split)
                split = -1
            self._refit(parent)
            if len(self.nodes[parent].children) > _MAX_ENTRIES:
                split = self._split(parent)
        if split >= 0:
            var children = List[Int]()
            children.append(self.root)
            children.append(split)
            self.nodes.append(_Node(False, Box3.empty(), children^))
            self.root = len(self.nodes) - 1
            self._refit(self.root)

    def _split(mut self, node: Int) -> Int:
        """Guttman's linear split: move part of a full node to a new one.
        Return the new node."""
        var children = self.nodes[node].children.copy()
        var boxes = List[Box3]()
        var whole = Box3.empty()
        for child in children:  # pragma: no branch
            var b = self._child_box(node, child)
            boxes.append(b)
            whole.union(b)
        # LinearPickSeeds: the pair with the greatest normalized separation.
        var seed_a = 0
        var seed_b = 1
        var best = -1.0
        for axis in range(3):  # pragma: no branch
            var highest_low = 0
            var lowest_high = 0
            for i in range(len(boxes)):  # pragma: no branch
                if _lo(boxes[i], axis) > _lo(boxes[highest_low], axis):
                    highest_low = i
                if _hi(boxes[i], axis) < _hi(boxes[lowest_high], axis):
                    lowest_high = i
            var width = Float64(_hi(whole, axis)) - Float64(_lo(whole, axis))
            var separation = Float64(_lo(boxes[highest_low], axis)) - Float64(
                _hi(boxes[lowest_high], axis)
            )
            if width > 0.0:
                separation /= width
            if highest_low != lowest_high and separation > best:
                best = separation
                seed_a = lowest_high
                seed_b = highest_low
        var group_a = List[Int]()
        var group_b = List[Int]()
        group_a.append(seed_a)
        group_b.append(seed_b)
        var box_a = boxes[seed_a]
        var box_b = boxes[seed_b]
        var left = len(boxes) - 2
        for i in range(len(boxes)):  # pragma: no branch
            if i == seed_a or i == seed_b:
                continue
            var to_a: Bool
            if len(group_a) + left <= _MIN_ENTRIES:
                to_a = True
            elif len(group_b) + left <= _MIN_ENTRIES:
                to_a = False
            else:
                var grow_a = _volume(_joined(box_a, boxes[i])) - _volume(box_a)
                var grow_b = _volume(_joined(box_b, boxes[i])) - _volume(box_b)
                if grow_a != grow_b:
                    to_a = grow_a < grow_b
                elif _volume(box_a) != _volume(box_b):
                    to_a = _volume(box_a) < _volume(box_b)
                else:
                    to_a = len(group_a) <= len(group_b)
            if to_a:
                group_a.append(i)
                box_a.union(boxes[i])
            else:
                group_b.append(i)
                box_b.union(boxes[i])
            left -= 1
        var kept = List[Int]()
        for i in group_a:  # pragma: no branch
            kept.append(children[i])
        var moved = List[Int]()
        for i in group_b:  # pragma: no branch
            moved.append(children[i])
        self.nodes[node].children = kept^
        self.nodes[node].box = box_a
        self.nodes.append(_Node(self.nodes[node].leaf, box_b, moved^))
        return len(self.nodes) - 1

    def nearest[
        F: _EntryFilter
    ](self, point: Vector3, count: Int, filter: F) raises -> List[Int]:
        if count < 0:
            raise Error(
                "A nearest-neighbor query needs a count of zero or more"
            )
        var found = List[Int]()
        if count == 0 or self.size() == 0:
            return found^
        var heap = _Heap()
        heap.push(
            _Candidate(
                _box_distance2(self.nodes[self.root].box, point), 0, self.root
            )
        )
        while len(heap.items) > 0 and len(found) < count:
            var item = heap.pop()
            if item.kind == 1:
                if filter.accepts_entry(self, item.index):
                    found.append(item.index)
                continue
            ref node = self.nodes[item.index]
            for child in node.children:  # pragma: no branch
                if node.leaf:
                    heap.push(
                        _Candidate(
                            _segment_distance2(
                                self.starts[child], self.ends[child], point
                            ),
                            1,
                            child,
                        )
                    )
                else:
                    heap.push(
                        _Candidate(
                            _box_distance2(self.nodes[child].box, point),
                            0,
                            child,
                        )
                    )
        return found^

    def intersections(self, box: Box3) -> List[Int]:
        var found = List[Int]()
        var stack = List[Int]()
        stack.append(self.root)
        while len(stack) > 0:
            var index = stack.pop()
            ref node = self.nodes[index]
            if not node.box.intersects_box(box):
                continue
            for child in node.children:  # pragma: no branch
                if not node.leaf:
                    stack.append(child)
                elif segment_intersects_box(
                    self.starts[child], self.ends[child], box
                ):
                    found.append(child)
        sort(found)
        return found^


def _lo(box: Box3, axis: Int) -> Float32:
    if axis == 0:
        return box.min.x
    if axis == 1:
        return box.min.y
    return box.min.z


def _hi(box: Box3, axis: Int) -> Float32:
    if axis == 0:
        return box.max.x
    if axis == 1:
        return box.max.y
    return box.max.z


# --- the public trees ------------------------------------------------------


struct PointCloudRtree(Movable):
    """An R-tree of points, CARLA's `PointCloudRtree`."""

    var _tree: _Rtree

    def __init__(out self):
        """Create an empty tree."""
        self._tree = _Rtree()

    def insert_element(mut self, point: Vector3, value: Int):
        """Add a point, `InsertElement(point, element)`.

        Args:
            point: The point.
            value: The caller's data for it.
        """
        self._tree.insert(point, point, value, value)

    def insert_element(mut self, element: PointElement):
        """Add a point, `InsertElement(element)`.

        Args:
            element: The point and its value.
        """
        self.insert_element(element.point, element.value)

    def insert_elements(mut self, elements: List[PointElement]):
        """Add many points, `InsertElements`.

        Args:
            elements: The points and their values, added in order.
        """
        for element in elements:
            self.insert_element(element)

    def _elements(self, entries: List[Int]) -> List[PointElement]:
        var out = List[PointElement]()
        for entry in entries:
            out.append(
                PointElement(
                    self._tree.starts[entry], self._tree.start_values[entry]
                )
            )
        return out^

    def get_nearest_neighbours(
        self, point: Vector3, number_neighbours: Int = 1
    ) raises -> List[PointElement]:
        """Return the points nearest a point, `GetNearestNeighbours`.

        Args:
            point: The query point.
            number_neighbours: How many to return at most.

        Returns:
            Up to that many points, the nearest first.

        Raises:
            Error: If the count is negative.
        """
        return self._elements(
            self._tree.nearest(point, number_neighbours, _AcceptAll())
        )

    def get_nearest_neighbours_with_filter[
        F: PointFilter & ImplicitlyCopyable & Deinitable
    ](
        self, point: Vector3, filter: F, number_neighbours: Int = 1
    ) raises -> List[PointElement]:
        """Return the accepted points nearest a point,
        `GetNearestNeighboursWithFilter`.

        Args:
            point: The query point.
            filter: The test each candidate must pass.
            number_neighbours: How many to return at most.

        Returns:
            Up to that many accepted points, the nearest first.

        Raises:
            Error: If the count is negative.
        """
        return self._elements(
            self._tree.nearest(point, number_neighbours, _PointAdapter(filter))
        )

    def get_tree_size(self) -> Int:
        """Return how many points the tree holds, `GetTreeSize`.

        Returns:
            The count.
        """
        return self._tree.size()


struct SegmentCloudRtree(Movable):
    """An R-tree of segments, CARLA's `SegmentCloudRtree`."""

    var _tree: _Rtree

    def __init__(out self):
        """Create an empty tree."""
        self._tree = _Rtree()

    def insert_element(
        mut self, start: Vector3, end: Vector3, start_value: Int, end_value: Int
    ):
        """Add a segment, `InsertElement(segment, start, end)`.

        Args:
            start: One end.
            end: The other end.
            start_value: The caller's data for the start.
            end_value: The caller's data for the end.
        """
        self._tree.insert(start, end, start_value, end_value)

    def insert_element(mut self, element: SegmentElement):
        """Add a segment, `InsertElement(element)`.

        Args:
            element: The segment and its values.
        """
        self.insert_element(
            element.start, element.end, element.start_value, element.end_value
        )

    def insert_elements(mut self, elements: List[SegmentElement]):
        """Add many segments, `InsertElements`.

        Args:
            elements: The segments and their values, added in order.
        """
        for element in elements:
            self.insert_element(element)

    def _elements(self, entries: List[Int]) -> List[SegmentElement]:
        var out = List[SegmentElement]()
        for entry in entries:
            out.append(self._tree.segment(entry))
        return out^

    def get_nearest_neighbours(
        self, point: Vector3, number_neighbours: Int = 1
    ) raises -> List[SegmentElement]:
        """Return the segments nearest a point, `GetNearestNeighbours`.

        Args:
            point: The query point.
            number_neighbours: How many to return at most.

        Returns:
            Up to that many segments, the nearest first. The distance is to
            the nearest point of the segment.

        Raises:
            Error: If the count is negative.
        """
        return self._elements(
            self._tree.nearest(point, number_neighbours, _AcceptAll())
        )

    def get_nearest_neighbours_with_filter[
        F: SegmentFilter & ImplicitlyCopyable & Deinitable
    ](
        self, point: Vector3, filter: F, number_neighbours: Int = 1
    ) raises -> List[SegmentElement]:
        """Return the accepted segments nearest a point,
        `GetNearestNeighboursWithFilter`.

        Args:
            point: The query point.
            filter: The test each candidate must pass.
            number_neighbours: How many to return at most.

        Returns:
            Up to that many accepted segments, the nearest first.

        Raises:
            Error: If the count is negative.
        """
        return self._elements(
            self._tree.nearest(
                point, number_neighbours, _SegmentAdapter(filter)
            )
        )

    def get_intersections(self, box: Box3) -> List[SegmentElement]:
        """Return the segments that meet a box, `GetIntersections`.

        Args:
            box: The box. Its faces count as inside.

        Returns:
            The segments, in the order they were inserted.
        """
        return self._elements(self._tree.intersections(box))

    def get_tree_size(self) -> Int:
        """Return how many segments the tree holds, `GetTreeSize`.

        Returns:
            The count.
        """
        return self._tree.size()
