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
import re
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
# operator copies it. A Bits is in both, also twice as one retained variable.
# Pinned Mojo 1.1.0 lowers `and`/`or` by operand type. With one type, it tests
# the left operand, then returns it or the right operand unconverted, and the
# enclosing operator or truth context tests the selected object again. These
# two-type fixtures use the ordinary Bool fallback, which converts each
# evaluated operand once. They still have native/model checks, but
# instrumentation must refuse them: a user-defined Bool-valued merge has the
# same result type and requires different observable behavior.
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

TRUTH_ACCEPTED = ()
TRUTH_TEMPORARY_REJECTED = (0, 1, 2, 3, 4, 5, 9, 15, 37, 39, 41)
TRUTH_MIXED_REJECTED = (6, 7, 8, 10, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 22, 23,
                        24, 25, 26, 27, 28, 29, 30, 32, 33, 35, 36, 38, 40, 42)
TRUTH_RETAINED_REJECTED = (31, 34)
TRUTH_REFUSED = tuple(sorted(TRUTH_MIXED_REJECTED + TRUTH_RETAINED_REJECTED + TRUTH_TEMPORARY_REJECTED))
TEMPORARY_SELECTION_REFUSAL = 'a one-type operator over custom temporaries'
RETAINED_SELECTION_REFUSAL = 'a one-type operator that selects a retained custom operand'
COMPOUND_REFUSAL = 'Coverage cannot yet preserve this compound condition'
BOOL_MERGE_REFUSAL = 'custom mixed-type operator whose Bool result'



def fresh(tree):
    """Rebuild a tree so each leaf is its own object.

    Python can share equal tuple constants, and the slots are keyed by object.
    """
    return tuple(fresh(child) if isinstance(child, tuple) else child for child in tree)


TRUTH_CASES = [fresh(tree) for tree in TRUTH_CASES]


def truth_supported(tree):
    """Admit only operators over Bool-valued custom-operand expressions.

    Borrowed retained probes cannot select an owned result. Temporary probes
    convert in place instead of adding an identity-changing move. Custom
    same-type operators therefore remain refused, as do mixed custom joins.
    """
    if tree[0] in ('and', 'or'):
        if truth_type(tree[1]) != 'B' or truth_type(tree[2]) != 'B':
            return False
    return all(truth_supported(child) for child in tree[1:] if isinstance(child, tuple))


def negate_custom_leaves(tree):
    """Make a separate positive program; never replace an original tree."""
    if tree[0] in ('S', 'D', 'X', 'C', 'M', 'P', 'Q', 'T', 'choose'):
        return ('not', ('not', tree))
    return tuple(negate_custom_leaves(child) if isinstance(child, tuple) else child
                 for child in tree)


NEGATED_TRUTH_CASES = [fresh(negate_custom_leaves(tree)) for tree in TRUTH_CASES]


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


def truth_source(numbers=None, names=TRUTH_NAMES, cases=TRUTH_CASES):
    """Generate one function per reference tree; return the decision lines."""
    numbers = tuple(range(len(cases))) if numbers is None else tuple(numbers)
    text = TRUTH_PRELUDE
    for name in ('probe', 'other', 'flag', 'moving', 'bits', 'shared'):
        text = text.replace(f'\ndef {name}(', f'\ndef {names[name]}(')
    state, cell, retained_names = names['state'], names['cell'], names['retained']
    lines = {}
    for number in numbers:
        tree = cases[number]
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
        lines[number] = len(text.splitlines()) + 1
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
                    for number in numbers)
    text += '\n\ndef main() raises:\n    TestSuite.discover_tests[__functions_in_module()]().run()\n'
    return text, lines


# Controls without an independent model. Preserve the original mixed source
# as a native-success/refusal test, then compare an accepted variant exactly.
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


def generic_negated[A: Made, B: Made](state: Cell) -> Bool:
    # `not` converts each operand once, also a Moving, before Bool operators.
    if not A.make(0, state) or not B.make(1, state) and not A.make(2, state):
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


# Capture before replacing any expression: none of the original recursion,
# lifetime, generic, concurrent, or control-flow source may silently disappear.
TRUTH_MIXED_CONTROLS = TRUTH_CONTROLS
CONTROL_REPLACEMENTS = {
    'probe(0, state) and (probe(1, state) or flag(2, state)) and count > 0':
        'not not (probe(0, state) and (probe(1, state) or probe(2, state))) and count > 0',
    '(probe(0, state) or probe(1, state)) and loops < 3':
        'not not (probe(0, state) or probe(1, state)) and loops < 3',
    'not probe(2, state) or other(3, state)':
        'not probe(2, state) or not other(3, state)',
    'flag(0, state) and not unpinned or probe(1, state)':
        'flag(0, state) and not unpinned or not probe(1, state)',
    'Pinned(1, state) or flag(2, state) and Pinned(3, state)':
        'not Pinned(1, state) or flag(2, state) and not Pinned(3, state)',
    'optional_probe(0, state) and flag(1, state) or probe(2, state)':
        'optional_probe(0, state) and flag(1, state) or not probe(2, state)',
    'generic_pair[Probe, Other](state)': 'generic_pair[Other, Other](state)',
    'Probe(0, state) or Probe(1, state) and Other(2, state)':
        'Probe(0, state) or Probe(1, state) and Probe(2, state)',
    'flag(0, state) and not held or probe(1, state)':
        'flag(0, state) and not held or not probe(1, state)',
    'if kept or flag(1, state):': 'if not not kept or flag(1, state):',
    'probe(0, state) and kept:': 'not probe(0, state) and not kept:',
    'value or flag(1, state)': 'not not value or flag(1, state)',
    '# One instantiation borrows a retained Shared; one has two Bool operands.':
        '# `not` converts a borrowed retained Shared or a Bool operand once.',
    'generic_pair[Probe, Moving](state)': 'generic_negated[Probe, Moving](state)',
    '# The operator checks run per instantiation: one type, then two types.':
        '# The operator checks run per instantiation: Probe, then Other.',
}
for original, accepted in CONTROL_REPLACEMENTS.items():
    assert TRUTH_CONTROLS.count(original) == 1, original
    TRUTH_CONTROLS = TRUTH_CONTROLS.replace(original, accepted, 1)


# Keep the exact failed V8 control as a separate native-success/refusal case.
# Independent A/B parameters select Bool fallback even when A == B after
# instantiation. The positive fixture must use one declared type parameter.
TRUTH_TWO_PARAMETER_CONTROLS = TRUTH_CONTROLS
SINGLE_GENERIC_REPLACEMENTS = {
    'def generic_pair[A: Made, B: Made](state: Cell) -> Bool:':
        'def generic_pair[A: Made](state: Cell) -> Bool:',
    'A.make(0, state) or B.make(1, state) and A.make(2, state)':
        'A.make(0, state) or A.make(1, state) and A.make(2, state)',
    'generic_pair[Probe, Probe](state)': 'generic_pair[Probe](state)',
    'generic_pair[Other, Other](state)': 'generic_pair[Other](state)',
    '# The operator checks run per instantiation: Probe, then Other.':
        '# One declared type keeps same-type joining for both instantiations.',
}
for original, accepted in SINGLE_GENERIC_REPLACEMENTS.items():
    assert TRUTH_CONTROLS.count(original) == 1, original
    TRUTH_CONTROLS = TRUTH_CONTROLS.replace(original, accepted, 1)

MIXED_CONTROL_WIDTHS = {
    'if probe(0, state) and (probe(1, state) or flag(2, state)) and count > 0:': 4,
    'if A.make(0, state) or B.make(1, state) and A.make(2, state):': 3,
    'while (probe(0, state) or probe(1, state)) and loops < 3:': 3,
    'if probe(0, state) and probe(1, state):': 2,
    'elif not probe(2, state) or other(3, state):': 2,
    'elif probe(1, state) or probe(2, state):': 2,
    'if flag(0, state) and not unpinned or probe(1, state):': 3,
    'if Pinned(1, state) or flag(2, state) and Pinned(3, state):': 3,
    'if optional_probe(0, state) and flag(1, state) or probe(2, state):': 3,
    'if (maybe or other) and (number or flag(1, state)) or String("x") and List[Int](length=mask, fill=0):': 6,
    'if nested_optional(mask % 2 == 0) or nested_optional(mask % 3 == 0):': 2,
    'if nested_optional(mask % 2 == 0) and nested_optional(mask % 3 == 0):': 2,
    'if Probe(0, state) or Probe(1, state) and Other(2, state):': 3,
    'if not A.make(0, state) or not B.make(1, state) and not A.make(2, state):': 3,
    'if value or flag(1, state):': 2,
    'if flag(0, state) and not held or probe(1, state):': 3,
    'if kept or flag(1, state):': 2,
    'elif probe(0, state) and kept:': 2,
    'if shared(0, state) and live:': 2,
    'if shared(0, state) or last:': 2,
}
TWO_PARAMETER_CONTROL_WIDTHS = {}
CONTROL_WIDTHS = {}
for header, width in MIXED_CONTROL_WIDTHS.items():
    for original, accepted in CONTROL_REPLACEMENTS.items():
        header = header.replace(original, accepted)
    TWO_PARAMETER_CONTROL_WIDTHS[header] = width
    for original, accepted in SINGLE_GENERIC_REPLACEMENTS.items():
        header = header.replace(original, accepted)
    CONTROL_WIDTHS[header] = width


# Preserve the previously admitted programs verbatim as native-success/refusal
# controls. The positive programs below make a different, explicit choice:
# each custom operand converts under not before a Bool-only operator.
TRUTH_OWNED_CONTROLS = TRUTH_CONTROLS
OWNED_CONTROL_WIDTHS = dict(CONTROL_WIDTHS)
IDENTITY_CONTROL_REPLACEMENTS = {
    'not not (probe(0, state) and (probe(1, state) or probe(2, state))) and count > 0':
        '(not not probe(0, state)) and ((not not probe(1, state)) or (not not probe(2, state))) and count > 0',
    'not not (probe(0, state) or probe(1, state)) and loops < 3':
        '((not not probe(0, state)) or (not not probe(1, state))) and loops < 3',
    'if probe(0, state) and probe(1, state):':
        'if not not probe(0, state) and not not probe(1, state):',
    'elif probe(1, state) or probe(2, state):':
        'elif not not probe(1, state) or not not probe(2, state):',
    'A.make(0, state) or A.make(1, state) and A.make(2, state)':
        '(not not A.make(0, state)) or (not not A.make(1, state)) and (not not A.make(2, state))',
    'Probe(0, state) or Probe(1, state) and Probe(2, state)':
        '(not not Probe(0, state)) or (not not Probe(1, state)) and (not not Probe(2, state))',
    'if shared(0, state) and live:':
        'if not not shared(0, state) and not not live:',
    'if shared(0, state) or last:':
        'if not not shared(0, state) or not not last:',
}
for original, accepted in IDENTITY_CONTROL_REPLACEMENTS.items():
    assert TRUTH_CONTROLS.count(original) == 1, original
    TRUTH_CONTROLS = TRUTH_CONTROLS.replace(original, accepted, 1)
CONTROL_WIDTHS = dict(OWNED_CONTROL_WIDTHS)
for original, accepted in IDENTITY_CONTROL_REPLACEMENTS.items():
    CONTROL_WIDTHS = {header.replace(original, accepted): width
                      for header, width in CONTROL_WIDTHS.items()}




class GenericTruthModel(TruthModel):
    """Model Made.make leaves, which do not call State.enter."""

    def enter(self, name):
        pass


