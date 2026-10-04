# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""3D Gaussian splats at a scene node, from three.js
`examples/jsm/objects/GaussianSplat.js`.

A `GaussianSplat` holds a `GaussianSplatGeometry` and the scene node that
places it. It keeps what three.js's object keeps beside its GPU buffers:

- **Bounds.** The box grows each splat by the largest coordinate extent,
  including the diagonal regularization used by picking. The sphere uses
  the largest absolute regularized covariance row sum to cover rotated
  long axes. Stored bounds round outward. Rendering retains its original
  covariance; the larger sphere also supplies the depth-sort range.
- **A raycast.** `raycast` meets the ray with the ellipsoid each splat's
  covariance describes, at the kernel's cutoff: three.js's
  `computeRayIntersection`. Splats fainter than `MIN_RAYCAST_OPACITY` are
  skipped, and a flat covariance is floored by `COVARIANCE_FLATNESS` of
  its widest variance so it can be inverted.
- **The draw order.** Splats blend, so they are drawn back to front.
  `update_sort` sorts them by view depth into `BIN_COUNT` bins with a
  stable counting sort, three.js's `CountingSort.computeCPU`, the WebGL
  fallback's sort. It sorts again only when the object's view direction
  turns by more than `SORT_DIRECTION_THRESHOLD` of a cosine, as three.js's
  `_needsSort` decides. `order` holds the result: the splat indices,
  furthest first.
- **The view-dependent color.** `spherical_harmonics_colors` evaluates the
  higher bands for a camera, as three.js's compute pass does; the renderer
  adds the result to each splat's color.

