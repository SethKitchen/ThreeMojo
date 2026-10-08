# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Operation-scoped input accounting for spatial map construction.

No validity result is cached across calls or after public record mutation.
Border records count as input storage; border geometry remains unsupported
until its independent evaluator and validation contract is implemented.
"""

from extensions.carla.map_search import _MapBuildWork
from extensions.carla.road import Road
from extensions.carla.road_info import InformationSet
from std.math import isfinite


def _count_information(info: InformationSet, mut work: _MapBuildWork) raises:
    # Separate checked additions avoid overflowing a total before its guard.
    work.record(len(info.geometries))
    work.record(len(info.elevations))
    work.record(len(info.lane_offsets))
    work.record(len(info.speeds))
    work.record(len(info.crosswalks))
    work.record(len(info.signals))
    work.record(len(info.widths))
    work.record(len(info.borders))
    work.record(len(info.heights))
    work.record(len(info.materials))
    work.record(len(info.visibilities))
    work.record(len(info.accesses))
    work.record(len(info.rules))
    work.record(len(info.marks))
    for record in info.geometries:
        work.step()
        ref geometry = record.geometry
        if (
            not isfinite(record.s)
            or not isfinite(geometry.length)
            or geometry.length <= 0.0
            or not geometry.kind.is_valid()
            or not isfinite(geometry.x)
            or not isfinite(geometry.y)
            or not isfinite(geometry.heading)
            or not isfinite(geometry.curvature_start)
            or not isfinite(geometry.curvature_end)
        ):
            raise Error("Spatial map geometry has an invalid finite domain")
        work.record(len(geometry.samples))
        work.step(len(geometry.samples))
        var previous = Float64(-1.0)
        for sample in geometry.samples:
            if (
                not isfinite(sample.s)
                or sample.s < 0.0
                or sample.s <= previous
                or not isfinite(sample.u)
                or not isfinite(sample.v)
                or not isfinite(sample.tu)
                or not isfinite(sample.tv)
            ):
                raise Error("Spatial map geometry has an invalid sample domain")
            previous = sample.s
    for record in info.crosswalks:
        work.step()
        work.record(len(record.points))
    for record in info.signals:
        work.step()
        work.record(len(record.validities))
    for record in info.marks:
        work.step()
        work.record(len(record.lines))


def _preflight_map_records(roads: List[Road], mut work: _MapBuildWork) raises:
    work.validate()
    work.record(len(roads))
    for road in roads:
        _preflight_road_records(road, work)


def _preflight_road_records(road: Road, mut work: _MapBuildWork) raises:
    work.step()
    if not isfinite(road.length) or road.length < 0.0:
        raise Error("Spatial map road has an invalid finite domain")
    work.record(len(road.nexts))
    work.record(len(road.prevs))
    _count_information(road.info, work)
    work.record(len(road.sections))
    for section in road.sections:
        work.step()
        if (
            not isfinite(section.s)
            or section.s < 0.0
            or section.s > road.length
        ):
            raise Error("Spatial map section has an invalid finite domain")
        work.record(len(section.lanes))
        for lane in section.lanes:
            work.step()
            work.record(len(lane.next_lanes))
            work.record(len(lane.prev_lanes))
            _count_information(lane.info, work)


def _reserve_lane_boundaries(
    road: Road, section: Int, mut work: _MapBuildWork
) raises:
    # Reserve every append/record scan before _lane_record_boundaries allocates.
    work.step(len(road.info.geometries))
    for record in road.info.geometries:
        work.step(len(record.geometry.samples))
    work.step(len(road.info.elevations))
    work.step(len(road.info.lane_offsets))
    work.step(len(road.sections[section].lanes))
    for lane in road.sections[section].lanes:
        work.step(len(lane.info.widths))


def _reserve_information_sort(
    info: InformationSet, mut work: _MapBuildWork
) raises:
    work.sort_work(len(info.geometries))
    work.sort_work(len(info.elevations))
    work.sort_work(len(info.lane_offsets))
    work.sort_work(len(info.speeds))
    work.sort_work(len(info.crosswalks))
    work.sort_work(len(info.signals))
    work.sort_work(len(info.widths))
    work.sort_work(len(info.borders))
    work.sort_work(len(info.heights))
    work.sort_work(len(info.materials))
    work.sort_work(len(info.visibilities))
    work.sort_work(len(info.accesses))
    work.sort_work(len(info.rules))
    work.sort_work(len(info.marks))


def _reserve_road_scan(
    road: Road, mut work: _MapBuildWork, section_passes: Int = 1
) raises:
    work.step_product(section_passes, len(road.sections))
    for section in road.sections:
        work.step(len(section.lanes))


def _reserve_lanes_at(road: Road, mut work: _MapBuildWork) raises:
    # sections_at scans every section twice. lanes_at then scans/inserts
    # into a growing ordered list, not just one pass through input lanes.
    work.step_product(2, len(road.sections))
    var lanes = 0
    for section in road.sections:
        work.step(len(section.lanes))
        # The preceding checked charge bounds this cumulative sum too.
        lanes += len(section.lanes)
    work.sort_work(lanes)


def _reserve_lane_scalars(
    road: Road, section: Int, mut work: _MapBuildWork, evaluations: Int = 1
) raises:
    # A scalar center builds a lane-order list and walks its widths. A pose
    # evaluates that accumulation twice. Admit both scans before allocation.
    work.step_product(evaluations, len(road.sections[section].lanes))
    work.step_product(evaluations, len(road.sections[section].lanes))


def _reserve_straightness(
    road: Road, section: Int, mut work: _MapBuildWork
) raises:
    work.step(len(road.sections))
    work.step(len(road.info.elevations))
    work.step(len(road.info.lane_offsets))
    work.step(len(road.sections[section].lanes))
    for lane in road.sections[section].lanes:
        work.step(len(lane.info.widths))
