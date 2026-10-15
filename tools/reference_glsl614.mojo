# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate and verify independent GLES 3.0 fixtures for ThreeMojo issue 614.

    mojo run -I . tools/reference_glsl614.mojo --verify FIXTURES.json [--case ID]
    mojo run -I . tools/reference_glsl614.mojo [--output DIR]

Mesa's software renderer executes the reference shaders through surfaceless
EGL. The tool loads `libEGL.so.1` and `libGLESv2.so.2` with Mojo FFI. It does
not import or run ThreeMojo code. Integer readback uses RGBA32UI, never a
float intermediary.

`--verify` replays the cases of a recorded file and changes no file.
Generation writes the full catalog to `DIR` (default `tools/fixtures`):
`fixtures.json`, `shaders/`, `expected_uint32.tsv` and
`expected_float32.tsv`. The catalog, its expectations and both TSV files are
the same, byte for byte, as those of the Python generator that this tool
replaces. Only the time, the toolchain and the platform fields differ.
"""

from std.ffi import OwnedDLHandle, external_call
from std.math import floor, isfinite
from std.memory import bitcast
from std.os import makedirs, setenv
from std.os.path import dirname
from std.pathlib import Path
from std.reflection import source_location
from std.sys import argv, exit, stderr
from std.time import perf_counter_ns

from loaders.json import ARRAY, BOOLEAN, JsonDocument, parse_json
from tools._json_tools import JsonWriter, get, index, is_none, quote_ascii
from tools._python_float import python_repr
from tools._python_math import hypot, log2, power, product
from tools._sha256 import sha256_hex

comptime U32 = 0xFFFFFFFF
"""The largest unsigned 32-bit value."""
comptime MOJO_VERSION = "1.1.0 (8189361e)"
"""The pinned Mojo toolchain. The project builds with this version only."""
comptime TOLERANCE = 2e-6
"""The absolute tolerance of each float32 lane."""
comptime HEX = "0123456789abcdef"
comptime VERTEX = """#version 300 es
precision highp float;
void main() {
    vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
"""
"""The vertex shader: one triangle that covers the 1-by-1 viewport."""
comptime PREFIX = """#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;
layout(location = 0) out uvec4 result;
"""
"""The start of every fragment shader."""
comptime USAGE = (
    "usage: reference_glsl614.mojo [-h] [--output OUTPUT] [--verify VERIFY]"
    " [--case CASE]"
)


# --- the catalog -------------------------------------------------------------


@fieldwise_init
struct Uniform(Copyable, Movable):
    """One uniform input: a name, a GLSL type and a value."""

    var name: String
    """The uniform's name."""
    var kind: String
    """The GLSL type, for example `uint` or `uvec4`."""
    var ints: List[Int]
    """The integer value or components."""
    var floats: List[Float64]
    """The float value or components."""
    var vector: Bool
    """True when the value is a list."""

    def is_float(self) -> Bool:
        """Return whether the value is a float or float vector.

        Returns:
            True for `float` and `vec2`.
        """
        return self.kind == "float" or self.kind == "vec2"


def scalar(name: String, kind: String, value: Int) -> Uniform:
    """Return an integer, Boolean or sampler uniform.

    Args:
        name: The uniform's name.
        kind: `uint`, `int`, `bool` or `sampler2D`.
        value: The value.

    Returns:
        The uniform.
    """
    return Uniform(name, kind, [value], List[Float64](), False)


def uvec(name: String, var values: List[Int]) -> Uniform:
    """Return a `uvec2`, `uvec3` or `uvec4` uniform.

    Args:
        name: The uniform's name.
        values: Two, three or four components.

    Returns:
        The uniform.
    """
    var kind = "uvec" + String(len(values))
    return Uniform(name, kind, values^, List[Float64](), True)


def vec2(name: String, var values: List[Float64]) -> Uniform:
    """Return a `vec2` uniform.

    Args:
        name: The uniform's name.
        values: Two components.

    Returns:
        The uniform.
    """
    return Uniform(name, "vec2", List[Int](), values^, True)


def merge(mut uniforms: List[Uniform], var update: Uniform):
    """Set a uniform as a dictionary update does: replace it, or add it.

    Args:
        uniforms: The uniforms to change.
        update: The new uniform.
    """
    for i in range(len(uniforms)):
        if uniforms[i].name == update.name:
            uniforms[i] = update^
            return
    uniforms.append(update^)


@fieldwise_init
struct TextureRecipe(Copyable, Movable):
    """The sampler state of a gradient case. The texels are fixed."""

    var min_filter: String
    """`nearest_mipmap_nearest`, `nearest_mipmap_linear` or
    `linear_mipmap_linear`."""
    var wrap_s: String
    """`clamp`, `repeat` or `mirror`."""
    var wrap_t: String
    """`clamp`, `repeat` or `mirror`."""

    def linear(self) -> Bool:
        """Return whether the filter is bilinear inside a level.

        Returns:
            True for `linear_mipmap_linear`.
        """
        return self.min_filter.startswith("linear")


@fieldwise_init
struct Case(Copyable, Movable):
    """One fixture: a fragment shader, its inputs and its expected result."""

    var id: String
    """The fixture's name."""
    var category: String
    """`uint`, `loops` or `textureGrad`."""
    var fragment_source: String
    """The complete fragment shader."""
    var uniforms: List[Uniform]
    """The uniform inputs, in insertion order."""
    var comparison: String
    """`exact_uint32` or `float32_absolute`."""
    var expected_ints: List[Int]
    """The four expected words of an `exact_uint32` case."""
    var expected_floats: List[Float64]
    """The expected values as floats. In a `float32_absolute` case they are
    the four expected lanes."""
    var has_texture: Bool
    """True when the case samples a texture."""
    var texture: TextureRecipe
    """The texture's sampler state, when `has_texture` is True."""
    var analytic_lod: Float64
    """The analytical level of detail of a gradient case."""
    var tolerance: Float64
    """The absolute tolerance of a `float32_absolute` case."""

    def exact(self) -> Bool:
        """Return whether the case compares exact words.

        Returns:
            True for `exact_uint32`.
        """
        return self.comparison == "exact_uint32"


def ints(*values: Int) -> List[Int]:
    """Return a list of integers.

    Args:
        values: The integers.

    Returns:
        The list.
    """
    var out = List[Int]()
    for value in values:
        out.append(value)
    return out^


def pair(a: Float64, b: Float64) -> List[Float64]:
    """Return a two-component float list.

    Args:
        a: The first component.
        b: The second component.

    Returns:
        The list.
    """
    return [a, b]


def uint_case(
    name: String,
    body: String,
    expected: List[Int],
    declarations: String = "",
    var uniforms: List[Uniform] = List[Uniform](),
    category: String = "uint",
) -> Case:
    """Return an exact unsigned case. Each expected word wraps to 32 bits.

    Args:
        name: The fixture's name.
        body: The body of `main`.
        expected: The four expected words, before wrapping.
        declarations: The text between the prefix and `main`.
        uniforms: The uniform inputs.
        category: `uint` or `loops`.

    Returns:
        The case.
    """
    var words = List[Int]()
    var lanes = List[Float64]()
    for value in expected:
        words.append(value & U32)
        lanes.append(Float64(value & U32))
    return Case(
        name,
        category,
        PREFIX + declarations + "\nvoid main() {\n" + body + "\n}\n",
        uniforms^,
        "exact_uint32",
        words^,
        lanes^,
        False,
        TextureRecipe("", "", ""),
        0.0,
        0.0,
    )


def hex8(value: Int) -> String:
    """Return eight lowercase hex digits, as `f"{value:08x}"` does.

    Args:
        value: A value from 0 to 2**32 - 1.

    Returns:
        The digits.
    """
    var out = String()
    for shift in [28, 24, 20, 16, 12, 8, 4, 0]:
        out += chr(Int(HEX.as_bytes()[(value >> shift) & 15]))
    return out^


struct UintCatalog(Movable):
    """The unsigned cases, with the shared runtime inputs."""

    var cases: List[Case]
    """The cases so far."""
    var inputs: List[Uniform]
    """The default uniforms of a runtime case."""
    var declarations: String
    """The uniform declarations of a runtime case."""

    def __init__(out self):
        """Start with the shared inputs."""
        self.cases = List[Case]()
        var v = ints(0, 16777217, 2147483648, U32)
        var w = ints(1, 16777216, 2147483649, U32 - 1)
        self.inputs = [
            scalar("uA", "uint", U32),
            scalar("uB", "uint", 16777217),
            uvec("uV", v^),
            uvec("uW", w^),
            scalar("uFlag", "bool", 1),
            scalar("uIndex", "int", 2),
        ]
        self.declarations = (
            "uniform uint uA; uniform uint uB; uniform uvec4 uV; uniform"
            " uvec4 uW; uniform bool uFlag; uniform int uIndex;\n"
        )

    def add(mut self, name: String, body: String, expected: List[Int]):
        """Add a case without uniforms.

        Args:
            name: The fixture's name.
            body: The body of `main`.
            expected: The four expected words.
        """
        self.cases.append(uint_case(name, body, expected))

    def runtime(
        mut self,
        name: String,
        body: String,
        expected: List[Int],
        changes: List[Uniform] = List[Uniform](),
        extra: String = "",
    ):
        """Add a case that reads the shared uniforms.

        Args:
            name: The fixture's name.
            body: The body of `main`.
            expected: The four expected words.
            changes: Uniforms that replace or extend the shared inputs.
            extra: Declarations after the uniform declarations.
        """
        var uniforms = self.inputs.copy()
        for change in changes:
            merge(uniforms, change.copy())
        self.cases.append(
            uint_case(
                name, body, expected, self.declarations + extra, uniforms^
            )
        )


def _compare_words(operation: Int, x: Int, y: Int) -> Int:
    """Return 1 or 0 for one of the six vector comparisons."""
    if operation == 0:
        return Int(x < y)
    if operation == 1:
        return Int(x <= y)
    if operation == 2:
        return Int(x > y)
    if operation == 3:
        return Int(x >= y)
    if operation == 4:
        return Int(x == y)
    return Int(x != y)


def _flag(flag: Int) -> List[Uniform]:
    """Return the change that sets `uFlag`."""
    return [scalar("uFlag", "bool", flag)]


def _with_flag(values: List[Int], flag: Int) -> List[Uniform]:
    """Return the changes that set `uV` and `uFlag`."""
    return [uvec("uV", values.copy()), scalar("uFlag", "bool", flag)]


def uint_cases() -> List[Case]:
    """Return the 87 exact unsigned cases.

    Returns:
        The cases, in catalog order.
    """
    var c = UintCatalog()
    c.add(
        "uint_literal_boundaries",
        "result = uvec4(16777215u, 16777216u, 16777217u, 4294967295u);",
        ints(16777215, 16777216, 16777217, U32),
    )
    c.add(
        "uint_literal_sign_boundary",
        "result = uvec4(2147483647u, 2147483648u, 2147483649u, 0xffffffffu);",
        ints(2147483647, 2147483648, 2147483649, U32),
    )
    c.add(
        "uint_const_wrap",
        "result = uvec4(4294967295u + 1u, 0u - 1u, 0x80000000u * 2u, -1u);",
        ints(0, U32, 0, U32),
    )
    c.add(
        "uint_constructors",
        "result = uvec4(uint(-1), uint(true), uint(false), uint(16777216.0));",
        ints(U32, 1, 0, 16777216),
    )
    c.add(
        "uint_join_uvec2_uvec3",
        (
            "uvec2 a = uvec2(16777217u, 2147483649u); uvec3 b = uvec3(a,"
            " 4294967295u); result = uvec4(b, 2147483648u);"
        ),
        ints(16777217, 2147483649, U32, 2147483648),
    )
    c.add(
        "uint_constructor_splat",
        "uvec4 a = uvec4(16777217u); result = a;",
        ints(16777217, 16777217, 16777217, 16777217),
    )
    c.add(
        "uint_swizzle_join",
        (
            "uvec4 a = uvec4(16777217u, 2147483648u, 2147483649u, 4294967295u);"
            " result = uvec4(a.wz, a.xy);"
        ),
        ints(U32, 2147483649, 16777217, 2147483648),
    )
    c.add(
        "uint_swizzle_assignment",
        (
            "uvec4 a = uvec4(16777217u, 2147483648u, 2147483649u, 4294967295u);"
            " a.xy = a.wz; result = a;"
        ),
        ints(U32, 2147483649, 2147483649, U32),
    )
    var a = U32
    var b = 16777217
    var v = ints(0, 16777217, 2147483648, U32)
    var w = ints(1, 16777216, 2147483649, U32 - 1)
    c.runtime("uint_uniform_exact", "result = uV;", v)
    c.runtime(
        "uint_uniform_wrap",
        "result = uvec4(uA + 1u, 0u - uA, uA * uB, -uA);",
        ints(0, 1, -b, 1),
    )
    c.runtime(
        "uint_uniform_div_rem",
        "result = uvec4(uA / uB, uA % uB, uA / 2147483648u, uA % 2147483648u);",
        ints(a // b, a % b, 1, 2147483647),
    )
    var factors = ints(1, 3, 2, 4)
    var sums = List[Int]()
    for i in range(4):
        sums.append((v[i] + w[i]) * factors[i])
    c.runtime(
        "uint_uniform_vector_arithmetic",
        "result = (uV + uW) * uvec4(1u, 3u, 2u, 4u);",
        sums,
    )
    var divisors = ints(1, 3, 2, 65537)
    var quotients = List[Int]()
    for i in range(4):
        quotients.append(v[i] // divisors[i] + v[i] % divisors[i])
    c.runtime(
        "uint_uniform_vector_div_rem",
        (
            "result = (uV / uvec4(1u, 3u, 2u, 65537u)) + (uV % uvec4(1u, 3u,"
            " 2u, 65537u));"
        ),
        quotients,
    )
    c.runtime(
        "uint_uniform_bitwise",
        "result = uvec4(uA & uB, uA | uB, uA ^ uB, ~uB);",
        ints(a & b, a | b, a ^ b, ~b),
    )
    c.runtime(
        "uint_uniform_shift_widths",
        "result = uvec4(uA >> 0u, uA >> 1u, uA >> 16u, uA >> 31u);",
        ints(a, a >> 1, a >> 16, a >> 31),
    )
    c.runtime(
        "uint_uniform_shift_left",
        "result = uvec4(uB << 0, uB << 1, uB << 16, uB << 31);",
        ints(b, b << 1, b << 16, b << 31),
    )
    c.runtime(
        "uint_vector_shift",
        "result = uV >> uvec4(0u, 1u, 16u, 31u);",
        ints(0, 16777217 >> 1, 2147483648 >> 16, 1),
    )
    var doubled = List[Int]()
    for x in v:
        doubled.append(x << 1)
    c.runtime("uint_vector_shift_scalar", "result = uV << 1u;", doubled)
    c.runtime(
        "uint_scalar_minmaxclamp",
        (
            "result = uvec4(min(uA, uB), max(uA, uB), clamp(uA, 16777216u,"
            " 2147483649u), clamp(uB, 2147483648u, uA));"
        ),
        ints(b, a, 2147483649, 2147483648),
    )
    var low_values = List[Int]()
    var high_values = List[Int]()
    var low_scalar = List[Int]()
    var high_scalar = List[Int]()
    var clamped = List[Int]()
    for i in range(4):
        low_values.append(min(v[i], w[i]))
        high_values.append(max(v[i], w[i]))
        low_scalar.append(min(v[i], 2147483648))
        high_scalar.append(max(v[i], 16777217))
        clamped.append(min(max(v[i], 16777216), 2147483649))
    c.runtime("uint_vector_min", "result = min(uV, uW);", low_values)
    c.runtime("uint_vector_max", "result = max(uV, uW);", high_values)
    c.runtime(
        "uint_vector_min_scalar", "result = min(uV, 2147483648u);", low_scalar
    )
    c.runtime(
        "uint_vector_max_scalar", "result = max(uV, 16777217u);", high_scalar
    )
    c.runtime(
        "uint_vector_clamp_scalar",
        "result = clamp(uV, 16777216u, 2147483649u);",
        clamped,
    )
    var low = ints(0, 16777216, 2147483647, 2147483648)
    var high = ints(1, 16777218, 2147483649, U32 - 1)
    var between = List[Int]()
    for i in range(4):
        between.append(min(max(v[i], low[i]), high[i]))
    c.runtime(
        "uint_vector_clamp_vector",
        (
            "result = clamp(uV, uvec4(0u, 16777216u, 2147483647u, 2147483648u),"
            " uvec4(1u, 16777218u, 2147483649u, 4294967294u));"
        ),
        between,
    )
    c.runtime(
        "uint_scalar_comparisons",
        (
            "result = uvec4(uint(uA > uB), uint(uB < uA), uint(uA =="
            " 4294967295u), uint(uB != 16777216u));"
        ),
        ints(1, 1, 1, 1),
    )
    c.runtime(
        "uint_scalar_equal_order",
        (
            "result = uvec4(uint(uA <= uB), uint(uA >= uB), uint(uB =="
            " 16777216u), uint(uA != uA));"
        ),
        ints(0, 1, 0, 0),
    )
    var names: List[String] = [
        "lessThan",
        "lessThanEqual",
        "greaterThan",
        "greaterThanEqual",
        "equal",
        "notEqual",
    ]
    for operation in range(len(names)):
        var flags = List[Int]()
        for i in range(4):
            flags.append(_compare_words(operation, v[i], w[i]))
        c.runtime(
            "uint_vector_" + names[operation],
            "result = uvec4(" + names[operation] + "(uV, uW));",
            flags,
        )
    c.runtime(
        "uint_vector_equal_identity",
        "result = uvec4(equal(uV, uV));",
        ints(1, 1, 1, 1),
    )
    for flag in range(2):
        var chosen = v.copy() if flag else w.copy()
        c.runtime(
            "uint_if_join_" + String(flag),
            "uvec4 x; if (uFlag) { x = uV; } else { x = uW; } result = x;",
            chosen,
            _flag(flag),
        )
        c.runtime(
            "uint_ternary_select_" + String(flag),
            "result = uFlag ? uV : uW;",
            chosen,
            _flag(flag),
        )
    c.runtime(
        "uint_runtime_swizzle",
        "uvec4 x = uV; x.zw = uW.yx; result = x.wzyx;",
        ints(1, 16777216, 16777217, 0),
    )
    c.runtime(
        "uint_runtime_vector_index",
        "result = uvec4(uV[uIndex], uV[3], uW[uIndex - 1], uW[0]);",
        ints(2147483648, U32, 16777216, 1),
    )
    c.runtime(
        "uint_runtime_array_read",
        (
            "uint a[4] = uint[4](uV.x, uV.y, uV.z, uV.w); result ="
            " uvec4(a[uIndex], a[1], a[3], a[0]);"
        ),
        ints(2147483648, 16777217, U32, 0),
    )
    c.runtime(
        "uint_runtime_array_write",
        (
            "uint a[4] = uint[4](uV.x, uV.y, uV.z, uV.w); a[uIndex] = uB;"
            " result = uvec4(a[0], a[1], a[2], a[3]);"
        ),
        ints(0, 16777217, 16777217, U32),
    )
    c.runtime(
        "uint_runtime_uvec_array",
        "uvec4 a[2] = uvec4[2](uV, uW); result = a[uIndex - 1];",
        w,
        [scalar("uIndex", "int", 2)],
    )
    c.runtime(
        "uint_function_return",
        "result = pick(uV, uW, uFlag);",
        v,
        extra=(
            "uvec4 pick(uvec4 a, uvec4 b, bool flag) { if (flag) { return a;"
            " } return b; }\n"
        ),
    )
    c.runtime(
        "uint_function_inout_out",
        (
            "uint a = uA; uint b = 0u; adjust(a, uB, b); result = uvec4(a, b,"
            " uA, uB);"
        ),
        ints(a + b, a - b, a, b),
        extra=(
            "void adjust(inout uint a, uint step, out uint b) { b = a - step;"
            " a += step; }\n"
        ),
    )
    c.runtime(
        "uint_struct_field_join",
        "Pair p = Pair(uA, uV); result = uvec4(p.a, p.b.yzw);",
        ints(a, v[1], v[2], v[3]),
        extra="struct Pair { uint a; uvec4 b; };\n",
    )
    # Keep the increment separate: constructor argument order is not specified.
    c.runtime(
        "uint_arithmetic_compound",
        (
            "uint a = uA; a += 2u; a -= 3u; a *= 3u; a /= 2u; uint before = a;"
            " ++a; result = uvec4(before, a, 0u, 0u);"
        ),
        ints(2147483645, 2147483646, 0, 0),
    )
    c.runtime(
        "uint_bitwise_compound",
        (
            "uint a = uA; a &= uB; a |= 0x80000000u; a ^= 1u; a >>= 1; a <<= 1;"
            " a %= 65537u; result = uvec4(a, uA, uB, 0u);"
        ),
        ints(((((((a & b) | 0x80000000) ^ 1) >> 1) << 1) % 65537), a, b, 0),
    )
    c.runtime(
        "uint_fragment_runtime_path",
        "uint pixel = uint(gl_FragCoord.x); result = uV + uvec4(pixel);",
        v,
    )
    c.cases.append(
        uint_case(
            "uint_uniform_uvec2",
            "result = uvec4(uPair, uPair.yx);",
            ints(16777217, U32, U32, 16777217),
            "uniform uvec2 uPair;\n",
            [uvec("uPair", ints(16777217, U32))],
        )
    )
    c.cases.append(
        uint_case(
            "uint_uniform_uvec3",
            "result = uvec4(uTriple, uTriple[1]);",
            ints(16777217, 2147483649, U32, 2147483649),
            "uniform uvec3 uTriple;\n",
            [uvec("uTriple", ints(16777217, 2147483649, U32))],
        )
    )
    c.add(
        "uint_const_minmaxclamp",
        (
            "result = uvec4(min(4294967295u, 16777217u), max(2147483647u,"
            " 2147483648u), clamp(4294967295u, 16777216u, 2147483649u),"
            " clamp(16777217u, 2147483648u, 4294967295u));"
        ),
        ints(16777217, 2147483648, 2147483649, 2147483648),
    )
    c.add(
        "uint_const_div_rem_shift",
        (
            "result = uvec4(4294967295u / 16777217u, 4294967295u % 16777217u,"
            " 4294967295u >> 31u, 16777217u << 31u);"
        ),
        ints(255, 16776960, 1, 2147483648),
    )
    c.add(
        "uint_int_uint_const_roundtrip",
        (
            "result = uvec4(uint(int(0x80000001u)), uint(int(0xffffffffu)),"
            " uint(int(0x80000000u)), uint(int(0x7fffffffu)));"
        ),
        ints(0x80000001, U32, 0x80000000, 0x7FFFFFFF),
    )
    var signed_values = ints(0x80000001, U32, 0x80000000, 0x7FFFFFFF)
    var signed_inputs: List[Uniform] = [uvec("uV", signed_values.copy())]
    c.runtime(
        "uint_ivec_variable_roundtrip",
        "ivec4 a = ivec4(uV); ivec4 b = a; result = uvec4(b);",
        signed_values,
        signed_inputs,
    )
    c.runtime(
        "uint_ivec_swizzle_roundtrip",
        (
            "ivec4 a = ivec4(uV); ivec2 b = a.wz; ivec2 c = a.xy; result ="
            " uvec4(ivec4(b,c));"
        ),
        ints(
            signed_values[3],
            signed_values[2],
            signed_values[0],
            signed_values[1],
        ),
        signed_inputs,
    )
    c.runtime(
        "uint_int_scalar_variable_roundtrip",
        (
            "int a = int(uV.x); int b = a; result = uvec4(uint(b),"
            " uint(int(uV.y)), uint(int(uV.z)), uint(int(uV.w)));"
        ),
        signed_values,
        signed_inputs,
    )
    c.runtime(
        "uint_int_function_roundtrip",
        (
            "result = uvec4(uint(signed_pass(int(uV.x))),"
            " uint(signed_pass(int(uV.y))), uint(signed_pass(int(uV.z))),"
            " uint(signed_pass(int(uV.w))));"
        ),
        signed_values,
        signed_inputs,
        extra="int signed_pass(int x) { int y = x; return y; }\n",
    )
    c.runtime(
        "uint_ivec_function_roundtrip",
        "result = uvec4(signed_pass(ivec4(uV)));",
        signed_values,
        signed_inputs,
        extra="ivec4 signed_pass(ivec4 x) { ivec4 y = x; return y; }\n",
    )
    c.runtime(
        "uint_ivec_inout_roundtrip",
        "ivec4 a = ivec4(uV); signed_pass(a); result = uvec4(a);",
        ints(
            signed_values[3],
            signed_values[2],
            signed_values[1],
            signed_values[0],
        ),
        signed_inputs,
        extra="void signed_pass(inout ivec4 x) { x = x.wzyx; }\n",
    )
    c.runtime(
        "uint_int_signed_comparison",
        "ivec4 a = ivec4(uV); result = uvec4(lessThan(a, ivec4(0)));",
        ints(1, 1, 1, 0),
        signed_inputs,
    )
    c.runtime(
        "uint_bool_high_bit",
        (
            "result = uvec4(uint(bool(uV.x)), uint(bool(uV.y)),"
            " uint(bool(uV.z)), uint(bool(uV.w)));"
        ),
        ints(1, 1, 1, 1),
        signed_inputs,
    )
    c.runtime(
        "uint_bvec_high_bit",
        "result = uvec4(bvec4(uV));",
        ints(1, 1, 1, 1),
        signed_inputs,
    )
    var bit_sets: List[List[Int]] = [
        ints(0, 1, 0x80000000, 0x7F800000),
        ints(0x7FC00001, 0xFF800000, U32, 0x007FFFFF),
    ]
    for set_index in range(len(bit_sets)):
        ref values = bit_sets[set_index]
        var update: List[Uniform] = [uvec("uV", values.copy())]
        var prefix = "uint_payload_" + String(set_index)
        var literal = String()
        for i in range(4):
            if i > 0:
                literal += ", "
            literal += "0x" + hex8(values[i]) + "u"
        c.add(prefix + "_constant", "result = uvec4(" + literal + ");", values)
        c.runtime(prefix + "_uniform", "result = uV;", values, update)
        c.runtime(
            prefix + "_variable",
            "uvec4 a = uV; uvec4 b = a; result = b;",
            values,
            update,
        )
        c.runtime(
            prefix + "_swizzle",
            "uvec2 a = uV.wz; uvec2 b = uV.xy; result = uvec4(a,b);",
            ints(values[3], values[2], values[0], values[1]),
            update,
        )
        c.runtime(
            prefix + "_function",
            "result = pass_value(uV);",
            values,
            update,
            extra=(
                "uvec4 pass_value(uvec4 x) { uvec4 local = x; return local; }\n"
            ),
        )
        var incremented = List[Int]()
        var nonzero = List[Int]()
        var minimum = List[Int]()
        var reversed_values = List[Int]()
        for i in range(4):
            incremented.append(values[i] + 1)
            nonzero.append(Int(values[i] != 0))
            minimum.append(min(values[i], 0x80000000))
            reversed_values.append(values[3 - i])
        c.runtime(
            prefix + "_inout",
            "uvec4 a = uV; pass_value(a); result = a;",
            incremented,
            update,
            extra="void pass_value(inout uvec4 x) { x += uvec4(1u); }\n",
        )
        c.runtime(
            prefix + "_array",
            (
                "uint a[4] = uint[4](uV.x,uV.y,uV.z,uV.w); result ="
                " uvec4(a[0],a[1],a[uIndex],a[3]);"
            ),
            values,
            update,
        )
        c.runtime(
            prefix + "_bool", "result = uvec4(bvec4(uV));", nonzero, update
        )
        c.runtime(
            prefix + "_minimum",
            "result = min(uV, 0x80000000u);",
            minimum,
            update,
        )
        c.runtime(
            prefix + "_ivec_roundtrip",
            "ivec4 a = ivec4(uV); result = uvec4(a);",
            values,
            update,
        )
        for flag in range(2):
            c.runtime(
                prefix + "_select_" + String(flag),
                "result = uFlag ? uV : uV.wzyx;",
                values.copy() if flag else reversed_values.copy(),
                _with_flag(values, flag),
            )
    return c.cases.copy()


def loop_cases() -> List[Case]:
    """Return the 35 loop cases.

    Returns:
        The cases, in catalog order.
    """
    var cases = List[Case]()
    for count in [63, 64, 65, 128, 256]:
        var sum = count * (count + 1) // 2
        for kind in ["while", "do"]:
            var bound = String(count) + "u"
            var inner = "i += 1u; total += i;"
            var body = "uint i = 0u; uint total = 0u;\n"
            if kind == "while":
                body += "while (i < " + bound + ") { " + inner + " }"
            else:
                body += "do { " + inner + " } while (i < " + bound + ");"
            body += "\nresult = uvec4(i, total, 0u, 1u);"
            cases.append(
                uint_case(
                    kind + "_finite_" + String(count),
                    body,
                    ints(count, sum, 0, 1),
                    category="loops",
                )
            )
            var declaration = (
                "bool condition(uint i, inout uint calls) { calls += 1u;"
                " return i < "
                + bound
                + "; }\n"
            )
            body = "uint i = 0u; uint total = 0u; uint calls = 0u;\n"
            if kind == "while":
                body += "while (condition(i, calls)) { " + inner + " }"
            else:
                body += "do { " + inner + " } while (condition(i, calls));"
            body += "\nresult = uvec4(i, total, calls, 1u);"
            cases.append(
                uint_case(
                    kind + "_condition_effects_" + String(count),
                    body,
                    ints(count, sum, count + Int(kind == "while"), 1),
                    declaration,
                    category="loops",
                )
            )
            inner = "i += 1u; total += gain;"
            body = "uint i = 0u; uint total = 4294967290u;\n"
            if kind == "while":
                body += "while (i < limit) { " + inner + " }"
            else:
                body += "do { " + inner + " } while (i < limit);"
            body += "\nresult = uvec4(i, total, gain, limit);"
            cases.append(
                uint_case(
                    kind + "_runtime_bound_" + String(count),
                    body,
                    ints(count, U32 - 5 + count * 16777217, 16777217, count),
                    "uniform uint gain; uniform uint limit;\n",
                    [
                        scalar("gain", "uint", 16777217),
                        scalar("limit", "uint", count),
                    ],
                    "loops",
                )
            )
    var odd_sum = 0
    for i in range(1, 65, 2):
        odd_sum += i
    for kind in ["while", "do"]:
        var head = "uint i = 0u; uint total = 0u; uint calls = 0u;\n"
        var loop = (
            "i += 1u; if (i == 65u) { break; } if ((i % 2u) == 0u) { continue;"
            " } total += i;"
        )
        var body = head
        if kind == "while":
            body += "while (condition(i,calls)) { " + loop + " }"
        else:
            body += "do { " + loop + " } while (condition(i,calls));"
        body += "result = uvec4(i,total,calls,1u);"
        cases.append(
            uint_case(
                kind + "_break_continue",
                body,
                ints(65, odd_sum, 65 if kind == "while" else 64, 1),
                (
                    "bool condition(uint i, inout uint calls) { calls += 1u;"
                    " return i < 256u; }\n"
                ),
                category="loops",
            )
        )
    var never = (
        "bool condition(uint i, inout uint calls) { calls += 1u; return false;"
        " }\n"
    )
    cases.append(
        uint_case(
            "while_zero_body",
            (
                "uint i = 0u; uint calls = 0u; while (condition(i,calls)) { i"
                " += 1u; } result = uvec4(i,calls,0u,1u);"
            ),
            ints(0, 1, 0, 1),
            never,
            category="loops",
        )
    )
    cases.append(
        uint_case(
            "do_minimum_one_body",
            (
                "uint i = 0u; uint calls = 0u; do { i += 1u; } while"
                " (condition(i,calls)); result = uvec4(i,calls,0u,1u);"
            ),
            ints(1, 1, 0, 1),
            never,
            category="loops",
        )
    )
    cases.append(
        uint_case(
            "while_nested_16_by_16",
            (
                "uint outer = 0u; uint total = 0u; while (outer < 16u) { uint"
                " inner = 0u; while (inner < 16u) { inner += 1u; total += 1u; }"
                " outer += 1u; } result = uvec4(outer,total,0u,1u);"
            ),
            ints(16, 256, 0, 1),
            category="loops",
        )
    )
    return cases^


# --- the analytical texture sampler ------------------------------------------


def texel(level: Int, x: Int, y: Int) -> List[Float64]:
    """Return the authored texel at a level and position.

    Args:
        level: The mip level, from 0 to 4.
        x: The column.
        y: The row.

    Returns:
        `[(level + 1) / 8, x / 16, y / 8, 1]`.
    """
    return [
        Float64(level + 1) / 8.0,
        Float64(x) / 16.0,
        Float64(y) / 8.0,
        1.0,
    ]


def wrap_index(index: Int, size: Int, mode: String) -> Int:
    """Return a texel index inside the level under a wrap mode.

    Args:
        index: The unwrapped index.
        size: The level's width or height.
        mode: `clamp`, `repeat` or `mirror`.

    Returns:
        The index from 0 to `size - 1`.
    """
    if mode == "clamp":
        return min(max(index, 0), size - 1)
    if mode == "repeat":
        return index % size
    var at = index % (2 * size)
    return at if at < size else 2 * size - 1 - at


def sample_level(
    level: Int, uv: List[Float64], texture: TextureRecipe, linear: Bool
) -> List[Float64]:
    """Sample one mip level, nearest or bilinear.

    Args:
        level: The mip level, from 0 to 4.
        uv: The texture coordinate.
        texture: The wrap modes.
        linear: True for bilinear filtering.

    Returns:
        The four lanes.
    """
    var width = max(1, 16 >> level)
    var height = max(1, 8 >> level)
    if not linear:
        var x = wrap_index(
            Int(floor(product(uv[0], Float64(width)))), width, texture.wrap_s
        )
        var y = wrap_index(
            Int(floor(product(uv[1], Float64(height)))), height, texture.wrap_t
        )
        return texel(level, x, y)
    var atx = product(uv[0], Float64(width)) - 0.5
    var aty = product(uv[1], Float64(height)) - 0.5
    var x = Int(floor(atx))
    var y = Int(floor(aty))
    var fx = atx - Float64(x)
    var fy = aty - Float64(y)
    var value: List[Float64] = [0.0, 0.0, 0.0, 0.0]
    for dx in range(2):
        var wx = fx if dx else 1.0 - fx
        for dy in range(2):
            var wy = fy if dy else 1.0 - fy
            var color = texel(
                level,
                wrap_index(x + dx, width, texture.wrap_s),
                wrap_index(y + dy, height, texture.wrap_t),
            )
            for lane in range(4):
                value[lane] += product(product(wx, wy), color[lane])
    return value^


def texture_expected(
    uv: List[Float64],
    dx: List[Float64],
    dy: List[Float64],
    texture: TextureRecipe,
) -> Tuple[List[Float64], Float64]:
    """Return the analytical `textureGrad` result and level of detail.

    Args:
        uv: The texture coordinate.
        dx: The coordinate's derivative along x.
        dy: The coordinate's derivative along y.
        texture: The filter and wrap modes.

    Returns:
        The four lanes and the level of detail.
    """
    var rho = max(
        hypot(product(dx[0], 16.0), product(dx[1], 8.0)),
        hypot(product(dy[0], 16.0), product(dy[1], 8.0)),
    )
    var lod = max(0.0, min(4.0, log2(rho))) if rho > 0 else 0.0
    if texture.min_filter == "nearest_mipmap_nearest":
        var level = min(4, Int(floor(lod + 0.5)))
        return (sample_level(level, uv, texture, False), lod)
    var low = Int(floor(lod))
    var high = min(4, low + 1)
    var fraction = lod - Float64(low)
    var linear = texture.min_filter == "linear_mipmap_linear"
    var a = sample_level(low, uv, texture, linear)
    var b = sample_level(high, uv, texture, linear)
    var out = List[Float64]()
    for lane in range(4):
        out.append(
            product(a[lane], 1.0 - fraction) + product(b[lane], fraction)
        )
    return (out^, lod)


def float32(value: Float64) -> Float64:
    """Return a value rounded to float32, as `struct` packs it.

    Args:
        value: The value.

    Returns:
        The nearest float32, as a Float64.
    """
    return Float64(Float32(value))


struct TextureCatalog(Movable):
    """The gradient cases."""

    var cases: List[Case]
    """The cases so far."""

    def __init__(out self):
        """Start empty."""
        self.cases = List[Case]()

    def add(
        mut self,
        name: String,
        uv: List[Float64],
        dx: List[Float64],
        dy: List[Float64],
        filtering: String = "nearest_mipmap_nearest",
        wrap: String = "clamp",
        body: String = "",
        eval_uv: List[Float64] = List[Float64](),
        eval_dx: List[Float64] = List[Float64](),
        eval_dy: List[Float64] = List[Float64](),
    ):
        """Add a case. The inputs are rounded to float32, as GLSL reads
        them. An `eval_` argument replaces the input in the expectation.

        Args:
            name: The fixture's name.
            uv: The coordinate uniform.
            dx: The x derivative uniform.
            dy: The y derivative uniform.
            filtering: The minification filter.
            wrap: The wrap mode on both axes.
            body: The body of `main`, or empty for the plain lookup.
            eval_uv: The coordinate of the expectation, when it differs.
            eval_dx: The x derivative of the expectation, when it differs.
            eval_dy: The y derivative of the expectation, when it differs.
        """
        var texture = TextureRecipe(filtering, wrap, wrap)
        var uv32 = pair(float32(uv[0]), float32(uv[1]))
        var dx32 = pair(float32(dx[0]), float32(dx[1]))
        var dy32 = pair(float32(dy[0]), float32(dy[1]))
        var result = texture_expected(
            eval_uv.copy() if eval_uv else uv32.copy(),
            eval_dx.copy() if eval_dx else dx32.copy(),
            eval_dy.copy() if eval_dy else dy32.copy(),
            texture,
        )
        var main_body = body if body else (
            "result = floatBitsToUint(textureGrad(source, uv, dx, dy));"
        )
        var uniforms: List[Uniform] = [
            scalar("source", "sampler2D", 0),
            vec2("uv", uv32^),
            vec2("dx", dx32^),
            vec2("dy", dy32^),
        ]
        self.cases.append(
            Case(
                name,
                "textureGrad",
                PREFIX
                + "uniform sampler2D source; uniform vec2 uv; uniform vec2 dx;"
                " uniform vec2 dy;\nvoid main() { "
                + main_body
                + " }\n",
                uniforms^,
                "float32_absolute",
                List[Int](),
                result[0].copy(),
                True,
                texture^,
                result[1],
                TOLERANCE,
            )
        )


def texture_cases() -> List[Case]:
    """Return the 28 `textureGrad` cases.

    Returns:
        The cases, in catalog order.
    """
    var c = TextureCatalog()
    var uv = pair(0.34375, 0.6875)
    for level in range(5):
        var scale = Float64(1 << level)
        c.add(
            "textureGrad_mip_" + String(level),
            uv,
            pair(scale / 16.0, 0),
            pair(0, scale / 8.0),
        )
    c.add("textureGrad_zero", uv, pair(0, 0), pair(0, 0))
    c.add(
        "textureGrad_magnification",
        uv,
        pair(1.0 / 64.0, 0),
        pair(0, 1.0 / 32.0),
    )
    c.add("textureGrad_minification_clamp", uv, pair(8, 0), pair(0, 8))
    c.add(
        "textureGrad_dx_dominates", uv, pair(1.0 / 2.0, 0), pair(0, 1.0 / 8.0)
    )
    c.add("textureGrad_dy_dominates", uv, pair(1.0 / 16.0, 0), pair(0, 1))
    c.add("textureGrad_rectangular_x", uv, pair(1.0 / 8.0, 0), pair(0, 0))
    c.add("textureGrad_rectangular_y", uv, pair(0, 1.0 / 8.0), pair(0, 0))
    c.add(
        "textureGrad_negative_gradients",
        uv,
        pair(-1.0 / 4.0, 0),
        pair(0, -1.0 / 2.0),
    )
    c.add(
        "textureGrad_swapped_derivatives",
        uv,
        pair(0, 1.0 / 2.0),
        pair(1.0 / 4.0, 0),
    )
    # Texel-space vector (2.4, 3.2), length 4.
    c.add("textureGrad_diagonal", uv, pair(0.15, 0.4), pair(0, 0))
    c.add(
        "textureGrad_nearest_below_mip_switch",
        uv,
        pair(power(2.0, 1.25) / 16.0, 0),
        pair(0, 0),
    )
    c.add(
        "textureGrad_nearest_above_mip_switch",
        uv,
        pair(power(2.0, 1.75) / 16.0, 0),
        pair(0, 0),
    )
    c.add(
        "textureGrad_trilinear_half",
        uv,
        pair(power(2.0, 1.5) / 16.0, 0),
        pair(0, 0),
        "nearest_mipmap_linear",
    )
    c.add(
        "textureGrad_bilinear",
        pair(0.375, 0.625),
        pair(1.0 / 16.0, 0),
        pair(0, 1.0 / 8.0),
        "linear_mipmap_linear",
    )
    c.add(
        "textureGrad_trilinear_bilinear",
        pair(0.375, 0.625),
        pair(power(2.0, 1.5) / 16.0, 0),
        pair(0, 0),
        "linear_mipmap_linear",
    )
    c.add(
        "textureGrad_uv_lower_left",
        pair(0.03125, 0.0625),
        pair(0, 0),
        pair(0, 0),
    )
    c.add(
        "textureGrad_uv_upper_right",
        pair(0.96875, 0.9375),
        pair(0, 0),
        pair(0, 0),
    )
    c.add("textureGrad_uv_clamp", pair(-0.25, 1.25), pair(0, 0), pair(0, 0))
    c.add(
        "textureGrad_uv_repeat",
        pair(1.34375, -0.3125),
        pair(0, 0),
        pair(0, 0),
        wrap="repeat",
    )
    c.add(
        "textureGrad_uv_mirror",
        pair(1.34375, -0.3125),
        pair(0, 0),
        pair(0, 0),
        wrap="mirror",
    )
    c.add(
        "textureGrad_uv_transform_fixed_grad",
        pair(0.125, 0.25),
        pair(1.0 / 16.0, 0),
        pair(0, 1.0 / 8.0),
        body=(
            "result = floatBitsToUint(textureGrad(source, uv * 2.0 +"
            " vec2(0.125,0.125), dx, dy));"
        ),
        eval_uv=pair(0.375, 0.625),
    )
    c.add(
        "textureGrad_uv_transform_scaled_grad",
        pair(0.125, 0.25),
        pair(1.0 / 16.0, 0),
        pair(0, 1.0 / 8.0),
        body=(
            "result = floatBitsToUint(textureGrad(source, uv * 2.0 +"
            " vec2(0.125,0.125), dx * 2.0, dy * 2.0));"
        ),
        eval_uv=pair(0.375, 0.625),
        eval_dx=pair(1.0 / 8.0, 0),
        eval_dy=pair(0, 1.0 / 4.0),
    )
    # Constants prove the parser path; uniforms above prove runtime inputs.
    c.add(
        "textureGrad_constant_arguments",
        uv,
        pair(1.0 / 4.0, 0),
        pair(0, 1.0 / 2.0),
        body=(
            "result = floatBitsToUint(textureGrad(source, vec2(0.34375,0.6875),"
            " vec2(0.25,0.0), vec2(0.0,0.5)));"
        ),
    )
    return c.cases.copy()


def catalog() -> List[Case]:
    """Return the full catalog: unsigned, loop and gradient cases.

    Returns:
        The 150 cases.
    """
    var cases = uint_cases()
    cases.extend(loop_cases())
    cases.extend(texture_cases())
    return cases^


# --- comparison and text -----------------------------------------------------


@fieldwise_init
struct Outcome(Copyable, Movable):
    """The comparison of one readback with its case."""

    var passed: Bool
    """True when the readback matches."""
    var ints: List[Int]
    """The observed words of an exact case."""
    var floats: List[Float64]
    """The observed lanes of a float case."""


def word_float(word: Int) -> Float64:
    """Return the float32 that a word encodes, as a Float64.

    Args:
        word: A value from 0 to 2**32 - 1.

    Returns:
        The float.
    """
    return Float64(bitcast[DType.float32](UInt32(word)))


def compare(fixture: Case, words: List[Int]) -> Outcome:
    """Compare a readback with a case.

    An exact case compares the words. A float case reads each word as a
    float32 and allows the case's absolute tolerance.

    Args:
        fixture: The case.
        words: The four words read back.

    Returns:
        The outcome and the observed values.
    """
    if fixture.exact():
        return Outcome(words == fixture.expected_ints, words.copy(), [])
    var actual = List[Float64]()
    var passed = len(fixture.expected_floats) == 4
    for i in range(4):
        actual.append(word_float(words[i]))
        if passed and not (
            isfinite(actual[i])
            and abs(actual[i] - fixture.expected_floats[i]) <= fixture.tolerance
        ):
            passed = False
    return Outcome(passed, [], actual^)


def float_text(value: Float64) raises -> String:
    """Return a float as `json.dumps` writes it.

    Args:
        value: The value.

    Returns:
        Python's `repr`, or `NaN`, `Infinity` or `-Infinity`.

    Raises:
        Error: If the shortest digits cannot be found.
    """
    if value != value:
        return "NaN"
    if not isfinite(value):
        return "Infinity" if value > 0 else "-Infinity"
    return python_repr(value)


def int_list_text(values: List[Int]) -> String:
    """Return integers as `json.dumps` writes a list on one line.

    Args:
        values: The integers.

    Returns:
        The text, for example `[0, 1]`.
    """
    var out = String("[")
    for i in range(len(values)):
        if i > 0:
            out += ", "
        out += String(values[i])
    return out + "]"


def float_list_text(values: List[Float64]) raises -> String:
    """Return floats as `json.dumps` writes a list on one line.

    Args:
        values: The floats.

    Returns:
        The text, for example `[0.5, 1.0]`.

    Raises:
        Error: If the shortest digits cannot be found.
    """
    var out = String("[")
    for i in range(len(values)):
        if i > 0:
            out += ", "
        out += float_text(values[i])
    return out + "]"


def observed_text(outcome: Outcome, exact: Bool) raises -> String:
    """Return the observed values as `json.dumps` writes them.

    Args:
        outcome: The outcome.
        exact: True for an exact case.

    Returns:
        The one-line list.

    Raises:
        Error: If the shortest digits cannot be found.
    """
    if exact:
        return int_list_text(outcome.ints)
    return float_list_text(outcome.floats)


def little_endian_hex(words: List[Int]) -> String:
    """Return words as `struct.pack("<4I", ...).hex()` does.

    Args:
        words: Values from 0 to 2**32 - 1.

    Returns:
        Eight hex digits for each word, low byte first.
    """
    var digits = HEX.as_bytes()
    var out = String()
    for word in words:
        for byte_index in range(4):
            var byte = (word >> (8 * byte_index)) & 255
            out += chr(Int(digits[byte >> 4]))
            out += chr(Int(digits[byte & 15]))
    return out^


def uint_tsv(cases: List[Case]) -> String:
    """Return `expected_uint32.tsv`.

    Args:
        cases: The catalog.

    Returns:
        A header and one row for each exact case.
    """
    var out = String("id\tr\tg\tb\ta\tlittle_endian_hex\n")
    for fixture in cases:
        if not fixture.exact():
            continue
        out += fixture.id
        for word in fixture.expected_ints:
            out += "\t" + String(word)
        out += "\t" + little_endian_hex(fixture.expected_ints) + "\n"
    return out^


def float_tsv(cases: List[Case]) raises -> String:
    """Return `expected_float32.tsv`.

    Args:
        cases: The catalog.

    Returns:
        A header and one row for each float case.

    Raises:
        Error: If the shortest digits cannot be found.
    """
    var out = String("id\tr\tg\tb\ta\tabs_tolerance\tanalytic_lod\n")
    for fixture in cases:
        if fixture.exact():
            continue
        out += fixture.id
        for lane in fixture.expected_floats:
            out += "\t" + python_repr(lane)
        out += "\t" + python_repr(fixture.tolerance)
        out += "\t" + python_repr(fixture.analytic_lod) + "\n"
    return out^


# --- reading a recorded file -------------------------------------------------


def _numbers(document: JsonDocument, node: Int) raises -> List[Int]:
    """Return the number nodes of a value: itself, or an array's items."""
    var items = List[Int]()
    if document.kind(node) == ARRAY:
        for i in range(document.length(node)):
            items.append(document.at(node, i))
    else:
        items.append(node)
    return items^


def read_uniform(
    document: JsonDocument, node: Int, name: String
) raises -> Uniform:
    """Read one recorded uniform.

    Args:
        document: The parsed file.
        node: The uniform's object, with `type` and `value`.
        name: The uniform's name.

    Returns:
        The uniform. A Boolean value is 0 or 1.

    Raises:
        Error: If the uniform has no type or value, or a value is not a
            number.
    """
    var kind = document.string(index(document, node, "type"))
    var value = index(document, node, "value")
    var whole = List[Int]()
    var floats = List[Float64]()
    for item in _numbers(document, value):
        var number: Float64
        if document.kind(item) == BOOLEAN:
            number = 1.0 if document.boolean(item) else 0.0
        else:
            number = document.number(item)
        floats.append(number)
        if number == floor(number) and abs(number) <= 9.0e15:
            whole.append(Int(number))
        else:
            whole.append(0)
    return Uniform(name, kind, whole^, floats^, document.kind(value) == ARRAY)


def read_case(document: JsonDocument, node: Int) raises -> Case:
    """Read one recorded case.

    Args:
        document: The parsed file.
        node: The case's object.

    Returns:
        The case.

    Raises:
        Error: If a required member is absent or has the wrong type.
    """
    var uniforms = List[Uniform]()
    var members = index(document, node, "uniforms")
    for i in range(document.length(members)):
        var name = document.key(members, i)
        uniforms.append(
            read_uniform(document, document.get(members, name), name)
        )
    var comparison = document.string(index(document, node, "comparison"))
    var expected = index(document, node, "expected")
    var expected_ints = List[Int]()
    var expected_floats = List[Float64]()
    for i in range(document.length(expected)):
        var number = document.number(document.at(expected, i))
        expected_floats.append(number)
        if comparison == "exact_uint32":
            # A word is never negative, so -1 marks a value with a fraction.
            var whole = number == floor(number) and abs(number) <= 9.0e15
            expected_ints.append(Int(number) if whole else -1)
    var texture = TextureRecipe("", "", "")
    var recipe = get(document, node, "texture")
    if not is_none(document, recipe):
        texture = TextureRecipe(
            document.string(index(document, recipe, "min_filter")),
            document.string(index(document, recipe, "wrap_s")),
            document.string(index(document, recipe, "wrap_t")),
        )
    var tolerance = 0.0
    if comparison != "exact_uint32":
        tolerance = document.number(index(document, node, "absolute_tolerance"))
    var lod = get(document, node, "analytic_lod")
    return Case(
        document.string(index(document, node, "id")),
        document.string(index(document, node, "category")),
        document.string(index(document, node, "fragment_source")),
        uniforms^,
        comparison,
        expected_ints^,
        expected_floats^,
        not is_none(document, recipe),
        texture^,
        0.0 if is_none(document, lod) else document.number(lod),
        tolerance,
    )


def read_cases(text: String) raises -> List[Case]:
    """Read the cases of a recorded fixtures file.

    Args:
        text: The file's JSON text.

    Returns:
        The cases, in file order.

    Raises:
        Error: If the text is not JSON or a case is malformed.
    """
    var document = parse_json(text)
    var cases = index(document, document.root(), "cases")
    var out = List[Case]()
    for i in range(document.length(cases)):
        out.append(read_case(document, document.at(cases, i)))
    return out^


# --- the GLES context --------------------------------------------------------


def c_string(text: String) -> List[UInt8]:
    """Return a string's bytes and a terminating zero.

    Args:
        text: The string.

    Returns:
        The C string.
    """
    var out = List[UInt8](capacity=text.byte_length() + 1)
    for byte in text.as_bytes():
        out.append(byte)
    out.append(0)
    return out^


def read_c_string(address: Int) -> String:
    """Copy a C string that the driver owns.

    Args:
        address: The string's address. Zero gives an empty string.

    Returns:
        The string.
    """
    if address == 0:
        return String()
    var length = external_call["strlen", Int](address)
    var bytes = List[UInt8](length=length, fill=0)
    _ = external_call["memcpy", Int](
        bytes.unsafe_ptr().unsafe_bitcast[NoneType](), address, length
    )
    return String(unsafe_from_utf8=bytes)


def text_before_zero(bytes: List[UInt8]) -> String:
    """Return the text of a buffer up to its first zero byte.

    Args:
        bytes: The buffer.

    Returns:
        The text.
    """
    var out = List[UInt8]()
    for byte in bytes:
        if byte == 0:
            break
        out.append(byte)
    return String(unsafe_from_utf8=out)


def hex4(value: Int) -> String:
    """Return at least four lowercase hex digits, as `f"{value:04x}"` does.

    Args:
        value: A non-negative value.

    Returns:
        The digits.
    """
    var digits = HEX.as_bytes()
    var out = String()
    var rest = value
    while rest > 0 or out.byte_length() < 4:
        out = chr(Int(digits[rest & 15])) + out
        rest >>= 4
    return out^


def load_library(name: String) raises -> OwnedDLHandle:
    """Load a system library, with an error that names it.

    Args:
        name: The library's file name, for example `libEGL.so.1`.

    Returns:
        The loaded library.

    Raises:
        Error: If the library cannot be loaded. The message names the
            library and the Mesa packages that supply it.
    """
    try:
        return OwnedDLHandle(name)
    except error:
        raise Error(
            "cannot load "
            + name
            + ". The reference needs Mesa's EGL and GLES 3 libraries"
            " (libegl1, libgles2 and libegl-mesa0 on Debian and Ubuntu): "
            + String(error)
        )


struct Gles(Movable):
    """A headless, software-only GLES 3 context with checked API calls."""

    var egl: OwnedDLHandle
    """`libEGL.so.1`."""
    var gl: OwnedDLHandle
    """`libGLESv2.so.2`."""
    var display: Int
    """The EGL display."""
    var context: Int
    """The EGL context."""
    var surface: Int
    """The 1-by-1 pbuffer surface."""
    var vertex: UInt32
    """The compiled vertex shader."""
    var vao: List[UInt32]
    """The vertex array object."""
    var output: List[UInt32]
    """The RGBA32UI render target."""
    var fbo: List[UInt32]
    """The framebuffer object."""
    var egl_version: String
    """The EGL version, `major.minor`."""
    var vendor: String
    """`GL_VENDOR`."""
    var renderer: String
    """`GL_RENDERER`."""
    var version: String
    """`GL_VERSION`."""
    var shading_language_version: String
    """`GL_SHADING_LANGUAGE_VERSION`."""

    def __init__(out self) raises:
        """Open a surfaceless software context and its RGBA32UI target.

        Raises:
            Error: If a library cannot be loaded, or EGL or GLES fails.
        """
        _ = setenv("LIBGL_ALWAYS_SOFTWARE", "1")
        _ = setenv("EGL_PLATFORM", "surfaceless")
        _ = setenv("MESA_SHADER_CACHE_DISABLE", "true")
        self.egl = load_library("libEGL.so.1")
        self.gl = load_library("libGLESv2.so.2")
        self.display = 0
        self.context = 0
        self.surface = 0
        self.vertex = 0
        self.vao = [0]
        self.output = [0]
        self.fbo = [0]
        self.egl_version = String()
        self.vendor = String()
        self.renderer = String()
        self.version = String()
        self.shading_language_version = String()
        self.display = self.egl.call["eglGetDisplay", Int](0)
        self.require(self.display != 0, "eglGetDisplay")
        var major: List[Int32] = [0]
        var minor: List[Int32] = [0]
        self.require(
            self.egl.call["eglInitialize", UInt32](
                self.display,
                major.unsafe_ptr().unsafe_bitcast[NoneType](),
                minor.unsafe_ptr().unsafe_bitcast[NoneType](),
            )
            != 0,
            "eglInitialize",
        )
        self.egl_version = String(major[0]) + "." + String(minor[0])
        var attributes: List[Int32] = [
            0x3033,
            1,
            0x3040,
            0x40,
            0x3024,
            8,
            0x3023,
            8,
            0x3022,
            8,
            0x3021,
            8,
            0x3038,
        ]
        var config: List[Int] = [0]
        var count: List[Int32] = [0]
        self.require(
            self.egl.call["eglChooseConfig", UInt32](
                self.display,
                attributes.unsafe_ptr().unsafe_bitcast[NoneType](),
                config.unsafe_ptr().unsafe_bitcast[NoneType](),
                Int32(1),
                count.unsafe_ptr().unsafe_bitcast[NoneType](),
            )
            != 0,
            "eglChooseConfig",
        )
        _ = len(attributes)
        if count[0] != 1:
            raise Error("No ES3 pbuffer EGL configuration")
        self.require(
            self.egl.call["eglBindAPI", UInt32](UInt32(0x30A0)) != 0,
            "eglBindAPI",
        )
        var context_attributes: List[Int32] = [0x3098, 3, 0x3038]
        self.context = self.egl.call["eglCreateContext", Int](
            self.display,
            config[0],
            0,
            context_attributes.unsafe_ptr().unsafe_bitcast[NoneType](),
        )
        _ = len(context_attributes)
        self.require(self.context != 0, "eglCreateContext")
        var surface_attributes: List[Int32] = [0x3057, 1, 0x3056, 1, 0x3038]
        self.surface = self.egl.call["eglCreatePbufferSurface", Int](
            self.display,
            config[0],
            surface_attributes.unsafe_ptr().unsafe_bitcast[NoneType](),
        )
        _ = len(surface_attributes)
        self.require(self.surface != 0, "eglCreatePbufferSurface")
        self.require(
            self.egl.call["eglMakeCurrent", UInt32](
                self.display, self.surface, self.surface, self.context
            )
            != 0,
            "eglMakeCurrent",
        )
        self.vendor = self.gl_string(0x1F00)
        self.renderer = self.gl_string(0x1F01)
        self.version = self.gl_string(0x1F02)
        self.shading_language_version = self.gl_string(0x8B8C)
        if not self.version.startswith("OpenGL ES 3."):
            raise Error("Reference requires OpenGL ES 3")
        self.vertex = self.shader(0x8B31, VERTEX)
        self.gl.call["glGenVertexArrays", NoneType](
            Int32(1), self.vao.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        self.gl.call["glBindVertexArray", NoneType](self.vao[0])
        self.gl.call["glGenTextures", NoneType](
            Int32(1), self.output.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        self.gl.call["glBindTexture", NoneType](UInt32(0x0DE1), self.output[0])
        # GL_RGBA32UI storage and GL_RGBA_INTEGER/GL_UNSIGNED_INT transfer.
        self.gl.call["glTexImage2D", NoneType](
            UInt32(0x0DE1),
            Int32(0),
            Int32(0x8D70),
            Int32(1),
            Int32(1),
            Int32(0),
            UInt32(0x8D99),
            UInt32(0x1405),
            0,
        )
        self.parameter(0x2801, 0x2600)
        self.parameter(0x2800, 0x2600)
        self.gl.call["glGenFramebuffers", NoneType](
            Int32(1), self.fbo.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        self.gl.call["glBindFramebuffer", NoneType](UInt32(0x8D40), self.fbo[0])
        self.gl.call["glFramebufferTexture2D", NoneType](
            UInt32(0x8D40),
            UInt32(0x8CE0),
            UInt32(0x0DE1),
            self.output[0],
            Int32(0),
        )
        if (
            self.gl.call["glCheckFramebufferStatus", UInt32](UInt32(0x8D40))
            != 0x8CD5
        ):
            raise Error("RGBA32UI framebuffer is incomplete")
        self.gl.call["glViewport", NoneType](
            Int32(0), Int32(0), Int32(1), Int32(1)
        )
        self.check("initialize GLES")

    def provenance(self) -> String:
        """Return the driver's provenance as `json.dumps(..., sort_keys=True)`
        writes it on one line.

        Returns:
            The JSON object.
        """
        return (
            '{"egl_version": '
            + quote_ascii(self.egl_version)
            + ', "renderer": '
            + quote_ascii(self.renderer)
            + ', "shading_language_version": '
            + quote_ascii(self.shading_language_version)
            + ', "vendor": '
            + quote_ascii(self.vendor)
            + ', "version": '
            + quote_ascii(self.version)
            + "}"
        )

    def write_provenance(self, mut writer: JsonWriter):
        """Write the driver's provenance as an object with sorted keys.

        Args:
            writer: The JSON writer.
        """
        writer.begin_object()
        writer.key("egl_version")
        writer.string(self.egl_version)
        writer.key("renderer")
        writer.string(self.renderer)
        writer.key("shading_language_version")
        writer.string(self.shading_language_version)
        writer.key("vendor")
        writer.string(self.vendor)
        writer.key("version")
        writer.string(self.version)
        writer.end()

    def gl_string(self, name: Int) -> String:
        """Return a `glGetString` value.

        Args:
            name: The enum, for example `GL_VERSION`.

        Returns:
            The string.
        """
        return read_c_string(self.gl.call["glGetString", Int](UInt32(name)))

    def parameter(self, name: Int, value: Int):
        """Set a parameter of the bound 2D texture.

        Args:
            name: The parameter enum.
            value: The value.
        """
        self.gl.call["glTexParameteri", NoneType](
            UInt32(0x0DE1), UInt32(name), Int32(value)
        )

    def require(self, ok: Bool, action: String) raises:
        """Raise the EGL error when a call failed.

        Args:
            ok: Whether the call succeeded.
            action: The call's name.

        Raises:
            Error: `action: EGL error 0x....` when `ok` is False.
        """
        if not ok:
            var error = Int(self.egl.call["eglGetError", UInt32]())
            raise Error(action + ": EGL error 0x" + hex4(error))

    def check(self, action: String) raises:
        """Raise the GL error when one is pending.

        Args:
            action: What was done.

        Raises:
            Error: `action: GL error 0x....` when GL reports an error.
        """
        var error = Int(self.gl.call["glGetError", UInt32]())
        if error != 0:
            raise Error(action + ": GL error 0x" + hex4(error))

    def shader(self, kind: Int, source: String) raises -> UInt32:
        """Compile a shader.

        Args:
            kind: `GL_VERTEX_SHADER` or `GL_FRAGMENT_SHADER`.
            source: The GLSL source.

        Returns:
            The shader object.

        Raises:
            Error: The compile log and the source when compilation fails.
        """
        var shader = self.gl.call["glCreateShader", UInt32](UInt32(kind))
        var text = c_string(source)
        var strings: List[Int] = [Int(text.unsafe_ptr())]
        self.gl.call["glShaderSource", NoneType](
            shader,
            Int32(1),
            strings.unsafe_ptr().unsafe_bitcast[NoneType](),
            0,
        )
        _ = len(text)
        _ = len(strings)
        self.gl.call["glCompileShader", NoneType](shader)
        var ok: List[Int32] = [0]
        self.gl.call["glGetShaderiv", NoneType](
            shader, UInt32(0x8B81), ok.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        if ok[0] == 0:
            var message = List[UInt8](length=16384, fill=0)
            self.gl.call["glGetShaderInfoLog", NoneType](
                shader,
                Int32(len(message)),
                0,
                message.unsafe_ptr().unsafe_bitcast[NoneType](),
            )
            raise Error(text_before_zero(message) + "\n" + source)
        return shader

    def set_uniform(self, program: UInt32, uniform: Uniform) raises:
        """Set one uniform of the current program.

        An inactive uniform has no location, and GLSL can optimize an
        unused input away, so it is skipped.

        Args:
            program: The linked program.
            uniform: The uniform.

        Raises:
            Error: If the uniform's type is not known.
        """
        var name = c_string(uniform.name)
        var location = self.gl.call["glGetUniformLocation", Int32](
            program, name.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        _ = len(name)
        if location == -1:
            return
        ref kind = uniform.kind
        ref n = uniform.ints
        ref f = uniform.floats
        if kind == "uint":
            self.gl.call["glUniform1ui", NoneType](location, UInt32(n[0]))
        elif kind == "int" or kind == "bool" or kind == "sampler2D":
            self.gl.call["glUniform1i", NoneType](location, Int32(n[0]))
        elif kind == "float":
            self.gl.call["glUniform1f", NoneType](location, Float32(f[0]))
        elif kind == "vec2":
            self.gl.call["glUniform2f", NoneType](
                location, Float32(f[0]), Float32(f[1])
            )
        elif kind == "uvec2":
            self.gl.call["glUniform2ui", NoneType](
                location, UInt32(n[0]), UInt32(n[1])
            )
        elif kind == "uvec3":
            self.gl.call["glUniform3ui", NoneType](
                location, UInt32(n[0]), UInt32(n[1]), UInt32(n[2])
            )
        elif kind == "uvec4":
            self.gl.call["glUniform4ui", NoneType](
                location,
                UInt32(n[0]),
                UInt32(n[1]),
                UInt32(n[2]),
                UInt32(n[3]),
            )
        else:
            raise Error(kind)

    def render(self, fixture: Case) raises -> List[Int]:
        """Draw a case and read back its four words.

        Args:
            fixture: The case.

        Returns:
            The four RGBA32UI words.

        Raises:
            Error: If the shader does not compile or link, or GL reports an
                error.
        """
        var fragment = self.shader(0x8B30, fixture.fragment_source)
        var program = self.gl.call["glCreateProgram", UInt32]()
        self.gl.call["glAttachShader", NoneType](program, self.vertex)
        self.gl.call["glAttachShader", NoneType](program, fragment)
        self.gl.call["glLinkProgram", NoneType](program)
        var ok: List[Int32] = [0]
        self.gl.call["glGetProgramiv", NoneType](
            program, UInt32(0x8B82), ok.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        if ok[0] == 0:
            var message = List[UInt8](length=16384, fill=0)
            self.gl.call["glGetProgramInfoLog", NoneType](
                program,
                Int32(len(message)),
                0,
                message.unsafe_ptr().unsafe_bitcast[NoneType](),
            )
            raise Error(text_before_zero(message))
        self.gl.call["glUseProgram", NoneType](program)
        for uniform in fixture.uniforms:
            self.set_uniform(program, uniform)
        var texture: List[UInt32] = [0]
        if fixture.has_texture:
            texture[0] = self.texture(fixture.texture)
        self.gl.call["glDrawArrays", NoneType](
            UInt32(0x0004), Int32(0), Int32(3)
        )
        self.gl.call["glFinish", NoneType]()
        var output: List[UInt32] = [0, 0, 0, 0]
        self.gl.call["glReadPixels", NoneType](
            Int32(0),
            Int32(0),
            Int32(1),
            Int32(1),
            UInt32(0x8D99),
            UInt32(0x1405),
            output.unsafe_ptr().unsafe_bitcast[NoneType](),
        )
        self.check(fixture.id)
        var words = List[Int]()
        for word in output:
            words.append(Int(word))
        self.gl.call["glDeleteProgram", NoneType](program)
        self.gl.call["glDeleteShader", NoneType](fragment)
        if fixture.has_texture:
            self.gl.call["glDeleteTextures", NoneType](
                Int32(1), texture.unsafe_ptr().unsafe_bitcast[NoneType]()
            )
        return words^

    def texture(self, recipe: TextureRecipe) raises -> UInt32:
        """Upload the authored five-level RGBA16F texture to unit 0.

        Binary fractions are exact in RGBA16F. GLES 3.0 supports filtering
        it.

        Args:
            recipe: The filter and wrap modes.

        Returns:
            The texture object.

        Raises:
            Error: If a mode is not known, or GL reports an error.
        """
        var texture: List[UInt32] = [0]
        self.gl.call["glGenTextures", NoneType](
            Int32(1), texture.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        self.gl.call["glActiveTexture", NoneType](UInt32(0x84C0))
        self.gl.call["glBindTexture", NoneType](UInt32(0x0DE1), texture[0])
        for level in range(5):
            var width = max(1, 16 >> level)
            var height = max(1, 8 >> level)
            var pixels = List[Float32]()
            for y in range(height):
                for x in range(width):
                    for component in texel(level, x, y):
                        pixels.append(Float32(component))
            self.gl.call["glTexImage2D", NoneType](
                UInt32(0x0DE1),
                Int32(level),
                Int32(0x881A),
                Int32(width),
                Int32(height),
                Int32(0),
                UInt32(0x1908),
                UInt32(0x1406),
                pixels.unsafe_ptr().unsafe_bitcast[NoneType](),
            )
            _ = len(pixels)
        var filters: Int
        if recipe.min_filter == "nearest_mipmap_nearest":
            filters = 0x2700
        elif recipe.min_filter == "nearest_mipmap_linear":
            filters = 0x2702
        elif recipe.min_filter == "linear_mipmap_linear":
            filters = 0x2703
        else:
            raise Error("'" + recipe.min_filter + "'")
        self.parameter(0x2801, filters)
        self.parameter(0x2800, 0x2601 if recipe.linear() else 0x2600)
        self.parameter(0x2802, wrap_enum(recipe.wrap_s))
        self.parameter(0x2803, wrap_enum(recipe.wrap_t))
        self.parameter(0x813D, 4)
        self.check("upload texture")
        return texture[0]

    def close(mut self):
        """Delete the objects and release the context."""
        self.gl.call["glDeleteShader", NoneType](self.vertex)
        self.gl.call["glDeleteFramebuffers", NoneType](
            Int32(1), self.fbo.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        self.gl.call["glDeleteTextures", NoneType](
            Int32(1), self.output.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        self.gl.call["glDeleteVertexArrays", NoneType](
            Int32(1), self.vao.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        _ = self.egl.call["eglMakeCurrent", UInt32](self.display, 0, 0, 0)
        _ = self.egl.call["eglDestroySurface", UInt32](
            self.display, self.surface
        )
        _ = self.egl.call["eglDestroyContext", UInt32](
            self.display, self.context
        )
        _ = self.egl.call["eglTerminate", UInt32](self.display)


def wrap_enum(mode: String) raises -> Int:
    """Return the GL wrap enum of a mode.

    Args:
        mode: `clamp`, `repeat` or `mirror`.

    Returns:
        `GL_CLAMP_TO_EDGE`, `GL_REPEAT` or `GL_MIRRORED_REPEAT`.

    Raises:
        Error: If the mode is not known.
    """
    if mode == "clamp":
        return 0x812F
    if mode == "repeat":
        return 0x2901
    if mode == "mirror":
        return 0x8370
    raise Error("'" + mode + "'")


# --- the report --------------------------------------------------------------


@fieldwise_init
struct Record(Copyable, Movable):
    """The result of one rendered case."""

    var words: List[Int]
    """The four words read back."""
    var outcome: Outcome
    """The comparison with the case."""
    var elapsed: Float64
    """The case's time, in seconds."""


def seconds_since(start: Int) -> Float64:
    """Return the seconds since a `perf_counter_ns` reading.

    Args:
        start: The earlier reading.

    Returns:
        The elapsed time.
    """
    return Float64(perf_counter_ns() - start) / 1e9


def two_digits(value: Int, width: Int = 2) -> String:
    """Return a value padded with zeros on the left.

    Args:
        value: A non-negative value.
        width: The minimum number of digits.

    Returns:
        The digits.
    """
    var out = String(value)
    while out.byte_length() < width:
        out = "0" + out
    return out^


def utc_now() -> String:
    """Return the time as `datetime.now(timezone.utc).isoformat()` does.

    Returns:
        For example `2026-10-14T22:40:44.123456+00:00`.
    """
    var now: List[Int64] = [0, 0]
    _ = external_call["clock_gettime", Int32](
        Int32(0), now.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    var seconds = Int(now[0])
    var micro = Int(now[1]) // 1000
    var days = seconds // 86400
    var rest = seconds - days * 86400
    # Howard Hinnant's days-to-civil conversion.
    var z = days + 719468
    var era = z // 146097
    var doe = z - era * 146097
    var yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    var doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    var mp = (5 * doy + 2) // 153
    var day = doy - (153 * mp + 2) // 5 + 1
    var month = mp + 3 if mp < 10 else mp - 9
    var year = yoe + era * 400 + Int(month <= 2)
    var out = (
        two_digits(year, 4)
        + "-"
        + two_digits(month)
        + "-"
        + two_digits(day)
        + "T"
        + two_digits(rest // 3600)
        + ":"
        + two_digits((rest // 60) % 60)
        + ":"
        + two_digits(rest % 60)
    )
    if micro:
        out += "." + two_digits(micro, 6)
    return out + "+00:00"


def platform_text() -> String:
    """Return the platform as `platform.platform()` writes it on Linux.

    Returns:
        For example `Linux-6.18.44-x86_64-with-glibc2.41`.
    """
    # struct utsname on Linux: six fields of 65 bytes each.
    var name = List[UInt8](length=6 * 65, fill=0)
    if (
        external_call["uname", Int32](
            name.unsafe_ptr().unsafe_bitcast[NoneType]()
        )
        != 0
    ):
        return "unknown"
    var system = text_before_zero(List[UInt8](name[0:65]))
    var release = text_before_zero(List[UInt8](name[130:195]))
    var machine = text_before_zero(List[UInt8](name[260:325]))
    var out = system + "-" + release + "-" + machine
    try:
        var libc = OwnedDLHandle()
        var version = read_c_string(libc.call["gnu_get_libc_version", Int]())
        out += "-with-glibc" + version
    except:
        pass
    return out^


def write_uniforms(mut writer: JsonWriter, uniforms: List[Uniform]):
    """Write uniforms as an object with sorted keys.

    Args:
        writer: The JSON writer.
        uniforms: The uniforms.
    """
    var order = List[Int]()
    for i in range(len(uniforms)):
        var at = len(order)
        while at > 0 and uniforms[order[at - 1]].name > uniforms[i].name:
            at -= 1
        order.insert(at, i)
    writer.begin_object()
    for i in order:
        ref uniform = uniforms[i]
        writer.key(uniform.name)
        writer.begin_object()
        writer.key("type")
        writer.string(uniform.kind)
        writer.key("value")
        if uniform.vector:
            writer.begin_array()
        var count = len(uniform.floats) if uniform.is_float() else len(
            uniform.ints
        )
        for item in range(count):
            if uniform.is_float():
                writer.number(uniform.floats[item])
            else:
                writer.integer(uniform.ints[item])
        if uniform.vector:
            writer.end()
        writer.end()
    writer.end()


def write_ints(mut writer: JsonWriter, values: List[Int]):
    """Write a list of integers.

    Args:
        writer: The JSON writer.
        values: The integers.
    """
    writer.begin_array()
    for value in values:
        writer.integer(value)
    writer.end()


def write_floats(mut writer: JsonWriter, values: List[Float64]):
    """Write a list of floats.

    Args:
        writer: The JSON writer.
        values: The floats.
    """
    writer.begin_array()
    for value in values:
        writer.number(value)
    writer.end()


def write_record(mut writer: JsonWriter, fixture: Case, record: Record):
    """Write one case and its result as an object with sorted keys.

    Args:
        writer: The JSON writer.
        fixture: The case.
        record: The result.
    """
    writer.begin_object()
    if not fixture.exact():
        writer.key("absolute_tolerance")
        writer.number(fixture.tolerance)
        writer.key("analytic_lod")
        writer.number(fixture.analytic_lod)
    writer.key("category")
    writer.string(fixture.category)
    writer.key("comparison")
    writer.string(fixture.comparison)
    writer.key("elapsed_seconds")
    writer.number(record.elapsed)
    writer.key("expected")
    if fixture.exact():
        write_ints(writer, fixture.expected_ints)
    else:
        write_floats(writer, fixture.expected_floats)
    writer.key("fragment_source")
    writer.string(fixture.fragment_source)
    writer.key("id")
    writer.string(fixture.id)
    writer.key("observed")
    if fixture.exact():
        write_ints(writer, record.outcome.ints)
    else:
        write_floats(writer, record.outcome.floats)
    writer.key("passed")
    writer.boolean(record.outcome.passed)
    writer.key("readback_little_endian_hex")
    writer.string(little_endian_hex(record.words))
    writer.key("readback_uint32")
    write_ints(writer, record.words)
    if fixture.has_texture:
        writer.key("texture")
        writer.begin_object()
        writer.key("base_height")
        writer.integer(8)
        writer.key("base_width")
        writer.integer(16)
        writer.key("internal_format")
        writer.string("RGBA16F")
        writer.key("levels")
        writer.integer(5)
        writer.key("mag_filter")
        writer.string("linear" if fixture.texture.linear() else "nearest")
        writer.key("min_filter")
        writer.string(fixture.texture.min_filter)
        writer.key("texel_formula")
        writer.string("[(level+1)/8, x/16, y/8, 1]")
        writer.key("wrap_s")
        writer.string(fixture.texture.wrap_s)
        writer.key("wrap_t")
        writer.string(fixture.texture.wrap_t)
        writer.end()
    writer.key("uniforms")
    write_uniforms(writer, fixture.uniforms)
    writer.end()


@fieldwise_init
struct Summary(Copyable, Movable):
    """The counts of a run."""

    var count: Int
    """The cases rendered."""
    var loops: Int
    """The cases in the `loops` category."""
    var texture_grad: Int
    """The cases in the `textureGrad` category."""
    var uint: Int
    """The cases in the `uint` category."""
    var failed: Int
    """The cases that did not match."""
    var elapsed: Float64
    """The run's time, in seconds."""

    def text(self) raises -> String:
        """Return the summary as `json.dumps(..., sort_keys=True)` writes it.

        Returns:
            The one-line JSON object.

        Raises:
            Error: If the shortest digits cannot be found.
        """
        return (
            '{"count": '
            + String(self.count)
            + ', "counts": {"loops": '
            + String(self.loops)
            + ', "textureGrad": '
            + String(self.texture_grad)
            + ', "uint": '
            + String(self.uint)
            + '}, "elapsed_seconds": '
            + float_text(self.elapsed)
            + ', "failed": '
            + String(self.failed)
            + ', "passed": '
            + String(self.count - self.failed)
            + "}"
        )

    def write(self, mut writer: JsonWriter):
        """Write the summary as an object with sorted keys.

        Args:
            writer: The JSON writer.
        """
        writer.begin_object()
        writer.key("count")
        writer.integer(self.count)
        writer.key("counts")
        writer.begin_object()
        writer.key("loops")
        writer.integer(self.loops)
        writer.key("textureGrad")
        writer.integer(self.texture_grad)
        writer.key("uint")
        writer.integer(self.uint)
        writer.end()
        writer.key("elapsed_seconds")
        writer.number(self.elapsed)
        writer.key("failed")
        writer.integer(self.failed)
        writer.key("passed")
        writer.integer(self.count - self.failed)
        writer.end()


def summarize(
    cases: List[Case], records: List[Record], elapsed: Float64
) -> Summary:
    """Count the cases by category and the failures.

    Args:
        cases: The cases that were selected.
        records: The results so far.
        elapsed: The run's time, in seconds.

    Returns:
        The summary.
    """
    var loops = 0
    var texture_grad = 0
    var uint = 0
    for fixture in cases:
        if fixture.category == "loops":
            loops += 1
        elif fixture.category == "textureGrad":
            texture_grad += 1
        elif fixture.category == "uint":
            uint += 1
    var failed = 0
    for record in records:
        if not record.outcome.passed:
            failed += 1
    return Summary(len(records), loops, texture_grad, uint, failed, elapsed)


def report_text(
    gl: Gles,
    cases: List[Case],
    records: List[Record],
    summary: Summary,
) raises -> String:
    """Return `fixtures.json`, as `json.dumps(indent=2, sort_keys=True)`
    writes it.

    Args:
        gl: The context, for its provenance.
        cases: The catalog.
        records: The result of each case.
        summary: The counts.

    Returns:
        The JSON text and a final newline.

    Raises:
        Error: If the generator's source cannot be read.
    """
    var writer = JsonWriter()
    writer.begin_object()
    writer.key("cases")
    writer.begin_array()
    for i in range(len(records)):
        write_record(writer, cases[i], records[i])
    writer.end()
    writer.key("generated_at_utc")
    writer.string(utc_now())
    writer.key("reference")
    writer.begin_object()
    writer.key("api_shader_version")
    writer.string("#version 300 es")
    writer.key("driver")
    gl.write_provenance(writer)
    writer.key("generator_sha256")
    writer.string(sha256_hex(Path(source_path()).read_bytes()))
    writer.key("issue")
    writer.string("https://github.com/SethKitchen/ThreeMojo/issues/614")
    writer.key("method")
    writer.string(
        "Mojo FFI (OwnedDLHandle), surfaceless EGL, GLES shaders executed by"
        " Mesa software rasterizer"
    )
    writer.key("mojo")
    writer.string(MOJO_VERSION)
    writer.key("platform")
    writer.string(platform_text())
    writer.key("readback")
    writer.string(
        "GL_RGBA32UI framebuffer; GL_RGBA_INTEGER / GL_UNSIGNED_INT; float"
        " samples encoded with floatBitsToUint"
    )
    writer.key("source_checkout_commit")
    writer.string("e53600eb4b0551bbe9900ea0e8b7151e49553a2d")
    writer.key("source_checkout_role")
    writer.string(
        "Read-only context only. No ThreeMojo implementation imports or"
        " executions."
    )
    writer.key("specification")
    writer.string(
        "https://registry.khronos.org/OpenGL/specs/es/3.0/GLSL_ES_Specification_3.00.pdf"
    )
    writer.key("texture_reference")
    writer.string(
        "https://registry.khronos.org/OpenGL-Refpages/es3.0/html/textureGrad.xhtml"
    )
    writer.end()
    writer.key("schema")
    writer.string("threemojo-glsl614-gles3-reference-v1")
    writer.key("summary")
    summary.write(writer)
    writer.key("vertex_source")
    writer.string(VERTEX)
    writer.end()
    return writer.text() + "\n"


def write_expected(mut writer: JsonWriter, fixture: Case):
    """Write a case's expected values. In an exact case, a whole value is an
    integer and a value with a fraction is a float.

    Args:
        writer: The JSON writer.
        fixture: The case.
    """
    writer.begin_array()
    for i in range(len(fixture.expected_floats)):
        if fixture.exact() and fixture.expected_ints[i] >= 0:
            writer.integer(fixture.expected_ints[i])
        else:
            writer.number(fixture.expected_floats[i])
    writer.end()


def failures_text(cases: List[Case], records: List[Record]) raises -> String:
    """Return the failures as `json.dumps(failures, indent=2)` writes them.

    Args:
        cases: The cases.
        records: The result of each case.

    Returns:
        A JSON array of objects with `id`, `expected` and `actual`.
    """
    var writer = JsonWriter()
    writer.begin_array()
    for i in range(len(records)):
        if records[i].outcome.passed:
            continue
        writer.begin_object()
        writer.key("id")
        writer.string(cases[i].id)
        writer.key("expected")
        write_expected(writer, cases[i])
        writer.key("actual")
        if cases[i].exact():
            write_ints(writer, records[i].outcome.ints)
        else:
            write_floats(writer, records[i].outcome.floats)
        writer.end()
    writer.end()
    return writer.text()


def source_path() -> String:
    """Return the path of this tool's source, recorded at compile time.

    Returns:
        The absolute path of `reference_glsl614.mojo`.
    """
    return String(source_location().file_name())


def write_outputs(
    output: String,
    gl: Gles,
    cases: List[Case],
    records: List[Record],
    summary: Summary,
) raises:
    """Write the generated fixtures.

    Args:
        output: The output directory.
        gl: The context, for its provenance.
        cases: The catalog.
        records: The result of each case.
        summary: The counts.

    Raises:
        Error: If a file cannot be written.
    """
    makedirs(output + "/shaders", exist_ok=True)
    Path(output + "/shaders/fullscreen.vert").write_text(VERTEX)
    for fixture in cases:
        Path(output + "/shaders/" + fixture.id + ".frag").write_text(
            fixture.fragment_source
        )
    Path(output + "/fixtures.json").write_text(
        report_text(gl, cases, records, summary)
    )
    Path(output + "/expected_uint32.tsv").write_text(uint_tsv(cases))
    Path(output + "/expected_float32.tsv").write_text(float_tsv(cases))


# --- the command line --------------------------------------------------------


def usage_error(message: String):
    """Print a usage error as `argparse` does and exit with status 2.

    Args:
        message: The error.
    """
    print(USAGE, file=stderr)
    print("reference_glsl614.mojo: error: " + message, file=stderr)
    exit(2)


@fieldwise_init
struct Options(Copyable, Movable):
    """The parsed command line."""

    var output: String
    """The output directory of generation mode."""
    var verify: String
    """The recorded file to verify, or empty."""
    var case_id: String
    """The one case to run, or empty."""


def parse_options(arguments: List[String]) -> Options:
    """Parse the arguments after the program name.

    Args:
        arguments: The arguments.

    Returns:
        The options. A usage error exits the process.
    """
    var options = Options(dirname(source_path()) + "/fixtures", "", "")
    var i = 0
    while i < len(arguments):
        var word = arguments[i]
        if word == "-h" or word == "--help":
            print(USAGE)
            print()
            print(
                "Generate and verify independent GLES 3.0 fixtures for"
                " ThreeMojo issue 614."
            )
            exit(0)
        var name = word
        var value = String()
        var has_value = False
        var equals = word.find("=")
        if word.startswith("--") and equals > 0:
            name = String(word[byte=:equals])
            value = String(word[byte = equals + 1 :])
            has_value = True
        if name != "--output" and name != "--verify" and name != "--case":
            usage_error("unrecognized arguments: " + word)
        if not has_value:
            if i + 1 >= len(arguments):
                usage_error("argument " + name + ": expected one argument")
            i += 1
            value = arguments[i]
        if name == "--output":
            options.output = value
        elif name == "--verify":
            options.verify = value
        else:
            options.case_id = value
        i += 1
    return options^


def run(options: Options) raises -> Int:
    """Verify or generate, print the results, and return the exit status.

    Args:
        options: The parsed command line.

    Returns:
        0 when every case passes, else 1.

    Raises:
        Error: If a file cannot be read or written, or EGL or GLES fails.
    """
    if options.case_id and not options.verify:
        usage_error(
            "--case requires --verify; generation always writes the full"
            " catalog"
        )
    var start = perf_counter_ns()
    var cases: List[Case]
    if options.verify:
        cases = read_cases(Path(options.verify).read_text())
    else:
        cases = catalog()
    if options.case_id:
        var selected = List[Case]()
        for fixture in cases:
            if fixture.id == options.case_id:
                selected.append(fixture.copy())
        if not selected:
            usage_error("Unknown fixture: " + options.case_id)
        cases = selected^
    var gl = Gles()
    print(gl.provenance(), flush=True)
    var records = List[Record]()
    try:
        for fixture in cases:
            var case_start = perf_counter_ns()
            var words = gl.render(fixture)
            var outcome = compare(fixture, words)
            var line = "PASS " if outcome.passed else "FAIL "
            print(
                line
                + fixture.id
                + " "
                + observed_text(outcome, fixture.exact()),
                flush=True,
            )
            records.append(Record(words^, outcome^, seconds_since(case_start)))
    finally:
        gl.close()
    var summary = summarize(cases, records, seconds_since(start))
    if not options.verify:
        write_outputs(options.output, gl, cases, records, summary)
    print(summary.text(), flush=True)
    if summary.failed:
        print(failures_text(cases, records), file=stderr)
        return 1
    return 0


def main() raises:
    var given = argv()
    var arguments = List[String]()
    for i in range(1, len(given)):
        arguments.append(String(given[i]))
    var options = parse_options(arguments)
    var status: Int
    try:
        status = run(options)
    except error:
        print("reference_glsl614.mojo: error: " + String(error), file=stderr)
        status = 1
    exit(status)
