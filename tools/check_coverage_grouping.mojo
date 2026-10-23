# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compile native and instrumented Boolean fixtures and compare exact behavior.

This is a separate integration check because test-tools needs no compiler.
Every built suite retains the five-second per-test limit. Build time is not
part of that limit. No device or external service is used.

    check_coverage_grouping --mojo .venv/bin/mojo

Run it from the repository root. `make test-coverage-tool` does.
"""

from std.collections import Dict
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._cli import absolute_path
from tools._process import ProcessResult, run_program
from tools.run_suite import result_errors, slow_tests

comptime _LEAF = 0
comptime _AND = 1
comptime _OR = 2
comptime _NOT = 3
comptime _ATOM = 4
comptime _CHOOSE = 5
comptime _EQ = 6
comptime _BOOLABLE = 7


struct Node(Copyable, ImplicitlyCopyable, Movable):
    """One node of an independent Boolean reference tree."""

    var op: Int
    """The operator, or `_LEAF`."""
    var index: Int
    """The leaf number when `op` is `_LEAF` or `_BOOLABLE`."""
    var left: Int
    """The first child, or -1."""
    var right: Int
    """The second child, or -1."""
    var third: Int
    """The third child of a conditional, or -1."""

    def __init__(
        out self, op: Int, index: Int, left: Int, right: Int, third: Int
    ):
        """Make a node.

        Args:
            op: The operator.
            index: The leaf number.
            left: The first child.
            right: The second child.
            third: The third child.
        """
        self.op = op
        self.index = index
        self.left = left
        self.right = right
        self.third = third


struct Step(Copyable, ImplicitlyCopyable, Movable):
    """One evaluation: its value, its order, and the probes it recorded."""

    var value: Bool
    """The Boolean result. Unused when `threw` is true."""
    var threw: Bool
    """True when a leaf raised the fixture exception."""
    var order: String
    """The leaf and boolable marks, in call order."""
    var probes: String
    """`slot:1` or `slot:0` entries separated by semicolons."""
    var slot: Int
    """The next probe slot."""

    def __init__(
        out self,
        value: Bool,
        threw: Bool,
        order: String,
        probes: String,
        slot: Int,
    ):
        """Make a step.

        Args:
            value: The Boolean result.
            threw: True when evaluation raised.
            order: The marks so far.
            probes: The recorded probes.
            slot: The next probe slot.
        """
        self.value = value
        self.threw = threw
        self.order = order
        self.probes = probes
        self.slot = slot


def _leaf(index: Int) -> Node:
    """Return a numbered leaf."""
    return Node(_LEAF, index, -1, -1, -1)


def _boolable(index: Int) -> Node:
    """Return a boolable leaf."""
    return Node(_BOOLABLE, index, -1, -1, -1)


def _unary(op: Int, child: Node) -> List[Node]:
    """Return a one-child tree, child first."""
    var nodes = List[Node]()
    nodes.append(child)
    nodes.append(Node(op, 0, 0, -1, -1))
    return nodes^


def _binary(op: Int, left: Node, right: Node) -> List[Node]:
    """Return a two-child tree."""
    var nodes = List[Node]()
    nodes.append(left)
    nodes.append(right)
    nodes.append(Node(op, 0, 0, 1, -1))
    return nodes^


def _one(node: Node) -> List[Node]:
    """Return a tree that holds one node."""
    var nodes = List[Node]()
    nodes.append(node)
    return nodes^


def _join(var prefix: List[Node], var child: List[Node]) -> List[Node]:
    """Append `child`, shifting its indexes by `len(prefix)`."""
    var base = len(prefix)
    for item in child:
        var left = item.left if item.left < 0 else item.left + base
        var right = item.right if item.right < 0 else item.right + base
        var third = item.third if item.third < 0 else item.third + base
        prefix.append(Node(item.op, item.index, left, right, third))
    return prefix^


def _wrap(op: Int, var child: List[Node]) -> List[Node]:
    """Append one operator over the root of `child`."""
    var root = len(child) - 1
    child.append(Node(op, 0, root, -1, -1))
    return child^


def _over(op: Int, var left: List[Node], var right: List[Node]) -> List[Node]:
    """Append one operator over two trees."""
    var left_root = len(left) - 1
    var nodes = _join(left^, right^)
    var right_root = len(nodes) - 1
    nodes.append(Node(op, 0, left_root, right_root, -1))
    return nodes^


def _choose(
    var condition: List[Node], var taken: List[Node], var other: List[Node]
) -> List[Node]:
    """Return a conditional expression tree."""
    var condition_root = len(condition) - 1
    var nodes = _join(condition^, taken^)
    var taken_root = len(nodes) - 1
    nodes = _join(nodes^, other^)
    var other_root = len(nodes) - 1
    nodes.append(Node(_CHOOSE, 0, condition_root, taken_root, other_root))
    return nodes^


def _atom(var child: List[Node]) -> List[Node]:
    """Return an opaque atom over `child`."""
    return _wrap(_ATOM, child^)


def cases() -> List[List[Node]]:
    """Return the independent Boolean trees, in fixture order.

    Returns:
        One tree for each source expression.
    """
    var trees = List[List[Node]]()
    trees.append(
        _over(_AND, _over(_OR, _one(_leaf(0)), _one(_leaf(1))), _one(_leaf(2)))
    )
    trees.append(
        _wrap(
            _NOT,
            _over(
                _AND,
                _one(_leaf(0)),
                _over(_OR, _one(_leaf(1)), _wrap(_NOT, _one(_leaf(2)))),
            ),
        )
    )
    trees.append(
        _over(
            _AND,
            _over(
                _OR, _one(_leaf(0)), _over(_AND, _one(_leaf(1)), _one(_leaf(2)))
            ),
            _wrap(_NOT, _wrap(_NOT, _one(_leaf(3)))),
        )
    )
    trees.append(
        _over(
            _OR,
            _over(_AND, _one(_leaf(0)), _one(_leaf(1))),
            _over(_AND, _wrap(_NOT, _one(_leaf(2))), _one(_leaf(3))),
        )
    )
    trees.append(
        _over(
            _OR,
            _over(
                _AND,
                _atom(_over(_OR, _one(_leaf(0)), _one(_leaf(1)))),
                _atom(_one(_leaf(2))),
            ),
            _atom(
                _over(
                    _EQ,
                    _over(_AND, _one(_leaf(3)), _one(_leaf(4))),
                    _one(_leaf(5)),
                )
            ),
        )
    )
    trees.append(
        _over(
            _OR,
            _wrap(_NOT, _one(_leaf(0))),
            _over(_AND, _one(_leaf(1)), _one(_leaf(2))),
        )
    )
    trees.append(
        _over(
            _AND,
            _over(_OR, _atom(_one(_leaf(0))), _one(_leaf(1))),
            _one(_leaf(2)),
        )
    )
    trees.append(_wrap(_NOT, _one(_leaf(0))))
    trees.append(
        _over(_OR, _over(_OR, _one(_leaf(0)), _one(_leaf(1))), _one(_leaf(2)))
    )
    trees.append(
        _atom(
            _choose(
                _one(_leaf(1)),
                _one(_leaf(0)),
                _over(_AND, _one(_leaf(2)), _one(_leaf(3))),
            )
        )
    )
    trees.append(
        _over(
            _AND,
            _atom(
                _choose(
                    _one(_leaf(2)),
                    _over(_AND, _one(_leaf(0)), _one(_leaf(1))),
                    _over(_OR, _one(_leaf(3)), _one(_leaf(4))),
                )
            ),
            _one(_leaf(5)),
        )
    )
    trees.append(
        _over(
            _OR,
            _atom(
                _choose(
                    _one(_leaf(1)),
                    _wrap(_NOT, _one(_leaf(0))),
                    _one(_leaf(2)),
                )
            ),
            _one(_leaf(3)),
        )
    )
    trees.append(_over(_OR, _one(_leaf(1)), _atom(_one(_leaf(0)))))
    trees.append(_over(_OR, _one(_leaf(1)), _atom(_one(_leaf(0)))))
    trees.append(
        _over(_AND, _one(_leaf(0)), _atom(_wrap(_NOT, _one(_leaf(1)))))
    )
    trees.append(_over(_AND, _one(_leaf(0)), _one(_leaf(1))))
    trees.append(_one(_leaf(0)))
    trees.append(_over(_OR, _one(_leaf(0)), _one(_leaf(1))))
    trees.append(_over(_AND, _one(_leaf(0)), _one(_leaf(1))))
    trees.append(
        _over(
            _OR,
            _wrap(_NOT, _one(_leaf(0))),
            _wrap(_NOT, _over(_OR, _one(_leaf(1)), _one(_leaf(2)))),
        )
    )
    trees.append(
        _over(
            _AND,
            _one(_leaf(0)),
            _over(_OR, _one(_leaf(1)), _one(_leaf(2))),
        )
    )
    trees.append(
        _over(_OR, _over(_AND, _one(_leaf(0)), _one(_leaf(1))), _one(_leaf(2)))
    )
    trees.append(
        _atom(
            _choose(
                _one(_leaf(1)),
                _one(_boolable(0)),
                _one(_boolable(0)),
            )
        )
    )
    return trees^


def _root(nodes: List[Node]) -> Int:
    """Return the index of a tree's root."""
    return len(nodes) - 1


