# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.fbx_tree` and `loaders.fbx`: two ASCII scenes
checked against what three.js r180's `FBXLoader` builds from them, binary
files built here byte by byte, and small files for every branch and every
refusal.

The expected numbers of `test_scene` and `test_pivots` were printed by
running the same text through `FBXLoader.parse` in Node. The triangles of
a polygon of four or more corners come out in another order, because
three.js cuts them with earcut and this port with ear clipping; the
surface is the same.
"""

from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV
from core.geometry_store import GeometryId
from core.scene import Scene
from lights.light import AMBIENT, DIRECTIONAL, POINT, SPOT
from loaders.fbx import (
    ALL_SAME,
    BY_POLYGON,
    BY_POLYGON_VERTEX,
    BY_VERTEX,
    DIRECT,
    INDEX_TO_DIRECT,
    MAX_MODEL_DEPTH,
    FbxLayer,
    FbxMapping,
    FbxModel,
    FbxReference,
    fbx_euler_order,
    fbx_mapping,
    fbx_reference,
    load_fbx,
    read_fbx,
    sanitize_node_name,
)
from loaders.fbx_tree import (
    FBX_ASCII,
    FBX_BINARY,
    FBX_BYTES,
    FBX_NUMBERS,
    MAX_FBX_DEPTH,
    NO_FBX_NODE,
    FbxDocument,
    FbxFormat,
    FbxProperty,
    FbxPropertyKind,
    integer_property,
    number_property,
    object_name,
    parse_fbx,
    parse_fbx_text,
    string_property,
)
from loaders.gltf import decode_base64
from materials.material import LAMBERT, NO_TEXTURE, PHONG, Material
from math.euler import YXZ, ZYX
from math.quaternion import Quaternion
from math.vector3 import Vector3
from render.png import zlib_stream
from render.srgb import LINEAR, SRGB
from render.texture import CLAMP, COVERAGE, IGNORED, REPEAT
from std.memory import bitcast
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import CENTIMETER, DEGREE, METER

# The scene three.js was run on: a mesh of a quad, a triangle and a
# pentagon in two materials, a model hierarchy, a camera, three lights
# and global settings.
comptime SCENE = (
    "; FBX 7.4.0 project file\nFBXHeaderExtension:  {\n\tFBXHeaderVersion:"
    " 1003\n\tFBXVersion: 7400\n}\nGlobalSettings:  {\n\tVersion:"
    ' 1000\n\tProperties70:  {\n\t\tP: "UnitScaleFactor", "double", "Number",'
    ' "",2.54\n\t\tP: "AmbientColor", "ColorRGB", "Color",'
    ' "",0.2,0.4,0.6\n\t}\n}\nObjects:  {\n\tGeometry: 100, "Geometry::Shape",'
    ' "Mesh" {\n\t\tVertices: *24 {\n\t\t\ta:'
    " 0,0,0,1,0,0,1,1,0,0,1,0,2,0,0,3,0,0,3,1,0,2,2,0\n\t\t}\n\t\tPolygonVertexIndex:"
    " *12 {\n\t\t\ta:"
    " 0,1,2,-4,1,4,-8,4,5,6,7,-3\n\t\t}\n\t\tLayerElementNormal: 0"
    ' {\n\t\t\tVersion: 101\n\t\t\tName: ""\n\t\t\tMappingInformationType:'
    ' "ByPolygonVertex"\n\t\t\tReferenceInformationType:'
    ' "Direct"\n\t\t\tNormals: *36 {\n\t\t\t\ta:'
    " 0,0,1,0,0,1,0,0,1,0,0,1,0,0,1,0,0,1,0,0,1,0,0,1,0,0,1,0,0,1,0,0,1,0,0,1\n\t\t\t}\n\t\t}\n\t\tLayerElementUV:"
    " 0 {\n\t\t\tVersion: 101\n\t\t\tName:"
    ' "map1"\n\t\t\tMappingInformationType:'
    ' "ByPolygonVertex"\n\t\t\tReferenceInformationType:'
    ' "IndexToDirect"\n\t\t\tUV: *8 {\n\t\t\t\ta:'
    " 0,0,1,0,1,1,0,1\n\t\t\t}\n\t\t\tUVIndex: *12 {\n\t\t\t\ta:"
    " 0,1,2,3,0,1,2,0,1,2,3,3\n\t\t\t}\n\t\t}\n\t\tLayerElementColor: 0"
    ' {\n\t\t\tVersion: 101\n\t\t\tName: ""\n\t\t\tMappingInformationType:'
    ' "ByVertice"\n\t\t\tReferenceInformationType: "Direct"\n\t\t\tColors: *32'
    " {\n\t\t\t\ta:"
    " 1,0,0,1,0,1,0,1,0,0,1,1,1,1,1,1,0.5,0.5,0.5,1,0.25,0.25,0.25,1,1,1,0,1,0,1,1,1\n\t\t\t}\n\t\t}\n\t\tLayerElementMaterial:"
    ' 0 {\n\t\t\tVersion: 101\n\t\t\tName: ""\n\t\t\tMappingInformationType:'
    ' "ByPolygon"\n\t\t\tReferenceInformationType:'
    ' "IndexToDirect"\n\t\t\tMaterials: *3 {\n\t\t\t\ta:'
    ' 0,1,0\n\t\t\t}\n\t\t}\n\t}\n\tModel: 200, "Model::Box Root", "Mesh"'
    ' {\n\t\tVersion: 232\n\t\tProperties70:  {\n\t\t\tP: "RotationOrder",'
    ' "enum", "", "",4\n\t\t\tP: "PreRotation", "Vector3D", "Vector",'
    ' "",0,0,90\n\t\t\tP: "Lcl Translation", "Lcl Translation", "",'
    ' "A",1,2,3\n\t\t\tP: "Lcl Rotation", "Lcl Rotation", "",'
    ' "A",10,20,30\n\t\t\tP: "Lcl Scaling", "Lcl Scaling", "",'
    ' "A",2,2,2\n\t\t\tP: "GeometricTranslation", "Vector3D", "Vector",'
    ' "",0,0,1\n\t\t}\n\t\tShading: T\n\t\tCulling: "CullingOff"\n\t}\n\tModel:'
    ' 201, "Model::Child", "Null" {\n\t\tVersion: 232\n\t\tProperties70: '
    ' {\n\t\t\tP: "InheritType", "enum", "", "",1\n\t\t\tP: "Lcl Translation",'
    ' "Lcl Translation", "", "A",0,5,0\n\t\t\tP: "RotationPivot", "Vector3D",'
    ' "Vector", "",1,0,0\n\t\t\tP: "Lcl Rotation", "Lcl Rotation", "",'
    ' "A",0,0,45\n\t\t\tP: "PostRotation", "Vector3D", "Vector",'
    ' "",15,0,0\n\t\t\tP: "ScalingPivot", "Vector3D", "Vector",'
    ' "",0,1,0\n\t\t\tP: "Lcl Scaling", "Lcl Scaling", "",'
    ' "A",1,3,1\n\t\t}\n\t}\n\tModel: 202, "Model::Lamp", "Light"'
    ' {\n\t\tVersion: 232\n\t\tProperties70:  {\n\t\t\tP: "Lcl Translation",'
    ' "Lcl Translation", "", "A",0,10,0\n\t\t}\n\t}\n\tModel: 203,'
    ' "Model::Cam", "Camera" {\n\t\tVersion: 232\n\t\tProperties70: '
    ' {\n\t\t\tP: "Lcl Translation", "Lcl Translation", "",'
    ' "A",0,0,20\n\t\t}\n\t}\n\tModel: 204, "Model::Bulb", "Light"'
    ' {\n\t\tVersion: 232\n\t}\n\tModel: 205, "Model::Sun", "Light"'
    ' {\n\t\tVersion: 232\n\t\tProperties70:  {\n\t\t\tP: "Lcl Rotation", "Lcl'
    ' Rotation", "", "A",-45,0,0\n\t\t}\n\t}\n\tNodeAttribute: 400,'
    ' "NodeAttribute::Lamp", "Light" {\n\t\tProperties70:  {\n\t\t\tP:'
    ' "LightType", "enum", "", "",2\n\t\t\tP: "Color", "Color", "",'
    ' "A",1,0.5,0\n\t\t\tP: "Intensity", "Number", "", "A",50\n\t\t\tP:'
    ' "InnerAngle", "Number", "", "A",40\n\t\t\tP: "OuterAngle", "Number", "",'
    ' "A",50\n\t\t\tP: "FarAttenuationEnd", "Number", "", "A",10\n\t\t\tP:'
    ' "CastShadows", "bool", "", "",1\n\t\t}\n\t}\n\tNodeAttribute: 401,'
    ' "NodeAttribute::Cam", "Camera" {\n\t\tProperties70:  {\n\t\t\tP:'
    ' "FieldOfView", "FieldOfView", "", "A",60\n\t\t\tP: "AspectWidth",'
    ' "double", "Number", "",320\n\t\t\tP: "AspectHeight", "double", "Number",'
    ' "",240\n\t\t\tP: "NearPlane", "double", "Number", "",10\n\t\t\tP:'
    ' "FarPlane", "double", "Number", "",10000\n\t\t}\n\t}\n\tNodeAttribute:'
    ' 402, "NodeAttribute::Bulb", "Light" {\n\t\tProperties70:  {\n\t\t\tP:'
    ' "LightType", "enum", "", "",0\n\t\t\tP: "FarAttenuationEnd", "Number",'
    ' "", "A",7\n\t\t\tP: "EnableFarAttenuation", "bool", "",'
    ' "",0\n\t\t}\n\t}\n\tNodeAttribute: 403, "NodeAttribute::Sun", "Light"'
    ' {\n\t\tProperties70:  {\n\t\t\tP: "LightType", "enum", "", "",1\n\t\t\tP:'
    ' "CastLightOnObject", "bool", "", "",0\n\t\t}\n\t}\n\tMaterial: 300,'
    ' "Material::Red", "" {\n\t\tVersion: 102\n\t\tShadingModel:'
    ' "phong"\n\t\tMultiLayer: 0\n\t\tProperties70:  {\n\t\t\tP:'
    ' "DiffuseColor", "Color", "", "A",1,0,0\n\t\t\tP: "Specular", "Vector3D",'
    ' "Vector", "",0.5,0.5,0.5\n\t\t\tP: "Shininess", "double", "Number",'
    ' "",20\n\t\t\tP: "Emissive", "Vector3D", "Vector", "",0,0.2,0\n\t\t\tP:'
    ' "EmissiveFactor", "double", "Number", "",2\n\t\t\tP:'
    ' "TransparencyFactor", "double", "Number", "",0.25\n\t\t\tP:'
    ' "ReflectionFactor", "double", "Number", "",0.5\n\t\t}\n\t}\n\tMaterial:'
    ' 301, "Material::Green", "" {\n\t\tVersion: 102\n\t\tShadingModel:'
    ' "Lambert"\n\t\tProperties70:  {\n\t\t\tP: "Diffuse", "Vector3D",'
    ' "Vector", "",0,1,0\n\t\t\tP: "TransparencyFactor", "double", "Number",'
    ' "",1\n\t\t\tP: "Opacity", "double", "Number", "",0.5\n\t\t\tP:'
    ' "BumpFactor", "double", "Number", "",0.3\n\t\t}\n\t}\n\tMaterial: 302,'
    ' "Material::Unused", "" {\n\t\tShadingModel: "phong"\n\t}\n}\nConnections:'
    '  {\n\t;Model::Box Root, Model::RootNode\n\tC: "OO",200,0\n\tC:'
    ' "OO",100,200\n\tC: "OO",300,200\n\tC: "OO",301,200\n\tC:'
    ' "OO",201,200\n\tC: "OO",202,201\n\tC: "OO",400,202\n\tC: "OO",203,0\n\tC:'
    ' "OO",401,203\n\tC: "OO",204,0\n\tC: "OO",402,204\n\tC: "OO",205,0\n\tC:'
    ' "OO",403,205\n}\n'
)

# Pivots, offsets, the three inherit types and the rotation orders.
comptime PIVOTS = (
    "; FBX 7.4.0 project file\n"
    "FBXHeaderExtension:  {\n"
    "\tFBXVersion: 7400\n"
    "}\n"
    "Objects:  {\n"
    '\tModel: 1, "Model::Parent", "Null" {\n'
    "\t\tProperties70:  {\n"
    '\t\t\tP: "Lcl Translation", "Lcl Translation", "", "A",1,0,0\n'
    '\t\t\tP: "Lcl Rotation", "Lcl Rotation", "", "A",0,30,0\n'
    '\t\t\tP: "Lcl Scaling", "Lcl Scaling", "", "A",1,2,3\n'
    '\t\t\tP: "RotationOrder", "enum", "", "",2\n'
    '\t\t\tP: "RotationOffset", "Vector3D", "Vector", "",0.5,0,0\n'
    '\t\t\tP: "ScalingOffset", "Vector3D", "Vector", "",0,0.25,0\n'
    "\t\t}\n"
    "\t}\n"
    '\tModel: 2, "Model::Kid", "Null" {\n'
    "\t\tProperties70:  {\n"
    '\t\t\tP: "InheritType", "enum", "", "",2\n'
    '\t\t\tP: "Lcl Translation", "Lcl Translation", "", "A",0,1,0\n'
    '\t\t\tP: "Lcl Rotation", "Lcl Rotation", "", "A",20,0,10\n'
    '\t\t\tP: "Lcl Scaling", "Lcl Scaling", "", "A",2,1,1\n'
    '\t\t\tP: "RotationOrder", "enum", "", "",5\n'
    "\t\t}\n"
    "\t}\n"
    '\tModel: 3, "Model::Other", "Null" {\n'
    "\t\tProperties70:  {\n"
    '\t\t\tP: "Lcl Translation", "Lcl Translation", "", "A",0,0,1\n'
    '\t\t\tP: "Lcl Rotation", "Lcl Rotation", "", "A",5,10,15\n'
    '\t\t\tP: "RotationOrder", "enum", "", "",1\n'
    "\t\t}\n"
    "\t}\n"
    '\tModel: 4, "Model::Last", "Null" {\n'
    "\t\tProperties70:  {\n"
    '\t\t\tP: "Lcl Rotation", "Lcl Rotation", "", "A",5,10,15\n'
    '\t\t\tP: "RotationOrder", "enum", "", "",3\n'
    '\t\t\tP: "InheritType", "enum", "", "",0\n'
    "\t\t}\n"
    "\t}\n"
    '\tModel: 5, "Model::Spin", "Null" {\n'
    "\t\tProperties70:  {\n"
    '\t\t\tP: "Lcl Rotation", "Lcl Rotation", "", "A",5,10,15\n'
    '\t\t\tP: "RotationOrder", "enum", "", "",6\n'
    "\t\t}\n"
    "\t}\n"
    "}\n"
    "Connections:  {\n"
    '\tC: "OO",1,0\n'
    '\tC: "OO",2,1\n'
    '\tC: "OO",3,2\n'
    '\tC: "OO",4,1\n'
    '\tC: "OO",5,0\n'
    "}\n"
)

# A two-by-two checker PNG, as base64, for the embedded images.
comptime CHECKER = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC"
comptime HERE = "assets/gltf/"


# --- building binary files ----------------------------------------------------


def le(value: Int, width: Int) -> List[UInt8]:
    """Return a number as `width` little-endian bytes."""
    var out = List[UInt8]()
    for index in range(width):
        out.append(UInt8((value >> (8 * index)) & 0xFF))
    return out^


def text_bytes(text: String) -> List[UInt8]:
    """Return a string's bytes."""
    var out = List[UInt8]()
    for byte in text.as_bytes():
        out.append(byte)
    return out^


