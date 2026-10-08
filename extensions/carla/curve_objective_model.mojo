# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Invocation-local Taylor restrictions of one complete smooth objective cell.

The stored second derivative and scalar error were evaluated over the whole
owning cell. Center values are translated ideal enclosures; their infinite
scalar-error sentinel is preserved and never used as the world error.
"""

from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.curve_sum2 import _sum2_supported_environment
from std.math import isfinite
from std.memory import bitcast


@fieldwise_init
struct _ObjectiveModel(ImplicitlyCopyable):
    # The calling proof consumer must keep one fixed query, an immutable
    # road/lane/profile snapshot and the same smooth ideal expression.
    # These preconditions must hold throughout the model's lifetime.
    # The current lane-search solver does not use this standalone helper.
    var low: Float64
    var high: Float64
    var center_s: Float64
    var scale_word: UInt64
    var domain: _Jet
    var center: _Jet


def _model_interval(value: _Interval) -> Bool:
    return value.is_finite() and value.low <= value.high


def _try_objective_model(
    low: Float64,
    high: Float64,
    center_s: Float64,
    scale: Float64,
    domain: _Jet,
    center: _Jet,
) -> Optional[_ObjectiveModel]:
    if not _sum2_supported_environment():
        return None
    if (
        not isfinite(low)
        or not isfinite(high)
        or not isfinite(center_s)
        or low >= high
        or center_s < low
        or center_s > high
        or not isfinite(scale)
        or scale <= 0.0
        or not _model_interval(domain.value)
        or not _model_interval(domain.first)
        or not _model_interval(domain.second)
        or not isfinite(domain.error)
        or domain.error < 0.0
        or not _model_interval(center.value)
        or not _model_interval(center.first)
    ):
        return None
    # This relies on the bound producer's audited smooth-function invariant:
    # unresolved record/profile/clamp/count/sample/phase/atan joins discard
    # derivatives. The producer's explicit finite reconstruction exceptions
    # have constant-function provenance (stored constant heading, wholly
    # clamped distance, or a proved constant sampled/axis frame). Ordinary
    # interval arithmetic preserves the discarded unknown derivatives.
    # Thus these data describe the same smooth ideal objective as the existing
    # _global_lower consumer. Scalar error is uniform over [low, high].
    return _ObjectiveModel(
        low, high, center_s, bitcast[DType.uint64](scale), domain, center
    )


def _restrict_objective_model(
    model: _ObjectiveModel, low: Float64, high: Float64, scale: Float64
) -> Optional[_Jet]:
    # Cached success never grants authority under a changed floating-point
    # mode. Check this invocation before touching cached arithmetic data.
    if not _sum2_supported_environment():
        return None
    if (
        not isfinite(low)
        or not isfinite(high)
        or high < low
        or low < model.low
        or high > model.high
        or bitcast[DType.uint64](scale) != model.scale_word
    ):
        return None
    var delta = _Interval(low, high) - _Interval.point(model.center_s)
    var value = (
        model.center.value
        + model.center.first * delta
        + _Interval.point(0.5) * model.domain.second * delta.square()
    )
    var first = model.center.first + model.domain.second * delta
    # Both the original whole-cell range and the Taylor restriction enclose
    # the same ideal F(s). Intersect only ordered finite enclosures.
    if not _model_interval(value) or not _model_interval(first):
        return None
    value = _Interval(
        max(value.low, model.domain.value.low),
        min(value.high, model.domain.value.high),
    )
    first = _Interval(
        max(first.low, model.domain.first.low),
        min(first.high, model.domain.first.high),
    )
    if not _model_interval(value) or not _model_interval(first):
        return None
    # These fields enclose F, F' and F'' on the child; they are not the
    # derivatives of the interval-valued quadratic used to compute value.
    # Actual rounded G remains within the same whole-owner uniform error E.
    return _Jet(value, first, model.domain.second, model.domain.error)


def _objective_followup_room(
    nodes: Int,
    terms: Int,
    max_nodes: Int,
    max_terms: Int,
    reference_work: Int,
    center_work: Int,
) -> Bool:
    # A reused model may schedule two children. Retain a node for each
    # child and each closed-cell recheck, plus each child's three scalar
    # witnesses and one domain reservation. Child reference work cannot
    # exceed the containing parent's complete count-union reservation.
    # This minimum followup reserve is not a whole-search completion bound.
    if (
        nodes < 0
        or nodes > max_nodes
        or terms < 0
        or terms > max_terms
        or reference_work < 0
        or center_work < 0
    ):
        return False
    var remaining = max_terms - terms
    return (
        max_nodes - nodes >= 4
        and center_work <= remaining
        and reference_work <= (remaining - center_work) // 8
    )


def _objective_recheck_room(nodes: Int, max_nodes: Int) -> Bool:
    # An optional cached closure retains a cell for later validation.
    # A strict exclusion discards the cell and needs no such reservation.
    return nodes >= 0 and nodes < max_nodes
