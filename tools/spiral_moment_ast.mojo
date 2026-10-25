# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Project the ideal spiral onto Python's stored-half AST digest.

The legacy graph commutes each half-times-rate product. The live graph
drops the reviewed Sum2 auxiliaries and projects each stored-half call.
The two graphs must be the same JSON Python's `ast` dump produces.
"""

from tests._python_tokens import _tokenize
from tools._python_float import parse_float, python_repr
from tools._sha256 import sha256_hex
from tools.spiral_moment_projection import stored_half_projection


comptime _NAME = 1
comptime _NUMBER = 2
comptime _STRING = 3
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6
comptime _OP = 55
comptime _END = -1

comptime _NODE = 1
comptime _LIST = 2
comptime _STR = 3
comptime _INT = 4
comptime _FLOAT = 5
comptime _PAIRS = 6

comptime _LEGACY_SHA256 = (
    "270a3cde3b012388ee8fcb6a4ecc59d837d1583f6c406f942ff98fdccd9f5733"
)
"""SHA-256 of the pinned legacy ideal spiral."""

comptime _PAIRS_JSON = '[["NAME","derivatives"],["OP",":"],["NAME","Bool"]]'
"""Python's token list for the ideal generic parameter."""


def _fail(message: String) raises:
    """Raise a projected-graph error.

    Args:
        message: The failure text.

    Raises:
        Error: The projection check failed.
    """
    raise Error("spiral moment ast: " + message)


def _bad() raises:
    """Raise a syntax error for an ideal function.

    Raises:
        Error: The source is outside the ideal subset.
    """
    _fail("unsupported ideal source syntax")


def _quote(text: String) -> String:
    """Return `text` as a JSON string.

    Args:
        text: An ASCII identifier or operator.

    Returns:
        The quoted text.
    """
    return '"' + text + '"'


struct _Graph:
    """A Python AST stored as nodes and lists."""

    var kind: List[String]
    var fname: List[List[String]]
    var ftag: List[List[Int]]
    var fnode: List[List[Int]]
    var fstr: List[List[String]]
    var fint: List[List[Int]]
    var ffloat: List[List[Float64]]
    var lists: List[List[Int]]

    def __init__(out self):
        """Create an empty graph."""
        self.kind = List[String]()
        self.fname = List[List[String]]()
        self.ftag = List[List[Int]]()
        self.fnode = List[List[Int]]()
        self.fstr = List[List[String]]()
        self.fint = List[List[Int]]()
        self.ffloat = List[List[Float64]]()
        self.lists = List[List[Int]]()

    def add(mut self, kind: String) -> Int:
        """Append a node and return its index.

        Args:
            kind: The Python AST type name.

        Returns:
            The new node index.
        """
        var index = len(self.kind)
        self.kind.append(kind)
        self.fname.append(List[String]())
        self.ftag.append(List[Int]())
        self.fnode.append(List[Int]())
        self.fstr.append(List[String]())
        self.fint.append(List[Int]())
        self.ffloat.append(List[Float64]())
        return index

    def push(
        mut self,
        node: Int,
        name: String,
        tag: Int,
        child: Int,
        text: String,
        ival: Int,
        fval: Float64,
    ):
        """Append one field.

        Args:
            node: The node that receives the field.
            name: The Python field name.
            tag: The value tag.
            child: A node or list index.
            text: A string value.
            ival: An int value.
            fval: A float value.
        """
        self.fname[node].append(name)
        self.ftag[node].append(tag)
        self.fnode[node].append(child)
        self.fstr[node].append(text)
        self.fint[node].append(ival)
        self.ffloat[node].append(fval)

    def clear(mut self, node: Int):
        """Remove every field of `node`.

        Args:
            node: The node to reuse.
        """
        self.fname[node] = List[String]()
        self.ftag[node] = List[Int]()
        self.fnode[node] = List[Int]()
        self.fstr[node] = List[String]()
        self.fint[node] = List[Int]()
        self.ffloat[node] = List[Float64]()

    def dump(self, node: Int) raises -> String:
        """Return Python's compact AST JSON for `node`.

        Args:
            node: The node to write.

        Returns:
            The JSON text.

        Raises:
            Error: A float cannot be written.
        """
        var out = String('["') + self.kind[node] + String('",[')
        var count = len(self.ftag[node])
        var index = 0
        while index < count:
            if index > 0:
                out += ","
            out += "[" + _quote(self.fname[node][index]) + ","
            var tag = self.ftag[node][index]
            if tag == _NODE:
                out += self.dump(self.fnode[node][index])
            elif tag == _LIST:
                out += self.dump_list(self.fnode[node][index])
            elif tag == _STR:
                out += _quote(self.fstr[node][index])
            elif tag == _INT:
                out += String(self.fint[node][index])
            elif tag == _FLOAT:
                out += python_repr(self.ffloat[node][index])
            else:
                out += self.fstr[node][index]
            out += "]"
            index += 1
        out += "]]"
        return out^

    def dump_list(self, index: Int) raises -> String:
        """Return the JSON array of nodes at `index`.

        Args:
            index: The list index.

        Returns:
            The JSON array.

        Raises:
            Error: A nested float cannot be written.
        """
        var out = String("[")
        var count = len(self.lists[index])
        var cursor = 0
        while cursor < count:
            if cursor > 0:
                out += ","
            out += self.dump(self.lists[index][cursor])
            cursor += 1
        out += "]"
        return out^

    def copy_node(mut self, node: Int) -> Int:
        """Return a deep copy of `node`.

        Args:
            node: The node to copy.

        Returns:
            The copy.
        """
        var kind = String(self.kind[node])
        var copy = self.add(kind)
        var count = len(self.ftag[node])
        var index = 0
        while index < count:
            var tag = self.ftag[node][index]
            var name = String(self.fname[node][index])
            if tag == _NODE:
                var child = self.copy_node(self.fnode[node][index])
                self.push(copy, name, tag, child, "", 0, 0.0)
            elif tag == _LIST:
                var copied = self.copy_list(self.fnode[node][index])
                self.push(copy, name, tag, copied, "", 0, 0.0)
            elif tag == _STR or tag == _PAIRS:
                var text = String(self.fstr[node][index])
                self.push(copy, name, tag, 0, text, 0, 0.0)
            elif tag == _INT:
                var ival = self.fint[node][index]
                self.push(copy, name, tag, 0, "", ival, 0.0)
            else:
                var fval = self.ffloat[node][index]
                self.push(copy, name, tag, 0, "", 0, fval)
            index += 1
        return copy

    def copy_list(mut self, index: Int) -> Int:
        """Return a deep copy of a node list.

        Args:
            index: The list to copy.

        Returns:
            The new list index.
        """
        var count = len(self.lists[index])
        var originals = List[Int]()
        var cursor = 0
        while cursor < count:
            originals.append(self.lists[index][cursor])
            cursor += 1
        var copied = List[Int]()
        cursor = 0
        while cursor < count:
            copied.append(self.copy_node(originals[cursor]))
            cursor += 1
        self.lists.append(copied^)
        return len(self.lists) - 1


