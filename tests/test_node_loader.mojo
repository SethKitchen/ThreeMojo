# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.node_loader`: three.js's node JSON read into a node
graph, and a scene file's node materials read by `loaders.object_loader`.

The documents in `MATERIAL_A` to `MATERIAL_E` and `NODE_D` are what three.js
r186 writes, from `MeshStandardNodeMaterial.toJSON()`, `Node.toJSON()` and
`Mesh.toJSON()`, with each uuid renamed to a short one and the material
fields the loader does not read taken out. Each value a test checks is
worked out by hand from the TSL the document came from.
"""

from core.assets import Assets
from core.scene import Scene
from exporters.gltf import encode_base64
from loaders.json import parse_json
from loaders.node_loader import (
    JSON_CONST_NODE,
    JSON_CUBE_TEXTURE_NODE,
    JSON_VAR_NODE,
    NODE_JSON_TYPE_COUNT,
    NodeJsonType,
    NodeLoader,
    node_json_type_names,
    node_json_type_of,
    node_material_properties,
    node_output_of,
    plain_material_type,
    read_node_material,
    type_width,
)
from loaders.object_loader import read_material_json, read_object_json
from materials.material import BASIC, STANDARD, MaterialId
from materials.nodes import (
    CAST_SHADOW_NODE,
    COLOR_NODE,
    FRAGMENT_NODE,
    NODE_FLOAT,
    NODE_MAT3,
    NODE_OUTPUT_COUNT,
    NODE_VEC2,
    NODE_VEC3,
    NORMAL_NODE,
    OPACITY_NODE,
    OUTPUT_NODE,
    ROUGHNESS_NODE,
    NodeInputs,
    NodeOutput,
    NodeProgram,
    ProgramSource,
    moved_position,
    run_nodes,
)
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from render.png import encode as encode_png
from std.math import pi
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import SECOND, Duration

comptime Lanes = SIMD[DType.float32, 4]

# `m.colorNode = mix(vertexColor(), uniform(new Color(1, 0.5, 0.25)),
# sin(time.mul(2)).mul(0.5))`, `m.opacityNode = float(0.5).add(uv().x)` and
# `m.roughnessNode = uv().y.abs()` on a `MeshStandardNodeMaterial`.
comptime MATERIAL_A = (
    '{"metadata":{"version":4.7,"type":"Material","generator":"Material.toJSON"},'
    '"uuid":"n0","type":"MeshStandardNodeMaterial","opacity":1,'
    '"transparent":false,"color":16777215,"roughness":1,"metalness":0,'
    '"inputNodes":{"colorNode":"n1","opacityNode":"n2","roughnessNode":"n3"},'
    '"nodes":[{"uuid":"n1","type":"VarNode","inputNodes":{"node":"n4"}},'
    '{"uuid":"n4","type":"MathNode","inputNodes":{"aNode":"n5","bNode":"n6",'
    '"cNode":"n7"},"method":"mix"},'
    '{"uuid":"n5","type":"VertexColorNode","global":true,'
    '"_attributeName":null,"index":0},'
    '{"uuid":"n6","type":"UniformNode","inputNodes":{"groupNode":"n8"},'
    '"value":[1,0.5,0.25],"valueType":"color","nodeType":null,'
    '"precision":null},'
    '{"uuid":"n8","type":"UniformGroupNode","name":"object","version":0,'
    '"shared":false},'
    '{"uuid":"n7","type":"VarNode","inputNodes":{"node":"n9"}},'
    '{"uuid":"n9","type":"OperatorNode","inputNodes":{"aNode":"n10",'
    '"bNode":"n11"},"op":"*"},'
    '{"uuid":"n10","type":"VarNode","inputNodes":{"node":"n12"}},'
    '{"uuid":"n12","type":"MathNode","inputNodes":{"aNode":"n13"},'
    '"method":"sin"},'
    '{"uuid":"n13","type":"VarNode","inputNodes":{"node":"n14"}},'
    '{"uuid":"n14","type":"OperatorNode","inputNodes":{"aNode":"n15",'
    '"bNode":"n16"},"op":"*"},'
    '{"uuid":"n15","type":"UniformNode","inputNodes":{"groupNode":"n17"},'
    '"value":0,"valueType":"float","nodeType":null,"precision":null},'
    '{"uuid":"n17","type":"UniformGroupNode","name":"render","version":0,'
    '"shared":true},'
    '{"uuid":"n16","type":"ConstNode","value":2,"valueType":"float",'
    '"nodeType":null,"precision":null},'
    '{"uuid":"n11","type":"ConstNode","value":0.5,"valueType":"float",'
    '"nodeType":null,"precision":null},'
    '{"uuid":"n2","type":"VarNode","inputNodes":{"node":"n18"}},'
    '{"uuid":"n18","type":"OperatorNode","inputNodes":{"aNode":"n19",'
    '"bNode":"n20"},"op":"+"},'
    '{"uuid":"n19","type":"VarNode","inputNodes":{"node":"n11"}},'
    '{"uuid":"n20","type":"SplitNode","inputNodes":{"node":"n21"},'
    '"components":"x"},'
    '{"uuid":"n21","type":"AttributeNode","global":true,'
    '"_attributeName":"uv"},'
    '{"uuid":"n3","type":"VarNode","inputNodes":{"node":"n22"}},'
    '{"uuid":"n22","type":"MathNode","inputNodes":{"aNode":"n23"},'
    '"method":"abs"},'
    '{"uuid":"n23","type":"SplitNode","inputNodes":{"node":"n24"},'
    '"components":"y"},'
    '{"uuid":"n24","type":"AttributeNode","global":true,'
    '"_attributeName":"uv"}]}'
)

# `m.positionNode = positionLocal.add(vec3(0, 1, 0))` and
# `m.normalNode = vec3(0, 1, 0)` on a `MeshBasicNodeMaterial`.
comptime MATERIAL_C = (
    '{"uuid":"n0","type":"MeshBasicNodeMaterial","opacity":1,'
    '"inputNodes":{"normalNode":"n1","positionNode":"n2"},'
    '"nodes":[{"uuid":"n1","type":"VarNode","inputNodes":{"node":"n3"}},'
    '{"uuid":"n3","type":"ConstNode","value":[0,1,0],"valueType":"vec3",'
    '"nodeType":"vec3","precision":null},'
    '{"uuid":"n2","type":"VarNode","inputNodes":{"node":"n4"}},'
    '{"uuid":"n4","type":"OperatorNode","inputNodes":{"aNode":"n5",'
    '"bNode":"n6"},"op":"+"},'
    '{"uuid":"n5","type":"VaryingNode","inputNodes":{"node":"n7"}},'
    '{"uuid":"n7","type":"SubBuild","inputNodes":{"node":"n8"}},'
    '{"uuid":"n8","type":"AttributeNode","global":true,'
    '"_attributeName":"position"},'
    '{"uuid":"n6","type":"VarNode","inputNodes":{"node":"n9"}},'
    '{"uuid":"n9","type":"ConstNode","value":[0,1,0],"valueType":"vec3",'
    '"nodeType":"vec3","precision":null}]}'
)

# `uv().x.greaterThan(0.5).select(float(1), float(2)).toJSON()`.
comptime NODE_D = (
    '{"uuid":"n0","type":"ConditionalNode","metadata":{"version":4.7,'
    '"type":"Node","generator":"Node.toJSON"},"inputNodes":{"condNode":"n1",'
    '"ifNode":"n2","elseNode":"n3"},'
    '"nodes":[{"uuid":"n1","type":"VarNode","inputNodes":{"node":"n4"}},'
    '{"uuid":"n4","type":"OperatorNode","inputNodes":{"aNode":"n5",'
    '"bNode":"n6"},"op":">"},'
    '{"uuid":"n5","type":"SplitNode","inputNodes":{"node":"n7"},'
    '"components":"x"},'
    '{"uuid":"n7","type":"AttributeNode","global":true,'
    '"_attributeName":"uv"},'
    '{"uuid":"n6","type":"ConstNode","value":0.5,"valueType":"float",'
    '"nodeType":null,"precision":null},'
    '{"uuid":"n2","type":"VarNode","inputNodes":{"node":"n8"}},'
    '{"uuid":"n8","type":"ConstNode","value":1,"valueType":"float",'
    '"nodeType":"float","precision":null},'
    '{"uuid":"n3","type":"VarNode","inputNodes":{"node":"n9"}},'
    '{"uuid":"n9","type":"ConstNode","value":2,"valueType":"float",'
    '"nodeType":"float","precision":null}]}'
)

# `m.colorNode = vec4(0.2, 0.4, 0.6, 0.5)` with `m.opacity = 0.5`.
comptime MATERIAL_E = (
    '{"uuid":"n0","type":"MeshBasicNodeMaterial","opacity":0.5,'
    '"inputNodes":{"colorNode":"n1"},'
    '"nodes":[{"uuid":"n1","type":"VarNode","inputNodes":{"node":"n2"}},'
    '{"uuid":"n2","type":"ConstNode","value":[0.2,0.4,0.6,0.5],'
    '"valueType":"vec4","nodeType":"vec4","precision":null}]}'
)

# `Mesh.toJSON()`'s nodes of a `MeshBasicNodeMaterial` whose `colorNode`
# is `texture(tex, uv().mul(2)).rgb.add(texture(tex).level(2).rgb)` and
# whose `opacityNode` is `textureLoad(tex, uv(), int(1)).a`.
comptime NODES_B = (
    '{"uuid":"n1","type":"VarNode","inputNodes":{"node":"n5"}},'
    '{"uuid":"n5","type":"OperatorNode","inputNodes":{"aNode":"n6",'
    '"bNode":"n7"},"op":"+"},'
    '{"uuid":"n6","type":"SplitNode","inputNodes":{"node":"n8"},'
    '"components":"xyz"},'
    '{"uuid":"n8","type":"TextureNode","inputNodes":{"groupNode":"n9",'
    '"uvNode":"n10"},"value":"n3","valueType":null,"nodeType":null,'
    '"precision":null,"sampler":true,"updateMatrix":false,'
    '"updateType":"none"},'
    '{"uuid":"n9","type":"UniformGroupNode","name":"object","version":0,'
    '"shared":false},'
    '{"uuid":"n10","type":"VarNode","inputNodes":{"node":"n11"}},'
    '{"uuid":"n11","type":"OperatorNode","inputNodes":{"aNode":"n12",'
    '"bNode":"n13"},"op":"*"},'
    '{"uuid":"n12","type":"AttributeNode","global":true,'
    '"_attributeName":"uv"},'
    '{"uuid":"n13","type":"ConstNode","value":2,"valueType":"float",'
    '"nodeType":null,"precision":null},'
    '{"uuid":"n7","type":"SplitNode","inputNodes":{"node":"n14"},'
    '"components":"xyz"},'
    '{"uuid":"n14","type":"TextureNode","inputNodes":{"groupNode":"n9",'
    '"levelNode":"n15","referenceNode":"n16"},"value":"n3","valueType":null,'
    '"nodeType":null,"precision":null,"sampler":true,"updateMatrix":true,'
    '"updateType":"none"},'
    '{"uuid":"n15","type":"ConstNode","value":2,"valueType":"float",'
    '"nodeType":null,"precision":null},'
    '{"uuid":"n16","type":"TextureNode","inputNodes":{"groupNode":"n9"},'
    '"value":"n3","valueType":null,"nodeType":null,"precision":null,'
    '"sampler":true,"updateMatrix":true,"updateType":"none"},'
    '{"uuid":"n2","type":"SplitNode","inputNodes":{"node":"n17"},'
    '"components":"w"},'
    '{"uuid":"n17","type":"TextureNode","inputNodes":{"groupNode":"n9",'
    '"uvNode":"n18","levelNode":"n19"},"value":"n3","valueType":null,'
    '"nodeType":null,"precision":null,"sampler":false,"updateMatrix":false,'
    '"updateType":"none"},'
    '{"uuid":"n18","type":"AttributeNode","global":true,'
    '"_attributeName":"uv"},'
    '{"uuid":"n19","type":"VarNode","inputNodes":{"node":"n20"}},'
    '{"uuid":"n20","type":"ConstNode","value":1,"valueType":"float",'
    '"nodeType":"int","precision":null}'
)


# --- helpers ------------------------------------------------------------------


def _inputs() -> NodeInputs:
    """Return a fragment with every attribute a different number."""
    return NodeInputs(
        0.25,
        0.75,
        Vector3(1, 2, 3),
        Vector3(0, 0, 1),
        Vector3(0.1, 0.2, 0.3),
        Vector3(0.5, 0.6, 0.7),
        False,
    )


def _in(name: String, uuid: String) -> String:
    """Return one entry of `inputNodes`."""
    return '"' + name + '":"' + uuid + '"'


def _node(
    uuid: String, type: String, inputs: String = "", extra: String = ""
) -> String:
    """Return a node of a class, with its inputs and its other fields."""
    var text = '{"uuid":"' + uuid + '","type":"' + type + '"'
    if inputs != "":
        text += ',"inputNodes":{' + inputs + "}"
    if extra != "":
        text += "," + extra
    return text + "}"


def _const(uuid: String, value: String, type: String = "float") -> String:
    """Return a `ConstNode`."""
    return _node(
        uuid, "ConstNode", "", '"valueType":"' + type + '","value":' + value
    )


def _uv(uuid: String) -> String:
    """Return the `uv` attribute node."""
    return _node(uuid, "AttributeNode", "", '"_attributeName":"uv"')


def _op(uuid: String, op: String, a: String, b: String = "") -> String:
    """Return an `OperatorNode`."""
    var inputs = _in("aNode", a)
    if b != "":
        inputs += "," + _in("bNode", b)
    return _node(uuid, "OperatorNode", inputs, '"op":"' + op + '"')


def _math(
    uuid: String, method: String, a: String, b: String = "", c: String = ""
) -> String:
    """Return a `MathNode`."""
    var inputs = _in("aNode", a)
    if b != "":
        inputs += "," + _in("bNode", b)
    if c != "":
        inputs += "," + _in("cNode", c)
    return _node(uuid, "MathNode", inputs, '"method":"' + method + '"')


def _lanes(
    nodes: String, root: String, view: Matrix4 = Matrix4()
) raises -> Lanes:
    """Return what a node of a list computes for `_inputs`, made a `vec4`."""
    var document = parse_json("[" + nodes + "]")
    var loader = NodeLoader()
    loader.parse_nodes(document, document.root())
    var node = loader.convert(loader.node(document, root), "vec4")
    loader.graph.set_output(FRAGMENT_NODE, node)
    var program = loader.graph.compile()
    program.set_frame(Duration(0, SECOND), view)
    return run_nodes(
        ProgramSource(Pointer(to=program)), FRAGMENT_NODE, _inputs()
    )


def _refused(nodes: String, root: String, message: String) raises:
    """Assert that building a node of a list is refused."""
    var document = parse_json("[" + nodes + "]")
    var loader = NodeLoader()
    loader.parse_nodes(document, document.root())
    with assert_raises(contains=message):
        _ = loader.node(document, root)


def _type(nodes: String, root: String) raises -> Int:
    """Return the width of the type a node of a list has."""
    var document = parse_json("[" + nodes + "]")
    var loader = NodeLoader()
    loader.parse_nodes(document, document.root())
    return loader.graph.type_of(loader.node(document, root)).value


def _output(program: NodeProgram, output: NodeOutput) -> Lanes:
    """Return what an output of a program computes for `_inputs`."""
    return run_nodes(ProgramSource(Pointer(to=program)), output, _inputs())


def _near(got: Lanes, x: Float32, y: Float32, z: Float32) raises:
    """Assert the first three lanes."""
    assert_almost_equal(got[0], x, atol=1e-5)
    assert_almost_equal(got[1], y, atol=1e-5)
    assert_almost_equal(got[2], z, atol=1e-5)


# --- names and types ------------------------------------------------------------


def test_the_types_and_names_are_three_js_s() raises:
    assert_true(JSON_VAR_NODE.is_valid())
    assert_true(JSON_CUBE_TEXTURE_NODE.is_valid())
    assert_false(NodeJsonType(NODE_JSON_TYPE_COUNT).is_valid())
    assert_false(NodeJsonType(-1).is_valid())
    assert_equal(len(node_json_type_names()), NODE_JSON_TYPE_COUNT)
    assert_true(node_json_type_of("ConstNode") == JSON_CONST_NODE)
    assert_true(node_json_type_of("CubeTextureNode") == JSON_CUBE_TEXTURE_NODE)
    assert_false(node_json_type_of("ModelNode").is_valid())
    assert_equal(len(node_material_properties()), NODE_OUTPUT_COUNT)
    assert_true(node_output_of("colorNode") == COLOR_NODE)
    assert_true(node_output_of("castShadowNode") == CAST_SHADOW_NODE)
    assert_false(node_output_of("clearcoatNode").is_valid())
    assert_equal(plain_material_type("NodeMaterial"), "MeshBasicMaterial")
    assert_equal(
        plain_material_type("MeshStandardNodeMaterial"), "MeshStandardMaterial"
    )
    assert_equal(plain_material_type("PointsNodeMaterial"), "PointsMaterial")
    assert_equal(plain_material_type("MeshBasicMaterial"), "MeshBasicMaterial")


def test_a_type_s_width_is_its_float_count() raises:
    assert_equal(type_width("float"), 1)
    assert_equal(type_width("int"), 1)
    assert_equal(type_width("uint"), 1)
    assert_equal(type_width("bool"), 1)
    assert_equal(type_width("color"), 3)
    assert_equal(type_width("mat3"), 9)
    assert_equal(type_width("mat4"), 16)
    assert_equal(type_width("vec2"), 2)
    assert_equal(type_width("ivec3"), 3)
    assert_equal(type_width("uvec4"), 4)
    assert_equal(type_width("bvec2"), 2)
    assert_equal(type_width(""), -1)
    assert_equal(type_width("vec"), -1)
    assert_equal(type_width("dvec3"), -1)
    assert_equal(type_width("mat2"), -1)
    assert_equal(type_width("vec5"), -1)
    assert_equal(type_width("vec1"), -1)


# --- NodeLoader ---------------------------------------------------------------


def test_a_node_is_read_with_the_nodes_it_lists() raises:
    """`Node.toJSON()` of a select: the fragment's u is 0.25, not over one
    half, so it gives two."""
    var document = parse_json(NODE_D)
    var loader = NodeLoader()
    var node = loader.parse(document, document.root())
    assert_equal(loader.graph.type_of(node), NODE_FLOAT)
    loader.graph.set_output(OPACITY_NODE, node)
    var program = loader.graph.compile()
    assert_equal(_output(program, OPACITY_NODE)[0], 2)
    # A node with no list of its own is read alone.
    var alone = parse_json(_const("k", "3"))
    var other = NodeLoader()
    _ = other.parse(alone, alone.root())
    # A node read twice is built once.
    var twice = parse_json("[" + _const("k", "3") + "]")
    var again = NodeLoader()
    again.parse_nodes(twice, twice.root())
    var first = again.node(twice, "k")
    assert_equal(again.node(twice, "k").value, first.value)
    # An empty list indexes nothing.
    var empty = parse_json("[]")
    again.parse_nodes(empty, empty.root())


def test_the_constants_hold_their_values() raises:
    _near(_lanes(_const("k", "2.5"), "k"), 2.5, 2.5, 2.5)
    _near(_lanes(_const("k", "true", "bool"), "k"), 1, 1, 1)
    _near(_lanes(_const("k", "false", "bool"), "k"), 0, 0, 0)
    _near(_lanes(_const("k", "[1,2]", "vec2"), "k"), 1, 2, 0)
    _near(_lanes(_const("k", "[1,2,3]", "vec3"), "k"), 1, 2, 3)
    var four = _lanes(_const("k", "[1,2,3,4]", "vec4"), "k")
    assert_equal(four[3], 4)
    # A color is linear already, as three.js keeps it.
    _near(_lanes(_const("k", "[1,0.5,0.25]", "color"), "k"), 1, 0.5, 0.25)
    # A matrix is its columns: this one times (1, 1, 1) is the sum of them.
    var columns = _const("m", "[1,0,0,2,1,0,0,0,2]", "mat3")
    var ones = _const("v", "[1,1,1]", "vec3")
    _near(
        _lanes(columns + "," + ones + "," + _op("p", "*", "m", "v"), "p"),
        3,
        1,
        2,
    )
    var big = _const("m", "[1,0,0,0,0,1,0,0,0,0,1,0,5,6,7,1]", "mat4")
    var point = _const("v", "[1,1,1,1]", "vec4")
    _near(
        _lanes(big + "," + point + "," + _op("p", "*", "m", "v"), "p"), 6, 7, 8
    )
    _refused(
        _const("k", '"text"', "string"),
        "k",
        "a value of type string is not read",
    )
    _refused(_const("k", "[1,2]", "vec3"), "k", "a vec3 holds 3 numbers, not 2")
    _refused(_const("k", "[]", "vec2"), "k", "a vec2 holds 2 numbers, not 0")


def test_a_uniform_is_named_by_its_uuid() raises:
    var nodes = (
        _node("f", "UniformNode", "", '"valueType":"float","value":2')
        + ","
        + _node("g", "UniformNode", "", '"valueType":"vec2","value":[1,2]')
        + ","
        + _node("h", "UniformNode", "", '"valueType":"vec3","value":[1,2,3]')
        + ","
        + _node("i", "UniformNode", "", '"valueType":"vec4","value":[1,2,3,4]')
        + ","
        + _node("j", "UniformNode", "", '"valueType":"color","value":[1,0.5,0]')
        + ","
        + _node(
            "m",
            "UniformNode",
            "",
            '"valueType":"mat3","value":[2,0,0,0,3,0,0,0,4]',
        )
        + ","
        + _node(
            "n",
            "UniformNode",
            "",
            '"valueType":"mat4","value":[1,0,0,0,0,1,0,0,0,0,1,0,5,6,7,1]',
        )
        + ","
        + _const("v3", "[1,1,1]", "vec3")
        + ","
        + _const("v4", "[1,1,1,1]", "vec4")
    )
    var document = parse_json("[" + nodes + "]")
    var loader = NodeLoader()
    loader.parse_nodes(document, document.root())
    var sum = loader.graph.add(
        loader.graph.add(
            loader.graph.mul(
                loader.node(document, "m"), loader.node(document, "v3")
            ),
            loader.graph.swizzle(
                loader.graph.mul(
                    loader.node(document, "n"), loader.node(document, "v4")
                ),
                "xyz",
            ),
        ),
        loader.graph.add(
            loader.node(document, "h"), loader.node(document, "j")
        ),
    )
    var extra = loader.graph.add(
        loader.graph.swizzle(loader.node(document, "i"), "x"),
        loader.graph.add(
            loader.graph.swizzle(loader.node(document, "g"), "y"),
            loader.node(document, "f"),
        ),
    )
    loader.graph.set_output(COLOR_NODE, sum)
    loader.graph.set_output(OPACITY_NODE, extra)
    var program = loader.graph.compile()
    # (2, 3, 4) + (6, 7, 8) + (1, 2, 3) + (1, 0.5, 0).
    _near(_output(program, COLOR_NODE), 10, 12.5, 15)
    assert_equal(_output(program, OPACITY_NODE)[0], 5)
    assert_equal(program.uniform("f")[0], 2)
    assert_equal(program.uniform("m")[0], 2)
    program.set_uniform("f", Float32(4))
    assert_equal(_output(program, OPACITY_NODE)[0], 7)


def test_the_attributes_are_read() raises:
    _near(_lanes(_uv("a"), "a"), 0.25, 0.75, 0)
    # `color` is the vertex colors.
    _near(
        _lanes(
            _node("a", "AttributeNode", "", '"_attributeName":"color"'), "a"
        ),
        0.1,
        0.2,
        0.3,
    )
    assert_equal(
        _type(
            _node("a", "AttributeNode", "", '"_attributeName":"position"'), "a"
        ),
        3,
    )
    assert_equal(
        _type(
            _node("a", "AttributeNode", "", '"_attributeName":"normal"'), "a"
        ),
        3,
    )
    # A custom attribute takes the type the caller declares.
    var document = parse_json(
        "[" + _node("a", "AttributeNode", "", '"_attributeName":"heat"') + "]"
    )
    var loader = NodeLoader()
    loader.parse_nodes(document, document.root())
    loader.set_attribute("heat", NODE_VEC2)
    loader.set_attribute("heat", NODE_FLOAT)
    assert_equal(loader.graph.type_of(loader.node(document, "a")), NODE_FLOAT)
    with assert_raises(
        contains="an attribute is a float or a vector, not a mat3"
    ):
        loader.set_attribute("bad", NODE_MAT3)
    _refused(
        _node("a", "AttributeNode", "", '"_attributeName":"heat"'),
        "a",
        "the attribute heat has no type; declare it with set_attribute",
    )
    _refused(
        _node("a", "AttributeNode", "", '"_attributeName":null'),
        "a",
        "a node's _attributeName must be a string",
    )
    _near(
        _lanes(_node("a", "VertexColorNode", "", '"index":0'), "a"),
        0.1,
        0.2,
        0.3,
    )
    _refused(
        _node("a", "VertexColorNode", "", '"index":1'),
        "a",
        "only the first vertex colors are read",
    )


def test_the_nodes_that_pass_their_input_on() raises:
    var uv = _uv("u")
    _near(
        _lanes(uv + "," + _node("a", "VarNode", _in("node", "u")), "a"),
        0.25,
        0.75,
        0,
    )
    _near(
        _lanes(uv + "," + _node("a", "SubBuild", _in("node", "u")), "a"),
        0.25,
        0.75,
        0,
    )
    # A varying of an attribute is the attribute itself.
    var document = parse_json(
        "["
        + uv
        + ","
        + _node("a", "VaryingNode", _in("node", "u"))
        + ","
        + _const("two", "2")
        + ","
        + _op("d", "*", "u", "two")
        + ","
        + _node("b", "VaryingNode", _in("node", "d"))
        + "]"
    )
    var loader = NodeLoader()
    loader.parse_nodes(document, document.root())
    assert_equal(
        loader.node(document, "a").value, loader.node(document, "u").value
    )
    # A varying of anything else is a varying node.
    var varied = loader.node(document, "b")
    assert_true(varied.value != loader.node(document, "d").value)
    assert_equal(loader.graph.type_of(varied), NODE_VEC2)
    assert_equal(_type(_node("a", "FrontFacingNode"), "a"), 1)
    assert_equal(_type(_node("a", "ScreenNode"), "a"), 2)
    assert_equal(_type(_node("a", "PointUVNode"), "a"), 2)
    # A varying of a constant, before any attribute is read.
    assert_equal(
        _type(
            _const("k", "1")
            + ","
            + _node("a", "VaryingNode", _in("node", "k")),
            "a",
        ),
        1,
    )


def test_the_operators_are_glsl_s() raises:
    var ops: List[String] = [
        "+",
        "-",
        "*",
        "/",
        "%",
        "==",
        "!=",
        "<",
        ">",
        "<=",
        ">=",
        "&&",
        "||",
        "^^",
        "&",
        "|",
        "^",
        "<<",
        ">>",
    ]
    var want: List[Float32] = [
        10,
        2,
        24,
        1.5,
        2,
        0,
        1,
        0,
        1,
        0,
        1,
        1,
        1,
        0,
        4,
        6,
        2,
        96,
        0,
    ]
    var values = _const("a", "6") + "," + _const("b", "4")
    for index in range(len(ops)):
        var got = _lanes(values + "," + _op("p", ops[index], "a", "b"), "p")
        assert_almost_equal(got[0], want[index], atol=1e-6)
    assert_equal(_lanes(values + "," + _op("p", "!", "a"), "p")[0], 0)
    assert_equal(_lanes(values + "," + _op("p", "~", "a"), "p")[0], -7)
    _refused(
        values + "," + _op("p", "=", "a", "b"),
        "p",
        "the operator = is not read",
    )


def test_the_math_of_one_value() raises:
    var methods: List[String] = [
        "radians",
        "degrees",
        "exp",
        "exp2",
        "log",
        "log2",
        "sqrt",
        "inversesqrt",
        "floor",
        "ceil",
        "normalize",
        "fract",
        "sin",
        "cos",
        "tan",
        "asin",
        "acos",
        "abs",
        "sign",
        "length",
        "negate",
        "oneMinus",
        "dFdx",
        "dFdy",
        "round",
        "reciprocal",
        "trunc",
        "fwidth",
        "sinh",
        "cosh",
        "tanh",
        "asinh",
        "acosh",
        "atanh",
        "atan",
    ]
    var inputs: List[String] = [
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "-0.5",
        "-0.5",
        "0.5",
        "-0.5",
        "0.5",
        "0.5",
        "0.5",
        "1.5",
        "0.5",
        "1.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "0.5",
        "1.5",
        "0.5",
        "0.5",
    ]
    var want: List[Float64] = [
        0.00872664626,
        28.6478897565,
        1.6487212707,
        1.41421356237,
        -0.69314718056,
        -1,
        0.70710678118,
        1.41421356237,
        0,
        1,
        1,
        0.5,
        0.4794255386,
        0.8775825619,
        0.5463024898,
        0.5235987756,
        1.0471975512,
        0.5,
        -1,
        0.5,
        0.5,
        0.5,
        0,
        0,
        2,
        2,
        1,
        0,
        0.5210953055,
        1.1276259652,
        0.4621171573,
        0.4812118251,
        0.9624236501,
        0.5493061443,
        0.463647609,
    ]
    for index in range(len(methods)):
        var got = _lanes(
            _const("a", inputs[index]) + "," + _math("p", methods[index], "a"),
            "p",
        )
        assert_almost_equal(Float64(got[0]), want[index], atol=1e-4)


def test_the_math_of_two_and_three_values() raises:
    var methods: List[String] = [
        "atan",
        "min",
        "max",
        "step",
        "distance",
        "difference",
        "dot",
        "pow",
        "equals",
        "reflect",
    ]
    var want: List[Float32] = [
        0.2449786631,
        0.5,
        2,
        1,
        1.5,
        1.5,
        1,
        0.25,
        0,
        -3.5,
    ]
    var values = _const("a", "0.5") + "," + _const("b", "2")
    for index in range(len(methods)):
        var got = _lanes(
            values + "," + _math("p", methods[index], "a", "b"), "p"
        )
        assert_almost_equal(got[0], want[index], atol=1e-5)
    var three = values + "," + _const("c", "0.25") + "," + _const("x", "3")
    # mix(0.5, 2, 0.25), clamp(3, 0.5, 2), smoothstep(0.5, 2, 3).
    assert_almost_equal(
        _lanes(three + "," + _math("p", "mix", "a", "b", "c"), "p")[0], 0.875
    )
    assert_almost_equal(
        _lanes(three + "," + _math("p", "clamp", "x", "a", "b"), "p")[0], 2
    )
    assert_almost_equal(
        _lanes(three + "," + _math("p", "smoothstep", "a", "b", "x"), "p")[0], 1
    )
    # Straight down through a floor, at half the index: still straight down.
    var down = (
        _const("i", "[0,-1,0]", "vec3")
        + ","
        + _const("n", "[0,1,0]", "vec3")
        + ","
        + _const("e", "0.5")
    )
    _near(
        _lanes(down + "," + _math("p", "refract", "i", "n", "e"), "p"), 0, -1, 0
    )
    # The ray meets the normal's back, so the normal stays as it is.
    _near(
        _lanes(down + "," + _math("p", "faceforward", "n", "i", "n"), "p"),
        0,
        1,
        0,
    )
    var axes = (
        _const("x", "[1,0,0]", "vec3") + "," + _const("y", "[0,1,0]", "vec3")
    )
    _near(_lanes(axes + "," + _math("p", "cross", "x", "y"), "p"), 0, 0, 1)
    _refused(
        values + "," + _math("p", "all", "a"),
        "p",
        "the math method all is not read",
    )
    _refused(
        values + "," + _math("p", "mix", "a", "b"),
        "p",
        "a MathNode has no cNode",
    )


def test_the_matrix_math() raises:
    # The columns (1, 0, 0), (2, 1, 0) and (0, 0, 2): the determinant is 2.
    var matrix = (
        _const("m", "[1,0,0,2,1,0,0,0,2]", "mat3")
        + ","
        + _const("v", "[1,1,1]", "vec3")
    )
    assert_almost_equal(
        _lanes(matrix + "," + _math("p", "determinant", "m"), "p")[0], 2
    )
    # The transpose times (1, 1, 1) sums each column.
    _near(
        _lanes(
            matrix
            + ","
            + _math("t", "transpose", "m")
            + ","
            + _op("p", "*", "t", "v"),
            "p",
        ),
        1,
        3,
        2,
    )
    # The inverse takes (3, 1, 2) back to (1, 1, 1).
    _near(
        _lanes(
            matrix
            + ","
            + _const("w", "[3,1,2]", "vec3")
            + ","
            + _math("t", "inverse", "m")
            + ","
            + _op("p", "*", "t", "w"),
            "p",
        ),
        1,
        1,
        1,
    )
    # A quarter turn about z takes x to y, with the matrix on either side.
    var turn = (
        _const("r", "[0,1,0,0,-1,0,0,0,0,0,1,0,0,0,0,1]", "mat4")
        + ","
        + _const("d", "[2,0,0]", "vec3")
    )
    _near(
        _lanes(turn + "," + _math("p", "transformDirection", "r", "d"), "p"),
        0,
        1,
        0,
    )
    _near(
        _lanes(turn + "," + _math("p", "transformDirection", "d", "r"), "p"),
        0,
        1,
        0,
    )


def test_the_swizzles_joins_and_selects() raises:
    var three = _const("k", "[1,2,3]", "vec3")
    _near(
        _lanes(
            three
            + ","
            + _node("s", "SplitNode", _in("node", "k"), '"components":"pts"'),
            "s",
        ),
        3,
        2,
        1,
    )
    var four = _const("q", "[1,2,3,4]", "vec4")
    _near(
        _lanes(
            four
            + ","
            + _node("s", "SplitNode", _in("node", "q"), '"components":"qbr"'),
            "s",
        ),
        4,
        3,
        1,
    )
    _refused(
        three
        + ","
        + _node("s", "SplitNode", _in("node", "k"), '"components":""'),
        "s",
        "A swizzle picks one to four components",
    )
    var parts = _const("a", "1") + "," + _uv("u")
    _near(
        _lanes(
            parts
            + ',{"uuid":"j","type":"JoinNode","inputNodes":{"nodes":["a","u"]}}',
            "j",
        ),
        1,
        0.25,
        0.75,
    )
    # Three vec3 columns are a mat3, and four vec4 columns a mat4.
    var columns = (
        _const("x", "[1,0,0]", "vec3")
        + ","
        + _const("y", "[0,2,0]", "vec3")
        + ","
        + _const("z", "[0,0,3]", "vec3")
        + ","
        + _const("one", "[1,1,1]", "vec3")
        + ',{"uuid":"m","type":"JoinNode","inputNodes":{"nodes":["x","y","z"]}}'
    )
    _near(_lanes(columns + "," + _op("p", "*", "m", "one"), "p"), 1, 2, 3)
    var wide = (
        _const("x", "[1,0,0,0]", "vec4")
        + ","
        + _const("y", "[0,1,0,0]", "vec4")
        + ","
        + _const("z", "[0,0,1,0]", "vec4")
        + ","
        + _const("w", "[4,5,6,1]", "vec4")
        + ","
        + _const("one", "[1,1,1,1]", "vec4")
        + ',{"uuid":"m","type":"JoinNode","inputNodes":{"nodes":["x","y","z","w"]}}'
    )
    _near(_lanes(wide + "," + _op("p", "*", "m", "one"), "p"), 5, 6, 7)
    # Nine or sixteen floats in other parts are no matrix.
    var pairs = (
        _const("a", "[1,2]", "vec2")
        + ","
        + _const("b", "[1,2,3]", "vec3")
        + ","
        + _const("c", "[1,2,3,4]", "vec4")
    )
    _refused(
        pairs
        + ',{"uuid":"j","type":"JoinNode","inputNodes":{"nodes":["a","a","a","b"]}}',
        "j",
        "A join makes at most four components, not 9",
    )
    _refused(
        pairs
        + ',{"uuid":"j","type":"JoinNode","inputNodes":{"nodes":["c","c","c","a","a"]}}',
        "j",
        "A join makes at most four components, not 16",
    )
    _refused(
        pairs + ',{"uuid":"j","type":"JoinNode","inputNodes":{"nodes":[]}}',
        "j",
        "A join needs at least one part",
    )
    _refused(
        pairs + ',{"uuid":"j","type":"JoinNode","inputNodes":{"nodes":"a"}}',
        "j",
        "a JoinNode needs a list of nodes",
    )
    _refused(
        pairs + ',{"uuid":"j","type":"JoinNode"}',
        "j",
        "a JoinNode needs a list of nodes",
    )


def _converted(value: String, type: String, to: String) raises -> Lanes:
    """Return a constant converted by a `ConvertNode`."""
    return _lanes(
        _const("k", value, type)
        + ","
        + _node(
            "c", "ConvertNode", _in("node", "k"), '"convertTo":"' + to + '"'
        ),
        "c",
    )


def test_a_conversion_is_three_js_s_format() raises:
    _near(_converted("2", "float", "vec3"), 2, 2, 2)
    var widened = _converted("[1,2]", "vec2", "vec4")
    _near(widened, 1, 2, 0)
    assert_equal(widened[3], 1)
    assert_equal(_converted("[1,2,3]", "vec3", "vec4")[3], 1)
    _near(_converted("[1,2]", "vec2", "vec3"), 1, 2, 0)
    assert_equal(_converted("[1,2,3]", "vec3", "float")[0], 1)
    _near(_converted("[1,2,3]", "vec3", "vec3"), 1, 2, 3)
    assert_equal(_converted("2.7", "float", "int")[0], 2)
    assert_equal(_converted("-1", "float", "uint")[0], Float32(4294967295))
    assert_equal(_converted("2", "float", "bool")[0], 1)
    assert_equal(_converted("0", "float", "bool")[0], 0)
    _near(_converted("[1.5,-2.5,3.9]", "vec3", "ivec3"), 1, -2, 3)
    _near(_converted("[1,2]", "vec2", "uvec2"), 1, 2, 0)
    _near(_converted("[0,2]", "vec2", "bvec2"), 0, 1, 0)
    _refused(
        _const("m", "[1,0,0,0,1,0,0,0,1]", "mat3")
        + ","
        + _node("c", "ConvertNode", _in("node", "m"), '"convertTo":"vec3"'),
        "c",
        "a matrix or a texture is not converted to another type",
    )
    # Of several types, the one as wide as the value, or else the first.
    var chosen = _converted("[1,2]", "vec2", "float|vec2|vec3")
    _near(chosen, 1, 2, 0)
    _near(_converted("5", "float", "vec3|vec4"), 5, 5, 5)
    _refused(
        _const("k", "[1,2,3]", "vec3")
        + ","
        + _node("c", "ConvertNode", _in("node", "k"), '"convertTo":"mat3"'),
        "c",
        "a matrix or a texture is not converted to another type",
    )
    _refused(
        _const("k", "1")
        + ","
        + _node("c", "ConvertNode", _in("node", "k"), '"convertTo":"foo"'),
        "c",
        "a conversion to foo is not read",
    )
    # A matrix converted to its own type is itself.
    var document = parse_json(
        "[" + _const("m", "[1,0,0,0,1,0,0,0,1]", "mat3") + "]"
    )
    var loader = NodeLoader()
    loader.parse_nodes(document, document.root())
    var matrix = loader.node(document, "m")
    assert_equal(loader.convert(matrix, "mat3").value, matrix.value)


def test_what_the_loader_refuses() raises:
    _refused(
        _node("a", "Node", _in("shaderNode", "b")),
        "a",
        "node a is a TSL function, which three.js writes without its body",
    )
    _refused(
        _node("a", "ModelNode", "", '"scope":"worldMatrix"'),
        "a",
        "a node type that is not read: ModelNode",
    )
    for kind in [
        String("MaterialNode"),
        String("PropertyNode"),
        String("StorageBufferNode"),
    ]:
        _refused(_node("a", kind), "a", "a node type that is not read: " + kind)
    _refused(_node("a", "VarNode"), "a", "a VarNode has no node")
    _refused(
        _node("a", "VarNode", _in("node", "b")), "a", "no node has the uuid b"
    )
    _refused(
        _node("a", "VarNode", _in("node", "b"))
        + ","
        + _node("b", "VarNode", _in("node", "a")),
        "a",
        "a node reads itself: a",
    )
    var document = parse_json(
        "[" + _const("a", "1") + "," + _const("a", "2") + "]"
    )
    var loader = NodeLoader()
    with assert_raises(contains="two nodes have the uuid a"):
        loader.parse_nodes(document, document.root())
    var bad = parse_json('{"a":1}')
    with assert_raises(contains="a list of nodes must be an array"):
        loader.parse_nodes(bad, bad.root())
    with assert_raises(contains="a node must be an object"):
        _ = loader.parse(parse_json("[1]"), 0)
    var numbers = parse_json("[1]")
    with assert_raises(contains="a node must be an object"):
        loader.parse_nodes(numbers, numbers.root())
    var nameless = parse_json('[{"type":"VarNode"}]')
    with assert_raises(contains="a node's uuid must be a string"):
        loader.parse_nodes(nameless, nameless.root())
    var typeless = parse_json('[{"uuid":"a","type":3}]')
    with assert_raises(contains="a node's type must be a string"):
        loader.parse_nodes(typeless, typeless.root())


def test_a_texture_node_reads_a_texture_uniform() raises:
    """Each texture node is a texture uniform named by its uuid, listed with
    the uuid of the file's texture it reads."""
    var document = parse_json("[" + NODES_B + "]")
    var loader = NodeLoader()
    loader.parse_nodes(document, document.root())
    loader.graph.set_output(COLOR_NODE, loader.node(document, "n1"))
    loader.graph.set_output(OPACITY_NODE, loader.node(document, "n2"))
    assert_equal(len(loader.textures), 3)
    assert_equal(loader.textures[0].uniform, "n8")
    assert_equal(loader.textures[0].texture, "n3")
    assert_equal(loader.textures[0].matrix, "")
    assert_false(loader.textures[0].cube)
    # The one with no coordinate reads `uv()` through the texture's matrix.
    assert_equal(loader.textures[1].uniform, "n14")
    assert_equal(loader.textures[1].matrix, "n14.matrix")
    assert_equal(loader.textures[2].uniform, "n17")
    var program = loader.graph.compile()
    var repeat = Matrix3()
    repeat.elements[0] = 2
    repeat.elements[4] = 3
    program.set_uniform("n14.matrix", repeat)
    assert_equal(program.uniform("n14.matrix")[0], 2)
    # A texel read with no level reads level zero; a cube reads in the
    # reflected view ray, or where its coordinate says.
    var more = parse_json(
        "["
        + _node(
            "t",
            "TextureNode",
            "",
            '"value":"tex","sampler":false,"updateMatrix":false',
        )
        + ","
        + _node("p", "TextureNode", "", '"value":"tex"')
        + ","
        + _node("c", "CubeTextureNode", "", '"value":"sky"')
        + ","
        + _const("d", "[1,0,0]", "vec3")
        + ","
        + _node("e", "CubeTextureNode", _in("uvNode", "d"), '"value":"sky"')
        + "]"
    )
    var other = NodeLoader()
    other.parse_nodes(more, more.root())
    other.graph.set_output(
        OPACITY_NODE,
        other.graph.add(
            other.graph.swizzle(other.node(more, "t"), "w"),
            other.graph.swizzle(other.node(more, "p"), "w"),
        ),
    )
    other.graph.set_output(
        COLOR_NODE,
        other.graph.add(
            other.graph.swizzle(other.node(more, "c"), "rgb"),
            other.graph.swizzle(other.node(more, "e"), "rgb"),
        ),
    )
    assert_false(other.textures[1].cube)
    assert_equal(other.textures[1].matrix, "")
    assert_true(other.textures[2].cube)
    assert_equal(other.textures[3].uniform, "e")
    var read = other.graph.compile()
    assert_equal(read.uniform("c")[0], -1)
    assert_equal(read.uniform("e")[0], -1)
    _refused(
        _const("b", "1")
        + ","
        + _node("t", "TextureNode", _in("biasNode", "b"), '"value":"tex"'),
        "t",
        "a texture node's biasNode is not read",
    )
    _refused(
        _const("b", "1")
        + ","
        + _node("t", "CubeTextureNode", _in("levelNode", "b"), '"value":"sky"'),
        "t",
        "a cube texture node's level is not read",
    )
    _refused(_node("t", "TextureNode"), "t", "a node's value must be a string")


