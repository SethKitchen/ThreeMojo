# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bytecode interpreter, MaterialX procedural noise and shadow shaping for TSL.

Both CPU and GPU rasterizers run `run_nodes` and `run_code` over their own
`NodeSource` implementations. `materials.nodes` re-exports every public symbol.
"""

from lights.shadow import ShadowShape
from materials.node_opcodes import (
    AT_FRAGMENT,
    AT_HERE,
    CORNER_A,
    CORNER_B,
    CORNER_C,
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
    NODE_COS,
    NODE_CROSS,
    NODE_DEGREES,
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
    NODE_INT_ABS,
    NODE_INT_ADD,
    NODE_INT_CLAMP,
    NODE_INT_DIV,
    NODE_INT_GREATER_THAN,
    NODE_INT_GREATER_THAN_EQUAL,
    NODE_INT_LAST,
    NODE_INT_LESS_THAN,
    NODE_INT_LESS_THAN_EQUAL,
    NODE_INT_MAX,
    NODE_INT_MIN,
    NODE_INT_MOD,
    NODE_INT_SHIFT_RIGHT,
    NODE_INT_SIGN,
    NODE_INT_TO_BOOL,
    NODE_INT_TO_FLOAT,
    NODE_INT_TO_UINT,
    NODE_INVERSE_SQRT,
    NODE_JOIN,
    NODE_LENGTH,
    NODE_LESS_THAN,
    NODE_LESS_THAN_EQUAL,
    NODE_LIT,
    NODE_LOG,
    NODE_LOG2,
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
    NODE_UINT_ADD,
    NODE_UINT_BIT_AND,
    NODE_UINT_BIT_NOT,
    NODE_UINT_BIT_OR,
    NODE_UINT_BIT_XOR,
    NODE_UINT_CLAMP,
    NODE_UINT_DIV,
    NODE_UINT_EQUAL,
    NODE_UINT_GREATER_THAN,
    NODE_UINT_GREATER_THAN_EQUAL,
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
    NODE_VECTOR_MATRIX,
    NODE_VIEWPORT_TEXTURE,
    NODE_WORLEY,
    NODE_XOR,
    NodeContext,
    NodeKind,
    POSITION_NODE,
    RECEIVED_SHADOW_NODE,
)
from materials.node_program import (
    INSTRUCTION_A,
    INSTRUCTION_B,
    INSTRUCTION_C,
    INSTRUCTION_DEST,
    INSTRUCTION_FLOATS,
    INSTRUCTION_IMMEDIATE,
    INSTRUCTION_OP,
    Lanes,
    MAX_REGISTERS,
    NodeOutput,
    NodeProgram,
    PROGRAM_TIME,
    PROGRAM_VIEW,
    SIZE_NODE,
)
from math.arc_tangent import atan2_float32, atan_float32
from math.norm import squared_length3
from math.smoothstep import smoothstep
from math.vector2 import Vector2
from math.vector3 import Vector3, weighted_sum3
from render.framebuffer import FloatColor, OPAQUE_WHITE
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
    # A corner's custom attributes, `MAX_ATTRIBUTE_FLOATS` floats.
    var custom: SIMD[DType.float32, 8]
    # What a light's shadow lets through, for a received shadow node.
    var shadow: Vector3

    def __init__(
        out self,
        u: Float32,
        v: Float32,
        position: Vector3,
        normal: Vector3,
        color: Vector3,
        lit: Vector3,
        textured: Bool,
        custom: SIMD[DType.float32, 8] = SIMD[DType.float32, 8](0),
        shadow: Vector3 = Vector3(1, 1, 1),
    ):
        """Gather a fragment's, a vertex's or a corner's attributes.

        Args:
            u: The texture coordinate across.
            v: The texture coordinate up.
            position: The position.
            normal: The unit normal.
            color: The interpolated corner color, linear.
            lit: What the standard lighting made of the fragment.
            textured: Whether texture nodes read their textures.
            custom: The custom attributes' floats; zeros by default.
            shadow: What a light's shadow lets through; ones by default.
        """
        self.u = u
        self.v = v
        self.position = position
        self.normal = normal
        self.color = color
        self.lit = lit
        self.textured = textured
        self.custom = custom
        self.shadow = shadow


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

    def sample_level(
        self, slot: Int, u: Float32, v: Float32, level: Float32
    ) -> FloatColor:
        """Return a texture read at a coordinate and a mip level, GLSL's
        `textureLod`.

        Args:
            slot: The texture's id.
            u: Across.
            v: Up.
            level: The mip level, fractional.

        Returns:
            The linear color, straight alpha.
        """
        ...

    def sample_grad(
        self, slot: Int, u: Float32, v: Float32, dx: Vector2, dy: Vector2
    ) -> FloatColor:
        """Read with explicit gradients, using isotropic filtering by default.

        Texture stores override this method to honor their anisotropy.
        The interpreter checks inputs before this call, rejecting nonfinite
        values.

        Args:
            slot: The texture's id.
            u: Across, already placed.
            v: Up, already placed.
            dx: Coordinate change per screen pixel across.
            dy: Coordinate change per screen pixel up.

        Returns:
            The linear color with straight alpha.
        """
        var size = self.size(slot, 0)
        var footprint = anisotropic_footprint(
            dx, dy, max(1, Int(size[0])), max(1, Int(size[1])), 1
        )
        return self.sample_level(slot, u, v, footprint.level)

    def sample_either(
        self,
        slot: Int,
        u: Float32,
        v: Float32,
        explicit: Bool,
        dx: Vector2,
        dy: Vector2,
    ) -> FloatColor:
        """Read as `sample_grad` when `explicit` is set, else as `sample`.

        The interpreter reads both kinds of texture node through this one
        call. A GPU inlines every call, so a source whose two reads share
        their footprint arithmetic can override this method and keep one
        copy of it per program.

        Args:
            slot: The texture's id.
            u: Across, already placed.
            v: Up, already placed.
            explicit: Whether `dx` and `dy` are the gradients to use.
            dx: Coordinate change per screen pixel across.
            dy: Coordinate change per screen pixel up.

        Returns:
            The linear color with straight alpha.
        """
        if explicit:
            return self.sample_grad(slot, u, v, dx, dy)
        return self.sample(slot, u, v)

    def fetch(self, slot: Int, x: Int, y: Int, level: Int) -> FloatColor:
        """Return a texel by its column and row, GLSL's `texelFetch`.

        Args:
            slot: The texture's id.
            x: The column.
            y: The row, counted as `v` counts.
            level: The mip level.

        Returns:
            The linear color, straight alpha.
        """
        ...

    def size(self, slot: Int, level: Int) -> Lanes:
        """Return a texture level's width and height, GLSL's
        `textureSize`.

        Args:
            slot: The texture's id.
            level: The mip level.

        Returns:
            The width and the height, then zeros.
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

    def frag_coord(self, context: NodeContext) -> Lanes:
        """Return where a fragment is on the target, GLSL's
        `gl_FragCoord`: the center of the pixel, the pixel to its right or
        the pixel above it, in pixels from the bottom left; its depth from
        zero to one; and one.

        Args:
            context: Which sample: the fragment, or a neighbor for a
                derivative. The depth is the fragment's for all three.

        Returns:
            The four numbers. A source with no pixel gives zeros and one.
        """
        ...

    def screen_size(self) -> Lanes:
        """Return the target's width and height in pixels, which
        `screen_uv` divides `frag_coord` by.

        Returns:
            The two numbers, then zeros. A source with no target gives
            ones.
        """
        return Lanes(1, 1, 0, 0)

    def behind(self, u: Float32, v: Float32) -> FloatColor:
        """Return the opaque scene behind the surface at a place on the
        target, three.js's `viewportSharedTexture`: its full-size level,
        filtered.

        Args:
            u: Across, from zero at the left edge.
            v: Up, from zero at the bottom edge.

        Returns:
            The linear color, straight alpha. A source with no scene
            behind reads opaque white.
        """
        return OPAQUE_WHITE

    def point_coord(self, context: NodeContext) -> Lanes:
        """Return where a fragment is in its point, GLSL's `gl_PointCoord`:
        zero to one across from the left edge, and down from the top one.

        Args:
            context: Which sample: the fragment, or a neighbor for a
                derivative. A corner is the point's center.

        Returns:
            The two numbers, then zeros. A source with no point gives
            zeros.
        """
        return Lanes(0)

    def sample_cube(self, slot: Int, direction: Vector3) -> FloatColor:
        """Return a cube texture read in a direction, GLSL's
        `textureCube`. A source with no cubes reads opaque white.

        Args:
            slot: The cube, as the source keeps it: its id on the host,
                and its first row in the texture table on the device.
            direction: Which way to look.

        Returns:
            The linear color, straight alpha.
        """
        return OPAQUE_WHITE

    def sample_3d(self, slot: Int, at: Vector3) -> FloatColor:
        """Return a 3D texture read at a coordinate, GLSL's `texture` of a
        `sampler3D`. A source with no 3D textures reads opaque white.

        Args:
            slot: The texture, as the source keeps it: its id on the host,
                and where its block starts on the device.
            at: Where to read it, zero to one on each axis.

        Returns:
            The linear color, straight alpha.
        """
        return OPAQUE_WHITE

    def sample_array(self, slot: Int, at: Vector3) -> FloatColor:
        """Return an array texture read at a coordinate and a layer,
        GLSL's `texture` of a `sampler2DArray`. A source with no array
        textures reads opaque white.

        Args:
            slot: The texture, as the source keeps it.
            at: `u`, `v` and the layer.

        Returns:
            The linear color, straight alpha.
        """
        return OPAQUE_WHITE

    def seen_from_behind(self) -> Bool:
        """Return whether the fragment's triangle is seen from its back,
        where TSL's `frontFacing` is false. A source with no triangle is
        seen from its front.

        Returns:
            Whether the triangle faces away.
        """
        return False

    def flip_sided(self) -> Bool:
        """Return whether the fragment's triangle has a `BACK_SIDE`
        material, which three.js's WebGL renderer draws with the front face
        turned round. A source with no triangle has none.

        Returns:
            Whether the material is `BACK_SIDE`.
        """
        return False

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return one corner's attributes, as the triangle carries them.

        Args:
            context: `CORNER_A`, `CORNER_B` or `CORNER_C`.

        Returns:
            The corner's coordinates, world position and normal and color.
        """
        ...

    def compute_builtin(self, which: Int) -> Float32:
        """Return one of a compute invocation's numbers, three.js's
        `instanceIndex` and the rest. A source that runs no compute
        program gives zero.

        Args:
            which: The number, a `ComputeBuiltin`'s value.

        Returns:
            The number.
        """
        return 0

    def storage_element(self, slot: Int, index: Float32) -> Lanes:
        """Return a storage buffer's or a workgroup array's element as the
        step began. A source that runs no compute program gives zeros.

        Args:
            slot: A buffer's id, or minus one less a workgroup array's.
            index: The element's place.

        Returns:
            The element's floats, then zeros; zeros past either end.
        """
        return Lanes(0)

    def statement_result(self, statement: Int) -> Lanes:
        """Return what an earlier statement of a compute program left. A
        source that runs no compute program gives zeros.

        Args:
            statement: The statement, a `ComputeStatementId`'s value.

        Returns:
            The value, then zeros.
        """
        return Lanes(0)


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
    return perspective_shares_over(
        wa * ia + wb * ib + wc * ic, wa, wb, wc, ia, ib, ic
    )


def perspective_shares_over(
    inv_w: Float32,
    wa: Float32,
    wb: Float32,
    wc: Float32,
    ia: Float32,
    ib: Float32,
    ic: Float32,
) -> Lanes:
    """Return each corner's perspective-correct weight at a sample, over
    an interpolated `1 / w` the caller already has.

    A rasterizer that tests depth with `inv_w` passes that same value, so
    the weights and the depth are rounded from one sum.

    Args:
        inv_w: The interpolated `1 / w` at the sample.
        wa: The first corner's screen-space weight.
        wb: The second's.
        wc: The third's.
        ia: The first corner's `1 / w`.
        ib: The second's.
        ic: The third's.

    Returns:
        The three weights, in the first three lanes, or the screen weights
        where `inv_w` is zero.
    """
    if inv_w == 0:
        return Lanes(wa, wb, wc, 0)
    var rcp = Float32(1) / inv_w
    return Lanes(wa * ia * rcp, wb * ib * rcp, wc * ic * rcp, 0)


struct ProgramSource[origin: Origin[mut=False]](Copyable, NodeSource):
    """The host's `NodeSource` for a program on its own, with no triangle:
    what the vertex stage runs a position node and a size node with, since
    neither reads a texture or a derivative. Every corner is one vertex."""

    var program: Pointer[NodeProgram, Self.origin]
    var vertex: NodeInputs

    def __init__(out self, program: Pointer[NodeProgram, Self.origin]):
        """Borrow a program for as long as the caller keeps it, with every
        attribute of the vertex zero.

        Args:
            program: The program to read.
        """
        var none = Vector3(0, 0, 0)
        self.program = program
        self.vertex = NodeInputs(0, 0, none, none, none, none, False)

    def __init__(
        out self, program: Pointer[NodeProgram, Self.origin], vertex: NodeInputs
    ):
        """Borrow a program for as long as the caller keeps it, at one
        vertex.

        Args:
            program: The program to read.
            vertex: The vertex every corner is.
        """
        self.program = program
        self.vertex = vertex

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
        return OPAQUE_WHITE

    def sample_level(
        self, slot: Int, u: Float32, v: Float32, level: Float32
    ) -> FloatColor:
        """Return opaque white: there is no surface to read a texture on.

        Args:
            slot: The texture's id, not read.
            u: Across, not read.
            v: Up, not read.
            level: The mip level, not read.

        Returns:
            Opaque white.
        """
        return OPAQUE_WHITE

    def fetch(self, slot: Int, x: Int, y: Int, level: Int) -> FloatColor:
        """Return opaque white: there is no surface to read a texture on.

        Args:
            slot: The texture's id, not read.
            x: The column, not read.
            y: The row, not read.
            level: The mip level, not read.

        Returns:
            Opaque white.
        """
        return OPAQUE_WHITE

    def size(self, slot: Int, level: Int) -> Lanes:
        """Return zeros: there is no texture here.

        Args:
            slot: The texture's id, not read.
            level: The mip level, not read.

        Returns:
            Zeros.
        """
        return Lanes(0)

    def shares(self, context: NodeContext) -> Lanes:
        """Return all the weight on the first corner: there is no triangle.

        Args:
            context: Which sample, not read.

        Returns:
            One, then zeros.
        """
        return Lanes(1, 0, 0, 0)

    def frag_coord(self, context: NodeContext) -> SIMD[DType.float32, 4]:
        """Return no place: there is no pixel here.

        Args:
            context: Not read.

        Returns:
            Zeros, and one.
        """
        return SIMD[DType.float32, 4](0, 0, 0, 1)

    def corner(self, context: NodeContext) -> NodeInputs:
        """Return the vertex, which every corner is.

        Args:
            context: Which corner, not read.

        Returns:
            The vertex.
        """
        return self.vertex


def _lanes(v: Vector3) -> Lanes:
    """Return a vector in the first three lanes."""
    return Lanes(v.x, v.y, v.z, 0)


def _unit(v: Vector3) -> Vector3:
    """Return a vector at a length of one, or zero for a zero vector."""
    var size = sqrt(squared_length3[DType.float32](v.x, v.y, v.z))
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
            at.u,
            at.v,
            at.position,
            _unit(at.normal),
            at.color,
            none,
            textured,
            at.custom,
        )
    var s = source.shares(context)
    var a = source.corner(CORNER_A)
    var b = source.corner(CORNER_B)
    var c = source.corner(CORNER_C)
    return NodeInputs(
        a.u * s[0] + b.u * s[1] + c.u * s[2],
        a.v * s[0] + b.v * s[1] + c.v * s[2],
        weighted_sum3(a.position, b.position, c.position, s[0], s[1], s[2]),
        _unit(weighted_sum3(a.normal, b.normal, c.normal, s[0], s[1], s[2])),
        weighted_sum3(a.color, b.color, c.color, s[0], s[1], s[2]),
        none,
        textured,
        a.custom * s[0] + b.custom * s[1] + c.custom * s[2],
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


def _in_kinds(op: Int, first: NodeKind, last: NodeKind) -> Bool:
    """Return True if an operation lies from `first` to `last`, inclusive.

    One unsigned comparison tests both ends: an operation below `first`
    wraps round to a distance larger than the range.

    Args:
        op: A raw operation, including values outside the kinds there are.
        first: The range's first kind.
        last: The range's last kind, not before `first`.

    Returns:
        Whether `op` is one of the kinds of the range.
    """
    return UInt(op - first.value) <= UInt(last.value - first.value)


def _reads_a_map(op: Int) -> Bool:
    """Return True if an operation reads a 2D texture through its sampler.

    Args:
        op: An instruction's operation.

    Returns:
        Whether it is `NODE_TEXTURE` or `NODE_TEXTURE_GRAD`.
    """
    if op == NODE_TEXTURE.value:
        return True
    return op == NODE_TEXTURE_GRAD.value


def _leaf[
    S: NodeSource
](
    source: S,
    op: Int,
    x: Lanes,
    z: Lanes,
    immediate: Float32,
    context: Int,
    inputs: NodeInputs,
) -> Lanes:
    """Return what a node that computes nothing from other nodes holds, or
    a texture read, whose coordinate is `x` and whose level is `z`. A
    constant and a uniform are read in `run_code` itself."""
    if op == NODE_TIME.value:
        return Lanes(source.word(PROGRAM_TIME))
    if op == NODE_CAMERA_POSITION.value:
        return _camera_position(source)
    if _reads_a_map(op):
        if not inputs.textured:
            return Lanes(1)
        # One read for both nodes; see `NodeSource.sample_either`.
        var explicit = op == NODE_TEXTURE_GRAD.value
        if explicit and (
            not isfinite(x[0])
            or not isfinite(x[1])
            or not isfinite(z).reduce_and()
        ):
            return Lanes(0)
        var texel = source.sample_either(
            Int(source.word(Int(immediate))),
            x[0],
            x[1],
            explicit,
            Vector2(z[0], z[1]),
            Vector2(z[2], z[3]),
        )
        return Lanes(texel.r, texel.g, texel.b, texel.a)
    if op == NODE_TEXTURE_LEVEL.value:
        if not inputs.textured:
            return Lanes(1)
        var texel = source.sample_level(
            Int(source.word(Int(immediate))), x[0], x[1], z[0]
        )
        return Lanes(texel.r, texel.g, texel.b, texel.a)
    if op == NODE_TEXEL_FETCH.value:
        if not inputs.textured:
            return Lanes(1)
        var texel = source.fetch(
            Int(source.word(Int(immediate))), Int(x[0]), Int(x[1]), Int(z[0])
        )
        return Lanes(texel.r, texel.g, texel.b, texel.a)
    if _in_kinds(op, NODE_TEXTURE_3D, NODE_TEXTURE_ARRAY):
        if not inputs.textured:
            return Lanes(1)
        var slot = Int(source.word(Int(immediate)))
        var at = Vector3(x[0], x[1], x[2])
        var texel = source.sample_3d(
            slot, at
        ) if op == NODE_TEXTURE_3D.value else source.sample_array(slot, at)
        return Lanes(texel.r, texel.g, texel.b, texel.a)
    if op == NODE_TEXTURE_CUBE.value:
        if not inputs.textured:
            return Lanes(1)
        var texel = source.sample_cube(
            Int(source.word(Int(immediate))), Vector3(x[0], x[1], x[2])
        )
        return Lanes(texel.r, texel.g, texel.b, texel.a)
    if op == NODE_TEXTURE_SIZE.value:
        return source.size(Int(source.word(Int(immediate))), Int(x[0]))
    if op == NODE_LIT.value:
        return _lanes(inputs.lit)
    if op == NODE_SHADOW.value:
        return _lanes(inputs.shadow)
    if op == NODE_FRAG_COORD.value:
        return source.frag_coord(NodeContext(context))
    if op == NODE_POINT_COORD.value:
        return source.point_coord(NodeContext(context))
    if op == NODE_SCREEN_UV.value:
        var place = source.frag_coord(NodeContext(context))
        var size = source.screen_size()
        return Lanes(place[0] / size[0], place[1] / size[1], 0, 0)
    if op == NODE_VIEWPORT_TEXTURE.value:
        if not inputs.textured:
            return Lanes(1)
        var behind = source.behind(x[0], x[1])
        return Lanes(behind.r, behind.g, behind.b, behind.a)
    if op == NODE_ATTRIBUTE.value:
        # Interpolated from the corners even at the fragment, whose own
        # attributes carry no custom floats.
        var at = AT_HERE if context == AT_FRAGMENT.value else NodeContext(
            context
        )
        var custom = node_attributes(source, at, inputs.textured).custom
        var first = Int(immediate) % 8
        var out = Lanes(0)
        for lane in range(Int(immediate) // 8):  # pragma: no branch
            out[lane] = custom[first + lane]
        return out
    if op == NODE_COMPUTE_BUILTIN.value:
        return Lanes(source.compute_builtin(Int(immediate)))
    if op == NODE_STORAGE_ELEMENT.value:
        return source.storage_element(Int(immediate), x[0])
    if op == NODE_COMPUTE_RESULT.value:
        return source.statement_result(Int(immediate))
    if op == NODE_FRONT_FACING.value:
        var behind = source.seen_from_behind()
        if immediate != 0:
            # WebGL's front face turns round under `BACK_SIDE`.
            behind = behind != source.flip_sided()
        return Lanes(0 if behind else 1)
    # An attribute, of the fragment or of the context the node runs in.
    var given = inputs
    if context != AT_FRAGMENT.value:
        given = node_attributes(source, NodeContext(context), inputs.textured)
    if op == NODE_UV.value:
        return Lanes(given.u, given.v, 0, 0)
    if _in_kinds(op, NODE_POSITION_LOCAL, NODE_POSITION_WORLD):
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


def _bjmix(mut a: UInt32, mut b: UInt32, mut c: UInt32):
    """Mix three words, Bob Jenkins's `mix`, MaterialX's `mx_bjmix`."""
    a -= c
    a ^= _rotl32(c, 4)
    c += b
    b -= a
    b ^= _rotl32(a, 6)
    a += c
    c -= b
    c ^= _rotl32(b, 8)
    b += a
    a -= c
    a ^= _rotl32(c, 16)
    c += b
    b -= a
    b ^= _rotl32(a, 19)
    a += c
    c -= b
    c ^= _rotl32(b, 4)
    b += a


def _hash_of(p: SIMD[DType.int32, 8], count: Int) -> UInt32:
    """Return MaterialX's `mx_hash_int` of one to five whole numbers."""
    var seed = UInt32(0xDEADBEEF) + (UInt32(count) << 2) + 13
    if count == 1:
        return _bjfinal(seed + UInt32(p[0]), seed, seed)
    var a = seed + UInt32(p[0])
    var b = seed + UInt32(p[1])
    var c = seed + UInt32(p[2]) if count >= 3 else seed
    if count <= 3:
        return _bjfinal(a, b, c)
    _bjmix(a, b, c)
    a += UInt32(p[3])
    if count == 5:
        b += UInt32(p[4])
    return _bjfinal(a, b, c)


