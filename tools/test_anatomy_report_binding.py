# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the saved anatomy report's source binding without a native probe."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import anatomy_validity as av


def check_binding(root):
    """Reject a missing or stale report; this does not validate its measurements."""
    report = json.loads((root/'docs/validation/anatomy-template-report.json').read_text())
    digest, hashes, _ = av.source_snapshot(root)
    expected = {
        'source_sha256': digest,
        'report_logic_sha256': hashes['tools/anatomy_validity.py'],
        'inventory_sha256': hashes['docs/validation/anatomy-provenance.json'],
    }
    actual = dict(report)
    actual['source_sha256'] = report['build_provenance']['source_sha256']
    for key, value in expected.items():
        if actual.get(key) != value:
            raise ValueError(f'anatomy report has stale {key}; regenerate on Linux '
                             'with python3 tools/anatomy_validity.py --build '
                             '--output docs/validation/anatomy-template-report.json')


def _fixture(root):
    """A probe that imports a package module, a cited input, and an
    unrelated module, with the binding code beside them."""
    files = {
        'tools/anatomy_probe.mojo':
            'from pkg.bound import value\nfrom std.sys import argv\n\n\n'
            'def main():\n    """Mentions import of prose that is not a module."""\n'
            '    print(value())\n',
        'pkg/bound.mojo': 'from helper import other\n\n\ndef value() -> Int:\n    return other()\n',
        'helper.mojo': 'def other() -> Int:\n    return 1\n',
        'cited.mojo': 'def cited():\n    pass\n',
        'unrelated.mojo': 'def unrelated():\n    pass\n',
        'tools/anatomy_validity.py': 'report logic',
        'tools/affected.py': 'resolver',
        'docs/validation/anatomy-provenance.json':
            json.dumps({'parameters': [{'source_files': ['cited.mojo']}]}),
    }
    for name, text in files.items():
        path = root/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


