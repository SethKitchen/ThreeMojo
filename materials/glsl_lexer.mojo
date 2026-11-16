# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""GLSL subset preprocessor, lexer, type system and constant folding.

`materials.glsl` parses these tokens and symbol records into a `NodeGraph`.
"""

from core.ordinal import ordinal_valid
from core.search import first_match
from loaders.bytes import (
    ascii_digit,
    is_exponent_mark,
    is_hex_digit,
    is_sign_mark,
    letter_or_underscore,
    space_tab_return,
)
from loaders.js_text import is_js_word
from materials.node_program import ValueType
from std.memory import bitcast

# --- word lists ---------------------------------------------------------------

# Each list is its words between spaces, with a space at each end, so a
# word is in a list when " word " is in it.
comptime _PAIRS = " ++ -- += -= *= /= %= == != <= >= && || ^^ << >> &= |= ^= "
comptime _SINGLES = "+-*/%=<>!~&|^?:;,.(){}[]"
comptime _KEYWORDS = (
    " attribute const uniform varying layout centroid flat smooth break"
    " continue do for while switch case default if else in out inout true false"
    " invariant discard return struct precision highp mediump lowp void float"
    " int uint uvec2 uvec3 uvec4 bool vec2 vec3 vec4 mat2 mat3 mat4 sampler2D"
    " ivec2 ivec3 ivec4 bvec2 bvec3 bvec4 samplerCube sampler3D sampler2DArray "
)
# The most elements an array holds: each is a variable, and an index picked
# where the shader runs reads every one.
comptime MAX_ARRAY_SIZE = 256
comptime _REFUSED_TYPES = (
    " mat2x2"
    " mat2x3 mat2x4 mat3x2 mat3x3 mat3x4 mat4x2 mat4x3 mat4x4"
    " sampler2DShadow samplerCubeShadow isampler2D"
    " usampler2D "
)
comptime _BUILTINS = (
    " radians degrees sin cos tan asin acos atan pow exp log exp2 log2 sqrt"
    " inversesqrt abs sign floor ceil trunc round roundEven fract mod min max"
    " clamp mix step smoothstep length distance dot cross normalize faceforward"
    " reflect refract dFdx dFdy fwidth texture texture2D transpose determinant"
    " inverse textureLod textureGrad lessThan lessThanEqual greaterThan"
    " greaterThanEqual equal notEqual any all not texelFetch textureSize"
    " textureProj texture2DProj textureCube "
)
comptime _REFUSED_FUNCTIONS = (
    " sinh cosh tanh asinh acosh atanh modf isnan isinf floatBitsToInt"
    " floatBitsToUint intBitsToFloat uintBitsToFloat packSnorm2x16"
    " unpackSnorm2x16 packUnorm2x16 unpackUnorm2x16 packHalf2x16"
    " unpackHalf2x16 matrixCompMult outerProduct"
    " textureOffset"
    " texelFetchOffset textureProjLod texture2DLod "
)
# The qualifiers the subset refuses, and the statements.
comptime _REFUSED_QUALIFIERS = " flat centroid invariant inout buffer shared "
# The most body executions of a `while` or a `do` loop. One additional
# condition-only iteration proves it has stopped. The compiler refuses a
# shader when it cannot prove that no loop reaches that extra body.
comptime MAX_WHILE_COUNT = 256
# The built-ins that compare two vectors one component at a time.
comptime _COMPARISONS = (
    " lessThan lessThanEqual greaterThan greaterThanEqual equal notEqual "
)
# What a `break` leaves when it is a loop's; see `_Compiler.breakables`.
comptime _A_LOOP = -2


def _listed(word: String, words: StringLiteral) -> Bool:
    """Return True if `word` is one of the space-separated `words`."""
    return (" " + word + " ") in String(words)


def _clipped(text: String, at: Int, end: Int) -> String:
    """Return the bytes from `at` to `end`, or to the end of the text.

    An end inside a character of more than one byte moves back to the start
    of that character. `at` must start a character.
    """
    var bytes = text.as_bytes()
    var stop = min(end, len(bytes))
    while stop > at and stop < len(bytes) and (bytes[stop] & 0xC0) == 0x80:
        stop -= 1
    return String(text[byte=at:stop])


def _character(text: String, at: Int) -> String:
    """Return the whole character that starts at `at`, all its bytes."""
    var bytes = text.as_bytes()
    var end = at + 1
    while end < len(bytes) and (bytes[end] & 0xC0) == 0x80:
        end += 1
    return String(text[byte=at:end])


def _letter(text: String, at: Int) -> String:
    """Return the one-byte string at `at`."""
    return String(text[byte = at : at + 1])


# --- tokens -------------------------------------------------------------------


@fieldwise_init
struct _TokenKind(Equatable, ImplicitlyCopyable):
    """A name, signed or unsigned whole number, real number, mark, or end."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the six token kinds."""
        return ordinal_valid(self.value, 5)


