# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Finite differential controls preserve v7 owner-classification boundaries."""
from contextlib import ExitStack
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as cleanup


def _baseline_operation_frame_kind(frame, *, include_aliases=False):
    if frame is None:
        return None
    namespace = frame.f_globals
    filename = namespace.get('__file__')
    if type(filename) is str and filename.startswith('/') and (type(__file__) is str) and __file__.startswith('/'):
        candidates = (namespace.get('verify'), namespace.get('reviewed_nonempty_loops'))
        if all((value is None or (type(value) is types.FunctionType and '__wrapped__' not in value.__dict__ and (frame.f_code is not value.__code__)) for value in candidates)):
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


def _baseline_cache_verify_frame(frame, *, include_aliases=False):
    """Recognize supported owners; aliases may only block outer borrowing."""
    name = __package__ + '.cache_key_contracts' if __package__ else 'cache_key_contracts'
    cache = sys.modules.get(name)
    if frame is not None and cache is not None and (frame.f_globals is vars(cache)) and (frame.f_code is _live_function_code(cache.verify)):
        return True
    main = sys.modules.get('__main__')
    if frame is not None and main is not None and (frame.f_globals is vars(main)) and (type(getattr(main, '__file__', None)) is str) and (Path(main.__file__).absolute() == Path(__file__).absolute().with_name('cache_key_contracts.py')) and (frame.f_code is _live_function_code(getattr(main, 'verify', None))):
        return True
    namespace = frame.f_globals if frame is not None else {}
    if include_aliases is True and _different_alias_leaf(namespace.get('__file__'), ('cache_key_contracts.py',)):
        return False
    return include_aliases and type(namespace.get('__file__')) is str and (Path(namespace['__file__']).absolute() == Path(__file__).absolute().with_name('cache_key_contracts.py')) and (frame.f_code is _live_function_code(namespace.get('verify')))


REFERENCE_OPERATION = types.FunctionType(_baseline_operation_frame_kind.__code__, vars(cleanup))
REFERENCE_CACHE = types.FunctionType(_baseline_cache_verify_frame.__code__, vars(cleanup))
PREFIX = (cleanup.__package__ + '.') if cleanup.__package__ else ''
REGISTRATIONS = (PREFIX + 'coverage_invariant_contracts', PREFIX + 'winner_sign_contracts',
                 PREFIX + 'border_parser_contracts', 'coverage_loop_proofs',
                 'tools.coverage_loop_proofs', PREFIX + 'cache_key_contracts')


