# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compile native and instrumented Boolean fixtures and compare exact behavior.

This is a separate integration check because test-tools needs no compiler.
Every built suite retains the five-second per-test limit. Build time is not
part of that limit. No device or external service is used.
"""

import argparse
from collections import defaultdict
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap

from coverage_io import Reducer
from run_suite import result_errors, slow_tests
from test_environment import isolated_environment

ROOT = Path(__file__).resolve().parent.parent

# A small independent Boolean tree supplies expected short-circuit order.
# An atomic subtree is deliberately opaque to the instrumenter.
CASES = [
    ('(((P0 or P1) and P2))', ('and', ('or', 0, 1), 2)),
    ('not (P0 and (P1 or not P2))', ('not', ('and', 0, ('or', 1, ('not', 2))))),
    ('(P0 or P1 and P2) and not not P3',
     ('and', ('or', 0, ('and', 1, 2)), ('not', ('not', 3)))),
    ('(\n            (P0 and P1)  # first group\n'
     '            or (not P2 and P3)\n        )',
     ('or', ('and', 0, 1), ('and', ('not', 2), 3))),
    ('(identity(P0 or P1, "and or") and values[Int(P2)] '
     'or (P3 and P4) == P5)',
     ('or', ('and', ('atom', ('or', 0, 1)), ('atom', 2)),
      ('atom', ('eq', ('and', 3, 4), 5)))),
    ('not(P0)or((P1)and(P2))', ('or', ('not', 0), ('and', 1, 2))),
    ('((quoted(mask, order, fail) == "\\\" and #:( or [") or P1) and P2',
     ('and', ('or', ('atom', 0), 1), 2)),
    ('(((not (P0))))', ('not', 0)),
    ('(P0 or P1 or P2)', ('or', ('or', 0, 1), 2)),
    ('P0 if P1 else P2 and P3', ('atom', ('choose', 0, 1, ('and', 2, 3)))),
    ('((P0 and P1) if P2 else (P3 or P4)) and P5',
     ('and', ('atom', ('choose', ('and', 0, 1), 2, ('or', 3, 4))), 5)),
    ('(not P0 if P1 else P2) or P3',
     ('or', ('atom', ('choose', ('not', 0), 1, 2)), 3)),
    ('(P1 or triple(mask, order, fail) == """hello" and word""")',
     ('or', 1, ('atom', 0))),
    ('(P1 or triple_lines(mask, order, fail) == """hello"\n# ) and or\nworld""")',
     ('or', 1, ('atom', 0))),
    ('P0 and (1 not in member_values(mask, order, fail))',
     ('and', 0, ('atom', ('not', 1)))),
    ('scalar_bool(P0) and P1', ('and', 0, 1)),
    ('optional_value(P0)', 0),
    ('optional_custom(P0, order) or P1', ('or', 0, 1)),
    ('list_custom(P0, order) and P1', ('and', 0, 1)),
    ('not P0 or not (optional_value(P1) or P2)',
     ('or', ('not', 0), ('not', ('or', 1, 2)))),
    ('optional_value(P0) and (optional_value(P1) or P2)',
     ('and', 0, ('or', 1, 2))),
    ('text_value(P0) and Int(P1) or list_value(P2)',
     ('or', ('and', 0, 1), 2)),
    ('borrowed if P1 else borrowed',
     ('atom', ('choose', ('boolable', 0), 1, ('boolable', 0)))),
]


def evaluate(tree, mask, fail, order, probes, slot):
    """Evaluate the independent reference tree with observable leaf calls."""
    if isinstance(tree, int):
        order.append(str(tree))
        if tree == fail:
            raise ValueError('fixture exception')
        value = bool(mask & (1 << tree))
        if slot is not None:
            probes.append((slot[0], value))
            slot[0] += 1
        return value
    op, *args = tree
    if op == 'boolable':
        order.append('b')
        value = bool(mask & (1 << args[0]))
        if slot is not None:
            probes.append((slot[0], value))
            slot[0] += 1
        return value
    if op == 'choose':
        choose = evaluate(args[1], mask, fail, order, [], None)
        return evaluate(args[0] if choose else args[2], mask, fail, order, [], None)
    if op == 'atom':
        value = evaluate(args[0], mask, fail, order, [], None)
        probes.append((slot[0], value))
        slot[0] += 1
        return value
    if op == 'not':
        return not evaluate(args[0], mask, fail, order, probes, slot)
    left = evaluate(args[0], mask, fail, order, probes, slot)
    if op == 'and' and not left or op == 'or' and left:
        if slot is not None:
            slot[0] += leaves(args[1])
        return left
    right = evaluate(args[1], mask, fail, order, probes, slot)
    return left == right if op == 'eq' else right


def leaves(tree):
    if isinstance(tree, int) or tree[0] in ('atom', 'boolable'):
        return 1
    return sum(leaves(child) for child in tree[1:])


def fixture_source():
    text = '''from std.os import getenv
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
        return """hello"
# ) and or
world"""
    return "different"


def quoted(mask: Int, mut order: String, fail: Int) raises -> String:
    if mark(mask, 0, order, fail):
        return '" and #:( or ['
    return "different"
'''
    decisions = []
    for number, (expression, tree) in enumerate(CASES):
        for index in range(6):
            expression = expression.replace(f'P{index}', f'mark(mask, {index}, order, fail)')
        text += f'''

def case_{number}(mask: Int, fail: Int) raises:
    var order = String("")
    var values: List[Bool] = [False, True]
    _ = values
    var borrowed = observable((mask & 1) != 0, order)
    try:
'''
        decisions.append(len(text.splitlines()) + 1)
        text += f'''        if {expression}:
            print("RESULT", {number}, mask, fail, "T", order)
        else:
            print("RESULT", {number}, mask, fail, "F", order)
    except error:
        print("RESULT", {number}, mask, fail, "E", order, String(error))
    _ = borrowed.value
'''
    text += '\n\ndef test_semantics() raises:\n    var fail = Int(getenv("THREEMOJO_GROUPING_FAIL", "-1"))\n    for mask in range(64):\n'
    for number in range(len(CASES)):
        text += f'        case_{number}(mask, fail)\n'
    text += '\n\ndef main() raises:\n    TestSuite.discover_tests[__functions_in_module()]().run()\n'
    return text, decisions


