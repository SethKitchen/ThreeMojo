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
import full_audit_cleanup_contracts as audit
import render_actor_reuse_contracts as reuse
import runtime_boundary_contracts as boundary

ROOT = Path(__file__).resolve().parents[2]


# This module's fixed byte/line/body assertions describe the historical main
# graph. The #333 current graph has separate physical admission/mutation tests.
_CURRENT_SOURCE_ROOT = ROOT


def setUpModule():
    global ROOT
    import _full_audit_test_fixtures as historical_fixtures
    owner = type('HistoricalModuleFixture', (), {
        'addCleanup': staticmethod(unittest.addModuleCleanup)})()
    ROOT = historical_fixtures.copy_historical_boundary_root(owner, _CURRENT_SOURCE_ROOT)
    unittest.addModuleCleanup(globals().__setitem__, 'ROOT', _CURRENT_SOURCE_ROOT)
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


from contextlib import contextmanager


@contextmanager
def physical(root, files):
    """Change real files only inside an isolated test root, then restore them."""
    original = {name: (root/name).read_bytes() for name in files}
    try:
        for name, content in files.items(): (root/name).write_bytes(content)
        yield
    finally:
        for name, content in original.items(): (root/name).write_bytes(content)


class LedgerFixture(unittest.TestCase):
    """A root with two pinned consumers, one bound test and the two records."""

    BEFORE = b'def value() -> Int:\n    return 1\n'
    MIDDLE = b'def value() -> Int:\n    return 2\n'
    AFTER = b'def value() -> Int:\n    return 3\n'
    TEST_SOURCE = b'def main():\n    pass\n'

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name).resolve()
        self.write('extensions/carla/one.mojo', self.BEFORE)
        self.write('extensions/carla/two.mojo', self.BEFORE)
        self.write('extensions/carla/map.mojo', self.BEFORE)
        self.write('tests/test_one.mojo', self.TEST_SOURCE)
        pins = {'extensions/carla/one.mojo': sha(self.BEFORE),
                'extensions/carla/map.mojo': sha(self.BEFORE)}
        self.write(ledger.RECORDS[0][0], json.dumps({'unchanged_inputs': pins}).encode())
        self.write(ledger.RECORDS[1][0], json.dumps(
            {'canonical_source_unchanged': {'extensions/carla/two.mojo': sha(self.BEFORE)}}).encode())
        fixture_records = tuple((path, group, sha((self.root/path).read_bytes()))
                                for path, group, _ in ledger.RECORDS)
        records = patch.object(ledger, 'RECORDS', fixture_records)
        records.start()
        self.addCleanup(records.stop)
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
                        'after_sha256': sha(self.MIDDLE),
                        'before_token_sha256': source.token_sha256(self.BEFORE.decode()),
                        'after_token_sha256': source.token_sha256(self.MIDDLE.decode()),
                        'kind': 'earlier'}}
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


