# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hair cards: a groom drawn as ribbons that a game can afford.

A strand drawn as a wide line costs the rasterizer a quad and two round
caps for each of its segments. A head of a few thousand strands then
costs gigabytes of raster corners a frame, far too much for a crowd.
Games draw hair as cards: ribbons laid on the hair, each textured with
many fibers. `HairCards` makes one card from each guide strand of a
groom:

1. `card_groom` keeps the groom's guide strands and drops their
   followers: the fibers of each card stand for them. A long strand
   keeps at most `CARD_POINTS` of its points, evenly spaced along it.
2. Each card is a ribbon along its strand. It lies flat on the hair: it
   spans the strand and the direction across the hair there. It is
   `root_width` wide at the root and narrows to `tip_width` at the tip.
3. `fiber_texture` gives the fibers: `FIBERS` fibers across a card, each
   a ridge of alpha in a shade of its own, and some ending short of the
   tile's end. The material cuts away alpha below one half, so the
   fibers show crisp and the gaps between them show the cards and the
   shell beneath.
4. Each point is shaded as a strand's point is: Kajiya and Kay's diffuse,
   Marschner's R, TT and TRT, and its depth in the hair toward each
   light. The density counts each card as `CARD_FIBERS` fibers. So the
   cards light as the strands do, and cost a mesh's triangles to draw.

A groom of cards moves under `HairSimulation` as strands do, with fewer
points to move. `HairCards.shade` writes the moved points into the
ribbons and lights them.

This is not a three.js port. See Extensions.

    var cards = add_hair_cards(scene, assets, holder, person, 600)
    cards.shade(assets, lights, camera, ambient)
"""

from std.math import sqrt

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, UV, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.skeleton.complexion import hair_tone
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.density import HairDensity
from extensions.humanoid.skeleton.head.hair.groom import (
    GroomSpec,
    HairGroom,
    follower_across,
    groom_hair,
)
from extensions.humanoid.skeleton.head.hair.shading import (
    HairLight,
    HairLook,
    require_groom_fields,
    shade_groom_into,
)
from extensions.humanoid.skeleton.head.hair.strands import hair_shadow_depths
from extensions.humanoid.skeleton.head.hair.styles import GROWN, HairStyle
from extensions.humanoid.spec import HumanoidSpec
from materials.material import BASIC, DOUBLE_SIDE, Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.srgb import LINEAR, srgb_to_linear
from render.texture import BILINEAR, REPEAT, Texture
from render.texture_store import TextureId
from units.si import METER, Length

comptime CARD_POINTS = 16
"""The most points a card keeps of its strand."""
comptime FIBERS = 12
"""How many fibers lie across one card."""
comptime CARD_FIBERS = Float32(60)
"""How many fibers of hair one card stands for, in the density."""
comptime FIBER_DIAMETER = Float32(0.00008)
"""The diameter of one fiber of hair, in meters."""
comptime FIBER_TEXELS = 64
"""The side of the fiber texture, in texels."""
comptime CARD_TILE = Float32(0.08)
"""How far along a card the fiber texture repeats, in meters."""
comptime CARD_CUTOFF = Float32(0.5)
"""The alpha below which a card's texel is cut away."""
comptime CARD_SPACING = Float32(2.2)
"""A card's root width for each square root of the scalp's share a card
covers, in template centimeters: 2.2 for one card in 600."""
comptime TIP_SHARE = Float32(0.2)
"""How wide a card is at its tip, for its width at the root."""
comptime ROOT_SHADE = Float32(0.55)
"""How bright a card is at its root, for its brightness past
`ROOT_REACH` of its length: the hair near the scalp lies under the rest."""
comptime ROOT_REACH = Float32(0.35)
"""How far along a card, as a share of its length, its root's shade
lifts to its full brightness."""


def _hash(a: Int, b: Int) -> Float32:
    """Return a number from zero to one that two integers pick."""
    var x = UInt64(a) * 0x9E3779B97F4A7C15 + UInt64(b) * 0xBF58476D1CE4E5B9
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9
    x = (x ^ (x >> 27)) * 0x94D049BB133111EB
    x = x ^ (x >> 31)
    return Float32(Int(x >> 40)) / Float32(1 << 24)


