# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""GLSL source for a `ShaderMaterial`: a subset of GLSL ES 3.0, compiled
to the node program both rasterizers run.

three.js hands a `ShaderMaterial`'s `vertexShader` and `fragmentShader`
strings to WebGL. This port has no GPU shader compiler, so this module
lexes, parses and type checks the two strings, and builds one
`materials.nodes.NodeGraph` from them as it goes. The graph compiles to a
`NodeProgram`, which a `shader_material` names.

- `compile_shader_material` reads the strings as three.js's
  `ShaderMaterial` does: the built-in uniforms and attributes are declared
  already, and both the GLSL ES 1.0 and the 3.0 spellings work.
- `compile_raw_shader_material` reads them as `RawShaderMaterial` does:
  nothing is declared, and the version is ES 1.0 unless the first line is
  `#version 300 es`.

**The vertex shader.** The rasterizers transform each vertex on the host,
so a vertex shader cannot place a vertex anywhere it likes. It must write
`gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0)`, or the
same through `viewMatrix * modelMatrix`, once, in `main` and outside every
branch. The point `p` becomes the program's position node, an offset from
`position`. A varying the vertex shader writes becomes a `varying` node:
computed at each corner and interpolated. A corner keeps the world
position and normal, the coordinates and the color, so a varying reads
those: `(modelMatrix * vec4(position, 1.0)).xyz`, `normalMatrix * normal`,
`uv`, and not `position` itself.

**The fragment shader.** `gl_FragColor`, `pc_fragColor` or the one `out
vec4` is the color and the opacity. `gl_FragDepth` is the depth node.
`discard` throws the fragment away.

**The subset.** The types `void`, `bool`, `int`, `float`, `vec2` to
`vec4`, and `mat3`, `mat4` and `sampler2D` uniforms. Uniforms, varyings,
`const` globals, functions with `in` parameters, `if` and `else`, `for`
with a constant count, the operators but the bit ones, `?:`, swizzles,
constant indexes, constructors, object-like `#define`s, and the built-in
functions GLSL has for floats and vectors. An `int` is a whole number held
in a float. GLSL ES has no conversion between `int` and `float`, and
neither has this. Whatever is outside the subset is refused with the
shader, the line and the reason.
"""

from materials.nodes import (
    COLOR_NODE,
    DEPTH_NODE,
    MAX_LOOP_COUNT,
    NODE_FLOAT,
    OPACITY_NODE,
    POSITION_NODE,
    NodeGraph,
    NodeProgram,
    NodeRef,
    NodeVar,
    ValueType,
)
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from math.vector4 import Vector4
from render.texture_store import NO_TEXTURE

# --- word lists ---------------------------------------------------------------

# Each list is its words between spaces, with a space at each end, so a
# word is in a list when " word " is in it.
comptime _PAIRS = " ++ -- += -= *= /= %= == != <= >= && || ^^ << >> &= |= ^= "
comptime _SINGLES = "+-*/%=<>!~&|^?:;,.(){}[]"
comptime _KEYWORDS = (
    " attribute const uniform varying layout centroid flat smooth break"
    " continue do for while switch case default if else in out inout true"
    " false invariant discard return struct precision highp mediump lowp"
    " void float int bool vec2 vec3 vec4 mat3 mat4 sampler2D "
)
comptime _REFUSED_TYPES = (
    " uint ivec2 ivec3 ivec4 uvec2 uvec3 uvec4 bvec2 bvec3 bvec4 mat2 mat2x2"
    " mat2x3 mat2x4 mat3x2 mat3x3 mat3x4 mat4x2 mat4x3 mat4x4 samplerCube"
    " sampler3D sampler2DArray sampler2DShadow samplerCubeShadow isampler2D"
    " usampler2D struct "
)
comptime _BUILTINS = (
    " radians degrees sin cos tan asin acos atan pow exp log exp2 log2 sqrt"
    " inversesqrt abs sign floor ceil trunc round roundEven fract mod min max"
    " clamp mix step smoothstep length distance dot cross normalize"
    " faceforward reflect refract dFdx dFdy fwidth texture texture2D "
)
comptime _REFUSED_FUNCTIONS = (
    " sinh cosh tanh asinh acosh atanh modf isnan isinf floatBitsToInt"
    " floatBitsToUint intBitsToFloat uintBitsToFloat packSnorm2x16"
    " unpackSnorm2x16 packUnorm2x16 unpackUnorm2x16 packHalf2x16"
    " unpackHalf2x16 matrixCompMult outerProduct transpose determinant"
    " inverse lessThan lessThanEqual greaterThan greaterThanEqual equal"
    " notEqual any all not textureSize textureLod textureOffset texelFetch"
    " texelFetchOffset textureProj textureProjLod textureGrad texture2DLod"
    " texture2DProj textureCube "
)
# The qualifiers the subset refuses, and the statements.
comptime _REFUSED_QUALIFIERS = " flat centroid invariant inout buffer shared "
comptime _REFUSED_STATEMENTS = " while do switch break continue case default "
comptime _BIT_MARKS = " | & ^ << >> ~ "


def _listed(word: String, words: StringLiteral) -> Bool:
    """Return True if `word` is one of the space-separated `words`."""
    return (" " + word + " ") in String(words)


def _clipped(text: String, at: Int, end: Int) -> String:
    """Return the bytes from `at` to `end`, or to the end of the text."""
    return String(text[byte = at : min(end, text.byte_length())])


def _letter(text: String, at: Int) -> String:
    """Return the one-byte string at `at`."""
    return String(text[byte = at : at + 1])


# --- tokens -------------------------------------------------------------------


@fieldwise_init
struct _TokenKind(Equatable, ImplicitlyCopyable):
    """What a token is: a name, a whole number, a real number, a mark, or
    the end."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the five kinds."""
        return self.value >= 0 and self.value <= 4


comptime _NAME = _TokenKind(0)
comptime _INT = _TokenKind(1)
comptime _REAL = _TokenKind(2)
comptime _MARK = _TokenKind(3)
comptime _END = _TokenKind(4)


@fieldwise_init
struct _Token(Copyable, Movable):
    """One token: its kind, its text, its number and its line."""

    var kind: _TokenKind
    var text: String
    var number: Float64
    var line: Int


def _is_letter(c: UInt8) -> Bool:
    """Return True for a letter or an underscore."""
    return (
        (c >= UInt8(ord("a")) and c <= UInt8(ord("z")))
        or (c >= UInt8(ord("A")) and c <= UInt8(ord("Z")))
        or c == UInt8(ord("_"))
    )


def _is_digit(c: UInt8) -> Bool:
    """Return True for a decimal digit."""
    return c >= UInt8(ord("0")) and c <= UInt8(ord("9"))


def _is_hex(c: UInt8) -> Bool:
    """Return True for a hexadecimal digit."""
    return (
        _is_digit(c)
        or (c >= UInt8(ord("a")) and c <= UInt8(ord("f")))
        or (c >= UInt8(ord("A")) and c <= UInt8(ord("F")))
    )


def _is_word_byte(c: UInt8) -> Bool:
    """Return True for a byte a name can hold after its first."""
    return _is_letter(c) or _is_digit(c)


def _is_space(c: UInt8) -> Bool:
    """Return True for a space, a tab or a carriage return."""
    return (
        c == UInt8(ord(" ")) or c == UInt8(ord("\t")) or c == UInt8(ord("\r"))
    )


def _is_exponent(c: UInt8) -> Bool:
    """Return True for `e` or `E`."""
    return c == UInt8(ord("e")) or c == UInt8(ord("E"))


def _is_sign(c: UInt8) -> Bool:
    """Return True for `+` or `-`."""
    return c == UInt8(ord("+")) or c == UInt8(ord("-"))


def _starts_number(c: UInt8, next: UInt8) -> Bool:
    """Return True if a number begins at `c`: a digit, or a point and a
    digit."""
    return _is_digit(c) or (c == UInt8(ord(".")) and _is_digit(next))


def _is_hex_start(text: String) -> Bool:
    """Return True if a number's text begins `0x` or `0X`."""
    return text.startswith("0x") or text.startswith("0X")


