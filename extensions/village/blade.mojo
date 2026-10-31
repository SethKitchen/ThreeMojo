# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A one-handed sword, held in a fighter's hand or sheathed at its hip.

`add_sword` hangs a sword from a node: a straight, double-edged blade 80
centimeters long for a person of six feet, a brass cross-guard and
pommel, and a grip wrapped in leather. It is built along plus z from the
middle of the grip. In the hand on a game humanoid's minus x, the grip
lies in the fist and the blade points the way the thumb points: see
`HAND_GRIP`. That is the hand a camera behind the humanoid sees on its
right: see `extensions.humanoid.rig.sword_clips`. Sheathed, the sword
hangs from the hips on the other side, its point back and down: see
`SHEATH_AT`. `add_scabbard` hangs a scabbard of dark leather there,
which covers a sheathed blade and stays when the sword is drawn.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.village.sheet import Sheet
from materials.material import BASIC, Material, MaterialId, standard_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import DEGREE, Angle

comptime BLADE = Float32(0.8)
"""The blade's length, in meters, for a person of six feet."""
comptime HAND_GRIP = Vector3(0.005, -0.082, 0.012)
"""Where the middle of the grip lies from the wrist of the hand on minus
x, in meters, for a person of six feet."""
comptime SHEATH_AT = Vector3(0.2, -0.06, 0.06)
"""Where the middle of a sheathed sword's grip lies from the hips, in
meters, for a person of six feet."""
comptime SHEATH_TILT = Float32(150)
"""How far a sheathed sword is turned about plus x from pointing forward,
in degrees, so its point goes back and down."""
comptime BRIGHT_STEEL = Vector3(0.82, 0.84, 0.88)
"""The color of a well-kept blade."""
comptime DULL_IRON = Vector3(0.42, 0.4, 0.38)
"""The color of a bandit's dull, notched blade."""
comptime BRASS = Vector3(0.78, 0.56, 0.22)
"""The color of the cross-guard and the pommel."""
comptime LEATHER = Vector3(0.26, 0.14, 0.08)
"""The color of the grip's wrap and of the scabbard."""


struct SwordLooks(ImplicitlyCopyable):
    """The materials of a sword and the other weapons: polished metal,
    leather and wood, and an unlit glow for a crystal or a string."""

    var metal: MaterialId
    var leather: MaterialId
    var glow: MaterialId

    def __init__(out self, mut assets: Assets) raises:
        """Make the three materials. Each shows its vertex colors.

        Args:
            assets: The stores the materials go into.

        Raises:
            Error: If a material cannot be made.
        """
        var metal = standard_material(
            Color(255, 255, 255), roughness=0.3, metalness=0.55
        )
        metal.vertex_colors = True
        self.metal = assets.materials.add(metal)
        var leather = standard_material(Color(255, 255, 255), roughness=0.85)
        leather.vertex_colors = True
        self.leather = assets.materials.add(leather)
        self.glow = assets.materials.add(
            Material(Color(255, 255, 255), kind=BASIC, vertex_colors=True)
        )


struct SwordSheets(Movable):
    """A sword's triangles: the metal parts and the leather parts."""

    var metal: Sheet
    var leather: Sheet

    def __init__(out self):
        """Hold no triangles."""
        self.metal = Sheet(1)
        self.leather = Sheet(1)


def sword_sheets(scale: Float32, steel: Vector3) -> SwordSheets:
    """Return a sword's triangles, built along plus z from the middle of
    its grip.

    Args:
        scale: The fighter's height over six feet.
        steel: The blade's color.

    Returns:
        The blade, the cross-guard and the pommel in metal, and the
        grip's wrap in leather.
    """
    var out = SwordSheets()
    var s = scale
    var x = Vector3(1, 0, 0)
    var y = Vector3(0, 1, 0)
    var z = Vector3(0, 0, 1)
    # The grip, a hand and a half long, and the pommel behind it.
    out.leather.box(
        Vector3(0, 0, 0), x * 0.014 * s, y * 0.016 * s, z * 0.07 * s, LEATHER
    )
    out.metal.box(
        Vector3(0, 0, -0.085 * s),
        x * 0.02 * s,
        y * 0.024 * s,
        z * 0.016 * s,
        BRASS,
    )
    # The cross-guard, across the edges.
    out.metal.box(
        Vector3(0, 0, 0.08 * s),
        x * 0.012 * s,
        y * 0.1 * s,
        z * 0.012 * s,
        BRASS,
    )
    var root = Float32(0.092) * s
    var length = BLADE * s
    # The blade: flat, its edges along y, tapering to the point.
    var half = length * 0.46
    out.metal.box(
        Vector3(0, 0, root + half),
        x * 0.004 * s,
        y * 0.022 * s,
        z * half,
        steel,
    )
    # The fuller down the middle, darker, on each face.
    for side in [Float32(-1), Float32(1)]:  # pragma: no branch
        out.metal.box(
            Vector3(side * 0.0045 * s, 0, root + half * 0.85),
            x * 0.0006 * s,
            y * 0.005 * s,
            z * half * 0.75,
            steel * 0.55,
        )
    # The point: two faces that meet at the tip.
    var base = root + 2 * half
    var tip = Vector3(0, 0, root + length)
    var w = Float32(0.022) * s
    var t = Float32(0.004) * s
    for side in [Float32(-1), Float32(1)]:  # pragma: no branch
        var n = Vector3(side, 0, 0)
        var a = out.metal.vertex(Vector3(side * t, -w, base), n, steel, 0, 0)
        var b = out.metal.vertex(Vector3(side * t, w, base), n, steel, 0, 0)
        var c = out.metal.vertex(tip, n, steel, 0, 0)
        if side > 0:
            out.metal.triangle(a, b, c)
        else:
            out.metal.triangle(b, a, c)
    return out^