def _to_01(bits: UInt32) -> Float32:
    """Return a hash as a float from zero to one, MaterialX's
    `mx_bits_to_01`."""
    return Float32(bits) / Float32(4294967295.0)


def _cells(p: Lanes, count: Int) -> SIMD[DType.int32, 8]:
    """Return the whole numbers below each of a point's lanes, and room
    for one more."""
    var out = SIMD[DType.int32, 8](0)
    for lane in range(count):  # pragma: no branch
        out[lane] = Int32(floor(p[lane]))
    return out


def cell_noise(p: Lanes, count: Int) -> Float32:
    """Return MaterialX's cell noise at a point, three.js's
    `mx_cell_noise_float`: one value from zero to one for each cell of
    whole numbers.

    Args:
        p: The point, in its first one to four lanes.
        count: How many lanes the point has.

    Returns:
        The noise.
    """
    return _to_01(_hash_of(_cells(p, count), count))


def cell_noise_vec3(p: Lanes, count: Int) -> Lanes:
    """Return MaterialX's cell noise of three components at a point,
    three.js's `mx_cell_noise_vec3`: the cell's whole numbers hashed with
    zero, one and two.

    Args:
        p: The point, in its first one to four lanes.
        count: How many lanes the point has.

    Returns:
        The noise, each component from zero to one.
    """
    var cells = _cells(p, count)
    var out = Lanes(0)
    for k in range(3):  # pragma: no branch
        cells[count] = Int32(k)
        out[k] = _to_01(_hash_of(cells, count + 1))
    return out


