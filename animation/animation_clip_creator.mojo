# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Ready-made clips, from three.js
`examples/jsm/animation/AnimationClipCreator.js`.

Each function returns a clip of one track, as three.js's static methods
do, with no name. three.js's tracks name their target by a path that the
mixer binds to the object it plays on. Here a track names its target, so
each function takes the node or the material to drive.

| Function | three.js | The track |
|---|---|---|
| `create_rotation_animation` | `CreateRotationAnimation` | `.rotation[axis]`, from 0 to 360 over `period` |
| `create_scale_axis_animation` | `CreateScaleAxisAnimation` | `.scale[axis]`, from 0 to 1 over `period` |
| `create_shake_animation` | `CreateShakeAnimation` | `.position`, ten random keys a second |
| `create_pulsation_animation` | `CreatePulsationAnimation` | `.scale`, ten random keys a second |
| `create_visibility_animation` | `CreateVisibilityAnimation` | `.visible`: shown, hidden at half way, shown |
| `create_material_color_animation` | `CreateMaterialColorAnimation` | `.material.color`, the colors evenly over `duration` |

The rotation runs to 360 radians, as three.js's does: it writes 360 and
reads radians. So a rotation clip turns the node 57 times and a bit. The
shake sets the node's position to each random key, and does not add it to
where the node is, as in three.js.

three.js draws its random numbers from `Math.random`. Here they come from
a `SeededRandom`, so a clip can be made again. The keys take its numbers
in three.js's order: x, y and z of each key in turn.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import (
    KeyframeTrack,
    MATERIAL_COLOR,
    POSITION,
    ROTATION_ELEMENT,
    SCALE,
    SCALE_ELEMENT,
    VISIBLE,
    material_target,
    node_element_target,
    node_target,
)
from core.object3d import NodeId
from materials.material import MaterialId
from math.utils import SeededRandom
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from units.si import Duration, SECOND

# How many keys a second the shake and the pulse take, three.js's `* 10`.
comptime KEYS_A_SECOND = Float32(10)
# Where a rotation clip ends, in radians, three.js's `360`.
comptime ROTATION_END = Float32(360)


def _clip(var track: KeyframeTrack, duration: Duration) raises -> AnimationClip:
    """Return a clip of no name holding one track, `duration` long."""
    var tracks = List[KeyframeTrack]()
    tracks.append(track^)
    return AnimationClip("", tracks^, duration=duration)


def create_rotation_animation(
    node: NodeId, period: Duration, axis: Int = 0
) raises -> AnimationClip:
    """Return a clip that turns a node about one axis, three.js's
    `CreateRotationAnimation`.

    Args:
        node: The node to turn.
        period: How long the clip runs.
        axis: 0 for x, the default, 1 for y and 2 for z.

    Returns:
        A clip whose one track takes the angle from 0 to 360 radians.

    Raises:
        Error: If the axis is not 0, 1 or 2, or the period is not above
            zero.
    """
    return _clip(
        KeyframeTrack(
            node_element_target(node, ROTATION_ELEMENT, axis),
            [Duration(0, SECOND), period],
            [0, ROTATION_END],
        ),
        period,
    )


def create_scale_axis_animation(
    node: NodeId, period: Duration, axis: Int = 0
) raises -> AnimationClip:
    """Return a clip that grows a node along one axis, three.js's
    `CreateScaleAxisAnimation`.

    Args:
        node: The node to scale.
        period: How long the clip runs.
        axis: 0 for x, the default, 1 for y and 2 for z.

    Returns:
        A clip whose one track takes the scale from 0 to 1.

    Raises:
        Error: If the axis is not 0, 1 or 2, or the period is not above
            zero.
    """
    return _clip(
        KeyframeTrack(
            node_element_target(node, SCALE_ELEMENT, axis),
            [Duration(0, SECOND), period],
            [0, 1],
        ),
        period,
    )


def _key_count(duration: Duration) -> Int:
    """Return how many keys three.js's `for ( i = 0; i < duration * 10;
    i ++ )` makes."""
    var limit = duration.to(SECOND) * KEYS_A_SECOND
    var count = 0
    while Float32(count) < limit:
        count += 1
    return count


