# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The node JSON of three.js: `NodeLoader`, `NodeMaterialLoader` and the
node half of `NodeObjectLoader`.

three.js writes a node material as a list of nodes. Each node has a
`uuid`, a `type` (the class that made it), the uuids of its inputs under
`inputNodes`, and the few fields its class serializes: an operator's `op`,
a math node's `method`, a constant's `value`. The material names the node
of each of its outputs under its own `inputNodes`. `NodeLoader` reads such
a list into a `NodeGraph`, one node of the graph for each node of the
list, and `NodeLoader.material` connects the graph's outputs as the
material's `inputNodes` say. `graph.compile()` then gives the program.

The node classes read are the ones this port has a node for:

- `VarNode` and `SubBuild` are their input. A `VaryingNode` is a `varying`
  of its input, or the input itself when that is an attribute.
- `ConstNode` and `UniformNode` hold a `float`, a `bool`, a vector, a
  `color` or a matrix. A uniform is named by its node's uuid, because
  three.js does not write a uniform's name.
- `AttributeNode` reads `uv`, `position`, `normal`, `color` or a custom
  attribute whose type the caller declares with `set_attribute`, because
  three.js does not write an attribute's type. `VertexColorNode` reads the
  vertex colors.
- `OperatorNode`, `MathNode`, `ConditionalNode`, `SplitNode`, `JoinNode`
  and `ConvertNode` are the arithmetic, the swizzles and the conversions.
- `FrontFacingNode`, `ScreenNode` and `PointUVNode` are `front_facing`,
  `screen_uv` and `point_coord`.
- `TextureNode` and `CubeTextureNode` read a texture uniform named by the
  node's uuid. `NodeLoader.textures` lists which texture of the file each
  one reads, so the caller can set it after `compile`.

Any other class is refused when an output reads it, with its name. Most of
three.js's built-in values, such as `positionWorld`, `normalWorld` and
`cameraPosition`, are TSL functions, and three.js writes a function as a
bare `Node` with no body. three.js's own `NodeLoader` cannot rebuild those
either.

