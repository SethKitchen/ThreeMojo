# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Custom shading from small expression graphs: three.js's node materials.

three.js lets a material replace parts of its shader with a graph of nodes,
its Three Shading Language (TSL): `material.colorNode = mix(a, b, sin(time))`.
The graph is compiled to a shader. This port has no shader compiler, so a
`NodeGraph` is compiled to a compact bytecode instead, a `NodeProgram`, and
both rasterizers interpret that bytecode per fragment with the one function
here, `run_nodes`. The host reads the program out of a list and the kernel
reads it out of a device buffer, through the `NodeSource` trait, so the two
backends run the same arithmetic in the same order. `materials.glsl`
compiles GLSL source to the same graphs.

A graph sets up to nine outputs, each three.js's property of the same name:

- `COLOR_NODE`, a `vec3`: the surface's diffuse color, three.js's
  `colorNode`. It replaces the material's color, its vertex colors and its
  map, and the lighting then multiplies it.
- `OPACITY_NODE`, a `float`: the fragment's alpha, three.js's
  `opacityNode`. It replaces the opacity, the map's alpha and the alpha map,
  before the alpha test.
- `EMISSIVE_NODE`, a `vec3`: the light the surface gives off, three.js's
  `emissiveNode`. It replaces the emissive color and the emissive map.
- `NORMAL_NODE`, a `vec3`: an offset added to the world-space normal before
  the lights read it. three.js's `normalNode` replaces the normal; add the
  normal node to the offset to get that.
- `POSITION_NODE`, a `vec3`: an offset added to each vertex's local position,
  on the host, before the model matrix. three.js's `positionNode` replaces the
  position; add the local position to the offset to get that.
- `OUTPUT_NODE`, a `vec3`: the finished color, three.js's `outputNode`. The
  `lit` node reads what the standard lighting of the material's kind made of
  the surface, so a graph can tint, mix or replace lit output.
- `MASK_NODE`, a `float`: three.js's `maskNode`. A fragment where it is zero
  is thrown away, before the alpha test. Every `Discard` joins it.
- `AO_NODE`, a `float`: three.js's `aoNode`. It replaces the ambient
  occlusion map's value, which dims the indirect light.
- `DEPTH_NODE`, a `float`: three.js's `depthNode`, the window depth from zero
  at the near plane to one at the far plane. It replaces the depth the
  fragment is tested and stored with.

A graph refuses a type error as it is built: a `vec3` added to a `vec2`, a
`float` output given a `vec3`, a swizzle of a component the value lacks. A
`float` next to a vector is repeated into every component, as GLSL does. A
rewire that would make a cycle is refused, and `compile` refuses a cycle and
a node that reads what its stage does not have. A program refuses a uniform
name it does not know, and a value of the wrong type for one it does.

**Control flow.** `If`, `ElseIf`, `Else`, `Loop`, `End`, `Var` and `Discard`
are TSL's statements. The bytecode has no jumps: the graph is built in
static single assignment form. An `If` computes both branches and each
variable a branch assigns is then a `select` of the two. A `Loop` has a
fixed count, and `End` unrolls it. So every output stays a graph with no
cycle, each node is one instruction, and a derivative can run any part of it
again. `Fn` is a function of nodes with a typed layout; a call inlines it.

**Derivatives and varyings.** `dfdx` and `dfdy` are exact per triangle: the
argument is computed again with the attributes of the pixel to the right or
the pixel above, which the triangle's own plane gives, and the difference
is the answer. A hardware quad takes the difference inside a two by two
block instead. `varying` computes its argument at each of the triangle's
three corners and interpolates the three with the fragment's
perspective-correct weights.

**Registers.** Each instruction writes one of `MAX_REGISTERS` registers of
four floats. The compiler gives a register back when the last reader of its
value has run, so an output can hold up to `MAX_INSTRUCTIONS` instructions
while no more than `MAX_REGISTERS` values are alive at once.

**What three.js offers that is not ported.** Compute nodes, storage buffers,
`Break`, `Continue` and `Return` in a loop, integer and bit operations, the
matrix functions (`transpose`, `inverse`), the Worley and cell noises and
`mx_noise_vec3`, and a texture node's own mip level: a texture node reads
its image at the level the surface's own coordinates pick, where WebGPU
measures the derivatives of the coordinate the node computes.
"""

from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.smoothstep import smoothstep
from math.vector2 import Vector2
from math.vector3 import Vector3
from math.vector4 import Vector4
from render.framebuffer import Color, FloatColor
from render.texture_store import NO_TEXTURE, TextureId
from std.math import ceil, cos, exp, exp2, floor, log2, max, min, pow, sin, sqrt
from units.si import Duration, SECOND

# How many values one output can hold alive at once: one register each, four
# floats a register. The kernel keeps them in a fixed array per thread, so
# the number is fixed, and a graph that needs more is refused by `compile`.
comptime MAX_REGISTERS = 32
# How many instructions one output can hold, so a fragment's work is bounded.
comptime MAX_INSTRUCTIONS = 4096
# How many times one `Loop` can run its body, and how many nodes a graph can
# grow to as its loops are unrolled.
comptime MAX_LOOP_COUNT = 1024
comptime MAX_GRAPH_NODES = 65536
# How one instruction is laid out: the node kind, the registers of its three
# inputs, one immediate -- where a constant's floats are, which components a
# swizzle picks, or how wide a vector is -- and the register it writes. A
# node that reads the fragment keeps its context in the third input's place.
comptime INSTRUCTION_OP = 0
comptime INSTRUCTION_A = 1
comptime INSTRUCTION_B = 2
comptime INSTRUCTION_C = 3
comptime INSTRUCTION_IMMEDIATE = 4
comptime INSTRUCTION_DEST = 5
comptime INSTRUCTION_FLOATS = 6
# How a program begins: where each of the nine outputs starts and how many
# instructions it holds, then the frame's time in seconds, then the view
# matrix, sixteen floats, column-major. The renderer writes the last two
# every frame, as three.js updates its `time` and `cameraViewMatrix` nodes.
comptime NODE_OUTPUT_COUNT = 9
comptime PROGRAM_TIME = NODE_OUTPUT_COUNT * 2
comptime PROGRAM_VIEW = PROGRAM_TIME + 1
comptime PROGRAM_HEADER = PROGRAM_VIEW + 16

comptime Lanes = SIMD[DType.float32, 4]


@fieldwise_init
struct ValueType(Equatable, ImplicitlyCopyable, Writable):
    """What a node's value is, as a type rather than a bare int: a `float`,
    a vector of two, three or four, a `mat3` or a `mat4`, or a texture.
    `value` is the component count, and 32 for a texture."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the seven types there are.

        Returns:
            Whether the value is one to four, 9, 16 or 32.
        """
        return (
            (self.value >= 1 and self.value <= 4)
            or self.value == 9
            or self.value == 16
            or self.value == 32
        )

    def is_vector(self) -> Bool:
        """Return True if a register holds this type: a `float` or a vector.

        Returns:
            Whether the value is one to four.
        """
        return self.value >= 1 and self.value <= 4

    def name(self) -> String:
        """Return the type's TSL name, for an error message.

        Returns:
            `float`, `vec2` to `vec4`, `mat3`, `mat4` or `texture`.
        """
        if self.value == 1:
            return "float"
        if self.value == 9:
            return "mat3"
        if self.value == 16:
            return "mat4"
        if self.value == 32:
            return "texture"
        return "vec" + String(self.value)


comptime NODE_FLOAT = ValueType(1)
comptime NODE_VEC2 = ValueType(2)
comptime NODE_VEC3 = ValueType(3)
comptime NODE_VEC4 = ValueType(4)
comptime NODE_MAT3 = ValueType(9)
comptime NODE_MAT4 = ValueType(16)
comptime NODE_SAMPLER = ValueType(32)


@fieldwise_init
struct NodeKind(Equatable, ImplicitlyCopyable, Writable):
    """What a node computes, as a type rather than a bare int. `value` is
    also the instruction's operation in a compiled program."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the kinds there are.

        Returns:
            Whether the value names a kind.
        """
        return (
            self.value >= NODE_CONSTANT.value
            and self.value <= NODE_VIEW_MATRIX.value
        )


# A fixed value, and a named value the caller can change between frames.
comptime NODE_CONSTANT = NodeKind(0)
comptime NODE_UNIFORM = NodeKind(1)
# The surface's attributes, three.js's `uv()`, `positionLocal`,
# `positionWorld`, `positionView`, `normalLocal`, `normalWorld`,
# `normalView` and `vertexColor()`, and the frame's `time`.
comptime NODE_UV = NodeKind(2)
comptime NODE_POSITION_LOCAL = NodeKind(3)
comptime NODE_POSITION_WORLD = NodeKind(4)
comptime NODE_POSITION_VIEW = NodeKind(5)
comptime NODE_NORMAL_LOCAL = NodeKind(6)
comptime NODE_NORMAL_WORLD = NodeKind(7)
comptime NODE_NORMAL_VIEW = NodeKind(8)
comptime NODE_VERTEX_COLOR = NodeKind(9)
comptime NODE_TIME = NodeKind(10)
# A texture read at a coordinate, three.js's `texture(map, uv)`, the color
# the standard lighting made, three.js's `output`, and the camera's place in
# the world, three.js's `cameraPosition`.
comptime NODE_TEXTURE = NodeKind(11)
comptime NODE_LIT = NodeKind(12)
comptime NODE_CAMERA_POSITION = NodeKind(13)
# The math, each three.js's function of the same name.
comptime NODE_ADD = NodeKind(14)
comptime NODE_SUB = NodeKind(15)
comptime NODE_MUL = NodeKind(16)
comptime NODE_DIV = NodeKind(17)
comptime NODE_MIX = NodeKind(18)
comptime NODE_CLAMP = NodeKind(19)
comptime NODE_DOT = NodeKind(20)
comptime NODE_NORMALIZE = NodeKind(21)
comptime NODE_SIN = NodeKind(22)
comptime NODE_COS = NodeKind(23)
comptime NODE_POW = NodeKind(24)
comptime NODE_STEP = NodeKind(25)
comptime NODE_SMOOTHSTEP = NodeKind(26)
comptime NODE_LENGTH = NodeKind(27)
comptime NODE_FRACT = NodeKind(28)
comptime NODE_SWIZZLE = NodeKind(29)
# Components of up to three values laid end to end, TSL's `vec3(a, b)`.
comptime NODE_JOIN = NodeKind(30)
comptime NODE_ABS = NodeKind(31)
comptime NODE_SIGN = NodeKind(32)
comptime NODE_FLOOR = NodeKind(33)
comptime NODE_CEIL = NodeKind(34)
comptime NODE_ROUND = NodeKind(35)
comptime NODE_TRUNC = NodeKind(36)
comptime NODE_EXP = NodeKind(37)
comptime NODE_EXP2 = NodeKind(38)
comptime NODE_LOG = NodeKind(39)
comptime NODE_LOG2 = NodeKind(40)
comptime NODE_SQRT = NodeKind(41)
comptime NODE_INVERSE_SQRT = NodeKind(42)
comptime NODE_NEGATE = NodeKind(43)
comptime NODE_ONE_MINUS = NodeKind(44)
comptime NODE_SATURATE = NodeKind(45)
comptime NODE_TAN = NodeKind(46)
comptime NODE_ASIN = NodeKind(47)
comptime NODE_ACOS = NodeKind(48)
comptime NODE_ATAN = NodeKind(49)
comptime NODE_RECIPROCAL = NodeKind(50)
comptime NODE_RADIANS = NodeKind(51)
comptime NODE_DEGREES = NodeKind(52)
comptime NODE_MIN = NodeKind(53)
comptime NODE_MAX = NodeKind(54)
comptime NODE_MOD = NodeKind(55)
comptime NODE_ATAN2 = NodeKind(56)
comptime NODE_DISTANCE = NodeKind(57)
comptime NODE_CROSS = NodeKind(58)
comptime NODE_REFLECT = NodeKind(59)
comptime NODE_REFRACT = NodeKind(60)
comptime NODE_FACEFORWARD = NodeKind(61)
# Comparisons and logic, one or zero per component, and a choice by one.
comptime NODE_LESS_THAN = NodeKind(62)
comptime NODE_LESS_THAN_EQUAL = NodeKind(63)
comptime NODE_GREATER_THAN = NodeKind(64)
comptime NODE_GREATER_THAN_EQUAL = NodeKind(65)
comptime NODE_EQUAL = NodeKind(66)
comptime NODE_NOT_EQUAL = NodeKind(67)
comptime NODE_AND = NodeKind(68)
comptime NODE_OR = NodeKind(69)
comptime NODE_XOR = NodeKind(70)
comptime NODE_NOT = NodeKind(71)
comptime NODE_SELECT = NodeKind(72)
# A matrix times a vector, and a vector times a matrix: the matrix is read
# from the program where the immediate says, not from a register.
comptime NODE_MATRIX_VECTOR = NodeKind(73)
comptime NODE_VECTOR_MATRIX = NodeKind(74)
# MaterialX's Perlin noise, three.js's `mx_perlin_noise_float`.
comptime NODE_NOISE = NodeKind(75)
# Three corner values mixed by the fragment's weights: what a varying
# compiles to. Only `compile` writes it.
comptime NODE_INTERPOLATE = NodeKind(76)
# Nodes of the graph that `compile` turns into other instructions: a
# varying, the two derivatives, a variable's value where a loop begins, and
# the camera's view matrix.
comptime NODE_VARYING = NodeKind(77)
comptime NODE_DFDX = NodeKind(78)
comptime NODE_DFDY = NodeKind(79)
comptime NODE_COPY = NodeKind(80)
comptime NODE_VIEW_MATRIX = NodeKind(81)


@fieldwise_init
struct NodeOutput(Equatable, ImplicitlyCopyable, Writable):
    """Which part of the shading a graph replaces, as a type rather than a
    bare int. See the module's list."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the nine outputs there are.

        Returns:
            Whether the value names an output.
        """
        return self.value >= 0 and self.value < NODE_OUTPUT_COUNT

    def value_type(self) -> ValueType:
        """Return the type a node given this output must have.

        Returns:
            `NODE_FLOAT` for the opacity, the mask, the ambient occlusion
            and the depth, and `NODE_VEC3` for the rest.
        """
        return NODE_FLOAT if (
            self == OPACITY_NODE
            or self == MASK_NODE
            or self == AO_NODE
            or self == DEPTH_NODE
        ) else NODE_VEC3


comptime COLOR_NODE = NodeOutput(0)
comptime OPACITY_NODE = NodeOutput(1)
comptime EMISSIVE_NODE = NodeOutput(2)
comptime NORMAL_NODE = NodeOutput(3)
comptime POSITION_NODE = NodeOutput(4)
comptime OUTPUT_NODE = NodeOutput(5)
comptime MASK_NODE = NodeOutput(6)
comptime AO_NODE = NodeOutput(7)
comptime DEPTH_NODE = NodeOutput(8)


@fieldwise_init
struct NodeContext(Equatable, ImplicitlyCopyable, Writable):
    """Where a node reads the surface's attributes, as a type rather than a
    bare int: the fragment itself, the fragment's own interpolated
    attributes before any map, the pixel to the right or the pixel above for
    a derivative, or one of the triangle's corners for a varying."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the seven contexts there are.

        Returns:
            Whether the value is zero to six.
        """
        return self.value >= 0 and self.value < NODE_CONTEXT_COUNT

    def is_corner(self) -> Bool:
        """Return True if this is one of the triangle's three corners.

        Returns:
            Whether the value is `CORNER_A`, `CORNER_B` or `CORNER_C`.
        """
        return self.value >= CORNER_A.value


# The fragment, with the normal the maps and the normal node made.
comptime AT_FRAGMENT = NodeContext(0)
# The fragment's own interpolated attributes, the normal before any map.
comptime AT_HERE = NodeContext(1)
# The pixel one to the right and the pixel one above, for `dfdx` and `dfdy`.
comptime AT_RIGHT = NodeContext(2)
comptime AT_UP = NodeContext(3)
# The triangle's three corners, for a varying.
comptime CORNER_A = NodeContext(4)
comptime CORNER_B = NodeContext(5)
comptime CORNER_C = NodeContext(6)
comptime NODE_CONTEXT_COUNT = 7


@fieldwise_init
struct NodeRef(Equatable, ImplicitlyCopyable, Writable):
    """Which node of a `NodeGraph`, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name a node: it is not negative.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct NodeVar(Equatable, ImplicitlyCopyable, Writable):
    """Which variable of a `NodeGraph`, TSL's `Var`, as a type rather than a
    bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name a variable: it is not negative.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct NodeProgramId(Equatable, ImplicitlyCopyable, Writable):
    """Which program in a `NodeProgramStore`, as a type rather than a bare
    int. See `core.object3d.NodeId` for why these are wrapped."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name a program, or is `NO_NODES`.

        Returns:
            Whether the value is zero or more, or is `NO_NODES`.
        """
        return self.value >= 0 or self == NO_NODES


# What a material holds when no graph replaces any of its shading.
comptime NO_NODES = NodeProgramId(-1)


def _lane_of(letter: UInt8) -> Int:
    """Return the component a swizzle letter names, or -1 for none."""
    if letter == UInt8(ord("x")) or letter == UInt8(ord("r")):
        return 0
    if letter == UInt8(ord("y")) or letter == UInt8(ord("g")):
        return 1
    if letter == UInt8(ord("z")) or letter == UInt8(ord("b")):
        return 2
    if letter == UInt8(ord("w")) or letter == UInt8(ord("a")):
        return 3
    return -1


def _note_texture(mut textures: List[TextureId], map: TextureId):
    """Append a texture to a program's list, once."""
    for index in range(len(textures)):
        if textures[index] == map:
            return
    textures.append(map)


