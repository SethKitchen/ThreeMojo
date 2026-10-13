# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The edge cases of the actor loft and the replayer's angle blend.

A loft with no sections passes each check and then fails because it has
no section to join. A replay turn of 270 degrees either way is shorter
as 90 degrees the other way.
"""

from extensions.carla.actor import ActorId
from extensions.carla.recorder_packets import LogVector, RecordedPosition
from extensions.carla.render_actors import loft
from extensions.carla.replayer_helper import interpolated_transform
from std.testing import TestSuite, assert_almost_equal, assert_raises
from units.si import Length


def test_loft_with_no_sections() raises:
    with assert_raises():
        _ = loft(
            List[Length](), List[Length](), List[Length](), List[Length](), 0, 8
        )


def test_replay_turns_the_shorter_way() raises:
    # A turn of +270 degrees is -90 the short way, and -270 is +90.
    var a = RecordedPosition(ActorId(1), LogVector(0, 0, 0), LogVector(0, 0, 0))
    var up = RecordedPosition(
        ActorId(1), LogVector(0, 0, 0), LogVector(0, 0, 270)
    )
    var down = RecordedPosition(
        ActorId(1), LogVector(0, 0, 0), LogVector(0, 0, -270)
    )
    var mid = interpolated_transform(a, up, 0.5)
    assert_almost_equal(Float64(mid.rotation.yaw), -45, atol=1e-4)
    mid = interpolated_transform(a, down, 0.5)
    assert_almost_equal(Float64(mid.rotation.yaw), 45, atol=1e-4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
