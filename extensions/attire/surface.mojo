# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The surface of a fabric: texture coordinates round each bone, and the
bump maps of mail, quilting and weave.

The skin's own texture coordinates run round the body's vertical axis,
which says nothing along an arm. `garment_uvs` gives each vertex of a
garment coordinates of its own, in meters, round the bone that weighs
most on it: `u` round the bone, as an arc at its chain's mean radius,
and `v` down the chain. A chain is a run of bones that go on in about
one direction, such as the upper arm, the forearm and the hand, so `v`
runs on across the elbow. The garment is cut along a seam down the back
of each bone first, so the coordinates never wrap across a triangle. A
pattern then tiles at its true size, and it meets itself at the seams
and where one chain meets another, as the panels of a sewn garment do.

The bump maps are height images, one tile each:

| Map | Tile | What it shows |
|---|---|---|
| `mail_heights` | 4 cm, four rows of four rings | riveted rings, each row of rings set half a ring over the last |
| `quilt_heights` | 6 cm | the diamond quilting of a gambeson: grooves along both diagonals |
| `weave_heights` | 4 mm | a two-over-two twill of warp and weft |

`surface_look` gives a fabric's bump map, its scale and how many tiles a
meter, or no map for leather and plate. `SurfaceMaps` makes each map once
and gives it to every material that needs it.

This is not a three.js port. See Extensions.

    var piece = garment_uvs(shell, rig)
    var maps = SurfaceMaps()
    maps.apply(material, assets, MAIL)
"""

from std.math import atan2, floor, pi, sin, sqrt

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, UV, BufferGeometry
from extensions.attire.kinds import (
    BUMP_COUNT,
    LINEN,
    MAIL,
    MAIL_RINGS,
    NO_BUMP,
    PADDING,
    QUILTING,
    SILK,
    TWILL,
    VELVET,
    WOOL,
    Bump,
    FabricKind,
    require_bump,
    require_fabric_kind,
)
from extensions.attire.mesh_ops import cut, merge
from extensions.humanoid.rig.joints import (
    JOINT_COUNT,
    HumanoidRig,
    Joint,
    joint_parent,
)
from materials.material import Material
from math.utils import clamp
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from render.srgb import LINEAR
from render.texture import BILINEAR, IGNORED, REPEAT, Texture
from render.texture_store import NO_TEXTURE, TextureId

comptime MAIL_TILE = Float32(0.04)
"""The side of one tile of mail, in meters: four rings of a centimeter."""
comptime QUILT_TILE = Float32(0.06)
"""The side of one diamond of quilting, in meters."""
comptime WEAVE_TILE = Float32(0.004)
"""The side of one repeat of a twill weave, in meters."""
comptime TEXELS = 64
"""The side of each bump map, in texels."""
comptime CHAIN_BEND = Float32(0.7)
"""A bone goes on its parent's chain when the cosine of the angle between
them is above this: when it bends less than about 45 degrees."""
comptime CHAIN_SHARE = Float32(0.5)
"""The share of a vertex's skin weight that puts it in a chain's part."""


struct SurfaceLook(ImplicitlyCopyable):
    """A fabric's bump map: which one, how strong, how many tiles a meter."""

    var kind: Bump
    """Which bump map."""
    var scale: Float32
    """The bump scale the material takes."""
    var tiles: Float32
    """How many tiles a meter of garment coordinates holds."""

    def __init__(out self, kind: Bump, scale: Float32, tiles: Float32):
        """Hold a fabric's bump map.

        Args:
            kind: Which bump map.
            scale: The bump scale.
            tiles: Tiles a meter.
        """
        self.kind = kind
        self.scale = scale
        self.tiles = tiles

    def has_map(self) -> Bool:
        """Return whether the fabric has a bump map.

        Returns:
            False for leather and plate, which are smooth.
        """
        return self.kind != NO_BUMP


def surface_look(kind: FabricKind) raises -> SurfaceLook:
    """Return a fabric's bump map.

    Args:
        kind: A named fabric kind.

    Returns:
        Mail's rings, padding's quilting, cloth's weave, or none for
        leather and plate.

    Raises:
        Error: If the kind is not named.
    """
    require_fabric_kind(kind)
    if kind == MAIL:
        return SurfaceLook(MAIL_RINGS, 0.6, 1 / MAIL_TILE)
    if kind == PADDING:
        return SurfaceLook(QUILTING, 1.0, 1 / QUILT_TILE)
    if kind == LINEN or kind == WOOL or kind == SILK or kind == VELVET:
        return SurfaceLook(TWILL, 0.15, 1 / WEAVE_TILE)
    return SurfaceLook(NO_BUMP, 0, 1)