def lifetime_source():
    """Observe move-only container destruction before later operands and bodies."""
    s = textwrap.dedent('''\
    @fieldwise_init
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
    ''')
    cases = []
    for kind in ('optional', 'items'):
        other = 'items' if kind == 'optional' else 'optional'
        for first in ('True', 'False'):
            for second in ('True', 'False'):
                left = f'{kind}(1, {first}, drops)'
                right = f'{kind}(2, {second}, drops)'
                mixed = f'{other}(2, {second}, drops)'
                observe = f'observe(3, {second}, drops)'
                for expression in (
                    f'{left} and {right}', f'{left} or {right}',
                    f'{left} and {observe}', f'{left} or {observe}',
                    f'({left} or {right}) and {observe}',
                    f'({left} and {right}) or {observe}',
                    f'not ({left} or {right})',
                    f'retained and {observe}', f'retained or {observe}',
                    f'(retained or {observe}) and {left}',
                    f'(retained and {observe}) or {left}',
                    f'{left} and {mixed}', f'{left} or {mixed}',
                ):
                    number = len(cases)
                    cases.append(expression)
                    s += f"""
def case_{number}():
    print("CASE", {number})
    var state = 0
    var drops = Pointer(to=state).unsafe_origin_cast[MutUntrackedOrigin]()
    var retained = {kind}(4, {first}, drops)
    if {expression}:
        print("BODY", {number}, state)
    else:
        print("ELSE", {number}, state)
    print("AFTER", {number}, Bool(retained), state)
"""
    s += '\ndef main():\n' + ''.join(
        f'    case_{number}()\n    print("END", {number})\n'
        for number in range(len(cases)))
    return s, cases


# Custom Boolable compound operands (issue #560). Leaves: ('S', i) a temporary
# Probe, ('D', i) a temporary Other, ('B', i) a Bool, ('X', i) a retained
# move-only Probe, ('C', i) a retained implicitly copyable Shared, ('M', i) a
# temporary Moving with a user-defined move constructor, ('P', i) a retained
# and ('Q', i) a temporary Bits whose copy, move and destruction are bitwise,
# ('T', i) a temporary Shared, and ('choose', condition, then, else) an
# opaque conditional expression. A Moving is only in two-type operators. A
# retained Shared is in a one-type operator only as the right operand: the
# operator copies it. A Bits is in both, also twice as one retained variable. Pinned Mojo 1.1.0 lowers `and`/`or` by operand type. With one
# type, it tests the left operand, then returns it or the right operand
# unconverted, and the enclosing operator or truth context tests the selected
# object again. With two types, it converts each evaluated operand once.
TRUTH_CASES = [
    ('or', ('S', 0), ('S', 1)),
    ('and', ('S', 0), ('S', 1)),
    ('or', ('or', ('S', 0), ('S', 1)), ('S', 2)),
    ('or', ('and', ('S', 0), ('S', 1)), ('S', 2)),
    ('or', ('S', 0), ('and', ('S', 1), ('S', 2))),
    ('not', ('or', ('S', 0), ('S', 1))),
    ('and', ('not', ('S', 0)), ('S', 1)),
    ('or', ('S', 0), ('D', 1)),
    ('and', ('D', 0), ('or', ('S', 1), ('S', 2))),
    ('and', ('or', ('S', 0), ('S', 1)), ('or', ('S', 2), ('S', 3))),
    ('or', ('and', ('S', 0), ('S', 1)), ('B', 2)),
    ('or', ('B', 0), ('and', ('S', 1), ('S', 2))),
    ('or', ('X', 0), ('B', 1)),
    ('or', ('and', ('B', 0), ('not', ('X', 1))), ('S', 2)),
    ('or', ('and', ('X', 0), ('D', 1)), ('S', 2)),
    ('or', ('choose', ('B', 1), ('S', 2), ('S', 3)), ('S', 0)),
    ('and', ('or', ('D', 0), ('D', 1)), ('S', 2)),
    ('or', ('C', 0), ('B', 1)),
    ('and', ('B', 0), ('C', 1)),
    ('or', ('and', ('C', 0), ('S', 1)), ('S', 2)),
    ('and', ('or', ('S', 0), ('S', 1)), ('not', ('C', 2))),
    ('or', ('C', 0), ('or', ('X', 1), ('and', ('C', 2), ('B', 3)))),
    ('and', ('C', 0), ('D', 1)),
    ('or', ('choose', ('B', 1), ('C', 2), ('C', 3)), ('S', 0)),
    ('or', ('M', 0), ('B', 1)),
    ('and', ('B', 0), ('M', 1)),
    ('or', ('not', ('M', 0)), ('and', ('S', 1), ('M', 2))),
    ('and', ('or', ('M', 0), ('D', 1)), ('or', ('S', 2), ('S', 3))),
    ('and', ('M', 0), ('C', 1)),
    ('or', ('choose', ('B', 1), ('M', 2), ('M', 3)), ('C', 0)),
    ('and', ('or', ('P', 0), ('P', 1)), ('B', 2)),
    ('and', ('P', 0), ('or', ('P', 1), ('Q', 2))),
    ('or', ('or', ('Q', 0), ('P', 1)), ('B', 2)),
    ('and', ('not', ('P', 0)), ('or', ('P', 1), ('or', ('P', 2), ('Q', 3)))),
    ('or', ('choose', ('B', 1), ('P', 2), ('P', 3)), ('P', 0)),
    ('or', ('and', ('P', 0), ('P', 0)), ('B', 1)),
    ('and', ('or', ('P', 0), ('S', 1)), ('or', ('Q', 2), ('P', 3))),
    ('or', ('T', 0), ('C', 1)),
    ('and', ('or', ('T', 0), ('C', 1)), ('B', 2)),
    ('or', ('or', ('T', 0), ('C', 1)), ('C', 2)),
    ('and', ('T', 0), ('or', ('B', 1), ('C', 2))),
    ('or', ('T', 0), ('choose', ('B', 1), ('C', 2), ('C', 3))),
    ('and', ('T', 0), ('not', ('C', 1))),
]



def fresh(tree):
    """Rebuild a tree so each leaf is its own object.

    Python can share equal tuple constants, and the slots are keyed by object.
    """
    return tuple(fresh(child) if isinstance(child, tuple) else child for child in tree)


TRUTH_CASES = [fresh(tree) for tree in TRUTH_CASES]


def truth_type(tree):
    """Return the native static type of a subexpression: S, D, C or Bool (B)."""
    kind = tree[0]
    if kind in ('S', 'X'):
        return 'S'
    if kind in ('P', 'Q'):
        return 'P'
    if kind == 'T':
        return 'C'
    if kind in ('D', 'B', 'C', 'M'):
        return kind
    if kind == 'choose':
        return truth_type(tree[2])
    if kind == 'not':
        return 'B'
    left, right = truth_type(tree[1]), truth_type(tree[2])
    return left if left == right else 'B'


# The fixture's own names. COLLISION_NAMES renders the same trees with names
# that shadow caller-scope types and take the instrumenter's default prefixes.
TRUTH_NAMES = {'probe': 'probe', 'other': 'other', 'flag': 'flag', 'moving': 'moving',
               'bits': 'bits', 'shared': 'shared',
               'state': 'state', 'cell': 'cell',
               'retained': ['retained0', 'retained1', 'retained2', 'retained3']}
COLLISION_NAMES = {'probe': '_cov_eval_leaf', 'other': '_cov_eval_node',
                   'flag': '_cov_branch', 'moving': '_cov_eval_buffer',
                   'bits': '_cov_eval_truth', 'shared': '_cov_eval_right',
                   'state': '_cov_eval_state0',
                   'cell': '_cov_hit',
                   'retained': ['List', 'Int', 'Bool', '_cov_eval_finish']}