class LedgerChainControls(LedgerFixture):
    def test_exact_first_edge_overlap_then_append(self):
        path = 'extensions/carla/one.mojo'
        first = edge(path, self.BEFORE, self.MIDDLE, self.tests)
        self.use([first, edge(path, self.MIDDLE, self.AFTER, self.tests)])
        self.write(path, self.AFTER)
        known = {'path': path, **{key: first[key] for key in ledger.ENDPOINT_KEYS}}
        result = ledger.extend({path: known}, self.root)[path]
        self.assertEqual(result['before_sha256'], sha(self.BEFORE))
        self.assertEqual(result['after_sha256'], sha(self.AFTER))
        self.assertEqual(known['after_sha256'], sha(self.MIDDLE))
        # A shared tail cannot replace exact first-edge correspondence.
        for key in ledger.ENDPOINT_KEYS:
            wrong = {**known, key: '0' * 64}
            with self.subTest(endpoint=key), self.assertRaises(ValueError):
                ledger.extend({path: wrong}, self.root)

    def test_suffix_requires_both_digest_forms(self):
        path = 'extensions/carla/one.mojo'
        first = edge(path, self.MIDDLE, self.AFTER, self.tests)
        self.use([first]); self.write(path, self.AFTER)
        prior = edge(path, self.BEFORE, self.MIDDLE, self.tests)
        known = {key: prior[key] for key in ledger.ENDPOINT_KEYS}
        self.assertEqual(ledger.extend({path: known}, self.root)[path]['after_sha256'], sha(self.AFTER))
        for key in ('after_sha256', 'after_token_sha256'):
            with self.subTest(endpoint=key), self.assertRaises(ValueError):
                ledger.extend({path: {**known, key: '0' * 64}}, self.root)

    def test_middle_token_only_mismatch_and_reordered_edges_reject(self):
        path = 'extensions/carla/one.mojo'
        first = edge(path, self.BEFORE, self.MIDDLE, self.tests)
        last = edge(path, self.MIDDLE, self.AFTER, self.tests)
        self.write(path, self.AFTER)
        for sequence in ([first, {**last, 'before_token_sha256': '0' * 64}], [last, first]):
            with self.subTest(sequence=sequence):
                self.use(sequence)
                with self.assertRaises(ValueError): ledger.verify(self.root)

    def test_stale_truncated_ledger_and_forged_historical_record_reject(self):
        path = 'extensions/carla/one.mojo'
        self.use([edge(path, self.BEFORE, self.MIDDLE, self.tests)])
        self.write(path, self.AFTER)
        with self.assertRaises(ValueError): ledger.verify(self.root)
        self.write(path, self.MIDDLE)
        record = self.root/ledger.RECORDS[0][0]
        record.write_bytes(record.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'historical consumer record changed'):
            ledger.verify(self.root)

    def test_consumer_and_test_symlinks_are_not_authority(self):
        path = 'extensions/carla/one.mojo'
        self.use([edge(path, self.BEFORE, self.AFTER, self.tests)])
        self.write(path, self.AFTER)
        for name in (path, 'tests/test_one.mojo'):
            target = self.root/name
            raw = target.read_bytes()
            other = target.with_suffix('.actual'); other.write_bytes(raw)
            target.unlink(); target.symlink_to(other)
            with self.subTest(name=name), self.assertRaises(ValueError): ledger.verify(self.root)
            target.unlink(); target.write_bytes(raw)


class LedgerJoinDiagnostics(LedgerFixture):
    def setUp(self):
        super().setUp()
        self.path = 'extensions/carla/one.mojo'
        self.first = edge(self.path, self.BEFORE, self.MIDDLE, self.tests)
        self.last = edge(self.path, self.MIDDLE, self.AFTER, self.tests)
        self.known = {key: self.first[key] for key in ledger.ENDPOINT_KEYS}
        self.known['kind'] = 'earlier'
        self.use([self.first, self.last])
        self.write(self.path, self.AFTER)

    def join(self, route, known):
        if route == 'endpoint':
            return ledger.endpoint(self.root, self.path, known)
        return ledger.extend({self.path: known}, self.root)[self.path]

    def test_each_missing_digest_has_a_contract_diagnostic_in_both_routes(self):
        for route in ('endpoint', 'extend'):
            for key in ledger.ENDPOINT_KEYS:
                known = {name: value for name, value in self.known.items() if name != key}
                with self.subTest(route=route, key=key), self.assertRaises(ValueError) as caught:
                    self.join(route, known)
                self.assertEqual(str(caught.exception),
                    'reviewed consumer successor ledger: '
                    'known successor is missing required digest key ' + repr(key) + ': ' + self.path)
                self.assertIs(type(caught.exception.__cause__), KeyError)
                self.assertEqual(caught.exception.__cause__.args, (key,))

    def test_complete_mapping_joins_keep_original_access_order_and_metadata(self):
        from collections.abc import Mapping
        class Descriptor(Mapping):
            def __init__(self, values):
                self.values, self.reads = values, []
            def __getitem__(self, key):
                self.reads.append(key)
                return self.values[key]
            def __iter__(self): return iter(self.values)
            def __len__(self): return len(self.values)
            def __contains__(self, key):
                raise AssertionError('joining must not add membership callbacks')
        cases = (('overlap', [self.first, self.last],
                  ['after_sha256', *ledger.ENDPOINT_KEYS]),
                 ('suffix', [self.last],
                  ['after_sha256', 'after_token_sha256', 'before_sha256']))
        for kind, edges, reads in cases:
            self.use(edges)
            for route in ('endpoint', 'extend'):
                known = Descriptor(dict(self.known))
                with self.subTest(kind=kind, route=route):
                    joined = self.join(route, known)
                    self.assertEqual(known.reads, reads + list(self.known))
                    self.assertEqual(joined, {**self.known,
                        'after_sha256': self.last['after_sha256'],
                        'after_token_sha256': self.last['after_token_sha256']})
                    self.assertEqual(known.values, self.known)

    def test_suffix_keeps_original_overlap_short_circuit(self):
        self.use([self.last])
        known = {key: value for key, value in self.known.items()
                 if key != 'before_token_sha256'}
        for route in ('endpoint', 'extend'):
            with self.subTest(route=route):
                joined = self.join(route, known)
                self.assertNotIn('before_token_sha256', joined)
                self.assertEqual(joined['after_sha256'], self.last['after_sha256'])
                self.assertEqual(joined['after_token_sha256'], self.last['after_token_sha256'])
                self.assertEqual(known['after_sha256'], self.first['after_sha256'])

    def test_no_chain_keeps_the_original_descriptor_without_join_validation(self):
        self.path = 'extensions/carla/two.mojo'
        known = {'kind': 'untouched'}
        for route in ('endpoint', 'extend'):
            with self.subTest(route=route):
                self.assertIs(self.join(route, known), known)

    def test_ledger_validation_still_precedes_missing_endpoint_diagnostics(self):
        self.write(ledger.LEDGER, (self.root/ledger.LEDGER).read_bytes() + b' ')
        for route in ('endpoint', 'extend'):
            with self.subTest(route=route), self.assertRaisesRegex(ValueError, 'unreviewed ledger'):
                self.join(route, {})


