# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Expression dumps that match CPython's normalized AST.

The heading check compares these dumps. It does not execute the graph.
"""

from tests._python_tokens import (
    _DEDENT,
    _INDENT,
    _NAME,
    _NEWLINE,
    _NUMBER,
    _OP,
    _STRING,
    _tokenize,
    function_slice,
    python_syntax_json,
    syntax_tree_source,
)
from tools._python_float import parse_float
from tools._python_json import PY_LIST, PY_STR, PyJson, py_equal


comptime _E_NAME = 1
comptime _E_INT = 2
comptime _E_FLOAT = 3
comptime _E_BOOL = 4
comptime _E_NONE = 5
comptime _E_ATTR = 6
comptime _E_CALL = 7
comptime _E_BIN = 8
comptime _E_UNARY = 9
comptime _E_SUB = 10
comptime _E_BOOL_OP = 11
comptime _E_TUPLE = 12
comptime _E_LIST = 13
comptime _E_KW = 14
comptime _E_CMP = 15
comptime _E_FUNC = 16
comptime _E_ARGS = 17
comptime _E_ARG = 18
comptime _E_ASSIGN = 19
comptime _E_AUG = 20
comptime _E_WHILE = 21
comptime _E_RETURN = 22
comptime _E_IF = 23
comptime _E_FOR = 24
comptime _E_EXPR = 25
comptime _E_RAISE = 26
comptime _E_STR = 27
comptime _E_IFEXP = 28
comptime _E_ANN = 29
comptime _E_SIMPLE = 30

comptime _P_TEST = 4
comptime _P_OR = 5
comptime _P_AND = 6
comptime _P_NOT = 7
comptime _P_CMP = 8
comptime _P_ARITH = 13
comptime _P_TERM = 14
comptime _P_FACTOR = 15
comptime _P_POWER = 16
comptime _P_ATOM = 18


struct _Parser:
    """One token stream and the expression nodes parsed from it."""

    var kinds: List[Int]
    var texts: List[String]
    var index: Int
    var kind: List[Int]
    var label: List[String]
    var left: List[Int]
    var right: List[Int]
    var at: List[Int]
    var narg: List[Int]
    var nkw: List[Int]
    var mark: List[Int]
    var span: List[Int]
    var extra: List[Int]
    var assign_name: List[String]
    var assign_node: List[Int]

    def __init__(out self, var kinds: List[Int], var texts: List[String]):
        self.kinds = kinds^
        self.texts = texts^
        self.index = 0
        self.kind = List[Int]()
        self.label = List[String]()
        self.left = List[Int]()
        self.right = List[Int]()
        self.at = List[Int]()
        self.narg = List[Int]()
        self.nkw = List[Int]()
        self.mark = List[Int]()
        self.span = List[Int]()
        self.extra = List[Int]()
        self.assign_name = List[String]()
        self.assign_node = List[Int]()

    def _add(
        mut self,
        kind: Int,
        text: String,
        left: Int,
        right: Int,
        var extra: List[Int],
        narg: Int,
        nkw: Int,
        mark: Int = 0,
    ) -> Int:
        var count = len(extra)
        self.kind.append(kind)
        self.label.append(text)
        self.left.append(left)
        self.right.append(right)
        self.at.append(len(self.extra))
        self.narg.append(narg)
        self.nkw.append(nkw)
        self.mark.append(mark)
        self.span.append(count)
        var cursor = 0
        while cursor < count:
            self.extra.append(extra[cursor])
            cursor += 1
        return len(self.kind) - 1

    def _empty(mut self) -> List[Int]:
        return List[Int]()

    def _done(self) -> Bool:
        return self.index >= len(self.kinds)

    def _kind_at(self) -> Int:
        if self._done():
            return -1
        return self.kinds[self.index]

    def _text_at(self) -> String:
        if self._done():
            return ""
        return self.texts[self.index]

    def _is_name(self, word: String) -> Bool:
        return self._kind_at() == _NAME and self._text_at() == word

    def _is_op(self, word: String) -> Bool:
        return self._kind_at() == _OP and self._text_at() == word

    def _next_op(self, word: String) -> Bool:
        var next = self.index + 1
        if next >= len(self.kinds):
            return False
        return self.kinds[next] == _OP and self.texts[next] == word

    def _fail(self) raises -> Int:
        raise Error("heading correspondence: unsupported expression")

    def _previous(self, index: Int) -> String:
        var cursor = index - 1
        while cursor >= 0:
            var kind = self.kinds[cursor]
            if kind != _NEWLINE and kind != _INDENT and kind != _DEDENT:
                return self.texts[cursor]
            cursor -= 1
        return ""

    def _parse_expr(mut self) raises -> Int:
        var body = self._parse_or()
        if not self._is_name("if"):
            return body
        self.index += 1
        var test = self._parse_or()
        if not self._is_name("else"):
            return self._fail()
        self.index += 1
        var orelse = self._parse_expr()
        var extra = self._empty()
        extra.append(orelse)
        return self._add(_E_IFEXP, "", test, body, extra^, 1, 0)

    def _parse_or(mut self) raises -> Int:
        var left = self._parse_and()
        if not self._is_name("or"):
            return left
        var values = self._empty()
        values.append(left)
        while self._is_name("or"):
            self.index += 1
            values.append(self._parse_and())
        var count = len(values)
        return self._add(_E_BOOL_OP, "Or", -1, -1, values^, count, 0)

    def _parse_and(mut self) raises -> Int:
        var left = self._parse_not()
        if not self._is_name("and"):
            return left
        var values = self._empty()
        values.append(left)
        while self._is_name("and"):
            self.index += 1
            values.append(self._parse_not())
        var count = len(values)
        return self._add(_E_BOOL_OP, "And", -1, -1, values^, count, 0)

    def _parse_not(mut self) raises -> Int:
        if self._is_name("not") and not self._next_is_name("in"):
            self.index += 1
            return self._add(
                _E_UNARY, "Not", self._parse_not(), -1, self._empty(), 0, 0
            )
        return self._parse_comparison()

    def _next_is_name(self, word: String) -> Bool:
        var next = self.index + 1
        if next >= len(self.kinds):
            return False
        return self.kinds[next] == _NAME and self.texts[next] == word

    def _parse_comparison(mut self) raises -> Int:
        var left = self._parse_bor()
        var ops = String("")
        var comps = self._empty()
        var count = 0
        while True:
            var op = self._comparison_op()
            if op == "":
                break
            if count > 0:
                ops += "\n"
            ops += op
            comps.append(self._parse_bor())
            count += 1
        if count == 0:
            return left
        return self._add(_E_CMP, ops, left, -1, comps^, count, 0)

    def _comparison_op(mut self) -> String:
        if self._is_op("=="):
            self.index += 1
            return "Eq"
        if self._is_op("!="):
            self.index += 1
            return "NotEq"
        if self._is_op("<="):
            self.index += 1
            return "LtE"
        if self._is_op(">="):
            self.index += 1
            return "GtE"
        if self._is_op("<"):
            self.index += 1
            return "Lt"
        if self._is_op(">"):
            self.index += 1
            return "Gt"
        if self._is_name("in"):
            self.index += 1
            return "In"
        if self._is_name("not") and self._next_is_name("in"):
            self.index += 2
            return "NotIn"
        if self._is_name("is"):
            self.index += 1
            if self._is_name("not"):
                self.index += 1
                return "IsNot"
            return "Is"
        return ""

    def _parse_bor(mut self) raises -> Int:
        var left = self._parse_bxor()
        while self._is_op("|"):
            self.index += 1
            left = self._add(
                _E_BIN, "BitOr", left, self._parse_bxor(), self._empty(), 0, 0
            )
        return left

    def _parse_bxor(mut self) raises -> Int:
        var left = self._parse_band()
        while self._is_op("^"):
            self.index += 1
            left = self._add(
                _E_BIN, "BitXor", left, self._parse_band(), self._empty(), 0, 0
            )
        return left

    def _parse_band(mut self) raises -> Int:
        var left = self._parse_shift()
        while self._is_op("&"):
            self.index += 1
            left = self._add(
                _E_BIN,
                "BitAnd",
                left,
                self._parse_shift(),
                self._empty(),
                0,
                0,
            )
        return left

    def _parse_shift(mut self) raises -> Int:
        var left = self._parse_arith()
        while self._is_op("<<") or self._is_op(">>"):
            var name = "LShift" if self._is_op("<<") else "RShift"
            self.index += 1
            left = self._add(
                _E_BIN, name, left, self._parse_arith(), self._empty(), 0, 0
            )
        return left

    def _parse_arith(mut self) raises -> Int:
        var left = self._parse_term()
        while self._is_op("+") or self._is_op("-"):
            var name = "Add" if self._is_op("+") else "Sub"
            self.index += 1
            left = self._add(
                _E_BIN, name, left, self._parse_term(), self._empty(), 0, 0
            )
        return left

    def _parse_term(mut self) raises -> Int:
        var left = self._parse_factor()
        while (
            self._is_op("*")
            or self._is_op("/")
            or self._is_op("//")
            or self._is_op("%")
        ):
            var name = String("Mult")
            if self._is_op("/"):
                name = "Div"
            elif self._is_op("//"):
                name = "FloorDiv"
            elif self._is_op("%"):
                name = "Mod"
            self.index += 1
            left = self._add(
                _E_BIN, name, left, self._parse_factor(), self._empty(), 0, 0
            )
        return left

    def _parse_factor(mut self) raises -> Int:
        if self._is_op("+") or self._is_op("-") or self._is_op("~"):
            var name = String("UAdd")
            if self._is_op("-"):
                name = "USub"
            elif self._is_op("~"):
                name = "Invert"
            self.index += 1
            return self._add(
                _E_UNARY, name, self._parse_factor(), -1, self._empty(), 0, 0
            )
        return self._parse_power()

    def _parse_power(mut self) raises -> Int:
        var left = self._parse_primary()
        if self._is_op("**"):
            self.index += 1
            return self._add(
                _E_BIN, "Pow", left, self._parse_factor(), self._empty(), 0, 0
            )
        return left

    def _parse_primary(mut self) raises -> Int:
        var node = self._parse_atom()
        while True:
            if self._is_op("("):
                node = self._parse_call(node)
            elif self._is_op("["):
                node = self._parse_subscript(node)
            elif self._is_op("."):
                self.index += 1
                if self._kind_at() != _NAME:
                    return self._fail()
                var attr = self._text_at()
                self.index += 1
                node = self._add(_E_ATTR, attr, node, -1, self._empty(), 0, 0)
            else:
                return node

    def _parse_atom(mut self) raises -> Int:
        if self._kind_at() == _NAME:
            var word = self._text_at()
            self.index += 1
            if word == "True":
                return self._add(_E_BOOL, "true", -1, -1, self._empty(), 0, 0)
            if word == "False":
                return self._add(_E_BOOL, "false", -1, -1, self._empty(), 0, 0)
            if word == "None":
                return self._add(_E_NONE, "", -1, -1, self._empty(), 0, 0)
            return self._add(_E_NAME, word, -1, -1, self._empty(), 0, 0)
        if self._kind_at() == _NUMBER:
            var token = self._text_at()
            self.index += 1
            return self._number(token)
        if self._kind_at() == _STRING:
            var token = self._text_at()
            self.index += 1
            return self._add(
                _E_STR, self._unquote(token), -1, -1, self._empty(), 0, 0
            )
        if self._is_op("("):
            return self._parse_paren()
        if self._is_op("["):
            return self._parse_list()
        return self._fail()

    def _number(mut self, token: String) raises -> Int:
        var data = token.as_bytes()
        var floats = False
        var cursor = 0
        while cursor < len(data):
            var byte = data[cursor]
            if byte == 46 or byte == 101 or byte == 69:
                floats = True
            cursor += 1
        if floats:
            _ = parse_float(token)
            return self._add(_E_FLOAT, token, -1, -1, self._empty(), 0, 0)
        return self._add(_E_INT, token, -1, -1, self._empty(), 0, 0)

    def _parse_paren(mut self) raises -> Int:
        self.index += 1
        if self._is_op(")"):
            self.index += 1
            return self._add(_E_TUPLE, "", -1, -1, self._empty(), 0, 0)
        var first = self._parse_expr()
        if self._is_op(","):
            var elts = self._empty()
            elts.append(first)
            while self._is_op(","):
                self.index += 1
                if self._is_op(")"):
                    break
                elts.append(self._parse_expr())
            if not self._is_op(")"):
                return self._fail()
            self.index += 1
            var count = len(elts)
            return self._add(_E_TUPLE, "", -1, -1, elts^, count, 0)
        if not self._is_op(")"):
            return self._fail()
        self.index += 1
        return first

    def _parse_list(mut self) raises -> Int:
        self.index += 1
        var elts = self._empty()
        if not self._is_op("]"):
            while True:
                elts.append(self._parse_expr())
                if self._is_op(","):
                    self.index += 1
                    if self._is_op("]"):
                        break
                    continue
                break
        if not self._is_op("]"):
            return self._fail()
        self.index += 1
        var count = len(elts)
        return self._add(_E_LIST, "", -1, -1, elts^, count, 0)

    def _parse_call(mut self, func: Int) raises -> Int:
        self.index += 1
        var args = self._empty()
        var kws = self._empty()
        if not self._is_op(")"):
            while True:
                if self._kind_at() == _NAME and self._next_op("="):
                    var arg = self._text_at()
                    self.index += 2
                    var value = self._parse_expr()
                    kws.append(
                        self._add(_E_KW, arg, value, -1, self._empty(), 0, 0)
                    )
                else:
                    if len(kws) > 0:
                        return self._fail()
                    args.append(self._parse_expr())
                if self._is_op(","):
                    self.index += 1
                    if self._is_op(")"):
                        break
                    continue
                break
        if not self._is_op(")"):
            return self._fail()
        self.index += 1
        var extra = self._empty()
        var cursor = 0
        while cursor < len(args):
            extra.append(args[cursor])
            cursor += 1
        cursor = 0
        while cursor < len(kws):
            extra.append(kws[cursor])
            cursor += 1
        var narg = len(args)
        var nkw = len(kws)
        return self._add(_E_CALL, "", func, -1, extra^, narg, nkw)

    def _parse_subscript(mut self, value: Int) raises -> Int:
        self.index += 1
        var first = self._parse_expr()
        if self._is_op(","):
            var elts = self._empty()
            elts.append(first)
            while self._is_op(","):
                self.index += 1
                if self._is_op("]"):
                    break
                elts.append(self._parse_expr())
            var count = len(elts)
            first = self._add(_E_TUPLE, "", -1, -1, elts^, count, 0)
        if not self._is_op("]"):
            return self._fail()
        self.index += 1
        return self._add(_E_SUB, "", value, first, self._empty(), 0, 0)

    def _parse_parameters(mut self) raises -> Int:
        self.index += 1
        var args = self._empty()
        if not self._is_op(")"):
            while True:
                if self._kind_at() != _NAME:
                    return self._fail()
                var name = self._text_at()
                self.index += 1
                var annotation = -1
                if self._is_op(":"):
                    self.index += 1
                    annotation = self._parse_expr()
                if self._is_op("="):
                    return self._fail()
                args.append(
                    self._add(_E_ARG, name, annotation, -1, self._empty(), 0, 0)
                )
                if self._is_op(","):
                    self.index += 1
                    if self._is_op(")"):
                        break
                    continue
                break
        if not self._is_op(")"):
            return self._fail()
        self.index += 1
        var count = len(args)
        return self._add(_E_ARGS, "", -1, -1, args^, count, 0)

    def _parse_statement(mut self) raises -> Int:
        if (
            self._is_name("continue")
            or self._is_name("break")
            or self._is_name("pass")
        ):
            var word = self._text_at()
            self.index += 1
            var label = String("Continue")
            if word == "break":
                label = "Break"
            elif word == "pass":
                label = "Pass"
            return self._add(_E_SIMPLE, label, -1, -1, self._empty(), 0, 0)
        if self._is_name("while"):
            self.index += 1
            var test = self._parse_expr()
            if not self._is_op(":"):
                return self._fail()
            self.index += 1
            if self._kind_at() != _NEWLINE:
                return self._fail()
            self.index += 1
            var body = self._parse_body()
            var count = len(body)
            return self._add(_E_WHILE, "", test, -1, body^, count, 0)
        if self._is_name("return"):
            self.index += 1
            var value = -1
            if (
                not self._done()
                and self._kind_at() != _NEWLINE
                and self._kind_at() != _DEDENT
            ):
                value = self._parse_expr()
            return self._add(_E_RETURN, "", value, -1, self._empty(), 0, 0)
        if self._kind_at() == _NAME and self._next_op(":"):
            var name = self._text_at()
            self.index += 2
            var annotation = self._parse_expr()
            var value = -1
            if self._is_op("="):
                self.index += 1
                value = self._parse_expr()
            var target = self._add(_E_NAME, name, 1, -1, self._empty(), 0, 0)
            var extra = self._empty()
            var present = 0
            if value >= 0:
                extra.append(value)
                present = 1
            return self._add(
                _E_ANN, "", target, annotation, extra^, 0, 0, present
            )
        if self._kind_at() == _NAME:
            var saved = self.index
            var target = self._parse_primary()
            if self._is_op("=") or self._is_op("+="):
                var aug = self._is_op("+=")
                self._mark_store(target)
                self.index += 1
                var value = self._parse_expr()
                if aug:
                    return self._add(
                        _E_AUG, "Add", target, value, self._empty(), 0, 0
                    )
                return self._add(
                    _E_ASSIGN, "", target, value, self._empty(), 0, 0
                )
            self.index = saved
        if self._is_name("if") or self._is_name("elif"):
            return self._parse_if()
        if self._is_name("for"):
            return self._parse_for()
        if self._is_name("raise"):
            self.index += 1
            var exc = self._parse_expr()
            return self._add(_E_RAISE, "", exc, -1, self._empty(), 0, 0)
        var value = self._parse_expr()
        return self._add(_E_EXPR, "", value, -1, self._empty(), 0, 0)

    def _mark_store(mut self, node: Int):
        if self.kind[node] == _E_NAME:
            self.left[node] = 1
        elif self.kind[node] == _E_ATTR or self.kind[node] == _E_SUB:
            self.nkw[node] = 1

    def _unquote(self, token: String) -> String:
        var data = token.as_bytes()
        if len(data) < 2:
            return token
        var quote = data[0]
        var end = len(data)
        var out = String("")
        var cursor = 1
        while cursor < end - 1:
            var byte = data[cursor]
            if byte == 92 and cursor + 1 < end - 1:
                var escaped = data[cursor + 1]
                if escaped == 110:
                    out += "\n"
                elif escaped == 116:
                    out += "\t"
                elif escaped == 114:
                    out += "\r"
                else:
                    out += chr(Int(escaped))
                cursor += 2
                continue
            out += chr(Int(byte))
            cursor += 1
        _ = quote
        return out

    def _parse_suite(mut self) raises -> List[Int]:
        if not self._is_op(":"):
            raise Error("heading correspondence: unsupported expression")
        self.index += 1
        if self._kind_at() != _NEWLINE:
            raise Error("heading correspondence: unsupported expression")
        self.index += 1
        return self._parse_body()

    def _parse_if(mut self) raises -> Int:
        self.index += 1
        var test = self._parse_expr()
        var body = self._parse_suite()
        var orelse = self._empty()
        if self._is_name("else"):
            self.index += 1
            orelse = self._parse_suite()
        elif self._is_name("elif"):
            orelse.append(self._parse_if())
        var extra = self._empty()
        var body_count = len(body)
        var cursor = 0
        while cursor < body_count:
            extra.append(body[cursor])
            cursor += 1
        var else_count = len(orelse)
        cursor = 0
        while cursor < else_count:
            extra.append(orelse[cursor])
            cursor += 1
        return self._add(_E_IF, "", test, -1, extra^, body_count, 0, else_count)

    def _parse_for(mut self) raises -> Int:
        self.index += 1
        if self._kind_at() != _NAME:
            return self._fail()
        var name = self._text_at()
        self.index += 1
        if not self._is_name("in"):
            return self._fail()
        self.index += 1
        var iter = self._parse_expr()
        var target = self._add(_E_NAME, name, 1, -1, self._empty(), 0, 0)
        var body = self._parse_suite()
        var count = len(body)
        return self._add(_E_FOR, "", target, iter, body^, count, 0)

    def _parse_body(mut self) raises -> List[Int]:
        if self._kind_at() != _INDENT:
            raise Error("heading correspondence: unsupported expression")
        self.index += 1
        var stmts = self._empty()
        while not self._done() and self._kind_at() != _DEDENT:
            if self._kind_at() == _NEWLINE:
                self.index += 1
                continue
            stmts.append(self._parse_statement())
            if self._kind_at() == _NEWLINE:
                self.index += 1
        if self._kind_at() == _DEDENT:
            self.index += 1
        return stmts^

    def _parse_statements(mut self) raises -> List[Int]:
        var stmts = self._empty()
        while not self._done():
            var kind = self._kind_at()
            if kind == _NEWLINE or kind == _INDENT or kind == _DEDENT:
                self.index += 1
                continue
            stmts.append(self._parse_statement())
            if self._kind_at() == _NEWLINE:
                self.index += 1
        return stmts^

    def _parse_function(mut self, typed: Bool) raises -> Int:
        while self._kind_at() == _NEWLINE:
            self.index += 1
        var decorators = self._empty()
        while self._is_op("@"):
            self.index += 1
            decorators.append(self._parse_expr())
            if self._kind_at() == _NEWLINE:
                self.index += 1
        if not self._is_name("def"):
            return self._fail()
        self.index += 1
        if self._kind_at() != _NAME:
            return self._fail()
        var name = self._text_at()
        self.index += 1
        if not self._is_op("("):
            return self._fail()
        var args = self._parse_parameters()
        var returns = -1
        if self._is_op("->"):
            self.index += 1
            returns = self._parse_expr()
        if not self._is_op(":"):
            return self._fail()
        self.index += 1
        if self._kind_at() != _NEWLINE:
            return self._fail()
        self.index += 1
        var body = self._parse_body()
        var count = len(body)
        var extra = self._empty()
        var cursor = 0
        while cursor < count:
            extra.append(body[cursor])
            cursor += 1
        var decorators_count = len(decorators)
        cursor = 0
        while cursor < decorators_count:
            extra.append(decorators[cursor])
            cursor += 1
        var flag = 0
        if typed:
            flag = 1
        return self._add(
            _E_FUNC, name, args, returns, extra^, count, flag, decorators_count
        )

    def _skip_statement(mut self):
        var depth = 0
        while not self._done():
            var kind = self._kind_at()
            var text = self._text_at()
            if kind == _OP and (text == "(" or text == "[" or text == "{"):
                depth += 1
            elif kind == _OP and (text == ")" or text == "]" or text == "}"):
                if depth > 0:
                    depth -= 1
            elif kind == _NEWLINE and depth == 0:
                return
            elif (kind == _INDENT or kind == _DEDENT) and depth == 0:
                return
            self.index += 1

    def _collect(mut self) raises:
        var indent = 0
        while not self._done():
            var kind = self._kind_at()
            if kind == _INDENT:
                indent += 1
                self.index += 1
                continue
            if kind == _DEDENT:
                indent -= 1
                self.index += 1
                continue
            if kind == _NEWLINE:
                self.index += 1
                continue
            if indent == 1 and kind == _NAME and self._next_op("="):
                var name = self._text_at()
                self.index += 2
                var value = self._parse_expr()
                self.assign_name.append(name)
                self.assign_node.append(value)
                continue
            var mark = self.index
            self._skip_statement()
            if self.index == mark:
                self.index += 1

    def _one(self, name: String) raises -> Int:
        var found = -1
        var hits = 0
        var index = 0
        while index < len(self.assign_name):
            if self.assign_name[index] == name:
                hits += 1
                found = self.assign_node[index]
            index += 1
        if hits != 1:
            raise Error(
                "heading correspondence: missing/ambiguous assignment " + name
            )
        return found

    def _clone(mut self, node: Int) -> Int:
        var narg = self.narg[node]
        var nkw = self.nkw[node]
        var mark = self.mark[node]
        var span = self.span[node]
        var start = self.at[node]
        var left = -1
        var right = -1
        if self.left[node] >= 0:
            left = self._clone(self.left[node])
        if self.right[node] >= 0:
            right = self._clone(self.right[node])
        var extra = self._empty()
        var cursor = 0
        while cursor < span:
            extra.append(self._clone(self.extra[start + cursor]))
            cursor += 1
        var text = String(self.label[node])
        var kind = self.kind[node]
        return self._add(kind, text, left, right, extra^, narg, nkw, mark)

    def _spec(mut self, node: Int, k0: Int, use_k0: Bool) -> Int:
        if self.kind[node] == _E_NAME:
            if self.label[node] == "Expression":
                return self._add(_E_NAME, "_Jet", -1, -1, self._empty(), 0, 0)
            if use_k0 and self.label[node] == "k0":
                return self._clone(k0)
            return self._clone(node)
        var narg = self.narg[node]
        var nkw = self.nkw[node]
        var mark = self.mark[node]
        var span = self.span[node]
        var start = self.at[node]
        var left = -1
        var right = -1
        if self.left[node] >= 0:
            left = self._spec(self.left[node], k0, use_k0)
        if self.right[node] >= 0:
            right = self._spec(self.right[node], k0, use_k0)
        var extra = self._empty()
        var cursor = 0
        while cursor < span:
            extra.append(self._spec(self.extra[start + cursor], k0, use_k0))
            cursor += 1
        var text = String(self.label[node])
        var kind = self.kind[node]
        return self._add(kind, text, left, right, extra^, narg, nkw, mark)

    def _bin_symbol(self, op: String) -> String:
        if op == "Add":
            return "+"
        if op == "Sub":
            return "-"
        if op == "Mult":
            return "*"
        if op == "Div":
            return "/"
        if op == "FloorDiv":
            return "//"
        if op == "Mod":
            return "%"
        if op == "Pow":
            return "**"
        return op

    def _bin_precedence(self, symbol: String) -> Int:
        if symbol == "+" or symbol == "-":
            return _P_ARITH
        if symbol == "*" or symbol == "/" or symbol == "//" or symbol == "%":
            return _P_TERM
        if symbol == "**":
            return _P_POWER
        return _P_ARITH

    def _cmp_symbol(self, op: String) -> String:
        if op == "Eq":
            return "=="
        if op == "NotEq":
            return "!="
        if op == "Lt":
            return "<"
        if op == "LtE":
            return "<="
        if op == "Gt":
            return ">"
        if op == "GtE":
            return ">="
        if op == "Is":
            return "is"
        if op == "IsNot":
            return "is not"
        if op == "In":
            return "in"
        if op == "NotIn":
            return "not in"
        return op

    def _unparse(mut self, node: Int, limit: Int) raises -> String:
        var kind = self.kind[node]
        if kind == _E_NAME or kind == _E_INT or kind == _E_FLOAT:
            return String(self.label[node])
        if kind == _E_BOOL:
            if self.label[node] == "true":
                return "True"
            return "False"
        if kind == _E_NONE:
            return "None"
        if kind == _E_ATTR:
            var name = String(self.label[node])
            var value_node = self.left[node]
            var numeric = self.kind[value_node] == _E_INT
            var text = self._unparse(value_node, _P_ATOM)
            if numeric:
                text += " "
            text += "."
            text += name
            return text
        if kind == _E_SUB:
            var value_node = self.left[node]
            var slice_node = self.right[node]
            return (
                self._unparse(value_node, _P_ATOM)
                + "["
                + self._unparse(slice_node, _P_TEST)
                + "]"
            )
        if kind == _E_CALL:
            var func_node = self.left[node]
            var text = self._unparse(func_node, _P_ATOM) + "("
            var start = self.at[node]
            var narg = self.narg[node]
            var nkw = self.nkw[node]
            var cursor = 0
            while cursor < narg:
                if cursor > 0:
                    text += ", "
                text += self._unparse(self.extra[start + cursor], _P_TEST)
                cursor += 1
            var kw = 0
            while kw < nkw:
                if narg + kw > 0:
                    text += ", "
                var item = self.extra[start + narg + kw]
                var arg_name = String(self.label[item])
                var value_node = self.left[item]
                text += arg_name
                text += "="
                text += self._unparse(value_node, _P_TEST)
                kw += 1
            text += ")"
            return text
        if kind == _E_UNARY:
            var op = String(self.label[node])
            var own = _P_NOT
            var spelling = String("not ")
            if op == "USub":
                own = _P_FACTOR
                spelling = "-"
            elif op == "UAdd":
                own = _P_FACTOR
                spelling = "+"
            elif op == "Invert":
                own = _P_FACTOR
                spelling = "~"
            var operand = self.left[node]
            var text = spelling + self._unparse(operand, own)
            if limit > own:
                return "(" + text + ")"
            return text
        if kind == _E_BIN:
            var op = String(self.label[node])
            var symbol = self._bin_symbol(op)
            var own = self._bin_precedence(symbol)
            var left_limit = own
            var right_limit = own + 1
            if symbol == "**":
                left_limit = own + 1
                right_limit = own
            var left_node = self.left[node]
            var right_node = self.right[node]
            var text = (
                self._unparse(left_node, left_limit)
                + " "
                + symbol
                + " "
                + self._unparse(right_node, right_limit)
            )
            if limit > own:
                return "(" + text + ")"
            return text
        if kind == _E_BOOL_OP:
            var op = String(self.label[node])
            var own = _P_AND
            var symbol = String("and")
            if op == "Or":
                own = _P_OR
                symbol = "or"
            var assigned = own
            var text = String("")
            var start = self.at[node]
            var count = self.narg[node]
            var cursor = 0
            while cursor < count:
                assigned += 1
                var piece = self._unparse(self.extra[start + cursor], assigned)
                if cursor > 0:
                    text += " " + symbol + " "
                text += piece
                cursor += 1
            if limit > own:
                return "(" + text + ")"
            return text
        if kind == _E_CMP:
            var ops = String(self.label[node])
            var op_words = List[String]()
            var data = ops.as_bytes()
            var size = len(data)
            var op_at = 0
            while op_at < size:
                var word = String("")
                while op_at < size and data[op_at] != 10:
                    word += chr(Int(data[op_at]))
                    op_at += 1
                op_words.append(word^)
                if op_at < size:
                    op_at += 1
            var left_node = self.left[node]
            var text = self._unparse(left_node, _P_CMP + 1)
            var start = self.at[node]
            var count = self.narg[node]
            var cursor = 0
            while cursor < count:
                var symbol = String("==")
                if cursor < len(op_words):
                    symbol = self._cmp_symbol(op_words[cursor])
                text += " " + symbol + " "
                text += self._unparse(self.extra[start + cursor], _P_CMP + 1)
                cursor += 1
            if limit > _P_CMP:
                return "(" + text + ")"
            return text
        raise Error("sampled body role: unsupported expression")

    def _role(mut self, node: Int) raises -> String:
        var kind = self.kind[node]
        if kind == _E_ASSIGN:
            return "assign:" + self._unparse(self.left[node], _P_TEST)
        if kind == _E_ANN:
            return "annotate:" + self._unparse(self.left[node], _P_TEST)
        if kind == _E_IF:
            return "if:" + self._unparse(self.left[node], _P_TEST)
        if kind == _E_RETURN:
            return "return"
        if kind == _E_AUG:
            return "AugAssign"
        if kind == _E_WHILE:
            return "While"
        if kind == _E_FOR:
            return "For"
        if kind == _E_EXPR:
            return "Expr"
        if kind == _E_RAISE:
            return "Raise"
        if kind == _E_SIMPLE:
            return String(self.label[node])
        raise Error("sampled body role: unsupported statement")

    def _dump(mut self, node: Int) raises -> String:
        var doc = PyJson()
        doc.root = self._json(doc, node)
        return doc.dumps()

    def _json(mut self, mut doc: PyJson, node: Int) raises -> Int:
        var kind = self.kind[node]
        if kind == _E_NAME:
            return self._typed(doc, "Name", self._name_fields(doc, node))
        if kind == _E_INT:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "value", doc.new_int(Int(self.label[node]))),
            )
            return self._typed(doc, "Constant", fields)
        if kind == _E_FLOAT:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(
                    doc, "value", doc.new_float(parse_float(self.label[node]))
                ),
            )
            return self._typed(doc, "Constant", fields)
        if kind == _E_BOOL:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(
                    doc, "value", doc.new_bool(self.label[node] == "true")
                ),
            )
            return self._typed(doc, "Constant", fields)
        if kind == _E_NONE:
            return self._typed(doc, "Constant", doc.new_list())
        if kind == _E_STR:
            var fields = doc.new_list()
            doc.append(
                fields, self._pair(doc, "value", doc.new_str(self.label[node]))
            )
            return self._typed(doc, "Constant", fields)
        if kind == _E_EXPR:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "value", self._json(doc, self.left[node])),
            )
            return self._typed(doc, "Expr", fields)
        if kind == _E_RAISE:
            var fields = doc.new_list()
            doc.append(
                fields, self._pair(doc, "exc", self._json(doc, self.left[node]))
            )
            return self._typed(doc, "Raise", fields)
        if kind == _E_ATTR:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "value", self._json(doc, self.left[node])),
            )
            doc.append(
                fields, self._pair(doc, "attr", doc.new_str(self.label[node]))
            )
            var ctx = self._load(doc)
            if self.nkw[node] == 1:
                ctx = self._bare(doc, "Store")
            doc.append(fields, self._pair(doc, "ctx", ctx))
            return self._typed(doc, "Attribute", fields)
        if kind == _E_CALL:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "func", self._json(doc, self.left[node])),
            )
            doc.append(
                fields, self._pair(doc, "args", self._arg_list(doc, node))
            )
            doc.append(
                fields, self._pair(doc, "keywords", self._kw_list(doc, node))
            )
            return self._typed(doc, "Call", fields)
        if kind == _E_BIN:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "left", self._json(doc, self.left[node])),
            )
            doc.append(
                fields, self._pair(doc, "op", self._bare(doc, self.label[node]))
            )
            doc.append(
                fields,
                self._pair(doc, "right", self._json(doc, self.right[node])),
            )
            return self._typed(doc, "BinOp", fields)
        if kind == _E_UNARY:
            var fields = doc.new_list()
            doc.append(
                fields, self._pair(doc, "op", self._bare(doc, self.label[node]))
            )
            doc.append(
                fields,
                self._pair(doc, "operand", self._json(doc, self.left[node])),
            )
            return self._typed(doc, "UnaryOp", fields)
        if kind == _E_SUB:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "value", self._json(doc, self.left[node])),
            )
            doc.append(
                fields,
                self._pair(doc, "slice", self._json(doc, self.right[node])),
            )
            var ctx = self._load(doc)
            if self.nkw[node] == 1:
                ctx = self._bare(doc, "Store")
            doc.append(fields, self._pair(doc, "ctx", ctx))
            return self._typed(doc, "Subscript", fields)
        if kind == _E_BOOL_OP:
            var fields = doc.new_list()
            doc.append(
                fields, self._pair(doc, "op", self._bare(doc, self.label[node]))
            )
            doc.append(
                fields, self._pair(doc, "values", self._arg_list(doc, node))
            )
            return self._typed(doc, "BoolOp", fields)
        if kind == _E_TUPLE or kind == _E_LIST:
            var fields = doc.new_list()
            doc.append(
                fields, self._pair(doc, "elts", self._arg_list(doc, node))
            )
            doc.append(fields, self._pair(doc, "ctx", self._load(doc)))
            var name = "Tuple" if kind == _E_TUPLE else "List"
            return self._typed(doc, name, fields)
        if kind == _E_KW:
            var fields = doc.new_list()
            doc.append(
                fields, self._pair(doc, "arg", doc.new_str(self.label[node]))
            )
            doc.append(
                fields,
                self._pair(doc, "value", self._json(doc, self.left[node])),
            )
            return self._typed(doc, "keyword", fields)
        if kind == _E_FUNC:
            var fields = doc.new_list()
            doc.append(
                fields, self._pair(doc, "name", doc.new_str(self.label[node]))
            )
            doc.append(
                fields,
                self._pair(doc, "args", self._json(doc, self.left[node])),
            )
            doc.append(
                fields, self._pair(doc, "body", self._arg_list(doc, node))
            )
            doc.append(
                fields,
                self._pair(
                    doc,
                    "decorator_list",
                    self._slice_list(
                        doc, node, self.narg[node], self.mark[node]
                    ),
                ),
            )
            if self.right[node] >= 0:
                doc.append(
                    fields,
                    self._pair(
                        doc, "returns", self._json(doc, self.right[node])
                    ),
                )
            if self.nkw[node] == 1:
                doc.append(
                    fields,
                    self._pair(
                        doc, "mojo_type_parameters", self._type_params(doc)
                    ),
                )
            return self._typed(doc, "FunctionDef", fields)
        if kind == _E_IF:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "test", self._json(doc, self.left[node])),
            )
            doc.append(
                fields, self._pair(doc, "body", self._arg_list(doc, node))
            )
            doc.append(
                fields,
                self._pair(
                    doc,
                    "orelse",
                    self._slice_list(
                        doc, node, self.narg[node], self.mark[node]
                    ),
                ),
            )
            return self._typed(doc, "If", fields)
        if kind == _E_FOR:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "target", self._json(doc, self.left[node])),
            )
            doc.append(
                fields,
                self._pair(doc, "iter", self._json(doc, self.right[node])),
            )
            doc.append(
                fields, self._pair(doc, "body", self._arg_list(doc, node))
            )
            doc.append(fields, self._pair(doc, "orelse", doc.new_list()))
            return self._typed(doc, "For", fields)
        if kind == _E_ARGS:
            var fields = doc.new_list()
            doc.append(fields, self._pair(doc, "posonlyargs", doc.new_list()))
            doc.append(
                fields, self._pair(doc, "args", self._arg_list(doc, node))
            )
            doc.append(fields, self._pair(doc, "kwonlyargs", doc.new_list()))
            doc.append(fields, self._pair(doc, "kw_defaults", doc.new_list()))
            doc.append(fields, self._pair(doc, "defaults", doc.new_list()))
            return self._typed(doc, "arguments", fields)
        if kind == _E_ARG:
            var fields = doc.new_list()
            doc.append(
                fields, self._pair(doc, "arg", doc.new_str(self.label[node]))
            )
            if self.left[node] >= 0:
                doc.append(
                    fields,
                    self._pair(
                        doc, "annotation", self._json(doc, self.left[node])
                    ),
                )
            return self._typed(doc, "arg", fields)
        if kind == _E_IFEXP:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "test", self._json(doc, self.left[node])),
            )
            doc.append(
                fields,
                self._pair(doc, "body", self._json(doc, self.right[node])),
            )
            doc.append(
                fields,
                self._pair(
                    doc, "orelse", self._json(doc, self.extra[self.at[node]])
                ),
            )
            return self._typed(doc, "IfExp", fields)
        if kind == _E_ANN:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "target", self._json(doc, self.left[node])),
            )
            doc.append(
                fields,
                self._pair(
                    doc, "annotation", self._json(doc, self.right[node])
                ),
            )
            if self.mark[node] == 1:
                doc.append(
                    fields,
                    self._pair(
                        doc, "value", self._json(doc, self.extra[self.at[node]])
                    ),
                )
            doc.append(fields, self._pair(doc, "simple", doc.new_int(1)))
            return self._typed(doc, "AnnAssign", fields)
        if kind == _E_ASSIGN:
            var targets = doc.new_list()
            doc.append(targets, self._json(doc, self.left[node]))
            var fields = doc.new_list()
            doc.append(fields, self._pair(doc, "targets", targets))
            doc.append(
                fields,
                self._pair(doc, "value", self._json(doc, self.right[node])),
            )
            return self._typed(doc, "Assign", fields)
        if kind == _E_AUG:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "target", self._json(doc, self.left[node])),
            )
            doc.append(
                fields, self._pair(doc, "op", self._bare(doc, self.label[node]))
            )
            doc.append(
                fields,
                self._pair(doc, "value", self._json(doc, self.right[node])),
            )
            return self._typed(doc, "AugAssign", fields)
        if kind == _E_WHILE:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "test", self._json(doc, self.left[node])),
            )
            doc.append(
                fields, self._pair(doc, "body", self._arg_list(doc, node))
            )
            doc.append(fields, self._pair(doc, "orelse", doc.new_list()))
            return self._typed(doc, "While", fields)
        if kind == _E_RETURN:
            var fields = doc.new_list()
            if self.left[node] >= 0:
                doc.append(
                    fields,
                    self._pair(doc, "value", self._json(doc, self.left[node])),
                )
            return self._typed(doc, "Return", fields)
        if kind == _E_CMP:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "left", self._json(doc, self.left[node])),
            )
            doc.append(fields, self._pair(doc, "ops", self._cmp_ops(doc, node)))
            doc.append(
                fields,
                self._pair(doc, "comparators", self._arg_list(doc, node)),
            )
            return self._typed(doc, "Compare", fields)
        if kind == _E_SIMPLE:
            var label = String(self.label[node])
            return self._typed(doc, label, doc.new_list())
        return self._fail()

    def _name_fields(self, mut doc: PyJson, node: Int) -> Int:
        var fields = doc.new_list()
        doc.append(fields, self._pair(doc, "id", doc.new_str(self.label[node])))
        var ctx_name = "Load"
        if self.left[node] == 1:
            ctx_name = "Store"
        doc.append(fields, self._pair(doc, "ctx", self._bare(doc, ctx_name)))
        return fields

    def _typed(self, mut doc: PyJson, name: String, fields: Int) -> Int:
        var node = doc.new_list()
        doc.append(node, doc.new_str(name))
        doc.append(node, fields)
        return node

    def _pair(self, mut doc: PyJson, key: String, value: Int) -> Int:
        var pair = doc.new_list()
        doc.append(pair, doc.new_str(key))
        doc.append(pair, value)
        return pair

    def _load(self, mut doc: PyJson) -> Int:
        return self._bare(doc, "Load")

    def _type_param(self, mut doc: PyJson, kind: String, text: String) -> Int:
        var pair = doc.new_list()
        doc.append(pair, doc.new_str(kind))
        doc.append(pair, doc.new_str(text))
        return pair

    def _type_params(self, mut doc: PyJson) -> Int:
        var rows = doc.new_list()
        doc.append(rows, self._type_param(doc, "NAME", "derivatives"))
        doc.append(rows, self._type_param(doc, "OP", ":"))
        doc.append(rows, self._type_param(doc, "NAME", "Bool"))
        return rows

    def _bare(self, mut doc: PyJson, name: String) -> Int:
        var node = doc.new_list()
        doc.append(node, doc.new_str(name))
        doc.append(node, doc.new_list())
        return node

    def _arg_list(mut self, mut doc: PyJson, node: Int) raises -> Int:
        return self._slice_list(doc, node, 0, self.narg[node])

    def _slice_list(
        mut self, mut doc: PyJson, node: Int, offset: Int, count: Int
    ) raises -> Int:
        var rows = doc.new_list()
        var cursor = 0
        while cursor < count:
            doc.append(
                rows,
                self._json(doc, self.extra[self.at[node] + offset + cursor]),
            )
            cursor += 1
        return rows

    def _kw_list(mut self, mut doc: PyJson, node: Int) raises -> Int:
        var rows = doc.new_list()
        var cursor = 0
        while cursor < self.nkw[node]:
            doc.append(
                rows,
                self._json(
                    doc, self.extra[self.at[node] + self.narg[node] + cursor]
                ),
            )
            cursor += 1
        return rows

    def _cmp_ops(self, mut doc: PyJson, node: Int) -> Int:
        var rows = doc.new_list()
        var text = self.label[node]
        var data = text.as_bytes()
        var start = 0
        var cursor = 0
        while cursor <= len(data):
            var split = cursor == len(data) or data[cursor] == 10
            if split and cursor > start:
                var name = String("")
                var copy = start
                while copy < cursor:
                    name += chr(Int(data[copy]))
                    copy += 1
                doc.append(rows, self._bare(doc, name))
                start = cursor + 1
            cursor += 1
        return rows

    def _half_calls(mut self) raises -> List[String]:
        var dumps = List[String]()
        var cursor = 0
        while cursor < len(self.kinds):
            var text = self.texts[cursor]
            var kind = self.kinds[cursor]
            if kind == _NAME and text == "_stored_half":
                var prev = self._previous(cursor)
                var call = (
                    cursor + 1 < len(self.kinds)
                    and self.texts[cursor + 1] == "("
                )
                if call and prev != "." and prev != "def" and prev != "class":
                    self.index = cursor
                    dumps.append(self._dump(self._parse_primary()))
                    cursor = self.index
                    continue
            cursor += 1
        return dumps^

    def _half_names(self) -> Int:
        var hits = 0
        var cursor = 0
        var depth = 0
        while cursor < len(self.kinds):
            var text = self.texts[cursor]
            var kind = self.kinds[cursor]
            if kind == _OP and (text == "(" or text == "[" or text == "{"):
                depth += 1
            elif kind == _OP and (text == ")" or text == "]" or text == "}"):
                if depth > 0:
                    depth -= 1
            if kind == _NAME and text == "_stored_half":
                var prev = self._previous(cursor)
                var keyword = (
                    depth > 0
                    and cursor + 1 < len(self.kinds)
                    and self.texts[cursor + 1] == "="
                )
                if (
                    prev != "."
                    and prev != "def"
                    and prev != "class"
                    and not keyword
                ):
                    hits += 1
            cursor += 1
        return hits


def _parser(source: String) raises -> _Parser:
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    return _Parser(kinds^, texts^)


def expression_dump(source: String) raises -> String:
    """Return the normalized AST dump of one expression.

    Args:
        source: A Python expression.

    Returns:
        The dump, with the same fields CPython 3.12 keeps.

    Raises:
        Error: The expression is missing or uses an unsupported form.
    """
    var parser = _parser(source)
    var node = parser._parse_expr()
    while not parser._done():
        var kind = parser._kind_at()
        if kind != _NEWLINE and kind != _DEDENT and kind != _INDENT:
            raise Error("heading correspondence: unsupported expression")
        parser.index += 1
    return parser._dump(node)


def statement_dump(source: String) raises -> String:
    """Return the normalized dump of one statement.

    Args:
        source: A Python statement.

    Returns:
        The dump, with the same fields CPython 3.12 keeps.

    Raises:
        Error: The statement is missing or uses an unsupported form.
    """
    var parser = _parser(source)
    var node = parser._parse_statement()
    while not parser._done():
        var kind = parser._kind_at()
        if kind != _NEWLINE and kind != _DEDENT and kind != _INDENT:
            raise Error("heading correspondence: unsupported expression")
        parser.index += 1
    return parser._dump(node)


def body_role_json(source: String) raises -> String:
    """Return the JSON statement roles of one function body.

    Args:
        source: Mojo source for one function.

    Returns:
        A JSON list of `assign:`, `annotate:`, `if:`, and `return` roles.

    Raises:
        Error: The function is missing or uses an unsupported statement.
    """
    var rewritten = syntax_tree_source(source)
    var parser = _parser(rewritten)
    var node = parser._parse_function(False)
    while not parser._done():
        var kind = parser._kind_at()
        if kind != _NEWLINE and kind != _DEDENT and kind != _INDENT:
            raise Error("sampled body role: unsupported statement")
        parser.index += 1
    if parser.kind[node] != _E_FUNC:
        raise Error("sampled body role: unsupported statement")
    var doc = PyJson()
    var rows = doc.new_list()
    var count = parser.narg[node]
    var start = parser.at[node]
    var index = 0
    while index < count:
        var role = parser._role(parser.extra[start + index])
        doc.append(rows, doc.new_str(role))
        index += 1
    doc.root = rows
    return doc.dumps()


def function_dump(source: String) raises -> String:
    """Return the normalized dump of one function, including its generic mark.

    Args:
        source: A Python function.

    Returns:
        The dump, with the reviewed `derivatives: Bool` generic attached.

    Raises:
        Error: The function is missing or uses an unsupported statement.
    """
    var parser = _parser(source)
    var node = parser._parse_function(True)
    while not parser._done():
        var kind = parser._kind_at()
        if kind != _NEWLINE and kind != _DEDENT and kind != _INDENT:
            raise Error("heading correspondence: unsupported expression")
        parser.index += 1
    return parser._dump(node)


def plain_function_dump(source: String) raises -> String:
    """Return the normalized dump of one function without a generic mark.

    Args:
        source: A Python function.

    Returns:
        The dump CPython keeps when the function has no generic parameters.

    Raises:
        Error: The function is missing or uses an unsupported statement.
    """
    var parser = _parser(source)
    var node = parser._parse_function(False)
    while not parser._done():
        var kind = parser._kind_at()
        if kind != _NEWLINE and kind != _DEDENT and kind != _INDENT:
            raise Error("heading correspondence: unsupported expression")
        parser.index += 1
    return parser._dump(node)


def _index_of(haystack: String, needle: String) -> Int:
    var data = haystack.as_bytes()
    var wanted = needle.as_bytes()
    if len(wanted) == 0 or len(wanted) > len(data):
        return -1
    var index = 0
    while index + len(wanted) <= len(data):
        var cursor = 0
        var same = True
        while cursor < len(wanted):
            if data[index + cursor] != wanted[cursor]:
                same = False
                break
            cursor += 1
        if same:
            return index
        index += 1
    return -1


def _decorator_prefix(source: String, sliced: String) -> String:
    var origin = _index_of(source, sliced)
    if origin < 0:
        return sliced
    var data = source.as_bytes()
    var start = origin
    while start > 0 and data[start - 1] == 10:
        var line_end = start - 1
        var line_start = line_end
        while line_start > 0 and data[line_start - 1] != 10:
            line_start -= 1
        var cursor = line_start
        while cursor < line_end and (data[cursor] == 32 or data[cursor] == 9):
            cursor += 1
        if cursor >= line_end or data[cursor] != 64:
            break
        start = line_start
    if start == origin:
        return sliced
    var prefix = String("")
    var cursor = start
    while cursor < origin:
        prefix += chr(Int(data[cursor]))
        cursor += 1
    return prefix + sliced


def sum2_graph_dump(payload: String) raises -> String:
    """Return one Sum2 function dump from a JSON document.

    Args:
        payload: JSON with `source` and `name`.

    Returns:
        The normalized dump without a generic mark.

    Raises:
        Error: The function is missing or uses an unsupported statement.
    """
    var doc = PyJson.parse(payload)
    var source = doc.text(doc.at(doc.root, "source"))
    var name = doc.text(doc.at(doc.root, "name"))
    var syntax = python_syntax_json(
        _decorator_prefix(source, function_slice(source, name))
    )
    var parsed = PyJson.parse(syntax)
    return plain_function_dump(parsed.text(parsed.at(parsed.root, "source")))


def _forbid_attribute(
    function_doc: PyJson, fragment: String, label: String
) raises:
    var dot = -1
    var data = fragment.as_bytes()
    var index = 0
    while index < len(data):
        if data[index] == 46:
            dot = index
            break
        index += 1
    if dot <= 0 or dot + 1 >= len(data):
        raise Error("invalid checker fragment: " + label)
    var value = String("")
    var attr = String("")
    index = 0
    while index < dot:
        value += chr(Int(data[index]))
        index += 1
    index = dot + 1
    while index < len(data):
        attr += chr(Int(data[index]))
        index += 1
    if _has_attribute(function_doc, function_doc.root, value, attr):
        raise Error("optional runtime contract: " + label)


def _has_attribute(
    doc: PyJson, node: Int, value: String, attr: String
) raises -> Bool:
    if _node_type(doc, node) == "Attribute":
        var owner = _named_field(doc, node, "value")
        var name = _named_field(doc, node, "attr")
        if _node_type(doc, owner) == "Name":
            var ident = _named_field(doc, owner, "id")
            if doc.text(ident) == value and doc.text(name) == attr:
                return True
    if doc.kind(node) == PY_LIST:
        var index = 0
        while index < doc.length(node):
            if _has_attribute(doc, doc.item(node, index), value, attr):
                return True
            index += 1
    return False


def _check_setup(function_doc: PyJson, fragment: String, label: String) raises:
    var body = _named_field(function_doc, function_doc.root, "body")
    var loops = List[Int]()
    var index = 0
    while index < function_doc.length(body):
        if _node_type(function_doc, function_doc.item(body, index)) == "While":
            loops.append(function_doc.item(body, index))
        index += 1
    if len(loops) != 1:
        raise Error(
            "optional runtime contract: one original search frontier loop"
        )
    var statements = _named_field(function_doc, loops[0], "body")
    var test = PyJson.parse(expression_dump("not sampled_checked"))
    var choice = -1
    var hits = 0
    index = 0
    while index < function_doc.length(statements):
        var statement = function_doc.item(statements, index)
        if _node_type(function_doc, statement) == "If":
            var condition = _named_field(function_doc, statement, "test")
            if py_equal(function_doc, condition, test, test.root):
                hits += 1
                choice = index
        index += 1
    if hits != 1 or choice <= 0:
        raise Error(
            "optional runtime contract: dispatch setup remains deferred in the"
            " original node"
        )
    var rows = PyJson.parse(_fragment_statements(fragment))
    if rows.length(rows.root) != 1:
        raise Error("invalid checker fragment: " + label)
    var found = _count_nodes(
        function_doc,
        function_doc.item(statements, choice - 1),
        rows,
        rows.item(rows.root, 0),
    )
    if found != 1:
        raise Error("optional runtime contract: " + label)


def _check_before_loop(
    function_doc: PyJson, fragment: String, label: String
) raises:
    var body = _named_field(function_doc, function_doc.root, "body")
    var rows = PyJson.parse(_fragment_statements(fragment))
    var loop = -1
    var index = 0
    while index < function_doc.length(body):
        if (
            _node_type(function_doc, function_doc.item(body, index)) == "For"
            and loop < 0
        ):
            loop = index
        index += 1
    var cursor = 0
    while cursor < rows.length(rows.root):
        var at = _statement_index(
            function_doc, body, rows, rows.item(rows.root, cursor)
        )
        if at < 0 or loop < 0 or at >= loop:
            raise Error("optional runtime contract: " + label)
        cursor += 1


def _statement_index(
    doc: PyJson, body: Int, wanted: PyJson, target: Int
) raises -> Int:
    var index = 0
    while index < doc.length(body):
        if py_equal(doc, doc.item(body, index), wanted, target):
            return index
        index += 1
    return -1


def _has_call(doc: PyJson, node: Int, name: String) raises -> Bool:
    if _node_type(doc, node) == "Call":
        var func = _named_field(doc, node, "func")
        if _node_type(doc, func) == "Name":
            var ident = _named_field(doc, func, "id")
            if doc.text(ident) == name:
                return True
    if doc.kind(node) == PY_LIST:
        var index = 0
        while index < doc.length(node):
            if _has_call(doc, doc.item(node, index), name):
                return True
            index += 1
    return False


def _check_before_call(
    function_doc: PyJson, fragment: String, call: String, label: String
) raises:
    var body = _named_field(function_doc, function_doc.root, "body")
    var rows = PyJson.parse(_fragment_statements(fragment))
    if rows.length(rows.root) != 1:
        raise Error("invalid checker fragment: " + label)
    var debit = _statement_index(
        function_doc, body, rows, rows.item(rows.root, 0)
    )
    var hits = 0
    var early = False
    var index = 0
    while index < function_doc.length(body):
        if _has_call(function_doc, function_doc.item(body, index), call):
            hits += 1
            if debit < 0 or index <= debit:
                early = True
        index += 1
    if debit < 0 or hits != 2 or early:
        raise Error("optional runtime contract: " + label)


def _node_type(doc: PyJson, node: Int) raises -> String:
    if doc.kind(node) != PY_LIST or doc.length(node) == 0:
        return ""
    var head = doc.item(node, 0)
    if doc.kind(head) != PY_STR:
        return ""
    return doc.text(head)


def _check_fresh(function_doc: PyJson, producer: String, label: String) raises:
    var body = _named_field(function_doc, function_doc.root, "body")
    var loops = List[Int]()
    var index = 0
    while index < function_doc.length(body):
        var statement = function_doc.item(body, index)
        if _node_type(function_doc, statement) == "While":
            loops.append(statement)
        index += 1
    if len(loops) != 1:
        raise Error(
            "optional runtime contract: one original search frontier loop"
        )
    var statements = _named_field(function_doc, loops[0], "body")
    var test = PyJson.parse(expression_dump("work >= 0"))
    var choice = -1
    var hits = 0
    index = 0
    while index < function_doc.length(statements):
        var statement = function_doc.item(statements, index)
        if _node_type(function_doc, statement) == "If":
            var condition = _named_field(function_doc, statement, "test")
            if py_equal(function_doc, condition, test, test.root):
                hits += 1
                choice = index
        index += 1
    if hits != 1 or choice <= 0:
        raise Error(
            "optional runtime contract: fresh cell producer must use original"
            " reference admission"
        )
    var work = PyJson.parse(
        _fragment_statements("var work = _reference_work(road, lo, hi)")
    )
    if work.length(work.root) != 1 or not py_equal(
        function_doc,
        function_doc.item(statements, choice - 1),
        work,
        work.item(work.root, 0),
    ):
        raise Error(
            "optional runtime contract: fresh cell producer must use current"
            " cell work"
        )
    var expected = PyJson.parse(_fragment_statements(producer))
    var branch = _named_field(
        function_doc, function_doc.item(statements, choice), "body"
    )
    if function_doc.length(branch) < expected.length(expected.root):
        raise Error(
            "optional runtime contract: fresh current-cell producer must"
            " immediately follow original debit"
        )
    var cursor = 0
    while cursor < expected.length(expected.root):
        if not py_equal(
            function_doc,
            function_doc.item(branch, cursor),
            expected,
            expected.item(expected.root, cursor),
        ):
            raise Error(
                "optional runtime contract: fresh current-cell producer must"
                " immediately follow original debit"
            )
        cursor += 1
    _ = label


def _named_field(doc: PyJson, node: Int, key: String) raises -> Int:
    var fields = doc.item(node, 1)
    var index = 0
    while index < doc.length(fields):
        var pair = doc.item(fields, index)
        if doc.text(doc.item(pair, 0)) == key:
            return doc.item(pair, 1)
        index += 1
    raise Error("invalid checker fragment: missing " + key)


def _count_nodes(
    doc: PyJson, node: Int, wanted: PyJson, target: Int
) raises -> Int:
    var count = 0
    if py_equal(doc, node, wanted, target):
        count = 1
    if doc.kind(node) == PY_LIST:
        var index = 0
        var size = doc.length(node)
        while index < size:
            count += _count_nodes(doc, doc.item(node, index), wanted, target)
            index += 1
    return count


def _count_sequences(
    doc: PyJson, node: Int, wanted: PyJson, target: Int
) raises -> Int:
    var matches = 0
    if doc.kind(node) == PY_LIST:
        var size = doc.length(node)
        var width = wanted.length(target)
        if width > 0 and size >= width:
            var start = 0
            while start + width <= size:
                var same = True
                var cursor = 0
                while cursor < width:
                    if not py_equal(
                        doc,
                        doc.item(node, start + cursor),
                        wanted,
                        wanted.item(target, cursor),
                    ):
                        same = False
                        break
                    cursor += 1
                if same:
                    matches += 1
                start += 1
        var child = 0
        while child < size:
            matches += _count_sequences(
                doc, doc.item(node, child), wanted, target
            )
            child += 1
    return matches


def _fragment_statements(fragment: String) raises -> String:
    var syntax = python_syntax_json(fragment)
    var parsed = PyJson.parse(syntax)
    var parser = _parser(parsed.text(parsed.at(parsed.root, "source")))
    var stmts = parser._parse_statements()
    var doc = PyJson()
    var rows = doc.new_list()
    var index = 0
    while index < len(stmts):
        doc.append(rows, parser._json(doc, stmts[index]))
        index += 1
    doc.root = rows
    return doc.dumps()


def fragment_count(payload: String) raises -> String:
    """Count one statement, expression, or statement sequence.

    Args:
        payload: JSON with `source`, `name`, `kind`, `fragment`, and `label`.
            `kind` is `contains`, `expression`, `sequence`, `first`, `body`,
            `equal`, `fresh`, `before-loop`, `before-call`, `setup`, or
            `no-attribute`.

    Returns:
        The decimal count of matches.

    Raises:
        Error: The fragment is not one statement, or the source cannot be read.
    """
    var doc = PyJson.parse(payload)
    var source = doc.text(doc.at(doc.root, "source"))
    var name = doc.text(doc.at(doc.root, "name"))
    var kind = doc.text(doc.at(doc.root, "kind"))
    var fragment = doc.text(doc.at(doc.root, "fragment"))
    var label = doc.text(doc.at(doc.root, "label"))
    var body = source
    try:
        body = _decorator_prefix(source, function_slice(source, name))
    except error:
        body = source
    var syntax = python_syntax_json(body)
    var parsed = PyJson.parse(syntax)
    var parser = _parser(parsed.text(parsed.at(parsed.root, "source")))
    var left_text = parser._dump(parser._parse_function(False))
    var function_doc = PyJson.parse(left_text)
    var count = 0
    if kind == "first" or kind == "body":
        var rows = PyJson.parse(_fragment_statements(fragment))
        if kind == "first" and rows.length(rows.root) != 1:
            raise Error("invalid checker fragment: " + label)
        var statements = _named_field(function_doc, function_doc.root, "body")
        if kind == "first":
            if function_doc.length(statements) == 0:
                count = 0
            elif py_equal(
                function_doc,
                function_doc.item(statements, 0),
                rows,
                rows.item(rows.root, 0),
            ):
                count = 1
        elif py_equal(function_doc, statements, rows, rows.root):
            count = 1
    elif kind == "fresh":
        _check_fresh(function_doc, fragment, label)
        count = 1
    elif kind == "setup":
        _check_setup(function_doc, fragment, label)
        count = 1
    elif kind == "no-attribute":
        _forbid_attribute(function_doc, fragment, label)
        count = 1
    elif kind == "before-loop":
        _check_before_loop(function_doc, fragment, label)
        count = 1
    elif kind == "before-call":
        _check_before_call(
            function_doc, fragment, doc.text(doc.at(doc.root, "call")), label
        )
        count = 1
    elif kind == "equal":
        var other = fragment
        try:
            other = _decorator_prefix(fragment, function_slice(fragment, name))
        except error:
            other = fragment
        var other_syntax = python_syntax_json(other)
        var other_parsed = PyJson.parse(other_syntax)
        var other_parser = _parser(
            other_parsed.text(other_parsed.at(other_parsed.root, "source"))
        )
        var right_text = other_parser._dump(other_parser._parse_function(False))
        if left_text == right_text:
            count = 1
    elif kind == "expression":
        var wanted = PyJson.parse(expression_dump(fragment))
        count = _count_nodes(
            function_doc, function_doc.root, wanted, wanted.root
        )
    elif kind == "contains" or kind == "sequence":
        var rows = PyJson.parse(_fragment_statements(fragment))
        if kind == "contains" and rows.length(rows.root) != 1:
            raise Error("invalid checker fragment: " + label)
        if kind == "contains":
            count = _count_nodes(
                function_doc, function_doc.root, rows, rows.item(rows.root, 0)
            )
        else:
            count = _count_sequences(
                function_doc, function_doc.root, rows, rows.root
            )
    else:
        raise Error("invalid checker fragment: " + label)
    return String(count)


def assignment_dump(source: String, name: String) raises -> String:
    """Return the dump of one function-body assignment.

    Args:
        source: A function whose body assigns `name`.
        name: The assignment target.

    Returns:
        The normalized dump of that value.

    Raises:
        Error: The assignment is missing, repeated, or unsupported.
    """
    var parser = _parser(source)
    parser._collect()
    return parser._dump(parser._one(name))


def _syntax_of(module: String, name: String) raises -> String:
    var payload = python_syntax_json(function_slice(module, name))
    var doc = PyJson.parse(payload)
    return doc.text(doc.at(doc.root, "source"))


def _match(
    mut parser: _Parser,
    name: String,
    expected: String,
    message: String,
    k0: Int,
    use_k0: Bool,
) raises -> Int:
    var node = parser._spec(parser._one(name), k0, use_k0)
    if parser._dump(node) != expression_dump(expected):
        raise Error(message)
    return node


def _consumer(source: String, filename: String) raises:
    var parser = _parser(source)
    parser._collect()
    _ = _match(
        parser,
        "rate",
        (
            "_Jet.constant((geometry.curvature_end - geometry.curvature_start)"
            " / geometry.length)"
        ),
        "heading correspondence: stored rate differs: " + filename,
        -1,
        False,
    )
    _ = _match(
        parser,
        "heading",
        (
            "_Jet.constant(geometry.heading) + d *"
            " (_Jet.constant(geometry.curvature_start) + _stored_half(rate)"
            " * d)"
        ),
        "heading correspondence: scalar heading differs: " + filename,
        -1,
        False,
    )
    _ = _match(
        parser,
        "u",
        "_Jet.constant(0.5) * rate * d * d",
        "heading correspondence: ideal u graph changed: " + filename,
        -1,
        False,
    )
    var calls = parser._half_calls()
    var wanted = expression_dump("_stored_half(rate)")
    if len(calls) != 1 or calls[0] != wanted:
        raise Error(
            "heading correspondence: unexpected helper consumer: " + filename
        )


def heading_graph(
    fresh: String,
    domain: String,
    domain_name: String,
    domain_file: String,
    moment: String,
    moment_name: String,
    moment_file: String,
    table: String,
    table_name: String,
    table_file: String,
    eligibility: String,
) raises:
    """Require the fresh heading graph to match each stored consumer.

    Args:
        fresh: The curve-bounds module.
        domain: The spiral-domain proof module.
        domain_name: The domain function to compare.
        domain_file: The domain file named in a failure.
        moment: The spiral-moment proof module.
        moment_name: The moment function to compare.
        moment_file: The moment file named in a failure.
        table: The spiral-moment table module.
        table_name: The table function to compare.
        table_file: The table file named in a failure.
        eligibility: The module that holds the quadrant-zero phase.

    Raises:
        Error: A heading assignment, helper call, or eligibility name changed.
    """
    var fresh_source = _syntax_of(fresh, "_spiral_expression")
    var parser = _parser(fresh_source)
    parser._collect()
    var k0 = _match(
        parser,
        "k0",
        "_Jet.constant(geometry.curvature_start)",
        "heading correspondence: fresh k0 changed",
        -1,
        False,
    )
    _ = _match(
        parser,
        "rate",
        (
            "_Jet.constant((geometry.curvature_end - geometry.curvature_start)"
            " / geometry.length)"
        ),
        "heading correspondence: fresh stored rate changed",
        -1,
        False,
    )
    _ = _match(
        parser,
        "heading",
        (
            "_Jet.constant(geometry.heading) + d *"
            " (_Jet.constant(geometry.curvature_start) + _stored_half(rate)"
            " * d)"
        ),
        "heading correspondence: fresh half heading changed",
        k0,
        True,
    )
    _consumer(_syntax_of(domain, domain_name), domain_file)
    _consumer(_syntax_of(moment, moment_name), moment_file)
    _consumer(_syntax_of(table, table_name), table_file)
    var phase = _parser(
        _syntax_of(eligibility, "_all_spiral_nodes_quadrant_zero")
    )
    phase._collect()
    _ = _match(
        phase,
        "theta",
        (
            "_Jet.constant(geometry.heading) + t *"
            " (_Jet.constant(geometry.curvature_start) + _Jet.constant(0.5) *"
            " rate * t)"
        ),
        "heading correspondence: original eligibility phase graph changed",
        -1,
        False,
    )
    if phase._half_names() != 0:
        raise Error(
            "heading correspondence: stored half introduced into eligibility"
        )


def heading_sources(payload: String) raises:
    """Check the heading graph in one JSON document.

    Args:
        payload: JSON with `fresh`, `domain`, `moment`, `table`, and
            `eligibility`.

    Raises:
        Error: A heading assignment, helper call, or eligibility name changed.
    """
    var doc = PyJson.parse(payload)
    var root = doc.root
    var consumers = doc.at(root, "consumers")
    var first = doc.item(consumers, 0)
    var second = doc.item(consumers, 1)
    var third = doc.item(consumers, 2)
    heading_graph(
        doc.text(doc.at(root, "fresh")),
        doc.text(doc.at(first, "text")),
        doc.text(doc.at(first, "name")),
        doc.text(doc.at(first, "file")),
        doc.text(doc.at(second, "text")),
        doc.text(doc.at(second, "name")),
        doc.text(doc.at(second, "file")),
        doc.text(doc.at(third, "text")),
        doc.text(doc.at(third, "name")),
        doc.text(doc.at(third, "file")),
        doc.text(doc.at(root, "eligibility")),
    )