def worley_noise(p: Lanes, count: Int, jitter: Float32, width: Int) -> Lanes:
    """Return MaterialX's Worley noise at a point, three.js's
    `mx_worley_noise_float`, `_vec2` and `_vec3` with the metric that
    `MaterialXNodes` gives them: the squared distances to the nearest one,
    two or three of the points that jitter each neighboring cell.

    Args:
        p: The point, in its first two or three lanes.
        count: Two or three, how many lanes the point has.
        jitter: How far a cell's point moves from its center, from zero to
            one.
        width: How many distances, nearest first.

    Returns:
        The distances, a million where fewer are near.
    """
    var cells = _cells(p, count)
    var local = Lanes(0)
    for lane in range(count):  # pragma: no branch
        local[lane] = p[lane] - Float32(cells[lane])
    var best = Lanes(1e6, 1e6, 1e6, 0)
    var depth = 3 if count == 3 else 1
    for dx in range(-1, 2):  # pragma: no branch
        for dy in range(-1, 2):  # pragma: no branch
            for dz in range(depth):  # pragma: no branch
                var offset = Lanes(Float32(dx), Float32(dy), Float32(dz - 1), 0)
                var at = Lanes(0)
                for lane in range(count):  # pragma: no branch
                    at[lane] = offset[lane] + Float32(cells[lane])
                var tmp = cell_noise_vec3(at, count)
                var dist = Float32(0)
                for lane in range(count):  # pragma: no branch
                    var moved = (tmp[lane] - 0.5) * jitter + 0.5
                    var d = (offset[lane] + moved) - local[lane]
                    dist = dist + d * d
                if dist < best[0]:
                    best[2] = best[1]
                    best[1] = best[0]
                    best[0] = dist
                elif width > 1 and dist < best[1]:
                    best[2] = best[1]
                    best[1] = dist
                elif width > 2 and dist < best[2]:
                    best[2] = dist
    return best


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
    return _perlin(p, count, -1)