struct _Parser:
    """A parser for one ideal spiral function."""

    var kinds: List[Int]
    var texts: List[String]
    var at: Int
    var graph: _Graph
    var root: Int

    def __init__(out self):
        """Create an empty parser."""
        self.kinds = List[Int]()
        self.texts = List[String]()
        self.at = 0
        self.graph = _Graph()
        self.root = 0

    def load(mut self, source: String) raises:
        """Load `source`, dropping `var` and `comptime` names.

        Args:
            source: Ideal spiral source.

        Raises:
            Error: The source cannot be tokenized.
        """
        var kinds = List[Int]()
        var texts = List[String]()
        var failed = False
        try:
            _tokenize(source, kinds, texts)
        except error:
            failed = True
        if failed:
            _bad()
        self.kinds = List[Int]()
        self.texts = List[String]()
        self.at = 0
        var index = 0
        while index < len(kinds):
            var skip = False
            if kinds[index] == _NAME:
                if texts[index] == "var":
                    skip = True
                if texts[index] == "comptime":
                    skip = True
            if not skip:
                self.kinds.append(kinds[index])
                self.texts.append(texts[index])
            index += 1

    def kind(self) -> Int:
        """Return the current token kind, or the end marker.

        Returns:
            The token kind.
        """
        if self.at >= len(self.kinds):
            return _END
        return self.kinds[self.at]

    def text(self) -> String:
        """Return the current token text.

        Returns:
            The token text.
        """
        return String(self.texts[self.at])

    def is_op(self, text: String) -> Bool:
        """Return whether the current token is `text`.

        Args:
            text: The operator text.

        Returns:
            True when the operator is current.
        """
        if self.kind() != _OP:
            return False
        return self.text() == text

    def is_name(self, text: String) -> Bool:
        """Return whether the current token is the name `text`.

        Args:
            text: The name.

        Returns:
            True when that name is current.
        """
        if self.kind() != _NAME:
            return False
        return self.text() == text

    def eat_op(mut self, text: String) raises:
        """Consume the operator `text`.

        Args:
            text: The operator text.

        Raises:
            Error: The operator is not current.
        """
        if not self.is_op(text):
            _bad()
        self.at += 1

    def eat_kind(mut self, kind: Int) raises:
        """Consume a token of `kind`.

        Args:
            kind: The token kind.

        Raises:
            Error: The current token has another kind.
        """
        if self.kind() != kind:
            _bad()
        self.at += 1

    def take_name(mut self) raises -> String:
        """Consume one name.

        Returns:
            The name text.

        Raises:
            Error: The current token is not a name.
        """
        if self.kind() != _NAME:
            _bad()
        var text = self.text()
        self.at += 1
        return text^

    def new_list(mut self, items: List[Int]) -> Int:
        """Store `items` and return the list index.

        Args:
            items: The node indexes.

        Returns:
            The list index.
        """
        var copied = List[Int]()
        var index = 0
        while index < len(items):
            copied.append(items[index])
            index += 1
        self.graph.lists.append(copied^)
        return len(self.graph.lists) - 1

    def empty_list(mut self) -> Int:
        """Return a new empty node list.

        Returns:
            The list index.
        """
        var items = List[Int]()
        return self.new_list(items)

    def node_field(self, node: Int, name: String) -> Int:
        """Return the node stored in `name`.

        Args:
            node: The parent.
            name: The field name.

        Returns:
            The child node.
        """
        var index = 0
        while index < len(self.graph.ftag[node]):
            if self.graph.fname[node][index] == name:
                return self.graph.fnode[node][index]
            index += 1
        return 0

    def list_field(self, node: Int, name: String) -> Int:
        """Return the list stored in `name`.

        Args:
            node: The parent.
            name: The field name.

        Returns:
            The list index.
        """
        return self.node_field(node, name)

    def set_node(mut self, node: Int, name: String, child: Int):
        """Replace the node stored in `name`.

        Args:
            node: The parent.
            name: The field name.
            child: The new child.
        """
        var index = 0
        while index < len(self.graph.ftag[node]):
            if self.graph.fname[node][index] == name:
                self.graph.fnode[node][index] = child
                return
            index += 1

    def items(self, index: Int) -> List[Int]:
        """Return a copy of a node list.

        Args:
            index: The list index.

        Returns:
            The node indexes.
        """
        var copied = List[Int]()
        var cursor = 0
        while cursor < len(self.graph.lists[index]):
            copied.append(self.graph.lists[index][cursor])
            cursor += 1
        return copied^

    def name(mut self, ident: String, store: Bool) -> Int:
        """Return a Name node.

        Args:
            ident: The identifier.
            store: True for a store context.

        Returns:
            The Name node.
        """
        var node = self.graph.add("Name")
        self.graph.push(node, "id", _STR, 0, ident, 0, 0.0)
        var ctx_kind = String("Load")
        if store:
            ctx_kind = "Store"
        var ctx = self.graph.add(ctx_kind)
        self.graph.push(node, "ctx", _NODE, ctx, "", 0, 0.0)
        return node

    def store(mut self, node: Int) raises:
        """Mark a target as stored.

        Args:
            node: A name or attribute.

        Raises:
            Error: The target is not a name or attribute.
        """
        var kind = String(self.graph.kind[node])
        if kind == "Name":
            self.set_node(node, "ctx", self.graph.add("Store"))
            return
        if kind == "Attribute":
            self.set_node(node, "ctx", self.graph.add("Store"))
            return
        _bad()

    def const_int(mut self, value: Int) -> Int:
        """Return an integer constant.

        Args:
            value: The integer.

        Returns:
            The Constant node.
        """
        var node = self.graph.add("Constant")
        self.graph.push(node, "value", _INT, 0, "", value, 0.0)
        return node

    def const_float(mut self, value: Float64) -> Int:
        """Return a float constant.

        Args:
            value: The float.

        Returns:
            The Constant node.
        """
        var node = self.graph.add("Constant")
        self.graph.push(node, "value", _FLOAT, 0, "", 0, value)
        return node

    def number(mut self, text: String) raises -> Int:
        """Return the constant for a number token.

        Args:
            text: The number spelling.

        Returns:
            The Constant node.

        Raises:
            Error: The spelling is not a plain decimal.
        """
        var raw = text.as_bytes()
        var dotted = False
        var ok = True
        var index = 0
        while index < len(raw):
            var byte = raw[index]
            if byte == 46:
                dotted = True
            elif byte > 57:
                ok = False
            index += 1
        if not ok:
            _bad()
        if dotted:
            return self.const_float(parse_float(text))
        var value = 0
        index = 0
        while index < len(raw):
            value = value * 10 + Int(raw[index] - 48)
            index += 1
        return self.const_int(value)

    def attr(mut self, value: Int, name: String) -> Int:
        """Return an attribute load.

        Args:
            value: The object.
            name: The attribute.

        Returns:
            The Attribute node.
        """
        var node = self.graph.add("Attribute")
        self.graph.push(node, "value", _NODE, value, "", 0, 0.0)
        self.graph.push(node, "attr", _STR, 0, name, 0, 0.0)
        var ctx = self.graph.add("Load")
        self.graph.push(node, "ctx", _NODE, ctx, "", 0, 0.0)
        return node

    def call(mut self, func: Int, args: List[Int]) -> Int:
        """Return a call.

        Args:
            func: The callee.
            args: The positional arguments.

        Returns:
            The Call node.
        """
        var node = self.graph.add("Call")
        self.graph.push(node, "func", _NODE, func, "", 0, 0.0)
        var arg_list = self.new_list(args)
        self.graph.push(node, "args", _LIST, arg_list, "", 0, 0.0)
        var keywords = self.empty_list()
        self.graph.push(node, "keywords", _LIST, keywords, "", 0, 0.0)
        return node

    def binop(mut self, left: Int, op: String, right: Int) -> Int:
        """Return a binary operation.

        Args:
            left: The left operand.
            op: The Python operator type.
            right: The right operand.

        Returns:
            The BinOp node.
        """
        var node = self.graph.add("BinOp")
        self.graph.push(node, "left", _NODE, left, "", 0, 0.0)
        var marker = self.graph.add(op)
        self.graph.push(node, "op", _NODE, marker, "", 0, 0.0)
        self.graph.push(node, "right", _NODE, right, "", 0, 0.0)
        return node

    def tuple(mut self, elts: List[Int]) -> Int:
        """Return a tuple.

        Args:
            elts: The elements.

        Returns:
            The Tuple node.
        """
        var node = self.graph.add("Tuple")
        var items = self.new_list(elts)
        self.graph.push(node, "elts", _LIST, items, "", 0, 0.0)
        var ctx = self.graph.add("Load")
        self.graph.push(node, "ctx", _NODE, ctx, "", 0, 0.0)
        return node

    def subscript(mut self, value: Int, slice: Int) -> Int:
        """Return a subscript load.

        Args:
            value: The container.
            slice: The index.

        Returns:
            The Subscript node.
        """
        var node = self.graph.add("Subscript")
        self.graph.push(node, "value", _NODE, value, "", 0, 0.0)
        self.graph.push(node, "slice", _NODE, slice, "", 0, 0.0)
        var ctx = self.graph.add("Load")
        self.graph.push(node, "ctx", _NODE, ctx, "", 0, 0.0)
        return node

    def atom(mut self) raises -> Int:
        """Parse one atom.

        Returns:
            The expression node.

        Raises:
            Error: The token is not an atom.
        """
        if self.kind() == _STRING:
            _bad()
        if self.kind() == _NAME:
            var ident = self.take_name()
            return self.name(ident, False)
        if self.kind() == _NUMBER:
            var spelling = self.text()
            self.at += 1
            return self.number(spelling)
        if self.is_op("("):
            return self.paren()
        _bad()
        return 0

    def paren(mut self) raises -> Int:
        """Parse a parenthesized expression or tuple.

        Returns:
            The expression.

        Raises:
            Error: The parentheses are not closed.
        """
        self.eat_op("(")
        var first = self.expr()
        if not self.is_op(","):
            self.eat_op(")")
            return first
        var elts = List[Int]()
        elts.append(first)
        while self.is_op(","):
            self.at += 1
            if self.is_op(")"):
                break
            elts.append(self.expr())
        self.eat_op(")")
        return self.tuple(elts)

    def trailer(mut self) raises -> Int:
        """Parse an atom and its trailers.

        Returns:
            The expression.

        Raises:
            Error: A trailer is malformed.
        """
        var node = self.atom()
        while True:
            if self.is_op("."):
                self.at += 1
                var ident = self.take_name()
                node = self.attr(node, ident)
            elif self.is_op("["):
                node = self.subscript_of(node)
            elif self.is_op("("):
                node = self.call_of(node)
            else:
                break
        return node

    def subscript_of(mut self, value: Int) raises -> Int:
        """Parse a subscript after `value`.

        Args:
            value: The container.

        Returns:
            The Subscript node.

        Raises:
            Error: The brackets are malformed.
        """
        self.eat_op("[")
        var first = self.expr()
        if not self.is_op(","):
            self.eat_op("]")
            return self.subscript(value, first)
        var elts = List[Int]()
        elts.append(first)
        while self.is_op(","):
            self.at += 1
            if self.is_op("]"):
                break
            elts.append(self.expr())
        self.eat_op("]")
        var slice = self.tuple(elts)
        return self.subscript(value, slice)

    def call_of(mut self, func: Int) raises -> Int:
        """Parse a call after `func`.

        Args:
            func: The callee.

        Returns:
            The Call node.

        Raises:
            Error: The arguments are malformed.
        """
        self.eat_op("(")
        var args = List[Int]()
        while not self.is_op(")"):
            args.append(self.expr())
            if self.is_op(","):
                self.at += 1
        self.eat_op(")")
        return self.call(func, args)

    def term(mut self) raises -> Int:
        """Parse a product.

        Returns:
            The expression.

        Raises:
            Error: A factor is malformed.
        """
        var left = self.trailer()
        while self.is_op("*") or self.is_op("/"):
            var op = String("Mult")
            if self.is_op("/"):
                op = "Div"
            self.at += 1
            var right = self.trailer()
            left = self.binop(left, op, right)
        return left

    def sum(mut self) raises -> Int:
        """Parse a sum.

        Returns:
            The expression.

        Raises:
            Error: A term is malformed.
        """
        var left = self.term()
        while self.is_op("+") or self.is_op("-"):
            var op = String("Add")
            if self.is_op("-"):
                op = "Sub"
            self.at += 1
            var right = self.term()
            left = self.binop(left, op, right)
        return left

    def compare(mut self) raises -> Int:
        """Parse a comparison.

        Returns:
            The expression.

        Raises:
            Error: An operand is malformed.
        """
        var left = self.sum()
        if not self.is_op("<"):
            return left
        self.at += 1
        var right = self.sum()
        var node = self.graph.add("Compare")
        self.graph.push(node, "left", _NODE, left, "", 0, 0.0)
        var ops = List[Int]()
        ops.append(self.graph.add("Lt"))
        var op_list = self.new_list(ops)
        self.graph.push(node, "ops", _LIST, op_list, "", 0, 0.0)
        var comps = List[Int]()
        comps.append(right)
        var comp_list = self.new_list(comps)
        self.graph.push(node, "comparators", _LIST, comp_list, "", 0, 0.0)
        return node

    def expr(mut self) raises -> Int:
        """Parse one expression.

        Returns:
            The expression.

        Raises:
            Error: The expression is malformed.
        """
        if not self.is_name("not"):
            return self.compare()
        self.at += 1
        var operand = self.expr()
        var node = self.graph.add("UnaryOp")
        var op = self.graph.add("Not")
        self.graph.push(node, "op", _NODE, op, "", 0, 0.0)
        self.graph.push(node, "operand", _NODE, operand, "", 0, 0.0)
        return node

    def block(mut self) raises -> Int:
        """Parse an indented block.

        Returns:
            The statement list.

        Raises:
            Error: The block is not indented.
        """
        self.eat_kind(_NEWLINE)
        self.eat_kind(_INDENT)
        var items = List[Int]()
        while self.kind() != _DEDENT:
            items.append(self.statement())
        self.at += 1
        return self.new_list(items)

    def statement(mut self) raises -> Int:
        """Parse one statement.

        Returns:
            The statement node.

        Raises:
            Error: The statement is not in the ideal subset.
        """
        if self.is_name("if"):
            return self.if_stmt()
        if self.is_name("while"):
            return self.while_stmt()
        if self.is_name("return"):
            return self.return_stmt()
        var target = self.expr()
        if self.is_op("+="):
            self.at += 1
            self.store(target)
            var value = self.expr()
            self.eat_kind(_NEWLINE)
            return self.aug_assign(target, value)
        if self.is_op("="):
            self.at += 1
            self.store(target)
            var value = self.expr()
            self.eat_kind(_NEWLINE)
            return self.assign(target, value)
        _bad()
        return 0

    def assign(mut self, target: Int, value: Int) -> Int:
        """Return an assignment.

        Args:
            target: The stored target.
            value: The value.

        Returns:
            The Assign node.
        """
        var node = self.graph.add("Assign")
        var targets = List[Int]()
        targets.append(target)
        var items = self.new_list(targets)
        self.graph.push(node, "targets", _LIST, items, "", 0, 0.0)
        self.graph.push(node, "value", _NODE, value, "", 0, 0.0)
        return node

    def aug_assign(mut self, target: Int, value: Int) -> Int:
        """Return an augmented assignment.

        Args:
            target: The stored target.
            value: The added value.

        Returns:
            The AugAssign node.
        """
        var node = self.graph.add("AugAssign")
        self.graph.push(node, "target", _NODE, target, "", 0, 0.0)
        var op = self.graph.add("Add")
        self.graph.push(node, "op", _NODE, op, "", 0, 0.0)
        self.graph.push(node, "value", _NODE, value, "", 0, 0.0)
        return node

    def if_stmt(mut self) raises -> Int:
        """Parse an if statement.

        Returns:
            The If node.

        Raises:
            Error: The statement is malformed.
        """
        self.at += 1
        var test = self.expr()
        self.eat_op(":")
        var body = self.block()
        var node = self.graph.add("If")
        self.graph.push(node, "test", _NODE, test, "", 0, 0.0)
        self.graph.push(node, "body", _LIST, body, "", 0, 0.0)
        var orelse = self.empty_list()
        self.graph.push(node, "orelse", _LIST, orelse, "", 0, 0.0)
        return node

    def while_stmt(mut self) raises -> Int:
        """Parse a while statement.

        Returns:
            The While node.

        Raises:
            Error: The statement is malformed.
        """
        self.at += 1
        var test = self.expr()
        self.eat_op(":")
        var body = self.block()
        var node = self.graph.add("While")
        self.graph.push(node, "test", _NODE, test, "", 0, 0.0)
        self.graph.push(node, "body", _LIST, body, "", 0, 0.0)
        var orelse = self.empty_list()
        self.graph.push(node, "orelse", _LIST, orelse, "", 0, 0.0)
        return node

    def return_stmt(mut self) raises -> Int:
        """Parse a return statement.

        Returns:
            The Return node.

        Raises:
            Error: The statement is malformed.
        """
        self.at += 1
        var value = self.expr()
        self.eat_kind(_NEWLINE)
        var node = self.graph.add("Return")
        self.graph.push(node, "value", _NODE, value, "", 0, 0.0)
        return node

    def params_ok(mut self) raises -> Bool:
        """Consume a generic parameter list.

        Returns:
            True when the list is `derivatives: Bool`.

        Raises:
            Error: The brackets are not closed.
        """
        self.eat_op("[")
        var depth = 1
        var labels = List[String]()
        var values = List[String]()
        while depth > 0:
            var kind = self.kind()
            var text = self.text()
            self.at += 1
            if kind == _OP and text == "[":
                depth += 1
            elif kind == _OP and text == "]":
                depth -= 1
            elif kind == _NAME:
                labels.append("NAME")
                values.append(text)
            elif kind == _OP:
                labels.append("OP")
                values.append(text)
            elif kind == _NUMBER:
                labels.append("NUMBER")
                values.append(text)
            else:
                return False
        var ok = len(values) == 3
        if ok:
            ok = labels[0] == "NAME"
        if ok:
            ok = values[0] == "derivatives"
        if ok:
            ok = labels[1] == "OP"
        if ok:
            ok = values[1] == ":"
        if ok:
            ok = labels[2] == "NAME"
        if ok:
            ok = values[2] == "Bool"
        return ok

    def arguments(mut self) raises -> Int:
        """Parse a parameter list inside parentheses.

        Returns:
            The arguments node.

        Raises:
            Error: A parameter is malformed.
        """
        var args = List[Int]()
        while not self.is_op(")"):
            var ident = self.take_name()
            self.eat_op(":")
            var ann = self.expr()
            var arg = self.graph.add("arg")
            self.graph.push(arg, "arg", _STR, 0, ident, 0, 0.0)
            self.graph.push(arg, "annotation", _NODE, ann, "", 0, 0.0)
            args.append(arg)
            if self.is_op(","):
                self.at += 1
        var node = self.graph.add("arguments")
        var empty = self.empty_list()
        self.graph.push(node, "posonlyargs", _LIST, empty, "", 0, 0.0)
        var arg_list = self.new_list(args)
        self.graph.push(node, "args", _LIST, arg_list, "", 0, 0.0)
        var kwonly = self.empty_list()
        self.graph.push(node, "kwonlyargs", _LIST, kwonly, "", 0, 0.0)
        var defaults = self.empty_list()
        self.graph.push(node, "kw_defaults", _LIST, defaults, "", 0, 0.0)
        var positional = self.empty_list()
        self.graph.push(node, "defaults", _LIST, positional, "", 0, 0.0)
        return node

    def function(mut self) raises:
        """Parse the one ideal function.

        Raises:
            Error: The declaration is not the ideal spiral.
        """
        if not self.is_name("def"):
            _fail("unsupported ideal function declaration")
        self.at += 1
        if not self.is_name("_spiral_expression"):
            _fail("unsupported ideal function declaration")
        self.at += 1
        if not self.is_op("["):
            _fail("unsupported ideal function declaration")
        if not self.params_ok():
            _fail("changed ideal generic declaration")
        self.eat_op("(")
        var args = self.arguments()
        self.eat_op(")")
        self.eat_op("->")
        var ret = self.expr()
        self.eat_op(":")
        var body = self.block()
        var node = self.graph.add("FunctionDef")
        self.graph.push(node, "name", _STR, 0, "_spiral_expression", 0, 0.0)
        self.graph.push(node, "args", _NODE, args, "", 0, 0.0)
        self.graph.push(node, "body", _LIST, body, "", 0, 0.0)
        var decorators = self.empty_list()
        self.graph.push(node, "decorator_list", _LIST, decorators, "", 0, 0.0)
        self.graph.push(node, "returns", _NODE, ret, "", 0, 0.0)
        self.graph.push(
            node, "mojo_type_parameters", _PAIRS, 0, _PAIRS_JSON, 0, 0.0
        )
        self.root = node
        if self.kind() != _END:
            _fail("ambiguous ideal function declaration")

    def joined(self, nodes: List[Int]) raises -> String:
        """Return the dumps of `nodes`, separated by semicolons.

        Args:
            nodes: The statements.

        Returns:
            The joined JSON.

        Raises:
            Error: A float cannot be written.
        """
        var out = String()
        var index = 0
        while index < len(nodes):
            if index > 0:
                out += ";"
            out += self.graph.dump(nodes[index])
            index += 1
        return out^

    def project(mut self) raises:
        """Drop the reviewed Sum2 auxiliaries and inline the terms.

        Raises:
            Error: A reviewed statement moved or changed.
        """
        var body_index = self.list_field(self.root, "body")
        var body = self.items(body_index)
        var guard = _one_dump(_GUARD)
        var bad_guard = len(body) != 19
        if not bad_guard:
            bad_guard = self.graph.dump(body[1]) != guard
        if bad_guard:
            _fail("fresh Sum2 environment refusal changed or moved")
        var kept = List[Int]()
        var index = 0
        while index < len(body):
            if index != 1:
                kept.append(body[index])
            index += 1
        if self.graph.kind[kept[13]] != "While":
            _fail("Sum2 complete ideal statement layout changed")
        var outer_index = self.list_field(kept[13], "body")
        var outer = self.items(outer_index)
        var bad_outer = len(outer) != 4
        if not bad_outer:
            bad_outer = self.graph.kind[outer[2]] != "While"
        if bad_outer:
            _fail("Sum2 complete outer-loop layout changed")
        var inner_index = self.list_field(outer[2], "body")
        var inner = self.items(inner_index)
        if len(inner) != 12:
            _fail("Sum2 complete node-loop layout changed")
        var declarations = List[Int]()
        declarations.append(kept[8])
        declarations.append(kept[9])
        declarations.append(kept[10])
        declarations.append(kept[11])
        if self.joined(declarations) != _one_dump(_DECLARATIONS):
            _fail("Sum2 declarations reordered or changed")
        var errors = List[Int]()
        errors.append(kept[14])
        errors.append(kept[15])
        if self.joined(errors) != _one_dump(_ERRORS):
            _fail("Sum2 final error writes reordered or changed")
        var updates = List[Int]()
        updates.append(inner[7])
        updates.append(inner[8])
        updates.append(inner[9])
        updates.append(inner[10])
        if self.joined(updates) != _one_dump(_UPDATES):
            _fail("Sum2 auxiliary updates reordered or changed")
        var terms = List[Int]()
        terms.append(inner[3])
        terms.append(inner[4])
        if self.joined(terms) != _one_dump(_TERMS):
            _fail("Sum2 immutable term definition moved or changed")
        var sums = List[Int]()
        sums.append(inner[5])
        sums.append(inner[6])
        if self.joined(sums) != _one_dump(_ACCUMULATIONS):
            _fail("Sum2 ideal term accumulation moved or changed")
        var term_x = self.graph.copy_node(self.node_field(inner[3], "value"))
        var term_y = self.graph.copy_node(self.node_field(inner[4], "value"))
        var sum_x = self.node_field(inner[5], "value")
        var sum_y = self.node_field(inner[6], "value")
        self.set_node(sum_x, "right", term_x)
        self.set_node(sum_y, "right", term_y)
        var new_inner = List[Int]()
        new_inner.append(inner[0])
        new_inner.append(inner[1])
        new_inner.append(inner[2])
        new_inner.append(inner[5])
        new_inner.append(inner[6])
        new_inner.append(inner[11])
        self.graph.lists[inner_index] = new_inner^
        var new_body = List[Int]()
        index = 0
        while index < 8:
            new_body.append(kept[index])
            index += 1
        new_body.append(kept[12])
        new_body.append(kept[13])
        new_body.append(kept[16])
        new_body.append(kept[17])
        self.graph.lists[body_index] = new_body^

    def half_shape(self, node: Int) -> Bool:
        """Return whether `node` is one stored-half name call.

        Args:
            node: A call whose callee is `_stored_half`.

        Returns:
            True for one name argument.
        """
        var args = self.list_field(node, "args")
        var ok = len(self.graph.lists[args]) == 1
        if ok:
            var arg = self.graph.lists[args][0]
            ok = self.graph.kind[arg] == "Name"
        return ok

    def func_is(self, node: Int, ident: String) -> Bool:
        """Return whether `node` calls the name `ident`.

        Args:
            node: A candidate call.
            ident: The callee name.

        Returns:
            True when the callee is that name.
        """
        if self.graph.kind[node] != "Call":
            return False
        var func = self.node_field(node, "func")
        if self.graph.kind[func] != "Name":
            return False
        return self.graph.fstr[func][0] == ident

    def project_half(mut self, node: Int, mut args: List[String]) raises:
        """Replace stored-half calls under `node`.

        Args:
            node: The subtree.
            args: The argument names, in visit order.

        Raises:
            Error: A stored-half call is not one name.
        """
        var count = len(self.graph.ftag[node])
        var index = 0
        while index < count:
            var tag = self.graph.ftag[node][index]
            if tag == _NODE:
                var child = self.graph.fnode[node][index]
                self.project_half(child, args)
            elif tag == _LIST:
                var list_index = self.graph.fnode[node][index]
                var cursor = 0
                var length = len(self.graph.lists[list_index])
                while cursor < length:
                    var child = self.graph.lists[list_index][cursor]
                    self.project_half(child, args)
                    cursor += 1
            index += 1
        if not self.func_is(node, "_stored_half"):
            return
        if not self.half_shape(node):
            _fail("unreviewed stored-half call shape")
        var args_index = self.list_field(node, "args")
        var arg = self.graph.lists[args_index][0]
        var ident = String()
        var field = 0
        while field < len(self.graph.fname[arg]):
            if self.graph.fname[arg][field] == "id":
                ident = String(self.graph.fstr[arg][field])
            field += 1
        args.append(ident)
        var right = self.half_constant()
        self.graph.kind[node] = "BinOp"
        self.graph.clear(node)
        self.graph.push(node, "left", _NODE, arg, "", 0, 0.0)
        var op = self.graph.add("Mult")
        self.graph.push(node, "op", _NODE, op, "", 0, 0.0)
        self.graph.push(node, "right", _NODE, right, "", 0, 0.0)

    def half_constant(mut self) -> Int:
        """Return `Expression.constant(0.5)`.

        Returns:
            The call node.
        """
        var expr = self.name("Expression", False)
        var func = self.attr(expr, "constant")
        var args = List[Int]()
        args.append(self.const_float(0.5))
        return self.call(func, args)

    def rate_half(self, node: Int) -> Bool:
        """Return whether `node` multiplies by the name `rate`.

        Args:
            node: A candidate product.

        Returns:
            True when the right operand is `rate`.
        """
        if self.graph.kind[node] != "BinOp":
            return False
        var op = self.node_field(node, "op")
        if self.graph.kind[op] != "Mult":
            return False
        var right = self.node_field(node, "right")
        if self.graph.kind[right] != "Name":
            return False
        return self.graph.fstr[right][0] == "rate"

    def commute(mut self, node: Int):
        """Swap each `rate` product so the name is on the left.

        Args:
            node: The subtree.
        """
        var count = len(self.graph.ftag[node])
        var index = 0
        while index < count:
            var tag = self.graph.ftag[node][index]
            if tag == _NODE:
                var child = self.graph.fnode[node][index]
                self.commute(child)
            elif tag == _LIST:
                var list_index = self.graph.fnode[node][index]
                var cursor = 0
                var length = len(self.graph.lists[list_index])
                while cursor < length:
                    var child = self.graph.lists[list_index][cursor]
                    self.commute(child)
                    cursor += 1
            index += 1
        if not self.rate_half(node):
            return
        var left = self.node_field(node, "left")
        var right = self.node_field(node, "right")
        self.set_node(node, "left", right)
        self.set_node(node, "right", left)