def _pool_size(type: ValueType) -> Int:
    """Return how many floats a constant or a uniform of a type holds."""
    return 9 if type == NODE_MAT3 else (16 if type == NODE_MAT4 else 4)


def _is_attribute(kind: NodeKind) -> Bool:
    """Return True for a node that reads the surface where it runs."""
    return (
        kind.value >= NODE_UV.value and kind.value <= NODE_VERTEX_COLOR.value
    ) or kind == NODE_LIT


# What an open block is: an `If` before and after its `Else`, and a `Loop`.
comptime _BLOCK_THEN = 0
comptime _BLOCK_ELSE = 1
comptime _BLOCK_LOOP = 2


@fieldwise_init
struct _Block(Copyable, Movable):
    """One `If` or `Loop` the graph is inside, and what `End` needs to
    close it."""

    var kind: Int
    # The condition of an `If`, and its negation once `Else` has run.
    var condition: Int
    var negation: Int
    # Whether `ElseIf` opened this `If`, so its `End` closes the outer too.
    var chained: Bool
    # Every variable's value where the block began, and where the `If`'s
    # first branch ended.
    var entry: List[Int]
    var then: List[Int]
    # A loop's count, first index and step, the first node of its body
    # (its index), and the node each variable reads where the body begins.
    var count: Int
    var start: Float32
    var step: Float32
    var body: Int
    var phis: List[Int]


comptime NodeBody = def(mut NodeGraph, List[NodeRef]) raises thin -> NodeRef


struct Fn(Copyable, Movable):
    """A function of nodes with a typed layout, TSL's `Fn` with its
    `setLayout`: a name, the types of its inputs, and the type it returns.

    The body is a Mojo function that builds nodes into the graph it is given
    from the refs of its arguments. `call` checks the arguments and the
    answer against the layout and inlines the body, as three.js inlines a
    `Fn` without a layout.
    """

    var name: String
    var inputs: List[ValueType]
    var output: ValueType
    var body: NodeBody

    def __init__(
        out self,
        name: String,
        var inputs: List[ValueType],
        output: ValueType,
        body: NodeBody,
    ) raises:
        """Create a function from its layout and its body.

        Args:
            name: What to call it in an error message.
            inputs: The type of each argument: a `float` or a vector.
            output: The type it returns: a `float` or a vector.
            body: What builds its nodes.

        Raises:
            Error: If a type is not a `float` or a vector.
        """
        for index in range(len(inputs)):
            if not inputs[index].is_vector():
                raise Error("A Fn takes floats and vectors, not a texture")
        if not output.is_vector():
            raise Error("A Fn returns a float or a vector")
        self.name = name
        self.inputs = inputs^
        self.output = output
        self.body = body

    def call(self, mut graph: NodeGraph, args: List[NodeRef]) raises -> NodeRef:
        """Build the function's nodes into a graph, TSL's `fn(a, b)`.

        Args:
            graph: The graph to build into.
            args: One node per input, each of the input's type.

        Returns:
            The node the body returned.

        Raises:
            Error: If the count or a type of the arguments is not the
                layout's, the body raises, leaves a block open, or returns a
                node of another type.
        """
        if len(args) != len(self.inputs):
            raise Error(
                "The Fn "
                + self.name
                + " takes "
                + String(len(self.inputs))
                + " arguments, not "
                + String(len(args))
            )
        for index in range(len(args)):
            if graph.type_of(args[index]) != self.inputs[index]:
                raise Error(
                    "The Fn "
                    + self.name
                    + " takes a "
                    + self.inputs[index].name()
                    + " as argument "
                    + String(index + 1)
                    + ", not a "
                    + graph.type_of(args[index]).name()
                )
        var depth = len(graph._blocks)
        var answer = self.body(graph, args)
        if len(graph._blocks) != depth:
            raise Error("The Fn " + self.name + " leaves an If or a Loop open")
        if graph.type_of(answer) != self.output:
            raise Error(
                "The Fn "
                + self.name
                + " returns a "
                + self.output.name()
                + ", not a "
                + graph.type_of(answer).name()
            )
        return answer


