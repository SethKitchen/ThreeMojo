# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""A preconstructed exact-polynomial model checks fresh hostile-state refusal."""

from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.curve_objective_model import (
    _ObjectiveModel,
    _try_objective_model,
    _restrict_objective_model,
)
from std.math import inf
from std.testing import assert_false, assert_true


def _objective_fp_fixture() raises -> Tuple[_Jet, _Jet, _ObjectiveModel]:
    # F(s)=1+2s+3s^2+s^3 on [0,1], with exact dyadic center data.
    var domain = _Jet(
        _Interval(1.0, 7.0), _Interval(2.0, 11.0), _Interval(6.0, 12.0), 0.0001
    )
    var center = _Jet(
        _Interval.point(2.875),
        _Interval.point(5.75),
        _Interval.point(9.0),
        inf[DType.float64](),
    )
    var result = _try_objective_model(0.0, 1.0, 0.5, 1.0, domain, center)
    assert_true(Bool(result))
    assert_true(
        Bool(_restrict_objective_model(result.value(), 0.25, 0.75, 1.0))
    )
    return (domain, center, result.value())


def _assert_objective_refuses_hostile_state(
    domain: _Jet, center: _Jet, model: _ObjectiveModel
) raises:
    assert_false(Bool(_try_objective_model(0.0, 1.0, 0.5, 1.0, domain, center)))
    assert_false(Bool(_restrict_objective_model(model, 0.25, 0.75, 1.0)))
