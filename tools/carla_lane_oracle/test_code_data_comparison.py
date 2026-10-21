# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Independent exact code-data comparison and mutation controls."""
from pathlib import Path
import gc
import struct
import sys
import types
import unittest
import weakref
from unittest.mock import patch

import full_audit_cleanup_contracts as owner


def reference_constant(value):
    """Build the original typed value image without the optimized helpers."""
    kind = type(value)
    if kind is types.CodeType:
        return ('code', reference_code(value))
    if kind is tuple:
        return ('tuple', tuple(reference_constant(item) for item in value))
    if kind is frozenset:
        return ('frozenset', frozenset(reference_constant(item) for item in value))
    if kind is float:
        return ('float', struct.pack('>d', value))
    if kind is complex:
        return ('complex', struct.pack('>dd', value.real, value.imag))
    if value is Ellipsis:
        return ('ellipsis',)
    if kind is slice:
        return ('slice', reference_constant(value.start), reference_constant(value.stop),
                reference_constant(value.step))
    if kind not in (str, bytes, int, bool, type(None)):
        raise ValueError('unsupported constant')
    return (kind.__name__, value)


def reference_code(code):
    """Enumerate every public non-callable code field except the file path."""
    if type(code) is not types.CodeType:
        raise ValueError('missing code')
    return tuple((name, reference_constant(getattr(code, name)))
                 for name in sorted(dir(code))
                 if name.startswith('co_') and name != 'co_filename'
                 and not callable(getattr(code, name)))


def float_bits(bits):
    return struct.unpack('>d', bits.to_bytes(8, 'big'))[0]


def sample_code():
    source = '''def outer(first, /, second=1, *, keyword=None):
    captured = first
    def inner(value):
        try:
            return captured + value + second
        except TypeError:
            return keyword
    return inner
'''
    module = compile(source, 'original.py', 'exec', dont_inherit=True)
    return next(value for value in module.co_consts if type(value) is types.CodeType)


