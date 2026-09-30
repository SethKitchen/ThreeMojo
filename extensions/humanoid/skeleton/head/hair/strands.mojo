# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The scalp's hair as strands in a scene: a groom drawn as wide lines,
in colors worked out in strand space.

`add_groom` grows a person's groom (see `groom`), shades it (see
`shading`) and draws each strand as a `LineSegments2` a pixel or so
wide, unlit, in the colors of its points. A strand is far thinner than
a pixel, so a line a pixel wide stands for it, as Frostbite's hair
widens its strands with distance.

The shading depends on where the camera and the lights are. `shade`
works it out again: call it when the head turns or the camera moves.

This is not a three.js port. See Extensions.

    var hair = add_groom(scene, assets, holder, person)
    hair.shade(assets, lights, camera, ambient)
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR
from core.geometry_store import GeometryId
from core.object3d import NodeId
from core.scene import Scene
from extensions.humanoid.skeleton.complexion import hair_tone
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.groom import (
    GroomSpec,
    HairGroom,
    groom_hair,
    groom_lines,
)
from extensions.humanoid.skeleton.head.hair.shading import (
    HairLight,
    HairLook,
    segment_colors,
    shade_groom,
)
from extensions.humanoid.spec import HumanoidSpec
from materials.material import LineWidth, line_material
from math.vector3 import Vector3
from objects.line_segments2 import LineSegments2


def _linear(channel: UInt8) -> Float32:
    """Return one sRGB channel decoded to linear."""
    var x = Float32(channel) / 255
    if x <= Float32(0.04045):
        return x / Float32(12.92)
    return ((x + Float32(0.055)) / Float32(1.055)) ** Float32(2.4)


struct HairStrands(Movable):
    """A groom in a scene: its strands, the geometry that draws them,
    and how they scatter light."""

    var groom: HairGroom
    var geometry: GeometryId
    var look: HairLook

    def __init__(
        out self, var groom: HairGroom, geometry: GeometryId, look: HairLook
    ):
        """Keep a groom and the geometry that draws it.

        Args:
            groom: The strands, in the frame of the node they hang from.
            geometry: The id of their wide-line geometry.
            look: How the fibers scatter light.
        """
        self.groom = groom^
        self.geometry = geometry
        self.look = look

    def shade(
        self,
        mut assets: Assets,
        lights: List[HairLight],
        camera: Vector3,
        ambient: Vector3,
    ) raises:
        """Work the strands' colors out again for a camera and lights.

        Args:
            assets: The store that holds the strands' geometry.
            lights: The distant lights, in the strands' frame.
            camera: Where the camera is, in the strands' frame.
            ambient: The light from all round, linear.

        Raises:
            Error: If the store no longer holds the geometry.
        """
        var colors = segment_colors(
            self.groom,
            shade_groom(self.groom, self.look, lights, camera, ambient),
        )
        var geometry = groom_lines(self.groom)
        geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
        assets.geometries.replace(self.geometry, geometry^)


def add_groom(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    guides: Int = 1500,
    followers: Int = 6,
    seed: Int = 1,
    width: Float32 = 1.0,
) raises -> HairStrands:
    """Grow a person's scalp hair as strands and draw it under `parent`.

    The strands lie in the pelvis frame, as the head's meshes do, so
    `parent` is the node `add_head` or `add_body` hangs the head from.
    They are first shaded for a light over the right shoulder and a
    camera in front of the face; call `HairStrands.shade` for the scene's.

    Args:
        scene: The scene that receives the strands.
        assets: The store for their geometry and their material.
        parent: The node they hang from.
        spec: Standing height, osteological sex, athleticism and genome.
        guides: How many guide strands; see `GroomSpec`.
        followers: How many follow strands round each guide.
        seed: Picks the roots, the lengths and the sway.
        width: How wide each strand is drawn, in pixels.

    Returns:
        The strands, for `HairStrands.shade`.

    Raises:
        Error: If the spec, a count or the width is refused, or no guide
            finds a root.
    """
    var dims = head_muscle_dimensions(spec)
    var groom = groom_hair(dims, GroomSpec(dims, guides, followers), seed)
    var tone = hair_tone(spec.genome)
    var look = HairLook(
        Vector3(_linear(tone.r), _linear(tone.g), _linear(tone.b))
    )
    var material = assets.materials.add(
        line_material(line_width=LineWidth(pixels=width), vertex_colors=True)
    )
    var geometry = assets.geometries.add(groom_lines(groom))
    scene.add_wide_line(LineSegments2(geometry, material, parent))
    var strands = HairStrands(groom^, geometry, look)
    var key = Vector3(1, 2, 2)
    key.normalize()
    var lights = List[HairLight]()
    lights.append(HairLight(key, Vector3(2, 2, 2)))
    strands.shade(
        assets,
        lights,
        dims.head.at(0, 74.0, 100.0),
        Vector3(0.1, 0.1, 0.1),
    )
    return strands^
