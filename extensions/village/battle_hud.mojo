# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a fight writes over the frame, with the font of
`extensions.village.hud`.

`draw_battle` draws eight things:

1. **The flashes** where blows land, each a star and a ring of light:
   see `extensions.village.slashes.draw_impact`.
   **The trails** of the swings, the ground wave's waves, the
   companion's bolts, the throwers' knives and a plunge's ring, as light
   added to the frame: see `extensions.village.slashes`. A wave dims as
   it runs. A knife is a small orange star. A plunge's
   ring spreads over the ground from the player's feet, and fades. A bolt is a blue
   star, or a gold one for a assist attack.
2. **The player's gauges**, in the bottom right, on a dark panel: the
   stance, the health, the stamina, the limit gauge, and the special
   gauge as a row of points. The health turns red below a quarter. What a
   blow takes stays pale on the health bar for a moment, then drains. In a surge, the limit gauge turns
   gold, says `SURGE`, and empties as it ends. Through a ultimate
   special's start-up, `ULTIMATE` stands large in the middle of the
   frame, and a gold star grows at the player's sword hand. The
   companion's assist gauge is in the bottom left, and says
   `ASSIST READY` when it is full.
3. **The combo**, such as `12 HITS`, on the right, while two blows or more
   have landed and the combo lasts. It fades as the combo ends.
4. **Each bandit's health and stamina**, over its head, while it fights or is
   hurt. What a blow takes stays pale on the health bar, then drains. A staggered bandit shows `BREAK`, or `FINISH` when a heavy
   attack would finish it. A bandit that winds up a heavy attack shows a
   red `!`, a warning of a strong blow. A bandit that winds up a piercing
   attack glows red at the chest, and the glow grows until it strikes. A raging bandit shows `RAGE` under
   its bars.
5. **A dummy's stamina**, over its head, while its stamina is not full.
6. **The lock's mark**: four gold dots around the locked target's chest.
7. **The numbers and the words** of the blows, which rise and fade,
   ringed dark so they read over the sky. A number stands half again as
   large as a word, a critical one twice as large, and each pops larger
   as it appears. They stand under `TOP_BAND`, so they do not cross the
   compass.
8. **The edges of the frame**, tinted: blue while the player's perfect
   dodge slows the foes; gold through an ultimate; and red below a
   quarter of the player's health. A stamina recovery rings the player's feet
   with blue light.
9. **The way of each blow on the player**, for `HURT_SECONDS`: a red arc
   near the frame's edge, toward where the blow came from. It fades.