struct NodeGraph(Copyable, Movable):
    """A graph of nodes being built, three.js's TSL expressions.

    Every method that makes a node returns a `NodeRef` naming it, and takes
    the refs of the nodes it reads. A ref from another graph, or one made up,
    is refused. Nothing is evaluated here: `compile` turns the outputs into a
    `NodeProgram`.
    """

    # Per node: its kind and its type, the refs of up to three inputs (-1
    # for none), four floats of value -- a constant's, a uniform's, a
    # texture's id, a swizzle's packed components or a width -- and a
    # uniform's name. A matrix constant or uniform keeps its floats in
    # `_matrices`, from the offset its first value float holds.
    var _kinds: List[NodeKind]
    var _types: List[ValueType]
    var _inputs: List[Int]
    var _values: List[Float32]
    var _names: List[String]
    var _matrices: List[Float32]
    # Per output, the ref of the node that feeds it, or -1 for none.
    var _outputs: List[Int]
    # Each variable's value now and its type, the blocks the builder is
    # inside, and the nodes that say where each `Discard` keeps a fragment.
    var _versions: List[Int]
    var _var_types: List[ValueType]
    var _blocks: List[_Block]
    var _discards: List[Int]

    def __init__(out self):
        """Create an empty graph with no outputs."""
        self._kinds = List[NodeKind]()
        self._types = List[ValueType]()
        self._inputs = List[Int]()
        self._values = List[Float32]()
        self._names = List[String]()
        self._matrices = List[Float32]()
        self._outputs = List[Int](length=NODE_OUTPUT_COUNT, fill=-1)
        self._versions = List[Int]()
        self._var_types = List[ValueType]()
        self._blocks = List[_Block]()
        self._discards = List[Int]()

    def count(self) -> Int:
        """Return how many nodes the graph holds.

        Returns:
            The node count.
        """
        return len(self._kinds)

    def type_of(self, node: NodeRef) raises -> ValueType:
        """Return the type of a node's value.

        Args:
            node: A node of this graph.

        Returns:
            Its type.

        Raises:
            Error: If the graph has no such node.
        """
        self._check(node)
        return self._types[node.value]

    def output(self, output: NodeOutput) raises -> NodeRef:
        """Return the node that feeds an output, or `NodeRef(-1)` for none.

        Args:
            output: One of the nine outputs.

        Returns:
            The node's ref.

        Raises:
            Error: If the output is none of the nine.
        """
        if not output.is_valid():
            raise Error("A node output that is none of the nine")
        return NodeRef(self._outputs[output.value])

    def _check(self, node: NodeRef) raises:
        """Refuse a ref that names no node of this graph.

        Raises:
            Error: If the ref is negative or past the last node.
        """
        if node.value < 0 or node.value >= self.count():
            raise Error("A node graph has no node with that ref")

    def _add(
        mut self,
        kind: NodeKind,
        type: ValueType,
        a: Int = -1,
        b: Int = -1,
        c: Int = -1,
        value: Lanes = Lanes(0),
        name: String = "",
    ) -> NodeRef:
        """Append a node and return its ref."""
        self._kinds.append(kind)
        self._types.append(type)
        self._inputs.append(a)
        self._inputs.append(b)
        self._inputs.append(c)
        for lane in range(4):  # pragma: no branch
            self._values.append(value[lane])
        self._names.append(name)
        return NodeRef(self.count() - 1)

    # --- values -------------------------------------------------------------

    def float(mut self, x: Float32) -> NodeRef:
        """Return a constant `float`, TSL's `float(x)`.

        Args:
            x: The value.

        Returns:
            The node.
        """
        return self._add(NODE_CONSTANT, NODE_FLOAT, value=Lanes(x, 0, 0, 0))

    def vec2(mut self, x: Float32, y: Float32) -> NodeRef:
        """Return a constant `vec2`, TSL's `vec2(x, y)`.

        Args:
            x: The first component.
            y: The second.

        Returns:
            The node.
        """
        return self._add(NODE_CONSTANT, NODE_VEC2, value=Lanes(x, y, 0, 0))

    def vec3(mut self, x: Float32, y: Float32, z: Float32) -> NodeRef:
        """Return a constant `vec3`, TSL's `vec3(x, y, z)`.

        Args:
            x: The first component.
            y: The second.
            z: The third.

        Returns:
            The node.
        """
        return self._add(NODE_CONSTANT, NODE_VEC3, value=Lanes(x, y, z, 0))

    def vec4(
        mut self, x: Float32, y: Float32, z: Float32, w: Float32
    ) -> NodeRef:
        """Return a constant `vec4`, TSL's `vec4(x, y, z, w)`.

        Args:
            x: The first component.
            y: The second.
            z: The third.
            w: The fourth.

        Returns:
            The node.
        """
        return self._add(NODE_CONSTANT, NODE_VEC4, value=Lanes(x, y, z, w))

    def color(mut self, color: Color) -> NodeRef:
        """Return a constant color as a linear `vec3`, TSL's `color()`.

        Args:
            color: The color, as authored in sRGB. Its alpha is not read.

        Returns:
            The node.
        """
        var linear = FloatColor(srgb=color)
        return self.vec3(linear.r, linear.g, linear.b)

    def _uniform(
        mut self, name: String, type: ValueType, value: Lanes
    ) raises -> NodeRef:
        """Append a uniform after refusing an empty or a repeated name.

        Raises:
            Error: If the name is empty or another uniform has it.
        """
        if name == "":
            raise Error("A uniform needs a name")
        for index in range(self.count()):
            if (
                self._kinds[index] == NODE_UNIFORM
                and self._names[index] == name
            ):
                raise Error("A node graph already has a uniform named " + name)
        return self._add(NODE_UNIFORM, type, value=value, name=name)

    def uniform(mut self, name: String, value: Float32) raises -> NodeRef:
        """Return a named `float` the caller can change between frames,
        TSL's `uniform(value)`. See `NodeProgram.set_uniform`.

        Args:
            name: A name no other uniform of this graph has.
            value: Its first value.

        Returns:
            The node.

        Raises:
            Error: If the name is empty or already taken.
        """
        return self._uniform(name, NODE_FLOAT, Lanes(value, 0, 0, 0))

    def uniform(mut self, name: String, value: Vector2) raises -> NodeRef:
        """Return a named `vec2` the caller can change between frames.

        Args:
            name: A name no other uniform of this graph has.
            value: Its first value.

        Returns:
            The node.

        Raises:
            Error: If the name is empty or already taken.
        """
        return self._uniform(name, NODE_VEC2, Lanes(value.x, value.y, 0, 0))

    def uniform(mut self, name: String, value: Vector3) raises -> NodeRef:
        """Return a named `vec3` the caller can change between frames.

        Args:
            name: A name no other uniform of this graph has.
            value: Its first value.

        Returns:
            The node.

        Raises:
            Error: If the name is empty or already taken.
        """
        return self._uniform(
            name, NODE_VEC3, Lanes(value.x, value.y, value.z, 0)
        )

    def uniform(mut self, name: String, value: Vector4) raises -> NodeRef:
        """Return a named `vec4` the caller can change between frames.

        Args:
            name: A name no other uniform of this graph has.
            value: Its first value.

        Returns:
            The node.

        Raises:
            Error: If the name is empty or already taken.
        """
        return self._uniform(
            name, NODE_VEC4, Lanes(value.x, value.y, value.z, value.w)
        )

    def uniform(mut self, name: String, value: Color) raises -> NodeRef:
        """Return a named color, a linear `vec3`, the caller can change
        between frames, TSL's `uniform(color)`.

        Args:
            name: A name no other uniform of this graph has.
            value: Its first value, as authored in sRGB.

        Returns:
            The node.

        Raises:
            Error: If the name is empty or already taken.
        """
        var linear = FloatColor(srgb=value)
        return self._uniform(
            name, NODE_VEC3, Lanes(linear.r, linear.g, linear.b, 0)
        )

    def _matrix_uniform(
        mut self, name: String, type: ValueType, elements: List[Float32]
    ) raises -> NodeRef:
        """Append a matrix uniform, its elements kept in `_matrices`.

        Raises:
            Error: If the name is empty or already taken.
        """
        var at = len(self._matrices)
        self._matrices.extend(elements.copy())
        return self._uniform(name, type, Lanes(Float32(at), 0, 0, 0))

    def uniform(mut self, name: String, value: Matrix3) raises -> NodeRef:
        """Return a named `mat3` the caller can change between frames. Only
        `mul` reads a matrix, with a vector.

        Args:
            name: A name no other uniform of this graph has.
            value: Its first value.

        Returns:
            The node.

        Raises:
            Error: If the name is empty or already taken.
        """
        var elements = List[Float32]()
        for index in range(9):  # pragma: no branch
            elements.append(value.elements[index])
        return self._matrix_uniform(name, NODE_MAT3, elements)

    def uniform(mut self, name: String, value: Matrix4) raises -> NodeRef:
        """Return a named `mat4` the caller can change between frames. Only
        `mul` reads a matrix, with a vector.

        Args:
            name: A name no other uniform of this graph has.
            value: Its first value.

        Returns:
            The node.

        Raises:
            Error: If the name is empty or already taken.
        """
        var elements = List[Float32]()
        for index in range(16):  # pragma: no branch
            elements.append(value.elements[index])
        return self._matrix_uniform(name, NODE_MAT4, elements)

    def texture_uniform(
        mut self, name: String, map: TextureId = NO_TEXTURE
    ) raises -> NodeRef:
        """Return a named texture the caller can change between frames,
        three.js's `texture(map)` whose `value` is set later. Read it with
        `texture(sampler, uv)`, and change it with `NodeProgram.set_texture`.

        Args:
            name: A name no other uniform of this graph has.
            map: Its first texture, or `NO_TEXTURE` for one set later. A
                mode that reads textures refuses to draw with none set.

        Returns:
            The node, of type `texture`.

        Raises:
            Error: If the name is empty or already taken, or `map` is a
                negative other than `NO_TEXTURE`.
        """
        if map.value < 0 and map != NO_TEXTURE:
            raise Error("A texture uniform names no texture there can be")
        return self._uniform(
            name, NODE_SAMPLER, Lanes(Float32(map.value), 0, 0, 0)
        )

    # --- attributes ---------------------------------------------------------

    def uv(mut self) -> NodeRef:
        """Return the surface's texture coordinate, a `vec2`: the one the
        material's `map` is read at, through its transform.

        Returns:
            The node.
        """
        return self._add(NODE_UV, NODE_VEC2)

    def position_local(mut self) -> NodeRef:
        """Return the vertex's position in the model's own space, a `vec3`,
        three.js's `positionLocal`. Only a `POSITION_NODE` reads it.

        Returns:
            The node.
        """
        return self._add(NODE_POSITION_LOCAL, NODE_VEC3)

    def position_world(mut self) -> NodeRef:
        """Return the fragment's position in world space, a `vec3`, in
        meters, three.js's `positionWorld`.

        Returns:
            The node.
        """
        return self._add(NODE_POSITION_WORLD, NODE_VEC3)

    def position_view(mut self) -> NodeRef:
        """Return the fragment's position in the camera's space, a `vec3`,
        three.js's `positionView`: the camera looks down minus z.

        Returns:
            The node.
        """
        return self._add(NODE_POSITION_VIEW, NODE_VEC3)

    def normal_local(mut self) -> NodeRef:
        """Return the vertex's normal in the model's own space, a `vec3`,
        three.js's `normalLocal`: zero for a geometry that has none. Only
        a `POSITION_NODE` reads it.

        Returns:
            The node.
        """
        return self._add(NODE_NORMAL_LOCAL, NODE_VEC3)

    def normal_world(mut self) -> NodeRef:
        """Return the fragment's unit normal in world space, a `vec3`,
        three.js's `normalWorld`, after any normal or bump map.

        Returns:
            The node.
        """
        return self._add(NODE_NORMAL_WORLD, NODE_VEC3)

    def normal_view(mut self) -> NodeRef:
        """Return the fragment's unit normal in the camera's space, a
        `vec3`, three.js's `normalView`.

        Returns:
            The node.
        """
        return self._add(NODE_NORMAL_VIEW, NODE_VEC3)

    def vertex_color(mut self) -> NodeRef:
        """Return the interpolated corner color, a linear `vec3`: the
        material's color times the geometry's vertex colors when it has
        them, three.js's `materialColor` times `vertexColor()`.

        Returns:
            The node.
        """
        return self._add(NODE_VERTEX_COLOR, NODE_VEC3)

    def time(mut self) -> NodeRef:
        """Return the frame's time in seconds, a `float`, three.js's `time`.
        The renderer's `time` sets it.

        Returns:
            The node.
        """
        return self._add(NODE_TIME, NODE_FLOAT)

    def camera_position(mut self) -> NodeRef:
        """Return the camera's position in world space, a `vec3`, three.js's
        `cameraPosition`, from the frame's view matrix.

        Returns:
            The node.
        """
        return self._add(NODE_CAMERA_POSITION, NODE_VEC3)

    def camera_view_matrix(mut self) -> NodeRef:
        """Return the frame's world-to-camera matrix, a `mat4`, three.js's
        `cameraViewMatrix`. Only `mul` reads it, with a `vec4`.

        Returns:
            The node.
        """
        return self._add(NODE_VIEW_MATRIX, NODE_MAT4)

    def texture(mut self, map: TextureId, uv: NodeRef) raises -> NodeRef:
        """Return a texture read at a coordinate, a linear `vec4` with
        straight alpha, three.js's `texture(map, uv)`. A shading mode that
        opens no textures reads opaque white.

        Args:
            map: The texture. It must be in the store the renderer draws
                with.
            uv: Where to read it, a `vec2`.

        Returns:
            The node.

        Raises:
            Error: If `map` is `NO_TEXTURE` or negative, or `uv` is not a
                `vec2` of this graph.
        """
        if map.value < 0:
            raise Error("A texture node needs a texture")
        self._check(uv)
        if self._types[uv.value] != NODE_VEC2:
            raise Error(
                "A texture node reads at a vec2, not a "
                + self._types[uv.value].name()
            )
        return self._add(
            NODE_TEXTURE,
            NODE_VEC4,
            uv.value,
            value=Lanes(Float32(map.value), 0, 0, 0),
        )

    def texture(mut self, sampler: NodeRef, uv: NodeRef) raises -> NodeRef:
        """Return a texture uniform read at a coordinate, a linear `vec4`
        with straight alpha: three.js's `texture(map, uv)` of a texture
        whose value can change.

        Args:
            sampler: A node of type `texture`, from `texture_uniform`.
            uv: Where to read it, a `vec2`.

        Returns:
            The node.

        Raises:
            Error: If either is not a node of this graph, `sampler` is not a
                texture, or `uv` is not a `vec2`.
        """
        self._check(sampler)
        self._check(uv)
        if self._types[sampler.value] != NODE_SAMPLER:
            raise Error(
                "A texture node reads a texture, not a "
                + self._types[sampler.value].name()
            )
        if self._types[uv.value] != NODE_VEC2:
            raise Error(
                "A texture node reads at a vec2, not a "
                + self._types[uv.value].name()
            )
        return self._add(NODE_TEXTURE, NODE_VEC4, uv.value, sampler.value)

    def lit(mut self) -> NodeRef:
        """Return the color the material's own lighting made of the surface,
        a linear `vec3`: three.js's `output`. Only an `OUTPUT_NODE` reads it.

        Returns:
            The node.
        """
        return self._add(NODE_LIT, NODE_VEC3)

    def varying(mut self, a: NodeRef) raises -> NodeRef:
        """Return a value computed at each corner of the triangle and
        interpolated across it, three.js's `varying(node)`.

        The value can read the world and view position and normal, the
        coordinates, the vertex color, the time, uniforms and any math of
        them. It reads no texture, no derivative, no lit color, and not the
        local position or normal, which a triangle's corners do not keep.

        Args:
            a: The value, a `float` or a vector.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph, or not a `float` or a
                vector.
        """
        self._vector(a, "interpolate")
        var type = self._types[a.value]
        return self._add(NODE_VARYING, type, a.value)

    # --- math ---------------------------------------------------------------

    def _vector(self, node: NodeRef, verb: String) raises:
        """Refuse a node that is not a `float` or a vector.

        Raises:
            Error: If the ref names no node of this graph, or the node is a
                matrix or a texture.
        """
        self._check(node)
        var type = self._types[node.value]
        if not type.is_vector():
            raise Error("A node graph cannot " + verb + " a " + type.name())

    def _splat(mut self, node: NodeRef, to: ValueType) -> NodeRef:
        """Return a `float` repeated into every component of `to`."""
        return self._add(NODE_SWIZZLE, to, node.value)

    def _match(
        mut self, node: NodeRef, to: ValueType, verb: String
    ) raises -> NodeRef:
        """Return `node` as a `to`: itself, or a `float` repeated.

        Raises:
            Error: If `node` is a vector of another size.
        """
        var type = self._types[node.value]
        if type == to:
            return node
        if type == NODE_FLOAT:
            return self._splat(node, to)
        raise Error(
            "A node graph cannot "
            + verb
            + " a "
            + to.name()
            + " and a "
            + type.name()
        )

    def _widest(self, a: NodeRef, b: NodeRef) -> ValueType:
        """Return the type two operands meet at: the wider of the two."""
        var left = self._types[a.value]
        var right = self._types[b.value]
        return left if left.value >= right.value else right

    def _binary(
        mut self, kind: NodeKind, a: NodeRef, b: NodeRef, verb: String
    ) raises -> NodeRef:
        """Append an operation of two operands of one type, or of a vector
        and a `float`.

        Raises:
            Error: If either is not a node of this graph, is not a `float` or
                a vector, or they are vectors of two sizes.
        """
        self._vector(a, verb)
        self._vector(b, verb)
        var type = self._widest(a, b)
        var left = self._match(a, type, verb)
        var right = self._match(b, type, verb)
        return self._add(kind, type, left.value, right.value)

    def add(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return `a + b`, TSL's `add`.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_ADD, a, b, "add")

    def sub(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return `a - b`, TSL's `sub`.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_SUB, a, b, "subtract")

    def _matrix_of(self, node: NodeRef) -> Bool:
        """Return True if a node is a `mat3` or a `mat4`."""
        var type = self._types[node.value]
        return type == NODE_MAT3 or type == NODE_MAT4

    def mul(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return `a * b`, TSL's `mul`: component by component for two
        vectors, or a matrix times a vector, or a vector times a matrix.

        Args:
            a: The first operand.
            b: The second, of `a`'s type or either a `float`, or a vector as
                wide as a matrix beside it.

        Returns:
            The node, of the wider type, or of the vector's type.

        Raises:
            Error: If either is not a node of this graph, they are vectors
                of two sizes, two matrices, or a matrix and a vector of
                another size.
        """
        self._check(a)
        self._check(b)
        if self._matrix_of(a) or self._matrix_of(b):
            var on_left = self._matrix_of(a)
            var matrix = a if on_left else b
            var vector = b if on_left else a
            var size = 3 if self._types[matrix.value] == NODE_MAT3 else 4
            if self._types[vector.value] != ValueType(size):
                raise Error(
                    "A node graph cannot multiply a "
                    + self._types[a.value].name()
                    + " and a "
                    + self._types[b.value].name()
                )
            return self._add(
                NODE_MATRIX_VECTOR if on_left else NODE_VECTOR_MATRIX,
                ValueType(size),
                vector.value,
                matrix.value,
            )
        return self._binary(NODE_MUL, a, b, "multiply")

    def div(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return `a / b` component by component, TSL's `div`. A division by
        zero gives what IEEE 754 gives, as a GPU does.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_DIV, a, b, "divide")

    def pow(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return `a` raised to `b` component by component, TSL's `pow`.
        GLSL leaves a negative `a` undefined.

        Args:
            a: The base.
            b: The exponent, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_POW, a, b, "raise")

    def step(mut self, edge: NodeRef, x: NodeRef) raises -> NodeRef:
        """Return zero where `x` is below `edge` and one elsewhere, TSL's
        `step(edge, x)`.

        Args:
            edge: The edge.
            x: The value, of `edge`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_STEP, edge, x, "step")

    def min(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return the lesser of `a` and `b` per component, TSL's `min`.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_MIN, a, b, "take the min of")

    def max(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return the greater of `a` and `b` per component, TSL's `max`.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_MAX, a, b, "take the max of")

    def mod(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return `a - b * floor(a / b)` per component, TSL's `mod` and
        GLSL's.

        Args:
            a: The dividend.
            b: The divisor, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_MOD, a, b, "take the mod of")

    def atan2(mut self, y: NodeRef, x: NodeRef) raises -> NodeRef:
        """Return the angle of `(x, y)` per component, in radians from minus
        pi to pi, TSL's `atan(y, x)` and GLSL's.

        Args:
            y: The rise.
            x: The run, of `y`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_ATAN2, y, x, "take the atan of")

    def less_than(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return one where `a < b` and zero elsewhere, per component, TSL's
        `lessThan`. A condition is a `float`: zero is false.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_LESS_THAN, a, b, "compare")

    def less_than_equal(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return one where `a <= b` and zero elsewhere, TSL's
        `lessThanEqual`.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_LESS_THAN_EQUAL, a, b, "compare")

    def greater_than(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return one where `a > b` and zero elsewhere, TSL's `greaterThan`.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_GREATER_THAN, a, b, "compare")

    def greater_than_equal(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return one where `a >= b` and zero elsewhere, TSL's
        `greaterThanEqual`.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_GREATER_THAN_EQUAL, a, b, "compare")

    def equal(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return one where `a == b` and zero elsewhere, TSL's `equal`.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_EQUAL, a, b, "compare")

    def not_equal(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return one where `a != b` and zero elsewhere, TSL's `notEqual`.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_NOT_EQUAL, a, b, "compare")

    def logical_and(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return one where both are not zero, TSL's `and`.

        Args:
            a: The first condition.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_AND, a, b, "and")

    def logical_or(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return one where either is not zero, TSL's `or`.

        Args:
            a: The first condition.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_OR, a, b, "or")

    def logical_xor(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return one where exactly one is not zero, TSL's `xor`.

        Args:
            a: The first condition.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_XOR, a, b, "xor")

    def _ternary(
        mut self,
        kind: NodeKind,
        a: NodeRef,
        b: NodeRef,
        c: NodeRef,
        verb: String,
    ) raises -> NodeRef:
        """Append an operation of three operands of one type, or of vectors
        and `float`s.

        Raises:
            Error: If any is not a node of this graph, is not a `float` or a
                vector, or two are vectors of two sizes.
        """
        self._vector(a, verb)
        self._vector(b, verb)
        self._vector(c, verb)
        var type = self._widest(a, b)
        if self._types[c.value].value > type.value:
            type = self._types[c.value]
        var first = self._match(a, type, verb)
        var second = self._match(b, type, verb)
        var third = self._match(c, type, verb)
        return self._add(kind, type, first.value, second.value, third.value)

    def mix(mut self, a: NodeRef, b: NodeRef, t: NodeRef) raises -> NodeRef:
        """Return `a * (1 - t) + b * t`, TSL's and GLSL's `mix`.

        Args:
            a: What `t` of zero gives.
            b: What `t` of one gives.
            t: How far from `a` toward `b`.

        Returns:
            The node, of the widest type.

        Raises:
            Error: If any is not a node of this graph, or two are vectors of
                two sizes.
        """
        return self._ternary(NODE_MIX, a, b, t, "mix")

    def clamp(
        mut self, x: NodeRef, low: NodeRef, high: NodeRef
    ) raises -> NodeRef:
        """Return `min(max(x, low), high)`, TSL's `clamp`.

        Args:
            x: The value.
            low: The least it can be.
            high: The most it can be.

        Returns:
            The node, of the widest type.

        Raises:
            Error: If any is not a node of this graph, or two are vectors of
                two sizes.
        """
        return self._ternary(NODE_CLAMP, x, low, high, "clamp")

    def smoothstep(
        mut self, low: NodeRef, high: NodeRef, x: NodeRef
    ) raises -> NodeRef:
        """Return the smooth rise from zero at `low` to one at `high`, TSL's
        `smoothstep`, by `math.smoothstep.smoothstep`.

        Args:
            low: Where the rise starts.
            high: Where it ends.
            x: The value.

        Returns:
            The node, of the widest type.

        Raises:
            Error: If any is not a node of this graph, or two are vectors of
                two sizes.
        """
        return self._ternary(NODE_SMOOTHSTEP, low, high, x, "smoothstep")

    def select(
        mut self, condition: NodeRef, a: NodeRef, b: NodeRef
    ) raises -> NodeRef:
        """Return `a` where `condition` is not zero and `b` where it is,
        per component, TSL's `select` and GLSL's `?:`.

        Args:
            condition: The condition, a `float` or a vector.
            a: What a true condition gives.
            b: What a false condition gives.

        Returns:
            The node, of the widest type.

        Raises:
            Error: If any is not a node of this graph, or two are vectors of
                two sizes.
        """
        return self._ternary(NODE_SELECT, condition, a, b, "select")

    def _same(
        mut self, kind: NodeKind, a: NodeRef, b: NodeRef, verb: String
    ) raises -> NodeRef:
        """Append an operation of two vectors of one type that reads its
        width: its type is `a`'s.

        Raises:
            Error: If either is not a node of this graph, or their types
                differ.
        """
        self._vector(a, verb)
        self._vector(b, verb)
        var type = self._types[a.value]
        if self._types[b.value] != type:
            raise Error(
                "A node graph cannot "
                + verb
                + " a "
                + type.name()
                + " and a "
                + self._types[b.value].name()
            )
        return self._add(
            kind, type, a.value, b.value, value=Lanes(Float32(type.value))
        )

    def dot(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return the dot product of two vectors of one size, a `float`,
        TSL's `dot`.

        Args:
            a: The first vector.
            b: The second, of `a`'s type.

        Returns:
            The node.

        Raises:
            Error: If either is not a node of this graph, or their types
                differ.
        """
        var node = self._same(NODE_DOT, a, b, "dot")
        self._types[node.value] = NODE_FLOAT
        return node

    def distance(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return the distance between two points, a `float`, TSL's
        `distance`.

        Args:
            a: The first point.
            b: The second, of `a`'s type.

        Returns:
            The node.

        Raises:
            Error: If either is not a node of this graph, or their types
                differ.
        """
        var node = self._same(NODE_DISTANCE, a, b, "measure")
        self._types[node.value] = NODE_FLOAT
        return node

    def reflect(mut self, incident: NodeRef, normal: NodeRef) raises -> NodeRef:
        """Return `incident` reflected about `normal`, TSL's `reflect`:
        `I - 2 * dot(N, I) * N`. The normal must be a unit vector.

        Args:
            incident: The direction that arrives.
            normal: The unit normal, of `incident`'s type.

        Returns:
            The node, of `incident`'s type.

        Raises:
            Error: If either is not a node of this graph, or their types
                differ.
        """
        return self._same(NODE_REFLECT, incident, normal, "reflect")

    def cross(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return the cross product of two `vec3`s, TSL's `cross`.

        Args:
            a: The first vector.
            b: The second.

        Returns:
            The node, a `vec3`.

        Raises:
            Error: If either is not a `vec3` of this graph.
        """
        self._vector(a, "cross")
        self._vector(b, "cross")
        if (
            self._types[a.value] != NODE_VEC3
            or self._types[b.value] != NODE_VEC3
        ):
            raise Error(
                "A node graph crosses two vec3s, not a "
                + self._types[a.value].name()
                + " and a "
                + self._types[b.value].name()
            )
        return self._add(NODE_CROSS, NODE_VEC3, a.value, b.value)

    def refract(
        mut self, incident: NodeRef, normal: NodeRef, eta: NodeRef
    ) raises -> NodeRef:
        """Return `incident` bent through a surface, TSL's and GLSL's
        `refract`, or zero past the critical angle.

        Args:
            incident: The unit direction that arrives.
            normal: The unit normal, of `incident`'s type.
            eta: The ratio of the two indices of refraction, a `float`.

        Returns:
            The node, of `incident`'s type.

        Raises:
            Error: If any is not a node of this graph, the two vectors'
                types differ, or `eta` is not a `float`.
        """
        self._vector(eta, "refract")
        if self._types[eta.value] != NODE_FLOAT:
            raise Error(
                "A refraction's ratio is a float, not a "
                + self._types[eta.value].name()
            )
        var node = self._same(NODE_REFRACT, incident, normal, "refract")
        self._inputs[node.value * 3 + 2] = eta.value
        return node

    def faceforward(
        mut self, normal: NodeRef, incident: NodeRef, reference: NodeRef
    ) raises -> NodeRef:
        """Return `normal` if `dot(reference, incident) < 0` and minus
        `normal` otherwise, TSL's `faceForward`.

        Args:
            normal: The vector to orient.
            incident: The direction that arrives, of `normal`'s type.
            reference: The normal to test, of `normal`'s type.

        Returns:
            The node, of `normal`'s type.

        Raises:
            Error: If any is not a node of this graph, or their types
                differ.
        """
        self._vector(reference, "orient")
        var node = self._same(NODE_FACEFORWARD, normal, incident, "orient")
        if self._types[reference.value] != self._types[normal.value]:
            raise Error(
                "A node graph cannot orient a "
                + self._types[normal.value].name()
                + " by a "
                + self._types[reference.value].name()
            )
        self._inputs[node.value * 3 + 2] = reference.value
        return node

    def _unary(
        mut self, kind: NodeKind, a: NodeRef, scalar: Bool = False
    ) raises -> NodeRef:
        """Append an operation of one operand whose width it reads: of the
        operand's type, or a `float` when `scalar`.

        Raises:
            Error: If `a` is not a `float` or a vector of this graph.
        """
        self._vector(a, "compute with")
        var width = self._types[a.value]
        return self._add(
            kind,
            NODE_FLOAT if scalar else width,
            a.value,
            value=Lanes(Float32(width.value), 0, 0, 0),
        )

    def normalize(mut self, a: NodeRef) raises -> NodeRef:
        """Return `a` scaled to a length of one, TSL's `normalize`. A zero
        vector stays zero, where GLSL leaves it undefined.

        Args:
            a: The vector.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_NORMALIZE, a)

    def length(mut self, a: NodeRef) raises -> NodeRef:
        """Return the length of `a`, a `float`, TSL's `length`.

        Args:
            a: The vector.

        Returns:
            The node.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_LENGTH, a, scalar=True)

    def sin(mut self, a: NodeRef) raises -> NodeRef:
        """Return the sine of each component, in radians, TSL's `sin`.

        Args:
            a: The angle.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_SIN, a)

    def cos(mut self, a: NodeRef) raises -> NodeRef:
        """Return the cosine of each component, in radians, TSL's `cos`.

        Args:
            a: The angle.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_COS, a)

    def tan(mut self, a: NodeRef) raises -> NodeRef:
        """Return the tangent of each component, in radians, TSL's `tan`.

        Args:
            a: The angle.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_TAN, a)

    def asin(mut self, a: NodeRef) raises -> NodeRef:
        """Return the arc sine of each component, in radians, TSL's `asin`.

        Args:
            a: The sine, from minus one to one.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_ASIN, a)

    def acos(mut self, a: NodeRef) raises -> NodeRef:
        """Return the arc cosine of each component, in radians, TSL's
        `acos`.

        Args:
            a: The cosine, from minus one to one.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_ACOS, a)

    def atan(mut self, a: NodeRef) raises -> NodeRef:
        """Return the arc tangent of each component, in radians, TSL's
        `atan` of one value.

        Args:
            a: The tangent.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_ATAN, a)

    def fract(mut self, a: NodeRef) raises -> NodeRef:
        """Return each component less its floor, TSL's `fract`.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_FRACT, a)

    def abs(mut self, a: NodeRef) raises -> NodeRef:
        """Return each component's magnitude, TSL's `abs`.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_ABS, a)

    def sign(mut self, a: NodeRef) raises -> NodeRef:
        """Return minus one, zero or one per component by its sign, TSL's
        `sign`.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_SIGN, a)

    def floor(mut self, a: NodeRef) raises -> NodeRef:
        """Return the greatest whole number not above each component, TSL's
        `floor`.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_FLOOR, a)

    def ceil(mut self, a: NodeRef) raises -> NodeRef:
        """Return the least whole number not below each component, TSL's
        `ceil`.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_CEIL, a)

    def round(mut self, a: NodeRef) raises -> NodeRef:
        """Return the nearest whole number to each component, a half to the
        even one, TSL's `round`. GLSL lets a half go either way.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_ROUND, a)

    def trunc(mut self, a: NodeRef) raises -> NodeRef:
        """Return each component with its fraction dropped, toward zero,
        TSL's `trunc`.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_TRUNC, a)

    def exp(mut self, a: NodeRef) raises -> NodeRef:
        """Return e raised to each component, TSL's `exp`.

        Args:
            a: The exponent.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_EXP, a)

    def exp2(mut self, a: NodeRef) raises -> NodeRef:
        """Return two raised to each component, TSL's `exp2`.

        Args:
            a: The exponent.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_EXP2, a)

    def log(mut self, a: NodeRef) raises -> NodeRef:
        """Return the natural logarithm of each component, TSL's `log`.

        Args:
            a: The value, above zero.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_LOG, a)

    def log2(mut self, a: NodeRef) raises -> NodeRef:
        """Return the base-two logarithm of each component, TSL's `log2`.

        Args:
            a: The value, above zero.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_LOG2, a)

    def sqrt(mut self, a: NodeRef) raises -> NodeRef:
        """Return the square root of each component, TSL's `sqrt`.

        Args:
            a: The value, zero or more.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_SQRT, a)

    def inverse_sqrt(mut self, a: NodeRef) raises -> NodeRef:
        """Return one over the square root of each component, TSL's
        `inverseSqrt`.

        Args:
            a: The value, above zero.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_INVERSE_SQRT, a)

    def negate(mut self, a: NodeRef) raises -> NodeRef:
        """Return minus each component, TSL's `negate`.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_NEGATE, a)

    def one_minus(mut self, a: NodeRef) raises -> NodeRef:
        """Return one less each component, TSL's `oneMinus`.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_ONE_MINUS, a)

    def saturate(mut self, a: NodeRef) raises -> NodeRef:
        """Return each component clamped to zero to one, TSL's `saturate`.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_SATURATE, a)

    def reciprocal(mut self, a: NodeRef) raises -> NodeRef:
        """Return one over each component, TSL's `reciprocal`.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_RECIPROCAL, a)

    def radians(mut self, a: NodeRef) raises -> NodeRef:
        """Return each component, in degrees, turned to radians, TSL's
        `radians`.

        Args:
            a: The angle in degrees.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_RADIANS, a)

    def degrees(mut self, a: NodeRef) raises -> NodeRef:
        """Return each component, in radians, turned to degrees, TSL's
        `degrees`.

        Args:
            a: The angle in radians.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_DEGREES, a)

    def logical_not(mut self, a: NodeRef) raises -> NodeRef:
        """Return one where `a` is zero and zero elsewhere, TSL's `not`.

        Args:
            a: The condition.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._unary(NODE_NOT, a)

    def _derivative(mut self, kind: NodeKind, a: NodeRef) raises -> NodeRef:
        """Append a derivative of `a`.

        Raises:
            Error: If `a` is not a `float` or a vector of this graph.
        """
        self._vector(a, "differentiate")
        var type = self._types[a.value]
        return self._add(kind, type, a.value)

    def dfdx(mut self, a: NodeRef) raises -> NodeRef:
        """Return how much `a` changes one pixel to the right, TSL's
        `dFdx`: `a` there less `a` here, both from the triangle's plane.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._derivative(NODE_DFDX, a)

    def dfdy(mut self, a: NodeRef) raises -> NodeRef:
        """Return how much `a` changes one pixel up, TSL's `dFdy`: `a` there
        less `a` here. Up, as GLSL's window rows count upward.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        return self._derivative(NODE_DFDY, a)

    def fwidth(mut self, a: NodeRef) raises -> NodeRef:
        """Return `abs(dfdx(a)) + abs(dfdy(a))`, TSL's `fwidth`.

        Args:
            a: The value.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        var across = self.abs(self.dfdx(a))
        return self.add(across, self.abs(self.dfdy(a)))

    def remap(
        mut self,
        x: NodeRef,
        in_low: NodeRef,
        in_high: NodeRef,
        out_low: NodeRef,
        out_high: NodeRef,
    ) raises -> NodeRef:
        """Return `x` moved from one range to another, TSL's `remap`:
        `(x - inLow) / (inHigh - inLow) * (outHigh - outLow) + outLow`.

        Args:
            x: The value.
            in_low: Where the first range starts.
            in_high: Where it ends.
            out_low: Where the second range starts.
            out_high: Where it ends.

        Returns:
            The node, of the widest type.

        Raises:
            Error: If any is not a node of this graph, or two are vectors of
                two sizes.
        """
        var t = self.div(self.sub(x, in_low), self.sub(in_high, in_low))
        return self.add(self.mul(t, self.sub(out_high, out_low)), out_low)

    def swizzle(mut self, a: NodeRef, components: String) raises -> NodeRef:
        """Return components of `a` picked and reordered, as `v.zyx` or
        `v.rg` is in TSL.

        Args:
            a: The value.
            components: One to four of `xyzw`, or of `rgba`, each naming a
                component `a` has.

        Returns:
            The node, as wide as `components` is long.

        Raises:
            Error: If `a` is not a node of this graph, or `components` is
                empty, longer than four, or names a component `a` lacks.
        """
        self._vector(a, "swizzle")
        var letters = components.as_bytes()
        if len(letters) < 1 or len(letters) > 4:
            raise Error("A swizzle picks one to four components")
        var width = self._types[a.value].value
        var packed = 0
        var scale = 1
        for index in range(len(letters)):  # pragma: no branch
            var lane = _lane_of(letters[index])
            if lane < 0 or lane >= width:
                raise Error(
                    "A swizzle names a component a "
                    + self._types[a.value].name()
                    + " does not have: "
                    + components
                )
            packed += lane * scale
            scale *= 4
        return self._add(
            NODE_SWIZZLE,
            ValueType(len(letters)),
            a.value,
            value=Lanes(Float32(packed), 0, 0, 0),
        )

    def join(mut self, parts: List[NodeRef]) raises -> NodeRef:
        """Return the components of `parts` laid end to end, TSL's
        `vec3(a, b)` and `vec4(a, b)` of nodes.

        Args:
            parts: One to four `float`s and vectors whose widths add up to
                two, three or four, or a lone value.

        Returns:
            The node, as wide as the widths add up to.

        Raises:
            Error: If `parts` is empty, a part is not a `float` or a vector
                of this graph, or the widths add up to more than four.
        """
        if len(parts) == 0:
            raise Error("A join needs at least one part")
        var total = 0
        for index in range(len(parts)):  # pragma: no branch
            self._vector(parts[index], "join")
            total += self._types[parts[index].value].value
        if total > 4:
            raise Error(
                "A join makes at most four components, not " + String(total)
            )
        if len(parts) == 1:
            return parts[0]
        # A join reads three inputs, so four floats are two joins.
        var first = parts[0]
        var rest = 1
        if len(parts) == 4:
            first = self.join([parts[0], parts[1]])
            rest = 2
        var widths = self._types[first.value].value
        var b = parts[rest]
        var c = -1
        widths += self._types[b.value].value * 5
        if rest + 1 < len(parts):
            c = parts[rest + 1].value
            widths += self._types[c].value * 25
        return self._add(
            NODE_JOIN,
            ValueType(total),
            first.value,
            b.value,
            c,
            value=Lanes(Float32(widths), 0, 0, 0),
        )

    def perlin_noise(mut self, p: NodeRef) raises -> NodeRef:
        """Return MaterialX's Perlin noise at a point, a `float` from about
        minus one to one, three.js's `mx_perlin_noise_float`.

        Args:
            p: The point, a `vec2` or a `vec3`.

        Returns:
            The node.

        Raises:
            Error: If `p` is not a `vec2` or a `vec3` of this graph.
        """
        self._check(p)
        var type = self._types[p.value]
        if type != NODE_VEC2 and type != NODE_VEC3:
            raise Error(
                "Perlin noise reads a vec2 or a vec3, not a " + type.name()
            )
        return self._add(
            NODE_NOISE, NODE_FLOAT, p.value, value=Lanes(Float32(type.value))
        )

    def mx_noise_float(
        mut self, texcoord: NodeRef, amplitude: Float32 = 1, pivot: Float32 = 0
    ) raises -> NodeRef:
        """Return Perlin noise scaled and moved, three.js's
        `mx_noise_float(texcoord, amplitude, pivot)`.

        Args:
            texcoord: The point, a `vec2` or a `vec3`.
            amplitude: What the noise is multiplied by.
            pivot: What is added after.

        Returns:
            The node, a `float`.

        Raises:
            Error: If `texcoord` is not a `vec2` or a `vec3` of this graph.
        """
        var noise = self.perlin_noise(texcoord)
        return self.add(
            self.mul(noise, self.float(amplitude)), self.float(pivot)
        )

    def mx_fractal_noise_float(
        mut self,
        position: NodeRef,
        octaves: Int = 3,
        lacunarity: Float32 = 2,
        diminish: Float32 = 0.5,
        amplitude: Float32 = 1,
    ) raises -> NodeRef:
        """Return octaves of three-dimensional Perlin noise summed, three.js's
        `mx_fractal_noise_float`: each octave at `lacunarity` times the
        frequency and `diminish` times the amplitude of the last.

        Args:
            position: The point, a `vec3`, or a `vec2` with a zero added.
            octaves: How many octaves, a count the `Loop` unrolls.
            lacunarity: How much faster each octave is.
            diminish: How much weaker each octave is.
            amplitude: What the sum is multiplied by.

        Returns:
            The node, a `float`.

        Raises:
            Error: If `position` is not a `vec2` or a `vec3` of this graph,
                or `octaves` is outside what a `Loop` runs.
        """
        self._check(position)
        var type = self._types[position.value]
        if type != NODE_VEC2 and type != NODE_VEC3:
            raise Error(
                "Fractal noise reads a vec2 or a vec3, not a " + type.name()
            )
        var p = position
        if type == NODE_VEC2:
            p = self.join([position, self.float(0)])
        var result = self.Var(self.float(0))
        var weight = self.Var(self.float(1))
        var at = self.Var(p)
        _ = self.Loop(octaves)
        var octave = self.mul(self.get(weight), self.perlin_noise(self.get(at)))
        self.assign(result, self.add(self.get(result), octave))
        self.assign(weight, self.mul(self.get(weight), self.float(diminish)))
        self.assign(at, self.mul(self.get(at), self.float(lacunarity)))
        self.End()
        return self.mul(self.get(result), self.float(amplitude))

    # --- variables and control flow -------------------------------------------

    def Var(mut self, value: NodeRef) raises -> NodeVar:
        """Return a variable holding a value, TSL's `toVar()`: `assign`
        changes it and `get` reads what it holds where the builder is.

        Args:
            value: Its first value, a `float` or a vector.

        Returns:
            The variable.

        Raises:
            Error: If `value` is not a `float` or a vector of this graph.
        """
        self._vector(value, "hold")
        self._versions.append(value.value)
        self._var_types.append(self._types[value.value])
        return NodeVar(len(self._versions) - 1)

    def _check_var(self, v: NodeVar) raises:
        """Refuse a variable this graph does not hold.

        Raises:
            Error: If `v` is negative or past the last variable.
        """
        if v.value < 0 or v.value >= len(self._versions):
            raise Error("A node graph has no variable with that ref")

    def get(self, v: NodeVar) raises -> NodeRef:
        """Return the node a variable holds here, as reading a TSL `Var`.

        Args:
            v: The variable.

        Returns:
            Its value now.

        Raises:
            Error: If the graph has no such variable.
        """
        self._check_var(v)
        return NodeRef(self._versions[v.value])

    def assign(mut self, v: NodeVar, value: NodeRef) raises:
        """Make a variable hold a new value from here on, TSL's `assign`.

        Args:
            v: The variable.
            value: The value, of the variable's type, or a `float` for a
                vector variable.

        Raises:
            Error: If the graph has no such variable or node, or the value's
                type is another.
        """
        self._check_var(v)
        self._check(value)
        var type = self._var_types[v.value]
        var node = self._match(value, type, "assign")
        self._versions[v.value] = node.value

    def _condition(self, condition: NodeRef) raises:
        """Refuse a condition that is not a `float`.

        Raises:
            Error: If the node is not a `float` of this graph.
        """
        self._check(condition)
        if self._types[condition.value] != NODE_FLOAT:
            raise Error(
                "A condition is a float, not a "
                + self._types[condition.value].name()
            )

    def If(mut self, condition: NodeRef) raises:
        """Open a branch that runs where `condition` is not zero, TSL's
        `If`. `ElseIf`, `Else` and `End` follow.

        Args:
            condition: The condition, a `float`.

        Raises:
            Error: If `condition` is not a `float` of this graph.
        """
        self._condition(condition)
        self._blocks.append(
            _Block(
                _BLOCK_THEN,
                condition.value,
                -1,
                False,
                self._versions.copy(),
                List[Int](),
                0,
                0,
                0,
                -1,
                List[Int](),
            )
        )

    def Else(mut self) raises:
        """Start the branch of the open `If` that runs where its condition
        is zero, TSL's `Else`.

        Raises:
            Error: If the builder is not in the first branch of an `If`.
        """
        if (
            len(self._blocks) == 0
            or self._blocks[len(self._blocks) - 1].kind != _BLOCK_THEN
        ):
            raise Error("An Else needs an If to follow")
        var condition = NodeRef(self._blocks[len(self._blocks) - 1].condition)
        var negation = self.logical_not(condition)
        ref block = self._blocks[len(self._blocks) - 1]
        block.kind = _BLOCK_ELSE
        block.negation = negation.value
        block.then = self._versions.copy()
        var entry = block.entry.copy()
        for index in range(len(entry)):
            self._versions[index] = entry[index]

    def ElseIf(mut self, condition: NodeRef) raises:
        """Start a branch that runs where the open `If`'s condition is zero
        and `condition` is not, TSL's `ElseIf`. One `End` closes the chain.

        Args:
            condition: The condition, a `float`.

        Raises:
            Error: If the builder is not in the first branch of an `If`, or
                `condition` is not a `float` of this graph.
        """
        self._condition(condition)
        self.Else()
        self.If(condition)
        self._blocks[len(self._blocks) - 1].chained = True

    def Loop(
        mut self, count: Int, start: Float32 = 0, step: Float32 = 1
    ) raises -> NodeRef:
        """Open a loop that runs its body `count` times, TSL's `Loop` with a
        fixed count. `End` closes it and unrolls it.

        Args:
            count: How many times, from zero to `MAX_LOOP_COUNT`.
            start: The index of the first time.
            step: How much the index grows each time.

        Returns:
            The index, a `float`: `start`, then `start + step`, and so on.

        Raises:
            Error: If `count` is negative or past `MAX_LOOP_COUNT`.
        """
        if count < 0 or count > MAX_LOOP_COUNT:
            raise Error(
                "A Loop runs from zero to "
                + String(MAX_LOOP_COUNT)
                + " times, not "
                + String(count)
            )
        var entry = self._versions.copy()
        var index = self.float(start)
        var phis = List[Int]()
        for v in range(len(self._versions)):
            var type = self._var_types[v]
            var phi = self._add(NODE_COPY, type, self._versions[v])
            phis.append(phi.value)
            self._versions[v] = phi.value
        self._blocks.append(
            _Block(
                _BLOCK_LOOP,
                -1,
                -1,
                False,
                entry^,
                List[Int](),
                count,
                start,
                step,
                index.value,
                phis^,
            )
        )
        return index

    def _end_if(mut self) raises:
        """Close the innermost `If`: each variable a branch changed becomes
        a `select` of the two branches' values."""
        var block = self._blocks.pop()
        var first = block.then.copy() if block.kind == _BLOCK_ELSE else (
            self._versions.copy()
        )
        var second = self._versions.copy() if block.kind == _BLOCK_ELSE else (
            block.entry.copy()
        )
        for v in range(len(block.entry)):
            if first[v] != second[v]:
                var chosen = self.select(
                    NodeRef(block.condition),
                    NodeRef(first[v]),
                    NodeRef(second[v]),
                )
                self._versions[v] = chosen.value
        if block.chained:
            self._end_if()

    def _end_loop(mut self) raises:
        """Close the innermost `Loop`: its body is copied once for each time
        after the first, each copy reading the variables the last one left.
        """
        var block = self._blocks.pop()
        var first = block.body
        var past = self.count()
        var copies = block.count - 1
        if copies > 0 and past + (past - first) * copies > MAX_GRAPH_NODES:
            raise Error(
                "A Loop would grow the graph past "
                + String(MAX_GRAPH_NODES)
                + " nodes"
            )
        var ended = self._versions.copy()
        if block.count == 0:
            # The body never runs: every variable keeps what it held, and a
            # discard in the body throws nothing away.
            for v in range(len(block.entry)):
                self._versions[v] = block.entry[v]
            var kept = List[Int]()
            for index in range(len(self._discards)):
                if self._discards[index] < first:
                    kept.append(self._discards[index])
            self._discards = kept^
            return
        var previous = ended.copy()
        for time in range(1, block.count):
            # Where each body node's copy is; -1 for one not yet copied.
            var moved = List[Int](length=past - first, fill=-1)
            moved[0] = self.float(
                block.start + Float32(time) * block.step
            ).value
            for v in range(len(block.phis)):
                moved[block.phis[v] - first] = previous[v]
            for node in range(first + 1, past):
                if moved[node - first] >= 0:
                    continue
                var inputs = List[Int]()
                var changed = False
                for slot in range(3):  # pragma: no branch
                    var input = self._inputs[node * 3 + slot]
                    # A body node reads only nodes made before it, so no
                    # input is past the body.
                    if input >= first:
                        var to = moved[input - first]
                        changed = changed or to != input
                        input = to
                    inputs.append(input)
                if not changed:
                    moved[node - first] = node
                    continue
                var kind = self._kinds[node]
                var type = self._types[node]
                var name = self._names[node]
                var copy = self._add(
                    kind,
                    type,
                    inputs[0],
                    inputs[1],
                    inputs[2],
                    Lanes(
                        self._values[node * 4],
                        self._values[node * 4 + 1],
                        self._values[node * 4 + 2],
                        self._values[node * 4 + 3],
                    ),
                    name,
                )
                moved[node - first] = copy.value
                for index in range(len(self._discards)):
                    if self._discards[index] == node:
                        self._discards.append(copy.value)
                        break
            for v in range(len(previous)):
                var at = ended[v]
                previous[v] = (
                    moved[at - first] if at >= first and at < past else at
                )
        for v in range(len(previous)):
            self._versions[v] = previous[v]

    def End(mut self) raises:
        """Close the innermost `If` chain or `Loop`.

        Raises:
            Error: If no block is open.
        """
        if len(self._blocks) == 0:
            raise Error("An End needs an If or a Loop to close")
        if self._blocks[len(self._blocks) - 1].kind == _BLOCK_LOOP:
            self._end_loop()
        else:
            self._end_if()

    def _path(mut self) raises -> NodeRef:
        """Return the condition under which the builder's code runs: every
        open branch's condition, joined by `logical_and`, or one for none.
        """
        var path = NodeRef(-1)
        for index in range(len(self._blocks)):
            var kind = self._blocks[index].kind
            if kind == _BLOCK_LOOP:
                continue
            var condition = NodeRef(
                self._blocks[index].condition if kind
                == _BLOCK_THEN else self._blocks[index].negation
            )
            path = condition if path.value < 0 else self.logical_and(
                path, condition
            )
        return path if path.value >= 0 else self.float(1)

    def Discard(mut self) raises:
        """Throw the fragment away where the open branches run, TSL's
        `Discard`. Every discard joins the mask, so it acts before the alpha
        test, whichever output its branch belongs to.

        Raises:
            Error: If a node the path reads is not in this graph.
        """
        var keep = self.logical_not(self._path())
        self._discards.append(keep.value)

    def call(mut self, function: Fn, args: List[NodeRef]) raises -> NodeRef:
        """Build a function's nodes into this graph, TSL's `fn(a, b)`.

        Args:
            function: The function.
            args: One node per input, each of the input's type.

        Returns:
            The node the function returns.

        Raises:
            Error: If the arguments are not the layout's, or the function
                raises.
        """
        return function.call(self, args)

    # --- wiring -------------------------------------------------------------

    def _reaches(self, start: Int, goal: Int) -> Bool:
        """Return True if `goal` is `start` or among the nodes it reads."""
        var stack: List[Int] = [start]
        var seen = List[Bool](length=self.count(), fill=False)
        while len(stack) > 0:
            var node = stack.pop()
            if node == goal:
                return True
            if seen[node]:
                continue
            seen[node] = True
            for slot in range(3):  # pragma: no branch
                var input = self._inputs[node * 3 + slot]
                if input >= 0:
                    stack.append(input)
        return False

    def set_input(mut self, node: NodeRef, slot: Int, source: NodeRef) raises:
        """Make one input of a node read another node, as a node editor
        rewires one. The type every node sees stays what it was.

        Args:
            node: The node to rewire.
            slot: Which of its inputs: zero, one or two.
            source: The node it reads from now.

        Raises:
            Error: If either is not a node of this graph, the node has no
                input in that slot, `source`'s type is not the input's, or
                `source` reads `node`, which would make a cycle.
        """
        self._check(node)
        self._check(source)
        if slot < 0 or slot > 2 or self._inputs[node.value * 3 + slot] < 0:
            raise Error("That node has no input in that slot")
        var was = self._types[self._inputs[node.value * 3 + slot]]
        if self._types[source.value] != was:
            raise Error(
                "That input reads a "
                + was.name()
                + ", not a "
                + self._types[source.value].name()
            )
        if self._reaches(source.value, node.value):
            raise Error("That rewire would make a cycle")
        self._inputs[node.value * 3 + slot] = source.value

    def set_output(mut self, output: NodeOutput, node: NodeRef) raises:
        """Make a node feed one output, as three.js's `material.colorNode =`
        does.

        Args:
            output: Which output: one of the nine.
            node: The node, of the type the output takes: a `float` for the
                opacity, the mask, the ambient occlusion and the depth, and
                a `vec3` for the rest.

        Raises:
            Error: If the output is none of the nine, the node is not in
                this graph, or its type is not the output's.
        """
        if not output.is_valid():
            raise Error("A node output that is none of the nine")
        self._check(node)
        var wanted = output.value_type()
        if self._types[node.value] != wanted:
            raise Error(
                "That output takes a "
                + wanted.name()
                + ", not a "
                + self._types[node.value].name()
            )
        self._outputs[output.value] = node.value

    # --- compiling ----------------------------------------------------------

    def _order(self, root: Int) raises -> List[Int]:
        """Return every node `root` reads, each once, inputs first, ending
        with `root`.

        Raises:
            Error: If a node reads a node the graph does not hold, or the
                nodes make a cycle.
        """
        # 0 unseen, 1 on the path from the root, 2 done.
        var state = List[Int](length=self.count(), fill=0)
        var order = List[Int]()
        # A node, and how many of its inputs have been walked.
        var stack: List[Int] = [root, 0]
        state[root] = 1
        while len(stack) > 0:
            var slot = stack[len(stack) - 1]
            var node = stack[len(stack) - 2]
            if slot == 3:
                _ = stack.pop()
                _ = stack.pop()
                state[node] = 2
                order.append(node)
                continue
            stack[len(stack) - 1] = slot + 1
            var input = self._inputs[node * 3 + slot]
            if input < 0:
                continue
            if input >= self.count():
                raise Error("A node reads a node the graph does not hold")
            if state[input] == 1:
                raise Error("A node graph cannot hold a cycle")
            if state[input] == 2:
                continue
            state[input] = 1
            stack.append(input)
            stack.append(0)
        return order^

    def _check_stage(self, output: NodeOutput, kind: NodeKind) raises:
        """Refuse a node an output's stage cannot compute.

        Raises:
            Error: If a position node reads what only a fragment has, a
                fragment output reads what only a vertex has, or an output
                other than `OUTPUT_NODE` reads the lit color.
        """
        var local = kind == NODE_POSITION_LOCAL or kind == NODE_NORMAL_LOCAL
        if output == POSITION_NODE:
            var fragment = (
                (_is_attribute(kind) and not local)
                or kind == NODE_TEXTURE
                or kind == NODE_VARYING
                or kind == NODE_DFDX
                or kind == NODE_DFDY
            )
            if fragment:
                raise Error(
                    "A position node runs once per vertex: it reads only"
                    " constants, uniforms, time, math and the local position"
                    " and normal"
                )
            return
        if local:
            raise Error(
                "Only a position node reads the local position or normal:"
                " a fragment has the world and view ones"
            )
        if kind == NODE_LIT and output != OUTPUT_NODE:
            raise Error(
                "Only an output node reads the lit color: the lights have"
                " not run before the others"
            )

    def compile(self) raises -> NodeProgram:
        """Return the graph's outputs as a program both rasterizers run.

        Each output's nodes are laid out inputs first, one instruction each,
        and a node two outputs share is computed by both. A derivative lays
        out its argument again for the pixel beside, and a varying lays out
        its argument for each corner. Every uniform, and every constant an
        instruction reads, is stored once after the instructions, so
        `NodeProgram.set_uniform` changes it everywhere.

        Returns:
            The program, at time zero under an identity view.

        Raises:
            Error: If an `If` or a `Loop` is still open, no output is set
                and no `Discard` was made, a node reads one the graph does
                not hold, the nodes make a cycle, an output reads what its
                stage does not have (see `set_output`), a varying or a
                derivative reads what it cannot, or an output needs more
                than `MAX_INSTRUCTIONS` instructions or `MAX_REGISTERS`
                values at once.
        """
        if len(self._blocks) > 0:
            raise Error(
                "A node graph has an If or a Loop that End never closed"
            )
        var work = self.copy()
        # The mask, with every discard joined to it.
        var mask = work._outputs[MASK_NODE.value]
        for index in range(len(work._discards)):
            var keep = work._discards[index]
            mask = (
                keep if mask
                < 0 else work._add(NODE_AND, NODE_FLOAT, mask, keep).value
            )
        work._outputs[MASK_NODE.value] = mask
        # The zero a derivative of what does not vary is.
        var zero = work._add(NODE_CONSTANT, NODE_VEC4).value
        var layouts = List[_Layout]()
        var total = 0
        var pool = _Pool(work)
        for output in range(NODE_OUTPUT_COUNT):  # pragma: no branch
            var root = work._outputs[output]
            if root < 0:
                layouts.append(_Layout())
                continue
            if root >= work.count():
                raise Error("An output names a node the graph does not hold")
            var order = work._order(root)
            for index in range(len(order)):  # pragma: no branch
                var node = order[index]
                # The two are open fields, so an edited graph can hold a
                # kind no instruction means or a type no value has.
                if (
                    not work._kinds[node].is_valid()
                    or not work._types[node].is_valid()
                ):
                    raise Error("A node holds a kind or a type there is not")
                work._check_stage(NodeOutput(output), work._kinds[node])
            var layout = _lay_out(work, order, root, zero, pool)
            total += len(layout.ops)
            layouts.append(layout^)
        if total == 0:
            raise Error("A node graph needs at least one output")
        var program = NodeProgram()
        var base = PROGRAM_HEADER + total * INSTRUCTION_FLOATS
        var at = PROGRAM_HEADER
        for output in range(NODE_OUTPUT_COUNT):  # pragma: no branch
            ref layout = layouts[output]
            program.code[output * 2] = Float32(at)
            program.code[output * 2 + 1] = Float32(len(layout.ops))
            for index in range(len(layout.ops)):
                program.code.append(Float32(layout.ops[index]))
                program.code.append(Float32(layout.a[index]))
                program.code.append(Float32(layout.b[index]))
                program.code.append(Float32(layout.c[index]))
                var immediate = layout.immediates[index]
                var pooled = layout.pooled[index]
                if pooled >= 0:
                    immediate += Float32((base + pooled) * layout.scale[index])
                program.code.append(immediate)
                program.code.append(Float32(layout.dest[index]))
                at += INSTRUCTION_FLOATS
        program.code.extend(pool.values.copy())
        for index in range(len(pool.names)):
            program.uniform_names.append(pool.names[index])
            program.uniform_offsets.append(base + pool.offsets[index])
            program.uniform_types.append(pool.types[index])
        for index in range(len(pool.textures)):
            program.texture_offsets.append(base + pool.textures[index])
        program._list_textures()
        return program^


