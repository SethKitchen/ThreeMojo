# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How much each joint turns each point of the skin.

Each bone of the rig is a segment, from its joint to where it ends, and
a thickness: about the radius of the body round it. A point of the skin
weighs each bone by how near it lies to the segment in that bone's own
thicknesses, to the sixth power, so a point is the nearest bone's and
the bones share it only near a joint. The four heaviest bones keep their
weights, which add up to one: the four a vertex of a skinned mesh can
carry.

Measuring in thicknesses lets the chest keep the side of the ribs,
although the thin upper arm lies nearer. A limb's bones weigh only the
points on their own side of the midline, so one thigh never pulls the
other.

This is not a three.js port. See Extensions.

    skin_weights(skin, rig)
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from extensions.humanoid.rig.joints import (
    HEAD,
    HIPS,
    LEFT_HAND,
    LEFT_TOES,
    LEFT_UPPER_ARM,
    RIGHT_HAND,
    RIGHT_THIGH,
    RIGHT_TOES,
    RIGHT_UPPER_ARM,
    JOINT_COUNT,
    HumanoidRig,
    Joint,
)
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT

# How thick each bone is, its radius on the six-foot template, in
# meters, in the order of the joints.
comptime THICKNESS: List[Float32] = [
    0.13,
    0.13,
    0.14,
    0.06,
    0.09,
    0.05,
    0.04,
    0.03,
    0.05,
    0.04,
    0.03,
    0.08,
    0.055,
    0.04,
    0.03,
    0.08,
    0.055,
    0.04,
    0.03,
]
# The power a nearness is raised to: the higher, the sharper each bend.
comptime SHARPNESS = 6
# How far past the midline a limb's bones still reach, in meters.
comptime MIDLINE = Float32(0.01)
# How far below the hips their bone starts, in meters on the template.
comptime HIPS_DROP = Float32(0.08)
# A vertex seeds its nearest bone when it lies within this many of the
# bone's thicknesses, and not within this fraction of either end.
comptime SEED_REACH = Float32(1.6)
comptime SEED_END = Float32(0.12)
# How far below the hips their bone still seeds the skin, in meters on
# the template.
comptime HIPS_SEED_DROP = Float32(0.03)
# How far a weight blends over the skin past the bone's own vertices,
# and how far over the skin a bone reaches at all, in meters on the
# template.
comptime BLEND = Float32(0.03)
comptime REACH = Float32(0.25)
# The template's stature, in meters.
comptime TEMPLATE_HEIGHT = Float32(1.8288)


def _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> Float32:
    """Return how far `p` lies from the segment from `a` to `b`."""
    var ab = b - a
    var t = Float32(0)
    var len2 = ab.dot(ab)
    if len2 > 0:
        t = min(Float32(1), max(Float32(0), (p - a).dot(ab) / len2))
    return (p - (a + ab * t)).length()


def bone_weights(rig: HumanoidRig, point: Vector3) -> List[Float32]:
    """Return how much each joint turns one point of the skin.

    Args:
        rig: The rig the skin is bound to.
        point: A point of the skin at rest, in the pelvis frame.

    Returns:
        One weight per joint, in the order of the joints, adding up to
        one.
    """
    var scale = rig.stature / TEMPLATE_HEIGHT
    var thickness = materialize[THICKNESS]()
    var weights = List[Float32](length=JOINT_COUNT, fill=0)
    var total = Float32(0)
    for j in range(JOINT_COUNT):  # pragma: no branch
        var side = Float32(Joint(j).side())
        if side * point.x < -MIDLINE:
            continue
        var start = rig.joints[j]
        if j == HIPS.value:
            start = start - Vector3(0, HIPS_DROP * scale, 0)
        var d = _segment_distance(point, start, rig.ends[j]) / (
            thickness[j] * scale
        )
        var w = 1 / (d**SHARPNESS + Float32(1e-6))
        weights[j] = w
        total += w
    for j in range(JOINT_COUNT):  # pragma: no branch
        weights[j] /= total
    return weights^


def _ends_chain(joint: Joint) -> Bool:
    """Return True for a joint no other joint hangs from."""
    return (
        joint == HEAD
        or joint == RIGHT_HAND
        or joint == LEFT_HAND
        or joint == RIGHT_TOES
        or joint == LEFT_TOES
    )