def _height_texture(heights: List[Float32]) raises -> Texture:
    """Return a tiling linear texture of heights, zero through one."""
    var pixels = List[UInt8](capacity=4 * TEXELS * TEXELS)
    for h in heights:  # pragma: no branch
        var byte = UInt8(Int(clamp(h, 0, 1) * 255 + 0.5))
        pixels.append(byte)
        pixels.append(byte)
        pixels.append(byte)
        pixels.append(255)
    return Texture(
        TEXELS,
        TEXELS,
        pixels^,
        REPEAT,
        BILINEAR,
        color_space=LINEAR,
        alpha=IGNORED,
    )


def _ring(d: Float32, radius: Float32, wire: Float32) -> Float32:
    """Return the height of a ring of wire at a distance from its center."""
    var off = abs(d - radius) / wire
    if off >= 1:
        return 0
    return sqrt(1 - off * off)


def mail_heights() -> List[Float32]:
    """Return the heights of one tile of mail: four rows of four rings.

    Each ring is a torus seen from above. Each row is set half a ring
    over the row above it, so each ring links its neighbors, as in the
    four-in-one pattern.

    Returns:
        `TEXELS` by `TEXELS` heights, row by row, zero through one.
    """
    var heights = List[Float32](capacity=TEXELS * TEXELS)
    var cell = Float32(TEXELS) / 4
    var radius = cell * 0.42
    var wire = cell * 0.14
    for y in range(TEXELS):  # pragma: no branch
        for x in range(TEXELS):  # pragma: no branch
            var best = Float32(0)
            for row in range(-1, 5):  # pragma: no branch
                var shift = cell / 2 if row % 2 != 0 else Float32(0)
                for column in range(-1, 5):  # pragma: no branch
                    var cx = (Float32(column) + 0.5) * cell + shift
                    var cy = (Float32(row) + 0.5) * cell
                    var dx = Float32(x) + 0.5 - cx
                    var dy = Float32(y) + 0.5 - cy
                    best = max(
                        best, _ring(sqrt(dx * dx + dy * dy), radius, wire)
                    )
            heights.append(best)
    return heights^


def quilt_heights() -> List[Float32]:
    """Return the heights of one diamond of quilting.

    The padding is full between the stitches and pressed down along both
    diagonals, where the stitching runs.

    Returns:
        `TEXELS` by `TEXELS` heights, row by row, zero through one.
    """
    var heights = List[Float32](capacity=TEXELS * TEXELS)
    var n = Float32(TEXELS)
    for y in range(TEXELS):  # pragma: no branch
        for x in range(TEXELS):  # pragma: no branch
            var u = (Float32(x) + 0.5) / n
            var v = (Float32(y) + 0.5) / n
            # Distance to the nearest diagonal, in tiles: zero on a seam.
            var a = abs(u + v - floor(u + v + 0.5))
            var b = abs(u - v - floor(u - v + 0.5))
            var seam = min(a, b)
            heights.append(clamp(seam * 6, 0, 1))
    return heights^


def weave_heights() -> List[Float32]:
    """Return the heights of one repeat of a two-over-two twill.

    Four warp threads cross four weft threads. A warp thread lies over two
    weft threads and under two, one thread further over in each row: the
    diagonal of twill.

    Returns:
        `TEXELS` by `TEXELS` heights, row by row, zero through one.
    """
    var heights = List[Float32](capacity=TEXELS * TEXELS)
    var cell = Float32(TEXELS) / 4
    for y in range(TEXELS):  # pragma: no branch
        for x in range(TEXELS):  # pragma: no branch
            var column = Int(Float32(x) / cell)
            var row = Int(Float32(y) / cell)
            var warp_over = (column + row) % 4 < 2
            # A thread is round across itself and full along its length.
            var across = (Float32(x) + 0.5) / cell - Float32(column)
            var along = (Float32(y) + 0.5) / cell - Float32(row)
            var t = across if warp_over else along
            var round = sin(Float32(pi) * t)
            heights.append(0.5 + 0.5 * round if warp_over else 0.5 * round)
    return heights^


def bump_texture(look: SurfaceLook) raises -> Texture:
    """Return a fabric's bump map, tiled at its true size.

    Args:
        look: A fabric's surface look that has a map.

    Returns:
        A tiling linear texture whose `repeat` holds the tiles a meter.

    Raises:
        Error: If the look has no map or its kind is not named.
    """
    require_bump(look.kind)
    var heights: List[Float32]
    if look.kind == MAIL_RINGS:
        heights = mail_heights()
    elif look.kind == QUILTING:
        heights = quilt_heights()
    elif look.kind == TWILL:
        heights = weave_heights()
    else:
        raise Error("This fabric has no bump map")
    var texture = _height_texture(heights)
    texture.repeat = Vector2(look.tiles, look.tiles)
    return texture^


