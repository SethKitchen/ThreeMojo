# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A ray, from three.js `src/math/Ray.js`.

A point and a unit direction: the half-line that starts at the origin and
goes the direction's way forever. It is what a click is once it leaves the
screen, and what `core.raycaster` carries through a scene asking each mesh
whether it is hit. The questions a ray answers are the ones a picker asks:
where along it a sphere, a box, a plane or a triangle is met, and how far
a point is from it.

The constructor normalizes the direction and refuses a zero direction.
`at(t)` is `t` meters along the ray only for a unit direction, and segment
approach keeps that unit-direction contract. Sphere and point-distance
queries account for the stored direction's actual squared norm. Box
queries support finite nonzero directions without requiring a unit norm.
Changing the public direction does not extend every other method's
contract to arbitrary non-unit vectors. three.js leaves normalization to
the caller.

A hit is an `Optional`. A ray that misses has no point to give, and a
point picked to mean "none" would be a point somewhere. three.js returns
`null` for the same reason. `intersect_*` gives the point and
`intersects_*` gives only whether, because the second is cheaper and is
asked more often.

Every point in a hit is *forward* of the origin. A ray is a half-line: a
sphere behind the origin is not hit, and a plane behind it is not met,
even though the line through both would cross them. An origin inside a
sphere hits it where the ray leaves; an origin inside a box hits where the
ray leaves it too, as three.js's does.

Like `Vector3` and the bounds, a ray holds bare `Float32` meters. The
`Raycaster` is the edge where the units live.
"""

from math.bounds import Box3, Plane, Sphere
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import copysign, inf, max, min, nan, sqrt
from std.memory import bitcast
from std.sys.intrinsics import unlikely


@fieldwise_init
struct _SphereHit(ImplicitlyCopyable):
    """A private point result without Optional's cross-call byte packing."""

    var found: Bool
    var point: Vector3


@fieldwise_init
struct _LineApproach(ImplicitlyCopyable):
    """A point's projection onto a line, before Float32 narrowing."""

    var parameter: Float64
    var distance_sq: Float64
    var norm_sq: Float64
    # Perpendicular vector from the nearest line point to the query point.
    var offset_x: Float64
    var offset_y: Float64
    var offset_z: Float64


@fieldwise_init
struct _RayProducts(ImplicitlyCopyable):
    """Immutable ray-only products for one bounds or Gaussian traversal."""

    var dx: Float64
    var dy: Float64
    var dz: Float64
    var xy: Float64
    var xz: Float64
    var yz: Float64
    var norm_sq: Float64
    var regular: Bool


@fieldwise_init
struct _LineProducts(ImplicitlyCopyable):
    """Unnormalized wide dot and cross products for one point and ray."""

    var projection: Float64
    var norm_sq: Float64
    var cross_x: Float64
    var cross_y: Float64
    var cross_z: Float64


@always_inline
def _line_products[
    prepared: Bool = False
](
    origin: Vector3,
    direction: Vector3,
    point: Vector3,
    ray_products: _RayProducts = _RayProducts(0, 0, 0, 0, 0, 0, 0, False),
) -> _LineProducts:
    """Keep shared products unnormalized until a caller needs a distance."""
    var x = Float64(point.x) - Float64(origin.x)
    var y = Float64(point.y) - Float64(origin.y)
    var z = Float64(point.z) - Float64(origin.z)
    var dx = ray_products.dx if prepared else Float64(direction.x)
    var dy = ray_products.dy if prepared else Float64(direction.y)
    var dz = ray_products.dz if prepared else Float64(direction.z)
    var norm_sq = (
        ray_products.norm_sq if prepared else dx * dx + dy * dy + dz * dz
    )
    # Cross the points separately. Subtracting a small center from a distant
    # origin first can erase its perpendicular offset even in Float64.
    var cross_x = (Float64(point.y) * dz - Float64(point.z) * dy) - (
        ray_products.yz if prepared else Float64(origin.y) * dz
        - Float64(origin.z) * dy
    )
    var cross_y = (Float64(point.z) * dx - Float64(point.x) * dz) - (
        -ray_products.xz if prepared else Float64(origin.z) * dx
        - Float64(origin.x) * dz
    )
    var cross_z = (Float64(point.x) * dy - Float64(point.y) * dx) - (
        ray_products.xy if prepared else Float64(origin.x) * dy
        - Float64(origin.y) * dx
    )
    return _LineProducts(
        x * dx + y * dy + z * dz, norm_sq, cross_x, cross_y, cross_z
    )


