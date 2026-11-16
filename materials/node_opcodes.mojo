# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Opcodes, node contexts, graph references and control-flow records for TSL.

Shared by `materials.node_vm` (bytecode execution) and `materials.nodes`
(graph construction and compilation) so bytecode execution does not pull in
the graph compiler.
"""

from core.ordinal import ordinal_valid
from core.search import first_match
from materials.node_program import (
    NODE_MAT3,
    NODE_MAT4,
    NodeOutput,
    PROGRAM_HEADER,
    ValueType,
)

# How many times one `Loop` can run its body, and how many nodes a graph can
# grow to as its loops are unrolled.
comptime MAX_LOOP_COUNT = 1024
comptime MAX_GRAPH_NODES = 65536


def require_program_code(size: Int) raises:
    """Refuse a node program whose code is shorter than its header.

    Nothing. The call returns when the code holds a header.

    Args:
        size: How many numbers the code holds.

    Raises:
        Error: If the code is shorter than `PROGRAM_HEADER`.
    """
    if size < PROGRAM_HEADER:
        raise Error("Object JSON: a node program's code is too short")


comptime NODE_UINT = ValueType(41)
comptime NODE_UVEC2 = ValueType(42)
comptime NODE_UVEC4 = ValueType(44)
comptime NODE_INT = ValueType(45)
comptime NODE_IVEC2 = ValueType(46)
comptime NODE_IVEC3 = ValueType(47)
comptime NODE_IVEC4 = ValueType(48)


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
            and self.value <= NODE_INT_LAST.value
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
# Where the fragment is on the target, GLSL's `gl_FragCoord`: the pixel's
# center in pixels from the bottom left, its depth from zero to one, and
# one. See `NodeSource.frag_coord`.
comptime NODE_FRAG_COORD = NodeKind(82)
# A matrix the graph builds from its columns: a `mat3`'s three, or a
# `mat4`'s first two and a `NODE_MATRIX_TAIL` of its last two. `mul`
# expands one into vector operations, so no instruction reads it.
comptime NODE_MATRIX_COLUMNS = NodeKind(83)
comptime NODE_MATRIX_TAIL = NodeKind(84)
# The bit operations of whole numbers, which a value holds as floats: each
# component truncated toward zero to a 32-bit integer, operated on, and
# held as a float again.
comptime NODE_BIT_AND = NodeKind(85)
comptime NODE_BIT_OR = NodeKind(86)
comptime NODE_BIT_XOR = NodeKind(87)
comptime NODE_BIT_NOT = NodeKind(88)
comptime NODE_SHIFT_LEFT = NodeKind(89)
comptime NODE_SHIFT_RIGHT = NodeKind(90)
# A whole number as TSL's `uint` holds it: truncated toward zero, and a
# negative one wrapped up by 2 ** 32.
comptime NODE_UNSIGNED = NodeKind(91)
# MaterialX's noises: Perlin of three components, cell noise of one and of
# three, and Worley noise of the one, two or three nearest points.
comptime NODE_NOISE_VEC3 = NodeKind(92)
comptime NODE_CELL_NOISE = NodeKind(93)
comptime NODE_CELL_NOISE_VEC3 = NodeKind(94)
comptime NODE_WORLEY = NodeKind(95)
# Which way the fragment's triangle faces, one or zero. Its immediate picks
# the rule: zero for TSL's `frontFacing`, false where the triangle is seen
# from its back; one for GLSL's `gl_FrontFacing` in three.js's WebGL
# renderer, which turns a `BACK_SIDE` material's front face round. See
# `NodeSource.seen_from_behind`.
comptime NODE_FRONT_FACING = NodeKind(96)
# A texture read at a mip level its third input gives, GLSL's
# `textureLod`: `NODE_TEXTURE` with no footprint. See
# `NodeSource.sample_level`.
comptime NODE_TEXTURE_LEVEL = NodeKind(97)
# A texel by its column and row, and a texture level's size: GLSL's
# `texelFetch` and `textureSize`, TSL's `textureLoad` and `textureSize`.
# See `NodeSource.fetch` and `NodeSource.size`.
comptime NODE_TEXEL_FETCH = NodeKind(98)
comptime NODE_TEXTURE_SIZE = NodeKind(99)
# A custom attribute of the geometry, three.js's `attribute(name)`: its
# immediate is its first float among a corner's custom floats, plus eight
# times its width. See `NodeGraph.attribute`.
comptime NODE_ATTRIBUTE = NodeKind(100)
# How many floats a corner carries for the custom attributes, all of them.
comptime MAX_ATTRIBUTE_FLOATS = 8
# A cube texture read in a direction, three.js's `cubeTexture(map, dir)`
# and GLSL's `textureCube`. See `NodeSource.sample_cube`.
comptime NODE_TEXTURE_CUBE = NodeKind(101)
# A 3D texture read at a `vec3`, three.js's `texture3D(map, uvw)` and
# GLSL's `sampler3D`, and an array texture read at a coordinate and a
# layer, GLSL's `sampler2DArray`. See `NodeSource.sample_3d` and
# `NodeSource.sample_array`.
comptime NODE_TEXTURE_3D = NodeKind(102)
comptime NODE_TEXTURE_ARRAY = NodeKind(103)
# Where a fragment is in its point, GLSL's `gl_PointCoord`: zero to one
# across from the left and down from the top. A leaf numbered after the
# operations; see `point_coord`.
comptime NODE_POINT_COORD = NodeKind(104)
# Where the fragment is on the target, zero to one from the bottom left,
# three.js's `screenUV`; and the opaque scene behind the surface read at a
# place on the target, three.js's `viewportSharedTexture`. Leaves numbered
# after the operations; see `screen_uv` and `viewport_texture`.
comptime NODE_SCREEN_UV = NodeKind(105)
comptime NODE_VIEWPORT_TEXTURE = NodeKind(106)
# What a light's shadow lets through to the fragment, a `vec3`, one for all
# of it: the argument of three.js's `receivedShadowNode`. A leaf numbered
# after the operations; see `shadow`.
comptime NODE_SHADOW = NodeKind(107)
# A compute program's leaves; see `materials.compute_nodes`. One of the
# invocation's numbers, three.js's `instanceIndex` and the compute
# builtins; an element of a storage buffer or a workgroup array, read at
# the index its one input computes; and what an earlier statement of the
# program left. Only a compute program reads them.
comptime NODE_COMPUTE_BUILTIN = NodeKind(108)
comptime NODE_STORAGE_ELEMENT = NodeKind(109)
comptime NODE_COMPUTE_RESULT = NodeKind(110)
# An explicit two-dimensional gradient pair packed into input C. Input A
# is the coordinate; input B is the sampler, as for NODE_TEXTURE_LEVEL.
comptime NODE_TEXTURE_GRAD = NodeKind(111)

# Integer operations use bitcast payloads, never float arithmetic.
comptime NODE_UINT_ADD = NodeKind(112)
comptime NODE_UINT_SUB = NodeKind(113)
comptime NODE_UINT_MUL = NodeKind(114)
comptime NODE_UINT_DIV = NodeKind(115)
comptime NODE_UINT_MOD = NodeKind(116)
comptime NODE_UINT_MIN = NodeKind(117)
comptime NODE_UINT_MAX = NodeKind(118)
comptime NODE_UINT_CLAMP = NodeKind(119)
comptime NODE_UINT_NEGATE = NodeKind(120)
comptime NODE_UINT_BIT_AND = NodeKind(121)
comptime NODE_UINT_BIT_OR = NodeKind(122)
comptime NODE_UINT_BIT_XOR = NodeKind(123)
comptime NODE_UINT_BIT_NOT = NodeKind(124)
comptime NODE_UINT_SHIFT_LEFT = NodeKind(125)
comptime NODE_UINT_SHIFT_RIGHT = NodeKind(126)
comptime NODE_UINT_LESS_THAN = NodeKind(127)
comptime NODE_UINT_LESS_THAN_EQUAL = NodeKind(128)
comptime NODE_UINT_GREATER_THAN = NodeKind(129)
comptime NODE_UINT_GREATER_THAN_EQUAL = NodeKind(130)
comptime NODE_UINT_EQUAL = NodeKind(131)
comptime NODE_UINT_NOT_EQUAL = NodeKind(132)
comptime NODE_TO_UINT = NodeKind(133)
comptime NODE_UINT_TO_FLOAT = NodeKind(134)
comptime NODE_UINT_TO_INT = NodeKind(135)
comptime NODE_UINT_TO_BOOL = NodeKind(136)
comptime NODE_INT_ADD = NodeKind(137)
comptime NODE_INT_SUB = NodeKind(138)
comptime NODE_INT_MUL = NodeKind(139)
comptime NODE_INT_DIV = NodeKind(140)
comptime NODE_INT_MOD = NodeKind(141)
comptime NODE_INT_MIN = NodeKind(142)
comptime NODE_INT_MAX = NodeKind(143)
comptime NODE_INT_CLAMP = NodeKind(144)
comptime NODE_INT_NEGATE = NodeKind(145)
comptime NODE_INT_BIT_AND = NodeKind(146)
comptime NODE_INT_BIT_OR = NodeKind(147)
comptime NODE_INT_BIT_XOR = NodeKind(148)
comptime NODE_INT_BIT_NOT = NodeKind(149)
comptime NODE_INT_SHIFT_LEFT = NodeKind(150)
comptime NODE_INT_SHIFT_RIGHT = NodeKind(151)
comptime NODE_INT_LESS_THAN = NodeKind(152)
comptime NODE_INT_LESS_THAN_EQUAL = NodeKind(153)
comptime NODE_INT_GREATER_THAN = NodeKind(154)
comptime NODE_INT_GREATER_THAN_EQUAL = NodeKind(155)
comptime NODE_INT_EQUAL = NodeKind(156)
comptime NODE_INT_NOT_EQUAL = NodeKind(157)
comptime NODE_TO_INT = NodeKind(158)
comptime NODE_INT_TO_FLOAT = NodeKind(159)
comptime NODE_INT_TO_UINT = NodeKind(160)
comptime NODE_INT_TO_BOOL = NodeKind(161)
comptime NODE_INT_ABS = NodeKind(162)
comptime NODE_INT_SIGN = NodeKind(163)
comptime NODE_UINT_FIRST = NODE_UINT_ADD
comptime NODE_UINT_LAST = NODE_UINT_TO_BOOL
comptime NODE_INT_FIRST = NODE_INT_ADD
comptime NODE_INT_LAST = NODE_INT_SIGN


def _integer_type(type: ValueType, width: Int) -> ValueType:
    """Return a register type of the same family and a new width."""
    return ValueType(
        width + (40 if type.is_unsigned() else (44 if type.is_signed() else 0))
    )


def _uint_kind(kind: NodeKind) -> NodeKind:
    """Map a supported numeric operation to its exact unsigned kind.

    Return an invalid kind for float-only math and logic.
    """
    if kind == NODE_ADD:
        return NODE_UINT_ADD
    if kind == NODE_SUB:
        return NODE_UINT_SUB
    if kind == NODE_MUL:
        return NODE_UINT_MUL
    if kind == NODE_DIV:
        return NODE_UINT_DIV
    if kind == NODE_MOD:
        return NODE_UINT_MOD
    if kind == NODE_MIN:
        return NODE_UINT_MIN
    if kind == NODE_MAX:
        return NODE_UINT_MAX
    if kind == NODE_CLAMP:
        return NODE_UINT_CLAMP
    if kind == NODE_NEGATE:
        return NODE_UINT_NEGATE
    if kind == NODE_BIT_AND:
        return NODE_UINT_BIT_AND
    if kind == NODE_BIT_OR:
        return NODE_UINT_BIT_OR
    if kind == NODE_BIT_XOR:
        return NODE_UINT_BIT_XOR
    if kind == NODE_BIT_NOT:
        return NODE_UINT_BIT_NOT
    if kind == NODE_SHIFT_LEFT:
        return NODE_UINT_SHIFT_LEFT
    if kind == NODE_SHIFT_RIGHT:
        return NODE_UINT_SHIFT_RIGHT
    if kind == NODE_LESS_THAN:
        return NODE_UINT_LESS_THAN
    if kind == NODE_LESS_THAN_EQUAL:
        return NODE_UINT_LESS_THAN_EQUAL
    if kind == NODE_GREATER_THAN:
        return NODE_UINT_GREATER_THAN
    if kind == NODE_GREATER_THAN_EQUAL:
        return NODE_UINT_GREATER_THAN_EQUAL
    if kind == NODE_EQUAL:
        return NODE_UINT_EQUAL
    if kind == NODE_NOT_EQUAL:
        return NODE_UINT_NOT_EQUAL
    return NodeKind(-1)


def _int_kind(kind: NodeKind) -> NodeKind:
    """Map a supported numeric operation to its exact signed kind."""
    if kind == NODE_ABS:
        return NODE_INT_ABS
    if kind == NODE_SIGN:
        return NODE_INT_SIGN
    var mapped = _uint_kind(kind)
    return NodeKind(
        mapped.value + NODE_INT_ADD.value - NODE_UINT_ADD.value
    ) if mapped.is_valid() else mapped


def _refuse_integer_operation(operation: NodeKind, verb: String) raises:
    """Refuse an integer operation this graph does not have.

    Nothing. The call returns when the kind is named.

    Args:
        operation: The kind chosen for the integer form.
        verb: The operation's name in the error.

    Raises:
        Error: If the kind is not named.
    """
    if not operation.is_valid():
        raise Error("A node graph cannot " + verb + " an exact integer")


comptime COLOR_NODE = NodeOutput(0)
comptime EMISSIVE_NODE = NodeOutput(2)
comptime NORMAL_NODE = NodeOutput(3)
comptime POSITION_NODE = NodeOutput(4)
comptime OUTPUT_NODE = NodeOutput(5)
comptime BACKDROP_NODE = NodeOutput(10)
comptime RECEIVED_SHADOW_NODE = NodeOutput(15)
# three.js's `MeshSSSNodeMaterial`: the color of the light through, and
# the five numbers that shape it. See `materials.mesh_sss_node_material`.
comptime THICKNESS_COLOR_NODE = NodeOutput(17)


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
        return ordinal_valid(self.value, NODE_CONTEXT_COUNT - 1)

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


def _letter_of(lane: Int) -> String:
    """Return the swizzle letter of a lane."""
    if lane == 0:
        return "x"
    if lane == 1:
        return "y"
    return "z" if lane == 2 else "w"


def _without(row: Int) -> String:
    """Return the swizzle of a `vec4`'s three lanes other than `row`."""
    if row == 0:
        return "yzw"
    if row == 1:
        return "xzw"
    return "xyw" if row == 2 else "xyz"


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