comptime _NAME = _TokenKind(0)
comptime _INT = _TokenKind(1)
comptime _REAL = _TokenKind(2)
comptime _MARK = _TokenKind(3)
comptime _END = _TokenKind(4)
comptime _UINT_TOKEN = _TokenKind(5)


@fieldwise_init
struct _Token(Copyable, Movable):
    """One token: its kind, its text, its number and its line."""

    var kind: _TokenKind
    var text: String
    var number: Float64
    var line: Int


def _starts_number(c: UInt8, next: UInt8) -> Bool:
    """Return True if a number begins at `c`: a digit, or a point and a
    digit."""
    return ascii_digit(c) or (c == UInt8(ord(".")) and ascii_digit(next))


def _is_hex_start(text: String) -> Bool:
    """Return True if a number's text begins `0x` or `0X`."""
    return text.startswith("0x") or text.startswith("0X")


# What an open `#if` is doing: taking its lines, waiting for a branch
# that holds, or done, having taken one or being inside a branch not taken.
comptime _TAKING = 0
comptime _WAITING = 1
comptime _DONE = 2


struct _Lexer(Movable):
    """Turns one shader's text into tokens, running its object-like
    `#define`s, its `#undef`s and its `#if`s, and refusing every other
    preprocessor directive."""

    var stage: String
    var raw: Bool
    var version: Int
    var names: List[String]
    var bodies: List[List[_Token]]
    var tokens: List[_Token]
    # Each open `#if`, innermost last: `_TAKING`, `_WAITING` or `_DONE`,
    # and whether its `#else` has come.
    var conditions: List[Int]
    var elsed: List[Bool]

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
        self.conditions = List[Int]()
        self.elsed = List[Bool]()

    def active(self) -> Bool:
        """Return True if every open `#if` is taking its lines."""
        for index in range(len(self.conditions)):
            if self.conditions[index] != _TAKING:
                return False
        return True

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
            elif space_tab_return(c):
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
            elif c == UInt8(ord("#")) and (starts_line or self.active()):
                if not starts_line:
                    raise self.error(line, "a # must begin its line")
                var end = text.find("\n", at)
                if end < 0:
                    end = size
                self.directive(
                    String(text[byte = at + 1 : end]), line, len(out)
                )
                at = end
            elif self.active():
                starts_line = False
                at = self.token(text, at, line, out)
            else:
                # A line an `#if` does not take is skipped, counted.
                starts_line = False
                at += 1
        if len(self.conditions) > 0:
            raise self.error(line, "an #if is never closed with #endif")
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
        if letter_or_underscore(c):
            var end = at
            while end < len(bytes) and is_js_word(bytes[end]):
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
        var triple = _clipped(text, at, at + 3)
        if triple == "<<=" or triple == ">>=":
            out.append(_Token(_MARK, triple, 0, line))
            return at + 3
        var pair = _clipped(text, at, at + 2)
        if pair.byte_length() == 2 and _listed(pair, _PAIRS):
            out.append(_Token(_MARK, pair, 0, line))
            return at + 2
        var single = _character(text, at)
        if single in String(_SINGLES):
            out.append(_Token(_MARK, single, 0, line))
            return at + 1
        raise self.error(
            line, "the character " + single + " is outside the subset"
        )

    def number(
        mut self, text: String, at: Int, line: Int, mut out: List[_Token]
    ) raises -> Int:
        """Lex decimal, octal or hexadecimal integers and real numbers.

        Raises:
            Error: If the spelling or the 32-bit integer range is invalid.
        """
        var bytes = text.as_bytes()
        var end = at
        var base = 10
        var digits_at = at
        if _is_hex_start(_clipped(text, at, at + 2)):
            base = 16
            digits_at += 2
            end = digits_at
            while end < len(bytes) and is_hex_digit(Int(bytes[end])):
                end += 1
            if end == digits_at:
                raise self.error(line, "a hexadecimal number needs digits")
        else:
            while end < len(bytes) and ascii_digit(bytes[end]):
                end += 1
        var real = False
        if base == 10 and end < len(bytes) and bytes[end] == UInt8(ord(".")):
            real = True
            end += 1
            while end < len(bytes) and ascii_digit(bytes[end]):
                end += 1
        if base == 10 and end < len(bytes) and is_exponent_mark(bytes[end]):
            real = True
            end += 1
            if end < len(bytes) and is_sign_mark(bytes[end]):
                end += 1
            var first = end
            while end < len(bytes) and ascii_digit(bytes[end]):
                end += 1
            if end == first:
                raise self.error(line, "an exponent needs digits")
        var written = String(text[byte=at:end])
        var kind = _REAL if real else _INT
        var number = Float64(0)
        if real:
            number = atof(written)
        else:
            if base == 10 and end - at > 1 and bytes[at] == UInt8(ord("0")):
                base = 8
            for digit_at in range(digits_at, end):
                var byte = Int(bytes[digit_at])
                var digit = byte - ord("0")
                if byte >= ord("a"):
                    digit = byte - ord("a") + 10
                elif byte >= ord("A"):
                    digit = byte - ord("A") + 10
                if digit >= base:
                    raise self.error(
                        line, "an octal integer uses digits 0 to 7"
                    )
                number = number * Float64(base) + Float64(digit)
                if number > 4294967295.0:
                    raise self.error(line, "an integer literal exceeds 32 bits")
        var suffix_end = end
        if end < len(bytes) and is_js_word(bytes[end]):
            var c = _letter(text, end)
            var alone = end + 1 >= len(bytes) or not is_js_word(bytes[end + 1])
            if not real and alone and (c == "u" or c == "U"):
                kind = _UINT_TOKEN
                suffix_end += 1
            elif real and alone and (c == "f" or c == "F"):
                suffix_end += 1
            else:
                raise self.error(line, "a letter cannot follow a number")
        if kind == _INT and number > 2147483647.0:
            raise self.error(
                line, "an int literal exceeds 2147483647; use a u suffix"
            )
        if written == "":
            raise self.error(line, "a number needs digits")
        out.append(_Token(kind, written, number, line))
        return suffix_end

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
        if _listed(name, " if ifdef ifndef elif else endif "):
            self.conditional(name, text, line)
            return
        if not self.active():
            return
        if name == "undef":
            if len(words) != 2:
                raise self.error(line, "an #undef names one macro")
            var gone = String(words[1])
            for index in range(len(self.names)):
                if self.names[index] == gone:
                    _ = self.names.pop(index)
                    _ = self.bodies.pop(index)
                    return
            return
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

    def conditional(mut self, name: String, text: String, line: Int) raises:
        """Run `#if`, `#ifdef`, `#ifndef`, `#elif`, `#else` or `#endif`.

        Raises:
            Error: If an `#elif`, an `#else` or an `#endif` has no `#if`, an
                `#elif` or an `#else` follows an `#else`, a name is missing,
                or a condition is outside the subset.
        """
        var rest = String(text[byte = text.find(name) + name.byte_length() :])
        if name == "if" or name == "ifdef" or name == "ifndef":
            if not self.active():
                self.conditions.append(_DONE)
                self.elsed.append(False)
                return
            var holds: Bool
            if name == "if":
                holds = self.condition(rest, line)
            else:
                var words = rest.split()
                if len(words) != 1:
                    raise self.error(line, "an #" + name + " names one macro")
                holds = self.defined(String(words[0])) == (name == "ifdef")
            self.conditions.append(_TAKING if holds else _WAITING)
            self.elsed.append(False)
            return
        if len(self.conditions) == 0:
            raise self.error(line, "an #" + name + " has no #if")
        var top = len(self.conditions) - 1
        if name == "endif":
            _ = self.conditions.pop()
            _ = self.elsed.pop()
            return
        if self.elsed[top]:
            raise self.error(line, "an #" + name + " follows the #else")
        var state = self.conditions[top]
        if name == "else":
            self.elsed[top] = True
            self.conditions[top] = _TAKING if state == _WAITING else _DONE
            return
        # `#elif`: taken where no branch before it was and it holds.
        if state == _WAITING and self.condition(rest, line):
            self.conditions[top] = _TAKING
        elif state == _TAKING:
            self.conditions[top] = _DONE

    def defined(self, name: String) -> Bool:
        """Return True if a macro is defined."""
        return first_match(self.names, name) >= 0

    def condition(self, text: String, line: Int) raises -> Bool:
        """Return whether an `#if`'s condition holds: whole numbers, macros
        that are one whole number, `defined`, `!`, `&&`, `||`, the six
        comparisons and parentheses. A name that is not a macro is zero, as
        the C preprocessor has it.

        Raises:
            Error: If the condition is empty, is outside the subset, or
                reads a macro that is not one whole number.
        """
        var parts = self.pieces(text, line)
        if len(parts) == 0:
            raise self.error(line, "an #if needs a condition")
        var at = 0
        var value = self.either(parts, at, line)
        if at != len(parts):
            raise self.error(
                line, "the #if condition goes on past " + parts[at - 1]
            )
        return value != 0

    def pieces(self, text: String, line: Int) raises -> List[String]:
        """Split an `#if` condition into names, numbers and marks.

        Raises:
            Error: If a character is outside a condition.
        """
        var parts = List[String]()
        var bytes = text.as_bytes()
        var at = 0
        while at < len(bytes):
            var c = bytes[at]
            if space_tab_return(c):
                at += 1
                continue
            if c == UInt8(ord("/")) and _clipped(text, at, at + 2) == "//":
                break
            var end = at + 1
            if is_js_word(c):
                while end < len(bytes) and is_js_word(bytes[end]):
                    end += 1
            elif _listed(_clipped(text, at, at + 2), " && || == != <= >= "):
                end = at + 2
            elif not (_character(text, at) in String("()!<>")):
                raise self.error(
                    line,
                    "the character "
                    + _character(text, at)
                    + " is outside an #if condition",
                )
            parts.append(String(text[byte=at:end]))
            at = end
        return parts^

    def either(self, parts: List[String], mut at: Int, line: Int) raises -> Int:
        """Evaluate `a || b` and what binds tighter."""
        var value = self.both(parts, at, line)
        while at < len(parts) and parts[at] == "||":
            at += 1
            var right = self.both(parts, at, line)
            value = 1 if value != 0 or right != 0 else 0
        return value

    def both(self, parts: List[String], mut at: Int, line: Int) raises -> Int:
        """Evaluate `a && b` and what binds tighter."""
        var value = self.compared(parts, at, line)
        while at < len(parts) and parts[at] == "&&":
            at += 1
            var right = self.compared(parts, at, line)
            value = 1 if value != 0 and right != 0 else 0
        return value

    def compared(
        self, parts: List[String], mut at: Int, line: Int
    ) raises -> Int:
        """Evaluate one comparison of two terms, or a term."""
        var value = self.term(parts, at, line)
        if at >= len(parts) or not _listed(parts[at], " == != < > <= >= "):
            return value
        var mark = parts[at]
        at += 1
        var right = self.term(parts, at, line)
        var holds: Bool
        if mark == "==":
            holds = value == right
        elif mark == "!=":
            holds = value != right
        elif mark == "<":
            holds = value < right
        elif mark == ">":
            holds = value > right
        elif mark == "<=":
            holds = value <= right
        else:
            holds = value >= right
        return 1 if holds else 0

    def term(self, parts: List[String], mut at: Int, line: Int) raises -> Int:
        """Evaluate `!a`, `(a)`, `defined(NAME)`, a whole number or a
        name."""
        if at >= len(parts):
            raise self.error(line, "an #if condition ends too soon")
        var part = parts[at]
        at += 1
        if part == "!":
            return 1 if self.term(parts, at, line) == 0 else 0
        if part == "(":
            var inner = self.either(parts, at, line)
            if at >= len(parts) or parts[at] != ")":
                raise self.error(line, "an #if condition leaves a ( open")
            at += 1
            return inner
        if part == "defined":
            var wrapped = at < len(parts) and parts[at] == "("
            if wrapped:
                at += 1
            if at >= len(parts) or not letter_or_underscore(
                parts[at].as_bytes()[0]
            ):
                raise self.error(line, "defined names a macro")
            var holds = self.defined(parts[at])
            at += 1
            if wrapped:
                if at >= len(parts) or parts[at] != ")":
                    raise self.error(line, "an #if condition leaves a ( open")
                at += 1
            return 1 if holds else 0
        if ascii_digit(part.as_bytes()[0]):
            # A part has at least one byte.
            for index in range(part.byte_length()):  # pragma: no branch
                if not ascii_digit(part.as_bytes()[index]):
                    raise self.error(
                        line, "an #if condition counts in whole numbers"
                    )
            return atol(part)
        if not letter_or_underscore(part.as_bytes()[0]):
            raise self.error(line, "an #if condition cannot hold " + part)
        for index in range(len(self.names)):
            if self.names[index] == part:
                ref body = self.bodies[index]
                if len(body) != 1 or body[0].kind != _INT:
                    raise self.error(
                        line,
                        "the macro "
                        + part
                        + " is not one whole number, as an #if reads it",
                    )
                return Int(body[0].number)
        # A name that is not a macro is zero.
        return 0

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
        while at < text.byte_length() and space_tab_return(text.as_bytes()[at]):
            at += 1
        var end = at
        while end < text.byte_length() and is_js_word(text.as_bytes()[end]):
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
            if space_tab_return(rest.as_bytes()[place]):
                place += 1
                continue
            place = self.token(rest, place, line, body)
        self.names.append(macro)
        self.bodies.append(body^)