def two_parameter_generic_source():
    """Isolate the exact original function so another refusal cannot mask it."""
    signature = 'def generic_pair[A: Made, B: Made](state: Cell) -> Bool:'
    assert TRUTH_TWO_PARAMETER_CONTROLS.count(signature) == 1
    body = signature + TRUTH_TWO_PARAMETER_CONTROLS.split(signature, 1)[1].split('\n\ndef ', 1)[0]
    source = TRUTH_PRELUDE + '\n\n' + body + '''


def run_pair[A: Made, B: Made](name: StaticString, mask: Int, changing: Bool):
    var cell = State(mask, -1, changing)
    var state = Pointer(to=cell).unsafe_origin_cast[MutUntrackedOrigin]()
    var result = generic_pair[A, B](state)
    print("PAIR", name, mask, changing, result, state[].log,
          state[].counts[0], state[].counts[1], state[].counts[2])
    _ = cell^


def main():
    for changing in [False, True]:
        for mask in range(16):
            run_pair[Probe, Probe]("Probe", mask, changing)
            run_pair[Other, Other]("Other", mask, changing)
'''
    header = 'if A.make(0, state) or B.make(1, state) and A.make(2, state):'
    line = next(i for i, text in enumerate(source.splitlines(), 1) if text.strip() == header)
    return source, {header: 3}, line, signature


def check_two_parameter_generic_truth(work, native, rewritten, build, mojo):
    """Require the generic-specific refusal after an independent native model."""
    name = 'generic-pair-isolated'
    source, widths, line, signature = two_parameter_generic_source()
    expected = []
    # Independently declared A/B select Bool fallback even for equal concrete
    # bindings. Each custom temporary converts once before Boolean selection.
    tree = negate_custom_leaves(('or', ('S', 0), ('and', ('S', 1), ('S', 2))))
    for changing in (False, True):
        for mask in range(16):
            for concrete in ('Probe', 'Other'):
                model = GenericTruthModel(tree, mask, -1, changing, line, name)
                log, _, vector = model.run()
                assert log[-2:] in ('|T', '|F') and vector is not None
                expected.append(f'PAIR {concrete} {mask} {changing} {log.endswith("|T")} {log[:-2]} '
                                + ' '.join(str(model.counts[i]) for i in range(3)))
    assert len(expected) == 64
    (work / f'{name}-expected.txt').write_text('\n'.join(expected) + '\n')
    (native / f'{name}.mojo').write_text(source)
    (work / f'{name}-native.mojo').write_text(source)
    binary = work / f'{name}-native'
    optional_capture(work, f'{name}-native-build',
                     [mojo, 'build', '-Werror', '-I', str(native), '-I', str(ROOT),
                      str(native / f'{name}.mojo'), '-o', str(binary)], timeout=180)
    original = optional_capture(work, f'{name}-native-run', [str(binary)], timeout=5)
    assert original.stdout.splitlines() == expected, (name, 'native/model output differs')
    check_refusal(work, native, rewritten, build, mojo, name, source, widths,
                  (COMPOUND_REFUSAL, BOOL_MERGE_REFUSAL, signature))
    assert_identity_origin(rewritten, name, source)


def single_generic_source(negated=False):
    """Keep one declared type parameter and exercise both concrete types."""
    source = TRUTH_PRELUDE + '''


def generic_single[A: Made](state: Cell) -> Bool:
    if A.make(0, state) or A.make(1, state) and A.make(2, state):
        return True
    return False


def run_generic[A: Made](name: StaticString, mask: Int, changing: Bool):
    var cell = State(mask, -1, changing)
    var state = Pointer(to=cell).unsafe_origin_cast[MutUntrackedOrigin]()
    var result = generic_single[A](state)
    print("GENERIC", name, mask, changing, result, state[].log,
          state[].counts[0], state[].counts[1], state[].counts[2])
    _ = cell^


def main():
    for changing in [False, True]:
        for mask in range(16):
            run_generic[Probe]("Probe", mask, changing)
            run_generic[Other]("Other", mask, changing)
'''
    header = 'if A.make(0, state) or A.make(1, state) and A.make(2, state):'
    if negated:
        replacement = 'if (not not A.make(0, state)) or (not not A.make(1, state)) and (not not A.make(2, state)):'
        assert source.count(header) == 1
        source = source.replace(header, replacement)
        header = replacement
    line = next(i for i, row in enumerate(source.splitlines(), 1) if row.strip() == header)
    return source, {header: 3}, line


def check_single_generic_truth(work, native, rewritten, build, mojo):
    """Retain the original generic oracle/refusal and a separate safe variant."""
    for negated in (False, True):
        name = 'generic-single-negated' if negated else 'generic-single-original'
        source, widths, line = single_generic_source(negated)
        (native / f'{name}.mojo').write_text(source)
        (work / f'{name}-native.mojo').write_text(source)
        expected_rows, expected_trace = [], []
        tree = ('or', ('S', 0), ('and', ('S', 1), ('S', 2)))
        if negated:
            tree = negate_custom_leaves(tree)
        for changing in (False, True):
            for mask in range(16):
                for concrete in ('Probe', 'Other'):
                    model = GenericTruthModel(tree, mask, -1, changing, line, name)
                    log, hits, vector = model.run()
                    assert log[-2:] in ('|T', '|F') and vector is not None
                    outcome = log.endswith('|T')
                    expected_rows.append(
                        f'GENERIC {concrete} {mask} {changing} {outcome} {log[:-2]} '
                        + ' '.join(str(model.counts[i]) for i in range(3)))
                    expected_trace.append(f'COVLINE:{name}:{line}')
                    expected_trace.extend(hits)
                    expected_trace.append(vector)
        assert len(expected_rows) == 64
        if not negated:
            assert len(expected_trace) == 328
            assert sum('?' in row for row in expected_trace if row.startswith('COVEVAL2:')) == 24
        else:
            assert not any('?' in row for row in expected_trace if row.startswith('COVEVAL2:'))
        (work / f'{name}-expected.txt').write_text('\n'.join(expected_rows) + '\n')
        (work / f'{name}-trace-expected.txt').write_text('\n'.join(expected_trace) + '\n')
        binary = work / f'{name}-native'
        optional_capture(work, f'{name}-native-build',
                         [mojo, 'build', '-Werror', '-I', str(native), '-I', str(ROOT),
                          str(native / f'{name}.mojo'), '-o', str(binary)])
        native_result = optional_capture(work, f'{name}-native-run', [str(binary)], timeout=5)
        assert native_result.stdout.splitlines() == expected_rows, (name, 'native/model output differs')
        if not negated:
            check_refusal(work, native, rewritten, build, mojo, name, source, widths,
                          (COMPOUND_REFUSAL, TEMPORARY_SELECTION_REFUSAL,
                           'def generic_single[A: Made](state: Cell) -> Bool:'))
            continue
        optional_capture(work, f'{name}-rewrite',
                         [str(build), str(rewritten), f'{name}.mojo'], cwd=native, timeout=5)
        shutil.copy(rewritten / f'{name}.mojo', work / f'{name}-instrumented.mojo')
        manifest = assert_obligations(rewritten, name, single_line_obligations(source, widths))
        (work / f'{name}-manifest.txt').write_text('\n'.join(manifest) + '\n')
        binary = work / f'{name}-instrumented'
        optional_capture(work, f'{name}-instrumented-build',
                         [mojo, 'build', '-Werror', '-I', str(rewritten), '-I', str(ROOT),
                          str(rewritten / f'{name}.mojo'), '-o', str(binary)])
        instrumented = optional_capture(work, f'{name}-instrumented-run', [str(binary)], timeout=5)
        assert instrumented.stdout == native_result.stdout, (name, 'native/instrumented output differs')
        actual = [row for row in instrumented.stderr.splitlines()
                  if row.startswith((f'COVLINE:{name}:', f'COVEVAL2:{name}:'))
                  and row.split(':')[2].split('.', 1)[0] == str(line)]
        (work / f'{name}-trace-actual.txt').write_text('\n'.join(actual) + '\n')
        assert actual == expected_trace, (name, 'generic line/condition/decision/vector order differs')

def single_line_obligations(source, widths=None):
    """Declare every decision in these fixtures, with explicit compound widths."""
    widths = {} if widths is None else widths
    obligations, used = {}, set()
    for line, text in enumerate(source.splitlines(), 1):
        header = text.strip()
        if not header.startswith(('if ', 'elif ', 'while ', 'for ')):
            continue
        assert header.endswith(':'), header
        if header in widths:
            width = widths[header]
            used.add(header)
        else:
            assert ' and ' not in header and ' or ' not in header, header
            width = 1
        obligations[line] = width
    assert used == set(widths), (used, widths)
    return obligations


def assert_obligations(rewritten, module, obligations):
    """Reject lost branches, conditions, or MC/DC slots, including refusals."""
    actual = [entry for entry in (rewritten / 'manifest.txt').read_text().splitlines()
              if entry.split()[0] in ('B', 'C', 'M') and entry.split()[1] == module]
    expected = []
    for line, width in obligations.items():
        expected.append(f'B {module} {line}')
        if width > 1:
            expected.extend(f'{kind} {module} {line} {slot}'
                            for slot in range(width) for kind in ('C', 'M'))
    assert sorted(actual) == sorted(expected), (module, actual, expected)
    return actual


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


# Keep the issue #560 counterexample independent of TruthModel. Native Mojo
# tests Left once and merges only the selected operand; it never tests Right.
# Every merge flips its stored truth. A Bool fallback therefore changes all
# eight outcomes even though the native result type is also Bool.
BOOL_MERGE_PRELUDE = '''struct Left(Movable, Boolable):
    var value: Bool

    def __init__(out self, value: Bool):
        self.value = value
        print("MAKE L", value)

    def __bool__(self) -> Bool:
        print("BOOL L", self.value)
        return self.value

    def __merge_with__[other_type: AnyType](self) -> Bool:
        print("MERGE L", self.value)
        return not self.value


struct Right(Movable, Boolable):
    var value: Bool

    def __init__(out self, value: Bool):
        self.value = value
        print("MAKE R", value)

    def __bool__(self) -> Bool:
        print("BOOL R", self.value)
        return self.value

    def __merge_with__[other_type: AnyType](self) -> Bool:
        print("MERGE R", self.value)
        return not self.value
'''

BOOL_MERGE_EXPECTED = {
    'or': '''CASE OR False False
MAKE L False
BOOL L False
MAKE R False
MERGE R False
BODY T
CASE OR False True
MAKE L False
BOOL L False
MAKE R True
MERGE R True
BODY F
CASE OR True False
MAKE L True
BOOL L True
MERGE L True
BODY F
CASE OR True True
MAKE L True
BOOL L True
MERGE L True
BODY F
''',
    'and': '''CASE AND False False
MAKE L False
BOOL L False
MERGE L False
BODY T
CASE AND False True
MAKE L False
BOOL L False
MERGE L False
BODY T
CASE AND True False
MAKE L True
BOOL L True
MAKE R False
MERGE R False
BODY T
CASE AND True True
MAKE L True
BOOL L True
MAKE R True
MERGE R True
BODY F
''',
}
BOOL_MERGE_REJECTIONS = {
    f'bool-merge-{operator}': (BOOL_MERGE_PRELUDE + f'''

def main():
    for first in [False, True]:
        for second in [False, True]:
            print("CASE {operator.upper()}", first, second)
            if Left(first) {operator} Right(second):
                print("BODY T")
            else:
                print("BODY F")
''', expected)
    for operator, expected in BOOL_MERGE_EXPECTED.items()
}


# A merge can apply to some operand types and not to others. Gated merges
# only with Bool, so `Gated(x) or flag` calls the merge and `Gated(x) or
# Plain(y)` uses Boolean fallback. No probe type can stand in for the other
# operand, and both forms must be refused. The model is independent of
# TruthModel: Mojo tests Gated once, then merges it only when it selects it.
GATED_MERGE_PRELUDE = '''struct Gated(Movable, Boolable):
    var value: Bool

    def __init__(out self, value: Bool):
        self.value = value
        print("MAKE G", value)

    def __bool__(self) -> Bool:
        print("BOOL G", self.value)
        return self.value

    def __merge_with__[other_type: AnyType](self) -> Bool where other_type == Bool:
        print("MERGE G", self.value)
        return not self.value


struct Plain(Movable, Boolable):
    var value: Bool

    def __init__(out self, value: Bool):
        self.value = value
        print("MAKE P", value)

    def __bool__(self) -> Bool:
        print("BOOL P", self.value)
        return self.value


def flag(value: Bool) -> Bool:
    print("FLAG", value)
    return value
'''


