# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.surface_sampler`, three.js's `MeshSurfaceSampler`.

The surface is four triangles of different sizes on six vertices. The
expected values were calculated by three.js 0.180, by node on
`examples/jsm/math/MeshSurfaceSampler.js`, with `MathUtils.seededRandom`
seeded with 11 as the random generator: the running totals, and the
triangle, point, normal, color and texture coordinates of four samples.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, NORMAL, POSITION, UV
from geometries.surface_sampler import MeshSurfaceSampler, SurfaceSample
from math.utils import SeededRandom
from math.vector3 import Vector3
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(2e-6)

comptime INDEX: List[Int] = [0, 1, 2, 2, 1, 3, 2, 3, 4, 4, 3, 5]


def spread(values: List[Float32], size: Int) -> List[Float32]:
    """Return per-vertex values laid out along the index, for the geometry
    with no index."""
    var out = List[Float32]()
    for vertex in materialize[INDEX]():
        for k in range(size):
            out.append(values[vertex * size + k])
    return out^


def surface(indexed: Bool, attributes: Bool) raises -> BufferGeometry:
    """Return the reference script's surface."""
    var positions: List[Float32] = [
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        1,
        0,
        2,
        1,
        0,
        0,
        3,
        1,
        3,
        3,
        2,
    ]
    var normals: List[Float32] = [
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        1,
        1,
        1,
    ]
    var colors: List[Float32] = [
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        1,
        1,
        0,
        0,
        1,
        1,
        1,
        0,
        1,
    ]
    var uvs: List[Float32] = [0, 0, 1, 0, 0, 1, 1, 1, 0.5, 0.5, 0.25, 0.75]
    var weights: List[Float32] = [1, 2, 0, 3, 0.5, 4]
    if not indexed:
        positions = spread(positions, 3)
        normals = spread(normals, 3)
        colors = spread(colors, 3)
        uvs = spread(uvs, 2)
        weights = spread(weights, 1)
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    if attributes:
        geometry.set_attribute(NORMAL, BufferAttribute(normals^, 3))
        geometry.set_attribute(COLOR, BufferAttribute(colors^, 3))
        geometry.set_attribute(UV, BufferAttribute(uvs^, 2))
    geometry.set_attribute("weight", BufferAttribute(weights^, 1))
    if indexed:
        geometry.set_index(materialize[INDEX]())
    return geometry^