A point behind the camera is not drawn.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.scene import Scene
from extensions.village.battle import (
    CHEST,
    WAVE_RANGE,
    HEAD,
    HURT_SECONDS,
    POPUP_SECONDS,
    Battle,
)
from extensions.village.combat import (
    PIERCE,
    COMBO_KEEP,
    FINISH_SHARE,
    LIMIT,
    ULTIMATE,
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
from extensions.village.companion import ASSIST_FULL
from extensions.village.foes import POSTED, bandit_fighter
from extensions.village.effects_hud import draw_effects
from extensions.village.raid_hud import draw_raid
from extensions.village.slashes import (
    PIERCE_TRAIL,
    draw_impact,
    FOE_TRAIL,
    OVER_TRAIL,
    draw_ring,
    draw_wave,
    glow_star,
)
from extensions.village.hud import (
    PANEL_ALPHA,
    clear_span,
    GOLD_TEXT,
    SHADOW,
    WHITE_TEXT,
    Rgb,
    draw_outlined,
    draw_text,
    fill_box,
    hud_scale,
    note_alpha,
    text_width,
)
from math.vector3 import Vector3
from render.tasks import TaskGroup
from renderers.renderer import available_workers
from std.math import sqrt
from render.framebuffer import Framebuffer
from units.si import METER, SECOND

comptime HEALTH = Rgb(96, 200, 90)
"""The color of a healthy fighter's health."""
comptime WOUNDED = Rgb(225, 70, 50)
"""The color of a fighter's health below a quarter, and of a bandit's."""
comptime STAMINA_COLOR = Rgb(140, 205, 255)
"""The color of stamina."""
comptime SPECIAL_COLOR = Rgb(255, 190, 70)
"""The color of the special gauge's points."""
comptime LIMIT_COLOR = Rgb(200, 120, 255)
"""The color of the limit gauge while it fills."""
comptime DANGER = Rgb(255, 40, 30)
"""The color of a heavy attack's warning."""
comptime NEAREST = Float32(0.2)
"""How far before the camera a point must be to be drawn, in meters."""
comptime ASSIST_COLOR = Rgb(110, 220, 200)
"""The color of the companion's assist gauge while it fills."""
comptime BOLT_COLOR = Vector3(140, 210, 255)
"""The light of a companion's bolt."""
comptime BOLT_GLOW = Float32(0.3)
"""How far a bolt's star reaches, in meters."""
comptime KNIFE_GLOW = Float32(0.15)
"""How far a knife's star reaches, in meters."""
comptime SLOW_TINT = Rgb(70, 140, 255)
"""The tint of the frame's edges while a perfect dodge slows the foes."""
comptime ULTIMATE_TINT = Rgb(255, 200, 80)
"""The tint of the frame's edges through an ultimate."""
comptime HURT_TINT = Rgb(200, 20, 20)
"""The tint of the frame's edges below a quarter of health."""
comptime EDGE = Float32(0.55)
"""How far from the middle of the frame its edges' tint begins, as a share
of the way to a corner."""
comptime PULSE_FLASH = Float32(0.3)
"""How long a stamina recovery's ring spreads and fades, in seconds."""
comptime RING_SECONDS = Float32(0.3)
"""How long a plunge's ring spreads and fades, in seconds."""
comptime GLOW_REACH = Float32(0.35)
"""How far a piercing attack's red glow reaches from the chest as it
begins, in meters: half a man's shoulders."""
comptime HURT_REACH = Float32(0.4)
"""How far from the frame's middle a blow's mark stands, as a share of
the frame's width across and of its height down."""
comptime HURT_SPREAD = Float32(0.2)
"""How far a blow's mark reaches each side of its middle along its arc, as
the sine of the angle from the frame's middle."""
comptime HURT_THICK = 4
"""Half the width of a blow's mark at its middle, in dots of the display's
font."""
comptime CHIP_COLOR = Rgb(255, 236, 196)
"""The color of the health a blow took, behind the health on a bar."""
comptime POP_SECONDS = Float32(0.12)
"""How long a number stands larger as it appears, in seconds."""
comptime POPUP_FADE = Float32(0.3)
"""How long a number or a word takes to fade at its end, in seconds."""
comptime BAR_GAP = 2
"""How many dots of the display's font stand between two foes' bars that
`stack_boxes` sets one over the other."""
comptime POPUP_GAP = 1
"""How many dots of a number's font stand between two numbers that
`stack_boxes` sets one over the other."""
comptime TOP_BAND = 46
"""How many dots of the heads-up display's font the compass, its caption
and the target panel take at the top of the frame. The numbers and the
words of the blows stand under them."""
comptime BOSS_ROOM = 40
"""How many dots of the heads-up display's font a fighting warden's bars
take at the top of the frame."""


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
    chip: Float32 = -1,
):
    """Draw a gauge: a dark box, filled from the left by a share.

    A gauge of health shows what a blow just took: past the share, up to
    `chip`, it is filled pale, and the pale part drains away. The fill's
    top row is lighter, so the bar reads as raised.

    Args:
        frame: The frame.
        x: The left of the box, in pixels.
        y: Its top, in pixels.
        width: Its width, in pixels.
        height: Its height, in pixels.
        share: How full it is, from 0 to 1.
        color: The fill's color.
        chip: How full it was a moment ago, from 0 to 1; less than
            `share` for none.
    """
    var full = Int(Float32(width) * max(Float32(0), min(Float32(1), share)))
    var was = Int(Float32(width) * max(Float32(0), min(Float32(1), chip)))
    fill_box(frame, x - 1, y - 1, x + width + 1, y + height + 1, SHADOW, 0.6)
    if was > full:
        fill_box(frame, x + full, y, x + was, y + height, CHIP_COLOR, 0.9)
    fill_box(frame, x, y, x + full, y + height, color, 1)
    if height >= 3:
        var light = Rgb(255, 255, 255)
        fill_box(frame, x, y, x + full, y + max(1, height // 4), light, 0.3)


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
    """Draw a line of text centered on a pixel's x, outlined so that it
    reads over the sky."""
    draw_outlined(
        frame, x - text_width(text, scale) // 2, y, text, scale, color, alpha
    )


def _gauges(mut frame: Framebuffer, battle: Battle, scale: Int):
    """Draw the player's stance, health, stamina and special gauge."""
    ref f = battle.fighter
    var margin = 6 * scale
    var width = 72 * scale
    var x = frame.width - margin - width
    var y = frame.height - margin - 4 * scale
    # A dark panel behind the gauges, so they read over a bright sky.
    fill_box(
        frame,
        x - 36 * scale,
        y - 56 * scale,
        frame.width - margin + 3 * scale,
        y + 6 * scale,
        SHADOW,
        PANEL_ALPHA,
    )
    # The special gauge: one box a point, filled by its share.
    var points = Int(f.parameters.special_points + 0.5)
    var pip = 6 * scale
    for k in range(points):
        var share = f.special - Float32(k)
        draw_bar(
            frame,
            x + width - (points - k) * (pip + 2 * scale),
            y,
            pip,
            3 * scale,
            share,
            SPECIAL_COLOR,
        )
    if points > 0:
        draw_text(frame, x, y - 2 * scale, "SP", scale, SPECIAL_COLOR, 1)
    y -= 7 * scale
    var share = f.limit / LIMIT
    var color = LIMIT_COLOR
    var label = String("SG")
    if f.over > 0:
        share = f.over / OVER_SECONDS
        color = GOLD_TEXT
        label = "SURGE"
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
    draw_bar(
        frame,
        x,
        y,
        width,
        3 * scale,
        f.stamina / f.parameters.stamina,
        STAMINA_COLOR,
    )
    draw_text(
        frame, x - 16 * scale, y - 2 * scale, "ST", scale, STAMINA_COLOR, 1
    )
    y -= 12 * scale
    var health = f.health / f.parameters.health
    var hue = HEALTH if health >= 0.25 else WOUNDED
    var chip = f.chip / f.parameters.health
    draw_bar(frame, x, y, width, 4 * scale, health, hue, chip)
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
    var tasks = max(1, min(available_workers() * 2, frame.height))
    var group = TaskGroup()
    for t in range(tasks):  # pragma: no branch
        group.create_task(
            _tint_task(
                frame.pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                frame.width,
                frame.height,
                color,
                strength,
                t * frame.height // tasks,
                (t + 1) * frame.height // tasks,
            )
        )
    group.wait()


__async def _tint_task(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    width: Int,
    height: Int,
    color: Rgb,
    strength: Float32,
    first: Int,
    past: Int,
):
    """Tint rows `first` to `past`, past the clear middle."""
    var cx = Float32(width) / 2
    var cy = Float32(height) / 2
    var tr = Float32(color.r)
    var tg = Float32(color.g)
    var tb = Float32(color.b)
    for y in range(first, past):  # pragma: no branch
        var dy = (Float32(y) + 0.5 - cy) / cy
        var clear = clear_span(y, width, height, EDGE * 1.4142)
        var x = 0
        while x < width:
            if x == clear[0] and clear[1] > clear[0]:
                x = clear[1]
                continue
            var dx = (Float32(x) + 0.5 - cx) / cx
            var reach = sqrt((dx * dx + dy * dy) / 2)
            if reach > EDGE:
                var share = (reach - EDGE) / (1 - EDGE)
                var w = min(Float32(1), share * share) * strength
                var at = (y * width + x) * 4
                pixels[unsafe_offset=at] = UInt8(
                    Int(
                        Float32(pixels[unsafe_offset=at]) * (1 - w)
                        + tr * w
                        + 0.5
                    )
                )
                pixels[unsafe_offset=at + 1] = UInt8(
                    Int(
                        Float32(pixels[unsafe_offset=at + 1]) * (1 - w)
                        + tg * w
                        + 0.5
                    )
                )
                pixels[unsafe_offset=at + 2] = UInt8(
                    Int(
                        Float32(pixels[unsafe_offset=at + 2]) * (1 - w)
                        + tb * w
                        + 0.5
                    )
                )
            x += 1


def _edges(
    mut frame: Framebuffer,
    battle: Battle,
    scene: Scene,
    camera: PerspectiveCamera,
    look: Vector3,
) raises:
    """Tint the edges of the frame for the slowed foes, an ultimate or
    low health, and ring the player's feet after a stamina recovery."""
    ref f = battle.fighter
    if f.move == ULTIMATE:
        tint_edges(frame, ULTIMATE_TINT, 0.35)
    elif battle.slow > 0:
        tint_edges(frame, SLOW_TINT, 0.4 * min(Float32(1), battle.slow * 5))
    if f.health > 0 and f.health < 0.25 * f.parameters.health:
        tint_edges(frame, HURT_TINT, 0.3)
    draw_hurts(frame, battle, look)
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


def _assist(mut frame: Framebuffer, battle: Battle, scale: Int):
    """Draw the companion's assist gauge, in the bottom left."""
    for k in range(len(battle.allies)):
        ref mind = battle.allies[k].mind
        var margin = 6 * scale
        var y = frame.height - margin - 3 * scale
        var color = ASSIST_COLOR
        var label = String("ASSIST")
        if mind.ready():
            color = GOLD_TEXT
            label = "ASSIST READY"
        draw_bar(
            frame,
            margin,
            y,
            48 * scale,
            3 * scale,
            mind.assist / ASSIST_FULL,
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
    """Glow red at the chest of a fighter that winds up a piercing attack:
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
    var startup = move_data(PIERCE).startup.to(SECOND) * fighter.pace
    var grown = 1 + fighter.clock / startup
    var reach = abs(top.y - center.y) * grown
    glow_star(frame, Vector3(center.x, center.y, 0.9), reach, PIERCE_TRAIL)


def _ultimate(
    mut frame: Framebuffer,
    battle: Battle,
    scene: Scene,
    camera: PerspectiveCamera,
    look: Vector3,
    scale: Int,
) raises:
    """Show an ultimate's start-up: its name, large in the middle of the
    frame, and a gold star that grows at the player's sword hand."""
    ref f = battle.fighter
    var startup = move_data(ULTIMATE).startup.to(SECOND) * f.pace
    if f.clock >= startup:
        return
    var share = f.clock / startup
    var title = String("ULTIMATE")
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
        scene.world_matrix(
            battle.arms.held[battle.fighter.style.value]
        ).transform_point(Vector3(0, 0, 0)),
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
        var glow = 1 - 0.6 * wave.gone / WAVE_RANGE
        draw_wave(frame, camera, look, wave.at, wave.way, glow)
    for bolt in battle.bolts:
        var color = OVER_TRAIL if bolt.assisted else BOLT_COLOR
        _star(frame, camera, look, bolt.at, BOLT_GLOW, color)
    for knife in battle.knives:
        _star(frame, camera, look, knife.at, KNIFE_GLOW, FOE_TRAIL)
    for impact in battle.impacts:
        draw_impact(frame, camera, look, impact)
    _ring(frame, battle, scene, camera, look)
    _edges(frame, battle, scene, camera, look)
    _gauges(frame, battle, scale)
    _assist(frame, battle, scale)
    ref f = battle.fighter
    if f.move == ULTIMATE:
        _ultimate(frame, battle, scene, camera, look, scale)
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
    # The bars' boxes, the farthest foe first, so that a nearer foe's bar
    # keeps its place and a farther one's stands over it.
    var foes = List[Int]()
    var depths = List[Float32]()
    var bar_lefts = List[Int]()
    var bar_tops = List[Int]()
    for index in range(len(battle.foes)):
        ref foe = battle.foes[index]
        if foe.down >= 0:
            continue
        var hurt = foe.fighter.health < foe.fighter.parameters.health
        if foe.brain.state == POSTED and not hurt:
            continue
        var head = foe.character.position + Vector3(0, HEAD + 0.2, 0)
        var over = on_screen(camera, look, head, w, h)
        if not over:
            continue
        var off = head - camera.position
        var depth = off.x * look.x + off.y * look.y + off.z * look.z
        # Insert it before the first nearer one.
        var k = 0
        while k < len(depths) and depths[k] >= depth:
            k += 1
        foes.insert(k, index)
        depths.insert(k, depth)
        bar_lefts.insert(k, Int(over.value().x) - bar // 2)
        bar_tops.insert(k, Int(over.value().y))
    var bar_widths = List[Int](length=len(foes), fill=bar)
    var bar_heights = List[Int](length=len(foes), fill=(4 + BAR_GAP) * scale)
    bar_tops = stack_boxes(bar_lefts, bar_tops, bar_widths, bar_heights)
    for k in range(len(foes)):
        ref foe = battle.foes[foes[k]]
        var x = bar_lefts[k]
        var y = bar_tops[k]
        ref p = foe.fighter.parameters
        draw_bar(
            frame,
            x,
            y,
            bar,
            2 * scale,
            foe.fighter.health / p.health,
            WOUNDED,
            foe.fighter.chip / p.health,
        )
        draw_bar(
            frame,
            x,
            y + 3 * scale,
            bar,
            scale,
            foe.fighter.stamina / p.stamina,
            STAMINA_COLOR,
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
        elif foe.fighter.piercing():
            _glow(frame, camera, look, foe.character.position, foe.fighter)
        if foe.fighter.raging():
            _centered(frame, middle, y + 6 * scale, "RAGE", scale, DANGER, 1)
    for index in range(len(battle.dummies)):
        ref practice = battle.dummies[index]
        ref fighter = practice.fighter
        if fighter.stamina >= fighter.parameters.stamina:
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
            fighter.stamina / fighter.parameters.stamina,
            STAMINA_COLOR,
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
            var x = mark.value().x
            var y = mark.value().y
            # Four outlined points round the chest, each aimed at it.
            var r = Float32(5 * scale)
            var long = Float32(4 * scale)
            var half = Float32(2.5) * Float32(scale)
            for way in [
                (Float32(-1), Float32(0)),
                (Float32(1), Float32(0)),
                (Float32(0), Float32(-1)),
                (Float32(0), Float32(1)),
            ]:  # pragma: no branch
                var dx = way[0]
                var dy = way[1]
                var tip_x = x + dx * r
                var tip_y = y + dy * r
                var back_x = x + dx * (r + long)
                var back_y = y + dy * (r + long)
                var edge = Float32(scale) * 0.75 + 0.5
                fill_triangle(
                    frame,
                    tip_x - dx * edge * 1.6,
                    tip_y - dy * edge * 1.6,
                    back_x + dx * edge - dy * (half + edge),
                    back_y + dy * edge + dx * (half + edge),
                    back_x + dx * edge + dy * (half + edge),
                    back_y + dy * edge - dx * (half + edge),
                    SHADOW,
                    0.75,
                )
                fill_triangle(
                    frame,
                    tip_x,
                    tip_y,
                    back_x - dy * half,
                    back_y + dx * half,
                    back_x + dy * half,
                    back_y - dx * half,
                    GOLD_TEXT,
                    1,
                )
    draw_raid(frame, battle, camera, look, scale)
    draw_effects(frame, battle, camera, look)
    # The numbers' boxes on the frame, the oldest first.
    var shown = List[Int]()
    var lefts = List[Int]()
    var tops = List[Int]()
    var widths = List[Int]()
    var heights = List[Int]()
    var sizes = List[Int]()
    for index in range(len(battle.popups)):
        ref popup = battle.popups[index]
        var at = on_screen(camera, look, popup.at, w, h)
        if not at:
            continue
        var size = popup_scale(popup.text, popup.color, popup.age, scale)
        var wide = text_width(popup.text, size)
        shown.append(index)
        sizes.append(size)
        lefts.append(Int(at.value().x) - wide // 2)
        # A box's top is the outline's, a stroke above the text. Its
        # height holds the text, the outline and the gap.
        tops.append(Int(at.value().y))
        widths.append(wide)
        heights.append((8 + POPUP_GAP) * size)
    # A newer number keeps its place. An older one that would cover it
    # moves up over it.
    tops = stack_boxes(lefts, tops, widths, heights)
    # Numbers over a head high in the frame stand under the compass and
    # the target panel, so they do not cross them. They move down
    # together, so they keep their order and do not cover each other.
    var band = (TOP_BAND + hud_drop(battle)) * scale
    var drop = 0
    for top in tops:
        drop = max(drop, band - top)
    for k in range(len(shown)):
        ref popup = battle.popups[shown[k]]
        draw_outlined(
            frame,
            lefts[k],
            tops[k] + drop + max(1, sizes[k] // 2),
            popup.text,
            sizes[k],
            popup.color,
            popup_alpha(popup.age),
        )


def fill_triangle(
    mut frame: Framebuffer,
    ax: Float32,
    ay: Float32,
    bx: Float32,
    by: Float32,
    cx: Float32,
    cy: Float32,
    color: Rgb,
    alpha: Float32,
):
    """Blend a color over each pixel whose middle lies in a triangle.

    Args:
        frame: The frame.
        ax: The first corner's x, in pixels.
        ay: The first corner's y, in pixels.
        bx: The second corner's x, either way round.
        by: The second corner's y.
        cx: The third corner's x.
        cy: The third corner's y.
        color: The color.
        alpha: How much of it shows, from 0 to 1.
    """
    var area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    if area == 0:
        return
    # Each edge's test, turned so that the inside is not negative.
    var turn = Float32(1) if area > 0 else Float32(-1)
    var x0 = max(0, Int(min(ax, min(bx, cx))))
    var x1 = min(frame.width - 1, Int(max(ax, max(bx, cx))))
    var y0 = max(0, Int(min(ay, min(by, cy))))
    var y1 = min(frame.height - 1, Int(max(ay, max(by, cy))))
    for y in range(y0, y1 + 1):
        var py = Float32(y) + 0.5
        for x in range(x0, x1 + 1):
            var px = Float32(x) + 0.5
            var e0 = ((bx - ax) * (py - ay) - (by - ay) * (px - ax)) * turn
            var e1 = ((cx - bx) * (py - by) - (cy - by) * (px - bx)) * turn
            var e2 = ((ax - cx) * (py - cy) - (ay - cy) * (px - cx)) * turn
            if min(e0, min(e1, e2)) < 0:
                continue
            fill_box(frame, x, y, x + 1, y + 1, color, alpha)


def stack_boxes(
    lefts: List[Int], tops: List[Int], widths: List[Int], heights: List[Int]
) -> List[Int]:
    """Set boxes over the fighters one over another where they would cover
    each other: the numbers of the blows, and the foes' bars.

    The boxes are taken from the last to the first. A box that crosses a
    box already placed moves up, until its bottom touches that box's top.
    So the last box stays where it is, and the boxes before it stand over
    it.

    Args:
        lefts: The left of each box, in pixels. The box that keeps its
            place last.
        tops: The top of each box, in pixels.
        widths: The width of each box, in pixels.
        heights: The height of each box, in pixels, with the space below
            it.

    Returns:
        The top of each box after the move, in the same order.
    """
    var placed = tops.copy()
    var count = len(tops)
    for back in range(count):
        var k = count - 1 - back
        # Each move takes the box higher than before, to the top of one of
        # the boxes after it less its height, so the moves end.
        var moved = True
        while moved:
            moved = False
            for j in range(k + 1, count):
                var across = _crosses(lefts[k], widths[k], lefts[j], widths[j])
                if across and _crosses(
                    placed[k], heights[k], placed[j], heights[j]
                ):
                    placed[k] = placed[j] - heights[k]
                    moved = True
    return placed^


def _crosses(a: Int, a_size: Int, b: Int, b_size: Int) -> Bool:
    """Return whether two spans of pixels share a pixel."""
    return a < b + b_size and b < a + a_size


def popup_scale(text: String, color: Rgb, age: Float32, scale: Int) -> Int:
    """Return the pixels a dot of a number or a word over a fighter takes.

    A number stands half again as large as the display's words, and a
    critical blow's gold number twice as large. Each number stands one
    dot larger for `POP_SECONDS` as it appears, so it pops.

    Args:
        text: The number or the word.
        color: Its color: gold for a critical blow.
        age: How long it has shown, in seconds.
        scale: The pixels a dot of the display's font takes.

    Returns:
        The pixels a dot takes, at least one.
    """
    var bytes = text.as_bytes()
    var first = Int(bytes[0]) if len(bytes) > 0 else 0
    var number = (first >= ord("0") and first <= ord("9")) or first == ord("+")
    if not number:
        return scale
    var size = scale + (scale + 1) // 2
    # One number of the three bytes: gold or not.
    var packed = (color.r * 256 + color.g) * 256 + color.b
    if packed == (GOLD_TEXT.r * 256 + GOLD_TEXT.g) * 256 + GOLD_TEXT.b:
        size = 2 * scale
    if age < POP_SECONDS:
        size += max(1, scale // 2)
    return size


def popup_alpha(age: Float32) -> Float32:
    """Return how strongly a number or a word over a fighter shows.

    Args:
        age: How long it has shown, in seconds.

    Returns:
        One until `POPUP_FADE` before `POPUP_SECONDS`, then less, to zero
        at `POPUP_SECONDS` and after.
    """
    var left = POPUP_SECONDS - age
    if left <= 0:
        return 0
    return min(Float32(1), left / POPUP_FADE)


def target_name(battle: Battle, index: Int) -> String:
    """Return the name of a foe the player can lock on to.

    Args:
        battle: The fight.
        index: The foe's place in `battle.foes`.

    Returns:
        `WOLF` for a beast, `KNIFE THROWER` for a bandit that throws,
        `BANDIT CAPTAIN` for one stronger than a bandit, else `BANDIT`.
    """
    ref foe = battle.foes[index]
    if foe.beast:
        return "WOLF"
    if foe.brain.throws:
        return "KNIFE THROWER"
    if foe.fighter.parameters.health > bandit_fighter().health:
        return "BANDIT CAPTAIN"
    return "BANDIT"


def draw_target(mut frame: Framebuffer, battle: Battle, top: Int):
    """Draw the foe the player is locked on to, under the compass: its
    name, and its health and stamina as wide bars, on a dark panel.

    Nothing is drawn while the player is locked on to no foe, as on a
    dummy or the warden, whose own bar is drawn apart.

    Args:
        frame: The frame, the window's size.
        battle: The fight.
        top: How far down the frame the panel starts, in pixels.
    """
    if battle.lock < 0 or battle.lock >= len(battle.foes):
        return
    ref foe = battle.foes[battle.lock]
    var scale = hud_scale(frame.height)
    var name = target_name(battle, battle.lock)
    var width = frame.width // 4
    var x = (frame.width - width) // 2
    # A dark panel behind the name and the bars, as behind the gauges.
    fill_box(
        frame,
        x - 4 * scale,
        top - 2 * scale,
        x + width + 4 * scale,
        top + 17 * scale,
        SHADOW,
        PANEL_ALPHA,
    )
    _centered(frame, frame.width // 2, top, name, scale, WHITE_TEXT, 1)
    ref p = foe.fighter.parameters
    var y = top + 9 * scale
    draw_bar(
        frame,
        x,
        y,
        width,
        3 * scale,
        foe.fighter.health / p.health,
        WOUNDED,
        foe.fighter.chip / p.health,
    )
    draw_bar(
        frame,
        x,
        y + 4 * scale,
        width,
        scale,
        foe.fighter.stamina / p.stamina,
        STAMINA_COLOR,
    )


def hud_drop(battle: Battle) -> Int:
    """Return how far down the compass and the target panel stand, so a
    fighting warden's bars show over them.

    Args:
        battle: The fight.

    Returns:
        `BOSS_ROOM` dots of the heads-up display's font while a warden
        fights, else zero.
    """
    return BOSS_ROOM if boss_fights(battle) else 0


def hurt_way(feet: Vector3, source: Vector3, look: Vector3) -> Vector3:
    """Return the way on the frame from its middle toward where a blow came
    from: up for ahead, right for the camera's right.

    Args:
        feet: Where the player stands.
        source: Where the blow came from.
        look: The way the camera looks, of length one.

    Returns:
        A way on the frame in `x` and `y`, with `y` down, of length one; or
        zero for a blow from where the player stands.
    """
    var wx = source.x - feet.x
    var wz = source.z - feet.z
    var ahead = wx * look.x + wz * look.z
    var right = wz * look.x - wx * look.z
    var length = sqrt(ahead * ahead + right * right)
    if length < 1.0e-4:
        return Vector3(0, 0, 0)
    return Vector3(right / length, -ahead / length, 0)


def draw_hurts(mut frame: Framebuffer, battle: Battle, look: Vector3):
    """Mark, near the frame's edge, the way to each blow the player took
    in the last `HURT_SECONDS`: a red arc that fades.

    Args:
        frame: The frame, the window's size.
        battle: The fight.
        look: The way the camera looks, of length one.
    """
    var scale = hud_scale(frame.height)
    var mx = Float32(frame.width) / 2
    var my = Float32(frame.height) / 2
    var rx = Float32(frame.width) * HURT_REACH
    var ry = Float32(frame.height) * HURT_REACH
    var half = Float32(HURT_THICK * scale)
    for hurt in battle.hurts:
        var way = hurt_way(battle.feet, hurt.source, look)
        if way.x == 0 and way.y == 0:
            continue
        var alpha = 0.9 * (1 - hurt.age / HURT_SECONDS)
        # The mark is a crescent on the ellipse through the middles of the
        # frame's edges: widest and strongest at its middle, and thin and
        # faint at its ends.
        var cx = Int(mx + way.x * rx)
        var cy = Int(my + way.y * ry)
        # The box round the arc: its run across the way, and how far its
        # ends bow in from its middle.
        var bow = HURT_SPREAD * HURT_SPREAD / 2
        var reach_x = Int(
            HURT_SPREAD * rx * abs(way.y) + bow * rx * abs(way.x) + half + 2
        )
        var reach_y = Int(
            HURT_SPREAD * ry * abs(way.x) + bow * ry * abs(way.y) + half + 2
        )
        for py in range(
            max(0, cy - reach_y), min(frame.height, cy + reach_y + 1)
        ):  # pragma: no branch
            var v = (Float32(py) + 0.5 - my) / ry
            for px in range(
                max(0, cx - reach_x), min(frame.width, cx + reach_x + 1)
            ):  # pragma: no branch
                var u = (Float32(px) + 0.5 - mx) / rx
                var r = sqrt(u * u + v * v)
                # How far along the arc from its middle, from 0 to 1.
                var along = abs(u * way.y - v * way.x) / r / HURT_SPREAD
                if along >= 1:
                    continue
                var taper = 1 - along * along
                var thick = half * (0.3 + 0.7 * taper)
                # How far off the ellipse, in pixels.
                var off = (
                    abs(r - 1) * sqrt(u * u * rx * rx + v * v * ry * ry) / r
                )
                if off >= thick:
                    continue
                var edge = min(Float32(1), 2 * (1 - off / thick))
                fill_box(
                    frame, px, py, px + 1, py + 1, DANGER, alpha * taper * edge
                )


def boss_fights(battle: Battle) -> Bool:
    """Return whether a raid's boss fights, and shows its bar at the top of
    the frame.

    Args:
        battle: The fight.

    Returns:
        Whether a warden is engaged and not yet defeated.
    """
    for index in range(len(battle.wardens)):
        ref boss = battle.wardens[index].boss
        if boss.engaged and not boss.defeated():
            return True
    return False