@always_inline
def _line_approach[
    prepared: Bool = False
](
    origin: Vector3,
    direction: Vector3,
    point: Vector3,
    ray_products: _RayProducts = _RayProducts(0, 0, 0, 0, 0, 0, 0, False),
) -> _LineApproach:
    """Return the stable projection, squared gap and perpendicular gap.

    Float32 direction storage is not an exact unit norm. One shared inverse
    accounts for its actual norm without recomputing several divisions.
    """
    var products = _line_products[prepared](
        origin, direction, point, ray_products
    )
    var inverse = 1 / products.norm_sq
    var dx = Float64(direction.x)
    var dy = Float64(direction.y)
    var dz = Float64(direction.z)
    var cx = products.cross_x
    var cy = products.cross_y
    var cz = products.cross_z
    return _LineApproach(
        products.projection * inverse,
        (cx * cx + cy * cy + cz * cz) / products.norm_sq,
        products.norm_sq,
        (dy * cz - dz * cy) * inverse,
        (dz * cx - dx * cz) * inverse,
        (dx * cy - dy * cx) * inverse,
    )


@always_inline
def _distance_sq_ratio[
    prepared: Bool = False
](
    origin: Vector3,
    direction: Vector3,
    point: Vector3,
    ray_products: _RayProducts = _RayProducts(0, 0, 0, 0, 0, 0, 0, False),
) -> Tuple[Float64, Float64]:
    """Return a squared ray distance as a numerator and positive denominator.

    Finite Float32 inputs and a nonzero direction give a nonnegative
    numerator and a positive denominator. Nonzero values and their radius
    products are normal Float64 values. No exact unit norm is assumed.
    """
    var products = _line_products[prepared](
        origin, direction, point, ray_products
    )
    if products.projection < 0 and products.norm_sq < inf[DType.float64]():
        var x = Float64(point.x) - Float64(origin.x)
        var y = Float64(point.y) - Float64(origin.y)
        var z = Float64(point.z) - Float64(origin.z)
        return (x * x + y * y + z * z, 1)
    return (
        products.cross_x * products.cross_x
        + products.cross_y * products.cross_y
        + products.cross_z * products.cross_z,
        products.norm_sq,
    )


def _distance_sq_to_point(
    origin: Vector3, direction: Vector3, point: Vector3
) -> Float64:
    """Return a ray's squared point distance without narrowing the square."""
    var ratio = _distance_sq_ratio(origin, direction, point)
    return ratio[0] / ratio[1]


@no_inline
def _radius_boundary(
    ratio: Tuple[Float64, Float64], radius_sq: Float64
) -> Tuple[Bool, Bool]:
    """Keep the rare boundary division off the ordinary predicate path."""
    var distance = ratio[0] / ratio[1]
    return (distance <= radius_sq, distance > radius_sq)


@always_inline
def _radius_relation(
    ratio: Tuple[Float64, Float64], radius_sq: Float64
) -> Tuple[Bool, Bool]:
    """Return within/exceeds decisions, retaining division near a boundary.

    For positive normal operands, multiplication and division each round
    by at most u=2^-53. A 4u relative interval around the rounded product
    encloses both uncertainties. The caller supplies a distance ratio from
    `_distance_sq_ratio` and a squared Float32-derived radius. For finite inputs
    and a nonzero direction, nonzero operands and products stay normal in
    Float64. Outside the interval, both comparisons agree. Inside it,
    retain the divided comparison. This is not an arbitrary tuple API:
    general nonfinite numerator/denominator pairs need not be equivalent.
    """
    var product = radius_sq * ratio[1]
    # Four neighboring positive binary64 values enclose the 4u interval,
    # including an exponent boundary. Integer distance avoids more floating
    # arithmetic on the ordinary, well-separated path.
    var separation = (
        bitcast[DType.uint64](ratio[0])
        - bitcast[DType.uint64](product)
        + UInt64(4)
    )
    if separation > UInt64(8):
        return (ratio[0] <= product, ratio[0] > product)
    return _radius_boundary(ratio, radius_sq)


@fieldwise_init
struct _BoxEndpoint(ImplicitlyCopyable):
    """A slab parameter stored as widened face/origin values and a divisor."""

    var face: Float64
    var origin: Float64
    var direction: Float64
    var sign: Float64
    var axis: Int


@fieldwise_init
struct _BoxInterval(ImplicitlyCopyable):
    """The two active box faces bounding a ray's parameter interval."""

    var near: _BoxEndpoint
    var far: _BoxEndpoint


