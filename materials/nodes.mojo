# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Custom shading from small expression graphs: three.js's node materials.

three.js lets a material replace parts of its shader with a graph of nodes,
its Three Shading Language (TSL): `material.colorNode = mix(a, b, sin(time))`.
The graph is compiled to a shader. This port has no shader language, so a
`NodeGraph` is compiled to a compact bytecode instead, a `NodeProgram`, and
both rasterizers interpret that bytecode per fragment with the one function
here, `run_nodes`. The host reads the program out of a list and the kernel
reads it out of a device buffer, through the `NodeSource` trait, so the two
backends run the same arithmetic in the same order.

A graph sets up to six outputs, each three.js's property of the same name:

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

A graph refuses a type error as it is built: a `vec3` added to a `vec2`, a
`float` output given a `vec3`, a swizzle of a component the value lacks. A
`float` next to a vector is repeated into every component, as GLSL does. A
rewire that would make a cycle is refused, and `compile` refuses a cycle and
a node that reads what its stage does not have. A program refuses a uniform
name it does not know, and a value of the wrong type for one it does.

**What three.js offers that is not ported.** GLSL source: a `ShaderMaterial`
here is `materials.material.shader_material`, a node graph given as the
fragment program, with named uniforms, and a GLSL string cannot be compiled.
Compute nodes, storage buffers, `Fn` functions, loops, conditionals, `varying`
and `Var` nodes, derivatives (`dFdx`), `discard`, and the node library past
the set below: `abs`, `min`, `max`, `atan`, `reflect`, `cross` and the rest.
A texture node reads its image at the level the surface's own coordinates
pick, where WebGPU measures the derivatives of the coordinate the node
computes. A graph holds at most `MAX_REGISTERS` nodes per output.
"""

from math.matrix4 import Matrix4
from math.smoothstep import smoothstep
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from render.texture_store import NO_TEXTURE, TextureId
from std.math import cos, floor, max, min, pow, sin, sqrt
from units.si import Duration, SECOND

# How many nodes one output can hold once compiled: one register each, four
# floats a register. The kernel keeps them in a fixed array per thread, so
# the number is fixed, and a bigger graph is refused by `compile`.
comptime MAX_REGISTERS = 32
# How one instruction is laid out: the node kind, the registers of its three
# inputs, and one immediate -- where a constant's four floats are, which
# texture to sample, or which components a swizzle picks.
comptime INSTRUCTION_OP = 0
comptime INSTRUCTION_A = 1
comptime INSTRUCTION_B = 2
comptime INSTRUCTION_C = 3
comptime INSTRUCTION_IMMEDIATE = 4
comptime INSTRUCTION_FLOATS = 5
# How a program begins: where each of the six outputs starts and how many
# instructions it holds, then the frame's time in seconds, then the view
# matrix, sixteen floats, column-major. The renderer writes the last two
# every frame, as three.js updates its `time` and `cameraViewMatrix` nodes.
comptime NODE_OUTPUT_COUNT = 6
comptime PROGRAM_TIME = NODE_OUTPUT_COUNT * 2
comptime PROGRAM_VIEW = PROGRAM_TIME + 1
comptime PROGRAM_HEADER = PROGRAM_VIEW + 16

comptime Lanes = SIMD[DType.float32, 4]


@fieldwise_init
struct ValueType(Equatable, ImplicitlyCopyable, Writable):
    """What a node's value is, as a type rather than a bare int: a `float`
    or a vector of two, three or four. `value` is the component count."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four types there are.

        Returns:
            Whether the count is one to four.
        """
        return self.value >= 1 and self.value <= 4

    def name(self) -> String:
        """Return the type's TSL name, for an error message.

        Returns:
            `float`, `vec2`, `vec3` or `vec4`.
        """
        if self.value == 1:
            return "float"
        return "vec" + String(self.value)


comptime NODE_FLOAT = ValueType(1)
comptime NODE_VEC2 = ValueType(2)
comptime NODE_VEC3 = ValueType(3)
comptime NODE_VEC4 = ValueType(4)


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
            and self.value <= NODE_SWIZZLE.value
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
# A texture read at a coordinate, three.js's `texture(map, uv)`, and the
# color the standard lighting made, three.js's `output`.
comptime NODE_TEXTURE = NodeKind(11)
comptime NODE_LIT = NodeKind(12)
# The math, each three.js's function of the same name.
comptime NODE_ADD = NodeKind(13)
comptime NODE_SUB = NodeKind(14)
comptime NODE_MUL = NodeKind(15)
comptime NODE_DIV = NodeKind(16)
comptime NODE_MIX = NodeKind(17)
comptime NODE_CLAMP = NodeKind(18)
comptime NODE_DOT = NodeKind(19)
comptime NODE_NORMALIZE = NodeKind(20)
comptime NODE_SIN = NodeKind(21)
comptime NODE_COS = NodeKind(22)
comptime NODE_POW = NodeKind(23)
comptime NODE_STEP = NodeKind(24)
comptime NODE_SMOOTHSTEP = NodeKind(25)
comptime NODE_LENGTH = NodeKind(26)
comptime NODE_FRACT = NodeKind(27)
comptime NODE_SWIZZLE = NodeKind(28)


@fieldwise_init
struct NodeOutput(Equatable, ImplicitlyCopyable, Writable):
    """Which part of the shading a graph replaces, as a type rather than a
    bare int. See the module's list."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the six outputs there are.

        Returns:
            Whether the value names an output.
        """
        return self.value >= 0 and self.value < NODE_OUTPUT_COUNT

    def value_type(self) -> ValueType:
        """Return the type a node given this output must have.

        Returns:
            `NODE_FLOAT` for the opacity, and `NODE_VEC3` for the rest.
        """
        return NODE_FLOAT if self == OPACITY_NODE else NODE_VEC3


comptime COLOR_NODE = NodeOutput(0)
comptime OPACITY_NODE = NodeOutput(1)
comptime EMISSIVE_NODE = NodeOutput(2)
comptime NORMAL_NODE = NodeOutput(3)
comptime POSITION_NODE = NodeOutput(4)
comptime OUTPUT_NODE = NodeOutput(5)


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


struct NodeGraph(Copyable, Movable):
    """A graph of nodes being built, three.js's TSL expressions.

    Every method that makes a node returns a `NodeRef` naming it, and takes
    the refs of the nodes it reads. A ref from another graph, or one made up,
    is refused. Nothing is evaluated here: `compile` turns the outputs into a
    `NodeProgram`.
    """

    # Per node: its kind and its type, the refs of up to three inputs (-1
    # for none), four floats of value -- a constant's or a uniform's, a
    # texture's id, or a swizzle's packed components -- and a uniform's name.
    var _kinds: List[NodeKind]
    var _types: List[ValueType]
    var _inputs: List[Int]
    var _values: List[Float32]
    var _names: List[String]
    # Per output, the ref of the node that feeds it, or -1 for none.
    var _outputs: List[Int]

    def __init__(out self):
        """Create an empty graph with no outputs."""
        self._kinds = List[NodeKind]()
        self._types = List[ValueType]()
        self._inputs = List[Int]()
        self._values = List[Float32]()
        self._names = List[String]()
        self._outputs = List[Int](length=NODE_OUTPUT_COUNT, fill=-1)

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

    def lit(mut self) -> NodeRef:
        """Return the color the material's own lighting made of the surface,
        a linear `vec3`: three.js's `output`. Only an `OUTPUT_NODE` reads it.

        Returns:
            The node.
        """
        return self._add(NODE_LIT, NODE_VEC3)

    # --- math ---------------------------------------------------------------

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
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        self._check(a)
        self._check(b)
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

    def mul(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return `a * b` component by component, TSL's `mul`.

        Args:
            a: The first operand.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
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
            Error: If any is not a node of this graph, or two are vectors of
                two sizes.
        """
        self._check(a)
        self._check(b)
        self._check(c)
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
        self._check(a)
        self._check(b)
        var type = self._types[a.value]
        if self._types[b.value] != type:
            raise Error(
                "A node graph cannot dot a "
                + type.name()
                + " and a "
                + self._types[b.value].name()
            )
        return self._add(
            NODE_DOT,
            NODE_FLOAT,
            a.value,
            b.value,
            value=Lanes(Float32(type.value), 0, 0, 0),
        )

    def _unary(
        mut self, kind: NodeKind, a: NodeRef, scalar: Bool = False
    ) raises -> NodeRef:
        """Append an operation of one operand whose width it reads: of the
        operand's type, or a `float` when `scalar`.

        Raises:
            Error: If `a` is not a node of this graph.
        """
        self._check(a)
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
        self._check(a)
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
            output: Which output: `COLOR_NODE`, `OPACITY_NODE`,
                `EMISSIVE_NODE`, `NORMAL_NODE`, `POSITION_NODE` or
                `OUTPUT_NODE`.
            node: The node, of the type the output takes: a `float` for the
                opacity and a `vec3` for the rest.

        Raises:
            Error: If the output is none of the six, the node is not in this
                graph, or its type is not the output's.
        """
        if not output.is_valid():
            raise Error("A node output that is none of the six")
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
            var vertex = (
                local
                or kind == NODE_TIME
                or kind == NODE_CONSTANT
                or kind == NODE_UNIFORM
                or kind.value >= NODE_ADD.value
            )
            if not vertex:
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

        Each output's nodes are laid out inputs first, one instruction and
        one register each, and a node two outputs share is computed by
        both. Every constant and uniform is stored once, after the
        instructions, so `NodeProgram.set_uniform` changes it everywhere.

        Returns:
            The program, at time zero under an identity view.

        Raises:
            Error: If no output is set, a node reads one the graph does not
                hold, the nodes make a cycle, an output reads what its stage
                does not have (see `set_output`), or an output needs more
                than `MAX_REGISTERS` nodes.
        """
        var orders = List[List[Int]]()
        var total = 0
        for output in range(NODE_OUTPUT_COUNT):  # pragma: no branch
            var root = self._outputs[output]
            if root < 0:
                orders.append(List[Int]())
                continue
            if root >= self.count():
                raise Error("An output names a node the graph does not hold")
            var order = self._order(root)
            if len(order) > MAX_REGISTERS:
                raise Error(
                    "A node output needs at most "
                    + String(MAX_REGISTERS)
                    + " nodes"
                )
            for index in range(len(order)):  # pragma: no branch
                var node = order[index]
                # The two are open fields, so an edited graph can hold a
                # kind no instruction means or a type no value has.
                if (
                    not self._kinds[node].is_valid()
                    or not self._types[node].is_valid()
                ):
                    raise Error("A node holds a kind or a type there is not")
                self._check_stage(NodeOutput(output), self._kinds[node])
            total += len(order)
            orders.append(order^)
        if total == 0:
            raise Error("A node graph needs at least one output")
        var program = NodeProgram()
        # Where each constant's and uniform's four floats are: after every
        # instruction, in the order they are first read.
        var pool = List[Int](length=self.count(), fill=-1)
        var next = PROGRAM_HEADER + total * INSTRUCTION_FLOATS
        var values = List[Float32]()
        var at = PROGRAM_HEADER
        for output in range(NODE_OUTPUT_COUNT):  # pragma: no branch
            ref order = orders[output]
            program.code[output * 2] = Float32(at)
            program.code[output * 2 + 1] = Float32(len(order))
            # Which register holds each node of this output.
            var register = List[Int](length=self.count(), fill=0)
            for index in range(len(order)):
                var node = order[index]
                register[node] = index
                var kind = self._kinds[node]
                var immediate = self._values[node * 4]
                if kind == NODE_CONSTANT or kind == NODE_UNIFORM:
                    if pool[node] < 0:
                        pool[node] = next
                        next += 4
                        for lane in range(4):  # pragma: no branch
                            values.append(self._values[node * 4 + lane])
                        if kind == NODE_UNIFORM:
                            program.uniform_names.append(self._names[node])
                            program.uniform_offsets.append(pool[node])
                            program.uniform_types.append(self._types[node])
                    immediate = Float32(pool[node])
                if kind == NODE_TEXTURE:
                    _note_texture(program.textures, TextureId(Int(immediate)))
                program.code.append(Float32(kind.value))
                for slot in range(3):  # pragma: no branch
                    var input = self._inputs[node * 3 + slot]
                    program.code.append(
                        Float32(register[input]) if input >= 0 else 0
                    )
                program.code.append(immediate)
                at += INSTRUCTION_FLOATS
        program.code.extend(values^)
        return program^


