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

from std.collections import Dict, Set
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


def reduce_text(text: String) -> String:
    """Return distinct hits and complete vectors, in first-seen order.

    Args:
        text: The raw standard error.

    Returns:
        The reduced stream. A repeated hit or vector is omitted.
    """
    var seen_hits = Set[String]()
    var seen_vectors = Set[String]()
    var out = String()
    for line in text.splitlines():
        var row = String(line)
        if row.startswith("COVLINE:"):
            if not (row in seen_hits):
                seen_hits.add(row)
                out += row + "\n"
        elif row.startswith("COVEVAL2:"):
            if not (row in seen_vectors):
                seen_vectors.add(row)
                out += row + "\n"
        else:
            out += row + "\n"
    return out


def _analyzer_source() -> String:
    """Return the program that prints parsed coverage traces."""
    return """from coverage.mcdc import parse_traces, is_mcdc_covered
from std.pathlib import Path
from std.sys import argv

def main() raises:
    var traces = parse_traces(Path(String(argv()[1])).read_text())
    for trace in traces:
        print(trace.id)
        for evaluation in trace.evaluations:
            print(evaluation.values, evaluation.outcome)
        for index in range(6):
            print(index, is_mcdc_covered(trace, index))
"""


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
            Path(work + "/raw-" + String(fail) + ".txt").write_text(raw)
            Path(work + "/reduced-" + String(fail) + ".txt").write_text(
                reduce_text(raw)
            )
            if fail == -1:
                Path(work + "/raw.txt").write_text(raw)
                Path(work + "/reduced.txt").write_text(reduce_text(raw))
            fail += 1
        Path(native + "/analyze.mojo").write_text(_analyzer_source())
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                native,
                native + "/analyze.mojo",
                "-o",
                work + "/analyze",
            ],
            180,
        )
        fail = -1
        while fail < 6:
            var raw_report = _must(
                [
                    work + "/analyze",
                    work + "/raw-" + String(fail) + ".txt",
                ],
                10,
            )
            var reduced_report = _must(
                [
                    work + "/analyze",
                    work + "/reduced-" + String(fail) + ".txt",
                ],
                10,
            )
            if raw_report.output != reduced_report.output:
                raise Error(
                    "raw/reduced Mojo traces differ at throwing leaf "
                    + String(fail)
                )
            fail += 1
        var line = made[1][8]
        var negative = (
            "COVLINE:fixture:"
            + String(line)
            + ".0:F\nCOVLINE:fixture:"
            + String(line)
            + ".1:F\nCOVLINE:fixture:"
            + String(line)
            + ".2:F\nCOVLINE:fixture:"
            + String(line)
            + ":F\nCOVEVAL2:fixture:"
            + String(line)
            + ":F:FFF;\nCOVLINE:fixture:"
            + String(line)
            + ".0:T\nCOVLINE:fixture:"
            + String(line)
            + ":T\nCOVEVAL2:fixture:"
            + String(line)
            + ":T:T--;\n"
        )
        Path(work + "/negative.txt").write_text(negative)
        var negative_manifest = "B fixture " + String(line) + "\n"
        var slot = 0
        while slot < 3:
            negative_manifest += (
                "C fixture " + String(line) + " " + String(slot) + "\n"
            )
            negative_manifest += (
                "M fixture " + String(line) + " " + String(slot) + "\n"
            )
            slot += 1
        Path(work + "/negative-manifest.txt").write_text(negative_manifest)
        var report_bin = work + "/report"
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                root,
                root + "/coverage/report_cli.mojo",
                "-o",
                report_bin,
            ],
            180,
        )
        var selected = String()
        for row in manifest.splitlines():
            var entry = String(row)
            var parts = entry.split(" ")
            if len(parts) < 3:
                continue
            var kind = String(parts[0])
            if kind != "B" and kind != "C" and kind != "M":
                continue
            var decision = _number(String(parts[2]))
            var kept = False
            for item in made[1]:
                if item == decision:
                    kept = True
            if kept:
                selected += entry + "\n"
        Path(work + "/decision-manifest.txt").write_text(selected)
        _ = _must(
            [report_bin, work + "/decision-manifest.txt", work + "/raw.txt"],
            10,
        )
        _ = _must(
            [
                report_bin,
                work + "/decision-manifest.txt",
                work + "/reduced.txt",
            ],
            10,
        )
        var negative_report = run_program(
            [
                report_bin,
                work + "/negative-manifest.txt",
                work + "/negative.txt",
            ],
            10,
            merge_errors=False,
        )
        if negative_report.status == 0:
            raise Error("negative report was accepted")
        var negative_text = negative_report.output + negative_report.errors
        if (
            negative_text.find("condition 1:") < 0
            or negative_text.find("condition 2:") < 0
        ):
            raise Error(negative_text)
        Path(work + "/branch-manifest.txt").write_text(
            "B fixture " + String(line) + "\n"
        )
        var branch_report = _must(
            [
                report_bin,
                work + "/branch-manifest.txt",
                work + "/negative.txt",
            ],
            10,
        )
        if branch_report.output.find("100%") < 0:
            raise Error(branch_report.output)
        print(
            "PASS: "
            + String(len(cases()))
            + " native/instrumented Boolean cases, 64 truth assignments,"
            " normal and 6 throwing positions, raw/reduced vectors, and"
            " the negative report"
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


def lifetime_source() -> Tuple[String, List[String]]:
    """Return the container-destruction fixture and its expressions.

    Returns:
        The source, and one expression per case.
    """
    var text = """@fieldwise_init
struct Item(Movable):
    var id: Int
    var drops: Pointer[Int, MutUntrackedOrigin]
    def __deinit__(deinit self):
        self.drops[] = self.drops[] * 10 + self.id
        print("DROP", self.id, self.drops[])

def optional(id: Int, full: Bool, drops: Pointer[Int, MutUntrackedOrigin]) -> Optional[Item]:
    print("MAKE", id)
    if full:
        return Optional[Item](Item(id, drops))
    return None

def items(id: Int, full: Bool, drops: Pointer[Int, MutUntrackedOrigin]) -> List[Item]:
    print("MAKE", id)
    var result = List[Item]()
    if full:
        result.append(Item(id, drops))
    return result^

def observe(id: Int, result: Bool, drops: Pointer[Int, MutUntrackedOrigin]) -> Bool:
    print("OBSERVE", id, drops[])
    return result
"""
    var cases = List[String]()
    for kind in ["optional", "items"]:
        var other = "items"
        if kind == "items":
            other = "optional"
        for first in ["True", "False"]:
            for second in ["True", "False"]:
                var left = kind + "(1, " + first + ", drops)"
                var right = kind + "(2, " + second + ", drops)"
                var mixed = other + "(2, " + second + ", drops)"
                var observe = "observe(3, " + second + ", drops)"
                var expressions = List[String]()
                expressions.append(left + " and " + right)
                expressions.append(left + " or " + right)
                expressions.append(left + " and " + observe)
                expressions.append(left + " or " + observe)
                expressions.append(
                    "(" + left + " or " + right + ") and " + observe
                )
                expressions.append(
                    "(" + left + " and " + right + ") or " + observe
                )
                expressions.append("not (" + left + " or " + right + ")")
                expressions.append("retained and " + observe)
                expressions.append("retained or " + observe)
                expressions.append("(retained or " + observe + ") and " + left)
                expressions.append("(retained and " + observe + ") or " + left)
                expressions.append(left + " and " + mixed)
                expressions.append(left + " or " + mixed)
                for expression in expressions:
                    var number = len(cases)
                    cases.append(expression)
                    text += "\ndef case_" + String(number) + "():\n"
                    text += '    print("CASE", ' + String(number) + ")\n"
                    text += "    var state = 0\n"
                    text += (
                        "    var drops ="
                        " Pointer(to=state).unsafe_origin_cast[MutUntrackedOrigin]()\n"
                    )
                    text += (
                        "    var retained = "
                        + kind
                        + "(4, "
                        + first
                        + ", drops)\n"
                    )
                    text += "    if " + expression + ":\n"
                    text += (
                        '        print("BODY", ' + String(number) + ", state)\n"
                    )
                    text += "    else:\n"
                    text += (
                        '        print("ELSE", ' + String(number) + ", state)\n"
                    )
                    text += (
                        '    print("AFTER", '
                        + String(number)
                        + ", Bool(retained), state)\n"
                    )
    text += "\ndef main():\n"
    var number = 0
    while number < len(cases):
        text += "    case_" + String(number) + "()\n"
        text += '    print("END", ' + String(number) + ")\n"
        number += 1
    return (text, cases^)


def _obligation_width(expression: String) -> Int:
    """Return the compound width the lifetime manifest expects."""
    var width = 1
    var rest = expression
    while True:
        var at = rest.find(" and ")
        var other = rest.find(" or ")
        var next = at
        if next < 0 or (other >= 0 and other < next):
            next = other
        if next < 0:
            return width
        width += 1
        var tail = String(rest[byte = next + 5 :])
        rest = tail


def check_lifetime(mojo: String) raises:
    """Require native and instrumented container destruction to match.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If the manifest or the destruction order differs.
    """
    var root = absolute_path(".")
    var compiler = absolute_path(mojo)
    var made = lifetime_source()
    var work = mkdtemp(prefix="threemojo-lifetime-")
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
        Path(native + "/lifetime.mojo").write_text(made[0])
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
        _ = _must([build, rewritten, "lifetime.mojo"], 60, native)
        var manifest = Path(rewritten + "/manifest.txt").read_text()
        var actual = List[String]()
        for line in manifest.splitlines():
            var row = String(line)
            var parts = row.split(" ")
            if (
                len(parts) >= 2
                and (
                    String(parts[0]) == "B"
                    or String(parts[0]) == "C"
                    or String(parts[0]) == "M"
                )
                and String(parts[1]) == "lifetime"
            ):
                actual.append(row)
        var expected = List[String]()
        var source_lines = made[0].splitlines()
        var index = 0
        while index < len(source_lines):
            var header = String(source_lines[index]).strip()
            if header.startswith("if ") and header.endswith(":"):
                var expression = String(
                    header[byte = 3 : header.byte_length() - 1]
                )
                var width = _obligation_width(expression)
                var line = index + 1
                expected.append("B lifetime " + String(line))
                if width > 1:
                    var slot = 0
                    while slot < width:
                        expected.append(
                            "C lifetime " + String(line) + " " + String(slot)
                        )
                        expected.append(
                            "M lifetime " + String(line) + " " + String(slot)
                        )
                        slot += 1
            index += 1
        sort(actual)
        sort(expected)
        if not _same(actual, expected):
            raise Error("lifetime manifest changed")
        var native_out = String()
        var instrumented_out = String()
        for label in ["native", "instrumented"]:
            var folder = native
            if label == "instrumented":
                folder = rewritten
            var binary = work + "/lifetime-" + label
            _ = _must(
                [
                    compiler,
                    "build",
                    "-Werror",
                    "-I",
                    folder,
                    folder + "/lifetime.mojo",
                    "-o",
                    binary,
                ],
                180,
            )
            var ran = _must([binary], 5)
            if label == "native":
                native_out = ran.output
            else:
                instrumented_out = ran.output
        if native_out != instrumented_out:
            raise Error("Container destruction order differs")
        print(
            "PASS: "
            + String(len(made[1]))
            + " container destructor-order cases"
        )
    finally:
        _ = run_program(["rm", "-rf", work], 30)


def identity_source(expression: String) -> String:
    """Return one retained-identity fixture.

    Args:
        expression: The condition to test.

    Returns:
        The Mojo source.
    """
    var text = """@fieldwise_init
struct Identity(ImplicitlyCopyable, Boolable):
    var payload: Int
    var expected: Int

    @inline(.never)
    def __bool__(self) -> Bool:
        var original = Int(Pointer(to=self.payload)) == self.expected
        print("CONVERT", original)
        return original


def main():
    comptime assert Identity.__copy_ctor_is_trivial
    comptime assert Identity.__move_ctor_is_trivial
    comptime assert Identity.__del__is_trivial
    var kept = Identity(7, 0)
    kept.expected = Int(Pointer(to=kept.payload))
    print("DIRECT", kept.__bool__())
"""
    if expression.find("flag") >= 0:
        text += "    var flag = False\n"
    if expression.find("choose_kept") >= 0:
        text += "    var choose_kept = True\n"
    text += "    if " + expression + ":\n"
    text += '        print("BRANCH T")\n'
    text += "    else:\n"
    text += '        print("BRANCH F")\n'
    text += '    print("RETAINED", kept.payload)\n'
    text += (
        '    print("ADDRESS", Int(Pointer(to=kept.payload)) == kept.expected)\n'
    )
    return text


def _identity_output(conversions: Int, outcome: Bool) -> String:
    """Return the native stdout of one identity case."""
    var text = "CONVERT True\nDIRECT True\n"
    var index = 0
    while index < conversions:
        text += "CONVERT True\n"
        index += 1
    text += "BRANCH T\n" if outcome else "BRANCH F\n"
    text += "RETAINED 7\nADDRESS True\n"
    return text


def _origin_text(path: String) raises -> Tuple[String, String]:
    """Return the header and body of one origin file."""
    var raw = String(from_utf8_lossy=Path(path).read_bytes())
    var cut = raw.find("\n")
    if cut < 0:
        raise Error("truncated origin " + path)
    var header = String(raw[byte=:cut])
    var body = String(raw[byte = cut + 1 :])
    return (header, body)


def _require_origin(rewritten: String, name: String, source: String) raises:
    """Require the builder origin to bind this exact source."""
    var encoded = source
    var generated = String(
        from_utf8_lossy=Path(rewritten + "/" + name + ".mojo").read_bytes()
    )
    var manifest = String(
        from_utf8_lossy=Path(rewritten + "/manifest.txt").read_bytes()
    )
    var origin = _origin_text(rewritten + "/" + name + ".mojo.cov-origin")
    var parts = List[String]()
    parts.append(name + ".mojo")
    parts.append(encoded)
    parts.append(generated)
    parts.append(manifest)
    var header = "COVORIGIN1"
    for part in parts:
        header += " " + String(part.byte_length())
    if origin[0] != header:
        raise Error(name + " origin header " + origin[0])
    if origin[1] != parts[0] + parts[1] + parts[2] + parts[3]:
        raise Error(name + " origin body differs")
    var index = _origin_text(rewritten + "/origins.ready")
    var expected_index = (
        "COVORIGIN_INDEX2 1 " + String(manifest.byte_length()) + " 0"
    )
    if index[0] != expected_index:
        raise Error(name + " origin index " + index[0])
    var name_bytes = name + ".mojo"
    if (
        index[1]
        != manifest + String(name_bytes.byte_length()) + "\n" + name_bytes
    ):
        raise Error(name + " origin index body differs")


def _decision_line(source: String, expression: String) raises -> Int:
    """Return the 1-based line of `if expression:`."""
    var wanted = "if " + expression + ":"
    var number = 1
    for line in source.splitlines():
        if String(line).strip() == wanted:
            return number
        number += 1
    raise Error("missing decision " + wanted)


def _identity_records(
    name: String, decision: Int, outcome: Bool, vector: String
) -> String:
    """Return the expected trace lines joined by newlines."""
    var truth = "T" if outcome else "F"
    var text = String()
    var index = 0
    var raw = vector.as_bytes()
    while index < len(raw):
        var state = String(vector[byte = index : index + 1])
        if state != "-":
            text += (
                "COVLINE:"
                + name
                + ":"
                + String(decision)
                + "."
                + String(index)
                + ":"
                + state
                + "\n"
            )
        index += 1
    text += "COVLINE:" + name + ":" + String(decision) + ":" + truth + "\n"
    text += (
        "COVEVAL2:"
        + name
        + ":"
        + String(decision)
        + ":"
        + truth
        + ":"
        + vector
        + ";\n"
    )
    return text


def check_identity(mojo: String) raises:
    """Keep original-object truth for the retained identity controls.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If native output, the origin, or a trace differs.
    """
    var root = absolute_path(".")
    var compiler = absolute_path(mojo)
    var expressions = List[String]()
    var conversions = List[Int]()
    var outcomes = List[Bool]()
    var vectors = List[String]()
    expressions.append("not kept or False")
    conversions.append(1)
    outcomes.append(False)
    vectors.append("TF")
    expressions.append("not not kept and True")
    conversions.append(1)
    outcomes.append(True)
    vectors.append("TT")
    expressions.append("flag or not kept")
    conversions.append(1)
    outcomes.append(False)
    vectors.append("FT")
    expressions.append("not (kept if choose_kept else kept) or False")
    conversions.append(1)
    outcomes.append(False)
    vectors.append("TF")
    expressions.append("(not kept) or (not not kept)")
    conversions.append(2)
    outcomes.append(True)
    vectors.append("TT")
    expressions.append("flag and not kept")
    conversions.append(0)
    outcomes.append(False)
    vectors.append("F-")
    var work = mkdtemp(prefix="threemojo-identity-")
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
        var number = 0
        while number < len(expressions):
            var expression = expressions[number]
            var name = "identity-positive-" + String(number)
            var source = identity_source(expression)
            var expected = _identity_output(
                conversions[number], outcomes[number]
            )
            Path(native + "/" + name + ".mojo").write_text(source)
            var native_binary = work + "/" + name + "-native"
            _ = _must(
                [
                    compiler,
                    "build",
                    "-Werror",
                    "-I",
                    native,
                    native + "/" + name + ".mojo",
                    "-o",
                    native_binary,
                ],
                180,
            )
            var actual = _must([native_binary], 5)
            if actual.output != expected:
                raise Error(name + "\n" + actual.output)
            _ = _must([build, rewritten, name + ".mojo"], 60, native)
            var decision = _decision_line(source, expression)
            var manifest = Path(rewritten + "/manifest.txt").read_text()
            var manifest_rows = List[String]()
            for line in manifest.splitlines():
                var row = String(line)
                var parts = row.split(" ")
                if (
                    len(parts) >= 2
                    and String(parts[1]) == name
                    and (
                        String(parts[0]) == "B"
                        or String(parts[0]) == "C"
                        or String(parts[0]) == "M"
                    )
                ):
                    manifest_rows.append(row)
            var wanted_manifest = List[String]()
            wanted_manifest.append("B " + name + " " + String(decision))
            wanted_manifest.append("C " + name + " " + String(decision) + " 0")
            wanted_manifest.append("M " + name + " " + String(decision) + " 0")
            wanted_manifest.append("C " + name + " " + String(decision) + " 1")
            wanted_manifest.append("M " + name + " " + String(decision) + " 1")
            sort(manifest_rows)
            sort(wanted_manifest)
            if not _same(manifest_rows, wanted_manifest):
                raise Error(name + " manifest changed")
            _require_origin(rewritten, name, source)
            var instrumented_binary = work + "/" + name + "-instrumented"
            _ = _must(
                [
                    compiler,
                    "build",
                    "-Werror",
                    "-I",
                    rewritten,
                    rewritten + "/" + name + ".mojo",
                    "-o",
                    instrumented_binary,
                ],
                180,
            )
            var instrumented = _must([instrumented_binary], 5)
            if instrumented.output != actual.output:
                raise Error(name + " stdout differs\n" + instrumented.output)
            var wanted = _identity_records(
                name, decision, outcomes[number], vectors[number]
            )
            var prefix_hit = "COVLINE:" + name + ":" + String(decision)
            var prefix_vector = (
                "COVEVAL2:" + name + ":" + String(decision) + ":"
            )
            var seen = String()
            for line in instrumented.errors.splitlines():
                var row = String(line)
                if (
                    row.startswith(prefix_hit + ":")
                    or row.startswith(prefix_hit + ".")
                    or row.startswith(prefix_vector)
                ):
                    seen += row + "\n"
            if seen != wanted:
                raise Error(name + "\n" + seen + "\n" + wanted)
            number += 1
        print("PASS: 6 immediate retained-identity controls with exact traces")
    finally:
        _ = run_program(["rm", "-rf", work], 30)


def identity_last_use_source(expression: String) raises -> String:
    """Return an identity fixture without the post-use reads.

    Args:
        expression: The condition to test.

    Returns:
        The source with the retained-value prints removed.

    Raises:
        Error: If the full fixture does not end with those prints.
    """
    var source = identity_source(expression)
    var suffix = (
        '    print("RETAINED", kept.payload)\n'
        '    print("ADDRESS", Int(Pointer(to=kept.payload)) =='
        " kept.expected)\n"
    )
    if not source.endswith(suffix):
        raise Error("identity source lost its trailing reads")
    var copy = source
    return String(copy[byte = : copy.byte_length() - suffix.byte_length()])


def check_last_use(mojo: String) raises:
    """Compare the two last-use identity controls with native execution.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If native output, the origin, or a trace differs.
    """
    var root = absolute_path(".")
    var compiler = absolute_path(mojo)
    var work = mkdtemp(prefix="threemojo-last-use-")
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
        for number in [0, 3]:
            var expression = "not kept or False"
            var vector = "TF"
            if number == 3:
                expression = "not (kept if choose_kept else kept) or False"
            var name = "identity-last-use-" + String(number)
            var source = identity_last_use_source(expression)
            var full = _identity_output(1, False)
            var tail = "RETAINED 7\nADDRESS True\n"
            var copy = full
            var expected = String(
                copy[byte = : copy.byte_length() - tail.byte_length()]
            )
            Path(native + "/" + name + ".mojo").write_text(source)
            var native_binary = work + "/" + name + "-native"
            _ = _must(
                [
                    compiler,
                    "build",
                    "-Werror",
                    "-I",
                    native,
                    native + "/" + name + ".mojo",
                    "-o",
                    native_binary,
                ],
                180,
            )
            var actual = _must([native_binary], 5)
            if actual.output != expected:
                raise Error(name + "\n" + actual.output + "\n" + expected)
            _ = _must([build, rewritten, name + ".mojo"], 60, native)
            var decision = _decision_line(source, expression)
            var manifest = Path(rewritten + "/manifest.txt").read_text()
            var manifest_rows = List[String]()
            for line in manifest.splitlines():
                var row = String(line)
                var parts = row.split(" ")
                if (
                    len(parts) >= 2
                    and String(parts[1]) == name
                    and (
                        String(parts[0]) == "B"
                        or String(parts[0]) == "C"
                        or String(parts[0]) == "M"
                    )
                ):
                    manifest_rows.append(row)
            var wanted_manifest = List[String]()
            wanted_manifest.append("B " + name + " " + String(decision))
            wanted_manifest.append("C " + name + " " + String(decision) + " 0")
            wanted_manifest.append("M " + name + " " + String(decision) + " 0")
            wanted_manifest.append("C " + name + " " + String(decision) + " 1")
            wanted_manifest.append("M " + name + " " + String(decision) + " 1")
            sort(manifest_rows)
            sort(wanted_manifest)
            if not _same(manifest_rows, wanted_manifest):
                raise Error(name + " manifest changed")
            _require_origin(rewritten, name, source)
            var instrumented_binary = work + "/" + name + "-instrumented"
            _ = _must(
                [
                    compiler,
                    "build",
                    "-Werror",
                    "-I",
                    rewritten,
                    rewritten + "/" + name + ".mojo",
                    "-o",
                    instrumented_binary,
                ],
                180,
            )
            var instrumented = _must([instrumented_binary], 5)
            if instrumented.output != actual.output:
                raise Error(name + " stdout differs\n" + instrumented.output)
            var wanted = _identity_records(name, decision, False, vector)
            var prefix_hit = "COVLINE:" + name + ":" + String(decision)
            var prefix_vector = (
                "COVEVAL2:" + name + ":" + String(decision) + ":"
            )
            var seen = String()
            for line in instrumented.errors.splitlines():
                var row = String(line)
                if (
                    row.startswith(prefix_hit + ":")
                    or row.startswith(prefix_hit + ".")
                    or row.startswith(prefix_vector)
                ):
                    seen += row + "\n"
            if seen != wanted:
                raise Error(name + "\n" + seen + "\n" + wanted)
        print(
            "PASS: 2 last-use identity controls with exact native truth and"
            " traces"
        )
    finally:
        _ = run_program(["rm", "-rf", work], 30)


def temporary_identity_source(kind: String, expression: String) -> String:
    """Return one temporary-identity fixture.

    Args:
        kind: `Anchored`, `MoveOnly`, or `Moving`.
        expression: The condition, with `{kind}` already replaced.

    Returns:
        The Mojo source.
    """
    var move = ""
    if kind == "Moving":
        move = "not "
    var text = """struct Anchored(ImplicitlyCopyable, Boolable):
    var payload: Int
    var expected: Int

    @inline(.never)
    def __init__(out self, payload: Int):
        self.payload = payload
        self.expected = Int(Pointer(to=self.payload))

    @inline(.never)
    def __bool__(self) -> Bool:
        var original = Int(Pointer(to=self.payload)) == self.expected
        print("CONVERT Anchored", original)
        return original


struct MoveOnly(Movable, Boolable):
    var payload: Int
    var expected: Int

    @inline(.never)
    def __init__(out self, payload: Int):
        self.payload = payload
        self.expected = Int(Pointer(to=self.payload))

    @inline(.never)
    def __bool__(self) -> Bool:
        var original = Int(Pointer(to=self.payload)) == self.expected
        print("CONVERT MoveOnly", original)
        return original


struct Moving(Movable, Boolable):
    var payload: Int
    var expected: Int

    @inline(.never)
    def __init__(out self, payload: Int):
        self.payload = payload
        self.expected = Int(Pointer(to=self.payload))

    @inline(.never)
    def __init__(out self, *, deinit move: Self):
        self.payload = move.payload
        self.expected = move.expected
        print("MOVE Moving")

    @inline(.never)
    def __bool__(self) -> Bool:
        var original = Int(Pointer(to=self.payload)) == self.expected
        print("CONVERT Moving", original)
        return original


"""
    text += "\ndef main():\n"
    text += "    comptime assert " + move + kind + ".__move_ctor_is_trivial\n"
    text += "    comptime assert " + kind + ".__del__is_trivial\n"
    text += '    print("DIRECT", ' + kind + "(7).__bool__())\n"
    if expression.find("flag") >= 0:
        text += "    var flag = False\n"
    text += "    if " + expression + ":\n"
    text += '        print("BRANCH T")\n'
    text += "    else:\n"
    text += '        print("BRANCH F")\n'
    return text


def check_temporary_identity(mojo: String) raises:
    """Preserve constructor-to-truth identity for every admitted temporary.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If native output, the origin, or a trace differs.
    """
    var root = absolute_path(".")
    var compiler = absolute_path(mojo)
    var work = mkdtemp(prefix="threemojo-temporary-")
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
        var templates = List[String]()
        var outcomes = List[Bool]()
        var vectors = List[String]()
        templates.append("not {kind}(7) or False")
        outcomes.append(False)
        vectors.append("TF")
        templates.append("flag or not {kind}(7)")
        outcomes.append(False)
        vectors.append("FT")
        templates.append("not not {kind}(7) and True")
        outcomes.append(True)
        vectors.append("TT")
        for kind in ["Anchored", "MoveOnly", "Moving"]:
            var number = 0
            while number < len(templates):
                var expression = templates[number].replace("{kind}", kind)
                var name = (
                    "identity-temporary-"
                    + String(kind).lower()
                    + "-"
                    + String(number)
                )
                var source = temporary_identity_source(kind, expression)
                var branch = "BRANCH F\n"
                if outcomes[number]:
                    branch = "BRANCH T\n"
                var expected = (
                    "CONVERT "
                    + kind
                    + " True\nDIRECT True\nCONVERT "
                    + kind
                    + " True\n"
                    + branch
                )
                Path(native + "/" + name + ".mojo").write_text(source)
                var native_binary = work + "/" + name + "-native"
                _ = _must(
                    [
                        compiler,
                        "build",
                        "-Werror",
                        "-I",
                        native,
                        native + "/" + name + ".mojo",
                        "-o",
                        native_binary,
                    ],
                    180,
                )
                var actual = _must([native_binary], 5)
                if actual.output != expected:
                    raise Error(name + "\n" + actual.output + "\n" + expected)
                _ = _must([build, rewritten, name + ".mojo"], 60, native)
                var decision = _decision_line(source, expression)
                var manifest = Path(rewritten + "/manifest.txt").read_text()
                var manifest_rows = List[String]()
                for line in manifest.splitlines():
                    var row = String(line)
                    var parts = row.split(" ")
                    if (
                        len(parts) >= 2
                        and String(parts[1]) == name
                        and (
                            String(parts[0]) == "B"
                            or String(parts[0]) == "C"
                            or String(parts[0]) == "M"
                        )
                    ):
                        manifest_rows.append(row)
                var wanted_manifest = List[String]()
                wanted_manifest.append("B " + name + " " + String(decision))
                wanted_manifest.append(
                    "C " + name + " " + String(decision) + " 0"
                )
                wanted_manifest.append(
                    "M " + name + " " + String(decision) + " 0"
                )
                wanted_manifest.append(
                    "C " + name + " " + String(decision) + " 1"
                )
                wanted_manifest.append(
                    "M " + name + " " + String(decision) + " 1"
                )
                sort(manifest_rows)
                sort(wanted_manifest)
                if not _same(manifest_rows, wanted_manifest):
                    raise Error(name + " manifest changed")
                _require_origin(rewritten, name, source)
                var instrumented_binary = work + "/" + name + "-instrumented"
                _ = _must(
                    [
                        compiler,
                        "build",
                        "-Werror",
                        "-I",
                        rewritten,
                        rewritten + "/" + name + ".mojo",
                        "-o",
                        instrumented_binary,
                    ],
                    180,
                )
                var instrumented = _must([instrumented_binary], 5)
                if instrumented.output != actual.output:
                    raise Error(
                        name + " stdout differs\n" + instrumented.output
                    )
                var wanted = _identity_records(
                    name, decision, outcomes[number], vectors[number]
                )
                var prefix_hit = "COVLINE:" + name + ":" + String(decision)
                var prefix_vector = (
                    "COVEVAL2:" + name + ":" + String(decision) + ":"
                )
                var seen = String()
                for line in instrumented.errors.splitlines():
                    var row = String(line)
                    if (
                        row.startswith(prefix_hit + ":")
                        or row.startswith(prefix_hit + ".")
                        or row.startswith(prefix_vector)
                    ):
                        seen += row + "\n"
                if seen != wanted:
                    raise Error(name + "\n" + seen + "\n" + wanted)
                number += 1
        print("PASS: 9 immediate temporary-identity controls with exact traces")
    finally:
        _ = run_program(["rm", "-rf", work], 30)


def _pair_leaf(
    mut log: String,
    mut counts: List[Int],
    name: Int,
    mask: Int,
    changing: Bool,
) -> Bool:
    """Convert one generic leaf once and drop it."""
    var count = counts[name]
    counts[name] = count + 1
    log += String(name)
    var value = (mask & (1 << name)) != 0
    if changing and count % 2 == 1:
        value = not value
    log += "~" + String(name)
    return value


def generic_pair_expected() -> String:
    """Return the 64 native `PAIR` lines, with a trailing newline.

    Returns:
        The lines in changing, mask, then concrete order.
    """
    var expected = String()
    for changing in [False, True]:
        var mask = 0
        while mask < 16:
            for concrete in ["Probe", "Other"]:
                expected += generic_pair_line(concrete, mask, changing) + "\n"
            mask += 1
    return expected


def _decision_manifest(
    name: String, source: String, compound: String
) raises -> List[String]:
    """Return the branch rows for one isolated fixture.

    Args:
        name: The module name in the manifest.
        source: The isolated fixture source.
        compound: The one decision whose width is 3.

    Returns:
        One `B` row for each decision, plus `C` and `M` slots when the
        width is greater than one.

    Raises:
        Error: If the compound decision is missing or another compound appears.
    """
    var rows = List[String]()
    var number = 1
    var saw = False
    for line in source.splitlines():
        var header = String(line).strip()
        var decision = (
            header.startswith("if ")
            or header.startswith("elif ")
            or header.startswith("while ")
            or header.startswith("for ")
        )
        if decision:
            if not header.endswith(":"):
                raise Error("decision has no colon " + header)
            var width = 1
            if header == compound:
                width = 3
                saw = True
            elif header.find(" and ") >= 0 or header.find(" or ") >= 0:
                raise Error("unexpected compound " + header)
            rows.append("B " + name + " " + String(number))
            if width > 1:
                var slot = 0
                while slot < width:
                    rows.append(
                        "C " + name + " " + String(number) + " " + String(slot)
                    )
                    rows.append(
                        "M " + name + " " + String(number) + " " + String(slot)
                    )
                    slot += 1
        number += 1
    if not saw:
        raise Error("missing compound decision")
    return rows^


def _require_manifest(
    rewritten: String, name: String, source: String, compound: String
) raises:
    """Require the manifest to keep every decision in `source`.

    Args:
        rewritten: The instrumented tree.
        name: The module name.
        source: The original source.
        compound: The one decision whose width is 3.

    Raises:
        Error: If the manifest rows differ.
    """
    var wanted_manifest = _decision_manifest(name, source, compound)
    var manifest = Path(rewritten + "/manifest.txt").read_text()
    var manifest_rows = List[String]()
    for line in manifest.splitlines():
        var row = String(line)
        var parts = row.split(" ")
        if (
            len(parts) >= 2
            and String(parts[1]) == name
            and (
                String(parts[0]) == "B"
                or String(parts[0]) == "C"
                or String(parts[0]) == "M"
            )
        ):
            manifest_rows.append(row)
    sort(manifest_rows)
    sort(wanted_manifest)
    if not _same(manifest_rows, wanted_manifest):
        var shown = String()
        for row in manifest_rows:
            shown += "actual " + row + "\n"
        for row in wanted_manifest:
            shown += "wanted " + row + "\n"
        raise Error(name + " manifest changed\n" + shown)


def generic_pair_line(concrete: String, mask: Int, changing: Bool) -> String:
    """Return one native `PAIR` line from the independent model.

    Args:
        concrete: `Probe` or `Other`.
        mask: The four truth bits.
        changing: True when a repeated conversion flips.

    Returns:
        The line the native program prints, without a newline.
    """
    var log = String()
    var counts = List[Int](length=3, fill=0)
    var outcome = False
    var left = _pair_leaf(log, counts, 0, mask, changing)
    if left:
        outcome = True
    else:
        var middle = _pair_leaf(log, counts, 1, mask, changing)
        if middle:
            outcome = _pair_leaf(log, counts, 2, mask, changing)
    var flag = "False"
    if outcome:
        flag = "True"
    var changing_text = "False"
    if changing:
        changing_text = "True"
    return (
        "PAIR "
        + concrete
        + " "
        + String(mask)
        + " "
        + changing_text
        + " "
        + flag
        + " "
        + log
        + " "
        + String(counts[0])
        + " "
        + String(counts[1])
        + " "
        + String(counts[2])
    )


def check_generic_pair(mojo: String) raises:
    """Require the two-parameter generic refusal after the native model.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If the native rows, the manifest, or the refusal differ.
    """
    var root = absolute_path(".")
    var compiler = absolute_path(mojo)
    var source = Path(
        "tools/fixtures/coverage_generic_pair_isolated.txt"
    ).read_text()
    var expected = generic_pair_expected()
    var work = mkdtemp(prefix="threemojo-generic-pair-")
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
        var name = "generic-pair-isolated"
        Path(native + "/" + name + ".mojo").write_text(source)
        var binary = work + "/" + name + "-native"
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                native,
                "-I",
                root,
                native + "/" + name + ".mojo",
                "-o",
                binary,
            ],
            180,
        )
        var ran = _must([binary], 5)
        if ran.output != expected:
            raise Error(ran.output)
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
        _ = _must([build, rewritten, name + ".mojo"], 60, native)
        _require_origin(rewritten, name, source)
        _require_manifest(
            rewritten,
            name,
            source,
            "if A.make(0, state) or B.make(1, state) and A.make(2, state):",
        )
        var rejected = run_program(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                rewritten,
                "-I",
                root,
                rewritten + "/" + name + ".mojo",
                "-o",
                work + "/rejected",
            ],
            180,
            merge_errors=False,
        )
        if rejected.status == 0:
            raise Error("generic pair was accepted")
        var errors = rejected.errors
        if (
            errors.find("Coverage cannot yet preserve this compound condition")
            < 0
        ):
            raise Error(errors)
        if errors.find("custom mixed-type operator whose Bool result") < 0:
            raise Error(errors)
        if (
            errors.find(
                "def generic_pair[A: Made, B: Made](state: Cell) -> Bool:"
            )
            < 0
        ):
            raise Error(errors)
        print(
            "PASS: 64 isolated two-parameter generic controls and the refusal"
        )
    finally:
        _ = run_program(["rm", "-rf", work], 30)


