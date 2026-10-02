# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for Gaussian splats: `core.gaussian_splat_utils`,
`objects.gaussian_splat`, `render.splatrule` and `render.splat_raster`.

The raycast and the sort order of `assets/gaussian_splat/four.splat`
are held to what three.js r186's `GaussianSplat` computed for the same
object and camera, in `expected.json`. The box and sphere use independent regularized-covariance bounds.
The depth range uses the same conservative sphere. The projection is held to the
closed form of a round splat straight ahead of the camera, and the
fragment to the Gaussian it draws.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from core.gaussian_splat_utils import (
    COVARIANCE,
    GaussianSplatGeometry,
    MAX_SH_DEGREE,
    SH_C0,
    band_words,
    clamped_byte,
    create_gaussian_splat_geometry,
    gaussian_splat_geometry_of,
    linear_to_sh0,
    packed_band,
    sh0_to_linear,
    sh_band_components,
    sh_band_words,
    sigmoid,
    spherical_harmonics_degree,
    write_color_bytes,
    write_color_bytes_from_sh0,
    write_covariance,
)
from core.object3d import NodeId, Object3D
from core.raycaster import Raycaster
from core.scene import Scene
from loaders.splat import read_splat
from math.euler import Euler, XYZ
from math.matrix4 import Matrix4
from math.utils import FLOAT32_COMPONENT, UINT32_COMPONENT, UINT8_COMPONENT
from math.vector3 import Vector3
from objects.gaussian_splat import BIN_COUNT, GaussianSplat
from render.framebuffer import Color
from render.raster_state import (
    DepthMode,
    LOGARITHMIC_DEPTH,
    REVERSED_DEPTH,
    STANDARD_DEPTH,
    log_depth_factor,
)
from render.splat_raster import (
    draw_gaussian_splat,
    prepare_gaussian_splat,
    rasterize_splats,
)
from render.splatrule import (
    FloatRgba,
    MAX_SCREEN_SPACE_SPLAT_SIZE,
    ProjectedSplat,
    SPLAT_FLOATS,
    SplatView,
    project_splat,
    splat_alpha,
    splat_depth_passes,
    splat_reach,
    stored_splat_depth,
)
from render.target import RenderTarget
from std.math import exp, isnan, log2, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER, RADIAN


# --- the data ---------------------------------------------------------------------


def test_the_band_tables() raises:
    assert_equal(sh_band_components(0), 0)
    assert_equal(sh_band_components(1), 9)
    assert_equal(sh_band_components(2), 15)
    assert_equal(sh_band_components(3), 21)
    assert_equal(sh_band_words(0), 0)
    assert_equal(sh_band_words(1), 3)
    assert_equal(sh_band_words(2), 4)
    assert_equal(sh_band_words(3), 6)
    with assert_raises(contains="degree -1 is not 0 through 3"):
        _ = sh_band_components(-1)
    with assert_raises(contains="degree 4 is not 0 through 3"):
        _ = sh_band_words(MAX_SH_DEGREE + 1)


def test_the_color_functions() raises:
    assert_equal(sigmoid(0), 0.5)
    assert_almost_equal(sigmoid(2), 1 / (1 + exp(Float64(-2))))
    assert_equal(sh0_to_linear(0), 0.5)
    assert_almost_equal(sh0_to_linear(1), SH_C0 + 0.5)
    assert_almost_equal(linear_to_sh0(sh0_to_linear(0.7)), 0.7)


def test_a_clamped_byte_rounds_half_to_even() raises:
    assert_equal(Int(clamped_byte(nan[DType.float64]())), 0)
    assert_equal(Int(clamped_byte(-3)), 0)
    assert_equal(Int(clamped_byte(0)), 0)
    assert_equal(Int(clamped_byte(255)), 255)
    assert_equal(Int(clamped_byte(1000)), 255)
    assert_equal(Int(clamped_byte(1.2)), 1)
    assert_equal(Int(clamped_byte(1.7)), 2)
    assert_equal(Int(clamped_byte(1.5)), 2)
    assert_equal(Int(clamped_byte(2.5)), 2)
    assert_equal(Int(clamped_byte(254.5)), 254)


def test_a_covariance_is_the_rotated_scale_squared() raises:
    var c = List[Float32](length=12, fill=0)
    write_covariance(c, 0, 2, 3, 4, 0, 0, 0, 1)
    assert_equal(c[0], 4)
    assert_equal(c[3], 9)
    assert_equal(c[5], 16)
    assert_equal(c[1], 0)
    # A quarter turn about z swaps the x and y variances; a quaternion of
    # no length is the identity.
    var half = sqrt(Float64(0.5))
    write_covariance(c, 6, 2, 3, 4, 0, 0, half * 7, half * 7)
    assert_almost_equal(c[6], 9, atol=1e-5)
    assert_almost_equal(c[9], 4, atol=1e-5)
    write_covariance(c, 6, 2, 3, 4, 0, 0, 0, 0)
    assert_equal(c[6], 4)
    assert_equal(c[9], 9)