def joined(parts: List[List[UInt8]]) -> List[UInt8]:
    """Return byte lists one after another."""
    var out = List[UInt8]()
    for part in parts:
        out.extend(part.copy())
    return out^


def p_code(code: String) -> List[UInt8]:
    """Return a property's one-letter type code."""
    return text_bytes(code)


def p_int(code: String, value: Int, width: Int) -> List[UInt8]:
    """Return a whole-number property: `Y`, `C`, `I` or `L`."""
    var out = p_code(code)
    out.extend(le(value, width))
    return out^


def p_f64(value: Float64) -> List[UInt8]:
    """Return a `D` property."""
    var out = p_code("D")
    out.extend(le(Int(bitcast[DType.uint64](value)), 8))
    return out^


def p_f32(value: Float32) -> List[UInt8]:
    """Return an `F` property."""
    var out = p_code("F")
    out.extend(le(Int(bitcast[DType.uint32](value)), 4))
    return out^


def p_str(text: String) -> List[UInt8]:
    """Return an `S` property."""
    var out = p_code("S")
    out.extend(le(text.byte_length(), 4))
    out.extend(text_bytes(text))
    return out^


def p_raw(bytes: List[UInt8]) -> List[UInt8]:
    """Return an `R` property."""
    var out = p_code("R")
    out.extend(le(len(bytes), 4))
    out.extend(bytes.copy())
    return out^


def p_array(
    code: String, count: Int, raw: List[UInt8], compress: Bool
) -> List[UInt8]:
    """Return an array property of `count` elements, raw or zlib."""
    var out = p_code(code)
    out.extend(le(count, 4))
    if compress:
        var packed = zlib_stream(raw)
        out.extend(le(1, 4))
        out.extend(le(len(packed), 4))
        out.extend(packed^)
    else:
        out.extend(le(0, 4))
        out.extend(le(len(raw), 4))
        out.extend(raw.copy())
    return out^


def doubles(values: List[Float64], compress: Bool) -> List[UInt8]:
    """Return a `d` array property."""
    var raw = List[UInt8]()
    for value in values:
        raw.extend(le(Int(bitcast[DType.uint64](value)), 8))
    return p_array("d", len(values), raw, compress)


def ints(values: List[Int], compress: Bool) -> List[UInt8]:
    """Return an `i` array property."""
    var raw = List[UInt8]()
    for value in values:
        raw.extend(le(value, 4))
    return p_array("i", len(values), raw, compress)


struct Tree(Movable):
    """Records to write, each naming its parent, the root being -1."""

    var names: List[String]
    var props: List[List[UInt8]]
    var counts: List[Int]
    var parents: List[Int]

    def __init__(out self):
        self.names = List[String]()
        self.props = List[List[UInt8]]()
        self.counts = List[Int]()
        self.parents = List[Int]()

    def add(
        mut self, parent: Int, name: String, var props: List[UInt8], count: Int
    ) -> Int:
        """Add a record and return its index."""
        self.names.append(name)
        self.props.append(props^)
        self.counts.append(count)
        self.parents.append(parent)
        return len(self.names) - 1

    def leaf(mut self, parent: Int, name: String, var props: List[UInt8]):
        """Add a record of one property."""
        _ = self.add(parent, name, props^, 1)


def write(tree: Tree, node: Int, at: Int, wide: Bool) -> List[UInt8]:
    """Return one record and its children, starting at file offset `at`."""
    var size = 4
    if wide:
        size = 8
    var header = 3 * size + 1 + tree.names[node].byte_length()
    var body = tree.props[node].copy()
    var offset = at + header + len(body)
    var children = List[UInt8]()
    var any = False
    for child in range(len(tree.names)):
        if tree.parents[child] == node:
            var written = write(tree, child, offset, wide)
            offset += len(written)
            children.extend(written^)
            any = True
    if any:
        children.extend(List[UInt8](length=3 * size + 1, fill=0))
    var out = le(at + header + len(body) + len(children), size)
    out.extend(le(tree.counts[node], size))
    out.extend(le(len(body), size))
    out.append(UInt8(tree.names[node].byte_length()))
    out.extend(text_bytes(tree.names[node]))
    out.extend(body^)
    out.extend(children^)
    return out^


def binary(tree: Tree, version: Int, aligned: Bool = False) -> List[UInt8]:
    """Return a binary file of the records, with a footer of zeros that
    three.js's `endOfContent` stops in."""
    var out = text_bytes("Kaydara FBX Binary  \x00")
    out.append(0x1A)
    out.append(0)
    out.extend(le(version, 4))
    for node in range(len(tree.names)):
        if tree.parents[node] == -1:
            out.extend(write(tree, node, len(out), version >= 7500))
    var footer = 176
    if aligned:
        footer += (16 - (len(out) + footer) % 16) % 16
    else:
        if (len(out) + footer) % 16 == 0:
            footer += 1
    out.extend(List[UInt8](length=footer, fill=0))
    return out^