def fiber_heights(seed: Int = 1) -> List[Float32]:
    """Return the alpha of one tile of fibers, row by row.

    `FIBERS` fibers lie across the tile, along its rows' direction down.
    Each fiber is a ridge one at its middle and zero at its edge, a
    little wider or narrower than the others. The ridges overlap, so
    about two thirds of the tile is above the cutoff: a card seen from
    far off, whose texels its mipmaps average, stays whole. About one
    fiber in four ends somewhere along the tile and starts again a
    little further on, so the fibers do not run as even stripes.

    Args:
        seed: Which fibers.

    Returns:
        `FIBER_TEXELS` by `FIBER_TEXELS` values, zero through one.
    """
    var alpha = List[Float32](length=FIBER_TEXELS * FIBER_TEXELS, fill=0)
    var lane = Float32(FIBER_TEXELS) / Float32(FIBERS)
    for fiber in range(FIBERS):
        var middle = (Float32(fiber) + 0.25 + 0.5 * _hash(seed, fiber)) * lane
        var half = lane * (0.55 + 0.3 * _hash(seed, fiber + 100))
        var gap_at = Int(_hash(seed, fiber + 200) * Float32(FIBER_TEXELS))
        var gap = 0
        if _hash(seed, fiber + 300) < 0.25:
            gap = 4 + Int(_hash(seed, fiber + 400) * 8)
        for row in range(FIBER_TEXELS):
            var since = (row - gap_at + FIBER_TEXELS) % FIBER_TEXELS
            if since < gap:
                continue
            for column in range(FIBER_TEXELS):
                var d = abs(Float32(column) + 0.5 - middle)
                # The tile wraps across, as the fibers of the card next
                # to it would.
                d = min(d, Float32(FIBER_TEXELS) - d)
                var ridge = 1 - d / half
                if ridge <= 0:
                    continue
                ref here = alpha[row * FIBER_TEXELS + column]
                here = max(here, ridge)
    return alpha^


def fiber_texture(seed: Int = 1) raises -> Texture:
    """Return the fibers of a card as a tiling texture.

    The color is white, a little darker for some fibers than for others
    and darker toward each fiber's edge, so the vertex colors carry the
    hair's shading and the texture adds only its grain. The alpha is
    `fiber_heights`.

    Args:
        seed: Which fibers.

    Returns:
        A repeating, mipmapped, linear RGBA texture.

    Raises:
        Error: If the texture constructor refuses it, which it does not.
    """
    var alpha = fiber_heights(seed)
    var lane = Float32(FIBER_TEXELS) / Float32(FIBERS)
    var pixels = List[UInt8](capacity=4 * FIBER_TEXELS * FIBER_TEXELS)
    for row in range(FIBER_TEXELS):
        for column in range(FIBER_TEXELS):
            var fiber = Int(Float32(column) / lane) % FIBERS
            var a = alpha[row * FIBER_TEXELS + column]
            var shade = (0.7 + 0.3 * _hash(seed, fiber + 500)) * (
                0.45 + 0.55 * min(Float32(1), a)
            )
            var byte = UInt8(Int(shade * 255 + 0.5))
            pixels.append(byte)
            pixels.append(byte)
            pixels.append(byte)
            pixels.append(UInt8(Int(min(Float32(1), a) * 255 + 0.5)))
    return Texture(
        FIBER_TEXELS,
        FIBER_TEXELS,
        pixels^,
        REPEAT,
        BILINEAR,
        color_space=LINEAR,
    )


def card_groom(groom: HairGroom, most: Int = CARD_POINTS) raises -> HairGroom:
    """Return a groom's guide strands, each with at most `most` points.

    A strand with more points keeps its root, its tip, and points evenly
    spaced by index between them. Its normals, depths and shade go with
    the points it keeps.

    Args:
        groom: A groom. A strand whose guide is -1 is a guide; with no
            guide records, every strand is one.
        most: The most points a card keeps, two or more.

    Returns:
        A groom of the guide strands alone, with no followers.

    Raises:
        Error: If `most` is below two, or the groom keeps no strand.
    """
    if most < 2:
        raise Error("A card keeps two points of its strand or more")
    var cards = HairGroom()
    var strands = len(groom)
    var known = len(groom.guides) == strands
    for strand in range(strands):
        if known and groom.guides[strand] != -1:
            continue
        var first = groom.starts[strand]
        var count = groom.starts[strand + 1] - first
        if count < 2:
            continue
        var keep = min(count, most)
        var points = List[Vector3](capacity=keep)
        var normals = List[Vector3](capacity=keep)
        var depths = List[Float32](capacity=keep)
        for k in range(keep):
            var index = first + (k * (count - 1) + (keep - 1) // 2) // (
                keep - 1
            )
            points.append(groom.points[index])
            normals.append(groom.normals[index])
            depths.append(groom.depths[index])
        cards.add(points, normals, depths, groom.shades[strand])
    if len(cards) == 0:
        raise Error("A groom of cards needs a guide strand of two points")
    return cards^