struct _Heap(Movable):
    """A binary heap of vertices by distance, nearest first."""

    var keys: List[Float32]
    var items: List[Int]

    def __init__(out self):
        """Start empty."""
        self.keys = List[Float32]()
        self.items = List[Int]()

    def push(mut self, key: Float32, item: Int):
        """Add an item."""
        self.keys.append(key)
        self.items.append(item)
        var i = len(self.keys) - 1
        while i > 0:
            var up = (i - 1) // 2
            if self.keys[up] <= self.keys[i]:
                break
            self.keys.swap_elements(up, i)
            self.items.swap_elements(up, i)
            i = up

    def pop(mut self) -> Tuple[Float32, Int]:
        """Remove and return the nearest item."""
        var top = (self.keys[0], self.items[0])
        var last = len(self.keys) - 1
        self.keys[0] = self.keys[last]
        self.items[0] = self.items[last]
        _ = self.keys.pop()
        _ = self.items.pop()
        var i = 0
        var n = len(self.keys)
        while True:
            var a = 2 * i + 1
            var b = a + 1
            var m = i
            if a < n and self.keys[a] < self.keys[m]:
                m = a
            if b < n and self.keys[b] < self.keys[m]:
                m = b
            if m == i:
                break
            self.keys.swap_elements(m, i)
            self.items.swap_elements(m, i)
            i = m
        return top


def _welded_edges(
    points: List[Vector3], triangles: List[Int]
) raises -> Tuple[List[Int], List[List[Int]]]:
    """Return each vertex's welded vertex, the first at the same place,
    and each welded vertex's neighbors along the triangles' edges."""
    var count = len(points)
    var first = Dict[Int, List[Int]]()
    var weld = List[Int](capacity=count)
    for v in range(count):  # pragma: no branch
        var p = points[v]
        var px = Int(p.x * 1e5)
        var py = Int(p.y * 1e5)
        var pz = Int(p.z * 1e5)
        var key = ((px * 1000003) ^ (py * 999983)) ^ pz
        # The hash selects a bucket, not a position: distinct coordinates
        # can have the same XOR. Only equal quantized coordinates weld.
        if key not in first:
            first[key] = List[Int]()
        var same = -1
        for candidate in first[key]:
            var q = points[candidate]
            if (
                px == Int(q.x * 1e5)
                # Equal hash, x and y imply equal z: XOR is invertible.
                and py == Int(q.y * 1e5)
            ):
                same = candidate
                break
        if same < 0:
            same = v
            first[key].append(v)
        weld.append(same)
    var near = List[List[Int]](length=count, fill=List[Int]())
    for t in range(0, len(triangles) - 2, 3):  # pragma: no branch
        for c in range(3):  # pragma: no branch
            var a = weld[triangles[t + c]]
            var b = weld[triangles[t + (c + 1) % 3]]
            if a != b and b not in near[a]:
                near[a].append(b)
                near[b].append(a)
    return (weld^, near^)


def _largest_patch(
    seeds: List[Int], near: List[List[Int]], count: Int
) -> List[Int]:
    """Return the largest set of `seeds` joined to one another along the
    skin's edges."""
    var mine = List[Bool](length=count, fill=False)
    for v in seeds:  # pragma: no branch
        mine[v] = True
    var seen = List[Bool](length=count, fill=False)
    var best = List[Int]()
    for start in seeds:  # pragma: no branch
        if seen[start]:
            continue
        var patch = List[Int]()
        var stack: List[Int] = [start]
        seen[start] = True
        while len(stack) > 0:
            var v = stack.pop()
            patch.append(v)
            for u in near[v]:  # pragma: no branch
                if mine[u] and not seen[u]:
                    seen[u] = True
                    stack.append(u)
        if len(patch) > len(best):
            best = patch^
    return best^


