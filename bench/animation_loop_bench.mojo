# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The same public action/mixer workloads against baseline and corrected trees.

Build this source in each tree. Compare matching ordinary checksums. Hard-case
checksums intentionally differ because the baseline count and phase are wrong.
There is one advance per iteration, never one iteration per elapsed clip loop.
"""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import (
    AnimationAction,
    AnimationMixer,
    REPEAT,
    PING_PONG,
)
from animation.keyframe_track import KeyframeTrack, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from std.memory import bitcast
from std.time import perf_counter_ns
from units.si import Duration, SECOND


def _clip() raises -> AnimationClip:
    return AnimationClip(
        "bench",
        [
            KeyframeTrack(
                NodeId(0),
                POSITION,
                [Duration(0, SECOND), Duration(1.5, SECOND)],
                [Float32(0), 0, 0, 1, 0, 0],
            )
        ],
    )


def _actions(count: Int, kind: Int) raises -> Float64:
    var action = AnimationAction(_clip(), PING_PONG if kind == 1 else REPEAT)
    var checksum = Float64(0)
    for i in range(count):
        var step = Float32(0.015625)
        if kind >= 2:
            action.phase = 0
            action.loop_count = -1
            action.started = False
            step = bitcast[DType.float32](UInt32(0x4C000000) + UInt32(i % 4))
        if kind == 3:
            step = -step
        action.advance(step)
        checksum += Float64(action.phase) + Float64(action.loop_delta)
    return checksum


def _mixer(count: Int, actions: Int) raises -> Float64:
    var scene = Scene()
    _ = scene.add(Object3D())
    var mixer = AnimationMixer()
    var which = mixer.add(AnimationAction(_clip()))
    mixer.action(which).play()
    for _ in range(1, actions):
        var next = mixer.add(AnimationAction(_clip()))
        mixer.action(next).play()
    var checksum = Float64(0)
    for _ in range(count):
        mixer.update(scene, Duration(0.015625, SECOND))
        checksum += Float64(mixer.action(which).phase)
    return checksum


def main() raises:
    for trial in range(7):
        for kind in range(6):
            var count = 200000 if kind < 4 else 10000
            var start = perf_counter_ns()
            var checksum: Float64
            if kind < 4:
                checksum = _actions(count, kind)
            else:
                checksum = _mixer(count, 1 if kind == 4 else 8)
            var elapsed = perf_counter_ns() - start
            print(trial, kind, count, elapsed, checksum)
