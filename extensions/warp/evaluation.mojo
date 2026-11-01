# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The whole analysis of a metric in one call.

`evaluate_metric` is WarpFactory's `evalMetric`. It finds the
stress-energy tensor with fourth-order differences, moves it into the
Eulerian frame, evaluates the four energy conditions and finds the
expansion, shear and vorticity scalars.
"""

from extensions.warp.conditions import ConditionMap, energy_condition
from extensions.warp.frame import to_eulerian
from extensions.warp.kinds import (
    DOMINANT_ENERGY,
    FOURTH_ORDER,
    NULL_ENERGY,
    STRONG_ENERGY,
    WEAK_ENERGY,
)
from extensions.warp.scalars import MetricScalars, metric_scalars
from extensions.warp.solver import StressEnergy, stress_energy
from extensions.warp.tensor import Metric


struct MetricEvaluation(Movable):
    """The products of `evaluate_metric`."""

    var metric: Metric
    """The metric that was evaluated."""
    var energy: StressEnergy
    """T^ab in the coordinate frame."""
    var eulerian: StressEnergy
    """T^ab in the Eulerian frame."""
    var null: ConditionMap
    """The null energy condition."""
    var weak: ConditionMap
    """The weak energy condition."""
    var strong: ConditionMap
    """The strong energy condition."""
    var dominant: ConditionMap
    """The dominant energy condition."""
    var scalars: MetricScalars
    """The expansion, shear and vorticity."""

    def __init__(
        out self,
        var metric: Metric,
        var energy: StressEnergy,
        var eulerian: StressEnergy,
        var null: ConditionMap,
        var weak: ConditionMap,
        var strong: ConditionMap,
        var dominant: ConditionMap,
        var scalars: MetricScalars,
    ):
        """Hold the products of an evaluation.

        Args:
            metric: The metric.
            energy: T^ab in the coordinate frame.
            eulerian: T^ab in the Eulerian frame.
            null: The null energy condition.
            weak: The weak energy condition.
            strong: The strong energy condition.
            dominant: The dominant energy condition.
            scalars: The expansion, shear and vorticity.
        """
        self.metric = metric^
        self.energy = energy^
        self.eulerian = eulerian^
        self.null = null^
        self.weak = weak^
        self.strong = strong^
        self.dominant = dominant^
        self.scalars = scalars^


def evaluate_metric(
    metric: Metric,
    keep_positive: Bool = True,
    count: Int = 100,
    shells: Int = 10,
) raises -> MetricEvaluation:
    """Return the stress-energy, energy conditions and scalars of a metric.

    This is WarpFactory's `evalMetric` on the CPU.

    Args:
        metric: The metric.
        keep_positive: Whether to keep the values that satisfy a
            condition. If False, each map holds only its violations, and
            every other value is zero.
        count: The number of directions on the sphere.
        shells: The number of timelike shells.

    Returns:
        The evaluation.

    Raises:
        Error: If a count is less than 1, or the metric is singular, has
            no Eulerian frame or has no real lapse at a point.
    """
    var energy = stress_energy(metric, FOURTH_ORDER)
    var eulerian = to_eulerian(energy, metric)
    var null = energy_condition(eulerian, metric, NULL_ENERGY, count, shells)
    var weak = energy_condition(eulerian, metric, WEAK_ENERGY, count, shells)
    var strong = energy_condition(
        eulerian, metric, STRONG_ENERGY, count, shells
    )
    var dominant = energy_condition(
        eulerian, metric, DOMINANT_ENERGY, count, shells
    )
    if not keep_positive:
        null = null.violations_only()
        weak = weak.violations_only()
        strong = strong.violations_only()
        dominant = dominant.violations_only()
    var scalars = metric_scalars(metric)
    return MetricEvaluation(
        metric.copy(),
        energy^,
        eulerian^,
        null^,
        weak^,
        strong^,
        dominant^,
        scalars^,
    )
