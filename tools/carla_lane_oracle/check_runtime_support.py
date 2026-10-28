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


_RUNTIME_INDENTED = None


def _runtime_result(root, groups, successors, heading, optional, sum2):
    """Return the runtime-support result and keep its indented text."""
    global _RUNTIME_INDENTED
    import ast
    import os
    import subprocess
    import tempfile
    payload = json.dumps({
        'root': root, 'groups': groups, 'successors': successors,
        'heading': heading, 'optional': optional, 'sum2': sum2,
    }, separators=(',', ':'))
    repo = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(repo / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='runtime-support-result-') as directory:
        path = Path(directory) / 'result.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(repo / 'tools' / 'tool.sh'), mojo,
             'carla_runtime_support_result', '--indented', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['key']
        if message.startswith(prefix):
            raise KeyError(ast.literal_eval(message[len(prefix):])) from None
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    _RUNTIME_INDENTED = parsed['indented']
    return parsed['result']


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
        return _runtime_result(
            str(root.resolve()), groups, current_edges, heading, optional, sum2)
    finally:
        if owns:
            _operation.close()


_CLI_FAILURES = None


def _cli_failures():
    """Return the checker failure prefixes."""
    global _CLI_FAILURES
    if _CLI_FAILURES is not None:
        return _CLI_FAILURES
    if __package__:
        from .ideal_projection import cli_failure_prefixes
    else:
        from ideal_projection import cli_failure_prefixes
    _CLI_FAILURES = cli_failure_prefixes()
    return _CLI_FAILURES


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo-root', type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        verify(args.repo_root.resolve())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(_cli_failures()['runtime'], error)
        return 1
    print(_RUNTIME_INDENTED, end='')
    return 0


if __name__ == '__main__':
    # The CLI uses the canonical registered module, so its public verifier
    # can own one physical capture just like an imported invocation.
    from check_runtime_support import main as _owned_main
    raise SystemExit(_owned_main())