def gated_merge_expected(right):
    """Model one `Gated(first) or <right>(second)` decision per assignment."""
    lines = []
    for first in (False, True):
        for second in (False, True):
            lines += [f'CASE {first} {second}', f'MAKE G {first}', f'BOOL G {first}']
            if first:
                # Boolean fallback keeps True. The merge returns its negation.
                outcome = right == 'Plain'
                if right == 'flag':
                    lines.append(f'MERGE G {first}')
            elif right == 'flag':
                lines.append(f'FLAG {second}')
                outcome = second
            else:
                lines += [f'MAKE P {second}', f'BOOL P {second}']
                outcome = second
            lines.append('BODY T' if outcome else 'BODY F')
    return '\n'.join(lines) + '\n'


GATED_MERGE_REJECTIONS = {
    f'gated-merge-{right.lower()}': (GATED_MERGE_PRELUDE + f'''

def main():
    for first in [False, True]:
        for second in [False, True]:
            print("CASE", first, second)
            if Gated(first) or {right}(second):
                print("BODY T")
            else:
                print("BODY F")
''', gated_merge_expected(right))
    for right in ('flag', 'Plain')
}


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
''', 'a one-type operator that selects a retained custom operand'),
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
''', 'a one-type operator that selects a retained custom operand'),
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
''', 'a one-type operator that selects a retained custom operand'),
    # Mixed-type sources: native Mojo converts each operand once, but the
    # operator check cannot tell this Boolean fallback from a custom merge.
    'copyable-retained-mixed': ('''@fieldwise_init
struct Copied(ImplicitlyCopyable, Boolable):
    var value: Bool

    def __bool__(self) -> Bool:
        return self.value


def main():
    var copied = Copied(False)
    var flag = True
    if copied or flag:
        print("T")
    else:
        print("F")
''', BOOL_MERGE_REFUSAL),
    'custom-move': ('''@fieldwise_init
struct Moving(Boolable):
    var value: Bool

    def __init__(out self, *, deinit move: Self):
        self.value = move.value
        print("MOVE")

    def __bool__(self) -> Bool:
        return self.value


def main():
    var flag = True
    if Moving(False) or flag:
        print("T")
    else:
        print("F")
''', BOOL_MERGE_REFUSAL),
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
''', 'a one-type operator that selects a retained custom operand'),
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


# Same-type forms of the old mixed sources. The node guard refuses each one
# with the specific one-type diagnostic. Reusing one retained origin makes
# both borrowing proxies one type, so only the borrow check can refuse it.
LEAF_GUARD_REJECTIONS = {
    'copyable-retained-same-origin': (
        TRUTH_REJECTED['copyable-retained'][0]
        .replace('    var other = Copied(False)\n', '')
        .replace('if copied or other:', 'if copied or copied:')
        + '    print("RETAINED", copied.value)\n',
        'a one-type operator that selects a retained custom operand'),
    'custom-move-same-type': (
        TRUTH_REJECTED['custom-move'][0]
        .replace('    var flag = True\n', '')
        .replace('Moving(False) or flag', 'Moving(False) or Moving(True)'),
        'a one-type operator over a type with a user-defined move'),
}


def check_refusal(work, native, rewritten, build, mojo, name, source, widths, messages):
    """Instrument the complete source, retain all obligations, and refuse it."""
    (native / f'{name}.mojo').write_text(source)
    (work / f'truth-{name}-native.mojo').write_text(source)
    optional_capture(work, f'truth-{name}-rewrite',
                     [str(build), str(rewritten), f'{name}.mojo'], cwd=native, timeout=5)
    shutil.copy(rewritten / f'{name}.mojo', work / f'truth-{name}-instrumented.mojo')
    shutil.copy(rewritten / 'manifest.txt', work / f'truth-{name}-manifest-raw.txt')
    manifest = assert_obligations(
        rewritten, name, single_line_obligations(source, widths))
    rejected = subprocess.run([mojo, 'build', '-Werror', '-I', str(rewritten),
                               '-I', str(ROOT), str(rewritten / f'{name}.mojo'),
                               '-o', str(work / 'rejected')],
                              text=True, capture_output=True)
    (work / f'truth-{name}-manifest.txt').write_text('\n'.join(manifest) + '\n')
    (work / f'truth-{name}-rejected.txt').write_text(rejected.stderr)
    (work / f'truth-{name}-rejected-stdout.txt').write_text(rejected.stdout)
    (work / f'truth-{name}-rejected-returncode.txt').write_text(str(rejected.returncode) + '\n')
    assert rejected.returncode != 0, (name, 'instrumentation unexpectedly accepted the source')
    for message in messages:
        assert message in rejected.stderr, (name, message, rejected.stderr[-4000:])


def truth_widths(numbers, names=TRUTH_NAMES, cases=TRUTH_CASES):
    return {f'if {truth_text(cases[number], names=names)}:':
            len(truth_slots(cases[number])) for number in numbers}


def check_truth_module(work, native, rewritten, build, mojo, module, names,
                       cases=TRUTH_CASES, accepted_numbers=TRUTH_ACCEPTED):
    """Check every native tree; compare only explicitly supported variants.

    The original 43 trees stay native-success/refusal controls. Negated-leaf
    variants are separate programs with their own native/model comparisons.
    """
    source, native_lines = truth_source(names=names, cases=cases)
    (native / f'{module}.mojo').write_text(source)
    (work / f'{module}-native.mojo').write_text(source)
    native_binary = work / f'{module}-native'
    run([mojo, 'build', '-Werror', '-I', str(native),
         str(native / f'{module}.mojo'), '-o', str(native_binary)])
    binaries = [('native', native_binary)]
    lines = {}
    if accepted_numbers:
        accepted, lines = truth_source(accepted_numbers, names, cases)
        accepted_source = work / f'{module}-accepted-source'
        accepted_source.mkdir()
        (accepted_source / f'{module}.mojo').write_text(accepted)
        (work / f'{module}-accepted-native.mojo').write_text(accepted)
        run([str(build), str(rewritten), f'{module}.mojo'], cwd=accepted_source)
        manifest = assert_obligations(
            rewritten, module,
            single_line_obligations(accepted, truth_widths(accepted_numbers, names, cases)))
        assert len([entry for entry in manifest if entry.startswith('M ')]) == sum(
            len(truth_slots(cases[number])) for number in accepted_numbers)
        (work / f'{module}-manifest.txt').write_text('\n'.join(manifest) + '\n')
        instrumented = (rewritten / f'{module}.mojo').read_text()
        (work / f'{module}-instrumented.mojo').write_text(instrumented)
        if names is COLLISION_NAMES:
            header = next(line for line in instrumented.splitlines()
                          if line.startswith('from coverage.runtime import '))
            aliases = [part.split(' as ')[1] for part in
                       header.removeprefix('from coverage.runtime import ').split(', ')]
            frames = sorted(set(word for word in instrumented.replace('(', ' ').replace(',', ' ').split()
                                if word.startswith(aliases[2].removesuffix('begin') + 'state')))
            assert frames, header
            for name in aliases + frames:
                assert name not in accepted, (name, header)
            for name in ('_cov_eval_leaf', '_cov_eval_buffer', '_cov_eval_truth', '_cov_eval_right',
                         '_cov_eval_state0', 'List', 'Int', 'Bool'):
                assert f'var {name} = ' in accepted or f'def {name}(' in accepted, name
        instrumented_binary = work / f'{module}-instrumented'
        run([mojo, 'build', '-Werror', '-I', str(rewritten),
             str(rewritten / f'{module}.mojo'), '-o', str(instrumented_binary)])
        binaries.append(('instrumented', instrumented_binary))

    native_rows = defaultdict(list)
    for changing in (False, True):
        expected_rows = {'native': [], 'instrumented': []}
        expected_records, expected_vectors = defaultdict(list), defaultdict(list)
        for fail in range(-1, 4):
            for mask in range(16):
                for number, tree in enumerate(cases):
                    log, hits, vector = TruthModel(
                        tree, mask, fail, changing, lines.get(number, native_lines[number]),
                        module).run()
                    row = f'TRUTH {number} {mask} {fail} {changing} {log}'
                    expected_rows['native'].append(row)
                    if number in accepted_numbers:
                        expected_rows['instrumented'].append(row)
                        expected_records[number] += hits
                        if vector:
                            expected_vectors[number].append(vector)
        outputs = {}
        label = 'changing' if changing else 'stable'
        for kind, binary in binaries:
            with isolated_environment() as environment:
                environment['THREEMOJO_TRUTH_CHANGING'] = '1' if changing else '0'
                result = run([str(binary)], env=environment, timeout=5)
            assert not result_errors(result.stdout), result.stdout
            assert not slow_tests(result.stdout, 5), result.stdout
            rows = [line for line in result.stdout.splitlines() if line.startswith('TRUTH ')]
            mismatch = next((pair for pair in zip(rows, expected_rows[kind]) if pair[0] != pair[1]), None)
            assert rows == expected_rows[kind], (module, binary.name, changing, mismatch, len(rows))
            if kind == 'native':
                for row in rows:
                    native_rows[int(row.split()[1])].append(row)
            (work / f'{module}-{kind}-{label}.txt').write_text(result.stdout)
            outputs[kind] = result
        if not accepted_numbers:
            continue
        raw = outputs['instrumented'].stderr
        (work / f'{module}-raw-{label}.txt').write_text(raw)
        for number, line in lines.items():
            hits = [record for record in raw.splitlines()
                    if record.startswith((f'COVLINE:{module}:{line}:', f'COVLINE:{module}:{line}.'))]
            assert hits == expected_records[number], (module, number, changing, hits[:4])
            actual = [record for record in raw.splitlines()
                      if record.startswith(f'COVEVAL2:{module}:{line}:')]
            assert actual == expected_vectors[number], (module, number, changing, actual[:3])
        # Each supported custom leaf converts once before a Bool operator.
        # Repeated-conversion rejection is exercised separately through the
        # real borrowed probe, reducer and reporter; it is never disabled.
        assert not any('?' in record.rpartition(':')[2]
                       for record in raw.splitlines() if record.startswith('COVEVAL2:'))
        reduced = []
        reducer = Reducer(reduced.append)
        for record in raw.encode().splitlines(keepends=True):
            reducer.feed(record)
        (work / f'{module}-reduced-{label}.txt').write_bytes(b''.join(reduced))
        reports = [run([str(work / 'analyze'), str(work / name)]).stdout
                   for name in (f'{module}-raw-{label}.txt', f'{module}-reduced-{label}.txt')]
        assert reports[0] == reports[1], f'raw/reduced custom {module} traces differ'
    return source, native_rows

