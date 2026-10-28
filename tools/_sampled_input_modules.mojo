# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the modules the sampled-value check reads first.

Bounds, trig, and the interval come first. The lane value module is last.
"""

from tools._carla_package import carla_package
from tools._sampled_graph_pins import sampled_graphs_and_names


def sampled_input_modules() -> String:
    """Return the four sampled input modules in reviewed order.

    Returns:
        A JSON list of file names.
    """
    return (
        '["curve_bounds.mojo","curve_trig.mojo","curve_interval.mojo",'
        + '"lane_value_bounds.mojo"]'
    )


def sampled_input_plan() -> String:
    """Return the input modules, then the package path.

    Returns:
        JSON with `modules` and `package` in that order.
    """
    var modules = sampled_input_modules()
    return '{"modules":' + modules + ',"package":"' + carla_package() + '"}'


def sampled_plan_then_graphs() raises -> String:
    """Read the input plan, then the graph pins and reference names.

    Returns:
        JSON with `modules`, `package`, `graphs`, and `closure`. The
        input plan is read before the graph pins.

    Raises:
        Error: The reference names differ from the digest keys. The
            input plan is read before that name check.
    """
    var plan = sampled_input_plan()
    var checked = sampled_graphs_and_names()
    var end = plan.byte_length() - 1
    var prefix = plan[byte=0:end]
    var rest = checked[byte=1:]
    return String(prefix) + "," + String(rest)