def leaves(nodes: List[Node], id: Int) -> Int:
    """Return how many instrumented leaves a subtree has.

    Args:
        nodes: The tree.
        id: The subtree root.

    Returns:
        The leaf count. An atom and a boolable each count as one.
    """
    var node = nodes[id]
    if node.op == _LEAF or node.op == _ATOM or node.op == _BOOLABLE:
        return 1
    var total = 0
    if node.left >= 0:
        total += leaves(nodes, node.left)
    if node.right >= 0:
        total += leaves(nodes, node.right)
    if node.third >= 0:
        total += leaves(nodes, node.third)
    return total


def _bit(mask: Int, index: Int) -> Bool:
    """Return whether bit `index` of `mask` is set."""
    return (mask & (1 << index)) != 0


def _probe(probes: String, slot: Int, value: Bool) -> String:
    """Append one probe."""
    return probes + String(slot) + (":1;" if value else ":0;")


def evaluate(
    nodes: List[Node],
    id: Int,
    mask: Int,
    fail: Int,
    order: String,
    probes: String,
    slot: Int,
    record: Bool,
) -> Step:
    """Evaluate one reference tree the way the fixture short-circuits.

    Args:
        nodes: The tree.
        id: The subtree root.
        mask: The six truth bits.
        fail: The leaf that raises, or -1.
        order: The marks already recorded.
        probes: The probes already recorded.
        slot: The next probe slot.
        record: True to record probes and advance `slot`.

    Returns:
        The result. `threw` is true when a leaf raised.
    """
    var node = nodes[id]
    if node.op == _LEAF or node.op == _BOOLABLE:
        var mark = "b" if node.op == _BOOLABLE else String(node.index)
        var next_order = order + mark
        if node.op == _LEAF and node.index == fail:
            return Step(False, True, next_order, probes, slot)
        var value = _bit(mask, node.index)
        if not record:
            return Step(value, False, next_order, probes, slot)
        return Step(
            value, False, next_order, _probe(probes, slot, value), slot + 1
        )
    if node.op == _CHOOSE:
        var condition = evaluate(
            nodes, node.left, mask, fail, order, String(), 0, False
        )
        if condition.threw:
            return condition
        var chosen = node.right if condition.value else node.third
        return evaluate(
            nodes, chosen, mask, fail, condition.order, String(), 0, False
        )
    if node.op == _ATOM:
        var inner = evaluate(
            nodes, node.left, mask, fail, order, String(), 0, False
        )
        if inner.threw:
            return Step(False, True, inner.order, probes, slot)
        if not record:
            return Step(inner.value, False, inner.order, probes, slot)
        return Step(
            inner.value,
            False,
            inner.order,
            _probe(probes, slot, inner.value),
            slot + 1,
        )
    if node.op == _NOT:
        var inner = evaluate(
            nodes, node.left, mask, fail, order, probes, slot, record
        )
        if inner.threw:
            return inner
        return Step(
            not inner.value, False, inner.order, inner.probes, inner.slot
        )
    var left = evaluate(
        nodes, node.left, mask, fail, order, probes, slot, record
    )
    if left.threw:
        return left
    var stop = (node.op == _AND and not left.value) or (
        node.op == _OR and left.value
    )
    if stop:
        var skipped = left.slot
        if record:
            skipped += leaves(nodes, node.right)
        return Step(left.value, False, left.order, left.probes, skipped)
    var right = evaluate(
        nodes,
        node.right,
        mask,
        fail,
        left.order,
        left.probes,
        left.slot,
        record,
    )
    if right.threw:
        return right
    var value = left.value == right.value if node.op == _EQ else right.value
    return Step(value, False, right.order, right.probes, right.slot)