def p70(
    mut tree: Tree,
    parent: Int,
    name: String,
    kind: String,
    var values: List[Float64],
):
    """Add a `P` entry of numbers."""
    var props = p_str(name)
    props.extend(p_str(kind))
    props.extend(p_str(""))
    props.extend(p_str("A"))
    for value in values:
        props.extend(p_f64(value))
    _ = tree.add(parent, "P", props^, 4 + len(values))


def quad_tree(compress: Bool) -> Tree:
    """Return a binary file's records for a quad model with a material:
    the same as `QUAD`."""
    var tree = Tree()
    var objects = tree.add(-1, "Objects", List[UInt8](), 0)
    var props = p_int("L", 10, 8)
    props.extend(p_str("Quad\x00\x01Geometry"))
    props.extend(p_str("Mesh"))
    var geometry = tree.add(objects, "Geometry", props^, 3)
    tree.leaf(
        geometry,
        "Vertices",
        doubles([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0], compress),
    )
    tree.leaf(geometry, "PolygonVertexIndex", ints([0, 1, 2, -4], compress))
    var layer = tree.add(geometry, "LayerElementNormal", p_int("I", 0, 4), 1)
    tree.leaf(layer, "MappingInformationType", p_str("AllSame"))
    tree.leaf(layer, "ReferenceInformationType", p_str("Direct"))
    tree.leaf(layer, "Normals", doubles([0, 0, 1], compress))
    props = p_int("L", 20, 8)
    props.extend(p_str("Quad\x00\x01Model"))
    props.extend(p_str("Mesh"))
    var model = tree.add(objects, "Model", props^, 3)
    var properties = tree.add(model, "Properties70", List[UInt8](), 0)
    p70(tree, properties, "Lcl Translation", "Lcl Translation", [1, 2, 3])
    props = p_int("L", 30, 8)
    props.extend(p_str("Mat\x00\x01Material"))
    props.extend(p_str(""))
    var material = tree.add(objects, "Material", props^, 3)
    tree.leaf(material, "ShadingModel", p_str("lambert"))
    properties = tree.add(material, "Properties70", List[UInt8](), 0)
    p70(tree, properties, "DiffuseColor", "Color", [0, 0, 1])
    var connections = tree.add(-1, "Connections", List[UInt8](), 0)
    for pair in [(10, 20), (20, 0), (30, 20)]:
        props = p_str("OO")
        props.extend(p_int("L", pair[0], 8))
        props.extend(p_int("L", pair[1], 8))
        _ = tree.add(connections, "C", props^, 3)
    return tree^


comptime QUAD = (
    "FBXHeaderExtension:  {\n\tFBXVersion: 7300\n}\n"
    'Objects:  {\n\tGeometry: 10, "Geometry::Quad", "Mesh" {\n'
    "\t\tVertices: *12 {\n\t\t\ta: 0,0,0,1,0,0,1,1,0,0,1,0\n\t\t}\n"
    "\t\tPolygonVertexIndex: *4 {\n\t\t\ta: 0,1,2,-4\n\t\t}\n"
    '\t\tLayerElementNormal: 0 {\n\t\t\tMappingInformationType: "AllSame"\n'
    '\t\t\tReferenceInformationType: "Direct"\n'
    "\t\t\tNormals: *3 {\n\t\t\t\ta: 0,0,1\n\t\t\t}\n\t\t}\n\t}\n"
    '\tModel: 20, "Model::Quad", "Mesh" {\n\t\tProperties70:  {\n'
    '\t\t\tP: "Lcl Translation", "Lcl Translation", "", "A",1,2,3\n'
    "\t\t}\n\t}\n"
    '\tMaterial: 30, "Material::Mat", "" {\n\t\tShadingModel: "lambert"\n'
    '\t\tProperties70:  {\n\t\t\tP: "DiffuseColor", "Color", "", "A",0,0,1\n'
    "\t\t}\n\t}\n}\n"
    'Connections:  {\n\tC: "OO",10,20\n\tC: "OO",20,0\n\tC: "OO",30,20\n}\n'
)


# --- helpers ------------------------------------------------------------------


def objects(body: String, connections: String = "") -> String:
    """Return an ASCII file of some objects and connections."""
    return (
        "FBXHeaderExtension:  {\n\tFBXVersion: 7400\n}\nObjects:  {\n"
        + body
        + "}\nConnections:  {\n"
        + connections
        + "}\n"
    )


def load_text(
    text: String, mut scene: Scene, mut assets: Assets
) raises -> FbxModel:
    """Read an ASCII file into a scene."""
    return load_fbx(parse_fbx_text(text), HERE, scene, assets)


def refused(text: String) raises:
    """Assert that reading an ASCII file is refused."""
    var scene = Scene()
    var assets = Assets()
    try:
        _ = load_text(text, scene, assets)
    except:
        return
    print("the FBX loader read what it should refuse: " + text)
    raise Error("not refused")


def refused_bytes(bytes: List[UInt8]) raises:
    """Assert that `parse_fbx` refuses some bytes."""
    try:
        _ = parse_fbx(bytes)
    except:
        return
    raise Error("parse_fbx read bytes it should refuse")


def values(
    assets: Assets, id: GeometryId, name: String
) raises -> List[Float32]:
    """Return a copy of one attribute's numbers."""
    return assets.geometries.get(id).clone_attribute(name).data.copy()


def assert_list(actual: List[Float32], expected: List[Float32]) raises:
    """Assert that two lists of numbers are close, entry by entry."""
    assert_equal(len(actual), len(expected))
    for index in range(len(actual)):
        assert_almost_equal(actual[index], expected[index], atol=1e-5)