# --- types and values ---------------------------------------------------------


@fieldwise_init
struct _Type(Equatable, ImplicitlyCopyable, Writable):
    """A GLSL type of the subset: `void`, `bool`, `int`, `float`, `vec2` to
    `vec4`, `ivec2` to `ivec4`, `bvec2` to `bvec4`, `mat2`, `mat3`, `mat4`
    or `sampler2D`. A float's or a vector's value is its width, as
    `ValueType` counts it; an `ivec`'s is 16 more, and a `bvec`'s 20 more.
    A `mat2` is held as a `vec4` of its two columns, so it is four wide."""

    var value: Int

    def is_struct(self) -> Bool:
        """Return True for a struct the shader declares."""
        return self.value >= _STRUCT_BASE

    def is_valid(self) -> Bool:
        """Return True if this is a supported built-in type."""
        return (
            (self.value >= 0 and self.value <= 6)
            or (self.value >= 18 and self.value <= 20)
            or (self.value >= 22 and self.value <= 24)
            or self.value == 8
            or self.value == 9
            or self.value == 16
            or (self.value >= 32 and self.value <= 35)
            or self.is_uint()
        )

    def name(self) -> String:
        """Return the type's GLSL name."""
        if self.is_uint():
            return "uint" if self.value == 41 else "uvec" + String(
                self.value - 40
            )
        if self.value == 0:
            return "void"
        if self.value == 1:
            return "float"
        if self.value == 5:
            return "int"
        if self.value == 6:
            return "bool"
        if self.value == 8:
            return "mat2"
        if self.value >= 18 and self.value <= 20:
            return "ivec" + String(self.value - 16)
        if self.value >= 22 and self.value <= 24:
            return "bvec" + String(self.value - 20)
        if self.value == 9:
            return "mat3"
        if self.value == 16:
            return "mat4"
        if self.value == 32:
            return "sampler2D"
        if self.value == 33:
            return "samplerCube"
        if self.value == 34:
            return "sampler3D"
        if self.value == 35:
            return "sampler2DArray"
        if self.value >= _STRUCT_BASE:
            return "struct"
        return "vec" + String(self.value)

    def width(self) -> Int:
        """Return how many components a value of this type has: one for a
        `bool` or an `int`, and four for a `mat2`."""
        if self.is_uint():
            return self.value - 40
        if self.value == 8:
            return 4
        if self.value >= 18 and self.value <= 20:
            return self.value - 16
        # `bvec2` to `bvec4`, as one unsigned comparison.
        if UInt(self.value - 22) < 3:
            return self.value - 20
        return 1 if self.is_scalar() else self.value

    def is_int(self) -> Bool:
        """Return True for `int` and `ivec2` to `ivec4`."""
        return self.value == 5 or (self.value >= 18 and self.value <= 20)

    def is_uint(self) -> Bool:
        """Return True for uint and its vectors."""
        return self.value >= 41 and self.value <= 44

    def graph_type(self) -> ValueType:
        """Return the register type, retaining exact unsigned payloads."""
        if self.is_uint():
            return ValueType(self.value)
        if self.is_int():
            return ValueType(44 + self.width())
        return ValueType(self.width())

    def is_bool(self) -> Bool:
        """Return True for `bool` and `bvec2` to `bvec4`."""
        return self.value == 6 or (self.value >= 22 and self.value <= 24)

    def is_any_vector(self) -> Bool:
        """Return True for a vector of floats, ints or bools."""
        return self.is_vector() or (
            (self.is_int() or self.is_bool() or self.is_uint())
            and not self.is_scalar()
        )

    def resized(self, width: Int) -> _Type:
        """Return the type of this one's kind of component, `width` wide: a
        scalar for one."""
        if self.is_uint():
            return _Type(40 + width)
        if self.is_int():
            return _TINT if width == 1 else _Type(16 + width)
        if self.is_bool():
            return _BOOL if width == 1 else _Type(20 + width)
        return _Type(width)

    def is_scalar(self) -> Bool:
        """Return True for `float`, `int` and `bool`."""
        return (
            self.value == 1
            or self.value == 5
            or self.value == 6
            or self.value == 41
        )

    def is_float(self) -> Bool:
        """Return True for `float` and the vectors."""
        return self.value >= 1 and self.value <= 4

    def is_vector(self) -> Bool:
        """Return True for `vec2`, `vec3` and `vec4`."""
        return self.value >= 2 and self.value <= 4

    def is_matrix(self) -> Bool:
        """Return True for `mat3` and `mat4`."""
        return self.value == 9 or self.value == 16

    def is_sampler(self) -> Bool:
        """Return True for `sampler2D`, `samplerCube`, `sampler3D` and
        `sampler2DArray`."""
        return self.value >= 32 and self.value <= 35

    def is_number(self) -> Bool:
        """Return True for `int`, `float` and their vectors."""
        return self.is_float() or self.is_int() or self.is_uint()

    def holds(self) -> Bool:
        """Return True for what a local variable can hold: a `bool`, an
        `int`, a `float`, a vector of them or a `mat2`."""
        return (
            (self.value >= 1 and self.value <= 6)
            or self.value == 8
            or self.is_any_vector()
            or self.is_uint()
        )


