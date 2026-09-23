# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The depth, color and stencil state a fragment is drawn under: three.js's
`depthTest`, `depthWrite`, `depthFunc`, `colorWrite`, the stencil fields and
`polygonOffset`.

Both rasterizers call `test_fragment`, the host from
`render.target.RenderTarget.test_fragment` and the device from the pixel
kernel, so the two agree by construction.

**The order is OpenGL's.** The stencil test runs first. A fragment that
fails it takes the `stencil_fail` operation and is discarded. The depth
test runs next. A fragment that fails it takes the `stencil_z_fail`
operation and is discarded. A fragment that passes both takes the
`stencil_z_pass` operation and is drawn.

**`stencil_write` turns the whole stencil test on**, as three.js's
`stencilWrite` does. Off, the default, the stencil buffer is neither read
nor written.

**A state is two integers on its way to the device.** `ops_word` packs the
switches, the functions and the operations, three bits each. `stencil_word`
packs the reference and the two masks, eight bits each. Both ride the
per-primitive state tables, and `RasterState.unpacked` reads them back.

**Polygon offset is not in the state.** `PolygonOffset.shift` moves a
triangle's corners before either backend sees it, so both receive the moved
depths and agree without a device lane.
"""

from math.vector3 import Vector3
from std.math import isfinite, max, min
from std.memory import bitcast
from std.utils.numerics import max_finite

# The largest value a stencil buffer holds: it is eight bits deep.
comptime STENCIL_MAX = 255
# Three bits a function or an operation in the packed ops word.
comptime OP_MASK = 7
# Eight bits a field in the packed stencil word.
comptime BYTE_BITS = 8


@fieldwise_init
struct DepthFunc(Equatable, ImplicitlyCopyable, Writable):
    """How a fragment's depth is compared with the stored depth, as a type
    rather than a bare int. three.js: `NeverDepth` and the rest, with its
    numbering."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the eight depth functions.

        Returns:
            Whether the value names a depth function.
        """
        return self.value >= 0 and self.value <= 7


comptime NEVER_DEPTH = DepthFunc(0)
comptime ALWAYS_DEPTH = DepthFunc(1)
comptime LESS_DEPTH = DepthFunc(2)
comptime LESS_EQUAL_DEPTH = DepthFunc(3)
comptime EQUAL_DEPTH = DepthFunc(4)
comptime GREATER_EQUAL_DEPTH = DepthFunc(5)
comptime GREATER_DEPTH = DepthFunc(6)
comptime NOT_EQUAL_DEPTH = DepthFunc(7)


@fieldwise_init
struct StencilFunc(Equatable, ImplicitlyCopyable, Writable):
    """How the reference is compared with the stored stencil value, as a
    type rather than a bare int. three.js: `NeverStencilFunc` and the rest,
    numbered from zero in WebGL's order rather than from 512."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the eight stencil functions.

        Returns:
            Whether the value names a stencil function.
        """
        return self.value >= 0 and self.value <= 7


comptime NEVER_STENCIL_FUNC = StencilFunc(0)
comptime LESS_STENCIL_FUNC = StencilFunc(1)
comptime EQUAL_STENCIL_FUNC = StencilFunc(2)
comptime LESS_EQUAL_STENCIL_FUNC = StencilFunc(3)
comptime GREATER_STENCIL_FUNC = StencilFunc(4)
comptime NOT_EQUAL_STENCIL_FUNC = StencilFunc(5)
comptime GREATER_EQUAL_STENCIL_FUNC = StencilFunc(6)
comptime ALWAYS_STENCIL_FUNC = StencilFunc(7)


@fieldwise_init
struct StencilOp(Equatable, ImplicitlyCopyable, Writable):
    """What a fragment does to the stored stencil value, as a type rather
    than a bare int. three.js: `ZeroStencilOp` and the rest, numbered from
    zero rather than by their WebGL values."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the eight stencil operations.

        Returns:
            Whether the value names a stencil operation.
        """
        return self.value >= 0 and self.value <= 7


comptime ZERO_STENCIL_OP = StencilOp(0)
comptime KEEP_STENCIL_OP = StencilOp(1)
comptime REPLACE_STENCIL_OP = StencilOp(2)
comptime INCREMENT_STENCIL_OP = StencilOp(3)
comptime DECREMENT_STENCIL_OP = StencilOp(4)
comptime INCREMENT_WRAP_STENCIL_OP = StencilOp(5)
comptime DECREMENT_WRAP_STENCIL_OP = StencilOp(6)
comptime INVERT_STENCIL_OP = StencilOp(7)


@always_inline
def depth_compare(func: DepthFunc, z: Float32, stored: Float32) -> Bool:
    """Return True if a fragment's depth passes the depth function.

    Args:
        func: The depth function.
        z: The fragment's NDC depth.
        stored: The depth the pixel holds.

    Returns:
        Whether the fragment passes. `LESS_DEPTH` passes when `z` is below
        `stored`, as a nearer fragment is.
    """
    if func == NEVER_DEPTH:
        return False
    if func == ALWAYS_DEPTH:
        return True
    if func == LESS_DEPTH:
        return z < stored
    if func == LESS_EQUAL_DEPTH:
        return z <= stored
    if func == EQUAL_DEPTH:
        return z == stored
    if func == GREATER_EQUAL_DEPTH:
        return z >= stored
    if func == GREATER_DEPTH:
        return z > stored
    return z != stored


@always_inline
def stencil_compare(
    func: StencilFunc, reference: Int, stored: Int, mask: Int
) -> Bool:
    """Return True if the reference passes the stencil function.

    OpenGL compares the masked reference with the masked stored value, the
    reference on the left: `LESS_STENCIL_FUNC` passes when
    `reference & mask < stored & mask`.

    Args:
        func: The stencil function.
        reference: The material's `stencil_ref`.
        stored: The value the pixel holds.
        mask: The material's `stencil_func_mask`.

    Returns:
        Whether the fragment passes the stencil test.
    """
    var left = reference & mask
    var right = stored & mask
    if func == NEVER_STENCIL_FUNC:
        return False
    if func == LESS_STENCIL_FUNC:
        return left < right
    if func == EQUAL_STENCIL_FUNC:
        return left == right
    if func == LESS_EQUAL_STENCIL_FUNC:
        return left <= right
    if func == GREATER_STENCIL_FUNC:
        return left > right
    if func == NOT_EQUAL_STENCIL_FUNC:
        return left != right
    if func == GREATER_EQUAL_STENCIL_FUNC:
        return left >= right
    return True


@always_inline
def stencil_apply(
    op: StencilOp, stored: Int, reference: Int, write_mask: Int
) -> Int:
    """Return the stencil value after an operation, through the write mask.

    Only the bits the write mask sets change; the rest keep the stored
    value, as OpenGL's `glStencilMask` keeps them. The increment and the
    decrement stop at 255 and 0; the wrapping forms wrap.

    Args:
        op: The stencil operation.
        stored: The value the pixel holds, from 0 to 255.
        reference: The material's `stencil_ref`, from 0 to 255.
        write_mask: The material's `stencil_write_mask`, from 0 to 255.

    Returns:
        The new value, from 0 to 255.
    """
    var result: Int
    if op == ZERO_STENCIL_OP:
        result = 0
    elif op == KEEP_STENCIL_OP:
        result = stored
    elif op == REPLACE_STENCIL_OP:
        result = reference
    elif op == INCREMENT_STENCIL_OP:
        result = min(stored + 1, STENCIL_MAX)
    elif op == DECREMENT_STENCIL_OP:
        result = max(stored - 1, 0)
    elif op == INCREMENT_WRAP_STENCIL_OP:
        result = (stored + 1) & STENCIL_MAX
    elif op == DECREMENT_WRAP_STENCIL_OP:
        result = (stored - 1) & STENCIL_MAX
    else:
        result = ~stored & STENCIL_MAX
    return (stored & ~write_mask & STENCIL_MAX) | (result & write_mask)


def _is_byte(value: Int) -> Bool:
    """Return True if `value` fits the eight-bit stencil buffer."""
    return value >= 0 and value <= STENCIL_MAX


struct RasterState(Equatable, ImplicitlyCopyable, Writable):
    """The depth, color and stencil state of one primitive: every field
    three.js's `Material` holds for them but the polygon offset.

    `Renderer.prepare` builds it from the material with
    `materials.material.Material.raster_state`, and every corner carries
    it. The defaults are three.js's.
    """

    # Whether the depth is tested at all, three.js's `depthTest`. Off, a
    # fragment passes the depth test and writes no depth, as OpenGL's
    # disabled depth test writes none.
    var depth_test: Bool
    # Whether a fragment that passes writes its depth, three.js's
    # `depthWrite`. A blending surface never writes depth in this port;
    # see `writes_depth`.
    var depth_write: Bool
    var depth_func: DepthFunc
    # Whether a fragment that passes changes the color, three.js's
    # `colorWrite`. Off, it still writes its depth and its stencil.
    var color_write: Bool
    # Whether the stencil test runs and the stencil is written, three.js's
    # `stencilWrite`.
    var stencil_write: Bool
    var stencil_func: StencilFunc
    # The reference value and the two masks, each from 0 to 255.
    var stencil_ref: Int
    var stencil_func_mask: Int
    var stencil_write_mask: Int
    var stencil_fail: StencilOp
    var stencil_z_fail: StencilOp
    var stencil_z_pass: StencilOp

    def __init__(
        out self,
        depth_test: Bool = True,
        depth_write: Bool = True,
        depth_func: DepthFunc = LESS_EQUAL_DEPTH,
        color_write: Bool = True,
        stencil_write: Bool = False,
        stencil_func: StencilFunc = ALWAYS_STENCIL_FUNC,
        stencil_ref: Int = 0,
        stencil_func_mask: Int = STENCIL_MAX,
        stencil_write_mask: Int = STENCIL_MAX,
        stencil_fail: StencilOp = KEEP_STENCIL_OP,
        stencil_z_fail: StencilOp = KEEP_STENCIL_OP,
        stencil_z_pass: StencilOp = KEEP_STENCIL_OP,
    ):
        """Create a state. Every default is three.js's.

        Args:
            depth_test: Whether the depth is tested.
            depth_write: Whether a passing fragment writes its depth.
            depth_func: How the depth is compared. `LESS_EQUAL_DEPTH`.
            color_write: Whether a passing fragment writes its color.
            stencil_write: Whether the stencil test runs.
            stencil_func: How the reference is compared.
                `ALWAYS_STENCIL_FUNC`.
            stencil_ref: The reference value, from 0 to 255.
            stencil_func_mask: What the test masks both sides with.
            stencil_write_mask: Which bits an operation changes.
            stencil_fail: The operation when the stencil test fails.
            stencil_z_fail: The operation when the depth test fails.
            stencil_z_pass: The operation when both tests pass.
        """
        self.depth_test = depth_test
        self.depth_write = depth_write
        self.depth_func = depth_func
        self.color_write = color_write
        self.stencil_write = stencil_write
        self.stencil_func = stencil_func
        self.stencil_ref = stencil_ref
        self.stencil_func_mask = stencil_func_mask
        self.stencil_write_mask = stencil_write_mask
        self.stencil_fail = stencil_fail
        self.stencil_z_fail = stencil_z_fail
        self.stencil_z_pass = stencil_z_pass

    def is_valid(self) -> Bool:
        """Return True if every function and operation is one there is and
        every stencil value fits eight bits.

        Returns:
            Whether both backends can draw under this state.
        """
        return (
            self.depth_func.is_valid()
            and self.stencil_func.is_valid()
            and self.stencil_fail.is_valid()
            and self.stencil_z_fail.is_valid()
            and self.stencil_z_pass.is_valid()
            and _is_byte(self.stencil_ref)
            and _is_byte(self.stencil_func_mask)
            and _is_byte(self.stencil_write_mask)
        )

    def check(self) raises:
        """Refuse a state that `is_valid` refuses.

        Raises:
            Error: If a function or an operation is none of the eight, or
                the reference or a mask is outside 0 to 255.
        """
        if not self.is_valid():
            raise Error(
                "A depth or stencil state names a function or an operation"
                " there is not, or a stencil value outside 0 to 255"
            )

    def writes_depth(self, mixes: Bool) -> Bool:
        """Return True if a fragment that passes writes its depth.

        A blending fragment never writes depth, as `Renderer.prepare`
        sorts it; see `docs/wiki/Why-transparency-is-sorted.md`. A
        fragment with the depth test off writes none, as OpenGL's does.

        Args:
            mixes: Whether the fragment blends into the pixel.

        Returns:
            Whether the depth test is on, the depth write is on and the
            fragment does not blend.
        """
        return self.depth_test and self.depth_write and not mixes

    def ops_word(self) -> Int:
        """Return the switches, the functions and the operations packed
        into one integer, for the device's state tables.

        Returns:
            Bit 0 the depth test, bit 1 the depth write, bit 2 the color
            write, bit 3 the stencil write, then three bits each for the
            depth function, the stencil function and the three operations.
        """
        return (
            Int(self.depth_test)
            | (Int(self.depth_write) << 1)
            | (Int(self.color_write) << 2)
            | (Int(self.stencil_write) << 3)
            | (self.depth_func.value << 4)
            | (self.stencil_func.value << 7)
            | (self.stencil_fail.value << 10)
            | (self.stencil_z_fail.value << 13)
            | (self.stencil_z_pass.value << 16)
        )

    def stencil_word(self) -> Int:
        """Return the reference and the two masks packed into one integer,
        for the device's state tables.

        Returns:
            The reference in bits 0 to 7, the function mask in 8 to 15 and
            the write mask in 16 to 23.
        """
        return (
            self.stencil_ref
            | (self.stencil_func_mask << BYTE_BITS)
            | (self.stencil_write_mask << (2 * BYTE_BITS))
        )

    @staticmethod
    def unpacked(ops: Int, stencil: Int) -> RasterState:
        """Return the state two packed words describe.

        Args:
            ops: What `ops_word` returned.
            stencil: What `stencil_word` returned.

        Returns:
            The state, equal to the one that was packed when it was valid.
        """
        return RasterState(
            (ops & 1) != 0,
            (ops & 2) != 0,
            DepthFunc((ops >> 4) & OP_MASK),
            (ops & 4) != 0,
            (ops & 8) != 0,
            StencilFunc((ops >> 7) & OP_MASK),
            stencil & STENCIL_MAX,
            (stencil >> BYTE_BITS) & STENCIL_MAX,
            (stencil >> (2 * BYTE_BITS)) & STENCIL_MAX,
            StencilOp((ops >> 10) & OP_MASK),
            StencilOp((ops >> 13) & OP_MASK),
            StencilOp((ops >> 16) & OP_MASK),
        )


@fieldwise_init
struct FragmentTest(ImplicitlyCopyable):
    """What the stencil and the depth tests say about one fragment."""

    # Whether the fragment passed both tests and is drawn.
    var passes: Bool
    # The stencil value the fragment leaves, whether it passed or not.
    var stencil: Int
    # Whether that value differs from the stored one.
    var changes: Bool


@always_inline
def test_fragment(
    state: RasterState, z: Float32, stored_depth: Float32, stored: Int
) -> FragmentTest:
    """Return what the stencil and the depth tests do to one fragment.

    OpenGL's order: the stencil test, then the depth test, each failure
    taking its own operation. It changes nothing; the caller writes the
    stencil value and the depth once the fragment survives its alpha test.

    Args:
        state: The primitive's state.
        z: The fragment's NDC depth.
        stored_depth: The depth the pixel holds.
        stored: The stencil value the pixel holds.

    Returns:
        Whether the fragment passes and the stencil value it leaves.
    """
    var depth_ok = not state.depth_test or depth_compare(
        state.depth_func, z, stored_depth
    )
    if not state.stencil_write:
        return FragmentTest(depth_ok, stored, False)
    var op = state.stencil_z_pass
    var passes = depth_ok
    if not stencil_compare(
        state.stencil_func, state.stencil_ref, stored, state.stencil_func_mask
    ):
        op = state.stencil_fail
        passes = False
    elif not depth_ok:
        op = state.stencil_z_fail
    var after = stencil_apply(
        op, stored, state.stencil_ref, state.stencil_write_mask
    )
    return FragmentTest(passes, after, after != stored)


@always_inline
def shades(test: FragmentTest, alpha_tested: Bool) -> Bool:
    """Return True if a fragment has to be shaded before its tests settle.

    A fragment that passes is shaded. One that fails is shaded only when an
    alpha test could still discard it and its failure changes the stencil:
    OpenGL applies the failing operation to a fragment the shader keeps and
    not to one it discards. Every other failing fragment settles at once.

    Args:
        test: What `test_fragment` returned.
        alpha_tested: Whether an alpha test can discard the fragment.

    Returns:
        Whether to shade the fragment.
    """
    return test.passes or (alpha_tested and test.changes)


@fieldwise_init
struct PolygonOffset(Equatable, ImplicitlyCopyable, Writable):
    """How far a filled triangle's depth is pushed back, three.js's
    `polygonOffsetFactor` and `polygonOffsetUnits`."""

    # What the triangle's steepest depth slope, per pixel, is multiplied by.
    var factor: Float32
    # What the smallest resolvable depth difference is multiplied by.
    var units: Float32

    def is_valid(self) -> Bool:
        """Return True if both terms are finite.

        Returns:
            Whether the offset can be applied.
        """
        return isfinite(self.factor) and isfinite(self.units)

    def shift(self, a: Vector3, b: Vector3, c: Vector3) -> Float32:
        """Return the depth to add to each corner of a triangle.

        OpenGL's `factor * m + r * units`. `m` is the larger of the depth's
        slopes across x and across y, in NDC depth per pixel. `r` is the
        smallest resolvable depth difference, which for this port's
        `Float32` depth is one unit in the last place of the largest depth
        magnitude in the triangle, as OpenGL defines `r` for a floating
        point depth buffer. A positive offset pushes the triangle away.

        Args:
            a: The first corner, screen x and y with NDC depth in z.
            b: The second corner.
            c: The third corner.

        Returns:
            The offset. A triangle with no area has no slope, and its
            offset is the units term alone.
        """
        var area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
        var slope = Float32(0)
        if area != 0:
            var across = (
                (b.z - a.z) * (c.y - a.y) - (c.z - a.z) * (b.y - a.y)
            ) / area
            var down = (
                (c.z - a.z) * (b.x - a.x) - (b.z - a.z) * (c.x - a.x)
            ) / area
            # Held below the largest float, so a factor of zero times a
            # sliver's slope is zero rather than not a number.
            slope = min(
                max(abs(across), abs(down)), max_finite[DType.float32]()
            )
        var deepest = max(abs(a.z), max(abs(b.z), abs(c.z)))
        return self.factor * slope + resolvable_depth(deepest) * self.units


comptime NO_OFFSET = PolygonOffset(0, 0)

# One unit in the last place of a float whose exponent is zero: 2^-23.
comptime _ULP_OF_ONE = Float32(1.0 / 8388608.0)
# The smallest normal float, which a depth of zero resolves to.
comptime _SMALLEST_NORMAL = Float32(1.1754944e-38)


def resolvable_depth(depth: Float32) -> Float32:
    """Return the smallest depth difference a `Float32` depth resolves at
    a magnitude: one unit in its last place.

    Args:
        depth: A depth magnitude, zero or above.

    Returns:
        Two to the power of the depth's exponent less 23, and never less
        than the smallest normal float.
    """
    var power = bitcast[DType.float32](
        bitcast[DType.uint32](depth) & 0x7F800000
    )
    return max(power * _ULP_OF_ONE, _SMALLEST_NORMAL)