struct _Pool(Movable):
    """The floats after a program's instructions: every uniform, in the
    order the graph made them, then each constant and texture an
    instruction reads, once."""

    var values: List[Float32]
    # Where each node's floats start, from the pool's first float, or -1.
    var at: List[Int]
    var names: List[String]
    var offsets: List[Int]
    var types: List[ValueType]
    # Where each texture an instruction reads keeps its id.
    var textures: List[Int]

    def __init__(out self, graph: NodeGraph):
        """Lay out every uniform of a graph."""
        self.values = List[Float32]()
        self.at = List[Int](length=graph.count(), fill=-1)
        self.names = List[String]()
        self.offsets = List[Int]()
        self.types = List[ValueType]()
        self.textures = List[Int]()
        # Never empty: `compile` adds the zero a derivative can need.
        for node in range(graph.count()):  # pragma: no branch
            if graph._kinds[node] == NODE_UNIFORM:
                var type = graph._types[node]
                var place = self.place(graph, node)
                self.names.append(graph._names[node])
                self.offsets.append(place)
                self.types.append(type)

    def place(mut self, graph: NodeGraph, node: Int) -> Int:
        """Return where a constant's or a uniform's floats are, laying them
        out the first time."""
        if self.at[node] >= 0:
            return self.at[node]
        var type = graph._types[node]
        self.at[node] = len(self.values)
        if type == NODE_MAT3 or type == NODE_MAT4:
            var first = Int(graph._values[node * 4])
            for index in range(_pool_size(type)):  # pragma: no branch
                self.values.append(graph._matrices[first + index])
        else:
            for lane in range(4):  # pragma: no branch
                self.values.append(graph._values[node * 4 + lane])
        return self.at[node]

    def texture(mut self, graph: NodeGraph, node: Int) -> Int:
        """Return where a texture node's texture id is: its uniform's, or a
        place of its own for the id it names."""
        var sampler = graph._inputs[node * 3 + 1]
        var place = len(self.values)
        if sampler >= 0:
            place = self.place(graph, sampler)
        else:
            for lane in range(4):  # pragma: no branch
                self.values.append(graph._values[node * 4 + lane])
        for index in range(len(self.textures)):
            if self.textures[index] == place:
                return place
        self.textures.append(place)
        return place