struct NodeProgram(Copyable, Movable):
    """A compiled `NodeGraph`: the bytecode both rasterizers interpret, and
    where its uniforms are in it.

    `code` is laid out as `PROGRAM_HEADER` floats -- each output's first
    instruction and its count, the time, the view -- then the instructions,
    `INSTRUCTION_FLOATS` each, then four floats per constant and uniform.
    """

    var code: List[Float32]
    var uniform_names: List[String]
    var uniform_offsets: List[Int]
    var uniform_types: List[ValueType]
    # Every texture a texture node reads, so a renderer can check and upload
    # them before a fragment asks.
    var textures: List[TextureId]

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

    def has(self, output: NodeOutput) raises -> Bool:
        """Return True if the program sets an output.

        Args:
            output: One of the six outputs.

        Returns:
            Whether a graph node feeds it.

        Raises:
            Error: If the output is none of the six.
        """
        if not output.is_valid():
            raise Error("A node output that is none of the six")
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

    def uniform(self, name: String) raises -> Lanes:
        """Return a uniform's value, in as many lanes as its type has and
        zero past them.

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


trait NodeSource:
    """Where a program's floats are read and its textures sampled: the host's
    list and store, or the kernel's buffers. `run_nodes` asks these two
    things and nothing else, so both backends run the one function."""

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


struct ProgramSource[origin: Origin[mut=False]](NodeSource):
    """The host's `NodeSource` for a program on its own, with no surface to
    sample a texture on: what the vertex stage runs a position node with,
    since a position node reads no texture."""

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


@fieldwise_init
struct NodeInputs(ImplicitlyCopyable):
    """What a fragment, or a vertex, hands a program: its attributes and,
    for an output node, the lit color."""

    # The texture coordinate.
    var u: Float32
    var v: Float32
    # The world-space position and unit normal of a fragment, or the local
    # position and normal of a vertex.
    var position: Vector3
    var normal: Vector3
    # The interpolated corner color, linear.
    var color: Vector3
    # What the standard lighting made of the fragment, linear.
    var lit: Vector3
    # Whether texture nodes read their textures: only under the mode that
    # opens them. Otherwise they read opaque white.
    var textured: Bool


def _lanes(v: Vector3) -> Lanes:
    """Return a vector in the first three lanes."""
    return Lanes(v.x, v.y, v.z, 0)


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


def _leaf[
    S: NodeSource
](
    source: S, op: Int, x: Lanes, immediate: Float32, inputs: NodeInputs
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
    if op == NODE_UV.value:
        return Lanes(inputs.u, inputs.v, 0, 0)
    if op == NODE_POSITION_LOCAL.value or op == NODE_POSITION_WORLD.value:
        return _lanes(inputs.position)
    if op == NODE_POSITION_VIEW.value:
        return _view_point(source, inputs.position)
    if op == NODE_NORMAL_LOCAL.value or op == NODE_NORMAL_WORLD.value:
        return _lanes(inputs.normal)
    if op == NODE_NORMAL_VIEW.value:
        return _view_normal(source, inputs.normal)
    if op == NODE_VERTEX_COLOR.value:
        return _lanes(inputs.color)
    if op == NODE_TIME.value:
        return Lanes(source.word(PROGRAM_TIME))
    if op == NODE_TEXTURE.value:
        if not inputs.textured:
            return Lanes(1)
        var texel = source.sample(Int(immediate), x[0], x[1])
        return Lanes(texel.r, texel.g, texel.b, texel.a)
    # `NODE_LIT`, the one leaf left: `compile` writes nothing else.
    return _lanes(inputs.lit)


def _operation(
    op: Int, x: Lanes, y: Lanes, z: Lanes, immediate: Float32
) -> Lanes:
    """Return what a math node computes from its inputs' registers."""
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
        return Lanes(_dot(x, y, Int(immediate)))
    if op == NODE_NORMALIZE.value:
        return _normalized(x, Int(immediate))
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
        return Lanes(sqrt(_dot(x, x, Int(immediate))))
    if op == NODE_FRACT.value:
        return x - floor(x)
    # `NODE_SWIZZLE`, the one operation left: `compile` writes nothing else.
    var packed = Int(immediate)
    return Lanes(
        x[packed & 3],
        x[(packed >> 2) & 3],
        x[(packed >> 4) & 3],
        x[(packed >> 6) & 3],
    )


