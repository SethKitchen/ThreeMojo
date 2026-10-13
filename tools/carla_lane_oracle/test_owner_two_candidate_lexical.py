# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""The literal two-candidate expansion preserves the v10 classifier protocol."""
import ast
import builtins
import hashlib
from pathlib import Path
import types
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as cleanup
import test_owner_frame_lexical as fixtures

def _baseline_operation_frame_kind(frame, *, include_aliases=False):
    if frame is None:
        return None
    namespace = frame.f_globals
    filename = namespace.get('__file__')
    if type(filename) is str and filename.startswith('/') and (type(__file__) is str) and __file__.startswith('/'):
        candidates = (namespace.get('verify'), namespace.get('reviewed_nonempty_loops'))
        if all((value is None or (type(value) is types.FunctionType and '__wrapped__' not in value.__dict__ and (frame.f_code is not value.__code__)) for value in candidates)):
            return None
        if type(namespace) is dict:
            for value in candidates:
                if value is None:
                    continue
                if type(value) is not types.FunctionType or type(value.__dict__) is not dict:
                    break
                if '__wrapped__' in value.__dict__:
                    value = value.__dict__['__wrapped__']
                    if type(value) is not types.FunctionType or type(value.__dict__) is not dict or '__wrapped__' in value.__dict__:
                        break
                if frame.f_code is value.__code__:
                    break
            else:
                if type(sys.modules) is dict and (__package__ is None or type(__package__) is str):
                    prefix = __package__ + '.' if __package__ else ''
                    for name, attribute in ((prefix + 'coverage_invariant_contracts', 'verify'), (prefix + 'winner_sign_contracts', 'verify'), (prefix + 'border_parser_contracts', 'verify'), ('coverage_loop_proofs', 'reviewed_nonempty_loops'), ('tools.coverage_loop_proofs', 'reviewed_nonempty_loops')):
                        module = sys.modules.get(name)
                        if module is not None and (type(module) is not types.ModuleType or (namespace is vars(module) and attribute not in vars(module) and ('__getattr__' in vars(module)))):
                            break
                    else:
                        return None
    for kind in ('invariant', 'winner', 'border'):
        module = _owner_module(kind)
        if module is not None and namespace is vars(module) and (frame.f_code is _live_function_code(getattr(module, 'verify', None))):
            return kind
    for name in ('coverage_loop_proofs', 'tools.coverage_loop_proofs'):
        module = sys.modules.get(name)
        if module is not None and namespace is vars(module) and (frame.f_code is _live_function_code(getattr(module, 'reviewed_nonempty_loops', None))):
            return {'extensions/carla/map': 'map_loops', 'extensions/carla/rtree': 'rtree_loops'}.get(frame.f_locals.get('module'), 'other_loops')
    if not include_aliases or type(filename) is not str:
        return None
    if _different_alias_leaf(filename, ('coverage_invariant_contracts.py', 'winner_sign_contracts.py', 'border_parser_contracts.py', 'coverage_loop_proofs.py')):
        return None
    for kind, name in (('invariant', 'coverage_invariant_contracts.py'), ('winner', 'winner_sign_contracts.py'), ('border', 'border_parser_contracts.py')):
        if Path(filename).absolute() == Path(__file__).absolute().with_name(name) and frame.f_code is _live_function_code(namespace.get('verify')):
            return 'alias_' + kind
    if Path(filename).absolute() == Path(__file__).absolute().parent.parent / 'coverage_loop_proofs.py' and frame.f_code is _live_function_code(namespace.get('reviewed_nonempty_loops')):
        return 'alias_loops'
    return None

REFERENCE = fixtures.typed_reference(_baseline_operation_frame_kind, 'operation', 'registry')
REFERENCE_AST = '7fb32652f190b1f87b8e794aa549193d808d048f5ebc1a5656b6eaf80e96f611'