**Where this port differs.** three.js's `normalNode` is the normal in
view space, and its `positionNode` is the local position. This port's
outputs are offsets, so the loader subtracts the normal and the position
they replace. A `colorNode` that is a `vec4` or a `float` sets the alpha as
well, as three.js's `vec4(colorNode)` does: the alpha multiplies the
opacity node, or the material's `opacity`. Texture gather inputs are
refused by name when reached. They are not ordinary RGBA samples.
"""

from loaders.json import (
    ARRAY,
    BOOLEAN,
    JsonDocument,
    NO_NODE,
    OBJECT,
    STRING,
    parse_json,
)
from materials.nodes import (
    COLOR_NODE,
    NODE_FLOAT,
    NODE_OUTPUT_COUNT,
    NODE_VEC4,
    NORMAL_NODE,
    OPACITY_NODE,
    POSITION_NODE,
    NodeGraph,
    NodeOutput,
    NodeRef,
    ValueType,
)
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from math.vector4 import Vector4
from std.collections import Dict


@fieldwise_init
struct NodeJsonType(Equatable, ImplicitlyCopyable, Writable):
    """Which of three.js's node classes an entry of node JSON is, as a type
    rather than a bare int: one of the classes this loader reads. See
    `node_json_type_names`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the classes the loader reads.

        Returns:
            Whether the value is zero to `NODE_JSON_TYPE_COUNT` less one.
        """
        return self.value >= 0 and self.value < NODE_JSON_TYPE_COUNT


comptime JSON_VAR_NODE = NodeJsonType(0)
comptime JSON_SUB_BUILD = NodeJsonType(1)
comptime JSON_VARYING_NODE = NodeJsonType(2)
comptime JSON_CONST_NODE = NodeJsonType(3)
comptime JSON_UNIFORM_NODE = NodeJsonType(4)
comptime JSON_ATTRIBUTE_NODE = NodeJsonType(5)
comptime JSON_VERTEX_COLOR_NODE = NodeJsonType(6)
comptime JSON_OPERATOR_NODE = NodeJsonType(7)
comptime JSON_MATH_NODE = NodeJsonType(8)
comptime JSON_CONDITIONAL_NODE = NodeJsonType(9)
comptime JSON_SPLIT_NODE = NodeJsonType(10)
comptime JSON_JOIN_NODE = NodeJsonType(11)
comptime JSON_CONVERT_NODE = NodeJsonType(12)
comptime JSON_FRONT_FACING_NODE = NodeJsonType(13)
comptime JSON_SCREEN_NODE = NodeJsonType(14)
comptime JSON_POINT_UV_NODE = NodeJsonType(15)
comptime JSON_TEXTURE_NODE = NodeJsonType(16)
comptime JSON_CUBE_TEXTURE_NODE = NodeJsonType(17)
comptime NODE_JSON_TYPE_COUNT = 18


def node_json_type_names() -> List[String]:
    """Return three.js's class name for each `NodeJsonType`, by its value.

    Returns:
        Eighteen names: `VarNode` for `JSON_VAR_NODE` at zero through
        `CubeTextureNode` for `JSON_CUBE_TEXTURE_NODE` at seventeen.
    """
    return [
        "VarNode",
        "SubBuild",
        "VaryingNode",
        "ConstNode",
        "UniformNode",
        "AttributeNode",
        "VertexColorNode",
        "OperatorNode",
        "MathNode",
        "ConditionalNode",
        "SplitNode",
        "JoinNode",
        "ConvertNode",
        "FrontFacingNode",
        "ScreenNode",
        "PointUVNode",
        "TextureNode",
        "CubeTextureNode",
    ]


def node_material_properties() -> List[String]:
    """Return three.js's `NodeMaterial` property for each `NodeOutput`, by
    its value.

    Returns:
        Twenty-five names: `colorNode` for `COLOR_NODE` at zero through
        `offsetNode` for `OFFSET_NODE` at twenty-four.
    """
    return [
        "colorNode",
        "opacityNode",
        "emissiveNode",
        "normalNode",
        "positionNode",
        "outputNode",
        "maskNode",
        "aoNode",
        "depthNode",
        "sizeNode",
        "backdropNode",
        "backdropAlphaNode",
        "fragmentNode",
        "roughnessNode",
        "metalnessNode",
        "receivedShadowNode",
        "castShadowNode",
        "thicknessColorNode",
        "thicknessDistortionNode",
        "thicknessAmbientNode",
        "thicknessAttenuationNode",
        "thicknessPowerNode",
        "thicknessScaleNode",
        "scatteringNode",
        "offsetNode",
    ]


def _position(names: List[String], name: String) -> Int:
    """Return where a name is in a list, or -1."""
    for index in range(len(names)):
        if names[index] == name:
            return index
    return -1


def node_json_type_of(name: String) -> NodeJsonType:
    """Return the `NodeJsonType` of a three.js class name.

    Args:
        name: The node's `type`, as three.js writes it.

    Returns:
        Its type, or `NodeJsonType(-1)`, which is not valid, for a class the
        loader does not read.
    """
    return NodeJsonType(_position(node_json_type_names(), name))


def node_output_of(property: String) -> NodeOutput:
    """Return the `NodeOutput` of a three.js `NodeMaterial` property.

    Args:
        property: The property, such as `colorNode`.

    Returns:
        Its output, or `NodeOutput(-1)`, which is not valid, for a property
        this port has no output for.
    """
    return NodeOutput(_position(node_material_properties(), property))


def plain_material_type(name: String) -> String:
    """Return the class a three.js node material's JSON is read as.

    Each node material extends a plain material and adds its nodes:
    `MeshStandardNodeMaterial` is a `MeshStandardMaterial`.
    `NodeMaterial` itself is unlit, as a `MeshBasicMaterial` is.

    Args:
        name: The material's `type`.

    Returns:
        The plain class, or `name` when it is not a node material's.
    """
    if name == "NodeMaterial":
        return "MeshBasicMaterial"
    # `MeshSSSNodeMaterial` extends `MeshPhysicalNodeMaterial`, and
    # `VolumeNodeMaterial` has no plain class: it is its own kind.
    if name == "MeshSSSNodeMaterial":
        return "MeshPhysicalMaterial"
    if name == "VolumeNodeMaterial":
        return name
    if name.endswith("NodeMaterial"):
        return String(name[byte = 0 : name.byte_length() - 12]) + "Material"
    return name


def type_width(name: String) -> Int:
    """Return how many floats a TSL type holds.

    Args:
        name: A type as three.js writes it: `float`, `int`, `uint`, `bool`,
            `vec2` to `vec4` and their `ivec`, `uvec` and `bvec` kin,
            `color`, `mat3` or `mat4`.

    Returns:
        One to four, nine or sixteen, or -1 for a type that is not read.
    """
    if name == "float" or name == "int" or name == "uint" or name == "bool":
        return 1
    if name == "color":
        return 3
    if name == "mat3":
        return 9
    if name == "mat4":
        return 16
    var size = name.byte_length()
    if size < 4:
        return -1
    var stem = String(name[byte = 0 : size - 1])
    var digit = Int(name.as_bytes()[size - 1]) - ord("0")
    if (
        stem == "vec" or stem == "ivec" or stem == "uvec" or stem == "bvec"
    ) and (digit >= 2 and digit <= 4):
        return digit
    return -1


def _component(name: String) -> String:
    """Return a TSL type's component: `int`, `uint`, `bool` or `float`."""
    if name == "int" or name.startswith("ivec"):
        return "int"
    if name == "uint" or name.startswith("uvec"):
        return "uint"
    if name == "bool" or name.startswith("bvec"):
        return "bool"
    return "float"


def _xyzw(components: String) -> String:
    """Return a swizzle in `xyzw`, from `xyzw`, `rgba` or `stpq`."""
    var out = String()
    for byte in components.as_bytes():
        if byte == UInt8(ord("s")):
            out += "x"
        elif byte == UInt8(ord("t")):
            out += "y"
        elif byte == UInt8(ord("p")):
            out += "z"
        elif byte == UInt8(ord("q")):
            out += "w"
        else:
            out += chr(Int(byte))
    return out


