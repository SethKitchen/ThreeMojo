# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the results of EPANET for one input file.

    python3 make_epanet.py LIBRARY NETWORK.inp > NETWORK.expected

LIBRARY is `libepanet2.so` of OWA EPANET 2.3.6, built from commit
57d8bd8ad60e89b57f2a1ac591f05c8e13589866 of
https://github.com/OpenWaterAnalytics/EPANET with

    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF
    cmake --build build

The script calls the toolkit through ctypes. It runs the hydraulics one
step at a time, then the water quality one step at a time.
`make_epanet_cases.py` can also run the two together: see
`simulate_together`. EPANET writes
its report to the null device. Values are in the units of the input file. Each value has ten significant digits.

The output has these lines:

- `size` with the number of nodes and of links.
- For each hydraulic step, `hydraulic` with the time in seconds. Then
  `head`, `demand` and `pressure` with one value for each node, and
  `flow`, `status`, `setting` and `energy` with one value for each
  link.
- For each quality step at a reporting time, `quality` with the time in
  seconds. Then `node` with the quality of each node and `link` with the
  quality of each link.
"""

import ctypes
import os
import sys

EN_DEMAND = 9
EN_HEAD = 10
EN_PRESSURE = 11
EN_QUALITY = 12
EN_FLOW = 8
EN_STATUS = 11
EN_SETTING = 12
EN_ENERGY = 13
EN_LINKQUAL = 14
EN_NODECOUNT = 0
EN_LINKCOUNT = 2
EN_REPORTSTEP = 5


class Failed(Exception):
    """A toolkit call returned an error code."""


def check(code, call="EPANET"):
    """Print an error code and stop. A code of 100 or less is a warning."""
    if code > 100:
        print(call, code)
        raise Failed(call)


def values(lib, project, get, count, field):
    """Return a line of values, one for each object."""
    out = []
    value = ctypes.c_double()
    for index in range(1, count + 1):
        check(get(project, index, field, ctypes.byref(value)))
        out.append(f"{value.value:.10g}")
    return " ".join(out)


def _size(lib, project):
    """Print and return the number of nodes and of links."""
    nodes = ctypes.c_int()
    links = ctypes.c_int()
    check(lib.EN_getcount(project, EN_NODECOUNT, ctypes.byref(nodes)))
    check(lib.EN_getcount(project, EN_LINKCOUNT, ctypes.byref(links)))
    print("size", nodes.value, links.value)
    return nodes.value, links.value


def _hydraulic(lib, project, n, m, time):
    """Print the hydraulic results of one step."""
    node = lib.EN_getnodevalue
    link = lib.EN_getlinkvalue
    print("hydraulic", time)
    print("head", values(lib, project, node, n, EN_HEAD))
    print("demand", values(lib, project, node, n, EN_DEMAND))
    print("pressure", values(lib, project, node, n, EN_PRESSURE))
    print("flow", values(lib, project, link, m, EN_FLOW))
    print("status", values(lib, project, link, m, EN_STATUS))
    print("setting", values(lib, project, link, m, EN_SETTING))
    print("energy", values(lib, project, link, m, EN_ENERGY))


def _quality(lib, project, n, m, time):
    """Print the water quality of one step."""
    print("quality", time)
    print("node", values(lib, project, lib.EN_getnodevalue, n, EN_QUALITY))
    print("link", values(lib, project, lib.EN_getlinkvalue, m, EN_LINKQUAL))


def simulate(lib, project):
    """Print the results of an open project, one step at a time."""
    n, m = _size(lib, project)
    time = ctypes.c_long()
    step = ctypes.c_long()
    check(lib.EN_openH(project), "openH")
    check(lib.EN_initH(project, 1), "initH")
    while True:
        check(lib.EN_runH(project, ctypes.byref(time)), "runH")
        _hydraulic(lib, project, n, m, time.value)
        check(lib.EN_nextH(project, ctypes.byref(step)), "nextH")
        if step.value <= 0:
            break
    check(lib.EN_closeH(project))
    report = ctypes.c_long()
    check(lib.EN_gettimeparam(project, EN_REPORTSTEP, ctypes.byref(report)))
    check(lib.EN_openQ(project), "openQ")
    check(lib.EN_initQ(project, 0), "initQ")
    while True:
        check(lib.EN_runQ(project, ctypes.byref(time)), "runQ")
        if time.value % report.value == 0:
            _quality(lib, project, n, m, time.value)
        check(lib.EN_nextQ(project, ctypes.byref(step)), "nextQ")
        if step.value <= 0:
            break
    check(lib.EN_closeQ(project))


def simulate_together(lib, project):
    """Print the results of the hydraulics and the quality, run together.

    The hydraulics stay open, start from new flows, and save nothing. Each
    step prints the hydraulic results, then the water quality.
    """
    n, m = _size(lib, project)
    time = ctypes.c_long()
    qtime = ctypes.c_long()
    step = ctypes.c_long()
    qstep = ctypes.c_long()
    check(lib.EN_openH(project), "openH")
    check(lib.EN_initH(project, 10), "initH")
    check(lib.EN_openQ(project), "openQ")
    check(lib.EN_initQ(project, 0), "initQ")
    while True:
        check(lib.EN_runH(project, ctypes.byref(time)), "runH")
        _hydraulic(lib, project, n, m, time.value)
        check(lib.EN_runQ(project, ctypes.byref(qtime)), "runQ")
        _quality(lib, project, n, m, qtime.value)
        check(lib.EN_nextH(project, ctypes.byref(step)), "nextH")
        check(lib.EN_nextQ(project, ctypes.byref(qstep)), "nextQ")
        if step.value <= 0:
            break
    check(lib.EN_closeQ(project))
    check(lib.EN_closeH(project))


def main():
    lib = ctypes.CDLL(sys.argv[1])
    project = ctypes.c_void_p()
    check(lib.EN_createproject(ctypes.byref(project)))
    check(lib.EN_open(project, sys.argv[2].encode(), os.devnull.encode(), b""))
    simulate(lib, project)
    check(lib.EN_close(project))
    check(lib.EN_deleteproject(project))


if __name__ == "__main__":
    main()