def test_colors_are_written_as_clamped_bytes() raises:
    var colors = List[UInt8](length=8, fill=0)
    write_color_bytes(colors, 0, 300, -1, 127.5, 10)
    assert_equal(Int(colors[0]), 255)
    assert_equal(Int(colors[1]), 0)
    assert_equal(Int(colors[2]), 128)
    assert_equal(Int(colors[3]), 10)
    write_color_bytes_from_sh0(colors, 4, 0, linear_to_sh0(1), -100, 0.5)
    assert_equal(Int(colors[4]), 128)
    assert_equal(Int(colors[5]), 255)
    assert_equal(Int(colors[6]), 0)
    assert_equal(Int(colors[7]), 128)


def test_a_packed_band_is_zero_coefficients() raises:
    var band = packed_band(2, 1)
    assert_equal(len(band), 24)
    assert_equal(Int(band[23]), 128)
    with assert_raises(contains="degree of 1 to 3"):
        _ = packed_band(2, 0)
    with assert_raises(contains="cannot be negative"):
        _ = packed_band(-1, 1)
    var words = band_words([1, 2, 3, 4, 128, 128, 128, 128])
    assert_equal(words[0], 0x04030201)
    assert_equal(words[1], 0x80808080)
    with assert_raises(contains="whole number of words"):
        _ = band_words([1, 2, 3])
    assert_equal(len(band_words(List[UInt8]())), 0)


