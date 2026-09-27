# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a material that shapes the shadows it receives, three.js's
`receivedShadowNode`: the shadow leaf, the output, and a frame whose
surfaces shape the shadows of a sun, a spot and a bulb."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import ambient_light, directional_light, point_light, spot_light
from lights.shadow import Unshaped
from materials.material import (
    Material,
    phong_material,
    standard_material,
    toon_material,
)
from materials.nodes import (
    COLOR_NODE,
    MASK_NODE,
    NO_NODES,
    RECEIVED_SHADOW_NODE,
    NodeGraph,
    NodeInputs,
    ProgramShape,
    ProgramSource,
    run_nodes,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Angle, DEGREE, Length, METER


comptime WIDTH = 48
comptime HEIGHT = 36


def a_fragment() -> NodeInputs:
    """Return a fragment with no attribute of note."""
    var zero = Vector3(0, 0, 0)
    return NodeInputs(0, 0, zero, zero, zero, zero, False)


def test_only_a_received_shadow_node_reads_the_shadow() raises:
    var graph = NodeGraph()
    var shadow = graph.shadow()
    graph.set_output(COLOR_NODE, graph.join([shadow, shadow, shadow]))
    with assert_raises(contains="Only a received shadow node reads"):
        _ = graph.compile()
    var varied = NodeGraph()
    var passed = varied.varying(varied.shadow())
    varied.set_output(
        RECEIVED_SHADOW_NODE, varied.join([passed, passed, passed])
    )
    with assert_raises(contains="cannot read the lit color or the shadow"):
        _ = varied.compile()


def test_a_shape_runs_the_output_on_each_shadow() raises:
    # Red where the shadow falls and white where it does not: three.js's
    # `shadow.mix( color( 0xff0000 ), 1 )`.
    var graph = NodeGraph()
    var shadow = graph.shadow()
    graph.set_output(
        RECEIVED_SHADOW_NODE,
        graph.join([graph.float(1), shadow, shadow]),
    )
    var program = graph.compile()
    var source = ProgramSource(Pointer(to=program))
    var shape = ProgramShape(source, a_fragment(), True)
    var half = shape.shaped(0.5)
    assert_equal(half.x, 1)
    assert_equal(half.y, 0.5)
    assert_equal(half.z, 0.5)
    # A program that sets no such output keeps the shadow as it falls.
    var idle = ProgramShape(source, a_fragment(), False)
    assert_equal(idle.shaped(0.25).x, 0.25)
    assert_equal(idle.shaped(0.25).z, 0.25)
    assert_equal(Unshaped().shaped(0.75).y, 0.75)
    # The leaf reads what the fragment was handed.
    var given = a_fragment()
    given.shadow = 0.125
    assert_equal(run_nodes(source, RECEIVED_SHADOW_NODE, given)[1], 0.125)


def a_shadowed_scene(
    mut assets: Assets, floor_paint: Material, block_paint: Material
) raises -> Scene:
    """Return a floor and a block above it, both receiving, under a sun, a
    spot and a bulb that all cast."""
    var scene = Scene()
    var ground = Object3D()
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var lift = Object3D()
    lift.set_position(0, 1.0, 0)
    var lift_node = scene.add(lift^)
    var floor = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER), 2, 2)
    )
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var floor_id = assets.materials.add(floor_paint)
    var block_id = assets.materials.add(block_paint)
    scene.add_mesh(Mesh(floor, floor_id, ground_node, receive_shadow=True))
    scene.add_mesh(
        Mesh(block, block_id, lift_node, cast_shadow=True, receive_shadow=True)
    )
    var lamp = Object3D()
    lamp.set_position(-3, 4, 0)
    var lamp_node = scene.add(lamp^)
    var sun = directional_light(Color(255, 250, 240), lamp_node, 2.5)
    sun.cast_shadow = True
    sun.shadow.map_size = 48
    sun.shadow.bias = -0.002
    scene.add_light(sun)
    var beam = Object3D()
    beam.set_position(2.5, 4, 1)
    var beam_node = scene.add(beam^)
    var spot = spot_light(
        Color(200, 220, 255), beam_node, 30.0, angle=Angle(45.0, DEGREE)
    )
    spot.cast_shadow = True
    spot.shadow.map_size = 32
    spot.shadow.normal_bias = 0.02
    scene.add_light(spot)
    var bulb = Object3D()
    bulb.set_position(0.5, 3, -2)
    var bulb_node = scene.add(bulb^)
    var glow = point_light(Color(255, 230, 200), bulb_node, 20.0)
    glow.cast_shadow = True
    glow.shadow.map_size = 16
    scene.add_light(glow)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.15))
    scene.update()
    return scene^