def test_r186_generated_texture_gather_is_refused() raises:
    var root = String("assets/node_gather/")
    var document = parse_json(Path(root + "node.json").read_text())
    var loader = NodeLoader()
    with assert_raises(contains="a texture node's gatherNode is not read"):
        _ = loader.parse(document, document.root())
    assert_equal(len(loader.textures), 0)
    var material = Path(root + "material.json").read_text()
    with assert_raises(contains="a texture node's gatherNode is not read"):
        _ = read_node_material(material)
    var material_assets = Assets()
    with assert_raises(contains="a texture node's gatherNode is not read"):
        _ = read_material_json(material, material_assets)
    assert_equal(material_assets.programs.count(), 0)
    var scene = Scene()
    var scene_assets = Assets()
    with assert_raises(contains="a texture node's gatherNode is not read"):
        _ = read_object_json(
            Path(root + "object.json").read_text(), scene, scene_assets
        )
    assert_equal(scene_assets.programs.count(), 0)


def test_r186_raw_default_null_materials_reach_gather_refusal() raises:
    # Preserve the official raw bytes. Default null must pass material flags
    # and reach the same gather refusal as the explicit-side fixtures.
    var root = String("assets/node_gather/default_null/")
    var document = parse_json(Path(root + "node.json").read_text())
    var loader = NodeLoader()
    with assert_raises(contains="a texture node's gatherNode is not read"):
        _ = loader.parse(document, document.root())
    assert_equal(len(loader.textures), 0)
    var material = Path(root + "material.json").read_text()
    with assert_raises(contains="a texture node's gatherNode is not read"):
        _ = read_node_material(material)
    var material_assets = Assets()
    with assert_raises(contains="a texture node's gatherNode is not read"):
        _ = read_material_json(material, material_assets)
    assert_equal(material_assets.programs.count(), 0)
    var scene = Scene()
    var scene_assets = Assets()
    with assert_raises(contains="a texture node's gatherNode is not read"):
        _ = read_object_json(
            Path(root + "object.json").read_text(), scene, scene_assets
        )
    assert_equal(scene_assets.programs.count(), 0)