struct _Layout(Movable):
    """One output's instructions, before the pool's place is known."""

    var ops: List[Int]
    var a: List[Int]
    var b: List[Int]
    var c: List[Int]
    var immediates: List[Float32]
    # The pool float an immediate points at, or -1, and what that offset is
    # multiplied by before it is added: eight for a matrix, else one.
    var pooled: List[Int]
    var scale: List[Int]
    var dest: List[Int]

    def __init__(out self):
        """Create an empty layout."""
        self.ops = List[Int]()
        self.a = List[Int]()
        self.b = List[Int]()
        self.c = List[Int]()
        self.immediates = List[Float32]()
        self.pooled = List[Int]()
        self.scale = List[Int]()
        self.dest = List[Int]()


def _dependence(
    graph: NodeGraph,
    order: List[Int],
    mut varies: List[Bool],
    mut bent: List[Bool],
):
    """Mark which nodes read the surface (`varies`), and which read the
    fragment's normal (`bent`), from their inputs, in `order`."""
    for index in range(len(order)):  # pragma: no branch
        var node = order[index]
        var kind = graph._kinds[node]
        var reads = _is_attribute(kind)
        var normal = kind == NODE_NORMAL_WORLD or kind == NODE_NORMAL_VIEW
        for slot in range(3):  # pragma: no branch
            var input = graph._inputs[node * 3 + slot]
            if input >= 0:
                reads = reads or varies[input]
                normal = normal or bent[input]
        varies[node] = reads
        # A varying reads its corners and a derivative reads the fragment's
        # own interpolated normal, so neither reads the fragment's normal.
        bent[node] = normal and not (
            kind == NODE_VARYING or kind == NODE_DFDX or kind == NODE_DFDY
        )