def perlin_noise_vec3(p: Lanes, count: Int) -> Lanes:
    """Return MaterialX's Perlin noise of three components at a point,
    three.js's `mx_perlin_noise_vec3`: each component graded by one byte
    of each corner's hash.

    Args:
        p: The point, in its first two or three lanes.
        count: Two or three, how many lanes the point has.

    Returns:
        The noise, each component from about minus one to one.
    """
    return Lanes(
        _perlin(p, count, 0), _perlin(p, count, 1), _perlin(p, count, 2), 0
    )


def _pick(byte: Int, hash: UInt32) -> UInt32:
    """Return a hash, or one byte of it, MaterialX's `mx_hash_vec3`."""
    if byte < 0:
        return hash
    return (hash >> UInt32(8 * byte)) & 0xFF


def _perlin(p: Lanes, count: Int, byte: Int) -> Float32:
    """Return Perlin noise graded by each corner's hash, or one byte of it."""
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
            _gradient(_pick(byte, _hash(X, Y, 0, 2)), x, y, 0, 2) * s1
            + _gradient(_pick(byte, _hash(X + 1, Y, 0, 2)), x - 1.0, y, 0, 2)
            * u
        ) + v * (
            _gradient(_pick(byte, _hash(X, Y + 1, 0, 2)), x, y - 1.0, 0, 2) * s1
            + _gradient(
                _pick(byte, _hash(X + 1, Y + 1, 0, 2)), x - 1.0, y - 1.0, 0, 2
            )
            * u
        )
        return 0.6616 * flat
    var fz = floor(p[2])
    var Z = Int32(fz)
    var z = p[2] - fz
    var w = _fade(z)
    var near = t1 * (
        _gradient(_pick(byte, _hash(X, Y, Z, 3)), x, y, z, 3) * s1
        + _gradient(_pick(byte, _hash(X + 1, Y, Z, 3)), x - 1.0, y, z, 3) * u
    ) + v * (
        _gradient(_pick(byte, _hash(X, Y + 1, Z, 3)), x, y - 1.0, z, 3) * s1
        + _gradient(
            _pick(byte, _hash(X + 1, Y + 1, Z, 3)), x - 1.0, y - 1.0, z, 3
        )
        * u
    )
    var far = t1 * (
        _gradient(_pick(byte, _hash(X, Y, Z + 1, 3)), x, y, z - 1.0, 3) * s1
        + _gradient(
            _pick(byte, _hash(X + 1, Y, Z + 1, 3)), x - 1.0, y, z - 1.0, 3
        )
        * u
    ) + v * (
        _gradient(
            _pick(byte, _hash(X, Y + 1, Z + 1, 3)), x, y - 1.0, z - 1.0, 3
        )
        * s1
        + _gradient(
            _pick(byte, _hash(X + 1, Y + 1, Z + 1, 3)),
            x - 1.0,
            y - 1.0,
            z - 1.0,
            3,
        )
        * u
    )
    return 0.9820 * ((1.0 - w) * near + w * far)


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
            out[lane] = atan_float32(a)
        elif op == NODE_ATAN2.value:
            out[lane] = atan2_float32(a, y[lane])
        elif op == NODE_ASIN.value:
            out[lane] = atan2_float32(a, sqrt(1 - a * a))
        elif op == NODE_ACOS.value:
            out[lane] = atan2_float32(sqrt(1 - a * a), a)
        else:
            out[lane] = _round(a)
    return out