def test_texture_gather_preserves_required_value_error_precedence() raises:
    for kind in ["TextureNode", "CubeTextureNode"]:
        _refused(
            _node("t", kind, _in("gatherNode", "missing")),
            "t",
            "a node's value must be a string",
        )


def test_texture_gather_inputs_are_refused_before_their_children() raises:
    # A valid child, a missing child and an unsupported child must all name
    # gatherNode in the error, rather than silently become ordinary sampling.
    for child in [
        _const("g", "0", "int"),
        "",
        _node("g", "UnsupportedGatherChild"),
    ]:
        for kind in ["TextureNode", "CubeTextureNode"]:
            var texture = _node(
                "t", kind, _in("gatherNode", "g"), '"value":"tex"'
            )
            var nodes = texture
            if child != "":
                nodes += "," + child
            _refused(nodes, "t", "a texture node's gatherNode is not read")
            var document = parse_json(
                String(texture[byte = 0 : texture.byte_length() - 1])
                + ',"nodes":['
                + child
                + "]}"
            )
            var loader = NodeLoader()
            with assert_raises(
                contains="a texture node's gatherNode is not read"
            ):
                _ = loader.parse(document, document.root())
            assert_equal(len(loader.textures), 0)


def test_material_and_object_loaders_refuse_texture_gather() raises:
    for child in [
        _const("g", "0", "int"),
        "",
        _node("g", "UnsupportedGatherChild"),
    ]:
        var nodes = _node(
            "t", "TextureNode", _in("gatherNode", "g"), '"value":"tex"'
        )
        if child != "":
            nodes += "," + child
        var material = (
            '{"uuid":"m","type":"MeshBasicNodeMaterial",'
            '"inputNodes":{"colorNode":"t"}'
        )
        var standalone = material + ',"nodes":[' + nodes + "]}"
        with assert_raises(contains="a texture node's gatherNode is not read"):
            _ = read_node_material(standalone)
        var assets = Assets()
        with assert_raises(contains="a texture node's gatherNode is not read"):
            _ = read_material_json(standalone, assets)
        assert_equal(assets.programs.count(), 0)
        var scene = Scene()
        var object_assets = Assets()
        with assert_raises(contains="a texture node's gatherNode is not read"):
            _ = read_object_json(
                '{"metadata":{"version":4.7,"type":"Object"},"materials":['
                + material
                + '}],"nodes":['
                + nodes
                + '],"object":{"uuid":"s","type":"Scene"}}',
                scene,
                object_assets,
            )
        assert_equal(object_assets.programs.count(), 0)