def check_custom_truth(work, native, rewritten, build, mojo):
    """Compare all native trees and only the explicitly supported instruments."""
    assert len(TRUTH_REFUSED) == len(set(TRUTH_REFUSED)) == 43
    assert set(TRUTH_ACCEPTED).isdisjoint(TRUTH_REFUSED)
    assert sorted(TRUTH_ACCEPTED + TRUTH_REFUSED) == list(range(len(TRUTH_CASES)))
    # The hand-kept lists must agree with the independent operator model.
    assert TRUTH_ACCEPTED == tuple(number for number, tree in enumerate(TRUTH_CASES)
                                   if truth_supported(tree))
    for module, names in (('truth', TRUTH_NAMES), ('collision', COLLISION_NAMES)):
        module_source, module_rows = check_truth_module(
            work, native, rewritten, build, mojo, module, names)
        if module == 'truth':
            source, native_rows = module_source, module_rows

    # These supported variants have explicit negation around each custom
    # leaf. Their own native/model evidence is separate from the originals.
    for module, names in (('negated-truth', TRUTH_NAMES), ('negated-collision', COLLISION_NAMES)):
        check_truth_module(work, native, rewritten, build, mojo, module, names,
                           NEGATED_TRUTH_CASES, tuple(range(len(NEGATED_TRUTH_CASES))))

    for number in TRUTH_REFUSED:
        rejected_source, _ = truth_source((number,))
        # The native-success evidence above covers this exact function, not an
        # easier substitute. The reduced fixture merely selects its entry point.
        signature = f'def truth_{number}('
        assert (source.split(signature, 1)[1].split('\n\ndef ', 1)[0].strip()
                == rejected_source.split(signature, 1)[1].split('\n\ndef ', 1)[0].strip())
        assert len(native_rows[number]) == 16 * 5 * 2, number
        reason = (RETAINED_SELECTION_REFUSAL if number in TRUTH_RETAINED_REJECTED else
                  TEMPORARY_SELECTION_REFUSAL if number in TRUTH_TEMPORARY_REJECTED else
                  BOOL_MERGE_REFUSAL)
        name = f'truth-refused-{number}'
        (work / f'truth-{name}-native.txt').write_text('\n'.join(native_rows[number]) + '\n')
        check_refusal(work, native, rewritten, build, mojo, name, rejected_source,
                      truth_widths((number,)), (COMPOUND_REFUSAL, reason))

    # Run the untouched original controls before requiring their refusal.
    name = 'controls-mixed'
    (native / f'{name}.mojo').write_text(TRUTH_MIXED_CONTROLS)
    binary = work / name
    run([mojo, 'build', '-Werror', '-I', str(native), '-I', str(ROOT),
         str(native / f'{name}.mojo'), '-o', str(binary)])
    result = run([str(binary)], timeout=5)
    assert not result_errors(result.stdout), result.stdout
    assert not slow_tests(result.stdout, 5), result.stdout
    assert 'CONCURRENT' in result.stdout and result.stdout.count('CONTROL ') == 32, result.stdout
    (work / 'controls-mixed-native.txt').write_text(result.stdout)
    check_refusal(work, native, rewritten, build, mojo, name, TRUTH_MIXED_CONTROLS,
                  MIXED_CONTROL_WIDTHS, (COMPOUND_REFUSAL, BOOL_MERGE_REFUSAL))

    # Preserve the complete V8 source and all 32 control rows, including both
    # equal-concrete A/B calls, rather than relabeling them as supported.
    name = 'controls-two-parameters'
    (native / f'{name}.mojo').write_text(TRUTH_TWO_PARAMETER_CONTROLS)
    (work / f'truth-{name}-native.mojo').write_text(TRUTH_TWO_PARAMETER_CONTROLS)
    binary = work / name
    optional_capture(work, f'truth-{name}-native-build',
                     [mojo, 'build', '-Werror', '-I', str(native), '-I', str(ROOT),
                      str(native / f'{name}.mojo'), '-o', str(binary)])
    two_parameter = optional_capture(work, f'truth-{name}-native-run', [str(binary)], timeout=5)
    assert not result_errors(two_parameter.stdout), two_parameter.stdout
    assert not slow_tests(two_parameter.stdout, 5), two_parameter.stdout
    two_parameter_rows = [row for row in two_parameter.stdout.splitlines() if row.startswith('CONTROL ')]
    assert len(two_parameter_rows) == 32 and 'CONCURRENT' in two_parameter.stdout
    check_refusal(work, native, rewritten, build, mojo, name, TRUTH_TWO_PARAMETER_CONTROLS,
                  TWO_PARAMETER_CONTROL_WIDTHS, (COMPOUND_REFUSAL, BOOL_MERGE_REFUSAL))
    check_two_parameter_generic_truth(work, native, rewritten, build, mojo)

    # This is the exact previously admitted one-parameter/owned control.
    # Keep all native lifetime, recursion and concurrent behavior, then
    # require refusal before testing the explicitly negated variant.
    name = 'controls-owned'
    (native / f'{name}.mojo').write_text(TRUTH_OWNED_CONTROLS)
    (work / 'controls-owned-native.mojo').write_text(TRUTH_OWNED_CONTROLS)
    binary = work / name
    optional_capture(work, 'controls-owned-native-build',
                     [mojo, 'build', '-Werror', '-I', str(native), '-I', str(ROOT),
                      str(native / f'{name}.mojo'), '-o', str(binary)])
    owned_result = optional_capture(work, 'controls-owned-native-run', [str(binary)], timeout=5)
    assert not result_errors(owned_result.stdout), owned_result.stdout
    assert not slow_tests(owned_result.stdout, 5), owned_result.stdout
    owned_rows = [row for row in owned_result.stdout.splitlines() if row.startswith('CONTROL ')]
    assert len(owned_rows) == 32 and 'CONCURRENT' in owned_result.stdout
    assert [row.split()[1:3] for row in two_parameter_rows] == [row.split()[1:3] for row in owned_rows]
    assert two_parameter_rows != owned_rows, 'Independent parameters lost their distinct native traces'
    check_refusal(work, native, rewritten, build, mojo, name, TRUTH_OWNED_CONTROLS,
                  OWNED_CONTROL_WIDTHS, (COMPOUND_REFUSAL, TEMPORARY_SELECTION_REFUSAL))

    (native / 'controls.mojo').write_text(TRUTH_CONTROLS)
    run([str(build), str(rewritten), 'controls.mojo'], cwd=native)
    control_manifest = assert_obligations(
        rewritten, 'controls', single_line_obligations(TRUTH_CONTROLS, CONTROL_WIDTHS))
    (work / 'controls-manifest.txt').write_text('\n'.join(control_manifest) + '\n')
    (work / 'controls-native.mojo').write_text(TRUTH_CONTROLS)
    shutil.copy(rewritten / 'controls.mojo', work / 'controls-instrumented.mojo')
    outputs = []
    for label, folder in (('native', native), ('instrumented', rewritten)):
        binary = work / f'controls-{label}'
        run([mojo, 'build', '-Werror', '-I', str(folder), '-I', str(ROOT),
             str(folder / 'controls.mojo'), '-o', str(binary)])
        result = run([str(binary)], timeout=5)
        assert not result_errors(result.stdout), result.stdout
        assert not slow_tests(result.stdout, 5), result.stdout
        outputs.append(result.stdout.partition('\nRunning ')[0].strip() or result.stdout)
        (work / f'controls-{label}.txt').write_text(result.stdout)
    assert outputs[0] == outputs[1], 'custom truth controls differ'
    assert 'CONCURRENT' in outputs[0] and outputs[0].count('CONTROL ') == 32, outputs[0]
    single_parameter_rows = [row for row in outputs[0].splitlines() if row.startswith('CONTROL ')]
    assert [row.split()[1:3] for row in two_parameter_rows] == [row.split()[1:3] for row in single_parameter_rows]
    check_single_generic_truth(work, native, rewritten, build, mojo)

    check_custom_refusals(work, native, rewritten, build, mojo)
    identity_summary = check_identity_truth(work, native, rewritten, build, mojo)
    last_use_summary = check_last_use_identity_truth(work, native, rewritten, build, mojo)
    temporary_identity_summary = check_temporary_identity_truth(work, native, rewritten, build, mojo)
    check_repeated_truth_guard(work, mojo)
    return (f'{len(TRUTH_CASES)} native/model custom truth trees x 16 masks x 5 failure positions, '
            f'stable and changing; all original trees explicitly refused; {len(NEGATED_TRUTH_CASES)} separate negated-leaf instrumented/model trees, '
            'with own and caller-scope collision names; '
            f'{len(TRUTH_MIXED_REJECTED)} mixed, {len(TRUTH_RETAINED_REJECTED)} retained-selection and {len(TRUTH_TEMPORARY_REJECTED)} temporary-selection trees, '
            'original mixed controls and exact two-parameter controls refused; '
            '64 original generic native/model cases refused and 64 separate negated native/model/trace cases; '
            'a real repeated borrowed-truth vector refused by reducer and reporter; '
            f'{len(TRUTH_REJECTED)} existing rejections; '
            f'{len(LEAF_GUARD_REJECTIONS)} same-type rejections of old mixed sources; '
            f'{len(BOOL_MERGE_REJECTIONS)} Bool-merge rejections x 4 native masks; '
            f'{len(GATED_MERGE_REJECTIONS)} type-gated merge rejections x 4 native masks; '
            f'{identity_summary}; {last_use_summary}; {temporary_identity_summary}')


TEMPORARY_IDENTITY_PRELUDE = '''struct Anchored(ImplicitlyCopyable, Boolable):
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


'''


TEMPORARY_IDENTITY_TYPES = ('Anchored', 'MoveOnly', 'Moving')
TEMPORARY_IDENTITY_POSITIVE_CASES = (
    ('not {kind}(7) or False', False, 'TF'),
    ('flag or not {kind}(7)', False, 'FT'),
    ('not not {kind}(7) and True', True, 'TT'),
)
TEMPORARY_IDENTITY_REFUSED_TEMPLATE = 'not ({kind}(7) or {kind}(9)) or False'


def temporary_identity_source(kind, expression):
    move = 'not ' if kind == 'Moving' else ''
    flag = '    var flag = False\n' if 'flag' in expression else ''
    return TEMPORARY_IDENTITY_PRELUDE + f'''
def main():
    comptime assert {move}{kind}.__move_ctor_is_trivial
    comptime assert {kind}.__del__is_trivial
    print("DIRECT", {kind}(7).__bool__())
{flag}    if {expression}:
        print("BRANCH T")
    else:
        print("BRANCH F")
'''


def check_temporary_identity_truth(work, native, rewritten, build, mojo):
    """Preserve constructor-to-truth identity for every admitted temporary."""
    for kind in TEMPORARY_IDENTITY_TYPES:
        for number, (template, outcome, vector) in enumerate(TEMPORARY_IDENTITY_POSITIVE_CASES):
            expression = template.format(kind=kind)
            name = f'identity-temporary-{kind.lower()}-{number}'
            source = temporary_identity_source(kind, expression)
            expected = (f'CONVERT {kind} True\nDIRECT True\nCONVERT {kind} True\n'
                        + ('BRANCH T\n' if outcome else 'BRANCH F\n'))
            (native / f'{name}.mojo').write_text(source)
            (work / f'{name}-native.mojo').write_text(source)
            binary = work / f'{name}-native'
            optional_capture(work, f'{name}-native-build',
                             [mojo, 'build', '-Werror', '-I', str(native),
                              str(native / f'{name}.mojo'), '-o', str(binary)], timeout=180)
            original = optional_capture(work, f'{name}-native-run', [str(binary)], timeout=5)
            assert original.stdout == expected, (name, 'native constructor/identity control',
                                                  original.stdout, expected)
            optional_capture(work, f'{name}-rewrite',
                             [str(build), str(rewritten), f'{name}.mojo'], cwd=native, timeout=5)
            shutil.copy(rewritten / f'{name}.mojo', work / f'{name}-instrumented.mojo')
            manifest = assert_obligations(
                rewritten, name, single_line_obligations(source, {f'if {expression}:': 2}))
            (work / f'{name}-manifest.txt').write_text('\n'.join(manifest) + '\n')
            assert_identity_origin(rewritten, name, source)
            binary = work / f'{name}-instrumented'
            optional_capture(work, f'{name}-instrumented-build',
                             [mojo, 'build', '-Werror', '-I', str(rewritten),
                              str(rewritten / f'{name}.mojo'), '-o', str(binary)], timeout=180)
            instrumented = optional_capture(work, f'{name}-instrumented-run', [str(binary)], timeout=5)
            assert instrumented.stdout == original.stdout, (name, 'native/instrumented stdout differs')
            decision = next(i for i, line in enumerate(source.splitlines(), 1)
                            if line.strip() == f'if {expression}:')
            truth = 'T' if outcome else 'F'
            expected_records = [f'COVLINE:{name}:{decision}.{slot}:{state}'
                                for slot, state in enumerate(vector)]
            expected_records += [f'COVLINE:{name}:{decision}:{truth}',
                                 f'COVEVAL2:{name}:{decision}:{truth}:{vector};']
            actual_records = [line for line in instrumented.stderr.splitlines()
                              if line.startswith((f'COVLINE:{name}:{decision}:',
                                                  f'COVLINE:{name}:{decision}.',
                                                  f'COVEVAL2:{name}:{decision}:'))]
            assert actual_records == expected_records, (name, actual_records, expected_records)

        name = f'identity-temporary-refused-{kind.lower()}'
        expression = TEMPORARY_IDENTITY_REFUSED_TEMPLATE.format(kind=kind)
        source = temporary_identity_source(kind, expression)
        (native / f'{name}.mojo').write_text(source)
        binary = work / f'{name}-native'
        optional_capture(work, f'{name}-native-build',
                         [mojo, 'build', '-Werror', '-I', str(native),
                          str(native / f'{name}.mojo'), '-o', str(binary)], timeout=180)
        original = optional_capture(work, f'{name}-native-run', [str(binary)], timeout=5)
        selected_move = 'MOVE Moving\n' if kind == 'Moving' else ''
        expected = (f'CONVERT {kind} True\nDIRECT True\nCONVERT {kind} True\n'
                    + selected_move + f'CONVERT {kind} False\nBRANCH T\n')
        assert original.stdout == expected, (name, 'native selected-object identity',
                                             original.stdout, expected)
        check_refusal(work, native, rewritten, build, mojo, name, source,
                      {f'if {expression}:': 3},
                      (COMPOUND_REFUSAL, TEMPORARY_SELECTION_REFUSAL))
        assert_identity_origin(rewritten, name, source)
    return '9 constructor-identity controls and 3 exact temporary-selection refusals'