def two_splats() -> Tuple[List[Float32], List[Float32], List[UInt8]]:
    """Return two splats' centers, covariances and colors."""
    var centers: List[Float32] = [0, 1, 2, 3, 4, 5]
    var covariances = List[Float32](length=12, fill=0.25)
    var colors: List[UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
    return (centers^, covariances^, colors^)


def test_a_geometry_checks_its_lengths() raises:
    var s = two_splats()
    with assert_raises(contains="not whole splats"):
        _ = create_gaussian_splat_geometry([0, 1], s[1].copy(), s[2].copy())
    with assert_raises(contains="covariances are not one a splat"):
        _ = create_gaussian_splat_geometry(s[0].copy(), [1], s[2].copy())
    with assert_raises(contains="colors are not one a splat"):
        _ = create_gaussian_splat_geometry(s[0].copy(), s[1].copy(), [1])
    with assert_raises(contains="invalid sphericalHarmonics1 packed length"):
        _ = create_gaussian_splat_geometry(
            s[0].copy(), s[1].copy(), s[2].copy(), [1, 2]
        )
    with assert_raises(contains="must be contiguous"):
        _ = create_gaussian_splat_geometry(
            s[0].copy(),
            s[1].copy(),
            s[2].copy(),
            List[UInt8](),
            packed_band(2, 2),
        )
    with assert_raises(contains="must be contiguous"):
        _ = create_gaussian_splat_geometry(
            s[0].copy(),
            s[1].copy(),
            s[2].copy(),
            packed_band(2, 1),
            List[UInt8](),
            packed_band(2, 3),
        )


def full_geometry() raises -> GaussianSplatGeometry:
    """Return two splats of every band, each band's bytes counting up."""
    var s = two_splats()
    var bands = List[List[UInt8]]()
    for degree in range(1, 4):
        var band = packed_band(2, degree)
        for at in range(len(band)):
            band[at] = UInt8((at * 7 + degree) % 256)
        bands.append(band^)
    return create_gaussian_splat_geometry(
        s[0].copy(),
        s[1].copy(),
        s[2].copy(),
        bands[0].copy(),
        bands[1].copy(),
        bands[2].copy(),
    )


def test_a_geometry_reads_its_bands() raises:
    var s = two_splats()
    var plain = create_gaussian_splat_geometry(
        s[0].copy(), s[1].copy(), s[2].copy()
    )
    assert_equal(plain.count(), 2)
    assert_equal(plain.spherical_harmonics_degree(), 0)
    var one = create_gaussian_splat_geometry(
        s[0].copy(), s[1].copy(), s[2].copy(), packed_band(2, 1)
    )
    assert_equal(one.spherical_harmonics_degree(), 1)
    var two = create_gaussian_splat_geometry(
        s[0].copy(),
        s[1].copy(),
        s[2].copy(),
        packed_band(2, 1),
        packed_band(2, 2),
    )
    assert_equal(two.spherical_harmonics_degree(), 2)
    var full = full_geometry()
    assert_equal(full.spherical_harmonics_degree(), 3)
    assert_equal(Int(full.band_byte(1, 1, 2)), (14 * 7 + 1) % 256)
    assert_equal(Int(full.band_byte(2, 0, 14)), (14 * 7 + 2) % 256)
    assert_equal(Int(full.band_byte(3, 1, 20)), (44 * 7 + 3) % 256)
    with assert_raises(contains="no spherical harmonics band 0"):
        _ = full.band_byte(0, 0, 0)
    with assert_raises(contains="no spherical harmonics band 2"):
        _ = one.band_byte(2, 0, 0)
    with assert_raises(contains="no splat -1"):
        _ = full.band_byte(1, -1, 0)
    with assert_raises(contains="no splat 2"):
        _ = full.band_byte(1, 2, 0)
    with assert_raises(contains="no band number -1"):
        _ = full.band_byte(1, 0, -1)
    with assert_raises(contains="no band number 9"):
        _ = full.band_byte(1, 0, 9)


def test_a_geometry_goes_to_a_buffer_geometry_and_back() raises:
    var full = full_geometry()
    var geometry = full.to_buffer_geometry()
    assert_equal(spherical_harmonics_degree(geometry), 3)
    assert_equal(geometry.attribute_view("sphericalHarmonics2").item_size, 4)
    var back = gaussian_splat_geometry_of(geometry)
    assert_equal(len(back.centers), 6)
    assert_equal(back.covariances[11], 0.25)
    for at in range(8):
        assert_equal(Int(back.colors[at]), at + 1)
    for at in range(len(full.sh3)):
        assert_equal(Int(back.sh3[at]), Int(full.sh3[at]))
    var s = two_splats()
    var plain = create_gaussian_splat_geometry(
        s[0].copy(), s[1].copy(), s[2].copy()
    )
    assert_equal(
        gaussian_splat_geometry_of(
            plain.to_buffer_geometry()
        ).spherical_harmonics_degree(),
        0,
    )


def test_no_splats_go_to_a_buffer_geometry_and_back() raises:
    var none = GaussianSplatGeometry().to_buffer_geometry()
    assert_equal(gaussian_splat_geometry_of(none).count(), 0)
    # A band of no words, beside no splats.
    var bare = BufferGeometry()
    bare.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    bare.set_attribute(String(COVARIANCE), BufferAttribute(List[Float32](), 6))
    bare.set_attribute(
        String(COLOR), BufferAttribute(List[Int](), 4, UINT8_COMPONENT, True)
    )
    bare.set_attribute(
        "sphericalHarmonics1", BufferAttribute(List[Int](), 3, UINT32_COMPONENT)
    )
    assert_equal(spherical_harmonics_degree(bare), 1)
    assert_equal(
        gaussian_splat_geometry_of(bare).spherical_harmonics_degree(), 0
    )


def test_a_buffer_geometry_of_bad_bands_is_refused() raises:
    var wide = BufferGeometry()
    wide.set_attribute(
        "sphericalHarmonics1",
        BufferAttribute([1, 2, 3, 4], 4, UINT32_COMPONENT),
    )
    with assert_raises(contains="invalid sphericalHarmonics1 item size"):
        _ = spherical_harmonics_degree(wide)
    var floats = BufferGeometry()
    floats.set_attribute(
        "sphericalHarmonics1", BufferAttribute([1, 2, 3], 3, FLOAT32_COMPONENT)
    )
    with assert_raises(contains="must use packed 32-bit words"):
        _ = spherical_harmonics_degree(floats)
    var gap = BufferGeometry()
    gap.set_attribute(
        "sphericalHarmonics2",
        BufferAttribute([1, 2, 3, 4], 4, UINT32_COMPONENT),
    )
    with assert_raises(contains="must be contiguous"):
        _ = spherical_harmonics_degree(gap)
    var bare = BufferGeometry()
    bare.set_attribute(
        "sphericalHarmonics1", BufferAttribute([1, 2, 3], 3, UINT32_COMPONENT)
    )
    assert_equal(spherical_harmonics_degree(bare), 1)
    bare.set_attribute(String(POSITION), BufferAttribute([0, 0, 0, 1, 1, 1], 3))
    with assert_raises(contains="counts must match position"):
        _ = spherical_harmonics_degree(bare)


def test_a_buffer_geometry_of_bad_attributes_is_refused() raises:
    var s = two_splats()
    var plain = create_gaussian_splat_geometry(
        s[0].copy(), s[1].copy(), s[2].copy()
    )
    var position = plain.to_buffer_geometry()
    position.set_attribute(String(POSITION), BufferAttribute([0, 0, 0, 0], 2))
    with assert_raises(contains="position must have three components"):
        _ = gaussian_splat_geometry_of(position)
    var covariance = plain.to_buffer_geometry()
    covariance.set_attribute(
        String(COVARIANCE), BufferAttribute(List[Float32](length=10, fill=0), 5)
    )
    with assert_raises(contains="covariance must have six components"):
        _ = gaussian_splat_geometry_of(covariance)
    var color = plain.to_buffer_geometry()
    color.set_attribute(String(COLOR), BufferAttribute([0, 0, 0, 0, 0, 0], 3))
    with assert_raises(contains="color must have four components"):
        _ = gaussian_splat_geometry_of(color)


# --- the object ---------------------------------------------------------------------


def place_four(mut scene: Scene) raises -> NodeId:
    """Add the node `make_splats.mjs` placed `four.splat` at, and update."""
    var holder = Object3D()
    holder.set_position(0.5, -0.25, 0.1)
    holder.set_rotation(
        Euler(Angle(0.2, RADIAN), Angle(0.4, RADIAN), Angle(-0.1, RADIAN), XYZ)
    )
    holder.set_scale(1.5, 1.5, 1.5)
    var node = scene.add(holder^)
    scene.update()
    return node


def four(node: NodeId) raises -> GaussianSplat:
    """Return `four.splat` at a node."""
    return GaussianSplat(read_splat("assets/gaussian_splat/four.splat"), node)


def test_an_object_needs_a_node() raises:
    with assert_raises(contains="must name a scene node"):
        _ = GaussianSplat(GaussianSplatGeometry(), NodeId(-1))
    var splat = GaussianSplat(full_geometry(), NodeId(0), auto_sort=False)
    assert_equal(splat.count(), 2)
    assert_false(splat.auto_sort)
    assert_equal(splat.order[1], 1)


def test_regularized_bounds_enclose_independent_covariance_references() raises:
    var scene = Scene()
    var splat = four(place_four(scene))
    splat.compute_bounding_sphere()
    var box = splat.bounding_box.value()
    var low = List[Float64](length=3, fill=1e100)
    var high = List[Float64](length=3, fill=-1e100)
    ref c = splat.splat_geometry.covariances
    ref centers = splat.splat_geometry.centers
    for i in range(splat.count()):
        var largest = max(
            Float64(c[6 * i]), max(Float64(c[6 * i + 3]), Float64(c[6 * i + 5]))
        )
        # Independent exact picking contract: C + max(diag(C))*1e-4 I.
        var reach = 2 * sqrt(largest * 1.0001)
        for axis in range(3):
            var center = Float64(centers[3 * i + axis])
            low[axis] = min(low[axis], center - reach)
            high[axis] = max(high[axis], center + reach)
    var stored_low = [box.min.x, box.min.y, box.min.z]
    var stored_high = [box.max.x, box.max.y, box.max.z]
    for axis in range(3):
        assert_true(Float64(stored_low[axis]) <= low[axis])
        assert_true(Float64(stored_high[axis]) >= high[axis])
        assert_almost_equal(
            Float64(stored_low[axis]), low[axis], atol=1e-6, rtol=0
        )
        assert_almost_equal(
            Float64(stored_high[axis]), high[axis], atol=1e-6, rtol=0
        )
    var sphere = splat.bounding_sphere.value()
    var expected = Float64(0)
    for i in range(splat.count()):
        var diagonal = max(
            Float64(c[6 * i]), max(Float64(c[6 * i + 3]), Float64(c[6 * i + 5]))
        )
        var floor_variance = diagonal * 1e-4
        var rows = [
            abs(Float64(c[6 * i]) + floor_variance)
            + abs(Float64(c[6 * i + 1]))
            + abs(Float64(c[6 * i + 2])),
            abs(Float64(c[6 * i + 3]) + floor_variance)
            + abs(Float64(c[6 * i + 1]))
            + abs(Float64(c[6 * i + 4])),
            abs(Float64(c[6 * i + 5]) + floor_variance)
            + abs(Float64(c[6 * i + 2]))
            + abs(Float64(c[6 * i + 4])),
        ]
        var x = Float64(centers[3 * i]) - Float64(sphere.center.x)
        var y = Float64(centers[3 * i + 1]) - Float64(sphere.center.y)
        var z = Float64(centers[3 * i + 2]) - Float64(sphere.center.z)
        expected = max(
            expected,
            sqrt(x * x + y * y + z * z)
            + 2 * sqrt(max(rows[0], max(rows[1], rows[2]))),
        )
    assert_true(Float64(sphere.radius) >= expected)
    assert_almost_equal(Float64(sphere.radius), expected, atol=1e-6, rtol=0)


def test_no_splats_have_an_empty_box() raises:
    var splat = GaussianSplat(GaussianSplatGeometry(), NodeId(0))
    splat.compute_bounding_box()
    assert_true(splat.bounding_box.value().is_empty())
    splat.compute_bounding_sphere()
    assert_equal(splat.bounding_sphere.value().radius, 0)
    splat.sort_cpu()
    assert_equal(len(splat.order), 0)


def test_the_raycast_is_three_js_raycast() raises:
    var scene = Scene()
    var node = place_four(scene)
    var splat = four(node)
    var raycaster = Raycaster(
        Vector3(-3, 0.2, 0),
        Vector3(1, 0, 0.05),
        Length(0.1, METER),
        Length(100, METER),
    )
    var hits = splat.raycast(scene.world_matrix(node), raycaster)
    assert_equal(len(hits), 1)
    assert_equal(hits[0].index, 0)
    assert_almost_equal(
        Float64(hits[0].distance.value), 3.110851303434168, atol=1e-4
    )
    assert_almost_equal(
        Float64(hits[0].point.x), 0.10697001520606647, atol=1e-4
    )
    assert_almost_equal(Float64(hits[0].point.y), 0.2, atol=1e-4)
    assert_almost_equal(
        Float64(hits[0].point.z), 0.15534850076030327, atol=1e-4
    )


def geometry_of(
    centers: List[Float32], covariances: List[Float32], alphas: List[UInt8]
) raises -> GaussianSplatGeometry:
    """Return splats of these centers, covariances and opacities."""
    var colors = List[UInt8]()
    for alpha in alphas:
        colors.extend([UInt8(255), UInt8(255), UInt8(255), alpha])
    return create_gaussian_splat_geometry(
        centers.copy(), covariances.copy(), colors^
    )


def isotropic(variance: Float32) -> List[Float32]:
    """Return a round splat's covariance."""
    return [variance, 0, 0, variance, 0, variance]


def test_a_ray_that_misses_the_bounds_meets_nothing() raises:
    var covariances = isotropic(0.25)
    covariances.extend(isotropic(0.25))
    var splat = GaussianSplat(
        geometry_of([-5, 0, 0, 5, 0, 0], covariances, [255, 255]), NodeId(0)
    )
    var world = Matrix4()
    # Past the sphere, and through the sphere beside the box.
    var away = Raycaster(Vector3(-10, 30, 0), Vector3(1, 0, 0))
    assert_equal(len(splat.raycast(world, away)), 0)
    var beside = Raycaster(Vector3(-10, 3, 0), Vector3(1, 0, 0))
    assert_equal(len(splat.raycast(world, beside)), 0)


def test_the_raycast_skips_what_three_js_skips() raises:
    var centers: List[Float32] = [0, 0, 0, 1, 0, 0, 2, 5, 0, 3, 0, 0]
    centers.extend([4, 0.5, 0, 6, 0, 0])
    var covariances = isotropic(1)
    covariances.extend(List[Float32](length=6, fill=0))
    covariances.extend(isotropic(0.0001))
    covariances.extend([1, 2, 0, 1, 0, 1])
    covariances.extend([1, 0, 0, 0, 0, 0])
    covariances.extend(isotropic(0.25))
    var splat = GaussianSplat(
        geometry_of(centers, covariances, [10, 255, 255, 255, 255, 255]),
        NodeId(0),
    )
    var world = Matrix4()
    # Faint, flat, far, not positive, missed and met, in that order.
    var hits = splat.raycast(
        world, Raycaster(Vector3(-10, 0, 0), Vector3(1, 0, 0))
    )
    assert_equal(len(hits), 1)
    assert_equal(hits[0].index, 5)
    assert_almost_equal(Float64(hits[0].distance.value), 15, atol=1e-4)
    # From inside the last splat the far side is met.
    var inside = splat.raycast(
        world, Raycaster(Vector3(6, 0, 0), Vector3(1, 0, 0))
    )
    assert_equal(len(inside), 1)
    assert_almost_equal(Float64(inside[0].point.x), 7, atol=1e-4)
    # Too near and too far.
    var near = Raycaster(
        Vector3(-10, 0, 0), Vector3(1, 0, 0), Length(20, METER)
    )
    assert_equal(len(splat.raycast(world, near)), 0)
    var far = Raycaster(
        Vector3(-10, 0, 0), Vector3(1, 0, 0), Length(0, METER), Length(1, METER)
    )
    assert_equal(len(splat.raycast(world, far)), 0)


def test_a_splat_behind_the_ray_is_not_met() raises:
    var covariance: List[Float32] = [0.01, 0, 0, 1, 0, 1]
    var splat = GaussianSplat(
        geometry_of([6, 0, 0], covariance, [255]), NodeId(0)
    )
    var hits = splat.raycast(
        Matrix4(), Raycaster(Vector3(6.5, 0, 0), Vector3(1, 0, 0))
    )
    assert_equal(len(hits), 0)


def three_js_camera() raises -> PerspectiveCamera:
    """Return the camera `make_splats.mjs` sorted for."""
    var camera = PerspectiveCamera(
        Angle(50, DEGREE), 1.25, Length(0.5, METER), Length(40, METER)
    )
    camera.place(Vector3(1, 2, 9), Vector3(0, 0, 0))
    return camera^


def test_the_sort_order_matches_three_js_with_conservative_depth_range() raises:
    var scene = Scene()
    var node = place_four(scene)
    var splat = four(node)
    var camera = three_js_camera()
    var world = scene.world_matrix(node)
    var view = camera.view_matrix_in(scene)
    assert_true(splat.update_sort(world, view, Length(0.5, METER)))
    assert_almost_equal(splat.sort_near, 2.9617235371522153, atol=1e-4)
    assert_almost_equal(splat.sort_far, 14.181266220021453, atol=1e-4)
    var want: List[Int] = [1, 0, 2, 3]
    for at in range(4):
        assert_equal(splat.order[at], want[at])
    # The same view needs no sort; a turned one does.
    assert_false(splat.update_sort(world, view, Length(0.5, METER)))
    camera.place(Vector3(9, 2, 1), Vector3(0, 0, 0))
    view = camera.view_matrix_in(scene)
    assert_true(splat.update_sort(world, view, Length(0.5, METER)))


def test_a_depth_outside_the_range_goes_to_an_end_bin() raises:
    var splat = GaussianSplat(
        geometry_of(
            [0, 0, -1, 0, 0, -10],
            [1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1],
            [255, 255],
        ),
        NodeId(0),
    )
    splat.sort_near = 2
    splat.sort_far = 3
    assert_equal(splat.sort_bin(0), BIN_COUNT - 1)
    assert_equal(splat.sort_bin(1), 0)
    splat.sort_cpu()
    assert_equal(splat.order[0], 1)
    assert_equal(splat.order[1], 0)


def test_the_harmonics_turn_with_the_view() raises:
    var s = two_splats()
    var bands = List[List[UInt8]]()
    for degree in range(1, 4):
        bands.append(packed_band(2, degree))
    # Splat 0: the one coefficient each band weighs along +z.
    bands[0][3] = 192
    bands[0][4] = 64
    bands[1][6] = 160
    bands[2][9] = 255
    var centers: List[Float32] = [0, 0, 0, 0, 0, 0]
    var splat = GaussianSplat(
        create_gaussian_splat_geometry(
            centers^,
            s[1].copy(),
            s[2].copy(),
            bands[0].copy(),
            bands[1].copy(),
            bands[2].copy(),
        ),
        NodeId(0),
    )
    var rgb = splat.spherical_harmonics_colors(Vector3(0, 0, -5))
    assert_equal(len(rgb), 6)
    var second = Float32(0.25) * 0.3153915 * 2
    var third = Float32(127) / 128 * 0.3731763 * 2
    assert_almost_equal(rgb[0], 0.5 * 0.4886025 + second + third, atol=1e-6)
    assert_almost_equal(rgb[1], -0.5 * 0.4886025, atol=1e-6)
    assert_almost_equal(rgb[2], 0, atol=1e-6)
    # Seen from the side, every weight along z is zero.
    var side = splat.spherical_harmonics_colors(Vector3(-5, 0, 0))
    assert_almost_equal(side[1], 0, atol=1e-6)
    var none = GaussianSplat(
        create_gaussian_splat_geometry(s[0].copy(), s[1].copy(), s[2].copy()),
        NodeId(0),
    )
    assert_equal(len(none.spherical_harmonics_colors(Vector3(0, 0, 5))), 0)
    # One band alone.
    var first = GaussianSplat(
        create_gaussian_splat_geometry(
            [0, 0, 0, 0, 0, 0], s[1].copy(), s[2].copy(), bands[0].copy()
        ),
        NodeId(0),
    )
    var only = first.spherical_harmonics_colors(Vector3(0, 0, -5))
    assert_almost_equal(only[0], 0.5 * 0.4886025, atol=1e-6)


# --- the projection and the fragment ---------------------------------------------------


def straight_view(
    mode: DepthMode = STANDARD_DEPTH,
) raises -> SplatView:
    """Return a camera at the origin looking down -z, 90 degrees across a
    100 by 100 target, from 1 to 100 meters."""
    var camera = PerspectiveCamera(
        Angle(90, DEGREE), 1, Length(1, METER), Length(100, METER)
    )
    return SplatView(
        Matrix4(),
        camera.projection_matrix(),
        100,
        100,
        mode,
        log_depth_factor(100),
    )


def white() -> FloatRgba:
    """Return opaque white."""
    return FloatRgba(1, 1, 1, 1)


def test_a_round_splat_projects_to_its_closed_form() raises:
    var view = straight_view()
    var projected = project_splat(
        Vector3(0, 0, -5), isotropic(0.01), 0, white(), view
    ).value()
    assert_almost_equal(projected.x, 50, atol=1e-4)
    assert_almost_equal(projected.y, 50, atol=1e-4)
    # The focal length is 50 pixels, so the variance on the screen is
    # 50^2 * 0.01 / 5^2 = 1, and the filter adds 0.3.
    assert_almost_equal(projected.scale1, sqrt(Float32(1.3)), atol=1e-3)
    assert_almost_equal(projected.scale2, sqrt(Float32(1.3)), atol=1e-3)
    assert_almost_equal(projected.a, 1 / Float32(1.3), atol=1e-5)
    assert_almost_equal(projected.axis_x, 1, atol=1e-6)
    ref p = view.projection.elements
    assert_almost_equal(projected.depth, (p[10] * -5 + p[14]) / 5, atol=1e-6)


def test_a_long_splat_turns_its_axis() raises:
    var covariance: List[Float32] = [0.04, 0.03, 0, 0.04, 0, 0.01]
    var projected = project_splat(
        Vector3(1, -1, -5),
        covariance,
        0,
        FloatRgba(2, -1, 0.5, 0.5),
        straight_view(),
    ).value()
    # The long axis is the diagonal, up and to the right on the screen.
    assert_almost_equal(abs(projected.axis_x), abs(projected.axis_y), atol=0.1)
    assert_true(projected.scale1 > projected.scale2)
    assert_equal(projected.r, 1)
    assert_equal(projected.g, 0)
    assert_equal(projected.b, 0.5)


def test_a_huge_splat_is_held_to_the_largest_size() raises:
    var projected = project_splat(
        Vector3(0, 0, -1.5), isotropic(1e6), 0, white(), straight_view()
    ).value()
    assert_equal(projected.scale1, MAX_SCREEN_SPACE_SPLAT_SIZE)


def test_a_splat_off_the_screen_is_not_drawn() raises:
    var view = straight_view()
    var at: List[Vector3] = [
        Vector3(0, 0, 1),
        Vector3(0, 0, -0.5),
        Vector3(0, 0, -200),
        Vector3(-8, 0, -5),
        Vector3(8, 0, -5),
        Vector3(0, -8, -5),
        Vector3(0, 8, -5),
    ]
    for index in range(len(at)):
        assert_false(
            Bool(project_splat(at[index], isotropic(0.01), 0, white(), view))
        )
    # A center past the edge but within 1.4 w is kept.
    assert_true(
        Bool(
            project_splat(
                Vector3(6.9, 0, -5), isotropic(0.01), 0, white(), view
            )
        )
    )


def test_the_depth_is_stored_as_the_target_stores_it() raises:
    assert_equal(stored_splat_depth(STANDARD_DEPTH, 0.25, 4, 1), 0.25)
    assert_equal(stored_splat_depth(REVERSED_DEPTH, 0.5, 4, 1), 0.25)
    assert_almost_equal(
        stored_splat_depth(LOGARITHMIC_DEPTH, 0.5, 3, 0.5), 0.5 * 2 - 1
    )
    var logarithmic = project_splat(
        Vector3(0, 0, -5),
        isotropic(0.01),
        0,
        white(),
        straight_view(LOGARITHMIC_DEPTH),
    ).value()
    assert_almost_equal(
        logarithmic.depth,
        log_depth_factor(100) * log2(Float32(6)) - 1,
        atol=1e-5,
    )


def test_the_depth_test_is_less_or_equal() raises:
    assert_true(splat_depth_passes(STANDARD_DEPTH, 0.5, 0.5))
    assert_false(splat_depth_passes(STANDARD_DEPTH, 0.7, 0.5))
    assert_true(splat_depth_passes(REVERSED_DEPTH, 0.7, 0.5))
    assert_false(splat_depth_passes(REVERSED_DEPTH, 0.3, 0.5))


def unit_splat(x: Float32, y: Float32) -> ProjectedSplat:
    """Return an opaque red splat one pixel across each way, at depth 0."""
    return ProjectedSplat(x, y, 0, 1, 0, 1, 1, 1, 0, 0, 1)


def test_the_fragment_is_the_gaussian() raises:
    var splat = unit_splat(4, 4)
    # Pixel (3, 3) has its center half a pixel left of and above the
    # splat's: r^2 = 0.5.
    assert_almost_equal(splat_alpha(splat, 3, 3), exp(Float32(-0.25)))
    assert_almost_equal(splat_alpha(splat, 5, 4), exp(Float32(-1.25)))
    assert_equal(splat_alpha(splat, 0, 0), 0)
    var reach = splat_reach(splat)
    assert_equal(reach[0], 2)
    assert_equal(reach[1], 2)
    var flat = List[Float32]()
    splat.append_to(flat)
    assert_equal(len(flat), SPLAT_FLOATS)
    assert_equal(flat[7], 1)


def test_splats_blend_into_a_target_behind_what_is_nearer() raises:
    var target = RenderTarget(8, 8, Color(0, 0, 0, 255))
    target.depth[3 * 8 + 4] = -0.5
    rasterize_splats(target, [unit_splat(4, 4), unit_splat(0, 0)])
    assert_almost_equal(target.color_at(3, 3).r, exp(Float32(-0.25)), atol=1e-6)
    # Nearer than the splat, so the splat is hidden there.
    assert_equal(target.color_at(4, 3).r, 0)
    assert_equal(target.color_at(7, 7).r, 0)
    # The splat in the corner is cut by the edge.
    assert_almost_equal(target.color_at(0, 0).r, exp(Float32(-0.25)), atol=1e-6)
    # No splats, and splats wholly above and left of the target, draw
    # nothing.
    rasterize_splats(target, List[ProjectedSplat]())
    rasterize_splats(target, [unit_splat(4, -100), unit_splat(-100, 4)])
    assert_equal(target.color_at(4, 0).r, 0)
    target.depth_mode = DepthMode(7)
    with assert_raises(contains="valid depth mode"):
        rasterize_splats(target, List[ProjectedSplat]())


def one_red_splat(scene: Scene, node: NodeId) raises -> GaussianSplat:
    """Return one opaque red splat at the node's origin."""
    var colors: List[UInt8] = [255, 0, 0, 255]
    return GaussianSplat(
        create_gaussian_splat_geometry([0, 0, 0], isotropic(1), colors^), node
    )


def test_a_splat_draws_in_a_scene() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var camera = PerspectiveCamera(
        Angle(90, DEGREE), 1, Length(1, METER), Length(100, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var splat = one_red_splat(scene, node)
    var target = RenderTarget(16, 16, Color(0, 0, 0, 255))
    draw_gaussian_splat(target, scene, splat, camera)
    assert_true(target.color_at(8, 8).r > 0.4)
    assert_equal(target.color_at(0, 0).r, 0)
    assert_true(splat.sort_initialized)
    with assert_raises(contains="valid depth mode"):
        _ = prepare_gaussian_splat(scene, splat, camera, 16, 16, DepthMode(9))


def test_a_hidden_splat_is_not_drawn_and_one_not_sorted_keeps_its_order() raises:
    var scene = Scene()
    var hidden = Object3D()
    hidden.visible = False
    var node = scene.add(hidden^)
    var shown = scene.add(Object3D())
    scene.update()
    var camera = PerspectiveCamera(
        Angle(90, DEGREE), 1, Length(1, METER), Length(100, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var splat = one_red_splat(scene, node)
    assert_equal(
        len(
            prepare_gaussian_splat(scene, splat, camera, 16, 16, STANDARD_DEPTH)
        ),
        0,
    )
    var still = GaussianSplat(full_geometry(), shown, auto_sort=False)
    var projected = prepare_gaussian_splat(
        scene, still, camera, 16, 16, STANDARD_DEPTH
    )
    var nothing = GaussianSplat(GaussianSplatGeometry(), shown)
    assert_equal(
        len(
            prepare_gaussian_splat(
                scene, nothing, camera, 16, 16, STANDARD_DEPTH
            )
        ),
        0,
    )
    assert_false(still.sort_initialized)
    assert_equal(still.order[0], 0)
    # The second splat is level with the camera, so it is not drawn.
    assert_equal(len(projected), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
