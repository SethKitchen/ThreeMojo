# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `VolumeNodeMaterial` and its
`VolumetricLightingModel`: a ray marched through a mesh, which gathers the
point and spot lights at each step."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import directional_light, point_light, spot_light
from lights.lighting import Lighting, falloff, shadowed_twice
from materials.material import (
    BACK_SIDE,
    BLEND,
    DEFAULT_STEPS,
    LAMBERT,
    VOLUME,
    Material,
)
from materials.nodes import (
    EMISSIVE_NODE,
    NO_NODES,
    NodeGraph,
    NodeInputs,
    NodeProgram,
    NodeProgramId,
    OFFSET_NODE,
    ProgramSource,
    SCATTERING_NODE,
)
from materials.volume_node_material import (
    DENSITY_SCALE,
    LitRay,
    RayLights,
    volume_node_material,
    volumetric_light,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from render.rasterizer import SHADE_UV, check_triangle_state
from renderers.renderer import Renderer
from std.math import exp, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

# Odd, so the middle pixel's center is on the camera's axis.
comptime SIZE = 15


@fieldwise_init
struct AboveHalf(ImplicitlyCopyable, RayLights):
    """A light of (100, 50, 0) wherever a step is above z = 0.5, and none
    below."""

    def light_at(self, position: Vector3) -> Vector3:
        """Return the light at one step.

        Args:
            position: Where the step is.

        Returns:
            The light.
        """
        if position.z > 0.5:
            return Vector3(100, 50, 0)
        return Vector3(0, 0, 0)


def empty_program() raises -> NodeProgram:
    """Return a program that sets one output nobody reads here."""
    var graph = NodeGraph()
    graph.set_output(EMISSIVE_NODE, graph.vec3(0, 0, 0))
    return graph.compile()


def at_surface() -> NodeInputs:
    """Return a fragment at the origin."""
    var here = Vector3(0, 0, 0)
    return NodeInputs(0, 0, here, Vector3(0, 0, 1), here, here, False)


def test_a_far_camera_sends_the_ray_from_itself() raises:
    # The camera is two meters out, farther than twice a radius of a half:
    # the ray runs from it down to the surface, four steps of a half, at
    # z = 2, 1.5, 1 and 0.5. Three are above a half, and each thins the
    # red by exp(-100 * 0.01 * 0.5).
    var program = empty_program()
    var ray = volumetric_light(
        AboveHalf(),
        ProgramSource(Pointer(to=program)),
        False,
        at_surface(),
        Vector3(0, 0, 2),
        0.5,
        4,
        0,
    )
    assert_almost_equal(ray.x, 1 - exp(Float32(-1.5)), atol=1e-6)
    assert_almost_equal(ray.y, 1 - exp(Float32(-0.75)), atol=1e-6)
    assert_equal(ray.z, 0)
    assert_equal(DENSITY_SCALE, Float32(0.01))


def test_a_near_camera_sends_the_ray_from_the_surface() raises:
    # A radius of two puts the camera inside twice it: the ray runs from
    # the surface up, at z = 0, 0.5, 1 and 1.5. Two are above a half.
    var program = empty_program()
    var ray = volumetric_light(
        AboveHalf(),
        ProgramSource(Pointer(to=program)),
        False,
        at_surface(),
        Vector3(0, 0, 2),
        2,
        4,
        0,
    )
    assert_almost_equal(ray.x, 1 - exp(Float32(-1.0)), atol=1e-6)
    # An offset of a whole step starts it at z = 0.5: three are above.
    var moved = volumetric_light(
        AboveHalf(),
        ProgramSource(Pointer(to=program)),
        False,
        at_surface(),
        Vector3(0, 0, 2),
        2,
        4,
        1,
    )
    assert_almost_equal(moved.x, 1 - exp(Float32(-1.5)), atol=1e-6)


def test_the_scattering_node_reads_the_step_s_position() raises:
    # A density times the step's height: 2, 1.5 and 1 above a half, so the
    # red is thinned by exp(-(2 + 1.5 + 1) * 100 * 0.01 * 0.5).
    var graph = NodeGraph()
    graph.set_output(
        SCATTERING_NODE, graph.swizzle(graph.position_world(), "z")
    )
    var program = graph.compile()
    var ray = volumetric_light(
        AboveHalf(),
        ProgramSource(Pointer(to=program)),
        True,
        at_surface(),
        Vector3(0, 0, 2),
        0.5,
        4,
        0,
    )
    assert_almost_equal(ray.x, 1 - exp(Float32(-2.25)), atol=1e-6)


def test_a_step_gathers_the_bulbs_and_the_spots() raises:
    var scene = Scene()
    var bulb = Object3D()
    bulb.set_position(0, 0, 0)
    scene.add_light(point_light(Color(255, 255, 255), scene.add(bulb^), 2.0))
    var lamp = Object3D()
    lamp.set_position(0, 3, 0)
    scene.add_light(
        spot_light(
            Color(255, 0, 0),
            scene.add(lamp^),
            1.0,
            angle=Angle(30.0, DEGREE),
            penumbra=0.1,
        )
    )
    var sun = Object3D()
    sun.set_position(0, 1, 0)
    scene.add_light(directional_light(Color(255, 255, 255), scene.add(sun^)))
    scene.update()
    var lighting = Lighting(scene, eye=Vector3(0, 0, 5))
    var up = Vector3(0, 1, 0)
    # One meter under the spot, on its axis, and one from the bulb. The
    # sun adds nothing: it has no distance.
    var light = lighting.volume_light_at(Vector3(0, 2, 0), up, True)
    var bulb_part = 2 * falloff(2, 2, 0)
    assert_almost_equal(light.x, bulb_part + 1, atol=1e-5)
    assert_almost_equal(light.y, bulb_part, atol=1e-5)
    # On the bulb, its falloff's floor; on the spot, no direction and no
    # light from it.
    var on_bulb = lighting.volume_light_at(Vector3(0, 0, 0), up, True)
    assert_almost_equal(on_bulb.y, 2 * falloff(0, 2, 0), atol=1e-3)
    var on_spot = lighting.volume_light_at(Vector3(0, 3, 0), up, True)
    assert_almost_equal(on_spot.x, on_spot.y, atol=1e-5)
    # Outside the cone the spot adds nothing.
    var aside = lighting.volume_light_at(Vector3(3, 2, 0), up, True)
    assert_almost_equal(aside.x, aside.y, atol=1e-5)


def test_a_shadow_darkens_a_step_twice() raises:
    var light = shadowed_twice(Vector3(1, 2, 4), 0.5, Vector3(0.5, 1, 0))
    assert_almost_equal(light.x, 0.125)
    assert_almost_equal(light.y, 1)
    assert_equal(light.z, 0)


def test_the_material_is_three_js_s() raises:
    var material = volume_node_material()
    assert_true(material.kind == VOLUME)
    assert_true(material.side == BACK_SIDE)
    assert_true(material.blending == BLEND)
    assert_false(material.depth_test)
    assert_false(material.depth_write)
    assert_equal(material.steps, DEFAULT_STEPS)
    assert_equal(DEFAULT_STEPS, 25)
    assert_equal(volume_node_material(steps=7).steps, 7)
    assert_true(VOLUME.is_valid())
    assert_false(VOLUME.is_lit())
    assert_false(VOLUME.displaces())
    assert_true(VOLUME.takes_nodes())
    assert_false(VOLUME.has_normal())


def test_a_volume_refuses_what_it_cannot_use() raises:
    with assert_raises(contains="at least one step"):
        _ = volume_node_material(steps=0)
    var lambert = Material(Color(200, 200, 200), kind=LAMBERT)
    with assert_raises(contains="Only a VOLUME material marches a ray"):
        lambert.set_steps(4)
    with assert_raises(contains="no emissive term"):
        _ = Material(
            Color(255, 255, 255), kind=VOLUME, emissive=Color(20, 20, 20)
        )


def box_of_light(
    mut assets: Assets, material: Material, bulb: Float32 = 1
) raises -> Scene:
    """Return a two-meter box of the material, with a white bulb at its
    center."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(cube(Length(2.0, METER))),
            assets.materials.add(material),
            node,
        )
    )
    var lamp = Object3D()
    scene.add_light(
        point_light(Color(255, 255, 255), scene.add(lamp^), bulb)
    )
    scene.update()
    return scene^


def camera_at(z: Float32) raises -> PerspectiveCamera:
    """Return a camera up the z axis, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, z), Vector3(0, 0, 0))
    return camera^