struct SurfaceMaps(Movable):
    """The bump maps one dressing has made, each made once."""

    var ids: List[TextureId]
    """The texture of each bump map, or `NO_TEXTURE` until it is made."""

    def __init__(out self):
        """Hold no maps yet."""
        self.ids = List[TextureId](length=BUMP_COUNT, fill=NO_TEXTURE)

    def apply(
        mut self, mut look: Material, mut assets: Assets, kind: FabricKind
    ) raises:
        """Give a material its fabric's bump map, if the fabric has one.

        The first material of each bump map adds the texture to `assets`.
        Each later one shares it.

        Args:
            look: The fabric's material.
            assets: The store the texture goes in.
            kind: A named fabric kind.

        Raises:
            Error: If the kind is not named.
        """
        var surface = surface_look(kind)
        if not surface.has_map():
            return
        var at = surface.kind.value
        if self.ids[at] == NO_TEXTURE:
            self.ids[at] = assets.textures.add(bump_texture(surface))
        look.bump_map = self.ids[at]
        look.bump_scale = surface.scale


struct BoneFrame(ImplicitlyCopyable):
    """A bone's axis, and two directions across it."""

    var axis: Vector3
    """Down the bone, from its joint to its end."""
    var side: Vector3
    """Across the bone, to its right as it faces forward."""
    var forward: Vector3
    """Across the bone, toward the front where it can be."""

    def __init__(out self, rig: HumanoidRig, joint: Int):
        """Make a bone's frame from its joint and its end.

        A bone of no length points down.

        Args:
            rig: The rig.
            joint: The index of the bone's joint.
        """
        var along = rig.ends[joint] - rig.joints[joint]
        var length = along.length()
        self.axis = Vector3(0, -1, 0)
        if length > 0:
            self.axis = along * (1 / length)
        var front = Vector3(0, 0, 1)
        if abs(self.axis.z) > 0.9:
            front = Vector3(0, 1, 0)
        self.side = self.axis
        self.side.cross(front)
        self.side = self.side * (1 / self.side.length())
        self.forward = self.side
        self.forward.cross(self.axis)


struct BoneChains(Movable):
    """The chains of a rig: runs of bones that go on in about one
    direction."""

    var frames: List[BoneFrame]
    """Each bone's frame."""
    var roots: List[Int]
    """The first joint of each joint's chain."""
    var starts: List[Float32]
    """How far down its chain each joint is, in meters."""

    def __init__(out self, rig: HumanoidRig) raises:
        """Find the chains of a rig.

        A bone goes on its parent's chain when it bends less than about
        45 degrees from it. On the template the spine and the head make
        one chain, each arm one, each leg one and each foot one.

        Args:
            rig: The rig.

        Raises:
            Error: If the joint table is malformed.
        """
        self.frames = List[BoneFrame](capacity=JOINT_COUNT)
        self.roots = List[Int](capacity=JOINT_COUNT)
        self.starts = List[Float32](capacity=JOINT_COUNT)
        for j in range(JOINT_COUNT):  # pragma: no branch
            self.frames.append(BoneFrame(rig, j))
            var parent = joint_parent(Joint(j)).value
            if (
                j != parent
                and self.frames[parent].axis.dot(self.frames[j].axis)
                > CHAIN_BEND
            ):
                self.roots.append(self.roots[parent])
                self.starts.append(
                    self.starts[parent]
                    + (rig.ends[parent] - rig.joints[parent]).length()
                )
            else:
                self.roots.append(j)
                self.starts.append(0)


def _chain_shares(
    piece: BufferGeometry, chains: BoneChains, root: Int
) raises -> List[Float32]:
    """Return each vertex's skin weight on one chain, less `CHAIN_SHARE`."""
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var shares = List[Float32](capacity=bones.count())
    for v in range(bones.count()):
        var total = Float32(0)
        for k in range(4):  # pragma: no branch
            var joint = Int(bones.component(v, k))
            if joint < 0 or joint >= JOINT_COUNT:
                raise Error("A garment weight names no joint")
            if chains.roots[joint] == root:
                total += weights.component(v, k)
        shares.append(total - CHAIN_SHARE)
    return shares^


def _joints_on(
    piece: BufferGeometry, chains: BoneChains, root: Int
) raises -> List[Int]:
    """Return the joint of one chain that weighs most on each vertex.

    A negative `root` takes the joint that weighs most of all. A vertex
    with no weight on the chain takes the chain's first joint.
    """
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var joints = List[Int](capacity=bones.count())
    for v in range(bones.count()):
        var joint = root
        var best = Float32(-1)
        for k in range(4):  # pragma: no branch
            var j = Int(bones.component(v, k))
            var weight = weights.component(v, k)
            if (root < 0 or chains.roots[j] == root) and weight > best:
                joint = j
                best = weight
        joints.append(joint)
    return joints^