def truth_text(tree, top=True, names=TRUTH_NAMES):
    """Render a reference tree as fixture source text."""
    kind = tree[0]
    state = names['state']
    if kind == 'S':
        return f'{names["probe"]}({tree[1]}, {state})'
    if kind == 'D':
        return f'{names["other"]}({tree[1]}, {state})'
    if kind == 'B':
        return f'{names["flag"]}({tree[1]}, {state})'
    if kind == 'M':
        return f'{names["moving"]}({tree[1]}, {state})'
    if kind == 'Q':
        return f'{names["bits"]}({tree[1]}, {state})'
    if kind == 'T':
        return f'{names["shared"]}({tree[1]}, {state})'
    if kind in ('X', 'C', 'P'):
        return names['retained'][tree[1]]
    if kind == 'choose':
        return (f'({truth_text(tree[2], False, names)} if '
                f'{truth_text(tree[1], False, names)}'
                f' else {truth_text(tree[3], False, names)})')
    if kind == 'not':
        return f'not {truth_text(tree[1], False, names)}'
    text = (f'{truth_text(tree[1], False, names)} {kind} '
            f'{truth_text(tree[2], False, names)}')
    return text if top else f'({text})'


def truth_slots(tree, slots=None):
    """Number the instrumented leaves left to right; a conditional is one."""
    slots = {} if slots is None else slots
    if tree[0] in ('S', 'D', 'B', 'X', 'C', 'M', 'P', 'Q', 'T', 'choose'):
        slots[id(tree)] = len(slots)
    else:
        for child in tree[1:]:
            truth_slots(child, slots)
    return slots


class TruthFailure(Exception):
    pass


class TruthModel:
    """Evaluate one decision as native Mojo does and as the probes record it."""

    def __init__(self, tree, mask, fail, changing, line, module='truth'):
        self.tree, self.mask, self.fail, self.changing = tree, mask, fail, changing
        self.line, self.slots, self.module = line, truth_slots(tree), module
        self.log, self.records, self.states = [], [], {}
        self.counts = defaultdict(int)

    def bit(self, name):
        return bool(self.mask & (1 << name))

    def enter(self, name):
        self.log.append(f'+{name}')
        if name == self.fail:
            raise TruthFailure()

    def observe(self, slot, value):
        # Mirrors the runtime: the first truth fills the slot, a later
        # disagreeing truth marks it inconsistent and is recorded too.
        state = self.states.get(slot, -1)
        if state == int(value):
            return
        self.states[slot] = int(value) if state < 0 else 2
        self.records.append(
            f'COVLINE:{self.module}:{self.line}.{slot}:{"T" if value else "F"}')

    def convert(self, item):
        kind, name, slot, _ = item
        if kind == 'B':
            return name
        self.log.append(str(name))
        count = self.counts[name]
        self.counts[name] += 1
        value = self.bit(name) != (self.changing and count % 2 == 1)
        self.observe(slot, value)
        return value

    def drop(self, item):
        kind, name, _, retained = item
        # A Bits destruction is bitwise and logs nothing.
        if kind not in ('B', 'Q') and not retained:
            self.log.append(f'~{name}')

    def evaluate(self, tree, owned=False):
        """Evaluate a subtree. `owned` marks the right operand of a one-type
        operator: the operator copies a retained Shared when it evaluates it.
        The fixture keeps every retained value alive, so it is never moved."""
        kind = tree[0]
        slot = self.slots.get(id(tree))
        if kind in ('S', 'D', 'M', 'Q', 'T'):
            self.enter(tree[1])
            return (kind, tree[1], slot, False)
        if kind == 'C' and owned:
            self.log.append(f'={tree[1]}')
            return ('S', tree[1], slot, False)
        if kind in ('X', 'C', 'P'):
            return ('S', tree[1], slot, True)
        if kind == 'B':
            self.enter(tree[1])
            value = self.bit(tree[1])
            self.observe(slot, value)
            return ('B', value, slot, False)
        if kind == 'choose':
            self.enter(tree[1][1])
            chosen = tree[2] if self.bit(tree[1][1]) else tree[3]
            if chosen[0] in ('C', 'P'):
                # Two retained arms give a reference to the selected one:
                # the conditional neither copies nor destroys it. A one-type
                # operator then copies a selected Shared, as a variable.
                kind, name, _, retained = self.evaluate(chosen, owned)
                return (kind, name, slot, retained)
            self.enter(chosen[1])
            if chosen[0] == 'M':
                # The selected temporary moves into the conditional's result.
                self.log.append(f'>{chosen[1]}')
            return ('S', chosen[1], slot, False)
        if kind == 'not':
            item = self.evaluate(tree[1])
            value = self.convert(item)
            self.drop(item)
            return ('B', not value, None, False)
        same = truth_type(tree[1]) == truth_type(tree[2])
        # A one-type operator moves a selected Moving after it converts it,
        # and copies a selected retained left Shared. Both are refused.
        assert not (same and truth_type(tree[1]) == 'M'), tree
        left = self.evaluate(tree[1])
        assert not (same and truth_type(tree[1]) == 'C' and left[3]), tree
        value = self.convert(left)
        short = value if kind == 'or' else not value
        if same:
            if short:
                return left
            self.drop(left)
            return self.evaluate(tree[2], owned=tree[2][0] in ('C', 'choose'))
        self.drop(left)
        if short:
            return ('B', value, None, False)
        right = self.evaluate(tree[2])
        value = self.convert(right)
        self.drop(right)
        return ('B', value, None, False)

    def run(self):
        retained = [leaf for leaf in truth_leaves(self.tree) if leaf[0] in ('X', 'C')]
        try:
            item = self.evaluate(self.tree)
            outcome = self.convert(item)
            self.drop(item)
        except TruthFailure:
            outcome = None
        self.log.append('|E' if outcome is None else ('|T' if outcome else '|F'))
        self.log.extend(f'~{leaf[1]}' for leaf in retained)
        vector = None
        if outcome is not None:
            self.records.append(f'COVLINE:{self.module}:{self.line}:{"T" if outcome else "F"}')
            vector = ''.join('FT?'[self.states[slot]] if slot in self.states else '-'
                             for slot in range(len(self.slots)))
            vector = f'COVEVAL2:{self.module}:{self.line}:{"T" if outcome else "F"}:{vector};'
        return ''.join(self.log), self.records, vector


def truth_leaves(tree):
    if tree[0] in ('S', 'D', 'B', 'X', 'C', 'M', 'P', 'Q', 'T'):
        return [tree]
    return [leaf for child in tree[1:] for leaf in truth_leaves(child)]