def test_unreachable_gather_inputs_remain_unbuilt() raises:
    var nodes = (
        _const("c", "[0.2,0.4,0.6]", "vec3")
        + ","
        + _node(
            "t", "TextureNode", _in("gatherNode", "missing"), '"value":"tex"'
        )
        + ","
        + _node("u", "TextureNode", _in("gatherNode", "g"), '"value":"tex"')
        + ","
        + _node("g", "UnsupportedGatherChild")
    )
    var document = parse_json("[" + nodes + "]")
    var loader = NodeLoader()
    loader.parse_nodes(document, document.root())
    loader.graph.set_output(COLOR_NODE, loader.node(document, "c"))
    assert_equal(len(loader.textures), 0)
    var direct = loader.graph.compile()
    _near(_output(direct, COLOR_NODE), 0.2, 0.4, 0.6)
    var material = (
        '{"uuid":"m","type":"MeshBasicNodeMaterial",'
        '"inputNodes":{"colorNode":"c"}'
    )
    var standalone = material + ',"nodes":[' + nodes + "]}"
    var read = read_node_material(standalone)
    assert_equal(len(read.textures), 0)
    var program = read.graph.compile()
    _near(_output(program, COLOR_NODE), 0.2, 0.4, 0.6)
    var assets = Assets()
    var id = read_material_json(standalone, assets)
    _near(
        _output(
            assets.programs.get(assets.materials.get(id).nodes), COLOR_NODE
        ),
        0.2,
        0.4,
        0.6,
    )
    var scene = Scene()
    var object_assets = Assets()
    _ = read_object_json(
        '{"metadata":{"version":4.7,"type":"Object"},"materials":['
        + material
        + '}],"nodes":['
        + nodes
        + '],"object":{"uuid":"s","type":"Scene"}}',
        scene,
        object_assets,
    )
    _near(
        _output(
            object_assets.programs.get(
                object_assets.materials.get(MaterialId(0)).nodes
            ),
            COLOR_NODE,
        ),
        0.2,
        0.4,
        0.6,
    )