class AnatomyReportBindingTests(unittest.TestCase):
    def test_checked_in_report_matches_current_source(self):
        # Only the probe closure, cited inputs, binding code, inventory and
        # build contract enter this digest. This test and the saved report
        # cannot bind themselves.
        check_binding(av.ROOT)

    def test_the_binding_is_the_closure_cited_inputs_and_code(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            _fixture(root)
            self.assertEqual(av.bound_paths(root), [
                'cited.mojo', 'docs/validation/anatomy-provenance.json', 'helper.mojo',
                'pkg/bound.mojo', 'tools/affected.py', 'tools/anatomy_probe.mojo',
                'tools/anatomy_validity.py'])

    def test_bound_changes_stale_the_report_and_others_do_not(self):
        changes = {
            'closure': lambda root: (root/'helper.mojo').write_text('def other() -> Int:\n    return 2\n'),
            'probe': lambda root: (root/'tools/anatomy_probe.mojo').write_text(
                'from pkg.bound import value\n\n\ndef main():\n    pass\n'),
            # A module beside the entry point shadows the root one.
            'shadow': lambda root: (root/'tools/helper.mojo').write_text('def other() -> Int:\n    return 3\n'),
            'cited': lambda root: (root/'cited.mojo').write_text('def cited():\n    return\n'),
            'logic': lambda root: (root/'tools/anatomy_validity.py').write_text('changed logic'),
            'resolver': lambda root: (root/'tools/affected.py').write_text('changed resolver'),
            'inventory': lambda root: (root/'docs/validation/anatomy-provenance.json').write_text(
                json.dumps({'parameters': [{'source_files': ['cited.mojo']}], 'note': 1})),
            'unrelated': lambda root: (root/'unrelated.mojo').write_text('def changed():\n    pass\n'),
            'added_unrelated': lambda root: (root/'other/new.mojo').parent.mkdir() or
                (root/'other/new.mojo').write_text('def new():\n    pass\n'),
        }
        for change, apply in changes.items():
            with self.subTest(change=change), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                _fixture(root)
                before = av.source_digest(root)
                apply(root)
                after = av.source_digest(root)
                if change in ('unrelated', 'added_unrelated'):
                    self.assertEqual(before, after)
                else:
                    self.assertNotEqual(before, after)

    def test_the_build_contract_is_bound(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            _fixture(root)
            before = av.source_digest(root)
            for name, value in (('PINNED_TOOLCHAIN', 'Mojo 1.2.0 (other)'),
                                ('BUILD_FLAGS', ['--Werror']),
                                ('BINDING_VERSION', 'anatomy-binding-v4')):
                with self.subTest(name=name), patch.object(av, name, value):
                    self.assertNotEqual(av.source_digest(root), before)

    def test_unbindable_inputs_are_refused(self):
        refusals = {
            'missing probe': lambda root: (root/'tools/anatomy_probe.mojo').unlink(),
            'missing cited input': lambda root: (root/'cited.mojo').unlink(),
            'missing binding code': lambda root: (root/'tools/affected.py').unlink(),
            'unresolved import': lambda root: (root/'pkg/bound.mojo').write_text(
                'from nowhere import other\n'),
            'relative import': lambda root: (root/'pkg/bound.mojo').write_text(
                'from .helper import other\n'),
            # An existing ancestor does not stand for a missing module.
            'missing module in a package': lambda root: (
                (root/'pkg/__init__.mojo').write_text('')
                or (root/'pkg/bound.mojo').write_text('from pkg.missing import other\n')),
            'missing module beside a module': lambda root: (root/'pkg/bound.mojo').write_text(
                'import helper.missing\n'),
            'unreadable import': lambda root: (root/'pkg/bound.mojo').write_text(
                'import 3d\n'),
            'unclosed import list': lambda root: (root/'pkg/bound.mojo').write_text(
                'from helper import (other\n'),
            'unended string': lambda root: (root/'pkg/bound.mojo').write_text(
                'var text = "open\nfrom helper import other\n'),
        }
        for name, apply in refusals.items():
            with self.subTest(refusal=name), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                _fixture(root)
                apply(root)
                with self.assertRaises(ValueError):
                    av.source_digest(root)

    def test_imports_are_read_as_the_compiler_reads_them(self):
        # Prose and strings hold no imports, and an alias can follow a tab.
        probe = ('"""Prose that is not code.\n\nimport missing\n'
                 'from .example import value\n"""\n'
                 'from pkg import bound\tas renamed\n'
                 'from helper import (\n    other\tas\tanother,  # import nowhere\n)\n'
                 "var text = r'from .x import y\\'\n"
                 '\n\ndef main():\n    pass\n')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            _fixture(root)
            (root/'pkg/__init__.mojo').write_text('')
            (root/'tools/anatomy_probe.mojo').write_text(probe)
            self.assertEqual(av.imports_of(probe),
                             [('pkg', ['bound']), ('helper', ['other'])])
            self.assertIn('pkg/bound.mojo', av.bound_paths(root))
            self.assertIn('helper.mojo', av.bound_paths(root))
            before = av.source_digest(root)
            (root/'pkg/bound.mojo').write_text('def value() -> Int:\n    return 4\n')
            self.assertNotEqual(av.source_digest(root), before)

    def test_each_alias_spacing_binds_its_module(self):
        # Pinned Mojo 1.1.0 compiles all six forms. Each one alone must
        # bind the module it imports.
        forms = ('import pkg.bound as renamed', 'import pkg.bound\tas renamed',
                 'import pkg.bound as\trenamed', 'from pkg import bound as renamed',
                 'from pkg import bound\tas renamed', 'from pkg import bound as\trenamed')
        for form in forms:
            with self.subTest(form=form), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                _fixture(root)
                (root/'pkg/__init__.mojo').write_text('')
                (root/'tools/anatomy_probe.mojo').write_text(
                    form + '\n\n\ndef main():\n    pass\n')
                self.assertIn('pkg/bound.mojo', av.bound_paths(root))
                before = av.source_digest(root)
                (root/'pkg/bound.mojo').write_text('def value() -> Int:\n    return 5\n')
                self.assertNotEqual(av.source_digest(root), before)

    def test_plain_imports_and_symbols_are_kept_apart(self):
        source = 'import pkg.bound as bound, helper\nfrom pkg import *\nimport a.b; import c\n'
        self.assertEqual(av.imports_of(source), [
            ('pkg.bound', None), ('helper', None), ('pkg', []), ('a.b', None), ('c', None)])
        for unreadable in ('from pkg import a.b\n', 'from pkg import\n', 'import\n',
                           'from 3d import x\n', 'import pkg as\n'):
            with self.subTest(source=unreadable), self.assertRaises(ValueError):
                av.imports_of(unreadable)
        # A name that only starts like an import is not one.
        self.assertEqual(av.imports_of('from_here = 1\nimported = 2\n'), [])

    def test_missing_and_stale_reports_are_rejected(self):
        for mutation in ('none', 'source', 'logic', 'inventory', 'missing_report',
                         'missing_key', 'report_logic_hash'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                _fixture(root)
                digest, hashes, _ = av.source_snapshot(root)
                report = {'build_provenance': {'source_sha256': digest},
                          'report_logic_sha256': hashes['tools/anatomy_validity.py'],
                          'inventory_sha256': hashes['docs/validation/anatomy-provenance.json']}
                if mutation == 'source':
                    (root/'helper.mojo').write_text('def other() -> Int:\n    return 9\n')
                elif mutation == 'logic':
                    (root/'tools/anatomy_validity.py').write_text('changed logic')
                    # Keep the digest current to check the separate hash.
                    report['build_provenance']['source_sha256'] = av.source_digest(root)
                elif mutation == 'inventory':
                    (root/'docs/validation/anatomy-provenance.json').write_text(
                        json.dumps({'parameters': [{'source_files': ['cited.mojo']}], 'v': 2}))
                    report['build_provenance']['source_sha256'] = av.source_digest(root)
                elif mutation == 'missing_key':
                    del report['build_provenance']['source_sha256']
                elif mutation == 'report_logic_hash':
                    report['report_logic_sha256'] = 'wrong'
                if mutation != 'missing_report':
                    (root/'docs/validation/anatomy-template-report.json').write_text(json.dumps(report))
                if mutation == 'none':
                    check_binding(root)
                else:
                    with self.assertRaises((ValueError, FileNotFoundError, KeyError)):
                        check_binding(root)


if __name__ == '__main__':
    unittest.main()
