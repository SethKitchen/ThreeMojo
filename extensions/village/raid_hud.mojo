# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the raid, the styles and the combos write over the frame, with the
font of `extensions.village.hud`. `extensions.village.battle_hud` calls
`draw_raid` after its own parts.

1. **The zones.** Each attack that winds up lays its zone on the ground in
   red light: its edge glows, and its inside fills from the middle as the
   wind-up goes on, so the fill reaches the edge as it strikes.
2. **The mark.** A member marked by a rockfall stands in a gold ring as
   wide as the boulder's share, with `STACK` and the seconds left over
   them.
3. **The boss.** At the top of the frame: the warden's name, its health,
   its poise, its phase, and the time until it enrages. A staggered warden
   shows `STAGGERED`, and `HEAVY: LINKED STRIKE` until a linked strike
   strikes it.
4. **The party.** On the left: each raider who joined, their role and
   their health. A fallen raider shows `DOWN`, and how far a revive has
   gone.
5. **The style.** Over the player's gauges: the style's name, and for
   magic, the mana.
6. **The routes.** Over the combo counter: each combo the player is on
   the way to, with its keys done in gold, the next in white and the rest
   in gray; a key that must be on the beat has a dot under it. A press on
   the beat flashes `ON BEAT`.
7. **The book.** While the book shows: each combo of the style, its tier,
   its keys and its rank; or the level that teaches it, or `SPECIALTY`.
8. **The missiles.** Each arrow, spell bolt and orb as a star of light.
"""

from cameras.perspective_camera import PerspectiveCamera
from extensions.village.battle import CHEST, Battle
from extensions.village.boss import (
    BOSS_POISE,
    CIRCLE,
    CONE,
    ENRAGE_SECONDS,
    FURY,
    LAST_STAND,
    ROCK_RADIUS,
    Zone,
)
from extensions.village.combos import (
    MASTER,
    MAX_RANK,
    key_name,
    tier_name,
)
from extensions.village.hud import (
    GOLD_TEXT,
    SHADOW,
    WHITE_TEXT,
    Rgb,
    draw_text,
    fill_box,
    text_width,
)
from extensions.village.missiles import ARROW, ORB, SPARK
from extensions.village.party import role_name
from extensions.village.slashes import arc_points, glow_ribbon, glow_star
from extensions.village.styles import MAGIC, style_name
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from std.math import pi

comptime ZONE_LIGHT = Vector3(255, 40, 24)
"""The light of a zone on the ground."""
comptime MARK_LIGHT = Vector3(255, 200, 60)
"""The light of a rockfall's ring."""
comptime ARROW_LIGHT = Vector3(230, 220, 190)
"""The light of an arrow."""
comptime SPARK_LIGHT = Vector3(150, 200, 255)
"""The light of a spell bolt."""
comptime ORB_LIGHT = Vector3(200, 120, 255)
"""The light of a blast's orb."""
comptime MANA_COLOR = Rgb(90, 140, 255)
"""The color of the mana gauge."""
comptime POISE_COLOR = Rgb(240, 200, 90)
"""The color of the warden's poise."""
comptime BOSS_RED = Rgb(200, 40, 30)
"""The color of the warden's health."""
comptime DIM_TEXT = Rgb(140, 132, 118)
"""The color of a combo's keys still to come, and of a locked combo."""
comptime BEAT_TEXT = Rgb(255, 120, 60)
"""The color of the dot under a key on the beat, and of `ON BEAT`."""
comptime BEAT_FLASH = Float32(0.4)
"""How long `ON BEAT` shows after a press on the beat, in seconds."""
comptime ZONE_EDGE = Float32(0.9)
"""The share of a zone's size at which its glowing edge begins."""
comptime ROUTES = 3
"""How many routes the display lists at most."""