def _expressions() -> List[String]:
    """Return the fixture expressions, with `P0` through `P5` still in them."""
    var lines = List[String]()
    lines.append("(((P0 or P1) and P2))")
    lines.append("not (P0 and (P1 or not P2))")
    lines.append("(P0 or P1 and P2) and not not P3")
    lines.append(
        "(\n            (P0 and P1)  # first group\n            or (not P2 and"
        " P3)\n        )"
    )
    lines.append(
        '(identity(P0 or P1, "and or") and values[Int(P2)] or (P3 and P4)'
        " == P5)"
    )
    lines.append("not(P0)or((P1)and(P2))")
    lines.append(
        '((quoted(mask, order, fail) == "\\" and #:( or [") or P1) and P2'
    )
    lines.append("(((not (P0))))")
    lines.append("(P0 or P1 or P2)")
    lines.append("P0 if P1 else P2 and P3")
    lines.append("((P0 and P1) if P2 else (P3 or P4)) and P5")
    lines.append("(not P0 if P1 else P2) or P3")
    lines.append('(P1 or triple(mask, order, fail) == """hello" and word""")')
    lines.append(
        '(P1 or triple_lines(mask, order, fail) == """hello"\n# ) and'
        ' or\nworld""")'
    )
    lines.append("P0 and (1 not in member_values(mask, order, fail))")
    lines.append("scalar_bool(P0) and P1")
    lines.append("optional_value(P0)")
    lines.append("optional_custom(P0, order) or P1")
    lines.append("list_custom(P0, order) and P1")
    lines.append("not P0 or not (optional_value(P1) or P2)")
    lines.append("optional_value(P0) and (optional_value(P1) or P2)")
    lines.append("text_value(P0) and Int(P1) or list_value(P2)")
    lines.append("borrowed if P1 else borrowed")
    return lines^


def _replace_marks(expression: String) -> String:
    """Replace `P0` through `P5` with `mark` calls."""
    var text = expression
    var index = 0
    while index < 6:
        var name = "P" + String(index)
        var call = "mark(mask, " + String(index) + ", order, fail)"
        text = text.replace(name, call)
        index += 1
    return text