def card_width(spec: HumanoidSpec, cards: Int) raises -> Float32:
    """Return how wide a card is at its root, for a number of cards.

    The cards share the scalp: each covers its share, with enough to
    spare that the cards next to it overlap.

    Args:
        spec: The person.
        cards: How many cards cover the scalp, one or more.

    Returns:
        The width at the root, in meters.

    Raises:
        Error: If `cards` is below one, or the spec is refused.
    """
    if cards < 1:
        raise Error("A scalp needs one card or more")
    var h = head_muscle_dimensions(spec).head.copy()
    return h.cm(CARD_SPACING * sqrt(Float32(600) / Float32(cards)))


struct HairCards(Movable):
    """A groom in a scene, drawn as one card for each strand."""

    var groom: HairGroom
    """The strands the cards lie along, in the frame of their node."""
    var geometry: GeometryId
    """The id of the cards' mesh."""
    var look: HairLook
    """How the fibers scatter light."""
    var density: HairDensity
    """The hair's density, for its depth toward each light."""
    var root_width: Float32
    """How wide each card is at its root, in meters."""
    var tip_width: Float32
    """How wide each card is at its tip, in meters."""
    var node: Optional[NodeId]
    """The node the cards hang from, once they are in a scene."""
    var material: Optional[MaterialId]
    """The cards' material, once they are in a scene."""
    var _colors: List[Float32]
    var _depths: List[Float32]

    def __init__(
        out self,
        var groom: HairGroom,
        geometry: GeometryId,
        look: HairLook,
        root_width: Float32,
        tip_width: Float32,
    ) raises:
        """Keep a groom of cards and the id of the mesh that draws it.

        Args:
            groom: One strand per card, as `card_groom` gives.
            geometry: The id of the mesh the cards are written into.
            look: How the fibers scatter light.
            root_width: The width at each root, in meters.
            tip_width: The width at each tip, in meters.

        Raises:
            Error: If the groom has no strand or its fields do not match
                its points, or a width is not positive and finite.
        """
        if len(groom) == 0:
            raise Error("Hair cards need a strand")
        require_groom_fields(groom)
        if not (root_width > 0 and root_width < 1) or not (
            tip_width > 0 and tip_width < 1
        ):
            raise Error("A card's widths must be positive and below a meter")
        self.density = HairDensity(
            diameter=Length(FIBER_DIAMETER * CARD_FIBERS, METER)
        )
        self._colors = List[Float32](length=3 * len(groom.points), fill=0)
        self._depths = List[Float32]()
        self.groom = groom^
        self.geometry = geometry
        self.look = look
        self.root_width = root_width
        self.tip_width = tip_width
        self.node = None
        self.material = None

    def mesh(self) raises -> BufferGeometry:
        """Return the cards' mesh for the groom's points and last colors.

        Each point gives two vertices, one each side of the strand across
        the hair. Each card's texture coordinates run across it from zero
        to one, and along it in tiles of `CARD_TILE`. A card is darker at
        its root, by `ROOT_SHADE`, and lifts to its full shading over
        `ROOT_REACH` of its length.

        Returns:
            Positions, colors and texture coordinates, two triangles for
            each segment of each strand.

        Raises:
            Error: If the groom's starts do not partition its points.
        """
        var count = len(self.groom.points)
        var positions = List[Float32](capacity=6 * count)
        var colors = List[Float32](capacity=6 * count)
        var uvs = List[Float32](capacity=4 * count)
        var index = List[Int]()
        for strand in range(len(self.groom)):
            var first = self.groom.starts[strand]
            var last = self.groom.starts[strand + 1] - 1
            if last <= first:
                raise Error("Each card needs two points of its strand")
            var along = Float32(0)
            for k in range(first, last + 1):
                var p = self.groom.points[k]
                if k > first:
                    along += (p - self.groom.points[k - 1]).length()
                var share = Float32(k - first) / Float32(last - first)
                var width = (
                    self.root_width + (self.tip_width - self.root_width) * share
                )
                var across = follower_across(
                    self.groom.points[max(k - 1, first)],
                    self.groom.points[min(k + 1, last)],
                    self.groom.normals[k],
                ) * (width * 0.5)
                var lift = ROOT_SHADE + (1 - ROOT_SHADE) * min(
                    Float32(1), share / ROOT_REACH
                )
                for side in range(2):
                    var q = p - across if side == 0 else p + across
                    positions.append(q.x)
                    positions.append(q.y)
                    positions.append(q.z)
                    for c in range(3):
                        colors.append(self._colors[3 * k + c] * lift)
                    uvs.append(Float32(side))
                    uvs.append(along / CARD_TILE)
                if k > first:
                    var a = 2 * (k - 1)
                    index.append(a)
                    index.append(a + 1)
                    index.append(a + 2)
                    index.append(a + 1)
                    index.append(a + 3)
                    index.append(a + 2)
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
        geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
        geometry.set_index(index^)
        return geometry^

    def shade(
        mut self,
        mut assets: Assets,
        lights: List[HairLight],
        camera: Vector3,
        ambient: Vector3,
    ) raises:
        """Light the cards for a camera and lights, and write their mesh.

        Call it after the groom moves, or when the camera or the lights
        move.

        Args:
            assets: The store that holds the cards' mesh.
            lights: The distant lights, in the cards' frame.
            camera: Where the camera is, in the cards' frame.
            ambient: The light from all round, linear.

        Raises:
            Error: If a light, the density or a shading field is refused,
                or the store does not hold the cards' mesh.
        """
        self.density.rebuild(self.groom)
        hair_shadow_depths(
            self.density, self.groom.points, lights, self._depths
        )
        shade_groom_into(
            self.groom,
            self.look,
            lights,
            camera,
            ambient,
            self._colors,
            self._depths,
        )
        assets.geometries.replace(self.geometry, self.mesh())