class CodeDataComparisonControls(unittest.TestCase):
    def assert_code_equal(self, left, right, expected):
        self.assertIs(reference_code(left) == reference_code(right), expected)
        self.assertIs(owner._code_identity(left) == owner._code_identity(right), expected)
        self.assertIs(owner._code_equal(left, right), expected)
        self.assertIs(owner._code_equal(right, left), expected)

    def constant_equal(self, left, right):
        code = sample_code()
        return owner._code_equal(code.replace(co_consts=(left,)),
                                 code.replace(co_consts=(right,)))

    def test_current_compiled_functions_match_independent_images(self):
        count = 0
        for filename, captured in owner._IMPORT_CODE.items():
            compiled = owner._compiled_functions(Path(filename).read_bytes(), filename)
            self.assertEqual(set(compiled), set(captured))
            for name, code in captured.items():
                with self.subTest(filename=filename, name=name):
                    self.assert_code_equal(code, compiled[name], True)
                    count += 1
        self.assertGreater(count, 300)

    def test_public_code_field_mutations_are_refused(self):
        code = sample_code()
        changes = {
            'co_argcount': {'co_argcount': code.co_argcount - 1},
            'co_posonlyargcount': {'co_posonlyargcount': 0},
            'co_kwonlyargcount': {'co_kwonlyargcount': 0},
            'co_nlocals': {'co_nlocals': code.co_nlocals + 1,
                           'co_varnames': code.co_varnames + ('extra_local',)},
            'co_stacksize': {'co_stacksize': code.co_stacksize + 1},
            'co_flags': {'co_flags': code.co_flags ^ 0x1000000},
            'co_code': {'co_code': code.co_code + b'\x09\x00'},
            'co_consts': {'co_consts': code.co_consts + (7919,)},
            'co_names': {'co_names': code.co_names + ('extra_name',)},
            'co_varnames': {'co_varnames': ('renamed',) + code.co_varnames[1:]},
            'co_filename': {'co_filename': 'relocated.py'},
            'co_name': {'co_name': code.co_name + '_changed'},
            'co_qualname': {'co_qualname': code.co_qualname + '_changed'},
            'co_firstlineno': {'co_firstlineno': code.co_firstlineno + 1},
            'co_linetable': {'co_linetable': b''},
            'co_exceptiontable': {'co_exceptiontable': code.co_exceptiontable + b'\x00'},
            'co_freevars': {'co_freevars': code.co_freevars + ('extra_free',)},
            'co_cellvars': {'co_cellvars': code.co_cellvars + ('extra_cell',)},
        }
        changed_fields = set()
        for field, replacement in changes.items():
            with self.subTest(field=field):
                changed = code.replace(**replacement)
                self.assert_code_equal(code, changed, field == 'co_filename')
                changed_fields.update(name for name in dir(code)
                                      if name.startswith('co_')
                                      and not callable(getattr(code, name))
                                      and getattr(code, name) != getattr(changed, name))
        data_fields = {name for name in dir(code) if name.startswith('co_')
                       and not callable(getattr(code, name))}
        self.assertEqual(changed_fields, data_fields)

    def test_nested_code_changes_and_relocation(self):
        code = sample_code()
        index = next(i for i, value in enumerate(code.co_consts)
                     if type(value) is types.CodeType)
        nested = code.co_consts[index]
        for field, value in (('co_filename', 'nested-relocated.py'),
                             ('co_consts', nested.co_consts + ('changed',)),
                             ('co_exceptiontable', b''),
                             ('co_firstlineno', nested.co_firstlineno + 1)):
            constants = list(code.co_consts)
            constants[index] = nested.replace(**{field: value})
            with self.subTest(field=field):
                self.assert_code_equal(code, code.replace(co_consts=tuple(constants)),
                                       field == 'co_filename')

    def test_supported_constants_match_independent_images(self):
        nan = float_bits(0x7ff8000000000001)
        values = (None, Ellipsis, False, True, 0, 1, -1, 2**100,
                  '', 'x', b'', b'x', 0.0, -0.0, 1.0, -1.0,
                  float('inf'), float('-inf'), nan,
                  float_bits(0x7ff8000000000002), float_bits(0xfff8000000000001),
                  complex(0.0, 0.0), complex(-0.0, 0.0), complex(0.0, -0.0),
                  complex(nan, 0.0), complex(0.0, nan), complex(1, 2),
                  (), (0,), (False,), (0.0,), (-0.0,), (nan,), ((1,), 'x'),
                  frozenset(), frozenset((0,)), frozenset((False,)),
                  frozenset((0.0,)), frozenset((-0.0,)), frozenset((nan,)),
                  frozenset((1, 'x', (2,))), slice(None), slice(0),
                  slice(False), slice(-0.0, nan, 1), sample_code())
        for i, left in enumerate(values):
            for j, right in enumerate(values):
                with self.subTest(left=i, right=j):
                    expected = reference_constant(left) == reference_constant(right)
                    self.assertIs(self.constant_equal(left, right), expected)

    def test_signed_zero_nan_payloads_and_typed_sets_remain_distinct(self):
        nan = float_bits(0x7ff8000000000001)
        nan_same = float_bits(0x7ff8000000000001)
        nan_other = float_bits(0x7ff8000000000002)
        equal_pairs = ((nan, nan_same), ((nan,), (nan_same,)),
                       (complex(nan, -0.0), complex(nan_same, -0.0)))
        unequal_pairs = ((0, False), (1, True), (1, 1.0), (0.0, -0.0),
                         (nan, nan_other), (complex(0.0, 0.0), complex(-0.0, 0.0)),
                         (complex(0.0, 0.0), complex(0.0, -0.0)),
                         (frozenset((0,)), frozenset((False,))),
                         (frozenset((0.0,)), frozenset((-0.0,))),
                         (slice(0.0), slice(-0.0)))
        code = sample_code()
        for pairs, expected in ((equal_pairs, True), (unequal_pairs, False)):
            for left, right in pairs:
                self.assertIs(self.constant_equal(left, right), expected)
                self.assert_code_equal(code.replace(co_consts=(left,)),
                                       code.replace(co_consts=(right,)), expected)
        duplicate_nans = frozenset((nan, nan_same))
        self.assertEqual(len(duplicate_nans), 2)
        self.assertIs(self.constant_equal(duplicate_nans, frozenset((nan,))), True)

    def test_unsupported_constants_are_rejected_after_earlier_mismatches(self):
        class IntSubclass(int):
            pass
        code = sample_code()
        subclasses = tuple(type('Unsupported', (kind,), {})(value) for kind, value in
                           ((str, 'x'), (float, 1), (complex, 1),
                            (tuple, (1,)), (frozenset, (1,))))
        for unsupported in (object(), [], {}, {1}, bytearray(b'x'), IntSubclass(1),
                            *subclasses):
            for left, right in (((0, unsupported), (1, None)),
                                ((0, None), (1, unsupported)),
                                ((0, unsupported), (1,)),
                                ((0,), (1, unsupported)),
                                (unsupported, None), (None, unsupported),
                                (slice(unsupported), slice(None))):
                with self.subTest(kind=type(unsupported).__name__):
                    with self.assertRaisesRegex(ValueError, 'unsupported'):
                        reference_constant(left) == reference_constant(right)
                    with self.assertRaisesRegex(owner.ContractError, 'unsupported'):
                        self.constant_equal(left, right)
                    with self.assertRaisesRegex(owner.ContractError, 'unsupported'):
                        owner._code_equal(code.replace(co_argcount=1, co_consts=(left,)),
                                          code.replace(co_consts=(right,)))
        invalid_set = frozenset((IntSubclass(1),))
        with self.assertRaisesRegex(owner.ContractError, 'unsupported'):
            self.constant_equal(invalid_set, frozenset())

    def test_invalid_code_witnesses_keep_the_original_rejection(self):
        code = sample_code()
        bad_constant = code.replace(co_consts=(object(),))
        for left, right in ((None, code), (code, None), (object(), code),
                            (bad_constant, None), (None, bad_constant)):
            with self.subTest(left=type(left).__name__, right=type(right).__name__):
                with self.assertRaises(owner.ContractError) as original:
                    owner._code_identity(left) == owner._code_identity(right)
                with self.assertRaises(owner.ContractError) as pairwise:
                    owner._code_equal(left, right)
                self.assertEqual(str(original.exception), str(pairwise.exception))

    def test_comparator_substitutions_cannot_validate_themselves(self):
        original = owner._code_equal
        always_equal = lambda left, right: True
        same_globals = types.FunctionType(always_equal.__code__, vars(owner))
        foreign_globals = types.FunctionType(original.__code__, dict(vars(owner)))
        constants = list(original.__code__.co_consts)
        nested_index = next(i for i, value in enumerate(constants)
                            if type(value) is types.CodeType)
        nested = constants[nested_index]
        constants[nested_index] = nested.replace(co_consts=nested.co_consts + ('changed',))
        nested_change = original.__code__.replace(co_consts=tuple(constants))
        for changed in (always_equal, same_globals, foreign_globals, object()):
            with self.subTest(kind=type(changed).__name__), patch.object(
                    owner, '_code_equal', changed), self.assertRaisesRegex(
                    owner.ContractError, 'executing code comparison helper changed'):
                owner.executing_checker_bindings()
        for name, changed in (('__code__', always_equal.__code__),
                              ('__code__', nested_change),
                              ('__defaults__', (None,)), ('__kwdefaults__', {})):
            previous = getattr(original, name)
            try:
                setattr(original, name, changed)
                with self.subTest(attribute=name), self.assertRaisesRegex(
                        owner.ContractError, 'executing code comparison helper changed'):
                    owner.executing_checker_bindings()
            finally:
                setattr(original, name, previous)
        self.assertIs(owner._code_equal, original)
        self.assertEqual(owner.executing_checker_bindings()[owner.CHECKER_PATHS[0]],
                         owner.sha(Path(owner.__file__).read_bytes()))

    def test_comparator_code_drift_after_guard_is_refused(self):
        original = owner._code_equal
        original_code = original.__code__
        changed_code = (lambda left, right: True).__code__
        physical_read = Path.read_bytes
        owner_path = Path(owner.__file__).resolve()
        changed = []

        def change_after_read(path):
            raw = physical_read(path)
            if path == owner_path and not changed:
                original.__code__ = changed_code
                changed.append(path)
            return raw

        try:
            with patch.object(Path, 'read_bytes', change_after_read):
                with self.assertRaisesRegex(owner.ContractError,
                        'executing function changed: .*:_code_equal'):
                    owner.executing_checker_bindings()
            self.assertEqual(changed, [owner_path])
        finally:
            original.__code__ = original_code
        self.assertIs(owner._code_equal, original)
        self.assertEqual(owner.executing_checker_bindings()[owner.CHECKER_PATHS[0]],
                         owner.sha(owner_path.read_bytes()))

    def test_recursive_helper_lifetime_does_not_require_cyclic_gc(self):
        references = []
        comparator_code = owner._code_equal.__code__
        code = sample_code()
        invalid = code.replace(co_consts=(object(),))

        def observe(frame, event, argument):
            if (event == 'call' and frame.f_code.co_name == 'code_equal'
                    and frame.f_back.f_code is comparator_code):
                local = frame.f_back.f_locals
                references.extend(weakref.ref(local[name])
                                  for name in ('constant_equal', 'code_equal'))

        previous_profile = sys.getprofile()
        collection_enabled = gc.isenabled()
        try:
            gc.disable()
            sys.setprofile(observe)
            self.assertTrue(owner._code_equal(code, code))
            self.assertFalse(owner._code_equal(code, code.replace(co_name='changed')))
            for left, right in ((invalid, code), (code, invalid)):
                with self.assertRaises(owner.ContractError):
                    owner._code_equal(left, right)
            sys.setprofile(previous_profile)
            self.assertEqual(len(references), 8)
            self.assertTrue(all(reference() is None for reference in references))
        finally:
            sys.setprofile(previous_profile)
            if collection_enabled:
                gc.enable()


if __name__ == '__main__':
    unittest.main()