def fixture_source() -> Tuple[String, List[Int]]:
    """Return the fixture source and the line of each decision.

    Returns:
        The source, and one 1-based line number per case.
    """
    var text = """from std.os import getenv
from std.testing import TestSuite


def mark(mask: Int, index: Int, mut order: String, fail: Int) raises -> Bool:
    order += String(index)
    if index == fail:
        raise Error("fixture exception")
    return (mask & (1 << index)) != 0


@fieldwise_init
struct Observable(Movable, Boolable):
    var value: Bool
    var order: Pointer[String, MutUntrackedOrigin]

    def __bool__(self) -> Bool:
        self.order[] += "b"
        return self.value


def observable(value: Bool, mut order: String) -> Observable:
    return Observable(value, Pointer(to=order).unsafe_origin_cast[MutUntrackedOrigin]())


def scalar_bool(value: Bool) -> SIMD[DType.bool, 1]:
    return SIMD[DType.bool, 1](value)


def optional_value(value: Bool) -> Optional[List[Float64]]:
    if value:
        return List[Float64]([1.0])
    return None


def optional_custom(value: Bool, mut order: String) -> Optional[Observable]:
    if value:
        return observable(False, order)
    return None


def list_custom(value: Bool, mut order: String) -> List[Observable]:
    var items = List[Observable]()
    if value:
        items.append(observable(False, order))
    return items^


def text_value(value: Bool) -> String:
    return "x" if value else ""


def list_value(value: Bool) -> List[Int]:
    if value:
        return [1]
    return []


def identity(value: Bool, text: String) -> Bool:
    _ = text
    return value


def member_values(mask: Int, mut order: String, fail: Int) raises -> List[Int]:
    return [Int(mark(mask, 1, order, fail)), 2]


def triple(mask: Int, mut order: String, fail: Int) raises -> String:
    if mark(mask, 0, order, fail):
        return 'hello" and word'
    return "different"


def triple_lines(mask: Int, mut order: String, fail: Int) raises -> String:
    if mark(mask, 0, order, fail):
        return \"\"\"hello\"
# ) and or
world\"\"\"
    return "different"


def quoted(mask: Int, mut order: String, fail: Int) raises -> String:
    if mark(mask, 0, order, fail):
        return '\" and #:( or ['
    return "different"
"""
    var decisions = List[Int]()
    var expressions = _expressions()
    var number = 0
    for expression in expressions:
        var body = _replace_marks(expression)
        text += (
            "\n\ndef case_"
            + String(number)
            + "(mask: Int, fail: Int) raises:\n"
        )
        text += '    var order = String("")\n'
        text += "    var values: List[Bool] = [False, True]\n"
        text += "    _ = values\n"
        text += "    var borrowed = observable((mask & 1) != 0, order)\n"
        text += "    try:\n"
        decisions.append(len(text.splitlines()) + 1)
        text += "        if " + body + ":\n"
        text += (
            '            print("RESULT", '
            + String(number)
            + ', mask, fail, "T", order)\n'
        )
        text += "        else:\n"
        text += (
            '            print("RESULT", '
            + String(number)
            + ', mask, fail, "F", order)\n'
        )
        text += "    except error:\n"
        text += (
            '        print("RESULT", '
            + String(number)
            + ', mask, fail, "E", order, String(error))\n'
        )
        text += "    _ = borrowed.value\n"
        number += 1
    text += "\n\ndef test_semantics() raises:\n"
    text += '    var fail = Int(getenv("THREEMOJO_GROUPING_FAIL", "-1"))\n'
    text += "    for mask in range(64):\n"
    number = 0
    while number < len(expressions):
        text += "        case_" + String(number) + "(mask, fail)\n"
        number += 1
    text += "\n\ndef main() raises:\n"
    text += "    TestSuite.discover_tests[__functions_in_module()]().run()\n"
    return (text, decisions^)


def _number(text: String) -> Int:
    """Return the integer value of an ASCII digit string."""
    var value = 0
    for byte in text.as_bytes():
        value = value * 10 + Int(byte) - 48
    return value


def _probes(text: String) -> List[Tuple[Int, Bool]]:
    """Return the probes encoded by `evaluate`."""
    var found = List[Tuple[Int, Bool]]()
    var rest = text
    while rest.byte_length() > 0:
        var end = rest.find(";")
        if end < 0:
            break
        var piece = String(rest[byte=:end])
        var colon = piece.find(":")
        var slot = _number(String(piece[byte=:colon]))
        var flag = String(piece[byte = colon + 1 :]) == "1"
        found.append((slot, flag))
        var next = String(rest[byte = end + 1 :])
        rest = next
    return found^


def expected_rows(fail: Int) -> List[String]:
    """Return the `RESULT` lines of one throwing position.

    Args:
        fail: The leaf that raises, or -1.

    Returns:
        One line for each mask and case, in fixture order.
    """
    var rows = List[String]()
    var trees = cases()
    var mask = 0
    while mask < 64:
        var number = 0
        while number < len(trees):
            var step = evaluate(
                trees[number],
                _root(trees[number]),
                mask,
                fail,
                String(),
                String(),
                0,
                True,
            )
            var outcome = "E" if step.threw else ("T" if step.value else "F")
            var suffix = " fixture exception" if step.threw else ""
            rows.append(
                "RESULT "
                + String(number)
                + " "
                + String(mask)
                + " "
                + String(fail)
                + " "
                + outcome
                + " "
                + step.order
                + suffix
            )
            number += 1
        mask += 1
    return rows^