comptime _VOID = _Type(0)
comptime _FLOAT = _Type(1)
comptime _VEC2 = _Type(2)
comptime _VEC3 = _Type(3)
comptime _VEC4 = _Type(4)
comptime _TINT = _Type(5)
comptime _TUINT = _Type(41)
comptime _UVEC2 = _Type(42)
comptime _UVEC3 = _Type(43)
comptime _UVEC4 = _Type(44)
comptime _BOOL = _Type(6)
comptime _MAT2 = _Type(8)
comptime _IVEC2 = _Type(18)
comptime _IVEC3 = _Type(19)
comptime _IVEC4 = _Type(20)
comptime _BVEC2 = _Type(22)
comptime _BVEC3 = _Type(23)
comptime _BVEC4 = _Type(24)
comptime _MAT3 = _Type(9)
comptime _MAT4 = _Type(16)
comptime _SAMPLER = _Type(32)
comptime _SAMPLER_CUBE = _Type(33)
comptime _SAMPLER_3D = _Type(34)
comptime _SAMPLER_ARRAY = _Type(35)
comptime _NO_TYPE = _Type(-1)
# A struct's type is this plus its place in the shader's list.
comptime _STRUCT_BASE = 64


@fieldwise_init
struct _Struct(Copyable, Movable):
    """A struct the shader declares: its name, and its fields' names and
    types."""

    var name: String
    var names: List[String]
    var types: List[_Type]