def _canonical(
    graph: NodeGraph,
    node: Int,
    context: Int,
    varies: List[Bool],
    bent: List[Bool],
    zero: Int,
) -> Int:
    """Return the node and context whose instruction computes `node` in
    `context`, as `node * NODE_CONTEXT_COUNT + context`: through a copy, a
    varying at a corner, a derivative of what does not vary, and to the
    fragment's own context for what reads no attribute there."""
    var at = node
    var seat = context
    while True:
        var kind = graph._kinds[at]
        if kind == NODE_COPY or (
            kind == NODE_VARYING and seat >= CORNER_A.value
        ):
            at = graph._inputs[at * 3]
            continue
        break
    var kind = graph._kinds[at]
    if not varies[at]:
        if kind == NODE_DFDX or kind == NODE_DFDY:
            at = zero
        seat = AT_FRAGMENT.value
    elif seat == AT_HERE.value and not bent[at]:
        seat = AT_FRAGMENT.value
    return at * NODE_CONTEXT_COUNT + seat


def _lay_out(
    graph: NodeGraph, order: List[Int], root: Int, zero: Int, mut pool: _Pool
) raises -> _Layout:
    """Return one output's instructions, each node in each context it is
    needed in once, inputs first, with registers given back as soon as the
    last reader of a value has run.

    Raises:
        Error: If a varying or a derivative reads what it cannot, or the
            output needs more than `MAX_INSTRUCTIONS` instructions or
            `MAX_REGISTERS` values at once.
    """
    var varies = List[Bool](length=graph.count(), fill=False)
    var bent = List[Bool](length=graph.count(), fill=False)
    _dependence(graph, order, varies, bent)
    var layout = _Layout()
    # The instruction of each node in each context, or -1.
    var made = List[Int](length=graph.count() * NODE_CONTEXT_COUNT, fill=-1)
    # Each instruction's operand instructions, or -1.
    var reads = List[Int]()
    var start = _canonical(graph, root, AT_FRAGMENT.value, varies, bent, zero)
    var stack: List[Int] = [start, 0]
    while len(stack) > 0:
        var key = stack[len(stack) - 2]
        var phase = stack[len(stack) - 1]
        if made[key] >= 0:
            _ = stack.pop()
            _ = stack.pop()
            continue
        var node = key // NODE_CONTEXT_COUNT
        var context = key % NODE_CONTEXT_COUNT
        var children = _children(graph, node, context, varies, bent, zero)
        if phase == 0:
            stack[len(stack) - 1] = 1
            # Always three: a child is -1 where the node has none.
            for index in range(len(children) - 1, -1, -1):  # pragma: no branch
                if children[index] >= 0 and made[children[index]] < 0:
                    stack.append(children[index])
                    stack.append(0)
            continue
        _ = stack.pop()
        _ = stack.pop()
        _emit(graph, node, context, children, made, reads, layout, pool)
        made[key] = len(layout.ops) - 1
    if len(layout.ops) > MAX_INSTRUCTIONS:
        raise Error(
            "A node output needs at most "
            + String(MAX_INSTRUCTIONS)
            + " instructions"
        )
    _allocate(reads, layout)
    return layout^


def _children(
    graph: NodeGraph,
    node: Int,
    context: Int,
    varies: List[Bool],
    bent: List[Bool],
    zero: Int,
) raises -> List[Int]:
    """Return the three operands a node needs in a context, each a node
    and a context, or -1 for none.

    Raises:
        Error: If the node reads, in that context, what the context does
            not have.
    """
    var kind = graph._kinds[node]
    var corner = context >= CORNER_A.value
    var beside = context == AT_RIGHT.value or context == AT_UP.value
    if kind == NODE_LIT and context != AT_FRAGMENT.value:
        raise Error(
            "A varying or a derivative cannot read the lit color: only"
            " the fragment has it"
        )
    if corner and (
        kind == NODE_TEXTURE or kind == NODE_DFDX or kind == NODE_DFDY
    ):
        raise Error(
            "A varying runs once per corner: it reads no texture and no"
            " derivative"
        )
    if (beside or context == AT_HERE.value) and (
        kind == NODE_DFDX or kind == NODE_DFDY
    ):
        raise Error("A derivative cannot read another derivative")
    var result = List[Int](length=3, fill=-1)
    if kind == NODE_VARYING:
        var value = graph._inputs[node * 3]
        result[0] = _canonical(graph, value, CORNER_A.value, varies, bent, zero)
        result[1] = _canonical(graph, value, CORNER_B.value, varies, bent, zero)
        result[2] = _canonical(graph, value, CORNER_C.value, varies, bent, zero)
        return result^
    if kind == NODE_DFDX or kind == NODE_DFDY:
        var value = graph._inputs[node * 3]
        var there = AT_RIGHT.value if kind == NODE_DFDX else AT_UP.value
        result[0] = _canonical(graph, value, there, varies, bent, zero)
        result[1] = _canonical(graph, value, AT_HERE.value, varies, bent, zero)
        return result^
    for slot in range(3):  # pragma: no branch
        var input = graph._inputs[node * 3 + slot]
        if input >= 0 and graph._types[input].is_vector():
            result[slot] = _canonical(graph, input, context, varies, bent, zero)
    return result^


def _emit(
    graph: NodeGraph,
    node: Int,
    context: Int,
    children: List[Int],
    made: List[Int],
    mut reads: List[Int],
    mut layout: _Layout,
    mut pool: _Pool,
):
    """Append the instruction that computes a node in a context, its
    operands already laid out."""
    var kind = graph._kinds[node]
    var op = kind.value
    var immediate = graph._values[node * 4]
    var pooled = -1
    var scale = 1
    if kind == NODE_CONSTANT or kind == NODE_UNIFORM:
        pooled = pool.place(graph, node)
        immediate = 0
    elif kind == NODE_TEXTURE:
        pooled = pool.texture(graph, node)
        immediate = 0
    elif kind == NODE_VARYING:
        op = NODE_INTERPOLATE.value
        immediate = Float32(context)
    elif kind == NODE_DFDX or kind == NODE_DFDY:
        op = NODE_SUB.value
    elif kind == NODE_MATRIX_VECTOR or kind == NODE_VECTOR_MATRIX:
        var matrix = graph._inputs[node * 3 + 1]
        var size = graph._types[node].value
        scale = 8
        immediate = Float32(size)
        if graph._kinds[matrix] == NODE_VIEW_MATRIX:
            immediate += Float32(PROGRAM_VIEW * 8)
        else:
            pooled = pool.place(graph, matrix)
    var operands = List[Int](length=3, fill=-1)
    for slot in range(3):  # pragma: no branch
        if children[slot] >= 0:
            operands[slot] = made[children[slot]]
        reads.append(operands[slot])
    layout.ops.append(op)
    layout.a.append(0)
    layout.b.append(0)
    # A node that reads the surface keeps its context where its third
    # operand would be.
    layout.c.append(context if _is_attribute(kind) else 0)
    layout.immediates.append(immediate)
    layout.pooled.append(pooled)
    layout.scale.append(scale)
    layout.dest.append(0)


def _allocate(reads: List[Int], mut layout: _Layout) raises:
    """Give each instruction a register, reusing one once the last reader of
    its value has run.

    Raises:
        Error: If more than `MAX_REGISTERS` values are alive at once.
    """
    var count = len(layout.ops)
    var last = List[Int](length=count, fill=-1)
    # Never empty: an output holds at least the node that feeds it.
    for index in range(count):  # pragma: no branch
        for slot in range(3):  # pragma: no branch
            var operand = reads[index * 3 + slot]
            if operand >= 0:
                last[operand] = index
    # The last instruction is the output: it lives to the end.
    last[count - 1] = count
    var free = List[Bool](length=MAX_REGISTERS, fill=True)
    for index in range(count):  # pragma: no branch
        for slot in range(3):  # pragma: no branch
            var operand = reads[index * 3 + slot]
            if operand >= 0 and last[operand] == index:
                free[layout.dest[operand]] = True
        var register = -1
        for candidate in range(MAX_REGISTERS):  # pragma: no branch
            if free[candidate]:
                register = candidate
                break
        if register < 0:
            raise Error(
                "A node output needs more than "
                + String(MAX_REGISTERS)
                + " values alive at once"
            )
        free[register] = False
        layout.dest[index] = register
        for slot in range(3):  # pragma: no branch
            var operand = reads[index * 3 + slot]
            if operand >= 0:
                var written = layout.dest[operand]
                if slot == 0:
                    layout.a[index] = written
                elif slot == 1:
                    layout.b[index] = written
                else:
                    layout.c[index] = written


struct NodeProgram(Copyable, Movable):
    """A compiled `NodeGraph`: the bytecode both rasterizers interpret, and
    where its uniforms are in it.

    `code` is laid out as `PROGRAM_HEADER` floats -- each output's first
    instruction and its count, the time, the view -- then the instructions,
    `INSTRUCTION_FLOATS` each, then every uniform and each constant an
    instruction reads: four floats a value, nine a `mat3`, sixteen a
    `mat4`, and a texture's id in the first of four.
    """

    var code: List[Float32]
    var uniform_names: List[String]
    var uniform_offsets: List[Int]
    var uniform_types: List[ValueType]
    # Every texture a texture node reads, so a renderer can check and upload
    # them before a fragment asks, and where each id is in `code`.
    var textures: List[TextureId]
    var texture_offsets: List[Int]

    def __init__(out self):
        """Create a program with no outputs, at time zero under an identity
        view. `NodeGraph.compile` fills one."""
        self.code = List[Float32](length=PROGRAM_HEADER, fill=0)
        self.code[PROGRAM_VIEW] = 1
        self.code[PROGRAM_VIEW + 5] = 1
        self.code[PROGRAM_VIEW + 10] = 1
        self.code[PROGRAM_VIEW + 15] = 1
        self.uniform_names = List[String]()
        self.uniform_offsets = List[Int]()
        self.uniform_types = List[ValueType]()
        self.textures = List[TextureId]()
        self.texture_offsets = List[Int]()

    def _list_textures(mut self):
        """List every texture the texture nodes read now, each once."""
        self.textures = List[TextureId]()
        for index in range(len(self.texture_offsets)):
            _note_texture(
                self.textures,
                TextureId(Int(self.code[self.texture_offsets[index]])),
            )

    def has(self, output: NodeOutput) raises -> Bool:
        """Return True if the program sets an output.

        Args:
            output: One of the nine outputs.

        Returns:
            Whether a graph node feeds it.

        Raises:
            Error: If the output is none of the nine.
        """
        if not output.is_valid():
            raise Error("A node output that is none of the nine")
        return self.code[output.value * 2 + 1] > 0

    def _find(self, name: String, type: ValueType) raises -> Int:
        """Return where a uniform's floats are.

        Raises:
            Error: If no uniform has that name, or its type is not `type`.
        """
        for index in range(len(self.uniform_names)):
            if self.uniform_names[index] == name:
                if self.uniform_types[index] != type:
                    raise Error(
                        "The uniform "
                        + name
                        + " is a "
                        + self.uniform_types[index].name()
                        + ", not a "
                        + type.name()
                    )
                return self.uniform_offsets[index]
        raise Error("A node program has no uniform named " + name)

    def _set(mut self, name: String, type: ValueType, value: Lanes) raises:
        """Write a uniform's four floats.

        Raises:
            Error: If no uniform has that name, or its type is not `type`.
        """
        var at = self._find(name, type)
        for lane in range(4):  # pragma: no branch
            self.code[at + lane] = value[lane]

    def set_uniform(mut self, name: String, value: Float32) raises:
        """Change a `float` uniform, as three.js's `uniform.value =` does.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `float`.
        """
        self._set(name, NODE_FLOAT, Lanes(value, 0, 0, 0))

    def set_uniform(mut self, name: String, value: Vector2) raises:
        """Change a `vec2` uniform.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `vec2`.
        """
        self._set(name, NODE_VEC2, Lanes(value.x, value.y, 0, 0))

    def set_uniform(mut self, name: String, value: Vector3) raises:
        """Change a `vec3` uniform.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `vec3`.
        """
        self._set(name, NODE_VEC3, Lanes(value.x, value.y, value.z, 0))

    def set_uniform(mut self, name: String, value: Vector4) raises:
        """Change a `vec4` uniform.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `vec4`.
        """
        self._set(name, NODE_VEC4, Lanes(value.x, value.y, value.z, value.w))

    def set_uniform(mut self, name: String, value: Color) raises:
        """Change a `vec3` uniform to a color, decoded to linear.

        Args:
            name: The uniform's name.
            value: Its new value, as authored in sRGB.

        Raises:
            Error: If no uniform has that name, or it is not a `vec3`.
        """
        var linear = FloatColor(srgb=value)
        self._set(name, NODE_VEC3, Lanes(linear.r, linear.g, linear.b, 0))

    def set_uniform(mut self, name: String, value: Matrix3) raises:
        """Change a `mat3` uniform.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `mat3`.
        """
        var at = self._find(name, NODE_MAT3)
        for index in range(9):  # pragma: no branch
            self.code[at + index] = value.elements[index]

    def set_uniform(mut self, name: String, value: Matrix4) raises:
        """Change a `mat4` uniform.

        Args:
            name: The uniform's name.
            value: Its new value.

        Raises:
            Error: If no uniform has that name, or it is not a `mat4`.
        """
        var at = self._find(name, NODE_MAT4)
        for index in range(16):  # pragma: no branch
            self.code[at + index] = value.elements[index]

    def set_texture(mut self, name: String, map: TextureId) raises:
        """Change a texture uniform, as three.js's `textureNode.value =`
        does, and list the textures the program reads again.

        Args:
            name: The uniform's name.
            map: The texture. It must be in the store the renderer draws
                with.

        Raises:
            Error: If `map` is negative, no uniform has that name, or it is
                not a texture.
        """
        if map.value < 0:
            raise Error("A texture uniform needs a texture")
        var at = self._find(name, NODE_SAMPLER)
        self.code[at] = Float32(map.value)
        self._list_textures()

    def uniform(self, name: String) raises -> Lanes:
        """Return a uniform's value, in as many lanes as its type has and
        zero past them: a matrix's first four floats, a texture's id.

        Args:
            name: The uniform's name.

        Returns:
            The value.

        Raises:
            Error: If no uniform has that name.
        """
        for index in range(len(self.uniform_names)):
            if self.uniform_names[index] == name:
                var at = self.uniform_offsets[index]
                return Lanes(
                    self.code[at],
                    self.code[at + 1],
                    self.code[at + 2],
                    self.code[at + 3],
                )
        raise Error("A node program has no uniform named " + name)

    def set_frame(mut self, time: Duration, view: Matrix4):
        """Write the frame's time and view, what the `time`, view position
        and view normal nodes read. The renderer does this every frame.

        Args:
            time: The time since the animation began.
            view: The world-to-camera matrix.
        """
        self.code[PROGRAM_TIME] = time.to(SECOND)
        for index in range(16):  # pragma: no branch
            self.code[PROGRAM_VIEW + index] = view.elements[index]


