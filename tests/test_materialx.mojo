# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `MaterialXLoader`: standard surfaces with values
and graphs, unlit node graphs, images, and what is refused."""

from core.assets import Assets
from loaders.materialx import load_materialx, mtlx_numbers, read_materialx
from materials.material import BASIC, DOUBLE_SIDE, PHYSICAL
from materials.nodes import (
    COLOR_NODE,
    EMISSIVE_NODE,
    METALNESS_NODE,
    NORMAL_NODE,
    NO_NODES,
    OPACITY_NODE,
    ROUGHNESS_NODE,
    NodeInputs,
    ProgramSource,
    run_nodes,
)
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from render.png import encode as encode_png
from std.os import remove
from std.pathlib import Path
from units.si import DEGREE
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def at_uv(u: Float32, v: Float32) -> NodeInputs:
    """Return a fragment's inputs at a coordinate."""
    var none = Vector3(0, 0, 0)
    return NodeInputs(
        u, v, Vector3(1, 2, 3), Vector3(0, 0, 1), none, none, True
    )


def test_the_values_are_read_as_three_js_reads_them() raises:
    var numbers = mtlx_numbers("0.5, 1 |2 true false")
    assert_equal(len(numbers), 5)
    assert_equal(numbers[2], 2)
    assert_equal(numbers[3], 1)
    assert_equal(numbers[4], 0)


comptime SURFACE = """<?xml version="1.0"?>
<materialx version="1.38" colorspace="lin_rec709">
  <nodegraph name="NG_marble">
    <input name="scale" type="float" value="2.0" />
    <texcoord name="uv0" type="vector2" />
    <multiply name="scaled" type="vector2">
      <input name="in1" type="vector2" nodename="uv0" />
      <input name="in2" type="float" interfacename="scale" />
    </multiply>
    <separate2 name="parts" type="multioutput">
      <input name="in" type="vector2" nodename="scaled" />
    </separate2>
    <combine3 name="tint" type="color3">
      <input name="in1" type="float" nodename="parts" output="outx" />
      <input name="in2" type="float" nodename="parts" output="outy" />
      <input name="in3" type="float" value="0.25" />
    </combine3>
    <ramplr name="rough" type="float">
      <input name="valuel" type="float" value="0.2" />
      <input name="valuer" type="float" value="0.6" />
    </ramplr>
    <output name="color_out" type="color3" nodename="tint" />
    <output name="rough_out" type="float" nodename="rough" />
  </nodegraph>
  <standard_surface name="SR_marble" type="surfaceshader">
    <input name="base" type="float" value="0.5" />
    <input name="base_color" type="color3" nodegraph="NG_marble" output="color_out" />
    <input name="specular_roughness" type="float" nodegraph="NG_marble" output="rough_out" />
    <input name="metalness" type="float" value="0.3" />
    <input name="ior" type="float" value="1.4" />
    <input name="coat" type="float" value="0.5" />
    <input name="transmission" type="float" value="0.2" />
    <input name="emission" type="float" value="2.0" />
    <input name="emission_color" type="color3" value="0.1, 0.2, 0.3" />
  </standard_surface>
  <surfacematerial name="M_marble" type="material">
    <input name="surfaceshader" type="surfaceshader" nodename="SR_marble" />
  </surfacematerial>
</materialx>
"""


def test_a_standard_surface_is_a_physical_material() raises:
    var assets = Assets()
    var read = read_materialx(SURFACE, assets)
    assert_equal(len(read.names), 1)
    assert_equal(read.names[0], "M_marble")
    var material = assets.materials.get(read.ids[0])
    assert_true(material.kind == PHYSICAL)
    assert_almost_equal(material.metalness, 0.3)
    assert_almost_equal(material.ior, 1.4)
    assert_almost_equal(material.clearcoat, 0.5)
    assert_almost_equal(material.transmission, 0.2)
    assert_true(material.side == DOUBLE_SIDE)
    assert_true(material.transparent)
    ref program = assets.programs.get(material.nodes)
    var source = ProgramSource(Pointer(to=program))
    # The color: the base times the graph's color, the coordinates times
    # the scale in red and green.
    var color = run_nodes(source, COLOR_NODE, at_uv(0.25, 0.125))
    assert_almost_equal(color[0], 0.25)
    assert_almost_equal(color[1], 0.125)
    assert_almost_equal(color[2], 0.125)
    # The roughness a ramp across, from the graph.
    assert_almost_equal(
        run_nodes(source, ROUGHNESS_NODE, at_uv(0.5, 0))[0], 0.4
    )
    var glow = run_nodes(source, EMISSIVE_NODE, at_uv(0, 0))
    assert_almost_equal(glow[2], 0.6)
    assert_false(program.has(METALNESS_NODE))