# --- NodeMaterialLoader -------------------------------------------------------


def test_a_node_material_sets_its_outputs() raises:
    var read = read_node_material(MATERIAL_A)
    assert_equal(len(read.textures), 0)
    var program = read.graph.compile()
    program.set_frame(Duration(0, SECOND), Matrix4())
    # At time zero the mix is the vertex colors.
    _near(_output(program, COLOR_NODE), 0.1, 0.2, 0.3)
    assert_equal(_output(program, OPACITY_NODE)[0], 0.75)
    assert_equal(_output(program, ROUGHNESS_NODE)[0], 0.75)
    # The tint is linear as three.js wrote it, named by its uuid.
    _near(program.uniform("n6"), 1, 0.5, 0.25)
    # three.js writes `time` as a plain uniform: at an eighth of a turn,
    # sin(2t) is one and the mix is halfway.
    program.set_uniform("n15", Float32(pi / 4))
    _near(_output(program, COLOR_NODE), 0.55, 0.35, 0.275)
    with assert_raises(contains="a node material must be an object"):
        _ = read_node_material("[]")


def test_the_normal_and_the_position_replace_what_they_name() raises:
    var read = read_node_material(MATERIAL_C)
    var program = read.graph.compile()
    # three.js's normal is in view space: up in view is up in the world
    # here, and the offset takes the fragment's normal away.
    program.set_frame(Duration(0, SECOND), Matrix4())
    _near(_output(program, NORMAL_NODE), 0, 1, -1)
    # With the camera turned a quarter about z, view up is world x.
    var turned = Matrix4()
    turned.elements[0] = 0
    turned.elements[1] = 1
    turned.elements[4] = -1
    turned.elements[5] = 0
    program.set_frame(Duration(0, SECOND), turned)
    _near(_output(program, NORMAL_NODE), 1, 0, -1)
    # `positionLocal.add(vec3(0, 1, 0))` moves each vertex up by one.
    var moved = moved_position(program, Vector3(1, 2, 3), Vector3(0, 0, 1))
    assert_almost_equal(moved.x, 1)
    assert_almost_equal(moved.y, 3)
    assert_almost_equal(moved.z, 3)


