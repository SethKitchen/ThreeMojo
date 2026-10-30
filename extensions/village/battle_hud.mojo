# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a fight writes over the frame, with the font of
`extensions.village.hud`.

`draw_battle` draws eight things:

1. **The trails** of the swings, the demon fang's waves, the
   companion's bolts, the throwers' knives and a plunge's ring, as light
   added to the frame: see `extensions.village.slashes`. A wave dims as
   it runs. A knife is a small orange star. A plunge's
   ring spreads over the ground from the player's feet, and fades. A bolt is a blue
   star, or a gold one for a boost attack.
2. **The player's gauges**, in the bottom right: the stance, the health,
   the ki, the limit gauge, and the arte gauge as a row of points. The
   health turns red below a quarter. Over Limit, the limit gauge turns
   gold, says `OVER LIMIT`, and empties as it ends. Through a mystic
   arte's start-up, `MYSTIC ARTE` stands large in the middle of the
   frame, and a gold star grows at the player's sword hand. The
   companion's boost gauge is in the bottom left, and says
   `BOOST READY` when it is full.
3. **The combo**, such as `12 HITS`, on the right, while two blows or more
   have landed and the combo lasts. It fades as the combo ends.
4. **Each bandit's health and ki**, over its head, while it fights or is
   hurt. A staggered bandit shows `BREAK`, or `FINISH` when a heavy
   attack would finish it. A bandit that winds up a heavy attack shows a
   red `!`, a warning of a strong blow. A bandit that winds up a burst
   attack glows red at the chest, and the glow grows until it strikes. A raging bandit shows `RAGE` under
   its bars.
5. **A dummy's ki**, over its head, while its ki is not full.
6. **The lock's mark**: four gold dots round the locked target's chest.
7. **The numbers and the words** of the blows, which rise and fade.
8. **The edges of the frame**, tinted: blue while the player's perfect
   dodge slows the foes; gold through a mystic arte; and red below a
   quarter of the player's health. A ki pulse rings the player's feet
   with blue light.

A point behind the camera is not drawn.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.scene import Scene
from extensions.village.battle import (
    CHEST,
    FANG_RANGE,
    HEAD,
    POPUP_SECONDS,
    Battle,
)
from extensions.village.combat import (
    BURST,
    COMBO_KEEP,
    FINISH_SHARE,
    LIMIT,
    MYSTIC_ARTE,
    OVER_SECONDS,
    PLUNGE,
    HEAVY,
    HIGH_STANCE,
    LIGHT_ONE,
    LOW_STANCE,
    STAGGER,
    CombatStance,
    Fighter,
    move_data,
)
from extensions.village.companion import BOOST_FULL
from extensions.village.foes import POSTED
from extensions.village.slashes import (
    BURST_TRAIL,
    FOE_TRAIL,
    OVER_TRAIL,
    draw_ring,
    draw_wave,
    glow_star,
)
from extensions.village.hud import (
    GOLD_TEXT,
    SHADOW,
    WHITE_TEXT,
    Rgb,
    draw_text,
    fill_box,
    hud_scale,
    note_alpha,
    text_width,
)
from math.vector3 import Vector3
from std.math import sqrt
from render.framebuffer import Framebuffer
from units.si import METER, SECOND

comptime HEALTH = Rgb(96, 200, 90)
"""The color of a healthy fighter's health."""
comptime WOUNDED = Rgb(225, 70, 50)
"""The color of a fighter's health below a quarter, and of a bandit's."""
comptime KI_COLOR = Rgb(140, 205, 255)
"""The color of ki."""
comptime ARTE_COLOR = Rgb(255, 190, 70)
"""The color of the arte gauge's points."""
comptime LIMIT_COLOR = Rgb(200, 120, 255)
"""The color of the limit gauge while it fills."""
comptime DANGER = Rgb(255, 40, 30)
"""The color of a heavy attack's warning."""
comptime NEAREST = Float32(0.2)
"""How far before the camera a point must be to be drawn, in meters."""
comptime BOOST_COLOR = Rgb(110, 220, 200)
"""The color of the companion's boost gauge while it fills."""
comptime BOLT_COLOR = Vector3(140, 210, 255)
"""The light of a companion's bolt."""
comptime BOLT_GLOW = Float32(0.3)
"""How far a bolt's star reaches, in meters."""
comptime KNIFE_GLOW = Float32(0.15)
"""How far a knife's star reaches, in meters."""
comptime SLOW_TINT = Rgb(70, 140, 255)
"""The tint of the frame's edges while a perfect dodge slows the foes."""
comptime MYSTIC_TINT = Rgb(255, 200, 80)
"""The tint of the frame's edges through a mystic arte."""
comptime HURT_TINT = Rgb(200, 20, 20)
"""The tint of the frame's edges below a quarter of health."""
comptime EDGE = Float32(0.55)
"""How far from the middle of the frame its edges' tint begins, as a share
of the way to a corner."""
comptime PULSE_FLASH = Float32(0.3)
"""How long a ki pulse's ring spreads and fades, in seconds."""
comptime RING_SECONDS = Float32(0.3)
"""How long a plunge's ring spreads and fades, in seconds."""
comptime GLOW_REACH = Float32(0.35)
"""How far a burst attack's red glow reaches from the chest as it
begins, in meters: half a man's shoulders."""