TRUTH_PRELUDE = '''from std.os import getenv
from std.testing import TestSuite


struct State(Movable):
    var log: String
    var mask: Int
    var fail: Int
    var changing: Bool
    var counts: List[Int]

    def __init__(out self, mask: Int, fail: Int, changing: Bool):
        self.log = String("")
        self.mask = mask
        self.fail = fail
        self.changing = changing
        self.counts = List[Int](length=8, fill=0)

    def enter(mut self, index: Int) raises:
        self.log += "+" + String(index)
        if index == self.fail:
            raise Error("fixture exception")

    def convert(mut self, index: Int) -> Bool:
        self.log += String(index)
        var count = self.counts[index]
        self.counts[index] = count + 1
        var value = (self.mask & (1 << index)) != 0
        return value != (self.changing and count % 2 == 1)


comptime Cell = Pointer[State, MutUntrackedOrigin]


trait Made(Boolable, Movable, Deinitable):
    @staticmethod
    def make(index: Int, state: Cell) -> Self:
        ...


struct Probe(Made):
    var index: Int
    var state: Cell

    def __init__(out self, index: Int, state: Cell):
        self.index = index
        self.state = state

    @staticmethod
    def make(index: Int, state: Cell) -> Self:
        return Self(index, state)

    def __bool__(self) -> Bool:
        return self.state[].convert(self.index)

    def __deinit__(deinit self):
        self.state[].log += "~" + String(self.index)


struct Other(Made):
    var index: Int
    var state: Cell

    def __init__(out self, index: Int, state: Cell):
        self.index = index
        self.state = state

    @staticmethod
    def make(index: Int, state: Cell) -> Self:
        return Self(index, state)

    def __bool__(self) -> Bool:
        return self.state[].convert(self.index)

    def __deinit__(deinit self):
        self.state[].log += "~" + String(self.index)


struct Shared(ImplicitlyCopyable, Boolable):
    var index: Int
    var state: Cell

    def __init__(out self, index: Int, state: Cell):
        self.index = index
        self.state = state

    def __init__(out self, *, copy: Self):
        self.index = copy.index
        self.state = copy.state
        self.state[].log += "=" + String(self.index)

    def __bool__(self) -> Bool:
        return self.state[].convert(self.index)

    def __deinit__(deinit self):
        self.state[].log += "~" + String(self.index)


struct Moving(Made):
    var index: Int
    var state: Cell

    @staticmethod
    def make(index: Int, state: Cell) -> Self:
        return Self(index, state)

    def __init__(out self, index: Int, state: Cell):
        self.index = index
        self.state = state

    def __init__(out self, *, deinit move: Self):
        self.index = move.index
        self.state = move.state
        self.state[].log += ">" + String(self.index)

    def __bool__(self) -> Bool:
        return self.state[].convert(self.index)

    def __deinit__(deinit self):
        self.state[].log += "~" + String(self.index)


@fieldwise_init
struct Bits(ImplicitlyCopyable, Boolable):
    var index: Int
    var state: Cell

    def __bool__(self) -> Bool:
        return self.state[].convert(self.index)


def bits(index: Int, state: Cell) raises -> Bits:
    state[].enter(index)
    return Bits(index, state)


def shared(index: Int, state: Cell) raises -> Shared:
    state[].enter(index)
    return Shared(index, state)


def moving(index: Int, state: Cell) raises -> Moving:
    state[].enter(index)
    return Moving(index, state)


def probe(index: Int, state: Cell) raises -> Probe:
    state[].enter(index)
    return Probe(index, state)


def other(index: Int, state: Cell) raises -> Other:
    state[].enter(index)
    return Other(index, state)


def flag(index: Int, state: Cell) raises -> Bool:
    state[].enter(index)
    return (state[].mask & (1 << index)) != 0
'''


def truth_source(names=TRUTH_NAMES):
    """Generate one function per reference tree; return the decision lines."""
    text = TRUTH_PRELUDE
    for name in ('probe', 'other', 'flag', 'moving', 'bits', 'shared'):
        text = text.replace(f'\ndef {name}(', f'\ndef {names[name]}(')
    state, cell, retained_names = names['state'], names['cell'], names['retained']
    lines = []
    for number, tree in enumerate(TRUTH_CASES):
        kept = list({leaf[1]: leaf for leaf in truth_leaves(tree)
                     if leaf[0] in ('X', 'C', 'P')}.values())
        retained = ''.join(
            f'    var {retained_names[leaf[1]]} = '
            f'{dict(X="Probe", C="Shared", P="Bits")[leaf[0]]}({leaf[1]}, {state})\n'
            for leaf in kept)
        released = ''.join(f'    _ = {retained_names[leaf[1]]}^\n' for leaf in kept)
        text += f'''

def truth_{number}(mask: Int, fail: Int, changing: Bool):
    var {cell} = State(mask, fail, changing)
    var {state} = Pointer(to={cell}).unsafe_origin_cast[MutUntrackedOrigin]()
{retained}    try:
'''
        lines.append(len(text.splitlines()) + 1)
        text += f'''        if {truth_text(tree, names=names)}:
            {state}[].log += "|T"
        else:
            {state}[].log += "|F"
    except error:
        {state}[].log += "|E"
{released}    print("TRUTH", {number}, mask, fail, changing, {state}[].log)
    _ = {cell}^
'''
    text += '''

def test_truth() raises:
    var changing = getenv("THREEMOJO_TRUTH_CHANGING", "0") == "1"
    for fail in range(-1, 4):
        for mask in range(16):
'''
    text += ''.join(f'            truth_{number}(mask, fail, changing)\n'
                    for number in range(len(TRUTH_CASES)))
    text += '\n\ndef main() raises:\n    TestSuite.discover_tests[__functions_in_module()]().run()\n'
    return text, lines


