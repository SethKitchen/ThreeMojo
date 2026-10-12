#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Read-only eligibility, translated-proof and work-support source gates.

PASS means fixed reviewed dependency tokens match, not runtime correctness.
Coefficient-table reproduction is a different checker with a different scope.
"""
import argparse
import json
from pathlib import Path
from source_contracts import GROUP_PATHS, verify_group, lexical_memo_scope
import heading_correspondence
import sum2_contracts
import optional_runtime_contracts

ROOT = Path(__file__).resolve().parents[2]


@lexical_memo_scope()
def verify(root):
    import full_audit_cleanup_contracts as audit
    _operation, owns = audit._operation_enter(root, 'runtime')
    try:
        groups = {name: verify_group(root, name, _operation=_operation) for name in GROUP_PATHS}
        heading = heading_correspondence.verify(root, _operation=_operation)
        optional = optional_runtime_contracts.verify(root, _operation=_operation)
        sum2 = sum2_contracts.verify(root, _operation=_operation)
        current_edges = audit.typed_successor_edges(root, _operation=_operation)
        if owns:
            _operation.finish(root)
        return {'status': 'PASS', 'scope':
            'Current source-integrity and explicit typed/conditioned successors; '
            'old source comparisons retain historical provenance only. '
            'Native execution, performance and coverage are separate requirements',
            'repo_root': str(root.resolve()), 'groups': groups,
            'typed_boundary_successors': current_edges,
            'heading_correspondence': heading, 'optional_runtime': optional,
            'sum2_correspondence': sum2}
    finally:
        if owns:
            _operation.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo-root', type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        result = verify(args.repo_root.resolve())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print('FAIL:', error)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    # The CLI uses the canonical registered module, so its public verifier
    # can own one physical capture just like an imported invocation.
    from check_runtime_support import main as _owned_main
    raise SystemExit(_owned_main())