def create_shake_animation(
    node: NodeId,
    duration: Duration,
    shake_scale: Vector3,
    mut random: SeededRandom,
) raises -> AnimationClip:
    """Return a clip that moves a node to a random place ten times a
    second, three.js's `CreateShakeAnimation`.

    Args:
        node: The node to shake.
        duration: How long the clip runs.
        shake_scale: How far each key may lie along each axis, either way.
        random: Where the random numbers come from.

    Returns:
        A clip whose one track sets the position.

    Raises:
        Error: If the duration is not above zero.
    """
    var times = List[Duration]()
    var values = List[Float32]()
    for key in range(_key_count(duration)):
        times.append(Duration(Float32(key) / KEYS_A_SECOND, SECOND))
        var x = Float32(random.next() * 2.0 - 1.0)
        var y = Float32(random.next() * 2.0 - 1.0)
        var z = Float32(random.next() * 2.0 - 1.0)
        values.append(x * shake_scale.x)
        values.append(y * shake_scale.y)
        values.append(z * shake_scale.z)
    return _clip(
        KeyframeTrack(node_target(node, POSITION), times, values^), duration
    )


def create_pulsation_animation(
    node: NodeId,
    duration: Duration,
    pulse_scale: Float32,
    mut random: SeededRandom,
) raises -> AnimationClip:
    """Return a clip that scales a node evenly to a random size ten times a
    second, three.js's `CreatePulsationAnimation`.

    Args:
        node: The node to scale.
        duration: How long the clip runs.
        pulse_scale: The largest scale a key can take.
        random: Where the random numbers come from.

    Returns:
        A clip whose one track sets the scale.

    Raises:
        Error: If the duration is not above zero.
    """
    var times = List[Duration]()
    var values = List[Float32]()
    for key in range(_key_count(duration)):
        times.append(Duration(Float32(key) / KEYS_A_SECOND, SECOND))
        var factor = Float32(random.next()) * pulse_scale
        values.append(factor)
        values.append(factor)
        values.append(factor)
    return _clip(
        KeyframeTrack(node_target(node, SCALE), times, values^), duration
    )


def create_visibility_animation(
    node: NodeId, duration: Duration
) raises -> AnimationClip:
    """Return a clip that hides a node for its second half, three.js's
    `CreateVisibilityAnimation`.

    Args:
        node: The node to hide.
        duration: How long the clip runs.

    Returns:
        A clip whose one track shows the node, hides it half way, and
        shows it at the end.

    Raises:
        Error: If the duration is not above zero.
    """
    var seconds = duration.to(SECOND)
    return _clip(
        KeyframeTrack(
            node_target(node, VISIBLE),
            [
                Duration(0, SECOND),
                Duration(seconds / 2, SECOND),
                duration,
            ],
            [1, 0, 1],
        ),
        duration,
    )


def create_material_color_animation(
    material: MaterialId, duration: Duration, colors: List[FloatColor]
) raises -> AnimationClip:
    """Return a clip that runs a material's color through a list, three.js's
    `CreateMaterialColorAnimation`.

    Args:
        material: The material to color.
        duration: How long the clip runs.
        colors: The colors, in linear light, at even steps from the start
            to `duration`. One color is one key at the start.

    Returns:
        A clip whose one track sets the material's color.

    Raises:
        Error: If there is no color, or the duration is not above zero.
    """
    if len(colors) == 0:
        raise Error("A color animation needs at least one color")
    var step = Float32(0)
    if len(colors) > 1:
        step = duration.to(SECOND) / Float32(len(colors) - 1)
    var times = List[Duration]()
    var values = List[Float32]()
    for index in range(len(colors)):  # pragma: no branch
        times.append(Duration(Float32(index) * step, SECOND))
        values.append(colors[index].r)
        values.append(colors[index].g)
        values.append(colors[index].b)
    return _clip(
        KeyframeTrack(
            material_target(material, MATERIAL_COLOR), times, values^
        ),
        duration,
    )
