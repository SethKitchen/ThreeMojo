# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""3D Gaussian splats at a scene node, from three.js
`examples/jsm/objects/GaussianSplat.js`.

A `GaussianSplat` holds a `GaussianSplatGeometry` and the scene node that
places it. It keeps what three.js's object keeps beside its GPU buffers:

- **Bounds.** `compute_bounding_box` and `compute_bounding_sphere` grow
  each splat by its drawn extent, `SPLAT_KERNEL_CUTOFF` times the square
  root of its largest variance, as three.js does.
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
from math.bounds import Box3, Sphere
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import floor, max, min, sqrt
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

    def _extent(self, index: Int) -> Float64:
        """Return how far a splat is drawn from its center.

        Args:
            index: Which splat.

        Returns:
            `SPLAT_KERNEL_CUTOFF` times the square root of its largest
            variance, and not a number for a negative variance, as
            three.js's `Math.sqrt` gives.
        """
        ref c = self.splat_geometry.covariances
        var largest = max(
            Float64(c[index * 6]),
            max(Float64(c[index * 6 + 3]), Float64(c[index * 6 + 5])),
        )
        return SPLAT_KERNEL_CUTOFF * sqrt(largest)

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
        """Bound every splat, each grown by its extent, three.js's
        `computeBoundingBox`. An object of no splats has the empty box."""
        var box = Box3.empty()
        for index in range(self.count()):
            var center = self._center(index)
            var reach = Float32(self._extent(index))
            box.expand_by_point(
                Vector3(center.x - reach, center.y - reach, center.z - reach)
            )
            box.expand_by_point(
                Vector3(center.x + reach, center.y + reach, center.z + reach)
            )
        self.bounding_box = box

    def compute_bounding_sphere(mut self):
        """Bound every splat with a sphere, three.js's
        `computeBoundingSphere`: centered on the box, and reaching the far
        side of the farthest splat."""
        self.compute_bounding_box()
        var sphere = self.bounding_box.value().bounding_sphere()
        var reach = Float32(0)
        for index in range(self.count()):
            var far = sphere.center.distance_to(self._center(index)) + Float32(
                self._extent(index)
            )
            reach = max(reach, far)
        sphere.radius = reach
        self.bounding_sphere = sphere

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
        for index in range(self.count()):  # pragma: no branch
            var t = self._ray_parameter(ray.origin, ray.direction, index)
            if t < 0:
                continue
            var point = world.transform_point(ray.at(Float32(t)))
            var distance = raycaster.query_ray().origin.distance_to(point)
            if distance < raycaster.query_near().value:
                continue
            if distance > raycaster.query_far().value:
                continue
            hits.append(SplatHit(Length(distance, METER), point, index))
        return hits^

    def _ray_parameter(
        self, origin: Vector3, direction: Vector3, index: Int
    ) -> Float64:
        """Return how far along a local ray it meets one splat's ellipsoid.

        Args:
            origin: The ray's origin, in the object's space.
            direction: Its unit direction, in the object's space.
            index: Which splat.

        Returns:
            The distance to the near surface, or to the far one when the
            origin is inside, and minus one when the ray misses, the splat
            is too faint, or its covariance is not positive.
        """
        var opacity = Float64(self.splat_geometry.colors[index * 4 + 3]) / 255
        if opacity < MIN_RAYCAST_OPACITY:
            return -1
        ref c = self.splat_geometry.covariances
        var c00 = Float64(c[index * 6])
        var c01 = Float64(c[index * 6 + 1])
        var c02 = Float64(c[index * 6 + 2])
        var c11 = Float64(c[index * 6 + 3])
        var c12 = Float64(c[index * 6 + 4])
        var c22 = Float64(c[index * 6 + 5])
        var largest = max(c00, max(c11, c22))
        if not largest > 0:
            return -1
        var center = self._center(index)
        var bound = SPLAT_KERNEL_CUTOFF * sqrt(largest)
        if Float64(_distance_sq(origin, direction, center)) > bound * bound:
            return -1
        var floor_variance = largest * COVARIANCE_FLATNESS
        var a00 = c00 + floor_variance
        var a11 = c11 + floor_variance
        var a22 = c22 + floor_variance
        # The inverse by cofactors, as three.js's `Matrix3.invert`.
        var t11 = a22 * a11 - c12 * c12
        var t12 = c12 * c02 - a22 * c01
        var t13 = c12 * c01 - a11 * c02
        var determinant = a00 * t11 + c01 * t12 + c02 * t13
        if not determinant > 0:
            return -1
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
        var ox = Float64(origin.x) - Float64(center.x)
        var oy = Float64(origin.y) - Float64(center.y)
        var oz = Float64(origin.z) - Float64(center.z)
        var nx = i00 * ox + i01 * oy + i02 * oz
        var ny = i01 * ox + i11 * oy + i12 * oz
        var nz = i02 * ox + i12 * oy + i22 * oz
        var b = 2 * (ox * mx + oy * my + oz * mz)
        var cc = (
            ox * nx
            + oy * ny
            + oz * nz
            - SPLAT_KERNEL_CUTOFF * SPLAT_KERNEL_CUTOFF
        )
        var discriminant = b * b - 4 * a * cc
        if discriminant < 0:
            return -1
        var root = sqrt(discriminant)
        var t = (-b - root) / (2 * a)
        if t < 0:
            t = (-b + root) / (2 * a)
        return t

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


def _distance_sq(
    origin: Vector3, direction: Vector3, point: Vector3
) -> Float32:
    """Return the squared distance from a ray to a point, three.js's
    `Ray.distanceSqToPoint`: to the origin when the point is behind it.

    Args:
        origin: The ray's origin.
        direction: Its unit direction.
        point: The point.

    Returns:
        The squared distance.
    """
    var along = (point - origin).dot(direction)
    if along < 0:
        return (point - origin).length_sq()
    var nearest = origin + direction * along
    return (point - nearest).length_sq()


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
