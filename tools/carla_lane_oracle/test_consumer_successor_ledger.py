# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""The consumer successor ledger admits reviewed chains and nothing else."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import border_parser_contracts as border
import consumer_successor_ledger as ledger
import source_contracts as source
import winner_sign_contracts as winner

ROOT = Path(__file__).resolve().parents[2]
CONSUMER = 'extensions/carla/actor.mojo'
BOUND_TEST = 'tests/test_carla_agents.mojo'


def sha(content):
    return hashlib.sha256(content).hexdigest()


def edge(path, before, after, tests, issue=703):
    return {'issue': issue, 'path': path,
            'before_sha256': sha(before), 'after_sha256': sha(after),
            'before_token_sha256': source.token_sha256(before.decode()),
            'after_token_sha256': source.token_sha256(after.decode()),
            'correctness_tests': tests}


def ledger_bytes(edges):
    return json.dumps({'schema': 1, 'scope': 'test', 'edges': edges}, indent=2).encode()


def patched(root, files):
    """Serve `files` (path to bytes) in place of the real ones under `root`."""
    read = Path.read_bytes
    targets = {root/name: content for name, content in files.items()}
    return patch.object(Path, 'read_bytes',
                        lambda p, *a, **k: targets[p] if p in targets else read(p, *a, **k))


class LedgerFixture(unittest.TestCase):
    """A root with two pinned consumers, one bound test and the two records."""

    BEFORE = b'def value() -> Int:\n    return 1\n'
    MIDDLE = b'def value() -> Int:\n    return 2\n'
    AFTER = b'def value() -> Int:\n    return 3\n'
    TEST_SOURCE = b'def main():\n    pass\n'

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.write('extensions/carla/one.mojo', self.BEFORE)
        self.write('extensions/carla/two.mojo', self.BEFORE)
        self.write('extensions/carla/map.mojo', self.BEFORE)
        self.write('tests/test_one.mojo', self.TEST_SOURCE)
        pins = {'extensions/carla/one.mojo': sha(self.BEFORE),
                'extensions/carla/map.mojo': sha(self.BEFORE)}
        self.write(ledger.RECORDS[0][0], json.dumps({'unchanged_inputs': pins}).encode())
        self.write(ledger.RECORDS[1][0], json.dumps(
            {'canonical_source_unchanged': {'extensions/carla/two.mojo': sha(self.BEFORE)}}).encode())
        self.tests = {'tests/test_one.mojo': sha(self.TEST_SOURCE)}

    def write(self, name, content):
        path = self.root/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    def use(self, edges):
        """Write and pin a ledger of `edges`."""
        content = ledger_bytes(edges)
        self.write(ledger.LEDGER, content)
        pin = patch.object(ledger, 'LEDGER_SHA256', sha(content))
        pin.start()
        self.addCleanup(pin.stop)