comptime Whole = SIMD[DType.int32, 4]


def _whole(x: Lanes) -> Whole:
    """Return each component truncated toward zero to a 32-bit integer.
    A value past the range is held at its end, and NaN is zero, so no
    conversion is undefined on either backend."""
    # NaN by its bits: every exponent bit set, and a mantissa. A float
    # compared with itself cannot be trusted to say so.
    var bits = bitcast[DType.uint32, 4](x)
    var nan = (bits & 0x7F800000).eq(0x7F800000) & (bits & 0x007FFFFF).ne(0)
    var held = nan.select(Lanes(0), x)
    held = min(max(held, Lanes(-2147483648.0)), Lanes(2147483520.0))
    return held.cast[DType.int32]()


def _bits(op: Int, x: Lanes, y: Lanes) -> Lanes:
    """Return a bit operation's result, held as floats."""
    var a = _whole(x)
    var b = _whole(y)
    if op == NODE_BIT_AND.value:
        return (a & b).cast[DType.float32]()
    if op == NODE_BIT_OR.value:
        return (a | b).cast[DType.float32]()
    if op == NODE_BIT_XOR.value:
        return (a ^ b).cast[DType.float32]()
    if op == NODE_BIT_NOT.value:
        return (~a).cast[DType.float32]()
    var by = b & Whole(31)
    if op == NODE_SHIFT_LEFT.value:
        return (a << by).cast[DType.float32]()
    if op == NODE_SHIFT_RIGHT.value:
        return (a >> by).cast[DType.float32]()
    # Unsigned: a negative number wrapped up by 2 ** 32.
    var whole = a.cast[DType.float32]()
    return whole.lt(0).select(whole + Lanes(4294967296.0), whole)


