# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An octree of triangles, from three.js `examples/jsm/math/Octree.js`.

An octree cuts space into eight boxes, and each box that holds too many
triangles into eight more. A game builds one from its level once. Then it
asks which triangles a player's capsule, a ball or a ray can touch, and it
tests only those. `capsule_intersect` and `sphere_intersect` give the push
that moves a collider out of the level. `ray_intersect` gives the nearest
triangle a ray meets.

A leaf holds up to `triangles_per_leaf` triangles, eight by default, unless
it is `max_level` levels down, sixteen by default. A triangle that crosses
a cut goes into every box it touches, and a query gives it once.

**Storage.** three.js makes each box an `Octree` of its own. Here the boxes
are nodes in one list, and each holds the indices of its triangles in
`triangles`, which keeps every triangle added, in order. Node 0 is the
root. The order of every search and of every push is three.js's, so a
collision gives three.js's answer.

Like `Box3`, an octree holds bare `Float32` meters.

**Differences from three.js.**

- `from_graph_node` reads the plain meshes of a scene, `Scene.meshes`.
  three.js also reads the geometry of a skinned mesh in its bind pose, and
  of an instanced mesh once, where its instances are not.
- `triangles_per_leaf` and `max_level` hold at every level. three.js reads
  them only on the root: each box below is a new `Octree` with the
  defaults.
- A triangle edge of no length meets nothing. three.js calculates `NaN` for
  it, which meets nothing too.