comptime UNLIT = """<?xml version="1.0"?>
<materialx version="1.38">
  <nodegraph name="NG_checker">
    <position name="p" type="vector3" />
    <noise3d name="n" type="float">
      <input name="position" type="vector3" nodename="p" />
      <input name="amplitude" type="float" value="0.0" />
      <input name="pivot" type="float" value="0.5" />
    </noise3d>
    <ifgreater name="pick" type="color3">
      <input name="value1" type="float" nodename="n" />
      <input name="value2" type="float" value="0.25" />
      <input name="in1" type="color3" value="1, 0, 0" />
      <input name="in2" type="color3" value="0, 0, 1" />
    </ifgreater>
    <rgbtohsv name="hsv" type="color3">
      <input name="in" type="color3" nodename="pick" />
    </rgbtohsv>
    <hsvtorgb name="back" type="color3">
      <input name="in" type="color3" nodename="hsv" />
    </hsvtorgb>
    <output name="out" type="color3" nodename="back" />
  </nodegraph>
</materialx>
"""


def test_a_graph_with_no_surface_is_an_unlit_material() raises:
    var assets = Assets()
    var read = read_materialx(UNLIT, assets)
    assert_equal(read.names[0], "NG_checker")
    var material = assets.materials.get(read.ids[0])
    assert_true(material.kind == BASIC)
    ref program = assets.programs.get(material.nodes)
    var color = run_nodes(
        ProgramSource(Pointer(to=program)), COLOR_NODE, at_uv(0, 0)
    )
    # The noise is flattened to its pivot, above the threshold: red, and
    # back through hue, saturation and value unchanged.
    assert_almost_equal(color[0], 1, atol=1e-5)
    assert_almost_equal(color[1], 0, atol=1e-5)
    assert_almost_equal(color[2], 0, atol=1e-5)


comptime TILED = """<?xml version="1.0"?>
<materialx version="1.38">
  <tiledimage name="tile" type="color3">
    <input name="file" type="filename" value="threemojo_materialx_checker.png" colorspace="srgb_texture" />
    <input name="uvtiling" type="vector2" value="2, 2" />
  </tiledimage>
  <standard_surface name="SR" type="surfaceshader">
    <input name="base_color" type="color3" nodename="tile" />
    <input name="opacity" type="color3" value="0.5, 0.5, 0.5" />
  </standard_surface>
  <surfacematerial name="M" type="material">
    <input name="surfaceshader" type="surfaceshader" nodename="SR" />
  </surfacematerial>
</materialx>
"""


def test_an_image_is_read_from_beside_the_document() raises:
    var image = Framebuffer(2, 2, Color(255, 0, 0))
    image.set_pixel(1, 0, Color(0, 255, 0))
    image.set_pixel(0, 1, Color(0, 0, 255))
    var folder = "/tmp/threemojo_materialx_"
    Path(folder + "checker.png").write_bytes(encode_png(image))
    Path(folder + "tiled.mtlx").write_text(TILED)
    var assets = Assets()
    var read = load_materialx(folder + "tiled.mtlx", assets)
    assert_equal(assets.textures.count(), 1)
    var material = assets.materials.get(read.ids[0])
    ref program = assets.programs.get(material.nodes)
    assert_equal(program.textures[0].value, 0)
    assert_true(program.has(OPACITY_NODE))
    assert_true(material.transparent)


def test_what_is_not_ported_is_refused() raises:
    var assets = Assets()
    with assert_raises(contains="the node normalmap is not read"):
        _ = read_materialx(
            (
                '<materialx><nodegraph name="G"><normalmap name="n"'
                ' type="vector3" /><output name="out" type="color3"'
                ' nodename="n" /></nodegraph></materialx>'
            ),
            assets,
        )
    with assert_raises(contains="a graph that drives sheen is not ported"):
        _ = read_materialx(
            (
                '<materialx><nodegraph name="G"><constant name="c"'
                ' type="float"><input name="value" type="float" value="1"'
                ' /></constant><output name="o" type="float" nodename="c"'
                ' /></nodegraph><standard_surface name="S"'
                ' type="surfaceshader"><input name="sheen" type="float"'
                ' nodegraph="G" output="o"'
                ' /></standard_surface><surfacematerial name="M"'
                ' type="material"><input name="surfaceshader"'
                ' type="surfaceshader" nodename="S"'
                " /></surfacematerial></materialx>"
            ),
            assets,
        )
    with assert_raises(contains="nothing is named G/missing"):
        _ = read_materialx(
            (
                '<materialx><nodegraph name="G"><output name="out"'
                ' type="color3" nodename="missing" /></nodegraph></materialx>'
            ),
            assets,
        )