@fieldwise_init
struct NodeTextureRead(Copyable, Movable):
    """A texture node the loader read: the texture uniform it made, the
    uuid of the file's texture it reads, and the `mat3` uniform that holds
    that texture's transform, or an empty string for none."""

    var uniform: String
    var texture: String
    var matrix: String
    # Whether the node is a `CubeTextureNode`, which reads a cube.
    var cube: Bool


struct NodeMaterialGraph(Movable):
    """A node material read from three.js's JSON: its graph, with each
    output the material sets, and the texture nodes the graph reads."""

    var graph: NodeGraph
    var textures: List[NodeTextureRead]

    def __init__(
        out self, var graph: NodeGraph, var textures: List[NodeTextureRead]
    ):
        """Hold a graph and its texture reads.

        Args:
            graph: The graph.
            textures: Its texture reads.
        """
        self.graph = graph^
        self.textures = textures^


def _text(document: JsonDocument, item: Int, key: String) raises -> String:
    """Return a node's string field, refusing one that is not a string."""
    var at = document.get(item, key)
    if at == NO_NODE or document.kind(at) != STRING:
        raise Error("Node JSON: a node's " + key + " must be a string")
    return document.string(at)


def _flag(
    document: JsonDocument, item: Int, key: String, default: Bool
) raises -> Bool:
    """Return a node's boolean field, or `default` where it is absent."""
    var at = document.get(item, key)
    if at == NO_NODE:
        return default
    return document.boolean(at)