def _box_slab(
    origin: Float32, direction: Float32, low: Float32, high: Float32, axis: Int
) -> _BoxInterval:
    """Write a nonparallel slab with a positive parameter denominator."""
    if direction < 0:
        return _BoxInterval(
            _BoxEndpoint(
                -Float64(high), -Float64(origin), -Float64(direction), -1, axis
            ),
            _BoxEndpoint(
                -Float64(low), -Float64(origin), -Float64(direction), -1, axis
            ),
        )
    return _BoxInterval(
        _BoxEndpoint(
            Float64(low), Float64(origin), Float64(direction), 1, axis
        ),
        _BoxEndpoint(
            Float64(high), Float64(origin), Float64(direction), 1, axis
        ),
    )


def _endpoint_before(left: _BoxEndpoint, right: _BoxEndpoint) -> Bool:
    """Compare parameters by separate wide determinants, without division.

    Both divisors are positive. Keeping face and origin products separate
    retains a small box's interval at a distant ray origin.
    """
    return (left.face * right.direction - right.face * left.direction) < (
        left.origin * right.direction - right.origin * left.direction
    )


@always_inline
def _include_box_interval(mut left: _BoxInterval, right: _BoxInterval):
    """Select active faces after the shared hit predicate accepts the box."""
    if _endpoint_before(left.near, right.near):
        left.near = right.near
    if _endpoint_before(right.far, left.far):
        left.far = right.far


@always_inline
def _box_pairs[
    width: Int
](
    place: SIMD[DType.float64, width],
    di: SIMD[DType.float64, width],
    dj: SIMD[DType.float64, width],
    low_i: SIMD[DType.float64, width],
    high_i: SIMD[DType.float64, width],
    low_j: SIMD[DType.float64, width],
    high_j: SIMD[DType.float64, width],
) -> Bool:
    """Check one or several signed projected slab intervals.

    Finite Float32 endpoint-direction products are exact in Float64.
    Differences of those products can still round.
    """
    var low = (
        dj.lt(0).select(high_i, low_i) * dj
        - di.lt(0).select(low_j, high_j) * di
    )
    var high = (
        dj.lt(0).select(low_i, high_i) * dj
        - di.lt(0).select(high_j, low_j) * di
    )
    return not (place.lt(low) | place.gt(high)).reduce_or()


def _plane_coordinate(
    origin_axis: Float64,
    origin_other: Float64,
    direction_axis: Float64,
    direction_other: Float64,
    point_axis: Float64,
    point_other: Float64,
    inverse: Float64,
) -> Float64:
    """Evaluate another component of a ray's intersection with a face."""
    if direction_other == 0:
        return origin_other
    var reference = (
        point_other if abs(point_other) < inf[DType.float64]() else origin_other
    )
    var offset = (
        (reference * direction_axis - point_axis * direction_other)
        - (origin_other * direction_axis - origin_axis * direction_other)
    ) * inverse
    return reference - offset


@fieldwise_init
struct SegmentApproach(ImplicitlyCopyable):
    """Where a ray and a segment come nearest each other, and how near."""

    # The square of the gap between the two points below.
    var distance_sq: Float32
    # The nearest point of the ray.
    var on_ray: Vector3
    # The nearest point of the segment.
    var on_segment: Vector3