def _single_observe(
    mut records: String,
    mut states: List[Int],
    line: Int,
    slot: Int,
    value: Bool,
):
    """Record the first truth in a slot, and a later disagreement."""
    var bit = 0
    if value:
        bit = 1
    var state = states[slot]
    if state == bit:
        return
    if state < 0:
        states[slot] = bit
    else:
        states[slot] = 2
    var flag = "F"
    if value:
        flag = "T"
    records += (
        "COVLINE:generic_single:"
        + String(line)
        + "."
        + String(slot)
        + ":"
        + flag
        + "\n"
    )


def _single_convert(
    mut log: String,
    mut counts: List[Int],
    mut records: String,
    mut states: List[Int],
    line: Int,
    index: Int,
    mask: Int,
    changing: Bool,
) -> Bool:
    """Convert one same-type leaf and keep its slot."""
    log += String(index)
    var count = counts[index]
    counts[index] = count + 1
    var value = (mask & (1 << index)) != 0
    if changing and count % 2 == 1:
        value = not value
    _single_observe(records, states, line, index, value)
    return value


def single_generic_case(
    concrete: String, mask: Int, changing: Bool, line: Int
) -> Tuple[String, String]:
    """Return one native `GENERIC` line and its coverage trace.

    Args:
        concrete: `Probe` or `Other`.
        mask: The four truth bits.
        changing: True when a repeated conversion flips.
        line: The decision line in the fixture.

    Returns:
        The stdout line without a newline, and the trace with newlines.
    """
    var log = String()
    var counts = List[Int](length=3, fill=0)
    var states = List[Int](length=3, fill=-1)
    var records = String()
    var left = _single_convert(
        log, counts, records, states, line, 0, mask, changing
    )
    var item = 0
    if not left:
        log += "~0"
        var middle = _single_convert(
            log, counts, records, states, line, 1, mask, changing
        )
        if not middle:
            item = 1
        else:
            log += "~1"
            item = 2
    var outcome = _single_convert(
        log, counts, records, states, line, item, mask, changing
    )
    log += "~" + String(item)
    var flag = "False"
    if outcome:
        flag = "True"
    var changing_text = "False"
    if changing:
        changing_text = "True"
    var row = (
        "GENERIC "
        + concrete
        + " "
        + String(mask)
        + " "
        + changing_text
        + " "
        + flag
        + " "
        + log
        + " "
        + String(counts[0])
        + " "
        + String(counts[1])
        + " "
        + String(counts[2])
    )
    var truth = "F"
    if outcome:
        truth = "T"
    var vector = String()
    var slot = 0
    while slot < 3:
        var state = states[slot]
        if state < 0:
            vector += "-"
        elif state == 0:
            vector += "F"
        elif state == 1:
            vector += "T"
        else:
            vector += "?"
        slot += 1
    var trace = "COVLINE:generic_single:" + String(line) + "\n"
    trace += records
    trace += "COVLINE:generic_single:" + String(line) + ":" + truth + "\n"
    trace += (
        "COVEVAL2:generic_single:"
        + String(line)
        + ":"
        + truth
        + ":"
        + vector
        + ";\n"
    )
    return (row, trace)