def zone_corners(zone: Zone, inner: Float32, outer: Float32) -> List[Vector3]:
    """Return the corners of a band of a zone on the ground, as
    `glow_ribbon` reads them.

    Args:
        zone: The zone.
        inner: Where the band begins, as a share of the zone's size: from
            the middle of a circle or the tip of a cone, or from the start
            of a line.
        outer: Where it ends, as a share of the zone's size.

    Returns:
        For a circle and a cone, an inner and an outer corner for each step
        of its arc; for a line, the band's two sides at each step along
        it, between the shares.
    """
    var side = Vector3(zone.way.z, 0, -zone.way.x)
    if zone.shape == CIRCLE:
        return arc_points(
            zone.at,
            Vector3(1, 0, 0),
            Vector3(0, 0, 1),
            0,
            Float32(2 * pi),
            zone.size * inner,
            zone.size * outer,
        )
    if zone.shape == CONE:
        var half = zone.span / 2 * Float32(pi) / 180
        return arc_points(
            zone.at,
            zone.way,
            side,
            -half,
            half,
            zone.size * inner,
            zone.size * outer,
        )
    var out = List[Vector3]()
    var steps = 12
    for k in range(steps + 1):  # pragma: no branch
        var t = inner + (outer - inner) * Float32(k) / Float32(steps)
        var p = zone.at + zone.way * (zone.size * t)
        out.append(p - side * (zone.span / 2))
        out.append(p + side * (zone.span / 2))
    return out^


