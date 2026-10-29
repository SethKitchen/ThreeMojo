# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A garment made elsewhere, bound to one body and fitted to another.

An artist models a garment on one body, in a modeling program, and
exports it to glTF. `bind_garment` reads where each of its vertices
lies against that body's skin:

- the nearest point of the skin under it;
- the joint that weighs most at that point, and where the point stands
  from that joint, in statures;
- how far the vertex stands off the skin, along the skin's normal.

A new body has a skin of its own, with other vertices and triangles.
`fit_garment` therefore never reads the old skin's topology. For each
vertex it goes to the same place from the same joint of the new rig,
scaled to the new stature, finds the nearest point of the new skin,
and stands the vertex off it by the same distance. The vertex takes
the new skin's weights there. MakeHuman's `mhclo` files bind a garment
to body triangles the same way; this binding goes through the rig, so
it holds across bodies whose skins share no vertices.

This is not a three.js port. See Extensions.

    var binding = bind_garment(coat, skin, rig)
    var fitted = fit_garment(binding, coat, other_skin, other_rig)
    _ = wear_fitted(scene, assets, other, fitted^, look)
"""

from std.math import floor

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.scene import Scene
from extensions.humanoid.rig.game import GameHumanoid
from materials.material import MaterialId
from objects.skinned_mesh import SkinnedMesh, SKIN_INDEX, SKIN_WEIGHT
from extensions.attire.shell import SkinFrame
from extensions.humanoid.rig.joints import JOINT_COUNT, HumanoidRig, Joint
from math.triangle import Triangle
from math.vector3 import Vector3

comptime SKIN_CELL = Float32(0.05)
"""The side of one cell of the grid the skin's triangles are filed in, in
meters."""


@fieldwise_init
struct SkinPoint(ImplicitlyCopyable):
    """The nearest point of a skin to some point."""

    var triangle: Int
    """The skin triangle it lies on."""
    var point: Vector3
    """Where it is."""
    var weights: Vector3
    """Its barycentric weights on the triangle's three corners."""