`render.splat_raster` draws one. Its arithmetic is shared with the GPU
through `render.splatrule`.
"""

from core.gaussian_splat_utils import GaussianSplatGeometry
from core.object3d import NodeId
from math.ray_query import RayQuery
from math.ray import (
    _distance_sq_ratio,
    _line_approach,
    _radius_relation,
    _RayProducts,
)
from math.bounds import Box3, Sphere
from math.box_extent import _max_radius_encloses_box
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import floor, inf, isfinite, max, min, sqrt
from std.memory import bitcast
from units.si import Length, METER

# How many standard deviations a splat is drawn out to.
comptime SPLAT_KERNEL_CUTOFF = Float64(2)
# The thinnest variance a raycast gives a splat, as a share of its widest.
comptime COVARIANCE_FLATNESS = Float64(1e-4)
# The faintest opacity a raycast can hit.
comptime MIN_RAYCAST_OPACITY = Float64(0.2)
# How many depth bins the sort quantizes into.
comptime BIN_COUNT = 4096
# The cosine between the last sorted view direction and the current one
# below which the splats are sorted again.
comptime SORT_DIRECTION_THRESHOLD = Float32(0.9995)
# The narrowest depth range the sort divides into bins.
comptime MIN_SORT_RANGE = Float64(0.0001)


def _sqrt_bound(variance: Float64) -> Float64:
    """Round a covariance reach above the regularized ellipsoid.

    The narrow phase and bounds share the rounded floor R and diagonals
    Aii=fl(Cii+R). Two positive row additions give at least (1-u)**2
    times the exact row sum of this stored matrix, where u=2**-53.
    The square root and final inflated product therefore give at least
    (1-u)**3*(1+16*u) times the exact reach, which is greater than one.
    A subsequent rounded square retains a positive margin as well.

    For finite Float32 covariance entries, every nonzero intermediate is
    normal Float64. Even a cancellation in Cii+R cannot go below 2**-217;
    a row sum stays below 2**131. No underflow or overflow invalidates the
    relative error bounds. The floor's rounding is shared with the actual
    picking matrix, rather than hidden by a different broad-phase formula.
    """
    return SPLAT_KERNEL_CUTOFF * sqrt(variance) * Float64(1.0000000000000018)


def _round_bound[upper: Bool](value: Float64, residual: Float64) -> Float32:
    """Round an exact two-term sum outward to a stored Float32 endpoint."""
    var stored = Float32(value)
    var wide = Float64(stored)
    var change: Bool
    comptime if upper:
        change = wide < value or (wide == value and residual > 0)
    else:
        change = wide > value or (wide == value and residual < 0)
    if change:
        if stored == 0:
            comptime if upper:
                return bitcast[DType.float32](UInt32(1))
            else:
                return bitcast[DType.float32](UInt32(0x80000001))
        var bits = bitcast[DType.uint32](stored)
        if (stored > 0) == upper:
            bits += 1
        else:
            bits -= 1
        stored = bitcast[DType.float32](bits)
    return stored


def _bound_coordinate[upper: Bool](center: Float32, extent: Float64) -> Float32:
    """Keep a tiny extent even when the wide endpoint rounds to its center."""
    var first = Float64(center)
    var second = extent if upper else -extent
    var value = first + second
    var virtual = value - first
    var residual = (first - (value - virtual)) + (second - virtual)
    return _round_bound[upper](value, residual)


@fieldwise_init
struct SplatHit(ImplicitlyCopyable):
    """Where a ray meets a splat: three.js's intersection object, with no
    face."""

    # How far along the world ray the hit is.
    var distance: Length
    # Where it is, in world space.
    var point: Vector3
    # Which splat.
    var index: Int


struct GaussianSplat(Copyable, Movable):
    """Gaussian splats at a scene node; see the module docstring."""

    var splat_geometry: GaussianSplatGeometry
    var node: NodeId
    # Whether the renderer sorts the splats before it draws them, three.js's
    # `autoSort`. On by default.
    var auto_sort: Bool
    # The splats' bounds in the object's own space, each splat grown by its
    # extent, or none until computed.
    var bounding_box: Optional[Box3]
    var bounding_sphere: Optional[Sphere]
    # The draw order: every splat index once, furthest first once sorted.
    var order: List[Int]
    # Whether `update_sort` has sorted once.
    var sort_initialized: Bool
    # The view direction the last sort was for.
    var last_sort_direction: Vector3
    # The last sort's model-view matrix and the view depths its bins span.
    var sort_matrix: Matrix4
    var sort_near: Float64
    var sort_far: Float64

    def __init__(
        out self,
        var geometry: GaussianSplatGeometry,
        node: NodeId,
        *,
        auto_sort: Bool = True,
    ) raises:
        """Place splats at a scene node.

        Args:
            geometry: The splats.
            node: The scene node that gives them their world transform.
            auto_sort: Whether the renderer sorts them before a draw.

        Raises:
            Error: If the node id is negative.
        """
        if node.value < 0:
            raise Error("A Gaussian splat must name a scene node")
        var count = geometry.count()
        self.splat_geometry = geometry^
        self.node = node
        self.auto_sort = auto_sort
        self.bounding_box = None
        self.bounding_sphere = None
        self.order = List[Int](capacity=count)
        for index in range(count):
            self.order.append(index)
        self.sort_initialized = False
        self.last_sort_direction = Vector3(0, 0, 0)
        self.sort_matrix = Matrix4()
        self.sort_near = 0
        self.sort_far = 1

    def count(self) -> Int:
        """Return how many splats there are."""
        return self.splat_geometry.count()

    @always_inline
    def _covariance_floor(self, index: Int) -> Float64:
        """Return the same diagonal regularization used by every pick bound."""
        ref c = self.splat_geometry.covariances
        return (
            max(
                Float64(c[index * 6]),
                max(Float64(c[index * 6 + 3]), Float64(c[index * 6 + 5])),
            )
            * COVARIANCE_FLATNESS
        )

    def _extent(self, index: Int) -> Float64:
        """Return the largest coordinate reach of the picking ellipsoid.

        Args:
            index: Which splat.

        Returns:
            An outward bound on `SPLAT_KERNEL_CUTOFF` times the square root
            of its largest regularized variance. Negative variance gives
            not a number, as three.js's `Math.sqrt` gives.
        """
        ref c = self.splat_geometry.covariances
        var largest = max(
            Float64(c[index * 6]),
            max(Float64(c[index * 6 + 3]), Float64(c[index * 6 + 5])),
        )
        return _sqrt_bound(largest + self._covariance_floor(index))

    @always_inline
    def _sphere_extent(self, index: Int) -> Float64:
        """Return a conservative radius for a positive covariance matrix.

        The largest absolute regularized row sum bounds every eigenvalue.
        Unlike the largest diagonal, it covers a rotated long axis. The
        same diagonal floor is used by the narrow-phase inverse.
        """
        ref c = self.splat_geometry.covariances
        var xy = abs(Float64(c[index * 6 + 1]))
        var xz = abs(Float64(c[index * 6 + 2]))
        var yz = abs(Float64(c[index * 6 + 4]))
        var regularizer = self._covariance_floor(index)
        var x = abs(Float64(c[index * 6]) + regularizer) + xy + xz
        var y = abs(Float64(c[index * 6 + 3]) + regularizer) + xy + yz
        var z = abs(Float64(c[index * 6 + 5]) + regularizer) + xz + yz
        return _sqrt_bound(max(x, max(y, z)))

    def _center(self, index: Int) -> Vector3:
        """Return a splat's center.

        Args:
            index: Which splat.

        Returns:
            The center, in the object's space.
        """
        ref c = self.splat_geometry.centers
        return Vector3(c[index * 3], c[index * 3 + 1], c[index * 3 + 2])

    def compute_bounding_box(mut self):
        """Bound every regularized picking ellipsoid with outward endpoints.

        This is three.js's `computeBoundingBox`, enlarged to include its
        raycast regularization. An object of no splats has the empty box.
        """
        var box = Box3.empty()
        for index in range(self.count()):
            var center = self._center(index)
            var reach = self._extent(index)
            box.expand_by_point(
                Vector3(
                    _bound_coordinate[False](center.x, reach),
                    _bound_coordinate[False](center.y, reach),
                    _bound_coordinate[False](center.z, reach),
                )
            )
            box.expand_by_point(
                Vector3(
                    _bound_coordinate[True](center.x, reach),
                    _bound_coordinate[True](center.y, reach),
                    _bound_coordinate[True](center.z, reach),
                )
            )
        self.bounding_box = box

    def compute_bounding_sphere(mut self):
        """Bound every splat with a sphere, three.js's
        `computeBoundingSphere`: centered on the box, and reaching the far
        side of the farthest regularized splat. A box with an infinite
        endpoint uses the finite center-only midpoint instead.
        """
        self.compute_bounding_box()
        var middle = self.bounding_box.value().center()
        if not (
            isfinite(middle.x) and isfinite(middle.y) and isfinite(middle.z)
        ):
            # A finite center plus a positive extent can need an infinite
            # Float32 box endpoint. The center-only box still has a midpoint.
            # The empty box has a finite origin center, so this path has splats.
            var first = self._center(0)
            var centers = Box3(first, first)
            for index in range(1, self.count()):
                centers.expand_by_point(self._center(index))
            middle = centers.center()
        var reach = Float64(0)
        for index in range(self.count()):
            var center = self._center(index)
            var x = Float64(center.x) - Float64(middle.x)
            var y = Float64(center.y) - Float64(middle.y)
            var z = Float64(center.z) - Float64(middle.z)
            # Differences, squares and two sums give a squared-distance lower
            # bound (1-u)**5. The root, reach addition and final product give
            # (1-u)**5.5*(1+16*u) > 1 for the enclosing distance plus reach.
            # Finite Float32 differences have squared magnitudes between
            # 2**-298 and 2**258, safely inside normal Float64 arithmetic.
            var far = (
                sqrt(x * x + y * y + z * z) + self._sphere_extent(index)
            ) * Float64(1.0000000000000018)
            reach = max(reach, far)
        var radius = _round_bound[True](reach, 0)
        if radius == inf[DType.float32]() and self._zero_reach_fits_limit(
            middle
        ):
            radius = bitcast[DType.float32](UInt32(0x7F7FFFFF))
        var sphere = Sphere(middle, radius)
        self.bounding_sphere = sphere

    def _zero_reach_fits_limit(self, middle: Vector3) -> Bool:
        """Exactly admit a finite-limit sphere for point splats only.

        Zero covariance is accepted by the geometry boundary. Inflating a
        rounded distance can cross the Float32 limit even when every point
        is exactly inside it. This predicate proves containment before
        replacing infinity; positive reaches and outside points fail.
        An empty set is enclosed, as for any universal point predicate.
        """
        if not (
            isfinite(middle.x) and isfinite(middle.y) and isfinite(middle.z)
        ):
            return False
        var stored_middle: Array[Float32, 3] = [middle.x, middle.y, middle.z]
        for index in range(self.count()):
            if self._sphere_extent(index) != 0:
                return False
            var point = self._center(index)
            if not (
                isfinite(point.x) and isfinite(point.y) and isfinite(point.z)
            ):
                return False
            var coordinate: Array[Float32, 3] = [point.x, point.y, point.z]
            if not _max_radius_encloses_box(
                coordinate, coordinate, stored_middle
            ):
                return False
        return True

    def raycast[
        R: RayQuery
    ](mut self, world: Matrix4, raycaster: R) raises -> List[SplatHit]:
        """Return where a ray meets the splats, three.js's `raycast`.

        Args:
            world: The object's world matrix.
            raycaster: The ray, and the distances it is kept between.

        Returns:
            One hit per splat met, in the splats' order.

        Raises:
            Error: If the world matrix is not affine or cannot be inverted.
        """
        var hits = List[SplatHit]()
        if not self.bounding_sphere:
            self.compute_bounding_sphere()
        var sphere = self.bounding_sphere.value()
        sphere.apply_matrix4(world)
        if not raycaster.query_ray().intersects_sphere(sphere):
            return hits^
        var inverse = world
        inverse.invert()
        var ray = raycaster.query_ray()
        ray.apply_matrix4(inverse)
        if not ray.intersects_box(self.bounding_box.value()):
            return hits^
        var products = ray._query_products()
        for index in range(self.count()):  # pragma: no branch
            var local_point = self._ray_intersection(
                ray.origin, ray.direction, index, products
            )
            if not local_point:
                continue
            var point = world.transform_point(local_point.value())
            var distance = raycaster.query_ray().origin.distance_to(point)
            if distance < raycaster.query_near().value:
                continue
            if distance > raycaster.query_far().value:
                continue
            hits.append(SplatHit(Length(distance, METER), point, index))
        return hits^

    def _ray_intersection(
        self,
        origin: Vector3,
        direction: Vector3,
        index: Int,
        products: _RayProducts,
    ) -> Optional[Vector3]:
        """Return where a local ray meets one splat's ellipsoid.

        Args:
            origin: The ray's origin, in the object's space.
            direction: Its unit direction, in the object's space.
            index: Which splat.
            products: Ray-only products prepared after its local transform.

        Returns:
            The near surface point, or the far one when the origin is
            inside. None when the ray misses, the splat is too faint, or
            its covariance is not positive.
        """
        var opacity = Float64(self.splat_geometry.colors[index * 4 + 3]) / 255
        if opacity < MIN_RAYCAST_OPACITY:
            return None
        ref c = self.splat_geometry.covariances
        var c00 = Float64(c[index * 6])
        var c01 = Float64(c[index * 6 + 1])
        var c02 = Float64(c[index * 6 + 2])
        var c11 = Float64(c[index * 6 + 3])
        var c12 = Float64(c[index * 6 + 4])
        var c22 = Float64(c[index * 6 + 5])
        var largest = max(c00, max(c11, c22))
        if not largest > 0:
            return None
        var center = self._center(index)
        var bound = self._sphere_extent(index)
        var ratio = _distance_sq_ratio[True](
            origin, direction, center, products
        )
        if _radius_relation(ratio, bound * bound)[1]:
            return None
        var floor_variance = self._covariance_floor(index)
        var a00 = c00 + floor_variance
        var a11 = c11 + floor_variance
        var a22 = c22 + floor_variance
        # The inverse by cofactors, as three.js's `Matrix3.invert`.
        var t11 = a22 * a11 - c12 * c12
        var t12 = c12 * c02 - a22 * c01
        var t13 = c12 * c01 - a11 * c02
        var determinant = a00 * t11 + c01 * t12 + c02 * t13
        if not (a00 > 0 and a00 * a11 - c01 * c01 > 0 and determinant > 0):
            return None
        var inv = 1 / determinant
        var i00 = t11 * inv
        var i01 = (c02 * c12 - a22 * c01) * inv
        var i02 = (c01 * c12 - c02 * a11) * inv
        var i11 = (a22 * a00 - c02 * c02) * inv
        var i12 = (c02 * c01 - a00 * c12) * inv
        var i22 = (a11 * a00 - c01 * c01) * inv
        var dx = Float64(direction.x)
        var dy = Float64(direction.y)
        var dz = Float64(direction.z)
        var mx = i00 * dx + i01 * dy + i02 * dz
        var my = i01 * dx + i11 * dy + i12 * dz
        var mz = i02 * dx + i12 * dy + i22 * dz
        var a = dx * mx + dy * my + dz * mz
        # First find the Euclidean closest point with the shared cross-product
        # calculation. Forming origin + parameter * direction can lose even
        # a whole splat at a distant origin with a rounded unit direction.
        var approach = _line_approach[True](origin, direction, center, products)
        var ox = -approach.offset_x
        var oy = -approach.offset_y
        var oz = -approach.offset_z
        # Shift from there to the closest point in the covariance metric.
        # This also avoids b*b - 4*a*c cancellation at a distant origin.
        var shift = -(ox * mx + oy * my + oz * mz) / a
        var foot = approach.parameter + shift
        var fx = ox + shift * dx
        var fy = oy + shift * dy
        var fz = oz + shift * dz
        var nx = i00 * fx + i01 * fy + i02 * fz
        var ny = i01 * fx + i11 * fy + i12 * fz
        var nz = i02 * fx + i12 * fy + i22 * fz
        var half_sq = (
            SPLAT_KERNEL_CUTOFF * SPLAT_KERNEL_CUTOFF
            - (fx * nx + fy * ny + fz * nz)
        ) / a
        if half_sq < 0:
            return None
        var half = sqrt(half_sq)
        var offset = -half
        if foot - half < 0:
            offset = half
        if foot + offset < 0:
            return None
        # Preserve the surface offset even when the distance from the ray
        # origin is too large for that offset to survive in its parameter.
        return Vector3(
            Float32(Float64(center.x) + fx + offset * dx),
            Float32(Float64(center.y) + fy + offset * dy),
            Float32(Float64(center.z) + fz + offset * dz),
        )

    def sort_direction(self, model_view: Matrix4) -> Vector3:
        """Return the object's axis toward the camera in view space, what
        three.js's `_needsSort` compares.

        Args:
            model_view: The view matrix times the object's world matrix.

        Returns:
            The model-view matrix's third row, made unit length.
        """
        ref e = model_view.elements
        var direction = Vector3(e[2], e[6], e[10])
        direction.normalize()
        return direction

    def needs_sort(self, model_view: Matrix4) -> Bool:
        """Return whether the view has turned far enough to sort again,
        three.js's `_needsSort`.

        Args:
            model_view: The view matrix times the object's world matrix.

        Returns:
            True when the direction's cosine with the last sorted one is
            below `SORT_DIRECTION_THRESHOLD`.
        """
        return (
            self.sort_direction(model_view).dot(self.last_sort_direction)
            < SORT_DIRECTION_THRESHOLD
        )

    def update_sort(
        mut self, world: Matrix4, view: Matrix4, near: Length
    ) raises -> Bool:
        """Sort the splats back to front when the view needs it, three.js's
        `updateSort` on the CPU.

        Args:
            world: The object's world matrix.
            view: The camera's view matrix, three.js's
                `matrixWorldInverse`.
            near: The camera's near distance.

        Returns:
            Whether the splats were sorted.

        Raises:
            Error: If the world matrix is not affine.
        """
        var model_view = view * world
        var needs = self.needs_sort(model_view)
        if self.sort_initialized and not needs:
            return False
        self._update_sort_range(world, view, model_view, near)
        self.sort_cpu()
        self.sort_initialized = True
        self.last_sort_direction = self.sort_direction(model_view)
        return True

    def _update_sort_range(
        mut self,
        world: Matrix4,
        view: Matrix4,
        model_view: Matrix4,
        near: Length,
    ) raises:
        """Set the sort's matrix and the view depths its bins span,
        three.js's `_updateSortUniforms`.

        Args:
            world: The object's world matrix.
            view: The camera's view matrix.
            model_view: Their product.
            near: The camera's near distance.

        Raises:
            Error: If the world matrix is not affine.
        """
        self.sort_matrix = model_view
        if not self.bounding_sphere:
            self.compute_bounding_sphere()
        var sphere = self.bounding_sphere.value()
        var in_view = view.transform_point(world.transform_point(sphere.center))
        ref e = world.elements
        var scale = max(
            _length(e[0], e[1], e[2]),
            max(_length(e[4], e[5], e[6]), _length(e[8], e[9], e[10])),
        )
        var radius = Float64(sphere.radius) * scale
        var depth = -Float64(in_view.z)
        var near_depth = max(Float64(near.value), depth - radius)
        var far_depth = max(near_depth + MIN_SORT_RANGE, depth + radius)
        self.sort_near = near_depth
        self.sort_far = far_depth

    def sort_bin(self, index: Int) -> Int:
        """Return the bin a splat sorts into, three.js's `_sortCPU` key.

        Args:
            index: Which splat.

        Returns:
            0 for the furthest depths up to `BIN_COUNT - 1` for the
            nearest.
        """
        ref m = self.sort_matrix.elements
        ref c = self.splat_geometry.centers
        var depth = -(
            Float64(m[2]) * Float64(c[index * 3])
            + Float64(m[6]) * Float64(c[index * 3 + 1])
            + Float64(m[10]) * Float64(c[index * 3 + 2])
            + Float64(m[14])
        )
        var span = max(self.sort_far - self.sort_near, MIN_SORT_RANGE)
        var scale = Float64(BIN_COUNT - 1) / span
        var bin = min(
            Float64(BIN_COUNT - 1),
            max(Float64(0), floor((depth - self.sort_near) * scale)),
        )
        return BIN_COUNT - 1 - Int(bin)

    def sort_cpu(mut self):
        """Sort the splats by `sort_bin`, stably, into `order`: three.js's
        `CountingSort.computeCPU`."""
        var count = self.count()
        var bins = List[Int](capacity=count)
        var counts = List[Int](length=BIN_COUNT, fill=0)
        for index in range(count):
            var bin = self.sort_bin(index)
            bins.append(bin)
            counts[bin] += 1
        var offsets = List[Int](length=BIN_COUNT, fill=0)
        var sum = 0
        for bin in range(BIN_COUNT):  # pragma: no branch
            offsets[bin] = sum
            sum += counts[bin]
        for index in range(count):
            self.order[offsets[bins[index]]] = index
            offsets[bins[index]] += 1

    def spherical_harmonics_colors(self, camera: Vector3) -> List[Float32]:
        """Return each splat's view-dependent color, three.js's
        `applySphericalHarmonics`.

        Args:
            camera: The camera's position, in the object's space.

        Returns:
            Three floats a splat, added to its color before the draw, or
            none when the splats carry no band above the zeroth.
        """
        var degree = self.splat_geometry.spherical_harmonics_degree()
        var out = List[Float32]()
        if degree == 0:
            return out^
        out.reserve(self.count() * 3)
        for index in range(self.count()):  # pragma: no branch
            var direction = self._center(index) - camera
            direction.normalize()
            ref g = self.splat_geometry
            var rgb = _band_sum(g.sh1, index, 1, direction)
            if degree >= 2:
                rgb = rgb + _band_sum(g.sh2, index, 2, direction)
            if degree >= 3:
                rgb = rgb + _band_sum(g.sh3, index, 3, direction)
            out.append(rgb.x)
            out.append(rgb.y)
            out.append(rgb.z)
        return out^


def _length(x: Float32, y: Float32, z: Float32) -> Float64:
    """Return a column's length, as three.js's `setFromMatrixScale` reads.

    Args:
        x: The column's first element.
        y: Its second.
        z: Its third.

    Returns:
        The length.
    """
    var fx = Float64(x)
    var fy = Float64(y)
    var fz = Float64(z)
    return sqrt(fx * fx + fy * fy + fz * fz)


def _weights(degree: Int, d: Vector3) -> List[Float32]:
    """Return the weights of one band's coefficients for a direction, as
    three.js's `applySphericalHarmonics` writes them.

    Args:
        degree: The band, 1 through 3.
        d: The unit direction from the camera to the splat.

    Returns:
        `2 degree + 1` weights.
    """
    var x = d.x
    var y = d.y
    var z = d.z
    if degree == 1:
        return [y * -0.4886025, z * 0.4886025, x * -0.4886025]
    var xx = x * x
    var yy = y * y
    var zz = z * z
    if degree == 2:
        return [
            x * y * 1.0925484,
            y * z * -1.0925484,
            (zz * 2 - xx - yy) * 0.3153915,
            x * z * -1.0925484,
            (xx - yy) * 0.5462742,
        ]
    var xy = x * y
    return [
        y * (xx * 3 - yy) * -0.5900436,
        xy * z * 2.8906114,
        y * (zz * 4 - xx - yy) * -0.4570458,
        z * (zz * 2 - xx * 3 - yy * 3) * 0.3731763,
        x * (zz * 4 - xx - yy) * -0.4570458,
        z * (xx - yy) * 1.4453057,
        x * (xx - yy * 3) * -0.5900436,
    ]


def _band_sum(
    band: List[UInt8], index: Int, degree: Int, d: Vector3
) -> Vector3:
    """Return one band's color for a splat and a direction.

    Args:
        band: The band's bytes.
        index: Which splat.
        degree: The band, 1 through 3.
        d: The unit direction from the camera to the splat.

    Returns:
        The sum of the band's coefficients, each `(byte - 128) / 128`,
        times their weights.
    """
    var weights = _weights(degree, d)
    # Each splat takes whole four-byte words: `sh_band_words`.
    var words = (len(weights) * 3 + 3) // 4
    var start = index * words * 4
    var sum = Vector3(0, 0, 0)
    for k in range(len(weights)):  # pragma: no branch
        var at = start + k * 3
        sum.x += (Float32(band[at]) - 128) / 128 * weights[k]
        sum.y += (Float32(band[at + 1]) - 128) / 128 * weights[k]
        sum.z += (Float32(band[at + 2]) - 128) / 128 * weights[k]
    return sum