comptime _GUARD = (
    "    if not _sum2_supported_environment():\n        unknown ="
    " Expression(_Interval.whole(), _Interval.whole(), _Interval.whole(),"
    " inf[DType.float64]())\n        return (unknown, unknown, unknown)\n"
)
"""The reviewed environment refusal."""

comptime _DECLARATIONS = (
    "    x_magnitude = _Interval.point(0.0)\n    y_magnitude ="
    " _Interval.point(0.0)\n    x_inherited = _Interval.point(0.0)\n   "
    " y_inherited = _Interval.point(0.0)\n"
)
"""The four reviewed auxiliary declarations."""

comptime _ERRORS = (
    "    x.error = _sum2_error_checked(x_magnitude.high, x_inherited.high, 5 *"
    " pieces)\n    y.error = _sum2_error_checked(y_magnitude.high,"
    " y_inherited.high, 5 * pieces)\n"
)
"""The two reviewed final error writes."""

comptime _UPDATES = (
    "    x_magnitude = x_magnitude +"
    " _Interval.point(term_x.rounded_value().magnitude())\n    y_magnitude ="
    " y_magnitude + _Interval.point(term_y.rounded_value().magnitude())\n   "
    " x_inherited = x_inherited + _Interval.point(term_x.error)\n   "
    " y_inherited = y_inherited + _Interval.point(term_y.error)\n"
)
"""The four reviewed auxiliary updates."""

