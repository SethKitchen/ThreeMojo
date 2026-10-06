# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Modest reproducible duplicate-lane work/storage counts, with wall time.

Run the executable under /usr/bin/time -v for process peak RSS. Counts are
logical entries and operations, not allocator-capacity or byte claims.
"""

from extensions.carla.map_search import MapQueryBudget, _MapQueryWork
from extensions.carla.road_info import LANE_DRIVING
from math.vector3 import Vector3
from std.time import perf_counter_ns
from tests.test_carla_map_budget import _map


def main() raises:
    for count in [1, 16, 20, 64, 256]:
        var started = perf_counter_ns()
        var map = _map(count)
        var built = perf_counter_ns()
        var work = _MapQueryWork(MapQueryBudget())
        var result = (
            map._closest_lane_certificate_with_work(
                Vector3(2, 0, 0), LANE_DRIVING, work
            )
            .value()
            .copy()
        )
        var done = perf_counter_ns()
        print(
            "roads",
            count,
            "segments",
            map.segment_count(),
            "records",
            map._construction_work.records,
            "build_steps",
            map._construction_work.steps,
            "build_terms",
            map._construction_work.terms,
            "candidates",
            work.candidates,
            "query_steps",
            work.steps,
            "query_nodes",
            work.nodes,
            "query_terms",
            work.terms,
            "index_pops",
            work.index_pops,
            "peak_queue",
            work.peak_queue_entries,
            "winner",
            result[0].road_id.value,
            "build_ns",
            built - started,
            "query_ns",
            done - built,
        )