def scabbard_sheet(scale: Float32) -> Sheet:
    """Return a scabbard's triangles, built along plus z from the middle
    of a sheathed sword's grip.

    Args:
        scale: The fighter's height over six feet.

    Returns:
        A box of dark leather a little wider and longer than the blade.
    """
    var s = scale
    var sheet = Sheet(1)
    var root = Float32(0.092) * s
    var length = BLADE * s
    sheet.box(
        Vector3(0, 0, root + length / 2),
        Vector3(0.014 * s, 0, 0),
        Vector3(0, 0.032 * s, 0),
        Vector3(0, 0, length / 2 + 0.01 * s),
        LEATHER * 0.7,
    )
    return sheet^


def _add_sheet(
    mut scene: Scene,
    mut assets: Assets,
    sheet: Sheet,
    material: MaterialId,
    parent: NodeId,
) raises:
    """Add a sheet as a mesh under a node, casting a shadow."""
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sheet.geometry()),
            material,
            parent,
            cast_shadow=True,
            receive_shadow=True,
        )
    )


def add_sword(
    mut scene: Scene,
    mut assets: Assets,
    looks: SwordLooks,
    parent: NodeId,
    scale: Float32,
    steel: Vector3,
    sheathed: Bool,
) raises -> NodeId:
    """Hang a sword from a node: in the hand, or sheathed at the hip.

    A sheathed sword's blade lies within the scabbard that
    `add_scabbard` hangs at the same place.

    Args:
        scene: The scene.
        assets: The stores for the geometries.
        looks: The sword's materials.
        parent: The node it hangs from: the bone of the hand on minus x,
            or for a sheathed sword the hips' bone.
        scale: The fighter's height over six feet.
        steel: The blade's color.
        sheathed: Whether it is sheathed at the hip, or held.

    Returns:
        The node that holds the sword. Hide it to hide the sword.

    Raises:
        Error: If a mesh cannot be added.
    """
    var holder = Object3D()
    if sheathed:
        var at = SHEATH_AT * scale
        holder.set_position(at.x, at.y, at.z)
        holder.set_rotation_from_axis_angle(
            Vector3(1, 0, 0), Angle(SHEATH_TILT, DEGREE)
        )
    else:
        var at = HAND_GRIP * scale
        holder.set_position(at.x, at.y, at.z)
    var node = scene.attach(holder^, parent)
    var sheets = sword_sheets(scale, steel)
    _add_sheet(scene, assets, sheets.metal, looks.metal, node)
    _add_sheet(scene, assets, sheets.leather, looks.leather, node)
    return node


def add_scabbard(
    mut scene: Scene,
    mut assets: Assets,
    looks: SwordLooks,
    hips: NodeId,
    scale: Float32,
) raises -> NodeId:
    """Hang a scabbard from the hips, where a sheathed sword hangs.

    Args:
        scene: The scene.
        assets: The stores for the geometry.
        looks: The sword's materials: the scabbard is leather.
        hips: The hips' bone.
        scale: The fighter's height over six feet.

    Returns:
        The node that holds the scabbard.

    Raises:
        Error: If the mesh cannot be added.
    """
    var holder = Object3D()
    var at = SHEATH_AT * scale
    holder.set_position(at.x, at.y, at.z)
    holder.set_rotation_from_axis_angle(
        Vector3(1, 0, 0), Angle(SHEATH_TILT, DEGREE)
    )
    var node = scene.attach(holder^, hips)
    _add_sheet(scene, assets, scabbard_sheet(scale), looks.leather, node)
    return node