def assert_near(actual: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert that a vector is close to (x, y, z)."""
    assert_almost_equal(actual.x, x, atol=2e-5)
    assert_almost_equal(actual.y, y, atol=2e-5)
    assert_almost_equal(actual.z, z, atol=2e-5)


def assert_turn(
    actual: Quaternion, x: Float32, y: Float32, z: Float32, w: Float32
) raises:
    """Assert that a rotation is close to (x, y, z, w)."""
    assert_almost_equal(actual.x, x, atol=2e-5)
    assert_almost_equal(actual.y, y, atol=2e-5)
    assert_almost_equal(actual.z, z, atol=2e-5)
    assert_almost_equal(actual.w, w, atol=2e-5)


# --- the fixtures, against three.js -------------------------------------------


def test_scene() raises:
    """The ASCII fixture, against what three.js r180's `FBXLoader` gives."""
    var scene = Scene()
    var assets = Assets()
    var model = load_fbx(parse_fbx_text(SCENE), "", scene, assets)
    assert_equal(model.format, FBX_ASCII)
    assert_equal(model.version, 7400)
    assert_almost_equal(model.unit.to(METER), 0.0254)
    var names: List[String] = [
        "Box_Root",
        "Child",
        "Lamp",
        "Cam",
        "Bulb",
        "Sun",
    ]
    assert_equal(len(model.models), len(names))
    for index in range(len(names)):
        assert_equal(model.model_names[index], names[index])
    assert_equal(model.model_ids[0], 200)
    assert_equal(model.model("Cam"), model.models[3])
    with assert_raises():
        _ = model.model("None")
    scene.update()
    var box = scene.get(model.models[0])
    assert_near(box.position, 1, 2, 3)
    assert_turn(box.quaternion, -0.01216, 0.19273, 0.84206, 0.50364)
    assert_near(box.scale, 2, 2, 2)
    var child = scene.get(model.models[1])
    assert_near(child.position, 1.65892, 2.92687, 0.51764)
    assert_turn(child.quaternion, -0.12059, -0.04995, 0.37941, 0.91598)
    assert_near(child.scale, 1, 3, 1)
    assert_near(
        scene.world_position(model.models[1]), -5.44641, 2.69801, 5.07429
    )
    assert_near(scene.get(model.models[2]).position, 0, 11, 0)
    assert_near(
        scene.world_position(model.models[2]), -24.66201, -59.94087, 13.01987
    )
    var sun = scene.get(model.models[5])
    assert_near(sun.position, 0, 0.70711, -0.70711)
    assert_turn(sun.quaternion, -0.38268, 0, 0, 0.92388)
    # The lights: the spot, the bulb, the sun, and the ambient light the
    # global settings ask for.
    assert_equal(model.light_count, 4)
    var spot = scene.lights[0]
    assert_equal(spot.kind, SPOT)
    assert_equal(spot.node, model.models[2])
    assert_almost_equal(spot.intensity, 0.5)
    assert_almost_equal(spot.distance, 10)
    assert_almost_equal(spot.decay, 1)
    assert_almost_equal(spot.angle.value, 0.6981317, atol=1e-6)
    assert_almost_equal(spot.penumbra, 1)
    assert_true(spot.cast_shadow)
    assert_equal(spot.color.g, 128)
    var bulb = scene.lights[1]
    assert_equal(bulb.kind, POINT)
    assert_almost_equal(bulb.intensity, 1)
    assert_almost_equal(bulb.distance, 0)
    assert_almost_equal(bulb.decay, 1)
    var light = scene.lights[2]
    assert_equal(light.kind, DIRECTIONAL)
    assert_almost_equal(light.intensity, 0)
    assert_false(light.cast_shadow)
    var ambient = scene.lights[3]
    assert_equal(ambient.kind, AMBIENT)
    assert_equal(ambient.color.r, 51)
    assert_equal(ambient.color.g, 102)
    assert_equal(ambient.color.b, 153)
    # The camera.
    assert_equal(len(model.cameras), 1)
    var camera = model.cameras[0]
    assert_equal(camera.node, model.models[3])
    assert_almost_equal(camera.fov.to(DEGREE), 60, atol=1e-4)
    assert_almost_equal(camera.aspect, 1.3333334)
    assert_almost_equal(camera.near.value, 0.01)
    assert_almost_equal(camera.far.value, 10)
    # The materials: the unused one is left out.
    assert_equal(len(model.materials), 2)
    assert_equal(model.material_ids[1], 301)
    assert_equal(model.material_names[0], "Red")
    var red = assets.materials.get(model.materials[0])
    assert_equal(red.kind, PHONG)
    assert_equal(red.color.r, 255)
    assert_equal(red.specular.r, 128)
    assert_equal(red.emissive.g, 51)
    assert_almost_equal(red.emissive_intensity, 2)
    assert_almost_equal(red.shininess, 20)
    assert_almost_equal(red.opacity, 0.75)
    assert_true(red.transparent)
    assert_almost_equal(red.reflectivity, 0.5)
    assert_true(red.vertex_colors)
    var green = assets.materials.get(model.materials[1])
    assert_equal(green.kind, LAMBERT)
    assert_equal(green.color.g, 255)
    assert_almost_equal(green.opacity, 0.5)
    assert_true(green.transparent)
    assert_almost_equal(green.bump_scale, 1)
    assert_true(green.vertex_colors)
    # One mesh that wears both materials: the quad and the pentagon are a
    # group in the first, and the triangle a group in the second.
    assert_equal(model.mesh_count, 1)
    assert_equal(len(model.geometries), 1)
    ref mesh = scene.meshes[0]
    assert_equal(len(mesh.materials), 2)
    assert_equal(mesh.materials[0], model.materials[0])
    assert_equal(mesh.materials[1], model.materials[1])
    var first = mesh.geometry
    ref groups = assets.geometries.get(first).groups
    assert_equal(len(groups), 3)
    assert_equal(groups[0].count, 6)
    assert_equal(groups[1].start, 6)
    assert_equal(groups[1].count, 3)
    assert_equal(groups[1].material_index.value, 1)
    assert_equal(groups[2].start, 9)
    assert_equal(groups[2].material_index.value, 0)
    assert_equal(assets.geometries.get(first).vertex_count(), 18)
    # In polygon order: the quad, the triangle and the pentagon.
    assert_list(
        values(assets, first, POSITION),
        [
            0,
            0,
            1,
            1,
            0,
            1,
            1,
            1,
            1,
            0,
            0,
            1,
            1,
            1,
            1,
            0,
            1,
            1,
            1,
            0,
            1,
            2,
            0,
            1,
            2,
            2,
            1,
            2,
            0,
            1,
            3,
            0,
            1,
            3,
            1,
            1,
            2,
            0,
            1,
            3,
            1,
            1,
            2,
            2,
            1,
            2,
            0,
            1,
            2,
            2,
            1,
            1,
            1,
            1,
        ],
    )
    var middle = values(assets, first, COLOR)
    var colors = List[Float32]()
    for index in range(18, 27):
        colors.append(middle[index])
    assert_list(colors, [0, 1, 0, 0.21404, 0.21404, 0.21404, 0, 1, 1])
    var normals = values(assets, first, NORMAL)
    assert_list([normals[18], normals[19], normals[20]], [Float32(0), 0, 1])


def test_pivots() raises:
    """Pivots, offsets, the three inherit types and every rotation order,
    against three.js r180."""
    var scene = Scene()
    var assets = Assets()
    var model = load_fbx(parse_fbx_text(PIVOTS), "", scene, assets)
    scene.update()
    var parent = scene.get(model.models[0])
    assert_near(parent.position, 1.5, 0.25, 0)
    assert_turn(parent.quaternion, 0, 0.25882, 0, 0.96593)
    assert_near(parent.scale, 1, 2, 3)
    var kid = scene.get(model.model("Kid"))
    assert_near(kid.position, 0, 1, 0)
    assert_turn(kid.quaternion, 0.18004, -0.00515, 0.10924, 0.97302)
    assert_near(kid.scale, 1.97676, 0.50681, 0.35687)
    var other = scene.get(model.model("Other"))
    assert_turn(other.quaternion, 0.05653, 0.10252, 0.14726, 0.97637)
    assert_near(other.scale, 1.13435, 0.97919, 0.98509)
    assert_near(
        scene.world_position(model.model("Other")), 2.00964, 1.99913, 0.86179
    )
    var last = scene.get(model.model("Last"))
    assert_turn(last.quaternion, 0.02673, 0.1454, 0.15846, 0.96592)
    assert_near(last.scale, 0.95861, 1.09326, 1.13597)
    var spin = scene.get(model.model("Spin"))
    assert_turn(spin.quaternion, 0.03172, 0.092, 0.12614, 0.98723)
    assert_equal(fbx_euler_order(0), ZYX)
    assert_equal(fbx_euler_order(4), YXZ)
    assert_equal(fbx_euler_order(7), ZYX)


# --- binary files -------------------------------------------------------------


def test_binary() raises:
    """A binary file reads as its ASCII twin does, in both record widths,
    with raw and with zlib arrays."""
    var reference = Scene()
    var reference_assets = Assets()
    var ascii = load_text(QUAD, reference, reference_assets)
    var expected = values(reference_assets, ascii.geometries[0], POSITION)
    assert_equal(len(expected), 18)
    for version in [7400, 7500]:
        for compress in [False, True]:
            var scene = Scene()
            var assets = Assets()
            var bytes = binary(quad_tree(compress), version, compress)
            var model = load_fbx(parse_fbx(bytes), "", scene, assets)
            assert_equal(model.format, FBX_BINARY)
            assert_equal(model.version, version)
            assert_equal(model.model_names[0], "Quad")
            assert_equal(model.material_names[0], "Mat")
            assert_list(values(assets, model.geometries[0], POSITION), expected)
            assert_list(
                values(assets, model.geometries[0], NORMAL),
                values(reference_assets, ascii.geometries[0], NORMAL),
            )
            scene.update()
            assert_near(scene.world_position(model.models[0]), 1, 2, 3)
            var material = assets.materials.get(model.materials[0])
            assert_equal(material.kind, LAMBERT)
            assert_equal(material.color.b, 255)
    # The same file read from disk.
    Path("out/quad.fbx").write_bytes(binary(quad_tree(True), 7500))
    var scene = Scene()
    var assets = Assets()
    var model = read_fbx("out/quad.fbx", scene, assets)
    assert_equal(model.mesh_count, 1)


def test_binary_properties() raises:
    """Every property type a binary file has."""
    var tree = Tree()
    var props = p_int("Y", -2, 2)
    props.extend(p_int("C", 1, 1))
    props.extend(p_int("I", -3, 4))
    props.extend(p_int("L", -4, 8))
    props.extend(p_f32(1.5))
    props.extend(p_f64(-2.25))
    props.extend(p_str("Name\x00\x01Class"))
    props.extend(p_raw([1, 2, 3]))
    props.extend(
        p_array(
            "f",
            2,
            joined(
                [
                    le(Int(bitcast[DType.uint32](Float32(0.5))), 4),
                    le(Int(bitcast[DType.uint32](Float32(-1))), 4),
                ]
            ),
            False,
        )
    )
    props.extend(p_array("l", 1, le(-5, 8), True))
    props.extend(p_array("b", 3, [1, 0, 1], False))
    props.extend(p_array("c", 1, [1], True))
    props.extend(p_array("d", 0, List[UInt8](), False))
    props.extend(p_array("i", 0, List[UInt8](), False))
    _ = tree.add(-1, "Everything", props^, 14)
    _ = tree.add(-1, "Empty", List[UInt8](), 0)
    var document = parse_fbx(binary(tree, 7500, True))
    var node = document.child(document.root(), "Everything")
    assert_equal(document.property_count(node), 14)
    assert_equal(len(document.property(node, 12).numbers), 0)
    assert_equal(len(document.property(node, 13).integers), 0)
    assert_equal(document.integer(node, 0), -2)
    assert_equal(document.integer(node, 1), 1)
    assert_equal(document.integer(node, 2), -3)
    assert_equal(document.integer(node, 3), -4)
    assert_almost_equal(document.number(node, 4), 1.5)
    assert_almost_equal(document.number(node, 5), -2.25)
    assert_equal(document.string(node, 6), "Name")
    assert_equal(document.property(node, 7).kind, FBX_BYTES)
    assert_equal(len(document.property(node, 7).bytes), 3)
    var floats = document.property(node, 8)
    assert_equal(floats.kind, FBX_NUMBERS)
    assert_almost_equal(floats.numbers[1], -1)
    assert_equal(document.property(node, 9).integers[0], -5)
    assert_equal(document.property(node, 10).integers[2], 1)
    assert_equal(document.property(node, 11).integers[0], 1)
    assert_equal(object_name(document.string(node, 6), FBX_BINARY), "Name")
    # A node of no properties.
    assert_equal(
        document.property_count(document.child(document.root(), "Empty")), 0
    )


def test_binary_refused() raises:
    var head = text_bytes("Kaydara FBX Binary  \x00")
    head.append(0x1A)
    head.append(0)
    # Too old, and too short to hold a version.
    var old = head.copy()
    old.extend(le(6300, 4))
    old.extend(List[UInt8](length=200, fill=0))
    refused_bytes(old)
    refused_bytes(head)
    # A record that ends outside the file, or before its own name.
    var tree = Tree()
    tree.leaf(-1, "A", p_int("I", 1, 4))
    var good = binary(tree, 7400)
    var far = good.copy()
    far[27] = 0xFF
    far[28] = 0xFF
    refused_bytes(far)
    var early = good.copy()
    early[27] = 1
    refused_bytes(early)
    # A property that runs past the file.
    var cut = good.copy()
    cut[27 + 12] = 200
    refused_bytes(cut)
    # Unknown types and encodings.
    for props in [
        p_code("Z"),
        joined([p_code("d"), le(1, 4), le(2, 4), le(8, 4), le(0, 8)]),
        p_array("i", 2, le(1, 4), True),
    ]:
        var bad = Tree()
        _ = bad.add(-1, "A", props.copy(), 1)
        refused_bytes(binary(bad, 7400))
    # A child that runs past its parent's end.
    var nested = Tree()
    var outer = nested.add(-1, "Outer", List[UInt8](), 0)
    tree.leaf(outer, "Inner", p_int("I", 1, 4))
    nested.leaf(outer, "Inner", p_int("I", 1, 4))
    var bytes = binary(nested, 7400)
    bytes[27] = UInt8(Int(bytes[27]) - 2)
    refused_bytes(bytes)
    # Records nested past the limit.
    var deep = Tree()
    var parent = -1
    for _ in range(MAX_FBX_DEPTH + 1):
        parent = deep.add(parent, "D", List[UInt8](), 0)
    refused_bytes(binary(deep, 7400))


# --- the tree -----------------------------------------------------------------


def test_document() raises:
    var document = parse_fbx_text(
        '; FBX\r\nFBXVersion: 7400\r\nTop: 1, 2.5, "text", Y {\r\n'
        + "\tInner: -1e3,\n\t\t+4 ; a comment\n\tSub: {\n\t}\n}\n"
        + "Numbers: *3 {\n\ta: 1.5,2,\n3\n}\nWhole: *2 {\n\ta: 4,5\n}\n"
        + 'None: *0 {\n}\nContent: ,\n"abc"\nBlock: {\n\tShut: 1}\n'
        + "Hollow: *0 {\n\ta: \n}\nBeside: *1 {\n\ta: 1\n\tExtra: 2\n}\nLast: 7"
        " ; end"
    )
    assert_equal(document.format, FBX_ASCII)
    var root = document.root()
    assert_equal(document.name(root), "")
    assert_equal(len(document.children(root)), 10)
    var sub = document.child(document.child(root, "Top"), "Sub")
    assert_equal(len(document.numbers(sub)), 0)
    assert_equal(len(document.integers(sub)), 0)
    var block = document.child(root, "Block")
    assert_equal(document.integer(document.child(block, "Shut"), 0), 1)
    assert_equal(len(document.integers(document.child(root, "Hollow"))), 0)
    var beside = document.child(root, "Beside")
    assert_equal(document.integers(beside)[0], 1)
    assert_equal(len(document.children(beside)), 1)
    assert_equal(len(parse_fbx(text_bytes(QUAD)).children(0)), 3)
    var top = document.child(root, "Top")
    assert_equal(document.property_count(top), 4)
    assert_equal(document.integer(top, 0), 1)
    assert_almost_equal(document.number(top, 1), 2.5)
    assert_equal(document.string(top, 2), "text")
    assert_equal(document.string(top, 3), "Y")
    var inner = document.child(top, "Inner")
    assert_equal(document.integer(inner, 0), -1000)
    assert_equal(document.integer(inner, 1), 4)
    assert_equal(len(document.integers(inner)), 2)
    assert_equal(len(document.children_named(top, "Sub")), 1)
    assert_equal(document.child(top, "None"), NO_FBX_NODE)
    var numbers = document.child(root, "Numbers")
    assert_equal(document.property(numbers, 0).kind, FBX_NUMBERS)
    assert_equal(len(document.numbers(numbers)), 3)
    with assert_raises():
        _ = document.integers(numbers)
    assert_equal(len(document.children(numbers)), 0)
    var whole = document.child(root, "Whole")
    assert_equal(document.integers(whole)[1], 5)
    assert_almost_equal(document.numbers(whole)[0], 4)
    assert_equal(len(document.numbers(document.child(root, "None"))), 0)
    assert_equal(document.string(document.child(root, "Content"), 0), "abc")
    assert_equal(document.integer(document.child(root, "Last"), 0), 7)
    # Accessors of the wrong kind or out of range.
    with assert_raises():
        _ = document.integer(top, 1)
    with assert_raises():
        _ = document.number(top, 2)
    with assert_raises():
        _ = document.string(top, 0)
    with assert_raises():
        _ = document.property(top, 4)
    with assert_raises():
        _ = document.property(top, -1)
    with assert_raises():
        _ = document.numbers(top)
    with assert_raises():
        _ = document.name(-1)
    with assert_raises():
        _ = document.children(len(document.nodes))
    with assert_raises():
        _ = document.children_named(-1, "x")
    with assert_raises():
        _ = document.child(-1, "x")
    with assert_raises():
        _ = document.property_count(-1)
    with assert_raises():
        _ = document.numbers(-1)
    with assert_raises():
        _ = document.integers(-1)
    # A property whose kind is none of the six is refused where it is read.
    document.nodes[top].properties.append(FbxProperty(FbxPropertyKind(9)))
    assert_false(FbxPropertyKind(9).is_valid())
    with assert_raises():
        _ = document.property(top, 4)
    # Names.
    assert_equal(object_name("Model::Box", FBX_ASCII), "Box")
    assert_equal(object_name("Box", FBX_ASCII), "Box")
    assert_equal(object_name("::Box", FBX_ASCII), "::Box")
    assert_equal(object_name("A b::Box", FBX_ASCII), "A b::Box")
    assert_equal(object_name("Model::Box", FBX_BINARY), "Model::Box")
    with assert_raises():
        _ = object_name("Box", FbxFormat(5))
    assert_false(FbxFormat(5).is_valid())
    assert_equal(sanitize_node_name("a b\tc[d].e:f/g\nh\ri"), "a_b_cdefg_h_i")
    # Constructors of properties.
    assert_equal(integer_property(3).integer, 3)
    assert_almost_equal(number_property(0.5).number, 0.5)
    assert_equal(string_property("s").text, "s")


def test_text_refused() raises:
    var head = String("FBXVersion: 7400\n")
    for text in [
        "",
        "FBXVersion: x\n",
        "FBXVersion: 6100\n",
        head + "A: 1 {\n",
        head + "}\n",
        head + "A 1\n",
        head + "A: *x\n",
        head + "A: *2 {\n\ta: 1\n}\n",
        head + 'A: "open\n',
        "FBXVersion: ",
        "}FBXVersion: 7400\n",
        head + "A",
        head + "A\nB: 1\n",
        head + "A{\n",
        head + "A}\n",
        head + "A,\n",
    ]:
        with assert_raises():
            _ = parse_fbx_text(text)
    var deep = head
    for _ in range(MAX_FBX_DEPTH):
        deep += "A: {\n"
    with assert_raises():
        _ = parse_fbx_text(deep)
    # Text that is not the binary magic is read as text.
    with assert_raises():
        _ = parse_fbx(text_bytes("Kaydara FBX Binary"))


# --- layers -------------------------------------------------------------------


def test_layers() raises:
    assert_equal(fbx_mapping("ByPolygonVertex"), BY_POLYGON_VERTEX)
    assert_equal(fbx_mapping("ByPolygon"), BY_POLYGON)
    assert_equal(fbx_mapping("ByVertice"), BY_VERTEX)
    assert_equal(fbx_mapping("ByVertex"), BY_VERTEX)
    assert_equal(fbx_mapping("AllSame"), ALL_SAME)
    with assert_raises():
        _ = fbx_mapping("ByEdge")
    assert_equal(fbx_reference("Direct"), DIRECT)
    assert_equal(fbx_reference("IndexToDirect"), INDEX_TO_DIRECT)
    assert_equal(fbx_reference("Index"), INDEX_TO_DIRECT)
    with assert_raises():
        _ = fbx_reference("Other")
    var values: List[Float64] = [0, 1, 2, 3, 4, 5]
    assert_equal(
        FbxLayer(BY_POLYGON_VERTEX, DIRECT, values.copy(), [], 2).start(
            2, 1, 0
        ),
        4,
    )
    assert_equal(
        FbxLayer(BY_POLYGON, DIRECT, values.copy(), [], 2).start(2, 1, 0), 2
    )
    assert_equal(
        FbxLayer(BY_VERTEX, INDEX_TO_DIRECT, values.copy(), [2, 0], 3).start(
            2, 1, 1
        ),
        0,
    )
    assert_equal(
        FbxLayer(ALL_SAME, DIRECT, values.copy(), [], 3).start(5, 5, 5), 0
    )
    assert_equal(
        FbxLayer(ALL_SAME, INDEX_TO_DIRECT, values.copy(), [1, 0], 3).start(
            5, 5, 5
        ),
        0,
    )
    for layer in [
        FbxLayer(FbxMapping(7), DIRECT, values.copy(), [], 1),
        FbxLayer(BY_POLYGON, FbxReference(7), values.copy(), [], 1),
        FbxLayer(BY_POLYGON, INDEX_TO_DIRECT, values.copy(), [0], 1),
        FbxLayer(BY_POLYGON, INDEX_TO_DIRECT, values.copy(), [0, 9], 1),
        FbxLayer(BY_POLYGON, INDEX_TO_DIRECT, values.copy(), [0, -1], 1),
        FbxLayer(BY_POLYGON, DIRECT, values.copy(), [], 6),
        FbxLayer(ALL_SAME, INDEX_TO_DIRECT, values.copy(), [-1], 1),
    ]:
        with assert_raises():
            _ = layer.start(1, 1, 1)
    assert_false(FbxMapping(7).is_valid())
    assert_false(FbxReference(7).is_valid())


# --- materials and textures ---------------------------------------------------


def material_of(
    material: String, links: String = "", more: String = ""
) raises -> Material:
    """Return the material a quad model draws with."""
    var scene = Scene()
    var assets = Assets()
    _ = load_text(
        objects(
            '\tGeometry: 10, "Geometry::G", "Mesh" {\n\t\tVertices: *9 {\n'
            + "\t\t\ta: 0,0,0,1,0,0,0,1,0\n\t\t}\n"
            + "\t\tPolygonVertexIndex: *3 {\n\t\t\ta: 0,1,-3\n\t\t}\n\t}\n"
            + '\tModel: 20, "Model::M", "Mesh" {\n\t}\n'
            + '\tMaterial: 30, "Material::Mat", "" {\n'
            + material
            + "\t}\n"
            + more,
            '\tC: "OO",10,20\n\tC: "OO",30,20\n' + links,
        ),
        scene,
        assets,
    )
    return assets.materials.get(scene.meshes[0].material)


def test_materials() raises:
    # A shading model in the properties, and one three.js does not know.
    var from_properties = material_of(
        '\t\tProperties70:  {\n\t\t\tP: "ShadingModel", "KString", "", "",'
        ' "Lambert"\n'
        + '\t\t\tP: "DiffuseColor", "Vector", "", "A",1,0,0\n'
        + '\t\t\tP: "EmissiveColor", "ColorRGB", "", "A",0,0,1\n'
        + '\t\t\tP: "SpecularColor", "Color", "", "A",1,1,1\n'
        + '\t\t\tP: "TransparencyFactor", "Number", "", "A",0\n'
        + '\t\t\tP: "TransparentColor", "Color", "", "A",0.5,0.5,0.5\n\t\t}\n'
    )
    assert_equal(from_properties.kind, LAMBERT)
    assert_equal(from_properties.color.g, 255)
    assert_equal(from_properties.emissive.b, 255)
    assert_equal(from_properties.specular.r, 0)
    assert_almost_equal(from_properties.opacity, 0.5)
    var unknown = material_of(
        '\t\tShadingModel: "toon"\n\t\tProperties70:  {\n'
        + '\t\t\tP: "SpecularColor", "Color", "", "A",1,1,1\n'
        + '\t\t\tP: "EmissiveColor", "Vector", "", "A",1,1,1\n\t\t}\n'
    )
    assert_equal(unknown.kind, PHONG)
    assert_equal(unknown.specular.r, 255)
    assert_equal(unknown.emissive.r, 0)
    assert_almost_equal(unknown.shininess, 30)
    var plain = material_of(
        '\t\tShadingModel: "phong"\n\t\tProperties70:  {\n'
        + '\t\t\tP: "SpecularColor", "ColorRGB", "", "A",1,1,1\n\t\t}\n'
    )
    assert_equal(plain.specular.r, 17)
    assert_almost_equal(plain.opacity, 1)
    assert_false(plain.transparent)
    refused(
        objects(
            '\tMaterial: 30, "Material::Mat", "" {\n\t}\n',
            '\tC: "OO",30,0\n',
        )
    )
    refused(
        objects(
            '\tMaterial: 30, "Material::Mat", "" {\n\t\tShadingModel: "phong"\n'
            + '\t\tProperties70:  {\n\t\t\tP: "Diffuse", "Color", "",'
            ' "A",2,0,0\n'
            + "\t\t}\n\t}\n",
            '\tC: "OO",30,0\n',
        )
    )


def test_textures() raises:
    var textures = String(
        '\tTexture: 40, "Texture::Color", "" {\n\t\tProperties70:  {\n'
        + '\t\t\tP: "WrapModeU", "enum", "", "",1\n'
        + '\t\t\tP: "Scaling", "Vector", "", "A",2,3,1\n'
        + '\t\t\tP: "Translation", "Vector", "", "A",0.5,0.25,0\n\t\t}\n\t}\n'
        + '\tVideo: 50, "Video::File", "Clip" {\n'
        + '\t\tRelativeFilename: "..\\\\images\\\\checker.png"\n\t}\n'
        + '\tTexture: 41, "Texture::Glow", "" {\n\t}\n'
        + '\tVideo: 51, "Video::Embedded", "Clip" {\n'
        + '\t\tFilename: "C:\\\\x\\\\inside.png"\n\t\tContent: ,\n\t\t"'
        + CHECKER
        + '"\n\t}\n'
        + '\tTexture: 42, "Texture::Again", "" {\n\t}\n'
        + '\tVideo: 52, "Video::Again", "Clip" {\n'
        + '\t\tRelativeFilename: ""\n\t\tFilename: "C:\\\\x\\\\inside.png"\n'
        + "\t\tContent: \n\t}\n"
        + '\tLayeredTexture: 43, "LayeredTexture::L", "" {\n\t}\n'
        + '\tTexture: 44, "Texture::Lonely", "" {\n\t}\n'
        + '\tLayeredTexture: 45, "LayeredTexture::Empty", "" {\n\t}\n'
        + '\tTexture: 46, "Texture::NotVideo", "" {\n\t}\n'
    )
    var links = String(
        '\tC: "OO",50,40\n\tC: "OO",51,41\n\tC: "OO",52,42\n'
        + '\tC: "OO",40,43\n\tC: "OO",30,46\n'
        + '\tC: "OP",40,30, "DiffuseColor"\n'
        + '\tC: "OP",41,30, "EmissiveColor"\n'
        + '\tC: "OP",42,30, "NormalMap"\n'
        + '\tC: "OP",43,30, "Bump"\n'
        + '\tC: "OP",40,30, "TransparentColor"\n'
        + '\tC: "OP",44,30, "Maya|TEX_ao_map"\n'
    )
    var scene = Scene()
    var assets = Assets()
    var model = load_text(
        objects(
            '\tGeometry: 10, "Geometry::G", "Mesh" {\n\t\tVertices: *9 {\n'
            + "\t\t\ta: 0,0,0,1,0,0,0,1,0\n\t\t}\n"
            + "\t\tPolygonVertexIndex: *3 {\n\t\t\ta: 0,1,-3\n\t\t}\n\t}\n"
            + '\tModel: 20, "Model::M", "Mesh" {\n\t}\n'
            + '\tMaterial: 30, "Material::Mat", "" {\n\t\tShadingModel:'
            ' "phong"\n'
            + '\t\tProperties70:  {\n\t\t\tP: "BumpFactor", "double", "Number",'
            ' "",0.5\n'
            + "\t\t}\n\t}\n"
            + textures,
            '\tC: "OO",10,20\n\tC: "OO",30,20\n' + links,
        ),
        scene,
        assets,
    )
    var built = assets.materials.get(model.materials[0])
    ref color = assets.textures.get(built.map)
    assert_equal(color.color_space, SRGB)
    assert_equal(color.alpha, COVERAGE)
    assert_equal(color.wrap_s, CLAMP)
    assert_almost_equal(color.repeat.x, 2)
    assert_almost_equal(color.repeat.y, 3)
    assert_almost_equal(color.offset.x, 0.5)
    ref glow = assets.textures.get(built.emissive_map)
    assert_equal(glow.alpha, IGNORED)
    assert_equal(glow.wrap_s, REPEAT)
    ref normal = assets.textures.get(built.normal_map)
    assert_equal(normal.color_space, LINEAR)
    # The bump map is dropped beside the normal map, and its scale with it.
    assert_equal(built.bump_map, NO_TEXTURE)
    assert_almost_equal(built.bump_scale, 1)
    assert_true(built.alpha_map != NO_TEXTURE)
    assert_true(built.transparent)
    assert_equal(len(model.textures), 4)
    # A bump map alone keeps its scale; a texture with no image, or a
    # layered one with no layers, is left out; `Maya|TEX_color_map` is a
    # color map.
    var bumped = material_of(
        '\t\tShadingModel: "phong"\n\t\tProperties70:  {\n'
        + '\t\t\tP: "BumpFactor", "double", "Number", "",0.5\n\t\t}\n',
        '\tC: "OO",50,40\n\tC: "OO",40,43\n\tC: "OP",43,30, "Bump"\n'
        + '\tC: "OP",44,30, "Maya|TEX_color_map"\n'
        + '\tC: "OP",45,30, "Maya|TEX_normal_map"\n'
        + '\tC: "OO",30,46\n\tC: "OP",46,30, "TransparencyFactor"\n',
        textures,
    )
    assert_true(bumped.bump_map != NO_TEXTURE)
    assert_almost_equal(bumped.bump_scale, 0.5)
    assert_equal(bumped.map, NO_TEXTURE)
    assert_equal(bumped.normal_map, NO_TEXTURE)
    assert_equal(bumped.alpha_map, NO_TEXTURE)
    # What is refused: a connection to what is not a texture, a path that
    # is not relative, a video with no name, content of a number, and a
    # file that is not there.
    for link in [
        '\tC: "OP",20,30, "DiffuseColor"\n',
        '\tC: "OO",60,47\n\tC: "OP",47,30, "DiffuseColor"\n',
        '\tC: "OO",61,47\n\tC: "OP",47,30, "DiffuseColor"\n',
        '\tC: "OO",62,47\n\tC: "OP",47,30, "DiffuseColor"\n',
        '\tC: "OO",63,47\n\tC: "OP",47,30, "DiffuseColor"\n',
    ]:
        refused(
            objects(
                '\tModel: 20, "Model::M", "Null" {\n\t}\n'
                + '\tMaterial: 30, "Material::Mat", "" {\n\t\tShadingModel:'
                ' "phong"\n\t}\n'
                + '\tTexture: 47, "Texture::T", "" {\n\t}\n'
                + '\tVideo: 60, "Video::V", "Clip" {\n\t\tFilename:'
                ' "C:/abs.png"\n\t}\n'
                + '\tVideo: 61, "Video::V", "Clip" {\n\t}\n'
                + '\tVideo: 62, "Video::V", "Clip" {\n\t\tFilename:'
                ' "x.png"\n\t\tContent: 5\n\t}\n'
                + '\tVideo: 63, "Video::V", "Clip" {\n\t\tFilename:'
                ' "none.png"\n\t}\n',
                '\tC: "OO",30,20\n' + link,
            )
        )


def test_embedded_binary() raises:
    """A binary file's `Video` embeds its image as raw bytes."""
    var tree = Tree()
    var objects_node = tree.add(-1, "Objects", List[UInt8](), 0)
    var props = p_int("L", 30, 8)
    props.extend(p_str("Mat\x00\x01Material"))
    props.extend(p_str(""))
    var material = tree.add(objects_node, "Material", props^, 3)
    tree.leaf(material, "ShadingModel", p_str("phong"))
    props = p_int("L", 40, 8)
    props.extend(p_str("T\x00\x01Texture"))
    props.extend(p_str(""))
    _ = tree.add(objects_node, "Texture", props^, 3)
    props = p_int("L", 50, 8)
    props.extend(p_str("V\x00\x01Video"))
    props.extend(p_str("Clip"))
    var video = tree.add(objects_node, "Video", props^, 3)
    tree.leaf(video, "RelativeFilename", p_str("inside.png"))
    tree.leaf(video, "Content", p_raw(decode_base64(CHECKER)))
    var connections = tree.add(-1, "Connections", List[UInt8](), 0)
    props = p_str("OO")
    props.extend(p_int("L", 50, 8))
    props.extend(p_int("L", 40, 8))
    _ = tree.add(connections, "C", props^, 3)
    props = p_str("OP")
    props.extend(p_int("L", 40, 8))
    props.extend(p_int("L", 30, 8))
    props.extend(p_str("DiffuseColor"))
    _ = tree.add(connections, "C", props^, 4)
    var scene = Scene()
    var assets = Assets()
    var model = load_fbx(parse_fbx(binary(tree, 7400)), "", scene, assets)
    var built = assets.materials.get(model.materials[0])
    assert_equal(assets.textures.get(built.map).width, 2)
    assert_equal(len(model.models), 0)


# --- models, meshes, cameras and lights ---------------------------------------


def test_material_groups_follow_three_js() raises:
    """A layer mapped `AllSame` adds no group, and a geometry with a
    material layer and no polygon gets one empty group, as three.js's
    `genGeometry` adds them."""
    var same = String(
        '\tGeometry: 10, "Geometry::S", "Mesh" {\n\t\tVertices: *9 {\n'
        + "\t\t\ta: 0,0,0,1,0,0,0,1,0\n\t\t}\n"
        + "\t\tPolygonVertexIndex: *3 {\n\t\t\ta: 0,1,-3\n\t\t}\n"
        + "\t\tLayerElementMaterial: 0 {\n"
        + '\t\t\tMappingInformationType: "AllSame"\n'
        + "\t\t\tMaterials: *1 {\n\t\t\t\ta: 1\n\t\t\t}\n\t\t}\n\t}\n"
    )
    var bare = String(
        '\tGeometry: 11, "Geometry::E", "Mesh" {\n'
        + "\t\tLayerElementMaterial: 0 {\n"
        + '\t\t\tMappingInformationType: "ByPolygon"\n'
        + "\t\t\tMaterials: *0 {\n\t\t\t}\n\t\t}\n\t}\n"
    )
    var scene = Scene()
    var assets = Assets()
    var model = load_text(
        objects(
            same
            + bare
            + '\tModel: 20, "Model::A", "Mesh" {\n\t}\n'
            + '\tModel: 21, "Model::B", "Mesh" {\n\t}\n'
            + '\tModel: 22, "Model::C", "Mesh" {\n\t}\n'
            + '\tModel: 23, "Model::D", "Mesh" {\n\t}\n'
            + '\tMaterial: 30, "Material::One", "" {\n\t\tShadingModel:'
            ' "phong"\n\t}\n'
            + '\tMaterial: 31, "Material::Two", "" {\n\t\tShadingModel:'
            ' "phong"\n\t}\n',
            '\tC: "OO",10,20\n\tC: "OO",30,20\n\tC: "OO",31,20\n'
            + '\tC: "OO",10,21\n\tC: "OO",10,22\n\tC: "OO",11,23\n',
        ),
        scene,
        assets,
    )
    # D's geometry has no triangle, and gets no mesh.
    assert_equal(model.mesh_count, 3)
    # Two meshes with no material share one default.
    assert_equal(scene.meshes[2].material, scene.meshes[1].material)
    # A list of two and no group: three.js draws nothing of it.
    assert_equal(len(scene.meshes[0].materials), 2)
    assert_equal(len(assets.geometries.get(scene.meshes[0].geometry).groups), 0)
    ref empty = assets.geometries.get(model.geometries[1]).groups
    assert_equal(len(empty), 1)
    assert_equal(empty[0].count, 0)


def test_meshes() raises:
    # A concave hexagon, cut by ear clipping; a polygon of two corners,
    # which draws nothing; material indices past the connected ones and
    # below zero; and no material connected.
    var geometry = String(
        '\tGeometry: 10, "Geometry::L", "Mesh" {\n\t\tVertices: *18 {\n'
        + "\t\t\ta: 0,0,0,2,0,0,2,1,0,1,1,0,1,2,0,0,2,0\n\t\t}\n"
        + "\t\tPolygonVertexIndex: *11 {\n\t\t\ta:"
        " 0,1,2,3,4,-6,0,-2,0,1,-3\n\t\t}\n"
        + "\t\tLayerElementMaterial: 0 {\n"
        + '\t\t\tMappingInformationType: "ByPolygon"\n'
        + "\t\t\tMaterials: *3 {\n\t\t\t\ta: 3,0,-1\n\t\t\t}\n\t\t}\n"
        + "\t\tLayerElementColor: 0 {\n"
        + '\t\t\tMappingInformationType: "AllSame"\n'
        + '\t\t\tReferenceInformationType: "IndexToDirect"\n'
        + "\t\t\tColors: *4 {\n\t\t\t\ta: 1,1,1,1\n\t\t\t}\n"
        + "\t\t\tColorIndex: *1 {\n\t\t\t\ta: 0\n\t\t\t}\n\t\t}\n\t}\n"
    )
    var scene = Scene()
    var assets = Assets()
    var model = load_text(
        objects(
            geometry
            + '\tModel: 20, "Model::A", "Mesh" {\n\t}\n'
            + '\tModel: 21, "Model::B", "Mesh" {\n\t}\n'
            + '\tModel: 22, "Model::C", "Mesh" {\n\t}\n'
            + '\tMaterial: 30, "Material::Mat", "" {\n\t\tShadingModel:'
            ' "phong"\n\t}\n'
            + '\tMaterial: 31, "Material::Two", "" {\n\t\tShadingModel:'
            ' "lambert"\n\t}\n',
            '\tC: "OO",10,20\n\tC: "OO",10,21\n\tC: "OO",30,21\n'
            + '\tC: "OO",10,22\n\tC: "OO",31,22\n\tC: "OO",30,22\n',
        ),
        scene,
        assets,
    )
    # One geometry, a group a run of one material index, drawn by three
    # models.
    assert_equal(len(model.geometries), 1)
    assert_equal(model.mesh_count, 3)
    var hexagon = scene.meshes[0].geometry
    assert_list(
        values(assets, hexagon, POSITION),
        [
            0,
            0,
            0,
            2,
            0,
            0,
            2,
            1,
            0,
            0,
            0,
            0,
            2,
            1,
            0,
            1,
            1,
            0,
            0,
            0,
            0,
            1,
            1,
            0,
            1,
            2,
            0,
            0,
            0,
            0,
            1,
            2,
            0,
            0,
            2,
            0,
            0,
            0,
            0,
            2,
            0,
            0,
            2,
            1,
            0,
        ],
    )
    assert_false(assets.geometries.get(hexagon).has_attribute(String(NORMAL)))
    assert_false(assets.geometries.get(hexagon).has_attribute(String(UV)))
    ref groups = assets.geometries.get(hexagon).groups
    assert_equal(len(groups), 2)
    assert_equal(groups[0].count, 12)
    assert_equal(groups[0].material_index.value, 3)
    # The negative index is the first material.
    assert_equal(groups[1].start, 12)
    assert_equal(groups[1].material_index.value, 0)
    # Model A has no material: a gray phong with vertex colors on, over
    # every polygon.
    assert_false(scene.meshes[0].is_multi_material())
    var gray = assets.materials.get(scene.meshes[0].material)
    assert_equal(gray.color.r, 204)
    assert_true(gray.vertex_colors)
    # Model B has one material, and wears it over every polygon.
    assert_false(scene.meshes[1].is_multi_material())
    assert_equal(scene.meshes[1].material, model.materials[0])
    assert_true(assets.materials.get(model.materials[0]).vertex_colors)
    # Model C wears both, in the order connected; index 3 is past them,
    # so that group draws nothing, as in three.js.
    ref both = scene.meshes[2]
    assert_equal(len(both.materials), 2)
    assert_equal(both.materials[0], model.materials[1])
    assert_false(Bool(both.group_material(groups[0].material_index)))
    # No material mapping, and an untinted mesh without a material.
    var plain = Scene()
    var plain_assets = Assets()
    var untinted = load_text(
        objects(
            '\tGeometry: 10, "Geometry::T", "Mesh" {\n\t\tVertices: *9 {\n'
            + "\t\t\ta: 0,0,0,1,0,0,0,1,0\n\t\t}\n"
            + "\t\tPolygonVertexIndex: *3 {\n\t\t\ta: 0,1,-3\n\t\t}\n"
            + "\t\tLayerElementMaterial: 0 {\n"
            + '\t\t\tMappingInformationType: "NoMappingInformation"\n'
            + "\t\t\tMaterials: *1 {\n\t\t\t\ta: 5\n\t\t\t}\n\t\t}\n"
            + "\t\tLayerElementUV: 0 {\n\t\t}\n"
            + "\t\tLayerElementNormal: 0 {\n\t\t\tMappingInformationType:"
            ' "ByVertice"\n'
            + '\t\t\tReferenceInformationType: "IndexToDirect"\n'
            + "\t\t\tNormals: *3 {\n\t\t\t\ta: 0,0,1\n\t\t\t}\n"
            + "\t\t\tNormalsIndex: *3 {\n\t\t\t\ta: 0,0,0\n\t\t\t}\n"
            + "\t\t\tNormalIndex: *3 {\n\t\t\t\ta: 9,9,9\n\t\t\t}\n\t\t}\n"
            + "\t\tLayerElementUV: 1 {\n\t\t\tMappingInformationType:"
            ' "ByVertice"\n'
            + "\t\t\tUV: *6 {\n\t\t\t\ta: 0,0,1,0,0,1\n\t\t\t}\n\t\t}\n\t}\n"
            + '\tGeometry: 11, "Geometry::Curve", "NurbsCurve" {\n\t}\n'
            + '\tGeometry: 12, "Geometry::Empty", "Mesh" {\n'
            + "\t\tLayerElementColor: 0 {\n\t\t\tMappingInformationType:"
            ' "ByVertice"\n'
            + "\t\t\tColors: *0 {\n\t\t\t}\n\t\t}\n\t}\n"
            + '\tModel: 20, "Model::A", "Mesh" {\n\t\tProperties70:  {\n'
            + '\t\t\tP: "GeometricScaling", "Vector3D", "Vector", "",2,2,2\n'
            + '\t\t\tP: "GeometricRotation", "Vector3D", "Vector", "",0,0,90\n'
            + "\t\t}\n\t}\n"
            + '\tModel: 21, "Model::B", "Mesh" {\n\t}\n'
            + '\tNodeAttribute: 22, "NodeAttribute::X", "Other" {\n\t}\n',
            '\tC: "OO",10,22\n\tC: "OO",10,20\n\tC: "OO",11,20\n\tC:'
            ' "OO",12,21\n'
            + '\tC: "OO",999,20\n',
        ),
        plain,
        plain_assets,
    )
    # A geometry with no polygons gets no mesh.
    assert_equal(untinted.mesh_count, 1)
    var tri = plain.meshes[0].geometry
    assert_list(
        values(plain_assets, tri, POSITION), [0, 0, 0, 0, 2, 0, -2, 0, 0]
    )
    assert_list(values(plain_assets, tri, UV), [0, 0, 1, 0, 0, 1])
    assert_false(
        plain_assets.materials.get(plain.meshes[0].material).vertex_colors
    )
    # What is refused.
    var head = String('\tModel: 20, "Model::A", "Mesh" {\n\t}\n')
    for polygons in [
        "0,1,5",
        "0,1,2",
        "0,0,0,-1",
        "0,1,2,3,-3",
    ]:
        refused(
            objects(
                '\tGeometry: 10, "Geometry::T", "Mesh" {\n\t\tVertices: *12 {\n'
                + "\t\t\ta: 2,1,0,3,3,0,2,3,0,2,0,0\n\t\t}\n"
                + "\t\tPolygonVertexIndex: *"
                + String(len(polygons.split(",")))
                + " {\n\t\t\ta: "
                + polygons
                + "\n\t\t}\n\t}\n"
                + head,
                '\tC: "OO",10,20\n',
            )
        )
    refused(objects(head, ""))
    for layer in [
        (
            "\t\tLayerElementNormal: 0 {\n\t\t\tNormals: *3 {\n\t\t\t\ta:"
            " 0,0,1\n\t\t\t}\n\t\t}\n"
        ),
        "\t\tLayerElementNormal: 0 {\n\t\t\tMappingInformationType:"
        ' "ByPolygon"\n'
        + '\t\t\tReferenceInformationType: "IndexToDirect"\n'
        + "\t\t\tNormals: *3 {\n\t\t\t\ta: 0,0,1\n\t\t\t}\n\t\t}\n",
    ]:
        refused(
            objects(
                '\tGeometry: 10, "Geometry::T", "Mesh" {\n\t\tVertices: *9 {\n'
                + "\t\t\ta: 0,0,0,1,0,0,0,1,0\n\t\t}\n"
                + "\t\tPolygonVertexIndex: *3 {\n\t\t\ta: 0,1,-3\n\t\t}\n"
                + layer
                + "\t}\n"
                + head,
                '\tC: "OO",10,20\n',
            )
        )


def test_models() raises:
    var scene = Scene()
    var assets = Assets()
    var model = load_text(
        objects(
            '\tModel: 1, "Model::Cam", "Camera" {\n\t}\n'
            + '\tModel: 2, "Model::Flat", "Camera" {\n\t}\n'
            + '\tModel: 3, "Model::Lens", "Camera" {\n\t}\n'
            + '\tModel: 4, "Model::Bare", "Camera" {\n\t}\n'
            + '\tModel: 5, "Model::Odd", "Light" {\n\t}\n'
            + '\tModel: 6, "Model::Dark", "Light" {\n\t}\n'
            + '\tModel: 7, "Model::Hot", "Light" {\n\t}\n'
            + '\tModel: 8, "Model::Wide", "Light" {\n\t}\n'
            + '\tModel: 9, "Model::Sun", "Light" {\n\t}\n'
            + '\tNodeAttribute: 11, "NodeAttribute::A", "Camera" {\n\t}\n'
            + '\tNodeAttribute: 12, "NodeAttribute::B", "Camera"'
            " {\n\t\tProperties70:  {\n"
            + '\t\t\tP: "CameraProjectionType", "enum", "", "",1\n\t\t}\n\t}\n'
            + '\tNodeAttribute: 13, "NodeAttribute::C", "Camera"'
            " {\n\t\tProperties70:  {\n"
            + '\t\t\tP: "FocalLength", "Number", "", "A",35\n'
            + '\t\t\tP: "AspectWidth", "double", "Number", "",2\n\t\t}\n\t}\n'
            + '\tNodeAttribute: 15, "NodeAttribute::E", "Light"'
            " {\n\t\tProperties70:  {\n"
            + '\t\t\tP: "LightType", "enum", "", "",3\n\t\t}\n\t}\n'
            + '\tNodeAttribute: 16, "NodeAttribute::F", "Light"'
            " {\n\t\tProperties70:  {\n"
            + '\t\t\tP: "LightType", "enum", "", "",0\n'
            + '\t\t\tP: "CastShadows", "bool", "", "",1\n'
            + '\t\t\tP: "FarAttenuationEnd", "Number", "", "A",4\n\t\t}\n\t}\n'
            + '\tNodeAttribute: 17, "NodeAttribute::G", "Light"'
            " {\n\t\tProperties70:  {\n"
            + '\t\t\tP: "LightType", "enum", "", "",2\n\t\t}\n\t}\n'
            + '\tNodeAttribute: 18, "NodeAttribute::H", "Light"'
            " {\n\t\tProperties70:  {\n"
            + '\t\t\tP: "LightType", "enum", "", "",1\n'
            + '\t\t\tP: "CastShadows", "bool", "", "",1\n\t\t}\n\t}\n',
            '\tC: "OO",11,1\n\tC: "OO",12,2\n\tC: "OO",13,3\n\tC: "OO",1,99\n'
            + '\tC: "OO",15,5\n\tC: "OO",16,7\n\tC: "OO",17,8\n\tC:'
            ' "OO",18,9\n',
        ),
        scene,
        assets,
    )
    # Cameras: the defaults, none for an orthographic one, the focal
    # length's field of view, and none for a camera with no attribute.
    assert_equal(len(model.cameras), 2)
    var plain = model.cameras[0]
    assert_almost_equal(plain.fov.to(DEGREE), 45, atol=1e-4)
    assert_almost_equal(plain.aspect, 1)
    assert_almost_equal(plain.near.value, 1)
    assert_almost_equal(plain.far.value, 1000)
    assert_almost_equal(model.cameras[1].fov.to(DEGREE), 53.130102, atol=1e-3)
    # Lights: an unknown type is a point light at three.js's defaults; a
    # light with no attribute is none; a point light's shadow is dropped.
    assert_equal(model.light_count, 4)
    assert_equal(scene.lights[0].kind, POINT)
    assert_almost_equal(scene.lights[0].decay, 2)
    assert_equal(scene.lights[1].kind, POINT)
    assert_false(scene.lights[1].cast_shadow)
    assert_almost_equal(scene.lights[1].distance, 4)
    assert_equal(scene.lights[2].kind, SPOT)
    assert_almost_equal(scene.lights[2].penumbra, 0)
    assert_almost_equal(scene.lights[2].angle.to(DEGREE), 60, atol=1e-4)
    assert_equal(scene.lights[3].kind, DIRECTIONAL)
    assert_true(scene.lights[3].cast_shadow)
    # What is refused.
    refused(
        objects(
            (
                '\tModel: 1, "Model::A", "Null" {\n\t}\n\tModel: 2, "Model::B",'
                ' "Null" {\n\t}\n'
            ),
            '\tC: "OO",1,2\n\tC: "OO",2,1\n',
        )
    )
    refused(
        objects(
            '\tModel: 1, "Model::A", "Null" {\n\t\tProperties70:  {\n'
            + '\t\t\tP: "Lcl Scaling", "Lcl Scaling", "",'
            ' "A",0,1,1\n\t\t}\n\t}\n'
        )
    )
    var chain = String()
    var links = String()
    for index in range(MAX_MODEL_DEPTH + 2):
        chain += (
            "\tModel: " + String(index + 1) + ', "Model::M", "Null" {\n\t}\n'
        )
        if index > 0:
            links += (
                '\tC: "OO",' + String(index + 1) + "," + String(index) + "\n"
            )
    refused(objects(chain, links))
    refused("FBXVersion: 7400\n")
    var empty = FbxDocument(FbxFormat(4))
    var nowhere = Scene()
    var none = Assets()
    with assert_raises():
        _ = load_fbx(empty^, "", nowhere, none)


def test_global_settings() raises:
    # Black ambient light adds none; no connections at all is no parent.
    var scene = Scene()
    var assets = Assets()
    var model = load_text(
        "FBXVersion: 7400\nGlobalSettings:  {\n\tProperties70:  {\n"
        + '\t\tP: "AmbientColor", "ColorRGB", "Color", "",0,0,0\n\t}\n}\n'
        + 'Objects:  {\n\tModel: 1, "Model::A", "Null" {\n\t\tProperties70: '
        " {\n\t\t}\n\t}\n"
        + '\tModel: 2, "", "Null" {\n\t}\n\tModel: 3 {\n\t}\n\tNothing: '
        " {\n\t}\n}\n",
        scene,
        assets,
    )
    assert_equal(model.light_count, 0)
    assert_equal(len(model.models), 3)
    assert_equal(model.model_names[2], "")
    assert_almost_equal(model.unit.to(CENTIMETER), 1)
    var other = load_text(
        "FBXVersion: 7400\nGlobalSettings:  {\n}\nObjects:  {\n}\n",
        scene,
        assets,
    )
    assert_equal(len(other.models), 0)
    with assert_raises():
        _ = other.model("A")
    var tinted = load_text(
        "FBXVersion: 7400\nGlobalSettings:  {\n\tProperties70:  {\n"
        + '\t\tP: "AmbientColor", "ColorRGB", "Color", "",0,1,0\n\t}\n}\n'
        + "Objects:  {\n}\n",
        scene,
        assets,
    )
    assert_equal(tinted.light_count, 1)


def test_triangulate() raises:
    # A polygon wound the other way round is cut in its own winding, and a
    # vertical one is laid flat on its own plane.
    var scene = Scene()
    var assets = Assets()
    var model = load_text(
        objects(
            '\tGeometry: 10, "Geometry::T", "Mesh" {\n\t\tVertices: *12 {\n'
            + "\t\t\ta: 0,0,0,0,0,1,0,1,1,0,1,0\n\t\t}\n"
            + "\t\tPolygonVertexIndex: *8 {\n\t\t\ta:"
            " 0,1,2,-4,3,2,1,-1\n\t\t}\n\t}\n"
            + '\tModel: 20, "Model::A", "Mesh" {\n\t}\n',
            '\tC: "OO",10,20\n',
        ),
        scene,
        assets,
    )
    assert_list(
        values(assets, model.geometries[0], POSITION),
        [
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            1,
            1,
            0,
            0,
            0,
            0,
            1,
            1,
            0,
            1,
            0,
            0,
            1,
            0,
            0,
            1,
            1,
            0,
            0,
            1,
            0,
            1,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
        ],
    )


def test_ear_clipping() raises:
    """An arrow, whose first corner's triangle holds the notch and whose
    notch is not an ear."""
    var scene = Scene()
    var assets = Assets()
    var model = load_text(
        objects(
            '\tGeometry: 10, "Geometry::T", "Mesh" {\n\t\tVertices: *15 {\n'
            + "\t\t\ta: 0,0,0,4,0,0,4,4,0,2,1,0,0,4,0\n\t\t}\n"
            + "\t\tPolygonVertexIndex: *5 {\n\t\t\ta: 0,1,2,3,-5\n\t\t}\n\t}\n"
            + '\tModel: 20, "Model::A", "Mesh" {\n\t}\n',
            '\tC: "OO",10,20\n',
        ),
        scene,
        assets,
    )
    assert_list(
        values(assets, model.geometries[0], POSITION),
        [
            4,
            0,
            0,
            4,
            4,
            0,
            2,
            1,
            0,
            0,
            0,
            0,
            4,
            0,
            0,
            2,
            1,
            0,
            0,
            0,
            0,
            2,
            1,
            0,
            0,
            4,
            0,
        ],
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