def expected_records(
    fail: Int, decisions: List[Int]
) raises -> Tuple[List[String], List[String]]:
    """Return the hit lines and the vector lines for one throwing position.

    Args:
        fail: The leaf that raises, or -1.
        decisions: The source line of each case.

    Returns:
        The hits and the vectors, grouped by repeating every case inside
        each mask. Each group is joined by newlines.
    """
    var hits = List[String]()
    var vectors = List[String]()
    var trees = cases()
    var number = 0
    while number < len(trees):
        hits.append(String())
        vectors.append(String())
        number += 1
    var mask = 0
    while mask < 64:
        number = 0
        while number < len(trees):
            var step = evaluate(
                trees[number],
                _root(trees[number]),
                mask,
                fail,
                String(),
                String(),
                0,
                True,
            )
            var line = decisions[number]
            var count = leaves(trees[number], _root(trees[number]))
            if count > 1:
                for pair in _probes(step.probes):
                    hits[number] += (
                        "COVLINE:fixture:"
                        + String(line)
                        + "."
                        + String(pair[0])
                        + ":"
                        + ("T" if pair[1] else "F")
                        + "\n"
                    )
            if not step.threw:
                var outcome = "T" if step.value else "F"
                hits[number] += (
                    "COVLINE:fixture:" + String(line) + ":" + outcome + "\n"
                )
                if count > 1:
                    var states = Dict[Int, Bool]()
                    for pair in _probes(step.probes):
                        states[pair[0]] = pair[1]
                    var vector = String()
                    var index = 0
                    while index < count:
                        if index in states:
                            vector += "T" if states[index] else "F"
                        else:
                            vector += "-"
                        index += 1
                    vectors[number] += (
                        "COVEVAL2:fixture:"
                        + String(line)
                        + ":"
                        + outcome
                        + ":"
                        + vector
                        + ";\n"
                    )
            number += 1
        mask += 1
    return (hits^, vectors^)


def _must(
    command: List[String], seconds: Float64, directory: String = ""
) raises -> ProcessResult:
    """Run a command and refuse a non-zero status or a time limit."""
    var result = run_program(
        command, seconds, merge_errors=False, directory=directory
    )
    if result.timed_out or result.status != 0:
        raise Error(result.output + "\n" + result.errors)
    return result^


def _with_env(prefix: List[String], command: List[String]) -> List[String]:
    """Return `env` plus `prefix` plus `command`."""
    var words = List[String]()
    words.append("env")
    for word in prefix:
        words.append(word)
    for word in command:
        words.append(word)
    return words^


def _rows(stdout: String) -> List[String]:
    """Return the `RESULT` lines."""
    var rows = List[String]()
    for line in stdout.splitlines():
        var text = String(line)
        if text.startswith("RESULT "):
            rows.append(text)
    return rows^


def _before_suite(stdout: String) -> String:
    """Return the program output before the test runner banner."""
    var at = stdout.find("\nRunning ")
    var head = stdout if at < 0 else String(stdout[byte=:at])
    var copy = head
    while copy.startswith("\n") or copy.startswith(" "):
        var next = String(copy[byte=1:])
        copy = next
    while copy.endswith("\n") or copy.endswith(" "):
        var next = String(copy[byte = : copy.byte_length() - 1])
        copy = next
    return copy


def _same(actual: List[String], expected: List[String]) -> Bool:
    """Return whether two lists hold the same lines in order."""
    if len(actual) != len(expected):
        return False
    var index = 0
    while index < len(actual):
        if actual[index] != expected[index]:
            return False
        index += 1
    return True


def _either(raw: String, first: String, second: String) -> String:
    """Return the lines that start with either prefix, in file order."""
    var text = String()
    for line in raw.splitlines():
        var row = String(line)
        if row.startswith(first) or row.startswith(second):
            text += row + "\n"
    return text


def _matching(raw: String, prefix: String) -> String:
    """Return the lines that start with `prefix`, each followed by a newline."""
    var text = String()
    for line in raw.splitlines():
        var row = String(line)
        if row.startswith(prefix):
            text += row + "\n"
    return text


