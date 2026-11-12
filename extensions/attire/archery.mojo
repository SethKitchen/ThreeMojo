# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Things an archer carries: a longbow, and a quiver of arrows at the hip.

A prop is a plain mesh that hangs from a socket, as in `props`. These are
painted in their `color` attribute, linear, so one material with vertex
colors draws them.

- `longbow` is a braced bow as tall as its archer. Its stave bends in an
  arc, thickest at the grip and thinning to each tip, and its string runs
  straight from tip to tip. The grip is at the origin, the stave runs
  along y, and the belly and the string lie toward plus z.
- `hip_quiver` is a leather tube, its mouth at the origin, hanging down
  along minus y. Its arrows stand up out of the mouth, fletched near
  their nocks.
- `equip_archer` hangs both on a person: the bow in the left hand,
  leaning forward, and the quiver on the back, its arrows over the right
  shoulder.

| Value | Size |
|---|---|
| Brace height, `BRACE` | 8% of the bow's height, between the string and the grip |
| Stave | 16 mm across at the grip, 6 mm at the tips |
| Quiver | 45 mm across at the mouth, 38 mm at the foot |
| Arrows, `QUIVER_ARROWS` | 9, standing 16 cm out of the mouth |

This is not a three.js port. See Extensions.

    var bow = longbow(Length(1.8, METER), yew, linen, flax)
    var quiver = hip_quiver(Length(0.55, METER), hide, ash, goose)
"""

from std.math import cos, pi, sin

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.attire.sockets import BACK, LEFT_GRIP, attach
from extensions.humanoid.rig.game import GameHumanoid
from materials.material import MaterialId
from objects.mesh import Mesh
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from extensions.attire.mesh_ops import merge
from geometries.box import box
from geometries.lathe import lathe
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color
from render.srgb import srgb_to_linear
from units.si import DEGREE, METER, Angle, Length

comptime BRACE = Float32(0.08)
"""How far the grip stands from the string, as a share of the bow's
height."""
comptime STAVE_GRIP = Float32(0.008)
"""The radius of the stave at the grip, in meters."""
comptime STAVE_TIP = Float32(0.003)
"""The radius of the stave at each tip, in meters."""
comptime GRIP_LENGTH = Float32(0.1)
"""How long the grip's wrap is, in meters."""
comptime STAVE_RINGS = 24
"""How many rings run along the stave."""
comptime STAVE_SIDES = 8
"""How many sides the stave has."""
comptime QUIVER_ARROWS = 9
"""How many arrows stand in a quiver."""
comptime ARROW_STAND = Float32(0.16)
"""How far the arrows stand out of a quiver's mouth, in meters."""


def _painted(var mesh: BufferGeometry, color: Color) raises -> BufferGeometry:
    """Return a mesh painted one sRGB color, as linear vertex colors."""
    var r = srgb_to_linear(Float32(color.r) / 255)
    var g = srgb_to_linear(Float32(color.g) / 255)
    var b = srgb_to_linear(Float32(color.b) / 255)
    var colors = List[Float32](capacity=3 * mesh.vertex_count())
    for _ in range(mesh.vertex_count()):  # pragma: no branch
        colors.append(r)
        colors.append(g)
        colors.append(b)
    mesh.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return mesh^