def single_generic_expected(line: Int) -> String:
    """Return the 64 native `GENERIC` lines, with a trailing newline.

    Args:
        line: The decision line in the fixture.

    Returns:
        The lines in changing, mask, then concrete order.
    """
    var text = String()
    for changing in [False, True]:
        var mask = 0
        while mask < 16:
            for concrete in ["Probe", "Other"]:
                var made = single_generic_case(concrete, mask, changing, line)
                text += made[0] + "\n"
            mask += 1
    return text


def single_generic_trace(line: Int) -> String:
    """Return the 64 coverage traces, with a trailing newline.

    Args:
        line: The decision line in the fixture.

    Returns:
        Statement, condition, decision, and vector records, in order.
    """
    var text = String()
    for changing in [False, True]:
        var mask = 0
        while mask < 16:
            for concrete in ["Probe", "Other"]:
                var made = single_generic_case(concrete, mask, changing, line)
                text += made[1]
            mask += 1
    return text


def _trace_for_line(raw: String, name: String, line: Int) -> String:
    """Return the coverage records for one decision line."""
    var wanted = String(line)
    var text = String()
    for row in raw.splitlines():
        var line_text = String(row)
        var parts = line_text.split(":")
        if len(parts) < 3:
            continue
        var kind = String(parts[0])
        if kind != "COVLINE" and kind != "COVEVAL2":
            continue
        if String(parts[1]) != name:
            continue
        var field = String(parts[2])
        var dot = field.find(".")
        var number = field
        if dot >= 0:
            number = String(field[byte=:dot])
        if number == wanted:
            text += line_text + "\n"
    return text