# Native-only controls without an independent model: the instrumented output
# must equal the native output byte for byte.
TRUTH_CONTROLS = TRUTH_PRELUDE.replace(
    'from std.testing import TestSuite\n',
    'from std.testing import TestSuite\nfrom render.tasks import TaskGroup\n') + '''

struct Pinned(Boolable):
    """A temporary that can be neither moved nor copied."""

    var index: Int
    var state: Cell

    def __init__(out self, index: Int, state: Cell):
        self.index = index
        self.state = state

    def __bool__(self) -> Bool:
        return self.state[].convert(self.index)

    def __deinit__(deinit self):
        self.state[].log += "~" + String(self.index)


@fieldwise_init
struct Copied(ImplicitlyCopyable, Boolable):
    var value: Bool

    def __bool__(self) -> Bool:
        return self.value


def optional_probe(index: Int, state: Cell) raises -> Optional[Probe]:
    state[].enter(index)
    if (state[].mask & (1 << index)) != 0:
        return Probe(index, state)
    return None


def nested_optional(full: Bool) -> Optional[Optional[Int]]:
    if full:
        return Optional[Int](None)
    return None


def depth(count: Int, state: Cell) raises -> Int:
    if probe(0, state) and (probe(1, state) or flag(2, state)) and count > 0:
        return 1 + depth(count - 1, state)
    return 0


def generic_retained[A: Boolable & ImplicitlyCopyable](value: A, state: Cell) raises -> Bool:
    # One instantiation borrows a retained Shared; one has two Bool operands.
    if value or flag(1, state):
        return True
    return False


def generic_pair[A: Made, B: Made](state: Cell) -> Bool:
    # The operator checks run per instantiation: one type, then two types.
    if A.make(0, state) or B.make(1, state) and A.make(2, state):
        return True
    return False


def controls(mask: Int, changing: Bool) raises:
    var cell = State(mask, -1, changing)
    var state = Pointer(to=cell).unsafe_origin_cast[MutUntrackedOrigin]()
    var loops = 0
    while (probe(0, state) or probe(1, state)) and loops < 3:
        loops += 1
        state[].log += "|W"
    state[].log += "|"
    if probe(0, state) and probe(1, state):
        state[].log += "|A"
    elif not probe(2, state) or other(3, state):
        state[].log += "|B"
    elif probe(1, state) or probe(2, state):
        state[].log += "|C"
    state[].log += "|"
    var unpinned = Probe(3, state)
    if flag(0, state) and not unpinned or probe(1, state):
        state[].log += "|U"
    state[].log += "|"
    # Retained Shared operands in two-type operators, without a pinned
    # lifetime. The log records every copy, conversion and destruction.
    var held = Shared(3, state)
    if flag(0, state) and not held or probe(1, state):
        state[].log += "|V"
    state[].log += "|"
    var kept = Shared(2, state)
    if kept or flag(1, state):
        state[].log += "|Y"
    elif probe(0, state) and kept:
        state[].log += "|Z"
    state[].log += "|" + String(generic_retained(kept, state))
    state[].log += "|" + String(generic_retained(mask % 2 == 0, state))
    state[].log += "|"
    # A one-type operator copies a live retained right operand and moves it
    # at its last use.
    var live = Shared(2, state)
    if shared(0, state) and live:
        state[].log += "|L"
    var last = Shared(1, state)
    if shared(0, state) or last:
        state[].log += "|M"
    state[].log += "|" + String(Bool(live)) + "|"
    if Pinned(1, state) or flag(2, state) and Pinned(3, state):
        state[].log += "|P"
    state[].log += "|"
    if optional_probe(0, state) and flag(1, state) or probe(2, state):
        state[].log += "|O"
    state[].log += "|"
    var maybe = Optional[Int](mask) if mask % 3 == 0 else None
    var other = Optional[Int](None) if mask % 2 == 0 else Optional[Int](0)
    var number = mask % 2
    if (maybe or other) and (number or flag(1, state)) or String("x") and List[Int](length=mask, fill=0):
        state[].log += "|S"
    state[].log += "|"
    if nested_optional(mask % 2 == 0) or nested_optional(mask % 3 == 0):
        state[].log += "|N"
    if nested_optional(mask % 2 == 0) and nested_optional(mask % 3 == 0):
        state[].log += "|D"
    state[].log += "|"
    var copied = Copied(mask % 2 == 0)
    if copied:
        state[].log += "|K"
    state[].log += "|" + String(depth(mask % 4, state))
    state[].log += "|" + String(generic_pair[Probe, Probe](state))
    state[].log += "|" + String(generic_pair[Probe, Other](state))
    state[].log += "|" + String(generic_pair[Probe, Moving](state))
    print("CONTROL", mask, changing, state[].log)
    _ = cell^


def worker(index: Int, iteration: Int) -> Bool:
    var cell = State(index * 7 + iteration, -1, False)
    var state = Pointer(to=cell).unsafe_origin_cast[MutUntrackedOrigin]()
    var result = False
    if Probe(0, state) or Probe(1, state) and Other(2, state):
        result = True
    _ = cell^
    return result


async def task(index: Int, totals: MutPointer[Int, MutAnyOrigin]):
    var total = 0
    for iteration in range(64):
        total += Int(worker(index, iteration))
    totals[unsafe_offset=index] = total


def test_controls() raises:
    for changing in [False, True]:
        for mask in range(16):
            controls(mask, changing)
    var totals = List[Int](length=8, fill=0)
    var group = TaskGroup()
    for index in range(8):
        group.create_task(task(index, totals.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()))
    group.wait()
    print("CONCURRENT", totals)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
'''

def nested_optional_rejections():
    """Model selection before an inner Optional wraps into the result type.

    Both operators first test the original left operand. The selected inner
    Optional becomes present in the outer result, even when it was empty.
    Construction logs also prove which right operands were short-circuited.
    """
    prelude = '''def inner(full: Bool) -> Optional[Int]:
    print("MAKE inner")
    if full:
        return 0
    return None


def outer(full: Bool) -> Optional[Optional[Int]]:
    print("MAKE outer")
    if full:
        return Optional[Int](None)
    return None
'''
    cases = {}
    for first, second in (("inner", "outer"), ("outer", "inner")):
        for operator in ("and", "or"):
            source = prelude + f'''

def main():
    for mask in range(4):
        print("CASE", mask)
        var left = (mask & 1) != 0
        var right = (mask & 2) != 0
        if {first}(left) {operator} {second}(right):
            print("T")
        else:
            print("F")
'''
            expected = []
            for mask in range(4):
                left, right = bool(mask & 1), bool(mask & 2)
                expected += [f"CASE {mask}", f"MAKE {first}"]
                short = left if operator == "or" else not left
                selected, present = (first, left) if short else (second, right)
                if not short:
                    expected.append(f"MAKE {second}")
                expected.append("T" if selected == "inner" or present else "F")
            cases[f"nested-optional-{first}-{operator}"] = (source, "\n".join(expected) + "\n")
    return cases


NESTED_OPTIONAL_REJECTIONS = nested_optional_rejections()