def test_every_node_of_the_library() raises:
    # Each node alone in a graph, its inputs values, read at the made-up
    # fragment: coordinates (0.25, 0.5), position (1, 2, 3), normal +z.
    var elements: List[String] = [
        "add",
        "subtract",
        "multiply",
        "divide",
        "modulo",
        "power",
        "atan2",
        "min",
        "max",
        "dotproduct",
        "crossproduct",
        "distance",
        "safepower",
        "absval",
        "sign",
        "floor",
        "ceil",
        "round",
        "sin",
        "cos",
        "tan",
        "asin",
        "acos",
        "sqrt",
        "ln",
        "exp",
        "normalize",
        "magnitude",
        "length",
        "clamp",
        "invert",
        "reflect",
        "refract",
        "remap",
        "smoothstep",
        "luminance",
        "saturate",
        "contrast",
        "mix",
        "combine2",
        "combine4",
        "extract",
        "ifgreatereq",
        "ifequal",
        "ramptb",
        "splitlr",
        "splittb",
        "ramp4",
        "noise2d",
        "noise3d",
        "fractal3d",
        "place2d",
        "rotate2d",
        "rotate3d",
        "position",
        "normal",
        "texcoord",
        "geomcolor",
        "time",
        "constant",
        "convert",
        "dot",
    ]
    var types: List[String] = [
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "vector3",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "vector3",
        "float",
        "float",
        "float",
        "float",
        "vector3",
        "vector3",
        "float",
        "float",
        "color3",
        "color3",
        "float",
        "float",
        "vector2",
        "color4",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "float",
        "vector3",
        "float",
        "vector2",
        "vector2",
        "vector3",
        "vector3",
        "vector3",
        "vector2",
        "color3",
        "float",
        "float",
        "color3",
        "float",
    ]
    var bodies: List[String] = [
        (
            '<input name="in1" type="float" value="0.25" /><input name="in2"'
            ' type="float" value="0.5" />'
        ),
        (
            '<input name="in1" type="float" value="1" /><input name="in2"'
            ' type="float" value="0.25" />'
        ),
        (
            '<input name="in1" type="float" value="0.5" /><input name="in2"'
            ' type="float" value="0.5" />'
        ),
        (
            '<input name="in1" type="float" value="1" /><input name="in2"'
            ' type="float" value="4" />'
        ),
        (
            '<input name="in1" type="float" value="5" /><input name="in2"'
            ' type="float" value="3" />'
        ),
        (
            '<input name="in1" type="float" value="2" /><input name="in2"'
            ' type="float" value="3" />'
        ),
        (
            '<input name="in1" type="float" value="1" /><input name="in2"'
            ' type="float" value="1" />'
        ),
        (
            '<input name="in1" type="float" value="0.3" /><input name="in2"'
            ' type="float" value="0.7" />'
        ),
        (
            '<input name="in1" type="float" value="0.3" /><input name="in2"'
            ' type="float" value="0.7" />'
        ),
        (
            '<input name="in1" type="vector3" value="1, 2, 3" /><input'
            ' name="in2" type="vector3" value="1, 1, 1" />'
        ),
        (
            '<input name="in1" type="vector3" value="1, 0, 0" /><input'
            ' name="in2" type="vector3" value="0, 1, 0" />'
        ),
        (
            '<input name="in1" type="vector3" value="0, 0, 0" /><input'
            ' name="in2" type="vector3" value="3, 4, 0" />'
        ),
        (
            '<input name="in1" type="float" value="-2" /><input name="in2"'
            ' type="float" value="2" />'
        ),
        '<input name="in" type="float" value="-0.5" />',
        '<input name="in" type="float" value="-3" />',
        '<input name="in" type="float" value="1.7" />',
        '<input name="in" type="float" value="1.2" />',
        '<input name="in" type="float" value="1.6" />',
        '<input name="in" type="float" value="0" />',
        '<input name="in" type="float" value="0" />',
        '<input name="in" type="float" value="0" />',
        '<input name="in" type="float" value="1" />',
        '<input name="in" type="float" value="1" />',
        '<input name="in" type="float" value="4" />',
        '<input name="in" type="float" value="1" />',
        '<input name="in" type="float" value="0" />',
        '<input name="in" type="vector3" value="3, 4, 0" />',
        '<input name="in1" type="vector3" value="3, 4, 0" />',
        '<input name="in" type="vector3" value="3, 4, 0" />',
        '<input name="in" type="float" value="2" />',
        '<input name="in" type="float" value="0.25" />',
        (
            '<input name="in" type="vector3" value="1, -1, 0" /><input'
            ' name="normal" type="vector3" value="0, 1, 0" />'
        ),
        (
            '<input name="in" type="vector3" value="0, -1, 0" /><input'
            ' name="normal" type="vector3" value="0, 1, 0" />'
        ),
        (
            '<input name="in" type="float" value="0.5" /><input name="outlow"'
            ' type="float" value="2" /><input name="outhigh" type="float"'
            ' value="4" />'
        ),
        '<input name="in" type="float" value="0.5" />',
        '<input name="in" type="color3" value="1, 1, 1" />',
        (
            '<input name="in" type="color3" value="1, 0, 0" /><input'
            ' name="amount" type="float" value="0" />'
        ),
        (
            '<input name="in" type="float" value="0.75" /><input name="amount"'
            ' type="float" value="2" />'
        ),
        (
            '<input name="bg" type="float" value="0" /><input name="fg"'
            ' type="float" value="1" /><input name="mix" type="float"'
            ' value="0.25" />'
        ),
        (
            '<input name="in1" type="float" value="0.25" /><input name="in2"'
            ' type="float" value="0.5" />'
        ),
        (
            '<input name="in1" type="float" value="0.25" /><input name="in2"'
            ' type="float" value="0.5" /><input name="in3" type="float"'
            ' value="0.75" /><input name="in4" type="float" value="1" />'
        ),
        (
            '<input name="in" type="vector3" value="1, 2, 3" /><input'
            ' name="index" type="integer" value="2" />'
        ),
        (
            '<input name="value1" type="float" value="1" /><input name="value2"'
            ' type="float" value="1" /><input name="in1" type="float"'
            ' value="0.25" /><input name="in2" type="float" value="0.75" />'
        ),
        (
            '<input name="value1" type="float" value="1" /><input name="value2"'
            ' type="float" value="2" /><input name="in1" type="float"'
            ' value="0.25" /><input name="in2" type="float" value="0.75" />'
        ),
        (
            '<input name="valuet" type="float" value="0" /><input name="valueb"'
            ' type="float" value="1" />'
        ),
        (
            '<input name="valuel" type="float" value="0.25" /><input'
            ' name="valuer" type="float" value="1" />'
        ),
        (
            '<input name="valuet" type="float" value="0.25" /><input'
            ' name="valueb" type="float" value="1" />'
        ),
        (
            '<input name="valuetl" type="float" value="0" /><input'
            ' name="valuetr" type="float" value="1" /><input name="valuebl"'
            ' type="float" value="0" /><input name="valuebr" type="float"'
            ' value="1" />'
        ),
        (
            '<input name="amplitude" type="float" value="0" /><input'
            ' name="pivot" type="float" value="0.5" />'
        ),
        (
            '<input name="amplitude" type="float" value="0" /><input'
            ' name="pivot" type="float" value="0.25" />'
        ),
        '<input name="amplitude" type="float" value="0" />',
        "",
        (
            '<input name="in" type="vector2" value="1, 0" /><input'
            ' name="amount" type="float" value="90" />'
        ),
        (
            '<input name="in" type="vector3" value="1, 0, 0" /><input'
            ' name="amount" type="float" value="90" /><input name="axis"'
            ' type="vector3" value="0, 0, 1" />'
        ),
        "",
        "",
        "",
        "",
        "",
        '<input name="value" type="float" value="0.5" />',
        '<input name="in" type="float" value="0.5" />',
        '<input name="in" type="float" value="0.5" />',
    ]
    var reds: List[Float32] = [
        0.75,
        0.75,
        0.25,
        0.25,
        2.0,
        8.0,
        0.785398,
        0.3,
        0.7,
        6.0,
        0.0,
        5.0,
        -4.0,
        0.5,
        -1.0,
        1.0,
        2.0,
        2.0,
        0.0,
        1.0,
        0.0,
        1.570796,
        0.0,
        2.0,
        0.0,
        1.0,
        0.6,
        5.0,
        5.0,
        1.0,
        0.75,
        1.0,
        0.0,
        3.0,
        0.5,
        1.0,
        0.2126,
        1.0,
        0.25,
        0.25,
        0.25,
        3.0,
        0.25,
        0.75,
        0.5,
        0.25,
        1.0,
        0.25,
        0.5,
        0.25,
        0.0,
        0.25,
        0.0,
        0.0,
        1.0,
        0.0,
        0.25,
        0.0,
        0.0,
        0.5,
        0.5,
        0.5,
    ]
    var greens: List[Float32] = [
        0.75,
        0.75,
        0.25,
        0.25,
        2.0,
        8.0,
        0.785398,
        0.3,
        0.7,
        6.0,
        0.0,
        5.0,
        -4.0,
        0.5,
        -1.0,
        1.0,
        2.0,
        2.0,
        0.0,
        1.0,
        0.0,
        1.570796,
        0.0,
        2.0,
        0.0,
        1.0,
        0.8,
        5.0,
        5.0,
        1.0,
        0.75,
        1.0,
        -1.0,
        3.0,
        0.5,
        1.0,
        0.2126,
        1.0,
        0.25,
        0.5,
        0.5,
        3.0,
        0.25,
        0.75,
        0.5,
        0.25,
        1.0,
        0.25,
        0.5,
        0.25,
        0.0,
        0.5,
        -1.0,
        1.0,
        2.0,
        0.0,
        0.5,
        0.0,
        0.0,
        0.5,
        0.5,
        0.5,
    ]
    var blues: List[Float32] = [
        0.75,
        0.75,
        0.25,
        0.25,
        2.0,
        8.0,
        0.785398,
        0.3,
        0.7,
        6.0,
        1.0,
        5.0,
        -4.0,
        0.5,
        -1.0,
        1.0,
        2.0,
        2.0,
        0.0,
        1.0,
        0.0,
        1.570796,
        0.0,
        2.0,
        0.0,
        1.0,
        0.0,
        5.0,
        5.0,
        1.0,
        0.75,
        0.0,
        0.0,
        3.0,
        0.5,
        1.0,
        0.2126,
        1.0,
        0.25,
        0.0,
        0.75,
        3.0,
        0.25,
        0.75,
        0.5,
        0.25,
        1.0,
        0.25,
        0.5,
        0.25,
        0.0,
        0.0,
        0.0,
        0.0,
        3.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.5,
        0.5,
        0.5,
    ]
    for index in range(len(elements)):
        var text = (
            '<materialx><nodegraph name="G"><'
            + elements[index]
            + ' name="n" type="'
            + types[index]
            + '">'
            + bodies[index]
            + "</"
            + elements[index]
            + '><output name="out" type="color3" nodename="n" />'
            + "</nodegraph></materialx>"
        )
        var assets = Assets()
        var read = read_materialx(text, assets)
        ref program = assets.programs.get(
            assets.materials.get(read.ids[0]).nodes
        )
        var color = run_nodes(
            ProgramSource(Pointer(to=program)), COLOR_NODE, at_uv(0.25, 0.5)
        )
        assert_almost_equal(
            color[0], reds[index], atol=1e-4, msg=elements[index]
        )
        assert_almost_equal(
            color[1], greens[index], atol=1e-4, msg=elements[index]
        )
        assert_almost_equal(
            color[2], blues[index], atol=1e-4, msg=elements[index]
        )


