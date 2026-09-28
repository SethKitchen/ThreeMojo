# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `MeshSSSNodeMaterial`: a `PHYSICAL` surface whose
graph sets the thickness color lets a light behind it through."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import directional_light
from lights.lighting import Reflected
from loaders.node_loader import node_output_of, plain_material_type
from materials.material import PHYSICAL, STANDARD, Material, MaterialKind
from materials.mesh_sss_node_material import (
    DEFAULT_THICKNESS_AMBIENT,
    DEFAULT_THICKNESS_ATTENUATION,
    DEFAULT_THICKNESS_DISTORTION,
    DEFAULT_THICKNESS_POWER,
    DEFAULT_THICKNESS_SCALE,
    Thickness,
    scatters,
    subsurface_diffuse,
    thickness_of,
)
from materials.nodes import (
    NO_NODES,
    NODE_OUTPUT_COUNT,
    NodeGraph,
    NodeInputs,
    NodeOutput,
    NodeProgram,
    NodeProgramId,
    OFFSET_NODE,
    ProgramSource,
    SCATTERING_NODE,
    THICKNESS_AMBIENT_NODE,
    THICKNESS_ATTENUATION_NODE,
    THICKNESS_COLOR_NODE,
    THICKNESS_DISTORTION_NODE,
    THICKNESS_POWER_NODE,
    THICKNESS_SCALE_NODE,
    NODE_FLOAT,
    NODE_VEC3,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 16
# sRGB 128, linear: what a gray of 0x80 decodes to.
comptime GRAY = Float32(0.21586050011389926)


def only_color(gray: Float32) raises -> NodeProgram:
    """Return a graph that sets the thickness color alone."""
    var graph = NodeGraph()
    graph.set_output(THICKNESS_COLOR_NODE, graph.vec3(gray, gray, gray))
    return graph.compile()


def every_number(gray: Float32) raises -> NodeProgram:
    """Return a graph that sets all six thickness nodes: no power term, an
    ambient of one and an attenuation of one, so the light through is the
    color times the light."""
    var graph = NodeGraph()
    graph.set_output(THICKNESS_COLOR_NODE, graph.vec3(gray, gray, gray))
    graph.set_output(THICKNESS_DISTORTION_NODE, graph.float(0.3))
    graph.set_output(THICKNESS_AMBIENT_NODE, graph.float(1))
    graph.set_output(THICKNESS_ATTENUATION_NODE, graph.float(1))
    graph.set_output(THICKNESS_POWER_NODE, graph.float(3))
    graph.set_output(THICKNESS_SCALE_NODE, graph.float(0))
    return graph.compile()


def lit_from_behind(
    mut assets: Assets, kind: MaterialKind, nodes: NodeProgramId
) raises -> Scene:
    """Return a square facing the camera, with only a sun behind it,
    straight on its axis."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(2.0, METER), Length(2.0, METER))
            ),
            assets.materials.add(
                Material(
                    Color(200, 200, 200),
                    kind=kind,
                    roughness=1,
                    metalness=0,
                    nodes=nodes,
                )
            ),
            node,
        )
    )
    var lamp = Object3D()
    lamp.set_position(0, 0, -2)
    scene.add_light(
        directional_light(Color(255, 255, 255), scene.add(lamp^), 1.0)
    )
    scene.update()
    return scene^


def middle_of(mut assets: Assets, scene: Scene) raises -> Color:
    """Return the middle pixel of the square, seen from four meters."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    return renderer.render(scene, assets, camera).get_pixel(
        SIZE // 2, SIZE // 2
    )



def test_a_sun_behind_a_physical_surface_shows_through() raises:
    # With no graph the sun behind the square leaves it dark. With the
    # thickness color alone, the way to the sun, bent a tenth along the
    # normal, is straight away from the camera: the light through is 10
    # at three.js's default scale, times the default attenuation, a tenth,
    # times the sun, one. So the square shows the color, sRGB 128. It is
    # added outside the one over pi of the diffuse lobe.
    var assets = Assets()
    assert_equal(
        middle_of(assets, lit_from_behind(assets, PHYSICAL, NO_NODES)).r, 0
    )
    var alone = assets.programs.add(only_color(GRAY))
    var through = middle_of(assets, lit_from_behind(assets, PHYSICAL, alone))
    assert_equal(Int(through.r), 128)
    assert_equal(Int(through.b), 128)
    # Every number set: an ambient of one and an attenuation of one, and a
    # scale of zero, give the color times the sun once more.
    var all = assets.programs.add(every_number(GRAY))
    var set = middle_of(assets, lit_from_behind(assets, PHYSICAL, all))
    assert_equal(Int(set.g), 128)