# Unsupported operands must fail compilation with the coverage diagnostic.
TRUTH_REJECTED = {
    # A one-type operator selects an owned copy or move of a retained
    # operand. 'copyable-retained-self' proves the native copy: two
    # borrowing proxies of one origin have one type and would pass a
    # type comparison alone.
    'copyable-retained': ('''struct Copied(ImplicitlyCopyable, Boolable):
    var value: Bool

    def __init__(out self, value: Bool):
        self.value = value

    def __init__(out self, *, copy: Self):
        self.value = copy.value
        print("COPY")

    def __bool__(self) -> Bool:
        print("CONVERT")
        return self.value


def main():
    var copied = Copied(True)
    var other = Copied(False)
    if copied or other:
        print("T")
    else:
        print("F")
''', 'a one-type operator that selects a retained operand whose copy runs source'),
    'copyable-retained-self': ('''struct Copied(ImplicitlyCopyable, Boolable):
    var value: Bool

    def __init__(out self, value: Bool):
        self.value = value

    def __init__(out self, *, copy: Self):
        self.value = copy.value
        print("COPY")

    def __bool__(self) -> Bool:
        print("CONVERT")
        return self.value


def main():
    var copied = Copied(False)
    if copied or copied:
        print("T")
    else:
        print("F")
    print(copied.value)
''', 'a one-type operator that selects a retained operand whose copy runs source'),
    'copyable-retained-temporary': ('''struct Copied(ImplicitlyCopyable, Boolable):
    var value: Bool

    def __init__(out self, value: Bool):
        self.value = value

    def __init__(out self, *, copy: Self):
        self.value = copy.value
        print("COPY")

    def __bool__(self) -> Bool:
        print("CONVERT")
        return self.value


def main():
    var copied = Copied(True)
    if copied or Copied(False):
        print("T")
    else:
        print("F")
    print(copied.value)
''', 'a one-type operator that selects a retained operand whose copy runs source'),
    # Before issue #560, a retained Optional became Bool and lost this copy.
    'optional-copied-element': ('''struct Logged(ImplicitlyCopyable):
    var name: Int

    def __init__(out self, name: Int):
        self.name = name

    def __init__(out self, *, copy: Self):
        self.name = copy.name
        print("COPY")


def main():
    var empty = Optional[Logged](None)
    var full = Optional[Logged](Logged(1))
    if empty or full:
        print("T")
    else:
        print("F")
    print(full.value().name)
''', 'a one-type operator that selects a retained operand whose copy runs source'),
    'custom-move-same': ('''struct Moving(Boolable, Movable):
    var value: Bool

    def __init__(out self, value: Bool):
        self.value = value

    def __init__(out self, *, deinit move: Self):
        self.value = move.value
        print("MOVE")

    def __bool__(self) -> Bool:
        print("CONVERT")
        return self.value


def main():
    if Moving(False) or Moving(True):
        print("T")
    else:
        print("F")
''', 'a one-type operator over a type with a user-defined move'),
    'optional-join': ('''struct Probe(Movable, Boolable):
    var value: Bool

    def __init__(out self, value: Bool):
        self.value = value

    def __bool__(self) -> Bool:
        print("CONVERT")
        return self.value


def empty() -> Optional[Probe]:
    return None


def main():
    if empty() or Probe(False):
        print("T")
    else:
        print("F")
''', 'an implicit conversion between operand types'),
    'pure-optional-join': ('''def main():
    var empty = Optional[Int](None)
    var zero = 0
    if empty or zero:
        print("T")
    else:
        print("F")
''', 'an implicit conversion between operand types'),
    **{name: (source, 'an implicit conversion between operand types')
       for name, (source, _) in NESTED_OPTIONAL_REJECTIONS.items()},
    'implicit-join': ('''struct Lifted(Movable, Boolable):
    var value: Bool

    @implicit
    def __init__(out self, value: Bool):
        print("LIFT")
        self.value = value

    def __bool__(self) -> Bool:
        print("CONVERT")
        return self.value


def main():
    var flag = True
    if Lifted(False) or flag:
        print("T")
    else:
        print("F")
''', 'an implicit conversion between operand types'),
}


# Native output of refused one-type operators. A borrowing proxy cannot make
# the copy of a selected retained operand. A temporary with a user-defined
# move constructor is converted once in place, so it cannot make the move.
NATIVE_REJECTED_OUTPUT = {
    'copyable-retained-self': 'CONVERT\nCOPY\nCONVERT\nF\nFalse\n',
    'copyable-retained-temporary': 'CONVERT\nCOPY\nCONVERT\nT\nTrue\n',
    'custom-move-same': 'CONVERT\nMOVE\nCONVERT\nT\n',
    'optional-copied-element': 'COPY\nT\n1\n',
}


def check_truth_module(work, native, rewritten, build, mojo, module, names):
    """Compare one rendering of the custom truth trees with the model.

    Returns:
        The number of inconsistent vectors that the reducer and report refused.
    """
    source, lines = truth_source(names)
    (native / f'{module}.mojo').write_text(source)
    run([str(build), str(rewritten), f'{module}.mojo'], cwd=native)
    instrumented = (rewritten / f'{module}.mojo').read_text()
    if names is COLLISION_NAMES:
        # Each generated alias and frame must avoid every source identifier,
        # also the default prefixes, which the fixture takes as its own names.
        header = next(line for line in instrumented.splitlines()
                      if line.startswith('from coverage.runtime import '))
        aliases = [part.split(' as ')[1] for part in
                   header.removeprefix('from coverage.runtime import ').split(', ')]
        frames = sorted(set(word for word in instrumented.replace('(', ' ').replace(',', ' ').split()
                            if word.startswith(aliases[2].removesuffix('begin') + 'state')))
        assert frames, header
        for name in aliases + frames:
            assert name not in source, (name, header)
        for name in ('_cov_eval_leaf', '_cov_eval_buffer', '_cov_eval_truth', '_cov_eval_right',
                     '_cov_eval_state0',
                     'List', 'Int', 'Bool'):
            assert f'var {name} = ' in source or f'def {name}(' in source, name
    binaries = []
    for label, folder in (('native', native), ('instrumented', rewritten)):
        binary = work / f'{module}-{label}'
        run([mojo, 'build', '-Werror', '-I', str(folder),
             str(folder / f'{module}.mojo'), '-o', str(binary)])
        binaries.append(binary)
    inconsistent = 0
    for changing in (False, True):
        expected_rows, expected_records, expected_vectors = [], defaultdict(list), defaultdict(list)
        for fail in range(-1, 4):
            for mask in range(16):
                for number, tree in enumerate(TRUTH_CASES):
                    log, hits, vector = TruthModel(
                        tree, mask, fail, changing, lines[number], module).run()
                    expected_rows.append(f'TRUTH {number} {mask} {fail} {changing} {log}')
                    expected_records[number] += hits
                    if vector:
                        expected_vectors[number].append(vector)
        outputs = []
        for binary in binaries:
            with isolated_environment() as environment:
                environment['THREEMOJO_TRUTH_CHANGING'] = '1' if changing else '0'
                result = run([str(binary)], env=environment, timeout=10)
            assert not result_errors(result.stdout), result.stdout
            assert not slow_tests(result.stdout, 5), result.stdout
            rows = [line for line in result.stdout.splitlines() if line.startswith('TRUTH ')]
            mismatch = next((pair for pair in zip(rows, expected_rows) if pair[0] != pair[1]), None)
            assert rows == expected_rows, (binary.name, changing, mismatch, len(rows))
            outputs.append(result)
        raw = outputs[1].stderr
        label = 'changing' if changing else 'stable'
        (work / f'{module}-raw-{label}.txt').write_text(raw)
        for number, line in enumerate(lines):
            hits = [record for record in raw.splitlines()
                    if record.startswith((f'COVLINE:{module}:{line}:', f'COVLINE:{module}:{line}.'))]
            assert hits == expected_records[number], (module, number, changing, hits[:4])
            actual = [record for record in raw.splitlines()
                      if record.startswith(f'COVEVAL2:{module}:{line}:')]
            assert actual == expected_vectors[number], (module, number, changing, actual[:3])
        marked = sum('?' in record.rpartition(':')[2]
                     for record in raw.splitlines() if record.startswith('COVEVAL2:'))
        reduced = []
        reducer = Reducer(reduced.append)
        if not changing:
            assert marked == 0
            for record in raw.encode().splitlines(keepends=True):
                reducer.feed(record)
            (work / f'{module}-reduced-stable.txt').write_bytes(b''.join(reduced))
            reports = [run([str(work / 'analyze'), str(work / name)]).stdout
                       for name in (f'{module}-raw-stable.txt', f'{module}-reduced-stable.txt')]
            assert reports[0] == reports[1], f'raw/reduced custom {module} traces differ'
            continue
        # A repeated conversion that disagrees must refuse MC-DC evidence.
        assert marked > 0
        inconsistent = marked
        try:
            for record in raw.encode().splitlines(keepends=True):
                reducer.feed(record)
            raise AssertionError('the reducer accepted an inconsistent vector')
        except ValueError as error:
            assert 'Inconsistent repeated truth conversion' in str(error), error
        manifest = [entry for entry in (rewritten / 'manifest.txt').read_text().splitlines()
                    if entry.split()[0] in ('B', 'C', 'M') and entry.split()[1] == module]
        assert len([entry for entry in manifest if entry.startswith('M ')]) == sum(
            len(truth_slots(tree)) for tree in TRUTH_CASES)
        (work / f'{module}-manifest.txt').write_text('\n'.join(manifest) + '\n')
        refused = subprocess.run([str(work / 'report'), str(work / f'{module}-manifest.txt'),
                                  str(work / f'{module}-raw-changing.txt')],
                                 text=True, capture_output=True)
        assert refused.returncode != 0, refused.stdout
        assert 'Inconsistent repeated truth conversion' in refused.stdout + refused.stderr, refused
        (work / f'{module}-refused-report.txt').write_text(refused.stdout + refused.stderr)
    return inconsistent