def test_the_noises_are_in_their_ranges() raises:
    for element in [
        "cellnoise2d",
        "cellnoise3d",
        "worleynoise2d",
        "worleynoise3d",
    ]:
        var text = (
            '<materialx><nodegraph name="G"><'
            + element
            + ' name="n" type="float" /><output name="out" type="color3"'
            + ' nodename="n" /></nodegraph></materialx>'
        )
        var assets = Assets()
        var read = read_materialx(text, assets)
        ref program = assets.programs.get(
            assets.materials.get(read.ids[0]).nodes
        )
        var color = run_nodes(
            ProgramSource(Pointer(to=program)), COLOR_NODE, at_uv(0.25, 0.5)
        )
        assert_true(color[0] >= 0, element)


comptime EVERY_INPUT = """<materialx>
  <nodegraph name="G">
    <texcoord name="uv0" type="vector2" />
    <separate2 name="parts" type="multioutput">
      <input name="in" type="vector2" nodename="uv0" />
    </separate2>
    <combine3 name="up" type="vector3">
      <input name="in1" type="float" value="0" />
      <input name="in2" type="float" value="1" />
      <input name="in3" type="float" value="0" />
    </combine3>
    <output name="metal" type="float" nodename="parts" output="outy" />
    <output name="bent" type="vector3" nodename="up" />
  </nodegraph>
  <standard_surface name="S" type="surfaceshader">
    <input name="base_color" type="color3" value="0.5, 0.5, 0.5" />
    <input name="base" type="float" value="0.5" />
    <input name="coat_color" type="color3" value="1, 0.5, 1" />
    <input name="metalness" type="float" nodegraph="G" output="metal" />
    <input name="normal" type="vector3" nodegraph="G" output="bent" />
    <input name="specular_roughness" type="float" value="0.35" />
    <input name="specular" type="float" value="0.75" />
    <input name="specular_color" type="color3" value="1, 1, 1" />
    <input name="specular_anisotropy" type="float" value="0.4" />
    <input name="specular_rotation" type="float" value="0.25" />
    <input name="transmission" type="float" value="0" />
    <input name="thin_film_thickness" type="float" value="300" />
    <input name="thin_film_ior" type="float" value="3" />
    <input name="sheen" type="float" value="0.6" />
    <input name="sheen_color" type="color3" value="0, 0, 0" />
    <input name="sheen_roughness" type="float" value="0.2" />
    <input name="coat_roughness" type="float" value="0.15" />
    <input name="emission" type="float" value="0.5" />
  </standard_surface>
  <gltf_pbr name="P" type="surfaceshader" />
  <surfacematerial name="M" type="material">
    <input name="surfaceshader" type="surfaceshader" nodename="S" />
    <input name="displacementshader" type="displacementshader" />
  </surfacematerial>
  <surfacematerial name="Q" type="material">
    <input name="surfaceshader" type="surfaceshader" nodename="P" />
  </surfacematerial>
</materialx>
"""