comptime _TERMS = (
    "    term_x = _stored_half(step) * Expression.constant(weights[i]) *"
    " trig[1]\n    term_y = _stored_half(step) *"
    " Expression.constant(weights[i]) * trig[0]\n"
)
"""The two reviewed term definitions."""

comptime _ACCUMULATIONS = "    x = x + term_x\n    y = y + term_y\n"
"""The two reviewed ideal accumulations."""


def _one_dump(body: String) raises -> String:
    """Return the joined dumps of one wrapper body.

    Args:
        body: Indented statements.

    Returns:
        The semicolon-joined JSON.

    Raises:
        Error: The wrapper is not the ideal subset.
    """
    var source = String(
        "def _spiral_expression[derivatives: Bool]() -> None:\n"
    )
    source += body
    var parser = _Parser()
    parser.load(source)
    parser.function()
    var items = parser.items(parser.list_field(parser.root, "body"))
    return parser.joined(items)


def _parse(source: String) raises -> _Parser:
    """Parse one ideal function.

    Args:
        source: The function source.

    Returns:
        The parser, positioned on that function.

    Raises:
        Error: The source is not one ideal function.
    """
    var parser = _Parser()
    parser.load(source)
    parser.function()
    return parser^


def _calls_match(args: List[String]) -> Bool:
    """Return whether `args` is the reviewed stored-half order.

    Args:
        args: The projected argument names.

    Returns:
        True for step, rate, step, step, rate.
    """
    if len(args) != 5:
        return False
    var joined = (
        args[0] + "," + args[1] + "," + args[2] + "," + args[3] + "," + args[4]
    )
    return joined == "step,rate,step,step,rate"