struct NodeProgramStore(Copyable, Movable):
    """Owns node programs and hands out ids naming them, as `TextureStore`
    owns textures: a `Material` names its program by id."""

    var programs: List[NodeProgram]

    def __init__(out self):
        """Create an empty store."""
        self.programs = List[NodeProgram]()

    def count(self) -> Int:
        """Return how many programs the store holds.

        Returns:
            The count.
        """
        return len(self.programs)

    def add(mut self, var program: NodeProgram) -> NodeProgramId:
        """Take ownership of a program and return the id naming it.

        Args:
            program: The program, moved in.

        Returns:
            Its id, valid for the life of the store.
        """
        self.programs.append(program^)
        return NodeProgramId(len(self.programs) - 1)

    def get(
        ref self, id: NodeProgramId
    ) raises -> ref[origin_of(self.programs[0])] NodeProgram:
        """Return the program with that id, borrowed: mutable through a
        mutable store, so `store.get(id).set_uniform(...)` changes it.

        Args:
            id: Which program.

        Returns:
            A reference to it.

        Raises:
            Error: If no program has that id.
        """
        if id.value < 0 or id.value >= len(self.programs):
            raise Error("No node program has that id")
        return self.programs[id.value]

    def set_frame(mut self, time: Duration, view: Matrix4):
        """Write the frame's time and view into every program.

        Args:
            time: The time since the animation began.
            view: The world-to-camera matrix.
        """
        for index in range(len(self.programs)):
            self.programs[index].set_frame(time, view)


# --- the interpreter ----------------------------------------------------------


@fieldwise_init
struct NodeInputs(ImplicitlyCopyable):
    """What a fragment, a vertex or a corner hands a program: its attributes
    and, for an output node, the lit color."""

    # The texture coordinate.
    var u: Float32
    var v: Float32
    # The world-space position and unit normal of a fragment or a corner,
    # or the local position and normal of a vertex.
    var position: Vector3
    var normal: Vector3
    # The interpolated corner color, linear.
    var color: Vector3
    # What the standard lighting made of the fragment, linear.
    var lit: Vector3
    # Whether texture nodes read their textures: only under the mode that
    # opens them. Otherwise they read opaque white.
    var textured: Bool


trait NodeSource:
    """Where a program's floats are read, its textures sampled and its
    triangle's attributes found: the host's list and store, or the kernel's
    buffers. `run_nodes` asks these four things and nothing else, so both
    backends run the one function."""

    def word(self, at: Int) -> Float32:
        """Return one float of the program.

        Args:
            at: Its offset from the program's first float.

        Returns:
            The float.
        """
        ...

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return a texture read at a coordinate, as the material's own map
        is read, at the level the surface's coordinates pick.

        Args:
            slot: The texture's id.
            u: Across.
            v: Up.

        Returns:
            The linear color, straight alpha.
        """
        ...

    def shares(self, context: NodeContext) -> Lanes:
        """Return the perspective-correct weight of each corner at the
        fragment, the pixel to its right, or the pixel above it: what
        `perspective_shares` makes of the triangle's plane there.

        Args:
            context: `AT_FRAGMENT` or `AT_HERE` for the fragment itself,
                `AT_RIGHT` or `AT_UP` for the pixel beside it.

        Returns:
            The three weights, in the first three lanes.
        """
        ...

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return one corner's attributes, as the triangle carries them.

        Args:
            context: `CORNER_A`, `CORNER_B` or `CORNER_C`.

        Returns:
            The corner's coordinates, world position and normal and color.
        """
        ...


def perspective_shares(
    wa: Float32,
    wb: Float32,
    wc: Float32,
    ia: Float32,
    ib: Float32,
    ic: Float32,
) -> Lanes:
    """Return each corner's perspective-correct weight at a sample: the
    screen weights times each corner's `1 / w`, over their sum. Both
    backends' `NodeSource.shares` call it.

    Args:
        wa: The first corner's screen-space weight.
        wb: The second's.
        wc: The third's.
        ia: The first corner's `1 / w`.
        ib: The second's.
        ic: The third's.

    Returns:
        The three weights, in the first three lanes, or the screen weights
        where the interpolated `1 / w` is zero.
    """
    var inv_w = wa * ia + wb * ib + wc * ic
    if inv_w == 0:
        return Lanes(wa, wb, wc, 0)
    var rcp = Float32(1) / inv_w
    return Lanes(wa * ia * rcp, wb * ib * rcp, wc * ic * rcp, 0)


struct ProgramSource[origin: Origin[mut=False]](NodeSource):
    """The host's `NodeSource` for a program on its own, with no triangle:
    what the vertex stage runs a position node with, since a position node
    reads no texture, no varying and no derivative."""

    var program: Pointer[NodeProgram, Self.origin]

    def __init__(out self, program: Pointer[NodeProgram, Self.origin]):
        """Borrow a program for as long as the caller keeps it.

        Args:
            program: The program to read.
        """
        self.program = program

    def word(self, at: Int) -> Float32:
        """Return one float of the program.

        Args:
            at: Its offset.

        Returns:
            The float.
        """
        return self.program[].code[at]

    def sample(self, slot: Int, u: Float32, v: Float32) -> FloatColor:
        """Return opaque white: there is no surface to read a texture on.

        Args:
            slot: The texture's id, not read.
            u: Across, not read.
            v: Up, not read.

        Returns:
            Opaque white.
        """
        return FloatColor(1.0, 1.0, 1.0, 1.0)

    def shares(self, context: NodeContext) -> Lanes:
        """Return all the weight on the first corner: there is no triangle.

        Args:
            context: Which sample, not read.

        Returns:
            One, then zeros.
        """
        return Lanes(1, 0, 0, 0)

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return a corner of nothing: every attribute zero.

        Args:
            context: Which corner, not read.

        Returns:
            Zeros.
        """
        var none = Vector3(0, 0, 0)
        return NodeInputs(0, 0, none, none, none, none, False)


def _lanes(v: Vector3) -> Lanes:
    """Return a vector in the first three lanes."""
    return Lanes(v.x, v.y, v.z, 0)


def _unit(v: Vector3) -> Vector3:
    """Return a vector at a length of one, or zero for a zero vector."""
    var size = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    return Vector3(v.x / size, v.y / size, v.z / size) if size != 0 else v


def node_attributes[
    S: NodeSource
](source: S, context: NodeContext, textured: Bool) -> NodeInputs:
    """Return the attributes a node reads in a context other than the
    fragment's own: a corner's, or the triangle's plane interpolated at the
    fragment or the pixel beside it, the normal made unit length.

    Args:
        source: The program's triangle.
        context: Any context but `AT_FRAGMENT`.
        textured: Whether texture nodes read their textures.

    Returns:
        The attributes, with no lit color.
    """
    var none = Vector3(0, 0, 0)
    if context.is_corner():
        var at = source.corner(context)
        return NodeInputs(
            at.u, at.v, at.position, _unit(at.normal), at.color, none, textured
        )
    var s = source.shares(context)
    var a = source.corner(CORNER_A)
    var b = source.corner(CORNER_B)
    var c = source.corner(CORNER_C)
    return NodeInputs(
        a.u * s[0] + b.u * s[1] + c.u * s[2],
        a.v * s[0] + b.v * s[1] + c.v * s[2],
        Vector3(
            a.position.x * s[0] + b.position.x * s[1] + c.position.x * s[2],
            a.position.y * s[0] + b.position.y * s[1] + c.position.y * s[2],
            a.position.z * s[0] + b.position.z * s[1] + c.position.z * s[2],
        ),
        _unit(
            Vector3(
                a.normal.x * s[0] + b.normal.x * s[1] + c.normal.x * s[2],
                a.normal.y * s[0] + b.normal.y * s[1] + c.normal.y * s[2],
                a.normal.z * s[0] + b.normal.z * s[1] + c.normal.z * s[2],
            )
        ),
        Vector3(
            a.color.x * s[0] + b.color.x * s[1] + c.color.x * s[2],
            a.color.y * s[0] + b.color.y * s[1] + c.color.y * s[2],
            a.color.z * s[0] + b.color.z * s[1] + c.color.z * s[2],
        ),
        none,
        textured,
    )


def _dot(x: Lanes, y: Lanes, width: Int) -> Float32:
    """Return the dot product of the first `width` lanes, summed in order,
    so a lane past the type, which can hold anything, is never read."""
    return (
        x[0] * y[0]
        + (x[1] * y[1] if width > 1 else 0)
        + (x[2] * y[2] if width > 2 else 0)
        + (x[3] * y[3] if width > 3 else 0)
    )


def _normalized(x: Lanes, width: Int) -> Lanes:
    """Return the first `width` lanes scaled to a length of one, or zero for
    a zero vector."""
    var size = sqrt(_dot(x, x, width))
    return x / size if size != 0 else Lanes(0)


def _step(edge: Float32, x: Float32) -> Float32:
    """Return GLSL's `step` of one lane."""
    return Float32(0) if x < edge else Float32(1)


def _truth(x: SIMD[DType.bool, 4]) -> Lanes:
    """Return one where a lane is true and zero where it is false."""
    return x.select(Lanes(1), Lanes(0))


def _view_point[S: NodeSource](source: S, p: Vector3) -> Lanes:
    """Return a world position in the camera's space, by the program's view."""
    var e = PROGRAM_VIEW
    return Lanes(
        source.word(e) * p.x
        + source.word(e + 4) * p.y
        + source.word(e + 8) * p.z
        + source.word(e + 12),
        source.word(e + 1) * p.x
        + source.word(e + 5) * p.y
        + source.word(e + 9) * p.z
        + source.word(e + 13),
        source.word(e + 2) * p.x
        + source.word(e + 6) * p.y
        + source.word(e + 10) * p.z
        + source.word(e + 14),
        0,
    )


def _view_normal[S: NodeSource](source: S, n: Vector3) -> Lanes:
    """Return a world direction turned into the camera's space and made a
    unit vector, three.js's `normalView`."""
    var e = PROGRAM_VIEW
    return _normalized(
        Lanes(
            source.word(e) * n.x
            + source.word(e + 4) * n.y
            + source.word(e + 8) * n.z,
            source.word(e + 1) * n.x
            + source.word(e + 5) * n.y
            + source.word(e + 9) * n.z,
            source.word(e + 2) * n.x
            + source.word(e + 6) * n.y
            + source.word(e + 10) * n.z,
            0,
        ),
        3,
    )


def _camera_position[S: NodeSource](source: S) -> Lanes:
    """Return the camera's world position from the view matrix: minus the
    rotation's transpose times the translation."""
    var e = PROGRAM_VIEW
    var tx = source.word(e + 12)
    var ty = source.word(e + 13)
    var tz = source.word(e + 14)
    return Lanes(
        -(
            source.word(e) * tx
            + source.word(e + 1) * ty
            + source.word(e + 2) * tz
        ),
        -(
            source.word(e + 4) * tx
            + source.word(e + 5) * ty
            + source.word(e + 6) * tz
        ),
        -(
            source.word(e + 8) * tx
            + source.word(e + 9) * ty
            + source.word(e + 10) * tz
        ),
        0,
    )


def _leaf[
    S: NodeSource
](
    source: S,
    op: Int,
    x: Lanes,
    immediate: Float32,
    context: Int,
    inputs: NodeInputs,
) -> Lanes:
    """Return what a node that computes nothing from other nodes holds."""
    if op == NODE_CONSTANT.value or op == NODE_UNIFORM.value:
        var at = Int(immediate)
        return Lanes(
            source.word(at),
            source.word(at + 1),
            source.word(at + 2),
            source.word(at + 3),
        )
    if op == NODE_TIME.value:
        return Lanes(source.word(PROGRAM_TIME))
    if op == NODE_CAMERA_POSITION.value:
        return _camera_position(source)
    if op == NODE_TEXTURE.value:
        if not inputs.textured:
            return Lanes(1)
        var texel = source.sample(Int(source.word(Int(immediate))), x[0], x[1])
        return Lanes(texel.r, texel.g, texel.b, texel.a)
    if op == NODE_LIT.value:
        return _lanes(inputs.lit)
    # An attribute, of the fragment or of the context the node runs in.
    var given = inputs
    if context != AT_FRAGMENT.value:
        given = node_attributes(source, NodeContext(context), inputs.textured)
    if op == NODE_UV.value:
        return Lanes(given.u, given.v, 0, 0)
    if op == NODE_POSITION_LOCAL.value or op == NODE_POSITION_WORLD.value:
        return _lanes(given.position)
    if op == NODE_POSITION_VIEW.value:
        return _view_point(source, given.position)
    if op == NODE_NORMAL_LOCAL.value or op == NODE_NORMAL_WORLD.value:
        return _lanes(given.normal)
    if op == NODE_NORMAL_VIEW.value:
        return _view_normal(source, given.normal)
    # `NODE_VERTEX_COLOR`, the one leaf left: `compile` writes nothing else.
    return _lanes(given.color)