def stance_label(stance: CombatStance) -> String:
    """Return what the display calls a stance.

    Args:
        stance: The stance.

    Returns:
        "HIGH STANCE", "LOW STANCE" or "MID STANCE".
    """
    if stance == HIGH_STANCE:
        return "HIGH STANCE"
    if stance == LOW_STANCE:
        return "LOW STANCE"
    return "MID STANCE"


def draw_bar(
    mut frame: Framebuffer,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    share: Float32,
    color: Rgb,
):
    """Draw a gauge: a dark box, filled from the left by a share.

    Args:
        frame: The frame.
        x: The left of the box, in pixels.
        y: Its top, in pixels.
        width: Its width, in pixels.
        height: Its height, in pixels.
        share: How full it is, from 0 to 1.
        color: The fill's color.
    """
    var full = Int(Float32(width) * max(Float32(0), min(Float32(1), share)))
    fill_box(frame, x - 1, y - 1, x + width + 1, y + height + 1, SHADOW, 0.6)
    fill_box(frame, x, y, x + full, y + height, color, 1)


def on_screen(
    camera: PerspectiveCamera,
    look: Vector3,
    at: Vector3,
    width: Int,
    height: Int,
) raises -> Optional[Vector3]:
    """Return where a point lands on the frame, if it is before the camera.

    Args:
        camera: The camera.
        look: The way the camera looks, of length one.
        at: The point, in world space.
        width: The frame's width, in pixels.
        height: The frame's height, in pixels.

    Returns:
        The point's pixel, x and y, or None for a point less than
        `NEAREST` before the camera.

    Raises:
        Error: If the camera or the frame's size is not valid.
    """
    var off = at - camera.position
    if off.x * look.x + off.y * look.y + off.z * look.z < NEAREST:
        return None
    return camera.project(at, width, height)


def _centered(
    mut frame: Framebuffer,
    x: Int,
    y: Int,
    text: String,
    scale: Int,
    color: Rgb,
    alpha: Float32,
):
    """Draw a line of text centered on a pixel's x."""
    draw_text(
        frame, x - text_width(text, scale) // 2, y, text, scale, color, alpha
    )


def _gauges(mut frame: Framebuffer, battle: Battle, scale: Int):
    """Draw the player's stance, health, ki and arte gauge."""
    ref f = battle.fighter
    var margin = 6 * scale
    var width = 72 * scale
    var x = frame.width - margin - width
    var y = frame.height - margin - 4 * scale
    # The arte gauge: one box a point, filled by its share.
    var points = Int(f.parameters.arte_points + 0.5)
    var pip = 6 * scale
    for k in range(points):
        var share = f.arte - Float32(k)
        draw_bar(
            frame,
            x + width - (points - k) * (pip + 2 * scale),
            y,
            pip,
            3 * scale,
            share,
            ARTE_COLOR,
        )
    if points > 0:
        draw_text(frame, x, y - 2 * scale, "AG", scale, ARTE_COLOR, 1)
    y -= 7 * scale
    var share = f.limit / LIMIT
    var color = LIMIT_COLOR
    var label = String("OL")
    if f.over > 0:
        share = f.over / OVER_SECONDS
        color = GOLD_TEXT
        label = "OVER LIMIT"
    draw_bar(frame, x, y, width, 2 * scale, share, color)
    draw_text(
        frame,
        x - text_width(label, scale) - 4 * scale,
        y - 2 * scale,
        label,
        scale,
        color,
        1,
    )
    y -= 10 * scale
    draw_bar(frame, x, y, width, 3 * scale, f.ki / f.parameters.ki, KI_COLOR)
    draw_text(frame, x - 16 * scale, y - 2 * scale, "KI", scale, KI_COLOR, 1)
    y -= 12 * scale
    var health = f.health / f.parameters.health
    var hue = HEALTH if health >= 0.25 else WOUNDED
    draw_bar(frame, x, y, width, 4 * scale, health, hue)
    draw_text(frame, x - 16 * scale, y - scale, "HP", scale, hue, 1)
    var count = String(Int(f.health + 0.5), "/", Int(f.parameters.health))
    var right = x + width
    y -= 10 * scale
    draw_text(
        frame, right - text_width(count, scale), y, count, scale, WHITE_TEXT, 1
    )
    var stance = stance_label(f.stance)
    y -= 10 * scale
    draw_text(
        frame, right - text_width(stance, scale), y, stance, scale, GOLD_TEXT, 1
    )