struct NodeLoader(Movable):
    """Reads node JSON into a `NodeGraph`: three.js's `NodeLoader`.

    `parse_nodes` indexes a list of nodes by uuid, as three.js's
    `parseNodes` does. `node` then builds the graph node of a uuid, with
    the nodes it reads, each once. `parse` reads what three.js's
    `Node.toJSON()` writes, and `material` reads a node material's
    outputs. One loader builds one graph.
    """

    var graph: NodeGraph
    var textures: List[NodeTextureRead]
    # Each node of the lists read, by uuid, and the graph node each built
    # node became.
    var _items: Dict[String, Int]
    var _built: Dict[String, Int]
    # The uuids being built, outermost first, to refuse a cycle.
    var _open: List[String]
    # The graph nodes that are attributes, which a varying passes on.
    var _leaves: List[Int]
    # The custom attributes the caller declared, and their types.
    var _attribute_names: List[String]
    var _attribute_types: List[ValueType]

    def __init__(out self):
        """Start with no nodes, an empty graph and no attributes."""
        self.graph = NodeGraph()
        self.textures = List[NodeTextureRead]()
        self._items = Dict[String, Int]()
        self._built = Dict[String, Int]()
        self._open = List[String]()
        self._leaves = List[Int]()
        self._attribute_names = List[String]()
        self._attribute_types = List[ValueType]()

    def set_attribute(mut self, name: String, type: ValueType) raises:
        """Declare the type of a custom attribute an `AttributeNode` reads.
        three.js takes it from the geometry; the JSON does not hold it.

        Args:
            name: The attribute's name.
            type: A `float` or a vector.

        Raises:
            Error: If the type is not a `float` or a vector.
        """
        if not type.is_vector():
            raise Error(
                "Node JSON: an attribute is a float or a vector, not a "
                + type.name()
            )
        var at = _position(self._attribute_names, name)
        if at >= 0:
            self._attribute_types[at] = type
            return
        self._attribute_names.append(name)
        self._attribute_types.append(type)

    def parse_nodes(mut self, document: JsonDocument, list: Int) raises:
        """Index a list of nodes by uuid, three.js's `parseNodes`. Nothing
        is built until an output reads it.

        Args:
            document: The parsed file.
            list: The array of nodes.

        Raises:
            Error: If the list is not an array, a node is not an object, a
                `uuid` or a `type` is not a string, or two nodes have one
                uuid.
        """
        if document.kind(list) != ARRAY:
            raise Error("Node JSON: a list of nodes must be an array")
        for index in range(document.length(list)):
            _ = self._index(document, document.at(list, index))

    def _index(mut self, document: JsonDocument, item: Int) raises -> String:
        """Index one node, and return its uuid."""
        if document.kind(item) != OBJECT:
            raise Error("Node JSON: a node must be an object")
        var uuid = _text(document, item, "uuid")
        _ = _text(document, item, "type")
        if uuid in self._items:
            raise Error("Node JSON: two nodes have the uuid " + uuid)
        self._items[uuid] = item
        return uuid

    def parse(mut self, document: JsonDocument, item: Int) raises -> NodeRef:
        """Read one node and the nodes it lists, three.js's `parse` of what
        `Node.toJSON()` writes.

        Args:
            document: The parsed file.
            item: The node's object. Its `nodes`, where present, lists the
                nodes it reads.

        Returns:
            Its node in `graph`.

        Raises:
            Error: If a node is refused; see `node`.
        """
        if document.kind(item) != OBJECT:
            raise Error("Node JSON: a node must be an object")
        var list = document.get(item, "nodes")
        if list != NO_NODE:
            self.parse_nodes(document, list)
        return self.node(document, self._index(document, item))

    def node(mut self, document: JsonDocument, uuid: String) raises -> NodeRef:
        """Return the graph node of a uuid, building it and what it reads
        the first time it is asked for.

        Args:
            document: The parsed file.
            uuid: A uuid `parse_nodes` indexed.

        Returns:
            Its node in `graph`.

        Raises:
            Error: If no node has the uuid, the nodes read each other in a
                cycle, a node's class or a field is not read, or the graph
                refuses a type.
        """
        if uuid in self._built:
            return NodeRef(self._built[uuid])
        if uuid not in self._items:
            raise Error("Node JSON: no node has the uuid " + uuid)
        if _position(self._open, uuid) >= 0:
            raise Error("Node JSON: a node reads itself: " + uuid)
        self._open.append(uuid)
        var built = self._build(document, self._items[uuid], uuid)
        _ = self._open.pop()
        self._built[uuid] = built.value
        return built

    def _input_at(
        self, document: JsonDocument, item: Int, name: String
    ) raises -> Int:
        """Return what a node's `inputNodes` holds under a name, or
        `NO_NODE`."""
        var inputs = document.get(item, "inputNodes")
        if inputs == NO_NODE:
            return NO_NODE
        return document.get(inputs, name)

    def _has_input(
        self, document: JsonDocument, item: Int, name: String
    ) raises -> Bool:
        """Return True if a node names an input."""
        return self._input_at(document, item, name) != NO_NODE

    def _input(
        mut self, document: JsonDocument, item: Int, name: String
    ) raises -> NodeRef:
        """Return a node's input, built."""
        var at = self._input_at(document, item, name)
        if at == NO_NODE:
            raise Error(
                "Node JSON: a "
                + _text(document, item, "type")
                + " has no "
                + name
            )
        return self.node(document, document.string(at))

    def _leaf(mut self, node: NodeRef) -> NodeRef:
        """Note an attribute node, and return it."""
        self._leaves.append(node.value)
        return node

    def _build(
        mut self, document: JsonDocument, item: Int, uuid: String
    ) raises -> NodeRef:
        """Build one node, by its class."""
        var name = _text(document, item, "type")
        var type = node_json_type_of(name)
        if not type.is_valid():
            if name == "Node":
                raise Error(
                    "Node JSON: node "
                    + uuid
                    + " is a TSL function, which three.js writes without"
                    " its body"
                )
            raise Error("Node JSON: a node type that is not read: " + name)
        if type == JSON_VAR_NODE or type == JSON_SUB_BUILD:
            return self._input(document, item, "node")
        if type == JSON_VARYING_NODE:
            var value = self._input(document, item, "node")
            if _position_of_int(self._leaves, value.value) >= 0:
                return value
            return self.graph.varying(value)
        if type == JSON_CONST_NODE:
            return self._value(document, item, "")
        if type == JSON_UNIFORM_NODE:
            return self._value(document, item, uuid)
        if type == JSON_ATTRIBUTE_NODE:
            return self._attribute(document, item)
        if type == JSON_VERTEX_COLOR_NODE:
            if document.integer(document.get(item, "index")) != 0:
                raise Error("Node JSON: only the first vertex colors are read")
            return self._leaf(self.graph.vertex_color())
        if type == JSON_OPERATOR_NODE:
            return self._operator(document, item)
        if type == JSON_MATH_NODE:
            return self._math(document, item)
        if type == JSON_CONDITIONAL_NODE:
            var condition = self._input(document, item, "condNode")
            var yes = self._input(document, item, "ifNode")
            var no = self._input(document, item, "elseNode")
            return self.graph.select(condition, yes, no)
        if type == JSON_SPLIT_NODE:
            var value = self._input(document, item, "node")
            return self.graph.swizzle(
                value, _xyzw(_text(document, item, "components"))
            )
        if type == JSON_JOIN_NODE:
            return self._join(document, item)
        if type == JSON_CONVERT_NODE:
            var value = self._input(document, item, "node")
            return self.convert(value, _text(document, item, "convertTo"))
        if type == JSON_FRONT_FACING_NODE:
            return self.graph.front_facing()
        if type == JSON_SCREEN_NODE:
            return self.graph.screen_uv()
        if type == JSON_POINT_UV_NODE:
            return self.graph.point_coord()
        return self._texture(
            document, item, uuid, type == JSON_CUBE_TEXTURE_NODE
        )

    def _value(
        mut self, document: JsonDocument, item: Int, uniform: String
    ) raises -> NodeRef:
        """Build a constant, or a uniform named `uniform`."""
        var value_type = _text(document, item, "valueType")
        var width = _value_width(value_type)
        if width < 0:
            raise Error(
                "Node JSON: a value of type " + value_type + " is not read"
            )
        var value = document.get(item, "value")
        var numbers = List[Float32]()
        if document.kind(value) == ARRAY:
            for index in range(document.length(value)):
                numbers.append(
                    Float32(document.number(document.at(value, index)))
                )
        elif document.kind(value) == BOOLEAN:
            numbers.append(
                Float32(1) if document.boolean(value) else Float32(0)
            )
        else:
            numbers.append(Float32(document.number(value)))
        if len(numbers) != width:
            raise Error(
                "Node JSON: a "
                + value_type
                + " holds "
                + String(width)
                + " numbers, not "
                + String(len(numbers))
            )
        if uniform != "":
            return self._uniform(uniform, numbers)
        if width == 1:
            return self.graph.float(numbers[0])
        if width == 2:
            return self.graph.vec2(numbers[0], numbers[1])
        if width == 3:
            return self.graph.vec3(numbers[0], numbers[1], numbers[2])
        if width == 4:
            return self.graph.vec4(
                numbers[0], numbers[1], numbers[2], numbers[3]
            )
        # A matrix, column by column.
        if width == 9:
            var columns = List[NodeRef]()
            for column in range(3):  # pragma: no branch
                var at = column * 3
                columns.append(
                    self.graph.vec3(
                        numbers[at], numbers[at + 1], numbers[at + 2]
                    )
                )
            return self.graph.mat3(columns[0], columns[1], columns[2])
        var columns = List[NodeRef]()
        for column in range(4):  # pragma: no branch
            var at = column * 4
            columns.append(
                self.graph.vec4(
                    numbers[at],
                    numbers[at + 1],
                    numbers[at + 2],
                    numbers[at + 3],
                )
            )
        return self.graph.mat4(columns[0], columns[1], columns[2], columns[3])

    def _uniform(
        mut self, name: String, numbers: List[Float32]
    ) raises -> NodeRef:
        """Build a uniform of as many floats as `numbers` holds."""
        var width = len(numbers)
        if width == 1:
            return self.graph.uniform(name, numbers[0])
        if width == 2:
            return self.graph.uniform(name, Vector2(numbers[0], numbers[1]))
        if width == 3:
            return self.graph.uniform(
                name, Vector3(numbers[0], numbers[1], numbers[2])
            )
        if width == 4:
            return self.graph.uniform(
                name, Vector4(numbers[0], numbers[1], numbers[2], numbers[3])
            )
        if width == 9:
            var matrix = Matrix3()
            for index in range(9):  # pragma: no branch
                matrix.elements[index] = numbers[index]
            return self.graph.uniform(name, matrix)
        var matrix = Matrix4()
        for index in range(16):  # pragma: no branch
            matrix.elements[index] = numbers[index]
        return self.graph.uniform(name, matrix)

    def _attribute(
        mut self, document: JsonDocument, item: Int
    ) raises -> NodeRef:
        """Build an `AttributeNode`."""
        var name = _text(document, item, "_attributeName")
        if name == "uv":
            return self._leaf(self.graph.uv())
        if name == "position":
            return self._leaf(self.graph.position_local())
        if name == "normal":
            return self._leaf(self.graph.normal_local())
        if name == "color":
            return self._leaf(self.graph.vertex_color())
        var at = _position(self._attribute_names, name)
        if at < 0:
            raise Error(
                "Node JSON: the attribute "
                + name
                + " has no type; declare it with set_attribute"
            )
        return self._leaf(self.graph.attribute(name, self._attribute_types[at]))

    def _operator(
        mut self, document: JsonDocument, item: Int
    ) raises -> NodeRef:
        """Build an `OperatorNode`, by its `op`."""
        var op = _text(document, item, "op")
        var a = self._input(document, item, "aNode")
        if op == "!":
            return self.graph.logical_not(a)
        if op == "~":
            return self.graph.bit_not(a)
        var b = self._input(document, item, "bNode")
        if op == "+":
            return self.graph.add(a, b)
        if op == "-":
            return self.graph.sub(a, b)
        if op == "*":
            return self.graph.mul(a, b)
        if op == "/":
            return self.graph.div(a, b)
        if op == "%":
            return self.graph.mod(a, b)
        if op == "==":
            return self.graph.equal(a, b)
        if op == "!=":
            return self.graph.not_equal(a, b)
        if op == "<":
            return self.graph.less_than(a, b)
        if op == ">":
            return self.graph.greater_than(a, b)
        if op == "<=":
            return self.graph.less_than_equal(a, b)
        if op == ">=":
            return self.graph.greater_than_equal(a, b)
        if op == "&&":
            return self.graph.logical_and(a, b)
        if op == "||":
            return self.graph.logical_or(a, b)
        if op == "^^":
            return self.graph.logical_xor(a, b)
        if op == "&":
            return self.graph.bit_and(a, b)
        if op == "|":
            return self.graph.bit_or(a, b)
        if op == "^":
            return self.graph.bit_xor(a, b)
        if op == "<<":
            return self.graph.shift_left(a, b)
        if op == ">>":
            return self.graph.shift_right(a, b)
        raise Error("Node JSON: the operator " + op + " is not read")

    def _math(mut self, document: JsonDocument, item: Int) raises -> NodeRef:
        """Build a `MathNode`, by its `method`."""
        var method = _text(document, item, "method")
        var a = self._input(document, item, "aNode")
        if _position(_unary_methods(), method) >= 0:
            return self._unary(method, a)
        if method == "atan" and not self._has_input(document, item, "bNode"):
            return self.graph.atan(a)
        var binary = _position(_binary_methods(), method) >= 0
        if not binary and _position(_ternary_methods(), method) < 0:
            raise Error("Node JSON: the math method " + method + " is not read")
        var b = self._input(document, item, "bNode")
        if binary:
            return self._binary(method, a, b)
        var c = self._input(document, item, "cNode")
        if method == "mix":
            return self.graph.mix(a, b, c)
        if method == "clamp":
            return self.graph.clamp(a, b, c)
        if method == "refract":
            return self.graph.refract(a, b, c)
        if method == "smoothstep":
            return self.graph.smoothstep(a, b, c)
        return self.graph.faceforward(a, b, c)

    def _unary(mut self, method: String, a: NodeRef) raises -> NodeRef:
        """Build a math method of one value."""
        if method == "radians":
            return self.graph.radians(a)
        if method == "degrees":
            return self.graph.degrees(a)
        if method == "exp":
            return self.graph.exp(a)
        if method == "exp2":
            return self.graph.exp2(a)
        if method == "log":
            return self.graph.log(a)
        if method == "log2":
            return self.graph.log2(a)
        if method == "sqrt":
            return self.graph.sqrt(a)
        if method == "inversesqrt":
            return self.graph.inverse_sqrt(a)
        if method == "floor":
            return self.graph.floor(a)
        if method == "ceil":
            return self.graph.ceil(a)
        if method == "normalize":
            return self.graph.normalize(a)
        if method == "fract":
            return self.graph.fract(a)
        if method == "sin":
            return self.graph.sin(a)
        if method == "cos":
            return self.graph.cos(a)
        if method == "tan":
            return self.graph.tan(a)
        if method == "asin":
            return self.graph.asin(a)
        if method == "acos":
            return self.graph.acos(a)
        if method == "abs":
            return self.graph.abs(a)
        if method == "sign":
            return self.graph.sign(a)
        if method == "length":
            return self.graph.length(a)
        if method == "negate":
            return self.graph.negate(a)
        if method == "oneMinus":
            return self.graph.one_minus(a)
        if method == "dFdx":
            return self.graph.dfdx(a)
        if method == "dFdy":
            return self.graph.dfdy(a)
        if method == "round":
            return self.graph.round(a)
        if method == "reciprocal":
            return self.graph.reciprocal(a)
        if method == "trunc":
            return self.graph.trunc(a)
        if method == "fwidth":
            return self.graph.fwidth(a)
        if method == "transpose":
            return self.graph.transpose(a)
        if method == "determinant":
            return self.graph.determinant(a)
        if method == "inverse":
            return self.graph.inverse(a)
        return self._hyperbolic(method, a)

    def _hyperbolic(mut self, method: String, a: NodeRef) raises -> NodeRef:
        """Build a hyperbolic function from `exp` and `log`, which is what
        each is."""
        var half = self.graph.float(0.5)
        var one = self.graph.float(1)
        if method == "sinh" or method == "cosh":
            var up = self.graph.exp(a)
            var down = self.graph.exp(self.graph.negate(a))
            if method == "sinh":
                return self.graph.mul(self.graph.sub(up, down), half)
            return self.graph.mul(self.graph.add(up, down), half)
        if method == "tanh":
            # 1 - 2 / (e^2x + 1), which holds at either end of the range.
            var twice = self.graph.exp(self.graph.mul(a, self.graph.float(2)))
            return self.graph.sub(
                one,
                self.graph.div(self.graph.float(2), self.graph.add(twice, one)),
            )
        if method == "asinh" or method == "acosh":
            var square = self.graph.mul(a, a)
            var root = self.graph.sqrt(
                self.graph.add(square, one) if method
                == "asinh" else self.graph.sub(square, one)
            )
            return self.graph.log(self.graph.add(a, root))
        # atanh: half the log of (1 + x) / (1 - x).
        return self.graph.mul(
            self.graph.log(
                self.graph.div(self.graph.add(one, a), self.graph.sub(one, a))
            ),
            half,
        )

    def _binary(
        mut self, method: String, a: NodeRef, b: NodeRef
    ) raises -> NodeRef:
        """Build a math method of two values."""
        if method == "atan":
            return self.graph.atan2(a, b)
        if method == "min":
            return self.graph.min(a, b)
        if method == "max":
            return self.graph.max(a, b)
        if method == "step":
            return self.graph.step(a, b)
        if method == "reflect":
            return self.graph.reflect(a, b)
        if method == "distance":
            return self.graph.distance(a, b)
        if method == "difference":
            return self.graph.abs(self.graph.sub(a, b))
        if method == "dot":
            return self.graph.dot(a, b)
        if method == "cross":
            return self.graph.cross(a, b)
        if method == "pow":
            return self.graph.pow(a, b)
        if method == "equals":
            return self.graph.equal(a, b)
        # transformDirection: the matrix times the direction, made unit
        # length, with the matrix on either side.
        var matrix = a
        var direction = b
        if self.graph.type_of(b).value > 4:
            matrix = b
            direction = a
        var turned = self.graph.mul(
            matrix, self.graph.join([direction, self.graph.float(0)])
        )
        return self.graph.normalize(self.graph.swizzle(turned, "xyz"))

    def _join(mut self, document: JsonDocument, item: Int) raises -> NodeRef:
        """Build a `JoinNode`: a vector, or a matrix of its columns."""
        var list = self._input_at(document, item, "nodes")
        if list == NO_NODE or document.kind(list) != ARRAY:
            raise Error("Node JSON: a JoinNode needs a list of nodes")
        var parts = List[NodeRef]()
        var width = 0
        for index in range(document.length(list)):
            var part = self.node(
                document, document.string(document.at(list, index))
            )
            width += self.graph.type_of(part).value
            parts.append(part)
        if width == 9 and len(parts) == 3:
            return self.graph.mat3(parts[0], parts[1], parts[2])
        if width == 16 and len(parts) == 4:
            return self.graph.mat4(parts[0], parts[1], parts[2], parts[3])
        return self.graph.join(parts)

    def convert(mut self, value: NodeRef, to: String) raises -> NodeRef:
        """Return a value converted to a type, as three.js's `ConvertNode`
        and its builder's `format` convert it.

        A narrower vector keeps its first components. A `vec2` gains a zero
        and a `vec3` gains a one, so a `vec2` made a `vec4` ends in zero and
        one. A `float` is repeated. An `int` truncates, a `uint` also wraps,
        and a `bool` is whether the value is not zero.

        Args:
            value: A node of `graph`.
            to: The type, or several split by `|`: the one as wide as the
                value, or else the first.

        Returns:
            The node.

        Raises:
            Error: If the type is not read, or either type is a matrix or a
                texture and the two differ.
        """
        var from_width = self.graph.type_of(value).value
        var chosen = String()
        for part in to.split("|"):  # pragma: no branch
            var name = String(part)
            if chosen == "" or type_width(name) == from_width:
                chosen = name
        var width = type_width(chosen)
        if width < 0:
            raise Error("Node JSON: a conversion to " + chosen + " is not read")
        var shaped = self._reshape(value, from_width, width)
        var component = _component(chosen)
        if component == "int":
            return self.graph.integer(shaped)
        if component == "uint":
            return self.graph.unsigned(shaped)
        if component == "bool":
            return self.graph.not_equal(shaped, self.graph.float(0))
        return shaped

    def _reshape(
        mut self, value: NodeRef, from_width: Int, to_width: Int
    ) raises -> NodeRef:
        """Return a value made as wide as `to_width`."""
        if from_width == to_width:
            return value
        if from_width > 4 or to_width > 4:
            raise Error(
                "Node JSON: a matrix or a texture is not converted to another"
                " type"
            )
        if from_width > to_width:
            return self.graph.swizzle(value, String("xyz"[byte=0:to_width]))
        if to_width == 4 and from_width > 1:
            return self.graph.join(
                [self._reshape(value, from_width, 3), self.graph.float(1)]
            )
        if from_width == 2:
            return self.graph.join([value, self.graph.float(0)])
        var parts = List[NodeRef]()
        for _ in range(to_width):  # pragma: no branch
            parts.append(value)
        return self.graph.join(parts)

    def _texture(
        mut self, document: JsonDocument, item: Int, uuid: String, cube: Bool
    ) raises -> NodeRef:
        """Build a `TextureNode` or a `CubeTextureNode`, reading a texture
        uniform named by the node's uuid."""
        var texture = _text(document, item, "value")
        # The list is never empty, so the loop always runs.
        for name in [  # pragma: no branch
            "biasNode",
            "compareNode",
            "depthNode",
            "gradNode",
            "gatherNode",
            "offsetNode",
        ]:
            if self._has_input(document, item, name):
                raise Error(
                    "Node JSON: a texture node's " + name + " is not read"
                )
        var has_uv = self._has_input(document, item, "uvNode")
        var has_level = self._has_input(document, item, "levelNode")
        if cube:
            if has_level:
                raise Error(
                    "Node JSON: a cube texture node's level is not read"
                )
            var sampler = self.graph.cube_uniform(uuid)
            var direction: NodeRef
            if has_uv:
                direction = self._input(document, item, "uvNode")
            else:
                # three.js's `reflectVector`: the view ray reflected in the
                # normal, in world space.
                var ray = self.graph.normalize(
                    self.graph.sub(
                        self.graph.position_world(),
                        self.graph.camera_position(),
                    )
                )
                direction = self.graph.reflect(ray, self.graph.normal_world())
            self.textures.append(NodeTextureRead(uuid, texture, "", True))
            return self.graph.texture_cube(sampler, direction)
        var sampler = self.graph.texture_uniform(uuid)
        var at: NodeRef
        if has_uv:
            at = self._input(document, item, "uvNode")
        else:
            at = self.graph.uv()
        var matrix = String()
        if _flag(document, item, "updateMatrix", False):
            # The texture's own transform, three.js's `texture.matrix`,
            # set with the texture.
            matrix = uuid + ".matrix"
            var transform = self.graph.uniform(matrix, Matrix3())
            at = self.graph.swizzle(
                self.graph.mul(
                    transform, self.graph.join([at, self.graph.float(1)])
                ),
                "xy",
            )
        self.textures.append(NodeTextureRead(uuid, texture, matrix, False))
        if not _flag(document, item, "sampler", True):
            var level = self.graph.float(0)
            if has_level:
                level = self._input(document, item, "levelNode")
            return self.graph.texture_load(sampler, at, level)
        if has_level:
            var level = self._input(document, item, "levelNode")
            return self.graph.texture_level(sampler, at, level)
        return self.graph.texture(sampler, at)

    def material(
        mut self, document: JsonDocument, item: Int
    ) raises -> NodeMaterialGraph:
        """Read a node material's outputs, three.js's `NodeMaterialLoader`.

        Each property of the material's `inputNodes` names the node of one
        output. The nodes are the material's own `nodes`, where it has
        them, and any list `parse_nodes` indexed first. Each output takes
        its type as three.js converts it.

        Args:
            document: The parsed file.
            item: The material's object.

        Returns:
            The graph, with its outputs set, and the texture nodes it reads.

        Raises:
            Error: If the material has no `inputNodes` object, a property
                has no output here, or a node is refused; see `node`.
        """
        var own = document.get(item, "nodes")
        if own != NO_NODE and document.kind(own) == ARRAY:
            self.parse_nodes(document, own)
        var inputs = document.get(item, "inputNodes")
        if inputs == NO_NODE or document.kind(inputs) != OBJECT:
            raise Error("Node JSON: a node material needs inputNodes")
        var refs = List[Int](length=NODE_OUTPUT_COUNT, fill=-1)
        for index in range(document.length(inputs)):
            var property = document.key(inputs, index)
            var output = node_output_of(property)
            if not output.is_valid():
                raise Error(
                    "Node JSON: a node material's " + property + " is not read"
                )
            refs[output.value] = self.node(
                document, document.string(document.at(inputs, index))
            ).value
        # three.js's `vec4(colorNode)`: a `vec4` or a `float` color carries
        # an alpha, which multiplies the opacity.
        var color = refs[COLOR_NODE.value]
        if color >= 0:
            var type = self.graph.type_of(NodeRef(color))
            if type == NODE_VEC4 or type == NODE_FLOAT:
                var alpha = NodeRef(color)
                if type == NODE_VEC4:
                    alpha = self.graph.swizzle(alpha, "w")
                var opacity: NodeRef
                if refs[OPACITY_NODE.value] >= 0:
                    opacity = self.convert(
                        NodeRef(refs[OPACITY_NODE.value]), "float"
                    )
                else:
                    var at = document.get(item, "opacity")
                    opacity = self.graph.float(
                        1 if at == NO_NODE else Float32(document.number(at))
                    )
                refs[OPACITY_NODE.value] = self.graph.mul(alpha, opacity).value
        for index in range(NODE_OUTPUT_COUNT):  # pragma: no branch
            if refs[index] < 0:
                continue
            var output = NodeOutput(index)
            var value = self.convert(
                NodeRef(refs[index]), output.value_type().name()
            )
            if output == NORMAL_NODE:
                # three.js's normal node is in view space and replaces the
                # normal: take it to world space, less the normal.
                var world = self.graph.swizzle(
                    self.graph.mul(
                        self.graph.join([value, self.graph.float(0)]),
                        self.graph.camera_view_matrix(),
                    ),
                    "xyz",
                )
                value = self.graph.sub(world, self.graph.normal_world())
            elif output == POSITION_NODE:
                value = self.graph.sub(value, self.graph.position_local())
            self.graph.set_output(output, value)
        return NodeMaterialGraph(self.graph.copy(), self.textures.copy())


