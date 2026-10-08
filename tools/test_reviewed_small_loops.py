# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact source and caller premises for two small loop proposals."""
from pathlib import Path
import tempfile
import unittest
import coverage_loop_proofs as loops

ROOT = Path(__file__).resolve().parents[1]
SPEED = 'extensions/carla/speed_limits'
TREE = 'extensions/carla/rtree'
RENDER = 'renderers/renderer'

class SmallLoopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for module in (SPEED,TREE):
            for name in loops.REVIEWED_LOOP_RULES[module][0]:
                p=self.root/name;p.parent.mkdir(parents=True,exist_ok=True)
                p.write_bytes((ROOT/name).read_bytes())

    def test_exact_partial_outcomes_keep_true(self):
        for module,line,kind,maximum in [(SPEED,154,'reviewed-nonempty-iterator',None),(TREE,666,'reviewed-nonempty-iterator',16)]:
            proofs=loops.reviewed_nonempty_loops(self.root,module)
            self.assertEqual(set(proofs),{line})
            self.assertEqual((proofs[line]['kind'],proofs[line]['required'],proofs[line]['impossible'],proofs[line]['cardinality'],proofs[line]['maximum_cardinality']),(kind,'T','F',1,maximum))

    def test_exact_source_premise_mutations_revoke(self):
        cases=[
            (SPEED,SPEED+'.mojo','if number.byte_length() == 0:','if number.byte_length() < 0:'),
            (SPEED,SPEED+'.mojo','for byte in number.as_bytes():','for byte in String().as_bytes():'),
            (SPEED,SPEED+'.mojo','var number = String(text.strip())','var number = String()'),
            (SPEED,SPEED+'.mojo','if not _speed_decimal_syntax(number):','if False:'),
            (SPEED,SPEED+'.mojo','if byte >= 48 and byte <= 57:','if byte >= 48:'),
            (SPEED,SPEED+'.mojo','if byte == 101 or byte == 69:','if byte == 101:'),
            (SPEED,SPEED+'.mojo','if byte >= 49:','if byte >= 48:'),
            (TREE,TREE+'.mojo','if self.size() > 0:','if self.size() >= 0:'),
            (TREE,TREE+'.mojo','group_a.append(seed_a)','pass'),
            (TREE,TREE+'.mojo','group_b.append(seed_b)','pass'),
            (TREE,TREE+'.mojo','children.append(self.root)','pass'),
            (TREE,TREE+'.mojo','children.append(split)','pass'),
            (TREE,TREE+'.mojo','self.nodes[node].children.append(entry)','pass'),
            (TREE,'extensions/carla/map.mojo','var frontier = self._tree._nearest_begin(location, work)','var frontier = _Heap()'),
            (TREE,'tests/_published_seed_selector.mojo','var frontier = map._tree._nearest_begin(location, work)','var frontier = _Heap()'),
        ]
        for module,name,before,after in cases:
            p=self.root/name;original=p.read_text();self.assertIn(before,original)
            with self.subTest(module=module,premise=before):
                p.write_text(original.replace(before,after))
                self.assertEqual(loops.reviewed_nonempty_loops(self.root,module),{})
                p.write_text(original)

    def test_unreviewed_frontier_caller_revokes_tree_only(self):
        p=self.root/'new_caller.mojo';p.write_text('def call(tree, heap, work):\n    return tree._nearest_next(point, filter, heap, work)\n')
        self.assertEqual(loops.reviewed_nonempty_loops(self.root,TREE),{})
        self.assertTrue(loops.reviewed_nonempty_loops(self.root,SPEED))

    def test_missing_dependency_or_range_shadow_revokes(self):
        for module in (SPEED,TREE):
            for name in loops.REVIEWED_LOOP_RULES[module][0]:
                p=self.root/name;original=p.read_bytes();p.unlink()
                self.assertEqual(loops.reviewed_nonempty_loops(self.root,module),{})
                p.write_bytes(original)

if __name__=='__main__':unittest.main()