def test_every_surface_input_is_read() raises:
    var assets = Assets()
    var read = read_materialx(EVERY_INPUT, assets)
    assert_equal(len(read.names), 2)
    var material = assets.materials.get(read.ids[0])
    assert_almost_equal(material.roughness, 0.35)
    assert_almost_equal(material.specular_intensity, 0.75)
    assert_equal(material.specular_color.hex(), 0xFFFFFF)
    assert_almost_equal(material.anisotropy, 0.4)
    assert_almost_equal(material.anisotropy_rotation.to(DEGREE), 90, atol=1e-3)
    assert_false(material.transparent)
    assert_equal(material.iridescence, 1)
    assert_almost_equal(material.iridescence_ior, 2.333)
    assert_almost_equal(material.sheen, 0.6)
    assert_equal(material.sheen_color.hex(), 0)
    assert_almost_equal(material.sheen_roughness, 0.2)
    assert_almost_equal(material.clearcoat_roughness, 0.15)
    ref program = assets.programs.get(material.nodes)
    var source = ProgramSource(Pointer(to=program))
    # The base color times the base, times the coat's color.
    var color = run_nodes(source, COLOR_NODE, at_uv(0.25, 0.5))
    assert_almost_equal(color[0], 0.25)
    assert_almost_equal(color[1], 0.125)
    assert_almost_equal(
        run_nodes(source, METALNESS_NODE, at_uv(0.25, 0.5))[0], 0.5
    )
    # The normal, as an offset from the surface's own.
    var bent = run_nodes(source, NORMAL_NODE, at_uv(0.25, 0.5))
    assert_almost_equal(bent[1], 1)
    assert_almost_equal(bent[2], -1)
    assert_almost_equal(run_nodes(source, EMISSIVE_NODE, at_uv(0, 0))[0], 0.5)
    # A glTF surface is left as it is, three.js's `gltf_pbr`, with no
    # program.
    assert_true(assets.materials.get(read.ids[1]).nodes == NO_NODES)