"""

from core.assets import Assets
from core.layers import Layers
from core.object3d import NodeId
from core.scene import Scene
from math.bounds import Box3, Sphere
from math.capsule import Capsule
from math.ray import Ray
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import inf, max, min, sqrt

# three.js's `EPS`: below this, two segments are parallel.
comptime _PARALLEL = Float32(1e-10)


def _sat_axis(
    axis: Vector3, v0: Vector3, v1: Vector3, v2: Vector3, extents: Vector3
) -> Bool:
    """Return whether an axis does not separate a triangle from a box at the
    origin. One step of three.js's `satForAxes`.

    Args:
        axis: The axis.
        v0: A corner, relative to the box's center.
        v1: A corner.
        v2: A corner.
        extents: The box's half size.

    Returns:
        Whether the two overlap along the axis.
    """
    var r = (
        extents.x * abs(axis.x)
        + extents.y * abs(axis.y)
        + extents.z * abs(axis.z)
    )
    var p0 = v0.dot(axis)
    var p1 = v1.dot(axis)
    var p2 = v2.dot(axis)
    return not (max(-max(p0, max(p1, p2)), min(p0, min(p1, p2))) > r)


def box_intersects_triangle(box: Box3, triangle: Triangle) -> Bool:
    """Return whether a triangle meets a box. three.js:
    `Box3.intersectsTriangle`.

    The separating axis test of Akenine-Moller: the nine cross products of
    the box's axes with the triangle's edges, the three axes of the box, and
    the triangle's normal.

    Args:
        box: The box.
        triangle: The triangle.

    Returns:
        Whether no axis separates them. False for an empty box.
    """
    if box.is_empty():
        return False
    var center = box.center()
    var extents = box.max - center
    var v0 = triangle.a - center
    var v1 = triangle.b - center
    var v2 = triangle.c - center
    var f0 = v1 - v0
    var f1 = v2 - v1
    var f2 = v0 - v2
    var normal = f0
    normal.cross(f1)
    return (
        _sat_axis(Vector3(0, -f0.z, f0.y), v0, v1, v2, extents)
        and _sat_axis(Vector3(0, -f1.z, f1.y), v0, v1, v2, extents)
        and _sat_axis(Vector3(0, -f2.z, f2.y), v0, v1, v2, extents)
        and _sat_axis(Vector3(f0.z, 0, -f0.x), v0, v1, v2, extents)
        and _sat_axis(Vector3(f1.z, 0, -f1.x), v0, v1, v2, extents)
        and _sat_axis(Vector3(f2.z, 0, -f2.x), v0, v1, v2, extents)
        and _sat_axis(Vector3(-f0.y, f0.x, 0), v0, v1, v2, extents)
        and _sat_axis(Vector3(-f1.y, f1.x, 0), v0, v1, v2, extents)
        and _sat_axis(Vector3(-f2.y, f2.x, 0), v0, v1, v2, extents)
        and _sat_axis(Vector3(1, 0, 0), v0, v1, v2, extents)
        and _sat_axis(Vector3(0, 1, 0), v0, v1, v2, extents)
        and _sat_axis(Vector3(0, 0, 1), v0, v1, v2, extents)
        and _sat_axis(normal, v0, v1, v2, extents)
    )


def _normalized(vector: Vector3) -> Vector3:
    """Return a vector made unit length, or the zero vector unchanged.

    Args:
        vector: The vector.

    Returns:
        The unit vector.
    """
    var out = vector
    out.normalize()
    return out


def _gap_sq(a: Vector3, b: Vector3) -> Float32:
    """Return the square of the distance between two points.

    Args:
        a: One point.
        b: The other.

    Returns:
        The squared distance.
    """
    var d = a - b
    return d.dot(d)


def _unit(value: Float32) -> Float32:
    """Return a number limited to the range from zero to one.

    Args:
        value: The number.

    Returns:
        The limited number.
    """
    return max(Float32(0), min(Float32(1), value))


@fieldwise_init
struct _TrianglePlane(ImplicitlyCopyable):
    """The plane of a triangle, as three.js's `Triangle.getPlane` gives it.

    A degenerate triangle gets a zero normal and a zero constant, where
    `Triangle.plane` refuses it. three.js keeps it, and a collision reads
    its edges.
    """

    var normal: Vector3
    var constant: Float32

    @staticmethod
    def of(triangle: Triangle) -> _TrianglePlane:
        """Return the plane of a triangle.

        Args:
            triangle: The triangle.

        Returns:
            Its plane.
        """
        var normal = _normalized(triangle.raw_normal())
        return _TrianglePlane(normal, -normal.dot(triangle.a))

    def distance_to_point(self, point: Vector3) -> Float32:
        """Return the signed distance of a point.

        Args:
            point: The point.

        Returns:
            The distance, positive in front.
        """
        return self.normal.dot(point) + self.constant

    def project_point(self, point: Vector3) -> Vector3:
        """Return the point of the plane nearest a point.

        Args:
            point: The point.

        Returns:
            The projected point.
        """
        return point + self.normal * (-self.distance_to_point(point))


def _contains_point(triangle: Triangle, point: Vector3) -> Bool:
    """Return whether a point, projected onto a triangle's plane, is in the
    triangle. three.js: `Triangle.containsPoint`.

    Args:
        triangle: The triangle.
        point: The point.

    Returns:
        Whether it is inside or on an edge. False for a degenerate
        triangle and for a point that is not a number.
    """
    var v0 = triangle.c - triangle.a
    var v1 = triangle.b - triangle.a
    var v2 = point - triangle.a
    var dot00 = v0.dot(v0)
    var dot01 = v0.dot(v1)
    var dot02 = v0.dot(v2)
    var dot11 = v1.dot(v1)
    var dot12 = v1.dot(v2)
    var denom = dot00 * dot11 - dot01 * dot01
    var inverse = 1 / denom
    var u = (dot11 * dot02 - dot01 * dot12) * inverse
    var v = (dot00 * dot12 - dot01 * dot02) * inverse
    var x = 1 - u - v
    return denom != 0 and x >= 0 and v >= 0 and x + v <= 1


def _closest_on_segment(
    start: Vector3, end: Vector3, point: Vector3
) -> Optional[Vector3]:
    """Return the point of a segment nearest a point. three.js:
    `Line3.closestPointToPoint` with `clamp` set.

    Args:
        start: The segment's start.
        end: The segment's end.
        point: The point.

    Returns:
        The nearest point, or None for a segment of no length.
    """
    var start_end = end - start
    var length_sq = start_end.dot(start_end)
    if length_sq == 0:
        return None
    var t = _unit(start_end.dot(point - start) / length_sq)
    return start_end * t + start


def line_to_line_closest_points(
    start1: Vector3, end1: Vector3, start2: Vector3, end2: Vector3
) -> Optional[Tuple[Vector3, Vector3]]:
    """Return the nearest points of two segments. three.js's
    `lineToLineClosestPoints`.

    Args:
        start1: The first segment's start.
        end1: The first segment's end.
        start2: The second segment's start.
        end2: The second segment's end.

    Returns:
        The point of the first segment and the point of the second, or None
        if the second has no length.
    """
    var r = end1 - start1
    var s = end2 - start2
    var w = start2 - start1
    var a = r.dot(s)
    var b = r.dot(r)
    var c = s.dot(s)
    var d = s.dot(w)
    var e = r.dot(w)
    if c == 0:
        return None
    var t1: Float32
    var t2: Float32
    var divisor = b * c - a * a
    if abs(divisor) < _PARALLEL:
        var d1 = -d / c
        var d2 = (a - d) / c
        if abs(d1 - 0.5) < abs(d2 - 0.5):
            t1 = 0
            t2 = d1
        else:
            t1 = 1
            t2 = d2
    else:
        t1 = (d * a + e * c) / divisor
        t2 = (t1 * a - d) / c
    t2 = _unit(t2)
    t1 = _unit(t1)
    return (r * t1 + start1, s * t2 + start2)


@fieldwise_init
struct Contact(ImplicitlyCopyable):
    """Where a collider meets one triangle, and how deep."""

    # The way to push the collider out, unit length.
    var normal: Vector3
    # The point of the triangle that is met.
    var point: Vector3
    # How far to push, in meters.
    var depth: Float32


@fieldwise_init
struct Collision(ImplicitlyCopyable):
    """The push that moves a collider out of every triangle it meets."""

    # The way to push, unit length.
    var normal: Vector3
    # How far to push, in meters.
    var depth: Float32


@fieldwise_init
struct OctreeRayHit(ImplicitlyCopyable):
    """The nearest triangle a ray meets."""

    # How far along the ray, in meters.
    var distance: Float32
    # Which triangle, as its index in `Octree.triangles`.
    var index: Int
    # The triangle.
    var triangle: Triangle
    # Where the ray meets it.
    var position: Vector3


def triangle_capsule_intersect(
    capsule: Capsule, triangle: Triangle
) -> Optional[Contact]:
    """Return where a capsule meets a triangle, or None. three.js:
    `Octree.triangleCapsuleIntersect`.

    The segment is first met with the triangle's plane. If that point is in
    the triangle, the push is along the normal. If not, the nearest points
    of the segment and each edge are compared with the radius.

    Args:
        capsule: The capsule.
        triangle: The triangle.

    Returns:
        The contact, or None.
    """
    var plane = _TrianglePlane.of(triangle)
    var d1 = plane.distance_to_point(capsule.start) - capsule.radius
    var d2 = plane.distance_to_point(capsule.end) - capsule.radius
    var above = d1 > 0 and d2 > 0
    var below = d1 < -capsule.radius and d2 < -capsule.radius
    if above or below:
        return None
    var delta = abs(d1 / (abs(d1) + abs(d2)))
    var crossing = capsule.start + (capsule.end - capsule.start) * delta
    if _contains_point(triangle, crossing):
        return Contact(plane.normal, crossing, abs(min(d1, d2)))
    var r2 = capsule.radius * capsule.radius
    var corners: List[Vector3] = [triangle.a, triangle.b, triangle.c]
    for edge in range(3):  # pragma: no branch
        var points = line_to_line_closest_points(
            capsule.start,
            capsule.end,
            corners[edge],
            corners[(edge + 1) % 3],
        )
        if not Bool(points):
            continue
        var point1 = points.value()[0]
        var point2 = points.value()[1]
        if _gap_sq(point1, point2) < r2:
            return Contact(
                _normalized(point1 - point2),
                point2,
                capsule.radius - sqrt(_gap_sq(point1, point2)),
            )
    return None


def triangle_sphere_intersect(
    sphere: Sphere, triangle: Triangle
) -> Optional[Contact]:
    """Return where a sphere meets a triangle, or None. three.js:
    `Octree.triangleSphereIntersect`.

    Args:
        sphere: The sphere.
        triangle: The triangle.

    Returns:
        The contact, or None. None for an empty sphere.
    """
    var plane = _TrianglePlane.of(triangle)
    var reach = abs(plane.distance_to_point(sphere.center))
    if not (reach <= sphere.radius):
        return None
    var depth = abs(plane.distance_to_point(sphere.center) - sphere.radius)
    var r2 = sphere.radius * sphere.radius - depth * depth
    var plain_point = plane.project_point(sphere.center)
    if _contains_point(triangle, sphere.center):
        return Contact(plane.normal, plain_point, depth)
    var corners: List[Vector3] = [triangle.a, triangle.b, triangle.c]
    for edge in range(3):  # pragma: no branch
        var nearest = _closest_on_segment(
            corners[edge], corners[(edge + 1) % 3], plain_point
        )
        if not Bool(nearest):
            continue
        var d = _gap_sq(nearest.value(), sphere.center)
        if d < r2:
            return Contact(
                _normalized(sphere.center - nearest.value()),
                nearest.value(),
                sphere.radius - sqrt(d),
            )
    return None


@fieldwise_init
struct _OctreeNode(Copyable, Movable):
    """One box of the tree: three.js's `Octree` below the root."""

    var box: Box3
    # The triangles of a leaf, as indices into `Octree.triangles`.
    var triangles: List[Int]
    # The boxes below, as indices into `Octree._nodes`.
    var sub_trees: List[Int]