def check_semantics(mojo: String) raises:
    """Compare the Boolean fixture with the independent reference tree.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If the native output, the records, or the vectors differ.
    """
    var root = absolute_path(".")
    var compiler = absolute_path(mojo)
    var work = mkdtemp(prefix="threemojo-grouping-")
    try:
        var native = work + "/native"
        var rewritten = work + "/rewritten"
        _ = _must(["mkdir", "-p", native, rewritten], 10)
        _ = _must(["cp", "-a", root + "/coverage", native + "/coverage"], 30)
        _ = _must(["cp", "-a", root + "/coverage", rewritten + "/coverage"], 30)
        for folder in [native, rewritten]:
            var built = folder + "/coverage/build"
            if Path(built).exists():
                _ = _must(["rm", "-rf", built], 10)
        var made = fixture_source()
        Path(native + "/fixture.mojo").write_text(made[0])
        var build = work + "/build_cli"
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                root,
                root + "/coverage/build_cli.mojo",
                "-o",
                build,
            ],
            180,
        )
        _ = _must([build, rewritten, "fixture.mojo"], 60, native)
        var manifest = Path(rewritten + "/manifest.txt").read_text()
        var trees = cases()
        var number = 0
        while number < len(trees):
            var count = leaves(trees[number], _root(trees[number]))
            var width = count if count > 1 else 0
            var line = made[1][number]
            for kind in ["C", "M"]:
                var wanted = String()
                var index = 0
                while index < width:
                    if wanted.byte_length() > 0:
                        wanted += "\n"
                    wanted += (
                        kind + " fixture " + String(line) + " " + String(index)
                    )
                    index += 1
                var actual = String()
                var prefix = kind + " fixture " + String(line) + " "
                for row in manifest.splitlines():
                    var text = String(row)
                    if text.startswith(prefix):
                        if actual.byte_length() > 0:
                            actual += "\n"
                        actual += text
                if actual != wanted:
                    raise Error("manifest changed for case " + String(number))
            number += 1
        var binaries = List[String]()
        for folder in [native, rewritten]:
            var binary = folder + "/suite"
            _ = _must(
                [
                    compiler,
                    "build",
                    "-Werror",
                    "-I",
                    folder,
                    folder + "/fixture.mojo",
                    "-o",
                    binary,
                ],
                180,
                folder,
            )
            binaries.append(binary)
        var fail = -1
        while fail < 6:
            var expected = expected_rows(fail)
            var records = expected_records(fail, made[1])
            var raw = String()
            var which = 0
            for binary in binaries:
                var temp = mkdtemp(prefix="threemojo-test-")
                var ran = _must(
                    _with_env(
                        [
                            "TMPDIR=" + temp,
                            "THREEMOJO_TEST_TMPDIR=" + temp,
                            "THREEMOJO_GROUPING_FAIL=" + String(fail),
                        ],
                        [binary],
                    ),
                    10,
                )
                _ = _must(["rm", "-rf", temp], 10)
                if (
                    len(result_errors(ran.output)) > 0
                    or len(slow_tests(ran.output, 5.0)) > 0
                ):
                    raise Error(ran.output)
                if _before_suite(ran.output) != "\n".join(expected):
                    raise Error(ran.output)
                if not _same(_rows(ran.output), expected):
                    raise Error("result rows changed at fail " + String(fail))
                if which == 1:
                    raw = ran.errors
                which += 1
            number = 0
            while number < len(made[1]):
                var line = String(made[1][number])
                var hits = _either(
                    raw,
                    "COVLINE:fixture:" + line + ":",
                    "COVLINE:fixture:" + line + ".",
                )
                if hits != records[0][number]:
                    raise Error(
                        "hits changed " + String(number) + " " + String(fail)
                    )
                if (
                    _matching(raw, "COVEVAL2:fixture:" + line + ":")
                    != records[1][number]
                ):
                    raise Error(
                        "vectors changed " + String(number) + " " + String(fail)
                    )
                number += 1
            fail += 1
        print(
            "PASS: "
            + String(len(cases()))
            + " native/instrumented Boolean cases, 64 truth assignments,"
            " normal and 6 throwing positions"
        )
    finally:
        _ = run_program(["rm", "-rf", work], 30)


def repeated_truth_source(probe: Bool) -> String:
    """Return the program that converts one Boolable value twice.

    Args:
        probe: True to convert through the coverage leaf helper.

    Returns:
        The Mojo source.
    """
    var text = String()
    if probe:
        text += (
            "from coverage.runtime import buffer, begin, leaf, finish,"
            " _borrowed\n"
        )
        text += "from std.reflection import reflect\n\n"
    text += """@fieldwise_init
struct Changing(Boolable):
    var count: Pointer[Int, MutUntrackedOrigin]

    @inline(.never)
    def __bool__(self) -> Bool:
        self.count[] += 1
        return self.count[] == 1

def main():
    var count = 0
    var kept = Changing(Pointer(to=count).unsafe_origin_cast[MutUntrackedOrigin]())
"""
    if probe:
        text += """    var values = buffer()
    _ = begin(values, 2)
    var observed = leaf(kept, values, "repeat:1.0", 0)
    comptime assert _borrowed(reflect[type_of(observed)].name())
"""
    var target = "kept"
    if probe:
        target = "observed"
    text += '    print("FIRST", ' + target + ".__bool__())\n"
    text += '    print("SECOND", ' + target + ".__bool__())\n"
    if probe:
        text += "    _ = observed^\n"
    text += '    print("COUNT", count, kept.count[])\n'
    if probe:
        text += """    _ = leaf(True, values, "repeat:1.1", 1)
    _ = finish(False, values, "repeat:1")
"""
    return text


def _without_quotes(body: String) -> String:
    """Remove triple-quoted docstrings the way the Python checker does."""
    var out = String()
    var rest = body
    while True:
        var at = rest.find('"""')
        if at < 0:
            out += rest
            return out
        var head = String(rest[byte=:at])
        out += head
        var after = String(rest[byte = at + 3 :])
        var end = after.find('"""')
        if end < 0:
            return out
        var next = String(after[byte = end + 3 :])
        rest = next


def _helper_body(text: String, name: String) raises -> String:
    """Return one coverage helper with comments and docstrings removed."""
    var lines = text.splitlines()
    var start = -1
    var index = 0
    var open_def = "def " + name + "("
    var generic_def = "def " + name + "["
    for line in lines:
        var row = String(line)
        if row.startswith(open_def) or row.startswith(generic_def):
            if start >= 0:
                raise Error("ambiguous helper " + name)
            start = index
        index += 1
    if start < 0:
        raise Error("missing helper " + name)
    var end = start + 1
    while end < len(lines):
        var row = String(lines[end])
        if row.byte_length() == 0:
            end += 1
            continue
        var lead = row.as_bytes()[0]
        if lead == 32 or lead == 41 or lead == 93:
            end += 1
            continue
        break
    var body = String()
    index = start
    while index < end:
        if body.byte_length() > 0:
            body += "\n"
        body += String(lines[index])
        index += 1
    body = _without_quotes(body)
    var stripped = String()
    for line in body.splitlines():
        var row = String(line)
        var mark = row.find("#")
        if mark >= 0:
            var cut = String(row[byte=:mark])
            row = cut
        if stripped.byte_length() > 0:
            stripped += "\n"
        stripped += row
    return stripped


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs in `text`."""
    var count = 0
    var rest = text
    var width = needle.byte_length()
    while True:
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        var next = String(rest[byte = at + width :])
        rest = next


def _names_fixture() -> String:
    """Return the mixed pure-operand fixture."""
    return """comptime READS = SIMD[DType.int32, 4](1, 2, 3, 4)