def sweep(
    points: List[Vector3], radii: List[Float32], sides: Int
) raises -> BufferGeometry:
    """Return a tube swept along a path in the x-y plane.

    Each ring stands across the path, round its tangent, with one axis
    along z.

    Args:
        points: The path, two points or more, in the x-y plane.
        radii: The tube's radius at each point, in meters.
        sides: How many sides the tube has, three or more.

    Returns:
        An indexed mesh with positions, normals and texture coordinates.
        Its ends are open.

    Raises:
        Error: If there are fewer than two points, not one radius a
            point, or fewer than three sides.
    """
    if len(points) < 2:
        raise Error("A sweep needs two points or more")
    if len(radii) != len(points):
        raise Error("A sweep needs one radius a point")
    if sides < 3:
        raise Error("A sweep needs three sides or more")
    var placed = List[Float32]()
    var faces = List[Float32]()
    var uvs = List[Float32]()
    var count = len(points)
    for k in range(count):  # pragma: no branch
        var ahead = points[min(k + 1, count - 1)] - points[max(k - 1, 0)]
        ahead.normalize()
        # Across the path in its plane, and out of the plane.
        var across = Vector3(ahead.y, -ahead.x, 0)
        for s in range(sides):  # pragma: no branch
            var turn = 2 * Float32(pi) * Float32(s) / Float32(sides)
            var facing = across * cos(turn) + Vector3(0, 0, 1) * sin(turn)
            var p = points[k] + facing * radii[k]
            placed.append(p.x)
            placed.append(p.y)
            placed.append(p.z)
            faces.append(facing.x)
            faces.append(facing.y)
            faces.append(facing.z)
            uvs.append(Float32(s) / Float32(sides))
            uvs.append(Float32(k) / Float32(count - 1))
    var index = List[Int]()
    for k in range(count - 1):  # pragma: no branch
        for s in range(sides):  # pragma: no branch
            var a = k * sides + s
            var b = k * sides + (s + 1) % sides
            var c = a + sides
            var d = b + sides
            index.append(a)
            index.append(b)
            index.append(c)
            index.append(c)
            index.append(b)
            index.append(d)
    var mesh = BufferGeometry()
    mesh.set_attribute(String(POSITION), BufferAttribute(placed^, 3))
    mesh.set_attribute(String(NORMAL), BufferAttribute(faces^, 3))
    mesh.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    mesh.set_index(index^)
    return mesh^


def longbow(
    height: Length, wood: Color, grip: Color, string: Color
) raises -> BufferGeometry:
    """Return a braced longbow, painted.

    Args:
        height: The bow's height from tip to tip.
        wood: The stave's color, sRGB.
        grip: The color of the wrap round the grip, sRGB.
        string: The string's color, sRGB.

    Returns:
        One mesh: the stave, the grip's wrap and the string.

    Raises:
        Error: If the height is not positive.
    """
    var tall = height.to(METER)
    if not (tall > 0):
        raise Error("A bow needs a positive height")
    var half = tall / 2
    var brace = BRACE * tall
    var stave = List[Vector3]()
    var radii = List[Float32]()
    var wrap = List[Vector3]()
    var wrap_radii = List[Float32]()
    for k in range(STAVE_RINGS + 1):  # pragma: no branch
        var t = 2 * Float32(k) / Float32(STAVE_RINGS) - 1
        # The stave bends back from the string: its tips are level with
        # the string, its grip `brace` behind it.
        var p = Vector3(0, half * t, brace * (t * t - 1))
        stave.append(p)
        radii.append(STAVE_TIP + (STAVE_GRIP - STAVE_TIP) * (1 - abs(t)))
        if abs(half * t) <= GRIP_LENGTH / 2 + half / Float32(STAVE_RINGS):
            wrap.append(p)
            wrap_radii.append(STAVE_GRIP * 1.25)
    var bow = _painted(sweep(stave, radii, STAVE_SIDES), wood)
    bow = merge(bow, _painted(sweep(wrap, wrap_radii, STAVE_SIDES), grip))
    var cord: List[Vector3] = [Vector3(0, -half, 0), Vector3(0, half, 0)]
    var thin: List[Float32] = [0.0015, 0.0015]
    return merge(bow, _painted(sweep(cord, thin, 4), string))