class RecordIntegrationTests(unittest.TestCase):
    """Both records consult the real ledger, as they consult earlier edges."""

    def setUp(self):
        import _full_audit_test_fixtures as fixtures
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)
        self.before = (self.root/CONSUMER).read_bytes()
        self.after = self.before + b'\n# A reviewed consumer edge.\n'
        self.tests = {BOUND_TEST: sha((self.root/BOUND_TEST).read_bytes())}

    def served(self, edges, live):
        content = ledger_bytes(edges)
        from contextlib import contextmanager
        @contextmanager
        def pin():
            with patch.object(ledger, 'LEDGER_SHA256', sha(content)), \
                    patch.object(audit, 'CONSUMER_LEDGER_SHA256', sha(content)):
                yield
        def files():
            return physical(self.root, {ledger.LEDGER: content, CONSUMER: live})
        return pin, files

    def test_the_real_ledger_changes_neither_record(self):
        self.assertEqual(set(ledger.verify(self.root)), set(reuse.MODULES))
        border.verify(self.root)
        winner.verify(self.root)

    def test_a_reviewed_edge_extends_both_records(self):
        pin, files = self.served([edge(CONSUMER, self.before, self.after, self.tests)],
                                 self.after)
        with pin(), files():
            border.verify(self.root)
            self.assertGreaterEqual(winner.verify(self.root)['reviewed_cleanup_successors'], 1)

    def test_a_chain_of_two_edges_extends_both_records(self):
        middle = self.before + b'\n# First.\n'
        pin, files = self.served([edge(CONSUMER, self.before, middle, self.tests),
                                  edge(CONSUMER, middle, self.after, self.tests)], self.after)
        with pin(), files():
            border.verify(self.root)
            winner.verify(self.root)

    def test_both_records_refuse_an_edge_that_skips_their_pin(self):
        other = self.before + b'\n# Not the pinned source.\n'
        pin, files = self.served([edge(CONSUMER, other, self.after, self.tests)], self.after)
        for record in (border, winner):
            with self.subTest(record=record.__name__), pin(), files():
                with self.assertRaisesRegex(ValueError, 'extend the record|historical canonical'):
                    record.verify(self.root)

    def test_both_records_refuse_an_unreviewed_consumer_change(self):
        pin, files = self.served([edge(CONSUMER, self.before, self.after, self.tests)],
                                 self.after + b'\n# Unreviewed.\n')
        for record in (border, winner):
            with self.subTest(record=record.__name__), pin(), files():
                with self.assertRaisesRegex(ValueError, 'not the last reviewed edge'):
                    record.verify(self.root)


