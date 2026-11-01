# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Continuous beams on pin and roller supports.

`continuous_beam` builds a line of frame members on the solver of
`extensions.structure`, one support at each end of each span, and loads
each span with its own uniform load. It returns the support reactions,
the largest positive and negative moments, the largest shear and the
largest deflection.

`patterned_beam` loads the dead load on every span and the live load on
each of the 2^n patterns of spans, as ASCE 7-16 section 4.3.3 asks for a
continuous member, and keeps the worst value of each effect.

The moments come from the reactions by statics, so they do not depend on
the stiffness. The deflection uses E I.
"""

from extensions.building.material import steel
from extensions.building.model import rectangle
from extensions.design.steel import require_positive
from extensions.structure.ids import MemberId, NodeId
from extensions.structure.kinds import RX, UX, UY, UZ
from extensions.structure.model import StructuralModel
from extensions.structure.static import StaticSolver
from generators.utils import Vec3d
from units.si import (
    Force64,
    Length64,
    LineLoad64,
    METER,
    Moment64,
    Pressure64,
    SecondMomentOfArea64,
)

# Members per span. Deflection is read at the nodes.
comptime _SEGMENTS = 12
# Points per span of the moment scan.
comptime _SCAN = 240
# The most spans that `patterned_beam` takes: 2^8 load patterns.
comptime MAX_PATTERNED_SPANS = 8


@fieldwise_init
struct BeamResult(Copyable, Movable):
    """The effects on a continuous beam.

    A positive moment puts the bottom in tension. A downward load gives a
    positive reaction and a negative deflection.
    """

    var reactions: List[Force64]
    var max_positive: Moment64
    var max_negative: Moment64
    var max_shear: Force64
    var max_deflection: Length64


def _check_spans(spans: List[Length64]) raises:
    """Refuse a beam without spans or with a span that is not positive."""
    if len(spans) == 0:
        raise Error("A beam needs one span or more")
    # A beam has one span or more here, so the loop always runs.
    for s in spans:  # pragma: no branch
        require_positive(s.value, "A span must be positive")


def continuous_beam(
    spans: List[Length64],
    loads: List[LineLoad64],
    modulus: Pressure64,
    inertia: SecondMomentOfArea64,
) raises -> BeamResult:
    """Analyze a continuous beam under a uniform load on each span.

    Args:
        spans: The span lengths, from the first support.
        loads: The downward load per length on each span.
        modulus: E.
        inertia: I.

    Returns:
        The reactions at the supports in order, and the largest effects.

    Raises:
        Error: If there is no span, a span, E or I is not positive, the
            loads do not match the spans, or a load is not finite.
    """
    _check_spans(spans)
    if len(loads) != len(spans):
        raise Error("A beam needs one load per span")
    # There is one load per span, so the loop always runs.
    for w in loads:  # pragma: no branch
        if not (w.value > -Float64.MAX and w.value < Float64.MAX):
            raise Error("A beam load must be finite")
    require_positive(modulus.value, "E must be positive")
    require_positive(inertia.value, "I must be positive")
    # A rectangle of 0.2 m depth with the width that gives I.
    var depth = 0.2
    var width = 12 * inertia.value / depth**3
    var section = rectangle(Length64(width, METER), Length64(depth, METER))
    var material = steel()
    material.elastic_modulus = modulus
    var model = StructuralModel()
    var support_nodes = List[NodeId]()
    var x = 0.0
    var first = model.add_node(Vec3d(0, 0, 0))
    support_nodes.append(first)
    model.add_support(first, [UX, UY, UZ, RX])
    var previous = first
    var span_members = List[List[MemberId]]()
    # A beam has one span or more, so these loops always run.
    for s in range(len(spans)):  # pragma: no branch
        var piece = spans[s].value / Float64(_SEGMENTS)
        var members = List[MemberId]()
        # Each span has _SEGMENTS members.
        for i in range(1, _SEGMENTS + 1):  # pragma: no branch
            var node = model.add_node(Vec3d(x + piece * Float64(i), 0, 0))
            members.append(
                model.add_member(
                    previous, node, section, material, Vec3d(0, 0, 1)
                )
            )
            previous = node
        x += spans[s].value
        model.add_support(previous, [UY, UZ])
        support_nodes.append(previous)
        span_members.append(members^)
    var load_case = model.add_load_case("uniform")
    # A beam has one span or more.
    for s in range(len(spans)):  # pragma: no branch
        # Each span has _SEGMENTS members.
        for m in span_members[s]:  # pragma: no branch
            model.add_line_load(load_case, m, UZ, -loads[s])
    var solver = StaticSolver(model^)
    var result = solver.solve(load_case)
    var reactions = List[Force64]()
    # A beam has two supports or more.
    for n in support_nodes:  # pragma: no branch
        reactions.append(result.reaction_force(n, UZ))
    var deflection = 0.0
    # A beam has two nodes or more.
    for i in range(len(result.displacements) // 6):  # pragma: no branch
        var dz = result.displacements[6 * i + 2]
        if abs(dz) > abs(deflection):
            deflection = dz
    # Statics: scan M(x) and V(x) from the left end.
    var best_pos = 0.0
    var best_neg = 0.0
    var best_shear = 0.0
    # The shear and moment just right of the span's left support.
    var shear = 0.0
    var moment = 0.0
    # A beam has one span or more.
    for s in range(len(spans)):  # pragma: no branch
        shear += reactions[s].value
        best_shear = max(best_shear, abs(shear))
        var l = spans[s].value
        var w = loads[s].value
        # The scan has _SCAN points per span.
        for i in range(1, _SCAN + 1):  # pragma: no branch
            var t = l * Float64(i) / Float64(_SCAN)
            var m = moment + shear * t - w * t * t / 2
            best_pos = max(best_pos, m)
            best_neg = min(best_neg, m)
        moment += shear * l - w * l * l / 2
        shear -= w * l
        best_shear = max(best_shear, abs(shear))
    return BeamResult(
        reactions^,
        Moment64(best_pos),
        Moment64(best_neg),
        Force64(best_shear),
        Length64(deflection),
    )


@fieldwise_init
struct PatternedResult(Copyable, Movable):
    """The worst effects of a continuous beam over the live patterns.

    Each reaction is the largest at its support. The live deflection is
    the largest of the live load alone.
    """

    var reactions: List[Force64]
    var max_positive: Moment64
    var max_negative: Moment64
    var max_shear: Force64
    var max_deflection: Length64
    var max_live_deflection: Length64


def patterned_beam(
    spans: List[Length64],
    dead: LineLoad64,
    live: LineLoad64,
    modulus: Pressure64,
    inertia: SecondMomentOfArea64,
) raises -> PatternedResult:
    """Analyze a continuous beam for dead load and patterned live load.

    Args:
        spans: The span lengths, at most `MAX_PATTERNED_SPANS`.
        dead: The dead load on every span.
        live: The live load on the loaded spans of a pattern.
        modulus: E.
        inertia: I.

    Returns:
        The worst reactions, moments, shear and deflections.

    Raises:
        Error: If there are no spans or too many, or `continuous_beam`
            refuses the beam.
    """
    _check_spans(spans)
    var n = len(spans)
    if n > MAX_PATTERNED_SPANS:
        raise Error("A patterned beam takes at most eight spans")
    var reactions = List[Force64]()
    # A beam has one span or more, so these loops always run.
    for _ in range(n + 1):  # pragma: no branch
        reactions.append(Force64(0))
    var pos = 0.0
    var neg = 0.0
    var shear = 0.0
    var defl = 0.0
    var live_defl = 0.0
    # One span or more gives one live pattern or more.
    for pattern in range(1, 1 << n):  # pragma: no branch
        var loads = List[LineLoad64]()
        var live_only = List[LineLoad64]()
        # A beam has one span or more.
        for s in range(n):  # pragma: no branch
            var on = (pattern >> s) & 1 == 1
            loads.append(dead + live if on else dead)
            live_only.append(live if on else LineLoad64(0))
        var r = continuous_beam(spans, loads, modulus, inertia)
        # A beam has two supports or more.
        for i in range(n + 1):  # pragma: no branch
            if r.reactions[i].value > reactions[i].value:
                reactions[i] = r.reactions[i]
        pos = max(pos, r.max_positive.value)
        neg = min(neg, r.max_negative.value)
        shear = max(shear, r.max_shear.value)
        if abs(r.max_deflection.value) > abs(defl):
            defl = r.max_deflection.value
        var l = continuous_beam(spans, live_only, modulus, inertia)
        if abs(l.max_deflection.value) > abs(live_defl):
            live_defl = l.max_deflection.value
    return PatternedResult(
        reactions^,
        Moment64(pos),
        Moment64(neg),
        Force64(shear),
        Length64(defl),
        Length64(live_defl),
    )