def _joined(x: Lanes, y: Lanes, z: Lanes, packed: Int) -> Lanes:
    """Return the first components of three values laid end to end: as many
    of each as `packed` says, five to a width."""
    var out = Lanes(0)
    var at = 0
    for lane in range(packed % 5):  # pragma: no branch
        out[at] = x[lane]
        at += 1
    for lane in range((packed // 5) % 5):  # pragma: no branch
        out[at] = y[lane]
        at += 1
    for lane in range(packed // 25):
        out[at] = z[lane]
        at += 1
    return out


def _matrix[
    S: NodeSource
](source: S, x: Lanes, code: Int, transposed: Bool) -> Lanes:
    """Return a matrix in the program times a vector, or the vector times
    the matrix: `code` is where the matrix is, times eight, plus its size.
    """
    var at = code // 8
    var size = code % 8
    var out = Lanes(0)
    for row in range(size):  # pragma: no branch
        var sum = Float32(0)
        for column in range(size):  # pragma: no branch
            # Column-major: the element in `row`, `column` is at
            # `column * size + row`.
            var element = source.word(
                at
                + (row * size + column if transposed else column * size + row)
            )
            sum += element * x[column]
        out[row] = sum
    return out


def _rotl32(x: UInt32, k: Int) -> UInt32:
    """Return `x` turned left by `k` bits, MaterialX's `mx_rotl32`."""
    return (x << UInt32(k)) | (x >> UInt32(32 - k))


def _bjfinal(var a: UInt32, var b: UInt32, var c: UInt32) -> UInt32:
    """Return Bob Jenkins's final mix of three words, MaterialX's
    `mx_bjfinal`."""
    c ^= b
    c -= _rotl32(b, 14)
    a ^= c
    a -= _rotl32(c, 11)
    b ^= a
    b -= _rotl32(a, 25)
    c ^= b
    c -= _rotl32(b, 16)
    a ^= c
    a -= _rotl32(c, 4)
    b ^= a
    b -= _rotl32(a, 14)
    c ^= b
    c -= _rotl32(b, 24)
    return c


def _hash(x: Int32, y: Int32, z: Int32, count: Int) -> UInt32:
    """Return MaterialX's `mx_hash_int` of two or three whole numbers."""
    var seed = UInt32(0xDEADBEEF) + (UInt32(count) << 2) + 13
    var c = seed + UInt32(z) if count == 3 else seed
    return _bjfinal(seed + UInt32(x), seed + UInt32(y), c)


def _gradient(
    hash: UInt32, x: Float32, y: Float32, z: Float32, count: Int
) -> Float32:
    """Return MaterialX's `mx_gradient_float` in two or three dimensions."""
    var h = hash & UInt32(7 if count == 2 else 15)
    var u = x if h < UInt32(4 if count == 2 else 8) else y
    var v = (2.0 * (y if h < 4 else x)) if count == 2 else (
        y if h < 4 else (x if h == 12 or h == 14 else z)
    )
    return (-u if (h & 1) != 0 else u) + (-v if (h & 2) != 0 else v)


def _fade(t: Float32) -> Float32:
    """Return MaterialX's `mx_fade`, the quintic ease."""
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def perlin_noise(p: Lanes, count: Int) -> Float32:
    """Return MaterialX's Perlin noise at a point, three.js's
    `mx_perlin_noise_float`, in the same order of operations.

    Args:
        p: The point, in its first two or three lanes.
        count: Two or three, how many lanes the point has.

    Returns:
        The noise, from about minus one to one.
    """
    var fx = floor(p[0])
    var fy = floor(p[1])
    var X = Int32(fx)
    var Y = Int32(fy)
    var x = p[0] - fx
    var y = p[1] - fy
    var u = _fade(x)
    var v = _fade(y)
    var s1 = 1.0 - u
    var t1 = 1.0 - v
    if count == 2:
        var flat = t1 * (
            _gradient(_hash(X, Y, 0, 2), x, y, 0, 2) * s1
            + _gradient(_hash(X + 1, Y, 0, 2), x - 1.0, y, 0, 2) * u
        ) + v * (
            _gradient(_hash(X, Y + 1, 0, 2), x, y - 1.0, 0, 2) * s1
            + _gradient(_hash(X + 1, Y + 1, 0, 2), x - 1.0, y - 1.0, 0, 2) * u
        )
        return 0.6616 * flat
    var fz = floor(p[2])
    var Z = Int32(fz)
    var z = p[2] - fz
    var w = _fade(z)
    var near = t1 * (
        _gradient(_hash(X, Y, Z, 3), x, y, z, 3) * s1
        + _gradient(_hash(X + 1, Y, Z, 3), x - 1.0, y, z, 3) * u
    ) + v * (
        _gradient(_hash(X, Y + 1, Z, 3), x, y - 1.0, z, 3) * s1
        + _gradient(_hash(X + 1, Y + 1, Z, 3), x - 1.0, y - 1.0, z, 3) * u
    )
    var far = t1 * (
        _gradient(_hash(X, Y, Z + 1, 3), x, y, z - 1.0, 3) * s1
        + _gradient(_hash(X + 1, Y, Z + 1, 3), x - 1.0, y, z - 1.0, 3) * u
    ) + v * (
        _gradient(_hash(X, Y + 1, Z + 1, 3), x, y - 1.0, z - 1.0, 3) * s1
        + _gradient(_hash(X + 1, Y + 1, Z + 1, 3), x - 1.0, y - 1.0, z - 1.0, 3)
        * u
    )
    return 0.9820 * ((1.0 - w) * near + w * far)


def _atan(x: Float32) -> Float32:
    """Return the arc tangent of one number, Cephes's `atanf`: the
    argument folded to below tan(pi / 8) and a polynomial there. Written
    out, because a GPU target has no libm."""
    var sign = Float32(1)
    var a = x
    if a < 0:
        sign = -1
        a = -a
    var offset = Float32(0)
    if a > 2.414213562373095:
        offset = Float32(1.5707963267948966)
        a = -1 / a
    elif a > 0.41421356237309503:
        offset = Float32(0.7853981633974483)
        a = (a - 1) / (a + 1)
    var z = a * a
    var y = (
        (
            (Float32(8.05374449538e-2) * z - Float32(1.38776856032e-1)) * z
            + Float32(1.99777106478e-1)
        )
        * z
        - Float32(3.33329491539e-1)
    ) * z * a + a
    return sign * (offset + y)


def _atan2(y: Float32, x: Float32) -> Float32:
    """Return the angle of `(x, y)` from minus pi to pi, by `_atan`."""
    if x != x or y != y:
        return x + y
    if x > 0:
        return _atan(y / x)
    if x < 0:
        return _atan(y / x) + Float32(
            3.141592653589793 if y >= 0 else -3.141592653589793
        )
    if y > 0:
        return Float32(1.5707963267948966)
    if y < 0:
        return Float32(-1.5707963267948966)
    return 0


def _round(x: Float32) -> Float32:
    """Return the whole number nearest `x`, a half to the even one."""
    var low = floor(x)
    var part = x - low
    if part > 0.5:
        return low + 1
    if part < 0.5:
        return low
    return low if low - 2 * floor(low / 2) == 0 else low + 1


def _lane_by_lane(op: Int) -> Bool:
    """Return True for an operation `_per_lane` computes."""
    return (
        op == NODE_ATAN.value
        or op == NODE_ATAN2.value
        or op == NODE_ASIN.value
        or op == NODE_ACOS.value
        or op == NODE_ROUND.value
    )


def _per_lane(op: Int, x: Lanes, y: Lanes) -> Lanes:
    """Return an operation of one number on each lane: the arc tangents,
    the arc sines and cosines, and rounding."""
    var out = Lanes(0)
    for lane in range(4):  # pragma: no branch
        var a = x[lane]
        if op == NODE_ATAN.value:
            out[lane] = _atan(a)
        elif op == NODE_ATAN2.value:
            out[lane] = _atan2(a, y[lane])
        elif op == NODE_ASIN.value:
            out[lane] = _atan2(a, sqrt(1 - a * a))
        elif op == NODE_ACOS.value:
            out[lane] = _atan2(sqrt(1 - a * a), a)
        else:
            out[lane] = _round(a)
    return out


def _operation[
    S: NodeSource
](
    source: S, op: Int, x: Lanes, y: Lanes, z: Lanes, immediate: Float32
) -> Lanes:
    """Return what a math node computes from its inputs' registers."""
    var width = Int(immediate)
    if op == NODE_ADD.value:
        return x + y
    if op == NODE_SUB.value:
        return x - y
    if op == NODE_MUL.value:
        return x * y
    if op == NODE_DIV.value:
        return x / y
    if op == NODE_MIX.value:
        return x * (1 - z) + y * z
    if op == NODE_CLAMP.value:
        return min(max(x, y), z)
    if op == NODE_DOT.value:
        return Lanes(_dot(x, y, width))
    if op == NODE_NORMALIZE.value:
        return _normalized(x, width)
    if op == NODE_SIN.value:
        return sin(x)
    if op == NODE_COS.value:
        return cos(x)
    if op == NODE_POW.value:
        return pow(x, y)
    if op == NODE_STEP.value:
        return Lanes(
            _step(x[0], y[0]),
            _step(x[1], y[1]),
            _step(x[2], y[2]),
            _step(x[3], y[3]),
        )
    if op == NODE_SMOOTHSTEP.value:
        return Lanes(
            smoothstep(x[0], y[0], z[0]),
            smoothstep(x[1], y[1], z[1]),
            smoothstep(x[2], y[2], z[2]),
            smoothstep(x[3], y[3], z[3]),
        )
    if op == NODE_LENGTH.value:
        return Lanes(sqrt(_dot(x, x, width)))
    if op == NODE_FRACT.value:
        return x - floor(x)
    if op == NODE_SWIZZLE.value:
        return Lanes(
            x[width & 3],
            x[(width >> 2) & 3],
            x[(width >> 4) & 3],
            x[(width >> 6) & 3],
        )
    if op == NODE_JOIN.value:
        return _joined(x, y, z, width)
    if op == NODE_ABS.value:
        return abs(x)
    if op == NODE_SIGN.value:
        return _truth(x.gt(0)) - _truth(x.lt(0))
    if op == NODE_FLOOR.value:
        return floor(x)
    if op == NODE_CEIL.value:
        return ceil(x)
    if op == NODE_TRUNC.value:
        return x.ge(0).select(floor(x), ceil(x))
    if op == NODE_EXP.value:
        return exp(x)
    if op == NODE_EXP2.value:
        return exp2(x)
    if op == NODE_LOG.value:
        return log2(x) * Float32(0.6931471805599453)
    if op == NODE_LOG2.value:
        return log2(x)
    if op == NODE_SQRT.value:
        return sqrt(x)
    if op == NODE_INVERSE_SQRT.value:
        return 1 / sqrt(x)
    if op == NODE_NEGATE.value:
        return -x
    if op == NODE_ONE_MINUS.value:
        return 1 - x
    if op == NODE_SATURATE.value:
        return min(max(x, 0), 1)
    if op == NODE_TAN.value:
        return sin(x) / cos(x)
    if _lane_by_lane(op):
        return _per_lane(op, x, y)
    if op == NODE_RECIPROCAL.value:
        return 1 / x
    if op == NODE_RADIANS.value:
        return x * Float32(0.017453292519943295)
    if op == NODE_DEGREES.value:
        return x * Float32(57.29577951308232)
    if op == NODE_MIN.value:
        return min(x, y)
    if op == NODE_MAX.value:
        return max(x, y)
    if op == NODE_MOD.value:
        return x - y * floor(x / y)
    if op == NODE_DISTANCE.value:
        var apart = x - y
        return Lanes(sqrt(_dot(apart, apart, width)))
    if op == NODE_CROSS.value:
        return Lanes(
            x[1] * y[2] - x[2] * y[1],
            x[2] * y[0] - x[0] * y[2],
            x[0] * y[1] - x[1] * y[0],
            0,
        )
    if op == NODE_REFLECT.value:
        return x - 2 * _dot(y, x, width) * y
    if op == NODE_REFRACT.value:
        var eta = z[0]
        var d = _dot(y, x, width)
        var k = 1 - eta * eta * (1 - d * d)
        return Lanes(0) if k < 0 else eta * x - (eta * d + sqrt(k)) * y
    if op == NODE_FACEFORWARD.value:
        return x if _dot(z, y, width) < 0 else -x
    if op == NODE_LESS_THAN.value:
        return _truth(x.lt(y))
    if op == NODE_LESS_THAN_EQUAL.value:
        return _truth(x.le(y))
    if op == NODE_GREATER_THAN.value:
        return _truth(x.gt(y))
    if op == NODE_GREATER_THAN_EQUAL.value:
        return _truth(x.ge(y))
    if op == NODE_EQUAL.value:
        return _truth(x.eq(y))
    if op == NODE_NOT_EQUAL.value:
        return _truth(x.ne(y))
    if op == NODE_AND.value:
        return _truth(x.ne(0) & y.ne(0))
    if op == NODE_OR.value:
        return _truth(x.ne(0) | y.ne(0))
    if op == NODE_XOR.value:
        return _truth(x.ne(0) ^ y.ne(0))
    if op == NODE_NOT.value:
        return _truth(x.eq(0))
    if op == NODE_SELECT.value:
        return x.ne(0).select(y, z)
    if op == NODE_MATRIX_VECTOR.value or op == NODE_VECTOR_MATRIX.value:
        return _matrix(source, x, width, op == NODE_VECTOR_MATRIX.value)
    if op == NODE_NOISE.value:
        return Lanes(perlin_noise(x, width))
    # `NODE_INTERPOLATE`, the one operation left: `compile` writes nothing
    # else.
    var s = source.shares(NodeContext(width))
    return x * s[0] + y * s[1] + z * s[2]


def has_output[S: NodeSource](source: S, output: NodeOutput) -> Bool:
    """Return True if the program `source` reads sets an output.

    Args:
        source: The program.
        output: One of the nine outputs; the caller names it by its constant.

    Returns:
        Whether any instruction computes it.
    """
    return source.word(output.value * 2 + 1) > 0


def run_nodes[
    S: NodeSource
](source: S, output: NodeOutput, inputs: NodeInputs) -> Lanes:
    """Return what one output of a program computes for one fragment or one
    vertex: the interpreter both rasterizers run.

    Each instruction writes the register it names, from the registers its
    inputs are in, and the output is what the last instruction wrote. A
    lane past the value's type can hold anything, and only the operations
    that read a width -- `dot`, `length`, `normalize`, `distance`, the
    reflections, a join, a matrix, a swizzle and the noise -- read lanes by
    number, each within the type.

    Args:
        source: The program, where its textures are sampled, and its
            triangle.
        output: One of the nine outputs, one `has_output` answers True for;
            the caller names it by its constant.
        inputs: The fragment's or the vertex's attributes.

    Returns:
        The value, in as many lanes as its type has.
    """
    var start = Int(source.word(output.value * 2))
    var count = Int(source.word(output.value * 2 + 1))
    var registers = Array[Lanes, MAX_REGISTERS](fill=Lanes(0))
    var written = 0
    # Never empty: the caller asks only of an output the program sets, and
    # an output that is set holds at least the node that feeds it.
    for index in range(count):  # pragma: no branch
        var at = start + index * INSTRUCTION_FLOATS
        var op = Int(source.word(at + INSTRUCTION_OP))
        var third = Int(source.word(at + INSTRUCTION_C))
        var x = registers[Int(source.word(at + INSTRUCTION_A))]
        var y = registers[Int(source.word(at + INSTRUCTION_B))]
        var z = registers[third]
        var immediate = source.word(at + INSTRUCTION_IMMEDIATE)
        written = Int(source.word(at + INSTRUCTION_DEST))
        if op < NODE_ADD.value:
            registers[written] = _leaf(source, op, x, immediate, third, inputs)
        else:
            registers[written] = _operation(source, op, x, y, z, immediate)
    return registers[written]


def here_inputs[S: NodeSource](source: S, textured: Bool) -> NodeInputs:
    """Return the fragment's own interpolated attributes, before any map:
    what a depth node reads, since it runs before the fragment is shaded.

    Args:
        source: The program's triangle, at the fragment.
        textured: Whether texture nodes read their textures.

    Returns:
        The attributes, with no lit color.
    """
    return node_attributes(source, AT_HERE, textured)


def offset_normal(normal: Vector3, offset: Lanes) -> Vector3:
    """Return a normal plus a normal node's offset, made a unit vector again:
    what the lights read. Both rasterizers call it.

    Args:
        normal: The fragment's unit normal, in world space.
        offset: What the normal node computed, in its first three lanes.

    Returns:
        The bent unit normal, or the zero vector the sum is when it is one.
    """
    var x = normal.x + offset[0]
    var y = normal.y + offset[1]
    var z = normal.z + offset[2]
    var size = sqrt(x * x + y * y + z * z)
    return Vector3(x / size, y / size, z / size) if size != 0 else Vector3(
        x, y, z
    )


def node_depth(depth: Float32, reversed: Bool) -> Float32:
    """Return a depth node's window depth as the depth buffer stores it:
    `2 * depth - 1` on the minus one to one scale, or the depth as it is for
    a reversed buffer, which stores one minus the window depth already.
    Both rasterizers call it.

    Args:
        depth: What the depth node computed: zero at the near plane and one
            at the far plane, or the other way for a reversed buffer.
        reversed: Whether the primitive's depth mode is `REVERSED_DEPTH`.

    Returns:
        The stored depth.
    """
    return depth if reversed else depth * 2 - 1


def moved_position(
    program: NodeProgram, position: Vector3, normal: Vector3
) raises -> Vector3:
    """Return a vertex moved by a program's position node, on the host: the
    vertex stage both rasterizers draw.

    Args:
        program: The program. It must set `POSITION_NODE`.
        position: The vertex's local position.
        normal: The vertex's local normal, or zero for a geometry that has
            none.

    Returns:
        The position plus the offset the node computes for it.

    Raises:
        Error: If the program sets no position node.
    """
    if not program.has(POSITION_NODE):
        raise Error("That node program has no position node")
    var offset = run_nodes(
        ProgramSource(Pointer(to=program)),
        POSITION_NODE,
        NodeInputs(
            0,
            0,
            position,
            normal,
            Vector3(0, 0, 0),
            Vector3(0, 0, 0),
            False,
        ),
    )
    return Vector3(
        position.x + offset[0], position.y + offset[1], position.z + offset[2]
    )