def _type_named(name: String) -> _Type:
    """Return the type a keyword names, or `_NO_TYPE`."""
    if name == "uint":
        return _TUINT
    if name == "uvec2":
        return _UVEC2
    if name == "uvec3":
        return _UVEC3
    if name == "uvec4":
        return _UVEC4
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
    if name == "mat2":
        return _MAT2
    if name == "ivec2":
        return _IVEC2
    if name == "ivec3":
        return _IVEC3
    if name == "ivec4":
        return _IVEC4
    if name == "bvec2":
        return _BVEC2
    if name == "bvec3":
        return _BVEC3
    if name == "bvec4":
        return _BVEC4
    if name == "mat3":
        return _MAT3
    if name == "mat4":
        return _MAT4
    if name == "sampler2D":
        return _SAMPLER
    if name == "samplerCube":
        return _SAMPLER_CUBE
    if name == "sampler3D":
        return _SAMPLER_3D
    if name == "sampler2DArray":
        return _SAMPLER_ARRAY
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
# A struct's value: its `point` is where its fields are in the compiler's
# bundles, and it has no node.
comptime _BUNDLE = 7
# `modelMatrix[i]`, its `.xyz`, and the `mat3` of the first three: the
# model's turn and stretch, which carries the normal into the world as
# `modelMatrix * vec4(normal, 0.0)` does. The point holds the column.
comptime _MODEL_COLUMN = 30
comptime _MODEL_COLUMN3 = 31
comptime _MODEL_ROTATION = 32


