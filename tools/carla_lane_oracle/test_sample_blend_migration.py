# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact, standalone checks for the seven unchanged tight-rounding rows.

No Mojo, production arithmetic, third-party package, or native export is
required. Frozen existing arithmetic proofs are also run separately.
"""
import ast
from fractions import Fraction as F
from pathlib import Path
import re
import unittest

try:
    from blend_fixture_reference import (
        ROWS, derive, scalar_graphs, coupled_error, bits, rn,
    )
except ModuleNotFoundError:
    from tools.carla_lane_oracle.blend_fixture_reference import (
        ROWS, derive, scalar_graphs, coupled_error, bits, rn,
    )

EXPECTED = [0x3d18500000000005, 0x4000f0de4df82003, 0x3cd0000000000003,
            0x3ce2000000000004, 0x3cdc000000000005,
            0x7c98e679c2f5e457, 0x000000000000000b]
ORIGINAL = EXPECTED[:]
ORIGINAL[4] = 0x3cdc000000000007
COUPLED = EXPECTED[:]
COUPLED[3] = 0x3ce8000000000005
COUPLED[5:] = [0x7ff0000000000000]*2
GRAPH_WORDS = [0x4059300000000000, 0x4341c37937e08001, 0xc014666666666666,
               0x401c000000000000, 0xc01c000000000000, 0,
               0x8002e055c9a3f6ba]

class BlendMigrationTests(unittest.TestCase):
    def test_exact_bound_recipe_and_minimum_choice(self):
        rows=derive()
        self.assertEqual(len(rows),7)
        self.assertEqual([int(x['original_error_word'],16) for x in rows],ORIGINAL)
        self.assertEqual([int(x['coupled_error_word'],16) for x in rows],COUPLED)
        self.assertEqual([int(x['expected_error_word'],16) for x in rows],EXPECTED)
        self.assertEqual([x['row'] for x in rows if x['changed_error']],[4])
        self.assertEqual(rows[4]['error_word_decrease'],2)
        self.assertGreater(COUPLED[3],ORIGINAL[3])
        self.assertEqual([x['supported'] for x in rows],[True]*5+[False]*2)

    def test_three_graphs_against_exact_real_expression(self):
        for index,((r,a,b),record) in enumerate(zip(ROWS,derive())):
            exact=F(r)*F(a)+(1-F(r))*F(b)
            self.assertEqual(exact,F(b)+F(r)*(F(a)-F(b)))
            outputs=scalar_graphs(r,a,b)
            self.assertEqual([bits(x) for x in outputs],[GRAPH_WORDS[index]]*3)
            maximum=max(abs(F(x)-exact) for x in outputs)
            self.assertEqual(maximum,F(record['required_error_fraction']))
            self.assertLessEqual(maximum,F(record['required_error_up']))
            self.assertLessEqual(maximum,F(record['expected_error']))
            if index>=5:
                self.assertEqual(record['expected_error_word'],record['original_error_word'])

    def test_each_coupled_component_covers_the_actual_scalar_graph(self):
        # Verify the algebra and every individual operation error. This is
        # independent of the final padded error-word reconstruction.
        for r,a,b in ROWS[:5]:
            allowance,parts=coupled_error(r,a,b)
            complement=rn(1-F(r));p=rn(F(r)*F(a));q=rn(F(complement)*F(b))
            ec=F(complement)-(1-F(r))
            ep=F(p)-F(r)*F(a);eq=F(q)-F(complement)*F(b)
            self.assertLessEqual(abs(ec),F(parts['complement_error']))
            self.assertLessEqual(abs(ep),F(parts['first_product_error']))
            self.assertLessEqual(abs(eq),F(parts['second_product_error']))
            for graph,output in enumerate(scalar_graphs(r,a,b)):
                exact=F(r)*F(a)+(1-F(r))*F(b)
                if graph==0:
                    pre=F(p)+F(q);kept=ep+eq
                elif graph==1:
                    pre=F(r)*F(a)+F(q);kept=eq
                else:
                    pre=F(complement)*F(b)+F(p);kept=ep
                ez=F(output)-pre
                self.assertEqual(F(output)-exact,F(b)*ec+kept+ez)
                self.assertLessEqual(abs(ez),F(parts['final_error']))
                self.assertLessEqual(abs(F(output)-exact),F(allowance))

    def test_native_word_arrays_are_generated_from_the_same_reference(self):
        path=Path(__file__).resolve().parents[2]/'tests/test_carla_tight_rounding.mojo'
        source=path.read_text()
        for name,expected in [('coupled_error_words',COUPLED),
                              ('expected_error_words',EXPECTED),
                              ('required_error_words',[int(x['required_error_word'],16) for x in derive()]),
                              ('graph_words',GRAPH_WORDS)]:
            body=re.search(r'var '+name+r': List\[UInt64\] = \[(.*?)\n    \]',source,re.S).group(1)
            words=[int(x,16) for x in re.findall(r'UInt64\((0x[0-9A-Fa-f]+)\)',body)]
            self.assertEqual(words,expected)


    def test_all_native_fixture_inputs_match_the_reference(self):
        path=Path(__file__).resolve().parents[2]/'tests/test_carla_tight_rounding.mojo'
        source=path.read_text()
        body=re.search(
            r'var samples: List\[Array\[Float64, 3\]\] = \[(.*?)\n    \]',
            source,re.S).group(1)
        native=ast.literal_eval('['+body+']')
        self.assertEqual(len(native),7)
        self.assertEqual([[bits(x) for x in row] for row in native],
                         [[bits(x) for x in row] for row in ROWS])

if __name__=='__main__':
    unittest.main()