def projected_ideal_text(
    legacy: String, current: String, helper: String
) raises -> String:
    """Return the projected ideal graph as Python AST JSON.

    Args:
        legacy: The pinned legacy ideal spiral.
        current: The live ideal spiral.
        helper: The source from `def _stored_half[`.

    Returns:
        The compact JSON of the projected function.

    Raises:
        Error: The legacy digest, the helper, or the projected graph
        changed.
    """
    if sha256_hex(legacy.as_bytes()) != _LEGACY_SHA256:
        _fail("historical ideal source changed")
    stored_half_projection(helper)
    var left = _parse(legacy)
    var right = _parse(current)
    right.project()
    var args = List[String]()
    right.project_half(right.root, args)
    left.commute(left.root)
    if not _calls_match(args):
        _fail("expected exactly five reviewed stored-half calls")
    var left_dump = left.graph.dump(left.root)
    var right_dump = right.graph.dump(right.root)
    if left_dump != right_dump:
        _fail("ideal expression differs beyond reviewed half projection")
    return left_dump^


def projected_ideal_digest(
    legacy: String, current: String, helper: String
) raises -> String:
    """Return the SHA-256 of the projected ideal graph.

    Args:
        legacy: The pinned legacy ideal spiral.
        current: The live ideal spiral.
        helper: The source from `def _stored_half[`.

    Returns:
        The hex digest.

    Raises:
        Error: The legacy digest, the helper, or the projected graph
        changed.
    """
    return sha256_hex(projected_ideal_text(legacy, current, helper).as_bytes())