def has_output[S: NodeSource](source: S, output: NodeOutput) -> Bool:
    """Return True if the program `source` reads sets an output.

    Args:
        source: The program.
        output: One of the six outputs; the caller names it by its constant.

    Returns:
        Whether any instruction computes it.
    """
    return source.word(output.value * 2 + 1) > 0


def run_nodes[
    S: NodeSource
](source: S, output: NodeOutput, inputs: NodeInputs) -> Lanes:
    """Return what one output of a program computes for one fragment or one
    vertex: the interpreter both rasterizers run.

    Each instruction writes the register of its own index, from the
    registers its inputs are in, and the output is the last register. A
    lane past the value's type can hold anything, and only `dot`,
    `length`, `normalize` and a swizzle read lanes by number, each within
    the type.

    Args:
        source: The program, and where its textures are sampled.
        output: One of the six outputs, one `has_output` answers True for;
            the caller names it by its constant.
        inputs: The fragment's or the vertex's attributes.

    Returns:
        The value, in as many lanes as its type has.
    """
    var start = Int(source.word(output.value * 2))
    var count = Int(source.word(output.value * 2 + 1))
    var registers = Array[Lanes, MAX_REGISTERS](fill=Lanes(0))
    # Never empty: the caller asks only of an output the program sets, and
    # an output that is set holds at least the node that feeds it.
    for index in range(count):  # pragma: no branch
        var at = start + index * INSTRUCTION_FLOATS
        var op = Int(source.word(at + INSTRUCTION_OP))
        var x = registers[Int(source.word(at + INSTRUCTION_A))]
        var y = registers[Int(source.word(at + INSTRUCTION_B))]
        var z = registers[Int(source.word(at + INSTRUCTION_C))]
        var immediate = source.word(at + INSTRUCTION_IMMEDIATE)
        if op < NODE_ADD.value:
            registers[index] = _leaf(source, op, x, immediate, inputs)
        else:
            registers[index] = _operation(op, x, y, z, immediate)
    return registers[count - 1]


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
