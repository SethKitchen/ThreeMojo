# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""three.js's `MaterialXLoader`: standard surfaces with values and graphs,
unlit node graphs, images, and what is refused."""

from core.assets import Assets
from loaders.materialx import load_materialx, mtlx_numbers, read_materialx
from materials.material import BASIC, DOUBLE_SIDE, PHYSICAL
from materials.nodes import (
    COLOR_NODE,
    EMISSIVE_NODE,
    METALNESS_NODE,
    OPACITY_NODE,
    ROUGHNESS_NODE,
    NodeInputs,
    ProgramSource,
    run_nodes,
)
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from render.png import encode as encode_png
from std.pathlib import Path
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
            '<materialx><nodegraph name="G"><normalmap name="n"'
            ' type="vector3" /><output name="out" type="color3"'
            ' nodename="n" /></nodegraph></materialx>',
            assets,
        )
    with assert_raises(contains="a graph that drives sheen is not ported"):
        _ = read_materialx(
            '<materialx><nodegraph name="G"><constant name="c" type="float">'
            '<input name="value" type="float" value="1" /></constant>'
            '<output name="o" type="float" nodename="c" /></nodegraph>'
            '<standard_surface name="S" type="surfaceshader">'
            '<input name="sheen" type="float" nodegraph="G" output="o" />'
            '</standard_surface><surfacematerial name="M" type="material">'
            '<input name="surfaceshader" type="surfaceshader" nodename="S" />'
            "</surfacematerial></materialx>",
            assets,
        )
    with assert_raises(contains="nothing is named G/missing"):
        _ = read_materialx(
            '<materialx><nodegraph name="G"><output name="out"'
            ' type="color3" nodename="missing" /></nodegraph></materialx>',
            assets,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
