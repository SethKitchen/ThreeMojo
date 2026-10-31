# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The weapons of each fighting style but the sword and the fists: an axe,
a mace, a mage's staff and a bow.

Each weapon is built as the sword is: along plus z from the middle of its
grip, so it lies in the fist with its head the way the thumb points. See
`extensions.village.blade`.

| Weapon | What it is, for a person of six feet | Where it is stowed |
|---|---|---|
| Axe | A haft of ash 75 centimeters long, and a bearded steel head with a poll | At the hip, as a sword |
| Mace | A haft 60 centimeters long, wrapped in leather, and an iron head of six flanges and a spike | At the hip, as a sword |
| Staff | A haft of dark wood 1.7 meters long, banded in brass, and a glowing crystal held in three prongs | Across the back |
| Bow | A recurve bow 1.3 meters from tip to tip, its limbs of horn and wood, and its string | Across the back |

The staff's crystal and the bow's string are lit by nothing: they show
their own color. `add_weapon` hangs one from a node, held or stowed.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.village.blade import BRASS, LEATHER, SwordLooks
from extensions.village.sheet import Sheet
from extensions.village.styles import (
    ARCHERY,
    AXE,
    MACE,
    MAGIC,
    FightingStyle,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import cos, pi, sin, sqrt
from units.si import DEGREE, Angle

comptime ASH = Vector3(0.52, 0.38, 0.24)
"""The color of an axe's haft."""
comptime DARK_WOOD = Vector3(0.2, 0.12, 0.07)
"""The color of a staff's haft."""
comptime AXE_STEEL = Vector3(0.62, 0.63, 0.66)
"""The color of an axe's head."""
comptime MACE_IRON = Vector3(0.36, 0.35, 0.36)
"""The color of a mace's head."""
comptime CRYSTAL = Vector3(0.45, 0.8, 1.0)
"""The color of a staff's crystal."""
comptime HORN = Vector3(0.3, 0.2, 0.12)
"""The color of a bow's limbs."""
comptime STRING = Vector3(0.85, 0.82, 0.72)
"""The color of a bow's string."""
comptime BACK_AT = Vector3(0.0, 0.05, -0.16)
"""Where a stowed staff's or bow's middle lies from the chest, in meters,
for a person of six feet."""
comptime HIP_AT = Vector3(0.2, -0.06, 0.06)
"""Where a stowed axe's or mace's grip lies from the hips, in meters, for
a person of six feet."""
comptime HELD_AT = Vector3(0.005, -0.082, 0.012)
"""Where the middle of a held weapon's grip lies from the wrist, in
meters, for a person of six feet."""


def tube(
    mut sheet: Sheet,
    a: Vector3,
    b: Vector3,
    radius: Float32,
    sides: Int,
    color: Vector3,
):
    """Add a prism along a line, its sides facing out, and its ends shut.

    Args:
        sheet: The sheet to add to.
        a: One end's middle.
        b: The other end's middle.
        radius: The radius of the circle its corners lie on, in meters.
        sides: How many sides, 3 or more.
        color: Its linear color.
    """
    var along = b - a
    var long = along.length()
    if long < 1.0e-6 or sides < 3:
        return
    var w = along / long
    # Two ways at right angles to the line.
    var helper = Vector3(1, 0, 0) if abs(w.x) < 0.9 else Vector3(0, 1, 0)
    var u = Vector3(
        helper.y * w.z - helper.z * w.y,
        helper.z * w.x - helper.x * w.z,
        helper.x * w.y - helper.y * w.x,
    )
    u = u / u.length()
    var v = Vector3(
        w.y * u.z - w.z * u.y, w.z * u.x - w.x * u.z, w.x * u.y - w.y * u.x
    )
    for k in range(sides):  # pragma: no branch
        var t0 = Float32(2 * pi) * Float32(k) / Float32(sides)
        var t1 = Float32(2 * pi) * Float32(k + 1) / Float32(sides)
        var r0 = (u * cos(t0) + v * sin(t0)) * radius
        var r1 = (u * cos(t1) + v * sin(t1)) * radius
        sheet.quad(a + r0, a + r1, b + r1, b + r0, color)
        var ca = sheet.vertex(a, w * -1, color, 0, 0)
        var c0 = sheet.vertex(a + r0, w * -1, color, 0, 0)
        var c1 = sheet.vertex(a + r1, w * -1, color, 0, 0)
        sheet.triangle(ca, c1, c0)
        var cb = sheet.vertex(b, w, color, 0, 0)
        var d0 = sheet.vertex(b + r0, w, color, 0, 0)
        var d1 = sheet.vertex(b + r1, w, color, 0, 0)
        sheet.triangle(cb, d0, d1)


def _plate(
    mut sheet: Sheet,
    corners: List[Vector3],
    thick: Float32,
    color: Vector3,
):
    """Add a flat plate across x: its outline in the plane x = 0, made as
    thick as `thick`, both faces and its rim. Each caller gives an outline
    of three corners or more."""
    var count = len(corners)
    var front = Vector3(thick / 2, 0, 0)
    var center = Vector3(0, 0, 0)
    for corner in corners:  # pragma: no branch
        center = center + corner
    center = center / Float32(count)
    for side in [Float32(-1), Float32(1)]:  # pragma: no branch
        var n = Vector3(side, 0, 0)
        var off = front * side
        var mid = sheet.vertex(center + off, n, color, 0, 0)
        for k in range(count):  # pragma: no branch
            var p = sheet.vertex(corners[k] + off, n, color, 0, 0)
            var q = sheet.vertex(corners[(k + 1) % count] + off, n, color, 0, 0)
            if side > 0:
                sheet.triangle(mid, p, q)
            else:
                sheet.triangle(mid, q, p)
    for k in range(count):  # pragma: no branch
        var p = corners[k]
        var q = corners[(k + 1) % count]
        sheet.quad(p - front, q - front, q + front, p + front, color * 0.9)


struct WeaponSheets(Movable):
    """A weapon's triangles: its metal, its wood or leather, and the parts
    that light up."""

    var metal: Sheet
    var leather: Sheet
    var glow: Sheet

    def __init__(out self):
        """Hold no triangles."""
        self.metal = Sheet(1)
        self.leather = Sheet(1)
        self.glow = Sheet(1)


def axe_sheets(scale: Float32) -> WeaponSheets:
    """Return an axe's triangles, along plus z from the middle of its grip.

    Args:
        scale: The fighter's height over six feet.

    Returns:
        The haft in wood, the head in steel: a bearded blade along plus y,
        and a poll behind it.
    """
    var out = WeaponSheets()
    var s = scale
    tube(
        out.leather,
        Vector3(0, 0, -0.12 * s),
        Vector3(0, 0, 0.62 * s),
        0.016 * s,
        6,
        ASH,
    )
    # A leather wrap where the hand holds it.
    tube(
        out.leather,
        Vector3(0, 0, -0.07 * s),
        Vector3(0, 0, 0.07 * s),
        0.019 * s,
        6,
        LEATHER,
    )
    # The eye around the haft, and the poll behind it.
    out.metal.box(
        Vector3(0, -0.005 * s, 0.54 * s),
        Vector3(0.022 * s, 0, 0),
        Vector3(0, 0.03 * s, 0),
        Vector3(0, 0, 0.05 * s),
        AXE_STEEL * 0.8,
    )
    out.metal.box(
        Vector3(0, -0.05 * s, 0.54 * s),
        Vector3(0.016 * s, 0, 0),
        Vector3(0, 0.02 * s, 0),
        Vector3(0, 0, 0.03 * s),
        AXE_STEEL * 0.7,
    )
    # The blade: a bearded outline that flares to its edge.
    var blade: List[Vector3] = [
        Vector3(0, 0.025 * s, 0.5 * s),
        Vector3(0, 0.1 * s, 0.44 * s),
        Vector3(0, 0.17 * s, 0.4 * s),
        Vector3(0, 0.19 * s, 0.5 * s),
        Vector3(0, 0.18 * s, 0.62 * s),
        Vector3(0, 0.12 * s, 0.63 * s),
        Vector3(0, 0.025 * s, 0.59 * s),
    ]
    _plate(out.metal, blade, 0.008 * s, AXE_STEEL)
    # The bright edge.
    tube(
        out.metal,
        Vector3(0, 0.172 * s, 0.4 * s),
        Vector3(0, 0.188 * s, 0.6 * s),
        0.004 * s,
        4,
        AXE_STEEL * 1.2,
    )
    return out^


def mace_sheets(scale: Float32) -> WeaponSheets:
    """Return a mace's triangles, along plus z from the middle of its grip.

    Args:
        scale: The fighter's height over six feet.

    Returns:
        The haft wrapped in leather, and an iron head of six flanges around
        a core, with a spike on top.
    """
    var out = WeaponSheets()
    var s = scale
    tube(
        out.leather,
        Vector3(0, 0, -0.1 * s),
        Vector3(0, 0, 0.42 * s),
        0.017 * s,
        6,
        LEATHER,
    )
    tube(
        out.metal,
        Vector3(0, 0, -0.13 * s),
        Vector3(0, 0, -0.1 * s),
        0.026 * s,
        6,
        MACE_IRON,
    )
    tube(
        out.metal,
        Vector3(0, 0, 0.4 * s),
        Vector3(0, 0, 0.56 * s),
        0.034 * s,
        8,
        MACE_IRON,
    )
    for k in range(6):  # pragma: no branch
        var turn = Float32(2 * pi) * Float32(k) / 6
        var c = cos(turn)
        var r = sin(turn)
        var flange: List[Vector3] = [
            Vector3(0, 0.025 * s, 0.4 * s),
            Vector3(0, 0.075 * s, 0.45 * s),
            Vector3(0, 0.08 * s, 0.51 * s),
            Vector3(0, 0.025 * s, 0.57 * s),
        ]
        var plate = Sheet(1)
        _plate(plate, flange, 0.01 * s, MACE_IRON * 1.1)
        # Turn the plate about z to its place around the core.
        var count = len(plate.positions) // 3
        for v in range(count):  # pragma: no branch
            var x = plate.positions[3 * v]
            var y = plate.positions[3 * v + 1]
            plate.positions[3 * v] = x * c - y * r
            plate.positions[3 * v + 1] = x * r + y * c
            var nx = plate.normals[3 * v]
            var ny = plate.normals[3 * v + 1]
            plate.normals[3 * v] = nx * c - ny * r
            plate.normals[3 * v + 1] = nx * r + ny * c
        var base = len(out.metal.positions) // 3
        for i in plate.index:  # pragma: no branch
            out.metal.index.append(base + i)
        out.metal.positions.extend(plate.positions.copy())
        out.metal.normals.extend(plate.normals.copy())
        out.metal.colors.extend(plate.colors.copy())
        out.metal.uvs.extend(plate.uvs.copy())
    tube(
        out.metal,
        Vector3(0, 0, 0.56 * s),
        Vector3(0, 0, 0.64 * s),
        0.012 * s,
        4,
        MACE_IRON * 1.2,
    )
    return out^


def staff_sheets(scale: Float32) -> WeaponSheets:
    """Return a staff's triangles, along plus z from the middle of its grip.

    Args:
        scale: The fighter's height over six feet.

    Returns:
        A haft of dark wood with brass bands, three prongs at its head, and
        a glowing crystal between them.
    """
    var out = WeaponSheets()
    var s = scale
    tube(
        out.leather,
        Vector3(0, 0, -0.75 * s),
        Vector3(0, 0, 0.92 * s),
        0.018 * s,
        7,
        DARK_WOOD,
    )
    for z in [Float32(-0.72), Float32(-0.1), Float32(0.1), Float32(0.86)]:
        tube(
            out.metal,
            Vector3(0, 0, (z - 0.02) * s),
            Vector3(0, 0, (z + 0.02) * s),
            0.022 * s,
            7,
            BRASS,
        )
    var top = Vector3(0, 0, 1.02 * s)
    for k in range(3):  # pragma: no branch
        var turn = Float32(2 * pi) * Float32(k) / 3
        var out_way = Vector3(cos(turn), sin(turn), 0)
        tube(
            out.metal,
            Vector3(0, 0, 0.9 * s) + out_way * (0.015 * s),
            top + out_way * (0.05 * s),
            0.006 * s,
            4,
            BRASS,
        )
    # The crystal: two pyramids, tip to tip along z.
    var r = Float32(0.04) * s
    var h = Float32(0.075) * s
    var low = top - Vector3(0, 0, h)
    var high = top + Vector3(0, 0, h)
    for k in range(5):  # pragma: no branch
        var t0 = Float32(2 * pi) * Float32(k) / 5
        var t1 = Float32(2 * pi) * Float32(k + 1) / 5
        var p0 = top + Vector3(cos(t0) * r, sin(t0) * r, 0)
        var p1 = top + Vector3(cos(t1) * r, sin(t1) * r, 0)
        var mid = (p0 + p1) / 2 - top
        var n = mid / max(mid.length(), Float32(1.0e-6))
        var a = out.glow.vertex(p0, n, CRYSTAL, 0, 0)
        var b = out.glow.vertex(p1, n, CRYSTAL, 0, 0)
        var c = out.glow.vertex(high, n, CRYSTAL * 1.2, 0, 0)
        var d = out.glow.vertex(low, n, CRYSTAL * 0.8, 0, 0)
        out.glow.triangle(a, b, c)
        out.glow.triangle(b, a, d)
    return out^


def bow_sheets(scale: Float32) -> WeaponSheets:
    """Return a bow's triangles, along plus z from the middle of its grip.

    Args:
        scale: The fighter's height over six feet.

    Returns:
        Two limbs that curve forward along plus y and recurve at their
        tips, a leather grip, and a string between the tips, along minus y
        of the grip.
    """
    var out = WeaponSheets()
    var s = scale
    var half = Float32(0.65) * s
    var steps = 8
    var last_up = Vector3(0, 0, 0.06 * s)
    var last_down = Vector3(0, 0, -0.06 * s)
    for k in range(1, steps + 1):  # pragma: no branch
        var t = Float32(k) / Float32(steps)
        var z = 0.06 * s + (half - 0.06 * s) * t
        # The limb bows forward, and its tip curls back.
        var bend = Float32(0.11) * s * sin(t * Float32(pi) * 0.85)
        bend -= Float32(0.04) * s * max(Float32(0), t - 0.8) * 5
        var thick = Float32(0.013) * s * (1 - 0.5 * t)
        var up = Vector3(0, bend, z)
        var down = Vector3(0, bend, -z)
        tube(out.leather, last_up, up, thick, 5, HORN)
        tube(out.leather, last_down, down, thick, 5, HORN)
        last_up = up
        last_down = down
    tube(
        out.leather,
        Vector3(0, 0, -0.07 * s),
        Vector3(0, 0, 0.07 * s),
        0.02 * s,
        6,
        LEATHER,
    )
    # The string, from tip to tip.
    tube(out.glow, last_down, last_up, 0.002 * s, 3, STRING)
    return out^


def _add(
    mut scene: Scene,
    mut assets: Assets,
    sheet: Sheet,
    material: Int,
    looks: SwordLooks,
    parent: NodeId,
) raises:
    """Add a sheet as a mesh under a node, in the metal, the leather or the
    glow."""
    if len(sheet.index) == 0:
        return
    var id = looks.metal
    if material == 1:
        id = looks.leather
    elif material == 2:
        id = looks.glow
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sheet.geometry()),
            id,
            parent,
            cast_shadow=material != 2,
            receive_shadow=material != 2,
        )
    )