def check_single_generic(mojo: String) raises:
    """Require one-parameter generic truth to match native and instrumented runs.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If the rows, the manifest, the origin, or the trace differ.
    """
    var root = absolute_path(".")
    var compiler = absolute_path(mojo)
    var source = Path("tools/fixtures/coverage_generic_single.txt").read_text()
    var expression = "A.make(0, state) or A.make(1, state) and A.make(2, state)"
    var line = _decision_line(source, expression)
    var expected = single_generic_expected(line)
    var wanted_trace = single_generic_trace(line)
    var work = mkdtemp(prefix="threemojo-generic-single-")
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
        var name = "generic_single"
        Path(native + "/" + name + ".mojo").write_text(source)
        var binary = work + "/" + name + "-native"
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                native,
                "-I",
                root,
                native + "/" + name + ".mojo",
                "-o",
                binary,
            ],
            180,
        )
        var ran = _must([binary], 5)
        if ran.output != expected:
            raise Error(ran.output)
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
        _ = _must([build, rewritten, name + ".mojo"], 60, native)
        _require_origin(rewritten, name, source)
        _require_manifest(
            rewritten,
            name,
            source,
            "if " + expression + ":",
        )
        var instrumented_binary = work + "/" + name + "-instrumented"
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                rewritten,
                "-I",
                root,
                rewritten + "/" + name + ".mojo",
                "-o",
                instrumented_binary,
            ],
            180,
        )
        var instrumented = _must([instrumented_binary], 5)
        if instrumented.output != expected:
            raise Error(instrumented.output)
        var seen = _trace_for_line(instrumented.errors, name, line)
        if seen != wanted_trace:
            raise Error(seen + "\n" + wanted_trace)
        print("PASS: 64 single-parameter generic controls with exact traces")
    finally:
        _ = run_program(["rm", "-rf", work], 30)