def card_material(fibers: TextureId) raises -> Material:
    """Return the material that draws hair cards.

    It is unlit: the cards' vertex colors carry the strand shading. The
    fibers' alpha cuts each card at `CARD_CUTOFF`, and both faces show.

    Args:
        fibers: The id of a `fiber_texture`.

    Returns:
        A `BASIC` material with vertex colors on.

    Raises:
        Error: If the material constructor refuses the values.
    """
    return Material(
        Color(255, 255, 255),
        map=fibers,
        side=DOUBLE_SIDE,
        kind=BASIC,
        vertex_colors=True,
        alpha_test=CARD_CUTOFF,
    )


def add_cards(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    var groom: HairGroom,
    look: HairLook,
    root_width: Float32,
    seed: Int = 1,
) raises -> HairCards:
    """Draw a groom's guide strands as cards under `parent`.

    Args:
        scene: The scene that receives a node and the cards' mesh.
        assets: The store for the mesh, the fibers and the material.
        parent: The node whose frame holds the groom.
        groom: A groom; `card_groom` keeps its guide strands.
        look: How the fibers scatter light.
        root_width: How wide each card is at its root, in meters.
        seed: Which fibers.

    Returns:
        The cards, lit for a light over the right shoulder and a camera
        in front; call `HairCards.shade` for the scene's.

    Raises:
        Error: If the groom has no guide strand of two points, the width
            is refused, or the parent is not in the scene.
    """
    var parent_object = scene.get(parent)
    var cards_groom = card_groom(groom)
    var geometry = assets.geometries.add(BufferGeometry())
    var cards = HairCards(
        cards_groom^, geometry, look, root_width, root_width * TIP_SHARE
    )
    var fibers = assets.textures.add(fiber_texture(seed))
    var material = assets.materials.add(card_material(fibers))
    var object = Object3D()
    object.parent = parent
    object.layers = parent_object.layers
    var node = scene.add(object^)
    var mesh = Mesh(geometry, material, node)
    mesh.cast_shadow = True
    scene.add_mesh(mesh)
    cards.node = node
    cards.material = material
    var key = Vector3(1, 2, 2)
    key.normalize()
    var lights = List[HairLight]()
    lights.append(HairLight(key, Vector3(2, 2, 2)))
    var center = Vector3(0, 0, 0)
    for p in cards.groom.points:
        center = center + p
    center = center * (1 / Float32(len(cards.groom.points)))
    cards.shade(
        assets, lights, center + Vector3(0, 0, 1), Vector3(0.1, 0.1, 0.1)
    )
    return cards^


def add_hair_cards(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    cards: Int = 600,
    seed: Int = 1,
    style: HairStyle = GROWN,
) raises -> HairCards:
    """Grow a person's scalp hair and draw it as cards under `parent`.

    The groom grows `cards` guide strands and no followers, in the
    pelvis frame, as `add_groom` grows strands. Each guide is a card,
    wide enough that the cards cover the scalp.

    Args:
        scene: The scene that receives the cards.
        assets: The store for their mesh, fibers and material.
        parent: The node they hang from.
        spec: Standing height, osteological sex, athleticism and genome.
        cards: How many cards, one or more.
        seed: Picks the roots, the lengths, the sway and the fibers.
        style: How the hair is cut and laid; `GROWN` by default.

    Returns:
        The cards, for `HairCards.shade`.

    Raises:
        Error: If the spec, the count or the style is refused, or no
            guide finds a root.
    """
    var dims = head_muscle_dimensions(spec)
    var groom = groom_hair(dims, GroomSpec(dims, cards, 0), seed, style)
    var tone = hair_tone(spec.genome)
    var look = HairLook(
        Vector3(
            srgb_to_linear(Float32(tone.r) / 255),
            srgb_to_linear(Float32(tone.g) / 255),
            srgb_to_linear(Float32(tone.b) / 255),
        )
    )
    return add_cards(
        scene, assets, parent, groom^, look, card_width(spec, cards), seed
    )