class ExistingSuccessorIntegrationTests(unittest.TestCase):
    setUp = RecordIntegrationTests.setUp

    def test_real_seed_is_exact_existing_reuse_edge(self):
        first = ledger.read_edges(self.root)
        historical = json.loads((self.root/reuse.MIGRATION).read_bytes())
        self.assertEqual(len(first), 1)
        self.assertEqual(first[0]['issue'], 306)
        self.assertEqual(first[0]['path'], reuse.MODULES[0])
        self.assertEqual({key: first[0][key] for key in ledger.ENDPOINT_KEYS},
                         historical['edges'][reuse.MODULES[0]])
        self.assertEqual(first[0]['correctness_tests'], historical['correctness_tests'])
        for consumer in (border, winner):
            with self.subTest(consumer=consumer.__name__): consumer.verify(self.root)

    def test_boundary_and_reuse_later_edges_reach_both_real_roots(self):
        for module in (boundary, reuse):
            path = module.MODULES[0]
            before = (self.root/path).read_bytes()
            after = before + b'\n# Reviewed later consumer endpoint.\n'
            sequence = ledger.read_edges(self.root) + [edge(path, before, after, self.tests)]
            content = ledger_bytes(sequence)
            from contextlib import ExitStack
            with self.subTest(module=module.__name__), ExitStack() as stack:
                stack.enter_context(patch.object(ledger, 'LEDGER_SHA256', sha(content)))
                stack.enter_context(patch.object(audit, 'CONSUMER_LEDGER_SHA256', sha(content)))
                stack.enter_context(physical(self.root, {ledger.LEDGER: content, path: after}))
                descriptors = module.verify(self.root)
                original = json.loads((self.root/module.MIGRATION).read_bytes())['edges'][path]
                self.assertEqual(descriptors[path]['after_sha256'], original['after_sha256'])
                for consumer in (border, winner): consumer.verify(self.root)

    def test_historical_and_latest_test_obligations_both_remain_live(self):
        path = reuse.MODULES[0]
        before = (self.root/path).read_bytes(); after = before + b'\n# Reviewed successor.\n'
        sequence = ledger.read_edges(self.root) + [edge(path, before, after, self.tests)]
        content = ledger_bytes(sequence)
        for name in (reuse.TESTS[0], BOUND_TEST):
            from contextlib import ExitStack
            with self.subTest(test=name), ExitStack() as stack:
                stack.enter_context(patch.object(ledger, 'LEDGER_SHA256', sha(content)))
                stack.enter_context(patch.object(audit, 'CONSUMER_LEDGER_SHA256', sha(content)))
                stack.enter_context(physical(self.root, {ledger.LEDGER: content, path: after,
                    name: (self.root/name).read_bytes() + b'\n# Unreviewed test.\n'}))
                for consumer in (border, winner):
                    with self.assertRaises(ValueError): consumer.verify(self.root)

    def test_generic_edge_cannot_override_independent_proof_source(self):
        path = 'extensions/carla/curve_objective_model.mojo'
        before = (self.root/path).read_bytes(); after = before + b'\n# Unreviewed proof input.\n'
        sequence = ledger.read_edges(self.root) + [edge(path, before, after, self.tests)]
        content = ledger_bytes(sequence)
        from contextlib import ExitStack
        with ExitStack() as stack:
            stack.enter_context(patch.object(ledger, 'LEDGER_SHA256', sha(content)))
            stack.enter_context(patch.object(audit, 'CONSUMER_LEDGER_SHA256', sha(content)))
            stack.enter_context(physical(self.root, {ledger.LEDGER: content, path: after}))
            for consumer in (border, winner):
                with self.assertRaises(ValueError): consumer.verify(self.root)


class LedgerCheckerIdentityTests(unittest.TestCase):
    def test_live_function_code_swap_is_not_a_verified_ledger(self):
        old = ledger._join.__code__
        def forged(known, chain): return known
        try:
            ledger._join.__code__ = forged.__code__
            with self.assertRaisesRegex(ValueError, 'executing function changed'):
                audit.executing_checker_bindings()
        finally:
            ledger._join.__code__ = old
        self.assertIn('tools/carla_lane_oracle/consumer_successor_ledger.py',
                      audit.executing_checker_bindings())


