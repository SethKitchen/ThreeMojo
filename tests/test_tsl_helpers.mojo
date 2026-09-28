# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `materials.tsl_helpers`: a ray marched through a box, soft
particles and the GGX sampling helpers.

Each expected value is worked out from three.js's formula, the GGX ones
in `assets/tsl/tsl_reference.py`, and read back through the compiled
program.
"""

from materials.nodes import (
    FRAGMENT_NODE,
    MASK_NODE,
    NODE_FLOAT,
    NODE_VEC2,
    NODE_VEC3,
    NodeGraph,
    NodeInputs,
    NodeRef,
    ProgramSource,
    run_nodes,
)
from materials.tsl_helpers import (
    ENV_RAY_LENGTH,
    ENV_RAY_LENGTH_THRESHOLD,
    RaymarchingBox,
    contrast_curve,
    d_gtr,
    equirect_dir_pdf,
    equirect_uv_to_dir,
    f_schlick,
    geometry_term,
    get_specular_dominant_factor,
    ggx_reflection_sample,
    ggx_vndf_pdf,
    mis_power_heuristic,
    perspective_depth_to_view_z,
    raymarch_count,
    sample_ggx_vndf,
    smith_g,
    soft_particles,
)
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Length, METER, SECOND, Duration

comptime Lanes = SIMD[DType.float32, 4]


def at(position: Vector3) -> NodeInputs:
    """Return a fragment at a world position, facing `+z`."""
    var none = Vector3(0, 0, 0)
    return NodeInputs(0, 0, position, Vector3(0, 0, 1), none, none, False)


def value_of(
    mut g: NodeGraph, node: NodeRef, place: Vector3 = Vector3(1, 2, 3)
) raises -> Lanes:
    """Return a node's value, padded to a `vec4`, through the fragment
    output, from a camera at the origin."""
    var type = g.type_of(node)
    var shown = node
    if type == NODE_FLOAT:
        shown = g.join([node, g.vec3(0, 0, 0)])
    elif type == NODE_VEC2:
        shown = g.join([node, g.vec2(0, 0)])
    elif type == NODE_VEC3:
        shown = g.join([node, g.float(0)])
    g.set_output(FRAGMENT_NODE, shown)
    var program = g.compile()
    program.set_frame(Duration(0.0, SECOND), Matrix4())
    return run_nodes(
        ProgramSource(Pointer(to=program)), FRAGMENT_NODE, at(place)
    )


def assert_near(
    got: Lanes, expected: List[Float32], tolerance: Float64 = 1e-5
) raises:
    """Assert as many lanes as `expected` has."""
    for index in range(len(expected)):
        assert_almost_equal(got[index], expected[index], atol=tolerance)


def marched(world_to_local: Matrix4) raises -> List[Lanes]:
    """Return the sum of the ray's positions and the count of steps of a
    march of four steps, and the mask, for the fragment at (1, 2, 3)."""
    var g = NodeGraph()
    var to_local = g.uniform("toLocal", world_to_local)
    var steps = g.Var(g.float(0))
    var total = g.Var(g.vec3(0, 0, 0))
    var march = RaymarchingBox(g, 4, to_local)
    g.assign(steps, g.add(g.get(steps), g.float(1)))
    g.assign(total, g.add(g.get(total), g.get(march.position_ray)))
    march.End(g)
    g.set_output(FRAGMENT_NODE, g.join([g.get(total), g.get(steps)]))
    var program = g.compile()
    program.set_frame(Duration(0.0, SECOND), Matrix4())
    var source = ProgramSource(Pointer(to=program))
    var place = at(Vector3(1, 2, 3))
    return [
        run_nodes(source, FRAGMENT_NODE, place),
        run_nodes(source, MASK_NODE, place),
    ]


def test_a_ray_marches_through_the_box_and_stops_where_it_leaves() raises:
    # The camera is inside the box, so the ray starts at it. It looks along
    # (1, 2, 3), leaves through z = 0.5, and a step is a quarter of that.
    var inside = marched(Matrix4())
    assert_near(inside[0], [1.0 / 12, 2.0 / 12, 3.0 / 12, 2])
    assert_equal(inside[1][0], 1)
    # Moved ten meters away along x, the ray misses the box and the
    # fragment is thrown away.
    var away = Matrix4()
    away.elements[12] = -10
    assert_equal(marched(away)[1][0], 0)
    assert_equal(raymarch_count(4), 8)


def test_a_march_refuses_a_count_or_a_matrix_it_cannot_run() raises:
    var g = NodeGraph()
    var to_local = g.uniform("toLocal", Matrix4())
    with assert_raises(contains="from one step to 1024 times"):
        _ = RaymarchingBox(g, 0, to_local)
    with assert_raises(contains="not 600 steps"):
        _ = RaymarchingBox(g, 600, to_local)
    with assert_raises(contains="matrix reads a mat4, not a vec3"):
        _ = RaymarchingBox(g, 4, g.vec3(1, 2, 3))


def test_soft_particles_fade_near_the_scene_behind() raises:
    var g = NodeGraph()
    var near = g.float(1)
    var far = g.float(11)
    assert_near(
        value_of(g, perspective_depth_to_view_z(g, g.float(0.5), near, far)),
        [-11.0 / 6],
    )
    assert_near(
        value_of(g, contrast_curve(g, g.float(0.25), g.float(2))), [0.125]
    )
    assert_near(
        value_of(g, contrast_curve(g, g.float(0.75), g.float(2))), [0.875]
    )
    assert_near(value_of(g, contrast_curve(g, g.float(0.5), g.float(2))), [0.5])
    # The scene is at z = -2.5 and the particle at z = -2: a quarter of the
    # distance of two, which the curve makes 0.125.
    var faded = soft_particles(
        g,
        g.float(0.66),
        Length(1.0, METER),
        Length(11.0, METER),
        g.float(0.8),
        Length(2.0, METER),
    )
    assert_near(value_of(g, faded, Vector3(0, 0, -2)), [0.1])
    # Well in front of the scene, the particle keeps its opacity.
    var kept = soft_particles(
        g, g.float(0.66), Length(1.0, METER), Length(11.0, METER)
    )
    assert_near(value_of(g, kept, Vector3(0, 0, -1)), [1])


def test_soft_particles_refuse_a_wrong_camera_or_distance() raises:
    var g = NodeGraph()
    var depth = g.float(0.5)
    with assert_raises(contains="needs 0 < near < far"):
        _ = soft_particles(g, depth, Length(0.0, METER), Length(1.0, METER))
    with assert_raises(contains="needs 0 < near < far"):
        _ = soft_particles(g, depth, Length(2.0, METER), Length(1.0, METER))
    with assert_raises(contains="a distance above zero"):
        _ = soft_particles(
            g,
            depth,
            Length(1.0, METER),
            Length(2.0, METER),
            distance=Length(0.0, METER),
        )
    with assert_raises(contains="softParticles reads a float, not a vec2"):
        _ = soft_particles(
            g, g.vec2(1, 2), Length(1.0, METER), Length(2.0, METER)
        )
    with assert_raises(contains="contrastCurve reads a float, not a vec3"):
        _ = contrast_curve(g, g.vec3(1, 2, 3), g.float(2))


def test_the_ggx_helpers_are_three_js_numbers() raises:
    var g = NodeGraph()
    assert_near(
        value_of(
            g,
            sample_ggx_vndf(
                g,
                g.vec3(0.3, 0.2, 0.9327379),
                g.float(0.4),
                g.float(0.4),
                g.float(0.25),
                g.float(0.6),
            ),
        ),
        [0.04973072186112404, 0.4235121011734009, 0.9045243263244629],
    )
    assert_near(
        value_of(g, d_gtr(g, g.float(0.5), g.float(0.8), g.float(2))),
        [0.29429537057876587],
    )
    assert_near(
        value_of(g, smith_g(g, g.float(0.7), g.float(0.3))),
        [0.9776181578636169],
    )
    assert_near(
        value_of(g, geometry_term(g, g.float(0.7), g.float(0.5), g.float(0.3))),
        [0.9192708],
    )
    assert_near(
        value_of(g, ggx_vndf_pdf(g, g.float(0.9), g.float(0.6), g.float(0.4))),
        [0.21213679015636444],
    )
    assert_near(
        value_of(g, f_schlick(g, g.vec3(0.04, 0.5, 1), g.float(0.2))),
        [0.3545728, 0.66384, 1],
    )
    assert_near(
        value_of(
            g, get_specular_dominant_factor(g, g.float(0.5), g.float(0.3))
        ),
        [0.9914836287498474],
    )
    assert_near(
        value_of(g, mis_power_heuristic(g, g.float(0.3), g.float(0.4))),
        [0.36],
    )
    assert_equal(ENV_RAY_LENGTH.to(METER), 1e4)
    assert_equal(ENV_RAY_LENGTH_THRESHOLD.to(METER), 1e3)


def test_a_ggx_reflection_sample_is_three_js_numbers() raises:
    var g = NodeGraph()
    var sample = ggx_reflection_sample(
        g,
        g.vec3(0, 0.6, 0.8),
        g.vec3(0.28, 0, 0.96),
        g.float(0.5),
        g.float(0.3),
        g.vec3(0.9, 0.5, 0.2),
        g.vec2(0.3, 0.7),
    )
    assert_near(
        value_of(g, sample.reflect_dir),
        [-0.021214423701167107, 0.46544983983039856, 0.8848199248313904],
    )
    assert_near(
        value_of(g, sample.sample_weight),
        [0.28680139780044556, 0.17131094634532928, 0.08469309657812119],
    )
    assert_near(value_of(g, sample.pdf), [0.14168685674667358])
    assert_near(value_of(g, sample.n_dot_v), [0.768])
    assert_near(value_of(g, sample.alpha), [0.25])
    assert_near(value_of(g, sample.f0), [0.298, 0.178, 0.088])
    # A normal along +z takes the second frame; the sample stays unit.
    var up = ggx_reflection_sample(
        g,
        g.vec3(0, 0, 1),
        g.vec3(0, 0, 1),
        g.float(0.5),
        g.float(0),
        g.vec3(1, 1, 1),
        g.vec2(0.3, 0.7),
    )
    var l = value_of(g, up.reflect_dir)
    assert_almost_equal(l[0] * l[0] + l[1] * l[1] + l[2] * l[2], 1, atol=1e-5)


def test_the_equirectangular_helpers_are_three_js_numbers() raises:
    var g = NodeGraph()
    assert_near(
        value_of(g, equirect_uv_to_dir(g, g.vec2(0.75, 0.5))), [0, 0, 1]
    )
    assert_near(
        value_of(g, equirect_uv_to_dir(g, g.vec2(0.5, 0.75))),
        [0.70710677, 0.70710677, 0],
    )
    assert_near(value_of(g, equirect_dir_pdf(g, g.vec3(1, 0, 0))), [0.05066059])
    # At a pole the density is zero.
    assert_near(value_of(g, equirect_dir_pdf(g, g.vec3(0, 1, 0))), [0])


def test_the_ggx_helpers_refuse_a_wrong_type() raises:
    var g = NodeGraph()
    var one = g.float(1)
    with assert_raises(contains="SampleGGXVNDF reads a vec3, not a float"):
        _ = sample_ggx_vndf(g, one, one, one, one, one)
    with assert_raises(contains="SampleGGXVNDF reads a float, not a vec2"):
        _ = sample_ggx_vndf(g, g.vec3(0, 0, 1), one, one, one, g.vec2(1, 2))
    with assert_raises(contains="D_GTR reads a float, not a vec2"):
        _ = d_gtr(g, g.vec2(1, 2), one, one)
    with assert_raises(contains="SmithG reads a float, not a vec2"):
        _ = geometry_term(g, one, g.vec2(1, 2), one)
    with assert_raises(contains="GGXVNDFPdf reads a float, not a vec2"):
        _ = ggx_vndf_pdf(g, one, one, g.vec2(1, 2))
    with assert_raises(contains="F_Schlick reads a vec3, not a float"):
        _ = f_schlick(g, one, one)
    with assert_raises(contains="F_Schlick's theta reads a float, not a vec3"):
        _ = f_schlick(g, g.vec3(1, 1, 1), g.vec3(1, 1, 1))
    with assert_raises(contains="getSpecularDominantFactor reads a float"):
        _ = get_specular_dominant_factor(g, g.vec2(1, 2), one)
    with assert_raises(contains="misPowerHeuristic reads a float"):
        _ = mis_power_heuristic(g, one, g.vec2(1, 2))
    with assert_raises(contains="equirectUvToDir reads a vec2, not a vec3"):
        _ = equirect_uv_to_dir(g, g.vec3(1, 2, 3))
    with assert_raises(contains="equirectDirPdf reads a vec3, not a vec2"):
        _ = equirect_dir_pdf(g, g.vec2(1, 2))
    with assert_raises(contains="perspectiveDepthToViewZ reads a float"):
        _ = perspective_depth_to_view_z(g, g.vec2(1, 2), one, one)
    var n = g.vec3(0, 0, 1)
    var rgb = g.vec3(1, 1, 1)
    var xi = g.vec2(0.5, 0.5)
    with assert_raises(contains="normal reads a vec3, not a float"):
        _ = ggx_reflection_sample(g, one, n, one, one, rgb, xi)
    with assert_raises(contains="view reads a vec3, not a float"):
        _ = ggx_reflection_sample(g, n, one, one, one, rgb, xi)
    with assert_raises(contains="albedo reads a vec3, not a float"):
        _ = ggx_reflection_sample(g, n, n, one, one, one, xi)
    with assert_raises(contains="random numbers reads a vec2, not a float"):
        _ = ggx_reflection_sample(g, n, n, one, one, rgb, one)
    with assert_raises(
        contains="ggxReflectionSample reads a float, not a vec2"
    ):
        _ = ggx_reflection_sample(g, n, n, xi, one, rgb, xi)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