struct _Lexer(Movable):
    """Turns one shader's text into tokens, running its object-like
    `#define`s and refusing every other preprocessor directive."""

    var stage: String
    var raw: Bool
    var version: Int
    var names: List[String]
    var bodies: List[List[_Token]]
    var tokens: List[_Token]

    def __init__(out self, stage: String, raw: Bool):
        """Start a lexer for one shader."""
        self.stage = stage
        self.raw = raw
        # A raw shader is GLSL ES 1.0 until it says otherwise; a three.js
        # `ShaderMaterial` takes both spellings, so it is marked zero.
        self.version = 100 if raw else 0
        self.names = List[String]()
        self.bodies = List[List[_Token]]()
        self.tokens = List[_Token]()

    def error(self, line: Int, why: String) -> Error:
        """Return the error that refuses the shader at a line: the caller
        raises it."""
        return Error(
            "GLSL " + self.stage + " shader, line " + String(line) + ": " + why
        )

    def run(mut self, text: String) raises:
        """Lex a whole shader into `tokens`, ending with an end token.

        Raises:
            Error: If a character, a number or a directive is outside the
                subset.
        """
        var line = 1
        var at = 0
        var starts_line = True
        var out = List[_Token]()
        var size = text.byte_length()
        while at < size:
            var c = text.as_bytes()[at]
            var next = text.as_bytes()[at + 1] if at + 1 < size else UInt8(0)
            if c == UInt8(ord("\n")):
                line += 1
                at += 1
                starts_line = True
            elif _is_space(c):
                at += 1
            elif c == UInt8(ord("/")) and next == UInt8(ord("/")):
                at = text.find("\n", at)
                if at < 0:
                    at = size
            elif c == UInt8(ord("/")) and next == UInt8(ord("*")):
                var close = text.find("*/", at + 2)
                if close < 0:
                    raise self.error(line, "a comment is never closed")
                line += String(text[byte=at:close]).count("\n")
                at = close + 2
            elif c == UInt8(ord("#")):
                if not starts_line:
                    raise self.error(line, "a # must begin its line")
                var end = text.find("\n", at)
                if end < 0:
                    end = size
                self.directive(
                    String(text[byte = at + 1 : end]), line, len(out)
                )
                at = end
            else:
                starts_line = False
                at = self.token(text, at, line, out)
        out.append(_Token(_END, "", 0, line))
        self.tokens = out^

    def token(
        mut self, text: String, at: Int, line: Int, mut out: List[_Token]
    ) raises -> Int:
        """Lex the token at `at` into `out`, a macro's body in place of its
        name, and return where the next begins.

        Raises:
            Error: If the character begins no token of the subset.
        """
        var bytes = text.as_bytes()
        var c = bytes[at]
        var next = bytes[at + 1] if at + 1 < len(bytes) else UInt8(0)
        if _is_letter(c):
            var end = at
            while end < len(bytes) and _is_word_byte(bytes[end]):
                end += 1
            var word = String(text[byte=at:end])
            for index in range(len(self.names)):
                if self.names[index] == word:
                    for part in range(len(self.bodies[index])):
                        var copy = self.bodies[index][part].copy()
                        copy.line = line
                        out.append(copy^)
                    return end
            out.append(_Token(_NAME, word, 0, line))
            return end
        if _starts_number(c, next):
            return self.number(text, at, line, out)
        var pair = _clipped(text, at, at + 2)
        if pair.byte_length() == 2 and _listed(pair, _PAIRS):
            out.append(_Token(_MARK, pair, 0, line))
            return at + 2
        var single = String(text[byte = at : at + 1])
        if single in String(_SINGLES):
            out.append(_Token(_MARK, single, 0, line))
            return at + 1
        raise self.error(
            line, "the character " + single + " is outside the subset"
        )

    def number(
        mut self, text: String, at: Int, line: Int, mut out: List[_Token]
    ) raises -> Int:
        """Lex a number: a decimal or hexadecimal `int`, or a `float`.

        Raises:
            Error: If it is unsigned, malformed, or a letter follows it.
        """
        var bytes = text.as_bytes()
        var end = at
        if _is_hex_start(_clipped(text, at, at + 2)):
            end = at + 2
            while end < len(bytes) and _is_hex(bytes[end]):
                end += 1
            var digits = String(text[byte = at + 2 : end])
            if digits == "":
                raise self.error(line, "a hexadecimal number needs digits")
            out.append(
                _Token(_INT, "0x" + digits, Float64(atol(digits, 16)), line)
            )
            return self.suffix(text, end, line, False)
        var real = False
        while end < len(bytes) and _is_digit(bytes[end]):
            end += 1
        if end < len(bytes) and bytes[end] == UInt8(ord(".")):
            real = True
            end += 1
            while end < len(bytes) and _is_digit(bytes[end]):
                end += 1
        if end < len(bytes) and _is_exponent(bytes[end]):
            real = True
            end += 1
            if end < len(bytes) and _is_sign(bytes[end]):
                end += 1
            var digits = end
            while end < len(bytes) and _is_digit(bytes[end]):
                end += 1
            if end == digits:
                raise self.error(line, "an exponent needs digits")
        var written = String(text[byte=at:end])
        if real:
            out.append(_Token(_REAL, written, atof(written), line))
        else:
            out.append(_Token(_INT, written, Float64(atol(written)), line))
        return self.suffix(text, end, line, real)

    def suffix(
        self, text: String, at: Int, line: Int, real: Bool
    ) raises -> Int:
        """Take a float's `f` suffix, and refuse any other letter after a
        number.

        Raises:
            Error: If a `u` or another letter follows the number.
        """
        var bytes = text.as_bytes()
        if at >= len(bytes) or not _is_word_byte(bytes[at]):
            return at
        var c = _letter(text, at)
        var alone = at + 1 >= len(bytes) or not _is_word_byte(bytes[at + 1])
        if real and (c == "f" or c == "F") and alone:
            return at + 1
        if c == "u" or c == "U":
            raise self.error(line, "unsigned integers are outside the subset")
        raise self.error(line, "a letter cannot follow a number")

    def directive(mut self, text: String, line: Int, before: Int) raises:
        """Run one preprocessor line: `#version`, an object-like `#define`,
        or a lone `#`.

        Raises:
            Error: If the directive is any other, or is misplaced.
        """
        var words = text.split()
        if len(words) == 0:
            return
        var name = String(words[0])
        if name == "version":
            var joined = String("")
            # Never empty: a directive has its name.
            for index in range(len(words)):  # pragma: no branch
                joined += (" " if index > 0 else "") + String(words[index])
            self.version_line(joined, line, before)
            return
        if name == "define":
            self.define(text, line)
            return
        if name == "include":
            raise self.error(
                line,
                (
                    "#include reads three.js's shader chunks, and this port's"
                    " materials are not made of chunks"
                ),
            )
        raise self.error(
            line, "the directive #" + name + " is outside the subset"
        )

    def version_line(mut self, version: String, line: Int, before: Int) raises:
        """Take `#version 300 es` or `#version 100` as a raw shader's first
        line.

        Raises:
            Error: If the shader is not raw, a token or another `#version`
                came first, or the version is another.
        """
        if not self.raw:
            raise self.error(
                line,
                (
                    "three.js writes a ShaderMaterial's #version itself: use a"
                    " RawShaderMaterial to write your own"
                ),
            )
        if before > 0 or self.version != 100:
            raise self.error(line, "#version must be the shader's first line")
        if version == "version 300 es":
            self.version = 300
            return
        if version == "version 100":
            self.version = 101
            return
        raise self.error(line, "the version is #version 300 es or #version 100")

    def define(mut self, text: String, line: Int) raises:
        """Take `#define NAME tokens`: from here on, `NAME` stands for its
        tokens.

        Raises:
            Error: If the macro has no name, has arguments, or is defined
                twice.
        """
        var at = text.find("define") + 6
        while at < text.byte_length() and _is_space(text.as_bytes()[at]):
            at += 1
        var end = at
        while end < text.byte_length() and _is_word_byte(text.as_bytes()[end]):
            end += 1
        var macro = String(text[byte=at:end])
        if macro == "":
            raise self.error(line, "a #define needs a name")
        if _clipped(text, end, end + 1) == "(":
            raise self.error(
                line, "a #define with arguments is outside the subset"
            )
        for index in range(len(self.names)):
            if self.names[index] == macro:
                raise self.error(
                    line, "the macro " + macro + " is defined twice"
                )
        var rest = String(text[byte=end:])
        var comment = rest.find("//")
        if comment >= 0:
            var kept = String(rest[byte=:comment])
            rest = kept
        var body = List[_Token]()
        var place = 0
        while place < rest.byte_length():
            if _is_space(rest.as_bytes()[place]):
                place += 1
                continue
            place = self.token(rest, place, line, body)
        self.names.append(macro)
        self.bodies.append(body^)


# --- types and values ---------------------------------------------------------


@fieldwise_init
struct _Type(Equatable, ImplicitlyCopyable, Writable):
    """A GLSL type of the subset: `void`, `bool`, `int`, `float`, `vec2` to
    `vec4`, `mat3`, `mat4` or `sampler2D`. A float's or a vector's value is
    its width, as `ValueType` counts it."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the ten types."""
        return (
            (self.value >= 0 and self.value <= 6)
            or self.value == 9
            or self.value == 16
            or self.value == 32
        )

    def name(self) -> String:
        """Return the type's GLSL name."""
        if self.value == 0:
            return "void"
        if self.value == 1:
            return "float"
        if self.value == 5:
            return "int"
        if self.value == 6:
            return "bool"
        if self.value == 9:
            return "mat3"
        if self.value == 16:
            return "mat4"
        if self.value == 32:
            return "sampler2D"
        return "vec" + String(self.value)

    def width(self) -> Int:
        """Return how many components a value of this type has: one for a
        `bool` or an `int`."""
        return 1 if self.is_scalar() else self.value

    def is_scalar(self) -> Bool:
        """Return True for `float`, `int` and `bool`."""
        return self.value == 1 or self.value == 5 or self.value == 6

    def is_float(self) -> Bool:
        """Return True for `float` and the vectors."""
        return self.value >= 1 and self.value <= 4

    def is_vector(self) -> Bool:
        """Return True for `vec2`, `vec3` and `vec4`."""
        return self.value >= 2 and self.value <= 4

    def is_matrix(self) -> Bool:
        """Return True for `mat3` and `mat4`."""
        return self.value == 9 or self.value == 16

    def is_number(self) -> Bool:
        """Return True for `int`, `float` and the vectors."""
        return self.is_float() or self.value == 5

    def holds(self) -> Bool:
        """Return True for what a local variable can hold: a `bool`, an
        `int`, a `float` or a vector."""
        return self.value >= 1 and self.value <= 6


comptime _VOID = _Type(0)
comptime _FLOAT = _Type(1)
comptime _VEC2 = _Type(2)
comptime _VEC3 = _Type(3)
comptime _VEC4 = _Type(4)
comptime _TINT = _Type(5)
comptime _BOOL = _Type(6)
comptime _MAT3 = _Type(9)
comptime _MAT4 = _Type(16)
comptime _SAMPLER = _Type(32)
comptime _NO_TYPE = _Type(-1)


def _type_named(name: String) -> _Type:
    """Return the type a keyword names, or `_NO_TYPE`."""
    if name == "void":
        return _VOID
    if name == "float":
        return _FLOAT
    if name == "vec2":
        return _VEC2
    if name == "vec3":
        return _VEC3
    if name == "vec4":
        return _VEC4
    if name == "int":
        return _TINT
    if name == "bool":
        return _BOOL
    if name == "mat3":
        return _MAT3
    if name == "mat4":
        return _MAT4
    if name == "sampler2D":
        return _SAMPLER
    return _NO_TYPE


# What a value stands for in a vertex shader where it is known only as a
# step toward `gl_Position`. The spaces a point moves through are the
# model's own, the world, the view and clip space. A point is tagged
# `_POINT` plus its space: `vec4(p, 1.0)` is in the model's space. A
# built-in matrix, or a product of them, is tagged `_MATRIX` plus the space
# it takes a point from, times four, plus the space it takes it to. The
# normal matrix and a direction `vec4(d, 0.0)` have tags of their own.
comptime _PLAIN = 0
comptime _NORMAL_MATRIX = 1
comptime _DIRECTION = 2
comptime _POINT = 3
comptime _MATRIX = 8
comptime _LOCAL_SPACE = 0
comptime _WORLD_SPACE = 1
comptime _VIEW_SPACE = 2
comptime _CLIP_SPACE = 3
comptime _MODEL = _MATRIX + _LOCAL_SPACE * 4 + _WORLD_SPACE
comptime _VIEW = _MATRIX + _WORLD_SPACE * 4 + _VIEW_SPACE
comptime _MODEL_VIEW = _MATRIX + _LOCAL_SPACE * 4 + _VIEW_SPACE
comptime _PROJECTION = _MATRIX + _VIEW_SPACE * 4 + _CLIP_SPACE
comptime _CLIP = _POINT + _CLIP_SPACE


def _is_matrix_tag(tag: Int) -> Bool:
    """Return True for a built-in matrix, or a product of them."""
    return tag >= _MATRIX


def _is_point_tag(tag: Int) -> Bool:
    """Return True for a point in one of the four spaces."""
    return tag >= _POINT and tag <= _CLIP


@fieldwise_init
struct _Value(Copyable, Movable):
    """What an expression computes: its type and node, what is known of it
    before it runs, its transform, and the symbol it can be assigned
    through."""

    var type: _Type
    # Its node, or -1 for a transform that is known only as a step.
    var node: Int
    # A constant expression, and a scalar whose number is known.
    var constant: Bool
    var known: Bool
    var number: Float64
    # Which transform, and the point or direction it carries.
    var tag: Int
    var point: Int
    # Whether it reads the local position or normal, which only a vertex
    # has.
    var local: Bool
    # The symbol it names and the components picked, when it can be
    # assigned to; -1 when it cannot.
    var symbol: Int
    var components: String


def _plain(type: _Type, node: Int) -> _Value:
    """Return a value that is its node and nothing more."""
    return _Value(type, node, False, False, 0, _PLAIN, -1, False, -1, "")


def _tagged(type: _Type, node: Int, tag: Int, point: Int) -> _Value:
    """Return a value that carries a transform."""
    return _Value(type, node, False, False, 0, tag, point, False, -1, "")


# What a name stands for.
comptime _LOCAL = 0
comptime _CONST = 1
comptime _UNIFORM = 2
comptime _ATTRIBUTE = 3
comptime _INPUT = 4
comptime _OUTPUT = 5
comptime _INDEX = 6
comptime _TRANSFORM = 7
comptime _POSITION = 8


@fieldwise_init
struct _Symbol(Copyable, Movable):
    """A name in scope: its kind, the value it holds, and the variable that
    holds a local's or an output's value."""

    var name: String
    var kind: Int
    var value: _Value
    var variable: Int
    var written: Bool


@fieldwise_init
struct _Function(Copyable, Movable):
    """A function of the shader: its signature and where its body is."""

    var name: String
    var result: _Type
    var types: List[_Type]
    var names: List[String]
    # The body's opening and closing braces.
    var first: Int
    var last: Int


@fieldwise_init
struct _Varying(Copyable, Movable):
    """What the vertex shader leaves the fragment shader under one name."""

    var name: String
    var type: _Type
    var node: Int