def _position_of_int(values: List[Int], value: Int) -> Int:
    """Return where a number is in a list, or -1."""
    for index in range(len(values)):
        if values[index] == value:
            return index
    return -1


def _unary_methods() -> List[String]:
    """Return the math methods of one value this loader reads."""
    return [
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
        "transpose",
        "determinant",
        "inverse",
        "sinh",
        "cosh",
        "tanh",
        "asinh",
        "acosh",
        "atanh",
    ]


def _value_width(name: String) -> Int:
    """Return how many numbers a `valueType` holds, or -1 for one that is
    not read: `float`, `bool`, `vec2` to `vec4`, `color`, `mat3` and
    `mat4`."""
    var at = _position(
        ["float", "bool", "vec2", "vec3", "vec4", "color", "mat3", "mat4"],
        name,
    )
    if at < 0:
        return -1
    return [1, 1, 2, 3, 4, 3, 9, 16][at]


def _ternary_methods() -> List[String]:
    """Return the math methods of three values this loader reads."""
    return ["mix", "clamp", "refract", "smoothstep", "faceforward"]


def _binary_methods() -> List[String]:
    """Return the math methods of two values this loader reads."""
    return [
        "atan",
        "min",
        "max",
        "step",
        "reflect",
        "distance",
        "difference",
        "dot",
        "cross",
        "pow",
        "equals",
        "transformDirection",
    ]


def read_node_material(text: String) raises -> NodeMaterialGraph:
    """Read a node material that three.js's `NodeMaterial.toJSON()` wrote
    alone, with its nodes inside it.

    Set each texture of `textures` on the compiled program with
    `set_texture` or `set_cube`, by its `uniform`. `read_object_json` does
    that for a material in a scene's file.

    Args:
        text: The JSON.

    Returns:
        The graph, with its outputs set, and the texture nodes it reads.

    Raises:
        Error: If the text is not a JSON object, or anything
            `NodeLoader.material` raises.
    """
    var document = parse_json(text)
    if document.kind(document.root()) != OBJECT:
        raise Error("Node JSON: a node material must be an object")
    var loader = NodeLoader()
    return loader.material(document, document.root())
