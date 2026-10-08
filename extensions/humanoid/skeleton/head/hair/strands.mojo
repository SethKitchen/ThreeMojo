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
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from core.geometry_store import GeometryId
from core.interleaved_buffer import InterleavedBuffer
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.skeleton.complexion import hair_tone
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.groom import (
    GroomSpec,
    HairGroom,
    groom_hair,
    groom_lines,
)
from extensions.humanoid.skeleton.head.hair.styles import GROWN, HairStyle
from extensions.humanoid.skeleton.head.hair.density import HairDensity
from extensions.humanoid.skeleton.head.hair.shading import (
    HairLight,
    HairLook,
    shade_groom_into,
)
from extensions.humanoid.spec import HumanoidSpec
from materials.material import (
    DEFAULT_LINE_WIDTH,
    LineWidth,
    MaterialId,
    OPAQUE,
    line_material,
)
from math.vector3 import Vector3
from std.math import isfinite, max
from objects.line_segments2 import LineSegments2, STRAND_LINE_COVERAGE


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
    var density: HairDensity
    var node: Optional[NodeId]
    var material: Optional[MaterialId]
    var _topology: List[Int]
    var _buffer: InterleavedBuffer
    var _point_colors: List[Float32]
    var _optical_depths: List[Float32]
    var _installed: Bool

    def __init__(
        out self, var groom: HairGroom, geometry: GeometryId, look: HairLook
    ) raises:
        """Keep a groom and the geometry that draws it.

        Args:
            groom: The strands, in the frame of the node they hang from.
            geometry: The id of their wide-line geometry.
            look: How the fibers scatter light.

        Raises:
            Error: If the groom has invalid topology or positions.
        """
        self.density = HairDensity()
        self.density.rebuild(groom)
        self._topology = groom.starts.copy()
        var segments = 0
        for strand in range(len(groom)):
            segments += max(
                0, groom.starts[strand + 1] - groom.starts[strand] - 1
            )
        if segments <= 0:
            raise Error("Hair strands need at least one segment")
        self._buffer = InterleavedBuffer(
            List[Float32](length=segments * 12, fill=0), 6
        )
        self._point_colors = List[Float32](length=len(groom.points) * 3, fill=0)
        self._optical_depths = List[Float32]()
        self._installed = False
        self.node = None
        self.material = None
        self.groom = groom^
        self.geometry = geometry
        self.look = look

    def shade(
        mut self,
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
            Error: If the store no longer holds this groom's geometry,
            topology changed, or the density or shading fields are invalid.
        """
        self._check_geometry(assets)
        self.density.rebuild(self.groom)
        self._shadow_depths(lights)
        shade_groom_into(
            self.groom,
            self.look,
            lights,
            camera,
            ambient,
            self._point_colors,
            self._optical_depths,
        )
        self._upload(assets)

    def _check_geometry(self, assets: Assets) raises:
        """Check topology and the retained geometry's buffer ownership."""
        if len(self.groom.starts) != len(self._topology):
            raise Error("Hair strand topology cannot change during an update")
        if self.groom.starts != self._topology:
            raise Error("Hair strand topology cannot change during an update")
        # Check ownership before writing through retained shared buffers.
        # A replacement geometry, or an equal slot in another store, must
        # never be silently updated as though it belonged to this groom.
        ref held = assets.geometries.get(self.geometry)
        if self._installed:
            if not held.has_attribute(
                String(POSITION)
            ) or not held.has_attribute(String(COLOR)):
                raise Error("The stored hair geometry was replaced")
            ref position = held.attribute_view(String(POSITION))
            ref color = held.attribute_view(String(COLOR))
            if not position.is_interleaved() or not color.is_interleaved():
                raise Error("The stored hair geometry was replaced")
            if not position.interleaved_buffer().shares_with(
                self._buffer
            ) or not color.interleaved_buffer().shares_with(self._buffer):
                raise Error("The stored hair geometry belongs to another owner")

    def _shadow_depths(mut self, lights: List[HairLight]) raises:
        """Fill the retained point-major optical-depth workspace."""
        var depth_count = len(self.groom.points) * len(lights)
        if len(self._optical_depths) != depth_count:
            self._optical_depths = List[Float32](length=depth_count, fill=0)
        for point in range(len(self.groom.points)):
            for light in range(len(lights)):
                self._optical_depths[
                    point * len(lights) + light
                ] = self.density.optical_depth(
                    self.groom.points[point], lights[light].direction
                )

    def _upload(mut self, mut assets: Assets) raises:
        """Write current positions and colors into the retained CPU buffer."""
        var vertex = 0
        for strand in range(len(self.groom)):
            for point in range(
                self.groom.starts[strand], self.groom.starts[strand + 1] - 1
            ):
                for end in range(2):
                    var index = point + end
                    var position = self.groom.points[index]
                    self._buffer.set_value(vertex * 6, position.x)
                    self._buffer.set_value(vertex * 6 + 1, position.y)
                    self._buffer.set_value(vertex * 6 + 2, position.z)
                    for channel in range(3):
                        self._buffer.set_value(
                            vertex * 6 + 3 + channel,
                            self._point_colors[index * 3 + channel],
                        )
                    vertex += 1
        if not self._installed:
            var geometry = BufferGeometry()
            geometry.set_attribute(
                String(POSITION), BufferAttribute(self._buffer, 3, 0)
            )
            geometry.set_attribute(
                String(COLOR), BufferAttribute(self._buffer, 3, 3)
            )
            assets.geometries.replace(self.geometry, geometry^)
            self._installed = True


def add_strands(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    var groom: HairGroom,
    look: HairLook,
    width: LineWidth = DEFAULT_LINE_WIDTH,
    opacity: Float32 = 0.65,
) raises -> HairStrands:
    """Attach a groom with feathered hashed coverage and strand shadows.

    Each accepted sample writes opaque depth. Rejected samples reveal
    surfaces behind it. This is stochastic coverage, not alpha blending.
    The geometry uses the same rule in camera and light views.

    Args:
        scene: The scene that receives a dedicated child node.
        assets: The store for one geometry and one material.
        parent: The node whose local frame holds the groom.
        groom: The strands to take ownership of.
        look: Their strand-space scattering parameters.
        width: The line width in output pixels or physical length.
        opacity: Sample coverage from zero through one.

    Returns:
        The persistent groom, ready for shade with the scene's lights.

    Raises:
        Error: If the parent, groom, width or opacity is invalid.
    """
    if not isfinite(opacity) or opacity < 0 or opacity > 1:
        raise Error("Strand opacity must be finite and between zero and one")
    var parent_object = scene.get(parent)
    if (
        len(groom.normals) != len(groom.points)
        or len(groom.depths) != len(groom.points)
        or len(groom.shades) != len(groom)
    ):
        raise Error("Hair shading fields must match the groom")
    var shape = groom_lines(groom)
    if shape.attribute_view(String(POSITION)).count() == 0:
        raise Error("Hair strands need at least one segment")
    # Validate before adding any scene or store entry. The append-only
    # stores on this API baseline cannot roll back a failed attachment.
    var checked_density = HairDensity()
    checked_density.rebuild(groom)
    var paint = line_material(
        line_width=width, vertex_colors=True, opacity=opacity, blending=OPAQUE
    )
    var geometry = assets.geometries.add(shape^)
    var strands = HairStrands(groom^, geometry, look)
    var material = assets.materials.add(paint)
    var object = Object3D()
    object.parent = parent
    object.layers = parent_object.layers
    var node = scene.add(object^)
    scene.add_wide_line(
        LineSegments2(
            geometry,
            material,
            node,
            frustum_culled=False,
            coverage=STRAND_LINE_COVERAGE,
            cast_shadow=True,
        )
    )
    strands.node = node
    strands.material = material
    # Install colors even with no direct light. The caller can replace
    # them without replacing either stored resource on subsequent frames.
    strands.shade(
        assets, List[HairLight](), Vector3(0, 0, 1), Vector3(0.1, 0.1, 0.1)
    )
    return strands^


def add_groom(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    guides: Int = 1500,
    followers: Int = 6,
    seed: Int = 1,
    width: Float32 = 1.0,
    style: HairStyle = GROWN,
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
        style: How the hair is cut and laid; `GROWN` by default. See
            `HairStyle`.

    Returns:
        The strands, for `HairStrands.shade`.

    Raises:
        Error: If the spec, a count, the width or the style is refused,
            or no guide finds a root.
    """
    var dims = head_muscle_dimensions(spec)
    var groom = groom_hair(
        dims, GroomSpec(dims, guides, followers), seed, style
    )
    var tone = hair_tone(spec.genome)
    var look = HairLook(
        Vector3(_linear(tone.r), _linear(tone.g), _linear(tone.b))
    )
    var strands = add_strands(
        scene, assets, parent, groom^, look, LineWidth(pixels=width)
    )
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