comptime _TS = 1
comptime _TD = 2
comptime _TB = 3
comptime _TX = 4
comptime _TC = 5
comptime _TM = 6
comptime _TP = 7
comptime _TQ = 8
comptime _TT = 9
comptime _TAND = 10
comptime _TOR = 11
comptime _TNOT = 12
comptime _TCHOOSE = 13


struct _TruthNode(Copyable, ImplicitlyCopyable, Movable):
    var kind: Int
    var index: Int
    var left: Int
    var right: Int
    var third: Int

    def __init__(
        out self, kind: Int, index: Int, left: Int, right: Int, third: Int
    ):
        self.kind = kind
        self.index = index
        self.left = left
        self.right = right
        self.third = third


struct _TruthItem(Copyable, ImplicitlyCopyable, Movable):
    var kind: Int
    var name: Int
    var retained: Bool
    var slot: Int

    def __init__(out self, kind: Int, name: Int, retained: Bool, slot: Int):
        self.kind = kind
        self.name = name
        self.retained = retained
        self.slot = slot


def _tn(kind: Int, index: Int) -> List[_TruthNode]:
    var nodes = List[_TruthNode]()
    nodes.append(_TruthNode(kind, index, -1, -1, -1))
    return nodes^


def _tjoin(
    var prefix: List[_TruthNode], var child: List[_TruthNode]
) -> List[_TruthNode]:
    var base = len(prefix)
    for item in child:
        var left = item.left if item.left < 0 else item.left + base
        var right = item.right if item.right < 0 else item.right + base
        var third = item.third if item.third < 0 else item.third + base
        prefix.append(_TruthNode(item.kind, item.index, left, right, third))
    return prefix^


def _tbin(
    kind: Int, var left: List[_TruthNode], var right: List[_TruthNode]
) -> List[_TruthNode]:
    var left_root = len(left) - 1
    var nodes = _tjoin(left^, right^)
    var right_root = len(nodes) - 1
    nodes.append(_TruthNode(kind, 0, left_root, right_root, -1))
    return nodes^


def _tunary(kind: Int, var child: List[_TruthNode]) -> List[_TruthNode]:
    var root = len(child) - 1
    child.append(_TruthNode(kind, 0, root, -1, -1))
    return child^


def _tchoose(
    var condition: List[_TruthNode],
    var taken: List[_TruthNode],
    var other: List[_TruthNode],
) -> List[_TruthNode]:
    var condition_root = len(condition) - 1
    var nodes = _tjoin(condition^, taken^)
    var taken_root = len(nodes) - 1
    nodes = _tjoin(nodes^, other^)
    var other_root = len(nodes) - 1
    nodes.append(
        _TruthNode(_TCHOOSE, 0, condition_root, taken_root, other_root)
    )
    return nodes^