def repeated_truth_source(probe):
    """Keep the counter storage and truth object alive after both conversions."""
    source = ('from coverage.runtime import buffer, begin, leaf, finish, _borrowed\n'
              'from std.reflection import reflect\n\n') if probe else ''
    source += """@fieldwise_init
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
        source += """    var values = buffer()
    _ = begin(values, 2)
    var observed = leaf(kept, values, "repeat:1.0", 0)
    comptime assert _borrowed(reflect[type_of(observed)].name())
"""
    target = 'observed' if probe else 'kept'
    source += f'    print("FIRST", {target}.__bool__())\n'
    source += f'    print("SECOND", {target}.__bool__())\n'
    if probe:
        source += '    _ = observed^\n'
    # The local storage must outlive its unsafe pointer, and kept must remain
    # retained at leaf() so this really selects the borrowed probe overload.
    source += '    print("COUNT", count, kept.count[])\n'
    if probe:
        source += """    _ = leaf(True, values, "repeat:1.1", 1)
    _ = finish(False, values, "repeat:1")
"""
    return source


def check_repeated_truth_guard(work, mojo):
    """Compare native repeated truth, then exercise both fail-closed readers."""
    expected_stdout = 'FIRST True\nSECOND False\nCOUNT 2 2\n'
    native_result = None
    for probe in (False, True):
        name = 'repeat-probe' if probe else 'repeat-native'
        path, binary = work / f'{name}.mojo', work / name
        path.write_text(repeated_truth_source(probe))
        optional_capture(work, f'{name}-build',
                         [mojo, 'build', '-Werror', '-I', str(ROOT), str(path), '-o', str(binary)],
                         timeout=180)
        result = optional_capture(work, f'{name}-run', [str(binary)], timeout=5)
        assert result.stdout == expected_stdout, (name, result.stdout)
        if not probe:
            assert result.stderr == '', result.stderr
            native_result = result
    assert native_result is not None and result.stdout == native_result.stdout
    expected = ('COVLINE:repeat:1.0:T\nCOVLINE:repeat:1.0:F\n'
                'COVLINE:repeat:1.1:T\nCOVLINE:repeat:1:F\n'
                'COVEVAL2:repeat:1:F:?T;\n')
    assert result.stderr == expected, result.stderr
    reducer = Reducer(lambda record: None)
    try:
        for record in result.stderr.encode().splitlines(keepends=True):
            reducer.feed(record)
        raise AssertionError('the reducer accepted an inconsistent vector')
    except ValueError as error:
        assert 'Inconsistent repeated truth conversion' in str(error), error
    manifest = work / 'repeat-manifest.txt'
    manifest.write_text('B repeat 1\nC repeat 1 0\nM repeat 1 0\nC repeat 1 1\nM repeat 1 1\n')
    raw = work / 'repeat-raw.txt'
    raw.write_text(result.stderr)
    rejected = subprocess.run([str(work / 'report'), str(manifest), str(raw)],
                              text=True, capture_output=True, timeout=5)
    (work / 'repeat-rejected-stdout.txt').write_text(rejected.stdout)
    (work / 'repeat-rejected-stderr.txt').write_text(rejected.stderr)
    assert rejected.returncode != 0, rejected
    assert 'Inconsistent repeated truth conversion' in rejected.stdout + rejected.stderr, rejected


# A bitwise lifecycle does not make truth insensitive to the object's identity.
# Only compare addresses within a process, never absolute addresses across runs.
IDENTITY_PRELUDE = '''@fieldwise_init
struct Identity(ImplicitlyCopyable, Boolable):
    var payload: Int
    var expected: Int

    @inline(.never)
    def __bool__(self) -> Bool:
        var original = Int(Pointer(to=self.payload)) == self.expected
        print("CONVERT", original)
        return original
'''
IDENTITY_POSITIVE_CASES = (
    ('not kept or False', 1, False, 'TF'),
    ('not not kept and True', 1, True, 'TT'),
    ('flag or not kept', 1, False, 'FT'),
    ('not (kept if choose_kept else kept) or False', 1, False, 'TF'),
    ('(not kept) or (not not kept)', 2, True, 'TT'),
    ('flag and not kept', 0, False, 'F-'),
)
IDENTITY_REFUSED_CASES = (
    'kept or kept',
    'kept and kept',
    'kept or Identity(9, 0)',
    '(kept if choose_kept else kept) or kept',
)


def identity_source(expression):
    flag = '    var flag = False\n' if 'flag' in expression else ''
    selector = '    var choose_kept = True\n' if 'choose_kept' in expression else ''
    return IDENTITY_PRELUDE + f'''

def main():
    comptime assert Identity.__copy_ctor_is_trivial
    comptime assert Identity.__move_ctor_is_trivial
    comptime assert Identity.__del__is_trivial
    var kept = Identity(7, 0)
    kept.expected = Int(Pointer(to=kept.payload))
    print("DIRECT", kept.__bool__())
{flag}{selector}    if {expression}:
        print("BRANCH T")
    else:
        print("BRANCH F")
    print("RETAINED", kept.payload)
    print("ADDRESS", Int(Pointer(to=kept.payload)) == kept.expected)
'''


def identity_output(conversions, outcome):
    return ('CONVERT True\nDIRECT True\n' + conversions +
            ('BRANCH T\n' if outcome else 'BRANCH F\n') +
            'RETAINED 7\nADDRESS True\n')


def assert_identity_origin(rewritten, name, source):
    """Bind a fixture's complete source, rewrite and denominator to the builder."""
    encoded = source.encode()
    generated = (rewritten / f'{name}.mojo').read_bytes()
    manifest = (rewritten / 'manifest.txt').read_bytes()
    header, body = (rewritten / f'{name}.mojo.cov-origin').read_bytes().split(b'\n', 1)
    parts = [f'{name}.mojo'.encode(), encoded, generated, manifest]
    assert header == b'COVORIGIN1 ' + b' '.join(str(len(part)).encode() for part in parts)
    assert body == b''.join(parts), (name, 'builder origin differs')
    header, body = (rewritten / 'origins.ready').read_bytes().split(b'\n', 1)
    assert header == b'COVORIGIN_INDEX2 1 ' + str(len(manifest)).encode() + b' 0'
    assert body == manifest + str(len(parts[0])).encode() + b'\n' + parts[0]


def identity_last_use_source(expression):
    """Remove only the retained fixture's two trailing post-use reads."""
    source = identity_source(expression)
    suffix = ('    print("RETAINED", kept.payload)\n'
              '    print("ADDRESS", Int(Pointer(to=kept.payload)) == kept.expected)\n')
    assert source.endswith(suffix)
    return source[:-len(suffix)]


def check_last_use_identity_truth(work, native, rewritten, build, mojo):
    """Compare direct and conditional last-use truth against native execution."""
    for number in (0, 3):
        expression, conversions, outcome, vector = IDENTITY_POSITIVE_CASES[number]
        name = f'identity-last-use-{number}'
        source = identity_last_use_source(expression)
        expected = identity_output('CONVERT True\n' * conversions, outcome)
        suffix = 'RETAINED 7\nADDRESS True\n'
        assert expected.endswith(suffix)
        expected = expected[:-len(suffix)]
        (native / f'{name}.mojo').write_text(source)
        (work / f'{name}-native.mojo').write_text(source)
        native_binary = work / f'{name}-native'
        optional_capture(work, f'{name}-native-build',
                         [mojo, 'build', '-Werror', '-I', str(native),
                          str(native / f'{name}.mojo'), '-o', str(native_binary)],
                         timeout=180)
        actual = optional_capture(work, f'{name}-native-run', [str(native_binary)], timeout=5)
        assert actual.stdout == expected, (name, 'native identity control', actual.stdout, expected)
        optional_capture(work, f'{name}-rewrite',
                         [str(build), str(rewritten), f'{name}.mojo'], cwd=native, timeout=5)
        shutil.copy(rewritten / f'{name}.mojo', work / f'{name}-instrumented.mojo')
        manifest = assert_obligations(
            rewritten, name, single_line_obligations(source, {f'if {expression}:': 2}))
        (work / f'{name}-manifest.txt').write_text('\n'.join(manifest) + '\n')
        assert_identity_origin(rewritten, name, source)
        binary = work / f'{name}-instrumented'
        optional_capture(work, f'{name}-instrumented-build',
                         [mojo, 'build', '-Werror', '-I', str(rewritten),
                          str(rewritten / f'{name}.mojo'), '-o', str(binary)], timeout=180)
        instrumented = optional_capture(work, f'{name}-instrumented-run', [str(binary)], timeout=5)
        assert instrumented.stdout == actual.stdout, (name, 'native/instrumented stdout differs')
        decision = next(number for number, line in enumerate(source.splitlines(), 1)
                        if line.strip() == f'if {expression}:')
        expected_records = [f'COVLINE:{name}:{decision}.{slot}:{state}'
                            for slot, state in enumerate(vector) if state != '-']
        truth = 'T' if outcome else 'F'
        expected_records += [f'COVLINE:{name}:{decision}:{truth}',
                             f'COVEVAL2:{name}:{decision}:{truth}:{vector};']
        actual_records = [line for line in instrumented.stderr.splitlines()
                          if line.startswith((f'COVLINE:{name}:{decision}:',
                                              f'COVLINE:{name}:{decision}.',
                                              f'COVEVAL2:{name}:{decision}:'))]
        assert actual_records == expected_records, (name, actual_records, expected_records)
        (work / f'{name}-expected-records.txt').write_text('\n'.join(expected_records) + '\n')

    return '2 last-use identity controls with exact native truth and traces'


