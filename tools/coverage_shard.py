# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Schedule coverage captures by measured wall time, longest first.

CPU sharding still uses import size. Coverage adds expensive probe output,
so its measured compile-and-run costs need a separate scheduling profile.
The profile only controls order and placement: every input suite is kept.
"""

import json
import math
from pathlib import Path
import statistics
import sys

import affected
import shard


PROFILE = Path(__file__).with_name('coverage_costs.json')


def load_costs(path):
    """Read positive finite seconds, rejecting malformed scheduling data."""
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'duplicate coverage profile key: {key}')
            result[key] = value
        return result
    data = json.loads(Path(path).read_text(), object_pairs_hook=unique_object)
    costs = data['seconds']
    if not isinstance(costs, dict) or not costs:
        raise ValueError('coverage costs must be a nonempty object')
    for suite, seconds in costs.items():
        if (not isinstance(suite, str) or not suite.startswith('tests/test_')
                or not suite.endswith('.mojo') or '/' in suite[6:]
                or isinstance(seconds, bool) or not isinstance(seconds, (int, float))
                or not math.isfinite(seconds) or seconds <= 0):
            raise ValueError(f'invalid coverage cost: {suite!r}: {seconds!r}')
    return costs


def schedule(suites, count, costs, source_weight):
    """Keep each suite once, with source-sized estimates for unseen suites."""
    if count < 1 or len(suites) != len(set(suites)):
        raise ValueError('expected a positive shard count and unique suites')
    # A median cost per imported byte avoids assigning an unseen suite zero
    # work. Only estimates change; missing profile entries never omit tests.
    ratios = [costs[suite] / max(1, source_weight(suite))
              for suite in suites if suite in costs]
    per_byte = statistics.median(ratios) if ratios else 1 / 10000
    def cost(suite):
        return costs[suite] if suite in costs else max(1, source_weight(suite) * per_byte)
    return shard.split(suites, count, cost)


def main(arguments):
    """Print one coverage group in descending estimated duration order."""
    if not arguments:
        print('usage: coverage_shard.py I/N SUITE...', file=sys.stderr)
        return 2
    index, _, count = arguments[0].partition('/')
    if not (index.isdigit() and count.isdigit()) or not (1 <= int(index) <= int(count)):
        print('coverage_shard.py: expected I/N with 1 <= I <= N', file=sys.stderr)
        return 2
    try:
        suites = [path.removeprefix('./') for path in arguments[1:]]
        costs = load_costs(PROFILE)
        known = set(affected.mojo_files())
        sizes = {path: (Path(affected.ROOT) / path).stat().st_size for path in known}
        cache = {}
        groups = schedule(suites, int(count), costs,
                          lambda suite: shard.weight(suite, known, sizes, cache))
        print(' '.join(groups[int(index) - 1]))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'coverage_shard.py: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