def weapon_sheets(style: FightingStyle, scale: Float32) raises -> WeaponSheets:
    """Return a style's weapon.

    Args:
        style: The style: the axe, the mace, magic or archery.
        scale: The fighter's height over six feet.

    Returns:
        The weapon's triangles.

    Raises:
        Error: If the style has no weapon of this module.
    """
    if style == AXE:
        return axe_sheets(scale)
    if style == MACE:
        return mace_sheets(scale)
    if style == MAGIC:
        return staff_sheets(scale)
    if style == ARCHERY:
        return bow_sheets(scale)
    raise Error("Only the axe, the mace, magic and archery have a weapon here")


def add_weapon(
    mut scene: Scene,
    mut assets: Assets,
    looks: SwordLooks,
    parent: NodeId,
    scale: Float32,
    style: FightingStyle,
    stowed: Bool,
) raises -> NodeId:
    """Hang a style's weapon from a node: held, or stowed.

    Args:
        scene: The scene.
        assets: The stores for the geometries.
        looks: The materials: the metal, the leather and the glow.
        parent: The node it hangs from: the bone of the hand that holds
            it; for a stowed axe or mace the hips' bone, and for a stowed
            staff or bow the chest's.
        scale: The fighter's height over six feet.
        style: The style: the axe, the mace, magic or archery.
        stowed: Whether it is stowed, or held.

    Returns:
        The node that holds the weapon. Hide it to hide the weapon.

    Raises:
        Error: If the style has no weapon here, or a mesh cannot be added.
    """
    var sheets = weapon_sheets(style, scale)
    var holder = Object3D()
    var back = style == MAGIC or style == ARCHERY
    if stowed and back:
        var at = BACK_AT * scale
        holder.set_position(at.x, at.y, at.z)
        # Slung across the back, from the right shoulder down to the left
        # hip.
        holder.set_rotation_from_axis_angle(
            Vector3(0, 0, 1), Angle(35.0, DEGREE)
        )
        var tilt = Object3D()
        tilt.set_rotation_from_axis_angle(Vector3(1, 0, 0), Angle(90.0, DEGREE))
        var outer = scene.attach(holder^, parent)
        var node = scene.attach(tilt^, outer)
        _add(scene, assets, sheets.metal, 0, looks, node)
        _add(scene, assets, sheets.leather, 1, looks, node)
        _add(scene, assets, sheets.glow, 2, looks, node)
        return outer
    if stowed:
        var at = HIP_AT * scale
        holder.set_position(at.x, at.y, at.z)
        holder.set_rotation_from_axis_angle(
            Vector3(1, 0, 0), Angle(150.0, DEGREE)
        )
    else:
        var at = HELD_AT * scale
        holder.set_position(at.x, at.y, at.z)
    var node = scene.attach(holder^, parent)
    _add(scene, assets, sheets.metal, 0, looks, node)
    _add(scene, assets, sheets.leather, 1, looks, node)
    _add(scene, assets, sheets.glow, 2, looks, node)
    return node