def _material(
    outputs: String, nodes: String, extra: String = ""
) raises -> NodeProgram:
    """Return the program of a material with these outputs and nodes."""
    var read = read_node_material(
        '{"uuid":"m","type":"MeshBasicNodeMaterial"'
        + extra
        + ',"inputNodes":{'
        + outputs
        + '},"nodes":['
        + nodes
        + "]}"
    )
    var program = read.graph.compile()
    program.set_frame(Duration(0, SECOND), Matrix4())
    return program^


def test_a_color_with_an_alpha_sets_the_opacity() raises:
    # A vec4 color's alpha multiplies the material's opacity.
    var read = read_node_material(MATERIAL_E)
    var program = read.graph.compile()
    _near(_output(program, COLOR_NODE), 0.2, 0.4, 0.6)
    assert_almost_equal(_output(program, OPACITY_NODE)[0], 0.25)
    # With no opacity written, three.js's default of one.
    var bare = _material(
        _in("colorNode", "c"), _const("c", "[0.2,0.4,0.6,0.5]", "vec4")
    )
    assert_almost_equal(_output(bare, OPACITY_NODE)[0], 0.5)
    # A float color is every component, the alpha too, times the opacity
    # node.
    var gray = _material(
        _in("colorNode", "c") + "," + _in("opacityNode", "o"),
        _const("c", "0.5") + "," + _const("o", "[0.5,0.5]", "vec2"),
    )
    _near(_output(gray, COLOR_NODE), 0.5, 0.5, 0.5)
    assert_almost_equal(_output(gray, OPACITY_NODE)[0], 0.25)
    # A vec3 color leaves the opacity alone.
    var plain = _material(
        _in("colorNode", "c"), _const("c", "[0.2,0.4,0.6]", "vec3")
    )
    assert_false(plain.has(OPACITY_NODE))
    # Each other output takes its own type, as three.js converts it.
    var outputs = _material(
        _in("outputNode", "c"), _const("c", "[0.1,0.2,0.3,0.4]", "vec4")
    )
    _near(_output(outputs, OUTPUT_NODE), 0.1, 0.2, 0.3)
    var whole = _material(
        _in("fragmentNode", "d"), _const("d", "[0.5,0.6,0.7]", "vec3")
    )
    var fragment = _output(whole, FRAGMENT_NODE)
    _near(fragment, 0.5, 0.6, 0.7)
    assert_equal(fragment[3], 1)