class LedgerOperationControls(unittest.TestCase):
    """Use real public owners and original reads, never a served PASS."""
    from test_invariant_operation_inputs import BoundedOwnerCurrentControls as _owners
    setUp = _owners.setUp
    audit = _owners.audit
    assert_closed = _owners.assert_closed

    def test_after_admission_read_failures_remain_sticky_after_restore(self):
        for name in (ledger.LEDGER, reuse.MODULES[0], reuse.TESTS[0]):
            caught = []
            def consume(operation):
                original = (self.root/name).read_bytes()
                with patched(self.root, {name: original + b' '}):
                    with self.assertRaises(ValueError):
                        ledger.verify(self.root, _operation=operation)
                caught.append(operation)
                self.assertTrue(operation._failed)
                with self.assertRaises(ValueError):
                    ledger.verify(self.root, _operation=operation)
            with self.subTest(path=name), self.audit(callback=consume) as events:
                with self.assertRaises(ValueError): winner.verify(self.root)
            self.assertEqual(caught, events['admissions'])
            self.assert_closed(caught[0])

    def test_malformed_join_is_sticky_even_when_the_caller_catches_it(self):
        def consume(operation):
            descriptor = json.loads((self.root/reuse.MIGRATION).read_bytes())['edges'][reuse.MODULES[0]]
            descriptor['before_token_sha256'] = '0' * 64
            with self.assertRaises(ValueError):
                ledger.endpoint(self.root, reuse.MODULES[0], descriptor, _operation=operation)
            self.assertTrue(operation._failed)
        with self.audit(callback=consume) as events:
            with self.assertRaises(ValueError): winner.verify(self.root)
        self.assertEqual(len(events['admissions']), 1)
        self.assert_closed(events['admissions'][0])

    def test_caught_missing_digest_refusal_leaves_the_real_owner_failed_and_closed(self):
        def consume(operation):
            path = reuse.MODULES[0]
            descriptor = json.loads((self.root/reuse.MIGRATION).read_bytes())['edges'][path]
            missing = {key: value for key, value in descriptor.items()
                       if key != 'after_token_sha256'}
            with self.assertRaisesRegex(ValueError, "missing required digest key 'after_token_sha256'") as caught:
                ledger.endpoint(self.root, path, missing, _operation=operation)
            self.assertIs(type(caught.exception), audit._OperationCoherenceError)
            self.assertIs(type(caught.exception.__cause__), ValueError)
            self.assertIs(type(caught.exception.__cause__.__cause__), KeyError)
            self.assertTrue(operation._failed)
            self.assertIn('after_token_sha256', operation._failure_reason)
            # Restoring the descriptor cannot clear a caught refusal.
            with self.assertRaises(ValueError):
                ledger.endpoint(self.root, path, descriptor, _operation=operation)
        with self.audit(callback=consume) as events:
            with self.assertRaises(ValueError): winner.verify(self.root)
        self.assertEqual(len(events['admissions']), 1)
        self.assertEqual(events['callbacks'], events['admissions'])
        self.assertTrue(events['admissions'][0]._failed)
        self.assert_closed(events['admissions'][0])

    def test_new_reads_bind_to_the_public_owner_before_admission(self):
        import sys
        import _full_audit_test_fixtures as fixtures
        # The pre-admission read order is a claim about the historical graph.
        self.root = fixtures.copy_historical_boundary_root(self, _CURRENT_SOURCE_ROOT)
        for name in (ledger.LEDGER, reuse.MODULES[0], reuse.TESTS[0]):
            original = (self.root/name).read_bytes()
            read = Path.read_bytes
            operations = []
            def changed(path, *args, **kwargs):
                frame = sys._getframe(1)
                if (path == self.root/name and frame.f_globals is vars(ledger)
                        and frame.f_code is ledger._read.__code__):
                    operation = frame.f_locals['_operation']
                    self.assertIs(type(operation), audit._InvariantInputs)
                    self.assertEqual(operation._state, 'pending')
                    operations.append(operation)
                    return original + b' '
                return read(path, *args, **kwargs)
            with self.subTest(path=name), patch.object(Path, 'read_bytes', changed):
                with self.assertRaises(ValueError): border.verify(self.root)
            self.assertEqual(len(operations), 1)
            self.assertTrue(operations[0]._failed)
            self.assert_closed(operations[0])

    def test_final_checkpoint_catches_change_after_last_ledger_consumer(self):
        from functools import wraps
        target = self.root/ledger.LEDGER
        original = target.read_bytes()
        checkpoint = audit._CacheInputs.checkpoint
        operations = []
        @wraps(checkpoint)
        def at_finish(view, owner, root):
            self.assertEqual(view._state, 'active')
            self.assertEqual(view._kind, 'winner')
            operations.append(view)
            # No consumer is invoked here: only the original final checkpoint
            # can reject this mutation before the public result escapes.
            target.write_bytes(original + b' ')
            return checkpoint(view, owner, root)
        try:
            with patch.object(audit._CacheInputs, 'checkpoint', at_finish):
                with self.assertRaisesRegex(ValueError, 'owned input changed'):
                    winner.verify(self.root)
        finally:
            target.write_bytes(original)
        self.assertEqual(len(operations), 1)
        self.assertTrue(operations[0]._failed)
        self.assert_closed(operations[0])

    def test_late_ledger_mutation_and_stale_owner_cannot_escape(self):
        target = self.root/ledger.LEDGER
        original = target.read_bytes()
        def consume(operation): target.write_bytes(original + b' ')
        try:
            with self.audit(callback=consume) as events:
                with self.assertRaises(ValueError): winner.verify(self.root)
        finally:
            target.write_bytes(original)
        operation = events['admissions'][0]
        self.assert_closed(operation)
        with self.assertRaises(ValueError): ledger.verify(self.root, _operation=operation)


if __name__ == '__main__':
    unittest.main()