def a_camera() raises -> PerspectiveCamera:
    """Return a camera above and in front of the block."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(50.0, METER),
    )
    camera.place(Vector3(1, 5, 5), Vector3(0, 0, 0))
    return camera^


def red_shadows() raises -> NodeGraph:
    """Return a graph that turns each shadow red, three.js's
    `shadow.mix( color( 0xff0000 ), 1 )`."""
    var graph = NodeGraph()
    var shadow = graph.shadow()
    graph.set_output(
        RECEIVED_SHADOW_NODE,
        graph.join([graph.float(1), shadow, shadow]),
    )
    return graph^


def as_it_falls() raises -> NodeGraph:
    """Return a graph that hands each shadow back as it is."""
    var graph = NodeGraph()
    var shadow = graph.shadow()
    graph.set_output(
        RECEIVED_SHADOW_NODE, graph.join([shadow, shadow, shadow])
    )
    return graph^


def no_shadows() raises -> NodeGraph:
    """Return a graph that lets every light through, three.js's
    `return float( 1 )`."""
    var graph = NodeGraph()
    graph.set_output(RECEIVED_SHADOW_NODE, graph.vec3(1, 1, 1))
    return graph^


def paints() raises -> List[Material]:
    """Return a surface of each kind of lighting: Lambert, Phong, toon and
    physical."""
    return [
        Material(Color(200, 200, 200)),
        phong_material(Color(200, 200, 200), specular=Color(80, 80, 80)),
        toon_material(Color(200, 200, 200)),
        standard_material(Color(200, 200, 200), roughness=0.5),
    ]


def drawn(
    paint: Material, shaped: Bool, graph: NodeGraph
) raises -> Framebuffer:
    """Return the scene with `paint` on the floor and the block, shaped by
    `graph` when `shaped`."""
    var assets = Assets()
    var named = NO_NODES
    if shaped:
        named = assets.programs.add(graph.compile())
    var painted = paint.copy()
    painted.nodes = named
    var scene = a_shadowed_scene(assets, painted, painted)
    var renderer = Renderer(WIDTH, HEIGHT)
    return renderer.render(scene, assets, a_camera())


def unreceived(paint: Material) raises -> Framebuffer:
    """Return the scene with `paint` on surfaces that receive no shadow."""
    var assets = Assets()
    var scene = a_shadowed_scene(assets, paint, paint)
    for index in range(len(scene.meshes)):
        scene.meshes[index].receive_shadow = False
    var renderer = Renderer(WIDTH, HEIGHT)
    return renderer.render(scene, assets, a_camera())


def differences(a: Framebuffer, b: Framebuffer) raises -> Int:
    """Return how many pixels differ at all."""
    var count = 0
    for y in range(a.height):
        for x in range(a.width):
            var p = a.get_pixel(x, y)
            var q = b.get_pixel(x, y)
            if p.r != q.r or p.g != q.g or p.b != q.b:
                count += 1
    return count


def test_a_shadow_handed_back_as_it_falls_changes_nothing() raises:
    for paint in paints():
        var plain = drawn(paint, False, NodeGraph())
        var shaped = drawn(paint, True, as_it_falls())
        assert_equal(differences(plain, shaped), 0)


def test_a_shadow_shaped_to_one_is_no_shadow() raises:
    for paint in paints():
        var shaped = drawn(paint, True, no_shadows())
        assert_equal(differences(unreceived(paint), shaped), 0)
        # And the shadows were there to take away.
        var plain = drawn(paint, False, NodeGraph())
        assert_true(differences(plain, shaped) > 20, "no shadow fell")


def test_a_shadow_can_be_turned_red() raises:
    for paint in paints():
        var plain = drawn(paint, False, NodeGraph())
        var red = drawn(paint, True, red_shadows())
        # Where a shadow fell, red comes through and green and blue do not.
        var redder = 0
        for y in range(HEIGHT):
            for x in range(WIDTH):
                var was = plain.get_pixel(x, y)
                var now = red.get_pixel(x, y)
                assert_equal(now.g, was.g)
                assert_equal(now.b, was.b)
                if now.r > was.r:
                    redder += 1
        assert_true(redder > 20, "no shadow turned red")


def test_a_caster_masked_away_casts_no_shadow() raises:
    # The light's view runs the caster's graph as the camera's does: where
    # its mask throws the block away, no shadow is cast.
    var assets = Assets()
    var graph = NodeGraph()
    graph.set_output(MASK_NODE, graph.float(0))
    var hidden = Material(Color(200, 200, 200))
    hidden.nodes = assets.programs.add(graph.compile())
    var scene = a_shadowed_scene(assets, Material(Color(200, 200, 200)), hidden)
    var renderer = Renderer(WIDTH, HEIGHT)
    var masked = renderer.render(scene, assets, a_camera())
    scene.meshes[1].cast_shadow = False
    var uncast = renderer.render(scene, assets, a_camera())
    assert_equal(differences(masked, uncast), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