def _ring(
    mut frame: Framebuffer,
    battle: Battle,
    scene: Scene,
    camera: PerspectiveCamera,
    look: Vector3,
) raises:
    """Ring the ground with light as the player's plunge strikes: it spreads
    to the plunge's reach over `RING_SECONDS`, and fades."""
    ref f = battle.fighter
    if f.move != PLUNGE:
        return
    var data = move_data(PLUNGE)
    var share = (f.clock - data.startup.to(SECOND)) / RING_SECONDS
    if share < 0 or share > 1:
        return
    var feet = scene.world_matrix(battle.trail.nodes[PLUNGE.value].value())
    var at = feet.transform_point(Vector3(0, 0.05, 0))
    var radius = data.reach.to(METER) * (0.3 + 0.7 * share)
    draw_ring(frame, camera, look, at, radius, 1 - share)


def tint_edges(mut frame: Framebuffer, color: Rgb, strength: Float32):
    """Tint the edges of a frame toward a color, more toward its corners.

    Args:
        frame: The frame.
        color: The tint.
        strength: How much of the tint covers the corners, from 0 to 1.
            Nothing is tinted within `EDGE` of the way from the middle to
            a corner.
    """
    var cx = Float32(frame.width) / 2
    var cy = Float32(frame.height) / 2
    var tint: List[Float32] = [
        Float32(color.r),
        Float32(color.g),
        Float32(color.b),
    ]
    # A frame's width and height are positive.
    for y in range(frame.height):  # pragma: no branch
        var dy = (Float32(y) + 0.5 - cy) / cy
        for x in range(frame.width):  # pragma: no branch
            var dx = (Float32(x) + 0.5 - cx) / cx
            var reach = sqrt((dx * dx + dy * dy) / 2)
            if reach <= EDGE:
                continue
            var share = (reach - EDGE) / (1 - EDGE)
            var w = min(Float32(1), share * share) * strength
            var at = (y * frame.width + x) * 4
            for k in range(3):  # pragma: no branch
                var mixed = Float32(frame.pixels[at + k]) * (1 - w)
                frame.pixels[at + k] = UInt8(Int(mixed + tint[k] * w + 0.5))


def _edges(
    mut frame: Framebuffer,
    battle: Battle,
    scene: Scene,
    camera: PerspectiveCamera,
    look: Vector3,
) raises:
    """Tint the edges of the frame for the slowed foes, a mystic arte or
    low health, and ring the player's feet after a ki pulse."""
    ref f = battle.fighter
    if f.move == MYSTIC_ARTE:
        tint_edges(frame, MYSTIC_TINT, 0.35)
    elif battle.slow > 0:
        tint_edges(frame, SLOW_TINT, 0.4 * min(Float32(1), battle.slow * 5))
    if f.health > 0 and f.health < 0.25 * f.parameters.health:
        tint_edges(frame, HURT_TINT, 0.3)
    if battle.pulsed >= 0 and battle.pulsed < PULSE_FLASH:
        var share = battle.pulsed / PULSE_FLASH
        var node = battle.trail.nodes[LIGHT_ONE.value].value()
        var feet = scene.world_matrix(node).transform_point(Vector3(0, 0.05, 0))
        draw_ring(frame, camera, look, feet, 0.6 + share, 1 - share)


