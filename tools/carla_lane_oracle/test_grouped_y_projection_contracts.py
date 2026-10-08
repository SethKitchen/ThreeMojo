"""Fail-closed actual-first Y -> selection -> table historical projection."""
from pathlib import Path
import hashlib
import json
import tempfile
import unittest
from unittest import mock
import grouped_y_finiteness_contracts as y
import selection_finiteness_contracts as selection
import grouped_table_contracts as table
import source_contracts
ROOT = Path(__file__).resolve().parents[2]


class GroupedYProjection(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        paths = set(y.EXPECTED) | set(selection.EXPECTED) | {
            y.RECORD, 'tools/carla_lane_oracle/selection-finiteness-contract.json'}
        for path in paths:
            target = self.root/path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT/path).read_bytes())

    def test_exact_predecessor_and_unchanged_actual_source(self):
        actual = (self.root/y.MODULE).read_bytes()
        record = json.loads((self.root/y.RECORD).read_text())
        restored = y.predecessor_text(self.root, y.MODULE)
        self.assertEqual(restored, record['before_complete_module'])
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), record['predecessor_file_sha256'])
        self.assertEqual((self.root/y.MODULE).read_bytes(), actual)

    def test_complete_two_stage_projection(self):
        self.assertEqual(selection.verify(self.root)['status'], 'PASS')
        restored = selection.predecessor_text(self.root, y.MODULE)
        self.assertEqual(source_contracts.token_sha256(restored), table.TOKEN_SHA256)
        self.assertEqual(table.verify(self.root)['status'], 'PASS')

    def test_every_actual_dependency_rejected_before_record(self):
        for path in y.EXPECTED:
            with self.subTest(path=path):
                target = self.root/path
                old = target.read_text()
                target.write_text(old + '\ncomptime changed_actual_dependency = 1\n')
                with self.assertRaisesRegex(ValueError, 'premise, graph, writes or ordering'):
                    y.predecessor_text(self.root, y.MODULE)
                with self.assertRaises(ValueError):
                    selection.verify(self.root)
                target.write_text(old)

    def test_record_rewrite_rejected(self):
        path = self.root/y.RECORD
        path.write_text(path.read_text() + '\n')
        with self.assertRaisesRegex(ValueError, 'Unreviewed grouped Y successor record'):
            y.predecessor_text(self.root, y.MODULE)

    def test_wrong_target_and_no_recursive_selection_call(self):
        with self.assertRaisesRegex(ValueError, 'only its exact grouped module'):
            y.predecessor_text(self.root, 'extensions/carla/spiral_roundoff_proof.mojo')
        with mock.patch.object(selection, 'verify', side_effect=AssertionError('recursive selection call')):
            self.assertEqual(source_contracts.token_sha256(y.predecessor_text(self.root, y.MODULE)), y.PREDECESSOR_TOKEN_SHA256)

    def test_preexisting_selection_generation_still_works(self):
        record = json.loads((self.root/y.RECORD).read_text())
        (self.root/y.MODULE).write_text(record['before_complete_module'])
        self.assertEqual(selection.verify(self.root)['status'], 'PASS')
        self.assertEqual(table.verify(self.root)['status'], 'PASS')
        with self.assertRaises(ValueError):
            y.predecessor_text(self.root, y.MODULE)

    def test_other_selection_producer_remains_checked(self):
        path = self.root/'extensions/carla/spiral_roundoff_proof.mojo'
        text = path.read_text()
        self.assertIn('floor(selection.low) != 0.0', text)
        path.write_text(text.replace('floor(selection.low) != 0.0', 'False', 1))
        with self.assertRaisesRegex(ValueError, 'Selection producer/input/error/phase graph changed'):
            selection.verify(self.root)

    def test_benign_actual_comments_and_spacing(self):
        for path in y.EXPECTED:
            target = self.root/path
            target.write_text(target.read_text() + '\n# harmless source annotation\n')
        target = self.root/y.MODULE
        target.write_text(target.read_text().replace('copies =', 'copies  ='))
        self.assertEqual(selection.verify(self.root)['status'], 'PASS')
        self.assertEqual(table.verify(self.root)['status'], 'PASS')


if __name__ == '__main__':
    unittest.main()