class OwnerFrameLexicalTests(unittest.TestCase):
    @staticmethod
    def function():
        def verify(): pass
        return verify

    @classmethod
    def wrapped(cls, depth=1):
        inner = cls.function()
        value = inner
        for _ in range(depth):
            outer = cls.function()
            outer.__wrapped__ = value
            value = outer
        return value, inner

    @staticmethod
    def frame(namespace, code, local=None, parent=None):
        return types.SimpleNamespace(f_globals=namespace, f_code=code,
                                     f_locals={} if local is None else local, f_back=parent)

    @staticmethod
    def outcome(function, frame, aliases):
        try:
            return ('return', function(frame, include_aliases=aliases))
        except Exception as error:
            return ('raise', type(error), error.args)

    def equivalent(self, frame, *, cache=False, expected=None):
        actual = cleanup._cache_verify_frame if cache else cleanup._operation_frame_kind
        reference = REFERENCE_CACHE if cache else REFERENCE_OPERATION
        for aliases in (False, True):
            old = self.outcome(reference, frame, aliases)
            new = self.outcome(actual, frame, aliases)
            self.assertEqual(new, old)
            if expected is not None: self.assertEqual(new, ('return', expected))

    def registered(self):
        return patch.dict(sys.modules, {name: None for name in REGISTRATIONS})

    def module(self, name, public, filename=None):
        module = types.ModuleType(name)
        module.__file__ = str(Path(cleanup.__file__).with_name(name.rsplit('.', 1)[-1]+'.py')) if filename is None else filename
        module.verify = public
        return module

    def test_canonical_decorated_owners_and_unrelated_namespace_frames(self):
        with self.registered():
            for kind, name in zip(('invariant', 'winner', 'border'), REGISTRATIONS[:3]):
                for depth in (0, 1, 2):
                    with self.subTest(kind=kind, depth=depth):
                        public, inner = self.wrapped(depth)
                        module = self.module(name, public)
                        with patch.dict(sys.modules, {name: module}):
                            self.equivalent(self.frame(vars(module), inner.__code__), expected=kind)
                            self.equivalent(self.frame(vars(module), compile('pass', '<unrelated>', 'exec')), expected=None)

    def test_wrapped_negative_branch_reduces_only_pure_owner_lookup(self):
        public, inner = self.wrapped()
        module = self.module(REGISTRATIONS[1], public)
        frame = self.frame(vars(module), compile('pass', '<unrelated>', 'exec'))
        original = cleanup._owner_module
        calls = []
        def owner(kind):
            calls.append(kind)
            return original(kind)
        with self.registered(), patch.dict(sys.modules, {REGISTRATIONS[1]: module}), \
                patch.object(cleanup, '_owner_module', owner):
            self.assertIsNone(REFERENCE_OPERATION(frame, include_aliases=True))
            self.assertTrue(calls)
            calls.clear()
            self.assertIsNone(cleanup._operation_frame_kind(frame, include_aliases=True))
            self.assertEqual(calls, [])
            self.equivalent(self.frame(vars(module), inner.__code__), expected='winner')

    def test_aliases_and_relative_or_exotic_filenames_retain_fallback(self):
        public, inner = self.wrapped()
        with self.registered():
            for name in ('coverage_invariant_contracts.py', 'winner_sign_contracts.py',
                         'border_parser_contracts.py', 'unrelated.py'):
                for filename in (str(Path(cleanup.__file__).with_name(name)), name, None):
                    with self.subTest(filename=filename):
                        namespace = {'__file__': filename, 'verify': public}
                        self.equivalent(self.frame(namespace, inner.__code__))
                        self.equivalent(self.frame(namespace, compile('pass', '<unrelated>', 'exec')))
            class Name(str): pass
            namespace = {'__file__': Name(cleanup.__file__), 'verify': public}
            self.equivalent(self.frame(namespace, inner.__code__))

    def test_loop_owner_classification_and_canonical_precedence(self):
        public, inner = self.wrapped()
        with self.registered():
            module = self.module('coverage_loop_proofs', public)
            module.reviewed_nonempty_loops = public
            with patch.dict(sys.modules, {'coverage_loop_proofs': module}):
                for name, expected in (('extensions/carla/map', 'map_loops'),
                                       ('extensions/carla/rtree', 'rtree_loops'), ('other', 'other_loops')):
                    self.equivalent(self.frame(vars(module), inner.__code__, {'module': name}), expected=expected)
            with patch.dict(sys.modules, {REGISTRATIONS[0]: module, REGISTRATIONS[1]: module}):
                self.equivalent(self.frame(vars(module), inner.__code__), expected='invariant')

    def test_deeper_cyclic_and_exotic_wrappers_match_reference(self):
        class Wrapper:
            @property
            def __wrapped__(self): raise ValueError('wrapper lookup')
        for value in (Wrapper(), object(), 7):
            with self.subTest(value=type(value)), self.registered():
                module = self.module(REGISTRATIONS[1], value)
                with patch.dict(sys.modules, {REGISTRATIONS[1]: module}):
                    self.equivalent(self.frame(vars(module), self.function().__code__))
        public, _ = self.wrapped()
        public.__wrapped__ = public
        with self.registered():
            module = self.module(REGISTRATIONS[1], public)
            with patch.dict(sys.modules, {REGISTRATIONS[1]: module}):
                self.equivalent(self.frame(vars(module), self.function().__code__))

    def test_exotic_registry_module_namespace_and_lazy_exports_match_reference(self):
        public, _ = self.wrapped()
        namespace = {'__file__': str(Path(cleanup.__file__).with_name('winner_sign_contracts.py')),
                     'verify': public}
        frame = self.frame(namespace, compile('pass', '<unrelated>', 'exec'))
        with self.registered(), patch.dict(sys.modules, {REGISTRATIONS[0]: object()}):
            self.equivalent(frame)
        class Registry(dict): pass
        with self.registered(), patch.object(sys, 'modules', Registry(sys.modules)):
            self.equivalent(frame)
        class Namespace(dict): pass
        with self.registered():
            self.equivalent(self.frame(Namespace(namespace), frame.f_code))
        class Package(str): pass
        with self.registered(), patch.object(cleanup, '__package__', Package(cleanup.__package__ or '')):
            self.equivalent(frame)
        # The loop module can expose a missing reviewed function lazily while
        # its unrelated decorated verify defeats v7's original negative guard.
        with self.registered():
            module = self.module('coverage_loop_proofs', public)
            def missing(name): raise ValueError('lazy export ' + name)
            module.__getattr__ = missing
            with patch.dict(sys.modules, {'coverage_loop_proofs': module}):
                self.equivalent(self.frame(vars(module), frame.f_code))

    def test_function_dictionary_subclass_preserves_protocol_order(self):
        events = []
        class Metadata(dict):
            def __contains__(self, key):
                events.append(('contains', key))
                return super().__contains__(key)
            def __getitem__(self, key):
                events.append(('getitem', key))
                raise ValueError('metadata indexed')
        public, _ = self.wrapped()
        public.__dict__ = Metadata(public.__dict__)
        module = self.module(REGISTRATIONS[1], public)
        frame = self.frame(vars(module), compile('pass', '<unrelated>', 'exec'))
        with self.registered(), patch.dict(sys.modules, {REGISTRATIONS[1]: module}):
            for aliases in (False, True):
                events.clear()
                expected = self.outcome(REFERENCE_OPERATION, frame, aliases), list(events)
                events.clear()
                actual = self.outcome(cleanup._operation_frame_kind, frame, aliases), list(events)
                self.assertEqual(actual, expected)

    def test_cache_canonical_main_alias_and_wrong_main_leaf_match_reference(self):
        public, inner = self.wrapped()
        with self.registered():
            module = self.module(REGISTRATIONS[-1], public)
            with patch.dict(sys.modules, {REGISTRATIONS[-1]: module}):
                self.equivalent(self.frame(vars(module), inner.__code__), cache=True, expected=True)
            for filename in (str(Path(cleanup.__file__).with_name('cache_key_contracts.py')),
                             str(Path(cleanup.__file__).with_name('unrelated.py')),
                             'cache_key_contracts.py', None):
                module = self.module('__main__', public, filename)
                module.__file__ = filename
                with self.subTest(filename=filename), patch.dict(sys.modules, {'__main__': module}):
                    self.equivalent(self.frame(vars(module), inner.__code__), cache=True)
            namespace = {'__file__': str(Path(cleanup.__file__).with_name('cache_key_contracts.py')),
                         'verify': public}
            self.equivalent(self.frame(namespace, inner.__code__), cache=True)

    def test_cache_main_file_lookup_count_and_alternating_values_match(self):
        public, inner = self.wrapped()
        expected_path = str(Path(cleanup.__file__).with_name('cache_key_contracts.py'))
        other_path = str(Path(cleanup.__file__).with_name('unrelated.py'))
        class Main(types.ModuleType):
            def __getattribute__(self, name):
                if name == '__file__':
                    values = types.ModuleType.__getattribute__(self, 'values')
                    events = types.ModuleType.__getattribute__(self, 'events')
                    events.append(name)
                    value = values.pop(0)
                    if isinstance(value, Exception): raise value
                    return value
                return types.ModuleType.__getattribute__(self, name)
        for second in (expected_path, other_path, None, ValueError('second lookup')):
            with self.subTest(second=second), self.registered():
                module = Main('__main__')
                module.verify = public
                module.__file__ = expected_path
                frame = self.frame(vars(module), inner.__code__)
                with patch.dict(sys.modules, {'__main__': module}):
                    for aliases in (False, True):
                        module.values, module.events = [expected_path, second, RuntimeError('extra lookup')], []
                        expected = self.outcome(REFERENCE_CACHE, frame, aliases), list(module.events)
                        module.values, module.events = [expected_path, second, RuntimeError('extra lookup')], []
                        actual = self.outcome(cleanup._cache_verify_frame, frame, aliases), list(module.events)
                        self.assertEqual(actual, expected)

    def test_nearer_independent_owner_remains_first_in_stack(self):
        with self.registered():
            winner, winner_inner = self.wrapped()
            border, border_inner = self.wrapped()
            modules = {REGISTRATIONS[1]: self.module(REGISTRATIONS[1], winner),
                       REGISTRATIONS[2]: self.module(REGISTRATIONS[2], border)}
            with patch.dict(sys.modules, modules):
                outer = self.frame(vars(modules[REGISTRATIONS[1]]), winner_inner.__code__)
                nearer = self.frame(vars(modules[REGISTRATIONS[2]]), border_inner.__code__, parent=outer)
                current = self.frame(vars(modules[REGISTRATIONS[2]]), compile('pass', '<unrelated>', 'exec'), parent=nearer)
                for classifier in (REFERENCE_OPERATION, cleanup._operation_frame_kind):
                    frame = current
                    while frame is not None:
                        found = classifier(frame, include_aliases=True)
                        if found is not None: break
                        frame = frame.f_back
                    self.assertIs(frame, nearer)
                    self.assertEqual(found, 'border')


if __name__ == '__main__':
    unittest.main()