def _band(
    mut frame: Framebuffer,
    camera: PerspectiveCamera,
    look: Vector3,
    corners: List[Vector3],
    glow: Float32,
    color: Vector3,
) raises:
    """Add a band's light, the same at each step."""
    var light = List[Float32](length=len(corners) // 2, fill=glow)
    glow_ribbon(frame, camera, look, corners, light, color)


def draw_zone(
    mut frame: Framebuffer,
    camera: PerspectiveCamera,
    look: Vector3,
    zone: Zone,
    warning: Float32,
) raises:
    """Lay a zone on the ground in red light: a glowing edge, and an inside
    that fills from the middle as the wind-up goes on.

    Args:
        frame: The frame, the camera's size.
        camera: The camera the frame was drawn from.
        look: The way the camera looks, of length one.
        zone: The zone, a little over the ground.
        warning: How far the attack has wound up, from 0 to 1.

    Raises:
        Error: If the camera or the frame's size is not valid.
    """
    var lifted = zone
    lifted.at = zone.at + Vector3(0, 0.05, 0)
    _band(
        frame,
        camera,
        look,
        zone_corners(lifted, ZONE_EDGE, 1),
        0.85,
        ZONE_LIGHT,
    )
    var fill = max(Float32(0.02), min(Float32(1), warning)) * ZONE_EDGE
    _band(frame, camera, look, zone_corners(lifted, 0, fill), 0.28, ZONE_LIGHT)


def _mark(
    mut frame: Framebuffer,
    battle: Battle,
    camera: PerspectiveCamera,
    look: Vector3,
    scale: Int,
) raises:
    """Ring the member a rockfall marks, and tell the party to gather."""
    for w in range(len(battle.wardens)):
        ref boss = battle.wardens[w].boss
        if boss.marked < 0:
            continue
        var at = battle.feet
        if boss.marked > 0:
            at = battle.members[boss.marked - 1].character.position
        var ring = Zone(
            CIRCLE, at + Vector3(0, 0.06, 0), Vector3(0, 0, 1), ROCK_RADIUS, 0
        )
        _band(frame, camera, look, zone_corners(ring, 0.92, 1), 0.9, MARK_LIGHT)
        var over = camera.project(
            at + Vector3(0, 2.6, 0), frame.width, frame.height
        )
        var off = at - camera.position
        if off.x * look.x + off.y * look.y + off.z * look.z < 0.2:
            continue
        var text = String("STACK ", Int(boss.mark_clock + 0.99))
        draw_text(
            frame,
            Int(over.x) - text_width(text, scale * 2) // 2,
            Int(over.y),
            text,
            scale * 2,
            GOLD_TEXT,
            1,
        )


def _bar(
    mut frame: Framebuffer,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    share: Float32,
    color: Rgb,
):
    """Draw a gauge: a dark box, filled from the left by a share."""
    var full = Int(Float32(width) * max(Float32(0), min(Float32(1), share)))
    fill_box(frame, x - 1, y - 1, x + width + 1, y + height + 1, SHADOW, 0.6)
    fill_box(frame, x, y, x + full, y + height, color, 1)


def _boss_bar(mut frame: Framebuffer, battle: Battle, scale: Int) raises:
    """Draw each warden's name, health, poise, phase and enrage time at the
    top of the frame, while it fights."""
    for w in range(len(battle.wardens)):
        ref boss = battle.wardens[w].boss
        if not boss.engaged or boss.defeated():
            continue
        var width = frame.width * 2 // 5
        var x = (frame.width - width) // 2
        var y = 8 * scale
        var name = String("THE STONE WARDEN")
        draw_text(
            frame,
            (frame.width - text_width(name, scale)) // 2,
            y,
            name,
            scale,
            WHITE_TEXT,
            1,
        )
        y += 9 * scale
        _bar(frame, x, y, width, 4 * scale, boss.health / boss.most, BOSS_RED)
        y += 6 * scale
        _bar(
            frame, x, y, width, scale + 1, boss.poise / BOSS_POISE, POISE_COLOR
        )
        y += 4 * scale
        var phase = String()
        if boss.phase == FURY:
            phase = "FURY"
        elif boss.phase == LAST_STAND:
            phase = "LAST STAND"
        if boss.staggered > 0:
            phase = "STAGGERED"
        if boss.enraged():
            phase = "ENRAGED"
        if phase.byte_length() > 0:
            draw_text(frame, x, y, phase, scale, GOLD_TEXT, 1)
        var left = max(0, Int(ENRAGE_SECONDS - boss.fight_time))
        var clock = String(left // 60, ":", (left % 60) // 10, left % 10)
        draw_text(
            frame,
            x + width - text_width(clock, scale),
            y,
            clock,
            scale,
            WHITE_TEXT,
            1,
        )
        if boss.link_ready():
            var call = String("HEAVY: LINKED STRIKE")
            draw_text(
                frame,
                (frame.width - text_width(call, scale)) // 2,
                y + 9 * scale,
                call,
                scale,
                GOLD_TEXT,
                1,
            )


def _party(mut frame: Framebuffer, battle: Battle, scale: Int) raises:
    """Draw each raider who joined: their role and their health, or `DOWN`
    and the revive."""
    var x = 6 * scale
    var y = frame.height // 3
    var width = 48 * scale
    for k in range(len(battle.members)):
        ref member = battle.members[k]
        if not member.joined:
            continue
        var role = role_name(member.mind.role)
        draw_text(frame, x, y, role, scale, WHITE_TEXT, 1)
        y += 8 * scale
        if member.down >= 0:
            draw_text(frame, x, y, "DOWN", scale, BOSS_RED, 1)
            if member.revive > 0:
                _bar(
                    frame,
                    x + 26 * scale,
                    y + scale,
                    22 * scale,
                    2 * scale,
                    member.revive / 2.5,
                    GOLD_TEXT,
                )
        else:
            ref f = member.fighter
            var share = f.health / f.parameters.health
            var hue = Rgb(96, 200, 90) if share >= 0.25 else BOSS_RED
            _bar(frame, x, y, width, 3 * scale, share, hue)
        y += 8 * scale


def _style(mut frame: Framebuffer, battle: Battle, scale: Int) raises:
    """Draw the style's name over the player's gauges, and the mana for
    magic."""
    ref f = battle.fighter
    var name = style_name(f.style)
    var margin = 6 * scale
    var width = 72 * scale
    var x = frame.width - margin - width
    var y = frame.height - margin - 64 * scale
    draw_text(
        frame,
        x + width - text_width(name, scale),
        y,
        name,
        scale,
        WHITE_TEXT,
        1,
    )
    if f.style == MAGIC:
        y += 8 * scale
        _bar(
            frame,
            x,
            y,
            width,
            2 * scale,
            f.mana / f.parameters.mana,
            MANA_COLOR,
        )
        draw_text(
            frame, x - 16 * scale, y - 2 * scale, "MP", scale, MANA_COLOR, 1
        )


def _routes(mut frame: Framebuffer, battle: Battle, scale: Int) raises:
    """List the combos the player's string is on the way to, and flash a
    press on the beat."""
    var routes = battle.book.routes(battle.tracker, battle.fighter.style)
    var y = frame.height * 2 // 5 - 30 * scale
    var right = frame.width - 6 * scale
    if battle.beat >= 0 and battle.beat < BEAT_FLASH:
        var word = String("ON BEAT")
        draw_text(
            frame,
            right - text_width(word, scale),
            y - 10 * scale,
            word,
            scale,
            BEAT_TEXT,
            1 - battle.beat / BEAT_FLASH,
        )
    var shown = 0
    for index in routes:
        if shown >= ROUTES:
            break
        shown += 1
        ref combo = battle.book.combos[index]
        var done = battle.tracker.progress(combo)
        var line = combo.name + "  "
        var x = right - text_width(line, scale) - 12 * scale * len(combo.keys)
        draw_text(frame, x, y, line, scale, GOLD_TEXT, 1)
        x += text_width(line, scale)
        for k in range(len(combo.keys)):  # pragma: no branch
            var color = DIM_TEXT
            if k < done:
                color = GOLD_TEXT
            elif k == done:
                color = WHITE_TEXT
            var letter = key_name(combo.keys[k])
            draw_text(frame, x, y, letter, scale, color, 1)
            if combo.beats[k]:
                fill_box(
                    frame,
                    x + scale,
                    y + 8 * scale,
                    x + 4 * scale,
                    y + 9 * scale,
                    BEAT_TEXT,
                    1,
                )
            x += 12 * scale
        y += 11 * scale


def _book(mut frame: Framebuffer, battle: Battle, scale: Int) raises:
    """Show the combo book: each combo of the player's style, its tier, its
    keys and its rank, or what teaches it."""
    ref book = battle.book
    var style = battle.fighter.style
    var x = frame.width // 4
    var y = frame.height // 6
    var title = style_name(style) + " COMBOS"
    fill_box(
        frame,
        x - 8 * scale,
        y - 6 * scale,
        frame.width * 3 // 4 + 8 * scale,
        frame.height * 5 // 6,
        SHADOW,
        0.7,
    )
    draw_text(frame, x, y, title, scale * 2, GOLD_TEXT, 1)
    y += 20 * scale
    for k in range(len(book.combos)):  # pragma: no branch
        ref combo = book.combos[k]
        if combo.style != style:
            continue
        var known = book.learned[k]
        var color = WHITE_TEXT if known else DIM_TEXT
        draw_text(frame, x, y, combo.name, scale, color, 1)
        draw_text(
            frame, x + 90 * scale, y, tier_name(combo.tier), scale, color, 1
        )
        var keys = String()
        for j in range(len(combo.keys)):  # pragma: no branch
            keys += key_name(combo.keys[j])
            keys += "' " if combo.beats[j] else " "
        draw_text(frame, x + 150 * scale, y, keys, scale, color, 1)
        var right = String("LEVEL ", combo.level)
        if known:
            right = String("RANK ", book.rank(k), "/", MAX_RANK)
        elif combo.tier == MASTER and style != book.specialty:
            right = "SPECIALTY"
        draw_text(
            frame,
            frame.width * 3 // 4 - text_width(right, scale),
            y,
            right,
            scale,
            GOLD_TEXT if known else DIM_TEXT,
            1,
        )
        y += 12 * scale


def _missiles(
    mut frame: Framebuffer,
    battle: Battle,
    camera: PerspectiveCamera,
    look: Vector3,
) raises:
    """Draw each of the missiles as a star of light."""
    for shot in battle.shots:
        var off = shot.at - camera.position
        if off.x * look.x + off.y * look.y + off.z * look.z < 0.2:
            continue
        var color = ARROW_LIGHT
        var reach = Float32(0.12)
        if shot.kind == SPARK:
            color = SPARK_LIGHT
            reach = 0.3
        elif shot.kind == ORB:
            color = ORB_LIGHT
            reach = 0.55
        var at = camera.project(shot.at, frame.width, frame.height)
        var edge = camera.project(
            shot.at + Vector3(0, reach, 0), frame.width, frame.height
        )
        var radius = abs(at.y - edge.y)
        glow_star(frame, Vector3(at.x, at.y, 1), max(Float32(2), radius), color)
        if shot.kind == ARROW:
            # A streak back along its flight.
            var tail = camera.project(shot.last, frame.width, frame.height)
            var mid = (at + tail) / 2
            glow_star(
                frame,
                Vector3(mid.x, mid.y, 0.6),
                max(Float32(1.5), radius * 0.6),
                color,
            )


def draw_raid(
    mut frame: Framebuffer,
    battle: Battle,
    camera: PerspectiveCamera,
    look: Vector3,
    scale: Int,
) raises:
    """Draw what the raid, the styles and the combos show: see the module's
    list.

    Args:
        frame: The frame, the window's size.
        battle: The fight.
        camera: The camera the frame was drawn from.
        look: The way the camera looks, of length one.
        scale: The size of a dot of the font, in pixels.

    Raises:
        Error: If the camera or the frame's size is not valid.
    """
    for w in range(len(battle.wardens)):
        ref boss = battle.wardens[w].boss
        var warning = boss.warning()
        if warning > 0 and boss.zone.size > 0:
            draw_zone(frame, camera, look, boss.zone, warning)
    _mark(frame, battle, camera, look, scale)
    _missiles(frame, battle, camera, look)
    _boss_bar(frame, battle, scale)
    _party(frame, battle, scale)
    _style(frame, battle, scale)
    _routes(frame, battle, scale)
    if battle.reading:
        _book(frame, battle, scale)