def _float_integer_bits(x: Float32, signed: Bool = False) -> UInt32:
    """Truncate a float in the target integer range without a numeric cast.

    Out-of-range and nonfinite inputs return zero. Reading IEEE fields
    avoids undefined float-to-integer casts on either backend.
    """
    var bits = bitcast[DType.uint32](x)
    var exponent = Int((bits >> 23) & 255) - 127
    if exponent < 0 or exponent > 31:
        return 0
    var magnitude = (bits & 0x007FFFFF) | 0x00800000
    if exponent >= 23:
        magnitude = magnitude << UInt32(exponent - 23)
    else:
        magnitude = magnitude >> UInt32(23 - exponent)
    if (bits & 0x80000000) != 0:
        if not signed or magnitude > 0x80000000:
            return 0
        return UInt32(0) - magnitude
    if signed and magnitude >= 0x80000000:
        return 0
    return magnitude


def _uint_operation(op: Int, x: Lanes, y: Lanes, z: Lanes) -> Lanes:
    """Compute exact unsigned operations from bitcast register payloads.

    Comparisons and Boolean conversions return ordinary float truth lanes.
    Division by zero and shifts of 32 or more return zero in each lane.
    """
    var a = bitcast[DType.uint32, 4](x)
    var b = bitcast[DType.uint32, 4](y)
    var c = bitcast[DType.uint32, 4](z)
    if op == NODE_TO_UINT.value:
        var converted = SIMD[DType.uint32, 4](0)
        for lane in range(4):  # pragma: no branch
            converted[lane] = _float_integer_bits(x[lane])
        return bitcast[DType.float32, 4](converted)
    if op == NODE_UINT_TO_INT.value:
        return x
    if op == NODE_UINT_TO_FLOAT.value:
        return a.cast[DType.float32]()
    if op == NODE_UINT_TO_BOOL.value:
        return _truth(a.ne(0))
    if op == NODE_UINT_LESS_THAN.value:
        return _truth(a.lt(b))
    if op == NODE_UINT_LESS_THAN_EQUAL.value:
        return _truth(a.le(b))
    if op == NODE_UINT_GREATER_THAN.value:
        return _truth(a.gt(b))
    if op == NODE_UINT_GREATER_THAN_EQUAL.value:
        return _truth(a.ge(b))
    if op == NODE_UINT_EQUAL.value:
        return _truth(a.eq(b))
    if op == NODE_UINT_NOT_EQUAL.value:
        return _truth(a.ne(b))
    var result = SIMD[DType.uint32, 4](0)
    if op == NODE_UINT_ADD.value:
        result = a + b
    elif op == NODE_UINT_SUB.value:
        result = a - b
    elif op == NODE_UINT_MUL.value:
        result = a * b
    elif op == NODE_UINT_MIN.value:
        result = min(a, b)
    elif op == NODE_UINT_MAX.value:
        result = max(a, b)
    elif op == NODE_UINT_CLAMP.value:
        result = min(max(a, b), c)
    elif op == NODE_UINT_NEGATE.value:
        result = SIMD[DType.uint32, 4](0) - a
    elif op == NODE_UINT_BIT_AND.value:
        result = a & b
    elif op == NODE_UINT_BIT_OR.value:
        result = a | b
    elif op == NODE_UINT_BIT_XOR.value:
        result = a ^ b
    elif op == NODE_UINT_BIT_NOT.value:
        result = ~a
    else:
        for lane in range(4):  # pragma: no branch
            if op == NODE_UINT_DIV.value:
                if b[lane] != 0:
                    result[lane] = a[lane] // b[lane]
            elif op == NODE_UINT_MOD.value:
                if b[lane] != 0:
                    result[lane] = a[lane] % b[lane]
            elif b[lane] < 32:
                if op == NODE_UINT_SHIFT_LEFT.value:
                    result[lane] = a[lane] << b[lane]
                else:
                    result[lane] = a[lane] >> b[lane]
    return bitcast[DType.float32, 4](result)