struct Octree(Movable):
    """Triangles sorted into nested boxes. three.js: `Octree`."""

    # The box around every triangle, with a margin. None until built.
    var box: Optional[Box3]
    # The box around every triangle, with no margin.
    var bounds: Box3
    # Which layers `from_graph_node` reads.
    var layers: Layers
    # How many triangles a box holds before it is split.
    var triangles_per_leaf: Int
    # How deep the boxes can nest.
    var max_level: Int
    # Every triangle added, in order.
    var triangles: List[Triangle]
    var _nodes: List[_OctreeNode]

    def __init__(out self):
        """Create an empty octree, as three.js's constructor does."""
        self.box = None
        self.bounds = Box3.empty()
        self.layers = Layers()
        self.triangles_per_leaf = 8
        self.max_level = 16
        self.triangles = List[Triangle]()
        self._nodes = List[_OctreeNode]()
        self._nodes.append(_OctreeNode(Box3.empty(), List[Int](), List[Int]()))

    def node_count(self) -> Int:
        """Return how many boxes hold triangles or boxes, the root included.

        Returns:
            The count.
        """
        var count = 1
        var pending: List[Int] = [0]
        while len(pending) > 0:
            var node = pending.pop()
            for child in self._nodes[node].sub_trees:
                count += 1
                pending.append(child)
        return count

    def boxes(self) -> List[Box3]:
        """Return the box of every node below the root, in the order
        three.js's `OctreeHelper` walks `subTrees`: each box, then the
        boxes below it, depth first.

        Returns:
            The boxes. None for a tree that is not built or holds no
            triangle.
        """
        var found = List[Box3]()
        # The boxes still to visit, the next one last.
        var pending = List[Int]()
        for index in range(len(self._nodes[0].sub_trees) - 1, -1, -1):
            pending.append(self._nodes[0].sub_trees[index])
        while len(pending) > 0:
            var node = pending.pop()
            found.append(self._nodes[node].box)
            ref below = self._nodes[node].sub_trees
            for index in range(len(below) - 1, -1, -1):
                pending.append(below[index])
        return found^

    def add_triangle(mut self, triangle: Triangle):
        """Add a triangle and grow the bounds around it. three.js:
        `addTriangle`.

        Args:
            triangle: The triangle.
        """
        self.bounds.min = Vector3(
            min(
                self.bounds.min.x,
                min(triangle.a.x, min(triangle.b.x, triangle.c.x)),
            ),
            min(
                self.bounds.min.y,
                min(triangle.a.y, min(triangle.b.y, triangle.c.y)),
            ),
            min(
                self.bounds.min.z,
                min(triangle.a.z, min(triangle.b.z, triangle.c.z)),
            ),
        )
        self.bounds.max = Vector3(
            max(
                self.bounds.max.x,
                max(triangle.a.x, max(triangle.b.x, triangle.c.x)),
            ),
            max(
                self.bounds.max.y,
                max(triangle.a.y, max(triangle.b.y, triangle.c.y)),
            ),
            max(
                self.bounds.max.z,
                max(triangle.a.z, max(triangle.b.z, triangle.c.z)),
            ),
        )
        self._nodes[0].triangles.append(len(self.triangles))
        self.triangles.append(triangle)

    def calc_box(mut self):
        """Set the box from the bounds. three.js: `calcBox`.

        The smallest corner moves out by a centimeter on each axis, so that
        a level on a regular grid does not lie on the cuts.
        """
        var box = self.bounds
        box.min.x -= 0.01
        box.min.y -= 0.01
        box.min.z -= 0.01
        self.box = box
        self._nodes[0].box = box

    def _split(mut self, node: Int, level: Int):
        """Cut a box into eight and sort its triangles into them. three.js:
        `split`.

        Args:
            node: The box.
            level: How deep it is.
        """
        var box = self._nodes[node].box
        var halfsize = (box.max - box.min) * 0.5
        var subs = List[Int]()
        for x in range(2):  # pragma: no branch
            for y in range(2):  # pragma: no branch
                for z in range(2):  # pragma: no branch
                    var low = box.min + Vector3(
                        Float32(x) * halfsize.x,
                        Float32(y) * halfsize.y,
                        Float32(z) * halfsize.z,
                    )
                    subs.append(len(self._nodes))
                    self._nodes.append(
                        _OctreeNode(
                            Box3(low, low + halfsize), List[Int](), List[Int]()
                        )
                    )
        # From the last, as three.js pops them.
        while len(self._nodes[node].triangles) > 0:
            var index = self._nodes[node].triangles.pop()
            # Eight boxes, always.
            for sub in subs:  # pragma: no branch
                if box_intersects_triangle(
                    self._nodes[sub].box, self.triangles[index]
                ):
                    self._nodes[sub].triangles.append(index)
        for sub in subs:  # pragma: no branch
            var count = len(self._nodes[sub].triangles)
            if count > self.triangles_per_leaf and level < self.max_level:
                self._split(sub, level + 1)
            if count != 0:
                self._nodes[node].sub_trees.append(sub)

    def build(mut self):
        """Build the tree from the triangles added. three.js: `build`."""
        self.calc_box()
        self._split(0, 0)

    def _collect(self, node: Int, mut found: List[Int], mut seen: List[Bool]):
        """Add the triangles of a leaf that are not found yet.

        Args:
            node: The leaf.
            found: The triangles, as indices, in the order found.
            seen: Which triangles are in `found` already.
        """
        # Called only for a box that holds triangles.
        for index in self._nodes[node].triangles:  # pragma: no branch
            if not seen[index]:
                seen[index] = True
                found.append(index)

    def _ray_gather(
        self, node: Int, ray: Ray, mut found: List[Int], mut seen: List[Bool]
    ):
        """Collect the triangles below a box that a ray can meet.

        Args:
            node: The box to search below.
            ray: The ray.
            found: The triangles, as indices, in the order found.
            seen: Which triangles are in `found` already.
        """
        for sub in self._nodes[node].sub_trees:
            if not ray.intersects_box(self._nodes[sub].box):
                continue
            if len(self._nodes[sub].triangles) > 0:
                self._collect(sub, found, seen)
            else:
                self._ray_gather(sub, ray, found, seen)

    def _sphere_gather(
        self,
        node: Int,
        sphere: Sphere,
        mut found: List[Int],
        mut seen: List[Bool],
    ):
        """Collect the triangles below a box that a sphere can meet.

        Args:
            node: The box to search below.
            sphere: The sphere.
            found: The triangles, as indices, in the order found.
            seen: Which triangles are in `found` already.
        """
        for sub in self._nodes[node].sub_trees:
            if not sphere.intersects_box(self._nodes[sub].box):
                continue
            if len(self._nodes[sub].triangles) > 0:
                self._collect(sub, found, seen)
            else:
                self._sphere_gather(sub, sphere, found, seen)

    def _capsule_gather(
        self,
        node: Int,
        capsule: Capsule,
        mut found: List[Int],
        mut seen: List[Bool],
    ):
        """Collect the triangles below a box that a capsule can meet.

        Args:
            node: The box to search below.
            capsule: The capsule.
            found: The triangles, as indices, in the order found.
            seen: Which triangles are in `found` already.
        """
        for sub in self._nodes[node].sub_trees:
            if not capsule.intersects_box(self._nodes[sub].box):
                continue
            if len(self._nodes[sub].triangles) > 0:
                self._collect(sub, found, seen)
            else:
                self._capsule_gather(sub, capsule, found, seen)

    def ray_triangles(self, ray: Ray) -> List[Int]:
        """Return the triangles a ray can meet. three.js: `getRayTriangles`.

        Args:
            ray: The ray.

        Returns:
            Indices into `triangles`, each once, in three.js's order.
        """
        var found = List[Int]()
        var seen = List[Bool](length=len(self.triangles), fill=False)
        self._ray_gather(0, ray, found, seen)
        return found^

    def sphere_triangles(self, sphere: Sphere) -> List[Int]:
        """Return the triangles a sphere can meet. three.js:
        `getSphereTriangles`.

        Args:
            sphere: The sphere.

        Returns:
            Indices into `triangles`, each once, in three.js's order.
        """
        var found = List[Int]()
        var seen = List[Bool](length=len(self.triangles), fill=False)
        self._sphere_gather(0, sphere, found, seen)
        return found^

    def capsule_triangles(self, capsule: Capsule) -> List[Int]:
        """Return the triangles a capsule can meet. three.js:
        `getCapsuleTriangles`.

        Args:
            capsule: The capsule.

        Returns:
            Indices into `triangles`, each once, in three.js's order.
        """
        var found = List[Int]()
        var seen = List[Bool](length=len(self.triangles), fill=False)
        self._capsule_gather(0, capsule, found, seen)
        return found^

    def sphere_intersect(self, sphere: Sphere) -> Optional[Collision]:
        """Return the push that moves a sphere out of the level, or None.
        three.js: `sphereIntersect`.

        The sphere is pushed out of each triangle it meets in turn. The
        answer is the total push.

        Args:
            sphere: The sphere.

        Returns:
            The push, or None if the sphere meets no triangle.
        """
        var moved = sphere
        var hit = False
        for index in self.sphere_triangles(sphere):
            var contact = triangle_sphere_intersect(
                moved, self.triangles[index]
            )
            if Bool(contact):
                hit = True
                moved.center.add(contact.value().normal * contact.value().depth)
        if not hit:
            return None
        var push = moved.center - sphere.center
        return Collision(_normalized(push), push.length())

    def capsule_intersect(self, capsule: Capsule) -> Optional[Collision]:
        """Return the push that moves a capsule out of the level, or None.
        three.js: `capsuleIntersect`.

        Args:
            capsule: The capsule.

        Returns:
            The push, or None if the capsule meets no triangle.
        """
        var moved = capsule
        var hit = False
        for index in self.capsule_triangles(moved):
            var contact = triangle_capsule_intersect(
                moved, self.triangles[index]
            )
            if Bool(contact):
                hit = True
                moved.translate(contact.value().normal * contact.value().depth)
        if not hit:
            return None
        var push = moved.center() - capsule.center()
        return Collision(_normalized(push), push.length())

    def ray_intersect(self, ray: Ray) -> Optional[OctreeRayHit]:
        """Return the nearest triangle a ray meets from its front, or None.
        three.js: `rayIntersect`.

        Args:
            ray: The ray.

        Returns:
            The nearest hit, or None.
        """
        var best: Optional[OctreeRayHit] = None
        var distance = inf[DType.float32]()
        for index in self.ray_triangles(ray):
            ref triangle = self.triangles[index]
            var met = ray.intersect_triangle(
                triangle.a, triangle.b, triangle.c, True
            )
            if not Bool(met):
                continue
            var offset = met.value() - ray.origin
            var along = offset.length()
            if distance > along:
                distance = along
                best = OctreeRayHit(along, index, triangle, offset + ray.origin)
        return best

    def from_graph_node(
        mut self, mut scene: Scene, assets: Assets, node: NodeId
    ) raises:
        """Add the triangles of every mesh at and below a node, in world
        space, and build. three.js: `fromGraphNode`.

        The scene is updated first, as three.js updates the world matrices.
        A mesh counts if its node shares a layer with `layers`, visible or
        not.

        Args:
            scene: The scene.
            assets: The geometry the meshes name.
            node: Where to start.

        Raises:
            Error: If the node is not in the scene, the scene cannot update,
                or a mesh names a geometry that is not there or has no
                positions.
        """
        scene.update()
        # The node itself is always the first.
        for visited in scene.descendants(node):  # pragma: no branch
            var layers = scene.get(visited).layers
            if not self.layers.test(layers):
                continue
            var world = scene.world_matrix(visited)
            for mesh in scene.meshes:
                if mesh.node != visited:
                    continue
                ref geometry = assets.geometries.get(mesh.geometry)
                for triangle in range(geometry.triangle_count()):
                    self.add_triangle(
                        Triangle(
                            world.transform_point(geometry.corner(triangle, 0)),
                            world.transform_point(geometry.corner(triangle, 1)),
                            world.transform_point(geometry.corner(triangle, 2)),
                        )
                    )
        self.build()

    def clear(mut self):
        """Empty the tree. three.js: `clear`."""
        self.box = None
        self.bounds = Box3.empty()
        self.triangles = List[Triangle]()
        self._nodes = List[_OctreeNode]()
        self._nodes.append(_OctreeNode(Box3.empty(), List[Int](), List[Int]()))
