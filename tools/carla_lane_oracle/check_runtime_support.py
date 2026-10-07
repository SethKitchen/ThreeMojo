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
from source_contracts import GROUP_PATHS, verify_group
import heading_correspondence
import sum2_contracts

ROOT = Path(__file__).resolve().parents[2]


def verify(root):
    groups = {name: verify_group(root, name) for name in GROUP_PATHS}
    heading = heading_correspondence.verify(root)
    return {'status': 'PASS', 'scope':
        'Reviewed source-integrity only; mathematical proof, native execution, '
        'cost, performance and coverage remain separate requirements',
        'repo_root': str(root.resolve()),
        'groups': groups, 'heading_correspondence': heading,
        'sum2_correspondence': sum2_contracts.verify(root)}


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
    raise SystemExit(main())
