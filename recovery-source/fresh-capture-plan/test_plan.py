"""Compiler-free helper/config tests. No repository module is imported or run."""
import ast
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


support = load('fresh_plan_support', HERE / 'capture_support.py')
prepare = load('fresh_plan_prepare', HERE / 'prepare_run.py')


class PureTests(unittest.TestCase):
    def test_fresh_denominator_is_not_historical_293(self):
        result = support.classify_report(0, b'TOTAL 11/11 100%\n', 11)
        self.assertEqual(result['required'], 11)
        with self.assertRaises(ValueError):
            support.classify_report(0, b'TOTAL 293/293 100%\n', 11)

    def test_complete_and_deficit_are_distinct(self):
        raw = (b'TOTAL 7/11 63%\nUnhandled exception caught during execution: '
               b'Coverage is incomplete: 4 of 11 items never covered.\n')
        result = support.classify_report(1, raw, 11)
        self.assertEqual(result['coverage_state'], 'incomplete_coverage')
        with self.assertRaises(ValueError):
            support.classify_report(0, raw, 11)
        with self.assertRaises(ValueError):
            support.classify_report(2, raw, 11)
        with self.assertRaises(ValueError):
            support.classify_report(1, b'Coverage replay failed: test\n' + raw, 11)

    def test_daz_requires_actual_both_modes(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'synthetic.log'
            text = 'REFUSAL_LEDGER 5 5000000005 1 0\n'
            text += 'LAST_REFUSAL_LEDGER 5 5 5000000005 1 0\n'
            path.write_text(text)
            with self.assertRaises(ValueError):
                support.daz_witness(path)
            path.write_text(text + 'LAST_REFUSAL_LEDGER 6 5 5000000005 1 0\n')
            self.assertEqual(support.daz_witness(path)['last_end_daz_modes'], [5, 6])
            path.write_text(path.read_text() + 'LAST_DAZ_CAPABILITY_UNAVAILABLE\n')
            with self.assertRaises(ValueError):
                support.daz_witness(path)

    def test_unchanged_origin_and_denominator_boundary(self):
        old = HERE.parent.parent / 'recovery-carla-capture-plan/exact/capture_support.py'
        def definitions(path):
            return {node.name: ast.dump(node, include_attributes=False)
                    for node in ast.parse(path.read_text()).body if isinstance(node, ast.FunctionDef)}
        before, after = definitions(old), definitions(HERE / 'capture_support.py')
        for name in ('target_material', 'check_frozen', 'classify_report', 'report_log', 'load_tools'):
            self.assertEqual(before[name], after[name], name)

    def test_duplicate_consumed_module_instances_are_rejected(self):
        affected = SimpleNamespace(__file__="/sealed/tools/affected.py")
        native = SimpleNamespace(__file__="/sealed/tools/native_test_support.py")
        suite_key = SimpleNamespace(affected=affected, native_test_support=native)
        with mock.patch.dict(sys.modules, {"affected": affected, "suite_key": suite_key,
                                           "native_test_support": native}):
            support.require_native_module_identity(affected, suite_key, native)
            # Same file pathname is insufficient: this is a different object.
            suite_key.affected = SimpleNamespace(__file__=affected.__file__)
            with self.assertRaises(ValueError):
                support.require_native_module_identity(affected, suite_key, native)
            suite_key.affected = affected
            suite_key.native_test_support = SimpleNamespace(__file__=native.__file__)
            with self.assertRaises(ValueError):
                support.require_native_module_identity(affected, suite_key, native)

    def test_config_generator_in_synthetic_workspace(self):
        # Copy input bytes, but never import them. The resulting configs are
        # test fixtures in a temporary directory, not an approved run bundle.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            here = root / 'plan'
            here.mkdir()
            source = root / 'source'
            source.mkdir()
            spec = json.loads((HERE / 'plan-spec.json').read_text())
            original = HERE.parent / 'candidate-v2'
            for name in spec['frozen_hashes']:
                target = source / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(original / name, target)
            shutil.copy2(HERE / 'plan-spec.json', here / 'plan-spec.json')
            shutil.copy2(HERE / 'capture_support.py', here / 'capture_support.py')
            (root / 'run_stage.py').write_text('# Synthetic supervisor, never executed.\n')
            recovered = root / 'recovery-carla-capture-plan/exact'
            recovered.mkdir(parents=True)
            shutil.copy2(HERE.parent.parent / 'recovery-carla-capture-plan/exact/capture_support.py',
                         recovered / 'capture_support.py')
            seal = root / 'SOURCE-SEAL.json'
            seal.write_text(json.dumps(prepare.snapshot(source)))
            argv = ['prepare_run.py', '--label', 'carla-synthetic-test', '--source-root', str(source),
                    '--source-seal', str(seal), '--source-seal-sha256', prepare.sha(seal)]
            with mock.patch.multiple(prepare, HERE=here, ROOT=root, WORK=root), \
                    mock.patch.object(sys, 'argv', argv), contextlib.redirect_stdout(io.StringIO()):
                prepare.main()
                with self.assertRaises(ValueError):
                    prepare.main()  # Never overwrite an earlier attempt.
            out = here / 'prepared/carla-synthetic-test'
            bundle_seal = json.loads((here / 'prepared/carla-synthetic-test-SEAL.json').read_text())
            self.assertEqual(prepare.snapshot(out), bundle_seal)
            for optimization in ('o3', 'o0'):
                config = json.loads((out / ('native-' + optimization + '.json')).read_text())
                builds = [s for s in config['stages'] if s['label'].endswith('-build')]
                runs = [s for s in config['stages'] if s['label'].endswith('-run')]
                self.assertEqual(len(builds), 19)
                self.assertEqual(len(runs), 19)
                for stage in builds:
                    self.assertEqual(stage['seconds'], 180)
                    self.assertIn('-O' + optimization[-1], stage['command'])
                    self.assertIn('tools/native_test_support.py', ' '.join(stage['command']))
                for stage in runs:
                    self.assertEqual(stage['seconds'], 15)
                    self.assertIn('5', stage['command'])
            preparation = json.loads((out / 'prepare.json').read_text())
            self.assertEqual(preparation['window_seconds'], 1200)
            capture = json.loads((out / 'capture.json').read_text())
            self.assertEqual(capture['window_seconds'], 10000)
            self.assertEqual([s['seconds'] for s in capture['stages']], [180, 9030, 180, 180])
            self.assertIn('9000', capture['stages'][1]['command'])
            self.assertFalse((root / 'evidence').exists())
            self.assertFalse(any(out.rglob('FINAL-TARGETED-RESULT.json')))


if __name__ == '__main__':
    unittest.main()