def check_identity_truth(work, native, rewritten, build, mojo):
    """Keep original-object truth under not and refuse premature selection.

    The expected traces describe the original retained object's truth. Trivial
    lifecycle flags do not prove this address-sensitive method copy-invariant.
    """
    for number, (expression, conversions, outcome, vector) in enumerate(IDENTITY_POSITIVE_CASES):
        name = f'identity-positive-{number}'
        source = identity_source(expression)
        expected = identity_output('CONVERT True\n' * conversions, outcome)
        (native / f'{name}.mojo').write_text(source)
        (work / f'{name}-native.mojo').write_text(source)
        native_binary = work / f'{name}-native'
        optional_capture(work, f'{name}-native-build',
                         [mojo, 'build', '-Werror', '-I', str(native),
                          str(native / f'{name}.mojo'), '-o', str(native_binary)],
                         timeout=180)
        actual = optional_capture(work, f'{name}-native-run', [str(native_binary)], timeout=5)
        assert actual.stdout == expected, (name, 'native identity control', actual.stdout, expected)
        optional_capture(work, f'{name}-rewrite',
                         [str(build), str(rewritten), f'{name}.mojo'], cwd=native, timeout=5)
        shutil.copy(rewritten / f'{name}.mojo', work / f'{name}-instrumented.mojo')
        manifest = assert_obligations(
            rewritten, name, single_line_obligations(source, {f'if {expression}:': 2}))
        (work / f'{name}-manifest.txt').write_text('\n'.join(manifest) + '\n')
        assert_identity_origin(rewritten, name, source)
        binary = work / f'{name}-instrumented'
        optional_capture(work, f'{name}-instrumented-build',
                         [mojo, 'build', '-Werror', '-I', str(rewritten),
                          str(rewritten / f'{name}.mojo'), '-o', str(binary)], timeout=180)
        instrumented = optional_capture(work, f'{name}-instrumented-run', [str(binary)], timeout=5)
        assert instrumented.stdout == actual.stdout, (name, 'native/instrumented stdout differs')
        decision = next(number for number, line in enumerate(source.splitlines(), 1)
                        if line.strip() == f'if {expression}:')
        expected_records = [f'COVLINE:{name}:{decision}.{slot}:{state}'
                            for slot, state in enumerate(vector) if state != '-']
        truth = 'T' if outcome else 'F'
        expected_records += [f'COVLINE:{name}:{decision}:{truth}',
                             f'COVEVAL2:{name}:{decision}:{truth}:{vector};']
        actual_records = [line for line in instrumented.stderr.splitlines()
                          if line.startswith((f'COVLINE:{name}:{decision}:',
                                              f'COVLINE:{name}:{decision}.',
                                              f'COVEVAL2:{name}:{decision}:'))]
        assert actual_records == expected_records, (name, actual_records, expected_records)
        (work / f'{name}-expected-records.txt').write_text('\n'.join(expected_records) + '\n')

    for number, expression in enumerate(IDENTITY_REFUSED_CASES):
        name = f'identity-refused-{number}'
        source = identity_source(expression)
        (native / f'{name}.mojo').write_text(source)
        binary = work / f'{name}-native'
        optional_capture(work, f'{name}-native-build',
                         [mojo, 'build', '-Werror', '-I', str(native),
                          str(native / f'{name}.mojo'), '-o', str(binary)], timeout=180)
        native_result = optional_capture(work, f'{name}-native-run', [str(binary)], timeout=5)
        expected = identity_output('CONVERT True\nCONVERT False\n', False)
        assert native_result.stdout == expected, (name, 'native selection timing',
                                                  native_result.stdout, expected)
        check_refusal(work, native, rewritten, build, mojo, name, source,
                      {f'if {expression}:': 2},
                      (COMPOUND_REFUSAL, RETAINED_SELECTION_REFUSAL))
        assert_identity_origin(rewritten, name, source)
    return (f'{len(IDENTITY_POSITIVE_CASES)} original-object identity controls with exact traces; '
            f'{len(IDENTITY_REFUSED_CASES)} native-success identity-selection refusals')


# Optional selection can run payload lifecycle operations that a Bool collapse
# omits. Item/or repeats the pinned regression source and exact event sequence.
# The other native event expectations are source models, not prior pin results.
OPTIONAL_LIFECYCLE_REFUSAL = 'an Optional result with observable copy, move, or destructor effects'
OPTIONAL_PAYLOADS = {
    'Item': '''struct Item(ImplicitlyCopyable):
    var index: Int

    def __init__(out self, index: Int):
        self.index = index
        print("CREATE", index)

    def __init__(out self, *, copy: Self):
        self.index = copy.index
        print("COPY", self.index)

    def __init__(out self, *, deinit move: Self):
        self.index = move.index
        print("MOVE", self.index)

    def __deinit__(deinit self):
        print("DROP", self.index)
''',
    'CopyOnly': '''struct CopyOnly(ImplicitlyCopyable):
    var index: Int

    def __init__(out self, index: Int):
        self.index = index
        print("CREATE", index)

    def __init__(out self, *, copy: Self):
        self.index = copy.index
        print("COPY", self.index)
''',
    'CopyDrop': '''@fieldwise_init
struct CopyDrop(ImplicitlyCopyable):
    var index: Int

    def __deinit__(deinit self):
        print("DROP", self.index)
''',
    'MoveOnly': '''struct MoveOnly(Movable):
    var index: Int

    def __init__(out self, index: Int):
        self.index = index
        print("CREATE", index)

    def __init__(out self, *, deinit move: Self):
        self.index = move.index
        print("MOVE", self.index)

    def __deinit__(deinit self):
        print("DROP", self.index)
''',
    'Trivial': '''@fieldwise_init
struct Trivial(ImplicitlyCopyable):
    var index: Int
''',
}


def check_custom_refusals(work, native, rewritten, build, mojo):
    """Run every original and same-type negative control without omissions."""
    refused_sources = dict(TRUTH_REJECTED)
    refused_sources.update(LEAF_GUARD_REJECTIONS)
    refused_sources.update({name: (text, BOOL_MERGE_REFUSAL)
                            for name, (text, _) in BOOL_MERGE_REJECTIONS.items()})
    refused_sources.update({name: (text, BOOL_MERGE_REFUSAL)
                            for name, (text, _) in GATED_MERGE_REJECTIONS.items()})
    for name, (text, message) in refused_sources.items():
        (native / f'{name}.mojo').write_text(text)
        (work / f'truth-{name}-native.mojo').write_text(text)
        optional_capture(work, f'truth-{name}-native-build',
                         [mojo, 'build', '-Werror', '-I', str(native), str(native / f'{name}.mojo'),
                          '-o', str(work / name)])
        native_output = optional_capture(
            work, f'truth-{name}-native-run', [str(work / name)], timeout=5).stdout
        (work / f'truth-{name}-native.txt').write_text(native_output)
        if name in NATIVE_REJECTED_OUTPUT:
            assert native_output == NATIVE_REJECTED_OUTPUT[name], (name, native_output)
        if name in NESTED_OPTIONAL_REJECTIONS:
            assert native_output == NESTED_OPTIONAL_REJECTIONS[name][1], (
                name, native_output, NESTED_OPTIONAL_REJECTIONS[name][1])
        if name in BOOL_MERGE_REJECTIONS:
            assert native_output == BOOL_MERGE_REJECTIONS[name][1], (
                name, native_output, BOOL_MERGE_REJECTIONS[name][1])
            assert 'BOOL R' not in native_output, (name, native_output)
        if name in GATED_MERGE_REJECTIONS:
            assert native_output == GATED_MERGE_REJECTIONS[name][1], (
                name, native_output, GATED_MERGE_REJECTIONS[name][1])
            assert ('MERGE G' in native_output) == name.endswith('-flag'), (name, native_output)
        # These negative fixtures each have one two-operand decision. Scalar
        # decisions in their constructors/helpers remain obligations as well.
        compound = [line.strip() for line in text.splitlines()
                    if line.strip().startswith('if ') and (' and ' in line or ' or ' in line)]
        assert len(compound) == 1, (name, compound)
        # Every source reaches the operator check. Require its intended
        # semantic diagnostic, never an arbitrary compiler error.
        check_refusal(work, native, rewritten, build, mojo, name, text,
                      {compound[0]: 2}, (COMPOUND_REFUSAL, message))


def optional_factory(payload, name='optional'):
    return f'''

def {name}(index: Int, full: Bool) -> Optional[{payload}]:
    print("MAKE", index, full)
    if full:
        return {payload}(index)
    return None
'''


def optional_lifecycle_expected(payload, operator):
    """Model selected native copy/move/drop independently of instrumenting.

    Item/or follows the saved 8189361e native receipt. All other cases are
    explicit source-model expectations awaiting their first pinned run. Do
    not update these by copying instrumented output if qualification fails.
    """
    lines = []
    custom_copy = payload in ('Item', 'CopyOnly')
    custom_move = payload in ('Item', 'MoveOnly')
    drops = payload in ('Item', 'CopyDrop', 'MoveOnly')

    def make(index, full):
        lines.append(f'MAKE {index} {full}')
        if full:
            if payload != 'CopyDrop':
                lines.append(f'CREATE {index}')
            if custom_move:
                lines.append(f'MOVE {index}')

    def drop(index, full):
        if full and drops:
            lines.append(f'DROP {index}')

    for first in (False, True):
        for second in (False, True):
            short = first if operator == 'or' else not first
            selected, present = (0, first) if short else (1, second)
            if payload != 'MoveOnly':
                lines.append(f'RETAINED {first} {second}')
                make(0, first)
                make(1, second)
                if present and custom_copy:
                    lines.append(f'COPY {selected}')
                drop(selected, present)
                lines.append('BODY T' if present else 'BODY F')
                # This is the established source form: post-use in the print
                # arguments keeps the operands retained at the operator. Its
                # last-use destruction precedes the final print in the pin.
                drop(0, first)
                drop(1, second)
                lines.append(f'RETAINED AFTER {first} {second}')
            lines.append(f'TEMPORARY {first} {second}')
            make(0, first)
            if not short:
                drop(0, first)
                make(1, second)
            if present and custom_move:
                lines.append(f'MOVE {selected}')
            drop(selected, present)
            lines.append('BODY T' if present else 'BODY F')
    return '\n'.join(lines) + '\n'


def optional_lifecycle_rejections():
    """Keep native-valid custom lifecycle pairs as exact-source refusals."""
    cases = {}
    for payload in ('Item', 'CopyOnly', 'CopyDrop', 'MoveOnly'):
        for operator in ('and', 'or'):
            source = OPTIONAL_PAYLOADS[payload] + optional_factory(payload)
            widths = {}
            if payload != 'MoveOnly':
                expression = f'left {operator} right'
                widths[f'if {expression}:'] = 2
                source += f'''

def retained(first: Bool, second: Bool):
    print("RETAINED", first, second)
    var left = optional(0, first)
    var right = optional(1, second)
    if {expression}:
        print("BODY T")
    else:
        print("BODY F")
    print("RETAINED AFTER", Bool(left), Bool(right))
'''
            expression = f'optional(0, first) {operator} optional(1, second)'
            widths[f'if {expression}:'] = 2
            source += f'''

def temporary(first: Bool, second: Bool):
    print("TEMPORARY", first, second)
    if {expression}:
        print("BODY T")
    else:
        print("BODY F")


def main():
    for first in [False, True]:
        for second in [False, True]:
'''
            if payload != 'MoveOnly':
                source += '            retained(first, second)\n'
            source += '            temporary(first, second)\n'
            cases[f'optional-{payload.lower()}-{operator}'] = (
                source, widths, optional_lifecycle_expected(payload, operator))
    return cases


OPTIONAL_LIFECYCLE_REJECTIONS = optional_lifecycle_rejections()


def optional_positive_source():
    """Exercise guard placement and storage-owner moves, with exact parity."""
    source = '\n'.join(OPTIONAL_PAYLOADS.values())
    for payload in OPTIONAL_PAYLOADS:
        source += optional_factory(payload, f'optional_{payload}')
    source += '''

def flag(index: Int, value: Bool) -> Bool:
    print("FLAG", index, value)
    return value


def items(index: Int, full: Bool) -> List[Item]:
    print("LIST", index, full)
    var result = List[Item]()
    if full:
        result.append(Item(index))
    return result^


def optional_items(index: Int, full: Bool) -> Optional[List[Item]]:
    print("OPTIONAL LIST", index, full)
    if full:
        return items(index, True)
    return None
'''
    cases = []
    for payload in ('Item', 'CopyOnly', 'CopyDrop', 'MoveOnly'):
        setup = f'    var retained = optional_{payload}(2, first)\n'
        after = '    print("RETAINED AFTER", Bool(retained))\n'
        leaf = f'optional_{payload}(0, first)'
        for expression, width in (
            (f'not {leaf}', 1), ('not retained', 1),
            (f'{leaf} and flag(1, second)', 2),
            (f'{leaf} or flag(1, second)', 2),
            ('retained and flag(1, second)', 2),
            ('retained or flag(1, second)', 2),
        ):
            retained = 'retained' in expression
            cases.append((setup if retained else '', expression,
                          after if retained else '', width))
    for operator in ('and', 'or'):
        cases.append(('', f'optional_Trivial(0, first) {operator} optional_Trivial(1, second)', '', 2))
        cases.append(('    var left = optional_Trivial(0, first)\n'
                      '    var right = optional_Trivial(1, second)\n',
                      f'left {operator} right',
                      '    print("AFTER", Bool(left), Bool(right))\n', 2))
        cases.append(('', f'optional_items(0, first) {operator} optional_items(1, second)', '', 2))
        cases.append(('', f'items(0, first) {operator} items(1, second)', '', 2))
        cases.append(('    var retained = items(0, first)\n',
                      f'retained {operator} flag(1, second)',
                      '    print("AFTER", len(retained))\n', 2))
        cases.append(('    var left = items(0, first)\n'
                      '    var right = items(1, second)\n',
                      f'left.copy() {operator} right.copy()',
                      '    print("AFTER", len(left), len(right))\n', 2))
    widths = {}
    for number, (setup, expression, after, width) in enumerate(cases):
        if width > 1:
            widths[f'if {expression}:'] = width
        source += f'''

def positive_{number}(first: Bool, second: Bool):
    print("POSITIVE", {number}, first, second)
{setup}    if {expression}:
        print("BODY T")
    else:
        print("BODY F")
{after}'''
    source += '\n\ndef main():\n    for first in [False, True]:\n        for second in [False, True]:\n'
    source += ''.join(f'            positive_{number}(first, second)\n' for number in range(len(cases)))
    return source, widths, len(cases)