def check_custom_truth(work, native, rewritten, build, mojo):
    """Compare custom compound operands with the native-semantics model."""
    inconsistent = 0
    for module, names in (('truth', TRUTH_NAMES), ('collision', COLLISION_NAMES)):
        inconsistent += check_truth_module(work, native, rewritten, build, mojo, module, names)

    (native / 'controls.mojo').write_text(TRUTH_CONTROLS)
    run([str(build), str(rewritten), 'controls.mojo'], cwd=native)
    outputs = []
    for label, folder in (('native', native), ('instrumented', rewritten)):
        binary = work / f'controls-{label}'
        run([mojo, 'build', '-Werror', '-I', str(folder), '-I', str(ROOT),
             str(folder / 'controls.mojo'), '-o', str(binary)])
        result = run([str(binary)], timeout=10)
        assert not result_errors(result.stdout), result.stdout
        assert not slow_tests(result.stdout, 5), result.stdout
        outputs.append(result.stdout.partition('\nRunning ')[0].strip() or result.stdout)
        (work / f'controls-{label}.txt').write_text(result.stdout)
    assert outputs[0] == outputs[1], 'custom truth controls differ'
    assert 'CONCURRENT' in outputs[0] and outputs[0].count('CONTROL ') == 32, outputs[0]

    for name, (text, message) in TRUTH_REJECTED.items():
        (native / f'{name}.mojo').write_text(text)
        result = run([mojo, 'build', '-Werror', '-I', str(native), str(native / f'{name}.mojo'),
                      '-o', str(work / name)])
        native_output = run([str(work / name)], timeout=5).stdout
        if name in NATIVE_REJECTED_OUTPUT:
            assert native_output == NATIVE_REJECTED_OUTPUT[name], (name, native_output)
        if name in NESTED_OPTIONAL_REJECTIONS:
            assert native_output == NESTED_OPTIONAL_REJECTIONS[name][1], (
                name, native_output, NESTED_OPTIONAL_REJECTIONS[name][1])
        run([str(build), str(rewritten), f'{name}.mojo'], cwd=native)
        rejected = subprocess.run([mojo, 'build', '-Werror', '-I', str(rewritten),
                                   str(rewritten / f'{name}.mojo'), '-o', str(work / 'rejected')],
                                  text=True, capture_output=True)
        assert rejected.returncode != 0 and message in rejected.stderr, (name, rejected.stderr[-2000:])
        (work / f'truth-{name}-native.txt').write_text(native_output)
        (work / f'truth-{name}-rejected.txt').write_text(rejected.stderr)
    return (f'{len(TRUTH_CASES)} custom truth trees x 16 masks x 5 failure positions, '
            f'stable and changing, with own and caller-scope collision names; '
            f'{inconsistent} inconsistent vectors refused; '
            f'{len(TRUTH_REJECTED)} explicit rejections')