def flag(value: Int) -> Bool:
    return value == 7 or value == 9


def check(
    value: Int, items: List[Int], text: String, maybe: Optional[Int]
) -> Int:
    var total = 0
    if flag(value) or READS.eq(Int32(value)).reduce_or():
        total += 1
    if READS.eq(Int32(value)).reduce_or() and value:
        total += 2
    if text or value and flag(value):
        total += 4
    if items or maybe and flag(value):
        total += 8
    if not flag(value) and READS.eq(Int32(value)).reduce_or() or text:
        total += 16
    return total


def main():
    for value in range(12):
        var items = [value] if value % 2 == 1 else List[Int]()
        var text = String("x") if value % 3 == 1 else String("")
        var maybe = Optional(value) if value % 4 != 0 else Optional[Int](None)
        print(value, check(value, items, text, maybe))
"""


def check_compile_time_names(mojo: String) raises:
    """Refuse compile-time string search and compare the pure name helpers.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If a helper searches at compile time or a result differs.
    """
    var root = absolute_path(".")
    var compiler = absolute_path(mojo)
    var source = Path(root + "/coverage/runtime.mojo").read_text()
    for name in [
        "node",
        "_pure",
        "_starts",
        "_bracket",
        "_optional",
        "_borrowed",
        "_standard_string_optional",
        "_optional_lifecycle",
    ]:
        var body = _helper_body(source, name)
        if body.find(".startswith(") >= 0 or body.find(".find(") >= 0:
            raise Error(name + " evaluates a string search at compile time")
    var work = mkdtemp(prefix="threemojo-names-")
    try:
        var native = work + "/native"
        var rewritten = work + "/rewritten"
        _ = _must(["mkdir", "-p", native, rewritten], 10)
        _ = _must(["cp", "-a", root + "/coverage", native + "/coverage"], 30)
        _ = _must(["cp", "-a", root + "/coverage", rewritten + "/coverage"], 30)
        Path(native + "/names.mojo").write_text(_names_source())
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                native,
                native + "/names.mojo",
                "-o",
                work + "/names",
            ],
            120,
        )
        var output = _must([work + "/names"], 5).output
        var rows = output.splitlines()
        if len(rows) == 0 or String(rows[0]) != "FIXED True":
            raise Error(output)
        var starts = 0
        var brackets = 0
        var saw_true = False
        var saw_false = False
        for line in rows:
            var row = String(line)
            if row.startswith("STARTS "):
                starts += 1
                var parts = row.split(" ")
                if String(parts[1]) != String(parts[2]):
                    raise Error(row)
                if String(parts[1]) == "True":
                    saw_true = True
                elif String(parts[1]) == "False":
                    saw_false = True
                else:
                    raise Error(row)
            elif row.startswith("BRACKET "):
                brackets += 1
                var parts = row.split(" ")
                if String(parts[1]) != String(parts[2]):
                    raise Error(row)
        if starts != 16 * 16 or brackets != 16 or not saw_true or not saw_false:
            raise Error(output)
        var types = 0
        for line in rows:
            var row = String(line)
            if not row.startswith("TYPE "):
                continue
            types += 1
            var parts = row.split(" ")
            var label = String(parts[1])
            var scalar = String(parts[2])
            var pure = String(parts[3])
            var optional = String(parts[4])
            var is_scalar = (
                label == "Bool"
                or label == "Scalar[bool]"
                or label == "Int"
                or label == "String"
            )
            if (scalar == "True") != is_scalar:
                raise Error(row)
            if scalar == "True" and (pure != "True" or optional != "False"):
                raise Error(row)
        if types != 11:
            raise Error("expected 11 type rows")
        var build = work + "/build_cli"
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                root,
                root + "/coverage/build_cli.mojo",
                "-o",
                build,
            ],
            180,
        )
        Path(native + "/names_fixture.mojo").write_text(_names_fixture())
        _ = _must([build, rewritten, "names_fixture.mojo"], 60, native)
        var instrumented = Path(rewritten + "/names_fixture.mojo").read_text()
        if _count(instrumented, "_cov_eval_node[") != 8:
            raise Error("instrumented name fixture changed")
        var native_out = String()
        var instrumented_out = String()
        for pair in ["native", "instrumented"]:
            var folder = native
            if pair == "instrumented":
                folder = rewritten
            var binary = work + "/names-fixture-" + pair
            _ = _must(
                [
                    compiler,
                    "build",
                    "--num-threads",
                    "1",
                    "-Werror",
                    "-I",
                    folder,
                    folder + "/names_fixture.mojo",
                    "-o",
                    binary,
                ],
                120,
            )
            var ran = _must([binary], 5)
            if pair == "native":
                native_out = ran.output
            else:
                instrumented_out = ran.output
        if native_out != instrumented_out or len(native_out.splitlines()) != 12:
            raise Error(native_out)
        print(
            "PASS: "
            + String(starts + brackets)
            + " byte-exact name-test results and "
            + String(types)
            + " scalar identities"
        )
    finally:
        _ = run_program(["rm", "-rf", work], 30)


def _names_source() -> String:
    """Return the compile-time name probe."""
    return """from coverage.runtime import _bracket, _optional, _pure, _scalar, _starts