def _lay_out(
    part: BufferGeometry,
    rig: HumanoidRig,
    chains: BoneChains,
    root: Int,
    radius: List[Float32],
) raises -> BufferGeometry:
    """Cut one chain's part along its back seam and give it coordinates."""
    var joints = _joints_on(part, chains, root)
    ref placed = part.attribute_view(String(POSITION))
    var sides = List[Float32](capacity=placed.count())
    var negated = List[Float32](capacity=placed.count())
    for v in range(placed.count()):
        ref f = chains.frames[joints[v]]
        var side = (placed.vector3(v) - rig.joints[joints[v]]).dot(f.side)
        sides.append(side)
        negated.append(-side)
    var halves: List[BufferGeometry] = [
        cut(part, sides, 0),
        cut(part, negated, 0),
    ]
    for h in range(2):  # pragma: no branch
        var half = _joints_on(halves[h], chains, root)
        ref points = halves[h].attribute_view(String(POSITION))
        var uv = List[Float32](capacity=2 * points.count())
        for v in range(points.count()):
            var j = half[v]
            ref f = chains.frames[j]
            var rel = points.vector3(v) - rig.joints[j]
            var angle = atan2(rel.dot(f.side), rel.dot(f.forward))
            # Each half keeps its own side of the seam: the right half
            # runs zero to plus pi, the left zero to minus pi, and the
            # two meet at the front.
            if h == 0:
                angle = abs(angle)
            else:
                angle = -abs(angle)
            uv.append(angle * radius[chains.roots[j]])
            uv.append(chains.starts[j] + rel.dot(f.axis))
        halves[h].set_attribute(String(UV), BufferAttribute(uv^, 2))
    return merge(halves[0], halves[1])


def garment_uvs(
    piece: BufferGeometry, rig: HumanoidRig
) raises -> BufferGeometry:
    """Return a garment with texture coordinates in meters round its bones.

    The garment is cut into one part for each chain of bones: the part
    where that chain holds at least half of the skin's weight. What no
    chain holds by half is a last part, laid out round the chain that
    holds most of it. So no triangle mixes two chains. Each part is cut
    along a seam down the back of its bones.

    Args:
        piece: A garment with skin weights, in the pelvis frame.
        rig: The rig it was made on.

    Returns:
        The garment, with a `uv` attribute: the arc round the bone at its
        chain's mean radius, and the distance down the chain, in meters.

    Raises:
        Error: If the garment has no skin weights or a weight names no
            joint.
    """
    var chains = BoneChains(rig)
    var rest = piece.clone()
    var parts = List[BufferGeometry]()
    var owners = List[Int]()
    var done = False
    for root in range(JOINT_COUNT):  # pragma: no branch
        if done or chains.roots[root] != root:
            continue
        var shares = _chain_shares(rest, chains, root)
        var most = Float32(-1)
        var least = Float32(1)
        for share in shares:
            most = max(most, share)
            least = min(least, share)
        if most < 0:
            continue
        owners.append(root)
        if least >= 0:
            parts.append(rest.clone())
            done = True
            continue
        parts.append(cut(rest, shares, 0))
        for k in range(len(shares)):  # pragma: no branch
            shares[k] = -shares[k]
        rest = cut(rest, shares, 0)
    if not done:
        # What no chain holds by half follows the chain that holds most.
        var owner = 0
        var most = Float32(-1)
        for root in range(JOINT_COUNT):  # pragma: no branch
            if chains.roots[root] != root:
                continue
            var total = Float32(0)
            for share in _chain_shares(rest, chains, root):
                total += share + CHAIN_SHARE
            if total > most:
                owner = root
                most = total
        parts.append(rest^)
        owners.append(owner)
    # Each chain's mean radius, over the vertices its joints weigh most on.
    var radius = List[Float32](length=JOINT_COUNT, fill=0)
    var count = List[Int](length=JOINT_COUNT, fill=0)
    var heaviest = _joints_on(piece, chains, -1)
    ref placed = piece.attribute_view(String(POSITION))
    for v in range(placed.count()):
        var j = heaviest[v]
        ref f = chains.frames[j]
        var rel = placed.vector3(v) - rig.joints[j]
        radius[chains.roots[j]] += (rel - f.axis * rel.dot(f.axis)).length()
        count[chains.roots[j]] += 1
    for j in range(JOINT_COUNT):  # pragma: no branch
        if count[j] > 0:
            radius[j] /= Float32(count[j])
    var laid = _lay_out(parts[0], rig, chains, owners[0], radius)
    for p in range(1, len(parts)):
        laid = merge(laid, _lay_out(parts[p], rig, chains, owners[p], radius))
    return laid^