def refused(text: String, why: String) raises:
    """Assert that a document is refused with a message."""
    var assets = Assets()
    with assert_raises(contains=why):
        _ = read_materialx(text, assets)


def test_what_a_document_cannot_say_is_refused() raises:
    var graph = String('<materialx><nodegraph name="G">')
    var tail = String(
        '<output name="out" type="color3" nodename="n"'
        " /></nodegraph></materialx>"
    )
    refused(
        graph + '<add name="n" type="float" />' + tail,
        "add needs its input in1",
    )
    refused(
        graph
        + '<extract name="n" type="float">'
        + '<input name="in" type="vector3" value="1, 2, 3" />'
        + '<input name="index" type="integer" value="4" /></extract>'
        + tail,
        "extract reads a component zero to three",
    )
    refused(
        graph
        + '<extract name="n" type="float">'
        + '<input name="in" type="vector3" value="1, 2, 3" />'
        + '<input name="index" type="integer" nodename="n" /></extract>'
        + tail,
        "the input index of extract must be a value",
    )
    refused(
        graph
        + '<constant name="n" type="float">'
        + '<input name="value" type="matrix33" value="1, 0, 0" /></constant>'
        + tail,
        "a value of type matrix33 that is not read",
    )
    refused(
        graph + '<image name="n" type="color3" />' + tail,
        "an image needs its file",
    )
    refused(
        '<materialx><unlit_surface name="S" type="surfaceshader" />'
        + '<surfacematerial name="M" type="material">'
        + '<input name="surfaceshader" type="surfaceshader" nodename="S" />'
        + "</surfacematerial></materialx>",
        "the surface unlit_surface is not read",
    )
    # A graph with no output named out makes no material.
    var assets = Assets()
    var none = read_materialx(
        (
            '<materialx><nodegraph name="G"><output name="other" type="float"'
            ' nodename="x" /></nodegraph></materialx>'
        ),
        assets,
    )
    assert_equal(len(none.names), 0)


