# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the combos' effects write over the frame: a flash of light as
each effect strikes, a reticle over each marked target, and the drops of
each wound that bleeds. `extensions.village.battle_hud` calls
`draw_effects` after the raid's parts.

| Effect | Its flash, over `FLASH_SECONDS` |
|---|---|
| `LAUNCH` | A streak of white light that rises from the foe |
| `SUNDER` | Shards of blue light that burst out from the foe |
| `BLEED` | Drops of red light that fall from the foe |
| `DRAIN` | Motes of green light that run from the foe to the player |
| `SHOCKWAVE` | A ring of gold light that spreads over the ground from the foe |
| `CHAIN` | A crooked arc of violet light from the foe to each target it leaps to |
| `MARK` | A ring of gold light that closes on the foe |

A marked target wears a ring of four gold stars over its head, which
turns as the mark runs out. A wounded target sheds a red drop that pulses
at each of its bleeding's numbers.

This is not a three.js port. See Extensions.
"""

from cameras.perspective_camera import PerspectiveCamera
from extensions.village.battle import (
    CHEST,
    FLASH_SECONDS,
    MARK_SECONDS,
    SHOCK_RADIUS,
    Battle,
    Flash,
)
from extensions.village.combos import (
    BLEED,
    CHAIN,
    DRAIN,
    LAUNCH,
    SHOCKWAVE,
    SUNDER,
)
from extensions.village.slashes import arc_points, glow_ribbon, glow_star
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from std.math import cos, pi, sin

comptime LAUNCH_LIGHT = Vector3(200, 230, 255)
"""The light of a launch's streak."""
comptime SUNDER_LIGHT = Vector3(120, 190, 255)
"""The light of a sunder's shards."""
comptime BLEED_LIGHT = Vector3(230, 30, 40)
"""The light of a wound's drops."""
comptime DRAIN_LIGHT = Vector3(110, 240, 130)
"""The light of a drain's motes."""
comptime SHOCK_LIGHT = Vector3(255, 200, 90)
"""The light of a shockwave's ring."""
comptime CHAIN_LIGHT = Vector3(205, 170, 255)
"""The light of a chain's arc."""
comptime MARK_LIGHT = Vector3(255, 215, 90)
"""The light of a mark's ring and reticle."""
comptime ARC_STEPS = 7
"""How many crooked steps a chain's arc takes."""
comptime MOTES = 5
"""How many motes a drain's light has, and shards a sunder's."""
comptime RETICLE_RISE = Float32(2.3)
"""How high over a marked target's feet its reticle turns, in meters."""


def _star(
    mut frame: Framebuffer,
    camera: PerspectiveCamera,
    look: Vector3,
    at: Vector3,
    size: Float32,
    color: Vector3,
    glow: Float32,
) raises:
    """Add a star of light at a point of the world, `size` meters across,
    unless the point is behind the camera."""
    var off = at - camera.position
    if off.x * look.x + off.y * look.y + off.z * look.z < 0.2:
        return
    var center = camera.project(at, frame.width, frame.height)
    var top = camera.project(
        at + Vector3(0, size, 0), frame.width, frame.height
    )
    var radius = max(Float32(1.5), abs(center.y - top.y))
    glow_star(frame, Vector3(center.x, center.y, glow), radius, color)