def middle_of(
    mut assets: Assets, scene: Scene, z: Float32, uv: Bool = False
) raises -> Color:
    """Return the middle pixel, seen from `z` up the axis."""
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    if uv:
        renderer.set_shading(SHADE_UV)
    return renderer.render(scene, assets, camera_at(z)).get_pixel(
        SIZE // 2, SIZE // 2
    )


def test_a_box_gathers_its_bulb_along_the_ray() raises:
    # The camera four meters out sees the far face at z = -1, five meters
    # away and farther than twice the box's radius, the square root of
    # three. Five steps of one meter from the camera sit 4, 3, 2, 1 and 0
    # meters from the bulb: 1/16 + 1/9 + 1/4 + 1 + 100, the last its
    # falloff's floor.
    var assets = Assets()
    var scene = box_of_light(assets, volume_node_material(steps=5))
    var density = (
        Float32(1) / 16 + Float32(1) / 9 + Float32(1) / 4 + 1 + falloff(0, 2, 0)
    )
    var through = 1 - exp(-density * DENSITY_SCALE)
    var expected = FloatColor(through, through, through).encode()
    var seen = middle_of(assets, scene, 4)
    assert_true(abs(Int(seen.r) - Int(expected.r)) <= 1)
    assert_true(abs(Int(seen.b) - Int(expected.b)) <= 1)