struct SkinIndex(Movable):
    """A skin's triangles, filed in a grid so the nearest is found fast."""

    var corners: List[Int]
    """Three skin vertices per triangle."""
    var triangles: List[Triangle]
    """Each triangle's corners."""
    var cells: Dict[Int, List[Int]]
    """The triangles each cell's box meets."""
    var low: Vector3
    """The least corner of the skin's box."""
    var span: Int
    """The most cells along any side of the box."""

    def __init__(out self, skin: BufferGeometry) raises:
        """File a skin's triangles.

        Degenerate triangles are left out: they have no nearest point
        that is not also on a neighbor.

        Args:
            skin: A mesh with positions, indexed or not.

        Raises:
            Error: If the mesh has no positions or no triangle that is
                not degenerate.
        """
        ref placed = skin.attribute_view(String(POSITION))
        self.corners = List[Int]()
        self.triangles = List[Triangle]()
        self.cells = Dict[Int, List[Int]]()
        var low = Vector3(1e30, 1e30, 1e30)
        var high = Vector3(-1e30, -1e30, -1e30)
        for t in range(skin.triangle_count()):
            var ids = List[Int]()
            for c in range(3):  # pragma: no branch
                ids.append(skin.corner_index(t, c))
            var shape = Triangle(
                placed.vector3(ids[0]),
                placed.vector3(ids[1]),
                placed.vector3(ids[2]),
            )
            if shape.is_degenerate():
                continue
            for c in range(3):  # pragma: no branch
                self.corners.append(ids[c])
            self.triangles.append(shape)
            for p in [shape.a, shape.b, shape.c]:  # pragma: no branch
                low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
                high = Vector3(
                    max(high.x, p.x), max(high.y, p.y), max(high.z, p.z)
                )
        if len(self.triangles) == 0:
            raise Error("A skin to bind to needs a triangle")
        self.low = low
        var size = high - low
        self.span = Int(max(size.x, max(size.y, size.z)) / SKIN_CELL) + 2
        for t in range(len(self.triangles)):  # pragma: no branch
            ref shape = self.triangles[t]
            var a = self._cell(
                Vector3(
                    min(shape.a.x, min(shape.b.x, shape.c.x)),
                    min(shape.a.y, min(shape.b.y, shape.c.y)),
                    min(shape.a.z, min(shape.b.z, shape.c.z)),
                )
            )
            var b = self._cell(
                Vector3(
                    max(shape.a.x, max(shape.b.x, shape.c.x)),
                    max(shape.a.y, max(shape.b.y, shape.c.y)),
                    max(shape.a.z, max(shape.b.z, shape.c.z)),
                )
            )
            for i in range(a[0], b[0] + 1):  # pragma: no branch
                for j in range(a[1], b[1] + 1):  # pragma: no branch
                    for k in range(a[2], b[2] + 1):  # pragma: no branch
                        var key = self._key(i, j, k)
                        if key not in self.cells:
                            self.cells[key] = List[Int]()
                        self.cells[key].append(t)

    def _cell(self, p: Vector3) -> List[Int]:
        """Return the cell a point falls in, as three integers."""
        return [
            Int(floor((p.x - self.low.x) / SKIN_CELL)),
            Int(floor((p.y - self.low.y) / SKIN_CELL)),
            Int(floor((p.z - self.low.z) / SKIN_CELL)),
        ]

    def _key(self, i: Int, j: Int, k: Int) -> Int:
        """Return one integer for a cell, which may lie off the grid."""
        var n = self.span + 4096
        return ((i + 2048) * n + (j + 2048)) * n + (k + 2048)

    def nearest(self, p: Vector3) raises -> SkinPoint:
        """Return the point of the skin nearest `p`.

        Args:
            p: A point near the skin.

        Returns:
            The nearest point, its triangle and its weights.

        Raises:
            Error: If a triangle's weights cannot be found.
        """
        var home = self._cell(p)
        var best = -1
        var closest = Float32(1e30)
        var at = p
        var ring = 0
        while True:
            for di in range(-ring, ring + 1):  # pragma: no branch
                for dj in range(-ring, ring + 1):  # pragma: no branch
                    for dk in range(-ring, ring + 1):  # pragma: no branch
                        if max(abs(di), max(abs(dj), abs(dk))) != ring:
                            continue
                        var key = self._key(
                            home[0] + di, home[1] + dj, home[2] + dk
                        )
                        if key not in self.cells:
                            continue
                        for t in self.cells[key]:  # pragma: no branch
                            var q = self.triangles[t].closest_point_to_point(p)
                            var d = (q - p).length()
                            if d < closest:
                                closest = d
                                best = t
                                at = q
            # A triangle in a cell not yet searched is at least this far.
            if best >= 0 and closest <= Float32(ring) * SKIN_CELL:
                break
            ring += 1
        var weights = self.triangles[best].barycoord(at)
        return SkinPoint(best, at, weights)


struct Binding(Copyable, Movable):
    """Where each vertex of a garment lies against the body it was made
    on."""

    var joints: List[Joint]
    """Per vertex, the joint that weighs most where it meets the skin."""
    var places: List[Vector3]
    """Per vertex, where it meets the skin from that joint, in statures."""
    var offsets: List[Float32]
    """Per vertex, how far it stands off the skin, in meters."""

    def __init__(out self):
        """Bind nothing."""
        self.joints = List[Joint]()
        self.places = List[Vector3]()
        self.offsets = List[Float32]()

    def count(self) -> Int:
        """Return how many vertices are bound.

        Returns:
            The vertex count.
        """
        return len(self.joints)


def _blend_normal(frame: SkinFrame, index: SkinIndex, at: SkinPoint) -> Vector3:
    """Return the skin's interpolated unit normal at a point of it."""
    var n = Vector3(0, 0, 0)
    var w = at.weights
    var shares: List[Float32] = [w.x, w.y, w.z]
    for c in range(3):  # pragma: no branch
        var v = index.corners[3 * at.triangle + c]
        n = n + frame.normals[v] * shares[c]
    var length = n.length()
    if length <= 0:
        return frame.normals[index.corners[3 * at.triangle]]
    return n * (1 / length)


def _blend_bones(
    skin: BufferGeometry, index: SkinIndex, at: SkinPoint
) raises -> List[Float32]:
    """Return the skin's weight on each joint at a point of it."""
    ref bones = skin.attribute_view(String(SKIN_INDEX))
    ref weights = skin.attribute_view(String(SKIN_WEIGHT))
    var all = List[Float32](length=JOINT_COUNT, fill=0)
    var w = at.weights
    var shares: List[Float32] = [w.x, w.y, w.z]
    for c in range(3):  # pragma: no branch
        var v = index.corners[3 * at.triangle + c]
        for k in range(4):  # pragma: no branch
            var bone = Int(bones.component(v, k))
            if bone < 0 or bone >= JOINT_COUNT:
                raise Error("A skin weight names a bone the rig does not have")
            all[bone] += shares[c] * weights.component(v, k)
    return all^