def _is_matrix_tag(tag: Int) -> Bool:
    """Return True for a built-in matrix, or a product of them."""
    return tag >= _MATRIX and tag < _MATRIX + 16


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
# A local matrix, given its value once: a register holds no matrix, so the
# name stands for the matrix its initializer built.
comptime _MATRIX_LOCAL = 9
# An array: its value's type is the element's, its variable is its length,
# and its elements are the symbols just before it, named `a[0]` and on.
comptime _ARRAY = 10
# A struct variable: its fields are the symbols just before it, named
# `s.a` and on, a struct field's own fields before it.
comptime _STRUCT_VAR = 11


@fieldwise_init
struct _Symbol(Copyable, Movable):
    """A name in scope: its kind, the value it holds, and the variable that
    holds a local's or an output's value."""

    var name: String
    var kind: Int
    var value: _Value
    var variable: Int
    var written: Bool


# How a parameter passes its value: into the function, back out of it, or
# both.
comptime _IN = 0
comptime _OUT = 1
comptime _INOUT = 2


@fieldwise_init
struct _Function(Copyable, Movable):
    """A function of the shader: its signature and where its body is."""

    var name: String
    var result: _Type
    var types: List[_Type]
    var names: List[String]
    # Each parameter's `_IN`, `_OUT` or `_INOUT`.
    var modes: List[Int]
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