struct Ray(ImplicitlyCopyable):
    """A half-line: an origin and the unit direction it leaves in."""

    var origin: Vector3
    var direction: Vector3

    def __init__(out self, origin: Vector3, direction: Vector3) raises:
        """Create a ray, making the direction unit length.

        Args:
            origin: Where the ray starts.
            direction: Which way it goes; any length but zero.

        Raises:
            Error: If the direction has no length: no way to point, no ray.
        """
        if direction.length() == 0:
            raise Error("A ray needs a direction with some length")
        var unit = direction
        unit.normalize()
        self.origin = origin
        self.direction = unit

    def at(self, t: Float32) -> Vector3:
        """Return the point `t` meters along this ray, three.js's `at`.

        Args:
            t: How far from the origin. Negative is behind it, where no
                hit ever is but a caller can still ask.

        Returns:
            The point.
        """
        return self.origin + self.direction * t

    def look_at(mut self, target: Vector3) raises:
        """Point this ray at `target`, three.js's `lookAt`.

        Args:
            target: The point to aim at.

        Raises:
            Error: If the target is the origin itself, which is no
                direction.
        """
        var toward = target - self.origin
        if toward.length() == 0:
            raise Error("A ray cannot look at its own origin")
        toward.normalize()
        self.direction = toward

    def recast(mut self, t: Float32):
        """Move the origin `t` meters along the ray, three.js's `recast`:
        the same line, started later.

        Args:
            t: How far to move the origin.
        """
        self.origin = self.at(t)

    def closest_point_to_point(self, point: Vector3) -> Vector3:
        """Return the point of this ray nearest `point`, three.js's
        `closestPointToPoint`.

        The foot of the perpendicular from the point onto the line, unless
        it falls behind the origin, where the ray does not go: then the
        origin, which is the nearest the ray comes.

        Args:
            point: The point to approach.

        Returns:
            The nearest point on the ray.
        """
        var approach = _line_approach(self.origin, self.direction, point)
        if approach.parameter < 0:
            return self.origin
        return Vector3(
            Float32(Float64(point.x) - approach.offset_x),
            Float32(Float64(point.y) - approach.offset_y),
            Float32(Float64(point.z) - approach.offset_z),
        )

    def distance_sq_to_point(self, point: Vector3) -> Float32:
        """Return the squared distance from `point` to this ray, three.js's
        `distanceSqToPoint`.

        Args:
            point: The point to measure from.

        Returns:
            The square of the distance to the nearest point of the ray,
            narrowed to Float32. This return value can overflow or underflow;
            sphere queries keep the wider square internally.
        """
        return Float32(
            _distance_sq_to_point(self.origin, self.direction, point)
        )

    def distance_sq_to_segment(
        self, start: Vector3, end: Vector3
    ) -> SegmentApproach:
        """Return where this ray comes nearest a segment, three.js's
        `distanceSqToSegment`.

        three.js's arithmetic, from Eberly's ray-to-segment test: the
        segment is written as a center, a unit direction and a half
        length, and the pair of parameters that minimize the gap is found
        in whichever region of the parameter plane it lies. A segment
        parallel to the ray takes the end the ray runs toward.

        The squared gap is measured between the two nearest points. The
        expanded squared-distance formula loses small gaps at long range
        in Float32, and can report zero or a negative distance.

        Args:
            start: One end of the segment.
            end: The other end.

        Returns:
            The squared gap, the ray's nearest point and the segment's.
        """
        var center = (start + end) * 0.5
        var along = end - start
        along.normalize()
        var diff = self.origin - center
        var extent = (end - start).length() * 0.5
        var a01 = -self.direction.dot(along)
        var b0 = diff.dot(self.direction)
        var b1 = -diff.dot(along)
        var det = abs(1 - a01 * a01)
        var s0: Float32
        var s1: Float32
        if det > 0:
            s0 = a01 * b1 - b0
            s1 = a01 * b0 - b1
            var ext_det = extent * det
            if s0 >= 0:
                if s1 >= -ext_det:
                    if s1 <= ext_det:
                        # Both inside: the two lines' own nearest points.
                        var inv_det = 1 / det
                        s0 *= inv_det
                        s1 *= inv_det
                    else:
                        s1 = extent
                        s0 = max(Float32(0), -(a01 * s1 + b0))
                else:
                    s1 = -extent
                    s0 = max(Float32(0), -(a01 * s1 + b0))
            elif s1 <= -ext_det:
                s0 = max(Float32(0), -(-a01 * extent + b0))
                s1 = -extent if s0 > 0 else min(max(-extent, -b1), extent)
            elif s1 <= ext_det:
                s0 = 0
                s1 = min(max(-extent, -b1), extent)
            else:
                s0 = max(Float32(0), -(a01 * extent + b0))
                s1 = extent if s0 > 0 else min(max(-extent, -b1), extent)
        else:
            # Parallel: the end the ray runs toward.
            s1 = -extent if a01 > 0 else extent
            s0 = max(Float32(0), -(a01 * s1 + b0))
        var on_ray = self.at(s0)
        var on_segment = center + along * s1
        var gap = on_ray - on_segment
        return SegmentApproach(gap.dot(gap), on_ray, on_segment)

    def distance_to_point(self, point: Vector3) -> Float32:
        """Return how far `point` is from this ray, three.js's
        `distanceToPoint`.

        Args:
            point: The point to measure from.

        Returns:
            The distance to the nearest point of the ray.
        """
        return Float32(
            sqrt(_distance_sq_to_point(self.origin, self.direction, point))
        )

    @no_inline
    def _intersect_sphere_fallback(self, sphere: Sphere) -> _SphereHit:
        """Retain the full-range, center-relative sphere reconstruction."""
        if sphere.is_empty():
            return _SphereHit(False, Vector3(0, 0, 0))
        var approach = _line_approach(
            self.origin, self.direction, sphere.center
        )
        var foot = approach.parameter
        var drop_sq = approach.distance_sq
        var radius_sq = Float64(sphere.radius) * Float64(sphere.radius)
        if drop_sq > radius_sq:
            return _SphereHit(False, Vector3(0, 0, 0))
        var half = sqrt((radius_sq - drop_sq) / approach.norm_sq)
        var entering = foot - half
        var leaving = foot + half
        if leaving < 0:
            return _SphereHit(False, Vector3(0, 0, 0))
        var offset = -half
        if entering < 0:
            offset = half
        # Work from the center and the perpendicular gap. A distant origin
        # can make even a Float64 parameter round away a small radius.
        return _SphereHit(
            True,
            Vector3(
                Float32(
                    Float64(sphere.center.x)
                    - approach.offset_x
                    + Float64(self.direction.x) * offset
                ),
                Float32(
                    Float64(sphere.center.y)
                    - approach.offset_y
                    + Float64(self.direction.y) * offset
                ),
                Float32(
                    Float64(sphere.center.z)
                    - approach.offset_z
                    + Float64(self.direction.z) * offset
                ),
            ),
        )

    def intersect_sphere(self, sphere: Sphere) -> Optional[Vector3]:
        """Return where this ray first meets `sphere`, three.js's
        `intersectSphere`, or None if it misses.

        The center is dropped onto the ray. The drop's square, against the
        radius squared, says whether the line through the ray crosses the
        sphere at all, and the two crossings sit either side of the foot.
        The nearer crossing is the hit, unless it is behind the origin: an
        origin inside the sphere hits where the ray leaves it, and a sphere
        wholly behind the origin is not hit at all. An empty sphere is hit
        nowhere, rather than its negative radius squaring to a real one.

        Args:
            sphere: The sphere.

        Returns:
            The first point of the sphere the ray reaches, or None.
        """
        if unlikely(sphere.is_empty()):
            return None
        # The quadratic is filtered before it supplies a point. All nonzero
        # Float32-derived products stay normal in Float64, including the
        # fourth-degree discriminant. No coordinate magnitude is guessed.
        var origin = SIMD[DType.float32, 2](self.origin.x, self.origin.y).cast[
            DType.float64
        ]()
        var center = SIMD[DType.float32, 2](
            sphere.center.x, sphere.center.y
        ).cast[DType.float64]()
        var direction = SIMD[DType.float32, 2](
            self.direction.x, self.direction.y
        ).cast[DType.float64]()
        var toward = center - origin
        var oz = Float64(self.origin.z)
        var z = Float64(sphere.center.z) - oz
        var dz = Float64(self.direction.z)
        var norm_sq = (direction * direction).reduce_add() + dz * dz
        var projection = (toward * direction).reduce_add() + z * dz
        var distance_sq = (toward * toward).reduce_add() + z * z
        var radius_sq = Float64(sphere.radius) * Float64(sphere.radius)
        var outside = distance_sq - radius_sq
        var discriminant = projection * projection - norm_sq * outside
        # For u=2^-53, discriminant/scale errors are bounded by
        # 32u*[p^2+n*(q+r^2)]. The identity 2*(p^2+n*r^2) =
        # [p^2+n*(q+r^2)] + D makes this test conservative. Accepted hits
        # have |center-origin|/radius < 725. Their pre-narrowing coordinate
        # error is below 2^-28*radius + u*abs(exact_coordinate).
        var scale = projection * projection + norm_sq * radius_sq
        var guard = 0.0000019073486328125 * scale
        if discriminant < -guard:
            return None
        # q has at most gamma_5 relative error; r^2 is exact. Sixteen
        # neighboring binary64 values enclose the origin-side uncertainty.
        var boundary = (
            bitcast[DType.uint64](distance_sq)
            - bitcast[DType.uint64](radius_sq)
            + UInt64(16)
        )
        if unlikely(not discriminant > guard or boundary <= UInt64(32)):
            var precise = self._intersect_sphere_fallback(sphere)
            if not precise.found:
                return None
            return precise.point
        # The certified nonzero origin-side sign selects entry or exit.
        if (
            bitcast[DType.int64](projection) & ~bitcast[DType.int64](outside)
        ) < 0:
            return None
        var inverse = 1 / norm_sq
        var root = sqrt(discriminant)
        var step = projection - copysign(root, outside)
        var parameter = step * inverse
        var point = (origin + direction * parameter).cast[DType.float32]()
        return Vector3(point[0], point[1], Float32(oz + dz * parameter))

    @always_inline
    def intersects_sphere(self, sphere: Sphere) -> Bool:
        """Return True if this ray meets `sphere`, three.js's
        `intersectsSphere`. An empty sphere is met nowhere.

        Args:
            sphere: The sphere.

        Returns:
            Whether any point of the ray is inside or on it.
        """
        if sphere.is_empty():
            return False
        var ratio = _distance_sq_ratio(
            self.origin, self.direction, sphere.center
        )
        return _radius_relation(
            ratio, Float64(sphere.radius) * Float64(sphere.radius)
        )[0]

    def distance_to_plane(self, plane: Plane) -> Optional[Float32]:
        """Return how far along this ray `plane` is met, three.js's
        `distanceToPlane`, or None if it is not.

        A ray parallel to the plane meets it nowhere, unless it lies in it,
        where every point is on the plane and the distance is zero. A ray
        pointing away from the plane would meet it behind the origin, which
        is not on the ray.

        Args:
            plane: The plane.

        Returns:
            The distance from the origin to the plane along the ray, or
            None.
        """
        var toward = plane.normal.dot(self.direction)
        if toward == 0:
            if plane.distance_to_point(self.origin) == 0:
                return Float32(0)
            return None
        var t = -plane.distance_to_point(self.origin) / toward
        if t < 0:
            return None
        return t

    def intersect_plane(self, plane: Plane) -> Optional[Vector3]:
        """Return where this ray meets `plane`, three.js's
        `intersectPlane`, or None if it does not.

        Args:
            plane: The plane.

        Returns:
            The point, or None. A ray lying in the plane meets it at its
            origin.
        """
        var t = self.distance_to_plane(plane)
        if not Bool(t):
            return None
        return self.at(t.value())

    def intersects_plane(self, plane: Plane) -> Bool:
        """Return True if this ray meets `plane`, three.js's
        `intersectsPlane`: it starts on the plane, or it starts on one side
        and points toward the other.

        Args:
            plane: The plane.

        Returns:
            Whether the ray reaches the plane.
        """
        var height = plane.distance_to_point(self.origin)
        if height == 0:
            return True
        return plane.normal.dot(self.direction) * height < 0

    def _query_products(self) -> _RayProducts:
        """Prepare a snapshot of ray-only products for one traversal."""
        var ox = Float64(self.origin.x)
        var oy = Float64(self.origin.y)
        var oz = Float64(self.origin.z)
        var dx = Float64(self.direction.x)
        var dy = Float64(self.direction.y)
        var dz = Float64(self.direction.z)
        var magnitude = abs(dx) + abs(dy) + abs(dz)
        return _RayProducts(
            dx,
            dy,
            dz,
            ox * dy - oy * dx,
            ox * dz - oz * dx,
            oy * dz - oz * dy,
            dx * dx + dy * dy + dz * dz,
            magnitude > 0
            and magnitude + abs(ox + oy + oz) < inf[DType.float64](),
        )

    @always_inline
    def _box_decision[
        prepared: Bool = False, need_regular: Bool = True
    ](
        self,
        box: Box3,
        products: _RayProducts = _RayProducts(0, 0, 0, 0, 0, 0, 0, False),
    ) -> Tuple[Bool, Bool]:
        """Return a shared box decision and an optional regularity flag.

        Three intervals overlap exactly when every pair overlaps. Combined
        with each slab containing a forward point, this also intersects the
        half-line [0,infinity). No endpoint or division is needed for Bool.
        The second result is meaningful only when `need_regular` is True.
        Boolean hits need no regularity work: invalid rays already retain
        the existing True result. A rejection must check regularity first.
        """
        var o = SIMD[DType.float32, 4](
            self.origin.x, self.origin.y, self.origin.z, 0
        )
        var d = SIMD[DType.float32, 4](
            self.direction.x, self.direction.y, self.direction.z, 0
        )
        var lo = SIMD[DType.float32, 4](box.min.x, box.min.y, box.min.z, 0)
        var hi = SIMD[DType.float32, 4](box.max.x, box.max.y, box.max.z, 0)
        if not lo.le(hi).reduce_and():
            return (False, True)
        if ((o.lt(lo) & d.le(0)) | (o.gt(hi) & d.ge(0))).reduce_or():
            var regular = (
                products.regular if prepared else self._query_products().regular
            )
            return (not regular, regular)
        if prepared:
            var hit = (
                _box_pairs[1](
                    products.xy,
                    products.dx,
                    products.dy,
                    Float64(box.min.x),
                    Float64(box.max.x),
                    Float64(box.min.y),
                    Float64(box.max.y),
                )
                and _box_pairs[1](
                    products.xz,
                    products.dx,
                    products.dz,
                    Float64(box.min.x),
                    Float64(box.max.x),
                    Float64(box.min.z),
                    Float64(box.max.z),
                )
                and _box_pairs[1](
                    products.yz,
                    products.dy,
                    products.dz,
                    Float64(box.min.y),
                    Float64(box.max.y),
                    Float64(box.min.z),
                    Float64(box.max.z),
                )
            )
            return (hit or not products.regular, products.regular)
        var ow = o.cast[DType.float64]()
        var dw = d.cast[DType.float64]()
        var lw = lo.cast[DType.float64]()
        var hw = hi.cast[DType.float64]()
        var ox = ow[0]
        var oy = ow[1]
        var oz = ow[2]
        var dx = products.dx if prepared else dw[0]
        var dy = products.dy if prepared else dw[1]
        var dz = products.dz if prepared else dw[2]
        # Lanes hold xy, xz, yz and a repeated xy comparison. Repeating a
        # real lane avoids padding masks without adding a new condition.
        var di = SIMD[DType.float64, 4](dx, dx, dy, dx)
        var dj = SIMD[DType.float64, 4](dy, dz, dz, dy)
        var low_i = SIMD[DType.float64, 4](lw[0], lw[0], lw[1], lw[0])
        var high_i = SIMD[DType.float64, 4](hw[0], hw[0], hw[1], hw[0])
        var low_j = SIMD[DType.float64, 4](lw[1], lw[2], lw[2], lw[1])
        var high_j = SIMD[DType.float64, 4](hw[1], hw[2], hw[2], hw[1])
        var place = SIMD[DType.float64, 4](
            products.xy, products.xz, products.yz, products.xy
        ) if prepared else (
            SIMD[DType.float64, 4](ox, ox, oy, ox) * dj
            - SIMD[DType.float64, 4](oy, oz, oz, oy) * di
        )
        var hit = _box_pairs[4](place, di, dj, low_i, high_i, low_j, high_j)
        if not need_regular and hit:
            return (True, True)
        var regular = (
            products.regular if prepared else self._query_products().regular
        )
        return (hit or not regular, regular)

    def _box_entry(self, box: Box3) -> _BoxEndpoint:
        """Select the active face after the common predicate reports a hit."""
        var dx = self.direction.x
        var dy = self.direction.y
        var dz = self.direction.z
        var span = _box_slab(self.origin.z, dz, box.min.z, box.max.z, 2)
        if dy != 0:
            span = _box_slab(self.origin.y, dy, box.min.y, box.max.y, 1)
        if dx != 0:
            span = _box_slab(self.origin.x, dx, box.min.x, box.max.x, 0)
        if dx != 0 and dy != 0:
            _include_box_interval(
                span, _box_slab(self.origin.y, dy, box.min.y, box.max.y, 1)
            )
        if dz != 0 and (dx != 0 or dy != 0):
            _include_box_interval(
                span, _box_slab(self.origin.z, dz, box.min.z, box.max.z, 2)
            )
        if span.near.face >= span.near.origin:
            return span.near
        return span.far

    def intersect_box(self, box: Box3) -> Optional[Vector3]:
        """Return where this ray enters the box, or exits if it starts inside.

        Args:
            box: The box.

        Returns:
            Its first finite forward surface point, or None for a miss,
            empty or NaN box, or an unbounded exit with no finite surface.
        """
        var decision = self._box_decision(box)
        if not decision[0]:
            return None
        if not decision[1]:
            return Vector3(
                nan[DType.float32](), nan[DType.float32](), nan[DType.float32]()
            )
        var endpoint = self._box_entry(box)
        if not abs(endpoint.face) < inf[DType.float64]():
            return None
        var face = endpoint.face * endpoint.sign
        var direction = endpoint.direction * endpoint.sign
        var origin = endpoint.origin * endpoint.sign
        var inverse = 1 / direction
        if endpoint.axis == 0:
            return Vector3(
                Float32(face),
                Float32(
                    _plane_coordinate(
                        origin,
                        Float64(self.origin.y),
                        direction,
                        Float64(self.direction.y),
                        face,
                        Float64(box.min.y),
                        inverse,
                    )
                ),
                Float32(
                    _plane_coordinate(
                        origin,
                        Float64(self.origin.z),
                        direction,
                        Float64(self.direction.z),
                        face,
                        Float64(box.min.z),
                        inverse,
                    )
                ),
            )
        if endpoint.axis == 1:
            return Vector3(
                Float32(
                    _plane_coordinate(
                        origin,
                        Float64(self.origin.x),
                        direction,
                        Float64(self.direction.x),
                        face,
                        Float64(box.min.x),
                        inverse,
                    )
                ),
                Float32(face),
                Float32(
                    _plane_coordinate(
                        origin,
                        Float64(self.origin.z),
                        direction,
                        Float64(self.direction.z),
                        face,
                        Float64(box.min.z),
                        inverse,
                    )
                ),
            )
        return Vector3(
            Float32(
                _plane_coordinate(
                    origin,
                    Float64(self.origin.x),
                    direction,
                    Float64(self.direction.x),
                    face,
                    Float64(box.min.x),
                    inverse,
                )
            ),
            Float32(
                _plane_coordinate(
                    origin,
                    Float64(self.origin.y),
                    direction,
                    Float64(self.direction.y),
                    face,
                    Float64(box.min.y),
                    inverse,
                )
            ),
            Float32(face),
        )

    @always_inline
    def intersects_box(self, box: Box3) -> Bool:
        """Return whether the ray reaches the box, including its surface.

        Args:
            box: The box.

        Returns:
            False for a missed, empty or NaN box. An unbounded volume can
            be met even when `intersect_box` has no finite exit to return.
        """
        return self._box_decision[False, False](box)[0]

    def intersect_triangle(
        self, a: Vector3, b: Vector3, c: Vector3, cull_back: Bool
    ) -> Optional[Vector3]:
        """Return where this ray meets the triangle `a`, `b`, `c`,
        three.js's `intersectTriangle`, or None if it misses.

        The triangle's front is the side it winds counter-clockwise from,
        as everywhere in this project. With `cull_back` set, a ray reaching
        it from behind passes through, which is what a `FRONT_SIDE`
        material wants: a pick lands on what is drawn.

        three.js's arithmetic, which is a Moller-Trumbore test written as
        three signed volumes: the ray's direction against the triangle's
        normal says which side it comes from and scales the rest; the
        origin's offset from `a`, crossed with each edge, says whether the
        hit is inside each of two edges; and their sum against the whole
        says whether it is inside the third. A hit behind the origin is a
        miss. A ray in the triangle's plane misses it, and so does a
        degenerate triangle, since neither has a normal to be on a side of.

        Args:
            a: First corner.
            b: Second corner.
            c: Third corner.
            cull_back: Whether a hit from behind counts as a miss.

        Returns:
            The point, or None.
        """
        var edge1 = b - a
        var edge2 = c - a
        var normal = edge1
        normal.cross(edge2)
        var d_dot_n = self.direction.dot(normal)
        var sign = Float32(1)
        if d_dot_n > 0:
            if cull_back:
                return None
        elif d_dot_n < 0:
            sign = -1
            d_dot_n = -d_dot_n
        else:
            return None
        var diff = self.origin - a
        var diff_x_edge2 = diff
        diff_x_edge2.cross(edge2)
        var d_dot_qxe2 = sign * self.direction.dot(diff_x_edge2)
        if d_dot_qxe2 < 0:
            return None
        var edge1_x_diff = edge1
        edge1_x_diff.cross(diff)
        var d_dot_e1xq = sign * self.direction.dot(edge1_x_diff)
        if d_dot_e1xq < 0:
            return None
        if d_dot_qxe2 + d_dot_e1xq > d_dot_n:
            return None
        var q_dot_n = -sign * diff.dot(normal)
        if q_dot_n < 0:
            return None
        return self.at(q_dot_n / d_dot_n)

    def apply_matrix4(mut self, matrix: Matrix4) raises:
        """Carry this ray through `matrix`, three.js's `applyMatrix4`: the
        origin as a point, the direction as a direction, made unit again.

        A raycaster does this with the inverse of a mesh's world matrix, so
        that the mesh's own triangles can be tested where they are stored.

        Args:
            matrix: The transform. Affine: it moves, turns, scales or
                shears, and keeps `w` at one.

        Raises:
            Error: If the matrix projects, since a direction has no image
                under one, or flattens the direction to nothing, which
                leaves the ray no way to point.
        """
        if not matrix.is_affine():
            raise Error("A ray can only be carried through an affine matrix")
        var direction = matrix.transform_direction(self.direction)
        if direction.length() == 0:
            raise Error(
                "A transform that flattens the ray's direction leaves it no"
                " way to point"
            )
        direction.normalize()
        self.origin = matrix.transform_point(self.origin)
        self.direction = direction