def _note_place(mut places: List[Int], place: Int):
    """Append a place to a list, once."""
    if first_match(places, place) >= 0:
        return
    places.append(place)


def _pool_size(type: ValueType) -> Int:
    """Return how many floats a constant or a uniform of a type holds."""
    return 9 if type == NODE_MAT3 else (16 if type == NODE_MAT4 else 4)


def _is_attribute(kind: NodeKind) -> Bool:
    """Return True for a node that reads the surface where it runs."""
    return (
        (kind.value >= NODE_UV.value and kind.value <= NODE_VERTEX_COLOR.value)
        or kind == NODE_LIT
        or kind == NODE_FRAG_COORD
        or kind == NODE_FRONT_FACING
        or kind == NODE_ATTRIBUTE
        or kind == NODE_POINT_COORD
        or kind == NODE_SCREEN_UV
        or kind == NODE_SHADOW
    )


def _is_compute(kind: NodeKind) -> Bool:
    """Return True for a node only a compute program reads."""
    return (
        kind == NODE_COMPUTE_BUILTIN
        or kind == NODE_STORAGE_ELEMENT
        or kind == NODE_COMPUTE_RESULT
    )


# The nodes other than the attributes that read a surface: the texture
# reads, the scene behind, varyings and derivatives. The last lanes repeat
# the first.
comptime _SURFACE_READS = SIMD[DType.int32, 16](
    Int32(NODE_TEXTURE.value),
    Int32(NODE_TEXTURE_LEVEL.value),
    Int32(NODE_TEXEL_FETCH.value),
    Int32(NODE_TEXTURE_SIZE.value),
    Int32(NODE_TEXTURE_CUBE.value),
    Int32(NODE_TEXTURE_3D.value),
    Int32(NODE_TEXTURE_ARRAY.value),
    Int32(NODE_VIEWPORT_TEXTURE.value),
    Int32(NODE_VARYING.value),
    Int32(NODE_DFDX.value),
    Int32(NODE_DFDY.value),
    Int32(NODE_TEXTURE_GRAD.value),
    Int32(NODE_TEXTURE.value),
    Int32(NODE_TEXTURE.value),
    Int32(NODE_TEXTURE.value),
    Int32(NODE_TEXTURE.value),
)


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
    # A loop's two hidden variables: `live`, which a `Break` clears, and
    # `skip`, which a `Continue` sets for the rest of the time through.
    # `stopped` is set once either has been called in the body, and from
    # then on each assignment in the loop is kept only where both allow.
    var live: Int
    var skip: Int
    var stopped: Bool


@fieldwise_init
struct _Return(Copyable, Movable):
    """One `Fn` call being built: its hidden variables `returned` and
    `result`, and how many blocks were open when it began."""

    var returned: Int
    var result: Int
    var depth: Int
    var used: Bool
