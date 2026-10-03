# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Keep fixture runtime pins, non-mutating verification and bit comparisons exact."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from fixture_manifest import ROOT, MANIFEST, runtime_metadata_errors
from fixture_runtime import output_words, reproduce, runtime_errors, table_words, word_differences, word_digest


class FixtureRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.families = {f['family']: f for f in json.loads((ROOT / MANIFEST).read_text())['families']}
        self.family = copy.deepcopy(self.families['js_number'])
        self.baseline = self.family['verified_runtime']

    def test_exact_runtime_is_required(self):
        observed = {key: self.baseline[key] for key in ('node', 'v8', 'platform', 'arch')}
        self.assertEqual(runtime_errors(observed, self.baseline), [])
        for key in observed:
            with self.subTest(key=key):
                changed = {**observed, key: 'different'}
                self.assertEqual(len(runtime_errors(changed, self.baseline)), 1)
                self.assertIn(key, runtime_errors(changed, self.baseline)[0])

    def test_known_metadata_and_locked_packages_match(self):
        for name in ('vtk', 'js_number'):
            self.assertEqual(runtime_metadata_errors(ROOT, self.families[name]), [])
        self.assertEqual(runtime_metadata_errors(ROOT, {'family': 'unverified'}), [])

    def test_runtime_flags_versions_dependencies_and_commands_cannot_drift(self):
        mutations = [
            lambda f: f.pop('verified_runtime'),
            lambda f: f['verified_runtime'].update(node='24'),
            lambda f: f['verified_runtime'].update(v8='13.6'),
            lambda f: f['verified_runtime'].update(platform='darwin'),
            lambda f: f['verified_runtime'].update(arch='arm64'),
            lambda f: f['verified_runtime'].update(node_flags=[]),
            lambda f: f['verified_runtime'].update(historical_environment_recovered=True),
            lambda f: f['verified_runtime'].update(evidence=''),
            lambda f: f['verified_runtime'].update(dependencies={}),
            lambda f: f['verified_runtime']['dependencies'].update(three='^0.180.0'),
            lambda f: f.update(three_version='0.180.0'),
            lambda f: f.update(cwd='assets/js_number'),
            lambda f: f.update(commands=['node srgb.mjs']),
        ]
        for change in mutations:
            family = copy.deepcopy(self.family)
            change(family)
            self.assertTrue(runtime_metadata_errors(ROOT, family))

    def test_separate_snapshot_cannot_claim_srgb_reproduction(self):
        for change in ({'status': 'reproduced'}, {'generator': 'srgb.mjs'},
                       {'historical_node': '24.19.0'}, {'historical_v8': '13.6.233.17-node.51'},
                       {'historical_node_major': 24},
                       {'path': 'other.json'}, {'evidence': ''}):
            family = copy.deepcopy(self.family)
            family['separate_snapshot'].update(change)
            self.assertTrue(runtime_metadata_errors(ROOT, family))
        self.assertEqual(self.family['three_version'], None)
        self.assertEqual(self.family['separate_snapshot']['historical_node_major'], 22)

    def test_package_and_lock_pins_cannot_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package_dir = root / 'tools/fixture-runtime'
            package_dir.mkdir(parents=True)
            originals = {name: (ROOT / 'tools/fixture-runtime' / name).read_text()
                         for name in ('package.json', 'package-lock.json')}
            for file, original in originals.items():
                (package_dir / file).write_text(original)
            self.assertEqual(runtime_metadata_errors(root, self.family), [])
            mutations = [
                ('package.json', lambda p: p['engines'].update(node='>=24')),
                ('package.json', lambda p: p['dependencies'].update(three='^0.180.0')),
                ('package-lock.json', lambda p: p['packages'][''].update(engines={})),
                ('package-lock.json', lambda p: p['packages'][''].update(dependencies={})),
                ('package-lock.json', lambda p: p['packages']['node_modules/three'].update(version='0.181.0')),
                ('package-lock.json', lambda p: p['packages']['node_modules/three'].pop('integrity')),
            ]
            for file, change in mutations:
                with self.subTest(file=file):
                    data = json.loads(originals[file])
                    change(data)
                    (package_dir / file).write_text(json.dumps(data))
                    self.assertTrue(runtime_metadata_errors(root, self.family))
                    (package_dir / file).write_text(originals[file])
            (package_dir / 'package-lock.json').unlink()
            self.assertTrue(runtime_metadata_errors(root, self.family))

    def test_word_parser_is_bounded_to_the_srgb_table(self):
        text = ',\n'.join(f'0x{i:016X}' for i in range(256))
        self.assertEqual(output_words(text), list(range(256)))
        source = ('# 0xFFFFFFFFFFFFFFFF\ncomptime _SRGB_TO_LINEAR: List[UInt64] = ['
                  + text + ']\n# 0xFFFFFFFFFFFFFFFF')
        self.assertEqual(table_words(source), list(range(256)))
        for bad in ('', text + ', 0x0000000000000000', text.replace('0x', 'x', 1), text + '\nextra'):
            with self.assertRaises(ValueError):
                output_words(bad)
        with self.assertRaises(ValueError):
            table_words(text)

    def test_word_diff_preserves_direction_and_float32_effect(self):
        old = [0x3F76F5ADDB270744, 0x3F78C6A940063D0E, 0x3FF0000000000000]
        new = [old[0] + 1, old[1] - 1, old[2]]
        differences = word_differences(old, new)
        self.assertEqual([d['ulp_delta'] for d in differences], [1, -1])
        self.assertTrue(all(d['float32_unchanged'] for d in differences))
        self.assertNotEqual(word_digest(old), word_digest(new))
        self.assertEqual(word_differences(old, old), [])
        self.assertFalse(word_differences([old[2]], [0x4000000000000000])[0]['float32_unchanged'])
        with self.assertRaisesRegex(ValueError, 'counts differ'):
            word_differences(old, new[:-1])

    @patch.dict('os.environ', {}, clear=True)
    def test_missing_flag_and_runtime_mismatch_stop_before_generation(self):
        self.family['verified_runtime']['node_flags'] = []
        with patch('fixture_runtime.subprocess.check_output') as run:
            with self.assertRaisesRegex(ValueError, 'requires --no-use-std-math-pow'):
                reproduce(ROOT, self.family, 'node', Path('/unused'))
            run.assert_not_called()

    @patch.dict('os.environ', {'NODE_OPTIONS': '--jitless'}, clear=True)
    def test_node_options_cannot_change_verified_execution(self):
        with patch('fixture_runtime.subprocess.check_output') as run:
            with self.assertRaisesRegex(ValueError, 'unset NODE_OPTIONS'):
                reproduce(ROOT, self.family, 'node', Path('/unused'))
            run.assert_not_called()

    @patch.dict('os.environ', {}, clear=True)
    def test_reproduction_uses_temporary_outputs_and_exact_flags(self):
        with tempfile.TemporaryDirectory() as directory:
            dependencies = Path(directory)
            (dependencies / 'three').mkdir()
            (dependencies / 'three/package.json').write_text('{"version":"0.180.0"}')
            observed = {key: self.baseline[key] for key in ('node', 'v8', 'platform', 'arch')}
            accepted = table_words((ROOT / 'loaders/js_number.mojo').read_text())
            output = ',\n'.join(f'0x{w:016X}' for w in accepted)
            with patch('fixture_runtime.subprocess.check_output', side_effect=[json.dumps(observed), output]) as run:
                report = reproduce(ROOT, self.family, 'node', dependencies)
                self.assertTrue(report['matches'])
                self.assertFalse(report['historical_environment_recovered'])
                self.assertEqual(report['not_regenerated'], ['assets/js_number/v8.json'])
                command = run.call_args_list[1]
                self.assertEqual(command.args[0], ['node', '--no-use-std-math-pow', 'srgb.mjs'])
                self.assertNotEqual(command.kwargs['cwd'], ROOT / 'assets/js_number')
                self.assertFalse(command.kwargs['cwd'].exists())
            with patch('fixture_runtime.subprocess.check_output', side_effect=[json.dumps(observed), output]):
                report = reproduce(ROOT, self.family, 'node', dependencies, True)
                self.assertEqual(report['mode'], 'diagnostic_only')
                self.assertEqual(report['runtime']['node_flags'], [])
            observed['node'] = '0.0.0'
            with patch('fixture_runtime.subprocess.check_output', return_value=json.dumps(observed)) as run:
                with self.assertRaisesRegex(ValueError, 'node: expected'):
                    reproduce(ROOT, self.family, 'node', dependencies)
                self.assertEqual(run.call_count, 1)
            observed['node'] = self.baseline['node']
            (dependencies / 'three/package.json').write_text('{"version":"0.181.0"}')
            with patch('fixture_runtime.subprocess.check_output', return_value=json.dumps(observed)) as run:
                with self.assertRaisesRegex(ValueError, 'three: expected'):
                    reproduce(ROOT, self.family, 'node', dependencies)
                self.assertEqual(run.call_count, 1)


if __name__ == '__main__':
    unittest.main()