class TwoCandidateOwnerTests(unittest.TestCase):
    def test_frozen_v10_reference_ast(self):
        tree = ast.parse(Path(__file__).read_text())
        node = next(n for n in tree.body if isinstance(n, ast.FunctionDef)
                    and n.name == '_baseline_operation_frame_kind')
        node.name = '_operation_frame_kind'
        self.assertEqual(hashlib.sha256(ast.dump(node, include_attributes=False).encode()).hexdigest(),
                         REFERENCE_AST)

    def compare(self, make, *, all_hook=None):
        outcomes = []
        for function in (REFERENCE, cleanup._operation_frame_kind):
            events = []
            frame = make(events)
            with fixtures.OwnerFrameLexicalTests().registered(), patch.dict(vars(cleanup)):
                if all_hook is not None:
                    cleanup.all = all_hook(events)
                try:
                    result = ('return', function(frame, include_aliases=True))
                except Exception as error:
                    result = ('raise', type(error), error.args)
            outcomes.append((result, events))
        self.assertEqual(*outcomes)
        return outcomes[0]

    def test_two_predicates_and_upfront_namespace_lookup_order(self):
        for first in (None, 'plain', 'matching', 'wrapped', 'exotic'):
            for second in (None, 'plain', 'matching', 'wrapped', 'exotic'):
                with self.subTest(first=first, second=second):
                    def make(events):
                        code = compile('pass', '<owner>', 'exec')
                        def candidate(kind):
                            if kind is None: return None
                            if kind == 'exotic': return object()
                            value = fixtures.OwnerFrameLexicalTests.function()
                            if kind == 'matching': value.__code__ = code
                            if kind == 'wrapped': value.__wrapped__ = fixtures.OwnerFrameLexicalTests.function()
                            return value
                        class Namespace(dict):
                            def get(self, key, default=None):
                                events.append(('get', key))
                                return super().get(key, default)
                        return fixtures.OwnerFrameLexicalTests.frame(Namespace(__file__=cleanup.__file__,
                            verify=candidate(first), reviewed_nonempty_loops=candidate(second)), code)
                    self.compare(make)

    def test_metadata_membership_and_frame_code_access_order(self):
        for first_wrapped in (False, True):
            for fail_second in (False, True):
                with self.subTest(first_wrapped=first_wrapped, fail_second=fail_second):
                    def make(events):
                        class Metadata(dict):
                            def __init__(self, label): super().__init__(); self.label = label
                            def __contains__(self, key):
                                events.append(('contains', self.label, key))
                                if self.label == 'second' and fail_second: raise ValueError('second metadata')
                                return first_wrapped if self.label == 'first' else False
                        first, second = fixtures.OwnerFrameLexicalTests.function(), fixtures.OwnerFrameLexicalTests.function()
                        first.__dict__, second.__dict__ = Metadata('first'), Metadata('second')
                        class Frame:
                            f_globals = {'__file__': cleanup.__file__, 'verify': first,
                                         'reviewed_nonempty_loops': second}
                            f_locals = {}
                            @property
                            def f_code(self):
                                events.append(('code',))
                                return compile('pass', '<unrelated>', 'exec')
                        return Frame()
                    self.compare(make)

    def test_injected_all_preserves_generator_and_short_circuit_protocol(self):
        for behavior in ('normal', 'first', 'raise', 'false'):
            with self.subTest(behavior=behavior):
                def make(events):
                    return fixtures.OwnerFrameLexicalTests.frame({'__file__': cleanup.__file__,
                        'verify': None, 'reviewed_nonempty_loops': None}, compile('pass', '<f>', 'exec'))
                def hook(events):
                    def consume(values):
                        events.append(('all', type(values)))
                        if behavior == 'raise': raise ValueError('injected all')
                        if behavior == 'false': return False
                        if behavior == 'first': return next(values)
                        return builtins.all(values)
                    return consume
                self.compare(make, all_hook=hook)

    def test_builtin_replacement_and_unavailable_original_use_fallback(self):
        frame = fixtures.OwnerFrameLexicalTests.frame({'__file__': cleanup.__file__, 'verify': None,
                                'reviewed_nonempty_loops': None}, compile('pass', '<f>', 'exec'))
        calls = []
        original = builtins.all
        def observed(values): calls.append(type(values)); return original(values)
        with fixtures.OwnerFrameLexicalTests().registered(), patch.object(builtins, 'all', observed):
            self.assertEqual(REFERENCE(frame, include_aliases=True),
                             cleanup._operation_frame_kind(frame, include_aliases=True))
        self.assertEqual(calls, [types.GeneratorType, types.GeneratorType])
        with patch.object(cleanup, '_BUILTIN_ALL', None):
            self.assertIsNone(cleanup._operation_frame_kind(frame, include_aliases=True))


if __name__ == '__main__':
    unittest.main()