def _star(
    mut frame: Framebuffer,
    camera: PerspectiveCamera,
    look: Vector3,
    at: Vector3,
    size: Float32,
    color: Vector3,
) raises:
    """Add a star of light at a point before the camera, reaching `size`
    meters from it, and three pixels at least."""
    var seen = on_screen(camera, look, at, frame.width, frame.height)
    if not seen:
        return
    var center = seen.value()
    var top = camera.project(
        at + Vector3(0, size, 0), frame.width, frame.height
    )
    var reach = max(Float32(3), abs(top.y - center.y))
    glow_star(frame, Vector3(center.x, center.y, 1), reach, color)


def _boost(mut frame: Framebuffer, battle: Battle, scale: Int):
    """Draw the companion's boost gauge, in the bottom left."""
    for k in range(len(battle.allies)):
        ref mind = battle.allies[k].mind
        var margin = 6 * scale
        var y = frame.height - margin - 3 * scale
        var color = BOOST_COLOR
        var label = String("BOOST")
        if mind.ready():
            color = GOLD_TEXT
            label = "BOOST READY"
        draw_bar(
            frame,
            margin,
            y,
            48 * scale,
            3 * scale,
            mind.boost / BOOST_FULL,
            color,
        )
        draw_text(frame, margin, y - 9 * scale, label, scale, color, 1)


def _glow(
    mut frame: Framebuffer,
    camera: PerspectiveCamera,
    look: Vector3,
    feet: Vector3,
    fighter: Fighter,
) raises:
    """Glow red at the chest of a fighter that winds up a burst attack:
    a star that grows through the start-up, as wide as the shoulders at
    first and twice as wide as it strikes."""
    var chest = feet + Vector3(0, CHEST, 0)
    var at = on_screen(camera, look, chest, frame.width, frame.height)
    if not at:
        return
    var center = at.value()
    var top = camera.project(
        chest + Vector3(0, GLOW_REACH, 0), frame.width, frame.height
    )
    var startup = move_data(BURST).startup.to(SECOND) * fighter.pace
    var grown = 1 + fighter.clock / startup
    var reach = abs(top.y - center.y) * grown
    glow_star(frame, Vector3(center.x, center.y, 0.9), reach, BURST_TRAIL)


def _mystic(
    mut frame: Framebuffer,
    battle: Battle,
    scene: Scene,
    camera: PerspectiveCamera,
    look: Vector3,
    scale: Int,
) raises:
    """Show a mystic arte's start-up: its name, large in the middle of the
    frame, and a gold star that grows at the player's sword hand."""
    ref f = battle.fighter
    var startup = move_data(MYSTIC_ARTE).startup.to(SECOND) * f.pace
    if f.clock >= startup:
        return
    var share = f.clock / startup
    var title = String("MYSTIC ARTE")
    var big = scale * 3
    draw_text(
        frame,
        (frame.width - text_width(title, big)) // 2,
        frame.height // 4,
        title,
        big,
        GOLD_TEXT,
        1,
    )
    var at = on_screen(
        camera,
        look,
        scene.world_matrix(battle.arms.held).transform_point(Vector3(0, 0, 0)),
        frame.width,
        frame.height,
    )
    if not at:
        return
    var center = at.value()
    var reach = Float32(frame.height) * (0.1 + 0.3 * share)
    glow_star(frame, Vector3(center.x, center.y, 1), reach, OVER_TRAIL)