def skin_weights(
    mut skin: BufferGeometry,
    rig: HumanoidRig,
    joints: List[Joint] = List[Joint](),
) raises:
    """Give a skin the joints that turn it: `skinIndex` and `skinWeight`,
    four of each per vertex.

    Distance is measured over the skin, not through the air, so a part
    is only turned by the bones it joins through the skin. Each bone is
    first given the vertices round its middle that lie nearest it, in
    its own thicknesses. From those, the nearness of every other vertex
    spreads along the triangles' edges. A vertex weighs each bone by the
    inverse fourth power of that distance over the skin plus a blend of
    a few centimeters, so the weights change smoothly across a joint.
    A part no bone reaches over the skin falls back on the nearest bone
    through the air.

    Args:
        skin: The skin at rest, in the pelvis frame.
        rig: The rig it is bound to.
        joints: The joints that may turn it, or every joint if empty.

    Raises:
        Error: If the skin has no positions, or a joint is not named.
    """
    var allowed = List[Bool](length=JOINT_COUNT, fill=len(joints) == 0)
    for j in joints:  # pragma: no branch
        if not j.is_valid():
            raise Error("A joint must be a named joint")
        allowed[j.value] = True
    ref placed = skin.attribute_view(String(POSITION))
    var count = placed.count()
    var points = List[Vector3](capacity=count)
    for v in range(count):  # pragma: no branch
        points.append(placed.vector3(v))
    var triangles = skin.index.copy()
    if len(triangles) == 0:
        for v in range(count - count % 3):  # pragma: no branch
            triangles.append(v)
    var graph = _welded_edges(points, triangles)
    ref weld = graph[0]
    ref near = graph[1]
    var scale = rig.stature / TEMPLATE_HEIGHT
    var thickness = materialize[THICKNESS]()
    # Each vertex's nearest allowed bone through the air, in thicknesses,
    # and whether it lies by the bone's middle.
    var seeds = List[List[Int]](length=JOINT_COUNT, fill=List[Int]())
    for v in range(count):  # pragma: no branch
        if weld[v] != v:
            continue
        var p = points[v]
        var best = -1
        var nearest = Float32(1e30)
        for j in range(JOINT_COUNT):  # pragma: no branch
            if not allowed[j]:
                continue
            var side = Float32(Joint(j).side())
            if side * p.x < -MIDLINE:
                continue
            var a = rig.joints[j]
            if j == HIPS.value:
                a = a - Vector3(0, HIPS_DROP * scale, 0)
            var ab = rig.ends[j] - a
            var t = Float32(0)
            var len2 = ab.dot(ab)
            if len2 > 0:
                t = min(Float32(1), max(Float32(0), (p - a).dot(ab) / len2))
            # Only a bone the vertex lies beside the middle of competes:
            # by a joint, the bones on either side share it later. A bone
            # that ends a chain, as the head, a hand or the toes, keeps
            # the vertices out to its tip.
            if t <= SEED_END or (
                t >= 1 - SEED_END and not _ends_chain(Joint(j))
            ):
                continue
            # The hips keep the pelvis above the buttocks' fold; the
            # thighs take the skin below it.
            if j == HIPS.value and p.y < rig.joints[HIPS.value].y - (
                HIPS_SEED_DROP * scale
            ):
                continue
            var d = (p - (a + ab * t)).length() / (thickness[j] * scale)
            if d < nearest:
                nearest = d
                best = j
        if best >= 0 and nearest < SEED_REACH:
            seeds[best].append(v)
    # A bone keeps only its largest patch of seeds over the skin: a
    # patch apart from it lies on another part that happens to be near,
    # as the thigh beside a hanging hand.
    for j in range(JOINT_COUNT):  # pragma: no branch
        if len(seeds[j]) > 0:
            seeds[j] = _largest_patch(seeds[j], near, count)
    var blend = BLEND * scale
    var weights = List[List[Float32]](length=count, fill=List[Float32]())
    for v in range(count):  # pragma: no branch
        weights[v] = List[Float32](length=JOINT_COUNT, fill=0)
    for j in range(JOINT_COUNT):  # pragma: no branch
        if len(seeds[j]) == 0:
            continue
        var far = List[Float32](length=count, fill=Float32(1e30))
        var heap = _Heap()
        for v in seeds[j]:  # pragma: no branch
            far[v] = 0
            heap.push(0, v)
        while len(heap.keys) > 0:
            var top = heap.pop()
            var v = top[1]
            if top[0] > far[v]:
                continue
            if top[0] > REACH * scale:
                break
            for u in near[v]:  # pragma: no branch
                var d = top[0] + (points[u] - points[v]).length()
                if d < far[u]:
                    far[u] = d
                    heap.push(d, u)
        var side = Float32(Joint(j).side())
        for v in range(count):  # pragma: no branch
            var g = far[weld[v]]
            # The thighs touch, so over the skin one leg's nearness
            # reaches the other's; a limb never turns the far side.
            if side * points[v].x < -MIDLINE:
                continue
            if g < Float32(1e29):
                var r = 1 / (g + blend)
                weights[v][j] = r * r * r * r
    var indices = List[Float32](capacity=4 * count)
    var kept_weights = List[Float32](capacity=4 * count)
    for v in range(count):  # pragma: no branch
        var all = weights[v].copy()
        var total = Float32(0)
        for j in range(JOINT_COUNT):  # pragma: no branch
            total += all[j]
        if total <= 0:
            # Out of reach of every bone over the skin: the nearest
            # through the air.
            all = bone_weights(rig, points[v])
            for j in range(JOINT_COUNT):  # pragma: no branch
                if not allowed[j]:
                    all[j] = 0
        var kept = Float32(0)
        var chosen = List[Int]()
        for _ in range(4):  # pragma: no branch
            var best = 0
            var heaviest = Float32(-1)
            for j in range(JOINT_COUNT):  # pragma: no branch
                if all[j] > heaviest and j not in chosen:
                    heaviest = all[j]
                    best = j
            chosen.append(best)
            kept += all[best]
        for k in range(4):  # pragma: no branch
            indices.append(Float32(chosen[k]))
            kept_weights.append(all[chosen[k]] / max(kept, Float32(1e-30)))
    skin.set_attribute(String(SKIN_INDEX), BufferAttribute(indices^, 4))
    skin.set_attribute(String(SKIN_WEIGHT), BufferAttribute(kept_weights^, 4))


