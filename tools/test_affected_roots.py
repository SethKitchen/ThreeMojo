# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
"""Resolve imports from the entry point's directory and the root (#714).

Each fixture records what pinned Mojo 1.1.0 (8189361e) did with
`mojo build --num-threads 1 -I . tools/probe.mojo`, where tools/probe.mojo
imports `pkg.one` and pkg/one.mojo imports `helper`:

- root helper.mojo and pkg/helper.mojo: the root one;
- pkg/helper.mojo alone: "unable to locate module 'helper'", with or
  without pkg/__init__.mojo;
- tools/helper.mojo, helper.mojo and pkg/helper.mojo: the tools one;
- tools/pkg/__init__.mojo without tools/pkg/one.mojo: "unable to locate
  module 'one'" even with a root pkg/one.mojo;
- a plain tools/pkg directory without one.mojo: the root pkg/one.mojo;
- tools/pkg/one.mojo and pkg/one.mojo, neither under a package
  initializer: "ambiguous import 'one'".

The resolver keeps every file each root can reach, so a change to either
side of a hidden or ambiguous name still selects the entry point.
"""

import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import affected
import ci_scope
import shard
import suite_key

PROBE = 'from pkg.one import value\n\n\ndef main():\n    print(value())\n'
VALUE = 'def value() -> Int:\n    return 1\n'


class ResolveTests(unittest.TestCase):
    def test_entry_directory_then_root_never_the_importer_directory(self):
        known = {'tools/probe.mojo', 'pkg/one.mojo', 'helper.mojo', 'pkg/helper.mojo'}
        # A transitive import searches the entry point's directory and the root.
        self.assertEqual(affected.resolve('helper', 'pkg/one.mojo', known, ['tools']),
                         ['helper.mojo'])
        known.add('tools/helper.mojo')
        self.assertEqual(affected.resolve('helper', 'pkg/one.mojo', known, ['tools']),
                         ['tools/helper.mojo', 'helper.mojo'])
        # A direct import from the entry point uses the same two roots.
        self.assertEqual(affected.resolve('helper', 'tools/probe.mojo', known),
                         ['tools/helper.mojo', 'helper.mojo'])

    def test_importer_sibling_never_substitutes_for_a_missing_module(self):
        known = {'tools/probe.mojo', 'pkg/__init__.mojo', 'pkg/one.mojo', 'pkg/helper.mojo'}
        self.assertEqual(affected.resolve('helper', 'pkg/one.mojo', known, ['tools']), [])
        # The sibling counts only when an entry point can sit beside it.
        self.assertEqual(affected.resolve('helper', 'pkg/one.mojo', known, ['tools', 'pkg']),
                         ['pkg/helper.mojo'])

    def test_package_initializers_and_namespace_prefix_overlaps(self):
        known = {'pkg/__init__.mojo', 'pkg/one.mojo', 'tools/pkg/__init__.mojo'}
        # A package initializer in the entry directory hides the root package.
        self.assertEqual(affected.resolve('pkg.one', 'tools/probe.mojo', known),
                         ['tools/pkg/__init__.mojo', 'pkg/__init__.mojo', 'pkg/one.mojo'])
        # A plain directory there does not; with its own module it is ambiguous.
        known = {'pkg/one.mojo', 'tools/pkg/other.mojo'}
        self.assertEqual(affected.resolve('pkg.one', 'tools/probe.mojo', known),
                         ['pkg/one.mojo'])
        known.add('tools/pkg/one.mojo')
        self.assertEqual(affected.resolve('pkg.one', 'tools/probe.mojo', known),
                         ['tools/pkg/one.mojo', 'pkg/one.mojo'])
        # A package named by its initializer alone, and a name nothing defines.
        self.assertEqual(affected.resolve('pkg', 'core/scene.mojo', {'pkg/__init__.mojo'}),
                         ['pkg/__init__.mojo'])
        self.assertEqual(affected.resolve('std.sys', 'core/scene.mojo', known), [])

    def test_entry_directories_are_the_directories_of_main(self):
        sources = {
            'tools/probe.mojo': PROBE,
            'bench/run.mojo': 'fn main():\n    pass\n',
            'pkg/one.mojo': '# def main():\nfrom helper import value\n',
            'pkg/two.mojo': 'def mainly():\n    pass\n',
            'driver.mojo': 'def main() raises:\n    pass\n',
        }
        self.assertEqual(affected.entry_directories(sources), ['', 'bench', 'tools'])

    def test_resolver_remembers_answers_for_one_root_set(self):
        known = {'helper.mojo', 'tools/helper.mojo'}
        lookup = affected.resolver(known, ['tools'])
        with patch.object(affected, 'resolve', wraps=affected.resolve) as resolve:
            self.assertEqual(lookup('helper'), ['tools/helper.mojo', 'helper.mojo'])
            self.assertEqual(lookup('helper'), ['tools/helper.mojo', 'helper.mojo'])
        self.assertEqual(resolve.call_count, 1)


class TreeTests(unittest.TestCase):
    """Run the selection tools on the native fixture's file tree."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.write('tools/probe.mojo', PROBE)
        self.write('tests/test_probe.mojo', PROBE)
        self.write('pkg/one.mojo', 'from helper import value\n')
        self.write('helper.mojo', VALUE)
        self.write('pkg/helper.mojo', VALUE)
        patcher = patch.object(affected, 'ROOT', str(self.root))
        patcher.start()
        self.addCleanup(patcher.stop)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def test_changed_actual_dependency_selects_every_consumer(self):
        self.assertEqual(affected.affected_set({'helper.mojo': False}),
                         {'helper.mojo', 'pkg/one.mojo', 'tools/probe.mojo',
                          'tests/test_probe.mojo'})
        # The importer's sibling is not compiled, so it selects nothing else.
        self.assertEqual(affected.affected_set({'pkg/helper.mojo': False}),
                         {'pkg/helper.mojo'})

    def test_a_module_beside_one_entry_point_selects_only_its_users(self):
        self.write('tools/helper.mojo', VALUE)
        selected = affected.affected_set({'tools/helper.mojo': False})
        self.assertIn('tools/probe.mojo', selected)
        self.assertIn('pkg/one.mojo', selected)
        # The union over entry directories also reaches the tests suite,
        # whose build uses the root helper; selection can only grow.
        self.assertIn('tests/test_probe.mojo', selected)

    def test_ci_scope_graph_uses_entry_directories(self):
        sources = {name: (self.root / name).read_text()
                   for name in affected.mojo_files()}
        imports, users = ci_scope.graph(sources)
        self.assertEqual(imports['pkg/one.mojo'], {'helper.mojo'})
        self.assertNotIn('pkg/helper.mojo', users)

    def test_suite_closure_and_weight_use_the_suite_directory(self):
        self.write('tests/helper.mojo', VALUE)
        known = set(affected.mojo_files())
        imports = {}
        self.assertEqual(suite_key.closure('tests/test_probe.mojo', known, imports),
                         ['helper.mojo', 'pkg/one.mojo', 'tests/helper.mojo',
                          'tests/test_probe.mojo'])
        # The same cache serves a suite in another directory correctly.
        self.assertEqual(suite_key.closure('tools/probe.mojo', known, imports),
                         ['helper.mojo', 'pkg/one.mojo', 'tools/probe.mojo'])
        sizes = {name: (self.root / name).stat().st_size for name in known}
        self.assertEqual(shard.weight('tools/probe.mojo', known, sizes, {}),
                         sizes['helper.mojo'] + sizes['pkg/one.mojo']
                         + sizes['tools/probe.mojo'])


if __name__ == '__main__':
    unittest.main()