class LedgerTests(LedgerFixture):
    def test_an_empty_ledger_extends_nothing(self):
        self.use([])
        self.assertEqual(ledger.verify(self.root), {})
        known = {'x': {'before_sha256': 'a', 'after_sha256': 'b'}}
        self.assertEqual(ledger.extend(known, self.root), known)

    def test_one_edge_needs_its_live_source_and_its_bound_tests(self):
        self.use([edge('extensions/carla/one.mojo', self.BEFORE, self.AFTER, self.tests)])
        with self.assertRaisesRegex(ValueError, 'not the last reviewed edge'):
            ledger.verify(self.root)
        self.write('extensions/carla/one.mojo', self.AFTER)
        chain = ledger.verify(self.root)['extensions/carla/one.mojo']
        self.assertEqual((chain['before_sha256'], chain['after_sha256']),
                         (sha(self.BEFORE), sha(self.AFTER)))
        self.write('tests/test_one.mojo', self.TEST_SOURCE + b'# changed\n')
        with self.assertRaisesRegex(ValueError, 'bound correctness test changed'):
            ledger.verify(self.root)
        (self.root/'tests/test_one.mojo').unlink()
        with self.assertRaisesRegex(ValueError, 'bound correctness test changed'):
            ledger.verify(self.root)

    def test_edges_of_one_consumer_chain_in_order(self):
        path = 'extensions/carla/one.mojo'
        self.use([edge(path, self.BEFORE, self.MIDDLE, self.tests),
                  edge(path, self.MIDDLE, self.AFTER, self.tests)])
        # The live source must be the end of the chain, not a step on it.
        self.write(path, self.MIDDLE)
        with self.assertRaisesRegex(ValueError, 'not the last reviewed edge'):
            ledger.verify(self.root)
        self.write(path, self.AFTER)
        chain = ledger.verify(self.root)[path]
        self.assertEqual((chain['before_sha256'], chain['after_sha256']),
                         (sha(self.BEFORE), sha(self.AFTER)))
        self.assertEqual(chain['before_token_sha256'], source.token_sha256(self.BEFORE.decode()))

    def test_an_edge_must_start_at_the_previous_edge(self):
        path = 'extensions/carla/one.mojo'
        self.write(path, self.AFTER)
        self.use([edge(path, self.BEFORE, self.MIDDLE, self.tests),
                  edge(path, self.BEFORE, self.AFTER, self.tests)])
        with self.assertRaisesRegex(ValueError, 'does not start at the previous edge'):
            ledger.verify(self.root)

    def test_the_ledger_must_be_the_reviewed_one(self):
        self.use([])
        self.write(ledger.LEDGER, ledger_bytes([]) + b'\n')
        with self.assertRaisesRegex(ValueError, 'unreviewed ledger'):
            ledger.verify(self.root)

    def test_malformed_ledgers_and_edges_are_refused(self):
        path = 'extensions/carla/one.mojo'
        self.write(path, self.AFTER)
        good = edge(path, self.BEFORE, self.AFTER, self.tests)
        mutants = {
            'extra key': {**good, 'note': 1},
            'missing key': {k: v for k, v in good.items() if k != 'issue'},
            'no issue': {**good, 'issue': 0},
            'text issue': {**good, 'issue': '703'},
            'same digests': {**good, 'after_sha256': good['before_sha256']},
            'short digest': {**good, 'before_sha256': 'ab'},
            'upper digest': {**good, 'after_token_sha256': good['after_token_sha256'].upper()},
            'no tests': {**good, 'correctness_tests': {}},
            'test outside tests': {**good, 'correctness_tests': {'tools/x.py': sha(b'')}},
            'own contract': {**good, 'path': 'extensions/carla/map.mojo'},
            'unpinned consumer': {**good, 'path': 'extensions/carla/three.mojo'},
            'outside the package': {**good, 'path': 'extensions/carla/../x.mojo'},
            'not a mojo source': {**good, 'path': 'extensions/carla/one.py'},
        }
        for name, mutant in mutants.items():
            with self.subTest(mutant=name):
                self.use([mutant])
                with self.assertRaises(ValueError):
                    ledger.verify(self.root)
        for name, record in (('schema', {'schema': 2, 'scope': '', 'edges': []}),
                             ('edges', {'schema': 1, 'scope': '', 'edges': {}}),
                             ('keys', {'schema': 1, 'edges': []})):
            with self.subTest(record=name):
                content = json.dumps(record).encode()
                self.write(ledger.LEDGER, content)
                with patch.object(ledger, 'LEDGER_SHA256', sha(content)):
                    with self.assertRaises(ValueError):
                        ledger.verify(self.root)
        content = b'{"schema": 1, "schema": 1, "scope": "", "edges": []}'
        self.write(ledger.LEDGER, content)
        with patch.object(ledger, 'LEDGER_SHA256', sha(content)):
            with self.assertRaises(ValueError):
                ledger.verify(self.root)

    def test_either_record_can_pin_the_consumer(self):
        self.write('extensions/carla/two.mojo', self.AFTER)
        self.use([edge('extensions/carla/two.mojo', self.BEFORE, self.AFTER, self.tests)])
        self.assertIn('extensions/carla/two.mojo', ledger.verify(self.root))

    def test_extend_joins_a_known_successor_or_adds_a_chain(self):
        path = 'extensions/carla/one.mojo'
        self.write(path, self.AFTER)
        self.use([edge(path, self.MIDDLE, self.AFTER, self.tests)])
        known = {path: {'path': path, 'before_sha256': sha(self.BEFORE),
                        'after_sha256': sha(self.MIDDLE), 'kind': 'earlier'}}
        joined = ledger.extend(known, self.root)[path]
        self.assertEqual((joined['before_sha256'], joined['after_sha256'], joined['kind']),
                         (sha(self.BEFORE), sha(self.AFTER), 'earlier'))
        self.assertEqual(known[path]['after_sha256'], sha(self.MIDDLE))
        # A known successor that ends elsewhere cannot be joined.
        known[path]['after_sha256'] = sha(self.BEFORE)
        with self.assertRaisesRegex(ValueError, 'does not start at the previous successor'):
            ledger.extend(known, self.root)
        # With no known successor, the chain is added for the record to check.
        self.assertEqual(ledger.extend({}, self.root)[path]['before_sha256'], sha(self.MIDDLE))


class RecordIntegrationTests(unittest.TestCase):
    """Both records consult the real ledger, as they consult earlier edges."""

    def setUp(self):
        self.before = (ROOT/CONSUMER).read_bytes()
        self.after = self.before + b'\n# A reviewed consumer edge.\n'
        self.tests = {BOUND_TEST: sha((ROOT/BOUND_TEST).read_bytes())}

    def served(self, edges, live):
        content = ledger_bytes(edges)
        pin = patch.object(ledger, 'LEDGER_SHA256', sha(content))
        files = patched(ROOT, {ledger.LEDGER: content, CONSUMER: live})
        return pin, files

    def test_the_real_ledger_changes_neither_record(self):
        self.assertEqual(ledger.verify(ROOT), {})
        border.verify(ROOT)
        winner.verify(ROOT)

    def test_a_reviewed_edge_extends_both_records(self):
        pin, files = self.served([edge(CONSUMER, self.before, self.after, self.tests)],
                                 self.after)
        with pin, files:
            border.verify(ROOT)
            self.assertGreaterEqual(winner.verify(ROOT)['reviewed_cleanup_successors'], 1)

    def test_a_chain_of_two_edges_extends_both_records(self):
        middle = self.before + b'\n# First.\n'
        pin, files = self.served([edge(CONSUMER, self.before, middle, self.tests),
                                  edge(CONSUMER, middle, self.after, self.tests)], self.after)
        with pin, files:
            border.verify(ROOT)
            winner.verify(ROOT)

    def test_both_records_refuse_an_edge_that_skips_their_pin(self):
        other = self.before + b'\n# Not the pinned source.\n'
        pin, files = self.served([edge(CONSUMER, other, self.after, self.tests)], self.after)
        for record in (border, winner):
            with self.subTest(record=record.__name__), pin, files:
                with self.assertRaisesRegex(ValueError, 'extend the record|historical canonical'):
                    record.verify(ROOT)

    def test_both_records_refuse_an_unreviewed_consumer_change(self):
        pin, files = self.served([edge(CONSUMER, self.before, self.after, self.tests)],
                                 self.after + b'\n# Unreviewed.\n')
        for record in (border, winner):
            with self.subTest(record=record.__name__), pin, files:
                with self.assertRaisesRegex(ValueError, 'not the last reviewed edge'):
                    record.verify(ROOT)


if __name__ == '__main__':
    unittest.main()