def test_only_a_physical_surface_scatters() raises:
    # `MeshSSSNodeMaterial` extends the physical material: a standard
    # surface with the same graph shows nothing through.
    var assets = Assets()
    var alone = assets.programs.add(only_color(GRAY))
    assert_equal(
        middle_of(assets, lit_from_behind(assets, STANDARD, alone)).r, 0
    )
    var program = only_color(GRAY)
    var source = ProgramSource(Pointer(to=program))
    assert_true(scatters(source, True, PHYSICAL))
    assert_false(scatters(source, False, PHYSICAL))
    assert_false(scatters(source, True, STANDARD))
    var none = NodeGraph()
    none.set_output(THICKNESS_POWER_NODE, none.float(1))
    var numbers = none.compile()
    assert_false(scatters(ProgramSource(Pointer(to=numbers)), True, PHYSICAL))


def test_the_thickness_nodes_take_three_js_s_defaults() raises:
    var program = only_color(0.5)
    var source = ProgramSource(Pointer(to=program))
    var here = Vector3(0, 0, 0)
    var thickness = thickness_of(
        source, NodeInputs(0, 0, here, here, here, here, False)
    )
    assert_almost_equal(thickness.color.y, 0.5)
    assert_equal(thickness.distortion, DEFAULT_THICKNESS_DISTORTION)
    assert_equal(thickness.ambient, DEFAULT_THICKNESS_AMBIENT)
    assert_equal(thickness.attenuation, DEFAULT_THICKNESS_ATTENUATION)
    assert_equal(thickness.power, DEFAULT_THICKNESS_POWER)
    assert_equal(thickness.scale, DEFAULT_THICKNESS_SCALE)
    assert_almost_equal(DEFAULT_THICKNESS_DISTORTION, 0.1)
    assert_equal(DEFAULT_THICKNESS_POWER, 2)
    assert_equal(DEFAULT_THICKNESS_SCALE, 10)
    var every = every_number(0.5)
    var set = thickness_of(
        ProgramSource(Pointer(to=every)),
        NodeInputs(0, 0, here, here, here, here, False),
    )
    assert_almost_equal(set.distortion, 0.3)
    assert_equal(set.ambient, 1)
    assert_equal(set.attenuation, 1)
    assert_equal(set.power, 3)
    assert_equal(set.scale, 0)


def test_the_light_through_joins_the_direct_diffuse_light() raises:
    var direct = Reflected(
        Vector3(0.1, 0.2, 0.3),
        Vector3(0.4, 0.5, 0.6),
        Vector3(0.7, 0.8, 0.9),
        Vector3(0.05, 0.05, 0.05),
    )
    var thickness = Thickness(Vector3(1, 0.5, 0.25), 0.1, 0, 0.5, 2, 10)
    var summed = subsurface_diffuse(direct, Vector3(2, 2, 4), thickness)
    assert_almost_equal(summed.diffuse.x, 1.1)
    assert_almost_equal(summed.diffuse.y, 0.7)
    assert_almost_equal(summed.diffuse.z, 0.8)
    assert_almost_equal(summed.specular.y, 0.5)
    assert_almost_equal(summed.clearcoat.z, 0.9)
    assert_almost_equal(summed.sheen.x, 0.05)


def test_the_outputs_are_three_js_s_properties() raises:
    assert_equal(NODE_OUTPUT_COUNT, 25)
    assert_true(OFFSET_NODE.is_valid())
    assert_false(NodeOutput(NODE_OUTPUT_COUNT).is_valid())
    assert_true(THICKNESS_COLOR_NODE.value_type() == NODE_VEC3)
    for output in [
        THICKNESS_DISTORTION_NODE,
        THICKNESS_AMBIENT_NODE,
        THICKNESS_ATTENUATION_NODE,
        THICKNESS_POWER_NODE,
        THICKNESS_SCALE_NODE,
        SCATTERING_NODE,
        OFFSET_NODE,
    ]:
        assert_true(output.value_type() == NODE_FLOAT)
    var graph = NodeGraph()
    with assert_raises():
        graph.set_output(THICKNESS_COLOR_NODE, graph.float(1))
    assert_true(node_output_of("thicknessColorNode") == THICKNESS_COLOR_NODE)
    assert_true(node_output_of("thicknessScaleNode") == THICKNESS_SCALE_NODE)
    assert_true(node_output_of("scatteringNode") == SCATTERING_NODE)
    assert_true(node_output_of("offsetNode") == OFFSET_NODE)
    assert_equal(
        plain_material_type("MeshSSSNodeMaterial"), "MeshPhysicalMaterial"
    )
    assert_equal(
        plain_material_type("VolumeNodeMaterial"), "VolumeNodeMaterial"
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