comptime _VERTEX = 0
comptime _FRAGMENT = 1


def _fold(mark: String, a: Float64, b: Float64, whole: Bool) -> Float64:
    """Return an arithmetic operator of two known numbers, as GLSL computes
    it: an `int` division drops the fraction, toward zero."""
    if mark == "+":
        return a + b
    if mark == "-":
        return a - b
    if mark == "*":
        return a * b
    if mark == "/":
        return Float64(Int(a / b)) if whole else a / b
    return a - b * Float64(Int(a / b))


def _runs(compare: String, index: Float64, bound: Float64) -> Bool:
    """Return True if a `for` loop's condition holds for its index."""
    if compare == "<":
        return index < bound
    if compare == "<=":
        return index <= bound
    if compare == ">":
        return index > bound
    if compare == ">=":
        return index >= bound
    return index != bound


def _comparison(mark: String) -> Bool:
    """Return True for a mark a `for` loop's condition can compare with."""
    return (
        mark == "<"
        or mark == "<="
        or mark == ">"
        or mark == ">="
        or mark == "!="
    )


def _assignment(mark: String) -> Bool:
    """Return True for an assignment operator of the subset."""
    return (
        mark == "="
        or mark == "+="
        or mark == "-="
        or mark == "*="
        or mark == "/="
    )


def _is_precision(word: String) -> Bool:
    """Return True for a precision qualifier or `smooth`, which change
    nothing here."""
    return (
        word == "highp"
        or word == "mediump"
        or word == "lowp"
        or word == "smooth"
    )


def _takes_ints(name: String) -> Bool:
    """Return True for a built-in GLSL gives `int` signatures too."""
    return (
        name == "abs"
        or name == "sign"
        or name == "min"
        or name == "max"
        or name == "clamp"
    )


def _shapes(name: String) -> List[String]:
    """Return a built-in's signatures: `G` a float or a vector, all the
    same, `F` a float, and `3` a `vec3`."""
    if name == "atan":
        return ["G", "GG"]
    if (
        name == "pow"
        or name == "distance"
        or name == "dot"
        or name == "reflect"
    ):
        return ["GG"]
    if name == "mod" or name == "min" or name == "max":
        return ["GG", "GF"]
    if name == "clamp":
        return ["GGG", "GFF"]
    if name == "mix":
        return ["GGG", "GGF"]
    if name == "step":
        return ["GG", "FG"]
    if name == "smoothstep":
        return ["GGG", "FFG"]
    if name == "cross":
        return ["33"]
    if name == "faceforward":
        return ["GGG"]
    if name == "refract":
        return ["GGF"]
    return ["G"]


def _derivative(name: String) -> Bool:
    """Return True for `dFdx`, `dFdy` and `fwidth`."""
    return name == "dFdx" or name == "dFdy" or name == "fwidth"