def draw_battle(
    mut frame: Framebuffer,
    battle: Battle,
    scene: Scene,
    camera: PerspectiveCamera,
    look: Vector3,
) raises:
    """Draw what a fight shows over a frame: see the module's list.

    Args:
        frame: The frame, the window's size.
        battle: The fight.
        scene: The scene, updated, that the fight is in.
        camera: The camera the frame was drawn from.
        look: The way the camera looks, of length one.

    Raises:
        Error: If the camera or the frame's size is not valid.
    """
    var scale = hud_scale(frame.height)
    var w = frame.width
    var h = frame.height
    battle.trail.draw(frame, scene, camera, look)
    for index in range(len(battle.people)):
        battle.people[index].trail.draw(frame, scene, camera, look)
    for wave in battle.waves:
        var glow = 1 - 0.6 * wave.gone / FANG_RANGE
        draw_wave(frame, camera, look, wave.at, wave.way, glow)
    for bolt in battle.bolts:
        var color = OVER_TRAIL if bolt.boosted else BOLT_COLOR
        _star(frame, camera, look, bolt.at, BOLT_GLOW, color)
    for knife in battle.knives:
        _star(frame, camera, look, knife.at, KNIFE_GLOW, FOE_TRAIL)
    _ring(frame, battle, scene, camera, look)
    _edges(frame, battle, scene, camera, look)
    _gauges(frame, battle, scale)
    _boost(frame, battle, scale)
    ref f = battle.fighter
    if f.move == MYSTIC_ARTE:
        _mystic(frame, battle, scene, camera, look, scale)
    if f.combo >= 2:
        var alpha = note_alpha(f.combo_age, COMBO_KEEP)
        var hits = String(f.combo, " HITS")
        draw_text(
            frame,
            w - 6 * scale - text_width(hits, scale * 2),
            h * 2 // 5,
            hits,
            scale * 2,
            GOLD_TEXT,
            alpha,
        )
    var bar = 30 * scale
    for index in range(len(battle.foes)):
        ref foe = battle.foes[index]
        if foe.down >= 0:
            continue
        var hurt = foe.fighter.health < foe.fighter.parameters.health
        if foe.brain.state == POSTED and not hurt:
            continue
        var over = on_screen(
            camera,
            look,
            foe.character.position + Vector3(0, HEAD + 0.2, 0),
            w,
            h,
        )
        if not over:
            continue
        var x = Int(over.value().x) - bar // 2
        var y = Int(over.value().y)
        ref p = foe.fighter.parameters
        draw_bar(
            frame, x, y, bar, 2 * scale, foe.fighter.health / p.health, WOUNDED
        )
        draw_bar(
            frame,
            x,
            y + 3 * scale,
            bar,
            scale,
            foe.fighter.ki / p.ki,
            KI_COLOR,
        )
        var middle = x + bar // 2
        if foe.fighter.move == STAGGER:
            var word = String("BREAK")
            if foe.fighter.health <= FINISH_SHARE * p.health:
                word = "FINISH"
            _centered(frame, middle, y - 9 * scale, word, scale, GOLD_TEXT, 1)
        elif foe.fighter.move == HEAVY:
            var startup = move_data(HEAVY).startup.to(SECOND) * foe.fighter.pace
            if foe.fighter.clock < startup:
                _centered(
                    frame, middle, y - 11 * scale, "!", scale * 2, DANGER, 1
                )
        elif foe.fighter.bursting():
            _glow(frame, camera, look, foe.character.position, foe.fighter)
        if foe.fighter.raging():
            _centered(frame, middle, y + 6 * scale, "RAGE", scale, DANGER, 1)
    for index in range(len(battle.dummies)):
        ref practice = battle.dummies[index]
        ref fighter = practice.fighter
        if fighter.ki >= fighter.parameters.ki:
            continue
        var over = on_screen(
            camera, look, practice.dummy.where() + Vector3(0, 1.75, 0), w, h
        )
        if not over:
            continue
        draw_bar(
            frame,
            Int(over.value().x) - bar // 2,
            Int(over.value().y),
            bar,
            scale,
            fighter.ki / fighter.parameters.ki,
            KI_COLOR,
        )
    if battle.lock >= 0:
        var mark = on_screen(
            camera,
            look,
            battle.target_at(battle.lock) + Vector3(0, CHEST, 0),
            w,
            h,
        )
        if mark:
            var x = Int(mark.value().x)
            var y = Int(mark.value().y)
            var r = 7 * scale
            var d = scale + 1
            for corner in [
                (-r, 0),
                (r, 0),
                (0, -r),
                (0, r),
            ]:  # pragma: no branch
                var cx = x + corner[0]
                var cy = y + corner[1]
                fill_box(frame, cx - d, cy - d, cx + d, cy + d, GOLD_TEXT, 1)
    for popup in battle.popups:
        var at = on_screen(camera, look, popup.at, w, h)
        if not at:
            continue
        _centered(
            frame,
            Int(at.value().x),
            Int(at.value().y),
            popup.text,
            scale,
            popup.color,
            note_alpha(popup.age, POPUP_SECONDS),
        )
