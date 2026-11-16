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

A graph sets up to twenty-five outputs, each three.js's property of the same name:

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
- `SIZE_NODE`, a `float`: three.js's `sizeNode` and GLSL's `gl_PointSize`,
  a point's width in pixels. It runs on the host, once per point, and
  replaces the material's size and its attenuation. Only a point reads it.
- `BACKDROP_NODE`, a `vec3`: three.js's `backdropNode`. It replaces the
  diffuse light, mixed by `BACKDROP_ALPHA_NODE`, a `float`, where that is
  set. The specular light and the glow are added after it.
- `FRAGMENT_NODE`, a `vec4`: three.js's `fragmentNode`, the fragment's
  color and alpha in place of all the material's own shading. The fog
  veils it; the alpha test and the output node do not run.
- `ROUGHNESS_NODE` and `METALNESS_NODE`, `float`s: three.js's
  `roughnessNode` and `metalnessNode`. They replace a standard or physical
  surface's roughness and metalness, their maps included.
- `RECEIVED_SHADOW_NODE`, a `vec3`: three.js's `receivedShadowNode`. It
  runs once for each light that casts a shadow on the surface, and the
  `shadow` node reads what the light's shadow lets through, a `vec3`. The
  light's color is multiplied by it in place of the shadow. See
  `ProgramShape`.
- `CAST_SHADOW_NODE`, a `vec4`: three.js's `castShadowNode`, the color and
  alpha a light sees through the surface where it casts a shadow. It runs
  in the shadow pass, under `Renderer.shadow_map_transmitted`, in place of
  opaque black, and the map's alpha multiplies its alpha. See
  `lights.shadow`.
- `THICKNESS_COLOR_NODE`, a `vec3`, and `THICKNESS_DISTORTION_NODE`,
  `THICKNESS_AMBIENT_NODE`, `THICKNESS_ATTENUATION_NODE`,
  `THICKNESS_POWER_NODE` and `THICKNESS_SCALE_NODE`, `float`s: three.js's
  `MeshSSSNodeMaterial`. A `PHYSICAL` surface whose graph sets the color
  lets each light with a direction through from behind. See
  `materials.mesh_sss_node_material`.
- `SCATTERING_NODE` and `OFFSET_NODE`, `float`s: three.js's
  `VolumeNodeMaterial`'s `scatteringNode` and `offsetNode`. A `VOLUME`
  surface runs the scattering node once at each step of its ray, with the
  world position at that step, and moves the ray's start by the offset.
  See `materials.volume_node_material`.

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
four 32-bit words. Float nodes use Float32 values. Exact integer nodes
bitcast UInt32 payloads into these words. No float arithmetic reads those
payloads. The compiler gives a register back when the last reader of its
value has run, so an output can hold up to `MAX_INSTRUCTIONS` instructions
while no more than `MAX_REGISTERS` values are alive at once.

**Exact integers.** `uint` and `uvec2` through `uvec4` retain all 32 bits.
The signed types produced by `uint_to_int` also retain all 32 bits. Integer
arithmetic wraps modulo 2 ** 32. Division or remainder by zero returns zero.
A shift count of 32 or more returns zero. Signed division truncates toward
zero; the minimum signed value divided by minus one wraps. These bounded
results define cases that GLSL leaves undefined. `to_uint` and `to_int`
truncate float values toward zero. Unsigned conversion accepts values from
zero through values below 2 ** 32. Signed conversion accepts values from
-2 ** 31 through values below 2 ** 31. Out-of-range and nonfinite inputs
return zero. Integer-to-integer conversions reinterpret all 32 bits.
`unsigned` remains the legacy float-backed conversion for existing callers.
Use `uint_to_float` or `int_to_float` before float-only math or shader outputs.

**Compute programs.** `materials.compute_nodes` builds three.js's compute
nodes on a graph: its statements' roots are laid out by `compile_roots`
and run by `run_code`, and the compute leaves read the invocation, the
storage buffers and the statements' results through `NodeSource`.

