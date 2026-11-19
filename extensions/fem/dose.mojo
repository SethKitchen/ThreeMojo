# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The thermal dose of heated tissue, in equivalent minutes at 43 C.

Heat kills tissue by the time that it spends hot, and above 43 C each
degree doubles the rate. Sapareto and Dewey (1984) turn a history of
temperatures into the minutes at 43 C that do the same harm, the
cumulative equivalent minutes (CEM43):

    CEM43 = sum over the intervals of R^(43 - T) dt

with `T` in degrees Celsius, `dt` in minutes, `R = 0.5` at or above
43 C and `R = 0.25` below. Hyperthermia and ablation research often takes
240 minutes as the dose that kills most tissues.

`thermal_dose` gives the CEM43 of each node from the records of
`solve_transient`. Each interval between two records counts at the mean
of its two temperatures, which is exact for a steady temperature. Keep
the records close enough that the temperature changes little within one.
`dose_volume` gives the volume of the elements whose corner nodes all
reach a dose, such as the ablated volume at 240 minutes.
"""

from extensions.fem.ids import ElementId
from extensions.fem.mesh import TetMesh
from extensions.fem.thermal import TransientResult
from std.math import isfinite
from units.si import CUBIC_METER, Duration64, MINUTE, SECOND, Volume64

comptime KELVIN_AT_ZERO_CELSIUS = 273.15


def thermal_dose(result: TransientResult) raises -> List[Duration64]:
    """Return the CEM43 of each node over the records of a transient.

    Args:
        result: The records of `solve_transient`, two or more.

    Returns:
        The equivalent minutes at 43 C of each node.

    Raises:
        Error: If there are fewer than two records, the times do not rise,
            or a record has another number of nodes.
    """
    var records = len(result.times)
    if records < 2 or len(result.temperatures) != records:
        raise Error("A thermal dose needs two or more records")
    var nodes = len(result.temperatures[0])
    var minutes = List[Float64](length=nodes, fill=0)
    for r in range(1, records):  # pragma: no branch
        var dt = (result.times[r] - result.times[r - 1]) / 60.0
        if not (dt > 0):
            raise Error("The times of a thermal dose must rise")
        if len(result.temperatures[r]) != nodes:
            raise Error("Each record needs the temperature of every node")
        for n in range(nodes):
            var celsius = (
                0.5
                * (result.temperatures[r - 1][n] + result.temperatures[r][n])
                - KELVIN_AT_ZERO_CELSIUS
            )
            var rate = 0.5 if celsius >= 43 else 0.25
            minutes[n] += rate ** (43.0 - celsius) * dt
    var out = List[Duration64](capacity=nodes)
    for n in range(nodes):
        out.append(Duration64(minutes[n], MINUTE))
    return out^


def dose_volume(
    mesh: TetMesh, doses: List[Duration64], threshold: Duration64
) raises -> Volume64:
    """Return the volume of the elements whose corners all reach a dose.

    Args:
        mesh: The mesh.
        doses: The dose of each node, from `thermal_dose`.
        threshold: The dose, such as 240 minutes. At least 0 and finite.

    Returns:
        The sum of the volumes of those elements.

    Raises:
        Error: If the doses do not fit the mesh, or the threshold is
            negative or not finite.
    """
    if len(doses) != mesh.node_count():
        raise Error("A dose volume needs the dose of every node")
    var limit = threshold.to(SECOND)
    if not (limit >= 0) or not isfinite(limit):
        raise Error("A dose threshold must be at least 0 and finite")
    var count = mesh.nodes_per_element()
    var total = 0.0
    for e in range(mesh.element_count()):
        var reached = True
        for c in range(4):  # pragma: no branch
            var node = mesh.corners[count * e + c]
            if not (doses[node].to(SECOND) >= limit):
                reached = False
        if reached:
            total += mesh.volume(ElementId(e)).to(CUBIC_METER)
    return Volume64(total, CUBIC_METER)