from std.reflection import reflect

def names() -> List[StaticString]:
    var result = List[StaticString]()
    result.append("")
    result.append("[")
    result.append("L")
    result.append("List[")
    result.append("List[Int]")
    result.append("Lis")
    result.append("Optional[")
    result.append("Optional[Int]")
    result.append("Optional")
    result.append("std.collections.optional.Optional[Int]")
    result.append("std.collections.optional.Optional[")
    result.append("Bool")
    result.append("SIMD[DType.bool, 1]")
    result.append("a[b[c")
    result.append("é[x")
    result.append("é")
    return result^

comptime FIXED = (
    _starts("List[Int]", "List[")
    and not _starts("Lis", "List[")
    and _starts("x", "")
    and _bracket("a[b[c") == 2
    and _bracket("abc") == 0
)


def kind[T: AnyType](label: StaticString):
    comptime name = reflect[T].name()
    print("TYPE", label, _scalar[T], _pure(name), _optional(name))


def main():
    print("FIXED", FIXED)
    var all = names()
    for name in all:
        print("BRACKET", _bracket(name), name.find("[") + 1)
        for prefix in all:
            print("STARTS", _starts(name, prefix), name.startswith(prefix))
    kind[Bool]("Bool")
    kind[Scalar[DType.bool]]("Scalar[bool]")
    kind[Int]("Int")
    kind[String]("String")
    kind[Int32]("Int32")
    kind[Float64]("Float64")
    kind[StaticString]("StaticString")
    kind[SIMD[DType.bool, 4]]("SIMD[bool,4]")
    kind[List[Int]]("List[Int]")
    kind[Optional[Int]]("Optional[Int]")
    kind[Optional[Bool]]("Optional[Bool]")
"""


def check_repeated_truth(mojo: String) raises:
    """Require native and borrowed repeated truth, then refuse the `?` vector.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If the output, the records, or the report differ.
    """
    var root = absolute_path(".")
    var compiler = absolute_path(mojo)
    var work = mkdtemp(prefix="threemojo-repeat-")
    try:
        var expected = "FIRST True\nSECOND False\nCOUNT 2 2\n"
        var stderr_text = String()
        for probe in [False, True]:
            var name = "repeat-native"
            if probe:
                name = "repeat-probe"
            var path = work + "/" + name + ".mojo"
            Path(path).write_text(repeated_truth_source(probe))
            var include = List[String]()
            include.append(compiler)
            include.append("build")
            include.append("-Werror")
            if probe:
                include.append("-I")
                include.append(root)
            include.append(path)
            include.append("-o")
            include.append(work + "/" + name)
            _ = _must(include, 180)
            var ran = _must([work + "/" + name], 5)
            if ran.output != expected:
                raise Error(name + "\n" + ran.output)
            if not probe and ran.errors.byte_length() > 0:
                raise Error(ran.errors)
            if probe:
                stderr_text = ran.errors
        var records = (
            "COVLINE:repeat:1.0:T\n"
            "COVLINE:repeat:1.0:F\n"
            "COVLINE:repeat:1.1:T\n"
            "COVLINE:repeat:1:F\n"
            "COVEVAL2:repeat:1:F:?T;\n"
        )
        if stderr_text != records:
            raise Error(stderr_text)
        var refused = False
        for line in stderr_text.splitlines():
            var row = String(line)
            if row.startswith("COVEVAL2:") and row.find("?") >= 0:
                refused = True
        if not refused:
            raise Error("the reducer accepted an inconsistent vector")
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                root,
                root + "/coverage/report_cli.mojo",
                "-o",
                work + "/report",
            ],
            180,
        )
        Path(work + "/repeat-manifest.txt").write_text(
            "B repeat 1\nC repeat 1 0\nM repeat 1 0\nC repeat 1 1\nM repeat"
            " 1 1\n"
        )
        Path(work + "/repeat-raw.txt").write_text(stderr_text)
        var report = run_program(
            [
                work + "/report",
                work + "/repeat-manifest.txt",
                work + "/repeat-raw.txt",
            ],
            5,
            merge_errors=False,
        )
        if (
            report.status == 0
            or (report.output + report.errors).find(
                "Inconsistent repeated truth conversion"
            )
            < 0
        ):
            raise Error(report.output + report.errors)
        print("PASS: repeated truth stays borrowed and the ? vector is refused")
    finally:
        _ = run_program(["rm", "-rf", work], 30)


def main() raises:
    """Compare the Boolean grouping fixture from the command line."""
    var mojo = ".venv/bin/mojo"
    var given = argv()
    var index = 1
    while index < len(given):
        var word = String(given[index])
        if word == "--mojo":
            if index + 1 >= len(given):
                print(
                    "check_coverage_grouping: --mojo needs a value",
                    file=stderr,
                )
                exit(2)
            mojo = String(given[index + 1])
            index += 2
            continue
        print("check_coverage_grouping: unknown argument " + word, file=stderr)
        exit(2)
    try:
        check_semantics(mojo)
        check_compile_time_names(mojo)
        check_repeated_truth(mojo)
    except error:
        print(String(error), file=stderr)
        exit(1)