def assert_vector(v: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a vector's components, within the tolerance."""
    assert_almost_equal(v.x, x, atol=TOLERANCE)
    assert_almost_equal(v.y, y, atol=TOLERANCE)
    assert_almost_equal(v.z, z, atol=TOLERANCE)


def assert_distribution(
    sampler: MeshSurfaceSampler, expected: List[Float32]
) raises:
    """Assert the running totals."""
    assert_equal(len(sampler.distribution), len(expected))
    for face in range(len(expected)):
        assert_almost_equal(
            sampler.distribution[face], expected[face], atol=TOLERANCE
        )


def assert_sample(
    sample: SurfaceSample,
    face: Int,
    position: Vector3,
    normal: Vector3,
    color: Vector3,
    uv_u: Float32,
    uv_v: Float32,
) raises:
    """Assert one sample, with its color and texture coordinates."""
    assert_equal(sample.face, face)
    assert_vector(sample.position, position.x, position.y, position.z)
    assert_vector(sample.normal, normal.x, normal.y, normal.z)
    assert_true(Bool(sample.color))
    assert_almost_equal(sample.color.value().r, color.x, atol=TOLERANCE)
    assert_almost_equal(sample.color.value().g, color.y, atol=TOLERANCE)
    assert_almost_equal(sample.color.value().b, color.z, atol=TOLERANCE)
    assert_almost_equal(sample.color.value().a, 1, atol=TOLERANCE)
    assert_true(Bool(sample.uv))
    assert_almost_equal(sample.uv.value().x, uv_u, atol=TOLERANCE)
    assert_almost_equal(sample.uv.value().y, uv_v, atol=TOLERANCE)


def test_indexed_surface_matches_three() raises:
    """Area alone, interpolated normals, colors and texture coordinates."""
    var sampler = MeshSurfaceSampler(surface(True, True), SeededRandom(11))
    sampler.build()
    assert_distribution(sampler, [1, 2, 4.23606777, 8.26719666])
    assert_sample(
        sampler.sample(),
        2,
        Vector3(0.783762872, 1.27612996, 0.138064966),
        Vector3(0.334255785, 0.400932819, 0.852951288),
        Vector3(0.391881436, 0.529946387, 0.608118594),
        0.460913926,
        0.930967510,
    )
    assert_sample(
        sampler.sample(),
        3,
        Vector3(2.09035230, 2.07604456, 0.926821291),
        Vector3(0.621321857, 0.283939719, 0.730299532),
        Vector3(0.850776672, 0.611200988, 0.538022280),
        0.633789122,
        0.828188598,
    )
    assert_sample(
        sampler.sample(),
        0,
        Vector3(0.784526825, 0.138242096, 0),
        Vector3(0, 0.136939764, 0.990579367),
        Vector3(0.469494492, 0.392263412, 0.138242096),
        0.392263412,
        0.138242096,
    )
    assert_sample(
        sampler.sample(),
        2,
        Vector3(0.312958658, 1.64712632, 0.323563129),
        Vector3(0.137514547, 0.456940383, 0.878803313),
        Vector3(0.156479329, 0.480042458, 0.843520701),
        0.318260908,
        0.838218451,
    )


def test_bare_surface_matches_three() raises:
    """No index and no attributes: the face's own normal, no color."""
    var sampler = MeshSurfaceSampler(surface(False, False), SeededRandom(11))
    sampler.build()
    assert_equal(sampler.face_count(), 4)
    assert_distribution(sampler, [1, 2, 4.23606777, 8.26719666])
    var first = sampler.sample()
    assert_equal(first.face, 2)
    assert_vector(first.position, 0.783762872, 1.27612996, 0.138064966)
    assert_vector(first.normal, 0, -0.447213590, 0.894427180)
    assert_false(Bool(first.color))
    assert_false(Bool(first.uv))
    var second = sampler.sample()
    assert_equal(second.face, 3)
    assert_vector(second.position, 2.09035230, 2.07604456, 0.926821291)
    assert_vector(second.normal, -0.248069465, -0.620173693, 0.744208395)
    var third = sampler.sample()
    assert_equal(third.face, 0)
    assert_vector(third.normal, 0, 0, 1)


def test_weighted_surface_matches_three() raises:
    """A weight attribute scales each triangle's area."""
    var sampler = MeshSurfaceSampler(surface(True, True), SeededRandom(11))
    sampler.set_weight_attribute(String("weight"))
    sampler.build()
    assert_distribution(sampler, [3, 8, 15.8262386, 46.0597038])
    assert_sample(
        sampler.sample(),
        3,
        Vector3(1.19795775, 2.21623707, 0.746183515),
        Vector3(0.464810699, 0.121095411, 0.877090037),
        Vector3(0.529946387, 0.861935019, 0.608118594),
        0.661424458,
        0.730456948,
    )
    _ = sampler.sample()
    assert_sample(
        sampler.sample(),
        1,
        Vector3(1.06101108, 0.607736588, 0),
        Vector3(0.124168299, 0.421697408, 0.898194611),
        Vector3(0.138242096, 0.530505538, 0.469494492),
        0.530505538,
        0.607736588,
    )
    # Back to area alone.
    sampler.set_weight_attribute(None)
    sampler.build()
    assert_distribution(sampler, [1, 2, 4.23606777, 8.26719666])


def test_the_seed_picks_the_points() raises:
    """The same seed gives the same points; another seed, others."""
    var one = MeshSurfaceSampler(surface(True, True), SeededRandom(3))
    var two = MeshSurfaceSampler(surface(True, True), SeededRandom(3))
    one.build()
    two.build()
    for _ in range(20):
        var a = one.sample()
        var b = two.sample()
        assert_equal(a.face, b.face)
        assert_equal(a.position.x, b.position.x)
    two.set_random_generator(SeededRandom(4))
    var differs = False
    for _ in range(5):
        if one.sample().position.x != two.sample().position.x:
            differs = True
    assert_true(differs)


def test_a_weight_of_zero_is_never_chosen() raises:
    """Every sample lands on a triangle with weight."""
    var sampler = MeshSurfaceSampler(surface(True, True), SeededRandom(5))
    var geometry = surface(True, True)
    var weights: List[Float32] = [0, 0, 0, 0, 0, 1]
    geometry.set_attribute("weight", BufferAttribute(weights^, 1))
    sampler = MeshSurfaceSampler(geometry, SeededRandom(5))
    sampler.set_weight_attribute(String("weight"))
    sampler.build()
    for _ in range(50):
        assert_equal(sampler.sample().face, 3)


def test_binary_search_finds_each_share() raises:
    """The search finds the first and last shares, and a sample of one
    triangle is on it."""
    var sampler = MeshSurfaceSampler(surface(True, True), SeededRandom(1))
    sampler.build()
    var sample = sampler.sample_face(1)
    assert_equal(sample.face, 1)
    with assert_raises(contains="No triangle"):
        _ = sampler.sample_face(4)
    with assert_raises(contains="No triangle"):
        _ = sampler.sample_face(-1)
    var single = BufferGeometry()
    var three: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    single.set_attribute(POSITION, BufferAttribute(three^, 3))
    var one = MeshSurfaceSampler(single, SeededRandom(1))
    one.build()
    assert_equal(one.sample().face, 0)


def test_a_number_past_the_total_finds_no_triangle() raises:
    """The search gives -1 for a number no share holds, and a sampler of
    no triangles builds and refuses to sample."""
    var sampler = MeshSurfaceSampler(surface(True, True), SeededRandom(1))
    sampler.build()
    assert_equal(sampler._binary_search(9), -1)
    assert_equal(sampler._binary_search(0), 0)
    assert_equal(sampler._binary_search(8), 3)
    var empty = BufferGeometry()
    empty.set_attribute(POSITION, BufferAttribute(List[Float32](), 3))
    var nothing = MeshSurfaceSampler(empty, SeededRandom(1))
    nothing.build()
    assert_equal(len(nothing.distribution), 0)
    with assert_raises(contains="Build"):
        _ = nothing.sample()


def test_refusals() raises:
    """What three.js reads past or cannot choose from is refused."""
    with assert_raises(contains="positions"):
        _ = MeshSurfaceSampler(BufferGeometry(), SeededRandom(1))
    var sampler = MeshSurfaceSampler(surface(True, True), SeededRandom(1))
    with assert_raises(contains="no attribute"):
        sampler.set_weight_attribute(String("mass"))
    with assert_raises(contains="Build"):
        _ = sampler.sample()
    # Positions that do not make whole triangles.
    var ragged = BufferGeometry()
    var four: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0]
    ragged.set_attribute(POSITION, BufferAttribute(four^, 3))
    var bad = MeshSurfaceSampler(ragged, SeededRandom(1))
    with assert_raises(contains="whole triangles"):
        bad.build()
    # A negative weight, and one that is not a number.
    var negative = surface(True, True)
    var minus: List[Float32] = [-1, -1, -1, -1, -1, -1]
    negative.set_attribute("weight", BufferAttribute(minus^, 1))
    var weighed = MeshSurfaceSampler(negative, SeededRandom(1))
    weighed.set_weight_attribute(String("weight"))
    with assert_raises(contains="weight"):
        weighed.build()
    var odd = surface(True, True)
    var nans = List[Float32](length=6, fill=nan[DType.float32]())
    odd.set_attribute("weight", BufferAttribute(nans^, 1))
    var weighed_odd = MeshSurfaceSampler(odd, SeededRandom(1))
    weighed_odd.set_weight_attribute(String("weight"))
    with assert_raises(contains="weight"):
        weighed_odd.build()
    # No weight at all.
    var zero = surface(True, True)
    var zeros: List[Float32] = [0, 0, 0, 0, 0, 0]
    zero.set_attribute("weight", BufferAttribute(zeros^, 1))
    var none = MeshSurfaceSampler(zero, SeededRandom(1))
    none.set_weight_attribute(String("weight"))
    none.build()
    with assert_raises(contains="weight"):
        _ = none.sample()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