def test_an_image_reads_the_coordinates_by_default() raises:
    var image = Framebuffer(1, 1, Color(255, 255, 255))
    Path("/tmp/threemojo_materialx_white.png").write_bytes(encode_png(image))
    var assets = Assets()
    var read = read_materialx(
        (
            '<materialx><nodegraph name="G"><image name="n"'
            ' type="color3"><input name="file" type="filename"'
            ' value="threemojo_materialx_white.png" /></image><output'
            ' name="out" type="color3" nodename="n" /></nodegraph></materialx>'
        ),
        assets,
        "/tmp/",
    )
    ref program = assets.programs.get(assets.materials.get(read.ids[0]).nodes)
    assert_equal(len(program.textures), 1)
    assert_equal(assets.textures.count(), 1)


comptime CORNERS = """<materialx fileprefix="/tmp/threemojo_mtlx_">
  <image name="loose" type="color3">
    <input name="file" type="filename" value="px.png" />
  </image>
  <nodegraph name="G">
    <constant name="i" type="integer"><input name="value" type="integer" value="2" /></constant>
    <constant name="b" type="boolean"><input name="value" type="boolean" value="true" /></constant>
    <constant name="v4" type="vector4"><input name="value" type="vector4" value="0.1,0.2,0.3,0.4" /></constant>
    <constant name="c4" type="color4"><input name="value" type="color4" value="0.5|0.5|0.5|1" /></constant>
    <convert name="f" type="float"><input name="in" type="vector3" value="0.1, 0.2, 0.3" /></convert>
    <convert name="v2" type="vector2"><input name="in" type="vector3" value="0.1, 0.2, 0.3" /></convert>
    <separate3 name="s3" type="multioutput"><input name="in" type="color3" value="0.1,0.2,0.3" /></separate3>
    <separate4 name="s4" type="multioutput"><input name="in" type="color4" nodename="c4" /></separate4>
    <separate3 name="sf" type="float"><input name="in" type="vector3" value="1,2,3" /></separate3>
    <luminance name="lum" type="color3">
      <input name="in" type="color3" value="1,1,1" />
      <input name="lumacoeffs" type="color3" value="0.3,0.6,0.1" />
    </luminance>
    <image name="im" type="color3">
      <input name="file" type="filename" value="px.png" />
      <input name="texcoord" type="vector2" />
    </image>
    <tiledimage name="t" type="color3">
      <input name="file" type="filename" value="px.png" />
      <input name="texcoord" type="vector2" nodename="v2" />
    </tiledimage>
    <combine4 name="all" type="vector4">
      <input name="in1" type="float" nodename="s3" output="outr" />
      <input name="in2" type="float" nodename="s3" output="outg" />
      <input name="in3" type="float" nodename="s3" output="outb" />
      <input name="in4" type="float" nodename="s4" output="outa" />
    </combine4>
    <output name="mid" type="float" nodename="f" />
    <add name="a1" type="color3"><input name="in1" type="color3" nodename="all" /><input name="in2" type="color3" nodename="im" /></add>
    <add name="a2" type="color3"><input name="in1" type="color3" nodename="a1" /><input name="in2" type="color3" nodename="t" /></add>
    <add name="a3" type="color3"><input name="in1" type="color3" nodename="a2" /><input name="in2" type="color3" nodename="lum" /></add>
    <add name="a4" type="color3"><input name="in1" type="color3" nodename="a3" /><input name="in2" type="color3" nodename="i" /></add>
    <add name="a5" type="color3"><input name="in1" type="color3" nodename="a4" /><input name="in2" type="color3" nodename="b" /></add>
    <add name="a6" type="color3"><input name="in1" type="color3" nodename="a5" /><input name="in2" type="color3" nodename="v4" /></add>
    <add name="a7" type="color3"><input name="in1" type="color3" nodename="a6" /><input name="in2" type="color3" nodename="sf" output="outy" /></add>
    <add name="a8" type="color3"><input name="in1" type="color3" nodename="a7" /><input name="in2" type="color3" nodename="mid" output="outx" /></add>
    <add name="a9" type="color3"><input name="in1" type="color3" nodename="a8" /><input name="in2" type="color3" nodename="v2" /></add>
    <output name="out" type="color3" nodename="a9" />
  </nodegraph>
</materialx>
"""