def _truth_case(number: Int) raises -> List[_TruthNode]:
    if number == 0:
        return _tbin(_TOR, _tn(_TS, 0), _tn(_TS, 1))
    if number == 1:
        return _tbin(_TAND, _tn(_TS, 0), _tn(_TS, 1))
    if number == 2:
        return _tbin(_TOR, _tbin(_TOR, _tn(_TS, 0), _tn(_TS, 1)), _tn(_TS, 2))
    if number == 3:
        return _tbin(_TOR, _tbin(_TAND, _tn(_TS, 0), _tn(_TS, 1)), _tn(_TS, 2))
    if number == 4:
        return _tbin(_TOR, _tn(_TS, 0), _tbin(_TAND, _tn(_TS, 1), _tn(_TS, 2)))
    if number == 5:
        return _tunary(_TNOT, _tbin(_TOR, _tn(_TS, 0), _tn(_TS, 1)))
    if number == 6:
        return _tbin(_TAND, _tunary(_TNOT, _tn(_TS, 0)), _tn(_TS, 1))
    if number == 7:
        return _tbin(_TOR, _tn(_TS, 0), _tn(_TD, 1))
    if number == 8:
        return _tbin(_TAND, _tn(_TD, 0), _tbin(_TOR, _tn(_TS, 1), _tn(_TS, 2)))
    if number == 9:
        return _tbin(
            _TAND,
            _tbin(_TOR, _tn(_TS, 0), _tn(_TS, 1)),
            _tbin(_TOR, _tn(_TS, 2), _tn(_TS, 3)),
        )
    if number == 10:
        return _tbin(_TOR, _tbin(_TAND, _tn(_TS, 0), _tn(_TS, 1)), _tn(_TB, 2))
    if number == 11:
        return _tbin(_TOR, _tn(_TB, 0), _tbin(_TAND, _tn(_TS, 1), _tn(_TS, 2)))
    if number == 12:
        return _tbin(_TOR, _tn(_TX, 0), _tn(_TB, 1))
    if number == 13:
        return _tbin(
            _TOR,
            _tbin(_TAND, _tn(_TB, 0), _tunary(_TNOT, _tn(_TX, 1))),
            _tn(_TS, 2),
        )
    if number == 14:
        return _tbin(_TOR, _tbin(_TAND, _tn(_TX, 0), _tn(_TD, 1)), _tn(_TS, 2))
    if number == 15:
        return _tbin(
            _TOR,
            _tchoose(_tn(_TB, 1), _tn(_TS, 2), _tn(_TS, 3)),
            _tn(_TS, 0),
        )
    if number == 16:
        return _tbin(_TAND, _tbin(_TOR, _tn(_TD, 0), _tn(_TD, 1)), _tn(_TS, 2))
    if number == 17:
        return _tbin(_TOR, _tn(_TC, 0), _tn(_TB, 1))
    if number == 18:
        return _tbin(_TAND, _tn(_TB, 0), _tn(_TC, 1))
    if number == 19:
        return _tbin(_TOR, _tbin(_TAND, _tn(_TC, 0), _tn(_TS, 1)), _tn(_TS, 2))
    if number == 20:
        return _tbin(
            _TAND,
            _tbin(_TOR, _tn(_TS, 0), _tn(_TS, 1)),
            _tunary(_TNOT, _tn(_TC, 2)),
        )
    if number == 21:
        return _tbin(
            _TOR,
            _tn(_TC, 0),
            _tbin(_TOR, _tn(_TX, 1), _tbin(_TAND, _tn(_TC, 2), _tn(_TB, 3))),
        )
    if number == 22:
        return _tbin(_TAND, _tn(_TC, 0), _tn(_TD, 1))
    if number == 23:
        return _tbin(
            _TOR,
            _tchoose(_tn(_TB, 1), _tn(_TC, 2), _tn(_TC, 3)),
            _tn(_TS, 0),
        )
    if number == 24:
        return _tbin(_TOR, _tn(_TM, 0), _tn(_TB, 1))
    if number == 25:
        return _tbin(_TAND, _tn(_TB, 0), _tn(_TM, 1))
    if number == 26:
        return _tbin(
            _TOR,
            _tunary(_TNOT, _tn(_TM, 0)),
            _tbin(_TAND, _tn(_TS, 1), _tn(_TM, 2)),
        )
    if number == 27:
        return _tbin(
            _TAND,
            _tbin(_TOR, _tn(_TM, 0), _tn(_TD, 1)),
            _tbin(_TOR, _tn(_TS, 2), _tn(_TS, 3)),
        )
    if number == 28:
        return _tbin(_TAND, _tn(_TM, 0), _tn(_TC, 1))
    if number == 29:
        return _tbin(
            _TOR,
            _tchoose(_tn(_TB, 1), _tn(_TM, 2), _tn(_TM, 3)),
            _tn(_TC, 0),
        )
    if number == 30:
        return _tbin(_TAND, _tbin(_TOR, _tn(_TP, 0), _tn(_TP, 1)), _tn(_TB, 2))
    if number == 31:
        return _tbin(_TAND, _tn(_TP, 0), _tbin(_TOR, _tn(_TP, 1), _tn(_TQ, 2)))
    if number == 32:
        return _tbin(_TOR, _tbin(_TOR, _tn(_TQ, 0), _tn(_TP, 1)), _tn(_TB, 2))
    if number == 33:
        return _tbin(
            _TAND,
            _tunary(_TNOT, _tn(_TP, 0)),
            _tbin(_TOR, _tn(_TP, 1), _tbin(_TOR, _tn(_TP, 2), _tn(_TQ, 3))),
        )
    if number == 34:
        return _tbin(
            _TOR,
            _tchoose(_tn(_TB, 1), _tn(_TP, 2), _tn(_TP, 3)),
            _tn(_TP, 0),
        )
    if number == 35:
        return _tbin(_TOR, _tbin(_TAND, _tn(_TP, 0), _tn(_TP, 0)), _tn(_TB, 1))
    if number == 36:
        return _tbin(
            _TAND,
            _tbin(_TOR, _tn(_TP, 0), _tn(_TS, 1)),
            _tbin(_TOR, _tn(_TQ, 2), _tn(_TP, 3)),
        )
    if number == 37:
        return _tbin(_TOR, _tn(_TT, 0), _tn(_TC, 1))
    if number == 38:
        return _tbin(_TAND, _tbin(_TOR, _tn(_TT, 0), _tn(_TC, 1)), _tn(_TB, 2))
    if number == 39:
        return _tbin(_TOR, _tbin(_TOR, _tn(_TT, 0), _tn(_TC, 1)), _tn(_TC, 2))
    if number == 40:
        return _tbin(_TAND, _tn(_TT, 0), _tbin(_TOR, _tn(_TB, 1), _tn(_TC, 2)))
    if number == 41:
        return _tbin(
            _TOR,
            _tn(_TT, 0),
            _tchoose(_tn(_TB, 1), _tn(_TC, 2), _tn(_TC, 3)),
        )
    if number == 42:
        return _tbin(_TAND, _tn(_TT, 0), _tunary(_TNOT, _tn(_TC, 1)))
    raise Error("bad truth case " + String(number))


def _truth_type(nodes: List[_TruthNode], id: Int) -> Int:
    var kind = nodes[id].kind
    if kind == _TS or kind == _TX:
        return _TS
    if kind == _TP or kind == _TQ:
        return _TP
    if kind == _TT:
        return _TC
    if kind == _TD or kind == _TB or kind == _TC or kind == _TM:
        return kind
    if kind == _TCHOOSE:
        return _truth_type(nodes, nodes[id].right)
    if kind == _TNOT:
        return _TB
    var left = _truth_type(nodes, nodes[id].left)
    var right = _truth_type(nodes, nodes[id].right)
    if left == right:
        return left
    return _TB


def _truth_enter(mut log: String, index: Int, fail: Int) raises:
    log += "+" + String(index)
    if index == fail:
        raise Error("truth-fail")


def _truth_assign(
    nodes: List[_TruthNode], id: Int, mut slots: List[Int], next: Int
) -> Int:
    var kind = nodes[id].kind
    if kind == _TAND or kind == _TOR or kind == _TNOT:
        var cursor = next
        if nodes[id].left >= 0:
            cursor = _truth_assign(nodes, nodes[id].left, slots, cursor)
        if nodes[id].right >= 0:
            cursor = _truth_assign(nodes, nodes[id].right, slots, cursor)
        if nodes[id].third >= 0:
            cursor = _truth_assign(nodes, nodes[id].third, slots, cursor)
        return cursor
    slots[id] = next
    return next + 1


def _truth_slots(nodes: List[_TruthNode]) -> List[Int]:
    var slots = List[Int](length=len(nodes), fill=-1)
    _ = _truth_assign(nodes, len(nodes) - 1, slots, 0)
    return slots^


def _truth_observe(
    mut records: String,
    mut states: List[Int],
    module_name: String,
    line: Int,
    slot: Int,
    value: Bool,
):
    if slot < 0:
        return
    var bit = 0
    if value:
        bit = 1
    var state = states[slot]
    if state == bit:
        return
    if state < 0:
        states[slot] = bit
    else:
        states[slot] = 2
    var flag = "F"
    if value:
        flag = "T"
    records += (
        "COVLINE:"
        + module_name
        + ":"
        + String(line)
        + "."
        + String(slot)
        + ":"
        + flag
        + "\n"
    )