def test_what_a_node_material_refuses() raises:
    with assert_raises(contains="a node material needs inputNodes"):
        _ = read_node_material('{"uuid":"m"}')
    with assert_raises(contains="a node material needs inputNodes"):
        _ = read_node_material('{"uuid":"m","inputNodes":[]}')
    with assert_raises(contains="a node material's clearcoatNode is not read"):
        _ = read_node_material(
            '{"uuid":"m","inputNodes":{"clearcoatNode":"c"},"nodes":['
            + _const("c", "1")
            + "]}"
        )
    # A `nodes` object is this port's own program, not a list of nodes.
    with assert_raises(contains="no node has the uuid c"):
        _ = read_node_material(
            '{"uuid":"m","inputNodes":{"colorNode":"c"},"nodes":{}}'
        )
    # A material that sets nothing reads nothing.
    var empty = read_node_material('{"uuid":"m","inputNodes":{}}')
    assert_equal(len(empty.textures), 0)


# --- NodeObjectLoader ---------------------------------------------------------


def _png() raises -> String:
    """Return a one-texel image as a PNG data URL."""
    var texel: List[UInt8] = [10, 20, 30, 255]
    return (
        '"data:image/png;base64,'
        + encode_base64(encode_png(Framebuffer(1, 1, texel^)))
        + '"'
    )