def rigid_weights(mut part: BufferGeometry, joint: Joint) raises:
    """Bind every vertex of a part wholly to one joint, as the eyes and
    the hair are to the head.

    Args:
        part: A mesh with positions.
        joint: A named joint.

    Raises:
        Error: If the part has no positions or `joint` is not named.
    """
    if not joint.is_valid():
        raise Error("A joint must be a named joint")
    var count = part.attribute_view(String(POSITION)).count()
    var indices = List[Float32](capacity=4 * count)
    var weights = List[Float32](capacity=4 * count)
    for _ in range(count):  # pragma: no branch
        indices.append(Float32(joint.value))
        indices.append(0)
        indices.append(0)
        indices.append(0)
        weights.append(1)
        weights.append(0)
        weights.append(0)
        weights.append(0)
    part.set_attribute(String(SKIN_INDEX), BufferAttribute(indices^, 4))
    part.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))


def _mirror(joint: Int) -> Int:
    """Return the same joint on the other side, or the joint itself on
    the midline."""
    var mirrored: List[Int] = [
        0,
        1,
        2,
        3,
        4,
        8,
        9,
        10,
        5,
        6,
        7,
        15,
        16,
        17,
        18,
        11,
        12,
        13,
        14,
    ]
    return mirrored[joint]


def part_legs(mut skin: BufferGeometry, crotch: Float32) raises:
    """Part the legs where the skin joins them, below the crotch.

    The thighs touch, so the skin over them is one surface: as the legs
    swing apart, its triangles between them would stretch into a web.
    Below `crotch`, each triangle that spans the midline is given to the
    leg its middle lies on. Its corners on the other side are copied,
    and each copy is turned by the joints of the leg it now belongs to.
    So each leg keeps its own triangles, and a slit opens between them.
    A copy's joints of the other leg become the same joints of its own.

    Args:
        skin: An indexed skin with `skinIndex` and `skinWeight`.
        crotch: The height below which the legs are parted, in meters.

    Raises:
        Error: If the skin has no positions or no skin attributes.
    """
    ref placed = skin.attribute_view(String(POSITION))
    var count = placed.count()
    var positions = skin.clone_attribute(String(POSITION)).data.copy()
    var bones = skin.clone_attribute(String(SKIN_INDEX)).data.copy()
    var weights = skin.clone_attribute(String(SKIN_WEIGHT)).data.copy()
    var others = List[String]()
    for name in [
        String("normal"),
        String("uv"),
        String("color"),
        String("thinness"),
    ]:  # pragma: no branch
        if skin.has_attribute(name):
            others.append(name)
    var extra = List[List[Float32]]()
    var sizes = List[Int]()
    for name in others:  # pragma: no branch
        var a = skin.clone_attribute(name)
        sizes.append(a.item_size)
        extra.append(a.data.copy())
    var index = skin.index.copy()
    # The copy of each vertex made for each side, once it is made.
    var copies = Dict[Int, Int]()
    for t in range(0, len(index) - 2, 3):  # pragma: no branch
        var middle = Vector3(0, 0, 0)
        var right = 0
        var left = 0
        for c in range(3):  # pragma: no branch
            var p = placed.vector3(index[t + c])
            middle = middle + p / 3
            if p.x > 0:
                right += 1
            elif p.x < 0:
                left += 1
        if middle.y >= crotch or right == 0 or left == 0:
            continue
        var sign = Float32(1) if middle.x >= 0 else Float32(-1)
        for c in range(3):  # pragma: no branch
            var v = index[t + c]
            if placed.vector3(v).x * sign >= 0:
                continue
            var key = v * 2 + (0 if sign > 0 else 1)
            var copy = copies.get(key, -1)
            if copy < 0:
                copy = len(positions) // 3
                for k in range(3):  # pragma: no branch
                    positions.append(positions[v * 3 + k])
                for k in range(4):  # pragma: no branch
                    var joint = Int(bones[v * 4 + k])
                    # A joint of the other leg becomes this leg's.
                    if Float32(Joint(joint).side()) * sign < 0:
                        joint = _mirror(joint)
                    bones.append(Float32(joint))
                    weights.append(weights[v * 4 + k])
                for n in range(len(extra)):  # pragma: no branch
                    for k in range(sizes[n]):  # pragma: no branch
                        extra[n].append(extra[n][v * sizes[n] + k])
                copies[key] = copy
            index[t + c] = copy
    _ = count
    skin.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    skin.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    skin.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    for n in range(len(others)):  # pragma: no branch
        skin.set_attribute(
            others[n], BufferAttribute(extra[n].copy(), sizes[n])
        )
    skin.set_index(index^)
