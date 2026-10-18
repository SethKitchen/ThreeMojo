#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Private-adapter AST and synthetic observation wiring controls.

The Fake classes use tiny physical files and synthetic owner validation. They
prove adapter forwarding, observation placement, and public/private parity;
they do not establish real immutable-image admission or owner lifecycle safety.
The existing real-gate suites remain mandatory. No gate runs at import time.
"""
import ast
from collections import Counter
from contextlib import contextmanager
import copy
import hashlib
import inspect
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import accepted_successor_contracts as accepted
import coverage_followup_contracts as followup
import coverage_invariant_contracts as invariant
import full_audit_cleanup_contracts as cleanup
import rounded_line_selector_contracts as selector
import source_contracts as source
import sum2_guard_contracts as guard
import test_paired_pin_contracts as paired_helpers
import test_owner_frame_lexical as owner_helpers

LANE = 'extensions/carla/lane_refinement.mojo'
ROAD = 'extensions/carla/road.mojo'
# These are the complete v17 public predecessors, recovered only through the
# exact reviewed #333 structural inverse below. Never replace these digests.
FROZEN_SELECTOR_AST = '9b5e8585b655328d7d8e33c0c81a8df14aea31e386184b98390d5b12b40ee17c'
FROZEN_PAIR_AST = '0d8a776fbcb25b7f89d6ca08e293bc3776e31794989fe2b3fc989ce7b3eb1a59'
SELECTOR_PLUMBING = (
    "full_audit._observe_text(root, item['path'], (root / item['path']).read_text(), _operation=_operation)",
    "full_audit._observe_text(root, item['path'], (root / item['path']).read_text(), _operation=_operation)",
    'full_audit._observe_text(root, name, (root / name).read_text(), _operation=_operation)',
    'full_audit._observe_text(root, name, (root / name).read_text(), _operation=_operation)',
    'full_audit._observe_text(root, path, (root / path).read_text(), _operation=_operation)',
    'full_audit._observe_bytes(root, name, physical.read_bytes(), _operation=_operation)',
    'full_audit._observe_bytes(root, name, full_audit._regular(root, name).read_bytes(), _operation=_operation)',
    "full_audit._observe_text(root, name, physical.read_text(), _operation=_operation, mode='physical', supplied=True, _checked_raw=raw)",
    '_lane_observation(root, **operation_args)', '_lane_observation(root, **operation_args)',
    'full_audit._reviewed_lane_observation(root, text, observed_raw, **operation_args)',
    'full_audit._reviewed_lane_observation(root, text, observed_raw, **operation_args)',
)
PAIR_PLUMBING = (
    '_verify_current_for_pin_pair(root, _operation=_operation)',
    '_read_current_pair_pin(root, runtime_name, _operation=_operation)',
    '_read_current_pair_pin(root, guard_name, _operation=_operation)',
    '_read_current_pair_pin(root, filename, _operation=_operation)',
)


def function_ast(module, name):
    tree = ast.parse(Path(module.__file__).read_text())
    return next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == name)


def ast_key(node):
    return ast.dump(node, include_attributes=False)


# These freeze the current public body/factory immediately before the single
# seed-score scope addition. Historical checker predecessor hashes stay fixed.
FROZEN_SEED_SCORE_PUBLIC_AST = 'f92febc4a765ea8133d2b3159df230e9d5cde658440312a21b588e5e2cb62439'
FROZEN_PUBLIC_ADMISSION_FACTORY_AST = 'e61c4d146f3a64555fb1ff7062bd019619a333687cd98a396a417ec3a2e4b404'


def _seed_score_admission_predecessor(node):
    """Remove only one exact scope after the unchanged ownership precheck."""
    node = copy.deepcopy(node)
    def checked(condition, detail):
        if not condition:
            raise AssertionError('unreviewed seed score admission ' + detail)
    checked(node.name == 'verify_score' and len(node.body) == 4
            and isinstance(node.body[3], ast.With), 'scope position')
    scope = node.body[3]
    expected = ast.parse(
        'with _typed_source.typed_admission_scope(root) as _typed_admission:\n    pass').body[0]
    checked(len(scope.items) == 1 and ast_key(scope.items[0]) == ast_key(expected.items[0])
            and scope.type_comment is None and len(scope.body) == 25, 'scope shape')
    # Keep the actual 3 prefix and 25 body nodes. The hash authenticates every
    # predicate, observation, argument, and final equality/return in order.
    node.body = node.body[:3] + scope.body
    checked(hashlib.sha256(ast_key(node).encode()).hexdigest() == FROZEN_SEED_SCORE_PUBLIC_AST,
            'preserved body')
    return node


def _inventory_admission_entries_predecessor(entries):
    """Invert only the exact two newly reviewed inventory entry pairs."""
    expected = ast.parse("def _public_admission_entries():\n"
        "    return {'cache_key_contracts.py': ('verify',),\n"
        "            'rounded_line_selector_contracts.py': ('verify_premises',),\n"
        "            'seed_count_contracts.py': ('verify_score',),\n"
        "            'sum2_guard_contracts.py': ('verify',),\n"
        "            'lane_order_contracts.py': ('verify',)}").body[0]
    if ast_key(entries) != ast_key(expected):
        raise AssertionError('unreviewed seed admission factory inventory entry transition')
    prior = copy.deepcopy(entries)
    prior.body[0].value.keys = prior.body[0].value.keys[:-2]
    prior.body[0].value.values = prior.body[0].value.values[:-2]
    return prior


def _seed_admission_factory_predecessor(node, entries):
    """Authenticate the single seed entry and its exact existing-parent guard."""
    node = copy.deepcopy(node)
    def checked(condition, detail):
        if not condition:
            raise AssertionError('unreviewed seed admission factory ' + detail)
    expected_entries = ast.parse("def _public_admission_entries():\n"
        "    return {'cache_key_contracts.py': ('verify',),\n"
        "            'rounded_line_selector_contracts.py': ('verify_premises',),\n"
        "            'seed_count_contracts.py': ('verify_score',)}").body[0]
    entries = _inventory_admission_entries_predecessor(entries)
    checked(ast_key(entries) == ast_key(expected_entries), 'entry set')
    checked(node.name == 'typed_admission_scope' and len(node.body) == 8,
            'body shape')
    expected = ast.parse("if Path(filename).name == 'seed_count_contracts.py':\n"
        "    if frame.f_locals.get('_inputs') is not None:\n"
        "        return nullcontext()\n"
        "    parent = audit._public_admission_for(root)\n"
        "    if parent is not None and parent._state == 'active':\n"
        "        return nullcontext()").body[0]
    checked(ast_key(node.body[6]) == ast_key(expected), 'owned input and parent guard')
    node.body.pop(6)
    checked(hashlib.sha256(ast_key(node).encode()).hexdigest() == FROZEN_PUBLIC_ADMISSION_FACTORY_AST,
            'preserved original factory')
    return node


def _selector_admission_predecessor(node):
    """Invert only the reviewed public scope, ordered split and final-read move."""
    node = copy.deepcopy(node)
    def checked(condition, detail):
        if not condition:
            raise AssertionError('unreviewed selector admission ' + detail)
    def statement(text):
        return ast.parse(text).body[0]
    def same(actual, text):
        return ast_key(actual) == ast_key(statement(text))
    expected = statement('def verify_premises(root, *, _return_current_admission=False, '
                         '_check_complete=False):\n    pass')
    checked(node.name == expected.name and ast_key(node.args) == ast_key(expected.args),
            'signature')
    checked(len(node.body) == 1 and isinstance(node.body[0], ast.With), 'scope count')
    scope = node.body[0]
    wrapper = statement('with _typed_source.typed_admission_scope(root) as _typed_admission:\n    pass')
    checked(len(scope.items) == 1 and ast_key(scope.items[0]) == ast_key(wrapper.items[0])
            and scope.type_comment is None, 'scope factory')
    body = scope.body
    checked(len(body) == 16, 'body shape')
    stage = body[7]
    header = statement('for admission_stage in (True, False):\n    pass')
    checked(isinstance(stage, ast.For) and ast_key(stage.target) == ast_key(header.target)
            and ast_key(stage.iter) == ast_key(header.iter) and not stage.orelse
            and stage.type_comment is None and len(stage.body) == 3, 'stage order')
    imports, declarations, modules = stage.body
    def loop_header(loop, text):
        expected = statement(text)
        checked(isinstance(loop, ast.For) and ast_key(loop.target) == ast_key(expected.target)
                and ast_key(loop.iter) == ast_key(expected.iter) and not loop.orelse
                and loop.type_comment is None, 'preserved loop header')
    loop_header(imports, "for name, expected in old['import_scopes'].items():\n    pass")
    loop_header(declarations, "for item in old['declarations']:\n    pass")
    checked(len(imports.body) > 1 and same(imports.body[0],
            "if (name == 'extensions/carla/lane_refinement.mojo') != admission_stage:\n    continue"),
            'scope partition')
    checked(len(declarations.body) > 2 and same(declarations.body[1],
            'if selected != admission_stage:\n    continue'), 'declaration partition')
    checked(isinstance(modules, ast.If) and ast_key(modules.test) == ast_key(ast.Name(
            id='admission_stage', ctx=ast.Load())) and not modules.orelse
            and len(modules.body) == 2, 'module placement')
    checked(same(body[12], "require(type(_check_complete) is bool, 'invalid complete-selector request')"),
            'complete-request guard')
    checked(same(body[13], "if _check_complete:\n"
            "    require(source.token_sha256(_typed_source.historical_text(root, record['path'], "
            "(root/record['path']).read_text())) == record['after_token_sha256'], "
            "'complete selector successor changed')"), 'complete physical read')
    # Preserve every old predicate and read node. Only the two new partition
    # guards and exactly authenticated scope/final-read machinery are removed.
    imports.body = imports.body[1:]
    declarations.body = declarations.body[:1] + declarations.body[2:]
    node.body = body[:6] + modules.body + [body[6], imports, declarations] + body[8:12] + body[14:]
    node.args.kwonlyargs.pop()
    node.args.kw_defaults.pop()
    return node


def _selector_complete_dispatch(node):
    """Require both public routes to request the moved final physical read."""
    def checked(condition):
        if not condition:
            raise AssertionError('unreviewed selector complete-read dispatch')
    def statement(text):
        return ast.parse(text).body[0]
    checked(node.name in ('_verify', '_verify_for_pin_pair') and len(node.body) >= 3)
    body = node.body
    if node.name == '_verify_for_pin_pair':
        checked(isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant)
                and body[0].value.value == "Report only this completed selector execution's admission branch.")
        body = body[1:]
    checked(ast_key(body[0]) == ast_key(statement('if _operation is not None:\n'
            '    full_audit._operation_check(_operation, root)')))
    if node.name == '_verify':
        expected = 'if _operation is None:\n    return verify_premises(root, _check_complete=True)'
        checked(ast_key(body[2]) == ast_key(statement(
            'record = _verify_premises(root, _operation=_operation)')))
    else:
        expected = ('if _operation is None:\n'
            '    return verify_premises(root, _return_current_admission=True, _check_complete=True)\n'
            'else:\n'
            '    record, observed_current_admission = _verify_premises(\n'
            '        root, _return_current_admission=True, _operation=_operation)')
    checked(ast_key(body[1]) == ast_key(statement(expected)))


def _generated_owner_predecessor_ast(node):
    """Remove only the closed generated-receipt additions for old AST controls."""
    def encode(value):
        if isinstance(value, ast.AST):
            return [type(value).__name__, [[name, encode(getattr(value, name))]
                    for name in value._fields]]
        if isinstance(value, list):
            return [encode(item) for item in value]
        if value is None or type(value) in (str, int, float, bool):
            return value
        raise AssertionError('unlisted AST primitive')
    def digest(value):
        return hashlib.sha256(json.dumps(encode(value), separators=(',', ':')).encode()).hexdigest()
    value = copy.deepcopy(node)
    if value.name == '_operation_frame_kind':
        # Authenticate the exact three-line standalone seed dispatch before
        # projecting the older generated-receipt prefix.  No general filter.
        seed_added = ast.Module(body=value.body[5:7], type_ignores=[])
        if digest(seed_added) != '2f250b6e96bc5eaa2f8ba7203a4ae4332476943c87da8a7ad4edc31e92f1dece':
            raise AssertionError('standalone seed classifier prefix drift')
        del value.body[5:7]
        if digest(value) != '383bea3ac7016ef793cfba965036f797cf476e3f3c49ad46a53d43303e7655da':
            raise AssertionError('complete pre-seed classifier drift')
        added = ast.Module(body=value.body[3:5], type_ignores=[])
        expected_added = 'b3c572a1c5dccb0e8908cee741858ce949562c672493138d1837fd98227005bd'
        expected_original = '0b561ce9a6c15077e8d5e819a45a0e3b9971b40ba512f9f15cd6e8eac846fa42'
        if digest(added) != expected_added:
            raise AssertionError('generated receipt classifier prefix drift')
        del value.body[3:5]
    elif value.name == '_private_operation_wrapper':
        expected_added = '1623332651b0d80825ba70f4bbba310dcca6a2caf06006187a5493c332c52d2d'
        expected_original = '9d9920a63c1f4e8dd194fd71630aea08d25b9a5b45d22a8fc761774a365eccb2'
        if digest(value.body[1]) != expected_added:
            raise AssertionError('generated receipt private wrapper drift')
        del value.body[1]
    else:
        raise AssertionError('unlisted generated owner projection')
    if digest(value) != expected_original:
        raise AssertionError('complete pre-receipt owner function drift')
    return value


# Complete, explicitly reviewed wrappers. Values inside _observe_* remain the
# actual physical read objects; the provenance view is only their outer call.
_TYPED_ADAPTER_CALLS = {'verify_premises': ("_typed_source.historical_text(root, root / item['path'], (root / "
                     "item['path']).read_text())",
                     '_typed_source.historical_text(root, root / name, (root / name).read_text())',
                     '_typed_source.historical_text(root, root / name, (root / name).read_text())',
                     '_typed_source.historical_text(root, root / path, (root / path).read_text())',
                     '_typed_source.historical_text(root, name, text)',
                     "_typed_source.historical_text(root, root / item['path'], (root / "
                     "item['path']).read_text())",
                     '_typed_source.historical_bytes(root, root / prior.MIGRATION, (root / '
                     'prior.MIGRATION).read_bytes())'),
 '_verify_premises': ("_typed_source.historical_text(root, item['path'], full_audit._observe_text(root, "
                      "item['path'], (root / item['path']).read_text(), _operation=_operation), "
                      '_operation=_operation)',
                      '_typed_source.historical_text(root, name, full_audit._observe_text(root, name, (root '
                      '/ name).read_text(), _operation=_operation), _operation=_operation)',
                      '_typed_source.historical_text(root, name, full_audit._observe_text(root, name, (root '
                      '/ name).read_text(), _operation=_operation), _operation=_operation)',
                      '_typed_source.historical_text(root, path, full_audit._observe_text(root, path, (root '
                      '/ path).read_text(), _operation=_operation), _operation=_operation)',
                      '_typed_source.historical_text(root, name, text, _operation=_operation)',
                      "_typed_source.historical_text(root, item['path'], full_audit._observe_text(root, "
                      "item['path'], (root / item['path']).read_text(), _operation=_operation), "
                      '_operation=_operation)',
                      '_typed_source.historical_bytes(root, root / prior.MIGRATION, (root / '
                      'prior.MIGRATION).read_bytes(), _operation=_operation)'),
 'predecessor_pin_pair': ("_typed_source.historical_bytes(root, root / 'tools/carla_lane_oracle' / "
                          "runtime_name, (root / 'tools/carla_lane_oracle' / runtime_name).read_bytes())",
                          "_typed_source.historical_bytes(root, root / 'tools/carla_lane_oracle' / "
                          "guard_name, (root / 'tools/carla_lane_oracle' / guard_name).read_bytes())"),
 '_predecessor_pin_pair': ("_typed_source.historical_bytes(root, root / 'tools/carla_lane_oracle' / "
                           "runtime_name, (root / 'tools/carla_lane_oracle' / runtime_name).read_bytes(), "
                           '_operation=_operation)',
                           "_typed_source.historical_bytes(root, root / 'tools/carla_lane_oracle' / "
                           "guard_name, (root / 'tools/carla_lane_oracle' / guard_name).read_bytes(), "
                           '_operation=_operation)')}


def typed_adapter_predecessor(node):
    """Remove exact public admission and #333 provenance adapters only."""
    node = (_selector_admission_predecessor(node) if node.name == 'verify_premises'
            else copy.deepcopy(node))
    expected = Counter(_TYPED_ADAPTER_CALLS[node.name])
    calls, removed = [], []
    assignment = ast.parse('text = _typed_source.historical_text(root, name, text'
        + (', _operation=_operation)' if node.name.startswith('_') else ')')).body[0]
    matches = [(parent, field, index) for parent in ast.walk(node)
               for field, values in ast.iter_fields(parent) if isinstance(values, list)
               for index, value in enumerate(values) if isinstance(value, ast.Assign)
               and ast_key(value) == ast_key(assignment)]
    if 'verify_premises' in node.name:
        if len(matches) != 1:
            raise AssertionError('one typed captured-reread projection required')
        parent, field, index = matches[0]
        statements = getattr(parent, field)
        compare = ast.parse("require(source.token_sha256(supplied) == source.token_sha256(text), "
                            "'consumer source text/bytes disagree: ' + name)").body[0]
        if field != 'body' or index != len(statements) - 1 or index == 0 or ast_key(statements[index - 1]) != ast_key(compare):
            raise AssertionError('typed projection must follow the physical reread comparison')
    elif matches:
        raise AssertionError('unreviewed typed reread projection')
    class Project(ast.NodeTransformer):
        def visit_Assign(self, item):
            if ast_key(item) == ast_key(assignment):
                removed.append(ast.unparse(item.value))
                return None
            return self.generic_visit(item)
        def visit_Call(self, item):
            if (isinstance(item.func, ast.Attribute) and isinstance(item.func.value, ast.Name)
                    and item.func.value.id == '_typed_source'):
                text = ast.unparse(item)
                if text not in expected:
                    raise AssertionError(('unreviewed typed adapter', text))
                calls.append(text)
                return self.visit(item.args[2])
            return self.generic_visit(item)
    result = Project().visit(node)
    if Counter(calls + removed) != expected:
        raise AssertionError('missing or extra typed adapter')
    if len(removed) != (1 if 'verify_premises' in node.name else 0):
        raise AssertionError('typed reread projection moved or changed')
    return result


class PrivateCloneProjection(ast.NodeTransformer):
    """Remove only enumerated operation plumbing; retain all proof semantics."""
    def __init__(self, kind):
        self.kind = kind
        self.calls = []
        self.removed = Counter()
        check = ('full_audit._operation_check(_operation, root)' if kind == 'selector'
                 else '_check_operation(root, _operation)')
        self.entry = ast_key(ast.parse('if _operation is not None:\n    ' + check).body[0])
        self.fallback = ast_key(ast.parse('if _operation is None:\n    return predecessor_pin_pair(root)').body[0])
        self.arguments = ast_key(ast.parse("operation_args = {} if _operation is None else {'_operation': _operation}").body[0])

    def visit_If(self, node):
        if ast_key(node) == self.entry:
            self.removed['entry'] += 1
            return None
        if self.kind == 'pair' and ast_key(node) == self.fallback:
            self.removed['fallback'] += 1
            return None
        return self.generic_visit(node)

    def visit_Assign(self, node):
        if self.kind == 'selector' and ast_key(node) == self.arguments:
            self.removed['arguments'] += 1
            return None
        return self.generic_visit(node)

    def visit_Call(self, node):
        relevant = any(keyword.arg == '_operation' or (
            keyword.arg is None and isinstance(keyword.value, ast.Name)
            and keyword.value.id == 'operation_args') for keyword in node.keywords)
        if relevant:
            self.calls.append(ast.unparse(node))
        node = self.generic_visit(node)
        if relevant:
            if isinstance(node.func, ast.Attribute) and node.func.attr in ('_observe_text', '_observe_bytes'):
                return node.args[2]
            node.keywords = [keyword for keyword in node.keywords if keyword.arg != '_operation'
                            and not (keyword.arg is None and isinstance(keyword.value, ast.Name)
                                     and keyword.value.id == 'operation_args')]
        return node


class OperationAdapterAstControls(unittest.TestCase):
    """Frozen public contracts and narrow, fail-on-drift private-copy controls."""
    def assert_clone(self, kind, private=None):
        module, name = ((selector, 'verify_premises') if kind == 'selector'
                        else (accepted, 'predecessor_pin_pair'))
        original = typed_adapter_predecessor(function_ast(module, name))
        private = typed_adapter_predecessor(private if private is not None else function_ast(module, '_' + name))
        self.assertEqual(private.name, '_' + name)
        self.assertEqual(private.args.kwonlyargs[-1].arg, '_operation')
        self.assertEqual(ast_key(private.args.kw_defaults[-1]), 'Constant(value=None)')
        private.name = name
        private.args.kwonlyargs.pop()
        private.args.kw_defaults.pop()
        projection = PrivateCloneProjection(kind)
        self.assertEqual(ast_key(private.body[1]), projection.entry)
        self.assertEqual(ast_key(private.body[2]),
                         projection.arguments if kind == 'selector' else projection.fallback)
        normalized = projection.visit(private)
        self.assertEqual(Counter(projection.calls), Counter(SELECTOR_PLUMBING if kind == 'selector' else PAIR_PLUMBING))
        self.assertEqual(projection.removed, Counter(entry=1, **({'arguments': 1} if kind == 'selector' else {'fallback': 1})))
        self.assertEqual(ast_key(normalized), ast_key(original))

    def test_original_public_ast_and_root_only_signatures_stay_frozen(self):
        for module, name, expected in ((selector, 'verify_premises', FROZEN_SELECTOR_AST),
                                      (accepted, 'predecessor_pin_pair', FROZEN_PAIR_AST)):
            with self.subTest(function=name):
                self.assertEqual(hashlib.sha256(ast_key(typed_adapter_predecessor(function_ast(module, name))).encode()).hexdigest(), expected)
        for function in (accepted.predecessor_pin_pair, followup.predecessor_pin_pair,
                         invariant.predecessor_pin_pair, accepted.verify_current, selector.verify):
            self.assertEqual(tuple(inspect.signature(function).parameters), ('root',))
        self.assertEqual(tuple(inspect.signature(selector.verify_premises).parameters),
                         ('root', '_return_current_admission', '_check_complete'))

    def test_private_copies_preserve_original_predicates_constants_and_order(self):
        for kind in ('selector', 'pair'):
            with self.subTest(kind=kind):
                self.assert_clone(kind)

    def test_public_selector_admission_inverse_rejects_new_shape_drift(self):
        node = function_ast(selector, 'verify_premises')
        current = ast.unparse(node)
        changes = (
            ('_check_complete=False', '_check_complete=True'),
            ('_check_complete=False', '_check_complete=False, _extra=False'),
            ('_typed_source.typed_admission_scope(root)', '_typed_source.other_scope(root)'),
            ('as _typed_admission:', 'as _other_admission:'),
            ('for admission_stage in (True, False):', 'for admission_stage in (False, True):'),
            ("if (name == 'extensions/carla/lane_refinement.mojo') != admission_stage:",
             "if (name == 'extensions/carla/lane_refinement.mojo') == admission_stage:"),
            ('if selected != admission_stage:', 'if selected == admission_stage:'),
            ('if admission_stage:', 'if not admission_stage:'),
            ('type(_check_complete) is bool', 'type(_check_complete) is int'),
            ('if _check_complete:', 'if not _check_complete:'),
            ("(root / record['path']).read_text()", "record['after_source']"),
            ("== record['after_token_sha256']", "!= record['after_token_sha256']"),
        )
        for before, after in changes:
            with self.subTest(shape=before):
                self.assertEqual(current.count(before), 1)
                changed = ast.parse(current.replace(before, after, 1)).body[0]
                with self.assertRaisesRegex(AssertionError, 'unreviewed selector admission'):
                    _selector_admission_predecessor(changed)
        # Removing both the scope and its added keyword must not fall back to
        # accepting the old node as though the new ownership guard were optional.
        with self.assertRaisesRegex(AssertionError, 'unreviewed selector admission'):
            _selector_admission_predecessor(_selector_admission_predecessor(node))
        # Reconstruct actual old nodes, rather than substituting a known answer.
        for before, after in (
                ("guard.significant(record['before_source'])", "guard.significant(record['after_source'])"),
                ("== guard.significant(record['after_source'])", "!= guard.significant(record['after_source'])"),
                ("words.verify_dependency(name, actual, item['token_sha256'])", 'pass'),
                ('guard.significant(actual) == guard.significant(expected)',
                 'guard.significant(actual) != guard.significant(expected)'),
                ('selected and lane_predecessor is not None', 'selected or lane_predecessor is not None'),
                ('raw = physical.read_bytes()', 'raw = bytes()')):
            with self.subTest(preserved=before):
                self.assertEqual(current.count(before), 1)
                changed = ast.parse(current.replace(before, after, 1)).body[0]
                original = typed_adapter_predecessor(changed)
                self.assertNotEqual(hashlib.sha256(ast_key(original).encode()).hexdigest(),
                                    FROZEN_SELECTOR_AST)

    def test_public_selector_dispatch_requires_complete_physical_read(self):
        for name in ('_verify', '_verify_for_pin_pair'):
            node = function_ast(selector, name)
            _selector_complete_dispatch(node)
            call = next(item for item in ast.walk(node) if isinstance(item, ast.Call)
                        and isinstance(item.func, ast.Name) and item.func.id == 'verify_premises')
            flags = tuple(keyword.arg for keyword in call.keywords)
            for flag in flags:
                for action in ('false', 'missing'):
                    with self.subTest(route=name, flag=flag, mutation=action):
                        changed = copy.deepcopy(node)
                        current = next(item for item in ast.walk(changed) if isinstance(item, ast.Call)
                            and isinstance(item.func, ast.Name) and item.func.id == 'verify_premises')
                        keyword = next(item for item in current.keywords if item.arg == flag)
                        if action == 'false':
                            keyword.value = ast.Constant(value=False)
                        else:
                            current.keywords.remove(keyword)
                        with self.assertRaisesRegex(AssertionError, 'unreviewed selector complete-read dispatch'):
                            _selector_complete_dispatch(changed)

    def test_projection_rejects_semantic_and_observation_drift(self):
        for kind, module, name in (('selector', selector, '_verify_premises'),
                                   ('pair', accepted, '_predecessor_pin_pair')):
            for mutation in ('predicate', 'message', 'statement_order', 'entry_placement', 'observation_target'):
                altered = function_ast(module, name)
                calls = [node for node in ast.walk(altered) if isinstance(node, ast.Call)]
                proof = next(node for node in calls if isinstance(node.func, ast.Name) and node.func.id == 'require')
                if mutation == 'predicate':
                    proof.args[0] = ast.Constant(True)
                elif mutation == 'message':
                    proof.args[1] = ast.Constant('unreviewed replacement')
                elif mutation == 'statement_order':
                    altered.body[-1], altered.body[-2] = altered.body[-2], altered.body[-1]
                elif mutation == 'entry_placement':
                    altered.body[1], altered.body[3] = altered.body[3], altered.body[1]
                else:
                    observed = next(node for node in calls if any(keyword.arg == '_operation' for keyword in node.keywords))
                    observed.args[0] = ast.Name(id='foreign_root', ctx=ast.Load())
                with self.subTest(kind=kind, mutation=mutation), self.assertRaises(AssertionError):
                    self.assert_clone(kind, altered)


class SeedScoreAdmissionAstControls(unittest.TestCase):
    """Exact one-entry wrapper correspondence, separate from real admission."""

    @staticmethod
    def score_node():
        path = Path(source.__file__).with_name('seed_count_contracts.py')
        return next(node for node in ast.parse(path.read_text()).body
                    if isinstance(node, ast.FunctionDef) and node.name == 'verify_score')

    def test_seed_score_scope_preserves_all_existing_body_nodes(self):
        prior = _seed_score_admission_predecessor(self.score_node())
        self.assertEqual(len(prior.body), 28)
        self.assertEqual(hashlib.sha256(ast_key(prior).encode()).hexdigest(),
                         FROZEN_SEED_SCORE_PUBLIC_AST)
        # The ownership precheck precedes entry; final observation and equality
        # stay inside the one scope, before its return and success sweep.
        self.assertEqual(ast.unparse(prior.body[2]).split('(')[0], '_check_inputs')
        self.assertEqual(prior.body[20].targets[0].id, 'final_raw')
        self.assertEqual(ast.unparse(prior.body[21].value.args[0]), 'final_raw == current_raw')
        self.assertIsInstance(prior.body[-1], ast.Return)

    def test_seed_score_scope_rejects_guard_read_and_return_drift(self):
        for fault in ('missing scope', 'factory', 'root', 'binding', 'early entry',
                      'initial read', 'final read', 'expected raw', 'final equality',
                      'predicate order', 'outside final read', 'outside return', 'signature'):
            node = self.score_node()
            scope = node.body[3]
            assignments = {item.targets[0].id: item for item in scope.body
                if isinstance(item, ast.Assign) and isinstance(item.targets[0], ast.Name)}
            if fault == 'missing scope': node.body = node.body[:3] + scope.body
            elif fault == 'factory': scope.items[0].context_expr.func.attr = 'other_scope'
            elif fault == 'root': scope.items[0].context_expr.args[0] = ast.Name(id='other', ctx=ast.Load())
            elif fault == 'binding': scope.items[0].optional_vars.id = '_other_admission'
            elif fault == 'early entry': node.body[2], node.body[3] = node.body[3], node.body[2]
            elif fault == 'initial read': assignments['current_raw'].value = ast.Constant(value=b'')
            elif fault == 'final read': assignments['final_raw'].value = ast.Name(id='current_raw', ctx=ast.Load())
            elif fault == 'expected raw': scope.body[2].body[0].value.args[0] = ast.Constant(value=True)
            elif fault == 'final equality': scope.body[18].value.args[0] = ast.Constant(value=True)
            elif fault == 'predicate order': scope.body[10], scope.body[11] = scope.body[11], scope.body[10]
            elif fault == 'outside final read':
                item = assignments['final_raw']; scope.body.remove(item); node.body.append(item)
            elif fault == 'outside return': node.body.append(scope.body.pop())
            else: node.args.kw_defaults[-1] = ast.Constant(value=b'')
            with self.subTest(fault=fault), self.assertRaisesRegex(AssertionError, 'unreviewed seed score admission'):
                _seed_score_admission_predecessor(node)

    def test_inventory_entry_transition_is_exact_and_preserves_old_three(self):
        entries = function_ast(cleanup, '_public_admission_entries')
        prior = _inventory_admission_entries_predecessor(entries)
        self.assertEqual([key.value for key in prior.body[0].value.keys],
                         ['cache_key_contracts.py', 'rounded_line_selector_contracts.py',
                          'seed_count_contracts.py'])
        for fault in ('missing', 'renamed', 'different method', 'swapped', 'extra statement'):
            altered = copy.deepcopy(entries)
            pairs = altered.body[0].value
            if fault == 'missing': pairs.keys.pop(); pairs.values.pop()
            elif fault == 'renamed': pairs.keys[-1].value = 'other_contracts.py'
            elif fault == 'different method': pairs.values[-1].elts[0].value = 'other'
            elif fault == 'swapped': pairs.keys[-1], pairs.keys[-2] = pairs.keys[-2], pairs.keys[-1]
            else: altered.body.append(ast.Pass())
            with self.subTest(fault=fault), self.assertRaisesRegex(AssertionError, 'inventory entry transition'):
                _inventory_admission_entries_predecessor(altered)

    def test_seed_scope_factory_preserves_owned_paths_and_authenticated_parent_reuse(self):
        node = function_ast(source, 'typed_admission_scope')
        entries = function_ast(cleanup, '_public_admission_entries')
        prior = _seed_admission_factory_predecessor(node, entries)
        self.assertEqual(hashlib.sha256(ast_key(prior).encode()).hexdigest(),
                         FROZEN_PUBLIC_ADMISSION_FACTORY_AST)
        text = ast.unparse(node)
        mutations = (
            ("frame.f_locals.get('_operation') is not None", "frame.f_locals.get('_operation') is None"),
            ("frame.f_locals.get('_inputs') is not None", "frame.f_locals.get('_inputs') is None"),
            ("Path(filename).name == 'seed_count_contracts.py'", 'True'),
            ('audit._public_admission_for(root)', 'audit._public_admission_for(other)'),
            ('parent is not None and', 'parent is not None or'),
            ("parent._state == 'active'", "parent._state == 'pending'"),
            ('return audit._public_admission_scope(root, frame)', 'return nullcontext()'),
        )
        for before, after in mutations:
            with self.subTest(fault=before):
                self.assertEqual(text.count(before), 1)
                changed = ast.parse(text.replace(before, after, 1)).body[0]
                with self.assertRaisesRegex(AssertionError, 'unreviewed seed admission factory'):
                    _seed_admission_factory_predecessor(changed, entries)
        for fault in ('missing owned guard', 'missing parent guard', 'extra entry', 'different entry'):
            changed, altered = copy.deepcopy(node), copy.deepcopy(entries)
            if fault == 'missing owned guard': changed.body[6].body.pop(0)
            elif fault == 'missing parent guard': changed.body[6].body.pop()
            elif fault == 'extra entry':
                altered.body[0].value.keys.append(ast.Constant(value='sum2_guard_contracts.py'))
                altered.body[0].value.values.append(ast.Tuple(elts=[ast.Constant(value='verify')], ctx=ast.Load()))
            else:
                seed = next(index for index, key in enumerate(altered.body[0].value.keys)
                            if key.value == 'seed_count_contracts.py')
                altered.body[0].value.values[seed].elts[0].value = 'verify'
            with self.subTest(fault=fault), self.assertRaisesRegex(AssertionError, 'unreviewed seed admission factory'):
                _seed_admission_factory_predecessor(changed, altered)


class OperationAdapterFakeFrameControls(unittest.TestCase):
    """Small synthetic owner/image wiring only; never real admission evidence."""
    @contextmanager
    def fake_image(self, root, raw_by_path):
        operation = object()
        def check(candidate, actual_root):
            self.assertIs(candidate, operation)
            self.assertEqual(actual_root, root)
        def observe(candidate, actual_root, path, value, mode):
            if candidate is None:
                return value
            check(candidate, actual_root)
            raw = raw_by_path[str(path)]
            expected = raw if mode == 'bytes' else cleanup._operation_text(raw, mode)
            matched = (type(value) is type(expected) and (
                source.token_sha256(value) == source.token_sha256(expected)
                if mode.startswith('supplied_') else value == expected))
            cleanup.require(matched, 'synthetic observation mismatch: ' + str(path))
            return value
        with patch.object(cleanup, '_operation_check', check), patch.object(cleanup, '_operation_observe', observe):
            yield operation

    @contextmanager
    def selector_fixture(self):
        # macOS temporary roots can have a symbolic /var ancestor. Normalize
        # only the fixture's parent; production must still reject aliased input.
        with tempfile.TemporaryDirectory(
                prefix='invariant-selector-fake-', dir=Path(tempfile.gettempdir()).resolve()) as directory:
            root = Path(directory)
            raw = {'selector.mojo': b'fake', 'reference.mojo': b'fake',
                   selector.prior.MIGRATION: b'fake', LANE: b'current scope', ROAD: b'road source'}
            for name, payload in raw.items():
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(payload)
            record = {'path': 'selector.mojo', 'before_source': 'fake', 'after_source': 'fake',
                      'after_token_sha256': source.token_sha256('fake'),
                      'prior_migration_sha256': hashlib.sha256(b'fake').hexdigest(),
                      'reference': {'path': 'reference.mojo', 'name': 'reference', 'source': 'fake'}}
            old = {'modules': {'selector.mojo': {'source': 'fake'}},
                   'import_scopes': {LANE: 'old scope'},
                   'declarations': [{'path': path, 'name': name, 'owner': [], 'source': 'fake'}
                                    for path, name in ((LANE, '_rounded_axis_lane_minimum'),
                                                       (LANE, '_refine_lane_certificate'), (ROAD, '_road_reference'))]}
            interpreted = []
            def declaration(text, name, owner):
                interpreted.append(text)
                return 'fake'
            with patch.object(selector, 'read_record', side_effect=lambda root: copy.deepcopy(record)), \
                    patch.object(selector.prior, 'read_record', side_effect=lambda root: copy.deepcopy(old)), \
                    patch.object(cleanup, '_reviewed_lane_observation', return_value=('old scope', raw[ROAD])), \
                    patch.object(guard, 'declaration', declaration):
                yield root, raw, record, interpreted

    def test_selector_fixture_under_symbolic_temp_root_keeps_controls(self):
        with tempfile.TemporaryDirectory(
                prefix='invariant-selector-temp-alias-', dir=Path(tempfile.gettempdir()).resolve()) as directory:
            parent = Path(directory)
            physical = parent/'physical'
            physical.mkdir()
            symbolic = parent/'symbolic'
            symbolic.symlink_to(physical, target_is_directory=True)
            with patch.object(tempfile, 'tempdir', str(symbolic)):
                self.assertEqual(Path(tempfile.gettempdir()), symbolic)
                for control in (
                        self.test_private_selector_positive_result_and_physical_read_order_match_public,
                        self.test_private_selector_consumed_b_stops_before_declaration,
                        self.test_private_selector_supplied_comments_keep_token_equivalence):
                    with self.subTest(control=control.__name__):
                        control()
                        self.assertEqual(list(physical.iterdir()), [])
                with self.selector_fixture() as (root, raw, record, interpreted):
                    self.assertEqual(root.parent, physical)
                    self.assertEqual(root, root.resolve())
                    self.assertEqual(cleanup._regular(root, LANE).read_bytes(), raw[LANE])
                    with self.assertRaisesRegex(cleanup.ContractError, 'symbolic root or ancestor'):
                        cleanup._regular(symbolic/root.name, LANE)
                    for kind in ('root', 'ancestor', 'leaf'):
                        message = 'symbolic root or ancestor' if kind == 'root' else 'symlink input'
                        with self.subTest(alias=kind), paired_helpers.alias(root, LANE, kind):
                            with self.assertRaisesRegex(cleanup.ContractError, message):
                                cleanup._regular(root, LANE)
                        self.assertEqual(cleanup._regular(root, LANE).read_bytes(), raw[LANE])
                self.assertFalse(root.exists())
                self.assertEqual(list(physical.iterdir()), [])

    def test_private_selector_positive_result_and_physical_read_order_match_public(self):
        from contextlib import nullcontext
        from types import SimpleNamespace
        # This tiny fixture checks adapter parity, not real admission. Replace
        # only this selector's scope transport; retain both provenance helpers.
        typed_source = SimpleNamespace(
            historical_text=selector._typed_source.historical_text,
            historical_bytes=selector._typed_source.historical_bytes,
            typed_admission_scope=lambda root: nullcontext())
        with self.selector_fixture() as (root, raw, record, interpreted), \
                self.fake_image(root, raw) as operation, patch.object(selector, '_typed_source', typed_source):
            traces = []
            original_text, original_bytes = Path.read_text, Path.read_bytes
            for private in (False, True):
                events = []
                def text(path, *args, **kwargs):
                    events.append(('text', path.relative_to(root).as_posix()))
                    return original_text(path, *args, **kwargs)
                def binary(path, *args, **kwargs):
                    events.append(('bytes', path.relative_to(root).as_posix()))
                    return original_bytes(path, *args, **kwargs)
                with patch.object(Path, 'read_text', text), patch.object(Path, 'read_bytes', binary):
                    result = (selector._verify_premises(root, _return_current_admission=True, _operation=operation)
                              if private else selector.verify_premises(root, _return_current_admission=True))
                self.assertEqual(result, (record, True))
                traces.append(events)
            # Public admission checks the lane before the selector; the private
            # adapter keeps the frozen predecessor order. Only this prefix moves.
            suffix = [
                ('bytes', LANE), ('text', LANE),
                ('bytes', ROAD), ('text', ROAD), ('text', 'reference.mojo'),
                ('bytes', LANE), ('bytes', ROAD)]
            self.assertEqual(traces[0], [
                ('bytes', selector.prior.MIGRATION), ('text', LANE),
                ('bytes', LANE), ('text', 'selector.mojo')] + suffix)
            self.assertEqual(traces[1], [
                ('bytes', selector.prior.MIGRATION), ('text', 'selector.mojo'),
                ('text', LANE), ('bytes', LANE)] + suffix)
            self.assertEqual(traces[0].count(('bytes', LANE)), 3)
            self.assertEqual(traces[0].count(('bytes', ROAD)), 2)

    def test_private_selector_consumed_b_stops_before_declaration(self):
        cases = [('text', 'selector.mojo', selector._verify_premises, 1),
                 ('text', 'reference.mojo', selector._verify_premises, 1),
                 ('bytes', LANE, selector._lane_observation, 1),
                 ('text', LANE, selector._lane_observation, 1)]
        cases += [(mode, name, selector._verify_premises, occurrence)
                  for name in (LANE, ROAD) for mode, occurrence in (('bytes', 1), ('bytes', 2), ('text', 1))]
        for mode, name, frame, occurrence in cases:
            with self.subTest(mode=mode, path=name, frame=frame.__name__, occurrence=occurrence), \
                    self.selector_fixture() as (root, raw, record, interpreted), self.fake_image(root, raw) as operation:
                original = getattr(Path, 'read_' + mode)
                visits = []
                marker = '\ndef unreviewed_private_observation():\n    pass\n'
                def changed(path, *args, **kwargs):
                    value = original(path, *args, **kwargs)
                    if path == root/name and sys._getframe(1).f_code is frame.__code__:
                        visits.append(name)
                        if len(visits) == occurrence:
                            return value + (marker.encode() if mode == 'bytes' else marker)
                    return value
                with patch.object(Path, 'read_' + mode, changed):
                    with self.assertRaisesRegex(ValueError, 'synthetic observation mismatch|checked physical and supplied views differ'):
                        selector._verify_premises(root, _operation=operation)
                self.assertEqual(len(visits), occurrence)
                self.assertFalse(any('unreviewed_private_observation' in text for text in interpreted))
                self.assertEqual((root/name).read_bytes(), raw[name])

    def test_private_selector_supplied_comments_keep_token_equivalence(self):
        with self.selector_fixture() as (root, raw, record, interpreted), self.fake_image(root, raw) as operation:
            original = Path.read_text
            visits = []
            def commented(path, *args, **kwargs):
                text = original(path, *args, **kwargs)
                if path == root/LANE and sys._getframe(1).f_code is selector._lane_observation.__code__:
                    visits.append(LANE)
                    return '# Token-equivalent supplied view.\n' + text
                return text
            with patch.object(Path, 'read_text', commented):
                self.assertEqual(selector._verify_premises(root, _operation=operation), record)
            self.assertEqual(visits, [LANE])

    def pin_fixture(self):
        fixture = paired_helpers.PairedPinFakeControls('test_fixed_shape_order_signatures_and_single_freshness')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        return fixture

    def test_private_pair_positive_result_and_read_order_match_public(self):
        fixture = self.pin_fixture()
        raw = {paired_helpers.PIN_DIR + '/' + name: payload
               for name, payload in zip(paired_helpers.NAMES, fixture.active)}
        for current in (False, True):
            with self.subTest(current=current), fixture.synthetic(current), self.fake_image(fixture.root, raw) as operation:
                original = Path.read_bytes
                traces = []
                for private in (False, True):
                    events = []
                    def observed(path, *args, **kwargs):
                        events.append(path.relative_to(fixture.root).as_posix())
                        return original(path, *args, **kwargs)
                    with patch.object(Path, 'read_bytes', observed):
                        result = (accepted._predecessor_pin_pair(fixture.root, _operation=operation)
                                  if private else accepted.predecessor_pin_pair(fixture.root))
                    paired_helpers.assert_pair(self, result)
                    self.assertEqual(result, fixture.outputs['accepted'])
                    traces.append(events)
                self.assertEqual(traces[0], traces[1])
                self.assertEqual(len(traces[0]), 4 if current else 2)

    def test_private_pair_consumed_and_final_b_stop_before_json(self):
        fixture = self.pin_fixture()
        raw = {paired_helpers.PIN_DIR + '/' + name: payload
               for name, payload in zip(paired_helpers.NAMES, fixture.active)}
        for current in (False, True):
            frame = accepted._read_current_pair_pin if current else accepted._predecessor_pin_pair
            for name in paired_helpers.NAMES:
                for occurrence in ((1, 2) if current else (1,)):
                    path = paired_helpers.PIN_DIR + '/' + name
                    with self.subTest(current=current, name=name, occurrence=occurrence), \
                            fixture.synthetic(current), self.fake_image(fixture.root, raw) as operation:
                        original, parser = Path.read_bytes, json.loads
                        visits, interpreted = [], []
                        bad = raw[path] + b' '
                        def changed(target, *args, **kwargs):
                            value = original(target, *args, **kwargs)
                            if target == fixture.root/path and sys._getframe(1).f_code is frame.__code__:
                                visits.append(path)
                                if len(visits) == occurrence:
                                    return bad
                            return value
                        def parsed(value, *args, **kwargs):
                            if value == bad:
                                interpreted.append(value)
                            return parser(value, *args, **kwargs)
                        expected_error = ('synthetic observation mismatch' if current
                                          else 'unreviewed runtime pin successor: ' + name)
                        with patch.object(Path, 'read_bytes', changed), patch.object(json, 'loads', parsed):
                            with self.assertRaisesRegex(ValueError, expected_error):
                                accepted._predecessor_pin_pair(fixture.root, _operation=operation)
                        self.assertEqual(len(visits), occurrence)
                        self.assertEqual(interpreted, [])
                        self.assertEqual((fixture.root/path).read_bytes(), raw[path])


class BoundedOwnerCurrentControls(unittest.TestCase):
    """Real gates and public owners over the existing complete physical fixture.

    Wrappers retain their original functions and checks. Faults enter at actual
    consumer reads or after a real admission; none replaces an authority image.
    These controls do not replace the full per-callsite mutation matrix.
    """

    def setUp(self):
        import _full_audit_test_fixtures as fixtures
        self.root = fixtures.copy_current_root(self, Path(__file__).resolve().parents[2])
        marker = 'extensions/carla/polynomial.mojo'
        self.assertTrue(cleanup.typed_boundary.is_current(marker, (self.root/marker).read_bytes()),
                        'current authority controls require the actual typed graph')

    @contextmanager
    def audit(self, core=cleanup, callback=None):
        from contextlib import ExitStack
        from functools import wraps
        events = {'admissions': [], 'finalizers': [], 'records': [],
                  'callbacks': [], 'frames': set()}
        binding, checkpoint, record = (core.executing_checker_bindings,
                                       core._CacheInputs.checkpoint, core._operation_record)
        notified = set()

        @wraps(binding)
        def admitted(*args, **kwargs):
            frame = sys._getframe(1)
            if (frame.f_globals is vars(core) and frame.f_code is core.verify.__code__
                    and 'executing' not in frame.f_locals):
                events['admissions'].append(frame.f_locals['_capture'])
            return binding(*args, **kwargs)

        @wraps(checkpoint)
        def finalized(view, owner, root):
            events['finalizers'].append(view)
            return checkpoint(view, owner, root)

        @wraps(record)
        def projected(operation, root, **kwargs):
            value = record(operation, root, **kwargs)
            events['records'].append(operation)
            frame = sys._getframe(1)
            while frame is not None:
                kind = core._operation_frame_kind(frame)
                if kind is not None:
                    events['frames'].add(kind)
                frame = frame.f_back
            if callback is not None and id(operation) not in notified:
                notified.add(id(operation))
                events['callbacks'].append(operation)
                callback(operation)
            return value

        with ExitStack() as stack:
            stack.enter_context(patch.object(core, 'executing_checker_bindings', admitted))
            stack.enter_context(patch.object(core._CacheInputs, 'checkpoint', finalized))
            stack.enter_context(patch.object(core, '_operation_record', projected))
            yield events

    def coverage(self):
        # Coverage uses its real package namespace. Never alias it to the
        # top-level verifier used by the invariant tests above.
        tools = str(Path(__file__).resolve().parents[1])
        if tools not in sys.path:
            self.addCleanup(sys.path.remove, tools)
            sys.path.insert(0, tools)
        import coverage_loop_proofs as loops
        from carla_lane_oracle import full_audit_cleanup_contracts as core
        return loops, core

    def assert_public_coherence_error(self, error, operation):
        """Require the established accepted-pin public envelope and its cause."""
        self.assertIs(type(error), ValueError)
        self.assertIs(type(error.__cause__), cleanup._OperationCoherenceError)
        self.assertTrue(operation._failed)
        self.assertTrue(operation._failure_reason)
        self.assertEqual(str(error.__cause__), operation._failure_reason)
        self.assertEqual(str(error),
                         'unreviewed complete successor: ' + operation._failure_reason)

    def assert_closed(self, operation, core=cleanup):
        self.assertIs(type(operation), core._InvariantInputs)
        self.assertEqual(operation._state, 'closed')
        self.assertFalse(operation._raw)
        self.assertIsNone(operation._record_raw)
        self.assertIsNone(operation._owner_frame)
        self.assertEqual(operation._observations, [])
        self.assertEqual(operation._discoveries, [])
        self.assertIs(operation._checker_receipt, False)

    def assert_one_owner(self, events, kind, core=cleanup):
        self.assertEqual(len(events['admissions']), 1)
        operation = events['admissions'][0]
        self.assertEqual(operation._kind, kind)
        self.assertEqual(events['finalizers'], [operation])
        self.assertTrue(events['records'])
        self.assertTrue(all(value is operation for value in events['records']))
        self.assert_closed(operation, core)
        return operation

    def test_current_invariant_calls_admit_finalize_and_dispose_independently(self):
        owners = []
        for _ in range(2):
            with self.audit() as events:
                result = invariant.verify(self.root)
            self.assertEqual(len(result['sources']), 4)
            owners.append(self.assert_one_owner(events, 'invariant'))
            self.assertFalse(any(value is owners[-1] for value in vars(invariant).values()))
            self.assertFalse(any(value is owners[-1] for value in vars(cleanup).values()))
        self.assertIsNot(owners[0], owners[1])
        for operation in owners:
            for copier in (copy.copy, copy.deepcopy):
                with self.assertRaises(ValueError):
                    copier(operation)
            with self.assertRaises(cleanup._OperationCoherenceError):
                cleanup._operation_check(operation, self.root)
            operation.close()
            self.assert_closed(operation)

    def test_current_winner_children_borrow_without_finalizing_parent(self):
        import winner_sign_contracts as winner
        import border_parser_contracts as border
        import _full_audit_test_fixtures as fixtures
        with self.audit() as events:
            result = winner.verify(self.root)
        self.assertEqual(result['status'], 'PASS')
        typed = cleanup.typed_boundary
        edges = result['typed_boundary_successors']
        self.assertEqual(set(edges), set(typed.SOURCE_PATHS))
        for path, edge in edges.items():
            self.assertEqual(edge['after_sha256'], hashlib.sha256((self.root/path).read_bytes()).hexdigest())
        canonical = json.loads((self.root/'tools/carla_lane_oracle/winner-sign-query-migration.json').read_bytes())['canonical_source_unchanged']
        self.assertEqual(len(canonical), 112)
        helpers = cleanup.shared_helpers
        self.assertEqual(set(helpers.SOURCE_PATHS) & set(canonical), fixtures.WINNER_SHARED_HELPER_SUCCESSORS)
        self.assertNotIn('loaders/xml.mojo', canonical)
        for path in fixtures.WINNER_SHARED_HELPER_SUCCESSORS:
            self.assertEqual(canonical[path], helpers.BEFORE_SHA256[path])
            raw = (self.root/path).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), helpers.AFTER_SHA256[path])
            before = helpers.predecessor_source(path, raw.decode('utf-8'))
            self.assertEqual(hashlib.sha256(before.encode('utf-8')).hexdigest(), canonical[path])
        prior = fixtures.WINNER_PRE_BORDER_SUCCESSORS | {
            border.MODULE, fixtures.WINNER_FULL_AUDIT_NEW_DEPENDENCY}
        self.assertTrue(prior.isdisjoint(fixtures.WINNER_SHARED_HELPER_SUCCESSORS))
        historical_changed, current_changed = set(), set()
        for path, digest in canonical.items():
            raw = (self.root/path).read_bytes()
            if hashlib.sha256(raw).hexdigest() != digest:
                current_changed.add(path)
            # The current owner has completed before historical reporting is
            # inspected. These views never replace the physical fixture.
            historical = typed.historical_source(path, raw.decode('utf-8')).encode('utf-8')
            if hashlib.sha256(historical).hexdigest() != digest:
                historical_changed.add(path)
        self.assertEqual(historical_changed, prior | fixtures.WINNER_SHARED_HELPER_SUCCESSORS)
        self.assertEqual(current_changed, historical_changed | (set(canonical) & set(typed.SOURCE_PATHS)))
        self.assertEqual((len(prior), len(canonical) - len(prior)), (20, 92))
        self.assertEqual((result['reviewed_cleanup_successors'], result['canonical_dependencies_unchanged']),
                         (len(historical_changed), len(canonical) - len(historical_changed)))
        self.assertEqual(result['map_source_sha256'], hashlib.sha256((self.root/'extensions/carla/map.mojo').read_bytes()).hexdigest())
        self.assert_one_owner(events, 'winner')
        self.assertTrue({'winner', 'invariant', 'border'} <= events['frames'])

    def test_current_decorated_border_has_one_own_lifetime(self):
        import border_parser_contracts as border
        with self.audit() as events:
            result = border.verify(self.root)
        self.assertEqual(result['after_sha256'], border.AFTER_SHA256)
        self.assert_one_owner(events, 'border')

    def test_current_map_and_rtree_never_share_an_image(self):
        loops, core = self.coverage()
        owners = []
        for module, kind in (('extensions/carla/map', 'map_loops'),
                             ('extensions/carla/rtree', 'rtree_loops')):
            with self.subTest(module=module), self.audit(core) as events:
                result = loops.reviewed_nonempty_loops(self.root, module)
            self.assertTrue(result)
            self.assertTrue(all(line == row['line'] for line, row in result.items()))
            owners.append(self.assert_one_owner(events, kind, core))
        self.assertIsNot(owners[0], owners[1])

    def test_current_foreign_root_thread_and_cwd_poison_the_owner(self):
        import os
        from concurrent.futures import ThreadPoolExecutor
        for fault in ('root', 'thread', 'cwd'):
            rejected = []
            def consume(operation):
                with self.assertRaises(cleanup._OperationCoherenceError):
                    if fault == 'root':
                        cleanup._operation_check(operation, self.root/'foreign')
                    elif fault == 'thread':
                        with ThreadPoolExecutor(max_workers=1) as pool:
                            pool.submit(cleanup._operation_check, operation, self.root).result(timeout=5)
                    else:
                        previous = Path.cwd()
                        try:
                            os.chdir(self.root)
                            cleanup._operation_check(operation, self.root)
                        finally:
                            os.chdir(previous)
                rejected.append(fault)
                self.assertTrue(operation._failed)
                self.assertFalse(operation._raw)
                with self.assertRaises(cleanup._OperationCoherenceError):
                    cleanup._operation_check(operation, self.root)
            with self.subTest(fault=fault), self.audit(callback=consume) as events:
                with self.assertRaises(ValueError) as public_error:
                    invariant.verify(self.root)
            self.assertEqual(len(events['admissions']), 1)
            self.assertEqual(events['callbacks'], events['admissions'])
            self.assertEqual(rejected, [fault])
            self.assert_public_coherence_error(public_error.exception, events['admissions'][0])
            self.assert_closed(events['admissions'][0])

    def test_current_primary_exception_closes_without_a_success_finalizer(self):
        failure = RuntimeError('independent consumer failure')
        def consume(operation):
            raise failure
        with self.audit(callback=consume) as events:
            with self.assertRaises(RuntimeError) as caught:
                invariant.verify(self.root)
        self.assertIs(caught.exception, failure)
        self.assertEqual(events['finalizers'], [])
        self.assert_closed(events['admissions'][0])

    def test_current_nested_public_owner_is_fresh_and_blocks_the_outer_handle(self):
        owners = []
        def consume(operation):
            owners.append(operation)
            if len(owners) == 1:
                self.assertEqual(len(invariant.verify(self.root)['sources']), 4)
            else:
                self.assertIsNot(operation, owners[0])
                with self.assertRaisesRegex(cleanup._OperationCoherenceError,
                                            'nearer independent operation'):
                    cleanup._operation_check(owners[0], self.root)
                cleanup._operation_check(operation, self.root)
        with self.audit(callback=consume) as events:
            with self.assertRaises(ValueError) as public_error:
                invariant.verify(self.root)
        self.assertEqual(events['admissions'], owners)
        self.assertEqual(events['finalizers'], [owners[1]])
        self.assert_public_coherence_error(public_error.exception, owners[0])
        for operation in owners:
            self.assert_closed(operation)

    def test_current_direct_and_arbitrary_borrow_routes_refuse(self):
        import border_parser_contracts as border
        import winner_sign_contracts as winner
        for target in ('invariant', 'border', 'arbitrary'):
            rejected = []
            def consume(operation):
                def arbitrary():
                    return invariant.verify(self.root, _operation=operation)
                route = arbitrary if target == 'arbitrary' else lambda: (
                    invariant.verify(self.root, _operation=operation) if target == 'invariant'
                    else border.verify(self.root, _operation=operation))
                with self.assertRaisesRegex(cleanup._OperationCoherenceError, 'exact private wrapper'):
                    route()
                rejected.append(target)
                self.assertTrue(operation._failed)
            with self.subTest(target=target), self.audit(callback=consume) as events:
                with self.assertRaises(cleanup._OperationCoherenceError):
                    winner.verify(self.root)
            self.assertEqual(len(events['admissions']), 1)
            self.assertEqual(events['callbacks'], events['admissions'])
            self.assertEqual(rejected, [target])
            self.assert_closed(events['admissions'][0])

    def test_current_registered_and_unregistered_aliases_block_outer_use(self):
        import importlib.util
        from contextlib import ExitStack
        from functools import wraps
        for registered in (False, True):
            name = '_bounded_invariant_alias_' + str(registered)
            spec = importlib.util.spec_from_file_location(name, invariant.__file__)
            alias = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(alias)
            reached = []
            def consume(operation):
                read_record = alias.read_record
                @wraps(read_record)
                def alias_read(root):
                    frame = sys._getframe(1)
                    self.assertIs(frame.f_globals, vars(alias))
                    self.assertIsNone(frame.f_locals['_operation'])
                    reached.append(True)
                    cleanup._operation_check(operation, root)
                    self.fail('alias frame permitted the outer owner')
                with patch.object(alias, 'read_record', alias_read):
                    with self.assertRaisesRegex(cleanup._OperationCoherenceError,
                                                'nearer independent operation'):
                        alias.verify(self.root)
            with self.subTest(registered=registered), ExitStack() as stack:
                if registered:
                    stack.enter_context(patch.dict(sys.modules, {name: alias}))
                events = stack.enter_context(self.audit(callback=consume))
                with self.assertRaises(ValueError) as public_error:
                    invariant.verify(self.root)
            self.assertEqual(reached, [True])
            self.assert_public_coherence_error(public_error.exception, events['admissions'][0])
            self.assert_closed(events['admissions'][0])

    def test_current_each_exact_demand_rechecks_four_immutable_endpoints(self):
        from functools import wraps
        checked = []
        original = cleanup.sha
        @wraps(original)
        def hashed(raw):
            frame = sys._getframe(1)
            if frame.f_code is cleanup._InvariantInputs._admit.__code__ and frame.f_locals['exact']:
                path = frame.f_locals['path']
                self.assertIs(raw, frame.f_locals['raw'])
                self.assertEqual(raw, (self.root/path).read_bytes())
                self.assertTrue(cleanup.typed_boundary.is_current(path, raw))
                checked.append(path)
            return original(raw)
        def consume(operation):
            with self.assertRaises(TypeError):
                operation._raw[ROAD] = b'changed captured input'
            with patch.object(cleanup, 'sha', hashed):
                first = cleanup.verified_edges(self.root, _operation=operation)
                second = cleanup.verified_edges(self.root, _operation=operation)
            self.assertEqual(Counter(checked), Counter({name: 2 for name in cleanup.SOURCE_PATHS}))
            self.assertEqual(first, second)
            self.assertIsNot(first, second)
            first[LANE]['after_sha256'] = 'changed caller result'
            self.assertEqual(second[LANE]['after_sha256'], cleanup.AFTER_SHA256[LANE])
        with self.audit(callback=consume) as events:
            invariant.verify(self.root)
        self.assert_one_owner(events, 'invariant')

    def test_current_direct_private_misuse_rejects_and_finally_closes(self):
        for fault in ('wrong_token', 'unlisted_path'):
            failure = RuntimeError('stop after rejected private access: ' + fault)
            def consume(operation):
                with self.assertRaises(ValueError):
                    if fault == 'wrong_token':
                        operation.raw(object(), self.root, ROAD)
                    else:
                        operation.raw(operation._owner, self.root, 'unlisted.mojo')
                # Reject this access, then exit. Do not require later reuse or
                # a poison policy for private misuse outside the owned graph.
                raise failure
            with self.subTest(fault=fault), self.audit(callback=consume) as events:
                with self.assertRaises(RuntimeError) as caught:
                    invariant.verify(self.root)
            self.assertIs(caught.exception, failure)
            self.assertEqual(events['finalizers'], [])
            self.assert_closed(events['admissions'][0])

    def test_current_invalid_exact_request_is_sticky_when_caught(self):
        rejected = []
        def consume(operation):
            with self.assertRaisesRegex(cleanup._OperationCoherenceError, 'exactness request'):
                cleanup._operation_record(operation, self.root, exact='yes')
            rejected.append('invalid_exact')
            self.assertTrue(operation._failed)
            self.assertFalse(operation._raw)
            with self.assertRaises(cleanup._OperationCoherenceError):
                cleanup._operation_record(operation, self.root)
        with self.audit(callback=consume) as events:
            with self.assertRaises(ValueError) as public_error:
                invariant.verify(self.root)
        self.assertEqual(len(events['admissions']), 1)
        self.assertEqual(events['callbacks'], events['admissions'])
        self.assertEqual(rejected, ['invalid_exact'])
        self.assert_public_coherence_error(public_error.exception, events['admissions'][0])
        self.assert_closed(events['admissions'][0])

    def test_current_consumed_text_and_bytes_refuse_before_semantic_use(self):
        import winner_sign_contracts as winner
        from functools import wraps
        for mode, module, name in (('text', invariant, LANE), ('bytes', winner, ROAD)):
            read = getattr(Path, 'read_' + mode)
            body = inspect.unwrap(module.verify).__code__
            visits, interpreted = [], []
            marker = '\n# Unreviewed consumed operation bytes.\n'
            token = source.token_sha256
            @wraps(token)
            def interpreted_text(text):
                if marker in text:
                    interpreted.append(text)
                return token(text)
            def changed(path, *args, **kwargs):
                value = read(path, *args, **kwargs)
                frame = sys._getframe(1)
                if (path == self.root/name and frame.f_globals is vars(module)
                        and frame.f_code is body
                        and frame.f_locals.get('_operation') is not None
                        and frame.f_locals['_operation']._state == 'active'):
                    visits.append(name)
                    return value + (marker.encode() if mode == 'bytes' else marker)
                return value
            original = (self.root/name).read_bytes()
            with self.subTest(mode=mode), self.audit() as events, patch.object(
                    Path, 'read_' + mode, changed), patch.object(source, 'token_sha256', interpreted_text):
                with self.assertRaisesRegex(cleanup._OperationCoherenceError, 'consumed operation'):
                    module.verify(self.root)
            self.assertEqual(visits, [name])
            self.assertEqual(interpreted, [])
            self.assertEqual((self.root/name).read_bytes(), original)
            self.assert_closed(events['admissions'][0])

    def test_current_finalizer_rejects_persistent_bytes_and_new_source_census(self):
        from functools import wraps
        finish = cleanup._InvariantInputs.finish
        for fault in ('bytes', 'census'):
            target = self.root/(ROAD if fault == 'bytes' else 'extensions/carla/unreviewed_owner.mojo')
            original = target.read_bytes() if target.exists() else None
            injected = []
            @wraps(finish)
            def finalized(operation, root):
                injected.append(operation)
                target.write_bytes((original or b'') + b'\n# Persistent owner mutation.\n')
                return finish(operation, root)
            try:
                with self.subTest(fault=fault), self.audit() as events, patch.object(
                        cleanup._InvariantInputs, 'finish', finalized):
                    with self.assertRaises(cleanup._OperationCoherenceError):
                        invariant.verify(self.root)
                self.assertEqual(injected, events['admissions'])
                self.assert_closed(injected[0])
            finally:
                if original is None:
                    target.unlink(missing_ok=True)
                else:
                    target.write_bytes(original)

    def test_current_validation_only_transient_change_has_no_extra_sampling(self):
        # Option B permits this only between actual consumers and finalization.
        # The consumed-read test above still rejects B even when disk stays A.
        target = self.root/ROAD
        original = target.read_bytes()
        def consume(operation):
            try:
                target.write_bytes(original + b'\n# Unconsumed transient change.\n')
                with patch.object(Path, 'read_bytes', side_effect=AssertionError('extra image sampling')):
                    operation.checkpoint(operation._owner, self.root)
            finally:
                target.write_bytes(original)
        with self.audit(callback=consume) as events:
            invariant.verify(self.root)
        self.assert_one_owner(events, 'invariant')

    def test_historical_invariant_keeps_lazy_current_admission(self):
        import _full_audit_test_fixtures as fixtures
        from functools import wraps
        self.root = fixtures.copy_historical_boundary_root(self, Path(__file__).resolve().parents[2])
        record = cleanup.read_record(self.root)
        predecessors = {name: cleanup.reverse_exact(name, item['after_source'], item).encode('utf-8')
                        for name, item in record['sources'].items()}
        fixtures.write_predecessors(self.root, predecessors)
        states, owners = [], []
        finish = cleanup._InvariantInputs.finish
        @wraps(finish)
        def finalized(operation, root):
            states.append(operation._state)
            owners.append(operation)
            return finish(operation, root)
        with self.audit() as events, patch.object(cleanup._InvariantInputs, 'finish', finalized):
            result = invariant.verify(self.root)
        self.assertEqual(len(result['sources']), 4)
        self.assertEqual(events['admissions'], [])
        self.assertEqual(events['finalizers'], [])
        self.assertEqual(states, ['pending'])
        self.assert_closed(owners[0])

    def test_current_caught_guarded_read_failure_discards_existing_map_rows(self):
        loops, core = self.coverage()
        from functools import wraps
        guarded, read = loops.guarded_loop_proof, Path.read_bytes
        earlier, injected = [], []
        @wraps(guarded)
        def proof(root, rule, **kwargs):
            result = sys._getframe(1).f_locals['result']
            self.assertTrue(result, 'construction must produce a real earlier row')
            earlier.append(set(result))
            def changed(path, *args, **settings):
                raw = read(path, *args, **settings)
                caller = sys._getframe(1)
                if (not injected and caller.f_code is loops._reviewed_dependency_hashes.__code__
                        and path == root/'extensions/carla/map.mojo'):
                    injected.append(path)
                    return raw + b'\n# Consumed B after a real earlier row.\n'
                return raw
            with patch.object(Path, 'read_bytes', changed):
                return guarded(root, rule, **kwargs)
        with self.audit(core) as events, patch.object(loops, 'guarded_loop_proof', proof):
            self.assertEqual(loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map'), {})
        self.assertTrue(earlier)
        self.assertEqual(len(injected), 1)
        self.assertTrue(events['admissions'][0]._failed)
        self.assert_closed(events['admissions'][0], core)

    def test_current_actual_stream_reads_reject_changed_short_wrong_and_failed_chunks(self):
        loops, core = self.coverage()
        original_open = Path.open
        for fault in ('changed', 'short', 'wrong_eof', 'io'):
            visited, injected = [], []
            message = {'changed': 'consumed operation bytes',
                       'short': 'consumed operation bytes',
                       'wrong_eof': 'Non-byte coverage source stream',
                       'io': 'injected stream failure'}[fault]
            def consume(operation):
                target = self.root/ROAD
                class Stream:
                    def __init__(self, stream):
                        self.stream = stream
                        self.calls = 0
                    def __enter__(self):
                        self.stream.__enter__()
                        return self
                    def __exit__(self, *args):
                        return self.stream.__exit__(*args)
                    def read(self, size):
                        raw = self.stream.read(size)
                        self.calls += 1
                        visited.append((size, self.calls))
                        if fault == 'io':
                            injected.append(fault)
                            raise PermissionError('injected stream failure')
                        if fault == 'wrong_eof' and not raw:
                            injected.append(fault)
                            return bytearray()
                        if self.calls == 1:
                            if fault == 'changed':
                                injected.append(fault)
                                return raw + b'\n# Stream B.\n'
                            if fault == 'short':
                                injected.append(fault)
                                return raw[:-1]
                        return raw
                def opened(path, *args, **kwargs):
                    stream = original_open(path, *args, **kwargs)
                    if path == target and sys._getframe(1).f_code is loops.file_sha256.__code__:
                        self.assertEqual(args, ('rb',))
                        return Stream(stream)
                    return stream
                with patch.object(Path, 'open', opened):
                    with self.assertRaisesRegex(core._OperationCoherenceError, message):
                        loops.file_sha256(target, _operation=operation, _root=self.root)
                self.assertTrue(operation._failed)
                with self.assertRaises(core._OperationCoherenceError):
                    core._operation_check(operation, self.root)
            with self.subTest(fault=fault), self.audit(core, consume) as events:
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map'), {})
            self.assertTrue(visited)
            self.assertEqual(injected, [fault])
            self.assertTrue(all(size == 1 << 20 for size, _ in visited))
            self.assert_closed(events['admissions'][0], core)

    def test_current_duplicate_proof_conflict_remains_an_error(self):
        # Only the fault is synthetic: both colliding rows are real proofs.
        loops, core = self.coverage()
        from functools import wraps
        guarded = loops.guarded_loop_proof
        collided = []
        @wraps(guarded)
        def proof(root, rule, **kwargs):
            result = sys._getframe(1).f_locals['result']
            value = guarded(root, rule, **kwargs)
            self.assertTrue(result)
            self.assertIsNotNone(value)
            changed = dict(value, line=next(iter(result)))
            collided.append(changed['line'])
            return changed
        with self.audit(core) as events, patch.object(loops, 'guarded_loop_proof', proof):
            with self.assertRaisesRegex(ValueError, 'Conflicting reviewed loop proof') as caught:
                loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map')
        self.assertNotIsInstance(caught.exception, core._OperationCoherenceError)
        self.assertEqual(len(collided), 1)
        self.assert_closed(events['admissions'][0], core)


class BoundedOwnerSyntheticBoundaryControls(unittest.TestCase):
    """Routing/frame controls only; no claim of real current-image admission."""

    def test_arbitrary_factory_and_unsupported_borrow_do_not_create_authority(self):
        root = Path(__file__).resolve().parents[2]
        self.assertEqual(cleanup._operation_enter(root, 'invariant'), (None, False))
        with self.assertRaisesRegex(ValueError, 'direct owner factory'):
            cleanup._InvariantInputs(root, sys._getframe(), 'invariant')
        with self.assertRaisesRegex(ValueError, 'unsupported context'):
            cleanup._operation_enter(root, None, object(), include_roots=(root,))

    def test_nonempty_include_and_unrelated_module_keep_original_fresh_dispatch(self):
        from contextlib import ExitStack
        tools = str(Path(__file__).resolve().parents[1])
        with patch.object(sys, 'path', [tools, *sys.path]):
            import coverage_loop_proofs as loops
            from carla_lane_oracle import full_audit_cleanup_contracts as core
        root = Path(__file__).resolve().parents[2]
        for module, includes in (('extensions/carla/map', (root,)),
                                 ('extensions/carla/rtree', (root,)), ('unrelated/module', ())):
            calls = []
            def historical(actual_root, actual_module, **kwargs):
                calls.append(('historical', actual_root, actual_module, kwargs))
                return {}
            def construction(actual_root, **kwargs):
                calls.append(('construction', actual_root, module, kwargs))
                return {}
            def guarded(actual_root, rule, **kwargs):
                calls.append(('guarded', actual_root, rule[0], kwargs))
                return None
            with self.subTest(module=module, includes=includes), ExitStack() as stack:
                stack.enter_context(patch.object(core, '_operation_enter', side_effect=AssertionError('unexpected owner')))
                stack.enter_context(patch.object(loops, '_historical_reviewed_nonempty_loops', historical))
                stack.enter_context(patch.object(loops, 'construction_boundary_loops', construction))
                stack.enter_context(patch.object(loops, 'guarded_loop_proof', guarded))
                self.assertEqual(loops.reviewed_nonempty_loops(root, module, include_roots=includes), {})
            self.assertTrue(calls)
            for _, actual_root, actual_module, kwargs in calls:
                self.assertEqual((actual_root, actual_module), (root, module))
                self.assertEqual(kwargs, {'include_roots': includes})

    def test_negative_frame_filter_matches_unfiltered_results_and_errors(self):
        import types
        node = copy.deepcopy(function_ast(cleanup, '_operation_frame_kind'))
        # Remove the complete reviewed negative filter at its exact location.
        # Keep all authoritative comparisons and exceptional behavior.
        _rc21_negative_filter(owner_helpers.typed_owner_ast(
            _generated_owner_predecessor_ast(node), 'registry', reverse=True))
        # Keep the exact receipt and standalone seed prefixes in both classifiers.
        del node.body[7]
        node.name = '_unfiltered_frame_kind'
        namespace = dict(vars(cleanup))
        exec(compile(ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])),
                     '<unfiltered-operation-frame-control>', 'exec'), namespace)
        reference = namespace[node.name]
        def plain():
            pass
        def cyclic():
            pass
        cyclic.__wrapped__ = cyclic
        frames = [None, types.SimpleNamespace(f_globals=globals(), f_code=plain.__code__, f_locals={})]
        for filename in (invariant.__file__, 'relative/coverage_invariant_contracts.py', None):
            for function in (None, plain, cyclic):
                frames.append(types.SimpleNamespace(
                    f_globals={'__file__': filename, 'verify': function},
                    f_code=plain.__code__, f_locals={}))
        frames.append(types.SimpleNamespace(f_globals=vars(invariant),
                                            f_code=invariant.verify.__code__, f_locals={}))
        def outcome(function, frame, aliases):
            try:
                return ('result', function(frame, include_aliases=aliases))
            except Exception as error:
                return ('error', type(error), str(error))
        for frame in frames:
            for aliases in (False, True):
                with self.subTest(frame=frame, aliases=aliases):
                    self.assertEqual(outcome(cleanup._operation_frame_kind, frame, aliases),
                                     outcome(reference, frame, aliases))

    @staticmethod
    def _receipt_control_namespace():
        """Compile isolated routing mechanics, never a replacement authority."""
        raw = Path(cleanup.__file__).read_bytes()
        _checker_source_predecessor('full_audit_cleanup_contracts.py', raw)
        tree = ast.parse(raw)
        owner = next(node for node in tree.body if isinstance(node, ast.ClassDef)
                     and node.name == '_InvariantInputs')
        methods = [copy.deepcopy(node) for node in owner.body
                   if isinstance(node, ast.FunctionDef)
                   and node.name in ('_bind_checker_receipt', 'finish')]
        if len(methods) != 2:
            raise AssertionError('missing exact checker receipt methods')
        namespace = dict(vars(cleanup))
        exec(compile(ast.Module(body=methods, type_ignores=[]),
                     '<isolated-checker-receipt-mechanics>', 'exec'), namespace)
        exec(compile("""
def proof_bindings(root, executing, *, _operation, target):
    return target._bind_checker_receipt(root, executing)
def wrong_frame(root, executing, *, _operation, target):
    return target._bind_checker_receipt(root, executing)
""", '<isolated-checker-receipt-callers>', 'exec'), namespace)
        return namespace

    def test_checker_receipt_registration_requires_exact_frame_owner_and_image(self):
        import types
        root = Path('/synthetic-checker-receipt-root')
        captured = {'synthetic-checker.py': 'captured'}
        for fault in (None, 'wrong frame', 'wrong globals', 'wrong owner', 'wrong root',
                      'pending', 'capturing', 'nonbool receipt', 'nondict image', 'different image'):
            with self.subTest(fault=fault):
                namespace = self._receipt_control_namespace()
                events = []
                owner = types.SimpleNamespace(_state='active', _capturing=False,
                    _checker_receipt=False, _executing=types.MappingProxyType(captured))
                def check(actual_root):
                    events.append('owner')
                    cleanup.require(actual_root == root, 'synthetic wrong root')
                def fail(actual_owner, error):
                    self.assertIs(actual_owner, owner)
                    events.append('failure')
                    owner._checker_receipt = False
                    raise error
                owner._check_owner = check
                owner._bind_checker_receipt = types.MethodType(namespace['_bind_checker_receipt'], owner)
                namespace['_operation_fail'] = fail
                caller = namespace['proof_bindings']
                operation, actual_root, executing = owner, root, dict(captured)
                if fault == 'wrong frame': caller = namespace['wrong_frame']
                elif fault == 'wrong globals':
                    caller = types.FunctionType(caller.__code__, dict(namespace))
                elif fault == 'wrong owner': operation = object()
                elif fault == 'wrong root': actual_root = root/'foreign'
                elif fault == 'pending': owner._state = 'pending'
                elif fault == 'capturing': owner._capturing = True
                elif fault == 'nonbool receipt': owner._checker_receipt = 0
                elif fault == 'nondict image': executing = types.MappingProxyType(captured)
                elif fault == 'different image': executing = {'synthetic-checker.py': 'different'}
                if fault is None:
                    self.assertIsNone(caller(actual_root, executing, _operation=operation, target=owner))
                    self.assertIs(owner._checker_receipt, True)
                    self.assertEqual(events, ['owner'])
                else:
                    with self.assertRaises(ValueError):
                        caller(actual_root, executing, _operation=operation, target=owner)
                    self.assertIs(owner._checker_receipt, False)
                    self.assertEqual(events, ['owner', 'failure'])

    def test_checker_receipt_finalizer_keeps_unregistered_owner_scope(self):
        import types
        root = Path('/synthetic-checker-receipt-root')
        captured = {'synthetic-checker.py': 'captured'}
        cases = (('active', False, False), ('pending', False, False),
                 ('active', True, False), ('active', True, True), ('active', 1, False))
        for state, registered, changed in cases:
            with self.subTest(state=state, registered=registered, changed=changed):
                namespace = self._receipt_control_namespace()
                events = []
                owner = types.SimpleNamespace(_state=state, _checker_receipt=registered,
                    _kind='invariant', _owner=object(), _executing=types.MappingProxyType(captured),
                    _resolver_paths=frozenset(), _scaled_resolver_paths=frozenset())
                def check(actual_root):
                    self.assertEqual(actual_root, root)
                    events.append('owner')
                def checkpoint(actual_owner, token, actual_root):
                    self.assertIs(actual_owner, owner)
                    self.assertIs(token, owner._owner)
                    self.assertEqual(actual_root, root)
                    events.append('checkpoint')
                def executing(actual_root):
                    self.assertEqual(actual_root, root)
                    events.append('executing')
                    return {'synthetic-checker.py': 'different'} if changed else dict(captured)
                def close():
                    events.append('close')
                    owner._checker_receipt = False
                    owner._state = 'closed'
                def fail(actual_owner, error):
                    self.assertIs(actual_owner, owner)
                    events.append('failure')
                    raise error
                owner._check_owner, owner.close = check, close
                namespace.update(_CacheInputs=types.SimpleNamespace(checkpoint=checkpoint),
                    executing_checker_bindings=executing, _operation_fail=fail)
                finish = types.MethodType(namespace['finish'], owner)
                refused = changed or type(registered) is not bool
                if refused:
                    with self.assertRaisesRegex(ValueError, 'consumed receipt checker changed|invalid consumed checker receipt state'):
                        finish(root)
                    self.assertEqual(owner._state, 'closed')
                    self.assertIs(owner._checker_receipt, False)
                else:
                    self.assertIsNone(finish(root))
                    self.assertEqual(owner._state, 'finished')
                expected = ['owner']
                if state == 'active': expected.append('checkpoint')
                if registered is True: expected.append('executing')
                if refused: expected.extend(('close', 'failure'))
                self.assertEqual(events, expected)


# Append before the maintained module's final unittest.main() guard.
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Reviewed classifier and lexical mechanics controls. These are not real
# immutable-image lifecycle qualification; the separate lifecycle tests remain.
import importlib as _rm_importlib
import os as _rm_os
from pathlib import Path as _rm_Path, PosixPath as _rm_PosixPath
import sys as _rm_sys
import unittest as _rm_unittest
from unittest.mock import patch as _rm_patch


def _reviewed_mechanics_module(stem):
    prefix = (__package__ + '.') if __package__ else ''
    if stem != 'coverage_loop_proofs':
        return _rm_importlib.import_module(prefix + stem)
    # Reuse the same supported canonical namespace as this test. Restore the
    # temporary import search entry before any classifier/helper observation.
    cleanup = _rm_importlib.import_module(prefix + 'full_audit_cleanup_contracts')
    root = _rm_Path(cleanup.__file__).resolve().parents[2]
    name = 'tools.coverage_loop_proofs' if prefix.startswith('tools.') else 'coverage_loop_proofs'
    with _rm_patch.object(_rm_sys, 'path', [str(root / 'tools'), *_rm_sys.path]):
        return _rm_importlib.import_module(name)

"""Focused differential classifier controls, not source qualification.

Import real canonical modules only when this script is explicitly authorized to
run. Compile just the old/new classifiers into isolated globals. Never replace
production functions, source bytes, sys.modules, or a source admission graph.
Synthetic frame records carry actual code and module-global identities. They
exercise classification only; real operation lifecycle controls remain separate.
"""
import ast as _rc21_ast
from contextlib import nullcontext as _rc21_nullcontext
import hashlib as _rc21_hashlib
import importlib as _rc21_importlib
import json as _rc21_json
from pathlib import Path as _rc21_Path
import sys as _rc21_sys
import types as _rc21_types
from unittest.mock import patch as _rc21_patch
_rc21_UNSET = object()
_rc21_CHECK_COUNT = 0
_rc21_OP_NAMES = ('coverage_invariant_contracts.py', 'winner_sign_contracts.py', 'border_parser_contracts.py', 'coverage_loop_proofs.py')

def _rc21_require(value, detail=None):
    """Always active in normal and optimized Python, unlike assert."""
    global _rc21_CHECK_COUNT
    _rc21_CHECK_COUNT += 1
    if not value:
        if detail is None:
            raise AssertionError
        raise AssertionError(detail)

def _rc21_definitions(text):
    return {node.name: node for node in _rc21_ast.parse(text).body if isinstance(node, (_rc21_ast.FunctionDef, _rc21_ast.ClassDef))}

def _rc21_ast_key(node):
    return _rc21_ast.dump(node, include_attributes=False)

def _rc21_function(code, namespace):
    return _rc21_types.FunctionType(code, namespace, code.co_name)

def _rc21_frame(namespace, code, **locals_):
    return _rc21_types.SimpleNamespace(f_globals=namespace, f_code=code, f_locals=locals_)

def _rc21_outcome(call, input_flag=_rc21_UNSET):
    try:
        value = call()
        if input_flag is not _rc21_UNSET and value is input_flag:
            return {'value_is_input_flag': True}
        return {'value': value}
    except Exception as error:
        return {'exception': type(error).__module__ + '.' + type(error).__qualname__, 'message': str(error)}

def _rc21_expect_ast(node, expected, detail):
    _rc21_require(_rc21_hashlib.sha256(_rc21_ast_key(node).encode()).hexdigest() == expected, detail)


def _rc21_negative_filter(tree):
    # Fixed position and complete subtree: reject changed or moved filters.
    node = tree.body[3]
    _rc21_expect_ast(node, 'dd29d074291dc2aa6d0471f3ea5ea61d8f6ed3dea6ced680fc179fa18bfeb84b',
                     'complete reviewed V11 operation negative filter AST drift')
    return node


def _rc21_original_classifiers(new_text):
    """Invert exact #333 owner additions, then the reviewed V14/V11/V8 edits."""
    module = _rc21_ast.parse(new_text)
    old_defs = {node.name: node for node in module.body
                if isinstance(node, (_rc21_ast.FunctionDef, _rc21_ast.ClassDef))}
    old_defs.pop('_different_alias_leaf')
    operation = old_defs['_operation_frame_kind'] = owner_helpers.typed_owner_ast(
        _generated_owner_predecessor_ast(old_defs['_operation_frame_kind']),
        'operation', 'registry', reverse=True)
    cache = old_defs['_cache_verify_frame']
    owner = old_defs['_owner_module'] = owner_helpers.typed_owner_predecessor(old_defs['_owner_module'])

    # V14 captured live-helper identities are exact assignments immediately
    # after the helper, not new cache or owner authority.
    helper_index = module.body.index(old_defs['_live_function_code'])
    for offset, expected in (
            (1, '21abf36fc99d9d8fccb2df493c51bc07d44374c13026e1297fe42afc77fba4ca'),
            (2, 'aa58adbcee1ebccf3a9978bde4b8b01e18ceaed35fed3e7689c2c93b9c982587')):
        _rc21_expect_ast(module.body[helper_index + offset], expected,
                         ('V14 live-helper capture', offset))

    # V14 cache helper-frame rejection is one exact new If after the original
    # alias-leaf guard. The owner dispatch retains the original assignment in
    # its else branch; only that exact branch is used for the inverse.
    _rc21_expect_ast(cache.body[8], 'a460808e6b3a9bf5d10acd12f88a7d8eaa89004a66271bc30aeb9287f15f0dfc',
                     'V14 cache real-frame negative guard AST drift')
    del cache.body[8]
    _rc21_expect_ast(cache, '430c1279085af0c279ec1e0d3ca166bdb5de822af0f3c8595246a489d3a211e8',
                     'complete V13 cache classifier AST drift')
    _rc21_expect_ast(owner.body[1], '73a7cd0ab7fe92a00574301143c48c926cf3f46080c65edc3fc5f35b09b42553',
                     'V14 exact-string owner dispatch AST drift')
    owner.body[1] = owner.body[1].orelse[0]
    _rc21_expect_ast(owner, 'a5f60b07d07556090def6d3490be5dfeef8197ef71d8e3ff13efce5c110d4860',
                     'complete original owner helper AST drift')

    # V11 expanded just the two plain-candidate predicates. Restore the exact
    # original generator from its preserved fallback, including its return body.
    negative = _rc21_negative_filter(operation)
    _rc21_expect_ast(_rc21_ast.Module(body=negative.body[1:4], type_ignores=[]),
                     'f9db65cf09a857bb6a52f12785632601d4d0bed5c50d80dfaf28b6857a1de362',
                     'V11 two-candidate expansion AST drift')
    original_all = negative.body[2].orelse[0].value
    original_all.func.id = 'all'
    original_if = negative.body[3]
    original_if.test = original_all
    negative.body[1:4] = [original_if]
    _rc21_expect_ast(operation, '7fb32652f190b1f87b8e794aa549193d808d048f5ebc1a5656b6eaf80e96f611',
                     'complete V10 operation classifier AST drift')

    # V8 added one wrapped-negative block and one __main__ leaf conjunct.
    # Their fixed locations and complete ASTs must match before removal.
    _rc21_expect_ast(negative.body[2], '4d30aa850d4f93f1ed75f9e648d376ee834b8544348d7c39ff9345dd88d309e8',
                     'V8 wrapped-negative filter AST drift')
    del negative.body[2]
    _rc21_expect_ast(operation, 'f944d5d5c8b841659e9e573fdfa5dc1d04e73b3680b93b31eef5357a84769516',
                     'complete V7 operation classifier AST drift')
    main_test = cache.body[5].test
    _rc21_expect_ast(main_test.values[4], '5b917f2e256600ae88f3c9554802a9068254f812797dfb2e5acb70f05ae8499f',
                     'V8 cache __main__ leaf conjunct AST drift')
    del main_test.values[4]
    _rc21_expect_ast(cache, 'acb1064c8282d433ad178057445119fddc352572af638a8964f6515fbc27d859',
                     'complete V7 cache classifier AST drift')

    guards = {'_operation_frame_kind': 'cba84dcfda3a51af833b0c31fab1af75e6315e2ad074f741e9175d51362ff010', '_cache_verify_frame': 'd7cbe42a90b3841722f4cc2f13c0c99279c20289ffbacb13a9e77387199b0d1e'}
    originals = {'_operation_frame_kind': '39b16f4014f5723842f04d3913d6cb7aaef23abddfd182ae6ffbbd316e0205d0', '_cache_verify_frame': 'f52cba9ca558a0db0d9acfd0701d035b297add0863943af5e619dfe99ec71390'}
    for name, guard_hash in guards.items():
        tree = old_defs[name]
        _rc21_expect_ast(tree.body[7], guard_hash, (name, 'one exact reviewed guard at original position'))
        del tree.body[7]
        _rc21_expect_ast(tree, originals[name], (name, 'complete original classifier AST drift'))
    old_defs['_operation_frame_kind'] = owner_helpers.typed_owner_ast(
        old_defs['_operation_frame_kind'], 'operation_unguarded')
    old_defs['_owner_module'] = owner_helpers.typed_owner_ast(old_defs['_owner_module'], 'owner')
    return old_defs


def _rc21_main():
    global _rc21_CHECK_COUNT
    _rc21_CHECK_COUNT = 0
    cleanup = _reviewed_mechanics_module('full_audit_cleanup_contracts')
    after = _rc21_Path(cleanup.__file__).absolute()
    root = after.parents[2]
    new_raw = after.read_bytes()
    new_text = new_raw.decode('utf-8')
    new_defs = _rc21_definitions(new_text)
    helper_hash = '3def29f2a78a9b5b66185e4df1a416e9db5b931aeee0edec7febe89bf25db2eb'
    _rc21_require(_rc21_hashlib.sha256(_rc21_ast_key(new_defs['_different_alias_leaf']).encode()).hexdigest() == helper_hash, 'reviewed classifier helper AST drift')
    old_defs = _rc21_original_classifiers(new_text)
    compiled = compile(new_raw, str(after), 'exec', dont_inherit=True, optimize=_rc21_sys.flags.optimize)
    code_by_name = {code.co_name: code for code in compiled.co_consts if isinstance(code, _rc21_types.CodeType)}
    for name in ('_operation_frame_kind', '_cache_verify_frame', '_owner_module',
                 '_different_alias_leaf', '_live_function_code'):
        _rc21_require(code_by_name[name] == getattr(cleanup, name).__code__, (name, 'live classifier source binding'))
    _rc21_require(cleanup._LIVE_FUNCTION_CODE is cleanup._live_function_code
                    and cleanup._LIVE_FUNCTION_CODE_CODE is cleanup._live_function_code.__code__,
                    'reviewed live-helper capture binding')
    modules = {name: _reviewed_mechanics_module(name) for name in ('coverage_invariant_contracts', 'winner_sign_contracts', 'border_parser_contracts', 'cache_key_contracts', 'lane_order_contracts', 'coverage_followup_contracts', 'coverage_loop_proofs')}
    _rc21_require(all((_rc21_Path(module.__file__).absolute().is_relative_to(root) for module in modules.values())), 'canonical fixture module roots')
    names = ('_owner_module', '_cache_verify_frame', '_operation_frame_kind')
    counts = {'cases': 0, 'equivalent': 0, 'negative_path_elisions': 0}
    details = []

    def contexts(core_file=str(after), *, main_module=None, registration=None, os_name=None):
        result = []
        for defs in (old_defs, new_defs):
            namespace = dict(vars(cleanup))
            namespace.pop('_different_alias_leaf', None)
            registry = dict(_rc21_sys.modules)
            if main_module is not None:
                registry['__main__'] = main_module
            if registration is not None:
                registry[registration[0]] = registration[1]
            namespace['sys'] = _rc21_types.SimpleNamespace(modules=registry)
            namespace['__file__'] = core_file
            if os_name is not None:
                namespace['os'] = _rc21_types.SimpleNamespace(name=os_name)
            calls = []

            def observed_path(value, _calls=calls):
                _calls.append(value)
                return _rc21_Path(value)
            namespace['Path'] = observed_path
            selected = [defs[name] for name in names]
            if '_different_alias_leaf' in defs:
                selected.insert(0, defs['_different_alias_leaf'])
            tree = _rc21_ast.Module(body=selected, type_ignores=[])
            exec(compile(tree, '<isolated-classifier-control>', 'exec'), namespace)
            result.append((namespace, calls))
        return result

    def compare(label, candidate, *, classifiers=('_operation_frame_kind', '_cache_verify_frame'), include_aliases=True, core_file=str(after), main_module=None, registration=None, os_name=None, missing_cwd=False, elide=False, expected=_rc21_UNSET, expected_error=None, preserve_path_calls=False, flag_factory=None, expected_bool_calls=None, expected_flag_return=False):
        pair = contexts(core_file, main_module=main_module, registration=registration, os_name=os_name)
        for classifier in classifiers:
            results = []
            calls = []
            bool_calls = []
            for namespace, path_calls in pair:
                path_calls.clear()
                scope = _rc21_patch('os.getcwd', side_effect=FileNotFoundError('control missing cwd')) if missing_cwd else _rc21_nullcontext()
                flag = include_aliases if flag_factory is None else flag_factory()
                with scope:
                    results.append(_rc21_outcome(lambda: namespace[classifier](candidate, include_aliases=flag), input_flag=flag if flag_factory is not None else _rc21_UNSET))
                calls.append(len(path_calls))
                bool_calls.append(flag.calls if flag_factory is not None else None)
            _rc21_require(results[0] == results[1], (label, classifier, results))
            if 'value' in results[0] and 'value' in results[1]:
                _rc21_require(type(results[0]['value']) is type(results[1]['value']), (label, results))
            if flag_factory is not None:
                _rc21_require(bool_calls == [expected_bool_calls, expected_bool_calls], (label, bool_calls))
            if expected_flag_return:
                _rc21_require(results[0] == {'value_is_input_flag': True}, (label, results))
            if expected is not _rc21_UNSET:
                wanted = expected[classifier] if type(expected) is dict else expected
                _rc21_require(results[0] == {'value': wanted}, (label, classifier, results, wanted))
                _rc21_require(type(results[0]['value']) is type(wanted), (label, results, wanted))
            if expected_error is not None:
                _rc21_require(results[0] == {'exception': expected_error[0], 'message': expected_error[1]}, (label, classifier, results, expected_error))
            if preserve_path_calls:
                _rc21_require(calls[0] > 0 and calls[0] == calls[1], (label, classifier, calls))
            if elide:
                _rc21_require(calls[0] > 0 and calls[1] == 0, (label, classifier, calls))
                counts['negative_path_elisions'] += 1
            counts['cases'] += 1
            counts['equivalent'] += 1
            details.append({'label': label, 'classifier': classifier, 'include_aliases': include_aliases, 'outcome': results[0], 'old_path_constructions': calls[0], 'new_path_constructions': calls[1], 'bool_calls': bool_calls})
    live = cleanup._live_function_code
    for name, module in modules.items():
        symbol = 'reviewed_nonempty_loops' if name == 'coverage_loop_proofs' else 'verify'
        for include_aliases in (False, True):
            choices = ('extensions/carla/map', 'extensions/carla/rtree', 'other') if symbol != 'verify' else (None,)
            for module_name in choices:
                operation_kind = {'coverage_invariant_contracts': 'invariant', 'winner_sign_contracts': 'winner', 'border_parser_contracts': 'border'}.get(name)
                if name == 'coverage_loop_proofs':
                    operation_kind = {'extensions/carla/map': 'map_loops', 'extensions/carla/rtree': 'rtree_loops'}.get(module_name, 'other_loops')
                compare('canonical:' + name + ':' + str(module_name), _rc21_frame(vars(module), live(getattr(module, symbol)), module=module_name), include_aliases=include_aliases, expected={'_operation_frame_kind': operation_kind, '_cache_verify_frame': name == 'cache_key_contracts'})
    for name in ('cache_key_contracts', 'lane_order_contracts', 'coverage_followup_contracts'):
        module = modules[name]
        compare('measured-operation-negative:' + name, _rc21_frame(vars(module), live(module.verify)), classifiers=('_operation_frame_kind',), elide=True, expected=None)
    for name in ('coverage_invariant_contracts', 'lane_order_contracts', 'coverage_followup_contracts'):
        module = modules[name]
        compare('measured-cache-negative:' + name, _rc21_frame(vars(module), live(module.verify)), classifiers=('_cache_verify_frame',), elide=True, expected=False)
    base_code = modules['coverage_invariant_contracts'].verify.__code__
    oracle = root / 'tools/carla_lane_oracle'
    paths = [str(oracle / name) for name in (*_rc21_OP_NAMES[:3], 'cache_key_contracts.py')]
    paths += [str(root / 'tools/coverage_loop_proofs.py'), str(oracle / 'other.py'), str(root / 'wrong/coverage_invariant_contracts.py'), str(oracle) + '//./coverage_invariant_contracts.py', str(oracle) + '//./other.py', str(oracle / 'other.py') + '/', str(oracle / 'other.py') + '/.', str(oracle / 'other.py') + '/..', 'relative.py', '', '/', '/.', '/..', None, 7]

    class ExoticString(str):
        pass
    paths.append(ExoticString(str(oracle / 'coverage_invariant_contracts.py')))
    for path in paths:
        namespace = {'__file__': path, '__name__': '_classifier_alias'}
        actual = _rc21_function(base_code, namespace)
        namespace['verify'] = actual
        namespace['reviewed_nonempty_loops'] = actual
        candidate = _rc21_frame(namespace, actual.__code__, module='extensions/carla/map')
        for include_aliases in (False, True):
            compare('spelling:' + repr(path), candidate, include_aliases=include_aliases)
        alias = _rc21_types.ModuleType('_classifier_alias')
        alias.__dict__.update(namespace)
        alias.verify = _rc21_function(base_code, vars(alias))
        alias.reviewed_nonempty_loops = alias.verify
        _rc21_require(alias.verify.__globals__ is vars(alias))
        compare('registered-alias:' + repr(path), _rc21_frame(vars(alias), alias.verify.__code__, module='extensions/carla/map'), registration=(alias.__name__, alias))
    expected_aliases = ((oracle / 'coverage_invariant_contracts.py', 'alias_invariant', False), (oracle / 'winner_sign_contracts.py', 'alias_winner', False), (oracle / 'border_parser_contracts.py', 'alias_border', False), (root / 'tools/coverage_loop_proofs.py', 'alias_loops', False), (oracle / 'cache_key_contracts.py', None, True), (root / 'wrong/coverage_invariant_contracts.py', None, False))
    for path, operation_kind, cache_kind in expected_aliases:
        for registered in (False, True):
            alias = _rc21_types.ModuleType('_explicit_classifier_alias')
            alias.__file__ = str(path)
            alias.verify = _rc21_function(base_code, vars(alias))
            alias.reviewed_nonempty_loops = alias.verify
            _rc21_require(alias.verify.__globals__ is vars(alias))
            for include_aliases in (False, True):
                compare('explicit-alias:' + str(path) + ':' + str(registered), _rc21_frame(vars(alias), alias.verify.__code__, module='extensions/carla/map'), registration=(alias.__name__, alias) if registered else None, include_aliases=include_aliases, expected={'_operation_frame_kind': operation_kind if include_aliases else None, '_cache_verify_frame': cache_kind if include_aliases else False})
    namespace = {'__file__': str(oracle / 'coverage_invariant_contracts.py')}
    renamed = _rc21_function(base_code.replace(co_name='renamed_public_entry'), namespace)
    namespace['verify'] = renamed
    compare('renamed-matching-alias', _rc21_frame(namespace, renamed.__code__), classifiers=('_operation_frame_kind',), expected='alias_invariant')

    class ExoticWrapped:

        def __init__(self):
            self.visits = 0

        @property
        def __wrapped__(self):
            self.visits += 1
            raise ValueError('control exotic wrapper')
    for kind in ('plain', 'wrapped', 'multiwrapped', 'cyclic', 'exotic'):
        for leaf in ('coverage_invariant_contracts.py', 'cache_key_contracts.py', 'other.py'):
            namespace = {'__file__': str(oracle / leaf)}
            target = _rc21_function(base_code, namespace)
            outer = _rc21_function(base_code.replace(co_name='wrapper'), namespace)
            outer.__wrapped__ = target
            if kind == 'plain':
                value = target
            elif kind == 'wrapped':
                value = outer
            elif kind == 'multiwrapped':
                value = _rc21_function(base_code.replace(co_name='outer'), namespace)
                value.__wrapped__ = outer
            elif kind == 'cyclic':
                value = outer
                value.__wrapped__ = value
            else:
                value = ExoticWrapped()
            namespace['verify'] = value
            for classifier, matching_leaf, good in (('_operation_frame_kind', 'coverage_invariant_contracts.py', 'alias_invariant'), ('_cache_verify_frame', 'cache_key_contracts.py', True)):
                negative = None if classifier == '_operation_frame_kind' else False
                matched = leaf == matching_leaf
                expected_error = None
                if matched and kind in ('cyclic', 'exotic'):
                    expected_error = (cleanup.ContractError.__module__ + '.' + cleanup.ContractError.__qualname__, 'full-audit cleanup successor: cyclic executing function wrapper') if kind == 'cyclic' else ('builtins.ValueError', 'control exotic wrapper')
                compare('wrapper:' + kind + ':' + leaf, _rc21_frame(namespace, target.__code__), classifiers=(classifier,), expected=_rc21_UNSET if expected_error else good if matched else negative, expected_error=expected_error, preserve_path_calls=matched)
            if kind == 'exotic':
                _rc21_require(value.visits == (2 if leaf != 'other.py' else 0), (leaf, value.visits))
    namespace = {'__file__': 'relative.py'}
    namespace['verify'] = _rc21_function(base_code, namespace)
    compare('missing-cwd-relative', _rc21_frame(namespace, namespace['verify'].__code__), missing_cwd=True, expected_error=('builtins.FileNotFoundError', 'control missing cwd'), preserve_path_calls=True)
    namespace['__file__'] = str(oracle / 'other.py')
    compare('missing-cwd-relative-core', _rc21_frame(namespace, namespace['verify'].__code__), core_file='relative/core.py', missing_cwd=True, expected_error=('builtins.FileNotFoundError', 'control missing cwd'), preserve_path_calls=True)
    for core in ('relative/core.py', '/', '/.', '/..', str(after) + '/', str(after) + '/.', None, 3, ExoticString(str(after))):
        compare('core-spelling:' + repr(core), _rc21_frame(namespace, namespace['verify'].__code__), core_file=core, preserve_path_calls=True)
    compare('non-posix-fallback', _rc21_frame(namespace, namespace['verify'].__code__), os_name='nt', preserve_path_calls=True)
    for leaf in ('cache_key_contracts.py', 'other.py'):
        main_module = _rc21_types.ModuleType('__main__')
        main_module.__file__ = str(oracle / leaf)
        main_module.verify = _rc21_function(modules['cache_key_contracts'].verify.__code__, vars(main_module))
        compare('cache-main:' + leaf, _rc21_frame(vars(main_module), main_module.verify.__code__), classifiers=('_cache_verify_frame',), main_module=main_module, expected=leaf == 'cache_key_contracts.py')
    main_module = _rc21_types.ModuleType('__main__')
    main_module.__file__ = str(oracle / 'cache_key_contracts.py')
    main_module.verify = _rc21_function(modules['cache_key_contracts'].verify.__code__, vars(main_module))
    wrong_code = base_code.replace(co_name='not_the_main_verify')
    for code in (main_module.verify.__code__, wrong_code):
        compare('cache-main-invalid-core:' + code.co_name, _rc21_frame(vars(main_module), code), classifiers=('_cache_verify_frame',), main_module=main_module, core_file='/', expected_error=('builtins.ValueError', "PosixPath('/') has an empty name"), preserve_path_calls=True)
    compare('cache-main-relative-core-missing-cwd', _rc21_frame(vars(main_module), wrong_code), classifiers=('_cache_verify_frame',), main_module=main_module, core_file='relative/core.py', missing_cwd=True, expected_error=('builtins.FileNotFoundError', 'control missing cwd'), preserve_path_calls=True)
    main_module.__file__ = 'relative-main.py'
    compare('cache-main-relative-file-missing-cwd', _rc21_frame(vars(main_module), wrong_code), classifiers=('_cache_verify_frame',), main_module=main_module, missing_cwd=True, expected_error=('builtins.FileNotFoundError', 'control missing cwd'), preserve_path_calls=True)

    class CustomFlag:

        def __init__(self, sequence):
            self.sequence = sequence
            self.calls = 0

        def __bool__(self):
            item = self.sequence[min(self.calls, len(self.sequence) - 1)]
            self.calls += 1
            if item == 'raise':
                raise ValueError('control flag truthiness')
            return item
    namespace = {'__file__': str(oracle / 'cache_key_contracts.py')}
    namespace['verify'] = _rc21_function(base_code, namespace)
    candidate = _rc21_frame(namespace, namespace['verify'].__code__)
    for trailing in ('', '/'):
        namespace['__file__'] = str(oracle / 'cache_key_contracts.py') + trailing
        for label, sequence in (('truthy', (True,)), ('falsey', (False,)), ('true-false', (True, False)), ('false-true', (False, True)), ('true-raise', (True, 'raise')), ('raising', ('raise',))):
            raising = sequence[0] == 'raise'
            compare('custom-flag:' + str(trailing) + ':' + label, candidate, classifiers=('_cache_verify_frame',), flag_factory=lambda sequence=sequence: CustomFlag(sequence), expected_bool_calls=1, expected=True if sequence[0] is True else _rc21_UNSET, expected_flag_return=sequence[0] is False, expected_error=('builtins.ValueError', 'control flag truthiness') if raising else None)
    namespace['__file__'] = str(oracle / 'cache_key_contracts.py')
    for flag, cache_result in ((0, 0), (1, True), (None, None)):
        compare('builtin-nonbool-flag:' + repr(flag), candidate, include_aliases=flag, expected={'_operation_frame_kind': None, '_cache_verify_frame': cache_result})
    compare('no-frame', None, expected={'_operation_frame_kind': None, '_cache_verify_frame': False})
    _rc21_require(counts == {'cases': 291, 'equivalent': 291, 'negative_path_elisions': 6}, counts)
    _rc21_require(after.read_bytes() == new_raw, 'classifier source changed during controls')
    return counts

"""Focused lexical-only differential controls; run only after source approval.

Extract one exact helper AST from sealed bytes. Do not import any repository
module or alter a candidate. Every predicate remains active under Python -O.
"""
import ast as _rl22_ast
import builtins as _rl22_builtins
from contextlib import ExitStack as _rl22_ExitStack
import hashlib as _rl22_hashlib
import json as _rl22_json
import os as _rl22_os
import pathlib as _rl22_pathlib
from pathlib import Path as _rl22_Path, PosixPath as _rl22_PosixPath, PurePosixPath as _rl22_PurePosixPath, PureWindowsPath as _rl22_PureWindowsPath
import sys as _rl22_sys
import types as _rl22_types
from unittest.mock import patch as _rl22_patch
_rl22_HELPER_AST_SHA = 'd02f09663ba33ad79ce4f5025c317f6c7bfad2e0529286b7a31430994754835f'
_rl22_UNSET = object()
_rl22_CHECKS = 0

def _rl22_require(value, detail):
    global _rl22_CHECKS
    _rl22_CHECKS += 1
    if not value:
        raise AssertionError(detail)

def _rl22_sha(raw):
    return _rl22_hashlib.sha256(raw).hexdigest()

class _rl22_LoggedText(str):

    def __new__(cls, value, log, label, fail=False):
        obj = super().__new__(cls, value)
        obj.log, obj.label, obj.fail = (log, label, fail)
        return obj

    def __bool__(self):
        self.log.append((self.label, 'bool'))
        if self.fail is True:
            raise RuntimeError(self.label + ' text parse blocked')
        return str.__len__(self) != 0

    def __getitem__(self, key):
        label = ('slice', key.start, key.stop, key.step) if isinstance(key, slice) else key
        self.log.append((self.label, 'getitem', label))
        if self.fail == 'getitem':
            raise RuntimeError(self.label + ' splitroot blocked')
        return str.__getitem__(self, key)

    def split(self, *args, **kwargs):
        self.log.append((self.label, 'split'))
        if self.fail == 'split':
            raise RuntimeError(self.label + ' split blocked')
        return str.split(self, *args, **kwargs)

class _rl22_ForeignRoot:

    def __init__(self, log, value='/a', fail=False):
        self.log, self.value, self.fail = (log, value, fail)

    def __fspath__(self):
        self.log.append(('root', 'fspath'))
        if self.fail:
            raise RuntimeError('root fspath blocked')
        return self.value

class _rl22_LoggedPath(_rl22_PosixPath):

    def __init__(self, *args, log=None):
        super().__init__(*args)
        self.log = log if log is not None else []

    @property
    def parts(self):
        self.log.append(('path', 'parts'))
        return super().parts

    @property
    def anchor(self):
        self.log.append(('path', 'anchor'))
        return super().anchor

    def with_segments(self, *segments):
        self.log.append(('path', 'with_segments', tuple((type(x).__name__ for x in segments))))
        return type(self)(*segments, log=self.log)

    def relative_to(self, root):
        self.log.append(('path', 'relative_to'))
        return super().relative_to(root)

class _rl22_DispatchOnlyPath(_rl22_PosixPath):

    def __init__(self, *args, log=None, fail=False):
        super().__init__(*args)
        self.log, self.fail = (log, fail)

    @property
    def parts(self):
        raise AssertionError('helper inspected subclass parts')

    @property
    def anchor(self):
        raise AssertionError('helper inspected subclass anchor')

    def relative_to(self, root):
        self.log.append(('dispatch', 'relative_to', type(root).__name__))
        if self.fail:
            raise RuntimeError('custom relative_to blocked')
        return _rl22_PosixPath('custom-result')

class _rl22_RawList(list):

    def __init__(self, values, log, label):
        super().__init__(values)
        self.log, self.label = (log, label)

    def __iter__(self):
        self.log.append((self.label, 'raw-list-iter'))
        return super().__iter__()

def _rl22_describe(value):
    if isinstance(value, _rl22_pathlib.PurePath):
        return ('value', type(value), str(value), value.parts)
    return ('value', type(value), value)

def _rl22_invoke(call, helper, fast_line, fallback_line):
    """Deny filesystem observations only around this one reference/helper call."""
    events, blocked = ([], [])
    old_trace = _rl22_sys.gettrace()
    _rl22_require(old_trace is None, 'unexpected existing trace callback')

    def trace(frame, event, arg):
        if frame.f_code is helper.__code__:
            if event == 'line' and frame.f_lineno in (fast_line, fallback_line):
                events.append('fast' if frame.f_lineno == fast_line else 'fallback')
            return trace
        return None

    def deny(*args, **kwargs):
        blocked.append('filesystem surface')
        raise AssertionError('filesystem surface called')
    with _rl22_ExitStack() as stack:
        for name in ('stat', 'lstat', 'resolve', 'cwd', 'absolute', 'open', 'read_bytes', 'read_text', 'iterdir', 'glob', 'rglob', 'walk'):
            stack.enter_context(_rl22_patch.object(_rl22_Path, name, deny))
        for name in ('stat', 'lstat', 'getcwd', 'listdir', 'scandir', 'readlink', 'open', 'access'):
            stack.enter_context(_rl22_patch.object(_rl22_os, name, deny))
        stack.enter_context(_rl22_patch.object(_rl22_builtins, 'open', deny))
        _rl22_sys.settrace(trace)
        try:
            try:
                value = call()
            except Exception as error:
                result = ('exception', type(error), str(error))
            else:
                result = value
        finally:
            _rl22_sys.settrace(old_trace)
    _rl22_require(not blocked, 'reference/helper attempted filesystem observation')
    if not (type(result) is tuple and result and (result[0] == 'exception')):
        result = _rl22_describe(result)
    return (result, events)

def _rl22_ordinary(path, root, path_type=_rl22_PosixPath, root_type=_rl22_PosixPath):

    def factory(log):
        return (path_type(path), root_type(root))
    return factory

def _rl22_exotic_text(path_exotic=False, root_exotic=False, preparse=False, fail_path=False, fail_root=False):

    def factory(log):
        p = _rl22_LoggedText('/a/b', log, 'path', fail_path) if path_exotic else '/a/b'
        r = _rl22_LoggedText('/a', log, 'root', fail_root) if root_exotic else '/a'
        path, root = (_rl22_PosixPath(p), _rl22_PosixPath(r))
        if preparse:
            root.parts
            path.parts
        log.clear()
        return (path, root)
    return factory

def _rl22_foreign_root(value='/a', fail=False):
    return lambda log: (_rl22_PosixPath('/a/b'), _rl22_ForeignRoot(log, value, fail))

def _rl22_raw_layout(which, layout):

    def factory(log):
        path, root = (_rl22_PosixPath('/a/b'), _rl22_PosixPath('/a'))
        target = root if which == 'root' else path
        if layout == 'missing':
            del target._raw_paths
        elif layout == 'tuple':
            target._raw_paths = tuple(target._raw_paths)
        elif layout == 'list-subclass':
            target._raw_paths = _rl22_RawList(target._raw_paths, log, which)
        elif layout == 'non-string':
            target._raw_paths = [17]
        else:
            raise AssertionError('unknown private layout case')
        return (path, root)
    return factory

def _rl22_main():
    global _rl22_CHECKS
    _rl22_CHECKS = 0
    cleanup = _reviewed_mechanics_module('full_audit_cleanup_contracts')
    source_path = _rl22_Path(cleanup.__file__)
    source_raw = source_path.read_bytes()
    tree = _rl22_ast.parse(source_raw.decode('utf-8'), filename=str(source_path))
    matches = [n for n in tree.body if isinstance(n, _rl22_ast.FunctionDef) and n.name == '_relative_path']
    _rl22_require(len(matches) == 1, 'one live helper definition')
    node = matches[0]
    _rl22_require(_rl22_sha(_rl22_ast.dump(node, include_attributes=False).encode()) == _rl22_HELPER_AST_SHA, 'reviewed relative helper AST identity')
    compiled = compile(source_raw, str(source_path), 'exec', dont_inherit=True, optimize=_rl22_sys.flags.optimize)
    codes = [code for code in compiled.co_consts if isinstance(code, _rl22_types.CodeType) and code.co_name == '_relative_path']
    helper = cleanup._relative_path
    _rl22_require(len(codes) == 1 and codes[0] == helper.__code__, 'live helper checked-source binding')
    stdlib_path = _rl22_Path(_rl22_pathlib.__file__)
    stdlib_raw = stdlib_path.read_bytes()
    compiled_stdlib = compile(stdlib_raw, str(stdlib_path), 'exec', dont_inherit=True, optimize=_rl22_sys.flags.optimize)
    pending, reference_codes = ([compiled_stdlib], [])
    while pending:
        code = pending.pop()
        if code.co_qualname == 'PurePath.relative_to':
            reference_codes.append(code)
        pending.extend((value for value in code.co_consts if isinstance(value, _rl22_types.CodeType)))
    _rl22_require(len(reference_codes) == 1 and reference_codes[0] == _rl22_pathlib.PurePath.relative_to.__code__, 'live reference equals current checked pathlib source')
    returns = [n for n in _rl22_ast.walk(node) if isinstance(n, _rl22_ast.Return)]
    fast = [n for n in returns if isinstance(n.value, _rl22_ast.Call) and isinstance(n.value.func, _rl22_ast.Name) and (n.value.func.id == 'PosixPath')]
    fallback = [n for n in returns if isinstance(n.value, _rl22_ast.Call) and isinstance(n.value.func, _rl22_ast.Attribute) and (n.value.func.attr == 'relative_to')]
    _rl22_require(len(returns) == 2 and len(fast) == len(fallback) == 1, 'exact return branches')
    records, totals = ([], {'fast': 0, 'fallback': 0})

    def compare(name, factory, branch, *, expected=_rl22_UNSET, error_type=None, first_callback=None, minimum_callbacks=0, exact_log=None, platform='posix'):
        old_log, new_log = ([], [])
        old_args, new_args = (factory(old_log), factory(new_log))
        _rl22_require(old_log == new_log, (name, 'independent fixture construction'))
        call_helper = helper
        if platform != _rl22_os.name:
            namespace = dict(helper.__globals__)
            namespace['os'] = _rl22_types.SimpleNamespace(name=platform)
            call_helper = _rl22_types.FunctionType(helper.__code__, namespace, helper.__name__)
            _rl22_require(call_helper.__code__ is helper.__code__, 'simulated platform uses live helper code')
        old, old_events = _rl22_invoke(lambda: old_args[0].relative_to(old_args[1]), helper, fast[0].lineno, fallback[0].lineno)
        new, new_events = _rl22_invoke(lambda: call_helper(*new_args), helper, fast[0].lineno, fallback[0].lineno)
        _rl22_require(old == new, (name, 'result/type/exception mismatch', old, new))
        _rl22_require(new[0] == ('value' if error_type is None else 'exception'), (name, 'explicit success/exception route', new))
        _rl22_require(old_log == new_log, (name, 'callback order/count mismatch', old_log, new_log))
        _rl22_require(old_events == [], (name, 'reference unexpectedly entered proposal'))
        _rl22_require(new_events == [branch], (name, 'actual helper branch', new_events, branch))
        _rl22_require(len(new_log) >= minimum_callbacks, (name, 'callback route not exercised'))
        if first_callback is not None:
            _rl22_require(bool(new_log) and new_log[0][0] == first_callback, (name, 'first parsing callback', new_log))
        if exact_log is not None:
            _rl22_require(new_log == exact_log, (name, 'explicit callback route', new_log))
        if expected is not _rl22_UNSET:
            _rl22_require(new[0] == 'value' and new[1] is _rl22_PosixPath and (new[2] == expected), (name, 'explicit successful result', new, expected))
        if error_type is not None:
            _rl22_require(new[0] == 'exception' and new[1] is error_type, (name, 'explicit exception route', new, error_type))
        totals[branch] += 1
        records.append({'case': name, 'branch': branch, 'outcome': new[0], 'type': new[1].__module__ + '.' + new[1].__qualname__, 'detail': new[2], 'callbacks': new_log})
    successes = [('equal', '/a', '/a', '.'), ('root-equal', '/', '/', '.'), ('root', '/a/b', '/', 'a/b'), ('nested', '/a/b/c', '/a', 'b/c'), ('dotfiles', '/a/.dot', '/a', '.dot'), ('unicode', '/a/é/漢', '/a', 'é/漢'), ('spaces', '/a/a b', '/a', 'a b'), ('case-retained', '/a/A', '/a', 'A'), ('nul', '/a/\x00x', '/a', '\x00x'), ('slashes-dots', '/a//./b///c/', '/a/.', 'b/c'), ('triple-anchor', '///a/b', '///a', 'b'), ('backslash-name', '/a/x\\y', '/a', 'x\\y'), ('colon-name', '/a/C:', '/a', 'C:'), ('prefix-root', '/a/ab', '/a', 'ab')]
    for name, path, root, expected in successes:
        compare(name, _rl22_ordinary(path, root), 'fast', expected=expected)
    components = ('a', 'ab', 'A', '.hidden', 'é', 'space x', '\x00x')
    for root_part in components:
        for leaf in components:
            compare('components:' + repr((root_part, leaf)), _rl22_ordinary('/' + root_part + '/' + leaf, '/' + root_part), 'fast', expected=leaf)
    for name, path, root, succeeds in [('sibling-prefix', '/ab/x', '/a', False), ('deeper-root', '/a', '/a/b', False), ('outside', '/b/x', '/a', False), ('case-mismatch', '/A/x', '/a', False), ('relative', 'a/b', 'a', True), ('relative-empty', '', '', True), ('relative-dot', './a/b', '.', True), ('mixed-path', 'a/b', '/a', False), ('mixed-root', '/a/b', 'a', False), ('double-slash', '//a/b', '//a', True), ('double-mixed', '//a/b', '/a', False), ('path-dotdot', '/a/../b', '/a', True), ('root-dotdot', '/a/../b', '/a/..', True), ('windows-looking', 'C:\\a\\b', 'C:\\a', False), ('windows-slashes', 'C:/a/b', 'C:/a', True)]:
        compare(name, _rl22_ordinary(path, root), 'fallback', error_type=None if succeeds else ValueError)
    compare('platform-fallback', _rl22_ordinary('/a/b', '/a'), 'fallback', expected='b', platform='nt')
    compare('pure-posix', _rl22_ordinary('/a/b', '/a', _rl22_PurePosixPath, _rl22_PurePosixPath), 'fallback')
    compare('pure-windows', _rl22_ordinary('C:/a/b', 'C:/a', _rl22_PureWindowsPath, _rl22_PureWindowsPath), 'fallback')
    compare('windows-foreign-root', _rl22_ordinary('/a/b', 'C:/a', _rl22_PosixPath, _rl22_PureWindowsPath), 'fallback', error_type=ValueError)
    compare('str-root', lambda log: (_rl22_PosixPath('/a/b'), '/a'), 'fallback', expected='b')
    compare('invalid-root', lambda log: (_rl22_PosixPath('/a/b'), 17), 'fallback', error_type=TypeError)
    compare('pathlike-root', _rl22_foreign_root(), 'fallback', expected='b', exact_log=[('root', 'fspath')])
    compare('pathlike-raising', _rl22_foreign_root(fail=True), 'fallback', error_type=RuntimeError, exact_log=[('root', 'fspath')])
    compare('pathlike-invalid-result', _rl22_foreign_root(value=b'/a'), 'fallback', error_type=TypeError, exact_log=[('root', 'fspath')])
    compare('subclass-normal', lambda log: (_rl22_LoggedPath('/a/b', log=log), _rl22_PosixPath('/a')), 'fallback', first_callback='path', minimum_callbacks=2)
    compare('subclass-root', lambda log: (_rl22_PosixPath('/a/b'), _rl22_LoggedPath('/a', log=log)), 'fallback', expected='b', exact_log=[])
    compare('subclass-dispatch', lambda log: (_rl22_DispatchOnlyPath('/a/b', log=log), _rl22_ForeignRoot(log)), 'fallback', expected='custom-result', exact_log=[('dispatch', 'relative_to', '_rl22_ForeignRoot')])
    compare('subclass-raising', lambda log: (_rl22_DispatchOnlyPath('/a/b', log=log, fail=True), _rl22_PosixPath('/a')), 'fallback', error_type=RuntimeError, exact_log=[('dispatch', 'relative_to', 'PosixPath')])
    for path_exotic, root_exotic in ((True, False), (False, True), (True, True)):
        for preparse in (False, True):
            name = 'str-subclass:' + repr((path_exotic, root_exotic, preparse))
            first = 'root' if root_exotic else 'path' if not preparse else None
            compare(name, _rl22_exotic_text(path_exotic, root_exotic, preparse), 'fallback', expected='b', first_callback=first, minimum_callbacks=1 if first else 0)
    for fail_path, fail_root in ((True, False), (False, True), (True, True)):
        compare('str-raising:' + repr((fail_path, fail_root)), _rl22_exotic_text(True, True, fail_path=fail_path, fail_root=fail_root), 'fallback', error_type=RuntimeError, first_callback='root', minimum_callbacks=1)
    for stage in ('getitem', 'split'):

        def late_parser(log, stage=stage):
            absolute = stage == 'getitem'
            path = _rl22_PosixPath('/a/b' if absolute else 'a/b')
            root = _rl22_PosixPath(_rl22_LoggedText('/a' if absolute else 'a', log, 'root', stage))
            return (path, root)
        compare('late-parser-raising:' + stage, late_parser, 'fallback', error_type=RuntimeError, first_callback='root', minimum_callbacks=2)
    for which in ('root', 'path'):
        for layout in ('missing', 'tuple', 'list-subclass', 'non-string'):
            compare('layout:' + which + ':' + layout, _rl22_raw_layout(which, layout), 'fallback', error_type=AttributeError if layout == 'missing' else TypeError if layout == 'non-string' else None)
    _rl22_require(totals['fast'] == len(successes) + len(components) ** 2, 'all expected fast cases')
    _rl22_require(totals['fallback'] == 47, 'all expected fallback cases')
    _rl22_require(sum(totals.values()) == len(records), 'all cases have explicit branch evidence')
    _rl22_require(source_path.read_bytes() == source_raw, 'helper source changed during controls')
    _rl22_require(stdlib_path.read_bytes() == stdlib_raw, 'reference source changed during controls')
    return {'cases': len(records), 'branch_counts': totals}

class ReviewedClassifierMechanics(_rm_unittest.TestCase):
    def test_reviewed_exact_guard_projection_and_291_cases(self):
        if _rm_os.name != 'posix':
            self.skipTest('The reviewed filename/error matrix is POSIX-specific.')
        result = _rc21_main()
        self.assertEqual(result, {'cases': 291, 'equivalent': 291, 'negative_path_elisions': 6})


class ReviewedRelativePathMechanics(_rm_unittest.TestCase):
    def test_reviewed_110_cases_on_supported_posix_layout(self):
        if _rm_os.name != 'posix':
            self.skipTest('The 110 reviewed fixture cases use concrete POSIX paths.')
        probe = _rm_PosixPath('/a')
        raw = getattr(probe, '_raw_paths', None)
        if type(raw) is not list or not all(type(piece) is str for piece in raw):
            self.skipTest('Private-layout fixtures are unavailable; native fallback is tested separately.')
        result = _rl22_main()
        self.assertEqual(result, {'cases': 110, 'branch_counts': {'fast': 63, 'fallback': 47}})

    def test_native_path_fallback_without_layout_requirement(self):
        cleanup = _reviewed_mechanics_module('full_audit_cleanup_contracts')
        old_path, old_root = _rm_Path('a/b'), _rm_Path('a')
        new_path, new_root = _rm_Path('a/b'), _rm_Path('a')
        old, new = old_path.relative_to(old_root), cleanup._relative_path(new_path, new_root)
        self.assertIs(type(new), type(old))
        self.assertEqual((str(new), new.parts), (str(old), old.parts))
        self.assertEqual(str(new), 'b')


def _one_ast_run(node, expected):
    """Find one exact contiguous statement sequence, never a filtered body."""
    expected = ast.parse(expected).body
    matches = []
    for parent in ast.walk(node):
        for _, body in ast.iter_fields(parent):
            if isinstance(body, list):
                for start in range(len(body) - len(expected) + 1):
                    items = body[start:start + len(expected)]
                    if all(isinstance(item, ast.AST) for item in items) and [ast_key(item) for item in items] == [ast_key(item) for item in expected]:
                        matches.append(items)
    if len(matches) != 1:
        raise AssertionError(('one exact current physical statement sequence', node.name, len(matches)))
    return matches[0]


def _seed_supplied_read_contract(node):
    """Two executed reads survive the removal of four conditional syntax copies."""
    first = _one_ast_run(node, """
current_raw = (Path(root) / MODULE).read_bytes()
if _operation is not None:
    current_raw = full_audit._observe_bytes(root, MODULE, current_raw, _operation=_operation)
require(source.token_sha256(text) == source.token_sha256(current_raw.decode('utf-8')),
        'unreviewed supplied Map source')
text = _typed_source.historical_text(root, MODULE, text, _operation=_operation)
physical = _typed_source.historical_bytes(root, MODULE, current_raw, _operation=_operation)
""")
    final = _one_ast_run(node, """
final_raw = (Path(root) / MODULE).read_bytes()
if _operation is not None:
    final_raw = full_audit._observe_bytes(root, MODULE, final_raw, _operation=_operation)
require(final_raw == current_raw, 'Map changed during supplied-view verification')
""")
    if first[-1].lineno >= final[0].lineno:
        raise AssertionError('supplied Map final read precedes admission')
    return first, final


def _station_census_read_contract(node):
    """Only authority-bearing Map census rows add a physical byte/lease read."""
    return _one_ast_run(node, """
supplied_text = ((path.read_text() if _operation is None else
                  full_audit._observe_text(root, rel.as_posix(), path.read_text(), _operation=_operation)) if _inputs is None else
                 _inputs.text_default(_input_owner, root, rel.as_posix()))
if rel.as_posix() == MODULE and station_edge is not None:
    physical = ((path.read_bytes() if _operation is None else
                 full_audit._observe_bytes(root, MODULE, path.read_bytes(), _operation=_operation)) if _inputs is None else
                _inputs.observe_bytes(_input_owner, root, MODULE))
    require(source.token_sha256(supplied_text) == source.token_sha256(physical.decode('utf-8')),
            'station census supplied and physical Map views differ')
text = _typed_source.historical_text(root, rel.as_posix(), supplied_text, _operation=_operation,
    _inputs=_inputs, _input_owner=_input_owner)
""")[1]


def _coverage_current_discriminator_contract(node):
    """Typed/historical row selection uses the preceding actual dependency digest."""
    if node.name == '_historical_reviewed_nonempty_loops':
        return _one_ast_run(node, """
current = _coverage_observe_text(root, name,
    relative_source(root, name, **operation_args).read_text(), _operation=_operation)
if sha256(current.encode('utf-8')) != actual[name]:
    return {}
""")
    if node.name == 'guarded_loop_proof':
        return _one_ast_run(node, """
current = _coverage_observe_text(root, module_path,
    relative_source(root, module_path, **operation_args).read_text(), _operation=_operation)
if sha256(current.encode('utf-8')) != actual_bindings[module_path]:
    return None
typed_current = typed.is_current(module_path, current)
""")
    raise AssertionError(('unknown coverage discriminator', node.name))


# Exact reviewed consumed-value boundaries only. Source spans are derived at runtime.
# Tuple: module, original owner, physical expression, expected count, selections.
# Each selection is (index, stable site suffix, comparator mode, narrow binding kind).
_OPERATION_REACHED_READ_SPECS = (
    # PR760's complete physical-image branch precedes the preserved typed
    # boundary branch. Trace the actual cohort and candidate reads too,
    # including every call of the nested observer during its final reread.
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_pr760_select',
     '_regular(root, path).read_bytes()', 1,
     ((0, 'pr760-cohort-physical', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_pr760_candidate_bindings',
     '_regular(root, path).read_bytes()', 1,
     ((0, 'pr760-candidate-physical', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_scaled_float32_bindings',
     '_regular(root, path).read_bytes()', 1, ((0, 'scaled-source-and-witness-observation', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'scaled_float32_proof_bindings',
     '_regular(root, name).read_bytes()', 1, ((0, 'scaled-receipt-final-observation', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'reviewed_text',
     "_regular(root, path).read_text(encoding='utf-8')", 1,
     ((0, 'typed-public-utf8-default', 'physical', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'reviewed_lane_before_center_text',
     '_regular(root, path).read_bytes()', 2, (
         (0, 'typed-center-supplied-first', 'bytes', 'observe'),
         (1, 'typed-center-supplied-final', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/heading_correspondence.py', 'verify',
     "(path / 'curve_bounds.mojo').read_text()", 1,
     ((0, 'typed-heading-producer', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/heading_correspondence.py', 'verify',
     '(path / filename).read_text()', 1,
     ((0, 'typed-heading-consumers', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/heading_correspondence.py', 'verify',
     "(path / 'spiral_moment_proof.mojo').read_text()", 1,
     ((0, 'typed-heading-eligibility', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_score_caller_inventory',
     'path.read_bytes()', 2, ((1, 'typed-station-census-physical', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_score_caller_inventory',
     '_inputs.observe_bytes(_input_owner, root, MODULE)', 1,
     ((0, 'station-census-lease', 'bytes', 'lease'),)),
    ('tools/carla_lane_oracle/optional_runtime_contracts.py', 'body',
     "(root / ('extensions/carla/' + module + '.mojo')).read_text()", 1,
     ((0, 'typed-runtime-body', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/optional_runtime_contracts.py', 'verify_no_containing_model_consumers',
     'path.read_text()', 1, ((0, 'typed-runtime-callers', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/optional_runtime_contracts.py', 'verify_semantics',
     "(root / 'extensions/carla/curve_bounds.mojo').read_text()", 1,
     ((0, 'typed-runtime-reference', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_contracts.py', 'verify',
     "(root / ('extensions/carla/' + name + '.mojo')).read_text()", 1,
     ((0, 'typed-sum2-source-batch', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_contracts.py', 'verify',
     "(root / 'tools/carla_lane_oracle/spiral-moment-pins.json').read_text()", 1,
     ((0, 'typed-sum2-pin', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_interval.mojo').read_text()", 1,
     ((0, 'typed-sum2-interval', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/check_sampled_values.py', 'verify',
     'path.read_text()', 1, ((0, 'typed-sampled-initial-batch', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/check_sampled_values.py', 'verify',
     'path.read_bytes()', 1, ((0, 'typed-sampled-final-sources', 'bytes', 'observe'),)),
    # #333 current physical admission/provenance seams. The original sites
    # below remain in the same matrix; this list adds the successor reads.
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_typed_boundary_bindings',
     '_regular(root, marker).read_bytes()', 1, ((0, 'typed-marker-first', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_typed_boundary_bindings',
     '_regular(root, path).read_bytes()', 4, (
         (0, 'typed-historical-mix-guard', 'bytes', 'observe'),
         (1, 'typed-source-first', 'bytes', 'observe'),
         (2, 'typed-bound-input-first', 'bytes', 'observe'),
         (3, 'typed-bound-input-final', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'reviewed_typed_text',
     '_regular(root, path).read_bytes()', 2, (
         (0, 'typed-provenance-first', 'bytes', 'observe'),
         (1, 'typed-provenance-final', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'typed_successor_edges',
     '_regular(root, marker).read_bytes()', 1, ((0, 'typed-edge-marker', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'typed_successor_edges',
     '_regular(root, path).read_bytes()', 1, ((0, 'typed-edge-source', 'bytes', 'observe'),)),
    ('tools/coverage_loop_proofs.py', '_historical_reviewed_nonempty_loops',
     'relative_source(root, name, **operation_args).read_text()', 1,
     ((0, 'typed-loop-current-source', 'default', 'observe'),)),
    ('tools/coverage_loop_proofs.py', 'guarded_loop_proof',
     'relative_source(root, module_path, **operation_args).read_text()', 1,
     ((0, 'typed-guarded-current-source', 'default', 'observe'),)),
    ('tools/coverage_loop_proofs.py', 'guarded_loop_proof',
     'relative_source(root, path.as_posix(), **operation_args).read_text()', 1,
     ((0, 'typed-guarded-current-caller', 'default', 'observe'),)),
    ('tools/coverage_loop_proofs.py', '_typed_construction_boundary_loops',
     'relative_source(root, path, **operation_args).read_bytes()', 1,
     ((0, 'typed-construction-input', 'bytes', 'observe'),)),
    ('tools/coverage_loop_proofs.py', 'construction_boundary_loops',
     'relative_source(root, name, **operation_args).read_text()', 1,
     ((0, 'typed-construction-source', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/consumer_successor_ledger.py', '_read',
     'audit._regular(root, path).read_bytes()', 1, ((0, '82:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/runtime_boundary_contracts.py', 'verify',
     '(root / MIGRATION).read_bytes()', 1, ((0, '66:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/render_actor_reuse_contracts.py', 'verify',
     '(root / MIGRATION).read_bytes()', 1, ((0, '59:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/coverage_invariant_contracts.py', 'verify',
     '(root / path).read_text()', 1, ((0, '81:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/coverage_followup_contracts.py', 'verify',
     '(root / path).read_text()', 1, ((0, '84:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/accepted_successor_contracts.py', '_verify_current',
     '(root / path).read_text()', 1, ((0, '56:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/accepted_successor_contracts.py', '_verify_current_for_pin_pair',
     '(root / path).read_text()', 1, ((0, '117:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/accepted_successor_contracts.py', '_read_current_pair_pin',
     'full_audit._regular(root, relative).read_bytes()', 1, ((0, '166:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_lane_observation',
     'path.read_text()', 1, ((0, '36:1', 'supplied_physical', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_lane_observation',
     'path.read_bytes()', 1, ((0, '37:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     '(root / path).read_text()', 1, ((0, '56:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     '(root / name).read_text()', 2, ((0, '59:1', 'default', 'observe'), (1, '71:1', 'default', 'observe'))),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     'physical.read_bytes()', 1, ((0, '92:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     'physical.read_text()', 1, ((0, '98:1', 'supplied_physical', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     "(root / item['path']).read_text()", 2, ((0, '106:1', 'default', 'observe'), (1, '118:1', 'default', 'observe'))),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_premises',
     'full_audit._regular(root, name).read_bytes()', 1, ((0, '124:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify',
     "(root / record['path']).read_text()", 1, ((0, '135:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/rounded_line_selector_contracts.py', '_verify_for_pin_pair',
     "(root / record['path']).read_text()", 1, ((0, '143:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/distance_validation_contracts.py', 'verify',
     '(root / MODULE).read_text()', 1, ((0, '18:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/distance_validation_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_interval.mojo').read_text()", 1, ((0, '18:2', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/grouped_y_finiteness_contracts.py', 'verify',
     '(root / p).read_text()', 1, ((0, '26:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/curve_support_dispatch_contracts.py', 'reviewed_source',
     '(root / path).read_text()', 1, ((0, '43:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/curve_support_dispatch_contracts.py', 'verify_premises',
     '(root / path).read_text()', 1, ((0, '68:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/curve_support_dispatch_contracts.py', 'verify_premises',
     "(root / item['path']).read_text()", 2, ((0, '71:1', 'default', 'observe'), (1, '98:1', 'default', 'observe'))),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify_premises',
     '(root / SOURCE_PATH).read_text()', 1, ((0, '47:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify_premises',
     "(root / 'extensions/carla/curve_sum2.mojo').read_text()", 1, ((0, '49:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify_premises',
     "(root / 'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_text()", 1, ((0, '53:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify_premises',
     "(root / 'tests/test_carla_raw_cut_successor.mojo').read_text()", 1, ((0, '57:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify_premises',
     "(root / 'tests/test_carla_support_dispatch_successor.mojo').read_text()", 1, ((0, '59:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/raw_cut_inverse_contracts.py', 'verify',
     '(root / SOURCE_PATH).read_text()', 1, ((0, '68:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/moment_finiteness_contracts.py', 'verify',
     '(root / MODULE).read_text()', 1, ((0, '39:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/moment_finiteness_contracts.py', 'verify',
     '(root / INTERVAL).read_text()', 1, ((0, '39:2', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/moment_finiteness_contracts.py', 'verify',
     "(root / 'extensions/carla/geometry.mojo').read_text()", 1, ((0, '39:3', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/moment_finiteness_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_trig.mojo').read_text()", 1, ((0, '39:4', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/envelope_budget_contracts.py', 'verify',
     '(Path(root) / MODULE).read_text()', 1, ((0, '35:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_order_contracts.py', 'inventory',
     'path.read_text()', 1, ((0, '45:1', 'default_or_map_supplied', 'observe'),)),
    ('tools/carla_lane_oracle/lane_order_contracts.py', 'inventory',
     'path.read_bytes()', 2, ((0, '55:1', 'bytes', 'observe'), (1, '65:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/lane_order_contracts.py', 'verify',
     "(root / record['module']).read_text()", 1, ((0, '83:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_order_contracts.py', 'verify',
     '(root / rel).read_text()', 1, ((0, '87:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_order_contracts.py', 'verify',
     "(root / 'tests/test_carla_lane_order_successor.mojo').read_text()", 1, ((0, '93:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_control_contracts.py', 'verify',
     "(root / record['module']).read_text()", 1, ((0, '34:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_control_contracts.py', 'verify',
     "(root / 'tests/test_carla_lane_control_successor.mojo').read_text()", 1, ((0, '50:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_control_contracts.py', 'verify',
     "(root / item['path']).read_text()", 1, ((0, '56:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/lane_control_contracts.py', 'verify',
     '(root / rel).read_text()', 1, ((0, '60:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/selection_finiteness_contracts.py', '_producer_text',
     '(root / path).read_text()', 1, ((0, '40:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/selection_finiteness_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_interval.mojo').read_text()", 1, ((0, '53:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/selection_finiteness_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_trig.mojo').read_text()", 1, ((0, '53:2', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/grouped_table_contracts.py', 'verify',
     '(root / MODULE).read_text()', 1, ((0, '38:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/grouped_table_contracts.py', 'verify',
     "(root / 'extensions/carla/geometry.mojo').read_text()", 1, ((0, '45:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/cache_key_contracts.py', 'inventory',
     'path.read_text()', 2, ((1, '89:1', 'supplied_default', 'local_s'),)),
    ('tools/carla_lane_oracle/cache_key_contracts.py', 'inventory',
     '_inputs.observe_bytes(_input_owner, root, rel.as_posix())', 2, ((0, '92:1', 'bytes', 'lease'), (1, '132:1', 'bytes', 'lease'))),
    ('tools/carla_lane_oracle/cache_key_contracts.py', 'verify',
     '(root / MODULE).read_text()', 1, ((0, '179:1', 'supplied_default', 'observe'),)),
    ('tools/carla_lane_oracle/cache_key_contracts.py', 'reviewed_text',
     '(Path(root) / MODULE).read_text()', 1, ((0, '229:1', 'supplied_default', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'dependency_inventory',
     '(root / name).read_bytes()', 2, ((1, '303:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_score_caller_inventory',
     'path.read_text()', 2, ((1, '484:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_score',
     '(root / MODULE).read_bytes()', 4, ((1, '541:1', 'bytes', 'observe'), (3, '563:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_score',
     '_inputs.observe_bytes(_input_owner, root, MODULE)', 2, ((0, '542:1', 'bytes', 'lease'), (1, '564:1', 'bytes', 'lease'))),
    ('tools/carla_lane_oracle/seed_count_contracts.py', '_verify_bound_inputs',
     '(root / path).read_bytes()', 4, ((1, '592:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_premises',
     '(root / path).read_bytes()', 8, ((1, '648:1', 'bytes', 'observe'), (3, '659:1', 'bytes', 'observe'), (5, '678:1', 'bytes', 'observe'), (7, '684:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'verify_premises',
     '(root / MODULE).read_bytes()', 2, ((1, '689:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/seed_count_contracts.py', '_verify_seed_body',
     '(root / MODULE).read_bytes()', 4, ((1, '709:1', 'bytes', 'observe'),
         (3, 'typed-seed-dispatch-final', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'reviewed_text',
     '(Path(root) / MODULE).read_bytes()', 2, ((0, '754:1', 'bytes', 'observe'), (1, '766:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_CacheInputs.observe_bytes',
     '_regular(root, path).read_bytes()', 1, ((0, '1003:1', 'bytes', 'base'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_cache_lane_inputs',
     '_regular(root, path).read_bytes()', 1, ((0, '1097:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', '_reviewed_lane_observation',
     '_regular(root, road).read_bytes()', 1, ((0, '1244:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/border_parser_contracts.py', 'verify',
     '(root / MODULE).read_bytes()', 1, ((0, '156:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/border_parser_contracts.py', 'verify',
     '(root / path).read_bytes()', 3, ((0, '163:1', 'bytes', 'observe'), (1, '170:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/frozen_arc_producer_contracts.py', 'verify_premises',
     "(root / item['path']).read_text()", 1, ((0, '81:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/frozen_arc_producer_contracts.py', 'verify_premises',
     "(root / 'extensions/carla/curve_rounded_arc.mojo').read_text()", 1, ((0, '85:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/frozen_arc_producer_contracts.py', 'verify',
     '(root / SOURCE_PATH).read_text()', 1, ((0, '96:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/frozen_arc_producer_contracts.py', 'verify',
     '(root / path).read_text()', 1, ((0, '104:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'reviewed_sum2_callers',
     'physical.read_bytes()', 1, ((0, '1289:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'reviewed_sum2_callers',
     "physical.read_text(encoding='utf-8')", 1, ((0, '1291:1', 'supplied_physical', 'observe'),)),
    ('tools/carla_lane_oracle/render_actor_reuse_contracts.py', 'verify',
     '(root / path).read_bytes()', 2, ((0, '47:1', 'bytes', 'observe'), (1, '81:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify_premises',
     '(root / SOURCE_PATHS[0]).read_text()', 1, ((0, '103:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify_premises',
     '(root / SOURCE_PATHS[1]).read_text()', 1, ((0, '104:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify_premises',
     '(root / SOURCE_PATHS[2]).read_text()', 1, ((0, '105:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/reviewed_cleanup_contracts.py', 'verify',
     '(root / path).read_text()', 2, ((0, '252:1', 'default', 'observe'), (1, '266:1', 'default', 'observe'))),
    ('tools/carla_lane_oracle/runtime_boundary_contracts.py', 'verify',
     '(root / path).read_bytes()', 2, ((0, '54:1', 'bytes', 'observe'), (1, '88:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/seed_count_contracts.py', 'historical_source',
     '(root / MODULE).read_bytes()', 2, ((0, '731:1', 'bytes', 'observe'), (1, '737:1', 'bytes', 'observe'))),
    ('tools/carla_lane_oracle/source_contracts.py', 'read_pins',
     "(root / PINS).read_text(encoding='utf-8')", 1, ((0, '180:1', 'physical', 'observe'),)),
    ('tools/carla_lane_oracle/source_contracts.py', 'verify_group',
     "(root / path).read_text(encoding='utf-8')", 1, ((0, '207:1', 'physical', 'observe'),)),
    ('tools/carla_lane_oracle/speed_parser_contracts.py', 'verify',
     '(root / MODULE).read_text()', 1, ((0, '35:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_guard_contracts.py', 'protected_inventory',
     'path.read_text()', 1, ((0, '148:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_guard_contracts.py', 'verify',
     '(root / PINS).read_text()', 1, ((0, '311:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_guard_contracts.py', 'verify',
     "(root / 'extensions/carla/curve_sum2.mojo').read_text()", 1, ((0, '331:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_guard_contracts.py', 'verify',
     '(root / path).read_text()', 1, ((0, '359:1', 'default', 'observe'),)),
    ('tools/carla_lane_oracle/sum2_guard_contracts.py', 'verify',
     '(root / path).read_bytes()', 1, ((0, '384:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/winner_sign_contracts.py', 'verify',
     "(root / 'extensions/carla/map.mojo').read_bytes()", 1, ((0, '71:1', 'bytes', 'observe'),)),
    ('tools/carla_lane_oracle/winner_sign_contracts.py', 'verify',
     '(root / path).read_bytes()', 2, ((0, '175:1', 'bytes', 'observe'), (1, '195:1', 'bytes', 'observe'))),
    ('tools/coverage_loop_proofs.py', 'file_sha256',
     "Path(path).open('rb')", 1, ((0, '156:1', 'stream_open', 'stream_open'),)),
    ('tools/coverage_loop_proofs.py', 'file_sha256',
     'stream.read(1 << 20)', 1, ((0, '157:1', 'stream_read', 'stream_read'),)),
    ('tools/coverage_loop_proofs.py', '_reviewed_dependency_hashes',
     'path.read_bytes()', 5, ((0, '798:1', 'bytes', 'observe'),
                            (1, 'typed-source-final', 'bytes', 'observe'),
                            (2, 'shared-helper-source-final', 'bytes', 'observe'),
                            (3, 'cleanup-source-final', 'bytes', 'observe'),
                            (4, '828:1', 'bytes', 'observe'))),
    # Only the exact shared-helper successor branch added to this owner.
    # Its checker, provider and package samples retain their physical values.
    ('tools/coverage_loop_proofs.py', '_reviewed_dependency_hashes',
     'relative_source(root, leaf, **operation_args).read_bytes()', 2,
     ((0, 'shared-helper-checker-first', 'bytes', 'observe'),
      (1, 'shared-helper-checker-final', 'bytes', 'observe'))),
    ('tools/coverage_loop_proofs.py', '_reviewed_dependency_hashes',
     'relative_source(root, provider, **operation_args).read_bytes()', 2,
     ((0, 'shared-helper-provider-first', 'bytes', 'observe'),
      (1, 'shared-helper-provider-final', 'bytes', 'observe'))),
    ('tools/coverage_loop_proofs.py', '_reviewed_dependency_hashes',
     'relative_source(root, package, **operation_args).read_bytes()', 1,
     ((0, 'shared-helper-package-first', 'bytes', 'observe'),)),
    ('tools/coverage_loop_proofs.py', '_historical_reviewed_nonempty_loops',
     'relative_source(root, path.as_posix(), **operation_args).read_text()', 1, ((0, '853:1', 'default', 'observe'),)),
    ('tools/coverage_loop_proofs.py', '_construction_boundary_callers',
     'relative_source(root, path.as_posix(), **operation_args).read_text()', 1, ((0, '1029:1', 'default', 'observe'),)),
)


def _seed_dispatch_body_contract(node):
    """Keep the physical seed read sites in the exact extracted old body."""
    value = copy.deepcopy(node)
    if value.name != '_verify_seed_body':
        raise AssertionError('unreviewed seed observation owner')
    value.name = 'verify'
    def encode(item):
        if isinstance(item, ast.AST):
            return [type(item).__name__, [[name, encode(getattr(item, name))]
                    for name in item._fields]]
        if isinstance(item, list):
            return [encode(child) for child in item]
        if item is None or type(item) in (str, int, float, bool):
            return item
        raise AssertionError('unlisted seed AST primitive')
    actual = hashlib.sha256(json.dumps(encode(value), separators=(',', ':')).encode()).hexdigest()
    if actual != '3b0e4d0db954ccb0522fbc4f4345ac0992850e9d73e67410a4a4ea37d41102e0':
        raise AssertionError('complete original seed dispatch body drift')


@contextmanager
def _operation_reached_bindings(case, code_root, physical_root, cores):
    """Observe reviewed read/comparison seams without changing their values.

    This is one bounded test-local ledger, not a replacement filesystem or
    authority. Frames, objects and stream chunks are kept until this one owner
    finishes; no object-id-only association or extra source sample is used.
    """
    from contextlib import ExitStack
    from functools import wraps
    import types

    sites, trees, compiled_modules, positions, families = {}, {}, {}, {}, {}
    for relative, owner, expression, expected_count, selections in _OPERATION_REACHED_READ_SPECS:
        filename = str((Path(code_root)/relative).absolute())
        if filename not in trees:
            source_raw = Path(filename).read_bytes()
            trees[filename] = ast.parse(source_raw, filename=filename)
            compiled_modules[filename] = compile(source_raw, filename, 'exec',
                dont_inherit=True, optimize=sys.flags.optimize)
        node = trees[filename]
        for component in owner.split('.'):
            matches = [item for item in node.body if getattr(item, 'name', None) == component]
            case.assertEqual(len(matches), 1, (relative, owner))
            node = matches[0]
        if relative == 'tools/coverage_loop_proofs.py' and owner in (
                '_historical_reviewed_nonempty_loops', 'guarded_loop_proof'):
            _coverage_current_discriminator_contract(node)
        if relative == 'tools/carla_lane_oracle/seed_count_contracts.py':
            if owner == '_verify_seed_body':
                _seed_dispatch_body_contract(node)
            elif owner == 'reviewed_text':
                _seed_supplied_read_contract(node)
            elif owner == 'verify_score_caller_inventory':
                _station_census_read_contract(node)
        key = ast.dump(ast.parse(expression, mode='eval').body, include_attributes=False)
        calls = sorted((item for item in ast.walk(node) if isinstance(item, ast.Call)
                        and ast.dump(item, include_attributes=False) == key),
                       key=lambda item: (item.lineno, item.col_offset))
        case.assertEqual(len(calls), expected_count, (relative, owner, expression))
        if (relative, owner, expression) == (
                'tools/coverage_loop_proofs.py', '_reviewed_dependency_hashes', 'path.read_bytes()'):
            # Both successor final rereads must observe the physical value
            # before equality; the typed one precedes historical projection.
            parents = {child: parent for parent in ast.walk(node)
                       for child in ast.iter_child_nodes(parent)}
            for index in (1, 3):
                observation = parents[calls[index]]
                expected = ast.parse('_coverage_observe_bytes(root, name, path.read_bytes(), '
                                     '_operation=_operation)', mode='eval').body
                case.assertEqual(ast_key(observation), ast_key(expected))
                case.assertIsInstance(parents[observation], ast.Compare)
                case.assertEqual(ast_key(parents[observation].comparators[0]),
                                 ast_key(ast.Name(id='raw', ctx=ast.Load())))
        for index, suffix, mode, binding in selections:
            call = calls[index]
            if suffix.startswith(('typed-', 'pr760-')):
                parents = {child: parent for parent in ast.walk(node)
                           for child in ast.iter_child_nodes(parent)}
                observed = parents[call]
                case.assertIsInstance(observed, ast.Call)
                if (relative, owner, suffix) == (
                        'tools/carla_lane_oracle/check_sampled_values.py', 'verify',
                        'typed-sampled-initial-batch'):
                    # verify later binds a local named source. The physical
                    # batch must use its unshadowed module import explicitly.
                    case.assertEqual(ast.unparse(observed.func), '_typed_source._observe_text')
                else:
                    case.assertIn(ast.unparse(observed.func), ('_observe_bytes', '_observe_text', '_coverage_observe_bytes',
                        '_coverage_observe_text', 'source._observe_text', 'audit._observe_bytes',
                        'full_audit._observe_bytes'))
                case.assertIs(observed.args[2], call)
                operation_keywords = [keyword.value for keyword in observed.keywords if keyword.arg == '_operation']
                case.assertEqual([ast_key(value) for value in operation_keywords],
                                 [ast_key(ast.Name(id='_operation', ctx=ast.Load()))])
            if mode == 'default_or_map_supplied':
                case.assertEqual((relative, owner),
                    ('tools/carla_lane_oracle/lane_order_contracts.py', 'inventory'))
                parents = {child: parent for parent in ast.walk(node)
                           for child in ast.iter_child_nodes(parent)}
                observation = parents[call]
                case.assertIsInstance(observation, ast.Call)
                case.assertIsInstance(observation.func, ast.Name)
                case.assertEqual(observation.func.id, '_observe_text')
                supplied = [keyword.value for keyword in observation.keywords
                            if keyword.arg == 'supplied']
                case.assertEqual(len(supplied), 1)
                case.assertEqual(ast.dump(supplied[0], include_attributes=False),
                    ast.dump(ast.parse("rel.as_posix() == 'extensions/carla/map.mojo'",
                                       mode='eval').body, include_attributes=False))
            span = (call.lineno, call.end_lineno, call.col_offset, call.end_col_offset)
            case.assertNotIn((filename, span), sites)
            sites[filename, span] = (relative + ':' + suffix, owner, mode, binding)

    # The one retained local-S comparator is deliberately not treated as a
    # generic _observe call. Keep its exact endpoint-paired chained predicate.
    cache_filename = str((Path(code_root)/'tools/carla_lane_oracle/cache_key_contracts.py').absolute())
    cache_tree = trees[cache_filename]
    inventory_node = next(item for item in cache_tree.body
                          if isinstance(item, ast.FunctionDef) and item.name == 'inventory')
    local_predicate = ast.parse(_CURRENT_LOCAL_S_PREDICATE, mode='eval').body
    predicate_key = ast.dump(local_predicate, include_attributes=False)
    guarded_comparisons = [item for item in ast.walk(inventory_node)
        if isinstance(item, ast.Call) and isinstance(item.func, ast.Name)
        and item.func.id == 'require' and len(item.args) == 2
        and ast.dump(item.args[0], include_attributes=False) == predicate_key
        and isinstance(item.args[1], ast.Constant)
        and item.args[1].value == 'unreviewed supplied score-helper source']
    case.assertEqual(len(guarded_comparisons), 1)
    case.assertIsInstance(guarded_comparisons[0].args[0], ast.BoolOp)
    case.assertIsInstance(guarded_comparisons[0].args[0].op, ast.And)
    local_call = guarded_comparisons[0].args[0].values[0].left
    local_span = (local_call.lineno, local_call.end_lineno,
                  local_call.col_offset, local_call.end_col_offset)

    reads, streams, observation_events, match_events, primitive_entries = [], [], [], [], []
    boundary_entries = []
    leases = []
    read_index, stream_index, stream_value_index, publish_replays = {}, {}, {}, {}
    operation_types = tuple(core._InvariantInputs for core in cores)
    lease_types = tuple(core._BorrowedCacheInputs for core in cores)

    def span(frame):
        code = frame.f_code
        if code not in positions:
            positions[code] = tuple(code.co_positions())
        index = frame.f_lasti // 2
        return positions[code][index] if 0 <= index < len(positions[code]) else None

    def original_family(frame, owner):
        key = (id(frame.f_globals), owner)
        if key not in families:
            components = owner.split('.')
            function = frame.f_globals.get(components[0])
            for component in components[1:]:
                function = getattr(function, component, None)
            function = inspect.unwrap(function)
            case.assertIs(getattr(function, '__globals__', None), frame.f_globals)
            filename = str(Path(frame.f_globals['__file__']).absolute())
            compiled_owner = compiled_modules[filename]
            for component in components:
                matches = [value for value in compiled_owner.co_consts
                           if isinstance(value, types.CodeType) and value.co_name == component]
                case.assertEqual(len(matches), 1, ('unique checked-source owner', filename, owner))
                compiled_owner = matches[0]
            case.assertEqual(function.__code__, compiled_owner,
                             ('live original equals checked source', filename, owner))
            pending, codes = [function.__code__], set()
            while pending:
                code = pending.pop()
                codes.add(code)
                pending.extend(value for value in code.co_consts if isinstance(value, types.CodeType))
            families[key] = codes
        return families[key]

    def site(frame):
        filename = frame.f_globals.get('__file__')
        if type(filename) is not str:
            return None
        filename = str(Path(filename).absolute())
        found = sites.get((filename, span(frame)))
        if found is None:
            return None
        case.assertIn(frame.f_code, original_family(frame, found[1]), found[0])
        return found

    def operation_at(frame, found):
        # A comprehension may hold root/path but not the explicit operation.
        # Only walk within this exact original function's nested code family.
        allowed = original_family(frame, found[1])
        namespace = frame.f_globals
        while frame is not None and frame.f_globals is namespace and frame.f_code in allowed:
            values = frame.f_locals
            if '_operation' in values:
                value = values['_operation']
                if type(value) in operation_types:
                    return value
                if value is not None:
                    return None
            view = values.get('_inputs', values.get('self'))
            if type(view) in lease_types:
                return view._operation
            if type(view) in operation_types:
                return view
            frame = frame.f_back
        return None

    def relative(path):
        return Path(path).relative_to(physical_root).as_posix()

    def caller_chain(frame):
        result = []
        while frame is not None:
            filename = frame.f_globals.get('__file__')
            if type(filename) is str:
                filename = str(Path(filename).absolute())
                if filename in trees:
                    result.append((Path(filename).relative_to(code_root).as_posix(),
                                   frame.f_code.co_qualname, frame.f_lineno))
            frame = frame.f_back
        return result

    def lease_number(view):
        for index, previous in enumerate(leases):
            if previous is view:
                return index
        case.assertIn(type(view), lease_types)
        leases.append(view)
        return len(leases) - 1

    def record_read(found, operation, path, value, frame, phase=None):
        name = relative(path)
        mode = found[2]
        if mode == 'default_or_map_supplied':
            mode = 'supplied_default' if name == 'extensions/carla/map.mojo' else 'default'
        item = {'site': found[0], 'mode': mode, 'binding': found[3],
                'operation': operation, 'path': name, 'value': value,
                'frame': frame, 'code': frame.f_code, 'globals': frame.f_globals,
                'owner': found[1], 'span': span(frame),
                'phase': phase or operation._state, 'sequence': len(reads),
                'observed': False, 'matched': False, 'local_compared': False}
        if found[3] in ('local_s', 'lease'):
            item['caller_chain'] = caller_chain(frame)
        if found[3] == 'local_s':
            item['lease_number'] = lease_number(frame.f_locals['_inputs'])
        reads.append(item)
        read_index[id(operation), item['path'], item['mode'], id(value)] = item
        return item

    def latest(operation, path, value, mode):
        item = read_index.get((id(operation), path, mode, id(value)))
        # The index accelerates a reference comparison; the retained objects,
        # not their recyclable ids, establish the actual association.
        return item if item is not None and item['operation'] is operation and item['value'] is value else None

    def joined_stream(operation, path, value):
        item = stream_index.get((id(operation), path))
        if (item is not None and item['operation'] is operation and item['eof']
                and type(value) is bytes and value == item['composed']):
            frame = sys._getframe(1)
            while frame is not None:
                if frame is item['owner_frame']:
                    return item
                frame = frame.f_back
        return None

    def publish_occurrence(operation, path, value, mode, frame):
        publish = inspect.unwrap(type(operation)._publish)
        if frame.f_code is not publish.__code__ or frame.f_globals is not publish.__globals__:
            return None, None
        case.assertIn(frame.f_code, original_family(frame, '_InvariantInputs._publish'))
        case.assertIs(frame.f_locals['self'], operation)
        case.assertIs(frame.f_locals['value'], value)
        case.assertEqual((frame.f_locals['path'], frame.f_locals['mode']), (path, mode))
        case.assertEqual(operation._state, 'active')
        case.assertTrue(operation._capturing)
        replay = publish_replays.setdefault(id(frame), {'frame': frame, 'next': 0})
        case.assertIs(replay['frame'], frame)
        queued = operation._observations[replay['next']]
        case.assertEqual((queued[0], queued[2]), (path, mode))
        case.assertIs(queued[1], value)
        return queued, replay

    def queued_stream(operation, path, value, queued):
        if queued is None:
            return None
        candidates = [item for item in stream_value_index.get((id(operation), path, id(value)), ())
                      if item['operation'] is operation and item['observed_value'] is value
                      and item['observed'] and item['queued_tuple'] is queued
                      and not item['matched']]
        case.assertLessEqual(len(candidates), 1, 'ambiguous retained stream observation')
        if not candidates:
            return None
        return candidates[0]

    def reader(original):
        @wraps(original)
        def read(path, *args, **kwargs):
            frame = sys._getframe(1)
            found = site(frame)
            operation = operation_at(frame, found) if found is not None else None
            if operation is not None:
                entry = {'frame': frame, 'operation': operation, 'site': found[0], 'returned': False}
                primitive_entries.append(entry)
            value = original(path, *args, **kwargs)
            if operation is not None:
                case.assertNotEqual(found[3], 'local_raw_residual',
                    'cleanup local comparator entered an owned route; review its binding')
                case.assertIn(found[3], ('observe', 'local_s', 'base'))
                entry['returned'] = True
                record_read(found, operation, path, value, frame)
            return value
        return read

    def observer(original):
        @wraps(original)
        def observed(operation, root, path, value, mode):
            item = latest(operation, path, value, mode)
            stream = joined_stream(operation, path, value) if mode == 'bytes' else None
            phase = operation._state
            queued_count = len(operation._observations) if stream is not None and phase == 'pending' else None
            event = {'operation': operation, 'path': path, 'mode': mode, 'phase': phase,
                     'read_sequence': item['sequence'] if item is not None else None,
                     'returned': False}
            observation_events.append(event)
            result = original(operation, root, path, value, mode)
            event['returned'] = True
            if item is not None:
                item['observed'] = True
            if stream is not None:
                stream['observed'] = True
                stream['observed_value'] = value
                stream['observation_phase'] = phase
                stream['queued_tuple'] = None
                if queued_count is not None:
                    case.assertEqual(len(operation._observations), queued_count + 1)
                    queued = operation._observations[queued_count]
                    case.assertEqual((queued[0], queued[2]), (path, mode))
                    case.assertIs(queued[1], value)
                    stream['queued_tuple'] = queued
                    stream['queued_index'] = queued_count
                stream_value_index.setdefault((id(operation), path, id(value)), []).append(stream)
            return result
        return observed

    def matcher(original):
        @wraps(original)
        def matched(operation, root, path, value, mode):
            item = latest(operation, path, value, mode)
            queued, replay = publish_occurrence(operation, path, value, mode, sys._getframe(1))
            stream = joined_stream(operation, path, value) if mode == 'bytes' else None
            origin = 'live_original_frame' if stream is not None else None
            if stream is None and mode == 'bytes':
                stream = queued_stream(operation, path, value, queued)
                if stream is not None:
                    origin = 'queued_publish_replay'
            event = {'operation': operation, 'path': path, 'mode': mode,
                     'read_sequence': item['sequence'] if item is not None else None,
                     'returned': False}
            match_events.append(event)
            result = original(operation, root, path, value, mode)
            event['returned'] = True
            if replay is not None:
                replay['next'] += 1
            if item is not None:
                item['matched'] = True
            if stream is not None:
                stream['matched'] = True
                stream['comparison_phase'] = operation._state
                stream['comparison_origin'] = origin
            return result
        return matched

    def base_observer(original):
        @wraps(original)
        def observed(view, owner, root, path):
            operation = view._operation if type(view) in lease_types else (
                view if type(view) in operation_types else None)
            start = len(reads)
            if operation is not None:
                event = {'operation': operation, 'kind': 'base', 'returned': False}
                boundary_entries.append(event)
            value = original(view, owner, root, path)
            if operation is not None:
                event['returned'] = True
                found = [item for item in reads[start:] if item['operation'] is operation
                         and item['path'] == path and item['value'] is value
                         and item['binding'] == 'base']
                case.assertEqual(len(found), 1, ('base physical/comparison join', path))
                found[0]['matched'] = True
                if type(view) in operation_types:
                    found[0]['phase'] = 'outer_finalizer'
            return value
        return observed

    def lease_observer(original):
        @wraps(original)
        def observed(view, owner, root, path):
            frame = sys._getframe(1)
            found = site(frame)
            operation = view._operation
            start = len(reads)
            event = {'operation': operation, 'kind': 'lease', 'returned': False}
            boundary_entries.append(event)
            value = original(view, owner, root, path)
            event['returned'] = True
            if found is not None:
                case.assertEqual(found[3], 'lease')
                physical = [item for item in reads[start:] if item['operation'] is operation
                            and item['path'] == path and item['value'] is value
                            and item['binding'] == 'base' and item['matched']]
                case.assertEqual(len(physical), 1, ('lease physical/comparison join', found[0]))
                item = record_read(found, operation, Path(root)/path, value, frame)
                item['matched'] = True
                item['physical_sequence'] = physical[0]['sequence']
                item['lease_number'] = lease_number(view)
            return value
        return observed

    def token_observer(original):
        @wraps(original)
        def tokens(text, *args, **kwargs):
            frame = sys._getframe(1)
            selected = (frame.f_globals.get('__file__') is not None
                        and str(Path(frame.f_globals['__file__']).absolute()) == cache_filename
                        and span(frame) == local_span
                        and type(frame.f_locals.get('_inputs')) in lease_types)
            if selected:
                case.assertIn(frame.f_code, original_family(frame, 'inventory'))
                view = frame.f_locals.get('_inputs')
                case.assertIn(type(view), lease_types)
                item = latest(view._operation, 'extensions/carla/map.mojo', text,
                              'supplied_default')
                case.assertIsNotNone(item, 'local-S must consume the original retained text object')
                case.assertEqual(item['binding'], 'local_s')
                case.assertIs(item['frame'], frame)
                item['lease'] = view
                event = {'operation': view._operation, 'kind': 'local_s', 'returned': False}
                boundary_entries.append(event)
            value = original(text, *args, **kwargs)
            if selected:
                event['returned'] = True
                item['local_compared'] = True
            return value
        return tokens

    with ExitStack() as stack:
        original_open = Path.open
        @wraps(original_open)
        def opened(path, *args, **kwargs):
            frame = sys._getframe(1)
            found = site(frame)
            operation = operation_at(frame, found) if found is not None else None
            if operation is not None and found[3] == 'stream_open':
                entry = {'frame': frame, 'operation': operation, 'site': found[0], 'returned': False}
                primitive_entries.append(entry)
            stream = original_open(path, *args, **kwargs)
            if operation is None or found[3] != 'stream_open':
                return stream
            entry['returned'] = True
            case.assertEqual(args, ('rb',))
            case.assertEqual(kwargs, {})
            item = {'operation': operation, 'path': relative(path), 'open_site': found[0],
                    'owner': found[1], 'mode': found[2], 'phase': operation._state,
                    'open_code': frame.f_code, 'globals': frame.f_globals,
                    'open_span': span(frame),
                    'read_site': None, 'chunks': [], 'requests': [], 'eof': False,
                    'observed': False, 'matched': False, 'stream': stream,
                    'owner_frame': frame, 'read_calls': [], 'composed': None}
            streams.append(item)
            stream_index[id(operation), item['path']] = item
            original_read = stream.read
            def read(size):
                read_frame = sys._getframe(1)
                read_site = site(read_frame)
                case.assertIsNotNone(read_site, 'stream must read in its original lambda')
                case.assertEqual(read_site[3], 'stream_read')
                case.assertFalse(item['eof'], 'no read after original EOF')
                event = {'frame': read_frame, 'size': size, 'returned': False,
                         'owner': read_site[1], 'mode': read_site[2],
                         'phase': operation._state, 'code': read_frame.f_code,
                         'globals': read_frame.f_globals, 'span': span(read_frame)}
                item['read_calls'].append(event)
                value = original_read(size)
                event['returned'] = True
                case.assertIs(type(value), bytes)
                item['read_site'] = read_site[0]
                item['requests'].append(size)
                item['chunks'].append(value)
                item['eof'] = value == b''
                if item['eof']:
                    item['composed'] = b''.join(item['chunks'])
                return value
            # Keep the original stream object and its original context manager.
            # Shadow only this instance's read, calling the original exactly once.
            stack.enter_context(patch.object(stream, 'read', read))
            return stream

        stack.enter_context(patch.object(Path, 'read_bytes', reader(Path.read_bytes)))
        stack.enter_context(patch.object(Path, 'read_text', reader(Path.read_text)))
        stack.enter_context(patch.object(Path, 'open', opened))
        for core in cores:
            stack.enter_context(patch.object(core._InvariantInputs, '_observe', observer(core._InvariantInputs._observe)))
            stack.enter_context(patch.object(core._InvariantInputs, '_match', matcher(core._InvariantInputs._match)))
            stack.enter_context(patch.object(core._CacheInputs, 'observe_bytes', base_observer(core._CacheInputs.observe_bytes)))
            stack.enter_context(patch.object(core._BorrowedCacheInputs, 'observe_bytes', lease_observer(core._BorrowedCacheInputs.observe_bytes)))
        sources = {id(core.source): core.source for core in cores}
        for module in sources.values():
            stack.enter_context(patch.object(module, 'token_sha256', token_observer(module.token_sha256)))

        def summarize(operation, route):
            actual = [item for item in reads if item['operation'] is operation]
            case.assertTrue(actual, ('no reviewed physical boundary reached', route))
            for item in actual:
                with case.subTest(route=route, site=item['site'], sequence=item['sequence']):
                    if item['binding'] == 'local_s':
                        case.assertTrue(item['local_compared'])
                        case.assertIn(type(item['lease']), lease_types)
                        case.assertEqual(item['lease']._state, 'closed')
                    elif item['binding'] in ('base', 'lease'):
                        case.assertTrue(item['matched'])
                    else:
                        case.assertTrue(item['observed'], 'original returned value was not observed')
                        case.assertTrue(item['matched'], 'current queued/active value never matched its image')
            actual_streams = [item for item in streams if item['operation'] is operation]
            for item in actual_streams:
                diagnostic = {key: item.get(key) for key in ('path', 'open_site', 'read_site',
                    'phase', 'observation_phase', 'queued_index', 'comparison_origin', 'comparison_phase')}
                diagnostic['route'] = route
                case.assertTrue(item['eof'], diagnostic)
                case.assertTrue(item['requests'], diagnostic)
                case.assertTrue(all(size == 1 << 20 for size in item['requests']), diagnostic)
                case.assertTrue(item['stream'].closed, diagnostic)
                case.assertTrue(item['observed'], diagnostic)
                case.assertTrue(item['matched'], diagnostic)
                case.assertIs(type(item['observed_value']), bytes, diagnostic)
                case.assertEqual(item['comparison_phase'], 'active', diagnostic)
                case.assertEqual(item['comparison_origin'], 'queued_publish_replay'
                    if item['observation_phase'] == 'pending' else 'live_original_frame', diagnostic)
                if item['observation_phase'] == 'pending':
                    case.assertIs(item['queued_tuple'][1], item['observed_value'], diagnostic)
                case.assertTrue(all(event['returned'] for event in item['read_calls']), diagnostic)
            reached = {item['site'] for item in actual}
            for item in actual_streams:
                reached.update((item['open_site'], item['read_site']))
            expected = {item[0] for item in sites.values()}
            case.assertTrue(any(event['operation'] is operation for event in observation_events))
            for events in (primitive_entries, observation_events, match_events, boundary_entries):
                case.assertTrue(all(event['returned'] for event in events if event['operation'] is operation))
            bindings = {}
            for item in actual:
                key = (item['site'], item['owner'], item['globals'].get('__name__'),
                       item['code'].co_qualname, item['span'])
                counts = bindings.setdefault(key, Counter())
                counts[item['path'], item['mode'], item['phase']] += 1
            for item in actual_streams:
                key = (item['open_site'], item['owner'], item['globals'].get('__name__'),
                       item['open_code'].co_qualname, item['open_span'])
                bindings.setdefault(key, Counter())[item['path'], item['mode'], item['phase']] += 1
                for event in item['read_calls']:
                    key = (item['read_site'], event['owner'], event['globals'].get('__name__'),
                           event['code'].co_qualname, event['span'])
                    bindings.setdefault(key, Counter())[
                        item['path'], event['mode'], event['phase']] += 1
            per_site = {}
            for (site_id, owner, namespace, code_name, call_span), counts in sorted(bindings.items()):
                per_site.setdefault(site_id, []).append({
                    'owner': owner, 'namespace': namespace, 'code': code_name,
                    'call_span': list(call_span),
                    'path_mode_phase_counts': [[path, mode, phase, count]
                        for (path, mode, phase), count in sorted(counts.items())]})
            lease_groups = []
            for number in sorted({item['lease_number'] for item in actual if 'lease_number' in item}):
                items = [item for item in actual if item.get('lease_number') == number]
                lease_groups.append({'lease': number,
                    'positions': sorted({item['site'] for item in items if item['binding'] == 'lease'}),
                    'local_supplied_map_seen': any(item['binding'] == 'local_s' for item in items),
                    'caller_chains': [json.loads(chain) for chain in sorted({
                        json.dumps(item['caller_chain']) for item in items})]})
            return {'route': route, 'reached_sites': sorted(reached),
                    'residual_unreached_sites': sorted(expected - reached),
                    'site_bindings': per_site,
                    'mode_counts': dict(Counter(item['mode'] for item in actual)),
                    'phase_counts': dict(Counter(item['phase'] for item in actual)),
                    'borrowed_positions': sorted({item['site'] for item in actual if item['binding'] == 'lease'}),
                    'borrowed_lease_groups': lease_groups,
                    'local_supplied_map_seen': any(item['binding'] == 'local_s' for item in actual),
                    'local_supplied_caller_chains': [json.loads(chain) for chain in sorted({
                        json.dumps(item['caller_chain']) for item in actual if item['binding'] == 'local_s'})],
                    'pending_accepted_pair_seen': any(item['phase'] == 'pending'
                        and item['site'].endswith('accepted_successor_contracts.py:117:1') for item in actual),
                    'stream_binding_counts': [
                        [path, observation_phase, comparison_origin, comparison_phase, count]
                        for (path, observation_phase, comparison_origin, comparison_phase), count
                        in sorted(Counter((item['path'], item['observation_phase'],
                            item['comparison_origin'], item['comparison_phase'])
                            for item in actual_streams).items())],
                    'original_streams': len(actual_streams)}
        try:
            yield summarize
        finally:
            # Release retained values and executing frames after this owner,
            # including a failed positive run. None survives into another call.
            read_index.clear()
            stream_index.clear()
            stream_value_index.clear()
            publish_replays.clear()
            leases.clear()
            for events in (reads, streams, observation_events, match_events,
                           primitive_entries, boundary_entries):
                events.clear()


class OperationReachedBindingControls(unittest.TestCase):
    """Positive real-owner value provenance; residual sites stay explicit."""
    # Reuse helper methods only. Do not inherit the nineteen lifecycle tests.
    setUp = BoundedOwnerCurrentControls.setUp
    audit = BoundedOwnerCurrentControls.audit
    coverage = BoundedOwnerCurrentControls.coverage
    assert_closed = BoundedOwnerCurrentControls.assert_closed
    assert_one_owner = BoundedOwnerCurrentControls.assert_one_owner

    def test_current_cold_routes_preserve_consumed_value_bindings(self):
        self._cold_routes_preserve_consumed_value_bindings(pr760=True)

    def test_common758_cold_routes_preserve_consumed_value_bindings(self):
        import _full_audit_test_fixtures as fixtures
        self.root = fixtures.copy_common758_boundary_root(self, self.root)
        self._cold_routes_preserve_consumed_value_bindings(pr760=False)

    def _cold_routes_preserve_consumed_value_bindings(self, *, pr760):
        examples = {path: (self.root/path).read_bytes()
                    for path in cleanup.pr760_stage.EXAMPLE_PATHS}
        self.assertIs(cleanup._pr760_image_selected(examples), pr760)
        import winner_sign_contracts as winner
        import check_runtime_support as runtime
        import check_sampled_values as sampled
        loops, coverage_core = self.coverage()
        code_root = Path(__file__).resolve().parents[2]
        routes = (
            ('invariant', cleanup, lambda: invariant.verify(self.root)),
            ('winner', cleanup, lambda: winner.verify(self.root)),
            ('runtime', cleanup, lambda: runtime.verify(self.root)),
            ('sampled', cleanup, lambda: sampled.verify(self.root)),
            ('map_loops', coverage_core, lambda: loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map')),
            ('rtree_loops', coverage_core, lambda: loops.reviewed_nonempty_loops(self.root, 'extensions/carla/rtree')),
        )
        owners = []
        for kind, core, run in routes:
            with self.subTest(owner=kind):
                with self.audit(core) as events, _operation_reached_bindings(
                        self, code_root, self.root, (cleanup, coverage_core)) as summarize:
                    result = run()
                    self.assertTrue(result)
                    operation = self.assert_one_owner(events, kind, core)
                    self.assertTrue(all(operation is not previous for previous in owners))
                    owners.append(operation)
                    report = summarize(operation, kind)
                    prefix = 'tools/carla_lane_oracle/full_audit_cleanup_contracts.py:'
                    # Both fixed physical cohorts retain their own obligations.
                    # A PR760 early return cannot claim the old sites were read.
                    typed_sites = {prefix + suffix for suffix in (
                        'typed-marker-first', 'typed-source-first',
                        'typed-bound-input-first', 'typed-bound-input-final')}
                    candidate_site = prefix + 'pr760-candidate-physical'
                    reached, residual = (set(report['reached_sites']),
                                         set(report['residual_unreached_sites']))
                    self.assertIn(prefix + 'pr760-cohort-physical', reached)
                    self.assertLessEqual(typed_sites, residual if pr760 else reached)
                    self.assertIn(candidate_site, reached if pr760 else residual)
                    if pr760:
                        # The candidate's one observer serves both first and
                        # terminal reads. Require both consumed map values to
                        # join this cold owner's pending publication, rather
                        # than treating one reached AST address as two reads.
                        map_reads = [row
                            for binding in report['site_bindings'][candidate_site]
                            for row in binding['path_mode_phase_counts']
                            if row[0] == 'extensions/carla/map.mojo']
                        self.assertEqual(map_reads, [
                            ['extensions/carla/map.mojo', 'bytes', 'pending', 2]])
                    if pr760 or kind in ('invariant', 'winner', 'runtime', 'sampled'):
                        for suffix in ('typed-provenance-first', 'typed-provenance-final'):
                            self.assertIn(prefix + suffix, reached)
                    if kind in ('runtime', 'sampled'):
                        self.assertTrue({kind, 'invariant'} <= events['frames'])
                        self.assertEqual(set(result['typed_boundary_successors']), set(cleanup.typed_boundary.SOURCE_PATHS))
                        for path, edge in result['typed_boundary_successors'].items():
                            self.assertEqual(edge['after_sha256'], hashlib.sha256((self.root/path).read_bytes()).hexdigest())
                        for suffix in ('typed-sum2-source-batch', 'typed-sum2-pin', 'typed-sum2-interval'):
                            self.assertIn('tools/carla_lane_oracle/sum2_contracts.py:' + suffix, report['reached_sites'])
                    if kind == 'runtime':
                        for suffix in ('typed-heading-producer', 'typed-heading-consumers', 'typed-heading-eligibility'):
                            self.assertIn('tools/carla_lane_oracle/heading_correspondence.py:' + suffix, report['reached_sites'])
                        for suffix in ('typed-runtime-body', 'typed-runtime-callers', 'typed-runtime-reference'):
                            self.assertIn('tools/carla_lane_oracle/optional_runtime_contracts.py:' + suffix, report['reached_sites'])
                    if kind == 'sampled':
                        for suffix in ('typed-sampled-initial-batch', 'typed-sampled-final-sources'):
                            self.assertIn('tools/carla_lane_oracle/check_sampled_values.py:' + suffix, report['reached_sites'])
                    if kind == 'map_loops':
                        self.assertIn('tools/coverage_loop_proofs.py:typed-source-final', report['reached_sites'])
                    # These shared-helper theorem branches remain outside the
                    # six owned routes in either cohort. Never report them as exercised owner
                    # observations merely because their AST addresses exist.
                    self.assertLessEqual({
                        'tools/coverage_loop_proofs.py:' + suffix for suffix in (
                            'shared-helper-source-final',
                            'shared-helper-checker-first', 'shared-helper-checker-final',
                            'shared-helper-provider-first', 'shared-helper-provider-final',
                            'shared-helper-package-first')},
                        set(report['residual_unreached_sites']))
                print('OPERATION_REACHED_BINDINGS ' + json.dumps(report, sort_keys=True))



# Distinct consumed-input mechanisms. Source-only proposal; gate/authority paths
# are always original. See the separately frozen 8-method / 18-owner plan.


# Exact test-only PR760 implementation successor. Historical inverse data and
# whole-file predecessor digests below remain unchanged.
_PR760_CHECKER_SOURCE_EDGES = {'coverage_loop_proofs.py': {'after_sha256': '21e3a9637a69c6abbf27e9c8dd193a1addf7ed8537dd8f2734c35ff1a468304d',
 'before_sha256': '28ff5cfe131ee2812d0a71a4a525ef3c962e5fa80442196dbb4b4cecfdb3d1ed',
 'edits': ((23, 24, (), ('import types\n',)),
           (498,
            508,
            (),
            ('# PR760 local literal successor. The retained-groom theorem below is unchanged.\n',
             'HAIR_LITERAL_SUCCESSOR = ({\n',
             "    'extensions/humanoid/skeleton/head/hair/strands.mojo':\n",
             "        '058c0e6fbfce95ee97c79247622185de968c8de5e0ad23240d667da13776404f',\n",
             '}, (\n',
             "    (229, 'literal-range', 2, 2, 'range(2)', 'hair-upload-two-endpoints'),\n",
             "    (235, 'literal-range', 3, 3, 'range(3)', 'hair-upload-three-channels'),\n",
             '))\n',
             '\n',
             '\n')),
           (805,
            806,
            ('def repaired_density_loops(root, *, include_roots=()):\n',),
            ('def repaired_density_loops(root, *, include_roots=(), _operation=None):\n',)),
           (807,
            812,
            (),
            ("    operation_args = {} if _operation is None else {'_operation': _operation}\n",
             "    stream_args = {} if _operation is None else {'_operation': _operation, '_root': "
             'root}\n',
             '    if _operation is not None:\n',
             '        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
             '        cleanup._operation_include_context(_operation, root, include_roots)\n')),
           (813,
            815,
            ('        if file_sha256(relative_source(root, DENSITY_SOURCE)) != '
             'DENSITY_AFTER_SHA256:\n',),
            ('        if file_sha256(relative_source(root, DENSITY_SOURCE, **operation_args),\n',
             '                       **stream_args) != DENSITY_AFTER_SHA256:\n')),
           (818,
            820,
            ('    if not all(_density_stdlib_unshadowed(path) for path in (root, '
             '*include_roots)):\n',),
            ('    if not all(_density_stdlib_unshadowed(path, **operation_args)\n',
             '               for path in (root, *include_roots)):\n')),
           (828,
            1281,
            (),
            ('\n',
             '\n',
             '# Fixed physical density/groom import closure on the reviewed PR760 image.\n',
             '# These bytes bind local domination proofs only, never whole CARLA admission.\n',
             "DENSITY760_INPUTS = {'core/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'core/assets.mojo': "
             "'5d5394df10b330767970b8585f9707673fb1ee6ef0f269ec430b8e2ffa54f89b',\n",
             " 'core/background.mojo': "
             "'0d43517034157e341071cd96448901e0483480053e26df93dca3521680446039',\n",
             " 'core/binary.mojo': "
             "'2d3a5a121ebcd919fc987b5972eb1071100bdd9dc397695c789561cc275e59d7',\n",
             " 'core/buffer_attribute.mojo': "
             "'8b0dfe3d758bf4e323805f5a3c513a3102f7fde86f7ebad418db3264295ceaed',\n",
             " 'core/buffer_geometry.mojo': "
             "'9e09d806746e717207b5d20bff79369b5cc6357bcde1d9a609792c0095668176',\n",
             " 'core/extent.mojo': "
             "'50f3c4fcc55b672ab1d42505cf70baeb3aae85ebf915927369246ab7e214a023',\n",
             " 'core/fog.mojo': "
             "'8026f0db83e2eef31d0e63793f65a449cb9eebae917e081e950a851ab98ca66c',\n",
             " 'core/gaussian_splat_utils.mojo': "
             "'63e4123f61a1e8ae6845b0eae449b5c173368bdf0ca691d7327255d33c8533b3',\n",
             " 'core/geometry_store.mojo': "
             "'c42cde4b1e8c5668b138d462a997ac23d36cfe9789cddd22eaee142a2cec6f06',\n",
             " 'core/interleaved_buffer.mojo': "
             "'2d9b3760a4e0d9d227d38a91ef4917501ffecdedfdf60bf0e8ccacd0e60de597',\n",
             " 'core/layers.mojo': "
             "'ebc7a81fcc9f8b7d36ab3cecc46208f078797b7ac108317baaac9a9d44cacb7b',\n",
             " 'core/morph.mojo': "
             "'8c84adfbad9405ae1f582ba6e3f6a9b39db14bbf8ac20e96bee1d03e9d6be47d',\n",
             " 'core/object3d.mojo': "
             "'749062c89390981215d7f4d9fb60a4557291b734b19f93571d4e46e1996cb203',\n",
             " 'core/order.mojo': "
             "'4c7a1e85fbb2ceffa9c6d59a4294517057b1580dfd7b0e2f07b1ec99b59096b7',\n",
             " 'core/ordinal.mojo': "
             "'020ae821e6e4d6f596174a672f70876d43a13d5a397bd42ef1b2152ac736bb90',\n",
             " 'core/scene.mojo': "
             "'4eb55a160cd53e4db34a51bc6fc48e7427cb10ffa4ffa72e191519dee76e8b20',\n",
             " 'core/search.mojo': "
             "'1bc8bedd8b4d91ff3a455fa8232dc36fdfdeae0b7f61adf8d41ee16467b8df72',\n",
             " 'core/user_data.mojo': "
             "'bec1a6fb8cf0cc43536c0e347a5e302fa225988a47dcd5001b30fb9dd443d5a5',\n",
             " 'extensions/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/anatomy/__init__.mojo': "
             "'e07a6d503cb1d532b4dac54ceca76d6ff2b7bbddea0af02d17f55b64143ee1cf',\n",
             " 'extensions/anatomy/soft_tissue.mojo': "
             "'7a72a46ef52f2d4a506b30eb405381a2e24760bfdb7e80a3b49bde1a29d1b91b',\n",
             " 'extensions/humanoid/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/assets.mojo': "
             "'5bb7d4e755b00fb7f9170449fac3fb294b8a32be7397772cfec73fd1af0a0fd4',\n",
             " 'extensions/humanoid/athleticism.mojo': "
             "'0cddb9a18fbd1de06a3af23fdba6bd6d76a0227c537277bf87ebc6b6aedc9541',\n",
             " 'extensions/humanoid/genome.mojo': "
             "'6e76453b4bd8f3b1fc7a1575ceff46684aa3d4c333b4fed506dfc21ed68a5eca',\n",
             " 'extensions/humanoid/sex.mojo': "
             "'d31e08b1eb5e8301ae86d895b1f0e35e9242ea0e2e265227243c4231b406c342',\n",
             " 'extensions/humanoid/side.mojo': "
             "'8e0d56aaa0b8a06cde796f440809daab81ff2ba5042c56f5474beaf5115cd2a9',\n",
             " 'extensions/humanoid/skeleton/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/arm/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/arm/assembly.mojo': "
             "'f62f2445d176dcb7135826a79fe03cf1ef1958717e9241fe6d083eadd034911f',\n",
             " 'extensions/humanoid/skeleton/arm/bones/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/arm/bones/dimensions.mojo': "
             "'fec01e7fcf2e22f572025a9aa25ee73787afe40a81af3d15895ed870eb220388',\n",
             " 'extensions/humanoid/skeleton/arm/bones/geometry.mojo': "
             "'b97e08430c780a0ee916aaa1137af5c64f2282de7330d34bd23e68f591c5903e',\n",
             " 'extensions/humanoid/skeleton/arm/contents.mojo': "
             "'4abe4929a889fbb130217874c52a470fad109c0d29d85a3e6004a77eeb28f508',\n",
             " 'extensions/humanoid/skeleton/arm/frame.mojo': "
             "'a6a2fd6455f20e4e261fb43d4b6754d382da71dd060a79a19612cafc4f927546',\n",
             " 'extensions/humanoid/skeleton/arm/hair/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/arm/hair/dimensions.mojo': "
             "'2117dae1a6b922403571c72f661ed270acef62589299c02daab143edd3d9188d',\n",
             " 'extensions/humanoid/skeleton/arm/hair/geometry.mojo': "
             "'20d3ff217a0c2fca7da2e62c94d5a5369261f1eb613e210c4a9e4d9bb9ea54db',\n",
             " 'extensions/humanoid/skeleton/arm/ligaments/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/arm/ligaments/dimensions.mojo': "
             "'d6439c7dc5bff3066ca69d8e610162f9038cb65dcc3056da3d430ab11a401162',\n",
             " 'extensions/humanoid/skeleton/arm/ligaments/geometry.mojo': "
             "'efdc55cb634b732654bc268971c0fafde6baa2d502ba0d4f827ec63acb1018e3',\n",
             " 'extensions/humanoid/skeleton/arm/lymph/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/arm/lymph/dimensions.mojo': "
             "'9c69c757e141106011074cc20ba0e0e90543ee7e2c767bf741f046ebf7b11a63',\n",
             " 'extensions/humanoid/skeleton/arm/lymph/geometry.mojo': "
             "'77d88fb31f2fdb2b3e7f0492c5f8b3f833afa3ac82d9f2094294081460b538ab',\n",
             " 'extensions/humanoid/skeleton/arm/muscles/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/arm/muscles/dimensions.mojo': "
             "'daea51edd98ea1882e5f5b840ef43e93f3f4421b6e142ad2fd6d5c1ca5174a0b',\n",
             " 'extensions/humanoid/skeleton/arm/muscles/geometry.mojo': "
             "'87c62ef12263a84408013142de1306ad3d682401d223121ee49a16a878bb1e26',\n",
             " 'extensions/humanoid/skeleton/arm/nerves/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/arm/nerves/dimensions.mojo': "
             "'5f99788bd09e4eba09c04c10547b443af4640e58161dd2414340f2fa63b8fee5',\n",
             " 'extensions/humanoid/skeleton/arm/nerves/geometry.mojo': "
             "'f4c02994854f0cdabe88453f3a7c691bb44dab599157da776380ba0289340cb4',\n",
             " 'extensions/humanoid/skeleton/arm/skin/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/arm/skin/dimensions.mojo': "
             "'65341dc934994f1401535fc732255739dae36ff4790389ca7808729064e92aa0',\n",
             " 'extensions/humanoid/skeleton/arm/skin/geometry.mojo': "
             "'8b687cd8a8982e32f2fac500c2db809a3ada568c4fbc3903dfd081f9089a05a3',\n",
             " 'extensions/humanoid/skeleton/arm/vessels/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/arm/vessels/dimensions.mojo': "
             "'720932e514410d8ed79f7bab028cda672a68b0380b11376b34356038faa4b6c9',\n",
             " 'extensions/humanoid/skeleton/arm/vessels/geometry.mojo': "
             "'a5f4cb9a6493d4ea73a5a50b4a146aa054452ca11a762922c2851771af35bc31',\n",
             " 'extensions/humanoid/skeleton/complexion.mojo': "
             "'4000aa47c43c805097a54b96d226ae89d6341a6ca6c79436e80b7e8dbd56ad06',\n",
             " 'extensions/humanoid/skeleton/dermis.mojo': "
             "'bdfbe857828add673109c382a8478ad6ea7a47c495b8bbfd3b38a6844d0ff5f9',\n",
             " 'extensions/humanoid/skeleton/field.mojo': "
             "'c5c57466cc6bd576d56bddd948f5dcbc3330523b2375742c8a8f1ab687d40fa9',\n",
             " 'extensions/humanoid/skeleton/foot/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/foot/assembly.mojo': "
             "'3cf5b178fa42b49feebf9336703caa990b43ed83dc2f0075d02292be77939df3',\n",
             " 'extensions/humanoid/skeleton/foot/bones/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/foot/bones/dimensions.mojo': "
             "'b6f21c7d225c013eab349961aee5c416322e6abb053b5e9cad69d006435a569a',\n",
             " 'extensions/humanoid/skeleton/foot/bones/geometry.mojo': "
             "'3e04cf81d212e620db76470513e20180c45c97264b56a06343eb8d821137da6b',\n",
             " 'extensions/humanoid/skeleton/foot/chain.mojo': "
             "'d82355f0a6f6c4f3340f24689b9b1aa18f916fd57c8f030647c200dc52eb00bc',\n",
             " 'extensions/humanoid/skeleton/foot/contents.mojo': "
             "'4ac91cacee468c5b8bad79ad8cdd8012995b51b31bbff3244dc1f09820e5af35',\n",
             " 'extensions/humanoid/skeleton/foot/hair/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/foot/hair/dimensions.mojo': "
             "'15781d9f1f7961037b22d418823cf2d007002563a78edc4b84f4400311d3a018',\n",
             " 'extensions/humanoid/skeleton/foot/hair/geometry.mojo': "
             "'2822843b766edb7f260a6a410635bcb39b57db0e5cea728177b0a1d431af6a38',\n",
             " 'extensions/humanoid/skeleton/foot/ligaments/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/foot/ligaments/dimensions.mojo': "
             "'e534d46121d26c543a7b506164c64ef54d2cc29caac636cef929d1eeff54f6d6',\n",
             " 'extensions/humanoid/skeleton/foot/ligaments/geometry.mojo': "
             "'3082eb038e5acef71d037476c7ccf9aef9e23fe0a8be88640e4ac3468965d317',\n",
             " 'extensions/humanoid/skeleton/foot/lymph/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/foot/lymph/dimensions.mojo': "
             "'822889f9bd9ca1e68714945c255d272747986037f8bf6d551d6e4c6c4e2f5b3a',\n",
             " 'extensions/humanoid/skeleton/foot/lymph/geometry.mojo': "
             "'822b1a94865951aa34427c927e5d3185e8c777a2a53616999de6354830a32ef3',\n",
             " 'extensions/humanoid/skeleton/foot/muscles/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/foot/muscles/dimensions.mojo': "
             "'06b1c0b7e304eed94682ffa8ba1b799bdce944f06f0804be9f25785d6c898d7b',\n",
             " 'extensions/humanoid/skeleton/foot/muscles/geometry.mojo': "
             "'1e40ff03dd6516b9e391c428a9884ca8cff56d3df9cc08cdd3443d5d2aa28a0f',\n",
             " 'extensions/humanoid/skeleton/foot/nerves/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/foot/nerves/dimensions.mojo': "
             "'6ae2a4a74534bf8d3ad32a1b4a2e4bbda71821af57793b17293169121e021908',\n",
             " 'extensions/humanoid/skeleton/foot/nerves/geometry.mojo': "
             "'20cc857c207e46a1e423533839219e418eb0334a8db8f09fa036649456cce4aa',\n",
             " 'extensions/humanoid/skeleton/foot/skin/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/foot/skin/dimensions.mojo': "
             "'cac9654d6385da4c8fa44ec185fa7829de620f823ebe178a7485b69926f49cec',\n",
             " 'extensions/humanoid/skeleton/foot/skin/geometry.mojo': "
             "'ac8fc0d736a79aa68108f52dff5b68d06a5a71cf1c74902cf30ec8fa5ae46154',\n",
             " 'extensions/humanoid/skeleton/foot/vessels/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/foot/vessels/dimensions.mojo': "
             "'22b582af30c0003ca1535d6573d44c54132cac6b47a8884df24adfde2f5058b8',\n",
             " 'extensions/humanoid/skeleton/foot/vessels/geometry.mojo': "
             "'52acebbddd8e2ced61c9c141a8e23668162ebca4d581ec96f3cf5b70f63bcdb0',\n",
             " 'extensions/humanoid/skeleton/hair_shafts.mojo': "
             "'1c8c1a21f439d4694bde79aff5d576a98d9d002ff2ac02b94010eaac6ac3311c',\n",
             " 'extensions/humanoid/skeleton/hand/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/hand/assembly.mojo': "
             "'77f807c1ee34a766f7f79b6b4d04c5caf4310cc569b26e6441621db35146c408',\n",
             " 'extensions/humanoid/skeleton/hand/bones/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/hand/bones/dimensions.mojo': "
             "'ee3533bb1657418b005a7bd13451a510789beb726fa38e0add676d4d1d618461',\n",
             " 'extensions/humanoid/skeleton/hand/bones/geometry.mojo': "
             "'93a3fa4a707f8fe950db466c0af19185fc9c13149021cd77a5512433c02ca2c4',\n",
             " 'extensions/humanoid/skeleton/hand/contents.mojo': "
             "'ce55447d577356c91dfa648ec4b2c28a6de4c00332859b9c8044df350e42aa56',\n",
             " 'extensions/humanoid/skeleton/hand/hair/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/hand/hair/dimensions.mojo': "
             "'85a3ad55508026b86b8ace135c0209b415595a8955df9445cb0370cd51f66832',\n",
             " 'extensions/humanoid/skeleton/hand/hair/geometry.mojo': "
             "'ace0c7dd09bf1e0cb64c4d16b0a4421f53e6dc4139ba0b482b7cad483277aa83',\n",
             " 'extensions/humanoid/skeleton/hand/ligaments/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/hand/ligaments/dimensions.mojo': "
             "'dedee73703e5a13bd8de7c37989a1480e129a3c79e596cd405e400c3113daafa',\n",
             " 'extensions/humanoid/skeleton/hand/ligaments/geometry.mojo': "
             "'e12c1e40562e5a6a533668b0827ecdd34ed5dfd78b56e27b79cb12845b949fe3',\n",
             " 'extensions/humanoid/skeleton/hand/lymph/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/hand/lymph/dimensions.mojo': "
             "'7f1b2197ba968af085e6cd42088447100eb33ec24fcd672efdf9ed33bb8dc7ab',\n",
             " 'extensions/humanoid/skeleton/hand/lymph/geometry.mojo': "
             "'f568f74defca05261750eabf717ad715689273911e07693f00819e48791f51aa',\n",
             " 'extensions/humanoid/skeleton/hand/muscles/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/hand/muscles/dimensions.mojo': "
             "'774775c26d5852f240f1140415103765d60a2165fd459189833d578f6d5657bf',\n",
             " 'extensions/humanoid/skeleton/hand/muscles/geometry.mojo': "
             "'c69e380e22d6a6470a828569174692d778c943c44dc55fa076fde77405f2e0e7',\n",
             " 'extensions/humanoid/skeleton/hand/nerves/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/hand/nerves/dimensions.mojo': "
             "'f0082636513ae8306f9bde3cce54d8f3090d3170d5f81c420d66ea2819a7a978',\n",
             " 'extensions/humanoid/skeleton/hand/nerves/geometry.mojo': "
             "'a59e5b920dffc808c9f8b469c1a00db77829e77ac533599049e5c514948c9088',\n",
             " 'extensions/humanoid/skeleton/hand/skin/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/hand/skin/dimensions.mojo': "
             "'329328b7896e02928f9d8afd319a2cbe380d65e6bc4ed06ea1b9d398d1276aa2',\n",
             " 'extensions/humanoid/skeleton/hand/skin/geometry.mojo': "
             "'82531a82da3600f8887a8e1e3af7e3758d3d975bb036c8c976ef4d7a8d44af6a',\n",
             " 'extensions/humanoid/skeleton/hand/vessels/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/hand/vessels/dimensions.mojo': "
             "'f6182b369605e4dc0a3fb389c90cdff1a907f1eb5cc7d4d62fbd42ca978b7052',\n",
             " 'extensions/humanoid/skeleton/hand/vessels/geometry.mojo': "
             "'ae7b3fe2dd1f1b6eae62317876b135ec07f8d0588c6835b46fbe4885fc4c51bb',\n",
             " 'extensions/humanoid/skeleton/head/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/head/assembly.mojo': "
             "'89c62abc454debdb2777e3698c2992185507a4c2b1c7674ecd22bf70a883f406',\n",
             " 'extensions/humanoid/skeleton/head/bones/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/head/bones/dimensions.mojo': "
             "'8de999263d7cb6b807b6e1105e5bf9e774efdbcd0501546bac58af77415e0eba',\n",
             " 'extensions/humanoid/skeleton/head/bones/geometry.mojo': "
             "'131afc719a4262c90defbd9c1c9c70dffe4382ee2f365fc57fe0bef96bbd12c5',\n",
             " 'extensions/humanoid/skeleton/head/contents.mojo': "
             "'8963187c2c449394e9deeb5efeca8e9f781d6fe39525b74c878a2af2c7eb4e69',\n",
             " 'extensions/humanoid/skeleton/head/eyes.mojo': "
             "'ed845af70644d0408e6a295c1af5abcf4ef6ab16073a8ab29a2c9d5b258e542b',\n",
             " 'extensions/humanoid/skeleton/head/face_model.mojo': "
             "'89f346b425a3f096e8ad46352f97cbf44299f3a0bd4713815af3b7e6a3322e6e',\n",
             " 'extensions/humanoid/skeleton/head/frame.mojo': "
             "'cc2ebb1a9d590ddd6072f509d8f9d59f41473f02128193bbf9f8b3de6f54795d',\n",
             " 'extensions/humanoid/skeleton/head/hair/collider.mojo': "
             "'da7bf07ec7f71bbb742e8af16de38d3b93bd3497446cf5f73ed1a1b8fe438a88',\n",
             " 'extensions/humanoid/skeleton/head/hair/density.mojo': "
             "'88283971d77ae8f245e606887373bc57222c403f4e64af982bf2acdf4a97ef63',\n",
             " 'extensions/humanoid/skeleton/head/hair/dimensions.mojo': "
             "'4dbcc1e61c5b8a748633d255b99f9167f55c7b822c7a7718e5b6b11ed860152b',\n",
             " 'extensions/humanoid/skeleton/head/hair/geometry.mojo': "
             "'786d218c79da1097b930bc83d42ac9d3ae2cb4b4705d2c1318f824db251396ee',\n",
             " 'extensions/humanoid/skeleton/head/hair/groom.mojo': "
             "'67f8ea34485c0f1a8b561dece38a933cdc5d0e6aea47d038196d68ee0b617fbd',\n",
             " 'extensions/humanoid/skeleton/head/hair/styles.mojo': "
             "'2693b22bbca30f659de4c954479249680871c001959c03644d897f17ba5c5ea4',\n",
             " 'extensions/humanoid/skeleton/head/ligaments/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/head/ligaments/dimensions.mojo': "
             "'4ff301c65e3c38639504f67f2ab32267a34c0e9f89768d5f30cafe97cf5a5779',\n",
             " 'extensions/humanoid/skeleton/head/ligaments/geometry.mojo': "
             "'a4da0a0a88d271c2198dca163b553b420987b76e0d61251f8b0482fc4d002586',\n",
             " 'extensions/humanoid/skeleton/head/lymph/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/head/lymph/dimensions.mojo': "
             "'1606f3ac37769995f888646920da7ff2973c4f0fdf29f8d118348a8173101831',\n",
             " 'extensions/humanoid/skeleton/head/lymph/geometry.mojo': "
             "'e6735eeddeff098772e131af3f3c05c2e19e67f7d4d5802c9eb493bd7435df3c',\n",
             " 'extensions/humanoid/skeleton/head/muscles/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/head/muscles/dimensions.mojo': "
             "'0fd568d8d36e0c7390f18b1d212853a6a643d9d86e2a358990f00fa369793c67',\n",
             " 'extensions/humanoid/skeleton/head/muscles/geometry.mojo': "
             "'9805573beadd5dc11b5689902f29bcd403eb18dd62d6317a4292948f8724f74c',\n",
             " 'extensions/humanoid/skeleton/head/nerves/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/head/nerves/dimensions.mojo': "
             "'b8648d896b8d5d0700f81ee12232c5933b3f30909f65b25da42240946d5a44f7',\n",
             " 'extensions/humanoid/skeleton/head/nerves/geometry.mojo': "
             "'0c794156f22d40b3224fb0e6b0f80943b1e777628e6a4a42fb07682898288fdf',\n",
             " 'extensions/humanoid/skeleton/head/skin/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/head/skin/dimensions.mojo': "
             "'fb1f420a98b05ce2a64224699b4dd5b1032654a096ffe9ce6e060d0fcee713be',\n",
             " 'extensions/humanoid/skeleton/head/skin/geometry.mojo': "
             "'22d55d868986379a82bab45d351325d223c0f228cd60b2ea9eacdc58286cc385',\n",
             " 'extensions/humanoid/skeleton/head/skin/mouth.mojo': "
             "'9c3bdb9b664e92a3a3e7fb93689be2ff7ca2b996de740bd750d7d31819eb406c',\n",
             " 'extensions/humanoid/skeleton/head/skin/scan.mojo': "
             "'616033de36df47bc74ec0c0f91d38dff73ae1b8606ca42731dc97af9b8891eb7',\n",
             " 'extensions/humanoid/skeleton/head/skin/tint.mojo': "
             "'aefb817f97ca01316b9a9a22e30f855bd9bd20fdfc9573d6fcdd7eed5c30d170',\n",
             " 'extensions/humanoid/skeleton/head/vessels/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/head/vessels/dimensions.mojo': "
             "'0f3bc9c28524be575a022bb1700eba4811c27410d270c7c80b5077425f1bf515',\n",
             " 'extensions/humanoid/skeleton/head/vessels/geometry.mojo': "
             "'775662396994f5ccffac5b4b5f2102488118a5d7cf1373f1f36c01fae1bf7709',\n",
             " 'extensions/humanoid/skeleton/isosurface.mojo': "
             "'cf40c00847dbdb157273acc2163ba3c2f90875ac0b41ec67ea9d4828fb17ac75',\n",
             " 'extensions/humanoid/skeleton/layer_set.mojo': "
             "'833ceb236d967cc0594cad8e7ccc97b13a874f73605ef103b32bf6c8776ced09',\n",
             " 'extensions/humanoid/skeleton/leg/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/assembly.mojo': "
             "'50593a0fbe48d64ccd33386d1ab1d5b2ad54482d758f78ccfc4b362b49a1cafd',\n",
             " 'extensions/humanoid/skeleton/leg/contents.mojo': "
             "'c2aef8fe7969cab99926bce30af9de3777294c96d8c526582739fa63e73be28b',\n",
             " 'extensions/humanoid/skeleton/leg/femur/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/femur/dimensions.mojo': "
             "'1bfcc887ee1f531108b2719c31d90d8b88f8650db75b32e3a628f991488dc4ba',\n",
             " 'extensions/humanoid/skeleton/leg/femur/geometry.mojo': "
             "'e6e99b707dff7ab24886a5ecbf4bf1ce15f7cd3ab617bf2117b392a671675691',\n",
             " 'extensions/humanoid/skeleton/leg/fibula/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/fibula/dimensions.mojo': "
             "'b4c7848f100e1ebd5ba1010de6fc34bc77aa59b227010fd33c0d40b664e0fbaa',\n",
             " 'extensions/humanoid/skeleton/leg/fibula/geometry.mojo': "
             "'50205b8c7e927732edac3e227f23d1e8d520f0eb4ceb04d0b91e8a2ca7fe93cc',\n",
             " 'extensions/humanoid/skeleton/leg/hair/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/hair/dimensions.mojo': "
             "'e904d80577cd1727684064b1ed4b487ff29b795f50eab770ded4665831c9cacb',\n",
             " 'extensions/humanoid/skeleton/leg/hair/geometry.mojo': "
             "'4653aab9209929c433617c94029f68d438cce5d0745fbd5dbfdb7a877bb9cef6',\n",
             " 'extensions/humanoid/skeleton/leg/knee/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/knee/dimensions.mojo': "
             "'6661d7cb0622e8f3e66044f0fe598ad9ae0a493654ccf0293313579fa2ec8297',\n",
             " 'extensions/humanoid/skeleton/leg/knee/geometry.mojo': "
             "'c7477b3213098d1c42ea4fb9fbb550f0c003f75512eb07ccd39721aca00ea38d',\n",
             " 'extensions/humanoid/skeleton/leg/lymph/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/lymph/dimensions.mojo': "
             "'34bb02ffa56e23a7f2651979fc4e52c0cf1c9bc329cf6f5c926f66a74076aa66',\n",
             " 'extensions/humanoid/skeleton/leg/lymph/geometry.mojo': "
             "'98572a4ddfb99d136838dcbfa1e97b58dc2fee8ef6e2e66c4a0f4403aa8989b4',\n",
             " 'extensions/humanoid/skeleton/leg/muscles/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/muscles/dimensions.mojo': "
             "'f947872e5d0f24ba923b445ff13970a56adc1299534a6cf5b48885173981117f',\n",
             " 'extensions/humanoid/skeleton/leg/muscles/geometry.mojo': "
             "'7ba642cfe580bd55e882020e0e7449b1b02b105a4c968d4eb86c51f76fd81957',\n",
             " 'extensions/humanoid/skeleton/leg/nerves/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/nerves/dimensions.mojo': "
             "'da35dd1c640e32ab76fe8af3ae59ea0d0f0fe1543a86f28b21f94d79e36cc833',\n",
             " 'extensions/humanoid/skeleton/leg/nerves/geometry.mojo': "
             "'b3ca7e7d49746d2fc1ea8fafa6aa8f971c0ce9f331bf2f2862cbb9a63f09b6a0',\n",
             " 'extensions/humanoid/skeleton/leg/patella/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/patella/dimensions.mojo': "
             "'0ff13ee04349990b58ee3b37f9b928ad36a9ffcf6237d6032f8d7de2aedd17ff',\n",
             " 'extensions/humanoid/skeleton/leg/patella/geometry.mojo': "
             "'6aa9d6af356e5a506e45035b3a160548bfed17455560b8a4190af74cef8350e9',\n",
             " 'extensions/humanoid/skeleton/leg/skin/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/skin/dimensions.mojo': "
             "'e85e7864d7a6e8d5c041ba8386c790938345502688f519717a1523f4076b9393',\n",
             " 'extensions/humanoid/skeleton/leg/skin/geometry.mojo': "
             "'612bead9071cff56cb692fed1a2014211acfbd1264911f8e0ff34eb41c48f8f4',\n",
             " 'extensions/humanoid/skeleton/leg/tibia/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/tibia/dimensions.mojo': "
             "'0b35d66eff93164c478da515d5966a736a37f0aac8853837a5c5f31cd61e05dc',\n",
             " 'extensions/humanoid/skeleton/leg/tibia/geometry.mojo': "
             "'e366515e962e34e2c3ded867861693eb7b5152bc3bd93d4f4e70027b9a1b7eaf',\n",
             " 'extensions/humanoid/skeleton/leg/vessels/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/leg/vessels/dimensions.mojo': "
             "'3a9b54cfa4eeeacbb1a04c8ce8952a46f5ca2d8405f69215832aecf37ea476a7',\n",
             " 'extensions/humanoid/skeleton/leg/vessels/geometry.mojo': "
             "'53b51984fd16179981a4f964f7fd6435009d946c8b1103c1b66504cf75b3bb85',\n",
             " 'extensions/humanoid/skeleton/limb/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/limb/skin.mojo': "
             "'3b93c4902fa4dfbb2bb984aa21dfd555036631b40e8d964e8b776a07414ac430',\n",
             " 'extensions/humanoid/skeleton/loft.mojo': "
             "'e752c764322629e463d4bda2ec1016fcf798dc783b8964e1d3c67380724083ab',\n",
             " 'extensions/humanoid/skeleton/look.mojo': "
             "'3650c0efb4bbfd6ab72793cbb2485b633bb70e6e8413006ea8022a3c1a93dc89',\n",
             " 'extensions/humanoid/skeleton/mesh_field.mojo': "
             "'2fae9883759be00f2d95eed70595bd4f3020773a96e821d88af86c45b5cd136d',\n",
             " 'extensions/humanoid/skeleton/morph.mojo': "
             "'ad45a84aecebd2ede894aaf3706ae14a79635e1df93156adb540662620c5d8ec',\n",
             " 'extensions/humanoid/skeleton/pelvis/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/pelvis/assembly.mojo': "
             "'a1db00e7da91785d4700751d2e23ab1a1359ff0176201c0a58390373dfd7785d',\n",
             " 'extensions/humanoid/skeleton/pelvis/bones/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/pelvis/bones/dimensions.mojo': "
             "'13fd1ec5e495f42650355847245f508d41b37da75766e0bae9b398c31403b5f1',\n",
             " 'extensions/humanoid/skeleton/pelvis/bones/geometry.mojo': "
             "'da74a97a5bc3c9bca9d3cbdad9addeef1ec8f349c3b0858b89f88dde35e1ec12',\n",
             " 'extensions/humanoid/skeleton/pelvis/contents.mojo': "
             "'43d95b7d5cfa1d784eeb36fdbf4916893b4283d6436417291deb6ffc1b89f10a',\n",
             " 'extensions/humanoid/skeleton/pelvis/ligaments/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/pelvis/ligaments/dimensions.mojo': "
             "'07f981c8d999391e065f3bae371a6f89b4d29c6e1d061e75a7978e1b05908440',\n",
             " 'extensions/humanoid/skeleton/pelvis/ligaments/geometry.mojo': "
             "'a3de67d9e17fdf08f1dac600a86e10e2784679066b2b663bb402111cb2efe945',\n",
             " 'extensions/humanoid/skeleton/pelvis/lower_body.mojo': "
             "'2fdd9e479823e2c35988e7321b6e723cbb367e854e410ba0423f80ce46d605eb',\n",
             " 'extensions/humanoid/skeleton/pelvis/lymph/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/pelvis/lymph/dimensions.mojo': "
             "'70f1362e55c33f8ee148d7243c3678a18d798b8a2de9b4933aa4a90eb71678d0',\n",
             " 'extensions/humanoid/skeleton/pelvis/lymph/geometry.mojo': "
             "'0adcc126f28e9ed4dc3043adeed75dc96e07fa1229d5a75010327c558a304c05',\n",
             " 'extensions/humanoid/skeleton/pelvis/muscles/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/pelvis/muscles/dimensions.mojo': "
             "'e0b25da2866e2ff54a9644e18b5c87c7cbe81d670bff0b2618d04e5ada054d50',\n",
             " 'extensions/humanoid/skeleton/pelvis/muscles/geometry.mojo': "
             "'76422f29dea2b0ee59fa3de095a9a8bc488cf00b18107227d4ab5be064cb1535',\n",
             " 'extensions/humanoid/skeleton/pelvis/nerves/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/pelvis/nerves/dimensions.mojo': "
             "'48e4f823a890ec63e6582774e803554389105476c58e03969abd64d8cd8b4211',\n",
             " 'extensions/humanoid/skeleton/pelvis/nerves/geometry.mojo': "
             "'c06bb0bd8c5f7042b584b96c230d9653dc0a1eec288e3ca1a09ae6de020b8f64',\n",
             " 'extensions/humanoid/skeleton/pelvis/skin/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/pelvis/skin/dimensions.mojo': "
             "'0a41deec5cec4c2d5c8e938534df901a63aacf1cae2d0119523a019f3244751b',\n",
             " 'extensions/humanoid/skeleton/pelvis/skin/geometry.mojo': "
             "'032066a91f40ecf521162aa1f98ca198baadcfc6fc59eb854f7a776cba63cdc0',\n",
             " 'extensions/humanoid/skeleton/pelvis/vessels/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/pelvis/vessels/dimensions.mojo': "
             "'e7fa736eccca74db021cbcd2a4dd816c4d72cd7b09661c38da6115eb0e1d347e',\n",
             " 'extensions/humanoid/skeleton/pelvis/vessels/geometry.mojo': "
             "'c6bc09e684ea9b75bf428e4df7e8159f096b422044f188f9e5a159f12662bdd7',\n",
             " 'extensions/humanoid/skeleton/place.mojo': "
             "'5821df5eefffc821ee3a219620ebe44ba41f1cbd48ed6003ae4040a5fd180b6b',\n",
             " 'extensions/humanoid/skeleton/sculpt.mojo': "
             "'a345363e76110c3a7e962156ca2ef3395724667f0f41644586cb360e264dd365',\n",
             " 'extensions/humanoid/skeleton/surface_nets.mojo': "
             "'c41e146dca44bb7c2e9f05113a0e0d254b4257547e8c7930dc25d5ba8567c86e',\n",
             " 'extensions/humanoid/skeleton/torso/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/torso/assembly.mojo': "
             "'1c82e6907e7c82478b0af19a45882340f34c5a1522814e2bfc5c4f8c38b5c4bd',\n",
             " 'extensions/humanoid/skeleton/torso/body.mojo': "
             "'0658ea8977066bff64e7cfcb96711f1b88bb2debb7339abaaf22bed477a2d44d',\n",
             " 'extensions/humanoid/skeleton/torso/bones/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/torso/bones/dimensions.mojo': "
             "'091efbf3f856a0d95ce1821316c448a240d8fd35fe811cf5f147d5e3a8333896',\n",
             " 'extensions/humanoid/skeleton/torso/bones/geometry.mojo': "
             "'d56c60e8875c95881311a1701f4b23e3e4036c1f0c60a566f7cc9175850f53db',\n",
             " 'extensions/humanoid/skeleton/torso/contents.mojo': "
             "'6b7e25da899e5ef3c092216d4f7e40d57623fb38d2a51443ca4b7560ab9707d1',\n",
             " 'extensions/humanoid/skeleton/torso/ligaments/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/torso/ligaments/dimensions.mojo': "
             "'1d3de688dd915e85bfdbd353799d950b4d4cb585e316ba118fed9fa209feb0e3',\n",
             " 'extensions/humanoid/skeleton/torso/ligaments/geometry.mojo': "
             "'802c3a65993a5e85d2f374b0ea988d0f3dc406ffe8427b09a28fa0d35c034b45',\n",
             " 'extensions/humanoid/skeleton/torso/lymph/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/torso/lymph/dimensions.mojo': "
             "'25495230d859a0df914d109ba132f9e8f2a919038525bc0a41808920e7c33b07',\n",
             " 'extensions/humanoid/skeleton/torso/lymph/geometry.mojo': "
             "'1a4003f46bdc343725b982d49d4f3232593a2d9b3551be73c7ea7cd7316338a7',\n",
             " 'extensions/humanoid/skeleton/torso/muscles/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/torso/muscles/dimensions.mojo': "
             "'b37174a431e5afb705e0d820c8721d608e167ee2914cef8bdd5d4b1a8e725ec9',\n",
             " 'extensions/humanoid/skeleton/torso/muscles/geometry.mojo': "
             "'5429ce4a2f1649d32781ad809371088f256f76dfc96c0b56f6c646ef6e9e9c9f',\n",
             " 'extensions/humanoid/skeleton/torso/nerves/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/torso/nerves/dimensions.mojo': "
             "'5d54ea4d00a723cf51cf1e5e29cb259567c39715f503711c1e1e725df273dc33',\n",
             " 'extensions/humanoid/skeleton/torso/nerves/geometry.mojo': "
             "'bda5de30375bf8f3c74a18c7f48d611aefdebf627ae7f1d5477dc179a3b8f442',\n",
             " 'extensions/humanoid/skeleton/torso/skin/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/torso/skin/dimensions.mojo': "
             "'33e3f30cdecfdc9ea615a984886ae01f8cd1aa0f4f86a4f0f5685581a088fd86',\n",
             " 'extensions/humanoid/skeleton/torso/skin/geometry.mojo': "
             "'09148d5decdd93e67de2785afcb696f5333f817327f7d40765a3024205530654',\n",
             " 'extensions/humanoid/skeleton/torso/sweep.mojo': "
             "'8ee430e8785effa1078ce22509580f60eb64c5c23e79c55145ba7cec2189891a',\n",
             " 'extensions/humanoid/skeleton/torso/vessels/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'extensions/humanoid/skeleton/torso/vessels/dimensions.mojo': "
             "'444ffc36a5040f1edc66bc31bc8c79d94f6329f22bc0c7c21bae5b51b2991d70',\n",
             " 'extensions/humanoid/skeleton/torso/vessels/geometry.mojo': "
             "'ab01ddda0002f59e5bc7faa2a8800331720cd908fdf418b27be569765b7616cf',\n",
             " 'extensions/humanoid/spec.mojo': "
             "'994d707324d994e1054b49bbb2181463727e7efb560ba66af9412ba1ec927224',\n",
             " 'geometries/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'geometries/attribute_utils.mojo': "
             "'0a87276b9264a028a3220a667e39f8e96ff6fde7e41ed2c180e0aed7484ccda6',\n",
             " 'geometries/surface.mojo': "
             "'8ff3246d240c90168470bde485496accca02d7096a53270c0d6ce442a4429e04',\n",
             " 'geometries/utils.mojo': "
             "'459f32ecdd779c03d347b6c99f743a48a56028ab02b3f813181781eea3dcf548',\n",
             " 'lights/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'lights/fresnel.mojo': "
             "'4c1a852d788c636603f75a3c459b6f43b0ec3a032d62b525c9fe9fc7cdfcada7',\n",
             " 'lights/light.mojo': "
             "'bc5654ee21e462cf9c86bc5eeffdd2ae7eaed91c3607a03312322e342d9108da',\n",
             " 'lights/light_slot.mojo': "
             "'05dd9713ca0a410e23b8ffdae48a9f530cec9239efaa127f4fb43861ab129652',\n",
             " 'lights/physical_layers.mojo': "
             "'b97a85136309d66b1042de440bf4bc4571c64851b87fb2c4c4aa4fff1b17f649',\n",
             " 'lights/shadow.mojo': "
             "'e57aabcefe61cebaa8e57ae129f0cae3873215b7b1c0d2171c972d78d4015b81',\n",
             " 'loaders/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'loaders/bytes.mojo': "
             "'5600d6d9ca117fc7c7c97a2e5d6a687adc8090627c34cf3181935245dae87c07',\n",
             " 'loaders/js_text.mojo': "
             "'847797a811cd7ee54bdf833e1f6d3f8c2965e90e2491c71d04bf2488c6d2b971',\n",
             " 'loaders/json.mojo': "
             "'b6d44e6930f415f9b47eb7c48b26673a961746cff3a3125b8ac3f7ef9a1de417',\n",
             " 'loaders/utf8.mojo': "
             "'e0d5891d9d2954bd5c4329cda8a3492f4f6464b402b84489eae000cf8e0ce10a',\n",
             " 'materials/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'materials/compute_ids.mojo': "
             "'215ccb1704fb7b30d8a0ad7ec14e839dc399f29f7c7ca29f0403f5c32e25a39e',\n",
             " 'materials/material.mojo': "
             "'0722ad172e97c70cc530348a627eb52cde41c643cabef385423ee8ea6d8b77b9',\n",
             " 'materials/nodes.mojo': "
             "'525920b0e48d73cd4329a51ed127e38c59972ebc48c8562c20ce2200b072c3ef',\n",
             " 'math/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'math/arc_tangent.mojo': "
             "'fde08cd180cb0e2bd94fca6196f86c4b318ef6f1a4ed8e588aaad848076ea8e5',\n",
             " 'math/bezier.mojo': "
             "'4a4087e15d2472bcbeedd492c5a866039988cc1988029a5c28c828eedfb77034',\n",
             " 'math/bounds.mojo': "
             "'712403832a9fc9bdcd835e68e1934dd4de37e8b218e418f797a717da3684ee25',\n",
             " 'math/box_extent.mojo': "
             "'d978c71d45c074acb0a6e36938b1f52f7b2bb6e822c95cf6b3ec4802223782c1',\n",
             " 'math/catmull.mojo': "
             "'d2584909e792fd6f503ea35b6e33fc0fcd801571b1260135ee6fb38df8c74ed2',\n",
             " 'math/cross.mojo': "
             "'352f81c1fc781becc0cf88056ac39978b24926303e3784ff783bcabdf5bf67e5',\n",
             " 'math/curve.mojo': "
             "'579839a0981c00cc9e188a0a57ff9f0c5822b09f3cd8ae6fa5b667d97d8ff5d9',\n",
             " 'math/curve_checks.mojo': "
             "'9ad53ff5ed5a540a85ed4ed00860e8d9c1b537c67edda2a8d6f58b458ae5a8ef',\n",
             " 'math/euler.mojo': "
             "'9645a80e2b0a7dcfeeb2fbf51a0030aab6b44f8603192b86aee533068dab7356',\n",
             " 'math/finite.mojo': "
             "'fc0bcbef9d5439f4ce6da4e10ac2c0a3a2a8022fb31f3426992408e25ac73f7b',\n",
             " 'math/matrix3.mojo': "
             "'b134fabd9dbf12f41c46724ccaa89582be5efbb929677a47c64af45c4d0a1e97',\n",
             " 'math/matrix4.mojo': "
             "'206877d7335ed69e9055ec69b2ac09bd83b493456bfc43c1083ea235a1a44549',\n",
             " 'math/matrix_determinant.mojo': "
             "'c5b25179893fd2903dbda5de68914a50e662e3428107ef2c3424ef42cafcde19',\n",
             " 'math/matrix_inverse.mojo': "
             "'d833edd9d3705ba77e5000b75e6cd4852955e4d978bf0afdbc8efbafa61d42de',\n",
             " 'math/norm.mojo': "
             "'941dbe97b3b6bc6d48af64a682f88970e12d387e8e896054cfc860d59eea9c3d',\n",
             " 'math/path.mojo': "
             "'e182834e6ecb1019ca882beeb2272053dfbbee263f4bfd45bcd35c5c53197f11',\n",
             " 'math/polyline.mojo': "
             "'c4ff928fc5278100da0df381e6ee79423ddd6ef7c3fc38dcfb11521ac73774c1',\n",
             " 'math/quaternion.mojo': "
             "'2cf5b20029448204c1b984349e2e9e5f804ff7831d0506ab156ea7f88173c65d',\n",
             " 'math/random.mojo': "
             "'f8a00ee7d03897a7c35f2f23d157fb65ce2c2b3fde5e4c91f21e7a764fab1655',\n",
             " 'math/ray.mojo': "
             "'5298756c8056364661902adb9a253b3c0e7d771641cc01e4781b85d3dc9a84a4',\n",
             " 'math/ray_query.mojo': "
             "'48136d70da9f19e28fc30e1660416ba1c25bf8a545bafbbe16a904f8e26ff3eb',\n",
             " 'math/remainder.mojo': "
             "'b7575b2fde7a212433498422a121c66b12a85e7109614093bb783ad1cc043e58',\n",
             " 'math/scaled_products.mojo': "
             "'8d16ee11a738e90a951943b786c1abcc7473286788392c447827240900ed16c5',\n",
             " 'math/sine.mojo': "
             "'81580a510da8722ef96df0074937d139019234afc3f089584f534d6b556edcf9',\n",
             " 'math/smoothstep.mojo': "
             "'1753a3342932f3c89eb5ebfb7f9ef5ee0a28530f447432b1bb179e3213ff8edb',\n",
             " 'math/spherical_harmonics3.mojo': "
             "'2ca87fb3e0c23a5755e6c7d147a866d041d3bcef40ad3d35329a4dd559c5b8f4',\n",
             " 'math/square_matrix.mojo': "
             "'04a9f011e814455c9d24a94c66df30b8137f7e9802a2a9b552b0d9bb05538c27',\n",
             " 'math/triangle.mojo': "
             "'f1facc4a319f3ee6614bc3c57896b82300826e0536640e73adc7d55573347f01',\n",
             " 'math/triangle_normal.mojo': "
             "'cdcf00131967b714f2518acd96fb28e874fa3006bfb52a242f3596c281e147bf',\n",
             " 'math/utils.mojo': "
             "'d32e99704324833af194084f0b1d646a894c63bdd0b8ce1baa0da8a287c1d690',\n",
             " 'math/vector2.mojo': "
             "'2aa5cee2c09cfad3c3b2fa883db31efe47f82f30bac6565415ce6a9f18c8d125',\n",
             " 'math/vector3.mojo': "
             "'39bd8f3d5102eb8d32f95fb0982b5886050c43031de416903d692e1c2c664b4a',\n",
             " 'math/vector4.mojo': "
             "'44797637aae80c1e92c08592bc2a510e90e14e93d1c74bb4a01ca71034b10ee6',\n",
             " 'objects/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'objects/clipping_group.mojo': "
             "'abb69d042f7add2154e9efeb83df36a10788844803b57fc405c7092bdc8dc19e',\n",
             " 'objects/gaussian_splat.mojo': "
             "'01fe94cc3159b21a70c104ea92a3631e57c217f19ad26f17bd2bd3ad3ff0f80f',\n",
             " 'objects/instanced_mesh.mojo': "
             "'9992a151f9340c0211f5202594b6bec3d63e10940ae236e9ec0e4feafd888261',\n",
             " 'objects/line.mojo': "
             "'3846559aebd946c4a5e73937fa488a14d2bdbfedf30102cb746456c86397ae27',\n",
             " 'objects/line_segments2.mojo': "
             "'fdff9f90123e0d3d8d3ca9b0aaf22e3b2c110c255d01a14927ce1fca8fa7d021',\n",
             " 'objects/lod.mojo': "
             "'4829fbffecab2c13215a9918f30df7ea7c1471fb94d75b0a0815ccbbb1156899',\n",
             " 'objects/mesh.mojo': "
             "'5e365168f48476146dc90c8bc9f3fec240be9c260b719925e7965e42d2de53b8',\n",
             " 'objects/points.mojo': "
             "'42cdd945dc927e8bcf490824e9163188f50d8dcdd407970b7ccb234e9b91f737',\n",
             " 'objects/skeleton.mojo': "
             "'baff1a5346ae64d843d58802437e797c83686a5f11447684dd028febd0a98a5d',\n",
             " 'objects/skinned_mesh.mojo': "
             "'bf9a1d2aebf7c510a322d85e209f13e472f11bd4898c1c4ea5d507e5fde5a3fb',\n",
             " 'objects/sprite.mojo': "
             "'c257fd417a1394f9c4600e58e5994d3251b8f221efab993ab54b4458e869b225',\n",
             " 'render/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'render/blend.mojo': "
             "'899f45b625a5c50af3960bf65042686ab4b6fb910e03cb142c9556847aedb271',\n",
             " 'render/checksum.mojo': "
             "'796c60b76d945f7672c1595a06d86443224747cbddc07cdaf3fae90bdd3b4eff',\n",
             " 'render/color_math.mojo': "
             "'37e57703f18f3ccd6c7f85ec4700ee2b2967e96b5451db2f7b3edf4be4d4d02b',\n",
             " 'render/css_color.mojo': "
             "'bcfa54778b83bf4056cbf15b7602f6a66e0a01c6778e87b75440fa667275e567',\n",
             " 'render/cube_texture.mojo': "
             "'28c83baf52788ffb412328360ceef2397de1ec33489ee1516d447e3fc8d1f79c',\n",
             " 'render/cube_texture_store.mojo': "
             "'f052c06f7608058225486575e8584da3dda50ced69cf4834501360a73aebefde',\n",
             " 'render/cube_uv.mojo': "
             "'8bd7e1dd5fb4eb131747759c7dfdb86f71ec2f77d4d99dd6735d924ae7756bbe',\n",
             " 'render/float_image.mojo': "
             "'5554273bf9382d919b8cc8450ba406de99b220c4951f86e61721bc92c7aba357',\n",
             " 'render/framebuffer.mojo': "
             "'cc907b6c905ad936f68fca609a7ddcffcd2090977088170670c4b43bfa6ad6ef',\n",
             " 'render/inflate.mojo': "
             "'7db92edc5ed721f4fb66a02195703fa4c7260607be732cb72070d33ac4d0c0a5',\n",
             " 'render/linerule.mojo': "
             "'0d809e132f3019d04cef9734e9841dfbd0244aac738ed4d09bb40b9c45faf07e',\n",
             " 'render/packing.mojo': "
             "'e7b3b4158fb6992edad74bd0870b4509b79d6547785ec9285448b2467b98f083',\n",
             " 'render/png.mojo': "
             "'75d9105e434ed286b207d55d27e90328a24a2ad9f4b8e6580f8de156256558c4',\n",
             " 'render/raster_state.mojo': "
             "'a8fc16d55ca53f4e36c333d99f3ce9eb110ea523aac33b90194c17a8f4fb1211',\n",
             " 'render/srgb.mojo': "
             "'630ac4819cf3eb7bd546e8400ab8984452570110ee15db2898ae65cebae20b61',\n",
             " 'render/tasks.mojo': "
             "'efa65ccd751c3430f1fa875382748f6040733f802be4719b92ff239b510804d4',\n",
             " 'render/texture.mojo': "
             "'3552ba623c9c6c8dd2ea0d7b6f4eb0aac924854086a0ddd9b90865e3f1978c15',\n",
             " 'render/texture_buffer.mojo': "
             "'a1977c2d14e15917b149280e4ae75a1c20e37a0b5939514d8daac50c3da7c7db',\n",
             " 'render/texture_store.mojo': "
             "'78dfcc5c37879dd286272674096b13bad72efdefac769f85525790800f1fbd4b',\n",
             " 'render/volume_texture.mojo': "
             "'e599b4924490cdd8d828749ae4e25cea751f59bfa59198cd3350b5823bda52bf',\n",
             " 'render/volume_texture_store.mojo': "
             "'105a32971b5e88c613ec3a350d9b2c99c27d19080c6c66fb9d42bd4be546c8b0',\n",
             " 'tests/test_hair_density_bounds_controls.mojo': "
             "'2cfb0de9ac61d170beaa7e47fbcaf5c51c7db139ed373f4ab4f07af2fae9e11c',\n",
             " 'tests/test_reconciled_hair_density.mojo': "
             "'2e0c703b365bc98d3d6fc4c8796d4133edf004eafb753262ca89cd6d639be3c4',\n",
             " 'tools/carla_lane_oracle/pr760_arithmetic_stage.py': "
             "'03757bafb02fbb3908919839c18d5c2c443f46469aeb01393dee57ae22054359',\n",
             " 'units/__init__.mojo': "
             "'5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',\n",
             " 'units/measure.mojo': "
             "'b7531458ae7a74d6b9213f55672073137dbac41c2634787f7d6a78a16b526b85',\n",
             " 'units/quantity.mojo': "
             "'bb77541cdb757cd63b59ac01134c6a6ebce88863bee69c84ff77b8c03aff6223',\n",
             " 'units/si.mojo': "
             "'d149a23f2ee4a9bde17875615e7251285cb56af535716b66c7d8959c80f48c02'}\n",
             'DENSITY760_RULES = (\n',
             "    (131, 64, 262144, 'range(count)', 'density-validated-positive-cube-count'),\n",
             "    (167, 1, None, 'range(len(groom))', 'density-partitioned-nonempty-groom'),\n",
             "    (178, 1, None, 'range(samples)', "
             "'density-checked-representable-positive-samples'),\n",
             "    (245, 16, 256, 'range(self.resolution * 4)', "
             "'density-query-validated-positive-step-count'),\n",
             ')\n',
             '\n',
             '\n',
             'def _density760_stage_identity(raw):\n',
             '    """Reuse existing executing-code checks for the one pure inverse leaf."""\n',
             '    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
             '    from carla_lane_oracle import pr760_arithmetic_stage as stage\n',
             '    filename = '
             "Path(__file__).resolve().parent/'carla_lane_oracle/pr760_arithmetic_stage.py'\n",
             '    cleanup.require(Path(stage.__file__).resolve() == filename,\n',
             "                    'density inverse executing origin changed')\n",
             "    compiled = compile(raw, str(filename), 'exec', dont_inherit=True, "
             'optimize=sys.flags.optimize)\n',
             '    cleanup.require(cleanup._code_identity(stage._EXECUTED_MODULE_CODE)\n',
             "                    == cleanup._code_identity(compiled), 'density inverse module "
             "code changed')\n",
             '    defaults = cleanup._compiled_defaults(raw)\n',
             '    for name, expected in cleanup._compiled_functions(raw, str(filename)).items():\n',
             "        if name.startswith('<'):\n",
             '            continue\n',
             '        live = getattr(stage, name, None)\n',
             '        actual = cleanup._live_function_code(live)\n',
             '        cleanup.require(actual is not None and cleanup._code_identity(actual)\n',
             "                        == cleanup._code_identity(expected), 'density inverse "
             "function changed: ' + name)\n",
             '        cleanup._check_defaults(live, defaults.get(name), name)\n',
             '    stage.verify_stage_data()\n',
             '\n',
             '\n',
             'def density760_loops(root, *, include_roots=(), _operation=None):\n',
             '    """Admit only four local validated density rows on one physical image."""\n',
             '    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
             '    from carla_lane_oracle import pr760_arithmetic_stage as stage\n',
             "    operation_args = {} if _operation is None else {'_operation': _operation}\n",
             '    if _operation is not None:\n',
             '        cleanup._operation_include_context(_operation, root, include_roots)\n',
             '    try:\n',
             '        # Historical and unknown endpoints keep their existing independent paths.\n',
             '        raw = _coverage_observe_bytes(root, DENSITY_SOURCE,\n',
             '            relative_source(root, DENSITY_SOURCE, **operation_args).read_bytes(),\n',
             '            _operation=_operation)\n',
             '        if sha256(raw) != DENSITY760_INPUTS[DENSITY_SOURCE]:\n',
             '            return {}\n',
             '        executing = cleanup.executing_checker_bindings()\n',
             '        snapshots = {}\n',
             '        for name, expected in DENSITY760_INPUTS.items():\n',
             '            value = _coverage_observe_bytes(root, name,\n',
             '                relative_source(root, name, **operation_args).read_bytes(), '
             '_operation=_operation)\n',
             '            if sha256(value) != expected:\n',
             '                return {}\n',
             '            snapshots[name] = value\n',
             "        leaf = 'tools/carla_lane_oracle/pr760_arithmetic_stage.py'\n",
             '        _density760_stage_identity(snapshots[leaf])\n',
             "        groom = 'extensions/humanoid/skeleton/head/hair/groom.mojo'\n",
             '        if sha256(stage.predecessor_source(DENSITY_SOURCE, '
             'snapshots[DENSITY_SOURCE].decode()).encode()) != DENSITY_AFTER_SHA256:\n',
             '            return {}\n',
             '        if sha256(stage.predecessor_source(groom, '
             'snapshots[groom].decode()).encode()) != GUARDED_LOOP_SOURCE_SHA256[groom]:\n',
             '            return {}\n',
             "        paths = {name for name in snapshots if name.endswith('.mojo')}\n",
             '        entries, source_image = cleanup._helper_entry_census(root, '
             '**operation_args)\n',
             '        contexts = [(root, entries, source_image)]\n',
             '        for location in include_roots:\n',
             '            extra_entries, extra_image = cleanup._include_entry_context(\n',
             '                location, source_image, **operation_args)\n',
             '            contexts.append((location, extra_entries, extra_image))\n',
             "        native_tests = {'tests/test_reconciled_hair_density.mojo',\n",
             "                        'tests/test_hair_density_bounds_controls.mojo'}\n",
             '        closure = cleanup.dependency_inventory(root, roots=(DENSITY_SOURCE, '
             'groom),\n',
             '            entries=entries, _known=set(source_image), '
             '_snapshots=dict(source_image))\n',
             '        if closure != paths - native_tests:\n',
             '            return {}\n',
             '        def resolver_ok():\n',
             '            # Source coordinates never allow origin sidecars, even when the\n',
             '            # same root is also listed as an include. Include-only sidecars\n',
             '            # correspond to observed staged Mojo coordinates; the generation\n',
             '            # owner authenticates their exact set and bytes before dispatch.\n',
             '            return all(cleanup.resolver_unshadowed(location,\n',
             '                paths if index == 0 else paths | {\n',
             "                    name + '.cov-origin' for name in paths if name in image},\n",
             '                **cleanup._render_lookup_args(paths, local_entries),\n',
             "                math_entries=frozenset(('.', *local_entries)))\n",
             '                for index, (location, local_entries, image) in '
             'enumerate(contexts))\n',
             '        if not resolver_ok():\n',
             '            return {}\n',
             '        for name, value in snapshots.items():\n',
             '            if _coverage_observe_bytes(root, name,\n',
             '                    relative_source(root, name, **operation_args).read_bytes(), '
             '_operation=_operation) != value:\n',
             '                return {}\n',
             '        _density760_stage_identity(snapshots[leaf])\n',
             '        for location, _, image in contexts:\n',
             '            cleanup._helper_entry_census_finish(location, image, **operation_args)\n',
             '        if cleanup.executing_checker_bindings() != executing or not resolver_ok():\n',
             '            return {}\n',
             '        return {line: {\n',
             "            'line': line, 'kind': 'reviewed-nonempty-range', 'cardinality': 1,\n",
             "            'minimum_cardinality': minimum, 'maximum_cardinality': maximum,\n",
             "            'required': 'T', 'impossible': 'F', 'expression': expression,\n",
             "            'proof_id': proof_id, 'dependency_sha256': dict(DENSITY760_INPUTS),\n",
             '        } for line, minimum, maximum, expression, proof_id in DENSITY760_RULES}\n',
             '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, AttributeError) '
             'as error:\n',
             '        if _operation is not None:\n',
             '            cleanup._operation_fail(_operation, error)\n',
             '        return {}\n')),
           (1314,
            1341,
            (),
            ('\n',
             '\n',
             '# Review the producer and consumer as one pair; old/new mixtures are unknown.\n',
             'STRAND_CAP_PAIRED_SUCCESSOR = ({\n',
             '    **STRAND_CAP_SOURCES,\n',
             "    'renderers/renderer.mojo':\n",
             "        '2491b99a982cd4bc49b3573d3c6db8313bfdd47372e693e932c03c27d0ff127d',\n",
             "    'objects/line_segments2.mojo':\n",
             "        'fdff9f90123e0d3d8d3ca9b0aaf22e3b2c110c255d01a14927ce1fca8fa7d021',\n",
             '}, 4047)\n',
             '\n',
             '\n',
             '# The Camera-order repair leaves the complete cap function and producer intact.\n',
             '# Preserve the first PR760 pair as a separately accepted historical endpoint.\n',
             'STRAND_CAP_CAMERA_ORDER_SUCCESSOR = ({\n',
             '    **STRAND_CAP_PAIRED_SUCCESSOR[0],\n',
             "    'renderers/renderer.mojo':\n",
             "        'df552b5bc14d6cc5a0ef4cf919afaf66da620f431b0d4f5bb9c3a61538cb2b84',\n",
             '}, 4047)\n',
             '\n',
             '\n',
             '# Formatting only: generic Camera signature gains two physical lines.\n',
             'STRAND_CAP_FORMATTED_SUCCESSOR = ({\n',
             '    **STRAND_CAP_CAMERA_ORDER_SUCCESSOR[0],\n',
             "    'renderers/renderer.mojo':\n",
             "        '5cc066092d9b0302c60a6676459efc855e220dc319d1f88b5eb84df768f489f9',\n",
             '}, 4049)\n')),
           (1377,
            1378,
            ('def strand_cap_loops(root, *, include_roots=()):\n',),
            ('def strand_cap_loops(root, *, include_roots=(), _operation=None):\n',)),
           (1379,
            1384,
            (),
            ("    operation_args = {} if _operation is None else {'_operation': _operation}\n",
             "    stream_args = {} if _operation is None else {'_operation': _operation, '_root': "
             'root}\n',
             '    if _operation is not None:\n',
             '        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
             '        cleanup._operation_include_context(_operation, root, include_roots)\n')),
           (1385,
            1387,
            ('        actual = {name: file_sha256(relative_source(root, name))\n',),
            ('        actual = {name: file_sha256(relative_source(root, name, **operation_args),\n',
             '                                   **stream_args)\n')),
           (1391,
            1398,
            ('        if line is None or actual != expected:\n',),
            ('        if actual == STRAND_CAP_FORMATTED_SUCCESSOR[0]:\n',
             '            line = STRAND_CAP_FORMATTED_SUCCESSOR[1]\n',
             '        elif actual == STRAND_CAP_CAMERA_ORDER_SUCCESSOR[0]:\n',
             '            line = STRAND_CAP_CAMERA_ORDER_SUCCESSOR[1]\n',
             '        elif actual == STRAND_CAP_PAIRED_SUCCESSOR[0]:\n',
             '            line = STRAND_CAP_PAIRED_SUCCESSOR[1]\n',
             '        elif line is None or actual != expected:\n')),
           (1579,
            1589,
            ('                if not all(cleanup.resolver_unshadowed(location, resolver_paths)\n',
             '                           for location in (root, *include_roots)):\n'),
            ('                def resolver_ok():\n',
             '                    # Source coordinates remain strict. Only include roots can\n',
             '                    # contain these exact provider origin sidecars; the receipt\n',
             '                    # owner authenticates their set and bytes before dispatch\n',
             '                    # and again before the generated proof can escape.\n',
             '                    return cleanup.resolver_unshadowed(root, resolver_paths) and '
             'all(\n',
             '                        cleanup.resolver_unshadowed(location, resolver_paths | {\n',
             "                            path + '.cov-origin' for path in resolver_paths})\n",
             '                        for location in include_roots)\n',
             '                if not resolver_ok():\n')),
           (1602,
            1603,
            ('                        or not all(cleanup.resolver_unshadowed(location, '
             'resolver_paths)\n',
             '                                   for location in (root, *include_roots))):\n'),
            ('                        or not resolver_ok()):\n',)),
           (1604,
            1619,
            (),
            ('                if _operation is not None:\n',
             "                    # Keep this local theorem's consumed resolver premises in\n",
             "                    # the generated owner's final physical sweep as well.\n",
             '                    observed = (_operation._raw.keys() if _operation._state == '
             "'active' else\n",
             '                        {path for location, path, value, mode in '
             '_operation._receipt_observations\n',
             '                         if location == _operation._root})\n',
             '                    cleanup.require(resolver_paths <= observed,\n',
             "                                    'local helper resolver inputs were not "
             "observed')\n",
             '                    _operation._resolver_paths = frozenset(\n',
             '                        _operation._resolver_paths | resolver_paths)\n',
             "                    if _operation._state == 'pending':\n",
             '                        cleanup.require(not _operation._executing\n',
             '                                        or dict(_operation._executing) == '
             'executing,\n',
             "                                        'local helper checker image changed')\n",
             '                        _operation._executing = '
             'types.MappingProxyType(dict(executing))\n')),
           (1684,
            1694,
            (),
            ("        if module == 'extensions/humanoid/skeleton/head/hair/strands':\n",
             "            name = module + '.mojo'\n",
             '            raw = _coverage_observe_bytes(root, name,\n',
             '                relative_source(root, name, **operation_args).read_bytes(),\n',
             '                _operation=_operation)\n',
             '            if sha256(raw) == HAIR_LITERAL_SUCCESSOR[0][name]:\n',
             '                bindings, sites = HAIR_LITERAL_SUCCESSOR\n',
             '                if not all(_density_stdlib_unshadowed(path, **operation_args)\n',
             '                           for path in (root, *include_roots)):\n',
             '                    return {}\n')),
           (2189,
            2190,
            ('            result.update(strand_cap_loops(root, include_roots=include_roots))\n',),
            ('            result.update(strand_cap_loops(root, include_roots=include_roots, '
             '**operation_args))\n',)),
           (2193,
            2195,
            ('            result.update(repaired_density_loops(root, '
             'include_roots=include_roots))\n',),
            ('            result.update(repaired_density_loops(root, include_roots=include_roots, '
             '**operation_args))\n',
             '            result.update(density760_loops(root, include_roots=include_roots, '
             '**operation_args))\n')))},
 'full_audit_cleanup_contracts.py': {'after_sha256': '65fc5809c888bf07e2a8798cc3803de1757988e5cad5cd8766beb2e5fb2673cb',
 'before_sha256': '6138ba2dcac394c716ea9ed32e74e0c6d15857d5c605fc82304d21d0c80fdc69',
 'edits': ((10, 11, (), ('from contextlib import nullcontext\n',)),
           (45, 46, (), ('        from . import lane_order_contracts as lane_order\n',)),
           (55, 56, (), ('        from . import pr760_arithmetic_stage as pr760_stage\n',)),
           (59, 60, (), ('        import lane_order_contracts as lane_order\n',)),
           (69, 70, (), ('        import pr760_arithmetic_stage as pr760_stage\n',)),
           (150,
            159,
            ("DEPENDENCY_TOOL_SHA256 = {'tools/carla_lane_oracle/scaled_float32_contracts.py': "
             "'e3a59a9f8d5a9394007c03fab6ac696e04998812dad5843a22e721bfbe57c2a1',\n",),
            ('PR760_STAGE_SHA256 = '
             "'03757bafb02fbb3908919839c18d5c2c443f46469aeb01393dee57ae22054359'\n",
             "PR760_IMAGE = 'tools/carla_lane_oracle/pr760-source-image.json'\n",
             'PR760_IMAGE_SHA256 = '
             "'ef91b7edab2c8a597aeedc90f86e834d5227aad5770ebe39e0438944f246f7cf'\n",
             "PR760_OWNER_PREDECESSOR = 'tools/carla_lane_oracle/pr760-owner-predecessor.txt'\n",
             'PR760_OWNER_PREDECESSOR_SHA256 = '
             "'6138ba2dcac394c716ea9ed32e74e0c6d15857d5c605fc82304d21d0c80fdc69'\n",
             "DEPENDENCY_TOOL_SHA256 = {'tools/carla_lane_oracle/winner_sign_contracts.py': "
             "'f850902634073364fe2407b00d12e9fdfb2ecfc6cf2a03414269fbb7984a8a7f',\n",
             " 'tools/carla_lane_oracle/border_parser_contracts.py': "
             "'734d7b24aaf4e9f537cd7f0d7c7b8094d9c29106770b66c4a7a24cab74604dd4',\n",
             " 'tools/carla_lane_oracle/pr760_arithmetic_stage.py': PR760_STAGE_SHA256,\n",
             " 'tools/carla_lane_oracle/scaled_float32_contracts.py': "
             "'e3a59a9f8d5a9394007c03fab6ac696e04998812dad5843a22e721bfbe57c2a1',\n")),
           (167,
            171,
            (" 'tools/carla_lane_oracle/source_contracts.py': "
             "'83fdd35b61f0dc7739160c113ae6b4558ad07d45ffded22b7062bc9a209032d0',\n",
             " 'tools/carla_lane_oracle/sum2_guard_contracts.py': "
             "'acbf385486e2b0dfe15a409d039cd31c8e9fed295704bc6adcb4289818b65f63',\n",
             " 'tools/carla_lane_oracle/typed_boundary_contracts.py': "
             "'baf231cb640435f5b81e350f32e6a0d6203e4ae5d0d6fb9bccb0c6d4bdbfae8a',\n"),
            (" 'tools/carla_lane_oracle/source_contracts.py': "
             "'ebb6e75b90528b5456485433d470de36e6b33e4df98139dd0acadda75a57adf5',\n",
             " 'tools/carla_lane_oracle/sum2_guard_contracts.py': "
             "'8c1d646c1dd70e1e7c9453077b63060ca506f76d2493137af0dd0a9a68012570',\n",
             " 'tools/carla_lane_oracle/lane_order_contracts.py': "
             "'314b1fae1f274c7223ab5dec50ad4cb97760c31926844ca92e1e6aa8560b4889',\n",
             " 'tools/carla_lane_oracle/typed_boundary_contracts.py': "
             "'59cc73b325af897981a2d7299cf2d4ed3c61d3ea64d5f958f2b85aef51666362',\n")),
           (174,
            175,
            (" 'tools/carla_lane_oracle/seed_count_contracts.py': "
             "'ff4a330326fd69bc649e6f235d1f05db4ed40e6b76b1d75e66a4474741c16345'}\n",),
            (" 'tools/carla_lane_oracle/seed_count_contracts.py': "
             "'daa8f391a18e54a3fae958150673c134897db52ce5de87291f613f84df7c6d90'}\n",)),
           (246,
            248,
            ("                 'tools/carla_lane_oracle/scaled_float32_contracts.py')\n",),
            ("                 'tools/carla_lane_oracle/scaled_float32_contracts.py',\n",
             "                 'tools/carla_lane_oracle/pr760_arithmetic_stage.py')\n")),
           (718,
            719,
            ("for _module in (source, guard, _sibling('affected'), _sibling('cache_key'), "
             'consumer_ledger, station, shared_helpers, runtime_view, deviation, witness_format, '
             'typed_boundary, conditioned_cubic, scaled_float32):\n',),
            ("for _module in (source, guard, _sibling('affected'), _sibling('cache_key'), "
             'consumer_ledger, station, shared_helpers, runtime_view, deviation, witness_format, '
             'typed_boundary, conditioned_cubic, scaled_float32, pr760_stage):\n',)),
           (771,
            772,
            ('               vars(scaled_float32))\n',),
            ('               vars(scaled_float32), vars(pr760_stage))\n',)),
           (808,
            810,
            (),
            ('    pr760_stage.verify_stage_data()\n', '    _pr760_authority_data()\n')),
           (921,
            922,
            ('                        math_entries=None):\n',),
            ('                        math_entries=None, example_entries=None):\n',)),
           (936,
            938,
            ('    inert. Include roots receive structural checks only: maintained generation\n',),
            ('    inert; entry scoping preserves this wiki guard. Include roots receive\n',
             '    structural checks only: maintained generation\n')),
           (951,
            958,
            (),
            ('    # PR760 examples add tools/generators providers and example roots. These\n',
             '    # namespaces compete only at freshly censused compiled lookup directories;\n',
             '    # exact consumed module/package coordinates remain unconditional below.\n',
             '    if example_entries is not None and (type(example_entries) is not frozenset\n',
             "            or '.' not in example_entries or any(type(path) is not str or not path\n",
             "            or Path(path).is_absolute() or '..' in Path(path).parts for path in "
             'example_entries)):\n',
             '        return False\n')),
           (967, 968, (), ('    coordinates = {path.casefold() for path in allowed}\n',)),
           (1008,
            1018,
            ('                relevant = (folded in stems or folded in prefixes or stem in '
             'stems\n',),
            ('                # Appended suffixes of exact consumed coordinates remain\n',
             '                # guarded even when their bare namespace is entry-scoped.\n',
             '                # This includes origin sidecars, allowed only when explicitly\n',
             '                # enumerated for an include root.\n',
             '                coordinate_suffix = any(\n',
             '                    (relative[:-len(name)] + name[:index]).casefold() in '
             'coordinates\n',
             "                    for index, character in enumerate(name) if character == '.')\n",
             '                # Entry-scoped math still owes the historical wiki guard:\n',
             '                # only the exact regular Math.md file is an inert exception.\n',
             '                relevant = (coordinate_suffix or folded in stems or folded in '
             'prefixes or stem in stems\n')),
           (1022,
            1026,
            ('                                     or relative_dir.casefold() in math_entries)\n',),
            ('                                     or relative_dir.casefold() in math_entries\n',
             "                                     or relative_dir.casefold() == 'docs/wiki')\n",
             "                                and (scoped_name not in ('tools', 'examples', "
             "'generators') or example_entries is None\n",
             '                                     or relative_dir.casefold() in '
             'example_entries)\n')),
           (1070,
            1170,
            (),
            ('\n',
             '\n',
             'def _pr760_image_selected(image):\n',
             '    """Identify one complete cohort inside an already observed byte image."""\n',
             '    current = tuple(image.get(path) is not None and\n',
             "        sha(image[path]) == pr760_stage.EDGES[path]['after_sha256']\n",
             '        for path in pr760_stage.EXAMPLE_PATHS)\n',
             "    require(not any(current) or all(current), 'mixed PR760 example source image')\n",
             '    return all(current)\n',
             '\n',
             '\n',
             'def _pr760_select(root, *, _snapshots=None, _operation=None, _inputs=None, '
             '_input_owner=None):\n',
             '    image = {}\n',
             '    for path in pr760_stage.EXAMPLE_PATHS:\n',
             '        raw = (_observe_bytes(root, path, _regular(root, path).read_bytes(), '
             '_operation=_operation)\n',
             '               if _inputs is None else _inputs.raw(_input_owner, root, path))\n',
             "        require(type(raw) is bytes, 'PR760 cohort is not physical bytes: ' + path)\n",
             '        if _snapshots is not None:\n',
             "            require(_snapshots.setdefault(path, raw) == raw, 'PR760 cohort changed: "
             "' + path)\n",
             '        image[path] = raw\n',
             '    return _pr760_image_selected(image)\n',
             '\n',
             '\n',
             'def _image_lookup_args(paths, entries, image):\n',
             '    args = _render_lookup_args(paths, entries)\n',
             '    if _pr760_image_selected(image):\n',
             "        roots = frozenset(('.', *entries,\n",
             '            *(str(Path(path).parent) for path in pr760_stage.REGISTRY_INPUT_SHA256\n',
             "              if path.endswith('.mojo') and path.startswith(('tests/', 'examples/', "
             "'bench/')))))\n",
             '        args.update(math_entries=roots, example_entries=roots)\n',
             '    return args\n',
             '\n',
             '\n',
             'def _pr760_admit(root, *, _inputs=None, _input_owner=None, _operation=None, '
             '_selection=None):\n',
             '    """Reuse only the current concrete owner\'s admitted immutable image."""\n',
             '    if _selection is not None:\n',
             '        caller = sys._getframe(1)\n',
             '        require(caller.f_globals is globals() and caller.f_code in\n',
             '                (_live_function_code(_shared_helper_bindings),\n',
             '                 _live_function_code(_scaled_float32_bindings)),\n',
             "                'unowned PR760 selection')\n",
             '        parent = caller.f_back\n',
             '        require(parent is not None and parent.f_globals is globals()\n',
             '                and parent.f_code is _live_function_code(verify)\n',
             "                and parent.f_locals.get('pr760') is _selection,\n",
             "                'PR760 selection must come from the complete physical gate')\n",
             '        return\n',
             '    if _inputs is not None:\n',
             '        _inputs._check(_input_owner, root)\n',
             "        require(_pr760_image_selected(_inputs._raw), 'owned image is not PR760')\n",
             '    elif _operation is not None:\n',
             '        _operation_record(_operation, root, exact=True)\n',
             "        require(_pr760_image_selected(_operation._raw), 'operation image is not "
             "PR760')\n",
             '    else:\n',
             '        verify(root, exact=True)\n',
             '    pr760_stage.verify_stage_data()\n',
             '\n',
             '\n',
             'def _pr760_composed_edges(leaf, bindings):\n',
             '    selected = tuple(path for path in leaf.SOURCE_PATHS\n',
             '        if bindings.get(path) == leaf.AFTER_SHA256[path]\n',
             '        or (path in pr760_stage.CARLA_REGISTRY_PATHS and\n',
             "            bindings.get(path) == pr760_stage.EDGES[path]['after_sha256']))\n",
             '    edges = leaf.edges(selected)\n',
             '    for path in selected:\n',
             '        if bindings[path] != leaf.AFTER_SHA256[path]:\n',
             '            edge = pr760_stage.EDGES[path]\n',
             "            require(edge['before_sha256'] == leaf.AFTER_SHA256[path],\n",
             "                    'PR760 historical helper join changed: ' + path)\n",
             "            edges[path] = {**edges[path], 'after_sha256': edge['after_sha256'],\n",
             "                          'after_token_sha256': edge['after_token_sha256'],\n",
             "                          'provenance_after_sha256': edge['before_sha256']}\n",
             '    return edges\n',
             '\n',
             '\n',
             'def provenance_after_sha256(edge):\n',
             '    """Authenticate the historical comparison target separately from physical '
             'bytes."""\n',
             "    require(type(edge) is dict, 'invalid provenance edge')\n",
             "    if 'provenance_after_sha256' not in edge:\n",
             "        return edge['after_sha256']\n",
             "    require(type(edge.get('path')) is str, 'invalid provenance edge')\n",
             '    pr760_stage.verify_stage_data()\n',
             "    path = edge['path']\n",
             '    require(path in pr760_stage.CARLA_REGISTRY_PATHS,\n',
             "            'unregistered provenance edge')\n",
             '    leaf = (shared_helpers if path in shared_helpers.SOURCE_PATHS else\n',
             '            scaled_float32 if path in scaled_float32.SOURCE_PATHS else None)\n',
             "    require(leaf is not None, 'provenance field is not a historical helper edge')\n",
             '    prior = leaf.edges((path,))[path]\n',
             '    current = pr760_stage.EDGES[path]\n',
             "    require(current['before_sha256'] == prior['after_sha256']\n",
             "            and edge['provenance_after_sha256'] == current['before_sha256']\n",
             '            and all(edge[field] == current[field] for field in\n',
             "                    ('after_sha256', 'after_token_sha256'))\n",
             "            and edge['before_sha256'] == prior['before_sha256']\n",
             "            and ('before_token_sha256' in edge) == ('before_token_sha256' in "
             'prior)\n',
             "            and ('before_token_sha256' not in prior or\n",
             "                 edge['before_token_sha256'] == prior['before_token_sha256']),\n",
             "            'provenance edge does not compose exact physical and historical "
             "endpoints')\n",
             "    return current['before_sha256']\n")),
           (1487,
            1488,
            ('                        **_render_lookup_args(self._resolver_paths, '
             'self._entries))\n',),
            ('                        **_image_lookup_args(self._resolver_paths, self._entries, '
             'self._raw))\n',)),
           (1536,
            1539,
            ("            'seed_count_contracts.py': ('verify_score',)}\n",),
            ("            'seed_count_contracts.py': ('verify_score',),\n",
             "            'sum2_guard_contracts.py': ('verify',),\n",
             "            'lane_order_contracts.py': ('verify',)}\n")),
           (1540,
            1557,
            (),
            ('\n',
             'def _canonical_inventory_admission_frame(frame):\n',
             '    """Only the two new canonical inventory entries may own a public scope."""\n',
             "    filename = frame.f_globals.get('__file__')\n",
             '    name = Path(filename).name if type(filename) is str else None\n',
             "    if (name not in ('sum2_guard_contracts.py', 'lane_order_contracts.py')\n",
             "            or frame.f_code.co_name != 'verify'):\n",
             '        return True\n',
             "    module = guard if name == 'sum2_guard_contracts.py' else lane_order\n",
             "    registered = sys.modules.get((__package__ + '.' if __package__ else '') + "
             'name[:-3])\n',
             "    candidate = frame.f_globals.get('verify')\n",
             '    return (type(module) is types.ModuleType and registered is module\n',
             '            and frame.f_globals is vars(module)\n',
             '            and type(candidate) is types.FunctionType\n',
             '            and candidate.__globals__ is frame.f_globals\n',
             '            and candidate.__code__ is frame.f_code\n',
             "            and '__wrapped__' not in candidate.__dict__)\n")),
           (1565,
            1567,
            (),
            ('    if not _canonical_inventory_admission_frame(frame):\n',
             '        return nullcontext()\n')),
           (1584,
            1586,
            (),
            ('        require(_canonical_inventory_admission_frame(frame),\n',
             "                'public inventory admission requires its canonical owner')\n")),
           (1608,
            1614,
            (),
            ("        owner_filename = self._owner_frame.f_globals.get('__file__')\n",
             '        inventory_owner = (type(owner_filename) is str\n',
             "            and Path(owner_filename).name in ('sum2_guard_contracts.py', "
             "'lane_order_contracts.py')\n",
             "            and self._owner_frame.f_code.co_name == 'verify')\n",
             '        if inventory_owner and not _canonical_inventory_admission_frame(frame):\n',
             '            return False\n')),
           (2553,
            2554,
            ('            require(stage_args == _render_lookup_args(resolver_paths, '
             'self._include_entries),\n',),
            ('            require(stage_args == _image_lookup_args(resolver_paths, '
             'self._include_entries, self._raw),\n',)),
           (2717,
            2718,
            ('                    **_render_lookup_args(self._resolver_paths, self._entries))\n',),
            ('                    **_image_lookup_args(self._resolver_paths, self._entries, '
             'self._raw))\n',)),
           (2720,
            2721,
            ('                    **_render_lookup_args(self._resolver_paths, '
             'self._include_entries)),\n',),
            ('                    **_image_lookup_args(self._resolver_paths, '
             'self._include_entries, self._raw)),\n',)),
           (2808,
            2809,
            ('                                **_render_lookup_args(self._resolver_paths, '
             'self._entries)),\n',),
            ('                                **_image_lookup_args(self._resolver_paths, '
             'self._entries, self._raw)),\n',)),
           (2983,
            2984,
            ('                            _input_owner=None, _operation=None):\n',),
            ('                            _input_owner=None, _operation=None, _pr760=None):\n',)),
           (3003,
            3019,
            (),
            ('    current = bool(_pr760) or any(name in pr760_stage.CARLA_REGISTRY_PATHS\n',
             "        and sha(raw) == pr760_stage.EDGES[name]['after_sha256']\n",
             '        for name, raw in sources.items())\n',
             '    if not current:\n',
             '        # Exact pre-extraction sources do not import their helper provider.\n',
             '        # Probe only live edges; a current source still selects full PR760\n',
             '        # admission above, including every physical provider it requires.\n',
             '        for name in {name for path in selected\n',
             '                     if sha(sources[path]) != shared_helpers.BEFORE_SHA256[path]\n',
             '                     for name in shared_helpers.PROVIDER_PATHS[path]}:\n',
             '            raw = observe(name)\n',
             '            if name in pr760_stage.CARLA_REGISTRY_PATHS and sha(raw) == '
             "pr760_stage.EDGES[name]['after_sha256']:\n",
             '                current = True\n',
             '    if current:\n',
             '        _pr760_admit(root, _inputs=_inputs, _input_owner=_input_owner,\n',
             '                    _operation=_operation, _selection=_pr760)\n')),
           (3021,
            3025,
            (),
            ("        prior = (_pr760['predecessors'][path] if _pr760 and path in "
             "_pr760['predecessors']\n",
             "                 else pr760_stage.predecessor_source(path, raw.decode('utf-8'))\n",
             '                 if current and path in pr760_stage.CARLA_REGISTRY_PATHS else '
             "raw.decode('utf-8'))\n",
             "        raw = prior.encode('utf-8')\n")),
           (3042,
            3045,
            (),
            ('        if current and path in pr760_stage.CARLA_REGISTRY_PATHS:\n',
             "            historical = (_pr760['predecessors'][path] if _pr760 else\n",
             '                pr760_stage.predecessor_source(path, '
             "raw.decode('utf-8'))).encode('utf-8')\n")),
           (3056,
            3067,
            (),
            ('    if current:\n',
             "        texts = {path: (_pr760['predecessors'][path] if _pr760 and path in "
             "_pr760['predecessors']\n",
             '            else pr760_stage.predecessor_source(path, text)\n',
             '            if path in pr760_stage.CARLA_REGISTRY_PATHS else text) for path, text in '
             'texts.items()}\n',
             "        for path in ('tools/carla_lane_oracle/pr760_arithmetic_stage.py', "
             'PR760_IMAGE,\n',
             '                     PR760_OWNER_PREDECESSOR):\n',
             '            bound[path] = observe(path)\n',
             '        require(sha(bound[PR760_IMAGE]) == PR760_IMAGE_SHA256\n',
             '                and sha(bound[PR760_OWNER_PREDECESSOR]) == '
             'PR760_OWNER_PREDECESSOR_SHA256\n',
             "                and sha(bound['tools/carla_lane_oracle/pr760_arithmetic_stage.py']) "
             '== PR760_STAGE_SHA256,\n',
             "                'PR760 shared-helper authority changed')\n")),
           (3167,
            3168,
            ('    return shared_helpers.edges(tuple(path for path in shared_helpers.SOURCE_PATHS\n',
             '        if bindings.get(path) == shared_helpers.AFTER_SHA256[path]))\n'),
            ('    return _pr760_composed_edges(shared_helpers, bindings)\n',)),
           (3191,
            3192,
            ('                             _input_owner=None, _operation=None, _context=None):\n',),
            ('                             _input_owner=None, _operation=None, _context=None, '
             '_pr760=None):\n',)),
           (3215,
            3228,
            ("    active = scaled_float32.verify_sources({name: raw.decode('utf-8') for name, raw "
             'in sources.items()})\n',),
            ('    current = bool(_pr760) or any(name in pr760_stage.CARLA_REGISTRY_PATHS\n',
             "        and sha(raw) == pr760_stage.EDGES[name]['after_sha256']\n",
             '        for name, raw in sources.items())\n',
             '    if current:\n',
             '        _pr760_admit(root, _inputs=_inputs, _input_owner=_input_owner,\n',
             '                    _operation=_operation, _selection=_pr760)\n',
             '    def historical(name, raw):\n',
             '        if current and name == '
             "'tools/carla_lane_oracle/test_scaled_float32_contracts.py':\n",
             "            return qualification_predecessor_bytes(name, raw).decode('utf-8')\n",
             "        return (_pr760['predecessors'][name] if _pr760 and name in "
             "_pr760['predecessors']\n",
             "                else pr760_stage.predecessor_source(name, raw.decode('utf-8'))\n",
             '                if current and name in pr760_stage.CARLA_REGISTRY_PATHS else '
             "raw.decode('utf-8'))\n",
             '    active = scaled_float32.verify_sources({name: historical(name, raw) for name, '
             'raw in sources.items()})\n')),
           (3234,
            3235,
            ("        require(sha(observe(name)) == digest, 'scaled correctness input changed: ' + "
             'name)\n',),
            ("        require(sha(historical(name, observe(name))) == digest, 'scaled correctness "
             "input changed: ' + name)\n",)),
           (3260,
            3265,
            (),
            ('    if current:\n',
             "        for name, digest in (('tools/carla_lane_oracle/pr760_arithmetic_stage.py', "
             'PR760_STAGE_SHA256),\n',
             '                             (PR760_IMAGE, PR760_IMAGE_SHA256),\n',
             '                             (PR760_OWNER_PREDECESSOR, '
             'PR760_OWNER_PREDECESSOR_SHA256)):\n',
             "            require(sha(observe(name)) == digest, 'PR760 scaled authority changed: ' "
             '+ name)\n')),
           (3348,
            3349,
            ('    return scaled_float32.edges(tuple(name for name in scaled_float32.SOURCE_PATHS\n',
             '        if bindings.get(name) == scaled_float32.AFTER_SHA256[name]))\n'),
            ('    return _pr760_composed_edges(scaled_float32, bindings)\n',)),
           (3446,
            3454,
            ('                require(type(raw) is bytes and sha(_historical_typed_text(path, '
             "raw.decode('utf-8'))) == expected,\n",),
            ("                require(type(raw) is bytes, 'witness-format input is not physical "
             "bytes: ' + path)\n",
             '                historical = raw\n',
             '                if (path == '
             "'tools/carla_lane_oracle/test_witness_format_contracts.py'\n",
             '                        and sha(raw) != expected):\n',
             '                    # This one qualification edge joins the unchanged typed\n',
             '                    # endpoint. Observations, rereads and receipts stay physical.\n',
             '                    historical = qualification_predecessor_bytes(path, raw)\n',
             '                require(sha(_historical_typed_text(path, '
             "historical.decode('utf-8'))) == expected,\n")),
           (3470,
            3471,
            ('def _historical_typed_text(path, text):\n',),
            ('def _historical_typed_text(path, text, *, pr760=False):\n',)),
           (3472,
            3474,
            (),
            ('    if pr760 and path in pr760_stage.CARLA_REGISTRY_PATHS:\n',
             '        text = pr760_stage.predecessor_source(path, text)\n')),
           (3477,
            3478,
            ('def _typed_boundary_bindings(root, *, _snapshots=None, _operation=None):\n',),
            ('def _typed_boundary_bindings(root, *, _snapshots=None, _operation=None, '
             '_selection=None):\n',)),
           (3481,
            3494,
            (),
            ('        if _pr760_select(root, _snapshots=_snapshots, _operation=_operation):\n',
             '            if (type(_operation) is _InvariantInputs and _operation._state == '
             "'active'\n",
             '                    and not _operation._capturing):\n',
             '                pr760_stage.verify_stage_data()\n',
             '                typed_boundary.verify_authority()\n',
             '                conditioned_cubic.verify_authority()\n',
             "                require(_pr760_image_selected(_operation._raw), 'operation cohort "
             "changed')\n",
             '                return {path: sha(raw) for path, raw in _operation._raw.items()}\n',
             '            candidate = _pr760_candidate_bindings(root, _snapshots=_snapshots, '
             '_operation=_operation)\n',
             '            if _selection is not None:\n',
             "                require(type(_selection) is dict and not _selection, 'invalid PR760 "
             "selection output')\n",
             '                _selection.update(candidate)\n',
             "            return candidate['bindings']\n")),
           (3558,
            3560,
            ('    edge = typed_boundary.EDGES.get(path)\n',),
            ('    edge = (pr760_stage.EDGES.get(path) if path in '
             'pr760_stage.CARLA_REGISTRY_PATHS\n',
             '            else typed_boundary.EDGES.get(path))\n')),
           (3578,
            3580,
            ('        if not (typed_boundary.is_current(path, text) or\n',),
            ('        new_endpoint = path in pr760_stage.CARLA_REGISTRY_PATHS and '
             "source.token_sha256(text) == edge['after_token_sha256']\n",
             '        if not (new_endpoint or typed_boundary.is_current(path, text) or\n')),
           (3584,
            3585,
            ('        require(typed_boundary.is_current(path, raw),\n',),
            ("        require((sha(raw) == edge['after_sha256']) if new_endpoint else "
             'typed_boundary.is_current(path, raw),\n',)),
           (3603,
            3607,
            ('        return _historical_typed_text(path, physical_text)\n',),
            ('        if new_endpoint:\n',
             '            require(_pr760_select(root, _operation=_operation,\n',
             "                _inputs=_inputs, _input_owner=_input_owner), 'new endpoint lacks "
             "complete PR760 image')\n",
             '        return _historical_typed_text(path, physical_text, pr760=new_endpoint)\n')),
           (3646,
            3648,
            ('        typed_bindings = _typed_boundary_bindings(root, _snapshots=snapshots,\n',),
            ('        pr760 = {}\n',
             '        typed_bindings = _typed_boundary_bindings(root, _snapshots=snapshots, '
             '_selection=pr760,\n')),
           (3670,
            3674,
            ('        scaled_bindings = _scaled_float32_bindings(root, _snapshots=snapshots)\n',
             '        scaled_edges = scaled_float32.edges(tuple(name for name in '
             'scaled_float32.SOURCE_PATHS\n',
             '            if scaled_bindings.get(name) == scaled_float32.AFTER_SHA256[name]))\n',
             '        helper_bindings = _shared_helper_bindings(root, _snapshots=snapshots)\n',
             '        helper_edges = shared_helpers.edges(tuple(\n',
             '            path for path in shared_helpers.SOURCE_PATHS\n',
             '            if helper_bindings.get(path) == shared_helpers.AFTER_SHA256[path]))\n'),
            ('        scaled_bindings = _scaled_float32_bindings(root, _snapshots=snapshots, '
             '_pr760=pr760 or None)\n',
             '        scaled_edges = _pr760_composed_edges(scaled_float32, scaled_bindings)\n',
             '        helper_bindings = _shared_helper_bindings(root, _snapshots=snapshots, '
             '_pr760=pr760 or None)\n',
             '        helper_edges = _pr760_composed_edges(shared_helpers, helper_bindings)\n')),
           (3681,
            3683,
            (),
            ('        if pr760:\n',
             "            resolver_paths |= set().union(*pr760['closures'].values())\n")),
           (3689,
            3690,
            ('                    **_render_lookup_args(resolver_paths, '
             "record['entry_directories'])),\n",),
            ('                    **_image_lookup_args(resolver_paths, '
             "record['entry_directories'], snapshots)),\n",)),
           (3691,
            3709,
            ("        known = {p.as_posix() for p in _sibling('cache_key').input_paths(root) if "
             "p.suffix == '.mojo'}\n",
             '        # #720 resolves from actual compiled entrypoint directories. Bind all\n',
             "        # maintained production entry contexts and each witness's own root.\n",
             '        live_sources = {}\n',
             '        for path in sorted(known):\n',
             '            raw = _regular(root, path).read_bytes()\n',
             '            previous = snapshots.setdefault(path, raw)\n',
             "            require(previous == raw, 'source changed before entrypoint census: ' + "
             'path)\n',
             '            live_sources[path] = _physical_text(raw)\n',
             "        entries = _sibling('affected').entry_directories(live_sources)\n",
             "        require(entries == record['entry_directories'], 'maintained entrypoint "
             "directories changed')\n"),
            ('        if pr760:\n',
             '            # The private whole-image check already consumed these exact bytes.\n',
             "            # Reuse only this call's pure census/closure results; final physical\n",
             '            # sweeps and include-root checks below remain mandatory.\n',
             "            known = set(pr760['known'])\n",
             "            entries = pr760['entries']\n",
             '        else:\n',
             "            known = {p.as_posix() for p in _sibling('cache_key').input_paths(root) "
             "if p.suffix == '.mojo'}\n",
             '            # #720 resolves from actual compiled entrypoint directories. Bind all\n',
             "            # maintained production entry contexts and each witness's own root.\n",
             '            live_sources = {}\n',
             '            for path in sorted(known):\n',
             '                raw = _regular(root, path).read_bytes()\n',
             '                previous = snapshots.setdefault(path, raw)\n',
             "                require(previous == raw, 'source changed before entrypoint census: ' "
             '+ path)\n',
             '                live_sources[path] = _physical_text(raw)\n',
             "            entries = _sibling('affected').entry_directories(live_sources)\n",
             "            require(entries == record['entry_directories'], 'maintained entrypoint "
             "directories changed')\n")),
           (3713,
            3714,
            ('            stage_args = _render_lookup_args(resolver_paths, stage_entries)\n',),
            ('            stage_args = _image_lookup_args(resolver_paths, stage_entries, '
             'snapshots)\n',)),
           (3717,
            3746,
            ('        require(dependency_inventory(root, roots=(*SOURCE_PATHS, '
             "*record['inventory']), entries=entries,\n",
             '                                     _known=known, _snapshots=snapshots)\n',
             '                == (set(typed_boundary.PRODUCTION_CLOSURE) if typed_bindings else\n',
             "                    set(record['dependency_inventory']) | helper_closure), "
             "'production import inventory changed')\n",
             '        native_found = _native_dependency_inventory(root, '
             'witnesses=NATIVE_WITNESSES,\n',
             '            _known=known, _snapshots=snapshots)\n',
             '        require(native_found == (set(typed_boundary.NATIVE_CLOSURE) if '
             'typed_bindings else\n',
             "                set(record['native_dependency_inventory']) | helper_closure),\n",
             "                'native witness import inventory changed')\n",
             '        if typed_bindings:\n',
             '            current_native = set()\n',
             '            test_paths = tuple(path for path in typed_boundary.TESTS if '
             "path.endswith('.mojo'))\n",
             '            for parent in sorted({str(Path(path).parent) for path in test_paths}):\n',
             '                current_native.update(dependency_inventory(root,\n',
             '                    roots=tuple(path for path in test_paths if '
             'str(Path(path).parent) == parent),\n',
             '                    entries=(parent,), _known=known, _snapshots=snapshots))\n',
             '            require(current_native == set(typed_boundary.TYPED_NATIVE_CLOSURE),\n',
             "                    'typed native test import inventory changed')\n",
             '            current_production = dependency_inventory(root,\n',
             '                roots=tuple(path for path in (*typed_boundary.SOURCE_PATHS, '
             '*typed_boundary.NEW_INPUTS)\n',
             "                    if path.endswith('.mojo') and not path.startswith(('tests/', "
             "'tools/', 'examples/', 'bench/'))),\n",
             '                entries=entries, _known=known, _snapshots=snapshots)\n',
             '            require(current_production == '
             'set(typed_boundary.TYPED_PRODUCTION_CLOSURE),\n',
             "                    'typed production import inventory changed')\n"),
            ('        if not pr760:\n',
             '            require(dependency_inventory(root, roots=(*SOURCE_PATHS, '
             "*record['inventory']), entries=entries,\n",
             '                                         _known=known, _snapshots=snapshots)\n',
             "                    == (pr760['closures']['PRODUCTION_CLOSURE'] if pr760 else\n",
             '                        set(typed_boundary.PRODUCTION_CLOSURE) if typed_bindings '
             'else\n',
             "                        set(record['dependency_inventory']) | helper_closure), "
             "'production import inventory changed')\n",
             '            native_found = _native_dependency_inventory(root, '
             'witnesses=NATIVE_WITNESSES,\n',
             '                _known=known, _snapshots=snapshots)\n',
             "            require(native_found == (pr760['closures']['NATIVE_CLOSURE'] if pr760 "
             'else\n',
             '                    set(typed_boundary.NATIVE_CLOSURE) if typed_bindings else\n',
             "                    set(record['native_dependency_inventory']) | helper_closure),\n",
             "                    'native witness import inventory changed')\n",
             '            if typed_bindings:\n',
             '                current_native = set()\n',
             '                test_paths = tuple(path for path in typed_boundary.TESTS if '
             "path.endswith('.mojo'))\n",
             '                for parent in sorted({str(Path(path).parent) for path in '
             'test_paths}):\n',
             '                    current_native.update(dependency_inventory(root,\n',
             '                        roots=tuple(path for path in test_paths if '
             'str(Path(path).parent) == parent),\n',
             '                        entries=(parent,), _known=known, _snapshots=snapshots))\n',
             "                require(current_native == (pr760['closures']['TYPED_NATIVE_CLOSURE'] "
             'if pr760 else\n',
             '                                          '
             'set(typed_boundary.TYPED_NATIVE_CLOSURE)),\n',
             "                        'typed native test import inventory changed')\n",
             '                current_production = dependency_inventory(root,\n',
             '                    roots=tuple(path for path in (*typed_boundary.SOURCE_PATHS, '
             '*typed_boundary.NEW_INPUTS)\n',
             "                        if path.endswith('.mojo') and not path.startswith(('tests/', "
             "'tools/', 'examples/', 'bench/'))),\n",
             '                    entries=entries, _known=known, _snapshots=snapshots)\n',
             '                require(current_production == '
             "(pr760['closures']['TYPED_PRODUCTION_CLOSURE'] if pr760 else\n",
             '                                              '
             'set(typed_boundary.TYPED_PRODUCTION_CLOSURE)),\n',
             "                        'typed production import inventory changed')\n")),
           (3780,
            3785,
            ('                historical = _historical_typed_text(path, '
             "raw.decode('utf-8')).encode('utf-8') if path in typed_boundary.EDGES and "
             'typed_bindings else raw\n',),
            ('                historical = raw\n',
             "                if pr760 and path in pr760['predecessors'] and path not in "
             'helper_edges and path not in scaled_edges:\n',
             "                    historical = pr760['predecessors'][path].encode('utf-8')\n",
             '                if path in typed_boundary.EDGES and typed_bindings:\n',
             '                    historical = _historical_typed_text(path, '
             "historical.decode('utf-8')).encode('utf-8')\n")),
           (3790,
            3797,
            ('        production = set() if _capture is not None or _public_admission is not None '
             'else None\n',
             '        observed_inventory = (inventory(root, _snapshots=snapshots) if production is '
             'None else\n',
             '                              inventory(root, _snapshots=snapshots, '
             '_production=production))\n'),
            ('        if pr760:\n',
             "            production = set(pr760['production'])\n",
             "            observed_inventory = pr760['inventory']\n",
             '        else:\n',
             '            production = set() if _capture is not None or _public_admission is not '
             'None else None\n',
             '            observed_inventory = (inventory(root, _snapshots=snapshots) if '
             'production is None else\n',
             '                                  inventory(root, _snapshots=snapshots, '
             '_production=production))\n')),
           (3812,
            3815,
            (),
            ('        if pr760:\n',
             '            require({path.relative_to(root).as_posix() for path in '
             'guard.production_mojo_paths(root)}\n',
             "                    == production, 'PR760 production path inventory changed during "
             "verification')\n")),
           (3818,
            3819,
            ('                    **_render_lookup_args(resolver_paths, '
             "record['entry_directories']))\n",),
            ('                    **_image_lookup_args(resolver_paths, '
             "record['entry_directories'], snapshots))\n",)),
           (3950,
            3954,
            ('    changed = {p for p, text in texts.items() if p in SOURCE_PATHS\n',
             '               and source.token_sha256(text) != BEFORE_TOKEN_SHA256[p]}\n'),
            ('    changed = {p for p, text in texts.items() if\n',
             '               (p in SOURCE_PATHS and source.token_sha256(text) != '
             'BEFORE_TOKEN_SHA256[p])\n',
             '               or (p in pr760_stage.CARLA_REGISTRY_PATHS and\n',
             '                   source.token_sha256(text) == '
             "pr760_stage.EDGES[p]['after_token_sha256'])}\n")),
           (3963, 3964, (), ('    pr760 = bool(_pr760_select(root))\n',)),
           (3975,
            3976,
            ('        text = _historical_typed_text(path, _physical_text(physical))\n',),
            ('        text = _historical_typed_text(path, _physical_text(physical), '
             'pr760=pr760)\n',)),
           (3983,
            3984,
            ('            require(raw == physical and source.token_sha256(text) == '
             'source.token_sha256(_historical_typed_text(path, _physical_text(raw))),\n',),
            ('            require(raw == physical and source.token_sha256(text) == '
             'source.token_sha256(_historical_typed_text(path, _physical_text(raw), '
             'pr760=pr760)),\n',)),
           (4070,
            4071,
            (),
            ('        current_image = _pr760_select(root, _operation=_operation)\n',)),
           (4075,
            4082,
            ('            require(typed_boundary.is_current(path, current),\n',),
            ('            qualification = (current_image and path ==\n',
             "                'tools/carla_lane_oracle/test_witness_format_contracts.py')\n",
             '            projected = (pr760_stage.predecessor_source(path, '
             "current.decode('utf-8'))\n",
             '                if current_image and path in pr760_stage.EXAMPLE_PATHS else\n',
             "                qualification_predecessor_bytes(path, current).decode('utf-8')\n",
             "                if qualification else current.decode('utf-8'))\n",
             '            require(typed_boundary.is_current(path, projected),\n')),
           (4084,
            4087,
            (),
            ('            if current_image and (path in pr760_stage.EXAMPLE_PATHS or '
             'qualification):\n',
             '                edge.update(after_sha256=sha(current),\n',
             '                            '
             "after_token_sha256=source.token_sha256(current.decode('utf-8')))\n")),
           (4178,
            5001,
            (),
            ('PR760_IMPLEMENTATION_PREDECESSORS = '
             "{'tools/carla_lane_oracle/pr760-border_parser-predecessor.txt': "
             "'d7a638dcf4d5cadabd183be03cbea08945e9bb5351f4b96dd24803d42fa5626e',\n",
             " 'tools/carla_lane_oracle/pr760-seed_count-predecessor.txt': "
             "'ff4a330326fd69bc649e6f235d1f05db4ed40e6b76b1d75e66a4474741c16345',\n",
             " 'tools/carla_lane_oracle/pr760-source-adapter-predecessor.txt': "
             "'83fdd35b61f0dc7739160c113ae6b4558ad07d45ffded22b7062bc9a209032d0',\n",
             " 'tools/carla_lane_oracle/pr760-winner_sign-predecessor.txt': "
             "'2ed96052d6568fee1bb7700515b7ad03bd38edafc7ca413fc1c03bb9ad5f6aad'}\n",
             'PR760_IMPLEMENTATION_SUCCESSORS = '
             "{'tools/carla_lane_oracle/border_parser_contracts.py': "
             "'734d7b24aaf4e9f537cd7f0d7c7b8094d9c29106770b66c4a7a24cab74604dd4',\n",
             " 'tools/carla_lane_oracle/seed_count_contracts.py': "
             "'daa8f391a18e54a3fae958150673c134897db52ce5de87291f613f84df7c6d90',\n",
             " 'tools/carla_lane_oracle/source_contracts.py': "
             "'ebb6e75b90528b5456485433d470de36e6b33e4df98139dd0acadda75a57adf5',\n",
             " 'tools/carla_lane_oracle/winner_sign_contracts.py': "
             "'f850902634073364fe2407b00d12e9fdfb2ecfc6cf2a03414269fbb7984a8a7f'}\n",
             '\n',
             '\n',
             'def _pr760_authority_data():\n',
             '    """Bind successor data selectors to literal executing-code constants."""\n',
             '    require((PR760_STAGE_SHA256, PR760_IMAGE, PR760_IMAGE_SHA256, '
             'PR760_OWNER_PREDECESSOR, PR760_OWNER_PREDECESSOR_SHA256) == (\n',
             "        '03757bafb02fbb3908919839c18d5c2c443f46469aeb01393dee57ae22054359',\n",
             "        'tools/carla_lane_oracle/pr760-source-image.json',\n",
             "        'ef91b7edab2c8a597aeedc90f86e834d5227aad5770ebe39e0438944f246f7cf',\n",
             "        'tools/carla_lane_oracle/pr760-owner-predecessor.txt',\n",
             "        '6138ba2dcac394c716ea9ed32e74e0c6d15857d5c605fc82304d21d0c80fdc69',\n",
             "    ), 'PR760 authority selectors changed')\n",
             '\n',
             '\n',
             'def qualification_predecessor_bytes(path, raw):\n',
             '    """Pure exact comparison for eight reviewed Python witness successors only.\n',
             '\n',
             '    Physical owners still consume and return actual bytes. This function grants\n',
             '    neither source-image admission nor a receipt, and never reads projected files.\n',
             '    """\n',
             '    executing_checker_bindings()\n',
             '    require(type(path) is str and type(raw) is bytes,\n',
             "            'qualification predecessor requires builtin source bytes')\n",
             "    rows = {'tools/carla_lane_oracle/test_common758_current_successor.py': "
             "('010cd7008a96b80e0aea26734dafb7be0068f677c5dd73af8fb15db585e70b9f',\n",
             '                                                                     '
             "'bae8693bfbc3557a53e54f3dea90c5bf44583d5fde349a6c24c16045acec10e4',\n",
             '                                                                     ((13,\n',
             '                                                                       14,\n',
             '                                                                       (),\n',
             "                                                                       ('import "
             "_full_audit_test_fixtures as '\n",
             '                                                                        '
             "'fixtures\\n',)),\n",
             '                                                                      (84,\n',
             '                                                                       90,\n',
             '                                                                       (),\n',
             "                                                                       ('    "
             "@classmethod\\n',\n",
             "                                                                        '    def "
             "setUpClass(cls):\\n',\n",
             "                                                                        '        "
             "baseline = '\n",
             '                                                                        '
             "'fixtures.common758_leaf_texts(ROOT)\\n',\n",
             "                                                                        '        "
             "cls.current = {name: '\n",
             '                                                                        '
             "'baseline[name] for name in '\n",
             '                                                                        '
             "'typed.SOURCE_PATHS}\\n',\n",
             "                                                                        '        '\n",
             '                                                                        '
             "'typed.verify_sources(dict(cls.current))\\n',\n",
             "                                                                        '\\n')),\n",
             '                                                                      (110,\n',
             '                                                                       111,\n',
             "                                                                       ('        '\n",
             '                                                                        '
             "'self.assertEqual(typed.BINDING_INPUTS[SELF], '\n",
             '                                                                        '
             "'_sha((ROOT/SELF).read_bytes()))\\n',),\n",
             "                                                                       ('        '\n",
             '                                                                        '
             "'self.assertEqual(typed.BINDING_INPUTS[SELF], '\n",
             '                                                                        '
             "'_sha(audit.qualification_predecessor_bytes(SELF, '\n",
             '                                                                        '
             "'(ROOT/SELF).read_bytes())))\\n',)),\n",
             '                                                                      (112,\n',
             '                                                                       113,\n',
             "                                                                       ('        '\n",
             '                                                                        '
             "'self.assertEqual(typed.BINDING_INPUTS[conditioned], '\n",
             '                                                                        '
             "'_sha((ROOT/conditioned).read_bytes()))\\n',),\n",
             "                                                                       ('        '\n",
             '                                                                        '
             "'self.assertEqual(typed.BINDING_INPUTS[conditioned], '\n",
             '                                                                        '
             "'_sha(audit.qualification_predecessor_bytes(conditioned, '\n",
             '                                                                        '
             "'(ROOT/conditioned).read_bytes())))\\n',)),\n",
             '                                                                      (121,\n',
             '                                                                       123,\n',
             "                                                                       ('        "
             "current = {p: '\n",
             '                                                                        '
             "'(ROOT/p).read_text() for p in '\n",
             '                                                                        '
             "'typed.SOURCE_PATHS}\\n',),\n",
             "                                                                       ('        "
             "current = dict(self.current)\\n',\n",
             "                                                                        '        '\n",
             '                                                                        '
             "'typed.verify_sources(current)\\n')),\n",
             '                                                                      (135,\n',
             '                                                                       137,\n',
             "                                                                       ('        "
             "current = {p: '\n",
             '                                                                        '
             "'(ROOT/p).read_text() for p in '\n",
             '                                                                        '
             "'typed.SOURCE_PATHS}\\n',),\n",
             "                                                                       ('        "
             "current = dict(self.current)\\n',\n",
             "                                                                        '        '\n",
             '                                                                        '
             "'typed.verify_sources(current)\\n')),\n",
             '                                                                      (184,\n',
             '                                                                       206,\n',
             "                                                                       ('        # "
             "Map is observed during source '\n",
             "                                                                        'admission, "
             "exact dependency binding,\\n',\n",
             "                                                                        '        # "
             "and the final image reread. '\n",
             "                                                                        'Exercise "
             "the first and final '\n",
             '                                                                        '
             "'observations.\\n',\n",
             "                                                                        '        for "
             "at_read in (1, 3):\\n'),\n",
             '                                                                       ("        # '
             'PR760\'s exact candidate has "\n',
             "                                                                        'one first "
             "and one terminal map read.\\n',\n",
             "                                                                        '        # "
             "Authenticate the actual '\n",
             "                                                                        'nested "
             "observer and establish a passing '\n",
             '                                                                        '
             "'image\\n',\n",
             "                                                                        '        # "
             "with exactly those two reads '\n",
             "                                                                        'before "
             "injecting either returned '\n",
             '                                                                        '
             "'value.\\n',\n",
             "                                                                        '        "
             "candidate = '\n",
             '                                                                        '
             "'audit._pr760_candidate_bindings\\n',\n",
             "                                                                        '        "
             "observers = [code for code in '\n",
             '                                                                        '
             "'candidate.__code__.co_consts\\n',\n",
             '                                                                        '
             "'                     if '\n",
             '                                                                        '
             "'isinstance(code, '\n",
             '                                                                        '
             "'type(candidate.__code__)) and '\n",
             '                                                                        '
             '"code.co_name == \'observe\']\\n",\n',
             "                                                                        '        '\n",
             '                                                                        '
             "'self.assertEqual(len(observers), 1)\\n',\n",
             "                                                                        '        "
             "observed_code = observers[0]\\n',\n",
             "                                                                        '        "
             "baseline_reads = []\\n',\n",
             "                                                                        '        def "
             "observe(path, *args, '\n",
             '                                                                        '
             "'**kwargs):\\n',\n",
             "                                                                        '            "
             "frame = sys._getframe(1)\\n',\n",
             "                                                                        '            "
             "if path == target and '\n",
             '                                                                        '
             "'frame.f_code is observed_code:\\n',\n",
             '                                                                        '
             "'                '\n",
             '                                                                        '
             "'self.assertIs(frame.f_globals, '\n",
             '                                                                        '
             "'vars(audit))\\n',\n",
             '                                                                        '
             "'                '\n",
             '                                                                        '
             "'self.assertIs(frame.f_back.f_code, '\n",
             '                                                                        '
             "'candidate.__code__)\\n',\n",
             '                                                                        '
             "'                '\n",
             '                                                                        '
             '"self.assertEqual(frame.f_back.f_locals[\'root\'], "\n',
             '                                                                        '
             "'ROOT)\\n',\n",
             '                                                                        '
             "'                '\n",
             '                                                                        '
             '"self.assertEqual(frame.f_locals[\'path\'], "\n',
             '                                                                        '
             '"\'extensions/carla/map.mojo\')\\n",\n',
             '                                                                        '
             "'                '\n",
             '                                                                        '
             "'baseline_reads.append(path)\\n',\n",
             "                                                                        '            "
             "return original(path, '\n",
             "                                                                        '*args, "
             "**kwargs)\\n',\n",
             "                                                                        '        "
             "with patch.object(Path, '\n",
             '                                                                        '
             '"\'read_bytes\', observe):\\n",\n',
             "                                                                        '            "
             "'\n",
             '                                                                        '
             "'audit._typed_boundary_bindings(ROOT)\\n',\n",
             "                                                                        '        '\n",
             '                                                                        '
             "'self.assertEqual(len(baseline_reads), '\n",
             "                                                                        '2)\\n',\n",
             "                                                                        '        for "
             "at_read in (1, 2):\\n')),\n",
             '                                                                      (209,\n',
             '                                                                       214,\n',
             '                                                                       '
             "('                        '\n",
             '                                                                        '
             "'audit._typed_boundary_bindings.__code__):\\n',),\n",
             '                                                                       '
             "('                        '\n",
             '                                                                        '
             "'observed_code):\\n',\n",
             '                                                                        '
             "'                    frame = '\n",
             '                                                                        '
             "'sys._getframe(1)\\n',\n",
             '                                                                        '
             "'                    '\n",
             '                                                                        '
             "'self.assertIs(frame.f_globals, '\n",
             '                                                                        '
             "'vars(audit))\\n',\n",
             '                                                                        '
             "'                    '\n",
             '                                                                        '
             "'self.assertIs(frame.f_back.f_code, '\n",
             '                                                                        '
             "'candidate.__code__)\\n',\n",
             '                                                                        '
             "'                    '\n",
             '                                                                        '
             '"self.assertEqual(frame.f_back.f_locals[\'root\'], "\n',
             '                                                                        '
             "'ROOT)\\n')))),\n",
             "     'tools/carla_lane_oracle/test_scaled_float32_contracts.py': "
             "('86cb083e302ec2f3b76beaa015bf5ec6b79bc9e2ea5058f76e80bec022649931',\n",
             '                                                                  '
             "'dfed575b3625ee6dab4257055023be20d60da8a20529f729e890df22679396a6',\n",
             '                                                                  ((22,\n',
             '                                                                    24,\n',
             "                                                                    ('        "
             "cls.after = {name: '\n",
             '                                                                     '
             "'(ROOT/name).read_text() for name in '\n",
             '                                                                     '
             "'scaled.SOURCE_PATHS}\\n',),\n",
             "                                                                    ('        "
             "baseline = '\n",
             '                                                                     '
             "'fixtures.common758_leaf_texts(ROOT)\\n',\n",
             "                                                                     '        "
             "cls.after = {name: baseline[name] '\n",
             "                                                                     'for name in "
             "scaled.SOURCE_PATHS}\\n')),\n",
             '                                                                   (185,\n',
             '                                                                    186,\n',
             '                                                                    '
             "('                with patch.object(Path, '\n",
             '                                                                     '
             '"\'read_bytes\', denied), "\n',
             '                                                                     '
             "'self.assertRaises(OSError) as caught:\\n',),\n",
             '                                                                    '
             "('                with patch.object(Path, '\n",
             '                                                                     '
             '"\'read_bytes\', denied), "\n',
             '                                                                     '
             "'self.assertRaises((OSError, ValueError)) '\n",
             "                                                                     'as "
             "caught:\\n',)),\n",
             '                                                                   (187,\n',
             '                                                                    191,\n',
             '                                                                    '
             "('                '\n",
             '                                                                     '
             "'self.assertIs(caught.exception, '\n",
             '                                                                     '
             "'failure)\\n',),\n",
             '                                                                    '
             "('                cause = caught.exception\\n',\n",
             '                                                                     '
             "'                while cause.__cause__ is '\n",
             "                                                                     'not "
             "None:\\n',\n",
             '                                                                     '
             "'                    cause = '\n",
             '                                                                     '
             "'cause.__cause__\\n',\n",
             '                                                                     '
             "'                self.assertIs(cause, '\n",
             '                                                                     '
             "'failure)\\n')),\n",
             '                                                                   (477,\n',
             '                                                                    483,\n',
             "                                                                    ('        "
             "self.original = {name: (ROOT / '\n",
             '                                                                     '
             "'name).read_bytes() for name in '\n",
             '                                                                     '
             "'self.paths}\\n',),\n",
             "                                                                    ('        "
             "baseline = '\n",
             '                                                                     '
             "'fixtures.common758_leaf_texts(ROOT)\\n',\n",
             "                                                                     '        "
             "self.original = {name: '\n",
             '                                                                     '
             '"(baseline[name].encode(\'utf-8\') if name in "\n',
             '                                                                     '
             "'baseline\\n',\n",
             '                                                                     '
             "'                         else '\n",
             '                                                                     '
             "'(ROOT/name).read_bytes()) for name in '\n",
             '                                                                     '
             "'self.paths}\\n',\n",
             "                                                                     '        "
             "witness = '\n",
             '                                                                     '
             '"\'tools/carla_lane_oracle/test_scaled_float32_contracts.py\'\\n",\n',
             "                                                                     '        "
             "self.original[witness] = '\n",
             '                                                                     '
             "'cleanup.qualification_predecessor_bytes(\\n',\n",
             "                                                                     '            "
             "witness, '\n",
             '                                                                     '
             "'self.original[witness])\\n')))),\n",
             "     'tools/carla_lane_oracle/test_shared_helper_contracts.py': "
             "('c5f02d4424d7c497557991d1b08e4864dd0249158506beac08f601413a9648f2',\n",
             " '63645797e8134e48b9a9bcfe01b33fcba83ac9c140e696af23937c43296ca494',\n",
             ' ((25,\n',
             '   27,\n',
             "   ('        cls.texts = {path: (ROOT/path).read_text()\\n',),\n",
             "   ('        baseline = fixtures.common758_leaf_texts(ROOT)\\n',\n",
             "    '        cls.texts = {path: baseline[path]\\n')),\n",
             '  (126,\n',
             '   130,\n',
             '   ("        self.assertEqual(bindings[\'render/color_math.mojo\'],\\n",\n',
             "    '                         '\n",
             '    '
             '"cleanup.typed_boundary.CURRENT_DEPENDENCIES[\'render/color_math.mojo\'])\\n"),\n',
             '   ("        color = \'render/color_math.mojo\'\\n",\n',
             "    '        self.assertEqual(bindings[color], "
             "cleanup.sha((self.root/color).read_bytes()))\\n',\n",
             "    '        "
             "self.assertEqual(cleanup.sha(cleanup.pr760_stage.predecessor_source(\\n',\n",
             "    '            color, (self.root/color).read_text())), '\n",
             "    'cleanup.typed_boundary.CURRENT_DEPENDENCIES[color])\\n')),\n",
             '  (177,\n',
             '   179,\n',
             "   ('        for root, typed in ((self.root, True), (historical, False)):\\n',),\n",
             "   ('        common = fixtures.copy_common758_boundary_root(self, ROOT)\\n',\n",
             "    '        for root, typed in ((common, True), (historical, False)):\\n')),\n",
             '  (196,\n',
             '   214,\n',
             '   (),\n',
             "   ('\\n',\n",
             "    '    def "
             "test_pr760_old_xml_cannot_borrow_the_current_provider_image(self):\\n',\n",
             "    '        baseline = fixtures.common758_leaf_texts(self.root)\\n',\n",
             '    "        old = helpers.predecessor_source(XML, '
             'baseline[XML]).encode(\'utf-8\')\\n",\n',
             "    '        with self.changed(XML, old):\\n',\n",
             "    '            with self.assertRaises(ValueError):\\n',\n",
             "    '                cleanup.shared_helper_proof_bindings(self.root, "
             "paths=helpers.SOURCE_PATHS)\\n',\n",
             "    '            utf8 = self.root/UTF8\\n',\n",
             "    '            raw = utf8.read_bytes()\\n',\n",
             "    '            utf8.unlink()\\n',\n",
             "    '            try:\\n',\n",
             "    '                with self.assertRaises(cleanup.ContractError) as caught:\\n',\n",
             "    '                    cleanup.shared_helper_proof_bindings(self.root, '\n",
             "    'paths=helpers.SOURCE_PATHS)\\n',\n",
             "    '                self.assertIsInstance(caught.exception.__cause__, "
             "FileNotFoundError)\\n',\n",
             "    '                self.assertEqual(caught.exception.__cause__.filename, "
             "str(utf8))\\n',\n",
             "    '            finally:\\n',\n",
             "    '                utf8.write_bytes(raw)\\n',\n",
             "    '        cleanup.shared_helper_proof_bindings(self.root, "
             "paths=helpers.SOURCE_PATHS)\\n')),\n",
             '  (235,\n',
             '   236,\n',
             '   ("                with patch.object(Path, \'read_bytes\', unreadable), '
             'self.assertRaises(OSError) "\n',
             "    'as caught:\\n',),\n",
             '   ("                with patch.object(Path, \'read_bytes\', unreadable), "\n',
             "    'self.assertRaises((OSError, ValueError)) as caught:\\n',)),\n",
             '  (237,\n',
             '   241,\n',
             "   ('                self.assertIs(caught.exception, failure)\\n',),\n",
             "   ('                cause = caught.exception\\n',\n",
             "    '                while cause.__cause__ is not None:\\n',\n",
             "    '                    cause = cause.__cause__\\n',\n",
             "    '                self.assertIs(cause, failure)\\n')),\n",
             '  (315,\n',
             '   319,\n',
             '   ("        self.assertEqual(bindings[\'render/color_math.mojo\'], "\n',
             '    "helpers.PROVIDERS[\'render/color_math.mojo\'])\\n",),\n',
             '   ("        color = \'render/color_math.mojo\'\\n",\n',
             "    '        self.assertEqual(bindings[color], "
             "cleanup.sha((self.root/color).read_bytes()))\\n',\n",
             "    '        "
             "self.assertEqual(cleanup.sha(cleanup.pr760_stage.predecessor_source(\\n',\n",
             "    '            color, (self.root/color).read_text())), "
             "helpers.PROVIDERS[color])\\n')),\n",
             '  (326,\n',
             '   342,\n',
             '   ("        entry = '
             'self.root/\'extensions/animals/anatomy/helper_scope_entry.mojo\'\\n",\n',
             '    "        entry.write_text(\'def main():\\\\n    pass\\\\n\')\\n",\n',
             "    '        try:\\n',\n",
             '    "            with self.assertRaisesRegex(ValueError, \'entrypoint directories '
             'changed\'):\\n",\n',
             "    '                cleanup.shared_helper_proof_bindings(self.root, "
             "paths=helpers.SOURCE_PATHS)\\n',\n",
             "    '        finally: entry.unlink()\\n'),\n",
             "   ('        common = fixtures.copy_common758_boundary_root(self, ROOT)\\n',\n",
             "    '        for cohort, root, message in (\\n',\n",
             '    "                (\'pr760\', self.root, \'PR760 maintained entry directories '
             'changed\'),\\n",\n',
             '    "                (\'common758\', common, \'maintained entrypoint directories '
             'changed\')):\\n",\n',
             "    '            with self.subTest(cohort=cohort):\\n',\n",
             "    '                cleanup.shared_helper_proof_bindings(root, "
             "paths=helpers.SOURCE_PATHS)\\n',\n",
             '    "                entry = '
             'root/\'extensions/animals/anatomy/helper_scope_entry.mojo\'\\n",\n',
             "    '                self.assertFalse(entry.exists())\\n',\n",
             '    "                entry.write_text(\'def main():\\\\n    pass\\\\n\')\\n",\n',
             "    '                try:\\n',\n",
             "    '                    with self.assertRaises(cleanup.ContractError) as "
             "caught:\\n',\n",
             "    '                        cleanup.shared_helper_proof_bindings(root, '\n",
             "    'paths=helpers.SOURCE_PATHS)\\n',\n",
             "    '                    self.assertEqual(str(caught.exception),\\n',\n",
             '    "                                     \'full-audit cleanup successor: \' + '
             'message)\\n",\n',
             "    '                finally: entry.unlink()\\n',\n",
             "    '                cleanup.shared_helper_proof_bindings(root, "
             "paths=helpers.SOURCE_PATHS)\\n')))),\n",
             "     'tools/carla_lane_oracle/test_typed_boundary_contracts.py': "
             "('7181041aa06c10cade1c7c0512c6a130cb28d5baaad293ba24874c3e3e142dd5',\n",
             " '7114f17cce33b84fe226d3559b4d08d1227a6c1cda1f83825441d22e48b51705',\n",
             ' ((18,\n',
             '   20,\n',
             '   (),\n',
             "   ('import full_audit_cleanup_contracts as audit\\n',\n",
             "    'import _full_audit_test_fixtures as fixtures\\n')),\n",
             '  (27,\n',
             '   30,\n',
             "   ('        cls.current = {path: (ROOT/path).read_text() for path in "
             "typed.SOURCE_PATHS}\\n',),\n",
             "   ('        baseline = fixtures.common758_leaf_texts(ROOT)\\n',\n",
             "    '        cls.current = {path: baseline[path] for path in "
             "typed.SOURCE_PATHS}\\n',\n",
             "    '        typed.verify_sources(dict(cls.current))\\n')),\n",
             "  (190, 191, (), ('        baseline = fixtures.common758_leaf_texts(ROOT)\\n',)),\n",
             '  (196,\n',
             '   201,\n',
             "   ('                path.write_bytes((ROOT/name).read_bytes())\\n',),\n",
             '   ("                raw = (baseline[name].encode(\'utf-8\') if name in '
             'baseline\\n",\n',
             "    '                       else (ROOT/name).read_bytes())\\n',\n",
             '    "                if name in (\'tools/test_conditioned_coverage_loops.py\', "\n',
             '    "\'tools/carla_lane_oracle/test_typed_boundary_contracts.py\', "\n',
             '    "\'tools/carla_lane_oracle/test_shared_helper_contracts.py\', "\n',
             '    "\'tools/carla_lane_oracle/test_scaled_float32_contracts.py\', "\n',
             '    "\'tools/carla_lane_oracle/test_common758_current_successor.py\'):\\n",\n',
             "    '                    raw = audit.qualification_predecessor_bytes(name, "
             "raw)\\n',\n",
             "    '                path.write_bytes(raw)\\n')),\n",
             '  (443,\n',
             '   447,\n',
             "   ('                "
             "self.assertEqual(hashlib.sha256(target.read_bytes()).hexdigest(), '\n",
             "    'expected)\\n',),\n",
             "   ('                raw = target.read_bytes()\\n',\n",
             '    "                if path in (\'tools/test_conditioned_coverage_loops.py\', "\n',
             '    "\'tools/carla_lane_oracle/test_typed_boundary_contracts.py\', "\n',
             '    "\'tools/carla_lane_oracle/test_shared_helper_contracts.py\', "\n',
             '    "\'tools/carla_lane_oracle/test_scaled_float32_contracts.py\', "\n',
             '    "\'tools/carla_lane_oracle/test_common758_current_successor.py\', "\n',
             '    "\'tools/carla_lane_oracle/test_coverage_invariant_contracts.py\', "\n',
             '    "\'tools/carla_lane_oracle/test_expectation_binding_successor.py\'):\\n",\n',
             "    '                    raw = audit.qualification_predecessor_bytes(path, "
             "raw)\\n',\n",
             "    '                self.assertEqual(hashlib.sha256(raw).hexdigest(), "
             "expected)\\n')))),\n",
             "     'tools/test_conditioned_coverage_loops.py': "
             "('633c30c126a0ccf535bea13c66e528ee78b95dd47cf55f01eccad4f9f67d22c9',\n",
             '                                                  '
             "'1c7a6f9f0f32ec579b0609c0cac7fec04dedd342c7e22ec9a9956d6c6042c2dc',\n",
             '                                                  ((167,\n',
             '                                                    169,\n',
             "                                                    ('        original = "
             "audit._InvariantInputs.finish\\n',),\n",
             "                                                    ('        original = "
             "audit._CacheInputs.checkpoint\\n',\n",
             "                                                     '        finish = "
             "audit._InvariantInputs.finish\\n')),\n",
             '                                                   (171,\n',
             '                                                    181,\n',
             "                                                    ('        def finish(operation, "
             "root):\\n',),\n",
             "                                                    ('        def "
             "checkpoint(operation, owner, root):\\n',\n",
             "                                                     '            result = "
             "original(operation, owner, root)\\n',\n",
             "                                                     '            frame = "
             "audit.sys._getframe(1)\\n',\n",
             "                                                     '            if frame.f_code is "
             "not finish.__code__:\\n',\n",
             "                                                     '                return "
             "result\\n',\n",
             "                                                     '            "
             "self.assertIs(frame.f_globals, vars(audit))\\n',\n",
             '                                                     "            '
             'self.assertIs(frame.f_locals[\'self\'], "\n',
             "                                                     'operation)\\n',\n",
             "                                                     '            "
             "self.assertIs(owner, operation._owner)\\n',\n",
             "                                                     '            "
             "self.assertEqual(root, self.root)\\n',\n",
             "                                                     '            "
             "self.assertEqual(operation._state, '\n",
             '                                                     "\'active\')\\n")),\n',
             '                                                   (184,\n',
             '                                                    185,\n',
             "                                                    ('            "
             "self.assertNotIn(name, operation._raw)\\n',),\n",
             "                                                    ('            "
             "self.assertEqual(operation._raw[name], '\n",
             "                                                     'physical)\\n',)),\n",
             '                                                   (187,\n',
             '                                                    190,\n',
             '                                                    (),\n',
             "                                                    ('            # PR760 also "
             "observes checker copies as data. '\n",
             "                                                     'Mutate after the real\\n',\n",
             "                                                     '            # data checkpoint "
             "so the unchanged later '\n",
             "                                                     'checker-receipt "
             "comparison\\n',\n",
             "                                                     '            # retains its "
             "distinct finalization '\n",
             "                                                     'obligation.\\n')),\n",
             '                                                   (191,\n',
             '                                                    192,\n',
             "                                                    ('            return "
             "original(operation, root)\\n',),\n",
             "                                                    ('            return "
             "result\\n',)),\n",
             '                                                   (193,\n',
             '                                                    194,\n',
             "                                                    ('            with "
             "patch.object(audit._InvariantInputs, '\n",
             '                                                     "\'finish\', finish):\\n",),\n',
             "                                                    ('            with "
             "patch.object(audit._CacheInputs, '\n",
             '                                                     "\'checkpoint\', '
             'checkpoint):\\n",)))),\n',
             "        'tools/carla_lane_oracle/test_witness_format_contracts.py': "
             "('ad002f1255ae4f545a5cbfb3b8abf3f8e883a2637656248a232b297032b178de',\n",
             " '82f7e13e72b4f99ccad63d5dfe55fc0a73c898120b43ed8416b0731489ea6f84',\n",
             ' ((154,\n',
             '   170,\n',
             '   ("        with patch.object(cleanup.guard, \'production_mojo_paths\', "\n',
             '    "side_effect=AssertionError(\'extra census\')):\\n",),\n',
             "   ('        # Observe the real current checker without invalidating its code "
             "seal.\\n',\n",
             "    '        census = cleanup.guard.production_mojo_paths\\n',\n",
             "    '        calls = []\\n',\n",
             "    '        def reject_census(frame, event, value):\\n',\n",
             '    "            if event == \'call\' and frame.f_code is census.__code__:\\n",\n',
             "    '                calls.append(True)\\n',\n",
             '    "                raise AssertionError(\'extra census\')\\n",\n',
             "    '        previous = sys.getprofile()\\n',\n",
             "    '        try:\\n',\n",
             "    '            sys.setprofile(reject_census)\\n',\n",
             '    "            with self.assertRaisesRegex(AssertionError, \'extra '
             'census\'):\\n",\n',
             "    '                list(census(self.root))\\n',\n",
             "    '            self.assertEqual(calls, [True])\\n',\n",
             "    '            # Python disables a profile callback after it raises. Rearm it "
             "for\\n',\n",
             "    '            # the actual positive; any real census call must still fail.\\n',\n",
             "    '            sys.setprofile(reject_census)\\n')),\n",
             '  (171,\n',
             '   174,\n',
             '   (),\n',
             "   ('            self.assertEqual(calls, [True])\\n',\n",
             "    '        finally:\\n',\n",
             "    '            sys.setprofile(previous)\\n')),\n",
             '  (176,\n',
             '   189,\n',
             '   (),\n',
             '   ("        with patch.object(cleanup.guard, \'production_mojo_paths\', "\n',
             '    "side_effect=AssertionError(\'extra census\')):\\n",\n',
             '    "            with self.assertRaisesRegex(cleanup.ContractError, \'executing '
             'function "\n',
             '    "changed\'):\\n",\n',
             "    '                cleanup._witness_format_bindings(self.root)\\n',\n",
             "    '        # The original pre-typed leaf still accepts the original "
             "monkeypatch\\n',\n",
             "    '        # control, proving its no-census behavior independently of this "
             "edge.\\n',\n",
             "    '        historical = fixtures.copy_historical_boundary_root(self, ROOT)\\n',\n",
             '    "        with patch.object(cleanup.guard, \'production_mojo_paths\', "\n',
             '    "side_effect=AssertionError(\'extra census\')):\\n",\n',
             "    '            old_bindings = cleanup._witness_format_bindings(historical)\\n',\n",
             "    '        self.assertEqual(set(old_bindings), set(self.paths))\\n',\n",
             '    "        self.assertNotIn(\'math/scaled_products.mojo\', old_bindings)\\n",\n',
             "    '        for root, actual in ((self.root, bindings), (historical, "
             "old_bindings)):\\n',\n",
             "    '            self.assertEqual(actual, {name: "
             "cleanup.sha((root/name).read_bytes())\\n',\n",
             "    '                                      for name in self.paths})\\n')),\n",
             '  (191,\n',
             '   202,\n',
             '   (),\n',
             "   ('        current = self.root\\n',\n",
             "    '        try:\\n',\n",
             '    "            for cohort in (\'pr760\', \'common758\'):\\n",\n',
             '    "                self.root = (current if cohort == \'pr760\' else\\n",\n',
             "    '                             fixtures.copy_common758_boundary_root(self, "
             "ROOT))\\n',\n",
             "    '                with self.subTest(cohort=cohort):\\n',\n",
             "    '                    "
             "self._check_alias_paths_and_native_module_shadows_refuse(cohort)\\n',\n",
             "    '        finally:\\n',\n",
             "    '            self.root = current\\n',\n",
             "    '\\n',\n",
             "    '    def _check_alias_paths_and_native_module_shadows_refuse(self, "
             "cohort):\\n')),\n",
             '  (219,\n',
             '   224,\n',
             '   (),\n',
             "   ('        created = []\\n',\n",
             "    '        parent = shadow.parent\\n',\n",
             "    '        while not parent.exists():\\n',\n",
             "    '            created.append(parent)\\n',\n",
             "    '            parent = parent.parent\\n')),\n",
             '  (226,\n',
             '   236,\n',
             '   ("        with self.assertRaisesRegex(ValueError, \'resolver\'):\\n",\n',
             "    '            cleanup.verify(self.root)\\n'),\n",
             "   ('        try:\\n',\n",
             '    "            reason = (\'PR760 exact dependency closure changed\' if cohort == '
             '\'pr760\'\\n",\n',
             '    "                      else \'resolver\')\\n",\n',
             "    '            with self.assertRaisesRegex(ValueError, reason):\\n',\n",
             "    '                cleanup.verify(self.root)\\n',\n",
             "    '        finally:\\n',\n",
             "    '            shadow.unlink()\\n',\n",
             "    '            for parent in created:\\n',\n",
             "    '                parent.rmdir()\\n',\n",
             "    '        cleanup.verify(self.root, exact=True)\\n')),\n",
             '  (255,\n',
             '   266,\n',
             '   (),\n',
             "   ('        current = self.root\\n',\n",
             "    '        try:\\n',\n",
             '    "            for cohort in (\'pr760\', \'common758\'):\\n",\n',
             '    "                self.root = (current if cohort == \'pr760\' else\\n",\n',
             "    '                             fixtures.copy_common758_boundary_root(self, "
             "ROOT))\\n',\n",
             "    '                with self.subTest(cohort=cohort):\\n',\n",
             "    '                    "
             "self._check_full_gate_late_proof_input_mutation(cohort)\\n',\n",
             "    '        finally:\\n',\n",
             "    '            self.root = current\\n',\n",
             "    '\\n',\n",
             "    '    def _check_full_gate_late_proof_input_mutation(self, cohort):\\n')),\n",
             '  (275,\n',
             '   280,\n',
             '   ("            with patch.object(cleanup, \'inventory\', late), '
             'self.assertRaisesRegex(ValueError, "\n',
             '    "\'input changed during verification\'):\\n",),\n',
             "   ('            # PR760 consumes inventory within its image admission; the same "
             "late\\n',\n",
             "    '            # mutation meets its physical reread before the outer final "
             "sweep.\\n',\n",
             '    "            reason = (\'PR760 source changed after consumption: \' + "\n',
             "    'target.relative_to(self.root).as_posix()\\n',\n",
             '    "                      if cohort == \'pr760\' else \'input changed during '
             'verification\')\\n",\n',
             '    "            with patch.object(cleanup, \'inventory\', late), '
             'self.assertRaisesRegex(ValueError, "\n',
             "    'reason):\\n')))),\n",
             "     'tools/carla_lane_oracle/test_coverage_invariant_contracts.py': "
             "('8ec5dfed0b21c02a2104c4df8778fe1e11215cd67a9fa7d4808c30e4cc4e2841',\n",
             " 'f1f5fba22e90180c5c68af113c15941e96b2b2d1cfdc3a7a9b2a01936a4735f2',\n",
             ' ((82,\n',
             '   88,\n',
             "   ('            # Exact current direct/package commands completed in "
             "40.007/40.211\\n',\n",
             "    '            # seconds on pinned Python 3.12.14. Keep a measured "
             "60-second\\n',\n",
             "    '            # validation allowance; native cases retain their 5-second "
             "bound.\\n'),\n",
             "   ('            # On pinned Python 3.12.14, current 64ed89bf and pre-scope\\n',\n",
             "    '            # 3dcb9f06 direct verification took 155.268/154.829 seconds\\n',\n",
             "    '            # (155.172/154.799 CPU seconds), each with one complete gate "
             "and\\n',\n",
             "    '            # one terminal checkpoint. Both import modes exceeded 300 "
             "seconds\\n',\n",
             "    '            # in hosted parallel tooling CI. Allow 600 seconds for this "
             "current\\n',\n",
             "    '            # integration only; historical and native bounds stay "
             "unchanged.\\n')),\n",
             '  (90,\n',
             '   91,\n',
             "   ('                               check=True, capture_output=True, text=True, "
             "timeout=60)\\n',),\n",
             "   ('                               check=True, capture_output=True, text=True, "
             "timeout=600)\\n',)))),\n",
             "     'tools/carla_lane_oracle/test_expectation_binding_successor.py': "
             "('6f866d62d04370dad8eed28e7e6bd26c5b6ab804b00c407932624ba183cd9a08',\n",
             " '112d9a22a78f4379fbdb932d57aea179a246251df63fb2778486903607e55050',\n",
             " ((13, 14, (), ('import _full_audit_test_fixtures as fixtures\\n',)),\n",
             '  (116,\n',
             '   123,\n',
             "   ('        target = ROOT/PATH\\n', '        raw = target.read_bytes()\\n'),\n",
             "   ('        historical = fixtures.copy_common758_boundary_root(self, ROOT)\\n',\n",
             "    '        candidate = audit._pr760_candidate_bindings\\n',\n",
             "    '        # The current candidate owns these reads in its exact nested "
             "observer;\\n',\n",
             "    '        # the common758 cohort retains the original direct binding "
             "observer.\\n',\n",
             "    '        observers = [code for code in candidate.__code__.co_consts\\n',\n",
             "    '                     if isinstance(code, type(candidate.__code__)) and "
             "code.co_name == '\n",
             '    "\'observe\']\\n",\n',
             "    '        self.assertEqual(len(observers), 1)\\n')),\n",
             '  (124,\n',
             '   172,\n',
             "   ('        for at_read in (1, 2):\\n',\n",
             "    '            reads = []\\n',\n",
             "    '            def changed(path, *args, **kwargs):\\n',\n",
             "    '                if (path == target and sys._getframe(1).f_code is\\n',\n",
             "    '                        audit._typed_boundary_bindings.__code__):\\n',\n",
             "    '                    reads.append(path)\\n',\n",
             '    "                    return raw+b\'\\\\n\' if len(reads) == at_read else '
             'raw\\n",\n',
             "    '                return original(path, *args, **kwargs)\\n',\n",
             '    "            with self.subTest(at_read=at_read), patch.object(Path, '
             '\'read_bytes\', changed):\\n",\n',
             "    '                with self.assertRaises(ValueError):\\n',\n",
             "    '                    audit._typed_boundary_bindings(ROOT)\\n',\n",
             "    '            self.assertEqual(len(reads), at_read)\\n',\n",
             "    '            self.assertEqual(target.read_bytes(), raw)\\n'),\n",
             "   ('        for cohort, root, observed_code in (\\n',\n",
             '    "                (\'common758\', historical, '
             'audit._typed_boundary_bindings.__code__),\\n",\n',
             '    "                (\'pr760\', ROOT, observers[0])):\\n",\n',
             "    '            target = root/PATH\\n',\n",
             "    '            raw = target.read_bytes()\\n',\n",
             "    '            def is_input_read(path, frame):\\n',\n",
             "    '                if path != target or frame.f_code is not observed_code:\\n',\n",
             "    '                    return False\\n',\n",
             "    '                self.assertIs(frame.f_globals, vars(audit))\\n',\n",
             '    "                self.assertEqual(frame.f_locals[\'path\'], PATH)\\n",\n',
             '    "                if cohort == \'pr760\':\\n",\n',
             "    '                    self.assertIs(frame.f_back.f_code, "
             "candidate.__code__)\\n',\n",
             '    "                    self.assertEqual(frame.f_back.f_locals[\'root\'], '
             'root)\\n",\n',
             "    '                else:\\n',\n",
             '    "                    self.assertEqual(frame.f_locals[\'root\'], root)\\n",\n',
             "    '                return True\\n',\n",
             "    '\\n',\n",
             "    '            baseline_reads = []\\n',\n",
             "    '            def observe(path, *args, **kwargs):\\n',\n",
             "    '                value = original(path, *args, **kwargs)\\n',\n",
             "    '                if is_input_read(path, sys._getframe(1)):\\n',\n",
             "    '                    self.assertEqual(value, raw)\\n',\n",
             "    '                    baseline_reads.append(path)\\n',\n",
             "    '                return value\\n',\n",
             '    "            with self.subTest(cohort=cohort, baseline=True), patch.object(Path, '
             '\'read_bytes\', "\n',
             "    'observe):\\n',\n",
             "    '                result = audit._typed_boundary_bindings(root)\\n',\n",
             "    '                self.assertEqual(result[PATH], "
             "hashlib.sha256(raw).hexdigest())\\n',\n",
             "    '            self.assertEqual(len(baseline_reads), 2)\\n',\n",
             "    '            for at_read in (1, 2):\\n',\n",
             "    '                reads = []\\n',\n",
             "    '                def changed(path, *args, **kwargs):\\n',\n",
             "    '                    value = original(path, *args, **kwargs)\\n',\n",
             "    '                    if is_input_read(path, sys._getframe(1)):\\n',\n",
             "    '                        self.assertEqual(value, raw)\\n',\n",
             "    '                        reads.append(path)\\n',\n",
             '    "                        return raw+b\'\\\\n\' if len(reads) == at_read else '
             'value\\n",\n',
             "    '                    return value\\n',\n",
             "    '                with self.subTest(cohort=cohort, at_read=at_read), "
             "patch.object(Path, '\n",
             '    "\'read_bytes\', changed):\\n",\n',
             "    '                    with self.assertRaises(ValueError) as caught:\\n',\n",
             "    '                        audit._typed_boundary_bindings(root)\\n',\n",
             '    "                    reason = ({1: \'PR760 physical input changed: \',\\n",\n',
             '    "                               2: \'PR760 source changed after consumption: '
             '\'}\\n",\n',
             '    "                              if cohort == \'pr760\' else\\n",\n',
             '    "                              {1: \'typed boundary bound input changed: '
             '\',\\n",\n',
             '    "                               2: \'typed input changed during admission: '
             '\'})[at_read]\\n",\n',
             "    '                    self.assertIn(reason+PATH, str(caught.exception))\\n',\n",
             "    '                self.assertEqual(len(reads), at_read)\\n',\n",
             "    '                self.assertEqual(target.read_bytes(), raw)\\n'))))}\n",
             "    require(path in rows, 'unregistered qualification witness: ' + path)\n",
             '    before_sha, after_sha, edits = rows[path]\n',
             "    expected = (typed_boundary.EDGES[path]['after_sha256'] if path ==\n",
             "        'tools/carla_lane_oracle/test_witness_format_contracts.py' else\n",
             '        scaled_float32.TESTS[path] if path ==\n',
             "        'tools/carla_lane_oracle/test_scaled_float32_contracts.py'\n",
             '        else typed_boundary.BINDING_INPUTS[path])\n',
             "    require(before_sha == expected, 'qualification historical authority changed: ' + "
             'path)\n',
             '    if sha(raw) == before_sha:\n',
             '        result = raw\n',
             '    else:\n',
             "        require(sha(raw) == after_sha, 'unreviewed qualification endpoint: ' + "
             'path)\n',
             "        lines = raw.decode('utf-8').splitlines(keepends=True)\n",
             '        previous = len(lines) + 1\n',
             '        for start, stop, before, after in reversed(edits):\n',
             '            require(0 <= start <= stop < previous and tuple(lines[start:stop]) == '
             'after,\n',
             "                    'qualification inverse span changed: ' + path)\n",
             '            lines[start:stop] = before\n',
             '            previous = start\n',
             "        result = ''.join(lines).encode('utf-8')\n",
             "        require(sha(result) == before_sha, 'qualification inverse misses "
             "predecessor: ' + path)\n",
             '    executing_checker_bindings()\n',
             '    return result\n',
             '\n',
             '\n',
             'def stage_witness_predecessor_bytes(raw):\n',
             '    """Recover one fixed stage witness for pure historical registry comparison.\n',
             '\n',
             '    The physical owner still observes, pins, rereads and returns current bytes.\n',
             '    This exact inverse supplies no admission, filesystem or receipt authority.\n',
             '    """\n',
             '    executing_checker_bindings()\n',
             '    before_sha, after_sha, edits = '
             "('b6d5ecc453ebe4c1f8d5f07e1f029b09f414dea887480fa6cf07ccd85bfacdb3',\n",
             " '35efae78b6a95568760b4544428c511a5ee90beec4d86338fd2f717c0f1c7516',\n",
             ' ((74,\n',
             '   75,\n',
             '   (),\n',
             '   ("            \'typed_boundary_contracts.py\': '
             '\'pr760-typed_boundary-predecessor.txt\',\\n",)),\n',
             '  (155,\n',
             '   158,\n',
             '   (),\n',
             "   ('        import full_audit_cleanup_contracts as owner\\n',\n",
             '    "        witness = '
             '\'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py\'\\n",\n',
             "    '        inputs[witness] = "
             "owner.stage_witness_predecessor_bytes(inputs[witness])\\n'))))\n",
             "    path = 'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py'\n",
             '    require(before_sha == pr760_stage.REGISTRY_INPUT_SHA256[path],\n',
             "            'stage witness historical authority changed')\n",
             '    require(type(raw) is bytes and sha(raw) in (before_sha, after_sha),\n',
             "            'unreviewed stage witness endpoint')\n",
             '    if sha(raw) == before_sha:\n',
             '        return raw\n',
             "    lines = raw.decode('utf-8').splitlines(keepends=True)\n",
             '    previous = len(lines) + 1\n',
             '    for start, stop, before, after in reversed(edits):\n',
             '        require(0 <= start <= stop < previous and tuple(lines[start:stop]) == '
             'after,\n',
             "                'stage witness inverse span changed')\n",
             '        lines[start:stop] = before\n',
             '        previous = start\n',
             "    result = ''.join(lines).encode('utf-8')\n",
             "    require(sha(result) == before_sha, 'stage witness inverse misses predecessor')\n",
             '    executing_checker_bindings()\n',
             '    return result\n',
             '\n',
             '\n',
             'def _pr760_candidate_bindings(root, *, _snapshots=None, _operation=None):\n',
             '    """Complete physical image comparison; the enclosing owner grants admission.\n',
             '\n',
             '    The fixed PR760 inverse runs once on immutable observed bytes. Historical\n',
             "    texts exist only in memory for the preserved authorities' pure comparisons.\n",
             '    All observations, terminal checks and returned digests remain physical.\n',
             '    Its return value alone is never an owner, publication token or receipt.\n',
             '    """\n',
             '    root = Path(root)\n',
             '    try:\n',
             '        _operation_check(_operation, root)\n',
             '        require(_snapshots is None or type(_snapshots) is dict,\n',
             "                'invalid PR760 snapshot owner')\n",
             '        executing = executing_checker_bindings(root)\n',
             '        image = {} if _snapshots is None else _snapshots\n',
             '\n',
             '        def observe(path):\n',
             '            raw = _observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
             '                                 _operation=_operation)\n',
             "            require(type(raw) is bytes, 'PR760 source is not physical bytes: ' + "
             'path)\n',
             '            require(image.setdefault(path, raw) == raw,\n',
             "                    'PR760 source changed after consumption: ' + path)\n",
             '            return raw\n',
             '\n',
             '        for path, digest in executing.items():\n',
             "            require(sha(observe(path)) == digest, 'PR760 executing source differs "
             "from owner: ' + path)\n",
             '        data_raw = observe(PR760_IMAGE)\n',
             '        require(sha(data_raw) == PR760_IMAGE_SHA256,\n',
             "                'PR760 physical-image authority changed')\n",
             '        data = json.loads(data_raw)\n',
             "        require(type(data) is dict and data.get('status') == 'closed-candidate'\n",
             "                and data.get('public_admission') is False\n",
             "                and data.get('stage_sha256') == PR760_STAGE_SHA256,\n",
             "                'PR760 image is not the fixed closed candidate')\n",
             '        before_owner = observe(PR760_OWNER_PREDECESSOR)\n',
             '        require(sha(before_owner) == PR760_OWNER_PREDECESSOR_SHA256\n',
             '                == pr760_stage.PROTECTED_AUTHORITY_SHA256[CHECKER_PATHS[0]],\n',
             "                'PR760 predecessor owner evidence changed')\n",
             '        for path, digest in {**PR760_IMPLEMENTATION_PREDECESSORS, '
             '**PR760_IMPLEMENTATION_SUCCESSORS}.items():\n',
             "            require(sha(observe(path)) == digest, 'PR760 implementation source "
             "changed: ' + path)\n",
             '        observe(MIGRATION)\n',
             '        record = read_record(root)\n',
             '        entries, source_image = _helper_entry_census(root, _operation=_operation)\n',
             "        require(list(entries) == record['entry_directories'],\n",
             "                'PR760 maintained entry directories changed')\n",
             '        for path, raw in source_image.items():\n',
             '            require(image.setdefault(path, raw) == raw,\n',
             "                    'PR760 source changed before entry census: ' + path)\n",
             "        expected = data['inputs']\n",
             '        require(type(expected) is dict and all(type(path) is str and type(digest) is '
             'str\n',
             "                for path, digest in expected.items()), 'malformed PR760 source-image "
             "pins')\n",
             '        for path, digest in expected.items():\n',
             "            require(sha(observe(path)) == digest, 'PR760 physical input changed: ' + "
             'path)\n',
             "        stage_witness = 'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py'\n",
             '        stage_prior = stage_witness_predecessor_bytes(image[stage_witness])\n',
             '        require(stage_prior == '
             "image['tools/carla_lane_oracle/pr760-test_pr760_arithmetic_stage-predecessor.txt'],\n",
             "                'stage witness archive differs from exact predecessor')\n",
             '        require(all((sha(stage_prior) if path == stage_witness else '
             'expected.get(path)) == digest\n',
             '                    for path, digest in '
             'pr760_stage.REGISTRY_INPUT_SHA256.items()),\n',
             "                'PR760 physical image misses reviewed registry input')\n",
             "        for path, archive in (('tools/test_conditioned_coverage_loops.py', "
             "'tools/carla_lane_oracle/pr760-test_conditioned_coverage_loops-predecessor.txt'), "
             "('tools/carla_lane_oracle/test_typed_boundary_contracts.py', "
             "'tools/carla_lane_oracle/pr760-test_typed_boundary_contracts-predecessor.txt'), "
             "('tools/carla_lane_oracle/test_shared_helper_contracts.py', "
             "'tools/carla_lane_oracle/pr760-test_shared_helper_contracts-predecessor.txt'), "
             "('tools/carla_lane_oracle/test_scaled_float32_contracts.py', "
             "'tools/carla_lane_oracle/pr760-test_scaled_float32_contracts-predecessor.txt'), "
             "('tools/carla_lane_oracle/test_common758_current_successor.py', "
             "'tools/carla_lane_oracle/pr760-test_common758_current_successor-predecessor.txt'), "
             "('tools/carla_lane_oracle/test_witness_format_contracts.py', "
             "'tools/carla_lane_oracle/pr760-test_witness_format_contracts-predecessor.txt'), "
             "('tools/carla_lane_oracle/test_coverage_invariant_contracts.py', "
             "'tools/carla_lane_oracle/pr760-test_coverage_invariant_contracts-predecessor.txt'), "
             "('tools/carla_lane_oracle/test_expectation_binding_successor.py', "
             "'tools/carla_lane_oracle/pr760-test_expectation_binding_successor-predecessor.txt')):\n",
             '            require(qualification_predecessor_bytes(path, image[path]) == '
             'image[archive],\n',
             "                    'PR760 qualification archive differs from exact predecessor: ' + "
             'path)\n',
             '        # One complete fixed image, with no per-file old/new fallback.\n',
             '        previous = pr760_stage.verify_registry_sources(\n',
             '            {path: stage_prior if path == stage_witness else image[path]\n',
             '             for path in pr760_stage.REGISTRY_INPUT_SHA256})\n',
             '        typed_texts = {path: (previous[path] if path in pr760_stage.EXAMPLE_PATHS\n',
             '                              else qualification_predecessor_bytes(path, '
             "image[path]).decode('utf-8')\n",
             '                              if path == '
             "'tools/carla_lane_oracle/test_witness_format_contracts.py' else "
             "image[path].decode('utf-8'))\n",
             '                       for path in typed_boundary.SOURCE_PATHS}\n',
             '        typed_previous = typed_boundary.verify_sources(typed_texts)\n',
             '        for path in pr760_stage.CARLA_REGISTRY_PATHS:\n',
             '            if path in pr760_stage.EXAMPLE_PATHS:\n',
             '                require(sha(previous[path]) == '
             "typed_boundary.EDGES[path]['after_sha256'],\n",
             "                        'PR760 example misses existing typed endpoint: ' + path)\n",
             '            elif path in typed_boundary.CURRENT_DEPENDENCIES:\n',
             '                require(sha(previous[path]) == '
             'typed_boundary.CURRENT_DEPENDENCIES[path],\n',
             "                        'PR760 dependency misses existing typed endpoint: ' + "
             'path)\n',
             '            else:\n',
             '                require(sha(previous[path]) == '
             "data['supplemental_predecessors'][path],\n",
             "                        'PR760 supplemental example predecessor changed: ' + path)\n",
             '        # #738 sees its original exact source/provider bytes solely as pure\n',
             '        # comparison inputs. Nothing is published as a synthetic filesystem.\n',
             '        helper_paths = set(shared_helpers.SOURCE_PATHS) | '
             'set(shared_helpers.PROVIDERS)\n',
             "        helper_texts = {path: previous.get(path, image[path].decode('utf-8'))\n",
             '                        for path in helper_paths}\n',
             '        active = shared_helpers.verify_correspondence(helper_texts)\n',
             '        require(set(active) == set(shared_helpers.SOURCE_PATHS),\n',
             "                'PR760 shared-helper composition changed')\n",
             '        shared_edges = shared_helpers.edges(active)\n',
             '        for path in active:\n',
             '            if path in previous:\n',
             "                require(sha(previous[path]) == shared_edges[path]['after_sha256'],\n",
             "                        'PR760 shared-helper predecessor join changed: ' + path)\n",
             '                shared_edges[path] = {**shared_edges[path],\n',
             "                    'after_sha256': sha(image[path]),\n",
             "                    'after_token_sha256': "
             "source.token_sha256(image[path].decode('utf-8'))}\n",
             '        known = set(source_image)\n',
             '        found = {}\n',
             "        found['PRODUCTION_CLOSURE'] = dependency_inventory(root,\n",
             "            roots=(*SOURCE_PATHS, *record['inventory']), entries=entries,\n",
             '            _known=known, _snapshots=image)\n',
             "        found['NATIVE_CLOSURE'] = _native_dependency_inventory(root,\n",
             '            witnesses=NATIVE_WITNESSES, _known=known, _snapshots=image)\n',
             '        test_paths = tuple(path for path in typed_boundary.TESTS if '
             "path.endswith('.mojo'))\n",
             "        found['TYPED_NATIVE_CLOSURE'] = set()\n",
             '        for parent in sorted({str(Path(path).parent) for path in test_paths}):\n',
             "            found['TYPED_NATIVE_CLOSURE'].update(dependency_inventory(root,\n",
             '                roots=tuple(path for path in test_paths if str(Path(path).parent) == '
             'parent),\n',
             '                entries=(parent,), _known=known, _snapshots=image))\n',
             "        found['TYPED_PRODUCTION_CLOSURE'] = dependency_inventory(root,\n",
             '            roots=tuple(path for path in (*typed_boundary.SOURCE_PATHS, '
             '*typed_boundary.NEW_INPUTS)\n',
             "                if path.endswith('.mojo') and not path.startswith(('tests/', "
             "'tools/', 'examples/', 'bench/'))),\n",
             '            entries=entries, _known=known, _snapshots=image)\n',
             "        found['EXAMPLE_CLOSURE'] = dependency_inventory(root,\n",
             '            roots=pr760_stage.EXAMPLE_PATHS, entries=pr760_stage.EXAMPLE_ENTRIES,\n',
             '            _known=known, _snapshots=image)\n',
             "        require(set(data['closures']) == set(found)\n",
             "                and all(set(data['closures'][name]) == paths for name, paths in "
             'found.items()),\n',
             "                'PR760 exact dependency closure changed')\n",
             "        pr760_stage.verify_example_closure(found['EXAMPLE_CLOSURE'], "
             'pr760_stage.EXAMPLE_ENTRIES)\n',
             '        resolver_paths = set().union(*found.values())\n',
             '        # Registry-wide diagnostic pins also contain the separately owned hair\n',
             '        # scope and qualification-only tests. They are observed bytes, not new\n',
             '        # CARLA import roots or a grant of their own caller/theorem contracts.\n',
             '        carla_providers = set(pr760_stage.REGISTRY_PROVIDER_SHA256) - {\n',
             "            'extensions/humanoid/skeleton/head/hair/styles.mojo'}\n",
             '        require(set(pr760_stage.CARLA_REGISTRY_PATHS) <= resolver_paths\n',
             '                and carla_providers <= resolver_paths\n',
             "                and resolver_paths <= set(expected), 'PR760 transitive provider is "
             "unbound')\n",
             '        lookup = _render_lookup_args(resolver_paths, entries)\n',
             "        lookup['math_entries'] = frozenset(('.', *entries,\n",
             '            *(str(Path(path).parent) for path in expected\n',
             "              if path.endswith('.mojo') and path.startswith(('tests/', 'examples/', "
             "'bench/')))))\n",
             "        lookup['example_entries'] = lookup['math_entries']\n",
             '        require(resolver_unshadowed(root, resolver_paths, **lookup),\n',
             "                'PR760 alternate, compiled, package, symlink or std resolver "
             "surface')\n",
             '        production = set()\n',
             '        observed = inventory(root, _snapshots=image, _production=production)\n',
             '        require(observed == typed_boundary.INVENTORY,\n',
             "                'PR760 production caller/use inventory changed')\n",
             '        # Fresh physical reads close both all source-classifying reads and every\n',
             '        # non-Mojo input. No authorization/result cache survives this call.\n',
             '        _helper_entry_census_finish(root, source_image, _operation=_operation)\n',
             '        for path, raw in tuple(image.items()):\n',
             "            require(observe(path) == raw, 'PR760 input changed during verification: "
             "' + path)\n",
             '        require(resolver_unshadowed(root, resolver_paths, **lookup),\n',
             "                'PR760 resolver surface changed during verification')\n",
             '        require(executing_checker_bindings(root) == executing,\n',
             "                'PR760 executing checker changed during verification')\n",
             "        return {'image': 'pr760-closed-candidate', 'public_admission': False,\n",
             "                'bindings': {path: sha(image[path]) for path in sorted(image)},\n",
             "                'predecessors': previous, 'typed_predecessors': typed_previous,\n",
             "                'shared_edges': shared_edges,\n",
             "                'closures': {name: frozenset(paths) for name, paths in "
             'found.items()},\n',
             "                'known': frozenset(known), 'entries': tuple(entries),\n",
             "                'production': frozenset(production),\n",
             "                'inventory': types.MappingProxyType({path: "
             'types.MappingProxyType(row)\n',
             '                    for path, row in observed.items()})}\n',
             '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, '
             'AttributeError) as error:\n',
             '        if isinstance(error, ContractError):\n',
             '            _operation_fail(_operation, error)\n',
             '        try:\n',
             '            _operation_fail(_operation, ContractError(\n',
             "                'full-audit cleanup successor: malformed or unreadable PR760 "
             "candidate: ' + str(error)))\n",
             '        except ContractError as failure:\n',
             '            raise failure from error\n',
             '\n',
             '\n')))},
 'seed_count_contracts.py': {'after_sha256': 'daa8f391a18e54a3fae958150673c134897db52ce5de87291f613f84df7c6d90',
                             'before_sha256': 'ff4a330326fd69bc649e6f235d1f05db4ed40e6b76b1d75e66a4474741c16345',
                             'edits': ((777,
                                        778,
                                        ("                expected = edge['after_sha256']\n",),
                                        ('                expected = '
                                         'full_audit.provenance_after_sha256(edge)\n',)),)},
 'source_contracts.py': {'after_sha256': 'ebb6e75b90528b5456485433d470de36e6b33e4df98139dd0acadda75a57adf5',
                         'before_sha256': '83fdd35b61f0dc7739160c113ae6b4558ad07d45ffded22b7062bc9a209032d0',
                         'edits': ((346,
                                    352,
                                    ('        return text\n',),
                                    ('        if __package__:\n',
                                     '            from . import pr760_arithmetic_stage as pr760\n',
                                     '        else:\n',
                                     '            import pr760_arithmetic_stage as pr760\n',
                                     '        if relative not in pr760.CARLA_REGISTRY_PATHS:\n',
                                     '            return text\n')),
                                   (370,
                                    376,
                                    ('        return raw\n',),
                                    ('        if __package__:\n',
                                     '            from . import pr760_arithmetic_stage as pr760\n',
                                     '        else:\n',
                                     '            import pr760_arithmetic_stage as pr760\n',
                                     '        if relative not in pr760.CARLA_REGISTRY_PATHS:\n',
                                     '            return raw\n')))}}


def _pr760_checker_source_predecessor(name, raw):
    """Return reviewed implementation predecessor and its physical line map."""
    row = _PR760_CHECKER_SOURCE_EDGES.get(name)
    if row is None or hashlib.sha256(raw).hexdigest() == row['before_sha256']:
        return raw, {line: (line, line) for line in range(1, len(raw.splitlines()) + 1)}
    if hashlib.sha256(raw).hexdigest() != row['after_sha256']:
        raise AssertionError(('unreviewed PR760 checker bytes', name))
    lines = raw.decode('utf-8').splitlines(keepends=True)
    result, mapping, cursor = [], {}, 0
    for start, stop, before, after in row['edits']:
        if not cursor <= start <= stop <= len(lines) or tuple(lines[start:stop]) != after:
            raise AssertionError(('unreviewed PR760 checker span', name, start, stop))
        for current in range(cursor, start):
            mapping[len(result) + 1] = (current + 1, current + 1)
            result.append(lines[current])
        for line in before:
            mapping[len(result) + 1] = (start + 1, stop)
            result.append(line)
        cursor = stop
    for current in range(cursor, len(lines)):
        mapping[len(result) + 1] = (current + 1, current + 1)
        result.append(lines[current])
    previous = ''.join(result).encode('utf-8')
    if hashlib.sha256(previous).hexdigest() != row['before_sha256']:
        raise AssertionError(('PR760 checker predecessor changed', name))
    return previous, mapping


def _checker_source_predecessor(name, raw):
    """Invert enumerated complete checker edits; retain every untouched byte.

    This test-only inverse never supplies a production root or observation.
    Its predecessor digest is the original whole-file pin, including unrelated
    functions. Mapping ranges address current physical calls from old site IDs.
    """
    if type(raw) is not bytes:
        raise AssertionError('checker source must be physical builtin bytes')
    raw, current_mapping = _pr760_checker_source_predecessor(name, raw)
    lines = raw.decode('utf-8').splitlines(keepends=True)
    result, mapping, cursor = [], {}, 0
    for start, stop, before, after in _TYPED_CHECKER_SOURCE_EDITS[name]:
        if not cursor <= start <= stop <= len(lines) or tuple(lines[start:stop]) != after:
            raise AssertionError(('unreviewed checker successor span', name, start, stop))
        for current in range(cursor, start):
            mapping[len(result) + 1] = (current + 1, current + 1)
            result.append(lines[current])
        for line in before:
            mapping[len(result) + 1] = (start + 1, stop)
            result.append(line)
        cursor = stop
    for current in range(cursor, len(lines)):
        mapping[len(result) + 1] = (current + 1, current + 1)
        result.append(lines[current])
    predecessor = ''.join(result).encode('utf-8')
    if hashlib.sha256(predecessor).hexdigest() != BoundedOwnerDistinctMechanismControls._SOURCE_SHA256[name]:
        raise AssertionError(('whole predecessor checker bytes changed', name))
    composed = {}
    for line, (first, last) in mapping.items():
        if first > last:
            # An old observer removed by an earlier reviewed edge has no active
            # call site; existing exact AST/call controls must still refuse it.
            composed[line] = (first, last)
            continue
        ranges = [current_mapping[index] for index in range(first, last + 1)]
        composed[line] = (min(start for start, stop in ranges), max(stop for start, stop in ranges))
    return predecessor, composed


_CURRENT_LOCAL_S_PREDICATE = (
    'source.token_sha256(text) == source.token_sha256('
    '_inputs.text_default(_input_owner, root, rel.as_posix())) '
    'and source.token_sha256(_typed_source.historical_text(root, rel.as_posix(), text, '
    '_operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) '
    '== seed_count.score_family_token_sha256(hashlib.sha256(provenance).hexdigest())')
_CURRENT_LOCAL_S_REQUIRE = "require(" + _CURRENT_LOCAL_S_PREDICATE + ", 'unreviewed supplied score-helper source')"


# BEGIN REVIEWED #333 CHECKER SOURCE INVERSE
_TYPED_CHECKER_SOURCE_EDITS = {
    'accepted_successor_contracts.py': (
        (3, 8,
         (),
         (
          'if __package__:\n',
          '    from . import source_contracts as _typed_source\n',
          'else:\n',
          '    import source_contracts as _typed_source\n',
          '\n',
         ),
        ),
        (9, 10,
         (),
         (
          '# #333 explicit historical provenance views; current inputs remain operation-owned.\n',
         ),
        ),
        (55, 56,
         (),
         (
          '\n',
         ),
        ),
        (62, 63,
         (
          '    payload = (root/MIGRATION).read_bytes()\n',
         ),
         (
          '    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())\n',
         ),
        ),
        (68, 69,
         (
          "    require(hashlib.sha256((root/'tools/carla_lane_oracle/coverage-followup-migration.json').read_bytes()).hexdigest()\n",
         ),
         (
          "    require(hashlib.sha256(_typed_source.historical_bytes(root, root/'tools/carla_lane_oracle/coverage-followup-migration.json', (root/'tools/carla_lane_oracle/coverage-followup-migration.json').read_bytes())).hexdigest()\n",
         ),
        ),
        (72, 73,
         (
          "        require(hashlib.sha256((root/'tools/carla_lane_oracle'/name).read_bytes()).hexdigest()\n",
         ),
         (
          "        require(hashlib.sha256(_typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/name, (root/'tools/carla_lane_oracle'/name).read_bytes())).hexdigest()\n",
         ),
        ),
        (87, 88,
         (
          "        require(source.token_sha256(_observe_text(root, path, (root/path).read_text(), _operation=_operation)) == item['after_token_sha256'],\n",
         ),
         (
          "        require(source.token_sha256(_typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)) == item['after_token_sha256'],\n",
         ),
        ),
        (132, 133,
         (
          "        payload = full_audit._observe_bytes(root, 'tools/carla_lane_oracle/'+filename, payload, _operation=_operation)\n",
         ),
         (
          "        payload = _typed_source.historical_bytes(root, 'tools/carla_lane_oracle/'+filename, full_audit._observe_bytes(root, 'tools/carla_lane_oracle/'+filename, payload, _operation=_operation), _operation=_operation)\n",
         ),
        ),
        (167, 176,
         (
          "    for path, item in record['sources'].items():\n",
          "        require(source.token_sha256(_observe_text(root, path, (root/path).read_text(), _operation=_operation)) == item['after_token_sha256'],\n",
          "                'unreviewed complete successor: ' + path)\n",
          "        require(hashlib.sha256(item['before_complete_module'].encode()).hexdigest()\n",
          "                == item['before_sha256'], 'historical module changed: ' + path)\n",
         ),
         (
          '    try:\n',
          "        for path, item in record['sources'].items():\n",
          "            require(source.token_sha256(_typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)) == item['after_token_sha256'],\n",
          "                    'unreviewed complete successor: ' + path)\n",
          "            require(hashlib.sha256(item['before_complete_module'].encode()).hexdigest()\n",
          "                    == item['before_sha256'], 'historical module changed: ' + path)\n",
          '    except ValueError as error:\n',
          '        raise ValueError(\n',
          "            'unreviewed complete successor: ' + str(error)) from error\n",
         ),
        ),
        (228, 229,
         (
          '        full_audit._observe_bytes(root, relative, payload, _operation=_operation)\n',
         ),
         (
          '        _typed_source.historical_bytes(root, relative, full_audit._observe_bytes(root, relative, payload, _operation=_operation), _operation=_operation)\n',
         ),
        ),
        (256, 257,
         (
          "        runtime_raw = (root/'tools/carla_lane_oracle'/runtime_name).read_bytes()\n",
         ),
         (
          "        runtime_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/runtime_name, (root/'tools/carla_lane_oracle'/runtime_name).read_bytes())\n",
         ),
        ),
        (263, 264,
         (
          "        guard_raw = (root/'tools/carla_lane_oracle'/guard_name).read_bytes()\n",
         ),
         (
          "        guard_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/guard_name, (root/'tools/carla_lane_oracle'/guard_name).read_bytes())\n",
         ),
        ),
        (302, 303,
         (
          "        runtime_raw = (root/'tools/carla_lane_oracle'/runtime_name).read_bytes()\n",
         ),
         (
          "        runtime_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/runtime_name, (root/'tools/carla_lane_oracle'/runtime_name).read_bytes(), _operation=_operation)\n",
         ),
        ),
        (309, 310,
         (
          "        guard_raw = (root/'tools/carla_lane_oracle'/guard_name).read_bytes()\n",
         ),
         (
          "        guard_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/guard_name, (root/'tools/carla_lane_oracle'/guard_name).read_bytes(), _operation=_operation)\n",
         ),
        ),
    ),
    'cache_key_contracts.py': ((10,
  15,
  (),
  ('if __package__:\n',
   '    from . import source_contracts as _typed_source\n',
   'else:\n',
   '    import source_contracts as _typed_source\n',
   '\n')),
 (66,
  67,
  ('def inventory(root, *, verified_lane_source=None, _inputs=None, _input_owner=None, '
   '_operation=None):\n',),
  ('def inventory(root, *, verified_lane_source=None, _inputs=None, _input_owner=None, '
   '_operation=None, _admission=None):\n',)),
 (68,
  77,
  (),
  ('    if _admission is not None:\n',
   '        if __package__:\n',
   '            from . import full_audit_cleanup_contracts as full_audit\n',
   '        else:\n',
   '            import full_audit_cleanup_contracts as full_audit\n',
   '        require(type(_admission) is full_audit._PublicAdmission\n',
   '                and full_audit._cache_inventory_admission_frame(sys._getframe(), '
   '_admission),\n',
   "                'invalid public inventory admission')\n",
   '        _admission._check(_admission._owner, root)\n')),
 (124,
  127,
  ('            require(hashlib.sha256(physical).hexdigest() in {seed_count.SCORE_AFTER_SHA256, '
   'seed_count.station.AFTER_SHA256, seed_count.deviation.AFTER_SHA256},\n',),
  ('            provenance = _typed_source.historical_bytes(root, rel.as_posix(), physical,\n',
   '                _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)\n',
   '            require(hashlib.sha256(provenance).hexdigest() in {seed_count.SCORE_AFTER_SHA256, '
   'seed_count.station.AFTER_SHA256, seed_count.deviation.AFTER_SHA256},\n')),
 (130,
  133,
  ('                    == '
   'seed_count.score_family_token_sha256(hashlib.sha256(physical).hexdigest()),\n',),
  ('                    and source.token_sha256(_typed_source.historical_text(root, '
   'rel.as_posix(), text,\n',
   '                        _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n',
   '                    == '
   'seed_count.score_family_token_sha256(hashlib.sha256(provenance).hexdigest()),\n')),
 (136,
  139,
  (),
  ('        supplied_text = text\n',
   '        text = _typed_source.historical_text(root, rel.as_posix(), text, '
   '_operation=_operation,\n',
   '                                              _inputs=_inputs, _input_owner=_input_owner)\n')),
 (153,
  156,
  ('            physical_digest = hashlib.sha256(physical).hexdigest()\n',),
  ('            provenance = _typed_source.historical_bytes(root, rel.as_posix(), physical,\n',
   '                _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)\n',
   '            physical_digest = hashlib.sha256(provenance).hexdigest()\n')),
 (161,
  163,
  ('                require(supplied_tokens == '
   'seed_count.score_family_token_sha256(physical_digest),\n',),
  ('                require(source.token_sha256(supplied_text) == '
   "source.token_sha256(physical.decode('utf-8'))\n",
   '                        and supplied_tokens == '
   'seed_count.score_family_token_sha256(physical_digest),\n')),
 (176,
  177,
  ('                text = '
   "seed_count.score_family_predecessor_source(physical.decode('utf-8'))\n",),
  ('                text = '
   "seed_count.score_family_predecessor_source(provenance.decode('utf-8'))\n",)),
 (224,
  269,
  ('    record = read_record(root)\n',
   "    for name, expected in record['preserved_records'].items():\n",
   "        require(hashlib.sha256((root / 'tools/carla_lane_oracle' / "
   'name).read_bytes()).hexdigest() == expected,\n',
   "                'historical component changed: ' + name)\n",
   '    _input_owner = object()\n',
   '    _inputs = None\n',
   '    try:\n',
   '        current = (root / MODULE).read_text()\n',
   '        if _operation is not None:\n',
   '            current = full_audit._observe_text(root, MODULE, current, _operation=_operation, '
   'supplied=True)\n',
   '        if source.token_sha256(current) != AFTER_TOKEN_SHA256:\n',
   '            try:\n',
   '                if __package__:\n',
   '                    from . import full_audit_cleanup_contracts as full_audit\n',
   '                else:\n',
   '                    import full_audit_cleanup_contracts as full_audit\n',
   '                if full_audit._cache_verify_frame(sys._getframe()):\n',
   '                    current, _inputs = full_audit._cache_lane_inputs(root, current, '
   '_input_owner, **operation_args)\n',
   '                else:\n',
   '                    # Unsupported import aliases preserve the complete fresh\n',
   '                    # public path; they cannot acquire or borrow an input view.\n',
   '                    current = full_audit.reviewed_text(root, MODULE, current, '
   '**operation_args)\n',
   '            except (ValueError, OSError) as error:\n',
   "                raise ContractError('cache-key successor: ' + str(error)) from error\n",
   '        require(source.token_sha256(current) == AFTER_TOKEN_SHA256,\n',
   "                'complete live successor tokens changed')\n",
   '        # Exact adopted bytes reverse independently. General live source keeps the\n',
   '        # established comment/whitespace compatibility of the historical gates.\n',
   '        # Full tokens retain indentation, boundaries, qualifiers and operations.\n',
   "        reverse_exact(record['after'], record)\n",
   '        observed = (inventory(root, verified_lane_source=current, **operation_args) if _inputs '
   'is None else\n',
   '                    inventory(root, verified_lane_source=current, _inputs=_inputs, '
   '_input_owner=_input_owner, **operation_args))\n',
   "        require(observed == record['inventory'],\n",
   "                'production helper/caller inventory changed')\n",
   '        # Complete module tokens retain imports, builtin name resolution, types,\n',
   '        # external-witness/Optional guards, word order, memo lifetimes and ledgers.\n',
   '        if _inputs is not None:\n',
   '            _inputs.checkpoint(_input_owner, root)\n',
   '        return record\n',
   '    finally:\n',
   '        if _inputs is not None:\n',
   '            _inputs.close(_input_owner)\n'),
  ('    with _typed_source.typed_admission_scope(root) as _typed_admission:\n',
   '        record = read_record(root)\n',
   "        for name, expected in record['preserved_records'].items():\n",
   "            require(hashlib.sha256((root / 'tools/carla_lane_oracle' / "
   'name).read_bytes()).hexdigest() == expected,\n',
   "                    'historical component changed: ' + name)\n",
   '        _input_owner = object()\n',
   '        _inputs = None\n',
   '        try:\n',
   '            current = (root / MODULE).read_text()\n',
   '            if _operation is not None:\n',
   '                current = full_audit._observe_text(root, MODULE, current, '
   '_operation=_operation, supplied=True)\n',
   '            if source.token_sha256(current) != AFTER_TOKEN_SHA256:\n',
   '                try:\n',
   '                    if __package__:\n',
   '                        from . import full_audit_cleanup_contracts as full_audit\n',
   '                    else:\n',
   '                        import full_audit_cleanup_contracts as full_audit\n',
   '                    if full_audit._cache_verify_frame(sys._getframe()):\n',
   '                        current, _inputs = full_audit._cache_lane_inputs(root, current, '
   '_input_owner, **operation_args)\n',
   '                    else:\n',
   '                        # Unsupported import aliases preserve the complete fresh\n',
   '                        # public path; they cannot acquire or borrow an input view.\n',
   '                        current = full_audit.reviewed_text(root, MODULE, current, '
   '**operation_args)\n',
   '                except (ValueError, OSError) as error:\n',
   "                    raise ContractError('cache-key successor: ' + str(error)) from error\n",
   '            require(source.token_sha256(current) == AFTER_TOKEN_SHA256,\n',
   "                    'complete live successor tokens changed')\n",
   '            # Exact adopted bytes reverse independently. General live source keeps the\n',
   '            # established comment/whitespace compatibility of the historical gates.\n',
   '            # Full tokens retain indentation, boundaries, qualifiers and operations.\n',
   "            reverse_exact(record['after'], record)\n",
   '            observed = (inventory(root, verified_lane_source=current,\n',
   "                        **({} if _typed_admission is None else {'_admission': "
   '_typed_admission}),\n',
   '                        **operation_args) if _inputs is None else\n',
   '                        inventory(root, verified_lane_source=current, _inputs=_inputs, '
   '_input_owner=_input_owner, **operation_args))\n',
   "            require(observed == record['inventory'],\n",
   "                    'production helper/caller inventory changed')\n",
   '            # Complete module tokens retain imports, builtin name resolution, types,\n',
   '            # external-witness/Optional guards, word order, memo lifetimes and ledgers.\n',
   '            if _inputs is not None:\n',
   '                _inputs.checkpoint(_input_owner, root)\n',
   '            return record\n',
   '        finally:\n',
   '            if _inputs is not None:\n',
   '                _inputs.close(_input_owner)\n')),
 (294,
  298,
  (),
  ('    text = _typed_source.historical_text(root, MODULE, text, _operation=_operation)\n',
   '    observed = _typed_source.historical_text(root, MODULE, observed, _operation=_operation)\n',
   '    require(source.token_sha256(text) == source.token_sha256(observed),\n',
   "            'unreviewed supplied lane source')\n"))),
    'coverage_followup_contracts.py': (
        (3, 8,
         (),
         (
          'if __package__:\n',
          '    from . import source_contracts as _typed_source\n',
          'else:\n',
          '    import source_contracts as _typed_source\n',
          '\n',
         ),
        ),
        (9, 10,
         (),
         (
          '# #333 explicit historical provenance views; current inputs remain operation-owned.\n',
         ),
        ),
        (64, 65,
         (),
         (
          '\n',
         ),
        ),
        (70, 71,
         (
          '    payload = (root/MIGRATION).read_bytes()\n',
         ),
         (
          '    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())\n',
         ),
        ),
        (76, 77,
         (
          '    require(hashlib.sha256(prior.read_bytes()).hexdigest() ==\n',
         ),
         (
          '    require(hashlib.sha256(_typed_source.historical_bytes(root, prior, prior.read_bytes())).hexdigest() ==\n',
         ),
        ),
        (79, 80,
         (
          "        require(hashlib.sha256((root/'tools/carla_lane_oracle'/name).read_bytes()).hexdigest()\n",
         ),
         (
          "        require(hashlib.sha256(_typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/name, (root/'tools/carla_lane_oracle'/name).read_bytes())).hexdigest()\n",
         ),
        ),
        (104, 117,
         (),
         (
          'def _source_view(root, path, physical_text, *, _operation=None):\n',
          '    """Keep supplied physical views only for the helper\'s named authority domain."""\n',
          '    if __package__:\n',
          '        from . import full_audit_cleanup_contracts as cleanup\n',
          '    else:\n',
          '        import full_audit_cleanup_contracts as cleanup\n',
          '    if path == cache_key.MODULE or path in cleanup.SOURCE_PATHS:\n',
          '        return cache_key.reviewed_text(root, path, physical_text, _operation=_operation)\n',
          '    historical = _typed_source.historical_text(root, path, physical_text, _operation=_operation)\n',
          "    # For unrelated modules cache_key's historical API is an identity function.\n",
          '    return cache_key.reviewed_text(root, path, historical, _operation=_operation)\n',
          '\n',
          '\n',
         ),
        ),
        (127, 128,
         (
          "        require(source.token_sha256(accepted.predecessor_text(root, path, **operation_args) if path in accepted.SOURCE_PATHS else cache_key.reviewed_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), **operation_args)) == item['after_token_sha256'],\n",
         ),
         (
          "        require(source.token_sha256(accepted.predecessor_text(root, path, **operation_args) if path in accepted.SOURCE_PATHS else _source_view(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), **operation_args)) == item['after_token_sha256'],\n",
         ),
        ),
    ),
    'coverage_loop_proofs.py': ((13, 14, (), ('import importlib.util\n',)),
 (26, 28, (), ('\n', '_EXECUTED_MODULE_CODE = sys._getframe().f_code\n')),
 (333,
  412,
  (),
  ('\n',
   '\n',
   '# #333 transports only these reviewed theorem sites from exact main2d81.\n',
   '# The complete current scalar/bound/API graph is admitted first. Pure row\n',
   '# correspondence cannot itself grant a coverage mask or source receipt.\n',
   "_TYPED_LOOP_MAIN_SHA256 = {'extensions/carla/curve_rounded_arc.mojo': "
   "'7bc84049fed26cb7b14b4fa4603ee36d55cdeb7055c62df50cf10d6a2ce90745',\n",
   " 'extensions/carla/curve_rounded_line.mojo': "
   "'6741ad9d7434c08070de3c959cb49ac42939ac633d1dcd48c9f5cdfdaa719aed',\n",
   " 'extensions/carla/curve_sample_dispatch.mojo': "
   "'91ede65bbc39ac57ca54239513b462d3c71e90cacd085b8bafb2bff514767a86',\n",
   " 'extensions/carla/junction_bounds.mojo': "
   "'d8b7a6de8e495ab16f0cbe9688459eb544ac9ef6c8ec0c44c952ed5b4743a615',\n",
   " 'extensions/carla/lane_refinement.mojo': "
   "'13ae6d4658458a7d243597428eee762f9bbc40f8fe3507a47beac9ebd4ac1737',\n",
   " 'extensions/carla/map.mojo': "
   "'0e2d282fcd6c70217e7413b7febe40619af070f7adbeaefa3fd56d95562c404b',\n",
   " 'extensions/carla/opendrive.mojo': "
   "'9ff9b750af2c1c1a92fe3f3dfe1e49566e9d6f8c39a3576e0d4cf542bc8cdc28',\n",
   " 'extensions/carla/rtree.mojo': "
   "'be63ea929c25e0a55600d19568e5f8a117e2f712850ea3da0d977c39b002d460'}\n",
   "_TYPED_LOOP_ROWS = {('extensions/carla/curve_rounded_arc', 228): (228, (), "
   "'_rounded_arc_context'),\n",
   " ('extensions/carla/curve_rounded_line', 93): (93, (), '_rounded_line_axis_context'),\n",
   " ('extensions/carla/curve_sample_dispatch', 126): (126, (), '_try_sample_dispatch_cuts'),\n",
   " ('extensions/carla/junction_bounds', 706): (706, (), '_lane_section_box_with_work'),\n",
   " ('extensions/carla/lane_refinement', 145): (146, (), '_axis_lane_minimum'),\n",
   " ('extensions/carla/lane_refinement', 726): (736, (), '_lane_certificate_dominates_cells'),\n",
   " ('extensions/carla/lane_refinement', 1289): (1299, (), '_continue_lane_certificate'),\n",
   " ('extensions/carla/lane_refinement', 1314): (1324, (), '_continue_lane_certificate'),\n",
   " ('extensions/carla/map', 1491): (1511, (), '_try_winner_seed'),\n",
   " ('extensions/carla/map', 2272): (2294, ('Map',), '_closest_lane_certificate_with_work'),\n",
   " ('extensions/carla/map', 2279): (2301, ('Map',), '_closest_lane_certificate_with_work'),\n",
   " ('extensions/carla/map', 2301): (2323, ('Map',), '_closest_lane_certificate_with_work'),\n",
   " ('extensions/carla/map', 2373): (2395, ('Map',), '_closest_lane_certificate_with_work'),\n",
   " ('extensions/carla/map', 2378): (2400, ('Map',), '_closest_lane_certificate_with_work'),\n",
   " ('extensions/carla/map', 2387): (2409, ('Map',), '_closest_lane_certificate_with_work'),\n",
   " ('extensions/carla/map', 2396): (2418, ('Map',), '_closest_lane_certificate_with_work'),\n",
   " ('extensions/carla/map', 4055): (4106, ('Map',), '_add_segment'),\n",
   " ('extensions/carla/opendrive', 450): (450, (), '_active'),\n",
   " ('extensions/carla/opendrive', 593): (593, (), '_border_widths'),\n",
   " ('extensions/carla/opendrive', 601): (601, (), '_border_widths'),\n",
   " ('extensions/carla/opendrive', 615): (615, (), '_border_widths'),\n",
   " ('extensions/carla/opendrive', 617): (617, (), '_border_widths'),\n",
   " ('extensions/carla/opendrive', 621): (621, (), '_border_widths'),\n",
   " ('extensions/carla/opendrive', 787): (787, (), '_lanes'),\n",
   " ('extensions/carla/rtree', 666): (666, ('_Rtree',), '_nearest_next')}\n",
   '\n',
   '\n',
   'def _typed_loop_row(module, historical_line, expression, current):\n',
   '    """Locate one unchanged loop in its exact reviewed declaration owner.\n',
   '\n',
   '    The whole endpoint and inverse must be sealed. Match the complete ordered\n',
   '    loop-statement inventory of the owner, not just a line or expression.\n',
   '    Owners call this only after physical current graph admission.\n',
   '    """\n',
   '    from carla_lane_oracle import typed_boundary_contracts as typed\n',
   '    from carla_lane_oracle import seed_count_contracts as seed\n',
   '    item = _TYPED_LOOP_ROWS.get((module, historical_line))\n',
   "    name = module + '.mojo'\n",
   '    if item is None or not typed.is_current(name, current):\n',
   '        return None\n',
   '    previous = typed.historical_source(name, current)\n',
   "    if sha256(previous.encode('utf-8')) != _TYPED_LOOP_MAIN_SHA256[name]:\n",
   '        return None\n',
   '    main_line, owner, function = item\n',
   '    before, before_first, before_last = seed._function_span(previous, function, owner)\n',
   '    after, after_first, after_last = seed._function_span(current, function, owner)\n',
   '    old_statements, new_statements = _statements(before), _statements(after)\n',
   "    expected = _statements('for value in ' + expression + ':\\n    pass\\n')\n",
   '    if old_statements is None or new_statements is None or expected is None:\n',
   '        return None\n',
   '    def for_rows(statements, first):\n',
   '        return [(first + row[0].start[0], tuple(token.string for token in row))\n',
   "                for row in statements if row[0].string == 'for']\n",
   '    old_rows = for_rows(old_statements, before_first)\n',
   '    new_rows = for_rows(new_statements, after_first)\n',
   '    if [words for _, words in old_rows] != [words for _, words in new_rows]:\n',
   '        return None\n',
   '    selected = [(index, words) for index, (line, words) in enumerate(old_rows)\n',
   '                if line == main_line]\n',
   '    if len(selected) != 1:\n',
   '        return None\n',
   '    index, words = selected[0]\n',
   "    if len(words) < 5 or words[2] != 'in' or words[-1] != ':' or words[3:-1] != tuple(\n",
   '            token.string for token in expected[0])[3:-1]:\n',
   '        return None\n',
   '    return new_rows[index][0]\n')),
 (923,
  924,
  ('    if _operation is not None and include_roots != ():\n',
   "        cleanup._operation_fail(_operation, ValueError('Unowned coverage include roots'))\n"),
  ('    cleanup._operation_include_context(_operation, root, include_roots)\n',)),
 (977,
  1002,
  ('        if _operation is not None and include_roots != ():\n',
   "            cleanup._operation_fail(_operation, ValueError('Unowned coverage include "
   "roots'))\n"),
  ('        cleanup._operation_include_context(_operation, root, include_roots)\n',
   '    # A partial producer may contain a local reviewed theorem without its\n',
   '    # unrelated sibling prerequisites. Absence is established by the frozen\n',
   '    # producer census before any read; consumed or current admission failures\n',
   '    # are never downgraded to a missing proof.\n',
   "    if (_operation is not None and _operation._kind == 'generated_receipt'\n",
   "            and _operation._state == 'pending'\n",
   '            and not bindings.keys() <= _operation._receipt_source_digests.keys()):\n',
   '        from carla_lane_oracle import typed_boundary_contracts as typed\n',
   '        try:\n',
   '            typed.verify_authority()\n',
   '        except (ValueError, TypeError, KeyError, AttributeError) as error:\n',
   '            cleanup._operation_fail(_operation, error)\n',
   '        captured = _operation._receipt_source_digests\n',
   '        # Exact current and intermediate successor endpoints keep their\n',
   '        # existing admission path. Only historical bytes (or the explicitly\n',
   '        # paired density repair) can make an absent sibling inapplicable.\n',
   '        current = any(name in typed.EDGES and captured.get(name) == '
   "typed.EDGES[name]['after_sha256']\n",
   '                      for name in bindings)\n',
   '        historical = all(captured[name] == expected or (\n',
   '            name == DENSITY_SOURCE and expected == DENSITY_BEFORE_SHA256\n',
   '            and captured[name] == DENSITY_AFTER_SHA256)\n',
   '            for name, expected in bindings.items() if name in captured)\n',
   '        if not current and historical:\n',
   '            return None\n')),
 (1009,
  1024,
  (),
  ('        physical_digest = digest\n',
   '        from carla_lane_oracle import typed_boundary_contracts as typed\n',
   '        if typed.is_current(name, raw):\n',
   '            from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
   '            current_bindings = cleanup.proof_bindings(\n',
   '                root, include_roots=include_roots, **operation_args)\n',
   '            if (current_bindings.get(name) != physical_digest\n',
   '                    or _coverage_observe_bytes(root, name, path.read_bytes(),\n',
   '                        _operation=_operation) != raw):\n',
   '                return None\n',
   '            actual.update(current_bindings)\n',
   '            # The current numerical/API graph was physically admitted above.\n',
   '            # This exact inverse now supplies historical provenance only.\n',
   "            checked = typed.historical_source(name, raw.decode('utf-8'))\n",
   "            digest = sha256(checked.encode('utf-8'))\n")),
 (1030,
  1031,
  ('            actual[name] = digest\n',),
  ('            actual[name] = physical_digest\n',)),
 (1089,
  1090,
  ('                actual[name] = digest\n',),
  ('                actual[name] = physical_digest\n',)),
 (1094,
  1098,
  ('                actual.update(cleanup.proof_bindings(root, include_roots=include_roots))\n',
   '                if path.read_bytes() != raw:\n'),
  ('                actual.update(cleanup.proof_bindings(\n',
   '                    root, include_roots=include_roots, **operation_args))\n',
   '                if _coverage_observe_bytes(root, name, path.read_bytes(),\n',
   '                                           _operation=_operation) != raw:\n')),
 (1099,
  1100,
  ('                actual[name] = digest\n',),
  ('                actual[name] = physical_digest\n',)),
 (1118, 1119, ('        actual[name] = digest\n',), ('        actual[name] = physical_digest\n',)),
 (1120,
  1134,
  (),
  ('\n',
   '\n',
   'def _final_unowned_typed_loop_bindings(root, bindings, *, include_roots=()):\n',
   '    """Fresh final topology/caller admission after current lexical transport.\n',
   '\n',
   '    This helper is only for unowned standalone rows. Map/R-tree retain their\n',
   '    existing owning operation and sticky finalization; no kind is broadened.\n',
   '    """\n',
   '    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
   '    fresh = cleanup.proof_bindings(root, include_roots=include_roots)\n',
   '    if any(bindings.get(name) != digest for name,digest in fresh.items()):\n',
   '        return False\n',
   '    return all(sha256(relative_source(root,name).read_bytes()) == digest\n',
   '               for name,digest in bindings.items())\n')),
 (1146,
  1147,
  ('        if _operation is not None and include_roots != ():\n',
   "            cleanup._operation_fail(_operation, ValueError('Unowned coverage include "
   "roots'))\n"),
  ('        cleanup._operation_include_context(_operation, root, include_roots)\n',)),
 (1178,
  1206,
  ('    return {line: {\n',
   "        'line': line, 'kind': kind, 'cardinality': minimum,\n",
   "        'maximum_cardinality': maximum, 'required': 'T', 'impossible': 'F',\n",
   "        'expression': expression, 'proof_id': proof_id,\n",
   "        'dependency_sha256': actual,\n",
   '    } for line, kind, minimum, maximum, expression, proof_id in sites}\n'),
  ('    try:\n',
   '        result = {}\n',
   '        from carla_lane_oracle import typed_boundary_contracts as typed\n',
   "        name = module + '.mojo'\n",
   '        current = _coverage_observe_text(root, name,\n',
   '            relative_source(root, name, **operation_args).read_text(), '
   '_operation=_operation)\n',
   "        if sha256(current.encode('utf-8')) != actual[name]:\n",
   '            return {}\n',
   '        for line, kind, minimum, maximum, expression, proof_id in sites:\n',
   '            if typed.is_current(name, current):\n',
   '                line = _typed_loop_row(module, line, expression, current)\n',
   '                if line is None:\n',
   '                    return {}\n',
   '            result[line] = {\n',
   "                'line': line, 'kind': kind, 'cardinality': minimum,\n",
   "                'maximum_cardinality': maximum, 'required': 'T', 'impossible': 'F',\n",
   "                'expression': expression, 'proof_id': proof_id,\n",
   "                'dependency_sha256': actual,\n",
   '            }\n',
   '        if (typed.is_current(name, current) and _operation is None\n',
   '                and not _final_unowned_typed_loop_bindings(\n',
   '                    root, actual, include_roots=include_roots)):\n',
   '            return {}\n',
   '        return result\n',
   '    except (OSError, ValueError, ImportError, UnicodeError) as error:\n',
   '        if _operation is not None and isinstance(error, (OSError, UnicodeError)):\n',
   '            cleanup._operation_fail(_operation, error)\n',
   '        return {}\n')),
 (1214,
  1215,
  ('        if _operation is not None and include_roots != ():\n',
   "            cleanup._operation_fail(_operation, ValueError('Unowned coverage include "
   "roots'))\n"),
  ('        cleanup._operation_include_context(_operation, root, include_roots)\n',)),
 (1224,
  1237,
  ("        if (module == 'extensions/carla/map'\n",),
  ('        from carla_lane_oracle import typed_boundary_contracts as typed\n',
   "        module_path = module + '.mojo'\n",
   '        current = _coverage_observe_text(root, module_path,\n',
   '            relative_source(root, module_path, **operation_args).read_text(),\n',
   '            _operation=_operation)\n',
   "        if sha256(current.encode('utf-8')) != actual_bindings[module_path]:\n",
   '            return None\n',
   '        typed_current = typed.is_current(module_path, current)\n',
   '        if typed_current:\n',
   '            line = _typed_loop_row(module, line, expression, current)\n',
   '            if line is None:\n',
   '                return None\n',
   "        if (not typed_current and module == 'extensions/carla/map'\n")),
 (1256,
  1257,
  ('        if ((module, line) in _CLEANUP_LOOP_ROWS\n',),
  ('        if (not typed_current and (module, line) in _CLEANUP_LOOP_ROWS\n',)),
 (1265,
  1270,
  (),
  ('            paths = tuple(cache_key.input_paths(Path(root)))\n',
   '            if _operation is not None:\n',
   '                cleanup._operation_known_paths(root, frozenset(\n',
   "                    path.as_posix() for path in paths if path.suffix == '.mojo'),\n",
   '                    _operation=_operation)\n')),
 (1271,
  1272,
  ('                path.as_posix() for path in cache_key.input_paths(Path(root))\n',),
  ('                path.as_posix() for path in paths\n',)),
 (1273,
  1276,
  ('                and re.search(pattern,\n',
   '                              relative_source(root, path.as_posix()).read_text())\n'),
  ('                and re.search(pattern, _coverage_observe_text(root, path.as_posix(),\n',
   '                    relative_source(root, path.as_posix(), **operation_args).read_text(),\n',
   '                    _operation=_operation))\n')),
 (1295,
  1299,
  (),
  ('        if (typed_current and _operation is None\n',
   '                and not _final_unowned_typed_loop_bindings(\n',
   '                    root, actual_bindings, include_roots=include_roots)):\n',
   '            return None\n')),
 (1439,
  1502,
  (),
  ('def _typed_construction_boundary_loops(root, current, *, include_roots=(), _operation=None):\n',
   '    """Re-admit the nonempty-list theorem for the exact typed current graph.\n',
   '\n',
   '    Successful same-owner _build_transform still calls the concrete private\n',
   '    Road implementation and rejects a missing geometry before success. The\n',
   '    boundary producer still appends that geometry into a fresh owned list.\n',
   '    Numerical value changes and new early refusals do not weaken this fact.\n',
   '    """\n',
   '    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
   '    from carla_lane_oracle import typed_boundary_contracts as typed\n',
   "    operation_args = {} if _operation is None else {'_operation': _operation}\n",
   '    bindings = cleanup.proof_bindings(root, include_roots=include_roots, **operation_args)\n',
   "    name = 'extensions/carla/map.mojo'\n",
   "    if (bindings.get(name) != sha256(current.encode('utf-8'))\n",
   '            or not typed.is_current(name, current)):\n',
   '        return {}\n',
   "    line = _typed_loop_row('extensions/carla/map', CONSTRUCTION_BOUNDARY_LINE,\n",
   "                           'boundaries', current)\n",
   '    if line is None:\n',
   '        return {}\n',
   '    # Preserve the actual whole-maintained-source caller census. A pure\n',
   '    # historical view cannot hide a new caller, alias, package, or std shadow.\n',
   '    try:\n',
   '        for location in (root, *include_roots):\n',
   '            if (not _density_stdlib_unshadowed(location, **operation_args)\n',
   '                    or not _construction_boundary_callers(location, **operation_args)):\n',
   "                raise ValueError('typed constructor caller or stdlib premise changed')\n",
   '    except (OSError, UnicodeError, ValueError) as error:\n',
   '        # An applicable typed theorem consumed this premise in the shared\n',
   '        # owned operation. Its rejection must also revoke sibling Map rows.\n',
   '        if _operation is not None:\n',
   '            cleanup._operation_fail(_operation, error)\n',
   '        return {}\n',
   '    if (_operation is None and not _final_unowned_typed_loop_bindings(\n',
   '            root, bindings, include_roots=include_roots)):\n',
   '        return {}\n',
   '    # The receipt has disjoint executing-checker and source-input domains.\n',
   '    # Recheck both physical images. A checker copy is not a source observation;\n',
   '    # the owner separately retains this consumed premise through finalization.\n',
   '    try:\n',
   '        executing = cleanup.executing_checker_bindings(root)\n',
   '        cleanup.require(all(bindings.get(path) == digest\n',
   '                            for path, digest in executing.items()),\n',
   "                        'construction receipt checker image changed')\n",
   '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, '
   'AttributeError) as error:\n',
   '        cleanup._operation_fail(_operation, error)\n',
   '    for path, expected in bindings.items():\n',
   '        if path in executing:\n',
   '            continue\n',
   '        raw = _coverage_observe_bytes(root, path,\n',
   '            relative_source(root, path, **operation_args).read_bytes(),\n',
   '            _operation=_operation)\n',
   '        if sha256(raw) != expected:\n',
   '            return {}\n',
   '    return {line: {\n',
   "        'line': line, 'kind': 'reviewed-nonempty-iterator', 'cardinality': 1,\n",
   "        'minimum_cardinality': 1, 'maximum_cardinality': None,\n",
   "        'required': 'T', 'impossible': 'F', 'expression': 'boundaries',\n",
   "        'proof_id': 'construction-geometry-boundary-list',\n",
   "        'dependency_sha256': bindings,\n",
   '    }}\n',
   '\n',
   '\n')),
 (1509,
  1510,
  ('        if _operation is not None and include_roots != ():\n',
   "            cleanup._operation_fail(_operation, ValueError('Unowned coverage include "
   "roots'))\n"),
  ('        cleanup._operation_include_context(_operation, root, include_roots)\n',)),
 (1511,
  1519,
  (),
  ('        from carla_lane_oracle import typed_boundary_contracts as typed\n',
   "        name = 'extensions/carla/map.mojo'\n",
   '        current = _coverage_observe_text(root, name,\n',
   '            relative_source(root, name, **operation_args).read_text(),\n',
   '            _operation=_operation)\n',
   '        if typed.is_current(name, current):\n',
   '            return _typed_construction_boundary_loops(\n',
   '                root, current, include_roots=include_roots, **operation_args)\n')),
 (1548,
  1552,
  ('                and actual[name] == cleanup.shared_helpers.AFTER_SHA256[name])\n',),
  ('                and actual[name] == cleanup.shared_helpers.AFTER_SHA256[name]) and not (\n',
   '                name in cleanup.scaled_float32.SOURCE_PATHS\n',
   '                and expected[name] == cleanup.scaled_float32.BEFORE_SHA256[name]\n',
   '                and actual[name] == cleanup.scaled_float32.AFTER_SHA256[name])\n')),
 (1568,
  1575,
  (),
  ('        scaled_bindings = cleanup.scaled_float32_proof_bindings(\n',
   '            root, include_roots=include_roots, **operation_args)\n',
   '        for name in cleanup.scaled_float32.SOURCE_PATHS:\n',
   '            if scaled_bindings.get(name) == cleanup.scaled_float32.AFTER_SHA256[name]:\n',
   '                if expected.get(name) != cleanup.scaled_float32.BEFORE_SHA256[name]:\n',
   '                    return {}\n',
   '                expected[name] = cleanup.scaled_float32.AFTER_SHA256[name]\n')),
 (1593, 1594, (), ('        actual.update(scaled_bindings)\n',)),
 (1618,
  1629,
  ('def reviewed_nonempty_loops(root, module, *, include_roots=()):\n',),
  ('def _receipt_reviewed_nonempty_loops(root, module, *, include_roots, _operation):\n',
   '    """The direct generated receipt alone lends its immutable image to rows."""\n',
   '    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
   '    cleanup._operation_include_context(_operation, root, include_roots)\n',
   "    cleanup.require(_operation._kind == 'generated_receipt'\n",
   '                    and sys._getframe(1) is _operation._owner_frame,\n',
   "                    'generated row wrapper lacks its direct owner')\n",
   '    return reviewed_nonempty_loops(root, module, include_roots=include_roots, '
   '_operation=_operation)\n',
   '\n',
   '\n',
   'def reviewed_nonempty_loops(root, module, *, include_roots=(), _operation=None):\n')),
 (1630,
  1631,
  ('    _operation, owns_operation = None, False\n',),
  ('    owns_operation = False\n',)),
 (1633, 1634, ('    if bounded:\n',), ('    if bounded or _operation is not None:\n',)),
 (1637,
  1641,
  ('        if bounded:\n',),
  ('        if _operation is not None:\n',
   '            cleanup._operation_include_context(_operation, root, include_roots)\n',
   "            cleanup.require(_operation._kind == 'generated_receipt', 'foreign generated row "
   "owner')\n",
   '        elif bounded:\n')),
 (1879,
  1963,
  ('    proofs = []\n',
   '    for module in modules:\n',
   "        name = module + '.mojo'\n",
   '        original = relative_source(root, name)\n',
   '        if name not in inputs:\n',
   "            raise ValueError('Missing instrumented module: ' + module)\n",
   "        candidates = constant_loops(original.read_text(encoding='utf-8'))\n",
   '        reviewed = reviewed_nonempty_loops(root, module, include_roots=(build,))\n',
   '        if candidates.keys() & reviewed.keys():\n',
   "            raise ValueError('Conflicting reviewed loop proof: ' + module)\n",
   '        candidates.update(reviewed)\n',
   '        for line in sorted(candidates):\n',
   '            if (module, line) not in branches:\n',
   '                continue  # Existing exclusions cannot become new proofs.\n',
   "            if any(record[0] in {'C', 'M'} and record[1] == module\n",
   '                   and int(record[2]) == line for record in records):\n',
   "                raise ValueError('Loop proof conflicts with compound decision: ' + module)\n",
   "            proofs.append({'module': module, **candidates[line],\n",
   "                           'source_sha256': inputs[name]['source']})\n",
   '    counts = _counts(records)\n',
   "    counts['proven_impossible'] = len(proofs)\n",
   "    counts['required_total'] = counts['potential_total'] - len(proofs)\n",
   "    return {'schema': SCHEMA, 'python': sys.version,\n",
   "            'compiler': compiler, 'flags': flags,\n",
   "            'manifest_sha256': sha256(raw), 'tools': tools,\n",
   "            'root_inputs': root_inputs, 'inputs': inputs, 'generation': generation,\n",
   "            'execution': execution_contract(root, build, inputs, mojo=mojo,\n",
   '                                            capture_cache=capture_cache, suites=suites),\n',
   "            'proofs': proofs, 'denominator': counts}\n"),
  ("    _receipt_seed = {'schema': SCHEMA, 'python': sys.version,\n",
   "        'compiler': compiler, 'flags': flags, 'manifest_sha256': sha256(raw),\n",
   "        'tools': tools, 'root_inputs': root_inputs, 'inputs': inputs, 'generation': "
   'generation,\n',
   "        'execution': execution_contract(root, build, inputs, mojo=mojo,\n",
   '                                        capture_cache=capture_cache, suites=suites)}\n',
   '    cleanup = None\n',
   "    if importlib.util.find_spec('carla_lane_oracle') is None:\n",
   '        # Standalone plain receipts need no CARLA semantic authority. A known\n',
   '        # reviewed source may never silently become a plain-only receipt.\n',
   '        reviewed_modules = (set(REVIEWED_LOOP_RULES)\n',
   '                            | {row[0] for row in GUARDED_LOOP_RULES}\n',
   "                            | {'renderers/renderer', 'extensions/carla/map',\n",
   "                               DENSITY_SOURCE.removesuffix('.mojo')})\n",
   "        if reviewed_modules & {name.removesuffix('.mojo') for name in "
   "generation['modules']}:\n",
   "            raise ValueError('Reviewed loop authority is unavailable')\n",
   '    else:\n',
   '        # A present but broken authority installation is an error, not fallback.\n',
   '        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup\n',
   '    _plain_seed = canonical(_receipt_seed) if cleanup is None else None\n',
   '    _operation = (None if cleanup is None else\n',
   '                  cleanup._receipt_operation_enter(root, build, _receipt_seed))\n',
   '    try:\n',
   '        if _operation is None:\n',
   "            check_capture_inputs({'receipt': json.loads(_plain_seed)}, root, build)\n",
   '            if not all(_density_stdlib_unshadowed(location) for location in (root, build)):\n',
   "                raise ValueError('Plain receipt resolver surface changed')\n",
   '        else:\n',
   '            _operation._receipt_inputs_check()\n',
   '        proofs = []\n',
   '        for module in modules:\n',
   "            name = module + '.mojo'\n",
   '            original = relative_source(root, name)\n',
   '            if name not in inputs:\n',
   "                raise ValueError('Missing instrumented module: ' + module)\n",
   "            text = original.read_text(encoding='utf-8')\n",
   '            if _operation is None:\n',
   '                source_raw = original.read_bytes()\n',
   "                with io.TextIOWrapper(io.BytesIO(source_raw), encoding='utf-8', newline=None) "
   'as reader:\n',
   '                    observed_text = reader.read()\n',
   "                if (sha256(source_raw) != json.loads(_plain_seed)['root_inputs'][name]\n",
   '                        or text != observed_text):\n',
   "                    raise ValueError('Plain receipt consumed source differs from generation: ' "
   '+ name)\n',
   '            else:\n',
   '                text = cleanup._observe_text(root, name, text,\n',
   "                                             _operation=_operation, mode='physical')\n",
   '            candidates = constant_loops(text)\n',
   '            reviewed = ({} if _operation is None else\n',
   '                        _receipt_reviewed_nonempty_loops(root, module, '
   'include_roots=(build,),\n',
   '                                                         _operation=_operation))\n',
   '            if _operation is not None:\n',
   '                cleanup._operation_check(_operation, root)\n',
   '            if candidates.keys() & reviewed.keys():\n',
   "                raise ValueError('Conflicting reviewed loop proof: ' + module)\n",
   '            candidates.update(reviewed)\n',
   '            for line in sorted(candidates):\n',
   '                if (module, line) not in branches:\n',
   '                    continue  # Existing exclusions cannot become new proofs.\n',
   "                if any(record[0] in {'C', 'M'} and record[1] == module\n",
   '                       and int(record[2]) == line for record in records):\n',
   "                    raise ValueError('Loop proof conflicts with compound decision: ' + "
   'module)\n',
   "                proofs.append({'module': module, **candidates[line],\n",
   "                               'source_sha256': "
   "(json.loads(_plain_seed)['root_inputs'][name]\n",
   "                                   if _operation is None else inputs[name]['source'])})\n",
   '        counts = _counts(records)\n',
   "        counts['proven_impossible'] = len(proofs)\n",
   "        counts['required_total'] = counts['potential_total'] - len(proofs)\n",
   '        if _operation is None:\n',
   '            if canonical(_receipt_seed) != _plain_seed:\n',
   "                raise ValueError('Plain receipt seed changed after consumption')\n",
   "            result = {**json.loads(_plain_seed), 'proofs': proofs, 'denominator': counts}\n",
   "            check_capture_inputs({'receipt': result}, root, build)\n",
   '            if not all(_density_stdlib_unshadowed(location) for location in (root, build)):\n',
   "                raise ValueError('Plain receipt resolver surface changed')\n",
   '        else:\n',
   "            result = {**json.loads(_operation._receipt_seed), 'proofs': proofs, 'denominator': "
   'counts}\n',
   '            _operation.finish(root)\n',
   '        return result\n',
   '    except BaseException as error:\n',
   '        if _operation is not None:\n',
   '            _operation._invalidate(error)\n',
   '        raise\n',
   '    finally:\n',
   '        if _operation is not None:\n',
   '            _operation.close()\n'))),
    'full_audit_cleanup_contracts.py': ((50,
  53,
  (),
  ('        from . import scaled_float32_contracts as scaled_float32\n',
   '        from . import typed_boundary_contracts as typed_boundary\n',
   '        from . import conditioned_cubic_contracts as conditioned_cubic\n')),
 (62,
  65,
  (),
  ('        import scaled_float32_contracts as scaled_float32\n',
   '        import typed_boundary_contracts as typed_boundary\n',
   '        import conditioned_cubic_contracts as conditioned_cubic\n')),
 (145,
  146,
  ("DEPENDENCY_TOOL_SHA256 = {'tools/carla_lane_oracle/witness_format_contracts.py': "
   "'a76ba6d5bf18be80c151fd03ea7a7ebeb75af1c1ed8af1600037d5f75ac13cb3',\n",
   " 'tools/carla_lane_oracle/runtime_view_contracts.py': "
   "'0afad70cdd83529e89550aaca0c1a469e2b25ca963a90e2b7b17e1a2fd324193',\n",
   " 'tools/carla_lane_oracle/shared_helper_contracts.py': "
   "'70b070d0bd5117b146a71470a46cb7a02c7fc31dfac1a5236eed50faf75b468e',\n",
   " 'tools/carla_lane_oracle/map_station_contracts.py': "
   "'caca22f46767ced3037d839a7941cb73a8ccf816238ad2037e28715f060055b7',\n",
   " 'tools/carla_lane_oracle/map_deviation_contracts.py': "
   "'741a95b3fd3d0d51253dfef36327997c19ac90b9230a73942dd4697dcefffd39',\n",
   " 'tools/carla_lane_oracle/consumer_successor_ledger.py': "
   "'8c18296f05a4a5150fc6ef8b4ae287479096b5bcff6f1047c82e6aae405310a1',\n"),
  ("DEPENDENCY_TOOL_SHA256 = {'tools/carla_lane_oracle/scaled_float32_contracts.py': "
   "'e3a59a9f8d5a9394007c03fab6ac696e04998812dad5843a22e721bfbe57c2a1',\n",)),
 (148,
  161,
  (" 'tools/carla_lane_oracle/source_contracts.py': "
   "'857dd399291611dd35e11adbbdde0fca03ed4ff4277eec54ed3ec5815bbaf791',\n",
   " 'tools/carla_lane_oracle/sum2_guard_contracts.py': "
   "'cf9bb32fd36fefb641e2c97210bfffe0fac00b5b773e87b5b19d46877afbf9a4'}\n"),
  (" 'tools/carla_lane_oracle/conditioned_cubic_contracts.py': "
   "'df99ea0826d5efa936c56e4ece9aa79b41806b60e52121c4f564a8de5d5b0198',\n",
   " 'tools/carla_lane_oracle/consumer_successor_ledger.py': "
   "'ce9a639084dfcc1442c6ac7535060cf5a123c2eb96683d2f35816ec26b0599ed',\n",
   " 'tools/carla_lane_oracle/map_deviation_contracts.py': "
   "'741a95b3fd3d0d51253dfef36327997c19ac90b9230a73942dd4697dcefffd39',\n",
   " 'tools/carla_lane_oracle/map_station_contracts.py': "
   "'caca22f46767ced3037d839a7941cb73a8ccf816238ad2037e28715f060055b7',\n",
   " 'tools/carla_lane_oracle/runtime_view_contracts.py': "
   "'67316129402fac643be3c6e49ceef94bcb25c1ef92f81fd764a6abb583f89e34',\n",
   " 'tools/carla_lane_oracle/shared_helper_contracts.py': "
   "'70b070d0bd5117b146a71470a46cb7a02c7fc31dfac1a5236eed50faf75b468e',\n",
   " 'tools/carla_lane_oracle/source_contracts.py': "
   "'83fdd35b61f0dc7739160c113ae6b4558ad07d45ffded22b7062bc9a209032d0',\n",
   " 'tools/carla_lane_oracle/sum2_guard_contracts.py': "
   "'acbf385486e2b0dfe15a409d039cd31c8e9fed295704bc6adcb4289818b65f63',\n",
   " 'tools/carla_lane_oracle/typed_boundary_contracts.py': "
   "'baf231cb640435f5b81e350f32e6a0d6203e4ae5d0d6fb9bccb0c6d4bdbfae8a',\n",
   " 'tools/carla_lane_oracle/witness_format_contracts.py': "
   "'a76ba6d5bf18be80c151fd03ea7a7ebeb75af1c1ed8af1600037d5f75ac13cb3',\n",
   " 'tools/carla_lane_oracle/cache_key_contracts.py': "
   "'87233ebca3701e3a79b57b324afd48fcffb38b87cb3988859b6ae36bd63d919f',\n",
   " 'tools/carla_lane_oracle/rounded_line_selector_contracts.py': "
   "'e47ff613bc198bc5cb629940fc0bcbe3c9517a153cd8e799e65ff0215f7b12bb',\n",
   " 'tools/carla_lane_oracle/seed_count_contracts.py': "
   "'ff4a330326fd69bc649e6f235d1f05db4ed40e6b76b1d75e66a4474741c16345'}\n")),
 (229,
  233,
  ("                 'tools/carla_lane_oracle/witness_format_contracts.py')\n",),
  ("                 'tools/carla_lane_oracle/witness_format_contracts.py',\n",
   "                 'tools/carla_lane_oracle/typed_boundary_contracts.py',\n",
   "                 'tools/carla_lane_oracle/conditioned_cubic_contracts.py',\n",
   "                 'tools/carla_lane_oracle/scaled_float32_contracts.py')\n")),
 (638,
  642,
  (),
  ('    if type(value) is slice:\n',
   '        # Python 3.14 folds constant slices such as `x[:2]` into co_consts.\n',
   "        return ('slice', _code_constant(value.start), _code_constant(value.stop),\n",
   '                _code_constant(value.step))\n')),
 (703,
  704,
  ("for _module in (source, guard, _sibling('affected'), _sibling('cache_key'), consumer_ledger, "
   'station, shared_helpers, runtime_view, deviation, witness_format):\n',),
  ("for _module in (source, guard, _sibling('affected'), _sibling('cache_key'), consumer_ledger, "
   'station, shared_helpers, runtime_view, deviation, witness_format, typed_boundary, '
   'conditioned_cubic, scaled_float32):\n',)),
 (724,
  738,
  (),
  ('# Public scopes can be entered by a consumer imported later (or by an importlib\n',
   '# alias). Bind its reviewed code now, without importing it through a cycle.\n',
   'for _relative, _digest in DEPENDENCY_TOOL_SHA256.items():\n',
   '    _path = Path(__file__).resolve().parents[2] / _relative\n',
   '    _key = str(_path.resolve())\n',
   '    if _key not in _IMPORT_IDENTITIES:\n',
   '        _raw = _path.read_bytes()\n',
   '        require(not _path.is_symlink() and sha(_raw) == _digest,\n',
   "                'unreviewed public consumer checker bytes: ' + _relative)\n",
   '        _IMPORT_IDENTITIES[_key] = _digest\n',
   '        _IMPORT_CODE[_key] = _compiled_functions(_raw, str(_path))\n',
   '        _IMPORT_DEFAULTS[_key] = _compiled_defaults(_raw)\n',
   '\n',
   '\n')),
 (755,
  757,
  ('               vars(deviation), vars(witness_format))\n',),
  ('               vars(deviation), vars(witness_format), vars(typed_boundary), '
   'vars(conditioned_cubic),\n',
   '               vars(scaled_float32))\n')),
 (787,
  789,
  ('            supplied = Path(root) / relative\n',
   '            require(not supplied.is_symlink() and sha(supplied.read_bytes()) == captured,\n'),
  ('            supplied = _regular(root, relative)\n',
   '            require(sha(supplied.read_bytes()) == captured,\n')),
 (791,
  793,
  (),
  ('    typed_boundary.verify_authority()\n', '    conditioned_cubic.verify_authority()\n')),
 (903,
  905,
  ('def resolver_unshadowed(root, paths, *, render_entries=None):\n',),
  ('def resolver_unshadowed(root, paths, *, render_entries=None, typed_entries=None,\n',
   '                        math_entries=None):\n')),
 (914,
  916,
  (),
  ('    A separate math scope is only for the exact supplemental native witness.\n',
   "    It does not replace any production owner's existing resolver obligations.\n")),
 (929,
  941,
  (),
  ('    if math_entries is not None and (type(math_entries) is not frozenset\n',
   "            or '.' not in math_entries or any(type(path) is not str or not path\n",
   "            or Path(path).is_absolute() or '..' in Path(path).parts for path in "
   'math_entries)):\n',
   '        return False\n',
   '    if typed_entries is not None and (type(typed_entries) is not frozenset\n',
   "            or '.' not in typed_entries or any(type(path) is not str or not path\n",
   "            or Path(path).is_absolute() or '..' in Path(path).parts for path in "
   'typed_entries)):\n',
   '        return False\n',
   '    # Only these newly introduced families use the established compiled-entry\n',
   '    # lookup rule. Every pre-333 family keeps its historical refusal policy.\n',
   "    typed_families = ('animation', 'cameras', 'core', 'exporters', 'geometries',\n",
   "                      'lights', 'materials', 'objects', 'postprocessing', 'renderers')\n")),
 (985,
  990,
  ('                                     or relative_dir.casefold() in render_entries))\n',),
  ('                                     or relative_dir.casefold() in render_entries)\n',
   "                                and (scoped_name != 'math' or math_entries is None\n",
   '                                     or relative_dir.casefold() in math_entries)\n',
   '                                and (scoped_name not in typed_families or typed_entries is '
   'None\n',
   '                                     or relative_dir.casefold() in typed_entries))\n')),
 (1011,
  1023,
  ('    """Restrict only render\'s namespace clause with an established entry census."""\n',
   "    if not any(path.startswith('render/') for path in paths):\n"),
  ('    """Scope only reviewed new families with an established entry census.\n',
   '\n',
   '    Exact module and package prefixes never use this namespace-only exception.\n',
   '    The caller checks the complete physical source/entry inventory before and\n',
   '    after the operation; adding a new entry or import cannot reuse this scope.\n',
   '    Include-root callers first bind their physical source/entry census.\n',
   '    """\n',
   "    render = any(path.startswith('render/') for path in paths)\n",
   "    typed = any(path.split('/')[0] in ('animation', 'cameras', 'core', 'exporters',\n",
   "        'geometries', 'lights', 'materials', 'objects', 'postprocessing', 'renderers')\n",
   '        for path in paths)\n',
   '    if not render and not typed:\n')),
 (1024,
  1031,
  ("    require(type(entries) in (tuple, list), 'missing render entry census')\n",
   "    return {'render_entries': frozenset(('.', *(path.casefold() for path in entries),\n",
   '        *(str(Path(path).parent).casefold() for path in shared_helpers.TESTS)))}\n'),
  ("    require(type(entries) in (tuple, list), 'missing compiled entry census')\n",
   "    roots = frozenset(('.', *(path.casefold() for path in entries),\n",
   '        *(str(Path(path).parent).casefold() for path in shared_helpers.TESTS)))\n',
   '    typed_roots = roots | frozenset(str(Path(path).parent).casefold()\n',
   '                                    for path in typed_boundary.TESTS)\n',
   "    return {**({'render_entries': roots} if render else {}),\n",
   "            **({'typed_entries': typed_roots} if typed else {})}\n")),
 (1057,
  1073,
  (),
  ('\n',
   '\n',
   'def _include_entry_context(location, source_image, *, _operation=None):\n',
   '    """Bind an include surface to maintained source coordinates and entries.\n',
   '\n',
   '    The coverage generation owner authenticates origins and complete staged\n',
   '    bytes before requesting proofs. This additional structural gate records\n',
   '    every physical Mojo file and refuses unknown coordinates or changed entry\n',
   '    contexts; callers retain and reread its image through finalization.\n',
   '    """\n',
   '    entries, image = _helper_entry_census(location, _operation=_operation)\n',
   "    require(set(image) <= set(source_image), 'unmaintained include source coordinate')\n",
   "    expected = _sibling('affected').entry_directories(\n",
   '        {path: _physical_text(source_image[path]) for path in image})\n',
   "    require(list(entries) == expected, 'include compiled entry directories changed')\n",
   '    return entries, image\n')),
 (1171,
  1207,
  (),
  ('def _publish_input_image(view, snapshots, authority_raw, known, production,\n',
   '                         entries, resolver_paths, executing):\n',
   '    """Store an immutable image only after its concrete owner authenticated it."""\n',
   '    caller = sys._getframe(1)\n',
   '    require(caller.f_globals is globals()\n',
   '            and caller.f_code in (_live_function_code(_CacheInputs._publish),\n',
   '                                  _live_function_code(_PublicAdmission._publish))\n',
   "            and caller.f_locals.get('self') is view,\n",
   "            'input image publication requires its concrete publisher')\n",
   '    require(type(authority_raw) is bytes and sha(authority_raw) == MIGRATION_SHA256,\n',
   "            'invalid captured authority bytes')\n",
   '    image = dict(snapshots)\n',
   '    for path, raw in image.items():\n',
   '        require(type(path) is str and Path(path).as_posix() == path\n',
   '                and bool(Path(path).parts) and not Path(path).is_absolute()\n',
   "                and '..' not in Path(path).parts and type(raw) is bytes,\n",
   "                'invalid captured input bytes or path')\n",
   '    require(set(known) <= image.keys() and set(production) <= image.keys()\n',
   "            and set(SOURCE_PATHS) <= image.keys(), 'incomplete captured input image')\n",
   '    require(not view._scaled_resolver_paths or\n',
   '            (view._scaled_resolver_paths == scaled_float32.NATIVE_CLOSURE\n',
   '             and view._scaled_resolver_paths <= image.keys()),\n',
   "            'pending scaled native context differs from captured image')\n",
   '    view._raw = types.MappingProxyType(image)\n',
   '    view._record_raw = authority_raw\n',
   '    view._known = frozenset(known)\n',
   '    view._production = frozenset(production)\n',
   '    view._entries = tuple(entries)\n',
   '    view._native_contexts = tuple((path, (str(Path(path).parent),)) for path in '
   'NATIVE_WITNESSES)\n',
   '    view._resolver_paths = frozenset(resolver_paths)\n',
   '    require(not view._executing or dict(view._executing) == executing,\n',
   "            'pending checker image differs from captured execution')\n",
   '    view._executing = types.MappingProxyType(dict(executing))\n',
   "    view._state = 'active'\n",
   '\n',
   '\n')),
 (1226, 1227, (), ('        self._scaled_resolver_paths = frozenset()\n',)),
 (1268,
  1270,
  ('        require(type(authority_raw) is bytes and sha(authority_raw) == MIGRATION_SHA256,\n',
   "                'invalid captured authority bytes')\n",
   '        image = dict(snapshots)\n',
   '        for path, raw in image.items():\n',
   '            require(type(path) is str and Path(path).as_posix() == path\n',
   '                    and bool(Path(path).parts) and not Path(path).is_absolute()\n',
   "                    and '..' not in Path(path).parts and type(raw) is bytes,\n",
   "                    'invalid captured input bytes or path')\n",
   '        require(set(known) <= image.keys() and set(production) <= image.keys()\n',
   "                and set(SOURCE_PATHS) <= image.keys(), 'incomplete captured input image')\n",
   '        self._raw = types.MappingProxyType(image)\n',
   '        self._record_raw = authority_raw\n',
   '        self._known = frozenset(known)\n',
   '        self._production = frozenset(production)\n',
   '        self._entries = tuple(entries)\n',
   '        self._native_contexts = tuple((path, (str(Path(path).parent),)) for path in '
   'NATIVE_WITNESSES)\n',
   '        self._resolver_paths = frozenset(resolver_paths)\n',
   '        require(not self._executing or dict(self._executing) == executing,\n',
   "                'pending checker image differs from captured execution')\n",
   '        self._executing = types.MappingProxyType(dict(executing))\n',
   "        self._state = 'active'\n"),
  ('        _publish_input_image(self, snapshots, authority_raw, known, production,\n',
   '                             entries, resolver_paths, executing)\n')),
 (1326,
  1327,
  ('            require(sha(self.raw(owner, root, path)) == AFTER_SHA256[path],\n',),
  ('            require(sha(_historical_typed_text(path, self.raw(owner, root, '
   "path).decode('utf-8'))) == AFTER_SHA256[path],\n",)),
 (1353,
  1358,
  (),
  ('            if self._scaled_resolver_paths:\n',
   '                require(self._scaled_resolver_paths == scaled_float32.NATIVE_CLOSURE\n',
   '                        and resolver_unshadowed(root, self._scaled_resolver_paths,\n',
   '                                                **_scaled_lookup_args()),\n',
   "                        'scaled native resolver changed during owned verification')\n")),
 (1379, 1380, (), ('        self._scaled_resolver_paths = frozenset()\n',)),
 (1391,
  1715,
  (),
  ('\n',
   '\n',
   '# Only these explicit public entries can own a short-lived typed admission.\n',
   '# The existing dependency authority binds their complete executable sources.\n',
   'def _public_admission_entries():\n',
   "    return {'cache_key_contracts.py': ('verify',),\n",
   "            'rounded_line_selector_contracts.py': ('verify_premises',),\n",
   "            'seed_count_contracts.py': ('verify_score',)}\n",
   '\n',
   '\n',
   '\n',
   'def _public_admission_scope(root, frame):\n',
   '    caller = sys._getframe(1)\n',
   '    require(caller.f_globals is vars(source)\n',
   '            and caller.f_code is _live_function_code(source.typed_admission_scope)\n',
   '            and caller.f_back is frame,\n',
   "            'public admission requires its direct source factory')\n",
   '    return _PublicAdmission(root, frame)\n',
   '\n',
   '\n',
   'class _PublicAdmission:\n',
   '    """A live public call\'s fully admitted image, never an ambient PASS."""\n',
   '\n',
   '    def __init__(self, root, frame):\n',
   '        caller = sys._getframe(1)\n',
   '        require(caller.f_globals is globals()\n',
   '                and caller.f_code is _public_admission_scope.__code__\n',
   "                and caller.f_locals.get('frame') is frame,\n",
   "                'public admission requires its direct factory')\n",
   "        filename = frame.f_globals.get('__file__')\n",
   '        require(type(filename) is str\n',
   '                and Path(filename).absolute().parent == Path(__file__).absolute().parent\n',
   '                and frame.f_code.co_name in '
   '_public_admission_entries().get(Path(filename).name, ()),\n',
   "                'unsupported public admission owner')\n",
   '        self._owner_frame = frame\n',
   '        self._owner = object()\n',
   '        self._stamp = id(self)\n',
   '        self._thread = threading.get_ident()\n',
   '        self._root = _absolute_root_text(root)\n',
   '        self._cwd = str(Path.cwd())\n',
   '        self._include_roots = ()\n',
   "        self._state = 'pending'\n",
   '        self._failed = False\n',
   '        self._raw = types.MappingProxyType({})\n',
   '        self._record_raw = None\n',
   '        self._known = self._production = frozenset()\n',
   '        self._entries = self._native_contexts = ()\n',
   '        self._resolver_paths = self._scaled_resolver_paths = frozenset()\n',
   '        self._executing = types.MappingProxyType({})\n',
   '        self._checker_raw = {}\n',
   '        self._checker_codes = {}\n',
   '        self._checker_frames = {}\n',
   '        self._inventory_frame = None\n',
   "        require(self._authenticate_frame(frame), 'unreviewed public admission owner code')\n",
   '\n',
   '    def _authenticate_frame(self, frame):\n',
   '        namespace = frame.f_globals\n',
   "        filename = namespace.get('__file__')\n",
   '        if type(filename) is not str:\n',
   '            return False\n',
   '        physical = Path(filename).absolute()\n',
   '        base = Path(__file__).absolute().parents[2]\n',
   '        if not physical.is_relative_to(base):\n',
   '            return False\n',
   '        relative = physical.relative_to(base).as_posix()\n',
   '        expected = _IMPORT_IDENTITIES.get(str(physical.resolve()))\n',
   '        if expected is None:\n',
   '            return False\n',
   '        require(physical == _SELF_PATH or DEPENDENCY_TOOL_SHA256.get(relative) == expected,\n',
   "                'public consumer checker authority changed: ' + relative)\n",
   '        raw = _regular(base, relative).read_bytes()\n',
   "        require(sha(raw) == expected, 'public admission checker changed: ' + relative)\n",
   '        previous = self._checker_raw.setdefault(relative, raw)\n',
   "        require(previous == raw, 'public admission checker changed during call: ' + "
   'relative)\n',
   '        if relative not in self._checker_codes:\n',
   '            def nested(code):\n',
   '                yield code\n',
   '                for child in code.co_consts:\n',
   '                    if type(child) is types.CodeType:\n',
   '                        yield from nested(child)\n',
   '            self._checker_codes[relative] = {\n',
   '                code.co_qualname: code for code in nested(compile(\n',
   "                    raw, filename, 'exec', dont_inherit=True, optimize=sys.flags.optimize))}\n",
   '        expected_code = self._checker_codes[relative].get(frame.f_code.co_qualname)\n',
   '        if expected_code is None or _code_identity(frame.f_code) != '
   '_code_identity(expected_code):\n',
   '            return False\n',
   "        parts = frame.f_code.co_qualname.split('.')\n",
   '        live = namespace.get(parts[0])\n',
   '        if type(live) is type and len(parts) > 1:\n',
   '            live = getattr(live, parts[1], None)\n',
   '        code = _live_function_code(live)\n',
   '        if code is frame.f_code:\n',
   '            self._checker_frames[(id(namespace), frame.f_code)] = frame\n',
   '            return True\n',
   '        # Comprehensions retain the identity of their executing parent code.\n',
   '        def contains(parent):\n',
   '            return parent is frame.f_code or any(contains(child) for child in '
   'parent.co_consts\n',
   '                if type(child) is types.CodeType)\n',
   '        return type(code) is types.CodeType and contains(code)\n',
   '\n',
   '    def __enter__(self):\n',
   "        require(sys._getframe(1) is self._owner_frame and self._state == 'pending',\n",
   "                'public admission entry requires its live owner')\n",
   '        return self\n',
   '\n',
   '    def _check_context(self, root):\n',
   '        require(_absolute_root_text(root) == self._root and str(Path.cwd()) == self._cwd\n',
   '                and self._thread == threading.get_ident(),\n',
   "                'public admission root, thread or working directory changed')\n",
   '\n',
   '    def _check(self, owner, root):\n',
   '        try:\n',
   '            require(type(self) is _PublicAdmission and self._stamp == id(self)\n',
   '                    and owner is self._owner and not self._failed\n',
   "                    and self._state in ('pending', 'active'), 'inactive public admission')\n",
   '            self._check_context(root)\n',
   '            methods = {code.co_name: code for code in\n',
   "                _IMPORT_CODE[str(_SELF_PATH)]['_PublicAdmission'].co_consts\n",
   '                if type(code) is types.CodeType}\n',
   "            for name in ('_publish', 'raw', 'observe_bytes'):\n",
   '                method = vars(_PublicAdmission).get(name)\n',
   '                require(name not in self.__dict__ and type(method) is types.FunctionType\n',
   '                        and method.__globals__ is globals()\n',
   "                        and '__wrapped__' not in method.__dict__\n",
   '                        and _code_identity(method.__code__) == '
   '_code_identity(methods[name]),\n',
   "                        'public admission image method changed: ' + name)\n",
   '            shared = {code.co_name: code for code in\n',
   "                _IMPORT_CODE[str(_SELF_PATH)]['_CacheInputs'].co_consts\n",
   '                if type(code) is types.CodeType}\n',
   "            for name in ('raw', 'observe_bytes', 'checkpoint'):\n",
   '                method = vars(_CacheInputs).get(name)\n',
   '                require(type(method) is types.FunctionType and method.__globals__ is '
   'globals()\n',
   "                        and '__wrapped__' not in method.__dict__\n",
   '                        and _code_identity(method.__code__) == _code_identity(shared[name]),\n',
   "                        'public admission shared method changed: ' + name)\n",
   '            frame = sys._getframe(1)\n',
   '            while frame is not None and frame is not self._owner_frame:\n',
   '                frame = frame.f_back\n',
   '            require(frame is self._owner_frame and frame is not None\n',
   "                    and frame.f_locals.get('_typed_admission') is self,\n",
   "                    'public admission owner is no longer active')\n",
   "            require(self._authenticate_frame(frame), 'public admission owner code changed')\n",
   '        except (OSError, UnicodeError, ValueError, TypeError, KeyError, AttributeError):\n',
   '            self.fail()\n',
   '            raise\n',
   '\n',
   '    def _check_pending(self, root):\n',
   '        self._check(self._owner, root)\n',
   "        require(self._state == 'pending' and not self._raw and self._record_raw is None,\n",
   "                'invalid pending public admission')\n",
   '        publisher = sys._getframe(1)\n',
   '        gate = publisher.f_back\n',
   '        require(publisher.f_code is _live_function_code(_PublicAdmission._publish)\n',
   '                and gate is not None and gate.f_globals is globals()\n',
   '                and gate.f_code is _live_function_code(verify)\n',
   "                and gate.f_locals.get('_public_admission') is self,\n",
   "                'public admission publication requires its complete gate')\n",
   '\n',
   '    def _publish(self, root, snapshots, authority_raw, known, production,\n',
   '                 entries, resolver_paths, executing):\n',
   '        caller = sys._getframe(1)\n',
   '        require(caller.f_globals is globals()\n',
   '                and caller.f_code is _live_function_code(verify),\n',
   "                'public input publication requires the full gate')\n",
   '        self._check_pending(root)\n',
   '        _publish_input_image(self, snapshots, authority_raw, known, production,\n',
   '                             entries, resolver_paths, executing)\n',
   '\n',
   '    def raw(self, owner, root, path):\n',
   '        return _CacheInputs.raw(self, owner, root, path)\n',
   '\n',
   '    def observe_bytes(self, owner, root, path):\n',
   '        return _CacheInputs.observe_bytes(self, owner, root, path)\n',
   '\n',
   '\n',
   '    def _check_consumer_bindings(self):\n',
   '        for frame in tuple(self._checker_frames.values()):\n',
   "            require(self._authenticate_frame(frame), 'public consumer frame changed')\n",
   '            namespace = frame.f_globals\n',
   "            path = Path(namespace['__file__']).resolve()\n",
   '            relative = path.relative_to(_SELF_PATH.parents[2]).as_posix()\n',
   '            if relative in CHECKER_PATHS:\n',
   '                continue  # The complete gate/checkpoint checks these modules.\n',
   '            key = str(path)\n',
   '            for name, expected in _IMPORT_CODE[key].items():\n',
   "                if name.startswith('<'):\n",
   '                    continue\n',
   '                live = namespace.get(name)\n',
   '                members = ({child.co_name: child for child in expected.co_consts\n',
   '                            if type(child) is types.CodeType}\n',
   '                           if type(live) is type else {None: expected})\n',
   '                for member, code in members.items():\n',
   '                    value = getattr(live, member, None) if member else live\n',
   "                    label = relative + ':' + name + ('.' + member if member else '')\n",
   '                    _check_defaults(value, _IMPORT_DEFAULTS[key].get(\n',
   "                        name + '.' + member if member else name), label)\n",
   '                    actual = _live_function_code(value)\n',
   '                    require(actual is not None and _code_identity(actual) == '
   '_code_identity(code),\n',
   "                            'public consumer binding changed: ' + label)\n",
   '\n',
   '    def _publication_inputs(self, root, snapshots):\n',
   '        self._check(self._owner, root)\n',
   '        self._check_consumer_bindings()\n',
   '        image = dict(snapshots)\n',
   '        for path, expected in self._checker_raw.items():\n',
   '            raw = _regular(root, path).read_bytes()\n',
   "            require(raw == expected, 'public checker differs from admitted root: ' + path)\n",
   "            require(image.setdefault(path, raw) == raw, 'public checker observation changed: ' "
   '+ path)\n',
   "        if self._state == 'active':\n",
   '            for path, raw in image.items():\n',
   '                require(self._raw.get(path) == raw or\n',
   '                        (path not in self._raw and self._checker_raw.get(path) == raw),\n',
   "                        'public input changed between admissions: ' + path)\n",
   '        return image\n',
   '\n',
   '    def project(self, root, path, raw):\n',
   '        try:\n',
   '            self._check(self._owner, root)\n',
   '            caller = sys._getframe(1)\n',
   '            require(caller.f_globals is globals()\n',
   '                    and caller.f_code is _live_function_code(reviewed_typed_text),\n',
   "                    'public projection requires its actual typed adapter')\n",
   "            require(self._state == 'active' and self._raw.get(path) == raw,\n",
   "                    'typed source differs from public admission: ' + path)\n",
   '            # A semantic admission is not an exact endpoint admission by itself.\n',
   '            for name in SOURCE_PATHS:\n',
   "                require(sha(_historical_typed_text(name, self._raw[name].decode('utf-8')))\n",
   "                        == AFTER_SHA256[name], 'unreviewed exact public endpoint: ' + name)\n",
   '            typed_boundary.verify_authority()\n',
   '            conditioned_cubic.verify_authority()\n',
   '        except (OSError, UnicodeError, ValueError, TypeError, KeyError, AttributeError):\n',
   '            self.fail()\n',
   '            raise\n',
   '\n',
   '    def fail(self):\n',
   '        self._failed = True\n',
   '\n',
   '    def __exit__(self, kind, error, traceback):\n',
   '        try:\n',
   '            require(sys._getframe(1) is self._owner_frame,\n',
   "                    'public admission exit requires its live owner')\n",
   '            if error is not None:\n',
   '                self.fail()\n',
   '            if kind is None:\n',
   '                self._check(self._owner, Path(self._root))\n',
   "                if self._state == 'active':\n",
   '                    self._check_consumer_bindings()\n',
   '                    for frame in tuple(self._checker_frames.values()):\n',
   '                        require(self._authenticate_frame(frame),\n',
   "                                'public admission consumer code changed')\n",
   '                    for path, raw in self._checker_raw.items():\n',
   '                        require(_regular(Path(self._root), path).read_bytes() == raw,\n',
   "                                'public consumer checker changed at exit: ' + path)\n",
   '                    _CacheInputs.checkpoint(self, self._owner, Path(self._root))\n',
   '                    self._check(self._owner, Path(self._root))\n',
   '        finally:\n',
   "            self._state = 'closed'\n",
   '            self._raw = types.MappingProxyType({})\n',
   '            self._record_raw = None\n',
   '            self._checker_raw.clear()\n',
   '            self._checker_codes.clear()\n',
   '            self._checker_frames.clear()\n',
   '            self._owner_frame = None\n',
   '            self._inventory_frame = None\n',
   '        return False\n',
   '\n',
   '    def __copy__(self):\n',
   "        raise ContractError('full-audit cleanup successor: public admissions cannot be "
   "copied')\n",
   '\n',
   '    def __deepcopy__(self, memo):\n',
   '        return self.__copy__()\n',
   '\n',
   '    def __reduce_ex__(self, protocol):\n',
   '        return self.__copy__()\n',
   '\n',
   '\n',
   'def _cache_inventory_admission_frame(frame, scope):\n',
   "    filename = frame.f_globals.get('__file__')\n",
   '    valid = (type(filename) is str and Path(filename).absolute() ==\n',
   "            Path(__file__).absolute().with_name('cache_key_contracts.py')\n",
   "            and frame.f_code is _live_function_code(frame.f_globals.get('inventory'))\n",
   "            and frame.f_locals.get('_admission') is scope\n",
   '            and scope._authenticate_frame(frame))\n',
   '    if valid:\n',
   '        if scope._inventory_frame is None:\n',
   '            scope._inventory_frame = frame\n',
   '        elif scope._inventory_frame is not frame:\n',
   '            scope.fail()\n',
   "            raise ContractError('full-audit cleanup successor: public inventory invocation "
   "changed')\n",
   '    return valid\n',
   '\n',
   '\n',
   'def _public_admission_for(root, *, publication=False):\n',
   '    """Find an explicitly entered owner through authenticated callsites only."""\n',
   '    frames = []\n',
   '    frame = sys._getframe(1)\n',
   '    while frame is not None:\n',
   "        scope = frame.f_locals.get('_typed_admission')\n",
   "        borrowed = frame.f_locals.get('_admission')\n",
   '        bridge = (type(borrowed) is _PublicAdmission\n',
   '                  and _cache_inventory_admission_frame(frame, borrowed))\n',
   '        if bridge:\n',
   '            scope = borrowed\n',
   '        if type(scope) is _PublicAdmission and (scope._owner_frame is frame or bridge):\n',
   '            try:\n',
   '                wrappers = set()\n',
   '                for call in frames:\n',
   '                    if publication and call.f_code in wrappers:\n',
   '                        wrappers.remove(call.f_code)\n',
   '                        continue\n',
   '                    if not scope._authenticate_frame(call):\n',
   '                        return None\n',
   '                    candidate = call.f_globals.get(call.f_code.co_name)\n',
   '                    while type(candidate) is types.FunctionType and hasattr(candidate, '
   "'__wrapped__'):\n",
   '                        wrappers.add(candidate.__code__)\n',
   '                        candidate = candidate.__wrapped__\n',
   '                scope._check(scope._owner, root)\n',
   '                return scope\n',
   '            except (OSError, UnicodeError, ValueError, TypeError, KeyError, AttributeError):\n',
   '                scope.fail()\n',
   '                raise\n',
   '        frames.append(frame)\n',
   '        frame = frame.f_back\n',
   '    return None\n')),
 (1744,
  1748,
  (),
  ("        elif kind == 'runtime':\n",
   "            name = 'check_runtime_support'\n",
   "        elif kind == 'sampled':\n",
   "            name = 'check_sampled_values'\n")),
 (1753,
  1755,
  ("                'winner': 'winner_sign_contracts', 'border': "
   "'border_parser_contracts'}.get(kind)\n",),
  ("                'winner': 'winner_sign_contracts', 'border': 'border_parser_contracts',\n",
   "                'runtime': 'check_runtime_support', 'sampled': "
   "'check_sampled_values'}.get(kind)\n")),
 (1756,
  1781,
  (),
  ('\n',
   '\n',
   'def _seed_frame_kind(frame, *, include_aliases=False):\n',
   '    """Recognize only the canonical standalone seed wrapper; aliases block reuse."""\n',
   '    namespace = frame.f_globals\n',
   '    if type(namespace) is not dict:\n',
   '        return None\n',
   "    candidate = namespace.get('_verify_standalone')\n",
   '    if type(candidate) is not types.FunctionType or frame.f_code is not candidate.__code__:\n',
   '        return None\n',
   "    filename = namespace.get('__file__')\n",
   '    if type(filename) is not str:\n',
   '        return None\n',
   "    expected = Path(__file__).absolute().with_name('seed_count_contracts.py')\n",
   '    if Path(filename).absolute() != expected:\n',
   '        return None\n',
   "    module_code = namespace.get('_EXECUTED_MODULE_CODE')\n",
   '    if type(module_code) is types.CodeType:\n',
   '        codes = [code for code in module_code.co_consts\n',
   "                 if type(code) is types.CodeType and code.co_name == '_verify_standalone']\n",
   "        module = sys.modules.get((__package__ + '.' if __package__ else '') + "
   "'seed_count_contracts')\n",
   '        if (len(codes) == 1 and codes[0] is frame.f_code and candidate.__globals__ is '
   'namespace\n',
   '                and type(module) is types.ModuleType and namespace is vars(module)):\n',
   "            return 'seed'\n",
   "    return 'alias_seed' if include_aliases else None\n")),
 (1788,
  1794,
  (),
  ('    receipt_kind = _receipt_frame_kind(frame, include_aliases=include_aliases)\n',
   '    if receipt_kind is not None:\n',
   '        return receipt_kind\n',
   '    seed_kind = _seed_frame_kind(frame, include_aliases=include_aliases)\n',
   '    if seed_kind is not None:\n',
   '        return seed_kind\n')),
 (1839,
  1841,
  (),
  ("                            (prefix + 'check_runtime_support', 'verify'),\n",
   "                            (prefix + 'check_sampled_values', 'verify'),\n")),
 (1850,
  1851,
  ("    for kind in ('invariant', 'winner', 'border'):\n",),
  ("    for kind in ('invariant', 'winner', 'border', 'runtime', 'sampled'):\n",)),
 (1864,
  1866,
  ("                                         'border_parser_contracts.py', "
   "'coverage_loop_proofs.py')):\n",),
  ("                                         'border_parser_contracts.py', "
   "'check_runtime_support.py',\n",
   "                                         'check_sampled_values.py', "
   "'coverage_loop_proofs.py')):\n")),
 (1869,
  1871,
  ("                       ('border', 'border_parser_contracts.py')):\n",),
  ("                       ('border', 'border_parser_contracts.py'),\n",
   "                       ('runtime', 'check_runtime_support.py'), ('sampled', "
   "'check_sampled_values.py')):\n")),
 (1880,
  1933,
  (),
  ('def _receipt_frame_kind(frame, *, include_aliases=False):\n',
   '    """Recognize the real maintained import or script; aliases only block reuse."""\n',
   '    namespace = frame.f_globals\n',
   '    if type(namespace) is not dict:\n',
   '        return None\n',
   "    candidate = namespace.get('build_receipt')\n",
   '    if type(candidate) is not types.FunctionType or frame.f_code is not candidate.__code__:\n',
   '        return None\n',
   "    filename = namespace.get('__file__')\n",
   '    if type(filename) is not str:\n',
   '        return None\n',
   "    expected = Path(__file__).absolute().parent.parent / 'coverage_loop_proofs.py'\n",
   '    if Path(filename).absolute() != expected:\n',
   '        return None\n',
   "    module_code = namespace.get('_EXECUTED_MODULE_CODE')\n",
   '    if type(module_code) is types.CodeType:\n',
   '        codes = [code for code in module_code.co_consts\n',
   "                 if type(code) is types.CodeType and code.co_name == 'build_receipt']\n",
   '        if len(codes) == 1 and codes[0] is frame.f_code and candidate.__globals__ is '
   'namespace:\n',
   "            for name in ('coverage_loop_proofs', 'tools.coverage_loop_proofs', '__main__'):\n",
   '                module = sys.modules.get(name)\n',
   '                if type(module) is types.ModuleType and namespace is vars(module):\n',
   "                    return 'generated_receipt'\n",
   "    return 'alias_generated_receipt' if include_aliases else None\n",
   '\n',
   '\n',
   'def _receipt_operation_enter(root, build, seed):\n',
   '    """Create a lazy image only for one live maintained generated receipt."""\n',
   '    frame = sys._getframe(1)\n',
   "    require(_receipt_frame_kind(frame) == 'generated_receipt'\n",
   "            and frame.f_locals.get('root') == root and frame.f_locals.get('build') == build\n",
   "            and frame.f_locals.get('_receipt_seed') is seed,\n",
   "            'generated receipt requires its direct producer frame')\n",
   "    return _InvariantInputs(root, frame, 'generated_receipt')\n",
   '\n',
   '\n',
   'def _operation_include_context(operation, root, include_roots):\n',
   '    """Nonempty include ownership belongs only to the exact generated invocation."""\n',
   '    try:\n',
   '        _operation_check(operation, root)\n',
   '        if operation is not None:\n',
   '            expected = operation._include_roots\n',
   '            supplied = tuple(_absolute_root_text(path) for path in include_roots)\n',
   '            # A generated receipt also admits root-only historical inputs.\n',
   '            require(supplied == expected or (supplied == ()\n',
   "                                             and operation._kind == 'generated_receipt'),\n",
   "                    'operation include root changed')\n",
   "            require(not expected or operation._kind == 'generated_receipt',\n",
   "                    'unowned coverage include roots')\n",
   '    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:\n',
   '        _operation_fail(operation, error)\n',
   '\n',
   '\n')),
 (1940,
  1958,
  ("    if kind not in ('invariant', 'border') or operation._kind != 'winner':\n",),
  ("    if kind in ('map_loops', 'rtree_loops', 'other_loops', 'alias_loops') and operation._kind "
   "== 'generated_receipt':\n",
   '        caller = frame.f_back\n',
   '        owner = operation._owner_frame\n',
   '        namespace = owner.f_globals\n',
   "        if (kind not in ('map_loops', 'rtree_loops', 'other_loops', 'alias_loops')\n",
   '                or frame.f_globals is not namespace or caller is None\n',
   '                or caller.f_globals is not namespace\n',
   '                or caller.f_code is not '
   "_live_function_code(namespace.get('_receipt_reviewed_nonempty_loops'))\n",
   '                or caller.f_back is not owner):\n',
   '            return None\n',
   '        for local in (frame.f_locals, caller.f_locals):\n',
   "            if (local.get('_operation') is not operation\n",
   "                    or _absolute_root_text(local.get('root')) != operation._root\n",
   "                    or tuple(_absolute_root_text(path) for path in local.get('include_roots', "
   '()))\n',
   '                    != operation._include_roots):\n',
   '                return None\n',
   '        return caller\n',
   "    if kind not in ('invariant', 'border') or operation._kind not in ('winner', 'runtime', "
   "'sampled'):\n")),
 (2005,
  2006,
  ("                and operation._kind == 'winner', 'invalid private operation wrapper')\n",),
  ("                and operation._kind in ('winner', 'runtime', 'sampled'), 'invalid private "
   "operation wrapper')\n",)),
 (2017,
  2018,
  ("        require(kind in ('invariant', 'winner', 'border', 'map_loops', 'rtree_loops'),\n",),
  ("        require(kind in ('invariant', 'winner', 'border', 'runtime', 'sampled', 'seed', "
   "'map_loops', 'rtree_loops'),\n",)),
 (2110,
  2111,
  ('def _operation_record(operation, root, *, exact=False, include_roots=(), '
   'expected_lane_raw=None):\n',),
  ('def _operation_record(operation, root, *, exact=False, include_roots=None, '
   'expected_lane_raw=None):\n',)),
 (2112,
  2113,
  ('        require(type(operation) is _InvariantInputs and include_roots == (),\n',),
  ('        require(type(operation) is _InvariantInputs,\n',)),
 (2114,
  2119,
  (),
  ('        if include_roots is None:\n',
   '            include_roots = tuple(Path(path) for path in operation._include_roots)\n',
   '        _operation_include_context(operation, root, include_roots)\n',
   '        require(_absolute_root_text(root) == operation._root,\n',
   "                'generated input cannot supply source authority')\n")),
 (2154,
  2156,
  ('                and caller.f_code in (_live_function_code(_invariant_operation), '
   '_live_function_code(_operation_enter))\n',),
  ('                and caller.f_code in (_live_function_code(_invariant_operation), '
   '_live_function_code(_operation_enter),\n',
   '                                      _live_function_code(_receipt_operation_enter))\n')),
 (2165,
  2251,
  (),
  ('        self._checker_receipt = False\n',
   '        self._receipt_seed = None\n',
   '        self._receipt_seed_token = None\n',
   '        self._receipt_source_digests = types.MappingProxyType({})\n',
   '        self._receipt_stage_digests = types.MappingProxyType({})\n',
   '        self._receipt_production = types.MappingProxyType({})\n',
   '        self._receipt_observations = []\n',
   '        self._receipt_discoveries = []\n',
   '        self._include_raw = types.MappingProxyType({})\n',
   '        self._include_entries = ()\n',
   '        self._include_production = frozenset()\n',
   '        self._proof_bindings = types.MappingProxyType({})\n',
   "        if kind == 'generated_receipt':\n",
   "            build = owner_frame.f_locals['build']\n",
   "            seed = owner_frame.f_locals['_receipt_seed']\n",
   '            require(type(seed) is dict and _absolute_root_text(build) != self._root,\n',
   "                    'invalid generated receipt coordinates')\n",
   '            self._include_roots = (_absolute_root_text(build),)\n',
   "            self._receipt_seed = _canonical(seed).encode('utf-8')\n",
   '            self._receipt_seed_token = seed\n',
   "            self._receipt_source_digests = types.MappingProxyType(dict(seed['root_inputs']))\n",
   '            self._receipt_stage_digests = types.MappingProxyType(\n',
   "                {path: item['instrumented'] for path, item in seed['inputs'].items()})\n",
   '            production = {}\n',
   '            for location, digests in ((self._root, self._receipt_source_digests),\n',
   '                                      (self._include_roots[0], '
   'self._receipt_stage_digests)):\n',
   '                production[location] = self._receipt_production_paths(location)\n',
   '                require(production[location] <= digests.keys(),\n',
   "                        'production census differs from producer coordinates')\n",
   '            self._receipt_production = types.MappingProxyType(production)\n',
   '\n',
   '    def _check_context(self, root):\n',
   "        if self._kind != 'generated_receipt':\n",
   '            return super()._check_context(root)\n',
   '        frame = self._owner_frame\n',
   '        require(frame is not None and str(Path.cwd()) == self._cwd\n',
   '                and _absolute_root_text(root) in (self._root, *self._include_roots)\n',
   "                and _absolute_root_text(frame.f_locals.get('root')) == self._root\n",
   "                and (_absolute_root_text(frame.f_locals.get('build')), ) == "
   'self._include_roots\n',
   "                and frame.f_locals.get('_receipt_seed') is self._receipt_seed_token,\n",
   "                'generated source/build context changed')\n",
   '\n',
   '    def _receipt_production_paths(self, location):\n',
   '        build = Path(self._include_roots[0])\n',
   '        return frozenset(path.relative_to(location).as_posix()\n',
   '            for path in guard.production_mojo_paths(Path(location))\n',
   '            if location != self._root or not path.absolute().is_relative_to(build))\n',
   '\n',
   '    def _receipt_inputs_check(self):\n',
   '        self._check_owner(Path(self._root))\n',
   "        require(self._kind == 'generated_receipt' and type(self._receipt_seed) is bytes,\n",
   "                'invalid generated input boundary')\n",
   "        require(_canonical(self._receipt_seed_token).encode('utf-8') == self._receipt_seed,\n",
   "                'generated receipt seed changed after consumption')\n",
   '        for location, expected in self._receipt_production.items():\n',
   '            require(self._receipt_production_paths(location) == expected,\n',
   "                'generated producer production census changed')\n",
   '        seed = json.loads(self._receipt_seed, object_pairs_hook=source.unique_keys)\n',
   "        self._owner_frame.f_globals['check_capture_inputs'](\n",
   "            {'receipt': seed}, Path(self._root), Path(self._include_roots[0]))\n",
   '\n',
   '    def _receipt_bindings(self, root, include_roots):\n',
   '        try:\n',
   '            _operation_include_context(self, root, include_roots)\n',
   "            require(self._kind == 'generated_receipt' and _absolute_root_text(root) == "
   'self._root,\n',
   "                    'invalid generated proof-binding request')\n",
   '            self._admit(root, exact=True)\n',
   '            # This authenticates live descriptor tables without replaying the\n',
   '            # complete source graph. Rows still read their actual physical bytes.\n',
   '            typed_boundary.verify_authority()\n',
   '            return dict(self._proof_bindings)\n',
   '        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, '
   'AttributeError) as error:\n',
   '            _operation_fail(self, error)\n',
   '\n',
   '    def _clear_receipt(self):\n',
   '        self._receipt_seed = None\n',
   '        self._receipt_seed_token = None\n',
   '        self._receipt_source_digests = types.MappingProxyType({})\n',
   '        self._receipt_stage_digests = types.MappingProxyType({})\n',
   '        self._receipt_production = types.MappingProxyType({})\n',
   '        self._receipt_observations.clear()\n',
   '        self._receipt_discoveries.clear()\n',
   '        self._include_raw = types.MappingProxyType({})\n',
   '        self._include_entries = ()\n',
   '        self._include_production = frozenset()\n',
   '        self._proof_bindings = types.MappingProxyType({})\n')),
 (2255, 2256, (), ('        self._clear_receipt()\n',)),
 (2264, 2265, (), ('        self._scaled_resolver_paths = frozenset()\n',)),
 (2268,
  2287,
  (),
  ('        self._checker_receipt = False\n',
   '\n',
   '    def _bind_checker_receipt(self, root, executing):\n',
   '        """Retain only a supplied checker image consumed by this operation."""\n',
   '        try:\n',
   '            self._check_owner(root)\n',
   '            caller = sys._getframe(1)\n',
   '            require(caller.f_globals is globals()\n',
   '                    and caller.f_code is _live_function_code(proof_bindings)\n',
   "                    and caller.f_locals.get('_operation') is self\n",
   '                    and type(executing) is dict\n',
   '                    and type(self._checker_receipt) is bool\n',
   "                    and self._state == 'active' and not self._capturing,\n",
   "                    'checker receipt requires its active proof-binding owner')\n",
   '            require(executing == dict(self._executing),\n',
   "                    'checker receipt differs from captured executing image')\n",
   '            self._checker_receipt = True\n',
   '        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, '
   'AttributeError) as error:\n',
   '            _operation_fail(self, error)\n')),
 (2333,
  2335,
  ('                 entries, resolver_paths, executing):\n',),
  ('                 entries, resolver_paths, executing, *, receipt_bindings=None,\n',
   '                 include_images=()):\n')),
 (2352,
  2356,
  (),
  ('        require(not self._scaled_resolver_paths or\n',
   '                (self._scaled_resolver_paths == scaled_float32.NATIVE_CLOSURE\n',
   '                 and self._scaled_resolver_paths <= image.keys()),\n',
   "                'pending scaled native context differs from captured image')\n")),
 (2366,
  2395,
  (),
  ("        if self._kind == 'generated_receipt':\n",
   '            require(type(receipt_bindings) is dict and len(include_images) == 1,\n',
   "                    'missing generated binding image')\n",
   '            location, stage_image, stage_args = include_images[0]\n',
   '            require(_absolute_root_text(location) == self._include_roots[0],\n',
   "                    'captured generated root changed')\n",
   '            seed = json.loads(self._receipt_seed, object_pairs_hook=source.unique_keys)\n',
   "            require(all(seed['root_inputs'][path] == sha(raw) for path, raw in image.items()\n",
   "                        if path in seed['root_inputs']),\n",
   "                    'source differs from pre-admission producer observation')\n",
   "            require(all(seed['inputs'].get(path, {}).get('instrumented') == sha(raw)\n",
   '                        for path, raw in stage_image.items()),\n',
   "                    'include differs from pre-admission producer observation')\n",
   '            require(all(digest == (executing[path] if path in executing else\n',
   '                        sha(authority_raw if path == MIGRATION else image[path]))\n',
   '                        for path, digest in receipt_bindings.items()),\n',
   "                    'generated binding map differs from captured physical domains')\n",
   '            self._include_raw = types.MappingProxyType(dict(stage_image))\n',
   "            self._include_entries = tuple(_sibling('affected').entry_directories(\n",
   '                {path: _physical_text(raw) for path, raw in stage_image.items()}))\n',
   '            require(stage_args == _render_lookup_args(resolver_paths, '
   'self._include_entries),\n',
   "                    'generated resolver entry context changed')\n",
   '            self._include_production = frozenset(path.relative_to(location).as_posix()\n',
   '                for path in guard.production_mojo_paths(Path(location)))\n',
   '            self._proof_bindings = types.MappingProxyType(dict(receipt_bindings))\n',
   '            self._checker_receipt = True\n',
   '        else:\n',
   '            require(receipt_bindings is None and include_images == (),\n',
   "                    'non-generated owner received include admission')\n")),
 (2396,
  2402,
  (),
  ('        for location, path, value, mode in self._receipt_observations:\n',
   '            self._match(Path(location), path, value, mode)\n',
   '        self._receipt_observations.clear()\n',
   '        for location, paths, kind in self._receipt_discoveries:\n',
   '            self._discovery(Path(location), paths, kind)\n',
   '        self._receipt_discoveries.clear()\n')),
 (2414,
  2424,
  (),
  ("            if self._kind == 'generated_receipt' and self._state == 'pending':\n",
   '                location = _absolute_root_text(root)\n',
   '                digests = (self._receipt_source_digests if location == self._root\n',
   '                           else self._receipt_stage_digests)\n',
   "                expected = (self._receipt_production[location] if kind == 'production'\n",
   '                            else frozenset(path for path in digests if '
   "path.endswith('.mojo')))\n",
   '                require(frozenset(paths) == expected,\n',
   "                        'consumed census differs from producer boundary: ' + kind)\n",
   '                self._receipt_discoveries.append((location, frozenset(paths), kind))\n',
   '                return\n')),
 (2427,
  2430,
  ("                expected = self._production if kind == 'production' else self._known\n",),
  ("                generated = self._kind == 'generated_receipt' and _absolute_root_text(root) != "
   'self._root\n',
   "                expected = ((self._include_production if kind == 'production' else "
   'frozenset(self._include_raw))\n',
   "                            if generated else (self._production if kind == 'production' else "
   'self._known))\n')),
 (2435,
  2438,
  ('        require(path in self._raw or path == MIGRATION,\n',),
  ("        generated = self._kind == 'generated_receipt' and _absolute_root_text(root) != "
   'self._root\n',
   '        image = self._include_raw if generated else self._raw\n',
   '        require(path in image or (not generated and path == MIGRATION),\n')),
 (2440,
  2441,
  ('        raw = self._record_raw if path == MIGRATION else self._raw[path]\n',),
  ('        raw = self._record_raw if not generated and path == MIGRATION else image[path]\n',)),
 (2466,
  2485,
  ("            if self._state == 'pending':\n",),
  ("            if self._kind == 'generated_receipt' and self._state == 'pending':\n",
   '                # Join reads even when no current theorem will trigger capture.\n',
   '                # A consumed transient value cannot disappear before lazy admission.\n',
   '                generated = _absolute_root_text(root) != self._root\n',
   '                digests = self._receipt_stage_digests if generated else '
   'self._receipt_source_digests\n',
   '                digest = digests.get(path)\n',
   '                if digest is not None:\n',
   "                    raw = value if mode == 'bytes' else _regular(root, path).read_bytes()\n",
   '                    require(type(raw) is bytes and sha(raw) == digest,\n',
   "                            'consumed input differs from generation boundary: ' + path)\n",
   "                    if mode != 'bytes':\n",
   '                        expected = _operation_text(raw, mode)\n',
   '                        require((source.token_sha256(value) == '
   'source.token_sha256(expected))\n',
   "                                if mode.startswith('supplied_') else value == expected,\n",
   "                                'consumed text differs from generation boundary: ' + path)\n",
   '                else:\n',
   "                    require(not generated, 'unknown generated input observation: ' + path)\n",
   '                self._receipt_observations.append((_absolute_root_text(root), path, value, '
   'mode))\n',
   "            elif self._state == 'pending':\n")),
 (2502,
  2511,
  ('                    verify(root, _expected_lane_raw=expected_lane_raw, _capture=self)\n',),
  ("                    if self._kind == 'generated_receipt':\n",
   '                        require(_absolute_root_text(root) == self._root,\n',
   "                                'generated bytes cannot supply source admission')\n",
   '                        self._receipt_inputs_check()\n',
   '                    verify(root, _expected_lane_raw=expected_lane_raw, _capture=self,\n',
   '                           include_roots=tuple(Path(path) for path in self._include_roots))\n',
   "                    if self._kind == 'generated_receipt':\n",
   '                        require(executing_checker_bindings(root) == dict(self._executing),\n',
   "                                'generated receipt checker differs from executing image')\n")),
 (2519,
  2522,
  ('                    require(sha(self.raw(self._owner, root, path)) == AFTER_SHA256[path],\n',),
  ('                    raw = self.raw(self._owner, root, path)\n',
   '                    require(sha(raw) == AFTER_SHA256[path] or (typed_boundary.is_current(path, '
   'raw)\n',
   "                            and typed_boundary.edge(path)['before_sha256'] == "
   'AFTER_SHA256[path]),\n')),
 (2532,
  2568,
  (),
  ('    def _receipt_finish_inputs(self, root):\n',
   '        """One terminal physical sweep, never another source semantic replay."""\n',
   "        require(_absolute_root_text(root) == self._root, 'foreign generated finalizer root')\n",
   '        for path in self._raw:\n',
   '            self.observe_bytes(self._owner, root, path)\n',
   "        require({p.as_posix() for p in _sibling('cache_key').input_paths(root)\n",
   "                 if p.suffix == '.mojo'} == self._known,\n",
   "                'source path inventory changed during generated verification')\n",
   '        require({path.relative_to(root).as_posix() for path in '
   'guard.production_mojo_paths(Path(root))}\n',
   "                == self._production, 'production path inventory changed during generated "
   "verification')\n",
   '        require(_regular(root, MIGRATION).read_bytes() == self._record_raw,\n',
   "                'record changed during generated verification')\n",
   '        typed_boundary.verify_authority()\n',
   '        location = Path(self._include_roots[0])\n',
   '        _helper_entry_census_finish(location, self._include_raw, _operation=self)\n',
   '        require({path.relative_to(location).as_posix() for path in '
   'guard.production_mojo_paths(location)}\n',
   "                == self._include_production, 'generated production path census changed')\n",
   '        require(resolver_unshadowed(root, self._resolver_paths,\n',
   '                    **_render_lookup_args(self._resolver_paths, self._entries))\n',
   '                and resolver_unshadowed(location, self._resolver_paths | {path + '
   "'.cov-origin'\n",
   "                    for path in self._resolver_paths if path.endswith('.mojo')},\n",
   '                    **_render_lookup_args(self._resolver_paths, self._include_entries)),\n',
   "                'generated resolver surface changed during verification')\n",
   '        if self._scaled_resolver_paths:\n',
   '            require(self._scaled_resolver_paths == scaled_float32.NATIVE_CLOSURE\n',
   '                    and _scaled_known_paths(root, _operation=self) == self._known,\n',
   "                    'generated scaled native context changed')\n",
   '            scaled_include_paths = self._scaled_resolver_paths | {\n',
   "                path + '.cov-origin' for path in self._scaled_resolver_paths}\n",
   '            require(resolver_unshadowed(root, self._scaled_resolver_paths,\n',
   '                                       **_scaled_lookup_args())\n',
   '                    and resolver_unshadowed(location, scaled_include_paths,\n',
   '                                            **_scaled_lookup_args()),\n',
   "                    'generated scaled native resolver changed during finalization')\n",
   '        self._receipt_inputs_check()\n',
   '\n')),
 (2573,
  2621,
  ('                    _CacheInputs.checkpoint(self, self._owner, root)\n',
   '                elif self._resolver_paths:\n'),
  ("                    if self._kind == 'generated_receipt':\n",
   '                        self._receipt_finish_inputs(root)\n',
   '                    else:\n',
   '                        _CacheInputs.checkpoint(self, self._owner, root)\n',
   '                    require(type(self._checker_receipt) is bool,\n',
   "                            'invalid consumed checker receipt state')\n",
   '                    if self._checker_receipt:\n',
   '                        require(executing_checker_bindings(root) == dict(self._executing),\n',
   "                                'consumed receipt checker changed during owned "
   "verification')\n",
   "                elif self._kind == 'generated_receipt':\n",
   '                    # No current theorem is needed, but every consumed read and\n',
   '                    # census still belongs to this producer observation image.\n',
   '                    for location, path, value, mode in tuple(self._receipt_observations):\n',
   '                        raw = _regular(Path(location), path).read_bytes()\n',
   "                        expected = raw if mode == 'bytes' else _operation_text(raw, mode)\n",
   '                        require((source.token_sha256(value) == '
   'source.token_sha256(expected))\n',
   "                                if mode.startswith('supplied_') else value == expected,\n",
   "                                'pending receipt input changed: ' + path)\n",
   '                    for location, paths, kind in tuple(self._receipt_discoveries):\n',
   '                        digests = (self._receipt_source_digests if location == self._root\n',
   '                                   else self._receipt_stage_digests)\n',
   '                        expected = (self._receipt_production[location] if kind == '
   "'production'\n",
   '                                    else frozenset(path for path in digests if '
   "path.endswith('.mojo')))\n",
   "                        require(paths == expected, 'pending receipt census changed')\n",
   '                    location = self._include_roots[0]\n',
   '                    stage_image = {path: raw for observed_root, path, raw, mode in\n',
   '                        self._receipt_observations if observed_root == location\n',
   "                        and mode == 'bytes' and path.endswith('.mojo')}\n",
   "                    stage_entries = tuple(_sibling('affected').entry_directories(\n",
   '                        {path: _physical_text(raw) for path, raw in stage_image.items()}))\n',
   '                    stage_args = _render_lookup_args(self._resolver_paths, stage_entries)\n',
   '                    require(not stage_args or set(stage_image) == {\n',
   '                        path for path in self._receipt_stage_digests if '
   "path.endswith('.mojo')},\n",
   "                        'pending include entry context lacks complete observations')\n",
   "                    include_paths = self._resolver_paths | {path + '.cov-origin'\n",
   "                        for path in self._resolver_paths if path.endswith('.mojo')}\n",
   '                    require(resolver_unshadowed(Path(location), include_paths, '
   '**stage_args),\n',
   "                            'pending generated resolver surface changed')\n",
   '                    if self._scaled_resolver_paths:\n',
   '                        require(self._scaled_resolver_paths == '
   'scaled_float32.NATIVE_CLOSURE,\n',
   "                                'pending generated scaled context changed')\n",
   '                        scaled_paths = self._scaled_resolver_paths | {\n',
   "                            path + '.cov-origin' for path in self._scaled_resolver_paths}\n",
   '                        require(resolver_unshadowed(Path(location), scaled_paths,\n',
   '                                                    **_scaled_lookup_args()),\n',
   "                                'pending generated scaled resolver surface changed')\n",
   '                    self._receipt_inputs_check()\n',
   "                if self._state == 'pending' and (self._resolver_paths or "
   'self._scaled_resolver_paths):\n')),
 (2626,
  2629,
  (),
  ('                                or (self._scaled_resolver_paths and\n',
   '                                    (path in self._scaled_resolver_paths\n',
   '                                     or path == scaled_float32.LEAF or path in '
   'scaled_float32.TESTS))\n')),
 (2643,
  2654,
  (),
  ('                    if self._scaled_resolver_paths:\n',
   '                        require(self._scaled_resolver_paths == '
   'scaled_float32.NATIVE_CLOSURE,\n',
   "                                'historical scaled native context changed')\n",
   '                        current_known = _scaled_known_paths(root, _operation=self)\n',
   '                        for paths, kind in self._discoveries:\n',
   "                            if kind == 'known':\n",
   '                                require(paths == current_known,\n',
   "                                        'scaled source path census changed during historical "
   "operation')\n",
   '                        require(resolver_unshadowed(root, self._scaled_resolver_paths,\n',
   '                                                    **_scaled_lookup_args()),\n',
   "                                'scaled native resolver changed during historical "
   "operation')\n")),
 (2665, 2666, (), ('        self._clear_receipt()\n',)),
 (2673, 2674, (), ('        self._scaled_resolver_paths = frozenset()\n',)),
 (2679, 2680, (), ('        self._checker_receipt = False\n',)),
 (2702, 2703, (), ('        self._scaled_resolver_paths = operation._scaled_resolver_paths\n',)),
 (2766, 2767, (), ('        self._scaled_resolver_paths = frozenset()\n',)),
 (2785,
  2785,
  ('        require(digest == AFTER_TOKEN_SHA256[path],\n',
   "                'unreviewed supplied successor source: ' + path)\n"),
  ()),
 (2789,
  2791,
  (),
  ('        require(digest == AFTER_TOKEN_SHA256[path] or typed_boundary.is_current(path, raw),\n',
   "                'unreviewed supplied successor source: ' + path)\n")),
 (2852, 2853, (), ('    typed_fixtures = {}\n',)),
 (2854,
  2864,
  ("        require(sha(raw) == expected[path], 'shared-helper fixture changed: ' + path)\n",),
  ('        historical = raw\n',
   '        if path in tests and typed_boundary.is_current(path, raw):\n',
   '            # Arithmetic capture has no typed fixture edge. Supplemental native\n',
   '            # fixtures use the complete current graph before exact provenance;\n',
   '            # source/provider extraction identities remain unchanged.\n',
   "            require(_snapshots is None, 'typed fixture entered arithmetic helper capture')\n",
   "            historical = reviewed_typed_text(root, path, raw.decode('utf-8'),\n",
   '                _operation=_operation, _inputs=_inputs, '
   "_input_owner=_input_owner).encode('utf-8')\n",
   '            typed_fixtures[path] = raw\n',
   "        require(sha(historical) == expected[path], 'shared-helper fixture changed: ' + "
   'path)\n')),
 (2868,
  2872,
  (),
  ('    if typed_fixtures and _inputs is None and _operation is None:\n',
   '        # Owned views retain their complete final sweep. A standalone typed\n',
   '        # fixture must join the same physical image at the terminal root gate.\n',
   '        verify(root, exact=True, _expected_sources=typed_fixtures)\n')),
 (2874,
  2875,
  ('    return {**expected, **{path: sha(raw) for path, raw in sources.items()}}\n',),
  ('    return {path: sha(raw) for path, raw in {**sources, **bound}.items()}\n',)),
 (2882,
  2885,
  (),
  ('        include_roots = tuple(include_roots)\n',
   '        if _operation is not None:\n',
   '            _operation_include_context(_operation, root, include_roots)\n')),
 (2898, 2899, (), ('        include_images = []\n',)),
 (2902,
  2904,
  ('                require(include_roots == () or (_operation is None and _inputs is None),\n',),
  ('                require(include_roots == () or (_inputs is None and (_operation is None\n',
   "                        or _operation._kind == 'generated_receipt')),\n")),
 (2909,
  2916,
  (),
  ('                for location in include_roots:\n',
   '                    source_image = (fresh_image if fresh_image is not None else\n',
   '                        {path: _operation._raw[path] for path in _operation._known})\n',
   '                    stage_entries, stage_image = _include_entry_context(\n',
   '                        location, source_image, _operation=_operation)\n',
   '                    include_images.append((location, stage_image,\n',
   '                        _render_lookup_args(resolver_paths, stage_entries)))\n')),
 (2917,
  2920,
  ("                    resolver_unshadowed(location, resolver_paths | {path + '.cov-origin' for "
   'path in resolver_paths})\n',
   "                    for location in include_roots), 'shared-helper resolver surface "
   "changed')\n"),
  ("                    resolver_unshadowed(location, resolver_paths | {path + '.cov-origin' for "
   'path in resolver_paths},\n',
   '                        **(include_images[index][2] if include_images else {}))\n',
   "                    for index, location in enumerate(include_roots)), 'shared-helper resolver "
   "surface changed')\n")),
 (2931,
  2935,
  ('                            {path for path, value, mode in owner._observations})\n',),
  ('                    {path for location, path, value, mode in owner._receipt_observations\n',
   '                     if location == owner._root}\n',
   "                    if type(owner) is _InvariantInputs and owner._kind == 'generated_receipt' "
   'else\n',
   '                    {path for path, value, mode in owner._observations})\n')),
 (2947,
  2949,
  ('            # Rendering callers have no include roots. Keep the historical\n',
   '            # conservative rule for explicitly supplied stage contexts.\n'),
  ('            for location, image, _ in include_images:\n',
   '                _helper_entry_census_finish(location, image, _operation=_operation)\n')),
 (2950,
  2953,
  ("                    resolver_unshadowed(location, resolver_paths | {path + '.cov-origin' for "
   'path in resolver_paths})\n',
   "                    for location in include_roots), 'shared-helper final resolver surface "
   "changed')\n"),
  ("                    resolver_unshadowed(location, resolver_paths | {path + '.cov-origin' for "
   'path in resolver_paths},\n',
   '                        **include_images[index][2])\n',
   "                    for index, location in enumerate(include_roots)), 'shared-helper final "
   "resolver surface changed')\n")),
 (2970,
  3135,
  (),
  ('def _scaled_known_paths(root, *, _operation=None):\n',
   '    """Validate every discovered path before a set can hide a typed alias."""\n',
   '    known = set()\n',
   "    for path in _sibling('cache_key').input_paths(root):\n",
   "        if path.suffix != '.mojo':\n",
   '            continue\n',
   '        name = path.as_posix()\n',
   '        require(type(name) is str and _canonical_relative_text(name),\n',
   "                'invalid scaled source path census item')\n",
   '        known.add(name)\n',
   '    _operation_known_paths(root, known, _operation=_operation)\n',
   '    return known\n',
   '\n',
   '\n',
   'def _scaled_lookup_args():\n',
   '    """Only the pinned native witnesses establish this supplemental context."""\n',
   "    return {'math_entries': frozenset(('.', *(str(Path(path).parent).casefold()\n",
   '        for path in scaled_float32.NATIVE_TESTS)))}\n',
   '\n',
   '\n',
   'def _scaled_float32_bindings(root, *, paths=None, _snapshots=None, _inputs=None,\n',
   '                             _input_owner=None, _operation=None, _context=None):\n',
   '    """Bind the exact math edge and its own native witness, not caller roots."""\n',
   '    _operation_check(_operation, root)\n',
   "    require((_inputs is None) == (_input_owner is None), 'incomplete scaled input "
   "ownership')\n",
   '    if _inputs is not None:\n',
   "        require(type(_inputs) in (_CacheInputs, _BorrowedCacheInputs), 'invalid scaled input "
   "view')\n",
   '        _inputs._check(_input_owner, root)\n',
   '        require(_operation is None or (type(_inputs) is _BorrowedCacheInputs\n',
   "                and _operation is _inputs._operation), 'unjoined scaled input and operation "
   "owners')\n",
   '    observed = {}\n',
   '\n',
   '    def observe(path):\n',
   '        raw = (_observe_bytes(root, path, _regular(root, path).read_bytes(), '
   '_operation=_operation)\n',
   '               if _inputs is None else _inputs.raw(_input_owner, root, path))\n',
   "        require(type(raw) is bytes, 'scaled input is not physical bytes: ' + path)\n",
   "        require(observed.setdefault(path, raw) == raw, 'scaled input changed after "
   "consumption: ' + path)\n",
   '        if _snapshots is not None:\n',
   "            require(_snapshots.setdefault(path, raw) == raw, 'scaled captured input changed: ' "
   '+ path)\n',
   '        return raw\n',
   '\n',
   '    selected = scaled_float32.SOURCE_PATHS if paths is None else paths\n',
   '    require(type(selected) is tuple and selected == scaled_float32.SOURCE_PATHS,\n',
   "            'invalid scaled input scope')\n",
   '    sources = {name: observe(name) for name in selected}\n',
   "    active = scaled_float32.verify_sources({name: raw.decode('utf-8') for name, raw in "
   'sources.items()})\n',
   '    if not active:\n',
   '        return {}\n',
   '    expected = {scaled_float32.LEAF: DEPENDENCY_TOOL_SHA256[scaled_float32.LEAF],\n',
   '                **scaled_float32.PACKAGE_INPUTS, **scaled_float32.PROVIDER_INPUTS,\n',
   '                **scaled_float32.TESTS}\n',
   '    for name, digest in expected.items():\n',
   "        require(sha(observe(name)) == digest, 'scaled correctness input changed: ' + name)\n",
   '    # Source identity and its actual main declaration jointly establish the\n',
   '    # fixed witness entry context. No production entry census is inferred.\n',
   "    affected = _sibling('affected')\n",
   '    entries = tuple(affected.entry_directories({name: _physical_text(observe(name))\n',
   '                                              for name in scaled_float32.NATIVE_TESTS}))\n',
   '    require(entries == tuple(sorted({str(Path(name).parent)\n',
   '                                     for name in scaled_float32.NATIVE_TESTS})),\n',
   "            'scaled native entry context changed')\n",
   '    known = _scaled_known_paths(root, _operation=_operation)\n',
   '    if _inputs is not None:\n',
   "        require(known == _inputs._known, 'scaled captured source path census changed')\n",
   '    found, pending = set(), list(scaled_float32.NATIVE_TESTS)\n',
   '    while pending:\n',
   '        name = pending.pop()\n',
   '        if name in found:\n',
   '            continue\n',
   "        require(name in known, 'scaled native dependency missing: ' + name)\n",
   '        found.add(name)\n',
   '        for imported in affected.imported_names(_physical_text(observe(name))):\n',
   '            pending.extend(affected.resolve(imported, name, known, entries=entries))\n',
   "    require(found == scaled_float32.NATIVE_CLOSURE, 'scaled native import closure changed')\n",
   '    for name, raw in tuple(observed.items()):\n',
   "        require(observe(name) == raw, 'scaled input changed during admission: ' + name)\n",
   '    final_known = _scaled_known_paths(root, _operation=_operation)\n',
   "    require(final_known == known, 'scaled source path census changed during admission')\n",
   '    if _context is not None:\n',
   "        require(type(_context) is dict and not _context, 'invalid scaled source context "
   "output')\n",
   "        _context['known'] = frozenset(known)\n",
   '    return {name: sha(raw) for name, raw in observed.items()}\n',
   '\n',
   '\n',
   'def scaled_float32_proof_bindings(root, *, paths=None, include_roots=(), _inputs=None,\n',
   '                                   _input_owner=None, _operation=None):\n',
   '    """Admit one source substitution and its fixed native context, never PASS."""\n',
   '    failure_operation = _operation\n',
   '    try:\n',
   '        _operation_check(_operation, root)\n',
   "        require((_inputs is None) == (_input_owner is None), 'incomplete scaled input "
   "ownership')\n",
   '        if _inputs is not None:\n',
   "            require(type(_inputs) in (_CacheInputs, _BorrowedCacheInputs), 'invalid scaled "
   "input view')\n",
   '            _inputs._check(_input_owner, root)\n',
   '            if type(_inputs) is _BorrowedCacheInputs:\n',
   '                # Only a validated real lease may identify its failure owner.\n',
   '                failure_operation = _inputs._operation\n',
   '            require(_operation is None or (type(_inputs) is _BorrowedCacheInputs\n',
   "                    and _operation is _inputs._operation), 'unjoined scaled input and "
   "operation owners')\n",
   '        include_roots = tuple(include_roots)\n',
   '        if _operation is not None:\n',
   '            _operation_include_context(_operation, root, include_roots)\n',
   '        require(include_roots == () or (_inputs is None and (_operation is None\n',
   "                or _operation._kind == 'generated_receipt')),\n",
   "                'unowned scaled include roots')\n",
   '        standalone = _inputs is None and (_operation is None or _operation._state != '
   "'active')\n",
   '        executing = (executing_checker_bindings() if standalone else\n',
   '                     (_inputs._executing if _inputs is not None else _operation._executing))\n',
   '        context = {}\n',
   '        result = _scaled_float32_bindings(root, paths=paths, _inputs=_inputs,\n',
   '            _input_owner=_input_owner, _operation=_operation, _context=context)\n',
   '        if result:\n',
   '            require(result[scaled_float32.LEAF] == executing[scaled_float32.LEAF],\n',
   "                    'scaled receipt lacks executing leaf')\n",
   "            resolver_paths = {name for name in result if name.endswith('.mojo')}\n",
   '            require(resolver_paths == scaled_float32.NATIVE_CLOSURE,\n',
   "                    'scaled resolver scope differs from native closure')\n",
   "            include_paths = resolver_paths | {name + '.cov-origin' for name in "
   'resolver_paths}\n',
   '            require(resolver_unshadowed(root, resolver_paths, **_scaled_lookup_args()) and '
   'all(\n',
   '                resolver_unshadowed(location, include_paths, **_scaled_lookup_args())\n',
   "                for location in include_roots), 'scaled resolver surface changed')\n",
   '            owners = (() if _inputs is None else (_inputs,))\n',
   '            if _operation is not None:\n',
   '                owners += (_operation,)\n',
   '            if type(_inputs) is _BorrowedCacheInputs:\n',
   '                owners += (_inputs._operation,)\n',
   '            for owner in owners:\n',
   "                observed = (owner._raw.keys() if owner._state == 'active' else\n",
   '                    {path for location, path, value, mode in owner._receipt_observations\n',
   '                     if location == owner._root}\n',
   "                    if type(owner) is _InvariantInputs and owner._kind == 'generated_receipt' "
   'else\n',
   '                    {name for name, value, mode in owner._observations})\n',
   "                require(result.keys() <= observed, 'scaled inputs were not observed by their "
   "owner')\n",
   '                # This native-only context must never narrow or replace the\n',
   "                # owner's existing production/helper resolver obligations.\n",
   '                owner._scaled_resolver_paths = frozenset(resolver_paths)\n',
   "                if owner._state == 'pending':\n",
   '                    require(not owner._executing or dict(owner._executing) == executing,\n',
   "                            'pending scaled checker image changed')\n",
   '                    owner._executing = types.MappingProxyType(dict(executing))\n',
   '            for name, expected in result.items():\n',
   '                raw = (_observe_bytes(root, name, _regular(root, name).read_bytes(), '
   '_operation=_operation)\n',
   '                       if _inputs is None else _inputs.raw(_input_owner, root, name))\n',
   '                require(type(raw) is bytes and sha(raw) == expected,\n',
   "                        'scaled input changed before receipt: ' + name)\n",
   '            require(resolver_unshadowed(root, resolver_paths, **_scaled_lookup_args()) and '
   'all(\n',
   '                resolver_unshadowed(location, include_paths, **_scaled_lookup_args())\n',
   "                for location in include_roots), 'scaled final resolver surface changed')\n",
   '            final_known = _scaled_known_paths(root, _operation=_operation)\n',
   "            require(final_known == context['known'], 'scaled source path census changed before "
   "receipt')\n",
   '        if standalone:\n',
   "            require(executing_checker_bindings() == executing, 'scaled checker changed during "
   "admission')\n",
   '        return result\n',
   '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, '
   'AttributeError) as error:\n',
   '        _operation_fail(failure_operation, error)\n',
   '\n',
   '\n',
   'def scaled_float32_edges(root, *, paths=None, _inputs=None, _input_owner=None, '
   '_operation=None):\n',
   '    """Return only the live math edge admitted through the same physical owner."""\n',
   '    bindings = scaled_float32_proof_bindings(root, paths=paths, _inputs=_inputs,\n',
   '        _input_owner=_input_owner, _operation=_operation)\n',
   '    return scaled_float32.edges(tuple(name for name in scaled_float32.SOURCE_PATHS\n',
   '        if bindings.get(name) == scaled_float32.AFTER_SHA256[name]))\n',
   '\n',
   '\n')),
 (3137, 3137, ('    runtime_view.steps(root, _operation=_operation)\n',), ()),
 (3142, 3143, (), ('    runtime_view.checked_steps(record)\n',)),
 (3151,
  3153,
  ("        require(sha(value) == expected, 'runtime view bound input changed: ' + path)\n",),
  ("        require(sha(_historical_typed_text(path, value.decode('utf-8'))) == expected,\n",
   "                'runtime view bound input changed: ' + path)\n")),
 (3156, 3157, ('        result[path] = expected\n',), ('        result[path] = sha(value)\n',)),
 (3172,
  3175,
  ('    if sha(raw) == station.BEFORE_SHA256:\n',
   '        require(source.token_sha256(_physical_text(raw)) == station.BEFORE_TOKEN_SHA256,\n'),
  ("    historical = _historical_typed_text(station.MODULE, raw.decode('utf-8'))\n",
   '    if sha(historical) == station.BEFORE_SHA256:\n',
   '        require(source.token_sha256(historical) == station.BEFORE_TOKEN_SHA256,\n')),
 (3177,
  3178,
  ('    require(sha(raw) in (station.AFTER_SHA256, deviation.AFTER_SHA256),\n',),
  ('    require(sha(historical) in (station.AFTER_SHA256, deviation.AFTER_SHA256),\n',)),
 (3179,
  3180,
  ("    station.predecessor_source(deviation.station_source(raw.decode('utf-8')))\n",),
  ('    station.predecessor_source(deviation.station_source(historical))\n',)),
 (3183,
  3184,
  ('    if sha(raw) == deviation.AFTER_SHA256:\n',),
  ('    if sha(historical) == deviation.AFTER_SHA256:\n',)),
 (3189,
  3191,
  ("        require(sha(value) == expected, 'station correctness fixture changed: ' + path)\n",),
  ("        require(sha(_historical_typed_text(path, value.decode('utf-8'))) == expected,\n",
   "                'station correctness fixture changed: ' + path)\n")),
 (3194, 3195, ('        result[path] = expected\n',), ('        result[path] = sha(value)\n',)),
 (3214,
  3216,
  ('            digest = sha(raw)\n',),
  ("            historical = _historical_typed_text(path, raw.decode('utf-8'))\n",
   '            digest = sha(historical)\n')),
 (3217,
  3218,
  ("                require(source.token_sha256(raw.decode('utf-8')) ==\n",),
  ('                require(source.token_sha256(historical) ==\n',)),
 (3221,
  3222,
  ("                witness_format.predecessor_source(path, raw.decode('utf-8'))\n",),
  ('                witness_format.predecessor_source(path, historical)\n',)),
 (3223, 3224, ('            result[path] = digest\n',), ('            result[path] = sha(raw)\n',)),
 (3230,
  3231,
  ('                require(type(raw) is bytes and sha(raw) == expected,\n',),
  ('                require(type(raw) is bytes and sha(_historical_typed_text(path, '
   "raw.decode('utf-8'))) == expected,\n",)),
 (3236,
  3237,
  ('                result[path] = expected\n',),
  ('                result[path] = sha(raw)\n',)),
 (3247,
  3371,
  ('def verify(root, *, exact=False, include_roots=(), _expected_lane_raw=None, '
   '_capture=None):\n',),
  ('def _historical_typed_text(path, text):\n',
   '    """Pure named provenance projection; never replace a captured input."""\n',
   '    return typed_boundary.historical_source(str(path), text)\n',
   '\n',
   '\n',
   'def _typed_boundary_bindings(root, *, _snapshots=None, _operation=None):\n',
   '    """Bind the complete new source graph and current native closure once."""\n',
   '    try:\n',
   '        _operation_check(_operation, root)\n',
   "        marker = 'extensions/carla/polynomial.mojo'\n",
   '        marker_raw = _observe_bytes(root, marker, _regular(root, marker).read_bytes(),\n',
   '                                    _operation=_operation)\n',
   '        if not typed_boundary.is_current(marker, marker_raw):\n',
   '            # A local-cubic graph cannot borrow historical polynomial storage.\n',
   '            # Each exact semantic endpoint must advance in the same operation.\n',
   '            for path in conditioned_cubic.SOURCE_PATHS:\n',
   '                raw = marker_raw if path == marker else _observe_bytes(\n',
   '                    root, path, _regular(root, path).read_bytes(), _operation=_operation)\n',
   '                require(not typed_boundary.is_current(path, raw),\n',
   "                        'mixed historical and conditioned source graph: ' + path)\n",
   '            return {}\n',
   '        image = {}\n',
   '        for path in typed_boundary.SOURCE_PATHS:\n',
   '            raw = marker_raw if path == marker else _observe_bytes(\n',
   '                root, path, _regular(root, path).read_bytes(), _operation=_operation)\n',
   "            require(type(raw) is bytes, 'typed source is not physical bytes: ' + path)\n",
   '            image[path] = raw\n',
   '        if (type(_operation) is _InvariantInputs\n',
   "                and _operation._kind == 'generated_receipt'\n",
   "                and _operation._state == 'active' and not _operation._capturing):\n",
   '            # Initial publication admitted this entire immutable source image.\n',
   '            # Every physical read above still joins it through _observe_bytes;\n',
   '            # authenticate live authority without replaying source semantics.\n',
   '            typed_boundary.verify_authority()\n',
   '            conditioned_cubic.verify_authority()\n',
   '        else:\n',
   "            typed_boundary.verify_sources({path: raw.decode('utf-8') for path, raw in "
   'image.items()})\n',
   "        leaves = ('tools/carla_lane_oracle/typed_boundary_contracts.py',\n",
   "                  'tools/carla_lane_oracle/conditioned_cubic_contracts.py')\n",
   '        conditioned_inputs = {}\n',
   '        for path, historical_digest in conditioned_cubic.BINDING_INPUTS.items():\n',
   '            if path in typed_boundary.EDGES:\n',
   '                edge = typed_boundary.edge(path)\n',
   "                require(edge['before_sha256'] == historical_digest,\n",
   "                        'typed input misses fixed conditioned witness/provider: ' + path)\n",
   '                # The semantic admission reconstructed this complete predecessor.\n',
   '                # Receipts bind current formatted bytes, not the old witness SHA.\n',
   "                conditioned_inputs[path] = edge['after_sha256']\n",
   '            else:\n',
   '                conditioned_inputs[path] = historical_digest\n',
   '        expected = {**typed_boundary.CURRENT_DEPENDENCIES, **typed_boundary.NEW_INPUTS, '
   '**typed_boundary.TESTS,\n',
   '                    **typed_boundary.BINDING_INPUTS, **conditioned_inputs,\n',
   '                    **{path: DEPENDENCY_TOOL_SHA256[path] for path in leaves}}\n',
   '        for path, digest in expected.items():\n',
   '            raw = _observe_bytes(root, path, _regular(root, path).read_bytes(), '
   '_operation=_operation)\n',
   "            require(sha(raw) == digest, 'typed boundary bound input changed: ' + path)\n",
   '            typed_boundary.verify_binding_successor(path, raw)\n',
   "            require(path not in image or image[path] == raw, 'typed input changed after source "
   "admission: ' + path)\n",
   '            image[path] = raw\n',
   '        for path, raw in image.items():\n',
   '            if _snapshots is not None:\n',
   "                require(_snapshots.setdefault(path, raw) == raw, 'typed input changed after "
   "consumption: ' + path)\n",
   '            require(_observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
   '                                   _operation=_operation) == raw,\n',
   "                    'typed input changed during admission: ' + path)\n",
   '        return {path: sha(raw) for path, raw in image.items()}\n',
   '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, '
   'AttributeError) as error:\n',
   '        _operation_fail(_operation, error)\n',
   '\n',
   '\n',
   'def reviewed_typed_text(root, path, text, *, _operation=None, _inputs=None, '
   '_input_owner=None):\n',
   '    """Admit physical current bytes before returning historical provenance."""\n',
   '    path = str(path)\n',
   '    edge = typed_boundary.EDGES.get(path)\n',
   '    if edge is None:\n',
   '        return text\n',
   '    _public_admission = None\n',
   '    try:\n',
   '        if _inputs is None and _operation is None:\n',
   '            _public_admission = _public_admission_for(root)\n',
   '        if _inputs is not None:\n',
   '            require(type(_inputs) in (_CacheInputs, _BorrowedCacheInputs),\n',
   "                    'invalid typed source owner')\n",
   '            if type(_inputs) is _BorrowedCacheInputs:\n',
   '                # Authenticate the lease before using its operation. Its\n',
   '                # canonical check poisons the consumed owner for bad tokens.\n',
   '                _BorrowedCacheInputs._check(_inputs, _input_owner, root)\n',
   '                explicit_operation = _operation\n',
   '                _operation = _inputs._operation\n',
   '                require(explicit_operation is None or explicit_operation is _operation,\n',
   "                        'typed source operation differs from borrowed owner')\n",
   "        require((_inputs is None) == (_input_owner is None), 'incomplete typed input owner')\n",
   '        if not (typed_boundary.is_current(path, text) or\n',
   "                source.token_sha256(text) == edge['after_token_sha256']):\n",
   '            return text\n',
   '        _operation_check(_operation, root)\n',
   '        raw = _observe_bytes(root, path, _regular(root, path).read_bytes(), '
   '_operation=_operation)\n',
   '        require(typed_boundary.is_current(path, raw),\n',
   "                'typed physical input is not the exact reviewed endpoint: ' + path)\n",
   "        physical_text = raw.decode('utf-8')\n",
   '        require(type(text) is str and source.token_sha256(text) == '
   'source.token_sha256(physical_text),\n',
   "                'supplied typed source differs from physical input: ' + path)\n",
   "        _observe_text(root, path, text, _operation=_operation, mode='physical',\n",
   '                      supplied=True, _checked_raw=raw)\n',
   '        if _inputs is not None:\n',
   "            require(_inputs.raw(_input_owner, root, path) == raw, 'typed owner image changed: "
   "' + path)\n",
   '        elif _operation is None:\n',
   "            if _public_admission is None or _public_admission._state == 'pending':\n",
   '                verify(root, exact=True)\n',
   '            if _public_admission is not None:\n',
   '                _public_admission.project(root, path, raw)\n',
   '        else:\n',
   '            _operation_record(_operation, root, exact=True)\n',
   '        require(_observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
   '                               _operation=_operation) == raw,\n',
   "                'typed source changed during provenance reconstruction: ' + path)\n",
   '        return _historical_typed_text(path, physical_text)\n',
   '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, '
   'AttributeError) as error:\n',
   '        if _public_admission is not None:\n',
   '            _public_admission.fail()\n',
   '        _operation_fail(_operation, error)\n',
   '\n',
   '\n',
   'def verify(root, *, exact=False, include_roots=(), _expected_lane_raw=None, _capture=None, '
   '_expected_sources=None):\n')),
 (3373,
  3374,
  (),
  ('    _public_admission = _public_admission_for(root, publication=True) if include_roots == () '
   'else None\n',)),
 (3376,
  3380,
  ('            require(type(_capture) in (_CacheInputs, _InvariantInputs) and not exact and '
   'include_roots == (),\n',),
  ('            generated = type(_capture) is _InvariantInputs and _capture._kind == '
   "'generated_receipt'\n",
   '            require(type(_capture) in (_CacheInputs, _InvariantInputs) and not exact\n',
   '                    and (include_roots == () or (generated and tuple(\n',
   '                        _absolute_root_text(path) for path in include_roots) == '
   '_capture._include_roots)),\n')),
 (3392,
  3411,
  ('        for path, raw in snapshots.items():\n', '            text = _physical_text(raw)\n'),
  ('        if _expected_sources is not None:\n',
   '            require(_capture is None and type(_expected_sources) is dict,\n',
   "                    'invalid supplied source capture request')\n",
   '            for path, expected in _expected_sources.items():\n',
   '                require(type(path) is str and _canonical_relative_text(path)\n',
   "                        and type(expected) is bytes, 'invalid supplied source capture "
   "value')\n",
   '                physical = _regular(root, path)\n',
   '                if path not in snapshots:\n',
   '                    snapshots[path] = physical.read_bytes()\n',
   '                require(snapshots[path] == expected,\n',
   "                        'supplied source observation changed before admission: ' + path)\n",
   '        typed_bindings = _typed_boundary_bindings(root, _snapshots=snapshots,\n',
   '            _operation=_capture if type(_capture) is _InvariantInputs else None)\n',
   '        for path in SOURCE_PATHS:\n',
   '            raw = snapshots[path]\n',
   '            # Exact provenance retains physical line endings. Universal-newline\n',
   '            # decoding belongs only to the separate semantic source view.\n',
   "            exact_text = _historical_typed_text(path, raw.decode('utf-8'))\n",
   "            text = _physical_text(exact_text.encode('utf-8'))\n")),
 (3412,
  3413,
  ('            require(source.token_sha256(supplied_view) == source.token_sha256(text),\n',),
  ('            require(source.token_sha256(supplied_view) == '
   'source.token_sha256(_physical_text(raw)),\n',)),
 (3415,
  3417,
  ('            require((not exact or sha(raw) == AFTER_SHA256[path])\n',
   '                    and source.token_sha256(_physical_text(raw)) == '
   "item['after_token_sha256']\n"),
  ('            require((not exact or sha(exact_text) == AFTER_SHA256[path])\n',
   "                    and source.token_sha256(text) == item['after_token_sha256']\n")),
 (3426,
  3429,
  (),
  ('        scaled_bindings = _scaled_float32_bindings(root, _snapshots=snapshots)\n',
   '        scaled_edges = scaled_float32.edges(tuple(name for name in '
   'scaled_float32.SOURCE_PATHS\n',
   '            if scaled_bindings.get(name) == scaled_float32.AFTER_SHA256[name]))\n')),
 (3437,
  3439,
  (),
  ("                          | {path for path in scaled_bindings if path.endswith('.mojo')}\n",
   '                          | (set(typed_boundary.CURRENT_DEPENDENCIES) if typed_bindings else '
   'set())\n')),
 (3446,
  3447,
  ("                    **_render_lookup_args(resolver_paths, record['entry_directories']))\n",
   '                and all(resolver_unshadowed(location, include_resolver_paths)\n',
   '                        for location in include_roots),\n'),
  ("                    **_render_lookup_args(resolver_paths, record['entry_directories'])),\n",)),
 (3459,
  3467,
  (),
  ('        include_images = []\n',
   '        for location in include_roots:\n',
   '            stage_entries, stage_image = _include_entry_context(\n',
   '                location, {path: snapshots[path] for path in known})\n',
   '            stage_args = _render_lookup_args(resolver_paths, stage_entries)\n',
   '            require(resolver_unshadowed(location, include_resolver_paths, **stage_args),\n',
   "                    'unreviewed include resolver surface')\n",
   '            include_images.append((location, stage_image, stage_args))\n')),
 (3469,
  3471,
  ("                == set(record['dependency_inventory']) | helper_closure, 'production import "
   "inventory changed')\n",),
  ('                == (set(typed_boundary.PRODUCTION_CLOSURE) if typed_bindings else\n',
   "                    set(record['dependency_inventory']) | helper_closure), 'production import "
   "inventory changed')\n")),
 (3473,
  3475,
  ("        require(native_found == set(record['native_dependency_inventory']) | "
   'helper_closure,\n',),
  ('        require(native_found == (set(typed_boundary.NATIVE_CLOSURE) if typed_bindings else\n',
   "                set(record['native_dependency_inventory']) | helper_closure),\n")),
 (3476,
  3491,
  (),
  ('        if typed_bindings:\n',
   '            current_native = set()\n',
   '            test_paths = tuple(path for path in typed_boundary.TESTS if '
   "path.endswith('.mojo'))\n",
   '            for parent in sorted({str(Path(path).parent) for path in test_paths}):\n',
   '                current_native.update(dependency_inventory(root,\n',
   '                    roots=tuple(path for path in test_paths if str(Path(path).parent) == '
   'parent),\n',
   '                    entries=(parent,), _known=known, _snapshots=snapshots))\n',
   '            require(current_native == set(typed_boundary.TYPED_NATIVE_CLOSURE),\n',
   "                    'typed native test import inventory changed')\n",
   '            current_production = dependency_inventory(root,\n',
   '                roots=tuple(path for path in (*typed_boundary.SOURCE_PATHS, '
   '*typed_boundary.NEW_INPUTS)\n',
   "                    if path.endswith('.mojo') and not path.startswith(('tests/', 'tools/', "
   "'examples/', 'bench/'))),\n",
   '                entries=entries, _known=known, _snapshots=snapshots)\n',
   '            require(current_production == set(typed_boundary.TYPED_PRODUCTION_CLOSURE),\n',
   "                    'typed production import inventory changed')\n")),
 (3494,
  3495,
  ('        _runtime_view_bindings(root, _snapshots=snapshots)\n',),
  ('        runtime_bindings = _runtime_view_bindings(root, _snapshots=snapshots)\n',)),
 (3514,
  3519,
  (),
  ('                if path in scaled_edges:\n',
   "                    require(group in ('unchanged_inputs', 'native_dependency_inputs')\n",
   "                            and expected == scaled_edges[path]['before_sha256'],\n",
   "                            'scaled edge does not extend immutable input: ' + path)\n",
   "                    expected = scaled_edges[path]['after_sha256']\n")),
 (3525,
  3529,
  ("                require(sha(raw) == expected, 'unchanged premise, record or fixture changed: ' "
   '+ path)\n',),
  ("                historical = _historical_typed_text(path, raw.decode('utf-8')).encode('utf-8') "
   'if path in typed_boundary.EDGES and typed_bindings else raw\n',
   '                if historical != raw and expected == sha(raw):\n',
   '                    expected = sha(historical)\n',
   "                require(sha(historical) == expected, 'unchanged premise, record or fixture "
   "changed: ' + path)\n")),
 (3531,
  3533,
  ('        production = set() if _capture is not None else None\n',
   '        observed_inventory = (inventory(root, _snapshots=snapshots) if _capture is None '
   'else\n'),
  ('        production = set() if _capture is not None or _public_admission is not None else '
   'None\n',
   '        observed_inventory = (inventory(root, _snapshots=snapshots) if production is None '
   'else\n')),
 (3542,
  3544,
  (),
  ('        if typed_bindings:\n', '            expected_inventory = typed_boundary.INVENTORY\n')),
 (3549,
  3551,
  (),
  ('        for location, image, _ in include_images:\n',
   '            _helper_entry_census_finish(location, image)\n')),
 (3553,
  3555,
  ('                and all(resolver_unshadowed(location, include_resolver_paths) for location in '
   'include_roots),\n',),
  ('                and all(resolver_unshadowed(location, include_resolver_paths, **stage_args)\n',
   '                        for location, _, stage_args in include_images),\n')),
 (3562,
  3597,
  ('            _capture._publish(root, snapshots, authority_raw, known, production, entries,\n',
   '                              resolver_paths, executing)\n'),
  ("            if type(_capture) is _InvariantInputs and _capture._kind == 'generated_receipt':\n",
   '                receipt_bindings = {MIGRATION: MIGRATION_SHA256,\n',
   '                                    CONSUMER_LEDGER: CONSUMER_LEDGER_SHA256, **executing}\n',
   "                receipt_bindings.update({path: item['after_sha256'] for path, item in "
   "record['sources'].items()})\n",
   '                for group in BOUND_GROUPS:\n',
   '                    receipt_bindings.update(record[group])\n',
   '                for family in (station_bindings, scaled_bindings, typed_bindings,\n',
   '                               witness_bindings, runtime_bindings, helper_bindings):\n',
   '                    receipt_bindings.update(family)\n',
   '                if scaled_bindings:\n',
   '                    scaled_paths = frozenset(name for name in scaled_bindings if '
   "name.endswith('.mojo'))\n",
   '                    require(scaled_paths == scaled_float32.NATIVE_CLOSURE\n',
   '                            and _scaled_known_paths(root) == known,\n',
   "                            'generated scaled native context differs from source admission')\n",
   "                    scaled_include_paths = scaled_paths | {name + '.cov-origin' for name in "
   'scaled_paths}\n',
   '                    require(resolver_unshadowed(root, scaled_paths, **_scaled_lookup_args())\n',
   '                            and all(resolver_unshadowed(location, scaled_include_paths,\n',
   '                                                       **_scaled_lookup_args())\n',
   '                                    for location in include_roots),\n',
   "                            'generated scaled native resolver changed during admission')\n",
   '                    _capture._scaled_resolver_paths = scaled_paths\n',
   '                _capture._publish(root, snapshots, authority_raw, known, production, '
   'entries,\n',
   '                    resolver_paths, executing, receipt_bindings=receipt_bindings,\n',
   '                    include_images=tuple(include_images))\n',
   '            else:\n',
   '                _capture._publish(root, snapshots, authority_raw, known, production, '
   'entries,\n',
   '                                  resolver_paths, executing)\n',
   '        if _public_admission is not None:\n',
   '            public_image = _public_admission._publication_inputs(root, snapshots)\n',
   "            if _public_admission._state == 'pending':\n",
   '                if scaled_bindings:\n',
   '                    _public_admission._scaled_resolver_paths = frozenset(\n',
   "                        path for path in scaled_bindings if path.endswith('.mojo'))\n",
   '                _public_admission._publish(root, public_image, authority_raw, known,\n',
   '                    production, entries, resolver_paths, executing)\n')),
 (3599,
  3601,
  (),
  ('        if _public_admission is not None:\n', '            _public_admission.fail()\n')),
 (3603,
  3605,
  (),
  ('        if _public_admission is not None:\n', '            _public_admission.fail()\n')),
 (3622,
  3651,
  ('    path = str(path)\n',
   '    if text is None:\n',
   "        text = _regular(root, path).read_text(encoding='utf-8')\n",
   '    if path not in SOURCE_PATHS or source.token_sha256(text) == BEFORE_TOKEN_SHA256[path]:\n',
   '        return text\n',
   "    require(source.token_sha256(text) == AFTER_TOKEN_SHA256[path], 'unreviewed supplied "
   "successor source: ' + path)\n",
   '    if _operation is not None:\n',
   "        _observe_text(root, path, text, _operation=_operation, mode='physical', "
   'supplied=True)\n',
   '    return predecessor_source(root, path, _operation=_operation)\n'),
  ('    _public_admission = None\n',
   '    try:\n',
   '        if _operation is None:\n',
   '            _public_admission = _public_admission_for(root)\n',
   '        path = str(path)\n',
   '        if text is None:\n',
   '            text = _observe_text(root, path, _regular(root, '
   "path).read_text(encoding='utf-8'),\n",
   "                                 _operation=_operation, mode='physical')\n",
   '        if path in SOURCE_PATHS and typed_boundary.is_current(path, text):\n',
   '            raw = _observe_bytes(root, path, _regular(root, path).read_bytes(), '
   '_operation=_operation)\n',
   '            require(typed_boundary.is_current(path, raw)\n',
   '                    and source.token_sha256(text) == '
   'source.token_sha256(_physical_text(raw)),\n',
   "                    'supplied typed successor differs from physical input: ' + path)\n",
   '            record = (verify(root) if _operation is None else _operation_record(_operation, '
   'root))\n',
   '            require(_observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
   '                                   _operation=_operation) == raw,\n',
   "                    'typed successor changed during admission: ' + path)\n",
   "            item = record['sources'][path]\n",
   "            return reverse_exact(path, item['after_source'], item)\n",
   '        text = reviewed_typed_text(root, path, text, _operation=_operation)\n',
   '        if path not in SOURCE_PATHS or source.token_sha256(text) == '
   'BEFORE_TOKEN_SHA256[path]:\n',
   '            return text\n',
   "        require(source.token_sha256(text) == AFTER_TOKEN_SHA256[path], 'unreviewed supplied "
   "successor source: ' + path)\n",
   '        return predecessor_source(root, path, _operation=_operation)\n',
   '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, '
   'AttributeError) as error:\n',
   '        if _public_admission is not None:\n',
   '            _public_admission.fail()\n',
   '        _operation_fail(_operation, error)\n',
   '\n')),
 (3663,
  3664,
  ('        require(digest == AFTER_TOKEN_SHA256[path],\n',),
  ('        require(digest == AFTER_TOKEN_SHA256[path] or typed_boundary.is_current(path, '
   'expected_raw),\n',)),
 (3672,
  3673,
  ("        require(sha(road_raw) == record['unchanged_inputs'][road],\n",),
  ("        require(sha(_historical_typed_text(road, road_raw.decode('utf-8'))) == "
   "record['unchanged_inputs'][road],\n",)),
 (3688,
  3695,
  ('    record = verify(root)\n',),
  ('    physical_inputs = {}\n',
   '    for path, text in texts.items():\n',
   '        raw = _regular(root, path).read_bytes()\n',
   '        require(source.token_sha256(text) == source.token_sha256(_physical_text(raw)),\n',
   "                'supplied successor source differs from physical input: ' + path)\n",
   '        physical_inputs[path] = raw\n',
   '    record = verify(root, _expected_sources=physical_inputs)\n')),
 (3699,
  3707,
  (),
  ('        physical = _regular(root, path).read_bytes()\n',
   '        require(physical == physical_inputs[path],\n',
   "                'supplied successor physical input changed during admission: ' + path)\n",
   '        require(source.token_sha256(text) == source.token_sha256(_physical_text(physical)),\n',
   "                'supplied successor source differs from physical input: ' + path)\n",
   '        # Only canonical physical bytes enter the exact typed inverse; caller\n',
   '        # comments have already been compared by the public supplied-view rule.\n',
   '        text = _historical_typed_text(path, _physical_text(physical))\n')),
 (3714,
  3715,
  ('            require(source.token_sha256(text) == source.token_sha256(_physical_text(raw)),\n',),
  ('            require(raw == physical and source.token_sha256(text) == '
   'source.token_sha256(_historical_typed_text(path, _physical_text(raw))),\n',)),
 (3716, 3717, (), ('            result[path] = text\n',)),
 (3735,
  3738,
  ('            changed = any(declaration_sha256(text, name) not in expected\n',),
  ('            typed_current = typed_boundary.is_current(path, text)\n',
   '            text = _historical_typed_text(path, text)\n',
   '            changed = typed_current or any(declaration_sha256(text, name) not in expected\n')),
 (3762,
  3763,
  ('def reviewed_lane_before_center_text(root, text=None):\n',),
  ('def reviewed_lane_before_center_text(root, text=None, *, _operation=None):\n',)),
 (3764, 3765, (), ('    supplied_raw = None\n',)),
 (3766,
  3778,
  ("        require(source.token_sha256(text) == AFTER_TOKEN_SHA256[path], 'unreviewed supplied "
   "center source')\n",
   "    item = verify(root)['sources'][path]\n"),
  ('        supplied_raw = _observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
   '                                      _operation=_operation)\n',
   '        require(source.token_sha256(text) == '
   'source.token_sha256(_physical_text(supplied_raw)),\n',
   "                'unreviewed supplied center source')\n",
   '    item = (verify(root, _expected_lane_raw=supplied_raw) if _operation is None else\n',
   '            _operation_record(_operation, root, '
   "expected_lane_raw=supplied_raw))['sources'][path]\n",
   '    if supplied_raw is not None:\n',
   '        require(source.token_sha256(_historical_typed_text(path, '
   '_physical_text(supplied_raw)))\n',
   "                == AFTER_TOKEN_SHA256[path], 'unreviewed supplied center source')\n",
   '        require(_observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
   '                               _operation=_operation) == supplied_raw,\n',
   "                'supplied center physical input changed during admission')\n")),
 (3787,
  3818,
  (),
  ('\n',
   '\n',
   'def typed_successor_edges(root, *, _operation=None):\n',
   '    """Return explicit current edges, separately from immutable old records."""\n',
   '    try:\n',
   "        marker = 'extensions/carla/polynomial.mojo'\n",
   '        raw = _observe_bytes(root, marker, _regular(root, marker).read_bytes(),\n',
   '                             _operation=_operation)\n',
   '        if not typed_boundary.is_current(marker, raw):\n',
   '            return {}\n',
   '        if _operation is None:\n',
   '            verify(root, exact=True)\n',
   '        else:\n',
   '            _operation_record(_operation, root, exact=True)\n',
   '        result = {}\n',
   '        for path in typed_boundary.SOURCE_PATHS:\n',
   '            current = _observe_bytes(root, path, _regular(root, path).read_bytes(),\n',
   '                                     _operation=_operation)\n',
   '            require(typed_boundary.is_current(path, current),\n',
   "                    'typed successor physical endpoint changed: ' + path)\n",
   '            edge = typed_boundary.edge(path)\n',
   "            edge['scope'] = 'explicit historical provenance; current typed API admission'\n",
   '            if path in conditioned_cubic.SOURCE_PATHS:\n',
   "                edge['conditioned_graph'] = {\n",
   "                    'before_sha256': conditioned_cubic.BEFORE_SHA256[path],\n",
   "                    'after_sha256': conditioned_cubic.AFTER_SHA256[path],\n",
   "                    'scope': 'new local-coefficient graph; no scalar bit-equivalence claim'}\n",
   '            result[path] = edge\n',
   '        return result\n',
   '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, '
   'AttributeError) as error:\n',
   '        _operation_fail(_operation, error)\n')),
 (3836,
  3844,
  (),
  ('        if result.get(station.MODULE) == '
   "typed_boundary.EDGES[station.MODULE]['after_sha256']:\n",
   '            # The public typed receipt requires the complete current graph.\n',
   "            # Keep _station_bindings itself nonrecursive for verify's capture.\n",
   '            if _operation is None:\n',
   '                verify(root, exact=True)\n',
   '            else:\n',
   '                _operation_record(_operation, root, exact=True)\n',
   '            result.update(_typed_boundary_bindings(root, _operation=_operation))\n')),
 (3860,
  3862,
  (),
  ("        if type(_operation) is _InvariantInputs and _operation._kind == 'generated_receipt':\n",
   '            return _operation._receipt_bindings(root, include_roots)\n')),
 (3873,
  3876,
  (),
  ('        result.update(scaled_float32_proof_bindings(root, include_roots=include_roots,\n',
   '                                                   _operation=_operation))\n',
   '        result.update(_typed_boundary_bindings(root, _operation=_operation))\n')),
 (3880,
  3882,
  (),
  ('        if _operation is not None:\n',
   '            _operation._bind_checker_receipt(root, executing)\n'))),
    'grouped_y_finiteness_contracts.py': (
        (1, 11,
         (),
         (
          '\n',
          'if __package__:\n',
          '    from . import source_contracts as _typed_source\n',
          'else:\n',
          '    import source_contracts as _typed_source\n',
          '\n',
          'if __package__:\n',
          '    from . import source_contracts as source\n',
          'else:\n',
          '    import source_contracts as source\n',
         ),
        ),
        (42, 46,
         (
          '        modules = {p: full_audit._observe_text(root, p, text, _operation=_operation)\n',
         ),
         (
          '        modules = {p: _typed_source.historical_text(root, p, full_audit._observe_text(root, p, text, _operation=_operation), _operation=_operation)\n',
          '                   for p, text in modules.items()}\n',
          '    else:\n',
          '        modules = {p: _typed_source.historical_text(root, p, text)\n',
         ),
        ),
        (58, 59,
         (),
         (
          '# #333 explicit historical provenance views; current inputs remain operation-owned.\n',
         ),
        ),
        (66, 67,
         (
          '    payload = (root / RECORD).read_bytes()\n',
         ),
         (
          '    payload = _typed_source.historical_bytes(root, root / RECORD, (root / RECORD).read_bytes(), _operation=_operation)\n',
         ),
        ),
    ),
    'raw_cut_inverse_contracts.py': (
        (3, 8,
         (),
         (
          '\n',
          'if __package__:\n',
          '    from . import source_contracts as _typed_source\n',
          'else:\n',
          '    import source_contracts as _typed_source\n',
         ),
        ),
        (9, 10,
         (),
         (
          '# #333 explicit historical provenance views; current inputs remain operation-owned.\n',
         ),
        ),
        (31, 32,
         (
          '    payload = (root/MIGRATION).read_bytes()\n',
         ),
         (
          '    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())\n',
         ),
        ),
        (60, 61,
         (),
         (
          '    text = _typed_source.historical_text(root, SOURCE_PATH, text, _operation=_operation)\n',
         ),
        ),
        (65, 67,
         (
          '        environment = full_audit._observe_text(\n',
          "            root, 'extensions/carla/curve_sum2.mojo', environment, _operation=_operation)\n",
         ),
         (
          "        environment = full_audit._observe_text(root, 'extensions/carla/curve_sum2.mojo', environment, _operation=_operation)\n",
          "    environment = _typed_source.historical_text(root, 'extensions/carla/curve_sum2.mojo', environment, _operation=_operation)\n",
         ),
        ),
        (69, 70,
         (
          "    predecessor_payload = (root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_bytes()\n",
         ),
         (
          "    predecessor_payload = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json', (root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_bytes(), _operation=_operation)\n",
         ),
        ),
        (74, 76,
         (
          '        predecessor_text = full_audit._observe_text(\n',
          "            root, 'tools/carla_lane_oracle/curve-support-dispatch-migration.json',\n",
          '            predecessor_text, _operation=_operation, _checked_raw=predecessor_payload)\n',
         ),
         (
          "        predecessor_text = full_audit._observe_text(root, 'tools/carla_lane_oracle/curve-support-dispatch-migration.json', predecessor_text, _operation=_operation, _checked_raw=predecessor_payload)\n",
          "    predecessor_text = _typed_source.historical_text(root, 'tools/carla_lane_oracle/curve-support-dispatch-migration.json', predecessor_text, _operation=_operation)\n",
         ),
        ),
        (82, 84,
         (
          '        fixture = full_audit._observe_text(\n',
          "            root, 'tests/test_carla_raw_cut_successor.mojo', fixture, _operation=_operation)\n",
         ),
         (
          "        fixture = full_audit._observe_text(root, 'tests/test_carla_raw_cut_successor.mojo', fixture, _operation=_operation)\n",
          "    fixture = _typed_source.historical_text(root, 'tests/test_carla_raw_cut_successor.mojo', fixture, _operation=_operation)\n",
         ),
        ),
        (88, 90,
         (
          '        reference = full_audit._observe_text(\n',
          "            root, 'tests/test_carla_support_dispatch_successor.mojo', reference,\n",
          '            _operation=_operation)\n',
         ),
         (
          "        reference = full_audit._observe_text(root, 'tests/test_carla_support_dispatch_successor.mojo', reference, _operation=_operation)\n",
          "    reference = _typed_source.historical_text(root, 'tests/test_carla_support_dispatch_successor.mojo', reference, _operation=_operation)\n",
         ),
        ),
        (107, 108,
         (),
         (
          '    text = _typed_source.historical_text(root, SOURCE_PATH, text, _operation=_operation)\n',
         ),
        ),
    ),
    'seed_count_contracts.py': ((10,
  15,
  (),
  ('if __package__:\n',
   '    from . import source_contracts as _typed_source\n',
   'else:\n',
   '    import source_contracts as _typed_source\n',
   '\n')),
 (16,
  17,
  (),
  ('# #333 explicit historical provenance views; current inputs remain operation-owned.\n',)),
 (20, 21, (), ('import sys\n',)),
 (38, 41, (), ('\n', '_EXECUTED_MODULE_CODE = sys._getframe().f_code\n', '\n')),
 (229,
  231,
  ('    payload = ((Path(root)/MIGRATION).read_bytes() if _inputs is None else\n',
   '               _inputs.raw(_input_owner, root, MIGRATION))\n'),
  ('    payload = (_typed_source.historical_bytes(root, Path(root)/MIGRATION, '
   '(Path(root)/MIGRATION).read_bytes(), _operation=_operation, _inputs=_inputs, '
   '_input_owner=_input_owner) if _inputs is None else\n',
   '               _typed_source.historical_bytes(root, MIGRATION, _inputs.raw(_input_owner, root, '
   'MIGRATION), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n')),
 (273,
  274,
  ("    text = (Path(root)/MODULE).read_bytes().decode('utf-8')\n",),
  ('    text = _typed_source.historical_bytes(root, Path(root)/MODULE, '
   "(Path(root)/MODULE).read_bytes()).decode('utf-8')\n",)),
 (377,
  379,
  ('        text = (((root/name).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, name, (root/name).read_bytes(), '
   "_operation=_operation)).decode('utf-8') if _inputs is None else\n",
   '                _inputs.text_utf8(_input_owner, root, name))\n'),
  ('        text = ((_typed_source.historical_bytes(root, root/name, (root/name).read_bytes(), '
   '_operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else '
   '_typed_source.historical_bytes(root, name, full_audit._observe_bytes(root, name, '
   '(root/name).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, '
   "_input_owner=_input_owner)).decode('utf-8') if _inputs is None else\n",
   '                _typed_source.historical_text(root, name, _inputs.text_utf8(_input_owner, '
   'root, name), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n')),
 (440,
  441,
  ('def verify_support(root):\n',),
  ('def verify_support(root, *, _expected_raw=None):\n',)),
 (444,
  449,
  ("    text = (root/MODULE).read_bytes().decode('utf-8')\n",),
  ('    current_raw = (root/MODULE).read_bytes()\n',
   '    if _expected_raw is not None:\n',
   '        require(type(_expected_raw) is bytes and current_raw == _expected_raw,\n',
   "                'Map observation changed before delegated verification')\n",
   "    text = _typed_source.historical_bytes(root, MODULE, current_raw).decode('utf-8')\n")),
 (455,
  456,
  ("    require((root/MODULE).read_bytes().decode('utf-8') == text,\n",),
  ('    require((root/MODULE).read_bytes() == current_raw,\n',)),
 (500,
  501,
  ('def verify_frontier(root):\n',),
  ('def verify_frontier(root, *, _expected_raw=None):\n',)),
 (504,
  509,
  ("    text = (root/MODULE).read_bytes().decode('utf-8')\n",),
  ('    current_raw = (root/MODULE).read_bytes()\n',
   '    if _expected_raw is not None:\n',
   '        require(type(_expected_raw) is bytes and current_raw == _expected_raw,\n',
   "                'Map observation changed before delegated verification')\n",
   "    text = _typed_source.historical_bytes(root, MODULE, current_raw).decode('utf-8')\n")),
 (516,
  517,
  ("    require((root/MODULE).read_bytes().decode('utf-8') == text,\n",),
  ('    require((root/MODULE).read_bytes() == current_raw,\n',)),
 (571,
  582,
  ('        text = ((path.read_text() if _operation is None else full_audit._observe_text(root, '
   'rel.as_posix(), path.read_text(), _operation=_operation)) if _inputs is None else\n',
   '                _inputs.text_default(_input_owner, root, rel.as_posix()))\n'),
  ('        supplied_text = ((path.read_text() if _operation is None else\n',
   '                          full_audit._observe_text(root, rel.as_posix(), path.read_text(), '
   '_operation=_operation)) if _inputs is None else\n',
   '                         _inputs.text_default(_input_owner, root, rel.as_posix()))\n',
   '        if rel.as_posix() == MODULE and station_edge is not None:\n',
   '            physical = ((path.read_bytes() if _operation is None else\n',
   '                         full_audit._observe_bytes(root, MODULE, path.read_bytes(), '
   '_operation=_operation)) if _inputs is None else\n',
   '                        _inputs.observe_bytes(_input_owner, root, MODULE))\n',
   '            require(source.token_sha256(supplied_text) == '
   "source.token_sha256(physical.decode('utf-8')),\n",
   "                    'station census supplied and physical Map views differ')\n",
   '        text = _typed_source.historical_text(root, rel.as_posix(), supplied_text, '
   '_operation=_operation,\n',
   '            _inputs=_inputs, _input_owner=_input_owner)\n')),
 (668,
  669,
  ('def verify_score(root, *, _inputs=None, _input_owner=None, _operation=None):\n',),
  ('def verify_score(root, *, _inputs=None, _input_owner=None, _operation=None, '
   '_expected_raw=None):\n',)),
 (672, 673, (), ('    with _typed_source.typed_admission_scope(root) as _typed_admission:\n',)),
 (673,
  674,
  ("    record = (read_record(root, **({} if _operation is None else {'_operation': _operation})) "
   'if _inputs is None else\n',),
  ("        record = (read_record(root, **({} if _operation is None else {'_operation': "
   '_operation})) if _inputs is None else\n',)),
 (674,
  675,
  ('              read_record(root, _inputs=_inputs, _input_owner=_input_owner, **({} if '
   "_operation is None else {'_operation': _operation})))\n",),
  ('                  read_record(root, _inputs=_inputs, _input_owner=_input_owner, **({} if '
   "_operation is None else {'_operation': _operation})))\n",)),
 (675,
  683,
  ('    text = (((root/MODULE).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   "_operation=_operation)).decode('utf-8') if _inputs is None else\n",
   "            _inputs.observe_bytes(_input_owner, root, MODULE).decode('utf-8'))\n"),
  ('        current_raw = (((root/MODULE).read_bytes() if _operation is None else\n',
   '                        full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   '_operation=_operation)) if _inputs is None else\n',
   '                       _inputs.observe_bytes(_input_owner, root, MODULE))\n',
   '        if _expected_raw is not None:\n',
   '            require(type(_expected_raw) is bytes and current_raw == _expected_raw,\n',
   "                    'Map observation changed before delegated verification')\n",
   '        text = _typed_source.historical_bytes(root, MODULE, current_raw, '
   '_operation=_operation,\n',
   "            _inputs=_inputs, _input_owner=_input_owner).decode('utf-8')\n")),
 (683,
  684,
  ('    for path, expected in SCORE_TESTS.items():\n',),
  ('        for path, expected in SCORE_TESTS.items():\n',)),
 (684,
  686,
  ('        require(hashlib.sha256(((root/path).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)) if '
   '_inputs is None else\n',
   '                               _inputs.raw(_input_owner, root, path)).hexdigest() == '
   'expected,\n'),
  ('            require(hashlib.sha256((_typed_source.historical_bytes(root, root/path, '
   '(root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) '
   'if _operation is None else _typed_source.historical_bytes(root, path, '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), '
   '_operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) if _inputs is None else\n',
   '                                   _typed_source.historical_bytes(root, path, '
   '_inputs.raw(_input_owner, root, path), _operation=_operation, _inputs=_inputs, '
   '_input_owner=_input_owner)).hexdigest() == expected,\n')),
 (686,
  687,
  ("                'score-helper numerical fixture changed: '+path)\n",),
  ("                    'score-helper numerical fixture changed: '+path)\n",)),
 (687,
  688,
  ('    deviation_edge = sha(text) == deviation.AFTER_SHA256\n',),
  ('        deviation_edge = sha(text) == deviation.AFTER_SHA256\n',)),
 (688,
  689,
  ('    station_edge = deviation_edge or sha(text) == station.AFTER_SHA256\n',),
  ('        station_edge = deviation_edge or sha(text) == station.AFTER_SHA256\n',)),
 (689,
  690,
  ('    score_text = station.predecessor_source(deviation.station_source(text)) if station_edge '
   'else text\n',),
  ('        score_text = station.predecessor_source(deviation.station_source(text)) if '
   'station_edge else text\n',)),
 (690, 691, ('    if deviation_edge:\n',), ('        if deviation_edge:\n',)),
 (691,
  692,
  ('        for path, expected in deviation.TESTS.items():\n',),
  ('            for path, expected in deviation.TESTS.items():\n',)),
 (692,
  694,
  ('            require(hashlib.sha256(((root/path).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)) if '
   '_inputs is None else\n',
   '                                   _inputs.raw(_input_owner, root, path)).hexdigest() == '
   'expected,\n'),
  ('                require(hashlib.sha256((_typed_source.historical_bytes(root, root/path, '
   '(root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) '
   'if _operation is None else _typed_source.historical_bytes(root, path, '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), '
   '_operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) if _inputs is None else\n',
   '                                       _typed_source.historical_bytes(root, path, '
   '_inputs.raw(_input_owner, root, path), _operation=_operation, _inputs=_inputs, '
   '_input_owner=_input_owner)).hexdigest() == expected,\n')),
 (694,
  695,
  ("                    'deviation correctness fixture changed: '+path)\n",),
  ("                        'deviation correctness fixture changed: '+path)\n",)),
 (695, 696, ('    if station_edge:\n',), ('        if station_edge:\n',)),
 (696,
  697,
  ('        for path, expected in station.TESTS.items():\n',),
  ('            for path, expected in station.TESTS.items():\n',)),
 (697,
  699,
  ('            require(hashlib.sha256(((root/path).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)) if '
   '_inputs is None else\n',
   '                                   _inputs.raw(_input_owner, root, path)).hexdigest() == '
   'expected,\n'),
  ('                require(hashlib.sha256((_typed_source.historical_bytes(root, root/path, '
   '(root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) '
   'if _operation is None else _typed_source.historical_bytes(root, path, '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), '
   '_operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) if _inputs is None else\n',
   '                                       _typed_source.historical_bytes(root, path, '
   '_inputs.raw(_input_owner, root, path), _operation=_operation, _inputs=_inputs, '
   '_input_owner=_input_owner)).hexdigest() == expected,\n')),
 (699,
  700,
  ("                    'station correctness fixture changed: '+path)\n",),
  ("                        'station correctness fixture changed: '+path)\n",)),
 (700,
  701,
  ('    frontier = score_predecessor_source(score_text)\n',),
  ('        frontier = score_predecessor_source(score_text)\n',)),
 (701,
  702,
  ('    support = frontier_predecessor_source(frontier)\n',),
  ('        support = frontier_predecessor_source(frontier)\n',)),
 (702,
  703,
  ('    optional = support_predecessor_source(support)\n',),
  ('        optional = support_predecessor_source(support)\n',)),
 (703,
  704,
  ('    middle = optional_predecessor_source(optional)\n',),
  ('        middle = optional_predecessor_source(optional)\n',)),
 (704,
  705,
  ('    prior_edge = verify_source(middle, record)\n',),
  ('        prior_edge = verify_source(middle, record)\n',)),
 (705,
  706,
  ("    require(prior_edge is not None, 'score edge must follow all preceding edges')\n",),
  ("        require(prior_edge is not None, 'score edge must follow all preceding edges')\n",)),
 (706, 707, ('    if _inputs is None:\n',), ('        if _inputs is None:\n',)),
 (707,
  708,
  ("        _verify_bound_inputs(root, record, **({} if _operation is None else {'_operation': "
   '_operation}))\n',),
  ("            _verify_bound_inputs(root, record, **({} if _operation is None else {'_operation': "
   '_operation}))\n',)),
 (708,
  709,
  ('        verify_score_caller_inventory(root, station_edge=station_edge, **({} if _operation is '
   "None else {'_operation': _operation}))\n",),
  ('            verify_score_caller_inventory(root, station_edge=station_edge, **({} if _operation '
   "is None else {'_operation': _operation}))\n",)),
 (709,
  710,
  ('        verify_premises(root, record, after=True, optional=True, support=True,\n',),
  ('            verify_premises(root, record, after=True, optional=True, support=True,\n',)),
 (710,
  711,
  ('                        frontier=True, score=True, **({} if _operation is None else '
   "{'_operation': _operation}))\n",),
  ('                            frontier=True, score=True, **({} if _operation is None else '
   "{'_operation': _operation}))\n",)),
 (711, 712, ('    else:\n',), ('        else:\n',)),
 (712,
  713,
  ('        _verify_bound_inputs(root, record, _inputs=_inputs, _input_owner=_input_owner, **({} '
   "if _operation is None else {'_operation': _operation}))\n",),
  ('            _verify_bound_inputs(root, record, _inputs=_inputs, _input_owner=_input_owner, '
   "**({} if _operation is None else {'_operation': _operation}))\n",)),
 (713,
  714,
  ('        verify_score_caller_inventory(root, station_edge=station_edge, _inputs=_inputs, '
   "_input_owner=_input_owner, **({} if _operation is None else {'_operation': _operation}))\n",),
  ('            verify_score_caller_inventory(root, station_edge=station_edge, _inputs=_inputs, '
   "_input_owner=_input_owner, **({} if _operation is None else {'_operation': _operation}))\n",)),
 (714,
  715,
  ('        verify_premises(root, record, after=True, optional=True, support=True,\n',),
  ('            verify_premises(root, record, after=True, optional=True, support=True,\n',)),
 (715,
  716,
  ('                        frontier=True, score=True, _inputs=_inputs, _input_owner=_input_owner, '
   "**({} if _operation is None else {'_operation': _operation}))\n",),
  ('                            frontier=True, score=True, _inputs=_inputs, '
   "_input_owner=_input_owner, **({} if _operation is None else {'_operation': _operation}))\n",)),
 (716,
  720,
  ('    final_text = (((root/MODULE).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   "_operation=_operation)).decode('utf-8') if _inputs is None else\n",
   "                  _inputs.observe_bytes(_input_owner, root, MODULE).decode('utf-8'))\n",
   '    require(final_text == text,\n'),
  ('        final_raw = (((root/MODULE).read_bytes() if _operation is None else\n',
   '                      full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   '_operation=_operation)) if _inputs is None else\n',
   '                     _inputs.observe_bytes(_input_owner, root, MODULE))\n',
   '        require(final_raw == current_raw,\n')),
 (720,
  721,
  ("            'Map changed during score-helper verification')\n",),
  ("                'Map changed during score-helper verification')\n",)),
 (721,
  722,
  ('    endpoints = ((AFTER_SHA256, AFTER_TOKEN_SHA256),\n',),
  ('        endpoints = ((AFTER_SHA256, AFTER_TOKEN_SHA256),\n',)),
 (722,
  723,
  ('                 (OPTIONAL_AFTER_SHA256, OPTIONAL_AFTER_TOKEN_SHA256),\n',),
  ('                     (OPTIONAL_AFTER_SHA256, OPTIONAL_AFTER_TOKEN_SHA256),\n',)),
 (723,
  724,
  ('                 (SUPPORT_AFTER_SHA256, SUPPORT_AFTER_TOKEN_SHA256),\n',),
  ('                     (SUPPORT_AFTER_SHA256, SUPPORT_AFTER_TOKEN_SHA256),\n',)),
 (724,
  725,
  ('                 (FRONTIER_AFTER_SHA256, FRONTIER_AFTER_TOKEN_SHA256),\n',),
  ('                     (FRONTIER_AFTER_SHA256, FRONTIER_AFTER_TOKEN_SHA256),\n',)),
 (725,
  726,
  ('                 (SCORE_AFTER_SHA256, SCORE_AFTER_TOKEN_SHA256))\n',),
  ('                     (SCORE_AFTER_SHA256, SCORE_AFTER_TOKEN_SHA256))\n',)),
 (726, 727, ('    edges = [prior_edge]\n',), ('        edges = [prior_edge]\n',)),
 (727,
  728,
  ('    for before, after in zip(endpoints, endpoints[1:]):\n',),
  ('        for before, after in zip(endpoints, endpoints[1:]):\n',)),
 (728,
  729,
  ("        edges.append({'path': MODULE, 'before_sha256': before[0],\n",),
  ("            edges.append({'path': MODULE, 'before_sha256': before[0],\n",)),
 (729,
  730,
  ("                      'after_sha256': after[0], 'before_token_sha256': before[1],\n",),
  ("                          'after_sha256': after[0], 'before_token_sha256': before[1],\n",)),
 (730,
  731,
  ("                      'after_token_sha256': after[1]})\n",),
  ("                          'after_token_sha256': after[1]})\n",)),
 (731, 732, ('    if station_edge:\n',), ('        if station_edge:\n',)),
 (732,
  733,
  ('        edges.append(station.edge())\n',),
  ('            edges.append(station.edge())\n',)),
 (733, 734, ('    if deviation_edge:\n',), ('        if deviation_edge:\n',)),
 (734,
  735,
  ('        edges.append(deviation.edge())\n',),
  ('            edges.append(deviation.edge())\n',)),
 (735,
  736,
  ("    return {'path': MODULE, 'before_sha256': BEFORE_SHA256,\n",),
  ("        return {'path': MODULE, 'before_sha256': BEFORE_SHA256,\n",)),
 (736,
  737,
  ("            'after_sha256': edges[-1]['after_sha256'],\n",),
  ("                'after_sha256': edges[-1]['after_sha256'],\n",)),
 (737,
  738,
  ("            'before_token_sha256': BEFORE_TOKEN_SHA256,\n",),
  ("                'before_token_sha256': BEFORE_TOKEN_SHA256,\n",)),
 (738,
  739,
  ("            'after_token_sha256': edges[-1]['after_token_sha256'],\n",),
  ("                'after_token_sha256': edges[-1]['after_token_sha256'],\n",)),
 (739, 740, ("            'edges': edges}\n",), ("                'edges': edges}\n",)),
 (749,
  751,
  (),
  ('    scaled_edges = full_audit.scaled_float32_edges(root,\n',
   '        _inputs=_inputs, _input_owner=_input_owner, _operation=_operation)\n')),
 (757,
  759,
  ('           and hashlib.sha256(((root/path).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)) if '
   '_inputs is None else\n',
   '                              _inputs.raw(_input_owner, root, path)).hexdigest() == '
   'full_audit.AFTER_SHA256[path]\n'),
  ('           and hashlib.sha256((_typed_source.historical_bytes(root, root/path, '
   '(root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) '
   'if _operation is None else _typed_source.historical_bytes(root, path, '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), '
   '_operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) if _inputs is None else\n',
   '                              _typed_source.historical_bytes(root, path, '
   '_inputs.raw(_input_owner, root, path), _operation=_operation, _inputs=_inputs, '
   '_input_owner=_input_owner)).hexdigest() == full_audit.AFTER_SHA256[path]\n')),
 (766,
  770,
  (),
  ('    for path, edge in scaled_edges.items():\n',
   "        require(path in record['unchanged_inputs'] and path not in cleanup_edges,\n",
   "                'unexpected or duplicate scaled count input: ' + path)\n",
   '        cleanup_edges[path] = edge\n')),
 (778,
  780,
  ('            require(hashlib.sha256(((root/path).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation)) if '
   '_inputs is None else\n',
   '                              _inputs.raw(_input_owner, root, path)).hexdigest() == '
   'expected,\n'),
  ('            require(hashlib.sha256((_typed_source.historical_bytes(root, root/path, '
   '(root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) '
   'if _operation is None else _typed_source.historical_bytes(root, path, '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), '
   '_operation=_operation, _inputs=_inputs, _input_owner=_input_owner)) if _inputs is None else\n',
   '                              _typed_source.historical_bytes(root, path, '
   '_inputs.raw(_input_owner, root, path), _operation=_operation, _inputs=_inputs, '
   '_input_owner=_input_owner)).hexdigest() == expected,\n')),
 (783,
  784,
  ('def verify_optional(root):\n',),
  ('def verify_optional(root, *, _expected_raw=None):\n',)),
 (787,
  792,
  ("    text = (root/MODULE).read_bytes().decode('utf-8')\n",),
  ('    current_raw = (root/MODULE).read_bytes()\n',
   '    if _expected_raw is not None:\n',
   '        require(type(_expected_raw) is bytes and current_raw == _expected_raw,\n',
   "                'Map observation changed before delegated verification')\n",
   "    text = _typed_source.historical_bytes(root, MODULE, current_raw).decode('utf-8')\n")),
 (797,
  798,
  ("    require((root/MODULE).read_bytes().decode('utf-8') == text,\n",),
  ('    require((root/MODULE).read_bytes() == current_raw,\n',)),
 (825,
  827,
  ('        text = (((root/path).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), '
   "_operation=_operation)).decode('utf-8') if _inputs is None else\n",
   '                    _inputs.text_utf8(_input_owner, root, path))\n'),
  ('        text = ((_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), '
   '_operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else '
   '_typed_source.historical_bytes(root, path, full_audit._observe_bytes(root, path, '
   '(root/path).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, '
   "_input_owner=_input_owner)).decode('utf-8') if _inputs is None else\n",
   '                    _typed_source.historical_text(root, path, _inputs.text_utf8(_input_owner, '
   'root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n')),
 (844,
  846,
  ('            text = (((root/path).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), '
   "_operation=_operation)).decode('utf-8') if _inputs is None else\n",
   '                    _inputs.text_utf8(_input_owner, root, path))\n'),
  ('            text = ((_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), '
   '_operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else '
   '_typed_source.historical_bytes(root, path, full_audit._observe_bytes(root, path, '
   '(root/path).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, '
   "_input_owner=_input_owner)).decode('utf-8') if _inputs is None else\n",
   '                    _typed_source.historical_text(root, path, _inputs.text_utf8(_input_owner, '
   'root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n')),
 (863,
  865,
  ('            actual = declaration((((root/path).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), '
   "_operation=_operation)).decode('utf-8') if _inputs is None else\n",
   '                    _inputs.text_utf8(_input_owner, root, path)), name, owner)\n'),
  ('            actual = declaration(((_typed_source.historical_bytes(root, root/path, '
   '(root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) '
   'if _operation is None else _typed_source.historical_bytes(root, path, '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), '
   "_operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).decode('utf-8') if _inputs "
   'is None else\n',
   '                    _typed_source.historical_text(root, path, _inputs.text_utf8(_input_owner, '
   'root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)), name, '
   'owner)\n')),
 (869,
  871,
  ('            actual = declaration((((root/path).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), '
   "_operation=_operation)).decode('utf-8') if _inputs is None else\n",
   '                    _inputs.text_utf8(_input_owner, root, path)), name, owner)\n'),
  ('            actual = declaration(((_typed_source.historical_bytes(root, root/path, '
   '(root/path).read_bytes(), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner) '
   'if _operation is None else _typed_source.historical_bytes(root, path, '
   'full_audit._observe_bytes(root, path, (root/path).read_bytes(), _operation=_operation), '
   "_operation=_operation, _inputs=_inputs, _input_owner=_input_owner)).decode('utf-8') if _inputs "
   'is None else\n',
   '                    _typed_source.historical_text(root, path, _inputs.text_utf8(_input_owner, '
   'root, path), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner)), name, '
   'owner)\n')),
 (874,
  876,
  ('    text = (((root/MODULE).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   "_operation=_operation)).decode('utf-8') if _inputs is None else\n",
   '            _inputs.text_utf8(_input_owner, root, MODULE))\n'),
  ('    text = ((_typed_source.historical_bytes(root, root/MODULE, (root/MODULE).read_bytes(), '
   '_operation=_operation, _inputs=_inputs, _input_owner=_input_owner) if _operation is None else '
   '_typed_source.historical_bytes(root, MODULE, full_audit._observe_bytes(root, MODULE, '
   '(root/MODULE).read_bytes(), _operation=_operation), _operation=_operation, _inputs=_inputs, '
   "_input_owner=_input_owner)).decode('utf-8') if _inputs is None else\n",
   '            _typed_source.historical_text(root, MODULE, _inputs.text_utf8(_input_owner, root, '
   'MODULE), _operation=_operation, _inputs=_inputs, _input_owner=_input_owner))\n')),
 (892,
  893,
  ('def verify(root, *, _operation=None):\n',),
  ('def _verify_seed_body(root, *, _operation=None, _expected_raw=None):\n',)),
 (896,
  902,
  ('    text = ((root/MODULE).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   "_operation=_operation)).decode('utf-8')\n",),
  ('    current_raw = ((root/MODULE).read_bytes() if _operation is None else\n',
   '                   full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   '_operation=_operation))\n',
   '    if _expected_raw is not None:\n',
   '        require(type(_expected_raw) is bytes and current_raw == _expected_raw,\n',
   "                'Map observation changed before delegated verification')\n",
   '    text = _typed_source.historical_bytes(root, MODULE, current_raw, '
   "_operation=_operation).decode('utf-8')\n")),
 (903,
  921,
  ("        return verify_score(root, **({} if _operation is None else {'_operation': "
   '_operation}))\n',
   '    if sha(text) == FRONTIER_AFTER_SHA256:\n',
   '        return verify_frontier(root)\n',
   '    if sha(text) == SUPPORT_AFTER_SHA256:\n',
   '        return verify_support(root)\n',
   '    if sha(text) == OPTIONAL_AFTER_SHA256:\n',
   '        return verify_optional(root)\n',
   '    edge = verify_source(text, record)\n',
   '    if edge is None:\n',
   '        return None\n',
   "    _verify_bound_inputs(root, record, **({} if _operation is None else {'_operation': "
   '_operation}))\n',
   "    verify_premises(root, record, after=True, **({} if _operation is None else {'_operation': "
   '_operation}))\n',
   '    # A caller must not project a source different from the one just verified.\n',
   '    require(((root/MODULE).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   "_operation=_operation)).decode('utf-8') == text, 'Map changed during verification')\n"),
  ("        edge = verify_score(root, **({'_expected_raw': current_raw} if _operation is None else "
   "{'_operation': _operation}))\n",
   '    elif sha(text) == FRONTIER_AFTER_SHA256:\n',
   '        edge = verify_frontier(root, _expected_raw=current_raw)\n',
   '    elif sha(text) == SUPPORT_AFTER_SHA256:\n',
   '        edge = verify_support(root, _expected_raw=current_raw)\n',
   '    elif sha(text) == OPTIONAL_AFTER_SHA256:\n',
   '        edge = verify_optional(root, _expected_raw=current_raw)\n',
   '    else:\n',
   '        edge = verify_source(text, record)\n',
   '        if edge is None:\n',
   '            return None\n',
   "        _verify_bound_inputs(root, record, **({} if _operation is None else {'_operation': "
   '_operation}))\n',
   '        verify_premises(root, record, after=True, **({} if _operation is None else '
   "{'_operation': _operation}))\n",
   "    # Reconcile the dispatch observation as well as the delegated verifier's\n",
   '    # own capture; an equal historical projection cannot hide a physical swap.\n',
   '    final_raw = ((root/MODULE).read_bytes() if _operation is None else\n',
   '                 full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   '_operation=_operation))\n',
   "    require(final_raw == current_raw, 'Map changed during verification')\n")),
 (922,
  945,
  (),
  ('\n',
   '\n',
   '\n',
   'def _verify_standalone(root, *, _expected_raw=None):\n',
   '    """One fresh canonical invocation; historical inputs keep lazy admission."""\n',
   "    _operation, owns = full_audit._operation_enter(root, 'seed')\n",
   '    try:\n',
   '        result = _verify_seed_body(root, _operation=_operation, _expected_raw=_expected_raw)\n',
   '        if owns:\n',
   '            _operation.finish(root)\n',
   '        return result\n',
   '    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, '
   'AttributeError) as error:\n',
   '        full_audit._operation_fail(_operation, error)\n',
   '    finally:\n',
   '        if owns:\n',
   '            _operation.close()\n',
   '\n',
   '\n',
   'def verify(root, *, _operation=None, _expected_raw=None):\n',
   '    """Verify the exact edge, live arithmetic dependencies and regression input."""\n',
   '    if _operation is not None:\n',
   '        return _verify_seed_body(root, _operation=_operation, _expected_raw=_expected_raw)\n',
   '    return _verify_standalone(root, _expected_raw=_expected_raw)\n')),
 (953,
  955,
  ('    text = full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   "_operation=_operation).decode('utf-8')\n",),
  ('    current_raw = full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   '_operation=_operation)\n',
   '    text = _typed_source.historical_bytes(root, MODULE, current_raw, '
   "_operation=_operation).decode('utf-8')\n")),
 (960,
  962,
  ("    require(verify(root, **operation_args) is not None, 'after Map did not activate its "
   "reviewed edge')\n",
   '    require(full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   "_operation=_operation).decode('utf-8') == text, 'Map changed during reconstruction')\n"),
  ("    require(verify(root, **({'_expected_raw': current_raw} if _operation is None else "
   "operation_args)) is not None, 'after Map did not activate its reviewed edge')\n",
   '    require(full_audit._observe_bytes(root, MODULE, (root/MODULE).read_bytes(), '
   "_operation=_operation) == current_raw, 'Map changed during reconstruction')\n")),
 (980,
  987,
  ('    physical = ((Path(root)/MODULE).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, MODULE, (Path(root)/MODULE).read_bytes(), '
   '_operation=_operation))\n',),
  ('    current_raw = (Path(root)/MODULE).read_bytes()\n',
   '    if _operation is not None:\n',
   '        current_raw = full_audit._observe_bytes(root, MODULE, current_raw, '
   '_operation=_operation)\n',
   "    require(source.token_sha256(text) == source.token_sha256(current_raw.decode('utf-8')),\n",
   "            'unreviewed supplied Map source')\n",
   '    text = _typed_source.historical_text(root, MODULE, text, _operation=_operation)\n',
   '    physical = _typed_source.historical_bytes(root, MODULE, current_raw, '
   '_operation=_operation)\n')),
 (1000,
  1005,
  ("    require(verify(root, **({} if _operation is None else {'_operation': _operation})) is not "
   "None, 'after Map did not activate its reviewed edge')\n",
   '    require(((Path(root)/MODULE).read_bytes() if _operation is None else '
   'full_audit._observe_bytes(root, MODULE, (Path(root)/MODULE).read_bytes(), '
   '_operation=_operation)) == physical,\n',
   "            'Map changed during supplied-view verification')\n"),
  ("    require(verify(root, **({'_expected_raw': current_raw} if _operation is None else "
   "{'_operation': _operation})) is not None, 'after Map did not activate its reviewed edge')\n",
   '    final_raw = (Path(root)/MODULE).read_bytes()\n',
   '    if _operation is not None:\n',
   '        final_raw = full_audit._observe_bytes(root, MODULE, final_raw, '
   '_operation=_operation)\n',
   "    require(final_raw == current_raw, 'Map changed during supplied-view verification')\n"))),
    'source_contracts.py': ((10,
  11,
  ('from contextlib import contextmanager\n',),
  ('from contextlib import contextmanager, nullcontext\n',)),
 (169, 170, ('@lru_cache(maxsize=128)\n',), ('@lru_cache(maxsize=1024)\n',)),
 (235,
  236,
  ('        checked = text\n',),
  ('        checked = historical_text(root, path, text, **operation_args)\n',)),
 (238,
  239,
  ("                and token_sha256(text) != pins['groups'][group][path]):\n",),
  ("                and token_sha256(checked) != pins['groups'][group][path]):\n",)),
 (248,
  249,
  ("        if path == PREFIX + 'lane_refinement.mojo' and token_sha256(text) != "
   "pins['groups'][group][path]:\n",),
  ("        if path == PREFIX + 'lane_refinement.mojo' and token_sha256(checked) != "
   "pins['groups'][group][path]:\n",)),
 (258,
  259,
  ("        elif path == PREFIX + 'map.mojo' and token_sha256(text) != "
   "pins['groups'][group][path]:\n",),
  ("        elif path == PREFIX + 'map.mojo' and token_sha256(checked) != "
   "pins['groups'][group][path]:\n",)),
 (274,
  276,
  ('def verify_qualifiers(root, filename, text):\n', '    pins = read_pins(root)\n'),
  ('def verify_qualifiers(root, filename, text, *, _operation=None):\n',
   '    pins = read_pins(root, _operation=_operation)\n')),
 (277,
  278,
  ('    checked = text\n',),
  ('    checked = historical_text(root, PREFIX + filename, text, _operation=_operation)\n',)),
 (279,
  280,
  ("            and qualifier_sha256(text) != pins['qualifiers'][filename]):\n",),
  ("            and qualifier_sha256(checked) != pins['qualifiers'][filename]):\n",)),
 (285,
  286,
  ('            checked = full_audit.reviewed_text(root, PREFIX + filename, text)\n',),
  ('            checked = full_audit.reviewed_text(root, PREFIX + filename, text, '
   '_operation=_operation)\n',)),
 (290,
  369,
  (),
  ('\n',
   '\n',
   'def _typed_path(root, path):\n',
   '    relative = str(path)\n',
   "    if not relative.endswith('.mojo'):\n",
   '        return None\n',
   '    if Path(relative).is_absolute():\n',
   '        relative = Path(relative).relative_to(root).as_posix()\n',
   '    elif isinstance(path, Path):\n',
   '        # Callers passing root/path may use a non-dot relative checkout root.\n',
   '        # Canonical module strings remain relative to root, never prefix-stripped.\n',
   '        root_text = str(root)\n',
   "        if (root_text not in ('', '.') and not Path(root_text).is_absolute()\n",
   "                and '..' not in Path(root_text).parts and '..' not in path.parts\n",
   "                and relative.startswith(root_text + '/')):\n",
   '            relative = relative[len(root_text) + 1:]\n',
   '    return relative\n',
   '\n',
   '\n',
   'def typed_admission_scope(root):\n',
   '    """Create a synchronous, frame-owned admission scope for a public checker."""\n',
   '    if __package__:\n',
   '        from . import full_audit_cleanup_contracts as audit\n',
   '    else:\n',
   '        import full_audit_cleanup_contracts as audit\n',
   '    frame = sys._getframe(1)\n',
   "    if frame.f_locals.get('_operation') is not None or audit._cache_verify_frame(frame):\n",
   '        return nullcontext()\n',
   "    filename = frame.f_globals.get('__file__')\n",
   '    if (type(filename) is not str\n',
   '            or Path(filename).absolute().parent != Path(__file__).absolute().parent\n',
   '            or frame.f_code.co_name not in '
   'audit._public_admission_entries().get(Path(filename).name, ())):\n',
   '        return nullcontext()\n',
   "    if Path(filename).name == 'seed_count_contracts.py':\n",
   "        if frame.f_locals.get('_inputs') is not None:\n",
   '            return nullcontext()\n',
   '        parent = audit._public_admission_for(root)\n',
   "        if parent is not None and parent._state == 'active':\n",
   '            return nullcontext()\n',
   '    return audit._public_admission_scope(root, frame)\n',
   '\n',
   '\n',
   'def historical_text(root, path, text, *, _operation=None, _inputs=None, _input_owner=None):\n',
   '    """Expose a fixed historical view only after actual current admission.\n',
   '\n',
   '    Reads and owned observations stay physical. The conditioned semantic\n',
   '    successor, rather than old byte-identity claims, binds the new graph.\n',
   '    """\n',
   '    relative = _typed_path(root, path)\n',
   '    if relative is None:\n',
   '        return text\n',
   '    if __package__:\n',
   '        from . import typed_boundary_contracts as typed\n',
   '    else:\n',
   '        import typed_boundary_contracts as typed\n',
   '    if relative not in typed.EDGES:\n',
   '        return text\n',
   '    if __package__:\n',
   '        from . import full_audit_cleanup_contracts as audit\n',
   '    else:\n',
   '        import full_audit_cleanup_contracts as audit\n',
   '    return audit.reviewed_typed_text(root, relative, text, _operation=_operation,\n',
   '                                     _inputs=_inputs, _input_owner=_input_owner)\n',
   '\n',
   '\n',
   'def historical_bytes(root, path, raw, *, _operation=None, _inputs=None, _input_owner=None):\n',
   '    """Preserve physical reads before one named historical-source projection."""\n',
   '    relative = _typed_path(root, path)\n',
   '    if relative is None:\n',
   '        return raw\n',
   '    if __package__:\n',
   '        from . import typed_boundary_contracts as typed\n',
   '    else:\n',
   '        import typed_boundary_contracts as typed\n',
   '    if relative not in typed.EDGES:\n',
   '        return raw\n',
   "    require(type(raw) is bytes, 'historical input is not physical bytes')\n",
   "    return historical_text(root, relative, raw.decode('utf-8'), _operation=_operation,\n",
   "                           _inputs=_inputs, _input_owner=_input_owner).encode('utf-8')\n"))),
}
# END REVIEWED #333 CHECKER SOURCE INVERSE
class BoundedOwnerDistinctMechanismControls(unittest.TestCase):
    setUp = BoundedOwnerCurrentControls.setUp
    audit = BoundedOwnerCurrentControls.audit
    coverage = BoundedOwnerCurrentControls.coverage
    assert_closed = BoundedOwnerCurrentControls.assert_closed
    assert_one_owner = BoundedOwnerCurrentControls.assert_one_owner
    assert_public_coherence_error = BoundedOwnerCurrentControls.assert_public_coherence_error

    _SOURCE_SHA256 = {
        'accepted_successor_contracts.py': '7a3accef16e213e0c68f366e0349ba7010c997ddf4559817d775269e0278cf18',
        'cache_key_contracts.py': '4dd8d16b6d7f1d415631cde453f9270cfe58fd6cdf1cd382e4e7cdde4ea076e2',
        'coverage_followup_contracts.py': '37258b36b2a1d2c5b0e5959efb764f7ba4c0c3271467345c229f302dc7c192a0',
        'coverage_loop_proofs.py': 'c70c73fad4702cd41eeed5273dec6382c7be6111cd28d47daba195c2dd10c4be',
        'full_audit_cleanup_contracts.py': '091df2a89a23f27b411477e61cb4532673baa1e8280c276cd6440a29af6ccca1',
        'grouped_y_finiteness_contracts.py': 'ebb2b381263ffde628fda521393cbdc115e3f39db070d42e4790b75cd4e31307',
        'raw_cut_inverse_contracts.py': 'ca1cb6bbba485f994a15a4771774383fc8a7f0d4673e028f7785aca109df73e5',
        'seed_count_contracts.py': '099269aecd67f590ddee6a10e7ebddb83541401559312112b129b0aa2abece18',
        'source_contracts.py': '857dd399291611dd35e11adbbdde0fca03ed4ff4277eec54ed3ec5815bbaf791',
    }

    def _site(self, function, line, expression):
        """Bind a primitive to original globals, code family and AST address."""
        from types import CodeType
        original = inspect.unwrap(function)
        path = Path(original.__code__.co_filename)
        raw = path.read_bytes()
        predecessor, line_mapping = _checker_source_predecessor(path.name, raw)
        old_tree = ast.parse(predecessor)
        tree = ast.parse(raw)
        if line == 'station-census':
            self.assertEqual((path.name, original.__name__, expression),
                ('seed_count_contracts.py', 'verify_score_caller_inventory',
                 '_inputs.observe_bytes(_input_owner, root, MODULE)'))
            node = next(item for item in tree.body if isinstance(item, ast.FunctionDef)
                        and item.name == original.__name__)
            clause = _station_census_read_contract(node)
            first, last = clause.lineno, clause.end_lineno
        elif line == 'typed-construction-discovery-catch':
            # This exact current helper is an enumerated addition in the
            # authenticated source inverse, so it has no predecessor line.
            self.assertEqual((path.name, original.__name__, expression),
                ('coverage_loop_proofs.py', '_typed_construction_boundary_loops',
                 'cleanup._operation_fail(_operation, error)'))
            node = next(item for item in tree.body if isinstance(item, ast.FunctionDef)
                        and item.name == original.__name__)
            handlers = [item for item in ast.walk(node) if isinstance(item, ast.ExceptHandler)
                        and ast.unparse(item.type) == '(OSError, UnicodeError, ValueError)'
                        and item.name == 'error']
            self.assertEqual(len(handlers), 1)
            calls = [item for item in ast.walk(handlers[0]) if isinstance(item, ast.Call)
                     and ast.unparse(item) == expression]
            self.assertEqual(len(calls), 1)
            first, last = calls[0].lineno, calls[0].end_lineno
        else:
            old_bodies = [node for node in ast.walk(old_tree) if isinstance(node, ast.FunctionDef)
                          and node.name == original.__name__]
            old_calls = [node for body in old_bodies for node in ast.walk(body)
                         if isinstance(node, ast.Call) and node.lineno == line
                         and ast.unparse(node) == expression]
            self.assertEqual(len(old_calls), 1, ('frozen predecessor site', path.name, line, expression))
            first, last = line_mapping[line]
        current_expression = (_CURRENT_LOCAL_S_REQUIRE if expression.startswith(
            'require(source.token_sha256(text) == source.token_sha256(_inputs.text_default') else expression)
        current_key = ast_key(ast.parse(current_expression, mode='eval').body)
        # Compilation creates code only; it never imports or executes a gate.
        compiled = compile(raw, str(path), 'exec', dont_inherit=True,
                           optimize=sys.flags.optimize)
        candidates = []
        def compiled_functions(code):
            if (code.co_name == original.__code__.co_name
                    and code.co_firstlineno == original.__code__.co_firstlineno):
                candidates.append(code)
            for item in code.co_consts:
                if isinstance(item, CodeType):
                    compiled_functions(item)
        compiled_functions(compiled)
        self.assertEqual(len(candidates), 1)
        self.assertEqual(original.__code__, candidates[0], 'loaded checker code differs from source')
        self.assertEqual(original.__code__.co_filename, candidates[0].co_filename)
        bodies = [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)
                  and node.name == original.__name__
                  and node.lineno == original.__code__.co_firstlineno]
        self.assertEqual(len(bodies), 1)
        calls = [node for node in ast.walk(bodies[0]) if isinstance(node, ast.Call)
                 and first <= node.lineno <= last and ast_key(node) == current_key]
        self.assertEqual(len(calls), 1, (path.name, line, first, last, expression))
        call = calls[0]
        codes = []
        def retain(code):
            codes.append((code, tuple(code.co_positions())))
            for item in code.co_consts:
                if isinstance(item, CodeType):
                    retain(item)
        retain(original.__code__)
        def matches(frame):
            if frame is None or frame.f_globals is not original.__globals__:
                return False
            positions = next((rows for code, rows in codes if frame.f_code is code), None)
            offset = frame.f_lasti // 2
            if positions is None or not 0 <= offset < len(positions):
                return False
            first, last, left, right = positions[offset]
            return (None not in (first, last, left, right)
                    and (call.lineno, call.col_offset) <= (first, left)
                    and (last, right) <= (call.end_lineno, call.end_col_offset))
        return matches

    @staticmethod
    def _frame(function, frame):
        original = inspect.unwrap(function)
        while frame is not None:
            if frame.f_globals is original.__globals__ and frame.f_code is original.__code__:
                return frame
            frame = frame.f_back
        return None

    def _followup_route(self, frame):
        """Source-derived propagation route, with no source/accepted catch."""
        found = self._frame(followup.verify, frame)
        return (found is not None
                and self._frame(followup.accepts_predecessor_source, found.f_back) is found.f_back
                and self._frame(invariant.verify, found.f_back.f_back) is found.f_back.f_back)

    def _cache_followup_route(self, cache, frame):
        found = self._frame(cache.verify, frame)
        if found is None:
            return False
        for function in (cache.predecessor_source, cache.reviewed_text,
                         followup._source_view, followup.verify):
            found = found.f_back
            if found is None or self._frame(function, found) is not found:
                return False
        return self._followup_route(found)

    def _active(self, function, frame, core=cleanup):
        found = self._frame(function, frame)
        operation = found.f_locals.get('_operation') if found is not None else None
        return (operation if type(operation) is core._InvariantInputs
                and operation._state == 'active' and not operation._capturing else None)

    def _assert_refused(self, events, operation, reason, core=cleanup, *, finalized=False):
        self.assertEqual(events['admissions'], [operation])
        self.assertEqual(events['finalizers'], [operation] if finalized else [])
        self.assertTrue(operation._failed)
        self.assertEqual(operation._failure_reason, reason)
        self.assert_closed(operation, core)

    def _assert_direct(self, error, operation, reason, core=cleanup):
        self.assertIs(type(error), core._OperationCoherenceError)
        self.assertEqual(str(error), reason)
        self.assertEqual(operation._failure_reason, reason)
        self.assertIs(type(error.__cause__), core.ContractError)
        self.assertEqual(str(error.__cause__), reason)

    def _assert_lease_closed(self, lease):
        self.assertIs(type(lease), cleanup._BorrowedCacheInputs)
        self.assertEqual(lease._state, 'closed')
        self.assertFalse(lease._raw)
        self.assertIsNone(lease._record_raw)
        self.assertIsNone(lease._operation)
        self.assertIsNone(lease._owner_frame)
        self.assertFalse(lease._known)
        self.assertFalse(lease._production)

    @contextmanager
    def _no_marked_semantics(self, marked):
        """Keep admission's parser identities until the exact marked read."""
        from contextlib import ExitStack
        from functools import wraps
        with ExitStack() as stack:
            armed = False
            def arm():
                nonlocal armed
                self.assertFalse(armed, 'semantic sinks armed more than once')
                self.assertEqual(marked, [], 'semantic sinks armed after marked publication')
                for module, name in ((source, 'token_sha256'), (source, 'tokens'), (json, 'loads')):
                    original = getattr(module, name)
                    def install(original):
                        @wraps(original)
                        def checked(value, *args, **kwargs):
                            self.assertFalse(any(value is item for item in marked),
                                             'marked observation reached semantic sink')
                            return original(value, *args, **kwargs)
                        return checked
                    stack.enter_context(patch.object(module, name, install(original)))
                armed = True
            try:
                yield arm
            finally:
                self.assertEqual(armed, bool(marked),
                                 'semantic sink arming and marked publication differ')

    def test_shared_helper_local_final_reread_rejects_and_recovers(self):
        """Exercise the new local theorem seam without fabricating an owner."""
        from functools import wraps
        loops, core = self.coverage()
        module = 'extensions/carla/lane_distance'
        path = 'extensions/carla/curve_distance.mojo'
        physical = (self.root/path).read_bytes()
        site = self._site(loops._reviewed_dependency_hashes, 959, 'path.read_bytes()')
        baseline = loops.reviewed_nonempty_loops(self.root, module)
        self.assertEqual(set(baseline), {50})
        self.assertEqual(baseline[50]['dependency_sha256'][path],
                         hashlib.sha256(physical).hexdigest())
        for fault in ('changed', 'io'):
            with self.subTest(fault=fault):
                original_read = Path.read_bytes
                original_observe = loops._coverage_observe_bytes
                injected, marked, observed = [], [], []
                failure = PermissionError('shared-helper final reread denied')

                @wraps(original_read)
                def read(actual, *args, **kwargs):
                    value = original_read(actual, *args, **kwargs)
                    frame = sys._getframe(1)
                    if site(frame) and actual == self.root/path:
                        self.assertEqual(injected, [])
                        self.assertIsNone(frame.f_locals['_operation'])
                        self.assertEqual(frame.f_locals['raw'], physical)
                        self.assertEqual(value, physical)
                        injected.append(frame)
                        if fault == 'io':
                            raise failure
                        value += b'\n# changed final helper read\n'
                        marked.append(value)
                    return value

                @wraps(original_observe)
                def observe(root, name, value, *, _operation=None):
                    if marked and value is marked[0]:
                        self.assertEqual((root, name), (self.root, path))
                        self.assertIsNone(_operation)
                        self.assertIs(sys._getframe(1), injected[0])
                        observed.append(value)
                    return original_observe(root, name, value, _operation=_operation)

                with self.audit(core) as events, patch.object(Path, 'read_bytes', read), \
                        patch.object(loops, '_coverage_observe_bytes', observe):
                    result = loops.reviewed_nonempty_loops(self.root, module)
                self.assertEqual(result, {})
                self.assertEqual(len(injected), 1)
                self.assertEqual(observed, marked)
                self.assertEqual(len(observed), 1 if fault == 'changed' else 0)
                self.assertEqual(events['admissions'], [])
                self.assertEqual(events['finalizers'], [])
                self.assertIs(Path.read_bytes, original_read)
                self.assertEqual((self.root/path).read_bytes(), physical)
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, module), baseline)
                print('COVERAGE_HELPER_FINAL_CONTROL ' + json.dumps({
                    'fault': fault, 'module': module, 'path': path,
                    'site': 'shared-helper-source-final', 'owned': False,
                    'reached': len(injected), 'refused': True, 'restored': True},
                    sort_keys=True))

    def test_distinct_pending_observation_reconciles_at_real_publication(self):
        from functools import wraps
        path = 'extensions/carla/curve_rounded_line.mojo'
        physical = (self.root/path).read_bytes()
        site = self._site(accepted._verify_current_for_pin_pair, 162, '(root / path).read_text()')
        original_read, original_match = Path.read_text, cleanup._InvariantInputs._match
        original_token = source.token_sha256
        marked, injected, reconciled, token_uses = [], [], [], []
        @wraps(original_read)
        def read(actual, *args, **kwargs):
            value = original_read(actual, *args, **kwargs)
            frame = sys._getframe(1)
            if site(frame) and actual == self.root/path and not injected:
                operation = frame.f_locals['_operation']
                self.assertIs(type(operation), cleanup._InvariantInputs)
                self.assertEqual(operation._state, 'pending')
                self.assertFalse(operation._capturing)
                injected.append(operation)
                value += '\n# queued observation B\n'
                marked.append(value)
            return value
        @wraps(original_token)
        def token(value, *args, **kwargs):
            if marked and value is marked[0]:
                frame = sys._getframe(1)
                self.assertIs(frame.f_globals, vars(cleanup))
                self.assertEqual(injected[0]._state, 'pending')
                token_uses.append(frame.f_code)
            return original_token(value, *args, **kwargs)
        @wraps(original_match)
        def match(operation, root, name, value, mode):
            if marked and value is marked[0]:
                caller = sys._getframe(1)
                self.assertIs(self._frame(cleanup._InvariantInputs._publish, caller), caller)
                self.assertIs(operation, injected[0])
                self.assertEqual((name, mode), (path, 'default'))
                self.assertEqual(operation._state, 'active')
                self.assertTrue(operation._capturing)
                self.assertIn((path, value, mode), operation._observations)
                reconciled.append(operation)
            return original_match(operation, root, name, value, mode)
        with self.audit() as events, patch.object(Path, 'read_text', read), \
                patch.object(source, 'token_sha256', token), \
                patch.object(cleanup._InvariantInputs, '_match', match):
            with self.assertRaises(ValueError) as raised:
                invariant.verify(self.root)
        self.assertEqual(len(injected), 1)
        operation = injected[0]
        self.assertEqual(reconciled, [operation])
        # Typed provenance admission now happens before the accepted semantic
        # comparison. Only its two supplied-view checks and the checked-raw
        # observation may tokenize B before exact queued publication refuses it.
        self.assertEqual(token_uses, [cleanup.reviewed_typed_text.__code__,
                                      cleanup.reviewed_typed_text.__code__,
                                      cleanup._observe_text.__code__])
        self.assertEqual(events['records'], [])
        self.assert_public_coherence_error(raised.exception, operation)
        self._assert_refused(events, operation,
            'full-audit cleanup successor: consumed operation text changed: ' + path)
        self.assertEqual((self.root/path).read_bytes(), physical)

    def test_distinct_grouped_y_batch_reads_all_five_before_observation_refusal(self):
        from functools import wraps
        import grouped_y_finiteness_contracts as grouped
        site = self._site(grouped.verify, 31, '(root / p).read_text()')
        path = next(iter(grouped.EXPECTED))
        physical = (self.root/path).read_bytes()
        original_read, original_verify = Path.read_text, grouped.verify_text
        marked, injected, reads, batches = [], [], [], []
        @wraps(original_read)
        def read(actual, *args, **kwargs):
            value = original_read(actual, *args, **kwargs)
            frame = sys._getframe(1)
            operation = self._active(grouped.verify, frame)
            if (site(frame) and operation is not None
                    and self._frame(accepted._verify_current_for_pin_pair,
                                    self._frame(grouped.verify, frame).f_back)
                    is self._frame(grouped.verify, frame).f_back):
                body = self._frame(grouped.verify, frame)
                if not batches:
                    batches.append(body)
                if body is batches[0]:
                    reads.append(actual.relative_to(self.root).as_posix())
                    if actual == self.root/path:
                        self.assertEqual(injected, [])
                        injected.append(operation)
                        value += '\n# grouped batch B\n'
                        arm_semantic_sinks()
                        marked.append(value)
            return value
        @wraps(original_verify)
        def verify(modules):
            self.assertFalse(any(value is item for value in modules.values() for item in marked))
            return original_verify(modules)
        with self.audit() as events, patch.object(Path, 'read_text', read), \
                patch.object(grouped, 'verify_text', verify), self._no_marked_semantics(marked) as arm_semantic_sinks:
            with self.assertRaises(ValueError) as raised:
                invariant.verify(self.root)
        self.assertEqual(len(injected), 1)
        self.assertEqual(reads, list(grouped.EXPECTED))
        operation = injected[0]
        self.assert_public_coherence_error(raised.exception, operation)
        self._assert_refused(events, operation,
            'full-audit cleanup successor: consumed operation text changed: ' + path)
        self.assertTrue(events['records'])
        self.assertEqual((self.root/path).read_bytes(), physical)

    def test_distinct_raw_cut_second_json_text_binds_original_checked_bytes(self):
        from functools import wraps
        import raw_cut_inverse_contracts as raw_cut
        path = 'tools/carla_lane_oracle/curve-support-dispatch-migration.json'
        physical = (self.root/path).read_bytes()
        site = self._site(raw_cut.verify_premises, 66,
                         "(root / 'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_text()")
        original = Path.read_text
        marked, injected, checked = [], [], []
        @wraps(original)
        def read(actual, *args, **kwargs):
            value = original(actual, *args, **kwargs)
            frame = sys._getframe(1)
            operation = self._active(raw_cut.verify_premises, frame)
            if (site(frame) and actual == self.root/path and operation is not None
                    and self._followup_route(frame)
                    and self._frame(raw_cut.verify, frame.f_back) is frame.f_back
                    and self._frame(followup.verify, frame.f_back.f_back) is frame.f_back.f_back
                    and not injected):
                self.assertEqual(frame.f_locals['predecessor_payload'], physical)
                self.assertEqual(hashlib.sha256(physical).hexdigest(),
                                 frame.f_locals['record']['predecessor_migration_sha256'])
                checked.append(frame.f_locals['predecessor_payload'])
                injected.append(operation)
                value = ' \n' + value
                arm_semantic_sinks()
                marked.append(value)
            return value
        with self.audit() as events, patch.object(Path, 'read_text', read), \
                self._no_marked_semantics(marked) as arm_semantic_sinks:
            with self.assertRaises(cleanup._OperationCoherenceError) as raised:
                invariant.verify(self.root)
        self.assertEqual(len(injected), 1)
        self.assertEqual(checked, [physical])
        operation = injected[0]
        reason = 'full-audit cleanup successor: checked physical and supplied views differ: ' + path
        self._assert_direct(raised.exception, operation, reason)
        self._assert_refused(events, operation, reason)
        self.assertEqual((self.root/path).read_bytes(), physical)

    def test_distinct_explicit_utf8_pins_and_group_refuse_before_semantics(self):
        from functools import wraps
        import winner_sign_contracts as winner
        cases = ((source.read_pins, 202, "(root / PINS).read_text(encoding='utf-8')", source.PINS),
                 (source.verify_group, 234, "(root / path).read_text(encoding='utf-8')",
                  'extensions/carla/curve_sum2.mojo'))
        for function, line, expression, path in cases:
            with self.subTest(role=function.__name__):
                site = self._site(function, line, expression)
                original, physical = Path.read_text, (self.root/path).read_bytes()
                marked, injected, modes = [], [], []
                observe = cleanup._operation_observe
                @wraps(original)
                def read(actual, *args, **kwargs):
                    value = original(actual, *args, **kwargs)
                    frame = sys._getframe(1)
                    operation = self._active(function, frame)
                    group = self._frame(source.verify_group, frame)
                    if (site(frame) and actual == self.root/path and operation is not None
                            and group is not None and group.f_locals['group'] == 'canonical_accumulation'
                            and self._frame(winner.verify, group.f_back) is group.f_back and not injected):
                        self.assertEqual(kwargs, {'encoding': 'utf-8'})
                        self.assertEqual(args, ())
                        injected.append(operation)
                        value = (' \n' + value if function is source.read_pins
                                 else value + '\n# UTF8 group B\n')
                        arm_semantic_sinks()
                        marked.append(value)
                    return value
                @wraps(observe)
                def observed(operation, root, name, value, mode):
                    if marked and value is marked[0]:
                        self.assertIs(operation, injected[0])
                        self.assertEqual(name, path)
                        modes.append(mode)
                    return observe(operation, root, name, value, mode)
                with self.audit() as events, patch.object(Path, 'read_text', read), \
                        patch.object(cleanup, '_operation_observe', observed), self._no_marked_semantics(marked) as arm_semantic_sinks:
                    with self.assertRaises(cleanup._OperationCoherenceError) as raised:
                        winner.verify(self.root)
                self.assertEqual(len(injected), 1)
                self.assertEqual(modes, ['physical'])
                operation = injected[0]
                reason = 'full-audit cleanup successor: consumed operation text changed: ' + str(path)
                self._assert_direct(raised.exception, operation, reason)
                self._assert_refused(events, operation, reason)
                self.assertEqual((self.root/path).read_bytes(), physical)

    def _lease_sites(self, cache, seed):
        # Keep the four original IDs; the new census observation is slot 5
        # and executes between slots 2 and 3.
        return (
            self._site(cache.inventory, 106, '_inputs.observe_bytes(_input_owner, root, rel.as_posix())'),
            self._site(seed.verify_score, 649, '_inputs.observe_bytes(_input_owner, root, MODULE)'),
            self._site(seed.verify_score, 684, '_inputs.observe_bytes(_input_owner, root, MODULE)'),
            self._site(cache.inventory, 150, '_inputs.observe_bytes(_input_owner, root, rel.as_posix())'),
            self._site(seed.verify_score_caller_inventory, 'station-census',
                       '_inputs.observe_bytes(_input_owner, root, MODULE)'),
        )

    @staticmethod
    def _lease_position(frame, sites):
        while frame is not None:
            for position, matches in enumerate(sites, 1):
                if matches(frame):
                    return position
            frame = frame.f_back
        return None

    def test_distinct_borrowed_map_observations_delegate_all_five_faults(self):
        from functools import wraps
        import os
        import cache_key_contracts as cache
        import seed_count_contracts as seed
        path = 'extensions/carla/map.mojo'
        physical = (self.root/path).read_bytes()
        sites = self._lease_sites(cache, seed)
        primitive = self._site(cleanup._CacheInputs.observe_bytes, 1205,
                               '_regular(root, path).read_bytes()')
        sequence = (1, 2, 5, 3, 4)
        for fault in ('changed', 'foreign_bytes', 'io', 'context', 'fourth', 'census'):
            with self.subTest(fault=fault):
                injected, selected, successes, attempts, equality = [], [], [], [], []
                failure = PermissionError('distinct borrowed Map read denied')
                original_read = Path.read_bytes
                original_observe = cleanup._BorrowedCacheInputs.observe_bytes
                original_check = cleanup._BorrowedCacheInputs._check
                class ForeignBytes(bytes):
                    def __eq__(self, other):
                        equality.append(other)
                        raise AssertionError('non-builtin bytes reached equality')
                def choose(lease, frame):
                    position = self._lease_position(frame, sites)
                    if (type(lease) is cleanup._BorrowedCacheInputs
                            and self._cache_followup_route(cache, frame) and position is not None):
                        if not selected:
                            self.assertEqual(position, 1)
                            self.assertEqual(lease._operation._state, 'active')
                            selected.append((lease, lease._operation))
                        if lease is selected[0][0]:
                            return position
                    return None
                @wraps(original_observe)
                def observe(lease, owner, root, name):
                    position = choose(lease, sys._getframe(1)) if name == path else None
                    if position is not None:
                        attempts.append((lease, position))
                    value = original_observe(lease, owner, root, name)
                    if position is not None:
                        self.assertIs(type(value), bytes)
                        self.assertEqual(value, physical)
                        successes.append((lease, position, value))
                    return value
                @wraps(original_read)
                def read(actual, *args, **kwargs):
                    value = original_read(actual, *args, **kwargs)
                    frame = sys._getframe(1)
                    if primitive(frame) and actual == self.root/path and fault != 'context':
                        lease = frame.f_locals['self']
                        position = choose(lease, frame)
                        target = 4 if fault == 'fourth' else 5 if fault == 'census' else 1
                        if position == target and not injected:
                            self.assertEqual(value, physical)
                            if fault in ('fourth', 'census'):
                                self.assertEqual([(view is lease, slot, data == physical)
                                                  for view, slot, data in successes],
                                                 [(True, slot, True) for slot in sequence[:sequence.index(target)]])
                            injected.append((lease, position))
                            if fault == 'io':
                                raise failure
                            if fault == 'foreign_bytes':
                                return ForeignBytes(value)
                            return value + b'\n# borrowed Map B\n'
                    return value
                @wraps(original_check)
                def check(lease, owner, root):
                    frame = sys._getframe(1)
                    base = self._frame(cleanup._CacheInputs.observe_bytes, frame)
                    if (fault == 'context' and not injected and base is not None
                            and base.f_locals['path'] == path
                            and self._frame(cleanup._CacheInputs.raw, frame) is frame
                            and choose(lease, frame) == 1):
                        injected.append((lease, 1))
                        before = Path.cwd()
                        self.assertNotEqual(before, self.root)
                        try:
                            os.chdir(self.root)
                            return original_check(lease, owner, root)
                        finally:
                            os.chdir(before)
                    return original_check(lease, owner, root)
                with self.audit() as events, patch.object(Path, 'read_bytes', read), \
                        patch.object(cleanup._BorrowedCacheInputs, 'observe_bytes', observe), \
                        patch.object(cleanup._BorrowedCacheInputs, '_check', check):
                    with self.assertRaises(cleanup._OperationCoherenceError) as raised:
                        invariant.verify(self.root)
                self.assertEqual(len(selected), 1)
                lease, operation = selected[0]
                target = 4 if fault == 'fourth' else 5 if fault == 'census' else 1
                self.assertEqual(injected, [(lease, target)])
                self.assertEqual(attempts, [(lease, slot) for slot in sequence[:sequence.index(target) + 1]])
                self.assertEqual([(view, slot) for view, slot, value in successes],
                                 [(lease, slot) for slot in sequence[:sequence.index(target)]])
                self.assertEqual(equality, [])
                detail = ('cache input root or working directory changed' if fault == 'context'
                          else ('unreadable owned input: ' if fault == 'io' else 'owned input changed: ') + path)
                reason = 'full-audit cleanup successor: ' + detail
                self._assert_direct(raised.exception, operation, reason)
                if fault == 'io':
                    self.assertIs(raised.exception.__cause__.__cause__, failure)
                else:
                    self.assertIsNone(raised.exception.__cause__.__cause__)
                self._assert_refused(events, operation, reason)
                self._assert_lease_closed(lease)
                self.assertEqual((self.root/path).read_bytes(), physical)

    def test_distinct_borrowed_map_local_supplied_text_preserves_its_own_contract(self):
        from functools import wraps
        import cache_key_contracts as cache
        import seed_count_contracts as seed
        path = 'extensions/carla/map.mojo'
        physical = (self.root/path).read_bytes()
        site = self._site(cache.inventory, 103, 'path.read_text()')
        local_require = self._site(cache.inventory, 113,
            "require(source.token_sha256(text) == source.token_sha256(_inputs.text_default(_input_owner, root, rel.as_posix())) == seed_count.score_family_token_sha256(hashlib.sha256(physical).hexdigest()), 'unreviewed supplied score-helper source')")
        sites = self._lease_sites(cache, seed)
        for fault in ('comment', 'tokens', 'io'):
            with self.subTest(fault=fault):
                injected, selected, compared, observations, projected = [], [], [], [], []
                failure = OSError('distinct local supplied Map read denied')
                original_read, original_require = Path.read_text, cache.require
                original_observe = cleanup._BorrowedCacheInputs.observe_bytes
                original_projection = seed.score_family_predecessor_source
                @wraps(original_read)
                def read(actual, *args, **kwargs):
                    value = original_read(actual, *args, **kwargs)
                    frame = sys._getframe(1)
                    if site(frame) and actual == self.root/path and self._cache_followup_route(cache, frame) and not injected:
                        lease = frame.f_locals['_inputs']
                        self.assertIs(type(lease), cleanup._BorrowedCacheInputs)
                        self.assertEqual(lease._operation._state, 'active')
                        selected.append((lease, lease._operation))
                        injected.append(fault)
                        if fault == 'io':
                            raise failure
                        return value + ('\n# local supplied comment B\n' if fault == 'comment'
                                        else '\nvar distinct_unreviewed_map_token = 1\n')
                    return value
                @wraps(original_require)
                def require(condition, message):
                    frame = sys._getframe(1)
                    if (selected and local_require(frame)
                            and frame.f_locals['_inputs'] is selected[0][0]):
                        compared.append(condition)
                    return original_require(condition, message)
                @wraps(original_observe)
                def observe(lease, owner, root, name):
                    position = self._lease_position(sys._getframe(1), sites)
                    value = original_observe(lease, owner, root, name)
                    if selected and lease is selected[0][0] and name == path and position is not None:
                        self.assertEqual(value, physical)
                        observations.append(position)
                    return value
                @wraps(original_projection)
                def projection(text):
                    frame = self._frame(cache.inventory, sys._getframe(1))
                    if selected and frame is not None and frame.f_locals['_inputs'] is selected[0][0]:
                        projected.append(text)
                    return original_projection(text)
                with self.audit() as events, patch.object(Path, 'read_text', read), \
                        patch.object(cache, 'require', require), \
                        patch.object(cleanup._BorrowedCacheInputs, 'observe_bytes', observe), \
                        patch.object(seed, 'score_family_predecessor_source', projection):
                    if fault == 'comment':
                        result = invariant.verify(self.root)
                    else:
                        with self.assertRaises(cache.ContractError) as raised:
                            invariant.verify(self.root)
                self.assertEqual(injected, [fault])
                self.assertEqual(len(selected), 1)
                lease, operation = selected[0]
                if fault == 'comment':
                    self.assertEqual(len(result['sources']), 4)
                    self.assertEqual(compared, [True])
                    self.assertEqual(observations, [1, 2, 5, 3, 4])
                    self.assertTrue(projected)
                    self.assertIs(self.assert_one_owner(events, 'invariant'), operation)
                else:
                    self.assertIs(type(raised.exception), cache.ContractError)
                    self.assertEqual(events['admissions'], [operation])
                    self.assertEqual(events['finalizers'], [])
                    self.assertEqual(compared, [False] if fault == 'tokens' else [])
                    self.assertEqual(observations, [1] if fault == 'tokens' else [])
                    self.assertEqual(projected, [])
                    self.assertEqual(str(raised.exception), 'cache-key successor: ' + (
                        'unreviewed supplied score-helper source' if fault == 'tokens'
                        else 'unreadable owned Map view'))
                    self.assertIs(raised.exception.__cause__, failure if fault == 'io' else None)
                    self.assert_closed(operation)
                self._assert_lease_closed(lease)
                self.assertEqual((self.root/path).read_bytes(), physical)

    def test_distinct_fresh_production_and_known_discoveries_refuse_four_faults(self):
        from functools import wraps
        loops, core = self.coverage()
        from carla_lane_oracle import seed_count_contracts as seed
        production_site = self._site(seed.verify_score_caller_inventory, 542,
                                     'guard.production_mojo_paths(root)')
        known_site = self._site(loops._construction_boundary_callers, 1220,
                                'cache_key.input_paths(Path(root))')
        production_catch = self._site(core._operation_production_paths, 1541,
                                      '_operation_fail(_operation, error)')
        known_catch = self._site(loops._typed_construction_boundary_loops,
                                 'typed-construction-discovery-catch',
                                 'cleanup._operation_fail(_operation, error)')
        omitted = 'extensions/carla/cameras.mojo'
        added = 'extensions/carla/distinct_unlisted_discovery.mojo'
        self.assertNotIn('_winner_seed_update_score', (self.root/omitted).read_text())
        self.assertFalse((self.root/added).exists())
        for fault in ('production_omit', 'production_io', 'known_add', 'known_io'):
            with self.subTest(fault=fault):
                production = fault.startswith('production')
                module = seed.guard if production else loops.cache_key
                name = 'production_mojo_paths' if production else 'input_paths'
                original = getattr(module, name)
                original_fail, original_discovery = core._operation_fail, core._InvariantInputs._discovery
                injected, selected, yielded, exhausted, comparisons, caught = [], [], [], [], [], []
                failure = OSError('distinct ' + fault + ' iterator denied')
                site = production_site if production else known_site
                function = seed.verify_score_caller_inventory if production else loops._construction_boundary_callers
                @wraps(original)
                def discovered(root, *args, **kwargs):
                    iterator = original(root, *args, **kwargs)
                    frame = sys._getframe(1)
                    operation = self._active(function, frame, core)
                    if not site(frame) or operation is None or selected:
                        return iterator
                    self.assertEqual(Path(root), self.root)
                    if production:
                        self.assertIsNone(frame.f_locals['_inputs'])
                    selected.append(operation)
                    def changed():
                        for path in iterator:
                            relative = path.relative_to(self.root).as_posix() if production else path.as_posix()
                            yielded.append(relative)
                            if fault.endswith('_io') and not injected:
                                injected.append(fault)
                                raise failure
                            if fault == 'production_omit' and relative == omitted:
                                self.assertEqual(injected, [])
                                injected.append(fault)
                                continue
                            yield path
                        exhausted.append(True)
                        if fault == 'known_add':
                            self.assertEqual(injected, [])
                            injected.append(fault)
                            yield Path(added)
                    return changed()
                @wraps(original_discovery)
                def discovery(operation, root, paths, kind):
                    if selected and operation is selected[0] and injected:
                        comparisons.append((kind, paths))
                    return original_discovery(operation, root, paths, kind)
                @wraps(original_fail)
                def fail(operation, error):
                    if error is failure:
                        self.assertIs(operation, selected[0])
                        self.assertTrue((production_catch if production else known_catch)(sys._getframe(1)))
                        caught.append(error)
                    try:
                        return original_fail(operation, error)
                    except core._OperationCoherenceError as refused:
                        if error is failure:
                            self.assertIs(type(refused), core._OperationCoherenceError)
                            self.assertIs(refused.__cause__, failure)
                        raise
                with self.audit(core) as events, patch.object(module, name, discovered), \
                        patch.object(core._InvariantInputs, '_discovery', discovery), \
                        patch.object(core, '_operation_fail', fail):
                    result = loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map')
                self.assertEqual(result, {})
                self.assertEqual(injected, [fault])
                self.assertEqual(len(selected), 1)
                operation = selected[0]
                self.assertTrue(yielded)
                if fault.endswith('_io'):
                    self.assertEqual(caught, [failure])
                    self.assertEqual(exhausted, [])
                    self.assertEqual(comparisons, [])
                    reason = str(failure)
                else:
                    self.assertEqual(caught, [])
                    self.assertEqual(exhausted, [True])
                    expected = set(yielded)
                    if production:
                        self.assertEqual(yielded.count(omitted), 1)
                        expected.remove(omitted)
                    else:
                        self.assertNotIn(added, yielded)
                        expected = {path for path in expected if Path(path).suffix == '.mojo'} | {added}
                    kind = 'production' if production else 'known'
                    self.assertEqual(comparisons, [(kind, frozenset(expected))])
                    reason = 'full-audit cleanup successor: consumed operation path census changed: ' + kind
                self._assert_refused(events, operation, reason, core)
                # Restoring the original discovery function cannot revive the
                # same failed owner, including after its normal close path.
                with self.assertRaises(core._OperationCoherenceError) as retry:
                    core._operation_check(operation, self.root)
                self.assertIs(type(retry.exception), core._OperationCoherenceError)
                self.assertEqual(str(retry.exception), reason)
                self.assertEqual(operation._failure_reason, reason)
                # The rejected reuse re-invalidates the already-closed owner.
                # It cannot recover its source image or become active again.
                self.assertEqual(operation._state, 'invalid')
                self.assertTrue(operation._failed)
                self.assertFalse(operation._raw)
                self.assertIsNone(operation._record_raw)
                self.assertIsNone(operation._owner_frame)
                self.assertEqual(operation._observations, [])
                self.assertEqual(operation._discoveries, [])
                operation.close()
                self.assert_closed(operation, core)
                self.assertTrue(operation._failed)
                self.assertEqual(operation._failure_reason, reason)
                self.assertFalse((self.root/added).exists())

    def test_distinct_late_map_finalizer_discards_every_real_completed_proof(self):
        from functools import wraps
        loops, core = self.coverage()
        module = 'extensions/carla/map'
        expected = {rule[5] for rule in loops.GUARDED_LOOP_RULES if rule[0] == module}
        expected.add('construction-geometry-boundary-list')
        self.assertGreater(len(expected), 1)
        original, original_fail = core._InvariantInputs.finish, core._operation_fail
        physical = (self.root/ROAD).read_bytes()
        injected, completed, failures = [], [], []
        reason = 'full-audit cleanup successor: owned input changed: ' + ROAD
        @wraps(original)
        def finish(operation, root):
            frame = sys._getframe(1)
            self.assertIs(self._frame(loops.reviewed_nonempty_loops, frame), frame)
            self.assertIs(frame.f_locals['_operation'], operation)
            self.assertEqual(frame.f_locals['module'], module)
            self.assertEqual(operation._state, 'active')
            self.assertEqual(injected, [])
            rows = frame.f_locals['result']
            self.assertTrue(all(line == row['line'] for line, row in rows.items()))
            proof_ids = {row['proof_id'] for row in rows.values()}
            self.assertLessEqual(expected, proof_ids)
            completed.append(proof_ids)
            injected.append(operation)
            (root/ROAD).write_bytes(physical + b'\n# late finalizer B\n')
            return original(operation, root)
        @wraps(original_fail)
        def fail(operation, error):
            if injected and operation is injected[0] and str(error) == reason:
                failures.append(error)
            return original_fail(operation, error)
        try:
            with self.audit(core) as events, patch.object(core._InvariantInputs, 'finish', finish), \
                    patch.object(core, '_operation_fail', fail):
                result = loops.reviewed_nonempty_loops(self.root, module)
        finally:
            (self.root/ROAD).write_bytes(physical)
        self.assertEqual(result, {})
        self.assertEqual(len(injected), 1)
        self.assertEqual(len(completed), 1)
        self.assertLessEqual(expected, completed[0])
        self.assertEqual(len(failures), 1)
        self.assertIs(type(failures[0]), core.ContractError)
        self.assertIsNone(failures[0].__cause__)
        self._assert_refused(events, injected[0], reason, core, finalized=True)
        self.assertEqual((self.root/ROAD).read_bytes(), physical)


class ReviewedAbsoluteRootTextMechanics(unittest.TestCase):
    """Pure root spelling conversion; no input admission or cached authority."""

    _V35_CALLER_AST = {
        '_CacheInputs._check_context': '6e5b17072ca307797a39ef291fd0fee1ba431a0a5dfddde1e7ceda0672c9921d',
        '_private_operation_wrapper': '85e1d09445b46b340c3ba5b4973463a685b14487845a07cd365420295c61c29c',
    }
    _HELPER_AST_SHA = '280c064b53770cbdb8239251de6a5e629884a9f491b5979911058b100c6f0312'
    _ROOT_BUILTINS = ('__import__', 'all', 'getattr', 'isinstance', 'len', 'list', 'next', 'str',
                      'type', 'vars', 'ImportError', 'OSError', 'ValueError',
                      'TypeError', 'RuntimeError')

    @staticmethod
    def _one_definition(body, name):
        matches = [node for node in body if isinstance(node, (ast.FunctionDef, ast.ClassDef))
                   and node.name == name]
        if len(matches) != 1:
            raise AssertionError(('one root-conversion definition', name))
        return matches[0]

    @staticmethod
    def _binding_sites(body, names):
        # This is a finite declaration/rebinding check, not a source evaluator.
        # Do not descend into unrelated function or class local namespaces.
        sites = []
        for statement in body:
            if isinstance(statement, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                bound = {statement.name}
            else:
                bound = set()
                for node in ast.walk(statement):
                    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                        bound.add(node.name)
                    elif isinstance(node, (ast.Import, ast.ImportFrom)):
                        bound.update(alias.asname or alias.name.split('.')[0] for alias in node.names)
                    elif isinstance(node, ast.Name) and isinstance(node.ctx, (ast.Store, ast.Del)):
                        bound.add(node.id)
                    elif isinstance(node, ast.ExceptHandler) and node.name:
                        bound.add(node.name)
                    elif isinstance(node, (ast.Attribute, ast.Subscript)) and isinstance(node.ctx, (ast.Store, ast.Del)):
                        target = node.value
                        while isinstance(target, (ast.Attribute, ast.Subscript)):
                            target = target.value
                        if isinstance(target, ast.Name):
                            bound.add(target.id)
            if bound.intersection(names):
                sites.append(statement)
        return sites

    # These are only the nineteen reviewed generated-receipt additions.  Keep
    # the two original root-optimization sites visible to the module-wide check.
    _GENERATED_ROOT_CALLS = (('_operation_include_context',
      ('body', 1, 'body', 1, 'body', 1, 'value', 'args', 0, 'elt'),
      '9dbdc0cf9877bde8fd710b1cfb4d7f14d49452c49a15d18026fb30810de6d995',
      ('body', 1, 'body', 1, 'body', 1),
      'f1c33b6980c708f8fbb31feaa61dbacd1f0dec125c9dadca859abfdc8d35bcd2'),
     ('_private_operation_wrapper',
      ('body', 1, 'body', 4, 'body', 0, 'test', 'values', 1, 'left'),
      '753c654e9c3eb1ca6d5f73abe70ed43c502e8ed896a61c5ec4d18b7fcec974ca',
      ('body', 1, 'body', 4, 'body', 0),
      'b339e3eb471b1a87a51859609d94e34ad3daf0f9fa76c5146bf0f3ab2bd27ffc'),
     ('_private_operation_wrapper',
      ('body', 1, 'body', 4, 'body', 0, 'test', 'values', 2, 'left', 'args', 0, 'elt'),
      '9dbdc0cf9877bde8fd710b1cfb4d7f14d49452c49a15d18026fb30810de6d995',
      ('body', 1, 'body', 4, 'body', 0),
      'b339e3eb471b1a87a51859609d94e34ad3daf0f9fa76c5146bf0f3ab2bd27ffc'),
     ('_operation_record',
      ('body', 0, 'body', 3, 'value', 'args', 0, 'left'),
      'aa5f5604e860e89847b1c79d56c213702318635d8e91d438d297b22e53eafa91',
      ('body', 0, 'body', 3),
      'ec3c9ca1f3090e9c3cfdd2e573531edc5f42c5f389919d1f491f47fc741ebc06'),
     ('_InvariantInputs.__init__',
      ('body', 21, 'body', 2, 'value', 'args', 0, 'values', 1, 'left'),
      'd929019f11ecefc5ecff0fb8a5a5155dd621851816626f2046776d387d9f0a3f',
      ('body', 21, 'body', 2),
      'd60db09dfa0cc724bb80d2f15ea25f8074753d40b988500a0cb5240eaff36e05'),
     ('_InvariantInputs.__init__',
      ('body', 21, 'body', 3, 'value', 'elts', 0),
      'd929019f11ecefc5ecff0fb8a5a5155dd621851816626f2046776d387d9f0a3f',
      ('body', 21, 'body', 3),
      'f048ad17dd52363c7cf03238370d223c3a9c899c6e8ad27cc706d920592e092c'),
     ('_InvariantInputs._check_context',
      ('body', 2, 'value', 'args', 0, 'values', 2, 'left'),
      'aa5f5604e860e89847b1c79d56c213702318635d8e91d438d297b22e53eafa91',
      ('body', 2),
      '35999423469694c123a301b2c7d32e4bc8e375d46b0491998a5dd1a4720a2624'),
     ('_InvariantInputs._check_context',
      ('body', 2, 'value', 'args', 0, 'values', 3, 'left'),
      'e9b68711c8da290ea0c2dc6a460886bfe6a92dbe6c8c501a2bdf746c89ac1863',
      ('body', 2),
      '35999423469694c123a301b2c7d32e4bc8e375d46b0491998a5dd1a4720a2624'),
     ('_InvariantInputs._check_context',
      ('body', 2, 'value', 'args', 0, 'values', 4, 'left', 'elts', 0),
      'e546e19c1b0eac34949ba8d75208cd5c64039b7776fe0733e771523534bdd98e',
      ('body', 2),
      '35999423469694c123a301b2c7d32e4bc8e375d46b0491998a5dd1a4720a2624'),
     ('_InvariantInputs._receipt_bindings',
      ('body', 0, 'body', 1, 'value', 'args', 0, 'values', 1, 'left'),
      'aa5f5604e860e89847b1c79d56c213702318635d8e91d438d297b22e53eafa91',
      ('body', 0, 'body', 1),
      '4e449f2d3cb0cd2eca6f87cf47fee1239d4d3a3bd6fc6d5cc8e8dea870ae4294'),
     ('_InvariantInputs._publish',
      ('body', 17, 'body', 2, 'value', 'args', 0, 'left'),
      'a9d80834554899bc92d337be6c7586da1c400e15c06a01715794aa6abe1922a8',
      ('body', 17, 'body', 2),
      '71356e8d45ab44056f004568b385f7e4016a5b14a43c05ac561b7c971056bf5b'),
     ('_InvariantInputs._discovery',
      ('body', 0, 'body', 3, 'body', 0, 'value'),
      'aa5f5604e860e89847b1c79d56c213702318635d8e91d438d297b22e53eafa91',
      ('body', 0, 'body', 3, 'body', 0),
      'b3f92f7cb7170a53f9df1b3de103b30b3273be0901b9e371c0db90c217a72aab'),
     ('_InvariantInputs._discovery',
      ('body', 0, 'body', 4, 'orelse', 0, 'value', 'values', 1, 'left'),
      'aa5f5604e860e89847b1c79d56c213702318635d8e91d438d297b22e53eafa91',
      ('body', 0, 'body', 4, 'orelse', 0),
      'ce8e13dc97ab93638a18c4d6122c56d2cd4b1a39d411d25d2e2020c3ba5dbbd5'),
     ('_InvariantInputs._match',
      ('body', 0, 'value', 'values', 1, 'left'),
      'aa5f5604e860e89847b1c79d56c213702318635d8e91d438d297b22e53eafa91',
      ('body', 0),
      'ce8e13dc97ab93638a18c4d6122c56d2cd4b1a39d411d25d2e2020c3ba5dbbd5'),
     ('_InvariantInputs._observe',
      ('body', 0, 'body', 5, 'body', 0, 'value', 'left'),
      'aa5f5604e860e89847b1c79d56c213702318635d8e91d438d297b22e53eafa91',
      ('body', 0, 'body', 5, 'body', 0),
      'eefe3331a94be6967c4203ac0e0d034e8e2d3a578624763153d44e124193dc85'),
     ('_InvariantInputs._observe',
      ('body', 0, 'body', 5, 'body', 4, 'value', 'args', 0, 'elts', 0),
      'aa5f5604e860e89847b1c79d56c213702318635d8e91d438d297b22e53eafa91',
      ('body', 0, 'body', 5, 'body', 4),
      '5e2756f23805ec7590f9c32815eaeaaee8acd82800ea94c7f1eabe9e3e2adf89'),
     ('_InvariantInputs._admit',
      ('body', 0, 'body', 3, 'body', 1, 'body', 0, 'body', 0, 'value', 'args', 0, 'left'),
      'aa5f5604e860e89847b1c79d56c213702318635d8e91d438d297b22e53eafa91',
      ('body', 0, 'body', 3, 'body', 1, 'body', 0, 'body', 0),
      '3daa57c0f994355fba6e78ebb81398a11554a05d110f3a5cc1b68b1527ab500e'),
     ('_InvariantInputs._receipt_finish_inputs',
      ('body', 1, 'value', 'args', 0, 'left'),
      'aa5f5604e860e89847b1c79d56c213702318635d8e91d438d297b22e53eafa91',
      ('body', 1),
      'bb8ebee85fefdc5f45426ff901645c8c25a3fde40daf830e8ecb63cceeeebbe5'),
     ('verify',
      ('body',
       3,
       'body',
       0,
       'body',
       1,
       'value',
       'args',
       0,
       'values',
       2,
       'values',
       1,
       'values',
       1,
       'left',
       'args',
       0,
       'elt'),
      '9dbdc0cf9877bde8fd710b1cfb4d7f14d49452c49a15d18026fb30810de6d995',
      ('body', 3, 'body', 0, 'body', 1),
      '40e5b3ce8225fa8b3fa60ac8ab25b988f6bbd182921de010afd55672d6ac9daf'))

    @staticmethod
    def _root_projection_key(node):
        # Stable across the supported Python AST dump presentation versions.
        def encode(value):
            if isinstance(value, ast.AST):
                return [type(value).__name__, [[field, encode(getattr(value, field, None))]
                                              for field in value._fields]]
            if isinstance(value, list):
                return [encode(item) for item in value]
            return value
        return hashlib.sha256(json.dumps(encode(node), separators=(',', ':'),
                                         ensure_ascii=True).encode()).hexdigest()

    def _project_generated_root_calls(self, tree):
        projected = copy.deepcopy(tree)
        pending = []
        locations = set()
        for qualified, path, call_sha, statement_path, statement_sha in self._GENERATED_ROOT_CALLS:
            self.assertNotIn((qualified, path), locations)
            locations.add((qualified, path))
            declaration = projected
            for name in qualified.split('.'):
                declaration = self._one_definition(declaration.body, name)
            def at(parts):
                node = declaration
                for part in parts:
                    node = node[part] if isinstance(part, int) else getattr(node, part)
                return node
            call = at(path)
            self.assertEqual(self._root_projection_key(call), call_sha,
                             (qualified, path, 'generated root call drift'))
            self.assertEqual(self._root_projection_key(at(statement_path)), statement_sha,
                             (qualified, statement_path, 'generated root statement drift'))
            self.assertIsInstance(call, ast.Call)
            self.assertIsInstance(call.func, ast.Name)
            self.assertEqual(call.func.id, '_absolute_root_text')
            self.assertEqual(len(call.args), 1)
            self.assertEqual(call.keywords, [])
            pending.append((at(path[:-1]), path[-1], call))
        self.assertEqual(len(pending), 19)
        # Authenticate the complete inventory before changing any copied node.
        for parent, field, call in pending:
            value = copy.deepcopy(call.args[0])
            if isinstance(field, int):
                parent[field] = value
            else:
                setattr(parent, field, value)
        return projected

    def _project_public_admission_root_calls(self, tree):
        """Project two root uses authenticated by the existing reviewed inverse."""
        projected = copy.deepcopy(tree)
        additions = [(start, stop, after) for start, stop, before, after in
                     _TYPED_CHECKER_SOURCE_EDITS['full_audit_cleanup_contracts.py']
                     if not before and 'class _PublicAdmission:\n' in after]
        self.assertEqual([(start, stop) for start, stop, _ in additions], [(1391, 1715)])
        reviewed = self._one_definition(ast.parse(''.join(additions[0][2])).body,
                                        '_PublicAdmission')
        public = self._one_definition(projected.body, '_PublicAdmission')
        pending = []
        for name, address in (
                ('__init__', ('body', 8, 'value')),
                ('_check_context', ('body', 0, 'value', 'args', 0, 'values', 0, 'left'))):
            method = self._one_definition(public.body, name)
            expected = self._one_definition(reviewed.body, name)
            if name == '__init__':
                self.assertEqual(len(method.body), len(expected.body) + 1)
                guard = ast.parse("require(_canonical_inventory_admission_frame(frame), "
                    "'public inventory admission requires its canonical owner')").body[0]
                self.assertEqual(ast_key(method.body[4]), ast_key(guard),
                                 'reviewed canonical inventory owner guard drift')
                method.body.pop(4)
            self.assertEqual(ast_key(method), ast_key(expected),
                             (name, 'reviewed public root method drift'))
            calls = [node for node in ast.walk(method) if isinstance(node, ast.Call)
                     and isinstance(node.func, ast.Name) and node.func.id == '_absolute_root_text']
            self.assertEqual(len(calls), 1)
            parent = method
            for part in address[:-1]:
                parent = parent[part] if isinstance(part, int) else getattr(parent, part)
            field = address[-1]
            call = parent[field] if isinstance(field, int) else getattr(parent, field)
            self.assertIs(call, calls[0])
            self.assertEqual(ast_key(call), ast_key(ast.parse(
                '_absolute_root_text(root)', mode='eval').body))
            pending.append((parent, field, call))
        self.assertEqual(len(pending), 2)
        # Authenticate both complete methods before changing either copied call.
        for parent, field, call in pending:
            value = copy.deepcopy(call.args[0])
            if isinstance(field, int):
                parent[field] = value
            else:
                setattr(parent, field, value)
        return projected

    def test_inventory_constructor_transition_preserves_exact_historical_root_method(self):
        original = ast.parse(inspect.getsource(cleanup._PublicAdmission))
        self._project_public_admission_root_calls(original)
        for fault in ('missing', 'moved', 'condition', 'message', 'duplicate'):
            tree = copy.deepcopy(original)
            public = self._one_definition(tree.body, '_PublicAdmission')
            method = self._one_definition(public.body, '__init__')
            if fault == 'missing': method.body.pop(4)
            elif fault == 'moved': method.body[4], method.body[5] = method.body[5], method.body[4]
            elif fault == 'condition': method.body[4].value.args[0] = ast.Constant(True)
            elif fault == 'message': method.body[4].value.args[1] = ast.Constant('other')
            else: method.body.insert(4, copy.deepcopy(method.body[4]))
            with self.subTest(fault=fault), self.assertRaises(AssertionError):
                self._project_public_admission_root_calls(tree)

    def _assert_root_projection(self, tree, source_tree):
        definitions = {name: self._one_definition(tree.body, name) for name in
                       ('_absolute_root_text', '_CacheInputs', '_private_operation_wrapper',
                        '_owner_module', 'require', 'ContractError')}
        helper = copy.deepcopy(definitions['_absolute_root_text'])
        condition = helper.body[1].body[1].body[1]
        _rc21_expect_ast(condition.test, '54e8dec820940f1e9f7fa3db81947711670b43becdf24ef3a4c4fd7a62e60c38',
                         'V10 root-string condition AST drift')
        condition.test = ast.parse("text == '/' or (text.startswith('/') and all("
                                   "part not in ('', '.', '..') for part in text[1:].split('/')))",
                                   mode='eval').body
        _rc21_expect_ast(helper, self._HELPER_AST_SHA, 'complete original root helper AST drift')

        cls = definitions['_CacheInputs']
        context = self._one_definition(cls.body, '_check_context')
        self.assertEqual(self._binding_sites(cls.body, {'_check_context'}), [context])
        header = copy.deepcopy(cls)
        header.body = []
        _rc21_expect_ast(header, '4e8b41b5eb76c028593ead8ae5d8bf20afaed0df8f1a5a124de6e3923e1e50c8',
                         'root-conversion owner class header AST drift')
        for name, node in (('_CacheInputs._check_context', context),
                           ('_private_operation_wrapper', definitions['_private_operation_wrapper'])):
            checked = (owner_helpers.typed_owner_ast(
                _generated_owner_predecessor_ast(node), 'private', reverse=True)
                       if name == '_private_operation_wrapper' else node)
            original, count = self._reverse(checked)
            self.assertEqual(count, 1)
            _rc21_expect_ast(original, self._V35_CALLER_AST[name], (name, 'complete V35 caller AST drift'))
        # Retain the original two-site assertion across the complete module.
        without_helper = copy.deepcopy(tree)
        without_helper.body = [node for node in without_helper.body
                               if not isinstance(node, ast.FunctionDef) or node.name != '_absolute_root_text']
        without_generated = self._project_generated_root_calls(without_helper)
        without_generated = self._project_public_admission_root_calls(without_generated)
        _, count = self._reverse(without_generated)
        self.assertEqual(count, 2)

        for name, expected in (
                ('require', '531a60a4ed0275a1b20c7a1dfade0631ab04a8f49bc6c143fd5895c687b322e1'),
                ('ContractError', 'a2c26b3043e0cbb0f8e9f746710f1dd081901375b1feeeec02a62e11d5f3b587')):
            _rc21_expect_ast(definitions[name], expected, (name, 'root-conversion dependency AST drift'))
        owner = owner_helpers.typed_owner_predecessor(definitions['_owner_module'])
        _rc21_expect_ast(owner.body[1], '73a7cd0ab7fe92a00574301143c48c926cf3f46080c65edc3fc5f35b09b42553',
                         'V14 root-conversion owner dispatch AST drift')
        owner.body[1] = owner.body[1].orelse[0]
        _rc21_expect_ast(owner, 'a5f60b07d07556090def6d3490be5dfeef8197ef71d8e3ff13efce5c110d4860',
                         'complete original root-conversion owner helper AST drift')

        watched = set(definitions) | set(self._ROOT_BUILTINS) | {'Path', 'PosixPath', 'os', 'sys', 'types', 'source', '__package__'}
        imports = [node for node in tree.body if isinstance(node, (ast.Import, ast.ImportFrom))
                   and self._binding_sites([node], watched)]
        self.assertEqual([ast_key(node) for node in imports], [ast_key(node) for node in ast.parse(
            'import types\nimport os\nfrom pathlib import Path, PosixPath\nimport sys').body])
        routes = [node for node in tree.body if isinstance(node, ast.Try)
                  and any(isinstance(child, (ast.Import, ast.ImportFrom))
                          and any(alias.asname == 'source' for alias in child.names) for child in ast.walk(node))]
        self.assertEqual(len(routes), 1)
        route = copy.deepcopy(routes[0])
        # Project unrelated sibling imports only. Preserve package routing,
        # exception handling and every binding relevant to this closure.
        for branch in (route.body[0].body, route.body[0].orelse):
            branch[:] = [node for node in branch if not isinstance(node, (ast.Import, ast.ImportFrom))
                         or self._binding_sites([node], watched)]
        _rc21_expect_ast(route, '718148af9e25144b4b3f6f8b8ceef51c21dd18ad5c5160f2931e41eb77860e60',
                         'root-conversion source import route AST drift')
        allowed = [*definitions.values(), *imports, routes[0]]
        self.assertEqual(self._binding_sites(tree.body, watched),
                         [node for node in tree.body if node in allowed])

        scope = self._one_definition(source_tree.body, 'lexical_memo_scope')
        _rc21_expect_ast(scope, '00d14c23b4efc7ab3aec27e257848bf15c652a028f8c88a589f9fb30bdd3007c',
                         'root-conversion lexical scope identity AST drift')
        scope_bindings = self._binding_sites(source_tree.body, {'lexical_memo_scope', 'contextmanager'})
        self.assertEqual(len(scope_bindings), 2)
        self.assertEqual(ast_key(scope_bindings[0]), ast_key(ast.parse('from contextlib import contextmanager, nullcontext').body[0]))
        self.assertIs(scope_bindings[1], scope)

    def _checked_functions(self):
        import abc
        import builtins
        import contextlib
        import os
        import pathlib
        import types
        if (cleanup.os.name != 'posix' or sys.version_info[:2] != (3, 12)
                or type(getattr(pathlib.PosixPath('/alpha'), '_raw_paths', None)) is not list):
            self.skipTest('fast-layout matrix requires pinned Python3.12 POSIX pathlib')
        raw = Path(cleanup.__file__).read_bytes()
        tree = ast.parse(raw)
        helper = next(item for item in tree.body
                      if isinstance(item, ast.FunctionDef) and item.name == '_absolute_root_text')
        source_raw = Path(source.__file__).read_bytes()
        source_tree = ast.parse(source_raw)
        self._assert_root_projection(tree, source_tree)
        compiled = compile(raw, cleanup.__file__, 'exec', dont_inherit=True, optimize=sys.flags.optimize)
        codes = [item for item in compiled.co_consts if isinstance(item, types.CodeType)
                 and item.co_name == '_absolute_root_text']
        self.assertEqual(codes, [cleanup._absolute_root_text.__code__])
        pending = [compiled]
        core_codes = {}
        while pending:
            code = pending.pop()
            core_codes[code.co_qualname] = code
            pending.extend(item for item in code.co_consts if isinstance(item, types.CodeType))
        self.assertEqual(core_codes['_CacheInputs._check_context'], cleanup._CacheInputs._check_context.__code__)
        self.assertEqual(core_codes['_private_operation_wrapper'], cleanup._private_operation_wrapper.__code__)
        for name in ('require', '_owner_module'):
            self.assertEqual(core_codes[name], getattr(cleanup, name).__code__)
        self.assertEqual(cleanup.ContractError.__bases__, (ValueError, RuntimeError))
        functions = (cleanup._absolute_root_text, cleanup._CacheInputs._check_context,
                     cleanup._private_operation_wrapper, cleanup.require, cleanup._owner_module)
        for function in functions:
            self.assertIs(function.__globals__, vars(cleanup))
        for name, value in (('os', os), ('sys', sys), ('types', types), ('source', source),
                            ('Path', pathlib.Path), ('PosixPath', pathlib.PosixPath)):
            self.assertIs(getattr(cleanup, name), value)
        self.assertIs(types.FunctionType, type(cleanup.require))
        self.assertIs(types.CodeType, type(cleanup.require.__code__))
        for name in self._ROOT_BUILTINS:
            self.assertNotIn(name, vars(cleanup))
            for function in functions:
                self.assertIs(function.__builtins__[name], getattr(builtins, name))
        # The bridge reads this decorated function's identity; it never executes
        # its memo body. Bind both layers without pulling in memo internals.
        source_compiled = compile(source_raw, source.__file__, 'exec', dont_inherit=True,
                                  optimize=sys.flags.optimize)
        scope_code = next(code for code in source_compiled.co_consts
                          if isinstance(code, types.CodeType) and code.co_name == 'lexical_memo_scope')
        self.assertIs(source.contextmanager, contextlib.contextmanager)
        self.assertEqual(source.lexical_memo_scope.__wrapped__.__code__, scope_code)
        self.assertIs(source.lexical_memo_scope.__wrapped__.__globals__, vars(source))
        context_raw = Path(contextlib.__file__).read_bytes()
        pending = [compile(context_raw, contextlib.__file__, 'exec', dont_inherit=True,
                           optimize=sys.flags.optimize)]
        context_codes = {}
        while pending:
            code = pending.pop()
            context_codes[code.co_qualname] = code
            pending.extend(item for item in code.co_consts if isinstance(item, types.CodeType))
        self.assertEqual(context_codes['contextmanager'], contextlib.contextmanager.__code__)
        self.assertEqual(context_codes['contextmanager.<locals>.helper'], source.lexical_memo_scope.__code__)
        self.assertIs(source.lexical_memo_scope.__globals__, vars(contextlib))
        self.assertEqual(source.lexical_memo_scope.__code__.co_freevars, ('func',))
        self.assertIs(source.lexical_memo_scope.__closure__[0].cell_contents,
                      source.lexical_memo_scope.__wrapped__)
        self.assertEqual(context_codes['ContextDecorator.__call__'], contextlib.ContextDecorator.__call__.__code__)
        self.assertIs(contextlib.contextmanager.__globals__, vars(contextlib))
        self.assertIs(contextlib.ContextDecorator.__call__.__globals__, vars(contextlib))
        manager = contextlib._GeneratorContextManager
        self.assertIs(type(manager), abc.ABCMeta)
        self.assertEqual(manager.__bases__, (contextlib._GeneratorContextManagerBase,
                         contextlib.AbstractContextManager, contextlib.ContextDecorator))
        for owner, names in ((manager, ('__enter__', '__exit__')),
                             (contextlib._GeneratorContextManagerBase, ('__init__', '_recreate_cm'))):
            for name in names:
                method = vars(owner)[name]
                self.assertEqual(context_codes[owner.__name__ + '.' + name], method.__code__)
                self.assertIs(method.__globals__, vars(contextlib))
        # Bind the reference implementation to actual checked stdlib source,
        # independently of interpreter optimization or relocation.
        stdlib = Path(pathlib.__file__).read_bytes()
        pending = [compile(stdlib, pathlib.__file__, 'exec', dont_inherit=True,
                           optimize=sys.flags.optimize)]
        names = {'PurePath.__init__', 'PurePath.__str__', 'Path.__init__',
                 'Path.__new__', 'Path.absolute', 'Path.cwd', 'PurePath.is_absolute',
                 'PurePath._load_parts', 'PurePath._parse_path', 'PurePath._format_parsed_parts',
                 'PurePath.drive', 'PurePath.root', 'PurePath._tail', 'PurePath.with_segments'}
        found = {}
        while pending:
            code = pending.pop()
            if code.co_qualname in names:
                found[code.co_qualname] = code
            pending.extend(item for item in code.co_consts if isinstance(item, types.CodeType))
        for qualified in names:
            owner, name = qualified.split('.')
            live = getattr(getattr(pathlib, owner), name)
            if isinstance(live, property): live = live.fget
            self.assertEqual(found[qualified], live.__code__)
        return tree, helper

    @staticmethod
    def _root_text_outcome(call):
        try:
            value = call()
            return ('return', type(value), value)
        except Exception as error:
            cause = error.__cause__
            return ('error', type(error), error.args,
                    None if cause is None else (type(cause), cause.args))

    @staticmethod
    def _reverse(node):
        class Reverse(ast.NodeTransformer):
            def __init__(self):
                self.count = 0
            def visit_Call(self, item):
                item = self.generic_visit(item)
                if isinstance(item.func, ast.Name) and item.func.id == '_absolute_root_text':
                    if len(item.args) != 1 or item.keywords:
                        raise AssertionError('unexpected root helper call shape')
                    self.count += 1
                    value = ast.parse('str(Path(ROOT).absolute())', mode='eval').body
                    value.args[0].func.value.args[0] = item.args[0]
                    return ast.copy_location(value, item)
                return item
        reverse = Reverse()
        value = reverse.visit(copy.deepcopy(node))
        return value, reverse.count

    def test_only_two_original_root_expressions_change(self):
        # Native fallback is checked even outside the scoped POSIX layout matrix.
        self.assertEqual(cleanup._absolute_root_text('relative'), str(Path('relative').absolute()))
        self._checked_functions()

    def test_projection_accepts_unrelated_source_change(self):
        tree = ast.parse(Path(cleanup.__file__).read_bytes())
        source_tree = ast.parse(Path(source.__file__).read_bytes())
        unrelated = self._one_definition(tree.body, 'native_support_mapping')
        unrelated.body.insert(0, ast.Pass())
        self._assert_root_projection(tree, source_tree)

    def test_projection_rejects_relevant_source_and_binding_changes(self):
        original = ast.parse(Path(cleanup.__file__).read_bytes())
        original_source = ast.parse(Path(source.__file__).read_bytes())
        for mutation in ('require', 'exception_base', 'owner', 'path_import', 'package_route',
                         'builtin_rebinding', 'class_header', 'method_rebinding', 'method_duplicate',
                         'conditional_method_rebinding', 'scope_decorator', 'caller_cwd'):
            tree, source_tree = copy.deepcopy(original), copy.deepcopy(original_source)
            definitions = {node.name: node for node in tree.body
                           if isinstance(node, (ast.FunctionDef, ast.ClassDef))}
            if mutation == 'require':
                definitions['require'].body[0].test = ast.Constant(False)
            elif mutation == 'exception_base':
                definitions['ContractError'].bases[0] = ast.Name(id='TypeError', ctx=ast.Load())
            elif mutation == 'owner':
                definitions['_owner_module'].body[1].test = ast.Constant(False)
            elif mutation == 'path_import':
                node = next(node for node in tree.body if isinstance(node, ast.ImportFrom) and node.module == 'pathlib')
                node.module = 'unreviewed_pathlib'
            elif mutation == 'package_route':
                node = next(node for node in tree.body if isinstance(node, ast.Try))
                node.body[0].test = ast.Constant(True)
            elif mutation == 'builtin_rebinding':
                tree.body.append(ast.parse('str = unreviewed_str').body[0])
            elif mutation == 'class_header':
                definitions['_CacheInputs'].decorator_list.append(ast.Name(id='unreviewed_decorator', ctx=ast.Load()))
            elif mutation == 'method_rebinding':
                definitions['_CacheInputs'].body.append(ast.parse('_check_context = unreviewed_context').body[0])
            elif mutation == 'method_duplicate':
                context = self._one_definition(definitions['_CacheInputs'].body, '_check_context')
                definitions['_CacheInputs'].body.append(copy.deepcopy(context))
            elif mutation == 'conditional_method_rebinding':
                definitions['_CacheInputs'].body.append(ast.parse(
                    'if True:\n    def _check_context(self, root): pass').body[0])
            elif mutation == 'scope_decorator':
                self._one_definition(source_tree.body, 'lexical_memo_scope').decorator_list = []
            else:
                context = self._one_definition(definitions['_CacheInputs'].body, '_check_context')
                cwd = next(node for node in ast.walk(context) if isinstance(node, ast.Call)
                           and ast_key(node) == ast_key(ast.parse('Path.cwd()', mode='eval').body))
                cwd.func.attr = 'home'
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                self._assert_root_projection(tree, source_tree)

        # Each allowed addition is exact, while calls outside the inventory
        # remain subject to the original complete-module two-site guard.
        for mutation in ('generated_argument', 'generated_missing', 'generated_moved',
                         'unexpected_root_call'):
            tree, source_tree = copy.deepcopy(original), copy.deepcopy(original_source)
            qualified, path, _, _, _ = self._GENERATED_ROOT_CALLS[0]
            declaration = tree
            for name in qualified.split('.'):
                declaration = self._one_definition(declaration.body, name)
            parent = declaration
            for part in path[:-1]:
                parent = parent[part] if isinstance(part, int) else getattr(parent, part)
            call = parent[path[-1]] if isinstance(path[-1], int) else getattr(parent, path[-1])
            unrelated = self._one_definition(tree.body, 'native_support_mapping')
            if mutation == 'generated_argument':
                call.args[0] = ast.Constant('/unreviewed')
            elif mutation in ('generated_missing', 'generated_moved'):
                if mutation == 'generated_moved':
                    unrelated.body.insert(0, ast.Expr(value=copy.deepcopy(call)))
                if isinstance(path[-1], int):
                    parent[path[-1]] = copy.deepcopy(call.args[0])
                else:
                    setattr(parent, path[-1], copy.deepcopy(call.args[0]))
            else:
                unrelated.body.insert(0, ast.parse('_absolute_root_text(root)').body[0])
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                self._assert_root_projection(tree, source_tree)

        # New public-scope additions cannot hide an extra root conversion.
        for name in ('__init__', '_check_context'):
            tree, source_tree = copy.deepcopy(original), copy.deepcopy(original_source)
            public = self._one_definition(tree.body, '_PublicAdmission')
            method = self._one_definition(public.body, name)
            method.body.append(ast.parse('_absolute_root_text(root)').body[0])
            with self.subTest(public_extra_root_call=name), self.assertRaises(AssertionError):
                self._assert_root_projection(tree, source_tree)

        # The reviewed nullcontext addition does not permit arbitrary siblings or aliases.
        for mutation in ('scope_extra_import', 'scope_aliased_import'):
            tree, source_tree = copy.deepcopy(original), copy.deepcopy(original_source)
            scope_import = next(node for node in source_tree.body
                                if isinstance(node, ast.ImportFrom) and node.module == 'contextlib')
            if mutation == 'scope_extra_import':
                scope_import.names.append(ast.alias(name='ExitStack'))
            else:
                scope_import.names[0].asname = 'unreviewed_contextmanager'
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                self._assert_root_projection(tree, source_tree)

    def test_fresh_values_callbacks_and_fallback_errors_match(self):
        from pathlib import PosixPath, PurePosixPath, PureWindowsPath
        import os
        tree, helper = self._checked_functions()
        fast = next(item.lineno for item in ast.walk(helper) if isinstance(item, ast.Return)
                    and isinstance(item.value, ast.Name) and item.value.id == 'text')
        fallback = next(item.lineno for item in ast.walk(helper) if isinstance(item, ast.Return)
                        and isinstance(item.value, ast.Call))
        class Foreign:
            def __init__(self, events, value='/alpha', failure=False):
                self.events, self.value, self.failure = events, value, failure
            def __fspath__(self):
                self.events.append('fspath')
                if self.failure:
                    raise OSError('deliberate root callback failure')
                return self.value
        class Text(str):
            def __new__(cls, value, events, failure=None):
                result = super().__new__(cls, value)
                result.events, result.failure = events, failure
                return result
            def __bool__(self):
                self.events.append('text-bool')
                if self.failure == 'bool': raise ValueError('early lazy text failure')
                return len(self) != 0
            def split(self, *args, **kwargs):
                self.events.append('text-split')
                if self.failure == 'split': raise RuntimeError('late lazy text failure')
                return super().split(*args, **kwargs)
        class RawList(list):
            def __iter__(self):
                self.events.append('raw-iter')
                return super().__iter__()
        class Derived(PosixPath):
            def __getattribute__(self, name):
                if name == '_raw_paths':
                    object.__getattribute__(self, 'events').append('path-raw')
                return super().__getattribute__(name)
        def raw_case(kind):
            def factory(events):
                root = PosixPath('/alpha')
                if kind == 'missing':
                    del root._raw_paths
                elif kind == 'tuple':
                    root._raw_paths = ('/alpha',)
                elif kind == 'list-subclass':
                    value = RawList(['/alpha']); value.events = events
                    root._raw_paths = value
                elif kind == 'non-string':
                    root._raw_paths = [17]
                elif kind == 'lazy-string':
                    root._raw_paths = [Text('/alpha', events)]
                elif kind in ('lazy-early-failure', 'lazy-late-failure'):
                    root._raw_paths = [Text('/alpha' if kind == 'lazy-early-failure' else 'relative',
                                            events, 'bool' if kind == 'lazy-early-failure' else 'split')]
                elif kind == 'cached':
                    root._str, root._drv, root._root, root._tail_cached = '/wrong', '', '/', ['wrong']
                return root
            return factory
        def derived(events):
            root = Derived('/alpha'); root.events = events
            return root
        cases = []
        canonical = ['/', '/alpha', '/alpha/beta', '/with spaces', '/Å/雪', '/Case/case',
                     '/colon:part/back\\slash', '/nul\x00part', '/' + 'x'*512]
        for value in canonical:
            for parsed in (False, True):
                def factory(events, value=value, parsed=parsed):
                    root = PosixPath(value)
                    if parsed:
                        str(root); root.parts
                    return root
                cases.append((repr((value, parsed)), factory, 'fast', None))
        for value in ['', '.', '..', 'relative', '/alpha/', '//alpha', '///alpha',
                      '/alpha//beta', '/alpha/./beta', '/alpha/../beta']:
            cases.append((repr(value), lambda events, value=value: PosixPath(value), 'fallback', None))
        for value in ['/alpha', '', 17, None, b'/alpha']:
            cases.append(('foreign-'+repr(value), lambda events, value=value: value, 'fallback',
                          None if isinstance(value, str) else TypeError))
        cases.extend([('pure-posix', lambda events: PurePosixPath('/alpha'), 'fallback', None),
                      ('pure-windows', lambda events: PureWindowsPath('C:/alpha'), 'fallback', None)])
        cases.extend([
            ('multiple-raw', lambda events: PosixPath('/alpha', 'beta'), 'fallback', None),
            ('path-subclass', derived, 'fallback', None),
            ('pathlike', lambda events: Foreign(events), 'fallback', None),
            ('pathlike-raises', lambda events: Foreign(events, failure=True), 'fallback', OSError),
            ('pathlike-invalid', lambda events: Foreign(events, 17), 'fallback', TypeError),
            ('str-subclass', lambda events: Text('/alpha', events), 'fallback', None),
        ])
        for kind in ('missing', 'tuple', 'list-subclass', 'non-string', 'lazy-string',
                     'lazy-early-failure', 'lazy-late-failure', 'cached'):
            cases.append((kind, raw_case(kind), 'fast' if kind == 'cached' else 'fallback',
                          {'missing': AttributeError, 'non-string': AttributeError,
                           'lazy-early-failure': ValueError, 'lazy-late-failure': RuntimeError}.get(kind)))
        counts = Counter()
        for name, factory, expected_branch, expected_error in cases:
            with self.subTest(name=name):
                old_events, new_events, branches = [], [], []
                old_root, new_root = factory(old_events), factory(new_events)
                old_events.clear(); new_events.clear()
                def cwd_old():
                    old_events.append('cwd'); return '/observed-cwd'
                def cwd_new():
                    new_events.append('cwd'); return '/observed-cwd'
                with patch.object(os, 'getcwd', cwd_old), patch.object(
                        Path, 'stat', side_effect=AssertionError('unexpected filesystem stat')), patch.object(
                        Path, 'lstat', side_effect=AssertionError('unexpected filesystem lstat')), patch.object(
                        os, 'scandir', side_effect=AssertionError('unexpected filesystem scan')), patch(
                        'builtins.open', side_effect=AssertionError('unexpected filesystem open')), patch(
                        'io.open', side_effect=AssertionError('unexpected filesystem open')):
                    old = self._root_text_outcome(lambda: str(Path(old_root).absolute()))
                def trace(frame, event, arg):
                    if frame.f_code is cleanup._absolute_root_text.__code__ and event == 'line':
                        if frame.f_lineno == fast: branches.append('fast')
                        if frame.f_lineno == fallback: branches.append('fallback')
                    return trace
                previous = sys.gettrace()
                try:
                    sys.settrace(trace)
                    with patch.object(os, 'getcwd', cwd_new), patch.object(
                            Path, 'stat', side_effect=AssertionError('unexpected filesystem stat')), patch.object(
                            Path, 'lstat', side_effect=AssertionError('unexpected filesystem lstat')), patch.object(
                        os, 'scandir', side_effect=AssertionError('unexpected filesystem scan')), patch(
                        'builtins.open', side_effect=AssertionError('unexpected filesystem open')), patch(
                        'io.open', side_effect=AssertionError('unexpected filesystem open')):
                        new = self._root_text_outcome(lambda: cleanup._absolute_root_text(new_root))
                finally:
                    sys.settrace(previous)
                self.assertEqual(new, old)
                self.assertEqual(new[:2], ('return', str) if expected_error is None else ('error', expected_error))
                self.assertEqual(new_events, old_events)
                self.assertEqual(branches, [expected_branch])
                counts.update(branches)
        self.assertEqual(counts, {'fast': 19, 'fallback': 30})
        for root in (PosixPath('/alpha'), PosixPath('relative')):
            with self.subTest(missing_cwd=str(root)), patch.object(os, 'getcwd', side_effect=OSError('missing cwd')):
                new = self._root_text_outcome(lambda: cleanup._absolute_root_text(root))
                self.assertEqual(new, self._root_text_outcome(lambda: str(Path(root).absolute())))
                self.assertEqual(new[:2], ('return', str) if root.is_absolute() else ('error', OSError))
        import types
        with patch.object(cleanup, 'os', types.SimpleNamespace(name='unsupported')):
            self.assertEqual(cleanup._absolute_root_text(PosixPath('/alpha')), '/alpha')

    def test_context_keeps_fresh_cwd_short_circuit_and_exception_order(self):
        import os
        from types import SimpleNamespace
        tree, helper = self._checked_functions()
        cls = next(item for item in tree.body if isinstance(item, ast.ClassDef) and item.name == '_CacheInputs')
        node = next(item for item in cls.body if getattr(item, 'name', None) == '_check_context')
        reference, count = self._reverse(node)
        self.assertEqual(count, 1)
        namespace = dict(vars(cleanup))
        exec(compile(ast.fix_missing_locations(ast.Module(body=[reference], type_ignores=[])),
                     '<original-context>', 'exec'), namespace)
        for root, stored, observed_cwd, includes, expected_cwd, succeeds in (
            ('/alpha', '/alpha', '/work', (), 1, True),
            ('/wrong', '/alpha', '/work', (), 0, False),
            ('/alpha', '/alpha', '/changed', (), 1, False),
            ('/alpha', '/alpha', OSError('missing cwd'), (), 1, False),
            ('/alpha', '/alpha', '/work', ('foreign',), 1, False),
            ('relative', '/work/relative', '/work', (), 2, True),
        ):
            outcomes, events = [], []
            for call in (namespace['_check_context'], cleanup._CacheInputs._check_context):
                seen = []
                def cwd():
                    seen.append('cwd')
                    if isinstance(observed_cwd, Exception): raise observed_cwd
                    return observed_cwd
                state = SimpleNamespace(_root=stored, _cwd='/work', _include_roots=includes)
                with patch.object(os, 'getcwd', cwd):
                    outcomes.append(self._root_text_outcome(lambda: call(state, Path(root))))
                events.append(seen)
            self.assertEqual(outcomes[0], outcomes[1])
            self.assertEqual(outcomes[1][:2], ('return', type(None)) if succeeds else ('error', cleanup.ContractError))
            self.assertEqual(events, [['cwd']*expected_cwd]*2)

    def test_private_bridge_keeps_both_root_checks_in_order(self):
        import types
        tree, helper = self._checked_functions()
        node = next(item for item in tree.body if isinstance(item, ast.FunctionDef)
                    and item.name == '_private_operation_wrapper')
        reference, count = self._reverse(_generated_owner_predecessor_ast(node))
        self.assertEqual(count, 1)
        namespace = dict(vars(cleanup))
        exec(compile(ast.fix_missing_locations(ast.Module(body=[reference], type_ignores=[])),
                     '<original-private-bridge>', 'exec'), namespace)
        module = types.ModuleType('private_bridge_fixture')
        exec('def verify(root): pass\ndef _verify_owned(root): pass\n', vars(module))
        class LoggedRoot:
            def __init__(self, label, events, value):
                self.label, self.events, self.value = label, events, value
            def __fspath__(self):
                self.events.append(self.label)
                if isinstance(self.value, Exception): raise self.value
                return self.value
        namespace['_owner_module'] = lambda kind: module
        for first, second, first_kind, second_kind, expected, order in (
            ('/alpha', '/alpha', 'logged', 'logged', True, ['first', 'second']),
            ('/wrong', '/alpha', 'logged', 'logged', False, ['first']),
            ('/alpha', '/wrong', 'logged', 'logged', False, ['first', 'second']),
            ('/alpha', '/alpha', 'path', 'path', True, []),
            ('/wrong', '/alpha', 'path', 'path', False, []),
            ('/alpha', '/wrong', 'path', 'path', False, []),
            ('/alpha', '/alpha', 'path', 'logged', True, ['second']),
            ('/wrong', '/alpha', 'path', 'logged', False, []),
            ('/alpha', OSError('second root failed'), 'path', 'logged', False, ['second']),
        ):
            results = []
            for call in (namespace['_private_operation_wrapper'], cleanup._private_operation_wrapper):
                events = []
                operation = types.SimpleNamespace(_kind='winner', _root='/alpha')
                caller = types.SimpleNamespace(f_globals=vars(module), f_code=module._verify_owned.__code__,
                    f_locals={'_operation': operation, 'root': Path(second) if second_kind == 'path' else LoggedRoot('second', events, second)})
                frame = types.SimpleNamespace(f_globals=vars(module), f_code=module.verify.__code__, f_back=caller,
                    f_locals={'_operation': operation, 'root': Path(first) if first_kind == 'path' else LoggedRoot('first', events, first)})
                with patch.object(cleanup, '_owner_module', lambda kind: module):
                    outcome = self._root_text_outcome(lambda: call(frame, 'invariant', operation) is caller)
                results.append((outcome, events))
            self.assertEqual(results[0], results[1])
            wanted = ('error', OSError, ('second root failed',), None) if isinstance(second, Exception) else ('return', bool, expected)
            self.assertEqual(results[1], (wanted, order))


class TypedCheckerSuccessorStaticControls(unittest.TestCase):
    @staticmethod
    def checker_path(name):
        root = Path(__file__).resolve().parents[2]
        return root / ('tools/' if name == 'coverage_loop_proofs.py'
                       else 'tools/carla_lane_oracle/') / name

    def test_complete_predecessor_bytes_remain_frozen(self):
        for name, digest in BoundedOwnerDistinctMechanismControls._SOURCE_SHA256.items():
            with self.subTest(checker=name):
                raw = self.checker_path(name).read_bytes()
                before, mapping = _checker_source_predecessor(name, raw)
                self.assertEqual(hashlib.sha256(before).hexdigest(), digest)
                self.assertEqual(set(mapping), set(range(1, len(before.splitlines()) + 1)))
                # The current checker is distinct; the historical fixture never
                # becomes the source executed by these current controls.
                self.assertNotEqual(raw, before)

    def test_unrelated_edits_in_every_complete_checker_are_refused(self):
        for name in BoundedOwnerDistinctMechanismControls._SOURCE_SHA256:
            raw = self.checker_path(name).read_bytes()
            with self.subTest(checker=name), self.assertRaises(AssertionError):
                _checker_source_predecessor(name, raw + b'\ndef unreviewed_unrelated_checker():\n    return True\n')
            start, stop, _, after = next(edit for edit in _TYPED_CHECKER_SOURCE_EDITS[name]
                                        if edit[3])
            lines = raw.decode('utf-8').splitlines(keepends=True)
            lines[start] = lines[start].rstrip('\n') + ' # changed successor span\n'
            with self.subTest(checker=name, fault='new span'), self.assertRaises(AssertionError):
                _checker_source_predecessor(name, ''.join(lines).encode('utf-8'))

    def test_exact_current_physical_observation_addresses(self):
        root = Path(__file__).resolve().parents[2]
        with _operation_reached_bindings(self, root, root, (cleanup,)):
            pass

    def test_distinct_old_site_ids_bind_unique_current_compiled_calls(self):
        import cache_key_contracts as cache
        import grouped_y_finiteness_contracts as grouped
        import raw_cut_inverse_contracts as raw_cut
        import seed_count_contracts as seed
        controls = BoundedOwnerDistinctMechanismControls()
        loops, core = BoundedOwnerCurrentControls.coverage(self)
        from carla_lane_oracle import seed_count_contracts as package_seed
        cases = (
            (loops._reviewed_dependency_hashes, 959, 'path.read_bytes()'),
            (accepted._verify_current_for_pin_pair, 162, '(root / path).read_text()'),
            (grouped.verify, 31, '(root / p).read_text()'),
            (raw_cut.verify_premises, 66, "(root / 'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_text()"),
            (source.read_pins, 202, "(root / PINS).read_text(encoding='utf-8')"),
            (source.verify_group, 234, "(root / path).read_text(encoding='utf-8')"),
            (cache.inventory, 106, '_inputs.observe_bytes(_input_owner, root, rel.as_posix())'),
            (seed.verify_score, 649, '_inputs.observe_bytes(_input_owner, root, MODULE)'),
            (seed.verify_score, 684, '_inputs.observe_bytes(_input_owner, root, MODULE)'),
            (cache.inventory, 150, '_inputs.observe_bytes(_input_owner, root, rel.as_posix())'),
            (seed.verify_score_caller_inventory, 'station-census', '_inputs.observe_bytes(_input_owner, root, MODULE)'),
            (cleanup._CacheInputs.observe_bytes, 1205, '_regular(root, path).read_bytes()'),
            (cache.inventory, 103, 'path.read_text()'),
            (cache.inventory, 113, "require(source.token_sha256(text) == source.token_sha256(_inputs.text_default(_input_owner, root, rel.as_posix())) == seed_count.score_family_token_sha256(hashlib.sha256(physical).hexdigest()), 'unreviewed supplied score-helper source')"),
            (package_seed.verify_score_caller_inventory, 542, 'guard.production_mojo_paths(root)'),
            (loops._construction_boundary_callers, 1220, 'cache_key.input_paths(Path(root))'),
            (core._operation_production_paths, 1541, '_operation_fail(_operation, error)'),
            (loops.construction_boundary_loops, 1349, 'cleanup._operation_fail(_operation, error)'),
        )
        for function, line, expression in cases:
            with self.subTest(function=function.__qualname__, line=line):
                self.assertTrue(callable(controls._site(function, line, expression)))

    def test_typed_public_adapter_projection_rejects_new_authority_drift(self):
        for module, name in ((selector, 'verify_premises'), (selector, '_verify_premises'),
                             (accepted, 'predecessor_pin_pair'), (accepted, '_predecessor_pin_pair')):
            original = function_ast(module, name)
            for fault in ('path', 'operation', 'missing', 'inner read'):
                node = copy.deepcopy(original)
                calls = [item for item in ast.walk(node) if isinstance(item, ast.Call)
                         and isinstance(item.func, ast.Attribute) and isinstance(item.func.value, ast.Name)
                         and item.func.value.id == '_typed_source'
                         and item.func.attr in ('historical_text', 'historical_bytes')]
                self.assertTrue(calls, 'missing typed provenance adapter')
                call = calls[0]
                self.assertEqual(len(call.args), 3)
                self.assertIsInstance(call.args[0], ast.Name)
                self.assertEqual(call.args[0].id, 'root')
                if fault == 'path': call.args[1] = ast.Constant('foreign.mojo')
                elif fault == 'operation': call.keywords.append(ast.keyword(arg='_operation', value=ast.Constant(None)))
                elif fault == 'missing': call.func.value.id = 'unreviewed_source'
                else: call.args[2] = ast.Constant('historical substitute')
                with self.subTest(function=name, fault=fault), self.assertRaises(AssertionError):
                    typed_adapter_predecessor(node)

    def test_typed_captured_reread_projection_cannot_precede_physical_compare(self):
        for name in ('verify_premises', '_verify_premises'):
            node = function_ast(selector, name)
            for parent in ast.walk(node):
                body = getattr(parent, 'body', ())
                if not isinstance(body, list):
                    continue
                for index, item in enumerate(body):
                    if (isinstance(item, ast.Assign) and isinstance(item.value, ast.Call)
                            and ast.unparse(item.value).startswith('_typed_source.historical_text(root, name, text')):
                        body[index - 1], body[index] = body[index], body[index - 1]
                        break
                else:
                    continue
                break
            else:
                self.fail('missing captured-reread projection control')
            with self.subTest(function=name), self.assertRaises(AssertionError):
                typed_adapter_predecessor(node)

    def test_seed_supplied_read_shape_preserves_observation_before_projection(self):
        import seed_count_contracts as seed
        original = function_ast(seed, 'reviewed_text')
        first, final = _seed_supplied_read_contract(original)
        self.assertEqual([ast.unparse(item.value) for item in (first[0], final[0])],
                         ['(Path(root) / MODULE).read_bytes()'] * 2)
        for fault in ('first observation', 'supplied compare', 'early projection', 'final observation', 'raw equality'):
            node = copy.deepcopy(original)
            before, after = _seed_supplied_read_contract(node)
            if fault == 'first observation': before[1].body[0].value.args[2] = ast.Name(id='historical', ctx=ast.Load())
            elif fault == 'supplied compare': before[2].value.args[0] = ast.Constant(True)
            elif fault == 'early projection':
                left, right = node.body.index(before[2]), node.body.index(before[3])
                node.body[left], node.body[right] = node.body[right], node.body[left]
            elif fault == 'final observation': after[1].body[0].value.args[2] = ast.Name(id='current_raw', ctx=ast.Load())
            else: after[2].value.args[0] = ast.parse('physical == physical', mode='eval').body
            with self.subTest(fault=fault), self.assertRaises(AssertionError):
                _seed_supplied_read_contract(node)

    def test_station_census_adds_only_authority_map_observation_before_projection(self):
        import seed_count_contracts as seed
        original = function_ast(seed, 'verify_score_caller_inventory')
        _station_census_read_contract(original)
        for fault in ('endpoint guard', 'unobserved lease', 'unchecked supplied text'):
            node = copy.deepcopy(original)
            clause = _station_census_read_contract(node)
            if fault == 'endpoint guard': clause.test = ast.parse('rel.as_posix() == MODULE', mode='eval').body
            elif fault == 'unobserved lease':
                call = next(item for item in ast.walk(clause) if isinstance(item, ast.Call)
                            and ast.unparse(item) == '_inputs.observe_bytes(_input_owner, root, MODULE)')
                call.func.attr = 'raw'
            else: clause.body[1].value.args[0] = ast.Constant(True)
            with self.subTest(fault=fault), self.assertRaises(AssertionError):
                _station_census_read_contract(node)

    def test_each_seed_dispatch_reconciles_outer_current_bytes_after_delegate(self):
        """Isolated control-flow checks; no synthetic root is admitted as real."""
        import types
        import seed_count_contracts as seed
        raw = Path(seed.__file__).read_bytes()
        _checker_source_predecessor('seed_count_contracts.py', raw)
        definition = function_ast(seed, '_verify_seed_body')
        _seed_dispatch_body_contract(definition)
        definition.name = 'verify'
        compiled = compile(ast.Module(body=[definition], type_ignores=[]),
                           '<isolated-current-seed-dispatch-control>', 'exec')
        for route, digest in (('verify_score', seed.SCORE_AFTER_SHA256),
                              ('verify_frontier', seed.FRONTIER_AFTER_SHA256),
                              ('verify_support', seed.SUPPORT_AFTER_SHA256),
                              ('verify_optional', seed.OPTIONAL_AFTER_SHA256)):
            for changed in (False, True):
                with self.subTest(route=route, changed=changed), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    target = root/seed.MODULE
                    target.parent.mkdir(parents=True)
                    target.write_bytes(b'current physical A')
                    events, projections, reads = [], [], []
                    edge = {'isolated_delegate': route}
                    def projected(actual_root, path, value, **kwargs):
                        self.assertEqual((actual_root, path, value), (root, seed.MODULE, b'current physical A'))
                        projections.append(value)
                        # Constant provenance deliberately cannot distinguish A/B.
                        return b'identical historical projection'
                    def delegate(actual_root, **kwargs):
                        self.assertEqual(actual_root, root)
                        self.assertEqual(kwargs, {'_expected_raw': b'current physical A'})
                        events.append(route)
                        if changed: target.write_bytes(b'current physical B')
                        return edge
                    def unexpected(*args, **kwargs):
                        self.fail('wrong delegated or historical verification branch')
                    namespace = dict(vars(seed))
                    namespace.update(read_record=lambda *args, **kwargs: {},
                        sha=lambda value: digest,
                        _typed_source=types.SimpleNamespace(historical_bytes=projected))
                    for name in ('verify_score', 'verify_frontier', 'verify_support', 'verify_optional',
                                 'verify_source', '_verify_bound_inputs', 'verify_premises'):
                        namespace[name] = delegate if name == route else unexpected
                    exec(compiled, namespace)
                    original_read = Path.read_bytes
                    def read(path):
                        value = original_read(path)
                        if path == target: reads.append(value)
                        return value
                    with patch.object(Path, 'read_bytes', read):
                        if changed:
                            with self.assertRaisesRegex(ValueError, 'Map changed during verification'):
                                namespace['verify'](root)
                        else:
                            self.assertIs(namespace['verify'](root), edge)
                    self.assertEqual(events, [route])
                    self.assertEqual(projections, [b'current physical A'])
                    self.assertEqual(reads, [b'current physical A',
                        b'current physical B' if changed else b'current physical A'])

    def test_coverage_row_discriminators_retain_actual_dependency_join(self):
        loops, _ = BoundedOwnerCurrentControls.coverage(self)
        for name in ('_historical_reviewed_nonempty_loops', 'guarded_loop_proof'):
            original = function_ast(loops, name)
            _coverage_current_discriminator_contract(original)
            for fault in ('wrong digest', 'unchecked current'):
                node = copy.deepcopy(original)
                statements = _coverage_current_discriminator_contract(node)
                check = statements[1]
                if fault == 'wrong digest': check.test.comparators[0] = ast.Constant('historical pin')
                else: check.test = ast.Constant(False)
                with self.subTest(function=name, fault=fault), self.assertRaises(AssertionError):
                    _coverage_current_discriminator_contract(node)

    def test_semantic_sink_guards_arm_only_at_marked_publication(self):
        controls = BoundedOwnerDistinctMechanismControls()
        sinks = ((source, 'token_sha256'), (source, 'tokens'), (json, 'loads'))
        originals = [getattr(module, name) for module, name in sinks]
        expected = [function('{}') for function in originals]
        marked = []
        with controls._no_marked_semantics(marked) as arm:
            self.assertTrue(all(getattr(module, name) is original
                                for (module, name), original in zip(sinks, originals)))
            arm()
            marker = 'marked semantic input'
            marked.append(marker)
            for (module, name), value in zip(sinks, expected):
                with self.subTest(sink=name):
                    function = getattr(module, name)
                    with self.assertRaisesRegex(AssertionError, 'marked observation reached semantic sink'):
                        function(marker)
                    self.assertEqual(function('{}'), value)
            with self.assertRaisesRegex(AssertionError, 'armed more than once'):
                arm()
        self.assertTrue(all(getattr(module, name) is original
                            for (module, name), original in zip(sinks, originals)))
        for fault in ('unarmed publication', 'arming without publication', 'arming after publication'):
            marked = []
            with self.subTest(fault=fault), self.assertRaisesRegex(
                    AssertionError, 'semantic sink arming and marked publication differ'):
                with controls._no_marked_semantics(marked) as arm:
                    if fault == 'arming without publication':
                        arm()
                    else:
                        marked.append('unobserved marked input')
                        if fault == 'arming after publication':
                            with self.assertRaisesRegex(AssertionError, 'armed after marked publication'):
                                arm()
            self.assertTrue(all(getattr(module, name) is original
                                for (module, name), original in zip(sinks, originals)))


    def test_checker_receipt_lifecycle_and_return_registration_are_explicit(self):
        raw = Path(cleanup.__file__).read_bytes()
        _checker_source_predecessor('full_audit_cleanup_contracts.py', raw)
        tree = ast.parse(raw)
        owner = next(node for node in tree.body if isinstance(node, ast.ClassDef)
                     and node.name == '_InvariantInputs')
        for name in ('__init__', '_invalidate', 'close'):
            node = next(item for item in owner.body if isinstance(item, ast.FunctionDef)
                        and item.name == name)
            _one_ast_run(node, 'self._checker_receipt = False')
        binding = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                       and node.name == 'proof_bindings')
        statements = _one_ast_run(binding, """
if _operation is not None:
    _operation._bind_checker_receipt(root, executing)
return result
""")
        calls = [item for item in ast.walk(binding) if isinstance(item, ast.Call)
                 and isinstance(item.func, ast.Attribute) and item.func.attr == '_bind_checker_receipt']
        self.assertEqual(len(calls), 1)
        self.assertIs(calls[0], statements[0].body[0].value)



class TypedBorrowedProvenancePureControls(unittest.TestCase):
    """Isolated helper wiring, never physical current-root admission evidence."""

    def probe(self):
        import types
        raw = Path(cleanup.__file__).read_bytes()
        _checker_source_predecessor('full_audit_cleanup_contracts.py', raw)
        node = function_ast(cleanup, 'reviewed_typed_text')
        root, path, physical = Path('/isolated-typed-owner'), 'module.mojo', b'current typed'
        events, reads, observations, projections, admissions = [], [], [], [], []
        token = object()

        class Refusal(ValueError):
            pass

        class Operation:
            def __init__(self):
                self.failed = False
                self.active = True

        operation, foreign = Operation(), Operation()

        def require(value, message):
            if not value:
                raise Refusal(message)

        def fail(owner, error):
            events.append(('failure', owner))
            if type(owner) is Operation:
                owner.failed = True
            raise error

        class Base:
            def raw(self, owner, actual_root, actual_path):
                events.append(('lease-image', owner))
                require(owner is token and actual_root == root and actual_path == path,
                        'invalid isolated base input context')
                return physical

        class Borrowed(Base):
            def _check(self, owner, actual_root):
                events.append(('authenticate', self))
                try:
                    require(type(self._operation) is Operation, 'malformed canonical owner')
                    require(owner is token and actual_root == root,
                            'invalid isolated borrowed token or root')
                    require(self._operation.active and not self._operation.failed,
                            'inactive isolated borrowed owner')
                except Refusal as error:
                    fail(self._operation, error)

        lease = Borrowed()
        lease._operation = operation
        # A permissive instance attribute cannot replace the canonical class
        # authentication at the helper's entry boundary.
        lease._check = lambda *args: events.append(('unchecked-instance-hook', lease))
        returned = []

        class PhysicalFile:
            def read_bytes(self):
                value = returned[len(reads)] if len(reads) < len(returned) else physical
                reads.append(value)
                events.append(('read', len(reads)))
                return value

        def regular(actual_root, actual_path):
            require((actual_root, actual_path) == (root, path), 'wrong physical input')
            return PhysicalFile()

        def check(owner, actual_root):
            events.append(('operation-check', owner))
            if owner is not None:
                if (type(owner) is not Operation or not owner.active or owner.failed
                        or actual_root != root):
                    fail(owner, Refusal('inactive isolated operation'))

        def observe(actual_root, actual_path, value, *, _operation=None):
            observations.append((_operation, value))
            events.append(('observe', _operation))
            if _operation is not None:
                check(_operation, actual_root)
                if actual_path != path or type(value) is not bytes or value != physical:
                    fail(_operation, Refusal('returned physical image changed'))
            return value

        def tokens(value):
            require(type(value) is str, 'nontext isolated tokens')
            return value.split('#', 1)[0].strip()

        def supplied(actual_root, actual_path, value, **kwargs):
            events.append(('supplied', kwargs['_operation']))
            require(kwargs == {'_operation': kwargs['_operation'], 'mode': 'physical',
                               'supplied': True, '_checked_raw': physical},
                    'changed supplied observation arguments')
            check(kwargs['_operation'], actual_root)
            require(actual_path == path and tokens(value) == tokens(physical.decode()),
                    'changed supplied current tokens')
            return value

        def admitted(actual_root, **kwargs):
            require(actual_root == root and kwargs == {'exact': True}, 'changed unowned gate')
            admissions.append('unowned')

        def record(owner, actual_root, **kwargs):
            require(owner is operation and actual_root == root and kwargs == {'exact': True},
                    'changed owned gate')
            admissions.append('owned')

        def historical(actual_path, text, *, pr760=False):
            require(pr760 is False, 'isolated legacy typed probe received PR760 provenance')
            require((actual_path, text) == (path, physical.decode()), 'nonphysical provenance')
            projections.append(text)
            return 'historical provenance'

        namespace = dict(vars(cleanup))
        namespace.update(require=require, _operation_fail=fail, _operation_check=check,
            _CacheInputs=Base, _BorrowedCacheInputs=Borrowed, _regular=regular,
            _observe_bytes=observe, _observe_text=supplied, verify=admitted,
            _operation_record=record, _historical_typed_text=historical,
            source=types.SimpleNamespace(token_sha256=tokens),
            typed_boundary=types.SimpleNamespace(EDGES={path: {'after_token_sha256': 'current typed'}},
                is_current=lambda name, value: name == path and value in (physical, physical.decode())))
        exec(compile(ast.Module(body=[node], type_ignores=[]),
                     '<isolated-borrowed-typed-provenance>', 'exec'), namespace)
        return types.SimpleNamespace(function=namespace['reviewed_typed_text'], root=root,
            path=path, physical=physical, token=token, lease=lease, base=Base(),
            operation=operation, foreign=foreign, events=events, reads=reads,
            observations=observations, projections=projections, admissions=admissions,
            returned=returned, Refusal=Refusal)

    def test_authenticated_borrowed_owner_joins_both_reads_and_supplied_view(self):
        for explicit in ('implicit', 'same'):
            with self.subTest(explicit=explicit):
                p = self.probe()
                result = p.function(p.root, p.path, 'current typed # supplied comment',
                    _inputs=p.lease, _input_owner=p.token,
                    _operation=p.operation if explicit == 'same' else None)
                self.assertEqual(result, 'historical provenance')
                self.assertEqual(p.reads, [p.physical, p.physical])
                self.assertEqual(p.observations, [(p.operation, p.physical)] * 2)
                self.assertEqual(p.events[0], ('authenticate', p.lease))
                self.assertIn(('supplied', p.operation), p.events)
                self.assertNotIn(('unchecked-instance-hook', p.lease), p.events)
                self.assertEqual(p.projections, [p.physical.decode()])
                self.assertEqual(p.admissions, [])
                self.assertFalse(p.operation.failed)

    def test_first_and_final_returned_mutations_poison_the_joined_owner(self):
        for ordinal in (1, 2):
            with self.subTest(ordinal=ordinal):
                p = self.probe()
                changed = p.physical + b'\n# returned physical B\n'
                p.returned.extend([p.physical] * (ordinal - 1) + [changed])
                arguments = {'_inputs': p.lease, '_input_owner': p.token}
                with self.assertRaisesRegex(p.Refusal, '^returned physical image changed$'):
                    p.function(p.root, p.path, p.physical.decode(), **arguments)
                self.assertTrue(p.operation.failed)
                self.assertEqual(len(p.reads), ordinal)
                self.assertEqual(p.observations[-1], (p.operation, changed))
                self.assertEqual(p.projections, [])
                # Catching the first failure cannot turn the same lease into
                # another authority, even after subsequent reads return A.
                with self.assertRaisesRegex(p.Refusal, 'inactive isolated borrowed owner'):
                    p.function(p.root, p.path, p.physical.decode(), **arguments)
                self.assertEqual(len(p.reads), ordinal)
                self.assertTrue(p.operation.failed)

    def test_bad_borrowed_authority_refuses_before_current_or_historical_reads(self):
        faults = ('explicit mismatch', 'missing token', 'wrong token', 'foreign root',
                  'inactive owner', 'malformed canonical owner', 'invalid lease type', 'lease subclass',
                  'owner without inputs')
        for text in ('current typed', 'historical text'):
            for fault in faults:
                with self.subTest(text=text, fault=fault):
                    p = self.probe()
                    root = p.root
                    arguments = {'_inputs': p.lease, '_input_owner': p.token}
                    if fault == 'explicit mismatch': arguments['_operation'] = p.foreign
                    elif fault == 'missing token': arguments['_input_owner'] = None
                    elif fault == 'wrong token': arguments['_input_owner'] = object()
                    elif fault == 'foreign root': root = p.root/'foreign'
                    elif fault == 'inactive owner': p.operation.active = False
                    elif fault == 'malformed canonical owner': p.lease._operation = object()
                    elif fault == 'invalid lease type': arguments['_inputs'] = object()
                    elif fault == 'lease subclass':
                        class Sublease(type(p.lease)):
                            pass
                        candidate = Sublease()
                        candidate._operation = p.operation
                        arguments['_inputs'] = candidate
                    else: arguments['_inputs'] = None
                    with self.assertRaises(p.Refusal):
                        p.function(root, p.path, text, **arguments)
                    self.assertEqual(p.reads, [])
                    self.assertEqual(p.projections, [])
                    self.assertEqual(p.admissions, [])
                    trusted = fault not in ('malformed canonical owner', 'invalid lease type', 'lease subclass',
                                            'owner without inputs')
                    self.assertEqual(p.operation.failed, trusted)
                    self.assertFalse(p.foreign.failed)

    def test_historical_base_unowned_and_explicit_operation_domains_stay_distinct(self):
        for mode in ('borrowed', 'base', 'unowned', 'operation'):
            p = self.probe()
            arguments = ({'_inputs': p.lease if mode == 'borrowed' else p.base,
                          '_input_owner': p.token} if mode in ('borrowed', 'base') else
                         {'_operation': p.operation} if mode == 'operation' else {})
            for text in ('historical text', 'current typed + stale executable token'):
                with self.subTest(mode=mode, text=text):
                    self.assertIs(p.function(p.root, p.path, text, **arguments), text)
                    self.assertEqual(p.reads, [])
                    self.assertEqual(p.projections, [])
                    self.assertEqual(p.admissions, [])
            self.assertEqual(p.function(p.root, p.path, 'current typed', **arguments),
                             'historical provenance')
            expected_owner = p.operation if mode in ('borrowed', 'operation') else None
            self.assertEqual(p.observations, [(expected_owner, p.physical)] * 2)
            self.assertEqual(p.admissions, ['unowned'] if mode == 'unowned' else
                             ['owned'] if mode == 'operation' else [])
        p = self.probe()
        text = 'outside the typed edge domain'
        self.assertIs(p.function(p.root, 'unlisted.mojo', text, _inputs=object()), text)
        self.assertEqual((p.events, p.reads, p.projections, p.admissions), ([], [], [], []))


class TypedBorrowedProvenanceCurrentControls(unittest.TestCase):
    """Actual current-root borrowed reads; all production admission stays real."""
    setUp = BoundedOwnerCurrentControls.setUp
    audit = BoundedOwnerCurrentControls.audit
    assert_closed = BoundedOwnerCurrentControls.assert_closed
    _frame = staticmethod(BoundedOwnerDistinctMechanismControls._frame)

    def test_first_and_final_borrowed_reads_refuse_and_caught_errors_stay_sticky(self):
        from functools import wraps
        import cache_key_contracts as cache
        import seed_count_contracts as seed
        helper = cleanup.reviewed_typed_text
        raw_source = Path(cleanup.__file__).read_bytes()
        _checker_source_predecessor('full_audit_cleanup_contracts.py', raw_source)
        path = seed.MODULE
        physical = (self.root/path).read_bytes()
        reason = 'full-audit cleanup successor: consumed operation bytes changed: ' + path
        for ordinal in (1, 2):
            with self.subTest(ordinal=ordinal):
                selected, reads, marked, observed, caught, retried, projections = [], [], [], [], [], [], []
                original_read = Path.read_bytes
                original_observe = cleanup._operation_observe
                original_projection = cleanup._historical_typed_text

                @wraps(original_read)
                def read(actual, *args, **kwargs):
                    value = original_read(actual, *args, **kwargs)
                    frame = sys._getframe(1)
                    if frame.f_code is not helper.__code__ or actual != self.root/path:
                        return value
                    lease = frame.f_locals.get('_inputs')
                    if (type(lease) is not cleanup._BorrowedCacheInputs
                            or self._frame(seed.verify_score, frame) is None
                            or self._frame(cache.verify, frame) is not lease._owner_frame):
                        return value
                    self.assertIsNone(frame.f_locals['explicit_operation'])
                    operation = frame.f_locals['_operation']
                    self.assertIs(operation, lease._operation)
                    self.assertIs(frame.f_locals['_input_owner'], lease._owner)
                    if not selected:
                        self.assertEqual(operation._state, 'active')
                        self.assertFalse(operation._failed)
                        selected.append((frame, lease, operation))
                    self.assertIs(frame, selected[0][0], 'a caught refusal reached another physical read')
                    reads.append(value)
                    if len(reads) == ordinal:
                        self.assertEqual(marked, [])
                        value += b'\n# borrowed physical B\n'
                        marked.append(value)
                    return value

                @wraps(original_observe)
                def observe(operation, root, name, value, mode):
                    if marked and value is marked[0]:
                        self.assertIs(operation, selected[0][2])
                        self.assertEqual((root, name, mode), (self.root, path, 'bytes'))
                        observed.append(value)
                    return original_observe(operation, root, name, value, mode)

                @wraps(original_projection)
                def project(name, text, **kwargs):
                    if selected and sys._getframe(1) is selected[0][0]:
                        projections.append((name, text))
                    return original_projection(name, text, **kwargs)

                @wraps(helper)
                def checked(root, name, text, **kwargs):
                    try:
                        return helper(root, name, text, **kwargs)
                    except cleanup._OperationCoherenceError as error:
                        if not selected or kwargs.get('_inputs') is not selected[0][1] or caught:
                            raise
                        frame, lease, operation = selected[0]
                        self.assertIsNone(kwargs.get('_operation'))
                        self.assertEqual(str(error), reason)
                        self.assertTrue(operation._failed)
                        caught.append(error)
                        with self.assertRaises(cleanup._OperationCoherenceError) as lease_failure:
                            lease.raw(kwargs['_input_owner'], root, name)
                        with self.assertRaises(cleanup._OperationCoherenceError) as retry_failure:
                            helper(root, name, text, **kwargs)
                        self.assertEqual(str(lease_failure.exception), reason)
                        self.assertEqual(str(retry_failure.exception), reason)
                        retried.extend((lease_failure.exception, retry_failure.exception))
                        raise

                with self.audit() as events, patch.object(Path, 'read_bytes', read), \
                        patch.object(cleanup, '_operation_observe', observe), \
                        patch.object(cleanup, '_historical_typed_text', project), \
                        patch.object(cleanup, 'reviewed_typed_text', checked):
                    with self.assertRaises(ValueError) as public:
                        invariant.verify(self.root)
                self.assertEqual(len(selected), 1)
                self.assertEqual(len(marked), 1)
                self.assertEqual(reads, [physical] * ordinal)
                self.assertEqual(observed, marked)
                self.assertEqual(len(caught), 1)
                self.assertEqual(len(retried), 2)
                self.assertEqual(projections, [])
                operation = selected[0][2]
                self.assertEqual(events['admissions'], [operation])
                self.assertTrue(operation._failed)
                self.assertEqual(operation._failure_reason, reason)
                chain, error = [], public.exception
                while error is not None and all(error is not item for item in chain):
                    chain.append(error)
                    error = error.__cause__
                self.assertTrue(any(error is caught[0] for error in chain))
                self.assert_closed(operation)
                self.assertEqual((self.root/path).read_bytes(), physical)



class StandaloneSeedFrameControls(unittest.TestCase):
    """Exact body extraction and canonical wrapper routing, without admission."""
    def seed(self):
        import importlib
        return importlib.import_module((cleanup.__package__ + '.' if cleanup.__package__ else '')
                                       + 'seed_count_contracts')

    def test_complete_original_body_and_signature_are_retained(self):
        seed = self.seed()
        text = inspect.getsource(seed._verify_seed_body)
        self.assertEqual(text.count('def _verify_seed_body('), 1)
        original = text.replace('def _verify_seed_body(', 'def verify(', 1)
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(),
                         '6a8c6ca3784540187b5e658ebd1425d06cbf5a4698b69a14df18613befcb00dd')
        self.assertEqual(inspect.signature(seed.verify), inspect.signature(seed._verify_seed_body))

    def test_explicit_borrowed_dispatch_forwards_exact_objects_without_factory(self):
        seed = self.seed()
        root, operation, expected, result = object(), object(), object(), object()
        def body(got_root, *, _operation=None, _expected_raw=None):
            self.assertIs(got_root, root)
            self.assertIs(_operation, operation)
            self.assertIs(_expected_raw, expected)
            return result
        def forbidden(*args, **kwargs):
            self.fail('Borrowed seed route attempted to enter a standalone owner')
        with patch.object(seed, '_verify_seed_body', body), patch.object(cleanup, '_operation_enter', forbidden):
            self.assertIs(seed.verify(root, _operation=operation, _expected_raw=expected), result)

    def test_frame_registry_code_identity_and_public_transparency(self):
        import types
        seed = self.seed()
        frame = types.SimpleNamespace(f_globals=vars(seed), f_code=seed._verify_standalone.__code__)
        self.assertEqual(cleanup._seed_frame_kind(frame), 'seed')
        public = types.SimpleNamespace(f_globals=vars(seed), f_code=seed.verify.__code__)
        self.assertIsNone(cleanup._seed_frame_kind(public, include_aliases=True))
        namespace = dict(vars(seed))
        namespace['_verify_standalone'] = types.FunctionType(seed._verify_standalone.__code__, namespace)
        alias = types.SimpleNamespace(f_globals=namespace, f_code=seed._verify_standalone.__code__)
        self.assertIsNone(cleanup._seed_frame_kind(alias))
        self.assertEqual(cleanup._seed_frame_kind(alias, include_aliases=True), 'alias_seed')
        copied = seed._verify_standalone.__code__.replace()
        self.assertEqual(copied, seed._verify_standalone.__code__)
        self.assertIsNot(copied, seed._verify_standalone.__code__)
        module = types.ModuleType(seed.__name__)
        module.__dict__.update(namespace)
        module._verify_standalone = types.FunctionType(copied, vars(module))
        fake = types.SimpleNamespace(f_globals=vars(module), f_code=copied)
        with patch.dict(sys.modules, {seed.__name__: module}):
            self.assertIsNone(cleanup._seed_frame_kind(fake))

    def test_actual_unregistered_and_registered_alias_wrappers_remain_unowned(self):
        import importlib.util
        seed = self.seed()
        for registered in (False, True):
            name = '_standalone_seed_alias_probe'
            spec = importlib.util.spec_from_file_location(name, seed.__file__)
            alias = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(alias)
            seen = []
            marker = object()
            def body(root, *, _operation=None, _expected_raw=None):
                seen.append(_operation)
                self.assertIsNone(_operation)
                return marker
            # A routing sentinel only; no semantic verification is claimed.
            with self.subTest(registered=registered), patch.object(alias, '_verify_seed_body', body):
                if registered:
                    with patch.dict(sys.modules, {name: alias}):
                        self.assertIs(alias.verify(Path(seed.__file__).parents[2]), marker)
                else:
                    self.assertNotIn(name, sys.modules)
                    self.assertIs(alias.verify(Path(seed.__file__).parents[2]), marker)
            self.assertEqual(seen, [None])

    def test_historical_before_endpoint_is_lazy_and_closed(self):
        seed = self.seed()
        source_root = Path(cleanup.__file__).resolve().parents[2]
        typed = cleanup.typed_boundary
        historical_map = typed.predecessor_source(
            seed.MODULE, (source_root/seed.MODULE).read_text(encoding='utf-8'))
        self.assertEqual(cleanup.sha(historical_map), typed.EDGES[seed.MODULE]['before_sha256'])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root/seed.MODULE).parent.mkdir(parents=True)
            (root/seed.MODULE).write_text(historical_map)
            (root/seed.MIGRATION).parent.mkdir(parents=True)
            (root/seed.MIGRATION).write_bytes((source_root/seed.MIGRATION).read_bytes())
            before = seed.predecessor_source(seed.successor_source(root), seed.read_record(root))
            self.assertEqual(seed.sha(before), seed.BEFORE_SHA256)
            (root/seed.MODULE).write_text(before)
            owners, calls = [], []
            def profile(frame, event, value):
                if event == 'call' and frame.f_code is cleanup.verify.__code__:
                    calls.append(True)
                if event == 'return' and frame.f_code is cleanup._operation_enter.__code__:
                    if isinstance(value, tuple) and value[1]:
                        owners.append(value[0])
            self.assertIsNone(sys.getprofile())
            sys.setprofile(profile)
            try:
                self.assertIsNone(seed.verify(root))
            finally:
                sys.setprofile(None)
            self.assertEqual(calls, [])
            self.assertEqual(len(owners), 1)
            self.assertEqual(owners[0]._kind, 'seed')
            self.assertEqual(owners[0]._state, 'closed')
            self.assertFalse(owners[0]._failed)
            self.assertIsNone(owners[0]._owner_frame)


class StandaloneSeedCurrentControls(unittest.TestCase):
    """Whole real verifications on one independently copied physical fixture."""
    @classmethod
    def setUpClass(cls):
        import importlib
        import _full_audit_test_fixtures as fixtures
        cls.seed = importlib.import_module((cleanup.__package__ + '.' if cleanup.__package__ else '')
                                          + 'seed_count_contracts')
        source_root = Path(cleanup.__file__).resolve().parents[2]
        owner = type('CurrentSeedFixture', (), {'addCleanup': staticmethod(cls.addClassCleanup)})()
        cls.root = fixtures.copy_current_root(owner, source_root)

    @contextmanager
    def traced(self, callback=None):
        counts, owners, reads = Counter(), [], Counter()
        self.assertIsNone(sys.getprofile())
        def profile(frame, event, value):
            if event == 'call':
                if frame.f_code is cleanup.verify.__code__:
                    counts['full'] += 1
                elif frame.f_code is cleanup.typed_boundary.verify_sources.__code__:
                    counts['typed'] += 1
                elif frame.f_code is cleanup._InvariantInputs.finish.__code__:
                    counts['finish'] += 1
                elif frame.f_code is Path.read_bytes.__code__:
                    path = frame.f_locals.get('self')
                    if isinstance(path, Path) and path.is_relative_to(self.root):
                        reads[path.relative_to(self.root).as_posix()] += 1
            elif event == 'return' and frame.f_code is cleanup._operation_enter.__code__:
                if isinstance(value, tuple) and value[1]:
                    owners.append(value[0])
            if callback is not None:
                callback(frame, event, value, owners)
        sys.setprofile(profile)
        try:
            yield counts, owners, reads
        finally:
            sys.setprofile(None)

    def closed(self, owner, failed):
        self.assertEqual(owner._kind, 'seed')
        self.assertEqual(owner._state, 'closed')
        self.assertEqual(owner._failed, failed)
        self.assertFalse(owner._raw)
        self.assertIsNone(owner._owner_frame)
        with self.assertRaises(ValueError):
            cleanup._operation_check(owner, self.root)

    def test_two_current_calls_each_admit_once_read_and_finish(self):
        results, previous = [], []
        record = self.seed.read_record(self.root)
        paths = {path for group in ('historical_records', 'unchanged_inputs',
                 'unchanged_correctness_tests', 'after_correctness_tests') for path in record[group]
                 if path in cleanup.typed_boundary.EDGES}
        self.assertEqual(len(paths), 21)
        for _ in range(2):
            with self.traced() as (counts, owners, reads):
                results.append(self.seed.verify(self.root))
            self.assertEqual(counts, {'full': 1, 'typed': 1, 'finish': 1})
            self.assertEqual(len(owners), 1)
            self.closed(owners[0], False)
            self.assertTrue(all(reads[path] >= 2 for path in paths))
            previous.append(owners[0])
        self.assertIsNot(previous[0], previous[1])
        self.assertEqual(results[0], results[1])
        self.assertEqual(results[0]['path'], self.seed.MODULE)
        self.assertEqual(results[0]['edges'][-1], self.seed.deviation.edge())

    def test_transient_consumed_bytes_remain_sticky_after_restore(self):
        target = self.root/'extensions/carla/curve_bounds.mojo'
        raw, fired = target.read_bytes(), []
        def callback(frame, event, value, owners):
            if (fired or event != 'return' or frame.f_code is not cleanup._InvariantInputs._admit.__code__
                    or not owners or owners[0]._state != 'active'):
                return
            fired.append(True)
            owner = owners[0]
            target.write_bytes(raw+b'\n# consumed temporary mutation\n')
            try:
                with self.assertRaisesRegex(ValueError, 'consumed operation bytes changed'):
                    cleanup._observe_bytes(self.root, target.relative_to(self.root).as_posix(),
                                           target.read_bytes(), _operation=owner)
            finally:
                target.write_bytes(raw)
            with self.assertRaises(ValueError):
                cleanup._operation_check(owner, self.root)
        with self.traced(callback) as (_, owners, _):
            with self.assertRaises(ValueError):
                self.seed.verify(self.root)
        self.assertEqual(fired, [True])
        self.assertEqual(target.read_bytes(), raw)
        self.assertEqual(len(owners), 1)
        self.closed(owners[0], True)

    def test_late_source_checker_and_census_fail_before_publication(self):
        for fault in ('source', 'checker', 'census'):
            target = self.root/'extensions/carla/curve_bounds.mojo'
            raw, fired, stop = target.read_bytes(), [], []
            extra = self.root/'tests/seed_late_source.mojo'
            self.assertFalse(extra.exists())
            def callback(frame, event, value, owners):
                if fired or event != 'call' or frame.f_code is not cleanup._InvariantInputs.finish.__code__:
                    return
                fired.append(True)
                self.assertEqual(len(owners), 1)
                self.assertEqual(owners[0]._state, 'active')
                if fault == 'source':
                    target.write_bytes(raw+b'\n# late source\n')
                elif fault == 'census':
                    extra.write_text('# late unrelated source\n')
                else:
                    checker = Path(cleanup.__file__).resolve()
                    read = Path.read_bytes
                    def changed(path, *args, **kwargs):
                        value = read(path, *args, **kwargs)
                        return value+b'\n# late executing checker read\n' if path.resolve() == checker else value
                    manager = patch.object(Path, 'read_bytes', changed)
                    manager.start()
                    stop.append(manager.stop)
            try:
                with self.subTest(fault=fault), self.traced(callback) as (_, owners, _):
                    with self.assertRaises(ValueError):
                        self.seed.verify(self.root)
                self.assertEqual(fired, [True])
                self.closed(owners[0], True)
            finally:
                for restore in reversed(stop):
                    restore()
                target.write_bytes(raw)
                extra.unlink(missing_ok=True)
            self.assertEqual(target.read_bytes(), raw)
            self.assertFalse(extra.exists())

    def test_nested_standalone_is_independent_and_outer_borrow_is_refused(self):
        target = self.root/'extensions/carla/curve_bounds.mojo'
        read = Path.read_bytes
        nested, blocked, result = [], [], []
        with self.traced() as (counts, owners, _):
            def bridge(path, *args, **kwargs):
                if path == target and owners and owners[0]._state == 'active' and not nested:
                    nested.append(True)
                    result.append(self.seed.verify(self.root))
                elif nested and len(owners) == 2 and not blocked:
                    blocked.append(True)
                    with self.assertRaisesRegex(ValueError, 'nearer independent operation blocks borrowing'):
                        cleanup._operation_check(owners[0], self.root)
                return read(path, *args, **kwargs)
            with patch.object(Path, 'read_bytes', bridge), self.assertRaises(ValueError):
                self.seed.verify(self.root)
        self.assertEqual(nested, [True])
        self.assertEqual(blocked, [True])
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['path'], self.seed.MODULE)
        self.assertEqual(len(owners), 2)
        self.assertIsNot(owners[0], owners[1])
        self.closed(owners[0], True)
        self.closed(owners[1], False)
        self.assertEqual(counts['full'], 2)
        self.assertEqual(counts['typed'], 2)


def check_generated_root_only_borrowing(root, stage, mojo, compiler, flags):
    """Explicit real-stage controls, called by the owned mutation-fixture adapter.

    This helper does not generate, copy, or rebind a stage. Its caller supplies
    the independently writable stage after complete producer admission.
    Source inputs remain read-only; only an independent staged file is changed.
    Existing unittest discovery and its method inventory are unchanged.
    """
    import os
    import coverage_loop_proofs as proofs
    from carla_lane_oracle import full_audit_cleanup_contracts as audit
    from carla_lane_oracle import seed_count_contracts as seed
    root, stage = Path(root).resolve(), Path(stage).resolve()
    sealed = Path(__file__).resolve().parents[2]
    audit.require(stage != sealed and not stage.is_relative_to(sealed),
                  'Root-only controls require an independent writable stage')
    expected = proofs.read_receipt(stage/'loop-proofs.json')['receipt']
    settings = {'mojo': [mojo], 'suites': expected['execution']['suites'],
                'capture_cache': proofs._expand_path(expected['execution']['cache'], root, stage)}
    helper_paths = ('extensions/carla/render_sky.mojo', 'extensions/carla/render_weather.mojo')
    labels = ('root-only-seed-and-shared-positive', 'root-only-wrong-nonempty-root',
              'root-only-stage-tamper-at-finish')
    completed, retained_owners = [], []
    for label in labels:
        audit.require(proofs.maintained_inputs(root, exclude=stage) == expected['root_inputs'],
                      'Root-only source fixture changed before control')
        proofs.check_capture_inputs({'receipt': expected}, root, stage)
        audit.require(sys.getprofile() is None, 'Root-only controls require an unprofiled thread')
        owners, fired, caught, restores = [], [], [], []
        def profile(frame, event, value):
            if event == 'return' and frame.f_code is audit._receipt_operation_enter.__code__:
                owners.append(value)
            if (fired or event != 'return'
                    or frame.f_code is not audit._InvariantInputs._receipt_bindings.__code__):
                return
            fired.append(True)
            audit.require(len(owners) == 1 and type(value) is dict and value,
                          'Root-only control missed the real receipt binding return')
            owner = owners[0]
            audit.require(owner._kind == 'generated_receipt' and owner._state == 'active'
                          and owner._owner_frame.f_code is proofs.build_receipt.__code__
                          and owner._owner_frame.f_locals.get('_operation') is owner,
                          'Root-only control requires its actual active build_receipt frame')
            include_context = owner._include_roots
            audit.require(include_context == (str(stage),), 'Generated stage context changed')
            if label == labels[0]:
                result = seed.verify(root, _operation=owner)
                audit.require(result['path'] == seed.MODULE
                              and result['before_sha256'] == seed.BEFORE_SHA256
                              and result['after_sha256'] == seed.deviation.AFTER_SHA256
                              and result['edges'][-1] == seed.deviation.edge(),
                              'Root-only seed borrow lost the exact current historical chain')
            helpers = audit.shared_helper_proof_bindings(
                root, paths=helper_paths, _operation=owner)
            audit.require(helpers and set(helper_paths) <= helpers.keys()
                          and any(path.startswith('render/') for path in helpers)
                          and owner._state == 'active' and not owner._failed
                          and owner._include_roots == include_context,
                          'Root-only shared-helper borrow changed the generated context')
            if label == labels[1]:
                try:
                    audit.shared_helper_proof_bindings(root, paths=helper_paths,
                        include_roots=(stage/'foreign',), _operation=owner)
                except ValueError as error:
                    audit.require('operation include root changed' in str(error),
                                  'Wrong include root did not reach the context comparison')
                    caught.append(True)
                else:
                    raise AssertionError('Wrong nonempty generated include root was accepted')
                audit.require(owner._include_roots == include_context and owner._failed,
                              'Caught wrong-root failure lost context or sticky refusal')
                try:
                    audit._operation_check(owner, root)
                except ValueError:
                    pass
                else:
                    raise AssertionError('Failed root-only owner was reusable')
            elif label == labels[2]:
                relative = 'extensions/animals/anatomy/render.mojo'
                target = stage/relative
                audit.require(target.is_file() and not target.is_symlink()
                              and target.stat().st_nlink == 1,
                              'Stage mutation requires an independent regular file')
                for original in (root/relative, sealed/relative):
                    if original.exists():
                        audit.require((target.stat().st_dev, target.stat().st_ino)
                                      != (original.stat().st_dev, original.stat().st_ino),
                                      'Stage mutation aliases a source inode')
                raw, mode = target.read_bytes(), target.stat().st_mode & 0o777
                def restore():
                    target.unlink()
                    with target.open('xb') as stream:
                        stream.write(raw)
                    os.chmod(target, mode)
                restores.append(restore)
                target.unlink()
                with target.open('xb') as stream:
                    stream.write(raw + b'\n# root-only borrow must retain final stage checks\n')
                os.chmod(target, mode)
        print('Root-only START '+label, flush=True)
        try:
            sys.setprofile(profile)
            try:
                actual = proofs.build_receipt(root, stage, compiler, flags, **settings)
            except ValueError as error:
                audit.require(label != labels[0] and fired == [True],
                              'Root-only control refused before its actual borrow')
                if label == labels[2]:
                    audit.require('consumed operation bytes changed: extensions/animals/anatomy/render.mojo' in str(error)
                                  or 'consumed operation text changed: extensions/animals/anatomy/render.mojo' in str(error)
                                  or 'render entry source changed: extensions/animals/anatomy/render.mojo' in str(error),
                                  'Stage tamper did not reach a generated-input refusal')
            else:
                audit.require(label == labels[0]
                              and proofs.canonical(actual) == proofs.canonical(expected),
                              'Root-only negative escaped or positive receipt changed')
            finally:
                sys.setprofile(None)
            audit.require(fired == [True] and len(owners) == 1
                          and owners[0]._state == 'closed'
                          and owners[0]._failed == (label != labels[0])
                          and owners[0]._owner_frame is None
                          and owners[0]._receipt_seed is None,
                          'Root-only receipt did not close with the expected outcome')
            audit.require(caught == ([True] if label == labels[1] else []),
                          'Root-only caught-refusal observation changed')
            retained_owners.append(owners[0])
        finally:
            for restore in reversed(restores):
                restore()
        proofs.check_capture_inputs({'receipt': expected}, root, stage)
        completed.append(label)
        print('Root-only DONE '+label, flush=True)
    audit.require(len({id(owner) for owner in retained_owners}) == len(labels),
                  'Root-only controls reused an owner across receipts')
    audit.require(completed == list(labels), 'Root-only control census changed')
    return {'completed': completed, 'fresh_receipts': len(labels)}


if __name__ == '__main__':
    unittest.main()