def _int_operation(op: Int, x: Lanes, y: Lanes, z: Lanes) -> Lanes:
    """Compute exact signed operations without rounded float intermediates.

    Wrapping arithmetic and bit operations use the unsigned implementation.
    Signed division truncates toward zero and signed shifts extend the sign.
    """
    if op == NODE_TO_INT.value:
        var converted = SIMD[DType.uint32, 4](0)
        for lane in range(4):  # pragma: no branch
            converted[lane] = _float_integer_bits(x[lane], signed=True)
        return bitcast[DType.float32, 4](converted)
    if op == NODE_INT_TO_UINT.value:
        return x
    var a = bitcast[DType.int32, 4](x)
    var b = bitcast[DType.int32, 4](y)
    var c = bitcast[DType.int32, 4](z)
    if op == NODE_INT_TO_FLOAT.value:
        return a.cast[DType.float32]()
    if op == NODE_INT_TO_BOOL.value:
        return _truth(a.ne(0))
    if op == NODE_INT_ABS.value:
        var bits = bitcast[DType.uint32, 4](x)
        return bitcast[DType.float32, 4](
            a.lt(0).select(SIMD[DType.uint32, 4](0) - bits, bits)
        )
    if op == NODE_INT_SIGN.value:
        var positive = a.gt(0).select(Whole(1), Whole(0))
        var negative = a.lt(0).select(Whole(-1), Whole(0))
        return bitcast[DType.float32, 4](positive | negative)
    if op == NODE_INT_LESS_THAN.value:
        return _truth(a.lt(b))
    if op == NODE_INT_LESS_THAN_EQUAL.value:
        return _truth(a.le(b))
    if op == NODE_INT_GREATER_THAN.value:
        return _truth(a.gt(b))
    if op == NODE_INT_GREATER_THAN_EQUAL.value:
        return _truth(a.ge(b))
    if op == NODE_INT_MIN.value:
        return bitcast[DType.float32, 4](min(a, b))
    if op == NODE_INT_MAX.value:
        return bitcast[DType.float32, 4](max(a, b))
    if op == NODE_INT_CLAMP.value:
        return bitcast[DType.float32, 4](min(max(a, b), c))
    if op == NODE_INT_DIV.value or op == NODE_INT_MOD.value:
        var result = SIMD[DType.uint32, 4](0)
        var ua = bitcast[DType.uint32, 4](x)
        var ub = bitcast[DType.uint32, 4](y)
        for lane in range(4):  # pragma: no branch
            if b[lane] == 0:
                continue
            var left = UInt32(0) - ua[lane] if a[lane] < 0 else ua[lane]
            var right = UInt32(0) - ub[lane] if b[lane] < 0 else ub[lane]
            if op == NODE_INT_DIV.value:
                var quotient = left // right
                result[lane] = (
                    UInt32(0) - quotient if (a[lane] < 0)
                    != (b[lane] < 0) else quotient
                )
            else:
                var remainder = left % right
                result[lane] = (
                    UInt32(0) - remainder if a[lane] < 0 else remainder
                )
        return bitcast[DType.float32, 4](result)
    if op == NODE_INT_SHIFT_RIGHT.value:
        var result = SIMD[DType.int32, 4](0)
        for lane in range(4):  # pragma: no branch
            if b[lane] >= 0 and b[lane] < 32:
                result[lane] = a[lane] >> b[lane]
        return bitcast[DType.float32, 4](result)
    return _uint_operation(
        op - NODE_INT_ADD.value + NODE_UINT_ADD.value, x, y, z
    )


def _is_signed_operation(op: Int) -> Bool:
    """Classify any raw opcode by the exact signed-integer instruction range.

    Args:
        op: A raw integer, including values outside the supported opcode range.

    Returns:
        True only for NODE_INT_ADD through NODE_INT_LAST, inclusive.
    """
    return _in_kinds(op, NODE_INT_ADD, NODE_INT_LAST)