def _truth_convert(
    mut log: String,
    mut counts: List[Int],
    mut records: String,
    mut states: List[Int],
    item: _TruthItem,
    mask: Int,
    changing: Bool,
    module_name: String,
    line: Int,
) -> Bool:
    if item.kind == _TB:
        return item.name != 0
    log += String(item.name)
    var count = counts[item.name]
    counts[item.name] = count + 1
    var value = (mask & (1 << item.name)) != 0
    if changing and count % 2 == 1:
        value = not value
    _truth_observe(records, states, module_name, line, item.slot, value)
    return value


def _truth_drop(mut log: String, item: _TruthItem):
    if item.kind == _TB or item.kind == _TQ or item.retained:
        return
    log += "~" + String(item.name)


def _truth_bit(value: Bool, slot: Int) -> _TruthItem:
    var bit = 0
    if value:
        bit = 1
    return _TruthItem(_TB, bit, False, slot)


def _truth_eval(
    nodes: List[_TruthNode],
    id: Int,
    slots: List[Int],
    mut log: String,
    mut counts: List[Int],
    mut records: String,
    mut states: List[Int],
    mask: Int,
    fail: Int,
    changing: Bool,
    module_name: String,
    line: Int,
    owned: Bool,
) raises -> _TruthItem:
    var node = nodes[id]
    var kind = node.kind
    var slot = slots[id]
    if kind == _TS or kind == _TD or kind == _TM or kind == _TQ or kind == _TT:
        _truth_enter(log, node.index, fail)
        return _TruthItem(kind, node.index, False, slot)
    if kind == _TC and owned:
        log += "=" + String(node.index)
        return _TruthItem(_TS, node.index, False, slot)
    if kind == _TX or kind == _TC or kind == _TP:
        return _TruthItem(_TS, node.index, True, slot)
    if kind == _TB:
        _truth_enter(log, node.index, fail)
        var bit_value = (mask & (1 << node.index)) != 0
        _truth_observe(records, states, module_name, line, slot, bit_value)
        return _truth_bit(bit_value, slot)
    if kind == _TCHOOSE:
        var cond = nodes[node.left]
        _truth_enter(log, cond.index, fail)
        var chosen = node.third
        if (mask & (1 << cond.index)) != 0:
            chosen = node.right
        var chosen_node = nodes[chosen]
        if chosen_node.kind == _TC or chosen_node.kind == _TP:
            var arm = _truth_eval(
                nodes,
                chosen,
                slots,
                log,
                counts,
                records,
                states,
                mask,
                fail,
                changing,
                module_name,
                line,
                owned,
            )
            return _TruthItem(arm.kind, arm.name, arm.retained, slot)
        _truth_enter(log, chosen_node.index, fail)
        if chosen_node.kind == _TM:
            log += ">" + String(chosen_node.index)
        return _TruthItem(_TS, chosen_node.index, False, slot)
    if kind == _TNOT:
        var item = _truth_eval(
            nodes,
            node.left,
            slots,
            log,
            counts,
            records,
            states,
            mask,
            fail,
            changing,
            module_name,
            line,
            False,
        )
        var value = _truth_convert(
            log,
            counts,
            records,
            states,
            item,
            mask,
            changing,
            module_name,
            line,
        )
        _truth_drop(log, item)
        return _truth_bit(not value, -1)
    var left = _truth_eval(
        nodes,
        node.left,
        slots,
        log,
        counts,
        records,
        states,
        mask,
        fail,
        changing,
        module_name,
        line,
        False,
    )
    var value = _truth_convert(
        log,
        counts,
        records,
        states,
        left,
        mask,
        changing,
        module_name,
        line,
    )
    var short = value if kind == _TOR else not value
    var same = _truth_type(nodes, node.left) == _truth_type(nodes, node.right)
    if same:
        if short:
            return left
        _truth_drop(log, left)
        var right_kind = nodes[node.right].kind
        var own_right = right_kind == _TC or right_kind == _TCHOOSE
        return _truth_eval(
            nodes,
            node.right,
            slots,
            log,
            counts,
            records,
            states,
            mask,
            fail,
            changing,
            module_name,
            line,
            own_right,
        )
    _truth_drop(log, left)
    if short:
        return _truth_bit(value, -1)
    var right = _truth_eval(
        nodes,
        node.right,
        slots,
        log,
        counts,
        records,
        states,
        mask,
        fail,
        changing,
        module_name,
        line,
        False,
    )
    value = _truth_convert(
        log,
        counts,
        records,
        states,
        right,
        mask,
        changing,
        module_name,
        line,
    )
    _truth_drop(log, right)
    return _truth_bit(value, -1)


def _truth_retain(nodes: List[_TruthNode], id: Int, mut log: String):
    var node = nodes[id]
    var kind = node.kind
    if kind == _TX or kind == _TC:
        log += "~" + String(node.index)
        return
    if (
        kind == _TS
        or kind == _TD
        or kind == _TB
        or kind == _TM
        or kind == _TP
        or kind == _TQ
        or kind == _TT
    ):
        return
    if node.left >= 0:
        _truth_retain(nodes, node.left, log)
    if node.right >= 0:
        _truth_retain(nodes, node.right, log)
    if node.third >= 0:
        _truth_retain(nodes, node.third, log)


def _truth_vector(states: List[Int]) -> String:
    var text = String()
    var slot = 0
    while slot < len(states):
        var state = states[slot]
        if state < 0:
            text += "-"
        elif state == 0:
            text += "F"
        elif state == 1:
            text += "T"
        else:
            text += "?"
        slot += 1
    return text


def _truth_execute(
    number: Int,
    mask: Int,
    fail: Int,
    changing: Bool,
    line: Int,
    module_name: String,
) raises -> Tuple[String, String]:
    var nodes = _truth_case(number)
    var slots = _truth_slots(nodes)
    var width = 0
    var index = 0
    while index < len(slots):
        if slots[index] >= width:
            width = slots[index] + 1
        index += 1
    var log = String()
    var records = String()
    var counts = List[Int](length=8, fill=0)
    var states = List[Int](length=width, fill=-1)
    var failed = False
    var outcome = False
    try:
        var item = _truth_eval(
            nodes,
            len(nodes) - 1,
            slots,
            log,
            counts,
            records,
            states,
            mask,
            fail,
            changing,
            module_name,
            line,
            False,
        )
        outcome = _truth_convert(
            log,
            counts,
            records,
            states,
            item,
            mask,
            changing,
            module_name,
            line,
        )
        _truth_drop(log, item)
    except error:
        if String(error).find("truth-fail") < 0:
            raise error
        failed = True
    if failed:
        log += "|E"
    elif outcome:
        log += "|T"
        records += "COVLINE:" + module_name + ":" + String(line) + ":T\n"
    else:
        log += "|F"
        records += "COVLINE:" + module_name + ":" + String(line) + ":F\n"
    if not failed:
        var mark = "F"
        if outcome:
            mark = "T"
        records += (
            "COVEVAL2:"
            + module_name
            + ":"
            + String(line)
            + ":"
            + mark
            + ":"
            + _truth_vector(states)
            + ";\n"
        )
    _truth_retain(nodes, len(nodes) - 1, log)
    return (log, records)


def truth_log(
    number: Int, mask: Int, fail: Int, changing: Bool
) raises -> String:
    """Return one custom-truth log, without the `TRUTH` label.

    Args:
        number: The reference tree, from 0 through 42.
        mask: The four truth bits.
        fail: The leaf that raises, or -1.
        changing: True when a repeated conversion flips.

    Returns:
        The native log, including the outcome mark and retained destruction.

    Raises:
        Error: If `number` is outside the reference trees.
    """
    var made = _truth_execute(number, mask, fail, changing, 1, "truth")
    return made[0]


def _truth_native_rows(changing: Bool) raises -> String:
    """Return the native rows for one changing mode."""
    var text = String()
    var fail = -1
    while fail < 4:
        var mask = 0
        while mask < 16:
            var number = 0
            while number < 43:
                var log = truth_log(number, mask, fail, changing)
                var changing_text = "False"
                if changing:
                    changing_text = "True"
                text += (
                    "TRUTH "
                    + String(number)
                    + " "
                    + String(mask)
                    + " "
                    + String(fail)
                    + " "
                    + changing_text
                    + " "
                    + log
                    + "\n"
                )
                number += 1
            mask += 1
        fail += 1
    return text


def truth_model_rows() raises -> String:
    """Return every custom-truth row, with a trailing newline.

    Returns:
        6,880 rows in changing, failure, mask, then tree order.

    Raises:
        Error: If a reference tree is missing.
    """
    return _truth_native_rows(False) + _truth_native_rows(True)


def _truth_lines(stdout: String) -> String:
    """Return the `TRUTH` lines, with a trailing newline."""
    var text = String()
    for line in stdout.splitlines():
        var row = String(line)
        if row.startswith("TRUTH "):
            text += row + "\n"
    return text