def test_a_scene_file_reads_its_node_materials() raises:
    """Three.js's `NodeObjectLoader`: the document's `nodes` are shared by
    its materials, each texture node reads the texture the file names, and
    a node material with nodes of its own reads those too."""
    var png = _png()
    var faces = String()
    for face in range(6):
        if face > 0:
            faces += ","
        faces += png
    var text = (
        '{"metadata":{"version":4.7,"type":"Object","generator":"Object3D.toJSON"},'
        + '"materials":[{"uuid":"n0","type":"MeshBasicNodeMaterial",'
        + '"inputNodes":{"colorNode":"n1","opacityNode":"n2",'
        + '"emissiveNode":"k0"}},'
        + '{"uuid":"z0","type":"MeshStandardNodeMaterial",'
        + '"inputNodes":{"colorNode":"z1"},"nodes":['
        + _const("z1", "[1,0,0]", "vec3")
        + "]}],"
        + '"textures":[{"uuid":"n3","image":"n4","mapping":300,'
        + '"repeat":[2,3]},{"uuid":"sky","image":"six"}],'
        + '"images":[{"uuid":"n4","url":'
        + png
        + '},{"uuid":"six","url":['
        + faces
        + "]}],"
        + '"nodes":['
        + NODES_B
        + ","
        + _const("dir", "[1,0,0]", "vec3")
        + ","
        + _node("k1", "CubeTextureNode", _in("uvNode", "dir"), '"value":"sky"')
        + ","
        + _node("k0", "SplitNode", _in("node", "k1"), '"components":"xyz"')
        + "],"
        + '"object":{"uuid":"s","type":"Scene"}}'
    )
    var scene = Scene()
    var assets = Assets()
    _ = read_object_json(text, scene, assets)
    ref basic = assets.materials.get(MaterialId(0))
    assert_true(basic.kind == BASIC)
    ref program = assets.programs.get(basic.nodes)
    # The three texture nodes read the one texture.
    assert_equal(len(program.textures), 1)
    var id = program.uniform("n8")[0]
    assert_true(id >= 0)
    assert_equal(program.uniform("n14")[0], id)
    assert_equal(program.uniform("n17")[0], id)
    # Its transform is the texture's: a repeat of two across, three up.
    assert_equal(program.uniform("n14.matrix")[0], 2)
    for index in range(len(program.uniform_names)):
        if program.uniform_names[index] == "n14.matrix":
            assert_equal(program.code[program.uniform_offsets[index] + 4], 3)
    assert_equal(len(program.cubes), 1)
    assert_true(program.uniform("k1")[0] >= 0)
    ref standard = assets.materials.get(MaterialId(1))
    assert_true(standard.kind == STANDARD)
    _near(_output(assets.programs.get(standard.nodes), COLOR_NODE), 1, 0, 0)


def test_a_lone_node_material_file_is_read() raises:
    """Three.js's `NodeMaterialLoader`: the material's own nodes."""
    var assets = Assets()
    var id = read_material_json(MATERIAL_A, assets)
    ref material = assets.materials.get(id)
    assert_true(material.kind == STANDARD)
    ref program = assets.programs.get(material.nodes)
    assert_true(program.has(ROUGHNESS_NODE))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