def _ring(
    mut frame: Framebuffer,
    camera: PerspectiveCamera,
    look: Vector3,
    center: Vector3,
    radius: Float32,
    color: Vector3,
    glow: Float32,
) raises:
    """Add a ring of light on the ground, of a radius, around a point."""
    var corners = arc_points(
        center,
        Vector3(1, 0, 0),
        Vector3(0, 0, 1),
        0,
        Float32(2 * pi),
        radius * 0.82,
        radius,
    )
    var light = List[Float32](length=len(corners) // 2, fill=glow)
    glow_ribbon(frame, camera, look, corners, light, color)


def arc_path(start: Vector3, end: Vector3, seed: Int) -> List[Vector3]:
    """Return the points of a chain's crooked arc of light.

    Args:
        start: Where it starts.
        end: Where it ends.
        seed: A number that sets how it bends, the same for the same arc.

    Returns:
        `ARC_STEPS + 1` points, from `start` to `end`. Each point between
        them is pushed up or down off the straight line by up to a tenth
        of its length, and never at the ends.
    """
    var out = List[Vector3]()
    var span = (end - start).length()
    for k in range(ARC_STEPS + 1):  # pragma: no branch
        var t = Float32(k) / Float32(ARC_STEPS)
        var bend = sin(Float32(k * 7 + seed * 13)) * span * 0.1
        if k == 0 or k == ARC_STEPS:
            bend = 0
        out.append(start + (end - start) * t + Vector3(0, bend, 0))
    return out^


def draw_flash(
    mut frame: Framebuffer,
    camera: PerspectiveCamera,
    look: Vector3,
    flash: Flash,
    seed: Int,
) raises:
    """Add an effect's flash of light to a frame: see the module's table.

    Args:
        frame: The frame, the camera's size.
        camera: The camera the frame was drawn from.
        look: The way the camera looks, of length one.
        flash: The flash.
        seed: A number that sets how a chain's arc bends.

    Raises:
        Error: If the camera or the frame's size is not valid.
    """
    var t = min(Float32(1), flash.age / FLASH_SECONDS)
    var glow = 1 - t
    ref at = flash.at
    var effect = flash.effect
    if effect == LAUNCH:
        for k in range(4):  # pragma: no branch
            var rise = t * Float32(2.5) * Float32(k + 1) / 4
            var up = at + Vector3(0, rise, 0)
            _star(frame, camera, look, up, 0.25, LAUNCH_LIGHT, glow)
    elif effect == SUNDER:
        for k in range(MOTES):  # pragma: no branch
            var a = Float32(2 * pi) * Float32(k) / Float32(MOTES)
            var reach = Float32(0.3) + Float32(1.2) * t
            var shard = at + Vector3(
                cos(a) * reach, sin(a) * reach * 0.6, sin(a) * reach
            )
            _star(frame, camera, look, shard, 0.18, SUNDER_LIGHT, glow)
    elif effect == BLEED:
        for k in range(3):  # pragma: no branch
            var drop = at + Vector3(
                Float32(k - 1) * 0.15, -t * Float32(0.9) - Float32(k) * 0.1, 0
            )
            _star(frame, camera, look, drop, 0.14, BLEED_LIGHT, glow)
    elif effect == DRAIN:
        for k in range(MOTES):  # pragma: no branch
            var share = max(Float32(0), t - Float32(k) * 0.08)
            var mote = at + (flash.to - at) * share
            _star(frame, camera, look, mote, 0.16, DRAIN_LIGHT, glow)
    elif effect == SHOCKWAVE:
        var ground = at - Vector3(0, CHEST, 0)
        var radius = max(Float32(0.2), SHOCK_RADIUS * t)
        _ring(frame, camera, look, ground, radius, SHOCK_LIGHT, glow)
    elif effect == CHAIN:
        var path = arc_path(at, flash.to, seed)
        var corners = List[Vector3]()
        for p in path:  # pragma: no branch
            corners.append(p - Vector3(0, 0.05, 0))
            corners.append(p + Vector3(0, 0.05, 0))
        var light = List[Float32](length=len(path), fill=glow)
        glow_ribbon(frame, camera, look, corners, light, CHAIN_LIGHT)
        _star(frame, camera, look, flash.to, 0.3, CHAIN_LIGHT, glow)
    else:
        var ground = at - Vector3(0, CHEST, 0)
        var radius = max(Float32(0.3), 1.6 * glow)
        _ring(frame, camera, look, ground, radius, MARK_LIGHT, glow)


def draw_effects(
    mut frame: Framebuffer,
    battle: Battle,
    camera: PerspectiveCamera,
    look: Vector3,
) raises:
    """Add the combos' effects to a frame: each flash, each mark's reticle
    and each wound's drop.

    Args:
        frame: The frame, the camera's size.
        battle: The fight.
        camera: The camera the frame was drawn from.
        look: The way the camera looks, of length one.

    Raises:
        Error: If the camera or the frame's size is not valid.
    """
    for k in range(len(battle.flashes)):
        draw_flash(frame, camera, look, battle.flashes[k], k)
    for index in range(len(battle.marks)):
        var left = battle.marks[index]
        if left <= 0 or not battle.standing(index):
            continue
        var over = battle.target_at(index) + Vector3(0, RETICLE_RISE, 0)
        var turn = Float32(pi) * (MARK_SECONDS - left)
        for k in range(4):  # pragma: no branch
            var a = turn + Float32(pi) * Float32(k) / 2
            var star = over + Vector3(cos(a) * 0.4, 0, sin(a) * 0.4)
            _star(frame, camera, look, star, 0.12, MARK_LIGHT, 0.9)
    for wound in battle.wounds:
        var chest = battle.target_at(wound.index) + Vector3(0, CHEST, 0)
        var pulse = Float32(0.4) + Float32(0.6) * (1 - wound.since * 2)
        _star(frame, camera, look, chest, 0.12, BLEED_LIGHT, pulse)