def check_custom_truth_native(mojo: String) raises:
    """Require the native custom-truth program to match the model.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If the build fails or a stable or changing row differs.
    """
    var compiler = absolute_path(mojo)
    var source = Path("tools/fixtures/coverage_truth_native.txt").read_text()
    var work = mkdtemp(prefix="threemojo-truth-native-")
    try:
        var native = work + "/native"
        _ = _must(["mkdir", "-p", native], 10)
        var name = "truth"
        Path(native + "/" + name + ".mojo").write_text(source)
        var binary = work + "/" + name + "-native"
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                native,
                native + "/" + name + ".mojo",
                "-o",
                binary,
            ],
            180,
        )
        for changing in [False, True]:
            var flag = "0"
            if changing:
                flag = "1"
            var temp = mkdtemp(prefix="threemojo-truth-run-")
            var ran = _must(
                _with_env(
                    [
                        "TMPDIR=" + temp,
                        "THREEMOJO_TEST_TMPDIR=" + temp,
                        "THREEMOJO_TRUTH_CHANGING=" + flag,
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
            var actual = _truth_lines(ran.output)
            var expected = _truth_native_rows(changing)
            if actual != expected:
                raise Error(actual)
        print(
            "PASS: 43 custom truth trees, 16 masks, and 5 failure positions,"
            " stable and changing"
        )
    finally:
        _ = run_program(["rm", "-rf", work], 30)


def _truth_accepted_numbers() -> List[Int]:
    var numbers = List[Int]()
    numbers.append(0)
    numbers.append(1)
    numbers.append(2)
    numbers.append(3)
    numbers.append(4)
    numbers.append(5)
    numbers.append(9)
    numbers.append(15)
    numbers.append(31)
    numbers.append(34)
    numbers.append(37)
    numbers.append(39)
    numbers.append(41)
    return numbers^


def _truth_accepted_line(number: Int) raises -> Int:
    if number == 0:
        return 166
    if number == 1:
        return 180
    if number == 2:
        return 194
    if number == 3:
        return 208
    if number == 4:
        return 222
    if number == 5:
        return 236
    if number == 9:
        return 250
    if number == 15:
        return 264
    if number == 31:
        return 280
    if number == 34:
        return 299
    if number == 37:
        return 317
    if number == 39:
        return 334
    if number == 41:
        return 352
    raise Error("not an accepted truth tree " + String(number))


def truth_records(
    number: Int, mask: Int, fail: Int, changing: Bool, line: Int
) raises -> String:
    """Return one custom-truth coverage trace, with trailing newlines.

    Args:
        number: The reference tree, from 0 through 42.
        mask: The four truth bits.
        fail: The leaf that raises, or -1.
        changing: True when a repeated conversion flips.
        line: The decision line recorded in the trace.

    Returns:
        The condition hits, the decision hit, and the vector. A thrown
        evaluation keeps only the hits recorded before the failure.

    Raises:
        Error: If `number` is outside the reference trees.
    """
    var made = _truth_execute(number, mask, fail, changing, line, "truth")
    return made[1]


def truth_accepted_traces(changing: Bool) raises -> String:
    """Return the accepted-tree traces, with a trailing newline.

    Args:
        changing: True when a repeated conversion flips.

    Returns:
        One block per failure, mask, and accepted tree. Each block starts
        with `CASE` and then the coverage records.

    Raises:
        Error: If a reference tree is missing.
    """
    var text = String()
    var fail = -1
    while fail < 4:
        var mask = 0
        while mask < 16:
            for number in _truth_accepted_numbers():
                text += (
                    "CASE "
                    + String(number)
                    + " "
                    + String(mask)
                    + " "
                    + String(fail)
                    + "\n"
                )
                text += truth_records(
                    number, mask, fail, changing, _truth_accepted_line(number)
                )
            mask += 1
        fail += 1
    return text


def _truth_accepted_rows(changing: Bool) raises -> String:
    var text = String()
    var fail = -1
    while fail < 4:
        var mask = 0
        while mask < 16:
            for number in _truth_accepted_numbers():
                var log = truth_log(number, mask, fail, changing)
                var changing_text = "False"
                if changing:
                    changing_text = "True"
                text += (
                    "TRUTH "
                    + String(number)
                    + " "
                    + String(mask)
                    + " "
                    + String(fail)
                    + " "
                    + changing_text
                    + " "
                    + log
                    + "\n"
                )
            mask += 1
        fail += 1
    return text


def _truth_tree_trace(number: Int, changing: Bool) raises -> String:
    var line = _truth_accepted_line(number)
    var text = String()
    var fail = -1
    while fail < 4:
        var mask = 0
        while mask < 16:
            text += truth_records(number, mask, fail, changing, line)
            mask += 1
        fail += 1
    return text


def _truth_coverage(raw: String, name: String, line: Int) -> String:
    var stem = name + ":" + String(line)
    var hit = "COVLINE:" + stem
    var vector = "COVEVAL2:" + stem + ":"
    var text = String()
    for row in raw.splitlines():
        var line_text = String(row)
        if (
            line_text.startswith(hit + ":")
            or line_text.startswith(hit + ".")
            or line_text.startswith(vector)
        ):
            text += line_text + "\n"
    return text


def _truth_width(number: Int) raises -> Int:
    var nodes = _truth_case(number)
    var slots = List[Int](length=len(nodes), fill=-1)
    return _truth_assign(nodes, len(nodes) - 1, slots, 0)


def _require_accepted_manifest(
    rewritten: String, name: String, source: String
) raises:
    var widths = Dict[Int, Int]()
    for number in _truth_accepted_numbers():
        widths[_truth_accepted_line(number)] = _truth_width(number)
    var wanted = List[String]()
    var seen = 0
    var number = 1
    for line in source.splitlines():
        var header = String(line).strip()
        var decision = (
            header.startswith("if ")
            or header.startswith("elif ")
            or header.startswith("while ")
            or header.startswith("for ")
        )
        if decision:
            if not header.endswith(":"):
                raise Error("decision has no colon " + header)
            var width = 1
            if number in widths:
                width = widths[number]
                seen += 1
            elif header.find(" and ") >= 0 or header.find(" or ") >= 0:
                raise Error("unexpected compound " + header)
            wanted.append("B " + name + " " + String(number))
            if width > 1:
                var slot = 0
                while slot < width:
                    wanted.append(
                        "C " + name + " " + String(number) + " " + String(slot)
                    )
                    wanted.append(
                        "M " + name + " " + String(number) + " " + String(slot)
                    )
                    slot += 1
        number += 1
    if seen != len(widths):
        raise Error("missing accepted decision")
    var manifest = Path(rewritten + "/manifest.txt").read_text()
    var actual = List[String]()
    for line in manifest.splitlines():
        var row = String(line)
        var parts = row.split(" ")
        if (
            len(parts) >= 2
            and String(parts[1]) == name
            and (
                String(parts[0]) == "B"
                or String(parts[0]) == "C"
                or String(parts[0]) == "M"
            )
        ):
            actual.append(row)
    sort(actual)
    sort(wanted)
    if not _same(actual, wanted):
        var shown = String()
        for row in actual:
            shown += "actual " + row + "\n"
        for row in wanted:
            shown += "wanted " + row + "\n"
        raise Error(name + " manifest changed\n" + shown)


def check_custom_truth_instrumented(mojo: String) raises:
    """Require the supported custom-truth trees to match after instrumentation.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If the native rows, the manifest, or an instrumented trace differ.
    """
    var root = absolute_path(".")
    var compiler = absolute_path(mojo)
    var source = Path("tools/fixtures/coverage_truth_accepted.txt").read_text()
    var work = mkdtemp(prefix="threemojo-truth-accepted-")
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
        var name = "truth"
        Path(native + "/" + name + ".mojo").write_text(source)
        var binary = work + "/" + name + "-native"
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                native,
                native + "/" + name + ".mojo",
                "-o",
                binary,
            ],
            180,
        )
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
        _ = _must([build, rewritten, name + ".mojo"], 60, native)
        _require_origin(rewritten, name, source)
        _require_accepted_manifest(rewritten, name, source)
        var instrumented_binary = work + "/" + name + "-instrumented"
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                rewritten,
                rewritten + "/" + name + ".mojo",
                "-o",
                instrumented_binary,
            ],
            180,
        )
        for changing in [False, True]:
            var flag = "0"
            if changing:
                flag = "1"
            var expected = _truth_accepted_rows(changing)
            for binary_path in [binary, instrumented_binary]:
                var temp = mkdtemp(prefix="threemojo-truth-accepted-run-")
                var ran = _must(
                    _with_env(
                        [
                            "TMPDIR=" + temp,
                            "THREEMOJO_TEST_TMPDIR=" + temp,
                            "THREEMOJO_TRUTH_CHANGING=" + flag,
                        ],
                        [binary_path],
                    ),
                    10,
                )
                _ = _must(["rm", "-rf", temp], 10)
                if (
                    len(result_errors(ran.output)) > 0
                    or len(slow_tests(ran.output, 5.0)) > 0
                ):
                    raise Error(ran.output)
                if _truth_lines(ran.output) != expected:
                    raise Error(ran.output)
                if binary_path == instrumented_binary:
                    for number in _truth_accepted_numbers():
                        var seen = _truth_coverage(
                            ran.errors, name, _truth_accepted_line(number)
                        )
                        var wanted = _truth_tree_trace(number, changing)
                        if seen != wanted:
                            raise Error(
                                "trace "
                                + String(number)
                                + "\n"
                                + seen
                                + "\n"
                                + wanted
                            )
        print(
            "PASS: 13 instrumented custom truth trees, 16 masks, and 5 failure"
            " positions, stable and changing"
        )
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
        check_lifetime(mojo)
        check_identity(mojo)
        check_last_use(mojo)
        check_temporary_identity(mojo)
        check_generic_pair(mojo)
        check_single_generic(mojo)
        check_custom_truth_native(mojo)
        check_custom_truth_instrumented(mojo)
    except error:
        print(String(error), file=stderr)
        exit(1)