def test_a_camera_inside_marches_from_the_surface() raises:
    # From half a meter up the axis the far face is a meter and a half
    # away: the ray runs from it back to the camera, as `volumetric_light`
    # works it out from the lights.
    var assets = Assets()
    var scene = box_of_light(assets, volume_node_material(steps=5))
    var lighting = Lighting(scene, eye=Vector3(0, 0, 0.5))
    var program = empty_program()
    var ray = volumetric_light(
        LitRay(Pointer(to=lighting), Vector3(0, 0, -1), True),
        ProgramSource(Pointer(to=program)),
        False,
        NodeInputs(
            0,
            0,
            Vector3(0, 0, -1),
            Vector3(0, 0, -1),
            Vector3(1, 1, 1),
            Vector3(0, 0, 0),
            False,
        ),
        Vector3(0, 0, 0.5),
        sqrt(Float32(3)),
        5,
        0,
    )
    var expected = FloatColor(ray.x, ray.y, ray.z).encode()
    var seen = middle_of(assets, scene, 0.5)
    assert_true(abs(Int(seen.g) - Int(expected.g)) <= 1)
    assert_true(Int(seen.g) > 0)


def test_a_graph_scatters_offsets_and_glows() raises:
    # A graph with no light at all in its scattering node sees nothing but
    # its glow; the offset moves the start and changes nothing then.
    var assets = Assets()
    var graph = NodeGraph()
    graph.set_output(SCATTERING_NODE, graph.float(0))
    graph.set_output(OFFSET_NODE, graph.float(0.5))
    graph.set_output(EMISSIVE_NODE, graph.vec3(0.2158605, 0, 0))
    var dark = assets.programs.add(graph.compile())
    var seen = middle_of(
        assets, box_of_light(assets, volume_node_material(nodes=dark)), 4
    )
    assert_true(abs(Int(seen.r) - 128) <= 1)
    assert_equal(Int(seen.g), 0)
    # A graph with only an offset still scatters the bulb's light.
    var other = NodeGraph()
    other.set_output(OFFSET_NODE, other.float(0.5))
    var moved = assets.programs.add(other.compile())
    var lit = middle_of(
        assets, box_of_light(assets, volume_node_material(nodes=moved)), 4
    )
    assert_true(Int(lit.g) > 0)


def test_the_uv_view_shows_no_ray() raises:
    var assets = Assets()
    var scene = box_of_light(assets, volume_node_material(), 0)
    var lit = middle_of(assets, scene, 4)
    assert_equal(Int(lit.g), 0)
    var uv = middle_of(assets, scene, 4, uv=True)
    assert_true(Int(uv.r) + Int(uv.g) > 0)


def test_the_renderer_and_the_rasterizer_refuse_a_ray_of_no_steps() raises:
    var assets = Assets()
    var material = volume_node_material()
    material.steps = 0
    var scene = box_of_light(assets, material)
    with assert_raises(contains="at least one step"):
        _ = middle_of(assets, scene, 4)
    var fine = Assets()
    var good = box_of_light(fine, volume_node_material(steps=3))
    var corners = Renderer(SIZE, SIZE).prepare(good, fine, camera_at(4))
    assert_equal(corners[0].steps, 3)
    assert_almost_equal(corners[0].model_radius, sqrt(Float32(3)))
    check_triangle_state(corners[0], corners[1], corners[2])
    corners[0].steps = 0
    with assert_raises(contains="at least one step"):
        check_triangle_state(corners[0], corners[1], corners[2])
    corners[0].steps = 3
    corners[0].model_radius = -1
    with assert_raises(contains="bounding radius cannot be negative"):
        check_triangle_state(corners[0], corners[1], corners[2])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