struct _Compiler(Movable):
    """Parses and type checks one shader at a time into the graph both
    shaders share.

    A parse builds nodes as it goes. A function's body is parsed at each
    call, with its parameters bound to the call's arguments, so a call is
    inlined as three.js's node builder inlines a `Fn`.
    """

    var graph: NodeGraph
    var raw: Bool
    var stage: Int
    var version: Int
    var tokens: List[_Token]
    var at: Int
    # The names in scope, and where each scope begins: the first holds the
    # built-ins and the second the shader's globals.
    var symbols: List[_Symbol]
    var scopes: List[Int]
    var functions: List[_Function]
    # The functions being inlined, innermost last, and what each returned.
    var calling: List[Int]
    var returned: List[_Value]
    # How many branches and loops the parse is inside, in this function.
    var depth: Int
    # The uniforms both shaders declare, and the varyings.
    var uniforms: List[_Symbol]
    var varyings: List[_Varying]
    # The attribute nodes, made once each, so two reads are one node.
    var position: Int
    var normal: Int
    # The point `gl_Position` draws, and each point a varying reads in the
    # world or the view, which must be the same.
    var drawn: Int
    var seen: List[Int]

    def __init__(out self, raw: Bool):
        """Start a compiler with an empty graph."""
        self.graph = NodeGraph()
        self.raw = raw
        self.stage = _VERTEX
        self.version = 0
        self.tokens = List[_Token]()
        self.at = 0
        self.symbols = List[_Symbol]()
        self.scopes = List[Int]()
        self.functions = List[_Function]()
        self.calling = List[Int]()
        self.returned = List[_Value]()
        self.depth = 0
        self.uniforms = List[_Symbol]()
        self.varyings = List[_Varying]()
        self.position = -1
        self.normal = -1
        self.drawn = -1
        self.seen = List[Int]()

    # --- tokens -------------------------------------------------------------

    def error(self, why: String) -> Error:
        """Return the error that refuses the shader at the current token's
        line: the caller raises it."""
        return Error(
            "GLSL "
            + ("vertex" if self.stage == _VERTEX else "fragment")
            + " shader, line "
            + String(self.tokens[self.at].line)
            + ": "
            + why
        )

    def peek(self, ahead: Int = 0) -> String:
        """Return the text of a token ahead, or empty past the end."""
        var index = min(self.at + ahead, len(self.tokens) - 1)
        return self.tokens[index].text

    def is_mark(self, text: String) -> Bool:
        """Return True if the current token is that mark."""
        return (
            self.tokens[self.at].kind == _MARK
            and self.tokens[self.at].text == text
        )

    def is_word(self, text: String) -> Bool:
        """Return True if the current token is that name."""
        return (
            self.tokens[self.at].kind == _NAME
            and self.tokens[self.at].text == text
        )

    def at_end(self) -> Bool:
        """Return True at the end of the shader."""
        return self.tokens[self.at].kind == _END

    def describe(self) -> String:
        """Return how an error names the current token."""
        if self.at_end():
            return "the end"
        return "'" + self.tokens[self.at].text + "'"

    def expect(mut self, text: String) raises:
        """Take a mark or a keyword, or refuse the shader.

        Raises:
            Error: If the current token is not `text`.
        """
        if self.at_end() or self.tokens[self.at].text != text:
            raise self.error("expected " + text + " before " + self.describe())
        self.at += 1

    def name(mut self) raises -> String:
        """Take a name, or refuse the shader.

        Raises:
            Error: If the current token is not a name.
        """
        if self.tokens[self.at].kind != _NAME:
            raise self.error("expected a name before " + self.describe())
        self.at += 1
        return self.tokens[self.at - 1].text

    # --- scopes -------------------------------------------------------------

    def open(mut self):
        """Open a scope."""
        self.scopes.append(len(self.symbols))

    def close(mut self):
        """Close the innermost scope and forget its names."""
        var first = self.scopes.pop()
        while len(self.symbols) > first:
            _ = self.symbols.pop()

    def find(self, name: String) -> Int:
        """Return the symbol a name means here, innermost first, or -1."""
        # Never empty: the built-in outputs are always declared.
        for index in range(len(self.symbols) - 1, -1, -1):  # pragma: no branch
            if self.symbols[index].name == name:
                return index
        return -1

    def declare(mut self, var symbol: _Symbol) raises:
        """Add a name to the innermost scope.

        Raises:
            Error: If the name is a keyword, GLSL's own, a built-in, or in
                this scope already.
        """
        if _listed(symbol.name, _KEYWORDS):
            raise self.error("the name " + symbol.name + " is a keyword")
        if symbol.name.startswith("gl_"):
            raise self.error("a name that begins gl_ is GLSL's")
        var first = self.scopes[len(self.scopes) - 1]
        var global_scope = len(self.scopes) == 2
        # Never empty: the built-in outputs are always declared.
        for index in range(len(self.symbols)):  # pragma: no branch
            var clash = index >= first or (global_scope and index < first)
            if clash and self.symbols[index].name == symbol.name:
                raise self.error(
                    "the name " + symbol.name + " is declared already"
                )
        self.symbols.append(symbol^)

    def builtin(mut self, name: String, kind: Int, var value: _Value):
        """Declare a built-in name in the first scope."""
        self.symbols.append(_Symbol(name, kind, value^, -1, False))

    # --- values -------------------------------------------------------------

    def zero(mut self, type: _Type) -> Int:
        """Return a node of zeros of a type."""
        if type == _VEC2:
            return self.graph.vec2(0, 0).value
        if type == _VEC3:
            return self.graph.vec3(0, 0, 0).value
        if type == _VEC4:
            return self.graph.vec4(0, 0, 0, 0).value
        return self.graph.float(0).value

    def literal(mut self, type: _Type, number: Float64) -> _Value:
        """Return a known scalar."""
        var node = self.graph.float(Float32(number)).value
        return _Value(type, node, True, True, number, _PLAIN, -1, False, -1, "")

    def node(self, value: _Value) raises -> NodeRef:
        """Return the node of a value, refusing a transform known only as a
        step toward `gl_Position`.

        Raises:
            Error: If the value is such a transform.
        """
        if value.node < 0:
            raise self.error(
                "this port knows modelMatrix, modelViewMatrix, normalMatrix"
                " and projectionMatrix only as the steps from position to"
                " gl_Position, the world and view position, and the normal"
            )
        return NodeRef(value.node)

    def derived(
        self, type: _Type, node: NodeRef, a: _Value, b: _Value
    ) -> _Value:
        """Return a value computed from two others: constant where both are,
        and local where either is."""
        return _Value(
            type,
            node.value,
            a.constant and b.constant,
            False,
            0,
            _PLAIN,
            -1,
            a.local or b.local,
            -1,
            "",
        )

    # --- the shader ---------------------------------------------------------

    def shader(mut self, text: String, stage: Int) raises:
        """Parse, check and build one whole shader.

        Raises:
            Error: If the shader is outside the subset or is not GLSL.
        """
        self.stage = stage
        var lexer = _Lexer(
            "vertex" if stage == _VERTEX else "fragment", self.raw
        )
        lexer.run(text)
        self.version = lexer.version
        self.tokens = lexer.tokens.copy()
        self.at = 0
        self.symbols = List[_Symbol]()
        self.scopes = List[Int]()
        self.functions = List[_Function]()
        self.open()
        self.declare_outputs()
        if not self.raw:
            self.declare_builtins()
        self.open()
        while not self.at_end():
            self.global_declaration()
        var main = -1
        for index in range(len(self.functions)):
            if self.functions[index].name == "main":
                main = index
        if main < 0:
            raise self.error("the shader has no main")
        var found = self.functions[main].copy()
        if found.result != _VOID or len(found.types) > 0:
            self.at = found.first
            raise self.error("main is void main()")
        _ = self.inline(main, List[_Value]())

    def declare_outputs(mut self) raises:
        """Declare GLSL's outputs this shader and version have: a vertex's
        `gl_Position`, and a fragment's color and depth."""
        if self.stage == _VERTEX:
            self.builtin("gl_Position", _POSITION, _plain(_VEC4, -1))
            return
        var color = self.zero(_VEC4)
        var variable = self.graph.Var(NodeRef(color)).value
        if self.version != 300:
            self.symbols.append(
                _Symbol(
                    "gl_FragColor",
                    _OUTPUT,
                    _plain(_VEC4, color),
                    variable,
                    False,
                )
            )
        if not self.raw:
            self.symbols.append(
                _Symbol(
                    "pc_fragColor",
                    _OUTPUT,
                    _plain(_VEC4, color),
                    variable,
                    False,
                )
            )
        if self.version == 100 or self.version == 101:
            return
        var depth = self.zero(_FLOAT)
        self.symbols.append(
            _Symbol(
                "gl_FragDepth",
                _OUTPUT,
                _plain(_FLOAT, depth),
                self.graph.Var(NodeRef(depth)).value,
                False,
            )
        )

    def declare_builtins(mut self) raises:
        """Declare what three.js's `ShaderMaterial` prefix declares."""
        self.builtin("viewMatrix", _TRANSFORM, self.view_matrix())
        self.builtin("cameraPosition", _UNIFORM, self.camera())
        if self.stage == _FRAGMENT:
            return
        self.builtin("modelMatrix", _TRANSFORM, _tagged(_MAT4, -1, _MODEL, -1))
        self.builtin(
            "modelViewMatrix", _TRANSFORM, _tagged(_MAT4, -1, _MODEL_VIEW, -1)
        )
        self.builtin(
            "projectionMatrix", _TRANSFORM, _tagged(_MAT4, -1, _PROJECTION, -1)
        )
        self.builtin(
            "normalMatrix", _TRANSFORM, _tagged(_MAT3, -1, _NORMAL_MATRIX, -1)
        )
        # Four names, always.
        for name in ["position", "normal", "uv", "color"]:  # pragma: no branch
            self.builtin(name, _ATTRIBUTE, self.attribute(name))

    def view_matrix(mut self) -> _Value:
        """Return `viewMatrix`: the frame's view, a real `mat4`."""
        return _tagged(_MAT4, self.graph.camera_view_matrix().value, _VIEW, -1)

    def camera(mut self) -> _Value:
        """Return `cameraPosition`, from the frame's view."""
        return _plain(_VEC3, self.graph.camera_position().value)

    def attribute(mut self, name: String) -> _Value:
        """Return a vertex attribute three.js names, its node made once."""
        if name == "position":
            self.position = self.graph.position_local().value
            var value = _plain(_VEC3, self.position)
            value.local = True
            return value^
        if name == "normal":
            self.normal = self.graph.normal_local().value
            var value = _plain(_VEC3, self.normal)
            value.local = True
            return value^
        if name == "uv":
            return _plain(_VEC2, self.graph.uv().value)
        return _plain(_VEC3, self.graph.vertex_color().value)

    def qualifiers(mut self) -> Bool:
        """Take any precision qualifiers and `const`, and return True if
        `const` was one."""
        var constant = False
        while True:
            if self.is_word("const"):
                constant = True
            elif not _is_precision(self.peek()):
                return constant
            self.at += 1

    def type(mut self) raises -> _Type:
        """Take a type name, or refuse the shader.

        Raises:
            Error: If the name is not a type of the subset.
        """
        var word = self.peek()
        var type = _type_named(word)
        if _listed(word, _REFUSED_TYPES):
            raise self.error("the type " + word + " is outside the subset")
        if not type.is_valid():
            raise self.error("expected a type before " + self.describe())
        self.at += 1
        return type

    def global_declaration(mut self) raises:
        """Parse one declaration at the top of a shader.

        Raises:
            Error: If it is outside the subset.
        """
        if self.is_mark(";"):
            self.at += 1
            return
        if self.is_word("precision"):
            self.at += 1
            if not _is_precision(self.peek()):
                raise self.error(
                    "a precision statement names highp, mediump or lowp"
                )
            self.at += 1
            _ = self.type()
            self.expect(";")
            return
        if self.is_word("layout"):
            self.at += 1
            self.expect("(")
            while not self.is_mark(")"):
                if self.at_end():
                    raise self.error("a layout is never closed")
                self.at += 1
            self.at += 1
        if _listed(self.peek(), _REFUSED_QUALIFIERS):
            raise self.error(
                "the qualifier " + self.peek() + " is outside the subset"
            )
        var storage = String("")
        if _listed(self.peek(), " uniform attribute varying in out "):
            storage = self.peek()
            self.at += 1
        var constant = self.qualifiers()
        var type = self.type()
        _ = self.qualifiers()
        var name = self.name()
        if self.is_mark("("):
            if storage != "" or constant:
                raise self.error("a function has no storage qualifier")
            self.function(type, name)
            return
        if self.is_mark("["):
            raise self.error("arrays are outside the subset")
        if storage == "uniform":
            self.uniform(type, name)
        elif storage != "":
            self.storage(storage, type, name)
        elif constant:
            self.constant(type, name)
        else:
            raise self.error(
                "a global variable is outside the subset: declare it in main,"
                " or make it const"
            )
        self.expect(";")

    def uniform(mut self, type: _Type, name: String) raises:
        """Declare a uniform: the one the other shader declared, or a new
        one, zero until the caller sets it.

        Raises:
            Error: If the type is not one a uniform takes, or the other
                shader gave the name another type.
        """
        if not type.is_float() and not type.is_matrix() and type != _SAMPLER:
            raise self.error(
                "a uniform of type " + type.name() + " is outside the subset"
            )
        if self.transform(type, name):
            return
        for index in range(len(self.uniforms)):
            if self.uniforms[index].name == name:
                if self.uniforms[index].value.type != type:
                    raise self.error(
                        "the uniform "
                        + name
                        + " is a "
                        + self.uniforms[index].value.type.name()
                        + " in the other shader"
                    )
                self.declare(self.uniforms[index].copy())
                return
        var node: NodeRef
        if type == _SAMPLER:
            node = self.graph.texture_uniform(name, NO_TEXTURE)
        elif type == _MAT3:
            var zero = Matrix3()
            zero.elements[0] = 0
            zero.elements[4] = 0
            zero.elements[8] = 0
            node = self.graph.uniform(name, zero)
        elif type == _MAT4:
            var zero = Matrix4()
            for index in range(0, 16, 5):  # pragma: no branch
                zero.elements[index] = 0
            node = self.graph.uniform(name, zero)
        elif type == _VEC2:
            node = self.graph.uniform(name, Vector2(0, 0))
        elif type == _VEC3:
            node = self.graph.uniform(name, Vector3(0, 0, 0))
        elif type == _VEC4:
            node = self.graph.uniform(name, Vector4(0, 0, 0, 0))
        else:
            node = self.graph.uniform(name, Float32(0))
        var symbol = _Symbol(
            name, _UNIFORM, _plain(type, node.value), -1, False
        )
        self.uniforms.append(symbol.copy())
        self.declare(symbol^)

    def transform(mut self, type: _Type, name: String) raises -> Bool:
        """Declare one of three.js's built-in uniforms in a raw shader and
        return True, or return False for another name.

        Raises:
            Error: If the built-in is declared with another type, or in a
                shader that does not have it.
        """
        var wanted = _MAT4
        var value = _tagged(_MAT4, -1, _MODEL, -1)
        var kind = _TRANSFORM
        if name == "viewMatrix":
            value = self.view_matrix()
        elif name == "cameraPosition":
            wanted = _VEC3
            value = self.camera()
            kind = _UNIFORM
        elif name == "modelViewMatrix":
            value.tag = _MODEL_VIEW
        elif name == "projectionMatrix":
            value.tag = _PROJECTION
        elif name == "normalMatrix":
            wanted = _MAT3
            value = _tagged(_MAT3, -1, _NORMAL_MATRIX, -1)
        elif name != "modelMatrix":
            return False
        if (
            self.stage == _FRAGMENT
            and kind == _TRANSFORM
            and name != "viewMatrix"
        ):
            raise self.error(
                "a fragment shader has no " + name + " in this port"
            )
        if type != wanted:
            raise self.error("three.js's " + name + " is a " + wanted.name())
        self.declare(_Symbol(name, kind, value^, -1, False))
        return True

    def storage(mut self, storage: String, type: _Type, name: String) raises:
        """Declare an attribute, a varying or a fragment output.

        Raises:
            Error: If the storage does not belong in this shader or this
                version, or its type is outside the subset.
        """
        var old = storage == "attribute" or storage == "varying"
        if self.version == 300 and old:
            raise self.error(
                storage + " is GLSL ES 1.0: #version 300 es writes in and out"
            )
        if self.version >= 100 and self.version <= 101 and not old:
            raise self.error(
                storage + " is GLSL ES 3.0: write #version 300 es first"
            )
        if storage == "attribute" or (
            storage == "in" and self.stage == _VERTEX
        ):
            if self.stage == _FRAGMENT:
                raise self.error("a fragment shader has no attributes")
            self.declare_attribute(type, name)
            return
        if storage == "out" and self.stage == _FRAGMENT:
            self.fragment_output(type, name)
            return
        if not type.is_float():
            raise self.error(
                "a varying of type " + type.name() + " is outside the subset"
            )
        if self.stage == _VERTEX:
            var start = self.zero(type)
            var variable = self.graph.Var(NodeRef(start)).value
            self.declare(
                _Symbol(name, _OUTPUT, _plain(type, start), variable, False)
            )
            self.varyings.append(_Varying(name, type, -1))
            return
        for index in range(len(self.varyings)):
            if self.varyings[index].name == name:
                if self.varyings[index].type != type:
                    raise self.error(
                        "the varying "
                        + name
                        + " is a "
                        + self.varyings[index].type.name()
                        + " in the vertex shader"
                    )
                var node = self.graph.varying(
                    NodeRef(self.varyings[index].node)
                )
                self.declare(
                    _Symbol(name, _INPUT, _plain(type, node.value), -1, False)
                )
                return
        raise self.error("the vertex shader declares no varying " + name)

    def fragment_output(mut self, type: _Type, name: String) raises:
        """Declare a fragment shader's `out vec4`, its color.

        Raises:
            Error: If it is not a `vec4`, or the shader has one already.
        """
        if not self.raw:
            raise self.error(
                "three.js declares a ShaderMaterial's out vec4 pc_fragColor"
                " itself: write gl_FragColor or pc_fragColor"
            )
        if type != _VEC4:
            raise self.error("a fragment output is a vec4")
        for index in range(self.scopes[1], len(self.symbols)):
            if self.symbols[index].kind == _OUTPUT:
                raise self.error(
                    "a fragment shader has one out vec4 in this port"
                )
        var start = self.zero(_VEC4)
        var variable = self.graph.Var(NodeRef(start)).value
        self.declare(
            _Symbol(name, _OUTPUT, _plain(_VEC4, start), variable, False)
        )

    def declare_attribute(mut self, type: _Type, name: String) raises:
        """Declare one of the attributes three.js gives a raw shader.

        Raises:
            Error: If the shader is not raw, the name is not one this port
                has, or the type is not its type.
        """
        if not self.raw:
            raise self.error(
                "three.js declares a ShaderMaterial's attributes itself"
            )
        if not _listed(name, " position normal uv color "):
            raise self.error(
                "the attribute "
                + name
                + " is not one this port has: position, normal, uv, color"
            )
        var wanted = _VEC2 if name == "uv" else _VEC3
        if type != wanted:
            raise self.error("the attribute " + name + " is a " + wanted.name())
        self.declare(_Symbol(name, _ATTRIBUTE, self.attribute(name), -1, False))

    def constant(mut self, type: _Type, name: String) raises:
        """Declare a `const` global from its constant value.

        Raises:
            Error: If it has no value, or the value is not constant or not of
                the type.
        """
        self.expect("=")
        var value = self.expression()
        if not value.constant:
            raise self.error("a const's value must be a constant expression")
        if value.type != type:
            raise self.error(
                "cannot give a const " + type.name() + " a " + value.type.name()
            )
        value.symbol = -1
        value.components = ""
        self.declare(_Symbol(name, _CONST, value^, -1, False))

    def function(mut self, result: _Type, name: String) raises:
        """Record a function's signature and where its body is, without
        parsing the body: each call parses it.

        Raises:
            Error: If the signature is outside the subset, or the name is
                taken.
        """
        if _listed(name, _KEYWORDS):
            raise self.error("the name " + name + " is a keyword")
        if _listed(name, _BUILTINS) or _listed(name, _REFUSED_FUNCTIONS):
            raise self.error("the function " + name + " is GLSL's own")
        for index in range(len(self.functions)):
            if self.functions[index].name == name:
                raise self.error(
                    "the function "
                    + name
                    + " is defined twice: overloads are outside the subset"
                )
        self.at += 1
        var types = List[_Type]()
        var names = List[String]()
        if self.is_word("void") and self.peek(1) == ")":
            self.at += 1
        while not self.is_mark(")"):
            if len(types) > 0:
                self.expect(",")
            _ = self.qualifiers()
            if self.is_word("out") or self.is_word("inout"):
                raise self.error(
                    "out and inout parameters are outside the subset"
                )
            if self.is_word("in"):
                self.at += 1
            _ = self.qualifiers()
            var type = self.type()
            if not type.holds():
                raise self.error(
                    "a parameter of type "
                    + type.name()
                    + " is outside the subset"
                )
            _ = self.qualifiers()
            types.append(type)
            names.append(self.name())
        self.at += 1
        if not self.is_mark("{"):
            raise self.error(
                "a function needs its body: prototypes are outside the subset"
            )
        var first = self.at
        var nesting = 0
        while True:
            if self.at_end():
                raise self.error("a function's body is never closed")
            if self.is_mark("{"):
                nesting += 1
            if self.is_mark("}"):
                nesting -= 1
                if nesting == 0:
                    break
            self.at += 1
        self.functions.append(
            _Function(name, result, types^, names^, first, self.at)
        )
        self.at += 1

    def inline(mut self, function: Int, args: List[_Value]) raises -> _Value:
        """Build a function's body into the graph for one call, its
        parameters variables that start at the arguments.

        Raises:
            Error: If the function calls itself, or its body is outside the
                subset or returns nothing.
        """
        for index in range(len(self.calling)):
            if self.calling[index] == function:
                raise self.error("a function cannot call itself")
        var back = self.at
        var depth = self.depth
        # A function sees the built-ins, the globals and its own names, not
        # its caller's.
        var globals_end = self.scopes[2] if len(self.scopes) > 2 else len(
            self.symbols
        )
        var hidden = List[_Symbol]()
        for index in range(globals_end, len(self.symbols)):
            hidden.append(self.symbols[index].copy())
        var scopes = self.scopes.copy()
        self.scopes = [scopes[0], scopes[1]]
        while len(self.symbols) > globals_end:
            _ = self.symbols.pop()
        self.open()
        self.calling.append(function)
        self.returned.append(_plain(_VOID, -1))
        var called = self.functions[function].copy()
        for index in range(len(args)):
            var variable = self.graph.Var(NodeRef(args[index].node)).value
            var value = _plain(args[index].type, args[index].node)
            value.local = args[index].local
            self.declare(
                _Symbol(called.names[index], _LOCAL, value^, variable, False)
            )
        self.at = called.first + 1
        self.depth = 0
        while self.at < called.last:
            self.statement()
        _ = self.calling.pop()
        var result = self.returned.pop()
        if called.result == _VOID:
            result = _plain(_VOID, -1)
        elif result.type == _VOID:
            raise self.error(
                "the function " + called.name + " ends with no return"
            )
        self.close()
        for index in range(len(hidden)):
            self.symbols.append(hidden[index].copy())
        self.scopes = scopes^
        self.depth = depth
        self.at = back
        return result^

    # --- statements ---------------------------------------------------------

    def statement(mut self) raises:
        """Parse and build one statement.

        Raises:
            Error: If it is outside the subset.
        """
        if self.is_mark("{"):
            self.at += 1
            self.open()
            # The braces balance: `function` counted them.
            while not self.is_mark("}"):
                self.statement()
            self.at += 1
            self.close()
        elif self.is_mark(";"):
            self.at += 1
        elif self.is_word("if"):
            self.branch()
        elif self.is_word("for"):
            self.loop()
        elif self.is_word("discard"):
            if self.stage == _VERTEX:
                raise self.error("only a fragment shader can discard")
            self.at += 1
            self.expect(";")
            self.graph.Discard()
        elif self.is_word("return"):
            self.return_statement()
        elif _listed(self.peek(), _REFUSED_STATEMENTS):
            raise self.error(self.peek() + " is outside the subset")
        elif self.starts_declaration():
            self.local_declaration()
        else:
            self.expression_statement()

    def starts_declaration(self) -> Bool:
        """Return True if the current token begins a local declaration: a
        qualifier, or a type followed by a name."""
        if self.tokens[self.at].kind != _NAME:
            return False
        var word = self.peek()
        if word == "const" or _is_precision(word):
            return True
        var typed = _type_named(word).is_valid() or _listed(
            word, _REFUSED_TYPES
        )
        return typed and self.peek(1) != "("

    def local_declaration(mut self) raises:
        """Parse `T a = e, b;`, each name a variable.

        Raises:
            Error: If the type or a value is outside the subset.
        """
        var constant = self.qualifiers()
        var type = self.type()
        if not type.holds():
            raise self.error(
                "a local variable of type "
                + type.name()
                + " is outside the subset"
            )
        while True:
            var name = self.name()
            if self.is_mark("["):
                raise self.error("arrays are outside the subset")
            var value = _plain(type, -1)
            if self.is_mark("="):
                self.at += 1
                value = self.expression()
                if value.type != type:
                    raise self.error(
                        "cannot give a "
                        + type.name()
                        + " a "
                        + value.type.name()
                    )
                if constant and not value.constant:
                    raise self.error(
                        "a const's value must be a constant expression"
                    )
            elif constant:
                raise self.error("a const needs a value")
            else:
                value.node = self.zero(type)
            # A point in clip space has no node yet; it holds zeros until
            # `gl_Position` takes it.
            var start = value.node if value.node >= 0 else self.zero(type)
            var variable = self.graph.Var(NodeRef(start)).value
            value.symbol = -1
            value.components = ""
            if not constant:
                value.known = False
                value.constant = False
            self.declare(
                _Symbol(
                    name,
                    _CONST if constant else _LOCAL,
                    value^,
                    variable,
                    False,
                )
            )
            if not self.is_mark(","):
                break
            self.at += 1
        self.expect(";")

    def condition(mut self, what: String) raises -> NodeRef:
        """Parse a `bool` expression.

        Raises:
            Error: If it is not a `bool`.
        """
        var value = self.expression()
        if value.type != _BOOL:
            raise self.error(what + " needs a bool, not a " + value.type.name())
        return NodeRef(value.node)

    def branch(mut self) raises:
        """Parse `if (c) s else s` as an `If` of the graph.

        Raises:
            Error: If the condition is not a `bool`, or a branch is outside
                the subset.
        """
        self.at += 1
        self.expect("(")
        var condition = self.condition("an if")
        self.expect(")")
        self.graph.If(condition)
        self.depth += 1
        self.statement()
        if self.is_word("else"):
            self.at += 1
            self.graph.Else()
            self.statement()
        self.depth -= 1
        self.graph.End()

    def known(mut self, type: _Type, what: String) raises -> Float64:
        """Parse a constant number of a type, for a `for` loop.

        Raises:
            Error: If it is not of the type, or not known before it runs.
        """
        var value = self.additive()
        if value.type != type or not value.known:
            raise self.error(
                "a for loop's " + what + " is a constant " + type.name()
            )
        return value.number

    def loop(mut self) raises:
        """Parse `for (int i = a; i < b; i++) s` with a constant count, as a
        `Loop` of the graph that unrolls it.

        Raises:
            Error: If the loop's form or count is outside the subset.
        """
        self.at += 1
        self.expect("(")
        _ = self.qualifiers()
        if not self.is_word("int") and not self.is_word("float"):
            raise self.error(
                "a for loop begins by declaring its int or float index"
            )
        var type = self.type()
        var name = self.name()
        self.expect("=")
        var first = self.known(type, "start")
        self.expect(";")
        if self.peek() != name:
            raise self.error("a for loop's condition compares its index")
        self.at += 1
        var compare = self.peek()
        if not _comparison(compare):
            raise self.error("a for loop's condition is <, <=, >, >= or !=")
        self.at += 1
        var bound = self.known(type, "bound")
        self.expect(";")
        var step = self.loop_step(name, type)
        self.expect(")")
        # The count, by running the index as GLSL would.
        var count = 0
        var index = first
        while _runs(compare, index, bound):
            count += 1
            if count > MAX_LOOP_COUNT:
                raise self.error(
                    "a for loop runs at most "
                    + String(MAX_LOOP_COUNT)
                    + " times"
                )
            index = Float64(Float32(index + step))
        var node = self.graph.Loop(count, Float32(first), Float32(step))
        self.open()
        self.declare(_Symbol(name, _INDEX, _plain(type, node.value), -1, False))
        self.depth += 1
        self.statement()
        self.depth -= 1
        self.close()
        self.graph.End()

    def loop_step(mut self, name: String, type: _Type) raises -> Float64:
        """Parse a `for` loop's step: `i++`, `++i`, `i--`, `--i`, `i += c`
        or `i -= c`, and return how much it adds.

        Raises:
            Error: If the step is another, or changes another variable.
        """
        var before = self.peek()
        if before == "++" or before == "--":
            self.at += 1
            if self.peek() != name:
                raise self.error("a for loop steps its own index")
            self.at += 1
            return 1 if before == "++" else -1
        if self.peek() != name:
            raise self.error("a for loop steps its own index")
        self.at += 1
        var mark = self.peek()
        self.at += 1
        if mark == "++" or mark == "--":
            return 1 if mark == "++" else -1
        if mark != "+=" and mark != "-=":
            self.at -= 1
            raise self.error("a for loop steps its index by ++, --, += or -=")
        var by = self.known(type, "step")
        if by == 0:
            raise self.error("a for loop's step cannot be zero")
        return by if mark == "+=" else -by

    def return_statement(mut self) raises:
        """Parse `return e;` as the last statement of a function.

        Raises:
            Error: If it is not the last, or its type is not the
                function's.
        """
        self.at += 1
        var function = self.calling[len(self.calling) - 1]
        var called = self.functions[function].copy()
        var value = _plain(_VOID, -1)
        if not self.is_mark(";"):
            value = self.expression()
        if value.type != called.result:
            raise self.error(
                "the function "
                + called.name
                + " returns a "
                + called.result.name()
                + ", not a "
                + value.type.name()
            )
        self.expect(";")
        if self.at != called.last or self.depth != 0:
            self.at -= 1
            raise self.error(
                "a return must be the last statement of its function"
            )
        value.symbol = -1
        value.components = ""
        if called.result == _VOID:
            value.type = _FLOAT
        self.returned[len(self.returned) - 1] = value^

    def expression_statement(mut self) raises:
        """Parse an assignment, an increment, or a call.

        Raises:
            Error: If the target cannot be assigned, or the types differ.
        """
        if self.is_mark("++") or self.is_mark("--"):
            var sign = Float64(1) if self.is_mark("++") else Float64(-1)
            self.at += 1
            var target = self.postfix()
            self.step(target, sign)
        else:
            var target = self.expression()
            var mark = self.peek()
            if mark == "++" or mark == "--":
                self.at += 1
                self.step(target, Float64(1) if mark == "++" else Float64(-1))
            elif _assignment(mark):
                self.at += 1
                var value = self.expression()
                if mark != "=":
                    value = self.arithmetic(_letter(mark, 0), target, value)
                self.assign(target, value)
            elif _listed(mark, " %= &= |= ^= <<= >>= "):
                raise self.error(
                    "the operator " + mark + " is outside the subset"
                )
        if self.is_mark("=") or self.is_mark("++") or self.is_mark("--"):
            raise self.error(
                "an assignment or ++ is a whole statement in this subset"
            )
        self.expect(";")

    def step(mut self, target: _Value, sign: Float64) raises:
        """Add one to an `int` or `float` variable, or take one away.

        Raises:
            Error: If the target cannot be assigned or is not a number.
        """
        if target.type != _TINT and target.type != _FLOAT:
            raise self.error("++ and -- change an int or a float")
        var one = self.literal(target.type, sign)
        self.assign(target, self.arithmetic("+", target, one))

    def assign(mut self, target: _Value, value: _Value) raises:
        """Make a variable, or some of its components, hold a value.

        Raises:
            Error: If the target cannot be assigned, or the types differ.
        """
        if target.symbol < 0:
            raise self.error("that cannot be assigned")
        var kind = self.symbols[target.symbol].kind
        if kind == _POSITION:
            self.draw(target, value)
            return
        if kind != _LOCAL and kind != _OUTPUT:
            raise self.error(
                "cannot assign "
                + self.symbols[target.symbol].name
                + ": it is "
                + _kind_name(kind)
            )
        if value.type != target.type:
            raise self.error(
                "cannot assign a "
                + value.type.name()
                + " to a "
                + target.type.name()
            )
        # A point in clip space has no node: a whole assignment outside
        # every branch keeps it for `gl_Position`, and nothing else can.
        var whole = target.components == "" and self.depth == 0
        if value.tag == _CLIP and whole:
            ref kept = self.symbols[target.symbol]
            kept.value.tag = _CLIP
            kept.value.point = value.point
            kept.value.node = -1
            return
        var node = self.node(value)
        var variable = NodeVar(self.symbols[target.symbol].variable)
        if target.components != "":
            # The components not written keep what the variable held.
            var held = self.graph.get(variable)
            var parts = List[NodeRef]()
            for lane in range(
                self.symbols[target.symbol].value.type.width()
            ):  # pragma: no branch
                var letter = _letter("xyzw", lane)
                var found = target.components.find(letter)
                if found < 0:
                    parts.append(self.graph.swizzle(held, letter))
                elif value.type.is_scalar():
                    parts.append(node)
                else:
                    parts.append(
                        self.graph.swizzle(node, _letter("xyzw", found))
                    )
            node = self.graph.join(parts)
        self.graph.assign(variable, node)
        ref changed = self.symbols[target.symbol]
        changed.written = True
        changed.value.local = changed.value.local or value.local
        # A transform is kept only by a whole assignment outside every
        # branch, where it cannot be one of two values.
        changed.value.tag = value.tag if whole else _PLAIN
        changed.value.point = value.point

    def draw(mut self, target: _Value, value: _Value) raises:
        """Take `gl_Position`: `projectionMatrix * modelViewMatrix * vec4(p,
        1.0)`, written once in `main` outside every branch.

        Raises:
            Error: If the value is not that, or it is written twice or in a
                branch or a function.
        """
        if len(self.calling) > 1 or self.depth != 0:
            raise self.error(
                "gl_Position is written in main, outside every branch and loop"
            )
        if self.drawn >= 0:
            raise self.error("gl_Position is written once")
        if value.tag != _CLIP:
            raise self.error(
                "this port draws gl_Position = projectionMatrix *"
                " modelViewMatrix * vec4(p, 1.0): the host places each vertex"
            )
        self.drawn = value.point

    # --- expressions --------------------------------------------------------

    def expression(mut self) raises -> _Value:
        """Parse an expression without assignment: `?:` and everything that
        binds tighter.

        Raises:
            Error: If the expression is outside the subset or mistyped.
        """
        var condition = self.logical_or()
        if not self.is_mark("?"):
            return condition^
        if condition.type != _BOOL:
            raise self.error(
                "a ?: needs a bool, not a " + condition.type.name()
            )
        self.at += 1
        var yes = self.expression()
        self.expect(":")
        var no = self.expression()
        if yes.type != no.type:
            raise self.error(
                "a ?: chooses between one type, not a "
                + yes.type.name()
                + " and a "
                + no.type.name()
            )
        var node = self.graph.select(
            NodeRef(condition.node), self.node(yes), self.node(no)
        )
        var value = self.derived(yes.type, node, yes, no)
        value.constant = value.constant and condition.constant
        value.local = value.local or condition.local
        return value^

    def logical(
        mut self, mark: String, left: _Value, right: _Value
    ) raises -> _Value:
        """Return `&&`, `||` or `^^` of two `bool`s. Both sides are
        computed: an expression here has no side effects to skip.

        Raises:
            Error: If either is not a `bool`.
        """
        if left.type != _BOOL or right.type != _BOOL:
            raise self.error(mark + " joins two bools")
        var a = NodeRef(left.node)
        var b = NodeRef(right.node)
        var node: NodeRef
        if mark == "&&":
            node = self.graph.logical_and(a, b)
        elif mark == "||":
            node = self.graph.logical_or(a, b)
        else:
            node = self.graph.logical_xor(a, b)
        return self.derived(_BOOL, node, left, right)

    def logical_or(mut self) raises -> _Value:
        """Parse `a || b`."""
        var left = self.logical_xor()
        while self.is_mark("||"):
            self.at += 1
            var right = self.logical_xor()
            left = self.logical("||", left, right)
        return left^

    def logical_xor(mut self) raises -> _Value:
        """Parse `a ^^ b`."""
        var left = self.logical_and()
        while self.is_mark("^^"):
            self.at += 1
            var right = self.logical_and()
            left = self.logical("^^", left, right)
        return left^

    def logical_and(mut self) raises -> _Value:
        """Parse `a && b`."""
        var left = self.equality()
        while self.is_mark("&&"):
            self.at += 1
            var right = self.equality()
            left = self.logical("&&", left, right)
        return left^

    def refuse_bits(self) raises:
        """Refuse a bit operator where one could follow a value.

        Raises:
            Error: If the current token is one.
        """
        if self.tokens[self.at].kind == _MARK and _listed(
            self.peek(), _BIT_MARKS
        ):
            raise self.error(
                "the bit operator " + self.peek() + " is outside the subset"
            )

    def equality(mut self) raises -> _Value:
        """Parse `a == b` and `a != b`: true only where every component
        agrees, as GLSL's `==` of two vectors is."""
        var left = self.relational()
        while self.is_mark("==") or self.is_mark("!="):
            var mark = self.peek()
            self.at += 1
            var right = self.relational()
            if left.type != right.type or not left.type.holds():
                raise self.error(
                    "cannot compare a "
                    + left.type.name()
                    + " and a "
                    + right.type.name()
                )
            var same = self.graph.equal(self.node(left), self.node(right))
            var every = self.graph.swizzle(same, "x")
            for lane in range(1, left.type.width()):
                every = self.graph.logical_and(
                    every, self.graph.swizzle(same, _letter("xyzw", lane))
                )
            if mark == "!=":
                every = self.graph.logical_not(every)
            left = self.derived(_BOOL, every, left, right)
        return left^

    def relational(mut self) raises -> _Value:
        """Parse `<`, `<=`, `>` and `>=` of two `int`s or two `float`s."""
        var left = self.additive()
        while (
            _listed(self.peek(), " < <= > >= ")
            and self.tokens[self.at].kind == _MARK
        ):
            var mark = self.peek()
            self.at += 1
            var right = self.additive()
            var scalar = left.type == _FLOAT or left.type == _TINT
            if left.type != right.type or not scalar:
                raise self.error(
                    "cannot compare a "
                    + left.type.name()
                    + " and a "
                    + right.type.name()
                )
            var a = NodeRef(left.node)
            var b = NodeRef(right.node)
            var node: NodeRef
            if mark == "<":
                node = self.graph.less_than(a, b)
            elif mark == "<=":
                node = self.graph.less_than_equal(a, b)
            elif mark == ">":
                node = self.graph.greater_than(a, b)
            else:
                node = self.graph.greater_than_equal(a, b)
            left = self.derived(_BOOL, node, left, right)
        self.refuse_bits()
        return left^

    def additive(mut self) raises -> _Value:
        """Parse `a + b` and `a - b`."""
        var left = self.multiplicative()
        while self.is_mark("+") or self.is_mark("-"):
            var mark = self.peek()
            self.at += 1
            var right = self.multiplicative()
            left = self.arithmetic(mark, left, right)
        self.refuse_bits()
        return left^

    def multiplicative(mut self) raises -> _Value:
        """Parse `a * b`, `a / b` and `a % b`."""
        var left = self.unary()
        while self.is_mark("*") or self.is_mark("/") or self.is_mark("%"):
            var mark = self.peek()
            self.at += 1
            var right = self.unary()
            left = self.arithmetic(mark, left, right)
        return left^

    def arithmetic(
        mut self, mark: String, left: _Value, right: _Value
    ) raises -> _Value:
        """Return `+`, `-`, `*`, `/` or `%` of two values by GLSL ES's rules:
        no conversion between `int` and `float`, a scalar beside a vector
        repeated, and a matrix times a vector.

        Raises:
            Error: If the operands' types do not meet.
        """
        var transforms = _is_matrix_tag(left.tag) or left.tag == _NORMAL_MATRIX
        if mark == "*" and (transforms or right.tag == _VIEW):
            return self.transformed(left, right)
        var a = left.type
        var b = right.type
        if mark == "%" and (a != _TINT or b != _TINT):
            raise self.error("% takes two ints: write mod() for floats")
        if a.is_matrix() or b.is_matrix():
            return self.matrix_product(mark, left, right)
        var numeric = (a.is_float() and b.is_float()) or (
            a == _TINT and b == _TINT
        )
        var sizes = a == b or a == _FLOAT or b == _FLOAT
        if not numeric or not sizes:
            raise self.error(
                "cannot use "
                + mark
                + " on a "
                + a.name()
                + " and a "
                + b.name()
            )
        var type = a if a.width() >= b.width() else b
        var x = self.node(left)
        var y = self.node(right)
        var node: NodeRef
        if mark == "+":
            node = self.graph.add(x, y)
        elif mark == "-":
            node = self.graph.sub(x, y)
        elif mark == "*":
            node = self.graph.mul(x, y)
        elif mark == "/":
            node = self.graph.div(x, y)
            if type == _TINT:
                node = self.graph.trunc(node)
        else:
            var quotient = self.graph.trunc(self.graph.div(x, y))
            node = self.graph.sub(x, self.graph.mul(y, quotient))
        var value = self.derived(type, node, left, right)
        if left.known and right.known:
            value.known = True
            value.number = _fold(mark, left.number, right.number, type == _TINT)
        return value^

    def matrix_product(
        mut self, mark: String, left: _Value, right: _Value
    ) raises -> _Value:
        """Return a matrix uniform times a vector, or a vector times it.

        Raises:
            Error: If the operator is not `*`, both are matrices, or the
                vector is not as wide as the matrix.
        """
        var a = left.type
        var b = right.type
        if mark != "*" or (a.is_matrix() and b.is_matrix()):
            raise self.error(
                "cannot use "
                + mark
                + " on a "
                + a.name()
                + " and a "
                + b.name()
            )
        var matrix = a if a.is_matrix() else b
        var vector = b if a.is_matrix() else a
        var wanted = _VEC3 if matrix == _MAT3 else _VEC4
        if vector != wanted:
            raise self.error(
                "cannot multiply a " + a.name() + " and a " + b.name()
            )
        var node = self.graph.mul(self.node(left), self.node(right))
        return self.derived(vector, node, left, right)

    def transformed(mut self, left: _Value, right: _Value) raises -> _Value:
        """Return a product with one of three.js's transforms: a step from
        `position` toward `gl_Position`, the normal, or the real view
        matrix.

        Raises:
            Error: If the product is not one this port knows.
        """
        var matrix = left.tag
        var carried = right.tag
        if _is_matrix_tag(matrix) and _is_matrix_tag(carried):
            # Two maps between spaces make one, if the second's starts where
            # the first's ends: `(right * point)` goes first.
            var into = (matrix - _MATRIX) // 4
            if into != (carried - _MATRIX) % 4:
                raise self.error(
                    "those two transforms do not follow one another"
                )
            var joined = (
                _MATRIX
                + ((carried - _MATRIX) // 4) * 4
                + (matrix - _MATRIX) % 4
            )
            return _tagged(_MAT4, -1, joined, -1)
        var matches = _is_point_tag(carried) and _is_matrix_tag(matrix)
        if matches and carried - _POINT == (matrix - _MATRIX) // 4:
            return self.moved((matrix - _MATRIX) % 4, right.point)
        if matrix == _VIEW or carried == _VIEW:
            return self.matrix_product("*", left, right)
        var of_normal = self.normal >= 0 and right.node == self.normal
        if matrix == _NORMAL_MATRIX and of_normal:
            return _plain(_VEC3, self.graph.normal_view().value)
        var of_direction = self.normal >= 0 and right.point == self.normal
        if matrix == _MODEL and carried == _DIRECTION and of_direction:
            var world = self.graph.normal_world()
            var zero = self.graph.float(0)
            return _plain(_VEC4, self.graph.join([world, zero]).value)
        raise self.error(
            "this port knows the transforms only as projectionMatrix *"
            " modelViewMatrix * vec4(p, 1.0) and the same through"
            " viewMatrix * modelMatrix, modelMatrix * vec4(position, 1.0),"
            " normalMatrix * normal and modelMatrix * vec4(normal, 0.0)"
        )

    def moved(mut self, space: Int, point: Int) raises -> _Value:
        """Return a point carried into the world, the view or clip space. In
        the world or the view, its node is the surface's own position there
        with a `w` of one, and the point is kept, to check against the one
        `gl_Position` draws. In clip space it has no node."""
        if space == _CLIP_SPACE:
            return _tagged(_VEC4, -1, _CLIP, point)
        var at = (
            self.graph.position_world() if space
            == _WORLD_SPACE else self.graph.position_view()
        )
        var node = self.graph.join([at, self.graph.float(1)])
        self.seen.append(point)
        return _tagged(_VEC4, node.value, _POINT + space, point)

    def unary(mut self) raises -> _Value:
        """Parse `-a`, `+a` and `!a`.

        Raises:
            Error: If the operand's type does not take the operator.
        """
        var mark = self.peek()
        if self.tokens[self.at].kind != _MARK or not _listed(
            mark, " - + ! ~ ++ -- "
        ):
            return self.postfix()
        self.at += 1
        if mark == "~":
            raise self.error("the bit operator ~ is outside the subset")
        if mark == "++" or mark == "--":
            raise self.error(
                "an assignment or ++ is a whole statement in this subset"
            )
        var value = self.unary()
        if mark == "!":
            if value.type != _BOOL:
                raise self.error("! takes a bool, not a " + value.type.name())
            return self.derived(
                _BOOL, self.graph.logical_not(NodeRef(value.node)), value, value
            )
        if not value.type.is_number():
            raise self.error(
                "cannot use " + mark + " on a " + value.type.name()
            )
        if mark == "+":
            value.symbol = -1
            return value^
        var result = self.derived(
            value.type, self.graph.negate(self.node(value)), value, value
        )
        result.known = value.known
        result.number = -value.number
        return result^

    def postfix(mut self) raises -> _Value:
        """Parse a primary value and the swizzles and constant indexes after
        it.

        Raises:
            Error: If a swizzle or an index is outside the value.
        """
        var value = self.primary()
        while True:
            if self.is_mark("."):
                self.at += 1
                value = self.swizzle(value, self.name())
            elif self.is_mark("["):
                self.at += 1
                var index = self.expression()
                self.expect("]")
                if not value.type.is_vector():
                    raise self.error(
                        "only a vector can be indexed in this subset"
                    )
                if index.type != _TINT or not index.known:
                    raise self.error("a vector is indexed by a constant int")
                if index.number < 0 or index.number >= Float64(
                    value.type.width()
                ):
                    raise self.error(
                        "the index is outside the " + value.type.name()
                    )
                value = self.swizzle(value, _letter("xyzw", Int(index.number)))
            else:
                return value^

    def swizzle(mut self, value: _Value, letters: String) raises -> _Value:
        """Return a vector's components picked by letters of one of the sets
        `xyzw`, `rgba` and `stpq`.

        Raises:
            Error: If the value is not a vector, a letter names no component
                of it, or the sets are mixed.
        """
        if value.symbol >= 0 and self.symbols[value.symbol].kind == _POSITION:
            raise self.error("gl_Position is written whole")
        if not value.type.is_vector():
            raise self.error("only a vector has components to pick")
        if letters.byte_length() > 4:
            raise self.error("a swizzle picks one to four components")
        var picked = String("")
        var set = -1
        for index in range(letters.byte_length()):  # pragma: no branch
            var letter = _letter(letters, index)
            var place = String("xyzwrgbastpq").find(letter)
            if place < 0 or place % 4 >= value.type.width():
                raise self.error(
                    "a " + value.type.name() + " has no component " + letter
                )
            if set >= 0 and place // 4 != set:
                raise self.error("a swizzle cannot mix xyzw, rgba and stpq")
            set = place // 4
            picked += _letter("xyzw", place % 4)
        var node = self.graph.swizzle(self.node(value), picked)
        var result = self.derived(
            _Type(picked.byte_length()), node, value, value
        )
        if value.symbol < 0:
            return result^
        # A swizzle of a variable can be assigned, each component once.
        var through = String("")
        for index in range(picked.byte_length()):  # pragma: no branch
            var letter = _letter(picked, index)
            if value.components != "":
                letter = _letter(value.components, String("xyzw").find(letter))
            if letter in through:
                return result^
            through += letter
        result.symbol = value.symbol
        result.components = through
        return result^

    def primary(mut self) raises -> _Value:
        """Parse a number, `true` or `false`, a name, a call, a constructor
        or a parenthesis.

        Raises:
            Error: If the token begins no value of the subset.
        """
        var token = self.tokens[self.at].copy()
        if token.kind == _INT:
            self.at += 1
            return self.literal(_TINT, token.number)
        if token.kind == _REAL:
            self.at += 1
            return self.literal(_FLOAT, Float64(Float32(token.number)))
        if self.is_mark("("):
            self.at += 1
            var value = self.expression()
            self.expect(")")
            value.symbol = -1
            value.components = ""
            return value^
        if token.kind != _NAME:
            raise self.error("expected a value before " + self.describe())
        self.at += 1
        if token.text == "true" or token.text == "false":
            return self.literal(
                _BOOL, Float64(1) if token.text == "true" else Float64(0)
            )
        if self.is_mark("("):
            return self.call(token.text)
        return self.read(token.text)

    def read(mut self, name: String) raises -> _Value:
        """Return the value a name holds here.

        Raises:
            Error: If the name means nothing here, or is GLSL's but outside
                the subset.
        """
        var index = self.find(name)
        if index < 0:
            if name.startswith("gl_"):
                raise self.error("GLSL's " + name + " is outside the subset")
            raise self.error("the name " + name + " is not declared")
        ref symbol = self.symbols[index]
        var value = symbol.value.copy()
        var held = symbol.kind == _LOCAL or symbol.kind == _OUTPUT
        if held and value.tag != _CLIP:
            value.node = self.graph.get(NodeVar(symbol.variable)).value
        value.symbol = index
        value.components = ""
        return value^

    # --- calls --------------------------------------------------------------

    def arguments(mut self) raises -> List[_Value]:
        """Parse a call's arguments through its `)`.

        Raises:
            Error: If an argument is outside the subset.
        """
        self.expect("(")
        var args = List[_Value]()
        while not self.is_mark(")"):
            if len(args) > 0:
                self.expect(",")
            args.append(self.expression())
        self.at += 1
        return args^

    def call(mut self, name: String) raises -> _Value:
        """Parse a call: a constructor, the shader's own function, or a
        built-in.

        Raises:
            Error: If the call is outside the subset or mistyped.
        """
        if _listed(name, _REFUSED_TYPES):
            raise self.error("the type " + name + " is outside the subset")
        if _listed(name, _REFUSED_FUNCTIONS):
            raise self.error("GLSL's " + name + "() is outside the subset")
        var type = _type_named(name)
        if type.is_valid():
            return self.construct(type, self.arguments())
        if _listed(name, _BUILTINS):
            return self.builtin_call(name, self.arguments())
        for index in range(len(self.functions)):
            if self.functions[index].name == name:
                return self.call_function(index, self.arguments())
        raise self.error("the function " + name + " is not declared")

    def call_function(
        mut self, index: Int, args: List[_Value]
    ) raises -> _Value:
        """Return the shader's own function called with arguments of its
        parameters' types.

        Raises:
            Error: If the arguments do not fit, or the body is refused.
        """
        var called = self.functions[index].copy()
        if len(args) != len(called.types):
            raise self.error(
                "the function "
                + called.name
                + " takes "
                + String(len(called.types))
                + " arguments"
            )
        for arg in range(len(args)):
            if args[arg].type != called.types[arg]:
                raise self.error(
                    "the function "
                    + called.name
                    + " takes a "
                    + called.types[arg].name()
                    + " as argument "
                    + String(arg + 1)
                )
            _ = self.node(args[arg])
        var result = self.inline(index, args)
        for arg in range(len(args)):
            result.local = result.local or args[arg].local
        return result^

    def construct(mut self, type: _Type, args: List[_Value]) raises -> _Value:
        """Return a constructor's value: one scalar converted, a vector of
        one scalar, or components laid end to end.

        Raises:
            Error: If the type cannot be constructed, or the arguments are
                too few or too many.
        """
        if not type.holds():
            raise self.error(
                "a " + type.name() + " constructor is outside the subset"
            )
        if len(args) == 0:
            raise self.error(
                "a " + type.name() + " constructor needs arguments"
            )
        var value = _plain(type, -1)
        value.constant = True
        # Never empty: a constructor of no arguments is refused above.
        for index in range(len(args)):  # pragma: no branch
            if not args[index].type.holds():
                raise self.error(
                    "cannot make a "
                    + type.name()
                    + " of a "
                    + args[index].type.name()
                )
            _ = self.node(args[index])
            value.constant = value.constant and args[index].constant
            value.local = value.local or args[index].local
        if type.is_scalar():
            return self.convert(type, args, value^)
        var width = type.width()
        var parts = List[NodeRef]()
        var filled = 0
        # Never empty: a constructor of no arguments is refused above.
        for index in range(len(args)):  # pragma: no branch
            if filled >= width:
                raise self.error(
                    "a " + type.name() + " constructor has too many arguments"
                )
            var part = NodeRef(args[index].node)
            var size = args[index].type.width()
            if filled + size > width:
                size = width - filled
                part = self.graph.swizzle(part, String("xyzw"[byte=0:size]))
            parts.append(part)
            filled += size
        if len(args) == 1 and filled == 1:
            # One scalar fills every component.
            for _ in range(1, width):  # pragma: no branch
                parts.append(parts[0])
            filled = width
        if filled < width:
            raise self.error(
                "a "
                + type.name()
                + " constructor needs "
                + String(width)
                + " components"
            )
        value.node = self.graph.join(parts).value
        # vec4(p, 1.0) and vec4(d, 0.0) are a point and a direction, which
        # the transforms toward gl_Position carry.
        var homogeneous = (
            type == _VEC4 and len(args) == 2 and args[0].type == _VEC3
        )
        if homogeneous and args[1].known and args[1].number == 1:
            value.tag = _POINT + _LOCAL_SPACE
            value.point = args[0].node
        if homogeneous and args[1].known and args[1].number == 0:
            value.tag = _DIRECTION
            value.point = args[0].node
        return value^

    def convert(
        mut self, type: _Type, args: List[_Value], var value: _Value
    ) raises -> _Value:
        """Return `float(x)`, `int(x)` or `bool(x)` of one scalar or of a
        vector's first component.

        Raises:
            Error: If there is more than one argument.
        """
        if len(args) > 1:
            raise self.error(
                "a " + type.name() + " constructor takes one argument"
            )
        var from_type = args[0].type
        var node = NodeRef(args[0].node)
        if from_type.width() > 1:
            node = self.graph.swizzle(node, "x")
        var number = args[0].number
        if type == _TINT and from_type != _TINT and from_type != _BOOL:
            node = self.graph.trunc(node)
            number = Float64(Int(number))
        if type == _BOOL and from_type != _BOOL:
            node = self.graph.not_equal(node, self.graph.float(0))
            number = 1 if number != 0 else 0
        value.node = node.value
        value.known = args[0].known
        value.number = number
        return value^

    def builtin_call(
        mut self, name: String, args: List[_Value]
    ) raises -> _Value:
        """Return a built-in function's value, by GLSL's signatures.

        Raises:
            Error: If the arguments fit no signature, or the function does
                not belong in this shader or version.
        """
        var nodes = List[NodeRef]()
        var value = _plain(_VOID, -1)
        value.constant = not _derivative(name)
        for index in range(len(args)):
            nodes.append(self.node(args[index]))
            value.constant = value.constant and args[index].constant
            value.local = value.local or args[index].local
        if name == "texture" or name == "texture2D":
            return self.texture(name, args, nodes, value^)
        if _derivative(name) and self.stage == _VERTEX:
            raise self.error(name + "() is a fragment shader's")
        var type = self.signature(name, args)
        value.type = _FLOAT if _listed(name, " length distance dot ") else type
        value.node = self.apply(name, nodes).value
        return value^

    def texture(
        mut self,
        name: String,
        args: List[_Value],
        nodes: List[NodeRef],
        var value: _Value,
    ) raises -> _Value:
        """Return `texture(s, uv)` or `texture2D(s, uv)`.

        Raises:
            Error: If the spelling is not the shader's version's, the shader
                is a vertex shader, or the arguments are others.
        """
        var modern = name == "texture"
        if self.raw and modern != (self.version == 300):
            raise self.error(name + "() is not in this shader's GLSL version")
        if self.stage == _VERTEX:
            raise self.error("a vertex shader reads no texture in this port")
        if len(args) != 2 or args[0].type != _SAMPLER or args[1].type != _VEC2:
            raise self.error(name + "() takes a sampler2D and a vec2")
        value.type = _VEC4
        value.constant = False
        value.node = self.graph.texture(nodes[0], nodes[1]).value
        return value^

    def apply(mut self, name: String, nodes: List[NodeRef]) raises -> NodeRef:
        """Return the node a built-in of a checked signature computes."""
        var x = nodes[0]
        if name == "radians":
            return self.graph.radians(x)
        if name == "degrees":
            return self.graph.degrees(x)
        if name == "sin":
            return self.graph.sin(x)
        if name == "cos":
            return self.graph.cos(x)
        if name == "tan":
            return self.graph.tan(x)
        if name == "asin":
            return self.graph.asin(x)
        if name == "acos":
            return self.graph.acos(x)
        if name == "atan":
            return self.graph.atan(x) if len(nodes) == 1 else self.graph.atan2(
                x, nodes[1]
            )
        if name == "exp":
            return self.graph.exp(x)
        if name == "log":
            return self.graph.log(x)
        if name == "exp2":
            return self.graph.exp2(x)
        if name == "log2":
            return self.graph.log2(x)
        if name == "sqrt":
            return self.graph.sqrt(x)
        if name == "inversesqrt":
            return self.graph.inverse_sqrt(x)
        if name == "abs":
            return self.graph.abs(x)
        if name == "sign":
            return self.graph.sign(x)
        if name == "floor":
            return self.graph.floor(x)
        if name == "ceil":
            return self.graph.ceil(x)
        if name == "trunc":
            return self.graph.trunc(x)
        if name == "round" or name == "roundEven":
            return self.graph.round(x)
        if name == "fract":
            return self.graph.fract(x)
        if name == "length":
            return self.graph.length(x)
        if name == "normalize":
            return self.graph.normalize(x)
        if name == "dFdx":
            return self.graph.dfdx(x)
        if name == "dFdy":
            return self.graph.dfdy(x)
        if name == "fwidth":
            return self.graph.fwidth(x)
        var y = nodes[1]
        if name == "pow":
            return self.graph.pow(x, y)
        if name == "mod":
            return self.graph.mod(x, y)
        if name == "min":
            return self.graph.min(x, y)
        if name == "max":
            return self.graph.max(x, y)
        if name == "step":
            return self.graph.step(x, y)
        if name == "distance":
            return self.graph.distance(x, y)
        if name == "dot":
            return self.graph.dot(x, y)
        if name == "cross":
            return self.graph.cross(x, y)
        if name == "reflect":
            return self.graph.reflect(x, y)
        var z = nodes[2]
        if name == "clamp":
            return self.graph.clamp(x, y, z)
        if name == "mix":
            return self.graph.mix(x, y, z)
        if name == "smoothstep":
            return self.graph.smoothstep(x, y, z)
        if name == "faceforward":
            return self.graph.faceforward(x, y, z)
        # `refract`, the one left: `_BUILTINS` names no other.
        return self.graph.refract(x, y, z)

    def signature(mut self, name: String, args: List[_Value]) raises -> _Type:
        """Return the type `genType` stands for in the signature a
        built-in's arguments fit, by GLSL ES 3.0's table.

        Raises:
            Error: If the arguments fit none of the function's signatures.
        """
        var shapes = _shapes(name)
        var ints = _takes_ints(name)
        # Never empty: every built-in has a signature.
        for shape in range(len(shapes)):  # pragma: no branch
            var letters = shapes[shape]
            if letters.byte_length() != len(args):
                continue
            var generic = _NO_TYPE
            var fits = True
            # Never empty: a shape of no letters is no built-in's.
            for index in range(len(args)):  # pragma: no branch
                var letter = _letter(letters, index)
                var type = args[index].type
                var number = type.is_float() or (ints and type == _TINT)
                if letter == "3":
                    generic = _VEC3
                    fits = fits and type == _VEC3
                elif letter == "F":
                    # The scalar of the generic type: an int beside ints.
                    var scalar = _TINT if generic == _TINT else _FLOAT
                    fits = fits and type == scalar
                else:
                    fits = (
                        fits
                        and number
                        and (generic == _NO_TYPE or type == generic)
                    )
                    generic = type
            if fits:
                return generic
        var got = String("")
        for index in range(len(args)):
            got += (", " if index > 0 else "") + args[index].type.name()
        raise self.error("no signature of " + name + "() takes (" + got + ")")


def _kind_name(kind: Int) -> String:
    """Return how an error names a kind of symbol that cannot be assigned."""
    if kind == _CONST:
        return "a const"
    if kind == _UNIFORM:
        return "a uniform"
    if kind == _ATTRIBUTE:
        return "an attribute"
    if kind == _INPUT:
        return "a varying the vertex shader wrote"
    if kind == _INDEX:
        return "a for loop's index"
    return "a built-in transform"


def _compile(
    vertex_shader: String, fragment_shader: String, raw: Bool
) raises -> NodeGraph:
    """Return the graph two shaders build.

    Raises:
        Error: If either shader is outside the subset.
    """
    var compiler = _Compiler(raw)
    compiler.shader(vertex_shader, _VERTEX)
    if compiler.drawn < 0:
        raise Error("GLSL vertex shader: main never writes gl_Position")
    for index in range(len(compiler.seen)):
        if compiler.seen[index] != compiler.drawn:
            raise Error(
                "GLSL vertex shader: this port knows the world and view"
                " position only of the point gl_Position draws"
            )
    # What each varying holds where the vertex shader ends.
    for index in range(len(compiler.varyings)):
        ref varying = compiler.varyings[index]
        var symbol = compiler.find(varying.name)
        ref held = compiler.symbols[symbol]
        varying.node = compiler.graph.get(NodeVar(held.variable)).value
        if held.value.local:
            raise Error(
                "GLSL vertex shader: the varying "
                + varying.name
                + " reads position or normal, which a triangle's corners do"
                " not keep: write (modelMatrix * vec4(position, 1.0)).xyz or"
                " normalMatrix * normal"
            )
    if compiler.drawn != compiler.position:
        var local = compiler.graph.position_local()
        var offset = compiler.graph.sub(NodeRef(compiler.drawn), local)
        compiler.graph.set_output(POSITION_NODE, offset)
    compiler.shader(fragment_shader, _FRAGMENT)
    var color = -1
    var depth = -1
    # Never empty: the built-in outputs are always declared.
    for index in range(len(compiler.symbols)):  # pragma: no branch
        ref symbol = compiler.symbols[index]
        if symbol.kind != _OUTPUT or not symbol.written:
            continue
        var node = compiler.graph.get(NodeVar(symbol.variable)).value
        if symbol.value.type == _FLOAT:
            depth = node
        else:
            color = node
    if color < 0:
        raise Error("GLSL fragment shader: main never writes its color")
    var rgb = compiler.graph.swizzle(NodeRef(color), "xyz")
    compiler.graph.set_output(COLOR_NODE, rgb)
    var alpha = compiler.graph.swizzle(NodeRef(color), "w")
    compiler.graph.set_output(OPACITY_NODE, alpha)
    if depth >= 0:
        compiler.graph.set_output(DEPTH_NODE, NodeRef(depth))
    return compiler.graph.copy()


def shader_graph(
    vertex_shader: String, fragment_shader: String
) raises -> NodeGraph:
    """Return the node graph a `ShaderMaterial`'s two shaders build, before
    it is compiled, to add to it or look into it.

    Args:
        vertex_shader: The vertex shader's GLSL.
        fragment_shader: The fragment shader's GLSL.

    Returns:
        The graph, with its color, opacity, position and depth outputs set.

    Raises:
        Error: If either shader is outside the subset, naming the shader,
            the line and the reason.
    """
    return _compile(vertex_shader, fragment_shader, False)


def compile_shader_material(
    vertex_shader: String, fragment_shader: String
) raises -> NodeProgram:
    """Return the node program three.js's `ShaderMaterial` draws with two
    GLSL shaders. Give its id to `shader_material`.

    three.js's built-ins are declared already: `modelMatrix`,
    `modelViewMatrix`, `projectionMatrix`, `viewMatrix`, `normalMatrix`,
    `cameraPosition`, and the attributes `position`, `normal`, `uv` and
    `color`. GLSL ES 1.0's `attribute`, `varying`, `texture2D` and
    `gl_FragColor`, and 3.0's `in`, `out`, `texture` and `pc_fragColor`,
    all work, as three.js's prefix makes them work.

    Args:
        vertex_shader: The vertex shader's GLSL.
        fragment_shader: The fragment shader's GLSL.

    Returns:
        The program. Its uniforms are the shaders' uniforms, zero until the
        caller sets them with `set_uniform` and `set_texture`.

    Raises:
        Error: If either shader is outside the subset, naming the shader,
            the line and the reason, or the graph does not compile.
    """
    return _compile(vertex_shader, fragment_shader, False).compile()


def compile_raw_shader_material(
    vertex_shader: String, fragment_shader: String
) raises -> NodeProgram:
    """Return the node program three.js's `RawShaderMaterial` draws with two
    GLSL shaders: nothing is declared for them.

    Each shader declares the built-ins it reads, with three.js's names and
    types. A shader is GLSL ES 1.0 unless its first line is
    `#version 300 es`.

    Args:
        vertex_shader: The vertex shader's GLSL.
        fragment_shader: The fragment shader's GLSL.

    Returns:
        The program.

    Raises:
        Error: If either shader is outside the subset, naming the shader,
            the line and the reason, or the graph does not compile.
    """
    return _compile(vertex_shader, fragment_shader, True).compile()