def _fold(mark: String, a: Float64, b: Float64) -> Float64:
    """Evaluate known float arithmetic with per-node Float32 rounding."""
    var x = Float32(a)
    var y = Float32(b)
    if mark == "+":
        return Float64(x + y)
    if mark == "-":
        return Float64(x - y)
    if mark == "*":
        return Float64(x * y)
    return Float64(x / y)


def _fold_uint(mark: String, a: Float64, b: Float64) -> Float64:
    """Evaluate a defined scalar unsigned operation modulo 2 ** 32."""
    var x = UInt32(UInt64(a))
    var y = UInt32(UInt64(b))
    if mark == "+":
        return Float64(x + y)
    if mark == "-":
        return Float64(x - y)
    if mark == "*":
        return Float64(x * y)
    if mark == "/":
        return Float64(x // y) if y != 0 else 0
    if mark == "%":
        return Float64(x % y) if y != 0 else 0
    if mark == "&":
        return Float64(x & y)
    if mark == "|":
        return Float64(x | y)
    if mark == "^":
        return Float64(x ^ y)
    if mark == "<<":
        return Float64(x << y) if y < 32 else 0
    return Float64(x >> y) if y < 32 else 0


def _fold_int(mark: String, a: Float64, b: Float64) -> Float64:
    """Evaluate scalar signed arithmetic with exact 32-bit intermediates."""
    var x = Int64(a)
    var y = Int64(b)
    var bits: UInt32
    if mark == "+":
        bits = UInt32(x) + UInt32(y)
    elif mark == "-":
        bits = UInt32(x) - UInt32(y)
    elif mark == "*":
        bits = UInt32(x) * UInt32(y)
    elif mark == "/":
        bits = UInt32(Int64(a / b)) if y != 0 else UInt32(0)
    else:
        bits = UInt32(x - y * Int64(a / b)) if y != 0 else UInt32(0)
    return Float64(bitcast[DType.int32](bits))


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
        or mark == "%="
        or mark == "&="
        or mark == "|="
        or mark == "^="
        or mark == "<<="
        or mark == ">>="
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