comptime SURFACES = """<materialx>
  <standard_surface name="plain" type="surfaceshader">
    <extra name="ignored" />
    <input name="coat_color" type="color3" value="1, 0.5, 0.5" />
    <input name="thin_film_thickness" type="float" value="0" />
    <input name="subsurface" type="float" value="0.25" />
  </standard_surface>
  <standard_surface name="empty" type="surfaceshader" />
  <surfacematerial name="A" type="material">
    <input name="surfaceshader" type="surfaceshader" nodename="plain" />
  </surfacematerial>
  <surfacematerial name="B" type="material">
    <input name="surfaceshader" type="surfaceshader" nodename="missing" />
  </surfacematerial>
  <surfacematerial name="C" type="material" />
  <surfacematerial name="D" type="material">
    <input name="surfaceshader" type="surfaceshader" nodename="empty" />
  </surfacematerial>
</materialx>
"""


def test_the_corners_of_the_reader() raises:
    var numbers = mtlx_numbers("1\t2\n3|4")
    assert_equal(len(numbers), 4)
    assert_equal(numbers[3], 4)
    Path("/tmp/threemojo_mtlx_px.png").write_bytes(
        encode_png(Framebuffer(1, 1, Color(255, 255, 255)))
    )
    var assets = Assets()
    var read = read_materialx(CORNERS, assets)
    assert_equal(len(read.ids), 1)
    # The one image, read once though three nodes name it.
    assert_equal(assets.textures.count(), 1)
    var surfaces = Assets()
    var four = read_materialx(SURFACES, surfaces)
    assert_equal(len(four.ids), 4)
    # No base: three.js's gray, times the coat's color.
    ref program = surfaces.programs.get(
        surfaces.materials.get(four.ids[0]).nodes
    )
    assert_true(program.has(COLOR_NODE))
    assert_equal(surfaces.materials.get(four.ids[0]).iridescence, 0)
    # An empty document reads nothing.
    var none = Assets()
    assert_equal(len(read_materialx("<materialx></materialx>", none).ids), 0)
    # A graph beside other elements, with no surface, is read alone.
    var alone = Assets()
    var graphs = read_materialx(
        (
            '<materialx><constant name="c" type="float"><input name="value"'
            ' type="float" value="1" /></constant><nodegraph name="G">'
            '<output name="out" type="color3" nodename="k" /><constant'
            ' name="k" type="color3"><input name="value" type="color3"'
            ' value="1,0,0" /></constant></nodegraph></materialx>'
        ),
        alone,
    )
    assert_equal(len(graphs.ids), 1)
    # A file beside the working folder is read with no folder before it.
    Path("threemojo_mtlx_here.mtlx").write_text("<materialx></materialx>")
    var here = Assets()
    assert_equal(len(load_materialx("threemojo_mtlx_here.mtlx", here).ids), 0)
    remove("threemojo_mtlx_here.mtlx")


def test_values_and_components_that_are_not_read_are_refused() raises:
    var graph = String(
        '<materialx><nodegraph name="G"><output name="out" type="color3"'
        ' nodename="n" />'
    )
    var tail = String("</nodegraph></materialx>")
    refused(
        graph
        + '<constant name="n" type="color3"><input name="value"'
        ' type="string" value="1" /></constant>'
        + tail,
        "a value of type string that is not read",
    )
    refused(
        graph
        + '<constant name="n" type="color3"><input name="value"'
        ' type="vector3" value="1,2" /></constant>'
        + tail,
        "a value of type vector3 that is not read",
    )
    refused(
        graph
        + '<extract name="n" type="float"><input name="in" type="vector3"'
        ' value="1,2,3" /><input name="index" type="integer" value="-1" />'
        "</extract>"
        + tail,
        "extract reads a component zero to three",
    )
    var assets = Assets()
    with assert_raises():
        _ = read_materialx(
            graph
            + '<add name="n" type="color3"><input name="in1" type="filename"'
            ' value="px.png" /></add>'
            + tail,
            assets,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