**Texture footprints.** An ordinary texture node reads its image at the
level the surface's own coordinates pick. WebGPU instead measures the
derivatives of the coordinate the node computes.
"""

from materials.node_program_id import NO_NODES, NodeProgramId
from materials.node_program import (
    AO_NODE,
    BACKDROP_ALPHA_NODE,
    CAST_SHADOW_NODE,
    DEPTH_NODE,
    FRAGMENT_NODE,
    Lanes,
    MASK_NODE,
    METALNESS_NODE,
    NODE_FLOAT,
    NODE_MAT3,
    NODE_MAT4,
    NODE_OUTPUT_COUNT,
    NODE_SAMPLER,
    NODE_SAMPLER_3D,
    NODE_SAMPLER_ARRAY,
    NODE_SAMPLER_CUBE,
    NODE_UVEC3,
    NODE_VEC2,
    NODE_VEC3,
    NODE_VEC4,
    NodeOutput,
    NodeProgram,
    NodeProgramStore,
    OFFSET_NODE,
    OPACITY_NODE,
    PROGRAM_HEADER,
    PROGRAM_TIME,
    PROGRAM_VIEW,
    INSTRUCTION_A,
    INSTRUCTION_B,
    INSTRUCTION_C,
    INSTRUCTION_DEST,
    INSTRUCTION_FLOATS,
    INSTRUCTION_IMMEDIATE,
    INSTRUCTION_OP,
    MAX_INSTRUCTIONS,
    MAX_REGISTERS,
    ROUGHNESS_NODE,
    SCATTERING_NODE,
    SIZE_NODE,
    THICKNESS_AMBIENT_NODE,
    THICKNESS_ATTENUATION_NODE,
    THICKNESS_DISTORTION_NODE,
    THICKNESS_POWER_NODE,
    THICKNESS_SCALE_NODE,
    ValueType,
    require_node_output,
    require_unsigned_width,
)
from core.ordinal import (
    index_in_count,
    ordinal_valid,
    require_index_in_count,
    require_valid,
    require_non_negative,
    require_positive,
)
from core.extent import require_closed_count
from core.search import first_match

from lights.shadow import ShadowShape
from materials.compute_ids import (
    ComputeBuiltin,
    ComputeStatementId,
    StorageBufferId,
    WorkgroupArrayId,
)
from math.arc_tangent import atan2_float32, atan_float32
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.square_matrix import copy_elements
from math.smoothstep import smoothstep
from math.vector2 import Vector2
from math.norm import squared_length3
from math.vector3 import Vector3, weighted_sum3
from math.vector4 import Vector4
from render.framebuffer import Color, FloatColor, OPAQUE_WHITE
from render.cube_texture_store import NO_CUBE_TEXTURE, CubeTextureId
from render.volume_texture_store import (
    NO_DATA_3D_TEXTURE,
    NO_DATA_ARRAY_TEXTURE,
    Data3DTextureId,
    DataArrayTextureId,
)
from render.texture_store import NO_TEXTURE, TextureId
from render.texture import anisotropic_footprint
from std.math import (
    ceil,
    cos,
    exp,
    exp2,
    floor,
    isfinite,
    log2,
    max,
    min,
    pow,
    sin,
    sqrt,
)
from std.memory import bitcast

from materials.node_opcodes import (
    AT_FRAGMENT,
    AT_HERE,
    AT_RIGHT,
    AT_UP,
    BACKDROP_NODE,
    COLOR_NODE,
    CORNER_A,
    CORNER_B,
    CORNER_C,
    EMISSIVE_NODE,
    MAX_ATTRIBUTE_FLOATS,
    MAX_GRAPH_NODES,
    MAX_LOOP_COUNT,
    NODE_ABS,
    NODE_ACOS,
    NODE_ADD,
    NODE_AND,
    NODE_ASIN,
    NODE_ATAN,
    NODE_ATAN2,
    NODE_ATTRIBUTE,
    NODE_BIT_AND,
    NODE_BIT_NOT,
    NODE_BIT_OR,
    NODE_BIT_XOR,
    NODE_CAMERA_POSITION,
    NODE_CEIL,
    NODE_CELL_NOISE,
    NODE_CELL_NOISE_VEC3,
    NODE_CLAMP,
    NODE_COMPUTE_BUILTIN,
    NODE_COMPUTE_RESULT,
    NODE_CONSTANT,
    NODE_CONTEXT_COUNT,
    NODE_COPY,
    NODE_COS,
    NODE_CROSS,
    NODE_DEGREES,
    NODE_DFDX,
    NODE_DFDY,
    NODE_DISTANCE,
    NODE_DIV,
    NODE_DOT,
    NODE_EQUAL,
    NODE_EXP,
    NODE_EXP2,
    NODE_FACEFORWARD,
    NODE_FLOOR,
    NODE_FRACT,
    NODE_FRAG_COORD,
    NODE_FRONT_FACING,
    NODE_GREATER_THAN,
    NODE_GREATER_THAN_EQUAL,
    NODE_INTERPOLATE,
    NODE_INT,
    NODE_INT_ABS,
    NODE_INT_ADD,
    NODE_INT_BIT_AND,
    NODE_INT_BIT_NOT,
    NODE_INT_BIT_OR,
    NODE_INT_BIT_XOR,
    NODE_INT_CLAMP,
    NODE_INT_DIV,
    NODE_INT_EQUAL,
    NODE_INT_FIRST,
    NODE_INT_GREATER_THAN,
    NODE_INT_GREATER_THAN_EQUAL,
    NODE_INT_LAST,
    NODE_INT_LESS_THAN,
    NODE_INT_LESS_THAN_EQUAL,
    NODE_INT_MAX,
    NODE_INT_MIN,
    NODE_INT_MOD,
    NODE_INT_MUL,
    NODE_INT_NEGATE,
    NODE_INT_NOT_EQUAL,
    NODE_INT_SHIFT_LEFT,
    NODE_INT_SHIFT_RIGHT,
    NODE_INT_SIGN,
    NODE_INT_SUB,
    NODE_INT_TO_BOOL,
    NODE_INT_TO_FLOAT,
    NODE_INT_TO_UINT,
    NODE_INVERSE_SQRT,
    NODE_IVEC2,
    NODE_IVEC3,
    NODE_IVEC4,
    NODE_JOIN,
    NODE_LENGTH,
    NODE_LESS_THAN,
    NODE_LESS_THAN_EQUAL,
    NODE_LIT,
    NODE_LOG,
    NODE_LOG2,
    NODE_MATRIX_COLUMNS,
    NODE_MATRIX_TAIL,
    NODE_MATRIX_VECTOR,
    NODE_MAX,
    NODE_MIN,
    NODE_MIX,
    NODE_MOD,
    NODE_MUL,
    NODE_NEGATE,
    NODE_NOISE,
    NODE_NOISE_VEC3,
    NODE_NORMALIZE,
    NODE_NORMAL_LOCAL,
    NODE_NORMAL_VIEW,
    NODE_NORMAL_WORLD,
    NODE_NOT,
    NODE_NOT_EQUAL,
    NODE_ONE_MINUS,
    NODE_OR,
    NODE_POINT_COORD,
    NODE_POSITION_LOCAL,
    NODE_POSITION_VIEW,
    NODE_POSITION_WORLD,
    NODE_POW,
    NODE_RADIANS,
    NODE_RECIPROCAL,
    NODE_REFLECT,
    NODE_REFRACT,
    NODE_ROUND,
    NODE_SATURATE,
    NODE_SCREEN_UV,
    NODE_SELECT,
    NODE_SHADOW,
    NODE_SHIFT_LEFT,
    NODE_SHIFT_RIGHT,
    NODE_SIGN,
    NODE_SIN,
    NODE_SMOOTHSTEP,
    NODE_SQRT,
    NODE_STEP,
    NODE_STORAGE_ELEMENT,
    NODE_SUB,
    NODE_SWIZZLE,
    NODE_TAN,
    NODE_TEXEL_FETCH,
    NODE_TEXTURE,
    NODE_TEXTURE_3D,
    NODE_TEXTURE_ARRAY,
    NODE_TEXTURE_CUBE,
    NODE_TEXTURE_GRAD,
    NODE_TEXTURE_LEVEL,
    NODE_TEXTURE_SIZE,
    NODE_TIME,
    NODE_TO_INT,
    NODE_TO_UINT,
    NODE_TRUNC,
    NODE_UINT,
    NODE_UINT_ADD,
    NODE_UINT_BIT_AND,
    NODE_UINT_BIT_NOT,
    NODE_UINT_BIT_OR,
    NODE_UINT_BIT_XOR,
    NODE_UINT_CLAMP,
    NODE_UINT_DIV,
    NODE_UINT_EQUAL,
    NODE_UINT_FIRST,
    NODE_UINT_GREATER_THAN,
    NODE_UINT_GREATER_THAN_EQUAL,
    NODE_UINT_LAST,
    NODE_UINT_LESS_THAN,
    NODE_UINT_LESS_THAN_EQUAL,
    NODE_UINT_MAX,
    NODE_UINT_MIN,
    NODE_UINT_MOD,
    NODE_UINT_MUL,
    NODE_UINT_NEGATE,
    NODE_UINT_NOT_EQUAL,
    NODE_UINT_SHIFT_LEFT,
    NODE_UINT_SHIFT_RIGHT,
    NODE_UINT_SUB,
    NODE_UINT_TO_BOOL,
    NODE_UINT_TO_FLOAT,
    NODE_UINT_TO_INT,
    NODE_UNIFORM,
    NODE_UNSIGNED,
    NODE_UV,
    NODE_UVEC2,
    NODE_UVEC4,
    NODE_VARYING,
    NODE_VECTOR_MATRIX,
    NODE_VERTEX_COLOR,
    NODE_VIEWPORT_TEXTURE,
    NODE_VIEW_MATRIX,
    NODE_WORLEY,
    NODE_XOR,
    NORMAL_NODE,
    NodeContext,
    NodeKind,
    NodeRef,
    NodeVar,
    OUTPUT_NODE,
    POSITION_NODE,
    RECEIVED_SHADOW_NODE,
    THICKNESS_COLOR_NODE,
    _BLOCK_ELSE,
    _BLOCK_LOOP,
    _BLOCK_THEN,
    _Block,
    _Return,
    _SURFACE_READS,
    _int_kind,
    _integer_type,
    _is_attribute,
    _is_compute,
    _lane_of,
    _letter_of,
    _note_place,
    _pool_size,
    _refuse_integer_operation,
    _uint_kind,
    _without,
    require_program_code,
)
from materials.node_vm import (
    NodeInputs,
    NodeSource,
    ProgramShape,
    ProgramSource,
    Whole,
    _bits,
    _bjfinal,
    _bjmix,
    _camera_position,
    _cells,
    _dot,
    _fade,
    _float_integer_bits,
    _gradient,
    _hash,
    _hash_of,
    _in_kinds,
    _int_operation,
    _is_leaf,
    _is_signed_operation,
    _joined,
    _lane_by_lane,
    _lanes,
    _late_leaf_bit,
    _leaf,
    _matrix,
    _normalized,
    _operation,
    _per_lane,
    _perlin,
    _pick,
    _reads_a_map,
    _rotl32,
    _round,
    _step,
    _to_01,
    _truth,
    _uint_operation,
    _unit,
    _view_normal,
    _view_point,
    _whole,
    cell_noise,
    cell_noise_vec3,
    has_output,
    here_inputs,
    moved_position,
    node_attributes,
    node_depth,
    offset_normal,
    perlin_noise,
    perlin_noise_vec3,
    perspective_shares,
    perspective_shares_over,
    point_size_of,
    run_code,
    run_nodes,
    worley_noise,
)


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
        graph.open_call(self.output)
        var answer = self.body(graph, args)
        if len(graph._blocks) != depth:
            raise Error("The Fn " + self.name + " leaves an If or a Loop open")
        answer = graph.close_call(answer)
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


def _require_noise_point(type: ValueType, name: String) raises:
    """Refuse a noise point that is neither a vec2 nor a vec3.

    Nothing. The call returns when the point is a vec2 or a vec3.

    Args:
        type: The point's type.
        name: Which noise reads the point.

    Raises:
        Error: If the point is another type.
    """
    if type != NODE_VEC2 and type != NODE_VEC3:
        raise Error(name + " reads a vec2 or a vec3, not a " + type.name())


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
    # Each `Fn` call being built, innermost last.
    var _returns: List[_Return]
    # Per variable, whether it is a closed loop's or call's hidden flag,
    # which no later loop needs to carry.
    var _retired: List[Bool]
    # Each custom attribute: its name, its first float among a corner's
    # custom floats, and its width.
    var _attribute_names: List[String]
    var _attribute_offsets: List[Int]
    var _attribute_widths: List[Int]

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
        self._returns = List[_Return]()
        self._retired = List[Bool]()
        self._attribute_names = List[String]()
        self._attribute_offsets = List[Int]()
        self._attribute_widths = List[Int]()

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
            output: One of the twenty-five outputs.

        Returns:
            The node's ref.

        Raises:
            Error: If the output is none of the twenty-five.
        """
        require_node_output(output)
        return NodeRef(self._outputs[output.value])

    def _check(self, node: NodeRef) raises:
        """Refuse a ref that names no node of this graph.

        Raises:
            Error: If the ref is negative or past the last node.
        """
        require_index_in_count(
            node.value,
            self.count(),
            "A node graph has no node with that ref",
        )

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

    def int32(mut self, x: Int32) -> NodeRef:
        """Return an exact signed 32-bit constant.

        Args:
            x: The signed value.

        Returns:
            The node, retaining every bit.
        """
        return self._add(
            NODE_CONSTANT,
            NODE_INT,
            value=Lanes(bitcast[DType.float32](x), 0, 0, 0),
        )

    def uint(mut self, x: UInt32) -> NodeRef:
        """Return an exact constant `uint`.

        Args:
            x: An unsigned component.

        Returns:
            The node, with all 32 bits of each component.
        """
        return self._add(
            NODE_CONSTANT,
            NODE_UINT,
            value=Lanes(bitcast[DType.float32](x), 0, 0, 0),
        )

    def uvec2(mut self, x: UInt32, y: UInt32) -> NodeRef:
        """Return an exact constant `uvec2`.

        Args:
            x: An unsigned component.
            y: An unsigned component.

        Returns:
            The node, with all 32 bits of each component.
        """
        return self._add(
            NODE_CONSTANT,
            NODE_UVEC2,
            value=Lanes(
                bitcast[DType.float32](x), bitcast[DType.float32](y), 0, 0
            ),
        )

    def uvec3(mut self, x: UInt32, y: UInt32, z: UInt32) -> NodeRef:
        """Return an exact constant `uvec3`.

        Args:
            x: An unsigned component.
            y: An unsigned component.
            z: An unsigned component.

        Returns:
            The node, with all 32 bits of each component.
        """
        return self._add(
            NODE_CONSTANT,
            NODE_UVEC3,
            value=Lanes(
                bitcast[DType.float32](x),
                bitcast[DType.float32](y),
                bitcast[DType.float32](z),
                0,
            ),
        )

    def uvec4(mut self, x: UInt32, y: UInt32, z: UInt32, w: UInt32) -> NodeRef:
        """Return an exact constant `uvec4`.

        Args:
            x: An unsigned component.
            y: An unsigned component.
            z: An unsigned component.
            w: An unsigned component.

        Returns:
            The node, with all 32 bits of each component.
        """
        return self._add(
            NODE_CONSTANT,
            NODE_UVEC4,
            value=Lanes(
                bitcast[DType.float32](x),
                bitcast[DType.float32](y),
                bitcast[DType.float32](z),
                bitcast[DType.float32](w),
            ),
        )

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

    def uniform_uint(mut self, name: String, type: ValueType) raises -> NodeRef:
        """Return a zero-initialized exact unsigned uniform.

        Args:
            name: A unique nonempty name.
            type: `NODE_UINT` or an unsigned vector type.

        Returns:
            The named zero value with the requested unsigned width.

        Raises:
            Error: If the type is not unsigned or the name is invalid.
        """
        if not type.is_unsigned():
            raise Error("An unsigned uniform requires an unsigned type")
        return self._uniform(name, type, Lanes(0))

    def uniform_uint(mut self, name: String, value: UInt32) raises -> NodeRef:
        """Create an exact unsigned scalar uniform.

        Args:
            name: The uniform's name.
            value: The unsigned value, retaining all bits.

        Returns:
            The new node.

        Raises:
            Error: If the name or the requested type is invalid.
        """
        return self.uniform_uint[1](name, value)

    def uniform_uint(
        mut self, name: String, value: SIMD[DType.uint32, 2]
    ) raises -> NodeRef:
        """Create an exact unsigned 2-component vector uniform.

        Args:
            name: The uniform's name.
            value: The unsigned value, retaining all bits.

        Returns:
            The new node.

        Raises:
            Error: If the name or the requested type is invalid.
        """
        return self.uniform_uint[2](name, value)

    def uniform_uint(
        mut self, name: String, x: UInt32, y: UInt32, z: UInt32
    ) raises -> NodeRef:
        """Create an exact unsigned three-component uniform.

        Mojo SIMD widths are powers of two. This overload supplies three
        components without requiring an unsupported SIMD width.

        Args:
            name: The uniform's name.
            x: The first unsigned component.
            y: The second unsigned component.
            z: The third unsigned component.

        Returns:
            The new node.

        Raises:
            Error: If the name or the requested type is invalid.
        """
        return self._uniform(
            name,
            NODE_UVEC3,
            Lanes(
                bitcast[DType.float32](x),
                bitcast[DType.float32](y),
                bitcast[DType.float32](z),
                0,
            ),
        )

    def uniform_uint(
        mut self, name: String, value: SIMD[DType.uint32, 4]
    ) raises -> NodeRef:
        """Create an exact unsigned 4-component vector uniform.

        Args:
            name: The uniform's name.
            value: The unsigned value, retaining all bits.

        Returns:
            The new node.

        Raises:
            Error: If the name or the requested type is invalid.
        """
        return self.uniform_uint[4](name, value)

    def uniform_uint[
        width: Int
    ](
        mut self, name: String, value: SIMD[DType.uint32, width]
    ) raises -> NodeRef:
        """Return a named exact unsigned scalar or vector.

        Args:
            name: A unique nonempty uniform name.
            value: One, two, or four unsigned components.

        Returns:
            The unsigned node, retaining every bit.

        Raises:
            Error: If the width is outside one through four, or the name
                is empty or already used.
        """
        require_unsigned_width(width)
        var lanes = Lanes(0)
        for lane in range(width):  # pragma: no branch
            lanes[lane] = bitcast[DType.float32](value[lane])
        return self._uniform(name, ValueType(40 + width), lanes)

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
        self._matrices.extend(Span(elements))
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
        return self._matrix_uniform(
            name, NODE_MAT3, copy_elements(value.elements)
        )

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
        return self._matrix_uniform(
            name, NODE_MAT4, copy_elements(value.elements)
        )

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

    def cube_uniform(
        mut self, name: String, map: CubeTextureId = NO_CUBE_TEXTURE
    ) raises -> NodeRef:
        """Return a named cube texture the caller can change between frames,
        three.js's `cubeTexture(map)` whose `value` is set later. Read it
        with `texture_cube`, and change it with `NodeProgram.set_cube`.

        Args:
            name: A name no other uniform of this graph has.
            map: Its first cube, or `NO_CUBE_TEXTURE` for one set later.

        Returns:
            The node, of type `cubeTexture`.

        Raises:
            Error: If the name is empty or already taken, or `map` is a
                negative other than `NO_CUBE_TEXTURE`.
        """
        if map.value < 0 and map != NO_CUBE_TEXTURE:
            raise Error("A cube uniform names no cube there can be")
        return self._uniform(
            name, NODE_SAMPLER_CUBE, Lanes(Float32(map.value), 0, 0, 0)
        )

    def texture_cube(
        mut self, sampler: NodeRef, direction: NodeRef
    ) raises -> NodeRef:
        """Return a cube texture uniform read in a direction, a linear
        `vec4` with straight alpha: three.js's `cubeTexture(map, dir)` and
        GLSL's `textureCube`. The face the direction points at, read where
        it points. A mode that opens no textures reads opaque white.

        Args:
            sampler: A node of type `cubeTexture`, from `cube_uniform`.
            direction: Which way to look, a `vec3` of any length.

        Returns:
            The node.

        Raises:
            Error: If a node is not of this graph, `sampler` is not a cube
                texture, or `direction` is not a `vec3`.
        """
        self._check(sampler)
        self._check(direction)
        if self._types[sampler.value] != NODE_SAMPLER_CUBE:
            raise Error(
                "A cube read reads a cube texture, not a "
                + self._types[sampler.value].name()
            )
        if self._types[direction.value] != NODE_VEC3:
            raise Error(
                "A cube is read in a vec3 direction, not a "
                + self._types[direction.value].name()
            )
        return self._add(
            NODE_TEXTURE_CUBE, NODE_VEC4, direction.value, sampler.value
        )

    def volume_uniform(
        mut self, name: String, map: Data3DTextureId = NO_DATA_3D_TEXTURE
    ) raises -> NodeRef:
        """Return a named 3D texture the caller can change between frames.
        Read it with `texture_3d`, and change it with
        `NodeProgram.set_volume`.

        Args:
            name: A name no other uniform of this graph has.
            map: Its first 3D texture, or `NO_DATA_3D_TEXTURE`.

        Returns:
            The node, of type `texture3D`.

        Raises:
            Error: If the name is empty or already taken, or `map` is a
                negative other than `NO_DATA_3D_TEXTURE`.
        """
        if map.value < 0 and map != NO_DATA_3D_TEXTURE:
            raise Error("A 3D texture uniform names no texture there can be")
        return self._uniform(
            name, NODE_SAMPLER_3D, Lanes(Float32(map.value), 0, 0, 0)
        )

    def array_uniform(
        mut self,
        name: String,
        map: DataArrayTextureId = NO_DATA_ARRAY_TEXTURE,
    ) raises -> NodeRef:
        """Return a named array texture the caller can change between
        frames. Read it with `texture_array`, and change it with
        `NodeProgram.set_array`.

        Args:
            name: A name no other uniform of this graph has.
            map: Its first array texture, or `NO_DATA_ARRAY_TEXTURE`.

        Returns:
            The node, of type `textureArray`.

        Raises:
            Error: If the name is empty or already taken, or `map` is a
                negative other than `NO_DATA_ARRAY_TEXTURE`.
        """
        if map.value < 0 and map != NO_DATA_ARRAY_TEXTURE:
            raise Error(
                "An array texture uniform names no texture there can be"
            )
        return self._uniform(
            name, NODE_SAMPLER_ARRAY, Lanes(Float32(map.value), 0, 0, 0)
        )

    def texture_3d(mut self, sampler: NodeRef, at: NodeRef) raises -> NodeRef:
        """Return a 3D texture uniform read at a `vec3` from zero to one on
        each axis, a linear `vec4` with straight alpha: three.js's
        `texture3D(map, uvw)` and GLSL's `texture` of a `sampler3D`.

        Args:
            sampler: A node of type `texture3D`, from `volume_uniform`.
            at: Where to read it, a `vec3`.

        Returns:
            The node.

        Raises:
            Error: If a node is not of this graph, `sampler` is not a 3D
                texture, or `at` is not a `vec3`.
        """
        return self._sampled(sampler, at, NODE_SAMPLER_3D, NODE_TEXTURE_3D)

    def texture_array(
        mut self, sampler: NodeRef, at: NodeRef
    ) raises -> NodeRef:
        """Return an array texture uniform read at a coordinate and a layer,
        a `vec3` of `u`, `v` and the layer, a linear `vec4` with straight
        alpha: GLSL's `texture` of a `sampler2DArray`. The layer is rounded
        to the nearest and held inside the stack.

        Args:
            sampler: A node of type `textureArray`, from `array_uniform`.
            at: Where to read it, a `vec3`.

        Returns:
            The node.

        Raises:
            Error: If a node is not of this graph, `sampler` is not an
                array texture, or `at` is not a `vec3`.
        """
        return self._sampled(
            sampler, at, NODE_SAMPLER_ARRAY, NODE_TEXTURE_ARRAY
        )

    def _sampled(
        mut self,
        sampler: NodeRef,
        at: NodeRef,
        type: ValueType,
        kind: NodeKind,
    ) raises -> NodeRef:
        """Return a read of a 3D or an array texture at a `vec3`.

        Raises:
            Error: If a node is not of this graph, or the types are others.
        """
        self._check(sampler)
        self._check(at)
        if self._types[sampler.value] != type:
            raise Error(
                "This read reads a "
                + type.name()
                + ", not a "
                + self._types[sampler.value].name()
            )
        if self._types[at.value] != NODE_VEC3:
            raise Error(
                "A "
                + type.name()
                + " is read at a vec3, not a "
                + self._types[at.value].name()
            )
        return self._add(kind, NODE_VEC4, at.value, sampler.value)

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

    def frag_coord(mut self) -> NodeRef:
        """Return where the fragment is on the target, a `vec4`, GLSL's
        `gl_FragCoord`: the pixel's center in pixels from the bottom left,
        its depth from zero to one, and one. Only a fragment reads it.

        Returns:
            The node.
        """
        return self._add(NODE_FRAG_COORD, NODE_VEC4)

    def point_coord(mut self) -> NodeRef:
        """Return where the fragment is in its point, a `vec2`, GLSL's
        `gl_PointCoord`: zero to one across from the left edge and down
        from the top one. A fragment of a triangle or a line gives zeros.
        Only a fragment reads it.

        Returns:
            The node.
        """
        return self._add(NODE_POINT_COORD, NODE_VEC2)

    def screen_uv(mut self) -> NodeRef:
        """Return where the fragment is on the target, a `vec2`, three.js's
        `screenUV`: zero to one across from the left edge and up from the
        bottom one, at the pixel's center. Only a fragment reads it.

        Returns:
            The node.
        """
        return self._add(NODE_SCREEN_UV, NODE_VEC2)

    def viewport_texture(mut self, at: NodeRef) raises -> NodeRef:
        """Return the opaque scene behind the surface at a place on the
        target, a linear `vec4` with straight alpha: three.js's
        `viewportSharedTexture(uv)`. Read it at `screen_uv` to see what is
        behind the fragment. The renderer draws the opaque scene first for
        a program that reads it, as it does for a transmissive surface. A
        triangle reads it; a point and a line read opaque white.

        Args:
            at: Where to read it, a `vec2`, as `screen_uv` gives it.

        Returns:
            The node.

        Raises:
            Error: If the node is not of this graph or not a `vec2`.
        """
        self._check(at)
        if self._types[at.value] != NODE_VEC2:
            raise Error(
                "The scene behind is read at a vec2, not a "
                + self._types[at.value].name()
            )
        return self._add(NODE_VIEWPORT_TEXTURE, NODE_VEC4, at.value)

    def front_facing(mut self) -> NodeRef:
        """Return one where the fragment's triangle is seen from its front
        and zero where it is seen from its back, a `float`, TSL's
        `frontFacing`. Only a fragment reads it.

        Returns:
            The node.
        """
        return self._add(NODE_FRONT_FACING, NODE_FLOAT)

    def face_direction(mut self) raises -> NodeRef:
        """Return one where the fragment's triangle is seen from its front
        and minus one where it is seen from its back, TSL's
        `faceDirection`.

        Returns:
            The node.

        Raises:
            Error: Never: the operands are floats.
        """
        return self.sub(
            self.mul(self.front_facing(), self.float(2)), self.float(1)
        )

    def gl_front_facing(mut self) -> NodeRef:
        """Return GLSL's `gl_FrontFacing` as three.js's WebGL renderer
        gives it, one or zero: as `front_facing`, except that a
        `BACK_SIDE` material turns the front face round, so it is one on
        every face such a material draws.

        Returns:
            The node.
        """
        return self._add(NODE_FRONT_FACING, NODE_FLOAT, value=Lanes(1))

    def attribute(mut self, name: String, type: ValueType) raises -> NodeRef:
        """Return a custom attribute of the geometry, three.js's
        `attribute(name)`: each corner's value of it, interpolated at the
        fragment. A geometry without it gives zeros and one, as WebGL gives
        an attribute that is not set.

        Args:
            name: The geometry attribute's name.
            type: A `float`, `vec2`, `vec3` or `vec4`.

        Returns:
            The node.

        Raises:
            Error: If the name is a built-in attribute's, the type is not a
                float or a vector, the name was declared with another type,
                or the attributes would hold more than `MAX_ATTRIBUTE_FLOATS`
                floats.
        """
        if (
            name == "position"
            or name == "normal"
            or name == "uv"
            or name == "uv1"
            or name == "color"
        ):
            raise Error(
                name + " is a built-in attribute: read it with its own node"
            )
        if type.value < 1 or type.value > 4:
            raise Error(
                "An attribute is a float or a vector, not a " + type.name()
            )
        var used = 0
        for index in range(len(self._attribute_names)):
            if self._attribute_names[index] == name:
                if self._attribute_widths[index] != type.value:
                    raise Error(
                        "The attribute "
                        + name
                        + " is a "
                        + ValueType(self._attribute_widths[index]).name()
                        + ", not a "
                        + type.name()
                    )
                return self._add_attribute(index)
            used += self._attribute_widths[index]
        if used + type.value > MAX_ATTRIBUTE_FLOATS:
            raise Error(
                "A graph's attributes hold at most "
                + String(MAX_ATTRIBUTE_FLOATS)
                + " floats"
            )
        self._attribute_names.append(name)
        self._attribute_offsets.append(used)
        self._attribute_widths.append(type.value)
        return self._add_attribute(len(self._attribute_names) - 1)

    def _add_attribute(mut self, index: Int) -> NodeRef:
        """Return a node that reads one of the graph's attributes."""
        var width = self._attribute_widths[index]
        return self._add(
            NODE_ATTRIBUTE,
            ValueType(width),
            value=Lanes(Float32(self._attribute_offsets[index] + 8 * width)),
        )

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

    def _require_texture_uv(self, uv: NodeRef) raises:
        """Refuse a texture coordinate that is not a vec2.

        Nothing. The call returns when the node is a vec2.

        Args:
            uv: The coordinate node.

        Raises:
            Error: If the node is not a vec2.
        """
        if self._types[uv.value] != NODE_VEC2:
            raise Error(
                "A texture node reads at a vec2, not a "
                + self._types[uv.value].name()
            )

    def _require_texture_level(self, level: NodeRef) raises:
        """Refuse a mip level that is not a float.

        Nothing. The call returns when the node is a float.

        Args:
            level: The level node.

        Raises:
            Error: If the node is not a float.
        """
        if self._types[level.value] != NODE_FLOAT:
            raise Error(
                "A texture's level is a float, not a "
                + self._types[level.value].name()
            )

    def _require_blocks_closed(self) raises:
        """Refuse a graph that still has an open If or Loop.

        Nothing. The call returns when every block is closed.

        Raises:
            Error: If an If or a Loop is still open.
        """
        if len(self._blocks) > 0:
            raise Error(
                "A node graph has an If or a Loop that End never closed"
            )

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
        require_non_negative(map.value, "A texture node needs a texture")
        self._check(uv)
        self._require_texture_uv(uv)
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
        self._require_texture_uv(uv)
        return self._add(NODE_TEXTURE, NODE_VEC4, uv.value, sampler.value)

    def texture_level(
        mut self, map: TextureId, uv: NodeRef, level: NodeRef
    ) raises -> NodeRef:
        """Return a texture read at a coordinate and a mip level, a linear
        `vec4` with straight alpha: three.js's `texture(map, uv).level(n)`.
        Level zero is the full-size image, and a texture with one level
        reads it at every level.

        Args:
            map: The texture. It must be in the store the renderer draws
                with.
            uv: Where to read it, a `vec2`.
            level: The mip level, a `float`.

        Returns:
            The node.

        Raises:
            Error: If `map` is `NO_TEXTURE` or negative, `uv` is not a
                `vec2`, or `level` is not a `float` of this graph.
        """
        return self._at_level(self.texture(map, uv), level)

    def texture_level(
        mut self, sampler: NodeRef, uv: NodeRef, level: NodeRef
    ) raises -> NodeRef:
        """Return a texture uniform read at a coordinate and a mip level,
        GLSL's `textureLod`.

        Args:
            sampler: A node of type `texture`, from `texture_uniform`.
            uv: Where to read it, a `vec2`.
            level: The mip level, a `float`.

        Returns:
            The node.

        Raises:
            Error: If a node is not of this graph, `sampler` is not a
                texture, `uv` is not a `vec2`, or `level` is not a `float`.
        """
        return self._at_level(self.texture(sampler, uv), level)

    def texture_grad(
        mut self, map: TextureId, uv: NodeRef, dx: NodeRef, dy: NodeRef
    ) raises -> NodeRef:
        """Return a texture read with explicit coordinate gradients.

        Args:
            map: The texture in the renderer's store.
            uv: The already placed coordinate, a `vec2`.
            dx: Coordinate change per screen pixel across, a `vec2`.
            dy: Coordinate change per screen pixel up, a `vec2`.

        Returns:
            A linear `vec4` with straight alpha. Nonfinite runtime inputs
            return transparent black before any texture read.

        Raises:
            Error: If the texture id is negative, a node has the wrong
                type, or a constant gradient is not finite.
        """
        self._check_texture_gradient(dx)
        self._check_texture_gradient(dy)
        var gradients = self.join([dx, dy])
        var texel = self.texture(map, uv)
        return self._with_texture_gradients(texel, gradients)

    def texture_grad(
        mut self, sampler: NodeRef, uv: NodeRef, dx: NodeRef, dy: NodeRef
    ) raises -> NodeRef:
        """Return a texture uniform read with explicit coordinate gradients.

        Args:
            sampler: A `texture` uniform, GLSL's `sampler2D`.
            uv: The already placed coordinate, a `vec2`.
            dx: Coordinate change per screen pixel across, a `vec2`.
            dy: Coordinate change per screen pixel up, a `vec2`.

        Returns:
            A linear `vec4` with straight alpha. Nonfinite runtime inputs
            return transparent black before any texture read.

        Raises:
            Error: If a node has the wrong type or a constant gradient is
                not finite.
        """
        self._check_texture_gradient(dx)
        self._check_texture_gradient(dy)
        var gradients = self.join([dx, dy])
        var texel = self.texture(sampler, uv)
        return self._with_texture_gradients(texel, gradients)

    def _with_texture_gradients(
        mut self, texel: NodeRef, gradients: NodeRef
    ) -> NodeRef:
        """Attach two checked, packed `vec2` gradients as the third input."""
        self._kinds[texel.value] = NODE_TEXTURE_GRAD
        self._inputs[texel.value * 3 + 2] = gradients.value
        return texel

    def _check_texture_gradient(self, gradient: NodeRef) raises:
        """Refuse wrong types and nonfinite source-independent gradients.

        Runtime values cannot raise in the shared renderer interpreter.
        Its texture-gradient leaf rejects nonfinite inputs as transparent
        black instead. Constant expressions are checked here with the same
        bounded interpreter that runs the final program.
        """
        self._check(gradient)
        if self._types[gradient.value] != NODE_VEC2:
            raise Error("A texture gradient must be a vec2")
        var order = self._order(gradient.value)
        for index in range(len(order)):  # pragma: no branch
            var kind = self._kinds[order[index]]
            if (
                kind == NODE_UNIFORM
                or kind == NODE_TIME
                or kind == NODE_CAMERA_POSITION
                or kind == NODE_VIEW_MATRIX
                or _is_attribute(kind)
                or _is_compute(kind)
                or _SURFACE_READS.eq(Int32(kind.value)).reduce_or()
            ):
                return
        var probe = self.copy()
        probe._blocks = List[_Block]()
        probe._discards = List[Int]()
        var starts = List[Int]()
        var program = probe.compile_roots([gradient], starts)
        var source = ProgramSource(Pointer(to=program))
        var value = run_code(source, starts[0], starts[1], source.vertex)
        if not isfinite(value[0]) or not isfinite(value[1]):
            raise Error("A texture gradient must be finite")

    def texture_load(
        mut self, sampler: NodeRef, at: NodeRef, level: NodeRef
    ) raises -> NodeRef:
        """Return the texel of a texture uniform at a column and a row, a
        linear `vec4` with straight alpha: TSL's `textureLoad`, GLSL's
        `texelFetch`. A coordinate outside the image wraps, and a level
        outside the chain is held inside it.

        Args:
            sampler: A node of type `texture`, from `texture_uniform`.
            at: The column and the row, a `vec2` of whole numbers.
            level: The mip level, a `float`.

        Returns:
            The node.

        Raises:
            Error: If a node is not of this graph, `sampler` is not a
                texture, `at` is not a `vec2`, or `level` is not a `float`.
        """
        var texel = self._at_level(self.texture(sampler, at), level)
        self._kinds[texel.value] = NODE_TEXEL_FETCH
        return texel

    def texture_size(
        mut self, sampler: NodeRef, level: NodeRef
    ) raises -> NodeRef:
        """Return a texture uniform's width and height at a level, a
        `vec2`: TSL's `textureSize`, GLSL's `textureSize`.

        Args:
            sampler: A node of type `texture`, from `texture_uniform`.
            level: The mip level, a `float`.

        Returns:
            The node.

        Raises:
            Error: If a node is not of this graph, `sampler` is not a
                texture, or `level` is not a `float`.
        """
        self._check(sampler)
        self._check(level)
        if self._types[sampler.value] != NODE_SAMPLER:
            raise Error(
                "A texture's size is a texture's, not a "
                + self._types[sampler.value].name()
            )
        self._require_texture_level(level)
        return self._add(
            NODE_TEXTURE_SIZE, NODE_VEC2, level.value, sampler.value
        )

    def _at_level(mut self, texel: NodeRef, level: NodeRef) raises -> NodeRef:
        """Turn a texture node just added, which nothing reads yet, into
        one read at a level.

        Raises:
            Error: If `level` is not a `float` of this graph.
        """
        self._check(level)
        self._require_texture_level(level)
        self._kinds[texel.value] = NODE_TEXTURE_LEVEL
        self._inputs[texel.value * 3 + 2] = level.value
        return texel

    def shadow(mut self) -> NodeRef:
        """Return what a light's shadow lets through to the fragment, a
        `vec3` of red, green and blue from zero to one: the argument three.js
        hands its `receivedShadowNode`. Only a `RECEIVED_SHADOW_NODE` reads
        it.

        Returns:
            The node.
        """
        return self._add(NODE_SHADOW, NODE_VEC3)

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
        self._float_vector(a, "interpolate")
        var type = self._types[a.value]
        return self._add(NODE_VARYING, type, a.value)

    # --- math ---------------------------------------------------------------

    def _vector(self, node: NodeRef, verb: String) raises:
        """Refuse a node that is not a scalar or vector register value.

        Raises:
            Error: If the ref names no node of this graph, or the node is a
                matrix or a texture.
        """
        self._check(node)
        var type = self._types[node.value]
        if not type.is_vector():
            raise Error("A node graph cannot " + verb + " a " + type.name())

    def _float_vector(self, node: NodeRef, verb: String) raises:
        """Refuse integer payloads for float-only operations.

        Raises:
            Error: If the node is not a float scalar or vector.
        """
        self._vector(node, verb)
        if self._types[node.value].is_integer():
            raise Error("A node graph cannot " + verb + " an exact integer")

    def _splat(mut self, node: NodeRef, to: ValueType) -> NodeRef:
        """Return scalar bits repeated into every component of `to`."""
        return self._add(NODE_SWIZZLE, to, node.value)

    def _match(
        mut self, node: NodeRef, to: ValueType, verb: String
    ) raises -> NodeRef:
        """Match a numeric family and repeat a scalar when needed.

        Legacy float-backed signed operands can promote to exact signed
        values. Other numeric families must use an explicit conversion.

        Raises:
            Error: If the families differ or the vector widths differ.
        """
        var type = self._types[node.value]
        if type == to:
            return node
        if (
            type.is_signed() != to.is_signed()
            and to.is_signed()
            and not type.is_integer()
            and type.is_vector()
        ):
            return self._match(self.to_int(node), to, verb)
        if (
            type.width() == 1
            and type.is_unsigned() == to.is_unsigned()
            and type.is_signed() == to.is_signed()
            and to.is_vector()
        ):
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
        var width = max(left.width(), right.width())
        if left.is_integer():
            return _integer_type(left, width)
        if right.is_integer():
            return _integer_type(right, width)
        return ValueType(width)

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
        var operation = kind
        var result = type
        if type.is_integer():
            operation = _uint_kind(kind) if type.is_unsigned() else _int_kind(
                kind
            )
            _refuse_integer_operation(operation, verb)
            if (
                kind.value >= NODE_LESS_THAN.value
                and kind.value <= NODE_NOT_EQUAL.value
            ):
                result = ValueType(type.width())
        return self._add(operation, result, left.value, right.value)

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

    def _columns(mut self, m: NodeRef) raises -> List[NodeRef]:
        """Return a matrix's columns: the ones it was built of, or a
        uniform's or the view's, each the matrix times a unit vector."""
        var size = 3 if self._types[m.value] == NODE_MAT3 else 4
        var out = List[NodeRef]()
        if self._kinds[m.value] == NODE_MATRIX_COLUMNS:
            out.append(NodeRef(self._inputs[m.value * 3]))
            out.append(NodeRef(self._inputs[m.value * 3 + 1]))
            var rest = self._inputs[m.value * 3 + 2]
            if size == 3:
                out.append(NodeRef(rest))
            else:
                out.append(NodeRef(self._inputs[rest * 3]))
                out.append(NodeRef(self._inputs[rest * 3 + 1]))
            return out^
        for index in range(size):  # pragma: no branch
            out.append(
                self._add(
                    NODE_MATRIX_VECTOR,
                    ValueType(size),
                    self._unit(size, index).value,
                    m.value,
                )
            )
        return out^

    def _unit(mut self, size: Int, index: Int) -> NodeRef:
        """Return the unit vector of `size` components along `index`."""
        var lanes = Lanes(0)
        lanes[index] = 1
        return self._add(NODE_CONSTANT, ValueType(size), value=lanes)

    def _from_columns(mut self, columns: List[NodeRef]) raises -> NodeRef:
        """Return the matrix of three `vec3` or four `vec4` columns."""
        var size = len(columns)
        var type = NODE_MAT3 if size == 3 else NODE_MAT4
        for index in range(size):  # pragma: no branch
            self._check(columns[index])
            if self._types[columns[index].value] != ValueType(size):
                raise Error(
                    "A "
                    + type.name()
                    + " is made of "
                    + ValueType(size).name()
                    + " columns, not a "
                    + self._types[columns[index].value].name()
                )
        var rest = columns[2].value
        if size == 4:
            rest = self._add(
                NODE_MATRIX_TAIL, type, columns[2].value, columns[3].value
            ).value
        return self._add(
            NODE_MATRIX_COLUMNS, type, columns[0].value, columns[1].value, rest
        )

    def _rows(mut self, m: NodeRef) raises -> List[NodeRef]:
        """Return a matrix's rows: each a join of one component of every
        column."""
        var columns = self._columns(m)
        var rows = List[NodeRef]()
        for row in range(len(columns)):  # pragma: no branch
            var parts = List[NodeRef]()
            for index in range(len(columns)):  # pragma: no branch
                parts.append(self.swizzle(columns[index], _letter_of(row)))
            rows.append(self.join(parts))
        return rows^

    def _square(self, m: NodeRef, verb: String) raises:
        """Refuse a node that is not a `mat3` or a `mat4`.

        Raises:
            Error: If `m` is not a matrix of this graph.
        """
        self._check(m)
        if not self._matrix_of(m):
            raise Error(
                "A node graph can "
                + verb
                + " a mat3 or a mat4, not a "
                + self._types[m.value].name()
            )

    def mat3(mut self, c0: NodeRef, c1: NodeRef, c2: NodeRef) raises -> NodeRef:
        """Return the `mat3` of three columns, TSL's `mat3(a, b, c)`.

        Args:
            c0: The first column, a `vec3`.
            c1: The second.
            c2: The third.

        Returns:
            The matrix, which `mul`, `transpose`, `inverse`,
            `determinant` and `column` read.

        Raises:
            Error: If a column is not a `vec3` of this graph.
        """
        return self._from_columns([c0, c1, c2])

    def mat4(
        mut self, c0: NodeRef, c1: NodeRef, c2: NodeRef, c3: NodeRef
    ) raises -> NodeRef:
        """Return the `mat4` of four columns, TSL's `mat4(a, b, c, d)`.

        Args:
            c0: The first column, a `vec4`.
            c1: The second.
            c2: The third.
            c3: The fourth.

        Returns:
            The matrix, which `mul`, `transpose`, `inverse`,
            `determinant` and `column` read.

        Raises:
            Error: If a column is not a `vec4` of this graph.
        """
        return self._from_columns([c0, c1, c2, c3])

    def column(mut self, m: NodeRef, index: Int) raises -> NodeRef:
        """Return one column of a matrix, GLSL's `m[index]`.

        Args:
            m: A `mat3` or a `mat4`.
            index: Which column, from zero.

        Returns:
            The column, a `vec3` or a `vec4`.

        Raises:
            Error: If `m` is not a matrix of this graph, or the matrix has
                no such column.
        """
        self._square(m, "take a column of")
        var columns = self._columns(m)
        if not index_in_count(index, len(columns)):
            raise Error(
                "A "
                + self._types[m.value].name()
                + " has no column "
                + String(index)
            )
        return columns[index]

    def transpose(mut self, m: NodeRef) raises -> NodeRef:
        """Return a matrix's transpose, TSL's `transpose`.

        Args:
            m: A `mat3` or a `mat4`.

        Returns:
            The matrix whose columns are `m`'s rows.

        Raises:
            Error: If `m` is not a matrix of this graph.
        """
        self._square(m, "transpose")
        return self._from_columns(self._rows(m))

    def _det3(mut self, a: NodeRef, b: NodeRef, c: NodeRef) raises -> NodeRef:
        """Return the determinant of three `vec3` columns."""
        return self.dot(a, self.cross(b, c))

    def _cross4(mut self, columns: List[NodeRef], skip: Int) raises -> NodeRef:
        """Return a `vec4` at right angles to every column but `skip`: each
        component the determinant of the other three with that component's
        row left out, signed in turn."""
        var others = List[NodeRef]()
        for index in range(4):  # pragma: no branch
            if index != skip:
                others.append(columns[index])
        var parts = List[NodeRef]()
        for row in range(4):  # pragma: no branch
            var keep = _without(row)
            var d = self._det3(
                self.swizzle(others[0], keep),
                self.swizzle(others[1], keep),
                self.swizzle(others[2], keep),
            )
            parts.append(d if row % 2 == 0 else self.negate(d))
        return self.join(parts)

    def determinant(mut self, m: NodeRef) raises -> NodeRef:
        """Return a matrix's determinant, TSL's `determinant`.

        Args:
            m: A `mat3` or a `mat4`.

        Returns:
            The determinant, a `float`.

        Raises:
            Error: If `m` is not a matrix of this graph.
        """
        self._square(m, "take the determinant of")
        var columns = self._columns(m)
        if len(columns) == 3:
            return self._det3(columns[0], columns[1], columns[2])
        return self.dot(columns[0], self._cross4(columns, 0))

    def inverse(mut self, m: NodeRef) raises -> NodeRef:
        """Return a matrix's inverse, TSL's `inverse`. Each row of the
        inverse is at right angles to every column of `m` but one, and
        scaled so its dot with that one is one. A singular matrix gives
        what the divisions by zero give.

        Args:
            m: A `mat3` or a `mat4`.

        Returns:
            The inverse, of `m`'s type.

        Raises:
            Error: If `m` is not a matrix of this graph.
        """
        self._square(m, "invert")
        var columns = self._columns(m)
        var size = len(columns)
        var rows = List[NodeRef]()
        for index in range(size):  # pragma: no branch
            var normal: NodeRef
            if size == 3:
                normal = self.cross(
                    columns[(index + 1) % 3], columns[(index + 2) % 3]
                )
            else:
                normal = self._cross4(columns, index)
            rows.append(self.div(normal, self.dot(columns[index], normal)))
        return self.transpose(self._from_columns(rows))

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
        if self._matrix_of(a) and self._matrix_of(b):
            if self._types[a.value] != self._types[b.value]:
                raise Error(
                    "A node graph cannot multiply a "
                    + self._types[a.value].name()
                    + " and a "
                    + self._types[b.value].name()
                )
            # Each column of the product is `a` times a column of `b`.
            var columns = self._columns(b)
            var product = List[NodeRef]()
            for index in range(len(columns)):  # pragma: no branch
                product.append(self.mul(a, columns[index]))
            return self._from_columns(product)
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
            if self._kinds[matrix.value] == NODE_MATRIX_COLUMNS:
                var columns = self._columns(matrix)
                if not on_left:
                    # A vector times a matrix: its dot with each column.
                    var dots = List[NodeRef]()
                    for index in range(size):  # pragma: no branch
                        dots.append(self.dot(vector, columns[index]))
                    return self.join(dots)
                # A matrix times a vector: its columns, weighted.
                var sum = self.mul(columns[0], self.swizzle(vector, "x"))
                for index in range(1, size):  # pragma: no branch
                    sum = self.add(
                        sum,
                        self.mul(
                            columns[index],
                            self.swizzle(vector, _letter_of(index)),
                        ),
                    )
                return sum
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
        var third_type = self._types[c.value]
        if third_type.is_integer() and not type.is_integer():
            type = _integer_type(
                third_type, max(type.width(), third_type.width())
            )
        elif third_type.width() > type.width():
            type = _integer_type(type, third_type.width())
        var first = self._match(a, type, verb)
        var second = self._match(b, type, verb)
        var third = self._match(c, type, verb)
        var operation = kind
        if type.is_integer():
            operation = _uint_kind(kind) if type.is_unsigned() else _int_kind(
                kind
            )
            _refuse_integer_operation(operation, verb)
        return self._add(
            operation, type, first.value, second.value, third.value
        )

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
        self._float_vector(condition, "select by")
        self._vector(a, "select")
        self._vector(b, "select")
        var type = self._widest(a, b)
        var condition_type = self._types[condition.value]
        if condition_type.width() > type.width():
            type = _integer_type(type, condition_type.width())
        var first = self._match(a, type, "select")
        var second = self._match(b, type, "select")
        var gate = self._match(condition, ValueType(type.width()), "select")
        return self._add(
            NODE_SELECT, type, gate.value, first.value, second.value
        )

    def _same(
        mut self, kind: NodeKind, a: NodeRef, b: NodeRef, verb: String
    ) raises -> NodeRef:
        """Append an operation of two vectors of one type that reads its
        width: its type is `a`'s.

        Raises:
            Error: If either is not a node of this graph, or their types
                differ.
        """
        self._float_vector(a, verb)
        self._float_vector(b, verb)
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
        var type = self._types[a.value]
        var operation = kind
        if type.is_integer():
            operation = _uint_kind(kind) if type.is_unsigned() else _int_kind(
                kind
            )
            if not operation.is_valid() or scalar:
                raise Error("A float-only node cannot read an exact integer")
        return self._add(
            operation,
            NODE_FLOAT if scalar else type,
            a.value,
            value=Lanes(Float32(type.width()), 0, 0, 0),
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

    def integer(mut self, a: NodeRef) raises -> NodeRef:
        """Return each component as a whole number, truncated toward zero,
        TSL's `int`. A value here is a float, so an integer is one that
        holds a whole number.

        Args:
            a: A `float` or a vector.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a `float` or a vector of this graph.
        """
        return self._unary(NODE_TRUNC, a)

    def to_uint(mut self, a: NodeRef) raises -> NodeRef:
        """Convert numeric float lanes, or reinterpret exact signed bits.

        Args:
            a: A register value of this graph.

        Returns:
            An exact unsigned node of the same width. Float inputs truncate
            toward zero. See the module's bounded conversion rules.

        Raises:
            Error: If the input is not a register value of this graph.
        """
        self._vector(a, "convert to uint")
        var type = self._types[a.value]
        if type.is_unsigned():
            return a
        return self._add(
            NODE_INT_TO_UINT if type.is_signed() else NODE_TO_UINT,
            ValueType(40 + type.width()),
            a.value,
        )

    def to_int(mut self, a: NodeRef) raises -> NodeRef:
        """Convert numeric float lanes, or reinterpret exact unsigned bits.

        Args:
            a: A register value of this graph.

        Returns:
            An exact signed node of the same width. Float inputs truncate
            toward zero. See the module's bounded conversion rules.

        Raises:
            Error: If the input is not a register value of this graph.
        """
        self._vector(a, "convert to int")
        var type = self._types[a.value]
        if type.is_signed():
            return a
        return self._add(
            NODE_UINT_TO_INT if type.is_unsigned() else NODE_TO_INT,
            ValueType(44 + type.width()),
            a.value,
        )

    def _integer_conversion(
        mut self, a: NodeRef, kind: NodeKind, unsigned: Bool
    ) raises -> NodeRef:
        """Append a numeric conversion after checking its integer family.

        Raises:
            Error: If the input is not the expected integer family.
        """
        self._vector(a, "convert")
        var type = self._types[a.value]
        if not type.is_integer() or type.is_unsigned() != unsigned:
            raise Error("An integer conversion received the wrong type")
        return self._add(kind, ValueType(type.width()), a.value)

    def uint_to_float(mut self, a: NodeRef) raises -> NodeRef:
        """Return each unsigned value as a numeric float.

        Args:
            a: An exact unsigned node.

        Returns:
            A float-backed node of the same width.

        Raises:
            Error: If the input has another type or is not in this graph.
        """
        return self._integer_conversion(a, NODE_UINT_TO_FLOAT, True)

    def int_to_float(mut self, a: NodeRef) raises -> NodeRef:
        """Return each signed value as a numeric float.

        Args:
            a: An exact signed node.

        Returns:
            A float-backed node of the same width.

        Raises:
            Error: If the input has another type or is not in this graph.
        """
        return self._integer_conversion(a, NODE_INT_TO_FLOAT, False)

    def uint_to_bool(mut self, a: NodeRef) raises -> NodeRef:
        """Return each unsigned value as zero or one.

        Args:
            a: An exact unsigned node.

        Returns:
            A float-backed node of the same width.

        Raises:
            Error: If the input has another type or is not in this graph.
        """
        return self._integer_conversion(a, NODE_UINT_TO_BOOL, True)

    def int_to_bool(mut self, a: NodeRef) raises -> NodeRef:
        """Return each signed value as zero or one.

        Args:
            a: An exact signed node.

        Returns:
            A float-backed node of the same width.

        Raises:
            Error: If the input has another type or is not in this graph.
        """
        return self._integer_conversion(a, NODE_INT_TO_BOOL, False)

    def uint_to_int(mut self, a: NodeRef) raises -> NodeRef:
        """Interpret exact unsigned bits as a signed 32-bit integer.

        Args:
            a: An exact unsigned scalar or vector.

        Returns:
            An exact signed value. `to_uint` can restore every original bit.

        Raises:
            Error: If the input is not unsigned or is not in this graph.
        """
        self._vector(a, "convert to int")
        if not self._types[a.value].is_unsigned():
            raise Error("uint_to_int requires an exact unsigned value")
        return self.to_int(a)

    def unsigned(mut self, a: NodeRef) raises -> NodeRef:
        """Return the legacy float-backed unsigned conversion.

        This truncates toward zero and wraps negative values by 2 ** 32.
        It can round large values. Use `to_uint` for exact integer storage.

        Args:
            a: A `float` or a vector.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a `float` or a vector of this graph.
        """
        return self._unary(NODE_UNSIGNED, a)

    def bit_and(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return the bits both hold, per component, TSL's `bitAnd`.

        Args:
            a: The first operand, a `float` or a vector of whole numbers.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_BIT_AND, a, b, "take the bits of")

    def bit_or(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return the bits either holds, per component, TSL's `bitOr`.

        Args:
            a: The first operand, a `float` or a vector of whole numbers.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_BIT_OR, a, b, "take the bits of")

    def bit_xor(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return the bits one of the two holds, per component, TSL's
        `bitXor`.

        Args:
            a: The first operand, a `float` or a vector of whole numbers.
            b: The second, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._binary(NODE_BIT_XOR, a, b, "take the bits of")

    def bit_not(mut self, a: NodeRef) raises -> NodeRef:
        """Return each component's bits flipped, TSL's `bitNot`: minus the
        number less one.

        Args:
            a: A `float` or a vector of whole numbers.

        Returns:
            The node, of `a`'s type.

        Raises:
            Error: If `a` is not a `float` or a vector of this graph.
        """
        return self._unary(NODE_BIT_NOT, a)

    def _shift(
        mut self, kind: NodeKind, a: NodeRef, b: NodeRef
    ) raises -> NodeRef:
        """Shift exact integers by signed or unsigned scalar/vector counts.

        Raises:
            Error: If the count cannot be matched to the left width.
        """
        self._vector(a, "shift")
        self._vector(b, "shift by")
        var type = self._types[a.value]
        if not type.is_integer():
            return self._binary(kind, a, b, "shift")
        var count = self.to_uint(b) if type.is_unsigned() else self.to_int(b)
        count = self._match(count, type, "shift")
        return self._add(
            _uint_kind(kind) if type.is_unsigned() else _int_kind(kind),
            type,
            a.value,
            count.value,
        )

    def shift_left(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return `a`'s bits moved up by `b`, per component, TSL's
        `shiftLeft`. A shift reads the low five bits of `b`, as a GPU does.

        Args:
            a: The value, a `float` or a vector of whole numbers.
            b: How far, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._shift(NODE_SHIFT_LEFT, a, b)

    def shift_right(mut self, a: NodeRef, b: NodeRef) raises -> NodeRef:
        """Return `a`'s bits moved down by `b`, per component, keeping the
        sign, TSL's `shiftRight` of an `int`.

        Args:
            a: The value, a `float` or a vector of whole numbers.
            b: How far, of `a`'s type, or either a `float`.

        Returns:
            The node, of the wider type.

        Raises:
            Error: If either is not a node of this graph, or they are
                vectors of two sizes.
        """
        return self._shift(NODE_SHIFT_RIGHT, a, b)

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
        self._float_vector(a, "differentiate")
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
        self._float_vector(x, "remap")
        self._float_vector(in_low, "remap")
        self._float_vector(in_high, "remap")
        self._float_vector(out_low, "remap")
        self._float_vector(out_high, "remap")
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
        require_closed_count(
            len(letters), 1, 4, "A swizzle picks one to four components"
        )
        var width = self._types[a.value].width()
        var packed = 0
        var scale = 1
        for index in range(len(letters)):  # pragma: no branch
            var lane = _lane_of(letters[index])
            if not index_in_count(lane, width):
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
            _integer_type(self._types[a.value], len(letters)),
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
        require_positive(len(parts), "A join needs at least one part")
        var total = 0
        for index in range(len(parts)):  # pragma: no branch
            self._vector(parts[index], "join")
            var type = self._types[parts[index].value]
            var first_type = self._types[parts[0].value]
            if (
                type.is_unsigned() != first_type.is_unsigned()
                or type.is_signed() != first_type.is_signed()
            ):
                raise Error("A join requires one numeric family")
            total += type.width()
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
        var widths = self._types[first.value].width()
        var b = parts[rest]
        var c = -1
        widths += self._types[b.value].width() * 5
        if rest + 1 < len(parts):
            c = parts[rest + 1].value
            widths += self._types[c].width() * 25
        return self._add(
            NODE_JOIN,
            _integer_type(self._types[first.value], total),
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
        _require_noise_point(type, "Perlin noise")
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

    def _noise_point(
        self, p: NodeRef, low: Int, high: Int, what: String
    ) raises -> ValueType:
        """Refuse a point of fewer than `low` or more than `high` lanes.

        Raises:
            Error: If `p` is not such a value of this graph.
        """
        self._check(p)
        var type = self._types[p.value]
        if not type.is_vector() or type.value < low or type.value > high:
            raise Error(
                what
                + " reads a "
                + ValueType(low).name()
                + " to a "
                + ValueType(high).name()
                + ", not a "
                + type.name()
            )
        return type

    def perlin_noise_vec3(mut self, p: NodeRef) raises -> NodeRef:
        """Return MaterialX's Perlin noise of three components at a point,
        three.js's `mx_perlin_noise_vec3`.

        Args:
            p: The point, a `vec2` or a `vec3`.

        Returns:
            The node, a `vec3`.

        Raises:
            Error: If `p` is not a `vec2` or a `vec3` of this graph.
        """
        var type = self._noise_point(p, 2, 3, "Perlin noise")
        return self._add(
            NODE_NOISE_VEC3,
            NODE_VEC3,
            p.value,
            value=Lanes(Float32(type.value)),
        )

    def cell_noise_float(mut self, p: NodeRef) raises -> NodeRef:
        """Return MaterialX's cell noise at a point, three.js's
        `mx_cell_noise_float`: one value from zero to one for each cell of
        whole numbers.

        Args:
            p: The point, a `float` to a `vec4`.

        Returns:
            The node, a `float`.

        Raises:
            Error: If `p` is not a `float` or a vector of this graph.
        """
        var type = self._noise_point(p, 1, 4, "Cell noise")
        return self._add(
            NODE_CELL_NOISE,
            NODE_FLOAT,
            p.value,
            value=Lanes(Float32(type.value)),
        )

    def cell_noise_vec3(mut self, p: NodeRef) raises -> NodeRef:
        """Return MaterialX's cell noise of three components at a point,
        three.js's `mx_cell_noise_vec3`.

        Args:
            p: The point, a `float` to a `vec4`.

        Returns:
            The node, a `vec3`.

        Raises:
            Error: If `p` is not a `float` or a vector of this graph.
        """
        var type = self._noise_point(p, 1, 4, "Cell noise")
        return self._add(
            NODE_CELL_NOISE_VEC3,
            NODE_VEC3,
            p.value,
            value=Lanes(Float32(type.value)),
        )

    def worley_noise(
        mut self, p: NodeRef, jitter: NodeRef, width: Int
    ) raises -> NodeRef:
        """Return MaterialX's Worley noise at a point, three.js's
        `mx_worley_noise_float`, `_vec2` and `_vec3`: the squared distances
        to the nearest one, two or three points that jitter each cell.

        Args:
            p: The point, a `vec2` or a `vec3`.
            jitter: How far a cell's point moves from its center, a
                `float` from zero to one.
            width: One, two or three distances, nearest first.

        Returns:
            The node, a `float`, a `vec2` or a `vec3`.

        Raises:
            Error: If `p` is not a `vec2` or a `vec3`, `jitter` is not a
                `float` of this graph, or `width` is not one to three.
        """
        var type = self._noise_point(p, 2, 3, "Worley noise")
        self._check(jitter)
        if self._types[jitter.value] != NODE_FLOAT:
            raise Error(
                "Worley noise's jitter is a float, not a "
                + self._types[jitter.value].name()
            )
        if width < 1 or width > 3:
            raise Error(
                "Worley noise gives one to three distances, not "
                + String(width)
            )
        return self._add(
            NODE_WORLEY,
            ValueType(width),
            p.value,
            jitter.value,
            value=Lanes(Float32(type.value + 4 * width)),
        )

    def mx_noise_vec3(
        mut self, texcoord: NodeRef, amplitude: Float32 = 1, pivot: Float32 = 0
    ) raises -> NodeRef:
        """Return Perlin noise of three components scaled and moved,
        three.js's `mx_noise_vec3(texcoord, amplitude, pivot)`.

        Args:
            texcoord: The point, a `vec2` or a `vec3`.
            amplitude: What the noise is multiplied by.
            pivot: What is added after.

        Returns:
            The node, a `vec3`.

        Raises:
            Error: If `texcoord` is not a `vec2` or a `vec3` of this graph.
        """
        var noise = self.perlin_noise_vec3(texcoord)
        return self.add(
            self.mul(noise, self.float(amplitude)), self.float(pivot)
        )

    def mx_noise_vec4(
        mut self, texcoord: NodeRef, amplitude: Float32 = 1, pivot: Float32 = 0
    ) raises -> NodeRef:
        """Return four components of noise scaled and moved, three.js's
        `mx_noise_vec4`: Perlin noise of three components, and Perlin
        noise of one at the point moved by (19, 73).

        Args:
            texcoord: The point, a `vec2` or a `vec3`. A `vec3` is moved by
                (19, 73, 0).
            amplitude: What the noise is multiplied by.
            pivot: What is added after.

        Returns:
            The node, a `vec4`.

        Raises:
            Error: If `texcoord` is not a `vec2` or a `vec3` of this graph.
        """
        var type = self._noise_point(texcoord, 2, 3, "Perlin noise")
        var moved = self.vec2(19, 73) if type == NODE_VEC2 else self.vec3(
            19, 73, 0
        )
        var noise = self.join(
            [
                self.perlin_noise_vec3(texcoord),
                self.perlin_noise(self.add(texcoord, moved)),
            ]
        )
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
        _require_noise_point(type, "Fractal noise")
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

    # --- compute leaves -------------------------------------------------------

    def compute_builtin(mut self, which: ComputeBuiltin) raises -> NodeRef:
        """Return one of the invocation's numbers, a `float`: three.js's
        `instanceIndex` and the other compute builtins. Only a compute
        program reads it; see `materials.compute_nodes`.

        Args:
            which: The number, such as `INSTANCE_INDEX`.

        Returns:
            The node.

        Raises:
            Error: If `which` is not one of the numbers.
        """
        require_valid(
            which.is_valid(), "A compute builtin names no number there is"
        )
        return self._add(
            NODE_COMPUTE_BUILTIN,
            NODE_FLOAT,
            value=Lanes(Float32(which.value), 0, 0, 0),
        )

    def _storage_element(
        mut self, slot: Int, index: NodeRef, type: ValueType
    ) raises -> NodeRef:
        """Return a storage element read at an index, of a slot the program
        keeps: a buffer's id, or minus one less a workgroup array's.

        Raises:
            Error: If `index` is not a `float` of this graph, or `type` is
                not a `float` or a vector.
        """
        self._check(index)
        if self._types[index.value] != NODE_FLOAT:
            raise Error(
                "A storage element is read at a float index, not a "
                + self._types[index.value].name()
            )
        if not type.is_vector() or type.is_integer():
            raise Error("A storage element is a float or a vector")
        return self._add(
            NODE_STORAGE_ELEMENT,
            type,
            index.value,
            value=Lanes(Float32(slot), 0, 0, 0),
        )

    def storage_element(
        mut self, buffer: StorageBufferId, index: NodeRef, type: ValueType
    ) raises -> NodeRef:
        """Return a storage buffer's element at an index, as it was when
        the program's step began: three.js's `storage(...).element(i)`.
        Only a compute program reads it; `ComputeKernel.element` adds what
        the invocation stored since.

        Args:
            buffer: The buffer.
            index: The element's place, a `float` of a whole number.
            type: The element's type, the buffer's.

        Returns:
            The node.

        Raises:
            Error: If `buffer` is negative, `index` is not a `float` of this
                graph, or `type` is not a `float` or a vector.
        """
        require_valid(
            buffer.is_valid(), "A storage element names no buffer there can be"
        )
        return self._storage_element(buffer.value, index, type)

    def storage_element(
        mut self, array: WorkgroupArrayId, index: NodeRef, type: ValueType
    ) raises -> NodeRef:
        """Return a workgroup array's element at an index, the invocation's
        own workgroup's copy: three.js's `workgroupArray(...).element(i)`.

        Args:
            array: The array.
            index: The element's place, a `float` of a whole number.
            type: The element's type, the array's.

        Returns:
            The node.

        Raises:
            Error: If `array` is negative, `index` is not a `float` of this
                graph, or `type` is not a `float` or a vector.
        """
        require_valid(
            array.is_valid(), "A storage element names no array there can be"
        )
        return self._storage_element(-1 - array.value, index, type)

    def compute_result(
        mut self, statement: ComputeStatementId, type: ValueType
    ) raises -> NodeRef:
        """Return what an earlier statement of a compute program left: an
        atomic function's old value, or a value the program holds. Only a
        compute program reads it.

        Args:
            statement: The statement.
            type: What it left: a `float` or a vector.

        Returns:
            The node.

        Raises:
            Error: If `statement` is negative, or `type` is not a `float`
                or a vector.
        """
        require_valid(
            statement.is_valid(),
            "A compute result names no statement there can be",
        )
        if not type.is_vector() or type.is_integer():
            raise Error("A compute result is a float or a vector")
        return self._add(
            NODE_COMPUTE_RESULT,
            type,
            value=Lanes(Float32(statement.value), 0, 0, 0),
        )

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
        self._retired.append(False)
        return NodeVar(len(self._versions) - 1)

    def _check_var(self, v: NodeVar) raises:
        """Refuse a variable this graph does not hold.

        Raises:
            Error: If `v` is negative or past the last variable.
        """
        require_index_in_count(
            v.value,
            len(self._versions),
            "A node graph has no variable with that ref",
        )

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
        var gate = self._gate()
        if gate.value >= 0:
            node = self.select(gate, node, NodeRef(self._versions[v.value]))
        self._versions[v.value] = node.value

    def _gate(mut self) raises -> NodeRef:
        """Return where an assignment here takes effect after a `Break`, a
        `Continue` or a `Return`, or -1 when none has been called."""
        var gate = NodeRef(-1)
        for index in range(len(self._blocks)):
            if self._blocks[index].kind != _BLOCK_LOOP:
                continue
            if not self._blocks[index].stopped:
                continue
            var here = NodeRef(self._versions[self._blocks[index].live])
            var skip = self._versions[self._blocks[index].skip]
            if not self._is_zero(skip):
                here = self.logical_and(here, self.logical_not(NodeRef(skip)))
            gate = here if gate.value < 0 else self.logical_and(gate, here)
        for index in range(len(self._returns)):
            if not self._returns[index].used:
                continue
            var going = self.logical_not(
                NodeRef(self._versions[self._returns[index].returned])
            )
            gate = going if gate.value < 0 else self.logical_and(gate, going)
        return gate

    def _is_zero(self, node: Int) -> Bool:
        """Return True if a node is the constant zero."""
        if self._kinds[node] != NODE_CONSTANT:
            return False
        if self._types[node].is_integer():
            return bitcast[DType.uint32](self._values[node * 4]) == 0
        return self._values[node * 4] == 0

    def open_call(mut self, output: ValueType) raises:
        """Begin building a function's body, so that `Return` has a call to
        return from: what `Fn.call` does, for a caller that inlines its own
        bodies.

        Args:
            output: The type the function returns: a `float` or a vector.

        Raises:
            Error: If the type is not a `float` or a vector.
        """
        if not output.is_vector():
            raise Error("A call returns a float or a vector")
        var returned = self.Var(self.float(0))
        var zero = self._add(NODE_CONSTANT, output)
        var result = self.Var(zero)
        self._returns.append(
            _Return(returned.value, result.value, len(self._blocks), False)
        )

    def close_call(mut self, answer: NodeRef) raises -> NodeRef:
        """End the innermost call `open_call` began, and return its answer:
        what a `Return` gave where one ran, and `answer` everywhere else.

        Args:
            answer: What the body gives at its end.

        Returns:
            The call's answer.

        Raises:
            Error: If no call is open, or `answer` is not a node of the
                call's type when a `Return` ran.
        """
        require_positive(len(self._returns), "A close_call needs an open_call")
        var frame = self._returns.pop()
        self._retired[frame.returned] = True
        self._retired[frame.result] = True
        self._check(answer)
        if (
            not frame.used
            or self.type_of(answer) != self._var_types[frame.result]
        ):
            return answer
        # A `Return` gives its value where it ran; the body's answer is the
        # value everywhere else.
        return self.select(
            self.get(NodeVar(frame.returned)),
            self.get(NodeVar(frame.result)),
            answer,
        )

    def _innermost_loop(self, what: String) raises -> Int:
        """Return the innermost open loop's block.

        Raises:
            Error: If no loop is open.
        """
        for index in range(len(self._blocks) - 1, -1, -1):
            if self._blocks[index].kind == _BLOCK_LOOP:
                return index
        raise Error("A " + what + " needs a Loop to be in")

    def Break(mut self) raises:
        """Leave the innermost loop where the open branches run, TSL's
        `Break`. Nothing more in the loop takes effect there: the rest of
        this time through, and every later time.

        Raises:
            Error: If no loop is open.
        """
        var index = self._innermost_loop("Break")
        var gate = self._gate()
        var live = self._blocks[index].live
        var off = self.float(0)
        if gate.value >= 0:
            off = self.select(gate, off, NodeRef(self._versions[live]))
        self._versions[live] = off.value
        self._blocks[index].stopped = True

    def Continue(mut self) raises:
        """Skip the rest of this time through the innermost loop where the
        open branches run, TSL's `Continue`.

        Raises:
            Error: If no loop is open.
        """
        var index = self._innermost_loop("Continue")
        var gate = self._gate()
        var skip = self._blocks[index].skip
        var on = self.float(1)
        if gate.value >= 0:
            on = self.select(gate, on, NodeRef(self._versions[skip]))
        self._versions[skip] = on.value
        self._blocks[index].stopped = True

    def Return(mut self, value: NodeRef) raises:
        """Return a value from the `Fn` being built where the open branches
        run, TSL's `Return`. Nothing more in the function takes effect there,
        and the loops it is in stop.

        Args:
            value: What the function returns, of its output type or a
                `float` for a vector.

        Raises:
            Error: If no `Fn` is being built, or the value's type is another.
        """
        require_positive(len(self._returns), "A Return needs a Fn to be in")
        self._check(value)
        var frame = self._returns[len(self._returns) - 1].copy()
        var type = self._var_types[frame.result]
        var node = self._match(value, type, "return")
        var gate = self._gate()
        var returned = self.float(1)
        var off = self.float(0)
        if gate.value >= 0:
            node = self.select(
                gate, node, NodeRef(self._versions[frame.result])
            )
            returned = self.select(
                gate, returned, NodeRef(self._versions[frame.returned])
            )
        self._versions[frame.result] = node.value
        self._versions[frame.returned] = returned.value
        for index in range(frame.depth, len(self._blocks)):
            if self._blocks[index].kind != _BLOCK_LOOP:
                continue
            var live = self._blocks[index].live
            var stop = off
            if gate.value >= 0:
                stop = self.select(gate, off, NodeRef(self._versions[live]))
            self._versions[live] = stop.value
            self._blocks[index].stopped = True
        self._returns[len(self._returns) - 1].used = True

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
                -1,
                -1,
                False,
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
        var live = self.Var(self.float(1))
        var skip = self.Var(self.float(0))
        var index = self.float(start)
        var phis = List[Int]()
        for v in range(len(self._versions)):  # pragma: no branch
            if self._retired[v]:
                phis.append(-1)
                continue
            var type = self._var_types[v]
            var phi = self._add(NODE_COPY, type, self._versions[v])
            phis.append(phi.value)
            self._versions[v] = phi.value
        # Each time through starts not skipping.
        self._versions[skip.value] = self.float(0).value
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
                live.value,
                skip.value,
                False,
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
        self._retired[block.live] = True
        self._retired[block.skip] = True
        var first = block.body
        if block.stopped and block.count > 0:
            # A time through that starts after a `Break` changes nothing: each
            # variable keeps what the time before left it, and a discard in
            # the body throws nothing away.
            var started = NodeRef(block.phis[block.live])
            for v in range(len(block.phis)):  # pragma: no branch
                if v == block.skip or self._versions[v] == block.phis[v]:
                    continue
                if block.phis[v] < 0:
                    continue
                self._versions[v] = self.select(
                    started,
                    NodeRef(self._versions[v]),
                    NodeRef(block.phis[v]),
                ).value
            for index in range(len(self._discards)):
                if self._discards[index] >= first:
                    self._discards[index] = self.logical_or(
                        NodeRef(self._discards[index]),
                        self.logical_not(started),
                    ).value
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
            for v in range(len(block.phis)):  # pragma: no branch
                if block.phis[v] >= 0:
                    moved[block.phis[v] - first] = previous[v]
            for node in range(first + 1, past):  # pragma: no branch
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
            for v in range(len(previous)):  # pragma: no branch
                var at = ended[v]
                previous[v] = (
                    moved[at - first] if at >= first and at < past else at
                )
        for v in range(len(previous)):  # pragma: no branch
            self._versions[v] = previous[v]

    def End(mut self) raises:
        """Close the innermost `If` chain or `Loop`.

        Raises:
            Error: If no block is open.
        """
        require_positive(
            len(self._blocks), "An End needs an If or a Loop to close"
        )
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
        var keep = self.logical_not(self.running())
        self._discards.append(keep.value)

    def running(mut self) raises -> NodeRef:
        """Return where the code built here runs: every open branch's
        condition, where no `Break`, `Continue` or `Return` has stopped it.
        A compute statement is kept only there.

        Returns:
            A `float` node, one where the code runs; the constant one
            outside every branch.

        Raises:
            Error: If a node the path reads is not in this graph.
        """
        var path = self._path()
        var gate = self._gate()
        if gate.value >= 0:
            path = self.logical_and(path, gate)
        return path

    def in_loop(self) -> Bool:
        """Return True if a `Loop` is open here. `End` copies a loop's body
        once for each time through, so a compute statement, which the graph
        does not hold, cannot be made inside one.

        Returns:
            Whether any open block is a `Loop`.
        """
        for index in range(len(self._blocks)):
            if self._blocks[index].kind == _BLOCK_LOOP:
                return True
        return False

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
            output: Which output: one of the twenty-five.
            node: The node, of the type the output takes: a `float` for the
                opacity, the mask, the ambient occlusion and the depth, and
                a `vec3` for the rest.

        Raises:
            Error: If the output is none of the twenty-five, the node is not in
                this graph, or its type is not the output's.
        """
        require_node_output(output)
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

    def _needs(self) -> List[Int]:
        """Return each node's Ershov number: how many registers its value
        takes to compute when the input that needs most goes first, as if
        no value were shared."""
        var need = List[Int](length=self.count(), fill=1)
        for node in range(self.count()):  # pragma: no branch
            var a = 0
            var b = 0
            var c = 0
            for slot in range(3):  # pragma: no branch
                var input = self._inputs[node * 3 + slot]
                # An input is made before its reader.
                if input < 0:
                    continue
                var n = need[input]
                if n > a:
                    c = b
                    b = a
                    a = n
                elif n > b:
                    c = b
                    b = n
                else:
                    # Only a third input gets here, and `c` is still zero.
                    c = n
            need[node] = max(max(a, b + 1), max(c + 2, 1))
        return need^

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

    def _check_compute(self, kind: NodeKind) raises:
        """Refuse a node a compute program cannot compute.

        Raises:
            Error: If the node reads an attribute, the fragment's place, the
                lit color, the shadow, a texture, a varying or a derivative:
                a compute program runs on no surface.
        """
        if (
            _is_attribute(kind)
            or _SURFACE_READS.eq(Int32(kind.value)).reduce_or()
        ):
            raise Error(
                "A compute program runs on no surface: it reads no"
                " attribute, texture, varying or derivative"
            )

    def _check_stage(self, output: NodeOutput, kind: NodeKind) raises:
        """Refuse a node an output's stage cannot compute.

        Raises:
            Error: If a position node reads what only a fragment has, a
                fragment output reads what only a vertex has, an output
                other than `OUTPUT_NODE` reads the lit color, or any
                output reads what only a compute program has.
        """
        if _is_compute(kind):
            raise Error(
                "Only a compute program reads a storage element, an"
                " invocation's number or a statement's result"
            )
        var local = kind == NODE_POSITION_LOCAL or kind == NODE_NORMAL_LOCAL
        if output == POSITION_NODE:
            var fragment = (
                (_is_attribute(kind) and not local)
                or _image_sample(kind)
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
        if output == SIZE_NODE and (
            _image_sample(kind)
            or kind == NODE_DFDX
            or kind == NODE_DFDY
            or kind == NODE_FRAG_COORD
            or kind == NODE_POINT_COORD
            or kind == NODE_SCREEN_UV
            or kind == NODE_FRONT_FACING
        ):
            raise Error(
                "A size node runs once per point, before its pixels: it"
                " reads no texture, no derivative and no fragment's place"
            )
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
        if kind == NODE_SHADOW and output != RECEIVED_SHADOW_NODE:
            raise Error(
                "Only a received shadow node reads the shadow: the others"
                " run once, not once a light"
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
        self._require_blocks_closed()
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
            var layout = work._root_layout(root, output, zero, pool)
            total += len(layout.ops)
            layouts.append(layout^)
        if total == 0:
            raise Error("A node graph needs at least one output")
        var program = NodeProgram()
        var starts = work._assemble(layouts, pool, program)
        for output in range(NODE_OUTPUT_COUNT):  # pragma: no branch
            program.code[output * 2] = Float32(starts[output])
            program.code[output * 2 + 1] = Float32(len(layouts[output].ops))
        return program^

    def compile_roots(
        self, roots: List[NodeRef], mut starts: List[Int]
    ) raises -> NodeProgram:
        """Return a compute program's roots laid out as `compile` lays out
        outputs: what `materials.compute_nodes` runs with `run_code`. The
        program sets no output; `starts` says where each root is.

        Args:
            roots: The nodes to lay out, each a `float` or a vector. A root
                can be named more than once.
            starts: Filled with each root's first instruction and its
                count, two numbers a root.

        Returns:
            The program, at time zero under an identity view.

        Raises:
            Error: If an `If` or a `Loop` is still open, a `Discard` was
                made, a root is not a node of this graph, the nodes make a
                cycle, a node reads what only a surface has (see
                `_check_compute`), or a root needs more than
                `MAX_INSTRUCTIONS` instructions or `MAX_REGISTERS` values
                at once.
        """
        self._require_blocks_closed()
        if len(self._discards) > 0:
            raise Error("A compute program has no fragment to Discard")
        var work = self.copy()
        var zero = work._add(NODE_CONSTANT, NODE_VEC4).value
        var layouts = List[_Layout]()
        var pool = _Pool(work)
        for index in range(len(roots)):
            work._check(roots[index])
            layouts.append(
                work._root_layout(roots[index].value, -1, zero, pool)
            )
        var program = NodeProgram()
        var at = work._assemble(layouts, pool, program)
        starts = List[Int]()
        for index in range(len(layouts)):
            starts.append(at[index])
            starts.append(len(layouts[index].ops))
        return program^

    def _root_layout(
        self, root: Int, output: Int, zero: Int, mut pool: _Pool
    ) raises -> _Layout:
        """Return one root's instructions: an output's, or a compute
        program's where `output` is -1.

        Raises:
            Error: If a node reads one the graph does not hold, the nodes
                make a cycle, a node is one the root's stage cannot run, or
                the root needs too many instructions or values at once.
        """
        if root >= self.count():
            raise Error("An output names a node the graph does not hold")
        var order = self._order(root)
        for index in range(len(order)):  # pragma: no branch
            var node = order[index]
            # The two are open fields, so an edited graph can hold a
            # kind no instruction means or a type no value has.
            if (
                not self._kinds[node].is_valid()
                or not self._types[node].is_valid()
            ):
                raise Error("A node holds a kind or a type there is not")
            if (
                self._kinds[node] == NODE_MATRIX_COLUMNS
                or self._kinds[node] == NODE_MATRIX_TAIL
            ):
                raise Error(
                    "A matrix a node graph builds is only multiplied,"
                    " not read by an instruction"
                )
            if output < 0:
                self._check_compute(self._kinds[node])
            else:
                self._check_stage(NodeOutput(output), self._kinds[node])
        try:
            return _lay_out(self, order, root, zero, pool, _SLOT_ORDER)
        except:
            # Too many values at once in slot order: the neediest input
            # first, then the oldest. The same nodes, so the same pooled
            # values.
            try:
                return _lay_out(self, order, root, zero, pool, _NEEDIEST)
            except:
                return _lay_out(self, order, root, zero, pool, _OLDEST)

    def _assemble(
        self, layouts: List[_Layout], pool: _Pool, mut program: NodeProgram
    ) -> List[Int]:
        """Append the layouts' instructions and the pool to a program's
        header, and list where each layout starts."""
        var total = 0
        for index in range(len(layouts)):
            total += len(layouts[index].ops)
        var base = PROGRAM_HEADER + total * INSTRUCTION_FLOATS
        var at = PROGRAM_HEADER
        var starts = List[Int]()
        for which in range(len(layouts)):
            ref layout = layouts[which]
            starts.append(at)
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
                if layout.ops[index] == NODE_VIEWPORT_TEXTURE.value:
                    program.reads_scene = True
                at += INSTRUCTION_FLOATS
        program.code.extend(Span(pool.values))
        for index in range(len(pool.names)):
            program.uniform_names.append(pool.names[index])
            program.uniform_offsets.append(base + pool.offsets[index])
            program.uniform_types.append(pool.types[index])
        for index in range(len(pool.textures)):
            program.texture_offsets.append(base + pool.textures[index])
        program._list_textures()
        for index in range(len(pool.cubes)):
            program.cube_offsets.append(base + pool.cubes[index])
        for index in range(len(pool.volumes)):
            program.volume_offsets.append(base + pool.volumes[index])
        for index in range(len(pool.arrays)):
            program.array_offsets.append(base + pool.arrays[index])
        program._list_cubes()
        program.attribute_names = self._attribute_names.copy()
        program.attribute_offsets = self._attribute_offsets.copy()
        program.attribute_widths = self._attribute_widths.copy()
        return starts^


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
    # Where each cube a cube read reads keeps its id, and each 3D and
    # array texture.
    var cubes: List[Int]
    var volumes: List[Int]
    var arrays: List[Int]

    def __init__(out self, graph: NodeGraph):
        """Lay out every uniform of a graph."""
        self.values = List[Float32]()
        self.at = List[Int](length=graph.count(), fill=-1)
        self.names = List[String]()
        self.offsets = List[Int]()
        self.types = List[ValueType]()
        self.textures = List[Int]()
        self.cubes = List[Int]()
        self.volumes = List[Int]()
        self.arrays = List[Int]()
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

    def cube(mut self, graph: NodeGraph, node: Int) -> Int:
        """Return where a cube read's cube id is: its uniform's place."""
        var place = self.place(graph, graph._inputs[node * 3 + 1])
        _note_place(self.cubes, place)
        return place

    def volume(mut self, graph: NodeGraph, node: Int) -> Int:
        """Return where a 3D texture read's texture id is."""
        var place = self.place(graph, graph._inputs[node * 3 + 1])
        _note_place(self.volumes, place)
        return place

    def array(mut self, graph: NodeGraph, node: Int) -> Int:
        """Return where an array texture read's texture id is."""
        var place = self.place(graph, graph._inputs[node * 3 + 1])
        _note_place(self.arrays, place)
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


# The orders `_lay_out` can visit a node's inputs in.
comptime _SLOT_ORDER = 0
comptime _NEEDIEST = 1
comptime _OLDEST = 2


def _lay_out(
    graph: NodeGraph,
    order: List[Int],
    root: Int,
    zero: Int,
    mut pool: _Pool,
    mode: Int,
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
    var need = graph._needs() if mode == _NEEDIEST else List[Int]()
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
            # Pushed last, visited first.
            var visit = _visit(children, mode, need)
            for index in range(len(visit) - 1, -1, -1):
                if made[visit[index]] < 0:
                    stack.append(visit[index])
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


def _visit(children: List[Int], mode: Int, need: List[Int]) -> List[Int]:
    """Return a node's inputs in the order to lay them out.

    Which goes first decides how many values wait while another is
    computed. Slot order suits most graphs. A chain of selects, such as
    `Break` and `Return` leave, can need the input that needs the most
    registers first, or the oldest first.
    """
    var out = List[Int]()
    # Always three: a child is -1 where the node has none.
    for index in range(3):  # pragma: no branch
        var child = children[index]
        if child < 0:
            continue
        var at = len(out)
        if mode == _NEEDIEST:
            var n = need[child // NODE_CONTEXT_COUNT]
            while at > 0 and need[out[at - 1] // NODE_CONTEXT_COUNT] < n:
                at -= 1
        elif mode == _OLDEST:
            while at > 0 and out[at - 1] > child:
                at -= 1
        out.insert(at, child)
    return out^


def _image_sample(kind: NodeKind) -> Bool:
    """Return whether a node reads an image.

    A texture, a level, a gradient, a texel fetch, a size, a cube, a
    volume, an array, and a viewport texture all do.
    """
    return (
        kind == NODE_TEXTURE
        or kind == NODE_TEXTURE_LEVEL
        or kind == NODE_TEXTURE_GRAD
        or kind == NODE_TEXEL_FETCH
        or kind == NODE_TEXTURE_SIZE
        or kind == NODE_TEXTURE_CUBE
        or kind == NODE_TEXTURE_3D
        or kind == NODE_TEXTURE_ARRAY
        or kind == NODE_VIEWPORT_TEXTURE
    )


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
    if (kind == NODE_LIT or kind == NODE_SHADOW) and (
        context != AT_FRAGMENT.value
    ):
        raise Error(
            "A varying or a derivative cannot read the lit color or the"
            " shadow: only the fragment has them"
        )
    if corner and (
        _image_sample(kind) or kind == NODE_DFDX or kind == NODE_DFDY
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
    elif (
        kind == NODE_TEXTURE
        or kind == NODE_TEXTURE_LEVEL
        or kind == NODE_TEXTURE_GRAD
        or kind == NODE_TEXEL_FETCH
        or kind == NODE_TEXTURE_SIZE
    ):
        pooled = pool.texture(graph, node)
        immediate = 0
    elif kind == NODE_TEXTURE_CUBE:
        pooled = pool.cube(graph, node)
        immediate = 0
    elif kind == NODE_TEXTURE_3D:
        pooled = pool.volume(graph, node)
        immediate = 0
    elif kind == NODE_TEXTURE_ARRAY:
        pooled = pool.array(graph, node)
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
    # Exact constants authorize raw payload words during JSON validation.
    # Their unused B field is metadata, not a register index. Uniforms
    # keep their type in the program's named-uniform metadata instead.
    layout.b.append(
        graph._types[node].value - 40 if kind == NODE_CONSTANT
        and graph._types[node].is_integer() else 0
    )
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
