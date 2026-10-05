#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reproduce corrected town orientation controls without Mojo outputs.

Read only the hand-authored OpenDRIVE fixture. Differentiate the line/arc/
clothoid equations and the documented CARLA sample interpolation model.
The spiral reference uses its analytic unit tangent rather than the port's
Gauss-Legendre implementation. The sample positions and derivative vectors
are independently reconstructed from their cubic definitions.

Run from the repository root with Python 3.9 or newer. No packages are needed.
"""

import bisect
import functools
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET


def coefficients(node, suffix=""):
    return tuple(float(node.get(key + suffix, "0")) for key in "abcd")


def polynomial(coeffs, x):
    a, b, c, d = coeffs
    return a + x * (b + x * (c + x * d))


def slope(coeffs, x):
    _, b, c, d = coeffs
    return b + x * (2 * c + x * 3 * d)


def active(nodes, at, key="s"):
    eligible = [node for node in nodes if float(node.get(key, "0")) <= at]
    return eligible[-1] if eligible else None


def record_value(nodes, at, key="s"):
    node = active(nodes, at, key)
    if node is None:
        return 0.0, 0.0
    local = at - float(node.get(key, "0"))
    c = coefficients(node)
    return polynomial(c, local), slope(c, local)


@functools.lru_cache(None)
def samples(record):
    """Sample polynomial definitions, without reading a generated fixture."""
    child = record[0]
    length = float(record.get("length"))
    result = []
    total = 0.0
    if child.tag == "poly3":
        v = coefficients(child)
        u, old_u, old_v = 0.0, 0.0, polynomial(v, 0.0)
        result.append((0.0, old_u, old_v, 1.0, slope(v, 0.0)))
        while total < length + 0.3:
            u += 0.3
            value = polynomial(v, u)
            total += math.hypot(u - old_u, value - old_v)
            result.append((total, u, value, 1.0, slope(v, u)))
            old_u, old_v = u, value
    else:
        u = coefficients(child, "U")
        v = coefficients(child, "V")
        intervals = max(int(length / 0.5), 5)
        step = (length if child.get("pRange") == "arcLength" else 1) / intervals
        p = 0.0
        old_u, old_v = polynomial(u, 0), polynomial(v, 0)
        result.append((0.0, old_u, old_v, slope(u, 0), slope(v, 0)))
        for _ in range(intervals):
            p += step
            pu, pv = polynomial(u, p), polynomial(v, p)
            total += math.hypot(pu - old_u, pv - old_v)
            result.append((total, pu, pv, slope(u, p), slope(v, p)))
            old_u, old_v = pu, pv
            if total > length:
                break
    return result


def reference(record, at):
    d = min(max(at - float(record.get("s")), 0), float(record.get("length")))
    heading = float(record.get("hdg"))
    child = record[0]
    if child.tag == "line":
        return math.cos(heading), math.sin(heading), heading, 0.0
    if child.tag == "arc":
        k = float(child.get("curvature"))
        theta = heading + k * d
        return math.cos(theta), math.sin(theta), theta, k
    if child.tag == "spiral":
        k = float(child.get("curvStart"))
        rate = (float(child.get("curvEnd")) - k) / float(record.get("length"))
        theta = heading + k * d + rate * d * d / 2
        return math.cos(theta), math.sin(theta), theta, k + rate * d
    table = samples(record)
    hi = min(max(bisect.bisect_left([row[0] for row in table], d), 1), len(table) - 1)
    first, second = table[hi - 1], table[hi]
    span = second[0] - first[0]
    alpha = (d - first[0]) / span
    du, dv = (second[1] - first[1]) / span, (second[2] - first[2]) / span
    tu = first[3] + alpha * (second[3] - first[3])
    tv = first[4] + alpha * (second[4] - first[4])
    dtu, dtv = (second[3] - first[3]) / span, (second[4] - first[4]) / span
    theta = heading + math.atan2(tv, tu)
    turn = (tu * dtv - tv * dtu) / (tu * tu + tv * tv)
    c, sn = math.cos(heading), math.sin(heading)
    return du * c - dv * sn, du * sn + dv * c, theta, turn


def tangent(road, section, lane_id, at):
    off, off_slope = record_value(road.findall("lanes/laneOffset"), at)
    offset, lateral_slope = -off, -off_slope
    if lane_id:
        for id in range(1, abs(lane_id) + 1):
            side = "left" if lane_id > 0 else "right"
            signed_id = id if lane_id > 0 else -id
            lane = section.find(f"{side}/lane[@id='{signed_id}']")
            if lane is None:
                continue
            value, derivative = record_value(
                lane.findall("width"), at - float(section.get("s")), "sOffset"
            )
            factor = -1.0 if lane_id > 0 else 1.0
            if id == abs(lane_id):
                factor *= 0.5
            offset += factor * value
            lateral_slope += factor * derivative
    _, dz = record_value(road.findall("elevationProfile/elevation"), at)
    record = active(road.findall("planView/geometry"), at)
    dx, dy, theta, turn = reference(record, at)
    dx += offset * turn * math.cos(theta) + lateral_slope * math.sin(theta)
    dy += offset * turn * math.sin(theta) - lateral_slope * math.cos(theta)
    yaw = -theta + math.atan2(
        dx * math.sin(theta) - dy * math.cos(theta),
        dx * math.cos(theta) + dy * math.sin(theta),
    )
    pitch = -math.atan2(dz, math.hypot(dx, dy))
    positive = lane_id <= 0 if road.get("rule") != "LHT" else lane_id >= 0
    sign = 1 if positive else -1
    if not positive:
        yaw += math.pi
        pitch = 2 * math.pi - pitch
    norm = math.sqrt(dx * dx + dy * dy + dz * dz)
    direction = (sign * dx / norm, -sign * dy / norm, sign * dz / norm)
    return (math.degrees(yaw), math.degrees(pitch)), direction


def segment_count(road, section, length, margins):
    count = 0
    by_lane = {}
    start = float(section.get("s"))
    end = start + length
    at_start = active(road.findall("planView/geometry"), start)
    straight = (
        at_start[0].tag == "line"
        and start >= float(at_start.get("s"))
        and end <= float(at_start.get("s")) + float(at_start.get("length"))
        and all(
            float(e.get("c", "0")) == 0 and float(e.get("d", "0")) == 0
            for e in road.findall("elevationProfile/elevation")
        )
    )
    for lane in section.findall("*/lane"):
        id = int(lane.get("id"))
        if id == 0:
            continue
        if straight:
            by_lane[id] = 1
            count += 1
            continue
        positive = id < 0 if road.get("rule") != "LHT" else id > 0
        inset = min(100 * 2.220446049250313e-16, length / 4)
        at = start + inset if positive else end - inset
        anchor = at
        forward = tangent(road, section, id, at)[1]
        n = 0
        while True:
            remaining = (end - at if positive else at - start) - 1e-6
            delta = min(1.0, remaining)
            if delta < 1e-6:
                n += 1
                break
            step = delta - 10 * 2.220446049250313e-16
            at += step if positive else -step
            next_forward = tangent(road, section, id, at)[1]
            angle = math.acos(max(-1, min(1, sum(a * b for a, b in zip(forward, next_forward)))))
            margins.append(abs(abs(angle) - math.pi / 100))
            if abs(angle) > math.pi / 100 or abs(anchor - at) > 100:
                n += 1
                anchor, forward = at, next_forward
        by_lane[id] = n
        count += n
    return count, by_lane


def main():
    root = ET.parse(Path(__file__).resolve().parents[1] / "assets/carla/town.xodr").getroot()
    roads = {int(r.get("id")): r for r in root.findall("road")}
    controls = []
    cases = [(1, 1, -1, 50), (5, 0, -1, 10), (5, 0, 1, 40), (5, 0, -2, 50)]
    for road_id, section_id, lane_id, at in cases:
        road = roads[road_id]
        section = road.findall("lanes/laneSection")[section_id]
        angles, direction = tangent(road, section, lane_id, at)
        controls.append({
            "road": road_id, "section": section_id, "lane": lane_id, "s": at,
            "yaw": angles[0], "pitch": angles[1], "forward": direction,
        })
    total, counts, margins = 0, {}, []
    for road_id, road in roads.items():
        sections = road.findall("lanes/laneSection")
        for i, section in enumerate(sections):
            end = (
                float(sections[i + 1].get("s"))
                if i + 1 < len(sections) else float(road.get("length"))
            )
            count, by_lane = segment_count(
                road, section, end - float(section.get("s")), margins
            )
            total += count
            counts[f"{road_id}/{i}"] = by_lane
    print(json.dumps({
        "orientation_controls": controls,
        "segment_count": total,
        "segments_by_road_section_lane": counts,
        "heading_threshold_decisions": len(margins),
        "minimum_threshold_margin_radians": min(margins),
    }, indent=2))


if __name__ == "__main__":
    main()
