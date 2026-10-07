# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Narrow fresh/proof SPIRAL heading graph correspondence.

Complete module tokens and stored-helper dependencies are checked separately.
This projection expands only the fresh local k0 constant and specializes its
Expression name to the full Jet alias. It never projects ideal u or eligibility
into a scalar-heading proof and does not claim arbitrary error equivalence.
"""
import ast
import copy
from pathlib import Path

from check_sampled_values import dump, function, syntax_tree, unique_function

CONSUMERS = {
    'spiral_domain_proof.mojo': '_spiral_proof_branch',
    'spiral_moment_proof.mojo': '_try_spiral_moment_expansion',
    'spiral_moment_table.mojo': '_try_spiral_moment_expansion',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def declaration(text, name):
    # The full source/token gate binds actual declaration identity, decorators
    # and everything outside this selected complete declaration as well.
    return unique_function(syntax_tree(function(text, name)), name)


def assigned(node, name):
    matches = [item.value for item in node.body if isinstance(item, ast.Assign)
               and len(item.targets) == 1 and isinstance(item.targets[0], ast.Name)
               and item.targets[0].id == name]
    require(len(matches) == 1, 'heading correspondence: missing/ambiguous assignment ' + name)
    return copy.deepcopy(matches[0])


class Specialize(ast.NodeTransformer):
    def __init__(self, k0=None):
        self.k0 = k0

    def visit_Name(self, node):
        if node.id == 'Expression':
            return ast.Name(id='_Jet', ctx=node.ctx)
        if node.id == 'k0' and self.k0 is not None:
            return copy.deepcopy(self.k0)
        return node


def expression(text):
    return ast.parse(text, mode='eval').body


def verify(root):
    path = root/'extensions/carla'
    fresh = declaration((path/'curve_bounds.mojo').read_text(), '_spiral_expression')
    k0 = Specialize().visit(assigned(fresh, 'k0'))
    expected_k0 = expression('_Jet.constant(geometry.curvature_start)')
    require(dump(k0) == dump(expected_k0), 'heading correspondence: fresh k0 changed')
    rate = Specialize().visit(assigned(fresh, 'rate'))
    expected_rate = expression('_Jet.constant((geometry.curvature_end - geometry.curvature_start) / geometry.length)')
    require(dump(rate) == dump(expected_rate), 'heading correspondence: fresh stored rate changed')
    heading = Specialize(k0).visit(assigned(fresh, 'heading'))
    expected_heading = expression('_Jet.constant(geometry.heading) + d * (_Jet.constant(geometry.curvature_start) + _stored_half(rate) * d)')
    require(dump(heading) == dump(expected_heading), 'heading correspondence: fresh half heading changed')
    ideal_u = expression('_Jet.constant(0.5) * rate * d * d')
    for filename, name in CONSUMERS.items():
        consumer = declaration((path/filename).read_text(), name)
        require(dump(assigned(consumer, 'rate')) == dump(rate),
                'heading correspondence: stored rate differs: ' + filename)
        require(dump(assigned(consumer, 'heading')) == dump(heading),
                'heading correspondence: scalar heading differs: ' + filename)
        require(dump(assigned(consumer, 'u')) == dump(ideal_u),
                'heading correspondence: ideal u graph changed: ' + filename)
        calls = [node for node in ast.walk(consumer) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Name) and node.func.id == '_stored_half']
        require(len(calls) == 1 and dump(calls[0]) == dump(expression('_stored_half(rate)')),
                'heading correspondence: unexpected helper consumer: ' + filename)
    eligibility = declaration((path/'spiral_moment_proof.mojo').read_text(),
                              '_all_spiral_nodes_quadrant_zero')
    expected_theta = expression('_Jet.constant(geometry.heading) + t * (_Jet.constant(geometry.curvature_start) + _Jet.constant(0.5) * rate * t)')
    require(dump(assigned(eligibility, 'theta')) == dump(expected_theta),
            'heading correspondence: original eligibility phase graph changed')
    require(not any(isinstance(node, ast.Name) and node.id == '_stored_half'
                    for node in ast.walk(eligibility)),
            'heading correspondence: stored half introduced into eligibility')
    return {'heading_consumers': len(CONSUMERS),
            'fresh_rate_and_heading_match': True,
            'ideal_u_and_original_quadrant_phase_unchanged': True,
            'scope': 'Exact fresh/full-Jet heading source graph after k0 expansion; '
                     'no change to ideal u, quadrant eligibility or scalar evaluator'}
