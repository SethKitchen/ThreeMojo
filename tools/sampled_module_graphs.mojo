# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live sampled module graphs.

The trig module and the interval module keep their reviewed syntax graphs.
The jet class keeps its reviewed primitive graph. A changed graph is refused.
"""

from std.pathlib import Path

from tests._python_tokens import _tokenize
from tools._bigint import BigInt
from tools._python_float import parse_float, python_repr
from tools._sha256 import sha256_hex


comptime _NAME = 1
comptime _NUMBER = 2
comptime _STRING = 3
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6
comptime _OP = 55
comptime _TRIG = "extensions/carla/curve_trig.mojo"
comptime _INTERVAL = "extensions/carla/curve_interval.mojo"
comptime _TRIG_GRAPH = (
    "4ca47db55caa96ba9ad6c6f43fa65d30a8fefe419f555d46a1a948a2fc606ecc"
)
comptime _INTERVAL_GRAPH = (
    "32b7bce9ad0b996fa87a7bc63ff0c905065751d164f7d673342234716523fd8e"
)
comptime _PRIMITIVE = (
    "e2e0257a0f42a95bac586638fc5d532f4bc69b882127201bbf343006f2143484"
)


def _fail(message: String) raises:
    """Raise a module-graph error.

    Args:
        message: The failure text.

    Raises:
        Error: The graph check failed.
    """
    raise Error(message)


def _json_str(text: String) -> String:
    """Return `text` as a JSON string.

    Args:
        text: The decoded characters.

    Returns:
        The quoted JSON text.
    """
    var out = String('"')
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes):
        var byte = bytes[index]
        if byte == 34:
            out += '\\"'
        elif byte == 92:
            out += "\\\\"
        elif byte == 10:
            out += "\\n"
        elif byte == 13:
            out += "\\r"
        elif byte == 9:
            out += "\\t"
        elif byte < 32:
            var hex = String("0123456789abcdef")
            var high = Int(byte) // 16
            var low = Int(byte) % 16
            out += "\\u00"
            out += String(hex[byte = high : high + 1])
            out += String(hex[byte = low : low + 1])
        else:
            out += String(chr(Int(byte)))
        index += 1
    out += '"'
    return out


def _pair(key: String, value: String) -> String:
    """Return one JSON field pair.

    Args:
        key: The field name.
        value: The encoded field value.

    Returns:
        The pair, without surrounding spaces.
    """
    return '["' + key + '",' + value + "]"


def _node(kind: String, fields: String) -> String:
    """Return one normalized AST node.

    Args:
        kind: The Python AST type name.
        fields: The field pairs, separated by commas.

    Returns:
        The node.
    """
    return '["' + kind + '",[' + fields + "]]"


def _empty(kind: String) -> String:
    """Return a node that has no fields.

    Args:
        kind: The Python AST type name.

    Returns:
        The node.
    """
    return '["' + kind + '",[]]'


def _load() -> String:
    """Return a load context.

    Returns:
        The load node.
    """
    return _empty("Load")


def _name(ident: String, ctx: String) -> String:
    """Return a name node.

    Args:
        ident: The identifier.
        ctx: The context node.

    Returns:
        The name node.
    """
    return _node(
        "Name", _pair("id", _json_str(ident)) + "," + _pair("ctx", ctx)
    )


def _qualifier(text: String) -> Bool:
    """Return whether `text` is a stripped Mojo qualifier.

    Args:
        text: One name token.

    Returns:
        True for `var`, `mut`, `out`, `ref`, `comptime`, or `raises`.
    """
    if text == "var":
        return True
    if text == "mut":
        return True
    if text == "out":
        return True
    if text == "ref":
        return True
    if text == "comptime":
        return True
    return text == "raises"


def _decode_string(token: String) raises -> String:
    """Return the characters of one Python string token.

    Args:
        token: The quoted token text.

    Returns:
        The decoded characters.

    Raises:
        Error: The token is not a closed quote or uses an unknown escape.
    """
    var bytes = token.as_bytes()
    if len(bytes) < 2:
        _fail("unsupported reference syntax: string")
    var quote = bytes[0]
    var triple = len(bytes) >= 6 and bytes[1] == quote and bytes[2] == quote
    var index = 3 if triple else 1
    var end = len(bytes) - (3 if triple else 1)
    var out = String()
    while index < end:
        var byte = bytes[index]
        if byte == 92:
            index += 1
            if index >= end:
                _fail("unsupported reference syntax: string")
            var esc = bytes[index]
            if esc == 110:
                out += "\n"
            elif esc == 116:
                out += "\t"
            elif esc == 114:
                out += "\r"
            elif esc == 92 or esc == 39 or esc == 34:
                out += String(chr(Int(esc)))
            else:
                _fail("unsupported reference syntax: string")
        else:
            out += String(chr(Int(byte)))
        index += 1
    return out


def _hex_int(text: String) -> String:
    """Return the decimal digits of a hexadecimal token.

    Args:
        text: A token that starts with `0x`.

    Returns:
        The decimal digits.
    """
    var value = BigInt(0)
    var sixteen = BigInt(16)
    var bytes = text.as_bytes()
    var index = 2
    while index < len(bytes):
        var byte = bytes[index]
        var digit = 0
        if byte >= 48 and byte <= 57:
            digit = Int(byte) - 48
        elif byte >= 65 and byte <= 70:
            digit = Int(byte) - 55
        elif byte >= 97 and byte <= 102:
            digit = Int(byte) - 87
        value = value * sixteen + BigInt(digit)
        index += 1
    return value.to_string()


def _number(text: String) raises -> String:
    """Return the constant node of one number token.

    Args:
        text: The number token.

    Returns:
        The constant node.

    Raises:
        Error: The token is not a float or an integer.
    """
    var float_token = False
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes):
        var byte = bytes[index]
        if byte == 46 or byte == 101 or byte == 69:
            float_token = True
        index += 1
    if float_token:
        return _node("Constant", _pair("value", python_repr(parse_float(text))))
    var digits = text
    if text.startswith("0x") or text.startswith("0X"):
        digits = _hex_int(text)
    return _node("Constant", _pair("value", digits))


def _match(kinds: List[Int], texts: List[String], open_at: Int) raises -> Int:
    """Return the index of the bracket that closes `open_at`.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        open_at: The index of `[`.

    Returns:
        The index of the matching `]`.

    Raises:
        Error: The bracket is not closed.
    """
    var depth = 0
    var index = open_at
    while index < len(kinds):
        if kinds[index] == _OP and texts[index] == "[":
            depth += 1
        elif kinds[index] == _OP and texts[index] == "]":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    _fail("unclosed Mojo generic declaration")
    return 0


def _token_label(kind: Int) -> String:
    """Return the Python token name of `kind`.

    Args:
        kind: The token number.

    Returns:
        `NAME`, `NUMBER`, `STRING`, or `OP`.
    """
    if kind == _NAME:
        return "NAME"
    if kind == _NUMBER:
        return "NUMBER"
    if kind == _STRING:
        return "STRING"
    return "OP"


def _meta(
    kinds: List[Int], texts: List[String], start: Int, end: Int
) -> String:
    """Return the generic-parameter metadata between two brackets.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        start: The first parameter token.
        end: The closing bracket, excluded.

    Returns:
        The JSON list of token pairs.
    """
    var out = String("[")
    var first = True
    var index = start
    while index < end:
        if not first:
            out += ","
        first = False
        out += (
            "["
            + _json_str(_token_label(kinds[index]))
            + ","
            + _json_str(texts[index])
            + "]"
        )
        index += 1
    out += "]"
    return out


def _prepare(
    source: String,
    mut kinds: List[Int],
    mut texts: List[String],
    mut generics: List[String],
) raises:
    """Tokenize `source` and remove qualifiers and generic brackets.

    Args:
        source: One module.
        kinds: The parser token kinds, replaced by this call.
        texts: The parser token texts, replaced by this call.
        generics: One metadata string for each `def` or `class`, in order.
            An empty string means the declaration has no type parameters.

    Raises:
        Error: The source cannot be tokenized or a generic is unclosed.
    """
    var raw_kinds = List[Int]()
    var raw_texts = List[String]()
    _tokenize(source, raw_kinds, raw_texts)
    var mid_kinds = List[Int]()
    var mid_texts = List[String]()
    var index = 0
    while index < len(raw_kinds):
        var text = raw_texts[index]
        if raw_kinds[index] == _NAME and _qualifier(text):
            index += 1
            continue
        if raw_kinds[index] == _NAME and text == "struct":
            text = "class"
        mid_kinds.append(raw_kinds[index])
        mid_texts.append(text)
        index += 1
    index = 0
    while index < len(mid_kinds):
        var kind = mid_kinds[index]
        var text = mid_texts[index]
        kinds.append(kind)
        texts.append(text)
        if kind == _NAME and (text == "def" or text == "class"):
            var generic = (
                index + 2 < len(mid_kinds)
                and mid_kinds[index + 1] == _NAME
                and mid_kinds[index + 2] == _OP
                and mid_texts[index + 2] == "["
            )
            if generic:
                kinds.append(mid_kinds[index + 1])
                texts.append(mid_texts[index + 1])
                var end = _match(mid_kinds, mid_texts, index + 2)
                generics.append(_meta(mid_kinds, mid_texts, index + 3, end))
                index = end + 1
                continue
            generics.append("")
        index += 1


def _plain_name(node: String) -> String:
    """Return the identifier when `node` is a plain name.

    Args:
        node: One expression node.

    Returns:
        The identifier, or an empty string when `node` is not a name.
    """
    var prefix = String('["Name",[["id","')
    if not node.startswith(prefix):
        return ""
    var rest = String(node[byte = prefix.byte_length() :])
    var end = rest.find('"')
    if end < 0:
        return ""
    return String(rest[byte=:end])


def _store(node: String) raises -> String:
    """Return `node` with its outermost context set to store.

    Args:
        node: A name or an attribute.

    Returns:
        The same node with a store context.

    Raises:
        Error: The node has no load context.
    """
    var needle = String('["ctx",["Load",[]]]')
    var last = -1
    var offset = 0
    var size = node.byte_length()
    var step = needle.byte_length()
    while offset < size:
        var rest = String(node[byte=offset:])
        var at = rest.find(needle)
        if at < 0:
            break
        last = offset + at
        offset += at + step
    if last < 0:
        _fail("unsupported reference syntax: target")
    var repl = String('["ctx",["Store",[]]]')
    return String(node[byte=:last]) + repl + String(node[byte = last + step :])


struct _Parser:
    """A parser for the normalized reference graph."""

    var kinds: List[Int]
    var texts: List[String]
    var at: Int
    var generics: List[String]
    var generic_at: Int
    var depth: Int
    var jet_count: Int
    var jet: String
    var alias_jet: Int
    var alias_value: Int
    var jet_alias: String
    var value_alias: String
    var fn_names: List[String]
    var fn_nodes: List[String]

    def __init__(out self):
        """Create an empty parser."""
        self.kinds = List[Int]()
        self.texts = List[String]()
        self.at = 0
        self.generics = List[String]()
        self.generic_at = 0
        self.depth = 0
        self.jet_count = 0
        self.jet = ""
        self.alias_jet = 0
        self.alias_value = 0
        self.jet_alias = ""
        self.value_alias = ""
        self.fn_names = List[String]()
        self.fn_nodes = List[String]()

    def _done(self) -> Bool:
        """Return whether every token has been read.

        Returns:
            True at the end of the token list.
        """
        return self.at >= len(self.kinds)

    def _kind(self, kind: Int) -> Bool:
        """Return whether the next token has `kind`.

        Args:
            kind: The token number.

        Returns:
            True when that token is next.
        """
        if self._done():
            return False
        return self.kinds[self.at] == kind

    def _op(self, text: String) -> Bool:
        """Return whether the next token is the operator `text`.

        Args:
            text: The operator spelling.

        Returns:
            True when that operator is next.
        """
        if not self._kind(_OP):
            return False
        return self.texts[self.at] == text

    def _keyword_next(self) -> Bool:
        """Return whether the next tokens are a keyword argument.

        Returns:
            True when a name is followed by `=`.
        """
        if not self._kind(_NAME):
            return False
        var nxt = self.at + 1
        if nxt >= len(self.kinds):
            return False
        return self.kinds[nxt] == _OP and self.texts[nxt] == "="

    def _is(self, text: String) -> Bool:
        """Return whether the next token is the name `text`.

        Args:
            text: The name.

        Returns:
            True when that name is next.
        """
        if not self._kind(_NAME):
            return False
        return self.texts[self.at] == text

    def _bump(mut self) raises -> String:
        """Return the next token text and advance.

        Returns:
            The token text.

        Raises:
            Error: There is no next token.
        """
        if self._done():
            _fail("unsupported reference syntax: end")
        var text = self.texts[self.at]
        self.at += 1
        return text

    def _expect_op(mut self, text: String) raises:
        """Require the next token to be the operator `text`.

        Args:
            text: The operator spelling.

        Raises:
            Error: A different token is next.
        """
        if not self._op(text):
            _fail("unsupported reference syntax: " + text)
        _ = self._bump()

    def _expect_kind(mut self, kind: Int) raises:
        """Require the next token to have `kind`.

        Args:
            kind: The token number.

        Raises:
            Error: A different token is next.
        """
        if not self._kind(kind):
            _fail("unsupported reference syntax: layout")
        _ = self._bump()

    def _expect_name(mut self) raises -> String:
        """Require a name and return its text.

        Returns:
            The name.

        Raises:
            Error: The next token is not a name.
        """
        if not self._kind(_NAME):
            _fail("unsupported reference syntax: name")
        return self._bump()

    def _take_generic(mut self) raises -> String:
        """Return the metadata of the next declaration.

        Returns:
            The metadata JSON, or an empty string when there is none.

        Raises:
            Error: A declaration has no recorded metadata.
        """
        if self.generic_at >= len(self.generics):
            _fail("unsupported reference syntax: generic")
        var value = self.generics[self.generic_at]
        self.generic_at += 1
        return value

    def _atom(mut self) raises -> String:
        """Parse one atom.

        Returns:
            The expression node.

        Raises:
            Error: The next token cannot start an atom.
        """
        if self._kind(_NAME):
            var word = self._bump()
            if word == "True":
                return _node("Constant", _pair("value", "true"))
            if word == "False":
                return _node("Constant", _pair("value", "false"))
            if word == "None":
                return '["Constant",[]]'
            return _name(word, _load())
        if self._kind(_NUMBER):
            return _number(self._bump())
        if self._kind(_STRING):
            var decoded = _decode_string(self._bump())
            return _node("Constant", _pair("value", _json_str(decoded)))
        if self._op("("):
            return self._paren()
        if self._op("["):
            return self._list()
        _fail("unsupported reference syntax: atom")
        return ""

    def _paren(mut self) raises -> String:
        """Parse one parenthesized expression or tuple.

        Returns:
            The expression or tuple node.

        Raises:
            Error: The parenthesis is not closed.
        """
        _ = self._bump()
        if self._op(")"):
            _ = self._bump()
            return _node(
                "Tuple", _pair("elts", "[]") + "," + _pair("ctx", _load())
            )
        var first = self._expr()
        if self._op(","):
            var elts = "[" + first
            while self._op(","):
                _ = self._bump()
                if self._op(")"):
                    break
                elts += "," + self._expr()
            elts += "]"
            self._expect_op(")")
            return _node(
                "Tuple", _pair("elts", elts) + "," + _pair("ctx", _load())
            )
        self._expect_op(")")
        return first

    def _list(mut self) raises -> String:
        """Parse one list display.

        Returns:
            The list node.

        Raises:
            Error: The bracket is not closed.
        """
        _ = self._bump()
        var elts = String("[")
        var first = True
        if not self._op("]"):
            while True:
                if not first:
                    elts += ","
                first = False
                elts += self._expr()
                if self._op(","):
                    _ = self._bump()
                    if self._op("]"):
                        break
                    continue
                break
        self._expect_op("]")
        elts += "]"
        return _node("List", _pair("elts", elts) + "," + _pair("ctx", _load()))

    def _call(mut self, func: String) raises -> String:
        """Parse one call after `func`.

        Args:
            func: The callee node.

        Returns:
            The call node.

        Raises:
            Error: The call is not closed.
        """
        _ = self._bump()
        var args = String("[")
        var keywords = String("[")
        var first_arg = True
        var first_keyword = True
        var saw_keyword = False
        if not self._op(")"):
            while True:
                if self._keyword_next():
                    saw_keyword = True
                    var name = self._bump()
                    _ = self._bump()
                    var value = self._expr()
                    if not first_keyword:
                        keywords += ","
                    first_keyword = False
                    keywords += _node(
                        "keyword",
                        _pair("arg", _json_str(name))
                        + ","
                        + _pair("value", value),
                    )
                else:
                    if saw_keyword:
                        _fail("unsupported reference syntax: keyword")
                    if not first_arg:
                        args += ","
                    first_arg = False
                    args += self._expr()
                if self._op(","):
                    _ = self._bump()
                    if self._op(")"):
                        break
                    continue
                break
        self._expect_op(")")
        args += "]"
        keywords += "]"
        return _node(
            "Call",
            _pair("func", func)
            + ","
            + _pair("args", args)
            + ","
            + _pair("keywords", keywords),
        )

    def _subscript(mut self, value: String) raises -> String:
        """Parse one subscript after `value`.

        Args:
            value: The value node.

        Returns:
            The subscript node.

        Raises:
            Error: The bracket is not closed.
        """
        _ = self._bump()
        var slice = self._expr()
        if self._op(","):
            var elts = "[" + slice
            while self._op(","):
                _ = self._bump()
                if self._op("]"):
                    break
                elts += "," + self._expr()
            elts += "]"
            slice = _node(
                "Tuple", _pair("elts", elts) + "," + _pair("ctx", _load())
            )
        self._expect_op("]")
        return _node(
            "Subscript",
            _pair("value", value)
            + ","
            + _pair("slice", slice)
            + ","
            + _pair("ctx", _load()),
        )

    def _trailer(mut self) raises -> String:
        """Parse one atom and its calls, subscripts, and attributes.

        Returns:
            The expression node.

        Raises:
            Error: A trailer is not closed.
        """
        var node = self._atom()
        while True:
            if self._op("("):
                node = self._call(node)
            elif self._op("["):
                node = self._subscript(node)
            elif self._op("."):
                _ = self._bump()
                var attr = self._expect_name()
                node = _node(
                    "Attribute",
                    _pair("value", node)
                    + ","
                    + _pair("attr", _json_str(attr))
                    + ","
                    + _pair("ctx", _load()),
                )
            else:
                return node

    def _unary(mut self) raises -> String:
        """Parse one unary expression.

        Returns:
            The expression node.

        Raises:
            Error: The operand is not an expression.
        """
        if self._op("-"):
            _ = self._bump()
            var operand = self._unary()
            return _node(
                "UnaryOp",
                _pair("op", _empty("USub")) + "," + _pair("operand", operand),
            )
        return self._trailer()

    def _term(mut self) raises -> String:
        """Parse one product.

        Returns:
            The expression node.

        Raises:
            Error: A factor is not an expression.
        """
        var left = self._unary()
        while self._op("*") or self._op("/") or self._op("//"):
            var op = "Mult"
            if self._op("/"):
                op = "Div"
            elif self._op("//"):
                op = "FloorDiv"
            _ = self._bump()
            var right = self._unary()
            left = _node(
                "BinOp",
                _pair("left", left)
                + ","
                + _pair("op", _empty(op))
                + ","
                + _pair("right", right),
            )
        return left

    def _arith(mut self) raises -> String:
        """Parse one sum.

        Returns:
            The expression node.

        Raises:
            Error: A term is not an expression.
        """
        var left = self._term()
        while self._op("+") or self._op("-"):
            var op = "Add" if self._op("+") else "Sub"
            _ = self._bump()
            var right = self._term()
            left = _node(
                "BinOp",
                _pair("left", left)
                + ","
                + _pair("op", _empty(op))
                + ","
                + _pair("right", right),
            )
        return left

    def _shift(mut self) raises -> String:
        """Parse one shift expression.

        Returns:
            The expression node.

        Raises:
            Error: A side is not an expression.
        """
        var left = self._arith()
        while self._op("<<") or self._op(">>"):
            var op = "LShift" if self._op("<<") else "RShift"
            _ = self._bump()
            var right = self._arith()
            left = _node(
                "BinOp",
                _pair("left", left)
                + ","
                + _pair("op", _empty(op))
                + ","
                + _pair("right", right),
            )
        return left

    def _bitand(mut self) raises -> String:
        """Parse one bitwise-and expression.

        Returns:
            The expression node.

        Raises:
            Error: A side is not an expression.
        """
        var left = self._shift()
        while self._op("&"):
            _ = self._bump()
            var right = self._shift()
            left = _node(
                "BinOp",
                _pair("left", left)
                + ","
                + _pair("op", _empty("BitAnd"))
                + ","
                + _pair("right", right),
            )
        return left

    def _cmp_name(self) -> String:
        """Return the comparison node name of the next operator.

        Returns:
            `Eq`, `NotEq`, `Lt`, `LtE`, `Gt`, or `GtE`.
        """
        if self._op("=="):
            return "Eq"
        if self._op("!="):
            return "NotEq"
        if self._op("<="):
            return "LtE"
        if self._op(">="):
            return "GtE"
        if self._op("<"):
            return "Lt"
        return "Gt"

    def _compare(mut self) raises -> String:
        """Parse one comparison.

        Returns:
            The expression node.

        Raises:
            Error: A side is not an expression.
        """
        var left = self._bitand()
        var compared = (
            self._op("==")
            or self._op("!=")
            or self._op("<=")
            or self._op(">=")
            or self._op("<")
            or self._op(">")
        )
        if not compared:
            return left
        var op = self._cmp_name()
        _ = self._bump()
        var right = self._bitand()
        return _node(
            "Compare",
            _pair("left", left)
            + ","
            + _pair("ops", "[" + _empty(op) + "]")
            + ","
            + _pair("comparators", "[" + right + "]"),
        )

    def _not(mut self) raises -> String:
        """Parse one `not` expression.

        Returns:
            The expression node.

        Raises:
            Error: The operand is not an expression.
        """
        if self._is("not"):
            _ = self._bump()
            var operand = self._not()
            return _node(
                "UnaryOp",
                _pair("op", _empty("Not")) + "," + _pair("operand", operand),
            )
        return self._compare()

    def _and(mut self) raises -> String:
        """Parse one `and` expression.

        Returns:
            The expression node.

        Raises:
            Error: A value is not an expression.
        """
        var left = self._not()
        if not self._is("and"):
            return left
        var values = "[" + left
        while self._is("and"):
            _ = self._bump()
            values += "," + self._not()
        values += "]"
        return _node(
            "BoolOp", _pair("op", _empty("And")) + "," + _pair("values", values)
        )

    def _or(mut self) raises -> String:
        """Parse one `or` expression.

        Returns:
            The expression node.

        Raises:
            Error: A value is not an expression.
        """
        var left = self._and()
        if not self._is("or"):
            return left
        var values = "[" + left
        while self._is("or"):
            _ = self._bump()
            values += "," + self._and()
        values += "]"
        return _node(
            "BoolOp", _pair("op", _empty("Or")) + "," + _pair("values", values)
        )

    def _expr(mut self) raises -> String:
        """Parse one expression, including a conditional expression.

        Returns:
            The expression node.

        Raises:
            Error: The expression is incomplete.
        """
        var body = self._or()
        if not self._is("if"):
            return body
        _ = self._bump()
        var test = self._or()
        if not self._is("else"):
            _fail("unsupported reference syntax: else")
        _ = self._bump()
        var orelse = self._expr()
        return _node(
            "IfExp",
            _pair("test", test)
            + ","
            + _pair("body", body)
            + ","
            + _pair("orelse", orelse),
        )

    def _expr_stmt(mut self) raises -> String:
        """Parse one assignment, annotation, update, or expression statement.

        Returns:
            The statement node.

        Raises:
            Error: The statement is incomplete.
        """
        var left = self._expr()
        if self._op("="):
            _ = self._bump()
            var value = self._expr()
            var ident = _plain_name(left)
            if self.depth == 0 and ident == "_Jet":
                self.alias_jet += 1
                self.jet_alias = value
            if self.depth == 0 and ident == "_ValueJet":
                self.alias_value += 1
                self.value_alias = value
            var stored = _store(left)
            return _node(
                "Assign",
                _pair("targets", "[" + stored + "]")
                + ","
                + _pair("value", value),
            )
        if self._op(":"):
            _ = self._bump()
            var annotation = self._expr()
            var fields = (
                _pair("target", _store(left))
                + ","
                + _pair("annotation", annotation)
            )
            if self._op("="):
                _ = self._bump()
                fields += "," + _pair("value", self._expr())
            var simple = "1" if _plain_name(left) != "" else "0"
            fields += "," + _pair("simple", simple)
            return _node("AnnAssign", fields)
        if self._op("+=") or self._op("-=") or self._op("*="):
            var op = "Add"
            if self._op("-="):
                op = "Sub"
            elif self._op("*="):
                op = "Mult"
            _ = self._bump()
            var value = self._expr()
            return _node(
                "AugAssign",
                _pair("target", _store(left))
                + ","
                + _pair("op", _empty(op))
                + ","
                + _pair("value", value),
            )
        return _node("Expr", _pair("value", left))

    def _import(mut self) raises -> String:
        """Parse one `from` import.

        Returns:
            The import node.

        Raises:
            Error: The import is incomplete.
        """
        _ = self._bump()
        var module = self._expect_name()
        while self._op("."):
            _ = self._bump()
            module += "." + self._expect_name()
        if not self._is("import"):
            _fail("unsupported reference syntax: import")
        _ = self._bump()
        var wrapped = self._op("(")
        if wrapped:
            _ = self._bump()
        var names = String("[")
        var first = True
        if not (wrapped and self._op(")")):
            while True:
                if not first:
                    names += ","
                first = False
                var ident = self._expect_name()
                var fields = _pair("name", _json_str(ident))
                if self._is("as"):
                    _ = self._bump()
                    fields += "," + _pair(
                        "asname", _json_str(self._expect_name())
                    )
                names += _node("alias", fields)
                if self._op(","):
                    _ = self._bump()
                    if self._kind(_NEWLINE) or self._done() or self._op(")"):
                        break
                    continue
                break
        if wrapped:
            self._expect_op(")")
        names += "]"
        return _node(
            "ImportFrom",
            _pair("module", _json_str(module))
            + ","
            + _pair("names", names)
            + ","
            + _pair("level", "0"),
        )

    def _simple(mut self) raises -> String:
        """Parse one small statement.

        Returns:
            The statement node.

        Raises:
            Error: The statement is incomplete.
        """
        if self._is("return"):
            _ = self._bump()
            var value = self._expr()
            return _node("Return", _pair("value", value))
        if self._is("assert"):
            _ = self._bump()
            var test = self._expr()
            return _node("Assert", _pair("test", test))
        if self._is("continue"):
            _ = self._bump()
            return '["Continue",[]]'
        if self._is("raise"):
            _ = self._bump()
            var exc = self._expr()
            return _node("Raise", _pair("exc", exc))
        if self._is("from"):
            return self._import()
        return self._expr_stmt()

    def _suite(mut self) raises -> String:
        """Parse one indented suite.

        Returns:
            The JSON list of statements.

        Raises:
            Error: The suite is not indented.
        """
        self._expect_kind(_NEWLINE)
        self._expect_kind(_INDENT)
        self.depth += 1
        var body = String("[")
        var first = True
        while not self._kind(_DEDENT):
            if self._done():
                _fail("unsupported reference syntax: suite")
            if not first:
                body += ","
            first = False
            body += self._statement()
        _ = self._bump()
        self.depth -= 1
        body += "]"
        return body

    def _if_tail(mut self) raises -> String:
        """Parse one `if` after its keyword.

        Returns:
            The if node.

        Raises:
            Error: The statement is incomplete.
        """
        var test = self._expr()
        self._expect_op(":")
        var body = self._suite()
        var orelse = String("[]")
        if self._is("elif"):
            _ = self._bump()
            orelse = "[" + self._if_tail() + "]"
        elif self._is("else"):
            _ = self._bump()
            self._expect_op(":")
            orelse = self._suite()
        return _node(
            "If",
            _pair("test", test)
            + ","
            + _pair("body", body)
            + ","
            + _pair("orelse", orelse),
        )

    def _parameters(mut self) raises -> String:
        """Parse one parameter list, including the parentheses.

        Returns:
            The arguments node.

        Raises:
            Error: The parameter list is incomplete.
        """
        self._expect_op("(")
        var args = String("[")
        var defaults = String("[")
        var first = True
        var first_default = True
        var saw_default = False
        if not self._op(")"):
            while True:
                if not first:
                    args += ","
                first = False
                var ident = self._expect_name()
                var fields = _pair("arg", _json_str(ident))
                if self._op(":"):
                    _ = self._bump()
                    fields += "," + _pair("annotation", self._expr())
                if self._op("="):
                    _ = self._bump()
                    if not first_default:
                        defaults += ","
                    first_default = False
                    defaults += self._expr()
                    saw_default = True
                elif saw_default:
                    _fail("unsupported reference syntax: default")
                args += _node("arg", fields)
                if self._op(","):
                    _ = self._bump()
                    if self._op(")"):
                        break
                    continue
                break
        self._expect_op(")")
        args += "]"
        defaults += "]"
        return _node(
            "arguments",
            _pair("posonlyargs", "[]")
            + ","
            + _pair("args", args)
            + ","
            + _pair("kwonlyargs", "[]")
            + ","
            + _pair("kw_defaults", "[]")
            + ","
            + _pair("defaults", defaults),
        )

    def _def(mut self, decorators: String) raises -> String:
        """Parse one function.

        Args:
            decorators: The JSON list of decorators.

        Returns:
            The function node.

        Raises:
            Error: The function is incomplete.
        """
        var top = self.depth == 0
        _ = self._bump()
        var ident = self._expect_name()
        var generic = self._take_generic()
        var args = self._parameters()
        var returns = String()
        var has_return = False
        if self._op("->"):
            _ = self._bump()
            returns = self._expr()
            has_return = True
        self._expect_op(":")
        var body = self._suite()
        var fields = (
            _pair("name", _json_str(ident))
            + ","
            + _pair("args", args)
            + ","
            + _pair("body", body)
            + ","
            + _pair("decorator_list", decorators)
        )
        if has_return:
            fields += "," + _pair("returns", returns)
        if generic != "":
            fields += "," + _pair("mojo_type_parameters", generic)
        var node = _node("FunctionDef", fields)
        if top:
            self.fn_names.append(ident)
            self.fn_nodes.append(node)
        return node

    def _class(mut self, decorators: String) raises -> String:
        """Parse one class.

        Args:
            decorators: The JSON list of decorators.

        Returns:
            The class node.

        Raises:
            Error: The class is incomplete.
        """
        _ = self._bump()
        var ident = self._expect_name()
        var generic = self._take_generic()
        var bases = String("[")
        if self._op("("):
            _ = self._bump()
            if not self._op(")"):
                bases += self._expr()
                while self._op(","):
                    _ = self._bump()
                    if self._op(")"):
                        break
                    bases += "," + self._expr()
            self._expect_op(")")
        bases += "]"
        self._expect_op(":")
        var body = self._suite()
        var fields = (
            _pair("name", _json_str(ident))
            + ","
            + _pair("bases", bases)
            + ","
            + _pair("keywords", "[]")
            + ","
            + _pair("body", body)
            + ","
            + _pair("decorator_list", decorators)
        )
        if generic != "":
            fields += "," + _pair("mojo_type_parameters", generic)
        var node = _node("ClassDef", fields)
        if ident == "_JetExpression":
            self.jet_count += 1
            self.jet = node
        return node

    def _statement(mut self) raises -> String:
        """Parse one statement.

        Returns:
            The statement node.

        Raises:
            Error: The statement is incomplete.
        """
        var decorators = String("[")
        var first = True
        while self._op("@"):
            _ = self._bump()
            if not first:
                decorators += ","
            first = False
            decorators += self._expr()
            self._expect_kind(_NEWLINE)
        decorators += "]"
        if self._is("def"):
            return self._def(decorators)
        if self._is("class"):
            return self._class(decorators)
        if not first:
            _fail("unsupported reference syntax: decorator")
        if self._is("if"):
            _ = self._bump()
            return self._if_tail()
        if self._is("while"):
            _ = self._bump()
            var test = self._expr()
            self._expect_op(":")
            var body = self._suite()
            var orelse = String("[]")
            if self._is("else"):
                _ = self._bump()
                self._expect_op(":")
                orelse = self._suite()
            return _node(
                "While",
                _pair("test", test)
                + ","
                + _pair("body", body)
                + ","
                + _pair("orelse", orelse),
            )
        if self._is("for"):
            _ = self._bump()
            var target = _store(self._expr())
            if not self._is("in"):
                _fail("unsupported reference syntax: in")
            _ = self._bump()
            var iter = self._expr()
            self._expect_op(":")
            var body = self._suite()
            var orelse = String("[]")
            if self._is("else"):
                _ = self._bump()
                self._expect_op(":")
                orelse = self._suite()
            return _node(
                "For",
                _pair("target", target)
                + ","
                + _pair("iter", iter)
                + ","
                + _pair("body", body)
                + ","
                + _pair("orelse", orelse),
            )
        var stmt = self._simple()
        self._expect_kind(_NEWLINE)
        return stmt

    def parse(mut self, source: String) raises -> String:
        """Parse `source` into a module node.

        Args:
            source: One module.

        Returns:
            The module node.

        Raises:
            Error: The source is not a supported reference module.
        """
        _prepare(source, self.kinds, self.texts, self.generics)
        var body = String("[")
        var first = True
        while not self._done() and not self._kind(_DEDENT):
            if not first:
                body += ","
            first = False
            body += self._statement()
        if not self._done():
            _fail("unsupported reference syntax: trailing")
        body += "]"
        return _node(
            "Module",
            _pair("body", body) + "," + _pair("type_ignores", "[]"),
        )


def _jet_subscript(flag: String) -> String:
    """Return the alias value `_JetExpression[flag]`.

    Args:
        flag: `true` or `false`.

    Returns:
        The subscript node.
    """
    var value = _name("_JetExpression", _load())
    var slice = _node("Constant", _pair("value", flag))
    return _node(
        "Subscript",
        _pair("value", value)
        + ","
        + _pair("slice", slice)
        + ","
        + _pair("ctx", _load()),
    )


def _parsed(source: String) raises -> _Parser:
    """Parse `source` and keep the primitive records.

    Args:
        source: One module.

    Returns:
        The parser after a complete module.

    Raises:
        Error: The source is not a supported reference module.
    """
    var parser = _Parser()
    _ = parser.parse(source)
    return parser^


def module_graph_json(source: String) raises -> String:
    """Return the normalized syntax graph of `source`.

    Args:
        source: One module.

    Returns:
        The JSON graph.

    Raises:
        Error: The source is not a supported reference module.
    """
    var parser = _Parser()
    return parser.parse(source)


def reference_module_graph(source: String) raises -> String:
    """Return the SHA-256 of the normalized syntax graph.

    Args:
        source: One module.

    Returns:
        The hex digest.

    Raises:
        Error: The source is not a supported reference module.
    """
    return sha256_hex(module_graph_json(source).as_bytes())


def function_graph(source: String, name: String) raises -> String:
    """Return the SHA-256 of one top-level function.

    Args:
        source: One module.
        name: The function name.

    Returns:
        The hex digest of that function node.

    Raises:
        Error: The function is missing or repeated, or the source cannot
            be parsed.
    """
    var parser = _Parser()
    _ = parser.parse(source)
    var found = 0
    var node = String()
    var index = 0
    while index < len(parser.fn_names):
        if parser.fn_names[index] == name:
            found += 1
            node = parser.fn_nodes[index]
        index += 1
    if found != 1:
        _fail("missing or ambiguous function: " + name)
    return sha256_hex(node.as_bytes())


def primitive_graph(source: String) raises -> String:
    """Return the SHA-256 of the `_JetExpression` class.

    Args:
        source: The interval module.

    Returns:
        The hex digest of that class.

    Raises:
        Error: The class is missing, or a derivative alias changed.
    """
    var parser = _parsed(source)
    if parser.jet_count != 1:
        _fail("unsupported primitive declaration")
    if parser.alias_jet != 1:
        _fail("missing or ambiguous actual alias: _Jet")
    if parser.jet_alias != _jet_subscript("true"):
        _fail("actual derivative alias changed: _Jet")
    if parser.alias_value != 1:
        _fail("missing or ambiguous actual alias: _ValueJet")
    if parser.value_alias != _jet_subscript("false"):
        _fail("actual derivative alias changed: _ValueJet")
    return sha256_hex(parser.jet.as_bytes())


def require_primitive(source: String) raises:
    """Require the reviewed jet primitive graph.

    Args:
        source: The interval module.

    Raises:
        Error: The class or a derivative alias changed.
    """
    if primitive_graph(source) != _PRIMITIVE:
        _fail(
            "Jet primitive graph changed; renewed "
            + "derivative-independence review required"
        )


def _root(root: String) -> String:
    """Return `root` without a trailing slash.

    Args:
        root: The repository root.

    Returns:
        The root used to join module paths.
    """
    if root.byte_length() > 1 and root.endswith("/"):
        var end = root.byte_length() - 1
        return String(root[byte=0:end])
    return root


def _read(base: String, path: String) raises -> String:
    """Return one module's text.

    Args:
        base: The repository root.
        path: The module path.

    Returns:
        The module text.

    Raises:
        Error: The file cannot be read.
    """
    return Path(base + "/" + path).read_text()


def sampled_module_graphs(root: String) raises:
    """Require the live sampled module graphs.

    Args:
        root: The repository root.

    Raises:
        Error: A trig graph, an interval graph, or the jet primitive changed.
    """
    var base = _root(root)
    var trig = reference_module_graph(_read(base, _TRIG))
    if trig != _TRIG_GRAPH:
        _fail(
            "reference module changed; renewed review required: curve_trig.mojo"
        )
    var interval = reference_module_graph(_read(base, _INTERVAL))
    if interval != _INTERVAL_GRAPH:
        _fail(
            "reference module changed; renewed review required: "
            + "curve_interval.mojo"
        )
    require_primitive(_read(base, _INTERVAL))