def bind_garment(
    garment: BufferGeometry, skin: BufferGeometry, rig: HumanoidRig
) raises -> Binding:
    """Read where each vertex of a garment lies against a skin.

    Args:
        garment: The garment, in the skin's frame.
        skin: The skin it was made on, with skin weights.
        rig: The rig the skin is bound to.

    Returns:
        The binding.

    Raises:
        Error: If either mesh is malformed or the skin has no triangle.
    """
    var frame = SkinFrame(skin)
    var index = SkinIndex(skin)
    ref placed = garment.attribute_view(String(POSITION))
    var binding = Binding()
    for v in range(placed.count()):
        var p = placed.vector3(v)
        var at = index.nearest(p)
        var all = _blend_bones(skin, index, at)
        var joint = 0
        for j in range(1, JOINT_COUNT):  # pragma: no branch
            if all[j] > all[joint]:
                joint = j
        var normal = _blend_normal(frame, index, at)
        binding.joints.append(Joint(joint))
        binding.places.append(
            (at.point - rig.joints[joint]) * (1 / rig.stature)
        )
        binding.offsets.append((p - at.point).dot(normal))
    return binding^


def fit_garment(
    binding: Binding,
    garment: BufferGeometry,
    skin: BufferGeometry,
    rig: HumanoidRig,
) raises -> BufferGeometry:
    """Return a bound garment fitted to another body's skin.

    Args:
        binding: Where the garment lay on the body it was made on.
        garment: The garment, for its other attributes and triangles.
        skin: The new body's skin, with skin weights.
        rig: The new body's rig.

    Returns:
        The garment moved onto the new skin, with that skin's weights at
        each vertex and recomputed normals.

    Raises:
        Error: If the binding is not one entry per vertex of the
            garment, or either mesh is malformed.
    """
    if binding.count() != garment.vertex_count():
        raise Error("A binding needs one entry per vertex of the garment")
    var frame = SkinFrame(skin)
    var index = SkinIndex(skin)
    var flat = List[Float32](capacity=3 * binding.count())
    var bones = List[Float32](capacity=4 * binding.count())
    var weights = List[Float32](capacity=4 * binding.count())
    for v in range(binding.count()):
        var joint = binding.joints[v].value
        var target = rig.joints[joint] + binding.places[v] * rig.stature
        var at = index.nearest(target)
        var p = at.point + _blend_normal(frame, index, at) * binding.offsets[v]
        flat.append(p.x)
        flat.append(p.y)
        flat.append(p.z)
        var all = _blend_bones(skin, index, at)
        var chosen = List[Int]()
        var total = Float32(0)
        for _ in range(4):  # pragma: no branch
            var best = 0
            var heaviest = Float32(-1)
            for j in range(JOINT_COUNT):  # pragma: no branch
                if all[j] > heaviest and j not in chosen:
                    heaviest = all[j]
                    best = j
            chosen.append(best)
            total += all[best]
        for k in range(4):  # pragma: no branch
            bones.append(Float32(chosen[k]))
            weights.append(all[chosen[k]] / max(total, Float32(1e-30)))
    var fitted = garment.clone()
    fitted.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    fitted.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    fitted.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    fitted.compute_vertex_normals()
    return fitted^


def wear_fitted(
    mut scene: Scene,
    mut assets: Assets,
    person: GameHumanoid,
    var garment: BufferGeometry,
    look: MaterialId,
) raises -> Int:
    """Add a fitted garment to a person, as a skinned mesh on its skeleton.

    Args:
        scene: The scene the person is in.
        assets: The store of the person's geometry and materials.
        person: The person the garment was fitted to.
        garment: The fitted garment, with skin weights.
        look: The material to draw it with.

    Returns:
        The garment's index in the scene's skinned meshes.

    Raises:
        Error: If the person's body mesh is not in the scene.
    """
    ref body = scene.skinned_meshes[person.skins[0]]
    var skeleton = body.skeleton.copy()
    var bind = body.bind_matrix
    var at = len(scene.skinned_meshes)
    scene.add_skinned_mesh(
        SkinnedMesh(
            assets.geometries.add(garment^),
            look,
            person.root,
            skeleton^,
            bind,
        )
    )
    return at