# Only public String operations appear here. In Mojo 1.1 the nondeprecated
# APIs are capacity_bytes/reserve_bytes and String(capacity_bytes=...). A
# literal remains static until mutation; build the inline case from String().
OPTIONAL_STRING_PRELUDE = '''def heap_string() -> String:
    var text = String(capacity_bytes=256)
    text += "heap-buffer-abcdefghijklmnopqrstuvwxyz-0123456789"
    return text^


def optional_string(index: Int, full: Bool, flavor: Int, shared: String) -> Optional[String]:
    print("MAKE STRING", index, full, flavor)
    if not full:
        return None
    if flavor == 0:
        return String()
    if flavor == 1:
        var text = String()
        text += "tiny"
        return text^
    if flavor == 2:
        return String("static-buffer-abcdefghijklmnopqrstuvwxyz-0123456789")
    if flavor == 3:
        return heap_string()
    return shared.copy()


def inspect_string(index: Int, value: Optional[String]):
    if value:
        print("STRING", index, True, value.value(), value.value().byte_length(), value.value().capacity_bytes())
    else:
        print("STRING", index, False)


def mutate_strings(mut left: Optional[String], mut right: Optional[String]) -> Bool:
    print("MUTATE")
    inspect_string(0, left)
    inspect_string(1, right)
    if left:
        left.value().write("!")
    if right:
        right.value().write("?")
    inspect_string(0, left)
    inspect_string(1, right)
    return True
'''


def optional_string_source():
    """Qualify the fixed standard type, including public COW observations.

    Every retained owner is used afterward to exercise that source category.
    There is no post-use added to a temporary and no lifetime-pinning pointer.
    The shared backing is used afterward so explicit copies really do share
    an owner across mutation. Identical source feeds both compilers.
    """
    source, widths, cases = OPTIONAL_STRING_PRELUDE, {}, []
    left = 'optional_string(0, first, flavor, shared)'
    right = 'optional_string(1, second, flavor, shared)'
    for operator in ('and', 'or'):
        for category, expression, retained_left, retained_right in (
            ('retained', f'left {operator} right', True, True),
            ('temporary', f'{left} {operator} {right}', False, False),
            ('retained-temporary', f'left {operator} {right}', True, False),
            ('temporary-retained', f'{left} {operator} right', False, True),
        ):
            cases.append((category, operator, None, expression, retained_left, retained_right))
        for outer in ('and', 'or'):
            cases.append((f'mutate-{outer}', operator, outer,
                          f'(left {operator} right) {outer} mutate_strings(left, right)', True, True))
    for number, (category, operator, outer, expression, retained_left, retained_right) in enumerate(cases):
        setup, after = '', ''
        if retained_left:
            setup += f'    var left = {left}\n'
            after += '    inspect_string(0, left)\n'
        if retained_right:
            setup += f'    var right = {right}\n'
            after += '    inspect_string(1, right)\n'
        widths[f'if {expression}:'] = 3 if outer else 2
        source += f'''

def strings_{number}(first: Bool, second: Bool, flavor: Int):
    print("STRING CASE", {number}, flavor, first, second)
    var shared = heap_string()
{setup}    if {expression}:
        print("STRING BODY", {number}, flavor, first, second, True)
    else:
        print("STRING BODY", {number}, flavor, first, second, False)
{after}    print("SHARED AFTER", shared, shared.byte_length(), shared.capacity_bytes())
'''
    source += '\n\ndef run_string_controls():\n    for flavor in range(5):\n        for first in [False, True]:\n            for second in [False, True]:\n'
    source += ''.join(f'                strings_{number}(first, second, flavor)\n' for number in range(len(cases)))
    nested_source, nested_widths, nested_expected = nested_optional_string_source()
    source += nested_source
    widths.update(nested_widths)
    source += '\n\ndef main():\n    run_string_controls()\n    run_nested_string_controls()\n'
    expected = []
    for flavor in range(5):
        for first in (False, True):
            for second in (False, True):
                for number, (_, operator, outer, _, _, _) in enumerate(cases):
                    pair = (first and second) if operator == 'and' else (first or second)
                    outcome = True if outer == 'or' else pair
                    expected.append(f'STRING BODY {number} {flavor} {first} {second} {outcome}')
    return source, widths, expected + nested_expected



def nested_optional_string_source():
    """Distinguish an absent outer Optional from a present, empty inner one."""
    source = '''

def nested_string(index: Int, full: Bool, flavor: Int) -> Optional[Optional[String]]:
    print("MAKE NESTED STRING", index, full, flavor)
    if not full:
        return None
    if flavor == 0:
        return Optional[String](None)
    if flavor == 1:
        return Optional[String](String())
    return Optional[String](heap_string())


def inspect_nested_string(index: Int, value: Optional[Optional[String]]):
    print("OUTER STRING", index, Bool(value))
    if value:
        inspect_string(index, value.value())
'''
    widths, expected = {}, []
    cases = []
    for operator in ('and', 'or'):
        for retained in (True, False):
            left, right = 'nested_string(0, first, flavor)', 'nested_string(1, second, flavor)'
            setup, after = '', ''
            if retained:
                setup = f'    var left = {left}\n    var right = {right}\n'
                left, right = 'left', 'right'
                after = '    inspect_nested_string(0, left)\n    inspect_nested_string(1, right)\n'
            expression = f'{left} {operator} {right}'
            number = len(cases)
            cases.append(operator)
            widths[f'if {expression}:'] = 2
            source += f'''

def nested_strings_{number}(first: Bool, second: Bool, flavor: Int):
    print("NESTED STRING CASE", {number}, flavor, first, second)
{setup}    if {expression}:
        print("NESTED STRING BODY", {number}, flavor, first, second, True)
    else:
        print("NESTED STRING BODY", {number}, flavor, first, second, False)
{after}'''
    source += '\n\ndef run_nested_string_controls():\n    for flavor in range(3):\n        for first in [False, True]:\n            for second in [False, True]:\n'
    source += ''.join(f'                nested_strings_{number}(first, second, flavor)\n'
                      for number in range(len(cases)))
    for flavor in range(3):
        for first in (False, True):
            for second in (False, True):
                for number, operator in enumerate(cases):
                    outcome = (first and second) if operator == 'and' else (first or second)
                    expected.append(f'NESTED STRING BODY {number} {flavor} {first} {second} {outcome}')
    return source, widths, expected


def optional_decision_models():
    """Declare reference trees separately from source spelling and rewriting.

    Integers name input values: first, second, and the mutation helper's True
    result. Negation applies to the outcome, not to its leaf observation.
    """
    simple = [('not', 0), ('not', 0), ('and', 0, 1), ('or', 0, 1),
              ('and', 0, 1), ('or', 0, 1)]
    positive = simple * 4 + [('and', 0, 1)] * 6 + [('or', 0, 1)] * 6
    strings = []
    for operator in ('and', 'or'):
        pair = (operator, 0, 1)
        strings += [pair] * 4 + [('and', pair, 2), ('or', pair, 2)]
    nested = [('and', 0, 1)] * 2 + [('or', 0, 1)] * 2
    return {
        'positive': {f'positive_{number}': tree for number, tree in enumerate(positive)},
        'strings': {f'strings_{number}': tree for number, tree in enumerate(strings)},
        'nested_strings': {f'nested_strings_{number}': tree for number, tree in enumerate(nested)},
    }


def optional_decision_lines(source, models):
    """Locate each tested decision inside its generated function declaration."""
    lines, function = {}, None
    declared = set()
    prefixes = {function.rsplit('_', 1)[0] for function in models}
    for line, text in enumerate(source.splitlines(), 1):
        if text.startswith('def '):
            function = text[4:].split('(', 1)[0]
            if function.rsplit('_', 1)[0] in prefixes:
                assert function in models, (function, 'missing independent model')
            if function in models:
                assert function not in declared, function
                declared.add(function)
        elif function in models and text.startswith('    if '):
            assert function not in lines, (function, 'more than one main decision')
            lines[function] = line
    assert set(lines) == set(models) == declared, (lines, models, declared)
    return lines


def optional_presence_records(tree, values, module, line):
    """Model exact stable hits and masked slots without using the runtime."""
    def width(node):
        return 1 if isinstance(node, int) else sum(width(child) for child in node[1:])

    observations, next_slot = [], [0]

    def evaluate(node):
        if isinstance(node, int):
            slot = next_slot[0]
            next_slot[0] += 1
            value = bool(values[node])
            observations.append((slot, value))
            return value
        operator = node[0]
        if operator == 'not':
            return not evaluate(node[1])
        left = evaluate(node[1])
        if (operator == 'and' and not left) or (operator == 'or' and left):
            next_slot[0] += width(node[2])
            return left
        return evaluate(node[2])

    outcome = evaluate(tree)
    count = width(tree)
    assert next_slot[0] == count
    tag = f'{module}:{line}'
    # Every tested source decision first emits its ordinary line hit.
    records = [f'COVLINE:{tag}']
    if count > 1:
        records += [f'COVLINE:{tag}.{slot}:{"T" if value else "F"}'
                    for slot, value in observations]
    records.append(f'COVLINE:{tag}:{"T" if outcome else "F"}')
    if count > 1:
        states = dict(observations)
        vector = ''.join('-' if slot not in states else ('T' if states[slot] else 'F')
                         for slot in range(count))
        records.append(f'COVEVAL2:{tag}:{"T" if outcome else "F"}:{vector};')
    return records


def optional_trace_expected(source, module, groups):
    """Construct a chronological oracle for only the generated main decisions."""
    models = optional_decision_models()
    expected, decision_lines = [], set()
    for group, repeats in groups:
        trees = models[group]
        lines = optional_decision_lines(source, trees)
        decision_lines.update(lines.values())
        for _ in range(repeats):
            for first in (False, True):
                for second in (False, True):
                    for function, tree in trees.items():
                        expected += optional_presence_records(
                            tree, (first, second, True), module, lines[function])
    return expected, decision_lines


def assert_optional_traces(work, module, source, raw, groups):
    """Assert interleaved decision/condition hits and complete vectors exactly."""
    expected, decisions = optional_trace_expected(source, module, groups)
    actual = []
    for row in raw.splitlines():
        fields = row.split(':')
        if len(fields) < 3 or fields[0] not in ('COVLINE', 'COVEVAL2') or fields[1] != module:
            continue
        main_line = fields[2].split('.', 1)[0]
        if main_line.isdigit() and int(main_line) in decisions:
            actual.append(row)
    (work / f'{module}-main-trace-expected.txt').write_text('\n'.join(expected) + '\n')
    (work / f'{module}-main-trace-actual.txt').write_text('\n'.join(actual) + '\n')
    assert actual == expected, (module, 'main decision/condition/vector order differs', actual, expected)