def _operation[
    S: NodeSource
](
    source: S, op: Int, x: Lanes, y: Lanes, z: Lanes, immediate: Float32
) -> Lanes:
    """Return what a math node computes from its inputs' registers. The
    commonest nodes, `add`, `sub`, `mul`, `div`, a swizzle, a join and a
    negation, are worked out in `run_code` itself."""
    if _in_kinds(op, NODE_UINT_ADD, NODE_UINT_TO_BOOL):
        return _uint_operation(op, x, y, z)
    if _is_signed_operation(op):
        return _int_operation(op, x, y, z)
    var width = Int(immediate)
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
    if _in_kinds(op, NODE_BIT_AND, NODE_UNSIGNED):
        return _bits(op, x, y)
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
        return bitcast[DType.float32, 4](
            x.ne(0).select(
                bitcast[DType.uint32, 4](y), bitcast[DType.uint32, 4](z)
            )
        )
    if _in_kinds(op, NODE_MATRIX_VECTOR, NODE_VECTOR_MATRIX):
        return _matrix(source, x, width, op == NODE_VECTOR_MATRIX.value)
    if op == NODE_NOISE.value:
        return Lanes(perlin_noise(x, width))
    if op == NODE_NOISE_VEC3.value:
        return perlin_noise_vec3(x, width)
    if op == NODE_CELL_NOISE.value:
        return Lanes(cell_noise(x, width))
    if op == NODE_CELL_NOISE_VEC3.value:
        return cell_noise_vec3(x, width)
    if op == NODE_WORLEY.value:
        return worley_noise(x, width % 4, y[0], width // 4)
    # `NODE_INTERPOLATE`, the one operation left: `compile` writes nothing
    # else.
    var s = source.shares(NodeContext(width))
    return x * s[0] + y * s[1] + z * s[2]


def has_output[S: NodeSource](source: S, output: NodeOutput) -> Bool:
    """Return True if the program `source` reads sets an output.

    Args:
        source: The program.
        output: One of the twenty-five outputs; the caller names it by its constant.

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
        output: One of the twenty-five outputs, one `has_output` answers True for;
            the caller names it by its constant.
        inputs: The fragment's or the vertex's attributes.

    Returns:
        The value, in as many lanes as its type has.
    """
    return run_code(
        source,
        Int(source.word(output.value * 2)),
        Int(source.word(output.value * 2 + 1)),
        inputs,
    )


# The leaves numbered after the operations, one bit each from the first.
comptime _LATE_LEAF_FIRST = NODE_FRAG_COORD.value
comptime _LATE_LEAVES = (
    _late_leaf_bit(NODE_FRAG_COORD)
    | _late_leaf_bit(NODE_POINT_COORD)
    | _late_leaf_bit(NODE_SCREEN_UV)
    | _late_leaf_bit(NODE_VIEWPORT_TEXTURE)
    | _late_leaf_bit(NODE_SHADOW)
    | _late_leaf_bit(NODE_FRONT_FACING)
    | _late_leaf_bit(NODE_TEXTURE_LEVEL)
    | _late_leaf_bit(NODE_TEXTURE_GRAD)
    | _late_leaf_bit(NODE_TEXEL_FETCH)
    | _late_leaf_bit(NODE_TEXTURE_SIZE)
    | _late_leaf_bit(NODE_ATTRIBUTE)
    | _late_leaf_bit(NODE_TEXTURE_CUBE)
    | _late_leaf_bit(NODE_TEXTURE_3D)
    | _late_leaf_bit(NODE_TEXTURE_ARRAY)
    | _late_leaf_bit(NODE_COMPUTE_BUILTIN)
    | _late_leaf_bit(NODE_STORAGE_ELEMENT)
    | _late_leaf_bit(NODE_COMPUTE_RESULT)
)


def _late_leaf_bit(kind: NodeKind) -> UInt64:
    """Return the bit of `_LATE_LEAVES` that stands for a late leaf.

    Args:
        kind: A leaf numbered after the operations.

    Returns:
        One bit, at the kind's distance from `_LATE_LEAF_FIRST`.
    """
    return UInt64(1) << UInt64(kind.value - _LATE_LEAF_FIRST)


def _is_leaf(op: Int) -> Bool:
    """Return True if `_leaf` works out an operation, not `_operation`.

    The leaves are numbered before `NODE_ADD`, and some after the
    operations. One mask holds the late ones, so the test is one lookup.

    Args:
        op: An instruction's operation.

    Returns:
        Whether the operation is a leaf.
    """
    if op < NODE_ADD.value:
        return True
    var bit = UInt(op - _LATE_LEAF_FIRST)
    if bit >= 64:
        return False
    return (_LATE_LEAVES >> UInt64(bit)) & 1 == 1


def run_code[
    S: NodeSource
](source: S, start: Int, count: Int, inputs: NodeInputs) -> Lanes:
    """Return what a run of instructions computes: `run_nodes` for one
    output, and a compute program's statements for each of their roots.

    Args:
        source: The program, where its textures are sampled, and its
            triangle or its invocation.
        start: Where the first instruction is in the program.
        count: How many instructions there are, at least one.
        inputs: The fragment's or the vertex's attributes.

    Returns:
        What the last instruction wrote, in as many lanes as its type has.
    """
    var registers = Array[Lanes, MAX_REGISTERS](fill=Lanes(0))
    var written = 0
    # Never empty: the caller asks only of an output the program sets, and
    # an output that is set holds at least the node that feeds it.
    for index in range(count):  # pragma: no branch
        var at = start + index * INSTRUCTION_FLOATS
        var op = Int(source.word(at + INSTRUCTION_OP))
        var immediate = source.word(at + INSTRUCTION_IMMEDIATE)
        written = Int(source.word(at + INSTRUCTION_DEST))
        # Integer constants use B for a type tag. Loads do not need
        # operand registers, so keep metadata out of the operand path.
        # The two loads are kinds 0 and 1, so one unsigned test finds both.
        if UInt(op) <= UInt(NODE_UNIFORM.value):
            var place = Int(immediate)
            registers[written] = Lanes(
                source.word(place),
                source.word(place + 1),
                source.word(place + 2),
                source.word(place + 3),
            )
            continue
        var third = Int(source.word(at + INSTRUCTION_C))
        var x = registers[Int(source.word(at + INSTRUCTION_A))]
        var y = registers[Int(source.word(at + INSTRUCTION_B))]
        var z = registers[third]
        # The commonest nodes, worked out here, each exactly as `_leaf` or
        # `_operation` works it out: calling either costs more than a
        # multiply does, and most of a program is these.
        if op == NODE_MUL.value:
            registers[written] = x * y
            continue
        if op == NODE_ADD.value:
            registers[written] = x + y
            continue
        if op == NODE_SUB.value:
            registers[written] = x - y
            continue
        if op == NODE_DIV.value:
            registers[written] = x / y
            continue
        if op == NODE_SWIZZLE.value:
            var order = Int(immediate)
            registers[written] = Lanes(
                x[order & 3],
                x[(order >> 2) & 3],
                x[(order >> 4) & 3],
                x[(order >> 6) & 3],
            )
            continue
        if op == NODE_JOIN.value:
            registers[written] = _joined(x, y, z, Int(immediate))
            continue
        if op == NODE_NEGATE.value:
            registers[written] = -x
            continue
        # The leaves, and `gl_FragCoord`, the facing and a texture read at
        # a level, leaves numbered after them.
        if _is_leaf(op):
            registers[written] = _leaf(
                source, op, x, z, immediate, third, inputs
            )
        else:
            registers[written] = _operation(source, op, x, y, z, immediate)
    return registers[written]


struct ProgramShape[S: NodeSource & Copyable & Deinitable](ShadowShape):
    """A shadow shaped by a program's `RECEIVED_SHADOW_NODE`, three.js's
    `receivedShadowNode`: the output run on the fragment, with the `shadow`
    node reading what one light's map lets through. Both rasterizers hand
    the lights one, so a light that casts runs the output once."""

    var source: Self.S
    var inputs: NodeInputs
    # Whether the program sets the output. A program that does not keeps
    # the shadow as it is, as `Unshaped` does.
    var active: Bool

    def __init__(out self, source: Self.S, inputs: NodeInputs, active: Bool):
        """Shape shadows by a program at one fragment.

        Args:
            source: The program, and the fragment's triangle.
            inputs: The fragment's attributes, with no lit color.
            active: Whether the program sets `RECEIVED_SHADOW_NODE`.
        """
        self.source = source.copy()
        self.inputs = inputs
        self.active = active

    def shaped(self, shadow: Vector3) -> Vector3:
        """Return what the output makes of a shadow, or the shadow as it is
        for a program that does not set it.

        Args:
            shadow: What the light's shadow lets through.

        Returns:
            The red, green and blue multipliers.
        """
        if not self.active:
            return shadow
        var given = self.inputs
        given.shadow = shadow
        var made = run_nodes(self.source, RECEIVED_SHADOW_NODE, given)
        return Vector3(made[0], made[1], made[2])


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
    var size = sqrt(squared_length3[DType.float32](x, y, z))
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


def point_size_of(program: NodeProgram, vertex: NodeInputs) raises -> Float32:
    """Return a point's width in pixels from a program's size node, on the
    host: what both rasterizers draw the point at.

    Args:
        program: The program. It must set `SIZE_NODE`.
        vertex: The point's attributes: its coordinate, world position,
            color and custom floats.

    Returns:
        The width the node computes.

    Raises:
        Error: If the program sets no size node.
    """
    if not program.has(SIZE_NODE):
        raise Error("That node program has no size node")
    return run_nodes(
        ProgramSource(Pointer(to=program), vertex), SIZE_NODE, vertex
    )[0]


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
