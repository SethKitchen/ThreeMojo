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
)
from tools._python_float import parse_float
from tools._python_json import PyJson


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
    ) -> Int:
        var count = len(extra)
        self.kind.append(kind)
        self.label.append(text)
        self.left.append(left)
        self.right.append(right)
        self.at.append(len(self.extra))
        self.narg.append(narg)
        self.nkw.append(nkw)
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
        return self._parse_or()

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
            return self._fail()
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
        if self._kind_at() == _NAME and self._next_op("="):
            var name = self._text_at()
            self.index += 2
            var target = self._add(_E_NAME, name, 1, -1, self._empty(), 0, 0)
            var value = self._parse_expr()
            return self._add(_E_ASSIGN, "", target, value, self._empty(), 0, 0)
        if self._kind_at() == _NAME and self._next_op("+="):
            var name = self._text_at()
            self.index += 2
            var target = self._add(_E_NAME, name, 1, -1, self._empty(), 0, 0)
            var value = self._parse_expr()
            return self._add(_E_AUG, "Add", target, value, self._empty(), 0, 0)
        return self._fail()

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

    def _parse_function(mut self, typed: Bool) raises -> Int:
        while self._kind_at() == _NEWLINE:
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
        var flag = 0
        if typed:
            flag = 1
        return self._add(_E_FUNC, name, args, returns, body^, count, flag)

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
        var start = self.at[node]
        var left = -1
        var right = -1
        if self.left[node] >= 0:
            left = self._clone(self.left[node])
        if self.right[node] >= 0:
            right = self._clone(self.right[node])
        var extra = self._empty()
        var count = narg + nkw
        var cursor = 0
        while cursor < count:
            extra.append(self._clone(self.extra[start + cursor]))
            cursor += 1
        var text = String(self.label[node])
        var kind = self.kind[node]
        return self._add(kind, text, left, right, extra^, narg, nkw)

    def _spec(mut self, node: Int, k0: Int, use_k0: Bool) -> Int:
        if self.kind[node] == _E_NAME:
            if self.label[node] == "Expression":
                return self._add(_E_NAME, "_Jet", -1, -1, self._empty(), 0, 0)
            if use_k0 and self.label[node] == "k0":
                return self._clone(k0)
            return self._clone(node)
        var narg = self.narg[node]
        var nkw = self.nkw[node]
        var start = self.at[node]
        var left = -1
        var right = -1
        if self.left[node] >= 0:
            left = self._spec(self.left[node], k0, use_k0)
        if self.right[node] >= 0:
            right = self._spec(self.right[node], k0, use_k0)
        var extra = self._empty()
        var count = narg + nkw
        var cursor = 0
        while cursor < count:
            extra.append(self._spec(self.extra[start + cursor], k0, use_k0))
            cursor += 1
        var text = String(self.label[node])
        var kind = self.kind[node]
        return self._add(kind, text, left, right, extra^, narg, nkw)

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
            var fields = doc.new_list()
            doc.append(fields, self._pair(doc, "value", doc.new_none()))
            return self._typed(doc, "Constant", fields)
        if kind == _E_ATTR:
            var fields = doc.new_list()
            doc.append(
                fields,
                self._pair(doc, "value", self._json(doc, self.left[node])),
            )
            doc.append(
                fields, self._pair(doc, "attr", doc.new_str(self.label[node]))
            )
            doc.append(fields, self._pair(doc, "ctx", self._load(doc)))
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
            doc.append(fields, self._pair(doc, "ctx", self._load(doc)))
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
                fields, self._pair(doc, "decorator_list", doc.new_list())
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
        var rows = doc.new_list()
        var cursor = 0
        while cursor < self.narg[node]:
            doc.append(
                rows, self._json(doc, self.extra[self.at[node] + cursor])
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