def optional_capture(work, stem, command, **kwargs):
    """Save diagnostics and actual output before checking a new probe's exit."""
    try:
        result = subprocess.run(command, text=True, capture_output=True, **kwargs)
    except subprocess.TimeoutExpired as error:
        for label, data in (('stdout', error.stdout), ('stderr', error.stderr)):
            if isinstance(data, bytes):
                data = data.decode(errors='replace')
            (work / f'{stem}-{label}.txt').write_text(data or '')
        (work / f'{stem}-returncode.txt').write_text('timeout\n')
        raise
    (work / f'{stem}-stdout.txt').write_text(result.stdout)
    (work / f'{stem}-stderr.txt').write_text(result.stderr)
    (work / f'{stem}-returncode.txt').write_text(str(result.returncode) + '\n')
    if result.returncode:
        raise RuntimeError(f'{command}:\n{result.stdout}\n{result.stderr}')
    return result


def check_optional_parity(work, native, rewritten, build, mojo, name, source, widths):
    """Retain exact sources, stdout, stderr and every B/C/M obligation."""
    (native / f'{name}.mojo').write_text(source)
    (work / f'{name}-native.mojo').write_text(source)
    optional_capture(work, f'{name}-rewrite',
                     [str(build), str(rewritten), f'{name}.mojo'], cwd=native, timeout=5)
    shutil.copy(rewritten / f'{name}.mojo', work / f'{name}-instrumented.mojo')
    shutil.copy(rewritten / 'manifest.txt', work / f'{name}-manifest-raw.txt')
    manifest = assert_obligations(rewritten, name, single_line_obligations(source, widths))
    (work / f'{name}-manifest.txt').write_text('\n'.join(manifest) + '\n')
    outputs = []
    for label, folder in (('native', native), ('instrumented', rewritten)):
        binary = work / f'{name}-{label}'
        optional_capture(work, f'{name}-{label}-build',
                         [mojo, 'build', '-Werror', '-I', str(folder),
                          str(folder / f'{name}.mojo'), '-o', str(binary)])
        result = optional_capture(work, f'{name}-{label}-run', [str(binary)], timeout=5)
        outputs.append(result.stdout)
        (work / f'{name}-{label}.txt').write_text(result.stdout)
        (work / f'{name}-{label}-stderr.txt').write_text(result.stderr)
    assert outputs[0] == outputs[1], (name, 'native/instrumented stdout differs')
    return outputs[0], result.stderr


def check_optional_lifecycles(work, native, rewritten, build, mojo):
    """Require native success, the specific refusal and retained obligations."""
    for name, (source, widths, expected) in OPTIONAL_LIFECYCLE_REJECTIONS.items():
        (native / f'{name}.mojo').write_text(source)
        (work / f'{name}-expected.txt').write_text(expected)
        binary = work / name
        (work / f'truth-{name}-native.mojo').write_text(source)
        optional_capture(work, f'{name}-native-build',
                         [mojo, 'build', '-Werror', '-I', str(native),
                          str(native / f'{name}.mojo'), '-o', str(binary)])
        result = optional_capture(work, f'{name}-native-run', [str(binary)], timeout=5)
        # Keep actual output before checking the independent oracle. A model
        # mismatch must leave useful evidence, never become a refusal pass.
        (work / f'truth-{name}-native.txt').write_text(result.stdout)
        (work / f'truth-{name}-native-stderr.txt').write_text(result.stderr)
        assert result.stdout == expected, (name, result.stdout, expected)
        check_refusal(work, native, rewritten, build, mojo, name, source, widths,
                      (COMPOUND_REFUSAL, OPTIONAL_LIFECYCLE_REFUSAL))
    source, widths, count = optional_positive_source()
    output, raw = check_optional_parity(work, native, rewritten, build, mojo,
                                       'optional-positive', source, widths)
    assert output.count('POSITIVE ') == count * 4, output
    assert_optional_traces(work, 'optional-positive', source, raw, [('positive', 1)])
    source, widths, expected = optional_string_source()
    output, raw = check_optional_parity(work, native, rewritten, build, mojo,
                                       'optional-string', source, widths)
    assert [line for line in output.splitlines()
            if line.startswith(('STRING BODY ', 'NESTED STRING BODY '))] == expected
    assert_optional_traces(work, 'optional-string', source, raw,
                           [('strings', 5), ('nested_strings', 3)])
    return (f'{len(OPTIONAL_LIFECYCLE_REJECTIONS)} Optional lifecycle refusals, 56 native cases; '
            f'{count * 4} accepted Optional/List lifecycle controls; '
            '240 standard Optional[String] value/capacity controls; '
            '48 same-depth Optional[Optional[String]] controls; exact main decision traces/vectors')


# The operator check evaluates these runtime helpers at compile time.
# Pinned Mojo 1.1.0 can deadlock a single-threaded build that evaluates
# `startswith` or `find` there: the instrumented `materials/nodes.mojo`
# waited forever on one `flag or mask.reduce_or()` check.
COMPILE_TIME_HELPERS = ('node', '_pure', '_starts', '_bracket', '_optional', '_borrowed',
                        '_standard_string_optional', '_optional_lifecycle')
COMPILE_TIME_FORBIDDEN = ('.startswith(', '.find(')
# A bound on one single-threaded build of the reduced fixture. It builds in
# seconds; the deadlock never finishes.
COMPILE_TIME_BOUND = 120

COMPILE_TIME_NAMES = '''from coverage.runtime import _bracket, _optional, _pure, _scalar, _starts
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

# The compile-time results must agree with the runtime results.
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
'''

COMPILE_TIME_SCALARS = {'Bool', 'Scalar[bool]', 'Int', 'String'}

# Mixed pure operands, including the `Bool or SIMD[DType.bool, 1]` operator
# that hung the coverage build of `materials/nodes.mojo`.
COMPILE_TIME_FIXTURE = '''comptime READS = SIMD[DType.int32, 4](1, 2, 3, 4)


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
'''


def helper_bodies(text):
    """Return each compile-time helper's code without docstrings or comments."""
    bodies = {}
    lines = text.splitlines()
    for name in COMPILE_TIME_HELPERS:
        starts = [index for index, line in enumerate(lines)
                  if line.startswith((f'def {name}[', f'def {name}('))]
        assert len(starts) == 1, (name, starts)
        end = starts[0] + 1
        while end < len(lines) and (not lines[end] or lines[end][0] in ' )]'):
            end += 1
        body = '\n'.join(lines[starts[0]:end])
        body = re.sub(r'"""(.|\n)*?"""', '', body)
        bodies[name] = '\n'.join(line.split('#')[0] for line in body.splitlines())
    return bodies


def check_compile_time_names(work, native, rewritten, build, mojo):
    """Keep the operator check's compile-time name tests off deadlocking calls."""
    bodies = helper_bodies((ROOT / 'coverage/runtime.mojo').read_text())
    for name, body in bodies.items():
        for call in COMPILE_TIME_FORBIDDEN:
            assert call not in body, f'{name} evaluates {call} at compile time'
    # The replacements must give exactly the standard results.
    (native / 'names.mojo').write_text(COMPILE_TIME_NAMES)
    run([mojo, 'build', '-Werror', '-I', str(native), str(native / 'names.mojo'),
         '-o', str(work / 'names')], timeout=COMPILE_TIME_BOUND)
    output = run([str(work / 'names')], timeout=5).stdout
    (work / 'names-native.txt').write_text(output)
    rows = output.splitlines()
    assert rows[0] == 'FIXED True', rows[0]
    starts = [row.split()[1:] for row in rows if row.startswith('STARTS ')]
    brackets = [row.split()[1:] for row in rows if row.startswith('BRACKET ')]
    assert (len(starts), len(brackets)) == (16 * 16, 16), (len(starts), len(brackets))
    for left, right in starts + brackets:
        assert left == right, (left, right, rows)
    assert {left for left, _ in starts} == {'True', 'False'}, starts
    types = [row.split() for row in rows if row.startswith('TYPE ')]
    assert len(types) == 11, types
    for _, label, scalar, pure, optional in types:
        # Type identity answers only what the pure-name branch also answers.
        assert (scalar == 'True') == (label in COMPILE_TIME_SCALARS), (label, scalar)
        if scalar == 'True':
            assert (pure, optional) == ('True', 'False'), (label, pure, optional)
    # A one-thread build of the instrumented operators must finish in bounds
    # and keep the native output.
    (native / 'names_fixture.mojo').write_text(COMPILE_TIME_FIXTURE)
    run([str(build), str(rewritten), 'names_fixture.mojo'], cwd=native)
    instrumented = (rewritten / 'names_fixture.mojo').read_text()
    assert instrumented.count('_cov_eval_node[') == 8, instrumented.count('_cov_eval_node[')
    outputs = []
    for label, folder in (('native', native), ('instrumented', rewritten)):
        binary = work / f'names-fixture-{label}'
        try:
            run([mojo, 'build', '--num-threads', '1', '-Werror', '-I', str(folder),
                 str(folder / 'names_fixture.mojo'), '-o', str(binary)],
                timeout=COMPILE_TIME_BOUND)
        except subprocess.TimeoutExpired:
            raise AssertionError(f'{label} names fixture build exceeded '
                                 f'{COMPILE_TIME_BOUND} s on one compiler thread') from None
        result = run([str(binary)], timeout=5)
        (work / f'names-fixture-{label}.txt').write_text(result.stdout)
        outputs.append(result.stdout)
    assert outputs[0] == outputs[1], outputs
    assert len(outputs[0].splitlines()) == 12, outputs[0]
    return (f'{len(starts) + len(brackets)} byte-exact name-test results, {len(types)} scalar identities, '
            'and a bounded one-thread build of 5 mixed pure decisions')


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
                    result = run([str(binary)], env=environment, timeout=5)
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
        names_summary = check_compile_time_names(work, native, rewritten, build, mojo)
        try:
            truth_summary = check_custom_truth(work, native, rewritten, build, mojo)
        finally:
            if args.output:
                args.output.mkdir(parents=True, exist_ok=True)
                for path in work.iterdir():
                    if path.suffix in ('.txt', '.mojo') and path.name.startswith(
                            ('truth-', 'controls-', 'generic-', 'identity-', 'negated-', 'repeat-')):
                        shutil.copy(path, args.output / path.name)

        lifetime, lifetime_cases = lifetime_source()
        (native / 'lifetime.mojo').write_text(lifetime)
        run([str(build), str(rewritten), 'lifetime.mojo'], cwd=native)
        lifetime_manifest = assert_obligations(
            rewritten, 'lifetime', single_line_obligations(lifetime, {
                f'if {expression}:': 1 + expression.count(' and ') + expression.count(' or ')
                for expression in lifetime_cases}))
        (work / 'lifetime-manifest.txt').write_text('\n'.join(lifetime_manifest) + '\n')
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

        try:
            optional_summary = check_optional_lifecycles(work, native, rewritten, build, mojo)
        finally:
            # A first-run native/model or standard-String mismatch is evidence,
            # not a disposable temporary directory or a successful refusal.
            if args.output:
                args.output.mkdir(parents=True, exist_ok=True)
                for path in work.iterdir():
                    if path.suffix in ('.txt', '.mojo') and path.name.startswith(
                            ('optional-', 'truth-optional-')):
                        shutil.copy(path, args.output / path.name)

        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            for path in work.glob('*.txt'):
                shutil.copy(path, args.output / path.name)
            for path in work.glob('*.mojo'):
                shutil.copy(path, args.output / path.name)
            shutil.copy(native / 'lifetime.mojo', args.output / 'lifetime-native.mojo')
            shutil.copy(rewritten / 'lifetime.mojo', args.output / 'lifetime-instrumented.mojo')
            shutil.copy(native / 'fixture.mojo', args.output / 'native.mojo')
            shutil.copy(rewritten / 'fixture.mojo', args.output / 'instrumented.mojo')
            (args.output / 'manifest.txt').write_text('\n'.join(manifest) + '\n')
        print(f'PASS: {len(CASES)} native/instrumented cases, 64 truth assignments, normal and 6 throwing positions; '
              'exact order/count/outcomes, manifest C/M, raw/reduced Mojo vectors, and negative report; '
              f'{len(lifetime_cases)} container destructor-order cases; {names_summary}; {truth_summary}; '
              f'{optional_summary}')


if __name__ == '__main__':
    main()