def hip_quiver(
    length: Length, leather: Color, shafts: Color, fletching: Color
) raises -> BufferGeometry:
    """Return a quiver of arrows, painted.

    Args:
        length: How long the quiver is, from its mouth to its foot.
        leather: The quiver's color, sRGB.
        shafts: The arrows' color, sRGB.
        fletching: The feathers' color, sRGB.

    Returns:
        One mesh: the quiver, the arrows and their feathers.

    Raises:
        Error: If the length is not positive.
    """
    var long = length.to(METER)
    if not (long > 0):
        raise Error("A quiver needs a positive length")
    var tube = lathe(
        [
            Vector2(0.0, -long),
            Vector2(0.038, -long),
            Vector2(0.045, 0.0),
            Vector2(0.041, 0.0),
            Vector2(0.034, -long + 0.01),
        ],
        16,
    )
    var quiver = _painted(tube^, leather)
    for k in range(QUIVER_ARROWS):  # pragma: no branch
        var turn = 2 * Float32(pi) * Float32(k) / Float32(QUIVER_ARROWS)
        var ring = Float32(0.022) if k % 2 == 0 else Float32(0.012)
        var x = ring * cos(turn)
        var z = ring * sin(turn)
        var top = ARROW_STAND + 0.012 * Float32(k % 3)
        var shaft = lathe(
            [
                Vector2(0.0, -long + 0.02),
                Vector2(0.004, -long + 0.02),
                Vector2(0.004, top),
                Vector2(0.0, top),
            ],
            6,
        )
        var fins = box(
            Length(0.022, METER), Length(0.09, METER), Length(0.002, METER)
        )
        var placed = shaft.clone_attribute(String(POSITION))
        for v in range(placed.count()):  # pragma: no branch
            placed.set_component(v, 0, placed.component(v, 0) + x)
            placed.set_component(v, 2, placed.component(v, 2) + z)
        shaft.set_attribute(String(POSITION), placed^)
        var feathers = fins.clone_attribute(String(POSITION))
        for v in range(feathers.count()):  # pragma: no branch
            # Turned to face out from the quiver's axis.
            var u = feathers.component(v, 0)
            var w = feathers.component(v, 2)
            feathers.set_component(v, 0, x + u * cos(turn) - w * sin(turn))
            feathers.set_component(v, 1, feathers.component(v, 1) + top - 0.06)
            feathers.set_component(v, 2, z + u * sin(turn) + w * cos(turn))
        fins.set_attribute(String(POSITION), feathers^)
        var turned = fins.clone_attribute(String(NORMAL))
        for v in range(turned.count()):  # pragma: no branch
            var u = turned.component(v, 0)
            var w = turned.component(v, 2)
            turned.set_component(v, 0, u * cos(turn) - w * sin(turn))
            turned.set_component(v, 2, u * sin(turn) + w * cos(turn))
        fins.set_attribute(String(NORMAL), turned^)
        quiver = merge(quiver, _painted(shaft^, shafts))
        quiver = merge(quiver, _painted(fins^, fletching))
    return quiver^


comptime BOW_TILT = Float32(30)
"""How far a carried bow leans forward from upright, in degrees, so its
lower tip clears the ground."""
comptime BOW_SHARE = Float32(0.95)
"""How tall a longbow is, as a share of its archer's stature."""
comptime QUIVER_SHARE = Float32(0.28)
"""How long a quiver is, as a share of its archer's stature."""
comptime QUIVER_LEAN = Float32(28)
"""How far a quiver on the back leans from upright, in degrees, its mouth
over the right shoulder."""


def equip_archer(
    mut scene: Scene,
    mut assets: Assets,
    person: GameHumanoid,
    look: MaterialId,
    quivered: Bool = True,
) raises -> List[NodeId]:
    """Give a person a longbow in the left hand and a quiver on the back.

    The bow is `BOW_SHARE` of the person's stature, leaning `BOW_TILT`
    forward so its lower tip clears the ground. The quiver hangs on the
    back, leaning `QUIVER_LEAN` so its arrows stand over the right
    shoulder. A person in a cloak carries the bow alone: pass `quivered`
    False, or the quiver would stand through the cloak.

    Args:
        scene: The scene the person is in.
        assets: The store the meshes go in.
        person: The archer.
        look: A material with vertex colors on, for the painted props.
        quivered: Whether to hang the quiver too. True by default.

    Returns:
        The nodes the props hang from: the bow's, then the quiver's.

    Raises:
        Error: If the scene refuses a node or a mesh.
    """
    var nodes = List[NodeId]()
    var tall = person.rig.stature
    var tilted = Object3D()
    tilted.rotate_x(Angle(BOW_TILT, DEGREE))
    var held = attach(scene, person, LEFT_GRIP, tilted^)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                longbow(
                    Length(tall * BOW_SHARE, METER),
                    Color(150, 104, 58),
                    Color(70, 46, 30),
                    Color(226, 220, 196),
                )
            ),
            look,
            held,
        )
    )
    nodes.append(held)
    if not quivered:
        return nodes^
    var turned = Object3D()
    turned.rotate_y(Angle(180.0, DEGREE))
    var back = attach(scene, person, BACK, turned^)
    var hung = Object3D()
    hung.set_position(0.08 * tall / 1.75, 0.16 * tall / 1.75, 0.06)
    hung.rotate_z(Angle(QUIVER_LEAN, DEGREE))
    var slung = scene.attach(hung^, back)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                hip_quiver(
                    Length(tall * QUIVER_SHARE, METER),
                    Color(104, 66, 40),
                    Color(196, 164, 112),
                    Color(236, 234, 226),
                )
            ),
            look,
            slung,
        )
    )
    nodes.append(slung)
    return nodes^
