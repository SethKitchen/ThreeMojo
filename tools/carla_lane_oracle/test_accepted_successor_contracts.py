# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Current-graph validation and explicit reversible successor placements."""
from pathlib import Path
import hashlib
import json
import unittest
from unittest.mock import patch
import accepted_successor_contracts as accepted
import coverage_followup_contracts as prior

ROOT = Path(__file__).resolve().parents[2]


class AcceptedSuccessorTests(unittest.TestCase):
    def test_current_graph_and_exact_scoped_pin_reconstruction(self):
        record = accepted.verify(ROOT)
        self.assertEqual(len(record['sources']), 3)
        self.assertEqual(len(record['pin_files']['runtime-source-pins.json']['transitions']), 7)
        self.assertEqual(len(record['pin_files']['sum2-guard-pins.json']['transitions']), 4)
        previous = prior.read_record(ROOT)
        for name in record['pin_files']:
            payload = accepted.predecessor_pins(ROOT, name)
            self.assertEqual(hashlib.sha256(payload).hexdigest(), previous['pin_files'][name]['after_sha256'])
        self.assertEqual(record['rounded_line_edges'][0]['after'], record['rounded_line_edges'][1]['before'])

    def test_each_current_module_mutation_blocks_projection(self):
        read = Path.read_text
        for name in accepted.SOURCE_PATHS:
            target = ROOT/name
            changed = read(target) + '\nfrom unreviewed import range\n'
            with self.subTest(name=name), patch.object(Path, 'read_text', lambda p,*a,**k: changed if p==target else read(p,*a,**k)):
                with self.assertRaises(ValueError):
                    accepted.predecessor_text(ROOT, name)
                with self.assertRaises(ValueError):
                    accepted.predecessor_pins(ROOT, 'runtime-source-pins.json')

    def test_every_pin_placement_mutation_is_rejected(self):
        read = Path.read_bytes
        for name, record in accepted.read_record(ROOT)['pin_files'].items():
            target = ROOT/'tools/carla_lane_oracle'/name
            for change in record['transitions']:
                pins = json.loads(read(target));ref=pins
                for part in change['pointer'][:-1]:ref=ref[part]
                ref[change['pointer'][-1]]=change['before']
                payload=(json.dumps(pins,indent=2)+'\n').encode()
                with self.subTest(pointer=change['pointer']),patch.object(Path,'read_bytes',lambda p,*a,**k:payload if p==target else read(p,*a,**k)):
                    with self.assertRaises(ValueError):accepted.verify(ROOT)

    def test_each_record_mutation_is_rejected(self):
        read=Path.read_bytes
        for name in [accepted.MIGRATION,*('tools/carla_lane_oracle/'+x for x in accepted.COMPONENTS)]:
            target=ROOT/name;payload=read(target)+b' '
            with self.subTest(name=name),patch.object(Path,'read_bytes',lambda p,*a,**k:payload if p==target else read(p,*a,**k)):
                with self.assertRaises(ValueError):accepted.verify(ROOT)


if __name__ == '__main__':
    unittest.main()