def run(command, **kwargs):
    result = subprocess.run(command, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{command}:\n{result.stdout}\n{result.stderr}')
    return result


def records(text, decision):
    return [line for line in text.splitlines()
            if line.startswith(f'COVLINE:fixture:{decision}:')
            or line.startswith(f'COVLINE:fixture:{decision}.')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mojo', default=str(ROOT / '.venv/bin/mojo'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='threemojo-grouping-') as directory:
        work = Path(directory)
        native, rewritten = work / 'native', work / 'rewritten'
        for folder in (native, rewritten):
            folder.mkdir()
            shutil.copytree(ROOT / 'coverage', folder / 'coverage',
                            ignore=shutil.ignore_patterns('build'))
        source, decisions = fixture_source()
        (native / 'fixture.mojo').write_text(source)
        mojo = str(Path(args.mojo).resolve())
        build = work / 'build_cli'
        run([mojo, 'build', '-Werror', '-I', str(ROOT),
             str(ROOT / 'coverage/build_cli.mojo'), '-o', str(build)])
        run([str(build), str(rewritten), 'fixture.mojo'], cwd=native)
        manifest = (rewritten / 'manifest.txt').read_text().splitlines()
        for number, (_, tree) in enumerate(CASES):
            count = leaves(tree)
            expected = count if count > 1 else 0
            for kind in ('C', 'M'):
                actual = [line for line in manifest
                          if line.startswith(f'{kind} fixture {decisions[number]} ')]
                assert actual == [f'{kind} fixture {decisions[number]} {i}'
                                  for i in range(expected)], (number, actual)
        binaries = []
        for folder in (native, rewritten):
            binary = folder / 'suite'
            run([mojo, 'build', '-Werror', '-I', str(folder),
                 str(folder / 'fixture.mojo'), '-o', str(binary)], cwd=folder)
            binaries.append(binary)
        for fail in range(-1, 6):
            expected_rows, expected_records, expected_vectors = [], defaultdict(list), defaultdict(list)
            for mask in range(64):
                for number, (_, tree) in enumerate(CASES):
                    order, probes = [], []
                    try:
                        outcome = 'T' if evaluate(tree, mask, fail, order, probes, [0]) else 'F'
                    except ValueError:
                        outcome = 'E'
                    suffix = ' fixture exception' if outcome == 'E' else ''
                    expected_rows.append(f'RESULT {number} {mask} {fail} {outcome} {"".join(order)}{suffix}')
                    line = decisions[number]
                    if leaves(tree) > 1:
                        for slot, value in probes:
                            expected_records[number].append(
                                f'COVLINE:fixture:{line}.{slot}:{"T" if value else "F"}')
                    if outcome != 'E':
                        expected_records[number].append(f'COVLINE:fixture:{line}:{outcome}')
                        if leaves(tree) > 1:
                            states = dict(probes)
                            vector = ''.join(
                                '-' if i not in states else ('T' if states[i] else 'F')
                                for i in range(leaves(tree)))
                            expected_vectors[number].append(f'COVEVAL2:fixture:{line}:{outcome}:{vector};')
            outputs = []
            for binary in binaries:
                with isolated_environment() as environment:
                    environment['THREEMOJO_GROUPING_FAIL'] = str(fail)
                    result = run([str(binary)], env=environment, timeout=10)
                assert not result_errors(result.stdout), result.stdout
                assert not slow_tests(result.stdout, 5), result.stdout
                program_output = result.stdout.partition('\nRunning ')[0].strip()
                assert program_output == '\n'.join(expected_rows), result.stdout
                rows = [line for line in result.stdout.splitlines() if line.startswith('RESULT ')]
                assert rows == expected_rows, (binary, fail, rows[:3], expected_rows[:3])
                outputs.append(result)
            raw = outputs[1].stderr
            for number, line in enumerate(decisions):
                assert records(raw, line) == expected_records[number], (number, fail)
                actual_vectors = [record for record in raw.splitlines()
                                  if record.startswith(f'COVEVAL2:fixture:{line}:')]
                assert actual_vectors == expected_vectors[number], (number, fail, actual_vectors[:3], expected_vectors[number][:3])
            reduced = []
            reducer = Reducer(reduced.append)
            for record in raw.encode().splitlines(keepends=True):
                reducer.feed(record)
            (work / f'raw-{fail}.txt').write_text(raw)
            (work / f'reduced-{fail}.txt').write_bytes(b''.join(reduced))
            if fail == -1:
                (work / 'raw.txt').write_text(raw)
                (work / 'reduced.txt').write_bytes(b''.join(reduced))
        # The real Mojo parser/report must agree on raw and reduced vectors.
        analyzer = '''from coverage.mcdc import parse_traces, is_mcdc_covered
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
'''
        (native / 'analyze.mojo').write_text(analyzer)
        run([mojo, 'build', '-Werror', '-I', str(native), str(native / 'analyze.mojo'),
             '-o', str(work / 'analyze')])
        for fail in range(-1, 6):
            reports = [run([str(work / 'analyze'), str(work / f'{kind}-{fail}.txt')]).stdout
                       for kind in ('raw', 'reduced')]
            assert reports[0] == reports[1], f'raw/reduced Mojo traces differ at throwing leaf {fail}'
            (work / f'vectors-{fail}.txt').write_text(reports[0])
        # Two evaluations cover the decision, but leave two leaves incomplete.
        line = decisions[8]
        negative = ('COVLINE:fixture:{0}.0:F\nCOVLINE:fixture:{0}.1:F\n'
                    'COVLINE:fixture:{0}.2:F\nCOVLINE:fixture:{0}:F\n'
                    'COVEVAL2:fixture:{0}:F:FFF;\n'
                    'COVLINE:fixture:{0}.0:T\nCOVLINE:fixture:{0}:T\n'
                    'COVEVAL2:fixture:{0}:T:T--;\n').format(line)
        (work / 'negative.txt').write_text(negative)
        (work / 'negative-manifest.txt').write_text('\n'.join(
            [f'B fixture {line}'] + [f'{kind} fixture {line} {i}'
                                   for i in range(3) for kind in ('C', 'M')]) + '\n')
        run([mojo, 'build', '-Werror', '-I', str(ROOT), str(ROOT / 'coverage/report_cli.mojo'),
             '-o', str(work / 'report')])
        selected = [entry for entry in manifest
                    if entry.split()[0] in ('B', 'C', 'M')
                    and int(entry.split()[2]) in decisions]
        (work / 'decision-manifest.txt').write_text('\n'.join(selected) + '\n')
        for kind in ('raw', 'reduced'):
            result = run([str(work / 'report'), str(work / 'decision-manifest.txt'),
                          str(work / f'{kind}.txt')])
            (work / f'{kind}-report.txt').write_text(result.stdout)
        result = subprocess.run([str(work / 'report'), str(work / 'negative-manifest.txt'),
                                 str(work / 'negative.txt')], text=True, capture_output=True)
        assert result.returncode != 0
        (work / 'branch-manifest.txt').write_text(f'B fixture {line}\n')
        branch_report = run([str(work / 'report'), str(work / 'branch-manifest.txt'),
                             str(work / 'negative.txt')])
        assert '100%' in branch_report.stdout, branch_report.stdout
        (work / 'branch-report.txt').write_text(branch_report.stdout)
        assert 'condition 1:' in result.stdout and 'condition 2:' in result.stdout, result.stdout
        (work / 'negative-report.txt').write_text(result.stdout + result.stderr)
        truth_summary = check_custom_truth(work, native, rewritten, build, mojo)

        lifetime, lifetime_cases = lifetime_source()
        (native / 'lifetime.mojo').write_text(lifetime)
        run([str(build), str(rewritten), 'lifetime.mojo'], cwd=native)
        lifetime_results = []
        for label, folder in (('native', native), ('instrumented', rewritten)):
            binary = work / f'lifetime-{label}'
            run([mojo, 'build', '-Werror', '-I', str(folder),
                 str(folder / 'lifetime.mojo'), '-o', str(binary)])
            result = run([str(binary)], timeout=5)
            lifetime_results.append(result.stdout)
            (work / f'lifetime-{label}.txt').write_text(result.stdout)
        assert lifetime_results[0] == lifetime_results[1], 'Container destruction order differs'
        (work / 'lifetime-cases.txt').write_text('\n'.join(lifetime_cases) + '\n')

        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            for path in work.glob('*.txt'):
                shutil.copy(path, args.output / path.name)
            shutil.copy(native / 'lifetime.mojo', args.output / 'lifetime-native.mojo')
            shutil.copy(rewritten / 'lifetime.mojo', args.output / 'lifetime-instrumented.mojo')
            shutil.copy(native / 'fixture.mojo', args.output / 'native.mojo')
            shutil.copy(rewritten / 'fixture.mojo', args.output / 'instrumented.mojo')
            (args.output / 'manifest.txt').write_text('\n'.join(manifest) + '\n')
        print(f'PASS: {len(CASES)} native/instrumented cases, 64 truth assignments, normal and 6 throwing positions; '
              'exact order/count/outcomes, manifest C/M, raw/reduced Mojo vectors, and negative report; '
              f'{len(lifetime_cases)} container destructor-order cases; {truth_summary}')


if __name__ == '__main__':
    main()
